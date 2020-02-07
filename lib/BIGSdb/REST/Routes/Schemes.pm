#Written by Keith Jolley
#Copyright (c) 2014-2019, University of Oxford
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
use JSON;
use MIME::Base64;
use Dancer2 appname => 'BIGSdb::REST::Interface';
use constant MAX_QUERY_SEQ => 5000;

#Scheme routes
sub setup_routes {
	my $self = setting('self');
	foreach my $dir ( @{ setting('api_dirs') } ) {
		get "$dir/db/:db/schemes"                       => sub { _get_schemes() };
		get "$dir/db/:db/schemes/breakdown/:field"      => sub { _get_schemes_breakdown() };
		get "$dir/db/:db/schemes/:scheme"               => sub { _get_scheme() };
		get "$dir/db/:db/schemes/:scheme/loci"          => sub { _get_scheme_loci() };
		get "$dir/db/:db/schemes/:scheme/fields/:field" => sub { _get_scheme_field() };
		post "$dir/db/:db/schemes/:scheme/sequence"     => sub { _query_scheme_sequence() };
	}
	return;
}

sub _get_schemes {
	my $self        = setting('self');
	my ($db)        = params->{'db'};
	my $set_id      = $self->get_set_id;
	my $schemes     = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	my $subdir      = setting('subdir');
	my $values      = { records => int(@$schemes) };
	my $scheme_list = [];
	foreach my $scheme (@$schemes) {
		push @$scheme_list,
		  { scheme => request->uri_for("$subdir/db/$db/schemes/$scheme->{'id'}"), description => $scheme->{'name'} };
	}
	$values->{'schemes'} = $scheme_list;
	return $values;
}

#Undocumented call used for site statistics
sub _get_schemes_breakdown {
	my $self = setting('self');
	my ( $db, $field ) = ( params->{'db'}, params->{'field'} );
	$self->check_seqdef_database;
	my %allowed_fields = map { $_ => 1 } qw(date_entered datestamp);
	if ( !$allowed_fields{$field} ) {
		send_error( 'Invalid field', 400 );
	}
	my $set_id = $self->get_set_id;
	my $values = $self->{'datastore'}->run_query(
		"SELECT p.$field,p.scheme_id,s.name,COUNT(*) AS count FROM profiles p JOIN "
		  . "schemes s ON p.scheme_id=s.id GROUP BY p.$field,p.scheme_id,s.name",
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
	if ($set_id) {
		my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
		my %scheme_name = map { $_->{'id'} => $_->{'name'} } @$schemes;
		my $filtered_values = [];
		foreach my $value (@$values) {
			next if !$scheme_name{ $value->{'scheme_id'} };
			$value->{'name'} = $scheme_name{ $value->{'scheme_id'} };
			push @$filtered_values, $value;
		}
		return $filtered_values;
	}
	return $values;
}

sub _get_scheme {
	my $self = setting('self');
	my ( $db, $scheme_id ) = ( params->{'db'}, params->{'scheme'} );
	$self->check_scheme($scheme_id);
	my $values      = {};
	my $set_id      = $self->get_set_id;
	my $subdir      = setting('subdir');
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	$values->{'id'}                    = int($scheme_id);
	$values->{'description'}           = $scheme_info->{'name'};
	$values->{'has_primary_key_field'} = $scheme_info->{'primary_key'} ? JSON::true : JSON::false;
	$values->{'primary_key_field'} =
	  request->uri_for("$subdir/db/$db/schemes/$scheme_id/fields/$scheme_info->{'primary_key'}")
	  if $scheme_info->{'primary_key'};
	my $scheme_fields      = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $scheme_field_links = [];

	foreach my $field (@$scheme_fields) {
		push @$scheme_field_links, request->uri_for("$subdir/db/$db/schemes/$scheme_id/fields/$field");
	}
	if ( $scheme_info->{'primary_key'} && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $allowed_filters = [qw(added_after added_on updated_after updated_on)];
		my $table           = "mv_scheme_$scheme_id";
		my $qry =
		  $self->add_filters( "SELECT COUNT(*),MAX(date_entered),MAX(datestamp) FROM $table", $allowed_filters );
		my ( $profile_count, $last_added, $last_updated ) = $self->{'datastore'}->run_query($qry);
		$values->{'records'}      = $profile_count;
		$values->{'last_updated'} = $last_updated if $last_updated;
		$values->{'last_added'}   = $last_added;
	}
	$values->{'fields'} = $scheme_field_links if @$scheme_field_links;
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	$values->{'locus_count'} = scalar @$loci;
	my $locus_links = [];
	foreach my $locus (@$loci) {
		my $cleaned_locus = $self->clean_locus($locus);
		push @$locus_links, request->uri_for("$subdir/db/$db/loci/$cleaned_locus");
	}
	$values->{'loci'} = $locus_links if @$locus_links;
	if ( $scheme_info->{'primary_key'} && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		$values->{'profiles'}     = request->uri_for("$subdir/db/$db/schemes/$scheme_id/profiles");
		$values->{'profiles_csv'} = request->uri_for("$subdir/db/$db/schemes/$scheme_id/profiles_csv");

		#Curators
		my $curators =
		  $self->{'datastore'}
		  ->run_query( 'SELECT curator_id FROM scheme_curators WHERE scheme_id=? ORDER BY curator_id',
			$scheme_id, { fetch => 'col_arrayref' } );
		my @curator_links;
		foreach my $user_id (@$curators) {
			push @curator_links, request->uri_for("$subdir/db/$db/users/$user_id");
		}
		$values->{'curators'} = \@curator_links if @curator_links;
	}
	my $c_scheme_list =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id,name FROM classification_schemes WHERE scheme_id=? ORDER BY display_order,id',
		$scheme_id, { fetch => 'all_arrayref', slice => {} } );
	if (@$c_scheme_list) {
		my $c_schemes = [];
		foreach my $c_scheme (@$c_scheme_list) {
			push @$c_schemes,
			  {
				href => request->uri_for("$subdir/db/$db/classification_schemes/$c_scheme->{'id'}"),
				name => $c_scheme->{'name'}
			  };
		}
		$values->{'classification_schemes'} = $c_schemes;
	}
	return $values;
}

sub _get_scheme_loci {
	my $self = setting('self');
	my ( $db, $scheme_id ) = ( params->{'db'}, params->{'scheme'} );
	$self->check_scheme($scheme_id);
	my $subdir = setting('subdir');
	my $allowed_filters =
	  $self->{'system'}->{'dbtype'} eq 'sequences' ? [qw(alleles_added_after alleles_updated_after)] : [];
	my $qry =
	  $self->add_filters( 'SELECT locus FROM scheme_members WHERE scheme_id=?', $allowed_filters, { id => 'locus' } );
	$qry .= ' ORDER BY field_order,locus';
	my $loci = $self->{'datastore'}->run_query( $qry, $scheme_id, { fetch => 'col_arrayref' } );
	my $values = { records => int(@$loci) };
	my $locus_links = [];

	foreach my $locus (@$loci) {
		my $cleaned_locus = $self->clean_locus($locus);
		push @$locus_links, request->uri_for("$subdir/db/$db/loci/$cleaned_locus");
	}
	$values->{'loci'} = $locus_links;
	return $values;
}

sub _get_scheme_field {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $scheme_id, $field ) = @{$params}{qw(db scheme field)};
	$self->check_scheme($scheme_id);
	my $values = {};
	my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
	if ( !$field_info ) {
		send_error( "Scheme field $field does not exist in scheme $scheme_id.", 404 );
	}
	foreach my $attribute (qw(field type description)) {
		$values->{$attribute} = $field_info->{$attribute} if defined $field_info->{$attribute};
	}
	$values->{'primary_key'} = $field_info->{'primary_key'} ? JSON::true : JSON::false;
	return $values;
}

sub _query_scheme_sequence {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $scheme_id, $sequence, $details, $base64 ) =
	  @{$params}{qw(db scheme sequence details base64)};
	$self->check_post_payload;
	$self->check_load_average;
	$self->check_seqdef_database;
	$self->check_scheme($scheme_id);
	$sequence = decode_base64($sequence) if $base64;

	if ( !$sequence ) {
		send_error( 'Required field missing: sequence.', 400 );
	}
	my $num_sequences = ($sequence =~ tr/>//);
	if ($num_sequences > MAX_QUERY_SEQ){
		my $max = MAX_QUERY_SEQ;
		send_error( "Query contains too many sequences - limit is $max.", 413 );
	}
	my $set_id      = $self->get_set_id;
	my $subdir      = setting('subdir');
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $loci        = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $blast_obj   = $self->get_blast_object($loci);
	$blast_obj->blast( \$sequence );
	my $matches      = $blast_obj->get_exact_matches( { details => $details } );
	my $exacts       = {};
	my $designations = {};

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
		$exacts->{$locus_name}  = $alleles;
		$designations->{$locus} = $alleles;    #Don't use set name for scheme field lookup.
	}
	my $values = { exact_matches => $exacts };
	my $field_values = _get_scheme_fields( $scheme_id, $designations );
	if ( keys %$field_values ) {
		$values->{'fields'} = $field_values;
	}
	if ($details) {
		my $analysis = _run_seq_query_script($values);
		if ($analysis) {
			my $heading = $self->{'system'}->{'rest_hook_seq_query_heading'} // 'analysis';
			$values->{$heading} = $analysis;
		}
	}
	return $values;
}

sub _run_seq_query_script {
	my ($values) = @_;
	my $self = setting('self');
	my $analysis;
	return if !$self->{'system'}->{'rest_hook_seq_query'};
	my $results_prefix    = BIGSdb::Utils::get_random();
	my $results_json_file = "$self->{'config'}->{'secure_tmp_dir'}/${results_prefix}.json";
	if ( -x $self->{'system'}->{'rest_hook_seq_query'} ) {
		my $results_json = encode_json($values);
		_write_results_file( $results_json_file, $results_json );
		my $script_out = `$self->{'system'}->{'rest_hook_seq_query'} $results_json_file`;
		if ($script_out) {
			$analysis = decode_json($script_out);
		}
		unlink $results_json_file;
	}
	return $analysis;
}

sub _write_results_file {
	my ( $filename, $buffer ) = @_;
	my $self = setting('self');
	open( my $fh, '>', $filename ) || $self->{'logger'}->error("Cannot open $filename for writing");
	say $fh $buffer;
	close $fh;
	return;
}

sub _get_scheme_fields {
	my ( $scheme_id, $matches ) = @_;
	my $self   = setting('self');
	my $loci   = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	return {} if !@$fields;
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
	my %allele_count;
	my @allele_ids;

	foreach my $locus (@$loci) {
		if ( !defined $matches->{$locus} ) {

			#Define a null designation if one doesn't exist for the purposes of looking up profile.
			#We can't just abort the query because some schemes allow missing loci, but we don't want to match based
			#on an incomplete set of designations.
			push @allele_ids, '-999';
			$allele_count{$locus} = 1;
		} else {
			$allele_count{$locus} =
			  scalar @{ $matches->{$locus} };    #We need a different query depending on number of designations at loci.
			foreach my $match ( @{ $matches->{$locus} } ) {
				push @allele_ids, $match->{'allele_id'};
			}
		}
	}
	return {} if !@allele_ids;
	my $locus_indices =
	  $self->{'datastore'}->run_query( 'SELECT locus,index FROM scheme_warehouse_indices WHERE scheme_id=?',
		$scheme_id, { fetch => 'all_arrayref' } );
	my %indices = map { $_->[0] => $_->[1] } @$locus_indices;
	local $" = ',';
	my @locus_terms;
	foreach my $locus (@$loci) {
		my $locus_name = "profile[$indices{$locus}]";
		my @temp_terms;
		push @temp_terms, ("$locus_name=?") x $allele_count{$locus};
		push @temp_terms, "$locus_name='N'" if $scheme_info->{'allow_missing_loci'};
		local $" = ' OR ';
		push @locus_terms, "(@temp_terms)";
	}
	local $" = ' AND ';
	my $locus_term_string = "@locus_terms";
	local $" = ',';
	my $table      = "mv_scheme_$scheme_id";
	my $value_sets = $self->{'datastore'}->run_query( "SELECT @$fields FROM $table WHERE $locus_term_string",
		[@allele_ids], { fetch => 'all_arrayref', slice => {} } );
	my $results      = {};
	my $seen_already = {};

	foreach my $value_set (@$value_sets) {
		foreach my $field (@$fields) {
			if ( $value_set->{ lc $field } ) {
				push @{ $results->{$field} }, $value_set->{ lc $field }
				  if !$seen_already->{$field}->{ $value_set->{ lc $field } };
				$seen_already->{$field}->{ $value_set->{ lc $field } } = 1;
			}
		}
	}
	foreach my $field (@$fields) {
		next if !$results->{$field};
		my @ordered = sort @{ $results->{$field} };
		local $" = q(,);
		$results->{$field} = qq(@ordered);
	}
	return $results;
}
1;
