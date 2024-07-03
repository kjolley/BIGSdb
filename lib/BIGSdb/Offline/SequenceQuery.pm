#Written by Keith Jolley
#Copyright (c) 2017-2024, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
use BIGSdb::Exceptions;
use BIGSdb::Utils;
use BIGSdb::Constants qw(:interface);
use Try::Tiny;
use Storable qw(dclone);
use Encode;
use constant MAX_RESULTS_SHOW => 20;

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
	my $qry         = "SELECT EXISTS(SELECT * FROM $table WHERE locus IN (SELECT value FROM $locus_table))";
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
	my $file          = decode( 'UTF-8', $q->param('fasta_upload') );

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
			$return_buffer .= q(</div>);
		}
	} else {
		my $best_match = $self->_get_best_partial_match($seq_ref);
		if ( keys %$best_match ) {
			$return_buffer .= q(<div class="box" id="resultsheader" style="padding-top:1em">);
			$return_buffer .= qq(<p><b>Uploaded file:</b> $file</p>) if $file;
			$return_buffer .= $self->_translate_button($seq_ref)     if $qry_type eq 'DNA';
			$return_buffer .= $self->_get_partial_match_results( $best_match, $data );
			$return_buffer .= q(</div>);
			$return_buffer .= q(<div class="box" id="resultspanel" style="padding-top:1em">);
			my $contig_ref = $self->get_contig( $best_match->{'query'} );
			$return_buffer .= $self->_get_partial_match_alignment( $seq_ref, $best_match, $contig_ref, $qry_type );

			if ( !$self->_is_match_size_unlikely($best_match) ) {
				$return_buffer .= q(<p style="margin-top:1em">);
				$return_buffer .= $self->_make_match_download_seq_file($best_match);
				$return_buffer .= $self->_start_submission($best_match);
				$return_buffer .= q(</p>);
			}
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

sub _is_match_size_unlikely {
	my ( $self, $match ) = @_;
	my $locus_stats =
	  $self->{'datastore'}
	  ->run_query( 'SELECT * FROM locus_stats WHERE locus=?', $match->{'locus'}, { fetch => 'row_hashref' } );
	return 1 if length $match->{'sequence'} > $locus_stats->{'max_length'};
	return 1 if length $match->{'sequence'} < $locus_stats->{'min_length'};
	return;
}

sub _make_match_download_seq_file {
	my ( $self, $match ) = @_;
	my $prefix    = BIGSdb::Utils::get_random();
	my $filename  = "$prefix.fas";
	my $full_path = qq($self->{'config'}->{'tmp_dir'}/$filename);
	my $direction = $match->{'reverse'} ? 'reverse' : 'forward';
	open( my $fh, '>', $full_path ) || $self->{'logger'}->error("Cannot open $full_path for writing");
	say $fh qq(>match start:$match->{'predicted_start'} end:$match->{'predicted_end'} direction:$direction);
	say $fh $match->{'sequence'};
	close $fh;
	my $buffer = q();

	if ( -e $full_path ) {
		my $fasta = FASTA_FILE;
		$buffer .= qq(<a href="/tmp/$filename" target="_blank" )
		  . qq(title="Export extracted sequence in FASTA format">$fasta</a>);
	}
	if ( $match->{'flanking_sequence'} && length $match->{'flanking_sequence'} > length $match->{'sequence'} ) {
		$filename  = "${prefix}_flanking.fas";
		$full_path = qq($self->{'config'}->{'tmp_dir'}/$filename);
		open( my $fh, '>', $full_path ) || $self->{'logger'}->error("Cannot open $full_path for writing");
		say $fh qq(>match start:$match->{'predicted_start'}; end:$match->{'predicted_end'}; including flanking )
		  . qq(sequence; direction:$direction);
		say $fh $match->{'flanking_sequence'};
		close $fh;
		if ( -e $full_path ) {
			my $fasta = FASTA_FLANKING_FILE;
			$buffer .= qq(<a href="/tmp/$filename" target="_blank" )
			  . qq(title="Export extracted sequence in FASTA format (including flanking sequence)">$fasta</a>);
		}
	}
	return $buffer;
}

sub _start_submission {
	my ( $self, $match, $fasta_file ) = @_;
	return q() if ( $self->{'system'}->{'submissions'} // q() ) ne 'yes';
	my $locus_info = $self->{'datastore'}->get_locus_info( $match->{'locus'} );
	return q() if $locus_info->{'no_submissions'};
	return q() if $locus_info->{'min_length'}     && $locus_info->{'min_length'} > length $match->{'sequence'};
	return q() if $locus_info->{'max_length'}     && $locus_info->{'max_length'} < length $match->{'sequence'};
	return q() if !$locus_info->{'length_varies'} && $locus_info->{'length'} != length $match->{'sequence'};
	my $upload   = SUBMIT_BUTTON;
	my $seq_file = $self->make_temp_file( $match->{'sequence'} );
	return
		qq(<a href="?db=$self->{'instance'}&amp;page=submit&amp;alleles=1&amp;)
	  . qq(locus=$match->{'locus'}&amp;sequence_file=$seq_file" target="_blank" )
	  . qq(title="Start submission for new allele assignment">$upload</a>);
}

sub _batch_query {
	my ( $self, $seq_ref, $data ) = @_;
	$self->ensure_seq_has_identifer($seq_ref);
	my $contig_names = $self->_get_contig_names($seq_ref);
	my $contigs;
	my $error;
	try {
		$contigs = BIGSdb::Utils::read_fasta( $seq_ref, { allow_peptide => 1 } );
	} catch {
		$error = $_;
	};
	if ($error) {
		return $self->print_bad_status(
			{
				message  => q(Query error),
				detail   => $error,
				get_only => 1
			}
		);
	}
	my @headings = qw(Contig Match Locus Allele Differences);
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
				my $allele_link   = $self->_get_allele_link( $match->{'locus'}, $match->{'allele'} );
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
					my $contig_ref     = $self->get_contig($name);
					while ( $match->{'sstart'} > 1 && $match->{'start'} > 1 ) {
						$match->{'sstart'}--;
						$match->{'start'}--;
					}
					my $diffs =
					  $self->_get_differences( $allele_seq_ref, \$contig_seq, $match->{'sstart'}, $match->{'start'} );
					my @formatted_diffs;
					foreach my $diff (@$diffs) {
						push @formatted_diffs, $self->_format_difference( $diff, $qry_type );
					}
					my $count  = @formatted_diffs;
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
				$table         .= $contig_buffer;
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
		my $file = decode( 'UTF-8', $q->param('fasta_upload') );
		$buffer .= qq(<p><b>Uploaded file:</b> $file</p></div>);
	}
	$buffer .= q(<div class="box" id="resultstable">);
	$buffer .= qq(<div class="scrollable">\n$table</div>);
	my $output_file = BIGSdb::Utils::get_random();
	my $full_path   = "$self->{'config'}->{'tmp_dir'}/$output_file.txt";
	open( my $fh, '>:encoding(utf8)', $full_path ) || $self->{'logger'}->error("Cannot open $full_path for writing");
	say $fh BIGSdb::Utils::convert_html_table_to_text($table);
	close $fh;
	my ( $text, $excel ) = ( TEXT_FILE, EXCEL_FILE );
	$buffer .= q(<p style="margin-top:1em">)
	  . qq(<a href="/tmp/$output_file.txt" title="Download in tab-delimited text format">$text</a>);
	my $excel_file = BIGSdb::Utils::text2excel($full_path);

	if ( -e $excel_file ) {
		$buffer .= qq(<a href="/tmp/$output_file.xlsx" title="Download in Excel format">$excel</a>);
	}
	$buffer .= q(</p></div>);
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
	if ( !$self->{'options'}->{'exemplar'} ) {    #Not using exemplars so this is best match
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
			my $table = $self->_get_table_header($data);
			$table .= $scheme_buffer;
			$table .= q(</table>);
			my $hide  = $match_count > MAX_RESULTS_SHOW;
			my $class = $hide ? q(expandable_retracted_large) : q();
			$buffer .= qq(<div id="matches" class="$class"><div class="scrollable">$table</div></div>);
			if ($hide) {
				$buffer .=
				  q(<div class="expand_link" id="expand_matches"><span class="fas fa-chevron-down"></span></div>);
			}
			$buffer .= q(<p style="margin-top:1em">Only exact matches are shown above. If a locus does not have an )
			  . q(exact match, try querying specifically against that locus to find the closest match.</p>);
			my $output_file = BIGSdb::Utils::get_random();
			my $full_path   = "$self->{'config'}->{'tmp_dir'}/$output_file.txt";
			open( my $fh, '>:encoding(utf8)', $full_path )
			  || $self->{'logger'}->error("Cannot open $full_path for writing");
			say $fh BIGSdb::Utils::convert_html_table_to_text($table);
			close $fh;
			my ( $text, $excel ) = ( TEXT_FILE, EXCEL_FILE );
			$buffer .= qq(<p style="margin-top:1em"><a href="/tmp/$output_file.txt" )
			  . qq(title="Download in tab-delimited text format">$text</a>);
			my $excel_file = BIGSdb::Utils::text2excel($full_path);

			if ( -e $excel_file ) {
				$buffer .= qq(<a href="/tmp/$output_file.xlsx" title="Download in Excel format">$excel</a>);
			}
			$buffer .= q(</p>);
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
	$buffer .= $q->submit( -label => 'Translate query', -class => 'small_submit' );
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
		my $allele_link   = $self->_get_allele_link( $locus, $match->{'allele'} );
		my $cleaned_locus = $self->clean_locus( $locus, { strip_links => 1 } );
		$buffer .= qq(<tr class="td$$td_ref"><td>$cleaned_locus</td><td>$allele_link</td>);
		$field_values =
		  $self->{'datastore'}->get_client_data_linked_to_allele( $locus, $match->{'allele'}, { table_format => 1 } );
		$self->{'linked_data'}->{$locus}->{ $match->{'allele'} } = $field_values->{'values'};
		$attributes  = $self->{'datastore'}->get_allele_attributes( $locus, [ $match->{'allele'} ] );
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
	  . ( $data->{'linked_data'}                                    ? '<th>Linked data values</th>' : q() )
	  . ( $data->{'extended_attributes'}                            ? '<th>Attributes</th>'         : q() )
	  . ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes'    ? q(<th>Flags</th>)             : q() )
	  . ( ( $self->{'system'}->{'allele_comments'} // '' ) eq 'yes' ? q(<th>Comments</th>)          : q() )
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
				my $scheme_buffer = $self->_get_scheme_table( $scheme->{'id'}, $designations );
				my $exact_match   = $scheme_buffer ? 1 : 0;
				$scheme_buffer .= $self->_get_classification_groups( $scheme->{'id'}, $designations, $exact_match );
				if ($scheme_buffer) {
					my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme->{'id'} );
					$buffer .= qq(<h2>$scheme_info->{'name'}</h2>);
					$buffer .= $scheme_buffer;
				}
			}
		}
	} else {
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		my $scheme_loci   = $self->{'datastore'}->get_scheme_loci($scheme_id);
		if ( @$scheme_fields && @$scheme_loci ) {
			my $scheme_buffer = $self->_get_scheme_table( $scheme_id, $designations );
			my $exact_match   = $scheme_buffer ? 1 : 0;
			$scheme_buffer .= $self->_get_classification_groups( $scheme_id, $designations, $exact_match );
			if ($scheme_buffer) {
				my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
				$buffer .= qq(<h2>$scheme_info->{'name'}</h2>);
				$buffer .= $scheme_buffer;
			}
		}
	}
	return $buffer;
}

sub _get_classification_groups {
	my ( $self, $scheme_id, $designations, $exact_match ) = @_;
	my $buffer = q();
	return $buffer if !$self->is_page_allowed('profileInfo');
	my $matched_loci = keys %$designations;
	return $buffer
	  if !$self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM classification_schemes WHERE scheme_id=?)', $scheme_id );
	my $must_match = $self->_how_many_loci_must_match($scheme_id);
	return $buffer if $matched_loci < $must_match;
	my $ret_val = $self->_get_closest_matching_profile( $scheme_id, $designations );
	return $buffer if !$ret_val;
	my $scheme_info   = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $first_profile = shift @{ $ret_val->{'profiles'} };

	if ( !$exact_match ) {
		$buffer .=
		  q(<span class="info_icon fas fa-2x fa-fw fa-fingerprint fa-pull-left" style="margin-top:-0.2em"></span>);
		$buffer .= q(<h3>Matching profiles</h3>);
		my $other_profiles_count = @{ $ret_val->{'profiles'} };
		my $plural               = $other_profiles_count == 1 ? q() : q(s);
		my $and_others =
		  $other_profiles_count
		  ? qq( and <a id="and_others" style="cursor:pointer">$other_profiles_count other$plural</a>)
		  : q();
		my $values = $self->_get_field_values( $scheme_id, $first_profile );
		my $loci_count =
		  $self->{'datastore'}->run_query( 'SELECT COUNT(*) FROM scheme_members WHERE scheme_id=?', $scheme_id );
		my $loci_matched    = $loci_count - $ret_val->{'mismatches'};
		my $percent_matched = BIGSdb::Utils::decimal_place( 100 * $loci_matched / $loci_count, 1 );
		my $list            = [
			{
				title => 'Closest profile',
				data  => qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=profileInfo&scheme_id=$scheme_id&amp;profile_id=$first_profile">)
				  . qq($scheme_info->{'primary_key'}-$first_profile</a>$and_others)
			},
		];
		push @$list, { title => 'Fields', data => $values } if $values;
		push @$list,
		  (
			{
				title => 'Mismatches',
				data  => $ret_val->{'mismatches'}
			},
			{ title => 'Loci matched', data => "$loci_matched/$loci_count ($percent_matched%)" }
		  );
		$buffer .= $self->get_list_block( $list, { width => 8 } );

		if ($other_profiles_count) {
			$plural = $ret_val->{'mismatches'} == 1 ? q() : q(es);
			$buffer .= q(<div id="other_matches" class="infopanel" style="display:none">);
			$buffer .= qq(<h3>Other profiles that have $ret_val->{'mismatches'} mismatch$plural</h3>);
			$buffer .= q(<ul>);
			foreach my $profile ( @{ $ret_val->{'profiles'} } ) {
				$values = $self->_get_field_values( $scheme_id, $profile );
				$values = qq( - $values) if $values;
				$buffer .=
					qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=profileInfo&scheme_id=$scheme_id&amp;profile_id=$profile">)
				  . qq($scheme_info->{'primary_key'}-$profile</a>$values</li>\n);
			}
			$buffer .= q(</ul></div>);
		}
	}
	my $cschemes =
	  $self->{'datastore'}
	  ->run_query( 'SELECT * FROM classification_schemes WHERE scheme_id=? ORDER BY display_order,name',
		$scheme_id, { fetch => 'all_arrayref', slice => {} } );
	return $buffer if !@$cschemes;
	my $client_dbs = $self->{'datastore'}->run_query(
		'SELECT * FROM client_dbase_cschemes cdc JOIN classification_schemes c ON cdc.cscheme_id=c.id JOIN '
		  . 'client_dbases cd ON cdc.client_dbase_id=cd.id WHERE c.scheme_id=? ORDER BY cd.name',
		$scheme_id,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $td = 1;
	my $cbuffer;
	my $fields_defined = $self->{'datastore'}->run_query(
		'SELECT EXISTS(SELECT * FROM classification_group_fields cgf JOIN '
		  . 'classification_schemes cs ON cgf.cg_scheme_id=cs.id WHERE cs.scheme_id=?)',
		$scheme_id
	);
	foreach my $cscheme (@$cschemes) {
		my $cgroup = $self->{'datastore'}->run_query(
			'SELECT group_id FROM classification_group_profiles WHERE (cg_scheme_id,profile_id)=(?,?)',
			[ $cscheme->{'id'}, $first_profile ],
			{ cache => 'SequenceQuery::_get_classification_groups::groups' }
		);
		next if !defined $cgroup;
		next if $cscheme->{'inclusion_threshold'} < $ret_val->{'mismatches'};
		my $desc = $cscheme->{'description'};
		my $tooltip =
			$desc
		  ? $self->get_tooltip(qq($cscheme->{'name'} - $desc))
		  : q();
		my $profile_count =
		  $self->{'datastore'}
		  ->run_query( 'SELECT COUNT(*) FROM classification_group_profiles WHERE (cg_scheme_id,group_id)=(?,?)',
			[ $cscheme->{'id'}, $cgroup ] );
		my $url = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;)
		  . qq(scheme_id=$scheme_id&amp;s1=$cscheme->{'name'}&amp;y1==&amp;t1=$cgroup&amp;submit=1);
		$cbuffer .=
			qq(<tr class="td$td"><td>$cscheme->{'name'}$tooltip</td><td>Single-linkage</td>)
		  . qq(<td>$cscheme->{'inclusion_threshold'}</td><td>$cscheme->{'status'}</td>)
		  . qq(<td>$cgroup</td>);

		if ($fields_defined) {
			$cbuffer .= q(<td>);
			$cbuffer .=
			  $self->{'datastore'}->get_classification_group_fields( $cscheme->{'id'}, $cgroup );
			$cbuffer .= q(</td>);
		}
		$cbuffer .= qq(<td><a href="$url">$profile_count</a></td>);
		if (@$client_dbs) {
			my @client_links = ();
			foreach my $client_db (@$client_dbs) {
				next if $client_db->{'cscheme_id'} != $cscheme->{'id'};
				my $client         = $self->{'datastore'}->get_client_db( $client_db->{'id'} );
				my $client_cscheme = $client_db->{'client_cscheme_id'} // $cscheme->{'id'};
				try {
					my $isolates =
					  $client->count_isolates_belonging_to_classification_group( $client_cscheme, $cgroup );
					my $client_db_url = $client_db->{'url'} // $self->{'system'}->{'script_name'};
					if ($isolates) {
						push @client_links,
							qq(<span class="source">$client_db->{'name'}</span> )
						  . qq(<a href="$client_db_url?db=$client_db->{'dbase_config_name'}&amp;page=query&amp;)
						  . qq(designation_field1=cg_${client_cscheme}_group&amp;designation_value1=$cgroup&amp;submit=1">)
						  . qq($isolates</a>);
					}
				} catch {
					if ( $_->isa('BIGSdb::Exception::Database::Configuration') ) {
						$self->{'logger'}->error( "Client database for classification scheme $cscheme->{'name'} "
							  . 'is not configured correctly.' );
					} else {
						$self->{'logger'}->logdie($_);
					}
				};
			}
			local $" = q(<br />);
			$cbuffer .= qq(<td style="text-align:left">@client_links</td>);
		}
		$cbuffer .= q(</tr>);
		$td = $td == 1 ? 2 : 1;
	}
	if ($cbuffer) {
		$buffer .=
			q(<div><span class="info_icon fas fa-2x fa-fw fa-sitemap fa-pull-left" )
		  . q(style="margin-top:-0.2em"></span>)
		  . q(<h3>Similar profiles (determined by classification schemes)</h3>)
		  . q(<p>Experimental schemes are subject to change and are not a stable part of the nomenclature.</p>)
		  . q(<div class="scrollable">)
		  . q(<div class="resultstable" style="float:left"><table class="resultstable"><tr>)
		  . q(<th>Classification scheme</th><th>Clustering method</th>)
		  . q(<th>Mismatch threshold</th><th>Status</th><th>Group</th>);
		$buffer .= q(<th>Fields</th>) if $fields_defined;
		$buffer .= q(<th>Profiles</th>);
		$buffer .= q(<th>Isolates</th>) if @$client_dbs;
		$buffer .= q(</tr>);
		$buffer .= $cbuffer;
		$buffer .= q(</table></div></div></div>);
	}
	return $buffer;
}

sub _get_field_values {
	my ( $self, $scheme_id, $profile_id ) = @_;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $pk          = $scheme_info->{'primary_key'};
	my $table       = "mv_scheme_$scheme_id";
	my $profile_info =
	  $self->{'datastore'}->run_query( "SELECT * FROM $table WHERE $pk=?", $profile_id, { fetch => 'row_hashref' } );
	my $fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my @values;
	foreach my $field (@$fields) {
		( my $cleaned_field = $field ) =~ tr/_/ /;
		push @values, "<b>$cleaned_field:</b> $profile_info->{$field}" if defined $profile_info->{$field};
	}
	local $" = q(; );
	return qq(@values);
}

sub _get_closest_matching_profile {
	my ( $self, $scheme_id, $designations ) = @_;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $pk_field    = $scheme_info->{'primary_key'};
	return if !$pk_field;
	my $pk_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $pk_field );
	my $order   = $pk_info->{'type'} eq 'integer' ? "CAST($pk_field AS int)" : $pk_field;
	my $loci    = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $profile_sth =
	  $self->{'db'}->prepare("SELECT $pk_field AS pk,profile FROM mv_scheme_$scheme_id ORDER BY $order");
	eval { $profile_sth->execute };

	if ($@) {
		$self->{'logger'}->error($@);
		return;
	}

	#TODO Extracting all cgMLST profiles from the database can take >5s for larger schemes.
	#This is all due to moving data over the network as it can be a few hundred MB. It would
	#be more efficient to write the following as an embedded plpgsql function within the
	#database and pass the matching profile in.
	my $least_mismatches = @$loci;
	my $best_matches     = [];
	my @locus_list       = sort @$loci;   #Profile array is always stored in alphabetical order, scheme order may not be
	my $rowcache;
  PROFILE:
	while ( my $profile = shift(@$rowcache)
		|| shift( @{ $rowcache = $profile_sth->fetchall_arrayref( undef, 10_000 ) || [] } ) )
	{
		my $mismatches = 0;
		my $index      = -1;
	  LOCUS: foreach my $locus (@locus_list) {
			$index++;
			next LOCUS if $profile->[1]->[$index] eq 'N';
			if ( !$designations->{$locus} ) {
				$mismatches++;
				next LOCUS;
			}
			my $alleles = $designations->{$locus};
			foreach my $allele (@$alleles) {
				next LOCUS if $profile->[1]->[$index] eq $allele;
			}
			$mismatches++;
			next PROFILE if $mismatches > $least_mismatches;    #Shortcut out
		}
		if ( $mismatches < $least_mismatches ) {
			$least_mismatches = $mismatches;
			$best_matches     = [ $profile->[0] ];
		} elsif ( $mismatches == $least_mismatches ) {
			push @$best_matches, $profile->[0];
		}
	}
	return if !@$best_matches;
	return { profiles => $best_matches, mismatches => $least_mismatches };
}

sub _how_many_loci_must_match {
	my ( $self, $scheme_id ) = @_;
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
	my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $must_match  = @$scheme_loci;
	if ( $scheme_info->{'allow_missing_loci'} ) {
		if ( $scheme_info->{'max_missing'} ) {
			$must_match -= $scheme_info->{'max_missing'};
		} else {
			$must_match = int( 0.5 * $must_match );    #Must match at least half the loci
		}
	}
	return $must_match;
}

sub _get_scheme_table {
	my ( $self, $scheme_id, $designations_no_clobber ) = @_;
	my ( @profile, @temp_qry );
	my $set_id      = $self->{'options'}->{'set_id'};
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	return q() if !defined $scheme_info->{'primary_key'};
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $scheme_loci   = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $missing_loci;

	#Do a deep copy so that we don't clobber hashref.
	my $designations = dclone $designations_no_clobber;
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
		$buffer .=
		  q(<span class="info_icon fas fa-2x fa-fw fa-fingerprint fa-pull-left" style="margin-top:-0.2em"></span>);
		my $plural = @$all_values == 1 ? q() : q(s);
		$buffer .= qq(<h3>Matching profile$plural</h3>);
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
		$diff->{'spos'}  = $spos + 1;
		$diff->{'sbase'} = substr( $$seq1_ref, $spos, 1 );
		if ( $qpos < length $$seq2_ref && substr( $$seq1_ref, $spos, 1 ) ne substr( $$seq2_ref, $qpos, 1 ) ) {
			$diff->{'qpos'}  = $qpos + 1;
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
	my $allele_link   = $self->_get_allele_link( $partial_match->{'locus'}, $partial_match->{'allele'} );
	my $buffer        = qq(<p style="margin-top:0.5em">Closest match: $cleaned_locus: $allele_link);
	my $flags         = $self->{'datastore'}->get_allele_flags( $partial_match->{'locus'}, $partial_match->{'allele'} );
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
		  . q(<pre style="padding:1em; border:1px black dashed">);
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
	open( my $seq1_fh, '>:encoding(utf8)', $seq2_infile )
	  || $self->{'logger'}->error("Cannot open $seq2_infile for writing");
	say $seq1_fh ">Ref\n$$allele_seq_ref";
	close $seq1_fh;
	open( my $seq2_fh, '>:encoding(utf8)', $seq1_infile )
	  || $self->{'logger'}->error("Cannot open $seq1_infile for writing");
	say $seq2_fh ">Query\n$$contig_ref";
	close $seq2_fh;
	my $reverse = $match->{'reverse'} ? 1 : 0;
	my @args    = (
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
		$buffer .= q(<pre class="alignment">);
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
		$buffer .= qq(<pre class="alignment"><span id="alignment"></span></pre></div>\n);
	}
	return $buffer;
}

sub get_allele_linked_data {
	my ($self) = @_;
	return $self->{'linked_data'};
}

sub _cleanup_alignment {
	my ( $self, $infile, $outfile ) = @_;
	open( my $in_fh,  '<:encoding(utf8)', $infile ) || $self->{'logger'}->error("Cannot open $infile for reading");
	open( my $out_fh, '>:encoding(utf8)', $outfile )
	  || $self->{'logger'}->error("Cannot open $outfile for writing");
	while (<$in_fh>) {
		next if $_ =~ /^\#/x;
		print $out_fh $_;
	}
	close $in_fh;
	close $out_fh;
	return;
}
1;
