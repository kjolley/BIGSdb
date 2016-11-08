#!/usr/bin/perl
#Synchronize user database users with details from client databases
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
use List::MoreUtils qw(uniq);
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;

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
GetOptions( 'quiet' => \$opts{'quiet'}, 'user_database=s' => \$opts{'user_database'}, 'help' => \$opts{'h'} )
  or die("Error in command line arguments\n");
if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( !$opts{'user_database'} ) {
	say "\nUsage: sync_user_dbase_users.pl --user_database <NAME>\n";
	say 'Help: sync_user_dbase_users.pl --help';
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
		options          => \%opts
	}
);
my $is_user_db =
  $script->{'datastore'}
  ->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', 'registered_users' );
die "This script can only be run against a user database.\n"
  if !$is_user_db;
main();

sub main {
	add_new_available_resources();
	remove_unavailable_resources();
	add_registered_users();
	remove_unregistered_users();
	return;
}

sub add_new_available_resources {
	my $available_configs  = get_available_configs();
	my %available          = map { $_ => 1 } @$available_configs;
	my $registered_configs = get_registered_configs();
	my %registered         = map { $_ => 1 } @$registered_configs;
	my $possible           = get_dbase_configs();
	my @list;
	foreach my $config (@$possible) {
		if ( !$available{$config} && !$registered{$config} ) {
			next if !uses_this_user_db($config);
			add_available_resource($config);
			push @list, $config;
		}
	}
	if ( @list && !$opts{'quiet'} ) {
		local $" = qq(\t\n);
		say heading('Adding new available resources');
		say qq(@list);
	}
	return;
}

sub remove_unavailable_resources {
	my $available_configs  = get_available_configs();
	my $registered_configs = get_registered_configs();
	my $possible_configs   = get_dbase_configs();
	my %possible           = map { $_ => 1 } @$possible_configs;
	my @list;
	foreach my $config ( uniq( @$available_configs, @$registered_configs ) ) {
		if ( !$possible{$config} ) {
			push @list, $config;
			remove_resource($config);
		}
	}
	if ( @list && !$opts{'quiet'} ) {
		local $" = qq(\t\n);
		say heading('Removing obsolete resources');
		say qq(@list);
	}
	return;
}

sub uses_this_user_db {
	my ($config) = @_;
	my $system   = read_config_xml($config);
	my $db       = get_db($system);
	return if _database_not_upgraded( $system, $db );    #TODO Remove
	my $user_dbnames =
	  $script->{'datastore'}
	  ->run_query( 'SELECT DISTINCT(dbase_name) FROM user_dbases', undef, { fetch => 'col_arrayref', db => $db } );

	#return if !@$user_dbnames;
	my $match;
	foreach my $user_dbname (@$user_dbnames) {

		#We can't rely on matching hostname as well so just matching database name will have to do.
		if ( $user_dbname eq $script->{'system'}->{'db'} ) {
			$match = 1;
			last;
		}
	}
	drop_connection($system);
	return $match;
}

sub heading {
	my ($heading) = @_;
	my $buffer = qq(\n$heading\t\n);    #Trailing tab to prevent Outlook removing line breaks
	$buffer .= q(-) x length($heading) . qq(\t);
	return $buffer;
}

sub get_available_configs {
	return $script->{'datastore'}->run_query( 'SELECT dbase_config FROM available_resources ORDER BY dbase_config',
		undef, { fetch => 'col_arrayref' } );
}

sub get_registered_configs {
	return $script->{'datastore'}->run_query( 'SELECT dbase_config FROM registered_resources ORDER BY dbase_config',
		undef, { fetch => 'col_arrayref' } );
}

sub get_registered_users {
	my ($config) = @_;
	return $script->{'datastore'}
	  ->run_query( 'SELECT user_name FROM registered_users WHERE dbase_config=? ORDER BY user_name',
		$config, { fetch => 'col_arrayref' } );
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
		host       => $system->{'host'} // $script->{'host'} // HOST,
		port       => $system->{'port'} // $script->{'port'} // PORT,
		user       => $system->{'user'} // $script->{'user'} // USER,
		password   => $system->{'password'} // $script->{'password'} // PASSWORD,
	};
	return $args;
}

sub get_dbase_configs {
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
		next if -l "$script->{'dbase_config_dir'}/$item/config.xml";
		push @configs, $item;
	}
	closedir($dh);
	return \@configs;
}

sub add_available_resource {
	my ($config) = @_;
	eval { $script->{'db'}->do( 'INSERT INTO available_resources (dbase_config) VALUES (?)', undef, $config ); };
	if (@$) {
		$script->{'logger'}->error($@);
		$script->{'db'}->rollback;
	} else {
		$script->{'db'}->commit;
	}
	return;
}

sub remove_resource {
	my ($config) = @_;
	eval {
		$script->{'db'}->do( 'DELETE FROM available_resources WHERE dbase_config=?',  undef, $config );
		$script->{'db'}->do( 'DELETE FROM registered_resources WHERE dbase_config=?', undef, $config );
	};
	if (@$) {
		$script->{'logger'}->error($@);
		$script->{'db'}->rollback;
	} else {
		$script->{'db'}->commit;
	}
	return;
}

#TODO This can be removed when all databases upgraded.
sub _database_not_upgraded {
	my ( $system, $db ) = @_;
	if (
		!$script->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)',
			'user_dbases', { db => $db }
		)
	  )
	{
		drop_connection($system);
		return 1;
	}
	return;
}

sub add_registered_users {
	my $registered_configs = get_registered_configs();
	my @list;
	foreach my $config (@$registered_configs) {
		my $system = read_config_xml($config);
		my $db     = get_db($system);
		return if _database_not_upgraded( $system, $db );    #TODO Remove
		my $user_db_id =
		  $script->{'datastore'}
		  ->run_query( 'SELECT id FROM user_dbases WHERE dbase_name=?', $script->{'system'}->{'db'}, { db => $db } );
		my $user_names =
		  $script->{'datastore'}->run_query( 'SELECT user_name FROM users WHERE user_db=? ORDER BY surname',
			$user_db_id, { fetch => 'col_arrayref', db => $db } );
		foreach my $user_name (@$user_names) {
			next if is_user_registered_for_resource( $config, $user_name );
			push @list, { config => $config, user_name => $user_name };
		}
		drop_connection($system);
	}
	if ( @list && !$opts{'quiet'} ) {
		local $" = qq(\t\n);
		say heading('Registering usernames');
		foreach my $reg (@list) {
			say qq($reg->{'config'}: $reg->{'user_name'});
			eval {
				$script->{'db'}->do( 'INSERT INTO registered_users (dbase_config,user_name,datestamp) VALUES (?,?,?)',
					undef, $reg->{'config'}, $reg->{'user_name'}, 'now' );
			};
			if (@$) {
				$script->{'logger'}->error($@);
				$script->{'db'}->rollback;
			} else {
				$script->{'db'}->commit;
			}
		}
	}
	return;
}

sub remove_unregistered_users {
	my $registered_configs = get_registered_configs();
	my @list;
	foreach my $config (@$registered_configs) {
		my $system = read_config_xml($config);
		my $db     = get_db($system);
		return if _database_not_upgraded( $system, $db );    #TODO Remove
		my $user_db_id =
		  $script->{'datastore'}
		  ->run_query( 'SELECT id FROM user_dbases WHERE dbase_name=?', $script->{'system'}->{'db'}, { db => $db } );
		my $client_db_user_names =
		  $script->{'datastore'}->run_query( 'SELECT user_name FROM users WHERE user_db=? ORDER BY surname',
			$user_db_id, { fetch => 'col_arrayref', db => $db } );
		my %client_user_names = map { $_ => 1 } @$client_db_user_names;
		my $registered_users = get_registered_users($config);
		foreach my $registered_user (@$registered_users) {
			next if $client_user_names{$registered_user};
			push @list, { config => $config, user_name => $registered_user };
		}
		drop_connection($system);
	}
	if ( @list && !$opts{'quiet'} ) {
		local $" = qq(\t\n);
		say heading('Removing unregistered usernames');
		foreach my $reg (@list) {
			say qq($reg->{'config'}: $reg->{'user_name'});
			eval {
				$script->{'db'}->do( 'DELETE FROM registered_users WHERE (dbase_config,user_name)=(?,?)',
					undef, $reg->{'config'}, $reg->{'user_name'} );
			};
			if (@$) {
				$script->{'logger'}->error($@);
				$script->{'db'}->rollback;
			} else {
				$script->{'db'}->commit;
			}
		}
	}
	return;
}

sub is_user_registered_for_resource {
	my ( $dbase_config, $user_name ) = @_;
	return $script->{'datastore'}->run_query(
		'SELECT EXISTS(SELECT * FROM registered_users WHERE (dbase_config,user_name)=(?,?))',
		[ $dbase_config, $user_name ],
		{ cache => 'is_user_registered_for_resource' }
	);
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw(me md us);
	say << "HELP";
${bold}NAME$norm
    ${bold}sync_user_dbase_users.pl$norm - Synchronize user database users with 
    details from client databases

${bold}SYNOPSIS$norm
    ${bold}sync_user_dbase_users.p --database ${under}NAME$norm [${under}options$norm]

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
