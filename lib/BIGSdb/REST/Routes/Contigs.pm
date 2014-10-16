#Written by Keith Jolley
#Copyright (c) 2014, University of Oxford
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
package BIGSdb::REST::Routes::Contigs;
use strict;
use warnings;
use 5.010;
use POSIX qw(ceil);
use Dancer2 appname                => 'BIGSdb::REST::Interface';
get '/db/:db/isolates/:id/contigs' => sub {
	my $self = setting('self');
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		status(404);
		return { error => "This is not an isolates database." };
	}
	my ( $db, $isolate_id ) = ( params->{'db'}, params->{'id'} );
	if ( !BIGSdb::Utils::is_int($isolate_id) ) {
		status(400);
		return { error => 'Id must be an integer.' };
	}
	my $values = [];
	my $field_values =
	  $self->{'datastore'}->run_query( "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id, { fetch => 'row_hashref' } );
	if ( !defined $field_values->{'id'} ) {
		status(404);
		return { error => "Isolate $isolate_id does not exist." };
	}
	my $contig_count = $self->{'datastore'}->run_query( "SELECT COUNT(*) FROM sequence_bin WHERE isolate_id=?", $isolate_id );
	my $page   = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $pages  = ceil( $contig_count / $self->{'page_size'} );
	my $offset = ( $page - 1 ) * $self->{'page_size'};
	my $contigs =
	  $self->{'datastore'}
	  ->run_query( "SELECT id FROM sequence_bin WHERE isolate_id=? ORDER BY id", $isolate_id, { fetch => 'col_arrayref' } );
	if ( !@$contigs ) {
		status(404);
		return { error => "No contigs for isolate id-$isolate_id are defined." };
	}
	my $paging = $self->get_paging( "/db/$db/isolates/$isolate_id/contigs", $pages, $page );
	push @$values, { paging => $paging } if $pages > 1;
	my $contig_links = [];
	foreach my $contig_id (@$contigs) {
		push @$contig_links, request->uri_for("/db/$db/contigs/$contig_id")->as_string;
	}
	push @$values, { contigs => $contig_links };
	return $values;
};
get '/db/:db/contigs/:contig' => sub {
	my $self = setting('self');
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		status(404);
		return { error => "This is not an isolates database." };
	}
	my ( $db, $contig_id ) = ( params->{'db'}, params->{'contig'} );
	if ( !BIGSdb::Utils::is_int($contig_id) ) {
		status(400);
		return { error => 'Contig id must be an integer.' };
	}
	my $contig = $self->{'datastore'}->run_query( "SELECT * FROM sequence_bin WHERE id=?", $contig_id, { fetch => 'row_hashref' } );
	if ( !$contig ) {
		status(404);
		return { error => "Contig id-$contig_id does not exist." };
	}
	my $values = [];
	foreach my $field (qw (id isolate_id sequence method orignal_designation comments sender curator date_entered datestamp)) {
		if ( $field eq 'isolate_id' ) {
			push @$values, { $field => request->uri_for("/db/$db/isolates/$contig->{$field}")->as_string };
		} elsif ( $field eq 'sender' || $field eq 'curator' ) {
			push @$values, { $field => request->uri_for("/db/$db/users/$contig->{$field}")->as_string };
		} else {
			push @$values, { $field => $contig->{ lc $field } } if defined $contig->{ lc $field };
		}
	}
	return $values;
};
1;
