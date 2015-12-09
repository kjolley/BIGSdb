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
use List::MoreUtils qw(uniq);
use Log::Log4perl qw(get_logger);
use BIGSdb::Utils;
use constant EMAIL_FLOOD_PROTECTION_TIME => 60 * 2;    #2 minutes
my $logger = get_logger('BIGSdb.Submissions');

sub new {
	my ( $class, @atr ) = @_;
	my $self = {@atr};
	bless( $self, $class );
	$logger->info('Submission handler set up.');
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
	$options = {} if ref $options ne 'HASH';
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( !$locus_info ) {
		$logger->error("Locus $locus is not defined");
		return;
	}
	open( my $stringfh_in, '<:encoding(utf8)', $fasta_ref ) || $logger->error("Could not open string for reading: $!");
	$stringfh_in->untaint;
	my $seqin = Bio::SeqIO->new( -fh => $stringfh_in, -format => 'fasta' );
	my ( @err, @info, @seqs, %used_ids );
	my $locus_seq_table = $self->{'datastore'}->create_temp_allele_table($locus);
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
		my $existing_allele =
		  $self->{'datastore'}->run_query( "SELECT allele_id FROM $locus_seq_table WHERE sequence=?",
			uc($sequence), { cache => 'check_new_alleles_fasta' } );
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
		my $check = $self->{'datastore'}->check_sequence_similarity( $locus, \$sequence );
		if ( !$check->{'similar'} ) {
			push @info,
			  qq(Sequence "$seq_id" is dissimilar (or in reverse orientation compared) to other $locus sequences.);
		} elsif ( $check->{'subsequence_of'} ) {
			push @info, qq(Sequence is a sub-sequence of allele-$check->{'subsequence_of'}.);
		} elsif ( $check->{'supersequence_of'} ) {
			push @info, qq[Sequence is a super-sequence of allele $check->{'supersequence_of'}.];
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
	push @$fields, 'assembly_filename' if $options->{'genomes'};
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
		next if $heading eq 'references';
		next if $heading eq 'aliases';
		push @unrecognized, $heading if $not_accounted_for{$heading};
	}
	$ret->{'missing'}      = \@missing            if @missing;
	$ret->{'duplicates'}   = [ uniq @duplicates ] if @duplicates;
	$ret->{'unrecognized'} = \@unrecognized       if @unrecognized;
	return $ret;
}

sub _check_isolate_record {
	my ( $self, $set_id, $positions, $values, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $metadata_list  = $self->{'datastore'}->get_set_metadata( $set_id, { curate => 1 } );
	my $fields         = $self->{'xmlHandler'}->get_field_list($metadata_list);
	push @$fields, 'assembly_filename' if $options->{'genomes'};
	my %do_not_include = map { $_ => 1 } qw(id sender curator date_entered datestamp);
	my ( @missing, @error );
	my $isolate = {};
	foreach my $field (@$fields) {
		next if $do_not_include{$field};
		next if !defined $positions->{$field};
		my $att = $self->{'xmlHandler'}->get_field_attributes($field);
		$att->{'required'} = 'yes' if $field eq 'assembly_filename';
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
	if ( defined $positions->{'references'} && $values->[ $positions->{'references'} ] ) {
		my @pmids = split /;/x, $values->[ $positions->{'references'} ];
		foreach my $pmid (@pmids) {
			if ( !BIGSdb::Utils::is_int($pmid) ) {
				push @error, 'references: should be a semi-colon separated list of PubMed ids (integers).';
				last;
			}
		}
	}
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
	$value = '' if !defined $value;
	$value =~ s/<blank>//x;
	$value =~ s/null//;
	my $thisfield = $self->{'xmlHandler'}->get_field_attributes($fieldname);
	$thisfield->{'type'} ||= 'text';

	#Field can't be compulsory if part of a metadata collection. If field is null make sure it's not a required field.
	$thisfield->{'required'} = 'no' if !$set_id && $fieldname =~ /^meta_/x;
	if ( $value eq '' ) {
		if ( $fieldname eq 'aliases' || $fieldname eq 'references' || ( ( $thisfield->{'required'} // '' ) eq 'no' ) ) {
			return 0;
		} else {
			return 'is a required field and cannot be left blank.';
		}
	}

	#Make sure int fields really are integers and obey min/max values if set
	if ( $thisfield->{'type'} eq 'int' ) {
		if ( !BIGSdb::Utils::is_int($value) ) { return 'must be an integer' }
		elsif ( defined $thisfield->{'min'} && $value < $thisfield->{'min'} ) {
			return "must be equal to or larger than $thisfield->{'min'}.";
		} elsif ( defined $thisfield->{'max'} && $value > $thisfield->{'max'} ) {
			return "must be equal to or smaller than $thisfield->{'max'}.";
		}
	}

	#Make sure sender is in database
	if ( $fieldname eq 'sender' or $fieldname eq 'sequenced_by' ) {
		my $sender_exists = $self->_user_exists($value);
		return qq(is not in the database users table - see <a href="$self->{'system'}->{'script_name'}?)
		  . qq(db=$self->{'instance'}&amp;page=fieldValues&amp;field=f_sender">list of values</a>)
		  if !$sender_exists;
	}

	#If a regex pattern exists, make sure data conforms to it
	if ( $thisfield->{'regex'} ) {
		if ( $value !~ /^$thisfield->{'regex'}$/x ) {
			if ( !( $thisfield->{'required'} && $thisfield->{'required'} eq 'no' && $value eq '' ) ) {
				return 'does not conform to the required formatting.';
			}
		}
	}

	#Make sure floats fields really are floats
	if ( $thisfield->{'type'} eq 'float' && !BIGSdb::Utils::is_float($value) ) {
		return 'must be a floating point number';
	}

	#Make sure the datestamp is today
	my $datestamp = BIGSdb::Utils::get_datestamp();
	if ( $fieldname eq 'datestamp' && ( $value ne $datestamp ) ) {
		return qq[must be today's date in yyyy-mm-dd format ($datestamp) or use 'today'];
	}
	if ( $flag && $flag eq 'insert' ) {

		#Make sure the date_entered is today
		if ( $fieldname eq 'date_entered'
			&& ( $value ne $datestamp ) )
		{
			return qq[must be today's date in yyyy-mm-dd format ($datestamp) or use 'today'];
		}
	}

	#make sure date fields really are dates in correct format
	if ( $thisfield->{'type'} eq 'date' && !BIGSdb::Utils::is_date($value) ) {
		return 'must be a valid date in yyyy-mm-dd format';
	}

	#make sure boolean fields are true/false
	if ( $thisfield->{'type'} eq 'bool' && !BIGSdb::Utils::is_bool($value) ) {
		return 'must be a valid boolean value - true, false, 1, or 0.';
	}

	#Make sure id number has not been used previously
	if ( $flag && $flag eq 'insert' && ( $fieldname eq 'id' ) ) {
		my $exists =
		  $self->{'datastore'}->run_query( "SELECT EXISTS(SELECT * FROM $self->{'system'}->{'view'} WHERE id=?)",
			$value, { cache => 'CuratePage::is_field_bad_isolates::id_exists' } );
		if ($exists) {
			return "$value is already in database";
		}
	}

	#Make sure options list fields only use a listed option (or null if optional)
	if ( $thisfield->{'optlist'} ) {
		my $options = $self->{'xmlHandler'}->get_field_option_list($fieldname);
		foreach (@$options) {
			if ( $value eq $_ ) {
				return 0;
			}
		}
		if ( $thisfield->{'required'} && $thisfield->{'required'} eq 'no' ) {
			return 0 if ( $value eq '' );
		}
		return qq("$value" is not on the list of allowed values for this field.);
	}

	#Make sure field is not too long
	if ( $thisfield->{'length'} && length($value) > $thisfield->{'length'} ) {
		return "field is too long (maximum length $thisfield->{'length'})";
	}
	return 0;
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

	#If field is null make sure it's not a required field
	if ( !defined $value || $value eq '' ) {
		if ( !$thisfield->{'required'} || $thisfield->{'required'} ne 'yes' ) {
			return 0;
		} else {
			my $msg = 'is a required field and cannot be left blank.';
			if ( $thisfield->{'optlist'} ) {
				my @optlist = split /;/x, $thisfield->{'optlist'};
				local $" = q(', ');
				$msg .= " Allowed values are '@optlist'.";
			}
			return $msg;
		}
	}

	#Make sure int fields really are integers
	if ( $thisfield->{'type'} eq 'int' && !BIGSdb::Utils::is_int($value) ) {
		return 'must be an integer';
	}

	#Make sure sender is in database
	if ( $fieldname eq 'sender' or $fieldname eq 'sequenced_by' ) {
		my $qry = 'SELECT DISTINCT id FROM users';
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute };
		$logger->error($@) if $@;
		while ( my ($senderid) = $sql->fetchrow_array ) {
			if ( $value == $senderid ) {
				return 0;
			}
		}
		return qq(is not in the database users table - see <a href="$self->{'system'}->{'script_name'}?)
		  . qq(db=$self->{'instance'}&amp;page=fieldValues&amp;field=f_sender">list of values</a>);
	}

	#If a regex pattern exists, make sure data conforms to it
	if ( $thisfield->{'regex'} ) {
		if ( $value !~ /^$thisfield->{regex}$/x ) {
			if ( !( $thisfield->{'required'} && $thisfield->{'required'} eq 'no' && $value eq '' ) ) {
				return 'does not conform to the required formatting';
			}
		}
	}

	#Make sure floats fields really are floats
	if ( $thisfield->{'type'} eq 'float' && !BIGSdb::Utils::is_float($value) ) {
		return 'must be a floating point number';
	}

	#Make sure the datestamp is today
	my $datestamp = BIGSdb::Utils::get_datestamp();
	if ( $fieldname eq 'datestamp' && ( $value ne $datestamp ) ) {
		return qq[must be today's date in yyyy-mm-dd format ($datestamp) or use 'today'];
	}
	if ( $flag eq 'insert' ) {

		#Make sure the date_entered is today
		if ( $fieldname eq 'date_entered'
			&& ( $value ne $datestamp ) )
		{
			return qq[must be today's date in yyyy-mm-dd format ($datestamp) or use 'today'];
		}
	}
	if ( $flag eq 'insert'
		&& ( $thisfield->{'unique'} ) )
	{
		#Make sure unique field values have not been used previously
		my $qry = "SELECT DISTINCT $thisfield->{'name'} FROM $table";
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute };
		$logger->error($@) if $@;
		while ( my ($id) = $sql->fetchrow_array ) {
			if ( $value eq $id ) {
				if ( $thisfield->{'name'} =~ /sequence/ ) {
					$value = q(<span class="seq">) . ( BIGSdb::Utils::truncate_seq( \$value, 40 ) ) . q(</span>);
				}
				return qq('$value' is already in database);
			}
		}
	}

	#Make sure options list fields only use a listed option (or null if optional)
	if ( $thisfield->{'optlist'} ) {
		my @options = split /;/x, $thisfield->{'optlist'};
		foreach (@options) {
			if ( $value eq $_ ) {
				return 0;
			}
		}
		if ( $thisfield->{'required'} && $thisfield->{'required'} eq 'no' ) {
			return 0 if ( $value eq '' );
		}
		return qq('$value' is not on the list of allowed values for this field.);
	}

	#Make sure field is not too long
	if ( $thisfield->{length} && length($value) > $thisfield->{'length'} ) {
		return "field is too long (maximum length $thisfield->{'length'})";
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
				return "value '$value' does not exist in isolates table or is not accessible to your account";
			}
			return "value '$value' does not exist in $thisfield->{'foreign_key'} table";
		}
	}
	return 0;
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
	return if !$self->{'config'}->{'smtp_server'};
	eval 'use Mail::Sender';    ## no critic (ProhibitStringyEval)
	if ($@) {
		$logger->error('Mail::Sender is not installed.');
		return;
	}
	my $submission = $self->get_submission($submission_id);
	my $subject = $params->{'subject'} // "Submission#$submission_id";
	foreach (qw(sender recipient message)) {
		$logger->logdie("No $_") if !$params->{$_};
	}
	my $sender    = $self->{'datastore'}->get_user_info( $params->{'sender'} );
	my $recipient = $self->{'datastore'}->get_user_info( $params->{'recipient'} );
	foreach my $user ( $sender, $recipient ) {
		if ( $user->{'email'} !~ /@/x ) {
			$logger->error("Invalid E-mail address for user $user->{'id'} - $user->{'email'}");
			return;
		}
	}
	my $args = { smtp => $self->{'config'}->{'smtp_server'}, to => $recipient->{'email'}, from => $sender->{'email'} };
	$args->{'cc'} = $sender->{'email'}
	  if $params->{'cc_sender'} && $sender->{'email'} ne $recipient->{'email'};
	my $mail_sender = Mail::Sender->new($args);
	$mail_sender->MailMsg(
		{ subject => $subject, ctype => 'text/plain', charset => 'utf-8', msg => $params->{'message'} } );
	no warnings 'once';
	$logger->error($Mail::Sender::Error) if $sender->{'error'};
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
	my $submitter_string = $self->{'datastore'}->get_user_string( $submission->{'submitter'}, { affiliation => 1 } );
	$msg .= "Submitter: $submitter_string\n";
	if ( $submission->{'curator'} ) {
		my $curator_string = $self->{'datastore'}->get_user_string( $submission->{'curator'}, { affiliation => 1 } );
		$msg .= "Curator: $curator_string\n";
	}
	$msg .= "Outcome: $outcome\n" if $outcome;
	my %methods = ( alleles => '_get_allele_submission_summary', profiles => '_get_profile_submission_summary' );
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
			if ($file =~ /^(.*BIGSdb.*)$/x){
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
	$return_buffer .= "Scheme: $scheme_info->{'description'}\n";
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
1;
