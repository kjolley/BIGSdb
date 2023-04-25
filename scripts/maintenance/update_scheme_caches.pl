#!/usr/bin/env perl
#Update tables of scheme field values linked to isolate
#Written by Keith Jolley
#Copyright (c) 2014-2023, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
#Version: 20230110
use strict;
use warnings;
use 5.010;
###########Local configuration################################
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases',
	LOCK_DIR         => '/var/run/lock'         #Override in bigsdb.conf
};
#######End Local configuration################################
use lib (LIB_DIR);
use BIGSdb::Offline::UpdateSchemeCaches;
use BIGSdb::Offline::Script;
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
my %opts;
GetOptions(
	'd|database=s' => \$opts{'d'},
	'h|help'       => \$opts{'h'},
	'm|method=s'   => \$opts{'method'},
	'q|quiet'      => \$opts{'q'},
	'r|reldate=i'  => \$opts{'reldate'},
	's|schemes=s'  => \$opts{'schemes'}
) or die("Error in command line arguments\n");

if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( !$opts{'d'} ) {
	say 'Usage: update_scheme_caches.pl --database <database configuration>';
	exit;
}
if ( $opts{'method'} ) {
	my %allowed = map { $_ => 1 } qw(full incremental daily daily_replace);
	die "$opts{'method'} is not a valid method.\n" if !$allowed{ $opts{'method'} };
}
my $script = BIGSdb::Offline::Script->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		options          => { no_user_db_needed => 1, %opts },
		instance         => $opts{'d'}
	}
);
check_if_script_already_running();
undef $script;
BIGSdb::Offline::UpdateSchemeCaches->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		options          => { mark_job => 1, no_user_db_needed => 1, %opts },
		instance         => $opts{'d'},
	}
);
remove_lock_file();

sub get_lock_file {
	my $hash      = Digest::MD5::md5_hex("$0||$opts{'d'}");
	my $lock_dir  = $script->{'config'}->{'lock_dir'} // LOCK_DIR;
	my $lock_file = "$lock_dir/BIGSdb_scheme_cache_$hash";
	return $lock_file;
}

sub remove_lock_file {
	my $lock_file = get_lock_file();
	unlink $lock_file;
	return;
}

sub check_if_script_already_running {
	my $lock_file = get_lock_file();
	if ( -e $lock_file ) {
		open( my $fh, '<', $lock_file )
		  || $script->{'logger'}->error("Cannot open lock file $lock_file for reading");
		my $pid = <$fh>;
		close $fh;
		my $pid_exists = kill( 0, $pid );
		if ( !$pid_exists ) {
			say 'Lock file exists but process is no longer running - deleting lock.'
			  if !$opts{'quiet'};
			unlink $lock_file;
		} else {
			undef $script;
			say 'Script already running against this database.' if !$opts{'q'};
			exit(1);
		}
	}
	open( my $fh, '>', $lock_file ) || $script->{'logger'}->error("Cannot open lock file $lock_file for writing");
	say $fh $$;
	close $fh;
	return;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t      = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw(me md us);
	say << "HELP";
${bold}NAME$norm
    ${bold}update_scheme_caches.pl$norm - Update scheme field caches

${bold}SYNOPSIS$norm
    ${bold}update_scheme_caches.pl --database ${under}NAME$norm ${bold} ${norm}[${under}options$norm]

${bold}OPTIONS$norm

${bold}--database$norm ${under}NAME$norm
    Database configuration name.
    
${bold}--help$norm
    This help page.
    
${bold}--method$norm ${under}METHOD$norm
    Update method - the following values are allowed:
    full: Completely recreate caches (default)
    incremental: Only add values for records not in cache.
    daily: Only add values for records not in cache updated today.
    daily_replace: Refresh values only for records updated today.
       
${bold}--quiet$norm
    Don't output progress messages.
    
${bold}--reldate$norm ${under}DAYS$norm
    Limit updates to isolates that were last modified up to the specified
    number of days ago. This option is only valid when method is set to
    'incremental'.
    
${bold}--schemes$norm ${under}SCHEMES$norm
    Comma-separated list of scheme ids to use.
    If left empty, all schemes will be updated.  
HELP
	return;
}
