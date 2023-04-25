#Written by Keith Jolley
#Copyright (c) 2017-2022, University of Oxford
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
package BIGSdb::REST::Routes::Fields;
use strict;
use warnings;
use 5.010;
use JSON;
use Dancer2 appname => 'BIGSdb::REST::Interface';
use BIGSdb::Utils;
use BIGSdb::Constants qw(MIN_GENOME_SIZE);

#Isolate database routes
sub setup_routes {
	my $self = setting('self');
	foreach my $dir ( @{ setting('api_dirs') } ) {
		get "$dir/db/:db/fields"                  => sub { _get_fields() };
		get "$dir/db/:db/fields/:field"           => sub { _get_field() };
		get "$dir/db/:db/fields/:field/breakdown" => sub { _get_breakdown() };
	}
	return;
}

sub _get_fields {
	my $self = setting('self');
	my $db   = params->{'db'};
	$self->check_isolate_database;
	my $subdir = setting('subdir');
	my $fields = $self->{'xmlHandler'}->get_field_list;
	my $values = [];
	foreach my $field (@$fields) {
		my $value = {};
		$value->{'name'} = $field;
		my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
		$thisfield->{'required'} //= 'yes';    #This is the default and may not be specified in config.xml.
		foreach (qw ( type required length min max regex comments)) {
			next if !defined $thisfield->{$_};
			if ( ( ( $_ eq 'min' || $_ eq 'max' ) && $thisfield->{'type'} =~ /^int/x ) || $_ eq 'length' ) {
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
		$value->{'values'}    = request->uri_for("$subdir/db/$db/fields/$field");
		$value->{'breakdown'} = request->uri_for("$subdir/db/$db/fields/$field/breakdown");
		push @$values, $value;
		my $ext_att =
		  $self->{'datastore'}
		  ->run_query( 'SELECT * FROM isolate_field_extended_attributes WHERE isolate_field=? ORDER BY field_order',
			$field, { fetch => 'all_arrayref', slice => {} } );
		foreach my $att (@$ext_att) {
			$att->{'value_format'} = 'int' if $att->{'value_format'} eq 'integer';
			$value = {
				name      => $att->{'attribute'},
				values    => request->uri_for("$subdir/db/$db/fields/$att->{'attribute'}"),
				type      => $att->{'value_format'},
				breakdown => request->uri_for("$subdir/db/$db/fields/$att->{'attribute'}/breakdown")
			};
			$value->{'required'} = JSON::false;
			$value->{'length'}   = $att->{'length'} if $att->{'length'};
			$value->{'regex'}    = $att->{'value_regex'} if $att->{'value_regex'};
			my $comments = qq(Value inferred from $field value.);
			$comments .= qq( $att->{'description'}) if $att->{'description'};
			$value->{'comments'} = $comments;
			push @$values, $value;
		}
	}
	return $values;
}

sub _get_field {
	my $self   = setting('self');
	my $params = params;
	$self->check_isolate_database;
	my ( $db, $field ) = @{$params}{qw(db field)};
	my $subdir            = setting('subdir');
	my $is_extended_field = $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM isolate_field_extended_attributes WHERE attribute=?)', $field );
	if ($is_extended_field) {
		return _get_extended_field($field);
	}
	if ( !$self->{'xmlHandler'}->is_field($field) ) {
		send_error( "Field $field does not exist.", 404 );
	}
	my $value_count =
	  $self->{'datastore'}->run_query("SELECT COUNT(DISTINCT ($field)) FROM $self->{'system'}->{'view'}");
	my $page_values = $self->get_page_values($value_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};
	my $qry = "SELECT DISTINCT $field FROM $self->{'system'}->{'view'} WHERE $field IS NOT NULL ORDER BY $field";
	$qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !param('return_all');
	my $set_values = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	if ( $self->{'datastore'}->field_needs_conversion($field) ) {

		foreach my $value (@$set_values) {
			$value = $self->{'datastore'}->convert_field_value( $field, $value );
		}
		@$set_values = sort @$set_values;
	}
	my $values = {
		records => int($value_count),
		values  => $set_values
	};
	my $paging = $self->get_paging( "$subdir/db/$db/fields/$field", $pages, $page, $offset );
	$values->{'paging'} = $paging if %$paging;
	return $values;
}

sub _get_extended_field {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $field ) = @{$params}{qw(db field)};
	my $subdir = setting('subdir');
	my $ext_att =
	  $self->{'datastore'}->run_query( 'SELECT * FROM isolate_field_extended_attributes WHERE attribute=? LIMIT 1',
		$field, { fetch => 'row_hashref' } );
	my $order;
	foreach my $type (qw (integer float date)) {
		if ( $ext_att->{'value_format'} eq $type ) {
			$order = qq(CAST (value AS $type));
		}
	}
	$order //= 'value';
	my $count_qry =
	    'SELECT COUNT(DISTINCT(value)) FROM isolate_value_extended_attributes WHERE (isolate_field,attribute)=(?,?) '
	  . "AND field_value IN (SELECT DISTINCT($ext_att->{'isolate_field'}) FROM $self->{'system'}->{'view'})";
	my $value_count = $self->{'datastore'}->run_query( $count_qry, [ $ext_att->{'isolate_field'}, $field ] );
	my $page_values = $self->get_page_values($value_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};
	my $qry = 'SELECT DISTINCT(value) FROM isolate_value_extended_attributes WHERE (isolate_field,attribute)=(?,?) '
	  . "AND field_value IN (SELECT DISTINCT($ext_att->{'isolate_field'}) FROM $self->{'system'}->{'view'}) ORDER BY $order";
	$qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !param('return_all');
	my $set_values =
	  $self->{'datastore'}->run_query( $qry, [ $ext_att->{'isolate_field'}, $field ], { fetch => 'col_arrayref' } );
	my $values = {
		records => int($value_count),
		values  => $set_values
	};
	my $paging = $self->get_paging( "$subdir/db/$db/field/$field", $pages, $page, $offset );
	$values->{'paging'} = $paging if %$paging;
	return $values;
}

sub _get_breakdown {
	my $self   = setting('self');
	my $params = params;
	$self->check_isolate_database;
	my ( $db, $field ) = @{$params}{qw(db field)};
	my $is_extended_field = $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM isolate_field_extended_attributes WHERE attribute=?)', $field );
	if ($is_extended_field) {
		return _get_extended_field_breakdown($field);
	}
	if ( !$self->{'xmlHandler'}->is_field($field) ) {
		send_error( "Field $field does not exist.", 404 );
	}
	my $genome_size =
	  BIGSdb::Utils::is_int( params->{'genome_size'} )
	  ? params->{'genome_size'}
	  : $self->{'system'}->{'min_genome_size'} // $self->{'config'}->{'min_genome_size'} // MIN_GENOME_SIZE;
	my $genome_clause =
	  $params->{'genomes'}
	  ? " AND id IN (SELECT isolate_id FROM seqbin_stats WHERE total_length>=$genome_size)"
	  : q();
	my $qry =
	    "SELECT $field,COUNT(*) AS count FROM $self->{'system'}->{'view'} WHERE $field IS NOT NULL AND "
	  . "new_version IS NULL$genome_clause GROUP BY $field";

	#Undocumented call - needed to generate stats of genome submissions
	if ( $params->{'genomes'} && ( $field eq 'date_entered' || $field eq 'datestamp' ) ) {

		#Need to ensure we use minimum date_entered value from sequence bin not the isolate date_entered
		$qry =
		    "CREATE TEMP TABLE temp_table_date_breakdown AS SELECT isolate_id,min($field) AS $field FROM "
		  . 'sequence_bin GROUP BY isolate_id;'
		  . "SELECT $field,COUNT(DISTINCT isolate_id) AS count FROM temp_table_date_breakdown WHERE "
		  . "isolate_id IN (SELECT id FROM $self->{'system'}->{'view'}) GROUP BY $field";
	}
	my $value_counts =
	  $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	if ( $self->{'datastore'}->field_needs_conversion($field) ) {
		foreach my $value_count (@$value_counts) {
			$value_count->{$field} = $self->{'datastore'}->convert_field_value( $field, $value_count->{$field} );
		}
	}
	my %values = map { $_->{$field} => $_->{'count'} } @$value_counts;
	return \%values;
}

sub _get_extended_field_breakdown {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $field ) = @{$params}{qw(db field)};
	$self->check_isolate_database;
	my $ext_att =
	  $self->{'datastore'}->run_query( 'SELECT * FROM isolate_field_extended_attributes WHERE attribute=? LIMIT 1',
		$field, { fetch => 'row_hashref' } );
	my $genome_size =
	  BIGSdb::Utils::is_int( params->{'genome_size'} ) ? params->{'genome_size'} : MIN_GENOME_SIZE;
	my $genome_clause =
	  $params->{'genomes'}
	  ? " AND id IN (SELECT isolate_id FROM seqbin_stats WHERE total_length>=$genome_size)"
	  : q();
	my $value_counts = $self->{'datastore'}->run_query(
		"SELECT a.value AS $field,COUNT(*) AS count FROM $self->{'system'}->{'view'} v "
		  . "JOIN isolate_value_extended_attributes a ON v.$ext_att->{'isolate_field'}=a.field_value "
		  . "WHERE new_version IS NULL$genome_clause GROUP BY a.value",
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my %values = map { $_->{$field} => $_->{'count'} } @$value_counts;
	return \%values;
}
1;
