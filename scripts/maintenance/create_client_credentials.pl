#!/usr/bin/perl
#Populate authentication database with third party application (API client)
#credentials.
#Written by Keith Jolley
#Copyright (c) 2015, University of Oxford
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
	'd|deny'          => \$opts{'d'},
	'h|help'          => \$opts{'h'},
	'i|insert'        => \$opts{'i'},
	'u|update'        => \$opts{'u'},
	'v|version=s'     => \$opts{'v'}
) or die("Error in command line arguments\n");

if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( !$opts{'a'} ) {
	say "\nUsage: create_client_credentials.pl --application <NAME>\n";
	say "Help: create_client_credentials.pl --help";
	exit;
}
if ( $opts{'i'} && $opts{'u'} ) {
	die "--update and --insert options are mutually exclusive!\n";
}
$opts{'v'} //= '';
main();
exit;

sub main {
	my $client_id = random_string(24);
	my $client_secret = random_string( 42, { extended_chars => 1 } );
	say "Application: $opts{'a'}";
	say "Version: $opts{'v'}";
	say "Client id: $client_id";
	say "Client secret: $client_secret";
	if ( $opts{'i'} || $opts{'u'} ) {
		my $db = DBI->connect( "DBI:Pg:dbname=" . DBASE, 'postgres', '', { AutoCommit => 0, RaiseError => 1, PrintError => 0 } )
		  || croak "couldn't open database";
		my $sql = $db->prepare("SELECT EXISTS(SELECT * FROM clients WHERE (application,version)=(?,?))");
		eval { $sql->execute( $opts{'a'}, $opts{'v'} ) };
		my $exists = $sql->fetchrow_array;
		die $@ if $@;
		my $permission = $opts{'d'} ? 'deny' : 'allow';
		if ( $opts{'i'} && $exists ) {
			say "\nCredentials for this application/version already exist\n(use --update option to update).";
		} elsif ( $opts{'u'} && !$exists ) {
			say "\nCredentials for this application/version do not already exist\n(use --insert option to add).";
		} elsif ( $opts{'i'} ) {
			eval {
				$db->do(
					"INSERT INTO clients (application,version,client_id,client_secret,default_permission,datestamp) VALUES "
					  . "(?,?,?,?,?,?)",
					undef, $opts{'a'}, $opts{'v'}, $client_id, $client_secret, $permission, 'now'
				);
			};
			if ($@) {
				$db->rollback;
				die $@;
			}
			$db->commit;
			say "\nCredentials added to authentication database.";
		} elsif ( $opts{'u'} ) {
			eval {
				$db->do(
					"UPDATE clients SET (client_id,client_secret,default_permission,datestamp)=(?,?,?,?) WHERE (application,version)=(?,?)"
					,
					undef, $client_id, $client_secret, $permission, 'now', $opts{'a'}, $opts{'v'}
				);
			};
			if ($@) {
				$db->rollback;
				die $@;
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
    
${bold}-d, --deny$norm
    Set default permission to 'deny'.  Permissions for access to specific 
    database configurations will have to be set.  If not included, the default
    permission will allow access to all resources by the client.
    
${bold}-h, --help$norm
    This help page.
    
${bold}-i, --insert$norm
    Add credentials to authentication database.  This will fail if a matching
    application version already exists (use --update in this case to overwrite
    existing credentials).
    
${bold}-u, --update$norm
    Update exisitng credentials in the authentication database.
    
${bold}-v, --version ${under}VERSION$norm  
    Version of application (optional).
HELP
	return;
}
