#!/usr/bin/perl -T
#bigscurate.pl
#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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

###########Local configuration###############################################
use constant {
	CONFIG_DIR => '/etc/bigsdb',     
	LIB_DIR    => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases',
};
#######End Local configuration###############################################

use CGI;
use DBI;
use XML::Parser::PerlSAX;
use Log::Log4perl qw(get_logger);    #Also need Log::Dispatch::File
use Error qw(:try);
use lib (LIB_DIR);
use BIGSdb::Application;
use BIGSdb::Curate;
use BIGSdb::Parser;
use BIGSdb::Dataconnector;
use BIGSdb::Datastore;
use BIGSdb::Utils;
use BIGSdb::Preferences;
use BIGSdb::Scheme;
use BIGSdb::Locus;
use BIGSdb::BIGSException;
use BIGSdb::Page;
use BIGSdb::IsolateInfoPage;
use BIGSdb::PubQueryPage;
use BIGSdb::SeqbinPage;
use BIGSdb::SeqbinToEMBL;
use BIGSdb::ExtractedSequencePage;
use BIGSdb::ErrorPage;
use BIGSdb::CuratePage;
use BIGSdb::CurateIndexPage;
use BIGSdb::CurateAddPage;
use BIGSdb::CurateDeletePage;
use BIGSdb::CurateDeleteAllPage;
use BIGSdb::CurateLinkToExperimentPage;
use BIGSdb::CurateUpdatePage;
use BIGSdb::CurateIsolateAddPage;
use BIGSdb::CurateIsolateDeletePage;
use BIGSdb::CurateBatchIsolateUpdatePage;
use BIGSdb::QueryPage;
use BIGSdb::BrowsePage;
use BIGSdb::ListQueryPage;
use BIGSdb::CurateIsolateUpdatePage;
use BIGSdb::CurateProfileAddPage;
use BIGSdb::CurateProfileUpdatePage;
use BIGSdb::CurateProfileBatchAddPage;
use BIGSdb::CuratePubmedQueryPage;
use BIGSdb::CurateBatchAddPage;
use BIGSdb::CurateBatchAddSeqbinPage;
use BIGSdb::CurateTableHeaderPage;
use BIGSdb::CurateCompositeQueryPage;
use BIGSdb::CurateCompositeUpdatePage;
use BIGSdb::CurateAlleleUpdatePage;
use BIGSdb::CurateTagScanPage;
use BIGSdb::CurateTagUpdatePage;
use BIGSdb::CurateDatabankScanPage;
use BIGSdb::CurateRenumber;
use BIGSdb::PluginManager;
use BIGSdb::ConfigCheckPage;
use BIGSdb::ConfigRepairPage;
use BIGSdb::LoginMD5;
use BIGSdb::ChangePasswordPage;
use BIGSdb::ProfileInfoPage;
use BIGSdb::AlleleInfoPage;
use BIGSdb::CurateIsolateACLPage;
use BIGSdb::ClientDB;
use BIGSdb::FieldHelpPage;
use BIGSdb::TableQueryPage;
use BIGSdb::DownloadSeqbinPage;
use BIGSdb::AlleleSequencePage;
use BIGSdb::OfflineJobManager;
use BIGSdb::OptionsPage;
use BIGSdb::CurateExportConfig;

my $r = shift;    #Apache request object (used for mod_perl)
Log::Log4perl->init_once(CONFIG_DIR . '/logging.conf');
BIGSdb::Curate->new( CONFIG_DIR, LIB_DIR,DBASE_CONFIG_DIR, $r,1 );


