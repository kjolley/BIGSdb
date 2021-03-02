#!/usr/bin/env perl
#Perform/update species id check and store results in isolate database.
#Written by Keith Jolley
#Copyright (c) 2021, University of Oxford
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
#Version: 20210302
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
use BIGSdb::Offline::Script;
use BIGSdb::Constants qw(LOG_TO_SCREEN :limits);
use BIGSdb::Plugins::Helpers::SpeciesID;
use BIGSdb::Utils;
use Term::Cap;
use POSIX;
use MIME::Base64;
use LWP::UserAgent;
use Config::Tiny;
use JSON;
use Getopt::Long qw(:config no_ignore_case);
my %opts;
GetOptions(
	'database=s'     => \$opts{'d'},
	'exclude=s'      => \$opts{'exclude'},
	'help'           => \$opts{'help'},
	'quiet'          => \$opts{'quiet'},
	'refresh_days=i' => \$opts{'refresh_days'}
);

#Direct all library logging calls to screen
my $log_conf = LOG_TO_SCREEN;
$log_conf =~ s/INFO/WARN/gx if $opts{'quiet'};
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
if ( $opts{'help'} ) {
	show_help();
	exit;
}
check_if_script_already_running();
main();
remove_lock_file();
local $| = 1;

sub main {
	if ( $opts{'d'} ) {
		check_db( $opts{'d'} );
		return;
	}
	my $dbs = get_dbs();
	foreach my $db (@$dbs) {
		check_db($db);
	}
	return;
}

sub get_dbs {
	opendir( DIR, DBASE_CONFIG_DIR ) or die "Unable to open dbase config directory! $!\n";
	my $config_dir  = DBASE_CONFIG_DIR;
	my @config_dirs = readdir(DIR);
	closedir DIR;
	my $configs = [];
	my %exclude = map { $_ => 1 } split /,/x, ( $opts{'exclude'} // q() );
	print 'Retrieving list of isolate databases ... ' if !$opts{'quiet'};
	foreach my $dir ( sort @config_dirs ) {
		next if !-e "$config_dir/$dir/config.xml" || -l "$config_dir/$dir/config.xml";
		my $script = BIGSdb::Offline::Script->new(
			{
				config_dir       => CONFIG_DIR,
				lib_dir          => LIB_DIR,
				dbase_config_dir => DBASE_CONFIG_DIR,
				instance         => $dir,
				logger           => $logger,
				options          => {}
			}
		);
		next if ( $script->{'system'}->{'dbtype'} // q() ) ne 'isolates';
		next if ( $script->{'system'}->{'rMLSTSpecies'} // q() ) eq 'no';
		if ( !$script->{'db'} ) {
			$logger->error("Skipping $dir ... database does not exist.");
			next;
		}
		next if $exclude{$dir};
		my $scheme_exists = rmlst_scheme_exists($script);
		next if !$scheme_exists;
		push @$configs, $dir;
	}
	say scalar @$configs . ' found.' if !$opts{'quiet'};
	return $configs;
}

sub check_db {
	my ($config) = @_;
	my $script = BIGSdb::Offline::Script->new(
		{
			config_dir       => CONFIG_DIR,
			lib_dir          => LIB_DIR,
			dbase_config_dir => DBASE_CONFIG_DIR,
			instance         => $config,
			logger           => $logger,
			options          => { mark_job => 1 }
		}
	);
	if ( ( $script->{'system'}->{'dbtype'} // q() ) ne 'isolates' ) {
		$logger->error("$config is not an isolate database.");
		return;
	}
	my $min_genome_size =
	  $script->{'system'}->{'min_genome_size'} // $script->{'config'}->{'min_genome_size'} // MIN_GENOME_SIZE;
	my $qry = q(SELECT id FROM isolates i JOIN seqbin_stats ss ON i.id=ss.isolate_id AND ss.total_length>=? LEFT JOIN )
	  . q(analysis_results ar ON i.id=ar.isolate_id AND name=? WHERE ar.datestamp IS NULL );
	if ( $opts{'refresh_days'} ) {
		$qry .= qq(OR ar.datestamp < now()-interval '$opts{'refresh_days'} days' );
	}
	$qry .= q(ORDER BY i.id);
	my $agent = LWP::UserAgent->new( agent => 'BIGSdb' );
	my $ids =
	  $script->{'datastore'}->run_query( $qry, [ $min_genome_size, 'RMLSTSpecies' ], { fetch => 'col_arrayref' } );
	my $plural = @$ids == 1 ? q() : q(s);
	my $count = @$ids;
	return if !$count;
	my $job_id = $script->add_job( 'RMLSTSpecies', { temp_init => 1 } );
	my $EXIT = 0;
	local @SIG{qw (INT TERM HUP)} = ( sub { $EXIT = 1 } ) x 3;    #Allow temp files to be cleaned on kill signals
	say qq(\n$config: $count genome$plural to analyse) if !$opts{'quiet'};
	my $id_obj = BIGSdb::Plugins::Helpers::SpeciesID->new(
		{
			config_dir       => CONFIG_DIR,
			lib_dir          => LIB_DIR,
			dbase_config_dir => DBASE_CONFIG_DIR,
			host             => $script->{'system'}->{'host'},
			port             => $script->{'system'}->{'port'},
			user             => $script->{'system'}->{'user'},
			password         => $script->{'system'}->{'password'},
			options          => {
				always_run           => 1,
				throw_busy_exception => 0,
				job_id               => $job_id,
				scan_genome          => 0,
				no_disconnect        => 1
			},
			instance => $config,
			logger   => $logger
		}
	);
	my %label = (
		0 => 'designations',
		1 => 'genome sequence'
	);
	my @scan_genome = defined $id_obj->get_rmlst_scheme_id ? ( 0, 1 ) : (1);
  ISOLATE: foreach my $isolate_id (@$ids) {
	  RUN: foreach my $run (@scan_genome) {
			last ISOLATE if $EXIT;
			print "Scanning id-$isolate_id $label{$run} ... " if !$opts{'quiet'};
			$id_obj->set_scan_genome($run);
			my $result = $id_obj->run($isolate_id);
			if ( $result->{'data'}->{'taxon_prediction'} ) {
				my @predictions = @{ $result->{'data'}->{'taxon_prediction'} };
				my @taxa;
				push @taxa, $_->{'taxon'} foreach @predictions;
				local $" = q(, );
				say qq(@taxa.) if !$opts{'quiet'};
				store_result( $script, $isolate_id, $result );
				last RUN;
			} else {
				say q(no match.) if !$opts{'quiet'};
			}
		}
	}
	$script->stop_job( $job_id, { temp_init => 1 } );
	return;
}

sub store_result {
	my ( $script, $isolate_id, $record_result ) = @_;
	my ( $data,   $result,     $response )      = @{$record_result}{qw{data values response}};
	return if $response->code != 200;
	my $predictions = ref $result->{'rank'} eq 'ARRAY' ? @{ $result->{'rank'} } : 0;
	return if !$predictions;
	my $json = encode_json($data);
	eval {
		$script->{'db'}
		  ->do( 'DELETE FROM analysis_results WHERE (isolate_id,name)=(?,?)', undef, $isolate_id, 'RMLSTSpecies' );
		$script->{'db'}->do( 'INSERT INTO analysis_results (name,isolate_id,results) VALUES (?,?,?)',
			undef, 'RMLSTSpecies', $isolate_id, $json );
	};
	if ($@) {
		$logger->error($@);
		$script->{'db'}->rollback;
	} else {
		$script->{'db'}->commit;
	}
	return;
}

sub get_lock_file {
	my $config_dir = CONFIG_DIR;
	my $config     = Config::Tiny->read("$config_dir/bigsdb.conf");
	if ( !defined $config ) {
		$logger->fatal( 'Unable to read or parse bigsdb.conf file. Reason: ' . Config::Tiny->errstr );
		$config = Config::Tiny->new();
	}
	my $lock_dir = $config->{_}->{'lock_dir'} // LOCK_DIR;
	my $lock_file = "$lock_dir/update_rmlst_species";
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
		say $lock_file;
		open( my $fh, '<', $lock_file ) || $logger->error("Cannot open lock file $lock_file for reading");
		my $pid = <$fh>;
		close $fh;
		my $pid_exists = kill( 0, $pid );
		if ( !$pid_exists ) {
			$logger->error('Lock file exists but process is no longer running - deleting lock.');
			unlink $lock_file;
		} else {
			die "Script already running - terminating.\n";
		}
	}
	open( my $fh, '>', $lock_file ) || $logger->error("Cannot open lock file $lock_file for writing");
	say $fh $$;
	close $fh;
	return;
}

sub rmlst_scheme_exists {
	my ($script) = @_;
	my $scheme_id =
	  $script->{'datastore'}
	  ->run_query( 'SELECT id FROM schemes WHERE name=? AND dbase_name IS NOT NULL and dbase_id IS NOT NULL',
		'Ribosomal MLST' );
	return if !defined $scheme_id;
	my $loci = $script->{'datastore'}->get_scheme_loci( $scheme_id, { profile_name => 1 } );
	foreach my $locus (@$loci) {
		return if $locus !~ /^BACT0000\d{2}$/x;
	}
	return 1;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw/me md us/;
	say << "HELP";
${bold}NAME$norm
    ${bold}update_rmlst_species.pl$norm - Perform/update species id check

${bold}SYNOPSIS$norm
    ${bold}update_rmlst_species.pl$norm [${under}options$norm]

${bold}OPTIONS$norm

${bold}--database$norm ${under}DATABASE CONFIG$norm
    Database configuration name. If not included then all isolate databases
    defined on the system will be checked.
    
${bold}--exclude$norm ${under}CONFIG NAMES $norm
    Comma-separated list of config names to exclude.
    
${bold}--help$norm
    This help page.
    
${bold}--quiet$norm
    Only show errors.
    
${bold}--refresh_days$norm ${under}DAYS$norm
    Refresh records last analysed longer that the number of days set. By 
    default, only records that have not been analysed will be checked.      
HELP
	return;
}
