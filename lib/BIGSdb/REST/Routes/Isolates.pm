#Written by Keith Jolley
#Copyright (c) 2014-2019, University of Oxford
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
use JSON;
use Dancer2 appname => 'BIGSdb::REST::Interface';
use BIGSdb::Utils;
use constant GENOME_SIZE => 500_000;

#Isolate database routes
sub setup_routes {
	my $self = setting('self');
	foreach my $dir ( @{ setting('api_dirs') } ) {
		get "$dir/db/:db/isolates"             => sub { _get_isolates() };
		get "$dir/db/:db/genomes"              => sub { _get_genomes() };
		get "$dir/db/:db/isolates/:id"         => sub { _get_isolate() };
		get "$dir/db/:db/isolates/:id/history" => sub { _get_history() };
		post "$dir/db/:db/isolates/search"     => sub { _query_isolates() };
	}
	return;
}

sub _get_isolates {
	my $self = setting('self');
	$self->check_isolate_database;
	my $params          = params;
	my $db              = params->{'db'};
	my $subdir          = setting('subdir');
	my $allowed_filters = [qw(added_after added_on updated_after updated_on)];
	my $qry = $self->add_filters( "SELECT COUNT(*),MAX(date_entered),MAX(datestamp) FROM $self->{'system'}->{'view'}",
		$allowed_filters );
	my ( $isolate_count, $last_added, $last_updated ) = $self->{'datastore'}->run_query($qry);
	my $page_values = $self->get_page_values($isolate_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};
	$qry = $self->add_filters( "SELECT id FROM $self->{'system'}->{'view'}", $allowed_filters );
	$qry .= ' ORDER BY id';
	$qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !param('return_all');
	my $ids = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	my $values = { records => int($isolate_count) };
	$values->{'last_added'}   = $last_added   if $last_added;
	$values->{'last_updated'} = $last_updated if $last_updated;
	my $path = $self->get_full_path( "$subdir/db/$db/isolates", $allowed_filters );
	my $paging = $self->get_paging( $path, $pages, $page, $offset );
	$values->{'paging'} = $paging if %$paging;
	my @links;
	push @links, request->uri_for("$subdir/db/$db/isolates/$_") foreach @$ids;
	$values->{'isolates'} = \@links;
	return $values;
}

sub _get_genomes {
	my $self = setting('self');
	$self->check_isolate_database;
	my $params          = params;
	my $db              = params->{'db'};
	my $subdir          = setting('subdir');
	my $allowed_filters = [qw(added_after updated_after genome_size)];
	my $genome_size     = BIGSdb::Utils::is_int( params->{'genome_size'} ) ? params->{'genome_size'} : GENOME_SIZE;
	my $qry             = $self->add_filters(
		"SELECT COUNT(*),MAX(date_entered),MAX(datestamp) FROM $self->{'system'}->{'view'} v JOIN seqbin_stats s "
		  . "ON v.id=s.isolate_id WHERE s.total_length>=$genome_size",
		$allowed_filters
	);
	my ( $isolate_count, $last_added, $last_updated ) = $self->{'datastore'}->run_query($qry);
	my $page_values = $self->get_page_values($isolate_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};
	$qry = $self->add_filters(
		"SELECT id FROM $self->{'system'}->{'view'} v JOIN seqbin_stats s "
		  . "ON v.id=s.isolate_id WHERE s.total_length>=$genome_size",
		$allowed_filters
	);
	$qry .= ' ORDER BY id';
	$qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !param('return_all');
	my $ids = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	my $values = { records => int($isolate_count) };
	$values->{'last_added'}   = $last_added   if $last_added;
	$values->{'last_updated'} = $last_updated if $last_updated;
	my $path = $self->get_full_path( "$subdir/db/$db/genomes", $allowed_filters );
	my $paging = $self->get_paging( $path, $pages, $page, $offset );
	$values->{'paging'} = $paging if %$paging;
	my @links;
	push @links, request->uri_for("$subdir/db/$db/isolates/$_") foreach @$ids;
	$values->{'isolates'} = \@links;
	return $values;
}

sub _get_isolate {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $id ) = @{$params}{qw(db id)};
	my $subdir = setting('subdir');
	$self->check_isolate_database;
	$self->check_isolate_is_valid($id);
	my $values = {};
	my $field_values =
	  $self->{'datastore'}
	  ->run_query( "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?", $id, { fetch => 'row_hashref' } );
	my $field_list = $self->{'xmlHandler'}->get_field_list;
	my $provenance = {};

	foreach my $field (@$field_list) {
		if ( $field eq 'sender' || $field eq 'curator' ) {
			$provenance->{$field} = request->uri_for("$subdir/db/$db/users/$field_values->{$field}");
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
	return $values if $params->{'provenance_only'};
	my $phenotypic = _get_phenotypic_values($id);
	$values->{'phenotypic'} = $phenotypic if %$phenotypic;
	my $has_history = $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM history WHERE isolate_id=?)', $id );
	$values->{'history'} = request->uri_for("$subdir/db/$db/isolates/$id/history") if $has_history;
	my $publications = _get_publications($id);
	$values->{'publications'} = $publications if @$publications;
	my $seqbin_stats =
	  $self->{'datastore'}
	  ->run_query( 'SELECT * FROM seqbin_stats WHERE isolate_id=?', $id, { fetch => 'row_hashref' } );

	if ($seqbin_stats) {
		my $seqbin = {
			contig_count  => $seqbin_stats->{'contigs'},
			total_length  => $seqbin_stats->{'total_length'},
			contigs       => request->uri_for("$subdir/db/$db/isolates/$id/contigs"),
			contigs_fasta => request->uri_for("$subdir/db/$db/isolates/$id/contigs_fasta")
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
			full_designations => request->uri_for("$subdir/db/$db/isolates/$id/allele_designations"),
			allele_ids        => request->uri_for("$subdir/db/$db/isolates/$id/allele_ids")
		};
	}
	my $scheme_links = _get_scheme_data($id);
	$values->{'schemes'} = $scheme_links if @$scheme_links;
	_get_isolate_projects( $values, $id );
	if ( BIGSdb::Utils::is_int( $field_values->{'new_version'} ) ) {
		$values->{'new_version'} = request->uri_for("$subdir/db/$db/isolates/$field_values->{'new_version'}");
	}
	my $old_version =
	  $self->{'datastore'}->run_query( "SELECT id FROM $self->{'system'}->{'view'} WHERE new_version=?", $id );
	if ($old_version) {
		$values->{'old_version'} = request->uri_for("$subdir/db/$db/isolates/$old_version");
	}
	return $values;
}

sub _get_publications {
	my ($isolate_id) = @_;
	my $self = setting('self');
	my $pubmed_ids =
	  $self->{'datastore'}->run_query( 'SELECT pubmed_id FROM refs WHERE isolate_id=? ORDER BY pubmed_id',
		$isolate_id, { fetch => 'col_arrayref' } );
	my $publications = [];
	foreach my $pubmed_id (@$pubmed_ids) {
		push @$publications,
		  {
			pubmed_id     => int($pubmed_id),
			citation_link => "https://www.ncbi.nlm.nih.gov/pubmed/$pubmed_id"
		  };
	}
	return $publications;
}

sub _get_history {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $id ) = @{$params}{qw(db id)};
	my $subdir = setting('subdir');
	my $data   = $self->{'datastore'}->run_query( 'SELECT * FROM history WHERE isolate_id=? ORDER BY timestamp',
		$id, { fetch => 'all_arrayref', slice => {} } );
	my $history = [];
	foreach my $record (@$data) {
		my @actions = split /<br\ \/>/x, $record->{'action'};
		push @$history,
		  {
			curator   => request->uri_for("$subdir/db/$db/users/$record->{'curator'}"),
			actions   => \@actions,
			timestamp => $record->{'timestamp'}
		  };
	}
	return { records => scalar @$history, updates => $history };
}

sub _get_similar {
	my ( $scheme_id, $isolate_id ) = @_;
	my $self   = setting('self');
	my $params = params;
	my ( $db, $id ) = @{$params}{qw(db id)};
	my $subdir = setting('subdir');
	my $view   = $self->{'system'}->{'view'};
	my $values = {};
	my $classification_schemes =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id,name FROM classification_schemes WHERE scheme_id=? ORDER BY display_order,name',
		$scheme_id, { fetch => 'all_arrayref', slice => {} } );

	foreach my $cscheme (@$classification_schemes) {
		my $cache_table_exists = $self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=? OR table_name=?)',
			[ "temp_isolates_scheme_fields_$scheme_id", "temp_${view}_scheme_fields_$scheme_id" ]
		);
		if ( !$cache_table_exists ) {

			#Scheme is not cached for this database - abort.
			return {};
		}
		my $scheme_info  = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		my $scheme_table = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
		my $pk           = $scheme_info->{'primary_key'};
		my $pk_values =
		  $self->{'datastore'}
		  ->run_query( "SELECT $pk FROM $scheme_table WHERE id=?", $isolate_id, { fetch => 'col_arrayref' } );
		my $c_scheme_values = [];
		if (@$pk_values) {
			my $cscheme_table = $self->{'datastore'}->create_temp_cscheme_table( $cscheme->{'id'} );

			#You may get multiple groups if you have a mixed sample
			my %group_displayed;
			foreach my $pk_value (@$pk_values) {
				my $groups = $self->{'datastore'}->run_query( "SELECT group_id FROM $cscheme_table WHERE profile_id=?",
					$pk_value, { fetch => 'col_arrayref' } );
				foreach my $group_id (@$groups) {
					next if $group_displayed{$group_id};
					my $isolate_count = $self->{'datastore'}->run_query(
						"SELECT COUNT(*) FROM $view WHERE $view.id IN (SELECT id FROM $scheme_table WHERE $pk IN "
						  . "(SELECT profile_id FROM $cscheme_table WHERE group_id=?)) AND new_version IS NULL",
						$group_id
					);
					if ( $isolate_count > 1 ) {
						push @$c_scheme_values,
						  {
							group    => int($group_id),
							records  => $isolate_count,
							isolates => request->uri_for(
								"$subdir/db/$db/classification_schemes/$cscheme->{'id'}/groups/$group_id")
						  };
					}
				}
			}
		}
		if (@$c_scheme_values) {
			$values->{ $cscheme->{'name'} }->{'href'} =
			  request->uri_for("$subdir/db/$db/classification_schemes/$cscheme->{'id'}");
			$values->{ $cscheme->{'name'} }->{'groups'} = $c_scheme_values;
		}
	}
	return $values;
}

sub _get_scheme_data {
	my ($isolate_id) = @_;
	my $self         = setting('self');
	my $db           = params->{'db'};
	my $subdir       = setting('subdir');
	my $set_id       = $self->get_set_id;
	my $scheme_list = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	my $scheme_links = [];
	foreach my $scheme (@$scheme_list) {
		my $allele_designations =
		  $self->{'datastore'}->get_scheme_allele_designations( $isolate_id, $scheme->{'id'}, { set_id => $set_id } );
		next if !$allele_designations;
		my $scheme_object = {
			description           => $scheme->{'name'},
			loci_designated_count => scalar keys %$allele_designations,
			full_designations =>
			  request->uri_for("$subdir/db/$db/isolates/$isolate_id/schemes/$scheme->{'id'}/allele_designations"),
			allele_ids => request->uri_for("$subdir/db/$db/isolates/$isolate_id/schemes/$scheme->{'id'}/allele_ids")
		};
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme->{'id'}, { set_id => $set_id, get_pk => 1 } );
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields( $scheme->{'id'} );
		if ( defined $scheme_info->{'primary_key'} ) {
			my $scheme_field_values =
			  $self->{'datastore'}->get_scheme_field_values_by_designations( $scheme->{'id'}, $allele_designations );
			my $field_values = {};
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
			my $similar_isolates = _get_similar( $scheme->{'id'}, $isolate_id );
			if ( keys %$similar_isolates ) {
				$scheme_object->{'classification_schemes'} = $similar_isolates;
			}
		}
		push @$scheme_links, $scheme_object;
	}
	return $scheme_links;
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

sub _get_phenotypic_values {
	my ($isolate_id) = @_;
	my $self         = setting('self');
	my $values       = {};
	foreach my $table (qw(eav_int eav_float eav_text eav_date eav_boolean)) {
		my $table_values = $self->{'datastore'}->run_query( "SELECT field,value FROM $table WHERE isolate_id=?",
			$isolate_id, { fetch => 'all_arrayref', slice => {} } );
		$values->{ $_->{'field'} } = $_->{'value'} foreach @$table_values;
	}
	return $values;
}

sub _get_isolate_projects {
	my ( $values, $isolate_id ) = @_;
	my $self         = setting('self');
	my $db           = params->{'db'};
	my $subdir       = setting('subdir');
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
			id          => request->uri_for("$subdir/db/$db/projects/$project->{'id'}"),
			description => $project->{'short_description'}
		  };
	}
	$values->{'projects'} = \@projects if @projects;
	return;
}

sub _unflatten_params {
	my $self         = setting('self');
	my $params       = body_parameters;
	my $query        = {};
	my @defined_cats = qw(field locus scheme);
	my %defined      = map { $_ => 1 } @defined_cats;
	foreach my $param ( keys %$params ) {
		next if $param =~ /^oauth_/x;
		my ( $cat, $field_or_scheme, $scheme_id ) = split /\./x, $param;
		if ( !$defined{$cat} ) {
			send_error( "$cat is not a recognized query parameter", 400 );
		}
		if ( $cat eq 'field' || $cat eq 'locus' ) {
			$query->{$cat}->{$field_or_scheme} = $params->{$param};
			next;
		}
		if ( $cat eq 'scheme' ) {
			$query->{$cat}->{$field_or_scheme}->{$scheme_id} = $params->{$param};
		}
	}
	return $query;
}

sub _query_isolates {
	my $self = setting('self');
	$self->check_isolate_database;
	$self->check_post_payload;
	my $db        = params->{'db'};
	my $subdir    = setting('subdir');
	my $count_qry = "SELECT COUNT(*) FROM $self->{'system'}->{'view'}";
	my $qry       = "SELECT id FROM $self->{'system'}->{'view'}";
	my $params    = _unflatten_params();
	if ( !keys %$params ) {
		send_error( 'No query passed', 400 );
	}
	my @categories = keys %$params;
	my ( @clauses, @values );
	if ( !params->{'all_versions'} ) {
		push @clauses, 'new_version IS NULL';
	}
	my $methods = {
		field  => \&_get_field_query,
		locus  => \&_get_locus_query,
		scheme => \&_get_scheme_query
	};
	foreach my $category (@categories) {
		my ( $cat_qry, $cat_values ) = $methods->{$category}->( $params->{$category} );
		if ($cat_qry) {
			push @clauses, $cat_qry;
			push @values,  @$cat_values;
		}
	}
	if (@clauses) {
		local $" = q[) AND (];
		$qry       .= qq( WHERE (@clauses));
		$count_qry .= qq( WHERE (@clauses));
	}
	my $isolate_count = $self->{'datastore'}->run_query( $count_qry, \@values );
	my $page_values = $self->get_page_values($isolate_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};
	$qry .= ' ORDER BY id';
	$qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !param('return_all');
	my $ids = $self->{'datastore'}->run_query( $qry, \@values, { fetch => 'col_arrayref' } );
	my $values = { records => int($isolate_count) };
	my $path   = $self->get_full_path("$subdir/db/$db/isolates");
	my $paging = $self->get_paging( $path, $pages, $page, $offset );
	$values->{'paging'} = $paging if %$paging;
	my @links;
	push @links, request->uri_for("$subdir/db/$db/isolates/$_") foreach @$ids;
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

	if ( ref $fields ne 'HASH' ) {
		send_error( 'Malformed request', 400 );
	}
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
		push @field_names, $field;
		if ( $att->{'type'} eq 'text' ) {
			push @$values, uc( $fields->{$field} );
		} else {
			push @$values, $fields->{$field};
		}
	}
	my $qry;
	my $first = 1;
	if (@field_names) {
		foreach my $field (@field_names) {
			$qry .= ' AND ' if !$first;
			my $att = $self->{'xmlHandler'}->get_field_attributes($field);
			if ( $att->{'type'} eq 'text' ) {
				if ( ( $att->{'multiple'} // q() ) eq 'yes' ) {
					$qry .= qq(? ILIKE ANY($field));
				} else {
					$qry .= qq(UPPER($field)=?);
				}
			} else {
				$qry .= qq($field=?);
			}
			$first = 0;
		}
	}
	foreach my $ext_field (@extended_fields) {
		$qry .= q( AND ) if $qry;
		$qry .=
		    qq[($extended_primary_field{$ext_field} IN ]
		  . q[(SELECT field_value FROM isolate_value_extended_attributes WHERE ]
		  . q[(isolate_field,attribute,UPPER(value))=(?,?,UPPER(?))))];
		push @$values, $extended_primary_field{$ext_field}, $ext_field, $extended_value{$ext_field};
	}
	return ( $qry, $values );
}

sub _get_locus_query {
	my ($loci) = @_;
	$loci //= {};
	my $self = setting('self');
	my @locus_names;
	my $values = [];
	foreach my $locus ( keys %$loci ) {
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		if ( !$locus_info ) {
			send_error( "$locus is not a valid locus", 400 );
		}
		push @locus_names, $locus;
	}
	my $qry;
	if (@locus_names) {
		my $view = $self->{'system'}->{'view'};
		foreach my $locus (@locus_names) {
			$qry .= q( AND ) if $qry;
			$qry .= qq($view.id IN (SELECT isolate_id FROM allele_designations WHERE (locus,allele_id)=(?,?)));
			push @$values, $locus, $loci->{$locus};
		}
	}
	return ( $qry, $values );
}

sub _get_scheme_query {
	my ($schemes) = @_;
	$schemes //= {};
	my $self = setting('self');
	my $qry;
	my $values = [];
	my $view   = $self->{'system'}->{'view'};
	foreach my $scheme_id ( keys %$schemes ) {
		if ( BIGSdb::Utils::is_int($scheme_id) ) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
			if ( !$scheme_info ) {
				send_error( "Scheme $scheme_id does not exist", 400 );
			}
			foreach my $field ( keys %{ $schemes->{$scheme_id} } ) {
				my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
				if ( !$field_info ) {
					send_error( "Scheme $scheme_id field $field does not exist", 400 );
				}
				if ( $field_info->{'type'} =~ /int/x && !BIGSdb::Utils::is_int( $schemes->{$scheme_id}->{$field} ) ) {
					send_error( "$field is an integer field.", 400 );
				}
				if ( $field_info->{'type'} =~ /bool/x
					&& !BIGSdb::Utils::is_bool( $schemes->{$scheme_id}->{$field} ) )
				{
					send_error( "$field is a boolean field.", 400 );
				}
				if ( $field_info->{'type'} eq 'date'
					&& !BIGSdb::Utils::is_date( $schemes->{$scheme_id}->{$field} ) )
				{
					send_error( "$field is a date field.", 400 );
				}
				if ( $field_info->{'type'} eq 'float'
					&& !BIGSdb::Utils::is_float( $schemes->{$scheme_id}->{$field} ) )
				{
					send_error( "$field is a float field.", 400 );
				}
				my $isolate_scheme_field_view =
				  $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
				$qry .= q( AND ) if $qry;
				$qry .= qq($view.id IN (SELECT id FROM $isolate_scheme_field_view WHERE $field=?));
				push @$values, $schemes->{$scheme_id}->{$field};
			}
		} else {
			send_error( 'Scheme id must be an integer', 400 );
		}
	}
	return ( $qry, $values );
}
1;
