#Written by Keith Jolley
#Copyright (c) 2010-2023, University of Oxford
#E-mail: keith.jolley@zoo.ox.ac.uk
#
#This file is part of Bacterial Isolate Genome Sequence Database (BIGSdb).
#
#BIGSdb is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#BIGSdb is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
package BIGSdb::CurateBatchAddPage;
use strict;
use warnings;
use 5.010;
use Digest::MD5 qw(md5);
use List::MoreUtils qw(any none uniq);
use parent qw(BIGSdb::CurateAddPage);
use Log::Log4perl qw(get_logger);
use Bio::Tools::CodonTable;
use BIGSdb::Constants qw(:submissions :interface :limits);
use BIGSdb::Utils;
use BIGSdb::Offline::BatchUploader;
use File::Type;
use Try::Tiny;
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self)        = @_;
	my $q             = $self->{'cgi'};
	my $table         = $q->param('table') // q();
	my $cleaned_table = $table;
	my $locus         = $q->param('locus');
	$cleaned_table =~ tr/_/ /;
	if ( !$self->{'datastore'}->is_table($table) ) {
		say q(<h1>Batch insert records</h1>);
		$self->print_bad_status( { message => qq(Table $table does not exist!) } );
		return;
	}
	say qq(<h1>Batch insert $cleaned_table</h1>);
	if ( !$self->can_modify_table($table) ) {
		$self->print_bad_status(
			{
				message => qq(Your user account is not allowed to add records to the $table table.),
			}
		);
		return;
	}
	my %table_message = (
		sequence_bin     => 'You cannot use this interface to add sequences to the bin.',
		allele_sequences => 'Tag allele sequences using the scan interface.',
		sequences        => 'You cannot use this interface to add new sequence definitions.'
	);
	if ( $table_message{$table} ) {
		$self->print_bad_status( { message => $table_message{$table} } );
		return;
	}
	my %modify_warning = map { $_ => 1 } qw (scheme_fields scheme_members);
	if (   $modify_warning{$table}
		&& $self->{'system'}->{'dbtype'} eq 'sequences'
		&& !$q->param('data')
		&& !$q->param('checked_buffer') )
	{
		say q(<div class="box" id="warning"><p>Please be aware that any modifications to the structure )
		  . q(of a scheme will result in the removal of all data from it. This is done to ensure data )
		  . q(integrity.  This does not affect allele designations, but any profiles will have to be )
		  . q(reloaded.</p></div>);
	}
	my ( $uses_integer_id, $has_sender_field );
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		( $uses_integer_id, $has_sender_field ) = ( 1, 1 );
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		foreach my $att (@$attributes) {
			if ( $att->{'name'} eq 'id' && $att->{'type'} eq 'int' ) {
				$uses_integer_id = 1;
			} elsif ( $att->{'name'} eq 'sender' ) {
				$has_sender_field = 1;
			}
		}
	}
	my $args =
	  { table => $table, uses_integer_id => $uses_integer_id, has_sender_field => $has_sender_field, locus => $locus };
	if ( $q->param('datatype') && $q->param('list_file') ) {
		$self->{'datastore'}->create_temp_list_table( scalar $q->param('datatype'), scalar $q->param('list_file') );
	}
	if ( $q->param('query_file') && !defined $q->param('query') ) {
		my $query_file = $q->param('query_file');
		my $query      = $self->get_query_from_temp_file($query_file);
		$q->param( query => $query );
	}
	if ( $q->param('checked_buffer') ) {
		$self->_upload_data($args);
	} elsif ( $q->param('data') || $q->param('query') ) {
		$self->_check_data($args);
	} else {
		if ( $q->param('submission_id') ) {
			$self->_set_submission_params( scalar $q->param('submission_id') );
		}
		$self->_print_interface($args);
	}
	return;
}

sub _print_interface {
	my ( $self, $arg_ref ) = @_;
	my $table       = $arg_ref->{'table'};
	my $record_name = $self->get_record_name($table);
	my $q           = $self->{'cgi'};
	$q->param( private => 1 ) if $self->{'permissions'}->{'only_private'};
	my $options = {};
	if ( $table eq 'isolates' ) {
		$options->{$_} = scalar $q->param($_) foreach qw(private user_header project_id);
		return
		  if $self->_cannot_upload_private_data( scalar $q->param('private'), scalar $q->param('project_id') );
	}
	say q(<div class="box" id="queryform"><div class="scrollable">);
	my $icon = $self->get_form_icon( $table, 'plus' );
	say $icon;
	say q(<h2>Instructions</h2>)
	  . qq(<p>This page allows you to upload $record_name )
	  . q(data as tab-delimited text or copied from a spreadsheet.</p>);
	say q(<ul><li>Field header names must be included and fields can be in any order. Optional fields can be )
	  . q(omitted if you wish.</li>);
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		say q[<li>Optionally enter aliases (alternative names) for your isolates as a semi-colon (;) ]
		  . q[separated list.</li>];
		say q[<li>Optionally enter references for your isolates as a semi-colon (;) separated list of ]
		  . q[PubMed ids (non-integer ids will be ignored).</li>];
		my $eav_fields = $self->{'datastore'}->get_eav_fields;
		if ( @$eav_fields && @$eav_fields > MAX_EAV_FIELD_LIST ) {
			my $field_name = $self->{'system'}->{'eav_fields'} // 'secondary metadata';
			say qq[<li>You can add new columns for $field_name - there are too many to include by default ]
			  . qq[(see the '$field_name' tab in the Excel template for allowed field names).];
		}
		say q[<li>You can also upload allele fields along with the other isolate data - simply create a new column ]
		  . q[with the locus name (see the 'allowed_loci' tab in the Excel template for locus names). These will be ]
		  . q[added with a confirmed status and method set as 'manual'.</li>];
	}
	if ( $table eq 'loci' && $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say q(<li>Enter aliases (alternative names) for your locus as a semi-colon (;) separated list.</li>);
	}
	if ( $arg_ref->{'uses_integer_id'} ) {
		say q(<li>You can choose whether or not to include an id number field - if it is omitted, the next )
		  . q(available id will be used automatically.</li>);
	}
	say q(</ul>);
	say q(<h2>Templates</h2>);
	my $order_clause = $table eq 'isolates' ? q(&amp;order=scheme) : q();
	my ( $text, $excel ) = ( TEXT_FILE, EXCEL_FILE );
	say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=tableHeader&amp;table=$table$order_clause" title="Tab-delimited text header">$text</a>)
	  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=excelTemplate&amp;table=$table)
	  . qq($order_clause" title="Excel format">$excel</a></p>);
	my $plugins = $self->{'pluginManager'}->get_installed_plugins;
	if ( $plugins->{'DatabaseFields'} && $table eq 'isolates' ) {
		say qq(<p>Check the <a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;)
		  . q(name=DatabaseFields" target="_blank">description of database fields</a> for help with filling in )
		  . q(the template.</p>);
	}
	say q(<h2>Upload</h2>);
	say $q->start_form;
	if ( $arg_ref->{'has_sender_field'} ) {
		$self->print_interface_sender_field;
	}
	say q(<fieldset style="float:left"><legend>Paste in tab-delimited text )
	  . q((<strong>include a field header as the first line</strong>).</legend>);
	say $q->textarea( -name => 'data', -rows => 20, -columns => 80 );
	say q(</fieldset>);
	say $q->hidden($_) foreach qw (page db table locus submission_id private project_id user_header);
	$self->print_action_fieldset( { table => $table, %$options } );
	say $q->end_form;
	my $script = $q->param('user_header') ? $self->{'system'}->{'query_script'} : $self->{'system'}->{'script_name'};
	say q(</div></div>);
	return;
}

sub _get_private_project_id {
	my ($self) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'isolates';
	my $q          = $self->{'cgi'};
	my $project_id = $q->param('project_id');
	if ( BIGSdb::Utils::is_int($project_id) ) {
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		my $is_project_user =
		  $self->{'datastore'}
		  ->run_query( 'SELECT EXISTS(SELECT * FROM merged_project_users WHERE (project_id,user_id)=(?,?) AND modify)',
			[ $project_id, $user_info->{'id'} ] );
		return $project_id if $is_project_user;
	}
	return;
}

sub _is_private_record {
	my ($self) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'isolates';
	my $q = $self->{'cgi'};
	return if !$q->param('private');
	my $user_info       = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $limit           = $self->{'datastore'}->get_user_private_isolate_limit( $user_info->{'id'} );
	my $private_project = $self->_get_private_project_id;
	if ($private_project) {
		my $project_info = $self->{'datastore'}
		  ->run_query( 'SELECT * FROM projects WHERE id=?', $private_project, { fetch => 'row_hashref' } );
		return 1 if $project_info->{'no_quota'};
	}
	return 1 if $limit;
	return;
}

sub _cannot_upload_private_data {
	my ( $self, $private, $project_id, $options ) = @_;
	return if !$private;
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $limit     = $self->{'datastore'}->get_user_private_isolate_limit( $user_info->{'id'} );
	my $available = $self->{'datastore'}->get_available_quota( $user_info->{'id'} );
	my $project;
	if ($project_id) {
		if ( !BIGSdb::Utils::is_int($project_id) ) {
			$self->print_bad_status( { message => q(Invalid project id selected.) } );
			return 1;
		}
		$project =
		  $self->{'datastore'}->run_query( 'SELECT short_description,no_quota,curate_config FROM projects WHERE id=?',
			$project_id, { fetch => 'row_hashref' } );
		if ( !$project ) {
			$self->print_bad_status( { message => q(Invalid project id selected.) } );
			return 1;
		}
		my $is_project_user =
		  $self->{'datastore'}
		  ->run_query( 'SELECT EXISTS(SELECT * FROM merged_project_users WHERE (project_id,user_id)=(?,?) AND modify)',
			[ $project_id, $user_info->{'id'} ] );
		if ( !$is_project_user ) {
			$self->print_bad_status(
				{
					message => q(Your account has insufficient privileges to upload to the )
					  . qq($project->{'short_description'} project.),
				}
			);
			return 1;
		}
		if ( !$project->{'no_quota'} && !$limit ) {
			$self->print_bad_status( { message => q(Your account cannot upload private data.) } );
			return 1;
		}
		if ( $project->{'curate_config'} && $project->{'curate_config'} ne $self->{'instance'} ) {
			$self->print_bad_status(
				{
					message => q(You cannot upload to this project using the current database configuration )
					  . qq("$self->{'instance'}". You must use the "$project->{'curate_config'}" configuration.)
				}
			);
			return 1;
		}
	} elsif ( !$limit ) {
		$self->print_bad_status( { message => q(Your account cannot upload private data.) } );
		return 1;
	}
	if ( !$options->{'no_message'} ) {
		say q(<div class="box resultspanel">);
		say q(<span class="main_icon fas fa-lock fa-3x fa-pull-left"></span>);
		say q(<h2>Private data upload</h2>);
		if ($project) {
			say q(<p>These isolates will be added to the private )
			  . qq(<strong>$project->{'short_description'}</strong> project.</p>);
			if ( $project->{'no_quota'} ) {
				say q(<p>These will not count against your quota of private data.</p>) if $limit;
			} else {
				say q(<p>These will count against your quota of private data.</p>);
				say qq(<p>Quota available: $available</p>);
			}
		} else {
			say q(<p>These isolates will count against your quota of private data.</p>);
			say qq(<p>Quota available: $available</p>);
		}
		say q(</div>);
	}
	return;
}

sub print_interface_sender_field {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	if ( $user_info->{'status'} eq 'submitter' || $q->param('private') ) {
		say $q->hidden( sender => $user_info->{'id'} );
		return;
	}
	my ( $users, $user_names ) = $self->{'datastore'}->get_users( { blank_message => 'Select sender ...' } );
	say q(<div style="margin-bottom:1em"><p>Please select the sender from the list below:</p>);
	$user_names->{-1} = 'Override with sender field';
	say $q->popup_menu(
		-name     => 'sender',
		-values   => [ '', -1, @$users ],
		-labels   => $user_names,
		-required => 'required'
	);
	say q(<span class="comment"> Value will be overridden if you include a sender field in your pasted data.</span>);
	say q(</div>);
	return;
}

sub get_sender_message {
	my ( $self, $args ) = @_;
	my $sender_message = q();
	my $q              = $self->{'cgi'};
	if ( $args->{'has_sender_field'} ) {
		my $sender = $q->param('sender');
		if ( $sender == -1 ) {
			$sender_message = qq(<p>Using sender field in pasted data.</p>\n);
		} else {
			my $sender_info = $self->{'datastore'}->get_user_info($sender);
			if ( !$sender_info ) {
				$sender_message = qq(<p>Sender: Unknown</p>\n);
			} else {
				$sender_message = qq(<p>Sender: $sender_info->{'first_name'} $sender_info->{'surname'}</p>\n);
			}
		}
	}
	return $sender_message;
}

sub sender_needed {
	my ( $self, $args ) = @_;
	if ( $args->{'has_sender_field'} ) {
		my $q      = $self->{'cgi'};
		my $sender = $q->param('sender');
		if ( !BIGSdb::Utils::is_int($sender) ) {
			$self->print_bad_status(
				{
					message => q(Please go back and select the sender for this submission.)
				}
			);
			return 1;
		}
	}
	return;
}

sub get_file_header_data {
	my ( $self, $records ) = @_;
	my $header;
	while ( $header = shift @$records ) {    #ignore blank lines before header
		$header =~ s/\r//gx;
		last if $header ne q();
	}
	my @file_header_fields = split /\t/x, $header;
	my %file_header_pos;
	my $pos = 0;
	foreach my $field (@file_header_fields) {
		$field =~ s/^\s+|\s+$//gx;    #Remove trailing spaces from header fields
		$file_header_pos{$field} = $pos;
		$pos++;
	}
	return ( \@file_header_fields, \%file_header_pos );
}

sub _get_id {
	my ( $self, $table ) = @_;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		return $self->next_id($table);
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		foreach my $att (@$attributes) {
			if ( $att->{'name'} eq 'id' && $att->{'type'} eq 'int' ) {
				return $self->next_id($table);
			}
		}
	}
	return;
}

sub _get_unique_fields {
	my ( $self, $table ) = @_;
	my %unique_field;
	if ( !( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) ) {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		foreach my $att (@$attributes) {
			if ( $att->{'unique'} ) {
				$unique_field{ $att->{'name'} } = 1;
			}
		}
	}
	return \%unique_field;
}

sub _increment_id {
	my ( $self, $table, $id_pos_defined, $integer_id, $first_record, $id_ref ) = @_;
	if ( !$id_pos_defined && $integer_id && !$first_record ) {
		do { $$id_ref++ } while ( $self->_is_id_used( $table, $$id_ref ) );
	}
	return;
}

sub _check_data {
	my ( $self,  $args )  = @_;
	my ( $table, $locus ) = @{$args}{qw (table locus)};
	my $q = $self->{'cgi'};
	if ( !$q->param('data') ) {
		$q->param( 'data', $self->_convert_query( scalar $q->param('table'), scalar $q->param('query') ) );
	}
	my @checked_buffer;
	my $fields = $self->_get_fields_in_order( $table, $locus );
	my %last_id;
	return if $self->sender_needed($args);
	my $sender_message = $self->get_sender_message($args);
	my $problems       = {};
	my $advisories     = {};
	my $table_header   = $self->_get_field_table_header($table);
	my $tablebuffer    = qq(<div class="scrollable"><table class="resultstable"><tr>$table_header</tr>);
	my @records        = split /\n/x, $q->param('data');
	my $td             = 1;
	my ( $file_header_fields, $file_header_pos ) = $self->get_file_header_data( \@records );
	my $id           = $self->_get_id($table);
	my $unique_field = $self->_get_unique_fields($table);
	my @primary_keys = $self->{'datastore'}->get_primary_keys($table);
	my ( %locus_format, %locus_regex, $header_row, $header_complete, $record_count );
	my $first_record = 1;
  RECORD: foreach my $record (@records) {
		$record =~ s/\r//gx;
		next if $record =~ /^\s*$/x;
		my $checked_record;
		if ($record) {
			my @data = split /\t/x, $record;
			BIGSdb::Utils::remove_trailing_spaces_from_list( \@data );
			my $first = 1;
			$self->_increment_id(
				$table,
				defined $file_header_pos->{'id'},
				$args->{'uses_integer_id'},
				$first_record, \$id
			);
			my ( $pk_combination, $pk_values_ref ) = $self->_get_primary_key_values(
				{
					primary_keys    => \@primary_keys,
					file_header_pos => $file_header_pos,
					id              => $id,
					locus           => $locus,
					table           => $table,
					first           => \$first,
					data            => \@data,
					record_count    => \$record_count
				}
			);
			my $rowbuffer;
			my $continue = 1;
		  FIELD: foreach my $field (@$fields) {

				#Prepare checked header
				if ( !$header_complete && ( defined $file_header_pos->{$field} || $field eq 'id' ) ) {
					$header_row .= "$field\t";
				}

				#Check individual values for correctness.
				my $value = $self->extract_value(
					{
						field           => $field,
						data            => \@data,
						id              => $id,
						file_header_pos => $file_header_pos,
					}
				);
				my $special_problem;
				my $new_args = {
					locus           => $locus,
					field           => $field,
					value           => \$value,
					file_header_pos => $file_header_pos,
					data            => \@data,
					pk_combination  => $pk_combination,
					problems        => $problems,
					special_problem => \$special_problem,
					continue        => \$continue,
					last_id         => \%last_id,
					unique_field    => $unique_field,
					advisories      => $advisories,
				};
				$self->check_data_duplicates($new_args);
				$self->_run_table_specific_field_checks( $table, $new_args );
				$pk_combination = $new_args->{'pk_combination'} // $pk_combination;

				#Display field - highlight in red if invalid.
				$rowbuffer .= $self->format_display_value(
					{
						table           => $table,
						field           => $field,
						value           => $value,
						problems        => $problems,
						pk_combination  => $pk_combination,
						special_problem => $special_problem
					}
				);
				$value //= q();
				$self->_run_table_specific_reformatting( $table, $new_args );
				if ( defined $file_header_pos->{$field} || ( $field eq 'id' ) ) {
					$checked_record .= qq($value\t);
				}
			}
			if ( !$continue ) {
				undef $header_row if $first_record;
				next;
			}
			my $row_buffer = qq(<tr class="td$td">$rowbuffer);
			my $new_args   = {
				file_header_fields => $file_header_fields,
				header_row         => \$header_row,
				first_record       => $first_record,
				file_header_pos    => $file_header_pos,
				data               => \@data,
				locus_format       => \%locus_format,
				locus_regex        => \%locus_regex,
				primary_keys       => \@primary_keys,
				pk_combination     => $pk_combination,
				pk_values          => $pk_values_ref,
				problems           => $problems,
				advisories         => $advisories,
				checked_record     => \$checked_record,
				table              => $table
			};
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
				my %newdata             = map { $_ => $data[ $file_header_pos->{$_} ] } keys %$file_header_pos;
				my $validation_failures = $self->{'submissionHandler'}->run_validation_checks( \%newdata );
				if (@$validation_failures) {
					foreach my $failure (@$validation_failures) {
						$failure =~ s/\.?\s*$/. /x;
						$problems->{$pk_combination} .= $failure;
					}
				}
				$row_buffer .= $self->_isolate_record_further_checks( $table, $new_args, $advisories, $pk_combination );
			}
			$header_complete = 1;
			push @checked_buffer, $header_row if $first_record;
			$first_record = 0;
			$row_buffer .= qq(</tr>\n);

			#Check for various invalid combinations of fields
			if ( !$problems->{$pk_combination} ) {
				my $skip_record = 0;
				try {
					$self->_check_data_primary_key($new_args);
				} catch {
					if ( $_->isa('BIGSdb::Exception::Data::Warning') ) {
						$skip_record = 1;
					} elsif ( $_->isa('BIGSdb::Exception::Data') ) {
						$continue = 0;
					}
				};
				last FIELD  if !$continue;
				next RECORD if $skip_record;
			}
			$tablebuffer .= $row_buffer;
			my %record_checks = (
				accession => sub {
					$self->_check_corresponding_sequence_exists( $pk_values_ref, $problems, $pk_combination );
					$self->check_permissions( $locus, $new_args, $problems, $pk_combination );
				},
				sequence_refs => sub {
					$self->_check_corresponding_sequence_exists( $pk_values_ref, $problems, $pk_combination );
					$self->check_permissions( $locus, $new_args, $problems, $pk_combination );
				},
				sequence_extended_attributes => sub {
					$self->_check_corresponding_sequence_exists( [ $pk_values_ref->[0], $pk_values_ref->[2] ],
						$problems, $pk_combination );
					$self->check_permissions( $locus, $new_args, $problems, $pk_combination );
				},
				loci => sub {
					$self->_check_data_loci($new_args);
				},
				locus_descriptions => sub {
					$self->check_permissions( $locus, $new_args, $problems, $pk_combination );
				},
				locus_links => sub {
					$self->check_permissions( $locus, $new_args, $problems, $pk_combination );
				},
				retired_allele_ids => sub {
					$self->check_permissions( $locus, $new_args, $problems, $pk_combination );
				},
				projects => sub {
					$self->_check_projects( $new_args, $problems, $pk_combination );
				},
				classification_group_field_values => sub {
					$self->_check_classification_field_values( $new_args, $problems, $pk_combination );
				},
				validation_conditions => sub {
					$self->_check_validation_conditions( $new_args, $problems, $pk_combination );
				},
				isolate_field_extended_attributes => sub {
					$self->_check_isolate_field_extended_attributes( $new_args, $problems, $pk_combination );
				},
				lincode_prefixes => sub {
					$self->_check_lincode_prefix_values( $new_args, $problems, $pk_combination );
				},
				geography_point_lookup => sub {
					$self->_check_geography_point_values( $new_args, $problems, $pk_combination );
				}
			);
			$record_checks{$table}->() if $record_checks{$table};
		}
		if ( defined $checked_record ) {
			$td = $td == 1 ? 2 : 1;    #row stripes
			$checked_record =~ s/\t$//x;
		}
		push @checked_buffer, $checked_record;
	}
	$tablebuffer .= q(</table></div>);
	if ( !$record_count ) {
		$self->print_bad_status(
			{
				message => q(No valid data entered. Make sure you've included the header line.)
			}
		);
		return;
	}
	return if $self->_is_over_quota( $table, scalar @checked_buffer - 1 );
	$self->{'submissionHandler'}->cleanup_validation_rules;
	$self->_report_check(
		{
			table          => $table,
			buffer         => \$tablebuffer,
			problems       => $problems,
			advisories     => $advisories,
			checked_buffer => \@checked_buffer,
			sender_message => \$sender_message
		}
	);
	return;
}

sub _is_over_quota {
	my ( $self, $table, $record_count ) = @_;
	my $q = $self->{'cgi'};
	return if $table ne 'isolates' || !$q->param('private');
	my $project_id = $q->param('project_id');
	if ( BIGSdb::Utils::is_int($project_id) ) {
		my $no_quota = $self->{'datastore'}->run_query( 'SELECT no_quota FROM projects WHERE id=?', $project_id );
		return if $no_quota;
	}
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $available = $self->{'datastore'}->get_available_quota( $user_info->{'id'} );
	if ( $record_count > $available ) {
		my $av_plural = $available == 1    ? q() : q(s);
		my $up_plural = $record_count == 1 ? q() : q(s);
		$self->print_bad_status(
			{
				message => qq(Your available quota for private data is $available record$av_plural. )
				  . qq(You are attempting to upload $record_count record$up_plural.)
			}
		);
		return 1;
	}
	return;
}

sub _isolate_record_further_checks {
	my ( $self, $table, $args, $advisories, $pk_combination ) = @_;
	return q() if $table ne 'isolates';
	if ( !$self->{'cache'}->{'label_field_values'} ) {
		$self->{'cache'}->{'label_field_values'} = $self->_get_existing_label_field_values;
	}

	#Check for locus values that can also be uploaded with an isolate record.
	my $buffer = $self->_check_data_isolate_record_locus_fields($args);

	#Check if a record with the same name already exists
	my $data = $args->{'data'};
	if ( defined $args->{'file_header_pos'}->{ $self->{'system'}->{'labelfield'} }
		&& $self->{'cache'}->{'label_field_values'}
		->{ $data->[ $args->{'file_header_pos'}->{ $self->{'system'}->{'labelfield'} } ] } )
	{
		$advisories->{$pk_combination} .= "$self->{'system'}->{'labelfield'} "
		  . "'$data->[$args->{'file_header_pos'}->{$self->{'system'}->{'labelfield'}}]' already exists in the database.";
	}

	#Check if aliases list has commas in it
	if ( defined $args->{'file_header_pos'}->{'aliases'}
		&& ( $data->[ $args->{'file_header_pos'}->{'aliases'} ] // q() ) =~ /,/x )
	{
		$advisories->{$pk_combination} .= 'Alias list should be separated by semi-colons (;). '
		  . 'Commas included in this field will be assumed to be part of an alias name.';
	}
	return $buffer;
}

sub format_display_value {
	my ( $self, $args ) = @_;
	my ( $table, $field, $value, $problems, $pk_combination, $special_problem ) =
	  @{$args}{qw(table field value problems pk_combination special_problem)};
	$value //= '';
	my $display_value;
	if ( $field =~ /sequence/ && $field ne 'coding_sequence' && $field ne 'sequence_method' ) {
		$display_value = q(<span class="seq">) . ( BIGSdb::Utils::truncate_seq( \$value, 40 ) ) . q(</span>);
	} else {
		$display_value = $value;
		$display_value =~ s/&/&amp;/gx;
		$display_value = BIGSdb::Utils::escape_html($display_value);
	}
	my $buffer;
	my $problem = $self->_check_field_bad( $table, $field, $value, $problems, $pk_combination );
	if ( !( $problem || $special_problem ) ) {
		if ( $table eq 'sequences' && $field eq 'flags' ) {
			my @flags = split /;/x, ( $display_value // q() );
			local $" = q(</a> <a class="seqflag_tooltip">);
			$display_value = qq(<a class="seqflag_tooltip">@flags</a>) if @flags;
		}
		$buffer = qq(<td>$display_value</td>);
	} else {
		$buffer = qq(<td><font color="red">$display_value</font></td>);
		if ($problem) {
			$problem = BIGSdb::Utils::escape_html($problem);
			my $problem_text = qq($field $problem<br />);
			if ( !defined $problems->{$pk_combination} || $problems->{$pk_combination} !~ /$problem_text/x ) {
				$problems->{$pk_combination} .= $problem_text;
			}
		}
	}
	return $buffer;
}

sub _check_field_bad {
	my ( $self, $table, $field, $value, $problems, $pk_combination ) = @_;
	return if ( $table eq 'sequences' && $field eq 'allele_id' && defined $problems->{$pk_combination} );
	my $set_id = $self->get_set_id;
	return $self->{'submissionHandler'}->is_field_bad( $table, $field, $value, 'insert', $set_id );
}

sub _check_projects {
	my ( $self, $args, $problems, $pk_combination ) = @_;
	my $data    = $args->{'data'};
	my $list    = $data->[ $args->{'file_header_pos'}->{'list'} ];
	my $private = $data->[ $args->{'file_header_pos'}->{'private'} ];
	my %true    = map { $_ => 1 } qw(true 1);
	if ( $true{ lc $private } && $true{ lc $list } ) {
		$problems->{$pk_combination} .=
		  'You cannot make a project both private and list it on the projects or isolate information pages. ';
	}
	return;
}

sub _check_classification_field_values {
	my ( $self, $args, $problems, $pk_combination ) = @_;
	my ( $data, $file_header_pos ) = ( $args->{'data'}, $args->{'file_header_pos'} );
	if (
		!$self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM classification_group_fields WHERE (cg_scheme_id,field)=(?,?))',
			[ $data->[ $file_header_pos->{'cg_scheme_id'} ], $data->[ $file_header_pos->{'field'} ] ]
		)
	  )
	{
		$problems->{$pk_combination} .= q(Selected field has not been defined for the selected classification scheme.);
	}
	my $format = $self->{'datastore'}->run_query(
		'SELECT type,value_regex FROM classification_group_fields WHERE (cg_scheme_id,field)=(?,?)',
		[ $data->[ $file_header_pos->{'cg_scheme_id'} ], $data->[ $file_header_pos->{'field'} ] ],
		{ fetch => 'row_hashref' }
	);
	return if !$format;
	if ( $format->{'type'} eq 'integer'
		&& !BIGSdb::Utils::is_int( $data->[ $file_header_pos->{'value'} ] ) )
	{
		$problems->{$pk_combination} .= "$data->[$file_header_pos->{'field'}] must be an integer.";
	} elsif ( $format->{'value_regex'} && $data->[ $file_header_pos->{'value'} ] !~ /$format->{'value_regex'}/x ) {
		$problems->{$pk_combination} .=
			"$data->[$file_header_pos->{'field'}] value is invalid - "
		  . "it must match the regular expression /$format->{'value_regex'}/.";
	}
	return;
}

sub _check_lincode_prefix_values {
	my ( $self, $args, $problems, $pk_combination ) = @_;
	my ( $data, $file_header_pos ) = ( $args->{'data'}, $args->{'file_header_pos'} );
	my $type = $self->{'datastore'}->run_query( 'SELECT type FROM lincode_fields WHERE (scheme_id,field)=(?,?)',
		[ $data->[ $file_header_pos->{'scheme_id'} ], $data->[ $file_header_pos->{'field'} ] ] );
	if ( $type eq 'integer'
		&& !BIGSdb::Utils::is_int( $data->[ $file_header_pos->{'value'} ] ) )
	{
		$problems->{$pk_combination} .= "$data->[$file_header_pos->{'field'}] must be an integer.";
	}
	return;
}

sub _check_geography_point_values {
	my ( $self, $args, $problems, $pk_combination ) = @_;
	my ( $data, $file_header_pos ) = ( $args->{'data'}, $args->{'file_header_pos'} );
	my $location = $data->[ $file_header_pos->{'location'} ];
	if ( $location =~ /^\s*(\-?\d+\.?\d*)\s*,\s*(\-?\d+\.?\d*)\s*$/x ) {
		my ( $lat, $long ) = ( $1, $2 );
		if ( $lat < -90 || $lat > 90 || $long < -180 || $long > 180 ) {
			$problems->{$pk_combination} .= qq('$data->[$file_header_pos->{'field'}]' latitude must be in the )
			  . q(range: -90 - 90; longitude must be in the range: -180 - 180 );
		}
	} else {
		$problems->{$pk_combination} .=
		  "$data->[$file_header_pos->{'field'}] should be in the format '[Latitude], [Longitude]'.";
	}
	return;
}

sub _check_validation_conditions {
	my ( $self, $args, $problems, $pk_combination ) = @_;
	my ( $data, $file_header_pos ) = ( $args->{'data'}, $args->{'file_header_pos'} );
	my %newdata = map { $_ => $data->[ $file_header_pos->{$_} ] } keys %$file_header_pos;
	return if !defined $newdata{'field'};
	if ( $newdata{'value'} eq 'null' ) {
		if ( $newdata{'operator'} ne '=' && $newdata{'operator'} ne 'NOT' ) {
			$problems->{$pk_combination} .= qq(The operator '$newdata{'operator'}' cannot be used for null values.);
		}
		return;
	}
	my $field_type = $self->get_field_type( $newdata{'field'} );
	if ( $newdata{'value'} =~ /^\[(.+)\]$/x ) {
		my $comp_field      = $1;
		my $comp_field_type = $self->get_field_type($comp_field);
		if ( !$comp_field_type ) {
			$problems->{$pk_combination} .= qq(Comparison field '$comp_field' is not recognized.);
			return;
		} else {
			if ( lc( substr( $field_type, 0, 3 ) ) ne lc( substr( $comp_field_type, 0, 3 ) ) ) {
				$problems->{$pk_combination} .=
					qq(Comparison field '$comp_field' has a different data type )
				  . qq(from '$newdata{'field'}' so cannot be compared.);
				return;
			}
		}
		return;
	}
	if ( lc($field_type) =~ /^int/x && !BIGSdb::Utils::is_int( $newdata{'value'} ) ) {
		$problems->{$pk_combination} .= qq('$newdata{'field'}' is an integer field.);
	}
	if ( lc($field_type) eq 'date' && !BIGSdb::Utils::is_date( $newdata{'value'} ) ) {
		$problems->{$pk_combination} .= qq('$newdata{'field'}' is a date field.);
	}
	if ( lc($field_type) eq 'float' && !BIGSdb::Utils::is_float( $newdata{'value'} ) ) {
		$problems->{$pk_combination} .= qq('$newdata{'field'}' is a float field.);
	}
	if ( lc($field_type) =~ /^bool/x && !BIGSdb::Utils::is_bool( $newdata{'value'} ) ) {
		$problems->{$pk_combination} .= qq('$newdata{'field'}' is a boolean field.);
	}
	return;
}

sub check_permissions {
	my ( $self, $locus, $args, $problems, $pk_combination ) = @_;
	return if !$self->{'system'}->{'dbtype'} eq 'sequences';
	return if $self->is_admin;
	my $data = $args->{'data'};
	if (  !defined $locus
		&& defined $args->{'file_header_pos'}->{'locus'}
		&& $data->[ $args->{'file_header_pos'}->{'locus'} ] )
	{
		$locus = $data->[ $args->{'file_header_pos'}->{'locus'} ];
	}
	if ( defined $locus
		&& !$self->{'datastore'}->is_allowed_to_modify_locus_sequences( $locus, $self->get_curator_id ) )
	{
		$problems->{$pk_combination} .= "Your user account is not allowed to add or modify records for locus $locus. ";
	}
	return;
}

sub _check_corresponding_sequence_exists {
	my ( $self, $pk_values_ref, $problems, $pk_combination ) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'sequences';
	return if !defined $pk_values_ref->[0];
	return if !defined $pk_values_ref->[1];
	if ( !$self->{'datastore'}->sequence_exists(@$pk_values_ref) ) {
		$problems->{$pk_combination} .= "Sequence $pk_values_ref->[0]-$pk_values_ref->[1] does not exist. ";
	}
	return;
}

sub _check_isolate_field_extended_attributes {
	my ( $self, $args, $problems, $pk_combination ) = @_;
	my ( $data, $file_header_pos ) = ( $args->{'data'}, $args->{'file_header_pos'} );
	if ( $self->{'xmlHandler'}->is_field( $data->[ $file_header_pos->{'attribute'} ] ) ) {
		$problems->{$pk_combination} .= 'A standard field already exists with this name.';
	}
	return;
}

sub _run_table_specific_field_checks {
	my ( $self, $table, $new_args ) = @_;
	my %further_checks = (
		allele_designations => sub {
			$self->_check_data_allele_designations($new_args);
		},
		users => sub {
			$self->_check_data_users($new_args);
		},
		scheme_group_group_members => sub {
			$self->_check_data_scheme_group_group_members($new_args);
		},
		isolates => sub {
			$self->_check_data_refs($new_args);
			$self->_check_data_codon_table($new_args);
			$self->_check_data_aliases($new_args);
			$self->_check_isolate_id_not_retired($new_args);
		},
		scheme_fields => sub {
			$self->_check_data_scheme_fields($new_args);
		},
		isolate_aliases => sub {
			$self->_check_data_isolate_aliases($new_args);
		},
		retired_allele_ids => sub {
			$self->_check_retired_allele_ids($new_args);
		},
		retired_profiles => sub {
			$self->_check_retired_profile_id($new_args);
		},
		retired_isolates => sub {
			$self->_check_retired_isolate_id($new_args);
		},
		classification_group_fields => sub {
			$self->_check_data_scheme_fields($new_args);
		},
		peptide_mutations => sub {
			$self->_check_peptide_mutation_fields($new_args);
		}
	);
	$further_checks{$table}->() if $further_checks{$table};
	return;
}

sub _run_table_specific_reformatting {
	my ( $self, $table, $new_args ) = @_;
	my %methods = (
		isolates => sub {
			$self->_rewrite_geography_point_data($new_args);
		}
	);
	$methods{$table}->() if $methods{$table};
	return;
}

sub _rewrite_geography_point_data {
	my ( $self,  $args )  = @_;
	my ( $field, $value ) = @{$args}{qw(field value)};
	my $geo_fields = $self->_get_geography_point_fields;
	return if !$geo_fields->{$field};
	if ( $$value =~ /^\s*(\-?\d+\.?\d*)\s*,\s*(\-?\d+\.?\d*)\s*$/x ) {
		$$value = $self->{'datastore'}->convert_coordinates_to_geography( $1, $2 );
	}
	return;
}

sub _get_geography_point_fields {
	my ($self) = @_;
	if ( !defined $self->{'cache'}->{'geography_point_fields'} ) {
		$self->{'cache'}->{'geography_point_fields'} = {};
		my $atts = $self->{'xmlHandler'}->get_all_field_attributes;
		foreach my $field ( keys %$atts ) {
			if ( ( $atts->{$field}->{'type'} // q() ) eq 'geography_point' ) {
				$self->{'cache'}->{'geography_point_fields'}->{$field} = 1;
			}
		}
	}
	return $self->{'cache'}->{'geography_point_fields'};
}

sub _get_existing_label_field_values {
	my ($self) = @_;
	my $values =
	  $self->{'datastore'}->run_query( "SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'}",
		undef, { fetch => 'col_arrayref' } );
	my %hash = map { $_ => 1 } @$values;
	return \%hash;
}

sub _report_check {
	my ( $self, $data ) = @_;
	my ( $table, $buffer, $problems, $advisories, $checked_buffer, $sender_message ) =
	  @{$data}{qw (table buffer problems advisories checked_buffer sender_message)};
	if ( !@$checked_buffer ) {
		say q(<div class="box" id="statusbad"><h2>Import status</h2>);
		say q(<p>No valid records to upload after filtering.</p></div>);
		return;
	}
	my $q = $self->{'cgi'};
	if (%$problems) {
		say q(<div class="box" id="statusbad"><h2>Import status</h2>);
		say q(<table class="resultstable">);
		say q(<tr><th>Primary key</th><th>Problem(s)</th></tr>);
		my $td = 1;
		foreach my $id ( sort keys %$problems ) {
			my $display_id = BIGSdb::Utils::escape_html($id);
			$problems->{$id} =~ s/'null'/<em>null<\/em>/gx;
			say qq(<tr class="td$td"><td>$display_id</td><td style="text-align:left">$problems->{$id}</td></tr>);
			$td = $td == 1 ? 2 : 1;    #row stripes
		}
		say q(</table></div>);
	} else {
		say qq(<div class="box" id="resultspanel"><h2>Import status</h2>$$sender_message);
		if (%$advisories) {
			say q(<p>Data can be uploaded but please note the following advisories:</p>);
			say q(<table class="resultstable">);
			say q(<tr><th>Primary key</th><th>Note(s)</th></tr>);
			my $td = 1;
			foreach my $id ( sort keys %$advisories ) {
				say qq(<tr class="td$td"><td>$id</td><td style="text-align:left">$advisories->{$id}</td></tr>);
				$td = $td == 1 ? 2 : 1;    #row stripes
			}
			say q(</table>);
		} else {
			say q(<p>No obvious problems identified so far.</p>);
		}
		my $filename = $self->make_temp_file(@$checked_buffer);
		say $q->start_form;
		say $q->hidden($_) foreach qw (page table db sender locus ignore_existing
		  submission_id project_id private user_header);
		say $q->hidden( checked_buffer => $filename );
		$self->print_action_fieldset( { submit_label => 'Import data', no_reset => 1 } );
		say $q->end_form;
		say q(</div>);
	}
	say q(<div class="box" id="resultstable"><h2>Data to be imported</h2>);
	say q(<p>The following table shows your data.  Any field with red text has a )
	  . q(problem and needs to be checked.</p>);
	say $$buffer;
	say q(</div>);
	return;
}

sub extract_value {
	my ( $self, $arg_ref ) = @_;
	my $q               = $self->{'cgi'};
	my $field           = $arg_ref->{'field'};
	my $data            = $arg_ref->{'data'};
	my $file_header_pos = $arg_ref->{'file_header_pos'};
	if ( $field eq 'id' ) {
		if ( defined $file_header_pos->{'id'} ) {
			return $data->[ $file_header_pos->{'id'} ];
		}
		return $arg_ref->{'id'};
	}
	if ( $field eq 'datestamp' || $field eq 'date_entered' ) {
		return BIGSdb::Utils::get_datestamp();
	}
	if ( $field eq 'sender' ) {
		if ( defined $file_header_pos->{$field} ) {
			return $data->[ $file_header_pos->{$field} ];
		} else {
			return $q->param('sender')
			  if $q->param('sender') != -1;
		}
	}
	if ( $field eq 'curator' ) {
		return $self->get_curator_id;
	}
	if (   $arg_ref->{'extended_attributes'}->{$field}->{'format'}
		&& $arg_ref->{'extended_attributes'}->{$field}->{'format'} eq 'boolean' )
	{
		if ( defined $file_header_pos->{$field} ) {
			return lc( $data->[ $file_header_pos->{$field} ] );
		}
	} else {
		if ( defined $file_header_pos->{$field} ) {
			return $data->[ $file_header_pos->{$field} ];
		}
	}
	return;
}

sub _get_primary_key_values {
	my ( $self, $arg_ref ) = @_;
	my @data            = @{ $arg_ref->{'data'} };
	my %file_header_pos = %{ $arg_ref->{'file_header_pos'} };
	my $pk_combination;
	my @pk_values;
	foreach ( @{ $arg_ref->{'primary_keys'} } ) {
		if ( !defined $file_header_pos{$_} ) {
			if ( $_ eq 'id' && $arg_ref->{'id'} ) {
				$pk_combination .= 'id: ' . BIGSdb::Utils::pad_length( $arg_ref->{'id'}, 10 );
				push @pk_values, $arg_ref->{'id'};
			} else {
				$pk_combination .= '; ' if $pk_combination;
				$pk_combination .= "$_: undef";
			}
		} else {
			$pk_combination .= '; ' if !${ $arg_ref->{'first'} };
			$pk_combination .= "$_: "
			  . (
				defined $data[ $file_header_pos{$_} ]
				? BIGSdb::Utils::pad_length( $data[ $file_header_pos{$_} ], 10 )
				: 'undef'
			  );
			push @pk_values, $data[ $file_header_pos{$_} ];
		}
		${ $arg_ref->{'first'} } = 0;
		${ $arg_ref->{'record_count'} }++;
	}
	return ( $pk_combination, \@pk_values );
}

sub _check_data_isolate_record_locus_fields {
	my ( $self, $arg_ref ) = @_;
	my $first_record    = $arg_ref->{'first_record'};
	my %file_header_pos = %{ $arg_ref->{'file_header_pos'} };
	my @data            = @{ $arg_ref->{'data'} };
	my $pk_combination  = $arg_ref->{'pk_combination'};
	my $set_id          = $self->get_set_id;
	my $locusbuffer;
	foreach my $field ( @{ $arg_ref->{'file_header_fields'} } ) {
		if ( !$self->{'field_name_cache'}->{$field} ) {
			$self->{'field_name_cache'}->{$field} = $self->{'submissionHandler'}->map_locus_name( $field, $set_id )
			  // $field;
		}
		if ( $self->{'datastore'}->is_locus( $self->{'field_name_cache'}->{$field}, { set_id => $set_id } ) ) {
			${ $arg_ref->{'header_row'} } .= "$self->{'field_name_cache'}->{$field}\t" if $first_record;
			my $value = defined $file_header_pos{$field} ? $data[ $file_header_pos{$field} ] : undef;
			if ( !$arg_ref->{'locus_format'}->{ $self->{'field_name_cache'}->{$field} } ) {
				my $locus_info = $self->{'datastore'}->get_locus_info( $self->{'field_name_cache'}->{$field} );
				$arg_ref->{'locus_format'}->{ $self->{'field_name_cache'}->{$field} } =
				  $locus_info->{'allele_id_format'};
				$arg_ref->{'locus_regex'}->{ $self->{'field_name_cache'}->{$field} } = $locus_info->{'allele_id_regex'};
			}
			if ( defined $value && $value ne '' ) {
				if ( $arg_ref->{'locus_format'}->{ $self->{'field_name_cache'}->{$field} } eq 'integer'
					&& !BIGSdb::Utils::is_int($value) )
				{
					$locusbuffer .= "<span><font color='red'>$field:&nbsp;$value</font></span><br />";
					$arg_ref->{'problems'}->{$pk_combination} .= "'$field' must be an integer<br />";
				} elsif ( $arg_ref->{'locus_regex'}->{ $self->{'field_name_cache'}->{$field} }
					&& $value !~ /$arg_ref->{'locus_regex'}->{$self->{'field_name_cache'}->{$field}}/x )
				{
					$locusbuffer .= "<span><font color='red'>$field:&nbsp;$value</font></span><br />";
					$arg_ref->{'problems'}->{$pk_combination} .= "'$field' does not conform to specified format.<br />";
				} else {
					$locusbuffer .= "$field:&nbsp;$value<br />";
				}
				${ $arg_ref->{'checked_record'} } .= "$value\t";
			} else {
				${ $arg_ref->{'checked_record'} } .= "\t";
			}
		}
	}
	return defined $locusbuffer ? "<td>$locusbuffer</td>" : '<td></td>';
}

sub _check_data_users {

	#special case to prevent a new user with curator or admin status unless user is admin themselves
	my ( $self, $arg_ref ) = @_;
	my $field          = $arg_ref->{'field'};
	my $value          = ${ $arg_ref->{'value'} };
	my $pk_combination = $arg_ref->{'pk_combination'};
	my $check          = {
		status => sub {
			if ( defined $value && $value ne 'user' && !$self->is_admin ) {
				$arg_ref->{'problems'}->{$pk_combination} .=
				  q(Only a user with admin status can add a user with a status other than 'user'.<br />);
				${ $arg_ref->{'special_problem'} } = 1;
			}
		},
		user_db => sub {
			if ( defined $value && $value ne q() ) {
				$arg_ref->{'problems'}->{$pk_combination} .= q(You cannot batch add users from external )
				  . q(user databases using this function. You need to import them.);
				${ $arg_ref->{'special_problem'} } = 1;
			}
		}
	};
	if ( $check->{$field} ) {
		$check->{$field}->();
	}
	return;
}

sub _check_data_scheme_fields {
	my ( $self, $arg_ref ) = @_;
	my $field          = $arg_ref->{'field'};
	my $value          = ${ $arg_ref->{'value'} };
	my $pk_combination = $arg_ref->{'pk_combination'};

	#special case to check that only one primary key field is set for a scheme field
	my $field_order = $arg_ref->{'file_header_pos'};
	my $scheme_id =
	  defined $field_order->{'scheme_id'}
	  ? $arg_ref->{'data'}->[ $field_order->{'scheme_id'} ]
	  : undef;
	my %false = map { $_ => 1 } qw(false 0);
	if ( $field eq 'primary_key' && !$false{ lc $value } ) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		if ( $scheme_info->{'primary_key'} || $self->{'pk_already_in_this_upload'}->{$scheme_id} ) {
			my $problem_text = q(This scheme already has a primary key field set.<br />);
			$arg_ref->{'problems'}->{$pk_combination} .= $problem_text;
			${ $arg_ref->{'special_problem'} } = 1;
		}
		$self->{'pk_already_in_this_upload'}->{$scheme_id} = 1;
	}

	#special case to check that scheme field is not called 'id' (this causes problems when joining tables)
	if ( $field eq 'field' && $value eq 'id' ) {
		my $problem_text = q(Scheme fields can not be called 'id'.<br />);
		if ( !defined $arg_ref->{'problems'}->{$pk_combination}
			|| $arg_ref->{'problems'}->{$pk_combination} !~ /$problem_text/x )
		{
			$arg_ref->{'problems'}->{$pk_combination} .= $problem_text;
		}
		${ $arg_ref->{'special_problem'} } = 1;
	}
	return;
}

sub _check_data_refs {

	#special case to check that references are valid PubMed ids.
	my ( $self, $arg_ref ) = @_;
	my $field          = $arg_ref->{'field'};
	my $value          = ${ $arg_ref->{'value'} };
	my $pk_combination = $arg_ref->{'pk_combination'};
	if ( $field eq 'references' ) {
		if ( defined $value ) {
			$value =~ s/\s//gx;
			my @refs = split /;/x, $value;
			my %used;
			foreach my $ref (@refs) {
				if ( $used{$ref} ) {
					my $problem_text = 'Duplicate PubMed id used.<br />';
					$arg_ref->{'problems'}->{$pk_combination} .= $problem_text;
					${ $arg_ref->{'special_problem'} } = 1;
					last;
				}
				if ( !BIGSdb::Utils::is_int($ref) ) {
					my $problem_text = "References are PubMed ids - $ref is not an integer.<br />";
					$arg_ref->{'problems'}->{$pk_combination} .= $problem_text;
					${ $arg_ref->{'special_problem'} } = 1;
				} elsif ( $ref <= 10_000 ) {
					if ( ( $arg_ref->{'advisories'}->{$pk_combination} // q() ) !~ /References\ may\ be\ invalid/x ) {
						$arg_ref->{'advisories'}->{$pk_combination} .=
						  'References may be invalid - you are unlikely to have a PubMed id less than 10,000.<br />';
					}
				}
				$used{$ref} = 1;
			}
		}
	}
	return;
}

sub _check_peptide_mutation_fields {
	my ( $self, $arg_ref ) = @_;
	my $field          = $arg_ref->{'field'};
	my $value          = ${ $arg_ref->{'value'} };
	my $pk_combination = $arg_ref->{'pk_combination'};
	if ( $field eq 'variant_aa' ) {
		$value =~ s/\s//gx;
		my @variants = split /;/x, $value;
		my %used;
		my $wt = $arg_ref->{'data'}->[ $arg_ref->{'file_header_pos'}->{'wild_type_aa'} ];
		foreach my $variant (@variants) {
			if ( $variant eq $wt ) {
				$arg_ref->{'problems'}->{$pk_combination} .= 'Variant amino acid is the same as wild-type.<br />';
			}
			if ( $used{$variant} ) {
				$arg_ref->{'problems'}->{$pk_combination} .= "Variant '$variant' is listed more than once.<br />";
			}
			$used{$variant} = 1;
		}
	}
	if ( $field eq 'position' ) {
		if ( $value < 1 ) {
			$arg_ref->{'problems'}->{$pk_combination} .= 'Position must be a positive integer.<br />';
		}
	}
	return;
}

sub _check_data_aliases {

	#special case to check that isolate aliases don't duplicate isolate name or consist of null terms
	#when batch uploaded isolates
	my ( $self, $arg_ref ) = @_;
	my $field          = $arg_ref->{'field'};
	my $value          = ${ $arg_ref->{'value'} };
	my $pk_combination = $arg_ref->{'pk_combination'};
	if ( $field eq 'aliases' ) {
		my $isolate_name = $arg_ref->{'data'}->[ $arg_ref->{'file_header_pos'}->{ $self->{'system'}->{'labelfield'} } ];
		my %null_terms   = map { lc($_) => 1 } NULL_TERMS;
		if ( defined $value ) {
			$value =~ s/\s//gx;
			my @aliases = split /;/x, $value;
			my %used;
			foreach my $alias (@aliases) {
				$alias =~ s/\s+$//x;
				$alias =~ s/^\s+//x;
				next if $alias eq '';
				if ( defined $isolate_name ) {
					if ( $used{$alias} ) {
						my $problem_text = 'Duplicate alias used.<br />';
						$arg_ref->{'problems'}->{$pk_combination} .= $problem_text;
						${ $arg_ref->{'special_problem'} } = 1;
						last;
					}
					if ( $alias eq $isolate_name ) {
						my $problem_text = 'Aliases are ALTERNATIVE names for the isolate name.<br />';
						$arg_ref->{'problems'}->{$pk_combination} .= $problem_text;
						${ $arg_ref->{'special_problem'} } = 1;
						last;
					}
					$used{$alias} = 1;
				}
				if ( $null_terms{ lc($alias) } ) {
					my $problem_text =
					  "Aliases are optional - leave blank rather than using a value like '$alias'.<br />";
					$arg_ref->{'problems'}->{$pk_combination} .= $problem_text;
					${ $arg_ref->{'special_problem'} } = 1;
					last;
				}
			}
		}
	}
	return;
}

sub _check_data_codon_table {
	my ( $self, $arg_ref ) = @_;
	return if ( $self->{'system'}->{'alternative_codon_tables'} // q() ) ne 'yes';
	my $field          = $arg_ref->{'field'};
	my $value          = ${ $arg_ref->{'value'} };
	my $pk_combination = $arg_ref->{'pk_combination'};
	return if $field ne 'codon_table';
	return if !defined $value || $value eq q();
	my $tables  = Bio::Tools::CodonTable->tables;
	my @allowed = sort { $a <=> $b } keys %$tables;
	my %allowed = map  { $_ => 1 } @allowed;

	if ( !$allowed{$value} ) {
		local $" = q(, );
		my $problem_text = "Allowed codon tables are: @allowed.<br />";
		$arg_ref->{'problems'}->{$pk_combination} .= $problem_text;
		${ $arg_ref->{'special_problem'} } = 1;
	}
	return;
}

sub _check_data_isolate_aliases {

	#special case to check that isolate aliases don't duplicate isolate name or consist of null values
	#when batch uploading isolate aliases
	my ( $self, $arg_ref ) = @_;
	my $field          = $arg_ref->{'field'};
	my $value          = ${ $arg_ref->{'value'} };
	my $pk_combination = $arg_ref->{'pk_combination'};
	my $isolate_id     = $arg_ref->{'data'}->[ $arg_ref->{'file_header_pos'}->{'isolate_id'} ];
	if ( $field eq 'alias' && BIGSdb::Utils::is_int($isolate_id) ) {
		my $isolate_name =
		  $self->{'datastore'}->run_query( "SELECT $self->{'system'}->{'labelfield'} FROM isolates WHERE id=?",
			$isolate_id, { cache => 'CurateBatchAddPage::check_data_isolates_aliases' } );
		return if !defined $isolate_name;
		if ( $value eq $isolate_name ) {
			my $problem_text = 'Alias duplicates isolate name.<br />';
			$arg_ref->{'problems'}->{$pk_combination} .= $problem_text;
			${ $arg_ref->{'special_problem'} } = 1;
		}
		my %null_terms = map { lc($_) => 1 } NULL_TERMS;
		if ( $null_terms{ lc($value) } ) {
			my $problem_text = 'Alias contains an invalid term.<br />';
			$arg_ref->{'problems'}->{$pk_combination} .= $problem_text;
			${ $arg_ref->{'special_problem'} } = 1;
		}
	}
	return;
}

sub _check_data_primary_key {
	my ( $self, $arg_ref ) = @_;
	my $pk_combination = $arg_ref->{'pk_combination'};
	my @primary_keys   = @{ $arg_ref->{'primary_keys'} };
	if ( !$self->{'sql'}->{'primary_key_check'} ) {
		local $" = '=? AND ';
		my $qry = "SELECT EXISTS(SELECT * FROM $arg_ref->{'table'} WHERE @primary_keys=?)";
		$self->{'sql'}->{'primary_key_check'} = $self->{'db'}->prepare($qry);
	}
	if ( $self->{'primary_key_combination'}->{$pk_combination} && $pk_combination !~ /\:\s*$/x ) {
		my $problem_text = 'Primary key submitted more than once in this batch.<br />';
		$arg_ref->{'problems'}->{$pk_combination} .= $problem_text
		  if !defined $arg_ref->{'problems'}->{$pk_combination}
		  || $arg_ref->{'problems'}->{$pk_combination} !~ /$problem_text/x;
	}
	$self->{'primary_key_combination'}->{$pk_combination}++;

	#Check if primary key already in database
	if ( @{ $arg_ref->{'pk_values'} } ) {
		eval { $self->{'sql'}->{'primary_key_check'}->execute( @{ $arg_ref->{'pk_values'} } ) };
		if ($@) {
			my $message = $@;
			local $" = ', ';
			$logger->debug(
					"Can't execute primary key check (incorrect data pasted): primary keys: @primary_keys values: "
				  . "@{$arg_ref->{'pk_values'}} $message" );
			my $plural = scalar @primary_keys > 1 ? 's' : '';
			if ( $message =~ /invalid input/ ) {
				$self->print_bad_status(
					{
						message => qq(Your pasted data has invalid primary key field$plural )
						  . qq((@primary_keys) data.)
					}
				);
				BIGSdb::Exception::Data->throw('Invalid primary key');
			}
			$self->print_bad_status(
				{
					message => q(Your pasted data does not appear to contain the primary )
					  . qq(key field$plural (@primary_keys) required for this table.)
				}
			);
			BIGSdb::Exception::Data->throw("no primary key field$plural (@primary_keys)");
		}
		my ($exists) = $self->{'sql'}->{'primary_key_check'}->fetchrow_array;
		if ($exists) {
			my %warn_tables = map { $_ => 1 } qw(codon_tables project_members refs isolate_aliases locus_aliases);
			if ( $warn_tables{ $arg_ref->{'table'} } ) {
				my $warning_text = 'Primary key already exists in the database - upload will be skipped.<br />';
				if ( !defined $arg_ref->{'problems'}->{$pk_combination}
					|| $arg_ref->{'advisories'}->{$pk_combination} !~ /$warning_text/x )
				{
					$arg_ref->{'advisories'}->{$pk_combination} .= $warning_text;
					BIGSdb::Exception::Data::Warning->throw('Primary key already exists.');
				}
			} else {
				my $problem_text = 'Primary key already exists in the database.<br />';
				if ( !defined $arg_ref->{'problems'}->{$pk_combination}
					|| $arg_ref->{'problems'}->{$pk_combination} !~ /$problem_text/x )
				{
					$arg_ref->{'problems'}->{$pk_combination} .= $problem_text;
				}
			}
		}
	}
	return;
}

sub _check_data_loci {

	#special case to ensure that a locus length is set if it is not marked as variable length
	my ( $self, $arg_ref ) = @_;
	my @data            = @{ $arg_ref->{'data'} };
	my %file_header_pos = %{ $arg_ref->{'file_header_pos'} };
	my $pk_combination  = $arg_ref->{'pk_combination'};
	if (
		(
			   defined $file_header_pos{'length_varies'}
			&& defined $data[ $file_header_pos{'length_varies'} ]
			&& none { $data[ $file_header_pos{'length_varies'} ] eq $_ } qw (true TRUE 1)
		)
		&& !$data[ $file_header_pos{'length'} ]
	  )
	{
		$arg_ref->{'problems'}->{$pk_combination} .= 'Locus set as non variable length but no length is set.<br />';
	}
	if ( $data[ $file_header_pos{'id'} ] =~ /[^\w_\-']/x ) {
		$arg_ref->{'problems'}->{$pk_combination} .=
			q(Locus names can only contain alphanumeric, underscore (_), hyphen (-) )
		  . q(and prime (') characters (no spaces or other symbols).<br />);
	}
	return;
}

sub check_data_duplicates {

	#check if unique value exists twice in submission
	my ( $self, $arg_ref ) = @_;
	my $field = $arg_ref->{'field'};
	my $value = ${ $arg_ref->{'value'} };
	return if !defined $value;
	my $pk_combination = $arg_ref->{'pk_combination'};
	if ( $arg_ref->{'unique_field'}->{$field} ) {
		if ( $self->{'unique_values'}->{$field}->{$value} ) {
			my $problem_text =
			  "unique field '$field' already has a value of '$value' set within this submission.<br />";
			$arg_ref->{'problems'}->{$pk_combination} .= $problem_text
			  if !defined $arg_ref->{'problems'}->{$pk_combination}
			  || $arg_ref->{'problems'}->{$pk_combination} !~ /$problem_text/x;
			${ $arg_ref->{'special_problem'} } = 1;
		}
		$self->{'unique_values'}->{$field}->{$value}++;
	}
	return;
}

sub _check_data_allele_designations {

	#special case to check for allele id format and regex which is defined in loci table
	my ( $self, $arg_ref ) = @_;
	my $field           = $arg_ref->{'field'};
	my $pk_combination  = $arg_ref->{'pk_combination'};
	my @data            = @{ $arg_ref->{'data'} };
	my %file_header_pos = %{ $arg_ref->{'file_header_pos'} };
	if ( $field eq 'allele_id' ) {
		if ( defined $file_header_pos{'locus'} ) {
			my $format = $self->{'datastore'}->run_query(
				'SELECT allele_id_format,allele_id_regex FROM loci WHERE id=?',
				$data[ $file_header_pos{'locus'} ],
				{ fetch => 'row_hashref' }
			);
			if (   defined $format->{'allele_id_format'}
				&& $format->{'allele_id_format'} eq 'integer'
				&& !BIGSdb::Utils::is_int( ${ $arg_ref->{'value'} } ) )
			{
				my $problem_text = "$field must be an integer.<br />";
				$arg_ref->{'problems'}->{$pk_combination} .= $problem_text
				  if !defined $arg_ref->{'problems'}->{$pk_combination}
				  || $arg_ref->{'problems'}->{$pk_combination} !~ /$problem_text/x;
				${ $arg_ref->{'special_problem'} } = 1;
			} elsif ( $format->{'allele_id_regex'}
				&& ${ $arg_ref->{'value'} } !~ /$format->{'allele_id_regex'}/x )
			{
				$arg_ref->{'problems'}->{$pk_combination} .=
					qq($field value is invalid - it must match the regular )
				  . qq(expression /$format->{'allele_id_regex'}/.<br />);
				${ $arg_ref->{'special_problem'} } = 1;
			}
		}
	}
	return;
}

sub _check_data_scheme_group_group_members {
	my ( $self, $arg_ref ) = @_;
	my $field           = $arg_ref->{'field'};
	my $pk_combination  = $arg_ref->{'pk_combination'};
	my @data            = @{ $arg_ref->{'data'} };
	my %file_header_pos = %{ $arg_ref->{'file_header_pos'} };
	if (   $field eq 'group_id'
		&& $data[ $file_header_pos{'parent_group_id'} ] == $data[ $file_header_pos{'group_id'} ] )
	{
		$arg_ref->{'problems'}->{$pk_combination} .= q(A scheme group can't be a member of itself.);
		${ $arg_ref->{'special_problem'} } = 1;
	}
	return;
}

sub _check_retired_allele_ids {
	my ( $self, $arg_ref ) = @_;
	my ( $pk_combination, $field, $file_header_pos ) = @{$arg_ref}{qw(pk_combination field file_header_pos)};
	if ( $field eq 'allele_id' ) {
		my $exists = $self->{'datastore'}->run_query(
			'SELECT EXISTS (SELECT * FROM sequences WHERE (locus,allele_id)=(?,?))',
			[
				$arg_ref->{'data'}->[ $file_header_pos->{'locus'} ],
				$arg_ref->{'data'}->[ $file_header_pos->{'allele_id'} ]
			]
		);
		if ($exists) {
			$arg_ref->{'problems'}->{$pk_combination} .=
			  'This allele has already been defined - delete it before you retire the identifier.';
			${ $arg_ref->{'special_problem'} } = 1;
		}
	}
	return;
}

sub _check_retired_profile_id {
	my ( $self, $arg_ref ) = @_;
	my ( $pk_combination, $field, $file_header_pos ) = @{$arg_ref}{qw(pk_combination field file_header_pos)};
	if ( $field eq 'profile_id' ) {
		if (
			$self->{'datastore'}->profile_exists(
				$arg_ref->{'data'}->[ $file_header_pos->{'scheme_id'} ],
				$arg_ref->{'data'}->[ $file_header_pos->{'profile_id'} ]
			)
		  )
		{
			$arg_ref->{'problems'}->{$pk_combination} .=
			  'Profile has already been defined - delete it before you retire the identifier.';
			${ $arg_ref->{'special_problem'} } = 1;
		}
	}
	if ( $field eq 'scheme_id' ) {
		if (   !$self->is_admin
			&& !$self->{'datastore'}
			->is_scheme_curator( $arg_ref->{'data'}->[ $file_header_pos->{'scheme_id'} ], $self->get_curator_id ) )
		{
			$arg_ref->{'problems'}->{$pk_combination} .= 'You are not a curator for this scheme.';
			${ $arg_ref->{'special_problem'} } = 1;
		}
	}
	return;
}

sub _check_retired_isolate_id {
	my ( $self, $arg_ref ) = @_;
	my ( $pk_combination, $field, $file_header_pos ) = @{$arg_ref}{qw(pk_combination field file_header_pos)};
	return if $field ne 'isolate_id';
	return if !BIGSdb::Utils::is_int( $arg_ref->{'data'}->[ $file_header_pos->{'isolate_id'} ] );
	if ( $self->{'datastore'}->isolate_exists( $arg_ref->{'data'}->[ $file_header_pos->{'isolate_id'} ], ) ) {
		$arg_ref->{'problems'}->{$pk_combination} .=
		  'Isolate has already been defined - delete it before you retire the identifier.';
		${ $arg_ref->{'special_problem'} } = 1;
	}
	return;
}

sub _check_isolate_id_not_retired {
	my ( $self, $arg_ref ) = @_;
	my ( $pk_combination, $field, $file_header_pos ) = @{$arg_ref}{qw(pk_combination field file_header_pos)};
	return
		 if $field ne 'id'
	  || !defined $file_header_pos->{'id'}
	  || !BIGSdb::Utils::is_int( $arg_ref->{'data'}->[ $file_header_pos->{'id'} ] );
	if (
		$self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM retired_isolates WHERE isolate_id=?)',
			$arg_ref->{'data'}->[ $file_header_pos->{'id'} ],
		)
	  )
	{
		$arg_ref->{'problems'}->{$pk_combination} .= 'Isolate id has been retired.';
		${ $arg_ref->{'special_problem'} } = 1;
	}
	return;
}

sub _is_not_allowed_to_upload_public_data {
	my ( $self, $table ) = @_;
	my $private   = $self->_is_private_record;
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	if ( $table eq 'isolates' && !$private && $self->{'permissions'}->{'only_private'} ) {
		$self->print_bad_status(
			{
				message =>
				  'You are attempting to upload public data but you do not have sufficient privileges to do so.'
			}
		);
		my $user_string = $self->{'datastore'}->get_user_string( $user_info->{'id'} );
		$logger->error("Attempt to upload public data by user ($user_string) who does not have permission.");
		return 1;
	}
	return;
}

sub _upload_data {
	my ( $self, $arg_ref ) = @_;
	my $table   = $arg_ref->{'table'};
	my $locus   = $arg_ref->{'locus'};
	my $q       = $self->{'cgi'};
	my $records = $self->_extract_checked_records;
	return if !@$records;
	my $field_order       = $self->_get_field_order($records);
	my $fields_to_include = $self->_get_fields_to_include( $table, $locus );
	my $project_id        = $self->_get_private_project_id;
	my $private           = $self->_is_private_record;
	return if $self->_is_not_allowed_to_upload_public_data($table);
	my $submission_id = $q->param('submission_id');
	my $prefix        = BIGSdb::Utils::get_random();
	my $status_file   = "$prefix.json";
	my $success_html  = $self->_report_successful_upload( $table, $project_id );

	#Use double fork to prevent zombie processes on apache2-mpm-worker
	defined( my $kid = fork ) or $self->{'logger'}->error('cannot fork');
	if ($kid) {
		waitpid( $kid, 0 );
	} else {
		defined( my $grandkid = fork ) or $self->{'logger'}->error('Kid cannot fork');
		if ($grandkid) {
			CORE::exit(0);
		} else {
			open STDIN,  '<', '/dev/null' || $self->{'logger'}->error("Can't detach STDIN: $!");
			open STDOUT, '>', '/dev/null' || $self->{'logger'}->error("Can't detach STDOUT: $!");
			open STDERR, '>&STDOUT' || $self->{'logger'}->error("Can't detach STDERR: $!");
			my $uploader = BIGSdb::Offline::BatchUploader->new(
				{
					config_dir       => $self->{'config_dir'},
					lib_dir          => $self->{'lib_dir'},
					dbase_config_dir => $self->{'dbase_config_dir'},
					host             => $self->{'system'}->{'host'},
					port             => $self->{'system'}->{'port'},
					user             => $self->{'system'}->{'user'},
					password         => $self->{'system'}->{'password'},
					instance         => $self->{'instance'},
					logger           => $logger,
					params           => {
						records           => $records,
						username          => $self->{'username'},
						field_order       => $field_order,
						fields_to_include => $fields_to_include,
						table             => $table,
						locus             => $locus,
						project_id        => $project_id,
						private           => $private,
						curator_id        => $self->get_curator_id,
						sender_id         => scalar $q->param('sender'),
						submission_id     => $submission_id,
						status_file       => $status_file,
						success_html      => $success_html
					}
				}
			);
			$uploader->upload;
			CORE::exit(0);
		}
	}
	$self->_load_status_page($status_file);
	return;
}

sub _load_status_page {
	my ( $self, $status_file ) = @_;
	say q(<div id="results"><div class="box" id="resultspanel">)
	  . q(<div><span class="wait_icon fas fa-sync-alt fa-spin fa-4x" style="margin-right:0.5em"></span>)
	  . q(<span class="wait_message">Uploading - Please wait.</span></div>)
	  . q(<div id="progress"></div></div>)
	  . q(<noscript><div class="box statusbad"><p>Please enable Javascript in your browser</p></div></noscript></div>);
	my $prefix = BIGSdb::Utils::get_random();
	say $self->_get_polling_javascript($status_file);
	return;
}

sub _get_polling_javascript {
	my ( $self, $status_file ) = @_;
	my $file_path     = "/tmp/$status_file";
	my $max_poll_time = 5_000;
	my $error         = $self->print_bad_status(
		{
			message  => 'Could not find results file',
			detail   => 'Please try re-uploading records.',
			get_only => 1
		}
	);
	my $buffer = << "END";
<script>//<![CDATA[

var error_seen = 0;
\$(function () {	
	getResults(500);
});

function getResults(poll_time) {	
	\$.ajax({
		url: "$file_path",
		dataType: 'json',
		cache: false,
		success: function(data){
			if (data.status == 'finished'){	
				\$("div#results").html(data.html);
			} else if (data.status == 'uploading'){
				\$("div#progress").html('<p style="font-size:5em;color:#888;margin-left:1.5em;margin-top:1em">' 
				+ data.progress + '%</p>');
				// Wait and poll again - increase poll time by 0.5s each time.
				poll_time += 500;
				if (poll_time > $max_poll_time){
					poll_time = $max_poll_time;
				}
				setTimeout(function() { 
           	        getResults(poll_time); 
                }, poll_time);
 			} else {
				\$("div#results").html();
			}
		},
		error: function (){
			if (error_seen > 10){
				\$("div#results").html('$error');
				return;
			}
			error_seen++;
			setTimeout(function() { 
            	getResults(poll_time); 
            }, poll_time);           
		}
	});
}
//]]></script>
END
	return $buffer;
}

sub _report_successful_upload {
	my ( $self, $table, $project_id ) = @_;
	my $q        = $self->{'cgi'};
	my $nav_data = $self->_get_nav_data($table);
	my $script =
	  $q->param('user_header') ? $self->{'system'}->{'query_script'} : $self->{'system'}->{'script_name'};
	my ( $more_url, $back_url, $upload_contigs_url );
	if ( $script eq $self->{'system'}->{'script_name'} ) {
		$more_url = qq($script?db=$self->{'instance'}&amp;page=batchAdd&amp;table=$table);
		if ( $table eq 'isolates' ) {
			$upload_contigs_url = qq($script?db=$self->{'instance'}&amp;page=batchAddSeqbin);
		}
	} elsif ( $self->{'system'}->{'curate_script'} && $table eq 'isolates' ) {
		if ( $q->param('private') ) {
			$more_url = qq($self->{'system'}->{'curate_script'}?db=$self->{'instance'}&amp;page=batchAdd&amp;)
			  . q(table=isolates&amp;private=1&amp;user_header=1);
			if ($project_id) {
				$more_url .= qq(&amp;project_id=$project_id);
			}
			$back_url = qq($script?db=$self->{'instance'}&amp;page=privateRecords);
		}
		$upload_contigs_url = qq($self->{'system'}->{'curate_script'}?db=$self->{'instance'}&amp;page=batchAddSeqbin);
	}
	my $detail;
	if ( $q->param('submission_id') ) {
		my $submission_id = $q->param('submission_id');
		my $url           = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit&amp;)
		  . qq(submission_id=$submission_id&amp;curate=1);
		$detail = qq(Don't forget to <a href="$url">close the submission</a>!);
	}
	return $self->print_good_status(
		{
			message => q(Database updated.),
			detail  => $detail,
			navbar  => 1,
			script  => $script,
			%$nav_data,
			more_text          => q(Add more),
			more_url           => $nav_data->{'more_url'} // $more_url,
			back_url           => $back_url,
			upload_contigs_url => $upload_contigs_url,
			get_only           => 1
		}
	);
}

sub _get_nav_data {
	my ( $self, $table ) = @_;
	my $q             = $self->{'cgi'};
	my $submission_id = $q->param('submission_id');
	my $more_url;
	return { submission_id => $submission_id, more_url => $more_url };
}

sub _extract_checked_records {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $records  = [];
	my $tmp_file = "$self->{'config'}->{'secure_tmp_dir'}/" . $q->param('checked_buffer');
	if ( !-e $tmp_file ) {
		$self->print_bad_status(
			{
					message => q(The temp file containing the checked data does not exist.</p>)
				  . q(<p>Upload cannot proceed.  Make sure that you haven't used the back button and are attempting to )
				  . q(re-upload already submitted data.  Please report this if the problem persists.)
			}
		);
		$logger->error("Checked buffer file $tmp_file does not exist.");
		return [];
	}
	if ( open( my $tmp_fh, '<:encoding(utf8)', $tmp_file ) ) {
		@$records = <$tmp_fh>;
		close $tmp_fh;
	} else {
		$logger->error("Cannot open $tmp_file for reading.");
	}
	if ( $tmp_file =~ /^(.*\/BIGSdb_[0-9_]+)$/x ) {
		$logger->info("Deleting temp file $tmp_file.");
		unlink $1;
	} else {
		$logger->error("Cannot delete temp file $tmp_file.");
	}
	return $records;
}

sub _get_field_order {
	my ( $self, $records ) = @_;
	my $header_line = shift @$records;
	my @fields;
	if ( defined $header_line ) {
		$header_line =~ s/[\r\n]//gx;
		@fields = split /\t/x, $header_line;
	}
	my $field_order = {};
	for my $i ( 0 .. @fields - 1 ) {
		$field_order->{ $fields[$i] } = $i;
	}
	return $field_order;
}

sub _get_fields_to_include {
	my ( $self, $table, $locus ) = @_;
	my $fields_to_include = [];
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		my $set_id     = $self->get_set_id;
		my $field_list = $self->{'xmlHandler'}->get_field_list;
		foreach my $field (@$field_list) {
			my $att = $self->{'xmlHandler'}->get_field_attributes($field);
			next if ( $att->{'no_curate'} // '' ) eq 'yes';
			push @$fields_to_include, $field;
		}
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		push @$fields_to_include, $_->{'name'} foreach @$attributes;
	}
	return ($fields_to_include);
}

sub get_title {
	my ($self) = @_;
	my $table  = $self->{'cgi'}->param('table');
	my $type   = $self->get_record_name($table) || '';
	return "Batch add $type records";
}

#Return list of fields in order
sub _get_fields_in_order {
	my ( $self, $table, $locus ) = @_;
	my @fields;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		my $set_id     = $self->get_set_id;
		my $field_list = $self->{'xmlHandler'}->get_field_list;
		foreach my $field (@$field_list) {
			my $att = $self->{'xmlHandler'}->get_field_attributes($field);
			next if ( $att->{'no_curate'} // '' ) eq 'yes';
			push @fields, $field;
			if ( $field eq $self->{'system'}->{'labelfield'} ) {
				push @fields, 'aliases';
				if ( ( $self->{'system'}->{'alternative_codon_tables'} // q() ) eq 'yes' ) {
					push @fields, 'codon_table';
				}
				push @fields, 'references';
			}
		}
		my $eav_fields = $self->{'datastore'}->get_eav_fieldnames;
		push @fields, @$eav_fields           if @$eav_fields;
		push @fields, REQUIRED_GENOME_FIELDS if $self->_in_genome_submission;
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		foreach my $att (@$attributes) {
			push @fields, $att->{'name'};
			if ( $table eq 'loci' && $att->{'name'} eq 'id' ) {
				push @fields, 'aliases';
			}
		}
	}
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' && $table eq 'loci' ) {
		push @fields, qw(full_name product description);
	}
	return \@fields;
}

sub _in_genome_submission {
	my ($self)        = @_;
	my $q             = $self->{'cgi'};
	my $submission_id = $q->param('submission_id');
	return if !$submission_id;
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	return   if !$submission;
	return 1 if $submission->{'type'} eq 'genomes';
	return;
}

sub _get_field_table_header {
	my ( $self, $table ) = @_;
	my @headers;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		my $set_id     = $self->get_set_id;
		my $field_list = $self->{'xmlHandler'}->get_field_list;
		foreach my $field (@$field_list) {
			my $att = $self->{'xmlHandler'}->get_field_attributes($field);
			next if ( $att->{'no_curate'} // '' ) eq 'yes';
			push @headers, $field;
			if ( $field eq $self->{'system'}->{'labelfield'} ) {
				push @headers, 'aliases';
				if ( ( $self->{'system'}->{'alternative_codon_tables'} // q() ) eq 'yes' ) {
					push @headers, 'codon_table';
				}
				push @headers, 'references';
			}
		}
		my $eav_fields = $self->{'datastore'}->get_eav_fieldnames;
		push @headers, @$eav_fields           if @$eav_fields;
		push @headers, REQUIRED_GENOME_FIELDS if $self->_in_genome_submission;
		push @headers, 'loci';
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		foreach (@$attributes) {
			push @headers, $_->{'name'};
			if ( $table eq 'loci' && $_->{'name'} eq 'id' ) {
				push @headers, 'aliases';
			}
		}
		if ( $self->{'system'}->{'dbtype'} eq 'sequences' && $table eq 'loci' ) {
			push @headers, qw(full_name product description);
		}
	}
	local $" = q(</th><th>);
	return qq(<th>@headers</th>);
}

sub _is_id_used {
	my ( $self, $table, $id ) = @_;
	if ( $table eq 'isolates' ) {
		my $qry =
			'SELECT EXISTS(SELECT * FROM isolates WHERE id=?) OR '
		  . 'EXISTS(SELECT * FROM retired_isolates WHERE isolate_id=?)';
		return $self->{'datastore'}->run_query( $qry, [ $id, $id ], { cache => "CurateBatchAdd::is_id_used::$table" } );
	}
	my $qry = "SELECT EXISTS(SELECT * FROM $table WHERE id=?)";
	return $self->{'datastore'}->run_query( $qry, $id, { cache => "CurateBatchAdd::is_id_used::$table" } );
}

sub _convert_query {
	my ( $self, $table, $qry ) = @_;
	return if !$self->{'datastore'}->is_table($table);
	if ( any { lc($qry) =~ /;\s*$_\s/x } (qw (insert delete update alter create drop)) ) {
		$logger->warn("Malicious SQL injection attempt '$qry'");
		return;
	}
	my $data;
	if ( $table eq 'project_members' ) {
		my $project_id = $self->{'cgi'}->param('project');
		$data = "project_id\tisolate_id\n";
		$qry =~ s/SELECT\ \*/SELECT id/x;
		$qry =~ s/ORDER\ BY\ .*/ORDER BY id/x;
		my $ids = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
		$data .= "$project_id\t$_\n" foreach (@$ids);
	}
	return $data;
}

sub _set_submission_params {
	my ( $self, $submission_id ) = @_;
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	return if !$submission;
	my $q = $self->{'cgi'};
	$q->param( sender => $submission->{'submitter'} );
	if ( $q->param('table') eq 'isolates' ) {
		my $submission_file = "$self->{'config'}->{'submission_dir'}/$submission_id/isolates.txt";
		if ( -e $submission_file ) {
			my $data_ref = BIGSdb::Utils::slurp($submission_file);
			$q->param( data => $$data_ref );
		}
	}
	return;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery noCache allowExpand);
	my $q = $self->{'cgi'};
	if ( $q->param('query') || $q->param('data') || $q->param('checked_buffer') ) {
		$self->{'processing'} = 1;
	}
	$self->set_level1_breadcrumbs;
	return;
}
1;
