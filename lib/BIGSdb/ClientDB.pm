#Written by Keith Jolley
#Copyright (c) 2010-2018, University of Oxford
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
use BIGSdb::Exceptions;
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
		my $view = $self->{'dbase_view'} // 'isolates';
		$self->{'sql'}->{'isolate_allele_count'} =
		  $self->{'db'}->prepare(
			    "SELECT COUNT(*) FROM allele_designations RIGHT JOIN $view ON $view.id=allele_designations.isolate_id "
			  . "WHERE (locus,allele_id)=(?,?) AND status!='ignore' AND $view.new_version IS NULL" );
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
	my @args;
	foreach my $locus ( keys %$alleles_hashref ) {
		if ( !defined $alleles_hashref->{$locus} ) {
			$logger->error("Invalid loci passed to client database#$self->{'id'} for profile check.");
			return 0;
		}
		$temp .= ' OR ' if !$first;
		$temp .= '((locus,allele_id)=(?,?))';
		push @args, ( $locus, $alleles_hashref->{$locus} );
		$first = 0;
	}
	my $view = $self->{'dbase_view'} // 'isolates';
	my $qry =
	    'SELECT COUNT(distinct isolate_id) FROM allele_designations WHERE isolate_id IN '
	  . "(SELECT isolate_id FROM allele_designations RIGHT JOIN $view ON $view.id=allele_designations.isolate_id "
	  . "WHERE ($temp) AND $view.new_version IS NULL GROUP BY isolate_id HAVING COUNT(isolate_id)=$locus_count)";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute(@args) };
	if ($@) {
		$logger->error($@);
		return 0;
	}
	my ($count) = $sql->fetchrow_array;
	return $count;
}

sub get_fields {
	my ( $self, $field, $locus, $allele_id ) = @_;
	my $view = $self->{'dbase_view'} // 'isolates';
	if ( !$self->{'sql'}->{$field} ) {
		$self->{'sql'}->{$field} =
		  $self->{'db'}
		  ->prepare( "SELECT $field, count(*) AS frequency FROM $view LEFT JOIN allele_designations ON $view.id="
			  . 'allele_designations.isolate_id WHERE (allele_designations.locus,allele_designations.allele_id)='
			  . "(?,?) AND allele_designations.status!='ignore' AND $field IS NOT NULL GROUP BY $field "
			  . "ORDER BY frequency desc,$field" );
	}
	eval { $self->{'sql'}->{$field}->execute( $locus, $allele_id ) };
	if ($@) {
		BIGSdb::Exception::Database::Configuration->throw($@);
	}
	my $data = $self->{'sql'}->{$field}->fetchall_arrayref( {} );
	return $data;
}

sub count_isolates_belonging_to_classification_group {
	my ( $self, $cscheme, $group ) = @_;
	my $view = $self->{'dbase_view'} // 'isolates';
	if ( !$self->{'sql'}->{'scheme_from_cg'} ) {
		$self->{'sql'}->{'scheme_from_cg'} =
		  $self->{'db'}->prepare('SELECT scheme_id FROM classification_schemes WHERE id=?');
	}
	eval { $self->{'sql'}->{'scheme_from_cg'}->execute($cscheme) };
	BIGSdb::Exception::Database::Configuration->throw($@) if $@;
	my $scheme_id = $self->{'sql'}->{'scheme_from_cg'}->fetchrow_array;
	BIGSdb::Exception::Database::Configuration->throw("No scheme_id set for classification scheme $cscheme")
	  if !defined $scheme_id;
	if ( !$self->{'sql'}->{'scheme_pk'} ) {
		$self->{'sql'}->{'scheme_pk'} =
		  $self->{'db'}->prepare('SELECT field FROM scheme_fields WHERE scheme_id=? AND primary_key');
	}
	eval { $self->{'sql'}->{'scheme_pk'}->execute($scheme_id) };
	BIGSdb::Exception::Database::Configuration->throw($@) if $@;
	my $pk = $self->{'sql'}->{'scheme_pk'}->fetchrow_array;
	BIGSdb::Exception::Database::Configuration->throw("No primary key set for scheme $scheme_id")
	  if !$pk;
	my $qry =
	    "SELECT COUNT(DISTINCT id) FROM temp_isolates_scheme_fields_$scheme_id t JOIN temp_cscheme_$cscheme c "
	  . "ON t.$pk=c.profile_id WHERE c.group_id=? AND t.id IN (SELECT id FROM $view WHERE new_version IS NULL) "
	  . 'AND t.id NOT IN (SELECT isolate_id FROM private_isolates)';
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute($group) };
	BIGSdb::Exception::Database::Configuration->throw($@) if $@;
	return $sql->fetchrow_array;
}

sub get_db {
	my ($self) = @_;
	return $self->{'db'};
}
1;
