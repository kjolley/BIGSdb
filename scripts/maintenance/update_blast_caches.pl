#!/usr/bin/perl -T
#Update cached BLAST databases for a seqdef database
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
use constant { CONFIG_DIR => '/etc/bigsdb', LIB_DIR => '/usr/local/lib', DBASE_CONFIG_DIR => '/etc/bigsdb/dbases' };
#######End Local configuration################################
use lib (LIB_DIR);
use BIGSdb::Offline::UpdateBlastCaches;
use Getopt::Std;
my %opts;
getopts( 'd:q', \%opts );
if ( !$opts{'d'} ) {
	say 'Usage: update_cached_blast_dbs.pl -d <database configuration>';
	exit;
}
BIGSdb::Offline::UpdateBlastCaches->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		options          => \%opts,
		instance         => $opts{'d'},
	}
);
