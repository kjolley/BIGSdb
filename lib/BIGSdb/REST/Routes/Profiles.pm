#Written by Keith Jolley
#Copyright (c) 2014-2024, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
use Dancer2 appname => 'BIGSdb::REST::Interface';

#Profile routes
sub setup_routes {
	my $self = setting('self');
	foreach my $dir ( @{ setting('api_dirs') } ) {
		get "$dir/db/:db/schemes/:scheme_id/profiles"     => sub { _get_profiles() };
		get "$dir/db/:db/schemes/:scheme_id/profiles_csv" => sub {
			header content_type => 'text/plain; charset=UTF-8';
			delayed { _get_profiles_csv(); done };
		};
		get "$dir/db/:db/schemes/:scheme_id/profiles/:profile_id" => sub { _get_profile() };
	}
	return;
}

sub _get_profiles {
	my $self = setting('self');
	if ( ( request->accept // q() ) =~ /(tsv|csv)/x ) {
		_get_profiles_csv();
	}
	$self->check_seqdef_database;
	my $params = params;
	my ( $db, $scheme_id ) = @{$params}{qw(db scheme_id)};
	my $allowed_filters = [qw(added_after added_reldate added_on updated_after updated_reldate updated_on)];
	my $set_id          = $self->get_set_id;
	$self->check_scheme( $scheme_id, { pk => 1 } );
	my $subdir           = setting('subdir');
	my $scheme_info      = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $date_restriction = $self->{'datastore'}->get_date_restriction;
	my $date_restriction_clause =
	  ( !$self->{'username'} && $date_restriction ) ? qq( WHERE date_entered<='$date_restriction') : q();
	my $qry = $self->add_filters( "SELECT COUNT(*),max(datestamp) FROM $scheme_warehouse$date_restriction_clause",
		$allowed_filters );
	my ( $profile_count, $last_updated ) = $self->{'datastore'}->run_query($qry);
	my $page_values = $self->get_page_values($profile_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};
	my $pk_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $scheme_info->{'primary_key'} );
	$qry = $self->add_filters( "SELECT $scheme_info->{'primary_key'} FROM $scheme_warehouse$date_restriction_clause",
		$allowed_filters );
	$qry .= ' ORDER BY '
	  . (
		$pk_info->{'type'} eq 'integer'
		? "CAST($scheme_info->{'primary_key'} AS int)"
		: $scheme_info->{'primary_key'}
	  );
	$qry .= " LIMIT $self->{'page_size'} OFFSET $offset" if !param('return_all');
	my $profiles = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	my $values   = { records => int($profile_count) };
	$values->{'last_updated'} = $last_updated if defined $last_updated;
	my $path   = $self->get_full_path( "$subdir/db/$db/schemes/$scheme_id/profiles", $allowed_filters );
	my $paging = $self->get_paging( $path, $pages, $page, $offset );
	$values->{'paging'} = $paging if %$paging;
	my $profile_links = [];

	foreach my $profile_id (@$profiles) {
		push @$profile_links, request->uri_for("$subdir/db/$db/schemes/$scheme_id/profiles/$profile_id");
	}
	$values->{'profiles'} = $profile_links;
	my $message = $self->get_date_restriction_message;
	$values->{'message'} = $message if $message;
	return $values;
}

sub _get_profiles_csv {
	my $self = setting('self');
	$self->reconnect;
	$self->check_seqdef_database;
	my $params = params;
	my ( $db, $scheme_id ) = @{$params}{qw(db scheme_id)};
	my $allowed_filters = [qw(added_after added_reldate added_on updated_after updated_reldate updated_on)];
	$self->check_scheme( $scheme_id, { pk => 1 } );
	my $set_id        = $self->get_set_id;
	my $scheme_info   = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	my $primary_key   = $scheme_info->{'primary_key'};
	my @heading       = ( $scheme_info->{'primary_key'} );
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my @fields        = ( $scheme_info->{'primary_key'}, 'profile' );
	my $locus_indices = $self->{'datastore'}->get_scheme_locus_indices($scheme_id);
	my @order;
	my $limit = 10000;

	foreach my $locus (@$loci) {
		my $locus_info   = $self->{'datastore'}->get_locus_info( $locus, { set_id => $set_id } );
		my $header_value = $locus_info->{'set_name'} // $locus;
		push @heading, $header_value;
		push @order,   $locus_indices->{$locus};
	}
	foreach my $field (@$scheme_fields) {
		next if $field eq $scheme_info->{'primary_key'};
		push @heading, $field;
		push @fields,  $field;
	}
	my $lincodes_defined = $self->{'datastore'}->are_lincodes_defined($scheme_id);
	my $lincode_fields   = [];
	if ($lincodes_defined) {
		push @heading, 'LINcode';
		$lincode_fields =
		  $self->{'datastore'}
		  ->run_query( 'SELECT field FROM lincode_fields WHERE scheme_id=? ORDER BY display_order,field',
			$scheme_id, { fetch => 'col_arrayref' } );
		local $" = qq(\t);
		push @heading, @$lincode_fields;
	}
	local $" = "\t";
	content "@heading\n";
	local $" = ',';
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $date_restriction = $self->{'datastore'}->get_date_restriction;
	my $date_restriction_clause =
	  ( !$self->{'username'} && $date_restriction ) ? qq( WHERE date_entered<='$date_restriction') : q();
	my $pk_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	my $qry = $self->add_filters( "SELECT @fields FROM $scheme_warehouse$date_restriction_clause", $allowed_filters );
	$qry .= ' ORDER BY ' . ( $pk_info->{'type'} eq 'integer' ? "CAST($primary_key AS int)" : $primary_key );
	$qry .= " LIMIT $limit OFFSET ?";
	my $profiles_exist =
	  $self->{'datastore'}->run_query("SELECT EXISTS(SELECT COUNT(*) FROM $scheme_warehouse$date_restriction_clause)");

	if ( !$profiles_exist ) {
		send_error( "No profiles for scheme $scheme_id are defined.", 404 );
	}
	my $lincodes;
	if ($lincodes_defined) {
		$lincodes = $self->{'datastore'}->run_query( 'SELECT profile_id,lincode FROM lincodes WHERE scheme_id=?',
			$scheme_id, { fetch => 'all_hashref', key => 'profile_id' } );
	}
	local $" = "\t";
	my $continue = 1;
	my $offset   = 0;
	while ($continue) {
		no warnings 'uninitialized';    #scheme field values may be undefined
		my $definitions = $self->{'datastore'}->run_query( $qry, $offset,
			{ fetch => 'all_arrayref', cache => 'Profiles::get_profiles_csv::get_profiles' } );
		foreach my $definition (@$definitions) {
			my $pk      = shift @$definition;
			my $profile = shift @$definition;
			content qq($pk\t@$profile[@order]);
			content qq(\t@$definition) if @$scheme_fields > 1;
			if ($lincodes_defined) {
				my $lincode = $lincodes->{$pk}->{'lincode'} // [];
				local $" = q(_);
				content qq(\t@$lincode);
				content _print_lincode_fields( $scheme_id, $lincode_fields, qq(@$lincode) );
			}
			content qq(\n);
		}
		$offset += $limit;
		$continue = 0 if !@$definitions;
	}
	return;
}

sub _print_lincode_fields {
	my ( $scheme_id, $fields, $lincode ) = @_;

	#Using $self->{'cache'} would be persistent between calls even when calling another database.
	#Datastore is destroyed after call so $self->{'datastore'}->{'prefix_cache'} is safe to
	#cache only for duration of call.
	my $self = setting('self');
	if ( !$self->{'datastore'}->{'prefix_cache'} ) {
		my $data = $self->{'datastore'}->run_query( 'SELECT * FROM lincode_prefixes WHERE scheme_id=?',
			$scheme_id, { fetch => 'all_arrayref', slice => {} } );
		foreach my $record (@$data) {
			$self->{'datastore'}->{'prefix_cache'}->{ $record->{'field'} }->{ $record->{'prefix'} } =
			  $record->{'value'};
		}
	}
	my $buffer = q();
	foreach my $field (@$fields) {
		if ( !$lincode ) {
			$buffer .= qq(\t);
			next;
		}
		my @prefixes = keys %{ $self->{'datastore'}->{'prefix_cache'}->{$field} };
		my @values;
		foreach my $prefix (@prefixes) {
			if ( $lincode eq $prefix || $lincode =~ /^${prefix}_/x ) {
				push @values, $self->{'datastore'}->{'prefix_cache'}->{$field}->{$prefix};
			}
		}
		@values = sort @values;
		local $" = q(; );
		$buffer .= qq(\t@values);
	}
	return $buffer;
}

sub _get_profile {
	my $self = setting('self');
	$self->check_seqdef_database;
	my $params = params;
	my ( $db, $scheme_id, $profile_id ) = @{$params}{qw(db scheme_id profile_id)};
	$self->check_scheme($scheme_id);
	my $page        = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $set_id      = $self->get_set_id;
	my $subdir      = setting('subdir');
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );

	if ( !$scheme_info->{'primary_key'} ) {
		send_error( "Scheme $scheme_id does not have a primary key field.", 400 );
	}
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $profile =
	  $self->{'datastore'}->run_query( "SELECT * FROM $scheme_warehouse WHERE $scheme_info->{'primary_key'}=?",
		$profile_id, { fetch => 'row_hashref' } );
	if ( !$profile ) {
		send_error( "Profile $scheme_info->{'primary_key'}-$profile_id does not exist.", 404 );
	}
	my $date_restriction = $self->{'datastore'}->get_date_restriction;
	if ( !$self->{'username'} && $date_restriction && $date_restriction lt $profile->{'date_entered'} ) {
		my $message = $self->get_date_restriction_message;
		send_error( $message, 403 );
	}
	my $values        = {};
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $allele_links  = [];
	my $locus_indices = $self->{'datastore'}->get_scheme_locus_indices($scheme_id);
	foreach my $locus (@$loci) {
		my $cleaned_locus = $self->clean_locus($locus);
		my $allele_id     = $profile->{'profile'}->[ $locus_indices->{$locus} ];
		push @$allele_links, request->uri_for("$subdir/db/$db/loci/$cleaned_locus/alleles/$allele_id");
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
			$values->{$attribute} = request->uri_for("$subdir/db/$db/users/$profile_info->{$attribute}")
			  if $profile_info->{$attribute};
		} else {
			$values->{$attribute} = $profile_info->{$attribute};
		}
	}
	my $classification_schemes =
	  $self->{'datastore'}->run_query( 'SELECT * FROM classification_schemes WHERE scheme_id=?',
		$scheme_id, { fetch => 'all_arrayref', slice => {} } );
	my $cs_values = {};
	foreach my $cs_scheme (@$classification_schemes) {
		my $group = $self->{'datastore'}->run_query(
			'SELECT group_id FROM classification_group_profiles WHERE (cg_scheme_id,scheme_id,profile_id)=(?,?,?)',
			[ $cs_scheme->{'id'}, $scheme_id, $profile_id ],
			{ cache => 'Profiles::get_profile::get_group' }
		);
		next if !defined $group;
		my $obj           = { href => request->uri_for("$subdir/db/$db/classification_schemes/$cs_scheme->{'id'}") };
		my $profile_count = $self->{'datastore'}->run_query(
			'SELECT COUNT(*) FROM classification_group_profiles WHERE (cg_scheme_id, group_id)=(?,?)',
			[ $cs_scheme->{'id'}, $group ],
			{ cache => 'Profiles::get_profile::get_profile_count' }
		);
		$fields =
		  $self->{'datastore'}->run_query( 'SELECT field,type FROM classification_group_fields WHERE cg_scheme_id=?',
			$cs_scheme->{'id'}, { fetch => 'all_arrayref', slice => {}, cache => 'Profiles:get_profile:get_fields' } );
		my $field_obj = {};
		foreach my $field (@$fields) {
			my $value = $self->{'datastore'}->run_query(
				'SELECT value FROM classification_group_field_values WHERE (cg_scheme_id,field,group_id)=(?,?,?)',
				[ $cs_scheme->{'id'}, $field->{'field'}, $group ],
				{ cache => 'Profiles::get_profile::get_field_value' }
			);
			if ( defined $value ) {
				$field_obj->{ $field->{'field'} } = $field->{'type'} eq 'integer' ? int($value) : $value;
			}
		}
		my $group_obj = {
			group    => int($group),
			records  => $profile_count,
			profiles => request->uri_for("$subdir/db/$db/classification_schemes/$cs_scheme->{'id'}/groups/$group")
		};
		$group_obj->{'fields'}               = $field_obj if keys %$field_obj;
		$obj->{'group'}                      = $group_obj;
		$cs_values->{ $cs_scheme->{'name'} } = $obj;
	}
	$values->{'classification_schemes'} = $cs_values if keys %$cs_values;
	my $lincode_scheme = $self->{'datastore'}->are_lincodes_defined($scheme_id);
	if ($lincode_scheme) {
		my $lincode =
		  $self->{'datastore'}
		  ->run_query( 'SELECT lincode FROM lincodes WHERE (scheme_id,profile_id)=(?,?)', [ $scheme_id, $profile_id ] );
		if ($lincode) {
			local $" = q(_);
			$values->{'LINcode'} = qq(@$lincode);
			my $lincode_fields =
			  $self->{'datastore'}
			  ->run_query( 'SELECT field FROM lincode_fields WHERE scheme_id=? ORDER BY display_order,field',
				$scheme_id, { fetch => 'col_arrayref' } );
			my $join_table =
				q[lincodes LEFT JOIN lincode_prefixes ON lincodes.scheme_id=lincode_prefixes.scheme_id AND (]
			  . q[array_to_string(lincodes.lincode,'_') LIKE (REPLACE(lincode_prefixes.prefix,'_','\_') || E'\\\_' || '%') ]
			  . q[OR array_to_string(lincodes.lincode,'_') = lincode_prefixes.prefix)];
			foreach my $field (@$lincode_fields) {
				my $type =
				  $self->{'datastore'}->run_query( 'SELECT type FROM lincode_fields WHERE (scheme_id,field)=(?,?)',
					[ $scheme_id, $field ] );
				my $order          = $type eq 'integer' ? 'CAST(value AS integer)' : 'value';
				my $lincode_values = $self->{'datastore'}->run_query(
					"SELECT value FROM $join_table WHERE (lincodes.scheme_id,lincode_prefixes.field,lincodes.lincode)="
					  . "(?,?,?) ORDER BY $order",
					[ $scheme_id, $field, $lincode ],
					{ fetch => 'col_arrayref' }
				);
				next if !@$lincode_values;
				( my $cleaned = $field ) =~ tr/_/ /;
				$values->{$cleaned} = @$lincode_values == 1 ? $lincode_values->[0] : $lincode_values;
			}
		}
	}
	return $values;
}
1;
