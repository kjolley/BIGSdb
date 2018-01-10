#!/usr/bin/perl
#List site-wide users not registered to any database and optionally remove
#them from users and authentication databases.
#Written by Keith Jolley
#Copyright (c) 2017-2018, University of Oxford
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
use BIGSdb::Constants qw(:accounts);
use List::MoreUtils qw(uniq);
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
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
	'days=i'          => \$opts{'days'},
	'user_database=s' => \$opts{'user_database'},
	'help'            => \$opts{'h'},
	'never_logged_in' => \$opts{'never_logged_in'},
	'remove'          => \$opts{'remove'}
) or die("Error in command line arguments\n");
if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( !$opts{'user_database'} ) {
	say "\nUsage: unregistered_users.pl --user_database <NAME>\n";
	say 'Help: unregistered_users.pl --help';
	exit;
}
my $script = BIGSdb::Offline::Script->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		host             => HOST,
		port             => PORT,
		user             => USER,
		password         => PASSWORD,
		options          => { %opts, always_run => 1 }
	}
);
die "Script initialization failed.\n" if !defined $script->{'db'};
my $is_user_db =
  $script->{'datastore'}
  ->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', 'registered_users' );
die "This script can only be run against a user database.\n"
  if !$is_user_db;
main();
undef $script;

sub main {
	my $usernames        = get_all_database_users();
	my %usernames        = map { $_ => 1 } @$usernames;
	my $registered_users = get_registered_users();
	my %registered_users = map { $_ => 1 } @$registered_users;
	my $special_users    = get_users_allow_deny();
	my %special_users    = map { $_ => 1 } @$special_users;
	my $inactive_time    = get_inactive_time();
	$script->initiate_authdb;
	my $qry = qq[SELECT name FROM users WHERE dbase=? AND (last_login<NOW()-INTERVAL '$inactive_time days'];

	if ( $opts{'never_logged_in'} ) {
		$qry .= q(OR last_login IS NULL);
	}
	$qry .= q[) ORDER BY name];
	my $old_users = $script->{'datastore'}
	  ->run_query( $qry, $script->{'system'}->{'db'}, { fetch => 'col_arrayref', db => $script->{'auth_db'} } );
	foreach my $name (@$old_users) {
		next
		  if $registered_users{$name};       #Probably not necessary as checking all users anyway - but doesn't hurt.
		next if $special_users{$name};
		next if $usernames{$name};
		print $name;
		if ( $opts{'remove'} ) {
			eval {
				$script->{'db'}->do( 'DELETE FROM users WHERE user_name=?', undef, $name );
				$script->{'auth_db'}
				  ->do( 'DELETE FROM users WHERE (dbase,name)=(?,?)', undef, $opts{'user_database'}, $name );
			};
			if ($@) {
				$script->{'db'}->rollback;
				$script->{'auth_db'}->rollback;
				say q( ...cannot remove!);
			} else {
				$script->{'db'}->commit;
				$script->{'auth_db'}->commit;
				say q( ...removed.);
			}
		} else {
			print qq(\n);
		}
	}
	return;
}

sub get_inactive_time {
	if ( BIGSdb::Utils::is_int( $opts{'days'} ) ) {
		return $opts{'days'};
	}
	return BIGSdb::Utils::is_int( $script->{'config'}->{'inactive_account_removal_days'} )
	  ? $script->{'config'}->{'inactive_account_removal_days'}
	  : INACTIVE_ACCOUNT_REMOVAL_DAYS;
}

sub get_registered_users {
	return $script->{'datastore'}
	  ->run_query( 'SELECT user_name FROM registered_users ORDER BY user_name', undef, { fetch => 'col_arrayref' } );
}

sub get_all_database_users {
	my $configs = get_dbase_configs();
	my @usernames;
	foreach my $config (@$configs) {
		my $system     = read_config_xml($config);
		my $db         = get_db($system);
		my $user_names = $script->{'datastore'}->run_query( 'SELECT user_name FROM users WHERE user_db IS NOT NULL',
			undef, { fetch => 'col_arrayref', db => $db } );
		push @usernames, @$user_names;
		drop_connection($system);
	}
	@usernames = uniq sort @usernames;
	return \@usernames;
}

sub get_users_allow_deny {
	my %names;
	my $configs = get_dbase_configs( { include_symlinked => 1 } );
	foreach my $config (@$configs) {
		foreach my $allow_deny (qw(allow deny)) {
			my $filename = "$script->{'dbase_config_dir'}/$config/users.$allow_deny";
			if ( -e $filename ) {
				open( my $fh, '<', $filename ) || $logger->error("Cannot open $filename for reading");
				while ( my $line = <$fh> ) {
					$line =~ s/[\s\r\n]//gx;
					$names{$line} = 1;
				}
				close $fh;
			}
		}
	}
	my @names = sort keys %names;
	return \@names;
}

sub read_config_xml {
	my ($config) = @_;
	if ( !$script->{'xmlHandler'} ) {
		$script->{'xmlHandler'} = BIGSdb::Parser->new;
	}
	my $parser = XML::Parser::PerlSAX->new( Handler => $script->{'xmlHandler'} );
	my $path = "$script->{'dbase_config_dir'}/$config/config.xml";
	eval { $parser->parse( Source => { SystemId => $path } ) };
	if ($@) {
		$logger->fatal("Invalid XML description: $@");
		return;
	}
	my $system = $script->{'xmlHandler'}->get_system_hash;
	return $system;
}

sub get_db {
	my ($system) = @_;
	my $args     = get_db_connection_args($system);
	my $db       = $script->{'dataConnector'}->get_connection($args);
	return $db;
}

sub get_db_connection_args {
	my ($system) = @_;
	my $args = {
		dbase_name => $system->{'db'},
		host       => $system->{'host'} // $script->{'host'} // HOST,
		port       => $system->{'port'} // $script->{'port'} // PORT,
		user       => $system->{'user'} // $script->{'user'} // USER,
		password   => $system->{'password'} // $script->{'password'} // PASSWORD,
	};
	return $args;
}

sub drop_connection {
	my ($system) = @_;
	my $args = get_db_connection_args($system);
	$script->{'dataConnector'}->drop_connection($args);
	return;
}

sub get_dbase_configs {
	my ($options) = @_;
	my @configs;
	opendir( my $dh, $script->{'dbase_config_dir'} )
	  || $logger->error("Cannot open $script->{'dbase_config_dir'} for reading");
	my @items = sort readdir $dh;
	foreach my $item (@items) {
		next if $item =~ /^\./x;
		next if !-d "$script->{'dbase_config_dir'}/$item";
		next if !-e "$script->{'dbase_config_dir'}/$item/config.xml";

		#Don't include configs with symlinked config.xml - these largely duplicate
		#other configs for specific projects.
		next if -l "$script->{'dbase_config_dir'}/$item/config.xml" && !$options->{'include_symlinked'};
		push @configs, $item;
	}
	closedir($dh);
	return \@configs;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw(me md us);
	say << "HELP";
${bold}NAME$norm
    ${bold}unregistered_users.pl$norm - List site-wide users not registered to
    any database.

${bold}SYNOPSIS$norm
    ${bold}unregistered_users.p --database ${under}NAME$norm [${under}options$norm]

${bold}OPTIONS$norm

${bold}--days$norm ${under}DAYS$norm
    Number of days that account has been inactive for.
    Default value is defined in /etc/bigsdb/bigsdb.conf.

${bold}--help$norm
    This help page.
    
${bold}--never_logged_in$norm
    Also include users who have never logged in.
    
${bold}--remove$norm
    Remove inactive users from both the users database and the authentication 
    database.

${bold}--user_database$norm ${under}NAME$norm
    Database name (actual postgres name - user databases don't have config 
    names).
        
HELP
	return;
}
