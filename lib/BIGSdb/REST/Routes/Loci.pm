#Written by Keith Jolley
#Copyright (c) 2014-2020, University of Oxford
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
package BIGSdb::REST::Routes::Loci;
use strict;
use warnings;
use 5.010;
use JSON;
use MIME::Base64;
use Dancer2 appname => 'BIGSdb::REST::Interface';

#Locus routes
sub setup_routes {
	my $self = setting('self');
	foreach my $dir ( @{ setting('api_dirs') } ) {
		get "$dir/db/:db/loci"                  => sub { _get_loci() };
		get "$dir/db/:db/loci/:locus"           => sub { _get_locus() };
		post "$dir/db/:db/loci/:locus/sequence" => sub { _query_locus_sequence() };
		post "$dir/db/:db/sequence"             => sub { _query_sequence() };
	}
	return;
}

sub _get_loci {
	my $self   = setting('self');
	my ($db)   = params->{'db'};
	my $subdir = setting('subdir');
	my $allowed_filters =
	  $self->{'system'}->{'dbtype'} eq 'sequences' ? [qw(alleles_added_after alleles_updated_after)] : [];
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? ' WHERE (id IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes '
	  . "WHERE set_id=$set_id)) OR id IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';
	my $count_qry   = $self->add_filters( "SELECT COUNT(*) FROM loci$set_clause", $allowed_filters );
	my $locus_count = $self->{'datastore'}->run_query($count_qry);
	my $page_values = $self->get_page_values($locus_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};
	my $qry = $self->add_filters( "SELECT id FROM loci$set_clause", $allowed_filters );
	$qry .= ' ORDER BY id';
	$qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !params->{'return_all'};
	my $loci = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	my $values = { records => int($locus_count) };

	if (@$loci) {
		my $path = $self->get_full_path( "$subdir/db/$db/loci", $allowed_filters );
		my $paging = $self->get_paging( $path, $pages, $page, $offset );
		$values->{'paging'} = $paging if %$paging;
		my @links;
		foreach my $locus (@$loci) {
			my $cleaned_locus = $self->clean_locus($locus);
			push @links, request->uri_for("$subdir/db/$db/loci/$cleaned_locus");
		}
		$values->{'loci'} = \@links;
	}
	return $values;
}

sub _get_locus {
	my $self = setting('self');
	my ( $db, $locus ) = ( params->{'db'}, params->{'locus'} );
	my $set_id     = $self->get_set_id;
	my $subdir     = setting('subdir');
	my $locus_name = $locus;
	my $set_name   = $locus_name;
	if ($set_id) {
		$locus_name = $self->{'datastore'}->get_set_locus_real_id( $locus, $set_id );
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus_name);
	if ( !$locus_info ) {
		send_error( "Locus $locus does not exist.", 404 );
	}
	my $values = {};
	my %boolean_field = map { $_ => 1 } qw(length_varies coding_sequence);
	foreach my $field (
		qw(data_type allele_id_format allele_id_regex common_name length length_varies min_length max_length
		coding_sequence genome_position orf reference_sequence)
	  )
	{
		if ( $boolean_field{$field} ) {
			$values->{$field} = $locus_info->{$field} ? JSON::true : JSON::false;
		} else {
			$values->{$field} = $locus_info->{$field} if defined $locus_info->{$field};
		}
	}
	$values->{'id'} = $set_name;

	#Aliases
	my $aliases = $self->{'datastore'}->run_query( 'SELECT alias FROM locus_aliases WHERE locus=? ORDER BY alias',
		$locus_name, { fetch => 'col_arrayref' } );
	$values->{'aliases'} = $aliases if @$aliases;
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		_get_extended_attributes( $values, $locus_name );
		_get_description( $values, $locus_name );
		_get_curators( $values, $locus_name );
	} else {

		#Isolate databases - attempt to link to seqdef definitions
		my $seqdef_definition = _get_seqdef_definition($locus_name);
		if ($seqdef_definition) {
			$values->{'seqdef_definition'} = request->uri_for($seqdef_definition);
		}
	}
	my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	my $scheme_member_list = [];
	foreach my $scheme (@$schemes) {
		my $is_member = $self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM scheme_members WHERE (scheme_id,locus)=(?,?))',
			[ $scheme->{'id'}, $locus_name ],
			{ cache => 'Loci::scheme_member' }
		);
		if ($is_member) {
			push @$scheme_member_list,
			  {
				scheme      => request->uri_for("$subdir/db/$db/schemes/$scheme->{'id'}"),
				description => $scheme->{'name'}
			  };
		}
	}
	if (@$scheme_member_list) {
		$values->{'schemes'} = $scheme_member_list;
	}
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		if ( $self->{'datastore'}->sequences_exist($locus_name) ) {
			$values->{'alleles'}       = request->uri_for("$subdir/db/$db/loci/$set_name/alleles");
			$values->{'alleles_fasta'} = request->uri_for("$subdir/db/$db/loci/$set_name/alleles_fasta");
		}
	}
	return $values;
}

sub _query_locus_sequence {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $locus, $sequence, $details, $base64, $partial_linked_data ) =
	  @{$params}{qw(db locus sequence details base64 partial_linked_data)};
	$self->check_post_payload;
	$self->check_load_average;
	$self->check_seqdef_database;
	$sequence = decode_base64($sequence) if $base64;
	my $set_id     = $self->get_set_id;
	my $subdir     = setting('subdir');
	my $locus_name = $locus;

	if ($set_id) {
		$locus_name = $self->{'datastore'}->get_set_locus_real_id( $locus, $set_id );
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus_name);
	if ( !$locus_info ) {
		send_error( "Locus $locus does not exist.", 404 );
	}
	if ( !$sequence ) {
		send_error( 'Required field missing: sequence.', 400 );
	}
	my $blast_obj = $self->get_blast_object( [$locus] );
	$blast_obj->blast( \$sequence );
	my $exact_matches = $blast_obj->get_exact_matches( { details => $details } );
	my @exacts;
	if ($details) {
		my $matches = $exact_matches->{$locus};
		foreach my $match (@$matches) {
			my $filtered = $self->filter_match( $match, { exact => 1 } );
			$filtered->{'href'} = request->uri_for("$subdir/db/$db/loci/$locus/alleles/$match->{'allele'}");
			my $field_values =
			  $self->{'datastore'}->get_client_data_linked_to_allele( $locus, $match->{'allele'} );
			$filtered->{'linked_data'} = $field_values->{'detailed_values'}
			  if $field_values->{'detailed_values'};
			push @exacts, $filtered;
		}
	} else {
		my $alleles = $exact_matches->{$locus};
		foreach my $allele_id (@$alleles) {
			push @exacts,
			  { allele_id => $allele_id, href => request->uri_for("$subdir/db/$db/loci/$locus/alleles/$allele_id") };
		}
	}
	my $values = { exact_matches => \@exacts };
	if ( !@exacts ) {
		my $partial_matches = $blast_obj->get_partial_matches( { details => 1 } );
		if ( $partial_matches->{$locus} ) {
			my $best     = $partial_matches->{$locus}->[0];
			my $filtered = $self->filter_match($best);
			if ($partial_linked_data) {
				my $field_values =
				  $self->{'datastore'}->get_client_data_linked_to_allele( $locus, $best->{'allele'} );
				$filtered->{'linked_data'} = $field_values->{'detailed_values'}
			}
			$values->{'best_match'} = $filtered;
		}
	}
	return $values;
}

sub _query_sequence {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $sequence, $details, $base64 ) = @{$params}{qw(db sequence details base64)};
	$self->check_post_payload;
	$self->check_load_average;
	$self->check_seqdef_database;
	$sequence = decode_base64($sequence) if $base64;
	my $set_id = $self->get_set_id;
	my $subdir = setting('subdir');

	if ( !$sequence ) {
		send_error( 'Required field missing: sequence.', 400 );
	}
	my $blast_obj = $self->get_blast_object( [] );
	$blast_obj->blast( \$sequence );
	my $matches = $blast_obj->get_exact_matches( { details => $details } );
	my $exacts = {};
	foreach my $locus ( keys %$matches ) {
		my $locus_name = $locus;
		if ($set_id) {
			$locus_name = $self->{'datastore'}->get_set_locus_real_id( $locus, $set_id );
		}
		my $alleles       = [];
		my $locus_matches = $matches->{$locus};
		if ($details) {
			foreach my $match (@$locus_matches) {
				my $filtered = $self->filter_match( $match, { exact => 1 } );
				my $field_values =
				  $self->{'datastore'}->get_client_data_linked_to_allele( $locus, $match->{'allele'} );
				$filtered->{'linked_data'} = $field_values->{'detailed_values'}
				  if $field_values->{'detailed_values'};
				push @$alleles, $filtered;
			}
		} else {
			foreach my $allele_id (@$locus_matches) {
				push @$alleles,
				  {
					allele_id => $allele_id,
					href      => request->uri_for("$subdir/db/$db/loci/$locus_name/alleles/$allele_id")
				  };
			}
		}
		$exacts->{$locus_name} = $alleles;
	}
	my $values = { exact_matches => $exacts };
	return $values;
}

#We probably need to have a specific field in the loci table to
#define this as there are too many cases where this won't work.
sub _get_seqdef_definition {
	my ($locus)    = @_;
	my $self       = setting('self');
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $subdir     = setting('subdir');
	foreach my $url (qw(description_url url)) {
		if (
			   $locus_info->{$url}
			&& $locus_info->{$url} =~ /page=(?:locusInfo|alleleInfo)/x
			&& $locus_info->{$url} =~ /^\//x    #Relative URL so on same server
			&& $locus_info->{$url} =~ /locus=(\w+)/x
		  )
		{
			my $seqdef_locus = $1;
			if ( $locus_info->{$url} =~ /db=(\w+)/x ) {
				my $seqdef_config = $1;
				return "$subdir/db/$seqdef_config/loci/$seqdef_locus";
			}
		}
	}
	return;
}

sub _get_extended_attributes {
	my ( $values, $locus_name ) = @_;
	my $self = setting('self');
	my $db   = params->{'db'};
	my $extended_attributes =
	  $self->{'datastore'}
	  ->run_query( 'SELECT * FROM locus_extended_attributes WHERE locus=? ORDER BY field_order,field',
		$locus_name, { fetch => 'all_arrayref', slice => {} } );
	my @attributes;
	foreach my $attribute (@$extended_attributes) {
		my $attribute_list = {};
		foreach (qw(field value_format value_regex description length)) {
			$attribute_list->{$_} = $attribute->{$_} if defined $attribute->{$_};
		}
		$attribute_list->{'required'} = $attribute->{'required'} ? JSON::true : JSON::false;
		if ( $attribute->{'option_list'} ) {
			my @values = split /\|/x, $attribute->{'option_list'};
			$attribute_list->{'allowed_values'} = \@values;
		}
		push @attributes, $attribute_list;
	}
	$values->{'extended_attributes'} = \@attributes if @attributes;
	return;
}

sub _get_description {
	my ( $values, $locus_name ) = @_;
	my $self = setting('self');
	my $db   = params->{'db'};
	my $description =
	  $self->{'datastore'}
	  ->run_query( 'SELECT * FROM locus_descriptions WHERE locus=?', $locus_name, { fetch => 'row_hashref' } );
	foreach (qw(full_name product description)) {
		$values->{$_} = $description->{$_} if defined $description->{$_} && $description->{$_} ne '';
	}
	my $pubmed_ids =
	  $self->{'datastore'}->run_query( 'SELECT pubmed_id FROM locus_refs WHERE locus=? ORDER BY pubmed_id',
		$locus_name, { fetch => 'col_arrayref' } );
	$values->{'publications'} = $pubmed_ids if @$pubmed_ids;
	return;
}

sub _get_curators {
	my ( $values, $locus_name ) = @_;
	my $self   = setting('self');
	my $db     = params->{'db'};
	my $subdir = setting('subdir');
	my $curators =
	  $self->{'datastore'}->run_query( 'SELECT curator_id FROM locus_curators WHERE locus=? ORDER BY curator_id',
		$locus_name, { fetch => 'col_arrayref' } );
	my @curator_links;
	foreach my $user_id (@$curators) {
		push @curator_links, request->uri_for("$subdir/db/$db/users/$user_id");
	}
	$values->{'curators'} = \@curator_links if @curator_links;
	return;
}
1;
