#Written by Keith Jolley
#Copyright (c) 2016-2018, University of Oxford
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
package BIGSdb::CurateImportUserPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateAddPage);
use BIGSdb::Constants qw(:interface);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Import user from remote users database</h1>);
	if ( !$self->{'datastore'}->user_dbs_defined ) {
		$self->print_bad_status( { message => q(No user databases are defined.), navbar => 1 } );
		return;
	}
	if ( !( $self->{'permissions'}->{'import_site_users'} || $self->is_admin ) ) {
		$self->print_bad_status(
			{ message => q(Your account does not have permission to import users.), navbar => 1 } );
		return;
	}
	my $default_db =
	  $self->{'datastore'}
	  ->run_query( 'SELECT * FROM user_dbases ORDER BY list_order,name LIMIT 1', undef, { fetch => 'row_hashref' } );
	if ( !$q->param('user_db') ) {
		$q->param( user_db => $default_db->{'id'} );
	}
	my $user_db = $q->param('user_db');
	if ( !BIGSdb::Utils::is_int($user_db) || !$self->{'datastore'}->user_db_defined($user_db) ) {
		$self->print_bad_status( { message => q(Invalid user database submitted.), navbar => 1 } );
		return;
	}
	if ( $q->param('submit') && $q->param('users') ) {
		$self->_import;
	}
	$self->_print_interface($user_db);
	return;
}

sub _print_interface {
	my ( $self, $user_db ) = @_;
	say $self->get_form_icon( 'users', 'import' );
	my $dbs = $self->{'datastore'}->run_query( 'SELECT * FROM user_dbases ORDER BY list_order,name',
		undef, { fetch => 'all_arrayref', slice => {} } );
	my $possible_users = $self->_get_possible_users($user_db);
	my $q              = $self->{'cgi'};
	say q(<div class="box" id="queryform"><div class="scrollable">);
	if ( @$dbs == 1 ) {
		say qq(<p>Domain/site: <strong>$dbs->[0]->{'name'}</strong></p>);
	} else {
		my $db_ids = [];
		my $labels = {};
		foreach my $db (@$dbs) {
			push @$db_ids, $db->{'id'};
			$labels->{ $db->{'id'} } = $db->{'name'};
		}
		say q(<fieldset><legend>Domain/site</legend>);
		say $q->start_form;
		say $q->popup_menu(
			-name    => 'user_db',
			-values  => $db_ids,
			-labels  => $labels,
			-default => $q->param('user_db')
		);
		say $q->submit( -name => 'select_db', -label => 'Select', class => BUTTON_CLASS );
		say $q->hidden($_) foreach qw(db page);
		say $q->end_form;
		say q(</fieldset><div style="clear:both"></div>);
	}
	my $labels     = {};
	my $user_names = [];
	foreach my $user (@$possible_users) {
		push @$user_names, $user->{'user_name'};
		my ($truncated_affiliation) = $self->get_truncated_label($user->{'affiliation'},80);
		$labels->{ $user->{'user_name'} } =
		    qq($user->{'surname'}, $user->{'first_name'} ($user->{'user_name'}) - )
		  . qq($truncated_affiliation ($user->{'email'}));
	}
	if (@$possible_users) {
		say $q->start_form;
		say q(<fieldset style="float:left"><legend>Select user(s)</legend>);
		say $self->popup_menu(
			-name     => 'users',
			-values   => $user_names,
			-labels   => $labels,
			-size     => 10,
			-multiple => 'true',
			-default  => [ $q->param('user_name') ]
		);
		say q(</fieldset>);
		$self->print_action_fieldset( { submit_label => 'Import', no_reset => 1 } );
		say $q->hidden($_) foreach qw(user_db user_name db page);
		say $q->end_form;
	} else {
		say q(<p>No more users available for import.</p>);
	}
	say q(</div></div>);
	return;
}

#Return users that do not have a corresponding username in local database
sub _get_possible_users {
	my ( $self, $user_db ) = @_;
	my $remote_db = $self->{'datastore'}->get_user_db($user_db);
	my $remote_users =
	  $self->{'datastore'}->run_query( 'SELECT * FROM users WHERE status=? ORDER BY surname,first_name',
		'validated', { fetch => 'all_arrayref', slice => {}, db => $remote_db } );
	my $local_users =
	  $self->{'datastore'}->run_query( 'SELECT * FROM users', undef, { fetch => 'all_arrayref', slice => {} } );
	my %local_usernames = map { $_->{'user_name'} => 1 } @$local_users;
	my $users = [];
	foreach my $remote_user (@$remote_users) {
		next if $local_usernames{ $remote_user->{'user_name'} };
		push @$users, $remote_user;
	}
	return $users;
}

sub _import {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $user_db   = $q->param('user_db');
	my @users     = $q->param('users');
	my $remote_db = $self->{'datastore'}->get_user_db($user_db);
	my $invalid_upload;
	my $matching_configs =
	  $self->{'datastore'}->get_configs_using_same_database( $remote_db, $self->{'system'}->{'db'} );
	eval {
		foreach my $user_name (@users) {
			$invalid_upload = 1 if !$self->_check_valid_import( $user_db, $user_name );
			my $id         = $self->next_id('users');
			my $curator_id = $self->get_curator_id;
			$self->{'db'}->do(
				'INSERT INTO users (id,user_name,status,date_entered,datestamp,curator,submission_emails,'
				  . 'account_request_emails,user_db) VALUES (?,?,?,?,?,?,?,?,?)',
				undef, $id, $user_name, 'user', 'now', 'now', $curator_id,, 'false', 'false', $user_db
			);

			#We need to identify all registered configs that use the same database
			foreach my $config (@$matching_configs) {
				$remote_db->do( 'INSERT INTO registered_users (dbase_config,user_name,datestamp) VALUES (?,?,?)',
					undef, $config, $user_name, 'now' );
				$remote_db->do( 'DELETE FROM pending_requests WHERE (dbase_config,user_name)=(?,?)',
					undef, $config, $user_name );
			}
		}
	};
	if ($invalid_upload) {
		$self->{'db'}->rollback;
		$remote_db->rollback;
		return;
	}
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
		$remote_db->rollback;
		$self->print_bad_status( { message => q(User upload failed.), navbar => 1 } );
	} else {
		$self->{'db'}->commit;
		$remote_db->commit;
		local $" = q(, );
		my $plural = @users == 1 ? q() : q(s);
		$self->print_good_status( { message => qq(User$plural @users successfully imported.), navbar => 1 } );
		my $user_db_object = $self->{'datastore'}->get_user_db($user_db);
	}
	return;
}

sub _check_valid_import {
	my ( $self, $user_db, $user_name ) = @_;
	my $exists_in_local = $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM users WHERE user_name=?)',
		$user_name, { cache => 'CurateImportUserPage::check_valid_import::local' } );
	if ($exists_in_local) {
		$logger->error("User '$user_name' already exists in the local database.");
		$self->print_bad_status(
			{ message => qq(User '$user_name' already exists in the local database.), navbar => 1 } );
		return;
	}
	my $remote_db        = $self->{'datastore'}->get_user_db($user_db);
	my $exists_in_remote = $self->{'datastore'}->run_query(
		'SELECT EXISTS(SELECT * FROM users WHERE (user_name,status)=(?,?))',
		[ $user_name, 'validated' ],
		{ cache => 'CurateImportUserPage::check_valid_import::remote', db => $remote_db }
	);
	if ( !$exists_in_remote ) {
		$logger->error("User '$user_name' does not exist in the remote user database.");
		$self->print_bad_status(
			{
				message => qq(User '$user_name' does not exist in the remote user database.),
				navbar  => 1
			}
		);
		return;
	}
	return 1;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Import user - $desc";
}
1;
