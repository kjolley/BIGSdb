#Written by Keith Jolley
#Copyright (c) 2010-2024, University of Oxford
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
package BIGSdb::TableQueryPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::QueryPage);
use List::MoreUtils qw(none any uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Constants qw(SEQ_FLAGS ALLELE_FLAGS OPERATORS :interface);

sub initiate {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('no_header') ) {
		$self->{'type'} = 'no_header';
		return;
	}
	$self->set_level1_breadcrumbs;
	my $table = $q->param('table');
	$self->{$_} = 1 foreach (qw (noCache tooltips jQuery jQuery.coolfieldset jQuery.multiselect));
	if ( !$q->param('save_options') ) {
		my $guid = $self->get_guid;
		return if !$guid;
		return if !$self->{'datastore'}->is_table($table);
		my $value =
		  $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, "${table}_list_fieldset" );
		$self->{'prefs'}->{"${table}_list_fieldset"} = ( $value // '' ) eq 'on' ? 1 : 0;
	}
	return;
}

sub get_help_url {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $table  = $q->param('table');
	return if !defined $table;
	if ( $self->{'curate'} ) {
		if ( $table eq 'sequences' ) {
			return "$self->{'config'}->{'doclink'}/curator_guide/0030_updating_and_deleting_alleles.html";
		}
	} else {
		if ( $table eq 'sequences' ) {
			return "$self->{'config'}->{'doclink'}/data_query/0020_search_sequence_attributes.html";
		}
		if ( $table eq 'loci' || $table eq 'schemes' || $table eq 'scheme_fields' ) {
			return "$self->{'config'}->{'doclink'}/data_query/0100_options.html"
			  . '#modifying-locus-and-scheme-display-options';
		}
	}
	return;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub print_content {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $q      = $self->{'cgi'};
	my $table  = $q->param('table') || '';
	if ( $q->param('no_header') ) {
		$self->_ajax_content($table);
		return;
	} elsif ( $q->param('save_options') ) {
		$self->_save_options;
		return;
	}
	if ( $table eq 'isolates'
		|| ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) )
	{
		say q(<h1>Table query</h1>);
		$self->print_bad_status(
			{ message => q(You cannot use this function to query the isolate table.), navbar => 1 } );
		return;
	}
	if ( !$self->{'datastore'}->is_table($table) ) {
		say q(<h1>Table query</h1>);
		$self->print_bad_status( { message => q(Invalid table.), navbar => 1 } );
		return;
	}
	my $cleaned = $table;
	$cleaned =~ tr/_/ /;
	my $title = $self->get_title;
	say qq(<h1>$title</h1>);
	my $qry;
	if (   !defined $q->param('currentpage')
		|| ( defined $q->param('pagejump') && $q->param('pagejump') eq '1' )
		|| $q->param('First')
		|| ( ( $q->param('currentpage') // 0 ) == 2 && $q->param('<') ) )
	{
		say q(<noscript>);
		$self->print_bad_status(
			{ message => q(This interface requires that you enable Javascript in your browser.) } );
		say q(</noscript>);
		$self->_print_interface;
	}
	if ( $q->param('submit') || defined $q->param('query_file') || defined $q->param('t1') ) {
		$self->_run_query;
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $table  = $self->{'cgi'}->param('table');
	my %title  = ( sequences => 'Sequence attribute search' );
	if ( $title{$table} ) {
		return $title{$table};
	}
	my $record = $self->get_record_name($table) || 'record';
	return "Query $record information";
}

sub get_javascript {
	my ($self)          = @_;
	my $filter_collapse = $self->filters_selected ? 'false' : 'true';
	my $panel_js        = $self->get_javascript_panel(qw(list));
	my $buffer          = $self->SUPER::get_javascript;
	$buffer .= << "END";
\$(function () {
  	\$('#filters_fieldset').coolfieldset({speed:"fast", collapsed:$filter_collapse});
  	\$('#filters_fieldset').show();
  	
  	\$('#field_tooltip').attr("title", "<h3>Search values</h3><p>Empty field "
  		+ "values can be searched using the term 'null'. </p><h3>Number of fields</h3><p>Add more fields by clicking the '+' button."
  		+ "</p><h3>Query modifier</h3><p>Select 'AND' for the isolate query to match ALL search terms, 'OR' to match ANY of these terms."
  		+ "</p>" );
  	$panel_js
  	\$("select.filter").multiselect({
		header: "Please select...",
		noneSelectedText: "Please select...",
		selectedList: 1,
		menuHeight: 250,
		menuWidth: 300,
		classes: 'filter'
	});
	\$("select.filter.search").multiselectfilter({
		placeholder: 'Search'
	});
});
  	
function loadContent(url) {
	var row = parseInt(url.match(/row=(\\d+)/)[1]);
	var fields = url.match(/fields=([table_fields]+)/)[1];
	if (fields == 'table_fields'){
		add_rows(url,fields,'table_field',row,'table_field_heading','add_table_fields');
	}
}
 
END
	return $buffer;
}

sub _get_select_items {
	my ( $self, $table ) = @_;
	return if !$table;
	if ( !$self->{'datastore'}->is_table($table) ) {
		return;
	}
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my ( @select_items, @order_by );
	my %labels;
	foreach my $att (@$attributes) {
		next if $att->{'hide_query'};
		if ( any { $att->{'name'} eq $_ } qw (sender curator user_id) ) {
			push @select_items, "$att->{'name'} (id)", "$att->{'name'} (surname)", "$att->{'name'} (first_name)",
			  "$att->{'name'} (affiliation)";
		} elsif ( $att->{'query_datestamp'} ) {
			push @select_items, "$att->{'name'} (date)";
		} else {
			push @select_items, $att->{'name'};
		}
		push @order_by, $att->{'name'} if !$att->{'no_order_by'};
		if ( $att->{'name'} eq 'isolate_id' && $table ne 'retired_isolates' ) {
			push @select_items, $self->{'system'}->{'labelfield'};
		}
		if ( $table eq 'sequences' && $att->{'name'} eq 'sequence' ) {
			push @select_items, 'sequence_length';
			push @order_by,     'sequence_length';
		} elsif ( $table eq 'sequence_bin' && $att->{'name'} eq 'comments' ) {
			my $seq_attributes =
			  $self->{'datastore'}
			  ->run_query( 'SELECT key FROM sequence_attributes ORDER BY key', undef, { fetch => 'col_arrayref' } );
			foreach my $key (@$seq_attributes) {
				push @select_items, "ext_$key";
				( my $label = $key ) =~ tr/_/ /;
				$labels{"ext_$key"} = $label;
			}
		}
	}
	foreach my $item (@select_items) {
		( $labels{$item} = $item ) =~ tr/_/ / if !defined $labels{$item};
	}
	return ( \@select_items, \%labels, \@order_by, $attributes );
}

#split so single row can be added by AJAX call
sub _print_table_fields {
	my ( $self, $table, $row, $max_rows, $select_items, $labels ) = @_;
	my $q = $self->{'cgi'};
	say q(<span style="white-space:nowrap">);
	print $q->popup_menu( -name => "s$row", -values => $select_items, -labels => $labels, -class => 'fieldlist' );
	print $q->popup_menu( -name => "y$row", -values => [OPERATORS] );
	say $q->textfield( -name => "t$row", -class => 'value_entry' );
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		print qq(<a id="add_table_fields" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=tableQuery&amp;fields=table_fields&amp;table=$table&amp;row=$next_row&amp;no_header=1" )
		  . q(data-rel="ajax" class="add_button"><span class="fa fas fa-plus"></span></a>);
		say $self->get_tooltip( '', { id => 'field_tooltip' } );
	}
	say q(</span>);
	return;
}

sub _ajax_content {
	my ( $self, $table ) = @_;
	my $system = $self->{'system'};
	my $q      = $self->{'cgi'};
	my $row    = $q->param('row');
	return if !BIGSdb::Utils::is_int($row) || $row > MAX_ROWS || $row < 2;
	my ( $select_items, $labels ) = $self->_get_select_items($table);
	$self->_print_table_fields( $table, $row, 0, $select_items, $labels );
	return;
}

sub _print_interface {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $prefs  = $self->{'prefs'};
	my $q      = $self->{'cgi'};
	my $table  = $q->param('table');
	my ( $select_items, $labels, $order_by, $attributes ) = $self->_get_select_items($table);
	say q(<div class="box" id="queryform"><div class="scrollable">);
	my $table_fields = $self->_highest_entered_fields || 1;
	my $cleaned      = $table;
	$cleaned =~ tr/_/ /;

	if ( $table eq 'sequences' ) {
		if ( $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM locus_extended_attributes)') ) {
			say q(<p>Some loci have additional fields which are not searchable from this general page.  )
			  . q(Search for these at the )
			  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleQuery">)
			  . q(locus-specific query</a> page.  Use this page also for access to the sequence analysis or )
			  . q(export plugins.</p>);
		} else {
			say q(<p>You can also search using the )
			  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleQuery">)
			  . q(locus-specific query</a> page.  Use this page for access to the sequence analysis or export )
			  . q(plugins.</p>);
		}
	}
	say q(<p>Please enter your search criteria below (or leave blank and submit to return all records).);
	if ( !$self->{'curate'} ) {
		say qq( Matching $cleaned will be returned and you will then be )
		  . q(able to update their display and query settings.);
	}
	say q(</p>);
	say $q->start_form;
	say $q->hidden($_) foreach qw (db page table);
	say q(<fieldset style="float:left"><legend>Search criteria</legend>);
	my $table_field_heading = $table_fields == 1 ? 'none' : 'inline';
	say qq(<span id="table_field_heading" style="display:$table_field_heading">)
	  . q(<label for="c0">Combine searches with: </label>);
	say $q->popup_menu( -name => 'c0', -id => 'c0', -values => [qw(AND OR)] );
	say q(</span>);
	say q(<ul id="table_fields">);

	foreach my $i ( 1 .. $table_fields ) {
		say q(<li>);
		$self->_print_table_fields( $table, $i, $table_fields, $select_items, $labels );
		say q(</li>);
	}
	say q(</ul></fieldset>);
	say q(<fieldset style="float:left"><legend>Display</legend>);
	say q(<ul><li><span style="white-space:nowrap"><label for="order" class="display">Order by: </label>);
	say $q->popup_menu( -name => 'order', -id => 'order', -values => $order_by, -labels => $labels );
	say $q->popup_menu( -name => 'direction', -values => [qw(ascending descending)], -default => 'ascending' );
	say q(</span></li><li>);
	say $self->get_number_records_control;
	say q(</li></ul></fieldset>);
	say q(<div style="clear:both"></div>);
	$self->_print_filter_fieldset( $table, $attributes );
	$self->_print_list_fieldset( $table, $attributes );
	$self->print_action_fieldset( { page => 'tableQuery', table => $table, submit_label => 'Search' } );
	$self->_print_modify_search_fieldset;
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub _get_sequence_filters {
	my ($self) = @_;
	my $filters = [];
	if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
		my @flag_values = ( 'any flag', 'no flag', ALLELE_FLAGS );
		push @$filters, $self->get_filter( 'allele_flag', \@flag_values );
	}
	push @$filters, $self->get_scheme_filter;
	return $filters;
}

sub _get_locus_description_filter {
	my ($self) = @_;
	my %labels;
	my $common_names =
	  $self->{'datastore'}
	  ->run_query( 'SELECT DISTINCT common_name FROM loci ORDER BY common_name', undef, { fetch => 'col_arrayref' } );
	return $self->get_filter(
		'common_name',
		$common_names,
		{
			tooltip => 'common names filter - Select a name to filter your search '
			  . 'to only those loci with the selected common name.'
		}
	);
}

sub _get_allele_sequences_filters {
	my ($self) = @_;
	my $filters = [];
	push @$filters, $self->get_scheme_filter;
	push @$filters,
	  $self->get_filter(
		'sequence_flag',
		[ 'any flag', 'no flag', SEQ_FLAGS ],
		{
			tooltip => 'sequence flag filter - Select the appropriate value to '
			  . 'filter tags to only those flagged accordingly.'
		}
	  );
	push @$filters,
	  $self->get_filter(
		'duplicates',
		[qw (1 2 5 10 25 50)],
		{
			text   => 'tags per isolate/locus',
			labels => {
				1  => 'no duplicates',
				2  => '2 or more',
				5  => '5 or more',
				10 => '10 or more',
				25 => '25 or more',
				50 => '50 or more'
			},
			tooltip => 'Duplicates filter - Filter search to only those loci that have '
			  . 'been tagged a specified number of times per isolate.'
		}
	  );
	return $filters;
}

sub _get_dropdown_filter {
	my ( $self, $table, $att ) = @_;
	if (   $att->{'name'} eq 'sender'
		|| $att->{'name'} eq 'curator'
		|| ( $att->{'foreign_key'} // '' ) eq 'users' )
	{
		return $self->get_user_filter( $att->{'name'} );
	}
	if ( $att->{'name'} eq 'scheme_id' ) {
		return $self->get_scheme_filter( { with_pk => $att->{'with_pk'} } );
	}
	if ( $att->{'name'} eq 'locus' ) {
		return $self->get_locus_filter;
	}
	my $desc;
	my $values;
	my %user_special_fields = map { $_ => 1 } qw(surname first_name);
	if ( $att->{'foreign_key'} ) {
		next if $att->{'name'} eq 'scheme_id';
		my @order_fields;
		if ( $att->{'labels'} ) {
			( my $fields_ref, $desc ) = $self->get_all_foreign_key_fields_and_labels($att);
			@order_fields = @$fields_ref;
		} else {
			push @order_fields, 'id';
		}
		local $" = ',';
		$values = $self->{'datastore'}->run_query( "SELECT id FROM $att->{'foreign_key'} ORDER BY @order_fields",
			undef, { fetch => 'col_arrayref' } );
		return if !@$values;
	} elsif ( $table eq 'users' && $user_special_fields{ $att->{'name'} } ) {
		$values = $self->_get_user_table_values( $att->{'name'} );
	} else {
		my $order        = $att->{'type'} eq 'text' ? "lower($att->{'name'})"       : $att->{'name'};
		my $empty_clause = $att->{'type'} eq 'text' ? " WHERE $att->{'name'} <> ''" : '';
		$values = $self->{'datastore'}->run_query( "SELECT $att->{'name'} FROM $table$empty_clause ORDER BY $order",
			undef, { fetch => 'col_arrayref' } );
		@$values = uniq @$values;
	}
	return $self->get_filter( $att->{'name'}, $values, { labels => $desc } );
}

sub _get_user_table_values {
	my ( $self, $field ) = @_;
	my $user_names =
	  $self->{'datastore'}->run_query( 'SELECT user_name FROM users WHERE id>0', undef, { fetch => 'col_arrayref' } );
	my %user = map { $_ => 1 } @$user_names;
	my $values =
	  $self->{'datastore'}
	  ->run_query( "SELECT $field FROM users WHERE $field IS NOT NULL AND id>0", undef, { fetch => 'col_arrayref' } );
	my $user_dbs =
	  $self->{'datastore'}
	  ->run_query( 'SELECT DISTINCT user_db FROM users WHERE user_db IS NOT NULL', undef, { fetch => 'col_arrayref' } );
	foreach my $user_db_id (@$user_dbs) {
		my $user_db       = $self->{'datastore'}->get_user_db($user_db_id);
		my $remote_values = $self->{'datastore'}->run_query( "SELECT user_name,$field FROM users",
			undef, { db => $user_db, fetch => 'all_arrayref', slice => {} } );
		next if !@$remote_values;
		foreach my $remote (@$remote_values) {
			next if !$user{ $remote->{'user_name'} };
			push @$values, $remote->{$field};
		}
	}
	@$values = sort { uc($a) cmp uc($b) } uniq @$values;
	return $values;
}

#Prevent SQL injection attempts.
sub _sanitize_order_field {
	my ( $self, $table ) = @_;
	my ( undef, undef, $order_by, undef ) = $self->_get_select_items($table);
	my $q       = $self->{'cgi'};
	my %allowed = map { $_ => 1 } @$order_by;
	$q->delete('order') if defined $q->param('order') && !$allowed{ $q->param('order') };
	return;
}

sub _run_query {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $system = $self->{'system'};
	my $table  = $q->param('table');
	my $prefs  = $self->{'prefs'};
	my ( $qry, $qry2 );
	my $errors     = [];
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my $set_id     = $self->get_set_id;
	$self->_sanitize_order_field($table);
	my ( $list_file, $data_type );

	if ( !defined $q->param('query_file') ) {
		( $qry, $errors ) = $self->_generate_query($table);
		if ( $table eq 'sequences' && $qry ) {
			$qry =~ s/sequences.sequence_length/length(sequences.sequence)/gx;
		}
		$self->_modify_isolates_for_view( $table, \$qry );
		$self->_modify_seqbin_for_view( $table, \$qry );
		$self->_modify_loci_for_sets( $table, \$qry );
		$self->_modify_schemes_for_sets( $table, \$qry );
		( $list_file, $data_type ) = $self->_modify_by_list( $table, \$qry );
		$self->_filter_query_by_scheme( $table, \$qry );
		$self->_filter_query_by_project( $table, \$qry );
		$self->_filter_query_by_common_name( $table, \$qry );
		$self->_filter_query_by_sequence_filters( $table, \$qry );
		$self->_filter_query_by_allele_definition_filters( $table, \$qry );
		$qry //= '1=1';    #So that we always have a WHERE clause even with no arguments selected.
		$qry2 = "SELECT * FROM $table WHERE ($qry)";
		$qry2 = $self->_process_dropdown_filters( $qry2, $table, $attributes );

		if ( $table eq 'sequences' ) {

			#Alleles can be set to 0 or N for arbitrary profile definitions
			$qry2 .= " AND $table.allele_id NOT IN ('0', 'N', 'P')";
		}
		$qry2 .= " ORDER BY $table.";
		my $default_order;
		if    ( $table eq 'sequences' )       { $default_order = 'locus' }
		elsif ( $table eq 'history' )         { $default_order = 'timestamp' }
		elsif ( $table eq 'profile_history' ) { $default_order = 'timestamp' }
		else                                  { $default_order = 'id' }
		my $order = $q->param('order') || $default_order;
		$qry2 .= $order;
		$qry2 =~ s/sequences.sequence_length/length(sequences.sequence)/gx if $table eq 'sequences';
		my $dir          = ( $q->param('direction') // '' ) eq 'descending' ? 'desc' : 'asc';
		my @primary_keys = $self->{'datastore'}->get_primary_keys($table);
		local $" = ",$table.";
		$qry2 .= " $dir";

		foreach my $pk (@primary_keys) {
			next if $pk eq $order;
			if ( $pk eq 'allele_id' ) {

				#allele_id field is a text field because some loci can have text identifers.
				#sort by integers first, then alphabetically.
				my $field = "${table}.allele_id";
				$qry2 .=
					qq(,COALESCE(SUBSTRING($field FROM '^(\\d+)')::INTEGER, 99999999),)
				  . qq(SUBSTRING($field FROM '^\\d* *(.*"?")(\\d+)"?"\$'),)
				  . qq(COALESCE(SUBSTRING($field FROM '(\\d+)\$')::INTEGER, 0),$field);
			} else {
				$qry2 .= ",${table}.$pk";
			}
		}
		$qry2 .= ';';
	} else {
		$qry2 = $self->get_query_from_temp_file( scalar $q->param('query_file') );
		if ( $q->param('list_file') && $q->param('list_type') ) {
			$self->{'datastore'}->create_temp_list_table( $q->param('list_type'), scalar $q->param('list_file') );
		}
	}
	$q->param( list_file => $list_file ) if $list_file;
	$q->param( datatype  => $data_type ) if $data_type;
	my @hidden_attributes;
	push @hidden_attributes, 'c0';
	foreach my $i ( 1 .. MAX_ROWS ) {
		push @hidden_attributes, "s$i", "t$i", "y$i";
	}
	push @hidden_attributes, $_->{'name'} . '_list' foreach (@$attributes);
	push @hidden_attributes, qw (sequence_flag_list duplicates_list common_name_list scheme_id_list list_file datatype);
	if (@$errors) {
		local $" = q(<br />);
		$self->print_bad_status( { message => q(Problem with search criteria:), detail => qq(@$errors) } );
	} else {
		my $args = { table => $table, query => $qry2, hidden_attributes => \@hidden_attributes };
		$args->{'passed_qry_file'} = $q->param('query_file') if defined $q->param('query_file');
		$self->paged_display($args);
	}
	return;
}

sub _filter_query_by_scheme {
	my ( $self, $table, $qry_ref ) = @_;
	my $q = $self->{'cgi'};
	return if ( $q->param('scheme_id_list') // '' ) eq '';
	return if !BIGSdb::Utils::is_int( scalar $q->param('scheme_id_list') );
	my %allowed_tables =
	  map { $_ => 1 } qw (loci scheme_fields schemes scheme_members client_dbase_schemes allele_designations sequences);
	return if !$allowed_tables{$table};
	my $sub_qry;

	#Don't do this for allele_sequences as this has its own method
	my $scheme_id = $q->param('scheme_id_list');
	my ( $identifier, $field );
	my %set_id_and_field = (
		loci                => sub { ( $identifier, $field ) = ( 'id',    'locus' ) },
		allele_designations => sub { ( $identifier, $field ) = ( 'locus', 'locus' ) },
		sequences           => sub { ( $identifier, $field ) = ( 'locus', 'locus' ) },
		schemes             => sub { ( $identifier, $field ) = ( 'id',    'scheme_id' ) }
	);
	if ( $set_id_and_field{$table} ) {
		$set_id_and_field{$table}->();
	} else {
		( $identifier, $field ) = ( 'scheme_id', 'scheme_id' );
	}
	my $set_id = $self->get_set_id;
	if ( $q->param('scheme_id_list') eq '0' ) {
		my $set_clause = $set_id ? "WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)" : '';
		$sub_qry = "$identifier NOT IN (SELECT $field FROM scheme_members $set_clause)";
	} else {
		if ( $table eq 'schemes' ) {
			$sub_qry = "$identifier = $scheme_id";
		} else {
			$sub_qry = "$identifier IN (SELECT $field FROM scheme_members WHERE scheme_id = $scheme_id)";
		}
	}
	if ($$qry_ref) {
		$$qry_ref .= " AND ($sub_qry)";
	} else {
		$$qry_ref = "($sub_qry)";
	}
	return;
}

sub _filter_query_by_project {
	my ( $self, $table, $qry_ref ) = @_;
	my $q = $self->{'cgi'};
	return if ( $q->param('project_list') // q() ) eq q();
	return if $table ne 'isolate_aliases';
	my $project_id = $q->param('project_list');
	return if !BIGSdb::Utils::is_int($project_id);
	my $sub_qry = "$table.isolate_id IN (SELECT isolate_id FROM project_members WHERE project_id=$project_id)";
	if ($$qry_ref) {
		$$qry_ref .= " AND ($sub_qry)";
	} else {
		$$qry_ref = "($sub_qry)";
	}
	return;
}

sub _filter_query_by_common_name {
	my ( $self, $table, $qry_ref ) = @_;
	my $q = $self->{'cgi'};
	return if $table ne 'locus_descriptions';
	return if ( $q->param('common_name_list') // q() ) eq q();
	my $common_name = $q->param('common_name_list');
	$common_name =~ s/'/\\'/gx;
	my $sub_qry =
		'locus_descriptions.locus IN (SELECT locus FROM locus_descriptions JOIN loci ON loci.id = '
	  . "locus_descriptions.locus WHERE common_name = E'$common_name')";
	if ($$qry_ref) {
		$$qry_ref .= " AND ($sub_qry)";
	} else {
		$$qry_ref = "($sub_qry)";
	}
	return;
}

sub _filter_query_by_sequence_filters {
	my ( $self, $table, $qry_ref ) = @_;
	return if $table ne 'allele_sequences';
	my $q = $self->{'cgi'};
	my $qry2;
	my @clauses;
	if ( any { $q->param($_) ne '' } qw (sequence_flag_list duplicates_list scheme_id_list) ) {
		if ( $q->param('sequence_flag_list') ne '' ) {
			my $flag_qry;
			if ( $q->param('sequence_flag_list') eq 'no flag' ) {
				$flag_qry = 'allele_sequences.id IN (SELECT allele_sequences.id FROM allele_sequences '
				  . 'LEFT JOIN sequence_flags ON sequence_flags.id = allele_sequences.id WHERE flag IS NULL)';
			} else {
				$flag_qry =
					'allele_sequences.id IN (SELECT allele_sequences.id FROM allele_sequences JOIN sequence_flags ON '
				  . 'sequence_flags.id = allele_sequences.id';
				if ( any { $q->param('sequence_flag_list') eq $_ } SEQ_FLAGS ) {
					my $flag = $q->param('sequence_flag_list');
					$flag_qry .= qq( WHERE flag = '$flag');
				}
				$flag_qry .= ')';
			}
			push @clauses, $flag_qry;
		}
		if ( $q->param('duplicates_list') ne '' ) {
			my $match = BIGSdb::Utils::is_int( $q->param('duplicates_list') ) ? $q->param('duplicates_list') : 1;
			my $not   = $match == 1                                           ? 'NOT'                        : '';

			#no dups == NOT 2 or more
			$match = 2 if $match == 1;
			my $dup_qry =
				'allele_sequences.id IN (SELECT allele_sequences.id WHERE '
			  . "(allele_sequences.locus,allele_sequences.isolate_id) $not IN (SELECT "
			  . "locus,isolate_id FROM allele_sequences GROUP BY locus,isolate_id HAVING count(*)>=$match))";
			push @clauses, $dup_qry;
		}
		if ( $q->param('scheme_id_list') ne '' ) {
			my $scheme_qry;
			if ( $q->param('scheme_id_list') eq '0' || !BIGSdb::Utils::is_int( scalar $q->param('scheme_id_list') ) ) {
				$scheme_qry = 'allele_sequences.locus NOT IN (SELECT locus FROM scheme_members)';
			} else {
				my $scheme_id = $q->param('scheme_id_list');
				$scheme_qry =
					'allele_sequences.locus IN (SELECT DISTINCT allele_sequences.locus FROM '
				  . 'allele_sequences JOIN scheme_members ON allele_sequences.locus = scheme_members.locus '
				  . "WHERE scheme_id=$scheme_id)";
			}
			push @clauses, $scheme_qry;
		}
	}
	return if !@clauses;
	local $" = ') AND (';
	if ($$qry_ref) {
		$$qry_ref .= " AND (@clauses)";
	} else {
		$$qry_ref = "(@clauses)";
	}
	return;
}

sub _filter_query_by_allele_definition_filters {
	my ( $self, $table, $qry_ref ) = @_;
	return if $table ne 'sequences';
	my $q = $self->{'cgi'};
	return if ( $q->param('allele_flag_list')       // '' ) eq '';
	return if ( $self->{'system'}->{'allele_flags'} // '' ) ne 'yes';
	my $sub_qry;
	if ( $q->param('allele_flag_list') eq 'no flag' ) {
		$sub_qry = '(sequences.locus,sequences.allele_id) NOT IN (SELECT locus,allele_id FROM allele_flags)';
	} else {
		$sub_qry = '(sequences.locus,sequences.allele_id) IN (SELECT locus,allele_id FROM allele_flags';
		if ( any { $q->param('allele_flag_list') eq $_ } ALLELE_FLAGS ) {
			my $flag = $q->param('allele_flag_list');
			$sub_qry .= qq( WHERE flag = '$flag');
		}
		$sub_qry .= ')';
	}
	if ($$qry_ref) {
		$$qry_ref .= " AND ($sub_qry)";
	} else {
		$$qry_ref = "($sub_qry)";
	}
	return;
}

sub _process_dropdown_filters {
	my ( $self, $qry, $table, $attributes ) = @_;
	my $q                 = $self->{'cgi'};
	my %user_remote_field = map { $_ => 1 } qw(surname first_name);
	foreach my $att (@$attributes) {
		my $name  = $att->{'name'};
		my $param = qq(${name}_list);
		if ( defined $q->param($param) && $q->param($param) ne '' ) {
			my $value;
			if ( $name eq 'locus' ) {
				( $value = $q->param('locus_list') ) =~ s/^cn_//x;
			} else {
				$value = $q->param($param);
			}
			my $field = qq($table.$name);
			if ( $qry !~ /WHERE\ \(\)\s*$/x ) {
				$qry .= q( AND );
			} else {
				$qry = qq(SELECT * FROM $table WHERE );
			}
			$value =~ s/'/\\'/gx;
			my $clause = ( lc($value) eq 'null' ? qq($name is null) : qq($field = E'$value') );
			if ( $table eq 'users' && $user_remote_field{$name} ) {
				$clause = $self->_modify_user_fields_in_remote_user_dbs( $clause, $name, '=', $value );
			}
			$qry .= $clause;
		}
	}
	return $qry;
}

sub _get_field_attributes {
	my ( $self, $table, $field ) = @_;
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my $thisfield  = {};
	foreach my $att (@$attributes) {
		if ( $att->{'name'} eq $field ) {
			$thisfield = $att;
			last;
		}
	}
	$thisfield->{'type'} = 'int' if $field eq 'sequence_length';
	my $clean_fieldname;
	if ( $table eq 'sequence_bin' && $field =~ /^ext_(.*)/x ) {
		$clean_fieldname = $1;
		my $type =
		  $self->{'datastore'}->run_query( 'SELECT type FROM sequence_attributes WHERE key=?', $clean_fieldname );
		$thisfield->{'type'} = $type ? $type : 'text';
	}

	#Timestamps are too awkward to search with so only search on date component
	if ( $field =~ /\ \(date\)$/x ) {
		$thisfield->{'type'} = 'date';
	}
	return ( $thisfield, $clean_fieldname );
}

sub _check_invalid_fieldname {
	my ( $self, $table, $field, $errors ) = @_;
	my $attributes     = $self->{'datastore'}->get_table_field_attributes($table);
	my @sender_fields  = ( 'sender (id)',  'sender (surname)',  'sender (first_name)',  'sender (affiliation)', );
	my @curator_fields = ( 'curator (id)', 'curator (surname)', 'curator (first_name)', 'curator (affiliation)' );
	my @user_fields    = ( 'user_id (id)', 'user_id (surname)', 'user_id (first_name)', 'user_id (affiliation)' );
	my %allowed        = map { $_->{'name'} => 1 } @$attributes;
	$allowed{$_} = 1 foreach @curator_fields;
	my $extended = [];

	if ( $table eq 'sequence_bin' ) {
		$extended = $self->{'datastore'}
		  ->run_query( q(SELECT 'ext_'||key FROM sequence_attributes), undef, { fetch => 'col_arrayref' } );
	}
	my $additional = {
		sequences           => [ qw(sequence_length), @sender_fields ],
		sequence_bin        => [ @$extended,     @sender_fields, $self->{'system'}->{'labelfield'} ],
		allele_designations => [ @sender_fields, $self->{'system'}->{'labelfield'} ],
		allele_sequences    => [ $self->{'system'}->{'labelfield'} ],
		project_members     => [ $self->{'system'}->{'labelfield'} ],
		history             => [ $self->{'system'}->{'labelfield'} ],
		isolate_aliases     => [ $self->{'system'}->{'labelfield'} ],
		refs                => [ $self->{'system'}->{'labelfield'} ],
		user_group_members  => [@user_fields],
		profile_history     => ['timestamp (date)'],
		history             => [ $self->{'system'}->{'labelfield'}, 'timestamp (date)' ]
	};
	if ( $additional->{$table} ) {
		foreach my $field ( @{ $additional->{$table} } ) {
			$allowed{$field} = 1;
		}
	}
	if ( !$allowed{$field} ) {

		#Prevent cross-site scripting vulnerability
		( my $cleaned_field = $field ) =~ s/[^A-z].*$//x;
		push @$errors, qq($cleaned_field is not a valid field name.);
		$logger->error("Attempt to modify fieldname: $field (table: $table)");
		return 1;
	}
	return;
}

sub _generate_query {
	my ( $self, $table ) = @_;
	my $q = $self->{'cgi'};
	my $qry;
	my $errors      = [];
	my $andor       = $q->param('c0') // 'AND';
	my $first_value = 1;
	my $set_id      = $self->get_set_id;
	foreach my $i ( 1 .. MAX_ROWS ) {
		next if !defined $q->param("t$i") || $q->param("t$i") eq q();
		my $field = $q->param("s$i") // q();
		next if $self->_check_invalid_fieldname( $table, $field, $errors );
		my $operator = $q->param("y$i") // '=';
		my $text     = $q->param("t$i");
		$text = $self->_modify_locus_in_sets( $field, $text );
		$self->process_value( \$text );
		my ( $thisfield, $clean_fieldname ) = $self->_get_field_attributes( $table, $field );
		next
		  if $self->_is_field_value_invalid(
			{
				field           => $field,
				thisfield       => $thisfield,
				clean_fieldname => $clean_fieldname,
				text            => $text,
				operator        => $operator,
				errors          => $errors
			}
		  );
		my $modifier = ( $i > 1 && !$first_value ) ? qq( $andor ) : q();
		$first_value = 0;
		my $args = {
			table     => $table,
			field     => $field,
			text      => $text,
			modifier  => $modifier,
			operator  => $operator,
			thisfield => $thisfield,
			qry_ref   => \$qry
		};
		next if $self->_modify_query_extended_attributes($args);
		next if $self->_modify_query_search_by_isolate($args);
		next if $self->_modify_query_search_by_users($args);
		next if $self->_modify_query_search_timestamp_by_date($args);
		$self->_modify_query_standard_field($args);
		$qry = $self->_modify_user_fields_in_remote_user_dbs( $qry, $field, $operator, $text );
	}
	return ( $qry, $errors );
}

sub _modify_query_standard_field {
	my ( $self, $args ) = @_;
	my ( $table, $field, $text, $modifier, $operator, $thisfield, $qry_ref ) =
	  @{$args}{qw(table field text modifier operator thisfield qry_ref)};
	$$qry_ref .= $modifier;
	my %methods = (
		'NOT' => sub {
			if ( lc($text) eq 'null' ) {
				$$qry_ref .= "$table.$field is not null";
			} else {
				$$qry_ref .=
				  $thisfield->{'type'} ne 'text'
				  ? "(NOT $table.$field = '$text'"
				  : "(NOT upper($table.$field) = upper(E'$text')";
				$$qry_ref .= " OR $table.$field IS NULL)";
			}
		},
		'contains' => sub {
			$$qry_ref .=
			  $thisfield->{'type'} ne 'text'
			  ? "CAST($table.$field AS text) LIKE '\%$text\%'"
			  : "$table.$field ILIKE E'\%$text\%'";
		},
		'starts with' => sub {
			$$qry_ref .=
			  $thisfield->{'type'} ne 'text'
			  ? "CAST($table.$field AS text) LIKE '$text\%'"
			  : "$table.$field ILIKE E'$text\%'";
		},
		'ends with' => sub {
			$$qry_ref .=
			  $thisfield->{'type'} ne 'text'
			  ? "CAST($table.$field AS text) LIKE '\%$text'"
			  : "$table.$field ILIKE E'\%$text'";
		},
		'NOT contain' => sub {
			$$qry_ref .=
			  $thisfield->{'type'} ne 'text'
			  ? "(NOT CAST($table.$field AS text) LIKE '\%$text\%'"
			  : "(NOT $table.$field ILIKE E'\%$text\%'";
			$$qry_ref .= " OR $table.$field IS NULL)";
		},
		'=' => sub {
			if ( $thisfield->{'type'} eq 'text' ) {
				$$qry_ref .=
				  ( lc($text) eq 'null' ? "$table.$field is null" : "upper($table.$field) = upper(E'$text')" );
			} else {
				$$qry_ref .= ( lc($text) eq 'null' ? "$table.$field is null" : "$table.$field = '$text'" );
			}
		}
	);
	if ( $methods{$operator} ) {
		$methods{$operator}->();
	} else {
		if ( ( $table eq 'sequences' || $table eq 'allele_designations' ) && $field eq 'allele_id' ) {
			if ( $self->_are_only_int_allele_ids_used && BIGSdb::Utils::is_int($text) ) {
				$$qry_ref .= "CAST($table.$field AS integer)";
			} else {
				$$qry_ref .= "$table.$field";
			}
			$$qry_ref .= " $operator E'$text'";
		} else {
			$$qry_ref .= "$table.$field $operator E'$text'";
		}
	}
	return;
}

sub _modify_query_extended_attributes {
	my ( $self, $args ) = @_;
	my ( $table, $field, $text, $modifier, $operator, $thisfield, $qry_ref ) =
	  @{$args}{qw(table field text modifier operator thisfield qry_ref)};
	if ( $table eq 'sequence_bin' && $field =~ /^ext_/x ) {
		$$qry_ref .= $modifier;
		$field =~ s/^ext_//x;
		if ( lc($text) eq 'null' ) {
			my $inv_not = $operator =~ /NOT/x ? q() : ' NOT';
			return "sequence_bin.id$inv_not IN (SELECT seqbin_id FROM sequence_attribute_values WHERE key='$field')";
		}
		my $not = $operator =~ /NOT/x ? ' NOT' : '';
		$$qry_ref .= "sequence_bin.id$not IN (SELECT seqbin_id FROM sequence_attribute_values WHERE key='$field' AND ";
		my %terms = (
			'contains'    => "value ILIKE E'%$text%'",
			'NOT contain' => "value ILIKE E'%$text%'",
			'starts with' => "value ILIKE E'$text%'",
			'ends with'   => "value ILIKE E'%$text'",
			'NOT'         => "UPPER(value) = UPPER(E'$text')",
			'='           => "UPPER(value) = UPPER(E'$text')"
		);
		if ( $terms{$operator} ) {
			$$qry_ref .= $terms{$operator};
		} else {
			if ( $thisfield->{'type'} eq 'integer' ) {
				$$qry_ref .= "CAST(value AS INT) $operator CAST(E'$text' AS INT)";
			} elsif ( $thisfield->{'type'} eq 'float' ) {
				$$qry_ref .= "CAST(value AS FLOAT) $operator CAST(E'$text' AS FLOAT)";
			} else {
				$$qry_ref .= "UPPER(value) $operator UPPER(E'$text')";
			}
		}
		$$qry_ref .= ')';
		return 1;
	}
	return;
}

sub _modify_query_search_by_isolate {
	my ( $self, $args ) = @_;
	my ( $table, $field, $text, $modifier, $operator, $qry_ref ) =
	  @{$args}{qw(table field text modifier operator qry_ref)};
	my %table_linked_to_isolate = map { $_ => 1 }
	  qw (allele_sequences allele_designations sequence_bin project_members isolate_aliases history refs);
	return if !$table_linked_to_isolate{$table};
	return if $field ne $self->{'system'}->{'labelfield'};
	$$qry_ref .= $modifier;
	$$qry_ref .= "$table.isolate_id IN (SELECT id FROM $self->{'system'}->{'view'} WHERE ";
	my $att     = $self->{'xmlHandler'}->get_field_attributes( $self->{'system'}->{'labelfield'} );
	my %methods = (
		NOT => sub {
			if ( $text eq '<blank>' || lc($text) eq 'null' ) {
				$$qry_ref .= "$field is not null";
			} else {
				if ( $att->{'type'} eq 'int' ) {
					$$qry_ref .= "NOT CAST($field AS text) = E'$text'";
				} else {
					$$qry_ref .= "NOT upper($field) = upper(E'$text') AND $self->{'system'}->{'view'}.id NOT IN "
					  . "(SELECT isolate_id FROM isolate_aliases WHERE upper(alias) = upper(E'$text'))";
				}
			}
		},
		contains => sub {
			if ( $att->{'type'} eq 'int' ) {
				$$qry_ref .= "CAST($field AS text) LIKE E'\%$text\%'";
			} else {
				$$qry_ref .=
				  "upper($field) LIKE upper(E'\%$text\%') OR $self->{'system'}->{'view'}.id IN (SELECT isolate_id FROM "
				  . "isolate_aliases WHERE upper(alias) LIKE upper(E'\%$text\%'))";
			}
		},
		'starts with' => sub {
			if ( $att->{'type'} eq 'int' ) {
				$$qry_ref .= "CAST($field AS text) LIKE E'$text\%'";
			} else {
				$$qry_ref .=
					"upper($field) LIKE upper(E'$text\%') OR $self->{'system'}->{'view'}.id IN (SELECT isolate_id FROM "
				  . "isolate_aliases WHERE upper(alias) LIKE upper(E'$text\%'))";
			}
		},
		'ends with' => sub {
			if ( $att->{'type'} eq 'int' ) {
				$$qry_ref .= "CAST($field AS text) LIKE E'\%$text'";
			} else {
				$$qry_ref .=
					"upper($field) LIKE upper(E'\%$text') OR $self->{'system'}->{'view'}.id IN (SELECT isolate_id FROM "
				  . "isolate_aliases WHERE upper(alias) LIKE upper(E'\%$text'))";
			}
		},
		'NOT contain' => sub {
			if ( $att->{'type'} eq 'int' ) {
				$$qry_ref .= "NOT CAST($field AS text) LIKE E'\%$text\%'";
			} else {
				$$qry_ref .= "NOT upper($field) LIKE upper(E'\%$text\%') AND $self->{'system'}->{'view'}.id NOT IN "
				  . "(SELECT isolate_id FROM isolate_aliases WHERE upper(alias) LIKE upper(E'\%$text\%'))";
			}
		},
		'=' => sub {
			if ( lc( $att->{'type'} ) eq 'text' ) {
				$$qry_ref .= (
					( $text eq '<blank>' || lc($text) eq 'null' )
					? "$field is null"
					: "upper($field) = upper(E'$text') OR $self->{'system'}->{'view'}.id IN "
					  . "(SELECT isolate_id FROM isolate_aliases WHERE upper(alias) = upper(E'$text'))"
				);
			} else {
				$$qry_ref .=
				  ( ( $text eq '<blank>' || lc($text) eq 'null' ) ? "$field is null" : "$field = E'$text'" );
			}
		}
	);
	if ( $methods{$operator} ) {
		$methods{$operator}->();
	} else {
		$$qry_ref .= "$field $operator E'$text'";
	}
	$$qry_ref .= ')';
	return 1;
}

sub _modify_query_search_by_users {
	my ( $self, $args ) = @_;
	my ( $table, $field, $text, $modifier, $operator, $qry_ref ) =
	  @{$args}{qw(table field text modifier operator qry_ref)};
	if (
		any {
			$field =~ /(.*)\ \($_\)$/x;
		}
		qw (id surname first_name affiliation)
	  )
	{
		$$qry_ref .= $modifier . $self->search_users( $field, $operator, $text, $table );
		return 1;
	}
	return;
}

sub _modify_query_search_timestamp_by_date {
	my ( $self, $args ) = @_;
	my ( $table, $field, $text, $modifier, $operator, $qry_ref ) =
	  @{$args}{qw(table field text modifier operator qry_ref)};
	if ( $field =~ /(.*)\ \(date\)$/x ) {
		my $db_field = $1;
		$$qry_ref .= $modifier;
		if ( $operator eq 'NOT' ) {
			$$qry_ref .= "(NOT date($table.$db_field) = '$text')";
		} else {
			$$qry_ref .= "(date($table.$db_field) $operator '$text')";
		}
		return 1;
	}
	return;
}

sub _is_field_value_invalid {
	my ( $self, $args ) = @_;
	my ( $field, $thisfield, $clean_fieldname, $text, $operator, $errors ) =
	  @{$args}{qw(field thisfield clean_fieldname text operator errors)};

	#Field may not actually exist in table (e.g. isolate_id in allele_sequences)
	if ( $thisfield->{'type'} ) {
		return 1
		  if $self->check_format(
			{
				field           => $field,
				text            => $text,
				type            => lc( $thisfield->{'type'} ),
				operator        => $operator,
				clean_fieldname => $clean_fieldname
			},
			$errors
		  );
	} elsif ( $field =~ /(.*)\ \(id\)$/x || $field eq 'isolate_id' ) {
		return 1
		  if $self->check_format( { field => $field, text => $text, type => 'int', operator => $operator }, $errors );
	}
	return;
}

sub _modify_locus_in_sets {
	my ( $self, $field, $text ) = @_;
	my $set_id = $self->get_set_id;
	if ( $field eq 'locus' && $set_id ) {
		$text = $self->{'datastore'}->get_set_locus_real_id( $text, $set_id );
	}
	return $text;
}

sub _modify_user_fields_in_remote_user_dbs {
	my ( $self, $qry, $field, $operator, $text ) = @_;
	my %remote_fields = map { $_ => 1 } qw(surname first_name affiliation email);
	return $qry if !$remote_fields{$field};
	my $and_or       = 'OR';
	my %modify_term  = map { $_ => q(LIKE UPPER(?)) } ( 'contains', 'starts with', 'ends with', 'NOT', 'NOT contain' );
	my %modify_value = (
		'contains'    => qq(\%$text\%),
		'starts with' => qq($text\%),
		'ends with'   => qq(\%$text),
		'NOT contain' => qq(\%$text\%)
	);
	my $term  = $modify_term{$operator}  // qq($operator UPPER(?));
	my $value = $modify_value{$operator} // $text;
	my $remote_db_ids =
	  $self->{'datastore'}
	  ->run_query( 'SELECT DISTINCT user_db FROM users WHERE user_db IS NOT NULL', undef, { fetch => 'col_arrayref' } );
	return $qry if !@$remote_db_ids;
	my @user_names;
	my $local_users =
	  $self->{'datastore'}
	  ->run_query( 'SELECT user_name,user_db FROM users', undef, { fetch => 'all_arrayref', slice => {} } );
	my $local_users_in_db = {};

	foreach my $local_user (@$local_users) {
		$local_user->{'user_db'} //= 0;
		$local_users_in_db->{ $local_user->{'user_name'} }->{ $local_user->{'user_db'} } = 1;
	}
	foreach my $user_db_id (@$remote_db_ids) {
		my $user_db  = $self->{'datastore'}->get_user_db($user_db_id);
		my $user_qry = "SELECT user_name FROM users WHERE UPPER($field) $term";
		my $remote_user_names =
		  $self->{'datastore'}->run_query( $user_qry, $value, { db => $user_db, fetch => 'col_arrayref' } );
		foreach my $user_name (@$remote_user_names) {
			( my $cleaned = $user_name ) =~ s/'/\\'/gx;

			#Only add user if exists in local database with the same user_db
			push @user_names, $cleaned if $local_users_in_db->{$user_name}->{$user_db_id};
		}
	}
	if ( $text eq 'null' && $operator eq '=' ) {
		$qry = qq(($qry AND user_db IS NULL));
	}
	return $qry if !@user_names;
	local $" = q(',E');
	$and_or = 'AND NOT' if $operator =~ /NOT/;
	$qry    = qq(($qry $and_or user_name IN (E'@user_names')));
	return $qry;
}

sub _modify_isolates_for_view {
	my ( $self, $table, $qry_ref ) = @_;
	return if none { $table eq $_ } qw(allele_designations isolate_aliases project_members refs sequence_bin history);
	my $view = $self->{'system'}->{'view'};
	if ( $view ne 'isolates' ) {
		$$qry_ref .= q[ AND] if $$qry_ref;
		$$qry_ref .= qq[ ($table.isolate_id IN (SELECT id FROM $view))];
	}
	return;
}

sub _modify_seqbin_for_view {
	my ( $self, $table, $qry_ref ) = @_;
	return if none { $table eq $_ } qw(allele_sequences);
	my $view = $self->{'system'}->{'view'};
	if ( $view ne 'isolates' ) {
		$$qry_ref .= q[ AND] if $$qry_ref;
		$$qry_ref .=
		  qq[ ($table.seqbin_id IN (SELECT id FROM sequence_bin WHERE isolate_id IN (SELECT id FROM $view)))];
	}
	return;
}

sub _modify_loci_for_sets {
	my ( $self, $table, $qry_ref ) = @_;
	my $set_id = $self->get_set_id;
	my %table_with_locus =
	  map { $_ => 1 } qw(locus_descriptions locus_aliases scheme_members allele_designations sequences);
	my $identifier;
	if    ( $table eq 'loci' )          { $identifier = 'id' }
	elsif ( $table_with_locus{$table} ) { $identifier = 'locus' }
	else                                { return }
	if ($set_id) {
		$$qry_ref .= q[ AND] if $$qry_ref;
		$$qry_ref .=
			qq[ ($table.$identifier IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT ]
		  . qq[scheme_id FROM set_schemes WHERE set_id=$set_id)) OR $table.$identifier IN (SELECT locus FROM ]
		  . qq[set_loci WHERE set_id=$set_id))];
	}
	return;
}

sub _modify_schemes_for_sets {
	my ( $self, $table, $qry_ref ) = @_;
	my $set_id = $self->get_set_id;
	my $identifier;
	if    ( $table eq 'schemes' )         { $identifier = 'id' }
	elsif ( $table eq 'scheme_members' )  { $identifier = 'scheme_id' }
	elsif ( $table eq 'profile_history' ) { $identifier = 'scheme_id' }
	else                                  { return }
	if ($set_id) {
		$$qry_ref .= ' AND ' if $$qry_ref;
		$$qry_ref .= " ($table.$identifier IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id))";
	}
	return;
}

sub _modify_by_list {
	my ( $self, $table, $qry_ref ) = @_;
	my $q = $self->{'cgi'};
	return if !$q->param('list');
	my $field      = $q->param('attribute');
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	if ( !defined $attributes ) {
		$logger->error("No attributes found for $table $field");
		return;
	}
	my $type;
	foreach my $att (@$attributes) {
		next if $att->{'name'} ne $field;
		$type = $att->{'type'};
	}
	if ( !defined $type ) {
		$logger->error("No type defined for $table $field");
		return;
	}
	my @list = split /\n/x, $q->param('list');
	@list = uniq @list;
	BIGSdb::Utils::remove_trailing_spaces_from_list( \@list );
	my $cleaned_list = $self->clean_list( $type, \@list );
	if ( !@$cleaned_list ) {    #List exists but there is nothing valid in there. Return no results.
		$$qry_ref .= ' AND FALSE';
		return;
	}
	my $temp_table =
	  $self->{'datastore'}->create_temp_list_table_from_array( $type, $cleaned_list, { table => 'temp_list' } );
	my $list_file = BIGSdb::Utils::get_random() . '.list';
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$list_file";
	open( my $fh, '>:encoding(utf8)', $full_path ) || $logger->error("Cannot open $full_path for writing");
	say $fh $_ foreach @$cleaned_list;
	close $fh;
	if ( $$qry_ref ) {
		$$qry_ref .= ' AND ';
	}
	$$qry_ref .= $type eq 'text'
	  ? "(UPPER($field) IN (SELECT value FROM $temp_table))"
	  : "($field IN (SELECT value FROM $temp_table))";
	return $list_file, $type;
}

sub print_additional_headerbar_functions {
	my ( $self, $filename ) = @_;
	return if $self->{'curate'};
	my $q       = $self->{'cgi'};
	my $table   = $q->param('table');
	my %allowed = map { $_ => 1 } qw(schemes loci scheme_fields);
	return if !$allowed{$table};
	return if $table eq 'loci' && ( $self->{'system'}->{'dbtype'} // q() ) ne 'isolates';
	my $record = $self->get_record_name($table);
	say q(<fieldset><legend>Customize</legend>);
	say $q->start_form;
	say $q->submit( -name => 'customize', -label => ucfirst("$record options"), -class => 'small_submit' );
	$q->param( page     => 'customize' );
	$q->param( filename => $filename );
	say $q->hidden($_) foreach qw (db filename table page);
	say $q->end_form;
	say q(</fieldset>);
	return;
}

#If all loci used have integer allele_ids then cast to int when performing a '<' or '>' query.
#If not the query has to be treated as text
sub _are_only_int_allele_ids_used {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $any_text_ids_used =
	  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM loci WHERE allele_id_format=?)', 'text' );
	return 1 if !$any_text_ids_used;
	if ( $q->param('locus_list') ) {
		( my $locus = $q->param('locus_list') ) =~ s/^cn_//x;
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		return 1 if $locus_info->{'allele_id_format'} eq 'integer';
	}
	return;
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
	my $q      = $self->{'cgi'};
	my $table  = $q->param('table');
	say q(<div id="modify_panel" class="panel">);
	say q(<a class="trigger" id="close_trigger" href="#"><span class="fas fa-lg fa-times"></span></a>);
	say q(<h2>Modify form parameters</h2>);
	say q(<p style="white-space:nowrap">Click to add or remove additional query terms:</p>)
	  . q(<ul style="list-style:none;margin-left:-2em">);
	my $list_fieldset_display = $self->{'prefs'}->{"${table}_list_fieldset"}
	  || $q->param('list') ? HIDE : SHOW;
	say qq(<li><a href="" class="button" id="show_list">$list_fieldset_display</a>);
	say q(Attribute values list</li>);
	say q(</ul>);
	my $save = SAVE;
	say qq(<a id="save_options" class="button" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=tableQuery&amp;table=$table&amp;save_options=1" style="display:none">$save</a> <span id="saving">)
	  . q(</span><br />);
	say q(</div>);
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
	my ( $self, $table, $attributes ) = @_;
	my @filters;
	foreach my $att (@$attributes) {
		( my $tooltip = $att->{'tooltip'} ) =~ tr/_/ /;
		my $sub = 'Select a value to filter your search to only those with the selected attribute.';
		$tooltip =~ s/ - / filter - $sub/x;
		if ( $att->{'dropdown_query'} ) {
			my $dropdown_filter = $self->_get_dropdown_filter( $table, $att );
			push @filters, $dropdown_filter if $dropdown_filter;
		} elsif ( $att->{'optlist'} ) {
			my @options = split /;/x, $att->{'optlist'};
			push @filters, $self->get_filter( $att->{'name'}, \@options );
		} elsif ( $att->{'type'} eq 'bool' ) {
			push @filters, $self->get_filter( $att->{'name'}, [qw(true false)], { tooltip => $tooltip } );
		}
	}
	my $filter_method = {
		loci                => sub { return $self->get_scheme_filter },
		allele_designations => sub { return $self->get_scheme_filter },
		schemes             => sub { return $self->get_scheme_filter },
		isolate_aliases     => sub { return $self->get_project_filter },
		sequences           => sub { return $self->_get_sequence_filters },
		locus_descriptions  => sub { return $self->_get_locus_description_filter },
		allele_sequences    => sub { return $self->_get_allele_sequences_filters }
	};
	if ( $filter_method->{$table} ) {
		my $table_filters = $filter_method->{$table}->();
		if ($table_filters) {
			push @filters, ref $table_filters ? @$table_filters : $table_filters;
		}
	}
	if (@filters) {
		if ( @filters > 2 ) {
			say q(<fieldset id="filters_fieldset" style="float:left;display:none" class="coolfieldset">)
			  . q(<legend>Filter query by</legend>);
		} else {
			say q(<fieldset style="float:left"><legend>Filter query by</legend>);
		}
		say q(<div><ul>);
		say qq(<li>$_</li>) foreach @filters;
		say q(</ul></div></fieldset>);
	}
	return;
}

sub _print_list_fieldset {
	my ( $self, $table, $attributes ) = @_;
	my $field_list = [];
	foreach my $att (@$attributes) {
		next if $att->{'hide_query'};
		next if $att->{'type'} eq 'bool';
		push @$field_list, $att->{'name'};
	}
	my $q       = $self->{'cgi'};
	my $display = $self->{'prefs'}->{"${table}_list_fieldset"}
	  || $q->param('list') ? 'inline' : 'none';
	say qq(<fieldset id="list_fieldset" style="float:left;display:$display"><legend>Attribute values list</legend>);
	say q(Field:);
	say $q->popup_menu( -name => 'attribute', -values => $field_list );
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

sub _save_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $guid   = $self->get_guid;
	my $table  = $q->param('table');
	return if !$self->{'datastore'}->is_table($table);
	return if !$guid;
	my $value = $q->param('list') ? 'on' : 'off';
	$self->{'prefstore'}->set_general( $guid, $self->{'system'}->{'db'}, "${table}_list_fieldset", $value );
	return;
}
1;
