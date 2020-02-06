#Written by Keith Jolley
#(c) 2010-2020, University of Oxford
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
package BIGSdb::BaseApplication;
use strict;
use warnings;
use 5.010;
use BIGSdb::Exceptions;
use BIGSdb::Constants qw(:login_requirements);
use BIGSdb::Dataconnector;
use BIGSdb::Datastore;
use BIGSdb::Parser;
use BIGSdb::PluginManager;
use BIGSdb::Preferences;
use BIGSdb::ContigManager;
use BIGSdb::SubmissionHandler;
use DBI;
use Carp;
use Try::Tiny;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Application_Initiate');
use List::MoreUtils qw(any);
use Config::Tiny;

sub set_dbconnection_params {
	my ( $self, $options ) = @_;
	$self->{'system'}->{'host'}     //= $options->{'host'}     // $self->{'config'}->{'dbhost'}     // 'localhost';
	$self->{'system'}->{'port'}     //= $options->{'port'}     // $self->{'config'}->{'dbport'}     // 5432;
	$self->{'system'}->{'user'}     //= $options->{'user'}     // $self->{'config'}->{'dbuser'}     // 'apache';
	$self->{'system'}->{'password'} //= $options->{'password'} // $self->{'config'}->{'dbpassword'} // 'remote';

	# These values are used in OfflineJobManager
	$self->{'host'}     //= $self->{'system'}->{'host'};
	$self->{'port'}     //= $self->{'system'}->{'port'};
	$self->{'user'}     //= $self->{'system'}->{'user'};
	$self->{'password'} //= $self->{'system'}->{'password'};
	return $self;
}

sub set_system_overrides {
	my ($self) = @_;
	return if !$self->{'instance'};
	my $override_file = "$self->{'dbase_config_dir'}/$self->{'instance'}/system.overrides";
	if ( -e $override_file ) {
		my $config = Config::Tiny->new();
		$config = Config::Tiny->read($override_file);
		foreach my $param ( keys %{ $config->{_} } ) {
			my $value = $config->{_}->{$param};
			$value =~ s/^"|"$//gx;    #Remove quotes around value
			$self->{'system'}->{$param} = $value;
		}
	}
	$self->_set_field_overrides;
	return;
}

sub _set_field_overrides {
	my ($self) = @_;
	return if !$self->{'instance'};
	my $override_file = "$self->{'dbase_config_dir'}/$self->{'instance'}/field.overrides";
	my %allowed_att = map { $_ => 1 } qw(required maindisplay);
	if ( -e $override_file ) {
		my $config = Config::Tiny->new();
		$config = Config::Tiny->read($override_file);
		foreach my $param ( keys %{ $config->{_} } ) {
			my ( $field, $attribute ) = split /:/x, $param;
			if ( !$self->{'xmlHandler'}->is_field($field) ) {
				$logger->error("Error in field.overrides file. Invalid field $field");
				next;
			}
			if ( !$allowed_att{$attribute} ) {
				$logger->error("Error in field.overrides file. Invalud attribute $attribute");
				next;
			}
			my $value = $config->{_}->{$param};
			$value =~ s/^"|"$//gx;    #Remove quotes around value
			$self->{'xmlHandler'}->{'attributes'}->{$field}->{$attribute} = $value;
		}
	}
	return;
}

sub initiate_authdb {
	my ($self) = @_;
	my %att = (
		dbase_name => $self->{'config'}->{'auth_db'},
		host       => $self->{'config'}->{'dbhost'} // $self->{'system'}->{'host'},
		port       => $self->{'config'}->{'dbport'} // $self->{'system'}->{'port'},
		user       => $self->{'config'}->{'dbuser'} // $self->{'system'}->{'user'},
		password   => $self->{'config'}->{'dbpassword'} // $self->{'system'}->{'password'},
	);
	try {
		$self->{'auth_db'} = $self->{'dataConnector'}->get_connection( \%att );
		$logger->info("Connected to authentication database '$self->{'config'}->{'auth_db'}'");
	}
	catch {
		if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
			$logger->error("Cannot connect to authentication database '$self->{'config'}->{'auth_db'}'");
			$self->{'error'} = 'noAuth';
		} else {
			$logger->logdie($_);
		}
	};
	return;
}

sub initiate_jobmanager {
	my ( $self, $config_dir, $dbase_config_dir, ) = @_;
	$self->{'jobManager'} = BIGSdb::OfflineJobManager->new(
		{
			config_dir       => $config_dir,
			dbase_config_dir => $dbase_config_dir,
			host             => $self->{'config'}->{'dbhost'} // $self->{'system'}->{'host'},
			port             => $self->{'config'}->{'dbport'} // $self->{'system'}->{'port'},
			user             => $self->{'config'}->{'dbuser'} // $self->{'system'}->{'user'},
			password         => $self->{'config'}->{'dbpassword'} // $self->{'system'}->{'password'},
			system           => $self->{'system'}
		}
	);
	return;
}

sub read_config_file {
	my ( $self, $config_dir ) = @_;
	my $config = Config::Tiny->read("$config_dir/bigsdb.conf");
	if ( !defined $config ) {
		$logger->fatal('bigsdb.conf file is not accessible.');
		$config = Config::Tiny->new();
	}
	foreach my $param ( keys %{ $config->{_} } ) {
		$self->{'config'}->{$param} = $config->{_}->{$param};
	}

	#Check integer values
	foreach my $param (
		qw(max_load max_load_webscan blast_threads bcrypt_cost mafft_threads results_deleted_days
		cache_days submissions_deleted_days)
	  )
	{
		if ( defined $self->{'config'}->{$param} && !BIGSdb::Utils::is_int( $self->{'config'}->{$param} ) ) {
			$logger->error("Parameter $param in bigsdb.conf should be an integer - default value used.");
			undef $self->{'config'}->{$param};
		}
	}

	#Check float values
	foreach my $param (qw(max_upload_size max_muscle_mb)) {
		if ( defined $self->{'config'}->{$param} && !BIGSdb::Utils::is_float( $self->{'config'}->{$param} ) ) {
			$logger->error("Parameter $param in bigsdb.conf should be a number - default value used.");
			undef $self->{'config'}->{$param};
		}
	}
	foreach my $param (qw(intranet disable_updates)) {
		$self->{'config'}->{$param} //= 0;
		$self->{'config'}->{$param} = 0 if $self->{'config'}->{$param} eq 'no';
	}
	$self->{'config'}->{'cache_days'} //= 7;
	if ( $self->{'config'}->{'chartdirector'} ) {
		eval 'use perlchartdir';    ## no critic (ProhibitStringyEval)
		if ($@) {
			$logger->error(q(Chartdirector not installed! - Either install or set 'chartdirector=0' in bigsdb.conf));
			$self->{'config'}->{'chartdirector'} = 0;
		} else {
			eval 'use BIGSdb::Charts';    ## no critic (ProhibitStringyEval)
			if ($@) {
				$logger->error('Charts.pm not installed!');
			}
		}
	}
	$self->{'config'}->{'aligner'} = 1 if $self->{'config'}->{'muscle_path'} || $self->{'config'}->{'mafft_path'};
	$self->{'config'}->{'doclink'}         //= 'http://bigsdb.readthedocs.io/en/latest';
	$self->{'config'}->{'max_upload_size'} //= 32;
	$self->{'config'}->{'max_upload_size'} *= 1024 * 1024;
	$self->{'config'}->{'python3_path'} //= '/usr/bin/python3';
	if ( $self->{'config'}->{'site_user_dbs'} ) {
		my @user_dbs;
		my @user_db_values = split /\s*,\s*/x, $self->{'config'}->{'site_user_dbs'};
		foreach my $user_db (@user_db_values) {
			my ( $name, $db_name ) = split /\|/x, $user_db;
			push @user_dbs, { name => $name, dbase => $db_name };
		}
		$self->{'config'}->{'site_user_dbs'} = \@user_dbs;
	}
	$self->_read_db_config_file($config_dir);
	return;
}

sub _read_db_config_file {
	my ( $self, $config_dir ) = @_;
	my $db_file = "$config_dir/db.conf";
	if ( !-e $db_file ) {
		$logger->info("Couldn't find db.conf in $config_dir");
		return;
	}
	my $config = Config::Tiny->new();
	$config = Config::Tiny->read("$db_file");
	foreach my $param (qw (dbhost dbport dbuser dbpassword)) {
		$self->{'config'}->{$param} = $config->{_}->{$param};
	}
	if ( defined $self->{'config'}->{'dbport'} && !BIGSdb::Utils::is_int( $self->{'config'}->{'dbport'} ) ) {
		$logger->error('Parameter dbport in db.conf should be an integer - default value used.');
		undef $self->{'config'}->{'dbport'};
	}
	$self->set_dbconnection_params();
	return;
}

sub read_host_mapping_file {
	my ( $self, $config_dir ) = @_;
	my $mapping_file = "$config_dir/host_mapping.conf";
	if ( -e $mapping_file ) {
		open( my $fh, '<', $mapping_file )
		  || $logger->error("Can't open $mapping_file for reading");
		while ( my $line = <$fh> ) {
			next if $line =~ /^\s+$/x || $line =~ /^\#/x;
			my ( $host, $mapped ) = split /\s+/x, $line;
			next if !$host || !$mapped;
			$self->{'config'}->{'host_map'}->{$host} = $mapped;
		}
		close $fh;
	}
	return;
}

sub setup_datastore {
	my ($self) = @_;
	$self->{'datastore'} = BIGSdb::Datastore->new(
		db            => $self->{'db'},
		dataConnector => $self->{'dataConnector'},
		system        => $self->{'system'},
		config        => $self->{'config'},
		xmlHandler    => $self->{'xmlHandler'},
		curate        => $self->{'curate'}
	);
	return;
}

sub setup_submission_handler {
	my ($self) = @_;
	$self->{'submissionHandler'} = BIGSdb::SubmissionHandler->new(
		dbase_config_dir => $self->{'dbase_config_dir'},
		config_dir       => $self->{'config_dir'},
		lib_dir          => $self->{'lib_dir'},
		db               => $self->{'db'},
		system           => $self->{'system'},
		config           => $self->{'config'},
		datastore        => $self->{'datastore'},
		xmlHandler       => $self->{'xmlHandler'},
		instance         => $self->{'instance'}
	);
	return;
}

sub setup_remote_contig_manager {
	my ($self) = @_;
	$self->{'contigManager'} = BIGSdb::ContigManager->new(
		dbase_config_dir => $self->{'dbase_config_dir'},
		config_dir       => $self->{'config_dir'},
		lib_dir          => $self->{'lib_dir'},
		db               => $self->{'db'},
		system           => $self->{'system'},
		config           => $self->{'config'},
		datastore        => $self->{'datastore'},
		xmlHandler       => $self->{'xmlHandler'},
		instance         => $self->{'instance'}
	);
	return;
}

sub db_connect {
	my ($self) = @_;
	my $att = {
		dbase_name => $self->{'system'}->{'db'},
		host       => $self->{'system'}->{'host'},
		port       => $self->{'system'}->{'port'},
		user       => $self->{'system'}->{'user'},
		password   => $self->{'system'}->{'password'}
	};
	try {
		$self->{'db'} = $self->{'dataConnector'}->get_connection($att);
	}
	catch {
		if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
			$logger->error("Cannot connect to database '$self->{'system'}->{'db'}'");
			$self->{'error'} = 'noConnect';
		} else {
			$logger->logdie($_);
		}
	};
	return;
}

#Override in subclasses
sub print_page              { }
sub app_specific_initiation { }

sub is_user_allowed_access {
	my ( $self, $username ) = @_;
	my %valid_user_type = map { $_ => 1 } qw(user submitter curator admin);
	if ( ( $self->{'system'}->{'curators_only'} // q() ) eq 'yes' ) {
		my $status = $self->{'datastore'}->run_query( 'SELECT status FROM users WHERE user_name=?', $username );
		return if !$status || $status eq 'user' || !$valid_user_type{$status};
		return if $status eq 'submitter' && !$self->{'curate'};
	}
	return 1 if !$self->{'system'}->{'default_access'};
	if ( $self->{'system'}->{'default_access'} eq 'deny' ) {
		my $users_allow_file = "$self->{'dbase_config_dir'}/$self->{'instance'}/users.allow";
		return 1 if -e $users_allow_file && $self->_is_name_in_file( $username, $users_allow_file );
		my $group_allow_file = "$self->{'dbase_config_dir'}/$self->{'instance'}/usergroups.allow";
		return 1 if -e $group_allow_file && $self->_is_user_in_group_file( $username, $group_allow_file );
		return;
	} elsif ( $self->{'system'}->{'default_access'} eq 'allow' ) {
		my $deny_file = "$self->{'dbase_config_dir'}/$self->{'instance'}/users.deny";
		return if -e $deny_file && $self->_is_name_in_file( $username, $deny_file );
		return 1;
	}
	return;
}

sub _is_name_in_file {
	my ( $self, $name, $filename ) = @_;
	BIGSdb::Exception::File::NotExist->throw("File $filename does not exist") if !-e $filename;
	open( my $fh, '<', $filename ) || $logger->error("Can't open $filename for reading");
	while ( my $line = <$fh> ) {
		next if $line =~ /^\#/x;
		$line =~ s/^\s+//x;
		$line =~ s/\s+$//x;
		if ( $line eq $name ) {
			close $fh;
			return 1;
		}
	}
	close $fh;
	return;
}

sub _is_user_in_group_file {
	my ( $self, $name, $filename ) = @_;
	BIGSdb::Exception::File::NotExist->throw("File $filename does not exist") if !-e $filename;
	my $group_names = [];
	open( my $fh, '<', $filename ) || $logger->error("Can't open $filename for reading");
	while ( my $line = <$fh> ) {
		next if $line =~ /^\#/x;
		$line =~ s/^\s+//x;
		$line =~ s/\s+$//x;
		push @$group_names, $line;
	}
	close $fh;
	my $list_table = $self->{'datastore'}->create_temp_list_table_from_array( 'text', $group_names );
	my $user_info = $self->{'datastore'}->get_user_info_from_username($name);
	return if !$user_info;
	return $self->{'datastore'}->run_query(
		'SELECT EXISTS(SELECT * FROM user_groups g JOIN user_group_members m ON g.id=m.user_group WHERE '
		  . "g.description IN (SELECT value FROM $list_table) AND m.user_id=?)",
		$user_info->{'id'}
	);
}

sub initiate_plugins {
	my ($self) = @_;
	$self->{'pluginManager'} = BIGSdb::PluginManager->new(
		system           => $self->{'system'},
		dbase_config_dir => $self->{'dbase_config_dir'},
		config_dir       => $self->{'config_dir'},
		lib_dir          => $self->{'lib_dir'},
		cgi              => $self->{'cgi'},
		instance         => $self->{'instance'},
		prefstore        => $self->{'prefstore'},
		config           => $self->{'config'},
		datastore        => $self->{'datastore'},
		db               => $self->{'db'},
		xmlHandler       => $self->{'xmlHandler'},
		dataConnector    => $self->{'dataConnector'},
		mod_perl_request => $self->{'mod_perl_request'},
		jobManager       => $self->{'jobManager'},
		contigManager    => $self->{'contigManager'},
		pluginDir        => $self->{'lib_dir'},
		curate           => $self->{'curate'}
	);
	return;
}

sub get_load_average {
	if ( -e '/proc/loadavg' ) {    #Faster to read from /proc/loadavg if available.
		my $loadavg;
		open( my $fh, '<', '/proc/loadavg' ) or croak 'Cannot open /proc/loadavg';
		while (<$fh>) {
			($loadavg) = split /\s/x, $_;
		}
		close $fh;
		return $loadavg;
	}
	my $uptime = `uptime`;         #/proc/loadavg not available on BSD.
	if ( $uptime =~ /load\ average:\s+([\d\.]+)/x ) {
		return $1;
	}
	BIGSdb::Exception::Data->throw('Cannot determine load average');
	return;
}
1;
