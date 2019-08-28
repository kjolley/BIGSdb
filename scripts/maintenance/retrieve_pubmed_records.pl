#!/usr/bin/env perl
#Retrieve PubMed records for a database
#Written by Keith Jolley
#Copyright (c) 2019, University of Oxford
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
#Version: 20190828
use strict;
use warnings;
use 5.010;
###########Local configuration#############################################
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases',
};
#######End Local configuration#############################################
use lib (LIB_DIR);
use BIGSdb::Offline::RetrievePubMedRecords;
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
use File::Find;
binmode( STDOUT, ':encoding(UTF-8)' );

#Direct all library logging calls to screen
my $log_conf =
    qq(log4perl.category.BIGSdb.Script        = INFO, Screen\n)
  . qq(log4perl.category.BIGSdb.Dataconnector = WARN, Screen\n)
  . qq(log4perl.category.BIGSdb.Datastore     = WARN, Screen\n)
  . qq(log4perl.appender.Screen               = Log::Log4perl::Appender::Screen\n)
  . qq(log4perl.appender.Screen.stderr        = 1\n)
  . qq(log4perl.appender.Screen.layout        = Log::Log4perl::Layout::SimpleLayout\n);
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
my %opts;
GetOptions(
	'd|database=s' => \$opts{'d'},
	'f|force'      => \$opts{'f'},
	'h|help'       => \$opts{'h'},
	'q|quiet'      => \$opts{'q'}
) or die("Error in command line arguments\n");
if ( $opts{'h'} ) {
	show_help();
	exit;
}
main();

sub main {
	if ( $opts{'d'} ) {
		retrieve_pubmed_ids( $opts{'d'} );
	} else {
		opendir( DIR, DBASE_CONFIG_DIR ) or die "Unable to open dbase config directory! $!\n";
		my @config_dirs = readdir(DIR);
		closedir DIR;
		foreach my $dir (@config_dirs) {
			next if !-e DBASE_CONFIG_DIR . "/$dir/config.xml";
			retrieve_pubmed_ids($dir);
		}
	}
	return;
}

sub retrieve_pubmed_ids {
	my ($dbase_config) = @_;
	state %db_checked;
	my $script = BIGSdb::Offline::RetrievePubMedRecords->new(
		{
			config_dir       => CONFIG_DIR,
			lib_dir          => LIB_DIR,
			dbase_config_dir => DBASE_CONFIG_DIR,
			instance         => $dbase_config,
			options          => { quiet => $opts{'q'}, force => $opts{'f'}, pause => $opts{'d'} ? 0 : 1 }
		}
	);
	my $db_name = $script->get_dbase_name;
	return if $db_checked{$db_name};
	$script->run;
	$db_checked{$db_name} = 1;
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
    ${bold}retrieve_pubmed_records.pl$norm - Download PubMed ids to local reference database

${bold}SYNOPSIS$norm
    ${bold}retrieve_pubmed_records.pl$norm [--database ${under}DATABASE$norm] 

${bold}OPTIONS$norm

${bold}-d, --database ${under}DATABASE$norm  
    Database configuration name. If not provided, then all databases on the
    system will be checked
    
${bold}-f, --force$norm
    By default, any suspicious PubMed ids are not retrieved. This option
    forces their retrieval. Suspicious ids are any < 10,000 or any that are
    sequential. Sequential ids are likely to have been entered by mistake using
    Excel autofill.
        
${bold}-h, --help$norm
    This help page.

${bold}-q, --quiet$norm
    Suppress output except errors.

HELP
	return;
}
