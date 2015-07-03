#!/usr/bin/perl
#Upload contigs to isolate records
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
###########Local configuration################################
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases',
	HOST             => 'localhost',
	PORT             => 5432,
	USER             => 'apache',
	PASSWORD         => ''
};
#######End Local configuration################################
use lib (LIB_DIR);
use BIGSdb::Offline::Script;
use BIGSdb::Utils;
use BIGSdb::Page qw(SEQ_METHODS);
use Error qw(:try);
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
use POSIX;
use Carp;
use List::MoreUtils qw(notall none);
use Log::Log4perl qw(get_logger);

#Direct all library logging calls to screen
my $log_conf =
    qq(log4perl.category.BIGSdb.Script        = INFO, Screen\n)
  . qq(log4perl.category.BIGSdb.Dataconnector = WARN, Screen\n)
  . qq(log4perl.category.BIGSdb.Datastore     = WARN, Screen\n)
  . qq(log4perl.appender.Screen               = Log::Log4perl::Appender::Screen\n)
  . qq(log4perl.appender.Screen.stderr        = 1\n)
  . qq(log4perl.appender.Screen.layout        = Log::Log4perl::Layout::SimpleLayout\n);
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
my %opts;
GetOptions(
	'a|append'     => \$opts{'a'},
	'c|curator=i'  => \$opts{'c'},
	'd|database=s' => \$opts{'d'},
	'f|file=s'     => \$opts{'f'},
	'i|isolate=i'  => \$opts{'i'},
	'h|help'       => \$opts{'h'},
	'm|method=s'   => \$opts{'m'},
	'min_length=i' => \$opts{'min_length'},
	's|sender=i'   => \$opts{'s'},
) or die("Error in command line arguments\n");
if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( notall { $opts{$_} } (qw(c d f i s)) ) {
	say "\nUsage: upload_contigs.pl --database <NAME> --isolate <ID> --file <FILE> --sender <ID> --curator <ID>\n";
	say 'Help: upload_contigs.pl --help';
	exit;
}
my $script = BIGSdb::Offline::Script->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		host             => HOST,
		port             => PORT,
		user             => USER,
		password         => PASSWORD,
		options          => \%opts,
		instance         => $opts{'d'},
	}
);

#Check arguments make sense
exit_cleanly("Contig file '$opts{'f'}' does not exist.") if !-e $opts{'f'};
exit_cleanly("Contig file '$opts{'f'}' is empty.")       if !-s $opts{'f'};
my $isolate_exists =
  $script->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM isolates WHERE id=?)', $opts{'i'} );
exit_cleanly("Isolate id-$opts{'i'} does not exist.") if !$isolate_exists;
my $seqbin_exists =
  $script->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM seqbin_stats WHERE isolate_id=?)', $opts{'i'} );
exit_cleanly("Isolate id-$opts{'i'} already has contigs uploaded.") if $seqbin_exists && !$opts{'a'};
my $sender_exists = $script->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM users WHERE id=?)', $opts{'s'} );
exit_cleanly("Sender id-$opts{'s'} does not exist.") if !$sender_exists;
my $curator_exists =
  $script->{'datastore'}
  ->run_query( q(SELECT EXISTS(SELECT * FROM users WHERE id=? AND status IN ('curator','admin'))), $opts{'c'} );
exit_cleanly("Curator id-$opts{'c'} does not exist (or user is not a curator).") if !$curator_exists;
$opts{'m'} //= 'unknown';
exit_cleanly("Method '$opts{'m'}' is invalid.") if none { $opts{'m'} eq $_ } SEQ_METHODS;
main();
$script->db_disconnect;
exit;

sub main {

	#Read FASTA
	my $fasta_ref;
	if ( -e $opts{'f'} ) {
		$fasta_ref = BIGSdb::Utils::slurp( $opts{'f'} );
	}
	my $seqs;
	try {
		$seqs = BIGSdb::Utils::read_fasta($fasta_ref);
	}
	catch BIGSdb::DataException with {
		my $err = shift;
		exit_cleanly($err);
	};
	upload( $opts{'i'}, $seqs );
	return;
}

sub exit_cleanly {
	my ($msg) = @_;
	$script->db_disconnect;
	die "$msg\n";
}

sub upload {
	my ( $isolate_id, $seqs ) = @_;
	my $total_length = 0;
	my $contig_count = 0;
	my $sql =
	  $script->{'db'}
	  ->prepare( 'INSERT INTO sequence_bin (isolate_id,sequence,method,original_designation,sender,curator,'
		  . 'date_entered,datestamp) VALUES (?,?,?,?,?,?,?,?)' );
	eval {
		foreach my $key ( keys %$seqs )
		{
			next if $opts{'min_length'} && length $seqs->{$key} < $opts{'min_length'};
			$sql->execute( $isolate_id, $seqs->{$key}, $opts{'m'}, $key, $opts{'s'}, $opts{'c'}, 'now', 'now' );
			$total_length += length( $seqs->{$key} );
			$contig_count++;
		}
	};
	if ($@) {
		$script->{'db'}->rollback;
		croak $@;
	}
	say "Isolate $isolate_id: $contig_count contigs uploaded ($total_length bp).";
	$script->{'db'}->commit;
	return;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw/me md us/;
	say << "HELP";
${bold}NAME$norm
    ${bold}upload_contigs.pl$norm - Upload contigs to BIGSdb isolate database

${bold}SYNOPSIS$norm
    ${bold}upload_contigs.pl --database ${under}NAME$norm ${bold}--isolate ${under}ID${norm} ${bold}--file ${under}FILE$norm 
          ${bold}--curator ${under}ID$norm ${bold}--sender ${under}ID$norm [${under}options$norm]

${bold}OPTIONS$norm
${bold}-a, --append$norm
    Upload contigs even if isolate already has sequences in the bin.
    
${bold}-c, --curator$norm ${under}ID$norm  
    Curator id number. 
    
${bold}-d, --database$norm ${under}NAME$norm
    Database configuration name.
    
${bold}-f, --file$norm ${under}FILE$norm
    Full path and filename of contig file.

${bold}-h, --help$norm
    This help page.

${bold}-i, --isolate$norm ${under}ID$norm  
    Isolate id of record to upload to.  
    
${bold}-m, --method$norm ${under}METHOD$norm  
    Method, e.g. 'Illumina', default 'unknown'.
    
${bold}--min_length$norm ${under}LENGTH$norm
    Exclude contigs with length less than value.
    
${bold}-s, --sender$norm ${under}ID$norm  
    Sender id number.                
HELP
	return;
}
