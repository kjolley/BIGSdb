#!/usr/bin/env perl
#Synchronize user database users with details from client databases
#Written by Keith Jolley
#Copyright (c) 2016-2019, University of Oxford
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
#
#Version: 20190830
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
use BIGSdb::Constants qw(:accounts LOG_TO_SCREEN);
use List::MoreUtils qw(uniq);
use Getopt::Long qw(:config no_ignore_case);
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
die "Script initialization failed.\n" if !defined $script->{'db'};
my $is_user_db =
  $script->{'datastore'}
  ->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', 'registered_users' );
die "This script can only be run against a user database.\n"
  if !$is_user_db;
main();
undef $script;

sub main {
	add_new_available_resources();
	remove_unavailable_resources();
	update_available_resources();
	add_registered_users();
	remove_unregistered_users();
	set_auto_registration();
	remove_deleted_users();
	check_invalid_users();
	remove_inactive_accounts();

	#TODO Automatic registration of paired databases
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
		if ( !$possible{$config} || !uses_this_user_db($config) ) {
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

sub update_available_resources {
	my $available_configs = get_available_configs();
	my @list;
	foreach my $config (@$available_configs) {
		my $system        = read_config_xml($config);
		my $config_values = $script->{'datastore'}->run_query( 'SELECT * FROM available_resources WHERE dbase_config=?',
			$config, { fetch => 'row_hashref', cache => 'get_available_config' } );
		if ( $system->{'description'} ne $config_values->{'description'} ) {
			eval {
				$script->{'db'}->do( 'UPDATE available_resources SET description=? WHERE dbase_config=?',
					undef, $system->{'description'}, $config );
			};
			if (@$) {
				$script->{'logger'}->error($@);
				$script->{'db'}->rollback;
			} else {
				push @list, { config => $config, description => $system->{'description'} };
				$script->{'db'}->commit;
			}
		}
	}
	if (@list) {
		local $" = qq(\t\n);
		say heading('Updating resource descriptions');
		foreach my $item (@list) {
			say qq($item->{'config'}: $item->{'description'});
		}
	}
	return;
}

sub uses_this_user_db {
	my ($config) = @_;
	my $system   = read_config_xml($config);
	my $db       = get_db($system);
	my $user_dbnames =
	  $script->{'datastore'}
	  ->run_query( 'SELECT DISTINCT(dbase_name) FROM user_dbases', undef, { fetch => 'col_arrayref', db => $db } );
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

	#Read system.override file
	my $override_file = "$script->{'dbase_config_dir'}/$config/system.overrides";
	if ( -e $override_file ) {
		open( my $fh, '<', $override_file )
		  || $logger->error("Can't open $override_file for reading");
		while ( my $line = <$fh> ) {
			next if $line =~ /^\#/x;
			$line =~ s/^\s+//x;
			$line =~ s/\s+$//x;
			if ( $line =~ /^([^=\s]+)\s*=\s*"([^"]+)"$/x ) {
				$system->{$1} = $2;
			}
		}
		close $fh;
	}
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

sub add_available_resource {
	my ($config) = @_;
	my $system = read_config_xml($config);
	eval {
		$script->{'db'}->do( 'INSERT INTO available_resources (dbase_config,dbase_name,description) VALUES (?,?,?)',
			undef, $config, $system->{'db'}, $system->{'description'} );
	};
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

sub add_registered_users {
	my $registered_configs = get_registered_configs();
	my @list;
	foreach my $config (@$registered_configs) {
		my $system = read_config_xml($config);
		my $db     = get_db($system);
		my $user_db_id =
		  $script->{'datastore'}
		  ->run_query( 'SELECT id FROM user_dbases WHERE dbase_name=?', $script->{'system'}->{'db'}, { db => $db } );
		if ( defined $user_db_id ) {
			my $user_names = $script->{'datastore'}->run_query(
				q(SELECT user_name FROM users WHERE user_db=? AND user_name NOT LIKE 'REMOVED_USER%' ORDER BY surname),
				$user_db_id,
				{ fetch => 'col_arrayref', db => $db }
			);
			foreach my $user_name (@$user_names) {
				next if is_user_registered_for_resource( $config, $user_name );
				push @list, { config => $config, user_name => $user_name };
			}
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
		my $user_db_id =
		  $script->{'datastore'}
		  ->run_query( 'SELECT id FROM user_dbases WHERE dbase_name=?', $script->{'system'}->{'db'}, { db => $db } );
		if ( defined $user_db_id ) {
			my $client_db_user_names =
			  $script->{'datastore'}->run_query( 'SELECT user_name FROM users WHERE user_db=? ORDER BY surname',
				$user_db_id, { fetch => 'col_arrayref', db => $db } );
			my %client_user_names = map { $_ => 1 } @$client_db_user_names;
			my $registered_users = get_registered_users($config);
			foreach my $registered_user (@$registered_users) {
				next if $client_user_names{$registered_user};
				push @list, { config => $config, user_name => $registered_user };
			}
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

sub set_auto_registration {
	my $available =
	  $script->{'datastore'}
	  ->run_query( 'SELECT * FROM available_resources', undef, { fetch => 'all_arrayref', slice => {} } );
	my @list;
	foreach my $available (@$available) {
		my $system   = read_config_xml( $available->{'dbase_config'} );
		my $db       = get_db($system);
		my $auto_reg = $script->{'datastore'}->run_query(
			'SELECT auto_registration FROM user_dbases WHERE dbase_name=?',
			$script->{'system'}->{'db'},
			{ db => $db }
		);
		$auto_reg = $auto_reg ? 'true' : 'false';
		$available->{'auto_registration'} = $available->{'auto_registration'} ? 'true' : 'false';
		if ( $available->{'auto_registration'} ne $auto_reg ) {
			push @list, { config => $available->{'dbase_config'}, auto_reg => $auto_reg };
		}
		drop_connection($system);
	}
	if ( @list && !$opts{'quiet'} ) {
		local $" = qq(\t\n);
		say heading('Updating auto-registration status');
		foreach my $item (@list) {
			say qq($item->{'config'}: $item->{'auto_reg'});
			eval {
				$script->{'db'}->do( 'UPDATE available_resources SET auto_registration=? WHERE dbase_config=?',
					undef, $item->{'auto_reg'}, $item->{'config'} );
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

#Populate invalid users with usernames used in other databases.
sub check_invalid_users {
	my $current_invalid =
	  $script->{'datastore'}
	  ->run_query( 'SELECT user_name FROM invalid_usernames', undef, { fetch => 'col_arrayref' } );
	my $users_in_this_db =
	  $script->{'datastore'}->run_query( 'SELECT user_name FROM users', undef, { fetch => 'col_arrayref' } );
	my %users_in_this_db = map { $_ => 1 } @$users_in_this_db;
	my %current_invalid  = map { $_ => 1 } @$current_invalid;
	my @usernames_from_databases;
	my $configs = get_dbase_configs();
	foreach my $config (@$configs) {
		my $system = read_config_xml($config);
		my $db     = get_db($system);
		my $user_names =
		  $script->{'datastore'}
		  ->run_query( 'SELECT user_name FROM users', undef, { fetch => 'col_arrayref', db => $db } );
		push @usernames_from_databases, @$user_names;
		drop_connection($system);
	}
	@usernames_from_databases = uniq sort @usernames_from_databases;
	my @filtered_list;
	eval {
		foreach my $user_name (@usernames_from_databases) {
			next if $users_in_this_db{$user_name};
			next if $current_invalid{$user_name};
			push @filtered_list, $user_name;
			$script->{'db'}->do( 'INSERT INTO invalid_usernames (user_name) VALUES (?)', undef, $user_name );
		}
	};
	if ($@) {
		$script->{'logger'}->error($@);
		$script->{'db'}->rollback;
	} else {
		if (@filtered_list) {
			local $" = qq(\t\n);
			say heading('Adding invalid users to list');
			foreach my $user_name (@filtered_list) {
				say $user_name;
			}
			$script->{'db'}->commit;
		}
	}
	my %usernames_in_dbases = map { $_ => 1 } @usernames_from_databases;
	my @to_remove;
	eval {
		foreach my $user_name (@$current_invalid) {
			next if $usernames_in_dbases{$user_name};
			push @to_remove, $user_name;
			$script->{'db'}->do( 'DELETE FROM invalid_usernames WHERE user_name=?', undef, $user_name );
		}
	};
	if ($@) {
		$script->{'logger'}->error($@);
		$script->{'db'}->rollback;
	} else {
		if (@to_remove) {
			local $" = qq(\t\n);
			say heading('Removing invalid users from list');
			foreach my $user_name (@to_remove) {
				say $user_name;
			}
			$script->{'db'}->commit;
		}
	}
	return;
}

sub remove_deleted_users {
	my $configs = get_registered_configs();
	my @deleted_users;
	foreach my $config (@$configs) {
		my $system = read_config_xml($config);
		my $db     = get_db($system);
		my $users =
		  $script->{'datastore'}->run_query( q(SELECT user_name FROM users WHERE user_name LIKE 'REMOVED_USER%'),
			undef, { db => $db, fetch => 'col_arrayref' } );
		eval {
			foreach my $user (@$users) {
				$db->do( 'DELETE FROM users WHERE user_name=?', undef, $user );
				push @deleted_users, { config => $config, username => $user };
			}
		};
		if ($@) {
			$logger->error($@);
			$db->rollback;
		} else {
			$db->commit;
		}
		drop_connection($system);
	}
	if ( @deleted_users && !$opts{'quiet'} ) {
		local $" = qq(\t\n);
		say heading('Removing deleted users');
		foreach my $item (@deleted_users) {
			say qq($item->{'config'}: $item->{'username'});
		}
	}
	return;
}

sub remove_inactive_accounts {
	my $configs = get_registered_configs();
	my $inactive_time =
	  BIGSdb::Utils::is_int( $script->{'config'}->{'inactive_account_removal_days'} )
	  ? $script->{'config'}->{'inactive_account_removal_days'}
	  : INACTIVE_ACCOUNT_REMOVAL_DAYS;
	$script->initiate_authdb;
	my @deleted_users;
	my $old_users = $script->{'datastore'}->run_query(
		qq(SELECT name FROM users WHERE dbase=? AND last_login<NOW()-INTERVAL '$inactive_time days'),
		$script->{'system'}->{'db'},
		{ fetch => 'col_arrayref', db => $script->{'auth_db'} }
	);
	my %old_user = map { $_ => 1 } @$old_users;
  CONFIG: foreach my $config (@$configs) {
		my $special_users = get_users_allow_deny($config);
		my %special_users = map { $_ => 1 } @$special_users;
		my $system        = read_config_xml($config);
		my $db            = get_db($system);
		my $user_db_id =
		  $script->{'datastore'}
		  ->run_query( 'SELECT id FROM user_dbases WHERE dbase_name=?', $script->{'system'}->{'db'}, { db => $db } );
		next CONFIG if !$user_db_id;
		my $users =
		  $script->{'datastore'}
		  ->run_query( q(SELECT id,user_name FROM users WHERE status='user' AND id>0 AND user_db=?),
			$user_db_id, { db => $db, fetch => 'all_arrayref', slice => {} } );
		my @curator_tables = $script->{'datastore'}->get_tables_with_curator( { dbtype => $system->{'dbtype'} } );
		my @sender_tables =
		  $system->{'dbtype'} eq 'isolates'
		  ? qw(isolates sequence_bin allele_designations)
		  : qw(sequences profiles);
	  USER: foreach my $user (@$users) {
			next if !$old_user{ $user->{'user_name'} };
			next if $special_users{ $user->{'user_name'} };
			my ( $is_sender, $is_curator );
		  TABLE: foreach my $table (@sender_tables) {
				if ( $script->{'datastore'}
					->run_query( "SELECT EXISTS(SELECT * FROM $table WHERE sender=?)", $user->{'id'}, { db => $db } ) )
				{
					$is_sender = 1;
					last TABLE;
				}
			}
			next USER if $is_sender;
		  TABLE: foreach my $table (@curator_tables) {
				if ( $script->{'datastore'}
					->run_query( "SELECT EXISTS(SELECT * FROM $table WHERE curator=?)", $user->{'id'}, { db => $db } ) )
				{
					$is_curator = 1;
					last TABLE;
				}
			}
			next USER if $is_curator;
			eval {
				$db->do( 'DELETE FROM users WHERE user_name=?', undef, $user->{'user_name'} );
				push @deleted_users, { config => $config, username => $user->{'user_name'} };
			};
			if ($@) {
				$db->rollback;
				$logger->error("Could not delete $user->{'user_name'} for $config. $@");
			} else {
				$db->commit;
			}
		}
		drop_connection($system);
	}
	if ( @deleted_users && !$opts{'quiet'} ) {
		local $" = qq(\t\n);
		say heading(qq(Removing users who haven't logged in for $inactive_time days));
		foreach my $item (@deleted_users) {
			say qq($item->{'config'}: $item->{'username'});
		}
	}
	return;
}

sub get_users_allow_deny {
	my ($config) = @_;
	my %names;
	my $configs = get_all_configs_using_same_database($config);
	foreach my $this_config (@$configs) {
		foreach my $allow_deny (qw(allow deny)) {
			my $filename = "$script->{'dbase_config_dir'}/$this_config/users.$allow_deny";
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

sub get_all_configs_using_same_database {
	my ($config) = @_;
	my $all_configs = get_dbase_configs( { include_symlinked => 1 } );
	state $configs_using_db = {};
	if ( !keys %$configs_using_db ) {
		foreach my $this_config (@$all_configs) {
			my $this_system = read_config_xml($this_config);
			push @{ $configs_using_db->{ $this_system->{'db'} } }, $this_config;
		}
	}
	my $system  = read_config_xml($config);
	my $db_name = $system->{'db'};
	return $configs_using_db->{$db_name} // [];
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
