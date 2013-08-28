#Written by Keith Jolley
#Copyright (c) 2011-2012, University of Oxford
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
use parent qw(BIGSdb::Offline::Script BIGSdb::Page);
use Error qw(:try);
use BIGSdb::OfflineJobManager;
use BIGSdb::PluginManager;
use BIGSdb::Parser;

sub initiate {
	my ($self) = @_;
	$self->{'jobManager'} = BIGSdb::OfflineJobManager->new(
		{
			config_dir       => $self->{'config_dir'},
			dbase_config_dir => $self->{'dbase_config_dir'},
			host             => $self->{'host'} || 'localhost',
			port             => $self->{'port'} || 5432,
			user             => $self->{'user'} || 'apache',
			password         => $self->{'password'} || 'remote'
		}
	);
	return;
}

sub _initiate_db {
	my ( $self, $instance ) = @_;
	$self->{'instance'} = $instance;
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
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->{'system'}->{'view'}       ||= 'isolates';
		$self->{'system'}->{'labelfield'} ||= 'isolate';
	}
	$self->set_system_overrides;
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
	$self->{'system'}->{'set_id'} = $params->{'set_id'};
	$self->initiate_view( $job->{'username'} );
	my $plugin = $self->{'pluginManager'}->get_plugin( $job->{'module'} );
	$self->{'jobManager'}->update_job_status( $job_id, { status => 'started', start_time => 'now' } );
	try {
		$plugin->run_job( $job_id, $params );
		$self->{'jobManager'}
		  ->update_job_status( $job_id, { status => 'finished', stage => '', stop_time => 'now', percent_complete => 100 } );
	}
	catch BIGSdb::PluginException with {
		my $msg = shift;
		$self->{'logger'}->debug($msg);
		$self->{'jobManager'}->update_job_status( $job_id,
			{ status => 'failed', stop_time => 'now', percent_complete => 100, message_html => "<p class=\"statusbad\">$msg</p>" } );
	};
	return;
}
1;
