#Written by Keith Jolley
#Copyright (c) 2015-2019, University of Oxford
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
package BIGSdb::SubmissionHandler;
use strict;
use warnings;
use 5.010;
use Bio::SeqIO;
use File::Path qw(make_path remove_tree);
use List::Util qw(max);
use List::MoreUtils qw(any uniq);
use Log::Log4perl qw(get_logger);
use Email::Sender::Transport::SMTP;
use Email::Sender::Simple qw(try_to_sendmail);
use Email::MIME;
use Email::Valid;
use BIGSdb::Utils;
use BIGSdb::Constants qw(:submissions SEQ_METHODS DEFAULT_DOMAIN);
use constant EMAIL_FLOOD_PROTECTION_TIME => 60 * 2;    #2 minutes
my $logger = get_logger('BIGSdb.Submissions');

sub new {
	my ( $class, @atr ) = @_;
	my $self = {@atr};
	bless( $self, $class );
	$logger->debug('Submission handler set up.');
	$self->_delete_expired_flood_protection_files;
	return $self;
}

sub get_submission_dir {
	my ( $self, $submission_id ) = @_;
	return "$self->{'config'}->{'submission_dir'}/$submission_id";
}

sub delete_submission {
	my ( $self, $submission_id ) = @_;
	eval { $self->{'db'}->do( 'DELETE FROM submissions WHERE id=?', undef, $submission_id ) };
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		$self->_delete_submission_files($submission_id);
	}
	return;
}

sub _delete_submission_files {
	my ( $self, $submission_id ) = @_;
	my $dir = $self->get_submission_dir($submission_id);
	if ( $dir =~ /^($self->{'config'}->{'submission_dir'}\/BIGSdb[^\/]+$)/x ) {
		remove_tree( $1, { error => \my $err } );
		if (@$err) {
			for my $diag (@$err) {
				my ( $file, $message ) = %$diag;
				if ( $file eq '' ) {
					$logger->error("general error: $message");
				} else {
					$logger->error("problem unlinking $file: $message");
				}
			}
		}
	}
	return;
}

sub set_allele_status {
	my ( $self, $submission_id, $seq_id, $status, $assigned_id ) = @_;
	eval {
		$self->{'db'}
		  ->do( 'UPDATE allele_submission_sequences SET (status,assigned_id)=(?,?) WHERE (submission_id,seq_id)=(?,?)',
			undef, $status, $assigned_id, $submission_id, $seq_id );
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		$self->update_submission_datestamp($submission_id);
	}
	return;
}

sub clear_assigned_seq_id {
	my ( $self, $submission_id, $seq_id ) = @_;
	eval {
		$self->{'db'}->do( 'UPDATE allele_submission_sequences SET assigned_id=NULL WHERE (submission_id,seq_id)=(?,?)',
			undef, $submission_id, $seq_id );
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		$self->update_submission_datestamp($submission_id);
	}
	return;
}

sub clear_assigned_profile_id {
	my ( $self, $submission_id, $profile_id ) = @_;
	eval {
		$self->{'db'}
		  ->do( 'UPDATE profile_submission_profiles SET assigned_id=NULL WHERE (submission_id,profile_id)=(?,?)',
			undef, $submission_id, $profile_id );
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		$self->update_submission_datestamp($submission_id);
	}
	return;
}

sub set_profile_status {
	my ( $self, $submission_id, $profile_id, $status, $assigned_id ) = @_;
	eval {
		$self->{'db'}->do(
			'UPDATE profile_submission_profiles SET (status,assigned_id)=(?,?) WHERE (submission_id,profile_id)=(?,?)',
			undef, $status, $assigned_id, $submission_id, $profile_id
		);
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		$self->update_submission_datestamp($submission_id);
	}
	return;
}

sub update_submission_outcome {
	my ( $self, $submission_id, $outcome ) = @_;
	eval { $self->{'db'}->do( 'UPDATE submissions SET outcome=? WHERE id=?', undef, $outcome, $submission_id ) };
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub update_submission_datestamp {
	my ( $self, $submission_id ) = @_;
	eval { $self->{'db'}->do( 'UPDATE submissions SET datestamp=? WHERE id=?', undef, 'now', $submission_id ) };
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub get_submission {
	my ( $self, $submission_id ) = @_;
	$logger->logcarp('No submission_id passed') if !$submission_id;
	return $self->{'datastore'}->run_query( 'SELECT * FROM submissions WHERE id=?',
		$submission_id, { fetch => 'row_hashref', cache => 'SubmissionHandler::get_submission' } );
}

sub get_allele_submission {
	my ( $self, $submission_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	$logger->logcarp('No submission_id passed') if !$submission_id;
	my $submission = $self->{'datastore'}->run_query( 'SELECT * FROM allele_submissions WHERE submission_id=?',
		$submission_id, { fetch => 'row_hashref', cache => 'SubmissionHandler::get_allele_submission' } );
	return if !$submission;
	my $fields = $options->{'fields'} // '*';
	my $seq_data =
	  $self->{'datastore'}
	  ->run_query( "SELECT $fields FROM allele_submission_sequences WHERE submission_id=? ORDER BY index",
		$submission_id,
		{ fetch => 'all_arrayref', slice => {}, cache => 'SubmissionHandler::get_allele_submission::sequences' } );
	$submission->{'seqs'} = $seq_data;
	return $submission;
}

sub get_profile_submission {
	my ( $self, $submission_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	$logger->logcarp('No submission_id passed') if !$submission_id;
	my $submission = $self->{'datastore'}->run_query( 'SELECT * FROM profile_submissions WHERE submission_id=?',
		$submission_id, { fetch => 'row_hashref', cache => 'SubmissionHandler::get_profile_submission' } );
	return if !$submission;
	if ( $options->{'count_only'} ) {
		my $count =
		  $self->{'datastore'}->run_query( 'SELECT COUNT(*) FROM profile_submission_profiles WHERE submission_id=?',
			$submission_id, { cache => 'SubmissionHandler::get_profile_submission::profile_count' } );
		$submission->{'count'} = $count;
		return $submission;
	}
	my $fields = $options->{'fields'} // '*';
	my $profiles =
	  $self->{'datastore'}
	  ->run_query( "SELECT $fields FROM profile_submission_profiles WHERE submission_id=? ORDER BY index",
		$submission_id,
		{ fetch => 'all_arrayref', slice => {}, cache => 'SubmissionHandler::get_profile_submission::profiles' } );
	$submission->{'profiles'} = [];
	foreach my $profile (@$profiles) {
		my $designations = $self->{'datastore'}->run_query(
			'SELECT locus,allele_id FROM '
			  . 'profile_submission_designations WHERE (submission_id,profile_id)=(?,?) ORDER BY locus',
			[ $submission_id, $profile->{'profile_id'} ],
			{
				fetch => 'all_arrayref',
				slice => {},
				cache => 'SubmissionHandler::get_profile_submission::designations'
			}
		);
		$profile->{'designations'}->{ $_->{'locus'} } = $_->{'allele_id'} foreach @$designations;
		push @{ $submission->{'profiles'} }, $profile;
	}
	return $submission;
}

sub get_isolate_submission {
	my ( $self, $submission_id ) = @_;
	$logger->logcarp('No submission_id passed') if !$submission_id;
	my $positions =
	  $self->{'datastore'}->run_query( 'SELECT field,index FROM isolate_submission_field_order WHERE submission_id=?',
		$submission_id, { fetch => 'all_arrayref', cache => 'SubmissionHandler::get_isolate_submission::positions' } );
	return if !$positions;
	my $order = {};
	$order->{ $_->[0] } = $_->[1] foreach @$positions;
	my $indexes =
	  $self->{'datastore'}
	  ->run_query( 'SELECT DISTINCT(index) FROM isolate_submission_isolates WHERE submission_id=? ORDER BY index',
		$submission_id, { fetch => 'col_arrayref', cache => 'SubmissionHandler::get_isolate_submission:index' } );
	my @isolates;

	foreach my $index (@$indexes) {
		my $values = $self->{'datastore'}->run_query(
			'SELECT field,value FROM isolate_submission_isolates WHERE (submission_id,index)=(?,?)',
			[ $submission_id, $index ],
			{ fetch => 'all_arrayref', cache => 'SubmissionHandler::get_isolate_submission::isolates' }
		);
		my $isolate_values = {};
		$isolate_values->{ $_->[0] } = $_->[1] foreach @$values;
		push @isolates, $isolate_values;
	}
	my $submission = { order => $order, isolates => \@isolates };
	return $submission;
}

sub write_submission_allele_FASTA {
	my ( $self, $submission_id ) = @_;
	my $allele_submission = $self->get_allele_submission($submission_id);
	my $seqs              = $allele_submission->{'seqs'};
	return if !@$seqs;
	my $dir = $self->get_submission_dir($submission_id);
	$dir = $dir =~ /^($self->{'config'}->{'submission_dir'}\/BIGSdb[^\/]+$)/x ? $1 : undef;    #Untaint
	$self->mkpath($dir);
	my $filename = 'sequences.fas';
	open( my $fh, '>', "$dir/$filename" ) || $logger->error("Can't open $dir/$filename for writing");

	foreach my $seq (@$seqs) {
		say $fh ">$seq->{'seq_id'}";
		say $fh $seq->{'sequence'};
	}
	close $fh;
	return $filename;
}

sub write_profile_csv {
	my ( $self, $submission_id ) = @_;
	my $profile_submission = $self->get_profile_submission($submission_id);
	my $profiles           = $profile_submission->{'profiles'};
	return if !@$profiles;
	my $dir = $self->get_submission_dir($submission_id);
	$dir = $dir =~ /^($self->{'config'}->{'submission_dir'}\/BIGSdb[^\/]+$)/x ? $1 : undef;    #Untaint
	$self->mkpath($dir);
	my $filename  = 'profiles.txt';
	my $scheme_id = $self->{'datastore'}->get_scheme_info( $profile_submission->{'scheme_id'} );
	my $loci      = $self->{'datastore'}->get_scheme_loci( $profile_submission->{'scheme_id'} );
	open( my $fh, '>', "$dir/$filename" ) || $logger->error("Can't open $dir/$filename for writing");
	local $" = qq(\t);
	say $fh qq(id\t@$loci);

	foreach my $profile (@$profiles) {
		print $fh $profile->{'profile_id'};
		foreach my $locus (@$loci) {
			$profile->{'designations'}->{$locus} //= q();
			print $fh qq(\t$profile->{'designations'}->{$locus});
		}
		print $fh qq(\n);
	}
	close $fh;
	return $filename;
}

sub write_isolate_csv {
	my ( $self, $submission_id ) = @_;
	my $isolate_submission = $self->get_isolate_submission($submission_id);
	my $isolates           = $isolate_submission->{'isolates'};
	return if !@$isolates;
	my $fields = $self->get_populated_fields( $isolates, $isolate_submission->{'order'} );
	my $dir = $self->get_submission_dir($submission_id);
	$dir = $dir =~ /^($self->{'config'}->{'submission_dir'}\/BIGSdb[^\/]+$)/x ? $1 : undef;    #Untaint
	$self->mkpath($dir);
	my $filename = 'isolates.txt';
	local $" = qq(\t);
	open( my $fh, '>:encoding(utf8)', "$dir/$filename" ) || $logger->error("Can't open $dir/$filename for writing");
	say $fh "@$fields";

	foreach my $isolate (@$isolates) {
		my @values;
		foreach my $field (@$fields) {
			push @values, $isolate->{$field} // '';
		}
		say $fh "@values";
	}
	close $fh;
	return $filename;
}

#Adds a file to the submission directory to ease tracking of which database submission is for.
#Useful if we ever need to manually delete these directories.
sub write_db_file {
	my ( $self, $submission_id ) = @_;
	my $dir = $self->get_submission_dir($submission_id);
	$dir = $dir =~ /^($self->{'config'}->{'submission_dir'}\/BIGSdb[^\/]+$)/x ? $1 : undef;    #Untaint
	$self->mkpath($dir);
	my $filename = 'dbase_config.txt';
	open( my $fh, '>:encoding(utf8)', "$dir/$filename" ) || $logger->error("Cannot open $dir/$filename for writing");
	say $fh $self->{'instance'};
	close $fh;
	return;
}

sub get_populated_fields {
	my ( $self, $isolates, $positions ) = @_;
	my @fields;
	foreach my $field ( sort { $positions->{$a} <=> $positions->{$b} } keys %$positions ) {
		my $populated = 0;
		foreach my $isolate (@$isolates) {
			if ( defined $isolate->{$field} && $isolate->{$field} ne q() ) {
				$populated = 1;
				last;
			}
		}
		push @fields, $field if $populated;
	}
	return \@fields;
}

sub append_message {
	my ( $self, $submission_id, $user_id, $message ) = @_;
	my $dir = $self->get_submission_dir($submission_id);
	$dir = $dir =~ /^($self->{'config'}->{'submission_dir'}\/BIGSdb[^\/]+$)/x ? $1 : undef;    #Untaint
	$self->mkpath($dir);
	my $filename  = 'messages.txt';
	my $full_path = "$dir/$filename";
	open( my $fh, '>>:encoding(utf8)', $full_path )
	  || $logger->error("Can't open $full_path for appending");
	my $user_string = $self->{'datastore'}->get_user_string($user_id);
	say $fh $user_string;
	my $timestamp = localtime(time);
	say $fh $timestamp;
	say $fh $message;
	say $fh '';
	close $fh;
	chmod 0664, $full_path;
	return;
}

sub mkpath {
	my ( $self, $dir ) = @_;
	my $save_u = umask();
	umask(0);
	##no critic (ProhibitLeadingZeros)
	make_path( $dir, { mode => 0775, error => \my $err } );
	if (@$err) {
		for my $diag (@$err) {
			my ( $path, $message ) = %$diag;
			if ( $path eq '' ) {
				$logger->error("general error: $message");
			} else {
				$logger->error("problem with $path: $message");
			}
		}
	}
	umask($save_u);
	return;
}

#Validate new allele submissions
sub check_new_alleles_fasta {
	my ( $self, $locus, $fasta_ref, $options ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( !$locus_info ) {
		$logger->error("Locus $locus is not defined");
		return;
	}
	open( my $stringfh_in, '<:encoding(utf8)', $fasta_ref ) || $logger->error("Could not open string for reading: $!");
	$stringfh_in->untaint;
	my $seqin = Bio::SeqIO->new( -fh => $stringfh_in, -format => 'fasta' );
	my ( @err, @info, @seqs, %used_ids );
	while ( my $seq_object = $seqin->next_seq ) {
		push @seqs, { seq_id => $seq_object->id, sequence => $seq_object->seq };
		my $seq_id = $seq_object->id;
		if ( $used_ids{$seq_id} ) {
			push @err, qq(Sequence identifier "$seq_id" is used more than once in submission.);
		}
		$used_ids{$seq_id} = 1;
		my $sequence = $seq_object->seq;
		if ( !defined $sequence ) {
			push @err, qq(Sequence identifier "$seq_id" does not have a valid sequence.);
			next;
		}
		$sequence =~ s/[\-\.\s]//gx;
		if ( $locus_info->{'data_type'} eq 'DNA' ) {
			my $diploid = ( $self->{'system'}->{'diploid'} // '' ) eq 'yes' ? 1 : 0;
			if ( !BIGSdb::Utils::is_valid_DNA( $sequence, { diploid => $diploid } ) ) {
				push @err, qq(Sequence "$seq_id" is not a valid unambiguous DNA sequence.);
			}
		} else {
			if ( !BIGSdb::Utils::is_valid_peptide($sequence) ) {
				push @err, qq(Sequence "$seq_id" is not a valid unambiguous peptide sequence.);
			}
		}
		my $seq_length = length $sequence;
		my $units = $locus_info->{'data_type'} eq 'DNA' ? 'bp' : 'residues';
		if ( !$options->{'ignore_length'} ) {
			if ( !$locus_info->{'length_varies'} && $seq_length != $locus_info->{'length'} ) {
				push @err,
				  qq(Sequence "$seq_id" has a length of $seq_length $units while this locus has a )
				  . qq(non-variable length of $locus_info->{'length'} $units.);
			} elsif ( $locus_info->{'min_length'} && $seq_length < $locus_info->{'min_length'} ) {
				push @err, qq(Sequence "$seq_id" has a length of $seq_length $units while this locus )
				  . qq(has a minimum length of $locus_info->{'min_length'} $units.);
			} elsif ( $locus_info->{'max_length'} && $seq_length > $locus_info->{'max_length'} ) {
				push @err, qq(Sequence "$seq_id" has a length of $seq_length $units while this locus )
				  . qq(has a maximum length of $locus_info->{'max_length'} $units.);
			}
		}
		my $existing_allele = $self->{'datastore'}->run_query(
			'SELECT allele_id FROM sequences WHERE (locus,md5(sequence))=(?,md5(?))',
			[ $locus, uc($sequence) ],
			{ cache => 'check_new_alleles_fasta' }
		);
		if ($existing_allele) {
			push @err, qq(Sequence "$seq_id" has already been defined as $locus-$existing_allele.);
		}
		next if $options->{'skip_info_checks'};
		if ( $locus_info->{'complete_cds'} && $locus_info->{'data_type'} eq 'DNA' ) {
			my $check = BIGSdb::Utils::is_complete_cds( \$sequence );
			if ( !$check->{'cds'} ) {
				push @info, qq(Sequence "$seq_id" is $check->{'err'});
			}
		}
		my $check = $self->_check_sequence_similarity( $locus, \$sequence );
		if ( !$check->{'similar'} ) {
			push @info,
			  qq(Sequence "$seq_id" is dissimilar (or in reverse orientation compared) to other $locus sequences.);
		} elsif ( $check->{'subsequence_of'} ) {
			push @info, qq(Sequence is a sub-sequence of allele-$check->{'subsequence_of'}.);
		} elsif ( $check->{'supersequence_of'} ) {
			push @info, qq(Sequence is a super-sequence of allele $check->{'supersequence_of'}.);
		}
	}
	close $stringfh_in;
	my $ret = {};
	$ret->{'err'}  = \@err  if @err;
	$ret->{'info'} = \@info if @info;
	$ret->{'seqs'} = \@seqs if @seqs;
	return $ret;
}

sub _check_sequence_similarity {

 #returns hashref with the following keys
 #similar          - true if sequence is at least IDENTITY_THRESHOLD% identical over an alignment length of 90% or more.
 #subsequence_of   - allele id of sequence that this is larger than query sequence but otherwise identical.
 #supersequence_of - allele id of sequence that is smaller than query sequence but otherwise identical.
	my ( $self, $locus, $seq_ref ) = @_;
	my $blast_obj = BIGSdb::Offline::Blast->new(
		{
			config_dir       => $self->{'config_dir'},
			lib_dir          => $self->{'lib_dir'},
			dbase_config_dir => $self->{'dbase_config_dir'},
			host             => $self->{'system'}->{'host'},
			port             => $self->{'system'}->{'port'},
			user             => $self->{'system'}->{'user'},
			password         => $self->{'system'}->{'password'},
			options          => {
				l             => ($locus),
				keep_partials => 1,
				find_similar  => 1,
				always_run    => 1
			},
			instance => $self->{'instance'},
			logger   => $logger
		}
	);
	$blast_obj->blast($seq_ref);
	return $blast_obj->check_sequence_similarity;
}

sub check_new_profiles {
	my ( $self, $scheme_id, $set_id, $profiles_csv_ref ) = @_;
	my @err;
	my @profiles;
	my @rows = split /\n/x, $$profiles_csv_ref;
	my $header_row = shift @rows;
	$header_row //= q();
	my $header_status = $self->_get_profile_header_positions( $header_row, $scheme_id, $set_id );
	my $positions     = $header_status->{'positions'};
	my %field_by_pos  = reverse %$positions;
	my %err_message =
	  ( missing => 'The header is missing a column for', duplicates => 'The header has a duplicate column for' );
	my $max_col_index = max keys %field_by_pos;

	foreach my $status (qw(missing duplicates)) {
		if ( $header_status->{$status} ) {
			my $list = $header_status->{$status};
			my $plural = @$list == 1 ? 'us' : 'i';
			local $" = q(, );
			push @err, "$err_message{$status} loc$plural: @$list.";
		}
	}
	if ( !@err ) {
		my $loci        = $self->{'datastore'}->get_scheme_loci($scheme_id);
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		my $row_number  = 1;
		my %id_exists;
		foreach my $row (@rows) {
			$row =~ s/\s*$//x;
			next if !$row;
			my @values = split /\t/x, $row;
			my $row_id =
			  defined $positions->{'id'} ? ( $values[ $positions->{'id'} ] || "Row $row_number" ) : "Row $row_number";
			$id_exists{$row_id}++;
			push @err, "$row_id: Identifier exists more than once in submission." if $id_exists{$row_id} == 2;
			my $locus_count  = @$loci;
			my $value_count  = @values;
			my $plural       = $value_count == 1 ? '' : 's';
			my $designations = {};

			for my $i ( 0 .. $max_col_index ) {
				$values[$i] //= '';
				$values[$i] =~ s/^\s*//x;
				$values[$i] =~ s/\s*$//x;
				next if !$field_by_pos{$i} || $field_by_pos{$i} eq 'id';
				if ( $values[$i] eq q(N) && !$scheme_info->{'allow_missing_loci'} ) {
					push @err, "$row_id: Arbitrary values (N) are not allowed for locus $field_by_pos{$i}.";
				} elsif ( $values[$i] eq q() ) {
					push @err, "$row_id: No value for locus $field_by_pos{$i}.";
				} else {
					my $allele_exists = $self->{'datastore'}->sequence_exists( $field_by_pos{$i}, $values[$i] );
					push @err, "$row_id: $field_by_pos{$i}:$values[$i] has not been defined." if !$allele_exists;
					$designations->{ $field_by_pos{$i} } = $values[$i];
				}
			}
			my $profile_status = $self->{'datastore'}->check_new_profile( $scheme_id, $designations );
			push @err, "$row_id: $profile_status->{'msg'}" if $profile_status->{'exists'};
			push @profiles, { id => $row_id, %$designations };
			$row_number++;
		}
	}
	my $ret = { profiles => \@profiles };
	$ret->{'err'} = \@err if @err;
	return $ret;
}

sub _get_profile_header_positions {
	my ( $self, $header_row, $scheme_id, $set_id ) = @_;
	$header_row =~ s/\s*$//x;
	my ( @missing, @duplicates, %positions );
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my @header = split /\t/x, $header_row;
	foreach my $locus (@$loci) {
		for my $i ( 0 .. @header - 1 ) {
			$header[$i] =~ s/\s//gx;
			$header[$i] = $self->{'datastore'}->get_set_locus_real_id( $header[$i], $set_id ) if $set_id;
			if ( $locus eq $header[$i] ) {
				push @duplicates, $locus if defined $positions{$locus};
				$positions{$locus} = $i;
			}
		}
	}
	for my $i ( 0 .. @header - 1 ) {
		$positions{'id'} = $i if $header[$i] eq 'id';
	}
	foreach my $locus (@$loci) {
		push @missing, $locus if !defined $positions{$locus};
	}
	my $ret = { positions => \%positions };
	$ret->{'missing'}    = \@missing    if @missing;
	$ret->{'duplicates'} = \@duplicates if @duplicates;
	return $ret;
}

sub check_new_isolates {
	my ( $self, $set_id, $data_ref, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my @isolates;
	my @err;
	my @rows          = split /\n/x, $$data_ref;
	my $header_row    = shift @rows;
	my $header_status = $self->_get_isolate_header_positions( $header_row, $set_id, $options );
	my $positions     = $header_status->{'positions'};
	my %err_message   = (
		unrecognized => 'The header contains an unrecognized column for',
		missing      => 'The header is missing a column for',
		duplicates   => 'The header has duplicate columns for'
	);

	foreach my $status (qw(unrecognized missing duplicates)) {
		if ( $header_status->{$status} ) {
			my $list = $header_status->{$status};
			local $" = q(, );
			push @err, "$err_message{$status}: @$list.";
		}
	}
	my $row_number = 0;
	if ( !@err ) {
		foreach my $row (@rows) {
			$row =~ s/\s*$//x;
			next if !$row;
			$row_number++;
			my @values = split /\t/x, $row;
			my $row_id =
			  defined $positions->{ $self->{'system'}->{'labelfield'} }
			  ? ( $values[ $positions->{ $self->{'system'}->{'labelfield'} } ] || "Row $row_number" )
			  : "Row $row_number";
			my $status = $self->_check_isolate_record( $set_id, $positions, \@values, $options );
			local $" = q(, );
			if ( $status->{'missing'} ) {
				my @missing = @{ $status->{'missing'} };
				push @err, "$row_id is missing required fields: @missing";
			}
			if ( $status->{'error'} ) {
				my @error = @{ $status->{'error'} };
				local $" = '; ';
				( my $msg = "$row_id has problems - @error" ) =~ s/\.;/;/gx;
				push @err, $msg;
			}
			push @isolates, $status->{'isolate'};
		}
	}
	my $ret = { isolates => \@isolates, positions => $positions };
	$ret->{'err'} = \@err if @err;
	$self->cleanup_validation_rules;
	return $ret;
}

sub _get_isolate_header_positions {
	my ( $self, $header_row, $set_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	$header_row =~ s/\s*$//x;
	my ( @unrecognized, @missing, @duplicates, %positions );
	my @header = split /\t/x, $header_row;
	my %not_accounted_for = map { $_ => 1 } @header;
	for my $i ( 0 .. @header - 1 ) {
		push @duplicates, $header[$i] if defined $positions{ $header[$i] };
		$positions{ $header[$i] } = $i;
	}
	my $ret = { positions => \%positions };
	my $fields = $self->{'xmlHandler'}->get_field_list;
	if ( $options->{'genomes'} ) {
		push @$fields, REQUIRED_GENOME_FIELDS;
	}
	if ($set_id) {
		my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
		my $meta_fields = $self->{'xmlHandler'}->get_field_list( $metadata_list, { meta_fields_only => 1 } );
		push @$fields, @$meta_fields;
	}
	my %do_not_include = map { $_ => 1 } qw(id sender curator date_entered datestamp);
	foreach my $field (@$fields) {
		next if $do_not_include{$field};
		my $att = $self->{'xmlHandler'}->get_field_attributes($field);
		push @missing, $field if !( ( $att->{'required'} // '' ) eq 'no' ) && !defined $positions{$field};
		delete $not_accounted_for{$field};
	}
	foreach my $heading (@header) {
		next if $self->{'datastore'}->is_locus($heading);
		next if $self->{'datastore'}->is_eav_field($heading);
		next if $heading eq 'references';
		next if $heading eq 'aliases';
		push @unrecognized, $heading if $not_accounted_for{$heading};
	}
	$ret->{'missing'}      = \@missing            if @missing;
	$ret->{'duplicates'}   = [ uniq @duplicates ] if @duplicates;
	$ret->{'unrecognized'} = \@unrecognized       if @unrecognized;
	return $ret;
}

sub _strip_trailing_spaces {
	my ( $self, $values ) = @_;
	s/^\s+|\s+$//gx foreach @$values;
	return;
}

sub _check_pubmed_ids {
	my ( $self, $positions, $values, $error ) = @_;
	if ( defined $positions->{'references'} && $values->[ $positions->{'references'} ] ) {
		my @pmids = split /;/x, $values->[ $positions->{'references'} ];
		foreach my $pmid (@pmids) {
			if ( !BIGSdb::Utils::is_int($pmid) ) {
				push @$error, 'references: should be a semi-colon separated list of PubMed ids (integers).';
				last;
			}
		}
	}
	return;
}

sub _check_aliases {
	my ( $self, $positions, $values, $error ) = @_;
	if ( defined $positions->{'aliases'} && $values->[ $positions->{'aliases'} ] ) {
		my @aliases = split /;/x, $values->[ $positions->{'aliases'} ];
		foreach my $alias (@aliases) {
			if ( $alias eq $values->[ $positions->{ $self->{'system'}->{'labelfield'} } ] ) {
				push @$error, 'aliases: should be ALTERNATIVE names for the isolate.';
				last;
			}
		}
	}
	return;
}

sub _check_isolate_record {
	my ( $self, $set_id, $positions, $values, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $metadata_list = $self->{'datastore'}->get_set_metadata( $set_id, { curate => 1 } );
	my $fields = $self->{'xmlHandler'}->get_field_list($metadata_list);
	push @$fields, @{ $self->{'datastore'}->get_eav_fieldnames };
	push @$fields, REQUIRED_GENOME_FIELDS if $options->{'genomes'};
	my %do_not_include = map { $_ => 1 } qw(id sender curator date_entered datestamp);
	my ( @missing, @error );
	my $isolate = {};
	$self->_strip_trailing_spaces($values);

	foreach my $field (@$fields) {
		next if $do_not_include{$field};
		next if !defined $positions->{$field};
		my $att = $self->{'xmlHandler'}->get_field_attributes($field);
		$att->{'required'} = 'yes' if ( any { $field eq $_ } REQUIRED_GENOME_FIELDS ) && $options->{'genomes'};
		$att->{'required'} = 'no' if $self->{'datastore'}->is_eav_field($field);
		if (  !( ( $att->{'required'} // '' ) eq 'no' )
			&& ( !defined $values->[ $positions->{$field} ] || $values->[ $positions->{$field} ] eq '' ) )
		{
			push @missing, $field;
		} else {
			my $value = $values->[ $positions->{$field} ] // '';
			my $status = $self->is_field_bad( 'isolates', $field, $value, undef, $set_id );
			push @error, "$field: $status" if $status;
		}
	}
	foreach my $heading ( sort { $positions->{$a} <=> $positions->{$b} } keys %$positions ) {
		my $value = $values->[ $positions->{$heading} ];
		next if !defined $value || $value eq q();
		$isolate->{$heading} = $value;
		next if !$self->{'datastore'}->is_locus($heading);
		my $locus_info = $self->{'datastore'}->get_locus_info($heading);
		if ( $locus_info->{'allele_id_format'} eq 'integer' && !BIGSdb::Utils::is_int($value) ) {
			push @error, "locus $heading: must be an integer";
		} elsif ( $locus_info->{'allele_id_regex'} && $value !~ /$locus_info->{'allele_id_regex'}/x ) {
			push @error, "locus $heading: doesn't match the required format";
		}
	}
	my %newdata = map { $_ => $values->[ $positions->{$_} ] } keys %$positions;
	my $validation_failures = $self->run_validation_checks( \%newdata );
	if (@$validation_failures) {
		foreach my $failure (@$validation_failures) {
			push @error, $failure;
		}
	}
	
	$self->_check_pubmed_ids( $positions, $values, \@error );
	$self->_check_aliases( $positions, $values, \@error );
	my $ret = { isolate => $isolate };
	$ret->{'missing'} = \@missing if @missing;
	$ret->{'error'}   = \@error   if @error;
	return $ret;
}

sub is_field_bad {
	my ( $self, $table, $fieldname, $value, $flag, $set_id ) = @_;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		return $self->_is_field_bad_isolates( $fieldname, $value, $flag, $set_id );
	} else {
		return $self->_is_field_bad_other( $table, $fieldname, $value, $flag, $set_id );
	}
}

sub _is_field_bad_isolates {
	my ( $self, $fieldname, $value, $flag, $set_id ) = @_;
	$value //= q();
	$flag  //= q();
	if ( $flag eq 'update' ) {
		$value =~ s/<blank>//x;
		$value =~ s/null//;
	}
	if ( !$self->{'cache'}->{'field_attributes'}->{$fieldname} ) {
		if ( $self->{'datastore'}->is_eav_field($fieldname) ) {
			my $data = $self->{'datastore'}->get_eav_field($fieldname);
			$self->{'cache'}->{'field_attributes'}->{$fieldname} = {
				type     => $data->{'value_format'},
				regex    => $data->{'value_regex'},
				min      => $data->{'min_value'},
				max      => $data->{'max_value'},
				length   => $data->{'length'},
				optlist  => $data->{'option_list'} ? 'yes' : 'no',
				comments => $data->{'description'},
				required => 'no'
			};
			if ( $data->{'option_list'} ) {
				$self->{'cache'}->{'field_attributes'}->{$fieldname}->{'option_list_values'} =
				  [ split /;/x, $data->{'option_list'} ];
			}
		} else {
			$self->{'cache'}->{'field_attributes'}->{$fieldname} =
			  $self->{'xmlHandler'}->get_field_attributes($fieldname);
		}
	}
	my $thisfield = $self->{'cache'}->{'field_attributes'}->{$fieldname};
	$thisfield->{'type'} ||= 'text';

	#Field can't be compulsory if part of a metadata collection. If field is null make sure it's not a required field.
	$thisfield->{'required'} = 'no' if !$set_id && $fieldname =~ /^meta_/x;
	$thisfield->{'required'} = 'no' if $self->{'datastore'}->is_eav_field($fieldname);
	my %optional_fields = map { $_ => 1 } qw(aliases references assembly_filename sequence_method);
	if ( $value eq '' ) {
		if ( $optional_fields{$fieldname} || ( ( $thisfield->{'required'} // '' ) eq 'no' ) ) {
			return;
		} else {
			return 'is a required field and cannot be left blank.';
		}
	}
	my @insert_checks = qw(date_entered id_exists);
	foreach my $insert_check (@insert_checks) {
		next if !( ( $flag // q() ) eq 'insert' );
		my $method = "_check_isolate_$insert_check";
		my $message = $self->$method( $fieldname, $value );
		return $message if $message;
	}
	my @checks = qw(sender regex datestamp integer date float boolean optlist length);
	foreach my $check (@checks) {
		my $method = "_check_isolate_$check";
		my $message = $self->$method( $fieldname, $value );
		return $message if $message;
	}
	return;
}

sub run_validation_checks {
	my ( $self, $values ) = @_;
	if ( !$self->{'validation_checks_prepared'} ) {
		$self->_prepare_validation_checks;
	}
	my $failures = [];
	foreach my $rule ( @{ $self->{'validation_rules'} } ) {
		if ( $rule->{'sub'}->($values) ) {
			push @$failures, $rule->{'failure_message'};
		}
	}
	return $failures;
}

sub _prepare_validation_checks {
	my ($self) = @_;
	$self->{'validation_rules'} //= [];
	my $rules = $self->{'datastore'}
	  ->run_query( 'SELECT * FROM validation_rules', undef, { fetch => 'all_arrayref', slice => {} } );
	foreach my $rule (@$rules) {
		my $conditions = $self->{'datastore'}->run_query(
			'SELECT vc.field,vc.operator,vc.value FROM validation_rule_conditions rc JOIN '
			  . 'validation_conditions vc ON rc.condition_id=vc.id WHERE rule_id=? ORDER BY condition_id',
			$rule->{'id'},
			{ fetch => 'all_arrayref', slice => {} }
		);
		my $rule = {
			id              => $rule->{'id'},
			conditions      => $conditions,
			failure_message => $rule->{'message'}
		};
		my $sub = $self->_setup_validation_rule($rule);
		$rule->{'sub'} = $sub;
		push @{ $self->{'validation_rules'} }, $rule;
	}
	$self->{'validation_checks_prepared'} = 1;
	return;
}

sub _setup_validation_rule {
	my ( $self, $rule ) = @_;
	my @condition_subs;
	foreach my $con ( @{ $rule->{'conditions'} } ) {
		if ( lc( $con->{'value'} eq 'null' ) ) {
			push @condition_subs, $self->_null_condition_sub($con);
			next;
		}
		my $type;
		if ( $self->{'xmlHandler'}->is_field( $con->{'field'} ) ) {
			my $att = $self->{'xmlHandler'}->get_field_attributes( $con->{'field'} );
			$type = lc( $att->{'type'} ) // 'text';
		} elsif ( $self->{'datastore'}->is_eav_field( $con->{'field'} ) ) {
			my $att = $self->{'datastore'}->get_eav_field( $con->{'field'} );
			$type = $att->{'value_format'};
		} else {
			$logger->error("Field $con->{'field'} is not recognized.");
			return;
		}
		my $method = {
			'='           => $self->_eq_condition_sub( $type, $con ),
			'contains'    => $self->_contains_condition_sub($con),
			'starts with' => $self->_starts_with_condition_sub($con),
			'ends with'   => $self->_ends_with_condition_sub($con),
			'>'           => $self->_gt_condition_sub( $type, $con ),
			'>='          => $self->_ge_condition_sub( $type, $con ),
			'<'           => $self->_lt_condition_sub( $type, $con ),
			'<='          => $self->_le_condition_sub( $type, $con ),
			'NOT'         => $self->_ne_condition_sub( $type, $con ),
			'NOT contain' => $self->_not_contain_condition_sub($con),
		};
		if ( $method->{ $con->{'operator'} } ) {
			push @condition_subs, $method->{ $con->{'operator'} };
		}
	}
	my $full_check = sub {
		return if !@condition_subs;
		foreach my $sub (@condition_subs) {
			if ( !$sub->( $_[0] ) ) {
				return;
			}
		}
		return 1;
	};
	return $full_check;
}

sub _null_condition_sub {
	my ( $self, $condition ) = @_;
	return sub {
		my ($values) = @_;
		my $value = $values->{ $condition->{'field'} } //= q();
		if ( $condition->{'operator'} eq '=' ) {
			return $value ne q() ? 0 : 1;
		} elsif ( $condition->{'operator'} eq 'NOT' ) {
			return $value ne q() ? 1 : 0;
		}
	};
}

sub _eq_condition_sub {
	my ( $self, $type, $condition ) = @_;
	return sub {
		my ($values) = @_;
		my $value = $values->{ $condition->{'field'} };
		return if !defined $value || $value eq q();
		my $cvalue = $self->_get_comp_value( $values, $condition );
		if ( $type eq 'text' ) {
			return lc($value) eq lc($cvalue);
		} else {
			return $value == $cvalue;
		}
	};
}

sub _contains_condition_sub {
	my ( $self, $condition ) = @_;
	return sub {
		my ($values) = @_;
		my $value = $values->{ $condition->{'field'} };
		return if !defined $value || $value eq q();
		my $cvalue = $self->_get_comp_value( $values, $condition );
		return $value =~ /$cvalue/xi;
	};
}

sub _starts_with_condition_sub {
	my ( $self, $condition ) = @_;
	return sub {
		my ($values) = @_;
		my $value = $values->{ $condition->{'field'} };
		return if !defined $value || $value eq q();
		my $cvalue = $self->_get_comp_value( $values, $condition );
		return $value =~ /^$cvalue/xi;
	};
}

sub _ends_with_condition_sub {
	my ( $self, $condition ) = @_;
	return sub {
		my ($values) = @_;
		my $value = $values->{ $condition->{'field'} };
		return if !defined $value || $value eq q();
		my $cvalue = $self->_get_comp_value( $values, $condition );
		return $value =~ /$cvalue$/xi;
	};
}

sub _gt_condition_sub {
	my ( $self, $type, $condition ) = @_;
	return sub {
		my ($values) = @_;
		my $value = $values->{ $condition->{'field'} };
		return if !defined $value || $value eq q();
		my $cvalue = $self->_get_comp_value( $values, $condition );
		if ( $type eq 'text' ) {
			return lc($value) gt lc($cvalue);
		} else {
			return $value > $cvalue;
		}
	};
}

sub _ge_condition_sub {
	my ( $self, $type, $condition ) = @_;
	return sub {
		my ($values) = @_;
		my $value = $values->{ $condition->{'field'} };
		return if !defined $value || $value eq q();
		my $cvalue = $self->_get_comp_value( $values, $condition );
		if ( $type eq 'text' ) {
			return lc($value) ge lc($cvalue);
		} else {
			return $value >= $cvalue;
		}
	};
}

sub _lt_condition_sub {
	my ( $self, $type, $condition ) = @_;
	return sub {
		my ($values) = @_;
		my $value = $values->{ $condition->{'field'} };
		return if !defined $value || $value eq q();
		my $cvalue = $self->_get_comp_value( $values, $condition );
		if ( $type eq 'text' || $type eq 'date' ) {
			return lc($value) lt lc($cvalue);
		} else {
			return $value < $cvalue;
		}
	};
}

sub _le_condition_sub {
	my ( $self, $type, $condition ) = @_;
	return sub {
		my ($values) = @_;
		my $value = $values->{ $condition->{'field'} };
		return if !defined $value || $value eq q();
		my $cvalue = $self->_get_comp_value( $values, $condition );
		if ( $type eq 'text' ) {
			return lc($value) le lc($cvalue);
		} else {
			return $value <= $cvalue;
		}
	};
}

sub _ne_condition_sub {
	my ( $self, $type, $condition ) = @_;
	return sub {
		my ($values) = @_;
		my $value = $values->{ $condition->{'field'} };
		return if !defined $value || $value eq q();
		my $cvalue = $self->_get_comp_value( $values, $condition );
		if ( $type eq 'text' ) {
			return lc($value) ne lc($cvalue);
		} else {
			return $value != $cvalue;
		}
	};
}

sub _not_contain_condition_sub {
	my ( $self, $condition ) = @_;
	return sub {
		my ($values) = @_;
		my $value = $values->{ $condition->{'field'} };
		return if !defined $value || $value eq q();
		my $cvalue = $self->_get_comp_value( $values, $condition );
		return $value !~ /$cvalue/xi;
	};
}

sub _get_comp_value {
	my ( $self, $values, $condition ) = @_;
	my $value = $condition->{'value'};
	if ( $condition->{'value'} =~ /^\[(.+)\]$/x ) {
		$value = $values->{$1};
	}
	return $value;
}

#Make sure sender is in database
sub _check_isolate_sender {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $value ) = @_;
	return if $field ne 'sender' && $field ne 'sequenced_by';
	my $sender_exists = $self->_user_exists($value);
	if ( !$sender_exists ) {
		return qq(is not in the database users table - see <a href="$self->{'system'}->{'script_name'}?)
		  . qq(db=$self->{'instance'}&amp;page=fieldValues&amp;field=f_sender">list of values</a>);
	}
	return;
}

sub _check_isolate_regex {     ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $value ) = @_;
	my $thisfield = $self->{'cache'}->{'field_attributes'}->{$field};
	$logger->error("$field attributes not cached") if !$thisfield;
	return if !$thisfield->{'regex'};
	if ( $value !~ /^$thisfield->{'regex'}$/x ) {
		if ( !( $thisfield->{'required'} eq 'no' && $value eq q() ) ) {
			return 'does not conform to the required formatting.';
		}
	}
	return;
}

sub _check_isolate_datestamp {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $value ) = @_;
	return if $field ne 'datestamp';
	my $datestamp = BIGSdb::Utils::get_datestamp();
	if ( $value ne $datestamp ) {
		return qq[must be today's date in yyyy-mm-dd format ($datestamp)];
	}
	return;
}

#Make sure the date_entered is today
sub _check_isolate_date_entered {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $value ) = @_;
	return if $field ne 'date_entered';
	my $datestamp = BIGSdb::Utils::get_datestamp();
	if ( $value ne $datestamp ) {
		return qq[must be today's date in yyyy-mm-dd format ($datestamp)];
	}
	return;
}

#Make sure id number has not been used previously
sub _check_isolate_id_exists {       ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $value ) = @_;
	return if $field ne 'id';
	return "$value is not an integer" if !BIGSdb::Utils::is_int($value);
	my $exists = $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM isolates WHERE id=?)',
		$value, { cache => 'CuratePage::is_field_bad_isolates::id_exists' } );
	if ($exists) {
		return "$value is already in database";
	}
	$exists = $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM retired_isolates WHERE isolate_id=?)',
		$value, { cache => 'CuratePage::is_field_bad_isolates::retired_id_exists' } );
	if ($exists) {
		return "$value has been retired";
	}
	return;
}

sub _check_isolate_integer {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $value ) = @_;
	my $thisfield = $self->{'cache'}->{'field_attributes'}->{$field};
	$logger->error("$field attributes not cached") if !$thisfield;
	return if $thisfield->{'type'} !~ /^int/x;
	if ( !BIGSdb::Utils::is_int($value) ) { return 'must be an integer' }
	elsif ( defined $thisfield->{'min'} && $value < $thisfield->{'min'} ) {
		return "must be equal to or larger than $thisfield->{'min'}";
	} elsif ( defined $thisfield->{'max'} && $value > $thisfield->{'max'} ) {
		return "must be equal to or smaller than $thisfield->{'max'}";
	}
	return;
}

sub _check_isolate_date {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $value ) = @_;
	my $thisfield = $self->{'cache'}->{'field_attributes'}->{$field};
	$logger->error("$field attributes not cached") if !$thisfield;
	return if $thisfield->{'type'} ne 'date';
	if ( $thisfield->{'type'} eq 'date' && !BIGSdb::Utils::is_date($value) ) {
		return 'must be a valid date in yyyy-mm-dd format';
	}
	if ( $thisfield->{'min'} && $value lt $thisfield->{'min'} ) {
		return "must be $thisfield->{'min'} or later";
	}
	if ( $thisfield->{'max'} && $value gt $thisfield->{'max'} ) {
		return "must be $thisfield->{'max'} or earlier";
	}
	return;
}

sub _check_isolate_float {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $value ) = @_;
	my $thisfield = $self->{'cache'}->{'field_attributes'}->{$field};
	$logger->error("$field attributes not cached") if !$thisfield;
	return if $thisfield->{'type'} ne 'float';
	if ( $thisfield->{'type'} eq 'float' && !BIGSdb::Utils::is_float($value) ) {
		return 'must be a floating point number';
	} elsif ( defined $thisfield->{'min'} && $value < $thisfield->{'min'} ) {
		return "must be equal to or larger than $thisfield->{'min'}";
	} elsif ( defined $thisfield->{'max'} && $value > $thisfield->{'max'} ) {
		return "must be equal to or smaller than $thisfield->{'max'}";
	}
	return;
}

sub _check_isolate_boolean {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $value ) = @_;
	my $thisfield = $self->{'cache'}->{'field_attributes'}->{$field};
	$logger->error("$field attributes not cached") if !$thisfield;
	return if $thisfield->{'type'} !~ /^bool/x;
	if ( $thisfield->{'type'} =~ /^bool/x && !BIGSdb::Utils::is_bool($value) ) {
		return 'must be a valid boolean value - true, false, 1, or 0';
	}
	return;
}

sub _check_isolate_optlist {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $value ) = @_;
	my $thisfield = $self->{'cache'}->{'field_attributes'}->{$field};
	$logger->error("$field attributes not cached") if !$thisfield;
	$thisfield->{'optlist'} = 'yes' if $field eq 'sequence_method';
	return if ( $thisfield->{'optlist'} // q() ) ne 'yes';
	my $options;
	if ( $self->{'cache'}->{'field_attributes'}->{$field}->{'option_list_values'} ) {
		$options = $self->{'cache'}->{'field_attributes'}->{$field}->{'option_list_values'};
	} else {
		$options = $self->{'xmlHandler'}->get_field_option_list($field);
		$options = [SEQ_METHODS] if $field eq 'sequence_method';
	}
	foreach my $option (@$options) {
		return if $value eq $option;
	}
	if ( ( $thisfield->{'required'} // q() ) eq 'no' ) {
		return if $value eq q();
	}
	return q(value is not on the list of allowed values for this field.);
}

sub _check_isolate_length {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $value ) = @_;
	my $thisfield = $self->{'cache'}->{'field_attributes'}->{$field};
	$logger->error("$field attributes not cached") if !$thisfield;

	#Ignore max length if we have a list of allowed values.
	return if ( $thisfield->{'optlist'} // q() ) eq 'yes';
	if ( $thisfield->{'length'} && length($value) > $thisfield->{'length'} ) {
		return "field is too long (maximum length $thisfield->{'length'})";
	}
	return;
}

sub _is_field_bad_other {
	my ( $self, $table, $fieldname, $value, $flag, $set_id ) = @_;
	my $q          = $self->{'cgi'};
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my $thisfield;
	foreach my $att (@$attributes) {
		if ( $att->{'name'} eq $fieldname ) {
			$thisfield = $att;
			last;
		}
	}
	$thisfield->{'type'} ||= 'text';
	my @checks_by_attribute = qw(required integer boolean float regex optlist length);
	foreach my $check (@checks_by_attribute) {
		my $method = "_check_other_$check";
		my $message = $self->$method( $thisfield, $value );
		return $message if $message;
	}
	my @checks_by_fieldname = qw(sender datestamp);
	foreach my $check (@checks_by_fieldname) {
		my $method = "_check_other_$check";
		my $message = $self->$method( $fieldname, $value );
		return $message if $message;
	}
	my @insert_checks = qw(date_entered);
	foreach my $insert_check (@insert_checks) {
		next if !( ( $flag // q() ) eq 'insert' );
		my $method = "_check_other_$insert_check";
		my $message = $self->$method( $fieldname, $value );
		return $message if $message;
	}

	#Make sure unique field values have not been used previously
	if ( $flag eq 'insert' && ( $thisfield->{'unique'} ) ) {
		my $exists =
		  $self->{'datastore'}->run_query( "SELECT EXISTS(SELECT * FROM $table WHERE $thisfield->{'name'}=?)", $value );
		if ($exists) {
			return qq('$value' is already in database.);
		}
	}

	#Make sure a foreign key value exists in foreign table
	if ( $thisfield->{'foreign_key'} ) {
		my $qry;
		if ( $fieldname eq 'isolate_id' ) {
			$qry = "SELECT EXISTS(SELECT * FROM $self->{'system'}->{'view'} WHERE id=?)";
		} else {
			$qry = "SELECT EXISTS(SELECT * FROM $thisfield->{'foreign_key'} WHERE id=?)";
		}
		$value = $self->map_locus_name( $value, $set_id ) if $fieldname eq 'locus';
		my $exists =
		  $self->{'datastore'}
		  ->run_query( $qry, $value, { cache => "SubmissionHandler::is_field_bad_other:$fieldname" } );
		if ( !$exists ) {
			if ( $thisfield->{'foreign_key'} eq 'isolates' && $self->{'system'}->{'view'} ne 'isolates' ) {
				return "value '$value' does not exist in isolates table or is not accessible to your account.";
			}
			return "value '$value' does not exist in $thisfield->{'foreign_key'} table.";
		}
	}
	return;
}

#If field is null make sure it's not a required field
sub _check_other_required {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $thisfield, $value ) = @_;
	return if defined $value && $value ne q();
	if ( !$thisfield->{'required'} ) {
		return;
	} else {
		my $msg = 'is a required field and cannot be left blank.';
		if ( $thisfield->{'optlist'} ) {
			my @optlist = split /;/x, $thisfield->{'optlist'};
			local $" = q(', ');
			$msg .= " Allowed values are '@optlist'.";
		}
		return $msg;
	}
	return;
}

#Make sure int fields really are integers
sub _check_other_integer {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $thisfield, $value ) = @_;
	return if !defined $value || $value eq q();
	if ( $thisfield->{'type'} eq 'int' && !BIGSdb::Utils::is_int($value) ) {
		return 'must be an integer.';
	}
	return;
}

#Make sure floats fields really are floats
sub _check_other_float {      ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $thisfield, $value ) = @_;
	return if !defined $value || $value eq q();
	if ( $thisfield->{'type'} eq 'float' && !BIGSdb::Utils::is_float($value) ) {
		return 'must be a floating point number';
	}
	return;
}

#Make sure boolean fields really are boolean
sub _check_other_boolean {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $thisfield, $value ) = @_;
	return if !defined $value || $value eq q();
	if ( $thisfield->{'type'} eq 'bool' && !BIGSdb::Utils::is_bool($value) ) {
		return 'must be a boolean value (true/false or 1/0)';
	}
	return;
}

#Make sure sender is in database
sub _check_other_sender {     ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $value ) = @_;
	if ( $field eq 'sender' or $field eq 'sequenced_by' ) {
		my $exists = $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM users WHERE id=?)',
			$value, { cache => 'SubmissionHandler::check_other_sender' } );
		if ( !$exists ) {
			return qq(is not in the database users table - see <a href="$self->{'system'}->{'script_name'}?)
			  . qq(db=$self->{'instance'}&amp;page=fieldValues&amp;field=f_sender">list of values</a>.);
		}
	}
	return;
}

#If a regex pattern exists, make sure data conforms to it
sub _check_other_regex {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $thisfield, $value ) = @_;
	return if !$thisfield->{'regex'};
	if ( $value !~ /^$thisfield->{regex}$/x ) {
		if ( $thisfield->{'required'} && $value ne q() ) {
			return 'does not conform to the required formatting.';
		}
	}
	return;
}

#Make sure options list fields only use a listed option (or null if optional)
sub _check_other_optlist {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $thisfield, $value ) = @_;
	return if !defined $value || $value eq q();
	return if !$thisfield->{'optlist'};
	my @options = split /;/x, $thisfield->{'optlist'};
	foreach (@options) {
		if ( $value eq $_ ) {
			return;
		}
	}
	if ( !$thisfield->{'required'} ) {
		return if ( $value eq q() );
	}
	return qq('$value' is not on the list of allowed values for this field.);
}

#Make sure field is not too long
sub _check_other_length {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $thisfield, $value ) = @_;
	if ( $thisfield->{length} && length($value) > $thisfield->{'length'} ) {
		return "field is too long (maximum length $thisfield->{'length'}).";
	}
	return;
}

#Make sure the datestamp is today
sub _check_other_datestamp {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $value ) = @_;
	return if $field ne 'datestamp';
	my $datestamp = BIGSdb::Utils::get_datestamp();
	if ( $value ne $datestamp ) {
		return qq[must be today's date in yyyy-mm-dd format ($datestamp).];
	}
	return;
}

#Make sure the date_entered is today
sub _check_other_date_entered {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $value ) = @_;
	return if $field ne 'date_entered';
	my $datestamp = BIGSdb::Utils::get_datestamp();
	if ( $value ne $datestamp ) {
		return qq[must be today's date in yyyy-mm-dd format ($datestamp).];
	}
	return;
}

sub map_locus_name {
	my ( $self, $locus, $set_id ) = @_;
	return $locus if !$set_id;
	my $locus_list = $self->{'datastore'}->run_query(
		'SELECT locus FROM set_loci WHERE (set_id,set_name)=(?,?)',
		[ $set_id, $locus ],
		{ fetch => 'col_arrayref' }
	);
	return $locus if @$locus_list != 1;
	return $locus_list->[0];
}

sub _user_exists {
	my ( $self, $user_id ) = @_;
	if ( !$self->{'cache'}->{'users'} ) {
		my $users = $self->{'datastore'}->run_query( 'SELECT id FROM users', undef, { fetch => 'col_arrayref' } );
		%{ $self->{'cache'}->{'users'} } = map { $_ => 1 } @$users;
	}
	return 1 if $self->{'cache'}->{'users'}->{$user_id};
	return;
}

sub email {
	my ( $self, $submission_id, $params ) = @_;
	my $submission = $self->get_submission($submission_id);
	foreach (qw(sender recipient message)) {
		$logger->logdie("No $_") if !$params->{$_};
	}
	my $domain     = $self->{'config'}->{'domain'} // DEFAULT_DOMAIN;
	my $from_email = qq(no_reply\@$domain);
	my $sender     = $self->{'datastore'}->get_user_info( $params->{'sender'} );
	my $recipient  = $self->{'datastore'}->get_user_info( $params->{'recipient'} );
	foreach my $user ( $sender, $recipient ) {
		my $address = Email::Valid->address( $user->{'email'} );
		if ( !$address ) {
			$logger->error("Invalid E-mail address for user $user->{'id'} - $user->{'email'}");
			return;
		}
	}
	my $subject = qq([$sender->{'email'}] ) . ( $params->{'subject'} // "Submission#$submission_id" );
	my $transport = Email::Sender::Transport::SMTP->new(
		{ host => $self->{'config'}->{'smtp_server'} // 'localhost', port => $self->{'config'}->{'smtp_port'} // 25, }
	);
	my $cc =
	  ( $params->{'cc_sender'} && $sender->{'email'} ne $recipient->{'email'} )
	  ? $sender->{'email'}
	  : undef;
	my $header_params = [
		To      => $recipient->{'email'},
		From    => $from_email,
		Subject => $subject
	];
	push @$header_params, ( Cc => $cc ) if defined $cc;
	my $email = Email::MIME->create(
		attributes => {
			encoding => 'quoted-printable',
			charset  => 'UTF-8',
		},
		header_str => $header_params,
		body_str   => $params->{'message'}
	);
	eval {
		try_to_sendmail( $email, { transport => $transport } )
		  || $logger->error("Cannot send E-mail to $recipient->{'email'}");
		$logger->info("Email to $recipient->{'email'}: $subject");
	};
	$logger->error($@) if $@;
	return;
}

sub get_text_summary {
	my ( $self, $submission_id, $options ) = @_;
	my $submission = $self->get_submission($submission_id);
	my $outcome    = $self->_translate_outcome( $submission->{'outcome'} );
	my %fields     = (
		id             => 'ID',
		type           => 'Data type',
		date_submitted => 'Date submitted',
		datestamp      => 'Last updated',
		status         => 'Status',
	);
	my $msg = $self->_get_text_heading('Submission status');
	foreach my $field (qw (id type date_submitted datestamp status)) {
		$msg .= "$fields{$field}: $submission->{$field}\n";
	}
	my $submitter_string =
	  $self->{'datastore'}
	  ->get_user_string( $submission->{'submitter'}, { email => 1, text_email => 1, affiliation => 1 } );
	$msg .= "Submitter: $submitter_string\n";
	if ( $submission->{'curator'} ) {
		my $curator_string = $self->{'datastore'}
		  ->get_user_string( $submission->{'curator'}, { email => 1, text_email => 1, affiliation => 1 } );
		$msg .= "Curator: $curator_string\n";
	}
	$msg .= "Outcome: $outcome\n" if $outcome;
	my %methods = (
		alleles  => '_get_allele_submission_summary',
		profiles => '_get_profile_submission_summary',
		isolates => '_get_isolate_submission_summary',
		genomes  => '_get_isolate_submission_summary'
	);
	if ( $methods{ $submission->{'type'} } ) {
		my $method  = $methods{ $submission->{'type'} };
		my $summary = $self->$method($submission_id);
		$msg .= $summary if $summary;
	}
	if ( $options->{'messages'} ) {
		my $qry = q(SELECT date_trunc('second',timestamp) AS timestamp,user_id,message FROM messages )
		  . q(WHERE submission_id=? ORDER BY timestamp asc);
		my $messages =
		  $self->{'datastore'}->run_query( $qry, $submission_id, { fetch => 'all_arrayref', slice => {} } );
		if (@$messages) {
			$msg .= $self->_get_text_heading( 'Correspondence', { blank_line_before => 1 } );
			foreach my $message (@$messages) {
				my $user_string = $self->{'datastore'}->get_user_string( $message->{'user_id'} );
				$msg .= "$user_string ($message->{'timestamp'}):\n";
				$msg .= "$message->{'message'}\n\n";
			}
		}
	}
	return $msg;
}

sub _get_curators {
	my ( $self, $submission_id ) = @_;
	my $submission = $self->get_submission($submission_id);
	return [] if !$submission;
	my $curators =
	  $self->{'datastore'}
	  ->run_query( q[SELECT id,status FROM users WHERE status IN ('curator','admin') AND submission_emails],
		undef, { fetch => 'all_arrayref', slice => {} } );
	my @filtered_curators;
	if ( $submission->{'type'} eq 'alleles' ) {
		my $allele_submission = $self->get_allele_submission($submission_id);
		return if !$allele_submission;
		my $locus_curators = $self->{'datastore'}->run_query(
			'SELECT curator_id FROM locus_curators WHERE locus=?',
			$allele_submission->{'locus'},
			{ fetch => 'col_arrayref' }
		);
		my %is_locus_curator = map { $_ => 1 } @$locus_curators;
		foreach my $curator (@$curators) {
			push @filtered_curators, $curator->{'id'}
			  if ( $is_locus_curator{ $curator->{'id'} } || $curator->{'status'} eq 'admin' );
		}
	} elsif ( $submission->{'type'} eq 'profiles' ) {
		my $profile_submission = $self->get_profile_submission($submission_id);
		return if !$profile_submission;
		my $scheme_curators = $self->{'datastore'}->run_query(
			'SELECT curator_id FROM scheme_curators WHERE scheme_id=?',
			$profile_submission->{'scheme_id'},
			{ fetch => 'col_arrayref' }
		);
		my %is_scheme_curator = map { $_ => 1 } @$scheme_curators;
		foreach my $curator (@$curators) {
			push @filtered_curators, $curator->{'id'}
			  if ( $is_scheme_curator{ $curator->{'id'} } || $curator->{'status'} eq 'admin' );
		}
	} else {
		push @filtered_curators, $_->{'id'} foreach @$curators;
	}
	return \@filtered_curators;
}

sub notify_curators {
	my ( $self, $submission_id ) = @_;
	return if !$self->{'config'}->{'smtp_server'};
	my $submission = $self->get_submission($submission_id);
	my $curators   = $self->_get_curators($submission_id);
	foreach my $curator_id (@$curators) {
		next if !$self->_can_email_curator($curator_id);
		my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
		my $message = qq(This message has been sent to curators/admins of the $desc database with privileges )
		  . qq(required to curate this submission.\n\n);
		$message .= qq(Please log in to the curator's interface to handle this submission.\n\n);
		$message .= $self->get_text_summary( $submission_id, { messages => 1 } );
		my $subject = "New $submission->{'type'} submission ($desc) - $submission_id";
		$self->email(
			$submission_id,
			{
				recipient => $curator_id,
				sender    => $submission->{'submitter'},
				subject   => $subject,
				message   => $message
			}
		);
		$self->_write_flood_protection_file($curator_id);
	}
	return;
}

#Prevent flood of curator E-mails when multiple submissions sent in very short
#space of time, e.g. via scripted REST calls.
sub _can_email_curator {
	my ( $self, $curator_id ) = @_;
	my $filename = "$self->{'config'}->{'secure_tmp_dir'}/BIGSdb_FLOOD_DEFENCE/$self->{'instance'}_$curator_id";
	return if -e $filename;
	return 1;
}

sub _delete_expired_flood_protection_files {
	my ($self) = @_;
	my @files = glob("$self->{'config'}->{'secure_tmp_dir'}/BIGSdb_FLOOD_DEFENCE/*");
	foreach my $file (@files) {

		# -M gives age relative to process startup - reset so it is relative to current time
		local $^T = time;
		my $file_age = ( -M $file ) * 3600 * 24;    #File age in seconds
		if ( $file_age > EMAIL_FLOOD_PROTECTION_TIME ) {
			if ( $file =~ /^(.*BIGSdb.*)$/x ) {
				unlink $1 || $logger->error("Could not unlink $file");
			}
		}
	}
	return;
}

sub _write_flood_protection_file {
	my ( $self, $curator_id ) = @_;
	my $dir = "$self->{'config'}->{'secure_tmp_dir'}/BIGSdb_FLOOD_DEFENCE";
	$self->mkpath($dir);
	my $filename = "$dir/$self->{'instance'}_$curator_id";
	open( my $fh, '>', $filename ) || $logger->error("Can't write flood defence file $filename");
	close $fh;
	return;
}

sub _get_text_heading {
	my ( $self, $heading, $options ) = @_;
	my $msg;

	#The tab before newline prevents Outlook removing 'extra line breaks'.
	$msg .= "\t\n" if $options->{'blank_line_before'};
	$msg .= "$heading\t\n";
	$msg .= ( '=' x length $heading ) . "\t\n";
	return $msg;
}

sub _translate_outcome {
	my ( $self, $outcome_value ) = @_;
	return if !$outcome_value;
	my %outcome = (
		good  => 'accepted - data uploaded',
		bad   => 'rejected - data not uploaded',
		mixed => 'mixed - submission partially accepted'
	);
	return $outcome{$outcome_value} // $outcome_value;
}

sub _get_allele_submission_summary {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $submission_id ) = @_;
	my $allele_submission = $self->get_allele_submission($submission_id);
	return if !$allele_submission;
	my $return_buffer = q();
	$return_buffer .= $self->_get_text_heading( 'Data summary', { blank_line_before => 1 } );
	$return_buffer .= "Locus: $allele_submission->{'locus'}\n";
	$return_buffer .= 'Sequence count: ' . scalar @{ $allele_submission->{'seqs'} } . "\n";
	my $buffer = q();

	foreach my $seq ( @{ $allele_submission->{'seqs'} } ) {
		next if $seq->{'status'} eq 'pending';
		$buffer .= "$seq->{'seq_id'}: $seq->{'status'}";
		$buffer .= " - $allele_submission->{'locus'}-$seq->{'assigned_id'}" if $seq->{'assigned_id'};
		$buffer .= "\n";
	}
	if ($buffer) {
		$return_buffer .= $self->_get_text_heading( 'Assignments', { blank_line_before => 1 } );
		$return_buffer .= $buffer;
	}
	return $return_buffer;
}

sub _get_profile_submission_summary {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $submission_id ) = @_;
	my $profile_submission = $self->get_profile_submission($submission_id);
	return if !$profile_submission;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $profile_submission->{'scheme_id'}, { get_pk => 1 } );
	my $return_buffer = q();
	$return_buffer .= $self->_get_text_heading( 'Data summary', { blank_line_before => 1 } );
	$return_buffer .= "Scheme: $scheme_info->{'name'}\n";
	$return_buffer .= 'Profile count: ' . scalar @{ $profile_submission->{'profiles'} } . "\n";
	my $buffer = q();

	foreach my $profile ( @{ $profile_submission->{'profiles'} } ) {
		next if $profile->{'status'} eq 'pending';
		$buffer .= "$profile->{'profile_id'}: $profile->{'status'}";
		$buffer .= " - $scheme_info->{'primary_key'}-$profile->{'assigned_id'}" if $profile->{'assigned_id'};
		$buffer .= "\n";
	}
	if ($buffer) {
		$return_buffer .= $self->_get_text_heading( 'Assignments', { blank_line_before => 1 } );
		$return_buffer .= $buffer;
	}
	return $return_buffer;
}

sub _get_isolate_submission_summary {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $submission_id ) = @_;
	my $isolate_submission = $self->get_isolate_submission($submission_id);
	my $return_buffer = $self->_get_text_heading( 'Data summary', { blank_line_before => 1 } );
	$return_buffer .= 'Isolate count: ' . scalar @{ $isolate_submission->{'isolates'} } . "\n";
	return $return_buffer;
}

#Can cause error during global cleanup if not called when finished.
sub cleanup_validation_rules {
	my ($self) = @_;
	undef $self->{'validation_rules'};
	return;
}

1;
