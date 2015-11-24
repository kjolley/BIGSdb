#Written by Keith Jolley
#Copyright (c) 2010-2015, University of Oxford
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
use BIGSdb::Constants qw(SEQ_STATUS ALLELE_FLAGS DIPLOID HAPLOID MAX_POSTGRES_COLS);
use BIGSdb::Utils;
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub get_help_url {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $table  = $q->param('table');
	return if !defined $table;
	if ( $table eq 'sequences' ) {
		return "$self->{'config'}->{'doclink'}/curator_guide.html#batch-adding-multiple-alleles";
	}
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $table         = $q->param('table') // q();
	my $cleaned_table = $table;
	my $locus         = $q->param('locus');
	$cleaned_table =~ tr/_/ /;
	my $sample_field_list = $self->{'xmlHandler'}->get_sample_field_list;
	if ( !$self->{'datastore'}->is_table($table) && !( $table eq 'samples' && @$sample_field_list ) ) {
		say q(<h1>Batch insert records</h1>);
		say qq(<div class="box" id="statusbad"><p>Table $table does not exist!</p></div>);
		return;
	}
	if ( $table eq 'sequences' && $locus ) {
		if ( !$self->{'datastore'}->is_locus($locus) ) {
			say q(<h1>Batch insert sequences</h1>);
			say qq(<div class="box" id="statusbad"><p>Locus $locus does not exist!</p></div>);
			return;
		}
		my $cleaned_locus = $self->clean_locus($locus);
		say qq(<h1>Batch insert $cleaned_locus sequences</h1>);
	} else {
		say qq(<h1>Batch insert $cleaned_table</h1>);
	}
	if ( !$self->can_modify_table($table) ) {
		say q(<div class="box" id="statusbad"><p>Your user account is not allowed to add records )
		  . qq(to the $table table.</p></div>);
		return;
	}
	my %table_message = (
		sequence_bin     => 'You cannot use this interface to add sequences to the bin.',
		allele_sequences => 'Tag allele sequences using the scan interface.'
	);
	if ( $table_message{$table} ) {
		say qq(<div class="box" id="statusbad">$table_message{$table}</p></div>);
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
		$self->{'datastore'}->create_temp_list_table( $q->param('datatype'), $q->param('list_file') );
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
			$self->_set_submission_params( $q->param('submission_id') );
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
	say qq(<div class="box" id="queryform"><div class="scrollable"><p>This page allows you to upload $record_name )
	  . q(data as tab-delimited text or copied from a spreadsheet.</p>);
	say q(<ul><li>Field header names must be included and fields can be in any order. Optional fields can be )
	  . q(omitted if you wish.</li>);
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		say q[<li>Enter aliases (alternative names) for your isolates as a semi-colon (;) separated list.</li>];
		say q[<li>Enter references for your isolates as a semi-colon (;) separated list of PubMed ids (non-integer ]
		  . q[ids will be ignored).</li>];
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
	my $locus_attribute = '';
	if ( $table eq 'sequences' ) {
		$locus_attribute = "&amp;locus=$arg_ref->{'locus'}" if $arg_ref->{'locus'};
		my @status = SEQ_STATUS;
		local $" = q(', ');
		say q(<li>If the locus uses integer allele ids you can leave the allele_id )
		  . q(field blank and the next available number will be used.</li>)
		  . qq(<li>The status defines how the sequence was curated.  Allowed values are: '@status'.</li>);
		if ( $self->{'system'}->{'allele_flags'} ) {
			say q(<li>Sequence flags can be added as a semi-colon (;) separated list.</li>);
		}
	}
	say qq(</ul><ul><li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=tableHeader&amp;table=$table$locus_attribute">Download tab-delimited header for your spreadsheet</a>)
	  . q( - use 'Paste Special <span class="fa fa-arrow-circle-right"></span> Text' to paste the data.</li>);
	say
	  qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=excelTemplate&amp;table=$table)
	  . qq($locus_attribute">Download submission template (xlsx format)</a>);
	if ( $table eq 'sequences' && !$q->param('locus') ) {
		$self->_print_interface_locus_selection;
	}
	print "</ul>\n";
	print $q->start_form;
	if ( $arg_ref->{'has_sender_field'} ) {
		$self->_print_interface_sender_field;
	}
	if ( $table eq 'sequences' ) {
		$self->_print_interface_sequence_switches;
	}
	say q(<fieldset style="float:left"><legend>Paste in tab-delimited text )
	  . q((<strong>include a field header line</strong>).</legend>);
	say $q->textarea( -name => 'data', -rows => 20, -columns => 80 );
	say q(</fieldset>);
	say $q->hidden($_) foreach qw (page db table locus submission_id);
	$self->print_action_fieldset( { table => $table } );
	say $q->end_form;
	say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back</a></p>);
	say q(</div></div>);
	return;
}

sub _print_interface_sender_field {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	if ( $user_info->{'status'} eq 'submitter' ) {
		say $q->hidden( sender => $user_info->{'id'} );
		return;
	}
	my ( $users, $user_names ) = $self->get_user_list_and_labels( { blank_message => 'Select sender ...' } );
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

sub _print_interface_locus_selection {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $set_id = $self->get_set_id;
	my $qry    = 'SELECT DISTINCT locus FROM locus_extended_attributes ';
	if ($set_id) {
		$qry .= 'WHERE locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM '
		  . "set_schemes WHERE set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id) ";
	}
	$qry .= 'ORDER BY locus';
	my $loci_with_extended = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	if (@$loci_with_extended) {
		say q(<li>Please note, some loci have extended attributes which may be required.  For affected loci please )
		  . q(use the batch insert page specific to that locus: );
		if ( @$loci_with_extended > 10 ) {
			say $q->start_form;
			say $q->hidden($_) foreach qw (page db table);
			say 'Reload page specific for locus: ';
			my @values = @$loci_with_extended;
			my %labels;
			unshift @values, '';
			$labels{''} = 'Select ...';
			say $q->popup_menu( -name => 'locus', -values => \@values, -labels => \%labels );
			say $q->submit( -name => 'Reload', -class => 'submit' );
			say $q->end_form;
		} else {
			my $first = 1;
			foreach my $locus (@$loci_with_extended) {
				print ' | ' if !$first;
				say qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;)
				  . qq(table=sequences&amp;locus=$locus">$locus</a>);
				$first = 0;
			}
		}
		say q(</li>);
	}
	return;
}

sub _print_interface_sequence_switches {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<ul style="list-style-type:none"><li>);
	my $ignore_existing = $q->param('ignore_existing') // 'checked';
	say $q->checkbox(
		-name    => 'ignore_existing',
		-label   => 'Ignore existing or duplicate sequences',
		-checked => $ignore_existing
	);
	say q(</li><li>);
	say $q->checkbox( -name => 'ignore_non_DNA', -label => 'Ignore sequences containing non-nucleotide characters' );
	say q(</li><li>);
	say $q->checkbox(
		-name => 'complete_CDS',
		-label =>
		  'Silently reject all sequences that are not complete reading frames - these must have a start and in-frame '
		  . 'stop codon at the ends and no internal stop codons.  Existing sequences are also ignored.'
	);
	say q(</li><li>);
	say $q->checkbox( -name => 'ignore_similarity', -label => 'Override sequence similarity check' );
	say q(</li></ul>);
	return;
}

sub _check_data {
	my ( $self,  $args )  = @_;
	my ( $table, $locus ) = @{$args}{qw (table locus)};
	my $q = $self->{'cgi'};
	if ( !$q->param('data') ) {
		$q->param( 'data', $self->_convert_query( $q->param('table'), $q->param('query') ) );
	}
	my @checked_buffer;
	my @fieldorder = $self->_get_fields_in_order($table);
	my $extended_attributes;
	my $required_extended_exist;
	my %last_id;
	if ( $table eq 'sequences' ) {
		push @fieldorder, 'flags' if ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes';
		if ($locus) {
			my $ext_att = $self->{'datastore'}->run_query(
				'SELECT field,value_format,value_regex,required,option_list FROM '
				  . 'locus_extended_attributes WHERE locus=? ORDER BY field_order',
				$locus,
				{ fetch => 'all_arrayref' }
			);
			foreach (@$ext_att) {
				my ( $field, $format, $regex, $required, $optlist ) = @$_;
				push @fieldorder, $field;
				$extended_attributes->{$field}->{'format'}      = $format;
				$extended_attributes->{$field}->{'regex'}       = $regex;
				$extended_attributes->{$field}->{'required'}    = $required;
				$extended_attributes->{$field}->{'option_list'} = $optlist;
			}
		} else {
			$required_extended_exist =
			  $self->{'datastore'}->run_query( 'SELECT DISTINCT locus FROM locus_extended_attributes WHERE required',
				undef, { fetch => 'col_arrayref' } );
		}
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' && $table eq 'loci' ) {
		push @fieldorder, qw(full_name product description);
	}
	my $sender_message = q();
	if ( $args->{'has_sender_field'} ) {
		my $sender = $q->param('sender');
		if ( !BIGSdb::Utils::is_int($sender) ) {
			say q(<div class="box" id="statusbad"><p>Please go back and select the sender )
			  . q(for this submission.</p></div>);
			return;
		}
		if ( $sender == -1 ) {
			$sender_message = qq(<p>Using sender field in pasted data.</p>\n);
		} else {
			my $sender_ref = $self->{'datastore'}->get_user_info($sender);
			$sender_message = qq(<p>Sender: $sender_ref->{'first_name'} $sender_ref->{'surname'}</p>\n);
		}
	}
	my ( %problems, %advisories );
	my $table_header = $self->_get_field_table_header($table);
	my $tablebuffer  = qq(<div class="scrollable"><table class="resultstable"><tr>$table_header</tr>);
	my @records      = split /\n/x, $q->param('data');
	my $td           = 1;
	my $header;
	while ( $header = shift @records ) {    #ignore blank lines before header
		$header =~ s/\r//gx;
		last if $header ne q();
	}
	my @file_header_fields = split /\t/x, $header;
	my %file_header_pos;
	my $pos = 0;
	foreach (@file_header_fields) {
		$file_header_pos{$_} = $pos;
		$pos++;
	}
	my $id;
	my %unique_field;
	my $label_field_values;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		$id                 = $self->next_id($table);
		$label_field_values = $self->_get_existing_label_field_values;
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		foreach (@$attributes) {
			if ( $_->{'name'} eq 'id' && $_->{'type'} eq 'int' ) {
				$id = $self->next_id($table);
			}
			if ( $_->{'unique'} && $_->{'unique'} eq 'yes' ) {
				$unique_field{ $_->{'name'} } = 1;
			}
		}
	}
	my @primary_keys = $self->{'datastore'}->get_primary_keys($table);
	my ( %locus_format, %locus_regex, $header_row, $header_complete, $record_count );
	my $first_record = 1;
	foreach my $record (@records) {
		$record =~ s/\r//gx;
		next if $record =~ /^\s*$/x;
		my @profile;
		my $checked_record;
		if ($record) {
			my @data = split /\t/x, $record;
			BIGSdb::Utils::remove_trailing_spaces_from_list( \@data );
			my $first = 1;
			if ( !defined $file_header_pos{'id'} && $args->{'uses_integer_id'} && !$first_record ) {
				do { $id++ } while ( $self->_is_id_used( $table, $id ) );
			}
			my ( $pk_combination, $pk_values_ref ) = $self->_get_primary_key_values(
				{
					primary_keys    => \@primary_keys,
					file_header_pos => \%file_header_pos,
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
			foreach my $field (@fieldorder) {

				#Prepare checked header
				if ( !$header_complete && ( defined $file_header_pos{$field} || $field eq 'id' ) ) {
					$header_row .= "$field\t";
				}

				#Check individual values for correctness.
				my $value = $self->_extract_value(
					{
						field               => $field,
						data                => \@data,
						id                  => $id,
						file_header_pos     => \%file_header_pos,
						extended_attributes => $extended_attributes
					}
				);
				my $special_problem;
				my $new_args = {
					locus                   => $locus,
					field                   => $field,
					value                   => \$value,
					file_header_pos         => \%file_header_pos,
					data                    => \@data,
					required_extended_exist => $required_extended_exist,
					pk_combination          => $pk_combination,
					problems                => \%problems,
					special_problem         => \$special_problem,
					continue                => \$continue,
					last_id                 => \%last_id,
					extended_attributes     => $extended_attributes,
					unique_field            => \%unique_field
				};
				$self->_check_data_duplicates($new_args);
				my %further_checks = (
					sequences => sub {
						$file_header_pos{'allele_id'} = keys %file_header_pos if !defined $file_header_pos{'allele_id'};
						$self->_check_data_sequences($new_args);
					},
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
						$self->_check_data_aliases($new_args);
					},
					scheme_fields => sub {
						$self->_check_data_scheme_fields($new_args);
					},
					isolate_aliases => sub {
						$self->_check_data_isolate_aliases($new_args);
					},
					retired_allele_ids => sub {
						$self->_check_retired_allele_ids($new_args);
					}
				);
				$further_checks{$table}->() if $further_checks{$table};

				#Display field - highlight in red if invalid.
				my $display_value;
				if ( $field =~ /sequence/ && $field ne 'coding_sequence' ) {
					$value //= '';
					$display_value =
					  q(<span class="seq">) . ( BIGSdb::Utils::truncate_seq( \$value, 40 ) ) . q(</span>);
				} else {
					$display_value = $value;
				}
				my $problem;
				if ( !( $table eq 'sequences' && $field eq 'allele_id' && defined $problems{$pk_combination} ) ) {
					my $set_id = $self->get_set_id;
					$problem = $self->{'submissionHandler'}->is_field_bad( $table, $field, $value, 'insert', $set_id );
				}
				$display_value =~ s/&/&amp;/gx if defined $display_value;
				if ( !( $problem || $special_problem ) ) {
					if ( $table eq 'sequences' && $field eq 'flags' ) {
						my @flags = split /;/x, ( $display_value // q() );
						local $" = q(</a> <a class="seqflag_tooltip">);
						$display_value = qq(<a class="seqflag_tooltip">@flags</a>) if @flags;
					}
					$rowbuffer .= defined $display_value ? qq(<td>$display_value</td>) : q(<td></td>);
				} else {
					$rowbuffer .=
					  defined $display_value ? qq(<td><font color="red">$display_value</font></td>) : q(<td></td>);
					if ($problem) {
						my $problem_text = "$field $problem<br />";
						$problems{$pk_combination} .= $problem_text
						  if !defined $problems{$pk_combination} || $problems{$pk_combination} !~ /$problem_text/x;
					}
				}
				$value = defined $value ? $value : '';
				$checked_record .= "$value\t"
				  if defined $file_header_pos{$field}
				  or ( $field eq 'id' );
			}
			if ( !$continue ) {
				undef $header_row if $first_record;
				next;
			}
			$tablebuffer .= qq(<tr class="td$td">$rowbuffer);
			my $new_args = {
				file_header_fields => \@file_header_fields,
				header_row         => \$header_row,
				first_record       => $first_record,
				file_header_pos    => \%file_header_pos,
				data               => \@data,
				locus_format       => \%locus_format,
				locus_regex        => \%locus_regex,
				primary_keys       => \@primary_keys,
				pk_combination     => $pk_combination,
				pk_values          => $pk_values_ref,
				problems           => \%problems,
				advisories         => \%advisories,
				checked_record     => \$checked_record,
				table              => $table
			};
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {

				#Check for locus values that can also be uploaded with an isolate record.
				$tablebuffer .= $self->_check_data_isolate_record_locus_fields($new_args);

				#Check if a record with the same name already exists
				if ( defined $file_header_pos{ $self->{'system'}->{'labelfield'} }
					&& $label_field_values->{ $data[ $file_header_pos{ $self->{'system'}->{'labelfield'} } ] } )
				{
					$advisories{$pk_combination} .= "$self->{'system'}->{'labelfield'} "
					  . "'$data[$file_header_pos{$self->{'system'}->{'labelfield'}}]' already exists in the database.";
				}
			}
			$header_complete = 1;
			push @checked_buffer, $header_row if $first_record;
			$first_record = 0;
			$tablebuffer .= "</tr>\n";

			#Check for various invalid combinations of fields
			if ( $table ne 'sequences' ) {
				my $skip_record = 0;
				try {
					$self->_check_data_primary_key($new_args);
				}
				catch BIGSdb::DataException with {
					$continue = 0;
				}
				catch BIGSdb::DataWarning with {
					$skip_record = 1;
				};
				last if !$continue;
				next if $skip_record;
			}

			#Check that sequence exists when adding accession or PubMed number
			my %seq_accession_table = map { $_ => 1 } qw (accession sequence_refs);
			if ( $self->{'system'}->{'dbtype'} eq 'sequences' && $seq_accession_table{$table} ) {
				if ( !$self->{'datastore'}->sequence_exists(@$pk_values_ref) ) {
					$problems{$pk_combination} .= "Sequence $pk_values_ref->[0]-$pk_values_ref->[1] does not exist.";
				}
			} elsif ( $table eq 'loci' ) {
				$self->_check_data_loci($new_args);
			}
			my %seq_table = map { $_ => 1 } qw (sequences retired_allele_ids sequence_refs accession);

			#check that user is allowed to add sequences for this locus
			if ( $seq_table{$table} && $self->{'system'}->{'dbtype'} eq 'sequences' && !$self->is_admin ) {
				if ( !defined $locus && defined $file_header_pos{'locus'} && $data[ $file_header_pos{'locus'} ] ) {
					$locus = $data[ $file_header_pos{'locus'} ];
				}
				if ( defined $locus
					&& !$self->{'datastore'}->is_allowed_to_modify_locus_sequences( $locus, $self->get_curator_id ) )
				{
					$problems{$pk_combination} .=
					  "Your user account is not allowed to add or modify sequences for locus $locus.";
				}
			}
		}
		$td = $td == 1 ? 2 : 1;    #row stripes
		$checked_record =~ s/\t$//x if defined $checked_record;
		push @checked_buffer, $checked_record;
	}
	$tablebuffer .= q(</table></div>);
	if ( !$record_count ) {
		say q(<div class="box" id="statusbad"><p>No valid data entered. Make sure )
		  . q(you've included the header line.</p></div>);
		return;
	}
	$self->_report_check(
		{
			table          => $table,
			buffer         => \$tablebuffer,
			problems       => \%problems,
			advisories     => \%advisories,
			checked_buffer => \@checked_buffer,
			sender_message => \$sender_message
		}
	);
	return;
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
	my $q = $self->{'cgi'};
	if (%$problems) {
		say q(<div class="box" id="statusbad"><h2>Import status</h2>);
		say q(<table class="resultstable">);
		say q(<tr><th>Primary key</th><th>Problem(s)</th></tr>);
		my $td = 1;
		foreach my $id ( sort keys %$problems ) {
			say qq(<tr class="td$td"><td>$id</td><td style="text-align:left">$problems->{$id}</td></tr>);
			$td = $td == 1 ? 2 : 1;    #row stripes
		}
		say q(</table></div>);
	} else {
		say qq(<div class="box" id="resultsheader"><h2>Import status</h2>$$sender_message);
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
		say $q->hidden($_) foreach qw (page table db sender locus ignore_existing ignore_non_DNA
		  complete_CDS ignore_similarity submission_id);
		say $q->hidden( checked_buffer => $filename );
		$self->print_action_fieldset( { submit_label => 'Import data', no_reset => 1 } );
		say $q->endform;
		say q(</div>);
	}
	say q(<div class="box" id="resultstable"><h2>Data to be imported</h2>);
	my $caveat =
	  ( $table eq 'sequences' && ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' )
	  ? '<em>Note: valid sequence flags are displayed with a red background not red text.</em>'
	  : q();
	say q(<p>The following table shows your data.  Any field with red text has a )
	  . qq(problem and needs to be checked. $caveat</p>);
	say $$buffer;
	say q(</div>);
	return;
}

sub _extract_value {
	my ( $self, $arg_ref ) = @_;
	my $q               = $self->{'cgi'};
	my $field           = $arg_ref->{'field'};
	my @data            = @{ $arg_ref->{'data'} };
	my %file_header_pos = %{ $arg_ref->{'file_header_pos'} };
	my $value;
	if ( $field eq 'id' ) {
		$value = $arg_ref->{'id'};
	}
	if ( $field eq 'datestamp' || $field eq 'date_entered' ) {
		$value = BIGSdb::Utils::get_datestamp();
	} elsif ( $field eq 'sender' ) {
		if ( defined $file_header_pos{$field} ) {
			$value = $data[ $file_header_pos{$field} ];
		} else {
			$value = $q->param('sender')
			  if $q->param('sender') != -1;
		}
	} elsif ( $field eq 'curator' ) {
		$value = $self->get_curator_id;
	} elsif ( $arg_ref->{'extended_attributes'}->{$field}->{'format'}
		&& $arg_ref->{'extended_attributes'}->{$field}->{'format'} eq 'boolean' )
	{
		if ( defined $file_header_pos{$field} ) {
			$value = $data[ $file_header_pos{$field} ];
			$value = lc($value);
		}
	} else {
		if ( defined $file_header_pos{$field} ) {
			$value = $data[ $file_header_pos{$field} ];
		}
	}
	return $value;
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
			} else {
				if ( $arg_ref->{'table'} eq 'sequences' && $arg_ref->{'locus'} && $_ eq 'locus' ) {
					push @pk_values, $arg_ref->{'locus'};
					$pk_combination .= "$_: " . BIGSdb::Utils::pad_length( $arg_ref->{'locus'}, 10 );
				} else {
					$pk_combination .= '; ' if $pk_combination;
					$pk_combination .= "$_: undef";
				}
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
	if ( $field eq 'status' ) {
		if ( defined $value && $value ne 'user' && !$self->is_admin ) {
			my $problem_text = q(Only a user with admin status can add a user with a status other than 'user'.<br />);
			$arg_ref->{'problems'}->{$pk_combination} .= $problem_text
			  if !defined $arg_ref->{'problems'}->{$pk_combination}
			  || $arg_ref->{'problems'}->{$pk_combination} !~ /$problem_text/x;
			${ $arg_ref->{'special_problem'} } = 1;
		}
	}
	return;
}

sub _check_data_scheme_fields {

	#special case to prevent a new user with curator or admin status unless user is admin themselves
	my ( $self, $arg_ref ) = @_;
	my $field          = $arg_ref->{'field'};
	my $value          = ${ $arg_ref->{'value'} };
	my $pk_combination = $arg_ref->{'pk_combination'};
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

	#special case to check that references are added as list of integers
	my ( $self, $arg_ref ) = @_;
	my $field          = $arg_ref->{'field'};
	my $value          = ${ $arg_ref->{'value'} };
	my $pk_combination = $arg_ref->{'pk_combination'};
	if ( $field eq 'references' ) {
		if ( defined $value ) {
			$value =~ s/\s//gx;
			my @refs = split /;/x, $value;
			foreach my $ref (@refs) {
				if ( !BIGSdb::Utils::is_int($ref) ) {
					my $problem_text = "References are PubMed ids - $ref is not an integer.<br />";
					$arg_ref->{'problems'}->{$pk_combination} .= $problem_text;
					${ $arg_ref->{'special_problem'} } = 1;
				}
			}
		}
	}
	return;
}

sub _check_data_aliases {

	#special case to check that isolate aliases don't duplicate isolate name when batch uploaded isolates
	my ( $self, $arg_ref ) = @_;
	my $field          = $arg_ref->{'field'};
	my $value          = ${ $arg_ref->{'value'} };
	my $pk_combination = $arg_ref->{'pk_combination'};
	if ( $field eq 'aliases' ) {
		my $isolate_name = $arg_ref->{'data'}->[ $arg_ref->{'file_header_pos'}->{ $self->{'system'}->{'labelfield'} } ];
		if ( defined $value && defined $isolate_name ) {
			$value =~ s/\s//gx;
			my @aliases = split /;/x, $value;
			foreach my $alias (@aliases) {
				$alias =~ s/\s+$//x;
				$alias =~ s/^\s+//x;
				next if $alias eq '';
				if ( $alias eq $isolate_name ) {
					my $problem_text = 'Aliases are ALTERNATIVE names for the isolate name.<br />';
					$arg_ref->{'problems'}->{$pk_combination} .= $problem_text;
					${ $arg_ref->{'special_problem'} } = 1;
					last;
				}
			}
		}
	}
	return;
}

sub _check_data_isolate_aliases {

	#special case to check that isolate aliases don't duplicate isolate name when batch uploading isolate aliases
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
				say qq(<div class="box" id="statusbad"><p>Your pasted data has invalid primary key field$plural )
				  . qq((@primary_keys) data.</p></div>);
				throw BIGSdb::DataException('Invalid primary key');
			}
			say q(<div class="box" id="statusbad"><p>Your pasted data does not appear to contain the primary )
			  . qq(key field$plural (@primary_keys) required for this table.</p></div>);
			throw BIGSdb::DataException("no primary key field$plural (@primary_keys)");
		}
		my ($exists) = $self->{'sql'}->{'primary_key_check'}->fetchrow_array;
		if ($exists) {
			my %warn_tables = map { $_ => 1 } qw(project_members refs isolate_aliases locus_aliases);
			if ( $warn_tables{ $arg_ref->{'table'} } ) {
				my $warning_text = 'Primary key already exists in the database - upload will be skipped.<br />';
				if ( !defined $arg_ref->{'problems'}->{$pk_combination}
					|| $arg_ref->{'advisories'}->{$pk_combination} !~ /$warning_text/x )
				{
					$arg_ref->{'advisories'}->{$pk_combination} .= $warning_text;
					throw BIGSdb::DataWarning('Primary key already exists.');
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
	if ( $data[ $file_header_pos{'id'} ] =~ /^\d/x ) {
		$arg_ref->{'problems'}->{$pk_combination} .=
		    'Locus names can not start with a digit.  Try prepending an underscore (_) '
		  . 'which will get hidden in the query interface.<br />';
	}
	if ( $data[ $file_header_pos{'id'} ] =~ /[^\w_']/x ) {
		$arg_ref->{'problems'}->{$pk_combination} .=
		    q(Locus names can only contain alphanumeric, underscore (_) )
		  . q(and prime (') characters (no spaces or other symbols).<br />);
	}
	return;
}

sub _check_data_duplicates {

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

sub _check_data_sequences {
	my ( $self, $arg_ref ) = @_;
	my $field           = $arg_ref->{'field'};
	my $pk_combination  = $arg_ref->{'pk_combination'};
	my %file_header_pos = %{ $arg_ref->{'file_header_pos'} };
	my @data            = @{ $arg_ref->{'data'} };
	my $q               = $self->{'cgi'};
	my $buffer;
	my $locus;

	if ( $field eq 'locus' && $q->param('locus') ) {
		${ $arg_ref->{'value'} } = $q->param('locus');
	}
	if ( $q->param('locus') ) {
		$locus = $q->param('locus');
	} else {
		$locus =
		  ( defined $file_header_pos{'locus'} && defined $data[ $file_header_pos{'locus'} ] )
		  ? $data[ $file_header_pos{'locus'} ]
		  : undef;
	}
	if ( defined $locus && $field eq 'allele_id' ) {
		if (   defined $file_header_pos{'locus'}
			&& $data[ $file_header_pos{'locus'} ]
			&& any { $_ eq $data[ $file_header_pos{'locus'} ] } @{ $arg_ref->{'required_extended_exist'} } )
		{
			$buffer .= qq(Locus $locus has required extended attributes - please use specific )
			  . q(batch upload form for this locus.<br />);
		}
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		if (
			   defined $locus_info->{'allele_id_format'}
			&& $locus_info->{'allele_id_format'} eq 'integer'
			&& (   !defined $file_header_pos{'allele_id'}
				|| !defined $data[ $file_header_pos{'allele_id'} ]
				|| $data[ $file_header_pos{'allele_id'} ] eq '' )
		  )
		{
			if ( $arg_ref->{'last_id'}->{$locus} ) {
				${ $arg_ref->{'value'} } = $arg_ref->{'last_id'}->{$locus};
			} else {
				${ $arg_ref->{'value'} } = $self->{'datastore'}->get_next_allele_id($locus) - 1;
			}
			my $exists;
			do {
				${ $arg_ref->{'value'} }++;
				$exists = $self->{'datastore'}->run_query(
					'SELECT EXISTS(SELECT * FROM sequences WHERE (locus,allele_id)=(?,?))',
					[ $locus, ${ $arg_ref->{'value'} } ],
					{ cache => 'CurateBatchAddPage::allele_id_exists' }
				);
			} while $exists;
			$arg_ref->{'last_id'}->{$locus} = ${ $arg_ref->{'value'} };
		} elsif ( defined $file_header_pos{'allele_id'}
			&& !BIGSdb::Utils::is_int( $data[ $file_header_pos{'allele_id'} ] )
			&& defined $locus_info->{'allele_id_format'}
			&& $locus_info->{'allele_id_format'} eq 'integer' )
		{
			$buffer .= 'Allele id must be an integer.<br />';
		}
		my $regex = $locus_info->{'allele_id_regex'};
		if ( $regex && $data[ $file_header_pos{'allele_id'} ] !~ /$regex/x ) {
			$buffer .= "Allele id value is invalid - it must match the regular expression /$regex/.<br />";
		}
		if ( $data[ $file_header_pos{'allele_id'} ] ) {
			my $exists = $self->{'datastore'}->run_query(
				'SELECT EXISTS(SELECT * FROM sequences WHERE (locus,allele_id)=(?,?))',
				[ $locus, $data[ $file_header_pos{'allele_id'} ] ],
				{ cache => 'CurateBatchAddPage::allele_id_exists' }
			);
			if ($exists) {
				$buffer .= 'Allele id already exists.<br />';
			}
			my $retired =
			  $self->{'datastore'}
			  ->run_query( 'SELECT EXISTS(SELECT * FROM retired_allele_ids WHERE (locus,allele_id)=(?,?))',
				[ $locus, $data[ $file_header_pos{'allele_id'} ] ] );
			if ($retired) {
				$buffer .= 'Allele id has been retired.<br />';
			}
		}
	}

	#special case to check for sequence length in sequences table, and that sequence doesn't already exist
	#and is similar to existing.
	if ( defined $locus && $field eq 'sequence' ) {
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		${ $arg_ref->{'value'} } //= '';
		${ $arg_ref->{'value'} } =~ s/ //g;
		my $length = length( ${ $arg_ref->{'value'} } );
		my $units = ( !defined $locus_info->{'data_type'} || $locus_info->{'data_type'} eq 'DNA' ) ? 'bp' : 'residues';
		if ( $length == 0 ) {
			${ $arg_ref->{'continue'} } = 0;
		} elsif ( !$locus_info->{'length_varies'}
			&& defined $locus_info->{'length'}
			&& $locus_info->{'length'} != $length )
		{
			my $problem_text =
			    "Sequence is $length $units long but this locus is set as a standard length of "
			  . "$locus_info->{'length'} $units.<br />";
			$buffer .= $problem_text
			  if !$buffer || $buffer !~ /$problem_text/x;
			${ $arg_ref->{'special_problem'} } = 1;
		} elsif ( $locus_info->{'min_length'} && $length < $locus_info->{'min_length'} ) {
			my $problem_text = "Sequence is $length $units long but this locus is set with a minimum length of "
			  . "$locus_info->{'min_length'} $units.<br />";
			$buffer .= $problem_text;
		} elsif ( $locus_info->{'max_length'} && $length > $locus_info->{'max_length'} ) {
			my $problem_text = "Sequence is $length $units long but this locus is set with a maximum length of "
			  . "$locus_info->{'max_length'} $units.<br />";
			$buffer .= $problem_text;
		} elsif ( defined $file_header_pos{'allele_id'}
			&& defined $data[ $file_header_pos{'allele_id'} ]
			&& $data[ $file_header_pos{'allele_id'} ] =~ /\s/x )
		{
			$buffer .= 'Allele id must not contain spaces - try substituting with underscores (_).<br />';
		} elsif ( defined $locus ) {
			${ $arg_ref->{'value'} } = uc( ${ $arg_ref->{'value'} } );
			if ( !defined $locus_info->{'data_type'} || $locus_info->{'data_type'} eq 'DNA' ) {
				${ $arg_ref->{'value'} } =~ s/[\W]//gx;
			} else {
				${ $arg_ref->{'value'} } =~ s/[^GPAVLIMCFYWHKRQNEDST\*]//gx;
			}
			my $md5_seq = md5( ${ $arg_ref->{'value'} } );
			$self->{'unique_values'}->{$locus}->{$md5_seq}++;
			if ( $self->{'unique_values'}->{$locus}->{$md5_seq} > 1 ) {
				if ( $q->param('ignore_existing') ) {
					${ $arg_ref->{'continue'} } = 0;
				} else {
					$buffer .= 'Sequence appears more than once in this submission.<br />';
				}
			}
			my $exists = $self->{'datastore'}->run_query(
				'SELECT EXISTS(SELECT * FROM sequences WHERE (locus,sequence)=(?,?))',
				[ $locus, ${ $arg_ref->{'value'} } ],
				{ cache => 'CurateBatchAddPage::sequence_exists' }
			);
			if ($exists) {
				if ( $q->param('complete_CDS') || $q->param('ignore_existing') ) {
					${ $arg_ref->{'continue'} } = 0;
				} else {
					$buffer .= "Sequence already exists in the database ($locus: $exists).<br />";
				}
			}
			if ( $q->param('complete_CDS') ) {    #TODO Use BIGSdb::Utils::is_complete_cds
				my $first_codon = substr( ${ $arg_ref->{'value'} }, 0, 3 );
				${ $arg_ref->{'continue'} } = 0 if none { $first_codon eq $_ } qw (ATG GTG TTG);
				my $end_codon = substr( ${ $arg_ref->{'value'} }, -3 );
				${ $arg_ref->{'continue'} } = 0 if none { $end_codon eq $_ } qw (TAA TGA TAG);
				my $multiple_of_3 =
				  ( length( ${ $arg_ref->{'value'} } ) / 3 ) == int( length( ${ $arg_ref->{'value'} } ) / 3 )
				  ? 1
				  : 0;
				${ $arg_ref->{'continue'} } = 0 if !$multiple_of_3;
				my $internal_stop;
				for ( my $pos = 0 ; $pos < length( ${ $arg_ref->{'value'} } ) - 3 ; $pos += 3 ) {
					my $codon = substr( ${ $arg_ref->{'value'} }, $pos, 3 );
					if ( any { $codon eq $_ } qw (TAA TGA TAG) ) {
						$internal_stop = 1;
					}
				}
				${ $arg_ref->{'continue'} } = 0 if $internal_stop;
			}
		}
		if ( ${ $arg_ref->{'continue'} } ) {
			if (
				( !defined $locus_info->{'data_type'} || $locus_info->{'data_type'} eq 'DNA' )
				&& !BIGSdb::Utils::is_valid_DNA(
					${ $arg_ref->{'value'} },
					{ diploid => ( ( $self->{'system'}->{'diploid'} // '' ) eq 'yes' ? 1 : 0 ) }
				)
			  )
			{
				if ( $q->param('complete_CDS') || $q->param('ignore_non_DNA') ) {
					${ $arg_ref->{'continue'} } = 0;
				} else {
					my @chars = ( $self->{'system'}->{'diploid'} // '' ) eq 'yes' ? DIPLOID : HAPLOID;
					local $" = '|';
					$buffer .= "Sequence contains non nucleotide (@chars) characters.<br />";
				}
			} elsif ( ( !defined $locus_info->{'data_type'} || $locus_info->{'data_type'} eq 'DNA' )
				&& $self->{'datastore'}->sequences_exist($locus)
				&& !$q->param('ignore_similarity')
				&& !$self->{'datastore'}->is_sequence_similar_to_others( $locus, $arg_ref->{'value'} ) )
			{
				$buffer .=
				    q[Sequence is too dissimilar to existing alleles (less than 70% identical or an ]
				  . q[alignment of less than 90% its length). Similarity is determined by the output of the ]
				  . q[best match from the BLAST algorithm - this may be conservative.  The check will also fail ]
				  . q[if the best match is in the reverse orientation. If you're sure that this sequence should ]
				  . q[be entered, please select the 'Override sequence similarity check' ]
				  . q[box.<br />];
			}
		}
	}

	#check extended attributes if they exist
	if ( $arg_ref->{'extended_attributes'}->{$field} ) {
		my @optlist;
		my %options;
		if ( $arg_ref->{'extended_attributes'}->{$field}->{'option_list'} ) {
			@optlist = split /\|/x, $arg_ref->{'extended_attributes'}->{$field}->{'option_list'};
			foreach (@optlist) {
				$options{$_} = 1;
			}
		}
		if (
			$arg_ref->{'extended_attributes'}->{$field}->{'required'}
			&& (   !defined $file_header_pos{$field}
				|| !defined $data[ $file_header_pos{$field} ]
				|| $data[ $file_header_pos{$field} ] eq q() )
		  )
		{
			$buffer .= "'$field' is a required field and cannot be left blank.<br />";
		} elsif ( $arg_ref->{'extended_attributes'}->{$field}->{'option_list'}
			&& defined $file_header_pos{$field}
			&& defined $data[ $file_header_pos{$field} ]
			&& $data[ $file_header_pos{$field} ] ne ''
			&& !$options{ $data[ $file_header_pos{$field} ] } )
		{
			local $" = ', ';
			$buffer .= "Field '$field' value is not on the allowed list (@optlist).<br />";
		} elsif (
			$arg_ref->{'extended_attributes'}->{$field}->{'format'}
			&& $arg_ref->{'extended_attributes'}->{$field}->{'format'} eq 'integer'
			&& (   defined $file_header_pos{$field}
				&& defined $data[ $file_header_pos{$field} ]
				&& $data[ $file_header_pos{$field} ] ne '' )
			&& !BIGSdb::Utils::is_int( $data[ $file_header_pos{$field} ] )
		  )
		{
			$buffer .= "Field '$field' must be an integer.<br />";
		} elsif (
			$arg_ref->{'extended_attributes'}->{$field}->{'format'}
			&& $arg_ref->{'extended_attributes'}->{$field}->{'format'} eq 'boolean'
			&& (   defined $file_header_pos{$field}
				&& lc( $data[ $file_header_pos{$field} ] ) ne 'false'
				&& lc( $data[ $file_header_pos{$field} ] ) ne 'true' )
		  )
		{
			$buffer .= "Field '$field' must be boolean (either true or false).<br />";
		} elsif ( defined $file_header_pos{$field}
			&& defined $data[ $file_header_pos{$field} ]
			&& $data[ $file_header_pos{$field} ] ne ''
			&& $arg_ref->{'extended_attributes'}->{$field}->{'regex'}
			&& $data[ $file_header_pos{$field} ] !~ /$arg_ref->{'extended_attributes'}->{$field}->{'regex'}/x )
		{
			$buffer .= "Field '$field' does not conform to specified format.<br />\n";
		}
	}

	#check sequence flags
	if (   ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes'
		&& $field eq 'flags'
		&& defined $file_header_pos{'flags'} )
	{
		my @flags = split /;/x, $data[ $file_header_pos{'flags'} ] // q();
		foreach my $flag (@flags) {
			if ( none { $flag eq $_ } ALLELE_FLAGS ) {
				$buffer .= "Flag '$flag' is not on the list of allowed flags.<br />\n";
			}
		}
	}
	if ($buffer) {
		$arg_ref->{'problems'}->{$pk_combination} .= $buffer;
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

sub _upload_data {
	my ( $self, $arg_ref ) = @_;
	my $table    = $arg_ref->{'table'};
	my $locus    = $arg_ref->{'locus'};
	my $loci     = $self->{'datastore'}->get_loci;
	my $q        = $self->{'cgi'};
	my $tmp_file = "$self->{'config'}->{'secure_tmp_dir'}/" . $q->param('checked_buffer');
	my %schemes;
	my @records;

	if ( !-e $tmp_file ) {
		say q(<div class="box" id="statusbad"><p>The temp file containing the checked data does not exist.</p>)
		  . q(<p>Upload cannot proceed.  Make sure that you haven't used the back button and are attempting to )
		  . q(re-upload already submitted data.  Please report this if the problem persists.<p></div>);
		$logger->error("Checked buffer file $tmp_file does not exist.");
		return;
	}
	if ( open( my $tmp_fh, '<:encoding(utf8)', $tmp_file ) ) {
		@records = <$tmp_fh>;
		close $tmp_fh;
	} else {
		$logger->error("Can't open $tmp_file for reading.");
	}
	if ( $tmp_file =~ /^(.*\/BIGSdb_[0-9_]+\.txt)$/x ) {
		$logger->info("Deleting temp file $tmp_file.");
		unlink $1;
	} else {
		$logger->error("Can't delete temp file $tmp_file.");
	}
	my $headerline = shift @records;
	my @fieldorder;
	if ( defined $headerline ) {
		$headerline =~ s/[\r\n]//gx;
		@fieldorder = split /\t/x, $headerline;
	}
	my %fieldorder;
	my $extended_attributes;
	for ( my $i = 0 ; $i < @fieldorder ; $i++ ) {
		$fieldorder{ $fieldorder[$i] } = $i;
	}
	my ( @fields_to_include, @metafields );
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		my $set_id        = $self->get_set_id;
		my $metadata_list = $self->{'datastore'}->get_set_metadata( $set_id, { curate => 1 } );
		my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
		foreach my $field (@$field_list) {
			if ( $field =~ /^meta_.*:/x ) {
				push @metafields, $field;
			} else {
				push @fields_to_include, $field;
			}
		}
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		push @fields_to_include, $_->{'name'} foreach @$attributes;
		if ( $table eq 'sequences' && $locus ) {
			$extended_attributes =
			  $self->{'datastore'}->run_query( 'SELECT field FROM locus_extended_attributes WHERE locus=?',
				$locus, { fetch => 'col_arrayref' } );
		}
	}
	my @history;
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	foreach my $record (@records) {
		$record =~ s/\r//gx;
		my @profile;
		if ($record) {
			my @data = split /\t/x, $record;
			@data = $self->_process_fields( \@data );
			my @value_list;
			my ( @extras, @ref_extras );
			my ( $id,     $sender );
			foreach my $field (@fields_to_include) {
				$id = $data[ $fieldorder{$field} ] if $field eq 'id';
				if ( $field eq 'date_entered' || $field eq 'datestamp' ) {
					push @value_list, 'now';
				} elsif ( $field eq 'curator' ) {
					push @value_list, $self->get_curator_id;
				} elsif ( $field eq 'sender' && $user_info->{'status'} eq 'submitter' ) {
					push @value_list, $self->get_curator_id;
					$sender = $self->get_curator_id;
				} elsif ( defined $fieldorder{$field}
					&& defined $data[ $fieldorder{$field} ] )
				{
					push @value_list, $data[ $fieldorder{$field} ];
					if ( $field eq 'sender' ) {
						$sender = $data[ $fieldorder{$field} ];
					}
				} elsif ( $field eq 'sender' ) {
					if ( $q->param('sender') ) {
						$sender = $q->param('sender');
						push @value_list, $q->param('sender');
					} else {
						push @value_list, undef;
						$logger->error('No sender!');
					}
				} elsif ( $table eq 'sequences' && !defined $fieldorder{$field} && $locus ) {
					push @value_list, $locus;
				} else {
					push @value_list, undef;
				}
				if ( $field eq 'scheme_id' ) {
					$schemes{ $data[ $fieldorder{'scheme_id'} ] } = 1;
				}
			}
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' && ( $table eq 'loci' || $table eq 'isolates' ) ) {
				@extras = split /;/x, $data[ $fieldorder{'aliases'} ]
				  if defined $fieldorder{'aliases'} && defined $data[ $fieldorder{'aliases'} ];
				@ref_extras = split /;/x, $data[ $fieldorder{'references'} ]
				  if defined $fieldorder{'references'} && defined $data[ $fieldorder{'references'} ];
			}
			my @inserts;
			my $qry;
			local $" = ',';
			my @placeholders = ('?') x @fields_to_include;
			$qry = "INSERT INTO $table (@fields_to_include) VALUES (@placeholders)";
			push @inserts, { statement => $qry, arguments => \@value_list };
			if ( $table eq 'allele_designations' ) {
				push @history, "$data[$fieldorder{'isolate_id'}]|$data[$fieldorder{'locus'}]: "
				  . "new designation '$data[$fieldorder{'allele_id'}]'";
			}
			my $curator = $self->get_curator_id;
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
				my $meta_inserts = $self->_prepare_metaset_insert( \@metafields, \%fieldorder, \@data );
				push @inserts, @$meta_inserts;

				#Remove duplicate loci which may occur if they belong to more than one scheme.
				my @locus_list = uniq @$loci;
				foreach (@locus_list) {
					next if !$fieldorder{$_};
					my $value = $data[ $fieldorder{$_} ];
					$value //= q();
					$value =~ s/^\s*//gx;
					$value =~ s/\s*$//gx;
					next if $value eq q();
					if ( defined $fieldorder{$_} ) {
						$qry =
						    'INSERT INTO allele_designations (isolate_id,locus,allele_id,sender,status,method,curator,'
						  . 'date_entered,datestamp) VALUES (?,?,?,?,?,?,?,?,?)';
						push @inserts,
						  {
							statement => $qry,
							arguments => [ $id, $_, $value, $sender, 'confirmed', 'manual', $curator, 'now', 'now' ]
						  };
					}
				}
				foreach (@extras) {
					next if !defined $_;
					$_ =~ s/^\s*//gx;
					$_ =~ s/\s*$//gx;
					if ( $_ && $_ ne $id && defined $data[ $fieldorder{ $self->{'system'}->{'labelfield'} } ] ) {
						$qry = 'INSERT INTO isolate_aliases (isolate_id,alias,curator,datestamp) VALUES (?,?,?,?)';
						push @inserts, { statement => $qry, arguments => [ $id, $_, $curator, 'now' ] };
					}
				}
				foreach (@ref_extras) {
					next if !defined $_;
					$_ =~ s/^\s*//gx;
					$_ =~ s/\s*$//gx;
					if ( $_ && $_ ne $id && defined $data[ $fieldorder{ $self->{'system'}->{'labelfield'} } ] ) {
						if ( BIGSdb::Utils::is_int($_) ) {
							$qry = 'INSERT INTO refs (isolate_id,pubmed_id,curator,datestamp) VALUES (?,?,?,?)';
							push @inserts, { statement => $qry, arguments => [ $id, $_, $curator, 'now' ] };
						}
					}
				}
				push @history, "$id|Isolate record added";
			} elsif ( $table eq 'loci' ) {
				foreach (@extras) {
					$_ =~ s/^\s*//gx;
					$_ =~ s/\s*$//gx;
					if ( defined $_ && $_ ne $id ) {
						$qry = 'INSERT INTO locus_aliases (locus,alias,use_alias,curator,datestamp) VALUES (?,?,?,?,?)';
						push @inserts, { statement => $qry, arguments => [ $id, $_, 'TRUE', $curator, 'now' ] };
					}
				}
				if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
					my $full_name = defined $fieldorder{'full_name'} ? $data[ $fieldorder{'full_name'} ] : undef;
					my $product = defined $fieldorder{'product'}
					  && $data[ $fieldorder{'product'} ] ? $data[ $fieldorder{'product'} ] : undef;
					my $description = defined $fieldorder{'description'} ? $data[ $fieldorder{'description'} ] : undef;
					$qry =
					    'INSERT INTO locus_descriptions (locus,curator,datestamp,full_name,product,description) '
					  . 'VALUES (?,?,?,?,?,?)';
					push @inserts,
					  { statement => $qry, arguments => [ $id, $curator, 'now', $full_name, $product, $description ] };
				}
			} elsif ( $table eq 'sequences' ) {
				$locus //= $data[ $fieldorder{'locus'} ];
				if ( $locus && ref $extended_attributes eq 'ARRAY' ) {
					my @values;
					$qry = 'INSERT INTO sequence_extended_attributes (locus,field,allele_id,value,datestamp,'
					  . 'curator) VALUES (?,?,?,?,?,?)';
					foreach (@$extended_attributes) {
						if ( defined $fieldorder{$_} && defined $data[ $fieldorder{$_} ] ) {
							push @inserts,
							  {
								statement => $qry,
								arguments => [
									$locus, $_,
									$data[ $fieldorder{'allele_id'} ],
									$data[ $fieldorder{$_} ],
									'now', $curator
								]
							  };
						}
					}
				}
				if (   ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes'
					&& defined $fieldorder{'flags'}
					&& defined $data[ $fieldorder{'flags'} ] )
				{
					my @flags = split /;/x, $data[ $fieldorder{'flags'} ];
					$qry = 'INSERT INTO allele_flags (locus,allele_id,flag,datestamp,curator) VALUES (?,?,?,?,?)';
					foreach (@flags) {
						push @inserts,
						  {
							statement => $qry,
							arguments => [ $locus, $data[ $fieldorder{'allele_id'} ], $_, 'now', $curator ]
						  };
					}
				}
				$self->{'datastore'}->mark_cache_stale;
			}
			eval {
				foreach my $insert (@inserts)
				{
					$self->{'db'}->do( $insert->{'statement'}, undef, @{ $insert->{'arguments'} } );
				}
			};
			if ($@) {
				my $err = $@;
				say q(<div class="box" id="statusbad"><p>Database update failed - transaction cancelled )
				  . q(- no records have been touched.</p>);
				if ( $err =~ /duplicate/ && $err =~ /unique/ ) {
					say q(<p>Data entry would have resulted in records with either duplicate ids or another )
					  . q(unique field with duplicate values.  This can result from another curator adding )
					  . q(data at the same time.  Try pressing the browser back button twice and then re-submit )
					  . q(the records.</p>);
				} else {
					say q(<p>An error has occurred - more details will be available in the server log.</p>);
					$logger->error($err);
				}
				say q(</div>);
				$self->{'db'}->rollback;
				return;
			}
		}
	}
	if ( ( $table eq 'scheme_members' || $table eq 'scheme_fields' )
		&& $self->{'system'}->{'dbtype'} eq 'sequences' )
	{
		foreach my $scheme_id ( keys %schemes ) {
			my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
			my $scheme_loci   = $self->{'datastore'}->get_scheme_loci($scheme_id);
			my $scheme_info   = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
			my $field_count   = @$scheme_fields + @$scheme_loci;
			if ( $scheme_info->{'primary_key'} && $field_count > MAX_POSTGRES_COLS ) {
				say q(<div class="box" id="statusbad"><p>Indexed scheme tables are limited to a maximum of )
				  . MAX_POSTGRES_COLS
				  . qq( columns - yours would have $field_count.  This is a limitation of PostgreSQL, but it's not really sensible )
				  . q(to have indexed schemes (those with a primary key field) to have so many fields. Update failed.</p></div);
				$self->{'db'}->rollback;
				return;
			}
			$self->remove_profile_data($scheme_id);
			$self->drop_scheme_view($scheme_id);
			$self->create_scheme_view($scheme_id);
		}
	}
	$self->{'db'}->commit && say q(<div class="box" id="resultsheader"><p>Database updated ok</p>);
	foreach (@history) {
		my ( $isolate_id, $action ) = split /\|/x, $_;
		$self->update_history( $isolate_id, $action );
	}
	say q(<p>);
	my $submission_id = $q->param('submission_id');
	if ($submission_id) {
		say qq(<a href="$self->{'system'}->{'query_script'}?db=$self->{'instance'}&amp;page=submit&amp;)
		  . qq(submission_id=$submission_id&amp;curate=1">Return to submission</a> | );
	}
	say qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a>);
	if ( $table eq 'sequences' ) {
		my $sender            = $q->param('sender');
		my $ignore_existing   = $q->param('ignore_existing') ? 'on' : 'off';
		my $ignore_non_DNA    = $q->param('ignore_non_DNA') ? 'on' : 'off';
		my $complete_CDS      = $q->param('complete_CDS') ? 'on' : 'off';
		my $ignore_similarity = $q->param('ignore_similarity') ? 'on' : 'off';
		say qq( | <a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;)
		  . qq(table=sequences&amp;sender=$sender&amp;ignore_existing=$ignore_existing&amp;)
		  . qq(ignore_non_DNA=$ignore_non_DNA&amp;complete_CDS=$complete_CDS&amp;)
		  . qq(ignore_similarity=$ignore_similarity">Add more</a>);
		$self->update_blast_caches;
	} elsif ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		$self->_update_scheme_caches if ( $self->{'system'}->{'cache_schemes'} // q() ) eq 'yes';
	}
	say q(</p></div>);
	return;
}

sub _update_scheme_caches {
	my ($self) = @_;

	#Use double fork to prevent zombie processes on apache2-mpm-worker
	defined( my $kid = fork ) or $logger->error('cannot fork');
	if ($kid) {
		waitpid( $kid, 0 );
	} else {
		defined( my $grandkid = fork ) or $logger->error('Kid cannot fork');
		if ($grandkid) {
			CORE::exit(0);
		} else {
			open STDIN,  '<', '/dev/null' || $logger->error("Can't detach STDIN: $!");
			open STDOUT, '>', '/dev/null' || $logger->error("Can't detach STDOUT: $!");
			open STDERR, '>&STDOUT' || $logger->error("Can't detach STDERR: $!");
			BIGSdb::Offline::UpdateSchemeCaches->new(
				{
					config_dir       => $self->{'config_dir'},
					lib_dir          => $self->{'lib_dir'},
					dbase_config_dir => $self->{'dbase_config_dir'},
					instance         => $self->{'instance'}
				}
			);
			CORE::exit(0);
		}
	}
	return;
}

sub _prepare_metaset_insert {
	my ( $self, $fields, $fieldorder, $data ) = @_;
	my %metasets;
	foreach my $field (@$fields) {
		next if !defined $fieldorder->{$field};
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
		my $value = $data->[ $fieldorder->{$field} ];
		$metasets{$metaset} = 1 if defined $value;
	}
	my @metasets = keys %metasets;
	my @inserts;
	my $isolate_id = $data->[ $fieldorder->{'id'} ];
	foreach my $metaset (@metasets) {
		my $meta_fields = $self->{'xmlHandler'}->get_field_list( ["meta_$metaset"], { meta_fields_only => 1 } );
		my @placeholders = ('?') x ( @$meta_fields + 1 );
		local $" = ',';
		my $qry    = "INSERT INTO meta_$metaset (isolate_id,@$meta_fields) VALUES (@placeholders)";
		my @values = ($isolate_id);
		foreach my $field (@$meta_fields) {
			push @values, $data->[ $fieldorder->{$field} ];
		}
		$qry =~ s/meta_$metaset://gx;    #field names include metaset which isn't used in database table.
		push @inserts, { statement => $qry, arguments => \@values };
	}
	return \@inserts;
}

sub get_title {
	my ($self) = @_;
	my $desc  = $self->{'system'}->{'description'} || 'BIGSdb';
	my $table = $self->{'cgi'}->param('table');
	my $type  = $self->get_record_name($table) || '';
	return "Batch add new $type records - $desc";
}

sub _get_fields_in_order {

	#Return list of fields in order
	my ( $self, $table ) = @_;
	my @fieldnums;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		my $set_id        = $self->get_set_id;
		my $metadata_list = $self->{'datastore'}->get_set_metadata( $set_id, { curate => 1 } );
		my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
		foreach (@$field_list) {
			push @fieldnums, $_;
			if ( $_ eq $self->{'system'}->{'labelfield'} ) {
				push @fieldnums, 'aliases';
				push @fieldnums, 'references';
			}
		}
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		foreach (@$attributes) {
			push @fieldnums, $_->{'name'};
			if ( $table eq 'loci' && $self->{'system'}->{'dbtype'} eq 'isolates' && $_->{'name'} eq 'id' ) {
				push @fieldnums, 'aliases';
			}
		}
	}
	return @fieldnums;
}

sub _get_field_table_header {
	my ( $self, $table ) = @_;
	my @headers;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		my $set_id        = $self->get_set_id;
		my $metadata_list = $self->{'datastore'}->get_set_metadata( $set_id, { curate => 1 } );
		my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
		foreach (@$field_list) {
			push @headers, $_;
			if ( $_ eq $self->{'system'}->{'labelfield'} ) {
				push @headers, 'aliases';
				push @headers, 'references';
			}
		}
		push @headers, 'loci';
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		foreach (@$attributes) {
			push @headers, $_->{'name'};
			if ( $table eq 'loci' && $self->{'system'}->{'dbtype'} eq 'isolates' && $_->{'name'} eq 'id' ) {
				push @headers, 'aliases';
			}
		}
		if ( $self->{'system'}->{'dbtype'} eq 'sequences' && $table eq 'sequences' ) {
			if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
				push @headers, 'flags';
			}
			if ( $self->{'cgi'}->param('locus') ) {
				my $extended_attributes = $self->{'datastore'}->run_query(
					'SELECT field FROM locus_extended_attributes WHERE locus=? ORDER BY field_order',
					$self->{'cgi'}->param('locus'),
					{ fetch => 'col_arrayref' }
				);
				push @headers, @$extended_attributes;
			}
		} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' && $table eq 'loci' ) {
			push @headers, qw(full_name product description);
		}
	}
	local $" = q(</th><th>);
	return qq(<th>@headers</th>);
}

sub _is_id_used {
	my ( $self, $table, $id ) = @_;
	my $qry = "SELECT EXISTS(SELECT * FROM $table WHERE id=?)";
	return $self->{'datastore'}->run_query( $qry, $id, { cache => "CurateBatchAdd::is_id_used::$table" } );
}

sub _process_fields {
	my ( $self, $data ) = @_;
	my @return_data;
	foreach my $value (@$data) {
		$value =~ s/^\s+//x;
		$value =~ s/\s+$//x;
		$value =~ s/\r//gx;
		$value =~ s/\n/ /gx;
		if ( $value eq q() ) {
			push @return_data, undef;
		} else {
			push @return_data, $value;
		}
	}
	return @return_data;
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
1;
