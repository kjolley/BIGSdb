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
package BIGSdb::REST::Routes::Resources;
use strict;
use warnings;
use 5.010;
use Dancer2 appname => 'BIGSdb::REST::Interface';
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Rest');

#Resource description routes
get '/' => sub {
	my $self      = setting('self');
	my $resources = $self->get_resources;
	my $values    = [];
	foreach my $resource (@$resources) {
		my $databases = [];
		push @$databases,
		  { name => 'Sequence/profile definitions', href => request->uri_for("/db/$resource->{'seqdef_config'}")->as_string }
		  if defined $resource->{'seqdef_config'};
		push @$databases, { name => 'Isolates', href => request->uri_for("/db/$resource->{'isolates_config'}")->as_string }
		  if defined $resource->{'isolates_config'};
		push @$values, { name => $resource->{'name'}, description => $resource->{'description'}, databases => $databases };
	}
	return $values;
};
get qr{^/db/?+$} => sub {
	redirect '/';
};
get '/db/:db' => sub {
	my $self = setting('self');
	my $db   = params->{'db'};
	if ( !$self->{'system'}->{'db'} ) {
		status(404);
		return { status => 404, error => "Database '$db' does not exist" };
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $count = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM $self->{'system'}->{'view'}");
		return {
			records  => $count,
			isolates => request->uri_for("/db/$db/isolates")->as_string,
			fields   => request->uri_for("/db/$db/fields")->as_string,
			schemes  => request->uri_for("/db/$db/schemes")->as_string,
			loci     => request->uri_for("/db/$db/loci")->as_string,
		};
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
	} else {
		return { title => 'Database configuration is invalid' };
	}
};
1;
