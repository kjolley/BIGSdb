#Written by Keith Jolley
#Copyright (c) 2010-2019, University of Oxford
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
package BIGSdb::Offline::Scan;
use strict;
use warnings;
use 5.010;
no warnings 'io';    #Prevent false warning message about STDOUT being reopened.
use parent qw(BIGSdb::Offline::Script BIGSdb::CuratePage);
use Data::Dumper;
use BIGSdb::Exceptions;
use List::MoreUtils qw(any);
use Try::Tiny;
use Fcntl qw(:flock);
use Bio::Seq;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Scan');
use BIGSdb::Constants qw(SEQ_METHODS SEQ_FLAGS LOCUS_PATTERN);
use constant INF => 9**99;

sub _get_word_size {
	my ( $self, $program, $locus, $params ) = @_;
	my $blastn_word_size;
	if ( defined $params->{'word_size'} && $params->{'word_size'} =~ /(\d+)/x ) {
		$blastn_word_size = $1;
	} else {
		$blastn_word_size = 20;
	}

	#If we're looking for exact matches only we can set the word size to the smallest length of an allele
	if ( $locus && $params->{'exact_matches_only'} && defined $self->{'min_allele_length'}->{$locus} ) {
		$blastn_word_size = $self->{'min_allele_length'}->{$locus}
		  if $self->{'min_allele_length'}->{$locus} > $blastn_word_size;
	}
	my $word_size = $program eq 'blastn' ? $blastn_word_size : 3;
	return $word_size;
}

sub _get_program {
	my ( $self, $locus_data_type, $params ) = @_;
	if ( $locus_data_type eq 'DNA' ) {
		return $params->{'tblastx'} ? 'tblastx' : 'blastn';
	} else {
		return 'blastx';
	}
}

sub blast_multiple_loci {
	my ( $self, $params, $loci, $isolate_id, $isolate_prefix, $locus_prefix ) = @_;
	my $temp_infile  = "$self->{'config'}->{'secure_tmp_dir'}/${isolate_prefix}_file.txt";
	my $temp_outfile = "$self->{'config'}->{'secure_tmp_dir'}/${isolate_prefix}_${$}_outfile.txt";
	$self->_create_query_fasta_file( $isolate_id, $temp_infile, $params );
	my $datatype_exact_matches   = {};
	my $datatype_partial_matches = {};
	my $probe_matches            = {};
	my $pcr_products             = {};
	my $pcr_filter               = {};
	my $probe_filter             = {};
  DATATYPE: foreach my $data_type (qw(DNA peptide)) {
		$datatype_exact_matches->{$data_type}   = {};
		$datatype_partial_matches->{$data_type} = {};
		my @locus_list;
	  LOCUS: foreach my $locus (@$loci) {
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			next LOCUS if $locus_info->{'data_type'} ne $data_type;
			my $continue = 1;
			try {
				$pcr_products->{$locus} = $self->_get_pcr_products( $locus, $temp_infile, $params );
				$probe_matches->{$locus} = $self->_get_probe_matches( $locus, $temp_infile, $params );
			}
			catch {
				if ( $_->isa('BIGSdb::Exception::Data') ) {
					$continue = 0;
				} else {
					$logger->logdie($_);
				}
			};
			next LOCUS if !$continue;
			$pcr_filter->{$locus}   = !$params->{'pcr_filter'}   ? 0 : $locus_info->{'pcr_filter'};
			$probe_filter->{$locus} = !$params->{'probe_filter'} ? 0 : $locus_info->{'probe_filter'};
			push @locus_list, $locus;
		}
		next DATATYPE if !@locus_list;
		my $program = $self->_get_program( $data_type, $params );
		my $temp_fastafile = "$self->{'config'}->{'secure_tmp_dir'}/${locus_prefix}_fastafile_$data_type.txt";
		$self->_create_fasta_index( \@locus_list, $temp_fastafile,
			{ exemplar => $params->{'exemplar'}, multiple_loci => 1 } );
		return if !-e $temp_fastafile || -z $temp_fastafile;
		$self->{'db'}->commit;    #prevent idle in transaction table locks
		my $word_size = $self->_get_word_size( $program, undef, $params );
		my $blast_threads = $self->{'config'}->{'blast_threads'} || 1;
		my $filter = $program eq 'blastn' ? 'dust' : 'seg';
		my %params = (
			-num_threads     => $blast_threads,
			-max_target_seqs => 1000 *
			  @locus_list,   #Set high for longer alleles that partially match and score higher than exact short alleles
			-word_size => $word_size,
			-db        => $temp_fastafile,
			-query     => $temp_infile,
			-out       => $temp_outfile,
			-outfmt    => 6,
			-$filter   => 'no',
		);

		#Will not return some matches with low-complexity regions otherwise.
		$params{'-comp_based_stats'} = 0
		  if $program ne 'blastn'
		  && $program ne 'tblastx';

		#Very short sequences won't be matched unless we increase the expect value significantly
		my $shortest_seq = $self->_get_shortest_seq_length($temp_fastafile);
		if ( $shortest_seq <= 20 ) {
			$params{'-evalue'} = 1000;
		}
		system( "$self->{'config'}->{'blast+_path'}/$program", %params );
		next DATATYPE if !-e $temp_outfile;
		my $matched_regions;
		( $datatype_exact_matches->{$data_type}, $matched_regions ) = $self->_parse_blast_exact(
			{
				params        => $params,
				blast_file    => "${isolate_prefix}_${$}_outfile.txt",
				pcr_filter    => $pcr_filter,
				pcr_products  => $pcr_products,
				probe_filter  => $probe_filter,
				probe_matches => $probe_matches,
				options       => { multiple_loci => 1, keep_data => 1 }
			}
		);
		$datatype_partial_matches->{$data_type} = $self->_parse_blast_partial(
			{
				params                => $params,
				exact_matched_regions => $matched_regions,
				blast_file            => "${isolate_prefix}_${$}_outfile.txt",
				pcr_filter            => $pcr_filter,
				pcr_products          => $pcr_products,
				probe_filter          => $probe_filter,
				probe_matches         => $probe_matches,
				options               => { multiple_loci => 1 }
			}
		);
	  LOCUS: foreach my $locus (@locus_list) {
			if ( $params->{'exemplar'} ) {
				$self->_lookup_partial_matches(
					$locus,
					$datatype_exact_matches->{$data_type},
					$datatype_partial_matches->{$data_type}
				);
			}
		}
	}
	my $exact_matches   = { %{ $datatype_exact_matches->{'DNA'} },   %{ $datatype_exact_matches->{'peptide'} } };
	my $partial_matches = { %{ $datatype_partial_matches->{'DNA'} }, %{ $datatype_partial_matches->{'peptide'} } };
	return ( $exact_matches, $partial_matches );
}

sub blast {
	my ( $self, $params, $locus, $isolate_id, $file_prefix, $locus_prefix ) = @_;
	my $locus_info   = $self->{'datastore'}->get_locus_info($locus);
	my $program      = $self->_get_program( $locus_info->{'data_type'}, $params );
	my $temp_infile  = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_file.txt";
	my $temp_outfile = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_$$\_outfile.txt";
	my $clean_locus  = $locus;
	$clean_locus =~ s/\W/_/gx;
	if ( $clean_locus =~ /(\w*)/x ) {
		$clean_locus = $1;    #untaint
	}
	my $temp_fastafile = "$self->{'config'}->{'secure_tmp_dir'}/$locus_prefix\_fastafile_$clean_locus.txt";
	$temp_fastafile =~ s/\\/\\\\/gx;
	$temp_fastafile =~ s/'/__prime__/gx;
	my $outfile_url = "$file_prefix\_$$\_outfile.txt";
	$self->_create_fasta_index( [$locus], $temp_fastafile,
		{ exemplar => $params->{'exemplar'}, type_alleles => $params->{'type_alleles'} } );
	$self->_create_query_fasta_file( $isolate_id, $temp_infile, $params );
	my ( $probe_matches, $pcr_products );
	my $continue = 1;
	try {
		$pcr_products = $self->_get_pcr_products( $locus, $temp_infile, $params );
		$probe_matches = $self->_get_probe_matches( $locus, $temp_infile, $params );
	}
	catch {
		if ( $_->isa('BIGSdb::Exception::Data') ) {
			$continue = 0;
		} else {
			$logger->logdie($_);
		}
	};
	return if !$continue;
	$self->{'db'}->commit;    #prevent idle in transaction table locks
	return if !-e $temp_fastafile || -z $temp_fastafile;
	$params->{'exact_matches_only'} = $self->exact_matches_only($params);
	my $word_size = $self->_get_word_size( $program, $locus, $params );
	my $blast_threads = $self->{'config'}->{'blast_threads'} || 1;
	my $filter = $program eq 'blastn' ? 'dust' : 'seg';
	my %params = (
		-num_threads => $blast_threads,
		-max_target_seqs =>
		  1000,    #Set high for longer alleles that partially match and score higher than exact short alleles
		-word_size => $word_size,
		-db        => $temp_fastafile,
		-query     => $temp_infile,
		-out       => $temp_outfile,
		-outfmt    => 6,
		-$filter   => 'no'
	);

	#Will not return some matches with low-complexity regions otherwise.
	$params{'-comp_based_stats'} = 0
	  if $program ne 'blastn'
	  && $program ne 'tblastx';

	#Very short sequences won't be matched unless we increase the expect value significantly
	my $shortest_seq = $self->_get_shortest_seq_length($temp_fastafile);
	if ( $shortest_seq <= 20 ) {
		$params{'-evalue'} = 1000;
	}
	open( my $infile_fh, '<', $temp_infile ) or $logger->error("Can't open temp file $temp_infile for reading");

	#Make sure query file has finished writing (it may be another thread doing it).
	flock( $infile_fh, LOCK_SH ) or $logger->error("Can't flock $temp_infile: $!");
	system( "$self->{'config'}->{'blast+_path'}/$program", %params );
	close $infile_fh;
	my ( $exact_matches, $matched_regions, $partial_matches );
	my $pcr_filter   = !$params->{'pcr_filter'}   ? 0 : $locus_info->{'pcr_filter'};
	my $probe_filter = !$params->{'probe_filter'} ? 0 : $locus_info->{'probe_filter'};
	if ( -e "$self->{'config'}->{'secure_tmp_dir'}/$outfile_url" ) {
		( $exact_matches, $matched_regions ) = $self->_parse_blast_exact(
			{
				params        => $params,
				locus         => $locus,
				blast_file    => $outfile_url,
				pcr_filter    => { $locus => $pcr_filter },
				pcr_products  => { $locus => $pcr_products },
				probe_filter  => { $locus => $probe_filter },
				probe_matches => { $locus => $probe_matches }
			}
		);
		if (
			(
				   !@{ $exact_matches->{$locus} }
				|| $params->{'partial_when_exact'}
				|| $self->_always_lookup_partials($params)
			)
			|| (   $locus_info->{'pcr_filter'}
				&& !$params->{'pcr_filter'}
				&& $locus_info->{'probe_filter'}
				&& !$params->{'probe_filter'} )
		  )
		{
			$partial_matches = $self->_parse_blast_partial(
				{
					params                => $params,
					locus                 => $locus,
					exact_matched_regions => $matched_regions,
					blast_file            => $outfile_url,
					pcr_filter            => { $locus => $pcr_filter },
					pcr_products          => { $locus => $pcr_products },
					probe_filter          => { $locus => $probe_filter },
					probe_matches         => { $locus => $probe_matches }
				}
			);
		}
		if ( $self->_always_lookup_partials($params) ) {
			$self->_lookup_partial_matches( $locus, $exact_matches, $partial_matches );
		}
		return ( $exact_matches->{$locus}, $partial_matches->{$locus} );
	}

	#Calling function should delete working files.  This is not done here as they can be re-used
	#if multiple loci are being scanned for the same isolate.
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

sub _always_lookup_partials {
	my ( $self, $params ) = @_;
	if ( $params->{'exemplar'} || $params->{'type_alleles'} || $self->{'introns_found'} ) {
		return 1;
	}
	return;
}

sub exact_matches_only {
	my ( $self, $params ) = @_;
	if ( $self->{'no_exemplars'} && !$params->{'scannew'} && !$params->{'type_alleles'} ) {
		return 1;
	}
	return;
}

#If we are BLASTing against a subset of the database, lookup partial matches against complete
#set of alleles.
sub _lookup_partial_matches {
	my ( $self, $locus, $exact_matches, $partial_matches ) = @_;
	$partial_matches->{$locus} //= [];
	return if !@{ $partial_matches->{$locus} };
	my %already_matched_alleles = map { $_->{'allele'} => 1 } @{ $exact_matches->{$locus} };
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	foreach my $match ( @{ $partial_matches->{$locus} } ) {
		my $seq = $self->extract_seq_from_match($match);
		if ( $locus_info->{'data_type'} eq 'peptide' ) {
			my $seq_obj = Bio::Seq->new( -seq => $seq, -alphabet => 'dna' );
			$seq = $seq_obj->translate->seq;
		}
		my $allele_id =
		    $locus_info->{'dbase_name'}
		  ? $self->{'datastore'}->get_locus($locus)->get_allele_id_from_sequence( \$seq )
		  : undef;
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

#Create fasta index
#Only need to create this once for each locus (per run), so check if file exists first
#this should then be deleted by the calling function!
sub _create_fasta_index {
	my ( $self, $locus_list, $temp_fastafile, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	return if -e $temp_fastafile;
	$self->{'no_exemplars'} = 1;
	my $dbtype = $options->{'dbtype'};
	open( my $fasta_fh, '>', $temp_fastafile )
	  or $logger->error("Can't open temp file $temp_fastafile for writing");
	foreach my $locus (@$locus_list) {
		( my $locus_name = $locus ) =~ s/'/__prime__/gx;
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		if ( $locus_info->{'dbase_name'} ) {
			my $ok = 1;
			try {
				my $seqs_ref = $self->{'datastore'}->get_locus($locus)->get_all_sequences(
					{
						exemplar      => $options->{'exemplar'},
						type_alleles  => $options->{'type_alleles'},
						no_temp_table => 1
					}
				);
				if ( $options->{'exemplar'} && !keys %$seqs_ref ) {
					$logger->debug("Locus $locus has no exemplars set - using all alleles.");
					$seqs_ref = $self->{'datastore'}->get_locus($locus)->get_all_sequences( { no_temp_table => 1 } );
				} else {
					undef $self->{'no_exemplars'};
				}
				return if !keys %$seqs_ref;
				foreach my $allele_id ( keys %$seqs_ref ) {
					next if !length $seqs_ref->{$allele_id};
					if ( $options->{'multiple_loci'} ) {
						say $fasta_fh ">$locus_name|$allele_id\n$seqs_ref->{$allele_id}";
					} else {
						say $fasta_fh ">$allele_id\n$seqs_ref->{$allele_id}";
					}
					my $allele_length = length $seqs_ref->{$allele_id};
					if ( !defined $self->{'min_allele_length'}->{$locus}
						|| $allele_length < $self->{'min_allele_length'}->{$locus} )
					{
						$self->{'min_allele_length'}->{$locus} = $allele_length;
					}
				}
			}
			catch {
				if ( $_->isa('BIGSdb::Exception::Database::Configuration') ) {
					$ok = 0;
				} else {
					$logger->logdie($_);
				}
			};
			return if !$ok;
		} else {
			return if !$locus_info->{'reference_sequence'};
			if ( $options->{'multiple_loci'} ) {
				say $fasta_fh ">$locus_name|ref\n$locus_info->{'reference_sequence'}";
			} else {
				say $fasta_fh ">ref\n$locus_info->{'reference_sequence'}";
			}
		}
		$dbtype = $locus_info->{'data_type'} eq 'DNA' ? 'nucl' : 'prot';
	}
	close $fasta_fh;
	system( "$self->{'config'}->{'blast+_path'}/makeblastdb",
		( -in => $temp_fastafile, -logfile => '/dev/null', -dbtype => $dbtype ) );
	return;
}

#Create query fasta file
#Only need to create this once for each isolate (per run), so check if file exists first
#this should then be deleted by the calling function!
sub _create_query_fasta_file {
	my ( $self, $isolate_id, $temp_infile, $params ) = @_;
	return if -e $temp_infile;
	my $experiment      = $params->{'experiment_list'};
	my $distinct_clause = $experiment ? ' DISTINCT' : '';
	my $seqbin          = $self->{'seqbin_table'} // 'sequence_bin';
	my $qry             = "SELECT$distinct_clause s.id,sequence FROM $seqbin s ";
	$qry .= 'LEFT JOIN experiment_sequences e ON s.id=e.seqbin_id ' if $experiment;
	$qry .= 'WHERE s.isolate_id=? AND NOT remote_contig';
	my $remote_qry = "SELECT$distinct_clause s.id,r.uri,r.length,r.checksum FROM $seqbin s ";
	$remote_qry .= 'LEFT JOIN experiment_sequences e ON s.id=e.seqbin_id ' if $experiment;
	$remote_qry .= 'LEFT JOIN remote_contigs r ON s.id=r.seqbin_id WHERE s.isolate_id=? AND remote_contig';
	my @criteria = ($isolate_id);
	my $method   = $params->{'seq_method_list'};
	my $modifier = q();

	if ($method) {
		if ( !any { $_ eq $method } SEQ_METHODS ) {
			$logger->error("Invalid method $method");
			return;
		}
		$modifier .= ' AND method=?';
		push @criteria, $method;
	}
	if ($experiment) {
		if ( !BIGSdb::Utils::is_int($experiment) ) {
			$logger->error("Invalid experiment $experiment");
			return;
		}
		$modifier .= ' AND experiment_id=?';
		push @criteria, $experiment;
	}
	$qry        .= $modifier;
	$remote_qry .= $modifier;
	my $contigs =
	  $self->{'datastore'}
	  ->run_query( $qry, \@criteria, { fetch => 'all_arrayref', cache => 'Scan::blast_create_fasta' } );
	open( my $infile_fh, '>', $temp_infile ) or $logger->error("Can't open temp file $temp_infile for writing");
	my $remote_contigs =
	  $self->{'datastore'}->run_query( $remote_qry, \@criteria,
		{ fetch => 'all_arrayref', slice => {}, cache => 'Scan::blast_create_fasta::remote' } );
	flock( $infile_fh, LOCK_EX ) or $logger->error("Can't flock $temp_infile: $!");
	if ( !@$contigs && !@$remote_contigs ) {
		$logger->error("No contigs for id-$isolate_id");
	}
	foreach my $contig (@$contigs) {
		say $infile_fh ">$contig->[0]\n$contig->[1]";
	}
	my $remote_uris = [];
	foreach my $contig_link (@$remote_contigs) {
		push @$remote_uris, $contig_link->{'uri'};
	}
	my $remote_data;
	eval { $remote_data = $self->{'contigManager'}->get_remote_contigs_by_list($remote_uris); };
	if ($@) {
		$logger->error($@);
	} else {
		foreach my $contig_link (@$remote_contigs) {
			say $infile_fh ">$contig_link->{'id'}\n$remote_data->{$contig_link->{'uri'}}";
			if ( !$contig_link->{'length'} ) {
				$self->{'contigManager'}->update_remote_contig_length( $contig_link->{'uri'},
					length( $remote_data->{ $contig_link->{'uri'} } ) );
			} elsif ( $contig_link->{'length'} != length( $remote_data->{ $contig_link->{'uri'} } ) ) {
				$logger->error("$contig_link->{'uri'} length has changed!");
			}

			#We won't set checksum because we're not extracting all metadata here
		}
	}
	close $infile_fh;
	return;
}

sub _get_pcr_products {
	my ( $self, $locus, $temp_infile, $params ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	return if !$locus_info->{'pcr_filter'} || !$params->{'pcr_filter'};
	if ( !$self->{'config'}->{'ipcress_path'} ) {
		$logger->error('Ipcress path is not set in bigsdb.conf. ');
		BIGSdb::Exception::Data->throw();
	}
	my $pcr_products = $self->_simulate_PCR( $temp_infile, $locus );
	if ( ref $pcr_products ne 'ARRAY' ) {
		$logger->error("PCR filter is set for locus $locus but no reactions are defined - resetting value.");
		eval { $self->{'db'}->do( 'UPDATE loci SET pcr_filter=null WHERE id=?', undef, $locus ); };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
			$self->{'datastore'}->clear_locus_info_cache;
		}
		BIGSdb::Exception::Data->throw();
	}
	return $pcr_products;
}

sub _get_probe_matches {
	my ( $self, $locus, $temp_infile, $params ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	return if !$locus_info->{'probe_filter'} || !$params->{'probe_filter'};
	my $probe_matches = $self->_simulate_hybridization( $temp_infile, $locus );
	if ( ref $probe_matches ne 'ARRAY' ) {
		$logger->error("Probe filter is set for locus $locus but no probes are defined - resetting value.");
		eval { $self->{'db'}->do( 'UPDATE loci SET probe_filter=null WHERE id=?', undef, $locus ); };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
			$self->{'datastore'}->clear_locus_info_cache;
		}
		BIGSdb::Exception::Data->throw();
	}
	return $probe_matches;
}

sub _reached_limit {
	my ( $self, $isolate_id, $start_time, $match, $options ) = @_;
	if ( $match >= $options->{'limit'} ) {
		$self->_write_status( $options->{'scan_job'}, 'match_limit_reached:1' );
		$self->_write_status( $options->{'scan_job'}, "last_isolate:$isolate_id" );
		return 1;
	}
	if ( time >= $start_time + $options->{'time_limit'} ) {
		$self->_write_status( $options->{'scan_job'}, 'time_limit_reached:1' );
		$self->_write_status( $options->{'scan_job'}, "last_isolate:$isolate_id" );
		return 1;
	}
	my $status = $self->_read_status( $options->{'scan_job'} );
	return 1 if $status->{'request_stop'};
	return;
}

sub _filter_ids_by_project {
	my ( $self, $ids, $project_id ) = @_;
	return $ids if !BIGSdb::Utils::is_int($project_id);
	my $project_members = $self->{'datastore'}->run_query( 'SELECT isolate_id FROM project_members WHERE project_id=?',
		$project_id, { fetch => 'col_arrayref' } );
	my %project_members = map { $_ => 1 } @$project_members;
	my @filtered_list;
	foreach my $id (@$ids) {
		push @filtered_list, $id if $project_members{$id};
	}
	return \@filtered_list;
}

sub _skip_because_existing {
	my ( $self, $isolate_id, $locus, $params ) = @_;
	my $existing_allele_ids = $self->{'datastore'}->get_allele_ids( $isolate_id, $locus );
	return 1 if !$params->{'rescan_alleles'} && @$existing_allele_ids;
	return 1
	  if !$params->{'rescan_seqs'} && $self->{'datastore'}->allele_sequence_exists( $isolate_id, $locus );
	return;
}

sub skip_for_locus_view {
	my ( $self, $isolate_id, $locus, $params ) = @_;
	return if $params->{'override_view'};
	if ( !$self->{'locus_view_cache_set'} ) {
		my $data = $self->{'datastore'}->run_query( 'SELECT id,view FROM loci WHERE view IS NOT NULL',
			undef, { fetch => 'all_arrayref', slice => {} } );
		$self->{'locus_view_cache'} = {};
		%{ $self->{'locus_view_cache'} } = map { $_->{'id'} => $_->{'view'} } @$data;
		$self->{'locus_view_cache_set'} = 1;
	}
	if ( $self->{'locus_view_cache'}->{$locus} ) {
		return !$self->{'datastore'}->is_isolate_in_view( $self->{'locus_view_cache'}->{$locus}, $isolate_id );
	}
	return;
}

sub run_script {
	my ($self)  = @_;
	my $params  = $self->{'params'};
	my $options = $self->{'options'};
	my @isolate_list = split( "\0", $params->{'isolate_id'} );
	BIGSdb::Exception::Data->throw('Invalid isolate_ids passed') if !@isolate_list;
	my $filtered_list = $self->_filter_ids_by_project( \@isolate_list, $options->{'project_id'} );
	my $loci = $self->{'options'}->{'loci'};
	BIGSdb::Exception::Data->throw('Invalid loci passed') if ref $loci ne 'ARRAY';
	$self->{'system'}->{'script_name'} = $self->{'options'}->{'script_name'};
	my ( @js, @js2, @js3, @js4 );
	my $show_key;
	my $new_seqs_found;
	my %isolates_to_tag;
	my $locus_prefix = BIGSdb::Utils::get_random();
	my $file_prefix  = BIGSdb::Utils::get_random();
	$self->initiate_job_manager if $self->{'config'}->{'record_scans'};
	my $job_id         = $self->_add_job;
	my $start_time     = time;
	my $seq_filename   = $self->{'config'}->{'tmp_dir'} . "/$options->{'scan_job'}\_unique_sequences.txt";
	my $fasta_filename = $self->{'config'}->{'tmp_dir'} . "/$options->{'scan_job'}\_unique_sequences.fasta";
	open( my $seqs_fh, '>', $seq_filename ) or $logger->error("Can't open $seq_filename for writing");
	say $seqs_fh "locus\tallele_id\tstatus\tsequence";
	close $seqs_fh;
	$self->_write_status( $options->{'scan_job'}, "start_time:$start_time", { reset => 1 } );
	$self->_write_match( $options->{'scan_job'}, undef, { reset => 1 } );
	$logger->info("Scan $self->{'instance'}:$options->{'scan_job'} ($options->{'curator_name'}) started");
	my $table_file = "$self->{'config'}->{'secure_tmp_dir'}/$options->{'scan_job'}_table.html";
	unlink $table_file;    #delete file if scan restarted
	my $args = {
		isolates        => $filtered_list,
		loci            => $loci,
		file_prefix     => $file_prefix,
		locus_prefix    => $locus_prefix,
		isolates_to_tag => \%isolates_to_tag,
		js              => \@js,
		js2             => \@js2,
		js3             => \@js3,
		js4             => \@js4,
		show_key        => \$show_key,
		new_seqs_found  => \$new_seqs_found,
		seq_filename    => $seq_filename,
		fasta_filename  => $fasta_filename,
		table_file      => $table_file
	};
	my $match = $params->{'loci_together'} ? $self->_scan_loci_together($args) : $self->_scan_locus_by_locus($args);

	#delete locus working files
	my @files = glob("$self->{'config'}->{'secure_tmp_dir'}/*$locus_prefix*");
	foreach (@files) { unlink $1 if /^(.*BIGSdb.*)$/x }
	if ($match) {
		open( my $fh, '>>', $table_file ) || $logger->error("Can't open $table_file for appending");
		local $" = ';';
		say $fh q(<tr class="td">) . ( q(<td></td>) x 14 ) . q(<td>);
		say $fh qq(<input type="button" value="All" onclick='@js' class="smallbutton" />)   if @js;
		say $fh qq(<input type="button" value="None" onclick='@js2' class="smallbutton" />) if @js2;
		say $fh q(</td><td>);
		say $fh qq(<input type="button" value="All" onclick='@js3' class="smallbutton" />)  if @js3;
		say $fh qq(<input type="button" value="None" onclick='@js4' class="smallbutton" />) if @js4;
		say $fh q(</td><td></td></tr>);
		close $fh;
	}
	my $stop_time = time;
	$self->_write_status( $options->{'scan_job'}, 'allele_off_contig:1' ) if $show_key;
	$self->_write_status( $options->{'scan_job'}, "new_matches:$match" );
	$self->_write_status( $options->{'scan_job'}, 'new_seqs_found:1' )    if $new_seqs_found;
	my @isolates_to_tag = sort { $a <=> $b } keys %isolates_to_tag;
	local $" = ',';
	$self->_write_status( $options->{'scan_job'}, "tag_isolates:@isolates_to_tag" );
	$self->_write_status( $options->{'scan_job'}, "loci:@$loci" );
	$self->_write_status( $options->{'scan_job'}, "stop_time:$stop_time" );
	$logger->info("Scan $self->{'instance'}:$options->{'scan_job'} ($options->{'curator_name'}) finished");
	$self->_stop_job($job_id);
	return;
}

sub _add_job {
	my ($self) = @_;
	my $params = $self->{'params'};
	return
	  if !$self->{'config'}->{'jobs_db'}
	  || !$self->{'config'}->{'record_scans'};
	my $job_id;
	try {
		$job_id = $self->{'jobManager'}->add_job(
			{
				dbase_config => $self->{'instance'},
				module       => 'ManualScan',
				ip_address   => $params->{'ip_address'},
				username     => $params->{'username'},
				email        => $params->{'email'},
				parameters   => {},
				mark_started => 1,
				no_progress  => 1
			}
		);
	}
	catch {
		$logger->error($_);
	};
	return $job_id;
}

sub _stop_job {
	my ( $self, $job_id ) = @_;
	return
	  if !$self->{'config'}->{'jobs_db'}
	  || !$self->{'config'}->{'record_scans'};
	$self->{'jobManager'}->update_job_status(
		$job_id,
		{
			status           => 'finished',
			stop_time        => 'now',
			percent_complete => 100,
			pid              => undef
		}
	);
	return;
}

sub _scan_locus_by_locus {
	my ( $self, $args ) = @_;
	my ( $isolates, $loci, $file_prefix, $locus_prefix ) =
	  @{$args}{qw(isolates loci file_prefix locus_prefix  )};
	my $match       = 0;
	my $start_time  = time;
	my $options     = $self->{'options'};
	my $labels      = $self->{'options'}->{'labels'};
	my $params      = $self->{'params'};
	my $td          = 1;
	my $new_alleles = {};
	foreach my $isolate_id (@$isolates) {
		last if $self->_reached_limit( $isolate_id, $start_time, $match, $options );
		next if !$self->is_allowed_to_view_isolate($isolate_id);
		my $pattern = LOCUS_PATTERN;
		foreach my $locus_id (@$loci) {
			my $locus = $locus_id =~ /$pattern/x ? $1 : undef;
			if ( !defined $locus ) {
				$logger->error("Locus name not extracted: Input was '$locus_id'");
				next;
			}
			last if $self->_reached_limit( $isolate_id, $start_time, $match, $options );
			next if $self->_skip_because_existing( $isolate_id, $locus, $params );
			next if $self->skip_for_locus_view( $isolate_id, $locus, $params );
			my ( $exact_matches, $partial_matches ) =
			  $self->blast( $params, $locus, $isolate_id, $file_prefix, $locus_prefix );
			my $analysis_args = {
				%$args,
				isolate_id      => $isolate_id,
				locus           => $locus,
				td_ref          => \$td,
				exact_matches   => $exact_matches,
				partial_matches => $partial_matches,
				params          => $params,
				options         => $options,
				labels          => $labels,
				new_alleles     => $new_alleles,
			};
			$match++ if $self->_analyse_blast_results($analysis_args);
		}

		#delete isolate working files
		my @files = glob("$self->{'config'}->{'secure_tmp_dir'}/*$file_prefix*");
		foreach (@files) { unlink $1 if /^(.*BIGSdb.*)$/x }
	}
	return $match;
}

sub _analyse_blast_results {
	my ( $self, $args ) = @_;
	my (
		$isolate_id,  $locus,          $td_ref,       $exact_matches,   $partial_matches,
		$params,      $options,        $labels,       $js,              $js2,
		$js3,         $js4,            $show_key,     $isolates_to_tag, $table_file,
		$new_alleles, $new_seqs_found, $seq_filename, $fasta_filename
	  )
	  = @{$args}{
		qw(isolate_id locus td_ref exact_matches partial_matches params options labels js js2 js3 js4
		  show_key isolates_to_tag table_file new_alleles new_seqs_found seq_filename fasta_filename)
	  };
	$exact_matches   //= [];
	$partial_matches //= [];
	my $row_buffer;
	my $off_end;
	my $i = 1;
	my $new_designation;
	if (@$exact_matches) {
		my %new_matches;
		foreach my $match (@$exact_matches) {
			my $match_key = "$match->{'seqbin_id'}\|$match->{'predicted_start'}|$match->{'predicted_end'}";
			( my $buffer, $off_end, $new_designation ) = $self->_get_row(
				{
					isolate_id => $isolate_id,
					labels     => $labels,
					locus      => $locus,
					id         => $i,
					match      => $match,
					td         => $$td_ref,
					exact      => 1,
					js         => $js,
					js2        => $js2,
					js3        => $js3,
					js4        => $js4,
					warning    => $new_matches{$match_key}
				}
			);
			$row_buffer .= $buffer;
			$new_matches{$match_key} = 1;
			$$show_key = 1 if $off_end;
			$$td_ref = $$td_ref == 1 ? 2 : 1;
			$self->_write_match( $options->{'scan_job'}, "$isolate_id:$locus:$i" );
			$i++;
		}
		$isolates_to_tag->{$isolate_id} = 1;
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( @$partial_matches && ( !@$exact_matches || $params->{'partial_when_exact'} ) ) {
		my $max_partial_match = $params->{'partial_matches'} // 1;
		my %new_matches;
		foreach my $match (@$partial_matches) {
			last if $i > $max_partial_match;
			my $match_key = "$match->{'seqbin_id'}\|$match->{'predicted_start'}|$match->{'predicted_end'}";
			( my $buffer, $off_end, $new_designation ) = $self->_get_row(
				{
					isolate_id => $isolate_id,
					labels     => $labels,
					locus      => $locus,
					id         => $i,
					match      => $match,
					td         => $$td_ref,
					exact      => 0,
					js         => $js,
					js2        => $js2,
					js3        => $js3,
					js4        => $js4,
					warning    => $new_matches{$match_key}
				}
			);
			$row_buffer .= $buffer;
			$new_matches{$match_key} = 1;
			if ($off_end) {
				$$show_key = 1;
			} else {
				$self->_check_if_new(
					{
						match          => $match,
						new_seqs_found => $new_seqs_found,
						new_alleles    => $new_alleles,
						locus          => $locus,
						seq_filename   => $seq_filename,
						fasta_filename => $fasta_filename
					}
				);
			}
			$$td_ref = $$td_ref == 1 ? 2 : 1;
			$self->_write_match( $options->{'scan_job'}, "$isolate_id:$locus:$i" );
			$i++;
		}
		$isolates_to_tag->{$isolate_id} = 1;
	} elsif ( $params->{'mark_missing'} && !@$exact_matches && !@$partial_matches ) {
		$row_buffer = $self->_get_missing_row( $isolate_id, $labels, $locus, $js, $js2, );
		if ($row_buffer) {
			$new_designation                = 1;
			$$td_ref                        = $$td_ref == 1 ? 2 : 1;
			$isolates_to_tag->{$isolate_id} = 1;
			$self->_write_match( $options->{'scan_job'}, "$isolate_id:$locus:$i" );
		}
	}
	if ($row_buffer) {
		open( my $fh, '>>', $table_file ) || $logger->error("Can't open $table_file for appending");
		say $fh $row_buffer;
		close $fh;
	}
	return 1 if $new_designation;
	return;
}

sub _scan_loci_together {
	my ( $self, $args ) = @_;
	my ( $isolates, $loci, $file_prefix, $locus_prefix ) =
	  @{$args}{qw(isolates loci file_prefix locus_prefix )};
	my $match       = 0;
	my $start_time  = time;
	my $options     = $self->{'options'};
	my $labels      = $self->{'options'}->{'labels'};
	my $params      = $self->{'params'};
	my $td          = 1;
	my $new_alleles = {};
	foreach my $isolate_id (@$isolates) {
		last if $self->_reached_limit( $isolate_id, $start_time, $match, $options );
		next if !$self->is_allowed_to_view_isolate($isolate_id);
		my $pattern      = LOCUS_PATTERN;
		my $loci_to_scan = [];
		foreach my $locus_id (@$loci) {
			my $row_buffer;
			my $locus = $locus_id =~ /$pattern/x ? $1 : undef;
			if ( !defined $locus ) {
				$logger->error("Locus name not extracted: Input was '$locus_id'");
				next;
			}
			last if $self->_reached_limit( $isolate_id, $start_time, $match, $options );
			next if $self->_skip_because_existing( $isolate_id, $locus, $params );
			next if $self->skip_for_locus_view( $isolate_id, $locus, $params );
			push @$loci_to_scan, $locus;
		}
		next if !@$loci_to_scan;
		my ( $exact_matches, $partial_matches ) =
		  $self->blast_multiple_loci( $params, $loci_to_scan, $isolate_id, $file_prefix, $locus_prefix );
		foreach my $locus (@$loci_to_scan) {
			my $analysis_args = {
				%$args,
				isolate_id      => $isolate_id,
				locus           => $locus,
				td_ref          => \$td,
				exact_matches   => $exact_matches->{$locus},
				partial_matches => $partial_matches->{$locus},
				params          => $params,
				options         => $options,
				labels          => $labels,
				new_alleles     => $new_alleles,
			};
			$match++ if $self->_analyse_blast_results($analysis_args);
		}

		#delete working files
		my @isolate_files = glob("$self->{'config'}->{'secure_tmp_dir'}/*$file_prefix*");
		my @locus_files   = glob("$self->{'config'}->{'secure_tmp_dir'}/*$locus_prefix*");
		foreach ( @isolate_files, @locus_files ) { unlink $1 if /^(.*BIGSdb.*)$/x }
	}
	return $match;
}

sub _check_if_new {
	my ( $self, $args ) = @_;
	my ( $match, $new_seqs_found, $new_alleles, $locus, $seq_filename, $fasta_filename ) =
	  @{$args}{qw(match new_seqs_found new_alleles locus seq_filename fasta_filename)};
	my $seq        = $self->extract_seq_from_match($match);
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( $locus_info->{'data_type'} eq 'peptide' ) {
		my $seq_obj = Bio::Seq->new( -seq => $seq, -alphabet => 'dna' );
		$seq = $seq_obj->translate->seq;
	}
	$$new_seqs_found = 1;
	my $new = 1;
	$new = 0 if any { $seq eq $_ } @{ $new_alleles->{$locus} };
	if ($new) {
		push @{ $new_alleles->{$locus} }, $seq;
		open( my $seqs_fh, '>>', $seq_filename )
		  or $logger->error("Can't open $seq_filename for appending");
		say $seqs_fh "$locus\t\tWGS: automated extract (BIGSdb)\t$seq";
		close $seqs_fh;
		open( $seqs_fh, '>>', $fasta_filename )
		  or $logger->error("Can't open $seq_filename for appending");
		say $seqs_fh qq(>${locus}_seqbin_$match->{'seqbin_id'}_$match->{'start'}-$match->{'end'});
		say $seqs_fh qq($seq);
		close $seqs_fh;
	}
	return;
}

sub extract_seq_from_match {
	my ( $self, $match ) = @_;
	if ( $match->{'predicted_start'} =~ /\*/x ) {    #Error appearing in log - need to track down what's causing this

		#		$logger->logcarp( Dumper $match);
		$match->{'predicted_start'} =~ s/\*//x;
	}
	my $seq;
	if ( $match->{'exons'} ) {
		foreach my $exon ( $match->{'reverse'} ? reverse @{ $match->{'exons'} } : @{ $match->{'exons'} } ) {
			my $seq_ref = $self->{'contigManager'}->get_contig_fragment(
				{
					seqbin_id => $match->{'seqbin_id'},
					reverse   => $match->{'reverse'},
					start     => $exon->{'start'},
					end       => $exon->{'end'}
				}
			);
			$seq .= $seq_ref->{'seq'};
		}
	} else {
		my $seq_ref = $self->{'contigManager'}->get_contig_fragment(
			{
				seqbin_id => $match->{'seqbin_id'},
				start     => $match->{'predicted_start'},
				end       => $match->{'predicted_end'},
				reverse   => $match->{'reverse'}
			}
		);
		$seq = $seq_ref->{'seq'};
	}
	$seq = uc($seq);
	return $seq;
}

sub _get_match_class {
	my ( $self, $exact ) = @_;
	my ( $class, $match_status );
	if ($exact) {
		$class        = q();
		$match_status = q(exact);
	} else {
		$class        = q( class="partialmatch");
		$match_status = q(partial);
	}
	return ( $class, $match_status );
}

sub _get_row {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $labels, $locus, $id, $match, $td, $exact, $js, $js2, $js3, $js4, $warning ) =
	  @{$args}{qw (isolate_id labels locus id match td exact js js2 js3 js4 warning)};
	my $q      = $self->{'cgi'};
	my $params = $self->{'params'};
	my $tooltip;
	my $new_designation  = 0;
	my $existing_alleles = $self->{'datastore'}->get_allele_ids( $isolate_id, $locus );
	my %existing         = map { $_ => 1 } @$existing_alleles;
	if ( $existing{ $match->{'allele'} } ) {
		$tooltip = $self->_get_designation_tooltip( $isolate_id, $locus, 'existing' );
	} elsif ( $match->{'allele'} && @$existing_alleles && !$existing{ $match->{'allele'} } ) {
		$tooltip = $self->_get_designation_tooltip( $isolate_id, $locus, 'clashing' );
	}
	my $hunt_for_start_end = ( !$exact && $params->{'hunt'} ) ? 1 : 0;
	my $original_start     = $match->{'predicted_start'};
	my $original_end       = $match->{'predicted_end'};
	my $buffer             = q();
	my $hunter = $self->_hunt_for_start_and_stop_codons( $hunt_for_start_end, $match, $original_start, $original_end );
	my $cleaned_locus = $self->clean_locus($locus);
	my $locus_info    = $self->{'datastore'}->get_locus_info($locus);
	my $translate     = ( $locus_info->{'coding_sequence'} || $locus_info->{'data_type'} eq 'peptide' ) ? 1 : 0;
	my $orf           = $locus_info->{'orf'} // 1;

	if ($warning) {
		$buffer .= q(<tr class="warning">);
		$exact = 0;
	} else {
		$buffer .= qq(<tr class="td$td">);
	}
	my $isolate_name = $labels->{$isolate_id} // $isolate_id;
	$tooltip //= q();
	my ( $class, $match_status ) = $self->_get_match_class($exact);
	$buffer .= qq(<td>$isolate_name</td><td$class>$match_status</td><td$class>$cleaned_locus</td>)
	  . qq(<td$class>$match->{'allele'}$tooltip</td>);
	if ( $match->{'from_partial'} ) {
		$buffer .= q(<td>100.00</td>)
		  . qq(<td colspan="3">Initial partial BLAST match to allele $match->{'partial_match_allele'}</td>);
	} else {
		$buffer .= qq(<td>$match->{'identity'}</td><td>$match->{'alignment'}</td>)
		  . qq(<td>$match->{'length'}</td><td>$match->{'e-value'}</td>);
	}
	$buffer .= qq(<td>$match->{'seqbin_id'}</td><td>$match->{'start'}</td><td>$match->{'end'} </td>);
	$buffer .=
	  $hunter->{'off_end'}
	  ? qq(<td class="incomplete">$match->{'predicted_start'}</td><td class="incomplete">)
	  : qq(<td>$match->{'predicted_start'}</td><td>);
	$match->{'reverse'} //= 0;
	my $intron_arg = $self->_get_intron_arg($match);
	my $url =
	    qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=extractedSequence&amp;)
	  . qq(seqbin_id=$match->{'seqbin_id'}&amp;start=$hunter->{'predicted_start'}&amp;)
	  . qq(end=$hunter->{'predicted_end'}&amp;reverse=$match->{'reverse'}&amp;translate=$translate&amp;)
	  . qq(orf=$orf$intron_arg);
	$buffer .=
	    qq($match->{'predicted_end'} <a target="_blank" class="extract_tooltip" )
	  . qq(href="$url" style="white-space:nowrap">)
	  . qq(extract <span class="fas fa-arrow-circle-right"></span></a>$hunter->{'complete_tooltip'}</td>);
	my $arrow = $self->_get_dir_arrow( $match->{'reverse'} );
	$buffer .= qq(<td>$arrow</td><td>);
	my $seq_disabled = 0;
	$cleaned_locus = $self->clean_checkbox_id($locus);
	$cleaned_locus =~ s/\\/\\\\/gx;

	if (   $exact
		&& ( !@$existing_alleles || !$existing{ $match->{'allele'} } )
		&& $match->{'allele'} ne 'ref'
		&& !$params->{'tblastx'} )
	{
		$buffer .= $q->checkbox(
			-name    => "id_${isolate_id}_${locus}_allele_$id",
			-id      => "id_${isolate_id}_${cleaned_locus}_allele_$id",
			-label   => '',
			-checked => $exact
		);
		$buffer .= $q->hidden( "id_${isolate_id}_${locus}_seqbin_id_$id", $match->{'seqbin_id'} );
		push @$js,  qq(\$("#id_${isolate_id}_${cleaned_locus}_allele_$id").prop("checked",true));
		push @$js2, qq(\$("#id_${isolate_id}_${cleaned_locus}_allele_$id").prop("checked",false));
		$new_designation = 1;
	} else {
		$buffer .=
		  $q->checkbox( -name => "id_${isolate_id}_${locus}_allele_$id", -label => '', disabled => 'disabled' );
	}
	$buffer .= q(</td><td>);
	my $existing_allele_sequence = $self->{'datastore'}->run_query(
		'SELECT id FROM allele_sequences WHERE (seqbin_id,locus,start_pos,end_pos)=(?,?,?,?)',
		[ $match->{'seqbin_id'}, $locus, $hunter->{'predicted_start'}, $hunter->{'predicted_end'} ],
		{ fetch => 'row_hashref', cache => 'Scan::get_row_existing_allele_sequence' }
	);
	if ( !$existing_allele_sequence ) {
		$buffer .= $q->checkbox(
			-name    => "id_${isolate_id}_${locus}_sequence_$id",
			-id      => "id_${isolate_id}_${cleaned_locus}_sequence_$id",
			-label   => '',
			-checked => $exact || ( $hunter->{'off_end'} && $match->{'identity'} == 100 )
		);
		push @$js3, qq(\$("#id_${isolate_id}_${cleaned_locus}_sequence_$id").prop("checked",true));
		push @$js4, qq(\$("#id_${isolate_id}_${cleaned_locus}_sequence_$id").prop("checked",false));
		$new_designation = 1;
		$buffer .= q(</td><td>);
		my $default_flags = $self->_get_match_flags( $locus, $match, $exact );
		if ( @$default_flags > 1 ) {
			$buffer .= $q->popup_menu(
				-name     => "id_${isolate_id}_${locus}_sequence_${id}_flag",
				-id       => "id_${isolate_id}_${cleaned_locus}_sequence_${id}_flag",
				-values   => [SEQ_FLAGS],
				-default  => $default_flags,
				-multiple => 'multiple',
			);
		} else {
			$buffer .= $q->popup_menu(
				-name    => "id_${isolate_id}_${locus}_sequence_${id}_flag",
				-id      => "id_${isolate_id}_${cleaned_locus}_sequence_${id}_flag",
				-values  => [ '', SEQ_FLAGS ],
				-default => $default_flags,
			);
		}
	} else {
		$buffer .=
		  $q->checkbox( -name => "id_${isolate_id}_${locus}_sequence_$id", -label => '', disabled => 'disabled' );
		$seq_disabled = 1;
		$buffer .= q(</td><td>);
		$buffer .= $self->_get_sequence_flags( $existing_allele_sequence->{'id'} );
	}
	if ($exact) {
		$buffer .= $q->hidden( "id_${isolate_id}_${locus}_allele_id_$id", $match->{'allele'} );
	}
	if ( !$seq_disabled ) {
		$buffer .= $q->hidden( "id_${isolate_id}_${locus}_start_$id"     => $hunter->{'predicted_start'} );
		$buffer .= $q->hidden( "id_${isolate_id}_${locus}_end_$id"       => $hunter->{'predicted_end'} );
		$buffer .= $q->hidden( "id_${isolate_id}_${locus}_reverse_$id"   => $match->{'reverse'} );
		$buffer .= $q->hidden( "id_${isolate_id}_${locus}_complete_$id"  => 1 ) if !$hunter->{'off_end'};
		$buffer .= $q->hidden( "id_${isolate_id}_${locus}_seqbin_id_$id" => $match->{'seqbin_id'} );
		$intron_arg = $self->_get_intron_arg( $match, { hidden => 1 } );
		if ($intron_arg) {
			$buffer .= $q->hidden( "id_${isolate_id}_${locus}_introns_$id" => $intron_arg );
		}
	}
	$buffer .= q(</td></tr>);
	return ( $buffer, $hunter->{'off_end'}, $new_designation );
}

sub _get_match_flags {
	my ( $self, $locus, $match, $exact ) = @_;
	my $flags = [];
	if ($exact) {
		$flags = $self->{'datastore'}->get_locus($locus)->get_flags( $match->{'allele'} );
	}
	if ( $match->{'introns'} && @{ $match->{'introns'} } ) {
		push @$flags, 'introns';
	}
	return $flags;
}

sub _get_sequence_flags {
	my ( $self, $allele_seq ) = @_;
	my $buffer = q();
	my $flags  = $self->{'datastore'}->get_sequence_flags($allele_seq);
	foreach my $flag (@$flags) {
		$buffer .= qq( <a class="seqflag_tooltip">$flag</a>);
	}
	return $buffer;
}

sub _get_intron_arg {
	my ( $self, $match, $options ) = @_;
	return q() if !$match->{'introns'} || !@{ $match->{'introns'} };
	my @args;
	foreach my $intron ( @{ $match->{'introns'} } ) {
		push @args, qq($intron->{'start'}-$intron->{'end'});
	}
	local $" = q(,);
	return $options->{'hidden'} ? qq(@args) : qq(&introns=@args);
}

sub _get_dir_arrow {
	my ( $self, $reverse ) = @_;
	my $dir = $reverse ? 'left' : 'right';
	return qq(<span class="fas fa-2x fa-long-arrow-alt-$dir"></span>);
}

sub _hunt_for_start_and_stop_codons {
	my ( $self, $hunt_for_start_end, $match, $original_start, $original_end ) = @_;
	my ( $off_end, $predicted_start, $predicted_end, $complete_gene );
	my $complete_tooltip = q();
	my $seqbin_length    = $self->{'datastore'}->run_query(
		'SELECT GREATEST(r.length,length(s.sequence)) FROM sequence_bin s LEFT JOIN '
		  . 'remote_contigs r ON s.id=r.seqbin_id WHERE s.id=?',
		$match->{'seqbin_id'},
		{ cache => 'Scan::hunt_for_start_and_stop_codons::contig_length' }
	);
	my ( $first_codon_is_start, $last_codon_is_stop );
	my %start_codons = map { $_ => 1 } qw(ATG GTG TTG);
	my %stop_codons  = map { $_ => 1 } qw(TAG TAA TGA);

	#Hunt for nearby start and stop codons.  Walk in from each end by 3 bases, then out by 3 bases, then in by 6 etc.
	my @runs = $hunt_for_start_end ? qw (-3 3 -6 6 -9 9 -12 12 -15 15 -18 18) : ();
  RUN: foreach my $offset ( 0, @runs ) {
		my @end_to_adjust = $hunt_for_start_end ? ( 1, 2 ) : (0);
		foreach my $end (@end_to_adjust) {

			#Don't change start position if already start codon
			if ( $end == 1 ) {
				next if $match->{'reverse'}  && $first_codon_is_start;
				next if !$match->{'reverse'} && $last_codon_is_stop;
				$match->{'predicted_end'} = $original_end + $offset;
			} elsif ( $end == 2 ) {
				next if !$match->{'reverse'} && $first_codon_is_start;
				next if $match->{'reverse'}  && $last_codon_is_stop;
				$match->{'predicted_start'} = $original_start + $offset;
			}
			$off_end = 1 if $self->_is_off_end( $match, $seqbin_length );
			$predicted_start = $match->{'predicted_start'};
			$predicted_start =~ s/\*//x;
			$predicted_end = $match->{'predicted_end'};
			$predicted_end =~ s/\*//x;

			#			my $seq_ref = $self->{'contigManager'}->get_contig_fragment(
			#				{
			#					seqbin_id => $match->{'seqbin_id'},
			#					start     => $predicted_start,
			#					end       => $predicted_end,
			#					flanking  => 0
			#				}
			#			);
			#			my $seq = $seq_ref->{'seq'};
			my $seq = $self->extract_seq_from_match($match);

			#			$logger->error($seq);
			if ($seq) {

				#				$seq = BIGSdb::Utils::reverse_complement($seq) if $match->{'reverse'};
				$off_end = 1 if $seq =~ /^N/x || $seq =~ /N$/x;    #Incomplete if Ns are end (scaffolding)
				$first_codon_is_start = 1 if $start_codons{ substr( $seq, 0, 3 ) };
				$last_codon_is_stop = 1 if $stop_codons{ substr( $seq, -3 ) };
				($complete_gene) = $self->is_complete_gene($seq);
				if ($complete_gene) {
					$complete_tooltip = q(<a class="cds" title="CDS - this is a complete coding sequence )
					  . q(including start and terminating stop codons with no internal stop codons.">CDS</a>);
					last RUN;
				}
			}
		}
	}
	if ( $hunt_for_start_end && !$complete_gene ) {
		$match->{'predicted_end'}   = $original_end;
		$predicted_end              = $original_end;
		$match->{'predicted_start'} = $original_start;
		$predicted_start            = $original_start;
		if ( $match->{'predicted_start'} < 1 ) {
			$match->{'predicted_start'} = '1*';
			$off_end = 1;
		}
		if ( $match->{'predicted_end'} > $seqbin_length ) {
			$match->{'predicted_end'} = "${seqbin_length}*";
			$off_end = 1;
		}
	}
	return {
		off_end          => $off_end,
		predicted_start  => $predicted_start,
		predicted_end    => $predicted_end,
		complete_tooltip => $complete_tooltip
	};
}

sub _is_off_end {
	my ( $self, $match, $seqbin_length ) = @_;
	my $off_end;
	if ( BIGSdb::Utils::is_int( $match->{'predicted_start'} ) && $match->{'predicted_start'} < 1 ) {
		if ( $match->{'from_partial'} ) {
			$match->{'predicted_start'} = 1;
		} else {
			$match->{'predicted_start'} = '1*';
			$off_end = 1;
		}
	}
	if ( BIGSdb::Utils::is_int( $match->{'predicted_end'} )
		&& $match->{'predicted_end'} > $seqbin_length )
	{
		if ( $match->{'from_partial'} ) {
			$match->{'predicted_end'} = ${seqbin_length};
		} else {
			$match->{'predicted_end'} = "${seqbin_length}*";
			$off_end = 1;
		}
	}
	return $off_end;
}

sub _get_missing_row {
	my ( $self, $isolate_id, $labels, $locus, $js, $js2, ) = @_;
	my $q                  = $self->{'cgi'};
	my $existing_alleles   = $self->{'datastore'}->get_allele_ids( $isolate_id, $locus );
	my $existing_sequences = $self->{'datastore'}->get_allele_sequence( $isolate_id, $locus );
	my $cleaned_locus      = $self->clean_locus($locus);
	my $buffer;
	if ( @$existing_alleles || @$existing_sequences ) {
		print ' ';    #try to prevent time-out.
		return $buffer;
	}
	$buffer .= q(<tr class="provisional">);
	$buffer .= q(<td>) . ( $labels->{$isolate_id} || $isolate_id ) . qq(</td><td>missing</td><td>$cleaned_locus</td>);
	$buffer .= q(<td>0</td>);
	$buffer .= ( q(<td></td>) x 10 ) . q(<td>);
	$cleaned_locus = $self->clean_checkbox_id($locus);
	$cleaned_locus =~ s/\\/\\\\/gx;
	$buffer .= $q->checkbox(
		-name    => "id_$isolate_id\_$locus\_allele_1",
		-id      => "id_$isolate_id\_$cleaned_locus\_allele_1",
		-label   => '',
		-checked => 'checked'
	);
	$buffer .= $q->hidden( "id_$isolate_id\_$locus\_allele_id_1", 0 );
	push @$js,  qq(\$("#id_$isolate_id\_$cleaned_locus\_allele_1").prop("checked",true));
	push @$js2, qq(\$("#id_$isolate_id\_$cleaned_locus\_allele_1").prop("checked",false));
	$buffer .= qq(</td><td></td><td></td></tr>\n);
	return $buffer;
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

sub _parse_blast_exact {
	my ( $self, $args ) = @_;
	my ( $params, $locus, $blast_file, $pcr_filter, $pcr_products, $probe_filter, $probe_matches, $options ) =
	  @{$args}{qw (params locus blast_file pcr_filter pcr_products probe_filter probe_matches options)};
	my $matches = {};
	$matches->{$locus} = [] if $locus;
	my $matched_already        = {};
	my $region_matched_already = {};
	my $locus_info             = {};
	$pcr_filter    //= {};
	$probe_filter  //= {};
	$pcr_products  //= {};
	$probe_matches //= {};
	$self->_read_blast_file_into_structure($blast_file);
  RECORD: foreach my $record ( @{ $self->{'records'} } ) {
		my $match;
		if ( $record->[2] == 100 ) {    #identity
			my $allele_id;
			if ( $options->{'multiple_loci'} ) {
				my ( $match_locus, $match_allele_id ) = split( /\|/x, $record->[1], 2 );
				( $locus = $match_locus ) =~ s/__prime__/'/gx;
				$matches->{$locus} //= [];
				$allele_id = $match_allele_id;
			} else {
				$allele_id = $record->[1];
			}
			if ( !$locus_info->{$locus} ) {
				$locus_info->{$locus} = $self->{'datastore'}->get_locus_info($locus);
			}
			my $ref_length;
			if ( $allele_id eq 'ref' ) {
				$ref_length = length( $locus_info->{$locus}->{'reference_sequence'} );
			} else {
				my $ref_seq = $self->{'datastore'}->get_locus($locus)->get_allele_sequence($allele_id);
				$ref_length = length($$ref_seq);
			}
			next if !defined $ref_length;
			if ( $self->_does_blast_record_match( $record, $ref_length ) ) {
				$match->{'seqbin_id'} = $record->[0];
				$match->{'allele'}    = $allele_id;
				$match->{'identity'}  = $record->[2];
				$match->{'alignment'} = $params->{'tblastx'} ? ( $record->[3] * 3 ) : $record->[3];
				$match->{'length'}    = $ref_length;
				$self->_identify_match_ends( $match, $record );
				if ( $pcr_filter->{$locus} ) {
					my $within_amplicon = 0;
					foreach my $product ( @{ $pcr_products->{$locus} } ) {
						next if $self->_is_match_outside_pcr_amplicon( $match, $product );
						$within_amplicon = 1;
					}
					next RECORD if !$within_amplicon;
				}
				if ( $probe_filter->{$locus} ) {
					next RECORD if !$self->_probe_filter_match( $locus, $match, $probe_matches->{$locus} );
				}
				$match->{'predicted_start'} = $match->{'start'};
				$match->{'predicted_end'}   = $match->{'end'};
				$match->{'reverse'}         = $self->_is_match_reversed($record);
				$match->{'e-value'}         = $record->[10];
				$match->{'length'}          = abs( $match->{'predicted_end'} - $match->{'predicted_start'} ) + 1;
				next RECORD
				  if $matched_already->{$locus}->{ $match->{'allele'} }->{ $match->{'predicted_start'} };
				$matched_already->{$locus}->{ $match->{'allele'} }->{ $match->{'predicted_start'} }           = 1;
				$region_matched_already->{$locus}->{ $match->{'seqbin_id'} }->{ $match->{'predicted_start'} } = 1;

				if ( $locus_info->{$locus}->{'match_longest'} && @{ $matches->{$locus} } ) {
					if ( $match->{'length'} > $matches->{$locus}->[0]->{'length'} ) {
						@{ $matches->{$locus} } = ($match);
					}
				} else {
					push @{ $matches->{$locus} }, $match;
				}
			}
		}
	}
	undef $self->{'records'} if !$options->{'keep_data'};
	return $matches, $region_matched_already;
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

sub _read_blast_file_into_structure {
	my ( $self, $blast_file ) = @_;
	if ( !$self->{'records'} ) {
		my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$blast_file";
		open( my $blast_fh, '<', $full_path )
		  || ( $logger->error("Can't open BLAST output file $full_path. $!"), return \$; );
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

sub _is_good_match {
	my ( $self, $record, $alignment_threshold, $identity_threshold, $allele_length ) = @_;
	return 1
	  if $record->[3] >= $alignment_threshold * 0.01 * $allele_length
	  && $record->[2] >= $identity_threshold;
	return;
}

sub _parse_blast_partial {
	my ( $self, $args ) = @_;
	my (
		$params,       $locus,        $exact_matched_regions, $blast_file, $pcr_filter,
		$pcr_products, $probe_filter, $probe_matches,         $options
	  )
	  = @{$args}{
		qw (params locus exact_matched_regions blast_file pcr_filter pcr_products probe_filter
		  probe_matches options)
	  };
	$pcr_filter    //= {};
	$probe_filter  //= {};
	$pcr_products  //= {};
	$probe_matches //= {};
	my $matches = {};
	$matches->{$locus} = [] if $locus;
	my $identity  = $params->{'identity'};
	my $alignment = $params->{'alignment'};
	$identity  = 70 if !BIGSdb::Utils::is_int($identity);
	$alignment = 50 if !BIGSdb::Utils::is_int($alignment);
	my $lengths = {};
	$self->_read_blast_file_into_structure($blast_file);
  RECORD: foreach my $record ( @{ $self->{'records'} } ) {
		my $allele_id;
		if ( $options->{'multiple_loci'} ) {
			my ( $match_locus, $match_allele_id ) = split( /\|/x, $record->[1], 2 );
			( $locus = $match_locus ) =~ s/__prime__/'/gx;
			$matches->{$locus} //= [];
			$allele_id = $match_allele_id;
		} else {
			$allele_id = $record->[1];
		}
		$self->_cache_match_allele_length( $lengths, $locus, $allele_id );
		next if !defined $lengths->{$locus}->{$allele_id};
		my $length = $lengths->{$locus}->{$allele_id};
		if ( $params->{'tblastx'} ) {
			$record->[3] *= 3;
		}
		my $quality = $record->[3] * $record->[2];    #simple metric of alignment length x percentage identity
		if ( $self->_is_good_match( $record, $alignment, $identity, $length ) ) {
			my $match;
			$match->{'quality'}   = $quality;
			$match->{'seqbin_id'} = $record->[0];
			$match->{'allele'}    = $allele_id;
			$match->{'identity'}  = $record->[2];
			$match->{'length'}    = $length;
			$match->{'alignment'} = $record->[3];
			$match->{'reverse'}   = $self->_is_match_reversed($record);
			$self->_identify_match_ends( $match, $record );
			$self->_predict_allele_ends( $length, $match, $record );

			#Don't handle exact matches - these are handled elsewhere.
			next
			  if !$params->{'exemplar'}
			  && $exact_matched_regions->{$locus}->{ $match->{'seqbin_id'} }->{ $match->{'predicted_start'} };
			$match->{'e-value'} = $record->[10];
			if ( $pcr_filter->{$locus} ) {
				my $within_amplicon = 0;
				foreach my $product ( @{ $pcr_products->{$locus} } ) {
					next if $self->_is_match_outside_pcr_amplicon( $match, $product );
					$within_amplicon = 1;
				}
				next RECORD if !$within_amplicon;
			}
			if ( $probe_filter->{$locus} ) {
				next RECORD if !$self->_probe_filter_match( $locus, $match, $probe_matches->{$locus} );
			}

			#check if match already found with same predicted start or end points
			if ( !$self->_matches_existing_same_region( $matches->{$locus}, $match, $params->{'exemplar'} ) ) {
				push @{ $matches->{$locus} }, $match;
			}
		}
	}

	#Only return the number of matches selected by 'partial_matches' parameter
	my @loci;
	if ( $options->{'multiple_loci'} ) {
		@loci = keys %$matches;
	} else {
		@loci = ($locus);
	}
	foreach my $locus (@loci) {
		@{ $matches->{$locus} } = sort { $b->{'quality'} <=> $a->{'quality'} } @{ $matches->{$locus} };
		my $partial_matches = $params->{'scan_partial_matches'} // $params->{'partial_matches'};
		$partial_matches = 1 if !BIGSdb::Utils::is_int($partial_matches) || $partial_matches < 1;
		while ( @{ $matches->{$locus} } > $partial_matches ) {
			pop @{ $matches->{$locus} };
		}
		if ( $self->{'config'}->{'blat_path'} ) {
			foreach my $match ( @{ $matches->{$locus} } ) {
				$self->_check_introns( $params, $locus, $match );
			}
		}
	}
	undef $self->{'records'} if !$options->{'keep_data'};
	return $matches;
}

sub _cache_match_allele_length {
	my ( $self, $lengths, $locus, $allele_id ) = @_;
	return if $lengths->{$locus}->{$allele_id};
	if ( $allele_id eq 'ref' ) {
		$lengths->{$locus}->{$allele_id} =
		  $self->{'datastore'}->run_query( 'SELECT length(reference_sequence) FROM loci WHERE id=?',
			$locus, { cache => 'Scan::parse_blast_partial' } );
	} else {
		my $seq_ref = $self->{'datastore'}->get_locus($locus)->get_allele_sequence($allele_id);
		return if !$$seq_ref;
		$lengths->{$locus}->{$allele_id} = length($$seq_ref);
	}
	return;
}

sub _check_introns {
	my ( $self, $params, $locus, $match ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	return if !$locus_info->{'introns'};
	my $contig = $self->{'contigManager'}->get_contig( $match->{'seqbin_id'} );
	my $allele = $self->{'datastore'}->get_locus($locus)->get_allele_sequence( $match->{'allele'} );
	return if !ref $contig || !ref $allele;
	my $prefix      = BIGSdb::Utils::get_random();
	my $query_file  = "$self->{'config'}->{'secure_tmp_dir'}/${prefix}_query.fas";
	my $contig_file = "$self->{'config'}->{'secure_tmp_dir'}/${prefix}_contig.fas";
	my $out_file    = "$self->{'config'}->{'secure_tmp_dir'}/${prefix}.psl";
	open( my $fh, '>:encoding(utf8)', $query_file ) || $logger->error("Cannot open $query_file for writing");
	say $fh '>query';
	say $fh $$allele;
	close $fh;
	open( $fh, '>:encoding(utf8)', $contig_file ) || $logger->error("Cannot open $contig_file for writing");
	say $fh qq(>$match->{'seqbin_id'});
	say $fh $$contig;
	close $fh;

	#Run BLAT with a range of tileSize values (8 - 11). Stop if we find a match.
  TILE_SIZE: foreach my $tile_size ( reverse 6 .. 11 ) {
		my @args = ( $contig_file, $query_file, '-noHead', "-tileSize=$tile_size" );
		if ( $params->{'tblastx'} ) {
			push @args, '-t=dnax', '-q=dnax';
		}
		system( "$self->{'config'}->{'blat_path'} @args $out_file >/dev/null" );
		if ( -e $out_file ) {
			open( $fh, '<:encoding(utf8)', $out_file ) || $logger->error("Cannot open $out_file for reading");
			my $line = <$fh>;
			close $fh;
			if ($line) {
				my $exons        = [];
				my @values       = split /\t/x, $line;
				my $end_of_match = $values[16];
				my @starts       = split /,/x, $values[20];
				pop @starts if !BIGSdb::Utils::is_int( $starts[-1] );    #List has trailing comma
				my @block_lengths = split /,/x, $values[18];
				next TILE_SIZE if @starts <= 1;
				foreach my $i ( 0 .. @starts - 1 ) {
					my $start = $starts[$i] + 1;
					my $end   = $start + $block_lengths[$i] - 1;
					push @$exons, { start => $start, end => $end };
				}
				my $merged_exons = $self->_remove_short_introns( $exons, 20 );
				$match->{'predicted_start'} = $exons->[0]->{'start'};
				$match->{'predicted_end'}   = $exons->[-1]->{'end'};
				$match->{'exons'}           = $merged_exons;
				$self->{'introns_found'}    = 1;
				my $introns = [];
				foreach my $i ( 0 .. @$merged_exons - 1 ) {
					last if !defined $merged_exons->[ $i + 1 ];
					push @$introns,
					  {
						start => $merged_exons->[$i]->{'end'} + 1,
						end   => $merged_exons->[ $i + 1 ]->{'start'} - 1
					  };
				}
				$match->{'introns'} = $introns;
				last TILE_SIZE;
			}
		}
	}
	unlink $query_file, $contig_file, $out_file;
	return $match;
}

sub _remove_short_introns {
	my ( $self, $exons, $min_length ) = @_;
	my $merged = [];
	foreach my $exon (@$exons) {
		if ( !@$merged ) {
			push @$merged, $exon;
			next;
		}
		if ( $exon->{'start'} < $merged->[-1]->{'end'} + $min_length ) {
			$merged->[-1]->{'end'} = $exon->{'end'};
		} else {
			push @$merged, $exon;
		}
	}
	return $merged;
}

sub _is_match_outside_pcr_amplicon {
	my ( $self, $match, $product ) = @_;
	if (   $match->{'seqbin_id'} != $product->{'seqbin_id'}
		|| $match->{'start'} < $product->{'start'}
		|| $match->{'end'} > $product->{'end'} )
	{
		return 1;
	}
	return;
}

sub _matches_existing_same_region {
	my ( $self, $existing_matches, $match, $both_ends ) = @_;
	foreach my $existing_match (@$existing_matches) {
		if ( !$both_ends ) {
			return 1
			  if $existing_match->{'seqbin_id'} == $match->{'seqbin_id'}
			  && ( $existing_match->{'predicted_start'} == $match->{'predicted_start'}
				|| $existing_match->{'predicted_end'} == $match->{'predicted_end'} );
		} else {
			return 1
			  if $existing_match->{'seqbin_id'} == $match->{'seqbin_id'}
			  && $existing_match->{'predicted_start'} == $match->{'predicted_start'}
			  && $existing_match->{'predicted_end'} == $match->{'predicted_end'};
		}
	}
	return;
}

sub _get_designation_tooltip {
	my ( $self, $isolate_id, $locus, $status ) = @_;
	my $class;
	my $text;
	if ( $status eq 'existing' ) {
		$class = 'existing_tooltip';
		$text  = 'existing';
	} else {
		$class = 'clashing_tooltip';
		$text  = 'conflict';
	}
	my $designations = $self->{'datastore'}->get_allele_designations( $isolate_id, $locus );
	my $plural = @$designations == 1 ? '' : 's';
	my $buffer = "Existing designation$plural - ";
	foreach my $designation (@$designations) {
		my $sender = $self->{'datastore'}->get_user_info( $designation->{'sender'} );
		$buffer .= "allele: $designation->{'allele_id'} ";
		$buffer .= "($designation->{'comments'}) "
		  if $designation->{'comments'};
		$buffer .=
		  "[$sender->{'first_name'} $sender->{'surname'}; $designation->{'method'}; $designation->{'datestamp'}]<br />";
	}
	return qq( <a class="$class" title="$buffer">$text</a>);
}

sub is_complete_gene {
	my ( $self, $seq ) = @_;
	my $status = BIGSdb::Utils::is_complete_cds($seq);
	return $status->{'cds'};
}

sub _write_status {

	#Write status to a file in secure_tmp that can be read by viewing page.
	my ( $self, $scan_job, $data, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $status_file = "$self->{'config'}->{'secure_tmp_dir'}/$scan_job\_status.txt";
	unlink $status_file if $options->{'reset'};
	open( my $fh, '>>', $status_file ) || $logger->error("Can't open $status_file for appending");
	say $fh $data;
	close $fh;
	return;
}

sub _read_status {
	my ( $self, $scan_job ) = @_;
	my $status_file = "$self->{'config'}->{'secure_tmp_dir'}/$scan_job\_status.txt";
	my %data;
	return \%data if !-e $status_file;
	open( my $fh, '<', $status_file ) || $logger->error("Can't open $status_file for reading. $!");
	while ( my $line = <$fh> ) {
		if ( $line =~ /^(.*):(.*)$/x ) {
			$data{$1} = $2;
		}
	}
	close $fh;
	return \%data;
}

sub _write_match {

	#Write matches to a file in secure_tmp that can be read by tagging page.
	my ( $self, $scan_job, $data, $options ) = @_;
	$data //= '';
	$options = {} if ref $options ne 'HASH';
	my $match_file = "$self->{'config'}->{'secure_tmp_dir'}/$scan_job\_matches.txt";
	unlink $match_file if $options->{'reset'};
	open( my $fh, '>>', $match_file ) || $logger->error("Can't open $match_file for appending");
	say $fh $data;
	close $fh;
	return;
}

sub _simulate_PCR {
	my ( $self, $fasta_file, $locus ) = @_;
	my $q = $self->{'cgi'};
	my $reactions =
	  $self->{'datastore'}
	  ->run_query( 'SELECT pcr.* FROM pcr LEFT JOIN pcr_locus ON pcr.id = pcr_locus.pcr_id WHERE locus=?',
		$locus, { fetch => 'all_arrayref', slice => {}, cache => 'Scan::simulate_PCR' } );
	return if !@$reactions;
	my $temp          = BIGSdb::Utils::get_random();
	my $reaction_file = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_reactions.txt";
	my $results_file  = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_results.txt";
	open( my $fh, '>', $reaction_file ) || $logger->error("Can't open $reaction_file for writing");
	my $max_primer_mismatch = 0;
	my $conditions;

	foreach my $reaction (@$reactions) {
		foreach my $primer (qw (primer1 primer2)) {
			$reaction->{$primer} =~ tr/ //;
		}
		my $min_length = $reaction->{'min_length'} || 1;
		my $max_length = $reaction->{'max_length'} || 50000;
		$reaction->{'max_primer_mismatch'} //= 0;
		$max_primer_mismatch = $reaction->{'max_primer_mismatch'}
		  if $reaction->{'max_primer_mismatch'} > $max_primer_mismatch;
		if ( $q->param('alter_pcr_mismatches') && $q->param('alter_pcr_mismatches') =~ /([\-\+]\d)/x ) {
			my $delta = $1;
			$max_primer_mismatch += $delta;
			$max_primer_mismatch = 0 if $max_primer_mismatch < 0;
		}
		say $fh "$reaction->{'id'}\t$reaction->{'primer1'}\t$reaction->{'primer2'}\t$min_length\t$max_length";
		$conditions->{ $reaction->{'id'} } = $reaction;
	}
	close $fh;
	system( "$self->{'config'}->{'ipcress_path'} --input $reaction_file --sequence $fasta_file "
		  . "--mismatch $max_primer_mismatch --pretty false > $results_file 2> /dev/null" );
	my @pcr_products;
	open( $fh, '<', $results_file ) || $logger->error("Can't open $results_file for reading");
	while ( my $line = <$fh> ) {
		if ( $line =~ /^ipcress:/x ) {
			my ( undef, $seq_id, $reaction_id, $length, undef, $start, $mismatch1, undef, $end, $mismatch2, $desc ) =
			  split /\s+/x, $line;
			next if $desc =~ /single/x;    #product generated by one primer only.
			my ( $seqbin_id, undef ) = split /:/x, $seq_id;
			$logger->debug("Seqbin_id:$seqbin_id; $start-$end; mismatch1:$mismatch1; mismatch2:$mismatch2");
			next
			  if $mismatch1 > $conditions->{$reaction_id}->{'max_primer_mismatch'}
			  || $mismatch2 > $conditions->{$reaction_id}->{'max_primer_mismatch'};
			my $product = {
				'seqbin_id' => $seqbin_id,
				'start'     => $start,
				'end'       => $end,
				'mismatch1' => $mismatch1,
				'mismatch2' => $mismatch2
			};
			push @pcr_products, $product;
		}
	}
	close $fh;
	unlink $reaction_file, $results_file;
	return \@pcr_products;
}

sub _simulate_hybridization {
	my ( $self, $fasta_file, $locus ) = @_;
	my $q      = $self->{'cgi'};
	my $probes = $self->{'datastore'}->run_query(
		'SELECT probes.id,probes.sequence,probe_locus.* FROM probes LEFT JOIN probe_locus ON '
		  . 'probes.id = probe_locus.probe_id WHERE locus=?',
		$locus,
		{ fetch => 'all_arrayref', slice => {} }
	);
	return if !@$probes;
	my $file_prefix      = BIGSdb::Utils::get_random();
	my $probe_fasta_file = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_probe.txt";
	my $results_file     = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_results.txt";
	open( my $fh, '>', $probe_fasta_file )
	  or $logger->error("Can't open temp file $probe_fasta_file for writing");
	my %probe_info;

	foreach my $probe (@$probes) {
		$probe->{'sequence'} =~ s/\s//gx;
		print $fh ">$probe->{'id'}\n$probe->{'sequence'}\n";
		$probe->{'max_mismatch'} = 0 if !$probe->{'max_mismatch'};
		if ( $q->param('alter_probe_mismatches') && $q->param('alter_probe_mismatches') =~ /([\-\+]\d)/x ) {
			my $delta = $1;
			$probe->{'max_mismatch'} += $delta;
			$probe->{'max_mismatch'} = 0 if $probe->{'max_mismatch'} < 0;
		}
		$probe->{'max_gaps'} = 0 if !$probe->{'max_gaps'};
		$probe->{'min_alignment'} = length $probe->{'sequence'} if !$probe->{'min_alignment'};
		$probe_info{ $probe->{'id'} } = $probe;
	}
	close $fh;
	system( "$self->{'config'}->{'blast+_path'}/makeblastdb",
		( -in => $fasta_file, -logfile => '/dev/null', -dbtype => 'nucl' ) );
	my $blast_threads = $self->{'config'}->{'blast_threads'} || 1;
	system(
		"$self->{'config'}->{'blast+_path'}/blastn",
		(
			-task            => 'blastn',
			-num_threads     => $blast_threads,
			-max_target_seqs => 1000,
			-db              => $fasta_file,
			-out             => $results_file,
			-query           => $probe_fasta_file,
			-outfmt          => 6,
			-dust            => 'no'
		)
	);
	my @matches;
	if ( -e $results_file ) {
		open( $fh, '<', $results_file ) || $logger->error("Can't open $results_file for reading");
		while ( my $line = <$fh> ) {
			my @record = split /\t/x, $line;
			my $match;
			$match->{'probe_id'}  = $record[0];
			$match->{'seqbin_id'} = $record[1];
			$match->{'alignment'} = $record[3];
			next if $match->{'alignment'} < $probe_info{ $match->{'probe_id'} }->{'min_alignment'};
			$match->{'mismatches'} = $record[4];
			next if $match->{'mismatches'} > $probe_info{ $match->{'probe_id'} }->{'max_mismatch'};
			$match->{'gaps'} = $record[5];
			next if $match->{'gaps'} > $probe_info{ $match->{'probe_id'} }->{'max_gaps'};

			if ( $record[8] < $record[9] ) {
				$match->{'start'} = $record[8];
				$match->{'end'}   = $record[9];
			} else {
				$match->{'start'} = $record[9];
				$match->{'end'}   = $record[8];
			}
			$logger->debug("Seqbin: $match->{'seqbin_id'}; Start: $match->{'start'}; End: $match->{'end'}");
			push @matches, $match;
		}
		close $fh;
		unlink $results_file;
	}
	unlink $probe_fasta_file;
	return \@matches;
}

sub _probe_filter_match {
	my ( $self, $locus, $blast_match, $probe_matches ) = @_;
	my $good_match = 0;
	foreach my $match (@$probe_matches) {
		if ( !$self->{'probe_locus'}->{$locus}->{ $match->{'probe_id'} } ) {
			$self->{'probe_locus'}->{$locus}->{ $match->{'probe_id'} } = $self->{'datastore'}->run_query(
				'SELECT * FROM probe_locus WHERE locus=? AND probe_id=?',
				[ $locus, $match->{'probe_id'} ],
				{ fetch => 'row_hashref' }
			);
		}
		next if $blast_match->{'seqbin_id'} != $match->{'seqbin_id'};
		my $probe_distance = -1;
		if ( $blast_match->{'start'} > $match->{'end'} ) {
			$probe_distance = $blast_match->{'start'} - $match->{'end'};
		}
		if ( $blast_match->{'end'} < $match->{'start'} ) {
			my $end_distance = $match->{'start'} - $blast_match->{'end'};
			if ( ( $end_distance < $probe_distance ) || ( $probe_distance == -1 ) ) {
				$probe_distance = $end_distance;
			}
		}
		next
		  if ( $probe_distance > $self->{'probe_locus'}->{$locus}->{ $match->{'probe_id'} }->{'max_distance'} )
		  || $probe_distance == -1;
		return 1;
	}
	return 0;
}
1;
