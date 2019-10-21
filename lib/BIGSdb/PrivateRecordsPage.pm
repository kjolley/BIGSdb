#Written by Keith Jolley
#Copyright (c) 2017-2019, University of Oxford
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
package BIGSdb::PrivateRecordsPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
use BIGSdb::Constants qw(:interface);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Private records - $desc";
}

sub print_content {
	my ($self) = @_;
	say q(<h1>Private records</h1>);
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		$self->print_bad_status( { message => q(This function is only available in isolate databases.), navbar => 1 } );
		return;
	}
	if ( !$self->{'username'} ) {
		$self->print_bad_status( { message => q(You are not logged in.), navbar => 1 } );
		return;
	}
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	if ( !$user_info ) {
		$self->print_bad_status( { message => q(You are not a recognized user.), navbar => 1 } );
		return;
	}
	if ( $user_info->{'status'} eq 'user' || !$self->can_modify_table('isolates') ) {
		$self->print_bad_status(
			{
				message => q(Your account does not have permission to upload private records.),
				navbar  => 1
			}
		);
		return;
	}
	$self->_print_limits( $user_info->{'id'} );
	$self->_print_projects( $user_info->{'id'} );
	return;
}

sub _print_limits {
	my ( $self, $user_id ) = @_;
	say q(<div class="box" id="resultspanel">);
	say q(<span class="main_icon fas fa-lock fa-3x fa-pull-left"></span>);
	say q(<h2>Limits</h2>);
	my $private       = $self->{'datastore'}->get_private_isolate_count($user_id);
	my $total_private = $self->{'datastore'}->run_query(
		'SELECT COUNT(*) FROM private_isolates pi WHERE user_id=? AND EXISTS(SELECT 1 '
		  . "FROM $self->{'system'}->{'view'} v WHERE v.id=pi.isolate_id)",
		$user_id
	);
	my $limit = $self->{'datastore'}->get_user_private_isolate_limit($user_id);
	say q(<p>Accounts have a quota for the number of private records that they can upload. )
	  . q(Uploading of private data to some registered projects may not count against your quota.<p>);
	my $available = $limit - $private;
	$available = 0 if $available < 0;
	my $list = [
		{
			title => 'Records (total)',
			data  => BIGSdb::Utils::commify($total_private),
			href  => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . q(page=query&amp;private_records_list=1&amp;include_old=on&amp;submit=1)
		},
		{
			title => 'Records (quota)',
			data  => BIGSdb::Utils::commify($private),
			href  => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . q(page=query&amp;private_records_list=2&amp;include_old=on&amp;submit=1)
		},
		{ title => 'Quota',          data => BIGSdb::Utils::commify($limit) },
		{ title => 'You can upload', data => BIGSdb::Utils::commify($available) }
	];
	say $self->get_list_block($list);

	if ($available) {
		say q(<span class="main_icon fas fa-upload fa-3x fa-pull-left"></span>);
		say q(<h2>Upload</h2>);
		my $link = $self->_get_upload_link;
		say qq(<ul style="margin-left:25px"><li><a href="$link">Upload private isolate records</a></li></ul>);
	}
	my $private_isolates = $self->{'datastore'}->get_user_private_isolate_limit($user_id);
	if ($user_id) {
		say q(<span class="main_icon fas fa-pencil-alt fa-3x fa-pull-left"></span>);
		say q(<h2>Curate</h2>);
		say qq(<ul style="margin-left:25px"><li><a href="$self->{'system'}->{'curate_script'}?db=$self->{'instance'}">)
		  . q(Update private records</a> <span class="link">Curator's interface</span></li></ul>);
	}
	say q(</div>);
	return;
}

sub _get_upload_link {
	my ($self) = @_;
	my $instance = $self->{'system'}->{'curate_config'} // $self->{'instance'};
	return "$self->{'system'}->{'curate_script'}?db=$instance&amp;page=batchAdd&amp;"
	  . 'table=isolates&amp;private=1&amp;user_header=1';
}

sub _print_projects {
	my ( $self, $user_id ) = @_;
	my $projects = $self->{'datastore'}->run_query(
		'SELECT p.id,p.short_description,p.full_description,p.no_quota FROM projects p JOIN merged_project_users m ON '
		  . 'p.id=m.project_id WHERE m.user_id=? AND m.modify ORDER BY UPPER(short_description)',
		$user_id,
		{ fetch => 'all_arrayref', slice => {} }
	);
	return if !@$projects;
	my $available = $self->{'datastore'}->get_available_quota($user_id);
	say q(<div class="box" id="resultstable">);
	say q(<span class="main_icon far fa-list-alt fa-3x fa-pull-left"></span>);
	say q(<h2>Projects</h2>);
	if ( $available > 0 ) {
		say q(<p>You can upload private data to the following projects. Anything you upload will be )
		  . q(visible to any other user of the project (indicated by the users column).);
	} else {
		say q(<p>Your available quota is zero. You can only upload private data )
		  . q(to projects that are excluded from the personal quota</p>);
	}
	say q(<div class="scrollable"><table class="resultstable"><tr><th>Project</th><th>Description</th><th>Users</th>)
	  . q(<th>Isolates</th><th>Quota free</th><th>Browse</th><th>Upload</th></tr>);
	my $td               = 1;
	my $upload_link_root = $self->_get_upload_link;
	foreach my $project (@$projects) {
		$project->{'full_description'} //= q();
		my $users = $self->{'datastore'}->run_query( 'SELECT COUNT(*) FROM merged_project_users WHERE project_id=?',
			$project->{'id'}, { cache => 'PrivateRecordsPage::project_users' } );
		my $isolates = $self->{'datastore'}->run_query(
			'SELECT COUNT(*) FROM project_members WHERE project_id=? '
			  . "AND isolate_id IN (SELECT id FROM $self->{'system'}->{'view'})",
			$project->{'id'},
			{ cache => 'PrivateRecordsPage::isolate_count' }
		);
		my $quota_free = $project->{'no_quota'} ? GOOD : q();
		say qq(<tr class="td$td"><td>$project->{'short_description'}</td><td>$project->{'full_description'}</td>)
		  . qq(<td>$users</td><td>$isolates</td><td>$quota_free</td>);
		say $isolates
		  ? qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;)
		  . qq(project_list=$project->{'id'}&amp;submit=1"><span class="fas fa-binoculars action browse">)
		  . q(</span></a></td>)
		  : q(<td></td>);
		my $can_upload = $project->{'no_quota'} || $available > 0;
		my ( $BAN, $UPLOAD ) = ( BAN, UPLOAD );
		say $can_upload
		  ? qq(<td><a href="$upload_link_root&amp;project_id=$project->{'id'}" class="action">$UPLOAD</a></td>)
		  : qq(<td>$BAN</td>);
		say q(</tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</table></div>);
	say q(</div>);
	return;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery noCache);
	return;
}

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/private_records.html";
}
1;
