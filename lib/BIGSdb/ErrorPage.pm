#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
package BIGSdb::ErrorPage;
use strict;
use warnings;
use base qw(BIGSdb::Page);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);

sub print_content {
	my ($self)    = @_;
	my $logger    = get_logger('BIGSdb.Page');
	my $desc      = $self->get_title;
	my $show_oops = (any {$self->{'error'} eq $_} qw (userNotAuthenticated accessDisabled)) ? 0 : 1;
	print "<h1>$desc</h1>\n";
	print "<p style=\"font-size:5em; color:#A0A0A0; padding-top:1em\">Ooops ...</p>\n" if $show_oops;
	print "<div class=\"box\" id=\"statusbad\">\n";

	if ( $self->{'error'} eq 'unknown' ) {
		my $function = $self->{'cgi'}->param('page');
		print
"<p>Unknown function '$function' requested - either an incorrect link brought you here or this functionality has not been implemented yet!</p>";
		$logger->info("Unknown function '$function' specified in URL");
	} elsif ( $self->{'error'} eq 'invalidXML' ) {
		print "<p>Invalid (or no) database description file specified!</p>";
	} elsif ( $self->{'error'} eq 'invalidDbType' ) {
		print
"<p>Invalid database type specified! Please set dbtype to either 'isolates' or 'sequences' in the system attributes of the XML description file for this database.</p>";
	} elsif ( $self->{'error'} eq 'invalidScriptPath' ) {
		print "<p>You are attempting to access this database from an invalid script path.</p>";
	} elsif ( $self->{'error'} eq 'invalidCurator' ) {
		print "<p>You are not a curator for this database.</p>";
	} elsif ( $self->{'error'} eq 'noConnect' ) {
		print "<p>Can not connect to database!</p>";
	} elsif ( $self->{'error'} eq 'noAuth' ) {
		print "<p>Can not connect to the authentication database!</p>";
	} elsif ( $self->{'error'} eq 'noPrefs' ) {
		if ( $self->{'fatal'} ) {
			print "<p>The preference database can be reached but it appears to be misconfigured!</p>";
		} else {
			print "<p>Can not connect to the preference database!</p>";
		}
	} elsif ( $self->{'error'} eq 'userAuthenticationFiles' ) {
		print "<p>Can not open the user authentication database!</p>";
	} elsif ( $self->{'error'} eq 'noAuthenticationSet' ) {
		print "<p>No authentication mechanism has been set in the database configuration!</p>";
	} elsif ( $self->{'error'} eq 'disableUpdates' ) {
		print "<p>Database updates are currently disabled.</p>";
		print "<p>$self->{'message'}</p>" if $self->{'message'};
	} elsif ( $self->{'error'} eq 'userNotAuthenticated' ) {
		print "<p>You have been denied access by the server configuration.  Either your login details are
		invalid or you are trying to connect from an unauthorized IP address.</p>";
		$self->print_warning_sign;
	} elsif ( $self->{'error'} eq 'accessDisabled' ) {
		print "<p>Your user account has been disabled.  If you believe this to be an error, please contact
		the system administrator.</p>";
		$self->print_warning_sign;
	} else {
		print "<p>An unforeseen error has occurred - please contact the system administrator.</p>";
		$logger->error("Unforeseen error page displayed to user");
	}
	print "</div>\n";
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Unknown function - $desc" if ( $self->{'error'} eq 'unknown' );
	return "Invalid XML - $desc"                     if $self->{'error'} eq 'invalidXML';
	return "Invalid database type - $desc"           if $self->{'error'} eq 'invalidDbType';
	return "Invalid script path - $desc"             if $self->{'error'} eq 'invalidScriptPath';
	return "Invalid curator - $desc"                 if $self->{'error'} eq 'invalidCurator';
	return "Can not connect to database - $desc"     if $self->{'error'} eq 'noConnect';
	return "Access denied - $desc"                   if $self->{'error'} eq 'userNotAuthenticated';
	return "Preference database error - $desc"       if $self->{'error'} eq 'noPrefs';
	return "No authentication mechanism set - $desc" if $self->{'error'} eq 'noAuthenticationSet';
	return "Access disabled - $desc"                 if $self->{'error'} eq 'accessDisabled';
	return $desc;
}
1;
