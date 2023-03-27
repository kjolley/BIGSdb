#Written by Keith Jolley
#Copyright (c) 2010-2023, University of Oxford
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
package BIGSdb::AlleleQueryPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::QueryPage);
use List::MoreUtils qw(any none uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Constants qw(:interface SEQ_STATUS ALLELE_FLAGS OPERATORS);

sub initiate {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	$self->SUPER::initiate;
	$self->{'noCache'} = 1;
	if ( !$self->{'cgi'}->param('save_options') ) {
		my $guid = $self->get_guid;
		return if !$guid;
		foreach my $attribute (qw (filters list mutations)) {
			my $value =
			  $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, "aq_${attribute}_fieldset" );
			$self->{'prefs'}->{"aq_${attribute}_fieldset"} = ( $value // '' ) eq 'on' ? 1 : 0;
		}
		my $value = $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, 'aq_allele_fieldset' );
		$self->{'prefs'}->{'aq_allele_fieldset'} = ( $value // '' ) eq 'off' ? 0 : 1;
	}
	$self->{$_} = 1 foreach (qw (tooltips jQuery jQuery.coolfieldset jQuery.multiselect));
	$self->set_level1_breadcrumbs;
	return;
}

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/data_query/0020_search_sequence_attributes.html"
	  . '#locus-specific-sequence-attribute-search';
}

sub get_javascript {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $max_rows = MAX_ROWS;
	my $panel_js = $self->get_javascript_panel(qw(filters list allele mutations));
	my $buffer   = $self->SUPER::get_javascript;
	$buffer .= << "END";
\$(function () {
   \$("#locus").change(function(){
 	  var locus_name = \$("#locus").val();
 	  locus_name = locus_name.replace("cn_","");
  	  var url = '$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=alleleQuery&locus=' + locus_name;
 	  location.href=url;
    });

    $panel_js
 });


function loadContent(url) {
	var row = parseInt(url.match(/row=(\\d+)/)[1]);
	var fields = url.match(/fields=([allele|mutation]+)/)[1];
	if (fields == 'allele'){			
		add_rows(url,fields,'allele',row,'allele_field_heading','add_allele_fields');
	} else if (fields == 'mutation'){
		add_rows(url,fields,'mutation',row,'mutation_field_heading','add_mutation_fields');	
	}
}
END
	return $buffer;
}

sub _ajax_content {
	my ( $self, $locus ) = @_;
	my $row = $self->{'cgi'}->param('row');
	return if !BIGSdb::Utils::is_int($row) || $row > MAX_ROWS || $row < 2;
	my $q      = $self->{'cgi'};
	my $fields = $q->param('fields');
	return if !$fields;
	if ( $fields eq 'allele' ) {
		my ( $select_items, $labels ) = $self->_get_select_items($locus);
		$self->_print_allele_fields( $locus, $row, 0, $select_items, $labels );
	} elsif ( $fields eq 'mutation' ) {
		$self->_print_mutation_fields( $locus, $row, 0 );
	}
	return;
}

sub _save_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $guid   = $self->get_guid;
	return if !$guid;
	foreach my $attribute (qw (allele filters list mutations)) {
		my $value = $q->param($attribute) ? 'on' : 'off';
		$self->{'prefstore'}->set_general( $guid, $self->{'system'}->{'db'}, "aq_${attribute}_fieldset", $value );
	}
	return;
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $locus  = $q->param('locus') // '';
	$locus =~ s/%27/'/gx;    #Web-escaped locus
	$locus =~ s/^cn_//x;
	if    ( $q->param('no_header') )    { $self->_ajax_content($locus); return }
	elsif ( $q->param('save_options') ) { $self->_save_options;         return }
	my $cleaned_locus = $self->clean_locus($locus);

	if ( !$self->{'datastore'}->is_locus($locus) ) {
		$cleaned_locus = q();
	}
	$cleaned_locus = qq( - $cleaned_locus) if $cleaned_locus;
	say qq(<h1>Sequence attribute search$cleaned_locus</h1>);
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
	if ( defined $q->param('submit') || defined $q->param('query_file') || defined $q->param('t1') ) {
		if ( $q->param('locus') eq q() ) {
			$self->print_bad_status(
				{
						message => q(Please select locus or use the general )
					  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;)
					  . q(table=sequences">sequence attribute query</a> page.)
				}
			);
		} else {
			$self->_run_query;
		}
	}
	return;
}

sub _get_select_items {
	my ( $self, $locus ) = @_;
	my $attributes = $self->{'datastore'}->get_table_field_attributes('sequences');
	my ( @select_items, @order_by );
	foreach my $att (@$attributes) {
		next if $att->{'name'} eq 'locus';
		if ( $att->{'name'} eq 'sender' || $att->{'name'} eq 'curator' || $att->{'name'} eq 'user_id' ) {
			push @select_items,
			  (
				"$att->{'name'} (id)",
				"$att->{'name'} (surname)",
				"$att->{'name'} (first_name)",
				"$att->{'name'} (affiliation)"
			  );
		} else {
			push @select_items, $att->{'name'};
		}
		push @order_by, $att->{'name'};
		if ( $att->{'name'} eq 'sequence' ) {
			push @select_items, 'sequence_length';
			push @order_by,     'sequence_length';
		}
	}
	my %labels;
	foreach my $item (@select_items) {
		( $labels{$item} = $item ) =~ tr/_/ /;
	}
	if ($locus) {
		my $ext_atts =
		  $self->{'datastore'}
		  ->run_query( 'SELECT field FROM locus_extended_attributes WHERE locus=? ORDER BY field_order',
			$locus, { fetch => 'col_arrayref' } );
		foreach my $field (@$ext_atts) {
			my $item = "extatt_$field";
			push @select_items, $item;
			( $labels{$item} = $item ) =~ s/^extatt_//x;
			$labels{$item} =~ tr/_/ /;
		}
	}
	return ( \@select_items, \%labels, \@order_by );
}

sub _print_allele_fields {

	#split so single row can be added by AJAX call
	my ( $self, $locus, $row, $max_rows, $select_items, $labels ) = @_;
	my $q = $self->{'cgi'};
	say q(<span style="white-space:nowrap">);
	say $q->popup_menu( -name => "field$row", -values => $select_items, -labels => $labels, -class => 'fieldlist' );
	say $q->popup_menu( -name => "operator$row", -values => [OPERATORS] );
	say $q->textfield( -name => "value$row", -id => "value$row", -class => 'value_entry' );
	if ( $row == 1 ) {
		$locus //= '';
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		say qq(<a id="add_allele_fields" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=alleleQuery&amp;locus=$locus&amp;fields=allele&amp;row=$next_row&amp;no_header=1" data-rel="ajax" )
		  . q(class="add_button"><span class="fa fas fa-plus"></span></a>);
		say $self->get_tooltip( q(Search values - Empty field values can be searched using the term 'null'. )
			  . q(<h3>Number of fields</h3>Add more fields by clicking the '+' button.) );
	}
	say q(</span>);
	return;
}

sub _print_interface {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $locus  = $q->param('locus');
	if ($locus) {
		$locus =~ s/%27/'/gx;            #Web-escaped locus
		$q->param( locus => $locus );    #In case of escape
	}
	my ( $select_items, $labels, $order_by ) = $self->_get_select_items($locus);
	say q(<div class="box" id="queryform"><div class="scrollable">);
	my $set_id = $self->get_set_id;
	my ( $display_loci, $cleaned ) = $self->{'datastore'}->get_locus_list( { set_id => $set_id } );
	unshift @$display_loci, '';
	print $q->start_form;
	$cleaned->{''} = 'Please select ...';
	say q(<p><b>Locus: </b>);
	say $q->popup_menu( -name => 'locus', -id => 'locus', -values => $display_loci, -labels => $cleaned );
	say q( <span class="comment">Page will reload when changed</span></p>);
	say $q->hidden($_) foreach qw (db page);

	if ( $q->param('locus') ) {
		say qq(<ul><li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=locusInfo&amp;)
		  . qq(locus=$locus">Further information</a> is available for this locus.</li></ul>);
	}
	say q(<p>Please enter your search criteria below (or leave blank and submit to return all records).</p>);
	my $table_fields = $self->_highest_entered_fields('alleles') || 1;
	my $display      = $self->{'prefs'}->{'aq_allele_fieldset'}
	  || $self->_highest_entered_fields('alleles') ? 'inline' : 'none';
	say qq(<fieldset id="allele_fieldset" style="float:left;display:$display"><legend>Allele fields</legend>);
	my $table_field_heading = $table_fields == 1 ? 'none' : 'inline';
	say qq(<span id="allele_field_heading" style="display:$table_field_heading">)
	  . q(<label for="c0">Combine searches with: </label>);
	say $q->popup_menu( -name => 'c0', -id => 'c0', -values => [qw(AND OR)] );
	say qq(</span>\n<ul id="allele">);

	foreach my $i ( 1 .. $table_fields ) {
		say q(<li>);
		$self->_print_allele_fields( $locus, $i, $table_fields, $select_items, $labels );
		say q(</li>);
	}
	say q(</ul></fieldset>);
	$self->_print_mutation_fieldset;
	$self->_print_list_fieldset;
	$self->_print_filters_fieldset;
	say q(<fieldset style="float:left"><legend>Display</legend>);
	say q(<ul><li><span style="white-space:nowrap"><label for="order" class="display">Order by: </label>);
	say $q->popup_menu( -name => 'order', -id => 'order', -values => $order_by, -labels => $labels );
	say $q->popup_menu( -name => 'direction', -values => [qw(ascending descending)], -default => 'ascending' );
	say q(</span></li><li>);
	say $self->get_number_records_control;
	say q(</li></ul></fieldset>);
	$self->print_action_fieldset( { locus => $locus, submit_label => 'Search' } );
	$self->_print_modify_search_fieldset;
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

sub _print_mutation_fieldset {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $locus  = $q->param('locus');
	return if !defined $locus;
	return
	  if !$self->{'datastore'}->run_query(
		'SELECT EXISTS(SELECT * FROM peptide_mutations WHERE locus=?) OR '
		  . 'EXISTS(SELECT * FROM dna_mutations WHERE locus=?)',
		[ $locus, $locus ]
	  );
	my $mutation_fields = $self->_highest_entered_fields('mutations') || 1;
	my $display         = $self->{'prefs'}->{'aq_mutations_fieldset'}
	  || $self->_highest_entered_fields('mutations') ? 'inline' : 'none';
	say qq(<fieldset id="mutations_fieldset" style="float:left;display:$display"><legend>Sequence variation</legend>);
	my $mutation_field_heading = $mutation_fields == 1 ? 'none' : 'inline';
	say qq(<span id="mutation_field_heading" style="display:$mutation_field_heading">)
	  . q(<label for="mutation_andor">Combine searches with: </label>);
	say $q->popup_menu( -name => 'mutation_andor', -id => 'mutation_andor', -values => [qw(AND OR)] );
	say q(</span><ul id="mutation">);

	foreach my $i ( 1 .. $mutation_fields ) {
		say q(<li>);
		$self->_print_mutation_fields( $locus, $i, $mutation_fields );
		say q(</li>);
	}
	say q(</ul></fieldset>);
	return;
}

sub _print_mutation_fields {
	my ( $self, $locus, $row, $max_rows ) = @_;
	my $q = $self->{'cgi'};
	my @values;
	my $labels = {};
	my $peptide_mutations =
	  $self->{'datastore'}->run_query( 'SELECT * FROM peptide_mutations WHERE locus=? ORDER BY reported_position',
		$locus, { fetch => 'all_arrayref', slice => {} } );
	foreach my $mutation (@$peptide_mutations) {
		my @wt  = split /;/x, $mutation->{'wild_type_aa'};
		my @mut = split /;/x, $mutation->{'variant_aa'};
		foreach my $wt (@wt) {
			push @values, "pm_$mutation->{'id'}_${wt}_wt";
			$labels->{"pm_$mutation->{'id'}_${wt}_wt"} = "$wt$mutation->{'reported_position'} wild-type";
			if ( @mut > 1 ) {
				push @values, "pm_$mutation->{'id'}_${wt}_variant";
				$labels->{"pm_$mutation->{'id'}_${wt}_variant"} = "$wt$mutation->{'reported_position'} variant";
			}
			foreach my $mut (@mut) {
				push @values, "pm_$mutation->{'id'}_${wt}_$mut";
				$labels->{"pm_$mutation->{'id'}_${wt}_$mut"} = "$wt$mutation->{'reported_position'}$mut";
			}
		}
	}
	my $dna_mutations =
	  $self->{'datastore'}->run_query( 'SELECT * FROM dna_mutations WHERE locus=? ORDER BY reported_position',
		$locus, { fetch => 'all_arrayref', slice => {} } );
	foreach my $mutation (@$dna_mutations) {
		my @wt  = split /;/x, $mutation->{'wild_type_nuc'};
		my @mut = split /;/x, $mutation->{'variant_nuc'};
		foreach my $wt (@wt) {
			push @values, "dm_$mutation->{'id'}_${wt}_wt";
			$labels->{"dm_$mutation->{'id'}_${wt}_wt"} = "$wt$mutation->{'reported_position'} wild-type";
			if ( @mut > 1 ) {
				push @values, "dm_$mutation->{'id'}_${wt}_variant";
				$labels->{"dm_$mutation->{'id'}_${wt}_variant"} = "$wt$mutation->{'reported_position'} polymorphism";
			}
			foreach my $mut (@mut) {
				push @values, "dm_$mutation->{'id'}_${wt}_$mut";
				$labels->{"dm_$mutation->{'id'}_${wt}_$mut"} = "$wt$mutation->{'reported_position'}$mut";
			}
		}
	}
	say q(<span style="white-space:nowrap">);
	say $self->popup_menu(
		-name   => "mutation$row",
		-id     => "mutation$row",
		-values => [ q(), @values ],
		-labels => $labels,
		-class  => 'fieldlist'
	);
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		say qq(<a id="add_mutation_fields" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=alleleQuery&amp;fields=mutation&amp;locus=$locus&amp;row=$next_row&amp;no_header=1" data-rel="ajax" )
		  . q(class="add_button"><span class="fa fas fa-plus"></span></a>);
	}
	say q(</span>);
	return;
}

sub _print_list_fieldset {
	my ($self)  = @_;
	my $q       = $self->{'cgi'};
	my $display = $self->{'prefs'}->{'aq_list_fieldset'} || $q->param('list') ? 'inline' : 'none';
	say qq(<fieldset id="list_fieldset" style="float:left;display:$display"><legend>Allele id list</legend>);
	say $q->textarea( -name => 'list', -id => 'list', -rows => 6, -cols => 12 );
	say q(</fieldset>);
	return;
}

sub _print_filters_fieldset {
	my ($self)  = @_;
	my $q       = $self->{'cgi'};
	my $display = $self->{'prefs'}->{'aq_filters_fieldset'}
	  || $self->filters_selected ? 'inline' : 'none';
	say qq(<fieldset id="filters_fieldset" style="float:left;display:$display"><legend>Filters</legend>);
	say q(<ul><li>);
	say $self->get_filter( 'status', [SEQ_STATUS], { class => 'display' } );
	say q(</li><li>);
	if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
		my @flag_values = ( 'any flag', 'no flag', ALLELE_FLAGS );
		say $self->get_filter( 'allele_flag', \@flag_values, { class => 'display' } );
	}
	say q(</li></ul></fieldset>);
	return;
}

sub _print_modify_search_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<div id="modify_panel" class="panel">);
	say q(<a class="trigger" id="close_trigger" href="#"><span class="fas fa-lg fa-times"></span></a>);
	say q(<h2>Modify form parameters</h2>);
	say q(<p style="white-space:nowrap">Click to add or remove additional query terms:</p>)
	  . q(<ul style="list-style:none;margin-left:-2em">);
	my $allele_fieldset_display = $self->{'prefs'}->{'aq_allele_fieldset'}
	  || $self->_highest_entered_fields('alleles') ? HIDE : SHOW;
	say qq(<li><a href="" class="button" id="show_allele">$allele_fieldset_display</a>);
	say q(Allele fields</li>);
	my $locus = $q->param('locus');

	if ($locus) {
		my $mutations = $self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM peptide_mutations WHERE locus=?) '
			  . 'OR EXISTS(SELECT * FROM dna_mutations WHERE locus=?)',
			[ $locus, $locus ]
		);
		if ($mutations) {
			my $mutation_fieldset_display = $self->{'prefs'}->{'aq_mutations_fieldset'}
			  || $self->_highest_entered_fields('mutations') ? HIDE : SHOW;
			say qq(<li><a href="" class="button" id="show_mutations">$mutation_fieldset_display</a>);
			say q(Sequence variation</li>);
		}
	}
	my $list_fieldset_display = $self->{'prefs'}->{'aq_list_fieldset'}
	  || $q->param('list') ? HIDE : SHOW;
	say qq(<li><a href="" class="button" id="show_list">$list_fieldset_display</a>);
	say q(Allele id list box</li>);
	my $filters_fieldset_display = $self->{'prefs'}->{'aq_filters_fieldset'}
	  || $self->filters_selected ? HIDE : SHOW;
	say qq(<li><a href="" class="button" id="show_filters">$filters_fieldset_display</a>);
	say q(Filters</li>);
	say q(</ul>);
	my $save = SAVE;
	say qq(<a id="save_options" class="button" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=alleleQuery&amp;save_options=1" style="display:none">$save</a> <span id="saving"></span><br />);
	say q(</div>);
	return;
}

sub _run_query {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $qry, $list_file );
	my $errors     = [];
	my $attributes = $self->{'datastore'}->get_table_field_attributes('sequences');
	my $locus      = $q->param('locus');
	$locus =~ s/^cn_//x;
	$locus =~ s/%27/'/gx;    #Web-escaped locus

	if ( !$self->{'datastore'}->is_locus($locus) ) {
		$logger->error("Invalid locus $locus");
		$self->print_bad_status( { message => q(Invalid locus selected.) } );
		return;
	}
	if ( !defined $q->param('query_file') ) {
		( $qry, $list_file, $errors ) = $self->_generate_query($locus);
		$q->param( list_file => $list_file );
	} else {
		$qry = $self->get_query_from_temp_file( scalar $q->param('query_file') );
		if ( $q->param('list_file') ) {
			$self->{'datastore'}->create_temp_list_table( 'text', scalar $q->param('list_file') );
		}
	}
	my @hidden_attributes;
	push @hidden_attributes, 'c0', 'mutation_andor';
	foreach my $i ( 1 .. MAX_ROWS ) {
		push @hidden_attributes, "field$i", "value$i", "operator$i", "mutation$i";
	}
	foreach (@$attributes) {
		push @hidden_attributes, $_->{'name'} . '_list';
	}
	push @hidden_attributes, qw(locus list list_file allele_flag_list);
	if (@$errors) {
		$self->print_bad_status( { message => q(Problem with search criteria:), detail => qq(@$errors) } );
		return;
	}
	$qry =~ s/AND\ \(\)//x;
	my $args = { table => 'sequences', query => $qry, hidden_attributes => \@hidden_attributes };
	$args->{'passed_qry_file'} = $q->param('query_file') if defined $q->param('query_file');
	$self->paged_display($args);
	return;
}

sub _generate_query {
	my ( $self, $locus ) = @_;
	my $locus_info  = $self->{'datastore'}->get_locus_info($locus);
	my $q           = $self->{'cgi'};
	my $andor       = $q->param('c0');
	my $first_value = 1;
	my ( $qry, $qry2 );
	my $errors = [];
	foreach my $i ( 1 .. MAX_ROWS ) {
		next if !defined $q->param("value$i") || $q->param("value$i") eq q();
		my $field    = $q->param("field$i");
		my $operator = $q->param("operator$i") // '=';
		my $text     = $q->param("value$i");
		$self->process_value( \$text );
		if ( $field =~ /^extatt_(.*)$/x ) {    #search by extended attribute
			$field = $1;
			my $this_field = $self->{'datastore'}->run_query(
				'SELECT * FROM locus_extended_attributes WHERE (locus,field)=(?,?)',
				[ $locus, $field ],
				{ fetch => 'row_hashref', cache => 'AlleleQueryPage::run_query::extended_attributes' }
			);
			next
			  if $self->check_format(
				{ field => $field, text => $text, type => $this_field->{'value_format'}, operator => $operator },
				$errors );
			my $modifier = ( $i > 1 && !$first_value ) ? " $andor " : '';
			$first_value = 0;
			( my $cleaned = $locus ) =~ s/'/\\'/gx;
			my $std_clause = "$modifier (allele_id IN (SELECT allele_id FROM sequence_extended_attributes "
			  . "WHERE locus=E'$cleaned' AND field='$field' ";
			my %methods = (
				'NOT'         => '_ext_not',
				'contains'    => '_ext_contains',
				'starts with' => '_ext_starts_with',
				'ends with'   => '_ext_ends_with',
				'NOT contain' => '_ext_not_contain',
				'='           => '_ext_equals'
			);
			my $args = {
				qry_ref        => \$qry,
				std_clause_ref => \$std_clause,
				this_field     => $this_field,
				text           => $text,
				modifier       => $modifier,
				field          => $field,
				locus          => $locus,
				operator       => $operator,
				errors         => $errors
			};

			if ( $methods{$operator} ) {
				my $method = $methods{$operator};
				$self->$method($args);
			} else {
				$self->_ext_other($args);
			}
		} else {
			my $thisfield = $self->_get_field_attributes($field);
			$thisfield->{'type'} = 'int' if $field eq 'sequence_length';
			$thisfield->{'type'} //= 'text';    # sender/curator surname, firstname, affiliation
			$thisfield->{'type'} = $locus_info->{'allele_id_format'} // 'text'
			  if ( $thisfield->{'name'} // '' ) eq 'allele_id';
			if ( none { $field =~ /\($_\)$/x } qw (surname first_name affiliation) ) {
				next
				  if $self->check_format(
					{ field => $field, text => $text, type => $thisfield->{'type'}, operator => $operator }, $errors );
			}
			my $modifier = ( $i > 1 && !$first_value ) ? " $andor " : '';
			$first_value = 0;
			if ( $field =~ /(.*)\ \(id\)$/x
				&& !BIGSdb::Utils::is_int($text) )
			{
				push @$errors, "$field is an integer field.";
				next;
			}
			$qry .= $modifier;
			if ( any { $field =~ /.*\ \($_\)/x } qw (id surname first_name affiliation) ) {
				$qry .= $self->search_users( $field, $operator, $text, 'sequences' );
			} else {
				my %methods = (
					'NOT'         => '_not',
					'contains'    => '_contains',
					'starts with' => '_starts_with',
					'ends with'   => '_ends_with',
					'NOT contain' => '_not_contain',
					'='           => '_equals'
				);
				my $args = {
					qry_ref    => \$qry,
					this_field => $thisfield,
					field      => $field,
					text       => $text,
					locus      => $locus,
					operator   => $operator,
					errors     => $errors
				};
				if ( $methods{$operator} ) {
					my $method = $methods{$operator};
					$self->$method($args);
				} else {
					$self->_other($args);
				}
			}
		}
	}
	$locus =~ s/'/\\'/gx;
	$qry //= q();
	$qry =~ s/sequence_length/length(sequence)/g;
	$qry2 = "SELECT * FROM sequences WHERE locus=E'$locus'";
	$qry2 .= " AND ($qry)" if $qry;
	my $list_file = $self->_modify_by_list( \$qry2, $locus );
	$self->_modify_by_filter( \$qry2, $locus );
	$self->_modify_query_by_mutations( \$qry2, $locus );
	$qry2 .= $self->_process_flags;
	$qry2 .= q( AND sequences.allele_id NOT IN ('0', 'N', 'P'));
	$qry2 .= q( ORDER BY );
	$q->param( order => 'allele_id' ) if !defined $q->param('order');

	if ( $q->param('order') eq 'allele_id' && $locus_info->{'allele_id_format'} eq 'integer' ) {
		$qry2 .= q(CAST (allele_id AS integer));
	} else {
		$qry2 .= $q->param('order');
	}
	my $dir = ( $q->param('direction') // '' ) eq 'descending' ? 'desc' : 'asc';
	$qry2 .= " $dir;";
	$qry2 =~ s/sequence_length/length(sequence)/g;
	return ( $qry2, $list_file, $errors );
}

sub _modify_query_by_mutations {
	my ( $self, $qry_ref, $locus ) = @_;
	my $q      = $self->{'cgi'};
	my $and_or = $q->param('mutation_andor') // 'AND';
	my @mutations;
	foreach my $i ( 1 .. MAX_ROWS ) {
		my $value = $q->param("mutation$i");
		next if !defined $value || $value eq q();
		if ( $value =~ /^pm_(\d+)_([A-Z])_([A-Z]|wt|variant)/x ) {
			my ( $mutation_id, $wt, $mut ) = ( $1, $2, $3 );
			if ( $mut eq 'wt' ) {
				push @mutations,
				  'allele_id IN (SELECT allele_id FROM sequences_peptide_mutations WHERE '
				  . "(mutation_id,amino_acid,is_wild_type)=($mutation_id,'$wt','true'))";
			} elsif ( $mut eq 'variant' ) {
				push @mutations,
				  'allele_id IN (SELECT allele_id FROM sequences_peptide_mutations WHERE '
				  . "(mutation_id,is_mutation)=($mutation_id,'true'))";
			} else {
				push @mutations,
				  'allele_id IN (SELECT allele_id FROM sequences_peptide_mutations WHERE '
				  . "(mutation_id,amino_acid,is_mutation)=($mutation_id,'$mut','true'))";
			}
		} elsif ( $value =~ /^dm_(\d+)_([A-Z])_([A-Z]|wt|variant)/x ) {
			my ( $mutation_id, $wt, $mut ) = ( $1, $2, $3 );
			if ( $mut eq 'wt' ) {
				push @mutations,
				  'allele_id IN (SELECT allele_id FROM sequences_dna_mutations WHERE '
				  . "(mutation_id,nucleotide,is_wild_type)=($mutation_id,'$wt','true'))";
			} elsif ( $mut eq 'variant' ) {
				push @mutations,
				  'allele_id IN (SELECT allele_id FROM sequences_dna_mutations WHERE '
				  . "(mutation_id,is_mutation)=($mutation_id,'true'))";
			} else {
				push @mutations,
				  'allele_id IN (SELECT allele_id FROM sequences_dna_mutations WHERE '
				  . "(mutation_id,nucleotide,is_mutation)=($mutation_id,'$mut','true'))";
			}
		} else {
			$logger->error("Invalid mutation passed: $value");
			next;
		}
	}
	local $" = qq[) $and_or (];
	$$qry_ref .= " AND ((@mutations))" if @mutations;
	return;
}

sub _modify_by_list {
	my ( $self, $qry_ref, $locus ) = @_;
	my $q = $self->{'cgi'};
	return if !$q->param('list');
	my @list = split /\n/x, $q->param('list');
	@list = uniq @list;
	BIGSdb::Utils::remove_trailing_spaces_from_list( \@list );
	return if !@list || ( @list == 1 && $list[0] eq q() );
	my $temp_table =
	  $self->{'datastore'}->create_temp_list_table_from_array( 'text', \@list, { table => 'temp_list' } );
	my $list_file = BIGSdb::Utils::get_random() . '.list';
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$list_file";
	open( my $fh, '>:encoding(utf8)', $full_path ) || $logger->error("Can't open $full_path for writing");
	say $fh $_ foreach @list;
	close $fh;

	if ( $$qry_ref !~ /WHERE\ \(\)\s*$/x ) {
		$$qry_ref .= ' AND ';
	} else {
		$$qry_ref = "SELECT * FROM sequences WHERE locus=E'$locus' AND ";
	}
	$$qry_ref .= "(sequences.allele_id IN (SELECT value FROM $temp_table))";
	return $list_file;
}

sub _modify_by_filter {
	my ( $self, $qry_ref, $locus ) = @_;
	my $q          = $self->{'cgi'};
	my $attributes = $self->{'datastore'}->get_table_field_attributes('sequences');
	foreach (@$attributes) {
		my $param = $_->{'name'} . '_list';
		if ( defined $q->param($param) && $q->param($param) ne '' ) {
			my $value = $q->param($param);
			$self->process_value( \$value );
			if ( $$qry_ref !~ /WHERE\ \(\)\s*$/x ) {
				$$qry_ref .= ' AND ';
			} else {
				$$qry_ref = "SELECT * FROM sequences WHERE locus=E'$locus' AND ";
			}
			$$qry_ref .= lc($value) eq 'null' ? "$_->{'name'} is null" : "$_->{'name'} = E'$value'";
		}
	}
	return;
}

sub _get_field_attributes {
	my ( $self, $field ) = @_;
	my $all_attributes = $self->{'datastore'}->get_table_field_attributes('sequences');
	foreach my $attributes (@$all_attributes) {
		return $attributes if $attributes->{'name'} eq $field;
	}
	return;
}

sub _ext_not {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $qry_ref, $std_clause_ref, $this_field, $text ) = @{$args}{qw(qry_ref std_clause_ref this_field text )};
	$$qry_ref .= $$std_clause_ref;
	if ( lc($text) eq 'null' ) {
		$$qry_ref .= '))';
	} else {
		$$qry_ref .=
		  $this_field->{'value_format'} eq 'integer'
		  ? "AND NOT CAST(value AS text) = E'$text'))"
		  : "AND NOT upper(value) = upper(E'$text')))";
	}
	return;
}

sub _ext_contains {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $qry_ref, $std_clause_ref, $this_field, $text ) = @{$args}{qw(qry_ref std_clause_ref this_field text )};
	$$qry_ref .= $$std_clause_ref;
	$$qry_ref .=
	  $this_field->{'value_format'} eq 'integer'
	  ? "AND CAST(value AS text) LIKE E'\%$text\%'))"
	  : "AND upper(value) LIKE upper(E'\%$text\%')))";
	return;
}

sub _ext_starts_with {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $qry_ref, $std_clause_ref, $this_field, $text ) = @{$args}{qw(qry_ref std_clause_ref this_field text )};
	$$qry_ref .= $$std_clause_ref;
	$$qry_ref .=
	  $this_field->{'value_format'} eq 'integer'
	  ? "AND CAST(value AS text) LIKE E'$text\%'))"
	  : "AND upper(value) LIKE upper(E'$text\%')))";
	return;
}

sub _ext_ends_with {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $qry_ref, $std_clause_ref, $this_field, $text ) = @{$args}{qw(qry_ref std_clause_ref this_field text )};
	$$qry_ref .= $$std_clause_ref;
	$$qry_ref .=
	  $this_field->{'value_format'} eq 'integer'
	  ? "AND CAST(value AS text) LIKE E'\%$text'))"
	  : "AND upper(value) LIKE upper(E'\%$text')))";
	return;
}

sub _ext_not_contain {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $qry_ref, $std_clause_ref, $this_field, $text ) = @{$args}{qw(qry_ref std_clause_ref this_field text )};
	$$qry_ref .= $$std_clause_ref;
	$$qry_ref .=
	  $this_field->{'value_format'} eq 'integer'
	  ? "AND NOT CAST(value AS text) LIKE E'\%$text\%'))"
	  : "AND NOT upper(value) LIKE upper(E'\%$text\%')))";
	return;
}

sub _ext_equals {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $qry_ref, $std_clause_ref, $this_field, $text, $modifier, $field, $locus ) =
	  @{$args}{qw(qry_ref std_clause_ref this_field text modifier field locus)};
	if ( lc($text) eq 'null' ) {
		( my $cleaned = $locus ) =~ s/'/\\'/gx;
		$$qry_ref .= "$modifier (allele_id NOT IN (select allele_id FROM sequence_extended_attributes "
		  . "WHERE locus=E'$cleaned' AND field='$field'))";
	} else {
		$$qry_ref .= $$std_clause_ref;
		$$qry_ref .=
		  $this_field->{'value_format'} eq 'text'
		  ? "AND upper(value)=upper(E'$text')))"
		  : "AND value=E'$text'))";
	}
	return;
}

sub _ext_other {
	my ( $self, $args ) = @_;
	my ( $qry_ref, $std_clause_ref, $this_field, $text, $operator, $errors ) =
	  @{$args}{qw(qry_ref std_clause_ref this_field text operator errors)};
	if ( lc($text) eq 'null' ) {
		push @$errors, BIGSdb::Utils::escape_html("$operator is not a valid operator for comparing null values.");
		next;
	}
	$$qry_ref .= $$std_clause_ref;
	$$qry_ref .=
	  $this_field->{'value_format'} eq 'integer'
	  ? "AND CAST(value AS int) $operator E'$text'))"
	  : "AND value $operator E'$text'))";
	return;
}

sub _not {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $qry_ref, $this_field, $field, $text ) = @{$args}{qw(qry_ref this_field field text )};
	if ( lc($text) eq 'null' ) {
		$$qry_ref .= "$field IS NOT null";
	} else {
		$$qry_ref .=
		  $this_field->{'type'} eq 'text'
		  ? "NOT UPPER($field) = UPPER(E'$text')"
		  : "NOT $field = E'$text'";
		$$qry_ref .= " OR $field IS NULL";
	}
	return;
}

sub _contains {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $qry_ref, $this_field, $field, $text ) = @{$args}{qw(qry_ref this_field field text )};
	$$qry_ref .=
	  $this_field->{'type'} eq 'text'
	  ? "$field ILIKE E'\%$text\%'"
	  : "CAST($field AS text) ILIKE E'\%$text\%'";
	return;
}

sub _starts_with {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $qry_ref, $this_field, $field, $text ) = @{$args}{qw(qry_ref this_field field text )};
	$$qry_ref .=
	  $this_field->{'type'} eq 'text'
	  ? "$field ILIKE E'$text\%'"
	  : "CAST($field AS text) ILIKE E'$text\%'";
	return;
}

sub _ends_with {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $qry_ref, $this_field, $field, $text ) = @{$args}{qw(qry_ref this_field field text )};
	$$qry_ref .=
	  $this_field->{'type'} eq 'text'
	  ? "$field ILIKE E'\%$text'"
	  : "CAST($field AS text) ILIKE E'\%$text'";
	return;
}

sub _not_contain {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $qry_ref, $this_field, $field, $text ) = @{$args}{qw(qry_ref this_field field text )};
	$$qry_ref .=
	  $this_field->{'type'} eq 'text'
	  ? "NOT $field ILIKE E'\%$text\%'"
	  : "NOT CAST($field AS text) LIKE E'\%$text\%'";
	$$qry_ref .= " OR $field IS NULL";
	return;
}

sub _equals {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $qry_ref, $this_field, $field, $text ) = @{$args}{qw(qry_ref this_field field text )};
	if ( lc($text) eq 'null' ) {
		$$qry_ref .= "$field is null";
	} else {
		$$qry_ref .=
		  $this_field->{'type'} eq 'text'
		  ? "UPPER($field) = UPPER(E'$text')"
		  : "$field = E'$text'";
	}
	return;
}

sub _other {
	my ( $self, $args ) = @_;
	my ( $qry_ref, $this_field, $field, $text, $locus, $operator, $errors ) =
	  @{$args}{qw(qry_ref this_field field text locus operator errors)};
	if ( lc($text) eq 'null' ) {
		push @$errors, BIGSdb::Utils::escape_html("$operator is not a valid operator for comparing null values.");
		return;
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( $field eq 'allele_id' && $locus_info->{'allele_id_format'} eq 'integer' ) {
		$$qry_ref .= "CAST($field AS integer) $operator E'$text'";
	} else {
		$$qry_ref .= "$field $operator E'$text'";
	}
	return;
}

sub _process_flags {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $buffer = '';
	if ( ( $q->param('allele_flag_list') // '' ) ne '' && ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
		if ( $q->param('allele_flag_list') eq 'no flag' ) {
			$buffer .= ' AND NOT EXISTS (SELECT 1 FROM allele_flags WHERE sequences.locus=allele_flags.locus AND '
			  . 'sequences.allele_id=allele_flags.allele_id)';
		} else {
			$buffer .= ' AND EXISTS (SELECT 1 FROM allele_flags WHERE sequences.locus=allele_flags.locus AND '
			  . 'sequences.allele_id=allele_flags.allele_id';
			if ( any { $q->param('allele_flag_list') eq $_ } ALLELE_FLAGS ) {
				$buffer .= q( AND flag = ') . $q->param('allele_flag_list') . q(');
			}
			$buffer .= ')';
		}
	}
	return $buffer;
}

sub _highest_entered_fields {
	my ( $self, $type ) = @_;
	my $q          = $self->{'cgi'};
	my %param_name = ( alleles => 'value', mutations => 'mutation' );
	my $highest;
	for my $row ( 1 .. MAX_ROWS ) {
		$highest = $row
		  if defined $q->param("$param_name{$type}$row") && $q->param("$param_name{$type}$row") ne '';
	}
	return $highest;
}

sub get_title {
	my ($self) = @_;
	return 'Sequence attribute search (locus-specific)';
}
1;
