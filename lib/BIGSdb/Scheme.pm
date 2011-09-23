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

package BIGSdb::Scheme;
use strict;
use warnings;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Scheme');

sub new { ## no critic
	my $class = shift;
	my $self  = {@_};
	$self->{'sql'} = {};
	bless( $self, $class );
	$logger->info("Scheme#$self->{'id'} ($self->{'description'}) set up.");
	return $self;
}

sub DESTROY {
	my ($self) = @_;
	foreach ( keys %{ $self->{'sql'} } ) {
		if ( $self->{'sql'}->{$_} ) {
			$self->{'sql'}->{$_}->finish;
			$logger->debug( "Scheme#$self->{'id'} ($self->{'description'}) statement handle '$_' finished." );
		}
	}
	$logger->info("Scheme#$self->{'id'} ($self->{'description'}) destroyed.");
	return;
}

sub get_profile_by_primary_keys {
	my ( $self, $values ) = @_;
	if ( !$self->{'db'} ) {
		$logger->debug("No connection to scheme database");
		return;
	}
	if ( !$self->{'sql'}->{'scheme_profiles'} ) {
		my $loci = $self->{'loci'};
		local $" = ',';
		my $qry = "SELECT @$loci FROM $self->{'dbase_table'} WHERE ";
		local $" = '=? AND ';
		my $primary_keys = $self->{'primary_keys'};
		$qry .= "@$primary_keys=?";
		$self->{'sql'}->{'scheme_profiles'} = $self->{'db'}->prepare($qry);
		$logger->debug( "Scheme#$self->{'id'} ($self->{'description'}) statement handle 'scheme_profiles' prepared." );
	}
	eval { $self->{'sql'}->{'scheme_profiles'}->execute(@$values); };
	if ($@) {
		$logger->warn(
"Can't execute 'scheme_profiles' query handle. Check database attributes in the scheme_fields and scheme_members tables for scheme#$self->{'id'} ($self->{'description'})! Statement was '$self->{'sql'}->{scheme_fields}->{Statement}'. $@"
			  . $self->{'db'}->errstr );
		throw BIGSdb::DatabaseConfigurationException("Scheme configuration error");
		return;
	} else {
		my @profile = $self->{'sql'}->{'scheme_profiles'}->fetchrow_array();
		return \@profile;
	}
}

sub get_field_values_by_profile {
	my ( $self, $profile, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	#Note that when returning a hashref that field names will always be lower-case!
	if ( !$self->{'db'} ) {
		$logger->debug("No connection to scheme database");
		return;
	}
	if ( !$self->{'dbase_table'} ) {
		$logger->warn("No scheme database table set.  Can not retrieve field values.");
		return;
	}
	my $fields = $self->{'fields'};
	my $loci   = $self->{'loci'};
	if ( !$self->{'sql'}->{'scheme_fields'} ) {
		local $" = ',';
		my $qry = "SELECT @$fields FROM $self->{'dbase_table'} WHERE ";
		local $" = '=? AND ';
		$qry .= "@$loci=?";
		$self->{'sql'}->{'scheme_fields'} = $self->{'db'}->prepare($qry);
		$logger->debug( "Scheme#$self->{'id'} ($self->{'description'}) statement handle 'scheme_fields' prepared. $qry" );
	}
	eval { $self->{'sql'}->{'scheme_fields'}->execute(@$profile) };
	if ($@) {
		$logger->warn(
"Can't execute 'scheme_fields' query handle. Check database attributes in the scheme_fields table for scheme#$self->{'id'} ($self->{'description'})! Statement was '$self->{'sql'}->{scheme_fields}->{Statement}'. "
			  . $self->{'db'}->errstr );
		throw BIGSdb::DatabaseConfigurationException("Scheme configuration error");
		return \@;
	} else {
		if ($options->{'return_hashref'}){
			return $self->{'sql'}->{'scheme_fields'}->fetchrow_hashref;
		}
		my @values = $self->{'sql'}->{'scheme_fields'}->fetchrow_array;
		return \@values;
	}
}

sub get_distinct_fields {
	my ($self, $field) = @_;	
	my @values;
	#If database name contains term 'bigsdb', then assume it has the usual BIGSdb seqdef structure.
	#Now can query profile_fields table directly, rather than the scheme view.  This will be much quicker.
	my $qry;
	if ($self->{'dbase_name'} =~ /bigsdb/ && $self->{'dbase_table'} =~ /^scheme_(\d+)$/){
		my $scheme_id = $1;
		$qry = "SELECT distinct value FROM profile_fields WHERE scheme_field='$field' AND scheme_id=$scheme_id ORDER BY value";
	} else {
		$qry = "SELECT distinct $field FROM $self->{'dbase_table'} WHERE $field <> '-999' ORDER BY $field";
	}
	my $sql = $self->{'db'}->prepare($qry);
	$logger->debug( "Scheme#$self->{'id'} ($self->{'description'}) statement handle 'distinct_fields' prepared." );
	eval { $sql->execute };
	if ($@){
		$logger->warn(
"Can't execute query handle. Check database attributes in the scheme_fields table for scheme#$self->{'id'} ($self->{'description'})! Statement was '$self->{'sql'}->{scheme_fields}->{Statement}'. "
			  . $self->{'db'}->errstr );
		throw BIGSdb::DatabaseConfigurationException("Scheme configuration error");
		return \@;
	} else {
		while (my ($value) = $sql->fetchrow_array){
			push @values,$value;
		}
	}
	return \@values;
}

sub get_db {
	my ($self) = @_;
	return $self->{'db'} if $self->{'db'};
	return;
}
1;


