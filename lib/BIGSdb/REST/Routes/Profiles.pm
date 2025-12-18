#Written by Keith Jolley
#Copyright (c) 2014-2025, University of Oxford
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
use List::MoreUtils qw(uniq);
use 5.010;
use Dancer2 appname => 'BIGSdb::REST::Interface';

#Profile routes
sub setup_routes {
	my $self = setting('self');
	foreach my $dir ( @{ setting('api_dirs') } ) {
		get "$dir/db/:db/schemes/:scheme_id/profiles"     => sub { _get_profiles() };
		get "$dir/db/:db/schemes/:scheme_id/lincodes"     => sub { _get_lincodes() };
		get "$dir/db/:db/schemes/:scheme_id/profiles_csv" => sub {
			_check_scheme();    #Need to do this before setting header.
			response_header content_type => 'text/plain; charset=UTF-8';
			delayed { _get_profiles_csv(); done };
		};
		get "$dir/db/:db/schemes/:scheme_id/profiles/:profile_id" => sub { _get_profile() };
	}
	return;
}

sub _check_scheme {
	my $self = setting('self');
	$self->check_seqdef_database;
	my $params = params;
	my ( $db, $scheme_id ) = @{$params}{qw(db scheme_id)};
	$self->check_scheme( $scheme_id, { pk => 1 } );
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
	my $records = [];

	foreach my $profile_id (@$profiles) {
		if ( params->{'include_records'} ) {
			my $record = _get_profile( $db, $scheme_id, $profile_id );
			push @$records, $record;
		} else {
			push @$records, request->uri_for("$subdir/db/$db/schemes/$scheme_id/profiles/$profile_id");
		}
	}
	$values->{'profiles'} = $records;
	my $message = $self->get_date_restriction_message;
	$values->{'message'} = $message if $message;
	return $values;
}

sub _get_lincodes {
	my $self = setting('self');
	$self->check_seqdef_database;
	my $params = params;
	my ( $db, $scheme_id ) = @{$params}{qw(db scheme_id)};

	my $allowed_filters = [qw(added_after added_reldate added_on updated_after updated_reldate updated_on)];
	$self->check_scheme( $scheme_id, { pk => 1 } );
	my $exists =
	  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM lincode_schemes WHERE scheme_id=?)', $scheme_id );
	if ( !$exists ) {
		send_error( "Scheme $scheme_id does not have a LIN code scheme.", 404 );
	}
	my $subdir           = setting('subdir');
	my $date_restriction = $self->{'datastore'}->get_date_restriction;
	my $date_restriction_clause =
	  ( !$self->{'username'} && $date_restriction ) ? qq( AND p.date_entered<='$date_restriction') : q();
	my $set_id           = $self->get_set_id;
	my $scheme_info      = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	my $pk_info          = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $scheme_info->{'primary_key'} );
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $qry              = $self->add_filters(
		'SELECT COUNT(*),max(p.datestamp) FROM lincodes l JOIN profiles p ON '
		  . '(l.scheme_id,l.profile_id)=(p.scheme_id,p.profile_id) WHERE '
		  . "p.scheme_id=$scheme_id$date_restriction_clause",
		$allowed_filters
	);
	my ( $profile_count, $last_updated ) = $self->{'datastore'}->run_query($qry);

	my $page_values = $self->get_page_values($profile_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};

	$qry = $self->add_filters(
		'SELECT l.profile_id,l.lincode,l.datestamp FROM lincodes l JOIN profiles p ON '
		  . '(l.scheme_id,l.profile_id)=(p.scheme_id,p.profile_id) '
		  . "WHERE p.scheme_id=$scheme_id$date_restriction_clause",
		$allowed_filters
	);
	$qry .= ' ORDER BY '
	  . (
		$pk_info->{'type'} eq 'integer'
		? 'CAST(l.profile_id AS int)'
		: 'l.profile_id'
	  );
	$qry .= " LIMIT $self->{'page_size'} OFFSET $offset" if !param('return_all');
	my $lincodes = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	my $values   = { records => int($profile_count) };
	$values->{'last_updated'} = $last_updated if defined $last_updated;
	my $path   = $self->get_full_path( "$subdir/db/$db/schemes/$scheme_id/lincodes", $allowed_filters );
	my $paging = $self->get_paging( $path, $pages, $page, $offset );
	$values->{'paging'} = $paging if %$paging;
	my $records = [];
	local $" = q(_);

	foreach my $lincode (@$lincodes) {
		push @$records,
		  {
			$scheme_info->{'primary_key'} =>
			  ( $pk_info->{'type'} eq 'integer' ? int( $lincode->{'profile_id'} ) : $lincode->{'profile_id'} ),
			lincode   => qq(@{$lincode->{'lincode'}}),
			datestamp => $lincode->{'datestamp'}
		  };
	}
	$values->{'lincodes'} = $records;
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
	my $set_id          = $self->get_set_id;
	my $scheme_info     = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	my $primary_key     = $scheme_info->{'primary_key'};
	my @heading         = ( $scheme_info->{'primary_key'} );
	my $loci            = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields   = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my @fields          = ( $scheme_info->{'primary_key'}, 'profile' );
	my $locus_indices   = $self->{'datastore'}->get_scheme_locus_indices($scheme_id);
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

	#Get username stored in datastore as $self->{'username'} gets cleared because of delayed call.
	my $username = $self->{'datastore'}->get_username;
	my $date_restriction_clause =
	  ( !$username && $date_restriction ) ? qq( WHERE date_entered<='$date_restriction') : q();
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
	my $continue        = 1;
	my $offset          = 0;
	my $date_restricted = $date_restriction ? '_restricted' : q();
	while ($continue) {
		no warnings 'uninitialized';    #scheme field values may be undefined
		my $definitions = $self->{'datastore'}->run_query(
			$qry, $offset,
			{
				fetch => 'all_arrayref',
				cache => "Profiles::get_profiles_csv::get_profiles_${scheme_id}_$date_restricted"
			}
		);
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
	my $self = setting('self');

	#Using $self->{'cache'} would be persistent between calls even when calling another database.
	#Datastore is destroyed after call so $self->{'datastore'}->{'prefix_cache'} is safe to
	#cache only for duration of call.
	unless ( $self->{'datastore'}->{'prefix_cache'} ) {
		my $data = $self->{'datastore'}->run_query( 'SELECT * FROM lincode_prefixes WHERE scheme_id=?',
			$scheme_id, { fetch => 'all_arrayref', slice => {} } );
		my $cache = {};
		foreach my $record (@$data) {
			if ( !defined $cache->{ $record->{'field'} }->{ $record->{'value'} } ) {
				$cache->{ $record->{'field'} }->{ $record->{'value'} } = [];
			}
			push @{ $cache->{ $record->{'field'} }->{ $record->{'prefix'} } }, $record->{'value'};
		}
		$self->{'datastore'}->{'prefix_cache'} = $cache;
	}

	my $buffer = q();
	my $cache  = $self->{'datastore'}->{'prefix_cache'};

	my @prefixes_for_this_lincode;
	my @bin_values = split /_/, $lincode;
	my $prefix     = shift @bin_values;
	push @prefixes_for_this_lincode, $prefix;
	foreach my $bin_value (@bin_values) {
		$prefix .= "_$bin_value";
		push @prefixes_for_this_lincode, $prefix;
	}
	foreach my $field (@$fields) {
		unless ($lincode) {
			$buffer .= "\t";
			next;
		}
		my $prefixes = $cache->{$field};
		unless ($prefixes) {
			$buffer .= "\t";
			next;
		}

		my @values;
		foreach my $prefix (@prefixes_for_this_lincode) {
			next if !defined $cache->{$field}->{$prefix};
			push @values, @{ $cache->{$field}->{$prefix} };
		}
		@values = uniq @values;
		@values = sort @values if @values > 1;
		local $" = '; ';
		$buffer .= "\t@values";
	}
	return $buffer;
}

sub _get_profile {
	my ( $db, $scheme_id, $profile_id ) = @_;
	my $self = setting('self');
	$self->check_seqdef_database;
	my $params = params;
	if ( !defined $db ) {
		( $db, $scheme_id, $profile_id ) = @{$params}{qw(db scheme_id profile_id)};
	}
	if ( !$self->{'datastore'}->{'scheme_checked'}->{$scheme_id} ) {
		$self->check_scheme( $scheme_id, { pk => 1 } );
		$self->{'datastore'}->{'scheme_checked'}->{$scheme_id} = 1;
	}

	my $page   = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $set_id = $self->get_set_id;
	my $subdir = setting('subdir');
	if ( !defined $self->{'datastore'}->{'scheme_info_cache_pk'}->{$scheme_id} ) {
		$self->{'datastore'}->{'scheme_info_cache_pk'}->{$scheme_id} =
		  $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	}
	my $scheme_info      = $self->{'datastore'}->{'scheme_info_cache_pk'}->{$scheme_id};
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $profile =
	  $self->{'datastore'}->run_query( "SELECT * FROM $scheme_warehouse WHERE $scheme_info->{'primary_key'}=?",
		$profile_id, { fetch => 'row_hashref', cache => "Profiles::get_profile::$scheme_warehouse" } );

	if ( !$profile ) {
		send_error( "Profile $scheme_info->{'primary_key'}-$profile_id does not exist.", 404 );
	}
	my $date_restriction = $self->{'datastore'}->get_date_restriction;
	if ( !$self->{'username'} && $date_restriction && $date_restriction lt $profile->{'date_entered'} ) {
		my $message = $self->get_date_restriction_message;
		send_error( $message, 403 );
	}
	my $values       = {};
	my $loci         = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $allele_links = [];
	if ( !defined $self->{'datastore'}->{'locus_indices'}->{$scheme_id} ) {
		$self->{'datastore'}->{'locus_indices'}->{$scheme_id} =
		  $self->{'datastore'}->get_scheme_locus_indices($scheme_id);
	}
	my $locus_indices = $self->{'datastore'}->{'locus_indices'}->{$scheme_id};
	foreach my $locus (@$loci) {
		my $cleaned_locus = $self->clean_locus($locus);
		my $allele_id     = $profile->{'profile'}->[ $locus_indices->{$locus} ];
		push @$allele_links, params->{'allele_ids_only'}
		  ? { locus => $cleaned_locus, allele_id => $allele_id }
		  : request->uri_for("$subdir/db/$db/loci/$cleaned_locus/alleles/$allele_id");
	}
	$values->{'alleles'} = $allele_links;
	my $fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach my $field (@$fields) {
		next if !defined $profile->{ lc($field) };
		if ( !defined $self->{'datastore'}->{'scheme_field_info_cache'}->{$scheme_id}->{$field} ) {
			$self->{'datastore'}->{'scheme_field_info_cache'}->{$scheme_id}->{$field} =
			  $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		}
		my $field_info = $self->{'datastore'}->{'scheme_field_info_cache'}->{$scheme_id}->{$field};
		if ( $field_info->{'type'} eq 'integer' ) {
			$values->{$field} = int( $profile->{ lc($field) } );
		} else {
			$values->{$field} = $profile->{ lc($field) };
		}
	}
	my $profile_info = $self->{'datastore'}->run_query(
		'SELECT * FROM profiles WHERE scheme_id=? AND profile_id=?',
		[ $scheme_id, $profile_id ],
		{ fetch => 'row_hashref', cache => 'Profiles::get_profile::profile_info' }
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
	if ( !defined $self->{'datastore'}->{'classification_schemes_cache'}->{$scheme_id} ) {
		$self->{'datastore'}->{'classification_schemes_cache'}->{$scheme_id} =
		  $self->{'datastore'}->run_query( 'SELECT * FROM classification_schemes WHERE scheme_id=?',
			$scheme_id, { fetch => 'all_arrayref', slice => {} } );
	}
	my $classification_schemes =
	  $self->{'datastore'}->{'classification_schemes_cache'}->{$scheme_id};
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
