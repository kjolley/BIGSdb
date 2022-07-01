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
#Version: 20220701
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
use PDL::IO::FastRaw;
use File::Map;
{
	no warnings 'once';
	$PDL::BIGPDL = 1;
}

#Direct all library logging calls to screen
my $log_conf = LOG_TO_SCREEN;
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
use Getopt::Long qw(:config no_ignore_case);
my %opts;
GetOptions(
	'd|database=s'  => \$opts{'d'},
	'debug'         => \$opts{'debug'},
	'batch_size=i'  => \$opts{'batch_size'},
	'log=s'         => \$opts{'log'},
	'missing=i'     => \$opts{'missing'},
	'mmap'          => \$opts{'mmap'},
	'q|quiet'       => \$opts{'quiet'},
	's|scheme_id=i' => \$opts{'scheme_id'},
	'x|min=s'       => \$opts{'x'},
	'y|max=s'       => \$opts{'y'},
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
$opts{'batch_size'} //= 10_000;
if ( $opts{'log'} ) {
	initiate_log_file( $opts{'log'} );
}
main();

sub main {
	local $| = 1;
	my $lincodes = get_lincode_definitions();
	if ( !@{ $lincodes->{'profile_ids'} } ) {
		say 'No LINcodes yet defined.' if !$opts{'quiet'};
	}
	my $profiles_to_assign;
	do {
		$profiles_to_assign = get_profiles_without_lincodes();
		if ( !@$profiles_to_assign ) {
			say 'All profiles assigned.' if !$opts{'quiet'};
			return;
		}
		my $profiles = @$profiles_to_assign == 1 ? $profiles_to_assign : get_prim_order($profiles_to_assign);
		if ( @{ $lincodes->{'profile_ids'} } ) {
			$profiles = adjust_prim_order( $lincodes->{'profile_ids'}, $lincodes->{'profiles'}, $profiles );
		}
		assign_lincodes($profiles);
		$lincodes = get_lincode_definitions();
	} while @$profiles_to_assign;
	return;
}

sub adjust_prim_order {
	my ( $assigned_profile_ids, $assigned_profiles, $new_profiles ) = @_;
	my $scheme_info      = $script->{'datastore'}->get_scheme_info( $opts{'scheme_id'}, { get_pk => 1 } );
	my $pk               = $scheme_info->{'primary_key'};
	my $loci             = $script->{'datastore'}->get_scheme_loci( $opts{'scheme_id'} );
	my $locus_count      = @$loci;
	my $closest_distance = 100;
	my $closest_profile_index;
	my $index = 0;
	my %missing = ( N => 0 );

	foreach my $profile_id (@$new_profiles) {
		my $profile_array = $script->{'datastore'}
		  ->run_query( "SELECT profile FROM mv_scheme_$opts{'scheme_id'} WHERE $pk=?", $profile_id );
		$_ = $missing{$_} // $_ foreach @$profile_array;
		my $profile = pdl($profile_array);
		for my $i ( 0 .. @$assigned_profile_ids - 1 ) {
			my $assigned_profile = $assigned_profiles->slice(",($i)");
			my ($diffs) = dims(
				where(
					$assigned_profile, $profile,
					( $assigned_profile != $profile ) & ( $assigned_profile != 0 ) & ( $profile != 0 )
				)
			);
			my ($missing_in_either) =
			  dims( where( $assigned_profile, $profile, ( $assigned_profile == 0 ) | ( $profile == 0 ) ) );
			my $distance = 100 * $diffs / ( $locus_count - $missing_in_either );
			if ( $distance < $closest_distance ) {
				$closest_distance      = $distance;
				$closest_profile_index = $index;
			}
		}
		$index++;
	}
	my $reordered_profiles = [ @$new_profiles[ $closest_profile_index .. @$new_profiles - 1 ] ];
	if ( $closest_profile_index > 0 ) {
		push @$reordered_profiles, reverse @$new_profiles[ 0 .. $closest_profile_index - 1 ];
	}
	return $reordered_profiles;
}

sub initiate_log_file {
	my ($filename) = @_;
	my $scheme_info = $script->{'datastore'}->get_scheme_info( $opts{'scheme_id'}, { get_pk => 1 } );
	my $pk = $scheme_info->{'primary_key'};
	open( my $fh, '>', $filename ) || die "Cannot write to log file $filename.\n";
	say $fh qq($pk\tclosest $pk\tcommon alleles\tmissing alleles\tmissing in either\tidentity\tdistance\t)
	  . qq(chosen prefix\tnew LINcode);
	close $fh;
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
		my $spaces     = q( ) x abs( 20 - length($identifier) );
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
	my $closest = {};

	for my $i ( 0 .. @{ $definitions->{'profile_ids'} } - 1 ) {
		my $prof1 = $definitions->{'profiles'}->slice(",($i)");
		my ($diffs) =
		  dims( where( $prof1, $prof2, ( $prof1 != $prof2 ) & ( $prof1 != 0 ) & ( $prof2 != 0 ) ) );
		my ($missing_in_either) = dims( where( $prof1, $prof2, ( $prof1 == 0 ) | ( $prof2 == 0 ) ) );
		my $distance = 100 * $diffs / ( $locus_count - $missing_in_either );
		if ( $distance < $min_distance ) {
			$min_distance  = $distance;
			$closest_index = $i;
			if ( $opts{'log'} ) {
				( $closest->{'common_alleles'} ) = dims( where( $prof1, $prof2, ( $prof1 == $prof2 ) ) );
				( $closest->{'missing'} ) = dims( where( $prof2, ( $prof2 == 0 ) ) );
				$closest->{'missing_in_either'} = $missing_in_either;
			}
		}
		if ( !$diffs ) {
			return $definitions->{'lincodes'}->[$closest_index];
		}
	}
	my $identity        = 100 - $min_distance;
	my $thresholds      = get_thresholds();
	my $threshold_index = 0;
	foreach my $threshold_identity ( @{ $thresholds->{'identity'} } ) {
		if ( $identity >= $threshold_identity ) {
			$threshold_index++;
			next;
		}
		last;
	}
	my $new_lincode = increment_lincode( $definitions->{'lincodes'}, $closest_index, $threshold_index );
	if ( $opts{'log'} ) {
		open( my $fh, '>>', $opts{'log'} ) || die "Cannot append to $opts{'log'}.\n";
		my @chosen_prefix =
		  $threshold_index == 0 ? () : @{ $definitions->{'lincodes'}->[$closest_index] }[ 0 .. $threshold_index - 1 ];
		local $" = q(_);
		say $fh qq($profile_id\t$definitions->{'profile_ids'}->[$closest_index]\t$closest->{'common_alleles'}\t)
		  . qq($closest->{'missing'}\t$closest->{'missing_in_either'}\t$identity\t$min_distance\t@chosen_prefix\t)
		  . qq(@$new_lincode);
		close $fh;
	}
	return $new_lincode;
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
	$closest_index //= 0;
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
	print "Retrieving up to $opts{'batch_size'} profiles without LINcodes ..." if !$opts{'quiet'};
	my $scheme_info = $script->{'datastore'}->get_scheme_info( $opts{'scheme_id'}, { get_pk => 1 } );
	my $pk          = $scheme_info->{'primary_key'};
	my $cast_pk     = get_profile_order_term();
	my $lincode_scheme =
	  $script->{'datastore'}
	  ->run_query( 'SELECT * FROM lincode_schemes WHERE scheme_id=?', $opts{'scheme_id'}, { fetch => 'row_hashref' } );
	my $max_missing = $opts{'missing'} // $lincode_scheme->{'max_missing'};
	my @filters;
	if ( $opts{'x'} ) {
		push @filters, "$cast_pk >= $opts{'x'}";
	}
	if ( $opts{'y'} ) {
		push @filters, "$cast_pk <= $opts{'y'}";
	}
	my $qry = "SELECT $pk FROM mv_scheme_$opts{'scheme_id'} WHERE cardinality(array_positions(profile,'N')) "
	  . "<= $max_missing AND $pk NOT IN (SELECT profile_id FROM lincodes WHERE scheme_id=$opts{'scheme_id'}) ";
	if (@filters) {
		local $" = ' AND ';
		$qry .= "AND (@filters) ";
	}
	$qry .= "ORDER BY $cast_pk LIMIT $opts{'batch_size'}";
	my $profiles = $script->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	my $count = @$profiles;
	say "$count retrieved." if !$opts{'quiet'};
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
	my ($profiles) = @_;
	##no critic (ProhibitMismatchedOperators) - PDL uses .= assignment.
	my ( $filename, $index, $dismat ) = get_distance_matrix($profiles);
	return $index                      if @$index == 1;
	print 'Calculating PRIM order ...' if !$opts{'quiet'};
	print "\n"                         if @$index >= 500;
	my $start_time = time;
	for my $i ( 0 .. @$index - 1 ) {
		$dismat->range( [ $i, $i ] ) .= 999;
	}
	my $ind = $dismat->flat->minimum_ind;
	my ( $x, $y ) = ( int( $ind / @$index ), $ind - int( $ind / @$index ) * @$index );
	my $index_order = [ $x, $y ];
	my $profile_order = [ $index->[$x], $index->[$y] ];
	$dismat->range( [ $x, $y ] ) .= $dismat->range( [ $y, $x ] ) .= 999;
	while ( @$profile_order != @$index ) {
		my $min = 101;
		my $v_min;
		foreach my $x (@$index_order) {
			my $this_min = $dismat->slice($x)->min;
			if ( $this_min < $min ) {
				$min   = $this_min;
				$v_min = $x;
			}
		}
		my $k = $dismat->slice($v_min)->flat->minimum_ind;
		for my $i (@$index_order) {
			$dismat->range( [ $i, $k ] ) .= $dismat->range( [ $k, $i ] ) .= 999;
		}
		push @$index_order,   $k;
		push @$profile_order, $index->[$k];
		my $count = @$profile_order;
		if ( $opts{'debug'} ) {
			say "Profile $count ordered.";
		} elsif ( $count % 500 == 0 ) {
			if ( !$opts{'quiet'} ) {
				say "Order calculated for $count profiles.";
			}
		}
	}
	say 'Done.' if !$opts{'quiet'};
	unlink $filename;
	unlink "$filename.hdr";
	my $stop_time = time;
	my $duration  = $stop_time - $start_time;
	say "Time taken (calculating PRIM order): $duration second(s)." if !$opts{'quiet'};
	return $profile_order;
}

sub get_distance_matrix {
	my ($profile_ids) = @_;
	my $scheme_info = $script->{'datastore'}->get_scheme_info( $opts{'scheme_id'}, { get_pk => 1 } );
	my $pk          = $scheme_info->{'primary_key'};
	my $loci        = $script->{'datastore'}->get_scheme_loci( $opts{'scheme_id'} );
	my $locus_count = @$loci;
	die "Scheme has no loci.\n" if !$locus_count;
	my $lincode_scheme = $script->{'datastore'}
	  ->run_query( 'SELECT * FROM lincode_schemes WHERE scheme_id=?', $opts{'scheme_id'}, { fetch => 'row_hashref' } );
	my $matrix      = [];
	my $index       = [];
	my $max_missing = $opts{'missing'} // $lincode_scheme->{'max_missing'};
	my $list_table  = $script->{'datastore'}->create_temp_list_table_from_array( 'text', $profile_ids );
	my $profiles =
	  $script->{'datastore'}
	  ->run_query( "SELECT $pk,profile FROM mv_scheme_$opts{'scheme_id'} s JOIN $list_table l ON s.$pk=l.value",
		undef, { fetch => 'all_arrayref', slice => {} } );

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
	my $profile_matrix = pdl($matrix);
	my $count          = @$index;
	die "No profiles to assign.\n" if ( !$count );
	return $index if @$index == 1;
	my $msg = $count > 2000 ? ' (this will take a while)' : q();
	print "Calculating distance matrix$msg ..." if !$opts{'quiet'};
	print "\n" if $count >= 500;
	my $start_time = time;
	my $prefix     = BIGSdb::Utils::get_random();
	my $filename   = "$script->{'config'}->{'secure_tmp_dir'}/${prefix}.dismat";
	my $dismat =
	  $opts{'mmap'}
	  ? mapfraw( $filename, { Creat => 1, Dims => [ $count, $count ], Datatype => float } )
	  : zeroes( float, $count, $count );

	for my $i ( 0 .. $count - 1 ) {
		if ( $opts{'debug'} ) {
			say "Profile $i.";
		} elsif ( $i && $i % 500 == 0 ) {
			if ( !$opts{'quiet'} ) {
				say "Calculated for $i profiles.";
				if ( $i == 500 && $count > 2000 ) {
					say 'Note that it does speed up (matrix calculations are for upper triangle)!';
				}
			}
		}
		for my $j ( $i + 1 .. $count - 1 ) {
			my $prof1 = $profile_matrix->slice(",($i)");
			my $prof2 = $profile_matrix->slice(",($j)");
			my ($diffs) =
			  dims( where( $prof1, $prof2, ( $prof1 != $prof2 ) & ( $prof1 != 0 ) & ( $prof2 != 0 ) ) );
			my ($missing_in_either) = dims( where( $prof1, $prof2, ( $prof1 == 0 ) | ( $prof2 == 0 ) ) );
			my $distance = 100 * $diffs / ( $locus_count - $missing_in_either );
			$dismat->range( [ $i, $j ] ) .= $distance;
			$dismat->range( [ $j, $i ] ) .= $distance;
		}
	}
	say 'Done.' if !$opts{'quiet'};
	my $timestamp = BIGSdb::Utils::get_timestamp();
	my $stop_time = time;
	my $duration  = $stop_time - $start_time;
	say "Time taken (distance matrix): $duration second(s)." if !$opts{'quiet'};
	return ( $filename, $index, $dismat );
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
    
${bold}--batch_size$norm ${under}NUMBER$norm
    Sets a maximum number of profiles to use to initiate assignment order. 
    The order of assignment is optimally determined using Prim's algorithm, 
    but can take a long time if there are thousands of profiles. Up to the 
    number of profiles set here will be ordered and assigned first before
    further batches are ordered and assigned. The default value is 10,000 
    but it is recommended that you allow ordering to be determined from all 
    defined profiles if LINcodes have not been previously determined, i.e.
    set this value to greater than the number of assigned profiles.

${bold}--database$norm ${under}DATABASE CONFIG$norm
    Database configuration name. This must be a sequence definition database.
    
${bold}--log$norm ${under}FILENAME$norm
    Filename to use for debug logging.
    
${bold}--missing$norm ${under}NUMBER$norm
    Set the maximum number of loci that are allowed to be missing in a profile
    for LINcodes to be assigned. If not set, the value defined in the LINcode
    schemes table will be used.
    
${bold}--mmap$norm
    Write distance matrix to disk rather than memory. Use this if calculating a
    very large distance matrix on a machine with limited memory. This may run
    slower.
    
${bold}--quiet$norm
    Only output errors.
	
${bold}--scheme$norm ${under}SCHEME ID$norm
    Scheme id number for which a LINcode scheme has been defined.
    
${bold}-x, --min$norm ${under}ID$norm
    Minimum profile id. Note that it is usually recommended that you allow 
    ordering to be determined from all unassigned defined profiles.

${bold}-y, --max$norm ${under}ID$norm
    Maximum profile id. Note that it is usually recommended that you allow 
    ordering to be determined from all unassigned defined profiles.
HELP
	return;
}
