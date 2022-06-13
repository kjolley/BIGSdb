#!/usr/bin/env perl
#Populate geography_point_lookup table to set city/town GPS coordinates for
#mapping.
#
#Written by Keith Jolley
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
#Version: 20220531
use strict;
use warnings;
use 5.010;
###########Local configuration#############################################
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases'
};
#######End Local configuration#############################################
use lib (LIB_DIR);
use BIGSdb::Offline::Script;
use BIGSdb::Constants qw(LOG_TO_SCREEN COUNTRIES);
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
use List::MoreUtils qw(uniq);
use Archive::Zip;
binmode( STDOUT, ':encoding(UTF-8)' );

#Direct all library logging calls to screen
my $log_conf = LOG_TO_SCREEN;
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
my %opts;
GetOptions(
	'database=s'       => \$opts{'d'},
	'feature_code=s'   => \$opts{'feature_code'},
	'field=s'          => \$opts{'field'},
	'geodataset=s'     => \$opts{'geodataset'},
	'help'             => \$opts{'h'},
	'min_population=i' => \$opts{'min_population'},
	'quiet'            => \$opts{'quiet'},
	'tmp_dir=s'        => \$opts{'tmp_dir'}
) or die("Error in command line arguments\n");
if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( !$opts{'d'} || !$opts{'field'} || !$opts{'geodataset'} ) {
	say "\nUsage: geography_point_lookups.pl --database <NAME> --field <FIELD> --geodataset <DIR>\n";
	say 'Help: geography_point_lookups.pl --help';
	exit;
}
$opts{'tmp_dir'} //= '/var/tmp';
if ( $opts{'tmp_dir'} =~ /\/$/x ) {
	$opts{'tmp_dir'} =~ s/\/$//x;
}
if ( $opts{'geodataset'} =~ /\/$/x ) {
	$opts{'geodataset'} =~ s/\/$//x;
}
$opts{'min_population'} //= 0;
$opts{'feature_code'}   //= 'P';
my $script = BIGSdb::Offline::Script->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		options          => { no_user_db_needed => 1, %opts },
		instance         => $opts{'d'},
		logger           => $logger
	}
);
die "This script can only be run against a seqdef database.\n"
  if ( $script->{'system'}->{'dbtype'} // '' ) ne 'isolates';
perform_sanity_checks();
main();
undef $script;

sub perform_sanity_checks {
	if ( !-e $opts{'geodataset'} ) {
		die "The Geonames dataset directory '$opts{'geodataset'}' does not exist.\n";
	}
	if ( !glob("$opts{'geodataset'}/??.zip") ) {
		die "The Geonames dataset directory does not contain country level zip files.\n";
	}
	if ( !$script->{'xmlHandler'}->is_field( $opts{'field'} ) ) {
		die "'$opts{'field'}' is not a defined field.\n";
	}
	my $att = $script->{'xmlHandler'}->get_field_attributes( $opts{'field'} );
	if ( ( $att->{'geography_point_lookup'} // q() ) ne 'yes' ) {
		die "Field '$opts{'field'}' does not have the geography_point_lookup attribute "
		  . "set to 'yes' in config.xml.\n";
	}
}

sub main {
	my $country_field = $script->{'system'}->{'country_field'} // 'country';
	my $countries = COUNTRIES;
	my $countries_used =
	  $script->{'datastore'}
	  ->run_query( "SELECT DISTINCT($country_field) FROM isolates WHERE $opts{'field'} IS NOT NULL",
		undef, { fetch => 'col_arrayref' } );
	my %iso2_countries_used;
	foreach my $country (@$countries_used) {
		if ( $countries->{$country}->{'iso2'} ) {
			$iso2_countries_used{ $countries->{$country}->{'iso2'} } = 1;
		}
	}
	foreach my $iso2 ( sort keys %iso2_countries_used ) {
		process_country($iso2);
	}
	return;
}

sub process_country {
	my ($iso2) = @_;
	my $country_field = $script->{'system'}->{'country_field'} // 'country';
	my @matching_countries;
	my $countries = COUNTRIES;
	foreach my $country_name ( sort keys %$countries ) {
		push @matching_countries, $country_name if $countries->{$country_name}->{'iso2'} eq $iso2;
	}
	my @towns;
	foreach my $country_name (@matching_countries) {
		my $country_towns =
		  $script->{'datastore'}
		  ->run_query( "SELECT $opts{'field'} FROM isolates WHERE $country_field=? AND $opts{'field'} IS NOT NULL",
			$country_name, { fetch => 'col_arrayref' } );
		push @towns, @$country_towns;
	}
	@towns = uniq @towns;
	my $defined_towns = $script->{'datastore'}->run_query(
		'SELECT DISTINCT(value) FROM geography_point_lookup WHERE (country_code,field)=(?,?)',
		[ $iso2, $opts{'field'} ],
		{ fetch => 'col_arrayref' }
	);
	my %defined = map { $_ => 1 } @$defined_towns;
	my $undefined = [];
	foreach my $town (@towns) {
		push @$undefined, $town if !$defined{$town};
	}
	my $filename = "$opts{'geodataset'}/$iso2.zip";
	if ( -e $filename ) {
		my $zip          = Archive::Zip->new($filename);
		my $csv_filename = "$opts{'tmp_dir'}/$iso2.txt";
		if ( !defined $zip->extractMember( "$iso2.txt", $csv_filename ) ) {
			$logger->error("$filename does not contain $iso2.txt file ... skipping.");
		}
		foreach my $town (@$undefined) {
			my $this_town;
			my $this_admin1_code;
			if ( $town =~ /^(.+)\s+\[(.+)\]$/x ) {
				$this_town        = $1;
				$this_admin1_code = $2;
			} else {
				$this_town = $town;
			}
			my $assigned;
			open( my $fh, '<:encoding(utf8)', $csv_filename ) || die "Cannot open $csv_filename.\n";
			my $largest_population = -1;    #Some populations are not available and are listed as 0.
			my $best_lat;
			my $best_long;
			my $hits;
			my $most_alternative_names = 0;

			while ( my $line = <$fh> ) {
				my @data              = split /\t/x, $line;
				my $name              = $data[1];
				my $ascii_name        = $data[2];
				my @alternative_names = split /,/x,
				  $data[3];                 #Records with more alternative names defined tend to be more accurate.
				my %alternative_names = map { $_ => 1 } @alternative_names;
				my $latitude          = $data[4];
				my $longitude         = $data[5];
				my $feature_code      = $data[6];
				my $admin1_code       = $data[10];
				my $population        = $data[14];
				if ( defined $this_admin1_code && $this_admin1_code ne $admin1_code ) {
					next;
				}
				if (
					(
						   $this_town eq $name
						|| uc($this_town) eq uc($name)
						|| $this_town eq $ascii_name
						|| uc($this_town) eq uc($ascii_name)
						|| $alternative_names{$this_town}
					)
					&& $population >= $opts{'min_population'}
					&& $feature_code eq $opts{'feature_code'}
				  )
				{
					$hits++;
					if ( $population > $largest_population
						|| ( $population == $largest_population && @alternative_names > $most_alternative_names ) )
					{
						$largest_population = $population;
						$best_lat           = $latitude;
						$best_long          = $longitude;
					}
					$most_alternative_names = @alternative_names if @alternative_names > $most_alternative_names;
				}
			}
			if ($hits) {
				say "$iso2 - $town (pop:$largest_population): $best_lat, $best_long" if !$opts{'quiet'};
				eval {
					$script->{'db'}->do(
						'INSERT INTO geography_point_lookup (country_code,field,value,location,datestamp,curator) '
						  . 'VALUES (?,?,?,ST_MakePoint(?,?)::geography,?,?)',
						undef, $iso2, $opts{'field'}, $town, $best_long, $best_lat, 'now', 0
					);
				};
				$assigned = 1;
				if ($@) {
					$script->{'db'}->rollback;
					die "$@\n";
				}
				$script->{'db'}->commit;
			}
			close $fh;
			$logger->info("No match found for $iso2: $town.") if !$assigned;
		}
		unlink $csv_filename;
	} else {
		$logger->error("$filename does not exist ... skipping.");
	}
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
    ${bold}geography_point_lookups.pl$norm - Populate geography_point_lookup table 
    to set city/town GPS coordinates for mapping.

${bold}SYNOPSIS$norm
    ${bold}geography_point_lookups.pl --database ${under}NAME$norm ${bold}--field ${under}FIELD$norm ${bold}--geodataset ${under}DIR$norm
    
    Run this to populate any unassigned values in the geography_point_lookup
    table.

${bold}OPTIONS$norm

${bold}--database$norm ${under}NAME$norm
    Database configuration name.
    
${bold}--feature_code$norm ${under}CODE$norm
    Geonames feature code. See http://www.geonames.org/export/codes.html.
    Default is 'P' (towns/cities).
    
${bold}--field$norm ${under}FIELD$norm
    Name of field. This should have the geography_point_lookup attribute set to
    'yes' in config.xml.
    
${bold}--geodataset$norm ${under}DIR$norm
    Directory containing the Geonames dataset
    
${bold}--help$norm
    This help page.
    
${bold}--min_population$norm ${under}POPULATION$norm
    Set the minimum population for town to assign. Note that all entries in the
    Geonames database has population, so setting this attribute may result in 
    some values not being assigned, but can ensure that only high-confidence 
    values are used.
    
${bold}--quiet$norm
    Only show error messages.
    
${bold}--tmp_dir$norm ${under}DIR$norm
    Location for temporary files. Defaults to /var/tmp/.
HELP
	return;
}
