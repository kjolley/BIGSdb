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
package BIGSdb::REST::Routes::ClassificationSchemes;
use strict;
use warnings;
use 5.010;
use JSON;
use Dancer2 appname => 'BIGSdb::REST::Interface';

#Scheme routes
get '/db/:db/classification_schemes'             => sub { _get_classification_schemes() };
get '/db/:db/classification_schemes/:cscheme_id' => sub { _get_classification_scheme() };

sub _get_classification_schemes {
	my $self = setting('self');
	my ($db) = params->{'db'};
	$self->check_seqdef_database;
	my $c_scheme_list = $self->{'datastore'}
	  ->run_query( 'SELECT id FROM classification_schemes ORDER BY id', undef, { fetch => 'col_arrayref' } );
	my $count     = @$c_scheme_list;
	my $c_schemes = [];
	foreach my $c_scheme_id (@$c_scheme_list) {
		push @$c_schemes, request->uri_for("/db/$db/classification_schemes/$c_scheme_id");
	}
	my $values = { records => int($count), classification_schemes => $c_schemes };
	return $values;
}

sub _get_classification_scheme {
	my $self = setting('self');
	my ( $db, $cscheme_id ) = ( params->{'db'}, params->{'cscheme_id'} );
	$self->check_seqdef_database;
	if ( !BIGSdb::Utils::is_int($cscheme_id) ) {
		send_error( 'Classification scheme id must be an integer.', 400 );
	}
	my $c_scheme = $self->{'datastore'}
	  ->run_query( 'SELECT * FROM classification_schemes WHERE id=?', $cscheme_id, { fetch => 'row_hashref' } );
	if ( !$c_scheme ) {
		send_error( "Classification scheme $cscheme_id does not exist.", 404 );
	}
	my $values = {
		id                  => int($cscheme_id),
		scheme              => request->uri_for("/db/$db/schemes/$c_scheme->{'scheme_id'}"),
		name                => $c_scheme->{'name'},
		inclusion_threshold => $c_scheme->{'inclusion_threshold'},
		relative_threshold  => $c_scheme->{'use_relative_threshold'} ? JSON::true : JSON::false
	};
	$values->{'description'} = $c_scheme->{'description'} if $c_scheme->{'description'};
	my $set_id = $self->get_set_id;
	my $scheme_info =
	  $self->{'datastore'}->get_scheme_info( $c_scheme->{'scheme_id'}, { get_pk => 1, set_id => $set_id } );
	my $pk_field_info =
	  $self->{'datastore'}->get_scheme_field_info( $c_scheme->{'scheme_id'}, $scheme_info->{'primary_key'} );
	my $profile_order = $pk_field_info->{'type'} eq 'integer' ? 'CAST(profile_id AS int)' : 'profile_id';
	my $group_profiles = $self->{'datastore'}->run_query(
		'SELECT group_id,profile_id FROM classification_group_profiles '
		  . "WHERE cg_scheme_id=? ORDER BY group_id,$profile_order",
		$cscheme_id,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $groups = {};

	foreach my $group_profile (@$group_profiles) {
		push @{ $groups->{ $group_profile->{'group_id'} } },
		  request->uri_for("/db/$db/schemes/$c_scheme->{'scheme_id'}/profiles/$group_profile->{'profile_id'}")
		  ;
	}
	$values->{'groups'} = $groups;
	return $values;
}
1;
