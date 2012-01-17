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
#
#
#is_float function (c) 2002-2008, David Wheeler
package BIGSdb::Utils;
use strict;
use warnings;
use POSIX qw(ceil);
use Time::Local;

sub reverse_complement {
	my ($seq) = @_;
	my $reversed = reverse $seq;
	$reversed =~ tr/GATCgatc/CTAGctag/;    #complement
	return $reversed;
}

sub is_valid_DNA {

	# checks if a valid DNA sequence
	my ( $seq, $diploid ) = @_;
	$seq = uc($seq);
	$seq =~ s/[-. \s]//g;

	#check it's a sequence - allow codes for two bases to
	#accommodate diploid sequence types
	if ($diploid) {
		return $seq =~ /[^ACGTRYWSMK]/ ? 0 : 1;
	} else {
		return $seq =~ /[^ACGT]/ ? 0 : 1;
	}
}

sub sequence_type {
	my ($seq) = @_;
	my $agtc_count = 0;
	foreach ( my $i = 0 ; $i < length $seq ; $i++ ) {
		if ( uc( substr( $seq, $i, 1 ) ) =~ /^G|A|T|C|N$/ ) {
			$agtc_count++;
		}
	}
	return 'DNA' if !length $seq;
	return ( $agtc_count / length $seq ) >= 0.9 ? 'DNA' : 'peptide';
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
	my $seq;
	my $pos = 1;
	for ( my $i = 0 ; $i < length($orig_string) ; $i++ ) {
		$seq .= substr $orig_string, $i, 1;
		if ( $pos == $length ) {
			$seq .= "\n" if $i != length($orig_string) - 1;
			$pos = 0;
		}
		$pos++;
	}
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
	if ( $qry =~ /^(\d{4})-(\d{2})-(\d{2})$/ ){
		my ($y, $m, $d) = ($1, $2, $3);
		eval { timelocal 0, 0, 0, $d, $m-1, $y-1900 };
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
	my ($N) = shift;
	return 0 if ( !defined $N || $N eq '' );
	my ($sign) = '^\s* [-+]? \s*';
	my ($int)  = '\d+ \s* $ ';
	return 1 if ( $N =~ /$sign $int/x );
	return 0;
}

sub is_float {

	#From Data::Types (c) 2002-2008 David Wheeler
	return unless defined $_[0] && $_[0] ne '';
	return unless $_[0] =~ /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/;
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
	my $sequence;
	foreach (@lines) {
		$_ =~ s/\r//g;
		if ( $_ =~ /^>/ ) {
			$header = substr( $_, 1 );
			next;
		}
		throw BIGSdb::DataException("Not valid FASTA format.") if !$header;
		my $temp_seq = uc($_);
		$temp_seq =~ s/\s//g;
		throw BIGSdb::DataException("Not valid DNA $header") if $temp_seq =~ /[^GATCBDHVRYKMSWN]/;
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
	my ( $max, $min ) = (0, 0);
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
	my ($number, $nearest) = @_;
	return ceil(int($number)/$nearest)*$nearest;  
}
1;
