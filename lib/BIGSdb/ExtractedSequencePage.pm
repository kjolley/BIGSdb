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
package BIGSdb::ExtractedSequencePage;
use strict;
use warnings;
use 5.010;
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
		say q(<h1>Extracted sequence</h1><div class="box" id="statusbad">)
		  . q(<p>Sequence bin id must be an integer.</p></div>);
		return;
	}
	if ( !BIGSdb::Utils::is_int($start) || !BIGSdb::Utils::is_int($end) ) {
		say q(<h1>Extracted sequence</h1><div class="box" id="statusbad">)
		  . q(<p>Start and end values must be integers.</p></div>);
		return;
	}
	if ( $orf && ( !BIGSdb::Utils::is_int($orf) || $orf < 1 || $orf > 6 ) ) {
		say q(<h1>Extracted sequence</h1><div class="box" id="statusbad">)
		  . q(<p>Orf must be an integer between 1-6.</p></div>);
		return;
	}
	my $exists = $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM sequence_bin WHERE id=?)', $seqbin_id );
	if ( !$exists ) {
		say q(<h1>Extracted sequence</h1><div class="box" id="statusbad">)
		  . qq(<p>There is no sequence with sequence bin id#$seqbin_id.</p></div>);
		return;
	}
	say qq(<h1>Extracted sequence: Seqbin id#:$seqbin_id ($start-$end)</h1>);
	my $length  = abs( $end - $start + 1 );
	my $method  = $self->{'datastore'}->run_query( 'SELECT method FROM sequence_bin WHERE id=?', $seqbin_id );
	my $display = $self->format_seqbin_sequence(
		{
			seqbin_id => $seqbin_id,
			reverse   => $reverse,
			start     => $start,
			end       => $end,
			translate => $translate,
			orf       => $orf
		}
	);
	my $orientation = $reverse ? '&larr;' : '&rarr;';
	say q(<div class="box" id="resultspanel"><dl class="data">);
	say q(<h2>Sequence position</h2>);
	say qq(<dt>sequence bin id</dt><dd>$seqbin_id</dd>);
	say qq(<dt>sequence method</dt><dd>$method</dd>);
	say qq(<dt>start</dt><dd>$start</dd>);
	say qq(<dt>end</dt><dd>$end</dd>);
	say qq(<dt>length</dt><dd>$length</dd>);
	say qq(<dt>orientation</dt><dd><span style="font-size:2em">$orientation</span></dd>);
	say q(<h2>Sequence</h2>);
	say q(<div class="seq" style="padding-left:5em">);
	say $display->{'seq'};
	say q(</div>);

	if ($translate) {
		say q(<h2>Translation</h2>);
		my @stops = @{ $display->{'internal_stop'} };
		if ( @stops && !$no_highlight ) {
			local $" = ', ';
			my $plural = @stops == 1 ? q() : q(s);
			say qq(<span class="highlight">Internal stop codon$plural at position$plural: @stops )
			  . q((numbering includes upstream flanking sequence).</span>);
		}
		say q(<div class="scrollable">);
		say q(<pre class="sixpack">);
		say $display->{'sixpack'};
		say q(</pre>);
		say q(</div>);
	}
	say q(</div>);
	return;
}

sub format_seqbin_sequence {
	my ( $self, $args ) = @_;
	$args->{'start'} = 1 if $args->{'start'} < 1;
	my $contig_length =
	  $self->{'datastore'}->run_query( 'SELECT length(sequence) FROM sequence_bin WHERE id=?', $args->{'seqbin_id'} );
	$args->{'end'} = $contig_length if $args->{'end'} > $contig_length;
	my $flanking = $self->{'cgi'}->param('flanking') || $self->{'prefs'}->{'flanking'};
	$flanking = ( BIGSdb::Utils::is_int($flanking) && $flanking >= 0 ) ? $flanking : 100;
	my $length = abs( $args->{'end'} - $args->{'start'} + 1 );
	my $qry =
	    "SELECT substring(sequence FROM $args->{'start'} FOR $length) AS seq,substring(sequence "
	  . "FROM ($args->{'start'}-$flanking) FOR $flanking) AS upstream,substring(sequence FROM "
	  . "($args->{'end'}+1) FOR $flanking) AS downstream FROM sequence_bin WHERE id=?";
	my $seq_ref = $self->{'datastore'}->run_query( $qry, $args->{'seqbin_id'}, { fetch => 'row_hashref' } );
	$seq_ref->{'seq'}        = BIGSdb::Utils::reverse_complement( $seq_ref->{'seq'} )        if $args->{'reverse'};
	$seq_ref->{'upstream'}   = BIGSdb::Utils::reverse_complement( $seq_ref->{'upstream'} )   if $args->{'reverse'};
	$seq_ref->{'downstream'} = BIGSdb::Utils::reverse_complement( $seq_ref->{'downstream'} ) if $args->{'reverse'};
	return $self->format_sequence( $seq_ref,
		{ translate => $args->{'translate'}, reverse => $args->{'reverse'}, length => $length, orf => $args->{'orf'} }
	);
}

sub _get_subseqs_and_offsets {
	my ( $self, $seq_ref, $options ) = @_;
	$seq_ref->{'downstream'} //= q();
	$seq_ref->{'upstream'}   //= q();
	my $length = $options->{'length'} // length $seq_ref->{'seq'};
	my $upstream_offset =
	  $options->{'reverse'}
	  ? ( 10 - substr( length( $seq_ref->{'downstream'} ), -1 ) )
	  : ( 10 - substr( length( $seq_ref->{'upstream'} ), -1 ) );
	my $downstream_offset =
	  $options->{'reverse'}
	  ? ( 10 - substr( $length + length( $seq_ref->{'downstream'} ), -1 ) )
	  : ( 10 - substr( $length + length( $seq_ref->{'upstream'} ), -1 ) );
	my $seq1 = substr( $seq_ref->{'seq'}, 0, $upstream_offset );
	my $seq2 = ( $upstream_offset < length $seq_ref->{'seq'} ) ? substr( $seq_ref->{'seq'}, $upstream_offset ) : q();
	my $downstream = $options->{'reverse'} ? $seq_ref->{'upstream'} : $seq_ref->{'downstream'};
	my $downstream1 = substr( $downstream, 0, $downstream_offset );
	my $downstream2 = ( length($downstream) >= $downstream_offset ) ? substr( $downstream, $downstream_offset ) : q();
	my $length_start_flanking = length( $options->{'reverse'} ? $seq_ref->{'downstream'} : $seq_ref->{'upstream'} );
	my $highlight_start = 0;

	if ( $length_start_flanking =~ /(\d+)/x ) {
		$highlight_start = $1 + 1;
	}
	my $highlight_end = 0;
	if ( $length =~ /(\d+)/x ) {
		$highlight_end = $1 - 1 + $highlight_start;
	}
	return {
		length            => $length,
		downstream1       => $downstream1,
		downstream2       => $downstream2,
		seq1              => $seq1,
		seq2              => $seq2,
		downstream_offset => $downstream_offset,
		highlight_start   => $highlight_start,
		highlight_end     => $highlight_end
	};
}

sub format_sequence {
	my ( $self, $seq_ref, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $sixpack;
	my @internal_stop_codons;
	my $orf = $options->{'orf'} // 1;
	my $seq_data = $self->_get_subseqs_and_offsets( $seq_ref, $options );
	my ( $length, $downstream1, $downstream2, $seq1, $seq2, $downstream_offset, $highlight_start, $highlight_end ) =
	  @{$seq_data}{qw(length downstream1 downstream2 seq1 seq2 downstream_offset highlight_start highlight_end)};
	if (   $options->{'translate'}
		&& $self->{'config'}->{'emboss_path'}
		&& -e "$self->{'config'}->{'emboss_path'}/sixpack" )
	{
		my $temp       = BIGSdb::Utils::get_random();
		my $seq_infile = "$self->{'config'}->{'secure_tmp_dir'}/${temp}_infile.txt";
		my $outfile    = "$self->{'config'}->{'secure_tmp_dir'}/${temp}_sixpack.txt";
		my $outseq     = "$self->{'config'}->{'secure_tmp_dir'}/${temp}_outseq.txt";
		open( my $seq_fh, '>', $seq_infile ) || $logger->("Can't open $seq_infile for writing");
		say $seq_fh q(>seq);
		say $seq_fh ( $options->{'reverse'} ? $seq_ref->{'downstream'} : $seq_ref->{'upstream'} )
		  . qq($seq1$seq2$downstream1$downstream2);
		close $seq_fh;
		my @highlights;
		my $first_codon = substr( $seq_ref->{'seq'}, $orf - 1, 3 );
		my $end_codon_pos = $orf - 1 + 3 * int( ( length( $seq_ref->{'seq'} ) - $orf + 1 - 3 ) / 3 );
		my $last_codon = substr( $seq_ref->{'seq'}, $end_codon_pos, 3 );
		my $start_offset = ( any { $first_codon eq $_ } qw (ATG TTG GTG) ) ? $orf + 2 : 0;
		my $end_offset = ( any { $last_codon eq $_ } qw (TAA TAG TGA) ) ? ( $length - $end_codon_pos ) : 0;
		$end_offset = 0 if $end_offset > 3;

		#5' of start codon
		if ( $orf > 1 && $start_offset ) {
			push @highlights, ($highlight_start) . q(-) . ( $highlight_start + $orf - 2 ) . q( coding)
			  if ( $highlight_start + $orf - 2 ) > $highlight_start;
		}

		#start codon
		if ($start_offset) {
			push @highlights, ( $highlight_start + $orf - 1 ) . q(-) . ( $highlight_start + $orf + 1 ) . q( startcodon);
		}

		#Coding sequence between start and end codons
		push @highlights, ( $highlight_start + $start_offset ) . q(-) . ( $highlight_end - $end_offset ) . q( coding)
		  if $highlight_start
		  && $highlight_end
		  && ( ( $highlight_end - $end_offset ) > ( $highlight_start + $start_offset ) );

		#end codon
		if ($end_offset) {
			push @highlights, ( $highlight_end - 2 ) . qq(-$highlight_end stopcodon);
		}

		#3' of end codon
		local $" = q( );
		my $highlight;
		if (@highlights) {
			$highlight = qq(-highlight "@highlights");
		}
		if ( $highlight =~ /(\-highlight.*)/x ) {
			$highlight = $1;
		}
		system(
			    "$self->{'config'}->{'emboss_path'}/sixpack -sequence $seq_infile -outfile $outfile -outseq $outseq "
			  . "-width $self->{'prefs'}->{'alignwidth'} -noreverse -noname -html $highlight 2>/dev/null" );
		open( my $sixpack_fh, '<', $outfile ) || $logger->error("Can't open $outfile for reading");
		while ( my $line = <$sixpack_fh> ) {
			last if $line =~ /^\#\#\#\#\#\#\#\#/x;
			$line =~ s/<H3><\/H3>//x;
			$line =~ s/<PRE>//x;
			$line =~ s/<font\ color=(\w+?)>/<span class="$1">/gx;
			$line =~ s/<\/font>/<\/span>/gx;
			$line =~ s/\*/<span class="stopcodon">*<\/span>/gx;
			$sixpack .= $line;
		}
		close $sixpack_fh;
		unlink $seq_infile, $outfile, $outseq;
		$orf = $orf - 3 if $orf > 3;    #reverse reading frames
		foreach ( my $i = $orf - 1 ; $i < length( $seq_ref->{'seq'} ) - 3 ; $i += 3 ) {
			my $codon = substr( $seq_ref->{'seq'}, $i, 3 );
			if ( any { $codon eq $_ } qw (TAA TAG TGA) ) {
				push @internal_stop_codons,
				  $i + 1 +
				  ( $options->{'reverse'} ? length( $seq_ref->{'downstream'} ) : length( $seq_ref->{'upstream'} ) );
			}
		}
	}
	my $upstream =
	  ( BIGSdb::Utils::split_line( $options->{'reverse'} ? $seq_ref->{'downstream'} : $seq_ref->{'upstream'} ) ) // '';
	my $seq_display =
	    qq(<span class="flanking">$upstream</span>)
	  . ( $downstream_offset ? q() : q( ) )
	  . qq($seq1 )
	  . ( BIGSdb::Utils::split_line($seq2) // q() )
	  . ( $downstream_offset ? q() : q( ) )
	  . qq(<span class="flanking">$downstream1 )
	  . ( BIGSdb::Utils::split_line($downstream2) // q() )
	  . q(</span>);
	return { seq => $seq_display, sixpack => $sixpack, internal_stop => \@internal_stop_codons };
}

sub get_title {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $seqbin_id = $q->param('seqbin_id');
	my $start     = $q->param('start');
	my $end       = $q->param('end');
	my $title     = qq(Extracted sequence: Seqbin id#:$seqbin_id ($start-$end) - $self->{'system'}->{'description'});
	return $title;
}
1;
