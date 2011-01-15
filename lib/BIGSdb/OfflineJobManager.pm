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

use base qw(BIGSdb::Application);
use Error qw(:try);
use Log::Log4perl qw(get_logger);

sub new {
	my ( $class, $config_dir, $plugin_dir, $dbase_config_dir, $host, $port, $user, $password ) = @_;
	my $self = {};
	$self->{'system'}           = {};
	$self->{'host'} = $host;
	$self->{'port'} = $port;
	$self->{'user'} = $user;
	$self->{'password'} = $password;
	$self->{'xmlHandler'}       = undef;
	$self->{'dataConnector'}    = new BIGSdb::Dataconnector;
	bless( $self, $class );
	$self->_initiate( $config_dir, $dbase_config_dir );	
#	$self->{'dataConnector'}->initiate($self->{'system'});
	$self->_db_connect;
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
	if (!$self->{'config'}->{'jobs_db'}){
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

1;