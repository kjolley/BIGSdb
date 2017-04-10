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
package BIGSdb::PrivateRecordsPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Private records - $desc";
}

sub _get_private_isolate_count {
	my ( $self, $user_id ) = @_;
	return $self->{'datastore'}->run_query(
		'SELECT COUNT(*) FROM private_isolates pi WHERE user_id=? AND NOT EXISTS'
		  . '(SELECT 1 FROM project_members pm JOIN projects p ON pm.project_id=p.id WHERE '
		  . 'pm.isolate_id=pi.isolate_id AND p.no_quota)',
		$user_id
	);
}

sub print_content {
	my ($self) = @_;
	say q(<h1>Private records</h1>);
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		say q(<div class="box" id="statusbad"><p>This function is only available in isolate databases.</p></div>);
		return;
	}
	if ( !$self->{'username'} ) {
		say q(<div class="box" id="statusbad"><p>You are not logged in.</p></div>);
		return;
	}
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	if ( !$user_info ) {
		say q(<div class="box" id="statusbad"><p>You are not a recognized user.</p></div>);
		return;
	}
	say q(<div class="box" id="resultspanel">);
	say q(<span class="main_icon fa fa-lock fa-3x pull-left"></span>);
	say q(<h2>Limits</h2>);
	my $private = $self->_get_private_isolate_count( $user_info->{'id'} );
	my $limit   = $self->{'datastore'}->get_user_private_isolate_limit( $user_info->{'id'} );
	say q(<p>Accounts have a quota for the number of private records that they can upload.<p>);
	say q(<dl class="data">);
	say qq(<dt>Uploaded</dt><dd>$private</dd>);
	say qq(<dt>Quota</dt><dd>$limit</dd>);
	my $available = $limit - $private;
	$available = 0 if $available < 0;
	say qq(<dt>Available</dt><dd>$available</dd>);
	say q(</dl>);
	say q(</div>);
	return;
}
1;
