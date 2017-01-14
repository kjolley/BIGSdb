#!/usr/bin/perl -T
#Helper application for Genome Comparator (v2)
#Will retrieve allele designations and sequences for one or more isolates.
#
#Written by Keith Jolley
#Copyright (c) 2017, University of Oxford
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
use constant { CONFIG_DIR => '/etc/bigsdb', LIB_DIR => '/usr/local/lib', DBASE_CONFIG_DIR => '/etc/bigsdb/dbases', };
#######End Local configuration#############################################
use lib (LIB_DIR);
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
use Parallel::ForkManager;
use JSON;
use BIGSdb::Offline::GCHelper;
my %opts;
GetOptions(
	'alignment=i'         => \$opts{'alignment'},
	'database=s'          => \$opts{'d'},
	'exemplar'            => \$opts{'exemplar'},
	'identity=i'          => \$opts{'identity'},
	'isolates=s'          => \$opts{'i'},
	'isolate_list_file=s' => \$opts{'isolate_list_file'},
	'loci=s'              => \$opts{'l'},
	'locus_list_file=s'   => \$opts{'locus_list_file'},
	'reference_file=s'    => \$opts{'reference_file'},
	'sequences'           => \$opts{'sequences'},
	'threads=i'           => \$opts{'threads'},
	'use_tagged'          => \$opts{'use_tagged'},
	'word_size=i'         => \$opts{'word_size'},
	'help'                => \$opts{'h'},
) or die("Error in command line arguments\n");

if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( !$opts{'d'} || ( !$opts{'l'} && !$opts{'locus_list_file'} && !$opts{'reference_file'} ) ) {
	show_help();
	exit;
}
if ( $opts{'threads'} && $opts{'threads'} > 1 ) {
	my $script;
	$script = BIGSdb::Offline::GCHelper->new(    #Create script object to use methods to determine isolate list
		{
			config_dir       => CONFIG_DIR,
			lib_dir          => LIB_DIR,
			dbase_config_dir => DBASE_CONFIG_DIR,
			options          => { query_only => 1, always_run => 1, %opts },
			instance         => $opts{'d'},
		}
	);
	die "Script initialization failed - check logs (authentication problem?).\n"
	  if !defined $script->{'db'};
	my $loci = $script->get_selected_loci;
	die "No valid loci selected.\n" if !@$loci;
	my $isolates = $script->get_isolates;
	delete $opts{$_} foreach qw(i);    #Remove options that impact isolate list
	$script->{'logger'}->info("$opts{'d'}:GCHelper (up to $opts{'threads'} threads)");
	my $data     = {};
	my $new_seqs = {};
	my $pm       = Parallel::ForkManager->new( $opts{'threads'} );
	$pm->run_on_finish(
		sub {
			my ( $pid, $exit_code, $ident, $exit_signal, $core_dump, $ret_data ) = @_;
			$data->{$_} = $ret_data->{'designations'}->{$_} foreach keys %{ $ret_data->{'designations'} };
			$new_seqs->{ $ret_data->{'isolate_id'} }->{$_} = $ret_data->{'local_new_seqs'}->{$_}
			  foreach keys %{ $ret_data->{'local_new_seqs'} };
		}
	);
	foreach my $isolate_id (@$isolates) {
		$pm->start and next;    #Forks
		my $helper = BIGSdb::Offline::GCHelper->new(
			{
				config_dir       => CONFIG_DIR,
				lib_dir          => LIB_DIR,
				dbase_config_dir => DBASE_CONFIG_DIR,
				options          => { i => $isolate_id, always_run => 1, fast => 1, %opts },
				instance         => $opts{'d'},
			}
		);
		my $isolate_data   = $helper->get_results;
		my $local_new_seqs = $helper->get_new_sequences;
		$pm->finish( 0,
			{ designations => $isolate_data, local_new_seqs => $local_new_seqs, isolate_id => $isolate_id } )
		  ;    #Terminates child process
	}
	$pm->wait_all_children;
	correct_new_designations( $data, $new_seqs );
	say encode_json($data);
	exit;
}

#Run non-threaded job
my $helper = BIGSdb::Offline::GCHelper->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		options          => { always_run => 1, fast => 1, global_new => 1, %opts },
		instance         => $opts{'d'},
	}
);
my $batch_data = $helper->get_results;
say encode_json($batch_data);

sub correct_new_designations {
	my ( $data, $new_seqs ) = @_;
	my @isolates;
	my %loci;
	foreach my $isolate_id ( sort { $a <=> $b } keys %$new_seqs ) {
		push @isolates, $isolate_id;
		foreach my $locus ( sort { $a cmp $b } keys %{ $new_seqs->{$isolate_id}->{'allele_lookup'} } ) {
			$loci{$locus} = 1;
		}
	}
	my @loci = sort keys %loci;
	foreach my $locus (@loci) {
		my $i = 1;
		my %hash_names;
		foreach my $isolate_id (@isolates) {
			foreach my $md5_hash ( keys %{ $new_seqs->{$isolate_id}->{'allele_lookup'}->{$locus} } ) {
				if ( !$hash_names{$md5_hash} ) {
					$hash_names{$md5_hash} = "new#$i";
					$i++;
				}
				$data->{$isolate_id}->{'designations'}->{$locus} = $hash_names{$md5_hash};
			}
		}
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
    ${bold}gc_scan.pl$norm - BIGSdb Genome Comparator Helper

${bold}SYNOPSIS$norm
    ${bold}gc_scan.pl --database$norm ${under}NAME$norm --loci$norm ${under}LIST$norm [${under}options$norm]
    
${bold}OPTIONS$norm

${bold}--alignment$norm ${under}INT$norm
    Percentage alignment (default: 100).

          
${bold}--database$norm ${under}NAME$norm
    Database configuration name.
    
${bold}--exemplar$norm
    Only use alleles with the 'exemplar' flag set in BLAST searches to identify
    locus within genome. Specific allele is then identified using a database 
    lookup. This may be quicker than using all alleles for the BLAST search, 
    but will be at the expense of sensitivity. If no exemplar alleles are set 
    for a locus then all alleles will be used. Sets default word size to 15.

${bold}--help$norm
    This help page.
    
${bold}--identity$norm ${under}INT$norm
    Percentage identity (default: 99).
    
${bold}--use_tagged
    Use tagged designations if available. Designations will be retrieved from 
    the database rather than by BLAST. This should be much quicker.

${bold}--isolates$norm ${under}LIST$norm  
    Comma-separated list of isolate ids to scan.
    
${bold}--isolate_list_file$norm ${under}FILE$norm  
    File containing list of isolate ids.
           
${bold}--loci$norm ${under}LIST$norm
    Comma-separated list of loci to scan (ignored if --locus_list used).
    
${bold}--locus_list_file$norm ${under}FILE$norm
    File containing locus names. Each locus should be on its own line.
    
${bold}--reference_file$norm ${under}FILE$norm
    File containing sequences of loci from a reference genome (FASTA format).
    
${bold}--sequences
    Return sequences as well as designations.
    
${bold}--threads$norm ${under}THREADS$norm
    Maximum number of threads to use.

${bold}--word_size$norm ${under}SIZE$norm
    BLASTN word size.

HELP
	return;
}
