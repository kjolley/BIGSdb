#Written by Keith Jolley
#Copyright (c) 2010-2025, University of Oxford
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
package BIGSdb::DownloadProfilesPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use List::MoreUtils qw(uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{'type'}   = 'text';
	$self->{'jQuery'} = 1;
	return;
}

sub _downloads_disabled {
	my ($self) = @_;
	return 1
	  if ( $self->{'system'}->{'disable_profile_downloads'} // q() ) eq 'yes'
	  && !$self->is_admin;
	return;
}

sub print_content {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	my $set_id    = $self->get_set_id;
	if ( $self->{'system'}->{'dbtype'} ne 'sequences' ) {
		say q(This is not a sequence definition database.);
		return;
	}
	if ( $self->_downloads_disabled ) {
		say 'Profile downloads are disabled for this database.';
		return;
	}
	if ( !$scheme_id ) {
		say q(No scheme id passed.);
		return;
	} elsif ( !BIGSdb::Utils::is_int($scheme_id) ) {
		say q(Scheme id must be an integer.);
		return;
	} elsif ( $set_id && !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id ) ) {
		say qq(Scheme $scheme_id is not available.);
		return;
	}
	$scheme_id =~ s/^0*//x;    #In case scheme_id has preceeding zeros.
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	if ( !$scheme_info ) {
		say q(Scheme does not exist.);
		return;
	}
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $primary_key   = $scheme_info->{'primary_key'};
	if ( !$primary_key ) {
		say q(This scheme has no primary key set.);
		return;
	}
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	print $primary_key;
	my @fields        = ( $primary_key, 'profile' );
	my $locus_indices = $self->{'datastore'}->get_scheme_locus_indices($scheme_id);
	my @order;
	foreach my $locus (@$loci) {
		my $locus_info   = $self->{'datastore'}->get_locus_info( $locus, { set_id => $set_id } );
		my $header_value = $locus_info->{'set_name'} // $locus;
		print qq(\t$header_value);
		push @order, $locus_indices->{$locus};
	}
	foreach my $field (@$scheme_fields) {
		next if $field eq $primary_key;
		print qq(\t$field);
		push @fields, $field;
	}
	my $cg_schemes = $self->_get_classification_schemes($scheme_id);
	my $c_groups   = $self->_get_classification_groups($scheme_id);
	my $lincodes   = $self->_get_lincodes($scheme_id);
	foreach my $cg_scheme (@$cg_schemes) {
		print qq(\t$cg_scheme->{'name'});
	}
	my $lincodes_defined = $self->{'datastore'}->are_lincodes_defined($scheme_id);
	my $lincode_fields   = [];
	if ($lincodes_defined) {
		print qq(\tLINcode);
		$lincode_fields =
		  $self->{'datastore'}
		  ->run_query( 'SELECT field FROM lincode_fields WHERE scheme_id=? ORDER BY display_order,field',
			$scheme_id, { fetch => 'col_arrayref' } );
		local $" = qq(\t);
		print qq(\t@$lincode_fields);
	}
	print qq(\n);
	local $" = q(,);
	my $scheme_warehouse = qq(mv_scheme_$scheme_id);
	my $pk_info          = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	my $date_restriction = $self->{'datastore'}->get_date_restriction;
	my $date_clause =
	  ( $date_restriction && !$self->{'username'} ) ? qq(WHERE date_entered<='$date_restriction' ) : q();
	my $qry = "SELECT @fields FROM $scheme_warehouse ${date_clause}ORDER BY "
	  . ( $pk_info->{'type'} eq 'integer' ? "CAST($primary_key AS int)" : $primary_key );
	my $data = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref' } );
	local $" = qq(\t);
	{
		no warnings 'uninitialized';    #scheme field values may be undefined
		foreach my $definition (@$data) {
			eval {
				my $pk      = shift @$definition;
				my $profile = shift @$definition;
				print qq($pk\t@$profile[@order]);
				print qq(\t@$definition) if @$scheme_fields > 1;
				foreach my $cg_schemes (@$cg_schemes) {
					my $group_id = $c_groups->{ $cg_schemes->{'id'} }->{$pk} // q();
					print qq(\t$group_id);
				}
				if ($lincodes_defined) {
					my $lincode = $lincodes->{$pk} // q();
					print qq(\t$lincode);
					$self->_print_lincode_fields( $scheme_id, $lincode_fields, $lincode );
				}
				print qq(\n);
			};
			if ($@) {
				$logger->error($@) if $@ !~ /Broken\spipe/x && $@ !~ /connection\sabort/x;
				last;
			}
		}
	}
	return;
}

sub _print_lincode_fields {
	my ( $self, $scheme_id, $fields, $lincode ) = @_;
	if ( !$self->{'cache'}->{'prefixes'} ) {
		my $data = $self->{'datastore'}->run_query( 'SELECT * FROM lincode_prefixes WHERE scheme_id=?',
			$scheme_id, { fetch => 'all_arrayref', slice => {} } );
		foreach my $record (@$data) {
			$self->{'cache'}->{'prefixes'}->{ $record->{'field'} }->{ $record->{'prefix'} } =
			  $record->{'value'};
		}
	}
	foreach my $field (@$fields) {
		if ( !$lincode ) {
			print qq(\t);
			next;
		}
		my @prefixes = keys %{ $self->{'cache'}->{'prefixes'}->{$field} };
		my @values;
		foreach my $prefix (@prefixes) {
			if ( $lincode eq $prefix || $lincode =~ /^${prefix}_/x ) {
				push @values, $self->{'cache'}->{'prefixes'}->{$field}->{$prefix};
			}
		}
		@values = sort @values;
		local $" = q(; );
		print qq(\t@values);
	}
	return;
}

sub _get_classification_schemes {
	my ( $self, $scheme_id ) = @_;
	return $self->{'datastore'}
	  ->run_query( 'SELECT id,name FROM classification_schemes WHERE scheme_id=? ORDER BY display_order,id',
		$scheme_id, { fetch => 'all_arrayref', slice => {} } );
}

sub _get_classification_groups {
	my ( $self, $scheme_id ) = @_;
	my $data =
	  $self->{'datastore'}
	  ->run_query( 'SELECT cg_scheme_id,group_id,profile_id FROM classification_group_profiles WHERE scheme_id=?',
		$scheme_id, { fetch => 'all_arrayref', slice => {} } );
	my $groups = {};
	foreach my $values (@$data) {
		$groups->{ $values->{'cg_scheme_id'} }->{ $values->{'profile_id'} } = $values->{'group_id'};
	}
	return $groups;
}

sub _get_lincodes {
	my ( $self, $scheme_id ) = @_;
	my $data =
	  $self->{'datastore'}
	  ->run_query( 'SELECT * FROM lincodes WHERE scheme_id=?', $scheme_id, { fetch => 'all_arrayref', slice => {} } );
	my $lincodes = {};
	foreach my $record (@$data) {
		my $lincode = $record->{'lincode'};
		local $" = q(_);
		$lincodes->{ $record->{'profile_id'} } = qq(@$lincode);
	}
	return $lincodes;
}
1;
