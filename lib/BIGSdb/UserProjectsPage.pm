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
package BIGSdb::UserProjectsPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateAddPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description || 'BIGSdb';
	return "User projects - $desc";
}

sub _user_projects_enabled {
	my ($self) = @_;
	if (
		(
			( ( $self->{'system'}->{'public_login'} // q() ) ne 'no' )
			|| $self->{'system'}->{'read_access'} ne 'public'
		)
		&& ( $self->{'system'}->{'user_projects'} // q() ) eq 'yes'
	  )
	{
		return 1;
	}
	return;
}

sub print_content {
	my ($self) = @_;
	say q(<h1>User projects</h1>);
	if ( !$self->_user_projects_enabled ) {
		say q(<div class="box" id="statusbad">User projects are not enabled in this database.</p></div>);
		return;
	}
	my $q = $self->{'cgi'};
	$self->_add_new_project if $q->param('new_project');
	$self->_print_user_projects;
	return;
}

sub _add_new_project {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $short_desc = $q->param('short_description');
	return if !$short_desc;
	my $desc_exists =
	  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM projects WHERE short_description=?)', $short_desc );
	if ($desc_exists) {
		say q(<div class="box" id="statusbad"><p>There is already a project defined with this name. )
		  . q(Please choose a different name.</p></div>);
		return;
	}
	my $id = $self->next_id('projects');
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	eval {
		$self->{'db'}->do(
			'INSERT INTO projects (id,short_description,full_description,isolate_display,'
			  . 'list,private,curator,datestamp) VALUES (?,?,?,?,?,?,?,?)',
			undef, $id, $short_desc, $q->param('full_description'),'false','false','true',$user_info->{'id'},'now'
		);
	};
	if ($@){
		$logger->error($@);
		say q(<div class="box" id="statusbad"><p>Could not add project at this time. Please try again later.</p></div>);
		$self->{'db'}->rollback;
	} else {
		say q(<div class="box" id="resultsheader"></p>Project successfully added.</p></div>);
		$self->{'db'}->commit;
	}
	return;
}

sub _print_user_projects {
	my ($self) = @_;
	say q(<div class="box" id="queryform">);
	say q(<h2>New private projects</h2>);
	say q(<p>Projects allow you to group isolates so that you can analyse them easily together.</p>);
	say q(<p>Please enter the details for a new project. The project name needs to be unique on the system. )
	  . q(A description is optional.</p>);
	my $q = $self->{'cgi'};
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>New project</legend>);
	say q(<ul>);
	say q(<li><label for="short_description" class="form" style="width:6em">Name:</label>);
	say $q->textfield(
		-name      => 'short_description',
		-id        => 'short_description',
		-size      => 30,
		-maxlength => 40,
		-required  => 'required'
	);
	say q(</li><li>);
	say q(<li><label for="full_description" class="form" style="width:6em">Description:</label>);
	say $q->textarea( -name => 'full_description', -id => 'full_description' );
	say q(</li></ul>);
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1 } );
	$q->param( new_project => 1 );
	say $q->hidden($_) foreach qw(db page new_project);
	say $q->end_form;
	say q(<h2>Existing projects</h2>);
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $projects  = $self->{'datastore'}->run_query( 'SELECT project_id FROM merged_project_users WHERE user_id=?',
		$user_info->{'id'}, { fetch => 'col_arrayref' } );

	if (@$projects) {
	} else {
		say q(<p>You do not own or are a member of any projects.</p>);
	}
	say q(</div>);
	return;
}
1;
