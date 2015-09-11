#Written by Keith Jolley
#Copyright (c) 2015, University of Oxford
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
package BIGSdb::REST::Routes::Projects;
use strict;
use warnings;
use 5.010;
use POSIX qw(ceil);
use JSON;
use Dancer2 appname => 'BIGSdb::REST::Interface';
any [qw(get post)] => '/db/:db/projects'                   => sub { _get_projects() };
any [qw(get post)] => '/db/:db/projects/:project'          => sub { _get_project() };
any [qw(get post)] => '/db/:db/projects/:project/isolates' => sub { _get_project_isolates() };

sub _get_projects {
	my $self = setting('self');
	my ($db) = params->{'db'};
	$self->check_isolate_database;
	my $projects = $self->{'datastore'}->run_query( 'SELECT id,short_description FROM projects ORDER BY id',
		undef, { fetch => 'all_arrayref', slice => {} } );
	if ( !@$projects ) {
		send_error( 'No projects exist.', 404 );
	}
	my @project_list;
	foreach my $project (@$projects) {
		my $isolate_count = $self->{'datastore'}->run_query(
			'SELECT COUNT(*) FROM project_members WHERE project_id=? AND '
			  . "isolate_id IN (SELECT id FROM $self->{'system'}->{'view'} WHERE new_version IS NULL)",
			$project->{'id'}
		);
		push @project_list,
		  {
			project       => request->uri_for("/db/$db/projects/$project->{'id'}"),
			description   => $project->{'short_description'},
			isolate_count => int($isolate_count)
		  };
	}
	return \@project_list;
}

sub _get_project {
	my $self = setting('self');
	my ( $db, $project_id ) = ( params->{'db'}, params->{'project'} );
	$self->check_isolate_database;
	if ( !BIGSdb::Utils::is_int($project_id) ) {
		send_error( 'Project id must be an integer.', 400 );
	}
	my $desc = $self->{'datastore'}->run_query( 'SELECT short_description FROM projects WHERE id=?', $project_id );
	if ( !$desc ) {
		send_error( "Project $project_id does not exist.", 404 );
	}
	my $isolate_count = $self->{'datastore'}->run_query(
		'SELECT COUNT(*) FROM project_members WHERE project_id=? AND '
		  . "isolate_id IN (SELECT id FROM $self->{'system'}->{'view'} WHERE new_version IS NULL)",
		$project_id
	);
	return {
		id            => int($project_id),
		description   => $desc,
		isolate_count => int($isolate_count),
		isolates      => request->uri_for("/db/$db/projects/$project_id/isolates"),
	};
}

sub _get_project_isolates {
	my $self = setting('self');
	my ( $db, $project_id ) = ( params->{'db'}, params->{'project'} );
	$self->check_isolate_database;
	if ( !BIGSdb::Utils::is_int($project_id) ) {
		send_error( 'Project id must be an integer.', 400 );
	}
	my $exists = $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM projects WHERE id=?)', $project_id );
	if ( !$exists ) {
		send_error( "Project $project_id does not exist.", 404 );
	}
	my $page = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $isolate_count = $self->{'datastore'}->run_query(
		'SELECT COUNT(*) FROM project_members WHERE project_id=? AND isolate_id '
		  . "IN (SELECT id FROM $self->{'system'}->{'view'} WHERE new_version IS NULL)",
		$project_id
	);
	my $pages  = ceil( $isolate_count / $self->{'page_size'} );
	my $offset = ( $page - 1 ) * $self->{'page_size'};
	my $qry    = 'SELECT isolate_id FROM project_members WHERE project_id=? AND isolate_id '
	  . "IN (SELECT id FROM $self->{'system'}->{'view'} WHERE new_version IS NULL) ORDER BY isolate_id";
	$qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !param('return_all');
	my $ids = $self->{'datastore'}->run_query( $qry, $project_id, { fetch => 'col_arrayref' } );
	my $values = {};

	if (@$ids) {
		my $paging = $self->get_paging( "/db/$db/projects/$project_id/isolates", $pages, $page );
		$values->{'paging'} = $paging if %$paging;
		my @links;
		push @links, request->uri_for("/db/$db/isolates/$_") foreach @$ids;
		$values->{'isolates'} = \@links;
	}
	return $values;
}
1;
