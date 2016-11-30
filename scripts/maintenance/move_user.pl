#!/usr/bin/perl
#Move user account to remote user database
#Written by Keith Jolley
#Copyright (c) 2016, University of Oxford
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
	PASSWORD         => undef
};
#######End Local configuration#############################################
use lib (LIB_DIR);
use BIGSdb::Offline::Script;
use BIGSdb::BIGSException;
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
use Error qw(:try);
binmode( STDOUT, ':encoding(UTF-8)' );

#Direct all library logging calls to screen
my $log_conf =
    qq(log4perl.category.BIGSdb.Script        = INFO, Screen\n)
  . qq(log4perl.category.BIGSdb.Dataconnector = WARN, Screen\n)
  . qq(log4perl.category.BIGSdb.Datastore     = WARN, Screen\n)
  . qq(log4perl.appender.Screen               = Log::Log4perl::Appender::Screen\n)
  . qq(log4perl.appender.Screen.stderr        = 1\n)
  . qq(log4perl.appender.Screen.layout        = Log::Log4perl::Layout::SimpleLayout\n);
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
my %opts;
GetOptions(
	'database=s'      => \$opts{'d'},
	'user_name=s'     => \$opts{'user_name'},
	'user_database=s' => \$opts{'user_database'},
	'help'            => \$opts{'h'}
) or die("Error in command line arguments\n");
if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( !$opts{'user_database'} || !$opts{'d'} || !$opts{'user_name'} ) {
	say "\nUsage: move_user.pl --database <NAME> --username <NAME> --user_database <NAME>\n";
	say 'Help: move_user.pl --help';
	exit;
}
my $script;
my $busy;
$opts{'throw_busy_exception'} = 1;
try {
	$script = BIGSdb::Offline::Script->new(
		{
			config_dir       => CONFIG_DIR,
			lib_dir          => LIB_DIR,
			dbase_config_dir => DBASE_CONFIG_DIR,
			host             => HOST,
			port             => PORT,
			user             => USER,
			password         => PASSWORD,
			instance         => $opts{'d'},
			options          => \%opts,
		}
	);
}
catch BIGSdb::ServerBusyException with {
	$busy = 1;
};
die "Script initialization failed - server is too busy.\n" if $busy;
if (
	!$script->{'system'}->{'db'}
	|| (   $script->{'system'}->{'dbtype'} ne 'isolates'
		&& $script->{'system'}->{'dbtype'} ne 'sequences' )
  )
{
	say "$opts{'d'} is not a valid database configuration.\n";
	exit;
}
main();

sub main {
	$script->initiate_authdb;
	$script->{'datastore'}->initiate_userdbs;
	check_params();
	my $user_db_id =
	  $script->{'datastore'}->run_query( 'SELECT id FROM user_dbases WHERE dbase_name=?', $opts{'user_database'} );
	my $user_db   = $script->{'datastore'}->get_user_db($user_db_id);
	my $user_info = $script->{'datastore'}->get_user_info_from_username( $opts{'user_name'} );
	my $is_resource_registered =
	  $script->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM registered_resources WHERE dbase_config=?)',
		$opts{'d'}, { db => $user_db } );
	eval {
		$user_db->do(
			'INSERT INTO users (user_name,surname,first_name,email,affiliation,date_entered,datestamp,status) '
			  . 'VALUES (?,?,?,?,?,?,?,?)',
			undef, @{$user_info}{qw(user_name surname first_name email affiliation)}, 'now', 'now', 'validated'
		);

		if ($is_resource_registered) {
			$user_db->do( 'INSERT INTO registered_users (dbase_config,user_name,datestamp) VALUES (?,?,?)',
				undef, $opts{'d'}, $opts{'user_name'}, 'now' );
		}
		$script->{'db'}->do(
			'UPDATE users SET (surname,first_name,email,affiliation,user_db)=(null,null,null,null,?) WHERE user_name=?',
			undef, $user_db_id, $opts{'user_name'}
		);
		$script->{'auth_db'}->do(
			'UPDATE users SET (dbase,datestamp)=(?,?) WHERE (dbase,name)=(?,?)',
			undef, $opts{'user_database'}, 'now', $script->{'system'}->{'db'},
			$opts{'user_name'}
		);
	};
	if ($@) {
		$user_db->rollback;
		$script->{'db'}->rollback;
		$script->{'auth_db'}->rollback;
		die "$@\n";
	}
	$user_db->commit;
	$script->{'db'}->commit;
	$script->{'auth_db'}->commit;
	$script->{'dataConnector'}->drop_all_connections;
	return;
}

sub check_params {
	my $user_dbs = $script->{'datastore'}->get_user_dbs;
	my $user_db_exists;
	foreach my $user_db (@$user_dbs) {
		if ( $user_db->{'name'} eq $opts{'user_database'} ) {
			$user_db_exists = 1;
			last;
		}
	}
	die "\nUser database $opts{'user_database'} does not exist!\n" if !$user_db_exists;
	my $user_info = $script->{'datastore'}->get_user_info_from_username( $opts{'user_name'} );
	die "\nUser $opts{'user_name'} does not exist!\n" if !$user_info;
	die "\nUser $opts{'user_name'} is already in a remote user database!\n" if ( $user_info->{'user_db'} );
	my $user_db_id =
	  $script->{'datastore'}->run_query( 'SELECT id FROM user_dbases WHERE dbase_name=?', $opts{'user_database'} );
	my $user_db = $script->{'datastore'}->get_user_db($user_db_id);
	my $remote_user =
	  $script->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM users WHERE user_name=?)', $opts{'user_name'}, { db => $user_db } );
	die "\nUser $opts{'user_name'} already exists in remote user database!\n" if $remote_user;
	die "\nAuthorization database is not available!\n" if !$script->{'auth_db'};
	return;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw(me md us);
	say << "HELP";
${bold}NAME$norm
    ${bold}move_user.pl$norm - Move user account to remote user database

${bold}SYNOPSIS$norm
    ${bold}move_user.pl --database ${under}NAME$norm ${bold}--user_name ${under}USERNAME$norm ${bold}--user_database ${under}NAME$norm

${bold}REQUIRED PARAMETERS$norm

${bold}--database$norm ${under}NAME$norm
    Database configuration name.  

${bold}--user_database$norm ${under}NAME$norm
    Name of user database.
    
${bold}--user_name$norm ${under}USERNAME$norm
    Username in local database users table.

${bold}OPTIONS$norm

${bold}--help$norm
    This help page.


HELP
	return;
}
