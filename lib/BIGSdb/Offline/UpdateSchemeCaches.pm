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
	my $schemes  = [];
	my $cschemes = [];
	if ( $self->{'options'}->{'schemes'} ) {
		@$schemes = split /,/x, $self->{'options'}->{'schemes'};
		foreach my $scheme_id (@$schemes) {
			if ( !BIGSdb::Utils::is_int($scheme_id) ) {
				die "Scheme id must be an integer - $scheme_id is not.\n";
			}
			my $cschemes_using_this_scheme =
			  $self->{'datastore'}->run_query( 'SELECT id FROM classification_schemes WHERE scheme_id=?',
				$scheme_id, { fetch => 'col_arrayref', cache => 'get_cschemes_from_scheme' } );
			push @$cschemes, @$cschemes_using_this_scheme if @$cschemes_using_this_scheme;
		}
	} else {
		$schemes =
		  $self->{'datastore'}
		  ->run_query( 'SELECT id FROM schemes WHERE dbase_name IS NOT NULL AND dbase_table IS NOT NULL ORDER BY id',
			undef, { fetch => 'col_arrayref' } );
		$cschemes =
		  $self->{'datastore'}
		  ->run_query( 'SELECT id FROM classification_schemes', undef, { fetch => 'col_arrayref' } );
	}
	foreach my $scheme_id (@$schemes) {
		$scheme_id =~ s/\s//gx;
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		if ( !$scheme_info ) {
			say "Scheme $scheme_id does not exist";
			next;
		}
		if ( !defined $scheme_info->{'primary_key'} ) {
			say "Scheme $scheme_id ($scheme_info->{'name'}) does not have a primary key - skipping.";
			next;
		}
		my $method = $self->{'options'}->{'method'} // 'full';
		say "Updating scheme $scheme_id cache ($scheme_info->{'name'}) - method: $method"
		  if !$self->{'options'}->{'q'};
		$self->{'datastore'}->create_temp_isolate_scheme_fields_view( $scheme_id, { cache => 1, method => $method } );
		$self->{'datastore'}->create_temp_scheme_status_table( $scheme_id, { cache => 1, method => $method } );
	}
	foreach my $cscheme_id (@$cschemes){
		$self->{'datastore'}->create_temp_cscheme_table($cscheme_id,{ cache => 1});
	}
	return;
}
1;
