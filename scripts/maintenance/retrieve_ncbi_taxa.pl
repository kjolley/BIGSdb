#!/usr/bin/env perl
#Retrieve NCBI taxa records for a database
#Written by Keith Jolley
#Copyright (c) 2026, University of Oxford
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
#Version: 20260909
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
use BIGSdb::Offline::RetrieveNcbiTaxa;
use BIGSdb::Constants qw(LOG_TO_SCREEN);
use Getopt::Long      qw(:config no_ignore_case);
use Term::Cap;
use File::Find;
binmode( STDOUT, ':encoding(UTF-8)' );

#Direct all library logging calls to screen
my $log_conf = LOG_TO_SCREEN;
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
my %opts;
GetOptions(
	'clear'          => \$opts{'clear'},
	'd|database=s'   => \$opts{'d'},
	'h|help'         => \$opts{'h'},
	'method=s'       => \$opts{'method'},
	'q|quiet'        => \$opts{'quiet'},
	'refresh_days=i' => \$opts{'refresh_days'},
	'retry'          => \$opts{'retry'}
) or die("Error in command line arguments\n");
if ( $opts{'h'} ) {
	show_help();
	exit;
}
my %methods = map { $_ => 1 } qw(new refresh);
$opts{'method'} //= 'new';
if ( !$methods{ $opts{'method'} } ) {
	die "Invalid method selected.\n";
}
main();

sub main {
	if ( $opts{'d'} ) {
		retrieve_taxa( $opts{'d'} );
	} else {
		opendir( my $dh, DBASE_CONFIG_DIR ) or die "Unable to open dbase config directory! $!\n";
		my @config_dirs = readdir($dh);
		closedir $dh;
		foreach my $dir (@config_dirs) {
			my $config_file = DBASE_CONFIG_DIR . "/$dir/config.xml";
			next if !-e $config_file;
			my $is_seqdef;
			open( my $fh, '<', $config_file ) or die "Cannot open $config_file $!\n";
			while (<$fh>) {
				if (/dbtype\s*=\s*"sequences"/x) {
					$is_seqdef = 1;
					last;
				}
			}
			close $fh;
			next if !$is_seqdef;
			retrieve_taxa($dir);
		}
	}
	return;
}

sub retrieve_taxa {
	my ($dbase_config) = @_;
	state %db_checked;
	my $script = BIGSdb::Offline::RetrieveNcbiTaxa->new(
		{
			config_dir       => CONFIG_DIR,
			lib_dir          => LIB_DIR,
			dbase_config_dir => DBASE_CONFIG_DIR,
			instance         => $dbase_config,
			logger           => $logger,
			options          => {
				quiet        => $opts{'quiet'},
				pause        => $opts{'d'} ? 0 : 1,
				method       => $opts{'method'},
				retry        => $opts{'retry'},
				refresh_days => $opts{'refresh_days'},
				clear        => $opts{'clear'}
			}
		}
	);
	my $db_name = $script->get_dbase_name;
	return if !$db_name || $db_checked{$db_name};
	$db_checked{$db_name} = 1;
	return;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t      = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw/me md us/;
	say << "HELP";
${bold}NAME$norm
    ${bold}retrieve_ncbi_taxa.pl$norm - Download NCBI taxa records for schemes

${bold}SYNOPSIS$norm
    ${bold}retrieve_ncbi_taxa.pl$norm [--database ${under}DATABASE$norm] 

${bold}OPTIONS$norm

${bold}--clear$norm
    Remove entries for taxa not included in schemes table.

${bold}-d, --database ${under}DATABASE$norm  
    Database configuration name. If not provided, then all databases on the
    system will be checked
          
${bold}-h, --help$norm
    This help page.
    
${bold}--method$norm ${under}METHOD$norm
    Method to use. Either 'add' or 'refresh'. Default is 'add'.

${bold}--quiet$norm
    Suppress output except errors.
    
${bold}--refresh_days$norm ${under}DAYS$norm
    Use with the refresh method to set the age of records in days that should
    be refreshed. Default is 365.
    
${bold}--retry$norm
    Retry ids that have been checked but were previously not found (usually 
    these indicate an error when entering the taxon id for a scheme).

HELP
	return;
}
