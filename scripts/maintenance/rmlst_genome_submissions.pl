#!/usr/bin/env perl
#Perform/update species id check and store results in isolate database.
#Written by Keith Jolley
#Copyright (c) 2021-2022, University of Oxford
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
#Version: 20220913
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
use File::Type;
use Term::Cap;
use POSIX;
use MIME::Base64;
use LWP::UserAgent;
use Config::Tiny;
use Try::Tiny;
use JSON;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Uncompress::Unzip qw(unzip $UnzipError);
use Getopt::Long qw(:config no_ignore_case);
my %opts;
GetOptions(
	'database=s' => \$opts{'d'},
	'exclude=s'  => \$opts{'exclude'},
	'help'       => \$opts{'help'},
	'quiet'      => \$opts{'quiet'},
);
use constant URL => 'https://rest.pubmlst.org/db/pubmlst_rmlst_seqdef_kiosk/schemes/1/sequence';

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
perform_sanity_check();
my $EXIT = 0;
local @SIG{qw (INT TERM HUP)} = ( sub { $EXIT = 1 } ) x 3;    #Capture kill signals
main();
remove_lock_file();
local $| = 1;

sub perform_sanity_check {
	my $submission_dir = get_submission_dir();
	die "Submission directory is not defined.\n" if !$submission_dir;
	return;
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
	my $min_genome_size =
	  $script->{'system'}->{'min_genome_size'} // $script->{'config'}->{'min_genome_size'} // MIN_GENOME_SIZE;
	my $agent = LWP::UserAgent->new( agent => 'BIGSdb' );
	my $pending_submissions = $script->{'datastore'}->run_query(
		'SELECT id FROM submissions WHERE type IN (?,?) AND status=?',
		[ 'genomes', 'assemblies', 'pending' ],
		{ fetch => 'col_arrayref' }
	);
	my @submission_ids;
	my %submission_type;
	foreach my $submission_id (@$pending_submissions) {
		my $genome_count;
		my $type = $script->{'datastore'}
		  ->run_query( 'SELECT type FROM submissions WHERE id=?', $submission_id, { cache => 'get_submission_type' } );
		$submission_type{$submission_id} = $type;
		if ( $type eq 'genomes' ) {
			$genome_count =
			  $script->{'datastore'}
			  ->run_query( 'SELECT COUNT(DISTINCT index) FROM isolate_submission_isolates WHERE submission_id=?',
				$submission_id );
		} elsif ( $type eq 'assemblies' ) {
			$genome_count =
			  $script->{'datastore'}
			  ->run_query( 'SELECT COUNT(*) FROM assembly_submissions WHERE submission_id=?', $submission_id );
		}
		my $analysed_count = $script->{'datastore'}
		  ->run_query( 'SELECT COUNT(*) FROM genome_submission_analysis WHERE submission_id=?', $submission_id );
		next if $genome_count == $analysed_count;
		push @submission_ids, $submission_id;
	}
	my $plural = @submission_ids == 1 ? q() : q(s);
	my $count = @submission_ids;
	return if !$count;
	my $job_id = $script->add_job( 'RMLSTSubmission', { temp_init => 1 } );
	say qq(\n$config: $count submission$plural to analyse) if !$opts{'quiet'};
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
  SUBMISSION: foreach my $submission_id (@submission_ids) {
		say "Checking submission: $submission_id" if !$opts{'quiet'};
		my $indices;
		if ( $submission_type{$submission_id} eq 'genomes' ) {
			$indices =
			  $script->{'datastore'}->run_query(
				'SELECT DISTINCT index FROM isolate_submission_isolates WHERE submission_id=? ORDER BY index',
				$submission_id, { fetch => 'col_arrayref' } );
		} elsif ( $submission_type{$submission_id} eq 'assemblies' ) {
			$indices =
			  $script->{'datastore'}
			  ->run_query( 'SELECT index FROM assembly_submissions WHERE submission_id=? ORDER BY index',
				$submission_id, { fetch => 'col_arrayref' } );
		}
	  RECORD: foreach my $index (@$indices) {
			last RECORD if $EXIT;

			#Make sure submission hasn't handled and removed while we're scanning.
			next SUBMISSION
			  if !$script->{'datastore'}
			  ->run_query( 'SELECT EXISTS(SELECT * FROM submissions WHERE id=?)', $submission_id );
			my $already_done =
			  $script->{'datastore'}->run_query(
				'SELECT EXISTS(SELECT * FROM genome_submission_analysis WHERE (submission_id,name,index)=(?,?,?))',
				[ $submission_id, 'RMLSTSpecies', $index ] );
			print "Scanning record:$index ... " if !$opts{'quiet'};
			if ($already_done) {
				say 'already checked.' if !$opts{'quiet'};
				next RECORD;
			}
			my $fasta_ref = get_fasta( $script, $submission_id, $index );
			next if !ref $fasta_ref;
			my $payload = encode_json(
				{
					base64   => JSON::true(),
					details  => JSON::true(),
					sequence => encode_base64($$fasta_ref)
				}
			);
			my $result = $id_obj->make_rest_call( $index, URL, \$payload );
			if ( $result->{'data'}->{'taxon_prediction'} ) {
				my @predictions = @{ $result->{'data'}->{'taxon_prediction'} };
				my @taxa;
				push @taxa, $_->{'taxon'} foreach @predictions;
				local $" = q(, );
				say qq(@taxa.) if !$opts{'quiet'};
				store_result( $script, $submission_id, $index, $result );
			} elsif ( $result->{'response'}->code == 413 ) {
				say q(Too big.) if !$opts{'quiet'};
				store_failure( $script, $submission_id, $index, 'Failed - too many contigs' );
			} else {
				say q(no match.) if !$opts{'quiet'};
				store_failure( $script, $submission_id, $index, 'No match' );
			}
		}
	}
	$script->stop_job( $job_id, { temp_init => 1 } );
	return;
}

sub get_fasta {
	my ( $script, $submission_id, $index ) = @_;
	my $submission_dir = get_submission_dir();
	my $type           = $script->{'datastore'}
	  ->run_query( 'SELECT type FROM submissions WHERE id=?', $submission_id, { cache => 'get_submission_type' } );
	my $filename;
	if ( $type eq 'genomes' ) {
		$filename =
		  $script->{'datastore'}
		  ->run_query( 'SELECT value FROM isolate_submission_isolates WHERE (submission_id,index,field)=(?,?,?)',
			[ $submission_id, $index, 'assembly_filename' ] );
	} elsif ( $type eq 'assemblies' ) {
		$filename =
		  $script->{'datastore'}
		  ->run_query( 'SELECT filename FROM assembly_submissions WHERE (submission_id,index)=(?,?)',
			[ $submission_id, $index ] );
	}
	my $full_path = "$submission_dir/$submission_id/supporting_files/$filename";
	return if !-e $full_path;
	my $return_value;
	try {
		my $fasta     = BIGSdb::Utils::slurp($full_path);
		my $ft        = File::Type->new;
		my $file_type = $ft->checktype_contents($$fasta);
		my $uncompressed;
		my $method = {
			'application/x-gzip' =>
			  sub { gunzip $fasta => \$uncompressed or $logger->error("gunzip failed: $GunzipError"); },
			'application/zip' => sub { unzip $fasta => \$uncompressed or $logger->error("unzip failed: $UnzipError"); }
		};
		if ( $method->{$file_type} ) {
			$method->{$file_type}->();
			$return_value = \$uncompressed;
		} else {
			$return_value = $fasta;
		}
	}
	catch {
		$logger->error($_);
	};
	return $return_value;
}

sub store_result {
	my ( $script, $submission_id, $index, $record_result ) = @_;
	my ( $data, $result, $response ) = @{$record_result}{qw{data values response}};
	return if $response->code != 200;
	my $predictions = ref $result->{'rank'} eq 'ARRAY' ? @{ $result->{'rank'} } : 0;
	my $json;
	if ($predictions) {
		$json = encode_json( $data->{'taxon_prediction'} );
	} else {
		$json = encode_json { results => 'no match' };
	}
	eval {
		$script->{'db'}
		  ->do( 'INSERT INTO genome_submission_analysis (submission_id,name,index,results) VALUES (?,?,?,?)',
			undef, $submission_id, 'RMLSTSpecies', $index, $json );
	};
	if ($@) {
		$logger->error($@);
		$script->{'db'}->rollback;
	} else {
		$script->{'db'}->commit;
	}
	return;
}

sub store_failure {
	my ( $script, $submission_id, $index, $message ) = @_;
	my $json = encode_json( { failed => 1, message => $message } );
	eval {
		$script->{'db'}
		  ->do( 'INSERT INTO genome_submission_analysis (submission_id,name,index,results) VALUES (?,?,?,?)',
			undef, $submission_id, 'RMLSTSpecies', $index, $json );
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
	my $lock_file = "$lock_dir/rmlst_genome_submissions";
	return $lock_file;
}

sub remove_lock_file {
	my $lock_file = get_lock_file();
	unlink $lock_file;
	return;
}

sub get_submission_dir {
	my $config_dir = CONFIG_DIR;
	my $config     = Config::Tiny->read("$config_dir/bigsdb.conf");
	if ( !defined $config ) {
		$logger->fatal( 'Unable to read or parse bigsdb.conf file. Reason: ' . Config::Tiny->errstr );
		$config = Config::Tiny->new();
	}
	return $config->{_}->{'submission_dir'};
}

sub check_if_script_already_running {
	my $lock_file = get_lock_file();
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

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw/me md us/;
	say << "HELP";
${bold}NAME$norm
    ${bold}rmlst_genome_submissions.pl$norm - Perform species id check on 
    pending genome submissions

${bold}SYNOPSIS$norm
    ${bold}rmlst_genome_submissions.pl$norm [${under}options$norm]

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
HELP
	return;
}
