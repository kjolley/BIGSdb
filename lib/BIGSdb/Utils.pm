#Written by Keith Jolley
#Copyright (c) 2010-2017, University of Oxford
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
use List::MoreUtils qw(any none);
use Bio::SeqIO;
use Bio::SeqFeature::Generic;
use Excel::Writer::XLSX;
use List::MoreUtils qw(uniq);
use autouse 'Time::Local'  => qw(timelocal);
use constant MAX_4BYTE_INT => 2147483647;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub reverse_complement {
	my ($seq) = @_;
	my $reversed = reverse $seq;
	$reversed =~ tr/GATCgatc/CTAGctag/;
	return $reversed;
}

sub is_valid_DNA {
	my ( $seq, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $check_seq = ref $seq eq 'SCALAR' ? uc($$seq) : uc($seq);
	$check_seq =~ s/[\-\.\s]//gx;

	#check it's a sequence - allow codes for two bases to
	#accommodate diploid sequence types
	if ( $options->{'allow_ambiguous'} ) {
		return $check_seq =~ /[^ACGTRYWSMKVHDBXN]/x ? 0 : 1;
	} elsif ( $options->{'diploid'} ) {
		return $check_seq =~ /[^ACGTRYWSMK]/x ? 0 : 1;
	} else {
		return $check_seq =~ /[^ACGT]/x ? 0 : 1;
	}
}

sub is_valid_peptide {
	my ($seq) = @_;
	my $check_seq = ref $seq eq 'SCALAR' ? uc($$seq) : uc($seq);
	$check_seq =~ s/[\-\.\s]//gx;
	return $check_seq =~ /[^GALMFWKQESPVICYHRNDT]/x ? 0 : 1;
}

sub is_complete_cds {
	my ($seq) = @_;
	my $check_seq = ref $seq eq 'SCALAR' ? uc($$seq) : uc($seq);
	$check_seq =~ s/[\-\.\s]//gx;
	my $first_codon = substr( $check_seq, 0, 3 );
	if ( none { $first_codon eq $_ } qw (ATG GTG TTG) ) {
		return { cds => 0, err => 'not a complete CDS - no start codon.' };
	}
	my $end_codon = substr( $check_seq, -3 );
	if ( none { $end_codon eq $_ } qw (TAA TGA TAG) ) {
		return { cds => 0, err => 'not a complete CDS - no stop codon.' };
	}
	my $multiple_of_3 = ( length($check_seq) / 3 ) == int( length($check_seq) / 3 ) ? 1 : 0;
	if ( !$multiple_of_3 ) {
		return { cds => 0, err => 'not a complete CDS - length not a multiple of 3.' };
	}
	my $internal_stop;
	for ( my $pos = 0 ; $pos < length($check_seq) - 3 ; $pos += 3 ) {
		my $codon = substr( $check_seq, $pos, 3 );
		if ( any { $codon eq $_ } qw (TAA TGA TAG) ) {
			$internal_stop = 1;
		}
	}
	if ($internal_stop) {
		return { cds => 0, err => 'not a complete CDS - internal stop codon.' };
	}
	return { cds => 1 };
}

sub sequence_type {
	my ($sequence) = @_;
	my $seq = ref $sequence ? $$sequence : $sequence;
	return 'DNA' if !$seq;
	my $AGTC_count = $seq =~ tr/[G|A|T|C|g|a|t|c|N|n]//;
	return ( $AGTC_count / length $seq ) >= 0.8 ? 'DNA' : 'peptide';
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

#chop sequence so that it is in a particular open reading frame
sub chop_seq {
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

#Pass string either as a scalar or as a reference to a scalar.  It will be returned the same way.
sub break_line {
	my ( $string, $length ) = @_;
	my $orig_string = ref $string eq 'SCALAR' ? $$string : $string;
	$orig_string //= q();
	my @lines = $orig_string =~ /(.{1,$length})/gx;
	my $seq = join( "\n", @lines );
	$seq =~ s/\n$//x;
	return ref $string eq 'SCALAR' ? \$seq : $seq;
}

sub decimal_place {
	my ( $number, $decimals ) = @_;
	return substr( $number + ( '0.' . '0' x $decimals . '5' ), 0, $decimals + length( int($number) ) + 1 );
}

#returns true if string is an acceptable date format
sub is_date {
	my ($qry) = @_;
	return if ( !defined $qry || $qry eq '' );
	return 1 if $qry eq 'today' || $qry eq 'yesterday';
	if ( $qry =~ /^(\d{4})-(\d{2})-(\d{2})$/x ) {
		my ( $y, $m, $d ) = ( $1, $2, $3 );
		eval { timelocal 0, 0, 0, $d, $m - 1, $y - 1900 };
		return $@ ? 0 : 1;
	}
	return;
}

sub is_bool {
	my ($qry) = @_;
	return 1
	  if ( lc($qry) eq 'true'
		|| lc($qry) eq 'false'
		|| $qry eq '1'
		|| $qry eq '0' );
	return;
}

sub is_int {
	my ( $N, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	return if ( !defined $N || $N eq '' );
	return if $N =~ /[\x{ff10}-\x{ff19}]/x;    #Reject Unicode full width form
	my ($sign) = '^\s* [-+]? \s*';
	my ($int)  = '\d+ \s* $ ';
	if ( $N =~ /$sign $int/x ) {
		return if !$options->{'do_not_check_range'} && $N > MAX_4BYTE_INT;
		return 1;
	}
	return;
}

#Modified from Data::Types (c) 2002-2008 David Wheeler
sub is_float {
	my ($value) = @_;
	return if !defined $value;
	## no critic (ProhibitUnusedCapture)
	return if $value !~ /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/x;
	return 1;
}

sub get_random {
	return 'BIGSdb_' . sprintf( '%06d', $$ ) . '_' . (time) . '_' . sprintf( '%05d', int( rand(99999) ) );
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
	my ( $data_ref, $options ) = @_;
	my @lines = split /\r?\n/x, $$data_ref;
	my %seqs;
	my $header;
	foreach my $line (@lines) {
		if ( substr( $line, 0, 1 ) eq '>' ) {
			$header = substr( $line, 1 );
			next;
		}
		throw BIGSdb::DataException('Not valid FASTA format.') if !$header;
		my $temp_seq = uc($line);
		$seqs{$header} .= $temp_seq;
	}
	foreach my $id ( keys %seqs ) {
		$seqs{$id} =~ s/\s//gx;
		if ( !$options->{'allow_peptide'} ) {
			throw BIGSdb::DataException("Not valid DNA - $id") if $seqs{$id} =~ /[^GATCBDHVRYKMSWN]/x;
		}
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

#Return simple stats for values in array ref
sub stats {
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
	open( my $fh1, '<', $source_file ) || $logger->error("Can't open $source_file for reading");
	open( my $fh, '>>', $destination_file ) || $logger->error("Can't open $destination_file for writing");
	print $fh "\n"      if $options->{'blank_before'};
	print $fh "<pre>\n" if $options->{'preformatted'};
	while ( my $line = <$fh1> ) {
		print $fh $line;
	}
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
		next if $line =~ /^=/x;
		if ( $line =~ /^>\s*(.+):/x ) {
			$seq{$current_id} .= $temp_seq;
			if ( $options->{'integer_ids'} ) {
				my $extracted_id = $1;
				if ( $extracted_id =~ /^(\d+)/x ) {
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
			$line =~ s/[\r\n]//gx;
			$temp_seq .= $line;
		}
	}
	$seq{$current_id} .= $temp_seq;
	close $xmfa_fh;
	( my $fasta_file = $xmfa_file ) =~ s/xmfa$/fas/x;
	open( my $fasta_fh, '>', $fasta_file )
	  || throw BIGSdb::CannotOpenFileException("Can't open $fasta_file for writing");
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
	my ( %text_fields, %text_cols );
	if ( $options->{'text_fields'} ) {
		%text_fields = map { $_ => 1 } split /,/x, $options->{'text_fields'};
	}

	#Always use text format for likely record names
	$text_fields{$_} = 1 foreach qw(isolate strain sample);
	my $excel_file;
	if ( $options->{'stdout'} ) {
		binmode(STDOUT);
		$excel_file = \*STDOUT;
	} else {
		( $excel_file = $text_file ) =~ s/txt$/xlsx/x;
	}
	my $workbook = Excel::Writer::XLSX->new($excel_file);
	my $text_format = $workbook->add_format( num_format => '@' );
	$text_format->set_align('center');
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
	open( my $text_fh, '<:encoding(utf8)', $text_file )
	  || throw BIGSdb::CannotOpenFileException("Can't open $text_file for reading");
	my ( $row, $col ) = ( 0, 0 );
	my %widths;
	my $first_line = 1;

	while ( my $line = <$text_fh> ) {
		$line =~ s/\r?\n$//x;      #Remove terminal newline
		$line =~ s/[\r\n]/ /gx;    #Replace internal newlines with spaces.
		my $format = !$options->{'no_header'} && $row == 0 ? $header_format : $cell_format;
		my @values = split /\t/x, $line;
		foreach my $value (@values) {
			if ( !$options->{'no_header'} && $first_line && $text_fields{$value} ) {
				$text_cols{$col} = 1;
			}
			if ( !$first_line && $text_cols{$col} ) {
				$worksheet->write_string( $row, $col, $value, $text_format );
			} else {
				$worksheet->write( $row, $col, $value, $format );
			}
			$widths{$col} = length $value if length $value > ( $widths{$col} // 0 );
			$col++;
		}
		$col = 0;
		$row++;
		$first_line = 0;
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
	( my $genbank_file = $fasta_file ) =~ s/\.(fas|fasta)$/.gb/x;
	my $in  = Bio::SeqIO->new( -file => $fasta_file,      -format => 'fasta' );
	my $out = Bio::SeqIO->new( -file => ">$genbank_file", -format => 'genbank' );
	my $start      = 1;
	my $concat_seq = '';
	my @features;
	while ( my $seq_obj = $in->next_seq ) {
		my $id = $seq_obj->primary_id;
		my $seq = ( $seq_obj->primary_seq->seq =~ /(.*)/x ) ? $1 : undef;    #untaint
		$seq =~ s/-//gx;
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

#Heatmap colour given value and max value
sub get_heatmap_colour_style {
	my ( $value, $max_value, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $normalised = $max_value ? ( $value / $max_value ) : 0;    #Don't divide by zero.
	my $colour = sprintf( '#%02x%02x%02x',
		$normalised * 201 + 54,
		abs( 0.5 - $normalised ) * 201 + 54,
		( 1 - $normalised ) * 201 + 54 );
	if ( $options->{'excel'} ) {
		return { bg_color => $colour, color => 'white', align => 'center', border => 1, border_color => 'white' };
	}
	if ( $options->{'rgb'} ) {
		return $colour;
	}
	return "background:$colour; color:white";
}

#Taken from Graphics::ColorUtils
sub get_rainbow_gradient_colour {
	my ( $value, $max_value ) = @_;
	my $frac    = $value / $max_value;
	my $rainbow = [
		[ 255, 0,   42 ],
		[ 255, 0,   36 ],
		[ 255, 0,   31 ],
		[ 255, 0,   26 ],
		[ 255, 0,   20 ],
		[ 255, 0,   15 ],
		[ 255, 0,   10 ],
		[ 255, 0,   4 ],
		[ 255, 5,   0 ],
		[ 255, 11,  0 ],
		[ 255, 16,  0 ],
		[ 255, 22,  0 ],
		[ 255, 27,  0 ],
		[ 255, 32,  0 ],
		[ 255, 38,  0 ],
		[ 255, 43,  0 ],
		[ 255, 48,  0 ],
		[ 255, 54,  0 ],
		[ 255, 59,  0 ],
		[ 255, 65,  0 ],
		[ 255, 70,  0 ],
		[ 255, 75,  0 ],
		[ 255, 81,  0 ],
		[ 255, 91,  0 ],
		[ 255, 97,  0 ],
		[ 255, 102, 0 ],
		[ 255, 108, 0 ],
		[ 255, 113, 0 ],
		[ 255, 118, 0 ],
		[ 255, 124, 0 ],
		[ 255, 129, 0 ],
		[ 255, 135, 0 ],
		[ 255, 140, 0 ],
		[ 255, 145, 0 ],
		[ 255, 151, 0 ],
		[ 255, 156, 0 ],
		[ 255, 161, 0 ],
		[ 255, 167, 0 ],
		[ 255, 178, 0 ],
		[ 255, 183, 0 ],
		[ 255, 188, 0 ],
		[ 255, 194, 0 ],
		[ 255, 199, 0 ],
		[ 255, 204, 0 ],
		[ 255, 210, 0 ],
		[ 255, 215, 0 ],
		[ 255, 221, 0 ],
		[ 255, 226, 0 ],
		[ 255, 231, 0 ],
		[ 255, 237, 0 ],
		[ 255, 242, 0 ],
		[ 255, 247, 0 ],
		[ 255, 253, 0 ],
		[ 245, 255, 0 ],
		[ 240, 255, 0 ],
		[ 235, 255, 0 ],
		[ 229, 255, 0 ],
		[ 224, 255, 0 ],
		[ 219, 255, 0 ],
		[ 213, 255, 0 ],
		[ 208, 255, 0 ],
		[ 202, 255, 0 ],
		[ 197, 255, 0 ],
		[ 192, 255, 0 ],
		[ 186, 255, 0 ],
		[ 181, 255, 0 ],
		[ 175, 255, 0 ],
		[ 170, 255, 0 ],
		[ 159, 255, 0 ],
		[ 154, 255, 0 ],
		[ 149, 255, 0 ],
		[ 143, 255, 0 ],
		[ 138, 255, 0 ],
		[ 132, 255, 0 ],
		[ 127, 255, 0 ],
		[ 122, 255, 0 ],
		[ 116, 255, 0 ],
		[ 111, 255, 0 ],
		[ 106, 255, 0 ],
		[ 100, 255, 0 ],
		[ 95,  255, 0 ],
		[ 89,  255, 0 ],
		[ 84,  255, 0 ],
		[ 73,  255, 0 ],
		[ 68,  255, 0 ],
		[ 63,  255, 0 ],
		[ 57,  255, 0 ],
		[ 52,  255, 0 ],
		[ 46,  255, 0 ],
		[ 41,  255, 0 ],
		[ 36,  255, 0 ],
		[ 30,  255, 0 ],
		[ 25,  255, 0 ],
		[ 19,  255, 0 ],
		[ 14,  255, 0 ],
		[ 9,   255, 0 ],
		[ 3,   255, 0 ],
		[ 0,   255, 1 ],
		[ 0,   255, 12 ],
		[ 0,   255, 17 ],
		[ 0,   255, 23 ],
		[ 0,   255, 28 ],
		[ 0,   255, 33 ],
		[ 0,   255, 39 ],
		[ 0,   255, 44 ],
		[ 0,   255, 49 ],
		[ 0,   255, 55 ],
		[ 0,   255, 60 ],
		[ 0,   255, 66 ],
		[ 0,   255, 71 ],
		[ 0,   255, 76 ],
		[ 0,   255, 82 ],
		[ 0,   255, 87 ],
		[ 0,   255, 98 ],
		[ 0,   255, 103 ],
		[ 0,   255, 109 ],
		[ 0,   255, 114 ],
		[ 0,   255, 119 ],
		[ 0,   255, 125 ],
		[ 0,   255, 130 ],
		[ 0,   255, 135 ],
		[ 0,   255, 141 ],
		[ 0,   255, 146 ],
		[ 0,   255, 152 ],
		[ 0,   255, 157 ],
		[ 0,   255, 162 ],
		[ 0,   255, 168 ],
		[ 0,   255, 173 ],
		[ 0,   255, 184 ],
		[ 0,   255, 189 ],
		[ 0,   255, 195 ],
		[ 0,   255, 200 ],
		[ 0,   255, 205 ],
		[ 0,   255, 211 ],
		[ 0,   255, 216 ],
		[ 0,   255, 222 ],
		[ 0,   255, 227 ],
		[ 0,   255, 232 ],
		[ 0,   255, 238 ],
		[ 0,   255, 243 ],
		[ 0,   255, 248 ],
		[ 0,   255, 254 ],
		[ 0,   250, 255 ],
		[ 0,   239, 255 ],
		[ 0,   234, 255 ],
		[ 0,   228, 255 ],
		[ 0,   223, 255 ],
		[ 0,   218, 255 ],
		[ 0,   212, 255 ],
		[ 0,   207, 255 ],
		[ 0,   201, 255 ],
		[ 0,   196, 255 ],
		[ 0,   191, 255 ],
		[ 0,   185, 255 ],
		[ 0,   180, 255 ],
		[ 0,   174, 255 ],
		[ 0,   169, 255 ],
		[ 0,   164, 255 ],
		[ 0,   153, 255 ],
		[ 0,   148, 255 ],
		[ 0,   142, 255 ],
		[ 0,   137, 255 ],
		[ 0,   131, 255 ],
		[ 0,   126, 255 ],
		[ 0,   121, 255 ],
		[ 0,   115, 255 ],
		[ 0,   110, 255 ],
		[ 0,   105, 255 ],
		[ 0,   99,  255 ],
		[ 0,   94,  255 ],
		[ 0,   88,  255 ],
		[ 0,   83,  255 ],
		[ 0,   78,  255 ],
		[ 0,   67,  255 ],
		[ 0,   62,  255 ],
		[ 0,   56,  255 ],
		[ 0,   51,  255 ],
		[ 0,   45,  255 ],
		[ 0,   40,  255 ],
		[ 0,   35,  255 ],
		[ 0,   29,  255 ],
		[ 0,   24,  255 ],
		[ 0,   18,  255 ],
		[ 0,   13,  255 ],
		[ 0,   8,   255 ],
		[ 0,   2,   255 ],
		[ 2,   0,   255 ],
		[ 7,   0,   255 ],
		[ 18,  0,   255 ],
		[ 24,  0,   255 ],
		[ 29,  0,   255 ],
		[ 34,  0,   255 ],
		[ 40,  0,   255 ],
		[ 45,  0,   255 ],
		[ 50,  0,   255 ],
		[ 56,  0,   255 ],
		[ 61,  0,   255 ],
		[ 67,  0,   255 ],
		[ 72,  0,   255 ],
		[ 77,  0,   255 ],
		[ 83,  0,   255 ],
		[ 88,  0,   255 ],
		[ 93,  0,   255 ],
		[ 104, 0,   255 ],
		[ 110, 0,   255 ],
		[ 115, 0,   255 ],
		[ 120, 0,   255 ],
		[ 126, 0,   255 ],
		[ 131, 0,   255 ],
		[ 136, 0,   255 ],
		[ 142, 0,   255 ],
		[ 147, 0,   255 ],
		[ 153, 0,   255 ],
		[ 158, 0,   255 ],
		[ 163, 0,   255 ],
		[ 169, 0,   255 ],
		[ 174, 0,   255 ],
		[ 180, 0,   255 ],
		[ 190, 0,   255 ],
		[ 196, 0,   255 ],
		[ 201, 0,   255 ],
		[ 206, 0,   255 ],
		[ 212, 0,   255 ],
		[ 217, 0,   255 ],
		[ 223, 0,   255 ],
		[ 228, 0,   255 ],
		[ 233, 0,   255 ],
		[ 239, 0,   255 ],
		[ 244, 0,   255 ],
		[ 249, 0,   255 ],
		[ 255, 0,   254 ],
		[ 255, 0,   249 ],
		[ 255, 0,   243 ],
		[ 255, 0,   233 ],
		[ 255, 0,   227 ],
		[ 255, 0,   222 ],
		[ 255, 0,   217 ],
		[ 255, 0,   211 ],
		[ 255, 0,   206 ],
		[ 255, 0,   201 ]
	];
	my $idx = int( $frac * ( @$rainbow - 1 ) );
	return sprintf( '#%02x%02x%02x', @{ $rainbow->[$idx] } );
}

sub all_ints {
	my ($list) = @_;
	$logger->logcarp('Not an arrayref') if ref $list ne 'ARRAY';
	foreach my $value (@$list) {
		return if !BIGSdb::Utils::is_int($value);
	}
	return 1;
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

#Array of lengths must be in descending length order.
sub get_N_stats {
	my ( $total_length, $contig_length_arrayref ) = @_;
	my $n50_target = 0.5 * $total_length;
	my $n90_target = 0.1 * $total_length;
	my $n95_target = 0.05 * $total_length;
	my $stats;
	my $running_total = $total_length;
	my $count         = 0;
	foreach my $length (@$contig_length_arrayref) {
		$running_total -= $length;
		$count++;
		if ( !defined $stats->{'L50'} && $running_total <= $n50_target ) {
			$stats->{'L50'} = $length;
			$stats->{'N50'} = $count;
		}
		if ( !defined $stats->{'L90'} && $running_total <= $n90_target ) {
			$stats->{'L90'} = $length;
			$stats->{'N90'} = $count;
		}
		if ( !defined $stats->{'L95'} && $running_total <= $n95_target ) {
			$stats->{'L95'} = $length;
			$stats->{'N95'} = $count;
		}
	}
	return $stats;
}

sub escape_html {
	my ($string) = @_;
	return if !defined $string;
	$string =~ s/"/\&quot;/gx;
	$string =~ s/</\&lt;/gx;
	$string =~ s/>/\&gt;/gx;
	return $string;
}

#Put commas in numbers
#Perl Cookbook 2.16
sub commify {
	my ($text) = @_;
	$text = reverse $text;
	$text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/gx;
	return scalar reverse $text;
}

sub random_string {
	my ( $length, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my @chars = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9 );
	push @chars, qw(! @ $ % ^ & * \( \) _ + ~) if $options->{'extended_chars'};
	my $string;
	for ( 1 .. $length ) {
		$string .= $chars[ int( rand($#chars) ) ];
	}
	return $string;
}

#From http://www.jb.man.ac.uk/~slowe/perl/filesize.html
sub get_nice_size {
	my ( $size, $decimal_places ) = @_;    # First variable is the size in bytes
	$logger->logcarp('Size not passed') if !defined $size;
	$decimal_places //= 1;
	my @units = ( 'bytes', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB' );
	my $u = 0;
	$decimal_places = ( $decimal_places > 0 ) ? 10**$decimal_places : 1;
	while ( $size > 1024 ) {
		$size /= 1024;
		$u++;
	}
	if   ( $units[$u] ) { return ( int( $size * $decimal_places ) / $decimal_places ) . ' ' . $units[$u]; }
	else                { return int($size); }
}

sub slurp {
	my ($file_path) = @_;
	open( my $fh, '<:raw', $file_path )
	  || throw BIGSdb::CannotOpenFileException("Can't open $file_path for reading");
	my $contents = do { local $/ = undef; <$fh> };
	return \$contents;
}

sub remove_trailing_spaces_from_list {
	my ($list) = @_;
	foreach (@$list) {
		s/^\s*//x;
		s/\s*$//x;
	}
	return;
}

sub get_datestamp {
	my @date = localtime;
	my $year = 1900 + $date[5];
	my $mon  = $date[4] + 1;
	my $day  = $date[3];
	return sprintf( '%d-%02d-%02d', $year, $mon, $day );
}

sub get_pg_array {
	my ($profile) = @_;
	my @cleaned_values;
	foreach my $value (@$profile) {
		$value =~ s/"/\\"/gx;
		$value =~ s/\\/\\\\/gx;
		push @cleaned_values, $value;
	}
	local $" = q(",");
	return qq({"@cleaned_values"});
}

#Uses Schwartzian transform https://en.wikipedia.org/wiki/Schwartzian_transform
sub dictionary_sort {
	my ( $values, $labels ) = @_;
	my @ret_values = map { $_->[0] }
	  sort { $a->[1] cmp $b->[1] }
	  map {    ## no critic(ProhibitComplexMappings)
		my $d = lc( $labels->{$_} );
		$d =~ s/[\W_]+//gx;
		[ $_, $d ]
	  } uniq @$values;
	return \@ret_values;
}

sub get_nice_duration {
	my ($total_seconds) = @_;
	my $hours = int( $total_seconds / 3600 );
	my $minutes = int( ( $total_seconds - $hours * 3600 ) / 60 );
	my $seconds = $total_seconds % 60;
	return sprintf( '%d:%02d:%02d', $hours, $minutes, $seconds );
}

sub convert_html_table_to_text {
	my ($html) = @_;
	my $buffer = q();
	my @lines = split /\n/x, $html;
	foreach my $line (@lines) {
		$line =~ s/&rarr;/->/gx;
		$line =~ s/<\/th><th.*?>/\t/gx;                      #Convert cell breaks to tabs
		$line =~ s/<\/td><td.*?>/\t/gx;
		$line =~ s/<\/tr>/\n/gx;                             #Convert </tr> to newlines
		$line =~ s/<span\ class="source">.*?<\/span>//gx;    #Remove linked data source
		$line =~ s/<.+?>//gx;                                #Remove any remaining tags
		$buffer .= $line;
	}
	return $buffer;
}
1;
