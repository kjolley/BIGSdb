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
#Version: 20220211
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
use Data::Dumper;                               #TODO Remove
use PDL;

#Direct all library logging calls to screen
my $log_conf = LOG_TO_SCREEN;
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
use Getopt::Long qw(:config no_ignore_case);
my %opts;
GetOptions(
	'd|database=s'  => \$opts{'d'},
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
main();

sub main {
	get_prim_order();
	return;
}

sub get_prim_order {
	##no critic (ProhibitMismatchedOperators) - PDL uses .= assignment.
	my ( $index, $dismat ) = get_distance_matrix();
	print 'Calculating PRIM order ...' if !$opts{'quiet'};
	my $M = pdl($dismat);
	for my $i ( 0 .. @$dismat - 1 ) {
		$M->range( [ $i, $i ] ) .= 100;
	}

	#	say $M;
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
	say Dumper $profile_order;
	return $profile_order;
}

sub get_distance_matrix {
	my $scheme_info = $script->{'datastore'}->get_scheme_info( $opts{'scheme_id'}, { get_pk => 1 } );
	my $loci        = $script->{'datastore'}->get_scheme_loci( $opts{'scheme_id'} );
	my $locus_count = @$loci;
	die "Scheme has no loci.\n" if !$locus_count;
	my $pk      = $scheme_info->{'primary_key'};
	my $pk_info = $script->{'datastore'}->get_scheme_field_info( $opts{'scheme_id'}, $pk );
	my $order   = $pk_info->{'type'} eq 'integer' ? "CAST($pk AS integer)" : $pk;

	#TODO Remove limit - just for testing.
	local $| = 1;
	print 'Reading profiles ...' if !$opts{'quiet'};
	my $profiles =
	  $script->{'datastore'}->run_query(
		"SELECT $scheme_info->{'primary_key'},profile FROM mv_scheme_$opts{'scheme_id'} ORDER BY $order LIMIT 100",
		undef, { fetch => 'all_arrayref', slice => {} } );
	my $count   = @$profiles;
	my $matrix  = [];
	my $index   = [];
	my $i       = 0;
	my %missing = ( N => 0 );
	foreach my $profile (@$profiles) {

		#TODO check not too many missing alleles.
		push @$index, $profile->{ lc( $scheme_info->{'primary_key'} ) };
		$_ = $missing{$_} // $_ foreach @{ $profile->{'profile'} };
		push @$matrix, $profile->{'profile'};
	}
	say 'Done.' if !$opts{'quiet'};
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
	return ( $index, $dismat );
}

sub get_thresholds {
	my $thresholds =
	  $script->{'datastore'}->run_query( 'SELECT thresholds FROM lincodes WHERE scheme_id=?', $opts{'scheme_id'} );
	my @thresholds = split /\s*;\s*/x, $thresholds;
	return \@thresholds;
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
    
${bold}--quiet$norm
    Only output errors.
	
${bold}--scheme$norm ${under}SCHEME ID$norm
    Scheme id number for which a LINcode scheme has been defined.
HELP
	return;
}
