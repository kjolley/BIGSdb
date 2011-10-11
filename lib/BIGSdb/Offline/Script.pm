#Written by Keith Jolley
#Copyright (c) 2011, University of Oxford
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
package BIGSdb::Offline::Script;
use strict;
use warnings;
use base qw(BIGSdb::Application);
use CGI;
use DBI;
use Error qw(:try);
use Log::Log4perl qw(get_logger);
use BIGSdb::Dataconnector;
use BIGSdb::Datastore;
use BIGSdb::BIGSException;
$ENV{'PATH'} = '/bin:/usr/bin';    ##no critic #so we don't foul taint check

sub new {
	my ($class, $options) = @_;
	my $self = {};
	$self->{'system'}           = {};
	$self->{'config'}           = {};
	$self->{'cgi'}              = CGI->new;
	$self->{'instance'}         = undef;
	$self->{'xmlHandler'}       = undef;
	$self->{'invalidXML'}       = 0;
	$self->{'dataConnector'}    = BIGSdb::Dataconnector->new;
	$self->{'datastore'}        = undef;
	$self->{'pluginManager'}    = undef;
	$self->{'db'}               = undef;
	$self->{'logger'}           = $options->{'logger'};
	$self->{'config_dir'}       = $options->{'config_dir'};
	$self->{'lib_dir'}          = $options->{'lib_dir'};
	$self->{'dbase_config_dir'} = $options->{'dbase_config_dir'};
	$self->{'host'}             = $options->{'host'};
	$self->{'port'}             = $options->{'port'};
	$self->{'user'}             = $options->{'user'};
	$self->{'password'}         = $options->{'password'};
	bless( $self, $class );
	if (!defined $self->{'logger'} ){
		Log::Log4perl->init_once( "$self->{'config_dir'}/script_logging.conf" );
		$self->{'logger'}  = get_logger('BIGSdb.Script');
	}
	$self->read_config_file($options->{'config_dir'});
	$self->read_host_mapping_file($options->{'config_dir'});
	$self->initiate;
	
	$self->go;
	return $self;
}

sub initiate {
	#override in subclass
}

sub get_load_average {
	my $uptime = `uptime`;
	return $1 if $uptime =~ /load average:\s+([\d\.]+)/;
	throw BIGSdb::DataException("Can't determine load average");
}

sub go {
	my ($self) = @_;
	my $load_average;
	my $max_load = $self->{'config'}->{'max_load'} || 8;
	try {
		$load_average = $self->get_load_average;
	}
	catch BIGSdb::DataException with {
		$self->{'logger'}->fatal("Can't determine load average ... aborting!");
		exit;
	};
	return if $load_average > $max_load;
	$self->run_script;
	return;
}

sub run_script {

	#override in subclass
	my ($self) = @_;
	$self->{'logger'}->fatal("run_script should be overridden in your subclass.");
	return;
}
1;
