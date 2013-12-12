#!/usr/bin/perl
#Add user to authentication database
use strict;
use warnings;
use 5.010;
use Digest::MD5;
use Getopt::Std;
use DBI;
my $dbase = 'bigsdb_auth';
my %opts;
getopts( 'ad:n:p:', \%opts );

if ( !$opts{'d'} || !$opts{'n'} || !$opts{'n'} ) {
	say "Usage: add_user.pl [-a] -d <dbase> -n <username> -p <password>";
	exit;
}
my $db = DBI->connect( "DBI:Pg:dbname=$dbase", 'postgres', '', { AutoCommit => 0, RaiseError => 1, PrintError => 0 } )
  || die "couldn't open database";    ## no critic (RequireCarping)
my $qry;
if ( $opts{'a'} ) {
	$qry = "INSERT INTO users (password,name,dbase) VALUES (?,?,?)";
} else {
	$qry = "UPDATE users SET password=? WHERE name=? AND dbase=?";
}
my $sql      = $db->prepare($qry);
my $password = Digest::MD5::md5_hex( $opts{'p'} . $opts{'n'} );
eval { $sql->execute( $password, $opts{'n'}, $opts{'d'} ); };
if ($@) {
	if ( $@ =~ /duplicate/ ) {
		say "Username already exists.  Don't use the -a option to update.";
	} else {
		say $@;
	}
	$db->rollback;
}
$db->commit;
