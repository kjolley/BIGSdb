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
package BIGSdb::REST::Routes::Loci;
use strict;
use warnings;
use 5.010;
use Dancer2 appname => 'BIGSdb::REST::Interface';

#Locus routes
get '/db/:db/loci' => sub {
	my $self   = setting('self');
	my ($db)   = params->{'db'};
	my $page   = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? " WHERE (id IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes "
	  . "WHERE set_id=$set_id)) OR id IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';
	my $locus_count = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM loci$set_clause");
	my $pages       = int( $locus_count / $self->{'page_size'} ) + 1;
	my $offset      = ( $page - 1 ) * $self->{'page_size'};
	my $loci = $self->{'datastore'}->run_query( "SELECT id FROM loci$set_clause ORDER BY id OFFSET $offset LIMIT $self->{'page_size'}",
		undef, { fetch => 'col_arrayref' } );
	my $values = [];

	if (@$loci) {
		my $paging = $self->get_paging( "/db/$db/loci", $pages, $page );
		push @$values, { paging => $paging } if $pages > 1;
		my @links;
		foreach my $locus (@$loci) {
			my $cleaned_locus = $self->clean_locus($locus);
			push @links, request->uri_for("/db/$db/loci/$cleaned_locus")->as_string;
		}
		push @$values, { loci => \@links };
	}
	return $values;
};
1;
