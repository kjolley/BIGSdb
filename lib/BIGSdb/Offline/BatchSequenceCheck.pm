#Written by Keith Jolley
#Copyright (c) 2019, University of Oxford
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
package BIGSdb::Offline::BatchSequenceCheck;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Offline::Script BIGSdb::CurateBatchAddPage);
use List::MoreUtils qw(any none);
use Digest::MD5 qw(md5);
use JSON;
use BIGSdb::Constants qw(ALLELE_FLAGS DIPLOID HAPLOID IDENTITY_THRESHOLD);
my $logger;

sub run {
	my ( $self, $prefix ) = @_;
	$logger = $self->{'logger'};
	my $status_file = qq($self->{'config'}->{'tmp_dir'}/${prefix}_status.json);
	my $data_file   = qq($prefix.json);
	my $full_path   = qq($self->{'config'}->{'tmp_dir'}/$data_file);
	$self->_update_status_file( $status_file, 'running', 0 );
	$self->{'username'} = $self->{'options'}->{'username'};
	my $locus = $self->{'options'}->{'locus'};
	$self->setup_submission_handler;
	my $checked_buffer = [];
	my $fields         = $self->_get_fields_in_order($locus);
	my ( $extended_attributes, $required_extended_exist ) =
	  @{ $self->_get_locus_extended_attributes($locus) }{qw(extended_attributes required_extended_exist)};
	my %last_id;
	my $problems     = {};
	my $table_header = $self->_get_field_table_header;
	my $table_buffer = qq(<div class="scrollable"><table class="resultstable"><tr>$table_header</tr>);
	my @records      = split /\n/x, $self->{'options'}->{'data'};
	my $td           = 1;
	my ( $file_header_fields, $file_header_pos ) = $self->get_file_header_data( \@records );
	my $primary_keys = [qw(locus allele_id)];
	my ( %locus_format, %locus_regex, $header_row, $header_complete, $record_count );
	my $i = 0;

	foreach my $record (@records) {
		my $progress = int( 100 * $i / @records );
		$self->_update_status_file( $status_file, 'running', $progress );
		$record =~ s/\r//gx;
		next if $record =~ /^\s*$/x;
		my $checked_record = {};
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
					problems                => $problems,
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
						table           => 'sequences',
						field           => $field,
						value           => $value,
						problems        => $problems,
						pk_combination  => $pk_combination,
						special_problem => $special_problem
					}
				);
				if ( defined $file_header_pos->{$field} || ( $field eq 'id' ) ) {
					$checked_record->{$field} = $value if defined $value && $value ne q();
				}
			}
			next if !$continue;
			$table_buffer .= qq(<tr class="td$td">$rowbuffer);
			my $new_args = {
				file_header_pos => $file_header_pos,
				data            => \@data,
			};
			$header_complete = 1;
			$table_buffer .= qq(</tr>\n);
			$self->check_permissions( $locus, $new_args, $problems, $pk_combination );
		}
		$td = $td == 1 ? 2 : 1;    #row stripes
		push @$checked_buffer, $checked_record;
	}
	$table_buffer .= q(</table></div>);
	$self->_update_status_file( $status_file, 'finished', 100 );
	$self->_write_results_file(
		$full_path,
		encode_json(
			{
				html         => $table_buffer,
				checked      => $checked_buffer,
				problems     => $problems,
				record_count => $record_count
			}
		)
	);
	return $data_file;
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
	my $locus;
	if ( $field eq 'locus' && $args->{'locus'} ) {
		${ $args->{'value'} } = $args->{'locus'};
	}
	if ( $args->{'locus'} ) {
		$locus = $args->{'locus'};
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
			if ( $self->{'options'}->{'ignore_existing'} ) {
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
			if ( $self->{'options'}->{'complete_CDS'} || $self->{'options'}->{'ignore_existing'} ) {
				${ $args->{'continue'} } = 0;
			} else {
				$buffer .= "Sequence already exists in the database ($locus: $exists).<br />";
			}
		}
		if ( $self->{'options'}->{'complete_CDS'} ) {
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
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if (
		( !defined $locus_info->{'data_type'} || $locus_info->{'data_type'} eq 'DNA' )
		&& !BIGSdb::Utils::is_valid_DNA(
			${ $args->{'value'} },
			{ diploid => ( ( $self->{'system'}->{'diploid'} // '' ) eq 'yes' ? 1 : 0 ) }
		)
	  )
	{
		if ( $self->{'options'}->{'complete_CDS'} || $self->{'options'}->{'ignore_non_DNA'} ) {
			${ $args->{'continue'} } = 0;
		} else {
			my @chars = ( $self->{'system'}->{'diploid'} // '' ) eq 'yes' ? DIPLOID : HAPLOID;
			local $" = '|';
			$buffer .= "Sequence contains non nucleotide (@chars) characters.<br />";
		}
	} elsif ( ( !defined $locus_info->{'data_type'} || $locus_info->{'data_type'} eq 'DNA' )
		&& $self->{'datastore'}->sequences_exist($locus)
		&& !$self->{'options'}->{'ignore_similarity'} )
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

sub _write_results_file {
	my ( $self, $filename, $buffer ) = @_;
	open( my $fh, '>', $filename ) || $logger->error("Cannot open $filename for writing");
	say $fh $buffer;
	close $fh;
	return;
}

sub _update_status_file {
	my ( $self, $status_file, $status, $progress ) = @_;
	open( my $fh, '>', $status_file )
	  || $self->{'logger'}->error("Cannot touch $status_file");
	say $fh qq({"status":"$status","progress":$progress});
	close $fh;
	return;
}
1;
