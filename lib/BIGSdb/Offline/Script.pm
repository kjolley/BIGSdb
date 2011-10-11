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
use BIGSdb::Parser;
$ENV{'PATH'} = '/bin:/usr/bin';    ##no critic #so we don't foul taint check
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};    # Make %ENV safer

sub new {
	my ($class, $options) = @_;
	my $self = {};
	$self->{'system'}           = {};
	$self->{'config'}           = {};
	$self->{'cgi'}              = CGI->new;
	$self->{'xmlHandler'}       = undef;
	$self->{'invalidXML'}       = 0;
	$self->{'dataConnector'}    = BIGSdb::Dataconnector->new;
	$self->{'datastore'}        = undef;
	$self->{'pluginManager'}    = undef;
	$self->{'db'}               = undef;
	$self->{'instance'}         = $options->{'instance'};
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
	$self->go;
	return $self;
}

sub initiate {
	my ( $self ) = @_;
	my $q = $self->{'cgi'};
	
	my $full_path = "$self->{'dbase_config_dir'}/$self->{'instance'}/config.xml";
	$self->{'xmlHandler'} = BIGSdb::Parser->new();
	my $parser = XML::Parser::PerlSAX->new( Handler => $self->{'xmlHandler'} );
	eval { $parser->parse( Source => { SystemId => $full_path } ); };

	if ($@) {
		$self->{'logger'}->fatal("Invalid XML description: $@") if $self->{'instance'} ne '';
		return;
	}
	$self->{'system'} = $self->{'xmlHandler'}->get_system_hash;
	if ( $self->{'system'}->{'dbtype'} ne 'sequences' && $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		$self->{'error'} = 'invalidDbType';
	}
	$self->{'system'}->{'read_access'} ||= 'public';      #everyone can view by default
	$self->{'system'}->{'host'}        ||= 'localhost';
	$self->{'system'}->{'port'}        ||= 5432;
	$self->{'system'}->{'user'}        ||= 'apache';
	$self->{'system'}->{'password'}    ||= 'remote';
	$self->{'system'}->{'locus_superscript_prefix'} ||= 'no';

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->{'system'}->{'view'}       ||= 'isolates';
		$self->{'system'}->{'labelfield'} ||= 'isolate';
		if ( !$self->{'xmlHandler'}->is_field( $self->{'system'}->{'labelfield'} ) ) {
			$self->{'logger'}->error(
"The defined labelfield '$self->{'system'}->{'labelfield'}' does not exist in the database.  Please set the labelfield attribute in the system tag of the database XML file."
			);
		}
	}
	$self->db_connect;	
	$self->setup_datastore if $self->{'db'};
	return;
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
	$self->read_config_file($self->{'config_dir'});
	$self->read_host_mapping_file($self->{'config_dir'});
	$self->initiate;
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
