#!/usr/bin/perl
#Create scheme profile caches in an isolate database
#
#Written by Keith Jolley
#Copyright (c) 2014-2015, University of Oxford
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
package BIGSdb::Offline::UpdateSchemeCaches;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Offline::Script);

sub run_script {
	my ($self) = @_;
	die "No connection to database (check logs).\n" if !defined $self->{'db'};
	die "This script can only be run against an isolate database.\n"
	  if ( $self->{'system'}->{'dbtype'} // '' ) ne 'isolates';
	my $schemes =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id FROM schemes WHERE dbase_name IS NOT NULL AND dbase_table IS NOT NULL ORDER BY id',
		undef, { fetch => 'col_arrayref' } );
	foreach my $scheme_id (@$schemes) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		if ( !defined $scheme_info->{'primary_key'} ) {
			say "Scheme $scheme_id ($scheme_info->{'description'}) does not have a primary key - skipping.";
			next;
		}
		my $method = $self->{'options'}->{'method'} // 'full';
		say "Updating scheme $scheme_id cache ($scheme_info->{'description'}) - method: $method"
		  if !$self->{'options'}->{'q'};
		$self->{'datastore'}->create_temp_isolate_scheme_fields_view( $scheme_id, { cache => 1, method => $method } );
		$self->{'datastore'}->create_temp_scheme_status_table( $scheme_id, { cache => 1 } );
	}
	return;
}
1;
