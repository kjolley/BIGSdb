#Written by Keith Jolley
#Copyright (c) 2020, University of Oxford
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
package BIGSdb::Offline::SpeciesID;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Offline::Script);
use JSON;
use MIME::Base64;
use LWP::UserAgent;
use BIGSdb::Exceptions;
use constant INITIAL_BUSY_DELAY   => 60;
use constant ATTEMPTS_BEFORE_FAIL => 50;
use constant MAX_DELAY            => 600;

#use constant URL => 'https://rest.pubmlst.org/db/pubmlst_rmlst_seqdef_kiosk/schemes/1/sequence';
use constant SEQUENCE_URL     => 'http://localhost/api/db/pubmlst_rmlst_seqdef_kiosk/schemes/1/sequence';
use constant DESIGNATIONS_URL => 'http://localhost/api/db/pubmlst_rmlst_seqdef_kiosk/schemes/1/designations';

sub run {
	my ( $self, $isolate_id ) = @_;
	$self->initiate_job_manager;
	my $agent = LWP::UserAgent->new( agent => 'BIGSdb' );
	my $payload;
	my $url;
	if ( $self->{'options'}->{'scan_genome'} ) {
		my $fasta_ref = $self->_get_genome_fasta($isolate_id);
		$payload = encode_json(
			{
				base64   => JSON::true(),
				details  => JSON::true(),
				sequence => encode_base64($$fasta_ref)
			}
		);
		$url = SEQUENCE_URL;
	} else {
		my $designations = $self->_get_rmlst_designations($isolate_id);
		$payload = encode_json(
			{
				designations => $designations
			}
		);
		$url = DESIGNATIONS_URL;
	}
	my ( $response, $unavailable );
	my $delay = INITIAL_BUSY_DELAY;
	my $isolate_name =
	  $self->{'datastore'}
	  ->run_query( "SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?",
		$isolate_id, { cache => 'SpeciesID::get_isolate_name_from_id' } );
	my %server_error = map { $_ => 1 } ( 500, 502, 503, 504 );
	my $attempts = 0;
	$self->{'dataConnector'}->drop_all_connections;    #No need to keep these open while we wait for REST response.
	do {
		$unavailable = 0;
		$response    = $agent->post(
			$url,
			Content_Type => 'application/json; charset=UTF-8',
			Content      => $payload
		);
		if ( $server_error{ $response->code } ) {
			my $code = $response->code;
			$self->{'logger'}->error("Error $code received from rMLST REST API.");
			$self->{'jobManager'}->update_job_status( $self->{'options'}->{'job_id'},
				{ stage => "rMLST server is unavailable or too busy at the moment - retrying in $delay seconds" } );
			$self->{'dataConnector'}->drop_all_connections;
			$unavailable = 1;
			$attempts++;
			if ( $attempts > ATTEMPTS_BEFORE_FAIL ) {
				BIGSdb::Exception::Server->throw(
					"Calls to REST interface have failed $attempts times. Giving up - please try again later.");
			}
			sleep $delay;
			$delay += 10 if $delay < MAX_DELAY;
		}
	} while ($unavailable);
	my $data     = {};
	my $rank     = [];
	my $taxon    = [];
	my $taxonomy = [];
	my $support  = [];
	my ( $rST, $species );
	if ( $response->is_success ) {
		$data = decode_json( $response->content );
		if ( $data->{'taxon_prediction'} ) {
			foreach my $prediction ( @{ $data->{'taxon_prediction'} } ) {
				push @$rank,     $prediction->{'rank'};
				push @$taxon,    $prediction->{'taxon'};
				push @$taxonomy, $prediction->{'taxonomy'};
				push @$support,  $prediction->{'support'};
			}
		}
		if ( $data->{'fields'} ) {
			$rST = $data->{'fields'}->{'rST'};
			$species = $data->{'fields'}->{'species'} // q();
		}
	} else {
		$self->{'logger'}->error( $response->as_string );
	}
	my $values = {
		isolate_id   => $isolate_id,
		isolate_name => $isolate_name,
		rank         => $rank,
		taxon        => $taxon,
		taxonomy     => $taxonomy,
		support      => $support,
		rST          => $rST,
		species      => $species
	};
	return { data => $data, values => $values, response => $response };
}

sub _get_rmlst_designations {
	my ( $self, $isolate_id ) = @_;
	my $scheme_id = $self->{'datastore'}->run_query( 'SELECT id FROM schemes WHERE name=?', 'Ribosomal MLST' );
	BIGSdb::Exception::Database::Configuration->throw('Ribosomal MLST scheme does not exist') if !defined $scheme_id;
	my $designations = $self->{'datastore'}->run_query(
		q(SELECT locus,allele_id FROM allele_designations WHERE isolate_id=? AND )
		  . q(locus IN (SELECT locus FROM scheme_members WHERE scheme_id=?) ),
		[ $isolate_id, $scheme_id ],
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $values = {};
	foreach my $designation (@$designations) {
		push @{ $values->{ $designation->{'locus'} } }, { allele => $designation->{'allele_id'} };
	}
	return $values;
}

sub _get_genome_fasta {
	my ( $self, $isolate_id ) = @_;
	my $qry = 'SELECT id,sequence FROM sequence_bin WHERE isolate_id=? AND NOT remote_contig';
	my $contigs =
	  $self->{'datastore'}
	  ->run_query( $qry, $isolate_id, { fetch => 'all_arrayref', cache => 'SpeciesID::blast_create_fasta::local' } );
	my $fasta;
	foreach my $contig (@$contigs) {
		$fasta .= qq(>$contig->[0]\n$contig->[1]\n);
	}
	my $remote_qry = 'SELECT s.id,r.uri,r.length,r.checksum FROM sequence_bin s LEFT JOIN remote_contigs r ON '
	  . 's.id=r.seqbin_id WHERE s.isolate_id=? AND remote_contig';
	my $remote_contigs =
	  $self->{'datastore'}->run_query( $remote_qry, $isolate_id,
		{ fetch => 'all_arrayref', slice => {}, cache => 'SpeciesID::blast_create_fasta::remote' } );
	my $remote_uris = [];
	foreach my $contig_link (@$remote_contigs) {
		push @$remote_uris, $contig_link->{'uri'};
	}
	my $remote_data;
	eval { $remote_data = $self->{'contigManager'}->get_remote_contigs_by_list($remote_uris); };
	if ($@) {
		$self->{'logger'}->error($@);
	} else {
		foreach my $contig_link (@$remote_contigs) {
			$fasta .= qq(>$contig_link->{'id'}\n$remote_data->{$contig_link->{'uri'}}\n);
			if ( !$contig_link->{'length'} ) {
				$self->{'contigManager'}->update_remote_contig_length( $contig_link->{'uri'},
					length( $remote_data->{ $contig_link->{'uri'} } ) );
			} elsif ( $contig_link->{'length'} != length( $remote_data->{ $contig_link->{'uri'} } ) ) {
				$self->{'logger'}->error("$contig_link->{'uri'} length has changed!");
			}

			#We won't set checksum because we're not extracting all metadata here
		}
	}
	return \$fasta;
}


1;
