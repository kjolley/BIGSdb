#Written by Keith Jolley
#Copyright (c) 2018, University of Oxford
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
package BIGSdb::REST::Routes::Sequences;
use strict;
use warnings;
use 5.010;
use JSON;
use Dancer2 appname => 'BIGSdb::REST::Interface';
get '/db/:db/sequences' => sub { _get_sequences() };

sub _get_sequences {
	my $self = setting('self');
	my ($db) = params->{'db'};
	$self->check_seqdef_database;
	my ($count, $last_updated) = $self->{'datastore'}->run_query('SELECT SUM(allele_count),MAX(datestamp) FROM locus_stats');
	my $values = { loci => request->uri_for("/db/$db/loci"), records => int($count) };
	$values->{'last_updated'} = $last_updated if $last_updated;
	return $values;
}
1;
