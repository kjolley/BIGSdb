#Written by Keith Jolley
#Copyright (c) 2010-2012, University of Oxford
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
use 5.010;
use parent qw(BIGSdb::BlastPage);
use Log::Log4perl qw(get_logger);
use List::MoreUtils qw(uniq any none);
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
	return $buffer;
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
	  . " to query against the database.  Query sequences will be checked first for an exact match against the chosen "
	  . "(or all) loci - they do not need to be trimmed. The nearest partial matches will be identified if an exact "
	  . "match is not found. You can query using either DNA or peptide sequences.";
	print " <a class=\"tooltip\" title=\"Query sequence - Your query sequence is assumed to be DNA if it contains "
	  . "90% or more G,A,T,C or N characters.\">&nbsp;<i>i</i>&nbsp;</a></p>\n";
	print $q->start_form;
	print "<div class=\"scrollable\"><fieldset><legend>Please select locus/scheme</legend>\n";
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
	print "</fieldset>\n<fieldset><legend>Order results by</legend>\n";
	print $q->popup_menu( -name => 'order', -values => [ ( 'locus', 'best match' ) ] );
	print "</fieldset>\n";
	print "<div style=\"clear:both\">\n";
	print "<fieldset><legend>"
	  . (
		$page eq 'sequenceQuery'
		? 'Enter query sequence (single or multiple contigs up to whole genome in size)'
		: 'Enter query sequences (FASTA format)'
	  ) . "</legend>";
	my $sequence;

	if ( $q->param('sequence') ) {
		$sequence = $q->param('sequence');
		$q->param( 'sequence', '' );
	}
	print $q->textarea( -name => 'sequence', -rows => 6, -cols => 70 );
	print
"</fieldset></div>\n<div style=\"clear:both\"><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page\" class=\"resetbutton\">"
	  . "Reset</a><span style=\"float:right\">";
	print $q->submit( -name => 'Submit', -class => 'submit' );
	print "</span></div></div>";
	print $q->hidden($_) foreach qw (db page);
	print $q->end_form;
	print "</div>\n";
	$self->_run_query($sequence) if $q->param('Submit') && $sequence;
	return;
}

sub _run_query {
	my ( $self, $sequence ) = @_;
	my $q    = $self->{'cgi'};
	my $page = $q->param('page');
	$self->remove_all_identifier_lines( \$sequence ) if $page eq 'sequenceQuery';    #Allows BLAST of multiple contigs
	if ( $sequence !~ /^>/ ) {

		#add identifier line if one missing since newer versions of BioPerl check
		$sequence = ">\n$sequence";
	}
	my $stringfh_in = IO::String->new($sequence);
	my $seqin = Bio::SeqIO->new( -fh => $stringfh_in, -format => 'fasta' );
	my $batch_buffer;
	my $td = 1;
	local $| = 1;
	my $first = 1;
	my $job   = 0;
	my $locus = $q->param('locus');

	if ( $locus =~ /^cn_(.+)$/ ) {
		$locus = $1;
	}
	my $distinct_locus_selected = ( $locus && $locus !~ /SCHEME_\d+/ ) ? 1 : 0;
	my $cleaned_locus           = $self->clean_locus($locus);
	my $locus_info              = $self->{'datastore'}->get_locus_info($locus);
	my $text_filename           = BIGSdb::Utils::get_random() . '.txt';
	while ( my $seq_object = $seqin->next_seq ) {
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
		my $seq = $seq_object->seq;
		$seq =~ s/\s//g if $seq;
		$seq = uc($seq);
		my $seq_type = BIGSdb::Utils::is_valid_DNA($seq) ? 'DNA' : 'peptide';
		my $qry_type = BIGSdb::Utils::sequence_type($seq);
		( my $blast_file, $job ) = $self->run_blast(
			{ 'locus' => $locus, 'seq_ref' => \$seq, 'qry_type' => $qry_type, 'num_results' => 50000, 'cache' => 1, 'job' => $job } );
		my $exact_matches = $self->parse_blast_exact( $locus, $blast_file );
		my $data_ref = {
			locus                   => $locus,
			locus_info              => $locus_info,
			seq_type                => $seq_type,
			qry_type                => $qry_type,
			distinct_locus_selected => $distinct_locus_selected,
			td                      => $td,
			seq_ref                 => \$seq,
			id                      => $seq_object->id // '',
			job                     => $job,
			linked_data             => $self->_data_linked_to_locus( $locus, 'client_dbase_loci_fields' ),
			extended_attributes     => $self->_data_linked_to_locus( $locus, 'locus_extended_attributes' ),
		};

		if ( ref $exact_matches eq 'ARRAY' && @$exact_matches ) {
			if ( $page eq 'sequenceQuery' ) {
				$self->_output_single_query_exact( $exact_matches, $data_ref );
			} else {
				$batch_buffer = $self->_output_batch_query_exact( $exact_matches, $data_ref, $text_filename );
			}
		} else {
			if ( defined $locus_info->{'data_type'} && $qry_type ne $locus_info->{'data_type'} && $distinct_locus_selected ) {
				system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$blast_file";
				if ( $page eq 'sequenceQuery' ) {
					$self->_output_single_query_nonexact_mismatched($data_ref);
					$blast_file =~ s/_outfile.txt//;
					system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$blast_file*";
					return;
				}
			}
			my $partial_match = $self->parse_blast_partial($blast_file);
			if ( ref $partial_match ne 'HASH' || !defined $partial_match->{'allele'} ) {
				if ( $page eq 'sequenceQuery' ) {
					print "<div class=\"box\" id=\"statusbad\"><p>No matches found.</p></div>\n";
				} else {
					my $id = defined $seq_object->id ? $seq_object->id : '';
					$batch_buffer = "<tr class=\"td$td\"><td>$id</td><td style=\"text-align:left\">No matches found.</td></tr>\n";
				}
			} else {
				if ( $page eq 'sequenceQuery' ) {
					$self->_output_single_query_nonexact( $partial_match, $data_ref );
				} else {
					$batch_buffer = $self->_output_batch_query_nonexact( $partial_match, $data_ref, $text_filename );
				}
			}
		}
		system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$blast_file";
		last if ( $page eq 'sequenceQuery' );    #only go round again if this is a batch query
		$td = $td == 1 ? 2 : 1;
		if ( $page eq 'batchSequenceQuery' ) {
			if ($first) {
				print "<div class=\"box\" id=\"resultsheader\">\n";
				print "<table class=\"resultstable\"><tr><th>Sequence</th><th>Results</th></tr>\n";
				$first = 0;
			}
			print $batch_buffer if $batch_buffer;
		}
	}
	system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$job*";
	if ( $page eq 'batchSequenceQuery' && $batch_buffer ) {
		print "</table>\n";
		print "<p><a href=\"/tmp/$text_filename\">Text format</a></p></div>\n";
	}
	return;
}

sub _output_single_query_exact {
	my ( $self, $exact_matches, $data ) = @_;
	my $data_type               = $data->{'locus_info'}->{'data_type'};
	my $seq_type                = $data->{'seq_type'};
	my $locus                   = $data->{'locus'};
	my $distinct_locus_selected = $data->{'distinct_locus_selected'};
	my $q                       = $self->{'cgi'};
	my %designations;
	print "<div class=\"box\" id=\"resultsheader\"><p>\n";
	print @$exact_matches . " exact match" . ( @$exact_matches > 1 ? 'es' : '' ) . " found.</p></div>";
	print "<div class=\"box\" id=\"resultstable\">\n";

	if ( defined $data_type && $data_type eq 'peptide' && $seq_type eq 'DNA' ) {
		print "<p>Please note that as this is a peptide locus, the length corresponds to the peptide translated from your "
		  . "query sequence.</p>\n";
	} elsif ( defined $data_type && $data_type eq 'DNA' && $seq_type eq 'peptide' ) {
		print "<p>Please note that as this is a DNA locus, the length corresponds to the matching nucleotide sequence that "
		  . "was translated to align against your peptide query sequence.</p>\n";
	}
	print "<div class=\"scrollable\"><table class=\"resultstable\"><tr><th>Allele</th><th>Length</th><th>Start position</th>"
	  . "<th>End position</th>"
	  . ( $data->{'linked_data'}         ? '<th>Linked data values</th>' : '' )
	  . ( $data->{'extended_attributes'} ? '<th>Attributes</th>'         : '' )
	  . ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ? '<th>Flags</th>' : '' )
	  . "</tr>\n";
	if ( !$distinct_locus_selected && $q->param('order') eq 'locus' ) {
		my %locus_values;
		foreach (@$exact_matches) {
			if ( $_->{'allele'} =~ /(.*):.*/ ) {
				$locus_values{$_} = $1;
			}
		}
		@$exact_matches = sort { $locus_values{$a} cmp $locus_values{$b} } @$exact_matches;
	}
	my $td = 1;
	foreach (@$exact_matches) {
		print "<tr class=\"td$td\"><td>";
		my $allele;
		my ( $field_values, $attributes, $flags );
		if ($distinct_locus_selected) {
			my $cleaned = $self->clean_locus($locus);
			print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleInfo&amp;locus=$locus&amp;allele_id=$_->{'allele'}\">";
			$allele       = "$cleaned: $_->{'allele'}";
			$field_values = $self->_get_client_dbase_fields( $locus, [ $_->{'allele'} ] );
			$attributes   = $self->_get_allele_attributes( $locus, [ $_->{'allele'} ] );
			$flags        = $self->{'datastore'}->get_allele_flags( $locus, $_->{'allele'} );
		} else {    #either all loci or a scheme selected
			my ( $locus, $allele_id );
			if ( $_->{'allele'} =~ /(.*):(.*)/ ) {
				( $locus, $allele_id ) = ( $1, $2 );
				$designations{$locus} = $allele_id;
				my $cleaned = $self->clean_locus($locus);
				$allele       = "$cleaned: $allele_id";
				$field_values = $self->_get_client_dbase_fields( $locus, [$allele_id] );
				$attributes   = $self->_get_allele_attributes( $locus, [$allele_id] );
				$flags        = $self->{'datastore'}->get_allele_flags( $locus, $allele_id );
			}
			print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleInfo&amp;locus=$locus&amp;allele_id=$allele_id\">"
			  if $locus && $allele_id;
		}
		print "$allele</a></td><td>$_->{'length'}</td><td>$_->{'start'}</td><td>$_->{'end'}</td>";
		print defined $field_values ? "<td style=\"text-align:left\">$field_values</td>" : '<td />' if $data->{'linked_data'};
		print defined $attributes   ? "<td style=\"text-align:left\">$attributes</td>"   : '<td />' if $data->{'extended_attributes'};
		if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
			local $" = '</a> <a class="seqflag_tooltip">';
			print @$flags ? "<td style=\"text-align:left\"><a class=\"seqflag_tooltip\">@$flags</a></td>" : '<td />';
		}
		print "</tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	print "</table></div>\n";
	$self->_output_scheme_fields( $locus, \%designations );
	print "</div>\n";
	return;
}

sub _output_scheme_fields {
	my ( $self, $locus, $designations ) = @_;
	if ( $locus =~ /SCHEME_(\d+)/ ) {    #Check for scheme fields
		my $scheme_id     = $1;
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		my $scheme_loci   = $self->{'datastore'}->get_scheme_loci($scheme_id);
		if ( @$scheme_fields && @$scheme_loci ) {
			my ( @profile, @placeholders );
			foreach (@$scheme_loci) {
				push @profile,      $designations->{$_};
				push @placeholders, '?';
			}
			if ( none { !defined $_ } @profile ) {
				local $" = ',';
				my $values =
				  $self->{'datastore'}
				  ->run_simple_query_hashref( "SELECT @$scheme_fields FROM scheme_$scheme_id WHERE (@$scheme_loci) = (@placeholders)",
					@profile );
				my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
				print "<h2>$scheme_info->{'description'}</h2>\n<table>\n";
				my $pks =
				  $self->{'datastore'}->run_list_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id );
				my $td = 1;
				foreach my $field (@$scheme_fields) {
					my $value = $values->{ lc($field) } // 'Not defined';
					my $primary_key = ( any { $field eq $_ } @$pks ) ? 1 : 0;
					$field =~ tr/_/ /;
					print "<tr class=\"td$td\"><th>$field</th><td>";
					print $primary_key && $value ne 'Not defined'
					  ? "<a href=\"$self->{'system'}->{'script_name'}?page=profileInfo&amp;db=$self->{'instance'}&amp;scheme_id=$scheme_id&amp;profile_id=$value\">$value</a>"
					  : $value;
					print "</td></tr>\n";
					$td = $td == 1 ? 2 : 1;
				}
				print "</table>\n";
			}
		}
	}
	return;
}

sub _output_batch_query_exact {
	my ( $self, $exact_matches, $data, $filename ) = @_;
	my $locus                   = $data->{'locus'};
	my $distinct_locus_selected = $data->{'distinct_locus_selected'};
	my $td                      = $data->{'td'};
	my $id                      = $data->{'id'};
	my $q                       = $self->{'cgi'};
	my $buffer                  = "Exact match" . ( @$exact_matches == 1 ? '' : 'es' ) . " found: ";
	if ( !$distinct_locus_selected && $q->param('order') eq 'locus' ) {
		my %locus_values;
		foreach (@$exact_matches) {
			if ( $_->{'allele'} =~ /(.*):.*/ ) {
				$locus_values{$_} = $1;
			}
		}
		@$exact_matches = sort { $locus_values{$a} cmp $locus_values{$b} } @$exact_matches;
	}
	my $first       = 1;
	my $text_buffer = '';
	foreach (@$exact_matches) {
		if ( !$first ) {
			$buffer      .= '; ';
			$text_buffer .= '; ';
		}
		my $allele_id;
		if ( !$distinct_locus_selected && $_->{'allele'} =~ /(.*):(.*)/ ) {
			( $locus, $allele_id ) = ( $1, $2 );
		} else {
			$allele_id = $_->{'allele'};
		}
		my $cleaned_locus = $self->clean_locus($locus);
		$buffer .=
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleInfo&amp;locus=$locus&amp;allele_id=$allele_id\">$cleaned_locus: $allele_id</a>";
		$text_buffer .= "$cleaned_locus-$allele_id";
		undef $locus if !$distinct_locus_selected;
		$first = 0;
	}
	open( my $fh, '>>', "$self->{'config'}->{'tmp_dir'}/$filename" ) or $logger->error("Can't open $filename for appending");
	say $fh "$id: $text_buffer";
	close $fh;
	return "<tr class=\"td$td\"><td>$id</td><td style=\"text-align:left\">$buffer</td></tr>\n";
}

sub _output_single_query_nonexact_mismatched {
	my ( $self, $data ) = @_;
	my ( $blast_file, undef ) = $self->run_blast(
		{
			'locus'       => $data->{'locus'},
			'seq_ref'     => $data->{'seq_ref'},
			'qry_type'    => $data->{'qry_type'},
			'num_results' => 5,
			'alignment'   => 1,
		}
	);
	print "<div class=\"box\" id=\"resultsheader\">\n";
	if ( -e "$self->{'config'}->{'secure_tmp_dir'}/$blast_file" ) {
		print "<p>Your query is a $data->{'qry_type'} sequence whereas this locus is defined with $data->{'locus_info'}->{'data_type'} "
		  . "sequences.  There were no exact matches, but the BLAST results are shown below (a maximum of five alignments are displayed).</p>";
		print "<pre style=\"font-size:1.4em; padding: 1em; border:1px black dashed\">\n";
		$self->print_file( "$self->{'config'}->{'secure_tmp_dir'}/$blast_file", 1 );
		print "</pre>\n";
	} else {
		print "<p>No results from BLAST.</p>\n";
	}
	$blast_file =~ s/outfile.txt//;
	system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$blast_file*";
	return;
}

sub _output_single_query_nonexact {
	my ( $self, $partial_match, $data ) = @_;
	my $distinct_locus_selected = $data->{'distinct_locus_selected'};
	my $locus                   = $data->{'locus'};
	my $qry_type                = $data->{'qry_type'};
	my $seq_ref                 = $data->{'seq_ref'};
	print "<div class=\"box\" id=\"resultsheader\"><p>Closest match: ";
	my $cleaned_match = $partial_match->{'allele'};
	my $cleaned_locus;

	if ($distinct_locus_selected) {
		print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleInfo&amp;locus=$locus&amp;allele_id=$cleaned_match\">";
		$cleaned_locus = $self->clean_locus($locus);
		print "$cleaned_locus: ";
	} else {
		my ( $locus, $allele_id );
		if ( $cleaned_match =~ /(.*):(.*)/ ) {
			( $locus, $allele_id ) = ( $1, $2 );
			$cleaned_locus = $self->clean_locus($locus);
			$cleaned_match = "$cleaned_locus: $allele_id";
			print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleInfo&amp;locus=$locus&amp;allele_id=$allele_id\">";
		}
	}
	print "$cleaned_match</a></p>";
	my ( $data_type, $allele_seq_ref );
	if ($distinct_locus_selected) {
		$allele_seq_ref = $self->{'datastore'}->get_sequence( $locus, $partial_match->{'allele'} );
		$data_type = $data->{'locus_info'}->{'data_type'};
	} else {
		my ( $locus, $allele ) = split /:/, $partial_match->{'allele'};
		$allele_seq_ref = $self->{'datastore'}->get_sequence( $locus, $allele );
		$data_type = $self->{'datastore'}->get_locus_info($locus)->{'data_type'};
	}
	if ( $data_type eq $data->{'qry_type'} ) {
		my $temp        = BIGSdb::Utils::get_random();
		my $seq1_infile = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_file1.txt";
		my $seq2_infile = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_file2.txt";
		my $outfile     = "$self->{'config'}->{'tmp_dir'}/$temp\_outfile.txt";
		open( my $seq1_fh, '>', $seq2_infile );
		print $seq1_fh ">Ref\n$$allele_seq_ref\n";
		close $seq1_fh;
		open( my $seq2_fh, '>', $seq1_infile );
		print $seq2_fh ">Query\n$$seq_ref\n";
		close $seq2_fh;
		my $start = $partial_match->{'qstart'} =~ /(\d+)/ ? $1 : undef;    #untaint
		my $end   = $partial_match->{'qend'}   =~ /(\d+)/ ? $1 : undef;
		my $reverse = $partial_match->{'reverse'} ? 1 : 0;
		my @args = (
			'-aformat', 'markx2', '-awidth', $self->{'prefs'}->{'alignwidth'},
			'-asequence', $seq1_infile, '-bsequence', $seq2_infile, '-sreverse1', $reverse, '-outfile', $outfile
		);
		push @args, ( '-sbegin1', $start, '-send1', $end ) if length $$seq_ref > 10000;
		system("$self->{'config'}->{'emboss_path'}/stretcher @args 2>/dev/null");
		unlink $seq1_infile, $seq2_infile;

		#Display nucleotide differences if BLAST reports no gaps.
		if ( !$partial_match->{'gaps'} ) {
			my $qstart = $partial_match->{'qstart'};
			my $sstart = $partial_match->{'sstart'};
			my $ssend  = $partial_match->{'send'};
			while ( $sstart > 1 && $qstart > 1 ) {
				$sstart--;
				$qstart--;
			}
			if ($reverse) {
				print "<p>The sequence is reverse-complemented with respect to the reference sequence. "
				  . "The list of differences is disabled but you can use the alignment or try reversing it and querying again.</p>\n";
				$self->_print_alignment( $outfile, $temp );
			} else {
				$self->_print_alignment( $outfile, $temp );
				my $diffs = $self->_get_differences( $allele_seq_ref, $seq_ref, $sstart, $qstart );
				print "<h2>Differences</h2>\n";
				if (@$diffs) {
					my $plural = @$diffs > 1 ? 's' : '';
					print "<p>" . @$diffs . " difference$plural found. ";
					my $data_type;
					if ( defined $data->{'locus_info'}->{'data_type'} ) {
						$data_type = $data->{'locus_info'}->{'data_type'} eq 'DNA' ? 'nucleotide' : 'residue';
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
						print $self->_format_difference( $_, $qry_type ) . '<br />';
					}
					print "</p>\n";
					if ( $sstart > 1 ) {
						print "<p>Your query sequence only starts at position $sstart of sequence ";
						print "$locus: " if $locus && $locus !~ /SCHEME_\d+/;
						print "$cleaned_match.</p>\n";
					} else {
						print "<p>The locus start point is at position " . ( $qstart - $sstart + 1 ) . " of your query sequence.";
						print
" <a class=\"tooltip\" title=\"start position - This may be approximate if there are gaps near the beginning of the alignment "
						  . "between your query and the reference sequence.\">&nbsp;<i>i</i>&nbsp;</a>";
						print "</p>\n";
					}
				} else {
					print "<p>Your query sequence only starts at position $sstart of sequence ";
					print "$locus: " if $distinct_locus_selected;
					print "$partial_match->{'allele'}.</p>\n";
				}
			}
		} else {
			print "<p>An alignment between your query and the returned reference sequence is shown rather than a simple "
			  . "list of differences because there are gaps in the alignment.</p>\n";
			print "<pre style=\"font-size:1.2em\">\n";
			$self->print_file( $outfile, 1 );
			print "</pre>\n";
			system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$temp*";
		}
	} else {
		my ( $blast_file, undef ) = $self->run_blast(
			{
				'locus'       => $locus,
				'seq_ref'     => $seq_ref,
				'qry_type'    => $qry_type,
				'num_results' => 5,
				'alignment'   => 1,
				'cache'       => 1,
				'job'         => $data->{'job'}
			}
		);
		if ( -e "$self->{'config'}->{'secure_tmp_dir'}/$blast_file" ) {
			print "<p>Your query is a $qry_type sequence whereas this locus is defined with "
			  . ( $qry_type eq 'DNA' ? 'peptide' : 'DNA' )
			  . " sequences.  There were no exact matches, but the BLAST results are shown below (a maximum of five "
			  . "alignments are displayed).</p>";
			print "<pre style=\"font-size:1.4em; padding: 1em; border:1px black dashed\">\n";
			$self->print_file( "$self->{'config'}->{'secure_tmp_dir'}/$blast_file", 1 );
			print "</pre>\n";
		} else {
			print "<p>No results from BLAST.</p>\n";
		}
		system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$blast_file";
	}
	print "</div>\n";
	return;
}

sub _print_alignment {
	my ( $self, $outfile, $outfile_prefix ) = @_;
	if ( -e $outfile ) {
		my $cleaned_file = "$self->{'config'}->{'tmp_dir'}/$outfile_prefix\_cleaned.txt";
		$self->_cleanup_alignment( $outfile, $cleaned_file );
		print "<p><a href=\"/tmp/$outfile_prefix\_cleaned.txt\" id=\"alignment_link\" rel=\"ajax\">Show alignment</a></p>\n";
		print "<pre style=\"font-size:1.2em\"><span id=\"alignment\"></span></pre>\n";
	}
	return;
}

sub _output_batch_query_nonexact {
	my ( $self, $partial_match, $data, $filename ) = @_;
	my $locus                   = $data->{'locus'};
	my $distinct_locus_selected = $data->{'distinct_locus_selected'};
	my ( $batch_buffer, $buffer, $text_buffer );
	my $allele_seq_ref;
	if ($distinct_locus_selected) {
		$allele_seq_ref = $self->{'datastore'}->get_sequence( $locus, $partial_match->{'allele'} );
	} else {
		my ( $locus, $allele ) = split /:/, $partial_match->{'allele'};
		$allele_seq_ref = $self->{'datastore'}->get_sequence( $locus, $allele );
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
			$buffer      .= "Reverse complemented - try reversing it and query again.";
			$text_buffer .= "Reverse complemented - try reversing it and query again.";
		} else {
			my $diffs = $self->_get_differences( $allele_seq_ref, $data->{'seq_ref'}, $sstart, $qstart );
			if (@$diffs) {
				my $plural = @$diffs > 1 ? 's' : '';
				$buffer      .= (@$diffs) . " difference$plural found. ";
				$text_buffer .= (@$diffs) . " difference$plural found. ";
				my $first = 1;
				foreach (@$diffs) {
					if ( !$first ) {
						$buffer      .= '; ';
						$text_buffer .= '; ';
					}
					$buffer .= $self->_format_difference( $_, $data->{'qry_type'} );
					$text_buffer .= "\[$_->{'spos'}\]$_->{'sbase'}->\[" . ( $_->{'qpos'} // '' ) . "\]$_->{'qbase'}";
					$first = 0;
				}
			}
		}
	} else {
		$buffer      .= "There are insertions/deletions between these sequences.  Try single sequence query to get more details.";
		$text_buffer .= "Insertions/deletions present.";
	}
	my ( $allele, $cleaned_locus, $text_allele );
	if ($distinct_locus_selected) {
		$cleaned_locus = $self->clean_locus($locus);
		$allele =
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleInfo&amp;locus=$locus&amp;allele_id=$partial_match->{'allele'}\">$cleaned_locus: $partial_match->{'allele'}</a>";
		$text_allele = "$locus-$partial_match->{'allele'}";
	} else {
		if ( $partial_match->{'allele'} =~ /(.*):(.*)/ ) {
			my ( $locus, $allele_id ) = ( $1, $2 );
			$cleaned_locus = $self->clean_locus($locus);
			$partial_match->{'allele'} =~ s/:/: /;
			$allele =
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleInfo&amp;locus=$locus&amp;allele_id=$allele_id\">$cleaned_locus: $allele_id</a>";
			$text_allele = "$locus-$allele_id";
		}
	}
	$batch_buffer =
	  "<tr class=\"td$data->{'td'}\"><td>$data->{'id'}</td><td style=\"text-align:left\">Partial match found: $allele: $buffer</td></tr>\n";
	open( my $fh, '>>', "$self->{'config'}->{'tmp_dir'}/$filename" ) or $logger->error("Can't open $filename for appending");
	say $fh "$data->{'id'}: Partial match: $text_allele: $text_buffer";
	close $fh;
	return $batch_buffer;
}

sub remove_all_identifier_lines {
	my ( $self, $seq_ref ) = @_;
	$$seq_ref =~ s/>.+\n//g;
	return;
}

sub _format_difference {
	my ( $self, $diff, $qry_type ) = @_;
	my $buffer;
	if ( $qry_type eq 'DNA' ) {
		$buffer .= "<sup>$_->{'spos'}</sup>";
		$buffer .= "<span class=\"$_->{'sbase'}\">$_->{'sbase'}</span>";
		$buffer .= " &rarr; ";
		$buffer .= defined $_->{'qpos'} ? "<sup>$_->{'qpos'}</sup>" : '';
		$buffer .= "<span class=\"$_->{'qbase'}\">$_->{'qbase'}</span>";
	} else {
		$buffer .= "<sup>$_->{'spos'}</sup>";
		$buffer .= $_->{'sbase'};
		$buffer .= " &rarr; ";
		$buffer .= defined $_->{'qpos'} ? "<sup>$_->{'qpos'}</sup>" : '';
		$buffer .= "$_->{'qbase'}";
	}
	return $buffer;
}

sub parse_blast_exact {
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

sub parse_blast_partial {

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
		$match{'qend'}      = $record[7];
		$match{'sstart'}    = $record[8];
		$match{'send'}      = $record[9];
		if ( ( $record[8] > $record[9] && $record[7] > $record[6] ) || ( $record[8] < $record[9] && $record[7] < $record[6] ) ) {
			$match{'reverse'} = 1;
		} else {
			$match{'reverse'} = 0;
		}
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
	return;
}

sub _get_client_dbase_fields {
	my ( $self, $locus, $allele_ids_refs ) = @_;
	return [] if ref $allele_ids_refs ne 'ARRAY';
	my $sql = $self->{'db'}->prepare("SELECT client_dbase_id,isolate_field FROM client_dbase_loci_fields WHERE allele_query AND locus = ?");
	eval { $sql->execute($locus) };
	$logger->error($@) if $@;
	my $values;
	my %db_desc;
	while ( my ( $client_dbase_id, $field ) = $sql->fetchrow_array ) {
		my $client_db      = $self->{'datastore'}->get_client_db($client_dbase_id)->get_db;
		my $client_db_desc = $self->{'datastore'}->get_client_db_info($client_dbase_id)->{'name'};
		my $client_sql     = $client_db->prepare(
"SELECT $field FROM isolates LEFT JOIN allele_designations ON isolates.id = allele_designations.isolate_id WHERE allele_designations.locus=? AND allele_designations.allele_id=?"
		);
		foreach (@$allele_ids_refs) {
			eval { $client_sql->execute( $locus, $_ ) };
			if ($@) {
				$logger->error(
"Can't extract isolate field '$field' FROM client database, make sure the client_dbase_loci_fields table is correctly configured.  $@"
				);
			} else {
				while ( my ($value) = $client_sql->fetchrow_array ) {
					next if !defined $value || $value eq '';
					if ( any { $field eq $_ } qw (species genus) ) {
						$value = "<i>$value</i>";
					}
					push @{ $values->{$field} }, $value;
					$db_desc{$client_db_desc} = 1;
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
		my @dbs = sort keys %db_desc;
		local $" = "</span> <span class=\"link\">";
		$buffer .= "<span class=\"link\">@dbs</span> ";
		$buffer .= $self->_format_list_values($values);
	}
	return $buffer;
}

sub _get_allele_attributes {
	my ( $self, $locus, $allele_ids_refs ) = @_;
	return [] if ref $allele_ids_refs ne 'ARRAY';
	my $fields = $self->{'datastore'}->run_list_query( "SELECT field FROM locus_extended_attributes WHERE locus=?", $locus );
	my $sql = $self->{'db'}->prepare("SELECT value FROM sequence_extended_attributes WHERE locus=? AND field=? AND allele_id=?");
	my $values;
	return if !@$fields;
	foreach my $field (@$fields) {
		foreach (@$allele_ids_refs) {
			eval { $sql->execute( $locus, $field, $_ ) };
			$logger->error($@) if $@;
			while ( my ($value) = $sql->fetchrow_array ) {
				next if !defined $value || $value eq '';
				push @{ $values->{$field} }, $value;
			}
		}
		if ( ref $values->{$field} eq 'ARRAY' && @{ $values->{$field} } ) {
			my @list = @{ $values->{$field} };
			@list = uniq sort @list;
			@{ $values->{$field} } = @list;
		}
	}
	return $self->_format_list_values($values);
}

sub _format_list_values {
	my ( $self, $hash_ref ) = @_;
	my $buffer = '';
	if ( keys %$hash_ref ) {
		my $first = 1;
		foreach ( sort keys %$hash_ref ) {
			local $" = ', ';
			$buffer .= '; ' if !$first;
			$buffer .= "$_: @{$hash_ref->{$_}}";
			$first = 0;
		}
	}
	return $buffer;
}

sub _data_linked_to_locus {
	my ( $self, $locus, $table ) = @_;    #Locus is value defined in drop-down box - may be a scheme or 0 for all loci.
	my $qry;
	given ($locus) {
		when ('0') { $qry = "SELECT EXISTS (SELECT * FROM $table)" }
		when (/SCHEME_(\d+)/) {
			$qry = "SELECT EXISTS (SELECT * FROM $table WHERE locus IN " . "(SELECT locus FROM scheme_members WHERE scheme_id=$1))"
		}
		default {
			$locus =~ s/'/\\'/g;
			$qry = "SELECT EXISTS (SELECT * FROM $table WHERE locus=E'$locus')";
		}
	}
	return $self->{'datastore'}->run_simple_query($qry)->[0];
}
1;
