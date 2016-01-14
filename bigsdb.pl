#!/usr/bin/perl -T
#bigsdb.pl
#Written by Keith Jolley
#Copyright (c) 2010-2016, University of Oxford
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
package BIGSdb::main;
use strict;
use warnings;
use version; our $VERSION = qv('v1.12.2');
use 5.010;

###########Local configuration################################
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases'
};
#######End Local configuration################################

use Log::Log4perl qw(get_logger);               #Also need Log::Dispatch::File
use lib (LIB_DIR);
use BIGSdb::Application;
use BIGSdb::OfflineJobManager;

my $r = shift;    #Apache request object (used for mod_perl)
Log::Log4perl->init_once( CONFIG_DIR . '/logging.conf' );
BIGSdb::Application->new( CONFIG_DIR, LIB_DIR, DBASE_CONFIG_DIR, $r );
