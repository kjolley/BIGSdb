#Written by Keith Jolley
#Copyright (c) 2010-2022, University of Oxford
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
package BIGSdb::ProjectPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::DashboardPage);
use BIGSdb::Constants qw(:interface :design :login_requirements);
use BIGSdb::Utils;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub get_title {
	my ( $self, $options ) = @_;
	my $project = $self->_get_project_name // 'Invalid project';
	return $project if $options->{'breadcrumb'};
	my $desc = $self->get_db_description || 'BIGSdb';
	return "$project - $desc";
}

sub initiate {
	my ($self) = @_;
	$self->SUPER::initiate;
	my $q          = $self->{'cgi'};
	my $project_id = $q->param('project_id');
	if ( BIGSdb::Utils::is_int($project_id) ) {
		my $prefix   = BIGSdb::Utils::get_random();
		my $qry_file = "$self->{'config'}->{'secure_tmp_dir'}/$prefix";
		my $qry      = "SELECT * FROM $self->{'system'}->{'view'} v WHERE id IN "
		  . "(SELECT isolate_id FROM project_members WHERE project_id=$project_id)";
		open( my $fh, '>', $qry_file ) || $logger->error("Cannot open $qry_file for writing.");
		say $fh $qry;
		close $fh;
		$self->{'qry_file'} = $prefix;
		$self->{'project_id'} = $project_id;
	}
	$self->{'dashboard_type'} = 'project';
	return;
}

sub process_breadcrumbs {
	my ($self) = @_;
	$self->set_level1_breadcrumbs;
	return;
}

sub print_content {
	my ($self) = @_;
	my $project_name = $self->_get_project_name;
	if ( !defined $project_name ) {
		say q(<h1>Invalid project</h1>);
		$self->print_bad_status( { message => 'An invalid project has been passed.' } );
		return;
	}
	my $q          = $self->{'cgi'};
	my $project_id = $q->param('project_id');
	if ( $self->_is_project_private($project_id) && !$self->_can_user_access_project($project_id) ) {
		say q(<h1>Cannot access project</h1>);
		$self->print_bad_status( { message => 'You are not a registered user of the selected project.' } );
		return;
	}
	$self->SUPER::print_content;
	return;
}

sub _is_project_private {
	my ( $self, $project_id ) = @_;
	return $self->{'datastore'}
	  ->run_query( 'SELECT private FROM projects WHERE id=?', $project_id, { fetch => 'row_hashref' } );
}

sub _can_user_access_project {
	my ( $self, $project_id ) = @_;
	my $private = $self->{'datastore'}->run_query( 'SELECT private FROM projects WHERE id=?', $project_id );
	if ($private) {
		if ( $self->{'username'} ) {
			my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
			return $self->{'datastore'}
			  ->run_query( 'SELECT EXISTS(SELECT * FROM project_users WHERE (project_id,user_id)=(?,?))',
				[ $project_id, $user_info->{'id'} ] );
		}
		return 0;
	}
	return defined $private ? 1 : 0;
}

sub _get_project_name {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $project_id = $q->param('project_id');
	if ( BIGSdb::Utils::is_int($project_id) ) {
		my $name = $self->{'datastore'}->run_query( 'SELECT short_description FROM projects WHERE id=?', $project_id );
		if ($name) {
			return $name;
		}
	}
	return;
}

sub get_heading {
	my ($self) = @_;
	my $project = $self->_get_project_name;
	return defined $project ? "Project: $project" : 'Invalid project';
}

sub print_panel_buttons {
	my ($self) = @_;
	$self->_print_modify_dashboard_trigger;
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $project_id = $q->param('project_id');
	my $buffer = $self->SUPER::get_javascript;
	$buffer .= qq(qryFile="$self->{'qry_file'}";\n);
	$buffer .= qq(dashboard_type='project';\n);
	$buffer.=qq(var project_id=$project_id;\n) if BIGSdb::Utils::is_int($project_id);
	return $buffer;
}
1;
