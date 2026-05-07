#Written by Keith Jolley
#Copyright (c) 2010-2026, University of Oxford
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
package BIGSdb::ChangePasswordPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Login);
use Digest::MD5;
use Crypt::Eksblowfish::Bcrypt qw(bcrypt_hash en_base64);
use Encode                     qw(encode);
use Log::Log4perl              qw(get_logger);
my $logger = get_logger('BIGSdb.User');
use constant MIN_PASSWORD_LENGTH => 12;
use BIGSdb::Login qw(BCRYPT_COST UNIQUE_STRING);

sub get_title {
	return 'Change password';
}

sub initiate {
	my ($self) = @_;
	$self->SUPER::initiate;
	$self->{'jQuery.multiselect'} = 1;
	return if !$self->{'config'}->{'site_user_dbs'};
	$self->use_correct_user_database;
	foreach my $param (qw(user existing new1 new2)) {
		next if !defined $self->{'vars'}->{$param};
		$self->{'vars'}->{$param} =~ s/^\s+|\s+$//gx;
	}
	return;
}

sub _can_continue {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $self->{'system'}->{'authentication'} ne 'builtin' ) {
		$self->print_bad_status(
			{
				message => q(This database uses external means of authentication and the password )
				  . q(cannot be changed from within the web application.)
			}
		);
		return;
	}
	if (   $q->param('page') eq 'setPassword'
		&& !$self->{'permissions'}->{'set_user_passwords'}
		&& !$self->is_admin )
	{
		$self->print_bad_status( { message => q(You are not allowed to change other users' passwords.) } );
		return;
	}
	if ( $q->param('sent') && $q->param('page') eq 'setPassword' && !$q->param('user') ) {
		$self->print_bad_status( { message => q(Please select a user.) } );
		$self->_print_interface;
		return;
	}
	if ( !$self->is_admin && $q->param('user') && $self->{'system'}->{'dbtype'} ne 'user' ) {
		my $subject_info = $self->{'datastore'}->get_user_info_from_username( scalar $q->param('user') );
		if ( $subject_info && $subject_info->{'status'} eq 'admin' ) {
			$self->print_bad_status(
				{
					message => q(You cannot change the password of an admin )
					  . q(user unless you are an admin yourself.)
				}
			);
			$self->_print_interface;
			return;
		}
	}
	if ( $q->param('user') && $q->param('page') eq 'setPassword' ) {
		my $user_info = $self->{'datastore'}->get_user_info_from_username( scalar $q->param('user') );
		if ( $user_info && $user_info->{'user_db'} && !$self->{'permissions'}->{'set_site_user_passwords'} ) {
			$self->print_bad_status(
				{
						message => q(The account details for this )
					  . q(user are set in a site-wide user database. Your account does not have )
					  . q(permission to update passwords for such user accounts.)
				}
			);
			$self->_print_interface;
			return;
		}
	}
	return 1;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="login_container">);
	if ( !$self->_can_continue ) {
		say q(</div>);
		return;
	}
	if ( !$self->is_https && !$self->{'config'}->{'allow_http'} ) {
		say q(<div class="box statusbad"><p>Authentication is disabled when accessed via HTTP. )
		  . q(Please use HTTPS to continue.</p></div><div style="clear:both"></div></div>);
		$logger->error( q(Password change disabled as running under HTTP. Review setup - you can set 'allow_http=1' in )
			  . q(bigsdb.conf for testing. If running behind proxy then set X-Forwarded-Proto to https in proxy header.)
		);
		return;
	}
	if ( $q->param('sent') ) {
		my $further_checks = 1;
		if ( $q->param('page') eq 'changePassword' || $self->{'system'}->{'password_update_required'} ) {

			#make sure user is only attempting to change their own password (user parameter is passed as a hidden
			#parameter and could be changed)
			if ( $self->{'username'} ne $q->param('user') ) {
				$self->print_bad_status(
					{
						message => q(You are attempting to change another user's password. )
						  . q(You are not allowed to do that!)
					}
				);
				$further_checks = 0;
			} else {

				#existing password not set when admin setting user passwords
				my $stored_hash     = $self->get_password_hash( $self->{'username'} );
				my $passed_password = $self->{'vars'}->{'existing'};
				my $user_name       = $self->{'vars'}->{'user'};
				my $local_md5;
				eval { $local_md5 = Digest::MD5::md5_hex( encode( 'UTF-8', $passed_password . $user_name ) ); };
				$logger->error($@) if $@;
				my $password_matches = 1;

				if ( $stored_hash->{'algorithm'} eq 'bcrypt' ) {
					my $hashed_submitted_password = en_base64(
						bcrypt_hash(
							{ key_nul => 1, cost => $stored_hash->{'cost'}, salt => $stored_hash->{'salt'} },
							$local_md5
						)
					);
					if ( $stored_hash->{'password'} ne $hashed_submitted_password ) {
						$password_matches = 0;
					}
				}
				if ( !$password_matches ) {
					$self->print_bad_status(
						{
							message => q(Your existing password was entered incorrectly. )
							  . q(The password has not been updated.)
						}
					);
					$further_checks = 0;
					$q->param( $_ => '' ) foreach qw(existing new1 new2);
				}
			}
		}
		my $new_password = $q->param('new1');

		if ($further_checks) {
			my %checks = (
				length   => '_fails_password_check',
				retype   => '_fails_retype_check',
				new      => '_fails_new_check',
				username => '_fails_username_check'
			);
			my $failed;
			foreach my $check (qw(length retype new username)) {
				my $method = $checks{$check};
				if ( $self->$method($new_password) ) {
					$failed = 1;
					last;
				}
			}
			if ( !$failed ) {
				my $username =
				  ( $q->param('page') eq 'changePassword' || $self->{'system'}->{'password_update_required'} )
				  ? $self->{'username'}
				  : $q->param('user');
				my $instance_clause = $self->{'instance'} ? qq(?db=$self->{'instance'}) : q();
				my $new_hash;
				eval { $new_hash = Digest::MD5::md5_hex( encode( 'UTF-8', $new_password . $username ) ); };
				$logger->error($@) if $@;
				if ( $self->set_password_hash( $username, $new_hash ) ) {
					my $message =
					  $q->param('page') eq 'changePassword'
					  ? q(Password updated ok.)
					  : qq(Password set for user '$username'.);
					$self->print_good_status( { message => $message } );
					$self->_set_validated_status;
				} else {
					$self->print_bad_status(
						{
							message => q(Password not updated. Please check with the system administrator.)
						}
					);
				}
				return;
			} else {
				$q->param( $_ => '' ) foreach qw(existing new1 new2);
			}
		}
	}
	$self->_print_interface;
	say q(</div>);
	return;
}

sub _get_min_password_length {
	my ($self) = @_;
	return BIGSdb::Utils::is_int( $self->{'config'}->{'min_password_length'} )
	  ? $self->{'config'}->{'min_password_length'}
	  : MIN_PASSWORD_LENGTH;
}

sub _fails_password_check {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $new_password ) = @_;
	my $q          = $self->{'cgi'};
	my $min_length = $self->_get_min_password_length;
	if ( length($new_password) < $min_length ) {
		$self->print_bad_status(
			{
				message => q(The password is too short and has not been updated. )
				  . qq(It must be at least $min_length characters long.)
			}
		);
		return 1;
	}
	if ( $self->{'config'}->{'require_special_chars'} && !$self->_contains_special_chars($new_password) ) {
		my $plural = $self->{'config'}->{'require_special_chars'} == 1 ? q() : q(s);
		$self->print_bad_status(
			{
				message => qq(The password must contain at least $self->{'config'}->{'require_special_chars'} )
				  . qq(special character$plural: $!@#%^&*. )
			}
		);
		return 1;
	}
	if ( $self->{'config'}->{'require_lower_case'} && !$self->_contains_lower_case_letters($new_password) ) {
		my $plural = $self->{'config'}->{'require_lower_case'} == 1 ? q() : q(s);
		$self->print_bad_status(
			{
				message => qq(The password must contain at least $self->{'config'}->{'require_lower_case'} )
				  . qq(lower-case letter$plural (a-z).)
			}
		);
		return 1;
	}
	if ( $self->{'config'}->{'require_capitals'} && !$self->_contains_capitals($new_password) ) {
		my $plural = $self->{'config'}->{'require_capitals'} == 1 ? q() : q(s);
		$self->print_bad_status(
			{
				message => qq(The password must contain at least $self->{'config'}->{'require_capitals'} )
				  . qq(capital letter$plural (A-Z). )
			}
		);
		return 1;
	}
	if ( $self->{'config'}->{'require_digits'} && !$self->_contains_digits($new_password) ) {
		my $plural = $self->{'config'}->{'require_digits'} == 1 ? q() : q(s);
		$self->print_bad_status(
			{
				message => qq(The password must contain at least $self->{'config'}->{'require_digits'} )
				  . qq(digit$plural (A-Z). )
			}
		);
		return 1;
	}
	if ( $new_password eq $self->{'username'} ) {

	}
	return;
}

sub _contains_special_chars {
	my ( $self, $password ) = @_;
	my $required =
	  ( BIGSdb::Utils::is_int( $self->{'config'}->{'require_special_chars'} )
		  && $self->{'config'}->{'require_special_chars'} > 0 )
	  ? $self->{'config'}->{'require_special_chars'}
	  : 0;
	my $count = () = $password =~ /[\$\!\@\#\%\^\&\*\(\)]/gx;
	return if $count < $required;
	return 1;
}

sub _contains_lower_case_letters {
	my ( $self, $password ) = @_;
	my $required =
	  ( BIGSdb::Utils::is_int( $self->{'config'}->{'require_lower_case'} )
		  && $self->{'config'}->{'require_lower_case'} > 0 )
	  ? $self->{'config'}->{'require_lower_case'}
	  : 0;
	my $count = () = $password =~ /[a-z]/gx;
	return if $count < $required;
	return 1;
}

sub _contains_capitals {
	my ( $self, $password ) = @_;
	my $required =
	  ( BIGSdb::Utils::is_int( $self->{'config'}->{'require_capitals'} )
		  && $self->{'config'}->{'require_capitals'} > 0 )
	  ? $self->{'config'}->{'require_capitals'}
	  : 0;
	my $count = () = $password =~ /[A-Z]/gx;
	return if $count < $required;
	return 1;
}

sub _contains_digits {
	my ( $self, $password ) = @_;
	my $required =
	  ( BIGSdb::Utils::is_int( $self->{'config'}->{'require_digits'} ) && $self->{'config'}->{'require_digits'} > 0 )
	  ? $self->{'config'}->{'require_digits'}
	  : 0;
	my $count = () = $password =~ /[0-9]/gx;
	return if $count < $required;
	return 1;
}

sub _fails_retype_check {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('new1') ne $q->param('new2') ) {
		$self->print_bad_status( { message => q(The password was not re-typed the same as the first time.) } );
		return 1;
	}
	return;
}

sub _fails_new_check {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('existing') eq $q->param('new1') ) {
		$self->print_bad_status( { message => q(You must use a new password!) } );
		return 1;
	}
	return;
}

sub _fails_username_check {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $password ) = @_;
	my $q = $self->{'cgi'};
	my $username =
	  ( $q->param('page') eq 'changePassword' || $self->{'system'}->{'password_update_required'} )
	  ? $self->{'username'}
	  : $q->param('user');
	if ( length($username) > 3 && index( $password, $username ) != -1 ) {
		$self->print_bad_status( { message => q(You cannot use your username as part of your password!) } );
		return 1;
	}
	return;
}

#Update status in external user database if used.
sub _set_validated_status {
	my ($self) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'user';
	my $prior_status =
	  $self->{'datastore'}
	  ->run_query( 'SELECT status FROM users WHERE user_name=?', $self->{'username'}, { db => $self->{'db'} } );

	eval {
		$self->{'db'}->do( 'UPDATE users SET (status,validate_start)=(?,?) WHERE user_name=?',
			undef, 'validated', undef, $self->{'username'} );
		$logger->info("User $self->{'username'} has changed their password.");
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	if ( $prior_status eq 'pending' && $self->{'config'}->{'auto_registration_auto_select'} ) {
		my $user_db_name = $self->get_user_db_name( $self->{'username'} );
		my $configs      = $self->{'datastore'}->run_query(
			'SELECT dbase_config FROM registered_resources WHERE auto_registration AND dbase_config NOT IN '
			  . '(SELECT dbase_config FROM registered_users WHERE user_name=?) ORDER BY dbase_config',
			$self->{'username'},
			{ fetch => 'col_arrayref' }
		);

		#Use double fork to prevent zombie processes on apache2-mpm-worker
		defined( my $kid = fork ) or $logger->error('cannot fork');
		if ($kid) {
			waitpid( $kid, 0 );
		} else {
			defined( my $grandkid = fork ) or $logger->error('Kid cannot fork');
			if ($grandkid) {
				CORE::exit(0);
			} else {
				open STDIN,  '<',  '/dev/null' or $logger->error("Cannot detach STDIN: $!");
				open STDOUT, '>',  '/dev/null' or $logger->error("Cannot detach STDOUT: $!");
				open STDERR, '>&', \*STDOUT    or $logger->error("Cannot detach STDERR: $!");
				$self->_run_autoreg( $self->{'username'}, $user_db_name, $configs );
			}
			CORE::exit(0);
		}
	}
	return;
}

sub _run_autoreg {
	my ( $self, $user_name, $user_db_name, $configs ) = @_;
	foreach my $config (@$configs) {
		my $script = BIGSdb::Offline::Script->new(
			{
				config_dir       => $self->{'config_dir'},
				lib_dir          => $self->{'lib_dir'},
				dbase_config_dir => $self->{'dbase_config_dir'},
				host             => $self->{'system'}->{'host'},
				port             => $self->{'system'}->{'port'},
				user             => $self->{'system'}->{'user'},
				password         => $self->{'system'}->{'password'},
				instance         => $config,
				logger           => $logger,
			}
		);
		my $user_db_id =
		  $script->{'datastore'}->run_query( 'SELECT id FROM user_dbases WHERE dbase_name=?', $user_db_name );
		if ( defined $user_db_id ) {
			my $next_id =
			  $script->{'datastore'}
			  ->run_query( 'SELECT l.id + 1 AS start FROM users AS l LEFT OUTER JOIN users AS r ON l.id+1=r.id '
				  . 'WHERE r.id is null AND l.id > 0 ORDER BY l.id LIMIT 1' );
			$next_id = 1 if !$next_id;
			eval {
				$script->{'db'}->do(
					'INSERT INTO users (id,user_name,status,date_entered,datestamp,curator,user_db) '
					  . 'VALUES (?,?,?,?,?,?,?)',
					undef, $next_id, $user_name, 'user', 'now', 'now', 0, $user_db_id
				);
			};
			if ($@) {
				$logger->error($@);
				$script->{'db'}->rollback;
			} else {
				$script->{'db'}->commit;
				my $user_db = $script->{'datastore'}->get_user_db($user_db_id);
				eval {
					$user_db->do( 'INSERT INTO registered_users (dbase_config,user_name,datestamp) VALUES (?,?,?)',
						undef, $config, $user_name, 'now' );
				};
				if ($@) {
					$logger->error($@);
					$user_db->rollback;
				} else {
					$user_db->commit;
				}
				$logger->info("User $user_name registered for $config.");
			}
		}

	}
	return;
}

sub _print_interface {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="password_box">);
	say $q->param('page') eq 'changePassword' ? '<h1>Change password</h1>' : '<h1>Set user password</h1>';
	if ( $self->{'system'}->{'password_update_required'} ) {
		say q(<p>You are required to update your password.</p>);
	}
	say q(<p>Please enter your existing and new passwords.</p>) if $q->param('page') eq 'changePassword';
	my $min_length = $self->_get_min_password_length;
	my @requirements;

	if ( BIGSdb::Utils::is_int( $self->{'config'}->{'require_special_chars'} )
		&& $self->{'config'}->{'require_special_chars'} > 0 )
	{
		my $plural = $self->{'config'}->{'require_special_chars'} == 1 ? q() : q(s);
		push @requirements,
		  qq(at least $self->{'config'}->{'require_special_chars'} special character$plural ($!@#%^&*));
	}
	if ( BIGSdb::Utils::is_int( $self->{'config'}->{'require_lower_case'} )
		&& $self->{'config'}->{'require_lower_case'} > 0 )
	{
		my $plural = $self->{'config'}->{'require_lower_case'} == 1 ? q() : q(s);
		push @requirements, qq(at least $self->{'config'}->{'require_lower_case'} lower case letter$plural (a-z));
	}
	if ( BIGSdb::Utils::is_int( $self->{'config'}->{'require_capitals'} )
		&& $self->{'config'}->{'require_capitals'} > 0 )
	{
		my $plural = $self->{'config'}->{'require_capitals'} == 1 ? q() : q(s);
		push @requirements, qq(at least $self->{'config'}->{'require_capitals'} capital letter$plural (A-Z));
	}
	if ( BIGSdb::Utils::is_int( $self->{'config'}->{'require_digits'} )
		&& $self->{'config'}->{'require_digits'} > 0 )
	{
		my $plural = $self->{'config'}->{'require_digits'} == 1 ? q() : q(s);
		push @requirements, qq(at least $self->{'config'}->{'require_digits'} digit$plural (0-9));
	}

	print qq(<p>Passwords must be at least $min_length characters long);
	if (@requirements) {
		local $" = q(</li><li>);
		say qq( and contain:</p><ul><li>@requirements</li></ul>);
	} else {
		say q(.</p>);
	}
	say $q->start_form;
	say q(<fieldset style="border-top:0">);
	say q(<ul>);

	if ( $q->param('page') eq 'changePassword' || $self->{'system'}->{'password_update_required'} ) {
		say q(<li><label for="existing" class="aligned width8">Existing password:</label>);
		say $q->password_field( -name => 'existing', -id => 'existing' );
		say q(</li>);
	} elsif ( $q->param('user') && $self->{'datastore'}->user_name_exists( scalar $q->param('user') ) ) {
		my $user_info = $self->{'datastore'}->get_user_info_from_username( scalar $q->param('user') );
		say q(<li><label class="aligned width8">Name:</label>);
		say qq(<span><strong>$user_info->{'surname'}, $user_info->{'first_name'} )
		  . qq(($user_info->{'user_name'})</strong></span></li>);
		if ( $self->{'datastore'}->user_dbs_defined ) {
			my $domain;
			if ( BIGSdb::Utils::is_int( $user_info->{'user_db'} ) ) {
				$domain =
				  $self->{'datastore'}->run_query( 'SELECT name FROM user_dbases WHERE id=?', $user_info->{'user_db'} );
			} else {
				$domain = 'this database only';
			}
			say q(<li><label class="aligned width8">Domain:</label>);
			say qq(<span><strong>$domain</strong></span></li>);
			say $q->hidden('user_db');
		}
		say $q->hidden( existing => '' );
	} else {
		my ( $user_names, $labels ) = $self->{'datastore'}->get_users( { identifier => 'user_name', format => 'sfu' } );
		unshift @$user_names, '';
		say q(<li><label for="user" class="aligned width8">User:</label>);
		say $q->popup_menu( -name => 'user', -id => 'user', -values => $user_names, -labels => $labels );
		say $q->hidden( existing => '' );
		say q(</li>);
	}
	say q(<li><label for="new1" class="aligned width8">New password:</label>);
	say $q->password_field( -name => 'new1', -id => 'new1' );
	say q(</li>);
	say q(<li><label for="new2" class="aligned width8">Retype password:</label>);
	say $q->password_field( -name => 'new2', -id => 'new2' );
	say q(</li></ul></fieldset>);
	say $q->submit( -name => 'submit', -label => 'Set password', -class => 'submit', -style => 'margin-top:1em' );
	$q->param( user => $self->{'username'} )
	  if $q->param('page') eq 'changePassword' || $self->{'system'}->{'password_update_required'};
	$q->param( sent => 1 );
	say $q->hidden($_) foreach qw (db page session  user sent);
	say $q->end_form;

	if ( $q->param('page') eq 'changePassword' ) {
		say q(<p style="margin-top:1em">You will be required to log in again with the new password )
		  . q(once you have changed it.</p>);
	}
	say q(</div>);
	return;
}

sub set_password_hash {
	my ( $self, $name, $hash, $options ) = @_;
	return if !$name;
	my $bcrypt_cost =
	  BIGSdb::Utils::is_int( $self->{'config'}->{'bcrypt_cost'} ) ? $self->{'config'}->{'bcrypt_cost'} : BCRYPT_COST;
	my $salt           = BIGSdb::Utils::random_string( 16, { extended_chars => 1 } );
	my $bcrypt_hash    = en_base64( bcrypt_hash( { key_nul => 1, cost => $bcrypt_cost, salt => $salt }, $hash ) );
	my $reset_password = $options->{'reset_password'} ? 1 : 0;
	my $db_name        = $self->get_user_db_name($name);
	my $exists         = $self->{'datastore'}->run_query(
		'SELECT EXISTS(SELECT * FROM users WHERE (dbase,name)=(?,?))',
		[ $db_name, $name ],
		{ db => $self->{'auth_db'} }
	);
	my $qry;
	my @values = ( $bcrypt_hash, 'bcrypt', $bcrypt_cost, $salt, $reset_password );

	if ( !$exists ) {
		$qry = 'INSERT INTO users (password,algorithm,cost,salt,reset_password,dbase,name,date_entered,datestamp) '
		  . 'VALUES (?,?,?,?,?,?,?,?,?)';
		push @values, ( $db_name, $name, 'now', 'now' );
	} else {
		$qry = 'UPDATE users SET (password,algorithm,cost,salt,reset_password,datestamp)=(?,?,?,?,?,?) '
		  . 'WHERE (dbase,name)=(?,?)';
		push @values, ( 'now', $db_name, $name );
	}
	eval { $self->{'auth_db'}->do( $qry, undef, @values ); };
	if ($@) {
		$logger->error($@);
		$self->{'auth_db'}->rollback;
		return 0;
	} else {
		$self->{'auth_db'}->commit;
		return 1;
	}
}

sub get_javascript {
	my ($self) = @_;
	my $buffer = << "END";
\$(function () {
 	\$("#user").multiselect({
		noneSelectedText: "Please select...",
		selectedList: 1,
		menuHeight: 250,
		menuWidth: 300,
		classes: 'filter',
	}).multiselectfilter({
		placeholder: 'Search'
	});	
 
});	

END
	return $buffer;
}
1;
