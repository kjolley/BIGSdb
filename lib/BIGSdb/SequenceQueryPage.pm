#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
package BIGSdb::SequenceQueryPage;
use strict;
use warnings;
use base qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
use List::MoreUtils qw(uniq any);
use Error qw(:try);
use IO::String;
use Bio::SeqIO;
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return $self->{'cgi'}->param('page') eq 'sequenceQuery' ? "Sequence query - $desc" : "Batch sequence query - $desc";
}

sub get_javascript {
	my $buffer = << "END";
\$(function () {
	\$('a[rel=ajax]').click(function(){
  		\$(this).attr('href', function(){
  			if (this.href.match(/javascript.loadContent/)){
  				return;
  			};
    		return(this.href.replace(/(.*)/, "javascript:loadContent\('\$1\'\)"));
    	});
  	});
});

function loadContent(url) {
	\$("#alignment").html('<img src=\"/javascript/themes/default/throbber.gif\" /> Loading ...').load(url);
	\$("#alignment_link").hide();
}

END
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $page   = $q->param('page');
	my $locus  = $q->param('locus');
	$locus =~ s/%27/'/g if $locus;    #Web-escaped locus
	$q->param( 'locus', $locus );
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		print "<div class=\"box\" id=\"statusbad\"><p>This function is not available in isolate databases.</p></div>\n";
		return;
	}
	print $page eq 'sequenceQuery' ? "<h1>Sequence query</h1>\n" : "<h1>Batch sequence query</h1>\n";
	print "<div class=\"box\" id=\"queryform\">\n";
	print "<p>Please paste in your sequence"
	  . ( $page eq 'batchSequenceQuery' ? 's' : '' )
	  . " to query against the database.  Query sequences will be checked first for an exact match against the chosen (or all) loci - they do
	not need to be trimmed. The nearest partial matches will be identified if an exact match is not found. You can query using either DNA or peptide 
	sequences.";
	print " <a class=\"tooltip\" title=\"Query sequence - Your query sequence is assumed
to be DNA if it contains 90% or more G,A,T,C or N characters.\">&nbsp;<i>i</i>&nbsp;</a>";
	print "</p>\n";
	print $q->start_form;
	print "<table><tr><td style=\"text-align:right\">Please select locus/scheme: </td><td>";
	my ( $display_loci, $cleaned ) = $self->{'datastore'}->get_locus_list;
	my $scheme_list =
	  $self->{'datastore'}->run_list_query_hashref("SELECT id,description FROM schemes ORDER BY display_order desc,description desc");

	foreach (@$scheme_list) {
		unshift @$display_loci, "SCHEME_$_->{'id'}";
		$cleaned->{"SCHEME_$_->{'id'}"} = $_->{'description'};
	}
	unshift @$display_loci, 0;
	$cleaned->{0} = 'All loci';
	print $q->popup_menu( -name => 'locus', -values => $display_loci, -labels => $cleaned );
	print "</td><td>";
	print "Order results by: ";
	print $q->popup_menu( -name => 'order', -values => [ ( 'locus', 'best match' ) ] );
	print "</td></tr>\n<tr><td style=\"text-align:right\">";

	if ( $page eq 'sequenceQuery' ) {
		print "Enter query sequence: ";
	} else {
		print "Enter query sequences<br />(FASTA format): ";
	}
	print "</td><td style=\"width:80%\" colspan=\"2\">";
	my $sequence;
	if ( $q->param('sequence') ) {
		$sequence = $q->param('sequence');
		$q->param( 'sequence', '' );
	}
	print $q->textarea( -name => 'sequence', -rows => '6', -cols => '70' );
	print "</td></tr>\n<tr><td colspan=\"2\">";
	print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page\" class=\"resetbutton\">Reset</a></td><td style=\"text-align:right\">";
	print $q->submit( -name => 'Submit', -class => 'submit' );
	print "</td></tr>\n";
	print "</table>\n";
	print $q->hidden($_) foreach qw (db page);
	print $q->end_form;
	print "</div>\n";
	if ( $q->param('Submit') && $sequence ) {
		$self->_run_query($sequence);
	}
}

sub _run_query {
	my ( $self, $sequence ) = @_;
	my $q    = $self->{'cgi'};
	my $page = $q->param('page');
	if ( $sequence !~ /^>/ ) {

		#add identifier line if one missing since newer versions of BioPerl check
		$sequence = ">\n$sequence";
	}
	my $stringfh_in = new IO::String($sequence);
	my $seqin = Bio::SeqIO->new( -fh => $stringfh_in, -format => 'fasta' );
	my $batchBuffer;
	my $td = 1;
	$| = 1;
	my $first = 1;
	my $job   = 0;

	while ( my $seq_object = $seqin->next_seq ) {
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			if ( $self->{'mod_perl_request'}->connection->aborted ) {
				return;
			}
		}
		my $seq = $seq_object->seq;
		$seq =~ s/\s//g;
		$seq = uc($seq);
		my $seq_type = BIGSdb::Utils::is_valid_DNA($seq) ? 'DNA' : 'peptide';
		my $locus = $q->param('locus');
		if ( $locus =~ /^cn_(.+)$/ ) {
			$locus = $1;
		}

		#Check for exact match first if locus selected
		my $qry;
		my $count;
		if ( $locus && $locus !~ /^SCHEME_\d+/ ) {
			$count =
			  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM sequences WHERE locus=? and sequence=?", $locus, $seq )->[0];
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			$qry = "SELECT locus,allele_id FROM sequences WHERE locus=? AND sequence=? ORDER BY locus,"
			  . ( $locus_info->{'allele_id_format'} eq 'integer' ? 'CAST(allele_id AS int)' : 'allele_id' );
		}
		if ($count) {
			my $sql = $self->{'db'}->prepare($qry);
			eval { 
				if ( $locus && $locus !~ /^SCHEME_\d+/ ){
					$sql->execute( $locus, $seq );
				} else {
					$sql->execute($seq);
				}
			};
			$logger->error($@) if $@;
			my @alleles;
			my @allele_ids;
			while ( my ( $locus, $allele_id ) = $sql->fetchrow_array ) {
				my $cleaned = $self->clean_locus($locus);
				push @allele_ids, $allele_id;
				push @alleles,
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleInfo&amp;locus=$locus&amp;allele_id=$allele_id\">$cleaned: $allele_id</a>";
			}
			$" = ', ';
			my $field_values = $self->_get_client_dbase_fields( $locus, \@allele_ids );
			if ( $page eq 'sequenceQuery' ) {
				print "<div class=\"box\" id=\"resultsheader\">";
				print "<p>Exact match" . ( $count == 1 ? '' : 'es' ) . " found: \n";
				print "@alleles";
				print " ($field_values)" if $field_values;
				print "</p>\n</div>\n";
			} else {
				$batchBuffer =
				    "<tr class=\"td$td\"><td>"
				  . ( $seq_object->id )
				  . "</td><td style=\"text-align:left\">Exact match"
				  . ( $count == 1 ? '' : 'es' )
				  . " found: @alleles";
				$batchBuffer .= " ($field_values)" if $field_values;
				$batchBuffer .= "</td></tr>\n";
			}
		} else {
			my $qry_type = BIGSdb::Utils::sequence_type($seq);
			( my $cleaned_locus = $locus ) =~ tr/_/ /;
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			( my $blast_file, $job ) = $self->run_blast(
				{ 'locus' => $locus, 'seq_ref' => \$seq, 'qry_type' => $qry_type, 'num_results' => 50000, 'cache' => 1, 'job' => $job } );
			my $exact_matches = $self->_parse_blast_exact( $locus, $blast_file );
			if ( ref $exact_matches eq 'ARRAY' && @$exact_matches ) {
				if ( $page eq 'sequenceQuery' ) {
					print "<div class=\"box\" id=\"resultsheader\"><p>\n";
					print scalar @$exact_matches
					  . " exact match"
					  . ( scalar @$exact_matches > 1 ? 'es' : '' )
					  . " found using BLAST.</p></div>";
					print "<div class=\"box\" id=\"resultstable\">\n";
					if ( defined $locus_info->{'data_type'} && $locus_info->{'data_type'} eq 'peptide' && $seq_type eq 'DNA' ) {
						print
"<p>Please note that as this is a peptide locus, the length corresponds to the peptide translated from your query sequence.</p>\n";
					} elsif ( defined $locus_info->{'data_type'} && $locus_info->{'data_type'} eq 'DNA' && $seq_type eq 'peptide' ) {
						print "<p>Please note that as this is a DNA locus, the length corresponds to the matching nucleotide sequence that 
							was translated to align against your peptide query sequence.</p>\n";
					}
					print
"<table class=\"resultstable\"><tr><th>Allele</th><th>Length</th><th>Start position</th><th>End position</th><th>Attributes</th></tr>\n";
					if ( ( !$locus || $locus =~ /SCHEME_(\d+)/ ) && $q->param('order') eq 'locus' ) {
						my %locus_values;
						foreach (@$exact_matches) {
							if ( $_->{'allele'} =~ /(.*):.*/ ) {
								$locus_values{$_} = $1;
							}
						}
						@$exact_matches = sort { $locus_values{$a} cmp $locus_values{$b} } @$exact_matches;
					}
					foreach (@$exact_matches) {
						print "<tr class=\"td$td\"><td>";
						my $allele;
						my $field_values;
						if ( $locus && $locus !~ /SCHEME_(\d+)/ ) {
							my $cleaned = $self->clean_locus($locus);
							print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleInfo&amp;locus=$locus&amp;allele_id=$_->{'allele'}\">";
							$allele = "$cleaned: $_->{'allele'}";
							$field_values = $self->_get_client_dbase_fields( $locus, [ $_->{'allele'} ] );
						} else {
							my ( $cleaned_locus, $locus, $allele_id );
							if ( $_->{'allele'} =~ /(.*):(.*)/ ) {
								$locus = $1;
								my $cleaned = $self->clean_locus($locus);
								$allele_id    = $2;
								$allele       = "$cleaned: $allele_id";
								$field_values = $self->_get_client_dbase_fields( $locus, [$allele_id] );
							}
							print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleInfo&amp;locus=$locus&amp;allele_id=$allele_id\">"
							  if $locus && $allele_id;
						}
						print "$allele</a></td><td>$_->{'length'}</td><td>$_->{'start'}</td><td>$_->{'end'}</td>";
						print defined $field_values ? "<td>$field_values</td>" : '<td />';
						print "</tr>\n";
						$td = $td == 1 ? 2 : 1;
					}
					print "</table>\n";
					print "</div>\n";
				} else {
					my $buffer = "Exact match" . ( scalar @$exact_matches == 1 ? '' : 'es' ) . " found: ";
					my $first = 1;
					if ( ( !$locus || $locus =~ /SCHEME_\d+/ ) && $q->param('order') eq 'locus' ) {
						my %locus_values;
						foreach (@$exact_matches) {
							if ( $_->{'allele'} =~ /(.*):.*/ ) {
								$locus_values{$_} = $1;
							}
						}
						@$exact_matches = sort { $locus_values{$a} cmp $locus_values{$b} } @$exact_matches;
					}
					foreach (@$exact_matches) {
						$buffer .= '; ' if !$first;
						my $allele_id;
						if ( ( !$locus || $locus =~ /SCHEME_\d+/ ) && $_->{'allele'} =~ /(.*):(.*)/ ) {
							$locus     = $1;
							$allele_id = $2;
						} else {
							$allele_id = $_->{'allele'};
						}
						my $field_values = $self->_get_client_dbase_fields( $locus, [$allele_id] );
						my $cleaned_locus = $self->clean_locus($locus);
						$buffer .=
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleInfo&amp;locus=$locus&amp;allele_id=$allele_id\">$cleaned_locus: $allele_id</a>";
						$buffer .= " ($field_values)" if $field_values;
						undef $locus if !$q->param('locus') || $q->param('locus') =~ /SCHEME_\d+/;
						$first = 0;
					}
					$batchBuffer =
					  "<tr class=\"td$td\"><td>" . ( $seq_object->id ) . "</td><td style=\"text-align:left\">$buffer</td></tr>\n";
				}
			} else {
				if ( defined $locus_info->{'data_type'} && $qry_type ne $locus_info->{'data_type'} && $locus && $locus !~ /SCHEME_(\d+)/ ) {
					system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$blast_file";
					if ( $page eq 'sequenceQuery' ) {
						( $blast_file, $job ) = $self->run_blast(
							{
								'locus'       => $locus,
								'seq_ref'     => \$seq,
								'qry_type'    => $qry_type,
								'num_results' => 5,
								'alignment'   => 1,
								'cache'       => 1,
								'job'         => $job
							}
						);
						print "<div class=\"box\" id=\"resultsheader\">\n";
						if (-e "$self->{'config'}->{'secure_tmp_dir'}/$blast_file"){
							print "<p>Your query is a $qry_type sequence whereas this locus is defined with 
							$locus_info->{'data_type'} sequences.  There were no exact matches, but the BLAST results are shown below (a maximum of five
							alignments are displayed).</p>";
							
							print "<pre style=\"font-size:1.2em\">\n";
							$self->print_file( "$self->{'config'}->{'secure_tmp_dir'}/$blast_file", 1 );
							print "</pre>\n";							
						} else {
							print "<p>No results from BLAST.</p>\n";
						}
						print "</div>\n";
						system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$blast_file";
						return;
					}
				}
				my $partial_match = $self->_parse_blast_partial($blast_file);
				if ( ref $partial_match ne 'HASH' || !defined $partial_match->{'allele'} ) {
					if ( $page eq 'sequenceQuery' ) {
						print "<div class=\"box\" id=\"statusbad\"><p>No matches found.</p></div>\n";
					} else {
						$batchBuffer =
						    "<tr class=\"td$td\"><td>"
						  . ( $seq_object->id )
						  . "</td><td style=\"text-align:left\">No matches found.</td></tr>\n";
					}
				} else {
					if ( $page eq 'sequenceQuery' ) {
						print "<div class=\"box\" id=\"resultsheader\"><p>Closest match: ";
						my $cleaned_match = $partial_match->{'allele'};
						my $field_values;
						if ( $locus && $locus !~ /SCHEME_(\d+)/ ) {
							print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleInfo&amp;locus=$locus&amp;allele_id=$cleaned_match\">";
							$cleaned_locus = $self->clean_locus($locus);
							print "$cleaned_locus: ";
							$field_values = $self->_get_client_dbase_fields( $locus, [$cleaned_match] );
						} else {
							my ( $locus, $allele_id );
							if ( $cleaned_match =~ /(.*):(.*)/ ) {
								$locus     = $1;
								$allele_id = $2;
								print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleInfo&amp;locus=$locus&amp;allele_id=$allele_id\">";
								$field_values = $self->_get_client_dbase_fields( $locus, [$allele_id] );
							}
							$cleaned_match =~ s/:/: /;
						}
						$cleaned_match = $self->clean_locus($cleaned_match);
						print "$cleaned_match</a>";
						print " ($field_values)" if $field_values;
						print "</p>";
						my $data_type;
						my $seq_ref;
						if ( $locus && $locus !~ /SCHEME_(\d+)/ ) {
							$seq_ref = $self->{'datastore'}->get_sequence( $locus, $partial_match->{'allele'} );
							$data_type = $locus_info->{'data_type'};
						} else {
							my ( $locus, $allele ) = split /:/, $partial_match->{'allele'};
							$seq_ref = $self->{'datastore'}->get_sequence( $locus, $allele );
							$data_type = $self->{'datastore'}->get_locus_info($locus)->{'data_type'};
						}
						if ( $data_type eq $qry_type ) {
							my $temp        = BIGSdb::Utils::get_random();
							my $seq1_infile = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_file1.txt";
							my $seq2_infile = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_file2.txt";
							my $outfile     = "$self->{'config'}->{'tmp_dir'}/$temp\_outfile.txt";
							open( my $seq1_fh, '>', $seq2_infile );
							print $seq1_fh ">Ref\n$$seq_ref\n";
							close $seq1_fh;
							open( my $seq2_fh, '>', $seq1_infile );
							print $seq2_fh ">Query\n$seq\n";
							close $seq2_fh;
							system(
"$self->{'config'}->{'emboss_path'}/stretcher -aformat markx2 -awidth $self->{'prefs'}->{'alignwidth'} $seq1_infile $seq2_infile $outfile 2> /dev/null"
							);
							unlink $seq1_infile, $seq2_infile;
							my $internal_gaps;

							if ( -e $outfile ) {
								my ( $gaps, $opening_gaps, $end_gaps );
								open my $fh, '<', $outfile;
								my $first_line = 1;
								while (<$fh>) {
									if ( $_ =~ /^# Gaps:\s+(\d+)+\// ) {
										$gaps = $1;
									}
									if ( $_ =~ /^\s+Ref [^-]+$/ ) {

										#Reset end gap count if line contains anything other than gaps
										$end_gaps = 0;
									}
									if ( $first_line && $_ =~ /^\s+Ref/ ) {
										if ( $_ =~ /^\s+Ref (-*)/ ) {
											$opening_gaps += length $1;
										}
									}
									if ( $_ =~ /^\s+Ref.+?(-*)\s*$/ ) {
										$end_gaps += length $1;
									}
									if ( $_ =~ /^\s+Ref [^-]+$/ ) {
										$first_line = 0;
									}
								}
								close $fh;
								$logger->debug("Opening gaps: $opening_gaps; End gaps: $end_gaps");
								$internal_gaps = $gaps - $opening_gaps - $end_gaps;
							}

							#Display nucleotide differences if both BLAST and stretcher report no gaps.
							if ( !$internal_gaps && !$partial_match->{'gaps'} ) {
								my $qstart = $partial_match->{'qstart'};
								my $sstart = $partial_match->{'sstart'};
								my $ssend  = $partial_match->{'send'};
								while ( $sstart > 1 && $qstart > 1 ) {
									$sstart--;
									$qstart--;
								}
								if ( $sstart > $ssend ) {
									print "<p>The sequence is reverse-complemented with respect to the reference sequence.  
								This will confuse the list of differences so try reversing it and query again.</p>\n";
								} else {
									if ( -e $outfile ) {
										my $cleaned_file = "$self->{'config'}->{'tmp_dir'}/$temp\_cleaned.txt";
										$self->_cleanup_alignment( $outfile, $cleaned_file );
										print
"<p><a href=\"/tmp/$temp\_cleaned.txt\" id=\"alignment_link\" rel=\"ajax\">Show alignment</a></p>\n";
										print "<pre><span id=\"alignment\"></span></pre>\n";
									}
									my $diffs = $self->_get_differences( $seq_ref, \$seq, $sstart, $qstart );
									print "<h2>Differences</h2>\n";
									if (@$diffs) {
										my $plural = scalar @$diffs > 1 ? 's' : '';
										print "<p>" . scalar @$diffs . " difference$plural found. ";
										my $data_type;
										if (defined $locus_info->{'data_type'}){
											$data_type = $locus_info->{'data_type'} eq 'DNA' ? 'nucleotide' : 'residue';
										} else {
											$data_type = 'identity';
										}
										print
"<a class=\"tooltip\" title=\"differences - The information to the left of the arrow$plural shows the $data_type and position on the reference sequence
		and the information to the right shows the corresponding $data_type and position on your query sequence.\">&nbsp;<i>i</i>&nbsp;</a>";
										print "</p><p>\n";
										foreach (@$diffs) {
											if ( !$_->{'qbase'} ) {
												print "Truncated at position $_->{'spos'} on reference sequence.";
												last;
											}
											if ( $qry_type eq 'DNA' ) {
												print
"<sup>$_->{'spos'}</sup><span class=\"$_->{'sbase'}\">$_->{'sbase'}</span> &rarr; <sup>$_->{'qpos'}</sup><span class=\"$_->{'qbase'}\">$_->{'qbase'}</span><br />\n";
											} else {
												print
"<sup>$_->{'spos'}</sup>$_->{'sbase'} &rarr; <sup>$_->{'qpos'}</sup>$_->{'qbase'}<br />\n";
											}
										}
										print "</p>\n";
										$plural = scalar @$diffs > 1 ? 's' : '';
										if ( $sstart > 1 ) {
											print "<p>Your query sequence only starts at position $sstart of sequence ";
											print "$locus: " if $locus && $locus !~ /SCHEME_\d+/;
											print "$cleaned_match.</p>\n";
										} else {
											print "<p>The locus start point is at position "
											  . ( $qstart - $sstart + 1 )
											  . " of your query sequence.";
											print
" <a class=\"tooltip\" title=\"start position - This may be approximate if there are gaps near the beginning of the alignment between your query and the 
		reference sequence.\">&nbsp;<i>i</i>&nbsp;</a>";
											print "</p>\n";
										}
									} else {
										print "<p>Your query sequence only starts at position $sstart of sequence ";
										print "$locus: " if $locus && $locus !~ /SCHEME_\d+/;
										print "$partial_match->{'allele'}.</p>\n";
									}
								}
							} else {
								print
"<p>An alignment between your query and the returned reference sequence is shown rather than a simple list of 
								differences because there are gaps in the alignment.</p>\n";
								print "<pre style=\"font-size:1.2em\">\n";
								$self->print_file( $outfile, 1 );
								print "</pre>\n";
								system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$temp*";
							}
						} else {
							( $blast_file, $job ) = $self->run_blast(
								{
									'locus'       => $locus,
									'seq_ref'     => \$seq,
									'qry_type'    => $qry_type,
									'num_results' => 5,
									'alignment'   => 1,
									'cache'       => 1,
									'job'         => $job
								}
							);
							if (-e "$self->{'config'}->{'secure_tmp_dir'}/$blast_file"){
								print "<p>Your query is a $qry_type sequence whereas this locus is defined with "
								  . ( $qry_type eq 'DNA' ? 'peptide' : 'DNA' )
								  . " sequences.  There were no exact matches, but the BLAST results are shown below (a maximum of five
								alignments are displayed).</p>";
								print "<pre style=\"font-size:1.2em\">\n";
								$self->print_file( "$self->{'config'}->{'secure_tmp_dir'}/$blast_file", 1 );
								print "</pre>\n";
							} else {
								print "<p>No results from BLAST.</p>\n";
							}
							print "</div>\n";
							system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$blast_file";
							return;
						}
						print "</div>\n";
					} else {
						my $cleaned_match = $partial_match->{'allele'};
						my $buffer;
						my $seq_ref;
						if ( $locus && $locus !~ /SCHEME_(\d+)/ ) {
							$seq_ref = $self->{'datastore'}->get_sequence( $locus, $partial_match->{'allele'} );
						} else {
							my ( $locus, $allele ) = split /:/, $partial_match->{'allele'};
							$seq_ref = $self->{'datastore'}->get_sequence( $locus, $allele );
						}
						if ( !$partial_match->{'gaps'} ) {
							my $qstart = $partial_match->{'qstart'};
							my $sstart = $partial_match->{'sstart'};
							my $ssend  = $partial_match->{'send'};
							while ( $sstart > 1 && $qstart > 1 ) {
								$sstart--;
								$qstart--;
							}
							if ( $sstart > $ssend ) {
								$buffer .= "Reverse complemented - try reversing it and query again.";
							} else {
								my $diffs = $self->_get_differences( $seq_ref, \$seq, $sstart, $qstart );
								if (@$diffs) {
									my $plural = scalar @$diffs > 1 ? 's' : '';
									$buffer .= ( scalar @$diffs ) . " difference$plural found. ";
									my $first = 1;
									foreach (@$diffs) {
										$buffer .= '; ' if !$first;
										if ( $qry_type eq 'DNA' ) {
											$buffer .=
"<sup>$_->{'spos'}</sup><span class=\"$_->{'sbase'}\">$_->{'sbase'}</span> &rarr; <sup>$_->{'qpos'}</sup><span class=\"$_->{'qbase'}\">$_->{'qbase'}</span>\n";
										} else {
											$buffer .= "<sup>$_->{'spos'}</sup>$_->{'sbase'} &rarr; <sup>$_->{'qpos'}</sup>$_->{'qbase'}\n";
										}
										$first = 0;
									}
									$plural = scalar @$diffs > 1 ? 's' : '';
								} else {
									$buffer .= "Your query sequence only starts at position $sstart of sequence ";
									$buffer .= "$locus: " if $locus && $locus !~ /SCHEME_\d+/;
									$buffer .= "$partial_match->{'allele'}.";
								}
							}
						} else {
							$buffer .=
							  "There are insertions/deletions between these sequences.  Try single sequence query to get more details.";
						}
						my $allele;
						my $field_values;
						if ( $locus && $locus !~ /SCHEME_(\d+)/ ) {
							$allele =
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleInfo&amp;locus=$locus&amp;allele_id=$partial_match->{'allele'}\">$cleaned_locus: $partial_match->{'allele'}</a>";
							$field_values = $self->_get_client_dbase_fields( $locus, [ $partial_match->{'allele'} ] );
						} else {
							my ( $locus, $allele_id );
							if ( $partial_match->{'allele'} =~ /(.*):(.*)/ ) {
								$locus = $1;
								my $cleaned_locus = $self->clean_locus($locus);
								$allele_id = $2;
								$partial_match->{'allele'} =~ s/:/: /;
								$allele =
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleInfo&amp;locus=$locus&amp;allele_id=$allele_id\">$cleaned_locus: $allele_id</a>";
								$field_values = $self->_get_client_dbase_fields( $locus, [$allele_id] );
							}
						}
						$batchBuffer =
						    "<tr class=\"td$td\"><td>"
						  . ( $seq_object->id )
						  . "</td><td style=\"text-align:left\">Partial match found: $allele";
						$batchBuffer .= " ($field_values)" if $field_values;
						$batchBuffer .= ": $buffer</td></tr>\n";
					}
				}
			}
			system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$blast_file";
		}
		last if ( $page eq 'sequenceQuery' );    #only go round again if this is a batch query
		$td = $td == 1 ? 2 : 1;
		if ( $page eq 'batchSequenceQuery' ) {
			if ($first) {
				print "<div class=\"box\" id=\"resultsheader\">\n";
				print "<table class=\"resultstable\"><tr><th>Sequence</th><th>Results</th></tr>\n";
				$first = 0;
			}
			if ($batchBuffer) {
				print $batchBuffer;
			}
		}
	}
	system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$job*";
	if ( $page eq 'batchSequenceQuery' ) {
		if ($batchBuffer) {
			print "</table>\n";
			print "</div>\n";
		} else {
			print "<div class=\"box\" id=\"statusbad\"><p>No matches found</p></div>\n";
		}
	}
}

sub _parse_blast_exact {
	my ( $self, $locus, $blast_file ) = @_;
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$blast_file";
	return if !-e $full_path;
	open( my $blast_fh, '<', $full_path ) || ( $logger->error("Can't open BLAST output file $full_path. $!"), return \@; );
	my @matches;
	while ( my $line = <$blast_fh> ) {
		my $match;
		next if !$line || $line =~ /^#/;
		my @record = split /\s+/, $line;
		if ( $record[2] == 100 ) {    #identity
			my $seq_ref;
			if ( $locus && $locus !~ /SCHEME_(\d+)/ ) {
				$seq_ref = $self->{'datastore'}->get_sequence( $locus, $record[1] );
			} else {
				my ( $locus, $allele ) = split /:/, $record[1];
				$seq_ref = $self->{'datastore'}->get_sequence( $locus, $allele );
			}
			my $length = length $$seq_ref;
			if (
				(
					(
						$record[8] == 1             #sequence start position
						&& $record[9] == $length    #end position
					)
					|| (
						$record[8] == $length       #sequence start position (reverse complement)
						&& $record[9] == 1          #end position
					)
				)
				&& !$record[4]                      #no gaps
			  )
			{
				$match->{'allele'}  = $record[1];
				$match->{'length'}  = $length;
				$match->{'start'}   = $record[6];
				$match->{'end'}     = $record[7];
				$match->{'reverse'} = 1 if ( $record[8] > $record[9] || $record[7] < $record[6] );
				push @matches, $match;
			}
		}
	}
	close $blast_fh;
	return \@matches;
}

sub _parse_blast_partial {

	#return best match
	my ( $self, $blast_file ) = @_;
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$blast_file";
	return if !-e $full_path;
	open( my $blast_fh, '<', $full_path ) || ( $logger->error("Can't open BLAST output file $full_path. $!"), return \$; );
	my %best_match;
	$best_match{'bit_score'} = 0;
	my %match;
	while ( my $line = <$blast_fh> ) {
		next if !$line || $line =~ /^#/;
		my @record = split /\s+/, $line;
		$match{'allele'}    = $record[1];
		$match{'identity'}  = $record[2];
		$match{'alignment'} = $record[3];
		$match{'gaps'}      = $record[5];
		$match{'qstart'}    = $record[6];
		$match{'send'}      = $record[7];
		$match{'sstart'}    = $record[8];
		$match{'send'}      = $record[9];
		$match{'bit_score'} = $record[11];

		if ( $match{'bit_score'} > $best_match{'bit_score'} ) {
			%best_match = %match;
		}
	}
	close $blast_fh;
	return \%best_match;
}

sub _get_differences {

	#returns differences between two sequences where there are no gaps
	my ( $self, $seq1_ref, $seq2_ref, $sstart, $qstart ) = @_;
	my $qpos = $qstart - 1;
	my @diffs;
	for ( my $spos = $sstart - 1 ; $spos < length $$seq1_ref ; $spos++ ) {
		if ( substr( $$seq1_ref, $spos, 1 ) ne substr( $$seq2_ref, $qpos, 1 ) ) {
			my $diff;
			$diff->{'spos'}  = $spos + 1;
			$diff->{'qpos'}  = $qpos + 1;
			$diff->{'sbase'} = substr( $$seq1_ref, $spos, 1 );
			$diff->{'qbase'} = substr( $$seq2_ref, $qpos, 1 );
			push @diffs, $diff;
		}
		$qpos++;
	}
	return \@diffs;
}

sub _cleanup_alignment {
	my ( $self, $infile, $outfile ) = @_;
	open( my $in_fh,  '<', $infile );
	open( my $out_fh, '>', $outfile );
	while (<$in_fh>) {
		next if $_ =~ /^#/;
		print $out_fh $_;
	}
	close $in_fh;
	close $out_fh;
}

sub _get_client_dbase_fields {
	my ( $self, $locus, $allele_ids_refs ) = @_;
	return [] if ref $allele_ids_refs ne 'ARRAY';
	my $sql = $self->{'db'}->prepare("SELECT client_dbase_id,isolate_field FROM client_dbase_loci_fields WHERE allele_query AND locus = ?");
	eval { $sql->execute($locus); };
	if ($@) {
		$logger->error($@);
	}
	my $values;
	while ( my ( $client_dbase_id, $field ) = $sql->fetchrow_array ) {
		my $client_db  = $self->{'datastore'}->get_client_db($client_dbase_id)->get_db;
		my $client_sql = $client_db->prepare(
"SELECT $field FROM isolates LEFT JOIN allele_designations ON isolates.id = allele_designations.isolate_id WHERE allele_designations.locus=? AND allele_designations.allele_id=?"
		);
		foreach (@$allele_ids_refs) {
			eval { $client_sql->execute( $locus, $_ ); };
			if ($@){
				$logger->error("Can't extract isolate field '$field' FROM client database, make sure the client_dbase_loci_fields table is correctly configured.  $@");
			} else {
				while ( my ($value) = $client_sql->fetchrow_array ) {
					next if $value eq '';
					if ( any { $field eq $_ } qw (species genus) ) {
						$value = "<i>$value</i>";
					}
					push @{ $values->{$field} }, $value;
				}
			}
		}
		if ( ref $values->{$field} eq 'ARRAY' && @{ $values->{$field} } ) {
			my @list = @{ $values->{$field} };
			@list = uniq sort @list;
			@{ $values->{$field} } = @list;
		}
	}
	my $buffer;
	if ( keys %$values ) {
		my $first = 1;
		foreach ( sort keys %$values ) {
			$buffer .= '; ' if !$first;
			$" = ', ';
			$buffer .= "$_: @{$values->{$_}}";
			$first = 0;
		}
	}
	return $buffer;
}
1;
