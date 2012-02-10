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
package BIGSdb::ExtractedSequencePage;
use strict;
use warnings;
use parent qw(BIGSdb::Page);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self)       = @_;
	my $q            = $self->{'cgi'};
	my $seqbin_id    = $q->param('seqbin_id');
	my $start        = $q->param('start');
	my $end          = $q->param('end');
	my $reverse      = $q->param('reverse');
	my $translate    = $q->param('translate');
	my $orf          = $q->param('orf');
	my $no_highlight = $q->param('no_highlight');
	if ( !BIGSdb::Utils::is_int($seqbin_id) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Sequence bin id must be an integer.</p></div>\n";
		return;
	}
	if ( !BIGSdb::Utils::is_int($start) || !BIGSdb::Utils::is_int($end) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Start and end values must be integers.</p></div>\n";
		return;
	}
	my $exists = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM sequence_bin WHERE id=?", $seqbin_id )->[0];
	if ( !$exists ) {
		print "<div class=\"box\" id=\"statusbad\"><p>There is no sequence with sequence bin id#$seqbin_id.</p></div>\n";
		return;
	}
	print "<h1>Extracted sequence: Seqbin id#:$seqbin_id ($start-$end)</h1>\n";
#	my $flanking   = $q->param('flanking') || $self->{'prefs'}->{'flanking'};
	my $length     = abs( $end - $start + 1 );
	my $method_ref = $self->{'datastore'}->run_simple_query( "SELECT method FROM sequence_bin WHERE id=?", $seqbin_id );
	$logger->error("No method") if ref $method_ref ne 'ARRAY';
	print "<div class=\"box\" id=\"resultstable\">\n";
	print "<div class=\"scrollable\">\n";
	print "<table class=\"resultstable\">\n";
	print "<tr><th colspan=\"3\">sequence bin id#$seqbin_id</th></tr>\n";
	print "<tr class=\"td1\"><th>sequence method</th><td>$method_ref->[0]</td><td rowspan=\"5\" class=\"seq\" style=\"text-align:left\">";
	my $display = $self->display_sequence( $seqbin_id, $reverse, $start, $end, $translate, $orf );
	print $display->{'seq'};
	print "</td></tr>\n";
	print "<tr class=\"td1\"><th>start</th><td>$start</td></tr>\n";
	print "<tr class=\"td1\"><th>end</th><td>$end</td></tr>\n";
	print "<tr class=\"td1\"><th>length</th><td>$length</td></tr>\n";
	print "<tr class=\"td1\"><th>orientation</th><td style=\"font-size:2em\">" . ( $reverse ? '&larr;' : '&rarr;' ) . "</td></tr>\n";

	if ($translate) {
		print "<tr class=\"td1\"><th>translation</th><td colspan=\"2\" style=\"text-align:left\">";
		my @stops = @{ $display->{'internal_stop'} };
		if ( @stops && !$no_highlight ) {
			$" = ', ';
			print "<span class=\"highlight\">Internal stop codon"
			  . ( @stops == 1 ? '' : 's' )
			  . " at position"
			  . ( @stops == 1 ? '' : 's' )
			  . ": @stops (numbering includes upstream flanking sequence).</span>\n";
		}
		print "<pre class=\"sixpack\">\n";
		print $display->{'sixpack'};
		print "</pre>\n";
		print "</td></tr>\n";
	}
	print "</table>\n</div></div>\n";
}

sub display_sequence {
	my ( $self, $seqbin_id, $reverse, $start, $end, $translate, $orf ) = @_;
	$start = 1 if $start < 1;
	my $contig_length = $self->{'datastore'}->run_simple_query( "SELECT length(sequence) FROM sequence_bin WHERE id=?", $seqbin_id )->[0];
	$end = $contig_length if $end > $contig_length;
	my $flanking = $self->{'cgi'}->param('flanking') || $self->{'prefs'}->{'flanking'};
	$flanking = (BIGSdb::Utils::is_int($flanking) && $flanking >= 0) ? $flanking : 100;
	my $length   = abs( $end - $start + 1 );
	my $qry =
"SELECT substring(sequence from $start for $length) AS seq,substring(sequence from ($start-$flanking) for $flanking) AS upstream,substring(sequence from ($end+1) for $flanking) AS downstream FROM sequence_bin WHERE id=?";
	my $seq_ref = $self->{'datastore'}->run_simple_query_hashref( $qry, $seqbin_id );
	$seq_ref->{'seq'}        = BIGSdb::Utils::reverse_complement( $seq_ref->{'seq'} )        if $reverse;
	$seq_ref->{'upstream'}   = BIGSdb::Utils::reverse_complement( $seq_ref->{'upstream'} )   if $reverse;
	$seq_ref->{'downstream'} = BIGSdb::Utils::reverse_complement( $seq_ref->{'downstream'} ) if $reverse;
	my $upstream_offset =
	  $reverse ? ( 10 - substr( length( $seq_ref->{'downstream'} ), -1 ) ) : ( 10 - substr( length( $seq_ref->{'upstream'} ), -1 ) );
	my $downstream_offset =
	  $reverse
	  ? ( 10 - substr( $length + length( $seq_ref->{'downstream'} ), -1 ) )
	  : ( 10 - substr( $length + length( $seq_ref->{'upstream'} ), -1 ) );
	my $seq1 = substr( $seq_ref->{'seq'}, 0, $upstream_offset );
	my $seq2 = substr( $seq_ref->{'seq'}, $upstream_offset );
	my $downstream = $reverse ? $seq_ref->{'upstream'} : $seq_ref->{'downstream'};
	my $downstream1 = substr( $downstream, 0, $downstream_offset );
	my $downstream2 = (length ($downstream) >= $downstream_offset) ? substr( $downstream, $downstream_offset ) : '';
	my $sixpack;
	my @internal_stop_codons;

	if ( $translate && $self->{'config'}->{'emboss_path'} && -e "$self->{'config'}->{'emboss_path'}/sixpack" ) {
		my $temp       = BIGSdb::Utils::get_random();
		my $seq_infile = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_infile.txt";
		my $outfile    = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_sixpack.txt";
		my $outseq     = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_outseq.txt";
		open( my $seq_fh, '>', $seq_infile );
		print $seq_fh ">seq\n";
		print $seq_fh ( $reverse ? $seq_ref->{'downstream'} : $seq_ref->{'upstream'} ) . "$seq1$seq2$downstream1$downstream2\n";
		close $seq_fh;
		my $upstream_length = length( $reverse ? $seq_ref->{'downstream'} : $seq_ref->{'upstream'} );
		my @highlights;
		my $highlight_start = ( length( $reverse ? $seq_ref->{'downstream'} : $seq_ref->{'upstream'} ) =~ /(\d+)/ ) ? ( $1 + 1 ) : 0;
		my $highlight_end = ( $length =~ /(\d+)/ ) ? ( $1 - 1 + $highlight_start ) : 0;
		$orf = 1 if !$orf;
		my $first_codon = substr( $seq_ref->{'seq'}, $orf - 1, 3 );
		my $end_codon_pos = $orf - 1 + 3 * int( ( length( $seq_ref->{'seq'} ) - $orf + 1 - 3 ) / 3 );
		my $last_codon = substr( $seq_ref->{'seq'}, $end_codon_pos, 3 );
		my $start_offset = ( any { $first_codon eq $_ } qw (ATG TTG GTG) ) ? $orf + 2 : 0;
		my $end_offset = ( any { $last_codon eq $_ } qw (TAA TAG TGA) ) ? ( $length - $end_codon_pos ) : 0;
		$end_offset = 0 if $end_offset > 3;

		#5' of start codon
		if ( $orf > 1 && $start_offset ) {
			push @highlights, ($highlight_start) . '-' . ( $highlight_start + $orf - 2 ) . " coding";
		}

		#start codon
		if ($start_offset) {
			push @highlights, ( $highlight_start + $orf - 1 ) . '-' . ( $highlight_start + $orf + 1 ) . " startcodon";
		}

		#Coding sequence between start and end codons
		push @highlights, ( $highlight_start + $start_offset ) . '-' . ( $highlight_end - $end_offset ) . " coding"
		  if $highlight_start && $highlight_end;

		#end codon
		if ($end_offset) {
			push @highlights, ( $highlight_end - 2 ) . "-$highlight_end stopcodon";
		}

		#3' of end codon
		$" = ' ';
		my $highlight;
		if (@highlights) {
			$highlight = "-highlight \"@highlights\"";
		}
		if ( $highlight =~ /(\-highlight.*)/ ) {
			$highlight = $1;
		}
		system(
"$self->{'config'}->{'emboss_path'}/sixpack -sequence $seq_infile -outfile $outfile -outseq $outseq -width $self->{'prefs'}->{'alignwidth'} -noreverse -noname -html $highlight 2>/dev/null"
		);
		open( my $sixpack_fh, '<', $outfile );
		while ( my $line = <$sixpack_fh> ) {
			last if $line =~ /^########/;
			$line =~ s/<H3><\/H3>//;
			$line =~ s/<PRE>//;
			$line =~ s/<font color=(\w+?)>/<span class=\"$1\">/g;
			$line =~ s/<\/font>/<\/span>/g;
			$line =~ s/\*/<span class=\"stopcodon\">\*<\/span>/g;
			$sixpack .= $line;
		}
		close $sixpack_fh;
		unlink $seq_infile, $outfile, $outseq;
		if ( $orf > 3 ) {
			$orf = $orf - 3;    #reverse reading frames
		}
		foreach ( my $i = ( $orf || 1 ) - 1 ; $i < length( $seq_ref->{'seq'} ) - 3 ; $i += 3 ) {
			my $codon = substr( $seq_ref->{'seq'}, $i, 3 );
			if ( any {$codon eq $_} qw (TAA TAG TGA) ) {
				push @internal_stop_codons, $i + 1 + ( $reverse ? length( $seq_ref->{'downstream'} ) : length( $seq_ref->{'upstream'} ) );
			}
		}
	}
	my $upstream = (BIGSdb::Utils::split_line( $reverse ? $seq_ref->{'downstream'} : $seq_ref->{'upstream'} )) || '';
	my $seq_display =
	    "<span class=\"flanking\">$upstream</span>"
	  . ( $downstream_offset ? '' : ' ' )
	  . "$seq1 "
	  . ( BIGSdb::Utils::split_line($seq2) || '' )
	  . ( $downstream_offset ? '' : ' ' )
	  . "<span class=\"flanking\">$downstream1 "
	  . ( BIGSdb::Utils::split_line($downstream2) || '' )
	  . "</span>";
	my $retval;
	$retval->{'seq'}           = $seq_display;
	$retval->{'sixpack'}       = $sixpack;
	$retval->{'internal_stop'} = \@internal_stop_codons;
	return $retval;
}

sub get_title {
	my ($self)    = @_;
	my $seqbin_id = $self->{'cgi'}->param('seqbin_id');
	my $start     = $self->{'cgi'}->param('start');
	my $end       = $self->{'cgi'}->param('end');
	my $title     = "Extracted sequence: Seqbin id#:$seqbin_id ($start-$end)";
	$title .= ' - ';
	$title .= "$self->{'system'}->{'description'}";
	return $title;
}
1;
