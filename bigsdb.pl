#!/usr/bin/perl -T
#bigsdb.pl
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
package BIGSdb::main;
use strict;
use warnings;
use version; our $VERSION = qv('1.3.6');
use 5.010;

###########Local configuration################################
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases'
};
#######End Local configuration################################

use CGI;
use DBI;
use Log::Log4perl qw(get_logger);               #Also need Log::Dispatch::File
use Error qw(:try);
use lib (LIB_DIR);
use BIGSdb::Application;
use BIGSdb::Parser;
use BIGSdb::Utils;
use BIGSdb::Dataconnector;
use BIGSdb::Datastore;
use BIGSdb::Preferences;
use BIGSdb::Scheme;
use BIGSdb::Locus;
use BIGSdb::Page;
use BIGSdb::IndexPage;
use BIGSdb::ErrorPage;
use BIGSdb::BrowsePage;
use BIGSdb::IsolateInfoPage;
use BIGSdb::ProfileInfoPage;
use BIGSdb::VersionPage;
use BIGSdb::QueryPage;
use BIGSdb::TableQueryPage;
use BIGSdb::OptionsPage;
use BIGSdb::PubQueryPage;
use BIGSdb::ProfileQueryPage;
use BIGSdb::BatchProfileQueryPage;
use BIGSdb::DownloadAllelesPage;
use BIGSdb::DownloadProfilesPage;
use BIGSdb::DownloadSeqbinPage;
use BIGSdb::SeqbinPage;
use BIGSdb::ListQueryPage;
use BIGSdb::SequenceQueryPage;
use BIGSdb::CustomizePage;
use BIGSdb::RecordInfoPage;
use BIGSdb::BIGSException;
use BIGSdb::PluginManager;
use BIGSdb::Plugin;
use BIGSdb::SeqbinToEMBL;
use BIGSdb::AlleleSequencePage;
use BIGSdb::LoginMD5;
use BIGSdb::ChangePasswordPage;
use BIGSdb::AlleleInfoPage;
use BIGSdb::ClientDB;
use BIGSdb::FieldHelpPage;
use BIGSdb::ExtractedSequencePage;
use BIGSdb::AlleleQueryPage;
use BIGSdb::LocusInfoPage;
use BIGSdb::OfflineJobManager;
use BIGSdb::JobViewerPage;

my $r = shift;    #Apache request object (used for mod_perl)
Log::Log4perl->init_once( CONFIG_DIR . '/logging.conf' );
BIGSdb::Application->new( CONFIG_DIR, LIB_DIR, DBASE_CONFIG_DIR, $r );
