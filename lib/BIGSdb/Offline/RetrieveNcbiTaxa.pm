#Written by Keith Jolley
#Copyright (c) 2026, University of Oxford
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

#Options - pass as 'options' key/value pairs in constructor.
#method:
#	new: retrieve new taxa not currently stored.
#	refresh: refresh all taxa retrieved >X days ago (option: retrieve_days; default 365).

#retry: set to 1 to retry ids that were previously not found.
#clear: set to 1 to remove entries for taxa not included in schemes table.
package BIGSdb::Offline::RetrieveNcbiTaxa;
use strict;
use warnings;
use 5.010;
use LWP::UserAgent;
use JSON;
use parent qw(BIGSdb::Offline::Script);
use constant REFRESH_DAYS => 365;
use constant API_URL      => 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi';

sub run_script {
	my ($self) = @_;
	return if !$self->{'system'}->{'db'};
	if ( ( $self->{'system'}->{'dbtype'} // q() ) ne 'sequences' ) {
		$self->{'logger'}->fatal('This should only be run against seqdef databases.');
	}
	my $selected_method = $self->{'options'}->{'method'} // 'new';
	my $methods         = { new => '_retrieve_new', refresh => '_refresh' };
	if ( $methods->{$selected_method} ) {
		my $method = $methods->{$selected_method};
		$self->$method();
	} else {
		$self->{'logger'}->fatal('Invalid method selected.');
	}
	if ( $self->{'options'}->{'clear'} ) {
		$self->_clear;
	}
	return;
}

sub get_dbase_name {
	my ($self) = @_;
	return $self->{'system'}->{'db'};
}

sub _get_referenced_taxon_ids {
	my ($self) = @_;
	return $self->{'datastore'}
	  ->run_query( 'SELECT DISTINCT UNNEST(ncbi_taxon) FROM schemes WHERE ncbi_taxon IS NOT NULL',
		undef, { fetch => 'col_arrayref' } );
}

sub _clear {
	my ($self)     = @_;
	my $taxon_ids  = $self->_get_referenced_taxon_ids;
	my %referenced = map { $_ => 1 } @$taxon_ids;
	my $defined_ids =
	  $self->{'datastore'}->run_query( q(SELECT id FROM ncbi_taxa ORDER BY id), undef, { fetch => 'col_arrayref' } );
	foreach my $id (@$defined_ids) {
		if ( !$referenced{$id} ) {
			$self->{'logger'}->info("Removing unused taxon: id-$id") if !$self->{'options'}->{'quiet'};
			eval { $self->{'db'}->do( 'DELETE FROM ncbi_taxa WHERE id=?', undef, $id ) };
			if ($@) {
				$self->{'logger'}->error($@);
				$self->{'db'}->rollback;
			} else {
				$self->{'db'}->commit;
			}
		}
	}
	return;
}

sub _retrieve_new {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self)    = @_;
	my $taxon_ids = $self->_get_referenced_taxon_ids;
	my $retry     = $self->{'options'}->{'retry'} ? q() : q( OR status='not found');
	my $existing  = $self->{'datastore'}
	  ->run_query( qq(SELECT id FROM ncbi_taxa WHERE status='active'$retry), undef, { fetch => 'col_arrayref' } );
	my %existing    = map { $_ => 1 } @$existing;
	my $to_retrieve = [];
	foreach my $id (@$taxon_ids) {
		next if $existing{$id};
		push @$to_retrieve, $id;
	}
	return if !@$to_retrieve;
	my $data = $self->_query_api($to_retrieve);
	$self->_update( $to_retrieve, $data );
	sleep 2 if $self->{'options'}->{'pause'};
	return;
}

sub _refresh {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self)       = @_;
	my $taxon_ids    = $self->_get_referenced_taxon_ids;
	my $retry        = $self->{'options'}->{'retry'} ? q() : q( OR status='not found');
	my $days         = $self->{'options'}->{'refresh_days'} // REFRESH_DAYS;
	my $last_checked = $self->{'options'}->{'retry'} ? q() : qq( OR last_checked>now()-interval '$days days');
	my $existing     = $self->{'datastore'}->run_query(
		qq(SELECT id FROM ncbi_taxa WHERE (status='active'$retry) AND )
		  . qq((fetched>now()-interval '$days days'$last_checked)),
		undef,
		{ fetch => 'col_arrayref' }
	);
	my %existing    = map { $_ => 1 } @$existing;
	my $to_retrieve = [];

	foreach my $id (@$taxon_ids) {
		next if $existing{$id};
		push @$to_retrieve, $id;
	}
	return if !@$to_retrieve;
	my $data = $self->_query_api($to_retrieve);
	$self->_update( $to_retrieve, $data );
	sleep 2 if $self->{'options'}->{'pause'};
	return;
}

sub _update {
	my ( $self, $taxon_ids, $results ) = @_;
	my %rank_domain = map{$_ => 1}qw(2 2157 2759);#Bacteria, Archaea, Eukaryota
	foreach my $id (@$taxon_ids) {
		eval {
			if ( $results->{'result'}->{$id} ) {
				my $result  = $results->{'result'}->{$id};
				my $status  = $result->{'error'} ? 'not found' : 'active';
				my $fetched = $result->{'error'} ? undef       : 'now';
				if (   ( $result->{'status'} // q() ) eq 'merged'
					&& $result->{'scientificname'} eq q()
					&& BIGSdb::Utils::is_int( $result->{'akataxid'} ) )
				{
					$self->{'logger'}->error( "$self->{'instance'}: NCBI taxon $id has merged. "
						  . "Update scheme taxa to use id: $result->{'akataxid'} instead." );
					next;
				}
				if (($result->{'rank'} // q()) eq 'acellular root' && $rank_domain{$id}){
					$result->{'rank'} = 'domain';
				}
				

				$self->{'db'}->do(
					'INSERT INTO ncbi_taxa (id,scientific_name,rank,status,fetched,last_checked) VALUES (?,?,?,?,?,?) '
					  . 'ON CONFLICT(id) DO UPDATE SET (scientific_name,rank,status,fetched,last_checked)=(?,?,?,?,?)',
					undef,
					$id,
					$result->{'scientificname'},
					$result->{'rank'},
					$status,
					$fetched,
					'now',
					$result->{'scientificname'},
					$result->{'rank'},
					$status,
					$fetched,
					'now',
				);
				if ( $result->{'error'} ) {
					$self->{'logger'}->error("$self->{'instance'}: Taxon id:$id not found.");

				} else {
					$self->{'logger'}->info("$self->{'instance'}: Adding taxon information for taxon id:$id.")
					  if !$self->{'options'}->{'quiet'};
				}
			} else {
				$self->{'db'}->do(
					'INSERT INTO ncbi_taxa (id,scientific_name,rank,status,fetched,last_checked) VALUES (?,?,?,?,?,?) '
					  . 'ON CONFLICT(id) DO NOTHING',
					undef, $id, undef, undef, 'error', undef, 'now'
				);
			}
		};
		if ($@) {
			$self->{'logger'}->error($@);
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
		}
	}
	return;
}

sub _query_api {
	my ( $self, $ids ) = @_;
	my $ua = LWP::UserAgent->new( agent => 'BIGSdb', timeout => 10 );
	local $" = q(,);
	my $response = $ua->post( API_URL, { db => 'taxonomy', retmode => 'json', id => qq(@$ids) } );
	if ( $response->is_success ) {
		my $json = $response->decoded_content;
		my $data = {};
		eval { $data = decode_json($json) };
		$self->{'logger'}->error($@) if $@;
		return $data;
	} else {
		$self->{'logger'}->error( 'Error from NCBI Taxonomy API: ' . $response->status_line );
	}
	return {};
}

1;
