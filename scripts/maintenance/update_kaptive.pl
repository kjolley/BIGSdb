#!/usr/bin/env perl
#Perform/update Kaptive analyses and store results in isolate database.
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
#Version: 20250717
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
use File::Path qw(make_path rmtree);
use Text::CSV;
use constant MODULE_NAME => 'Kaptive';
use constant VALID_DBS   => (qw(kpsc_k kpsc_o ab_k ab_o));
use constant DB_NAMES    => {
	kpsc_k => 'Klebsiella K locus',
	kpsc_o => 'Klebsiella O locus',
	ab_k   => 'Acinetobacter baumannii K locus',
	ab_o   => 'Acinetobacter baumannii OC locus'
};
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
				options          => { no_user_db_needed => 1 }
			}
		);
		if ( !defined $script->{'config'}->{'kaptive_path'} ) {
			die "kaptive_path is not set in bigsdb.conf.\n";
		}
		next if ( $script->{'system'}->{'dbtype'}  // q() ) ne 'isolates';
		next if ( $script->{'system'}->{'Kaptive'} // q() ) ne 'yes';
		next if !defined $script->{'system'}->{'kaptive_dbs'};
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
	  ->run_query( $qry, [ 'Kaptive', 'Kaptive', $min_genome_size ], { fetch => 'col_arrayref' } );
	my $ids    = filter_ids_by_kaptive_view( $script, $genome_ids );
	my $plural = @$ids == 1 ? q() : q(s);
	my $count  = @$ids;
	return if !$count;
	my $job_id = $script->add_job( 'Kaptive (offline)', { temp_init => 1 } ) // BIGSdb::Utils::get_random();
	say qq(\n$config: $count genome$plural to analyse) if !$opts{'quiet'};
	my $i          = 0;
	my $db_names   = DB_NAMES;
	my @dbs        = split /\s*,\s*/x, $script->{'system'}->{'kaptive_dbs'};
	my $labelfield = ucfirst( $script->{'system'}->{'labelfield'} );

	foreach my $isolate_id (@$ids) {
		my $isolate_data = {};
		my $progress     = int( $i * 100 / @$ids );
		$script->update_job(
			$job_id,
			{
				status    => { stage => "Analysing id-$isolate_id", percent_complete => $progress },
				temp_init => 1
			}
		);
		print qq(Processing id-$isolate_id ...) if !$opts{'quiet'};
		my $assembly_file = make_assembly_file( $script, $job_id, $isolate_id );
		foreach my $db (@dbs) {
			last if $EXIT;
			my $temp_out = "$script->{'config'}->{'secure_tmp_dir'}/${job_id}/temp_${isolate_id}_$db.tsv";
			my $cmd      = "$script->{'config'}->{'kaptive_path'} assembly $db $assembly_file --out $temp_out "
			  . "--plot $script->{'config'}->{'secure_tmp_dir'}/$job_id --plot-fmt svg 2> /dev/null";

			system($cmd);
			if ( -e $temp_out ) {
				my $data = tsv2arrayref($temp_out);
				if ( ref $data eq 'ARRAY' ) {
					if ( @$data == 1 ) {
						$isolate_data->{$db}->{'fields'} = $data->[0];
						delete $isolate_data->{$db}->{'Assembly'};
					} elsif ( @$data > 1 ) {
						$logger->error("Multiple rows reported for id-$isolate_id $db - This is unexpected.");
					}
				}
				open( my $fh_in, '<:encoding(utf8)', $temp_out )
				  || $logger->error("Cannot open $temp_out for reading.");
				my $name = $script->{'datastore'}
				  ->run_query( "SELECT $script->{'system'}->{'labelfield'} FROM isolates WHERE id=?", $isolate_id );
				close $fh_in;
				my $svg_filename = "id-${isolate_id}_kaptive_results.svg";
				my $svg_path     = "$script->{'config'}->{'secure_tmp_dir'}/${job_id}/$svg_filename";
				if ( -e $svg_path ) {
					my $svg_ref = BIGSdb::Utils::slurp($svg_path);
					$isolate_data->{$db}->{'svg'} = $$svg_ref;
					unlink $svg_path;
				}

			}
			$script->update_job( $job_id, { percent_complete => $progress } );
		}
		if ( keys %$isolate_data ) {
			store_results( $script, $isolate_id, $isolate_data );
		}

		$script->set_last_run_time( MODULE_NAME, $isolate_id );
		rmtree "$script->{'config'}->{'secure_tmp_dir'}/$job_id";

		say q(done.) if !$opts{'quiet'};
		$i++;
		last if $EXIT;
	}
	$script->stop_job( $job_id, { temp_init => 1 } );
	return;
}

sub store_results {
	my ( $self, $isolate_id, $data ) = @_;
	my $version = get_kaptive_version($self);
	my $json    = encode_json( { version => $version, data => $data } );
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

sub filter_ids_by_kaptive_view {
	my ( $self, $ids ) = @_;
	my $filtered = [];
	if ( !$self->{'system'}->{'kaptive_view'} ) {
		$filtered = $ids;
	} else {
		my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $ids );
		$filtered =
		  $self->{'datastore'}
		  ->run_query( "SELECT v.id FROM $self->{'system'}->{'kaptive_view'} v JOIN $temp_table t ON v.id=t.value",
			undef, { fetch => 'col_arrayref' } );

	}
	return $filtered;
}

sub tsv2arrayref {
	my ($tsv_file) = @_;
	open( my $fh, '<', $tsv_file ) || $logger->error("Could not open '$tsv_file': $!");
	my $tsv    = Text::CSV->new( { sep_char => "\t", binary => 1, auto_diag => 1 } );
	my $header = $tsv->getline($fh);
	$tsv->column_names(@$header);
	my $rows = [];
	while ( my $row = $tsv->getline_hr($fh) ) {
		push @$rows, $row;
	}
	close $fh;
	return $rows;
}

sub make_assembly_file {
	my ( $self, $job_id, $isolate_id ) = @_;
	my $filename   = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}/id-$isolate_id.fasta";
	my $seqbin_ids = $self->{'datastore'}->run_query( 'SELECT id FROM sequence_bin WHERE isolate_id=?',
		$isolate_id, { fetch => 'col_arrayref', cache => 'make_assembly_file::get_seqbin_list' } );
	my $contigs = $self->{'contigManager'}->get_contigs_by_list($seqbin_ids);
	make_path("$self->{'config'}->{'secure_tmp_dir'}/${job_id}");
	open( my $fh, '>', $filename ) || $logger->error("Cannot open $filename for writing.");
	foreach my $contig_id ( sort { $a <=> $b } keys %$contigs ) {
		say $fh ">$contig_id";
		say $fh $contigs->{$contig_id};
	}
	close $fh;
	return $filename;
}

sub get_kaptive_version {
	my ($self)  = @_;
	my $command = "$self->{'config'}->{'kaptive_path'} --version";
	my $version = `$command`;
	chomp $version;
	return $version;
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
    ${bold}update_kaptive.pl$norm - Perform/update Kaptive analysis

${bold}SYNOPSIS$norm
    ${bold}update_kaptive.pl$norm [${under}options$norm]

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
