#Written by Keith Jolley
#Copyright (c) 2010-2014, University of Oxford
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
use 5.010;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Scheme');

sub new {    ## no critic (RequireArgUnpacking)
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
			$logger->debug("Scheme#$self->{'id'} ($self->{'description'}) statement handle '$_' finished.");
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
		s/'/_PRIME_/g foreach @$loci;
		local $" = ',';
		my $qry = "SELECT @$loci FROM $self->{'dbase_table'} WHERE ";
		local $" = '=? AND ';
		my $primary_keys = $self->{'primary_keys'};
		$qry .= "@$primary_keys=?";
		$self->{'sql'}->{'scheme_profiles'} = $self->{'db'}->prepare($qry);
		$logger->debug("Scheme#$self->{'id'} ($self->{'description'}) statement handle 'scheme_profiles' prepared.");
	}
	eval { $self->{'sql'}->{'scheme_profiles'}->execute(@$values) };
	if ($@) {
		$logger->warn( "Can't execute 'scheme_profiles' query handle. Check database attributes in the scheme_fields and scheme_members "
			  . "tables for scheme#$self->{'id'} ($self->{'description'})! Statement was '$self->{'sql'}->{scheme_fields}->{Statement}'. $@"
			  . $self->{'db'}->errstr );
		throw BIGSdb::DatabaseConfigurationException("Scheme configuration error");
		return;
	} else {
		my @profile = $self->{'sql'}->{'scheme_profiles'}->fetchrow_array;
		return \@profile;
	}
}

sub get_field_values_by_profile {
	my ( $self, $profile, $options ) = @_;
	$logger->logcarp("Scheme::get_field_values_by_profile is deprecated");    #TODO remove
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
	my @locus_terms;
	if ( !$self->{'sql'}->{'scheme_fields'} ) {
		foreach my $locus (@$loci) {
			$locus =~ s/'/_PRIME_/g;
			my $temp = "$locus=?";
			$temp .= " OR $locus='N'" if $self->{'allow_missing_loci'};
			push @locus_terms, "($temp)";
		}
		local $" = ' AND ';
		my $locus_term_string = "@locus_terms";
		local $" = ',';
		my $qry = "SELECT @$fields FROM $self->{'dbase_table'} WHERE $locus_term_string";
		$self->{'sql'}->{'scheme_fields'} = $self->{'db'}->prepare($qry);
		$logger->debug("Scheme#$self->{'id'} ($self->{'description'}) statement handle 'scheme_fields' prepared. $qry");
	}
	eval { $self->{'sql'}->{'scheme_fields'}->execute(@$profile) };
	if ($@) {
		$logger->warn( "Can't execute 'scheme_fields' query handle. Check database attributes in the scheme_fields table for "
			  . "scheme#$self->{'id'} ($self->{'description'})! Statement was '$self->{'sql'}->{scheme_fields}->{Statement}'. "
			  . $self->{'db'}->errstr );
		throw BIGSdb::DatabaseConfigurationException("Scheme configuration error");
	} else {
		if ( $options->{'return_hashref'} ) {
			return $self->{'sql'}->{'scheme_fields'}->fetchrow_hashref;
		}
		my @values = $self->{'sql'}->{'scheme_fields'}->fetchrow_array;
		return \@values;
	}
}

sub get_field_values_by_designations {
	my ( $self, $designations ) = @_;    #$designations is a hashref containing arrayref of allele_designations for each locus
	my ( @allele_count, @allele_ids );
	my $loci       = $self->{'loci'};
	my $fields     = $self->{'fields'};
	my $field_data = [];
	foreach my $locus (@$loci) {
		if (!defined $designations->{$locus}){
			#Define a null designation if one doesn't exist for the purposes of looking up profile.
			#We can't just abort the query because some schemes allow missing loci, but we don't want to match based
			#on an incomplete set of designations.
			push @allele_ids, '-999';
			push @allele_count,1;
		} else {
			push @allele_count, scalar @{ $designations->{$locus} }; #We need a different query depending on number of designations at loci.
			push @allele_ids, $_->{'allele_id'} foreach @{ $designations->{$locus} };
		}
	}
	local $" = ',';
	my $query_key = "@allele_count";
	if ( !$self->{'sql'}->{"field_values_$query_key"} ) {
		my @locus_terms;
		my $i = 0;
		foreach my $locus (@$loci) {
			$locus =~ s/'/_PRIME_/g;
			my @temp_terms;
			push @temp_terms, ("$locus=?") x $allele_count[$i];
			push @temp_terms, "$locus='N'" if $self->{'allow_missing_loci'};
			local $" = ' OR ';
			push @locus_terms, "(@temp_terms)";
			$i++;
		}
		local $" = ' AND ';
		my $locus_term_string = "@locus_terms";
		local $" = ',';
		$self->{'sql'}->{"field_values_$query_key"} =
		  $self->{'db'}->prepare("SELECT @$loci,@$fields FROM $self->{'dbase_table'} WHERE $locus_term_string");
	}
	eval { $self->{'sql'}->{"field_values_$query_key"}->execute(@allele_ids) };
	if ($@) {
		$logger->warn( "Can't execute 'field_values_$query_key' query handle. Check database attributes in the scheme_fields table for "
			  . "scheme#$self->{'id'} ($self->{'description'})! Statement was '"
			  . $self->{'sql'}->{"field_values_$query_key"}->{'Statement'} . "'. "
			  . $self->{'db'}->errstr );
		throw BIGSdb::DatabaseConfigurationException("Scheme configuration error");
	}
	while ( my $data = $self->{'sql'}->{"field_values_$query_key"}->fetchrow_hashref ) {
		push @$field_data, $data;
	}
	return $field_data;
}

sub get_distinct_fields {
	my ( $self, $field ) = @_;
	my @values;

	#If database name contains term 'bigsdb', then assume it has the usual BIGSdb seqdef structure.
	#Now can query profile_fields table directly, rather than the scheme view.  This will be much quicker.
	my $qry;
	if ( $self->{'dbase_name'} =~ /bigsdb/ && $self->{'dbase_table'} =~ /^scheme_(\d+)$/ ) {
		my $scheme_id = $1;
		$qry = "SELECT distinct value FROM profile_fields WHERE scheme_field='$field' AND scheme_id=$scheme_id ORDER BY value";
	} else {
		$qry = "SELECT distinct $field FROM $self->{'dbase_table'} WHERE $field <> '-999' ORDER BY $field";
	}
	my $sql = $self->{'db'}->prepare($qry);
	$logger->debug("Scheme#$self->{'id'} ($self->{'description'}) statement handle 'distinct_fields' prepared.");
	eval { $sql->execute };
	if ($@) {
		$logger->warn( "Can't execute query handle. Check database attributes in the scheme_fields table for scheme#$self->{'id'} "
			  . "($self->{'description'})! Statement was '$self->{'sql'}->{scheme_fields}->{Statement}'. "
			  . $self->{'db'}->errstr );
		throw BIGSdb::DatabaseConfigurationException("Scheme configuration error");
		return \@;;
	} else {
		while ( my ($value) = $sql->fetchrow_array ) {
			push @values, $value;
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
