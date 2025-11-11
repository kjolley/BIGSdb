#!/usr/bin/env perl
#Perform/update PlasmidFinder analyses and store results in isolate database.
#Written by Keith Jolley
#Copyright (c) 2025, University of Oxford
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
#Version: 20251111
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
use File::Copy;
use File::Path qw(rmtree);
use constant MODULE_NAME => 'PlasmidFinder';
use Getopt::Long qw(:config no_ignore_case);
my %opts;
GetOptions(
	'database=s'      => \$opts{'d'},
	'exclude=s'       => \$opts{'exclude'},
	'help'            => \$opts{'help'},
	'last_run_days=i' => \$opts{'last_run_days'},
	'quiet'           => \$opts{'quiet'},
	'refresh_days=i'  => \$opts{'refresh_days'},
	'v|view=s'        => \$opts{'v'}
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

sub check_if_script_already_running {
	my $lock_file = get_lock_file('update_plasmidfinder');
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
	if ( defined $opts{'refresh_days'} ) {
		$qry .= qq(OR ar.datestamp < now()-interval '$opts{'refresh_days'} days' );
	}
	$qry .= q[) ];
	if ( defined $opts{'last_run_days'} ) {
		$qry .= qq(AND (lr.timestamp IS NULL OR lr.timestamp < now()-interval '$opts{'last_run_days'} days') );
	}
	if ( $opts{'v'} ) {
		$qry .= qq( AND ss.isolate_id IN (SELECT id FROM $opts{'v'}));
	}
	$qry .= q(ORDER BY ss.isolate_id);
	my $agent = LWP::UserAgent->new( agent => 'BIGSdb', timeout => 600 );
	my $genome_ids =
	  $script->{'datastore'}
	  ->run_query( $qry, [ 'PlasmidFinder', 'PlasmidFinder', $min_genome_size ], { fetch => 'col_arrayref' } );
	my $ids    = filter_ids_by_plasmidfinder_view( $script, $genome_ids );
	my $plural = @$ids == 1 ? q() : q(s);
	my $count  = @$ids;
	return if !$count;
	my $job_id = $script->add_job( 'PlasmidFinder (offline)', { temp_init => 1 } ) // BIGSdb::Utils::get_random();
	say qq(\n$config: $count genome$plural to analyse) if !$opts{'quiet'};
	my $i          = 0;
	my $labelfield = ucfirst( $script->{'system'}->{'labelfield'} );
	my $tmp_dir    = "$script->{'config'}->{'secure_tmp_dir'}/$job_id";

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
		my $assembly_file_path = $script->make_assembly_file( $job_id, $isolate_id );
		mkdir $tmp_dir;
		( my $assembly_filename = $assembly_file_path ) =~ s/.+\///x;
		my $error_file = "$tmp_dir/${isolate_id}_error.log";

		move( $assembly_file_path, $tmp_dir );
		my $json_file = "${isolate_id}.json";
		my $cmd =
			qq(docker run -u "\$(id -u):\$(id -g)" --rm -v plasmidfinder_db_path:/database -v ${tmp_dir}:/workdir )
		  . qq(-w /workdir plasmidfinder -i $assembly_filename -o /workdir -j $json_file);
		eval { system(qq($cmd 1>/dev/null 2>$error_file)); };

		my $error_ref = BIGSdb::Utils::slurp($error_file);
		if ( $! || $$error_ref ) {
			$logger->error("$$error_ref Command: $cmd");
			BIGSdb::Exception::Plugin->throw('PlasmidFinder failed.');
		}
		my $json_path = "$tmp_dir/$json_file";
		my $results   = {};
		eval {
			my $json_results = BIGSdb::Utils::slurp($json_path);
			$results = decode_json($$json_results);
		};
		if ($@) {
			$logger->error($@);
		}
		if ( keys %$results ) {
			store_results( $script, $isolate_id, $results );
		}
		$script->set_last_run_time( MODULE_NAME, $isolate_id );
		say q(done.) if !$opts{'quiet'};
		rmtree($tmp_dir);
		$i++;
		last if $EXIT;
	}
	rmtree($tmp_dir);
	$script->stop_job( $job_id, { temp_init => 1 } );
	return;
}

sub store_results {
	my ( $self, $isolate_id, $data ) = @_;
	my $json = encode_json($data);
	eval {
		$self->{'db'}
		  ->do( 'DELETE FROM analysis_results WHERE (isolate_id,name)=(?,?)', undef, $isolate_id, MODULE_NAME );
		$self->{'db'}->do( 'INSERT INTO analysis_results (name,isolate_id,results) VALUES (?,?,?)',
			undef, MODULE_NAME, $isolate_id, $json );
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub filter_ids_by_plasmidfinder_view {
	my ( $self, $ids ) = @_;
	my $filtered = [];
	if ( !$self->{'system'}->{'plasmidfinder_view'} ) {
		$filtered = $ids;
	} else {
		my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $ids );
		$filtered =
		  $self->{'datastore'}->run_query(
			"SELECT v.id FROM $self->{'system'}->{'plasmidfinder_view'} v JOIN $temp_table t ON v.id=t.value",
			undef, { fetch => 'col_arrayref' } );

	}
	return $filtered;
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
		if ( !defined $script->{'config'}->{'plasmidfinder'} ) {
			die "plasmidfinder is not set in bigsdb.conf.\n";
		}
		if ( !defined $script->{'config'}->{'plasmidfinder_db_path'} ) {
			die "plasmidfinder_db_path is not set in bigsdb.conf.\n";
		}
		next if ( $script->{'system'}->{'dbtype'}        // q() ) ne 'isolates';
		next if ( $script->{'system'}->{'PlasmidFinder'} // q() ) eq 'no';
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

sub get_lock_file {
	my $config_dir = CONFIG_DIR;
	my $config     = Config::Tiny->read("$config_dir/bigsdb.conf");
	if ( !defined $config ) {
		$logger->fatal( 'Unable to read or parse bigsdb.conf file. Reason: ' . Config::Tiny->errstr );
		$config = Config::Tiny->new();
	}
	my $lock_dir  = $config->{_}->{'lock_dir'} // LOCK_DIR;
	my $lock_file = "$lock_dir/update_plasmidfinder";
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
    ${bold}update_plasmidfinder.pl$norm - Perform/update PlasmidFinder analysis

${bold}SYNOPSIS$norm
    ${bold}update_plasmidfinder.pl$norm [${under}options$norm]

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
       
${bold}--quiet$norm
    Only show errors.
    
${bold}--refresh_days$norm ${under}DAYS$norm
    Refresh records last analysed longer that the number of days set. By 
    default, only records that have not been analysed will be checked. 
    
${bold}--view, -v$norm ${under}VIEW$norm
    Isolate database view (overrides the view set in config.xml).
     
HELP
	return;
}
