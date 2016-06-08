#!/usr/bin/perl
#Find and mark exemplar alleles for use by tagging functions
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

#Direct all library logging calls to screen
my $log_conf =
    qq(log4perl.category.BIGSdb.Script        = INFO, Screen\n)
  . qq(log4perl.category.BIGSdb.Dataconnector = WARN, Screen\n)
  . qq(log4perl.category.BIGSdb.Datastore     = WARN, Screen\n)
  . qq(log4perl.appender.Screen               = Log::Log4perl::Appender::Screen\n)
  . qq(log4perl.appender.Screen.stderr        = 1\n)
  . qq(log4perl.appender.Screen.layout        = Log::Log4perl::Layout::SimpleLayout\n);
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
		options          => \%opts,
		instance         => $opts{'d'},
	}
);
die "This script can only be run against a seqdef database.\n"
  if ( $script->{'system'}->{'dbtype'} // '' ) ne 'sequences';
main();

sub main {
	my $loci = $script->get_selected_loci;
	die "No valid loci selected.\n" if !@$loci;
	foreach my $locus (@$loci) {
		if ( $opts{'update'} ) {
			eval { $script->{'db'}->do( 'UPDATE sequences SET exemplar=NULL WHERE locus=?', undef, $locus ); };
			die "$@\n" if $@;
		}
		my %exemplars;
		my %length_represented;
		my %checked;
		my $alleles = get_alleles($locus);

		#First pass - add representative for each length
		foreach my $allele (@$alleles) {
			my ( $allele_id, $seq ) = @$allele;
			my $length = length $seq;
			if ( !$length_represented{$length} ) {
				$exemplars{$allele_id}       = 1;
				$length_represented{$length} = 1;
				$checked{$allele_id}         = 1;
			}
		}
	  PASS: while ( keys %checked < @$alleles ) {
		  ALLELE: foreach my $allele (@$alleles) {
				my ( $allele_id, $seq ) = @$allele;
				next ALLELE if $checked{$allele_id};
				my $length = length $seq;
			  COMPARE: foreach my $compare_allele (@$alleles) {
					my ( $compare_allele_id, $compare_seq ) = @$compare_allele;
					next COMPARE if !$exemplars{$compare_allele_id};
					next COMPARE if $compare_allele_id eq $allele_id;
					next COMPARE if $length != length $compare_seq;
					my $diff = get_percent_difference( $seq, $compare_seq );
					if ( $diff < $opts{'variation'} ) {
						$checked{$allele_id} = 1;
						next ALLELE;
					}
				}

				#Sequence is >threshold percent different to any currently defined
				#exemplar sequence.
				$exemplars{$allele_id} = 1;
				$checked{$allele_id}   = 1;
				next PASS;
			}
		}
		foreach my $allele (@$alleles) {
			my ( $allele_id, $seq ) = @$allele;
			if ( $exemplars{$allele_id} ) {
				say "$locus-$allele_id";
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

sub get_percent_difference {
	my ( $seq1, $seq2 ) = @_;
	die "Sequences are different lengths.\n" if length $seq1 != length $seq2;
	my $length = length $seq1;
	my $diffs  = 0;
	foreach my $pos ( 0 .. ($length - 1)  ) {
		$diffs++ if substr( $seq1, $pos, 1 ) ne substr( $seq2, $pos, 1 );
	}
	return ( ( $diffs * 100 ) / $length );
}

sub get_alleles {
	my ($locus)    = @_;
	my $locus_info = $script->{'datastore'}->get_locus_info($locus);
	my $qry        = q(SELECT allele_id,sequence FROM sequences WHERE locus=? AND allele_id NOT IN ('0', 'N') ORDER BY )
	  . ( $locus_info->{'allele_id_format'} eq 'integer' ? q(CAST(allele_id AS int)) : q(allele_id) );
	my $alleles = $script->{'datastore'}->run_query( $qry, $locus, { fetch => 'all_arrayref' } );
	return $alleles;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
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
    
${bold}--schemes$norm ${under}LIST$norm
    Comma-separated list of scheme loci to scan.
    
${bold}--update$norm
    Update exemplar flags in database.
    
${bold}--variation$norm ${under}IDENTITY$norm
    Value for percentage identity variation that exemplar alleles
    cover (smaller value will result in more exemplars). Default: 10. 

HELP
	return;
}
