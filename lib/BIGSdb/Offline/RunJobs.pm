#Written by Keith Jolley
#Copyright (c) 2011-2025, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
use BIGSdb::Exceptions;
use BIGSdb::OfflineJobManager;
use BIGSdb::PluginManager;
use BIGSdb::Parser;
use BIGSdb::Constants qw(DEFAULT_DOMAIN);
use Email::Sender::Transport::SMTP;
use Email::Sender::Simple qw(try_to_sendmail);
use Email::MIME;
use Email::Valid;
use Try::Tiny;

sub initiate {
	my ($self) = @_;
	$self->initiate_job_manager;

	#refdb attribute has been renamed ref_db for consistency with other databases (refdb still works)
	$self->{'config'}->{'ref_db'} //= $self->{'config'}->{'refdb'};
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
		$self->{'system'}->{'view'} ||= 'isolates';
		$self->{'system'}->{'original_view'} = $self->{'system'}->{'view'};
		$self->{'system'}->{'labelfield'} ||= 'isolate';
	}
	$self->set_system_overrides;
	$self->{'dataConnector'}->initiate( $self->{'system'}, $self->{'config'} );
	$self->db_connect;
	$self->setup_datastore;
	$self->{'datastore'}->initiate_userdbs;
	$self->setup_remote_contig_manager;
	$self->initiate_plugins( $self->{'lib_dir'} );
	return;
}

sub run_script {
	my ($self) = @_;
	my $job_id = $self->{'jobManager'}->get_next_job_id;
	if ( !$job_id ) {
		$self->_purge;
		exit;
	}
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
	$self->{'curate'} = 1 if $params->{'curate'};
	$self->initiate_view( $job->{'username'} );
	$self->{'jobManager'}->update_job_status( $job_id, { status => 'started', start_time => 'now', pid => $$ } );
	my $attributes = $self->{'pluginManager'}->get_plugin_attributes( $job->{'module'} );

	if ( ( $attributes->{'language'} // q() ) eq 'Python' ) {
		if ( $self->_python_plugins_enabled ) {
			my $appender     = Log::Log4perl->appender_by_name('A1');
			my $log_filename = $appender->{'filename'} // '/var/log/bigsdb_jobs.log';
			my $command =
				"$self->{'config'}->{'python_plugin_runner_path'} --run_job $job_id "
			  . "--database $job->{'dbase_config'} --module $job->{'module'} "
			  . "--module_dir $self->{'config'}->{'python_plugin_dir'} --log_file $log_filename";
			system($command);
		} else {
			$self->{'logger'}->logdie('Python plugins are not enabled');
		}
	} else {
		my $plugin = $self->{'pluginManager'}->get_plugin( $job->{'module'} );
		try {
			$plugin->run_job( $job_id, $params );
		} catch {
			if ( $_->isa('BIGSdb::Exception::Plugin') ) {
				$self->{'logger'}->debug($_);
				$self->{'jobManager'}->update_job_status(
					$job_id,
					{
						status           => 'failed',
						stop_time        => 'now',
						percent_complete => 100,
						message_html     => qq(<p class="statusbad">$_</p>),
						pid              => undef
					}
				);
			} else {
				$self->{'logger'}->logdie($_);
			}
		};
	}
	$job = $self->{'jobManager'}->get_job($job_id);
	my $status = $job->{'status'} // 'started';
	$status = 'finished' if $status eq 'started';
	$self->{'jobManager'}->update_job_status( $job_id,
		{ status => $status, stage => undef, stop_time => 'now', percent_complete => 100, pid => undef } );
	$self->_notify_user($job_id);
	return;
}

sub _python_plugins_enabled {
	my ($self) = @_;
	my $python_config = "$self->{'config_dir'}/python_plugins.json";
	return
		 $self->{'config'}->{'python_plugin_runner_path'}
	  && $self->{'config'}->{'python_plugin_dir'}
	  && -e $python_config;
}

sub _notify_user {
	my ( $self, $job_id ) = @_;
	return if !$self->{'config'}->{'smtp_server'};
	my $job    = $self->{'jobManager'}->get_job($job_id);
	my $params = $self->{'jobManager'}->get_job_params($job_id);
	return if !$params->{'enable_notifications'};
	my $address = Email::Valid->address( $params->{'email'} );
	return if !$address;
	my $domain  = $self->{'config'}->{'domain'} // DEFAULT_DOMAIN;
	my $subject = qq(Job finished: $job_id);
	$subject .= qq( - $params->{'title'}) if $params->{'title'};
	my $message = qq(The following job has finished:\n\n);
	$message .= qq(     Job id: $job_id\n);
	$message .= qq(   Database: $job->{'dbase_config'}\n);
	$message .= qq(     Module: $job->{'module'}\n);
	my $time = substr( $job->{'submit_time'}, 0, 16 );
	$message .= qq(Submit time: $time\n);
	$message .= qq(      Title: $params->{'title'}\n)       if $params->{'title'};
	$message .= qq(Description: $params->{'description'}\n) if $params->{'description'};
	$message .= qq(        URL: $params->{'job_url'}\n\n);

	if ( BIGSdb::Utils::is_int( $self->{'config'}->{'results_deleted_days'} ) ) {
		$message .= qq(This job will remain on the server for $self->{'config'}->{'results_deleted_days'} days.);
	}
	my $transport = Email::Sender::Transport::SMTP->new(
		{ host => $self->{'config'}->{'smtp_server'} // 'localhost', port => $self->{'config'}->{'smtp_port'} // 25, }
	);
	my $sender_address = $self->{'config'}->{'automated_email_address'} // "no_reply\@$domain";
	my $email          = Email::MIME->create(
		attributes => {
			encoding => 'quoted-printable',
			charset  => 'UTF-8',
		},
		header_str => [
			To      => $address,
			From    => $sender_address,
			Subject => $subject
		],
		body_str => $message
	);
	$self->{'logger'}->info("Email job report to $address");
	eval {
		try_to_sendmail( $email, { transport => $transport } )
		  || $self->{'logger'}->error("Cannot send E-mail to $address");
	};
	$self->{'logger'}->error($@) if $@;
	return;
}

#Only need to purge old jobs infrequently. This script is usually run from
#a CRON job every minute, so we can check the time and only purge if we're
#on the hour. It is also only run if there is no job to run (it doesn't really
#matter when or how often old jobs are purged, as long as it happens occasionally).
sub _purge {
	my ($self) = @_;
	my @time   = localtime(time);
	my $min    = $time[1];
	return if $min != 0;
	$self->{'jobManager'}->purge_old_jobs;
	return;
}
1;
