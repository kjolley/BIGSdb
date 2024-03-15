#Written by Keith Jolley
#Copyright (c) 2010-2024, University of Oxford
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
package BIGSdb::ExtractedSequencePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
use BIGSdb::Constants qw(FLANKING DEFAULT_CODON_TABLE);
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
	my $locus        = $q->param('locus');
	my $isolate_id = $self->{'datastore'}->run_query( 'SELECT isolate_id FROM sequence_bin WHERE id=?', $seqbin_id );
	my ( $introns, $intron_length ) = $self->get_introns;
	$self->update_prefs if $q->param('reload');

	if ( !BIGSdb::Utils::is_int($seqbin_id) ) {
		say q(<h1>Extracted sequence</h1>);
		$self->print_bad_status( { message => q(Sequence bin id must be an integer.), navbar => 1 } );
		return;
	}
	if ( !BIGSdb::Utils::is_int($start) || !BIGSdb::Utils::is_int($end) ) {
		say q(<h1>Extracted sequence</h1>);
		$self->print_bad_status( { message => q(Start and end values must be integers.), navbar => 1 } );
		return;
	}
	if ( $orf && ( !BIGSdb::Utils::is_int($orf) || $orf < 1 || $orf > 6 ) ) {
		say q(<h1>Extracted sequence</h1>);
		$self->print_bad_status( { message => q(Orf must be an integer between 1-6.), navbar => 1 } );
		return;
	}
	my $exists = $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM sequence_bin WHERE id=?)', $seqbin_id );
	if ( !$exists ) {
		say q(<h1>Extracted sequence</h1>);
		$self->print_bad_status(
			{ message => qq(There is no sequence with sequence bin id#$seqbin_id.), navbar => 1 } );
		return;
	}
	say qq(<h1>Extracted sequence: Seqbin id#:$seqbin_id ($start-$end)</h1>);
	my $length      = abs( $end - $start + 1 );
	my $method      = $self->{'datastore'}->run_query( 'SELECT method FROM sequence_bin WHERE id=?', $seqbin_id );
	my $flanking    = $q->param('flanking') // $self->{'prefs'}->{'flanking'};
	my $orientation = $reverse ? '&larr;' : '&rarr;';
	say q(<div class="box" id="resultspanel"><div style="float:left">);
	say q(<h2>Sequence position</h2>);
	say q(<dl class="data">);
	say qq(<dt>sequence bin id</dt><dd>$seqbin_id</dd>);
	say qq(<dt>sequence method</dt><dd>$method</dd>) if $method;
	say qq(<dt>start</dt><dd>$start</dd>);
	say qq(<dt>end</dt><dd>$end</dd>);
	say qq(<dt>length</dt><dd>$length</dd>);

	if ($intron_length) {
		my $exon_length = $length - $intron_length;
		say qq(<dt>exon length</dt><dd>$exon_length</dd>);
	}
	say qq(<dt>orientation</dt><dd><span style="font-size:2em">$orientation</span></dd>);
	say q(</dl>);
	say q(</div>);
	say $self->get_option_fieldset;
	say q(<div style="clear:both"></div>);
	my $seq_features = $self->get_seq_features(
		{
			seqbin_id => $seqbin_id,
			reverse   => $reverse,
			start     => $start,
			end       => $end,
			flanking  => $flanking,
			introns   => $introns
		}
	);
	say q(<h2>Sequence</h2>);
	say q(<div class="resize_seq" style="padding-left:4em;max-width:110ch">);
	say $self->format_sequence_features($seq_features);
	say q(</div>);

	if (@$introns) {
		say q(<p style="padding-left:5em;margin-top:1em">Key: <span class="flanking">Flanking</span>; )
		  . q(<span class="exon">Exon</span>; <span class="intron">Intron</span></p>);
		say q(<h2>Spliced sequence (exons only)</h2>);
		say q(<div class="resize_seq" style="padding-left:4em;max-width:110ch">);
		say $self->format_sequence_features( $seq_features, { spliced => 1 } );
		say q(</div>);
	}
	if ($translate) {
		say q(<h2>Translation</h2>);
		my $codon_table = $self->{'datastore'}->get_codon_table($isolate_id);
		if ( $codon_table > 23 ) {
			say "<p>Set codon table ($codon_table) is not supported. Using default.</p>";
			$codon_table = DEFAULT_CODON_TABLE;    #EMBOSS doesn't support later codon tables.
		}
		my $tables = Bio::Tools::CodonTable->tables;
		say qq(<p>Codon table: $codon_table - $tables->{$codon_table}<p>);
		my $stops = $self->find_internal_stops( $seq_features, 1, { isolate_id => $isolate_id } );
		if (@$stops) {
			local $" = ', ';
			my $plural = @$stops == 1 ? q() : q(s);
			say qq(<span class="highlight">Internal stop codon$plural at position$plural: @$stops )
			  . q((numbering includes upstream flanking sequence).</span>);
		}
		say q(<div class="scrollable"><pre class="sixpack">);
		say $self->get_sixpack_display( $seq_features, undef, { locus => $locus, isolate_id => $isolate_id } );
		say q(</pre></div>);
	}
	say q(</div>);
	return;
}

sub get_introns {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	return [] if !$q->param('introns');
	my @ranges       = split /,/x, $q->param('introns');
	my $introns      = [];
	my $total_length = 0;
	foreach my $range (@ranges) {
		if ( $range =~ /^(\d+)\-(\d+)$/x ) {
			my $length = abs( $2 - $1 );
			push @$introns, { start => $1, end => $2, length => $length };
			$total_length += $length + 1;
		}
	}
	return ( $introns, $total_length );
}

sub get_seq_features {
	my ( $self, $args ) = @_;
	my ( $seqbin_id, $reverse, $start, $end, $flanking, $introns ) =
	  @{$args}{qw(seqbin_id reverse start end flanking introns)};
	$introns //= [];
	my $contig          = $self->{'contigManager'}->get_contig($seqbin_id);
	my $contig_length   = length $$contig;
	my $features        = [];
	my $up_flank_length = $start - $flanking < 0 ? $start - 1 : $flanking;
	if ($up_flank_length) {
		my $up_flank_seq = substr( $$contig, $start - 1 - $up_flank_length, $up_flank_length );
		push @$features, { feature => 'flanking', sequence => $up_flank_seq };
	}
	if (@$introns) {
		my $start_pos = $start - 1;
		foreach my $intron (@$introns) {
			my $exon_seq = substr( $$contig, $start_pos, ( $intron->{'start'} - $start_pos - 1 ) );
			push @$features, { feature => 'exon', sequence => $exon_seq };
			my $intron_seq = substr( $$contig, $intron->{'start'} - 1, ( $intron->{'end'} - $intron->{'start'} + 1 ) );
			push @$features, { feature => 'intron', sequence => $intron_seq };
			$start_pos = $intron->{'end'};
		}
		my $exon_seq = substr( $$contig, $start_pos, ( $end - $start_pos ) );
		push @$features, { feature => 'exon', sequence => $exon_seq };
	} else {
		my $main_seq = substr( $$contig, $start - 1, ( $end - $start + 1 ) );
		push @$features, { feature => 'allele_seq', sequence => $main_seq };
	}
	my $down_flank_length = $contig_length - $end > $flanking ? $flanking : $contig_length - $end;
	if ($down_flank_length) {
		my $down_flank_seq = substr( $$contig, $end, $down_flank_length );
		push @$features, { feature => 'flanking', sequence => $down_flank_seq };
	}
	return $features if !$reverse;

	#Reverse-complement features
	my $reverse_features = [];
	foreach my $feature ( reverse @$features ) {
		my $seq = BIGSdb::Utils::reverse_complement( $feature->{'sequence'} );
		push @$reverse_features, { feature => $feature->{'feature'}, sequence => $seq };
	}
	return $reverse_features;
}

sub format_sequence_features {
	my ( $self, $features, $options ) = @_;
	my $buffer        = q();
	my $offset        = 0;
	my $length_so_far = 0;
	foreach my $feature (@$features) {
		next if $feature->{'feature'} ne 'exon' && $options->{'spliced'};
		my $seq = BIGSdb::Utils::split_line( $feature->{'sequence'}, $offset );
		$buffer .= qq(<span class="$feature->{'feature'}">$seq</span>);
		$length_so_far += length( $feature->{'sequence'} );
		$offset = $length_so_far % 10;
	}
	return $buffer;
}

sub find_internal_stops {
	my ( $self, $features, $orf, $options ) = @_;
	$orf //= 1;
	my $stop_codons = $self->{'datastore'}->get_stop_codons($options);
	my %stop_codon  = map { $_ => 1 } @$stop_codons;
	my $exon_seq    = $self->_get_exons_seqs($features);
	my $mapped_pos  = $self->_get_mapped_positions($features);
	my $stops       = [];
	for ( my $i = 0 + $orf - 1 ; $i < length $exon_seq ; $i += 3 ) {
		my $codon = substr( $exon_seq, $i, 3 );
		if ( $stop_codon{$codon} && $i < length($exon_seq) - 3 ) {
			push @$stops, $mapped_pos->{ $i + 1 };
		}
	}
	return $stops;
}

sub _get_exons_seqs {
	my ( $self, $features ) = @_;
	my $seq;
	foreach my $feature (@$features) {
		if ( $feature->{'feature'} eq 'allele_seq' || $feature->{'feature'} eq 'exon' ) {
			$seq .= $feature->{'sequence'};
		}
	}
	return $seq;
}

sub _get_feature_seqs {
	my ( $self, $features ) = @_;
	my $seq;
	foreach my $feature (@$features) {
		$seq .= $feature->{'sequence'};
	}
	return $seq;
}

sub _get_mapped_positions {
	my ( $self, $features ) = @_;
	my $mapped = {};
	my $total_pos;
	my $mapped_pos;
	foreach my $feature (@$features) {
		my @nucs = split //, $feature->{'sequence'};
		foreach my $nuc (@nucs) {
			$total_pos++;
			if ( $feature->{'feature'} eq 'allele_seq' || $feature->{'feature'} eq 'exon' ) {
				$mapped_pos++;
				$mapped->{$mapped_pos} = $total_pos;
			}
		}
	}
	return $mapped;
}

sub get_option_fieldset {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $buffer = q(<fieldset style="float:right"><legend>Options</legend>);
	$buffer .= $q->start_form;
	$buffer .= q(<ul></li>);
	$buffer .= q(<label for="flanking">Flanking sequence length: </label>);
	$buffer .= $q->popup_menu( -name => 'flanking', -values => [FLANKING], -default => $self->{'prefs'}->{'flanking'} );
	$buffer .= q(</li></ul>);
	$buffer .= $q->submit(
		-name  => 'reload',
		-label => 'Reload',
		-class => 'small_submit',
		-style => 'float:right;margin-top:0.5em'
	);
	$buffer .= $q->hidden($_) foreach qw(db page seqbin_id start end reverse translate orf introns id locus set_id);
	$buffer .= $q->end_form;
	$buffer .= q(</fieldset>);
	return $buffer;
}

sub update_prefs {
	my ($self) = @_;
	my $guid = $self->get_guid;
	return if !$guid;
	my $q = $self->{'cgi'};
	my %allowed_flanking = map { $_ => 1 } FLANKING;
	if ( $allowed_flanking{ $q->param('flanking') } ) {
		$self->{'prefstore'}->set_general( $guid, $self->{'system'}->{'db'}, 'flanking', scalar $q->param('flanking') );
	}
	return;
}

sub get_sixpack_display {
	my ( $self, $seq_features, $orf, $options ) = @_;
	$orf //= 1;
	my $buffer = q();
	return $buffer if !$self->{'config'}->{'emboss_path'} || !-e "$self->{'config'}->{'emboss_path'}/sixpack";
	my $temp       = BIGSdb::Utils::get_random();
	my $seq_infile = "$self->{'config'}->{'secure_tmp_dir'}/${temp}_infile.txt";
	my $outfile    = "$self->{'config'}->{'secure_tmp_dir'}/${temp}_sixpack.txt";
	my $outseq     = "$self->{'config'}->{'secure_tmp_dir'}/${temp}_outseq.txt";
	my $seq        = $self->_get_feature_seqs($seq_features);
	open( my $fh, '>', $seq_infile ) || $logger->("Cannot open $seq_infile for writing");
	say $fh q(>seq);
	say $fh $seq;
	close $fh;
	my @highlights;
	my $mapped       = $self->_get_mapped_positions($seq_features);
	my $pos          = 0;
	my $start_codons = $self->{'datastore'}->get_start_codons( { locus => $options->{'locus'} } );
	my %start_codon  = map { $_ => 1 } @$start_codons;
	my $stop_codons  = $self->{'datastore'}->get_stop_codons( { isolate_id => $options->{'isolate_id'} } );
	my %stop_codon   = map { $_ => 1 } @$stop_codons;
	my $exon_count   = $self->_get_exon_count($seq_features);
	my $codon_table  = $options->{'codon_table'}
	  // $self->{'datastore'}->get_codon_table( $options->{'isolate_id'} );

	if ( $codon_table > 23 ) {
		$codon_table = DEFAULT_CODON_TABLE;
	}
	my $exon_number    = 0;
	my $exon_length    = 0;
	my $feature_number = 0;
	my $stop_highlight = q();
	foreach my $feature (@$seq_features) {
		$feature_number++;
		if ( $feature->{'feature'} ne 'allele_seq' && $feature->{'feature'} ne 'exon' ) {
			$pos += length( $feature->{'sequence'} );
			next;
		}
		my $start_offset = 0;
		$exon_number++;
		$exon_length += length( $feature->{'sequence'} );
		if ( $exon_number == 1 && $start_codon{ uc substr( $feature->{'sequence'}, 0 + $orf - 1, 3 ) } ) {
			push @highlights, ( $mapped->{1} + $orf - 1 ) . q(-) . ( $mapped->{1} + $orf + 1 ) . q( startcodon);
			$start_offset = 3;
		}
		my $end_offset = 0;
		if (   $exon_number == $exon_count
			&& $exon_length % 3 == 0
			&& $stop_codon{ uc substr( $feature->{'sequence'}, -3 + $orf - 1 ) } )
		{
			$stop_highlight =
			    ( $mapped->{ $exon_length - 2 + $orf - 1 } ) . q(-)
			  . ( $mapped->{ $exon_length - 2 + $orf + 1 } )
			  . q( stopcodon);
			$end_offset = 3;
		}

		#Coding sequence between start and end codons
		my $end = $pos + length( $feature->{'sequence'} );
		push @highlights, ( $pos + $start_offset + 1 ) . q(-) . ( $end - $end_offset ) . q( coding);
		$pos += length( $feature->{'sequence'} );
	}
	push @highlights, $stop_highlight if $stop_highlight;
	local $" = q( );
	my $highlight;
	if (@highlights) {
		$highlight = qq(-highlight "@highlights");
	}
	if ( $highlight =~ /(\-highlight.*)/x ) {
		$highlight = $1;
	}
	system( "$self->{'config'}->{'emboss_path'}/sixpack -sequence $seq_infile -outfile $outfile -outseq $outseq "
		  . "-width $self->{'prefs'}->{'alignwidth'} -table $codon_table -noreverse -noname -html "
		  . "$highlight 2>/dev/null" );
	open( my $sixpack_fh, '<', $outfile ) || $logger->error("Cannot open $outfile for reading");
	while ( my $line = <$sixpack_fh> ) {
		last if $line =~ /^\#\#\#\#\#\#\#\#/x;
		$line =~ s/<H3><\/H3>//x;
		$line =~ s/<PRE>//x;
		$line =~ s/<font\ color=(\w+?)>/<span class="$1">/gx;
		$line =~ s/<\/font>/<\/span>/gx;
		$line =~ s/\*/<span class="stopcodon">*<\/span>/gx;
		$buffer .= $line;
	}
	close $sixpack_fh;
	unlink $seq_infile, $outfile, $outseq;
	return $buffer;
}

sub _get_exon_count {
	my ( $self, $seq_features ) = @_;
	my $exons = 0;
	foreach my $feature (@$seq_features) {
		if ( $feature->{'feature'} eq 'allele_seq' || $feature->{'feature'} eq 'exon' ) {
			$exons++;
		}
	}
	return $exons;
}

sub get_title {
	my ( $self, $options ) = @_;
	my $q = $self->{'cgi'};
	return q(Extracted sequence) if $options->{'breadcrumb'};
	my $seqbin_id = $q->param('seqbin_id');
	my $start     = $q->param('start');
	my $end       = $q->param('end');
	my $title     = qq(Extracted sequence: Seqbin id#:$seqbin_id ($start-$end) - $self->{'system'}->{'description'});
	return $title;
}

sub initiate {
	my ($self) = @_;
	$self->{'jQuery'} = 1;
	$self->set_level1_breadcrumbs;
	return;
}
1;
