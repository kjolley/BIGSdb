#Written by Keith Jolley
#Copyright (c) 2015-2020, University of Oxford
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
use JSON;
use Try::Tiny;
use List::MoreUtils qw(uniq);
use Dancer2 appname => 'BIGSdb::REST::Interface';

sub setup_routes {
	my $self = setting('self');
	foreach my $dir ( @{ setting('api_dirs') } ) {
		get "$dir/db/:db/projects"                   => sub { _get_projects() };
		get "$dir/db/:db/projects/:project"          => sub { _get_project() };
		get "$dir/db/:db/projects/:project/isolates" => sub { _get_project_isolates() };
		get "$dir/db/:db/projects/:project/dataset"  => sub { _get_project_dataset() };
	}
	return;
}

sub _get_projects {
	my $self = setting('self');
	my ($db) = params->{'db'};
	$self->check_isolate_database;
	my $subdir = setting('subdir');
	my $qry    = 'SELECT id,short_description FROM projects WHERE id IN (SELECT project_id FROM project_members WHERE '
	  . "isolate_id IN (SELECT id FROM $self->{'system'}->{'view'})) AND (NOT private";
	if ( $self->{'username'} ) {
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		my $user_id   = $user_info->{'id'};
		if ( BIGSdb::Utils::is_int($user_id) ) {
			$qry .= " OR id IN (SELECT project_id FROM merged_project_users WHERE user_id=$user_id)";
		}
	}
	$qry .= ') ORDER BY id';
	my $projects = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	my @project_list;
	foreach my $project (@$projects) {
		my $isolate_count = $self->{'datastore'}->run_query(
			'SELECT COUNT(*) FROM project_members WHERE project_id=? AND '
			  . "isolate_id IN (SELECT id FROM $self->{'system'}->{'view'} WHERE new_version IS NULL)",
			$project->{'id'}
		);
		next if !$isolate_count;
		push @project_list,
		  {
			project     => request->uri_for("$subdir/db/$db/projects/$project->{'id'}"),
			description => $project->{'short_description'},
		  };
	}
	my $values = { records => int(@project_list) };
	$values->{'projects'} = \@project_list;
	return $values;
}

sub _get_project {
	my $self = setting('self');
	my ( $db, $project_id ) = ( params->{'db'}, params->{'project'} );
	$self->check_isolate_database;
	if ( !BIGSdb::Utils::is_int($project_id) ) {
		send_error( 'Project id must be an integer.', 400 );
	}
	my $subdir = setting('subdir');
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
		id          => int($project_id),
		description => $desc,
		isolates    => request->uri_for("$subdir/db/$db/projects/$project_id/isolates"),
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
	my $subdir        = setting('subdir');
	my $isolate_count = _get_isolate_count($project_id);
	my $page_values   = $self->get_page_values($isolate_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};
	my $qry = 'SELECT isolate_id FROM project_members WHERE project_id=? AND isolate_id '
	  . "IN (SELECT id FROM $self->{'system'}->{'view'} WHERE new_version IS NULL) ORDER BY isolate_id";
	$qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !param('return_all');
	my $ids = $self->{'datastore'}->run_query( $qry, $project_id, { fetch => 'col_arrayref' } );
	my $values = { records => int($isolate_count) };

	if (@$ids) {
		my $paging = $self->get_paging( "$subdir/db/$db/projects/$project_id/isolates", $pages, $page, $offset );
		$values->{'paging'} = $paging if %$paging;
		my @links;
		push @links, request->uri_for("$subdir/db/$db/isolates/$_") foreach @$ids;
		$values->{'isolates'} = \@links;
	}
	return $values;
}

sub _get_isolate_count {
	my ($project_id)  = @_;
	my $self          = setting('self');
	my $isolate_count = $self->{'datastore'}->run_query(
		'SELECT COUNT(*) FROM project_members WHERE project_id=? AND isolate_id '
		  . "IN (SELECT id FROM $self->{'system'}->{'view'} WHERE new_version IS NULL)",
		$project_id
	);
	return $isolate_count;
}

sub _get_project_dataset {
	my $self = setting('self');
	my ( $db, $project_id, $fields, $loci, $schemes ) =
	  ( params->{'db'}, params->{'project'}, params->{'fields'}, params->{'loci'}, params->{'schemes'} );
	$self->check_isolate_database;
	if ( !BIGSdb::Utils::is_int($project_id) ) {
		send_error( 'Project id must be an integer.', 400 );
	}
	my $exists = $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM projects WHERE id=?)', $project_id );
	if ( !$exists ) {
		send_error( "Project $project_id does not exist.", 404 );
	}
	my $subdir        = setting('subdir');
	my $isolate_count = _get_isolate_count($project_id);
	my $page_values   = $self->get_page_values($isolate_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};
	my $all_normal_fields = $self->{'xmlHandler'}->get_field_list;
	my %is_normal_field   = map { $_ => 1 } @$all_normal_fields;
	my $eav_fields        = $self->{'datastore'}->get_eav_fieldnames;
	my %is_eav_field      = map { $_ => 1 } @$eav_fields;
	my $extended_fields   = $self->{'datastore'}
	  ->run_query( 'SELECT attribute FROM isolate_field_extended_attributes', undef, { fetch => 'col_arrayref' } );
	my %is_extended_field = map { $_ => 1 } @$extended_fields;
	$fields //= q();
	my @selected_fields = split /,/x, $fields;
	my %is_selected = map { $_ => 1 } @selected_fields;
	my @selected_normal_fields;
	my $selected_extended_fields = [];
	my @selected_eav_fields;

	if ($fields) {
		push @selected_normal_fields, 'id' if !$is_selected{'id'};
		foreach my $field (@selected_fields) {
			push @selected_normal_fields,    $field if $is_normal_field{$field};
			push @selected_eav_fields,       $field if $is_eav_field{$field};
			push @$selected_extended_fields, $field if $is_extended_field{$field};
		}
	} else {
		@selected_normal_fields = @$all_normal_fields;
	}
	local $" = q(,);
	my $qry =
	    "SELECT @selected_normal_fields FROM $self->{'system'}->{'view'} WHERE new_version IS NULL AND id IN "
	  . '(SELECT isolate_id FROM project_members WHERE project_id=?)';
	$qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !param('return_all');
	my $records = $self->{'datastore'}->run_query( $qry, $project_id, { fetch => 'all_arrayref', slice => {} } );
	my $values = { records => int($isolate_count) };
	$self->remove_null_values($records);
	if (@$records) {
		my $paging = $self->get_paging( "$subdir/db/$db/projects/$project_id/dataset", $pages, $page, $offset );
		$values->{'paging'} = $paging if %$paging;
		my @links;
		$values->{'dataset'} = $records;
	}
	if (@selected_eav_fields) {
		foreach my $record (@$records) {
			foreach my $field (@selected_eav_fields) {
				my $value = $self->{'datastore'}->get_eav_field_value( $record->{'id'}, $field );
				$record->{$field} = $value if defined $value;
			}
		}
	}
	if (@$selected_extended_fields) {
		_add_extended_field_values( $selected_extended_fields, \%is_selected, $records );
	}
	if ($loci) {
		my @selected_loci = split /,/x, $loci;
		_add_allele_designations( \@selected_loci, $records );
	}
	if ($schemes) {
		my @selected_schemes = split /,/x, $schemes;
		_add_scheme_fields( \@selected_schemes, $records );
	}
	return $values;
}

sub _add_extended_field_values {
	my ( $selected_extended_fields, $is_selected, $records ) = @_;
	my $self = setting('self');
	my $extended_attribute_values =
	  $self->{'datastore'}->run_query( 'SELECT attribute,field_value,value FROM isolate_value_extended_attributes',
		undef, { fetch => 'all_arrayref', slice => {} } );
	my $att_values = {};
	foreach my $a (@$extended_attribute_values) {
		$att_values->{ $a->{'attribute'} }->{ $a->{'field_value'} } = $a->{'value'};
	}
	my $atts = $self->{'datastore'}->run_query( 'SELECT isolate_field,attribute FROM isolate_field_extended_attributes',
		undef, { fetch => 'all_arrayref', slice => {}, cache => 'Projects::get_extended_attributes' } );
	my %isolate_field = map { $_->{'attribute'} => $_->{'isolate_field'} } @$atts;
	foreach my $record (@$records) {
		foreach my $field (@$selected_extended_fields) {
			my $field_value;
			if ( $is_selected->{ $isolate_field{$field} } ) {
				$field_value = $record->{ $isolate_field{$field} };
			} else {
				$field_value =
				  $self->{'datastore'}
				  ->run_query( "SELECT $isolate_field{$field} FROM $self->{'system'}->{'view'} WHERE id=?",
					$record->{'id'} );
			}
			next if !defined $field_value;
			$record->{$field} = $att_values->{$field}->{$field_value}
			  if defined $att_values->{$field}->{$field_value};
		}
	}
	return;
}

sub _add_allele_designations {
	my ( $selected_loci, $records ) = @_;
	my $self     = setting('self');
	my $set_id   = $self->get_set_id;
	my $all_loci = $self->{'datastore'}->get_loci( { do_not_order => 1, set_id => $set_id } );
	my %is_locus = map { $_ => 1 } @$all_loci;
	foreach my $record (@$records) {
		my $designations = {};
		foreach my $locus (@$selected_loci) {
			next if !$is_locus{$locus};
			my $allele_ids = $self->{'datastore'}->run_query(
				q(SELECT allele_id FROM allele_designations WHERE (isolate_id,locus)=(?,?) ORDER BY allele_id),
				[ $record->{'id'}, $locus ],
				{ fetch => 'col_arrayref' }
			);
			next if !@$allele_ids;
			if ( @$allele_ids == 1 ) {
				$designations->{$locus} = $allele_ids->[0];
			} else {
				$designations->{$locus} = $allele_ids;
			}
		}
		$record->{'allele_designations'} = $designations if keys %$designations;
	}
	return;
}

sub _add_scheme_fields {
	my ( $selected_schemes, $records ) = @_;
	my $self            = setting('self');
	my $set_id          = $self->get_set_id;
	my $scheme_list     = $self->{'datastore'}->get_scheme_list( { with_pk => 1, set_id => $set_id } );
	my %scheme_names    = map { $_->{'id'} => $_->{'name'} } @$scheme_list;
	my %is_valid_scheme = map { $_->{'id'} => 1 } @$scheme_list;
	foreach my $record (@$records) {
		my $schemes = {};
		foreach my $scheme_id (@$selected_schemes) {
			my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
			my $values        = {};
			foreach my $field (@$scheme_fields) {
				my $value = _get_scheme_field_values( $record->{'id'}, $scheme_id, $field );
				next if !defined $value || !defined $value->[0];
				$values->{$field} = @$value == 1 ? $value->[0] : $value;
			}
			if ( keys %$values ) {
				$schemes->{$scheme_id} = $values;
				$schemes->{$scheme_id}->{'name'} = $scheme_names{$scheme_id};
			}
		}
		$record->{'schemes'} = $schemes if keys %$schemes;
	}
	return;
}

sub _get_scheme_field_values {
	my ( $isolate_id, $scheme_id, $field ) = @_;
	my $self = setting('self');

	#Using $self->{'cache'} would be persistent between calls even when calling another database.
	#Datastore is destroyed after call so $self->{'datastore'}->{'scheme_cache_table'} is safe to
	#cache only for duration of call.
	if ( !$self->{'datastore'}->{'scheme_cache_table'}->{$scheme_id} ) {
		$self->{'datastore'}->{'scheme_cache_table'}->{$scheme_id} =
		  $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
	}
	my $values =
	  $self->{'datastore'}->run_query(
		"SELECT $field FROM $self->{'datastore'}->{'scheme_cache_table'}->{$scheme_id} WHERE id=? ORDER BY $field",
		$isolate_id, { fetch => 'col_arrayref', cache => "Projects::get_scheme_field_values::${scheme_id}::$field" } );
	no warnings 'uninitialized';    #Values most probably include undef
	@$values = uniq @$values;
	return $values;
}
1;
