#!/usr/bin/perl
#Upgrade password hashes in authentication database to use bcrypt algorithm.
#Use to update md5 hashes.
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
use Crypt::Eksblowfish::Bcrypt qw(bcrypt_hash en_base64);
use constant DBASE       => 'bigsdb_auth';
use constant BCRYPT_COST => 12;
main();
exit;

sub main {
	my $db =
	     DBI->connect( 'DBI:Pg:dbname=' . DBASE, 'postgres', '', { 
	     	AutoCommit => 0, RaiseError => 1, PrintError => 0 } )
	  || croak 'could not open database';
	my $sql = $db->prepare('SELECT * FROM users WHERE algorithm IS NULL OR algorithm=?');
	eval { $sql->execute ('md5')};
	croak $@ if $@;
	my $sql2   = $db->prepare('UPDATE users SET (algorithm,cost,salt,password)=(?,?,?,?) WHERE (dbase,name)=(?,?)');
	my $header = "dbase\tname\tbcrypt_hash\tsalt";
	my $first  = 1;
	while ( my $data = $sql->fetchrow_hashref ) {
		my $salt = generate_salt();
		my $bcrypt_hash =
		  en_base64( bcrypt_hash( { key_nul => 1, cost => BCRYPT_COST, salt => $salt }, $data->{'password'} ) );
		eval { $sql2->execute( 'bcrypt', BCRYPT_COST, $salt, $bcrypt_hash, $data->{'dbase'}, $data->{'name'} ) };
		if ($@) {
			$db->rollback;
			croak $@;
		} else {
			$db->commit;
		}
		say $header if $first;
		say "$data->{'dbase'}\t$data->{'name'}\t$bcrypt_hash\t$salt";
		$first = 0;
	}
	$db->disconnect;
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
