#Written by Keith Jolley
#Copyright (c) 2017, University of Oxford
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
package BIGSdb::REST::Routes::Fields;
use strict;
use warnings;
use 5.010;
use JSON;
use Dancer2 appname => 'BIGSdb::REST::Interface';
use BIGSdb::Utils;

#Isolate database routes
get '/db/:db/fields'        => sub { _get_fields() };
get '/db/:db/fields/:field' => sub { _get_field() };

sub _get_fields {
	my $self = setting('self');
	my $db   = params->{'db'};
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
		$value->{'values'} = request->uri_for("/db/$db/fields/$field");
		push @$values, $value;
		my $ext_att =
		  $self->{'datastore'}
		  ->run_query( 'SELECT * FROM isolate_field_extended_attributes WHERE isolate_field=? ORDER BY field_order',
			$field, { fetch => 'all_arrayref', slice => {} } );
		foreach my $att (@$ext_att) {
			$att->{'value_format'} = 'int' if $att->{'value_format'} eq 'integer';
			$value = {
				name   => $att->{'attribute'},
				values => request->uri_for("/db/$db/fields/$att->{'attribute'}"),
				type   => $att->{'value_format'}
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
	my $values = {
		records => int($value_count),
		values  => $set_values
	};
	my $paging = $self->get_paging( "/db/$db/fields/$field", $pages, $page, $offset );
	$values->{'paging'} = $paging if %$paging;
	return $values;
}

sub _get_extended_field {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $field ) = @{$params}{qw(db field)};
	my $ext_att =
	  $self->{'datastore'}->run_query( 'SELECT * FROM isolate_field_extended_attributes WHERE attribute=? LIMIT 1',
		$field, { fetch => 'row_hashref' } );
	my $order;
	foreach my $type (qw (integer float data)) {
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
	my $paging = $self->get_paging( "/db/$db/field/$field", $pages, $page, $offset );
	$values->{'paging'} = $paging if %$paging;
	return $values;
}
1;
