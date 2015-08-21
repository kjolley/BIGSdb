#Written by Keith Jolley
#Copyright (c) 2010-2015, University of Oxford
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
use constant MAX_ROWS => 10;
use BIGSdb::Page qw(ALLELE_FLAGS SEQ_STATUS);
use BIGSdb::QueryPage qw(OPERATORS);

sub initiate {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	$self->SUPER::initiate;
	$self->{'noCache'} = 1;
	if ( !$self->{'cgi'}->param('save_options') ) {
		my $guid = $self->get_guid;
		return if !$guid;
		foreach my $attribute (qw (filter list)) {
			my $value =
			  $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, "aq_${attribute}_fieldset" );
			$self->{'prefs'}->{"aq_${attribute}_fieldset"} = ( $value // '' ) eq 'on' ? 1 : 0;
		}
		my $value = $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, 'aq_allele_fieldset' );
		$self->{'prefs'}->{'aq_allele_fieldset'} = ( $value // '' ) eq 'off' ? 0 : 1;
	}
	return;
}

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/data_query.html#locus-specific-sequence-attribute-search";
}

sub get_javascript {
	my ($self)                 = @_;
	my $q                      = $self->{'cgi'};
	my $max_rows               = MAX_ROWS;
	my $filter_fieldset_display = $self->{'prefs'}->{'aq_filter_fieldset'}
	  || $self->filters_selected ? 'inline' : 'none';
	my $list_fieldset_display = $self->{'prefs'}->{'aq_list_fieldset'} || $q->param('list') ? 'inline' : 'none';
	my $buffer = << "END";
\$(function () {
   \$('#filter_fieldset').css({display:"$filter_fieldset_display"});
   \$('#list_fieldset').css({display:"$list_fieldset_display"});
   \$("#locus").change(function(){
 	  var locus_name = \$("#locus").val();
 	  locus_name = locus_name.replace("cn_","");
  	  var url = '$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=alleleQuery&locus=' + locus_name;
 	  location.href=url;
    });
    \$('a[data-rel=ajax]').click(function(){
  	  \$(this).attr('href', function(){
  		  if (this.href.match(/javascript.loadContent/)){
  			  return;
  		  };
   		  return(this.href.replace(/(.*)/, "javascript:loadContent\('\$1\'\)"));
   	  });
    });
    \$("#show_allele").click(function() {
  		if(\$(this).text() == 'Hide'){\$('[id^="value"]').val('')}
 		\$("#allele_fieldset").toggle(100);
		\$(this).text(\$(this).text() == 'Show' ? 'Hide' : 'Show');
		\$("a#save_options").fadeIn();
		return false;
	});
    \$("#show_filters").click(function() {
		if(\$(this).text() == 'Hide'){
			\$('[id\$="_list"]').val('');
		}
 		\$("#filter_fieldset").toggle(100);
		\$(this).text(\$(this).text() == 'Show' ? 'Hide' : 'Show');
		\$("a#save_options").fadeIn();
		return false;
    });
    \$("#show_list").click(function() {
		if(\$(this).text() == 'Hide'){
			\$("#list").val('');
		}
 		\$("#list_fieldset").toggle(100);
		\$(this).text(\$(this).text() == 'Show' ? 'Hide' : 'Show');
		\$("a#save_options").fadeIn();
		return false;
    });
  	\$(".trigger").click(function(){		
		\$(".panel").toggle("slide",{direction:"right"},"fast");
		\$("#panel_trigger").show().animate({backgroundColor: "#448"},100).animate({backgroundColor: "#99d"},100);
		
		return false;
	});
	\$("#panel_trigger").show().animate({backgroundColor: "#99d"},500);
		\$("a#save_options").click(function(event){		
		event.preventDefault();
		var filter = \$("#show_filters").text() == 'Show' ? 0 : 1;
		var list = \$("#show_list").text() == 'Show' ? 0 : 1;
		var allele = \$("#show_allele").text() == 'Show' ? 0 : 1;
	  	\$(this).attr('href', function(){  	
	  		\$("a#save_options").text('Saving ...');
	  		var new_url = this.href + "&filter=" + filter + "&list=" + list + "&allele=" + allele;
		  		\$.ajax({
	  			url : new_url,
	  			success: function () {	  				
	  				\$("a#save_options").hide();
	  				\$("a#save_options").text('Save options');
	  			}
	  		});
	   	});
	});
});

function loadContent(url) {
	var row = parseInt(url.match(/row=(\\d+)/)[1]);
	var new_row = row+1;
	\$("ul#table_fields").append('<li id="fields' + row + '" />');
	\$("li#fields"+row).html('<img src=\"/javascript/themes/default/throbber.gif\" /> Loading ...').load(url);
	url = url.replace(/row=\\d+/,'row='+new_row);
	\$("#add_table_fields").attr('href',url);
	\$("span#table_field_heading").show();
	if (new_row > $max_rows){
		\$("#add_table_fields").hide();
	}
}
END
	return $buffer;
}

sub _ajax_content {
	my ( $self, $locus ) = @_;
	my $row = $self->{'cgi'}->param('row');
	return if !BIGSdb::Utils::is_int($row) || $row > MAX_ROWS || $row < 2;
	my ( $select_items, $labels ) = $self->_get_select_items($locus);
	$self->_print_table_fields( $locus, $row, 0, $select_items, $labels );
	return;
}

sub _save_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $guid   = $self->get_guid;
	return if !$guid;
	foreach my $attribute (qw (allele filter list)) {
		my $value = $q->param($attribute) ? 'on' : 'off';
		$self->{'prefstore'}->set_general( $guid, $self->{'system'}->{'db'}, "aq_${attribute}_fieldset", $value );
	}
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $locus = $q->param('locus') // '';
	$locus =~ s/^cn_//x;
	if    ( $q->param('no_header') )    { $self->_ajax_content; return }
	elsif ( $q->param('save_options') ) { $self->_save_options; return }
	my $cleaned_locus = $self->clean_locus($locus);
	my $desc          = $self->get_db_description;
	say "<h1>Query $cleaned_locus sequences - $desc database</h1>";
	my $qry;

	if (   !defined $q->param('currentpage')
		|| ( defined $q->param('pagejump') && $q->param('pagejump') eq '1' )
		|| $q->param('First') )
	{
		if ( !$q->param('no_js') ) {
			my $locus_clause = $locus ? "&amp;locus=$locus" : q();
			say q(<noscript><div class="box statusbad"><p>The dynamic customisation of this interface requires )
			  . q(that you enable Javascript in your browser. Alternatively, you can use a )
			  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=alleleQuery$locus_clause&amp;no_js=1">non-Javascript version</a> that has 4 combinations )
			  . q(of fields.</p></div></noscript>);
		}
		$self->_print_interface;
	}
	if ( defined $q->param('submit') || defined $q->param('query_file') || defined $q->param('t1') ) {
		if ( $q->param('locus') eq q() ) {
			say q(<div class="box" id="statusbad"><p>Please select locus or use the general )
			  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;)
			  . q(table=sequences">sequence attribute query</a> page.</p></div>);
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

sub _print_table_fields {

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
		say qq(<a id="add_table_fields" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=alleleQuery&amp;locus=$locus&amp;row=$next_row&amp;no_header=1" data-rel="ajax" )
		  . q(class="button">+</a>);
		say q( <a class="tooltip" title="Search values - Empty field values can be searched using the term 'null'. )
		  . q(<h3>Number of fields</h3>Add more fields by clicking the '+' button."><span class="fa fa-info-circle">)
		  . q(</span></a>);
	}
	say q(</span>);
	return;
}

sub _print_interface {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $locus  = $q->param('locus');
	my ( $select_items, $labels, $order_by ) = $self->_get_select_items($locus);
	say q(<div class="box" id="queryform"><div class="scrollable">);
	my $set_id = $self->get_set_id;
	my ( $display_loci, $cleaned ) = $self->{'datastore'}->get_locus_list( { set_id => $set_id } );
	unshift @$display_loci, '';
	print $q->startform;
	$cleaned->{''} = 'Please select ...';
	say q(<p><b>Locus: </b>);
	say $q->popup_menu( -name => 'locus', -id => 'locus', -values => $display_loci, -labels => $cleaned );
	say q( <span class="comment">Page will reload when changed</span></p>);
	say $q->hidden($_) foreach qw (db page no_js);

	if ( $q->param('locus') ) {
		say qq(<ul><li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=locusInfo&amp;)
		  . qq(locus=$locus">Further information</a> is available for this locus.</li></ul>);
	}
	say q(<p>Please enter your search criteria below (or leave blank and submit to return all records).</p>);
	my $table_fields = $q->param('no_js') ? 4 : ( $self->_highest_entered_fields || 1 );
	my $display = $self->{'prefs'}->{'aq_allele_fieldset'} || $self->_highest_entered_fields ? 'inline' : 'none';
	say qq(<fieldset id="allele_fieldset" style="float:left;display:$display"><legend>Allele fields</legend>);
	my $table_field_heading = $table_fields == 1 ? 'none' : 'inline';
	say qq(<span id="table_field_heading" style="display:$table_field_heading">)
	  . q(<label for="c0">Combine searches with: </label>);
	say $q->popup_menu( -name => 'c0', -id => 'c0', -values => [qw(AND OR)] );
	say qq(</span>\n<ul id="table_fields">);

	foreach my $i ( 1 .. $table_fields ) {
		say q(<li>);
		$self->_print_table_fields( $locus, $i, $table_fields, $select_items, $labels );
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
	$self->_print_list_fieldset;
	$self->_print_filter_fieldset;
	$self->print_action_fieldset( { locus => $locus } );
	$self->_print_modify_search_fieldset;
	say $q->endform;
	say q(</div></div>);
	return;
}

sub _print_list_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $display = $q->param('no_js') ? 'block' : 'none';
	say qq(<fieldset id="list_fieldset" style="float:left;display:$display"><legend>Allele id list</legend>);
	say $q->textarea( -name => 'list', -id => 'list', -rows => 6, -cols => 12 );
	say q(</fieldset>);
	return;
}

sub _print_filter_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $display = $q->param('no_js') ? 'block' : 'none';
	say qq(<fieldset id="filter_fieldset" style="float:left;display:$display"><legend>Filters</legend>);
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
	say q(<div class="panel">);
	say q(<a class="trigger" id="close_trigger" href="#"><span class="fa fa-lg fa-close"></span></a>);
	say q(<h2>Modify form parameters</h2>);
	say q(<p style="white-space:nowrap">Click to add or remove additional query terms:</p><ul>);
	my $allele_fieldset_display = $self->{'prefs'}->{'aq_allele_fieldset'}
	  || $self->_highest_entered_fields ? 'Hide' : 'Show';
	say qq(<li><a href="" class="button" id="show_allele">$allele_fieldset_display</a>);
	say q(Allele fields</li>);
	my $list_fieldset_display = $self->{'prefs'}->{'aq_list_fieldset'}
	  || $q->param('list') ? 'Hide' : 'Show';
	say qq(<li><a href="" class="button" id="show_list">$list_fieldset_display</a>);
	say q(Allele id list box</li>);
	my $filter_fieldset_display = $self->{'prefs'}->{'aq_filter_fieldset'}
	  || $self->filters_selected ? 'Hide' : 'Show';
	say qq(<li><a href="" class="button" id="show_filters">$filter_fieldset_display</a>);
	say q(Filters</li>);
	say q(</ul>);
	say qq(<a id="save_options" class="button" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . q(page=alleleQuery&amp;save_options=1" style="display:none">Save options</a><br />);
	say q(</div>);
	say q(<a class="trigger" id="panel_trigger" href="" style="display:none">Modify<br />form<br />options</a>);
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
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		$logger->error("Invalid locus $locus");
		say q(<div class="box" id="statusbad"><p>Invalid locus selected.</p></div>);
		return;
	}
	if ( !defined $q->param('query_file') ) {
		( $qry, $list_file, $errors ) = $self->_generate_query($locus);
		$q->param( list_file => $list_file );
	} else {
		$qry = $self->get_query_from_temp_file( $q->param('query_file') );
		if ( $q->param('list_file') ) {
			$self->{'datastore'}->create_temp_list_table( 'text', $q->param('list_file') );
		}
	}
	my @hidden_attributes;
	push @hidden_attributes, 'c0';
	foreach my $i ( 1 .. MAX_ROWS ) {
		push @hidden_attributes, "field$i", "value$i", "operator$i";
	}
	foreach (@$attributes) {
		push @hidden_attributes, $_->{'name'} . '_list';
	}
	push @hidden_attributes, qw(locus no_js list list_file allele_flag_list);
	if (@$errors) {
		say q(<div class="box" id="statusbad"><p>Problem with search criteria:</p>);
		say qq(<p>@$errors</p></div>);
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
	$qry2 = "SELECT * FROM sequences WHERE locus=E'$locus' AND ($qry)";
	my $list_file = $self->_modify_by_list( \$qry2, $locus );
	$self->_modify_by_filter( \$qry2, $locus );
	$qry2 .= $self->_process_flags;
	$qry2 .= q( AND sequences.allele_id NOT IN ('0', 'N'));
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

sub _modify_by_list {
	my ( $self, $qry_ref, $locus ) = @_;
	my $q = $self->{'cgi'};
	return if !$q->param('list');
	my @list = split /\n/x, $q->param('list');
	@list = uniq @list;
	BIGSdb::Utils::remove_trailing_spaces_from_list( \@list );
	return if !@list;
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
			$$qry_ref .= $value eq 'null' ? "$_->{'name'} is null" : "$_->{'name'} = E'$value'";
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
	if ( $text eq 'null' ) {
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

sub _ext_ends_with {      ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
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

sub _ext_equals {         ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $qry_ref, $std_clause_ref, $this_field, $text, $modifier, $field, $locus ) =
	  @{$args}{qw(qry_ref std_clause_ref this_field text modifier field locus)};
	if ( $text eq 'null' ) {
		$$qry_ref .= "$modifier (allele_id NOT IN (select allele_id FROM sequence_extended_attributes "
		  . "WHERE locus=E'$locus' AND field='$field'))";
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
	if ( $text eq 'null' ) {
		push @$errors, "$operator is not a valid operator for comparing null values.";
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
	if ( $text eq 'null' ) {
		$$qry_ref .= "$field IS NOT null";
	} else {
		$$qry_ref .=
		  $this_field->{'type'} eq 'text'
		  ? "NOT UPPER($field) = UPPER(E'$text')"
		  : "NOT $field = E'$text'";
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

sub _ends_with {      ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
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
	return;
}

sub _equals {         ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $qry_ref, $this_field, $field, $text ) = @{$args}{qw(qry_ref this_field field text )};
	if ( $text eq 'null' ) {
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
	if ( $text eq 'null' ) {
		push @$errors, "$operator is not a valid operator for comparing null values.";
		next;
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
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $highest;
	for my $row ( 1 .. MAX_ROWS ) {
		$highest = $row if defined $q->param("value$row") && $q->param("value$row") ne '';
	}
	return $highest;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Allele query - $desc";
}
1;
