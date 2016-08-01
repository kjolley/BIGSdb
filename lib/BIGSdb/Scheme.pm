#Written by Keith Jolley
#Copyright (c) 2010-2016, University of Oxford
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
	$self->_initiate;
	$logger->info("Scheme#$self->{'id'} ($self->{'name'}) set up.");
	return $self;
}

sub _initiate {
	my ($self) = @_;
	my $sql = $self->{'db'}->prepare('SELECT locus,index FROM scheme_warehouse_indices WHERE scheme_id=?');
	if ( $self->{'dbase_id'} ) {
		eval { $sql->execute( $self->{'dbase_id'} ); };
		$logger->error($@) if $@;
		my $data = $sql->fetchall_arrayref;
		my %indices = map { $_->[0] => $_->[1] } @$data;
		$self->{'locus_index'} = \%indices;
	}
	return;
}

sub get_locus_indices {
	my ($self) = @_;
	return $self->{'locus_index'};
}

sub DESTROY {
	my ($self) = @_;
	foreach ( keys %{ $self->{'sql'} } ) {
		if ( $self->{'sql'}->{$_} ) {
			$self->{'sql'}->{$_}->finish;
		}
	}
	return;
}

sub get_profile_by_primary_keys {
	my ( $self, $values ) = @_;
	return if !$self->{'db'};
	if ( !$self->{'sql'}->{'scheme_profiles'} ) {
		my $loci = $self->{'loci'};
		my @locus_names;
		push @locus_names, "profile[$self->{'locus_index'}->{$_}]" foreach @$loci;
		local $" = ',';
		my $table = "mv_scheme_$self->{'dbase_id'}";
		my $qry   = "SELECT @locus_names FROM $table WHERE ";
		local $" = '=? AND ';
		my $primary_keys = $self->{'primary_keys'};
		$qry .= "@$primary_keys=?";
		$self->{'sql'}->{'scheme_profiles'} = $self->{'db'}->prepare($qry);
		$logger->debug("Scheme#$self->{'id'} ($self->{'name'}) statement handle 'scheme_profiles' prepared.");
	}
	eval { $self->{'sql'}->{'scheme_profiles'}->execute(@$values) };
	if ($@) {
		$logger->warn( q(Can't execute 'scheme_profiles' query handle. )
			  . q(Check database attributes in the scheme_fields and scheme_members )
			  . qq(tables for scheme#$self->{'id'} ($self->{'name'})! Statement was )
			  . qq('$self->{'sql'}->{scheme_fields}->{Statement}'. $@)
			  . $self->{'db'}->errstr );
		throw BIGSdb::DatabaseConfigurationException('Scheme configuration error');
	} else {
		my @profile = $self->{'sql'}->{'scheme_profiles'}->fetchrow_array;
		return \@profile;
	}
}

sub get_field_values_by_designations {

	#$designations is a hashref containing arrayref of allele_designations for each locus
	my ( $self, $designations, $options ) = @_;
	my ( @allele_count, @allele_ids );
	my $loci   = $self->{'loci'};
	my $fields = $self->{'fields'};
	my @used_loci;
	foreach my $locus (@$loci) {
		if ( !defined $designations->{$locus} ) {
			next if $options->{'dont_match_missing_loci'};

			#Define a null designation if one doesn't exist for the purposes of looking up profile.
			#We can't just abort the query because some schemes allow missing loci, but we don't want to match based
			#on an incomplete set of designations.
			push @allele_ids,   '-999';
			push @allele_count, 1;
		} else {
			next if $options->{'dont_match_missing_loci'} && $designations->{$locus}->[0]->{'allele_id'} eq 'N';
			push @allele_count,
			  scalar
			  @{ $designations->{$locus} };    #We need a different query depending on number of designations at loci.
			foreach my $designation ( @{ $designations->{$locus} } ) {
				push @allele_ids, $designation->{'status'} eq 'ignore' ? '-999' : $designation->{'allele_id'};
			}
		}
		push @used_loci, $locus;
	}
	return {} if !@allele_ids;
	local $" = ',';
	my @locus_terms;
	my @locus_list;
	my $i = 0;
	foreach my $locus (@used_loci) {
		my $locus_name = "profile[$self->{'locus_index'}->{$locus}]";
		push @locus_list, $locus_name;
		my @temp_terms;
		push @temp_terms, ("$locus_name=?") x $allele_count[$i];
		push @temp_terms, "$locus_name='N'" if $self->{'allow_missing_loci'};
		local $" = ' OR ';
		push @locus_terms, "(@temp_terms)";
		$i++;
	}
	local $" = ' AND ';
	my $locus_term_string = "@locus_terms";
	local $" = ',';
	my $table = "mv_scheme_$self->{'dbase_id'}";

	#Don't cache statement handle because it will vary depending on whether or not there are missing loci
	#or differing numbers of allele designations at loci.
	my $sql = $self->{'db'}->prepare("SELECT @locus_list,@$fields FROM $table WHERE $locus_term_string");
	eval { $sql->execute(@allele_ids) };
	if ($@) {
		$logger->warn( q(Check database attributes in the scheme_fields table for )
			  . qq(scheme#$self->{'id'} ($self->{'name'})! $@ ) );
		throw BIGSdb::DatabaseConfigurationException('Scheme configuration error');
	}
	my $field_data = $sql->fetchall_arrayref( {} );
	$self->{'db'}->commit;    #Prevent IDLE in transaction locks in long-running REST process.
	return $field_data;
}

sub get_distinct_fields {
	my ( $self, $field ) = @_;
	$logger->error("Scheme#$self->{'id'} database is not configured.") if !defined $self->{'dbase_name'};
	return [] if !defined $self->{'dbase_name'} || !defined $self->{'dbase_id'};
	my $qry    = q(SELECT DISTINCT value FROM profile_fields WHERE scheme_field=? AND scheme_id=? ORDER BY value);
	my $values = [];
	eval { $values = $self->{'db'}->selectcol_arrayref( $qry, undef, $field, $self->{'dbase_id'} ) };
	if ($@) {
		$logger->warn( q(Can't execute query handle. Check database attributes in the scheme_fields table )
			  . qq(for scheme#$self->{'id'} $@) );
		throw BIGSdb::DatabaseConfigurationException('Scheme configuration error');
	}
	return $values;
}

sub get_db {
	my ($self) = @_;
	return $self->{'db'} if $self->{'db'};
	return;
}
1;
