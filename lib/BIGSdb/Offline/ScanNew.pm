#Written by Keith Jolley
#Copyright (c) 2014-2019, University of Oxford
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
use BIGSdb::Exceptions;
use Digest::MD5;
use Try::Tiny;
use constant DEFAULT_ALIGNMENT => 100;
use constant DEFAULT_IDENTITY  => 99;
use constant DEFAULT_WORD_SIZE => 30;
use constant DEFINER_USER      => -1;              #User id for tagger (there needs to be a record in the users table)
use constant DEFINER_USERNAME  => 'autodefiner';

sub run_script {
	my ($self) = @_;
	return $self if $self->{'options'}->{'query_only'};    #Return script object to allow access to methods
	$self->{'exit'} = 0;
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1 } ) x 3; #Allow temp files to be cleaned on kill signals
	die "No connection to database (check logs).\n" if !defined $self->{'db'};
	die "This script can only be run against an isolate database.\n"
	  if ( $self->{'system'}->{'dbtype'} // '' ) ne 'isolates';
	my $params = $self->_get_params;
	my $loci   = $self->get_loci_with_ref_db;

	if ( $self->{'options'}->{'a'} && !$self->_can_define_alleles($loci) ) {
		exit(1);
	}
	my $isolates      = $self->get_isolates_with_linked_seqs;
	my $isolate_list  = $self->filter_and_sort_isolates($isolates);
	my $isolate_count = @$isolate_list;
	my $plural        = $isolate_count == 1 ? '' : 's';
	$self->initiate_job_manager if $self->{'options'}->{'mark_job'};
	my $job_id = $self->add_job('ScanNew');
	$self->{'start_time'} = time;
	$self->{'logger'}->info("$self->{'options'}->{'d'}#pid$$:Autodefiner start ($isolate_count genome$plural)");

	if ( $params->{'fast'} ) {
		$self->_scan_loci_together( $isolate_list, $loci, $params );
	} else {
		$self->_scan_locus_by_locus( $isolate_list, $loci, $params );
	}
	my $stop          = time;
	my $duration      = $stop - $self->{'start_time'};
	my $nice_duration = BIGSdb::Utils::get_nice_duration($duration);
	$self->{'logger'}->info("$self->{'options'}->{'d'}#pid$$:Autodefiner stop ($nice_duration)");
	$self->stop_job($job_id);
	return;
}

sub _scan_loci_together {
	my ( $self, $isolate_list, $loci, $params ) = @_;
	my $i              = 0;
	my $total          = @$isolate_list;
	my $isolate_prefix = BIGSdb::Utils::get_random();
	my $locus_prefix   = BIGSdb::Utils::get_random();
	my $seqs           = {};
  ISOLATE: foreach my $isolate_id (@$isolate_list) {
		$i++;
		my $complete = BIGSdb::Utils::decimal_place( ( $i * 100 / @$isolate_list ), 1 );
		$self->{'logger'}->info("$self->{'options'}->{'d'}#pid$$:Checking isolate $isolate_id - $i/$total($complete%)");
		my ( @loci_to_scan, @loci_to_check );
		my $allele_seq = {};
		if ( $self->{'options'}->{'reuse_blast'} ) {
			@loci_to_scan = @$loci;
		}
	  LOCUS: foreach my $locus (@$loci) {
			my $existing_allele_ids = $self->{'datastore'}->get_allele_ids( $isolate_id, $locus );
			next if @$existing_allele_ids;
			$allele_seq->{$locus} = $self->{'datastore'}->get_allele_sequence( $isolate_id, $locus );
			next if @{ $allele_seq->{$locus} } && !$self->{'options'}->{'T'};
			push @loci_to_check, $locus;
			if ( !$self->{'options'}->{'reuse_blast'} ) {
				push @loci_to_scan, $locus;
			}
		}
		my ( $exact_matches, $partial_matches ) =
		  $self->blast_multiple_loci( $params, \@loci_to_scan, $isolate_id, $isolate_prefix, $locus_prefix );
	  LOCUS: foreach my $locus (@loci_to_check) {
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			next if ref $exact_matches->{$locus} && @{ $exact_matches->{$locus} };
			my $matches = $partial_matches->{$locus} // [];
			foreach my $match (@$matches) {
				$self->_handle_match( $locus_info, $match, $seqs );
			}
		}

		#Delete isolate seqbin FASTA
		$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$isolate_prefix*");

		#Delete locus working files
		if ( !$self->{'options'}->{'reuse_blast'} ) {
			$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$locus_prefix*");
		}
		last ISOLATE if $self->{'exit'} || $self->_is_time_up;
	}

	#Delete locus working files
	$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$locus_prefix*");
	return;
}

sub _scan_locus_by_locus {
	my ( $self, $isolate_list, $loci, $params ) = @_;
	my $isolate_prefix = $self->{'options'}->{'prefix'} || BIGSdb::Utils::get_random();
	my $locus_prefix   = BIGSdb::Utils::get_random();
	my $first          = 1;
	my $i              = 0;
  LOCUS: foreach my $locus (@$loci) {
		$i++;
		my $complete = BIGSdb::Utils::decimal_place( ( $i * 100 / @$loci ), 1 );
		$self->{'logger'}->info( "$self->{'options'}->{'d'}#pid$$:Checking $locus - $i/" . (@$loci) . "($complete%)" );
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		my $seqs       = {};
	  ISOLATE: foreach my $isolate_id (@$isolate_list) {
			my $allele_ids = $self->{'datastore'}->get_allele_ids( $isolate_id, $locus );
			next if @$allele_ids;
			if ( !$self->{'options'}->{'T'} ) {
				my $allele_seq = $self->{'datastore'}->get_allele_sequence( $isolate_id, $locus );
				next if @$allele_seq;
			}
			my ( $exact_matches, $partial_matches ) =
			  $self->blast( $params, $locus, $isolate_id, "${isolate_prefix}_$isolate_id", $locus_prefix );
			next if ref $exact_matches && @$exact_matches;
			foreach my $match (@$partial_matches) {
				$self->_handle_match( $locus_info, $match, $seqs );
			}
			last if $self->{'exit'} || $self->_is_time_up;
		}
		$self->{'datastore'}->finish_with_locus($locus);

		#Delete locus working files
		$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$locus_prefix*");
		last if $self->{'exit'} || $self->_is_time_up;
	}

	#Delete isolate working files
	#Only delete if single threaded (we'll delete when all threads finished in multithreaded).
	$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$isolate_prefix*")
	  if !$self->{'options'}->{'prefix'};
	return;
}

sub _handle_match {
	my ( $self, $locus_info, $match, $seqs ) = @_;
	use Data::Dumper;
	return if $self->_off_end_of_contig($match);
	my $seq = $self->extract_seq_from_match($match);
	my ( $reject, $flag ) = $self->_check_cds($seq);
	return if $reject;
	my $locus = $locus_info->{'id'};
	if ( $locus_info->{'data_type'} eq 'peptide' ) {
		my $seq_obj = Bio::Seq->new( -seq => $seq, -alphabet => 'dna' );
		$seq = $seq_obj->translate->seq;
	}
	my $seq_hash = Digest::MD5::md5_hex($seq);
	return if $seqs->{$locus}->{$seq_hash};
	$seqs->{$locus}->{$seq_hash} = 1;
	return if $self->_check_sub_or_super_seq( $locus, $seq );
	if ( $self->{'options'}->{'a'} ) {
		return if $locus_info->{'data_type'} eq 'DNA' && $seq =~ /[^GATC]/x;
		my $allele_id = $self->_define_allele( $locus, $seq, $flag );
		say ">$locus-$allele_id";
		say $seq;
	} else {
		say "$locus\t\tWGS: automated extract (BIGSdb)\t$seq\t$flag";
	}
	return;
}

sub _check_cds {
	my ( $self, $seq ) = @_;
	my $reject       = 0;
	my $flag         = q();
	my $complete_cds = BIGSdb::Utils::is_complete_cds($seq);
	if ( $self->{'options'}->{'c'} && !$complete_cds->{'cds'} ) {
		if ( $self->{'options'}->{'allow_frameshift'} ) {
			$complete_cds->{'err'} //= q();
			if ( $complete_cds->{'err'} =~ /internal\ stop\ codon/x ) {
				$flag = 'internal stop codon';
			} elsif ( $complete_cds->{'err'} =~ /multiple\ of\ 3/x ) {
				$flag = 'frameshift';
			} else {    #Sequence does not have start or stop codon.
				$reject = 1;
			}
		} else {
			$reject = 1;
		}
	}
	return ( $reject, $flag );
}

sub _check_sub_or_super_seq {
	my ( $self, $locus_name, $seq ) = @_;
	return if $self->{'options'}->{'allow_subsequences'};
	my $locus = $self->{'datastore'}->get_locus($locus_name);
	my $time  = time;
	return 1 if $locus->is_seq_a_subsequence_of_allele( \$seq );
	return 1 if $locus->is_seq_a_supersequence_of_allele( \$seq );
	return;
}

sub _get_params {
	my ($self) = @_;
	my $params;
	$params->{$_} = 1 foreach qw(pcr_filter probe_filter scannew);
	$params->{'alignment'} =
	  BIGSdb::Utils::is_int( $self->{'options'}->{'A'} ) ? $self->{'options'}->{'A'} : DEFAULT_ALIGNMENT;
	$params->{'identity'} =
	  BIGSdb::Utils::is_int( $self->{'options'}->{'B'} ) ? $self->{'options'}->{'B'} : DEFAULT_IDENTITY;
	if ( BIGSdb::Utils::is_int( $self->{'options'}->{'w'} ) ) {
		$params->{'word_size'} = $self->{'options'}->{'w'};
	} else {
		if ( $self->{'options'}->{'exemplar'} ) {

			#More stringent if checking using exemplar alleles.
			$params->{'word_size'} = 15;
		} else {
			$params->{'word_size'} = DEFAULT_WORD_SIZE;
		}
	}
	$params->{$_} = $self->{'options'}->{$_} foreach qw(exemplar fast type_alleles reuse_blast);
	return $params;
}

sub _define_allele {
	my ( $self, $locus, $seq, $flag ) = @_;
	my $locus_info     = $self->{'datastore'}->get_locus_info($locus);
	my $data_connector = $self->{'datastore'}->get_data_connector;
	my $can_define     = 1;
	my $allele_id;
	try {
		my $locus_db = $data_connector->get_connection(
			{
				host       => $locus_info->{'dbase_host'},
				port       => $locus_info->{'dbase_port'},
				user       => $locus_info->{'dbase_user'},
				password   => $locus_info->{'dbase_password'},
				dbase_name => $locus_info->{'dbase_name'}
			}
		);
		$allele_id = $self->{'datastore'}->get_next_allele_id( $locus, { db => $locus_db } );
		eval {
			$locus_db->do(
				'INSERT INTO sequences (locus,allele_id,sequence,status,date_entered,datestamp,'
				  . 'sender,curator) VALUES (?,?,?,?,?,?,?,?)',
				undef,
				$locus,
				$allele_id,
				$seq,
				'WGS: automated extract (BIGSdb)',
				'now',
				'now',
				DEFINER_USER,
				DEFINER_USER
			);
			if ($flag) {
				$locus_db->do( 'INSERT INTO allele_flags (locus,allele_id,flag,curator,datestamp) VALUES (?,?,?,?,?)',
					undef, $locus, $allele_id, $flag, DEFINER_USER, 'now' );
			}
		};
		if ($@) {
			if ( $@ =~ /duplicate key value/ ) {
				$self->{'logger'}->info("Duplicate allele: $locus-$allele_id (can't define)");
				say 'Cannot add new allele - duplicate. Somebody else has probably '
				  . 'defined allele in the past few minutes.';
			} else {
				$self->{'logger'}->error($@);
				say "Can't add new allele. Error: $@";
				$can_define = 0;
			}
			$locus_db->rollback;
		} else {
			$locus_db->commit;
			$self->{'logger'}->info("New allele defined: $locus-$allele_id");
		}
	}
	catch {
		if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
			$self->{'logger'}->error("Cannot connect to database for locus $locus");
			say "Can not connect to database for locus $locus";
			$can_define = 0;
		} else {
			$self->{'logger'}->logdie($_);
		}
	};
	exit(1) if !$can_define;
	return $allele_id;
}

sub _off_end_of_contig {
	my ( $self, $match ) = @_;
	my $seqbin_length = $self->{'datastore'}->run_query(
		'SELECT GREATEST(r.length,length(s.sequence)) FROM sequence_bin s LEFT JOIN '
		  . 'remote_contigs r ON s.id=r.seqbin_id WHERE s.id=?',
		$match->{'seqbin_id'},
		{ cache => 'ScanNew::off_end_of_contig' }
	);
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

sub _can_define_alleles {
	my ( $self, $loci ) = @_;
	my $data_connector = $self->{'datastore'}->get_data_connector;
	my $can_define     = 1;
	foreach my $locus (@$loci) {
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		if ( $locus_info->{'allele_id_format'} ne 'integer' ) {
			$self->{'logger'}->error("Locus $locus does not use integer identifiers.");
			say "Locus $locus does not use integer identifiers.";
			$can_define = 0;
			last;
		}
		try {
			my $locus_db = $data_connector->get_connection(
				{
					host       => $locus_info->{'dbase_host'},
					port       => $locus_info->{'dbase_port'},
					user       => $locus_info->{'dbase_user'},
					password   => $locus_info->{'dbase_password'},
					dbase_name => $locus_info->{'dbase_name'}
				}
			);
			my $user_exists = $self->{'datastore'}->run_query(
				'SELECT EXISTS(SELECT * FROM users WHERE (id,user_name)=(?,?))',
				[ DEFINER_USER, DEFINER_USERNAME ],
				{ db => $locus_db }
			);
			if ( !$user_exists ) {
				$self->{'logger'}->error("Autodefiner user does not exist in database for locus $locus.");
				say "Autodefiner user does not exist in database for locus $locus.";
				$can_define = 0;
			}
			my $extended_attributes =
			  $self->{'datastore'}
			  ->run_query( 'SELECT EXISTS(SELECT * FROM locus_extended_attributes WHERE locus=? AND required)',
				$locus, { db => $locus_db, cache => 'ScanNew::can_define_alleles_attributes' } );
			if ($extended_attributes) {
				$self->{'logger'}->error("Locus $locus has required extended attributes.");
				say "Locus $locus has required extended attributes.";
				$can_define = 0;
			}
		}
		catch {
			if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
				$self->{'logger'}->error("Cannot connect to database for locus $locus");
				say "Cannot connect to database for locus $locus";
				$can_define = 0;
			} else {
				$self->{'logger'}->logdie($_);
			}
		};
		last if !$can_define;
	}
	return $can_define;
}

1;
