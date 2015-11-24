#!/usr/bin/perl
#Update cached BLAST databases for a seqdef database
#
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
package BIGSdb::Offline::UpdateBlastCaches;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Offline::Script);

sub run_script {
	my ($self) = @_;
	die "No connection to database (check logs).\n" if !defined $self->{'db'};
	die "This script can only be run against an seqdef database.\n"
	  if ( $self->{'system'}->{'dbtype'} // '' ) ne 'sequences';
	$self->_create_all_loci_cache;
	my $sets =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id,description FROM sets ORDER BY id', undef, { fetch => 'all_arrayref', slice => {} } );
	foreach my $set (@$sets) {
		$self->_create_set_cache($set);
	}
	my $schemes = $self->{'datastore'}->get_scheme_list;
	foreach my $scheme (@$schemes) {
		$self->_create_scheme_cache($scheme);
	}
	my $groups = $self->{'datastore'}->get_group_list( { seq_query => 1 } );
	foreach my $group (@$groups) {
		$self->_create_group_cache($group);
	}
	return;
}

sub _create_all_loci_cache {
	my ($self) = @_;
	my @runs = qw (DNA peptide);
	foreach my $run (@runs) {
		my $check = $self->{'datastore'}->check_blast_cache( \@runs, $run, { locus => '' } );
		my ( $temp_fastafile, $run_already_generated ) = @{$check}{qw(temp_fastafile run_already_generated)};
		if ( !$run_already_generated ) {
			$self->{'datastore'}->create_blast_db( { locus => '' }, $run, $temp_fastafile );
			say qq(Created 'all loci' $run cache.) if !$self->{'options'}->{'q'};
		}
	}
	return;
}

sub _create_set_cache {
	my ( $self, $dataset ) = @_;
	my @runs = qw (DNA peptide);
	foreach my $run (@runs) {
		my $check =
		  $self->{'datastore'}->check_blast_cache( \@runs, $run, { set_id => $dataset->{'id'}, locus => '' } );
		my ( $temp_fastafile, $run_already_generated ) = @{$check}{qw(temp_fastafile run_already_generated)};
		if ( !$run_already_generated ) {
			$self->{'datastore'}->create_blast_db( { set_id => $dataset->{'id'}, locus => '' }, $run, $temp_fastafile );
			say qq(Created set '$dataset->{'description'}' $run cache.) if !$self->{'options'}->{'q'};
		}
	}
	return;
}

sub _create_scheme_cache {
	my ( $self, $scheme ) = @_;
	my @runs = qw (DNA peptide);
	foreach my $run (@runs) {
		my $check = $self->{'datastore'}->check_blast_cache( \@runs, $run, { locus => "SCHEME_$scheme->{'id'}" } );
		my ( $temp_fastafile, $run_already_generated ) = @{$check}{qw(temp_fastafile run_already_generated)};
		if ( !$run_already_generated ) {
			$self->{'datastore'}->create_blast_db( { locus => "SCHEME_$scheme->{'id'}" }, $run, $temp_fastafile );
			say qq(Created scheme '$scheme->{'description'}' $run cache.) if !$self->{'options'}->{'q'};
		}
	}
	return;
}

sub _create_group_cache {
	my ( $self, $group ) = @_;
	my @runs = qw (DNA peptide);
	foreach my $run (@runs) {
		my $check = $self->{'datastore'}->check_blast_cache( \@runs, $run, { locus => "GROUP_$group->{'id'}" } );
		my ( $temp_fastafile, $run_already_generated ) = @{$check}{qw(temp_fastafile run_already_generated)};
		if ( !$run_already_generated ) {
			$self->{'datastore'}->create_blast_db( { locus => "GROUP_$group->{'id'}" }, $run, $temp_fastafile );
			say qq(Created group '$group->{'name'}' $run cache.) if !$self->{'options'}->{'q'};
		}
	}
	return;
}
1;
