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
use POSIX qw(ceil);
use Dancer2 appname => 'BIGSdb::REST::Interface';
use BIGSdb::Utils;
get '/db/:db/submissions'                  => sub { _get_submissions() };
get '/db/:db/submissions/alleles'          => sub { };
get '/db/:db/submissions/alleles/:locus'   => sub { };
get '/db/:db/submissions/profiles'         => sub { _get_submissions_profiles() };
get '/db/:db/submissions/profiles/:scheme' => sub { _get_submission_profiles_scheme_id() };
get '/db/:db/submissions/pending'          => sub { _get_submissions_by_status('pending') };
get '/db/:db/submissions/closed'           => sub { _get_submissions_by_status('closed') };
get '/db/:db/submissions/started'          => sub { _get_submissions_by_status('started') };
get '/db/:db/submissions/:submission'      => sub { _get_submission() };
del '/db/:db/submissions/:submission'      => sub { _delete_submission() };

sub _get_submissions {
	my $self = setting('self');
	my $db   = params->{'db'};
	send_error( 'Submissions are not enabled on this database.', 404 )
	  if !( ( $self->{'system'}->{'submissions'} // '' ) eq 'yes' );
	my $user_id = $self->get_user_id;
	my $type    = {};
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		$type->{'alleles'} = request->uri_for("/db/$db/submissions/alleles");
		if ( ( $self->{'system'}->{'profile_submissions'} // '' ) eq 'yes' ) {
			my $profile_links = [];
			my $set_id        = $self->get_set_id;
			my $schemes       = $self->{'datastore'}->get_scheme_list( { with_pk => 1, set_id => $set_id } );
			$type->{'profiles'} = request->uri_for("/db/$db/submissions/profiles") if @$schemes;
		}
	} else {
		$type->{'isolates'} = request->uri_for("/db/$db/submissions/isolates");
	}
	my $values = { type => $type };
	$values->{'status'} = {
		pending => request->uri_for("/db/$db/submissions/pending"),
		started => request->uri_for("/db/$db/submissions/started"),
		closed  => request->uri_for("/db/$db/submissions/closed"),
	};
	my $submission_count =
	  $self->{'datastore'}->run_query( 'SELECT COUNT(*) FROM submissions WHERE submitter=?', $user_id );
	my $page   = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $pages  = ceil( $submission_count / $self->{'page_size'} );
	my $offset = ( $page - 1 ) * $self->{'page_size'};
	my $qry    = q(SELECT id FROM submissions WHERE submitter=? ORDER BY id);
	$qry .= qq( LIMIT $self->{'page_size'} OFFSET $offset) if !param('return_all');
	my $submission_ids = $self->{'datastore'}->run_query( $qry, $user_id, { fetch => 'col_arrayref' } );
	$values->{'records'} = int($submission_count);
	my $paging = $self->get_paging( "/db/$db/submissions", $pages, $page );
	$values->{'paging'} = $paging if %$paging;
	my $submission_links = [];

	foreach my $submission_id (@$submission_ids) {
		push @$submission_links, request->uri_for("/db/$db/submissions/$submission_id");
	}
	$values->{'submissions'} = $submission_links;
	return $values;
}

sub _get_submissions_by_status {
	my ($status)       = @_;
	my $self           = setting('self');
	my $db             = params->{'db'};
	my $user_id        = $self->get_user_id;
	my $submission_ids = $self->{'datastore'}->run_query(
		'SELECT id FROM submissions WHERE (status,submitter)=(?,?) ORDER BY id',
		[ $status, $user_id ],
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

sub _get_submissions_profiles {
	my ($status) = @_;
	my $self     = setting('self');
	my $db       = params->{'db'};
	$self->check_seqdef_database;
	my $scheme_links = [];
	my $set_id       = $self->get_set_id;
	my $schemes      = $self->{'datastore'}->get_scheme_list( { with_pk => 1, set_id => $set_id } );
	foreach my $scheme (@$schemes) {
		push @$scheme_links, request->uri_for("/db/$db/submissions/profiles/$scheme->{'id'}");
	}
	return { schemes => $scheme_links };
}

sub _get_submission_profiles_scheme_id {
	my $self = setting('self');
	my ( $db, $scheme_id ) = ( params->{'db'}, params->{'scheme'} );
	$self->check_seqdef_database;
	$self->check_scheme( $scheme_id, { pk => 1 } );
	my $user_id = $self->get_user_id;
	my $qry     = 'SELECT COUNT(*) FROM submissions RIGHT JOIN profile_submissions ON '
	  . 'submissions.id=profile_submissions.submission_id WHERE (submitter,type,scheme_id)=(?,?,?)';
	my $submission_count = $self->{'datastore'}->run_query( $qry, [ $user_id, 'profiles', $scheme_id ] );
	my $page   = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $pages  = ceil( $submission_count / $self->{'page_size'} );
	my $offset = ( $page - 1 ) * $self->{'page_size'};
	$qry = 'SELECT id FROM submissions RIGHT JOIN profile_submissions ON '
	  . 'submissions.id=profile_submissions.submission_id WHERE (submitter,type,scheme_id)=(?,?,?) ORDER BY id';
	$qry .= qq( LIMIT $self->{'page_size'} OFFSET $offset) if !param('return_all');
	my $submission_ids =
	  $self->{'datastore'}->run_query( $qry, [ $user_id, 'profiles', $scheme_id ], { fetch => 'col_arrayref' } );
	my $values = {};
	$values->{'records'} = int($submission_count);
	my $paging = $self->get_paging( "/db/$db/submissions/profiles/$scheme_id", $pages, $page );
	$values->{'paging'} = $paging if %$paging;
	my $submission_links = [];

	foreach my $submission_id (@$submission_ids) {
		push @$submission_links, request->uri_for("/db/$db/submissions/$submission_id");
	}
	$values->{'submissions'} = $submission_links;
	return $values;
}

sub _delete_submission {
	my $self = setting('self');
	my ( $db, $submission_id ) = ( params->{'db'}, params->{'submission'} );
	my $user_id    = $self->get_user_id;
	my $submission = $self->{'datastore'}->get_submission($submission_id);
	send_error( 'Submission does not exist.',                404 ) if !$submission;
	send_error( 'You are not the owner of this submission.', 403 ) if $user_id != $submission->{'submitter'};
	send_error( 'You cannot delete a pending submission.',   403 ) if $submission->{'status'} eq 'pending';
	$self->{'datastore'}->delete_submission($submission_id);
	status(200);
	return;
}
1;
