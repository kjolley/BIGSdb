#Written by Keith Jolley
#(c) 2011, University of Oxford
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
use base qw(BIGSdb::Application);
use Error qw(:try);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Job');

sub new {

	#The job manager uses its own Dataconnector since it may be called by a stand-alone script.
	my ( $class, $config_dir, $plugin_dir, $dbase_config_dir, $host, $port, $user, $password ) = @_;
	my $self = {};
	$self->{'system'}        = {};
	$self->{'host'}          = $host;
	$self->{'port'}          = $port;
	$self->{'user'}          = $user;
	$self->{'password'}      = $password;
	$self->{'xmlHandler'}    = undef;
	$self->{'dataConnector'} = new BIGSdb::Dataconnector;
	bless( $self, $class );
	$self->_initiate( $config_dir, $dbase_config_dir );
	$self->_db_connect;
	return $self;
}

sub _initiate {
	my ( $self, $config_dir, $dbase_config_dir ) = @_;
	$self->_read_config_file($config_dir);
	my $logger = get_logger('BIGSdb.Application_Initiate');

	#	$logger->error("Test logging");
}

sub _db_connect {
	my ($self) = @_;
	my $logger = get_logger('BIGSdb.Application_Initiate');
	if ( !$self->{'config'}->{'jobs_db'} ) {
		$logger->fatal("jobs_db not set in config file.");
		return;
	}
	my %att = (
		'dbase_name' => $self->{'config'}->{'jobs_db'},
		'host'       => $self->{'host'},
		'port'       => $self->{'port'},
		'user'       => $self->{'user'},
		'password'   => $self->{'password'},
		'writable'   => 1
	);
	try {
		$self->{'db'} = $self->{'dataConnector'}->get_connection( \%att );
	}
	catch BIGSdb::DatabaseConnectionException with {
		my $logger = get_logger('BIGSdb.Application_Initiate');
		$logger->error("Can not connect to database '$self->{'config'}->{'jobs_db'}'");
		return;
	};
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
	$params->{'priority'} = 5 if !$params->{'priority'};
	my $id         = BIGSdb::Utils::get_random();
	my $cgi_params = $params->{'parameters'};
	if ( ref $cgi_params ne 'HASH' ) {
		$logger->error("CGI parameters not passed as a ref");
		throw BIGSdb::DataException("CGI parameters not passed as a ref");
	}
	eval {
		$self->{'db'}->do(
"INSERT INTO jobs (id,dbase_config,username,email,ip_address,submit_time,module,status,percent_complete,priority) VALUES (?,?,?,?,?,?,?,?,?,?)",
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
			$params->{'priority'}
		);
		my $param_sql = $self->{'db'}->prepare("INSERT INTO params (job_id,key,value) VALUES (?,?,?)");
		$" = '||';
		foreach ( keys %$cgi_params ) {
			my @values = split( "\0", $cgi_params->{$_} );
			$param_sql->execute( $id, $_, "@values" );
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

sub update_job_output {
	my ( $self, $job_id, $output_hash ) = @_;
	if ( ref $output_hash ne 'HASH' ) {
		$logger->error("status hash not passed as a ref");
		throw BIGSdb::DataException("status hash not passed as a ref");
	}
	eval {
		$self->{'db'}->do(
			"INSERT INTO output (job_id,filename,description) VALUES (?,?,?)",
			undef,
			$job_id,
			$output_hash->{'filename'},
			$output_hash->{'description'}
		);
		$logger->debug($output_hash->{'filename'} . '; ' .$output_hash->{'description'}. "; $job_id");
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	
}

sub update_job_status {
	my ( $self, $job_id, $status_hash ) = @_;
	if ( ref $status_hash ne 'HASH' ) {
		$logger->error("status hash not passed as a ref");
		throw BIGSdb::DataException("status hash not passed as a ref");
	}
	eval {
		foreach ( keys %$status_hash )
		{
			$self->{'db'}->do( "UPDATE jobs SET $_=? WHERE id=?", undef, $status_hash->{$_}, $job_id );
			$logger->debug("$job_id $_: $status_hash->{$_}");
		}
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
}

sub get_job {
	my ( $self, $job_id ) = @_;
	my $sql = $self->{'db'}->prepare("SELECT * FROM jobs WHERE id=?");
	eval { $sql->execute($job_id); };
	if ($@) {
		$logger->error($@);
		return;
	}
	my $job = $sql->fetchrow_hashref;
	$sql = $self->{'db'}->prepare("SELECT key,value FROM params WHERE job_id=?");
	my ($params,$output);
	eval { $sql->execute( $job->{'id'} ); };
	if ($@) {
		$logger->error($@);
		return;
	}
	while ( my ( $key, $value ) = $sql->fetchrow_array ) {
		$params->{$key} = $value;
	}
	$sql = $self->{'db'}->prepare("SELECT filename,description FROM output WHERE job_id=?");
	eval { $sql->execute( $job->{'id'} ); };
	if ($@) {
		$logger->error($@);
		return;
	}
	while ( my ( $filename, $desc ) = $sql->fetchrow_array ) {
		$output->{$desc} = $filename;
	}
	return ( $job, $params, $output );
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
