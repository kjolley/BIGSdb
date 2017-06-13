#!/usr/bin/perl -T
#Scan genomes for new alleles
#Written by Keith Jolley
#Copyright (c) 2013-2017, University of Oxford
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
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
use Parallel::ForkManager;
use BIGSdb::Offline::ScanNew;
my %opts;
GetOptions(
	'A|alignment=i'        => \$opts{'A'},
	'B|identity=i'         => \$opts{'B'},
	'd|database=s'         => \$opts{'d'},
	'e|exemplar'           => \$opts{'exemplar'},
	'f|fast'               => \$opts{'fast'},
	'i|isolates=s'         => \$opts{'i'},
	'isolate_list_file=s'  => \$opts{'isolate_list_file'},
	'I|exclude_isolates=s' => \$opts{'I'},
	'l|loci=s'             => \$opts{'l'},
	'L|exclude_loci=s'     => \$opts{'L'},
	'm|min_size=i'         => \$opts{'m'},
	'p|projects=s'         => \$opts{'p'},
	'P|exclude_projects=s' => \$opts{'P'},
	'prefix=s'             => \$opts{'prefix'},
	'R|locus_regex=s'      => \$opts{'R'},
	's|schemes=s'          => \$opts{'s'},
	't|time=i'             => \$opts{'t'},
	'threads=i'            => \$opts{'threads'},
	'w|word_size=i'        => \$opts{'w'},
	'x|min=i'              => \$opts{'x'},
	'y|max=i'              => \$opts{'y'},
	'a|assign'             => \$opts{'a'},
	'allow_frameshift'     => \$opts{'allow_frameshift'},
	'c|coding_sequences'   => \$opts{'c'},
	'h|help'               => \$opts{'h'},
	'n|new_only'           => \$opts{'n'},
	'o|order'              => \$opts{'o'},
	'r|random'             => \$opts{'r'},
	'reuse_blast'          => \$opts{'reuse_blast'},
	'type_alleles'         => \$opts{'type_alleles'},
	'T|already_tagged'     => \$opts{'T'},
	'v|view=s'             => \$opts{'v'}
) or die("Error in command line arguments\n");
if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( !$opts{'d'} ) {
	say "\nUsage: scannew.pl -d <database configuration>\n";
	say 'Help: scannew.pl -h';
	exit;
}
if ( BIGSdb::Utils::is_int( $opts{'threads'} ) && $opts{'threads'} > 1 ) {
	my $script;
	$script = BIGSdb::Offline::ScanNew->new(    #Create script object to use methods to determine isolate list
		{
			config_dir       => CONFIG_DIR,
			lib_dir          => LIB_DIR,
			dbase_config_dir => DBASE_CONFIG_DIR,
			host             => HOST,
			port             => PORT,
			user             => USER,
			password         => PASSWORD,
			options          => { query_only => 1, %opts },
			instance         => $opts{'d'},
		}
	);
	local @SIG{qw (INT TERM HUP)} =
	  ( sub { $script->{'logger'}->info("$opts{'d'}:Autodefiner kill signal detected.  Waiting for child processes.") }
	  ) x 3;
	die "Script initialization failed - check logs (authentication problems or server too busy?).\n"
	  if !defined $script->{'db'};
	my $loci = $script->get_loci_with_ref_db;
	$script->{'db'}->commit;    #Prevent idle in transaction table locks
	my $lists = [];
	my $i     = 0;
	$opts{'prefix'} = BIGSdb::Utils::get_random();    #Reuse isolate file for each thread.
	foreach my $locus (@$loci) {
		push @{ $lists->[$i] }, $locus;
		$i++;
		if ( $i == $opts{'threads'} ) {
			$i = 0;
		}
	}
	delete $opts{$_} foreach qw(l L R s);             #Remove options that impact locus list
	$script->{'logger'}->info("$opts{'d'}:Running Autodefiner (up to $opts{'threads'} threads)");
	print_header();
	my $pm = Parallel::ForkManager->new( $opts{'threads'} );
	foreach my $list (@$lists) {
		$pm->start and next;                          #Forks
		local $" = ',';
		BIGSdb::Offline::ScanNew->new(
			{
				config_dir       => CONFIG_DIR,
				lib_dir          => LIB_DIR,
				dbase_config_dir => DBASE_CONFIG_DIR,
				host             => HOST,
				port             => PORT,
				user             => USER,
				password         => PASSWORD,
				options          => { l => "@$list", %opts },
				instance         => $opts{'d'},
			}
		);
		$pm->finish;    #Terminates child process
	}
	$pm->wait_all_children;
	$script->delete_temp_files("$script->{'config'}->{'secure_tmp_dir'}/*$opts{'prefix'}*");
	$script->{'logger'}->info("$opts{'d'}:All Autodefiner threads finished");
	exit;
}

#Run non-threaded job
print_header();
my $script = BIGSdb::Offline::ScanNew->new(
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

sub print_header {
	if ( !$opts{'a'} ) {
		say "locus\tallele_id\tstatus\tsequence\tflags";
	}
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
    ${bold}scannew.pl$norm - BIGSdb automated allele definer

${bold}SYNOPSIS$norm
    ${bold}scannew.pl --database$norm ${under}NAME$norm [${under}options$norm]

${bold}OPTIONS$norm
${bold}-a, --assign$norm
    Assign new alleles in definitions database.
    
${bold}--allow_frameshift$norm
    Allow sequences to contain a frameshift so that the length is not a 
    multiple of 3, or an internal stop codon. To be used with 
    --coding_sequences option to allow automated curation of pseudogenes.
    New alleles assigned will be flagged either 'frameshift' or 'internal stop
    codon' if appropriate.  Essentially, combining these two options only 
    checks that the sequence starts with a start codon and ends with a stop
    codon.    

${bold}-A, --alignment$norm ${under}INT$norm
    Percentage alignment (default: 100).

${bold}-B, --identity$norm ${under}INT$norm
    Percentage identity (default: 99).

${bold}-c, --coding_sequences$norm
    Only return complete coding sequences.

${bold}-d, --database$norm ${under}NAME$norm
    Database configuration name.
    
${bold}-e, --exemplar$norm
    Only use alleles with the 'exemplar' flag set in BLAST searches to identify
    locus within genome. Specific allele is then identified using a database 
    lookup. This may be quicker than using all alleles for the BLAST search, 
    but will be at the expense of sensitivity. If no exemplar alleles are set 
    for a locus then all alleles will be used. Sets default word size to 15.

${bold}-f --fast$norm
    Perform single BLAST query against all selected loci together. This will
    take longer to return any results but the overall scan should finish 
    quicker. This method will also use more memory - this can be used with
    --exemplar to mitigate against this.

${bold}-h, --help$norm
    This help page.

${bold}-i, --isolates$norm ${under}LIST$norm
    Comma-separated list of isolate ids to scan (ignored if -p used).
    
${bold}--isolate_list_file$norm ${under}FILE$norm  
    File containing list of isolate ids (ignored if -i or -p used).
           
${bold}-I, --exclude_isolates$norm ${under}LIST$norm
    Comma-separated list of isolate ids to ignore.

${bold}-l, --loci$norm ${under}LIST$norm
    Comma-separated list of loci to scan (ignored if -s used).

${bold}-L, --exclude_loci$norm ${under}LIST$norm
    Comma-separated list of loci to exclude.

${bold}-m, --min_size$norm ${under}SIZE$norm
    Minimum size of seqbin (bp) - limit search to isolates with at least this
    much sequence.
           
${bold}-n, --new_only$norm
    New (previously untagged) isolates only.

${bold}-o, --order$norm
    Order so that isolates last tagged the longest time ago get scanned first
    (ignored if -r used).
           
${bold}-p, --projects$norm ${under}LIST$norm
    Comma-separated list of project isolates to scan.

${bold}-P, --exclude_projects$norm ${under}LIST$norm
    Comma-separated list of projects whose isolates will be excluded.
           
${bold}-r, --random$norm
    Shuffle order of isolate ids to scan.
    
${bold}--reuse_blast$norm
    Reuse the BLAST database for every isolate (when running --fast option). 
    All loci will be scanned rather than just those missing from an isolate. 
    Consequently, this may be slower if isolates have already been scanned, 
    and for the first isolate scanned by a thread. On larger schemes, such as 
    wgMLST, or when isolates have not been previously scanned, setting up the
    BLAST database can take a significant amount of time, so this may be 
    quicker.

${bold}-R, --locus_regex$norm ${under}REGEX$norm
    Regex for locus names.

${bold}-s, --schemes$norm ${under}LIST$norm
    Comma-separated list of scheme loci to scan.

${bold}-t, --time$norm ${under}MINS$norm
    Stop after t minutes.

${bold}--threads$norm ${under}THREADS$norm
    Maximum number of threads to use.
    
${bold}--type_alleles$norm
    Only use alleles with the 'type_allele' flag set to identify locus.
    If a partial match is found then a full database lookup will be performed
    to identify any known alleles. Using this option will constrain the search
    space so that allele definitions don't become more variable over time. Note
    that you must have at least one allele defined as a type allele for a locus
    if you use this option otherwise you will not find any matches!

${bold}-T, --already_tagged$norm
    Scan even when sequence tagged (no designation).
    
${bold}-v, --view$norm ${under}VIEW$norm
    Isolate database view (overrides value set in config.xml).

${bold}-w, --word_size$norm ${under}SIZE$norm
    BLASTN word size.

${bold}-x, --min$norm ${under}ID$norm
    Minimum isolate id.

${bold}-y, --max$norm ${under}ID$norm
    Maximum isolate id.
HELP
	return;
}
