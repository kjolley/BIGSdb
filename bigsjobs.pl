#!/usr/bin/perl -T
#Offline Job Manager for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2011, University of Oxford
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

###########Local configuration################################
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases',
	HOST			 => 'localhost',
	PORT			 => 5432,
	USER			 => 'bigsdb',
	PASSWORD	 	 => 'bigsdb'
};
#######End Local configuration################################

use DBI;
use Log::Log4perl qw(get_logger);
use lib (LIB_DIR);
use BIGSdb::OfflineJobManager;
use BIGSdb::Dataconnector;
use BIGSdb::BIGSException;

Log::Log4perl->init_once( CONFIG_DIR . '/job_logging.conf' );
BIGSdb::OfflineJobManager->new( CONFIG_DIR, LIB_DIR, DBASE_CONFIG_DIR, HOST, PORT, USER, PASSWORD);