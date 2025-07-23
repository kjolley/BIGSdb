#!/usr/bin/env perl
#Update authentication database with third party application (API client)
#permissions.
#Written by Keith Jolley
#Copyright (c) 2025, University of Oxford
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
#Version: 20250721
use strict;
use warnings;
use 5.010;
use DBI;
use Carp;
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
use POSIX;
use constant DBASE      => 'bigsdb_auth';
use constant SUBMISSION => 'true';
use constant CURATION   => 'false';
binmode( STDOUT, ':encoding(UTF-8)' );
my %opts;

GetOptions(
	'allow_curation'         => \$opts{'allow_curation'},
	'allow_submissions'      => \$opts{'allow_submissions'},
	'c|clear'                => \$opts{'clear'},
	'clear_dbs=s'            => \$opts{'clear_dbs'},
	'dbuser=s'               => \$opts{'dbuser'},
	'dbpass=s'               => \$opts{'dbpass'},
	'dbhost=s'               => \$opts{'dbhost'},
	'dbport=i'               => \$opts{'dbport'},
	'f|filter=s'             => \$opts{'filter'},
	'h|help'                 => \$opts{'help'},
	'k|key=s'                => \$opts{'key'},
	'l|list'                 => \$opts{'list'},
	'p|permissions'          => \$opts{'permissions'},
	's|set_default_access=s' => \$opts{'set_default_access'},
	'set_dbs=s'              => \$opts{'set_dbs'},
	'set_db_access=s'        => \$opts{'set_db_access'},
	'set_db_curate=s'        => \$opts{'set_db_curate'},
	'set_db_submit=s'        => \$opts{'set_db_submit'},
) or die("Error in command line arguments\n");

$opts{'dbuser'} //= 'postgres';
$opts{'dbpass'} //= q();
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

main();

sub main {
	if ( $opts{'help'} ) {
		show_help();
		exit;
	}
	if ( $opts{'list'} ) {
		list_clients();
		exit;
	}
	if ( $opts{'permissions'} ) {
		list_permissions();
		exit;
	}
	if ( $opts{'set_default_access'} ) {
		set_default_access();
	}
	if ( $opts{'clear'} ) {
		clear_permissions();
	} elsif ( $opts{'clear_dbs'} ) {
		clear_db_permissions();
	}
	if ( $opts{'set_dbs'} ) {
		set_db_permissions('set_db_allow');
	}
	return;
}

sub list_clients {
	my $sql = $db->prepare('SELECT * FROM clients ORDER BY application,version');
	eval { $sql->execute };
	croak $@ if $@;
	say q(key) . ( q( ) x 22 ) . q(| application);
	say q(-) x 25 . q(+) . q(-) x 36;
	while ( my $record = $sql->fetchrow_hashref ) {
		$record->{'application'} .= qq( version $record->{'version'}) if $record->{'version'} ne q();
		$record->{'application'} .= q( )                              if $record->{'application'};
		$record->{'application'} .= qq([user: $record->{'username'}]) if $record->{'username'};
		## no critic(RequireExtendedFormatting)
		if ( $opts{'filter'} && $record->{'application'} !~ /$opts{'filter'}/i ) {
			next;
		}
		say qq($record->{'client_id'} | $record->{'application'});
	}
	return;
}

sub list_permissions {
	my $key = $opts{'key'};
	if ( !defined $key ) {
		say 'No key provided - include with --key attribute.';
		return;
	}
	my $sql = $db->prepare('SELECT * FROM clients WHERE client_id=?');
	eval { $sql->execute($key) };
	croak $@ if $@;
	my $client = $sql->fetchrow_hashref;
	if ( !$client ) {
		say 'Client does not exist.';
		return;
	}
	my $application = $client->{'application'};
	$application .= qq( version $client->{'version'}) if $client->{'version'} ne q();
	$application .= q( )                              if $client->{'application'};
	$application .= qq([user: $client->{'username'}]) if $client->{'username'};
	say $application;
	say qq(\nDefault permissions:);
	say qq(Access:       $client->{'default_permission'});
	my $deny_overridden = $client->{'default_permission'} eq 'deny' ? q( [overridden by default access]) : q();
	say q(Curation:     ) . ( $client->{'default_permission'} ? qq(allow$deny_overridden) : q(deny) );
	say q(Submission:   ) . ( $client->{'default_permission'} ? qq(allow$deny_overridden) : q(deny) );
	$sql = $db->prepare('SELECT * FROM client_permissions WHERE client_id=? ORDER BY authorize,dbase');
	eval { $sql->execute($key) };
	croak $@ if $@;
	my $permissions = $sql->fetchall_arrayref( {} );
	say qq(\nDatabase permissions:);

	if ( !@$permissions ) {
		say q(No explicit permissions/exclusions set.);
		return;
	}
	say q(Database) . q( ) x 50 . q(|) . ' Access | Curate | Submit';
	say q(-) x 58 . q(+) . q(--------+--------+-------);
	foreach my $permission (@$permissions) {
		my $dbase = $permission->{'dbase'};
		$dbase = substr( $permission->{'dbase'}, 0, 58 ) if length( $permission->{'dbase'} ) > 58;
		$dbase .= q( ) x ( 58 - length($dbase) ) if length($dbase) < 58;
		my $access = $permission->{'authorize'} eq 'allow' ? q( allow  ) : q(  deny  );
		my $curate = $permission->{'curation'}             ? q( allow  ) : q(  deny  );
		my $submit = $permission->{'submission'}           ? q( allow  ) : q(  deny  );
		say qq($dbase|$access|$curate|$submit);
	}
	return;
}

sub key_exists {
	my $key = $opts{'key'};
	my $sql = $db->prepare('SELECT EXISTS(SELECT * FROM clients WHERE client_id=?)');
	eval { $sql->execute($key) };
	croak $@ if $@;
	return $sql->fetchrow_array;
}

sub check_key {
	my $key = $opts{'key'};
	if ( !defined $key ) {
		say q(No key provided - include with --key attribute.);
		exit;
	}
	if ( !key_exists($key) ) {
		say q(Invalid client key - client does not exist.);
		exit;
	}
	return;
}

sub set_default_access {
	my $key     = $opts{'key'};
	my $default = $opts{'set_default_access'};
	check_key();
	my %allowed = map { $_ => 1 } qw(allow deny);
	if ( !$allowed{$default} ) {
		say q(Invalid default permission passed - can only be 'allow' or 'deny'.);
		exit;
	}
	eval {
		$db->do( 'UPDATE clients SET (default_permission,datestamp)=(?,?) WHERE client_id=?',
			undef, $default, 'now', $key );
		$db->commit;
	};
	croak $@ if $@;
	say qq(Default permission '$default' set.);
	return;
}

sub clear_permissions {
	my $key = $opts{'key'};
	check_key();
	eval {
		$db->do( 'DELETE FROM client_permissions WHERE client_id=?', undef, $key );
		$db->commit;
	};
	croak $@ if $@;
	say q(Explicit permissions cleared.);
	return;
}

sub clear_db_permissions {
	my $key = $opts{'key'};
	check_key();
	my @dbases = split /\s*,\s*/x, $opts{'clear_dbs'};
	my @results;
	eval {
		foreach my $dbase (@dbases) {
			$db->do( 'DELETE FROM client_permissions WHERE (client_id,dbase)=(?,?)', undef, $key, $dbase );
			push @results, qq(Permission for $dbase cleared.);
		}
		$db->commit;
	};
	croak $@ if $@;
	local $" = qq(\n);
	say qq(@results);
	return;
}

sub set_db_permissions {
	my ($permission) = @_;
	my $key = $opts{'key'};
	check_key();
	( my $value = $permission ) =~ s/set_db_//x;
	my @dbases     = split /\s*,\s*/x, $opts{$permission};
	my $submission = SUBMISSION;
	my $curation   = CURATION;

	my @results;
	eval {
		foreach my $dbase (@dbases) {
			$db->do(
				'INSERT INTO client_permissions (client_id,dbase,authorize,submission,curation) VALUES '
				  . '(?,?,?,?,?) ON CONFLICT(client_id,dbase) DO UPDATE SET '
				  . '(authorize,curation,submission)=(?,?,?)',
				undef, $key, $dbase, $value, $submission, $curation, $value, $submission, $curation
			);
			push @results,
			  qq(Permission set for $dbase: authorize: $value; submission: $submission; curation: $curation.);
		}
		$db->commit;
	};
	croak $@ if $@;
	local $" = qq(\n);
	say qq(@results);
	return;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t      = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw/me md us/;
	say << "HELP";
${bold}NAME$norm
    ${bold}create_client_credentials.pl$norm - Update authentication database 
    with permissions for third party applications (API clients) .

${bold}SYNOPSIS$norm
    ${bold}update_clients.pl$norm ${under}options$norm

${bold}OPTIONS$norm

${bold}--allow_curation$norm

${bold}--allow_submission$norm
    

${bold}-c, --clear$norm
    Clear explicit permissions (default permission is unchanged).
    
${bold}--clear_dbs$norm ${under}LIST$norm
    Comma-separated list of databases to clear permissions for.

${bold}-f, --filter$norm ${under}STRING$norm
    Only show keys for applications or users that contain the filter term.

${bold}-h, --help$norm
    This help page.
    
${bold}-k, --key$norm ${under}KEY$norm 
    
${bold}-l, --list$norm
    List clients and their keys. Combine with --filter to search list.
    
${bold}-p, --permissions$norm
    List permissions for application key.
    
${bold}-s, --set_dbs$norm ${under}LIST$norm
	Comma-separated list of databases to set permissions for.
	  
${bold}-s, --set_default_access$norm ${under}approve|deny$norm
    Set default permission for client
    
${bold}-s, --set_default_curate$norm ${under}approve|deny$norm
    Set default curation permission for client. Client curation is not
    currently supported but the permission can be set for future compatability.
  
${bold}-s, --set_default_submit$norm ${under}approve|deny$norm
    Set default submission permission for client
    
${bold}DATABASE CONNECTION OPTIONS$norm

${bold}--dbuser$norm ${under}USER$norm 
   Database user used to connect to database server [DEFAULT 'postgres'].

${bold}--dbpass$norm ${under}PASSWORD$norm
   Database user password used to connect to database server.

${bold}--dbhost$norm ${under}HOST$norm 
   Database server hostname [DEFAULT 'localhost' if port set]. If neither 
   dbhost or dbport are set then UNIX domain sockets will be used for the 
   connection.

${bold}--dbport$norm ${under}PORT$norm 
   Database server port connection number [DEFAULT 5432 if host set]. 
HELP
	return;
}

