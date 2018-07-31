#!/usr/bin/env perl
#Obtain API access token for configuring remote contig manager
#Written by Keith Jolley
#Copyright (c) 2017-2018, University of Oxford
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
use strict;
use warnings;
use 5.010;
use Net::OAuth 0.20;
$Net::OAuth::PROTOCOL_VERSION = Net::OAuth::PROTOCOL_VERSION_1_0A;
use HTTP::Request::Common;
use LWP::UserAgent;
use JSON qw(encode_json decode_json);
use Data::Random qw(rand_chars);
my $ua = LWP::UserAgent->new;
main();

sub main {
	print q(Enter consumer key: );
	my $consumer_key = <>;
	chomp $consumer_key;
	print q(Enter consumer secret: );
	my $consumer_secret = <>;
	chomp $consumer_secret;
	print q(Enter API database URI: );
	my $rest_uri = <>;
	chomp $rest_uri;
	print q(Enter web database URL: );
	my $web_uri = <>;
	chomp $web_uri;
	my $request_token = get_request_token( $consumer_key, $consumer_secret, $rest_uri );
	my $access_token = get_access_token(
		$consumer_key, $consumer_secret,
		$request_token->{'token'},
		$request_token->{'token_secret'},
		$web_uri, $rest_uri
	);
	say q(Access Token:        ).$access_token->token;
	say q(Access Token Secret: ).$access_token->token_secret;
	say qq(\nThis access token will not expire but may be revoked);
	say q(by the user or the service provider. It may be used to);
	say q(obtain temporary session tokens.);
	return;
}

sub get_request_token {
	my ( $consumer_key, $consumer_secret, $rest_uri ) = @_;
	my $request = Net::OAuth->request('request token')->new(
		consumer_key     => $consumer_key,
		consumer_secret  => $consumer_secret,
		request_url      => "$rest_uri/oauth/get_request_token",
		request_method   => 'GET',
		signature_method => 'HMAC-SHA1',
		timestamp        => time,
		nonce            => join( '', rand_chars( size => 16, set => 'alphanumeric' ) ),
		callback         => 'oob'
	);
	$request->sign;

	#say $request->signature_base_string;
	die "COULDN'T VERIFY! Check OAuth parameters.\n" unless $request->verify;
	print q(Getting request token...);
	my $res = $ua->request( GET $request->to_url, Content_Type => 'application/json', );
	my $decoded_json = decode_json( $res->content );
	my $request_response;
	if ( $res->is_success ) {
		say q(Success.);
		$request_response = Net::OAuth->response('request token')->from_hash($decoded_json);
		return $request_response;
	} else {
		say q(Failed.);
		exit;
	}
}

sub get_access_token {
	my ( $consumer_key, $consumer_secret, $request_token, $request_secret, $web_uri, $rest_uri ) = @_;
	say qq(\nNow log in at ${web_uri}&page=authorizeClient&oauth_token=$request_token\n)
	  . q(to obtain a verification code.);
	print qq(\nPlease enter verification code: );
	my $verifier = <>;
	chomp $verifier;
	my $request = Net::OAuth->request('access token')->new(
		consumer_key     => $consumer_key,
		consumer_secret  => $consumer_secret,
		token            => $request_token,
		token_secret     => $request_secret,
		verifier         => $verifier,
		request_url      => "$rest_uri/oauth/get_access_token",
		request_method   => 'GET',
		signature_method => 'HMAC-SHA1',
		timestamp        => time,
		nonce            => join( '', rand_chars( size => 16, set => 'alphanumeric' ) ),
	);
	$request->sign;
	die "COULDN'T VERIFY! Check OAuth parameters.\n" unless $request->verify;
	print qq(\nGetting access token...);
	my $res = $ua->request( GET $request->to_url, Content_Type => 'application/json' );
	my $decoded_json = decode_json( $res->content );

	if ( $res->is_success ) {
		say q(Success.);
		my $access_response = Net::OAuth->response('access token')->from_hash($decoded_json);
		return $access_response;
	} else {
		say q(Failed.);
		exit;
	}
}
