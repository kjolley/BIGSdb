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
package BIGSdb::ContigManager;
use strict;
use warnings;
use 5.010;
use BIGSdb::Exceptions;
use LWP::UserAgent;
use HTTP::Request::Common;
use Net::OAuth 0.20;
$Net::OAuth::PROTOCOL_VERSION = Net::OAuth::PROTOCOL_VERSION_1_0A;
use JSON;
use Data::Random qw(rand_chars);
use Digest::MD5;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Application_Authentication');

sub new {
	my ( $class, @atr ) = @_;
	my $self = {@atr};
	bless( $self, $class );
	$self->{'ua'} = LWP::UserAgent->new( agent => 'BIGSdb' );
	$logger->info('Remote contig manager set up.');
	return $self;
}

sub set_seqbin_table {
	my ( $self, $table ) = @_;
	$self->{'seqbin_table'} = $table;
	return;
}

#Faster method to retrieve multiple contigs without extended metadata.
#This checks the isolate URI from the first retrieved contig and if it
#contains a URI to contigs_fasta will download all contigs in one call.
sub get_remote_contigs_by_list {
	my ( $self, $uri_list ) = @_;
	my $contigs = {};
	return $contigs if !@$uri_list;
	my %batch_seqs;
	while (@$uri_list) {
		my $uri = shift @$uri_list;
		( my $contig_route = $uri ) =~ s/\/\d+$//x;
		if ( $batch_seqs{$uri} ) {
			$contigs->{$uri} = $batch_seqs{$uri};
			next;
		}
		my $contig = $self->get_remote_contig($uri);
		if ( $contig->{'sequence'} ) {
			$contigs->{$uri} = $contig->{'sequence'};
			if ( $contig->{'isolate_id'} ) {
				my $isolate_record = $self->get_remote_isolate( $contig->{'isolate_id'} );
				if ( $isolate_record->{'sequence_bin'}->{'contigs_fasta'} ) {
					my $fasta = $self->get_remote_fasta( $isolate_record->{'sequence_bin'}->{'contigs_fasta'} );
					eval {
						my $seqs = BIGSdb::Utils::read_fasta( \$fasta );
						foreach my $seqbin_id ( keys %$seqs ) {
							my $contig_uri = "$contig_route/$seqbin_id";
							$batch_seqs{$contig_uri} = $seqs->{$seqbin_id};
						}
					};
					$logger->error($@) if $@;
				}
			}
		}
	}
	return $contigs;
}

sub update_remote_contig_length {
	my ( $self, $uri, $length ) = @_;
	eval { $self->{'db'}->do( 'UPDATE remote_contigs SET length=? WHERE uri=?', undef, $length, $uri ); };
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub update_isolate_remote_contig_lengths {
	my ( $self, $isolate_id ) = @_;
	my $seqbin = $self->{'seqbin_table'} // 'sequence_bin';
	my $qry = "SELECT r.uri,r.length FROM $seqbin s JOIN remote_contigs r ON "
	  . 's.id=r.seqbin_id WHERE s.isolate_id=? AND remote_contig';
	my $remote_contigs = $self->{'datastore'}->run_query( $qry, $isolate_id,
		{ fetch => 'all_arrayref', slice => {}, cache => 'ContigManager::update_isolate_remote_contig_lengths' } );
	my $uri_list = [];
	foreach my $contig (@$remote_contigs) {
		next if $contig->{'length'};
		push @$uri_list, $contig->{'uri'};
	}
	return if !@$uri_list;
	my $contigs = $self->get_remote_contigs_by_list($uri_list);
	foreach my $contig (@$remote_contigs) {
		$self->update_remote_contig_length( $contig->{'uri'}, length( $contigs->{ $contig->{'uri'} } ) );
	}
	return;
}

sub get_remote_contig {
	my ( $self, $uri, $options ) = @_;
	( my $base_uri = $uri ) =~ s/\/contigs\/\d+$//x;
	if ( $uri !~ /\?/x ) {
		$uri .= q(?no_loci=1);
	}
	if ( $self->{'cache'}->{'remote_contig'}->{$uri} ) {
		return $self->{'cache'}->{'remote_contig'}->{$uri};
	}
	my $contig = $self->_get_remote_record( $base_uri, $uri );
	my $length = length $contig->{'sequence'};
	if ( $options->{'length'} ) {
		if ( $length != $options->{'length'} ) {
			$logger->error("Contig $uri length has changed!");
		}
	}
	my $checksum = Digest::MD5::md5_hex( $contig->{'sequence'} );
	if ( $options->{'checksum'} ) {
		if ( $checksum ne $options->{'checksum'} ) {
			$logger->error("Contig $uri checksum has changed!");
		}
	}
	if ( $options->{'set_checksum'} && $options->{'seqbin_id'} ) {
		my $seqbin = $self->{'seqbin_table'} // 'sequence_bin';
		eval {
			$self->{'db'}
			  ->do( 'UPDATE remote_contigs SET (length,checksum)=(?,?) WHERE uri=?', undef, $length, $checksum, $uri );
			$self->{'db'}->do(
				"UPDATE $seqbin SET (method,original_designation,comments)=(?,?,?) WHERE id=?",
				undef, $contig->{'method'}, $contig->{'original_designation'},
				$contig->{'comments'}, $options->{'seqbin_id'}
			);
		};
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
		}
	}
	$self->{'cache'}->{'remote_contig'}->{$uri} = $contig;
	return $contig;
}

sub get_remote_contig_list {
	my ( $self, $uri ) = @_;
	( my $base_uri = $uri ) =~ s/\/isolates\/\d+\/contigs[\?return_all=1]*$//x;
	return $self->_get_remote_record( $base_uri, $uri );
}

sub get_remote_isolate {
	my ( $self, $uri ) = @_;
	( my $base_uri = $uri ) =~ s/\/isolates\/\d+$//x;
	return $self->_get_remote_record( $base_uri, $uri );
}

sub get_remote_fasta {
	my ( $self, $uri ) = @_;
	( my $base_uri = $uri ) =~ s/\/isolates\/\d+\/contigs_fasta$//x;
	return $self->_get_remote_record( $base_uri, $uri, { non_json => 1 } );
}

sub is_config_ok {
	my ( $self, $base_uri ) = @_;
	eval { $self->_get_remote_record( $base_uri, $base_uri ); };
	return $@ ? 0 : 1;
}

sub _get_remote_record {
	my ( $self, $base_uri, $uri, $options ) = @_;
	my $oauth_credentials = $self->{'datastore'}->run_query( 'SELECT * FROM oauth_credentials WHERE base_uri=?',
		$base_uri, { fetch => 'row_hashref', cache => 'ContigManager::get_credentials' } );
	my $requires_authorization = $oauth_credentials ? 1 : 0;
	if ( !$requires_authorization ) {
		my $response;
		for my $attempt ( 1 .. 5 ) {
			$response = $self->{'ua'}->get($uri);
			last if $response->is_success || $response->code == 401;
			my ( $code, $msg ) = ( $response->code, $response->message );
			$logger->error("Error retrieving $uri: Response $code: $msg. Will retry in 1s.");
			sleep 1;
		}
		if ( $response->is_success ) {
			if ( $options->{'non_json'} ) {
				return $response->decoded_content;
			}
			my $data;
			eval { $data = decode_json( $response->decoded_content ); };
			BIGSdb::Exception::Data->throw('Data is not JSON') if $@;
			return $data;
		} else {
			if ( $response->code == 401 ) {
				$requires_authorization = 1;
			} else {
				my ( $code, $msg ) = ( $response->code, $response->message );
				$logger->error("Error retrieving $uri: Response $code: $msg");
			}
		}
	}
	if ($requires_authorization) {
		if ( !$oauth_credentials ) {
			BIGSdb::Exception::Authentication->throw("$uri requires authorization - no credentials set");
		}
		return $self->_get_protected_route( $oauth_credentials, $base_uri, $uri, $options );
	}
	BIGSdb::Exception::File->throw("Cannot retrieve $uri");
}

sub _get_protected_route {
	my ( $self, $oauth_credentials, $base_uri, $uri, $options ) = @_;
	if ( !$oauth_credentials->{'session_token'} ) {
		$self->_get_session_token( $oauth_credentials, $base_uri );
	}
	my $request = Net::OAuth->request('protected resource')->new(
		consumer_key     => $oauth_credentials->{'consumer_key'},
		consumer_secret  => $oauth_credentials->{'consumer_secret'},
		token            => $oauth_credentials->{'session_token'},
		token_secret     => $oauth_credentials->{'session_secret'},
		request_url      => $uri,
		request_method   => 'GET',
		signature_method => 'HMAC-SHA1',
		timestamp        => time,
		nonce            => join( '', rand_chars( size => 16, set => 'alphanumeric' ) ),
	);
	$request->sign;
	BIGSdb::Exception::Authentication->throw('Cannot verify signature') unless $request->verify;
	my $res = $self->{'ua'}->get( $request->to_url );
	if ( $options->{'non_json'} ) {
		return $res->content;
	}
	my $decoded_json;
	eval { $decoded_json = decode_json( $res->content ) };
	if ($@) {
		$logger->error( $res->content );
		return;
	}
	BIGSdb::Exception::Data->throw('Invalid JSON') if ref $decoded_json ne 'HASH';
	if ( ( $decoded_json->{'message'} // q() ) =~ /Client\ is\ unauthorized/x ) {
		BIGSdb::Exception::Authentication->throw('Access denied - client is unauthorized.');
	}
	if ( ( $decoded_json->{'status'} // q() ) eq '401' ) {
		$logger->info('Invalid session token, requesting new one.');
		$self->_remove_session_token($base_uri);
		$self->_get_session_token( $oauth_credentials, $base_uri );
		return $self->_get_protected_route( $oauth_credentials, $base_uri, $uri );
	}
	return $decoded_json;
}

sub _remove_session_token {
	my ( $self, $base_uri ) = @_;
	eval {
		$self->{'db'}->do( 'UPDATE oauth_credentials SET session_token=NULL,session_secret=NULL WHERE base_uri=?',
			undef, $base_uri );
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub _get_session_token {
	my ( $self, $oauth_credentials, $base_uri ) = @_;
	my $request = Net::OAuth->request('protected resource')->new(
		consumer_key     => $oauth_credentials->{'consumer_key'},
		consumer_secret  => $oauth_credentials->{'consumer_secret'},
		token            => $oauth_credentials->{'access_token'},
		token_secret     => $oauth_credentials->{'access_secret'},
		request_url      => "$base_uri/oauth/get_session_token",
		request_method   => 'GET',
		signature_method => 'HMAC-SHA1',
		timestamp        => time,
		nonce            => join( '', rand_chars( size => 16, set => 'alphanumeric' ) ),
	);
	$request->sign;
	BIGSdb::Exception::Authentication->throw('Cannot verify signature') unless $request->verify;
	my $res = $self->{'ua'}->request( GET $request->to_url, Content_Type => 'application/json' );
	my $decoded_json = decode_json( $res->content );
	if ( $res->is_success ) {
		my $session_response = Net::OAuth->response('access token')->from_hash($decoded_json);
		eval {
			$self->{'db'}->do( 'UPDATE oauth_credentials SET (session_token,session_secret)=(?,?) WHERE base_uri=?',
				undef, $session_response->token, $session_response->token_secret, $base_uri );
		};
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
		}
		$oauth_credentials->{'session_token'}  = $session_response->token;
		$oauth_credentials->{'session_secret'} = $session_response->token_secret;
		return $session_response;
	} else {
		$logger->error($res->as_string);
		BIGSdb::Exception::Authentication->throw("Invalid access token for $base_uri");
	}
}

sub get_contig_fragment {
	my ( $self, $args ) = @_;
	$args->{'start'} = 1 if $args->{'start'} < 1;
	my $seqbin = $self->{'seqbin_table'} // 'sequence_bin';
	my $contig_info = $self->{'datastore'}->run_query(
		"SELECT GREATEST(r.length,length(s.sequence)) AS length,s.remote_contig FROM $seqbin s LEFT JOIN "
		  . 'remote_contigs r ON s.id=r.seqbin_id WHERE s.id=?',
		$args->{'seqbin_id'},
		{ fetch => 'row_hashref', cache => "ContigManager::get_contig_fragment::$seqbin" }
	);
	$args->{'contig_length'} = $contig_info->{'length'};
	$args->{'end'} = $args->{'contig_length'} if $args->{'end'} > $args->{'contig_length'};
	$args->{'flanking'} =
	  ( BIGSdb::Utils::is_int( $args->{'flanking'} ) && $args->{'flanking'} >= 0 ) ? $args->{'flanking'} : 100;
	my $seq_ref;

	if ( $contig_info->{'remote_contig'} ) {
		$seq_ref = $self->_get_remote_contig_fragment($args);
	} else {
		$seq_ref = $self->_get_local_contig_fragment($args);
	}
	if ( $args->{'reverse'} ) {
		$seq_ref->{'seq'}        = BIGSdb::Utils::reverse_complement( $seq_ref->{'seq'} );
		$seq_ref->{'upstream'}   = BIGSdb::Utils::reverse_complement( $seq_ref->{'upstream'} );
		$seq_ref->{'downstream'} = BIGSdb::Utils::reverse_complement( $seq_ref->{'downstream'} );
	}
	return $seq_ref;
}

sub _get_remote_contig_fragment {
	my ( $self, $args ) = @_;
	my ( $uri, $checksum ) =
	  $self->{'datastore'}
	  ->run_query( 'SELECT uri,checksum FROM remote_contigs WHERE seqbin_id=?', $args->{'seqbin_id'} );
	my $contig;
	my $seq_ref = {};
	eval { $contig = $self->get_remote_contig( $uri, { checksum => $checksum } ) };
	if ($@) {
		$logger->error($@);
		return {};
	}
	if ( $args->{'start'} < 1 ) {
		$logger->error('Seq start is <1!');
	}
	my $flanking       = $args->{'flanking'};
	my $upstream_flanking=$flanking;
	my $extract_length = $args->{'end'} - $args->{'start'} + 1;
	my $upstream_start = $args->{'start'} - 1 - $flanking;
	if ($upstream_start < 0){
		$upstream_flanking += $upstream_start;
		$upstream_start=0;
		$upstream_flanking = 0 if $upstream_flanking<0;
	}
	return {
		seq => substr( $contig->{'sequence'}, $args->{'start'} - 1, $extract_length ),
		upstream => substr( $contig->{'sequence'}, $upstream_start, $upstream_flanking ),
		downstream => substr( $contig->{'sequence'}, $args->{'end'}, $flanking )
	};
}

sub _get_local_contig_fragment {
	my ( $self, $args ) = @_;
	my $flanking = $args->{'flanking'};
	my $length   = abs( $args->{'end'} - $args->{'start'} + 1 );
	my $seqbin   = $self->{'seqbin_table'} // 'sequence_bin';
	my $qry =
	    "SELECT substring(sequence FROM $args->{'start'} FOR $length) AS seq,substring(sequence "
	  . "FROM ($args->{'start'}-$flanking) FOR $flanking) AS upstream,substring(sequence FROM "
	  . "($args->{'end'}+1) FOR $flanking) AS downstream FROM $seqbin WHERE id=?";
	return $self->{'datastore'}->run_query( $qry, $args->{'seqbin_id'}, { fetch => 'row_hashref' } );
}

sub get_contig {
	my ( $self, $seqbin_id ) = @_;
	my $seqbin = $self->{'seqbin_table'} // 'sequence_bin';
	my ( $remote, $sequence ) =
	  $self->{'datastore'}->run_query( "SELECT remote_contig,sequence FROM $seqbin WHERE id=?",
		$seqbin_id, { cache => 'ContigManager::get_contig' } );
	if ( !defined $remote ) {
		$logger->error("No seqbin record $seqbin_id");
		return \undef;
	}
	if ($remote) {
		my $uri = $self->{'datastore'}->run_query( 'SELECT uri FROM remote_contigs WHERE seqbin_id=?',
			$seqbin_id, { cache => 'ContigManager::get_remote_contig_uri' } );
		my $contig;
		eval { $contig = $self->get_remote_contig($uri) };
		if ($@) {
			$logger->error($@);
			return \undef;
		}
		my $seq = $contig->{'sequence'};
		return \$seq;
	} else {
		return \$sequence;
	}
}

sub get_contig_length {
	my ( $self, $seqbin_id ) = @_;
	my $seqbin = $self->{'seqbin_table'} // 'sequence_bin';
	return $self->{'datastore'}->run_query(
		"SELECT GREATEST(r.length,length(s.sequence)) FROM $seqbin s LEFT JOIN "
		  . 'remote_contigs r ON s.id=r.seqbin_id WHERE s.id=?',
		$seqbin_id,
		{ cache => 'ContigManager::get_contig_length' }
	);
}

sub get_contigs_by_list {
	my ( $self, $seqbin_ids ) = @_;
	my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $seqbin_ids );
	my $seqbin = $self->{'seqbin_table'} // 'sequence_bin';
	my $data = $self->{'datastore'}->run_query(
		"SELECT s.id,s.remote_contig,r.uri,r.checksum,s.sequence FROM $seqbin s LEFT JOIN "
		  . "remote_contigs r ON s.id=r.seqbin_id JOIN $temp_table t ON s.id=t.value",
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $return_contigs = {};
	my $uris           = [];
	foreach my $contig (@$data) {
		if ( $contig->{'remote_contig'} ) {
			push @$uris, $contig->{'uri'};
		} else {
			$return_contigs->{ $contig->{'id'} } = $contig->{'sequence'};
		}
	}
	if (@$uris) {
		my $remote_seqs = $self->get_remote_contigs_by_list($uris);
		foreach my $contig (@$data) {
			next if !$contig->{'remote_contig'};
			if ( $contig->{'checksum'} ) {
				my $checksum = Digest::MD5::md5_hex( $remote_seqs->{ $contig->{'uri'} } );
				if ( $contig->{'checksum'} ne $checksum ) {
					$logger->error("Checksum for remote contig seqbin id: $contig->{'id'} has changed!");
				}
			}
			$return_contigs->{ $contig->{'id'} } = $remote_seqs->{ $contig->{'uri'} };
		}
	}
	$self->{'db'}->do("DROP TABLE $temp_table");
	$self->{'db'}->commit;
	return $return_contigs;
}
1;
