#!/usr/bin/perl -T
#Scan genomes for new alleles
#Written by Keith Jolley
#Copyright (c) 2013, University of Oxford
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
use Getopt::Std;
use BIGSdb::Offline::ScanNew;
my %opts;
getopts( 'd:A:B:i:I:l:L:m:p:P:R:s:t:w:x:y:chnor', \%opts );

if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( !$opts{'d'} ) {
	say "\nUsage: scannew.pl -d <database configuration>\n";
	say "Help: scannew.pl -h";
	exit;
}
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
-d <name>  Database configuration name.
-A         Percentage alignment (default: 100)
-B         Percentage identity (default: 99)
-c         Only return complete coding sequences
-h         This help page.
-i <list>  Isolates - comma-separated list of isolate ids to scan (ignored if
           -p used).
-I <list>  Exclude isolates - comma-separated list of isolate ids to ignore.
-l <list>  Loci - comma-separated list of loci to scan (ignored if -s used).
-L <list>  Loci to exclude - comma-separated list of loci to exclude.
-m <size>  Minimum size of seqbin (bp) - limit search to isolates with at 
           least this much sequence.
-n         New (previously untagged) isolates only
-o         Order so that isolates last tagged the longest time ago get
           scanned first (ignored if -r used).
-p <list>  Projects - comma-separated list of project isolates to scan.
-P <list>  Exclude projects - comma-separated list of projects whose isolates
           will be excluded.
-r         Random - shuffle order of isolate ids to scan
-R         Regex for locus names
-s <list>  Schemes - comma-separated list of scheme loci to scan.
-t <mins>  Time limit - Stop after t minutes.
-w <size>  BLASTN word size
-x <id>    Minimum isolate id
-y <id>    Maximum isolate id
HELP
	return;
}
