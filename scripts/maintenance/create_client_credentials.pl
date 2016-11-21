#!/usr/bin/perl
#Populate authentication database with third party application (API client)
#credentials.
#Written by Keith Jolley
#Copyright (c) 2015-2016, University of Oxford
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
use DBI;
use Carp;
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
use POSIX;
use constant DBASE => 'bigsdb_auth';
my %opts;
GetOptions(
	'a|application=s' => \$opts{'a'},
	'c|curate'        => \$opts{'c'},
	'h|help'          => \$opts{'h'},
	'i|insert'        => \$opts{'i'},
	'p|permission=s'  => \$opts{'permission'},
	's|submit'        => \$opts{'s'},
	'u|update'        => \$opts{'u'},
	'U|dbuser=s'      => \$opts{'dbuser'},
	'P|dbpass=s'      => \$opts{'dbpass'},
	'H|dbhost=s'      => \$opts{'dbhost'},
	'N|dbport=i'      => \$opts{'dbport'},
	'v|version=s'     => \$opts{'v'}
) or die("Error in command line arguments\n");
if ( $opts{'permission'} && $opts{'permission'} ne 'allow' && $opts{'permission'} ne 'deny' ) {
	die("Allowed permissions are 'allow' or 'deny'.\n");
}
if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( !$opts{'a'} ) {
	say "\nUsage: create_client_credentials.pl --application <NAME>\n";
	say 'Help: create_client_credentials.pl --help';
	exit;
}
if ( $opts{'i'} && $opts{'u'} ) {
	die "--update and --insert options are mutually exclusive!\n";
}
$opts{'v'}      //= '';
$opts{'dbuser'} //= 'postgres';
$opts{'dbpass'} //= '';
main();
exit;

sub main {
	my $client_id = random_string(24);
	my $client_secret = random_string( 42, { extended_chars => 1 } );
	say "Application: $opts{'a'}";
	say "Version: $opts{'v'}";
	if ( !$opts{'u'} ) {
		say "Client id: $client_id";
		say "Client secret: $client_secret";
	}
	if ( $opts{'i'} || $opts{'u'} ) {
		my $db;
		my $db_name = DBASE;
		if ( $opts{'dbhost'} || $opts{'dbport'} ) {
			$opts{'dbhost'} //= 'localhost';
			$opts{'dbport'} //= 5432;
			$db = DBI->connect( "DBI:Pg:dbname=$db_name;host=$opts{'dbhost'};port=$opts{'dbport'}",
				$opts{'dbuser'}, $opts{'dbpass'}, { AutoCommit => 0, RaiseError => 1, PrintError => 0 } )
			  || croak q(couldn't open database);
		} else {    #No host/port - use UNIX domain sockets
			$db =
			  DBI->connect( "DBI:Pg:dbname=$db_name",
				$opts{'dbuser'}, $opts{'dbpass'}, { AutoCommit => 0, RaiseError => 1, PrintError => 0 } )
			  || croak q(couldn't open database);
		}
		my $sql = $db->prepare('SELECT EXISTS(SELECT * FROM clients WHERE (application,version)=(?,?))');
		eval { $sql->execute( $opts{'a'}, $opts{'v'} ) };
		my $exists = $sql->fetchrow_array;
		croak $@ if $@;
		$opts{'permission'} //= 'allow';
		if ( $opts{'i'} && $exists ) {
			$sql->finish;
			$db->disconnect;
			die "\nCredentials for this application/version already exist\n(use --update option to update).\n";
		}
		if ( $opts{'u'} && !$exists ) {
			$sql->finish;
			$db->disconnect;
			die "\nCredentials for this application/version do not already exist\n(use --insert option to add).\n";
		}
		if ( $opts{'i'} ) {
			eval {
				$db->do(
					'INSERT INTO clients (application,version,client_id,client_secret,default_permission,'
					  . 'default_submission,default_curation,datestamp) VALUES (?,?,?,?,?,?,?,?)',
					undef,
					$opts{'a'},
					$opts{'v'},
					$client_id,
					$client_secret,
					$opts{'permission'},
					$opts{'s'} ? 'true' : 'false',
					$opts{'c'} ? 'true' : 'false',
					'now'
				);
			};
			if ($@) {
				$db->rollback;
				croak $@;
			}
			$db->commit;
			say "\nCredentials added to authentication database.";
		} elsif ( $opts{'u'} ) {
			$sql = $db->prepare('SELECT client_id,client_secret FROM clients WHERE (application,version)=(?,?)');
			eval { $sql->execute( $opts{'a'}, $opts{'v'} ) };
			if ($@) {
				$db->rollback;
				croak $@;
			}
			( $client_id, $client_secret ) = $sql->fetchrow_array;
			say "Client id: $client_id";
			say "Client secret: $client_secret";
			eval {
				$db->do(
					'UPDATE clients SET (default_permission,default_submission,'
					  . 'default_curation,datestamp)=(?,?,?,?) WHERE (application,version)=(?,?)',
					undef,
					$opts{'permission'},
					$opts{'s'} ? 'true' : 'false',
					$opts{'c'} ? 'true' : 'false',
					'now',
					$opts{'a'},
					$opts{'v'}
				);
			};
			if ($@) {
				$db->rollback;
				croak $@;
			}
			$db->commit;
			say "\nCredentials updated in authentication database.";
		}
		$sql->finish;
		$db->disconnect;
	}
	return;
}

sub random_string {
	my ( $length, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my @chars = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9 );
	push @chars, qw(! @ $ % ^ & * \( \)_+ ~) if $options->{'extended_chars'};
	my $string;
	for ( 1 .. $length ) {
		$string .= $chars[ int( rand($#chars) ) ];
	}
	return $string;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw/me md us/;
	say << "HELP";
${bold}NAME$norm
    ${bold}create_client_credentials.pl$norm - Generate and populate 
    authentication database with third party application (API client) 
    credentials.

${bold}SYNOPSIS$norm
    ${bold}create_client_credentials.pl ${bold}--application ${under}NAME$norm ${norm}[${under}options$norm]

${bold}OPTIONS$norm
${bold}-a, --application ${under}NAME$norm  
    Name of application.
    
${bold}-c, --curate$norm
    Set to allow curation by default. The default condition is to not allow.
  
${bold}-h, --help$norm
    This help page.
    
${bold}-i, --insert$norm
    Add credentials to authentication database. This will fail if a matching
    application version already exists (use --update in this case to overwrite
    existing credentials).
   
${bold}-p, --permission$norm
    Set default permission (default is 'allow'). Allowed values are 'allow' 
    or 'deny'.
    
${bold}-s, --submit$norm
    Set to allow submission by default. The default condition is to not allow.
    
${bold}-u, --update$norm
    Update exisitng credentials in the authentication database.
    
${bold}-v, --version ${under}VERSION$norm  
    Version of application (optional).

${bold}DATABASE CONNECTION OPTIONS$norm

${bold}-U, --dbuser$norm
   Database user used to connect to database server [DEFAULT 'postgres'].

${bold}-P, --dbpass$norm
   Database user password used to connect to database server.

${bold}-H, --dbhost$norm
   Database server hostname [DEFAULT 'localhost' if port set]. If neither 
   dbhost or dbport are set then UNIX domain sockets will be used for the 
   connection.

${bold}-N, --dbport$norm
   Database server port connection number [DEFAULT 5432 if host set].
HELP
	return;
}
