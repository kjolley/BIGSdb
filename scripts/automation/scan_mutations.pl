#!/usr/bin/env perl
#Written by Keith Jolley
#Copyright (c) 2023, University of Oxford
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
#Version: 20230207
use strict;
use warnings;
use 5.010;
###########Local configuration################################
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases'
};
#######End Local configuration################################
use lib (LIB_DIR);
use BIGSdb::Offline::Script;
use BIGSdb::Constants qw(LOG_TO_SCREEN :limits);
use BIGSdb::Utils;
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
use POSIX;
use Bio::Seq;
use Data::Dumper;    #TODO Remove after testing.
my %opts;
GetOptions(
	'database=s'     => \$opts{'d'},
	'exclude_loci=s' => \$opts{'L'},
	'flanking=i'     => \$opts{'flanking'},
	'help'           => \$opts{'help'},
	'loci=s'         => \$opts{'l'},
	'locus_regex=s'  => \$opts{'R'},
	'quiet'          => \$opts{'quiet'},
	'schemes=s'      => \$opts{'s'},
);

if ( $opts{'help'} ) {
	show_help();
	exit;
}
my $script = BIGSdb::Offline::Script->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		options          => { no_user_db_needed => 1, %opts },
		instance         => $opts{'d'}
	}
);

#Direct all library logging calls to screen
my $log_conf = LOG_TO_SCREEN;
$log_conf =~ s/INFO/WARN/gx if $opts{'quiet'};
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
if ( !$opts{'d'} ) {
	show_help();
	exit;
}
die "This script can only be run against a seqdef database.\n"
  if ( $script->{'system'}->{'dbtype'} // '' ) ne 'sequences';
$opts{'flanking'} //= 10;
if ( $opts{'flanking'} < 5 || $opts{'flanking'} > 20 ) {

	die "Flanking length should be between 5 and 20.\n";
}
main();
undef $script;

sub main {
	my $locus_records = get_loci_with_mutations();
	foreach my $locus_record (@$locus_records) {
		if ( $locus_record->{'locus_type'} eq 'DNA' ) {
			if ( $locus_record->{'mutation_type'} eq 'DNA' ) {    #Mutation defined by DNA position
				die "Mutation defined by DNA position not yet supported.\n";
			} else {                                              #Mutation defined by peptide position
				dna_locus_peptide_mutation( $locus_record->{'locus'} );
			}
		} else {    #Peptide locus
			die "Peptide loci not yet supported.\n";
		}
	}
	return;
}

sub get_loci_with_mutations {
	my $loci     = $script->get_selected_loci;
	my $filtered = [];
	foreach my $mutation_type (qw(peptide dna)) {
		my $loci_with_mutations =
		  $script->{'datastore'}
		  ->run_query( "SELECT locus FROM ${mutation_type}_mutations", undef, { fetch => 'col_arrayref' } );
		my %with_mutations = map { $_ => 1 } @$loci_with_mutations;
		foreach my $locus (@$loci) {
			next if !$with_mutations{$locus};
			my $locus_info = $script->{'datastore'}->get_locus_info($locus);
			push @$filtered,
			  {
				locus         => $locus,
				locus_type    => $locus_info->{'data_type'},
				mutation_type => $mutation_type
			  };
		}
	}
	return $filtered;
}

sub dna_locus_peptide_mutation {
	my ($locus) = @_;
	my $sequences = get_translated_alleles($locus);
	if ( !keys %$sequences ) {
		$logger->error("No translated sequences generated for $locus.");
		return;
	}
	my $mutations =
	  $script->{'datastore'}
	  ->run_query( 'SELECT position,wild_type_aa,variant_aa FROM peptide_mutations WHERE locus=? ORDER BY position',
		$locus, { fetch => 'all_arrayref', slice => {} } );
	foreach my $mutation (@$mutations) {
		my $most_common_length =
		  find_most_common_sequence_length_with_wt( $sequences, $mutation->{'position'}, $mutation->{'wild_type_aa'} );
		my $motifs = define_motifs(
			$sequences, $most_common_length,
			$mutation->{'position'},
			$mutation->{'wild_type_aa'},
			$mutation->{'variant_aa'}
		);
		$logger->error( Dumper $motifs);
	}
	return;
	#$logger->error( Dumper $mutations);
}

sub define_motifs {
	my ( $sequences, $most_common_length, $pos, $wt, $variants ) = @_;
	my $start  = $pos - $opts{'flanking'} - 1;
	my $offset = 0;
	if ( $start < 0 ) {
		$offset = -$start;
		$start  = 0;
	}
	my $end = $pos + $opts{'flanking'} + $offset - 1;
	$end = ( $most_common_length - 1 ) if $end > ( $most_common_length - 1 );
	my %used;
	my %allowed_char = map { $_ => 1 } ( $wt, split /;/x, $variants );
	my $motifs       = {};
	foreach my $allele_id ( sort keys %$sequences ) {    
		next if length $sequences->{$allele_id} != $most_common_length;
		my $motif = substr( $sequences->{$allele_id}, $start, ( $end - $start + 1 ) );
		next if $used{$motif};
		$used{$motif} = 1;
		my $char = substr( $motif, $opts{'flanking'} - $offset, 1 );
		next if !$allowed_char{$char};
		$motifs->{$motif}= {
			variant_char => $char,
			wt           => ( $char eq $wt ? 1 : 0 )
		};
	}
	return $motifs;
}

sub find_most_common_sequence_length_with_wt {
	my ( $sequences, $pos, $wt ) = @_;
	my %lengths;
	foreach my $allele_id ( keys %$sequences ) {
		next if substr( $sequences->{$allele_id}, $pos - 1, 1 ) ne $wt;
		my $length = length( $sequences->{$allele_id} );
		$lengths{$length}++;
	}
	my $most_common_length;
	foreach my $length ( sort keys %lengths ) {
		if ( !defined $most_common_length || $lengths{$length} > $lengths{$most_common_length} ) {
			$most_common_length = $length;
		}
	}
	return $most_common_length;
}

sub get_translated_alleles {
	my ($locus)     = @_;
	my $locus_info  = $script->{'datastore'}->get_locus_info($locus);
	my $codon_table = $script->{'system'}->{'codon_table'} // 11;
	my $orf         = $locus_info->{'orf'}                 // 1;
	my $reverse;
	if ( $orf > 3 ) {
		$reverse = 1;
		$orf     = $orf - 3;
	}
	my $alleles = $script->{'datastore'}->run_query(
		'SELECT allele_id,sequence FROM sequences WHERE locus=? AND allele_id NOT IN (?,?)',
		[ $locus, 0, 'N' ],
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $translated = {};
	foreach my $allele (@$alleles) {
		my $seq = $reverse ? BIGSdb::Utils::reverse_complement( $allele->{'sequence'} ) : $allele->{'sequence'};
		if ( $orf > 1 && $orf <= 3 ) {
			$seq = substr( $seq, $orf - 1 );
		}
		my $seq_obj = Bio::Seq->new( -seq => $seq, -alphabet => 'dna' );
		my $peptide = $seq_obj->translate( -codontable_id => $codon_table )->seq;
		$peptide =~ s/\*$//x;            #Remove terminal stop codon.
		next if $peptide =~ /\*/gx;      #Ignore any alleles with internal stops.
		$translated->{ $allele->{'allele_id'} } = $peptide;
	}
	return $translated;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t      = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw/me md us/;
	say << "HELP";
${bold}NAME$norm
    ${bold}scan_mutations.pl$norm - Search for mutations in defined allele sequences

${bold}SYNOPSIS$norm
    ${bold}scan_mutations.pl --database ${under}DB_CONFIG$norm [${under}options$norm]

${bold}OPTIONS$norm

${bold}--database$norm ${under}DATABASE CONFIG$norm
    Database configuration name.
    
${bold}--exclude_loci$norm ${under}LIST$norm
    Comma-separated list of loci to exclude.
    
${bold}--flanking$norm ${under}LENGTH$norm
    Length of flanking sequence to use either side of mutation site when 
    defining search motifs. Default: 10.
    
${bold}--help$norm
    This help page.
    
${bold}--loci$norm ${under}LIST$norm
    Comma-separated list of loci to scan (ignored if --schemes used).
 
${bold}--locus_regex$norm ${under}REGEX$norm
    Regex for locus names.
   
${bold}--quiet$norm
    Only show errors.   

${bold}--schemes$norm ${under}LIST$norm
    Comma-separated list of scheme loci to scan.   
HELP
	return;
}
