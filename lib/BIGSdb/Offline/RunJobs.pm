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
package BIGSdb::Offline::RunJobs;
use strict;
use warnings;
use base qw(BIGSdb::Offline::Script);
use BIGSdb::OfflineJobManager;
use BIGSdb::PluginManager;
use BIGSdb::Parser;

sub initiate {
	my ($self) = @_;
	$self->{'jobManager'} = BIGSdb::OfflineJobManager->new(
		$self->{'config_dir'}, $self->{'lib_dir'},
		$self->{'dbase_config_dir'},
		$self->{'host'}     || 'localhost',
		$self->{'port'}     || 5432,
		$self->{'user'}     || 'apache',
		$self->{'password'} || 'remote'
	);
	return;
}

sub _initiate_db {
	my ( $self, $instance ) = @_;
	my $full_path  = "$self->{'dbase_config_dir'}/$instance/config.xml";
	my $xmlHandler = BIGSdb::Parser->new();
	my $parser     = XML::Parser::PerlSAX->new( Handler => $xmlHandler );
	eval { $parser->parse( Source => { SystemId => $full_path } ); };
	if ($@) {
		$self->{'logger'}->fatal("Invalid XML description: $@");
		return;
	}
	$self->{'system'} = $xmlHandler->get_system_hash;
	$self->{'system'}->{'host'}     ||= 'localhost';
	$self->{'system'}->{'port'}     ||= 5432;
	$self->{'system'}->{'user'}     ||= 'apache';
	$self->{'system'}->{'password'} ||= 'remote';
	$self->{'dataConnector'}->initiate( $self->{'system'}, $self->{'config'} );
	$self->db_connect;
	$self->setup_datastore;
	$self->initiate_plugins( $self->{'lib_dir'} );
	return;
}

sub run_script {
	my ($self) = @_;
	my $job_id = $self->{'jobManager'}->get_next_job_id;
	exit if !$job_id;
	$self->{'logger'}->info("Job:$job_id") if $job_id;
	my ( $job, $params ) = $self->{'jobManager'}->get_job($job_id);
	my $instance = $job->{'dbase_config'};
	$self->_initiate_db($instance);
	my $plugin = $self->{'pluginManager'}->get_plugin( $job->{'module'} );
	$self->{'jobManager'}->update_job_status( $job_id, { 'status' => 'started', 'start_time' => 'now' } );
	$plugin->run_job( $job_id, $params );
	$self->{'jobManager'}->update_job_status( $job_id, { 'status' => 'finished', 'stop_time' => 'now', 'percent_complete' => 100 } );
	return;
}
1;
