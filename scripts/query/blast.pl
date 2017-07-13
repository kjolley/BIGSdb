#!/usr/bin/perl
#BLAST query sequence against seqdef database
#Written by Keith Jolley
#Copyright (c) 2017, University of Oxford
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
###########Local configuration#############################################
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases',
	HOST             => undef,                  #Use values in config.xml
	PORT             => undef,                  #But you can override here.
	USER             => undef,
	PASSWORD         => undef
};
#######End Local configuration#############################################
use lib (LIB_DIR);
use BIGSdb::Offline::Blast;
use Error qw(:try);
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;

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
	'alignment=f'     => \$opts{'alignment'},
	'database=s'      => \$opts{'d'},
	'duration'        => \$opts{'duration'},
	'exclude_loci=s'  => \$opts{'L'},
	'exemplar'        => \$opts{'exemplar'},
	'help'            => \$opts{'h'},
	'identity=f'      => \$opts{'identity'},
	'loci=s'          => \$opts{'l'},
	'locus_regex=s'   => \$opts{'R'},
	'num_results=i'   => \$opts{'num_results'},
	'scheme_group=i'  => \$opts{'scheme_group'},
	'schemes=s'       => \$opts{'s'},
	'sequence=s'      => \$opts{'sequence'},
	'sequence_file=s' => \$opts{'sequence_file'},
	'threads=i'       => \$opts{'threads'},
	'word_size=i'     => \$opts{'word_size'}
) or die("Error in command line arguments\n");
if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( !$opts{'d'} || ( !$opts{'sequence'} && !$opts{'sequence_file'} ) ) {
	say "\nUsage: blast.pl --database <NAME> (--sequence <SEQ> OR --sequence_file <FILE>)\n";
	say 'Help: blast.pl --help';
	exit;
}
if ( $opts{'sequence_file'} && !-e $opts{'sequence_file'} ) {
	say "File $opts{'sequence_file'} does not exist.\n";
	exit;
}
my $start  = time;
my $blast_obj = BIGSdb::Offline::Blast->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		host             => HOST,
		port             => PORT,
		user             => USER,
		password         => PASSWORD,
		options          => { %opts, always_run => 1 },
		instance         => $opts{'d'},
	}
);
die "Script initialization failed.\n" if !defined $blast_obj->{'db'};
die "This script can only be run against a seqdef database.\n"
  if ( $blast_obj->{'system'}->{'dbtype'} // '' ) ne 'sequences';
main();
my $stop = time;
if ( $opts{'duration'} ) {
	my $duration = BIGSdb::Utils::get_nice_duration( $stop - $start );
	say "Duration: $duration";
}
undef $blast_obj;

sub main {
	my $seq;
	if ( $opts{'sequence_file'} ) {
		try {
			my $seq_ref = BIGSdb::Utils::slurp( $opts{'sequence_file'} );
			$seq = $$seq_ref;
		}
		catch BIGSdb::CannotOpenFileException with {
			$logger->error("Cannot open file $opts{'sequence_file'} for reading");
		};
	} else {
		$seq = $opts{'sequence'};
	}
	$blast_obj->blast( \$seq );
	my $exact_matches = $blast_obj->get_exact_matches;
	if ( keys %$exact_matches ) {
		foreach my $locus ( sort keys %$exact_matches ) {
			local $" = q(, );
			my $alleles = qq(@{$exact_matches->{$locus}});
			say qq($locus: $alleles);
		}
	}
	return;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw(me md us);
	say << "HELP";
${bold}NAME$norm
    ${bold}blast.pl$norm - BLAST query sequence against seqdef database 

${bold}SYNOPSIS$norm
    ${bold}blast.pl --database ${under}NAME$norm $bold--sequence ${under}SEQ$norm [${under}options$norm]

${bold}OPTIONS$norm

${bold}--alignment$norm ${under}ALIGNMENT$norm
    Percentage alignment (default: 50). Please note that if you are scanning
    using exemplars, then this is the initial match threshold to an exemplar
    allele.

${bold}--database$norm ${under}NAME$norm
    Database configuration name.

${bold}--duration$norm
    Display elapsed time.
    
${bold}--exclude_loci$norm ${under}LIST$norm
    Comma-separated list of loci to exclude
    
${bold}--exemplar$norm
    Only use alleles with the 'exemplar' flag set in BLAST searches to identify
    locus within genome. Specific allele is then identified using a database 
    lookup. This may be quicker than using all alleles for the BLAST search, 
    but will be at the expense of sensitivity. If no exemplar alleles are set 
    for a locus then all alleles will be used.
    
${bold}--help$norm
    This help page.

${bold}--identity$norm ${under}IDENTITY$norm
    Percentage identity (default: 90). Please note that if you are scanning
    using exemplars, then this is the initial match threshold to an exemplar
    allele.
    
${bold}--loci$norm ${under}LIST$norm
    Comma-separated list of loci to scan (ignored if -s used).

${bold}--locus_regex$norm ${under}REGEX$norm
    Regex for locus names.
    
${bold}--num_results$norm ${under}NUMBER$norm
    Maximum number of results.
    
${bold}--scheme_group$norm ${under}GROUP$norm
    Scheme group

${bold}--schemes$norm ${under}LIST$norm
    Comma-separated list of scheme loci to scan.
    
${bold}--sequence$norm ${under}SEQUENCE$norm
    DNA or peptide sequence.
    
${bold}--sequence_file$norm ${under}FILE$norm
    DNA or peptide sequence file.
    
${bold}--threads$norm ${under}THREADS$norm
    Maximum number of BLAST threads to use.
    
${bold}--word_size$norm ${under}SIZE$norm
    BLASTN word size.
    
HELP
	return;
}
