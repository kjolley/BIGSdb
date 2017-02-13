#Written by Keith Jolley
#Copyright (c) 2011-2017, University of Oxford
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
use 5.010;
use parent qw(BIGSdb::Offline::Script BIGSdb::Page);
use Error qw(:try);
use BIGSdb::OfflineJobManager;
use BIGSdb::PluginManager;
use BIGSdb::Parser;
use Email::Sender::Transport::SMTP;
use Email::Sender::Simple qw(try_to_sendmail);
use Email::Simple;
use Email::Simple::Creator;
use Email::Valid;
use constant DEFAULT_DOMAIN => 'pubmlst.org';

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
	$self->{'xmlHandler'} = $xmlHandler;
	$self->{'system'}     = $xmlHandler->get_system_hash;
	##### Tuco : 26.09.2016: Set again from db.conf as previous statement erase it
	$self->set_dbconnection_params(
		{
			user     => $self->{'config'}->{'dbuser'},
			password => $self->{'config'}->{'dbpasword'},
			host     => $self->{'config'}->{'dbhost'},
			port     => $self->{'config'}->{'dbport'}
		}
	);
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
	my $job = $self->{'jobManager'}->get_job($job_id);
	if ( $job->{'cancel'} ) {
		$self->{'jobManager'}->update_job_status( $job_id, { status => 'cancelled' } );
		exit;
	}
	my $params = $self->{'jobManager'}->get_job_params($job_id);
	$params->{$_} = $self->{$_} foreach qw(lib_dir config_dir dbase_config_dir);
	my $instance = $job->{'dbase_config'};
	$self->_initiate_db($instance);
	$self->{'system'}->{'set_id'} = $params->{'set_id'};
	$self->initiate_view( $job->{'username'} );
	my $plugin = $self->{'pluginManager'}->get_plugin( $job->{'module'} );
	$self->{'jobManager'}->update_job_status( $job_id, { status => 'started', start_time => 'now', pid => $$ } );
	try {
		$plugin->run_job( $job_id, $params );
		$job = $self->{'jobManager'}->get_job($job_id);
		my $status = $job->{'status'} // 'started';
		$status = 'finished' if $status eq 'started';
		$self->{'jobManager'}->update_job_status( $job_id,
			{ status => $status, stage => undef, stop_time => 'now', percent_complete => 100, pid => undef } );
	}
	catch BIGSdb::PluginException with {
		my $msg = shift;
		$self->{'logger'}->debug($msg);
		$self->{'jobManager'}->update_job_status(
			$job_id,
			{
				status           => 'failed',
				stop_time        => 'now',
				percent_complete => 100,
				message_html     => qq(<p class="statusbad">$msg</p>),
				pid              => undef
			}
		);
	};
	$self->_notify_user($job_id);
	return;
}

sub _notify_user {
	my ( $self, $job_id ) = @_;
	return if !$self->{'config'}->{'smtp_server'};
	my $job    = $self->{'jobManager'}->get_job($job_id);
	my $params = $self->{'jobManager'}->get_job_params($job_id);
	return if !$params->{'enable_notifications'};
	my $address = Email::Valid->address( $params->{'email'} );
	return if !$address;
	my $domain = $self->{'config'}->{'domain'} // DEFAULT_DOMAIN;
	my $subject = qq(Job finished: $job_id);
	$subject .= qq( - $params->{'title'}) if $params->{'title'};
	my $message = qq(The following job has finished:\n\n);
	$message .= qq(     Job id: $job_id\n);
	$message .= qq(   Database: $job->{'dbase_config'}\n);
	$message .= qq(     Module: $job->{'module'}\n);
	my $time = substr( $job->{'submit_time'}, 0, 16 );
	$message .= qq(Submit time: $time\n);
	$message .= qq(      Title: $params->{'title'}\n) if $params->{'title'};
	$message .= qq(Description: $params->{'description'}\n) if $params->{'description'};
	$message .= qq(        URL: $params->{'job_url'}\n\n);

	if ( BIGSdb::Utils::is_int( $self->{'config'}->{'results_deleted_days'} ) ) {
		$message .= qq(This job will remain on the server for $self->{'config'}->{'results_deleted_days'} days.);
	}
	my $transport = Email::Sender::Transport::SMTP->new(
		{ host => $self->{'config'}->{'smtp_server'} // 'localhost', port => $self->{'config'}->{'smtp_port'} // 25, }
	);
	my $email = Email::Simple->create(
		header => [
			To             => $address,
			From           => "no_reply\@$domain",
			Subject        => $subject,
			'Content-Type' => 'text/plain; charset=UTF-8'
		],
		body => $message
	);
	$self->{'logger'}->info("Email job report to $address");
	try_to_sendmail( $email, { transport => $transport } )
	  || $self->{'logger'}->error("Cannot send E-mail to $address");
	return;
}
1;
