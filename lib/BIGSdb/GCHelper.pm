#Written by Keith Jolley
#Copyright (c) 2017-2019, University of Oxford
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
package BIGSdb::GCHelper;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Offline::Scan);
use BIGSdb::Constants qw(SEQ_METHODS);

sub run_script {
	my ($self) = @_;
	return $self if $self->{'options'}->{'query_only'};    #Return script object to allow access to methods
	my $isolates    = $self->_process_user_genomes;
	my $merged_data = {};
	if ( $self->{'options'}->{'reference_file'} ) {
		foreach my $isolate_id (@$isolates) {
			my $data = $self->_get_allele_designations_from_reference($isolate_id);
			$merged_data->{$isolate_id} = $data;
		}
	} else {
		my $loci = $self->get_selected_loci;
		foreach my $isolate_id (@$isolates) {
			my $data = $self->_get_allele_designations_from_defined_loci( $isolate_id, $loci );
			$merged_data->{$isolate_id} = $data;
		}
	}
	$self->{'results'} = $merged_data;
	return;
}

sub _process_user_genomes {
	my ($self) = @_;
	my $isolate_ids = $self->get_isolates;
	return $isolate_ids if !$self->{'options'}->{'user_genomes'};
	my $user_genomes        = $self->{'options'}->{'user_genomes'};
	my $temp_list_table     = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $isolate_ids );
	my $isolate_table       = 'temp_isolates';
	my $merged_isolate_view = 'isolates_view';
	my $seqbin_table        = 'temp_seqbin';
	my $merged_seqbin_view  = 'seqbin_view';
	my $id                  = -1;
	$self->{'db'}->do("CREATE TEMP table $isolate_table AS (SELECT * FROM $self->{'system'}->{'view'} LIMIT 0)");
	$self->{'db'}->do("CREATE TEMP table $seqbin_table AS (SELECT * FROM sequence_bin LIMIT 0)");
	my $seqbin_id = -1;

	foreach my $genome_name ( reverse sort keys %$user_genomes ) {
		$self->{'db'}->do( "INSERT INTO $isolate_table (id, $self->{'system'}->{'labelfield'}) VALUES (?,?)",
			undef, $id, $genome_name );
		unshift @$isolate_ids, $id if !$self->{'options'}->{'i'};
		foreach my $contig ( @{ $user_genomes->{$genome_name} } ) {
			$self->{'db'}->do(
				"INSERT INTO $seqbin_table (id,isolate_id,remote_contig,sequence,original_designation,"
				  . 'sender,curator,date_entered,datestamp) VALUES (?,?,?,?,?,?,?,?,?)',
				undef, $seqbin_id, $id, 'false', $contig->{'seq'}, $contig->{'id'}, 0, 0, 'now', 'now'
			);
			$seqbin_id--;
		}
		$id--;
	}
	$self->{'db'}->do( "CREATE TEMP view $merged_isolate_view AS (SELECT i.* FROM $self->{'system'}->{'view'} i "
		  . "JOIN $temp_list_table t ON i.id=t.value) UNION SELECT * FROM $isolate_table" );
	$self->{'system'}->{'view'} = $merged_isolate_view;
	$self->{'db'}->do( "CREATE TEMP view $merged_seqbin_view AS (SELECT s.* FROM sequence_bin s "
		  . "JOIN $temp_list_table t ON s.isolate_id=t.value) UNION SELECT * FROM $seqbin_table" );
	$self->{'seqbin_table'} = $merged_seqbin_view;
	$self->{'contigManager'}->set_seqbin_table($merged_seqbin_view);
	return [ $self->{'options'}->{'i'} ] if defined $self->{'options'}->{'i'};
	return $isolate_ids;
}

sub get_results {
	my ($self) = @_;
	return $self->{'results'};
}

sub get_new_sequences {
	my ($self) = @_;
	return { seq_lookup => $self->{'seq_lookup'}, allele_lookup => $self->{'allele_lookup'} };
}

sub _get_allele_designations_from_reference {
	my ( $self, $isolate_id ) = @_;
	my $isolate_fasta = $self->_create_isolate_FASTA_db($isolate_id);
	my $word_size =
	  BIGSdb::Utils::is_int( $self->{'params'}->{'word_size'} )
	  ? $self->{'params'}->{'word_size'}
	  : 15;
	my $out_file =
	  "$self->{'config'}->{'secure_tmp_dir'}/$self->{'options'}->{'job_id'}_isolate_${isolate_id}_outfile.txt";
	if ( !$self->_does_isolate_have_sequence_data($isolate_id) ) {

		#Don't bother with BLAST but we do need an empty results file.
		open( my $fh, '>', $out_file ) || $self->{'logger'}->error("Cannot touch $out_file");
		close $fh;
	} else {
		$self->_blast(
			{
				word_size   => $word_size,
				fasta_file  => $isolate_fasta,
				in_file     => $self->{'options'}->{'reference_file'},
				locus_count => $self->{'options'}->{'locus_count'},
				out_file    => $out_file,
			}
		);
	}
	return $self->_parse_blast($out_file);
}

sub _blast {
	my ( $self, $params ) = @_;
	my $blast_threads = $self->{'config'}->{'blast_threads'} // 1;
	my %params = (
		-num_threads     => $blast_threads,
		-max_target_seqs => $params->{'locus_count'} * 1000,
		-word_size       => $params->{'word_size'},
		-db              => $params->{'fasta_file'},
		-query           => $params->{'in_file'},
		-out             => $params->{'out_file'},
		-outfmt          => 6,
		-dust            => 'no'
	);
	my $program = "$self->{'config'}->{'blast+_path'}/blastn";
	system( $program, %params );
	return;
}

sub _parse_blast {

	#return best matches
	my ( $self, $blast_file ) = @_;
	my $params    = $self->{'params'};
	my $identity  = BIGSdb::Utils::is_int( $params->{'identity'} ) ? $params->{'identity'} : 70;
	my $alignment = BIGSdb::Utils::is_int( $params->{'alignment'} ) ? $params->{'alignment'} : 50;
	my $blast     = {};
	open( my $blast_fh, '<', $blast_file )
	  || ( $self->{'logger'}->error("Cannot open BLAST output file $blast_file. $!"), return \$; );
	while ( my $line = <$blast_fh> ) {
		my @data = split /\t/x, $line;
		push @{ $blast->{ $data[0] } }, \@data;
	}
	close $blast_fh;
	my $designations = {};
	my $sequences    = {};
	my $paralogous   = [];
	my $locus_data   = $self->{'options'}->{'locus_data'};
	foreach my $locus ( sort keys %{ $self->{'options'}->{'locus_data'} } ) {
		my $final_match;
		my $quality = 0;    #simple metric of alignment length x percentage identity
		my $required_alignment = length $locus_data->{$locus}->{'sequence'};
		my $criteria_matches   = 0;
		$blast->{$locus} //= [];
		foreach my $record ( @{ $blast->{$locus} } ) {
			my $this_quality = $record->[3] * $record->[2];
			if ( $record->[3] >= $alignment * 0.01 * $required_alignment && $record->[2] >= $identity ) {
				my $this_match = $self->_extract_match( $record, $required_alignment, $required_alignment );
				$criteria_matches++;
				if ( $this_quality > $quality ) {
					$quality     = $this_quality;
					$final_match = $this_match;
				}
			}
		}
		if ($final_match) {
			my $sequence = $self->_extract_sequence($final_match);
			if ( $sequence eq $locus_data->{$locus}->{'sequence'} ) {
				$designations->{$locus} = '1';
			} elsif ( defined $final_match->{'predicted_start'} && defined $final_match->{'predicted_end'} ) {
				my $seqbin_length = $self->{'contigManager'}->get_contig_length( $final_match->{'seqbin_id'} );
				foreach my $end (qw (predicted_start predicted_end)) {
					if ( $final_match->{$end} < 1 || $final_match->{$end} > $seqbin_length ) {
						$designations->{$locus} = 'incomplete';
					}
				}
				$designations->{$locus} //= $self->_get_new_allele_designation( $locus, \$sequence );
			}
			$sequences->{$locus} = $sequence;
		} else {
			$designations->{$locus} = 'missing';
		}
		if ( $criteria_matches > 1 ) {    #only check if match sequences are different if there are more than 1
			push @$paralogous, $locus
			  if $self->_is_paralogous( $blast->{$locus}, $required_alignment, $identity, $alignment );
		}
	}
	my $results = { designations => $designations, paralogous => $paralogous };
	$results->{'sequences'} = $sequences if $self->{'options'}->{'align'};
	return $results;
}

sub _is_paralogous {
	my ( $self, $locus_blast_records, $required_alignment, $identity, $alignment ) = @_;
	my $good_matches = 0;
	my %existing_match_seqs;
	foreach my $record (@$locus_blast_records) {
		if ( $record->[3] >= $alignment * 0.01 * $required_alignment && $record->[2] >= $identity ) {
			my $this_match = $self->_extract_match( $record, $required_alignment, $required_alignment );
			my $match_seq = $self->_extract_sequence($this_match);
			if ( !$existing_match_seqs{$match_seq} ) {
				$existing_match_seqs{$match_seq} = 1;
				$good_matches++;
			}
		}
	}
	return 1 if $good_matches > 1;
	return;
}

sub _extract_match {
	my ( $self, $record, $required_alignment, $ref_length ) = @_;
	my $match;
	$match->{'seqbin_id'} = $record->[1];
	$match->{'identity'}  = $record->[2];
	$match->{'alignment'} = $record->[3];
	$match->{'start'}     = $record->[8];
	$match->{'end'}       = $record->[9];
	if (   ( $record->[8] > $record->[9] && $record->[7] > $record->[6] )
		|| ( $record->[8] < $record->[9] && $record->[7] < $record->[6] ) )
	{
		$match->{'reverse'} = 1;
	} else {
		$match->{'reverse'} = 0;
	}
	if ( $required_alignment > $match->{'alignment'} ) {
		if ( $match->{'reverse'} ) {
			$match->{'predicted_start'} = $match->{'start'} - $ref_length + $record->[6];
			$match->{'predicted_end'}   = $match->{'end'} + $record->[7] - 1;
		} else {
			$match->{'predicted_start'} = $match->{'start'} - $record->[6] + 1;
			$match->{'predicted_end'}   = $match->{'end'} + $ref_length - $record->[7];
		}
	} else {
		if ( $match->{'reverse'} ) {
			$match->{'predicted_start'} = $match->{'end'};
			$match->{'predicted_end'}   = $match->{'start'};
		} else {
			$match->{'predicted_start'} = $match->{'start'};
			$match->{'predicted_end'}   = $match->{'end'};
		}
	}
	return $match;
}

sub _extract_sequence {
	my ( $self, $match ) = @_;
	my $start = $match->{'predicted_start'};
	my $end   = $match->{'predicted_end'};
	return if !defined $start || !defined $end;
	if ( $end < $start ) {
		$start = $end;
	}
	my $seq_ref = $self->{'contigManager'}->get_contig_fragment(
		{
			seqbin_id => $match->{'seqbin_id'},
			start     => $start,
			end       => $end,
			reverse   => $match->{'reverse'}
		}
	);
	my $seq = $seq_ref->{'seq'};
	$self->{'db'}->commit;
	return $seq;
}

sub _create_isolate_FASTA_db {
	my ( $self, $isolate_id ) = @_;
	my $temp_infile = $self->_create_isolate_FASTA( $isolate_id, $self->{'options'}->{'job_id'} );
	return if !$temp_infile;
	system( "$self->{'config'}->{'blast+_path'}/makeblastdb",
		( -in => $temp_infile, -logfile => '/dev/null', -dbtype => 'nucl' ) );
	return $temp_infile;
}

sub _create_isolate_FASTA {
	my ( $self, $isolate_id, $prefix ) = @_;
	my $seqbin = $self->{'seqbin_table'} // 'sequence_bin';
	my $qry = "SELECT DISTINCT id FROM $seqbin s LEFT JOIN experiment_sequences e ON "
	  . 's.id=e.seqbin_id WHERE s.isolate_id=?';
	my @criteria = ($isolate_id);
	my $method   = $self->{'params'}->{'seq_method_list'};
	if ($method) {
		my %seq_methods = map { $_ => 1 } SEQ_METHODS;
		if ( !$seq_methods{$method} ) {
			$self->{'logger'}->error("Invalid method $method");
			return;
		}
		$qry .= ' AND method=?';
		push @criteria, $method;
	}
	my $experiment = $self->{'params'}->{'experiment_list'};
	if ($experiment) {
		if ( !BIGSdb::Utils::is_int($experiment) ) {
			$self->{'logger'}->error("Invalid experiment $experiment");
			return;
		}
		$qry .= ' AND experiment_id=?';
		push @criteria, $experiment;
	}
	my $seqbin_ids =
	  $self->{'datastore'}
	  ->run_query( $qry, \@criteria, { fetch => 'col_arrayref', cache => 'GenomeComparator::create_isolate_FASTA' } );
	my $contigs = $self->{'contigManager'}->get_contigs_by_list($seqbin_ids);
	if ( $isolate_id =~ /(-?\d*)/x ) { $isolate_id = $1 }    #untaint
	my $temp_infile = "$self->{'config'}->{'secure_tmp_dir'}/${prefix}_isolate_$isolate_id.txt";
	open( my $infile_fh, '>', $temp_infile ) || $self->{'logger'}->error("Cannot open $temp_infile for writing");
	foreach my $seqbin_id (@$seqbin_ids) {
		say $infile_fh ">$seqbin_id\n$contigs->{$seqbin_id}";
	}
	close $infile_fh;
	$self->{'db'}->commit;
	return $temp_infile;
}

sub _get_allele_designations_from_defined_loci {
	my ( $self, $isolate_id, $loci ) = @_;
	my %loci = map { $_ => 1 } @$loci;
	my $all_designations =
	  $self->{'datastore'}
	  ->run_query( q(SELECT locus,allele_id FROM allele_designations WHERE isolate_id=? AND status!='ignore'),
		$isolate_id, { fetch => 'all_arrayref', slice => {}, cache => 'GCHelper::get_allele_designations' } );
	my $tagged_loci = [];
	if ( $self->{'options'}->{'tag_status'} ) {
		$tagged_loci =
		  $self->{'datastore'}
		  ->run_query( 'SELECT DISTINCT(locus) FROM allele_sequences WHERE isolate_id=? ORDER BY locus',
			$isolate_id, { fetch => 'col_arrayref', cache => 'GCHelper::get_tagged_loci' } );
	}
	my $designations = {};
	my $paralogous   = {};
	my %designation_in_db;
	foreach my $designation (@$all_designations) {
		next if !$self->{'options'}->{'use_tagged'};
		next if !$loci{ $designation->{'locus'} };
		if ( $designation->{'allele_id'} eq '0' ) {
			next;
		} else {
			$designation_in_db{ $designation->{'locus'} } = 1;
		}
		my $locus_info = $self->{'datastore'}->get_locus_info( $designation->{'locus'} );

		#Always BLAST if it is a peptide locus and we need the nucleotide sequence for alignment
		next if $locus_info->{'data_type'} eq 'peptide' && $self->{'options'}->{'align'};
		if ( $designations->{ $designation->{'locus'} } ) {

			#Make sure allele ordering is consistent.
			my @allele_ids = split /;/x, $designations->{ $designation->{'locus'} };
			push @allele_ids, $designation->{'allele_id'};
			my $sorted_allele_ids = $self->_sort_allele_list( $designation->{'locus'}, \@allele_ids );
			local $" = q(;);
			$designations->{ $designation->{'locus'} } = qq(@$sorted_allele_ids);
			$paralogous->{ $designation->{'locus'} }   = 1;
		} else {
			$designations->{ $designation->{'locus'} } = $designation->{'allele_id'};
		}
	}
	my $sequences = {};
	if ( $self->{'options'}->{'align'} ) {
		$sequences = $self->_get_designation_seqs($designations);
	}
	my $missing_loci = [];
	foreach my $locus (@$loci) {
		push @$missing_loci, $locus if !defined $designations->{$locus};
	}

	#Only scan genome if <50% of selected loci are designated
	my $rescan = (keys %$designations < ( 0.5 * @$loci ) || $self->{'options'}->{'rescan_missing'}) ? 1 : 0;
	my ( $scanned_designations, $scanned_sequences, $scanned_paralogous ) = ( {}, {}, {} );
	if ($rescan) {
		( $scanned_designations, $scanned_sequences, $scanned_paralogous ) =
		  $self->_scan_by_loci( $isolate_id, $missing_loci );
	} else {
		foreach my $locus (@$missing_loci) {
			$scanned_designations->{$locus} = 'missing';
		}
	}

	#Merge looked up and scanned designations and sequences.
	%$designations = ( %$designations, %$scanned_designations );
	%$paralogous   = ( %$paralogous,   %$scanned_paralogous );
	my $paralogous_list = [];
	@$paralogous_list = sort keys %$paralogous;
	if ( $self->{'options'}->{'align'} ) {
		%$sequences = ( %$sequences, %$scanned_sequences );
	}
	my $return_hash = { designations => $designations, paralogous => $paralogous_list };
	if ( $self->{'options'}->{'align'} ) {
		$return_hash->{'sequences'} = $sequences;
	}
	if ( $self->{'options'}->{'designation_status'} ) {
		$return_hash->{'designation_in_db'} = [ sort ( keys %designation_in_db ) ];
	}
	if ( $self->{'options'}->{'tag_status'} ) {
		my $filtered_list = [];
		foreach my $locus (@$tagged_loci) {
			next if !$loci{$locus};
			push @$filtered_list, $locus;
		}
		$return_hash->{'tag_in_db'} = $filtered_list;
	}
	return $return_hash;
}

sub _does_isolate_have_sequence_data {
	my ( $self, $isolate_id ) = @_;
	my $seqbin = $self->{'seqbin_table'} // 'sequence_bin';
	return $self->{'datastore'}->run_query( qq(SELECT EXISTS(SELECT * FROM $seqbin WHERE isolate_id=?)),
		$isolate_id, { cache => 'GCHelper::does_isolate_have_sequence_data' } );
}

sub _scan_by_loci {
	my ( $self, $isolate_id, $loci ) = @_;
	return ( {}, {}, {} ) if !@$loci;
	my $isolate_prefix = BIGSdb::Utils::get_random();
	my $locus_prefix   = BIGSdb::Utils::get_random();
	my $params         = {};
	$params->{$_} = $self->{'options'}->{$_} foreach qw(exemplar fast partial_matches identity alignment word_size);
	my ( $exact_matches, $partial_matches );
	if ( !$self->_does_isolate_have_sequence_data($isolate_id) ) {
		$exact_matches   = {};
		$partial_matches = {};
	} else {
		( $exact_matches, $partial_matches ) =
		  $self->blast_multiple_loci( $params, $loci, $isolate_id, $isolate_prefix, $locus_prefix );
	}
	my $designations = {};
	my $seqs         = {};
	my $paralogous   = {};
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
			if ( $self->{'options'}->{'align'} ) {
				$seqs->{$locus} = $self->_get_seqs_from_matches( $locus, $sorted_allele_ids, $exact_matches->{$locus} );
			}
			if ( @$sorted_allele_ids > 1 ) {
				$paralogous->{$locus} = 1;
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
	$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/$_*") foreach ( $isolate_prefix, $locus_prefix );
	return ( $designations, $seqs, $paralogous );
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
	my %null_alleles = map { $_ => 1 } qw (0 N);
	foreach my $locus ( keys %$designations ) {
		my @allele_ids = split /;/x, $designations->{$locus};
		foreach my $allele_id (@allele_ids) {
			if ( $null_alleles{$allele_id} ) {
				next;
			} else {
				my $seq_ref = $self->{'datastore'}->get_locus($locus)->get_allele_sequence($allele_id);
				$seqs->{$locus} .= $$seq_ref // q();
			}
		}
	}
	return $seqs;
}

sub _get_seqs_from_matches {
	my ( $self, $locus, $allele_ids, $matches ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $seq;
	if ( $locus_info->{'data_type'} eq 'DNA' && $locus_info->{'dbase_name'} ) {
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
	my $seqbin_length = $self->{'contigManager'}->get_contig_length( $match->{'seqbin_id'} );
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
	my $by_ref = $self->{'options'}->{'reference_file'} ? 1 : 0;
	if ( !$by_ref ) {    #Scan by defined loci
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		if ( $locus_info->{'data_type'} eq 'peptide' ) {
			$seq_ref = $self->_translate($seq_ref);
		}
	}
	my $hash = Digest::MD5::md5_hex($$seq_ref);
	$self->{'seq_lookup'}->{$locus}    //= {};
	$self->{'allele_lookup'}->{$locus} //= {};
	if ( $self->{'allele_lookup'}->{$locus}->{$hash} ) {
		return $self->{'allele_lookup'}->{$locus}->{$hash};
	}
	my $i = $by_ref ? 2 : 1;
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
