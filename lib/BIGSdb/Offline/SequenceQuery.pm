#Written by Keith Jolley
#Copyright (c) 2017-2018, University of Oxford
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
package BIGSdb::Offline::SequenceQuery;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Offline::Blast BIGSdb::Page);
use List::MoreUtils qw(any uniq none);
use BIGSdb::Utils;
use BIGSdb::Constants qw(:interface);

sub run {
	my ( $self, $seq ) = @_;
	my $options = $self->{'options'};
	my $loci    = $self->get_selected_loci;
	$self->{'system'}->{'set_id'} //= $self->{'options'}->{'set_id'};
	my $linked_data = {
		linked_data         => $self->_data_linked_to_loci( 'client_dbase_loci_fields',  $loci ),
		extended_attributes => $self->_data_linked_to_loci( 'locus_extended_attributes', $loci ),
	};
	if ( $options->{'batch_query'} ) {
		return $self->_batch_query( \$seq, $linked_data );
	} else {
		return $self->_single_query( \$seq, $linked_data );
	}
	return;
}

sub _data_linked_to_loci {
	my ( $self, $table, $loci ) = @_;
	my $locus_table = $self->{'datastore'}->create_temp_list_table_from_array( 'text', $loci );
	my $qry = "SELECT EXISTS(SELECT * FROM $table WHERE locus IN (SELECT value FROM $locus_table))";
	return $self->{'datastore'}->run_query($qry);
}

sub _single_query {
	my ( $self, $seq_ref, $data ) = @_;
	my $q       = $self->{'cgi'};
	my $options = $self->{'options'};
	$self->blast($seq_ref);
	my $exact_matches = $self->get_exact_matches( { details => 1 } );
	my ( $buffer, $displayed );
	my $qry_type      = BIGSdb::Utils::sequence_type($seq_ref);
	my $return_buffer = q();
	my $file          = $q->param('fasta_upload');
	if ( keys %$exact_matches ) {

		if ( $options->{'select_type'} eq 'locus' ) {
			( $buffer, $displayed ) =
			  $self->_get_distinct_locus_exact_results( $options->{'select_id'}, $exact_matches, $data );
		} else {
			( $buffer, $displayed ) = $self->_get_scheme_exact_results( $exact_matches, $data );
		}
		if ($displayed) {
			$return_buffer .= q(<div class="box" id="resultsheader"><p>);
			$return_buffer .= qq(<p><b>Uploaded file:</b> $file</p>) if $file;
			my $plural = $displayed == 1 ? q() : q(es);
			$return_buffer .= qq($displayed exact match$plural found.</p>);
			$return_buffer .= $self->_translate_button($seq_ref) if $qry_type eq 'DNA';
			$return_buffer .= q(</div>);
			$return_buffer .= q(<div class="box" id="resultstable">);
			$return_buffer .= $buffer;
			$return_buffer .= q(<div>);
		}
	} else {
		my $best_match = $self->_get_best_partial_match($seq_ref);
		if ( keys %$best_match ) {
			$return_buffer .= q(<div class="box" id="resultsheader" style="padding-top:1em">);
			$return_buffer .= qq(<p><b>Uploaded file:</b> $file</p>) if $file;
			$return_buffer .= $self->_translate_button($seq_ref) if $qry_type eq 'DNA';
			$return_buffer .= $self->_get_partial_match_results( $best_match, $data );
			$return_buffer .= q(</div>);
			$return_buffer .= q(<div class="box" id="resultspanel" style="padding-top:1em">);
			my $contig_ref = $self->get_contig( $best_match->{'query'} );
			$return_buffer .= $self->_get_partial_match_alignment( $seq_ref, $best_match, $contig_ref, $qry_type );
			$return_buffer .= q(</div>);
		} else {
			$return_buffer .= q(<div class="box" id="statusbad">);
			$return_buffer .= qq(<p><b>Uploaded file:</b> $file</p>) if $file;
			$return_buffer .= q(<p>No matches found.</p>);
			$return_buffer .= $self->_translate_button($seq_ref) if $qry_type eq 'DNA';
			$return_buffer .= q(</div>);
		}
	}
	return $return_buffer;
}

sub _batch_query {
	my ( $self, $seq_ref, $data ) = @_;
	$self->ensure_seq_has_identifer($seq_ref);
	my $contig_names = $self->_get_contig_names($seq_ref);
	my $contigs      = BIGSdb::Utils::read_fasta( $seq_ref, { allow_peptide => 1 } );
	my @headings     = qw(Contig Match Locus Allele Differences);
	local $" = q(</th><th>);
	my $table = qq(<table class="resultstable"><tr><th>@headings</th></tr>);
	my $td    = 1;
	my $loci  = $self->get_selected_loci;
  CONTIG: foreach my $name (@$contig_names) {
		my $contig_seq = $contigs->{$name};
		$self->blast( \$contig_seq );
		my $exact_matches = $self->get_exact_matches( { details => 1 } );
		my $contig_buffer;
	  LOCUS: foreach my $locus (@$loci) {
			my @exact_alleles;
			foreach my $match ( @{ $exact_matches->{$locus} } ) {
				push @exact_alleles, $self->_get_allele_link( $locus, $match->{'allele'} );
			}
			local $" = q(, );
			my $cleaned_locus = $self->clean_locus( $locus, { strip_links => 1 } );
			if (@exact_alleles) {
				$contig_buffer .= qq(<tr class="td$td"><td>$name</td>);
				$contig_buffer .= qq(<td>exact</td><td>$cleaned_locus</td><td>@exact_alleles</td><td></td></tr>);
				$td = $td == 1 ? 2 : 1;
			}
		}
		if ($contig_buffer) {
			$table .= $contig_buffer;
		} else {
			$contig_seq = $contigs->{$name};
			my $match = $self->_get_best_partial_match( \$contig_seq );
			if ( keys %$match ) {
				my $locus_info = $self->{'datastore'}->get_locus_info( $match->{'locus'} );
				my $qry_type   = BIGSdb::Utils::sequence_type($contig_seq);
				$contig_buffer .= qq(<tr class="td$td"><td>$name</td>);
				my $cleaned_locus = $self->clean_locus( $match->{'locus'}, { strip_links => 1 } );
				my $allele_link = $self->_get_allele_link( $match->{'locus'}, $match->{'allele'} );
				$contig_buffer .= qq(<td>partial</td><td>$cleaned_locus</td><td>$allele_link</td>);
				if ( $locus_info->{'data_type'} ne $qry_type ) {
					$contig_buffer .=
					    qq(<td style="text-align:left">Your query is a $qry_type sequence whereas this locus )
					  . qq(is defined with $locus_info->{'data_type'} sequences. Perform a single query to see )
					  . q(alignment.</td>);
				} elsif ( $match->{'gaps'} ) {
					$contig_buffer .=
					    q(<td style="text-align:left">There are insertions/deletions between these sequences. )
					  . q(Try single sequence query to get more details.</td>);
				} elsif ( $match->{'reverse'} ) {
					$contig_buffer .=
					  q(<td style="text-align:left">Reverse-complemented - try reversing it and query again.</td);
				} else {
					my $allele_seq_ref = $self->{'datastore'}->get_sequence( $match->{'locus'}, $match->{'allele'} );
					my $contig_ref = $self->get_contig($name);
					my $diffs =
					  $self->_get_differences( $allele_seq_ref, \$contig_seq, $match->{'sstart'}, $match->{'start'} );
					my @formatted_diffs;
					foreach my $diff (@$diffs) {
						push @formatted_diffs, $self->_format_difference( $diff, $qry_type );
					}
					my $count = @formatted_diffs;
					my $plural = $count == 1 ? q() : q(s);
					local $" = q(; );
					$contig_buffer .= qq(<td style="text-align:left">$count difference$plural found. @formatted_diffs);
					if ( !$count ) {
						$contig_buffer .=
						  qq(Your query sequence only starts at position $match->{'sstart'} of sequence.);
					}
					$contig_buffer .= q(</td>);
				}
				$contig_buffer .= q(</tr>);
				$table .= $contig_buffer;
				$td = $td == 1 ? 2 : 1;
			}
		}
		if ( !$contig_buffer ) {
			$table .= qq(<tr class="td$td"><td>$name</td><td>-</td><td></td><td></td><td></td></tr>);
			$td = $td == 1 ? 2 : 1;
		}
	}
	$table .= q(</table>);
	my $buffer;
	my $q = $self->{'cgi'};
	if ( $q->param('fasta_upload') ) {
		$buffer = q(<div class="box" id="resultsheader"><p>);
		my $file = $q->param('fasta_upload');
		$buffer .= qq(<p><b>Uploaded file:</b> $file</p></div>);
	}
	$buffer .= q(<div class="box" id="resultstable">);
	$buffer .= qq(<div class="scrollable">\n$table</div>);
	my $output_file = BIGSdb::Utils::get_random() . q(.txt);
	my $full_path   = "$self->{'config'}->{'tmp_dir'}/$output_file";
	open( my $fh, '>', $full_path ) || $self->{'logger'}->error("Cannot open $full_path for writing");
	say $fh BIGSdb::Utils::convert_html_table_to_text($table);
	close $fh;
	$buffer .= qq(<p style="margin-top:1em">Download: <a href="/tmp/$output_file">text format</a></p>);
	$buffer .= q(</div>);
	return $buffer;
}

sub _get_distinct_locus_exact_results {
	my ( $self, $locus, $exact_matches, $data ) = @_;
	my $locus_info   = $self->{'datastore'}->get_locus_info($locus);
	my $match_count  = 0;
	my $td           = 1;
	my $buffer       = q();
	my $match_buffer = $self->_get_locus_matches(
		{
			locus           => $locus,
			exact_matches   => $exact_matches,
			data            => $data,
			match_count_ref => \$match_count,
			td_ref          => \$td
		}
	);
	if ($match_buffer) {
		$buffer = qq(<div class="scrollable">\n);
		$buffer .= $self->_get_table_header($data);
		$buffer .= $match_buffer;
		$buffer .= qq(</table></div>\n);
	}
	return ( $buffer, $match_count );
}

sub _get_best_partial_match {
	my ( $self, $seq_ref ) = @_;
	my $best_match = $self->get_best_partial_match;
	return {} if !keys %$best_match;
	if ( ( $self->{'system'}->{'exemplars'} // q() ) ne 'yes' ) {    #Not using exemplars so this is best match
		return $best_match;
	}
	my $loci = $self->get_selected_loci;    #Get locus list so that we can restore object after BLASTing single locus

	#The best match is only the best matching exemplar so we need to repeat the query using all
	#alleles for the identified locus.
	$self->_reset_blast_object( [ $best_match->{'locus'} ] );
	$self->blast($seq_ref);

	#Return BLAST object to previous state.
	$self->_reset_blast_object($loci);
	return $self->get_best_partial_match;
}

sub _reset_blast_object {
	my ( $self, $loci ) = @_;
	local $" = q(,);
	$self->{'options'}->{'l'} = qq(@$loci);
	undef $self->{'options'}->{$_} foreach qw(seq_ref exact_matches partial_matches);
	$self->{'options'}->{'exemplar'} = ( $self->{'system'}->{'exemplars'} // q() ) eq 'yes' ? 1 : 0;
	$self->{'options'}->{'exemplar'} = 0 if @$loci == 1;
	return;
}

sub _get_scheme_exact_results {
	my ( $self, $exact_matches, $data ) = @_;
	my $options = $self->{'options'};
	my $set_id  = $options->{'set_id'};
	my @schemes;
	if ( $options->{'select_type'} eq 'all' ) {
		push @schemes, 0;
	} elsif ( $options->{'select_type'} eq 'scheme' ) {
		push @schemes, $options->{'select_id'};
	} elsif ( $options->{'select_type'} eq 'group' ) {
		my $group_schemes =
		  $self->{'datastore'}->get_schemes_in_group( $options->{'select_id'}, { set_id => $set_id } );
		push @schemes, @$group_schemes;
	}
	my $match_count  = 0;
	my $designations = {};
	my $buffer       = q();
	foreach my $scheme_id (@schemes) {
		my $scheme_buffer = q();
		my $td            = 1;
		my $scheme_members;
		if ($scheme_id) {
			$scheme_members = $self->{'datastore'}->get_scheme_loci($scheme_id);
			next if none { $exact_matches->{$_} } @$scheme_members;
		} else {
			$scheme_members = $self->{'datastore'}->get_loci( { set_id => $set_id } );
		}
		foreach my $locus (@$scheme_members) {
			$scheme_buffer .= $self->_get_locus_matches(
				{
					locus           => $locus,
					exact_matches   => $exact_matches,
					data            => $data,
					match_count_ref => \$match_count,
					td_ref          => \$td,
					designations    => $designations
				}
			);
		}
		if ($scheme_buffer) {
			if ($scheme_id) {
				my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
				$buffer .= qq(<h2>$scheme_info->{'name'}</h2>);
			}
			my $table = $self->_get_table_header($data);
			$table  .= $scheme_buffer;
			$table  .= q(</table>);
			$buffer .= qq(<div class="scrollable">\n$table</div>\n);
			my $text        = BIGSdb::Utils::convert_html_table_to_text($table);
			my $output_file = BIGSdb::Utils::get_random() . q(.txt);
			my $full_path   = "$self->{'config'}->{'tmp_dir'}/$output_file";
			open( my $fh, '>', $full_path ) || $self->{'logger'}->error("Cannot open $full_path for writing");
			say $fh BIGSdb::Utils::convert_html_table_to_text($table);
			close $fh;
			$buffer .= qq(<p style="margin-top:1em">Download: <a href="/tmp/$output_file">text format</a></p>);
		}
		$buffer .= $self->_get_scheme_fields( $scheme_id, $designations );
	}
	if ( !@schemes ) {
		$buffer .= $self->_get_scheme_fields( 0, $designations );
	}
	return ( $buffer, $match_count );
}

sub _translate_button {
	my ( $self, $seq_ref ) = @_;
	return q() if ref $seq_ref ne 'SCALAR' || length $$seq_ref < 3 || length $$seq_ref > 10000;
	return q() if !$self->{'config'}->{'emboss_path'};
	return q() if !$self->is_page_allowed('sequenceTranslate');
	my $contigs = () = $$seq_ref =~ />/gx;
	return q() if $contigs > 1;
	my $seq = $$seq_ref;
	$seq =~ s/^>.*?\n//x;    #Remove identifier line if exists
	$seq =~ s/\s//gx;
	my $q      = $self->{'cgi'};
	my $buffer = $q->start_form;
	$q->param( page     => 'sequenceTranslate' );
	$q->param( sequence => $seq );
	$buffer .= $q->hidden($_) foreach (qw (db page sequence));
	$buffer .= $q->submit( -label => 'Translate query', -class => BUTTON_CLASS );
	$buffer .= $q->end_form;
	return $buffer;
}

sub _get_locus_matches {
	my ( $self, $args ) = @_;
	my ( $locus, $exact_matches, $data, $match_count_ref, $td_ref, $designations ) =
	  @{$args}{qw(locus exact_matches data match_count_ref td_ref designations)};
	my $buffer      = q();
	my $locus_info  = $self->{'datastore'}->get_locus_info($locus);
	my $locus_count = 0;
	foreach my $match ( @{ $exact_matches->{$locus} } ) {
		my ( $field_values, $attributes, $allele_info, $flags );
		$$match_count_ref++;
		next if $locus_info->{'match_longest'} && $locus_count > 1;
		$designations->{$locus} //= [];
		my %existing_alleles = map { $_ => 1 } @{ $designations->{$locus} };
		push @{ $designations->{$locus} }, $match->{'allele'} if !$existing_alleles{ $match->{'allele'} };
		my $allele_link = $self->_get_allele_link( $locus, $match->{'allele'} );
		my $cleaned_locus = $self->clean_locus( $locus, { strip_links => 1 } );
		$buffer .= qq(<tr class="td$$td_ref"><td>$cleaned_locus</td><td>$allele_link</td>);
		$field_values =
		  $self->{'datastore'}->get_client_data_linked_to_allele( $locus, $match->{'allele'}, { table_format => 1 } );
		$self->{'linked_data'}->{$locus}->{ $match->{'allele'} } = $field_values->{'values'};
		$attributes = $self->{'datastore'}->get_allele_attributes( $locus, [ $match->{'allele'} ] );
		$allele_info = $self->{'datastore'}->run_query(
			'SELECT * FROM sequences WHERE (locus,allele_id)=(?,?)',
			[ $locus, $match->{'allele'} ],
			{ fetch => 'row_hashref' }
		);
		$flags = $self->{'datastore'}->get_allele_flags( $locus, $match->{'allele'} );
		$buffer .= qq(<td>$match->{'length'}</td><td>$match->{'query'}</td><td>$match->{'start'}</td>)
		  . qq(<td>$match->{'end'}</td>);
		$buffer .=
		  defined $field_values ? qq(<td style="text-align:left">$field_values->{'formatted'}</td>) : q(<td></td>)
		  if $data->{'linked_data'};
		$buffer .= defined $attributes ? qq(<td style="text-align:left">$attributes</td>) : q(<td></td>)
		  if $data->{'extended_attributes'};

		if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
			local $" = q(</a> <a class="seqflag_tooltip">);
			$buffer .=
			  @$flags ? qq(<td style="text-align:left"><a class="seqflag_tooltip">@$flags</a></td>) : q(<td></td>);
		}
		if ( ( $self->{'system'}->{'allele_comments'} // '' ) eq 'yes' ) {
			$buffer .= $allele_info->{'comments'} ? qq(<td>$allele_info->{'comments'}</td>) : q(<td></td>);
		}
		$buffer .= qq(</tr>\n);
		$$td_ref = $$td_ref == 1 ? 2 : 1;
		$locus_count++;
	}
	return $buffer;
}

sub _get_allele_link {
	my ( $self, $locus, $allele_id ) = @_;
	if ( $self->is_page_allowed('alleleInfo') ) {
		return qq(<a href="$self->{'options'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=alleleInfo&amp;locus=$locus&amp;allele_id=$allele_id">$allele_id</a>);
	}
	return qq($allele_id);
}

sub _get_table_header {
	my ( $self, $data ) = @_;
	my $buffer =
	    q(<table class="resultstable"><tr><th>Locus</th><th>Allele</th><th>Length</th>)
	  . q(<th>Contig</th><th>Start position</th><th>End position</th>)
	  . ( $data->{'linked_data'}         ? '<th>Linked data values</th>' : q() )
	  . ( $data->{'extended_attributes'} ? '<th>Attributes</th>'         : q() )
	  . ( ( $self->{'system'}->{'allele_flags'}    // '' ) eq 'yes' ? q(<th>Flags</th>)    : q() )
	  . ( ( $self->{'system'}->{'allele_comments'} // '' ) eq 'yes' ? q(<th>Comments</th>) : q() )
	  . q(</tr>);
	return $buffer;
}

sub _get_scheme_fields {
	my ( $self, $scheme_id, $designations ) = @_;
	my $buffer = q();
	if ( !$scheme_id ) {    #all loci
		my $schemes = $self->get_scheme_data( { with_pk => 1 } );
		foreach my $scheme (@$schemes) {
			my $scheme_loci = $self->{'datastore'}->get_scheme_loci( $scheme->{'id'} );
			if ( any { defined $designations->{$_} } @$scheme_loci ) {
				$buffer .= $self->_get_scheme_table( $scheme->{'id'}, $designations );
			}
		}
	} else {
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		my $scheme_loci   = $self->{'datastore'}->get_scheme_loci($scheme_id);
		if ( @$scheme_fields && @$scheme_loci ) {
			$buffer .= $self->_get_scheme_table( $scheme_id, $designations );
		}
	}
	return $buffer;
}

sub _get_scheme_table {
	my ( $self, $scheme_id, $designations ) = @_;
	my ( @profile, @temp_qry );
	my $set_id = $self->{'options'}->{'set_id'};
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	return q() if !defined $scheme_info->{'primary_key'};
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $scheme_loci   = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $missing_loci;

	foreach my $locus (@$scheme_loci) {
		$missing_loci = 1 if !defined $designations->{$locus};
		my $alleles = $designations->{$locus};
		foreach my $allele (@$alleles) {
			$allele =~ s/'/\\'/gx;
		}
		push @profile, $alleles;
		$designations->{$locus} //= [0];
		my $locus_profile_name = $self->{'datastore'}->get_scheme_warehouse_locus_name( $scheme_id, $locus );
		local $" = q(',E');
		push @$alleles, q(N) if $scheme_info->{'allow_missing_loci'};
		my $temp_qry = "$locus_profile_name IN (E'@$alleles')";
		push @temp_qry, $temp_qry;
	}
	if ( !$missing_loci || $scheme_info->{'allow_missing_loci'} ) {
		local $" = ') AND (';
		my $temp_qry_string = "@temp_qry";
		local $" = ',';
		my $all_values =
		  $self->{'datastore'}->run_query( "SELECT @$scheme_fields FROM mv_scheme_$scheme_id WHERE ($temp_qry_string)",
			undef, { fetch => 'all_arrayref', slice => {} } );
		return q() if !@$all_values;
		my $buffer;
		$buffer .= qq(<h2>$scheme_info->{'name'}</h2>) if $self->{'cgi'}->param('locus') eq '0';
		$buffer .= q(<dl class="data">);
		my $td           = 1;
		my $field_values = {};
		my %populated_fields;

		foreach my $value (@$all_values) {
			foreach my $field (@$scheme_fields) {
				$field_values->{$field} //= [];
				my %existing = map { $_ => 1 } @{ $field_values->{$field} };
				if ( defined $value->{ lc($field) } && !$existing{ $value->{ lc($field) } } ) {
					push @{ $field_values->{$field} }, $value->{ lc($field) };
					$populated_fields{$field} = 1;
				}
			}
		}
		my $max_chars = $self->_get_longest_heading_width( [ keys %populated_fields ] );
		my $width     = int( 0.6 * $max_chars ) + 2;
		my $margin    = $width + 1;
		foreach my $field (@$scheme_fields) {
			my $values = $field_values->{$field};
			next if !@$values;
			@$values = sort @$values;
			my $primary_key = $field eq $scheme_info->{'primary_key'} ? 1 : 0;
			$field =~ tr/_/ /;
			$buffer .= qq(<dt style="width:${width}em">$field</dt><dd style="margin: 0 0 0 ${margin}em">);
			local $" = q(, );
			if ( $primary_key && $self->is_page_allowed('profileInfo') ) {
				my @linked_values;
				foreach my $value (@$values) {
					push @linked_values,
					  qq(<a href="$self->{'options'}->{'script_name'}?page=profileInfo&amp;db=$self->{'instance'}&amp;)
					  . qq(scheme_id=$scheme_id&amp;profile_id=$value">$value</a>);
				}
				$buffer .= qq(@linked_values);
			} else {
				$buffer .= qq(@$values);
			}
			$buffer .= q(</dd>);
			$td = $td == 1 ? 2 : 1;
		}
		$buffer .= q(</dl>);
		return $buffer;
	}
	return q();
}

sub _get_longest_heading_width {
	my ( $self, $headings ) = @_;
	my $longest = 1;
	foreach my $heading (@$headings) {
		if ( length $heading > $longest ) {
			$longest = length $heading;
		}
	}
	return $longest;
}

sub _get_contig_names {
	my ( $self, $seq_ref ) = @_;
	my @lines = split /\r?\n/x, $$seq_ref;
	my $names = [];
	foreach my $line (@lines) {
		if ( $line =~ /^>/x ) {
			( my $name = $line ) =~ s/^>//x;
			$name =~ s/\s.*$//x;
			push @$names, $name;
		}
	}
	return $names;
}

sub _get_differences {

	#returns differences between two sequences where there are no gaps
	my ( $self, $seq1_ref, $seq2_ref, $sstart, $qstart ) = @_;
	my $qpos = $qstart - 1;
	my @diffs;
	if ( $sstart > $qstart ) {
		foreach my $spos ( $qstart .. $sstart - 1 ) {
			my $diff;
			$diff->{'spos'}  = $spos;
			$diff->{'sbase'} = substr( $$seq1_ref, $spos, 1 );
			$diff->{'qbase'} = 'missing';
			push @diffs, $diff;
		}
	}
	for ( my $spos = $sstart - 1 ; $spos < length $$seq1_ref ; $spos++ ) {
		my $diff;
		$diff->{'spos'} = $spos + 1;
		$diff->{'sbase'} = substr( $$seq1_ref, $spos, 1 );
		if ( $qpos < length $$seq2_ref && substr( $$seq1_ref, $spos, 1 ) ne substr( $$seq2_ref, $qpos, 1 ) ) {
			$diff->{'qpos'} = $qpos + 1;
			$diff->{'qbase'} = substr( $$seq2_ref, $qpos, 1 );
			push @diffs, $diff;
		} elsif ( $qpos >= length $$seq2_ref ) {
			$diff->{'qbase'} = 'missing';
			push @diffs, $diff;
		}
		$qpos++;
	}
	return \@diffs;
}

sub _format_difference {
	my ( $self, $diff, $qry_type ) = @_;
	my $buffer;
	if ( $qry_type eq 'DNA' ) {
		$buffer .= qq(<sup>$diff->{'spos'}</sup>);
		$buffer .= qq(<span class="$diff->{'sbase'}">$diff->{'sbase'}</span>);
		$buffer .= q( &rarr; );
		$buffer .= defined $diff->{'qpos'} ? qq(<sup>$diff->{'qpos'}</sup>) : q();
		$buffer .= qq(<span class="$diff->{'qbase'}">$diff->{'qbase'}</span>);
	} else {
		$buffer .= qq(<sup>$diff->{'spos'}</sup>);
		$buffer .= $diff->{'sbase'};
		$buffer .= q( &rarr; );
		$buffer .= defined $diff->{'qpos'} ? qq(<sup>$diff->{'qpos'}</sup>) : q();
		$buffer .= "$diff->{'qbase'}";
	}
	return $buffer;
}

sub _get_partial_match_results {
	my ( $self, $partial_match, $data ) = @_;
	return q() if !keys %$partial_match;
	my $cleaned_locus = $self->clean_locus( $partial_match->{'locus'}, { strip_links => 1 } );
	my $allele_link = $self->_get_allele_link( $partial_match->{'locus'}, $partial_match->{'allele'} );
	my $buffer      = qq(<p style="margin-top:0.5em">Closest match: $cleaned_locus: $allele_link);
	my $flags       = $self->{'datastore'}->get_allele_flags( $partial_match->{'locus'}, $partial_match->{'allele'} );
	my $field_values =
	  $self->{'datastore'}->get_client_data_linked_to_allele( $partial_match->{'locus'}, $partial_match->{'allele'} );
	if ( ref $flags eq 'ARRAY' ) {
		local $" = q(</a> <a class="seqflag_tooltip">);
		my $plural = @$flags == 1 ? '' : 's';
		$buffer .= qq( (Flag$plural: <a class="seqflag_tooltip">@$flags</a>)) if @$flags;
	}
	$buffer .= q(</p>);
	if ( $field_values->{'formatted'} ) {
		$buffer .= q(<p>This match is linked to the following data:</p>);
		$buffer .= $field_values->{'formatted'};
	}
	return $buffer;
}

sub _get_partial_match_alignment {
	my ( $self, $seq_ref, $match, $contig_ref, $qry_type ) = @_;
	my $buffer     = q();
	my $locus_info = $self->{'datastore'}->get_locus_info( $match->{'locus'} );
	if ( $locus_info->{'data_type'} eq $qry_type ) {
		$buffer .= $self->_get_differences_output( $match, $contig_ref, $qry_type );
	} else {
		$self->_reset_blast_object( [ $match->{'locus'} ] );
		my $align_file = $self->blast( $seq_ref, { num_results => 5, alignment => 1 } );
		$buffer .=
		    qq(<p>Your query is a $qry_type sequence whereas this locus is defined with )
		  . ( $qry_type eq 'DNA' ? 'peptide' : 'DNA' )
		  . q( sequences.  There were no exact matches, but the BLAST results are shown below )
		  . q((a maximum of five alignments are displayed).</p>)
		  . q(<pre style="font-size:1.4em; padding: 1em; border:1px black dashed">);
		$buffer .= $self->print_file( $align_file, { ignore_hashlines => 1, get_only => 1 } );
		$buffer .= q(</pre>);
		unlink $align_file;
	}
	return $buffer;
}

sub _get_differences_output {
	my ( $self, $match, $contig_ref, $qry_type ) = @_;
	my $allele_seq_ref = $self->{'datastore'}->get_sequence( $match->{'locus'}, $match->{'allele'} );
	my $temp           = BIGSdb::Utils::get_random();
	my $seq1_infile    = "$self->{'config'}->{'secure_tmp_dir'}/${temp}_file1.txt";
	my $seq2_infile    = "$self->{'config'}->{'secure_tmp_dir'}/${temp}_file2.txt";
	my $outfile        = "$self->{'config'}->{'tmp_dir'}/${temp}_outfile.txt";
	open( my $seq1_fh, '>', $seq2_infile ) || $self->{'logger'}->error("Cannot open $seq2_infile for writing");
	say $seq1_fh ">Ref\n$$allele_seq_ref";
	close $seq1_fh;
	open( my $seq2_fh, '>', $seq1_infile ) || $self->{'logger'}->error("Cannot open $seq1_infile for writing");
	say $seq2_fh ">Query\n$$contig_ref";
	close $seq2_fh;
	my $reverse = $match->{'reverse'} ? 1 : 0;
	my @args = (
		-aformat   => 'markx2',
		-awidth    => $self->{'options'}->{'align_width'},
		-asequence => $seq1_infile,
		-bsequence => $seq2_infile,
		-outfile   => $outfile
	);
	push @args, ( -sreverse1 => 1 ) if $reverse;

	if ( length $$contig_ref > 10000 ) {
		if ( $match->{'predicted_start'} =~ /^(\d+)$/x ) {
			push @args, ( -sbegin1 => $1 );    #Untaint
		}
		if ( $match->{'predicted_end'} =~ /^(\d+)$/x ) {
			push @args, ( -send1 => $1 );
		}
	}
	local $" = q( );
	system("$self->{'config'}->{'emboss_path'}/stretcher @args 2>/dev/null");
	unlink $seq1_infile, $seq2_infile;
	my $buffer;
	if ( !$match->{'gaps'} ) {
		if ($reverse) {
			$buffer .=
			    q(<p>The sequence is reverse-complemented with respect to the reference sequence. )
			  . q(It has been reverse-complemented in the alignment but try reverse complementing )
			  . q(your query sequence in order to see a list of differences.</p>);
			$buffer .= $self->get_alignment( $outfile, $temp );
			return $buffer;
		}
		$buffer .= $self->get_alignment( $outfile, $temp );
		my $match_seq = $match->{'sequence'};
		while ( $match->{'sstart'} > 1 && $match->{'start'} > 1 ) {
			$match->{'sstart'}--;
			$match->{'start'}--;
		}
		my $diffs = $self->_get_differences( $allele_seq_ref, $contig_ref, $match->{'sstart'}, $match->{'start'} );
		$buffer .= q(<h2>Differences</h2>);
		if ( $match->{'query'} ne 'Query' ) {
			$buffer .= qq(<p>Contig: $match->{'query'}<p>);
		}
		my $non_missing_diffs = 0;
		if (@$diffs) {
			my $pos         = 0;
			my $diff_buffer = q();
			foreach my $diff (@$diffs) {
				$pos++;
				next if $pos < $match->{'sstart'};
				if ( $diff->{'qbase'} eq 'missing' ) {
					$diff_buffer .= qq(Truncated at position $diff->{'spos'} on reference sequence.);
					last;
				}
				$non_missing_diffs++;
				$diff_buffer .= $self->_format_difference( $diff, $qry_type ) . q(<br />);
			}
			my $plural = $non_missing_diffs > 1 ? 's' : '';
			$buffer .= qq(<p>$non_missing_diffs difference$plural found.);
			if ($non_missing_diffs) {
				$buffer .= $self->get_tooltip(
					qq(differences - The information to the left of the arrow$plural shows the identity and position )
					  . q(on the reference sequence and the information to the right shows the corresponding identity )
					  . q(and position on your query sequence.) );
			}
			$buffer .= qq(</p><p>$diff_buffer</p>);
			if ( $match->{'sstart'} > 1 ) {
				$buffer .= qq(<p>Your query sequence only starts at position $match->{'sstart'} of sequence.</p>);
			} else {
				$buffer .=
				    q(<p>The locus start point is at position )
				  . ( $match->{'start'} - $match->{'sstart'} + 1 )
				  . q( of your query sequence.);
				$buffer .= $self->get_tooltip(
					q(start position - This may be approximate if there are gaps near the beginning of the alignment )
					  . q(between your query and the reference sequence) );
			}
		} else {
			$buffer .= qq(<p>Your query sequence only starts at position $match->{'sstart'} of sequence.);
		}
	} else {
		$buffer .= q(<p>An alignment between your query and the returned reference sequence is shown rather )
		  . q(than a simple list of differences because there are gaps in the alignment.</p>);
		$buffer .= q(<div class="scrollable">);
		$buffer .= q(<pre style="font-size:1.2em">);
		$buffer .= $self->print_file( $outfile, { get_only => 1, ignore_hashlines => 1 } );
		$buffer .= q(</pre></div>);
		my @files = glob("$self->{'config'}->{'secure_tmp_dir'}/$temp*");
		foreach (@files) { unlink $1 if /^(.*BIGSdb.*)$/x }
	}
	return $buffer;
}

sub get_alignment {
	my ( $self, $outfile, $outfile_prefix ) = @_;
	my $buffer = '';
	if ( -e $outfile ) {
		my $cleaned_file = "$self->{'config'}->{'tmp_dir'}/${outfile_prefix}_cleaned.txt";
		$self->_cleanup_alignment( $outfile, $cleaned_file );
		$buffer .= qq(<p><a href="/tmp/${outfile_prefix}_cleaned.txt" id="alignment_link" data-rel="ajax">)
		  . qq(Show alignment</a></p>\n);
		$buffer .= q(<div class="scrollable">);
		$buffer .= qq(<pre style="font-size:1.2em"><span id="alignment"></span></pre></div>\n);
	}
	return $buffer;
}

sub get_allele_linked_data {
	my ($self) = @_;
	return $self->{'linked_data'};
}

sub _cleanup_alignment {
	my ( $self, $infile, $outfile ) = @_;
	open( my $in_fh,  '<', $infile )  || $self->{'logger'}->error("Cannot open $infile for reading");
	open( my $out_fh, '>', $outfile ) || $self->{'logger'}->error("Cannot open $outfile for writing");
	while (<$in_fh>) {
		next if $_ =~ /^\#/x;
		print $out_fh $_;
	}
	close $in_fh;
	close $out_fh;
	return;
}
1;
