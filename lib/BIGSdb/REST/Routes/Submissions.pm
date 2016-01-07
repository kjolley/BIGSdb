#Written by Keith Jolley
#Copyright (c) 2015-2016, University of Oxford
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
use POSIX qw(ceil strftime);
use Dancer2 appname => 'BIGSdb::REST::Interface';
use MIME::Base64;
use BIGSdb::Utils;
use BIGSdb::Constants qw(SEQ_METHODS :submissions);
get '/db/:db/submissions'                         => sub { _get_submissions() };
post '/db/:db/submissions'                        => sub { _create_submission() };
get '/db/:db/submissions/:submission'             => sub { _get_submission() };
del '/db/:db/submissions/:submission'             => sub { _delete_submission() };
get '/db/:db/submissions/:submission/messages'    => sub { _get_messages() };
post '/db/:db/submissions/:submission/messages'   => sub { _add_message() };
get '/db/:db/submissions/:submission/files'       => sub { _get_files() };
post '/db/:db/submissions/:submission/files'      => sub { _upload_file() };
get '/db/:db/submissions/:submission/files/:file' => sub { _get_file() };
del '/db/:db/submissions/:submission/files/:file' => sub { _delete_file() };

sub _check_db_type {
	my ($type) = @_;
	my $self = setting('self');
	if ( ( $self->{'system'}->{'submissions'} // '' ) ne 'yes' ) {
		send_error( 'Submissions are not enabled on this database', 404 );
	}
	send_error( 'Submission type not selected', 400 ) if !$type;
	my $db_types = { sequences => { alleles => 1, profiles => 1 }, isolates => { isolates => 1, genomes => 1 } };
	if ( !$db_types->{ $self->{'system'}->{'dbtype'} }->{$type} ) {
		send_error( qq(Submissions of type "$type" are not supported by this database), 404 );
	}
	if ( $type eq 'profiles' && ( $self->{'system'}->{'profile_submissions'} // '' ) ne 'yes' ) {
		send_error( 'Profile submissions are not enabled on this database', 404 );
	}
	return;
}

sub _get_submissions {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $type, $status ) = @{$params}{qw(db type status)};
	send_error( 'Submissions are not enabled on this database.', 404 )
	  if !( ( $self->{'system'}->{'submissions'} // '' ) eq 'yes' );
	my $user_id = $self->get_user_id;
	my $values  = {};
	if ($type) {
		_check_db_type($type);
	}
	my $part_qry   = q(FROM submissions WHERE submitter=?);
	my $args       = [$user_id];
	my $paging_uri = "/db/$db/submissions";
	if ($type) {
		$part_qry .= ' AND type=?';
		push @$args, $type;
		$paging_uri .= "?type=$type";
	}
	if ($status) {
		if ( $status ne 'pending' && $status ne 'closed' ) {
			send_error( 'Invalid status value - use either "pending" or "closed".', 400 );
		}
		$part_qry .= ' AND status=?';
		push @$args, $status;
		$paging_uri .= $type ? '&' : '?';
		$paging_uri .= "status=$status";
	}
	my $submission_count = $self->{'datastore'}->run_query( "SELECT COUNT(*) $part_qry", $args );
	my $page   = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $pages  = ceil( $submission_count / $self->{'page_size'} );
	my $offset = ( $page - 1 ) * $self->{'page_size'};
	my $qry    = qq(SELECT id $part_qry ORDER BY id);
	$qry .= qq( LIMIT $self->{'page_size'} OFFSET $offset) if !param('return_all');
	my $submission_ids = $self->{'datastore'}->run_query( $qry, $args, { fetch => 'col_arrayref' } );
	$values->{'records'} = int($submission_count);
	my $paging = $self->get_paging( $paging_uri, $pages, $page );
	$values->{'paging'} = $paging if %$paging;
	my $submission_links = [];

	foreach my $submission_id (@$submission_ids) {
		push @$submission_links, request->uri_for("/db/$db/submissions/$submission_id");
	}
	$values->{'submissions'} = $submission_links;
	return $values;
}

sub _get_submission {
	my $self = setting('self');
	my ( $db, $submission_id ) = ( params->{'db'}, params->{'submission'} );
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
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
			  $self->{'submissionHandler'}
			  ->get_allele_submission( $submission->{'id'}, { fields => 'seq_id,sequence,status,assigned_id' } );
			if ($allele_submission) {
				foreach my $field (qw (locus technology read_length coverage assembly_method software comments seqs)) {
					$values->{$field} = $allele_submission->{$field} if $allele_submission->{$field};
				}
			}
		},
		profiles => sub {
			my $profile_submission =
			  $self->{'submissionHandler'}
			  ->get_profile_submission( $submission->{'id'}, { fields => 'profile_id,status,assigned_id' } );
			if ($profile_submission) {
				$values->{'scheme'}   = request->uri_for("/db/$db/schemes/$profile_submission->{'scheme_id'}");
				$values->{'profiles'} = $profile_submission->{'profiles'};
			}
		},
		isolates => sub {
			_add_isolate_data( $submission->{'id'}, $values );
		},
		genomes => sub {
			_add_isolate_data( $submission->{'id'}, $values );
			_add_missing_contig_files( $submission->{'id'}, $values );
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

sub _add_isolate_data {
	my ( $submission_id, $values ) = @_;
	my $self               = setting('self');
	my $isolate_submission = $self->{'submissionHandler'}->get_isolate_submission($submission_id);
	if ($isolate_submission) {
		$values->{'isolates'} = $isolate_submission->{'isolates'} if @{ $isolate_submission->{'isolates'} };
	}
	return;
}

sub _add_missing_contig_files {
	my ( $submission_id, $values ) = @_;
	my $self                 = setting('self');
	my $missing_contig_files = _get_missing_contig_filenames($submission_id);
	if (@$missing_contig_files) {
		local $" = q(, );
		$values->{'missing_files'} = \@$missing_contig_files;
		$values->{'message'}       = 'Please upload missing contig files to complete submission.';
	}
	return;
}

sub _delete_submission {
	my $self = setting('self');
	my ( $db, $submission_id ) = ( params->{'db'}, params->{'submission'} );
	my $user_id    = $self->get_user_id;
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	send_error( 'Submission does not exist.',                404 ) if !$submission;
	send_error( 'You are not the owner of this submission.', 403 ) if $user_id != $submission->{'submitter'};
	send_error( 'You cannot delete a pending submission.',   403 ) if $submission->{'status'} eq 'pending';
	$self->{'submissionHandler'}->delete_submission($submission_id);
	status(200);
	return { message => 'Submission deleted.' };
}

sub _check_if_over_limit {
	my $self                    = setting('self');
	my $limit                   = _get_quota_limit();
	my $submitter               = $self->get_user_id;
	my $pending_submitted_today = $self->{'datastore'}->run_query(
		'SELECT COUNT(*) FROM submissions WHERE (submitter,status,date_submitted)=(?,?,?)',
		[ $submitter, 'pending', 'today' ],
		{ cache => 'REST::Submissions::check_if_over_limit' }
	);
	if ( $pending_submitted_today >= $limit ) {
		send_error(
			'You have made too many separate submissions today - please try again tomorrow. '
			  . 'A quota is in place to prevent misbehaving scripts flooding the submission system.',
			403
		);
	}
	return;
}

sub _get_quota_limit {
	my $self = setting('self');
	my $limit =
	  BIGSdb::Utils::is_int( $self->{'system'}->{'daily_rest_submissions_limit'} )
	  ? $self->{'system'}->{'daily_rest_submissions_limit'}
	  : DAILY_REST_LIMIT;
	return $limit;
}

sub _create_submission {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $type, $message, $email ) = @{$params}{qw(db type message email)};
	_check_db_type($type);
	_check_if_over_limit();
	my $submitter     = $self->get_user_id;
	my $submission_id = 'BIGSdb_' . strftime( '%Y%m%d%H%M%S', localtime ) . "_$$\_" . int( rand(99999) );
	my %method        = (
		alleles  => sub { _prepare_allele_submission($submission_id) },
		profiles => sub { _prepare_profile_submission($submission_id) },
		isolates => sub { _prepare_isolate_submission($submission_id) },
		genomes  => sub { _prepare_isolate_submission( $submission_id, { genomes => 1 } ) }
	);
	my $sql = [];
	$sql = $method{$type}->() if $method{$type};
	eval {
		$self->{'db'}->do(
			'INSERT INTO submissions (id,type,submitter,date_submitted,datestamp,status,email) VALUES (?,?,?,?,?,?,?)',
			undef, $submission_id, $type, $submitter, 'now', 'now', 'pending', $email ? 'true' : 'false'
		);

		foreach my $sql (@$sql) {
			$self->{'db'}->do( $sql->{'statement'}, undef, @{ $sql->{'arguments'} } );
		}
		my $msg = "Submission via REST interface (client: $self->{'client_name'}).";
		$msg .= "\n$message" if $message;
		$self->{'db'}->do( 'INSERT INTO messages (submission_id,timestamp,user_id,message) VALUES (?,?,?,?)',
			undef, $submission_id, 'now', $submitter, $msg );
		$self->{'submissionHandler'}->append_message( $submission_id, $submitter, $msg );
	};
	if ($@) {
		$self->{'logger'}->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	my $missing_contig_files = [];
	my %write_file           = (
		alleles  => sub { $self->{'submissionHandler'}->write_submission_allele_FASTA($submission_id) },
		profiles => sub { $self->{'submissionHandler'}->write_profile_csv($submission_id) },
		isolates => sub { $self->{'submissionHandler'}->write_isolate_csv($submission_id) },
		genomes  => sub {
			$self->{'submissionHandler'}->write_isolate_csv($submission_id);
			$missing_contig_files = _get_missing_contig_filenames($submission_id);
		}
	);
	$write_file{$type}->() if $write_file{$type};
	$self->{'submissionHandler'}->notify_curators($submission_id);
	status(201);
	if ( $type eq 'genomes' ) {
		local $" = q(, );
		return {
			submission    => request->uri_for("/db/$db/submissions/$submission_id"),
			missing_files => "@$missing_contig_files",
			message       => 'Please upload missing contig files to complete submission.'
		};
	}
	return { submission => request->uri_for("/db/$db/submissions/$submission_id") };
}

sub _get_missing_contig_filenames {
	my ($submission_id) = @_;
	my $self            = setting('self');
	my $filenames       = $self->{'datastore'}->run_query(
		'SELECT value FROM isolate_submission_isolates WHERE (submission_id,field)=(?,?)',
		[ $submission_id, 'assembly_filename' ],
		{ fetch => 'col_arrayref' }
	);
	my $dir = $self->{'submissionHandler'}->get_submission_dir($submission_id) . '/supporting_files';
	my @missing_files;
	foreach my $filename (@$filenames) {
		push @missing_files, $filename if !-e "$dir/$filename";
	}
	return \@missing_files;
}

sub _prepare_allele_submission {
	my ($submission_id) = @_;
	my $self            = setting('self');
	my $params          = params;
	my ( $db, $locus, $technology, $read_length, $coverage, $assembly, $software, $sequences ) =
	  @{$params}{qw(db locus technology read_length coverage assembly software sequences)};
	my %required = map { $_ => 1 } qw(locus technology assembly software sequences);
	my @missing;
	foreach my $field ( sort keys %required ) {
		push @missing, $field if !defined $params->{$field};
	}
	local $" = q(, );
	if (@missing) {
		send_error( "Required field(s) missing: @missing", 400 );
	}
	my $set_id = $self->get_set_id;
	send_error( "Invalid value for locus: $locus", 400 )
	  if !$self->{'datastore'}->is_locus( $locus, { set_id => $set_id } );
	my @methods = SEQ_METHODS;
	my %methods = map { $_ => 1 } @methods;
	if ( !$methods{$technology} ) {
		send_error( "Invalid value for technology: $technology. Allowed values are: @methods", 400 );
	}
	my %field_requires = ( read_length => [REQUIRES_READ_LENGTH], coverage => [REQUIRES_COVERAGE] );
	my %allowed        = ( read_length => [READ_LENGTH],          coverage => [COVERAGE] );
	foreach my $field (qw (read_length coverage)) {
		my %requires = map { $_ => 1 } @{ $field_requires{$field} };
		if ( !defined $params->{$field} && $requires{$technology} ) {
			send_error( "$field must be provided for $technology sequences.", 400 );
		}
		next if !defined $params->{$field};
		my %allowed_values = map { $_ => 1 } @{ $allowed{$field} };
		if (
			!(
				$allowed_values{ $params->{$field} }
				|| ( BIGSdb::Utils::is_int( $params->{$field} ) && $params->{$field} > 0 )
			)
		  )
		{
			send_error(
				"Invalid value for $field: $params->{$field}. "
				  . "Allowed values are: @{$allowed{$field}} or any positive integer.",
				400
			);
		}
	}
	my $qry = 'INSERT INTO allele_submissions (submission_id,locus,technology,read_length,'
	  . 'coverage,assembly,software) VALUES (?,?,?,?,?,?,?)';
	my $sql = [
		{
			statement => $qry,
			arguments => [ $submission_id, $locus, $technology, $read_length, $coverage, $assembly, $software ]
		}
	];
	my ( $checked_allele_sql, $seqs ) = _check_submitted_alleles( $submission_id, $locus );
	push @$sql, @$checked_allele_sql;
	return $sql;
}

sub _check_submitted_alleles {
	my ( $submission_id, $locus ) = @_;
	my $self         = setting('self');
	my $params       = params;
	my $fasta_string = $params->{'sequences'};
	$fasta_string =~ s/^\s*//x;
	$fasta_string =~ s/\n\s*/\n/xg;
	$fasta_string = ">seq\n$fasta_string" if $fasta_string !~ /^\s*>/x;
	my $check =
	  $self->{'submissionHandler'}->check_new_alleles_fasta( $locus, \$fasta_string, { skip_info_checks => 1 } );

	if ( $check->{'err'} ) {
		local $" = q( );
		my $err = "@{ $check->{'err'} }";
		send_error( $err, 400 );
	}
	my $sql   = [];
	my $index = 1;
	foreach my $seq ( @{ $check->{'seqs'} } ) {
		push @$sql,
		  {
			statement => 'INSERT INTO allele_submission_sequences (submission_id,seq_id,index,sequence,status) '
			  . 'VALUES (?,?,?,?,?)',
			arguments => [ $submission_id, $seq->{'seq_id'}, $index, $seq->{'sequence'}, 'pending' ]
		  };
		$index++;
	}
	return ( $sql, $check->{'seqs'} );
}

sub _prepare_profile_submission {
	my ($submission_id) = @_;
	my $self            = setting('self');
	my $params          = params;
	my ( $db, $scheme_id, $profiles ) = @{$params}{qw(db scheme_id profiles)};
	my @missing;
	foreach my $field (qw (scheme_id profiles)) {
		push @missing, $field if !defined $params->{$field};
	}
	local $" = q(, );
	if (@missing) {
		send_error( "Required field(s) missing: @missing", 400 );
	}
	send_error( 'Scheme id must be an integer', 400 ) if !BIGSdb::Utils::is_int($scheme_id);
	my $scheme_exists =
	  $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM scheme_fields WHERE scheme_id=? AND primary_key)', $scheme_id );
	send_error( 'Scheme does not exist (or it does not contain a primary key field).', 400 ) if !$scheme_exists;
	my $set_id = $self->get_set_id;
	send_error( 'Scheme is not available.', 400 )
	  if $set_id && !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id );
	my $check = $self->{'submissionHandler'}->check_new_profiles( $scheme_id, $set_id, \$profiles );
	if ( $check->{'err'} ) {
		local $" = q( );
		my $err = "@{ $check->{'err'} }";
		send_error( $err, 400 );
	}
	if ( !@{ $check->{'profiles'} } ) {
		send_error( 'No profiles in upload.', 400 );
	}
	my $sql = [
		{
			statement => 'INSERT INTO profile_submissions (submission_id,scheme_id) VALUES (?,?)',
			arguments => [ $submission_id, $scheme_id ]
		}
	];
	my $loci  = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $index = 1;
	foreach my $profile ( @{ $check->{'profiles'} } ) {
		push @$sql,
		  {
			statement => 'INSERT INTO profile_submission_profiles '
			  . '(index,submission_id,profile_id,status) VALUES (?,?,?,?)',
			arguments => [ $index, $submission_id, $profile->{'id'}, 'pending' ]
		  };
		foreach my $locus (@$loci) {
			push @$sql,
			  {
				statement => 'INSERT INTO profile_submission_designations (submission_id,profile_id,locus,'
				  . 'allele_id) VALUES (?,?,?,?)',
				arguments => [ $submission_id, $profile->{'id'}, $locus, $profile->{$locus} ]
			  };
		}
		$index++;
	}
	return $sql;
}

sub _prepare_isolate_submission {
	my ( $submission_id, $options ) = @_;
	my $self   = setting('self');
	my $params = params;
	my ( $db, $isolates ) = @{$params}{qw(db isolates)};
	send_error( 'Required field(s) missing: isolates', 400 ) if !defined $isolates;
	my $set_id = $self->get_set_id;
	my $check = $self->{'submissionHandler'}->check_new_isolates( $set_id, \$isolates, $options );
	if ( $check->{'err'} ) {
		local $" = q( );
		my $err = "@{ $check->{'err'} }";
		send_error( $err, 400 );
	}
	my $sql = [];
	foreach my $field ( keys %{ $check->{'positions'} } ) {
		push @$sql,
		  {
			statement => 'INSERT INTO isolate_submission_field_order (submission_id,field,index) VALUES (?,?,?)',
			arguments => [ $submission_id, $field, $check->{'positions'}->{$field} ]
		  };
	}
	my $i = 1;
	foreach my $isolate ( @{ $check->{'isolates'} } ) {
		foreach my $field ( keys %$isolate ) {
			next if !defined $isolate->{$field} || $isolate->{$field} eq '';
			push @$sql,
			  {
				statement =>
				  'INSERT INTO isolate_submission_isolates (submission_id,index,field,value) VALUES (?,?,?,?)',
				arguments => [ $submission_id, $i, $field, $isolate->{$field} ]
			  };
		}
		$i++;
	}
	return $sql;
}

sub _get_messages {
	my $self = setting('self');
	my ( $db, $submission_id ) = ( params->{'db'}, params->{'submission'} );
	my $submission = $self->{'datastore'}->run_query( 'SELECT * FROM submissions WHERE id=?',
		$submission_id, { fetch => 'row_hashref', cache => 'REST::Submissions::get_submission' } );
	send_error( 'Submission does not exist.', 404 ) if !$submission;
	my $messages = $self->{'datastore'}->run_query(
		q(SELECT date_trunc('second',timestamp) AS timestamp,user_id,)
		  . q(message FROM messages WHERE submission_id=? ORDER BY timestamp),
		$submission_id,
		{ fetch => 'all_arrayref', slice => {}, cache => 'REST::Submissions::get_messages' }
	);
	my $values = [];
	foreach my $message (@$messages) {
		push @$values,
		  {
			user      => request->uri_for("/db/$db/users/$message->{'user_id'}"),
			message   => $message->{'message'},
			timestamp => $message->{'timestamp'}
		  };
	}
	return $values;
}

sub _add_message {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $submission_id, $message ) = @{$params}{qw(db submission message)};
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	send_error( 'Submission does not exist.', 404 ) if !$submission;
	send_error( 'No message included.',       400 ) if !$message;
	my $user_id = $self->get_user_id;
	eval {
		$self->{'db'}->do( 'INSERT INTO messages (submission_id,timestamp,user_id,message) VALUES (?,?,?,?)',
			undef, $submission_id, 'now', $user_id, $message );
	};

	if ($@) {
		$self->{'logger'}->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		$self->{'submissionHandler'}->append_message( $submission_id, $user_id, $message );
	}
	status(201);
	return { message => 'Message added.' };
}

sub _upload_file {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $submission_id, $filename, $upload ) = @{$params}{qw(db submission filename upload)};
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	send_error( 'Submission does not exist.', 404 ) if !$submission;
	send_error( 'Filename is required.',      400 ) if !$filename;
	my $dir = $self->{'submissionHandler'}->get_submission_dir($submission_id) . '/supporting_files';
	$self->{'submissionHandler'}->mkpath($dir);
	my $full_path = "$dir/$filename";

	if ( -e $full_path ) {
		send_error( "File $filename is already uploaded.", 400 );
	}
	if ( !length $upload ) {
		send_error( 'No data in upload.', 400 );
	}
	open( my $fh, '>', $full_path ) || $self->{'logger'}->error("Can't open $full_path for writing");
	print $fh decode_base64($upload);
	binmode $fh;
	close $fh;
	status(201);
	return { message => 'File uploaded.' };
}

sub _get_files {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $submission_id ) = @{$params}{qw(db submission)};
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	send_error( 'Submission does not exist.', 404 ) if !$submission;
	my $dir = $self->{'submissionHandler'}->get_submission_dir($submission_id) . '/supporting_files';
	my @files;
	opendir( my $dh, $dir ) || $self->{'logger'}->error("Directory $dir can't be read.");

	while ( defined( my $filename = readdir($dh) ) ) {
		push @files, $filename;
	}
	closedir $dh;
	my $values = [];
	foreach my $file ( sort @files ) {
		next if $file =~ /^\.\.?/x;
		push @$values, request->uri_for("/db/$db/submissions/$submission_id/files/$file");
	}
	return $values;
}

sub _get_file {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $submission_id, $filename ) = @{$params}{qw(db submission file)};
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	send_error( 'Submission does not exist.', 404 ) if !$submission;
	my $dir       = $self->{'submissionHandler'}->get_submission_dir($submission_id) . '/supporting_files';
	my $full_path = "$dir/$filename";
	if ( !-e $full_path ) {
		send_error( 'File does not exist.', 404 );
	}
	send_file( $full_path, system_path => 1 );
	return;
}

sub _delete_file {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $submission_id, $filename ) = @{$params}{qw(db submission file)};
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	send_error( 'Submission does not exist.', 404 ) if !$submission;
	my $user_id = $self->get_user_id;
	send_error( 'You are not the owner of this submission.', 403 ) if $user_id != $submission->{'submitter'};
	my $dir       = $self->{'submissionHandler'}->get_submission_dir($submission_id) . '/supporting_files';
	my $full_path = "$dir/$filename";

	if ( !-e $full_path ) {
		send_error( 'File does not exist.', 404 );
	}
	if ( $filename =~ /\//x || $filename =~ /\.\./x ) {
		send_error( 'Filename contains invalid characters.', 400 );
	}
	unlink $full_path || $self->{'logger'}->error("Cannot delete $full_path.");
	status(200);
	return { message => 'File deleted.' };
}
1;
