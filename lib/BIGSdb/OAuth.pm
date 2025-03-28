#Written by Keith Jolley
#Copyright (c) 2025, University of Oxford
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

package BIGSdb::OAuth;
use strict;
use warnings;
use 5.010;
use BIGSdb::Exceptions;
use Data::Random qw(rand_chars);
use JSON;
use Try::Tiny;
use LWP::UserAgent;
use HTTP::Request::Common;
use Net::OAuth 0.20;
$Net::OAuth::PROTOCOL_VERSION = Net::OAuth::PROTOCOL_VERSION_1_0A;

use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

sub new {    ## no critic (RequireArgUnpacking)
	my $class = shift;
	my $self  = {@_};
	bless( $self, $class );
	$self->_initiate;
	return $self;
}

sub _initiate {
	my ($self) = @_;
	my @required = qw(base_uri datastore db client_id client_secret access_token access_secret);
	my @missing;
	foreach (@required) {
		push @missing, $_ if !defined $self->{$_};
	}
	if (@missing) {
		local $" = q(, );
		BIGSdb::Exception::Authentication->throw("@missing not passed.");
	}
	$self->{'ua'} = LWP::UserAgent->new( agent => 'BIGSdb' );
	return;

}

sub _retrieve_tokens {
	my ($self) = @_;
	my $tokens = $self->{'datastore'}->run_query(
		'SELECT * FROM oauth_credentials WHERE (base_uri,consumer_key,access_token)=(?,?,?)',
		[ $self->{'base_uri'}, $self->{'client_id'}, $self->{'access_token'} ],
		{ fetch => 'row_hashref' }
	);
	$self->{$_} = $tokens->{$_} foreach (qw(session_token session_secret));
	my $error;
	if ( !defined $tokens->{'session_token'} || !defined $tokens->{'session_secret'} ) {
		try {
			$self->_get_new_session_token;
		} catch {
			if ( $_->isa('BIGSdb::Exception::Authentication') ) {
				if ( $_ =~ /access\stoken/x ) {
					$logger->error('Invalid access token.');
				} else {
					$logger->error("OAuth exception: $_");
				}
			} else {
				$logger->error($_);
			}
			$error = 1;
		};
	}

	return $error;
}

sub test_authentication {
	my ($self) = @_;
	return 1 if $self->_retrieve_tokens;
	my $error;
	try {
		$self->get_route( $self->{'base_uri'} );
	} catch {
		if ( $_->isa('BIGSdb::Exception::Authentication') ) {
			if ( $_ =~ /Signature\sverification/x ) {
				$logger->error('Signature verification failed.');
			} else {
				$logger->error("OAuth exception: $_");
			}
		} else {
			$logger->error($_);
		}
		$error = 1;
	};
	return $error;
}

sub get_route {
	my ( $self, $uri, $options ) = @_;
	$options->{'method'} //= 'GET';
	$self->_retrieve_tokens;
	my $request = Net::OAuth->request('protected resource')->new(
		consumer_key     => $self->{'client_id'},
		consumer_secret  => $self->{'client_secret'},
		token            => $self->{'session_token'},
		token_secret     => $self->{'session_secret'},
		request_url      => $uri,
		request_method   => $options->{'method'},
		signature_method => 'HMAC-SHA1',
		timestamp        => time,
		nonce            => join( '', rand_chars( size => 16, set => 'alphanumeric' ) ),
	);
	$request->sign;
	BIGSdb::Exception::Authentication->throw('Cannot verify signature') unless $request->verify;
	my $res;
	if ( $options->{'method'} eq 'POST' ) {
		$res = $self->{'ua'}->post( $request->to_url, Content => ( $options->{'payload'} // q() ) );
	} else {
		$res = $self->{'ua'}->get( $request->to_url );
	}
	if ( $res->code == 429 ) {
		return $res;
	}
	if ( $options->{'non_json'} ) {
		return $res;
	}
	my $decoded_json;
	eval { $decoded_json = decode_json( $res->content ) };
	if ($@) {
		$logger->error( $res->content );
		return $res;
	}
	BIGSdb::Exception::Data->throw('Invalid JSON') if ref $decoded_json ne 'HASH';
	if ( ( $decoded_json->{'message'} // q() ) =~ /Client\ is\ unauthorized/x ) {
		BIGSdb::Exception::Authentication->throw('Access denied - client is unauthorized.');
	}
	if ( ( $decoded_json->{'status'} // q() ) eq '401' ) {
		if ( $options->{'retry'} ) {
			BIGSdb::Exception::Authentication->throw('Invalid session token - still failing after refresh.');
		}
		$logger->info('Invalid session token, requesting new one.');
		$self->_get_new_session_token;
		$options->{'retry'} = 1;
		return $self->get_route( $uri, $options );
	}
	return $res;
}

sub _get_new_session_token {
	my ($self) = @_;
	my $request = Net::OAuth->request('protected resource')->new(
		consumer_key     => $self->{'client_id'},
		consumer_secret  => $self->{'client_secret'},
		token            => $self->{'access_token'},
		token_secret     => $self->{'access_secret'},
		request_url      => "$self->{'base_uri'}/oauth/get_session_token",
		request_method   => 'GET',
		signature_method => 'HMAC-SHA1',
		timestamp        => time,
		nonce            => join( '', rand_chars( size => 16, set => 'alphanumeric' ) ),
	);
	$request->sign;
	BIGSdb::Exception::Authentication->throw('Cannot verify signature') unless $request->verify;
	my $res;
	eval { $res = $self->{'ua'}->request( GET $request->to_url, Content_Type => 'application/json' ); };
	my $decoded_json = decode_json( $res->content );
	if ( $res->is_success ) {
		my $session_response = Net::OAuth->response('access token')->from_hash($decoded_json);
		eval {
			$self->{'db'}->do(
				'INSERT INTO oauth_credentials (base_uri,consumer_key,consumer_secret,access_token,access_secret,'
				  . 'session_token,session_secret,curator,date_entered,datestamp) VALUES (?,?,?,?,?,?,?,?,?,?) '
				  . 'ON CONFLICT (base_uri) DO UPDATE SET (consumer_key,consumer_secret,access_token,access_secret,'
				  . 'session_token,session_secret,curator,datestamp)=(?,?,?,?,?,?,?,?)',
				undef,
				$self->{'base_uri'},
				$self->{'client_id'},
				$self->{'client_secret'},
				$self->{'access_token'},
				$self->{'access_secret'},
				$session_response->token,
				$session_response->token_secret,
				0,
				'now',
				'now',
				$self->{'client_id'},
				$self->{'client_secret'},
				$self->{'access_token'},
				$self->{'access_secret'},
				$session_response->token,
				$session_response->token_secret,
				0,
				'now'
			);
		};
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
		}
		$self->{'session_token'}  = $session_response->token;
		$self->{'session_secret'} = $session_response->token_secret;
		return $session_response;
	} else {
		my $error = $res->as_string;
		if ( $error =~ /Unrecognized\sclient/x ) {
			BIGSdb::Exception::Authentication->throw("Invalid client for $self->{'base_uri'}");
		} elsif ( $error =~ /Invalid\saccess\stoken/x ) {
			BIGSdb::Exception::Authentication->throw("Invalid access token for $self->{'base_uri'}");
		} else {
			BIGSdb::Exception::Authentication->throw($error);
		}
	}
	return;
}

1;
