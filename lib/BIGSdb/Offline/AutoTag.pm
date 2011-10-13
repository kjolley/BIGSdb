#Written by Keith Jolley
#Copyright (c) 2011, University of Oxford
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
use List::Util qw(shuffle);
use List::MoreUtils qw(none);
use base qw(BIGSdb::Offline::Script BIGSdb::CurateTagScanPage);
use BIGSdb::Utils;
use constant TAG_USER     => -1;             #User id for tagger (there needs to be a record in the users table)
use constant TAG_USERNAME => 'autotagger';

sub run_script {
	my ($self) = @_;
	die "No connection to database (check logs).\n" if !defined $self->{'db'} || $self->{'system'}->{'dbtype'} ne 'isolates';
	my $tag_user_id = TAG_USER;
	$self->{'username'} = TAG_USERNAME;
	my $user_ok =
	  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM users WHERE id=? AND user_name=?", $tag_user_id, $self->{'username'} )
	  ->[0];
	die
"Database user '$self->{'username'}' not set.  Enter a user '$self->{'username'}' with id $tag_user_id in the database to represent the auto tagger.\n"
	  if !$user_ok;
	my $isolates = $self->get_isolates_with_linked_seqs( $self->{'options'}->{'m'} );
	@$isolates = shuffle(@$isolates) if $self->{'options'}->{'r'};
	die "No isolates selected.\n" if !@$isolates;
	my $loci = $self->get_loci_with_ref_db;
	die "No valid loci selected.\n" if !@$loci;
	$self->{'start_time'} = time;
	my $file_prefix  = BIGSdb::Utils::get_random();
	my $locus_prefix = BIGSdb::Utils::get_random();

	foreach my $isolate_id (@$isolates) {
		if ( $self->{'options'}->{'m'} && BIGSdb::Utils::is_int( $self->{'options'}->{'m'} ) ) {
			my $size = $self->_get_size_of_seqbin($isolate_id);
			next if $size < $self->{'options'}->{'m'};
		}
		undef $self->{'history'};
		foreach my $locus (@$loci) {
			next if defined $self->{'datastore'}->get_allele_id( $isolate_id, $locus );
			my $allele_seq = $self->{'datastore'}->get_allele_sequence( $isolate_id, $locus );
			next if ref $allele_seq eq 'ARRAY' && @$allele_seq;
			my ( $exact_matches, undef ) = $self->_blast( $locus, $isolate_id, $file_prefix, $locus_prefix );
			if ( ref $exact_matches && @$exact_matches ) {
				print "Isolate: $isolate_id; Locus: $locus; " if !$self->{'options'}->{'q'};
				foreach (@$exact_matches) {
					if ( $_->{'allele'} ) {
						print "Allele: $_->{'allele'} " if !$self->{'options'}->{'q'};
						my $sender =
						  $self->{'datastore'}->run_simple_query( "SELECT sender FROM sequence_bin WHERE id=?", $_->{'seqbin_id'} )->[0];
						$self->_tag_allele(
							{ isolate_id => $isolate_id, locus => $locus, allele_id => $_->{'allele'}, sender => $sender } );
						$self->_tag_sequence(
							{
								seqbin_id => $_->{'seqbin_id'},
								locus     => $locus,
								start_pos => $_->{'start'},
								end_pos   => $_->{'end'},
								reverse   => $_->{'reverse'}
							}
						);
					}
				}
				print "\n" if !$self->{'options'}->{'q'};
			}
			last if $self->_is_time_up;
		}
		if ( ref $self->{'history'} eq 'ARRAY' && @{ $self->{'history'} } ) {
			local $" = '<br />';
			$self->update_history( $isolate_id, "@{$self->{'history'}}" );
		}
		system "rm -f $self->{'config'}->{'secure_tmp_dir'}/*$file_prefix*";    #delete isolate seqbin FASTA
		last if $self->_is_time_up;
	}
	system "rm -f $self->{'config'}->{'secure_tmp_dir'}/*$locus_prefix*";       #delete locus working files
	if ( $self->_is_time_up && !$self->{'options'}->{'q'} ) {
		print "Time limit reached ($self->{'options'}->{'t'} minute" . ( $self->{'options'}->{'t'} == 1 ? '' : 's' ) . ")\n";
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

sub _tag_allele {
	my ( $self, $values ) = @_;
	my $existing = $self->{'datastore'}->get_allele_designation( $values->{'isolate_id'}, $values->{'locus'} );
	return if defined $existing && $existing->{'allele_id'} eq $values->{'allele_id'};
	if ( defined $existing ) {
		my $pending = $self->{'datastore'}->get_pending_allele_designations( $values->{'isolate_id'}, $values->{'locus'} );
		if ( none { $_->{'allele_id'} eq $values->{'allele_id'} } @$pending ) {
			my $sql =
			  $self->{'db'}->prepare( "INSERT INTO pending_allele_designations (isolate_id,locus,allele_id,"
				  . "sender,method,curator,date_entered,datestamp) VALUES (?,?,?,?,?,?,?,?)" );
			eval {
				$sql->execute(
					$values->{'isolate_id'},
					$values->{'locus'}, $values->{'allele_id'},
					$values->{'sender'}, 'automatic', TAG_USER, 'now', 'now'
				);
			};
			if ($@) {
				$self->{'logger'}->error($@) if $@;
				$self->{'db'}->rollback;
				die "Can't insert pending designation.\n";
			}
			$self->{'db'}->commit;
			push @{ $self->{'history'} }, "$values->{'locus'}: new pending designation '$values->{'allele_id'}' (sequence bin scan)";
		}
	} else {
		my $sql =
		  $self->{'db'}->prepare( "INSERT INTO allele_designations (isolate_id,locus,allele_id,"
			  . "sender,status,method,curator,date_entered,datestamp) VALUES (?,?,?,?,?,?,?,?,?)" );
		eval {
			$sql->execute(
				$values->{'isolate_id'}, $values->{'locus'}, $values->{'allele_id'}, $values->{'sender'},
				'confirmed',             'automatic',        TAG_USER,               'now',
				'now'
			);
		};
		if ($@) {
			$self->{'logger'}->error($@) if $@;
			$self->{'db'}->rollback;
			die "Can't insert allele designation.\n";
		}
		$self->{'db'}->commit;
		push @{ $self->{'history'} }, "$values->{'locus'}: new designation '$values->{'allele_id'}' (sequence bin scan)";
	}
	return;
}

sub _tag_sequence {
	my ( $self, $values ) = @_;
	my $existing = $self->{'datastore'}->get_allele_sequence( $values->{'isolate_id'}, $values->{'locus'} );
	if ( defined $existing ) {
		foreach (@$existing) {
			return
			  if $_->{'seqbin_id'} == $values->{'seqbin_id'}
				  && $_->{'start_pos'} == $values->{'start_pos'}
				  && $_->{'end_pos'} == $values->{'end_pos'};
		}
	}
	my $sql =
	  $self->{'db'}->prepare( "INSERT INTO allele_sequences (seqbin_id,locus,start_pos,"
		  . "end_pos,reverse,complete,curator,datestamp) VALUES (?,?,?,?,?,?,?,?)" );
	eval {
		$sql->execute(
			$values->{'seqbin_id'},
			$values->{'locus'}, $values->{'start_pos'},
			$values->{'end_pos'}, ( $values->{'reverse'} ? 'true' : 'false' ),
			'true', TAG_USER, 'now'
		);
	};
	if ($@) {
		$self->{'logger'}->error($@) if $@;
		$self->{'db'}->rollback;
		die "Can't insert allele sequence.\n";
	}
	$self->{'db'}->commit;
	push @{ $self->{'history'} },
"$values->{'locus'}: sequence tagged. Seqbin id: $values->{'seqbin_id'}; $values->{'start_pos'}-$values->{'end_pos'} (sequence bin scan)";
	return;
}

sub _get_size_of_seqbin {
	my ( $self, $isolate_id ) = @_;
	if ( !$self->{'sql'}->{'seqbin_size'} ) {
		$self->{'sql'}->{'seqbin_size'} = $self->{'db'}->prepare("SELECT SUM(LENGTH(sequence)) FROM sequence_bin WHERE isolate_id=?");
	}
	eval { $self->{'sql'}->{'seqbin_size'}->execute($isolate_id) };
	$self->{'logger'}->error($@) if $@;
	my ($size) = $self->{'sql'}->{'seqbin_size'}->fetchrow_array;
	return $size;
}
1;
