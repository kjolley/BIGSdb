#Written by Keith Jolley
#Copyright (c) 2016-2024, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
use XML::Parser::PerlSAX;
use Email::Sender::Transport::SMTP;
use Email::Sender::Simple qw(try_to_sendmail);
use Email::MIME;
use Email::Valid;
use Time::Piece;
use Time::Seconds;
use BIGSdb::Parser;
use BIGSdb::Login;
use BIGSdb::Utils;
use BIGSdb::Constants qw(:interface DEFAULT_DOMAIN);
use constant SUBMISSION_INTERVAL => {
	60   => '1 hour',
	120  => '2 hours',
	180  => '3 hours',
	360  => '6 hours',
	720  => '12 hours',
	1440 => '24 hours',
};
my $logger = get_logger('BIGSdb.User');

sub _ajax {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('ajax') eq 'merge_users' ) {
		say $self->_show_merge_user_accounts;
	} elsif ( $q->param('ajax') eq 'modify_users' ) {
		say $self->_show_modify_users;
	}
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('ajax') ) {
		$self->_ajax;
		return;
	}
	if ( $self->{'config'}->{'site_user_dbs'} ) {
		say qq(<h1>$self->{'system'}->{'description'} site-wide settings</h1>);
		if ( $self->{'config'}->{'disable_updates'} ) {
			$self->print_bad_status(
				{
					message => q(The registration pages are currently disabled.),
					detail  => $self->{'config'}->{'disable_update_message'}
				}
			);
			return;
		}
		if ( $self->{'curate'} && $q->param('user') ) {
			if ( $q->param('merge_user') ) {
				$self->_select_merge_users;
				return;
			} elsif ( $q->param('update_user') ) {
				$self->_edit_user( scalar $q->param('user') );
				return;
			}
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
	$self->{$_} = 1 foreach qw(jQuery noCache jQuery.multiselect);
	my $q = $self->{'cgi'};
	if ( $q->param('ajax') ) {
		$self->{'type'} = 'no_header';
	}
	return if !$self->{'config'}->{'site_user_dbs'};
	$self->use_correct_user_database;
	$self->{'breadcrumbs'} = [
		{
			label => 'Home',
			href  => '/'
		}
	];
	if ( $q->param('user') || $q->param('update_user') || $q->param('edit') ) {
		push @{ $self->{'breadcrumbs'} },
		  {
			label => 'Account',
			href  => $self->{'system'}->{'script_name'}
		  };
	} else {
		push @{ $self->{'breadcrumbs'} }, { label => 'Account' };
	}
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
		$self->_edit_user($user_name);
		return;
	}
	say q(<div class="box queryform"><div id="accordion">);
	$self->{'panel'} = 0;
	$self->_show_registration_details;
	$self->_show_submission_options;
	if ( $self->{'curate'} ) {
		$self->_show_admin_roles;
	} else {
		$self->_show_user_roles;
	}
	say q(</div></div>);
	return;
}

sub _show_registration_details {
	my ($self) = @_;
	say q(<h2>User details</h2>);
	say q(<div><div class="scrollable">);
	say q(<span class="main_icon fas fa-address-card fa-3x fa-pull-left"></span>);
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
	say qq(<div class="registration_buttons"><a href="$self->{'system'}->{'script_name'}?edit=1" class="small_submit">)
	  . q(<span><span class="fas fa-pencil-alt"></span> Edit details</span></a>)
	  . qq(<a class="small_reset" style="margin-left:1em" href="$self->{'system'}->{'script_name'}?page=logout"><span>)
	  . q(<span class="fas fa-sign-out-alt"></span> Log out</span></a></div>);
	say q(</div></div>);
	return;
}

sub _show_submission_options {
	my ($self) = @_;
	return if !$self->_is_curator( $self->{'username'} );
	$self->{'panel'}++;
	my $q = $self->{'cgi'};
	my $prefs =
	  $self->{'datastore'}
	  ->run_query( 'SELECT * FROM curator_prefs WHERE user_name=?', $self->{'username'}, { fetch => 'row_hashref' } );
	say q(<h2>Submission notifications</h2>);
	say q(<div><div class="scrollable">);
	$self->_update_submission_options;

	if ( $q->param('submission_options') ) {
		say qq(<script>var active_panel=$self->{'panel'};</script>);
	}
	say q(<span class="main_icon fas fa-envelope fa-3x fa-pull-left"></span>);
	say q(<p>You are a curator for at least one of the databases on the system. If you receive automated submission )
	  . q(messages, you may wish to modify how you receive these or mark yourself absent for a period of time so that )
	  . q(messages are suspended.</p>);
	say $q->start_form;
	say q(<div>);
	if ( $self->{'config'}->{'submission_digests'} ) {
		say q(<h3>How do you wish to receive notifications?</h3>);
		my $submission_digest = $q->param('submission_digest');
		say $q->radio_group(
			-name   => 'submission_digest',
			-id     => 'submission_digest',
			-values => [ 0, 1 ],
			-labels => {
				0 => 'immediate notification of every submission',
				1 => 'periodic digest summarising submissions since last digest'
			},
			-default   => $submission_digest // $prefs->{'submission_digests'},
			-linebreak => 'true'
		);
		say q(<p style="margin-top:1em">Minimum digest interval: );
		my $intervals = SUBMISSION_INTERVAL;
		my $digest_interval = $q->param('digest_interval');
		say $self->popup_menu(
			-id       => 'digest_interval',
			-name     => 'digest_interval',
			-values   => [ sort { $a <=> $b } keys %$intervals ],
			-labels   => $intervals,
			-default  => $digest_interval // $prefs->{'digest_interval'} // 1440,
			-disabled => $prefs->{'submission_digests'} ? 'false' : 'true'
		);
		say q(</p>);
	}
	say q(<h3>Submission responses</h3>);
	my $response_cc = $q->param('response_cc');
	say $q->checkbox(
		-name    => 'response_cc',
		-label   => 'Receive copy of E-mail to submitter when closing submission',
		-checked => $response_cc // $prefs->{'submission_email_cc'}
	);
	say q(<h3>Suspend notifications</h3>);
	say q(<p>If you are going to be away and unable to process submissions, you can suspend notifications for )
	  . q(a specified period of time of up to 3 months. Set a date below to suspend - clear field to resume )
	  . q(notifications.</p>);
	my $datestamp = BIGSdb::Utils::get_datestamp;
	say q(<p>Resume on: );
	my $max_date = $self->_max_suspend_date;
	my $absent_until = $q->param('absent_until');
	say $self->textfield(
		name  => 'absent_until',
		type  => 'date',
		min   => $datestamp,
		max   => $max_date,
		value => $absent_until // $prefs->{'absent_until'}
	);
	say q(</p>);
	say q(</div>);
	say $q->submit(
		-name  => 'submission_options',
		-label => 'Update',
		-class => 'small_submit',
		-style => 'margin-top:1em'
	);
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub _max_suspend_date {
	my $max_date = localtime() + 3 * ONE_MONTH;
	return $max_date->ymd;
}

sub _update_submission_options {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	return if !$q->param('submission_options');
	my $max_suspend_date = $self->_max_suspend_date;
	if ( $q->param('absent_until') && $q->param('absent_until') gt $max_suspend_date ) {
		$q->param( absent_until => $max_suspend_date );
	}
	eval {
		$self->{'db'}->do(
			q[INSERT INTO curator_prefs (user_name,submission_digests,digest_interval,submission_email_cc,]
			  . q[absent_until) VALUES (?,?,?,?,?) ON CONFLICT(user_name) DO UPDATE SET (submission_digests,]
			  . q[digest_interval,submission_email_cc,absent_until)=(EXCLUDED.submission_digests,]
			  . q[EXCLUDED.digest_interval,EXCLUDED.submission_email_cc,EXCLUDED.absent_until)],
			undef,
			scalar $self->{'username'},
			scalar $q->param('submission_digest') ? 1 : 0,
			scalar $q->param('digest_interval') // 1440,
			scalar $q->param('response_cc') ? 1 : 0,
			scalar $q->param('absent_until') || undef
		);
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		print q(<div class="box statusgood_no_resize"><span class="statusgood">)
		  . q(Notification options updated.</span></div>);
	}
	return;
}

sub _edit_user {
	my ( $self, $username ) = @_;
	my $q = $self->{'cgi'};
	if ( !$self->{'permissions'}->{'modify_users'} && $username ne $self->{'username'} ) {
		$self->print_bad_status( { message => q(You do not have permission to edit other users' accounts.) } );
		return;
	}
	if ( $q->param('update') ) {
		$self->_update_user($username);
	}
	say q(<div class="box" id="queryform"><div class="scrollable">);
	say q(<span class="config_icon fas fa-edit fa-3x fa-pull-left"></span>);
	say q(<h2>User account details</h2>);
	if ( $username eq $self->{'username'} ) {
		say q(<p>Please ensure that your details are correct - if you submit data to the database these will be )
		  . q(associated with your record. The E-mail address will be used to send you notifications about your )
		  . q(submissions.</p>);
	}
	my $user_info = $self->{'datastore'}->get_user_info_from_username($username);
	$q->param( $_ => $q->param($_) // BIGSdb::Utils::unescape_html( $user_info->{$_} ) )
	  foreach qw(first_name surname email affiliation);
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
	say $q->textarea( -name => 'affiliation', -id => 'affiliation', -required => 'required', -cols => 30 );
	say q(</li></ul>);
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Update' } );
	$q->param( update => 1 );
	say $q->hidden($_) foreach qw(edit update user update_user);
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub _update_user {
	my ( $self, $username, $panel ) = @_;
	my $q = $self->{'cgi'};
	my @missing;
	my $data;
	foreach my $param (qw (first_name surname email affiliation)) {
		if ( !$q->param($param) || $q->param($param) eq q() ) {
			push @missing, $param;
		} else {
			$data->{$param} = $q->param($param);
			if ( $param eq 'affiliation' ) {
				$data->{$param} =~ s/\r?\n*$//x;
				$data->{$param} =~ s/,?\s*\r?\n/, /gx;
				$data->{$param} =~ s/,(\S)/, $1/gx;
			}
			$data->{$param} = $self->clean_value( $data->{$param}, { no_escape => 1 } );
			$data->{$param} = BIGSdb::Utils::escape_html( $data->{$param} );
		}
	}
	my $address = Email::Valid->address( scalar $q->param('email') );
	my $error;
	if (@missing) {
		local $" = q(, );
		$error = qq(Please enter the following parameters: @missing.);
	} elsif ( !$address ) {
		$error = q(E-mail address is not valid.);
	}
	if ($error) {
		$self->print_bad_status( { message => qq($error) } );
		return;
	}
	my $user_info = $self->{'datastore'}->get_user_info_from_username($username);
	my ( @changed_params, @new, %old );
	foreach my $param (qw (first_name surname email affiliation)) {
		if ( $data->{$param} ne $user_info->{$param} ) {
			push @changed_params, $param;
			push @new,            $data->{$param};
			$old{$param} = $user_info->{$param};
		}
	}
	if (@changed_params) {
		local $" = q(,);
		my @placeholders = ('?') x @changed_params;
		my $qry          = "UPDATE users SET (@changed_params,datestamp)=(@placeholders,?) WHERE user_name=?";
		eval {
			$self->{'db'}->do( $qry, undef, @new, 'now', $username );
			foreach my $param (@changed_params) {
				$self->{'db'}->do( 'INSERT INTO history (timestamp,user_name,field,old,new) VALUES (?,?,?,?,?)',
					undef, 'now', $username, $param, $user_info->{$param}, $data->{$param} );
			}
			$logger->info("$self->{'username'} updated user details for $username.");
		};
		if ($@) {
			$self->print_bad_status( { message => q(User detail update failed.) } );
			$logger->error($@);
			$self->{'db'}->rollback;
		} else {
			$self->print_good_status( { message => q(Details successfully updated.) } );
			$self->{'db'}->commit;
		}
	} else {
		$self->print_bad_status( { message => q(No changes made.) } );
	}
	return;
}

sub _show_user_roles {
	my ($self) = @_;
	my $buffer;
	$buffer .= $self->_registrations;
	say $buffer if $buffer;
	say $self->_api_keys;
	return;
}

sub _registrations {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $buffer = q();
	my $configs =
	  $self->{'datastore'}->run_query( 'SELECT dbase_config FROM registered_resources ORDER BY dbase_config',
		undef, { fetch => 'col_arrayref' } );
	return $buffer if !@$configs;
	$self->{'panel'}++;
	$buffer .= q(<h2>Database registrations</h2>);
	$buffer .= q(<div>);
	$buffer .= q(<span class="main_icon fas fa-list-alt fa-3x fa-pull-left"></span>);
	$buffer .=
		q(<p>Use this page to register your account with specific databases. )
	  . q(<strong><em>You need to do this if you want to submit data to a specific database, )
	  . q(access a password-protected resource, create a user project, or run jobs.</em>)
	  . q(</strong></p>);
	$buffer .= $self->_register if $q->param('register');
	$buffer .= $self->_request  if $q->param('request');
	my $registered_configs =
	  $self->{'datastore'}->run_query( 'SELECT dbase_config FROM registered_users WHERE user_name=?',
		$self->{'username'}, { fetch => 'col_arrayref' } );
	my $labels = $self->_get_config_labels;
	@$registered_configs = sort { $labels->{$a} cmp $labels->{$b} } @$registered_configs;
	$buffer .= q(<fieldset style="float:left"><legend>Registered</legend>);
	$buffer .= q(<p>Your account is registered for:</p>);

	if (@$registered_configs) {
		$buffer .= q(<div class="scrollable">);
		$buffer .= q(<div class="registered_configs">);
		$buffer .= q(<ul style="list-style:disc inside none">);
		foreach my $config (@$registered_configs) {
			$buffer .= qq(<li>$labels->{$config}</li>);
		}
		$buffer .= q(</ul>);
		$buffer .= q(</div></div>);
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
			-style    => 'min-width:10em; min-height:10em',
			-labels   => $labels
		);
		$buffer .= q(<div style='text-align:right;margin-top:0.5em'>);
		$buffer .= $q->submit( -name => 'register', -label => 'Register', -class => 'submit' );
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
		$buffer .= q(<p>Access to the listed resources can be requested but requires manual<br />authorization. );
		$buffer .=
			q(<strong><em>Check respective web sites for licencing and access<br />)
		  . q(conditions. Please ensure that you are registered with your real<br />)
		  . q(name and full affiliation or authorization is likely to be rejected.<br />)
		  . q(Affiliations should not use abbreviations unless these are<br />)
		  . q(internationally recognized.</em></strong><br />);
		$buffer .= q(Select from list and click 'Request' button.</p>);
		$buffer .= $q->start_form;
		$buffer .= q(<div style="float:left">);
		$buffer .= $self->popup_menu(
			-name     => 'request_reg',
			-id       => 'request_reg',
			-values   => $request_reg,
			-multiple => 'true',
			-style    => 'min-width:10em; min-height:7em',
			-labels   => $labels
		);
		$buffer .= q(<div style='text-align:right'>);
		$buffer .=
		  $q->submit( -name => 'request', -label => 'Request', -class => 'submit', -style => 'margin-top:0.5em' );
		$buffer .= q(</div></div>);
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
		$buffer .= q(<div class="scrollable">);
		$buffer .= q(<div class="registered_configs">);
		$buffer .= q(<ul style="list-style:disc inside none">);
		foreach my $config (@$pending) {
			$buffer .= qq(<li>$labels->{$config}</li>);
		}
		$buffer .= q(</ul>);
		$buffer .= q(</div></div>);
		$buffer .= q(</fieldset>);
	}
	if ( !@$auto_reg && !@$request_reg && !@$pending ) {
		$buffer .= q(<fieldset style="float:left"><legend>New registrations</legend>);
		$buffer .= q(<p>There are no other resources available to register for.</p>);
		$buffer .= q(</fieldset>);
	}
	if ( $q->param('register') || $q->param('request') ) {
		$buffer .= qq(<script>var active_panel=$self->{'panel'};</script>);
	}
	$buffer .= q(</div>);
	return $buffer;
}

sub _api_keys {
	my ($self) = @_;
	return q() if !( $self->{'config'}->{'automated_api_keys'} && $self->{'config'}->{'site_user_dbs'} );
	$self->{'panel'}++;
	my $q = $self->{'cgi'};
	my $buffer =
		q(<h2>API keys</h2>)
	  . q(<div><span class="main_icon fas fa-key fa-3x fa-pull-left"></span>)
	  . q(<p>Here you can create keys that enable you to delegate your account access to scripts or third-party )
	  . q(applications using the API without the need to share credentials. More details can be found at )
	  . q(<a href="https://bigsdb.readthedocs.io/en/latest/rest.html" target="_blank">)
	  . q(https://bigsdb.readthedocs.io/en/latest/rest.html</a>.</p>);
	my $email = $self->{'config'}->{'site_admin_email'};
	my $admins =
	  $email
	  ? qq(<a href="mailto:$email">site administrators</a>)
	  : q(site administrators);
	$buffer .= q(<p>Note that these are personal keys - if you want to obtain a key for a platform or organisation, )
	  . qq(beyond for testing purposes, then please contact the $admins.</p>);

	if ( $q->param('new_key') ) {
		$buffer .= qq(<script>var active_panel=$self->{'panel'};</script>);
		my $key_exists = $self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM clients WHERE (dbase,username,application)=(?,?,?))',
			[ $self->{'system'}->{'db'}, $self->{'username'}, scalar $q->param('key_name') ],
			{ db => $self->{'auth_db'} }
		);
		if ($key_exists) {
			$buffer .= q(<div class="box statusbad"><span class="statusbad">You already have )
			  . q(a key with that name. Use a different name.</span></div>);
		} else {
			my $client_id     = BIGSdb::Utils::random_string(24);
			my $client_secret = BIGSdb::Utils::random_string(42);
			my $key_name      = $q->param('key_name');
			eval {
				$self->{'auth_db'}->do(
					'INSERT INTO clients (application,version,client_id,client_secret,'
					  . 'default_permission,datestamp,default_submission,default_curation,dbase,username) VALUES '
					  . '(?,?,?,?,?,?,?,?,?,?)',
					undef,
					$key_name,
					'',
					$client_id,
					$client_secret,
					'allow',
					'now',
					'true',
					'false',
					$self->{'system'}->{'db'},
					$self->{'username'}
				);
			};
			if ($@) {
				$logger->error($@);
				$buffer .=
				  q(<div class="box statusbad_no_resize"><span class="statusbad">Error creating new key.</span></div>);
				$self->{'auth_db'}->rollback;
			} else {
				$logger->info("User $self->{'username'} created a new API key - $key_name.");
				$buffer .=
				  q(<div class="box statusgood_no_resize"><span class="statusgood">New API key created.</span></div>);
				$self->{'auth_db'}->commit;
			}
		}
	}
	if ( $q->param('revoke') ) {
		$buffer .= qq(<script>var active_panel=$self->{'panel'};</script>);
		my $client_id = $q->param('revoke');
		eval {
			$self->{'auth_db'}
			  ->do( 'DELETE FROM clients WHERE (client_id,username)=(?,?)', undef, $client_id, $self->{'username'} );
		};
		if ($@) {
			$logger->error($@);
			$self->{'auth_db'}->rollback;
		} else {
			$logger->info("User $self->{'username'} deleted API key.");
			$self->{'auth_db'}->commit;
		}
	}
	my $keys = $self->{'datastore'}->run_query(
		'SELECT * FROM clients WHERE (dbase,username)=(?,?) ORDER BY application',
		[ $self->{'system'}->{'db'}, $self->{'username'} ],
		{ db => $self->{'auth_db'}, fetch => 'all_arrayref', slice => {} }
	);
	if (@$keys) {
		$buffer .= q(<div class="scrollable"><table class="resultstable">);
		$buffer .=
		  q(<tr><th>Revoke</th><th>Key name</th><th>Client id</th><th>Client secret</th><th>Datestamp</th></tr>);
		my $td = 1;
		foreach my $key (@$keys) {
			my $revoke = DELETE;
			$buffer .=
				qq(<tr class="td$td"><td><a href="$self->{'system'}->{'script_name'}?revoke=$key->{'client_id'}" )
			  . qq(class="action">$revoke</a></td><td>$key->{'application'}</td>)
			  . qq(<td style="font-family:monospace">$key->{'client_id'}</td>)
			  . qq(<td style="font-family:monospace">$key->{'client_secret'}</td>)
			  . qq(<td>$key->{'datestamp'}</tr>);
			$td = $td == 1 ? 2 : 1;
		}
		$buffer .= q(</table></div>);
	}
	$buffer .= $q->start_form;
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	$buffer .= q(<fieldset style="float:left"><legend>Create new API key</legend>);
	$buffer .= q(<ul><li>);
	$buffer .= q(<label for="key_name">Key name: </label>);
	$buffer .= $q->textfield(
		-name      => 'key_name',
		-id        => 'key_name',
		-size      => 30,
		-maxlength => 50,
		-default   => "$user_info->{'first_name'} $user_info->{'surname'} - Personal key",
	);
	$buffer .= q(</li></ul>);
	$buffer .= q(</fieldset>);
	$buffer .= $self->print_action_fieldset( { no_reset => 1, get_only => 1, submit_name => 'new_key' } );
	$buffer .= $q->end_form;
	$buffer .= q(<div style="clear:both"></div></div>);
	return $buffer;
}

sub _register {
	my ($self)  = @_;
	my $q       = $self->{'cgi'};
	my @configs = $q->multi_param('auto_reg');
	return if !@configs;
	my $current_config;
	my @fail;
	my %reason;
	foreach my $config (@configs) {
		$current_config = $config;
		my $auto_reg =
		  $self->{'datastore'}->run_query( 'SELECT auto_registration FROM registered_resources WHERE dbase_config=?',
			$config, { cache => 'UserPage::register::check_auto_reg' } );
		next if !$auto_reg;
		my $already_registered_in_user_db = $self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM registered_users WHERE (dbase_config,user_name)=(?,?))',
			[ $config, $self->{'username'} ],
			{ cache => 'UserPage::register::check_already_reg' }
		);

		#Prevents refreshing page trying to register twice
		next if $already_registered_in_user_db;
		my $system = $self->_read_config_xml($config);
		my $db;
		eval { $db = $self->_get_db($system); };
		if ($@) {
			$self->{'db'}->rollback;
			push @fail, $config;
			$reason{$config} = q( - cannot connect to database.);
		}
		next if !$db;
		my $id      = $self->_get_next_id($db);
		my $user_db = $self->_get_user_db($db);
		next if !$user_db;
		eval {
			$self->{'db'}->do( 'INSERT INTO registered_users (dbase_config,user_name,datestamp) VALUES (?,?,?)',
				undef, $config, $self->{'username'}, 'now' );
			$db->do(
				'INSERT INTO users (id,user_name,status,date_entered,datestamp,curator,user_db) VALUES (?,?,?,?,?,?,?)',
				undef, $id, $self->{'username'}, 'user', 'now', 'now', 0, $user_db
			);
			$db->commit;
			$self->_drop_connection($system);
			$logger->info("User $self->{'username'} registered for $config.");
		};
		if ($@) {
			$self->{'db'}->rollback;
			push @fail, $config;
			if ( $@ =~ /users_user_name_key/x ) {
				$reason{$config} = q( - username already registered.);
			}
		}
	}
	if (@fail) {
		my $msg = q(Registration failed for:<ul>);
		foreach my $config (@fail) {
			$msg .= qq(<li>$config);
			$msg .= $reason{$config} if $reason{$config};
			$msg .= q(</li>);
		}
		$msg .= q(</ul>);
		return qq(<div class="box statusbad_no_resize"><span class="statusbad">$msg</span></div>);
	} else {
		$self->{'db'}->commit;
		return q(<div class="box statusgood_no_resize"><span class="statusgood">)
		  . q(User registration succeeded.</span></div>);
	}
	return;
}

sub _request {
	my ($self)  = @_;
	my $q       = $self->{'cgi'};
	my @configs = $q->multi_param('request_reg');
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
			$self->_notify_db_admin($config);
			$logger->info("$self->{'username'} requests registration for $config.");
		}
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
		return q(<div class="box statusbad_no_resize"><span class="statusbad">User request failed.</span></div>);
	} else {
		$self->{'db'}->commit;
		return q(<div class="box statusgood_no_resize"><span class="statusgood">)
		  . q(User request is now pending.</span></div>);
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
	if ($buffer) {
		say $buffer;
	} else {
		say q(<h2>Administrator functions</h2>);
		say q(<div class="box" id="statusbad" style="min-height:5em">);
		say q(<span class="config_icon far fa-thumbs-down fa-5x fa-pull-left"></span>);
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

sub _is_curator {
	my ( $self, $username ) = @_;
	return $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM registered_curators WHERE user_name=?)', $username );
}

sub _get_autoreg_status {
	my ( $self, $config ) = @_;
	return $self->{'datastore'}->run_query( 'SELECT auto_registration FROM available_resources WHERE dbase_config=?',
		$config, { cahce => 'UserPage::get_autoreg_status' } );
}

sub _import_dbase_config {
	my ($self) = @_;
	return q() if !$self->{'permissions'}->{'import_dbase_configs'};
	$self->{'panel'}++;
	my $q = $self->{'cgi'};
	my $set_panel;
	if ( $q->param('add') ) {
		$set_panel = 1;
		foreach my $config ( $q->multi_param('available') ) {
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
		$set_panel = 1;
		foreach my $config ( $q->multi_param('registered') ) {
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
	$buffer .= q(<h2>Enable database configurations for user registration</h2><div>);
	$buffer .= q(<span class="config_icon fas fa-wrench fa-3x fa-pull-left"></span>);
	if ( !@$registered_configs && !@$available_configs ) {
		$buffer .=
			q(<p>There are no configurations available or registered. Please run the sync_user_dbase_users.pl )
		  . q(script to populate the available configurations.</p>);
		return $buffer;
	}
	$buffer .= q(<p>Register configurations by selecting those available and moving to registered. Note that )
	  . q(user accounts are linked to specific databases rather than the configuration itself.</p>);
	$buffer .= qq(<script>var active_panel=$self->{'panel'};</script>) if $set_panel;
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
	  . qq(value="All" style="margin-top:1em" class="small_submit" />\n);
	$buffer .= q(<input type="button" onclick='listbox_selectall("available",false)' value="None" )
	  . q(style="margin-top:1em" class="small_submit" /></td><td></td>);
	$buffer .= q(<td style="text-align:center"><input type="button" onclick='listbox_selectall("registered",true)' )
	  . qq(value="All" style="margin-top:1em" class="small_submit" />\n);
	$buffer .= q(<input type="button" onclick='listbox_selectall("registered",false)' value="None" )
	  . q(style="margin-top:1em" class="small_submit" />);
	$buffer .= q(</td></tr></table>);
	$buffer .= $q->end_form;
	$buffer .= q(</div></div>);
	return $buffer;
}

sub _get_users {
	my ($self) = @_;
	if ( !$self->{'cache'}->{'users'} ) {
		my $users =
		  $self->{'datastore'}->run_query(
			'SELECT user_name,first_name,surname FROM users WHERE status=? ORDER BY surname, first_name, user_name',
			'validated', { fetch => 'all_arrayref', slice => {} } );
		my $usernames = [''];
		my $labels    = { '' => 'Select user...' };
		foreach my $user (@$users) {
			push @$usernames, $user->{'user_name'};
			$labels->{ $user->{'user_name'} } = "$user->{'surname'}, $user->{'first_name'} ($user->{'user_name'})";
		}
		$self->{'cache'}->{'users'}->{'usernames'} = $usernames;
		$self->{'cache'}->{'users'}->{'labels'}    = $labels;
	}
	return ( $self->{'cache'}->{'users'}->{'usernames'}, $self->{'cache'}->{'users'}->{'labels'} );
}

sub _show_merge_user_accounts {
	my ($self) = @_;
	return q() if !$self->{'permissions'}->{'merge_users'};
	my ( $usernames, $labels ) = $self->_get_users;
	return q() if !@$usernames;
	$self->{'panel'}++;
	my $buffer = q(<h2>Merge user accounts</h2><div>);
	$buffer .= q(<span class="config_icon fas fa-wrench fa-3x fa-pull-left"></span>);
	my $q = $self->{'cgi'};
	$buffer .= $q->start_form;
	$buffer .= q(<fieldset style="float:left"><legend>Select site account</legend>);
	$buffer .= $self->popup_menu( -name => 'user', -id => 'merge_user', -values => $usernames, -labels => $labels );
	$buffer .= $q->submit( -label => 'Select user', -class => 'small_submit' );
	$buffer .= q(</fieldset>);
	$buffer .= $q->hidden( merge_user => 1 );
	$buffer .= $q->end_form;
	$buffer .= q(</div>);
	return $buffer;
}

sub _show_modify_users {
	my ($self) = @_;
	return q() if !$self->{'permissions'}->{'modify_users'};
	my ( $usernames, $labels ) = $self->_get_users;
	return q() if !@$usernames;
	$self->{'panel'}++;
	my $buffer = q(<h2>Update user details</h2><div>);
	$buffer .= q(<span class="config_icon fas fa-wrench fa-3x fa-pull-left"></span>);
	my $q = $self->{'cgi'};
	$buffer .= $q->start_form;
	$buffer .= q(<fieldset><legend>Select site account</legend>);
	$buffer .= $self->popup_menu( -name => 'user', -id => 'modify_user', -values => $usernames, -labels => $labels );
	$buffer .= $q->submit( -label => 'Update user', -class => 'small_submit' );
	$buffer .= q(</fieldset>);
	$buffer .= $q->hidden( update_user  => 1 );
	$buffer .= $q->hidden( modify_other => 1 );
	$buffer .= $q->end_form;
	$buffer .= q(</div>);
	return $buffer;
}

sub _select_merge_users {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( scalar $q->param('user') );
	if ( !$user_info ) {
		$self->print_bad_status( { message => q(No information available for user.) } );
		return;
	}
	if ( !$self->{'permissions'}->{'merge_users'} ) {
		$self->print_bad_status( { message => q(Your account does not have permission to merge accounts.) } );
		return;
	}
	if ( $q->param('merge') ) {
		my $account;
		if ( $q->param('dbase_config') && $q->param('username') ) {
			$account = $q->param('dbase_config') . '|' . $q->param('username');
		} else {
			$account = $q->param('accounts');
		}
		$self->_merge( scalar $q->param('user'), $account );
	}
	$self->{'panel'}++;
	say q(<div class="box" id="queryform">);
	say q(<h2>Merge user accounts</h2>);
	say
	  q(<p>Please note that merging of user accounts may fail due to a database timeout if the site user account below )
	  . q(has multiple (1000+) records already associated with it in a specific database. This is unusual as the site user )
	  . q(account is normally newly created.</p>)
	  . q(<p>Database changes will be rolled back if this occurs so the system will always be in a consistent state.</p>);
	say q(<p><strong>Site user:</strong></p>);
	say q(<dl class="data">)
	  . qq(<dt>Username</dt><dd>$user_info->{'user_name'}</dd>)
	  . qq(<dt>First name</dt><dd>$user_info->{'first_name'}</dd>)
	  . qq(<dt>Last name</dt><dd>$user_info->{'surname'}</dd>)
	  . qq(<dt>E-mail</dt><dd>$user_info->{'email'}</dd>)
	  . qq(<dt>Affiliation</dt><dd>$user_info->{'affiliation'}</dd>)
	  . q(</dl>);
	my $possible_accounts = $self->_get_possible_matching_accounts( scalar $q->param('user') );
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
	say $q->textfield( -name => 'username', id => 'username', -default => scalar $q->param('user') );
	say q(</li></ul>);
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Merge' } );
	$q->param( merge => 1 );
	say $q->hidden($_) foreach qw(merge merge_user user);
	say $q->end_form;
	say q(</div>);
	say q(</div>);
	return;
}

sub _merge {
	my ( $self, $user, $account ) = @_;
	return if !$account;
	my ( $config, $remote_user ) = split /\|/x, $account;
	my $system = $self->_read_config_xml($config);
	my @curator_tables =
	  $self->{'datastore'}->get_tables_with_curator( { dbtype => $system->{'dbtype'} } );
	my @sender_tables =
	  $system->{'dbtype'} eq 'isolates'
	  ? qw(isolates sequence_bin allele_designations)
	  : qw(sequences profiles);
	my $db = $self->_get_db($system);
	my $db_user_id =
	  $self->{'datastore'}->run_query( 'SELECT id FROM users WHERE user_name=?', $remote_user, { db => $db } );
	my $site_user_id =
	  $self->{'datastore'}->run_query( 'SELECT id FROM users WHERE user_name=?', $user, { db => $db } );

	if ( !$db_user_id ) {
		$self->print_bad_status( { message => qq(User $remote_user is not found in $config.) } );
		return;
	}
	my $site_db =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id FROM user_dbases WHERE dbase_name=?', $self->{'system'}->{'db'}, { db => $db } );
	return if !$site_db;
	eval {
		if ( $db_user_id != $site_user_id ) {
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
		$self->print_bad_status( { message => q(Account failed to merge.) } );
	} else {
		$db->commit;
		$self->{'auth_db'}->commit;
		$self->print_good_status( { message => q(Account successfully merged.) } );
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
				my $affiliation_details =
				  $self->{'datastore'}->get_user_info_from_username( $recipient->{'user_name'} );
				$recipient->{$_} = $affiliation_details->{$_} foreach qw(first_name surname affiliation email);
			}
		}
	}
	if ( !@$recipients ) {
		$logger->error(
			"No admins or curators with permissions needed to import users to $system->{'description'} database.");
		return;
	}
	foreach my $user ( $sender, @$recipients ) {
		my $address = Email::Valid->address( $user->{'email'} );
		if ( !$address ) {
			$logger->error("Invalid E-mail address for user $user->{'id'}-$user->{'user_name'} - $user->{'email'}");
			return;
		}
	}
	$sender->{$_} = BIGSdb::Utils::unescape_html( $sender->{$_} ) foreach qw(first_name surname affiliation email);
	my $message =
		qq(The following user has requested access to the $system->{'description'} database.\n\n)
	  . qq(Username: $self->{'username'}\n)
	  . qq(First name: $sender->{'first_name'}\n)
	  . qq(Surname: $sender->{'surname'}\n)
	  . qq(Affiliation: $sender->{'affiliation'}\n)
	  . qq(E-mail: $sender->{'email'}\n\n);
	$message .=
	  qq(Please log in to the $system->{'description'} database curation system to accept or reject this user.);
	my $domain         = $self->{'config'}->{'domain'}                  // DEFAULT_DOMAIN;
	my $sender_address = $self->{'config'}->{'automated_email_address'} // "no_reply\@$domain";
	foreach my $recipient (@$recipients) {
		next if !$recipient->{'account_request_emails'};
		my $transport = Email::Sender::Transport::SMTP->new(
			{
				host => $self->{'config'}->{'smtp_server'} // 'localhost',
				port => $self->{'config'}->{'smtp_port'}   // 25,
			}
		);
		my $email = Email::MIME->create(
			attributes => {
				encoding => 'quoted-printable',
				charset  => 'UTF-8',
			},
			header_str => [
				To      => $recipient->{'email'},
				From    => $sender_address,
				Subject => $subject
			],
			body_str => $message
		);
		eval {
			try_to_sendmail( $email, { transport => $transport } )
			  || $logger->error("Cannot send E-mail to $recipient->{'email'}");
		};
		$logger->error($@) if $@;
	}
	$self->_drop_connection($system);
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $admin_js = q();
	if ( $self->{'curate'} ) {
		if ( $self->{'permissions'}->{'merge_users'} ) {
			my $url = "$self->{'script_name'}?ajax=merge_users";
			$admin_js .= <<"JS";
			\$.ajax({
				url: "$url",
				type: "GET",
				success: function(content){
					\$("#accordion").append(content);
					\$("#accordion").accordion("refresh");
				}
			});
JS
		}
		if ( $self->{'permissions'}->{'modify_users'} ) {
			my $url = "$self->{'script_name'}?ajax=modify_users";
			$admin_js .= <<"JS";
			\$.ajax({
				url: "$url",
				type: "GET",
				success: function(content){
					\$("#accordion").append(content);	
					\$("#accordion").accordion("refresh");
				}
			});
JS
		}
	}
	my $buffer = << "END";
\$(function () {
	render_selects();
	\$('input[type=radio][id=submission_digest]').change(function() {
	    if (this.value == '1') {
	        \$("#digest_interval").prop("disabled", false);
	    } else {
	    	\$("#digest_interval").prop("disabled", true);
	    }
	});
	if (typeof active_panel !== 'undefined'){
 		\$("#accordion").accordion({
 			heightStyle: "content",
 			active: active_panel
 		});
 	} else {
 		\$("#accordion").accordion({
	 		heightStyle: "content",
	 	});
 	}
 	$admin_js
	
	\$(window).resize(function() {
    	delay(function(){
    		\$("#auto_reg,#request_reg").multiselectfilter('destroy')
    		\$("#auto_reg,#request_reg").multiselect('destroy')
     		render_selects();
      		\$("#accordion").accordion("refresh");
    	}, 1000);
 	});
 	
	
});

function render_selects(){
	\$("#auto_reg,#request_reg").multiselect({
		noneSelectedText: "Please select...",
		listbox:true,
		menuHeight: 250,
		menuWidth: 'auto',
		classes: 'filter',
	}).multiselectfilter({
		placeholder: 'Search'
	});
}

function listbox_selectall(listID, isSelect) {
	\$("#" + listID + " option").prop("selected",isSelect);
}

var delay = (function(){
  var timer = 0;
  return function(callback, ms){
    clearTimeout (timer);
    timer = setTimeout(callback, ms);
  };
})();
END
	return $buffer;
}

sub _read_config_xml {
	my ( $self, $config ) = @_;
	if ( !$self->{'xmlHandler'} ) {
		$self->{'xmlHandler'} = BIGSdb::Parser->new;
	}
	my $parser = XML::Parser::PerlSAX->new( Handler => $self->{'xmlHandler'} );
	my $path   = "$self->{'dbase_config_dir'}/$config/config.xml";
	eval { $parser->parse( Source => { SystemId => $path } ) };
	if ($@) {
		$logger->fatal("Invalid XML description: $@");
		return;
	}
	my $system = $self->{'xmlHandler'}->get_system_hash;

	#Read system.override file
	my $override_file = "$self->{'dbase_config_dir'}/$config/system.overrides";
	if ( -e $override_file ) {
		open( my $fh, '<', $override_file )
		  || $logger->error("Cannot open $override_file for reading");
		while ( my $line = <$fh> ) {
			next if $line =~ /^\#/x;
			$line         =~ s/^\s+//x;
			$line         =~ s/\s+$//x;
			if ( $line =~ /^([^=\s]+)\s*=\s*"([^"]+)"$/x ) {
				$system->{$1} = $2;
			}
		}
		close $fh;
	}
	return $system;
}

sub _get_db_connection_args {
	my ( $self, $system ) = @_;
	my $args = {
		dbase_name => $system->{'db'},
		host       => $system->{'host'}     // $self->{'system'}->{'host'},
		port       => $system->{'port'}     // $self->{'system'}->{'port'},
		user       => $system->{'user'}     // $self->{'system'}->{'user'},
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
