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
package BIGSdb::CurateNewVersionPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::IsolateInfoPage BIGSdb::CurateAddPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant ERROR => 1;

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say "<h1>Create new isolate record version</h1>";
	my $existing_id = $q->param('id');
	if ( !BIGSdb::Utils::is_int($existing_id) ) {
		say qq(<div class="box" id="statusbad"><p>Invalid isolate id passed.</p></div>);
		return;
	} elsif ( !$self->can_modify_table('isolates') ) {
		say qq(<div class="box" id="statusbad"><p>Your user account is not allowed to create isolate records.</p></div>);
		return;
	} elsif ( !$self->isolate_exists($existing_id) ) {
		say qq(<div class="box" id="statusbad"><p>Isolate $existing_id does not exist.</p></div>);
		return;
	} elsif ( !$self->is_allowed_to_view_isolate($existing_id) ) {
		say qq(<div class="box" id="statusbad"><p>Your user account is not allowed to access this isolate record.</p></div>);
		return;
	}
	if ( $q->param('new_id') ) {
		my $ret_val = $self->_create_new_version;
		$self->_print_interface if $ret_val == ERROR;
		return;
	}
	$self->_print_interface;
	return;
}

sub _print_interface {
	my ($self)      = @_;
	my $q           = $self->{'cgi'};
	my $existing_id = $q->param('id');
	say qq(<div class="box" id="queryform"><div class="scrollable">);
	say "<p>This page allows you to create a new version of the isolate record shown below.  Provenance and publication information "
	  . "will be copied to the new record but the sequence bin and allele designations will not.  This facilitates storage of different "
	  . "versions of genome assemblies.  The old record will be hidden by default, but can still be accessed when needed, with links "
	  . "from the new record.  The update history will be reset for the new record.</p>";
	say $q->start_form;
	say qq(<fieldset style="float:left"><legend>Enter new record id</legend>);
	my $next_id = $q->param('new_id') // $self->next_id('isolates');
	say qq(<label for="new_id">id:</label>);
	say $self->textfield( name => 'new_id', id => 'new_id', value => $next_id, type => 'number', min => 1, step => 1 );
	say '</fieldset>';
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Create' } );
	say $q->hidden($_) foreach qw(db page id);
	say $q->end_form;
	say '</div></div>';
	say qq(<div class="box" id="resultspanel"><div class="scrollable">);
	my $isolate_record = BIGSdb::IsolateInfoPage->new(
		(
			system        => $self->{'system'},
			cgi           => $self->{'cgi'},
			instance      => $self->{'instance'},
			prefs         => $self->{'prefs'},
			prefstore     => $self->{'prefstore'},
			config        => $self->{'config'},
			datastore     => $self->{'datastore'},
			db            => $self->{'db'},
			xmlHandler    => $self->{'xmlHandler'},
			dataConnector => $self->{'dataConnector'},
			curate        => 1
		)
	);
	say $isolate_record->get_isolate_record($existing_id);
	say '</div></div>';
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Create new isolate record version - $desc";
}

sub _create_new_version {
	my ($self)      = @_;
	my $q           = $self->{'cgi'};
	my $existing_id = $q->param('id');
	my $new_id      = $q->param('new_id');
	if ( !BIGSdb::Utils::is_int($new_id) ) {
		say qq(<div class="box" id="statusbad"><p>Invalid new record id.</p></div>);
		return ERROR;
	}
	return;
}
1;
