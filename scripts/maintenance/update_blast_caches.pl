#!/usr/bin/perl -T
#Update cached BLAST databases for a seqdef database
#Written by Keith Jolley
#Copyright (c) 2015-2017, University of Oxford
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
use BIGSdb::Offline::Blast;
use Term::Cap;
use POSIX;
use Getopt::Long qw(:config no_ignore_case);
my %opts;
GetOptions(
	'all_loci'            => \$opts{'all_loci'},
	'd|database=s'        => \$opts{'d'},
	'delete_all'          => \$opts{'delete_all'},
	'delete_old'          => \$opts{'delete_old'},
	'delete_single_locus' => \$opts{'delete_single_locus'},
	'help'                => \$opts{'help'},
	'quiet'               => \$opts{'quiet'},
	'refresh'             => \$opts{'refresh'},
	'scheme=i'            => \$opts{'scheme'}
);
if ( $opts{'help'} ) {
	show_help();
	exit;
}

my $script_logging = $opts{'quiet'} ? 'WARN' : 'INFO';

#Direct all library logging calls to screen
my $log_conf =
    qq(log4perl.category.BIGSdb.Script        = $script_logging, Screen\n)
  . qq(log4perl.category.BIGSdb.Dataconnector = WARN, Screen\n)
  . qq(log4perl.category.BIGSdb.Datastore     = WARN, Screen\n)
  . qq(log4perl.appender.Screen               = Log::Log4perl::Appender::Screen\n)
  . qq(log4perl.appender.Screen.stderr        = 1\n)
  . qq(log4perl.appender.Screen.layout        = Log::Log4perl::Layout::SimpleLayout\n);
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
if ( !$opts{'d'} ) {
	say 'Usage: update_cached_blast_dbs.pl --database <database configuration>';
	exit;
}
my $blast_obj = BIGSdb::Offline::Blast->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		options          => \%opts,
		instance         => $opts{'d'},
		logger           => $logger
	}
);
my $method = {
	all_loci            => sub { $blast_obj->create_scheme_cache(0) },
	delete_all          => sub { $blast_obj->delete_caches },
	delete_old          => sub { $blast_obj->delete_caches( { if_stale => 1 } ) },
	delete_single_locus => sub { $blast_obj->delete_caches( { single_locus => 1 } ) },
	scheme              => sub { $blast_obj->create_scheme_cache( $opts{'scheme'} ) },
	refresh             => sub { $blast_obj->refresh_caches },
};
foreach my $action (qw (delete_all delete_old delete_single_locus all_loci scheme refresh)) {
	if ( $opts{$action} ) {
		$method->{$action}->();
		last;
	}
	$blast_obj->refresh_caches;    #Default action
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw/me md us/;
	say << "HELP";
${bold}NAME$norm
    ${bold}update_cached_blast_dbs.pl$norm - Refresh BLAST database caches

${bold}SYNOPSIS$norm
    ${bold}update_cached_blast_dbs.pl --database ${under}DB_CONFIG$norm [${under}options$norm]

${bold}OPTIONS$norm
${bold}--all_loci$norm
    Refresh or create cache for all loci.

${bold}--database$norm ${under}DATABASE CONFIG$norm
    Database configuration name.
    
${bold}--delete_all$norm
    Remove all cache files.
    
${bold}--delete_old$norm
    Remove cache files older than the cache_days setting in bigsdb.conf or 
    that have been marked stale.
    
${bold}--delete_single_locus$norm
    Remove caches containing only one locus. There can be many of these and
    they can clutter the cache directory. They are generally quick to recreate
    when needed.
    
${bold}--help$norm
    This help page.
    
${bold}--quiet$norm
    Only show errors.  
    
${bold}--refresh$norm
    Refresh existing caches.
    
${bold}--scheme$norm ${under}SCHEME_ID$norm
    Refresh or create cache for specified scheme.
    
HELP
	return;
}
