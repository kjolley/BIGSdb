#Written by Keith Jolley
#Copyright (c) 2014-2015, University of Oxford
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
use JSON;
use Dancer2 appname => 'BIGSdb::REST::Interface';
use BIGSdb::Utils;

#Isolate database routes
get '/db/:db/isolates'     => sub { _get_isolates() };
get '/db/:db/isolates/:id' => sub { _get_isolate() };
get '/db/:db/fields'       => sub { _get_fields() };

sub _get_isolates {
	my $self = setting('self');
	$self->check_isolate_database;
	my ($db) = params->{'db'};
	my $page          = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $isolate_count = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM $self->{'system'}->{'view'}");
	my $pages         = ceil( $isolate_count / $self->{'page_size'} );
	my $offset        = ( $page - 1 ) * $self->{'page_size'};
	my $qry           = "SELECT id FROM $self->{'system'}->{'view'} ORDER BY id";
	$qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !param('return_all');
	my $ids = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	my $values = {};

	if (@$ids) {
		my $paging = $self->get_paging( "/db/$db/isolates", $pages, $page );
		$values->{'paging'} = $paging if %$paging;
		my @links;
		push @links, request->uri_for("/db/$db/isolates/$_") foreach @$ids;
		$values->{'isolates'} = \@links;
	}
	return $values;
}

sub _get_isolate {
	my $self = setting('self');
	my ( $db, $id ) = ( params->{'db'}, params->{'id'} );
	$self->check_isolate_is_valid($id);
	my $values = {};
	my $field_values =
	  $self->{'datastore'}
	  ->run_query( "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?", $id, { fetch => 'row_hashref' } );
	my $field_list = $self->{'xmlHandler'}->get_field_list;
	my $provenance = {};
	foreach my $field (@$field_list) {

		if ( $field eq 'sender' || $field eq 'curator' ) {
			$provenance->{$field} = request->uri_for("/db/$db/users/$field_values->{$field}");
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
	  $self->{'datastore'}->run_query( 'SELECT pubmed_id FROM refs WHERE isolate_id=? ORDER BY pubmed_id',
		$id, { fetch => 'col_arrayref' } );
	$values->{'publications'} = $pubmed_ids if @$pubmed_ids;
	my $seqbin_stats =
	  $self->{'datastore'}
	  ->run_query( 'SELECT * FROM seqbin_stats WHERE isolate_id=?', $id, { fetch => 'row_hashref' } );
	if ($seqbin_stats) {
		my $seqbin = {
			contig_count  => $seqbin_stats->{'contigs'},
			total_length  => $seqbin_stats->{'total_length'},
			contigs       => request->uri_for("/db/$db/isolates/$id/contigs"),
			contigs_fasta => request->uri_for("/db/$db/isolates/$id/contigs_fasta")
		};
		$values->{'sequence_bin'} = $seqbin;
	}
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? 'AND (locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes '
	  . "WHERE set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';
	my $designations =
	  $self->{'datastore'}->run_query( "SELECT COUNT(*) FROM allele_designations WHERE isolate_id=?$set_clause", $id );
	if ($designations) {
		$values->{'allele_designations'} = {
			designation_count => int($designations),
			full_designations => request->uri_for("/db/$db/isolates/$id/allele_designations"),
			allele_ids        => request->uri_for("/db/$db/isolates/$id/allele_ids")
		};
	}
	my $scheme_list = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	my $scheme_links = [];
	foreach my $scheme (@$scheme_list) {
		my $allele_designations =
		  $self->{'datastore'}->get_scheme_allele_designations( $id, $scheme->{'id'}, { set_id => $set_id } );
		next if !$allele_designations;
		my $scheme_object = {
			description           => $scheme->{'description'},
			loci_designated_count => scalar keys %$allele_designations,
			full_designations =>
			  request->uri_for("/db/$db/isolates/$id/schemes/$scheme->{'id'}/allele_designations"),
			allele_ids => request->uri_for("/db/$db/isolates/$id/schemes/$scheme->{'id'}/allele_ids")
		};
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme->{'id'}, { set_id => $set_id, get_pk => 1 } );
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields( $scheme->{'id'} );
		if ( defined $scheme_info->{'primary_key'} ) {
			my $scheme_field_values =
			  $self->{'datastore'}->get_scheme_field_values_by_designations( $scheme->{'id'}, $allele_designations );
			$field_values = {};
			foreach my $field (@$scheme_fields) {
				next if !defined $scheme_field_values->{ lc $field };
				my @field_values = keys %{ $scheme_field_values->{ lc $field } };
				my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme->{'id'}, $field );
				if ( $scheme_field_info->{'type'} eq 'integer' ) {
					foreach my $value (@field_values) {
						$value = int($value) if BIGSdb::Utils::is_int($value);    #Force unquoted integers in output.
					}
				}
				if ( @field_values == 1 ) {
					$field_values->{$field} = $field_values[0] if $field_values[0];
				} else {
					$field_values->{$field} = \@field_values;
				}
			}
			$scheme_object->{'fields'} = $field_values if keys %$field_values;
		}
		push @$scheme_links, $scheme_object;
	}
	$values->{'schemes'} = $scheme_links if @$scheme_links;
	my $projects = _get_isolate_projects($id);
	$values->{'projects'} = $projects if @$projects;
	if ( BIGSdb::Utils::is_int( $field_values->{'new_version'} ) ) {
		$values->{'new_version'} = request->uri_for("/db/$db/isolates/$field_values->{'new_version'}");
	}
	my $old_version =
	  $self->{'datastore'}->run_query( "SELECT id FROM $self->{'system'}->{'view'} WHERE new_version=?", $id );
	if ($old_version) {
		$values->{'old_version'} = request->uri_for("/db/$db/isolates/$old_version");
	}
	return $values;
}

sub _get_isolate_projects {
	my ($isolate_id) = @_;
	my $self         = setting('self');
	my ($db)         = params->{'db'};
	my $project_data = $self->{'datastore'}->run_query(
		'SELECT id,short_description FROM projects JOIN project_members ON projects.id=project_members.project_id '
		  . 'WHERE isolate_id=? AND isolate_display ORDER BY id',
		$isolate_id,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my @projects;
	foreach my $project (@$project_data) {
		push @projects,
		  {
			id => request->uri_for("/db/$db/projects/$project->{'id'}"),
			, description => $project->{'short_description'}
		  };
	}
	return \@projects;
}

sub _get_fields {
	my $self = setting('self');
	$self->check_isolate_database;
	my $fields = $self->{'xmlHandler'}->get_field_list;
	my $values = [];
	foreach my $field (@$fields) {
		my $value = {};
		$value->{'name'} = $field;
		my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
		$thisfield->{'required'} //= 'yes';    #This is the default and may not be specified in config.xml.
		foreach (qw ( type required length min max regex comments)) {
			next if !defined $thisfield->{$_};
			if ( $_ eq 'min' || $_ eq 'max' || $_ eq 'length' ) {
				$value->{$_} = int( $thisfield->{$_} );
			} elsif ( $_ eq 'required' ) {
				$value->{$_} = $thisfield->{$_} eq 'yes' ? JSON::true : JSON::false;
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
}
1;
