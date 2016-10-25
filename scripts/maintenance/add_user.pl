#!/usr/bin/perl
#Add user to authentication database
#Written by Keith Jolley
#Copyright (c) 2010-2016, University of Oxford
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
use Digest::MD5;
use Getopt::Std;
use DBI;
use Carp;
use Crypt::Eksblowfish::Bcrypt qw(bcrypt_hash en_base64);
use constant DBASE       => 'bigsdb_auth';
use constant BCRYPT_COST => 12;
my %opts;
getopts( 'ad:n:p:', \%opts );

if ( !$opts{'d'} || !$opts{'n'} || !$opts{'n'} ) {
	say 'Usage: add_user.pl [-a] -d <dbase> -n <username> -p <password>';
	say 'Use -a option to add a new user.';
	exit;
}
main();
exit;

sub main {
	my $db =
	  DBI->connect( 'DBI:Pg:dbname=' . DBASE, 'postgres', '',
		{ AutoCommit => 0, RaiseError => 1, PrintError => 0 } )
	  || croak 'could not open database';
	my $qry;
	my $password    = Digest::MD5::md5_hex( $opts{'p'} . $opts{'n'} );
	my $salt        = generate_salt();
	my $bcrypt_hash = en_base64( bcrypt_hash( { key_nul => 1, cost => BCRYPT_COST, salt => $salt }, $password ) );
	my @values = ( $bcrypt_hash, 'bcrypt', BCRYPT_COST, $salt );
	if ( $opts{'a'} ) {
		$qry = 'INSERT INTO users (password,algorithm,cost,salt,dbase,name,date_entered,datestamp) '
		  . 'VALUES (?,?,?,?,?,?,?,?)';
		push @values, ($opts{'d'}, $opts{'n'}, 'now', 'now' );
	} else {
		$qry = 'UPDATE users SET (password,algorithm,cost,salt,datestamp)=(?,?,?,?,?) WHERE (dbase,name)=(?,?)';
		push @values, ( 'now', $opts{'d'}, $opts{'n'} );
	}
	my $sql         = $db->prepare($qry);

	eval { $db->do( $qry, undef, @values ) };
	if ($@) {
		if ( $@ =~ /duplicate/ ) {
			say 'Username already exists.  Do not use the -a option to update.';
		} else {
			say $@;
		}
		$db->rollback;
	}
	$db->commit;
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
