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
use BIGSdb::Login;
use Error qw(:try);
my $logger = get_logger('BIGSdb.Application_Authentication');

sub print_content {
	my ($self) = @_;
	say q(<h1>Bacterial Isolate Genome Sequence Database (BIGSdb)</h1>);
	if ( $self->{'config'}->{'site_user_dbs'} ) {
		$self->_site_account;
		return;
	}
	$self->print_about_bigsdb;
	return;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery noCache);
	return if !$self->{'config'}->{'site_user_dbs'};

	#We may be logged in to a different user database than the one containing
	#the logged in user details. Make sure the DBI object is set to correct
	#database.
	my $att = {
		dbase_name => $self->{'system'}->{'db'},
		host       => $self->{'system'}->{'host'},
		port       => $self->{'system'}->{'port'},
		user       => $self->{'system'}->{'user'},
		password   => $self->{'system'}->{'password'}
	};
	try {
		$self->{'db'} = $self->{'dataConnector'}->get_connection($att);
	}
	catch BIGSdb::DatabaseConnectionException with {
		$logger->error("Cannot connect to database '$self->{'system'}->{'db'}'");
	};
	$self->{'datastore'}->change_db( $self->{'db'} );
	$self->{'permissions'} = $self->{'datastore'}->get_permissions( $self->{'username'} );
	return;
}

sub _site_account {
	my ($self) = @_;
	my $user_name = $self->{'username'};
	if ($user_name) {
		my $user_info = $self->{'datastore'}->get_user_info_from_username($user_name);
		say qq(<p>Logged in: $user_info->{'first_name'} $user_info->{'surname'} ($user_name)</p>);
	}
	return;
}
1;
