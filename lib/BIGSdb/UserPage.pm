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
	$self->_show_user_roles;
	if ( $self->{'curate'} ) {
		$self->_show_admin_roles;
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
		say q(</div>);
	}
	return;
}

sub _registrations {
	my ($self) = @_;
	my $buffer = q();
	my $registered_configs =
	  $self->{'datastore'}->run_query( 'SELECT dbase_config FROM registered_resources ORDER BY dbase_config',
		undef, { fetch => 'col_arrayref' } );
	return $buffer;
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

sub _import_dbase_config {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	return q() if !$self->{'permissions'}->{'import_dbase_configs'};
	if ( $q->param('add') ) {
		foreach my $config ( $q->param('available') ) {
			next if $self->_is_config_registered($config);
			eval { $self->{'db'}->do( 'INSERT INTO registered_resources (dbase_config) VALUES (?)', undef, $config ) };
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
1;
