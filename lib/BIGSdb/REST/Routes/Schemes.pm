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
		get "$dir/db/:db/schemes"                           => sub { _get_schemes() };
		get "$dir/db/:db/schemes/breakdown/:field"          => sub { _get_schemes_breakdown() };
		get "$dir/db/:db/schemes/:scheme"                   => sub { _get_scheme() };
		get "$dir/db/:db/schemes/:scheme/loci"              => sub { _get_scheme_loci() };
		get "$dir/db/:db/schemes/:scheme/fields/:field"     => sub { _get_scheme_field() };
		get "$dir/db/:db/schemes/:scheme/lincode_nicknames" => sub { _get_lincode_nicknames() };
		post "$dir/db/:db/schemes/:scheme/sequence"     => sub { _query_scheme_sequence() };
		post "$dir/db/:db/schemes/:scheme/designations" => sub { _query_scheme_designations() };
	}
	return;
}

sub _get_schemes {
	my $self = setting('self');
	my ( $db, $with_pk ) = ( params->{'db'}, params->{'with_pk'} );
	my $set_id      = $self->get_set_id;
	my $schemes     = $self->{'datastore'}->get_scheme_list( { set_id => $set_id, with_pk => $with_pk } );
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
		my $schemes         = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
		my %scheme_name     = map { $_->{'id'} => $_->{'name'} } @$schemes;
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
	my $subdir      = setting('subdir');
	my $values      = {};
	my $set_id      = $self->get_set_id;
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
		my $allowed_filters = [qw(added_after added_reldate added_on updated_after updated_reldate updated_on)];
		my $table           = "mv_scheme_$scheme_id";
		my $qry =
		  $self->add_filters( "SELECT COUNT(*),MAX(date_entered),MAX(datestamp) FROM $table", $allowed_filters );
		my ( $profile_count, $last_added, $last_updated ) = $self->{'datastore'}->run_query($qry);
		$values->{'records'}      = $profile_count;
		$values->{'last_updated'} = $last_updated if $last_updated;
		$values->{'last_added'}   = $last_added;
		$values->{'max_missing'}  = $scheme_info->{'max_missing'} if defined $scheme_info->{'max_missing'};
	}
	my @boolean = qw(allow_missing_loci allow_presence);
	$values->{$_} = ( $scheme_info->{$_} ? JSON::true : JSON::false ) foreach @boolean;
	$values->{'display_order'} = $scheme_info->{'display_order'} if defined $scheme_info->{'display_order'};

	$values->{'fields'} = $scheme_field_links if @$scheme_field_links;
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	$values->{'locus_count'} = scalar @$loci;
	my $locus_links = [];
	foreach my $locus (@$loci) {
		my $cleaned_locus = $self->clean_locus($locus);
		push @$locus_links, request->uri_for("$subdir/db/$db/loci/$cleaned_locus");
	}
	$values->{'loci'} = $locus_links if @$locus_links;
	my $flags = $self->{'datastore'}
	  ->run_query( 'SELECT flag FROM scheme_flags WHERE scheme_id=?', $scheme_id, { fetch => 'col_arrayref' } );
	$values->{'flags'} = $flags if @$flags;
	my $pubmed_ids =
	  $self->{'datastore'}->run_query( 'SELECT pubmed_id FROM scheme_refs WHERE scheme_id=? ORDER BY pubmed_id',
		$scheme_id, { fetch => 'col_arrayref' } );
	my $publications = [];
	foreach my $pubmed_id (@$pubmed_ids) {
		push @$publications,
		  {
			pubmed_id     => int($pubmed_id),
			citation_link => "https://www.ncbi.nlm.nih.gov/pubmed/$pubmed_id"
		  };
	}
	$values->{'publications'} = $publications if @$publications;
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
	my $lincode_scheme =
	  $self->{'datastore'}
	  ->run_query( 'SELECT * FROM lincode_schemes WHERE scheme_id=?', $scheme_id, { fetch => 'row_hashref' } );
	if ($lincode_scheme) {
		my $lc = { thresholds => $lincode_scheme->{'thresholds'} };
		$lc->{'max_missing'} = $lincode_scheme->{'max_missing'} if defined $lincode_scheme->{'max_missing'};
		if ( defined $lincode_scheme->{'maindisplay'} ) {
			$lc->{'maindisplay'} = $lincode_scheme->{'maindisplay'} ? JSON::true : JSON::false;
		}
		if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
			$lc->{'definitions'} = request->uri_for("$subdir/db/$db/schemes/$scheme_id/lincodes");
		}
		my @fields = qw(field type display_order);
		push @fields, 'maindisplay' if $self->{'system'}->{'dbtype'} eq 'isolates';
		local $" = q(,);
		my $fields =
		  $self->{'datastore'}
		  ->run_query( "SELECT @fields FROM lincode_fields WHERE scheme_id=? ORDER BY display_order,field",
			$scheme_id, { fetch => 'all_arrayref', slice => {} } );
		foreach my $field (@$fields) {
			if ( defined $field->{'maindisplay'} ) {
				$field->{'maindisplay'} = $field->{'maindisplay'} ? JSON::true : JSON::false;
			}
		}
		$lc->{'fields'} = $fields if $fields;
		my $prefixes_exist = $self->{'datastore'}
		  ->run_query( 'SELECT EXISTS(SELECT * FROM lincode_prefixes WHERE scheme_id=?)', $scheme_id );
		if ($prefixes_exist) {
			$lc->{'nicknames'} = request->uri_for("$subdir/db/$db/schemes/$scheme_id/lincode_nicknames");
		}
		$values->{'lincodes'} = $lc;
	}
	my $message = $self->get_date_restriction_message;
	$values->{'message'} = $message if $message;
	return $values;
}

sub _get_scheme_loci {
	my $self = setting('self');
	my ( $db, $scheme_id ) = ( params->{'db'}, params->{'scheme'} );
	$self->check_scheme($scheme_id);
	my $subdir = setting('subdir');
	my $allowed_filters =
	  $self->{'system'}->{'dbtype'} eq 'sequences'
	  ? [qw(alleles_added_after alleles_added_reldate alleles_updated_after alleles_updated_reldate)]
	  : [];
	my $qry =
	  $self->add_filters( 'SELECT locus FROM scheme_members WHERE scheme_id=?', $allowed_filters, { id => 'locus' } );
	$qry .= ' ORDER BY field_order,locus';
	my $loci        = $self->{'datastore'}->run_query( $qry, $scheme_id, { fetch => 'col_arrayref' } );
	my $values      = { records => int(@$loci) };
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
	my $values     = {};
	my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
	if ( !$field_info ) {
		send_error( "Scheme field $field does not exist in scheme $scheme_id.", 404 );
	}
	foreach my $attribute (qw(field type description value_regex option_list field_order)) {
		$values->{$attribute} = $field_info->{$attribute} if defined $field_info->{$attribute};
	}
	foreach my $attribute (qw(primary_key index dropdown)) {
		$values->{$attribute} = $field_info->{$attribute} ? JSON::true : JSON::false;
	}
	return $values;
}

sub _query_scheme_sequence {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $scheme_id, $sequence, $details, $partial_matches, $base64 ) =
	  @{$params}{qw(db scheme sequence details partial_matches base64)};
	$self->check_post_payload;
	$self->check_load_average;
	$self->check_seqdef_database;
	$self->check_scheme($scheme_id);
	$sequence = decode_base64($sequence) if $base64;

	if ( !$sequence ) {
		send_error( 'Required field missing: sequence.', 400 );
	}
	if ($base64) {
		eval { BIGSdb::Utils::read_fasta( \$sequence, { allow_peptide => 1 } ); };
		if ($@) {
			send_error( 'Sequence is not a valid FASTA file.', 400 );
		}
	}
	my $num_sequences = ( $sequence =~ tr/>// );
	if ( $num_sequences > MAX_QUERY_SEQ ) {
		my $max = MAX_QUERY_SEQ;
		send_error( "Query contains too many sequences - limit is $max.", 413 );
	}
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	$self->{'dataConnector'}->drop_all_connections;    #Don't keep connections open while waiting for BLAST.
	my $blast_obj = $self->get_blast_object($loci);
	$blast_obj->blast( \$sequence );
	$self->reconnect;
	return _process_sequence_matches( $db, $scheme_id, $blast_obj, $details, undef, $partial_matches );
}

sub _process_sequence_matches {
	my ( $db, $scheme_id, $blast_obj, $details, $options, $check_partials ) = @_;
	my $self          = setting('self');
	my $set_id        = $self->get_set_id;
	my $subdir        = setting('subdir');
	my $exact_matches = $blast_obj->get_exact_matches( { details => $details } );
	my ( $exacts, $designations ) = _process_exact_matches(
		{
			db      => $db,
			set_id  => $set_id,
			matches => $exact_matches,
			details => $details,
			options => $options
		}
	);
	my $partials = {};
	if ($check_partials) {
		my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
		foreach my $locus (@$loci) {
			if ( !defined $exact_matches->{$locus} ) {
				my $partial = $blast_obj->get_best_partial_match($locus);
				if ($partial) {
					$partials->{$locus} = $partial;
				}
			}
		}
	}
	my $values = {};
	$values->{'exact_matches'}   = $exacts   if keys %$exacts;
	$values->{'partial_matches'} = $partials if keys %$partials;
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

sub _process_designation_matches {
	my ( $db, $scheme_id, $matches, $details, $options ) = @_;
	my $self   = setting('self');
	my $set_id = $self->get_set_id;
	my $subdir = setting('subdir');
	return {} if ref $matches ne 'HASH';
	my ( $exacts, $designations ) = _process_exact_matches(
		{
			db      => $db,
			set_id  => $set_id,
			matches => $matches,
			details => $details,
			options => $options
		}
	);
	my $values       = { exact_matches => $exacts };
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

sub _process_exact_matches {
	my ($args) = @_;
	my ( $db, $set_id, $matches, $details, $options ) = @$args{qw(db set_id matches details options)};
	my $self         = setting('self');
	my $subdir       = setting('subdir');
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
				my $filtered =
				  $options->{'designations_only'}
				  ? { allele_id => $match->{'allele'} }
				  : $self->filter_match( $match, { exact => 1 } );
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
	return ( $exacts, $designations );
}

sub _query_scheme_designations {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $scheme_id, $designations ) =
	  @{$params}{qw(db scheme designations )};
	$self->check_post_payload;
	$self->check_load_average;
	$self->check_seqdef_database;
	$self->check_scheme($scheme_id);
	if ( !$designations ) {
		send_error( 'Required field missing: designations.', 400 );
	}
	return _process_designation_matches( $db, $scheme_id, $designations, 1, { designations_only => 1 } );
}

sub _run_seq_query_script {
	my ($values) = @_;
	my $self = setting('self');
	my $analysis;
	return if !$self->{'system'}->{'rest_hook_seq_query'};
	my $results_prefix    = BIGSdb::Utils::get_random();
	my $results_json_file = "$self->{'config'}->{'secure_tmp_dir'}/${results_prefix}.json";
	if ( -x $self->{'system'}->{'rest_hook_seq_query'} ) {

		#Don't keep connections open while waiting for external script.
		$self->{'dataConnector'}->drop_all_connections( $self->{'do_not_drop'} );
		my $results_json = encode_json($values);
		_write_results_file( $results_json_file, $results_json );
		my $script_out;
		eval { $script_out = `$self->{'system'}->{'rest_hook_seq_query'} $results_json_file`; };
		if ($@) {
			$self->{'logger'}->error($@);
		}
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

sub _get_lincode_nicknames {
	my $self = setting('self');
	$self->check_seqdef_database;
	my $params = params;
	my ( $db, $scheme_id ) = @{$params}{qw(db scheme)};

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
	  ( !$self->{'username'} && $date_restriction ) ? qq( AND datestamp<='$date_restriction') : q();

	my $qry = $self->add_filters(
		'SELECT COUNT(*),max(datestamp) FROM lincode_prefixes WHERE ' . "scheme_id=$scheme_id$date_restriction_clause",
		$allowed_filters
	);
	my ( $prefix_count, $last_updated ) = $self->{'datastore'}->run_query($qry);

	my $page_values = $self->get_page_values($prefix_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};

	$qry = $self->add_filters(
		'SELECT prefix,field,value AS nickname,datestamp FROM lincode_prefixes '
		  . "WHERE scheme_id=$scheme_id$date_restriction_clause",
		$allowed_filters
	);
	$qry .= ' ORDER BY prefix,field';
	$qry .= " LIMIT $self->{'page_size'} OFFSET $offset" if !param('return_all');
	my $nicknames = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	my $values    = { records => int($prefix_count) };
	$values->{'last_updated'} = $last_updated if defined $last_updated;
	my $path   = $self->get_full_path( "$subdir/db/$db/schemes/$scheme_id/lincode_nicknames", $allowed_filters );
	my $paging = $self->get_paging( $path, $pages, $page, $offset );
	$values->{'paging'} = $paging if %$paging;
	local $" = q(_);

	$values->{'nicknames'} = $nicknames;
	my $message = $self->get_date_restriction_message;
	$values->{'message'} = $message if $message;
	return $values;
}
1;
