#Written by Keith Jolley
#Copyright (c) 2010-2016, University of Oxford
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
use 5.010;
use parent qw(BIGSdb::Page);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);

sub print_content {
	my ($self) = @_;
	my $logger = get_logger('BIGSdb.Page');
	my $desc   = $self->get_title;
	say qq(<h1>$desc</h1>);
	say q(<div class="box" id="statusbad">);
	no warnings 'once';
	my $upload_limit = BIGSdb::Utils::get_nice_size($CGI::POST_MAX);
	my %error        = (
		missingXML    => q(Database description file does not exist!),
		invalidXML    => q(Invalid database description file specified!),
		invalidDbType => q(Invalid database type specified! Please set dbtype to either 'isolates' )
		  . q(or 'sequences' in the system attributes of the XML description file for this database.),
		invalidScriptPath        => q(You are attempting to access this database from an invalid script path.),
		invalidCurator           => q(You are not a curator for this database.),
		noConnect                => q(Cannot connect to database!),
		noAuth                   => q(Cannot connect to the authentication database!),
		noAuthenticationSet      => q(No authentication mechanism has been set in the database configuration!),
		invalidAuthenticationSet => q(An invalid authentication method has been set in the database configuration!),
		disableUpdates           => q(Database updates are currently disabled.),
		userNotAuthenticated     => q(You have been denied access by the server configuration.  Either your login )
		  . q(details are invalid or you are trying to connect from an unauthorized IP address.),
		accessDisabled => q(Your user account has been disabled.  If you believe this to be an error, )
		  . q(please contact the system administrator.),
		configAccessDenied => q(Your user account cannot access this database configuration.  If you believe )
		  . q(this to be an error, please contact the system administrator.),
		tooBig => q(You are attempting to upload too much data in one go.  )
		  . qq(Uploads are limited to a size of $upload_limit.)
	);

	if ( $self->{'error'} eq 'unknown' ) {
		my $function = $self->{'cgi'}->param('page');
		say q(<span class="warning_icon fa fa-thumbs-o-down fa-5x pull-left"></span><h2>Oops ...</h2>)
		  . qq(<p>Unknown function '$function' requested - either an incorrect link brought you )
		  . q(here or this functionality has not been implemented yet!</p>);
		$logger->info(qq(Unknown function '$function' specified in URL));
	} elsif ( $error{ $self->{'error'} } ) {
		my %show_warning = map { $_ => 1 } qw(userNotAuthenticated accessDisabled configAccessDenied);
		my $warning =
		  $show_warning{ $self->{'error'} }
		  ? q(<span class="warning_icon fa fa-exclamation-triangle fa-5x pull-left"></span>)
		  : q(<span class="warning_icon fa fa-thumbs-o-down fa-5x pull-left"></span><h2>Oops ...</h2>);
		say qq($warning<p>$error{$self->{'error'}}</p><div style="clear:both"></div>);
	} elsif ( $self->{'error'} eq 'noPrefs' ) {
		say q(<span class="warning_icon fa fa-thumbs-o-down fa-5x pull-left"></span><h2>Oops ...</h2>);
		if ( $self->{'fatal'} ) {
			say q(<p>The preference database can be reached but it appears to be misconfigured!</p>);
		} else {
			say q(<p>Cannot connect to the preference database!</p>);
		}
	} else {
		say q(<p>An unforeseen error has occurred - please contact the system administrator.</p>);
		$logger->error(q(Unforeseen error page displayed to user));
	}
	if ( $self->{'message'} ) {
		say qq(<p>$self->{'message'}</p>);
	}
	say q(</div>);
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	my %error = (
		unknown                  => "Unknown function - $desc",
		missingXML               => "Missing database configuration - $desc",
		invalidXML               => "Invalid database configuration - $desc",
		invalidDbType            => "Invalid database type - $desc",
		invalidScriptPath        => "Invalid script path - $desc",
		invalidCurator           => "Invalid curator - $desc",
		noConnect                => "Cannot connect to database - $desc",
		userNotAuthenticated     => "Access denied - $desc",
		noPrefs                  => "Preference database error - $desc",
		noAuthenticationSet      => "No authentication mechanism set - $desc",
		invalidAuthenticationSet => "Invalid authentication mechanism set - $desc",
		accessDisabled           => "Access disabled - $desc",
		configAccessDenied       => "Access denied - $desc",
		tooBig                   => "Upload file size too large - $desc"
	);
	return $error{ $self->{'error'} } if $error{ $self->{'error'} };
	return $desc;
}

sub initiate {
	my ($self) = @_;
	my $codes = {
		401 => '401 Unauthorized',
		403 => '403 Forbidden',
		404 => '404 Not Found',
		413 => '413 Request Entity Too Large',
		501 => '501 Not Implemented',
		500 => '500 Internal Server Error',
		503 => '503 Service Unavailable'
	};
	my $status = {
		unknown                  => $codes->{501},
		missingXML               => $codes->{404},
		invalidXML               => $codes->{500},
		invalidDbType            => $codes->{500},
		invalidScriptPath        => $codes->{403},
		invalidCurator           => $codes->{403},
		noConnect                => $codes->{503},
		userNotAuthenticated     => $codes->{401},
		noPrefs                  => $codes->{503},
		noAuthenticationSet      => $codes->{500},
		invalidAuthenticationSet => $codes->{500},
		accessDisabled           => $codes->{403},
		configAccessDenied       => $codes->{403},
		tooBig                   => $codes->{413}
	};
	if ( $status->{ $self->{'error'} } ) {
		$self->{'status'} = $status->{ $self->{'error'} };
	}
	return;
}
1;
