#Written by Keith Jolley
#(c) 2011-2013, University of Oxford
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
use parent qw(BIGSdb::Application);
use Error qw(:try);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Job');

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
	$self->_db_connect;
	return $self;
}

sub _initiate {
	my ( $self, $config_dir ) = @_;
	$self->read_config_file($config_dir);
	return;
}

sub _db_connect {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $logger = get_logger('BIGSdb.Application_Initiate');
	if ( !$self->{'config'}->{'jobs_db'} ) {
		$logger->fatal("jobs_db not set in config file.");
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
		$self->{'db'} = $self->{'dataConnector'}->drop_connection( \%att );
	}
	try {
		$self->{'db'} = $self->{'dataConnector'}->get_connection( \%att );
	}
	catch BIGSdb::DatabaseConnectionException with {
		my $logger = get_logger('BIGSdb.Application_Initiate');
		$logger->error("Can not connect to database '$self->{'config'}->{'jobs_db'}'");
		return;
	};
	return;
}

sub add_job {

	#Required params:
	#dbase_config: name of db configuration direction in /etc/dbases
	#ip_address: connecting address
	#module: Plugin module name
	#function: Function in module to call
	#
	#Optional params:
	#username and email of user
	#priority: (highest 1 - lowest 9)
	#parameters: any additional parameters needed by plugin (hashref)
	my ( $self, $params ) = @_;
	foreach (qw (dbase_config ip_address module)) {
		if ( !$params->{$_} ) {
			$logger->error("Parameter $_ not passed");
			throw BIGSdb::DataException("Parameter $_ not passed");
		}
	}
	my $priority;
	if ( $self->{'system'}->{'job_priority'} && BIGSdb::Utils::is_int( $self->{'system'}->{'job_priority'} ) ) {
		$priority = $self->{'system'}->{'job_priority'};    #Database level priority
	} else {
		$priority = 5;
	}
	$priority += $params->{'priority'} if $params->{'priority'} && BIGSdb::Utils::is_int( $params->{'priority'} );    #Plugin level priority
	my $id         = BIGSdb::Utils::get_random();
	my $cgi_params = $params->{'parameters'};
	if ( ref $cgi_params ne 'HASH' ) {
		$logger->error("CGI parameters not passed as a ref");
		throw BIGSdb::DataException("CGI parameters not passed as a ref");
	}
	eval {
		$self->{'db'}->do(
			"INSERT INTO jobs (id,dbase_config,username,email,ip_address,submit_time,module,status,percent_complete,"
			  . "priority) VALUES (?,?,?,?,?,?,?,?,?,?)",
			undef,
			$id,
			$params->{'dbase_config'},
			$params->{'username'},
			$params->{'email'},
			$params->{'ip_address'},
			'now',
			$params->{'module'},
			'submitted',
			0,
			$priority
		);
		my $param_sql = $self->{'db'}->prepare("INSERT INTO params (job_id,key,value) VALUES (?,?,?)");
		local $" = '||';
		foreach ( keys %$cgi_params ) {
			if ( defined $cgi_params->{$_} && $cgi_params->{$_} ne '' ) {
				my @values = split( "\0", $cgi_params->{$_} );
				$param_sql->execute( $id, $_, "@values" );
			}
		}
		if ( defined $params->{'isolates'} && ref $params->{'isolates'} eq 'ARRAY' ) {

			#Benchmarked quicker to use single insert rather than multiple inserts, ids are integers so no problem with escaping values.
			my @checked_list;
			foreach my $id ( @{ $params->{'isolates'} } ) {
				push @checked_list, $id if BIGSdb::Utils::is_int($id);
			}
			local $" = "),('$id',";
			my $sql = $self->{'db'}->prepare("INSERT INTO isolates (job_id,isolate_id) VALUES ('$id',@checked_list)");
			$sql->execute;
		}
		if ( defined $params->{'loci'} && ref $params->{'loci'} eq 'ARRAY' ) {

			#Safer to use placeholders and multiple inserts for loci though.
			my $sql = $self->{'db'}->prepare("INSERT INTO loci (job_id,locus) VALUES (?,?)");
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

sub cancel_job {
	my ( $self, $id ) = @_;
	eval { $self->{'db'}->do( "UPDATE jobs SET status='cancelled',cancel=true WHERE id=?", undef, $id ) };
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
		$logger->error("status hash not passed as a ref");
		throw BIGSdb::DataException("status hash not passed as a ref");
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
			"INSERT INTO output (job_id,filename,description) VALUES (?,?,?)",
			undef, $job_id,
			$output_hash->{'filename'},
			$output_hash->{'description'}
		);
		$logger->debug( $output_hash->{'filename'} . '; ' . $output_hash->{'description'} . "; $job_id" );
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
		$logger->error("status hash not passed as a ref");
		throw BIGSdb::DataException("status hash not passed as a ref");
	}

	#Exceptions in BioPerl appear to sometimes cause the connection to the jobs database to be broken
	#No idea why - so reconnect if status is 'failed'.
	$self->_db_connect( { reconnect => 1 } ) if ( $status_hash->{'status'} // '' ) eq 'failed';
	eval {
		foreach ( keys %$status_hash )
		{
			$self->{'db'}->do( "UPDATE jobs SET $_=? WHERE id=?", undef, $status_hash->{$_}, $job_id );
		}
	};
	if ($@) {
		$logger->logcarp($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	my $job = $self->get_job($job_id);
	if ( $job->{'status'} && $job->{'status'} eq 'cancelled' || $job->{'cancel'} ) {
		system( 'kill', $job->{'pid'} );
	}
	return;
}

sub get_job {
	my ( $self, $job_id ) = @_;
	my $sql =
	  $self->{'db'}->prepare( "SELECT *,extract(epoch FROM now() - start_time) AS elapsed,extract(epoch FROM "
		  . "stop_time - start_time) AS total_time FROM jobs WHERE id=?" );
	eval { $sql->execute($job_id); };
	if ($@) {
		$logger->error($@);
		return;
	}
	my $job = $sql->fetchrow_hashref;
	return $job;
}

sub get_job_params {
	my ( $self, $job_id ) = @_;
	my $sql = $self->{'db'}->prepare("SELECT key,value FROM params WHERE job_id=?");
	my $params;
	eval { $sql->execute($job_id) };
	if ($@) {
		$logger->error($@);
		return;
	}
	while ( my ( $key, $value ) = $sql->fetchrow_array ) {
		$params->{$key} = $value;
	}
	return $params;
}

sub get_job_output {
	my ( $self, $job_id ) = @_;
	my $sql = $self->{'db'}->prepare("SELECT filename,description FROM output WHERE job_id=?");
	eval { $sql->execute($job_id) };
	if ($@) {
		$logger->error($@);
		return;
	}
	my $output;
	while ( my ( $filename, $desc ) = $sql->fetchrow_array ) {
		$output->{$desc} = $filename;
	}
	return $output;
}

sub get_job_isolates {
	my ( $self, $job_id ) = @_;
	my $sql = $self->{'db'}->prepare("SELECT isolate_id FROM isolates WHERE job_id=? ORDER BY isolate_id");
	eval { $sql->execute($job_id) };
	$logger->error($@) if $@;
	my @isolate_ids;
	while ( my ($isolate_id) = $sql->fetchrow_array ) {
		push @isolate_ids, $isolate_id;
	}
	return \@isolate_ids;
}

sub get_job_loci {
	my ( $self, $job_id ) = @_;
	my $sql = $self->{'db'}->prepare("SELECT locus FROM loci WHERE job_id=? ORDER BY locus");
	eval { $sql->execute($job_id) };
	$logger->error($@) if $@;
	my @loci;
	while ( my ($locus) = $sql->fetchrow_array ) {
		push @loci, $locus;
	}
	return \@loci;
}

sub get_user_jobs {
	my ( $self, $instance, $username, $days ) = @_;
	my $sql =
	  $self->{'db'}->prepare( "SELECT *,extract(epoch FROM now() - start_time) AS elapsed,extract(epoch FROM stop_time - "
		  . "start_time) AS total_time FROM jobs WHERE dbase_config=? AND username=? AND (submit_time > now()-interval '$days days' "
		  . "OR stop_time > now()-interval '$days days' OR status='started' OR status='submitted') ORDER BY submit_time" );
	eval { $sql->execute( $instance, $username ) };
	if ($@) {
		$logger->error($@);
		return;
	}
	my @jobs;
	while ( my $job = $sql->fetchrow_hashref ) {
		push @jobs, $job;
	}
	return \@jobs;
}

sub get_jobs_ahead_in_queue {
	my ( $self, $job_id ) = @_;
	my $sql =
	  $self->{'db'}->prepare( "SELECT COUNT(j1.id) FROM jobs AS j1 INNER JOIN jobs AS j2 ON (j1.submit_time < j2.submit_time AND "
		  . "j2.priority <= j1.priority) OR j2.priority > j1.priority WHERE j2.id = ? AND j2.id != j1.id AND j1.status='submitted'" );
	eval { $sql->execute($job_id) };
	if ($@) {
		$logger->error($@);
		return;
	}
	my ($jobs) = $sql->fetchrow_array;
	return $jobs;
}

sub get_next_job_id {
	my ($self) = @_;
	my $sql = $self->{'db'}->prepare("SELECT id FROM jobs WHERE status='submitted' ORDER BY priority asc,submit_time asc LIMIT 1");
	eval { $sql->execute; };
	if ($@) {
		$logger->error($@);
		return;
	}
	my ($job) = $sql->fetchrow_array;
	return $job;
}
1;
