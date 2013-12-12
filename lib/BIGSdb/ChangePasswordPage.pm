#Written by Keith Jolley
#Copyright (c) 2010-2013, University of Oxford
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
use parent qw(BIGSdb::LoginMD5);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return $self->{'cgi'}->param('page') eq 'changePassword' ? "Change password - $desc" : "Set user password - $desc";
}

sub print_content {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $continue = 1;
	say $q->param('page') eq 'changePassword' ? "<h1>Change password</h1>" : "<h1>Set user password</h1>";
	if ( $self->{'system'}->{'authentication'} ne 'builtin' ) {
		say "<div class=\"box\" id=\"statusbad\"><p>This database uses external means of authentication and the password "
		  . "can not be changed	from within the web application.</p></div>";
		return;
	} elsif ( $q->param('page') eq 'setPassword' && !$self->{'permissions'}->{'set_user_passwords'} && !$self->is_admin ) {
		say "<div class=\"box\" id=\"statusbad\"><p>You are not allowed to change other users' passwords.</p></div>";
		return;
	} elsif ( $q->param('sent') && $q->param('page') eq 'setPassword' && !$q->param('user') ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Please select a user.</p></div>";
		$continue = 0;
	}
	if ( $continue && $q->param('sent') && $q->param('existing_password') ) {
		my $further_checks = 1;
		if ( $q->param('page') eq 'changePassword' ) {

			#make sure user is only attempting to change their own password (user parameter is passed as a hidden
			#parameter and could be changed)
			if ( $self->{'username'} ne $q->param('user') ) {
				say "<div class=\"box\" id=\"statusbad\"><p>You are attempting to change another user's password.  You are not "
				  . "allowed to do that!</p></div>";
				$further_checks = 0;
			} else {

				#existing password not set when admin setting user passwords
				my $stored_hash = $self->_get_password_hash( $self->{'username'} );
				if ( $stored_hash ne $q->param('existing_password') ) {
					say "<div class=\"box\" id=\"statusbad\"><p>Your existing password was entered incorrectly. The password has not "
					  . "been updated.</p></div>";
					$further_checks = 0;
				}
			}
		}
		if ($further_checks) {
			if ( $q->param('new_length') < 6 ) {
				say "<div class=\"box\" id=\"statusbad\"><p>The password is too short and has not been updated.  It must be at least 6 "
				  . "characters long.</p></div>";
			} elsif ( $q->param('new_password1') ne $q->param('new_password2') ) {
				say "<div class=\"box\" id=\"statusbad\"><p>The password was not re-typed the same as the first time.</p></div>";
			} else {
				my $username = $q->param('page') eq 'changePassword' ? $self->{'username'} : $q->param('user');
				if ( $self->set_password_hash( $username, $q->param('new_password1') ) ) {
					say "<div class=\"box\" id=\"resultsheader\"><p>"
					  . ( $q->param('page') eq 'changePassword' ? "Password updated ok." : "Password set for user '$username'." )
					  . "</p>";
				} else {
					say "<div class=\"box\" id=\"resultsheader\"><p>Password not updated.  Please check with the system administrator.</p>";
				}
				say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Return to index</a></p>\n</div>";
				return;
			}
		}
	}
	say "<div class=\"box\" id=\"queryform\">";
	say "<p>Please enter your existing and new passwords.</p>\n" if $q->param('page') eq 'changePassword';
	say "<noscript><p class=\"highlight\">Please note that Javascript must be enabled in order to login.  Passwords are encrypted using "
	  . "Javascript prior to transmitting to the server.</p></noscript>";
	say $q->start_form( -onSubmit => "existing_password.value=existing.value; existing.value='';new_length.value=new1.value.length;"
	  . "new_password1.value=new1.value;new1.value='';new_password2.value=new2.value;new2.value='';"
	  . "existing_password.value=calcMD5(existing_password.value+user.value);"
	  . "new_password1.value=calcMD5(new_password1.value+user.value);"
	  . "new_password2.value=calcMD5(new_password2.value+user.value);"
	  . "return true"
	);
	say "<table>";
	if ( $q->param('page') eq 'changePassword' ) {
		say "<tr><td style=\"text-align:right\">Existing password: </td><td>";
		say $q->password_field( -name => 'existing' );
	} else {
		my $sql = $self->{'db'}->prepare("SELECT user_name, first_name, surname FROM users WHERE id>0 ORDER BY lower(surname)");
		eval { $sql->execute };
		$logger->error($@) if $@;
		my ( @users, %labels );
		push @users, '';
		while ( my ( $username, $first_name, $surname ) = $sql->fetchrow_array ) {
			push @users, $username;
			$labels{$username} = "$surname, $first_name ($username)";
		}
		say "<tr><td style=\"text-align:right\">User: </td><td>";
		say $q->popup_menu( -name => 'user', -values => [@users], -labels => \%labels );
		say $q->hidden( 'existing', '' );
	}
	say "</td></tr>\n<tr><td style=\"text-align:right\">New password: </td><td>";
	say $q->password_field( -name => 'new1' );
	say "</td></tr>\n<tr><td style=\"text-align:right\">Retype password: </td><td>";
	say $q->password_field( -name => 'new2' );
	say "</td></tr>\n<tr><td colspan=\"2\" style=\"text-align:right\">";
	say $q->submit( -class => 'submit', -label => 'Set password' );
	say "</td></tr>";
	say "</table>";
	$q->param( $_, '' ) foreach qw (existing_password new_password1 new_password2 new_length);
	$q->param( 'user', $self->{'username'} ) if $q->param('page') eq 'changePassword';
	$q->param( 'sent', 1 );
	say $q->hidden($_) foreach qw (db page existing_password new_password1 new_password2 new_length user sent);
	say $q->end_form;
	say "</div>\n";
	return;
}
1;
