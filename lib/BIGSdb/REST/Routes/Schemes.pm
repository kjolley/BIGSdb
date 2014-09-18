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
package BIGSdb::REST::Routes::Schemes;
use strict;
use warnings;
use 5.010;
use Dancer2 appname => 'BIGSdb::REST::Interface';

#Scheme routes
get '/db/:db/schemes' => sub {
	my $self    = setting('self');
	my ($db)    = params->{'db'};
	my $set_id  = $self->get_set_id;
	my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	my $values  = [];
	foreach my $scheme (@$schemes) {
		push @$values,
		  [ { href => request->uri_for("/db/$db/schemes/$scheme->{'id'}")->as_string }, { description => $scheme->{'description'} } ];
	}
	return $values;
};
get '/db/:db/schemes/:scheme' => sub {
	my $self = setting('self');
	my ( $db, $scheme_id ) = ( params->{'db'}, params->{'scheme'} );
	my $set_id = $self->get_set_id;
	my $values = [];
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		status(400);
		return { error => 'Scheme id must be an integer.' };
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	if ( !$scheme_info ) {
		status(404);
		return { error => "Scheme $scheme_id does not exist." };
	}
	push @$values, { description => $scheme_info->{'description'} };
	push @$values, { has_primary_key_field => $scheme_info->{'primary_key'} ? 'true' : 'false' };
	push @$values,
	  { primary_key_field => request->uri_for("/db/$db/schemes/$scheme_id/fields/$scheme_info->{'primary_key'}")->as_string }
	  if $scheme_info->{'primary_key'};
	my $scheme_fields      = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $scheme_field_links = [];
	foreach my $field (@$scheme_fields) {
		push @$scheme_field_links, request->uri_for("/db/$db/schemes/$scheme_id/fields/$field")->as_string;
	}
	push @$values, { fields => $scheme_field_links } if @$scheme_field_links;
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	push @$values, { locus_count => scalar @$loci };
	my $locus_links = [];
	foreach my $locus (@$loci) {
		my $cleaned_locus = $self->clean_locus($locus);
		push @$locus_links, request->uri_for("/db/$db/loci/$cleaned_locus")->as_string;
	}
	push @$values, { loci => $locus_links } if @$locus_links;
	return $values;
};
get '/db/:db/schemes/:scheme/fields/:field' => sub {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $scheme_id, $field ) = @{$params}{qw(db scheme field)};
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		status(400);
		return { error => 'Scheme id must be an integer.' };
	}
	my $values = [];
	my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
	if ( !$field_info ) {
		status(404);
		return { error => "Scheme field $field does not exist in scheme $scheme_id." };
	}
	foreach my $attribute (qw(field type description)) {
		push @$values, { $attribute => $field_info->{$attribute} } if defined $field_info->{$attribute};
	}
	push @$values, { primary_key => $field_info->{'primary_key'} ? 'true' : 'false' };
	return $values;
};
1;
