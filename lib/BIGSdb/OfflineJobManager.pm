#Written by Keith Jolley
#Copyright (c) 2011-2019, University of Oxford
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
package BIGSdb::OfflineJobManager;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::BaseApplication);
use BIGSdb::Exceptions;
use Try::Tiny;
use Digest::MD5;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Job');
use constant DBASE_QUOTA_EXCEEDED => 1;
use constant USER_QUOTA_EXCEEDED  => 2;
use constant RESULTS_DELETED_DAYS => 7;

sub new {

	#The job manager uses its own Dataconnector since it may be called by a stand-alone script.
	my ( $class, $options ) = @_;
	my $self = {};
	$self->{'system'}        = $options->{'system'} // {};
	$self->{'host'}          = $options->{'host'};
	$self->{'port'}          = $options->{'port'};
	$self->{'user'}          = $options->{'user'};
	$self->{'password'}      = $options->{'password'};
	$self->{'xmlHandler'}    = undef;
	$self->{'dataConnector'} = BIGSdb::Dataconnector->new;
	bless( $self, $class );
	$self->_initiate( $options->{'config_dir'} );
	$self->{'dataConnector'}->initiate( $self->{'system'}, $self->{'config'} );
	$self->_db_connect;
	return $self;
}

sub _initiate {
	my ( $self, $config_dir ) = @_;
	$self->read_config_file($config_dir);
	$self->read_host_mapping_file($config_dir);
	return;
}

sub _db_connect {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $initiate_logger = get_logger('BIGSdb.Application_Initiate');
	if ( !$self->{'config'}->{'jobs_db'} ) {
		$initiate_logger->fatal('jobs_db not set in config file.');
		return;
	}
	my %att = (
		dbase_name => $self->{'config'}->{'jobs_db'},
		host       => $self->{'host'},
		port       => $self->{'port'},
		user       => $self->{'user'},
		password   => $self->{'password'},
	);
	if ( $options->{'reconnect'} ) {
		$self->{'db'} = $self->{'dataConnector'}->drop_all_connections;
	}
	try {
		$self->{'db'} = $self->{'dataConnector'}->get_connection( \%att );
	}
	catch {
		if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
			$initiate_logger->error("Cannot connect to database '$self->{'config'}->{'jobs_db'}'");
		} else {
			$logger->logdie($_);
		}
	};
	return;
}

sub add_job {

	#Required params:
	#dbase_config: name of db configuration direction in /etc/dbases
	#ip_address: connecting address
	#module: Plugin module name
	#
	#Optional params:
	#username and email of user
	#priority: (highest 1 - lowest 9)
	#parameters: any additional parameters needed by plugin (hashref)
	my ( $self, $params ) = @_;
	foreach (qw (dbase_config ip_address module)) {
		if ( !$params->{$_} ) {
			$logger->error("Parameter $_ not passed");
			BIGSdb::Exception::Data->throw("Parameter $_ not passed");
		}
	}
	my $priority =
	  BIGSdb::Utils::is_int( $self->{'system'}->{'job_priority'} ) ? $self->{'system'}->{'job_priority'} : 5;

	#Adjust for plugin level priority.
	$priority += $params->{'priority'} if BIGSdb::Utils::is_int( $params->{'priority'} );

	#If IP address already has jobs queued, i.e. not started, then lower the priority on any new
	#jobs from them.  This will prevent a single user from flooding the queue and preventing other
	#user jobs from running.
	$priority += 2 if $self->_has_ip_address_got_queued_jobs( $params->{'ip_address'} );
	my $id         = BIGSdb::Utils::get_random();
	my $cgi_params = $params->{'parameters'};
	$logger->logdie('CGI parameters not passed as a ref') if ref $cgi_params ne 'HASH';
	foreach my $key ( keys %$cgi_params ) {
		delete $cgi_params->{$key} if BIGSdb::Utils::is_int($key);    #Treeview implementation has integer node ids.
	}
	delete $cgi_params->{$_} foreach qw(submit page update_options format dbase_config_dir instance);
	my $fingerprint = $self->_make_job_fingerprint( $cgi_params, $params );
	my $status = $self->_get_status( $params, $fingerprint );
	eval {
		$self->{'db'}->do(
			'INSERT INTO jobs (id,dbase_config,username,email,ip_address,submit_time,start_time,module,status,'
			  . 'pid,percent_complete,priority,fingerprint) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
			undef,
			$id,
			$params->{'dbase_config'},
			$params->{'username'},
			$params->{'email'},
			$params->{'ip_address'},
			'now',
			( $params->{'mark_started'} ? 'now' : undef ),
			$params->{'module'},
			$status,
			( $params->{'mark_started'} ? $$ : undef ),
			( $params->{'no_progress'}  ? -1 : 0 ),
			$priority,
			$fingerprint
		);
		my $param_sql = $self->{'db'}->prepare('INSERT INTO params (job_id,key,value) VALUES (?,?,?)');
		local $" = '||';
		foreach ( keys %$cgi_params ) {
			if ( defined $cgi_params->{$_} && $cgi_params->{$_} ne '' ) {
				my @values = split( "\0", $cgi_params->{$_} );
				$param_sql->execute( $id, $_, "@values" );
			}
		}

		#Benchmarked quicker to use pg_copydata rather than multiple inserts,
		#ids are integers so no problem with escaping values.
		if ( ref $params->{'isolates'} eq 'ARRAY' ) {
			my @checked_list;
			foreach my $id ( @{ $params->{'isolates'} } ) {
				push @checked_list, $id if BIGSdb::Utils::is_int($id);
			}
			if (@checked_list) {
				$self->{'db'}->do('COPY isolates (job_id,isolate_id) FROM STDIN');
				foreach my $isolate_id (@checked_list) {
					$self->{'db'}->pg_putcopydata("$id\t$isolate_id\n");
				}
				$self->{'db'}->pg_putcopyend;
			}
		}

		#Safer to use placeholders and multiple inserts for profiles and loci though.
		if ( ref $params->{'profiles'} eq 'ARRAY' && $cgi_params->{'scheme_id'} ) {
			my @list = @{ $params->{'profiles'} };
			my $sql  = $self->{'db'}->prepare('INSERT INTO profiles (job_id,scheme_id,profile_id) VALUES (?,?,?)');
			$sql->execute( $id, $cgi_params->{'scheme_id'}, $_ ) foreach @{ $params->{'profiles'} };
		}
		if ( ref $params->{'loci'} eq 'ARRAY' ) {
			my $sql = $self->{'db'}->prepare('INSERT INTO loci (job_id,locus) VALUES (?,?)');
			$sql->execute( $id, $_ ) foreach @{ $params->{'loci'} };
		}
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return $id;
}

sub _get_status {
	my ( $self, $params, $fingerprint ) = @_;
	return 'started' if $params->{'mark_started'};
	my $duplicate_job = $self->_get_duplicate_job_id( $fingerprint, $params->{'username'}, $params->{'ip_address'} );
	my $quota_exceeded = $self->_is_quota_exceeded($params);
	my $status;
	if ($duplicate_job) {
		$status = "rejected - duplicate job ($duplicate_job)";
	} elsif ($quota_exceeded) {
		$status = $self->_get_quota_status($quota_exceeded);
	} else {
		$status = 'submitted';
	}
	return $status;
}

sub _get_quota_status {
	my ( $self, $quota_status ) = @_;
	if ( $quota_status == DBASE_QUOTA_EXCEEDED ) {
		my $plural = $self->{'system'}->{'job_quota'} == 1 ? '' : 's';
		return "rejected - database jobs exceeded. This database has a quota of $self->{'system'}->{'job_quota'} "
		  . "concurrent job$plural.  Please try again later.";
	} elsif ( $quota_status == USER_QUOTA_EXCEEDED ) {
		my $plural = $self->{'system'}->{'user_job_quota'} == 1 ? '' : 's';
		return "rejected - database jobs exceeded. This database has a quota of $self->{'system'}->{'user_job_quota'} "
		  . "concurrent job$plural for any user.  Please try again later.";
	}
	$logger->error('Invalid job quota status - this should not be possible.');
	return;
}

sub _make_job_fingerprint {
	my ( $self, $cgi_params, $params ) = @_;
	my $buffer = q();
	return $buffer if $params->{'mark_started'};
	foreach my $key ( sort keys %$cgi_params ) {
		$buffer .= "$key:$cgi_params->{$key};" if ( $cgi_params->{$key} // '' ) ne '';
	}
	local $" = ',';
	$buffer .= "isolates:@{ $params->{'isolates'} };"
	  if defined $params->{'isolates'} && ref $params->{'isolates'} eq 'ARRAY';
	$buffer .= "profiles:@{ $params->{'profiles'} };"
	  if defined $params->{'profiles'} && ref $params->{'profiles'} eq 'ARRAY';
	$buffer .= "loci:@{ $params->{'loci'} };" if defined $params->{'loci'} && ref $params->{'loci'} eq 'ARRAY';
	my $fingerprint = Digest::MD5::md5_hex($buffer);
	return $fingerprint;
}

sub _has_ip_address_got_queued_jobs {
	my ( $self, $ip_address ) = @_;
	return $self->_run_query( 'SELECT EXISTS(SELECT * FROM jobs WHERE (ip_address,status)=(?,?))',
		[ $ip_address, 'submitted' ] );
}

sub _is_quota_exceeded {
	my ( $self, $params ) = @_;
	if ( BIGSdb::Utils::is_int( $self->{'system'}->{'job_quota'} ) ) {
		my $job_count =
		  $self->_run_query( q[SELECT COUNT(*) FROM jobs WHERE dbase_config=? AND status IN ('submitted','started')],
			$params->{'dbase_config'} );
		return DBASE_QUOTA_EXCEEDED if $job_count >= $self->{'system'}->{'job_quota'};
	}
	if ( BIGSdb::Utils::is_int( $self->{'system'}->{'user_job_quota'} ) && $params->{'username'} ) {
		my $job_count =
		  $self->_run_query(
			q[SELECT COUNT(*) FROM jobs WHERE (dbase_config,username)=(?,?) AND status IN ('submitted','started')],
			[ $params->{'dbase_config'}, $params->{'username'} ] );
		return USER_QUOTA_EXCEEDED if $job_count >= $self->{'system'}->{'user_job_quota'};
	}
	return;
}

sub _get_duplicate_job_id {
	my ( $self, $fingerprint, $username, $ip_address ) = @_;
	my $qry = q(SELECT id FROM jobs WHERE fingerprint=? AND (status='started' OR status='submitted') AND );
	$qry .= $self->{'system'}->{'read_access'} eq 'public' ? 'ip_address=?' : 'username=?';
	return $self->_run_query( $qry,
		[ $fingerprint, ( $self->{'system'}->{'read_access'} eq 'public' ? $ip_address : $username ) ] );
}

sub cancel_job {
	my ( $self, $id ) = @_;
	eval { $self->{'db'}->do( q(UPDATE jobs SET status='cancelled',cancel=true WHERE id=?), undef, $id ) };
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub update_job_output {
	my ( $self, $job_id, $output_hash ) = @_;
	if ( ref $output_hash ne 'HASH' ) {
		$logger->error('status hash not passed as a ref');
		BIGSdb::Exception::Data->throw('status hash not passed as a ref');
	}
	if ( !$self->{'db'}->ping ) {
		$self->_db_connect( { reconnect => 1 } );
		undef $self->{'sql'};
	}
	if ( $output_hash->{'compress'} ) {
		my $full_path = "$self->{'config'}->{'tmp_dir'}/$output_hash->{'filename'}";
		if ( -s $full_path > ( 10 * 1024 * 1024 ) ) {    #>10 MB
			if ( $output_hash->{'keep_original'} ) {
				system("gzip -c $full_path > $full_path\.gz");
			} else {
				system( 'gzip', $full_path );
			}
			if ( $? == -1 ) {
				$logger->error("Can't gzip file $full_path: $!");
			} else {
				$output_hash->{'filename'}    .= '.gz';
				$output_hash->{'description'} .= ' [gzipped file]';
			}
		}
	}
	eval {
		$self->{'db'}->do(
			'INSERT INTO output (job_id,filename,description) VALUES (?,?,?)',
			undef, $job_id,
			$output_hash->{'filename'},
			$output_hash->{'description'}
		);
	};
	if ($@) {
		$logger->logcarp($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub update_job_status {
	my ( $self, $job_id, $status_hash ) = @_;
	if ( ref $status_hash ne 'HASH' ) {
		$logger->error('status hash not passed as a ref');
		BIGSdb::Exception::Data->throw('status hash not passed as a ref');
	}
	if ( !$self->{'db'}->ping ) {
		$self->_db_connect( { reconnect => 1 } );
		undef $self->{'sql'};
	}
	my ( @keys, @values );
	foreach my $key ( sort keys %$status_hash ) {
		push @keys,   $key;
		push @values, $status_hash->{$key};
	}
	local $" = '=?,';
	my $qry = "UPDATE jobs SET @keys=? WHERE id=?";
	if ( !$self->{'sql'}->{$qry} ) {

		#Prepare and cache statement handle.  Previously, using DBI::do resulted in continuously increasing memory use.
		$self->{'sql'}->{$qry} = $self->{'db'}->prepare($qry);
	}
	eval { $self->{'sql'}->{$qry}->execute( @values, $job_id ) };
	if ($@) {
		$logger->logcarp($@);
		local $" = q(;);
		$logger->error("Values were: @values");
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return if ( $status_hash->{'status'} // '' ) eq 'failed';
	my $job = $self->get_job_status($job_id);
	if ( $job->{'status'} && $job->{'status'} eq 'cancelled' || $job->{'cancel'} ) {
		system( 'kill', $job->{'pid'} ) if $job->{'pid'};
	}
	return;
}

sub update_notifications {
	my ( $self, $job_id, $values ) = @_;
	if ( !$self->{'sql'}->{'param_exists'} ) {
		$self->{'sql'}->{'param_exists'} =
		  $self->{'db'}->prepare('SELECT EXISTS(SELECT * FROM params WHERE (job_id,key)=(?,?))');
	}
	eval {
		foreach my $param (qw(email title description enable_notifications job_url)) {
			my ($exists) = $self->{'db'}->selectrow_array( $self->{'sql'}->{'param_exists'}, undef, $job_id, $param );
			if ($exists) {
				$self->{'db'}->do( 'UPDATE params SET value=? WHERE (job_id,key)=(?,?)',
					undef, $values->{$param}, $job_id, $param );
			} else {
				$self->{'db'}->do( 'INSERT INTO params (job_id,key,value) VALUES (?,?,?)',
					undef, $job_id, $param, $values->{$param} );
			}
		}
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub get_job_status {
	my ( $self, $job_id ) = @_;
	my $status =
	  $self->_run_query( 'SELECT status,cancel,pid FROM jobs WHERE id=?', $job_id, { fetch => 'row_hashref' } );
	$self->{'db'}->commit;    #Prevent idle in transaction table lock.
	return $status;
}

sub get_job {
	my ( $self, $job_id ) = @_;
	my $qry = 'SELECT *,extract(epoch FROM now() - start_time) AS elapsed,extract(epoch FROM '
	  . 'stop_time - start_time) AS total_time, localtimestamp AS query_time FROM jobs WHERE id=?';
	return $self->_run_query( $qry, $job_id, { fetch => 'row_hashref' } );
}

sub get_job_params {
	my ( $self, $job_id ) = @_;
	my $key_values =
	  $self->_run_query( 'SELECT key,value FROM params WHERE job_id=?', $job_id, { fetch => 'all_arrayref' } );
	my $params;
	$params->{ $_->[0] } = $_->[1] foreach @$key_values;
	return $params;
}

sub get_job_output {
	my ( $self, $job_id ) = @_;
	my $key_values = $self->_run_query( 'SELECT description,filename FROM output WHERE job_id=?',
		$job_id, { fetch => 'all_arrayref' } );
	my $output;
	$output->{ $_->[0] } = $_->[1] foreach @$key_values;
	return $output;
}

sub get_job_isolates {
	my ( $self, $job_id ) = @_;
	return $self->_run_query( 'SELECT isolate_id FROM isolates WHERE job_id=? ORDER BY isolate_id',
		$job_id, { fetch => 'col_arrayref' } );
}

sub get_job_profiles {
	my ( $self, $job_id, $scheme_id ) = @_;
	return $self->_run_query(
		'SELECT profile_id FROM profiles WHERE (job_id,scheme_id)=(?,?) ORDER BY profile_id',
		[ $job_id, $scheme_id ],
		{ fetch => 'col_arrayref' }
	);
}

sub get_job_loci {
	my ( $self, $job_id ) = @_;
	return $self->_run_query( 'SELECT locus FROM loci WHERE job_id=? ORDER BY locus', $job_id,
		{ fetch => 'col_arrayref' } );
}

sub get_user_jobs {
	my ( $self, $instance, $username, $days ) = @_;
	my $qry =
	    q[SELECT *,extract(epoch FROM now() - start_time) AS elapsed,extract(epoch FROM stop_time - ]
	  . q[start_time) AS total_time FROM jobs WHERE (dbase_config,username)=(?,?) AND (submit_time > ]
	  . qq[now()-interval '$days days' OR stop_time > now()-interval '$days days' OR status='started' OR ]
	  . q[status='submitted') ORDER BY submit_time];
	my $jobs = $self->_run_query( $qry, [ $instance, $username ], { fetch => 'all_arrayref', slice => {} } );
	return $jobs;
}

sub get_jobs_ahead_in_queue {
	my ( $self, $job_id ) = @_;
	my $qry =
	    q[SELECT COUNT(j1.id) FROM jobs AS j1 INNER JOIN jobs AS j2 ON (j1.submit_time < j2.submit_time AND ]
	  . q[j2.priority <= j1.priority) OR j2.priority > j1.priority WHERE j2.id = ? AND j2.id != j1.id AND ]
	  . q[j1.status='submitted'];
	return $self->_run_query( $qry, $job_id );
}

sub get_next_job_id {
	my ($self) = @_;
	return $self->_run_query(
		q(SELECT id FROM jobs WHERE status='submitted' ORDER BY priority asc,submit_time asc LIMIT 1));
}

#Cutdown version of Datastore::run_query as Datastore not initialized.
sub _run_query {
	my ( $self, $qry, $values, $options ) = @_;
	if ( !$self->{'db'}->ping ) {
		$self->_db_connect( { reconnect => 1 } );
		undef $self->{'sql'};
	}
	if ( defined $values ) {
		$values = [$values] if ref $values ne 'ARRAY';
	} else {
		$values = [];
	}
	my $sql = $self->{'db'}->prepare($qry);
	$options->{'fetch'} //= 'row_array';
	if ( $options->{'fetch'} eq 'col_arrayref' ) {
		my $data;
		eval { $data = $self->{'db'}->selectcol_arrayref( $sql, undef, @$values ) };
		$logger->logcarp($@) if $@;
		return $data;
	}
	eval { $sql->execute(@$values) };
	$logger->logcarp($@) if $@;
	if ( $options->{'fetch'} eq 'row_array' ) {    #returns () when no rows, (undef-scalar context)
		return $sql->fetchrow_array;
	}
	if ( $options->{'fetch'} eq 'row_hashref' ) {    #returns undef when no rows
		return $sql->fetchrow_hashref;
	}
	if ( $options->{'fetch'} eq 'all_arrayref' ) {    #returns [] when no rows
		return $sql->fetchall_arrayref( $options->{'slice'} );
	}
	$logger->logcarp('Query failed - invalid fetch method specified.');
	return;
}

sub get_job_temporal_data {
	my ( $self, $past_mins ) = @_;
	return $self->_run_query(
		q[SET timezone TO 'UTC';]
		  . q[SELECT submit_time,start_time,stop_time,status FROM jobs where ((submit_time > now()-interval ]
		  . qq['$past_mins min' OR start_time > now()-interval '$past_mins min' OR ]
		  . qq[stop_time > now()-interval '$past_mins min') AND ]
		  . q[(status NOT LIKE '%rejected%' AND status != 'cancelled')) OR status='started' ORDER BY submit_time],
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
}

sub get_period_timestamp {
	my ( $self, $past_mins ) = @_;
	return $self->_run_query(qq(SET timezone TO 'UTC';SELECT CAST(now()-interval '$past_mins min' AS timestamp)));
}

sub get_summary_stats {
	my ($self) = @_;
	my ( $running, $queued, $day ) =
	  $self->_run_query( q(SELECT SUM(CASE WHEN status='started' THEN 1 ELSE 0 END) AS running, )
		  . q(SUM(CASE WHEN status='submitted' THEN 1 ELSE 0 END) AS queued, )
		  . q(SUM(CASE WHEN stop_time > now()-interval '1 day' THEN 1 ELSE 0 END) AS day FROM jobs) );
	my $results = { running => $running, queued => $queued, day => $day };
	if ( ( $self->{'config'}->{'results_deleted_days'} // 0 ) >= 7 ) {
		my $week = $self->_run_query(q(SELECT COUNT(*) FROM jobs WHERE stop_time > now()-interval '7 days'));
		$results->{'week'} = $week;
	}
	return $results;
}

sub purge_old_jobs {
	my ($self) = @_;
	my $days = $self->{'config'}->{'results_deleted_days'} // RESULTS_DELETED_DAYS;
	eval {
		$self->{'db'}->do(
			    qq[DELETE FROM jobs where (stop_time IS NOT NULL AND stop_time < now()-interval '$days days') ]
			  . qq[OR (status LIKE 'rejected%' AND submit_time < now()-interval '$days days') OR ]
			  . q[(status IN ('failed','cancelled','terminated','finished') ]
			  . qq[AND stop_time IS NULL AND submit_time <now()-interval '$days days')]
		);
	};
	if ($@) {
		$logger->logcarp($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}
1;
