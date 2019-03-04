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
use BIGSdb::Constants qw(:interface SEQ_STATUS ALLELE_FLAGS DIPLOID HAPLOID IDENTITY_THRESHOLD);
use List::MoreUtils qw(any none);
use Digest::MD5 qw(md5);
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
				say qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSequences&amp;)
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

sub _check_data {
	my ( $self, $locus ) = @_;
	my $q = $self->{'cgi'};
	my @checked_buffer;
	my $fields = $self->_get_fields_in_order($locus);
	my ( $extended_attributes, $required_extended_exist ) =
	  @{ $self->_get_locus_extended_attributes($locus) }{qw(extended_attributes required_extended_exist)};
	my %last_id;
	return if $self->sender_needed( { has_sender_field => 1 } );
	my $sender_message = $self->get_sender_message( { has_sender_field => 1 } );
	my %problems;
	my $table_header = $self->_get_field_table_header;
	my $tablebuffer  = qq(<div class="scrollable"><table class="resultstable"><tr>$table_header</tr>);
	my @records      = split /\n/x, $q->param('data');
	my $td           = 1;
	my ( $file_header_fields, $file_header_pos ) = $self->get_file_header_data( \@records );
	my $primary_keys = [qw(locus allele_id)];
	my ( %locus_format, %locus_regex, $header_row, $header_complete, $record_count );
	my $first_record = 1;

	foreach my $record (@records) {
		$record =~ s/\r//gx;
		next if $record =~ /^\s*$/x;
		my $checked_record;
		if ($record) {
			my @data = split /\t/x, $record;
			BIGSdb::Utils::remove_trailing_spaces_from_list( \@data );
			my $first = 1;
			my ( $pk_combination, $pk_values_ref ) = $self->_get_primary_key_values(
				{
					primary_keys    => $primary_keys,
					file_header_pos => $file_header_pos,
					locus           => $locus,
					first           => \$first,
					data            => \@data,
					record_count    => \$record_count
				}
			);
			my $rowbuffer;
			my $continue = 1;
			foreach my $field (@$fields) {

				#Prepare checked header
				if ( !$header_complete && ( defined $file_header_pos->{$field} || $field eq 'id' ) ) {
					$header_row .= "$field\t";
				}

				#Check individual values for correctness.
				my $value = $self->extract_value(
					{
						field               => $field,
						data                => \@data,
						file_header_pos     => $file_header_pos,
						extended_attributes => $extended_attributes
					}
				);
				my $special_problem;
				my $new_args = {
					locus                   => $locus,
					field                   => $field,
					value                   => \$value,
					file_header_pos         => $file_header_pos,
					data                    => \@data,
					required_extended_exist => $required_extended_exist,
					pk_combination          => $pk_combination,
					problems                => \%problems,
					special_problem         => \$special_problem,
					continue                => \$continue,
					last_id                 => \%last_id,
					extended_attributes     => $extended_attributes,
				};
				$self->check_data_duplicates($new_args);
				$new_args->{'file_header_pos'}->{'allele_id'} = keys %{ $new_args->{'file_header_pos'} }
				  if !defined $new_args->{'file_header_pos'}->{'allele_id'};
				$self->_check_data_sequences($new_args);
				$pk_combination = $new_args->{'pk_combination'} // $pk_combination;

				#Display field - highlight in red if invalid.
				$rowbuffer .= $self->format_display_value(
					{
						table => 'sequences',
						field           => $field,
						value           => $value,
						problems        => \%problems,
						pk_combination  => $pk_combination,
						special_problem => $special_problem
					}
				);
				$value //= q();
				if ( defined $file_header_pos->{$field} || ( $field eq 'id' ) ) {
					$checked_record .= qq($value\t);
				}
			}
			if ( !$continue ) {
				undef $header_row if $first_record;
				next;
			}
			$tablebuffer .= qq(<tr class="td$td">$rowbuffer);
			my $new_args = {
				file_header_fields => $file_header_fields,
				header_row         => \$header_row,
				first_record       => $first_record,
				file_header_pos    => $file_header_pos,
				data               => \@data,
				locus_format       => \%locus_format,
				locus_regex        => \%locus_regex,
				primary_keys       => $primary_keys,
				pk_combination     => $pk_combination,
				pk_values          => $pk_values_ref,
				problems           => \%problems,
				checked_record     => \$checked_record,
			};
			$header_complete = 1;
			push @checked_buffer, $header_row if $first_record;
			$first_record = 0;
			$tablebuffer .= qq(</tr>\n);
			$self->check_permissions( $locus, $new_args, \%problems, $pk_combination );
		}
		$td = $td == 1 ? 2 : 1;    #row stripes
		$checked_record =~ s/\t$//x if defined $checked_record;
		push @checked_buffer, $checked_record;
	}
	$tablebuffer .= q(</table></div>);
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
			table => 'sequences',
			buffer         => \$tablebuffer,
			problems       => \%problems,
			advisories     => {},
			checked_buffer => \@checked_buffer,
			sender_message => \$sender_message
		}
	);
	return;
}

sub _get_fields_in_order {
	my ( $self, $locus ) = @_;
	my $fields     = [];
	my $attributes = $self->{'datastore'}->get_table_field_attributes('sequences');
	foreach my $att (@$attributes) {
		push @$fields, $att->{'name'};
	}
	push @$fields, 'flags' if ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes';
	my $ext_att = $self->_get_locus_extended_attributes($locus);
	push @$fields, @{ $ext_att->{'field_names'} };
	return $fields;
}

sub _get_locus_extended_attributes {
	my ( $self, $locus ) = @_;
	my $extended_attributes      = {};
	my $extended_attribute_names = [];
	my $required_extended_exist;
	if ($locus) {
		my $ext_att = $self->{'datastore'}->run_query(
			'SELECT field,value_format,value_regex,required,option_list FROM '
			  . 'locus_extended_attributes WHERE locus=? ORDER BY field_order',
			$locus,
			{ fetch => 'all_arrayref' }
		);
		foreach (@$ext_att) {
			my ( $field, $format, $regex, $required, $optlist ) = @$_;
			push @$extended_attribute_names, $field;
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
	return {
		extended_attributes     => $extended_attributes,
		field_names             => $extended_attribute_names,
		required_extended_exist => $required_extended_exist
	};
}

sub _get_primary_key_values {
	my ( $self, $arg_ref ) = @_;
	my @data            = @{ $arg_ref->{'data'} };
	my %file_header_pos = %{ $arg_ref->{'file_header_pos'} };
	my $pk_combination;
	my $pk_values = [];
	foreach ( @{ $arg_ref->{'primary_keys'} } ) {
		if ( !defined $file_header_pos{$_} ) {
			if ( $arg_ref->{'locus'} && $_ eq 'locus' ) {
				push @$pk_values, $arg_ref->{'locus'};
				$pk_combination .= "$_: " . BIGSdb::Utils::pad_length( $arg_ref->{'locus'}, 10 );
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
			push @$pk_values, $data[ $file_header_pos{$_} ];
		}
		${ $arg_ref->{'first'} } = 0;
		${ $arg_ref->{'record_count'} }++;
	}
	return ( $pk_combination, $pk_values );
}

sub _get_field_table_header {
	my ($self) = @_;
	my @headers;
	my $attributes = $self->{'datastore'}->get_table_field_attributes('sequences');
	foreach (@$attributes) {
		push @headers, $_->{'name'};
	}
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
	local $" = q(</th><th>);
	return qq(<th>@headers</th>);
}

sub _check_data_sequences {
	my ( $self, $args ) = @_;
	my ( $field, $file_header_pos, $data, $pk_combination ) = @{$args}{qw(field file_header_pos data pk_combination)};
	my $q = $self->{'cgi'};
	my $locus;
	if ( $field eq 'locus' && $q->param('locus') ) {
		${ $args->{'value'} } = $q->param('locus');
	}
	if ( $q->param('locus') ) {
		$locus = $q->param('locus');
	} else {
		$locus =
		  ( defined $file_header_pos->{'locus'} && defined $data->[ $file_header_pos->{'locus'} ] )
		  ? $data->[ $file_header_pos->{'locus'} ]
		  : undef;
	}
	my $buffer = $self->_check_sequence_allele_id( $locus, $args );
	$buffer .= $self->_check_sequence_length( $locus, $args );
	$buffer .= $self->_check_sequence_field( $locus, $args );
	$buffer .= $self->_check_sequence_extended_attributes( $locus, $args );
	$buffer .= $self->_check_sequence_flags( $locus, $args );
	$buffer .= $self->_check_super_sequence( $locus, $args );
	if ($buffer) {
		$args->{'problems'}->{$pk_combination} .= $buffer;
		${ $args->{'special_problem'} } = 1;
	}
	return;
}

sub _check_sequence_allele_id {
	my ( $self,  $locus,           $args ) = @_;
	my ( $field, $file_header_pos, $data ) = @{$args}{qw(field file_header_pos data)};
	my $buffer = q();
	if ( defined $locus && $field eq 'allele_id' ) {
		if (   defined $file_header_pos->{'locus'}
			&& $data->[ $file_header_pos->{'locus'} ]
			&& any { $_ eq $data->[ $file_header_pos->{'locus'} ] } @{ $args->{'required_extended_exist'} } )
		{
			$buffer .= qq(Locus $locus has required extended attributes - please use specific )
			  . q(batch upload form for this locus.<br />);
		}
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		if (
			   defined $locus_info->{'allele_id_format'}
			&& $locus_info->{'allele_id_format'} eq 'integer'
			&& (   !defined $file_header_pos->{'allele_id'}
				|| !defined $data->[ $file_header_pos->{'allele_id'} ]
				|| $data->[ $file_header_pos->{'allele_id'} ] eq '' )
		  )
		{
			if ( $args->{'last_id'}->{$locus} ) {
				${ $args->{'value'} } = $args->{'last_id'}->{$locus};
			} else {
				${ $args->{'value'} } = $self->{'datastore'}->get_next_allele_id($locus) - 1;
			}
			my $exists;
			do {
				${ $args->{'value'} }++;
				$exists = $self->{'datastore'}->run_query(
					'SELECT EXISTS(SELECT * FROM sequences WHERE (locus,allele_id)=(?,?)) OR '
					  . 'EXISTS(SELECT * FROM retired_allele_ids WHERE (locus,allele_id)=(?,?))',
					[ $locus, ${ $args->{'value'} }, $locus, ${ $args->{'value'} } ],
					{ cache => 'CurateBatchAddPage::allele_id_exists_or_retired' }
				);
			} while $exists;
			$args->{'last_id'}->{$locus} = ${ $args->{'value'} };
			$args->{'pk_combination'} = "locus: $locus; allele_id: ${ $args->{'value'} }";
		} elsif ( defined $file_header_pos->{'allele_id'}
			&& !BIGSdb::Utils::is_int( $data->[ $file_header_pos->{'allele_id'} ] )
			&& defined $locus_info->{'allele_id_format'}
			&& $locus_info->{'allele_id_format'} eq 'integer' )
		{
			$buffer .= 'Allele id must be an integer.<br />';
		} elsif ( defined $file_header_pos->{'allele_id'}
			&& defined $data->[ $file_header_pos->{'allele_id'} ]
			&& $data->[ $file_header_pos->{'allele_id'} ] =~ /\s/x )
		{
			$buffer .= 'Allele id must not contain spaces - try substituting with underscores (_).<br />';
		}
		my $regex = $locus_info->{'allele_id_regex'};
		if ( $regex && ( $data->[ $file_header_pos->{'allele_id'} ] // q() ) !~ /$regex/x ) {
			$buffer .= "Allele id value is invalid - it must match the regular expression /$regex/.<br />";
		}
		if ( $data->[ $file_header_pos->{'allele_id'} ] ) {
			my $exists = $self->{'datastore'}->run_query(
				'SELECT EXISTS(SELECT * FROM sequences WHERE (locus,allele_id)=(?,?))',
				[ $locus, $data->[ $file_header_pos->{'allele_id'} ] ],
				{ cache => 'CurateBatchAddPage::allele_id_exists' }
			);
			if ($exists) {
				$buffer .= 'Allele id already exists.<br />';
			}
			my $retired =
			  $self->{'datastore'}
			  ->run_query( 'SELECT EXISTS(SELECT * FROM retired_allele_ids WHERE (locus,allele_id)=(?,?))',
				[ $locus, $data->[ $file_header_pos->{'allele_id'} ] ] );
			if ($retired) {
				$buffer .= 'Allele id has been retired.<br />';
			}
		}
	}
	return $buffer;
}

sub _check_sequence_length {
	my ( $self,  $locus,           $args ) = @_;
	my ( $field, $file_header_pos, $data ) = @{$args}{qw(field file_header_pos data)};
	my $q = $self->{'cgi'};

	#Check for sequence length, doesn't already exist, and is similar to existing.
	my $buffer = q();
	return $buffer if !( defined $locus && $field eq 'sequence' );
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	${ $args->{'value'} } //= '';
	${ $args->{'value'} } =~ s/ //g;
	my $length = length( ${ $args->{'value'} } );
	my $units = ( !defined $locus_info->{'data_type'} || $locus_info->{'data_type'} eq 'DNA' ) ? 'bp' : 'residues';
	if ( $length == 0 ) {
		${ $args->{'continue'} } = 0;
		return $buffer;
	}
	if (   !$locus_info->{'length_varies'}
		&& defined $locus_info->{'length'}
		&& $locus_info->{'length'} != $length )
	{
		my $problem_text =
		    "Sequence is $length $units long but this locus is set as a standard length of "
		  . "$locus_info->{'length'} $units.<br />";
		$buffer .= $problem_text
		  if !$buffer || $buffer !~ /$problem_text/x;
		${ $args->{'special_problem'} } = 1;
		return $buffer;
	}
	if ( $locus_info->{'min_length'} && $length < $locus_info->{'min_length'} ) {
		my $problem_text = "Sequence is $length $units long but this locus is set with a minimum length of "
		  . "$locus_info->{'min_length'} $units.<br />";
		$buffer .= $problem_text;
	} elsif ( $locus_info->{'max_length'} && $length > $locus_info->{'max_length'} ) {
		my $problem_text = "Sequence is $length $units long but this locus is set with a maximum length of "
		  . "$locus_info->{'max_length'} $units.<br />";
		$buffer .= $problem_text;
	} elsif ( defined $locus ) {
		${ $args->{'value'} } = uc( ${ $args->{'value'} } );
		if ( !defined $locus_info->{'data_type'} || $locus_info->{'data_type'} eq 'DNA' ) {
			${ $args->{'value'} } =~ s/[\W]//gx;
		} else {
			${ $args->{'value'} } =~ s/[^GPAVLIMCFYWHKRQNEDST\*]//gx;
		}
		my $md5_seq = md5( ${ $args->{'value'} } );
		$self->{'unique_values'}->{$locus}->{$md5_seq}++;
		if ( $self->{'unique_values'}->{$locus}->{$md5_seq} > 1 ) {
			if ( $q->param('ignore_existing') ) {
				${ $args->{'continue'} } = 0;
			} else {
				$buffer .= 'Sequence appears more than once in this submission.<br />';
			}
		}
		my $exists = $self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM sequences WHERE (locus,md5(sequence))=(?,md5(?)))',
			[ $locus, ${ $args->{'value'} } ],
			{ cache => 'CurateBatchAddPage::sequence_exists' }
		);
		if ($exists) {
			if ( $q->param('complete_CDS') || $q->param('ignore_existing') ) {
				${ $args->{'continue'} } = 0;
			} else {
				$buffer .= "Sequence already exists in the database ($locus: $exists).<br />";
			}
		}
		if ( $q->param('complete_CDS') ) {
			my $cds_check = BIGSdb::Utils::is_complete_cds( $args->{'value'} );
			${ $args->{'continue'} } = 0 if !$cds_check->{'cds'};
		}
	}
	return $buffer;
}

sub _check_sequence_field {
	my ( $self,  $locus,           $args ) = @_;
	my ( $field, $file_header_pos, $data ) = @{$args}{qw(field file_header_pos data)};
	my $buffer = q();
	return $buffer if !( defined $locus && $field eq 'sequence' );
	return $buffer if !${ $args->{'continue'} };
	my $q          = $self->{'cgi'};
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if (
		( !defined $locus_info->{'data_type'} || $locus_info->{'data_type'} eq 'DNA' )
		&& !BIGSdb::Utils::is_valid_DNA(
			${ $args->{'value'} },
			{ diploid => ( ( $self->{'system'}->{'diploid'} // '' ) eq 'yes' ? 1 : 0 ) }
		)
	  )
	{

		if ( $q->param('complete_CDS') || $q->param('ignore_non_DNA') ) {
			${ $args->{'continue'} } = 0;
		} else {
			my @chars = ( $self->{'system'}->{'diploid'} // '' ) eq 'yes' ? DIPLOID : HAPLOID;
			local $" = '|';
			$buffer .= "Sequence contains non nucleotide (@chars) characters.<br />";
		}
	} elsif ( ( !defined $locus_info->{'data_type'} || $locus_info->{'data_type'} eq 'DNA' )
		&& $self->{'datastore'}->sequences_exist($locus)
		&& !$q->param('ignore_similarity') )
	{
		my $check = $self->check_sequence_similarity( $locus, $args->{'value'} );
		if ( !$check->{'similar'} ) {
			my $id_threshold =
			  BIGSdb::Utils::is_float( $locus_info->{'id_check_threshold'} )
			  ? $locus_info->{'id_check_threshold'}
			  : IDENTITY_THRESHOLD;
			my $type = $locus_info->{'id_check_type_alleles'} ? q( type) : q();
			$buffer .=
			    qq[Sequence is too dissimilar to existing$type alleles (less than $id_threshold% identical or an ]
			  . q[alignment of less than 90% its length).  Similarity is determined by the output of the best ]
			  . q[match from the BLAST algorithm - this may be conservative.  This check will also fail if the ]
			  . q[best match is in the reverse orientation. If you're sure you want to add this sequence then make ]
			  . q[sure that the 'Override sequence similarity check' box is ticked.<br />];
		} elsif ( $check->{'subsequence_of'} ) {
			$buffer .=
			    qq[Sequence is a sub-sequence of allele-$check->{'subsequence_of'}, i.e. it is identical over its ]
			  . q[complete length but is shorter. If you're sure you want to add this sequence then make ]
			  . q[sure that the 'Override sequence similarity check' box is ticked.<br />];
		} elsif ( $check->{'supersequence_of'} ) {
			$buffer .=
			    qq[Sequence is a super-sequence of allele $check->{'supersequence_of'}, i.e. it is identical over the ]
			  . q[complete length of this allele but is longer. If you're sure you want to add this sequence then ]
			  . q[make sure that the 'Override sequence similarity check' box is ticked.<br />];
		}
	}
	return $buffer;
}

sub _check_sequence_extended_attributes {
	my ( $self,  $locus,           $args ) = @_;
	my ( $field, $file_header_pos, $data ) = @{$args}{qw(field file_header_pos data)};
	return q() if !defined $locus;
	return q() if !$args->{'extended_attributes'}->{$field};
	my @optlist;
	my %options;
	if ( $args->{'extended_attributes'}->{$field}->{'option_list'} ) {
		@optlist = split /\|/x, $args->{'extended_attributes'}->{$field}->{'option_list'};
		%options = map { $_ => 1 } @optlist;
	}
	if (
		$args->{'extended_attributes'}->{$field}->{'required'}
		&& (   !defined $file_header_pos->{$field}
			|| !defined $data->[ $file_header_pos->{$field} ]
			|| $data->[ $file_header_pos->{$field} ] eq q() )
	  )
	{
		return "'$field' is a required field and cannot be left blank.<br />";
	}
	if (   $args->{'extended_attributes'}->{$field}->{'option_list'}
		&& defined $file_header_pos->{$field}
		&& defined $data->[ $file_header_pos->{$field} ]
		&& $data->[ $file_header_pos->{$field} ] ne q()
		&& !$options{ $data->[ $file_header_pos->{$field} ] } )
	{
		local $" = ', ';
		return "Field '$field' value is not on the allowed list (@optlist).<br />";
	}
	if (
		   $args->{'extended_attributes'}->{$field}->{'format'}
		&& $args->{'extended_attributes'}->{$field}->{'format'} eq 'integer'
		&& (   defined $file_header_pos->{$field}
			&& defined $data->[ $file_header_pos->{$field} ]
			&& $data->[ $file_header_pos->{$field} ] ne '' )
		&& !BIGSdb::Utils::is_int( $data->[ $file_header_pos->{$field} ] )
	  )
	{
		return "Field '$field' must be an integer.<br />";
	}
	if (
		   $args->{'extended_attributes'}->{$field}->{'format'}
		&& $args->{'extended_attributes'}->{$field}->{'format'} eq 'boolean'
		&& (   defined $file_header_pos->{$field}
			&& lc( $data->[ $file_header_pos->{$field} ] ) ne 'false'
			&& lc( $data->[ $file_header_pos->{$field} ] ) ne 'true' )
	  )
	{
		return "Field '$field' must be boolean (either true or false).<br />";
	}
	if (   defined $file_header_pos->{$field}
		&& defined $data->[ $file_header_pos->{$field} ]
		&& $data->[ $file_header_pos->{$field} ] ne ''
		&& $args->{'extended_attributes'}->{$field}->{'regex'}
		&& $data->[ $file_header_pos->{$field} ] !~ /$args->{'extended_attributes'}->{$field}->{'regex'}/x )
	{
		return "Field '$field' does not conform to specified format.<br />\n";
	}
	return q();
}

sub _check_sequence_flags {
	my ( $self,  $locus,           $args ) = @_;
	my ( $field, $file_header_pos, $data ) = @{$args}{qw(field file_header_pos data)};
	return q() if !defined $locus;
	my $buffer = q();
	if (   ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes'
		&& $field eq 'flags'
		&& defined $file_header_pos->{'flags'} )
	{
		my @flags = split /;/x, $data->[ $file_header_pos->{'flags'} ] // q();
		foreach my $flag (@flags) {
			if ( none { $flag eq $_ } ALLELE_FLAGS ) {
				$buffer .= "Flag '$flag' is not on the list of allowed flags.<br />\n";
			}
		}
	}
	return $buffer;
}

sub _check_super_sequence {
	my ( $self,  $locus,           $args ) = @_;
	my ( $field, $file_header_pos, $data ) = @{$args}{qw(field file_header_pos data)};
	my $q = $self->{'cgi'};
	return q() if $q->param('ignore_similarity');
	return q() if !( defined $locus && $field eq 'sequence' );
	return q() if !${ $args->{'continue'} };
	my $seq = $data->[ $args->{'file_header_pos'}->{'sequence'} ];
	return q() if $self->{'cache'}->{'seqs'}->{$locus}->{$seq};
	my $allele_id = $args->{'last_id'}->{$locus} // $data->[ $file_header_pos->{'allele_id'} ];

	foreach my $test_seq ( keys %{ $self->{'cache'}->{'seqs'}->{$locus} } ) {
		if ( $seq =~ /$test_seq/x ) {
			return "Sequence is a super-sequence of allele $self->{'cache'}->{'seqs'}->{$locus}->{$test_seq} "
			  . 'submitted as part of this batch.';
		}
		if ( $test_seq =~ /$seq/x ) {
			return "Sequence is a sub-sequence of allele $self->{'cache'}->{'seqs'}->{$locus}->{$test_seq} "
			  . 'submitted as part of this batch.';
		}
	}
	$self->{'cache'}->{'seqs'}->{$locus}->{$seq} = $allele_id;
	return q();
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
