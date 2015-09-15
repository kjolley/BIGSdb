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
package BIGSdb::REST::Routes::Submissions;
use strict;
use warnings;
use 5.010;
use Dancer2 appname => 'BIGSdb::REST::Interface';
use BIGSdb::Utils;
get '/db/:db/submissions'             => sub { _get_submissions() };
get '/db/:db/submissions/pending'     => sub { _get_submissions_by_status('pending') };
get '/db/:db/submissions/closed'      => sub { _get_submissions_by_status('closed') };
get '/db/:db/submissions/started'     => sub { _get_submissions_by_status('started') };
get '/db/:db/submissions/:submission' => sub { _get_submission() };

sub _get_submissions {
	my $self      = setting('self');
	my $db        = params->{'db'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	send_error( 'Unrecognized user.', 401 ) if !$user_info;
	my @submission_status = qw(closed started pending);
	my $values            = {};
	foreach my $status (@submission_status) {
		$values->{$status} = request->uri_for("/db/$db/submissions/$status");
	}
	return $values;
}

sub _get_submissions_by_status {
	my ($status)  = @_;
	my $self      = setting('self');
	my $db        = params->{'db'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	send_error( 'Unrecognized user.', 401 ) if !$user_info;
	my $submission_ids = $self->{'datastore'}->run_query(
		'SELECT id FROM submissions WHERE (status,submitter)=(?,?) ORDER BY id',
		[ $status, $user_info->{'id'} ],
		{ fetch => 'col_arrayref' }
	);
	my $values = { records => int(@$submission_ids) };
	my @submissions;
	push @submissions, request->uri_for("/db/$db/submissions/$_") foreach @$submission_ids;
	$values->{'submissions'} = \@submissions;
	return $values;
}

sub _get_submission {
	my $self = setting('self');
	my ( $db, $submission_id ) = ( params->{'db'}, params->{'submission'} );
	my $submission = $self->{'datastore'}->run_query( 'SELECT * FROM submissions WHERE id=?',
		$submission_id, { fetch => 'row_hashref', cache => 'REST::Submissions::get_submission' } );
	send_error( 'Submission does not exist.', 404 ) if !$submission;
	my $values = {};
	foreach my $field (qw (id type date_submitted datestamp status outcome)) {
		$values->{$field} = $submission->{$field} if defined $submission->{$field};
	}
	foreach my $field (qw (submitter curator)) {
		$values->{$field} = request->uri_for("/db/$db/users/$submission->{$field}")
		  if defined $submission->{$field};
	}
	my %type = (
		alleles => sub {
			my $allele_submission =
			  $self->{'datastore'}
			  ->get_allele_submission( $submission->{'id'}, { fields => 'seq_id,sequence,status,assigned_id' } );
			if ($allele_submission) {
				foreach my $field (qw (locus technology read_length coverage assembly_method software comments seqs)) {
					$values->{$field} = $allele_submission->{$field} if $allele_submission->{$field};
				}
			}
		},
		profiles => sub {
			my $profile_submission =
			  $self->{'datastore'}
			  ->get_profile_submission( $submission->{'id'}, { fields => 'profile_id,status,assigned_id' } );
			if ($profile_submission) {
				$values->{'scheme'}   = request->uri_for("/db/$db/schemes/$profile_submission->{'scheme_id'}");
				$values->{'profiles'} = $profile_submission->{'profiles'};
			}
		},
		isolates => sub {
			my $isolate_submission = $self->{'datastore'}->get_isolate_submission( $submission->{'id'} );
			if ($isolate_submission) {
				$values->{'isolates'} = $isolate_submission->{'isolates'} if @{ $isolate_submission->{'isolates'} };
			}
		}
	);
	$type{ $submission->{'type'} }->() if $type{ $submission->{'type'} };
	my $messages = $self->{'datastore'}->run_query( 'SELECT * FROM messages WHERE submission_id=? ORDER BY timestamp',
		$submission_id,
		{ fetch => 'all_arrayref', slice => {}, cache => 'REST::Submissions::get_submission::messages' } );
	my $correspondence = [];
	if (@$messages) {
		foreach my $message (@$messages) {
			$message->{'user'} = request->uri_for("/db/$db/users/$message->{'user_id'}");
			delete $message->{$_} foreach qw(user_id submission_id);
			push @$correspondence, $message;
		}
		$values->{'correspondence'} = $correspondence;
	}
	return $values;
}
1;
