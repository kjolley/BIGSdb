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
use Digest::MD5;
use File::Path qw(make_path remove_tree);
use Fcntl qw(:flock);
use constant INF => 9**99;

sub run_script {
	my ($self) = @_;

	#	my $params  = $self->{'params'};
	#	my $options = $self->{'options'};
	my $loci = $self->get_selected_loci;
	throw BIGSdb::DataException('Invalid loci') if !@$loci;
	$self->_blast($loci);
	return;
}

sub _blast {
	my ( $self, $loci ) = @_;
	my $job      = BIGSdb::Utils::get_random();
	my $in_file  = "$self->{'config'}->{'secure_tmp_dir'}/$job.txt";
	my $out_file = "$self->{'config'}->{'secure_tmp_dir'}/${job}_outfile.txt";
	my $options  = $self->{'options'};
	my $runs     = [qw(DNA peptide)];
	foreach my $run (@$runs) {
		my $loci_by_type = $self->_get_selected_loci_by_type( $loci, $run );
		next if !@$loci_by_type;
		my $cache_name = $self->_get_cache_name($loci_by_type);
		if ( !$self->_cache_exists($cache_name) ) {
			$self->_create_blast_database( $cache_name, $run, $loci_by_type );
		}
		my $path      = $self->_get_cache_dir($cache_name);
		my $lock_file = "$path/LOCK";
		if ( -e $lock_file ) {

			#Wait for lock to clear - database is being created by other process.
			open( my $lock_fh, '<', $lock_file ) || $self->{'logger'}->error('Cannot read lock file.');
			flock( $lock_fh, LOCK_SH ) or $self->{'logger'}->error("Cannot flock $lock_file: $!");
			close $lock_fh;
		}
		my $qry_type      = BIGSdb::Utils::sequence_type( $options->{'sequence'} );
		my $program       = $self->_determine_blast_program( $run, $qry_type );
		my $blast_threads = $options->{'threads'} // $self->{'config'}->{'blast_threads'} // 1;
		my $filter        = $program eq 'blastn' ? 'dust' : 'seg';
		my $word_size     = $program eq 'blastn' ? ( $options->{'word_size'} // 15 ) : 3;
		my $format        = $options->{'alignment'} ? 0 : 6;
		$options->{'num_results'} //= 1_000_000;    #effectively return all results
		my $fasta_file   = "$path/sequences.fas";
		my $shortest_seq = $self->_get_shortest_seq_length($fasta_file);
		say "format: $format";
		say "shortest seq: $shortest_seq";
		say "threads: $blast_threads";
		say "word size: $word_size";
		say "$run: $cache_name $program";
		my %params = (
			-num_threads => $blast_threads,
			-word_size   => $word_size,
			-db          => $fasta_file,
			-query       => $in_file,
			-out         => $out_file,
			-outfmt      => $format,
			-$filter     => 'no'
		);

		if ( $options->{'alignment'} ) {
			$params{'-num_alignments'} = $options->{'num_results'};
		} else {
			$params{'-max_target_seqs'} = $options->{'num_results'};
		}

		#Ensure matches with low-complexity regions are returned.
		if ( $program ne 'blastn' && $program ne 'tblastx' ) {
			$params{'-comp_based_stats'} = 0;
		}

		#Very short sequences won't be matched unless we increase the expect value significantly
		if ( $shortest_seq <= 20 ) {
			$params{'-evalue'} = 1000;
		}
		use Data::Dumper;
		say Dumper \%params;
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

sub _create_blast_database {
	my ( $self, $cache_name, $data_type, $loci, $exemplar ) = @_;
	my $path = $self->_get_cache_dir($cache_name);

	#Prevent two makeblastdb processes running in the same directory
	make_path($path);

	#This method may be called by apache during a web query or by the bigsdb user
	#if called from external script. We need to make sure that files can be overwritten
	#by both. bigsdb should be a member of the apache group and vice versa.
	chmod 0775, $path;
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
	open( my $fasta_fh, '>', $fasta_file ) || $self->{'logger'}->error("Cannot open $fasta_file for writing");
	flock( $fasta_fh, LOCK_EX ) or $self->{'logger'}->error("Cannot flock $fasta_file: $!");

	foreach my $allele (@$data) {
		say $fasta_fh ">$allele->[0]:$allele->[1]\n$allele->[2]";
	}
	close $fasta_fh;
	my $db_type = $data_type eq 'DNA' ? 'nucl' : 'prot';
	system( "$self->{'config'}->{'blast+_path'}/makeblastdb",
		( -in => $fasta_file, -logfile => '/dev/null', -dbtype => $db_type ) );
	if ($lock_fh) {
		close $lock_fh;
		unlink $lock_file;
	}
	return;
}

sub _get_cache_dir {
	my ( $self, $cache_name ) = @_;
	return "$self->{'config'}->{'secure_tmp_dir'}/$self->{'system'}->{'db'}/$cache_name";
}

sub _cache_exists {
	my ( $self, $cache_name ) = @_;
	my $path = $self->_get_cache_dir($cache_name);
	return if !-e $path;
	my $cache_is_stale = -e "$path/stale";
	my $cache_age      = $self->_get_cache_age($cache_name);
	if ( $cache_age > $self->{'config'}->{'cache_days'} || $cache_is_stale ) {
		$self->_delete_cache($cache_name);
		return;
	}
	return 1;
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
	say 'deleting cache';
	my $path       = $self->_get_cache_dir($cache_name);
	my $fasta_file = "$path/sequences.fas";
	open( my $fasta_fh, '<', $fasta_file ) || $self->{'logger'}->error("Cannot open $fasta_file for reading");
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
	my ( $self, $loci ) = @_;
	local $" = q(,);
	return Digest::MD5::md5_hex(qq(@$loci));
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
1;
