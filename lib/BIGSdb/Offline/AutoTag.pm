#Written by Keith Jolley
#Copyright (c) 2011-2016, University of Oxford
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
package BIGSdb::Offline::AutoTag;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Offline::Scan);
use BIGSdb::Utils;
use BIGSdb::BIGSException;
use Error qw(:try);
use constant TAG_USER          => -1;             #User id for tagger (there needs to be a record in the users table)
use constant TAG_USERNAME      => 'autotagger';
use constant DEFAULT_WORD_SIZE => 60;             #Only looking for exact matches
use constant MISSING_ALLELE_ALIGNMENT => 30;
use constant MISSING_ALLELE_IDENTITY  => 50;
use constant PROBLEM                  => 1;

sub run_script {
	my ($self) = @_;
	return $self if $self->{'options'}->{'query_only'};    #Return script object to allow access to methods
	my $params = $self->_get_params;
	die "No connection to database (check logs).\n" if !defined $self->{'db'};
	die "This script can only be run against an isolate database.\n"
	  if ( $self->{'system'}->{'dbtype'} // '' ) ne 'isolates';
	my $tag_user_id = TAG_USER;
	$self->{'username'} = TAG_USERNAME;
	my $user_ok = $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM users WHERE (id,user_name)=(?,?))',
		[ $tag_user_id, $self->{'username'} ] );
	die "Database user '$self->{'username'}' not set.  Enter a user '$self->{'username'}' with id $tag_user_id\n"
	  . "in the database to represent the auto tagger.\n"
	  if !$user_ok;
	my $isolates     = $self->get_isolates_with_linked_seqs;
	my $isolate_list = $self->filter_and_sort_isolates($isolates);

	if ( !@$isolate_list ) {
		exit(0) if $self->{'options'}->{'n'};
		die "No isolates selected.\n";
	}
	my $loci = $self->get_loci_with_ref_db;
	die "No valid loci selected.\n" if !@$loci;
	$self->{'start_time'} = time;
	$self->{'logger'}->info("$self->{'options'}->{'d'}#pid$$:Autotagger start");
	if ( $params->{'fast'} ) {
		$self->_scan_loci_together( $isolate_list, $loci, $params );
	} else {
		$self->_scan_locus_by_locus( $isolate_list, $loci, $params );
	}
	my $stop     = time;
	my $duration = $stop - $self->{'start_time'};
	$self->{'logger'}->info("$self->{'options'}->{'d'}#pid$$:Autotagger stop ($duration s)");
	return;
}

sub _scan_loci_together {
	my ( $self, $isolate_list, $loci, $params ) = @_;
	my $EXIT = 0;
	local @SIG{qw (INT TERM HUP)} = ( sub { $EXIT = 1 } ) x 3;    #Allow temp files to be cleaned on kill signals
	my $i              = 0;
	my $isolate_prefix = BIGSdb::Utils::get_random();
	my $locus_prefix   = BIGSdb::Utils::get_random();
  ISOLATE: foreach my $isolate_id (@$isolate_list) {
		$i++;
		my $complete = BIGSdb::Utils::decimal_place( ( $i * 100 / @$isolate_list ), 1 );
		$self->{'logger'}->info(
			"$self->{'options'}->{'d'}#pid$$:Checking isolate $isolate_id - $i/" . (@$isolate_list) . "($complete%)" );
		undef $self->{'history'};
		my @loci_to_tag;
		my $allele_seq = {};
		foreach my $locus (@$loci) {
			my $existing_allele_ids = $self->{'datastore'}->get_allele_ids( $isolate_id, $locus );
			next if @$existing_allele_ids;
			$allele_seq->{$locus} = $self->{'datastore'}->get_allele_sequence( $isolate_id, $locus );
			next if @{ $allele_seq->{$locus} } && !$self->{'options'}->{'T'};
			next
			  if !@{ $allele_seq->{$locus} } && !@$existing_allele_ids && $self->{'options'}->{'only_already_tagged'};
			push @loci_to_tag, $locus;
		}
		my ( $exact_matches, $partial_matches ) =
		  $self->blast_multiple_loci( $params, \@loci_to_tag, $isolate_id, $isolate_prefix, $locus_prefix );
		my $blast_status_bad = $?;
	  LOCUS: foreach my $locus (@loci_to_tag) {
			if ( ref $exact_matches->{$locus} && @{ $exact_matches->{$locus} } ) {
				my $ret_val = $self->_handle_match(
					{
						isolate_id     => $isolate_id,
						locus          => $locus,
						exact_matches  => $exact_matches->{$locus},
						allele_seq     => $allele_seq->{$locus},
						isolate_prefix => $isolate_prefix,
						locus_prefix   => $locus_prefix
					}
				);
				last ISOLATE if $ret_val;
			} elsif ( $self->{'options'}->{'0'} && !$blast_status_bad ) {
				my $ret_val = $self->_handle_no_match(
					{
						isolate_id      => $isolate_id,
						locus           => $locus,
						partial_matches => $partial_matches->{$locus},
						isolate_prefix  => $isolate_prefix,
						locus_prefix    => $locus_prefix
					}
				);
				last ISOLATE if $ret_val;
			}
			last if $EXIT || $self->_is_time_up;
		}
		$self->_update_isolate_history( $isolate_id, $self->{'history'} );

		#Delete isolate seqbin FASTA
		$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$isolate_prefix*");

		#Delete locus working files
		$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$locus_prefix*");
	}
	return;
}

sub _scan_locus_by_locus {
	my ( $self, $isolate_list, $loci, $params ) = @_;
	my $EXIT = 0;
	local @SIG{qw (INT TERM HUP)} = ( sub { $EXIT = 1 } ) x 3;    #Allow temp files to be cleaned on kill signals
	my $isolate_prefix = BIGSdb::Utils::get_random();
	my $locus_prefix   = BIGSdb::Utils::get_random();
	my $i              = 0;
  ISOLATE: foreach my $isolate_id (@$isolate_list) {
		$i++;
		my $complete = BIGSdb::Utils::decimal_place( ( $i * 100 / @$isolate_list ), 1 );
		$self->{'logger'}->info(
			"$self->{'options'}->{'d'}#pid$$:Checking isolate $isolate_id - $i/" . (@$isolate_list) . "($complete%)" );
		undef $self->{'history'};
	  LOCUS: foreach my $locus (@$loci) {
			last if $EXIT || $self->_is_time_up;
			my $existing_allele_ids = $self->{'datastore'}->get_allele_ids( $isolate_id, $locus );
			next if @$existing_allele_ids;
			my $allele_seq = $self->{'datastore'}->get_allele_sequence( $isolate_id, $locus );
			next if @$allele_seq && !$self->{'options'}->{'T'};
			next if !@$allele_seq && !@$existing_allele_ids && $self->{'options'}->{'only_already_tagged'};
			my ( $exact_matches, $partial_matches ) =
			  $self->blast( $params, $locus, $isolate_id, $isolate_prefix, $locus_prefix );
			my $blast_status_bad = $?;

			if ( ref $exact_matches && @$exact_matches ) {
				my $ret_val = $self->_handle_match(
					{
						isolate_id     => $isolate_id,
						locus          => $locus,
						exact_matches  => $exact_matches,
						allele_seq     => $allele_seq,
						isolate_prefix => $isolate_prefix,
						locus_prefix   => $locus_prefix
					}
				);
				last ISOLATE if $ret_val;
			} elsif ( $self->{'options'}->{'0'} && !$blast_status_bad ) {
				my $ret_val = $self->_handle_no_match(
					{
						isolate_id      => $isolate_id,
						locus           => $locus,
						partial_matches => $partial_matches,
						isolate_prefix  => $isolate_prefix,
						locus_prefix    => $locus_prefix
					}
				);
				last ISOLATE if $ret_val;
			}
		}
		$self->_update_isolate_history( $isolate_id, $self->{'history'} );

		#Delete isolate seqbin FASTA
		$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$isolate_prefix*");
		last if $EXIT || $self->_is_time_up;
	}

	#Delete locus working files
	$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$locus_prefix*");
	if ( $self->_is_time_up && !$self->{'options'}->{'q'} ) {
		say "Time limit reached ($self->{'options'}->{'t'} minute"
		  . ( $self->{'options'}->{'t'} == 1 ? '' : 's' ) . ')';
	}
	return;
}

sub _get_params {
	my ($self) = @_;
	my $params = {};
	$params->{$_} = 1 foreach qw(pcr_filter probe_filter);
	if ( BIGSdb::Utils::is_int( $self->{'options'}->{'w'} ) ) {
		$params->{'word_size'} = $self->{'options'}->{'w'};
	} else {
		if ( $self->{'options'}->{'0'} || $self->{'options'}->{'exemplar'} ) {

			#More stringent if checking for missing loci or using exemplar alleles.
			$params->{'word_size'} = 15;
		} else {
			$params->{'word_size'}          = DEFAULT_WORD_SIZE;
			$params->{'exact_matches_only'} = 1;
		}
	}
	if ( $self->{'options'}->{'0'} ) {
		$params->{'alignment'} = MISSING_ALLELE_ALIGNMENT;
		$params->{'identity'}  = MISSING_ALLELE_IDENTITY;
	}
	$params->{$_} = $self->{'options'}->{$_} foreach qw(exemplar fast);
	$params->{'partial_matches'} = 100 if $self->{'options'}->{'exemplar'};
	return $params;
}

sub _handle_match {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $locus, $exact_matches, $allele_seq, $isolate_prefix, $locus_prefix ) =
	  @{$args}{qw(isolate_id locus exact_matches allele_seq isolate_prefix locus_prefix)};
	print "Isolate: $isolate_id; Locus: $locus; " if !$self->{'options'}->{'q'};
	foreach (@$exact_matches) {
		next if !$_->{'allele'};
		print "Allele: $_->{'allele'} " if !$self->{'options'}->{'q'};
		my $sender = $self->{'datastore'}->run_query( 'SELECT sender FROM sequence_bin WHERE id=?',
			$_->{'seqbin_id'}, { cache => 'AutoTag::run_script_sender' } );
		my $problem;
		try {
			$self->_tag_allele(
				{ isolate_id => $isolate_id, locus => $locus, allele_id => $_->{'allele'}, sender => $sender } );
			if ( !$self->{'options'}->{'T'} || !@$allele_seq ) {
				$self->_tag_sequence(
					{
						seqbin_id => $_->{'seqbin_id'},
						locus     => $locus,
						allele_id => $_->{'allele'},
						start_pos => $_->{'start'},
						end_pos   => $_->{'end'},
						reverse   => $_->{'reverse'}
					}
				);
			}
		}
		catch BIGSdb::DatabaseException with {
			$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$isolate_prefix*");
			$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$locus_prefix*");
			$problem = PROBLEM;
		};
		if ($problem) {
			$self->_update_isolate_history( $isolate_id, $self->{'history'} );
			return PROBLEM;
		}
	}
	print "\n" if !$self->{'options'}->{'q'};
	return;
}

sub _handle_no_match {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $locus, $partial_matches, $isolate_prefix, $locus_prefix ) =
	  @{$args}{qw(isolate_id locus partial_matches isolate_prefix locus_prefix)};
	if ( ref $partial_matches && @$partial_matches ) {
		foreach my $match (@$partial_matches) {
			return
			  if $match->{'identity'} >= MISSING_ALLELE_IDENTITY
			  && $match->{'alignment'} >= MISSING_ALLELE_ALIGNMENT;
		}
	}
	say "Isolate: $isolate_id; Locus: $locus; Allele: 0 " if !$self->{'options'}->{'q'};
	my $problem = 0;
	try {
		$self->_tag_allele(
			{
				isolate_id => $isolate_id,
				locus      => $locus,
				allele_id  => '0',
				status     => 'provisional',
				sender     => TAG_USER
			}
		);
	}
	catch BIGSdb::DatabaseException with {
		$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$isolate_prefix*");
		$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$locus_prefix*");
		$problem = PROBLEM;
	};
	if ($problem) {
		$self->_update_isolate_history( $isolate_id, $self->{'history'} );
		return PROBLEM;
	}
	return;
}

sub _update_isolate_history {
	my ( $self, $isolate_id, $history ) = @_;
	return if ref $history ne 'ARRAY' || !@$history;
	local $" = '<br />';
	$self->update_history( $isolate_id, "@$history" );
	return;
}

sub _is_time_up {
	my ($self) = @_;
	if ( $self->{'options'}->{'t'} && BIGSdb::Utils::is_int( $self->{'options'}->{'t'} ) ) {
		return 1 if time > ( $self->{'start_time'} + $self->{'options'}->{'t'} * 60 );
	}
	return;
}

sub _tag_allele {
	my ( $self, $values ) = @_;
	my $existing_designations =
	  $self->{'datastore'}->get_allele_designations( $values->{'isolate_id'}, $values->{'locus'} );
	foreach my $designation (@$existing_designations) {
		return if $designation->{'allele_id'} eq $values->{'allele_id'};
	}
	if ( !$self->{'sql'}->{'tag_allele'} ) {
		$self->{'sql'}->{'tag_allele'} =
		  $self->{'db'}->prepare( 'INSERT INTO allele_designations (isolate_id,locus,allele_id,'
			  . 'sender,status,method,curator,date_entered,datestamp) VALUES (?,?,?,?,?,?,?,?,?)' );
	}
	my $status = $values->{'status'} // 'confirmed';
	eval {
		$self->{'sql'}->{'tag_allele'}->execute(
			$values->{'isolate_id'}, $values->{'locus'}, $values->{'allele_id'}, $values->{'sender'},
			$status,                 'automatic',        TAG_USER,               'now',
			'now'
		);
	};
	if ($@) {
		$self->{'logger'}->error($@) if $@;
		$self->{'db'}->rollback;
		say 'Cannot insert allele designation.';
		throw BIGSdb::DatabaseException('Cannot insert allele designation.');
	}
	$self->{'db'}->commit;
	push @{ $self->{'history'} }, "$values->{'locus'}: new designation '$values->{'allele_id'}' (sequence bin scan)";
	return;
}

sub _tag_sequence {
	my ( $self, $values ) = @_;
	my $existing = $self->{'datastore'}->get_allele_sequence( $values->{'isolate_id'}, $values->{'locus'} );
	my $locus_info = $self->{'datastore'}->get_locus_info( $values->{'locus'} );
	if ( defined $existing ) {
		foreach (@$existing) {
			return
			     if $_->{'seqbin_id'} == $values->{'seqbin_id'}
			  && $_->{'start_pos'} == $values->{'start_pos'}
			  && $_->{'end_pos'} == $values->{'end_pos'};
		}
	}
	if ( !$self->{'sql'}->{'tag_sequence'} ) {
		$self->{'sql'}->{'tag_sequence'} =
		  $self->{'db'}->prepare( 'INSERT INTO allele_sequences (seqbin_id,locus,start_pos,'
			  . 'end_pos,reverse,complete,curator,datestamp) VALUES (?,?,?,?,?,?,?,?)' );
	}
	if ( !$self->{'sql'}->{'tag_flag'} ) {
		$self->{'sql'}->{'tag_flag'} =
		  $self->{'db'}->prepare( 'INSERT INTO sequence_flags (id,flag,datestamp,curator) SELECT allele_sequences.id,'
			  . '?,?,? FROM allele_sequences WHERE (seqbin_id,locus,start_pos,end_pos)=(?,?,?,?)' );
	}
	eval {
		$self->{'sql'}->{'tag_sequence'}->execute(
			$values->{'seqbin_id'},
			$values->{'locus'}, $values->{'start_pos'},
			$values->{'end_pos'}, ( $values->{'reverse'} ? 'true' : 'false' ),
			'true', TAG_USER, 'now'
		);
		if ( $locus_info->{'flag_table'} ) {
			my $flags = $self->{'datastore'}->get_locus( $values->{'locus'} )->get_flags( $values->{'allele_id'} );
			foreach my $flag (@$flags) {
				$self->{'sql'}->{'tag_flag'}->execute(
					$flag, 'now', TAG_USER, $values->{'seqbin_id'},
					$values->{'locus'}, $values->{'start_pos'},
					$values->{'end_pos'}
				);
			}
		}
	};
	if ($@) {
		$self->{'logger'}->error($@) if $@;
		$self->{'db'}->rollback;
		say 'Cannot insert allele sequence.';
		throw BIGSdb::DatabaseException('Cannot insert allele sequence.');
	}
	$self->{'db'}->commit;
	push @{ $self->{'history'} }, "$values->{'locus'}: sequence tagged. Seqbin id: $values->{'seqbin_id'}; "
	  . "$values->{'start_pos'}-$values->{'end_pos'} (sequence bin scan)";
	return;
}
1;
