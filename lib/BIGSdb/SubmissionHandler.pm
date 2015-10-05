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
1;
