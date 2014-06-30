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
	} else {
		my $new_version = $self->{'datastore'}->run_query( "SELECT new_version FROM isolates WHERE id=?", $existing_id );
		if ($new_version) {
			if ( $self->isolate_exists($new_version) ) {
				say qq(<div class="box" id="statusbad"><p>This isolate already has a newer version defined. See )
				  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=info&amp;id=$new_version">)
				  . qq(isolate id-$new_version</a>.</p></div>);
			} else {
				say qq(<div class="box" id="statusbad"><p>This isolate already has a newer version defined. It is not, however, )
				  . qq(accessible from the current database view.</p></div>);
			}
			return;
		}
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
		say qq(<div class="box" id="resultsheader"><p>The new record shown below has been created.</p>);
		say qq(<ul><li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSeqbin&amp;isolate_id=$new_id">)
		  . qq(Upload contigs</a></li></ul></div>);
		say qq(<div class="box" id="resultspanel"><div class="scrollable">);
		say $self->{'isolate_record'}->get_isolate_record($new_id);
		say '</div></div>';
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
	say qq(<fieldset style="float:left"><legend>Options</legend);
	say $q->checkbox( -name => 'copy_projects', -label => 'Add new version to projects', -checked => 'checked' );
	say '</fieldset>';
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Create' } );
	say $q->hidden($_) foreach qw(db page id);
	say $q->end_form;
	say '</div></div>';
	say qq(<div class="box" id="resultspanel"><div class="scrollable">);
	say $self->{'isolate_record'}->get_isolate_record($existing_id);
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

	#Don't use Page::isolate_exists as that only checks current view, but we need to check whole isolates table.
	my $exists = $self->{'datastore'}->run_query( "SELECT EXISTS(SELECT * FROM isolates WHERE id=?)", $new_id );
	if ($exists) {
		say qq(<div class="box" id="statusbad"><p>An isolate record already exists with id-$new_id.</p></div>);
		return ERROR;
	}
	my $fields       = $self->{'xmlHandler'}->get_field_list;
	my $field_values = $self->{'datastore'}->get_isolate_field_values($existing_id);
	my (@values);
	my $curator_id = $self->get_curator_id;
	foreach my $field (@$fields) {
		$field_values->{$field} = $new_id if $field eq 'id';
		$field_values->{$field} = $self->get_datestamp if $field eq 'date_entered' || $field eq 'datestamp';
		$field_values->{$field} = $curator_id if $field eq 'curator';
		push @values, $field_values->{ lc($field) };
	}
	my @placeholders = ('?') x @values;
	local $" = ',';
	my $insert  = "INSERT INTO isolates (@$fields) VALUES (@placeholders)";
	my $aliases = $self->{'datastore'}->get_isolate_aliases($existing_id);
	my $refs    = $self->{'datastore'}->get_isolate_refs($existing_id);
	my $projects =
	  $self->{'datastore'}
	  ->run_query( "SELECT project_id FROM project_members WHERE isolate_id=?", $existing_id, { fetch => 'col_arrayref' } );
	eval {
		$self->{'db'}->do( $insert, undef, @values );
		$self->{'db'}->do( "INSERT INTO isolate_aliases (isolate_id,alias,curator,datestamp) VALUES (?,?,?,?)",
			undef, $new_id, $_, $curator_id, 'now' )
		  foreach @$aliases;
		if ( $q->param('copy_projects') ) {
			$self->{'db'}->do( "INSERT INTO project_members (project_id,isolate_id,curator,datestamp) VALUES (?,?,?,?)",
				undef, $_, $new_id, $curator_id, 'now' ) foreach @$projects;
		}
		$self->{'db'}
		  ->do( "INSERT INTO refs (isolate_id,pubmed_id,curator,datestamp) VALUES (?,?,?,?)", undef, $new_id, $_, $curator_id, 'now' )
		  foreach @$refs;
		$self->{'db'}->do( "UPDATE isolates SET new_version=? WHERE id=?", undef, $new_id, $existing_id );
	};
	if ($@) {
		say qq(<div class="box" id="statusbad"><p>New record creation failed.  More details will be in the error log.</p></div>);
		$logger->error($@);
		$self->{'db'}->rollback;
		return ERROR;
	} else {
		$self->update_history( $new_id, "Isolate record copied from id-$existing_id." );
		$self->{'db'}->commit;
	}
	return;
}
1;
