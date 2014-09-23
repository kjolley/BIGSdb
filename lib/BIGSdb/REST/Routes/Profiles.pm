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
package BIGSdb::REST::Routes::Profiles;
use strict;
use warnings;
use 5.010;
use POSIX qw(ceil);
use Dancer2 appname => 'BIGSdb::REST::Interface';

#Profile routes
get '/db/:db/schemes/:scheme_id/profiles' => sub {
	my $self = setting('self');
	if ( $self->{'system'}->{'dbtype'} ne 'sequences' ) {
		status(404);
		return { error => "This is not a sequence definition database." };
	}
	my $params = params;
	my ( $db, $scheme_id ) = @{$params}{qw(db scheme_id)};
	my $page = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $set_id = $self->get_set_id;
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		status(400);
		return { error => 'Scheme id must be an integer.' };
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	if ( !$scheme_info ) {
		status(404);
		return { error => "Scheme $scheme_id does not exist." };
	} elsif ( !$scheme_info->{'primary_key'} ) {
		status(404);
		return { error => "Scheme $scheme_id does not have a primary key field." };
	}
	my $profile_view  = ( $self->{'system'}->{'materialized_views'} // '' ) eq 'yes' ? "mv_scheme_$scheme_id" : "scheme_$scheme_id";
	my $profile_count = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM $profile_view");
	my $pages         = ceil( $profile_count / $self->{'page_size'} );
	my $offset        = ( $page - 1 ) * $self->{'page_size'};
	my $pk_info       = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $scheme_info->{'primary_key'} );
	my $qry =
	    "SELECT $scheme_info->{'primary_key'} FROM $profile_view ORDER BY "
	  . ( $pk_info->{'type'} eq 'integer' ? "CAST($scheme_info->{'primary_key'} AS int)" : $scheme_info->{'primary_key'} )
	  . " LIMIT $self->{'page_size'} OFFSET $offset";
	my $profiles = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );

	if ( !@$profiles ) {
		status(404);
		return { error => "No profiles for scheme $scheme_id are defined." };
	}
	my $values = [];
	my $paging = $self->get_paging( "/db/$db/schemes/$scheme_id/profiles", $pages, $page );
	push @$values, { paging => $paging } if $pages > 1;
	my $profile_links = [];
	foreach my $profile_id (@$profiles) {
		push @$profile_links, request->uri_for("/db/$db/schemes/$scheme_id/profiles/$profile_id")->as_string;
	}
	push @$values, { profiles => $profile_links };
	return $values;
};
get '/db/:db/schemes/:scheme_id/profiles/:profile_id' => sub {
	my $self = setting('self');
	if ( $self->{'system'}->{'dbtype'} ne 'sequences' ) {
		status(404);
		return { error => "This is not a sequence definition database." };
	}
	my $params = params;
	my ( $db, $scheme_id, $profile_id ) = @{$params}{qw(db scheme_id profile_id)};
	my $page = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $set_id = $self->get_set_id;
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		status(400);
		return { error => 'Scheme id must be an integer.' };
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	if ( !$scheme_info ) {
		status(404);
		return { error => "Scheme $scheme_id does not exist." };
	} elsif ( !$scheme_info->{'primary_key'} ) {
		status(404);
		return { error => "Scheme $scheme_id does not have a primary key field." };
	}
	my $profile_view = ( $self->{'system'}->{'materialized_views'} // '' ) eq 'yes' ? "mv_scheme_$scheme_id" : "scheme_$scheme_id";
	my $profile =
	  $self->{'datastore'}
	  ->run_query( "SELECT * FROM $profile_view WHERE $scheme_info->{'primary_key'}=?", $profile_id, { fetch => 'row_hashref' } );
	if ( !$profile ) {
		status(404);
		return { error => "Profile $scheme_info->{'primary_key'}-$profile_id does not exist." };
	}
	my $values = [];
	push @$values, { $scheme_info->{'primary_key'} => $profile->{ lc( $scheme_info->{'primary_key'} ) } };
	my $loci         = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $allele_links = [];
	foreach my $locus (@$loci) {
		my $cleaned_locus = $self->clean_locus($locus);
		( my $profile_name = $locus ) =~ s/'/_PRIME_/g;
		my $allele_id = $profile->{ lc($profile_name) };
		push @$allele_links, request->uri_for("/db/$db/alleles/$cleaned_locus/$allele_id")->as_string;
	}
	push @$values, { alleles => $allele_links };
	my $fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach my $field (@$fields) {
		push @$values, { $field => $profile->{ lc($field) } }
		  if defined $profile->{ lc($field) } && $field ne $scheme_info->{'primary_key'};
	}
	my $profile_info =
	  $self->{'datastore'}
	  ->run_query( "SELECT * FROM profiles WHERE scheme_id=? AND profile_id=?", [ $scheme_id, $profile_id ], { fetch => 'row_hashref' } );
	foreach my $attribute (qw(sender curator date_entered datestamp)) {
		if ( $attribute eq 'sender' || $attribute eq 'curator' ) {

			#Don't link to user 0 (setup user)
			push @$values, { $attribute => request->uri_for("/db/$db/users/$profile_info->{$attribute}")->as_string }
			  if $profile_info->{$attribute};
		} else {
			push @$values, { $attribute => $profile_info->{$attribute} };
		}
	}
	return $values;
};
1;
