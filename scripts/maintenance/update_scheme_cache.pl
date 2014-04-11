#!/usr/bin/perl
#Create a scheme profile cache in an isolate database
#
#Written by Keith Jolley
#Copyright (c) 2011-2014, University of Oxford
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
use Getopt::Std;
use DBI;
use Carp;
my %opts;
getopts( 'd:x:i:y:', \%opts );

if ( !$opts{'d'} || !$opts{'x'} || !$opts{'i'} || !$opts{'y'} ) {
	say "\nUsage: update_scheme_cache.pl -d <definitions dbase> -x <scheme id (definitions)> -i <isolates dbase> -y "
	  . "<scheme id (isolates)> \n";
	exit;
}
my $db1 = DBI->connect( "DBI:Pg:dbname=$opts{'d'}", 'postgres', '', { AutoCommit => 0 } )
  or croak "couldn't open database";
my $db2 = DBI->connect( "DBI:Pg:dbname=$opts{'i'}", 'postgres', '', { AutoCommit => 0 } )
  or croak "couldn't open database";
my $sql = $db2->prepare("SELECT field,type,primary_key FROM scheme_fields WHERE scheme_id=? ORDER BY field_order");
$sql->execute( $opts{'y'} );
my ( @fields, %field_type );
my $pk;
while ( my ( $field, $type, $primary_key ) = $sql->fetchrow_array ) {
	push @fields, $field;
	$field_type{$field} = $type;
	if ($primary_key) {
		$pk = $field;
	}
}
$sql = $db2->prepare( "SELECT locus,allele_id_format,profile_name FROM scheme_members LEFT JOIN loci ON loci.id=scheme_members.locus "
	  . "WHERE scheme_id=? ORDER BY field_order" );
$sql->execute( $opts{'y'} );
my $scheme_sql = $db1->prepare("SELECT * FROM schemes WHERE id=?");
$scheme_sql->execute( $opts{'x'} );
my $scheme_info = $scheme_sql->fetchrow_hashref;
my ( @loci, %locus_type, %profile_name );
while ( my ( $locus, $type, $profile_name ) = $sql->fetchrow_array ) {
	push @loci, $locus;
	$locus_type{$locus} = $scheme_info->{'allow_missing_loci'} ? 'text' : $type;
	$profile_name{$locus} = $profile_name;
}
$db2->do("DROP TABLE IF EXISTS temp_scheme_$opts{'y'}");
my $qry   = "CREATE TABLE temp_scheme_$opts{'y'} (";
my $first = 1;
foreach (@fields) {
	$qry .= ', ' if !$first;
	$qry .= "$_ $field_type{$_}";
	$first = 0;
}
foreach (@loci) {
	( my $cleaned_locus = $_ ) =~ s/'/_PRIME_/g;
	$qry .= ', ' if !$first;
	$qry .= "$cleaned_locus $locus_type{$_}";
	$first = 0;
}
$qry .= ", PRIMARY KEY ($pk)" if $pk;
$qry .= ");";
$db2->do($qry);
if ( !@loci ) {
	say "No loci defined.";
	exit;
}
if ( !@fields ) {
	say "No fields defined.";
	exit;
}
local $" = ',';
my @profile_loci;
foreach (@loci) {
	s/'/_PRIME_/g;
	push @profile_loci, $profile_name{$_} || $_;
}
$sql = $db1->prepare("SELECT @fields,@profile_loci FROM scheme_$opts{'x'}");
$sql->execute;
my $field_string = "@fields,@loci";
while ( my @profile = $sql->fetchrow_array ) {
	for my $i ( 0 .. @profile - 1 ) {
		$profile[$i] = defined $profile[$i] ? "'$profile[$i]'" : 'null';
	}
	$db2->do("INSERT INTO temp_scheme_$opts{'y'} ($field_string) VALUES (@profile)");
}

#Index up to three profile fields - no need for more
my $i     = 0;
foreach my $locus (@loci) {
	$locus =~ s/'/_PRIME_/g;
	$i++;
	eval { $db2->do("CREATE INDEX i_ts_$opts{'y'}\_$locus ON temp_scheme_$opts{'y'} ($locus)") };
	last if $i == 3;
}
$db2->do("GRANT SELECT ON temp_scheme_$opts{'y'} TO apache,remote");
$db2->commit;
$sql->finish        if $sql;
$scheme_sql->finish if $scheme_sql;
$db1->disconnect;
$db2->disconnect;
