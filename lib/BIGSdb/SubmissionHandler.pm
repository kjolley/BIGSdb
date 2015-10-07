#Written by Keith Jolley
#Copyright (c) 2015, University of Oxford
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
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Submissions');

sub new {
	my ( $class, @atr ) = @_;
	my $self = {@atr};
	bless( $self, $class );
	$logger->info('Submission handler set up.');
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
	my ( $self, $locus, $fasta_ref ) = @_;
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
		my $existing_allele = $self->{'datastore'}->run_query(
			'SELECT allele_id FROM sequences WHERE (locus,UPPER(sequence))=(?,UPPER(?))',
			[ $locus, $sequence ],
			{ cache => 'check_new_alleles_fasta' }
		);
		if ($existing_allele) {
			push @err, qq(Sequence "$seq_id" has already been defined as $locus-$existing_allele.);
		}
		if ( $locus_info->{'complete_cds'} && $locus_info->{'data_type'} eq 'DNA' ) {
			my $check = BIGSdb::Utils::is_complete_cds( \$sequence );
			if ( !$check->{'cds'} ) {
				push @info, qq(Sequence "$seq_id" is $check->{'err'});
			}
		}
		if ( !$self->{'datastore'}->is_sequence_similar_to_others( $locus, \$sequence ) ) {
			push @info,
			  qq(Sequence "$seq_id" is dissimilar (or in reverse orientation compared) to other $locus sequences.);
		}
	}
	close $stringfh_in;
	my $ret = {};
	$ret->{'err'}  = \@err  if @err;
	$ret->{'info'} = \@info if @info;
	$ret->{'seqs'} = \@seqs if @seqs;
	return $ret;
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
1;
