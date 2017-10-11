#!/usr/bin/perl
#Download, check length and create checksum contigs stored as URIs
#in a remote BIGSdb database
#Written by Keith Jolley
#Copyright (c) 2017, University of Oxford
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
###########Local configuration#############################################
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases',
	HOST             => undef,                  #Use values in config.xml
	PORT             => undef,                  #But you can override here.
	USER             => undef,
	PASSWORD         => undef
};
#######End Local configuration#############################################
use lib (LIB_DIR);
use BIGSdb::Offline::ProcessRemoteContigs;
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
my %opts;
GetOptions(
	'database=s'          => \$opts{'d'},
	'exclude_isolates=s'  => \$opts{'I'},
	'exclude_projects=s'  => \$opts{'P'},
	'help'                => \$opts{'h'},
	'isolates=s'          => \$opts{'i'},
	'isolate_list_file=s' => \$opts{'isolate_list_file'},
	'min=i'               => \$opts{'x'},
	'max=i'               => \$opts{'y'},
	'projects=s'          => \$opts{'p'},
	'quiet'               => \$opts{'quiet'}
) or die("Error in command line arguments\n");
if ( $opts{'h'} ) {
	show_help();
	exit;
}

#Direct all library logging calls to screen
my $log_conf =
    qq(log4perl.category.BIGSdb.Script        = INFO, Screen\n)
  . qq(log4perl.category.BIGSdb.Application_Authentication = INFO, Screen\n)  
  . qq(log4perl.category.BIGSdb.Dataconnector = WARN, Screen\n)
  . qq(log4perl.category.BIGSdb.Datastore     = WARN, Screen\n)
  . qq(log4perl.category.BIGSdb.Scheme        = WARN, Screen\n)
  . qq(log4perl.appender.Screen               = Log::Log4perl::Appender::Screen\n)
  . qq(log4perl.appender.Screen.stderr        = 1\n)
  . qq(log4perl.appender.Screen.layout        = Log::Log4perl::Layout::SimpleLayout\n);
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
if ( !$opts{'d'} ) {
	say "\nUsage: process_remote_contigs --database <database configuration>\n";
	say 'Help: process_remote_contigs.pl --help';
	exit;
}
main();

sub main {
	BIGSdb::Offline::ProcessRemoteContigs->new(
		{
			config_dir       => CONFIG_DIR,
			lib_dir          => LIB_DIR,
			dbase_config_dir => DBASE_CONFIG_DIR,
			host             => HOST,
			port             => PORT,
			user             => USER,
			password         => PASSWORD,
			options          => {
				always_run => 1,
				%opts
			},
			instance => $opts{'d'},
			logger   => $logger
		}
	);
	return;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw(me md us);
	say << "HELP";
${bold}NAME$norm
    ${bold}process_remote_contigs.pl$norm
    Download, check length and create checksum contigs stored as URIs

${bold}SYNOPSIS$norm
    ${bold}process_remote_contigs.pl --database$norm ${under}NAME$norm [${under}options$norm]

${bold}OPTIONS$norm
           
${bold}--database$norm ${under}NAME$norm
    Database configuration name.
    
${bold}--exclude_isolates$norm ${under}LIST$norm
    Comma-separated list of isolate ids to ignore.
    
${bold}--exclude_projects$norm ${under}LIST$norm
    Comma-separated list of projects whose isolates will be excluded.
    
${bold}--help$norm
    This help page.
    
${bold}--isolates$norm ${under}LIST$norm  
    Comma-separated list of isolate ids to scan (ignored if -p used).
    
${bold}--isolate_list_file$norm ${under}FILE$norm  
    File containing list of isolate ids (ignored if -i or -p used).
    
${bold}--min$norm ${under}ID$norm
    Minimum isolate id.

${bold}--max$norm ${under}ID$norm
    Maximum isolate id.
           
${bold}--projects$norm ${under}LIST$norm
    Comma-separated list of project isolates to scan.
 
HELP
	return;
}
