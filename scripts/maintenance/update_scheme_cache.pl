#!/usr/bin/perl
#Create a scheme profile cache in an isolate database
use Getopt::Std;
use DBI;
use strict;
use warnings;

my %opts;
getopts( 'd:x:i:y:', \%opts );

if ( !$opts{'d'} or !$opts{'x'} or !$opts{'i'} or !$opts{'y'}) {
	print "\nUsage: update_scheme_cache.pl -d <definitions dbase> -x <scheme id (definitions)> -i <isolates dbase> -y <scheme id (isolates)> \n\n";
	exit;
}

my $db1 = DBI->connect( "DBI:Pg:dbname=$opts{'d'}", 'postgres', '', { 'AutoCommit' => 0 } )
  or die "couldn't open database";
my $db2 = DBI->connect( "DBI:Pg:dbname=$opts{'i'}", 'postgres', '', { 'AutoCommit' => 0 } )
  or die "couldn't open database";
my $sql = $db2->prepare("SELECT field,type,primary_key FROM scheme_fields WHERE scheme_id=? ORDER BY field_order");
$sql->execute($opts{'y'});
my (@fields,%field_type);
my $pk;
while (my ($field,$type,$primary_key) = $sql->fetchrow_array){
	push @fields, $field;
	$field_type{$field} = $type;
	if ($primary_key){
		$pk = $field;
	}
}
$sql = $db2->prepare("SELECT locus,allele_id_format,profile_name FROM scheme_members LEFT JOIN loci ON loci.id=scheme_members.locus WHERE scheme_id=? ORDER BY field_order");
$sql->execute($opts{'y'});
my (@loci,%locus_type,%profile_name);
while (my ($locus, $type, $profile_name) = $sql->fetchrow_array){
	push @loci, $locus;
	$locus_type{$locus} = $type;
	$profile_name{$locus} = $profile_name;
}

$db2->do("DROP TABLE IF EXISTS temp_scheme_$opts{'y'}");
my $qry = "CREATE TABLE temp_scheme_$opts{'y'} (";
my $first = 1;
foreach (@fields){
	$qry .= ', ' if !$first; 
	$qry .= "$_ $field_type{$_}";
	$first = 0;
}
foreach (@loci){
	$qry .= ', ' if !$first; 
	$qry .= "$_ $locus_type{$_}";
	$first = 0;
}
$qry.= ", PRIMARY KEY ($pk)" if $pk;
$qry.= ");";

$db2->do($qry);


if (!@loci){
	print "No loci defined.\n";
	exit;
}
if (!@fields){
	print "No fields defined.\n";
	exit;
}
$"=',';
my @profile_loci;
foreach (@loci){
	push @profile_loci,$profile_name{$_} || $_;
}
$sql = $db1->prepare("SELECT @fields,@profile_loci FROM scheme_$opts{'x'}");
$sql->execute;
my $field_string = "@fields,@loci";
$"=',';
while (my @profile = $sql->fetchrow_array){
	for (my $i=0; $i<@profile; $i++){
		$profile[$i] = defined  $profile[$i] ? "'$profile[$i]'" : 'null';
	}
	$db2->do("INSERT INTO temp_scheme_$opts{'y'} ($field_string) VALUES (@profile)");
}
#foreach (@fields){
#	if ($_ ne $pk){
#		$db2->do("CREATE INDEX i_ts$opts{'y'}_$_ ON temp_scheme_$opts{'y'} ($_)");
#	}
#}
$db2->do("CREATE INDEX i_ts$opts{'y'}_profile ON temp_scheme_$opts{'y'} (@loci)");
$db2->do("GRANT SELECT ON temp_scheme_$opts{'y'} TO apache,remote");
$db2->commit;


$sql->finish if $sql;
$db1->disconnect;
$db2->disconnect;
