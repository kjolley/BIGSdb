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
use Dancer2 appname => 'BIGSdb::REST::Interface';
use BIGSdb::Utils;

#Isolate database routes
get '/db/:db/isolates' => sub {
	my $self          = setting('self');
	my ($db)          = params->{'db'};
	my $page          = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $isolate_count = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM $self->{'system'}->{'view'}");
	my $pages         = int( $isolate_count / $self->{'page_size'} ) + 1;
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
	my $values = [];
	my $field_values =
	  $self->{'datastore'}->run_query( "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?", $id, { fetch => 'row_hashref' } );
	if ( !defined $field_values->{'id'} ) {
		status(404);
		return { error => "Isolate $id does not exist." };
	}
	my $field_list = $self->{'xmlHandler'}->get_field_list;
	foreach my $field (@$field_list) {
		if ( $field eq 'sender' || $field eq 'curator' ) {
			push @$values, { $field => request->uri_for("/db/$db/users/$field_values->{$field}")->as_string };
		} else {
			push @$values, { $field => $field_values->{ lc $field } } if defined $field_values->{ lc $field };
		}
	}
	my $pubmed_ids =
	  $self->{'datastore'}
	  ->run_query( "SELECT pubmed_id FROM refs WHERE isolate_id=? ORDER BY pubmed_id", $id, { fetch => 'col_arrayref' } );
	if (@$pubmed_ids) {
		my @refs;
		push @refs, $self->get_pubmed_link($_) foreach @$pubmed_ids;
		push @$values, { publications => \@refs };
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
		my $value = [ { name => $field } ];
		my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
		foreach (qw ( type required length min max regex comments)) {
			push @$value, { $_ => $thisfield->{$_} } if defined $thisfield->{$_};
		}
		if ( ( $thisfield->{'optlist'} // '' ) eq 'yes' ) {
			push @$value, { allowed_values => $self->{'xmlHandler'}->get_field_option_list($field) };
		}
		push @$values, $value;
	}
	return $values;
};
1;
