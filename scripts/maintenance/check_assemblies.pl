#!/usr/bin/env perl
#Perform/update calculation of assembly GC, N and gap stats.
#Written by Keith Jolley
#Copyright (c) 2021-2022, University of Oxford
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
#Version: 20221031
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
	'database=s'      => \$opts{'d'},
	'exclude=s'       => \$opts{'exclude'},
	'help'            => \$opts{'help'},
	'last_run_days=i' => \$opts{'last_run_days'},
	'quiet'           => \$opts{'quiet'},
	'require_stats'   => \$opts{'require_stats'},
	'refresh_days=i'  => \$opts{'refresh_days'}
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
my $EXIT = 0;
local @SIG{qw (INT TERM HUP)} = ( sub { $EXIT = 1 } ) x 3;    #Capture kill signals
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
		last if $EXIT;
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
	$script->read_assembly_check_file;
	my $min_genome_size =
	  $script->{'system'}->{'min_genome_size'} // $script->{'config'}->{'min_genome_size'} // MIN_GENOME_SIZE;
	my $qry =
	    q[SELECT ss.isolate_id FROM seqbin_stats ss LEFT JOIN assembly_checks ac ON ss.isolate_id=ac.isolate_id ]
	  . q[LEFT JOIN last_run lr ON ss.isolate_id=lr.isolate_id AND lr.name=? ]
	  . q[WHERE ss.total_length>=? AND (ac.datestamp IS NULL ];
	if ( defined $opts{'refresh_days'} ) {
		$qry .= qq(OR ac.datestamp < now()-interval '$opts{'refresh_days'} days' );
	}
	$qry .= q[) ];
	if ( defined $opts{'last_run_days'} ) {
		$qry .= qq(AND (lr.timestamp IS NULL OR lr.timestamp < now()-interval '$opts{'last_run_days'} days') );
	} else {
		$qry .= q(AND lr.timestamp IS NULL );
	}
	$qry .= q(ORDER BY ss.isolate_id);
	my $agent = LWP::UserAgent->new( agent => 'BIGSdb' );
	my $ids =
	  $script->{'datastore'}->run_query( $qry, [ 'AssemblyChecks', $min_genome_size, ], { fetch => 'col_arrayref' } );
	if ( !ref $ids ) {
		$logger->error("Failed on database $config.");
		exit(1);
	}
	my $plural = @$ids == 1 ? q() : q(s);
	my $count = @$ids;
	return if !$count;
	my $job_id = $script->add_job( 'AssemblyChecks', { temp_init => 1 } );
	say qq(\n$config: $count genome$plural to analyse) if !$opts{'quiet'};
	my $app = BIGSdb::Offline::Script->new(
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
			},
			instance => $config,
			logger   => $logger
		}
	);
  ISOLATE: foreach my $isolate_id (@$ids) {
		last ISOLATE if $EXIT;
		next ISOLATE if $opts{'require_stats'} && !advanced_stats_available( $script, $isolate_id );
		print "Checking id-$isolate_id ... " if !$opts{'quiet'};
		my $results = check_record( $script, $isolate_id );
		store_result( $script, $isolate_id, $results );
		say qq(done\t) if !$opts{'quiet'};
		set_last_run_time( $script, $isolate_id );
	}
	$script->stop_job( $job_id, { temp_init => 1 } );
	return;
}

sub check_record {
	my ( $script, $isolate_id ) = @_;
	my $results      = [];
	my $seqbin_stats = $script->{'datastore'}->get_seqbin_stats($isolate_id);
	check_max_contigs( $script, $results, $seqbin_stats );
	check_min_size( $script, $results, $seqbin_stats );
	check_max_size( $script, $results, $seqbin_stats );
	check_min_n50( $script, $results, $seqbin_stats );
	my $ext_checks = $script->{'datastore'}->run_query(
		'SELECT results FROM analysis_results WHERE (name,isolate_id)=(?,?)',
		[ 'AssemblyStats', $isolate_id ]
	);
	if (defined $ext_checks){
		my $checks = decode_json($ext_checks);
		check_min_gc( $script, $results,$checks );
		check_max_gc( $script, $results,$checks );
		check_max_n( $script, $results,$checks );
		check_max_gaps( $script, $results,$checks );
	}
	
	return $results;
}

sub check_max_contigs {
	my ( $script, $results, $seqbin_stats ) = @_;
	return if !defined $seqbin_stats->{'contigs'};
	my $checks = $script->{'assembly_checks'};
	if ( defined $checks->{'max_contigs'}->{'fail'} && $seqbin_stats->{'contigs'} > $checks->{'max_contigs'}->{'fail'} )
	{
		push @$results,
		  {
			name   => 'max_contigs',
			status => 'fail'
		  };
	} elsif ( defined $checks->{'max_contigs'}->{'warn'}
		&& $seqbin_stats->{'contigs'} > $checks->{'max_contigs'}->{'warn'} )
	{
		push @$results,
		  {
			name   => 'max_contigs',
			status => 'warn'
		  };
	}
	return;
}

sub check_min_size {
	my ( $script, $results, $seqbin_stats ) = @_;
	return if !defined $seqbin_stats->{'total_length'};
	my $checks = $script->{'assembly_checks'};
	if ( defined $checks->{'min_size'}->{'fail'} && $seqbin_stats->{'total_length'} < $checks->{'min_size'}->{'fail'} )
	{
		push @$results,
		  {
			name   => 'min_size',
			status => 'fail'
		  };
	} elsif ( defined $checks->{'min_size'}->{'warn'}
		&& $seqbin_stats->{'total_length'} < $checks->{'min_size'}->{'warn'} )
	{
		push @$results,
		  {
			name   => 'min_size',
			status => 'warn'
		  };
	}
	return;
}

sub check_max_size {
	my ( $script, $results, $seqbin_stats ) = @_;
	return if !defined $seqbin_stats->{'total_length'};
	my $checks = $script->{'assembly_checks'};
	if ( defined $checks->{'max_size'}->{'fail'} && $seqbin_stats->{'total_length'} > $checks->{'max_size'}->{'fail'} )
	{
		push @$results,
		  {
			name   => 'max_size',
			status => 'fail'
		  };
	} elsif ( defined $checks->{'max_size'}->{'warn'}
		&& $seqbin_stats->{'total_length'} > $checks->{'max_size'}->{'warn'} )
	{
		push @$results,
		  {
			name   => 'max_size',
			status => 'warn'
		  };
	}
	return;
}

sub check_min_n50 {
	my ( $script, $results, $seqbin_stats ) = @_;
	return if !defined $seqbin_stats->{'n50'};
	my $checks = $script->{'assembly_checks'};
	if ( defined $checks->{'min_n50'}->{'fail'} && $seqbin_stats->{'n50'} < $checks->{'min_n50'}->{'fail'} ) {
		push @$results,
		  {
			name   => 'min_n50',
			status => 'fail'
		  };
	} elsif ( defined $checks->{'min_n50'}->{'warn'}
		&& $seqbin_stats->{'n50'} < $checks->{'min_n50'}->{'warn'} )
	{
		push @$results,
		  {
			name   => 'min_n50',
			status => 'warn'
		  };
	}
	return;
}

sub check_min_gc {
	my ( $script, $results, $stats ) = @_;
	return if !defined $stats->{'percent_GC'};
	my $checks = $script->{'assembly_checks'};
	if ( defined $checks->{'min_gc'}->{'fail'} && $stats->{'percent_GC'} < $checks->{'min_gc'}->{'fail'} ) {
		push @$results,
		  {
			name   => 'min_gc',
			status => 'fail'
		  };
	} elsif ( defined $checks->{'min_gc'}->{'warn'}
		&& $stats->{'percent_GC'} < $checks->{'min_gc'}->{'warn'} )
	{
		push @$results,
		  {
			name   => 'min_gc',
			status => 'warn'
		  };
	}
	return;
}

sub check_max_gc {
	my ( $script, $results, $stats ) = @_;
	return if !defined $stats->{'percent_GC'};
	my $checks = $script->{'assembly_checks'};
	if ( defined $checks->{'max_gc'}->{'fail'} && $stats->{'percent_GC'} > $checks->{'max_gc'}->{'fail'} ) {
		push @$results,
		  {
			name   => 'max_gc',
			status => 'fail'
		  };
	} elsif ( defined $checks->{'max_gc'}->{'warn'}
		&& $stats->{'percent_GC'} > $checks->{'max_gc'}->{'warn'} )
	{
		push @$results,
		  {
			name   => 'max_gc',
			status => 'warn'
		  };
	}
	return;
}

sub check_max_n {
	my ( $script, $results, $stats ) = @_;
	return if !defined $stats->{'N'};
	my $checks = $script->{'assembly_checks'};
	if ( defined $checks->{'max_n'}->{'fail'} && $stats->{'N'} > $checks->{'max_n'}->{'fail'} ) {
		push @$results,
		  {
			name   => 'max_n',
			status => 'fail'
		  };
	} elsif ( defined $checks->{'max_n'}->{'warn'}
		&& $stats->{'N'} > $checks->{'max_n'}->{'warn'} )
	{
		push @$results,
		  {
			name   => 'max_n',
			status => 'warn'
		  };
	}
	return;
}

sub check_max_gaps {
	my ( $script, $results, $stats ) = @_;
	return if !defined $stats->{'gaps'};
	my $checks = $script->{'assembly_checks'};
	if ( defined $checks->{'max_gaps'}->{'fail'} && $stats->{'gaps'} > $checks->{'max_gaps'}->{'fail'} ) {
		push @$results,
		  {
			name   => 'max_gaps',
			status => 'fail'
		  };
	} elsif ( defined $checks->{'max_gaps'}->{'warn'}
		&& $stats->{'gaps'} > $checks->{'max_gaps'}->{'warn'} )
	{
		push @$results,
		  {
			name   => 'max_gaps',
			status => 'warn'
		  };
	}
	return;
}

sub advanced_stats_available {
	my ( $script, $isolate_id ) = @_;
	return $script->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM analysis_results WHERE (name,isolate_id)=(?,?))',
		[ 'AssemblyStats', $isolate_id ] );
}

sub set_last_run_time {
	my ( $script, $isolate_id ) = @_;
	eval {
		$script->{'db'}->do(
			'INSERT INTO last_run (name,isolate_id) VALUES (?,?) ON '
			  . 'CONFLICT (name,isolate_id) DO UPDATE SET timestamp = now()',
			undef, 'AssemblyChecks', $isolate_id
		);
	};
	if ($@) {
		$logger->error($@);
		$script->{'db'}->rollback;
	} else {
		$script->{'db'}->commit;
	}
	return;
}

sub store_result {
	my ( $script, $isolate_id, $results ) = @_;
	eval {
		$script->{'db'}->do( 'DELETE FROM assembly_checks WHERE isolate_id=?', undef, $isolate_id );
		foreach my $result (@$results) {
			$script->{'db'}->do( 'INSERT INTO assembly_checks (name,isolate_id,status) VALUES (?,?,?)',
				undef, $result->{'name'}, $isolate_id, $result->{'status'} );
		}
	};
	if (@$) {
		$logger->error($@);
		$script->{'db'}->rollback;
	} else {
		$script->{'db'}->commit;
	}
}

sub get_lock_file {
	my $config_dir = CONFIG_DIR;
	my $config     = Config::Tiny->read("$config_dir/bigsdb.conf");
	if ( !defined $config ) {
		$logger->fatal( 'Unable to read or parse bigsdb.conf file. Reason: ' . Config::Tiny->errstr );
		$config = Config::Tiny->new();
	}
	my $lock_dir = $config->{_}->{'lock_dir'} // LOCK_DIR;
	my $lock_file = "$lock_dir/assembly_checks";
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
			say 'Lock file exists but process is no longer running - deleting lock.'
			  if !$opts{'quiet'};
			unlink $lock_file;
		} else {
			say 'Script already running with these parameters - terminating.' if !$opts{'quiet'};
			exit(1);
		}

	}
	open( my $fh, '>', $lock_file ) || $logger->error("Cannot open lock file $lock_file for writing");
	say $fh $$;
	close $fh;
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
    ${bold}check_assembies.pl$norm - Validate assemblies based on QC rules.

${bold}SYNOPSIS$norm
    ${bold}check_assembies.pl$norm [${under}options$norm]

${bold}OPTIONS$norm

${bold}--database$norm ${under}DATABASE CONFIG$norm
    Database configuration name. If not included then all isolate databases
    defined on the system will be checked.
    
${bold}--exclude$norm ${under}CONFIG NAMES $norm
    Comma-separated list of config names to exclude.
    
${bold}--help$norm
    This help page.
    
${bold}--last_run_days$norm ${under}DAYS$norm
    Only run for a particular isolate when the analysis was last performed
    at least the specified number of days ago. By default, records will not
    be checked more than once, so setting this to '0' will repeat the checks
    for any record that has not previously failed validation. This is useful
    if the validation settings have been changed. Combine with --refresh_days
    to recheck records that have previously failed validation.
    
${bold}--quiet$norm
    Only show errors.
    
${bold}--refresh_days$norm ${under}DAYS$norm
    Refresh records last analysed longer than the number of days set. By 
    default, only records that have not had a validation failure result 
    recorded will be checked. This will recheck records that have previously
    failed validation.
    
${bold}--require_stats$norm
    Do not perform checks, or update last run time, if detailed assembly stats
    have not been recorded for an isolate. Setting this ensures that the
    update_assembly_stats.pl script has had a chance to run first.  
HELP
	return;
}
