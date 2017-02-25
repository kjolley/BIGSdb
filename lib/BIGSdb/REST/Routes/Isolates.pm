#Written by Keith Jolley
#Copyright (c) 2014-2016, University of Oxford
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
get '/db/:db/isolates'         => sub { _get_isolates() };
get '/db/:db/isolates/:id'     => sub { _get_isolate() };
post '/db/:db/isolates/search' => sub { _query_isolates() };

sub _get_isolates {
	my $self = setting('self');
	$self->check_isolate_database;
	my $params          = params;
	my $db              = params->{'db'};
	my $page            = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $allowed_filters = [qw(added_after updated_after)];
	my $qry             = $self->add_filters( "SELECT COUNT(*) FROM $self->{'system'}->{'view'}", $allowed_filters );
	my $isolate_count   = $self->{'datastore'}->run_query($qry);
	my $pages           = ceil( $isolate_count / $self->{'page_size'} );
	my $offset          = ( $page - 1 ) * $self->{'page_size'};
	$qry = $self->add_filters( "SELECT id FROM $self->{'system'}->{'view'}", $allowed_filters );
	$qry .= ' ORDER BY id';
	$qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !param('return_all');
	my $ids = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	my $values = { records => int($isolate_count) };
	my $path = $self->get_full_path( "/db/$db/isolates", $allowed_filters );
	my $paging = $self->get_paging( $path, $pages, $page );
	$values->{'paging'} = $paging if %$paging;
	my @links;
	push @links, request->uri_for("/db/$db/isolates/$_") foreach @$ids;
	$values->{'isolates'} = \@links;
	return $values;
}

sub _get_isolate {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $id ) = @{$params}{qw(db id)};
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
	_get_extended_attributes( $provenance, $id );
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
			description           => $scheme->{'name'},
			loci_designated_count => scalar keys %$allele_designations,
			full_designations => request->uri_for("/db/$db/isolates/$id/schemes/$scheme->{'id'}/allele_designations"),
			allele_ids        => request->uri_for("/db/$db/isolates/$id/schemes/$scheme->{'id'}/allele_ids")
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
	_get_isolate_projects( $values, $id );
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

sub _get_extended_attributes {
	my ( $provenance, $isolate_id ) = @_;
	my $self = setting('self');
	my $fields_with_extended_attributes =
	  $self->{'datastore'}->run_query( 'SELECT DISTINCT isolate_field FROM isolate_field_extended_attributes',
		undef, { fetch => 'col_arrayref' } );
	foreach my $field (@$fields_with_extended_attributes) {
		next if !defined $provenance->{$field};
		my $attribute_list = $self->{'datastore'}->run_query(
			'SELECT attribute,value FROM isolate_value_extended_attributes WHERE (isolate_field,field_value)=(?,?)',
			[ $field, $provenance->{$field} ],
			{ fetch => 'all_arrayref', slice => {}, cache => 'Isolates::isolate_value_extended_attributes' }
		);
		foreach my $attribute (@$attribute_list) {
			next if !defined $attribute->{'value'};
			$provenance->{ $attribute->{'attribute'} } = $attribute->{'value'};
		}
	}
	return;
}

sub _get_isolate_projects {
	my ( $values, $isolate_id ) = @_;
	my $self         = setting('self');
	my $db           = params->{'db'};
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
			id          => request->uri_for("/db/$db/projects/$project->{'id'}"),
			description => $project->{'short_description'}
		  };
	}
	$values->{'projects'} = \@projects if @projects;
	return;
}

sub _query_isolates {
	my $self = setting('self');
	$self->check_isolate_database;
	my ( $db, $fields ) = ( params->{'db'}, params->{'fields'} );
	my $page      = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $offset    = ( $page - 1 ) * $self->{'page_size'};
	my $count_qry = "SELECT COUNT(*) FROM $self->{'system'}->{'view'}";
	my $qry       = "SELECT id FROM $self->{'system'}->{'view'}";
	my ( @clauses, @values );

	if ( !params->{'all_versions'} ) {
		push @clauses, 'new_version IS NULL';
	}
	my ( $field_query, $field_values ) = _get_field_query($fields);
	if ($field_query) {
		push @clauses, $field_query;
		push @values,  @$field_values;
	}
	if (@clauses) {
		local $" = q[) AND (];
		$qry       .= qq( WHERE (@clauses));
		$count_qry .= qq( WHERE (@clauses));
	}
	my $isolate_count = $self->{'datastore'}->run_query( $count_qry, \@values );
	$qry .= ' ORDER BY id';
	$qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !param('return_all');
	my $ids = $self->{'datastore'}->run_query( $qry, \@values, { fetch => 'col_arrayref' } );
	my $values = { records => int($isolate_count) };
	my $pages  = ceil( $isolate_count / $self->{'page_size'} );
	my $path   = $self->get_full_path("/db/$db/isolates");
	my $paging = $self->get_paging( $path, $pages, $page );
	$values->{'paging'} = $paging if %$paging;
	my @links;
	push @links, request->uri_for("/db/$db/isolates/$_") foreach @$ids;
	$values->{'isolates'} = \@links;
	return $values;
}

sub _get_field_query {
	my ($fields) = @_;
	$fields //= {};
	my $self = setting('self');
	my @field_names;
	my @extended_fields;
	my %extended_primary_field;
	my %extended_value;
	my $values = [];

	foreach my $field ( keys %$fields ) {
		my $is_extended_field = $self->{'datastore'}
		  ->run_query( 'SELECT EXISTS(SELECT * FROM isolate_field_extended_attributes WHERE attribute=?)', $field );
		if ($is_extended_field) {
			push @extended_fields, $field;
			my $ext_att =
			  $self->{'datastore'}
			  ->run_query( 'SELECT * FROM isolate_field_extended_attributes WHERE attribute=? LIMIT 1',
				$field, { fetch => 'row_hashref' } );
			$extended_primary_field{$field} = $ext_att->{'isolate_field'};
			$extended_value{$field}         = $fields->{$field};
			next;
		}
		if ( !$self->{'xmlHandler'}->is_field($field) ) {
			send_error( "$field is not a valid field.", 400 );
		}
		my $att = $self->{'xmlHandler'}->get_field_attributes($field);
		if ( $att->{'type'} =~ /int/x && !BIGSdb::Utils::is_int( $fields->{$field} ) ) {
			send_error( "$field is an integer field.", 400 );
		}
		if ( $att->{'type'} =~ /bool/x && !BIGSdb::Utils::is_bool( $fields->{$field} ) ) {
			send_error( "$field is a boolean field.", 400 );
		}
		if ( $att->{'type'} eq 'date' && !BIGSdb::Utils::is_date( $fields->{$field} ) ) {
			send_error( "$field is a date field.", 400 );
		}
		if ( $att->{'type'} eq 'float' && !BIGSdb::Utils::is_float( $fields->{$field} ) ) {
			send_error( "$field is a float field.", 400 );
		}
		if ( $att->{'type'} eq 'text' ) {
			push @field_names, qq(UPPER($field));
			push @$values,     uc( $fields->{$field} );
		} else {
			push @field_names, $field;
			push @$values,     $fields->{$field};
		}
	}
	my $qry;
	if (@field_names) {
		local $" = q(=? AND );
		$qry = qq(@field_names=?);
	}
	foreach my $ext_field (@extended_fields) {
		$qry .= q( AND ) if $qry;
		$qry .= qq[($extended_primary_field{$ext_field} IN ]
		  . q[(SELECT field_value FROM isolate_value_extended_attributes WHERE ]
		  . q[(isolate_field,attribute,UPPER(value))=(?,?,UPPER(?))))];
		push @$values, $extended_primary_field{$ext_field}, $ext_field, $extended_value{$ext_field};
	}
	return ( $qry, $values );
}
1;
