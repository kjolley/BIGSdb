#Written by Keith Jolley
#Copyright (c) 2010-2022, University of Oxford
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
package BIGSdb::ChangePasswordPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Login);
use Crypt::Eksblowfish::Bcrypt qw(bcrypt_hash en_base64);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.User');
use constant MIN_PASSWORD_LENGTH => 8;
use BIGSdb::Login qw(BCRYPT_COST UNIQUE_STRING);

sub get_title {
	return 'Change password';
}

sub initiate {
	my ($self) = @_;
	$self->SUPER::initiate;
	return if !$self->{'config'}->{'site_user_dbs'};
	$self->use_correct_user_database;
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
	if ( $q->param('sent') && $q->param('existing_password') ) {
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
				my $stored_hash      = $self->get_password_hash( $self->{'username'} );
				my $password_matches = 1;
				if ( !$stored_hash->{'algorithm'} || $stored_hash->{'algorithm'} eq 'md5' ) {
					if ( $stored_hash->{'password'} ne $q->param('existing_password') ) {
						$password_matches = 0;
					}
				} elsif ( $stored_hash->{'algorithm'} eq 'bcrypt' ) {
					my $hashed_submitted_password = en_base64(
						bcrypt_hash(
							{ key_nul => 1, cost => $stored_hash->{'cost'}, salt => $stored_hash->{'salt'} },
							$q->param('existing_password')
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
				}
			}
		}
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
				if ( $self->$method ) {
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
				if ( $self->set_password_hash( $username, scalar $q->param('new_password1') ) ) {
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
			}
		}
	}
	$self->_print_interface;
	say q(</div>);
	return;
}

sub _fails_password_check {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $min_length = MIN_PASSWORD_LENGTH;
	if ( $q->param('new_length') < MIN_PASSWORD_LENGTH ) {
		$self->print_bad_status(
			{
				message => q(The password is too short and has not been updated. )
				  . qq(It must be at least $min_length characters long.)
			}
		);
		return 1;
	}
	return;
}

sub _fails_retype_check {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('new_password1') ne $q->param('new_password2') ) {
		$self->print_bad_status( { message => q(The password was not re-typed the same as the first time.) } );
		return 1;
	}
	return;
}

sub _fails_new_check {       ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('existing_password') eq $q->param('new_password1') ) {
		$self->print_bad_status( { message => q(You must use a new password!) } );
		return 1;
	}
	return;
}

sub _fails_username_check {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('username_as_password') eq $q->param('new_password1') ) {
		$self->print_bad_status( { message => q(You can't use your username as your password!) } );
		return 1;
	}
	return;
}

#Update status in external user database if used.
sub _set_validated_status {
	my ($self) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'user';
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
	say q(<p>Passwords must be at least ) . MIN_PASSWORD_LENGTH . q( characters long.</p>);
	say q(<noscript><p class="highlight">Please note that Javascript must be enabled in order to login. )
	  . q(Passwords are encrypted using Javascript prior to transmitting to the server.</p></noscript>);
	say $q->start_form(
		-onSubmit => q[existing_password.value=existing.value.trim();existing.value='';]
		  . q[new_length.value=new1.value.trim().length;var username;]
		  . q[if ($('#user').length){username=document.getElementById('user').value} else {username=user.value}]
		  . q[new_password1.value=new1.value.trim();new1.value='';new_password2.value=new2.value.trim();new2.value='';]
		  . q[existing_password.value=CryptoJS.MD5(existing_password.value+username);]
		  . q[new_password1.value=CryptoJS.MD5(new_password1.value+username);]
		  . q[new_password2.value=CryptoJS.MD5(new_password2.value+username);]
		  . q[username_as_password.value=CryptoJS.MD5(username+username);]
		  . q[return true]
	);
	say q(<fieldset style="border-top:0">);
	say q(<ul>);
	if ( $q->param('page') eq 'changePassword' || $self->{'system'}->{'password_update_required'} ) {
		say q(<li><label for="existing" class="form" style="width:10em">Existing password:</label>);
		say $q->password_field( -name => 'existing', -id => 'existing' );
		say q(</li>);
	} elsif ( $q->param('user') && $self->{'datastore'}->user_name_exists( scalar $q->param('user') ) ) {
		my $user_info = $self->{'datastore'}->get_user_info_from_username( scalar $q->param('user') );
		say q(<li><label class="form" style="width:10em">Name:</label>);
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
			say q(<li><label class="form" style="width:10em">Domain:</label>);
			say qq(<span><strong>$domain</strong></span></li>);
			say $q->hidden('user_db');
		}
		say $q->hidden( existing => '' );
	} else {
		my ( $user_names, $labels ) = $self->{'datastore'}->get_users( { identifier => 'user_name', format => 'sfu' } );
		unshift @$user_names, '';
		say q(<li><label for="user" class="form" style="width:10em">User:</label>);
		say $q->popup_menu( -name => 'user', -id => 'user', -values => $user_names, -labels => $labels );
		say $q->hidden( existing => '' );
		say q(</li>);
	}
	say q(<li><label for="new1" class="form" style="width:10em">New password:</label>);
	say $q->password_field( -name => 'new1', -id => 'new1' );
	say q(</li>);
	say q(<li><label for="new2" class="form" style="width:10em">Retype password:</label>);
	say $q->password_field( -name => 'new2', -id => 'new2' );
	say q(</li></ul></fieldset>);
	say $q->submit( -name => 'submit', -label => 'Set password', -class => 'submit', -style => 'margin-top:1em' );
	$q->param( $_ => '' ) foreach qw (existing_password new_password1 new_password2 new_length username_as_password);
	$q->param( user => $self->{'username'} )
	  if $q->param('page') eq 'changePassword' || $self->{'system'}->{'password_update_required'};
	$q->param( sent => 1 );
	say $q->hidden($_) foreach qw (db page session existing_password new_password1 new_password2
	  new_length user sent username_as_password);
	say $q->end_form;

	if ( $q->param('page') eq 'changePassword' ) {
		say q(<p>You will be required to log in again with the new password once you have changed it.</p>);
	}
	say q(</div>);
	return;
}

sub set_password_hash {
	my ( $self, $name, $hash, $options ) = @_;
	return if !$name;
	my $bcrypt_cost =
	  BIGSdb::Utils::is_int( $self->{'config'}->{'bcrypt_cost'} ) ? $self->{'config'}->{'bcrypt_cost'} : BCRYPT_COST;
	my $salt = BIGSdb::Utils::random_string( 16, { extended_chars => 1 } );
	my $bcrypt_hash = en_base64( bcrypt_hash( { key_nul => 1, cost => $bcrypt_cost, salt => $salt }, $hash ) );
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
1;
