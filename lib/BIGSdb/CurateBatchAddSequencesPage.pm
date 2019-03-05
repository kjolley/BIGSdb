#Written by Keith Jolley
#Copyright (c) 2010-2019, University of Oxford
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
package BIGSdb::CurateBatchAddSequencesPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateBatchAddPage);
use BIGSdb::Offline::BatchSequenceCheck;
use BIGSdb::Constants qw(:interface SEQ_STATUS );
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/curator_guide.html#batch-adding-multiple-alleles";
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Batch add new allele sequence records - $desc";
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $locus  = $q->param('locus');
	if ( ( $self->{'system'}->{'dbtype'} // q() ) ne 'sequences' ) {
		say q(<h1>Batch insert sequences</h1>);
		$self->print_bad_status(
			{
				message => q(This method can only be called on a sequence definition database.),
				navbar  => 1
			}
		);
		return;
	}
	if ($locus) {
		if ( !$self->{'datastore'}->is_locus($locus) ) {
			say q(<h1>Batch insert sequences</h1>);
			$self->print_bad_status( { message => qq(Locus $locus does not exist!), navbar => 1 } );
			return;
		}
		my $cleaned_locus = $self->clean_locus($locus);
		say qq(<h1>Batch insert $cleaned_locus sequences</h1>);
	} else {
		say q(<h1>Batch insert sequences</h1>);
	}
	if ( !$self->can_modify_table('sequences') ) {
		$self->print_bad_status(
			{
				message => q(Your user account is not allowed to add records to the sequences table.),
				navbar  => 1
			}
		);
		return;
	}
	if ( $q->param('datatype') && $q->param('list_file') ) {
		$self->{'datastore'}->create_temp_list_table( $q->param('datatype'), $q->param('list_file') );
	}
	if ( $q->param('query_file') && !defined $q->param('query') ) {
		my $query_file = $q->param('query_file');
		my $query      = $self->get_query_from_temp_file($query_file);
		$q->param( query => $query );
	}
	if ( $q->param('checked_buffer') ) {
		$self->_upload_data($locus);
	} elsif ( $q->param('data') || $q->param('query') ) {
		$self->_check_data($locus);
	} else {
		if ( $q->param('submission_id') ) {
			$self->_set_submission_params( $q->param('submission_id') );
		}
		my $icon = $self->get_form_icon( 'sequences', 'plus' );
		say $icon;
		$self->_print_interface($locus);
	}
	return;
}

sub _print_interface {
	my ( $self, $locus ) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="queryform"><div class="scrollable"><h2>Instructions</h2>)
	  . q(<p>This page allows you to upload allele sequence )
	  . q(data as tab-delimited text or copied from a spreadsheet.</p>);
	say q(<ul><li>Field header names must be included and fields can be in any order. Optional fields can be )
	  . q(omitted if you wish.</li>);
	my $locus_attribute = '';
	$locus_attribute = "&amp;locus=$locus" if $locus;
	my @status = SEQ_STATUS;
	local $" = q(', ');
	say q(<li>If the locus uses integer allele ids you can leave the allele_id )
	  . q(field blank and the next available number will be used.</li>)
	  . qq(<li>The status defines how the sequence was curated.  Allowed values are: '@status'.</li>);

	if ( $self->{'system'}->{'allele_flags'} ) {
		say q(<li>Sequence flags can be added as a semi-colon (;) separated list.</li>);
	}
	if ( !$q->param('locus') ) {
		$self->_print_interface_locus_selection;
	}
	say q(</ul>);
	say q(<h2>Templates</h2>);
	my ( $text, $excel ) = ( TEXT_FILE, EXCEL_FILE );
	say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=tableHeader&amp;table=sequences$locus_attribute" title="Tab-delimited text header">$text</a>)
	  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=excelTemplate&amp;table=sequences$locus_attribute" title="Excel format">$excel</a></p>);
	say q(<h2>Upload</h2>);
	say $q->start_form;
	$self->print_interface_sender_field;
	$self->_print_interface_sequence_switches;
	say q(<fieldset style="float:left"><legend>Paste in tab-delimited text )
	  . q((<strong>include a field header line</strong>).</legend>);
	say $q->textarea( -name => 'data', -rows => 20, -columns => 80 );
	say q(</fieldset>);
	say $q->hidden($_) foreach qw (page db table locus);
	$self->print_action_fieldset( { table => 'sequences' } );
	say $q->end_form;
	$self->print_navigation_bar;
	say q(</div></div>);
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
				say
				  qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSequences&amp;)
				  . qq(locus=$locus">$locus</a>);
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

sub _run_helper {
	my ( $self, $locus ) = @_;
	my $q         = $self->{'cgi'};
	my $set_id    = $self->get_set_id;
	my $check_obj = BIGSdb::Offline::BatchSequenceCheck->new(
		{
			config_dir       => $self->{'config_dir'},
			lib_dir          => $self->{'lib_dir'},
			dbase_config_dir => $self->{'dbase_config_dir'},
			host             => $self->{'system'}->{'host'},
			port             => $self->{'system'}->{'port'},
			user             => $self->{'system'}->{'user'},
			password         => $self->{'system'}->{'password'},
			options          => {
				always_run        => 1,
				set_id            => $set_id,
				script_name       => $self->{'system'}->{'script_name'},
				locus             => $locus,
				data              => $q->param('data'),
				ignore_existing   => $q->param('ignore_existing') ? 1 : 0,
				complete_CDS      => $q->param('complete_CDS') ? 1 : 0,
				ignore_non_DNA    => $q->param('ignore_non_DNA') ? 1 : 0,
				ignore_similarity => $q->param('ignore_similarity') ? 1 : 0,
				username          => $self->{'username'}
			},
			instance => $self->{'instance'},
			logger   => $logger
		}
	);
	return $check_obj->run;
}

sub _check_data {
	my ( $self, $locus ) = @_;
	return if $self->sender_needed( { has_sender_field => 1 } );
	my $results = $self->_run_helper($locus);
	use Data::Dumper;
	$logger->error( Dumper $results);
	my $sender_message   = $self->get_sender_message( { has_sender_field => 1 } );
	my $table_buffer_ref = $results->{'table_buffer'};
	my $record_count     = $results->{'record_count'};
	my $problems         = $results->{'problems'};
	my $checked_buffer   = $results->{'checked_buffer'};
	if ( !$record_count ) {
		$self->print_bad_status(
			{
				message => q(No valid data entered. Make sure you've included the header line.),
				navbar  => 1
			}
		);
		return;
	}
	$self->report_check(
		{
			table          => 'sequences',
			buffer         => $table_buffer_ref,
			problems       => $problems,
			advisories     => {},
			checked_buffer => $checked_buffer,
			sender_message => \$sender_message
		}
	);
	return;
}

sub _upload_data {
	my ( $self, $locus ) = @_;
	my $q       = $self->{'cgi'};
	my $records = $self->extract_checked_records;
	return if !@$records;
	my $field_order = $self->get_field_order($records);
	my ( $fields_to_include, $meta_fields, $extended_attributes ) = $self->_get_fields_to_include($locus);
	my @history;
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my %loci;
	$loci{$locus} = 1 if $locus;

	foreach my $record (@$records) {
		$record =~ s/\r//gx;
		if ($record) {
			my @data = split /\t/x, $record;
			@data = $self->process_fields( \@data );
			my @value_list;
			my $id;
			my $sender = $self->get_sender( $field_order, \@data, $user_info->{'status'} );
			foreach my $field (@$fields_to_include) {
				$id = $data[ $field_order->{$field} ] if $field eq 'id';
				push @value_list,
				  $self->read_value(
					{
						table       => 'sequences',
						field       => $field,
						field_order => $field_order,
						data        => \@data,
						locus       => $locus,
						user_status => ( $user_info->{'status'} // undef )
					}
				  ) // undef;
			}
			$loci{ $data[ $field_order->{'locus'} ] } = 1 if defined $field_order->{'locus'};
			my @inserts;
			my $qry;
			local $" = ',';
			my @placeholders = ('?') x @$fields_to_include;
			$qry = "INSERT INTO sequences (@$fields_to_include) VALUES (@placeholders)";
			push @inserts, { statement => $qry, arguments => \@value_list };
			my $curator = $self->get_curator_id;
			my ( $upload_err, $failed_file );
			my $extra_methods = {
				sequences => sub {
					return $self->_prepare_sequences_extra_inserts(
						{
							locus               => $locus,
							extended_attributes => $extended_attributes,
							data                => \@data,
							field_order         => $field_order,
							curator             => $curator
						}
					);
				},
			};
			if ( $extra_methods->{'sequences'} ) {
				my $extra_inserts = $extra_methods->{'sequences'}->();
				push @inserts, @$extra_inserts;
			}
			eval {
				foreach my $insert (@inserts) {
					$self->{'db'}->do( $insert->{'statement'}, undef, @{ $insert->{'arguments'} } );
				}
			};
			if ( $@ || $upload_err ) {
				$self->report_upload_error( ( $upload_err // $@ ), $failed_file );
				$self->{'db'}->rollback;
				return;
			}
		}
	}
	$self->{'db'}->commit;
	$self->_report_successful_upload;
	foreach (@history) {
		my ( $isolate_id, $action ) = split /\|/x, $_;
		$self->update_history( $isolate_id, $action );
	}
	my @loci = keys %loci;
	$self->mark_locus_caches_stale( \@loci );
	$self->update_blast_caches;
	return;
}

sub _get_fields_to_include {
	my ( $self, $locus ) = @_;
	my ( @fields_to_include, @metafields, $extended_attributes );
	my $attributes = $self->{'datastore'}->get_table_field_attributes('sequences');
	push @fields_to_include, $_->{'name'} foreach @$attributes;
	if ($locus) {
		$extended_attributes =
		  $self->{'datastore'}->run_query( 'SELECT field FROM locus_extended_attributes WHERE locus=?',
			$locus, { fetch => 'col_arrayref' } );
	}
	return ( \@fields_to_include, \@metafields, $extended_attributes );
}

sub _prepare_sequences_extra_inserts {
	my ( $self, $args ) = @_;
	my ( $locus, $extended_attributes, $data, $field_order, $curator ) =
	  @{$args}{qw(locus extended_attributes data field_order curator)};
	my @inserts;
	$locus //= $data->[ $field_order->{'locus'} ];
	if ( $locus && ref $extended_attributes eq 'ARRAY' ) {
		my @values;
		my $qry = 'INSERT INTO sequence_extended_attributes (locus,field,allele_id,value,datestamp,'
		  . 'curator) VALUES (?,?,?,?,?,?)';
		foreach (@$extended_attributes) {
			if ( defined $field_order->{$_} && defined $data->[ $field_order->{$_} ] ) {
				push @inserts,
				  {
					statement => $qry,
					arguments => [
						$locus, $_,
						$data->[ $field_order->{'allele_id'} ],
						$data->[ $field_order->{$_} ],
						'now', $curator
					]
				  };
			}
		}
	}
	if (   ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes'
		&& defined $field_order->{'flags'}
		&& defined $data->[ $field_order->{'flags'} ] )
	{
		my @flags = split /;/x, $data->[ $field_order->{'flags'} ];
		my $qry = 'INSERT INTO allele_flags (locus,allele_id,flag,datestamp,curator) VALUES (?,?,?,?,?)';
		foreach (@flags) {
			push @inserts,
			  {
				statement => $qry,
				arguments => [ $locus, $data->[ $field_order->{'allele_id'} ], $_, 'now', $curator ]
			  };
		}
	}
	return \@inserts;
}

sub _report_successful_upload {
	my ( $self, $project_id ) = @_;
	my $q        = $self->{'cgi'};
	my $nav_data = $self->_get_nav_data;
	my $more_url = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSequences);
	$self->print_good_status(
		{
			message => q(Database updated.),
			navbar  => 1,
			%$nav_data,
			more_text => q(Add more),
			more_url  => $nav_data->{'more_url'} // $more_url,
		}
	);
	return;
}

sub _get_nav_data {
	my ($self)        = @_;
	my $q             = $self->{'cgi'};
	my $submission_id = $q->param('submission_id');
	if ($submission_id) {
		$self->_update_submission_database($submission_id);
	}
	my $more_url;
	my $sender            = $q->param('sender');
	my $ignore_existing   = $q->param('ignore_existing') ? 'on' : 'off';
	my $ignore_non_DNA    = $q->param('ignore_non_DNA') ? 'on' : 'off';
	my $complete_CDS      = $q->param('complete_CDS') ? 'on' : 'off';
	my $ignore_similarity = $q->param('ignore_similarity') ? 'on' : 'off';
	$more_url =
	    qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;)
	  . qq(table=sequences&amp;sender=$sender&amp;ignore_existing=$ignore_existing&amp;)
	  . qq(ignore_non_DNA=$ignore_non_DNA&amp;complete_CDS=$complete_CDS&amp;)
	  . qq(ignore_similarity=$ignore_similarity);
	return { submission_id => $submission_id, more_url => $more_url };
}
1;
