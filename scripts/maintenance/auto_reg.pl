#!/usr/bin/env perl
#Automatically register site-wide user accounts with all
#databases that allow self-registration.
#Written by Keith Jolley
#Copyright (c) 2026, University of Oxford
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
#
#Version: 20260513
use strict;
use warnings;
use 5.010;
###########Local configuration#############################################
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases',
	HOST             => undef,
	PORT             => undef,
	USER             => undef,
	PASSWORD         => undef,
	LOCK_DIR         => '/var/run/lock'         #Override in bigsdb.conf
};
#######End Local configuration#############################################
use lib (LIB_DIR);
use BIGSdb::Offline::Script;
use BIGSdb::Constants qw(:accounts LOG_TO_SCREEN);
use List::MoreUtils   qw(uniq);
use Getopt::Long      qw(:config no_ignore_case);
use Term::Cap;
binmode( STDOUT, ':encoding(UTF-8)' );

#Direct all library logging calls to screen
my $log_conf = LOG_TO_SCREEN;
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
my %opts;
GetOptions( 'quiet' => \$opts{'quiet'}, 'user_database=s' => \$opts{'user_database'}, 'help' => \$opts{'h'} )
  or die("Error in command line arguments\n");
if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( !$opts{'user_database'} ) {
	say "\nUsage: auto_reg.pl --user_database <NAME>\n";
	say 'Help: auto_reg.pl --help';
	exit;
}
check_if_script_already_running();
my $script = BIGSdb::Offline::Script->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		host             => HOST,
		port             => PORT,
		user             => USER,
		password         => PASSWORD,
		options          => \%opts
	}
);
die "Script initialization failed.\n" if !defined $script->{'db'};
my $is_user_db =
  $script->{'datastore'}
  ->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', 'registered_users' );
die "This script can only be run against a user database.\n"
  if !$is_user_db;
main();
remove_lock_file();
undef $script;

sub main {
	my $configs    = get_registered_configs();
	my $site_users = $script->{'datastore'}
	  ->run_query( 'SELECT user_name FROM users ORDER BY user_name', undef, { fetch => 'col_arrayref' } );

	#TODO Optionally filter to only active users.
	#Check auth database and exclude users that did not register today, but where last_login=date_entered.

  CONFIG: foreach my $config (@$configs) {
		say $config;
		my $system = read_config_xml($config);
		my $db     = get_db($system);
		my $user_db_id =
		  $script->{'datastore'}
		  ->run_query( 'SELECT id FROM user_dbases WHERE dbase_name=?', $script->{'system'}->{'db'}, { db => $db } );

		if ( !defined $user_db_id ) {
			drop_connection($system);
			next CONFIG;
		}

		my $db_users = $script->{'datastore'}
		  ->run_query( 'SELECT user_name FROM users', undef, { fetch => 'col_arrayref', db => $db } );
		my %is_db_user = map { $_ => 1 } @$db_users;
	  USER: foreach my $site_user (@$site_users) {
			next USER                              if $is_db_user{$site_user};
			say "$config: Registering $site_user." if !$opts{'quiet'};
			my $id = next_user_id($db);

			eval {
				$db->do(
					'INSERT INTO users (id,user_name,status,date_entered,datestamp,curator,user_db) '
					  . 'VALUES (?,?,?,?,?,?,?)',
					undef, $id, $site_user, 'user', 'now', 'now', 0, $user_db_id
				);
				$script->{'db'}->do(
					'INSERT INTO registered_users (dbase_config,user_name,datestamp) VALUES (?,?,?) '
					  . 'ON CONFLICT(dbase_config,user_name) DO NOTHING',
					undef, $config, $site_user, 'now'
				);
			};
			if ($@) {
				$logger->error($@);
				$db->rollback;
				$script->{'db'}->rollback;
			} else {
				$db->commit;
				$script->{'db'}->commit;
			}

		}

		drop_connection($system);

	}
	return;
}

sub next_user_id {
	my ($db) = @_;

	#this will find next id except when id 1 is missing
	my $next = $script->{'datastore'}->run_query(
		'SELECT l.id + 1 AS start FROM users AS l LEFT OUTER JOIN users AS r ON l.id+1=r.id '
		  . 'WHERE r.id is null AND l.id > 0 ORDER BY l.id LIMIT 1',
		undef,
		{ db => $db }
	);
	$next = 1 if !$next;
	return $next;
}

sub get_db {
	my ($system) = @_;
	my $args = get_db_connection_args($system);
	my $db;
	eval { $db = $script->{'dataConnector'}->get_connection($args); };
	return $db;
}

sub drop_connection {
	my ($system) = @_;
	my $args = get_db_connection_args($system);
	$script->{'dataConnector'}->drop_connection($args);
	return;
}

sub get_db_connection_args {
	my ($system) = @_;
	my $args = {
		dbase_name => $system->{'db'},
		host       => $system->{'host'}     // $script->{'host'}     // HOST,
		port       => $system->{'port'}     // $script->{'port'}     // PORT,
		user       => $system->{'user'}     // $script->{'user'}     // USER,
		password   => $system->{'password'} // $script->{'password'} // PASSWORD,
	};
	return $args;
}

sub get_registered_configs {
	return $script->{'datastore'}
	  ->run_query( 'SELECT dbase_config FROM registered_resources WHERE auto_registration ORDER BY dbase_config',
		undef, { fetch => 'col_arrayref' } );
}

sub get_lock_file {
	my $config_dir = CONFIG_DIR;
	my $config     = Config::Tiny->read("$config_dir/bigsdb.conf");
	if ( !defined $config ) {
		$logger->fatal( 'Unable to read or parse bigsdb.conf file. Reason: ' . Config::Tiny->errstr );
		$config = Config::Tiny->new();
	}
	my $lock_dir  = $config->{_}->{'lock_dir'} // LOCK_DIR;
	my $lock_file = "$lock_dir/auto_reg";
	return $lock_file;
}

sub remove_lock_file {
	my $lock_file = get_lock_file();
	unlink $lock_file;
	return;
}

sub check_if_script_already_running {
	my $lock_file = get_lock_file();
	if ( -e $lock_file ) {
		open( my $fh, '<', $lock_file ) || $logger->error("Cannot open lock file $lock_file for reading");
		my $pid = <$fh>;
		close $fh;
		my $pid_exists = kill( 0, $pid );
		if ( !$pid_exists ) {
			say 'Lock file exists but process is no longer running - deleting lock.'
			  if !$opts{'quiet'};
			unlink $lock_file;
		} else {
			say 'Script already running with these parameters - terminating.' if !$opts{'quiet'};
			exit(1);
		}
	}
	open( my $fh, '>', $lock_file ) || $logger->error("Cannot open lock file $lock_file for writing");
	say $fh $$;
	close $fh;
	return;
}

sub read_config_xml {
	my ($config) = @_;
	if ( !$script->{'xmlHandler'} ) {
		$script->{'xmlHandler'} = BIGSdb::Parser->new;
	}
	my $parser = XML::Parser::PerlSAX->new( Handler => $script->{'xmlHandler'} );
	my $path   = "$script->{'dbase_config_dir'}/$config/config.xml";
	eval { $parser->parse( Source => { SystemId => $path } ) };
	if ($@) {
		$logger->fatal("Invalid XML description: $@");
		return;
	}
	my $system = $script->{'xmlHandler'}->get_system_hash;

	#Read system.override file
	my $override_file = "$script->{'dbase_config_dir'}/$config/system.overrides";
	if ( -e $override_file ) {
		open( my $fh, '<', $override_file )
		  || $logger->error("Can't open $override_file for reading");
		while ( my $line = <$fh> ) {
			next if $line =~ /^\#/x;
			$line         =~ s/^\s+//x;
			$line         =~ s/\s+$//x;
			if ( $line =~ /^([^=\s]+)\s*=\s*"([^"]+)"$/x ) {
				$system->{$1} = $2;
			}
		}
		close $fh;
	}
	return $system;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t      = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw(me md us);
	say << "HELP";
${bold}NAME$norm
    ${bold}auto_reg.pl$norm - Automatically register site-wide user accounts with all
    databases that allow self-registration.

${bold}SYNOPSIS$norm
    ${bold}auto_reg.pl --database ${under}NAME$norm [${under}options$norm]

${bold}OPTIONS$norm

${bold}--help$norm
    This help page.

${bold}--quiet$norm
    Only display error messages.

${bold}--user_database$norm ${under}NAME$norm
    Database name (actual postgres name - user databases don't have config 
    names).
        
HELP
	return;
}
