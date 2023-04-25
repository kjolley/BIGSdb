#Written by Keith Jolley
#Copyright (c) 2014-2019, University of Oxford
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
package BIGSdb::REST::Routes::Contigs;
use strict;
use warnings;
use 5.010;
use JSON;
use Dancer2 appname => 'BIGSdb::REST::Interface';

sub setup_routes {
	my $self = setting('self');
	foreach my $dir ( @{ setting('api_dirs') } ) {
		get "$dir/db/:db/isolates/:id/contigs"       => sub { _get_contigs() };
		get "$dir/db/:db/isolates/:id/contigs_fasta" => sub { _get_contigs_fasta() };
		get "$dir/db/:db/contigs/:contig"            => sub { _get_contig() };
	}
	return;
}

sub _get_contigs {
	my $self = setting('self');
	my ( $db, $isolate_id ) = ( params->{'db'}, params->{'id'} );
	$self->check_isolate_is_valid($isolate_id);
	my $subdir = setting('subdir');
	my $contig_count =
	  $self->{'datastore'}->run_query( 'SELECT COUNT(*) FROM sequence_bin WHERE isolate_id=?', $isolate_id );
	my $page_values = $self->get_page_values($contig_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};
	my $qry = 'SELECT id FROM sequence_bin WHERE isolate_id=? ORDER BY id';
	$qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !param('return_all');
	my $contigs = $self->{'datastore'}->run_query( $qry, $isolate_id, { fetch => 'col_arrayref' } );
	my $values = { records => int($contig_count) };
	my $paging = $self->get_paging( "$subdir/db/$db/isolates/$isolate_id/contigs", $pages, $page, $offset );
	$values->{'paging'} = $paging if %$paging;
	my $contig_links = [];

	foreach my $contig_id (@$contigs) {
		push @$contig_links, request->uri_for("$subdir/db/$db/contigs/$contig_id");
	}
	$values->{'contigs'} = $contig_links;
	return $values;
}

sub _get_contigs_fasta {
	my $self = setting('self');
	my ( $db, $isolate_id ) = ( params->{'db'}, params->{'id'} );
	$self->check_isolate_is_valid($isolate_id);
	my $values = {};
	my $contigs =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id,original_designation,sequence FROM sequence_bin WHERE isolate_id=? ORDER BY id',
		$isolate_id, { fetch => 'all_arrayref', slice => {} } );
	if ( !@$contigs ) {
		send_error( "No contigs for isolate id-$isolate_id are defined.", 404 );
	}
	if ( ( $self->{'system'}->{'remote_contigs'} // q() ) eq 'yes' ) {
		my $seqbin_ids = [];
		push @$seqbin_ids, $_->{'id'} foreach @$contigs;
		my $seqs = $self->{'contigManager'}->get_contigs_by_list($seqbin_ids);
		foreach my $contig (@$contigs) {
			$contig->{'sequence'} = $seqs->{ $contig->{'id'} } if $seqs->{ $contig->{'id'} };
		}
	}
	my $buffer = '';
	my $header_field = ( param('header') // q() ) eq 'original_designation' ? 'original_designation' : 'id';
	foreach my $contig (@$contigs) {
		my $header = $contig->{$header_field} // $contig->{'id'};
		$buffer .= ">$header\n$contig->{'sequence'}\n";
	}
	send_file( \$buffer, content_type => 'text/plain; charset=UTF-8' );
	return;
}

sub _get_contig {
	my $self = setting('self');
	$self->check_isolate_database;
	my ( $db, $contig_id ) = ( params->{'db'}, params->{'contig'} );
	if ( !BIGSdb::Utils::is_int($contig_id) ) {
		send_error( 'Contig id must be an integer.', 400 );
	}
	my $contig =
	  $self->{'datastore'}->run_query(
		'SELECT s.*,r.uri,r.checksum FROM sequence_bin s LEFT JOIN remote_contigs r ON s.id=r.seqbin_id WHERE id=?',
		$contig_id, { fetch => 'row_hashref' } );
	if ( !$contig ) {
		send_error( "Contig id-$contig_id does not exist.", 404 );
	}
	my $subdir = setting('subdir');
	if ( $contig->{'remote_contig'} ) {
		my $remote =
		  $self->{'contigManager'}->get_remote_contig( $contig->{'uri'}, { checksum => $contig->{'checksum'} } );
		$contig->{'sequence'} = $remote->{'sequence'};
	}
	my $values = {
		isolate_id => request->uri_for("$subdir/db/$db/isolates/$contig->{'isolate_id'}"),
		id         => int( $contig->{'id'} ),
		sequence   => $contig->{'sequence'},
		length     => length $contig->{'sequence'},
		sender     => request->uri_for("$subdir/db/$db/users/$contig->{'sender'}"),
		curator    => request->uri_for("$subdir/db/$db/users/$contig->{'curator'}")
	};
	$values->{'original_designation'} = $contig->{'original_designation'}
	  if defined $contig->{'original_designation'};
	foreach my $field (qw (method orignal_designation comments date_entered datestamp)) {
		$values->{$field} = $contig->{ lc $field }
		  if defined $contig->{ lc $field } && $contig->{ lc $field } ne '';
	}
	my $attributes =
	  $self->{'datastore'}->run_query( 'SELECT * FROM sequence_attribute_values WHERE seqbin_id=? ORDER BY key',
		$contig_id, { fetch => 'all_arrayref', slice => {} } );
	foreach my $attribute (@$attributes) {
		if ( BIGSdb::Utils::is_int( $attribute->{'value'} ) ) {

			#Force integer output (non-quoted)
			push @$values, { $attribute->{'key'} => int( $attribute->{'value'} ) };
		} else {
			push @$values, { $attribute->{'key'} => $attribute->{'value'} };
		}
	}
	if ( !params->{'no_loci'} ) {
		my $allele_seqs =
		  $self->{'datastore'}->run_query( 'SELECT * FROM allele_sequences WHERE seqbin_id=? ORDER BY start_pos',
			$contig_id, { fetch => 'all_arrayref', slice => {} } );
		my $tags = [];
		foreach my $tag (@$allele_seqs) {
			my $locus_name = $self->clean_locus( $tag->{'locus'} );
			push @$tags,
			  {
				locus      => request->uri_for("$subdir/db/$db/loci/$tag->{'locus'}"),
				locus_name => $locus_name,
				start      => int( $tag->{'start_pos'} ),
				end        => int( $tag->{'end_pos'} ),
				direction  => $tag->{'reverse'} ? 'reverse' : 'forward',
				complete   => $tag->{'complete'} ? JSON::true : JSON::false
			  };
		}
		$values->{'loci'} = $tags if @$tags;
	}
	return $values;
}
1;
