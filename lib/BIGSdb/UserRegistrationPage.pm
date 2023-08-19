#Written by Keith Jolley
#Copyright (c) 2016-2022, University of Oxford
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
package BIGSdb::UserRegistrationPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage BIGSdb::ChangePasswordPage);
use BIGSdb::Constants qw(:accounts :interface DEFAULT_DOMAIN);
use Email::Sender::Transport::SMTP;
use Email::Sender::Simple qw(try_to_sendmail);
use Email::MIME;
use Email::Valid;
use Digest::MD5;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.User');

sub print_content {
	my ($self) = @_;
	say q(<div class="login_container">);
	if ( $self->{'config'}->{'disable_updates'} ) {
		$self->print_bad_status(
			{
				message => q(The registration pages are currently disabled.),
				detail  => $self->{'config'}->{'disable_update_message'}
			}
		);
		say q(</div>);
		return;
	}
	if ( !$self->{'config'}->{'auto_registration'} ) {
		$self->print_bad_status( { message => q(This site does not allow automated registrations.) } );
		say q(</div>);
		return;
	}
	if ( $self->{'system'}->{'dbtype'} ne 'user' ) {
		$self->print_bad_status(
			{
				message => q(Account registrations cannot be performed when accessing a database.),
			}
		);
		say q(</div>);
		return;
	}
	my $q = $self->{'cgi'};
	if ( $q->param('register') ) {
		$self->_register;
		say q(</div>);
		return;
	}
	if ( $q->param('page') eq 'usernameRemind' && $q->param('email') ) {
		$self->_username_reminder( scalar $q->param('email') );
		say q(</div>);
		return;
	}
	if ( $q->param('page') eq 'resetPassword' && $q->param('username') && $q->param('email') ) {
		$self->_reset_password( scalar $q->param('username'), scalar $q->param('email') );
		say q(</div>);
		return;
	}
	$self->_print_registration_form;
	say q(</div>);
	return;
}

sub _username_reminder {
	my ( $self, $email_address ) = @_;
	$email_address =~ s/^\s+|\s+$//gx;
	my $address = Email::Valid->address($email_address);
	if ( !$address ) {
		$self->print_bad_status(
			{
				message  => q(The passed E-mail address is not valid),
				navbar   => 1,
				back_url => $self->{'system'}->{'script_name'}
			}
		);
		return;
	}

	#Only send E-mail if we find an account but don't tell user if we don't (to stop this being used
	#to check if specific addresses have registered accounts).
	my $usernames =
	  $self->{'datastore'}->run_query( 'SELECT user_name FROM users WHERE LOWER(email)=LOWER(?) ORDER BY user_name',
		$email_address, { fetch => 'col_arrayref' } );
	$self->print_good_status(
		{
			message => qq(A user name reminder has been sent to $email_address if )
			  . q(it has a user name associated with it.),
			navbar   => 1,
			back_url => qq($self->{'system'}->{'script_name'})
		}
	);
	return if !@$usernames;
	my $transport = Email::Sender::Transport::SMTP->new(
		{ host => $self->{'config'}->{'smtp_server'} // 'localhost', port => $self->{'config'}->{'smtp_port'} // 25, }
	);
	my $domain      = $self->{'config'}->{'domain'} // DEFAULT_DOMAIN;
	my $user_domain = $self->_get_user_domain;
	my $message = qq(A user name reminder has been requested for the address $email_address (domain: $user_domain).\n);
	$message .= qq(The request came from IP address: $ENV{'REMOTE_ADDR'}.\n\n);
	my $plural = @$usernames == 1 ? q() : q(s);
	$message .= qq(This address is associated with the following user name$plural:\n\n);

	foreach my $username (@$usernames) {
		my $status = $self->{'datastore'}->run_query( 'SELECT status FROM users WHERE user_name=?', $username );
		if ( $status eq 'validated' ) {
			$message .= qq($username\n);
		} else {
			$message .= qq($username (not yet validated - will be removed automatically soon)\n);
		}
	}
	if ( $self->{'config'}->{'site_admin_email'} ) {
		$message .= qq(\nPlease use the password reset link on the registration page if you need to. If all else )
		  . qq(fails then please contact $self->{'config'}->{'site_admin_email'}.\n);
	}
	$message .= qq(\n);
	my $registrations = $self->{'datastore'}->run_query(
		'SELECT ar.dbase_config,ar.description,u.user_name FROM registered_users ru JOIN '
		  . 'available_resources ar ON ru.dbase_config=ar.dbase_config JOIN users u ON u.user_name=ru.user_name WHERE '
		  . 'LOWER(email)=LOWER(?) ORDER BY ar.dbase_config,u.user_name',
		$email_address,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $is_are = @$usernames > 1 ? 'are' : 'is';
	if (@$registrations) {
		$message .= qq(Your account$plural $is_are registered for the following databases:\n\n);
	} else {
		$message .= qq(Your account$plural $is_are not yet registered for any databases. )
		  . qq(You need to register for a specific database before you can log in.\n\n);
	}
	foreach my $reg (@$registrations) {
		my $value = qq($reg->{'dbase_config'} ($reg->{'description'}));
		$value   .= qq( - Username: $reg->{'user_name'}) if @$usernames > 1;
		$message .= qq($value\t\n);    #Terminal tab prevents Outlook removing newlines.
	}
	if ( $self->{'config'}->{'registration_address'} ) {
		my $additional = @$registrations ? q(additional ) : q();
		$message .= qq(\nYou can update your profile or register for ${additional}databases at )
		  . qq($self->{'config'}->{'registration_address'}.);
	}
	my $sender_address = $self->{'config'}->{'automated_email_address'} // "no_reply\@$domain";
	my $email          = Email::MIME->create(
		attributes => {
			encoding => 'quoted-printable',
			charset  => 'UTF-8',
		},
		header_str => [
			To      => $email_address,
			From    => $sender_address,
			Subject => "$domain user name reminder",
		],
		body_str => $message
	);
	eval {
		try_to_sendmail( $email, { transport => $transport } )
		  || $logger->error("Cannot send E-mail to $email_address.");
	};
	$logger->error($@) if $@;
	$logger->info("Username reminder requested for $email_address ($user_domain).");
	return;
}

sub _get_user_domain {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	foreach my $user_db ( @{ $self->{'config'}->{'site_user_dbs'} } ) {
		if ( $user_db->{'dbase'} eq $q->param('domain') ) {
			return $user_db->{'name'};
		}
	}
	return 'default domain';
}

sub _reset_password {
	my ( $self, $username, $email_address ) = @_;
	$username      =~ s/^\s+|\s+$//gx;
	$email_address =~ s/^\s+|\s+$//gx;
	my $address = Email::Valid->address($email_address);
	if ( !$address ) {
		$self->print_bad_status(
			{
				message  => q(The passed E-mail address is not valid),
				navbar   => 1,
				back_url => $self->{'system'}->{'script_name'}
			}
		);
		return;
	}

	#Attempts have been made to use the password reset for spamming with the username set to
	#the spam message. Don't send E-mail if username is longer than allowed or if it contains
	#slashes as used in web addresses.
	if ( length $username > 20 || $username =~ /\//x ) {
		$self->print_bad_status(
			{
				message  => q(The passed user name is not valid),
				navbar   => 1,
				back_url => $self->{'system'}->{'script_name'}
			}
		);
		$logger->error("Invalid username '$username' passed.");
		return;
	}
	my $user_domain = $self->_get_user_domain;
	$self->print_good_status(
		{
			message => qq(A temporary password has been sent to $email_address for $username (domain: $user_domain) )
			  . q(if an account with these details exists.),
			navbar   => 1,
			back_url => qq($self->{'system'}->{'script_name'})
		}
	);
	my $password = $self->_create_password;
	my $message  = qq(A password reset has been requested for user '$username' with E-mail address '$email_address' )
	  . qq((domain: $user_domain).\n);
	$message .= qq(The request came from IP address: $ENV{'REMOTE_ADDR'}.\n\n);
	if (
		$self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM users WHERE (user_name,LOWER(email))=(?,LOWER(?)))',
			[ $username, $email_address ]
		)
	  )
	{
		$self->set_password_hash( $username, Digest::MD5::md5_hex( $password . $username ), { reset_password => 1 } );
		$logger->info("Password reset request for $email_address ($user_domain).");
		if ( $self->{'config'}->{'registration_address'} ) {
			$message .=
			  qq(Please log on at $self->{'config'}->{'registration_address'} with the following details:\n\n);
		} else {
			$message .= qq(Please log on with the following details:\n\n);
		}
		$message .= qq(Username: $username\n);
		$message .= qq(Password: $password\n\n);
		$message .= qq(You will be required to then change your password.\n\n);
	} else {
		$logger->error("Password reset request for $username ($email_address). Address does not match user.");
		$message .= q(There is no account with that username registered to this address.);
	}
	my $transport = Email::Sender::Transport::SMTP->new(
		{ host => $self->{'config'}->{'smtp_server'} // 'localhost', port => $self->{'config'}->{'smtp_port'} // 25, }
	);
	my $domain         = $self->{'config'}->{'domain'}                  // DEFAULT_DOMAIN;
	my $sender_address = $self->{'config'}->{'automated_email_address'} // "no_reply\@$domain";
	my $email          = Email::MIME->create(
		attributes => {
			encoding => 'quoted-printable',
			charset  => 'UTF-8',
		},
		header_str => [
			To      => $email_address,
			From    => $sender_address,
			Subject => "$domain password reset",
		],
		body_str => $message
	);
	eval {
		try_to_sendmail( $email, { transport => $transport } )
		  || $logger->error("Cannot send E-mail to  $email_address");
	};
	$logger->error($@) if $@;
	return;
}

sub _print_registration_form {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="registration_box">);
	say q(<h1>Register</h1>);
	say q(<p>If you don't already have a site account, you can register below. Please ensure that you enter a valid )
	  . q(E-mail address as account validation details will be sent to this.</p>);
	say q(<p>Please note that user names:</p><ul>);
	say q(<li>should be between 4 and 20 characters long</li>);
	say q(<li>can contain only alpha-numeric characters (A-Z, a-z, 0-9) - no spaces, hyphens or punctuation</li>);
	say q(<li>are case-sensitive</li>);
	say q(</ul>);
	say q(<p><strong><em>Please fill in your details completely with proper first letter capitalization of names and )
	  . q(full affiliation details (avoiding acronyms). This information will appear with any data that you submit.)
	  . q(</em></strong></p>);
	say $q->start_form;
	say q(<fieldset class="form" style="float:left"><legend>Please enter your details</legend>);
	say q(<ul><li>);
	my $user_dbs = $self->{'config'}->{'site_user_dbs'};
	my $values   = [];
	my $labels   = {};

	foreach my $user_db (@$user_dbs) {
		push @$values, $user_db->{'dbase'};
		$labels->{ $user_db->{'dbase'} } = $user_db->{'name'};
	}
	say q(<label for="db" class="form">Domain: </label>);
	if ( @$values == 1 ) {
		say $q->popup_menu(
			-name     => 'domain',
			-id       => 'domain',
			-values   => $values,
			-labels   => $labels,
			-disabled => 'disabled'
		);
		say $q->hidden( domain => $values->[0] );
	} else {
		unshift @$values, q();
		say $q->popup_menu(
			-name     => 'domain',
			-id       => 'domain',
			-values   => $values,
			-labels   => $labels,
			-required => 'required'
		);
	}
	say q(</li><li>);
	say q(<label for="user_name" class="form">User name:</label>);
	say $q->textfield( -name => 'user_name', -id => 'user_name', -required => 'required', size => 25 );
	say q(</li><li>);
	say q(<label for="first_name" class="form">First name:</label>);
	say $q->textfield( -name => 'first_name', -id => 'first_name', -required => 'required', size => 25 );
	say q(</li><li>);
	say q(<label for="surname" class="form">Last name/surname:</label>);
	say $q->textfield( -name => 'surname', -id => 'surname', -required => 'required', size => 25 );
	say q(</li><li>);
	say q(<label for="email" class="form">E-mail:</label>);
	say $q->textfield( -name => 'email', -id => 'email', -required => 'required', size => 25 );
	say q(</li><li>);
	say q(<label for="affiliation" class="form">Affiliation (institute):</label>);
	say $q->textarea( -name => 'affiliation', -id => 'affiliation', -required => 'required' );
	say q(</li></ul>);
	say q(</fieldset>);
	$q->param( register => 1 );
	say $q->hidden($_) foreach qw(page register);
	say $q->submit( -name => 'submit', -label => 'Register', -class => 'submit', -style => 'margin-top:1em' );
	say $q->end_form;
	say q(</div>);
	return;
}

sub _register {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	foreach my $param (qw(domain first_name surname email affiliation)) {
		my $cleaned = $self->clean_value( scalar $q->param($param), { no_escape => 1 } );
		$q->param( $param => $cleaned );
		if ( !$q->param($param) ) {
			$self->print_bad_status( { message => q(Please complete form.) } );
			$self->_print_registration_form;
			return;
		}
	}
	my $data = {};
	$data->{$_} = $q->param($_) foreach qw(domain user_name first_name surname email affiliation);
	if ( $self->_bad_username( $data->{'user_name'} ) || $self->_bad_email( $data->{'email'} ) ) {
		$self->_print_registration_form;
		return;
	}
	foreach my $param ( keys %$data ) {
		if ( $param eq 'affiliation' ) {
			$data->{$param} =~ s/\r?\n*$//x;
			$data->{$param} =~ s/,?\s*\r?\n/, /gx;
			$data->{$param} =~ s/,(\S)/, $1/gx;
		}
		$data->{$param} = $self->clean_value( $data->{$param}, { no_escape => 1 } );
		$data->{$param} = BIGSdb::Utils::escape_html( $data->{$param} );
	}
	$self->format_data( 'users', $data );
	$data->{'password'} = $self->_create_password;
	eval {
		$self->{'db'}->do(
			'INSERT INTO users (user_name,first_name,surname,email,affiliation,date_entered,'
			  . 'datestamp,status,validate_start) VALUES (?,?,?,?,?,?,?,?,?)',
			undef,
			$data->{'user_name'},
			$data->{'first_name'},
			$data->{'surname'},
			$data->{'email'},
			$data->{'affiliation'},
			'now',
			'now',
			'pending',
			time
		);
		$self->set_password_hash(
			$data->{'user_name'},
			Digest::MD5::md5_hex( $data->{'password'} . $data->{'user_name'} ),
			{ reset_password => 1 }
		);
	};
	if ($@) {
		$self->print_bad_status(
			{ message => q(User creation failed. This error has been logged - please try again later.) } );
		$logger->error($@);
		$self->{'db'}->rollback;
		return;
	}
	$self->{'db'}->commit;
	say q(<div class="box" id="resultspanel">);
	say q(<span class="main_icon far fa-address-card fa-3x fa-pull-left"></span>);
	say q(<h2>New account</h2>);
	say q(<p>A new account has been created with the details below. The user name and a randomly-generated )
	  . q(password has been sent to your E-mail address. You are required to validate your account by )
	  . qq(logging in and changing your password within $self->{'validate_time'} minutes.</p>);
	say q(<dl class="data">);
	say qq(<dt>First name</dt><dd>$data->{'first_name'}</dd>);
	say qq(<dt>Last name</dt><dd>$data->{'surname'}</dd>);
	say qq(<dt>E-mail</dt><dd>$data->{'email'}</dd>);
	say qq(<dt>Affiliation</dt><dd>$data->{'affiliation'}</dd>);
	say q(</dl>);
	say q(<dl class="data">);
	say qq(<dt>Username</dt><dd><b>$data->{'user_name'}</b></dd>);
	say q(</dl>);
	say qq(<p>Please note that your account may be removed if you do not log in for $self->{'inactive_time'} days. )
	  . q(This does not apply to accounts that have submitted data linked to them within the database.</p>);
	say q(<p>Once you log in you will be able to register for specific resources on the site.</p>);
	say qq(<p><a href="$self->{'system'}->{'script_name'}" class="submit">Log in</a></p>);
	say q(</div>);

	#Log files indicate form spamming using random registration details that contain random alphanumeric strings
	#for names. This is a very crude and simple means of blocking these. May need something more sophisticated.
	#These also use a long random string without spaces for the affiliation so we can check for this.
	if (   $data->{'first_name'} =~ /\d/x
		|| $data->{'surname'} =~ /\d/x
		|| ( length $data->{'affiliation'} > 30 && $data->{'affiliation'} !~ /\s/x ) )
	{
		$logger->error(
			"Attempted form spam blocked - User $data->{'user_name'} ($data->{'first_name'} $data->{'surname'})");
	} else {
		$self->_send_email($data);
		$logger->info(
			"User $data->{'user_name'} ($data->{'first_name'} $data->{'surname'}) has registered for the site.");
	}
	return;
}

sub _bad_email {
	my ( $self, $email ) = @_;
	my $address = Email::Valid->address($email);
	if ( !$address ) {
		$self->print_bad_status( { message => q(The provided E-mail address is not valid.) } );
		return 1;
	}
	my $registration_exists =
	  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM users WHERE UPPER(email)=UPPER(?))', $email );
	if ($registration_exists) {
		my $detail;
		if ( $self->{'config'}->{'site_admin_email'} ) {
			$detail = qq(Contact the <a href="mailto:$self->{'config'}->{'site_admin_email'}">site administrator</a> )
			  . q(if you need to reset your password.);
		}
		$self->print_bad_status(
			{
				message => q(An account has already been registered with this E-mail address. )
				  . qq(<a href="$self->{'system'}->{'script_name'}?page=usernameRemind&amp;email=$email">Click here</a> )
				  . q(for a reminder of your user name to be sent to this address.),
				detail   => $detail,
				navbar   => 1,
				back_url => $self->{'system'}->{'script_name'}
			}
		);
		return 1;
	}
	return;
}

sub _bad_username {
	my ( $self, $user_name ) = @_;
	my @problems;
	my $length = length $user_name;
	if ( $length > 20 || $length < 4 ) {
		my $plural = $length == 1 ? q() : q(s);
		push @problems, qq(Username must be between 4 and 20 characters long - your is $length character$plural long.);
	}
	if ( $user_name =~ /[^A-Za-z0-9]/x ) {
		push @problems, q(Username contains non-alphanumeric (A-Z, a-z, 0-9) characters.);
	}
	my $invalid =
	  $self->{'datastore'}->run_query( 'SELECT user_name FROM invalid_usernames UNION SELECT user_name FROM users',
		undef, { fetch => 'col_arrayref' } );
	my %invalid = map { $_ => 1 } @$invalid;
	if ( $invalid{$user_name} ) {
		push @problems, q(Username is already registered. Site-wide accounts cannot use a user name )
		  . q(that is currently in use in any databases on the site.);
	}
	if (@problems) {
		local $" = q(<br />);
		$self->print_bad_status( { message => qq(@problems) } );
		return 1;
	}
	return;
}

sub _send_email {
	my ( $self, $data ) = @_;
	my $message =
		qq(An account has been set up for you on $self->{'config'}->{'domain'}\n\n)
	  . qq(Please log in with the following details in the next $self->{'validate_time'} minutes. The account )
	  . qq(will be removed if you do not log in within this time - if this happens you will need to re-register.\n\n)
	  . qq(You will be required to change your password when you first log in.\n\n)
	  . qq(Username: $data->{'user_name'}\n)
	  . qq(Password: $data->{'password'}\n\n)
	  . q(PLEASE NOTE: Once you have validated your account, you then need to register this with individual )
	  . qq(databases before you are able to log in to them.\n);
	if ( $self->{'config'}->{'registration_address'} ) {
		$message .= qq(\nYou can do this at $self->{'config'}->{'registration_address'}.);
	}
	my $transport = Email::Sender::Transport::SMTP->new(
		{ host => $self->{'config'}->{'smtp_server'} // 'localhost', port => $self->{'config'}->{'smtp_port'} // 25, }
	);
	my $domain         = $self->{'config'}->{'domain'}                  // DEFAULT_DOMAIN;
	my $sender_address = $self->{'config'}->{'automated_email_address'} // "no_reply\@$domain";
	my $email          = Email::MIME->create(
		attributes => {
			encoding => 'quoted-printable',
			charset  => 'UTF-8',
		},
		header_str => [
			To      => $data->{'email'},
			From    => $sender_address,
			Subject => "New $domain user account",
		],
		body_str => $message
	);
	eval {
		try_to_sendmail( $email, { transport => $transport } )
		  || $logger->error("Cannot send E-mail to  $data->{'email'}");
	};
	$logger->error($@) if $@;
	return;
}

sub _create_password {
	my ($self) = @_;

	#Avoid ambiguous characters (I, l, 1, O, 0)
	my @allowed_chars = qw(
	  A B C D E F G H J K L M N P Q R S T U V W X Y Z
	  a b c d e f g h j k m n p q r s t u v w x y z
	  1 2 3 4 5 6 7 8 9
	);
	my $password;
	$password .= @allowed_chars[ rand( scalar @allowed_chars ) ] foreach ( 1 .. 12 );
	return $password;
}

sub get_title {
	return 'User registration';
}

sub get_javascript {
	my ($self) = @_;
	my $buffer = << "END";
\$(function () {
	var textboxes = ["first_name","surname","affiliation"];
	\$.each(textboxes, function (i, val){
		\$("#" + val).bind("keyup", function(e) {
			capitalize(val,\$("#" + val).val());
			var code = e.keyCode || e.which;
			if (code != '9') {  //Tab not pressed
				\$("#" + val).unbind("keyup");
	    	}
		});
	});
});	
function capitalize(textboxid, str) {
      // string with alteast one character
      if (str && str.length >= 1)
      {       
          var firstChar = str.charAt(0);
          var remainingStr = str.slice(1);
          str = firstChar.toUpperCase() + remainingStr;
      }
      document.getElementById(textboxid).value = str;
  }

END
	return $buffer;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery noCache login);
	$self->{'validate_time'} =
	  BIGSdb::Utils::is_int( $self->{'config'}->{'new_account_validation_timeout_mins'} )
	  ? $self->{'config'}->{'new_account_validation_timeout_mins'}
	  : NEW_ACCOUNT_VALIDATION_TIMEOUT_MINS;
	$self->{'inactive_time'} =
	  BIGSdb::Utils::is_int( $self->{'config'}->{'inactive_account_removal_days'} )
	  ? $self->{'config'}->{'inactive_account_removal_days'}
	  : INACTIVE_ACCOUNT_REMOVAL_DAYS;
	return if !$self->{'config'}->{'site_user_dbs'};
	my $q = $self->{'cgi'};
	if ( $q->param('domain') ) {
		$self->{'system'}->{'db'} = $q->param('domain');
		$self->use_correct_user_database;
	}
	$self->{'breadcrumbs'} = [
		{
			label => 'Home',
			href  => '/'
		},
		{
			label => 'Registration'
		}
	];
	return;
}
1;
