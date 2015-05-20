#Written by Keith Jolley
#Copyright (c) 2010-2015, University of Oxford
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
package BIGSdb::CurateTableHeaderPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use List::MoreUtils qw(none);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{'type'} = 'text';
	return;
}

sub print_content {
	my ($self) = @_;
	my $table = $self->{'cgi'}->param('table') || '';
	if ( !$self->{'datastore'}->is_table($table) && !@{ $self->{'xmlHandler'}->get_sample_field_list } ) {
		say "Table $table does not exist!";
		return;
	}
	my $q                = $self->{'cgi'};
	my $no_fields        = $q->param('no_fields') ? 1 : 0;           #For profile submissions
	my $id_field = $q->param('id_field') ? 1 : 0;    #Ditto
	my $headers = $self->get_headers( $table, { no_fields => $no_fields, id_field => $id_field } );
	local $" = "\t";
	say "@$headers";
	return;
}

sub get_headers {
	my ( $self, $table, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my @headers;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		my $set_id        = $self->get_set_id;
		my $metadata_list = $self->{'datastore'}->get_set_metadata( $set_id, { curate => 1 } );
		my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
		foreach my $field (@$field_list) {
			push @headers, $field if none { $field eq $_ } qw (id curator sender date_entered datestamp);
			if ( $field eq $self->{'system'}->{'labelfield'} ) {
				push @headers, qw(aliases references);
			}
		}
		my $isolate_loci = $self->get_isolate_loci;
		push @headers, @$isolate_loci;
	} elsif ( $table eq 'profiles' ) {
		my $scheme_id = $self->{'cgi'}->param('scheme_id') || 0;
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		my $set_id = $self->get_set_id;
		push @headers, 'id' if $options->{'id_field'};
		push @headers, $scheme_info->{'primary_key'} if ( !$options->{'no_fields'} );
		my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
		foreach my $locus (@$loci) {
			my $label = $self->clean_locus( $locus, { text_output => 1, no_common_name => 1 } );
			push @headers, $label // $locus;
		}
		if ( !$options->{'no_fields'} ) {
			my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
			foreach my $field (@$scheme_fields) {
				my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
				push @headers, $field if !$scheme_field_info->{'primary_key'};
			}
		}
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		foreach my $att (@$attributes) {
			if ( !( $att->{'name'} eq 'id' && $att->{'type'} eq 'int' ) ) {
				push @headers, $att->{'name'}
				  if none { $att->{'name'} eq $_ } qw (curator sender date_entered datestamp);
			}
			if ( $table eq 'loci' && $self->{'system'}->{'dbtype'} eq 'isolates' && $att->{'name'} eq 'id' ) {
				push @headers, 'aliases';
			}
		}
		if ( $table eq 'sequences' ) {
			if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
				push @headers, 'flags';
			}
			if ( $self->{'cgi'}->param('locus') ) {
				shift @headers;    #don't include 'locus'
				my $extended_attributes = $self->{'datastore'}->run_query(
					"SELECT field FROM locus_extended_attributes WHERE locus=? ORDER BY field_order",
					$self->{'cgi'}->param('locus'),
					{ fetch => 'col_arrayref' }
				);
				if ( ref $extended_attributes eq 'ARRAY' ) {
					push @headers, @$extended_attributes;
				}
			}
		} elsif ( $table eq 'loci' && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
			push @headers, qw(full_name product description);
		}
	}
	return \@headers;
}

sub get_isolate_loci {
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	my @headers;
	my $loci = $self->{'datastore'}->get_loci( { set_id => $set_id } );
	if ( @$loci < 20 ) {
		my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
		my %locus_used;
		foreach my $scheme (@$schemes) {
			my $scheme_loci = $self->{'datastore'}->get_scheme_loci( $scheme->{'id'} );
			foreach my $locus (@$scheme_loci) {
				if ( !$locus_used{$locus} ) {
					my $cleaned_name = $self->clean_locus( $locus, { no_common_name => 1, text_output => 1 } );
					push @headers, $cleaned_name;
					$locus_used{$locus} = 1;
				}
			}
		}
		my $loci_in_no_scheme = $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
		foreach my $locus (@$loci_in_no_scheme) {
			if ( !$locus_used{$locus} ) {
				my $cleaned_name = $self->clean_locus( $locus, { no_common_name => 1, text_output => 1 } );
				push @headers, $cleaned_name;
				$locus_used{$locus} = 1;
			}
		}
	} else {    #Just list MLST loci
		my $scheme_ids =
		  $self->{'datastore'}
		  ->run_query( "SELECT id FROM schemes WHERE description LIKE 'MLST%' ORDER BY display_order",
			undef, { fetch => 'col_arrayref' } );
		foreach my $scheme_id (@$scheme_ids) {
			my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
			foreach my $locus (@$scheme_loci) {
				my $cleaned_name = $self->clean_locus( $locus, { no_common_name => 1, text_output => 1 } );
				push @headers, $cleaned_name;
			}
		}
	}
	return \@headers;
}
1;
