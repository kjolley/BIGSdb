#!/usr/bin/perl -T
#Update cached BLAST databases for a seqdef database
#Written by Keith Jolley
#Copyright (c) 2015, University of Oxford
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
###########Local configuration################################
use constant { CONFIG_DIR => '/etc/bigsdb', LIB_DIR => '/usr/local/lib', DBASE_CONFIG_DIR => '/etc/bigsdb/dbases' };
#######End Local configuration################################
use lib (LIB_DIR);
use BIGSdb::Offline::Script;
use Getopt::Std;
my %opts;
getopts( 'd:q', \%opts );

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
if ( !$opts{'d'} ) {
	say 'Usage: update_cached_blast_dbs.pl -d <database configuration>';
	exit;
}
my $script = BIGSdb::Offline::Script->new(
	{ config_dir => CONFIG_DIR, lib_dir => LIB_DIR, dbase_config_dir => DBASE_CONFIG_DIR, instance => $opts{'d'}, } );
main();

sub main {
	if ( $script->{'system'}->{'dbtype'} eq 'isolates' ) {
		say 'This script should only be run against sequence definition databases.';
		exit(1);
	}
	create_all_loci_cache();
	my $sets =
	  $script->{'datastore'}
	  ->run_query( 'SELECT id,description FROM sets ORDER BY id', undef, { fetch => 'all_arrayref', slice => {} } );
	foreach my $set (@$sets) {
		create_set_cache($set);
	}
	my $schemes = $script->{'datastore'}->get_scheme_list;
	foreach my $scheme (@$schemes) {
		create_scheme_cache($scheme);
	}
	my $groups = $script->{'datastore'}->get_group_list( { seq_query => 1 } );
	foreach my $group (@$groups) {
		create_group_cache($group);
	}
	return;
}

sub create_all_loci_cache {
	my @runs = qw (DNA peptide);
	foreach my $run (@runs) {
		my $check = $script->{'datastore'}->check_blast_cache( \@runs, $run, { locus => '' } );
		my ( $temp_fastafile, $run_already_generated ) = @{$check}{qw(temp_fastafile run_already_generated)};
		if ( !$run_already_generated ) {
			$script->{'datastore'}->create_blast_db( { locus => '' }, $run, $temp_fastafile );
			say qq(Created 'all loci' $run cache.) if !$opts{'q'};
		}
	}
	return;
}

sub create_set_cache {
	my ($dataset) = @_;
	my @runs = qw (DNA peptide);
	foreach my $run (@runs) {
		my $check =
		  $script->{'datastore'}->check_blast_cache( \@runs, $run, { set_id => $dataset->{'id'}, locus => '' } );
		my ( $temp_fastafile, $run_already_generated ) = @{$check}{qw(temp_fastafile run_already_generated)};
		if ( !$run_already_generated ) {
			$script->{'datastore'}
			  ->create_blast_db( { set_id => $dataset->{'id'}, locus => '' }, $run, $temp_fastafile );
			say qq(Created set '$dataset->{'description'}' $run cache.) if !$opts{'q'};
		}
	}
	return;
}

sub create_scheme_cache {
	my ($scheme) = @_;
	my @runs = qw (DNA peptide);
	foreach my $run (@runs) {
		my $check = $script->{'datastore'}->check_blast_cache( \@runs, $run, { locus => "SCHEME_$scheme->{'id'}" } );
		my ( $temp_fastafile, $run_already_generated ) = @{$check}{qw(temp_fastafile run_already_generated)};
		if ( !$run_already_generated ) {
			$script->{'datastore'}->create_blast_db( { locus => "SCHEME_$scheme->{'id'}" }, $run, $temp_fastafile );
			say qq(Created scheme '$scheme->{'description'}' $run cache.) if !$opts{'q'};
		}
	}
	return;
}

sub create_group_cache {
	my ($group) = @_;
	my @runs = qw (DNA peptide);
	foreach my $run (@runs) {
		my $check = $script->{'datastore'}->check_blast_cache( \@runs, $run, { locus => "GROUP_$group->{'id'}" } );
		my ( $temp_fastafile, $run_already_generated ) = @{$check}{qw(temp_fastafile run_already_generated)};
		if ( !$run_already_generated ) {
			$script->{'datastore'}->create_blast_db( { locus => "GROUP_$group->{'id'}" }, $run, $temp_fastafile );
			say qq(Created group '$group->{'name'}' $run cache.) if !$opts{'q'};
		}
	}
	return;
}
