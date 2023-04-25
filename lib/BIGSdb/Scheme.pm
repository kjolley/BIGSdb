#Written by Keith Jolley
#Copyright (c) 2010-2023, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
use BIGSdb::Exceptions;
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
		my $data    = $sql->fetchall_arrayref;
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
		my $table = "mv_scheme_$self->{'dbase_id'}";
		my $qry   = "SELECT profile FROM $table WHERE ";
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
		BIGSdb::Exception::Database::Configuration->throw('Scheme configuration error');
	} else {
		my $profile = $self->{'sql'}->{'scheme_profiles'}->fetchrow_array;
		return $profile;
	}
	return;
}

sub get_field_values_by_designations {

	#$designations is a hashref containing arrayref of allele_designations for each locus
	my ( $self, $designations, $options ) = @_;
	my $loci   = $self->{'loci'};
	my $fields = $self->{'fields'};
	my @used_loci;
	my %missing_loci;
	my $values = {};

	#The original version of the query used placeholders. It was found, however, that memory usage
	#accumulated when doing full cache renewals for cgMLST schemes. Although not as elegant, using
	#a query without placeholders seems to use less memory. Allele ids do need to be escaped in case
	#they include a ' symbol in their identifier.
	foreach my $locus (@$loci) {
		if ( !defined $designations->{$locus} ) {
			next if $options->{'dont_match_missing_loci'};

			#Define a null designation if one doesn't exist for the purposes of looking up profile.
			#We can't just abort the query because some schemes allow missing loci, but we don't want to match based
			#on an incomplete set of designations.
			$values->{$locus}->{'allele_ids'}   = [-999];
			$values->{$locus}->{'allele_count'} = 1;
			$missing_loci{$locus} = 1
		} else {
			next if $options->{'dont_match_missing_loci'} && $designations->{$locus}->[0]->{'allele_id'} eq 'N';

			#We need a different query depending on number of designations at loci.
			$values->{$locus}->{'allele_count'} = scalar @{ $designations->{$locus} };
			my $allele_ids = [];
			foreach my $designation ( @{ $designations->{$locus} } ) {
				$missing_loci{$locus} = 1 if $designation->{'allele_id'} eq '0';
				$designation->{'allele_id'} =~ s/'/\\'/gx;
				push @$allele_ids, $designation->{'status'} eq 'ignore' ? '-999' : $designation->{'allele_id'};
			}
			$values->{$locus}->{'allele_ids'} = $allele_ids;
		}
		push @used_loci, $locus;
	}
	return {} if !$values;
	local $" = ',';
	my @locus_terms;
	foreach my $locus (@used_loci) {
		if (!defined $options->{'dont_match_missing_loci'} || $options->{'dont_match_missing_loci'} ){
			if ( $self->{'allow_missing_loci'}){
				push @{ $values->{$locus}->{'allele_ids'} }, 'N';
			}
			if ( $self->{'allow_presence'} && !$missing_loci{$locus} ){
				push @{ $values->{$locus}->{'allele_ids'} }, 'P';
			}
		}
		local $" = q(',E');
		push @locus_terms, "profile[$self->{'locus_index'}->{$locus}] IN (E'@{ $values->{$locus}->{'allele_ids'} }')";
	}
	local $" = ' AND ';
	my $locus_term_string = "@locus_terms";
	local $" = ',';
	my $table = "mv_scheme_$self->{'dbase_id'}";

	#The query varies depending on whether or not there are missing or multiple alleles for loci,
	#or differing numbers of allele designations at loci.
	#Note that long queries cause memory to increase over time.
	my $qry = "SELECT @$fields FROM $table WHERE $locus_term_string";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	if ($@) {
		$logger->warn( q(Check database attributes in the scheme_fields table for )
			  . qq(scheme#$self->{'id'} ($self->{'name'})! $@ ) );
		$self->{'db'}->rollback;
		BIGSdb::Exception::Database::Configuration->throw('Scheme configuration error');
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
		BIGSdb::Exception::Database::Configuration->throw('Scheme configuration error');
	}
	return $values;
}

sub get_db {
	my ($self) = @_;
	return $self->{'db'} if $self->{'db'};
	return;
}
1;
