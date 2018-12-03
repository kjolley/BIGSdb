#!/usr/bin/env perl
#Script to cluster cgMLST profiles using classification groups
#Written by Keith Jolley
#Copyright (c) 2016-2018, University of Oxford
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
#Version: 20181203
use strict;
use warnings;
use List::Util qw(min);
use Digest::MD5;
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
	LOCK_DIR         => '/var/run/lock'
};
#######End Local configuration#############################################
use lib (LIB_DIR);
use BIGSdb::Offline::Script;
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;

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
	'cscheme=i'  => \$opts{'cscheme_id'},
	'database=s' => \$opts{'database'},
	'help'       => \$opts{'help'},
	'quiet'      => \$opts{'quiet'},
	'reset'      => \$opts{'reset'}
) or die("Error in command line arguments\n");
if ( $opts{'help'} ) {
	show_help();
	exit;
}
if ( !$opts{'database'} || !$opts{'cscheme_id'} ) {
	say "\nUsage: define_profiles.pl --database <NAME> --cscheme <SCHEME ID>\n";
	say 'Help: cluster.pl --help';
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
die "This script can only be run against a seqdef database.\n"
  if ( $script->{'system'}->{'dbtype'} // '' ) ne 'sequences';
perform_sanity_checks();
if ( $opts{'reset'} ) {
	reset_scheme();
	exit;
}
main();
remove_lock_file();
undef $script;

sub perform_sanity_checks {
	check_if_script_already_running();
	check_cscheme_exists();
	check_user_exists();
	check_cscheme_properly_defined();
	return;
}

sub main {
	my $profiles    = get_ungrouped_profiles();
	my $cg_info     = get_cscheme_info();
	my $scheme_info = $script->{'datastore'}->get_scheme_info( $cg_info->{'scheme_id'}, { get_pk => 1 } );
	$script->{'pk'} = $scheme_info->{'primary_key'};
	$script->{'grouped_profiles'} = { map { $_ => 1 } @{ get_grouped_profiles() } };
  ITERATION: while (1) {
	  PROFILE: foreach my $profile_id (@$profiles) {
			next PROFILE if $script->{'grouped_profiles'}->{$profile_id};
			my $pg_method =
			  $cg_info->{'use_relative_threshold'}
			  ? 'matching_profiles_with_relative_threshold_cg'
			  : 'matching_profiles_cg';
			my $possible_groups = $script->{'datastore'}->run_query(
				'SELECT DISTINCT(group_id) FROM classification_group_profiles WHERE cg_scheme_id=? AND profile_id IN '
				  . "(SELECT $pg_method(?,?,?)) ORDER BY group_id",
				[ $opts{'cscheme_id'}, $opts{'cscheme_id'}, $profile_id, $cg_info->{'inclusion_threshold'} ],
				{ fetch => 'col_arrayref', cache => 'matching_profiles' }
			);
			if (@$possible_groups) {
				if ( @$possible_groups == 1 ) {
					add_profile_to_group( $possible_groups->[0], $profile_id );
					next ITERATION;
				} else {
					local $" = ',';
					say "$script->{'pk'}-$profile_id: multiple possible groups: @$possible_groups" if !$opts{'quiet'};
					my $largest_groups = get_largest_groups($possible_groups);
					if ( @$largest_groups == 1 ) {
						add_profile_to_group( $largest_groups->[0], $profile_id );
						merge_groups( $possible_groups, $largest_groups->[0],
							"Merging due to $script->{'pk'}-$profile_id" );
					} else {
						my $smallest_group_id = min @$largest_groups;
						add_profile_to_group( $smallest_group_id, $profile_id );
						merge_groups( $possible_groups, $smallest_group_id,
							"Merging due to $script->{'pk'}-$profile_id" );
					}
				}
			} else {
				my $new_group = create_group($profile_id);
				add_profile_to_group( $new_group, $profile_id );
				next ITERATION;
			}
		}
		last ITERATION;
	}
	return;
}

sub reset_scheme {
	eval {
		$script->{'db'}->do( 'DELETE FROM classification_groups WHERE cg_scheme_id=?', undef, $opts{'cscheme_id'} );
	};
	if ($@) {
		$script->{'db'}->rollback;
		die "$@\n";
	}
	$script->{'db'}->commit;
	say "Classification group $opts{'cscheme_id'} reset.";
	return;
}

sub merge_groups {
	my ( $groups, $merged_group_id, $comment ) = @_;
	my $scheme_id = get_cscheme_info()->{'scheme_id'};
	foreach my $group_id (@$groups) {
		next if $group_id == $merged_group_id;
		my $profiles = get_profiles_in_group($group_id);
		foreach my $profile_id (@$profiles) {
			eval {
				$script->{'db'}
				  ->do( 'UPDATE classification_group_profiles SET group_id=? WHERE (cg_scheme_id,profile_id)=(?,?)',
					undef, $merged_group_id, $opts{'cscheme_id'}, $profile_id );
				$script->{'db'}
				  ->do( 'UPDATE classification_groups SET active=false WHERE (cg_scheme_id,group_id)=(?,?)',
					undef, $opts{'cscheme_id'}, $group_id );
				$script->{'db'}->do(
					'INSERT INTO classification_group_profile_history (timestamp,scheme_id,profile_id,'
					  . 'cg_scheme_id,previous_group,comment) VALUES (?,?,?,?,?,?)',
					undef, 'now', $scheme_id, $profile_id, $opts{'cscheme_id'}, $group_id, $comment
				);
			};
			if ($@) {
				$script->{'db'}->rollback;
				die "$@\n";
			}
		}
		$script->{'db'}->commit;
		say "Group $group_id merged in to group $merged_group_id." if !$opts{'quiet'};
	}
	return;
}

sub get_profiles_in_group {
	my ($group_id) = @_;
	return $script->{'datastore'}->run_query(
		'SELECT profile_id FROM classification_group_profiles WHERE (cg_scheme_id,group_id)=(?,?)',
		[ $opts{'cscheme_id'}, $group_id ],
		{ fetch => 'col_arrayref', cache => 'get_profiles_in_group' }
	);
}

sub get_largest_groups {
	my ($groups) = @_;
	my @largest_groups;
	my $largest_size = 0;
	foreach my $group_id (@$groups) {
		my $size = get_group_size($group_id);
		if ( $size == $largest_size ) {
			push @largest_groups, $group_id;
		} elsif ( $size > $largest_size ) {
			@largest_groups = ($group_id);
			$largest_size   = $size;
		}
	}
	return \@largest_groups;
}

sub get_group_size {
	my ($group_id) = @_;
	return $script->{'datastore'}->run_query(
		'SELECT COUNT(*) FROM classification_group_profiles WHERE (cg_scheme_id,group_id)=(?,?)',
		[ $opts{'cscheme_id'}, $group_id ],
		{ cache => 'get_group_size' }
	);
}

sub get_grouped_profiles {
	return $script->{'datastore'}
	  ->run_query( 'SELECT profile_id FROM classification_group_profiles WHERE cg_scheme_id=?',
		$opts{'cscheme_id'}, { fetch => 'col_arrayref' } );
}

sub create_group {
	my ($profile_id) = @_;
	my $new_group_id =
	  $script->{'datastore'}
	  ->run_query( 'SELECT COALESCE((MAX(group_id)+1),1) FROM classification_groups WHERE cg_scheme_id=?',
		$opts{'cscheme_id'}, { cache => 'create_group:next_id' } );
	say "New group: $new_group_id." if !$opts{'quiet'};
	eval {
		$script->{'db'}
		  ->do( 'INSERT INTO classification_groups (cg_scheme_id,group_id,active,curator,datestamp) VALUES (?,?,?,?,?)',
			undef, $opts{'cscheme_id'}, $new_group_id, 'true', DEFINER_USER, 'now' );
	};
	if ($@) {
		$script->{'db'}->rollback;
		$logger->logdie($@);
	}
	$script->{'db'}->commit;
	return $new_group_id;
}

sub add_profile_to_group {
	my ( $group_id, $profile_id ) = @_;
	my $cg_scheme_info = get_cscheme_info();
	say "Adding $script->{'pk'}-$profile_id to group $group_id." if !$opts{'quiet'};
	eval {
		$script->{'db'}->do(
			'INSERT INTO classification_group_profiles (cg_scheme_id,group_id,profile_id,'
			  . 'scheme_id,curator,datestamp) VALUES (?,?,?,?,?,?)',
			undef, $opts{'cscheme_id'}, $group_id, $profile_id, $cg_scheme_info->{'scheme_id'}, DEFINER_USER, 'now'
		);
	};
	if ($@) {
		$script->{'db'}->rollback;
		$logger->logdie($@);
	}
	$script->{'db'}->commit;
	$script->{'grouped_profiles'}->{$profile_id} = 1;
	return;
}

sub get_lock_file {
	my $hash      = Digest::MD5::md5_hex("$0||$opts{'database'}||$opts{'cscheme_id'}");
	my $lock_file = LOCK_DIR . "/BIGSdb_cluster_$hash";
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

sub check_cscheme_properly_defined {
	my $cg_scheme_info = get_cscheme_info();
	my $scheme_info = $script->{'datastore'}->get_scheme_info( $cg_scheme_info->{'scheme_id'}, { get_pk => 1 } );
	if ( !$scheme_info->{'primary_key'} ) {
		die "No primary key field has been set for scheme $scheme_info->{'id'} ($scheme_info->{'name'}).\n";
	}
	return;
}

sub get_ungrouped_profiles {
	if ( !$script->{'cache'}->{'get_ungrouped_profiles'} ) {
		my $scheme_id     = get_cscheme_info()->{'scheme_id'};
		my $scheme_info   = $script->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		my $pk_field_info = $script->{'datastore'}->get_scheme_field_info( $scheme_id, $scheme_info->{'primary_key'} );
		my $qry           = "SELECT profile_id FROM profiles WHERE scheme_id=$scheme_id AND profile_id NOT IN "
		  . '(SELECT profile_id FROM classification_group_profiles WHERE cg_scheme_id=?) ORDER BY ';
		$qry .=
		  $pk_field_info->{'type'} eq 'integer'
		  ? 'CAST(profile_id AS integer)'
		  : 'profile_id';
		$script->{'cache'}->{'get_ungrouped_profiles'} = $qry;
	}
	return $script->{'datastore'}->run_query( $script->{'cache'}->{'get_ungrouped_profiles'},
		$opts{'cscheme_id'}, { fetch => 'col_arrayref', cache => 'get_ungrouped_profiles' } );
}

sub get_cscheme_info {
	return $script->{'datastore'}
	  ->run_query( 'SELECT * FROM classification_schemes WHERE id=?', $opts{'cscheme_id'}, { fetch => 'row_hashref' } );
}

sub check_cscheme_exists {
	my $exists =
	  $script->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM classification_schemes WHERE id=?)', $opts{'cscheme_id'} );
	die "Scheme $opts{'cscheme_id'} does not exist.\n" if !$exists;
	return;
}

sub check_user_exists {
	my $exists =
	  $script->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM users WHERE (id,user_name)=(?,?))',
		[ DEFINER_USER, DEFINER_USERNAME ] );
	die "The autodefiner user does not exist.\n" if !$exists;
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
    ${bold}cluster.pl$norm - Cluster cgMLST profiles using classification groups.
    
${bold}SYNOPSIS$norm
    ${bold}cluster.pl --database ${under}NAME$norm${bold} --cscheme ${under}SCHEME_ID$norm [${under}options$norm]

${bold}OPTIONS$norm

${bold}--cscheme$norm ${under}CLASSIFICATION_SCHEME_ID$norm
    Classification scheme id number.

${bold}--database$norm ${under}NAME$norm
    Database configuration name.
    
${bold}--help$norm
    This help page.
    
${bold}--quiet$norm
    Suppress normal output.
    
${bold}--reset$norm
    Remove all groups and profiles currently defined for classification group.          
HELP
	return;
}
