#Written by Keith Jolley
#Copyright (c) 2010-2023, University of Oxford
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
package BIGSdb::ProfileQueryPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::QueryPage);
use BIGSdb::Constants qw(:interface OPERATORS);
use List::MoreUtils qw(any uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub _ajax_content {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $q      = $self->{'cgi'};
	my $row    = $q->param('row');
	return if !BIGSdb::Utils::is_int($row) || $row > MAX_ROWS || $row < 2;
	if ( $q->param('fields') eq 'scheme_fields' ) {
		my $scheme_id = $q->param('scheme_id');
		return if !BIGSdb::Utils::is_int($scheme_id);
		my ( $primary_key, $select_items, $orderitems, $cleaned ) = $self->_get_select_items($scheme_id);
		$self->_print_scheme_fields( $row, 0, $scheme_id, $select_items, $cleaned );
	}
	return;
}

sub _save_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $guid   = $self->get_guid;
	return if !$guid;
	foreach my $attribute (qw (scheme list filters)) {
		my $value = $q->param($attribute) ? 'on' : 'off';
		$self->{'prefstore'}->set_general( $guid, $self->{'system'}->{'db'}, "${attribute}_fieldset", $value );
	}
	return;
}

sub get_help_url {
	my ($self) = @_;
	if ( $self->{'curate'} ) {
		return "$self->{'config'}->{'doclink'}/curator_guide/0070_updating_and_deleting_profiles.html";
	} else {
		return "$self->{'config'}->{'doclink'}/data_query/0030_search_scheme_profiles.html"
		  . '#querying-scheme-profile-definitions';
	}
	return;
}

sub get_title {
	my ($self) = @_;
	return $self->{'curate'} ? q(Query or update profiles) : q(Search or browse profiles);
}

sub print_content {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $q      = $self->{'cgi'};
	if    ( $q->param('no_header') )    { $self->_ajax_content; return }
	elsif ( $q->param('save_options') ) { $self->_save_options; return }
	my $title = $self->get_title;
	say qq(<h1>$title</h1>);
	my $qry;
	my $schemes = $self->{'datastore'}->get_scheme_list( { with_pk => 1 } );

	if ( !@$schemes ) {
		$self->print_bad_status( { message => 'There are no indexed schemes defined in this database.', navbar => 1 } );
		return;
	}
	if (   !defined $q->param('currentpage')
		|| $q->param('First')
		|| ( ( $q->param('currentpage') // 0 ) == 2 && $q->param('<') ) )
	{
		say q(<noscript><div class="box statusbad"><p>This interface requires )
		  . q(that you enable Javascript in your browser.</p></div></noscript>);
		return if $self->_print_interface;    #Returns 1 if scheme is invalid
	}
	$self->_run_query if $q->param('submit') || defined $q->param('query_file');
	return;
}

sub initiate {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	$self->SUPER::initiate;
	$self->{'noCache'} = 1;
	if ( !$self->{'cgi'}->param('save_options') ) {
		my $guid = $self->get_guid;
		return if !$guid;
		foreach my $attribute (qw (list filters)) {
			my $value =
			  $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, "${attribute}_fieldset" );
			$self->{'prefs'}->{"${attribute}_fieldset"} = ( $value // '' ) eq 'on' ? 1 : 0;
		}
		my $value = $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, 'scheme_fieldset' );
		$self->{'prefs'}->{'scheme_fieldset'} = ( $value // '' ) eq 'off' ? 0 : 1;
	}
	$self->set_level1_breadcrumbs;
	return;
}

sub _print_interface {
	my ($self)    = @_;
	my $system    = $self->{'system'};
	my $prefs     = $self->{'prefs'};
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	return 1 if defined $scheme_id && $self->is_scheme_invalid( $scheme_id, { with_pk => 1 } );
	$self->print_scheme_section( { with_pk => 1 } );
	$scheme_id = $q->param('scheme_id');    #Will be set by scheme section method
	say q(<div class="box" id="queryform"><div class="scrollable">);
	say q(<p>Enter search criteria or leave blank to browse all records. Modify form parameters to filter or )
	  . q(enter a list of values.</p>);
	say $q->start_form;
	say $q->hidden($_) foreach qw (db page scheme_id);
	my $scheme_field_count   = $self->_highest_entered_fields || 1;
	my $scheme_field_heading = $scheme_field_count == 1 ? 'none' : 'inline';
	say q(<div style="white-space:nowrap">);
	my $display = $self->{'prefs'}->{'scheme_fieldset'}
	  || $self->_highest_entered_fields ? 'inline' : 'none';
	say qq(<fieldset style="float:left;display:$display" id="scheme_fieldset"><legend>Locus/scheme fields</legend>);
	say qq(<span id="scheme_field_heading" style="display:$scheme_field_heading">)
	  . q(<label for="c0">Combine searches with: </label>);
	say $q->popup_menu( -name => 'c0', -id => 'c0', -values => [qw(AND OR)] );
	say q(</span><ul id="scheme_fields">);
	my ( $primary_key, $selectitems, $orderitems, $cleaned ) = $self->_get_select_items($scheme_id);

	foreach my $i ( 1 .. $scheme_field_count ) {
		print q(<li>);
		$self->_print_scheme_fields( $i, $scheme_field_count, $scheme_id, $selectitems, $cleaned );
		say q(</li>);
	}
	say q(</ul></fieldset>);
	$self->_print_list_fieldset($scheme_id);
	$self->_print_filter_fieldset($scheme_id);
	$self->_print_order_fieldset($scheme_id);
	$self->print_action_fieldset( { page => 'query', scheme_id => $scheme_id, submit_label => 'Search' } );
	$self->_print_modify_search_fieldset;
	say q(</div>);
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub print_panel_buttons {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if (   !defined $q->param('currentpage')
		|| ( defined $q->param('pagejump') && $q->param('pagejump') eq '1' )
		|| $q->param('First') )
	{
		say q(<span class="icon_button"><a class="trigger_button" id="panel_trigger" style="display:none">)
		  . q(<span class="fas fa-lg fa-wrench"></span><span class="icon_label">Modify form</span></a></span>);
	}
	return;
}

sub _print_filter_fieldset {
	my ( $self, $scheme_id ) = @_;
	my $q = $self->{'cgi'};
	my @filters;
	my $set_id      = $self->get_set_id;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	if ( $self->{'config'}->{'ref_db'} ) {
		my $pmid = $self->{'datastore'}->run_query( 'SELECT DISTINCT(pubmed_id) FROM profile_refs WHERE scheme_id=?',
			$scheme_id, { fetch => 'col_arrayref' } );
		if (@$pmid) {
			my $labels = $self->{'datastore'}->get_citation_hash($pmid);
			my @values = sort { $labels->{$a} cmp $labels->{$b} } keys %$labels;
			push @filters,
			  $self->get_filter(
				'publication',
				\@values,
				{
					labels  => $labels,
					text    => 'Publication',
					tooltip => 'publication filter - Select a publication to filter your search '
					  . 'to only those isolates that match the selected publication.'
				}
			  );
		}
	}
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach my $field (@$scheme_fields) {
		if ( $self->{'prefs'}->{'dropdown_scheme_fields'}->{$scheme_id}->{$field} ) {
			my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
			my $value_clause      = $scheme_field_info->{'type'} eq 'integer' ? 'CAST(value AS integer)' : 'value';
			my $values            = $self->{'datastore'}->run_query(
				"SELECT DISTINCT $value_clause FROM profile_fields WHERE "
				  . "(scheme_id,scheme_field)=(?,?) ORDER BY $value_clause",
				[ $scheme_id, $field ],
				{ fetch => 'col_arrayref' }
			);
			next if !@$values;
			my $a_or_an = substr( $field, 0, 1 ) =~ /[aeiouAEIOU]/x ? 'an' : 'a';
			push @filters,
			  $self->get_filter(
				$field, $values,
				{
					text    => $field,
					tooltip => "$field ($scheme_info->{'name'}) filter - Select $a_or_an $field to "
					  . "filter your search to only those profiles that match the selected $field."
				}
			  );
		}
	}
	if (@filters) {
		say q(<fieldset id="filters_fieldset" style="float:left;display:none"><legend>Filters</legend>);
		say q(<ul>);
		say qq(<li><span style="white-space:nowrap">$_</span></li>) foreach @filters;
		say q(</ul></fieldset>);
		$self->{'filters_present'} = 1;
	}
	return;
}

sub _print_order_fieldset {
	my ( $self, $scheme_id ) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset id="display_fieldset" style="float:left"><legend>Display/sort options</legend>);
	say q(<ul><li><span style="white-space:nowrap"><label for="order" class="display">Order by: </label>);
	my ( $primary_key, $selectitems, $orderitems, $cleaned ) = $self->_get_select_items($scheme_id);
	say $q->popup_menu(
		-name   => 'order',
		-id     => 'order',
		-values => $orderitems,
		-labels => $cleaned,
		-class  => 'fieldlist'
	);
	say $q->popup_menu( -name => 'direction', -values => [qw(ascending descending)], -default => 'ascending' );
	say q(</span></li><li>);
	say $self->get_number_records_control;
	say q(</li></ul></fieldset>);
	return;
}

sub _print_scheme_fields {
	my ( $self, $row, $max_rows, $scheme_id, $selectitems, $labels ) = @_;
	my $q = $self->{'cgi'};
	say q(<span style="white-space:nowrap">);
	say $q->popup_menu( -name => "s$row", -values => $selectitems, -labels => $labels, -class => 'fieldlist' );
	say $q->popup_menu( -name => "y$row", -values => [OPERATORS] );
	say $q->textfield( -name => "t$row", -class => 'value_entry' );
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		print qq(<a id="add_scheme_fields" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=query&amp;fields=scheme_fields&amp;scheme_id=$scheme_id&amp;row=$next_row&amp;no_header=1" )
		  . q(data-rel="ajax" class="add_button"><span class="fa fas fa-plus"></span></a>);
		say $self->get_tooltip( '', { id => 'scheme_field_tooltip' } );
	}
	say q(</span>);
	return;
}

sub _get_select_items {
	my ( $self, $scheme_id ) = @_;
	my ( @selectitems, @orderitems, %cleaned );
	my $loci        = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	if ( !defined $primary_key ) {
		$logger->error('No primary key - this should not have been called.');
		return;
	}
	push @selectitems, $primary_key;
	push @orderitems,  $primary_key;
	if ( $self->{'datastore'}->are_lincodes_defined($scheme_id) ) {
		push @selectitems, 'LINcode';
		my $lincode_fields = $self->{'datastore'}
		  ->run_query( 'SELECT field FROM lincode_fields WHERE scheme_id=?', $scheme_id, { fetch => 'col_arrayref' } );
		push @selectitems, "$_ (LINcode)" foreach @$lincode_fields;
	}
	foreach my $locus (@$loci) {
		$cleaned{$locus} = $self->clean_locus( $locus, { text_output => 1 } );
		push @selectitems, $locus;
		push @orderitems,  $locus;
	}
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach my $field (@$scheme_fields) {
		next if $field eq $primary_key;
		( $cleaned{$field} = $field ) =~ tr/_/ /;
		push @selectitems, $field;
		push @orderitems,  $field;
	}
	my $cschemes =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id,name FROM classification_schemes WHERE scheme_id=? ORDER BY display_order,name',
		$scheme_id, { fetch => 'all_arrayref', slice => {} } );
	foreach my $cscheme (@$cschemes) {
		push @selectitems, $cscheme->{'name'};
		my $cscheme_fields =
		  $self->{'datastore'}
		  ->run_query( 'SELECT field FROM classification_group_fields WHERE cg_scheme_id=? ORDER BY field_order,field',
			$cscheme->{'id'}, { fetch => 'col_arrayref' } );
		push @selectitems, "$cscheme->{'name'}: $_" foreach @$cscheme_fields;
	}
	foreach my $field (qw (sender curator)) {
		push @selectitems, "$field (id)", "$field (surname)", "$field (first_name)", "$field (affiliation)";
		push @orderitems, $field;
	}
	push @selectitems, qw(date_entered datestamp);
	$cleaned{'date_entered'} = 'date entered';
	( $cleaned{$primary_key} = $primary_key ) =~ tr/_/ /;
	return ( $primary_key, \@selectitems, \@orderitems, \%cleaned );
}

sub _run_query {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $system = $self->{'system'};
	my ( $qry, $list_file );
	my $errors    = [];
	my $scheme_id = BIGSdb::Utils::is_int( scalar $q->param('scheme_id') ) ? $q->param('scheme_id') : 0;
	if ( !defined $q->param('query_file') ) {
		( $qry, $list_file, $errors ) = $self->_generate_query($scheme_id);
		$q->param( list_file => $list_file );
	} else {
		$qry = $self->get_query_from_temp_file( scalar $q->param('query_file') );
		if ( $q->param('list_file') ) {
			$self->{'datastore'}->create_temp_list_table( 'text', scalar $q->param('list_file') );
		}
	}
	my $browse;
	if ( $qry =~ /\(\)/x ) {
		$qry =~ s/\ WHERE\ \(\)//x;
		$browse = 1;
	}
	if (@$errors) {
		local $" = '<br />';
		$self->print_bad_status( { message => q(Problem with search criteria:), detail => qq(@$errors) } );
	} else {
		my @hidden_attributes;
		push @hidden_attributes, 'c0', 'c1';
		foreach my $i ( 1 .. MAX_ROWS ) {
			push @hidden_attributes, "s$i", "t$i", "y$i", "ls$i", "ly$i", "lt$i";
		}
		foreach ( @{ $self->{'xmlHandler'}->get_field_list } ) {
			push @hidden_attributes, $_ . '_list';
		}
		push @hidden_attributes, qw (publication_list scheme_id list list_file datatype);
		my $args = { table => 'profiles', query => $qry, browse => $browse, hidden_attributes => \@hidden_attributes };
		$args->{'passed_qry_file'} = $q->param('query_file') if defined $q->param('query_file');
		$self->paged_display($args);
	}
	return;
}

sub _is_locus_in_scheme {
	my ( $self, $scheme_id, $locus ) = @_;
	if ( !$self->{'cache'}->{'is_scheme_locus'}->{$scheme_id} ) {
		my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
		%{ $self->{'cache'}->{'is_scheme_locus'}->{$scheme_id} } = map { $_ => 1 } @$loci;
	}
	return $self->{'cache'}->{'is_scheme_locus'}->{$scheme_id}->{$locus};
}

sub _generate_query {
	my ( $self, $scheme_id ) = @_;
	my $q           = $self->{'cgi'};
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my ( $qry, $errors ) = $self->_generate_query_from_main_form($scheme_id);
	( $qry, my $list_file ) = $self->_modify_by_list( $scheme_id, $qry );
	$q->param( datatype => 'text' );
	$qry = $self->_modify_query_for_filters( $scheme_id, $qry );
	my $primary_key   = $scheme_info->{'primary_key'};
	my $order         = $q->param('order') || $primary_key;
	my $dir           = ( defined $q->param('direction') && $q->param('direction') eq 'descending' ) ? 'desc' : 'asc';
	my $pk_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	my $profile_id_field = $pk_field_info->{'type'} eq 'integer' ? "lpad($primary_key,20,'0')" : $primary_key;

	if ( $self->{'datastore'}->is_locus($order) ) {
		my $locus_info    = $self->{'datastore'}->get_locus_info($order);
		my $cleaned_order = $self->{'datastore'}->get_scheme_warehouse_locus_name( $scheme_id, $order );
		if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
			$order = "to_number(textcat('0', $cleaned_order), text(99999999))";    #Handle arbitrary allele = 'N'
		}
	}
	$qry .= ' ORDER BY' . ( $order ne $primary_key ? " $order $dir,$profile_id_field;" : " $profile_id_field $dir;" );
	#TODO Ordering is not working for presence schemes.
	return ( $qry, $list_file, $errors );
}

sub _get_data_type {
	my ( $self, $scheme_id, $field ) = @_;
	my %date_fields = map { $_ => 1 } qw(date_entered datestamp);
	my $is_locus    = $self->_is_locus_in_scheme( $scheme_id, $field );
	if ($is_locus) {
		return $self->{'datastore'}->get_locus_info($field)->{'allele_id_format'};
	} elsif ( $self->{'datastore'}->is_scheme_field( $scheme_id, $field ) ) {
		return $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field )->{'type'};
	} elsif ( $date_fields{$field} ) {
		return 'date';
	}
	return;
}

sub _get_classification_scheme_names {
	my ( $self, $scheme_id ) = @_;
	my $cschemes = $self->{'datastore'}->run_query( 'SELECT name FROM classification_schemes WHERE scheme_id=?',
		$scheme_id, { fetch => 'col_arrayref' } );
	my %cscheme_names = map { $_ => 1 } @$cschemes;
	return \%cscheme_names;
}

sub _get_classification_scheme_fields {
	my ($self) = @_;
	my $cscheme_fields = $self->{'datastore'}->run_query(
		'SELECT cs.name,cgf.field FROM classification_group_fields cgf JOIN '
		  . 'classification_schemes cs ON cgf.cg_scheme_id=cs.id',
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my %cscheme_fields = map { ("$_->{'name'}: $_->{'field'}") => 1 } @$cscheme_fields;
	return \%cscheme_fields;
}

sub _generate_query_from_main_form {
	my ( $self, $scheme_id ) = @_;
	my $q                = $self->{'cgi'};
	my $errors           = [];
	my $scheme_info      = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $qry              = "SELECT * FROM $scheme_warehouse WHERE (";
	my $andor            = $q->param('c0');
	my $first_value      = 1;
	my $cscheme_names    = $self->_get_classification_scheme_names($scheme_id);
	my $cscheme_fields   = $self->_get_classification_scheme_fields($scheme_id);
	my %standard_fields  = map { $_ => 1 } (
		'sender (id)',
		'sender (surname)',
		'sender (first_name)',
		'sender (affiliation)',
		'curator (id)',
		'curator (surname)',
		'curator (first_name)',
		'curator (affiliation)',
		'date_entered',
		'datestamp'
	);
	my %recognized_fields = ( %standard_fields, %$cscheme_names, %$cscheme_fields );
	my $lincodes_defined  = $self->{'datastore'}->are_lincodes_defined($scheme_id);
	$recognized_fields{'LINcode'} = 1 if $lincodes_defined;
	my $lincode_fields = $self->{'datastore'}
	  ->run_query( 'SELECT field FROM lincode_fields WHERE scheme_id=?', $scheme_id, { fetch => 'col_arrayref' } );
	$recognized_fields{"$_ (LINcode)"} = 1 foreach @$lincode_fields;

	foreach my $i ( 1 .. MAX_ROWS ) {
		next if !defined $q->param("t$i") || $q->param("t$i") eq q();
		my $field = $q->param("s$i") // q();
		my $type  = $self->_get_data_type( $scheme_id, $field );
		if ( !defined $type && !$recognized_fields{$field} ) {

			#Prevent cross-site scripting vulnerability
			( my $cleaned_field = $field ) =~ s/[^A-z0-9:\s].*$//x;
			push @$errors, "Field $cleaned_field is not recognized.";
			$logger->error("Attempt to modify fieldname: $field");
			next;
		}
		my $operator = $q->param("y$i") // '=';
		my $text     = $q->param("t$i");
		$self->process_value( \$text );
		my $is_locus = $self->_is_locus_in_scheme( $scheme_id, $field );
		next
		  if !(
			(
				   ( $scheme_info->{'allow_missing_loci'} && $text eq 'N' )
				|| ( $scheme_info->{'allow_presence'} && $text eq 'P' )
			)
			&& $is_locus
			&& $operator ne '<'
			&& $operator ne '>'
		  )
		  && $self->check_format( { field => $field, text => $text, type => $type, operator => $operator }, \@$errors );
		my $modifier = ( $i > 1 && !$first_value ) ? " $andor " : '';
		$first_value = 0;
		if ( $field =~ /(.*)\ \(id\)$/x
			&& !BIGSdb::Utils::is_int($text) )
		{
			push @$errors, "$field is an integer field.";
			next;
		}
		$qry .= $modifier;
		my $cleaned_field = $field;
		if ($is_locus) {
			$cleaned_field = $self->{'datastore'}->get_scheme_warehouse_locus_name( $scheme_id, $field );
		}
		if ( any { $field =~ /(.*)\ \($_\)$/x } qw (id surname first_name affiliation) ) {
			$qry .= $self->search_users( $field, $operator, $text, $scheme_warehouse );
			next;
		}
		if ( $cscheme_names->{$field} ) {
			if ( lc($text) ne 'null' && !BIGSdb::Utils::is_int($text) ) {
				push @$errors, "$field is an integer field.";
				next;
			}
			$qry .= $self->_modify_query_by_classification_group( $scheme_id, $field, $operator, $text, $errors );
			next;
		}
		if ( $cscheme_fields->{$field} ) {
			$qry .= $self->_modify_query_by_classification_group_field( $scheme_id, $field, $operator, $text, $errors );
			next;
		}
		if ( $field eq 'LINcode' ) {
			$qry .= $self->_modify_query_by_lincode( $scheme_id, $operator, $text, $errors );
			next;
		}
		if ( $field =~ /^(.*)\ \(LINcode\)$/x ) {
			$cleaned_field = $1;
			$qry .= $self->_modify_query_by_lincode_field( $scheme_id, $cleaned_field, $operator, $text, $errors );
			next;
		}
		$qry .= $self->_modify_query_by_scheme_fields(
			{
				scheme_id     => $scheme_id,
				cleaned_field => $cleaned_field,
				type          => $type,
				operator      => $operator,
				text          => $text,
				errors        => $errors
			}
		);
	}
	$qry .= ')';
	return ( $qry, $errors );
}

sub _modify_query_by_scheme_fields {
	my ( $self, $args ) = @_;
	my ( $scheme_id, $cleaned_field, $type, $operator, $text, $errors ) =
	  @{$args}{qw(scheme_id cleaned_field type operator text errors)};
	my $qry;
	my $equals =
	  lc($text) eq 'null'
	  ? "$cleaned_field is null"
	  : ( $type eq 'text' ? "UPPER($cleaned_field)=UPPER('$text')" : "$cleaned_field='$text'" );
	my %modify = (
		'NOT'         => lc($text) eq 'null' ? "(NOT $equals)" : "((NOT $equals) OR $cleaned_field IS NULL)",
		'contains'    => "(UPPER($cleaned_field) LIKE UPPER('\%$text\%'))",
		'starts with' => "(UPPER($cleaned_field) LIKE UPPER('$text\%'))",
		'ends with'   => "(UPPER($cleaned_field) LIKE UPPER('\%$text'))",
		'NOT contain' => "(NOT UPPER($cleaned_field) LIKE UPPER('\%$text\%') OR $cleaned_field IS NULL)",
		'='           => "($equals)"
	);
	if ( $modify{$operator} ) {
		$qry .= $modify{$operator};
	} else {
		if ( lc($text) eq 'null' ) {
			push @$errors, BIGSdb::Utils::escape_html("$operator is not a valid operator for comparing null values.");
		}
		$qry .= (
			$type eq 'integer'
			? "(to_number(textcat('0', $cleaned_field), text(99999999))"
			: "($cleaned_field"
		) . " $operator '$text')";
	}
	return $qry;
}

sub _modify_query_for_filters {
	my ( $self, $scheme_id, $qry ) = @_;
	my $q                = $self->{'cgi'};
	my $scheme_info      = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $primary_key      = $scheme_info->{'primary_key'};
	if ( defined $q->param('publication_list') && $q->param('publication_list') ne '' ) {
		my $pmid = $q->param('publication_list');
		my $ids  = $self->{'datastore'}->run_query(
			'SELECT profile_id FROM profile_refs WHERE (scheme_id,pubmed_id)=(?,?)',
			[ $scheme_id, $pmid ],
			{ fetch => 'col_arrayref' }
		);
		if ($pmid) {
			local $" = q(',');
			if ( $qry !~ /WHERE\ \(\)\s*$/x ) {
				$qry .= " AND ($primary_key IN ('@$ids'))";
			} else {
				$qry = "SELECT * FROM $scheme_warehouse WHERE ($primary_key IN ('@$ids'))";
			}
		}
	}
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach my $field (@$scheme_fields) {
		if ( defined $q->param("${field}_list") && $q->param("${field}_list") ne '' ) {
			my $value = $q->param("${field}_list");
			$value =~ s/'/\\'/gx;
			if ( $qry !~ /WHERE\ \(\)\s*$/x ) {
				$qry .= " AND (UPPER($field) = UPPER(E'$value'))";
			} else {
				$qry = "SELECT * FROM $scheme_warehouse WHERE (UPPER($field)=UPPER(E'$value'))";
			}
		}
	}
	return $qry;
}

sub _modify_query_by_classification_group {
	my ( $self, $scheme_id, $field, $operator, $text, $errors ) = @_;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	my $cscheme_id  = $self->{'datastore'}
	  ->run_query( 'SELECT id FROM classification_schemes WHERE (scheme_id,name)=(?,?)', [ $scheme_id, $field ] );
	my %modify = (
		  'NOT' => lc($text) eq 'null'
		? "($primary_key IN (SELECT profile_id FROM classification_group_profiles WHERE cg_scheme_id=$cscheme_id))"
		: "($primary_key NOT IN (SELECT profile_id FROM classification_group_profiles WHERE (cg_scheme_id,group_id)="
		  . "($cscheme_id,$text)))",
		'contains' => "($primary_key IN (SELECT profile_id FROM classification_group_profiles WHERE "
		  . "cg_scheme_id=$cscheme_id AND CAST(group_id AS text) LIKE '\%$text\%'))",
		'starts with' => "($primary_key IN (SELECT profile_id FROM classification_group_profiles WHERE "
		  . "cg_scheme_id=$cscheme_id AND CAST(group_id AS text) LIKE '$text\%'))",
		'ends with' => "($primary_key IN (SELECT profile_id FROM classification_group_profiles WHERE "
		  . "cg_scheme_id=$cscheme_id AND CAST(group_id AS text) LIKE '\%$text'))",
		'NOT contain' => "($primary_key NOT IN (SELECT profile_id FROM classification_group_profiles WHERE "
		  . "cg_scheme_id=$cscheme_id AND CAST(group_id AS text) LIKE '\%$text\%'))",
		'=' => lc($text) eq 'null'
		? "($primary_key NOT IN (SELECT profile_id FROM classification_group_profiles WHERE cg_scheme_id=$cscheme_id))"
		: "($primary_key IN (SELECT profile_id FROM classification_group_profiles WHERE (cg_scheme_id,group_id)="
		  . "($cscheme_id,$text)))"
	);
	if ( $modify{$operator} ) {
		return $modify{$operator};
	} else {
		if ( lc($text) eq 'null' ) {
			push @$errors, BIGSdb::Utils::escape_html("$operator is not a valid operator for comparing null values.");
			return q();
		}
		return "($primary_key IN (SELECT profile_id FROM classification_group_profiles WHERE "
		  . "cg_scheme_id=$cscheme_id AND group_id $operator $text))";
	}
	return q();
}

sub _get_cscheme_field_info {
	my ( $self, $field ) = @_;
	my $data = $self->{'datastore'}->run_query(
		'SELECT cs.name,cgf.* FROM classification_group_fields cgf JOIN '
		  . 'classification_schemes cs ON cgf.cg_scheme_id=cs.id',
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
	foreach my $scheme_field (@$data) {
		if ( $field eq "$scheme_field->{'name'}: $scheme_field->{'field'}" ) {
			return $scheme_field;
		}
	}
	return {};
}

sub _modify_query_by_classification_group_field {
	my ( $self, $scheme_id, $field, $operator, $text, $errors ) = @_;
	my $scheme_info   = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key   = $scheme_info->{'primary_key'};
	my $cscheme_field = $self->_get_cscheme_field_info($field);
	if ( $cscheme_field->{'type'} eq 'integer' && $text ne 'null' && !BIGSdb::Utils::is_int($text) ) {
		push @$errors, "$field is an integer field.";
		return q();
	}
	( my $cleaned_field = $cscheme_field->{'field'} ) =~ s/'/\\'/gx;
	( my $cleaned_value = $text )                     =~ s/'/\\'/gx;
	my $join_table =
		q(classification_group_field_values v JOIN classification_group_profiles p )
	  . q(ON v.cg_scheme_id=p.cg_scheme_id AND v.group_id=p.group_id AND )
	  . qq(v.cg_scheme_id=$cscheme_field->{'cg_scheme_id'} AND v.field=E'$cleaned_field');
	my %modify = (
		  'NOT' => lc($text) eq 'null' ? "($primary_key IN (SELECT profile_id FROM $join_table))"
		: "($primary_key NOT IN (SELECT profile_id FROM $join_table WHERE value=E'$cleaned_value'))",
		'contains'    => "($primary_key IN (SELECT profile_id FROM $join_table WHERE value LIKE E'\%$text\%'))",
		'starts with' => "($primary_key IN (SELECT profile_id FROM $join_table WHERE value LIKE E'$text\%'))",
		'ends with'   => "($primary_key IN (SELECT profile_id FROM $join_table WHERE value LIKE E'\%$text'))",
		'NOT contain' => "($primary_key NOT IN (SELECT profile_id FROM $join_table WHERE value LIKE E'\%$text\%'))",
		'='           => lc($text) eq 'null' ? "($primary_key NOT IN (SELECT profile_id FROM $join_table))"
		: "($primary_key IN (SELECT profile_id FROM $join_table WHERE value=E'$cleaned_value'))"
	);
	if ( $modify{$operator} ) {
		return $modify{$operator};
	} else {
		if ( lc($text) eq 'null' ) {
			push @$errors, BIGSdb::Utils::escape_html("$operator is not a valid operator for comparing null values.");
			return q();
		}
		return $cscheme_field->{'type'} eq 'integer'
		  ? "($primary_key IN (SELECT profile_id FROM $join_table WHERE CAST(value AS int) $operator $text))"
		  : "($primary_key IN (SELECT profile_id FROM $join_table WHERE value $operator E'$text'))";
	}
	return q();
}

sub _modify_by_list {
	my ( $self, $scheme_id, $qry ) = @_;
	my $q = $self->{'cgi'};
	return $qry if !$q->param('list');
	my $field;
	if ( $q->param('attribute') =~ /^s_${scheme_id}_(.*)$/x ) {
		$field = $1;
		return $qry if !$self->{'datastore'}->is_scheme_field( $scheme_id, $field );
	} elsif ( $q->param('attribute') =~ /^l_(.*)$/x ) {
		my $locus = $1;
		return $qry if !$self->_is_locus_in_scheme( $scheme_id, $locus );
		$field = $self->{'datastore'}->get_scheme_warehouse_locus_name( $scheme_id, $locus );
	}
	my @list = split /\n/x, $q->param('list');
	@list = uniq @list;
	BIGSdb::Utils::remove_trailing_spaces_from_list( \@list );
	my $list = $self->clean_list( 'text', \@list );
	return $qry if !@list || ( @list == 1 && $list[0] eq q() );
	my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( 'text', $list, { table => 'temp_list' } );
	my $list_file  = BIGSdb::Utils::get_random() . '.list';
	my $full_path  = "$self->{'config'}->{'secure_tmp_dir'}/$list_file";
	open( my $fh, '>:encoding(utf8)', $full_path ) || $logger->error("Can't open $full_path for writing");
	say $fh $_ foreach @list;
	close $fh;
	my $scheme_warehouse = qq(mv_scheme_$scheme_id);

	if ( $qry !~ /WHERE\ \(\)\s*$/x ) {
		$qry .= ' AND ';
	} else {
		$qry = "SELECT * FROM $scheme_warehouse WHERE ";
	}
	$qry .= "($field IN (SELECT value FROM $temp_table))";
	return ( $qry, $list_file );
}

sub _modify_query_by_lincode {
	my ( $self, $scheme_id, $operator, $text, $errors ) = @_;
	$text =~ s/^\s*|\s*$//gx;
	return q() if $text eq q();
	if ( lc($text) ne 'null' && $text !~ /^\d+(?:_\d+)*$/x ) {
		push @$errors, 'LINcodes are integer values separated by underscores (_).';
		return q();
	}
	my @values      = split /_/x, $text;
	my $value_count = @values;
	my $thresholds =
	  $self->{'datastore'}->run_query( 'SELECT thresholds FROM lincode_schemes WHERE scheme_id=?', $scheme_id );
	my @thresholds      = split /;/x, $thresholds;
	my $threshold_count = @thresholds;
	if ( $value_count > $threshold_count ) {
		push @$errors, "LINcode scheme has $threshold_count thresholds but you have entered $value_count.";
		return q();
	}
	my %allow_null = map { $_ => 1 } ( '=', 'NOT' );
	if ( lc($text) eq 'null' && !$allow_null{$operator} ) {
		push @$errors, BIGSdb::Utils::escape_html("'$operator' is not a valid operator for comparing null values.");
		return q();
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	my $modify      = {
		'=' => sub {
			if ( lc($text) eq 'null' ) {
				return "($primary_key NOT IN (SELECT profile_id FROM lincodes WHERE scheme_id=$scheme_id))";
			}
			if ( $value_count != $threshold_count ) {
				push @$errors, "You must enter $threshold_count values to perform an exact match LINcode query.";
				return q();
			}
			my $pg_array = BIGSdb::Utils::get_pg_array( [@values] );
			return
			  "($primary_key IN (SELECT profile_id FROM lincodes WHERE scheme_id=$scheme_id AND lincode='$pg_array'))";
		},
		'starts with' => sub {
			my $i = 1;    #pg arrays are 1-based.
			my @terms;
			foreach my $value (@values) {
				push @terms, "lincode[$i]=$value";
				$i++;
			}
			local $" = q( AND );
			return "($primary_key IN (SELECT profile_id FROM lincodes WHERE scheme_id=$scheme_id AND @terms))";
		},
		'ends with' => sub {
			my $i = $threshold_count;
			my @terms;
			foreach my $value ( reverse @values ) {
				push @terms, "lincode[$i]=$value";
				$i--;
			}
			local $" = q( AND );
			return "($primary_key IN (SELECT profile_id FROM lincodes WHERE scheme_id=$scheme_id AND @terms))";
		},
		'NOT' => sub {
			if ( lc($text) eq 'null' ) {
				return "($primary_key IN (SELECT profile_id FROM lincodes WHERE scheme_id=$scheme_id))";
			}
			my $pg_array = BIGSdb::Utils::get_pg_array( [@values] );
			return "($primary_key NOT IN (SELECT profile_id FROM lincodes "
			  . "WHERE scheme_id=$scheme_id AND lincode='$pg_array'))";
		}
	};
	if ( $modify->{$operator} ) {
		return $modify->{$operator}->();
	} else {
		push @$errors,
		  BIGSdb::Utils::escape_html( qq('$operator' is not a valid operator for comparing LINcodes. Only '=', )
			  . q('starts with', 'ends with', and 'NOT' are appropriate for searching LINcodes.) );
		return q();
	}
	return q();
}

sub _modify_query_by_lincode_field {
	my ( $self, $scheme_id, $field, $operator, $text, $errors ) = @_;
	my $field_info = $self->{'datastore'}->run_query(
		'SELECT * FROM lincode_fields WHERE (scheme_id,field)=(?,?)',
		[ $scheme_id, $field ],
		{ fetch => 'row_hashref' }
	);
	if ( $field_info->{'type'} eq 'integer' && $text ne 'null' && !BIGSdb::Utils::is_int($text) ) {
		push @$errors, "$field (LINcode) is an integer field.";
		return q();
	}
	$field =~ s/'/\\'/gx;
	( my $cleaned_value = uc($text) ) =~ s/'/\\'/gx;
	my $qry;
	my $type = $self->{'datastore'}
	  ->run_query( 'SELECT type FROM lincode_fields WHERE (scheme_id,field)=(?,?)', [ $scheme_id, $field ] );
	my %valid_null = map { $_ => 1 } ( '=', 'NOT' );
	if ( $cleaned_value eq 'NULL' && !$valid_null{$operator} ) {
		push @$errors,
		  q(You can only use '=' and 'NOT' when searching fields linked to LINcode prefixes using null values.);
		return q();
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $pk          = $scheme_info->{'primary_key'};
	my $join_table =
		qq[mv_scheme_$scheme_id LEFT JOIN lincodes ON mv_scheme_$scheme_id.$pk=lincodes.profile_id AND ]
	  . qq[lincodes.scheme_id=$scheme_id LEFT JOIN lincode_prefixes ON ]
	  . q[lincodes.scheme_id=lincode_prefixes.scheme_id AND (]
	  . q[array_to_string(lincodes.lincode,'_') LIKE (REPLACE(lincode_prefixes.prefix,'_',E'\\\_') || E'\\\_' || '%') ]
	  . q[OR array_to_string(lincodes.lincode,'_') = lincode_prefixes.prefix)];
	my %modify = (
		  'NOT' => $cleaned_value eq 'NULL'
		? "($pk IN (SELECT lincodes.profile_id FROM $join_table WHERE lincode_prefixes.field=E'$field'))"
		: "($pk IN (SELECT mv_scheme_$scheme_id.$pk FROM $join_table WHERE (lincode_prefixes.field=E'$field' "
		  . "AND UPPER(lincode_prefixes.value) != E'$cleaned_value') OR lincode_prefixes.value IS NULL))",
		'contains' => "($pk IN (SELECT lincodes.profile_id FROM $join_table WHERE lincode_prefixes.field=E'$field' "
		  . "AND UPPER(lincode_prefixes.value) LIKE E'%$cleaned_value%'))",
		'starts with' => "($pk IN (SELECT lincodes.profile_id FROM $join_table WHERE lincode_prefixes.field=E'$field' "
		  . "AND UPPER(lincode_prefixes.value) LIKE E'$cleaned_value%'))",
		'ends with' => "($pk IN (SELECT lincodes.profile_id FROM $join_table WHERE lincode_prefixes.field=E'$field' "
		  . "AND lincode_prefixes.value LIKE E'%$cleaned_value'))",
		'NOT contain' =>
		  "($pk IN (SELECT mv_scheme_$scheme_id.$pk FROM $join_table WHERE (lincode_prefixes.field=E'$field' "
		  . "AND UPPER(lincode_prefixes.value) NOT LIKE E'%$cleaned_value%' OR lincode_prefixes.value IS NULL)))",
		'=' => $cleaned_value eq 'NULL'
		? "($pk NOT IN (SELECT lincodes.profile_id FROM $join_table WHERE lincode_prefixes.field=E'$field'))"
		: "($pk IN (SELECT lincodes.profile_id FROM $join_table WHERE lincode_prefixes.field=E'$field' "
		  . "AND UPPER(lincode_prefixes.value)=E'$cleaned_value'))"
	);
	if ( $modify{$operator} ) {
		$qry .= $modify{$operator};
	} else {
		$qry .= "($pk IN (SELECT lincodes.profile_id FROM $join_table WHERE lincode_prefixes.field=E'$field' AND ";
		$qry .=
		  $type eq 'integer'
		  ? 'CAST(lincode_prefixes.value AS integer) '
		  : 'lincode_prefixes.value ';
		$qry .= "$operator E'$cleaned_value'))";
	}
	return $qry;
}

sub _print_list_fieldset {
	my ( $self, $scheme_id ) = @_;
	my $q = $self->{'cgi'};
	my ( $field_list, $labels );
	my $fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach (@$fields) {
		push @$field_list, "s_$scheme_id\_$_";
		( $labels->{"s_$scheme_id\_$_"} = $_ ) =~ tr/_/ /;
	}
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	foreach my $locus (@$loci) {
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		push @$field_list, "l_$locus";
		$labels->{"l_$locus"} = $self->clean_locus( $locus, { text_output => 1 } );
	}
	my $display = $self->{'prefs'}->{'list_fieldset'}
	  || $q->param('list') ? 'inline' : 'none';
	say qq(<fieldset id="list_fieldset" style="float:left;display:$display"><legend>Attribute values list</legend>);
	say q(Field:);
	say $q->popup_menu( -name => 'attribute', -values => $field_list, -labels => $labels );
	say q(<br />);
	say $q->textarea(
		-name        => 'list',
		-id          => 'list',
		-rows        => 6,
		-style       => 'width:100%',
		-placeholder => 'Enter list of values (one per line)...'
	);
	say q(</fieldset>);
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $filters_fieldset_display = $self->{'prefs'}->{'filters_fieldset'}
	  || $self->filters_selected ? 'inline' : 'none';
	my $panel_js = $self->get_javascript_panel(qw(scheme list filters));
	my $buffer   = $self->SUPER::get_javascript;
	$buffer .= << "END";
\$(function () {
	\$('#filters_fieldset').css({display:"$filters_fieldset_display"});
   	\$('#scheme_field_tooltip').attr("title", "<h3>Search values</h3><p>Empty field "
  		+ "values can be searched using the term 'null'. </p><h3>Number of fields</h3>"
  		+ "<p>Add more fields by clicking the '+' button.</p>"
  		+ "<h3>Query modifier</h3><p>Select 'AND' for the isolate query to match ALL search "
  		+ "terms, 'OR' to match ANY of these terms.</p>");   	
   	$panel_js
});
 
function loadContent(url) {
	var row = parseInt(url.match(/row=(\\d+)/)[1]);
	var fields = url.match(/fields=([scheme_fields]+)/)[1];
	if (fields == 'scheme_fields'){
		add_rows(url,fields,'scheme_field',row,'scheme_field_heading','add_scheme_fields');
	}
}
END
	return $buffer;
}

sub _highest_entered_fields {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $highest;
	for ( 1 .. MAX_ROWS ) {
		$highest = $_ if defined $q->param("t$_") && $q->param("t$_") ne '';
	}
	return $highest;
}

sub _print_modify_search_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<div id="modify_panel" class="panel">);
	say q(<a class="trigger" id="close_trigger" href="#"><span class="fas fa-lg fa-times"></span></a>);
	say q(<h2>Modify form parameters</h2>);
	say q(<p style="white-space:nowrap">Click to add or remove additional query terms:</p>)
	  . q(<ul style="list-style:none;margin-left:-2em">);
	my $scheme_fieldset_display = $self->{'prefs'}->{'scheme_fieldset'}
	  || $self->_highest_entered_fields ? HIDE : SHOW;
	say qq(<li><a href="" class="button" id="show_scheme">$scheme_fieldset_display</a>);
	say q(Locus/scheme field values</li>);
	my $list_fieldset_display = $self->{'prefs'}->{'list_fieldset'}
	  || $q->param('list') ? HIDE : SHOW;
	say qq(<li><a href="" class="button" id="show_list">$list_fieldset_display</a>);
	say q(Attribute values list</li>);

	if ( $self->{'filters_present'} ) {
		my $filter_fieldset_display = $self->{'prefs'}->{'filters_fieldset'}
		  || $self->filters_selected ? HIDE : SHOW;
		say qq(<li><a href="" class="button" id="show_filters">$filter_fieldset_display</a>);
		say q(Filters</li>);
	}
	say q(</ul>);
	my $save = SAVE;
	say qq(<a id="save_options" class="button" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=query&amp;save_options=1" style="display:none">$save</a> <span id="saving"></span><br />);
	say q(</div>);
	return;
}
1;
