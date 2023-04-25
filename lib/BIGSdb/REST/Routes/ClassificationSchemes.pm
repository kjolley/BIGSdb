#Written by Keith Jolley
#Copyright (c) 2017-2021, University of Oxford
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
package BIGSdb::REST::Routes::ClassificationSchemes;
use strict;
use warnings;
use 5.010;
use JSON;
use Dancer2 appname => 'BIGSdb::REST::Interface';

#Scheme routes
sub setup_routes {
	my $self = setting('self');
	foreach my $dir ( @{ setting('api_dirs') } ) {
		get "$dir/db/:db/classification_schemes"                           => sub { _get_classification_schemes() };
		get "$dir/db/:db/classification_schemes/:cscheme_id"               => sub { _get_classification_scheme() };
		get "$dir/db/:db/classification_schemes/:cscheme_id/groups"        => sub { _get_groups() };
		get "$dir/db/:db/classification_schemes/:cscheme_id/groups/:group" => sub { _get_group() };
	}
	return;
}

sub _get_classification_schemes {
	my $self          = setting('self');
	my ($db)          = params->{'db'};
	my $c_scheme_list = $self->{'datastore'}
	  ->run_query( 'SELECT id FROM classification_schemes ORDER BY id', undef, { fetch => 'col_arrayref' } );
	my $count     = @$c_scheme_list;
	my $c_schemes = [];
	my $subdir    = setting('subdir');
	foreach my $c_scheme_id (@$c_scheme_list) {
		push @$c_schemes, request->uri_for("$subdir/db/$db/classification_schemes/$c_scheme_id");
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
	my $subdir = setting('subdir');
	my $values = {
		id                  => int($cscheme_id),
		scheme              => request->uri_for("$subdir/db/$db/schemes/$c_scheme->{'scheme_id'}"),
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
		$values->{'groups'} = request->uri_for("$subdir/db/$db/classification_schemes/$cscheme_id/groups");
	}
	return $values;
}

sub _get_groups {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $id, $cscheme_id, $group ) = @{$params}{qw(db id cscheme_id group)};
	my $subdir = setting('subdir');
	$self->check_seqdef_database;
	my $group_count =
	  $self->{'datastore'}
	  ->run_query( 'SELECT COUNT(DISTINCT(group_id)) FROM classification_group_profiles WHERE cg_scheme_id=?',
		$cscheme_id );
	my $page_values = $self->get_page_values($group_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};
	my $qry = 'SELECT DISTINCT(group_id) FROM classification_group_profiles WHERE cg_scheme_id=? ORDER BY group_id';
	$qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !param('return_all');
	my $values = { records => int($group_count) };
	my $path   = $self->get_full_path("$subdir/db/$db/classification_schemes/$cscheme_id/groups");
	my $paging = $self->get_paging( $path, $pages, $page, $offset );
	$values->{'paging'} = $paging if %$paging;
	my $group_ids = $self->{'datastore'}->run_query( $qry, $cscheme_id, { fetch => 'col_arrayref' } );
	my @links;
	push @links, request->uri_for("$path/$_") foreach @$group_ids;
	$values->{'groups'} = \@links;
	return $values;
}

sub _get_group_seqdef {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $id, $cs, $group ) = @{$params}{qw(db id cscheme_id group)};
	$self->check_seqdef_database;
	my $subdir  = setting('subdir');
	my $cscheme = $self->{'datastore'}
	  ->run_query( 'SELECT * FROM classification_schemes WHERE id=?', $cs, { fetch => 'row_hashref' } );
	if ( !$cscheme ) {
		send_error( "Classification scheme $cs does not exist.", 404 );
	}
	my $scheme_id = $cscheme->{'scheme_id'};
	my $profile_count =
	  $self->{'datastore'}
	  ->run_query( 'SELECT COUNT(*) FROM classification_group_profiles WHERE (cg_scheme_id,group_id)=(?,?)',
		[ $cs, $group ] );
	my $values = { records => int($profile_count) };
	my $page_values = $self->get_page_values($profile_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};
	my $pk_type =
	  $self->{'datastore'}->run_query( 'SELECT type FROM scheme_fields WHERE scheme_id=? AND PRIMARY_KEY', $scheme_id );
	my $order_by = $pk_type eq 'integer' ? 'CAST(profile_id AS int)' : 'profile_id';
	my $qry =
	  "SELECT profile_id FROM classification_group_profiles WHERE (cg_scheme_id,group_id)=(?,?) ORDER BY $order_by";
	$qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !param('return_all');
	my $path = $self->get_full_path("$subdir/db/$db/classification_schemes/$cs/groups/$group");
	my $paging = $self->get_paging( $path, $pages, $page, $offset );
	$values->{'paging'} = $paging if %$paging;
	my $profile_ids = $self->{'datastore'}->run_query( $qry, [ $cs, $group ], { fetch => 'col_arrayref' } );
	my @links;
	push @links, request->uri_for("$subdir/db/$db/schemes/$scheme_id/profiles/$_") foreach @$profile_ids;
	$values->{'profiles'} = \@links;
	return $values;
}

sub _get_group_isolates {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $id, $cs, $group ) = @{$params}{qw(db id cscheme_id group)};
	$self->check_isolate_database;
	my $subdir  = setting('subdir');
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
	my $qry           = "SELECT COUNT(*) FROM $view WHERE $view.id IN (SELECT s.id FROM $scheme_table s "
	  . "JOIN $cscheme_table c ON s.$pk=c.profile_id WHERE c.group_id=?) AND $view.new_version IS NULL";
	my $isolate_count = $self->{'datastore'}->run_query( $qry, $group );
	my $page_values = $self->get_page_values($isolate_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};
	$qry =
	    "SELECT $view.id FROM $view WHERE $view.id IN (SELECT s.id FROM $scheme_table s "
	  . "JOIN $cscheme_table c ON s.$pk=c.profile_id WHERE c.group_id=?) AND $view.new_version IS NULL "
	  . "ORDER BY $view.id";
	$qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !param('return_all');
	my $isolate_ids = $self->{'datastore'}->run_query( $qry, $group, { fetch => 'col_arrayref' } );
	my $isolate_uris = [];

	foreach my $isolate_id (@$isolate_ids) {
		push @$isolate_uris, request->uri_for("$subdir/db/$db/isolates/$isolate_id");
	}
	my $path   = $self->get_full_path("$subdir/db/$db/classification_schemes/$cs/groups/$group");
	my $paging = $self->get_paging( $path, $pages, $page, $offset );
	my $values = {
		records  => $isolate_count,
		isolates => $isolate_uris
	};
	$values->{'paging'} = $paging if %$paging;
	return $values;
}

sub _get_group {
	my $self   = setting('self');
	my $params = params;
	my $group  = params->{'group'};
	if ( !BIGSdb::Utils::is_int($group) ) {
		send_error( 'Group must be an integer.', 400 );
	}
	if ( ( $self->{'system'}->{'dbtype'} // q() ) eq 'isolates' ) {
		return _get_group_isolates();
	} elsif ( ( $self->{'system'}->{'dbtype'} // q() ) eq 'sequences' ) {
		return _get_group_seqdef();
	}
	send_error( 'Invalid method.', 400 );
	return;
}
1;
