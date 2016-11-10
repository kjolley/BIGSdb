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
use BIGSdb::Parser;
use BIGSdb::Login;
use BIGSdb::Constants qw(:interface);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Application_Authentication');

sub print_content {
	my ($self) = @_;
	if ( $self->{'config'}->{'site_user_dbs'} ) {
		say qq(<h1>$self->{'system'}->{'description'} site-wide settings</h1>);
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
	my $user_info = $self->{'datastore'}->get_user_info_from_username($user_name);
	if ( $self->{'curate'} ) {
		$self->_show_admin_roles;
	} else {
		$self->_show_user_roles;
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
	$buffer .= q(<h2>Registrations</h2>);
	$buffer .= q(<p>Use this page to register your account with specific databases. )
	  . q(You only need to do this if you need to submit data or access password-protected resources.<p>);
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
			-labels   => $labels
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
	}
	$buffer .= q(</div>);
	return $buffer;
}

sub _register {
	my ($self)  = @_;
	my $q       = $self->{'cgi'};
	my @configs = $q->param('auto_reg');
	return if !@configs;
	eval {
		foreach my $config (@configs)
		{
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
				undef, $id, $self->{'username'}, 'user', 'now', 'now', $id, $user_db
			);
			$db->commit;
			$self->_drop_connection($system);
		}
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
		say q(<div class="box" id="statusbad"><p>User registration failed.</p></div>);
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
		foreach my $config (@configs) {
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
		my ($desc) = $self->get_truncated_label( $config->{'description'}, 50 );
		$labels->{ $config->{'dbase_config'} } = qq($desc ($config->{'dbase_config'}));
	}
	return $labels;
}

sub _show_admin_roles {
	my ($self) = @_;
	my $buffer;
	$buffer .= $self->_import_dbase_config;
	if ($buffer) {
		say q(<div class="box" id="restricted">);
		say q(<span class="config_icon fa fa-wrench fa-3x pull-left"></span>);
		say $buffer;
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
	my $q = $self->{'cgi'};
	return q() if !$self->{'permissions'}->{'import_dbase_configs'};
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
		$buffer .= q(<p>There are no configurations available or registered. Please run the sync_user_dbase_users.pl )
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
	$buffer .= q(<tr><td style="text-align:center"><input type="button" onclick='listbox_selectall("available",true)' )
	  . q(value="All" style="margin-top:1em" class="smallbutton" />);
	$buffer .= q(<input type="button" onclick='listbox_selectall("available",false)' value="None" )
	  . q(style="margin-top:1em" class="smallbutton" /></td><td></td>);
	$buffer .= q(<td style="text-align:center"><input type="button" onclick='listbox_selectall("registered",true)' )
	  . q(value="All" style="margin-top:1em" class="smallbutton" />);
	$buffer .= q(<input type="button" onclick='listbox_selectall("registered",false)' value="None" )
	  . q(style="margin-top:1em" class="smallbutton" />);
	$buffer .= q(</td></tr>);
	$buffer .= $q->end_form;
	$buffer .= q(</div>);
	return $buffer;
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
