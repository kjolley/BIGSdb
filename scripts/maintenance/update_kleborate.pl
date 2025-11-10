#!/usr/bin/env perl
#Perform/update Kleborate analyses and store results in isolate database.
#Written by Keith Jolley
#Copyright (c) 2023-2025, University of Oxford
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
#Version: 20251110
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
use JSON;
use Term::Cap;
use POSIX;
use File::Path qw(rmtree);
use constant MODULE_NAME => 'Kleborate';
use Getopt::Long qw(:config no_ignore_case);
my %opts;
GetOptions(
	'database=s'      => \$opts{'d'},
	'exclude=s'       => \$opts{'exclude'},
	'help'            => \$opts{'help'},
	'last_run_days=i' => \$opts{'last_run_days'},
	'preset=s'        => \$opts{'preset'},
	'quiet'           => \$opts{'quiet'},
	'refresh_days=i'  => \$opts{'refresh_days'},
	'v|view=s'        => \$opts{'v'}
);
$opts{'preset'} //= 'kpsc';

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
my %allowed_presets = map { $_ => 1 } qw(kpsc kosc escherichia);

if ( !$allowed_presets{ $opts{'preset'} } ) {
	die "Invalid --preset option - use either kpsc, kosc, or escherichia.\n";
}

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
	opendir( my $dir, DBASE_CONFIG_DIR ) or die "Unable to open dbase config directory! $!\n";
	my $config_dir  = DBASE_CONFIG_DIR;
	my @config_dirs = readdir($dir);
	closedir $dir;
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
		if ( !defined $script->{'config'}->{'kleborate_path'} ) {
			die "kleborate_path is not set in bigsdb.conf.\n";
		}
		next if ( $script->{'system'}->{'dbtype'}    // q() ) ne 'isolates';
		next if ( $script->{'system'}->{'Kleborate'} // q() ) ne 'yes';
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
	my $min_genome_size = $script->{'system'}->{'min_genome_size'} // $script->{'config'}->{'min_genome_size'}
	  // MIN_GENOME_SIZE;
	my $qry =
		q[SELECT ss.isolate_id FROM seqbin_stats ss LEFT JOIN analysis_results ar ON ss.isolate_id=ar.isolate_id ]
	  . q[AND ar.name=? LEFT JOIN last_run lr ON ss.isolate_id=lr.isolate_id AND lr.name=? ]
	  . q[WHERE ss.total_length>=? AND (ar.datestamp IS NULL ];
	if ( $opts{'refresh_days'} ) {
		$qry .= qq(OR ar.datestamp < now()-interval '$opts{'refresh_days'} days' );
	}
	$qry .= q[) ];
	if ( $opts{'last_run_days'} ) {
		$qry .= qq(AND (lr.timestamp IS NULL OR lr.timestamp < now()-interval '$opts{'last_run_days'} days') );
	}
	if ( $opts{'v'} ) {
		$qry .= qq( AND ss.isolate_id IN (SELECT id FROM $opts{'v'}));
	}
	$qry .= q(ORDER BY ss.isolate_id);
	my $agent = LWP::UserAgent->new( agent => 'BIGSdb', timeout => 600 );
	my $ids =
	  $script->{'datastore'}
	  ->run_query( $qry, [ 'Kleborate', 'Kleborate', $min_genome_size ], { fetch => 'col_arrayref' } );
	my $plural = @$ids == 1 ? q() : q(s);
	my $count  = @$ids;
	return if !$count;
	my $job_id = $script->add_job( 'Kleborate (offline)', { temp_init => 1 } ) // BIGSdb::Utils::get_random();
	say qq(\n$config: $count genome$plural to analyse) if !$opts{'quiet'};
	my $i             = 0;
	my $major_version = get_kleborate_major_version($script);

	foreach my $isolate_id (@$ids) {
		my $progress = int( $i * 100 / @$ids );
		$script->update_job(
			$job_id,
			{
				status    => { stage => "Analysing id-$isolate_id", percent_complete => $progress },
				temp_init => 1
			}
		);
		print qq(Processing id-$isolate_id ...) if !$opts{'quiet'};
		my $assembly_file = $script->make_assembly_file( $job_id, $isolate_id, { extension => 'fasta' } );
		my $out_file;

		if ( $major_version == 2 ) {
			$out_file = "$script->{'config'}->{'secure_tmp_dir'}/${job_id}_kleborate.txt";
			my $cmd = "$script->{'config'}->{'kleborate_path'} -all -o $out_file -a $assembly_file > /dev/null";
			system($cmd);
		} else {

			my $dir = "$script->{'config'}->{'secure_tmp_dir'}/$job_id";
			mkdir $dir;
			my $cmd = "$script->{'config'}->{'kleborate_path'} -o $dir -a $assembly_file "
			  . "-p $opts{'preset'} --trim_headers > /dev/null";
			$out_file = "$dir/klebsiella_pneumo_complex_output.txt";
			system($cmd);
		}

		store_results( $script, $isolate_id, $out_file );
		$script->set_last_run_time( MODULE_NAME, $isolate_id );
		if ( $major_version > 2 ) {
			rmtree "$script->{'config'}->{'secure_tmp_dir'}/$job_id";
		}
		unlink $assembly_file;
		unlink $out_file;
		say q(done.) if !$opts{'quiet'};
		$i++;
		last if $EXIT;
	}
	$script->stop_job( $job_id, { temp_init => 1 } );
	return;
}

sub extract_results {
	my ($filename) = @_;
	open( my $fh, '<', $filename ) || $logger->error("Cannot open $filename for reading");
	my $header_line = <$fh>;
	chomp $header_line;
	my $results_line = <$fh>;
	chomp $results_line;
	close $fh;
	my $headers = [ split /\t/x, $header_line ];
	my $results = [ split /\t/x, $results_line ];
	return ( $headers, $results );
}

sub store_results {
	my ( $script, $isolate_id, $output_file ) = @_;
	my $cleaned_results = [];
	my ( $headers, $results ) = extract_results($output_file);
	if ( !@$headers || !@$results ) {
		$logger->error("No valid results for id-$isolate_id");
		return;
	}
	my %ignore = map { $_ => 1 }
	  qw(strain contig_count N50 largest_contig total_size ambiguous_bases ST Chr_ST gapA infB mdh pgi phoE rpoB tonB);
	for my $i ( 0 .. @$headers - 1 ) {
		next if $ignore{ $headers->[$i] };
		next
		  if !defined $results->[$i]
		  || $results->[$i] eq '-'
		  || $results->[$i] eq ''
		  || $results->[$i] eq 'Not Tested';
		push @$cleaned_results,
		  { $headers->[$i] => BIGSdb::Utils::is_int( $results->[$i] ) ? int( $results->[$i] ) : $results->[$i] };
	}
	my $version = get_kleborate_version($script);
	chomp $version;
	my $json = encode_json( { version => $version, fields => $cleaned_results } );
	eval {
		$script->{'db'}
		  ->do( 'DELETE FROM analysis_results WHERE (isolate_id,name)=(?,?)', undef, $isolate_id, MODULE_NAME );
		$script->{'db'}->do( 'INSERT INTO analysis_results (name,isolate_id,results) VALUES (?,?,?)',
			undef, MODULE_NAME, $isolate_id, $json );
	};
	if ($@) {
		$logger->error($@);
		$script->{'db'}->rollback;
	} else {
		$script->{'db'}->commit;
	}
	return;
}

sub get_kleborate_major_version {
	my ($script) = @_;
	my $version = get_kleborate_version($script);
	my $major_version;
	if ( $version =~ /^Kleborate\s+v(\d+)\./x ) {
		$major_version = $1;
	} else {
		$logger->error('Unknown Kleborate version');
		$major_version = 2;
	}
	return $major_version;
}

sub get_kleborate_version {
	my ($script) = @_;
	return if !-x $script->{'config'}->{'kleborate_path'};
	my $out = "$script->{'config'}->{'secure_tmp_dir'}/kleborate_$$";
	local $ENV{'TERM'} = 'dumb';
	my $version     = system("$script->{'config'}->{'kleborate_path'} --version > $out");
	my $version_ref = BIGSdb::Utils::slurp($out);
	unlink $out;
	return $$version_ref;
}

sub check_if_script_already_running {
	my $lock_file = get_lock_file('update_kleborate');
	if ( -e $lock_file ) {
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

sub get_lock_file {
	my $config_dir = CONFIG_DIR;
	my $config     = Config::Tiny->read("$config_dir/bigsdb.conf");
	if ( !defined $config ) {
		$logger->fatal( 'Unable to read or parse bigsdb.conf file. Reason: ' . Config::Tiny->errstr );
		$config = Config::Tiny->new();
	}
	my $lock_dir  = $config->{_}->{'lock_dir'} // LOCK_DIR;
	my $lock_file = "$lock_dir/update_kleborate";
	return $lock_file;
}

sub remove_lock_file {
	my $lock_file = get_lock_file();
	unlink $lock_file;
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
    ${bold}update_kleborate.pl$norm - Perform/update Kleborate analysis

${bold}SYNOPSIS$norm
    ${bold}update_kleborate.pl$norm [${under}options$norm]

${bold}OPTIONS$norm

${bold}--database$norm ${under}DATABASE CONFIG$norm
    Database configuration name. If not included then all isolate databases
    with the Kleborate flag set on their configuration will be checked.
    
${bold}--exclude$norm ${under}CONFIG NAMES $norm
    Comma-separated list of config names to exclude.
    
${bold}--help$norm
    This help page.
    
${bold}--last_run_days$norm ${under}DAYS$norm
    Only run for a particular isolate when the analysis was last performed
    at least the specified number of days ago.
    
${bold}--preset$norm ${under}PRESET$norm
    Preset list of modules to run (only for Kleborate v3). Available options
    are:
      kpsc [for Klebsiella pneumoniae species complex - default],
      kosc [for Klebsiella oxytoca species complex],
      escherichia [for Escherichia coli]
    
${bold}--quiet$norm
    Only show errors.
    
${bold}--refresh_days$norm ${under}DAYS$norm
    Refresh records last analysed longer that the number of days set. By 
    default, only records that have not been analysed will be checked. 
    
${bold}--view, -v$norm ${under}VIEW$norm
    Isolate database view (overrides value set in config.xml).
     
HELP
	return;
}
