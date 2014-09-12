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
package BIGSdb::REST::Routes::Schemes;
use strict;
use warnings;
use 5.010;
use Dancer2 appname => 'BIGSdb::REST::Interface';

#Scheme routes
get '/db/:db/schemes' => sub {
	my $self    = setting('self');
	my ($db)    = params->{'db'};
	my $set_id  = $self->get_set_id;
	my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	my $values  = [];
	foreach my $scheme (@$schemes) {
		my $scheme_data = [];
		push @$scheme_data, { $_ => $scheme->{$_} } foreach (qw(id description));
		push @$values, $scheme_data;
	}
	return $values;
};
1;
