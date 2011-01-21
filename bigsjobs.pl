#!/usr/bin/perl -T
#Offline Job Manager for BIGSdb
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

#This script should be run frequently (perhaps every minute) as
#a CRON job.  If the load average of the server is too high (as
#defined in bigsdb.conf) or there is no job to process, the script
#will exit immediately.  Note that CRON does not like '.' in executable
#filenames, so either rename the script to 'bigsjobs' or create
#a symlink and call that from CRON.
use strict;
###########Local configuration################################
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases',
	HOST             => 'localhost',
	PORT             => 5432,
	USER             => 'bigsdb',
	PASSWORD         => 'bigsdb'
};
#######End Local configuration################################
use DBI;
use CGI;
use Log::Log4perl qw(get_logger);
use lib (LIB_DIR);
use Config::Tiny;
use Error qw(:try);
use BIGSdb::Parser;
use BIGSdb::Datastore;
use BIGSdb::OfflineJobManager;
use BIGSdb::PluginManager;
use BIGSdb::Dataconnector;
use BIGSdb::BIGSException;
Log::Log4perl->init_once( CONFIG_DIR . '/job_logging.conf' );
my $logger     = get_logger('BIGSdb.Job');
$ENV{'PATH'} = '/bin:/usr/bin';    #so we don't foul taint check
my $config = read_config_file();

my $load_average; 
my $max_load = $config->{'max_load'} || 8;

try {
	$load_average = get_load_average();
} catch BIGSdb::DataException with {
	$logger->fatal("Can't determine load average ... aborting!");
	exit;
};

exit if $load_average > $max_load;

my $cgi = new CGI;                 #Plugins expect a CGI object even though we're not using one
my $job_manager = BIGSdb::OfflineJobManager->new( CONFIG_DIR, LIB_DIR, DBASE_CONFIG_DIR, HOST, PORT, USER, PASSWORD );
my $job_id      = $job_manager->get_next_job_id;
exit if !$job_id;
my ( $job, $params ) = $job_manager->get_job($job_id);

my $instance   = $job->{'dbase_config'};
my $full_path  = DBASE_CONFIG_DIR . "/$instance/config.xml";
my $xmlHandler = BIGSdb::Parser->new();
my $parser     = XML::Parser::PerlSAX->new( Handler => $xmlHandler );
eval { $parser->parse( Source => { SystemId => $full_path } ); };

if ($@) {
	$logger->fatal("Invalid XML description: $@");
	return;
}

my $system = $xmlHandler->get_system_hash;
$system->{'host'}     = 'localhost' if !$system->{'host'};
$system->{'port'}     = 5432        if !$system->{'port'};
$system->{'user'}     = 'apache'    if !$system->{'user'};
$system->{'password'} = 'remote'    if !$system->{'password'};
$system->{'view'}     = 'isolates'  if !$system->{'view'};
my $dataConnector = BIGSdb::Dataconnector->new();
$dataConnector->initiate($system);
my $db;
$logger->info("Job: $job->{'id'}; Module: $job->{'module'}");

db_connect($system);
my $datastore = BIGSdb::Datastore->new(
	( 'db' => $db, 'dataConnector' => $dataConnector, 'system' => $system, 'config' => $config, 'xmlHandler' => $xmlHandler ) );
my $plugin_manager = BIGSdb::PluginManager->new(
	'system'        => $system,
	'cgi'           => $cgi,
	'instance'      => $instance,
	'config'        => $config,
	'datastore'     => $datastore,
	'db'            => $db,
	'xmlHandler'    => $xmlHandler,
	'dataConnector' => $dataConnector,
	'jobManager'    => $job_manager,
	'pluginDir'     => LIB_DIR
);
my $plugin = $plugin_manager->get_plugin( $job->{'module'} );
$job_manager->update_job_status( $job_id, { 'status' => 'started', 'start_time' => 'now' } );
$plugin->run_job( $job_id, $params );
$job_manager->update_job_status( $job_id, { 'status' => 'finished', 'stop_time' => 'now', 'percent_complete' => 100 } );
undef $dataConnector;

sub read_config_file {
	my $config = Config::Tiny->new();
	$config = Config::Tiny->read( CONFIG_DIR . "/bigsdb.conf" );
	foreach (
		qw ( prefs_db auth_db jobs_db max_load emboss_path tmp_dir secure_tmp_dir 
		blast_path muscle_path mogrify_path reference refdb )
	  )
	{
		$config->{$_} = $config->{_}->{$_};
	}
	return $config;
}

sub db_connect {
	my ($system) = @_;
	my %att = (
		'dbase_name' => $system->{'db'},
		'host'       => $system->{'host'},
		'port'       => $system->{'port'},
		'user'       => $system->{'user'},
		'password'   => $system->{'password'}
	);
	try {
		$db = $dataConnector->get_connection( \%att );
	}
	catch BIGSdb::DatabaseConnectionException with {
		my $logger = get_logger('BIGSdb.Application_Initiate');
		$logger->error("Can not connect to database '$system->{'db'}'");
		return;
	};
}

sub get_load_average {
	my $uptime = `uptime`;
	my $load;
	if ( $uptime =~ /load average:\s+([\d\.]+)/ ) {
		$load = $1;
	} else {
		throw BIGSdb::DataException("Can't determine load average");
	}
	return $load;
}


