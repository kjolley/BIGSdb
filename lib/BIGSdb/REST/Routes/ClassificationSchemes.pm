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
use POSIX qw(ceil);
use Dancer2 appname => 'BIGSdb::REST::Interface';

#Scheme routes
get '/db/:db/classification_schemes'                           => sub { _get_classification_schemes() };
get '/db/:db/classification_schemes/:cscheme_id'               => sub { _get_classification_scheme() };
get '/db/:db/classification_schemes/:cscheme_id/groups/:group' => sub { _get_group() };

sub _get_classification_schemes {
	my $self          = setting('self');
	my ($db)          = params->{'db'};
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
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
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
			  request->uri_for("/db/$db/schemes/$c_scheme->{'scheme_id'}/profiles/$group_profile->{'profile_id'}");
		}
		$values->{'groups'} = [];
		foreach my $group (sort {$a <=> $b} keys %$groups){
			push @{$values->{'groups'}}, {
				id => int($group),
				profiles=>$groups->{$group}
			};
		}
	}
	return $values;
}

sub _get_group {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $id, $cs, $group ) = @{$params}{qw(db id cscheme_id group)};
	$self->check_isolate_database;
	my $cscheme = $self->{'datastore'}
	  ->run_query( 'SELECT * FROM classification_schemes WHERE id=?', $cs, { fetch => 'row_hashref' } );
	if ( !$cscheme ) {
		send_error( "Classification scheme $cs does not exist.", 404 );
	}
	my $view               = $self->{'system'}->{'view'};
	my $scheme_id          = $cscheme->{'scheme_id'};
	my $cache_table_exists = $self->{'datastore'}->run_query(
		'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=? OR table_name=?)',
		[ "temp_isolates_scheme_fields_$scheme_id", "temp_${view}_scheme_fields_$scheme_id" ]
	);
	if ( !$cache_table_exists ) {

		#Scheme is not cached for this database - abort.
		return { records => 0, isolates => [] };
	}
	my $scheme_info   = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $scheme_table  = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
	my $cscheme_table = $self->{'datastore'}->create_temp_cscheme_table($cs);
	my $pk            = $scheme_info->{'primary_key'};
	my $page            = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
		my $qry             = "SELECT COUNT(*) FROM $view WHERE $view.id IN (SELECT s.id FROM $scheme_table s "
	  . "JOIN $cscheme_table c ON s.$pk=c.profile_id WHERE c.group_id=?) AND $view.new_version IS NULL";
	my $isolate_count   = $self->{'datastore'}->run_query($qry,$group);
	my $pages           = ceil( $isolate_count / $self->{'page_size'} );
	my $offset          = ( $page - 1 ) * $self->{'page_size'};
	
	
	$qry =
	    "SELECT $view.id FROM $view WHERE $view.id IN (SELECT s.id FROM $scheme_table s "
	  . "JOIN $cscheme_table c ON s.$pk=c.profile_id WHERE c.group_id=?) AND $view.new_version IS NULL "
	  . "ORDER BY $view.id";
	  $qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !param('return_all');
	my $isolate_ids = $self->{'datastore'}->run_query( $qry, $group, { fetch => 'col_arrayref' } );
	my $isolate_uris = [];

	foreach my $isolate_id (@$isolate_ids) {
		push @$isolate_uris, request->uri_for("/db/$db/isolates/$isolate_id");
	}
	my $path = $self->get_full_path( "/db/$db/classification_schemes/$cs/groups/$group" );
	my $paging = $self->get_paging( $path, $pages, $page );
		my $values = {
		records  => $isolate_count,
		isolates => $isolate_uris
	};
	$values->{'paging'} = $paging if %$paging;
	return $values;
}
1;
