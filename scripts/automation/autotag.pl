#!/usr/bin/perl -T
#Automatically tag scan genomes for exactly matching alleles
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
use BIGSdb::Offline::AutoTag;
my %opts;
GetOptions(
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
	'w|word_size=i'        => \$opts{'w'},
	'x|min=i'              => \$opts{'x'},
	'y|max=i'              => \$opts{'y'},
	'0|missing'            => \$opts{'0'},
	'h|help'               => \$opts{'h'},
	'n|new_only'           => \$opts{'n'},
	'o|order'              => \$opts{'o'},
	'q|quiet'              => \$opts{'q'},
	'r|random'             => \$opts{'r'},
	'T|already_tagged'     => \$opts{'T'}
) or die("Error in command line arguments\n");

if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( !$opts{'d'} ) {
	print "\nUsage: autotag.pl -d <database configuration>\n\n";
	print "Help: autotag.pl -h\n";
	exit;
}
BIGSdb::Offline::AutoTag->new(
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

Usage autotag.pl -d <database configuration>

Options
-------
-0                        Marks missing loci as provisional allele 0. Sets
--missing                 default word size to 15.
           
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
           
-q                        Only error messages displayed.
--quiet

-r                        Shuffle order of isolate ids to scan.
--random

-R <regex>                Regex for locus names
--locus_regex <regex>

-s <list>                 Comma-separated list of scheme loci to scan.
--schemes <list>

-t <mins>                 Stop after t minutes.
--time <mins>

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
