#Written by Keith Jolley
#Copyright (c) 2017, University of Oxford
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
package BIGSdb::Offline::GCHelper;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Offline::Scan);

sub run_script {
	my ($self) = @_;
	return $self if $self->{'options'}->{'query_only'};    #Return script object to allow access to methods
	my $loci        = $self->get_selected_loci;
	my $isolates    = $self->get_isolates;
	my $merged_data = {};
	foreach my $isolate_id (@$isolates) {
		my $data = $self->_get_allele_designations( $isolate_id, $loci );
		$merged_data->{$isolate_id} = $data;
	}
	$self->{'results'} = $merged_data;
	return;
}

sub get_results {
	my ($self) = @_;
	return $self->{'results'};
}

sub get_new_sequences {
	my ($self) = @_;
	return { seq_lookup => $self->{'seq_lookup'}, allele_lookup => $self->{'allele_lookup'} };
}

sub _get_allele_designations {
	my ( $self, $isolate_id, $loci ) = @_;
	my %loci = map { $_ => 1 } @$loci;
	my $all_designations =
	  $self->{'datastore'}
	  ->run_query( q(SELECT locus,allele_id FROM allele_designations WHERE isolate_id=? AND status!='ignore'),
		$isolate_id, { fetch => 'all_arrayref', slice => {}, cache => 'GCHelper::get_allele_designations' } );
	my $designations = {};
	foreach my $designation (@$all_designations) {
		next if !$self->{'options'}->{'use_tagged'};
		next if !$loci{ $designation->{'locus'} };
		my $locus_info = $self->{'datastore'}->get_locus_info( $designation->{'locus'} );

		#Always BLAST if it is a peptide locus and we need the nucleotide sequence for alignment
		next if $locus_info->{'data_type'} eq 'peptide' && $self->{'options'}->{'sequences'};
		if ( $designations->{ $designation->{'locus'} } ) {

			#Make sure allele ordering is consistent.
			my @allele_ids = split /;/x, $designations->{ $designation->{'locus'} };
			push @allele_ids, $designation->{'allele_id'};
			my $sorted_allele_ids = $self->_sort_allele_list( $designation->{'locus'}, \@allele_ids );
			local $" = q(;);
			$designations->{ $designation->{'locus'} } = qq(@$sorted_allele_ids);
		} else {
			$designations->{ $designation->{'locus'} } = $designation->{'allele_id'};
		}
	}
	my $sequences = {};
	if ( $self->{'options'}->{'sequences'} ) {
		$sequences = $self->_get_designation_seqs($designations);
	}
	my $missing_loci = [];
	foreach my $locus (@$loci) {
		push @$missing_loci, $locus if !defined $designations->{$locus};
	}
	my ( $scanned_designations, $scanned_sequences ) = $self->_scan_by_loci( $isolate_id, $missing_loci );

	#Merge looked up and scanned designations and sequences.
	%$designations = ( %$designations, %$scanned_designations );
	if ( $self->{'options'}->{'sequences'} ) {
		%$sequences = ( %$sequences, %$scanned_sequences );
	}
	my $return_hash = { designations => $designations };
	$return_hash->{'sequences'} = $sequences if $self->{'options'}->{'sequences'};
	return $return_hash;
}

sub _scan_by_loci {
	my ( $self, $isolate_id, $loci ) = @_;
	return ( {}, {} ) if !@$loci;
	my $isolate_prefix = BIGSdb::Utils::get_random();
	my $locus_prefix   = BIGSdb::Utils::get_random();
	my $params         = {};
	$params->{$_} = $self->{'options'}->{$_} foreach qw(exemplar fast identity alignment word_size);
	my ( $exact_matches, $partial_matches ) =
	  $self->blast_multiple_loci( $params, $loci, $isolate_id, $isolate_prefix, $locus_prefix );
	my $designations = {};
	my $seqs         = {};
  LOCUS: foreach my $locus (@$loci) {
		my %allele_already_found;
		my @allele_ids;
	  MATCH: foreach my $match ( @{ $exact_matches->{$locus} } ) {
			if ( !$allele_already_found{ $match->{'allele'} } ) {
				push @allele_ids, $match->{'allele'};
				$allele_already_found{ $match->{'allele'} } = 1;
			}
		}
		my $sorted_allele_ids = $self->_sort_allele_list( $locus, \@allele_ids );
		if (@$sorted_allele_ids) {
			local $" = q(;);
			$designations->{$locus} = qq(@$sorted_allele_ids);
			if ( $self->{'options'}->{'sequences'} ) {
				$seqs->{$locus} = $self->_get_seqs_from_matches( $locus, $sorted_allele_ids, $exact_matches->{$locus} );
			}
		}
	}
  LOCUS: foreach my $locus (@$loci) {
		next if $designations->{$locus};

		#There may be multiple matches
		my $match = $self->_get_highest_quality_match( $partial_matches->{$locus} );
		if ( !$match ) {
			$designations->{$locus} = 'missing';
			$seqs->{$locus}         = undef;
			next LOCUS;
		}
		$self->_check_off_end_of_contig($match);
		my $seq = $self->extract_seq_from_match($match);
		if ( $match->{'incomplete'} ) {
			$designations->{$locus} = 'incomplete';
			$seqs->{$locus}         = $seq;
			next LOCUS;
		}
		$designations->{$locus} = $self->_get_new_allele_designation( $locus, \$seq );
		$seqs->{$locus} = $seq;
	}
	$self->delete_temp_files("$_*") foreach ( $isolate_prefix, $locus_prefix );
	return ( $designations, $seqs );
}

sub _sort_allele_list {
	my ( $self, $locus, $allele_ids ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
		@$allele_ids = sort { $a <=> $b } @$allele_ids;
	} else {
		@$allele_ids = sort { $a cmp $b } @$allele_ids;
	}
	return $allele_ids;
}

sub _get_designation_seqs {
	my ( $self, $designations ) = @_;
	my $seqs = {};
	foreach my $locus ( keys %$designations ) {
		my @allele_ids = split /;/x, $designations->{$locus};
		foreach my $allele_id (@allele_ids) {
			my $seq_ref = $self->{'datastore'}->get_locus($locus)->get_allele_sequence($allele_id);
			$seqs->{$locus} .= $$seq_ref;
		}
	}
	return $seqs;
}

sub _get_seqs_from_matches {
	my ( $self, $locus, $allele_ids, $matches ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $seq;
	if ( $locus_info->{'data_type'} eq 'DNA' ) {
		foreach my $allele_id (@$allele_ids) {
			my $seq_ref = $self->{'datastore'}->get_locus($locus)->get_allele_sequence($allele_id);
			$seq .= $$seq_ref;
		}
		return $seq;
	}
	foreach my $allele_id (@$allele_ids) {
		foreach my $match (@$matches) {
			next if $match->{'allele'} ne $allele_id;
			$seq .= $self->extract_seq_from_match($match);
			last;
		}
	}
	return $seq;
}

sub _get_highest_quality_match {
	my ( $self, $matches ) = @_;
	return if !ref $matches || !@$matches;
	my $highest_quality = 0;
	my $i               = 0;
	my $index           = 0;
	foreach my $match (@$matches) {
		if ( $match->{'quality'} > $highest_quality ) {
			$highest_quality = $match->{'quality'};
			$index           = $i;
		}
		$i++;
	}
	return $matches->[$index];
}

sub _check_off_end_of_contig {
	my ( $self, $match ) = @_;
	my $seqbin_length = $self->{'datastore'}->run_query( 'SELECT length(sequence) FROM sequence_bin WHERE id=?',
		$match->{'seqbin_id'}, { cache => 'GCHelper::off_end_of_contig' } );
	if ( BIGSdb::Utils::is_int( $match->{'predicted_start'} ) && $match->{'predicted_start'} < 1 ) {
		$match->{'predicted_start'} = '1';
		$match->{'incomplete'}      = 1;
	} elsif ( BIGSdb::Utils::is_int( $match->{'predicted_end'} ) && $match->{'predicted_end'} > $seqbin_length ) {
		$match->{'predicted_end'} = $seqbin_length;
		$match->{'incomplete'}    = 1;
	}
	return;
}

sub _get_new_allele_designation {
	my ( $self, $locus, $seq_ref ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( $locus_info->{'data_type'} eq 'peptide' ) {
		$seq_ref = $self->_translate($seq_ref);
	}
	my $hash = Digest::MD5::md5_hex($$seq_ref);
	$self->{'seq_lookup'}->{$locus}    //= {};
	$self->{'allele_lookup'}->{$locus} //= {};
	if ( $self->{'allele_lookup'}->{$locus}->{$hash} ) {
		return $self->{'allele_lookup'}->{$locus}->{$hash};
	}
	my $i = 1;
	my $name = $self->{'options'}->{'global_new'} ? 'new' : 'local_new';
	$i++ while $self->{'seq_lookup'}->{$locus}->{"$name#$i"};
	$self->{'seq_lookup'}->{$locus}->{"$name#$i"} = $$seq_ref;
	$self->{'allele_lookup'}->{$locus}->{$hash} = "$name#$i";
	return "$name#$i";
}

sub _translate {
	my ( $self, $seq_ref ) = @_;
	my $seq_obj = Bio::Seq->new( -seq => $$seq_ref, -alphabet => 'dna' );
	my $translated_seq = $seq_obj->translate->seq;
	return \$translated_seq;
}
1;
