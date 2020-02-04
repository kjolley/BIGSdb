#!/usr/bin/env perl
#Add user to authentication database
#Written by Keith Jolley
#Copyright (c) 2010-2020, University of Oxford
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
#Version: 20200204
use strict;
use warnings;
use 5.010;
###########Local configuration#############################################
use constant {
	CONFIG_DIR => '/etc/bigsdb',
	LIB_DIR    => '/usr/local/lib',
};
#######End Local configuration#############################################
use lib (LIB_DIR);
use BIGSdb::Offline::Script;
use BIGSdb::Constants qw(LOG_TO_SCREEN);
use Digest::MD5;
use Getopt::Long qw(:config no_ignore_case);
use DBI;
use Carp;
use Crypt::Eksblowfish::Bcrypt qw(bcrypt_hash en_base64);
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
use POSIX;

#Direct all library logging calls to screen
my $log_conf = LOG_TO_SCREEN;
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
use constant BCRYPT_COST => 12;
my %opts;
GetOptions(
	'a|add'            => \$opts{'add'},
	'd|database=s'     => \$opts{'database'},
	'h|help'           => \$opts{'help'},
	'n|username=s'     => \$opts{'name'},
	'p|password=s'     => \$opts{'password'},
	'r|reset_password' => \$opts{'reset_password'}
) or die("Error in command line arguments\n");
if ( $opts{'help'} ) {
	show_help();
	exit;
}
if ( !$opts{'database'} || !$opts{'name'} || !$opts{'password'} ) {
	say 'Usage: add_user.pl [-a] --database <dbase> --username <username> --password <password>';
	say 'Use --add option to add a new user.';
	exit;
}
main();
exit;

sub main {
	my $script = BIGSdb::Offline::Script->new(
		{
			config_dir => CONFIG_DIR,
			lib_dir    => LIB_DIR,
			logger     => $logger
		}
	);
	my $user_dbase = $script->{'config'}->{'auth_db'} // 'bigsdb_auth';
	$script->initiate_authdb;
	my $db = $script->{'auth_db'};
	my $qry;
	my $password    = Digest::MD5::md5_hex( $opts{'password'} . $opts{'name'} );
	my $salt        = generate_salt();
	my $bcrypt_hash = en_base64( bcrypt_hash( { key_nul => 1, cost => BCRYPT_COST, salt => $salt }, $password ) );
	my @values      = ( $bcrypt_hash, 'bcrypt', BCRYPT_COST, $salt );
	my $reset       = $opts{'reset_password'} ? 'true' : undef;

	if ( $opts{'add'} ) {
		$qry = 'INSERT INTO users (password,algorithm,cost,salt,dbase,name,date_entered,datestamp,reset_password) '
		  . 'VALUES (?,?,?,?,?,?,?,?,?)';
		push @values, ( $opts{'database'}, $opts{'name'}, 'now', 'now', $reset );
	} else {
		$qry =
		    'UPDATE users SET (password,algorithm,cost,salt,datestamp,reset_password)=(?,?,?,?,?,?) '
		  . 'WHERE (dbase,name)=(?,?)';
		push @values, ( 'now', $reset, $opts{'database'}, $opts{'name'} );
	}
	my $sql = $db->prepare($qry);
	eval { $db->do( $qry, undef, @values ) };
	if ($@) {
		if ( $@ =~ /duplicate/ ) {
			say 'Username already exists.  Do not use the --add (-a) option to update.';
		} else {
			say $@;
		}
		$db->rollback;
	}
	$db->commit;
	undef $script;
	return;
}

sub generate_salt {
	my @saltchars = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9, '.', '/' );
	my $salt;
	for ( 1 .. 16 ) {
		$salt .= $saltchars[ int( rand($#saltchars) ) ];
	}
	return $salt;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw/me md us/;
	say << "HELP";
${bold}NAME$norm
    ${bold}add_user.pl$norm - Add user to authentication database 

${bold}SYNOPSIS$norm
    ${bold}add_user.pl ${bold}--database ${under}DATABASE$norm ${bold}--username ${under}NAME$norm ${bold}--password ${under}PASSWORD$norm ${norm}[${under}options$norm]

${bold}OPTIONS$norm

${bold}-a, --add$norm
    Add details to authentication database. Do not use if updating the password
    of an existing user.
    
${bold}-d, --database ${under}DATABASE$norm  
    Database name. If site-wide databases are being used, this may be the name
    of the users database.
    
${bold}-h, --help$norm
    This help page.
    
${bold}-n, --username ${under}USERNAME$norm  
    User name.
    
${bold}-p, --password ${under}PASSWORD$norm  
    Password.    

${bold}-r, --reset_password$norm
    Require that the user resets their password the next time they log in.    

HELP
	return;
}
