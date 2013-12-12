#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
package BIGSdb::ClientDB;
use strict;
use warnings;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.ClientDB');

sub new {    ## no critic (RequireArgUnpacking)
	my $class = shift;
	my $self  = {@_};
	$self->{'sql'} = {};
	bless( $self, $class );
	$logger->info("ClientDB#$self->{'id'} set up.");
	return $self;
}

sub DESTROY {
	my ($self) = @_;
	foreach ( keys %{ $self->{'sql'} } ) {
		if ( $self->{'sql'}->{$_} ) {
			$self->{'sql'}->{$_}->finish;
			$logger->debug("ClientDB#$self->{'id'} statement handle '$_' finished.");
		}
	}
	$logger->info("ClientDB#$self->{'id'} destroyed.");
	return;
}

sub count_isolates_with_allele {
	my ( $self, $locus, $allele_id ) = @_;
	if ( !$self->{'sql'}->{'isolate_allele_count'} ) {
		$self->{'sql'}->{'isolate_allele_count'} =
		  $self->{'db'}->prepare("SELECT COUNT(*) FROM allele_designations WHERE locus=? AND allele_id=?");
		$logger->info("Statement handle 'isolate_allele_count' prepared.");
	}
	eval { $self->{'sql'}->{'isolate_allele_count'}->execute( $locus, $allele_id ) };
	$logger->error($@) if $@;
	my ($count) = $self->{'sql'}->{'isolate_allele_count'}->fetchrow_array;
	$self->{'sql'}->{'isolate_allele_count'}->finish;    #Getting active statement handle errors on disconnect without.
	return $count;
}

sub count_matching_profiles {
	my ( $self, $alleles_hashref ) = @_;
	my $locus_count = scalar keys %$alleles_hashref;
	my $first       = 1;
	my $temp;
	foreach ( keys %$alleles_hashref ) {
		if (!defined $alleles_hashref->{$_}){
			$logger->error("Invalid loci passed to client database#$self->{'id'} for profile check.");
			return 0;
		}
		$temp .= ' OR ' if !$first;
		$temp .= "(locus='$_' AND allele_id='$alleles_hashref->{$_}')";
		$first = 0;
	}
	my $qry = "SELECT COUNT(distinct isolate_id) FROM allele_designations WHERE isolate_id IN (SELECT isolate_id "
	  . "FROM allele_designations WHERE $temp GROUP BY isolate_id HAVING COUNT(isolate_id) = $locus_count)";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	if ($@) {
		$logger->error($@);
		return 0;
	}
	my ($count) = $sql->fetchrow_array;
	return $count;
}

sub get_fields {
	my ( $self, $field, $locus, $allele_id ) = @_;
	if ( !$self->{'sql'}->{$field} ) {
		$self->{'sql'}->{$field} =
		  $self->{'db'}->prepare( "SELECT $field, count(*) AS frequency FROM isolates LEFT JOIN allele_designations ON isolates.id "
			  . "= allele_designations.isolate_id WHERE allele_designations.locus=? AND allele_designations.allele_id=? AND $field IS "
			  . "NOT NULL GROUP BY $field ORDER BY frequency desc,$field" );
	}
	eval { $self->{'sql'}->{$field}->execute( $locus, $allele_id ) };
	if ($@) {
		throw BIGSdb::DatabaseConfigurationException($@);
	}
	my @data;
	while ( my $hashref = $self->{'sql'}->{$field}->fetchrow_hashref ) {
		push @data, $hashref;
	}
	return \@data;
}

sub get_db {
	my ($self) = @_;
	return $self->{'db'};
}
1;
