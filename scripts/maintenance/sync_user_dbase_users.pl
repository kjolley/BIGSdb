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
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;

#Direct all library logging calls to screen
my $log_conf =
    qq(log4perl.category.BIGSdb.Script        = INFO, Screen\n)
  . qq(log4perl.category.BIGSdb.Dataconnector = DEBUG, Screen\n)
  . qq(log4perl.category.BIGSdb.Datastore     = WARN, Screen\n)
  . qq(log4perl.appender.Screen               = Log::Log4perl::Appender::Screen\n)
  . qq(log4perl.appender.Screen.stderr        = 1\n)
  . qq(log4perl.appender.Screen.layout        = Log::Log4perl::Layout::SimpleLayout\n);
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
my %opts;
GetOptions( 'user_database=s' => \$opts{'user_database'}, 'help' => \$opts{'h'}, )
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
	my $configs = get_registered_configs();
	foreach my $config (@$configs) {
		my $system = read_config_xml($config);
		my $db     = get_db($system);
	}
	return;
}

sub get_registered_configs {
	return $script->{'datastore'}
	  ->run_query( 'SELECT dbase_config FROM resources ORDER BY dbase_config', undef, { fetch => 'col_arrayref' } );
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
	my $args = {
		dbase_name => $system->{'db'},
		host       => $system->{'host'} // $script->{'host'} // HOST,
		port       => $system->{'port'} // $script->{'port'} // PORT,
		user       => $system->{'user'} // $script->{'user'} // USER,
		password   => $system->{'password'} // $script->{'password'} // PASSWORD,
	};
	my $db = $script->{'dataConnector'}->get_connection($args);
	return $db;
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

${bold}--user_database$norm ${under}NAME$norm
    Database name (actual postgres name - user databases don't have config 
    names).
    
${bold}--help$norm
    This help page.
    
HELP
	return;
}
