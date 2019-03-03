#!/usr/bin/env perl
#Define scheme profiles found in isolate database.
#Designed for uploading cgMLST profiles to the seqdef database.
#Written by Keith Jolley
#Copyright (c) 2016-2019, University of Oxford
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
#Version: 20190303
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
	PASSWORD         => undef,
	LOCK_DIR         => '/var/run/lock'         #Override in bigsdb.conf
};
#######End Local configuration#############################################
use lib (LIB_DIR);
use BIGSdb::Offline::Script;
use BIGSdb::Exceptions;
use Digest::MD5;
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
use Try::Tiny;

#User id for definer (there needs to be a record in the users table of the seqdef database)
use constant DEFINER_USER     => -1;
use constant DEFINER_USERNAME => 'autodefiner';

#Direct all library logging calls to screen
my $log_conf =
    qq(log4perl.category.BIGSdb.Script        = INFO, Screen\n)
  . qq(log4perl.category.BIGSdb.Dataconnector = WARN, Screen\n)
  . qq(log4perl.category.BIGSdb.Datastore     = WARN, Screen\n)
  . qq(log4perl.category.BIGSdb.Scheme        = WARN, Screen\n)
  . qq(log4perl.appender.Screen               = Log::Log4perl::Appender::Screen\n)
  . qq(log4perl.appender.Screen.stderr        = 1\n)
  . qq(log4perl.appender.Screen.layout        = Log::Log4perl::Layout::SimpleLayout\n);
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
my %opts;
GetOptions(
	'cache'                => \$opts{'cache'},
	'database=s'           => \$opts{'database'},
	'exclude_isolates=s'   => \$opts{'I'},
	'exclude_projects=s'   => \$opts{'P'},
	'help'                 => \$opts{'help'},
	'ignore_multiple_hits' => \$opts{'ignore_multiple_hits'},
	'isolates=s'           => \$opts{'i'},
	'isolate_list_file=s'  => \$opts{'isolate_list_file'},
	'match_missing'        => \$opts{'match_missing'},
	'max=i'                => \$opts{'y'},
	'min=i'                => \$opts{'x'},
	'min_size=i'           => \$opts{'m'},
	'missing=i'            => \$opts{'missing'},
	'projects=s'           => \$opts{'p'},
	'quiet'                => \$opts{'quiet'},
	'scheme=i'             => \$opts{'scheme_id'},
) or die("Error in command line arguments\n");
if ( $opts{'help'} ) {
	show_help();
	exit;
}
if ( !$opts{'database'} || !$opts{'scheme_id'} ) {
	say "\nUsage: define_profiles.pl --database <NAME> --scheme <SCHEME ID>\n";
	say 'Help: define_profiles.pl --help';
	exit;
}
my $script = BIGSdb::Offline::Script->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		host             => HOST,
		port             => PORT,
		user             => USER,
		password         => PASSWORD,
		options          => \%opts,
		instance         => $opts{'database'},
		logger           => $logger
	}
);
die "This script can only be run against an isolate database.\n"
  if ( $script->{'system'}->{'dbtype'} // '' ) ne 'isolates';
perform_sanity_checks();
get_existing_alleles();
local $| = 1;
$script->initiate_job_manager if $script->{'config'}->{'jobs_db'};
$script->{'options'}->{'mark_job'} = 1;
my $job_id = $script->add_job('DefineProfiles');
main();
remove_lock_file();
$script->stop_job($job_id);
undef $script;

sub main {
	my $isolates     = $script->get_isolates;
	my $isolate_list = $script->filter_and_sort_isolates($isolates);
	my $scheme       = $script->{'datastore'}->get_scheme( $opts{'scheme_id'} );
	my $scheme_info  = $script->{'datastore'}->get_scheme_info( $opts{'scheme_id'} );
	my $view         = $scheme_info->{'view'};
	my $need_to_refresh_cache;
	foreach my $isolate_id (@$isolate_list) {
		next if defined_in_cache($isolate_id);
		next if filtered_out_by_view( $view, $isolate_id );
		my ( $profile, $designations, $missing ) = get_profile($isolate_id);
		next if $missing > $opts{'missing'};
		my $field_values =
		  $scheme->get_field_values_by_designations( $designations,
			{ dont_match_missing_loci => $opts{'match_missing'} ? 0 : 1 } );
		next if @$field_values;                                 #Already defined
		print "Isolate id: $isolate_id; " if !$opts{'quiet'};
		define_new_profile($designations);
		$need_to_refresh_cache = 1;
	}
	refresh_caches() if $need_to_refresh_cache;
	return;
}

sub get_existing_alleles {
	my $db        = get_seqdef_db();
	my $scheme_id = get_remote_scheme_id();
	my $data      = $script->{'datastore'}->run_query(
		'SELECT locus,allele_id FROM sequences WHERE locus IN '
		  . '(SELECT locus FROM scheme_members WHERE scheme_id=?)',
		$scheme_id,
		{ db => $db, fetch => 'all_arrayref' }
	);
	foreach my $allele (@$data) {
		$script->{'existing'}->{ $allele->[0] }->{ $allele->[1] } = 1;
	}
	return;
}

sub define_new_profile {
	my ($designations)   = @_;
	my $db               = get_seqdef_db();
	my $scheme_id        = get_remote_scheme_id();
	my $next_pk          = get_next_pk();
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	$script->{'new_missing_awaiting_commit'} = [];
	my $failed;
	eval {
		$db->do(
			'INSERT INTO profiles (scheme_id,profile_id,sender,curator,date_entered,datestamp) VALUES (?,?,?,?,?,?)',
			undef, $scheme_id, $next_pk, DEFINER_USER, DEFINER_USER, 'now', 'now' );
		$db->do(
			'INSERT INTO profile_fields (scheme_id,scheme_field,profile_id,value,curator,datestamp) '
			  . 'VALUES (?,?,?,?,?,?)',
			undef, $scheme_id, $script->{'primary_key'}, $next_pk, $next_pk, DEFINER_USER, 'now'
		);
		my $loci = $script->{'datastore'}->run_query( 'SELECT locus,profile_name FROM scheme_members WHERE scheme_id=?',
			$opts{'scheme_id'}, { fetch => 'all_arrayref', slice => {} } );
		my @allele_data;
		foreach my $locus (@$loci) {
			my $locus_name = $locus->{'profile_name'} // $locus->{'locus'};
			my $allele_id = $designations->{ $locus->{'locus'} }->[0]->{'allele_id'};
			$allele_id = 'N' if $allele_id eq '0';
			if ( allele_exists( $locus_name, $allele_id ) ) {
				push @allele_data, [ $locus_name, $scheme_id, $next_pk, $allele_id, DEFINER_USER, 'now' ];
			} else {
				say "Allele $locus->{'locus'}-$allele_id has not been defined.";
				$failed = 1;
			}
			last if $failed;
		}
		if ( @allele_data && !$failed ) {
			$db->do('ALTER TABLE profile_members DISABLE TRIGGER modify_profile_member');
			$db->do('COPY profile_members(locus,scheme_id,profile_id,allele_id,curator,datestamp) FROM STDIN');
			local $" = "\t";
			foreach my $alleles (@allele_data) {
				$db->pg_putcopydata("@$alleles\n");
			}
			$db->pg_putcopyend;
			$db->do(
				"UPDATE $scheme_warehouse SET profile=ARRAY(SELECT allele_id FROM profile_members WHERE "
				  . "(scheme_id,profile_id)=(?,?) ORDER BY locus) WHERE $script->{'primary_key'}=?",
				undef, $scheme_id, $next_pk, $next_pk
			);
			$db->do('ALTER TABLE profile_members ENABLE TRIGGER modify_profile_member');
		}
	};
	if ( $@ || $failed ) {
		if ($@) {
			if ( $@ =~ /must\ be\ owner\ of\ relation\ profile_members/x ) {
				$logger->error('The profile_members table must be owned by apache.');
			} else {
				$logger->error($@);
			}
		}
		$db->rollback;
		return;
	}
	$db->commit;
	if ( @{ $script->{'new_missing_awaiting_commit'} } ) {
		foreach my $locus ( @{ $script->{'new_missing_awaiting_commit'} } ) {
			$script->{'existing'}->{$locus}->{'N'} = 1;
		}
		$script->{'new_missing_awaiting_commit'} = [];
	}
	say "$script->{'primary_key'}-$next_pk assigned." if !$opts{'quiet'};
	return;
}

sub allele_exists {
	my ( $locus, $allele_id ) = @_;
	return 1 if $script->{'existing'}->{$locus}->{$allele_id};
	if ( $allele_id eq 'N' ) {
		define_missing_allele($locus);
		return 1;
	}
	return;
}

sub define_missing_allele {
	my ($locus) = @_;
	my $db = get_seqdef_db();
	$db->do(
		'INSERT INTO sequences (locus,allele_id,sequence,sender,curator,date_entered,datestamp,status) '
		  . 'VALUES (?,?,?,?,?,?,?,?)',
		undef, $locus, 'N', 'arbitrary allele', 0, 0, 'now', 'now', ''
	);
	push @{ $script->{'new_missing_awaiting_commit'} }, $locus;

	#Don't commit here - this is part of the transaction and errors are trapped in calling method.
	return;
}

sub get_next_pk {
	my $db        = get_seqdef_db();
	my $scheme_id = get_remote_scheme_id();
	my $qry =
	    'SELECT CAST(profile_id AS int) FROM profiles WHERE scheme_id=? AND '
	  . 'CAST(profile_id AS int)>0 UNION SELECT CAST(profile_id AS int) FROM retired_profiles '
	  . 'WHERE scheme_id=? ORDER BY profile_id';
	my $test = 0;
	my $next = 0;
	my $id   = 0;
	my $profiles =
	  $script->{'datastore'}
	  ->run_query( $qry, [ $scheme_id, $scheme_id ], { db => $db, fetch => 'col_arrayref', cache => 'get_next_pk' } );
	foreach my $profile_id (@$profiles) {
		$test++;
		$id = $profile_id;
		if ( $test != $id ) {
			$next = $test;
			return $next;
		}
	}
	if ( $next == 0 ) {
		$next = $id + 1;
	}
	return $next;
}

sub get_profile {
	my ($isolate_id) = @_;
	my $all_designations = $script->{'datastore'}->get_scheme_allele_designations( $isolate_id, $opts{'scheme_id'} );
	my @profile;
	my $designations = {};
	my $missing      = 0;
	if ( !$script->{'cache'}->{'scheme_loci'} ) {
		$script->{'cache'}->{'scheme_loci'} = [];
		my $db               = get_seqdef_db();
		my $remote_scheme_id = get_remote_scheme_id();
		my $loci =
		  $script->{'datastore'}
		  ->run_query( 'SELECT locus FROM scheme_warehouse_indices WHERE scheme_id=? ORDER BY index',
			$remote_scheme_id, { db => $db, fetch => 'col_arrayref', cache => 'get_profile:loci' } );
		foreach my $profile_locus (@$loci) {
			my $locus_name = $script->{'datastore'}->run_query(
				'SELECT locus FROM scheme_members WHERE (scheme_id,profile_name)=(?,?)',
				[ $opts{'scheme_id'}, $profile_locus ],
				{ cache => 'get_profile:profile_name' }
			);
			push @{ $script->{'cache'}->{'scheme_loci'} }, ( $locus_name // $profile_locus );
		}
	}
	foreach my $locus ( @{ $script->{'cache'}->{'scheme_loci'} } ) {
		my $value;
		my $locus_designations = $all_designations->{$locus};
		$locus_designations //= [];
		if ( @$locus_designations == 0 ) {
			$value = 'N';
		} elsif ( @$locus_designations == 1 ) {
			$value = $locus_designations->[0]->{'allele_id'};
		} else {
			$value = $opts{'ignore_multiple_hits'} ? 'N' : $locus_designations->[0]->{'allele_id'};
		}
		push @profile, $value;
		$missing++ if $value eq 'N';
		$designations->{$locus} = [ { allele_id => $value, status => 'confirmed' } ];
	}
	return \@profile, $designations, $missing;
}

sub perform_sanity_checks {
	check_if_script_already_running();
	check_scheme_exists();
	check_user_exists();
	check_scheme_properly_defined();
	check_allowed_missing();
	return;
}

sub check_scheme_exists {
	my $scheme_info = $script->{'datastore'}->get_scheme_info( $opts{'scheme_id'} );
	die "Scheme $opts{'scheme_id'} does not exist.\n" if !$scheme_info;
	return;
}

sub check_user_exists {
	my $db     = get_seqdef_db();
	my $exists = $script->{'datastore'}->run_query(
		'SELECT EXISTS(SELECT * FROM users WHERE (id,user_name)=(?,?))',
		[ DEFINER_USER, DEFINER_USERNAME ],
		{ db => $db }
	);
	die "The autodefiner user does not exist in the seqdef users table.\n" if !$exists;
	return;
}

sub get_remote_scheme_id {
	my $db = get_seqdef_db();
	my $scheme_info = $script->{'datastore'}->get_scheme_info( $opts{'scheme_id'}, { get_pk => 1 } );
	return $scheme_info->{'dbase_id'} if $scheme_info->{'dbase_id'};
	die "The scheme id in the seqdef database is not properly set for this scheme in the isolate database.\n";
}

sub check_scheme_properly_defined {
	my $db               = get_seqdef_db();
	my $scheme_info      = $script->{'datastore'}->get_scheme_info( $opts{'scheme_id'}, { get_pk => 1 } );
	my $remote_scheme_id = get_remote_scheme_id();
	if ( !$scheme_info->{'primary_key'} ) {
		die "No primary key field has been set for this scheme in the isolate database.\n";
	}
	$script->{'primary_key'} = $scheme_info->{'primary_key'};
	my $remote_scheme =
	  $script->{'datastore'}
	  ->run_query( 'SELECT * FROM schemes WHERE id=?', $remote_scheme_id, { db => $db, fetch => 'row_hashref' } );
	die "The scheme does not exist in the seqdef database.\n" if !$remote_scheme;
	my $loci = $script->{'datastore'}->run_query( 'SELECT locus,profile_name FROM scheme_members WHERE scheme_id=?',
		$opts{'scheme_id'}, { fetch => 'all_arrayref', slice => {} } );
	my $remote_loci = $script->{'datastore'}->run_query( 'SELECT locus FROM scheme_members WHERE scheme_id=?',
		$remote_scheme_id, { db => $db, fetch => 'col_arrayref' } );
	my ( $remote_count, $local_count ) = ( scalar @$remote_loci, scalar @$loci );
	die "The scheme in the isolate database has $local_count loci\n"
	  . "while the scheme in the seqdef database has $remote_count loci.\n"
	  if $remote_count != $local_count;

	foreach my $locus (@$loci) {
		my $locus_exists_in_seqdef_scheme = $script->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM scheme_members WHERE (scheme_id,locus)=(?,?))',
			[ $remote_scheme_id, ( $locus->{'profile_name'} // $locus->{'locus'} ) ],
			{ db => $db, cache => 'check_scheme_properly_defined::loci' }
		);
		die "Locus $locus->{'locus'} does not exist in the seqdef database scheme.\n"
		  if !$locus_exists_in_seqdef_scheme;
	}
	my $remote_pk = $script->{'datastore'}->run_query( 'SELECT * FROM scheme_fields WHERE scheme_id=? AND primary_key',
		$remote_scheme_id, { db => $db, fetch => 'row_hashref' } );
	die "No primary key field is set for the scheme in the seqdef database.\n" if !$remote_pk;
	die "Remote primary key is not an integer field.\n" if $remote_pk->{'type'} ne 'integer';
	die "The primary key fields do not match in the isolate and seqdef databases.\n"
	  if $scheme_info->{'primary_key'} ne $remote_pk->{'field'};
	return;
}

sub check_allowed_missing {
	my $db               = get_seqdef_db();
	my $remote_scheme_id = get_remote_scheme_id();
	my $remote_scheme =
	  $script->{'datastore'}
	  ->run_query( 'SELECT * FROM schemes WHERE id=?', $remote_scheme_id, { db => $db, fetch => 'row_hashref' } );
	if ( !$remote_scheme->{'allow_missing_loci'} && $opts{'missing'} ) {
		say "The remote scheme does not allow missing alleles in the profile - \n" . 'setting --missing to 0.';
		$opts{'missing'} = 0;
	}
	$opts{'missing'} //= 0;
	return;
}

sub get_seqdef_db {
	my $data_connector = $script->{'datastore'}->get_data_connector;
	my $scheme_info    = $script->{'datastore'}->get_scheme_info( $opts{'scheme_id'} );
	my $seqdef_db;
	try {
		$seqdef_db = $data_connector->get_connection(
			{
				host       => $scheme_info->{'dbase_host'},
				port       => $scheme_info->{'dbase_port'},
				user       => $scheme_info->{'dbase_user'},
				password   => $scheme_info->{'dbase_password'},
				dbase_name => $scheme_info->{'dbase_name'}
			}
		);
	}
	catch {
		if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
			$script->{'logger'}->error('Cannot connect to seqdef database');
			say 'Cannot connect to seqdef database';
		} else {
			$logger->logdie($_);
		}
	};
	exit(1) if !$seqdef_db;
	return $seqdef_db;
}

sub refresh_caches {
	return if !$opts{'cache'};
	say 'Refreshing caches...' if !$opts{'quiet'};
	$script->{'datastore'}
	  ->create_temp_isolate_scheme_fields_view( $opts{'scheme_id'}, { cache => 1, method => 'incremental' } );
	$script->{'datastore'}
	  ->create_temp_scheme_status_table( $opts{'scheme_id'}, { cache => 1, method => 'incremental' } );
	return;
}

sub defined_in_cache {
	my ($isolate_id) = @_;
	my $table = "temp_isolates_scheme_fields_$opts{'scheme_id'}";
	my $cache_exists =
	  $script->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)',
		$table, { cache => 'defined_in_cache::table_exists' } );
	return if !$cache_exists;
	return $script->{'datastore'}->run_query( "SELECT EXISTS(SELECT * FROM $table WHERE id=?)",
		$isolate_id, { cache => 'defined_in_cache::isolate_found' } );
}

sub filtered_out_by_view {
	my ( $view, $isolate_id ) = @_;
	return if !defined $view;
	return !$script->{'datastore'}->is_isolate_in_view( $view, $isolate_id );
}

sub get_lock_file {
	my $hash      = Digest::MD5::md5_hex("$0||$opts{'database'}||$opts{'scheme_id'}");
	my $lock_dir = $script->{'config'}->{'lock_dir'} // LOCK_DIR;
	my $lock_file = "$lock_dir/BIGSdb_define_profiles_$hash";
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
		open( my $fh, '<', $lock_file ) || $script->{'logger'}->error("Cannot open lock file $lock_file for reading");
		my $pid = <$fh>;
		close $fh;
		my $pid_exists = kill( 0, $pid );
		if ( !$pid_exists ) {
			say 'Lock file exists but process is no longer running - deleting lock.';
			unlink $lock_file;
		} else {
			undef $script;
			die "Script already running with these parameters - terminating.\n";
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
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw(me md us);
	say << "HELP";
${bold}NAME$norm
    ${bold}define_profiles.pl$norm - Define scheme profiles found in isolate database
    
${bold}SYNOPSIS$norm
    ${bold}define_profiles.pl --database ${under}NAME$norm${bold} --scheme ${under}SCHEME_ID$norm [${under}options$norm]

${bold}OPTIONS$norm

${bold}--cache$norm
    Update scheme field cache in isolate database.

${bold}--database$norm ${under}NAME$norm
    Database configuration name.
    
${bold}--help$norm
    This help page.
    
${bold}--exclude_isolates$norm ${under}LIST$norm
    Comma-separated list of isolate ids to ignore.
    
${bold}--exclude_projects$norm ${under}LIST$norm
    Comma-separated list of projects whose isolates will be excluded.
    
${bold}--ignore_multiple_hits$norm
    Set allele designation to 'N' if there are multiple designations set for
    a locus. The default is to use the lowest allele value in the profile
    definition.
 
${bold}--isolates$norm ${under}LIST$norm
    Comma-separated list of isolate ids to scan (ignored if -p used).
    
${bold}--isolate_list_file$norm ${under}FILE$norm  
    File containing list of isolate ids (ignored if -i or -p used).
    
${bold}--match_missing$norm
    Treat missing loci as specific alleles rather than 'any'. This will 
    allow profiles for every isolate that has <= threshold of missing alleles 
    to be defined but may result in some isolates having >1 ST.
             
${bold}--max$norm ${under}ID$norm
    Maximum isolate id.
    
${bold}--min$norm ${under}ID$norm
    Minimum isolate id.
    
${bold}--min_size$norm ${under}SIZE$norm
    Minimum size of seqbin (bp) - limit search to isolates with at least this
    much sequence.
    
${bold}--missing$norm ${under}NUMBER$norm
    Set the number of loci that are allowed to be missing in the profile. If
    the remote scheme does not allow missing loci then this number will be set
    to 0.  Default=0.
    
${bold}--projects$norm ${under}LIST$norm
    Comma-separated list of project isolates to scan.
    
${bold}--quiet$norm
    Suppress normal output.
 
${bold}--scheme$norm ${under}SCHEME_ID$norm
    Scheme id number.
         
HELP
	return;
}
