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
get '/db/:db/submissions' => sub { _get_submissions() };

foreach my $type (qw (alleles profiles isolates)) {
	get "/db/:db/submissions/$type"         => sub { _get_submissions( { type => $type } ) };
	get "/db/:db/submissions/$type/pending" => sub { _get_submissions( { type => $type, status => 'pending' } ) };
	get "/db/:db/submissions/$type/closed"  => sub { _get_submissions( { type => $type, status => 'closed' } ) };
}
get '/db/:db/submissions/pending'     => sub { _get_submissions_by_status('pending') };
get '/db/:db/submissions/closed'      => sub { _get_submissions_by_status('closed') };
get '/db/:db/submissions/:submission' => sub { _get_submission() };
del '/db/:db/submissions/:submission' => sub { _delete_submission() };

sub _get_submissions {
	my ($options) = @_;
	$options = {} if ref $options ne 'HASH';
	my $self = setting('self');
	my $db   = params->{'db'};
	send_error( 'Submissions are not enabled on this database.', 404 )
	  if !( ( $self->{'system'}->{'submissions'} // '' ) eq 'yes' );
	my $user_id = $self->get_user_id;
	my $values  = {};
	if ( !$options->{'type'} ) {
		my $type = {};
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
		$values->{'type'} = $type;
	} else {
		my $db_types = { sequences => { alleles => 1, profiles => 1 }, isolates => { isolates => 1 } };
		if ( !$db_types->{ $self->{'system'}->{'dbtype'} }->{ $options->{'type'} } ) {
			send_error( "Submissions of type \'$options->{'type'}\' are not supported by this database", 404 );
		}
	}
	my $type = $options->{'type'} ? "/$options->{'type'}" : '';
	if ( !$options->{'status'} ) {
		$values->{'status'} = {
			pending => request->uri_for("/db/$db/submissions${type}/pending"),
			closed  => request->uri_for("/db/$db/submissions${type}/closed"),
		};
	}
	my $status   = $options->{'status'} ? "/$options->{'status'}" : '';
	my $part_qry = q(FROM submissions WHERE submitter=?);
	my $args     = [$user_id];
	if ( $options->{'type'} ) {
		$part_qry .= ' AND type=?';
		push @$args, $options->{'type'};
	}
	if ( $options->{'status'} ) {
		$part_qry .= ' AND status=?';
		push @$args, $options->{'status'};
	}
	my $submission_count = $self->{'datastore'}->run_query( "SELECT COUNT(*) $part_qry", $args );
	my $page   = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $pages  = ceil( $submission_count / $self->{'page_size'} );
	my $offset = ( $page - 1 ) * $self->{'page_size'};
	my $qry    = qq(SELECT id $part_qry ORDER BY id);
	$qry .= qq( LIMIT $self->{'page_size'} OFFSET $offset) if !param('return_all');
	my $submission_ids = $self->{'datastore'}->run_query( $qry, $args, { fetch => 'col_arrayref' } );
	$values->{'records'} = int($submission_count);
	my $paging = $self->get_paging( "/db/$db/submissions$type$status", $pages, $page );
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
