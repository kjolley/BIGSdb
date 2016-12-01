#Written by Keith Jolley
#Copyright (c) 2016, University of Oxford
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
package BIGSdb::UserPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::VersionPage);
use Log::Log4perl qw(get_logger);
use BIGSdb::BIGSException;
use XML::Parser::PerlSAX;
use Mail::Sender;
use Email::Valid;
use BIGSdb::Parser;
use BIGSdb::Login;
use BIGSdb::Constants qw(:interface);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	if ( $self->{'config'}->{'site_user_dbs'} ) {
		say qq(<h1>$self->{'system'}->{'description'} site-wide settings</h1>);
		my $q = $self->{'cgi'};
		if ( $self->{'curate'} && $q->param('merge_user') && $q->param('user') ) {
			$self->_select_merge_users;
			return;
		}
		$self->_site_account;
		return;
	}
	say q(<h1>Bacterial Isolate Genome Sequence Database (BIGSdb)</h1>);
	$self->print_about_bigsdb;
	return;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery noCache);
	return if !$self->{'config'}->{'site_user_dbs'};
	$self->use_correct_user_database;
	return;
}

sub _site_account {
	my ($self) = @_;
	my $user_name = $self->{'username'};
	if ( !$user_name ) {
		$logger->error('User not logged in - this should not be possible.');
		$self->print_about_bigsdb;
		return;
	}
	my $q = $self->{'cgi'};
	if ( $q->param('edit') ) {
		$self->_edit_user;
		return;
	}
	$self->_show_registration_details;
	if ( $self->{'curate'} ) {
		$self->_show_admin_roles;
	} else {
		$self->_show_user_roles;
	}
	return;
}

sub _show_registration_details {
	my ($self) = @_;
	say q(<div class="box" id="resultspanel"><div class="scrollable">);
	say q(<span class="main_icon fa fa-id-card-o fa-3x pull-left"></span>);
	say q(<h2>User details</h2>);
	say q(<p>You are registered with the following details. Please ensure that these are correct and use )
	  . q(appropriate capitalization etc. These details will be linked to any data you submit to the )
	  . q(databases and will be visible to other users.</p>);
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	say q(<dl class="data">)
	  . qq(<dt>Username</dt><dd>$user_info->{'user_name'}</dd>)
	  . qq(<dt>First name</dt><dd>$user_info->{'first_name'}</dd>)
	  . qq(<dt>Last name</dt><dd>$user_info->{'surname'}</dd>)
	  . qq(<dt>E-mail address</dt><dd>$user_info->{'email'}</dd>)
	  . qq(<dt>Affiliation/institute</dt><dd>$user_info->{'affiliation'}</dd></dl>);
	my $edit  = EDIT;
	my $class = RESET_BUTTON_CLASS;
	say qq(<p><a href="$self->{'system'}->{'script_name'}?edit=1" class="$class ui-button-text-only">)
	  . qq(<span class="ui-button-text">$edit Edit details</span></a></p>);
	say q(</div></div>);
	return;
}

sub _edit_user {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('update') ) {
		$self->_update_user;
	}
	say q(<div class="box" id="queryform"><div class="scrollable">);
	say q(<span class="config_icon fa fa-edit fa-3x pull-left"></span>);
	say q(<h2>User account details</h2>);
	say q(<p>Please ensure that your details are correct - if you submit data to the database these will be )
	  . q(associated with your record. The E-mail address will be used to send you notifications about your submissions.</p>);
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	$q->param( $_ => $q->param($_) // $user_info->{$_} ) foreach qw(first_name surname email affiliation);
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Edit details</legend>);
	say q(<ul><li>);
	say q(<label for="first_name" class="form">First name:</label>);
	say $q->textfield( -name => 'first_name', -id => 'first_name', -required => 'required', size => 25 );
	say q(</li><li>);
	say q(<label for="surname" class="form">Last name/surname:</label>);
	say $q->textfield( -name => 'surname', -id => 'surname', -required => 'required', size => 25 );
	say q(</li><li>);
	say q(<label for="email" class="form">E-mail:</label>);
	say $q->textfield( -name => 'email', -id => 'email', -required => 'required', size => 30 );
	say q(</li><li>);
	say q(<label for="affiliation" class="form">Affiliation/institute:</label>);
	say $q->textarea( -name => 'affiliation', -id => 'affiliation', -required => 'required' );
	say q(</li></ul>);
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Update' } );
	$q->param( update => 1 );
	say $q->hidden($_) foreach qw(edit update);
	say $q->end_form;
	say qq(<p><a href="$self->{'system'}->{'script_name'}">Back to user page</a></p>);
	say q(</div></div>);
	return;
}

sub _update_user {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my @missing;
	foreach my $param (qw (first_name surname email affiliation)) {
		push @missing, $param if !$q->param($param) || $q->param($param) eq q();
	}
	my $address = Email::Valid->address( $q->param('email') );
	my $error;
	if (@missing) {
		local $" = q(, );
		$error = qq(Please enter the following parameters: @missing.);
	} elsif ( !$address ) {
		$error = q(Your E-mail address is not valid.);
	}
	if ($error) {
		say qq(<div class="box" id="statusbad"><p>$error</p></div>);
		return;
	}
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my ( @changed_params, @new, %old );
	foreach my $param (qw (first_name surname email affiliation)) {
		if ( $q->param($param) ne $user_info->{$param} ) {
			push @changed_params, $param;
			push @new,            $q->param($param);
			$old{$param} = $user_info->{$param};
		}
	}
	if (@changed_params) {
		local $" = q(,);
		my @placeholders = ('?') x @changed_params;
		my $qry          = "UPDATE users SET (@changed_params,datestamp)=(@placeholders,?) WHERE user_name=?";
		eval {
			$self->{'db'}->do( $qry, undef, @new, 'now', $self->{'username'} );
			foreach my $param (@changed_params) {
				$self->{'db'}->do( 'INSERT INTO history (timestamp,user_name,field,old,new) VALUES (?,?,?,?,?)',
					undef, 'now', $self->{'username'}, $param, $user_info->{$param}, $q->param($param) );
			}
			$logger->info("$self->{'username'} updated user details.");
		};
		if ($@) {
			say q(<div class="box" id="statusbad"><p>User detail update failed.</p></div>);
			$logger->error($@);
			$self->{'db'}->rollback;
		} else {
			say q(<div class="box" id="resultsheader"><p>Details successfully updated</p></div>);
			$self->{'db'}->commit;
		}
	} else {
		say q(<div class="box" id="resultsheader"><p>No changes made.</p></div>);
	}
	return;
}

sub _show_user_roles {
	my ($self) = @_;
	my $buffer;
	$buffer .= $self->_registrations;
	if ($buffer) {
		say q(<div class="box" id="queryform">);
		say $buffer;
		say q(<div style="clear:both"></div></div>);
	} else {
		$self->print_about_bigsdb;
	}
	return;
}

sub _registrations {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	$self->_register if $q->param('register');
	$self->_request  if $q->param('request');
	my $buffer = q();
	my $configs =
	  $self->{'datastore'}->run_query( 'SELECT dbase_config FROM registered_resources ORDER BY dbase_config',
		undef, { fetch => 'col_arrayref' } );
	return $buffer if !@$configs;
	$buffer .= q(<span class="main_icon fa fa-list-alt fa-3x pull-left"></span>);
	$buffer .= q(<h2>Registrations</h2>);
	$buffer .=
	    q(<p>Use this page to register your account with specific databases. )
	  . q(<strong><em>You should only do this if you want to submit data to a specific database )
	  . q(or access a password-protected resource.</em></strong></p>);
	my $registered_configs =
	  $self->{'datastore'}->run_query( 'SELECT dbase_config FROM registered_users WHERE user_name=?',
		$self->{'username'}, { fetch => 'col_arrayref' } );
	my $labels = $self->_get_config_labels;
	@$registered_configs = sort { $labels->{$a} cmp $labels->{$b} } @$registered_configs;
	$buffer .= q(<div class="scrollable">);
	$buffer .= q(<fieldset style="float:left"><legend>Registered</legend>);
	$buffer .= q(<p>Your account is registered for:</p>);

	if (@$registered_configs) {
		$buffer .= $q->scrolling_list(
			-name     => 'registered',
			-id       => 'registered',
			-values   => $registered_configs,
			-multiple => 'true',
			-disabled => 'disabled',
			-style    => 'min-width:10em; min-height:9.5em',
			-labels   => $labels,
			-size     => 9
		);
	} else {
		$buffer .= q(<p>Nothing</p>);
	}
	$buffer .= q(</fieldset>);
	my $auto_reg = $self->{'datastore'}->run_query(
		'SELECT dbase_config FROM registered_resources WHERE auto_registration AND dbase_config NOT IN '
		  . '(SELECT dbase_config FROM registered_users WHERE user_name=?)',
		$self->{'username'},
		{ fetch => 'col_arrayref' }
	);
	if (@$auto_reg) {
		@$auto_reg = sort { $labels->{$a} cmp $labels->{$b} } @$auto_reg;
		$buffer .= q(<fieldset style="float:left"><legend>Auto-registrations</legend>);
		$buffer .= q(<p>The listed resources allow you to register yourself.<br />);
		$buffer .= q(Select from list and click 'Register' button.</p>);
		$buffer .= $q->start_form;
		$buffer .= $self->popup_menu(
			-name     => 'auto_reg',
			-id       => 'auto_reg',
			-values   => $auto_reg,
			-multiple => 'true',
			-style    => 'min-width:10em; min-height:8em',
			-labels   => $labels
		);
		$buffer .= q(<div style='text-align:right'>);
		$buffer .= $q->submit( -name => 'register', -label => 'Register', -class => BUTTON_CLASS );
		$buffer .= q(</div>);
		$buffer .= $q->end_form;
		$buffer .= q(</fieldset>);
	}
	my $request_reg = $self->{'datastore'}->run_query(
		'SELECT dbase_config FROM registered_resources WHERE auto_registration IS NOT true AND dbase_config NOT IN '
		  . '(SELECT dbase_config FROM registered_users WHERE user_name=?) AND dbase_config NOT IN (SELECT '
		  . 'dbase_config FROM pending_requests WHERE user_name=?)',
		[ $self->{'username'}, $self->{'username'} ],
		{ fetch => 'col_arrayref' }
	);
	if (@$request_reg) {
		@$request_reg = sort { $labels->{$a} cmp $labels->{$b} } @$request_reg;
		$buffer .= q(<fieldset style="float:left"><legend>Admin authorization</legend>);
		$buffer .= q(<p>Access to the listed resources can be requested but require authorization.<br />);
		$buffer .= q(Select from list and click 'Request' button.</p>);
		$buffer .= $q->start_form;
		$buffer .= $self->popup_menu(
			-name     => 'request_reg',
			-id       => 'request_reg',
			-values   => $request_reg,
			-multiple => 'true',
			-style    => 'min-width:10em; min-height:8em',
			-labels   => $labels
		);
		$buffer .= q(<div style='text-align:right'>);
		$buffer .= $q->submit( -name => 'request', -label => 'Request', -class => BUTTON_CLASS );
		$buffer .= q(</div>);
		$buffer .= $q->end_form;
		$buffer .= q(</fieldset>);
	}
	my $pending = $self->{'datastore'}->run_query( 'SELECT dbase_config FROM pending_requests WHERE user_name=?',
		$self->{'username'}, { fetch => 'col_arrayref' } );
	if (@$pending) {
		@$pending = sort { $labels->{$a} cmp $labels->{$b} } @$pending;
		$buffer .= q(<fieldset style="float:left"><legend>Pending</legend>);
		$buffer .= q(<p>You have requested access to the following:<br />);
		$buffer .= q(You will be E-mailed confirmation of registration.</p>);
		$buffer .= $q->scrolling_list(
			-name     => 'pending',
			-id       => 'pending',
			-values   => $pending,
			-multiple => 'true',
			-disabled => 'disabled',
			-style    => 'min-width:10em; min-height:8em',
			-labels   => $labels
		);
		$buffer .= q(</fieldset>);
	}
	if ( !@$auto_reg && !@$request_reg && !@$pending ) {
		$buffer .= q(<fieldset style="float:left"><legend>New registrations</legend>);
		$buffer .= q(<p>There are no other resources available to register for.</p>);
		$buffer .= q(</fieldset>);
	}
	$buffer .= q(</div>);
	return $buffer;
}

sub _register {
	my ($self)  = @_;
	my $q       = $self->{'cgi'};
	my @configs = $q->param('auto_reg');
	return if !@configs;
	my $current_config;
	eval {
		foreach my $config (@configs)
		{
			$current_config = $config;
			my $auto_reg =
			  $self->{'datastore'}
			  ->run_query( 'SELECT auto_registration FROM registered_resources WHERE dbase_config=?',
				$config, { cache => 'UserPage::register::check_auto_reg' } );
			next if !$auto_reg;
			my $already_registered_in_user_db = $self->{'datastore'}->run_query(
				'SELECT EXISTS(SELECT * FROM registered_users WHERE (dbase_config,user_name)=(?,?))',
				[ $config, $self->{'username'} ],
				{ cache => 'UserPage::register::check_already_reg' }
			);

			#Prevents refreshing page trying to register twice
			next if $already_registered_in_user_db;
			my $system  = $self->_read_config_xml($config);
			my $db      = $self->_get_db($system);
			my $id      = $self->_get_next_id($db);
			my $user_db = $self->_get_user_db($db);
			next if !$user_db;
			$self->{'db'}->do( 'INSERT INTO registered_users (dbase_config,user_name,datestamp) VALUES (?,?,?)',
				undef, $config, $self->{'username'}, 'now' );
			$db->do(
				'INSERT INTO users (id,user_name,status,date_entered,datestamp,curator,user_db) VALUES (?,?,?,?,?,?,?)',
				undef, $id, $self->{'username'}, 'user', 'now', 'now', 0, $user_db
			);
			$db->commit;
			$self->_drop_connection($system);
		}
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
		my $msg = q();
		if ( $@ =~ /users_user_name_key/x ) {
			$msg = qq( A user with the same username is already registered in the $current_config database.);
			if ( $self->{'config'}->{'site_admin_email'} ) {
				$msg .= qq( Please contact the <a href="mailto:$self->{'config'}->{'site_admin_email'}">)
				  . q(site admin</a> for advice.);
			}
		}
		say qq(<div class="box" id="statusbad"><p>User registration failed.$msg</p></div>);
	} else {
		$self->{'db'}->commit;
		say q(<div class="box" id="resultsheader"><p>User registration succeeded.</p></div>);
	}
	return;
}

sub _request {
	my ($self)  = @_;
	my $q       = $self->{'cgi'};
	my @configs = $q->param('request_reg');
	return if !@configs;
	eval {
		foreach my $config (@configs)
		{
			my $already_requested = $self->{'datastore'}->run_query(
				'SELECT EXISTS(SELECT * FROM registered_users WHERE (dbase_config,user_name)=(?,?)) OR '
				  . 'EXISTS(SELECT * FROM pending_requests WHERE (dbase_config,user_name)=(?,?))',
				[ $config, $self->{'username'}, $config, $self->{'username'} ],
				{ cache => 'UserPage::register::check_already_requested' }
			);

			#Prevents refreshing page trying to register twice
			next if $already_requested;
			$self->{'db'}->do( 'INSERT INTO pending_requests (dbase_config,user_name,datestamp) VALUES (?,?,?)',
				undef, $config, $self->{'username'}, 'now' );
			$self->_notify_db_admin($config);
		}
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
		say q(<div class="box" id="statusbad"><p>User request failed.</p></div>);
	} else {
		$self->{'db'}->commit;
		say q(<div class="box" id="resultsheader"><p>User request is now pending.</p></div>);
	}
	return;
}

sub _get_config_labels {
	my ($self) = @_;
	my $configs = $self->{'datastore'}->run_query( 'SELECT dbase_config,description FROM available_resources',
		undef, { fetch => 'all_arrayref', slice => {} } );
	my $labels = {};
	foreach my $config (@$configs) {
		my ($desc) = $self->get_truncated_label( $config->{'description'}, 50, { no_html => 1 } );
		$labels->{ $config->{'dbase_config'} } = qq($desc ($config->{'dbase_config'}));
	}
	return $labels;
}

sub _show_admin_roles {
	my ($self) = @_;
	my $buffer;
	$buffer .= $self->_import_dbase_config;
	$buffer .= $self->_show_merge_user_accounts;
	if ($buffer) {
		say q(<div class="box" id="restricted">);
		say q(<span class="config_icon fa fa-wrench fa-3x pull-left"></span>);
		say $buffer;
		say q(</div>);
	} else {
		say q(<div class="box" id="statusbad" style="min-height:5em">);
		say q(<span class="config_icon fa fa-thumbs-o-down fa-5x pull-left"></span>);
		say q(<p>Your account has no administrator privileges for this site.</p>);
		say q(</div>);
	}
	return;
}

sub _is_config_registered {
	my ( $self, $config ) = @_;
	return $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM registered_resources WHERE dbase_config=?)',
		$config, { cache => 'UserPage::resource_registered' } );
}

sub _get_autoreg_status {
	my ( $self, $config ) = @_;
	return $self->{'datastore'}->run_query( 'SELECT auto_registration FROM available_resources WHERE dbase_config=?',
		$config, { cahce => 'UserPage::get_autoreg_status' } );
}

sub _import_dbase_config {
	my ($self) = @_;
	return q() if !$self->{'permissions'}->{'import_dbase_configs'};
	my $q = $self->{'cgi'};
	if ( $q->param('add') ) {
		foreach my $config ( $q->param('available') ) {
			next if $self->_is_config_registered($config);
			my $reg = $self->_get_autoreg_status($config);
			eval {
				$self->{'db'}->do( 'INSERT INTO registered_resources (dbase_config,auto_registration) VALUES (?,?)',
					undef, $config, $reg );
			};
			if ($@) {
				$logger->error($@);
				$self->{'db'}->rollback;
			} else {
				$self->{'db'}->commit;
			}
		}
	} elsif ( $q->param('remove') ) {
		foreach my $config ( $q->param('registered') ) {
			eval { $self->{'db'}->do( 'DELETE FROM registered_resources WHERE dbase_config=?', undef, $config ) };
			if ($@) {
				$logger->error($@);
				$self->{'db'}->rollback;
			} else {
				$self->{'db'}->commit;
			}
		}
	}
	my $buffer = q();
	my $registered_configs =
	  $self->{'datastore'}->run_query( 'SELECT dbase_config FROM registered_resources ORDER BY dbase_config',
		undef, { fetch => 'col_arrayref' } );
	my %registered = map { $_ => 1 } @$registered_configs;
	my $dbase_configs =
	  $self->{'datastore'}->run_query( 'SELECT dbase_config FROM available_resources ORDER BY dbase_config',
		undef, { fetch => 'col_arrayref' } );
	my $available_configs = [];
	foreach my $config (@$dbase_configs) {
		push @$available_configs, $config if !$registered{$config};
	}
	$buffer .= q(<h2>Database configurations</h2>);
	if ( !@$registered_configs && !@$available_configs ) {
		$buffer .=
		    q(<p>There are no configurations available or registered. Please run the sync_user_dbase_users.pl )
		  . q(script to populate the available configurations.</p>);
		return $buffer;
	}
	$buffer .= q(<p>Register configurations by selecting those available and moving to registered. Note that )
	  . q(user accounts are linked to specific databases rather than the configuration itself.</p>);
	$buffer .= q(<div class="scrollable">);
	$buffer .= $q->start_form;
	$buffer .= qq(<table><tr><th>Available</th><td></td><th>Registered</th></tr>\n<tr><td>);
	$buffer .= $self->popup_menu(
		-name     => 'available',
		-id       => 'available',
		-values   => $available_configs,
		-multiple => 'true',
		-style    => 'min-width:10em; min-height:15em'
	);
	$buffer .= q(</td><td>);
	my ( $add, $remove ) = ( RIGHT, LEFT );
	$buffer .= qq(<button type="submit" name="add" value="add" class="smallbutton">$add</button>);
	$buffer .= q(<br />);
	$buffer .= qq(<button type="submit" name="remove" value="remove" class="smallbutton">$remove</button>);
	$buffer .= q(</td><td>);
	$buffer .= $self->popup_menu(
		-name     => 'registered',
		-id       => 'registered',
		-values   => $registered_configs,
		-multiple => 'true',
		-style    => 'min-width:10em; min-height:15em'
	);
	$buffer .= q(</td></tr>);
	$buffer .=
	    q(<tr><td style="text-align:center"><input type="button" onclick='listbox_selectall("available",true)' )
	  . q(value="All" style="margin-top:1em" class="smallbutton" />);
	$buffer .= q(<input type="button" onclick='listbox_selectall("available",false)' value="None" )
	  . q(style="margin-top:1em" class="smallbutton" /></td><td></td>);
	$buffer .= q(<td style="text-align:center"><input type="button" onclick='listbox_selectall("registered",true)' )
	  . q(value="All" style="margin-top:1em" class="smallbutton" />);
	$buffer .= q(<input type="button" onclick='listbox_selectall("registered",false)' value="None" )
	  . q(style="margin-top:1em" class="smallbutton" />);
	$buffer .= q(</td></tr></table>);
	$buffer .= $q->end_form;
	$buffer .= q(</div>);
	return $buffer;
}

sub _show_merge_user_accounts {
	my ($self) = @_;
	return q() if !$self->{'permissions'}->{'merge_users'};
	my $users =
	  $self->{'datastore'}
	  ->run_query( 'SELECT user_name,first_name,surname FROM users ORDER BY surname, first_name, user_name',
		undef, { fetch => 'all_arrayref', slice => {} } );
	return q() if !@$users;
	my $usernames = [''];
	my $labels = { '' => 'Select user...' };
	foreach my $user (@$users) {
		push @$usernames, $user->{'user_name'};
		$labels->{ $user->{'user_name'} } = "$user->{'surname'}, $user->{'first_name'} ($user->{'user_name'})";
	}
	my $buffer = q(<h2>Merge user accounts</h2>);
	my $q      = $self->{'cgi'};
	$buffer .= $q->start_form;
	$buffer .= q(<fieldset style="float:left"><legend>Select site account</legend>);
	$buffer .= $self->popup_menu( -name => 'user', -id => 'user', -values => $usernames, -labels => $labels );
	$buffer .= q(</fieldset>);
	$buffer .= $q->hidden( merge_user => 1 );
	$buffer .= $self->print_action_fieldset( { get_only => 1, no_reset => 1, submit_label => 'Select user' } );
	$buffer .= q(<div style="clear:both"></div>);
	$buffer .= $q->end_form;
	return $buffer;
}

sub _select_merge_users {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $q->param('user') );
	if ( !$user_info ) {
		say q(<div class="box" id="statusbad"><p>No information available for user.</p></div>);
		return;
	}
	if ( !$self->{'permissions'}->{'merge_users'} ) {
		say q(<div class="box" id="statusbad"><p>Your account does not have permission to merge accounts.</p></div>);
		return;
	}
	if ( $q->param('merge') ) {
		my $account;
		if ( $q->param('dbase_config') && $q->param('username') ) {
			$account = $q->param('dbase_config') . '|' . $q->param('username');
		} else {
			$account = $q->param('accounts');
		}
		$self->_merge( $q->param('user'), $account );
	}
	say q(<div class="box" id="queryform">);
	say q(<h2>Merge user accounts</h2>);
	say
	  q(<p>Please note that merging of user accounts may fail due to a database timeout if the site user account below )
	  . q(has multiple (1000+) records already associated with it in a specific database. This is unusual as the site user )
	  . q(account is normally newly created, but can occur if you are trying to merge multiple user accounts in to one.</p>)
	  . q(<p>Databases changes will be rolled back if this occurs so the system will always be in a consistent state.</p>);
	say q(<p><strong>Site user:</strong></p>);
	say q(<dl class="data">)
	  . qq(<dt>Username</dt><dd>$user_info->{'user_name'}</dd>)
	  . qq(<dt>First name</dt><dd>$user_info->{'first_name'}</dd>)
	  . qq(<dt>Last name</dt><dd>$user_info->{'surname'}</dd>)
	  . qq(<dt>E-mail</dt><dd>$user_info->{'email'}</dd>)
	  . qq(<dt>Affiliation</dt><dd>$user_info->{'affiliation'}</dd>)
	  . q(</dl>);
	my $possible_accounts = $self->_get_possible_matching_accounts( $q->param('user') );
	say q(<div class="scrollable">);
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Possible matching accounts</legend>);

	if (@$possible_accounts) {
		my $accounts = [];
		my $labels   = {};
		foreach my $possible (@$possible_accounts) {
			push @$accounts, "$possible->{'dbase_config'}|$possible->{'user_name'}";
			$labels->{"$possible->{'dbase_config'}|$possible->{'user_name'}"} =
			    "$possible->{'dbase_config'}: $possible->{'first_name'} $possible->{'surname'} "
			  . "($possible->{'user_name'}) - $possible->{'email'} - $possible->{'affiliation'}";
		}
		say q(<p>The following accounts have been found by exact matches to first+last name or E-mail address.</p>);
		say q(<p>Select each account in turn and click 'Merge' to replace these database-specific accounts )
		  . q(with the above site account.</p>);
		say $q->scrolling_list(
			-name   => 'accounts',
			-id     => 'accounts',
			-values => $accounts,
			-labels => $labels,
			-size   => 5
		);
		say q(</fieldset>);
		$self->print_action_fieldset( { no_reset => 1, submit_label => 'Merge' } );
		$q->param( merge => 1 );
		say $q->hidden($_) foreach qw(merge merge_user user);
	} else {
		say q(<p>No matching database-specific accounts found based on )
		  . q(matching first+last name or E-mail address.</p>);
	}
	say $q->end_form;
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Enter account username to merge</legend>);
	say q(<p>If the database/user combination you want isn't listed above, you can enter it specifically below:</p>);
	my $registered_configs =
	  $self->{'datastore'}->run_query( 'SELECT dbase_config FROM registered_resources ORDER BY dbase_config',
		undef, { fetch => 'col_arrayref' } );
	unshift @$registered_configs, q();
	say q(<ul><li>);
	say q(<label for="dbase_config" class="form">Database configuration:</label>);
	say $q->popup_menu(
		-name   => 'dbase_config',
		-id     => 'dbase_config',
		values  => $registered_configs,
		-labels => { '' => 'Select database...' }
	);
	say q(</li><li>);
	say q(<label for="username" class="form">Username:</label>);
	say $q->textfield( -name => 'username', id => 'username', -default => $q->param('user') );
	say q(</li></ul>);
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Merge' } );
	$q->param( merge => 1 );
	say $q->hidden($_) foreach qw(merge merge_user user);
	say $q->end_form;
	say q(</div>);
	say qq(<p><a href="$self->{'system'}->{'script_name'}">Back</a></p>);
	say q(</div>);
	return;
}

sub _merge {
	my ( $self, $user, $account ) = @_;
	return if !$account;
	my @curator_tables = $self->{'datastore'}->get_tables_with_curator;
	my ( $config, $remote_user ) = split /\|/x, $account;
	my $system = $self->_read_config_xml($config);
	my @sender_tables =
	  $system->{'dbtype'} eq 'isolates'
	  ? qw(isolates sequence_bin allele_designations)
	  : q(sequences profiles );
	my $db = $self->_get_db($system);
	my $db_user_id =
	  $self->{'datastore'}->run_query( 'SELECT id FROM users WHERE user_name=?', $remote_user, { db => $db } );
	my $site_user_id =
	  $self->{'datastore'}->run_query( 'SELECT id FROM users WHERE user_name=?', $user, { db => $db } );

	if ( !$db_user_id ) {
		say qq(<div class="box" id="statusbad"><p>User $remote_user is not found in $config.<p></div>);
		return;
	}
	my $site_db =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id FROM user_dbases WHERE dbase_name=?', $self->{'system'}->{'db'}, { db => $db } );
	return if !$site_db;
	eval {
		if ( $db_user_id != $site_user_id )
		{
			foreach my $table (@sender_tables) {
				$db->do( "UPDATE $table SET sender=? WHERE sender=?", undef, $db_user_id, $site_user_id );
			}
			$db->do( 'UPDATE submissions SET submitter=? WHERE submitter=?', undef, $db_user_id, $site_user_id );
			$db->do( 'UPDATE messages SET user_id=? WHERE user_id=?',        undef, $db_user_id, $site_user_id );
			foreach my $table (@curator_tables) {
				$db->do( "UPDATE $table SET curator=? WHERE curator=?", undef, $db_user_id, $site_user_id );
			}

			#Don't delete user - this can take a long time as there are a lot of constraints on the users table.
			#We'll change the username instead and then reap these with an offline script.
			my $username_to_delete = $self->_get_username_to_delete($db);
			$db->do( 'UPDATE users SET (user_name,status,user_db,datestamp)=(?,?,null,?) WHERE id=?',
				undef, $username_to_delete, 'user', 'now', $site_user_id );
		}
		$self->{'auth_db'}->do( 'DELETE FROM users WHERE (dbase,name)=(?,?)', undef, $system->{'db'}, $remote_user );
		$db->do(
			'UPDATE users SET (user_name,surname,first_name,email,affiliation,user_db)='
			  . '(?,null,null,null,null,?) WHERE id=?',
			undef, $user, $site_db, $db_user_id
		);
	};
	if ($@) {
		$logger->error($@);
		$db->rollback;
		$self->{'auth_db'}->rollback;
		say q(<div class="box" id="statusbad"><p>Account failed to merge</p></div>);
	} else {
		$db->commit;
		$self->{'auth_db'}->commit;
		say q(<div class="box" id="resultsheader"><p>Account successfully merged</p></div>);
	}
	$self->_drop_connection($system);
	return;
}

sub _get_username_to_delete {
	my ( $self, $db ) = @_;
	my $i = 0;
	while (1) {
		$i++;
		my $user_name = 'REMOVED_USER_' . $i;
		my $exists =
		  $self->{'datastore'}
		  ->run_query( 'SELECT EXISTS(SELECT * FROM users WHERE user_name=?)', $user_name, { db => $db } );
		return $user_name if !$exists;
	}
	return;
}

sub _get_possible_matching_accounts {
	my ( $self, $username ) = @_;
	my $user_info = $self->{'datastore'}->get_user_info_from_username($username);
	my $configs   = $self->{'datastore'}->run_query( 'SELECT dbase_config FROM registered_users WHERE user_name=?',
		$username, { fetch => 'col_arrayref' } );
	my %db_checked;
	my $accounts = [];
	foreach my $config (@$configs) {
		my $system = $self->_read_config_xml($config);
		next if $db_checked{ $system->{'db'} };
		my $db    = $self->_get_db($system);
		my $users = $self->{'datastore'}->run_query(
			'SELECT * FROM users WHERE ((first_name,surname)=(?,?) OR email=?) AND user_db IS NULL AND id>0',
			[ $user_info->{'first_name'}, $user_info->{'surname'}, $user_info->{'email'} ],
			{ db => $db, fetch => 'all_arrayref', slice => {} }
		);
		$db_checked{ $system->{'db'} } = 1;
		foreach my $user (@$users) {
			push @$accounts,
			  {
				dbase_config => $config,
				user_name    => $user->{'user_name'},
				first_name   => $user->{'first_name'},
				surname      => $user->{'surname'},
				affiliation  => $user->{'affiliation'},
				email        => $user->{'email'},
			  };
		}
		$self->_drop_connection($system);
	}
	return $accounts;
}

sub _notify_db_admin {
	my ( $self, $config ) = @_;
	return if !$self->{'config'}->{'smtp_server'};
	my $system     = $self->_read_config_xml($config);
	my $db         = $self->_get_db($system);
	my $subject    = qq(Account registration request for $system->{'description'} database);
	my $sender     = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $recipients = $self->{'datastore'}->run_query(
		'SELECT * FROM users WHERE status=? OR id IN (SELECT user_id FROM permissions WHERE permission=?)',
		[ 'admin', 'import_site_users' ],
		{ db => $db, fetch => 'all_arrayref', slice => {} }
	);
	foreach my $recipient (@$recipients) {

		if ( $recipient->{'user_db'} ) {
			my $user_dbname =
			  $self->{'datastore'}
			  ->run_query( 'SELECT dbase_name FROM user_dbases WHERE id=?', $recipient->{'user_db'}, { db => $db } );
			if ( $user_dbname eq $self->{'system'}->{'db'} ) {
				$recipient = $self->{'datastore'}->get_user_info_from_username( $recipient->{'user_name'} );
			}
		}
	}
	if ( !@$recipients ) {
		$logger->error(
			"No admins or curators with permissions needed to import users to $system->{'description'} database.");
		return;
	}
	foreach my $user ( $sender, @$recipients ) {
		if ( $user->{'email'} !~ /@/x ) {
			$logger->error("Invalid E-mail address for user $user->{'id'}-$user->{'user_name'} - $user->{'email'}");
			return;
		}
	}
	my $message =
	    qq(The following user has requested access to the $system->{'description'} database.\n\n)
	  . qq(Username: $self->{'username'}\n)
	  . qq(First name: $sender->{'first_name'}\n)
	  . qq(Surname: $sender->{'surname'}\n)
	  . qq(Affiliation: $sender->{'affiliation'}\n\n);
	$message .= qq(This user already has a site-wide account. Please log in to the $system->{'description'} )
	  . q(database curation system to import this user (please DO NOT create a new user account).);
	foreach my $recipient (@$recipients) {
		my $args =
		  { smtp => $self->{'config'}->{'smtp_server'}, to => $recipient->{'email'}, from => $sender->{'email'} };
		my $mail_sender = Mail::Sender->new($args);
		$mail_sender->MailMsg( { subject => $subject, ctype => 'text/plain', charset => 'utf-8', msg => $message } );
		no warnings 'once';
		$logger->error($Mail::Sender::Error) if $mail_sender->{'error'};
	}
	$self->_drop_connection($system);
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $buffer = << "END";
function listbox_selectall(listID, isSelect) {
	\$("#" + listID + " option").prop("selected",isSelect);
}
END
	return $buffer;
}

sub _read_config_xml {
	my ( $self, $config ) = @_;
	if ( !$self->{'xmlHandler'} ) {
		$self->{'xmlHandler'} = BIGSdb::Parser->new;
	}
	my $parser = XML::Parser::PerlSAX->new( Handler => $self->{'xmlHandler'} );
	my $path = "$self->{'dbase_config_dir'}/$config/config.xml";
	eval { $parser->parse( Source => { SystemId => $path } ) };
	if ($@) {
		$logger->fatal("Invalid XML description: $@");
		return;
	}
	my $system = $self->{'xmlHandler'}->get_system_hash;
	return $system;
}

sub _get_db_connection_args {
	my ( $self, $system ) = @_;
	my $args = {
		dbase_name => $system->{'db'},
		host       => $system->{'host'} // $self->{'system'}->{'host'},
		port       => $system->{'port'} // $self->{'system'}->{'port'},
		user       => $system->{'user'} // $self->{'system'}->{'user'},
		password   => $system->{'password'} // $self->{'system'}->{'password'},
	};
	return $args;
}

sub _get_db {
	my ( $self, $system ) = @_;
	my $args = $self->_get_db_connection_args($system);
	my $db   = $self->{'dataConnector'}->get_connection($args);
	return $db;
}

sub _get_next_id {
	my ( $self, $db ) = @_;

	#this will find next id except when id 1 is missing
	my $next = $self->{'datastore'}->run_query(
		'SELECT l.id + 1 AS start FROM users AS l LEFT OUTER JOIN users AS r ON l.id+1=r.id '
		  . 'WHERE r.id is null AND l.id > 0 ORDER BY l.id LIMIT 1',
		undef,
		{ db => $db }
	);
	$next = 1 if !$next;
	return $next;
}

sub _get_user_db {
	my ( $self, $db ) = @_;
	return $self->{'datastore'}
	  ->run_query( 'SELECT id FROM user_dbases WHERE dbase_name=?', $self->{'system'}->{'db'}, { db => $db } );
}

sub _drop_connection {
	my ( $self, $system ) = @_;
	my $args = $self->_get_db_connection_args($system);
	$self->{'dataConnector'}->drop_connection($args);
	return;
}
1;
