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
package BIGSdb::REST::Routes::OAuth;
use strict;
use warnings;
use 5.010;
use Net::OAuth;
$Net::OAuth::PROTOCOL_VERSION = Net::OAuth::PROTOCOL_VERSION_1_0A;
use Dancer2 appname                => 'BIGSdb::REST::Interface';
use constant REQUEST_TOKEN_EXPIRES => 3600;
use constant REQUEST_TOKEN_TIMEOUT => 600;
any [qw(get post)] => '/db/:db/oauth/get_request_token' => sub {
	my $self   = setting('self');
	my $params = params;
	my $db     = param('db');
	my $consumer_secret =
	  $self->{'datastore'}
	  ->run_query( "SELECT client_secret FROM clients WHERE client_id=?", param('oauth_consumer_key'), { db => $self->{'auth_db'} } );
	if ( !$consumer_secret ) {
		send_error( "Unrecognized client", 400 );
	}
	my $request_params = {};
	$request_params->{$_} = param($_)
	  foreach qw(oauth_consumer_key oauth_signature_method oauth_timestamp oauth_nonce oauth_callback oauth_version oauth_signature);
	my $request = eval {
		Net::OAuth->request('request token')->from_hash(
			$request_params,
			request_method  => request->method,
			request_url     => uri_for("/db/$db/oauth/get_request_token")->as_string,
			consumer_secret => $consumer_secret
		);
	};
	if ($@) {
		warn $@;
		if ( $@ =~ /Missing required parameter \'(\w+?)\'/ ) {
			send_error( "Invalid token request. Missing required parameter: $1", 400 );
		} else {
			$self->{'logger'}->error($@);
			send_error( "Invalid token request", 400 );
		}
	}
	$self->{'logger'}->debug( "Request string: " . $request->signature_base_string );
	if ( !$request->verify ) {
		send_error( "Signature verification failed", 400 );
	}
	if ( abs( $request->timestamp - time ) > REQUEST_TOKEN_TIMEOUT ) {
		send_error( "Request timestamp more than " . REQUEST_TOKEN_TIMEOUT . " seconds from current time.", 400 );
	}
	my $request_repeated = $self->{'datastore'}->run_query(
		"SELECT EXISTS(SELECT * FROM request_tokens WHERE (nonce,timestamp)=(?,?))",
		[ param('oauth_nonce'), param('oauth_timestamp') ],
		{ db => $self->{'auth_db'} }
	);
	if ($request_repeated) {
		send_error( "Request with same nonce and timestamp already made", 400 );
	}
	my $token        = BIGSdb::Utils::random_string(32);
	my $token_secret = BIGSdb::Utils::random_string(32);
	eval {
		$self->{'auth_db'}->do("DELETE FROM request_tokens WHERE start_time<?",undef, time - REQUEST_TOKEN_EXPIRES);
		$self->{'auth_db'}->do(
			"INSERT INTO request_tokens (token,secret,client_id,nonce,timestamp,start_time) VALUES (?,?,?,?,?,?)",
			undef, $token, $token_secret, param('oauth_consumer_key'),
			param('oauth_nonce'), param('oauth_timestamp'),
			time
		);
	};
	if ($@) {
		$self->{'logger'}->error($@);
		$self->{'auth_db'}->rollback;
		send_error( "Error creating request token", 400 );
	}
	$self->{'auth_db'}->commit;
	return { oauth_token => $token, oauth_token_secret => $token_secret, oauth_callback_confirmed => 'true' };
};
1;
