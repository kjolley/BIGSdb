#!/usr/bin/perl
#Script to cluster cgMLST profiles using classification groups
#Written by Keith Jolley
#Copyright (c) 2016, University of Oxford
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
	PASSWORD         => undef
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
GetOptions( 'cscheme=i' => \$opts{'cscheme_id'}, 'database=s' => \$opts{'database'}, 'help' => \$opts{'help'}, )
  or die("Error in command line arguments\n");
if ( $opts{'help'} ) {
	show_help();
	exit;
}
if ( !$opts{'database'} || !$opts{'cscheme_id'} ) {
	say "\nUsage: define_profiles.pl --database <NAME> --cscheme_id <SCHEME ID>\n";
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
main();
$script->db_disconnect;

sub perform_sanity_checks {
	check_cscheme_exists();
	check_user_exists();
	check_cscheme_properly_defined();
	return;
}

#TODO Remove primary_key field from classification_group_fields
sub main {
	my $profiles    = get_ungrouped_profiles();
	my $cg_info     = get_cg_scheme_info();
	my $scheme_info = $script->{'datastore'}->get_scheme_info( $cg_info->{'scheme_id'}, { get_pk => 1 } );
	my $pk          = $scheme_info->{'primary_key'};
  ITERATION: while (1) {
	  PROFILE: foreach my $profile_id (@$profiles) {
			next PROFILE if profile_in_group($profile_id);
			my $pg_method = $cg_info->{'use_relative_threshold'} ? 'matching_profiles_with_relative_threshold' : 'matching_profiles';
			my $possible_groups = $script->{'datastore'}->run_query(
				'SELECT DISTINCT(group_id) FROM classification_group_profiles WHERE cg_scheme_id=? AND profile_id IN '
				  . "(SELECT $pg_method(?,?,?))",
				[ $opts{'cscheme_id'}, $cg_info->{'scheme_id'}, $profile_id, $cg_info->{'inclusion_threshold'} ],
				{ fetch => 'col_arrayref', cache => 'matching_profiles' }
			);
			if (@$possible_groups) {
				if ( @$possible_groups == 1 ) {
					add_profile_to_group( $possible_groups->[0], $profile_id );
					say "Adding $pk-$profile_id to exisiting group $possible_groups->[0].";
					next ITERATION;
				} else {
					local $" = ',';
					say "$pk-$profile_id: multiple possible groups: @$possible_groups";

					#TODO Assign to correct group and merge groups
				}
			} else {
				my $new_group = create_group($profile_id);
				add_profile_to_group( $new_group, $profile_id );
				say "New group: $new_group. Adding $pk-$profile_id";
				next ITERATION;
			}
		}
		last ITERATION;
	}
	return;
}

sub profile_in_group {
	my ($profile_id) = @_;
	return $script->{'datastore'}->run_query(
		'SELECT EXISTS(SELECT * FROM classification_group_profiles WHERE (cg_scheme_id,profile_id)=(?,?))',
		[ $opts{'cscheme_id'}, $profile_id ],
		{ cache => 'profile_in_group' }
	);
}

sub create_group {
	my ($profile_id) = @_;
	my $new_group_id =
	  $script->{'datastore'}
	  ->run_query( 'SELECT COALESCE((MAX(group_id)+1),1) FROM classification_groups WHERE cg_scheme_id=?',
		$opts{'cscheme_id'}, { cache => 'create_group:next_id' } );
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
	my $cg_scheme_info = get_cg_scheme_info();
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
	return;
}

sub check_cscheme_properly_defined {
	my $cg_scheme_info = get_cg_scheme_info();
	my $scheme_info = $script->{'datastore'}->get_scheme_info( $cg_scheme_info->{'scheme_id'}, { get_pk => 1 } );
	if ( !$scheme_info->{'primary_key'} ) {
		die "No primary key field has been set for scheme $scheme_info->{'id'} ($scheme_info->{'description'}).\n";
	}
	return;
}

sub get_ungrouped_profiles {
	if ( !$script->{'cache'}->{'get_ungrouped_profiles'} ) {
		my $scheme_id = get_cg_scheme_info()->{'scheme_id'};
		my $scheme_info = $script->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
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

sub get_cg_scheme_info {
	return $script->{'datastore'}->run_query( 'SELECT * FROM classification_group_schemes WHERE id=?',
		$opts{'cscheme_id'}, { fetch => 'row_hashref' } );
}

sub check_cscheme_exists {
	my $exists =
	  $script->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM classification_group_schemes WHERE id=?)', $opts{'cscheme_id'} );
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
    ${bold}cluster.pl --database ${under}NAME$norm${bold} --cscheme_id ${under}SCHEME_ID$norm [${under}options$norm]

${bold}OPTIONS$norm

${bold}--cscheme$norm ${under}CLASSIFICATION_SCHEME_ID$norm
    Classification scheme id number.

${bold}--database$norm ${under}NAME$norm
    Database configuration name.
    
${bold}--help$norm
    This help page.
           
HELP
	return;
}
