#!/usr/bin/env perl
#Find and mark exemplar alleles for use by tagging functions
#Written by Keith Jolley
#Copyright (c) 2016-2025, University of Oxford
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
#Version: 20250224
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
use BIGSdb::Constants qw(LOG_TO_SCREEN);
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;

#Direct all library logging calls to screen
my $log_conf = LOG_TO_SCREEN;
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
my %opts;
GetOptions(
	'database=s'     => \$opts{'d'},
	'datatype=s'     => \$opts{'datatype'},
	'exclude_loci=s' => \$opts{'L'},
	'help'           => \$opts{'h'},
	'loci=s'         => \$opts{'l'},
	'locus_regex=s'  => \$opts{'R'},
	'quiet'          => \$opts{'quiet'},
	'schemes=s'      => \$opts{'s'},
	'update'         => \$opts{'update'},
	'variation=f'    => \$opts{'variation'}
) or die("Error in command line arguments\n");
if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( !$opts{'d'} ) {
	say "\nUsage: find_exemplars.pl --database <NAME>\n";
	say 'Help: find_exemplars.pl --help';
	exit;
}
$opts{'variation'} //= 10;
if ( $opts{'variation'} < 0 || $opts{'variation'} > 100 ) {
	die "%variation must be between 0-100.\n";
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
		options          => { no_user_db_needed => 1, %opts },
		instance         => $opts{'d'},
		logger           => $logger
	}
);
die "This script can only be run against a seqdef database.\n"
  if ( $script->{'system'}->{'dbtype'} // '' ) ne 'sequences';
$script->{'options'}->{'mark_job'} = 1;
my $job_id = $script->add_job( 'FindExemplars', { temp_init => 1 } );
main();
$script->stop_job( $job_id, { temp_init => 1 } );
undef $script;

sub main {
	my $loci = $script->get_selected_loci;
	die "No valid loci selected.\n" if !@$loci;
	foreach my $locus (@$loci) {
		my %exemplars;
		my %length_represented;
		my $alleles = get_alleles($locus);
		if ( $opts{'update'} ) {
			eval { $script->{'db'}->do( 'UPDATE sequences SET exemplar=NULL WHERE locus=?', undef, $locus ); };
			die "$@\n" if $@;
		}

		#First pass - add representative for each length
		foreach my $allele (@$alleles) {
			my ( $allele_id, $seq ) = @$allele;
			my $length = length $seq;
			if ( !$length_represented{$length} ) {
				push @{ $exemplars{$length} }, [ $allele_id, $seq ];
				$length_represented{$length} = 1;
			}
		}
	  ALLELE: foreach my $allele (@$alleles) {
			my ( $allele_id, $seq ) = @$allele;
			my $length = length $seq;
		  COMPARE: foreach my $compare_allele ( @{ $exemplars{$length} } ) {
				my ( $compare_allele_id, $compare_seq ) = @$compare_allele;
				next COMPARE if $compare_allele_id eq $allele_id;

				#XOR strings together and count bits
				#See https://stackoverflow.com/questions/33050582/perl-count-mismatch-between-two-strings
				my $diff_count = ( $seq ^ $compare_seq ) =~ tr/\0//c;
				my $diff       = ( $diff_count * 100 ) / $length;
				if ( $diff < $opts{'variation'} ) {
					next ALLELE;
				}
			}

			#Sequence is >threshold percent different to any currently defined
			#exemplar sequence.
			push @{ $exemplars{$length} }, [ $allele_id, $seq ] if $allele_id ne $exemplars{$length}[0]->[0];
		}
		$script->reconnect;
		foreach my $length ( sort { $a <=> $b } keys %exemplars ) {
			foreach my $allele ( @{ $exemplars{$length} } ) {
				my ( $allele_id, $seq ) = @$allele;
				say "Locus: $locus; Length: $length; Allele: $allele_id" if !$opts{'quiet'};
				if ( $opts{'update'} ) {
					eval {
						$script->{'db'}->do( 'UPDATE sequences SET exemplar=TRUE WHERE (locus,allele_id)=(?,?)',
							undef, $locus, $allele_id );
					};
					die "$@\n" if $@;
				}
			}
		}
		if ( $opts{'update'} ) {
			$script->{'db'}->commit;
		}
	}
	return;
}

sub get_alleles {
	my ($locus) = @_;
	my $locus_info = $script->{'datastore'}->get_locus_info($locus);
	my $qry =
	  q(SELECT allele_id,sequence FROM sequences WHERE locus=? AND allele_id NOT IN ('0', 'N', 'P') ORDER BY )
	  . ( $locus_info->{'allele_id_format'} eq 'integer' ? q(CAST(allele_id AS int)) : q(allele_id) );
	my $alleles = $script->{'datastore'}->run_query( $qry, $locus, { fetch => 'all_arrayref' } );
	$script->{'db'}->commit;    #Prevent idle in transaction
	return $alleles;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t      = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw(me md us);
	say << "HELP";
${bold}NAME$norm
    ${bold}find_exemplars.pl$norm - Identify and mark exemplar alleles for use
    by tagging functions

${bold}SYNOPSIS$norm
    ${bold}find_exemplars.pl --database ${under}NAME$norm ${bold} $norm [${under}options$norm]

${bold}OPTIONS$norm

${bold}--database$norm ${under}NAME$norm
    Database configuration name.
    
${bold}--datatype$norm ${under}DNA|peptide$norm
    Only define exemplars for specified data type (DNA or peptide)    
   
${bold}--exclude_loci$norm ${under}LIST$norm
    Comma-separated list of loci to exclude
    
${bold}--help$norm
    This help page.
    
${bold}--loci$norm ${under}LIST$norm
    Comma-separated list of loci to scan (ignored if -s used).
  
${bold}--locus_regex$norm ${under}REGEX$norm
    Regex for locus names.
    
${bold}--quiet$norm
    Only show error messages.
    
${bold}--schemes$norm ${under}LIST$norm
    Comma-separated list of scheme loci to scan.
    
${bold}--update$norm
    Update exemplar flags in database.
    
${bold}--variation$norm ${under}DISSIMILARITY$norm
    Value for percentage identity variation that exemplar alleles
    cover (smaller value will result in more exemplars). Default: 10. 

HELP
	return;
}
