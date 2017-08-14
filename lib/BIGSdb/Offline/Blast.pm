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
package BIGSdb::Offline::Blast;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Offline::Script);
use BIGSdb::Constants qw(IDENTITY_THRESHOLD);
use Digest::MD5;
use File::Path qw(make_path remove_tree);
use Error qw(:try);
use Fcntl qw(:flock);
use constant INF => 9**99;

sub blast {
	my ( $self, $seq_ref, $args ) = @_;
	my $params  = $self->{'params'};
	my $options = $self->{'options'};

	#Clear stored results as we can make multiple calls against the same BLAST database object.
	undef $self->{'contigs'};
	undef $self->{'exact_matches'};
	undef $self->{'partial_matches'};
	my $loci = $self->get_selected_loci;
	throw BIGSdb::DataException('Invalid loci') if !@$loci;
	my $seq = $$seq_ref;    #Don't modify scalar ref as it may be needed by calling method
	$self->ensure_seq_has_identifer( \$seq );
	$seq_ref = $self->_strip_invalid_chars( \$seq );
	$self->{'seq_ref'} = $seq_ref;
	my $blast_results = $self->_run_blast( \$seq, $loci, $args );

	if ( $args->{'alignment'} ) {
		return $blast_results;
	}
	my $exact_matches = $self->_parse_blast_exact(
		{
			loci       => $loci,
			params     => $params,
			blast_file => $blast_results,
			options    => { keep_data => 1 }
		}
	);
	my $partial_matches = $self->_parse_blast_partial(
		{
			loci          => $loci,
			params        => $params,
			blast_file    => $blast_results,
			exact_matches => $exact_matches,
			seq_ref       => $seq_ref,
			options       => { keep_partials => $options->{'keep_partials'} }
		}
	);
	$self->{'exact_matches'}   = $exact_matches;
	$self->{'partial_matches'} = $partial_matches;
	unlink $blast_results;
	return;
}

sub _get_cache_names {
	my ($self) = @_;
	my $dir = "$self->{'config'}->{'secure_tmp_dir'}/$self->{'system'}->{'db'}";
	my @caches;
	return [] if !-d $dir;
	opendir( my $dh, $dir ) || $self->{'logger'}->error("Cannot open directory $dir");
	while ( my $name = readdir $dh ) {
		next if $name =~ /^\./x;
		next if !-d "$dir/$name";
		push @caches, $name;
	}
	closedir $dh;
	return \@caches;
}

sub create_scheme_cache {
	my ( $self, $scheme_id ) = @_;
	my $loci;
	if ($scheme_id) {
		$loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	} else {
		$loci = $self->{'datastore'}->get_loci;
	}
	my $runs = [qw(DNA peptide)];
	my $exemplars = ( $self->{'system'}->{'exemplars'} // q() ) eq 'yes' ? 1 : 0;
	foreach my $run (@$runs) {
		my $loci_by_type = $self->_get_selected_loci_by_type( $loci, $run );
		next if !@$loci_by_type;
		my $cache_name = $self->_get_cache_name( $loci_by_type, { exemplar => $exemplars } );
		if ( !$self->_cache_exists($cache_name) ) {
			$self->_create_blast_database( $cache_name, $run, $loci_by_type, $exemplars );
		}
	}
	return;
}

sub delete_caches {
	my ( $self, $options ) = @_;
	my $caches = $self->_get_cache_names;
	foreach my $cache (@$caches) {
		if ( $options->{'single_locus'} ) {
			my $loci = $self->_get_cache_loci($cache);
			next if @$loci > 1;
		}
		if ( $options->{'if_stale'} ) {
			$self->_delete_cache_if_stale($cache);
		} else {
			$self->_delete_cache($cache);
		}
	}
	return;
}

sub mark_locus_caches_stale {
	my ( $self, $locus ) = @_;
	my $caches = $self->_get_caches_containing_locus($locus);
	foreach my $cache (@$caches) {
		my $dir             = $self->_get_cache_dir($cache);
		my $stale_flag_file = "$dir/stale";
		open( my $fh, '>', $stale_flag_file ) || $self->{'logger'}->error("Cannot mark $cache cache stale.");
		close $fh;
	}
	return;
}

sub _get_caches_containing_locus {
	my ( $self, $locus ) = @_;
	my $dir          = "$self->{'config'}->{'secure_tmp_dir'}/$self->{'system'}->{'db'}";
	my $caches       = $self->_get_cache_names;
	my $locus_caches = [];
  CACHE: foreach my $cache (@$caches) {
		my $locus_file = "$dir/$cache/loci";
		next if !-e $locus_file;
		open( my $fh, '<', $locus_file ) || $self->{'logger'}->error("Cannot open $locus_file for reading");
		while ( my $line = <$fh> ) {
			chomp $line;
			if ( $line eq $locus ) {
				push @$locus_caches, $cache;
				next CACHE;
			}
		}
		close $fh;
	}
	return $locus_caches;
}

sub _get_matches {
	my ( $self, $type, $options ) = @_;
	return $self->{$type} if $options->{'details'};
	my $alleles = {};
	foreach my $locus ( keys %{ $self->{$type} } ) {
		my $allele_ids = [];
		foreach my $match ( @{ $self->{$type}->{$locus} } ) {
			push @$allele_ids, $match->{'allele'};
		}
		$alleles->{$locus} = $allele_ids;
	}
	return $alleles;
}

sub get_exact_matches {
	my ( $self, $options ) = @_;
	return $self->_get_matches( 'exact_matches', $options );
}

sub get_partial_matches {
	my ( $self, $options ) = @_;
	return $self->_get_matches( 'partial_matches', $options );
}

sub get_best_partial_match {
	my ($self)          = @_;
	my $partial_matches = $self->{'partial_matches'};
	my $best_match      = {};
	my $bitscore        = 0;
	foreach my $locus ( keys %$partial_matches ) {
		foreach my $match ( @{ $partial_matches->{$locus} } ) {
			if ( $match->{'bitscore'} > $bitscore ) {
				$best_match            = $match;
				$best_match->{'locus'} = $locus;
				$bitscore              = $match->{'bitscore'};
			}
		}
	}
	if ( $self->{'seq_ref'} && keys %$best_match ) {
		my $seq = $self->_extract_match_seq_from_query( $self->{'seq_ref'}, $best_match );
		$best_match->{'sequence'} = $seq;
	}
	return $best_match;
}

sub get_contig {
	my ( $self, $name ) = @_;
	my $contig = $self->{'contigs'}->{$name} // q();
	return \$contig;
}

sub _create_query_file {
	my ( $self, $in_file, $seq_ref ) = @_;
	open( my $infile_fh, '>', $in_file ) || $self->{'logger'}->error("Cannot open $in_file for writing");
	say $infile_fh $$seq_ref;
	close $infile_fh;
	return;
}

sub _run_blast {
	my ( $self, $seq_ref, $loci, $args ) = @_;
	my $job      = BIGSdb::Utils::get_random();
	my $in_file  = "$self->{'config'}->{'secure_tmp_dir'}/$job.txt";
	my $out_file = "$self->{'config'}->{'secure_tmp_dir'}/${job}_outfile.txt";
	my $options  = $self->{'options'};
	$self->_create_query_file( $in_file, $seq_ref );
	my $runs = [qw(DNA peptide)];
	foreach my $run (@$runs) {
		my $loci_by_type = $self->_get_selected_loci_by_type( $loci, $run );
		next if !@$loci_by_type;
		my $cache_name = $self->_get_cache_name($loci_by_type);
		if ( !$self->_cache_exists($cache_name) ) {
			$self->_create_blast_database( $cache_name, $run, $loci_by_type, $options->{'exemplar'} );
		}
		my $path      = $self->_get_cache_dir($cache_name);
		my $lock_file = "$path/LOCK";
		if ( -e $lock_file ) {

			#Wait for lock to clear - database is being created by other process.
			open( my $lock_fh, '<', $lock_file ) || $self->{'logger'}->error('Cannot open lock file.');
			flock( $lock_fh, LOCK_SH ) or $self->{'logger'}->error("Cannot flock $lock_file: $!");
			close $lock_fh;
		}
		my $qry_type = BIGSdb::Utils::sequence_type($seq_ref);
		my $program = $self->_determine_blast_program( $run, $qry_type );
		$self->{'program'} = $program;
		my $blast_threads = $options->{'threads'} // $self->{'config'}->{'blast_threads'} // 1;
		my $filter = $program eq 'blastn' ? 'dust' : 'seg';
		my $word_size = $program eq 'blastn' ? ( $options->{'word_size'} // 15 ) : 3;
		my $format = $args->{'alignment'} ? 0 : 6;
		$options->{'num_results'} //= 1_000_000;    #effectively return all results
		my $fasta_file = "$path/sequences.fas";
		open( my $fasta_fh, '<', $fasta_file ) || $self->{'logger'}->error("Cannot open $fasta_file for reading");

		#Open shared lock on FASTA file to prevent cache being deleted while being used.
		flock( $fasta_fh, LOCK_SH ) || $self->{'logger'}->error("Cannot flock $fasta_file");
		my %params = (
			-num_threads => $blast_threads,
			-word_size   => $word_size,
			-db          => $fasta_file,
			-query       => $in_file,
			-out         => $out_file,
			-outfmt      => $format,
			-$filter     => 'no'
		);
		$options->{'num_results'} = $args->{'num_results'} if $args->{'num_results'};
		if ( $args->{'alignment'} ) {
			$params{'-num_alignments'} = $options->{'num_results'};
		} else {
			$params{'-max_target_seqs'} = $options->{'num_results'};
		}

		#Ensure matches with low-complexity regions are returned.
		if ( $program ne 'blastn' && $program ne 'tblastx' ) {
			$params{'-comp_based_stats'} = 0;
		}

		#Very short sequences won't be matched unless we increase the expect value significantly
		my $shortest_seq = $self->_get_shortest_seq_length($fasta_file);
		if ( $shortest_seq <= 20 ) {
			$params{'-evalue'} = 1000;
		}
		system( "$self->{'config'}->{'blast+_path'}/$program", %params );
		close $fasta_fh;
		next if !-e $out_file;
		if ( $run eq 'DNA' ) {
			rename( $out_file, "${out_file}.1" );
		}
	}
	my $out_file1 = "${out_file}.1";
	if ( -e $out_file1 ) {
		BIGSdb::Utils::append( $out_file1, $out_file );
		unlink $out_file1;
	}
	unlink $in_file;
	return $out_file;
}

sub _parse_blast_exact {
	my ( $self, $args ) = @_;
	my ( $params, $loci, $blast_file, $options ) =
	  @{$args}{qw (params loci blast_file options)};
	my $matches = {};
	$self->_read_blast_file_into_structure($blast_file);
	my $matched_already = {};
	my $length_cache    = {};
  RECORD: foreach my $record ( @{ $self->{'records'} } ) {
		my $match;
		if ( $record->[2] == 100 ) {    #identity
			my $allele_id;
			my ( $locus, $match_allele_id ) = split( /\|/x, $record->[1], 2 );
			$locus =~ s/__prime__/'/gx;
			my $locus_match = $matches->{'locus'} // [];
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			$allele_id = $match_allele_id;
			if ( !$length_cache->{$locus}->{$allele_id} ) {
				$length_cache->{$locus}->{$allele_id} = $self->{'datastore'}->run_query(
					'SELECT length(sequence) FROM sequences WHERE (locus,allele_id)=(?,?)',
					[ $locus, $allele_id ],
					{ cache => 'Blast::get_seq_length' }
				);
			}
			my $ref_length = $length_cache->{$locus}->{$allele_id};
			next if !defined $ref_length;
			if ( $self->_does_blast_record_match( $record, $ref_length ) ) {
				$match->{'query'}     = $record->[0];
				$match->{'allele'}    = $allele_id;
				$match->{'identity'}  = $record->[2];
				$match->{'alignment'} = $params->{'tblastx'} ? ( $record->[3] * 3 ) : $record->[3];
				$match->{'length'}    = $ref_length;
				$self->_identify_match_ends( $match, $record );
				$match->{'reverse'} = 1 if $self->_is_match_reversed($record);
				$match->{'e-value'} = $record->[10];
				next RECORD if $matched_already->{ $match->{'allele'} }->{ $match->{'start'} };
				$matched_already->{ $match->{'allele'} }->{ $match->{'start'} } = 1;

				if ( $locus_info->{'match_longest'} && @$locus_match ) {
					if ( $match->{'length'} > $locus_match->[0]->{'length'} ) {
						@$locus_match = ($match);
					}
				} else {
					push @$locus_match, $match;
				}
			}
			$matches->{$locus} = $locus_match if @$locus_match;
		}
	}
	undef $self->{'records'} if !$options->{'keep_data'};
	return $matches;
}

sub _parse_blast_partial {
	my ( $self, $args ) = @_;
	my ( $params, $loci, $blast_file, $exact_matches, $seq_ref, $options ) =
	  @{$args}{qw (params loci blast_file exact_matches seq_ref options)};
	my $partial_matches = {};
	my $identity        = $self->{'options'}->{'identity'};
	my $alignment       = $self->{'options'}->{'alignment'};
	$identity  = 50 if !BIGSdb::Utils::is_int($identity);
	$alignment = 50 if !BIGSdb::Utils::is_int($alignment);
	$self->_read_blast_file_into_structure($blast_file);
	my $length_cache = {};
  RECORD: foreach my $record ( @{ $self->{'records'} } ) {
		my $allele_id;
		my ( $locus, $match_allele_id ) = split( /\|/x, $record->[1], 2 );
		next if $exact_matches->{$locus} && !$self->{'options'}->{'exemplar'} && !$self->{'options'}->{'find_similar'};
		my $locus_match = $partial_matches->{$locus} // [];
		$allele_id = $match_allele_id;
		if ( $self->{'program'} =~ /tblast/x ) {
			$record->[3] *= 3;
		}
		if ( $record->[2] >= $identity ) {
			if ( !$length_cache->{$locus}->{$allele_id} ) {
				$length_cache->{$locus}->{$allele_id} = $self->{'datastore'}->run_query(
					'SELECT length(sequence) FROM sequences WHERE (locus,allele_id)=(?,?)',
					[ $locus, $allele_id ],
					{ cache => 'Blast::get_seq_length' }
				);
			}
			my $length = $length_cache->{$locus}->{$allele_id};
			if ( $record->[3] >= $alignment * 0.01 * $length ) {
				my $match;
				$match->{'query'}      = $record->[0];
				$match->{'allele'}     = $allele_id;
				$match->{'identity'}   = $record->[2];
				$match->{'length'}     = $length;
				$match->{'mismatches'} = $record->[4];
				$match->{'gaps'}       = $record->[5];
				$match->{'qstart'}     = $record->[6];
				$match->{'qend'}       = $record->[7];
				$match->{'sstart'}     = $record->[8];
				$match->{'send'}       = $record->[9];
				$match->{'bitscore'}   = $record->[11];
				$match->{'alignment'}  = $params->{'tblastx'} ? ( $record->[3] * 3 ) : $record->[3];
				$match->{'reverse'}    = 1 if $self->_is_match_reversed($record);
				$self->_identify_match_ends( $match, $record );
				$self->_predict_allele_ends( $length, $match, $record );
				push @$locus_match, $match;
			}
		}
		$partial_matches->{$locus} = $locus_match if @$locus_match;
	}
	if ( $self->{'options'}->{'exemplar'} ) {
		foreach my $locus (@$loci) {
			$self->_lookup_partial_matches( $seq_ref, $locus, $exact_matches, $partial_matches );
			if ( ref $exact_matches->{$locus} && @{ $exact_matches->{$locus} } ) {
				if ( !$options->{'keep_partials'} ) {
					delete $partial_matches->{$locus};
				}
			} else {
				delete $exact_matches->{$locus};
			}
		}
	}
	undef $self->{'records'} if !$options->{'keep_data'};
	return $partial_matches;
}

sub _lookup_partial_matches {
	my ( $self, $seq_ref, $locus, $exact_matches, $partial_matches ) = @_;
	my $locus_matches = $partial_matches->{$locus} // [];
	return if !@$locus_matches;
	my %already_matched_alleles = map { $_->{'allele'} => 1 } @{ $exact_matches->{$locus} };
	my $locus_info              = $self->{'datastore'}->get_locus_info($locus);
	my $qry_type                = BIGSdb::Utils::sequence_type($seq_ref);
	foreach my $match (@$locus_matches) {
		my $seq = $self->_extract_match_seq_from_query( $seq_ref, $match );
		if ( $locus_info->{'data_type'} eq 'peptide' && $qry_type eq 'DNA' ) {
			my $seq_obj = Bio::Seq->new( -seq => $seq, -alphabet => 'dna' );
			$seq = $seq_obj->translate->seq;
		}
		my $allele_id = $self->{'datastore'}
		  ->run_query( 'SELECT allele_id FROM sequences WHERE (locus,md5(sequence))=(?,md5(?))', [ $locus, $seq ] );
		if ( defined $allele_id && !$already_matched_alleles{$allele_id} ) {
			$match->{'from_partial'}         = 1;
			$match->{'partial_match_allele'} = $match->{'allele'};
			$match->{'identity'}             = 100;
			$match->{'allele'}               = $allele_id;
			$match->{'start'}                = $match->{'predicted_start'};
			$match->{'end'}                  = $match->{'predicted_end'};
			$match->{'length'}               = abs( $match->{'predicted_end'} - $match->{'predicted_start'} ) + 1;
			if ( $locus_info->{'match_longest'} && @{ $exact_matches->{$locus} } ) {

				if ( $match->{'length'} > $exact_matches->{$locus}->[0]->{'length'} ) {
					@{ $exact_matches->{$locus} } = ($match);
				}
			} else {
				push @{ $exact_matches->{$locus} }, $match;
				$already_matched_alleles{$allele_id} = 1;
			}
		}
	}
	return;
}

sub _extract_match_seq_from_query {
	my ( $self, $seq_ref, $match ) = @_;
	if ( !$self->{'contigs'} ) {
		$self->{'contigs'} = BIGSdb::Utils::read_fasta( $seq_ref, { allow_peptide => 1 } );
	}
	my $length = $match->{'predicted_end'} - $match->{'predicted_start'} + 1;
	my $seq =
	  substr( $self->{'contigs'}->{ $match->{'query'} }, $match->{'predicted_start'} - 1, $length );
	$seq = BIGSdb::Utils::reverse_complement($seq) if $match->{'reverse'};
	$seq = uc($seq);
	return $seq;
}

sub _does_blast_record_match {
	my ( $self, $record, $ref_length ) = @_;
	return 1
	  if (
		(
			$record->[8] == 1                 #sequence start position
			&& $record->[9] == $ref_length    #end position
		)
		|| (
			$record->[8] == $ref_length       #sequence start position (reverse complement)
			&& $record->[9] == 1              #end position
		)
	  ) && !$record->[4];                     #no gaps
	return;
}

sub _identify_match_ends {
	my ( $self, $match, $record ) = @_;
	if ( $record->[6] < $record->[7] ) {
		$match->{'start'} = $record->[6];
		$match->{'end'}   = $record->[7];
	} else {
		$match->{'start'} = $record->[7];
		$match->{'end'}   = $record->[6];
	}
	return;
}

sub _predict_allele_ends {
	my ( $self, $length, $match, $record ) = @_;
	if ( $length != $match->{'alignment'} ) {
		if ( $match->{'reverse'} ) {
			if ( $record->[8] < $record->[9] ) {
				$match->{'predicted_start'} = $match->{'start'} - $length + $record->[9];
				$match->{'predicted_end'}   = $match->{'end'} + $record->[8] - 1;
			} else {
				$match->{'predicted_start'} = $match->{'start'} - $length + $record->[8];
				$match->{'predicted_end'}   = $match->{'end'} + $record->[9] - 1;
			}
		} else {
			if ( $record->[8] < $record->[9] ) {
				$match->{'predicted_start'} = $match->{'start'} - $record->[8] + 1;
				$match->{'predicted_end'}   = $match->{'end'} + $length - $record->[9];
			} else {
				$match->{'predicted_start'} = $match->{'start'} - $record->[9] + 1;
				$match->{'predicted_end'}   = $match->{'end'} + $length - $record->[8];
			}
		}
	} else {
		$match->{'predicted_start'} = $match->{'start'};
		$match->{'predicted_end'}   = $match->{'end'};
	}
	return;
}

#Record represents field values from BLAST output
sub _is_match_reversed {
	my ( $self, $record ) = @_;
	if (   ( $record->[8] > $record->[9] && $record->[7] > $record->[6] )
		|| ( $record->[8] < $record->[9] && $record->[7] < $record->[6] ) )
	{
		return 1;
	}
	return;
}

sub _read_blast_file_into_structure {
	my ( $self, $blast_file ) = @_;
	if ( !$self->{'records'} ) {
		open( my $blast_fh, '<', $blast_file )
		  || ( $self->{'logger'}->error("Cannot open BLAST output file $blast_file. $!"), return \$; );
		$self->{'records'} = [];
		my @lines = <$blast_fh>;
		foreach my $line (@lines) {
			my @record = split /\s+/x, $line;
			push @{ $self->{'records'} }, \@record;
		}
		close $blast_fh;
	}
	return;
}

sub _get_shortest_seq_length {
	my ( $self, $fasta ) = @_;
	my $shortest = INF;
	open( my $fh, '<', $fasta ) || $self->{'logger'}->error("Cannot open $fasta for reading");
	while ( my $line = <$fh> ) {
		next if $line =~ /^>/x;
		chomp $line;
		my $length = length $line;
		$shortest = $length if $length < $shortest;
	}
	close $fh;
	return $shortest;
}

sub ensure_seq_has_identifer {
	my ( $self, $seq_ref ) = @_;
	if ( $$seq_ref !~ /^\s*>/x ) {
		$$seq_ref = qq(>Query\n$$seq_ref);
	}
	return;
}

sub _strip_invalid_chars {
	my ( $self, $seq_ref ) = @_;
	my @lines = split /\n/x, $$seq_ref;
	my $new_seq = q();
	foreach my $line (@lines) {
		if ( $line !~ /^>/x ) {
			$line =~ s/\s//gx;
			$line =~ s/\-//gx;
		} else {
			$line =~ s/\s*$//x;
		}
		$new_seq .= qq($line\n);
	}
	return \$new_seq;
}

sub _create_blast_database {
	my ( $self, $cache_name, $data_type, $loci, $exemplar ) = @_;
	my $path = $self->_get_cache_dir($cache_name);
	make_path($path);

	#This method may be called by apache during a web query, by the bigsdb or any other user
	#if called from external script. We need to make sure that cache files can be overwritten
	#by all.
	chmod 0777, "$self->{'config'}->{'secure_tmp_dir'}/$self->{'system'}->{'db'}", $path;

	#Prevent two makeblastdb processes running in the same directory.
	my $lock_file = "$path/LOCK";
	open( my $lock_fh, '>', $lock_file ) || $self->{'logger'}->error('Cannot open lock file');
	if ( !flock( $lock_fh, LOCK_EX ) ) {
		$self->{'logger'}->error("Cannot flock $lock_file: $!");
		return;
	}
	my $list_table = $self->{'datastore'}->create_temp_list_table_from_array( 'text', $loci );
	my $qry = q(SELECT locus,allele_id,sequence from sequences WHERE locus IN )
	  . qq((SELECT value FROM $list_table) AND allele_id NOT IN ('N','0'));
	$qry .= ' AND exemplar' if $exemplar;
	my $data = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref' } );
	my $fasta_file = "$path/sequences.fas";
	unlink $fasta_file;    #Recreate rather than overwrite to ensure both apache and bigsdb users can write
	my $fasta_fh;

	if ( !open( $fasta_fh, '>', $fasta_file ) ) {
		$self->{'logger'}->error("Cannot open $fasta_file for writing");
		return;
	}
	flock( $fasta_fh, LOCK_EX ) or $self->{'logger'}->error("Cannot flock $fasta_file: $!");
	foreach my $allele (@$data) {
		say $fasta_fh ">$allele->[0]|$allele->[1]\n$allele->[2]";
	}
	close $fasta_fh;
	chmod 0666, $fasta_file;
	my $db_type = $data_type eq 'DNA' ? 'nucl' : 'prot';
	system( "$self->{'config'}->{'blast+_path'}/makeblastdb",
		( -in => $fasta_file, -logfile => '/dev/null', -dbtype => $db_type ) );
	my $locus_list_file = "$path/loci";
	my $locus_fh;
	if ( !open( $locus_fh, '>', $locus_list_file ) ) {
		$self->{'logger'}->error("Cannot open $locus_list_file for writing");
		return;
	}
	say $locus_fh $_ foreach @$loci;
	close $locus_fh;
	if ($lock_fh) {
		close $lock_fh;
		unlink $lock_file;
	}
	return;
}

sub _get_cache_dir {
	my ( $self, $cache_name ) = @_;
	my $dir = "$self->{'config'}->{'secure_tmp_dir'}/$self->{'system'}->{'db'}/$cache_name";
	if ( $dir =~ /(.+)/x ) {
		return $1;    #Untaint
	}
	return $dir;
}

sub _cache_exists {
	my ( $self, $cache_name ) = @_;
	my $path = $self->_get_cache_dir($cache_name);
	return if !-e $path;
	return if $self->_delete_cache_if_stale($cache_name);
	return 1;
}

sub _delete_cache_if_stale {
	my ( $self, $cache_name ) = @_;
	my $path           = $self->_get_cache_dir($cache_name);
	my $cache_is_stale = -e "$path/stale";
	my $cache_age      = $self->_get_cache_age($cache_name);
	if ( $cache_age > $self->{'config'}->{'cache_days'} || $cache_is_stale ) {
		$self->_delete_cache($cache_name);
		return 1;
	}
	return;
}

sub _get_cache_age {
	my ( $self, $cache_name ) = @_;
	my $path       = $self->_get_cache_dir($cache_name);
	my $fasta_file = "$path/sequences.fas";
	return 0 if !-e $fasta_file;
	return -M $fasta_file;
}

sub _delete_cache {
	my ( $self, $cache_name ) = @_;
	$self->{'logger'}->info("Deleting cache $cache_name");
	my $path       = $self->_get_cache_dir($cache_name);
	my $fasta_file = "$path/sequences.fas";
	my $fasta_fh;
	if ( !open( $fasta_fh, '>', $fasta_file ) ) {
		$self->{'logger'}->error("Cannot open $fasta_file for writing");
		return;
	}
	if ( flock( $fasta_fh, LOCK_EX ) ) {
		remove_tree( $path, { error => \my $err } );
		if (@$err) {
			$self->{'logger'}->error("Cannot remove cache directory $path");
		}
	} else {
		$self->{'logger'}->error("Cannot flock $fasta_file: $!");
	}
	return;
}

sub _get_cache_name {
	my ( $self, $loci, $options ) = @_;
	my $exemplar_value = ( $options->{'exemplar'} // $self->{'options'}->{'exemplar'} ) ? q(EX) : q();
	local $" = q(,);
	my $hash = Digest::MD5::md5_hex(qq(@$loci));
	return "$exemplar_value$hash";
}

sub _get_selected_loci_by_type {
	my ( $self, $selected_loci, $type ) = @_;
	my $by_type =
	  $self->{'datastore'}->run_query( 'SELECT id FROM loci WHERE data_type=?', $type, { fetch => 'col_arrayref' } );
	my %by_type = map { $_ => 1 } @$by_type;
	my $loci_of_type = [];
	foreach my $locus (@$selected_loci) {
		push @$loci_of_type, $locus if $by_type{$locus};
	}
	return $loci_of_type;
}

sub _determine_blast_program {
	my ( $self, $blast_db_type, $qry_type ) = @_;
	if ( $blast_db_type eq 'DNA' ) {
		return $qry_type eq 'DNA' ? 'blastn' : 'tblastn';
	} else {
		return $qry_type eq 'DNA' ? 'blastx' : 'blastp';
	}
}

#Recreate any cache that is either marked stale or is older than age specified
#in bigsdb.conf.
sub refresh_caches {
	my ( $self, $options ) = @_;
	my $dir    = "$self->{'config'}->{'secure_tmp_dir'}/$self->{'system'}->{'db'}";
	my $caches = $self->_get_cache_names;
  CACHE: foreach my $cache_name (@$caches) {
		my $loci = $self->_get_cache_loci($cache_name);
		if ( !$self->_cache_exists($cache_name) ) {    #Will delete cache if stale or old.
			my %data_types;
			foreach my $locus (@$loci) {
				my $locus_info = $self->{'datastore'}->get_locus_info($locus);
				if ( !$locus_info ) {
					$self->{'logger'}->error("Locus $locus does not exist for cache.");
					next CACHE;
				}
				$data_types{ $locus_info->{'data_type'} } = 1;
			}
			if ( keys %data_types > 1 ) {
				$self->{'logger'}->error("Cache $cache_name contains DNA and peptide loci. Cannot create.");
				next CACHE;
			}
			my $exemplar = $cache_name =~ /^EX/x ? 1 : 0;
			my ($data_type) = keys %data_types;
			$self->_create_blast_database( $cache_name, $data_type, $loci, $exemplar );
		}
	}
	return;
}

sub _get_cache_loci {
	my ( $self, $cache_name ) = @_;
	my $locus_file = "$self->{'config'}->{'secure_tmp_dir'}/$self->{'system'}->{'db'}/$cache_name/loci";
	if ( !-e $locus_file ) {
		$self->{'logger'}->error("Locus file $locus_file does not exist");
		return;
	}
	my $loci = [];
	open( my $fh, '<', $locus_file ) || $self->{'logger'}->error("Cannot open locus file $locus_file");
	while ( my $locus = <$fh> ) {
		chomp $locus;
		push @$loci, $locus;
	}
	close $fh;
	return $loci;
}

sub check_sequence_similarity {

 #returns hashref with the following keys
 #similar          - true if sequence is at least IDENTITY_THRESHOLD% identical over an alignment length of 90% or more.
 #subsequence_of   - allele id of sequence that this is larger than query sequence but otherwise identical.
 #supersequence_of - allele id of sequence that is smaller than query sequence but otherwise identical.
	my ($self) = @_;
	my $loci = $self->get_selected_loci;
	if ( @$loci > 1 ) {
		$self->{'logger'}->error('Multiple loci selected - using first one.');
	}
	my $locus      = $loci->[0];
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $id_threshold =
	  BIGSdb::Utils::is_float( $locus_info->{'id_check_threshold'} )
	  ? $locus_info->{'id_check_threshold'}
	  : IDENTITY_THRESHOLD;
	my $length = length $self->_get_stripped_sequence;
	my ( $similar, $subsequence_of, $supersequence_of ) = ( 0, undef, undef );
	my $match = $self->get_best_partial_match;
	my ( $allele_id, $identity, $reversed, $alignment ) = @{$match}{qw(allele identity reverse alignment)};

	if ( !$reversed && defined $identity && $identity >= $id_threshold && $alignment >= 0.9 * $length ) {
		$similar = 1;
		if ( $identity == 100 ) {
			my $matched_seq_ref = $self->{'datastore'}->get_sequence( $locus, $allele_id );
			my $length_of_matched_seq = length $$matched_seq_ref;
			if ( $length == $alignment && $length < $length_of_matched_seq ) {
				$subsequence_of = $allele_id;
			} elsif ( $length_of_matched_seq == $alignment && $length > $length_of_matched_seq ) {
				$supersequence_of = $allele_id;
			}
		}
	}
	return { similar => $similar, subsequence_of => $subsequence_of, supersequence_of => $supersequence_of };
}

sub _get_stripped_sequence {
	my ($self) = @_;
	my @lines = split /\n/x, ${ $self->{'seq_ref'} };
	my $new_seq = q();
	foreach my $line (@lines) {
		next if $line =~ /^>/x;
		$new_seq .= $line;
	}
	return $new_seq;
}
1;
