#!/usr/bin/perl
#Add user to authentication database
use Digest::MD5;
use Getopt::Std;
use DBI;
use strict;
use warnings;

my $dbase = 'bigsdb_auth';
my %opts;
getopts( 'ad:n:p:', \%opts );

if ( !$opts{'d'} or !$opts{'n'} or !$opts{'n'} ) {
	print "\nusage: add_user.pl [-a] -d <dbase> -n <username> -p <password>\n\n";
	exit;
}
my $db = DBI->connect( "DBI:Pg:dbname=$dbase", 'postgres', '', { 'AutoCommit' => 0, 'RaiseError' => 1, 'PrintError' => 0 } )
  or die "couldn't open database";
my $qry;
if ( $opts{'a'} ) {
	$qry = "INSERT INTO users (password,name,dbase) VALUES (?,?,?)";
} else {
	$qry = "UPDATE users SET password=? WHERE name=? AND dbase=?";
}
my $sql = $db->prepare($qry) or die "Can't prepare";
my $password = Digest::MD5::md5_hex( $opts{'p'} . $opts{'n'} );
eval { $sql->execute( $password, $opts{'n'}, $opts{'d'} ); };
if ($@) {
	if ( $@ =~ /duplicate/ ) {
		print "\nUsername already exists.  Don't use the -a option to update.\n";
	} else {
		print $@;
	}
	$db->rollback;
}
$db->commit;
