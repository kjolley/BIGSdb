#Written by Keith Jolley
#Copyright (c) 2013, University of Oxford
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
package BIGSdb::Offline::ScanNew;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Offline::Scan);
use Digest::MD5;
use constant DEFAULT_ALIGNMENT => 100;
use constant DEFAULT_IDENTITY  => 99;
use constant DEFAULT_WORD_SIZE => 30;

sub run_script {
	my ($self) = @_;
	my $EXIT = 0;
	local @SIG{qw (INT TERM HUP)} = ( sub { $EXIT = 1 } ) x 3;    #Allow temp files to be cleaned on kill signals
	my $params;
	$params->{$_} = 1 foreach qw(pcr_filter probe_filter);
	$params->{'alignment'} = BIGSdb::Utils::is_int( $self->{'options'}->{'A'} ) ? $self->{'options'}->{'A'} : DEFAULT_ALIGNMENT;
	$params->{'identity'}  = BIGSdb::Utils::is_int( $self->{'options'}->{'B'} ) ? $self->{'options'}->{'B'} : DEFAULT_IDENTITY;
	$params->{'word_size'} = BIGSdb::Utils::is_int( $self->{'options'}->{'w'} ) ? $self->{'options'}->{'w'} : DEFAULT_WORD_SIZE;
	my $isolates       = $self->get_isolates_with_linked_seqs;
	my $isolate_list   = $self->filter_and_sort_isolates($isolates);
	my $loci           = $self->get_loci_with_ref_db;
	my $isolate_prefix = BIGSdb::Utils::get_random();
	my $locus_prefix   = BIGSdb::Utils::get_random();
	$self->{'start_time'} = time;
	my $first = 1;
	my $isolate_count = @$isolate_list;
	my $plural = $isolate_count == 1 ? '' : 's';
	$self->{'logger'}->info("$self->{'options'}->{'d'}:ScanNew start ($isolate_count genome$plural)");

	foreach my $locus (@$loci) {
		$self->{'logger'}->info("$self->{'options'}->{'d'}:Checking $locus");
		my %seqs;
		foreach my $isolate_id (@$isolate_list) {
			next if defined $self->{'datastore'}->get_allele_id( $isolate_id, $locus );
			my $allele_seq = $self->{'datastore'}->get_allele_sequence( $isolate_id, $locus );
			next if @$allele_seq;
			my ( $exact_matches, $partial_matches ) = $self->blast( $params, $locus, $isolate_id, $isolate_prefix, $locus_prefix );
			next if ref $exact_matches && @$exact_matches;
			foreach my $match (@$partial_matches) {
				next if $self->_off_end_of_contig($match);
				my $seq      = $self->extract_seq_from_match($match);
				my $seq_hash = Digest::MD5::md5_hex($seq);
				next if $seqs{$seq_hash};
				$seqs{$seq_hash} = 1;
				if ($first) {
					say "locus\tallele_id\tstatus\tsequence";
					$first = 0;
				}
				say "$locus\t\ttrace not checked\t$seq";
			}
			last if $EXIT || $self->_is_time_up;
		}

		#Delete locus working files
		$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$locus_prefix*");
		last if $EXIT || $self->_is_time_up;
	}

	#Delete isolate working files
	$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$isolate_prefix*");
	$self->{'logger'}->info("$self->{'options'}->{'d'}:ScanNew stop");
	return;
}

sub _off_end_of_contig {
	my ( $self, $match ) = @_;
	my $seqbin_length =
	  $self->{'datastore'}->run_simple_query( "SELECT length(sequence) FROM sequence_bin WHERE id=?", $match->{'seqbin_id'} )->[0];
	if ( BIGSdb::Utils::is_int( $match->{'predicted_start'} ) && $match->{'predicted_start'} < 1 ) {
		$match->{'predicted_start'} = '1';
		$match->{'incomplete'}      = 1;
		return 1;
	}
	if ( BIGSdb::Utils::is_int( $match->{'predicted_end'} ) && $match->{'predicted_end'} > $seqbin_length ) {
		$match->{'predicted_end'} = $seqbin_length;
		$match->{'incomplete'}    = 1;
		return 1;
	}
	return;
}

sub _is_time_up {
	my ($self) = @_;
	if ( $self->{'options'}->{'t'} && BIGSdb::Utils::is_int( $self->{'options'}->{'t'} ) ) {
		return 1 if time > ( $self->{'start_time'} + $self->{'options'}->{'t'} * 60 );
	}
	return;
}
1;
