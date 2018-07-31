#!/usr/bin/env perl
#Offline Job Manager for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2011-2018, University of Oxford
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
#
#
#This script should be run frequently (perhaps every minute) as
#a CRON job.  If the load average of the server is too high (as
#defined in bigsdb.conf) or there is no job to process, the script
#will exit immediately.  Note that CRON does not like '.' in executable
#filenames, so either rename the script to 'bigsjobs' or create
#a symlink and call that from CRON.
use strict;
use warnings;
###########Local configuration################################
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases',
	HOST             => 'localhost',
	PORT             => 5432,
	USER             => 'bigsdb',
	PASSWORD         => 'bigsdb'
};
#######End Local configuration################################
use lib (LIB_DIR);
use Log::Log4perl qw(get_logger);
use BIGSdb::Offline::RunJobs;
Log::Log4perl->init_once( CONFIG_DIR . '/job_logging.conf' );
my $logger = get_logger('BIGSdb.Job');
BIGSdb::Offline::RunJobs->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		host             => HOST,
		port             => PORT,
		user             => USER,
		password         => PASSWORD,
		logger           => $logger
	}
);
