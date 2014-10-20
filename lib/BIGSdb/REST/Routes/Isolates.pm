#Written by Keith Jolley
#Copyright (c) 2014, University of Oxford
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
package BIGSdb::REST::Routes::Isolates;
use strict;
use warnings;
use 5.010;
use POSIX qw(ceil);
use Dancer2 appname => 'BIGSdb::REST::Interface';
use BIGSdb::Utils;

#Isolate database routes
get '/db/:db/isolates' => sub {
	my $self          = setting('self');
	my ($db)          = params->{'db'};
	my $page          = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $isolate_count = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM $self->{'system'}->{'view'}");
	my $pages         = ceil( $isolate_count / $self->{'page_size'} );
	my $offset        = ( $page - 1 ) * $self->{'page_size'};
	my $ids =
	  $self->{'datastore'}->run_query( "SELECT id FROM $self->{'system'}->{'view'} ORDER BY id OFFSET $offset LIMIT $self->{'page_size'}",
		undef, { fetch => 'col_arrayref' } );
	my $values = [];

	if (@$ids) {
		my $paging = $self->get_paging( "/db/$db/isolates", $pages, $page );
		push @$values, { paging => $paging } if $pages > 1;
		my @links;
		push @links, request->uri_for("/db/$db/isolates/$_")->as_string foreach @$ids;
		push @$values, { isolates => \@links };
	}
	return $values;
};
get '/db/:db/isolates/:id' => sub {
	my $self = setting('self');
	my ( $db, $id ) = ( params->{'db'}, params->{'id'} );
	if ( !BIGSdb::Utils::is_int($id) ) {
		status(400);
		return { error => 'Id must be an integer.' };
	}
	my $values = {};
	my $field_values =
	  $self->{'datastore'}->run_query( "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?", $id, { fetch => 'row_hashref' } );
	if ( !defined $field_values->{'id'} ) {
		status(404);
		return { error => "Isolate $id does not exist." };
	}
	my $field_list = $self->{'xmlHandler'}->get_field_list;
	my $provenance = {};
	foreach my $field (@$field_list) {
		if ( $field eq 'sender' || $field eq 'curator' ) {
			$provenance->{$field} = request->uri_for("/db/$db/users/$field_values->{$field}")->as_string;
		} else {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			if ( defined $field_values->{ lc $field } ) {
				if ( $thisfield->{'type'} eq 'int' ) {
					$provenance->{$field} = int( $field_values->{ lc $field } );
				} else {
					$provenance->{$field} = $field_values->{ lc $field };
				}
			}
		}
	}
	$values->{'provenance'} = $provenance;
	my $pubmed_ids =
	  $self->{'datastore'}
	  ->run_query( "SELECT pubmed_id FROM refs WHERE isolate_id=? ORDER BY pubmed_id", $id, { fetch => 'col_arrayref' } );
	if (@$pubmed_ids) {
		my @refs;
		push @refs, $self->get_pubmed_link($_) foreach @$pubmed_ids;
		$values->{'publications'} = \@refs;
	}
	my $seqbin_stats = $self->{'datastore'}->run_query( "SELECT * FROM seqbin_stats WHERE isolate_id=?", $id, { fetch => 'row_hashref' } );
	if ($seqbin_stats) {
		my $seqbin = {
			contig_count => $seqbin_stats->{'contigs'},
			total_length => $seqbin_stats->{'total_length'},
			contigs      => request->uri_for("/db/$db/isolates/$id/contigs")->as_string
		};
		$values->{'sequence_bin'} = $seqbin;
	}
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? "AND (locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes "
	  . "WHERE set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';
	my $designations = $self->{'datastore'}->run_query( "SELECT COUNT(*) FROM allele_designations WHERE isolate_id=?$set_clause", $id );
	if ($designations) {
		$values->{'allele_designations'} = {
			designation_count => int($designations),
			full_designations => request->uri_for("/db/$db/isolates/$id/allele_designations")->as_string,
			allele_ids        => request->uri_for("/db/$db/isolates/$id/allele_ids")->as_string
		};
	}
	return $values;
};
get '/db/:db/fields' => sub {
	my $self = setting('self');
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		status(400);
		return { error => "Fields can only be defined in isolate databases." };
	}
	my $fields = $self->{'xmlHandler'}->get_field_list;
	my $values = [];
	foreach my $field (@$fields) {
		my $value = {};
		$value->{'name'} = $field;
		my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
		foreach (qw ( type required length min max regex comments)) {
			next if !defined $thisfield->{$_};
			if ( $_ eq 'min' || $_ eq 'max' || $_ eq 'length' ) {
				$value->{$_} = int( $thisfield->{$_} );
			} else {
				$value->{$_} = $thisfield->{$_};
			}
		}
		if ( ( $thisfield->{'optlist'} // '' ) eq 'yes' ) {
			$value->{'allowed_values'} = $self->{'xmlHandler'}->get_field_option_list($field);
		}
		push @$values, $value;
	}
	return $values;
};
1;
