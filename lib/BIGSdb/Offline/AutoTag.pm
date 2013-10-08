#Written by Keith Jolley
#Copyright (c) 2011-2013, University of Oxford
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
use List::Util qw(shuffle);
use List::MoreUtils qw(none uniq);
use POSIX qw(strftime);
use parent qw(BIGSdb::Offline::Scan);
use BIGSdb::Utils;
use BIGSdb::BIGSException;
use Error qw(:try);
use constant TAG_USER     => -1;             #User id for tagger (there needs to be a record in the users table)
use constant TAG_USERNAME => 'autotagger';

sub run_script {
	my ($self) = @_;
	my $EXIT = 0;
	local @SIG{qw (INT TERM HUP)} = ( sub { $EXIT = 1 } ) x 3;    #Allow temp files to be cleaned on kill signals
	my $params;
	$params->{$_} = 1 foreach qw(pcr_filter probe_filter);
	$params->{'word_size'} = 30;                                  #Only looking for exact matches.
	die "No connection to database (check logs).\n" if !defined $self->{'db'} || $self->{'system'}->{'dbtype'} ne 'isolates';
	my $tag_user_id = TAG_USER;
	$self->{'username'} = TAG_USERNAME;
	my $user_ok =
	  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM users WHERE id=? AND user_name=?", $tag_user_id, $self->{'username'} )
	  ->[0];
	die "Database user '$self->{'username'}' not set.  Enter a user '$self->{'username'}' with id $tag_user_id in the database "
	  . "to represent the auto tagger.\n"
	  if !$user_ok;
	my $isolates     = $self->get_isolates_with_linked_seqs;
	my $isolate_list = $self->_filter_and_sort_isolates($isolates);

	if ( !@$isolate_list ) {
		exit(0) if $self->{'options'}->{'n'};
		die "No isolates selected.\n";
	}
	my $loci = $self->get_loci_with_ref_db;
	die "No valid loci selected.\n" if !@$loci;
	$self->{'start_time'} = time;
	my $isolate_prefix = BIGSdb::Utils::get_random();
	my $locus_prefix   = BIGSdb::Utils::get_random();
	$self->{'logger'}->info("$self->{'options'}->{'d'}:Autotagger start");
	my $i = 0;
  ISOLATE: foreach my $isolate_id (@$isolate_list) {
		$i++;
		my $complete = BIGSdb::Utils::decimal_place( ( $i * 100 / @$isolate_list ), 1 );
		$self->{'logger'}->info( "$self->{'options'}->{'d'}:Checking isolate $isolate_id - $i/" . (@$isolate_list) . "($complete%)" );
		undef $self->{'history'};
	  LOCUS: foreach my $locus (@$loci) {
			next if defined $self->{'datastore'}->get_allele_id( $isolate_id, $locus );
			my $allele_seq = $self->{'datastore'}->get_allele_sequence( $isolate_id, $locus );
			next if ref $allele_seq eq 'ARRAY' && @$allele_seq;
			my ( $exact_matches, undef ) = $self->blast( $params, $locus, $isolate_id, $isolate_prefix, $locus_prefix );
			if ( ref $exact_matches && @$exact_matches ) {
				print "Isolate: $isolate_id; Locus: $locus; " if !$self->{'options'}->{'q'};
				foreach (@$exact_matches) {
					if ( $_->{'allele'} ) {
						print "Allele: $_->{'allele'} " if !$self->{'options'}->{'q'};
						my $sender =
						  $self->{'datastore'}->run_simple_query( "SELECT sender FROM sequence_bin WHERE id=?", $_->{'seqbin_id'} )->[0];
						my $problem = 0;
						try {
							$self->_tag_allele(
								{ isolate_id => $isolate_id, locus => $locus, allele_id => $_->{'allele'}, sender => $sender } );
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
						catch BIGSdb::DatabaseException with {
							$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$isolate_prefix*");
							$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$locus_prefix*");
							$problem = 1;
						};
						last ISOLATE if $problem;
					}
				}
				print "\n" if !$self->{'options'}->{'q'};
			}
			last if $EXIT || $self->_is_time_up;
		}
		if ( ref $self->{'history'} eq 'ARRAY' && @{ $self->{'history'} } ) {
			local $" = '<br />';
			$self->update_history( $isolate_id, "@{$self->{'history'}}" );
		}
		$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$isolate_prefix*");    #delete isolate seqbin FASTA
		last if $EXIT || $self->_is_time_up;
	}
	$self->delete_temp_files("$self->{'config'}->{'secure_tmp_dir'}/*$locus_prefix*");          #delete locus working files
	if ( $self->_is_time_up && !$self->{'options'}->{'q'} ) {
		say "Time limit reached ($self->{'options'}->{'t'} minute" . ( $self->{'options'}->{'t'} == 1 ? '' : 's' ) . ")";
	}
	$self->{'logger'}->info("$self->{'options'}->{'d'}:Autotagger stop");
	return;
}

sub _filter_and_sort_isolates {
	my ( $self, $isolates, ) = @_;
	my @exclude_isolates;
	if ( $self->{'options'}->{'I'} ) {
		@exclude_isolates = split /,/, $self->{'options'}->{'I'};
	}
	if ( $self->{'options'}->{'P'} ) {
		push @exclude_isolates, @{ $self->_get_isolates_excluded_by_project };
		@exclude_isolates = uniq(@exclude_isolates);
	}
	if ( $self->{'options'}->{'r'} ) {
		@$isolates = shuffle(@$isolates);
	} elsif ( $self->{'options'}->{'o'} ) {
		my $tag_date = $self->_get_last_tagged_date($isolates);
		@$isolates = sort { $tag_date->{$a} cmp $tag_date->{$b} } @$isolates;
	}
	my %exclude = map { $_ => 1 } @exclude_isolates;
	my @list;
	foreach my $isolate_id (@$isolates) {
		next if $exclude{$isolate_id};
		next if $self->{'options'}->{'n'} && $self->_is_previously_tagged($isolate_id);
		if ( $self->{'options'}->{'m'} && BIGSdb::Utils::is_int( $self->{'options'}->{'m'} ) ) {
			my $size = $self->_get_size_of_seqbin($isolate_id);
			next if $size < $self->{'options'}->{'m'};
		}
		if (
			( $self->{'options'}->{'x'} && BIGSdb::Utils::is_int( $self->{'options'}->{'x'} ) && $self->{'options'}->{'x'} > $isolate_id )
			|| (   $self->{'options'}->{'y'}
				&& BIGSdb::Utils::is_int( $self->{'options'}->{'y'} )
				&& $self->{'options'}->{'y'} < $isolate_id )
		  )
		{
			next;
		}
		push @list, $isolate_id;
	}
	return \@list;
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
				say "Can't insert pending designation.";
				throw BIGSdb::DatabaseException("Can't insert pending designation.");
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
			say "Can't insert allele designation.";
			throw BIGSdb::DatabaseException("Can't insert allele designation.");
		}
		$self->{'db'}->commit;
		push @{ $self->{'history'} }, "$values->{'locus'}: new designation '$values->{'allele_id'}' (sequence bin scan)";
	}
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
	my $sql =
	  $self->{'db'}->prepare( "INSERT INTO allele_sequences (seqbin_id,locus,start_pos,"
		  . "end_pos,reverse,complete,curator,datestamp) VALUES (?,?,?,?,?,?,?,?)" );
	my $sql_flag =
	  $self->{'db'}
	  ->prepare("INSERT INTO sequence_flags (seqbin_id,locus,start_pos,end_pos,flag,datestamp,curator) VALUES (?,?,?,?,?,?,?)");
	eval {
		$sql->execute(
			$values->{'seqbin_id'},
			$values->{'locus'}, $values->{'start_pos'},
			$values->{'end_pos'}, ( $values->{'reverse'} ? 'true' : 'false' ),
			'true', TAG_USER, 'now'
		);
		if ( $locus_info->{'flag_table'} ) {
			my $flags = $self->{'datastore'}->get_locus( $values->{'locus'} )->get_flags( $values->{'allele_id'} );
			foreach my $flag (@$flags) {
				$sql_flag->execute(
					$values->{'seqbin_id'},
					$values->{'locus'}, $values->{'start_pos'},
					$values->{'end_pos'}, $flag, 'now', TAG_USER
				);
			}
		}
	};
	if ($@) {
		$self->{'logger'}->error($@) if $@;
		$self->{'db'}->rollback;
		say "Can't insert allele sequence.";
		throw BIGSdb::DatabaseException("Can't insert allele sequence.");
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

sub _get_last_tagged_date {
	my ( $self, $isolates ) = @_;
	my $sql = $self->{'db'}->prepare("SELECT MAX(datestamp) FROM allele_designations WHERE isolate_id=?");
	my %tag_date;
	foreach (@$isolates) {
		eval { $sql->execute($_) };
		$self->{'logger'}->error($@) if $@;
		my ($date) = $sql->fetchrow_array || '0000-00-00';
		$tag_date{$_} = $date;
	}
	return \%tag_date;
}

sub _get_isolates_excluded_by_project {
	my ($self) = @_;
	my @projects = split /,/, $self->{'options'}->{'P'};
	my @isolates;
	foreach (@projects) {
		next if !BIGSdb::Utils::is_int($_);
		my $list_ref = $self->get_project_isolates($_);
		push @isolates, @$list_ref;
	}
	@isolates = uniq(@isolates);
	return \@isolates;
}

sub _is_previously_tagged {
	my ( $self, $isolate_id ) = @_;
	my $designations_set =
	  $self->{'datastore'}->run_simple_query( "SELECT EXISTS(SELECT isolate_id FROM allele_designations WHERE isolate_id=?)", $isolate_id )
	  ->[0];
	my $tagged = $self->{'datastore'}->run_simple_query(
		"SELECT EXISTS(SELECT isolate_id FROM allele_sequences LEFT JOIN sequence_bin "
		  . "ON allele_sequences.seqbin_id = sequence_bin.id WHERE isolate_id=?)",
		$isolate_id
	)->[0];
	return ( $tagged || $designations_set ) ? 1 : 0;
}
1;
