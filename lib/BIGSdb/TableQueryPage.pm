#Written by Keith Jolley
#Copyright (c) 2010-2018, University of Oxford
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
	if ( $self->{'cgi'}->param('no_header') ) {
		$self->{'type'} = 'no_header';
		return;
	}
	$self->{$_} = 1 foreach (qw (tooltips jQuery jQuery.coolfieldset jQuery.multiselect));
	return;
}

sub get_help_url {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $table  = $q->param('table');
	return if !defined $table;
	if ( $self->{'curate'} ) {
		if ( $table eq 'sequences' ) {
			return
			  "$self->{'config'}->{'doclink'}/curator_guide.html#updating-and-deleting-allele-sequence-definitions";
		}
	} else {
		if ( $table eq 'sequences' ) {
			return "$self->{'config'}->{'doclink'}/data_query.html#searching-for-specific-allele-definitions";
		}
		if ( $table eq 'loci' || $table eq 'schemes' || $table eq 'scheme_fields' ) {
			return "$self->{'config'}->{'doclink'}/data_query.html#modifying-locus-and-scheme-display-options";
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
	my $table = $q->param('table') || '';
	if ( $q->param('no_header') ) {
		$self->_ajax_content($table);
		return;
	}
	if ( $table eq 'isolates'
		|| ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) )
	{
		say q(<h1>Table query</h1>);
		say q(<div class="box" id="statusbad"><p>You cannot use this function to query the isolate table.</p></div>);
		return;
	}
	if (   !$self->{'datastore'}->is_table($table)
		&& !( $table eq 'samples' && @{ $self->{'xmlHandler'}->get_sample_field_list } ) )
	{
		say q(<h1>Table query</h1>);
		say qq(<div class="box" id="statusbad"><p>Table '$table' is not defined.</p></div>);
		return;
	}
	my $cleaned = $table;
	$cleaned =~ tr/_/ /;
	my $desc = $self->get_db_description;
	say qq(<h1>Query $cleaned for $desc database</h1>);
	my $qry;
	if (   !defined $q->param('currentpage')
		|| ( defined $q->param('pagejump') && $q->param('pagejump') eq '1' )
		|| $q->param('First') )
	{
		say q(<noscript><div class="box statusbad"><p>This interface requires )
		  . q(that you enable Javascript in your browser.</p></div></noscript>);
		$self->_print_interface;
	}
	if ( $q->param('submit') || defined $q->param('query_file') || defined $q->param('t1') ) {
		$self->_run_query;
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description || 'BIGSdb';
	my $record = $self->get_record_name( $self->{'cgi'}->param('table') ) || 'record';
	return "Query $record information - $desc";
}

sub get_javascript {
	my ($self) = @_;
	my $filter_collapse = $self->filters_selected ? 'false' : 'true';
	my $buffer = $self->SUPER::get_javascript;
	$buffer .= << "END";
\$(function () {
  	\$('#filters_fieldset').coolfieldset({speed:"fast", collapsed:$filter_collapse});
  	\$('#filters_fieldset').show();
  	
  	\$('#field_tooltip').tooltip({ content: "<h3>Search values</h3><p>Empty field "
  		+ "values can be searched using the term 'null'. </p><h3>Number of fields</h3><p>Add more fields by clicking the '+' button."
  		+ "</p><h3>Query modifier</h3><p>Select 'AND' for the isolate query to match ALL search terms, 'OR' to match ANY of these terms."
  		+ "</p>" });
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
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my ( @select_items, @order_by );
	if ( $table eq 'experiment_sequences' ) {
		push @select_items, 'isolate_id';
		push @select_items, $self->{'system'}->{'labelfield'};
	}
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
		push @order_by, $att->{'name'};
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
		  . q(data-rel="ajax" class="button">+</a>);
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
	my $cleaned = $table;
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
		my $any_text_ids_used =
		  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM loci WHERE allele_id_format=?)', 'text' );
		if ($any_text_ids_used) {
			say q(<p>Also note that some loci in this database have allele ids defined as text strings.  )
			  . q(Queries using the '&lt;' or '&gt;' modifiers will work alphabetically rather than numerically )
			  . q(unless you filter your search to a locus that uses integer allele ids using the drop-down list.</p>);
		}
	}
	say q(<p>Please enter your search criteria below (or leave blank and submit to return all records).);
	if ( !$self->{'curate'} && $table ne 'samples' ) {
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
	my %table_with_scheme_filter = map { $_ => 1 } qw (loci allele_designations schemes);
	if ( $table_with_scheme_filter{$table} ) {
		push @filters, $self->get_scheme_filter;
	} elsif ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' && $table eq 'sequences' ) {
		my @flag_values = ( 'any flag', 'no flag', ALLELE_FLAGS );
		push @filters, $self->get_filter( 'allele_flag', \@flag_values );
	} elsif ( $table eq 'sequence_bin' ) {
		my %labels;
		my @experiments;
		my $qry = 'SELECT id,description FROM experiments ORDER BY description';
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute };
		$logger->error($@) if $@;
		while ( my @data = $sql->fetchrow_array ) {
			push @experiments, $data[0];
			$labels{ $data[0] } = $data[1];
		}
		if (@experiments) {
			push @filters, $self->get_filter( 'experiment', \@experiments, { labels => \%labels } );
		}
	} elsif ( $table eq 'locus_descriptions' ) {
		my %labels;
		my $common_names =
		  $self->{'datastore'}->run_query( 'SELECT DISTINCT common_name FROM loci ORDER BY common_name',
			undef, { fetch => 'col_arrayref' } );
		push @filters,
		  $self->get_filter(
			'common_name',
			$common_names,
			{
				tooltip => 'common names filter - Select a name to filter your search '
				  . 'to only those loci with the selected common name.'
			}
		  );
	} elsif ( $table eq 'allele_sequences' ) {
		push @filters, $self->get_scheme_filter;
		push @filters,
		  $self->get_filter(
			'sequence_flag',
			[ 'any flag', 'no flag', SEQ_FLAGS ],
			{
				tooltip => 'sequence flag filter - Select the appropriate value to '
				  . 'filter tags to only those flagged accordingly.'
			}
		  );
		push @filters,
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
	}
	if (@filters) {
		if ( @filters > 2 ) {
			say q(<fieldset id="filters_fieldset" style="float:left;display:none" class="coolfieldset">)
			  . q(<legend>Filter query by</legend>);
		} else {
			say q(<fieldset style="float:left"><legend>Filter query by</legend>);
		}
		say q(<div><ul>);
		say qq(<li><span style="white-space:nowrap">$_</span></li>) foreach @filters;
		say q(</ul></div></fieldset>);
	}
	$self->print_action_fieldset( { page => 'tableQuery', table => $table } );
	say $q->end_form;
	say q(</div></div>);
	return;
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
		return $self->get_scheme_filter;
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
	my $values =
	  $self->{'datastore'}
	  ->run_query( "SELECT $field FROM users WHERE $field IS NOT NULL AND id>0", undef, { fetch => 'col_arrayref' } );
	my $user_dbs =
	  $self->{'datastore'}
	  ->run_query( 'SELECT DISTINCT user_db FROM users WHERE user_db IS NOT NULL', undef, { fetch => 'col_arrayref' } );
	foreach my $user_db_id (@$user_dbs) {
		my $user_db = $self->{'datastore'}->get_user_db($user_db_id);
		my $remote_values =
		  $self->{'datastore'}
		  ->run_query( "SELECT $field FROM users", undef, { db => $user_db, fetch => 'col_arrayref' } );
		next if !@$remote_values;
		push @$values, @$remote_values;
	}
	@$values = sort { uc($a) cmp uc($b) } uniq @$values;
	return $values;
}

#Prevent SQL injection attempts.
sub _sanitize_order_field {
	my ( $self, $table ) = @_;
	my ( undef, undef, $order_by, undef ) = $self->_get_select_items($table);
	my $q = $self->{'cgi'};
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

	if ( !defined $q->param('query_file') ) {
		( $qry, $errors ) = $self->_generate_query($table);
		if ( $table eq 'sequences' && $qry ) {
			$qry =~ s/sequences.sequence_length/length(sequences.sequence)/gx;
		}
		$self->_modify_isolates_for_view( $table, \$qry );
		$self->_modify_seqbin_for_view( $table, \$qry );
		$self->_modify_loci_for_sets( $table, \$qry );
		$self->_modify_schemes_for_sets( $table, \$qry );
		$self->_filter_query_by_scheme( $table, \$qry );
		$self->_filter_query_by_experiment( $table, \$qry );
		$self->_filter_query_by_common_name( $table, \$qry );
		$self->_filter_query_by_sequence_filters( $table, \$qry );
		$self->_filter_query_by_allele_definition_filters( $table, \$qry );
		$qry //= '1=1';    #So that we always have a WHERE clause even with no arguments selected.
		$qry2 = "SELECT * FROM $table WHERE ($qry)";
		$qry2 = $self->_process_dropdown_filters( $qry2, $table, $attributes );

		if ( $table eq 'sequences' ) {

			#Alleles can be set to 0 or N for arbitrary profile definitions
			$qry2 .= " AND $table.allele_id NOT IN ('0', 'N')";
		}
		$qry2 .= " ORDER BY $table.";
		my $default_order;
		if    ( $table eq 'sequences' )       { $default_order = 'locus' }
		elsif ( $table eq 'history' )         { $default_order = 'timestamp' }
		elsif ( $table eq 'profile_history' ) { $default_order = 'timestamp' }
		else                                  { $default_order = 'id' }
		$qry2 .= $q->param('order') || $default_order;
		$qry2 =~ s/sequences.sequence_length/length(sequences.sequence)/gx if $table eq 'sequences';
		my $dir = ( $q->param('direction') // '' ) eq 'descending' ? 'desc' : 'asc';
		my @primary_keys = $self->{'datastore'}->get_primary_keys($table);
		local $" = ",$table.";
		$qry2 .= " $dir,$table.@primary_keys;";
	} else {
		$qry2 = $self->get_query_from_temp_file( $q->param('query_file') );
	}
	my @hidden_attributes;
	push @hidden_attributes, 'c0';
	foreach my $i ( 1 .. MAX_ROWS ) {
		push @hidden_attributes, "s$i", "t$i", "y$i";
	}
	push @hidden_attributes, $_->{'name'} . '_list' foreach (@$attributes);
	push @hidden_attributes, qw (sequence_flag_list duplicates_list common_name_list scheme_id_list);
	if (@$errors) {
		local $" = q(<br />);
		say q(<div class="box" id="statusbad"><p>Problem with search criteria:</p>);
		say qq(<p>@$errors</p></div>);
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
	return if !BIGSdb::Utils::is_int( $q->param('scheme_id_list') );
	my %allowed_tables =
	  map { $_ => 1 } qw (loci scheme_fields schemes scheme_members client_dbase_schemes allele_designations);
	return if !$allowed_tables{$table};
	my $sub_qry;

	#Don't do this for allele_sequences as this has its own method
	my $scheme_id = $q->param('scheme_id_list');
	my ( $identifier, $field );
	my %set_id_and_field = (
		loci                => sub { ( $identifier, $field ) = ( 'id',    'locus' ) },
		allele_designations => sub { ( $identifier, $field ) = ( 'locus', 'locus' ) },
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
		$sub_qry = "$identifier IN (SELECT $field FROM scheme_members WHERE scheme_id = $scheme_id)";
	}
	if ($$qry_ref) {
		$$qry_ref .= " AND ($sub_qry)";
	} else {
		$$qry_ref = "($sub_qry)";
	}
	return;
}

sub _filter_query_by_experiment {
	my ( $self, $table, $qry_ref ) = @_;
	my $q = $self->{'cgi'};
	return if ( $q->param('experiment_list') // q() ) eq q();
	return if $table ne 'sequence_bin';
	my $experiment = $q->param('experiment_list');
	if ( BIGSdb::Utils::is_int($experiment) ) {
		my $sub_qry = 'sequence_bin.id IN (SELECT id FROM sequence_bin JOIN experiment_sequences ON sequence_bin.id = '
		  . "experiment_sequences.seqbin_id WHERE experiment_id = $experiment)";
		if ($$qry_ref) {
			$$qry_ref .= " AND ($sub_qry)";
		} else {
			$$qry_ref = "($sub_qry)";
		}
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
			my $not = $match == 1 ? 'NOT' : '';

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
			if ( $q->param('scheme_id_list') eq '0' || !BIGSdb::Utils::is_int( $q->param('scheme_id_list') ) ) {
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
	return if ( $q->param('allele_flag_list') // '' ) eq '';
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
	my $q = $self->{'cgi'};
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
	my @sender_fields  = ( 'sender (id)', 'sender (surname)', 'sender (first_name)', 'sender (affiliation)', );
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
		sequences => [ qw(sequence_length), @sender_fields ],
		sequence_bin => [ @$extended, @sender_fields, $self->{'system'}->{'labelfield'} ],
		allele_designations  => [ @sender_fields,                    $self->{'system'}->{'labelfield'} ],
		allele_sequences     => [ $self->{'system'}->{'labelfield'} ],
		project_members      => [ $self->{'system'}->{'labelfield'} ],
		history              => [ $self->{'system'}->{'labelfield'} ],
		isolate_aliases      => [ $self->{'system'}->{'labelfield'} ],
		refs                 => [ $self->{'system'}->{'labelfield'} ],
		experiment_sequences => [ 'isolate_id',                      $self->{'system'}->{'labelfield'} ],
		user_group_members   => [@user_fields],
		profile_history      => ['timestamp (date)'],
		history              => [ $self->{'system'}->{'labelfield'}, 'timestamp (date)' ]
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
	}
	return;
}

sub _generate_query {
	my ( $self, $table ) = @_;
	my $q = $self->{'cgi'};
	my $qry;
	my $errors      = [];
	my $andor       = $q->param('c0');
	my $first_value = 1;
	my $set_id      = $self->get_set_id;
	foreach my $i ( 1 .. MAX_ROWS ) {
		next if !defined $q->param("t$i") || $q->param("t$i") eq q();
		my $field = $q->param("s$i");
		$self->_check_invalid_fieldname( $table, $field, $errors );
		my $operator = $q->param("y$i") // '=';
		my $text = $q->param("t$i");
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
		next if $self->_modify_query_search_by_isolate_id($args);
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
				  ? "(NOT CAST($table.$field AS text) = '$text'"
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

sub _modify_query_search_by_isolate_id {
	my ( $self, $args ) = @_;
	my ( $table, $field, $text, $modifier, $operator, $qry_ref ) =
	  @{$args}{qw(table field text modifier operator qry_ref)};
	my %table_without_isolate_id = map { $_ => 1 } qw (experiment_sequences);
	if ( $table_without_isolate_id{$table} && $field eq 'isolate_id' ) {
		$$qry_ref .= $modifier;
		$$qry_ref .= "$table.seqbin_id IN (SELECT sequence_bin.id FROM sequence_bin LEFT JOIN "
		  . "$self->{'system'}->{'view'} ON isolate_id = $self->{'system'}->{'view'}.id WHERE ";
		my %terms = (
			'NOT'         => "NOT $self->{'system'}->{'view'}.id = $text",
			'contains'    => "CAST($self->{'system'}->{'view'}.id AS text) LIKE '\%$text\%'",
			'starts with' => "CAST($self->{'system'}->{'view'}.id AS text) LIKE '$text\%'",
			'ends with'   => "CAST($self->{'system'}->{'view'}.id AS text) LIKE '\%$text'",
			'NOT contain' => "NOT CAST($self->{'system'}->{'view'}.id AS text) LIKE '\%$text\%'"
		);
		if ( $terms{$operator} ) {
			$$qry_ref .= $terms{$operator};
		} else {
			$$qry_ref .= "$self->{'system'}->{'view'}.id $operator $text";
		}
		$$qry_ref .= ')';
		return 1;
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
	  qw (allele_sequences allele_designations experiment_sequences sequence_bin
	  project_members isolate_aliases samples history refs);
	return if !$table_linked_to_isolate{$table};
	return if $field ne $self->{'system'}->{'labelfield'};
	$$qry_ref .= $modifier;
	my $att = $self->{'xmlHandler'}->get_field_attributes( $self->{'system'}->{'labelfield'} );

	if ( $table eq 'experiment_sequences' ) {
		$$qry_ref .=
		    "$table.seqbin_id IN (SELECT sequence_bin.id FROM sequence_bin LEFT JOIN $self->{'system'}->{'view'} ON "
		  . "isolate_id = $self->{'system'}->{'view'}.id WHERE ";
	} else {
		$$qry_ref .= "$table.isolate_id IN (SELECT id FROM $self->{'system'}->{'view'} WHERE ";
	}
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
	return $qry if !@user_names;
	local $" = q(',E');
	$and_or = 'AND NOT' if $operator =~ /NOT/;
	$qry = qq(($qry $and_or user_name IN (E'@user_names')));
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
	return if none { $table eq $_ } qw(allele_sequences experiment_sequences);
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

sub print_additional_headerbar_functions {
	my ( $self, $filename ) = @_;
	return if $self->{'curate'};
	my $q = $self->{'cgi'};
	my %allowed = map { $_ => 1 } qw(schemes loci scheme_fields);
	return if !$allowed{ $q->param('table') };
	my $record = $self->get_record_name( $q->param('table') );
	say q(<fieldset><legend>Customize</legend>);
	say $q->start_form;
	say $q->submit( -name => 'customize', -label => ucfirst("$record options"), -class => BUTTON_CLASS );
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
1;
