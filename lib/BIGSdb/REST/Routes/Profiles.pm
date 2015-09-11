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
package BIGSdb::REST::Routes::Profiles;
use strict;
use warnings;
use 5.010;
use POSIX qw(ceil);
use Dancer2 appname => 'BIGSdb::REST::Interface';

#Profile routes
get '/db/:db/schemes/:scheme_id/profiles'             => sub { _get_profiles() };
get '/db/:db/schemes/:scheme_id/profiles_csv'         => sub { _get_profiles_csv() };
get '/db/:db/schemes/:scheme_id/profiles/:profile_id' => sub { _get_profile() };

sub _get_profiles {
	my $self = setting('self');
	$self->check_seqdef_database;
	my $params = params;
	my ( $db, $scheme_id ) = @{$params}{qw(db scheme_id)};
	my $page = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $set_id = $self->get_set_id;
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		send_error( 'Scheme id must be an integer.', 400 );
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	if ( !$scheme_info ) {
		send_error( "Scheme $scheme_id does not exist.", 404 );
	} elsif ( !$scheme_info->{'primary_key'} ) {
		send_error( "Scheme $scheme_id does not have a primary key field.", 404 );
	}
	my $profile_view =
	  ( $self->{'system'}->{'materialized_views'} // '' ) eq 'yes' ? "mv_scheme_$scheme_id" : "scheme_$scheme_id";
	my $profile_count = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM $profile_view");
	my $pages         = ceil( $profile_count / $self->{'page_size'} );
	my $offset        = ( $page - 1 ) * $self->{'page_size'};
	my $pk_info       = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $scheme_info->{'primary_key'} );
	my $qry           = "SELECT $scheme_info->{'primary_key'} FROM $profile_view ORDER BY "
	  . (
		$pk_info->{'type'} eq 'integer'
		? "CAST($scheme_info->{'primary_key'} AS int)"
		: $scheme_info->{'primary_key'}
	  );
	$qry .= " LIMIT $self->{'page_size'} OFFSET $offset" if !param('return_all');
	my $profiles = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );

	if ( !@$profiles ) {
		send_error( "No profiles for scheme $scheme_id are defined.", 404 );
	}
	my $values = {};
	my $paging = $self->get_paging( "/db/$db/schemes/$scheme_id/profiles", $pages, $page );
	$values->{'paging'} = $paging if %$paging;
	my $profile_links = [];
	foreach my $profile_id (@$profiles) {
		push @$profile_links, request->uri_for("/db/$db/schemes/$scheme_id/profiles/$profile_id");
	}
	$values->{'profiles'} = $profile_links;
	return $values;
}

sub _get_profiles_csv {
	my $self = setting('self');
	$self->check_seqdef_database;
	my $params = params;
	my ( $db, $scheme_id ) = @{$params}{qw(db scheme_id)};
	my $set_id = $self->get_set_id;
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		send_error( 'Scheme id must be an integer.', 400 );
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	if ( !$scheme_info ) {
		send_error( "Scheme $scheme_id does not exist.", 404 );
	} elsif ( !$primary_key ) {
		send_error( "Scheme $scheme_id does not have a primary key field.", 404 );
	}
	my @heading       = ( $scheme_info->{'primary_key'} );
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my @fields        = ( $scheme_info->{'primary_key'} );
	foreach my $locus (@$loci) {
		my $locus_info = $self->{'datastore'}->get_locus_info( $locus, { set_id => $set_id } );
		my $header_value = $locus_info->{'set_name'} // $locus;
		push @heading, $header_value;
		( my $cleaned = $locus ) =~ s/'/_PRIME_/gx;
		push @fields, $cleaned;
	}
	foreach my $field (@$scheme_fields) {
		next if $field eq $scheme_info->{'primary_key'};
		push @heading, $field;
		push @fields,  $field;
	}
	local $" = "\t";
	my $buffer = "@heading\n";
	local $" = ',';
	my $scheme_view =
	  $self->{'datastore'}->materialized_view_exists($scheme_id) ? "mv_scheme_$scheme_id" : "scheme_$scheme_id";
	my $pk_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	my $qry =
	  "SELECT @fields FROM $scheme_view ORDER BY "
	  . ( $pk_info->{'type'} eq 'integer' ? "CAST($primary_key AS int)" : $primary_key );
	my $data = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref' } );

	if ( !@$data ) {
		send_error( "No profiles for scheme $scheme_id are defined.", 404 );
	}
	local $" = "\t";
	{
		no warnings 'uninitialized';    #scheme field values may be undefined
		foreach my $profile (@$data) {
			$buffer .= "@$profile\n";
		}
	}
	send_file(\$buffer, content_type => 'text/plain; charset=UTF-8');
	return;
}

sub _get_profile {
	my $self = setting('self');
	$self->check_seqdef_database;
	my $params = params;
	my ( $db, $scheme_id, $profile_id ) = @{$params}{qw(db scheme_id profile_id)};
	$self->check_scheme($scheme_id);
	my $page        = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $set_id      = $self->get_set_id;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	if ( !$scheme_info->{'primary_key'} ) {
		send_error( "Scheme $scheme_id does not have a primary key field.", 400 );
	}
	my $profile_view =
	  ( $self->{'system'}->{'materialized_views'} // '' ) eq 'yes' ? "mv_scheme_$scheme_id" : "scheme_$scheme_id";
	my $profile = $self->{'datastore'}->run_query( "SELECT * FROM $profile_view WHERE $scheme_info->{'primary_key'}=?",
		$profile_id, { fetch => 'row_hashref' } );
	if ( !$profile ) {
		send_error( "Profile $scheme_info->{'primary_key'}-$profile_id does not exist.", 404 );
	}
	my $values       = {};
	my $loci         = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $allele_links = [];
	foreach my $locus (@$loci) {
		my $cleaned_locus = $self->clean_locus($locus);
		( my $profile_name = $locus ) =~ s/'/_PRIME_/gx;
		my $allele_id = $profile->{ lc($profile_name) };
		push @$allele_links, request->uri_for("/db/$db/loci/$cleaned_locus/alleles/$allele_id");
	}
	$values->{'alleles'} = $allele_links;
	my $fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach my $field (@$fields) {
		next if !defined $profile->{ lc($field) };
		my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		if ( $field_info->{'type'} eq 'integer' ) {
			$values->{$field} = int( $profile->{ lc($field) } );
		} else {
			$values->{$field} = $profile->{ lc($field) };
		}
	}
	my $profile_info = $self->{'datastore'}->run_query(
		'SELECT * FROM profiles WHERE scheme_id=? AND profile_id=?',
		[ $scheme_id, $profile_id ],
		{ fetch => 'row_hashref' }
	);
	foreach my $attribute (qw(sender curator date_entered datestamp)) {
		if ( $attribute eq 'sender' || $attribute eq 'curator' ) {

			#Don't link to user 0 (setup user)
			$values->{$attribute} = request->uri_for("/db/$db/users/$profile_info->{$attribute}")
			  if $profile_info->{$attribute};
		} else {
			$values->{$attribute} = $profile_info->{$attribute};
		}
	}
	return $values;
}
1;
