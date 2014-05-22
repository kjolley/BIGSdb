#!/usr/bin/perl -T
#Scan genomes for new alleles
#Written by Keith Jolley
#Copyright (c) 2013-2014, University of Oxford
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
use Getopt::Long qw(:config no_ignore_case);
use POSIX;
use Parallel::ForkManager;
use BIGSdb::Offline::ScanNew;
my %opts;
GetOptions(
	'A|alignment=i'        => \$opts{'A'},
	'B|identity=i'         => \$opts{'B'},
	'd|database=s'         => \$opts{'d'},
	'i|isolates=s'         => \$opts{'i'},
	'I|exclude_isolates=s' => \$opts{'I'},
	'l|loci=s'             => \$opts{'l'},
	'L|exclude_loci=s'     => \$opts{'L'},
	'm|min_size=i'         => \$opts{'m'},
	'p|projects=s'         => \$opts{'p'},
	'P|exclude_projects=s' => \$opts{'P'},
	'R|locus_regex=s'      => \$opts{'R'},
	's|schemes=s'          => \$opts{'s'},
	't|time=i'             => \$opts{'t'},
	'threads=i'            => \$opts{'threads'},
	'w|word_size=i'        => \$opts{'w'},
	'x|min=i'              => \$opts{'x'},
	'y|max=i'              => \$opts{'y'},
	'a|assign'             => \$opts{'a'},
	'c|coding_sequences'   => \$opts{'c'},
	'h|help'               => \$opts{'h'},
	'n|new_only'           => \$opts{'n'},
	'o|order'              => \$opts{'o'},
	'r|random'             => \$opts{'r'},
	'T|already_tagged'     => \$opts{'T'}
) or die("Error in command line arguments\n");

if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( !$opts{'d'} ) {
	say "\nUsage: scannew.pl -d <database configuration>\n";
	say "Help: scannew.pl -h";
	exit;
}
if ( $opts{'threads'} && $opts{'threads'} > 1 ) {
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
	  ( sub { $script->{'logger'}->info("$opts{'d'}:Autodefiner kill signal detected.  Waiting for child processes.") } ) x 3;
	die "Script initialization failed - check logs (authentication problems or server too busy?).\n" if !defined $script->{'db'};
	my $loci = $script->get_loci_with_ref_db;
	$script->{'db'}->commit;    #Prevent idle in transaction table locks
	my $loci_per_list = floor( @$loci / $opts{'threads'} );
	$loci_per_list++ if @$loci % $opts{'threads'};
	my $lists = [];
	my $list  = 0;
	my $i     = 0;

	foreach my $locus (@$loci) {
		push @{ $lists->[$list] }, $locus;
		$i++;
		if ( $i == $loci_per_list ) {
			$list++;
			$i = 0;
		}
	}
	delete $opts{$_} foreach qw(l L R s);    #Remove options that impact locus list
	$script->{'logger'}->info("$opts{'d'}:Running Autodefiner (up to $opts{'threads'} threads)");
	my $pm = Parallel::ForkManager->new( $opts{'threads'} );
	$list = 0;
	$pm->run_on_start(
		sub {
			my ( $pid, $ident ) = @_;
			$list++;
		}
	);
	foreach my $list (@$lists) {
		$pm->start and next;                 #Forks
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
	$script->{'logger'}->info("$opts{'d'}:All Autodefiner threads finished");
	exit;
}

#Run non-threaded job
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

sub show_help {
	print << "HELP";

Usage scannew.pl -d <database configuration>

Options
-------
-a                        Assign new alleles in definitions database.
--assign

-A <int>                  Percentage alignment (default: 100).
--alignment

-B <int>                  Percentage identity (default: 99).
--identity

-c                        Only return complete coding sequences.
--coding_sequences

-d <name>                 Database configuration name.
--database	

-h                        This help page.
--help

-i <list>                 Comma-separated list of isolate ids to scan (ignored
--isolates <list>         if -p used).
           
-I <list>                 Comma-separated list of isolate ids to ignore.
--exclude_isolates <list>

-l <list>                 Comma-separated list of loci to scan (ignored if -s
--loci <list>             used).

-L <list>                 Comma-separated list of loci to exclude
--exclude_loci <list>

-m <size>                 Minimum size of seqbin (bp) - limit search to
--min_size <size>         isolates with at least this much sequence.
           
-n                        New (previously untagged) isolates only
--new_only

-o                        Order so that isolates last tagged the longest time
--order                   ago get scanned first (ignored if -r used).
           
-p <list>                 Comma-separated list of project isolates to scan.
--projects <list>

-P <list>                 Comma-separated list of projects whose isolates will
--exclude_projects        be excluded.
           
-r                        Shuffle order of isolate ids to scan.
--random

-R <regex>                Regex for locus names
--locus_regex <regex>

-s <list>                 Comma-separated list of scheme loci to scan.
--schemes <list>

-t <mins>                 Stop after t minutes.
--time <mins>

--threads <threads>       Maximum number of threads to use.

-T                        Scan even when sequence tagged (no designation).
--already_tagged

-w <size>                 BLASTN word size.
--word_size <size>

-x <id>                   Minimum isolate id.
--min <id>

-y <id>                   Maximum isolate id.
--max <id>

HELP
	return;
}
