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
package BIGSdb::REST::Routes::Alleles;
use strict;
use warnings;
use 5.010;
use POSIX qw(ceil);
use Dancer2 appname => 'BIGSdb::REST::Interface';

#Allele routes
get '/db/:db/alleles/:locus' => sub {
	my $self = setting('self');
	if ( $self->{'system'}->{'dbtype'} ne 'sequences' ) {
		status(404);
		return { error => "This is not a sequence definition database." };
	}
	my $params = params;
	my ( $db, $locus ) = @{$params}{qw(db locus)};
	my $page       = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $set_id     = $self->get_set_id;
	my $locus_name = $locus;
	if ($set_id) {
		$locus_name = $self->{'datastore'}->get_set_locus_real_id( $locus, $set_id );
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus_name);
	if ( !$locus_info ) {
		status(404);
		return { error => "Locus $locus does not exist." };
	}
	my $allele_count = $self->{'datastore'}->run_query( "SELECT COUNT(*) FROM sequences WHERE locus=?", $locus_name );
	my $pages        = ceil( $allele_count / $self->{'page_size'} );
	my $offset       = ( $page - 1 ) * $self->{'page_size'};
	my $qry =
	    "SELECT allele_id FROM sequences WHERE locus=? AND allele_id NOT IN ('0', 'N') ORDER BY "
	  . ( $locus_info->{'allele_id_format'} eq 'integer' ? 'CAST(allele_id AS int)' : 'allele_id' )
	  . " LIMIT $self->{'page_size'} OFFSET $offset";
	my $allele_ids = $self->{'datastore'}->run_query( $qry, $locus, { fetch => 'col_arrayref' } );
	if ( !@$allele_ids ) {
		status(404);
		return { error => "No alleles for locus $locus are defined." };
	}
	my $values = [];
	my $paging = $self->get_paging( "/db/$db/alleles/$locus_name", $pages, $page );
	push @$values, { paging => $paging } if $pages > 1;
	my $allele_links = [];
	foreach my $allele_id (@$allele_ids) {
		push @$allele_links, request->uri_for("/db/$db/alleles/$locus_name/$allele_id")->as_string;
	}
	push @$values, [ alleles => $allele_links ];
	return $values;
};
get '/db/:db/alleles/:locus/:allele_id' => sub {
	my $self = setting('self');
	if ( $self->{'system'}->{'dbtype'} ne 'sequences' ) {
		status(404);
		return { error => "This is not a sequence definition database." };
	}
	my $params = params;
	my ( $db, $locus, $allele_id ) = @{$params}{qw(db locus allele_id)};
	my $set_id     = $self->get_set_id;
	my $locus_name = $locus;
	if ($set_id) {
		$locus_name = $self->{'datastore'}->get_set_locus_real_id( $locus, $set_id );
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus_name);
	if ( !$locus_info ) {
		status(404);
		return { error => "Locus $locus does not exist." };
	}
	my $allele =
	  $self->{'datastore'}
	  ->run_query( "SELECT * FROM sequences WHERE locus=? AND allele_id=?", [ $locus_name, $allele_id ], { fetch => 'row_hashref' } );
	if ( !$allele ) {
		status(404);
		return { error => "Allele $locus-$allele_id does not exist." };
	}
	my $values = {};
	foreach my $attribute (qw(locus allele_id sequence status comments date_entered datestamp sender curator)) {
		if ( $attribute eq 'locus' ) {
			$values->{$attribute} = request->uri_for("/db/$db/loci/$locus")->as_string;
		} elsif ( $attribute eq 'sender' || $attribute eq 'curator' ) {

			#Don't link to user 0 (setup user)
			$values->{$attribute} = request->uri_for("/db/$db/users/$allele->{$attribute}")->as_string if $allele->{$attribute};
		} else {
			$values->{$attribute} = $allele->{$attribute} if defined $allele->{$attribute} && $allele->{$attribute} ne '';
		}
	}
	my $extended_attributes =
	  $self->{'datastore'}
	  ->run_query( "SELECT field FROM locus_extended_attributes WHERE locus=?", $locus_name, { fetch => 'col_arrayref' } );
	foreach my $attribute (@$extended_attributes) {
		my $extended_value = $self->{'datastore'}->run_query(
			"SELECT value FROM sequence_extended_attributes WHERE locus=? AND field=? AND allele_id=?",
			[ $locus_name, $attribute, $allele_id ],
			{ cache => 'Alleles:extended_attributes' }
		);
		$values->{$attribute} = $extended_value if defined $extended_value && $extended_value ne '';
	}
	my $flags = $self->{'datastore'}->get_allele_flags( $locus_name, $allele_id );
	$values->{'flags'} = $flags if @$flags;

	#TODO scheme members
	return $values;
};
1;
