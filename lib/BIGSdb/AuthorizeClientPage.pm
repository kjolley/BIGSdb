#Written by Keith Jolley
#Copyright (c) 2015, University of Oxford
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
package BIGSdb::AuthorizeClientPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant REQUEST_TOKEN_EXPIRES => 3600;

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery noCache);
	return;
}

sub print_content {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $token_id = $q->param('oauth_token');
	say q(<h1>Authorize client software to access your account</h1>);
	if ( $self->{'system'}->{'authentication'} ne 'builtin' ) {
		say q(<div class="box" id="statusbad"><p>This database does not use built-in authentication.  You cannot )
		  . q(currently authorize third-party applications.</p></div>);
		return;
	} elsif ( $q->param('modify') ) {
		$self->_modify_authorization;
		return;
	} elsif ( !$token_id ) {
		say q(<div class="box" id="statusbad"><p>No request token specified.</p></div>);
		return;
	}
	my $token = $self->{'datastore'}->run_query( 'SELECT * FROM request_tokens WHERE token=?',
		$token_id, { db => $self->{'auth_db'}, fetch => 'row_hashref' } );
	if ( !$token ) {
		say q(<div class="box" id="statusbad"><p>Invalid token submitted.  )
		  . q(It is possible that the token has expired.</p></div>);
		return;
	} elsif ( time - $token->{'start_time'} > REQUEST_TOKEN_EXPIRES ) {
		say q(<div class="box" id="statusbad"><p>The request token has expired.</p></div>);
		return;
	} elsif ( $token->{'verifier'} ) {
		say q(<div class="box" id="statusbad"><p>The request token has already been redeemed.</p></div>);
		return;
	}
	my $client = $self->{'datastore'}->run_query( 'SELECT * FROM clients WHERE client_id=?',
		$token->{'client_id'}, { db => $self->{'auth_db'}, fetch => 'row_hashref' } );
	if ( !$client ) {
		say q(<div class="box" id="statusbad"><p>The client is not recognized.</p></div>);
		$logger->error("Client $token->{'client_id'} does not exist.  This should not be possible.")
		  ;    #Token is linked to client
		return;
	} elsif (
		!$self->_can_client_access_database(
			$token->{'client_id'},
			$client->{'default_permission'},
			$self->{'system'}->{'db'}
		)
	  )
	{
		say q(<div class="box" id="statusbad"><p>The client does not have permission to )
		  . q(access this resource.</p></div>);
		return;
	}
	if ( $q->param('authorize') ) {
		$self->_authorize_token($client);
		return;
	}
	say q(<div class="box" id="queryform"><div class="scrollable"><p>Do you wish for the following )
	  . q(application to access data on your behalf?</p>);
	say q(<fieldset style="float:left"><legend>Application</legend>);
	say qq(<p><b>$client->{'application'} );
	say qq(version $client->{'version'}) if $client->{'version'};
	say q(</b></p></fieldset>);
	my $desc = $self->{'system'}->{'description'};
	if ($desc) {
		say q(<fieldset style="float:left"><legend>Resource</legend>);
		say qq(<b>$desc</b>);
		say q(</fieldset>);
	}
	say $q->start_form;
	$q->param( authorize => 1 );
	$self->print_action_fieldset( { submit_label => 'Authorize', reset_label => 'Cancel', page => 'index' } );
	say $q->hidden($_) foreach qw(db page oauth_token authorize);
	say $q->end_form;
	say qq(<p>You will be able to <a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . q(page=authorizeClient&amp;modify=1">revoke access for this application</a> at any time.</p>);
	say q(</div></div>);
	return;
}

sub _authorize_token {
	my ( $self, $client ) = @_;
	my $q        = $self->{'cgi'};
	my $verifier = BIGSdb::Utils::random_string(8);
	eval {
		$self->{'auth_db'}->do(
			'UPDATE request_tokens SET (username,dbase,verifier,start_time)=(?,?,?,?) WHERE token=?',
			undef, $self->{'username'}, $self->{'system'}->{'db'},
			$verifier, time, $q->param('oauth_token')
		);
	};
	if ($@) {
		say q(<div class="box" id="statusbad"><p>Token could not be authorized.</p></div>);
		$logger->error($@);
		$self->{'auth_db'}->rollback;
	} else {
		say q(<div class="box" id="resultspanel">);
		my $version = $client->{'version'} ? " version $client->{'version'} " : '';
		my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
		say qq(<p>You have authorized <b>$client->{'application'}$version</b> to access <b>$desc</b> )
		  . q(on your behalf.</p>);
		say qq(<p>Enter the following verification code when asked by $client->{'application'}.</p>);
		say qq(<p><b>Verification code: $verifier</b></p>);
		say q(<p>This code is valid for ) . ( REQUEST_TOKEN_EXPIRES / 60 ) . q( minutes.</p>);
		say qq(<p>You will be able to <a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . q(page=authorizeClient&amp;modify=1">revoke access for this application</a> at any time.</p>);
		say q(</div>);
		$self->{'auth_db'}->commit;
	}
	return;
}

sub _can_client_access_database {
	my ( $self, $client_id, $default_permission, $dbase ) = @_;
	my $authorize = $self->{'datastore'}->run_query(
		'SELECT authorize FROM client_permissions WHERE (client_id,dbase)=(?,?)',
		[ $client_id, $dbase ],
		{ db => $self->{'auth_db'} }
	);
	if ( $default_permission eq 'allow' ) {
		return ( !$authorize || $authorize eq 'allow' ) ? 1 : 0;
	} else {    #default deny
		return ( !$authorize || $authorize eq 'deny' ) ? 0 : 1;
	}
}

sub _modify_authorization {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('submit') ) {
		my $known_clients = $self->{'datastore'}->run_query( 'SELECT * FROM clients ORDER BY application,version',
			undef, { db => $self->{'auth_db'}, fetch => 'all_arrayref', slice => {} } );
		my @revoked;
		foreach my $client (@$known_clients) {
			next if !$q->param( $client->{'client_id'} );
			eval {
				$self->{'auth_db'}->do( 'DELETE FROM access_tokens WHERE (username,client_id)=(?,?)',
					undef, $self->{'username'}, $client->{'client_id'} );
			};
			if ($@) {
				$logger->error($@);
				$self->{'auth_db'}->rollback;
			} else {
				$client->{'version'} //= '';
				push @revoked, "$client->{'application'} $client->{'version'}";
				$self->{'auth_db'}->commit;
			}
		}
		if (@revoked) {
			my $plural = @revoked == 1 ? '' : 's';
			local $" = '</li><li>';
			say q(<div class="box" id="resultsheader"><p>You have revoked access to the following )
			  . qq(application$plural:</p><ul><li>@revoked</li></ul></div>);
		}
	}
	my $clients = $self->{'datastore'}->run_query(
		'SELECT * FROM clients WHERE client_id IN (SELECT client_id FROM access_tokens '
		  . 'WHERE (username,dbase)=(?,?)) ORDER BY application',
		[ $self->{'username'}, $self->{'system'}->{'db'} ],
		{ db => $self->{'auth_db'}, fetch => 'all_arrayref', slice => {} }
	);
	if ( !@$clients ) {
		say q(<div class="box" id="resultspanel"><p>You have not authorized any application )
		  . q(to access your resources.</p></div> );
		return;
	}
	say q(<div class="box" id="resultstable"><div class="scrollable">);
	say q(<p>You have authorized the following applications to access resources on your behalf.  )
	  . q(Select any whose permissions you would like to revoke.</p>);
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Applications</legend>);
	say q(<table class="resultstable"><tr><th>Application</th><th>Version</th><th>Revoke</th></tr>);
	my $td = 1;
	foreach my $client (@$clients) {
		$client->{'version'} //= '-';
		say qq(<tr class="td$td"><td>$client->{'application'}</td><td>$client->{'version'}</td><td>);
		say $q->checkbox( -name => $client->{'client_id'}, -label => '' );
		say q(</td></tr>);
	}
	say q(</table></fieldset>);
	$self->print_action_fieldset( { modify => 1, submit_label => 'Revoke' } );
	say $q->hidden($_) foreach qw(db page modify);
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Authorize third-party client - $desc";
}
1;
