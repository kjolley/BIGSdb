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
#
#
#is_float function (c) 2002-2008, David Wheeler
package BIGSdb::Utils;
use strict;
use warnings;
use POSIX qw(ceil);
use BIGSdb::BIGSException;
use Bio::SeqIO;
use Bio::SeqFeature::Generic;
use Excel::Writer::XLSX;
use autouse 'Time::Local'  => qw(timelocal);
use constant MAX_4BYTE_INT => 2147483647;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub reverse_complement {
	my ($seq) = @_;
	my $reversed = reverse $seq;
	$reversed =~ tr/GATCgatc/CTAGctag/;    #complement
	return $reversed;
}

sub is_valid_DNA {

	# checks if a valid DNA sequence
	my ( $seq, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $check_seq = ref $seq eq 'SCALAR' ? uc($$seq) : uc($seq);
	$check_seq =~ s/[\-\.\s]//g;

	#check it's a sequence - allow codes for two bases to
	#accommodate diploid sequence types
	if ( $options->{'allow_ambiguous'} ) {
		return $check_seq =~ /[^ACGTRYWSMKVHDBXN]/ ? 0 : 1;
	} elsif ( $options->{'diploid'} ) {
		return $check_seq =~ /[^ACGTRYWSMK]/ ? 0 : 1;
	} else {
		return $check_seq =~ /[^ACGT]/ ? 0 : 1;
	}
}

sub sequence_type {
	my ($seq) = @_;
	return 'DNA' if !$seq;
	my $AGTC_count = $seq =~ tr/[G|A|T|C|g|a|t|c|N|n]//;	
	return ( $AGTC_count / length $seq ) >= 0.9 ? 'DNA' : 'peptide';
}

sub truncate_seq {
	my ( $string_ref, $length ) = @_;
	$length = 20 if !$length;
	if ( length $$string_ref > $length ) {
		my $start = substr( $$string_ref, 0, int( $length / 2 ) );
		my $end = substr( $$string_ref, -int( $length / 2 ) );
		return "$start ... $end";
	} else {
		return $$string_ref;
	}
}

sub chop_seq {

	#chop sequence so that it is in a particular open reading frame
	my ( $seq, $orf ) = @_;
	return '' if !defined $seq;
	my $returnseq;
	if ( $orf > 3 ) {
		$orf = $orf - 3;
		$seq = reverse_complement($seq);
	}
	$returnseq = substr( $seq, $orf - 1 );

	#make sure sequence length is a multiple of 3
	while ( ( length $returnseq ) % 3 != 0 ) {
		chop $returnseq;
	}
	return $returnseq;
}

sub split_line {
	my $string = shift;
	return if !defined $string;
	my $seq;
	my $pos = 1;
	for ( my $i = 0 ; $i < length($string) ; $i++ ) {
		$seq .= substr $string, $i, 1;
		if ( $pos == 10 ) {
			$seq .= ' ';
			$pos = 0;
		}
		$pos++;
	}
	return $seq;
}

sub break_line {

	#Pass string either as a scalar or as a reference to a scalar.  It will be returned the same way.
	my ( $string, $length ) = @_;
	my $orig_string = ref $string eq 'SCALAR' ? $$string : $string;
	my $seq = '';
	my $s;
	$seq .= "$s\n" while $s = substr $orig_string, 0, $length, '';
	$seq =~ s/\n$//;
	return ref $string eq 'SCALAR' ? \$seq : $seq;
}

sub decimal_place {
	my ( $number, $decimals ) = @_;
	return substr( $number + ( "0." . "0" x $decimals . "5" ), 0, $decimals + length( int($number) ) + 1 );
}

sub is_date {

	#returns true if string is an acceptable date format
	my ($qry) = @_;
	return 1 if $qry eq 'today' || $qry eq 'yesterday';
	if ( $qry =~ /^(\d{4})-(\d{2})-(\d{2})$/ ) {
		my ( $y, $m, $d ) = ( $1, $2, $3 );
		eval { timelocal 0, 0, 0, $d, $m - 1, $y - 1900 };
		return $@ ? 0 : 1;
	}
	return 0;
}

sub is_bool {
	my ($qry) = @_;
	return 1
	  if ( lc($qry) eq 'true'
		|| lc($qry) eq 'false'
		|| $qry     eq '1'
		|| $qry     eq '0' );
	return 0;
}

sub is_int {
	my ( $N, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	return 0 if ( !defined $N || $N eq '' );
	my ($sign) = '^\s* [-+]? \s*';
	my ($int)  = '\d+ \s* $ ';
	if ( $N =~ /$sign $int/x ) {
		return if !$options->{'do_not_check_range'} && $N > MAX_4BYTE_INT;
		return 1;
	}
	return;
}

sub is_float {
	my ($value) = @_;

	#From Data::Types (c) 2002-2008 David Wheeler
	return unless defined $value && $value ne '';
	return unless $value =~ /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/;
	return 1;
}

sub get_random {
	return 'BIGSdb_' . $$ . '_' . (time) . '_' . int( rand(99999) );
}

sub pad_length {
	my ( $value, $length ) = @_;
	my $new_value;
	if ( length $value < $length ) {
		$new_value = ' ' x ( $length - length $value ) . $value;
	} else {
		return $value;
	}
	return $new_value;
}

sub round_up {
	my $n = shift;
	return ( ( $n == int($n) ) ? $n : int( $n + 1 ) );
}

sub read_fasta {
	my $data_ref = shift;
	my @lines = split /\n/, $$data_ref;
	my %seqs;
	my $header;
	foreach (@lines) {
		$_ =~ s/\r//g;
		if ( $_ =~ /^>/ ) {
			$header = substr( $_, 1 );
			next;
		}
		throw BIGSdb::DataException("Not valid FASTA format.") if !$header;
		my $temp_seq = uc($_);
		$temp_seq =~ s/\s//g;
		throw BIGSdb::DataException("Not valid DNA - $header") if $temp_seq =~ /[^GATCBDHVRYKMSWN]/;
		$seqs{$header} .= $temp_seq;
	}
	return \%seqs;
}

sub histogram {
	my ( $width, $list ) = @_;
	my %histogram;
	foreach (@$list) {
		$histogram{ ceil( ( $_ + 1 ) / $width ) - 1 }++;
	}
	my ( $max, $min ) = ( 0, 0 );
	foreach ( keys %histogram ) {
		$max = $_ if $_ > $max;
		$min = $_ if $_ < $min || !defined($min);
	}
	return ( \%histogram, $min, $max );
}

sub stats {

	#Return simple stats for values in array ref
	my ($list_ref) = @_;
	return if ref $list_ref ne 'ARRAY';
	my $stats;
	$stats->{'count'} = @$list_ref;
	$stats->{'min'}   = $list_ref->[0];
	$stats->{'max'}   = $list_ref->[0];
	foreach (@$list_ref) {
		$stats->{'sum'} += $_;
		$stats->{'max'} = $_ if $stats->{'max'} < $_;
		$stats->{'min'} = $_ if $stats->{'min'} > $_;
	}
	$stats->{'mean'} = $stats->{'sum'} / $stats->{'count'};
	foreach (@$list_ref) {
		$stats->{'sum2'} += ( $_ - $stats->{'mean'} )**2;
	}
	$stats->{'std'} = sqrt( $stats->{'sum2'} / ( ( $stats->{'count'} - 1 ) || 1 ) );
	return $stats;
}

sub round_to_nearest {
	my ( $number, $nearest ) = @_;
	return ceil( int($number) / $nearest ) * $nearest;
}

sub append {
	my ( $source_file, $destination_file, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	open( my $fh1, '<',  $source_file )      || $logger->error("Can't open $source_file for reading");
	open( my $fh,  '>>', $destination_file ) || $logger->error("Can't open $destination_file for writing");
	print $fh "\n"      if $options->{'blank_before'};
	print $fh "<pre>\n" if $options->{'preformatted'};
	print $fh $_ while <$fh1>;
	print $fh "</pre>\n" if $options->{'preformatted'};
	print $fh "\n"       if $options->{'blank_after'};
	close $fh;
	close $fh1;
	return;
}

sub xmfa2fasta {
	my ( $xmfa_file, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my %seq;
	my @ids;
	my $temp_seq   = '';
	my $current_id = '';
	open( my $xmfa_fh, '<', $xmfa_file ) || throw BIGSdb::CannotOpenFileException("Can't open $xmfa_file for reading");
	my %labels;

	while ( my $line = <$xmfa_fh> ) {
		next if $line =~ /^=/;
		if ( $line =~ /^>\s*([\d\w\s\|\-\\\/\.\(\),#]+):/ ) {
			$seq{$current_id} .= $temp_seq;
			if ( $options->{'integer_ids'} ) {
				my $extracted_id = $1;
				if ( $extracted_id =~ /^(\d+)/ ) {
					$current_id = $1;
					$labels{$current_id} = $extracted_id
					  if !defined $labels{$current_id} || length $extracted_id > length $labels{$current_id};
				} else {
					$current_id = $extracted_id;
				}
			} else {
				$current_id = $1;
			}
			if ( !$seq{$current_id} ) {
				push @ids, $current_id;
			}
			$temp_seq = '';
		} else {
			$line =~ s/[\r\n]//g;
			$temp_seq .= $line;
		}
	}
	$seq{$current_id} .= $temp_seq;
	close $xmfa_fh;
	( my $fasta_file = $xmfa_file ) =~ s/xmfa$/fas/;
	open( my $fasta_fh, '>', $fasta_file ) || throw BIGSdb::CannotOpenFileException("Can't open $fasta_file for writing");
	foreach my $id (@ids) {
		my $label = $labels{$id} // $id;
		say $fasta_fh ">$label";
		my $seq_ref = break_line( \$seq{$id}, 60 );
		say $fasta_fh $$seq_ref;
	}
	return $fasta_file;
}

sub text2excel {
	my ( $text_file, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $excel_file;
	if ( $options->{'stdout'} ) {
		binmode(STDOUT);
		$excel_file = \*STDOUT;
	} else {
		( $excel_file = $text_file ) =~ s/txt$/xlsx/;
	}
	my $workbook = Excel::Writer::XLSX->new($excel_file);
	$workbook->set_tempdir( $options->{'tmp_dir'} ) if $options->{'tmp_dir'};
	$workbook->set_optimization;
	if ( !defined $workbook ) {
		$logger->error("Can't create Excel file $excel_file");
		return;
	}
	my $worksheet_name = $options->{'worksheet'} // 'output';
	my $worksheet      = $workbook->add_worksheet($worksheet_name);
	my $header_format  = $workbook->add_format;
	$header_format->set_align('center');
	$header_format->set_bold;
	my $cell_format = $workbook->add_format;
	$cell_format->set_align('center');
	open( my $text_fh, '<:encoding(utf8)', $text_file ) || throw BIGSdb::CannotOpenFileException("Can't open $text_file for reading");
	my ( $row, $col ) = ( 0, 0 );
	my %widths;

	while ( my $line = <$text_fh> ) {
		$line =~ s/[\r\n]/ /g;
		my $format = !$options->{'no_header'} && $row == 0 ? $header_format : $cell_format;
		my @values = split /\t/, $line;
		foreach my $value (@values) {
			$worksheet->write( $row, $col, $value, $format );
			$widths{$col} = length $value if length $value > ( $widths{$col} // 0 );
			$col++;
		}
		$col = 0;
		$row++;
	}
	foreach my $col ( keys %widths ) {
		my $width = my $value_width = int( 0.9 * ( $widths{$col} ) + 2 );
		if ( $options->{'max_width'} ) {
			$width = $options->{'max_width'} if $width > $options->{'max_width'};
		}
		$worksheet->set_column( $col, $col, $width );
	}
	$worksheet->freeze_panes( 1, 0 ) if !$options->{'no_header'};
	close $text_fh;
	return $excel_file;
}

sub fasta2genbank {
	my ($fasta_file) = @_;
	( my $genbank_file = $fasta_file ) =~ s/\.(fas|fasta)$/.gb/;
	my $in  = Bio::SeqIO->new( -file => $fasta_file,      -format => 'fasta' );
	my $out = Bio::SeqIO->new( -file => ">$genbank_file", -format => 'genbank' );
	my $start      = 1;
	my $concat_seq = '';
	my @features;
	while ( my $seq_obj = $in->next_seq ) {
		my $id = $seq_obj->primary_id;
		my $seq = ( $seq_obj->primary_seq->seq =~ /(.*)/ ) ? $1 : undef;    #untaint
		$seq =~ s/-//g;
		$concat_seq .= $seq;
		my $length = length($seq);
		my $end    = $start + $length - 1;
		my $feat   = Bio::SeqFeature::Generic->new(
			-start       => $start,
			-end         => $end,
			-strand      => 1,
			-primary_tag => 'CDS',
			-tag         => { gene => $id, product => '' }
		);
		push @features, $feat;
		$start += $length;
	}
	my $out_seq_obj = Bio::Seq->new( -seq => $concat_seq, -id => 'FROM_FASTA' );
	$out_seq_obj->add_SeqFeature($_) foreach (@features);
	$out->write_seq($out_seq_obj);
	return $genbank_file;
}

sub get_heatmap_colour_style {

	#Heatmap colour given value and max value
	my ( $value, $max_value, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $normalised = $max_value ? ( $value / $max_value ) : 0;    #Don't divide by zero.
	my $colour = sprintf( "#%02x%02x%02x", $normalised * 201 + 54, abs( 0.5 - $normalised ) * 201 + 54, ( 1 - $normalised ) * 201 + 54 );
	if ( $options->{'excel'} ) {
		return { bg_color => $colour, color => 'white', align => 'center', border => 1, border_color => 'white' };
	}
	return "background:$colour; color:white";
}

sub get_largest_string_length {
	my ($array_ref) = @_;
	my $length = 0;
	foreach (@$array_ref) {
		my $this_length = length $_;
		$length = $this_length if $this_length > $length;
	}
	return $length;
}

sub get_N_stats {

	#Array of lengths must be in descending length order.
	my ( $total_length, $contig_length_arrayref ) = @_;
	my $n50_target = 0.5 * $total_length;
	my $n90_target = 0.1 * $total_length;
	my $n95_target = 0.05 * $total_length;
	my $stats;
	my $running_total = $total_length;
	foreach my $length (@$contig_length_arrayref) {
		$running_total -= $length;
		$stats->{'N50'} = $length if !defined $stats->{'N50'} && $running_total <= $n50_target;
		$stats->{'N90'} = $length if !defined $stats->{'N90'} && $running_total <= $n90_target;
		$stats->{'N95'} = $length if !defined $stats->{'N95'} && $running_total <= $n95_target;
	}
	return $stats;
}

sub escape_html {
	my ($string) = @_;
	return if !defined $string;
	$string =~ s/"/\&quot;/g;
	$string =~ s/</\&lt;/g;
	$string =~ s/>/\&gt;/g;
	return $string;
}

sub commify {

	#Put commas in numbers
	#Perl Cookbook 2.16
	my ($text) = @_;
	$text = reverse $text;
	$text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
	return scalar reverse $text;
}

sub random_string {
	my ( $length, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my @chars = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9 );
	push @chars, qw(! @ $ % ^ & * \( \)_+ ~) if $options->{'extended_chars'};
	my $string;
	for ( 1 .. $length ) {
		$string .= $chars[ int( rand($#chars) ) ];
	}
	return $string;
}
1;
