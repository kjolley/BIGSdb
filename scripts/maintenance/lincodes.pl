#!/usr/bin/env perl
#Define LINcodes from cgMLST profiles
#Written by Keith Jolley
#Based on code by Melanie Hennart (https://gitlab.pasteur.fr/BEBP/LINcoding).
#Copyright (c) 2022, University of Oxford
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
#Version: 20220216
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
use BIGSdb::Constants qw(LOG_TO_SCREEN);
use Term::Cap;
use PDL;

#Direct all library logging calls to screen
my $log_conf = LOG_TO_SCREEN;
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
use Getopt::Long qw(:config no_ignore_case);
my %opts;
GetOptions(
	'd|database=s'  => \$opts{'d'},
	'init_size=i'   => \$opts{'init_size'},
	'missing=i'     => \$opts{'missing'},
	'q|quiet'       => \$opts{'quiet'},
	's|scheme_id=i' => \$opts{'scheme_id'},
	'help'          => \$opts{'help'},
);
if ( $opts{'help'} ) {
	show_help();
	exit;
}
if ( !$opts{'d'} || !$opts{'scheme_id'} ) {
	say 'Usage: lincodes.pl --database [DB_CONFIG] --scheme [SCHEME_ID]';
	exit;
}
my $script = BIGSdb::Offline::Script->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		instance         => $opts{'d'},
		logger           => $logger,
	}
);
check_db();
$opts{'init_size'} //= 1000;
main();

sub main {
	local $| = 1;
	my $profiles_to_assign = [];
	my $lincodes           = get_lincode_definitions();
	my $initiating;
	if ( !@{ $lincodes->{'profile_ids'} } ) {
		say 'No LINcodes yet defined.' if !$opts{'quiet'};
		$profiles_to_assign = get_prim_order();
		$initiating         = 1;
	} else {
		$profiles_to_assign = get_profiles_without_lincodes();
	}
	if ( !@$profiles_to_assign ) {
		say 'No profiles to assign.' if !$opts{'quiet'};
		return;
	}
	assign_lincodes($profiles_to_assign);
	if ($initiating) {
		$profiles_to_assign = get_profiles_without_lincodes();
		if (@$profiles_to_assign) {
			say 'Assigning remaining profiles sequentially.';
			assign_lincodes($profiles_to_assign);
		}
	}
	return;
}

sub assign_lincodes {
	my ($profiles_to_assign) = @_;
	my $scheme_info = $script->{'datastore'}->get_scheme_info( $opts{'scheme_id'}, { get_pk => 1 } );
	my $pk          = $scheme_info->{'primary_key'};
	my $count       = @$profiles_to_assign;
	my $plural      = $count == 1 ? q() : q(s);
	say "Assigning LINcodes for $count profile$plural." if !$opts{'quiet'};
	my $definitions = get_lincode_definitions();
	my $thresholds  = get_thresholds();
	my %missing     = ( N => 0 );
	foreach my $profile_id (@$profiles_to_assign) {
		my $lincode;
		my $profile = $script->{'datastore'}
		  ->run_query( "SELECT profile FROM mv_scheme_$opts{'scheme_id'} WHERE $pk=?", $profile_id );
		$_ = $missing{$_} // $_ foreach @$profile;
		if ( !@{ $definitions->{'profile_ids'} } ) {
			$lincode = [ (0) x @{ $thresholds->{'diffs'} } ];
			$definitions->{'profiles'} = pdl($profile);
		} else {
			$lincode = get_new_lincode( $definitions, $profile_id, $profile );
		}
		local $" = q(_);
		my $identifier = "$pk-$profile_id";
		my $spaces = q( ) x abs(20 - length($identifier));
		say "$identifier:$spaces@$lincode." if !$opts{'quiet'};
		assign_lincode( $profile_id, $lincode );
		push @{ $definitions->{'profile_ids'} }, $profile_id;
		push @{ $definitions->{'lincodes'} },    $lincode;
	}
	return;
}

sub get_lincode_definitions {
	my $scheme_info = $script->{'datastore'}->get_scheme_info( $opts{'scheme_id'}, { get_pk => 1 } );
	my $pk          = $scheme_info->{'primary_key'};
	my $data        = $script->{'datastore'}->run_query(
		"SELECT profile_id,lincode,profile FROM lincodes l JOIN mv_scheme_$opts{'scheme_id'} s ON "
		  . "l.profile_id=s.$pk WHERE scheme_id=? ORDER BY lincode",
		$opts{'scheme_id'},
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $profile_ids = [];
	my $profiles    = [];
	my $lincodes    = [];
	my %missing     = ( N => 0 );
	foreach my $record (@$data) {
		push @$profile_ids, $record->{'profile_id'};
		$_ = $missing{$_} // $_ foreach @{ $record->{'profile'} };
		push @$profiles, $record->{'profile'};
		push @$lincodes, $record->{'lincode'};
	}
	return {
		profile_ids => $profile_ids,
		profiles    => pdl($profiles),
		lincodes    => $lincodes
	};
}

sub get_new_lincode {
	my ( $definitions, $profile_id, $profile ) = @_;
	my $loci        = $script->{'datastore'}->get_scheme_loci( $opts{'scheme_id'} );
	my $locus_count = @$loci;
	$definitions->{'profiles'} = $definitions->{'profiles'}->glue( 1, pdl($profile) );
	my $j            = @{ $definitions->{'profile_ids'} };           #Newly added last row
	my $prof2        = $definitions->{'profiles'}->slice(",($j)");
	my $min_distance = 100;
	my $closest_index;

	for my $i ( 0 .. @{ $definitions->{'profile_ids'} } - 1 ) {
		my $prof1 = $definitions->{'profiles'}->slice(",($i)");
		my ($diffs) =
		  dims( where( $prof1, $prof2, ( $prof1 != $prof2 ) & ( $prof1 != 0 ) & ( $prof2 != 0 ) ) );
		my ($missing_in_either) = dims( where( $prof1, $prof2, ( $prof1 == 0 ) | ( $prof2 == 0 ) ) );
		my $distance = 100 * $diffs / ( $locus_count - $missing_in_either );
		if ( $distance < $min_distance ) {
			$min_distance  = $distance;
			$closest_index = $i;
		}
	}
	my $identity        = 100 - $min_distance;
	my $thresholds      = get_thresholds();
	my $threshold_index = 0;
	foreach my $threshold_identity ( @{ $thresholds->{'identity'} } ) {
		if ( $identity > $threshold_identity ) {
			$threshold_index++;
			next;
		}
		last;
	}
	return increment_lincode( $definitions->{'lincodes'}, $closest_index, $threshold_index );
}

sub increment_lincode {
	my ( $lincodes, $closest_index, $threshold_index ) = @_;
	my $thresholds = get_thresholds();
	if ( $threshold_index == 0 ) {
		my $max_first = 0;
		foreach my $lincode (@$lincodes) {
			if ( $lincode->[0] > $max_first ) {
				$max_first = $lincode->[0];
			}
		}
		my @new_lincode = ( ++$max_first, (0) x ( @{ $thresholds->{'diffs'} } - 1 ) );
		return [@new_lincode];
	}
	my $closest_lincode     = $lincodes->[$closest_index];
	my @lincode_prefix      = @$closest_lincode[ 0 .. $threshold_index - 1 ];
	my $max_threshold_index = 0;
	foreach my $lincode (@$lincodes) {
		local $" = q(_);
		next if qq(@lincode_prefix) ne qq(@$lincode[ 0 .. $threshold_index - 1 ]);
		if ( $lincode->[$threshold_index] > $max_threshold_index ) {
			$max_threshold_index = $lincode->[$threshold_index];
		}
	}
	my @new_lincode = @lincode_prefix;
	push @new_lincode, ++$max_threshold_index;
	push @new_lincode, 0 while @new_lincode < @{ $thresholds->{'diffs'} };
	return [@new_lincode];
}

sub assign_lincode {
	my ( $profile_id, $lincode ) = @_;
	eval {
		$script->{'db'}->do( 'INSERT INTO lincodes (scheme_id,profile_id,lincode,curator,datestamp) VALUES (?,?,?,?,?)',
			undef, $opts{'scheme_id'}, $profile_id, $lincode, 0, 'now' );
	};
	if ($@) {
		$script->{'db'}->rollback;
		die "Cannot assign LINcode. $@.\n";
	}
	$script->{'db'}->commit;
	return;
}

sub get_profiles_without_lincodes {
	print 'Retrieving profiles without LINcodes ...' if !$opts{'quiet'};
	my $scheme_info = $script->{'datastore'}->get_scheme_info( $opts{'scheme_id'}, { get_pk => 1 } );
	my $pk          = $scheme_info->{'primary_key'};
	my $order       = get_profile_order_term();
	my $lincode_scheme =
	  $script->{'datastore'}
	  ->run_query( 'SELECT * FROM lincode_schemes WHERE scheme_id=?', $opts{'scheme_id'}, { fetch => 'row_hashref' } );
	my $max_missing = $opts{'missing'} // $lincode_scheme->{'max_missing'};
	my $profiles = $script->{'datastore'}->run_query(
		"SELECT $pk FROM mv_scheme_$opts{'scheme_id'} WHERE cardinality(array_positions(profile,'N')) "
		  . "<= $max_missing AND $pk NOT IN (SELECT profile_id FROM lincodes WHERE scheme_id=$opts{'scheme_id'}) "
		  . "ORDER BY $order",
		undef,
		{ fetch => 'col_arrayref', slice => {} }
	);
	say 'Done.' if !$opts{'quiet'};
	return $profiles;
}

sub get_profile_order_term {
	my $scheme_info = $script->{'datastore'}->get_scheme_info( $opts{'scheme_id'}, { get_pk => 1 } );
	my $pk          = $scheme_info->{'primary_key'};
	my $pk_info     = $script->{'datastore'}->get_scheme_field_info( $opts{'scheme_id'}, $pk );
	my $order       = $pk_info->{'type'} eq 'integer' ? "CAST($pk AS integer)" : $pk;
	return $order;
}

sub get_prim_order {
	##no critic (ProhibitMismatchedOperators) - PDL uses .= assignment.
	my ( $index, $dismat ) = get_distance_matrix();
	return $index if @$index == 1;
	print 'Calculating PRIM order ...' if !$opts{'quiet'};
	my $M = pdl($dismat);
	for my $i ( 0 .. @$dismat - 1 ) {
		$M->range( [ $i, $i ] ) .= 100;
	}
	my $ind = $M->flat->minimum_ind;
	my ( $x, $y ) = ( int( $ind / @$index ), $ind - int( $ind / @$index ) * @$index );
	my %used = map { $_ => 1 } ( $x, $y );
	my $index_order = [ $x, $y ];
	my $profile_order = [ $index->[$x], $index->[$y] ];
	$M->range( [ $x, $y ] ) .= $M->range( [ $y, $x ] ) .= 100;
	while ( @$profile_order != @$index ) {
		my $min = 101;
		my $v_min;
		foreach my $x (@$index_order) {
			my $this_min = $M->slice($x)->min;
			if ( $this_min < $min ) {
				$min   = $this_min;
				$v_min = $x;
			}
		}
		my $k = $M->slice($v_min)->flat->minimum_ind;
		for my $i (@$index_order) {
			$M->range( [ $i, $k ] ) .= $M->range( [ $k, $i ] ) .= 100;
		}
		if ( !$used{$k} ) {
			push @$index_order,   $k;
			push @$profile_order, $index->[$k];
			$used{$k} = 1;
		}
	}
	say 'Done.' if !$opts{'quiet'};
	return $profile_order;
}

sub get_distance_matrix {
	my $scheme_info = $script->{'datastore'}->get_scheme_info( $opts{'scheme_id'}, { get_pk => 1 } );
	my $loci        = $script->{'datastore'}->get_scheme_loci( $opts{'scheme_id'} );
	my $locus_count = @$loci;
	die "Scheme has no loci.\n" if !$locus_count;
	my $lincode_scheme =
	  $script->{'datastore'}
	  ->run_query( 'SELECT * FROM lincode_schemes WHERE scheme_id=?', $opts{'scheme_id'}, { fetch => 'row_hashref' } );
	my $order = get_profile_order_term();
	print "Reading profiles (first $opts{'init_size'}) ..." if !$opts{'quiet'};
	my $profiles = $script->{'datastore'}->run_query(
		    "SELECT $scheme_info->{'primary_key'},profile FROM mv_scheme_$opts{'scheme_id'} "
		  . "ORDER BY $order LIMIT $opts{'init_size'}"
		,
		undef, { fetch => 'all_arrayref', slice => {} }
	);
	my $matrix      = [];
	my $index       = [];
	my $i           = 0;
	my $max_missing = $opts{'missing'} // $lincode_scheme->{'max_missing'};
	foreach my $profile (@$profiles) {
		my $Ns = 0;
		foreach my $allele ( @{ $profile->{'profile'} } ) {
			if ( $allele eq 'N' ) {
				$Ns++;
				$allele = 0;
			}
		}
		next if $Ns > $max_missing;
		push @$index,  $profile->{ lc( $scheme_info->{'primary_key'} ) };
		push @$matrix, $profile->{'profile'};
	}
	say 'Done.' if !$opts{'quiet'};
	my $count = @$index;
	die "No profiles to assign.\n"          if ( !$count );
	return $index                           if @$index == 1;
	print 'Calculating distance matrix ...' if !$opts{'quiet'};
	my $m      = pdl(@$matrix);
	my $dismat = [];

	for my $i ( 0 .. $count - 1 ) {
		for my $j ( $i + 1 .. $count - 1 ) {
			my $prof1 = $m->slice(",($i)");
			my $prof2 = $m->slice(",($j)");
			my ($diffs) =
			  dims( where( $prof1, $prof2, ( $prof1 != $prof2 ) & ( $prof1 != 0 ) & ( $prof2 != 0 ) ) );
			my ($missing_in_either) = dims( where( $prof1, $prof2, ( $prof1 == 0 ) | ( $prof2 == 0 ) ) );
			my $distance = 100 * $diffs / ( $locus_count - $missing_in_either );
			$dismat->[$i]->[$j] = $distance;
			$dismat->[$j]->[$i] = $distance;
		}
	}
	say 'Done.' if !$opts{'quiet'};
	return ( $index, $dismat );
}

sub get_thresholds {
	if ( $script->{'cache'}->{'thresholds'} ) {
		return $script->{'cache'}->{'thresholds'};
	}
	my $thresholds =
	  $script->{'datastore'}
	  ->run_query( 'SELECT thresholds FROM lincode_schemes WHERE scheme_id=?', $opts{'scheme_id'} );
	my $diffs    = [ split /\s*;\s*/x, $thresholds ];
	my $identity = [];
	my $loci     = $script->{'datastore'}->get_scheme_loci( $opts{'scheme_id'} );
	foreach my $diff (@$diffs) {
		push @$identity, 100 * ( @$loci - $diff ) / @$loci;
	}
	$script->{'cache'}->{'thresholds'} = {
		diffs    => $diffs,
		identity => $identity
	};
	return $script->{'cache'}->{'thresholds'};
}

sub check_db {
	if ( ( $script->{'system'}->{'dbtype'} // q() ) ne 'sequences' ) {
		$logger->error("$opts{'d'} is not a sequence definition database.");
		exit;
	}
	if ( !$script->{'datastore'}->are_lincodes_defined( $opts{'scheme_id'} ) ) {
		$logger->error("LINcodes are not defined for scheme $opts{'scheme_id'}.");
		exit;
	}
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw/me md us/;
	say << "HELP";
${bold}NAME$norm
    ${bold}lincodes.pl$norm - Define LINcodes from cgMLST profiles.
    
${bold}SYNOPSIS$norm
    ${bold}lincodes.pl$norm ${bold}--database ${under}DB_CONFIG${norm} ${bold}--scheme ${under}SCHEME_ID$norm ${norm}[${under}options$norm]

${bold}OPTIONS$norm

${bold}--database$norm ${under}DATABASE CONFIG$norm
    Database configuration name. This must be a sequence definition database.
    
${bold}--init_size$norm ${under}NUMBER$norm
    Maximum number of profiles to use to initiate assignment order if no 
    LINcodes have yet been defined. The order of assignment is optimally 
    determined using Prim's algorithm, but as this requires calculation of
    a distance matrix is limited, by default, to the first 1000 profiles.
    After this, new LINcodes will be assigned sequentially. 
    
${bold}--missing$norm ${under}NUMBER$norm
    Set the maximum number of loci that are allowed to be missing in a profile
    for LINcodes to be assigned. If not set, the value defined in the LINcode
    schemes table will be used.
    
${bold}--quiet$norm
    Only output errors.
	
${bold}--scheme$norm ${under}SCHEME ID$norm
    Scheme id number for which a LINcode scheme has been defined.
HELP
	return;
}
