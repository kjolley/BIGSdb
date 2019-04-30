#Written by Keith Jolley
#Copyright (c) 2018-2019, University of Oxford
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
package BIGSdb::IDList;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);

sub initiate {
	my ($self) = @_;
	$self->{'type'}    = 'no_header';
	$self->{'noCache'} = 1;
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	return if ( $self->{'system'}->{'dbtype'} // q() ) ne 'isolates';
	my $genome_filter = $q->param('genomes') ? 'JOIN seqbin_stats ON id=isolate_id ' : '';
	my $ids = $self->{'datastore'}->run_query( "SELECT id FROM $self->{'system'}->{'view'} $genome_filter ORDER BY id",
		undef, { fetch => 'col_arrayref' } );
	say $_ foreach @$ids;
	return;
}
1;
