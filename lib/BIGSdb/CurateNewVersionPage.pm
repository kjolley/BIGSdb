#Written by Keith Jolley
#Copyright (c) 2014-2017, University of Oxford
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
use BIGSdb::Utils;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant ERROR => 1;

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery noCache);
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Create new isolate record version</h1>);
	my $existing_id = $q->param('id');
	if ( $self->{'system'}->{'view'} ne 'isolates' && $self->{'system'}->{'view'} ne 'temp_view' ) {
		say q(<div class="box" id="statusbad"><p>New record versions cannot be created when a filtered )
		  . q(isolate view is used.  Any new version could be potentially inaccessible.</p></div>);
		return;
	}
	if ( !BIGSdb::Utils::is_int($existing_id) ) {
		say q(<div class="box" id="statusbad"><p>Invalid isolate id passed.</p></div>);
		return;
	}
	if ( !$self->can_modify_table('isolates') ) {
		say q(<div class="box" id="statusbad"><p>Your user account is not allowed to )
		  . q(create isolate records.</p></div>);
		return;
	}
	if ( !$self->isolate_exists($existing_id) ) {
		say qq(<div class="box" id="statusbad"><p>Isolate $existing_id does not exist.</p></div>);
		return;
	}
	if ( !$self->is_allowed_to_view_isolate($existing_id) ) {
		say q(<div class="box" id="statusbad"><p>Your user account is not allowed to access )
		  . q(this isolate record.</p></div>);
		return;
	}
	my $new_version = $self->{'datastore'}->run_query( 'SELECT new_version FROM isolates WHERE id=?', $existing_id );
	if ($new_version) {
		if ( $self->isolate_exists($new_version) ) {
			say q(<div class="box" id="statusbad"><p>This isolate already has a newer version defined. See )
			  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=info&amp;)
			  . qq(id=$new_version">isolate id-$new_version</a>.</p></div>);
		} else {
			say q(<div class="box" id="statusbad"><p>This isolate already has a newer version defined. )
			  . q(It is not, however, accessible from the current database view.</p></div>);
		}
		return;
	}
	$self->{'isolate_record'} = BIGSdb::IsolateInfoPage->new(
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
	my $new_id = $q->param('new_id');
	if ($new_id) {
		my $ret_val = $self->_create_new_version;
		if ($ret_val) {
			$self->_print_interface;
			return;
		}
		say q(<div class="box" id="resultsheader"><p>The new record shown below has been created.</p>);
		say qq(<ul><li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=batchAddSeqbin&amp;isolate_id=$new_id">Upload contigs</a></li>);
		say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=isolateUpdate&amp;id=$new_id">Update record</a></li></ul></div>);
		say q(<div class="box" id="resultspanel"><div class="scrollable">);
		say $self->{'isolate_record'}->get_isolate_record($new_id);
		say q(</div></div>);
		return;
	}
	$self->_print_interface;
	return;
}

sub _print_interface {
	my ($self)      = @_;
	my $q           = $self->{'cgi'};
	my $existing_id = $q->param('id');
	say q(<div class="box" id="queryform"><div class="scrollable">);
	say q(<p>This page allows you to create a new version of the isolate record shown below.  )
	  . q(Provenance and publication information will be copied to the new record but the sequence )
	  . q(bin and allele designations will not.  This facilitates storage of different versions of )
	  . q(genome assemblies.  The old record will be hidden by default, but can still be accessed )
	  . q(when needed, with links from the new record.  The update history will be reset for the new record.</p>);
	if ( BIGSdb::Utils::is_int($existing_id) && $self->_is_private($existing_id) ) {
		say q(<p>As this record is private, the new version will also be private with you set as the owner. If )
		  . q(the original record forms part of a private quota, the new record will also take up quota space.</p>)
		  ;
	}
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Enter new record id</legend>);
	my $next_id = $q->param('new_id') // $self->next_id('isolates');
	say q(<label for="new_id">id:</label>);
	say $self->textfield( name => 'new_id', id => 'new_id', value => $next_id, type => 'number', min => 1, step => 1 );
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Options</legend);
	say $q->checkbox( -name => 'copy_projects', -label => 'Add new version to projects', -checked => 'checked' );
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Create' } );
	say $q->hidden($_) foreach qw(db page id);
	say $q->end_form;
	say q(</div></div>);
	say q(<div class="box" id="resultspanel"><div class="scrollable">);
	say $self->{'isolate_record'}->get_isolate_record($existing_id);
	say q(</div></div>);
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
		say q(<div class="box" id="statusbad"><p>Invalid new record id.</p></div>);
		return ERROR;
	}

	#Don't use Page::isolate_exists as that only checks current view, but we need to check whole isolates table.
	my $exists = $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM isolates WHERE id=?)', $new_id );
	if ($exists) {
		say qq(<div class="box" id="statusbad"><p>An isolate record already exists with id-$new_id.</p></div>);
		return ERROR;
	}
	my $is_private   = $self->_is_private($existing_id);
	my $fields       = $self->{'xmlHandler'}->get_field_list;
	my $field_values = $self->{'datastore'}->get_isolate_field_values($existing_id);
	my (@values);
	my $curator_id = $self->get_curator_id;
	foreach my $field (@$fields) {
		$field_values->{$field} = $new_id if $field eq 'id';
		$field_values->{$field} = BIGSdb::Utils::get_datestamp() if $field eq 'date_entered' || $field eq 'datestamp';
		$field_values->{$field} = $curator_id if $field eq 'curator';
		push @values, $field_values->{ lc($field) };
	}
	my @placeholders = ('?') x @values;
	local $" = ',';
	my $insert   = "INSERT INTO isolates (@$fields) VALUES (@placeholders)";
	my $aliases  = $self->{'datastore'}->get_isolate_aliases($existing_id);
	my $refs     = $self->{'datastore'}->get_isolate_refs($existing_id);
	my $projects = $self->{'datastore'}->run_query( 'SELECT project_id FROM project_members WHERE isolate_id=?',
		$existing_id, { fetch => 'col_arrayref' } );
	eval {
		$self->{'db'}->do( $insert, undef, @values );
		$self->{'db'}->do( 'INSERT INTO isolate_aliases (isolate_id,alias,curator,datestamp) VALUES (?,?,?,?)',
			undef, $new_id, $_, $curator_id, 'now' )
		  foreach @$aliases;
		if ( $q->param('copy_projects') ) {
			$self->{'db'}->do( 'INSERT INTO project_members (project_id,isolate_id,curator,datestamp) VALUES (?,?,?,?)',
				undef, $_, $new_id, $curator_id, 'now' )
			  foreach @$projects;
		}
		$self->{'db'}->do( 'INSERT INTO refs (isolate_id,pubmed_id,curator,datestamp) VALUES (?,?,?,?)',
			undef, $new_id, $_, $curator_id, 'now' )
		  foreach @$refs;
		$self->{'db'}->do( 'UPDATE isolates SET new_version=? WHERE id=?', undef, $new_id, $existing_id );
		if ($is_private) {
			$self->{'db'}->do( 'INSERT INTO private_isolates (isolate_id,user_id,datestamp) VALUES (?,?,?)',
				undef, $new_id, $curator_id, 'now' );
		}
	};
	if ($@) {
		say q(<div class="box" id="statusbad"><p>New record creation failed.  )
		  . q(More details will be in the error log.</p></div>);
		$logger->error($@);
		$self->{'db'}->rollback;
		return ERROR;
	} else {
		$self->update_history( $new_id, "Isolate record copied from id-$existing_id." );
		$self->{'db'}->commit;
	}
	return;
}

sub _is_private {
	my ( $self, $isolate_id ) = @_;
	return $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM private_isolates WHERE isolate_id=?)', $isolate_id );
}
1;
