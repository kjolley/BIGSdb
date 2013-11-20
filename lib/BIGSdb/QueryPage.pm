#Written by Keith Jolley
#Copyright (c) 2010-2013, University of Oxford
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
package BIGSdb::QueryPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::ResultsTablePage);
use List::MoreUtils qw(any none all);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant MAX_ROWS  => 20;
use constant MAX_INT   => 2147483647;
use constant OPERATORS => ( '=', 'contains', 'starts with', 'ends with', '>', '<', 'NOT', 'NOT contain' );
use BIGSdb::Page qw(SEQ_FLAGS LOCUS_PATTERN);
our @EXPORT_OK = qw(OPERATORS);

sub initiate {
	my ($self) = @_;
	if ( $self->{'cgi'}->param('no_header') ) {
		$self->{'type'} = 'no_header';
		return;
	}
	$self->{$_} = 1 foreach qw (field_help tooltips jQuery jQuery.coolfieldset jQuery.multiselect);
	return;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { general => 1, main_display => 1, isolate_display => 0, analysis => 0, query_field => 1 };
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $max_rows = MAX_ROWS;
	my $locus_collapse  = $self->_highest_entered_fields('loci') ? 'false' : 'true';
	my $tag_collapse    = $self->_highest_entered_fields('tags') ? 'false' : 'true';
	my $filter_collapse = $self->_filters_selected               ? 'false' : 'true';
	my $buffer          = $self->SUPER::get_javascript;
	$buffer .= << "END";
\$(function () {
	\$('a[data-rel=ajax]').click(function(){
  		\$(this).attr('href', function(){
    		return(this.href.replace(/(.*)/, "javascript:loadContent\('\$1\'\)"));
    	});
  	});
  	\$('#locus_fieldset').coolfieldset({speed:"fast", collapsed:$locus_collapse});
   	\$('#tag_fieldset').coolfieldset({speed:"fast", collapsed:$tag_collapse});
  	\$('#filter_fieldset').coolfieldset({speed:"fast", collapsed:$filter_collapse});
  	\$('#locus_fieldset').show();
  	\$('#tag_fieldset').show();
  	\$('#filter_fieldset').show();
  	\$('#prov_tooltip,#loci_tooltip,#scheme_field_tooltip,#field_tooltip').tooltip({ content: "<h3>Search values</h3><p>Empty field "
  		+ "values can be searched using the term 'null'. </p><h3>Number of fields</h3><p>Add more fields by clicking the '+' button."
  		+ "</p><h3>Query modifier</h3><p>Select 'AND' for the isolate query to match ALL search terms, 'OR' to match ANY of these terms."
  		+ "</p>" });
  	\$('#tag_tooltip').tooltip({ content: "<h3>Number of fields</h3><p>Add more fields by clicking the '+' button.</p>" });	
  	if (! Modernizr.touch){
  		\$('.multiselect').multiselect({noneSelectedText:'&nbsp;'});
  	}
 });

function loadContent(url) {
	var row = parseInt(url.match(/row=(\\d+)/)[1]);
	var new_row = row+1;
	var fields = url.match(/fields=([provenance|loci|scheme|table_fields|tags]+)/)[1];
	if (fields == 'provenance'){	
		\$("ul#provenance").append('<li id="fields' + row + '" />');
		\$("li#fields"+row).html('<img src=\"/javascript/themes/default/throbber.gif\" /> Loading ...').load(url);
		url = url.replace(/row=\\d+/,'row='+new_row);
		\$("#add_fields").attr('href',url);
		\$("span#prov_field_heading").show();
		if (new_row > $max_rows){
			\$("#add_fields").hide();
		}
	} else if (fields == 'loci'){
		\$("ul#loci").append('<li id="locus' + row + '" />');
		\$("li#locus"+row).html('<img src=\"/javascript/themes/default/throbber.gif\" /> Loading ...').load(url);
		url = url.replace(/row=\\d+/,'row='+new_row);
		\$("#add_loci").attr('href',url);	
		\$("span#loci_field_heading").show();
		if (new_row > $max_rows){
			\$("#add_loci").hide();
		}	
	} else if (fields == 'scheme'){
		\$("ul#scheme_fields").append('<li id="scheme_field' + row + '" />');
		\$("li#scheme_field"+row).html('<img src=\"/javascript/themes/default/throbber.gif\" /> Loading ...').load(url);
		url = url.replace(/row=\\d+/,'row='+new_row);
		\$("#add_scheme_fields").attr('href',url);	
		\$("span#scheme_field_heading").show();
		if (new_row > $max_rows){
			\$("#add_scheme_fields").hide();
		}
	} else if (fields == 'table_fields'){
		\$("ul#table_fields").append('<li id="table_field' + row + '" />');
		\$("li#table_field"+row).html('<img src=\"/javascript/themes/default/throbber.gif\" /> Loading ...').load(url);
		url = url.replace(/row=\\d+/,'row='+new_row);
		\$("#add_table_fields").attr('href',url);	
		\$("span#table_field_heading").show();
		if (new_row > $max_rows){
			\$("#add_table_fields").hide();
		}
	} else if (fields == 'tags'){
		\$("ul#tags").append('<li id="tag' + row + '" />');
		\$("li#tag"+row).html('<img src=\"/javascript/themes/default/throbber.gif\" /> Loading ...').load(url);
		url = url.replace(/row=\\d+/,'row='+new_row);
		\$("#add_tags").attr('href',url);	
		\$("span#locus_tags_heading").show();
		if (new_row > $max_rows){
			\$("#add_tags").hide();
		}				
	}
}
END
	return $buffer;
}

sub _ajax_content {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $q      = $self->{'cgi'};
	my $row    = $q->param('row');
	return if !BIGSdb::Utils::is_int($row) || $row > MAX_ROWS || $row < 2;
	if ( $system->{'dbtype'} eq 'isolates' ) {
		if ( $q->param('fields') eq 'provenance' ) {
			my ( $select_items, $labels ) = $self->_get_isolate_select_items;
			$self->_print_provenance_fields( $row, 0, $select_items, $labels );
		} elsif ( $q->param('fields') eq 'loci' ) {
			my ( $locus_list, $locus_labels ) =
			  $self->get_field_selection_list( { 'loci' => 1, 'scheme_fields' => 1, 'sort_labels' => 1 } );
			$self->_print_loci_fields( $row, 0, $locus_list, $locus_labels );
		} elsif ( $q->param('fields') eq 'tags' ) {
			my ( $locus_list, $locus_labels ) =
			  $self->get_field_selection_list( { 'loci' => 1, 'scheme_fields' => 0, 'sort_labels' => 1 } );
			$self->_print_locus_tag_fields( $row, 0, $locus_list, $locus_labels );
		}
	} elsif ( $system->{'dbtype'} eq 'sequences' ) {
		if ( $q->param('fields') eq 'scheme' ) {
			my $scheme_id = $q->param('scheme_id');
			my ( $primary_key, $select_items, $orderitems, $cleaned ) = $self->_get_profile_select_items($scheme_id);
			$self->_print_scheme_fields( $row, 0, $scheme_id, $select_items, $cleaned );
		}
	}
	return;
}

sub print_content {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $q      = $self->{'cgi'};
	my $scheme_info;
	if ( $q->param('no_header') ) {
		$self->_ajax_content;
		return;
	}
	my $desc = $self->get_db_description;
	if ( $system->{'dbtype'} eq 'sequences' ) {
		if ( $self->{'curate'} ) {
			say "<h1>Query/update profiles - $desc</h1>";
		} else {
			say "<h1>Search profiles - $desc</h1>";
		}
	} else {
		if ( $self->{'curate'} ) {
			say "<h1>Isolate query/update</h1>";
		} else {
			say "<h1>Search $desc database</h1>";
		}
	}
	my $qry;
	if ( !defined $q->param('currentpage')
		|| $q->param('First') )
	{
		if ( !$q->param('no_js') ) {
			my $scheme_id = BIGSdb::Utils::is_int( $q->param('scheme_id') ) ? $q->param('scheme_id') : undef;
			my $scheme_clause = ( $system->{'dbtype'} eq 'sequences' && defined $scheme_id ) ? "&amp;scheme_id=$scheme_id" : '';
			say "<noscript><div class=\"box statusbad\"><p>The dynamic customisation of this interface requires that you enable "
			  . "Javascript in your browser. Alternatively, you can use a <a href=\"$self->{'system'}->{'script_name'}?db="
			  . "$self->{'instance'}&amp;page=query$scheme_clause&amp;no_js=1\">non-Javascript version</a> that has 4 combinations "
			  . "of fields.</p></div></noscript>";
		}
		if ( $system->{'dbtype'} eq 'isolates' ) {
			$self->_print_isolate_query_interface;
		} else {
			$self->_print_profile_query_interface;
		}
	}
	if ( $q->param('submit') || defined $q->param('query') ) {
		if ( $system->{'dbtype'} eq 'isolates' ) {
			$self->_run_isolate_query;
		} else {
			$self->_run_profile_query;
		}
	}
	return;
}
####START ISOLATE INTERFACE#####################################################
sub _print_provenance_fields {

	#split so single row can be added by AJAX call
	my ( $self, $row, $max_rows, $select_items, $labels ) = @_;
	my $q = $self->{'cgi'};
	print "<span style=\"white-space:nowrap\">\n";
	print $q->popup_menu( -name => "s$row", -values => $select_items, -labels => $labels, -class => 'fieldlist' );
	print $q->popup_menu( -name => "y$row", -values => [OPERATORS] );
	print $q->textfield( -name => "t$row", -class => 'value_entry' );
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		if ( !$q->param('no_js') ) {
			my $page = $self->{'curate'} ? 'isolateQuery' : 'query';
			print "<a id=\"add_fields\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;"
			  . "fields=provenance&amp;row=$next_row&amp;no_header=1\" data-rel=\"ajax\" class=\"button\">&nbsp;+&nbsp;</a>\n";
			print " <a class=\"tooltip\" id=\"prov_tooltip\" title=\"\">&nbsp;<i>i</i>&nbsp;</a>";
		}
	}
	print "</span>\n";
	return;
}

sub _print_loci_fields {
	my ( $self, $row, $max_rows, $locus_list, $locus_labels ) = @_;
	unshift @$locus_list, '';
	$locus_labels->{''} = ' ';    #Required for HTML5 validation.
	my $q = $self->{'cgi'};
	print "<span style=\"white-space:nowrap\">\n";
	print $self->popup_menu( -name => "ls$row", -values => $locus_list, -labels => $locus_labels, -class => 'fieldlist' );
	print $q->popup_menu( -name => "ly$row", -values => [OPERATORS] );
	print $q->textfield( -name => "lt$row", -class => 'value_entry' );

	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		if ( !$q->param('no_js') ) {
			my $page = $self->{'curate'} ? 'isolateQuery' : 'query';
			say "<a id=\"add_loci\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;"
			  . "fields=loci&amp;row=$next_row&amp;no_header=1\" data-rel=\"ajax\" class=\"button\">&nbsp;+&nbsp;</a>"
			  . " <a class=\"tooltip\" id=\"loci_tooltip\" title=\"\">&nbsp;<i>i</i>&nbsp;</a>";
		}
	}
	print "</span>\n";
	return;
}

sub _print_locus_tag_fields {
	my ( $self, $row, $max_rows, $locus_list, $locus_labels ) = @_;
	unshift @$locus_list, 'any locus';
	unshift @$locus_list, '';
	my $q = $self->{'cgi'};
	print "<span style=\"white-space:nowrap\">\n";
	print $self->popup_menu( -name => "ts$row", -values => $locus_list, -labels => $locus_labels, -class => 'fieldlist' );
	print ' is ';
	my @values = qw(untagged tagged complete incomplete);
	push @values, "flagged: $_" foreach ( 'any', 'none', SEQ_FLAGS );
	unshift @values, '';
	my %labels = ( '' => ' ' );    #Required for HTML5 validation.
	print $q->popup_menu( -name => "tt$row", -values => \@values, -labels => \%labels );

	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		if ( !$q->param('no_js') ) {
			my $page = $self->{'curate'} ? 'isolateQuery' : 'query';
			say "<a id=\"add_tags\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;"
			  . "fields=tags&amp;row=$next_row&amp;no_header=1\" data-rel=\"ajax\" class=\"button\">&nbsp;+&nbsp;</a>"
			  . " <a class=\"tooltip\" id=\"tag_tooltip\" title=\"\">&nbsp;<i>i</i>&nbsp;</a>";
		}
	}
	print "</span>\n";
	return;
}

sub _get_isolate_select_items {
	my ($self) = @_;
	my ( $field_list, $labels ) =
	  $self->get_field_selection_list( { 'isolate_fields' => 1, 'sender_attributes' => 1, 'extended_attributes' => 1 } );
	my $grouped = $self->{'xmlHandler'}->get_grouped_fields;
	my @grouped_fields;
	foreach (@$grouped) {
		push @grouped_fields, "f_$_";
		( $labels->{"f_$_"} = $_ ) =~ tr/_/ /;
	}
	my @select_items = ( @grouped_fields, @$field_list );
	return \@select_items, $labels;
}

sub _print_isolate_query_interface {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $prefs  = $self->{'prefs'};
	my $q      = $self->{'cgi'};
	say "<div class=\"box\" id=\"queryform\"><div class=\"scrollable\">";
	say $q->startform;
	$q->param( 'table', $self->{'system'}->{'view'} );
	say $q->hidden($_) foreach qw (db page table no_js);
	say "<div style=\"white-space:nowrap\">";
	$self->_print_isolate_fields_fieldset;
	$self->_print_isolate_display_fieldset;
	say "<div style=\"clear:both\"></div>";
	$self->_print_isolate_locus_fieldset;
	$self->_print_isolate_tag_fieldset;
	$self->_print_isolate_filter_fieldset;
	my $page = $self->{'curate'} ? 'isolateQuery' : 'query';
	$self->print_action_fieldset( { page => $page } );
	say "</div>";
	say $q->end_form;
	say "</div>\n</div>";
	return;
}

sub _print_isolate_fields_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<fieldset style=\"float:left\">\n<legend>Isolate provenance/phenotype fields</legend>\n";
	my $prov_fields = $q->param('no_js') ? 4 : ( $self->_highest_entered_fields('provenance') || 1 );
	my $display_field_heading = $prov_fields == 1 ? 'none' : 'inline';
	print "<span id=\"prov_field_heading\" style=\"display:$display_field_heading\"><label for=\"c0\">Combine with: </label>\n";
	print $q->popup_menu( -name => 'c0', -id => 'c0', -values => [qw (AND OR)] );
	print "</span>\n<ul id=\"provenance\">\n";
	my ( $select_items, $labels ) = $self->_get_isolate_select_items;

	for ( 1 .. $prov_fields ) {
		print "<li>\n";
		$self->_print_provenance_fields( $_, $prov_fields, $select_items, $labels );
		print "</li>\n";
	}
	print "</ul>\n</fieldset>\n";
	return;
}

sub _filters_selected {
	my ($self) = @_;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my %params = $self->{'cgi'}->Vars;
		return 1 if any { $_ =~ /_list$/ && $params{$_} ne '' } keys %params;
	}
	return;
}

sub _print_isolate_filter_fieldset {
	my ($self) = @_;
	my $prefs  = $self->{'prefs'};
	my $q      = $self->{'cgi'};
	my @filters;
	my $extended      = $self->get_extended_attributes;
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
	foreach my $field (@$field_list) {
		my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
		my $dropdownlist;
		my %dropdownlabels;
		if ( $prefs->{'dropdownfields'}->{$field} ) {
			if (   $field eq 'sender'
				|| $field eq 'curator'
				|| ( $thisfield->{'userfield'} && $thisfield->{'userfield'} eq 'yes' ) )
			{
				push @filters, $self->get_user_filter($field);
			} else {
				my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
				if ( $thisfield->{'optlist'} ) {
					$dropdownlist = $self->{'xmlHandler'}->get_field_option_list($field);
					$dropdownlabels{$_} = $_ foreach (@$dropdownlist);
					if (   $thisfield->{'required'}
						&& $thisfield->{'required'} eq 'no' )
					{
						push @$dropdownlist, '<blank>';
						$dropdownlabels{'<blank>'} = '<blank>';
					}
				} elsif ( defined $metaset ) {
					my $list =
					  $self->{'datastore'}->run_list_query( "SELECT DISTINCT($metafield) FROM meta_$metaset WHERE isolate_id "
						  . "IN (SELECT id FROM $self->{'system'}->{'view'})" );
					push @$dropdownlist, @$list;
				} else {
					my $list =
					  $self->{'datastore'}->run_list_query("SELECT DISTINCT($field) FROM $self->{'system'}->{'view'} ORDER BY $field");
					push @$dropdownlist, @$list;
				}
				my $a_or_an = substr( $field, 0, 1 ) =~ /[aeiouAEIOU]/ ? 'an' : 'a';
				my $display_field = $metafield // $field;
				push @filters,
				  $self->get_filter(
					$field,
					$dropdownlist,
					{
						text => $metafield // undef,
						'labels'  => \%dropdownlabels,
						'tooltip' => "$display_field filter - Select $a_or_an $display_field to filter your search to only those "
						  . "isolates that match the selected $display_field."
					}
				  );
			}
		}
		my $extatt = $extended->{$field};
		if ( ref $extatt eq 'ARRAY' ) {
			foreach my $extended_attribute (@$extatt) {
				if ( $self->{'prefs'}->{'dropdownfields'}->{"$field\..$extended_attribute"} ) {
					my $values = $self->{'datastore'}->run_list_query(
						"SELECT DISTINCT value FROM isolate_value_extended_attributes WHERE isolate_field=? AND attribute=? ORDER BY value",
						$field, $extended_attribute
					);
					my $a_or_an = substr( $extended_attribute, 0, 1 ) =~ /[aeiouAEIOU]/ ? 'an' : 'a';
					push @filters,
					  $self->get_filter(
						"$field\..$extended_attribute",
						$values,
						{
							    'tooltip' => "$field\..$extended_attribute filter - Select $a_or_an $extended_attribute to filter your "
							  . "search to only those isolates that match the selected $field."
						}
					  );
				}
			}
		}
	}
	my $buffer = $self->get_publication_filter( { any => 1, multiple => 1 } );
	push @filters, $buffer if $buffer;
	$buffer = $self->get_project_filter( { any => 1, multiple => 1 } );
	push @filters, $buffer if $buffer;
	my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	foreach my $scheme (@$schemes) {
		my $field = "scheme_$scheme->{'id'}\_profile_status";
		if ( $prefs->{'dropdownfields'}->{$field} ) {
			push @filters,
			  $self->get_filter(
				$field,
				[ 'complete', 'incomplete', 'partial', 'started', 'not started' ],
				{
					'text'    => "$scheme->{'description'} profiles",
					'tooltip' => "$scheme->{'description'} profile completion filter - Select whether the isolates should "
					  . "have complete, partial, or unstarted profiles."
				}
			  );
		}
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields( $scheme->{'id'} );
		foreach my $field (@$scheme_fields) {
			if ( $self->{'prefs'}->{"dropdown\_scheme_fields"}->{ $scheme->{'id'} }->{$field} ) {
				my $values = $self->{'datastore'}->get_scheme( $scheme->{'id'} )->get_distinct_fields($field);
				my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme->{'id'}, $field );
				if ( $scheme_field_info->{'type'} eq 'integer' ) {
					@$values = sort { $a <=> $b } @$values;
				}
				my $a_or_an = substr( $field, 0, 1 ) =~ /[aeiouAEIOU]/ ? 'an' : 'a';
				push @filters,
				  $self->get_filter(
					"scheme\_$scheme->{'id'}\_$field",
					$values,
					{
						'text'    => "$field ($scheme->{'description'})",
						'tooltip' => "$field ($scheme->{'description'}) filter - Select $a_or_an $field to filter your search "
						  . "to only those isolates that match the selected $field."
					}
				  ) if @$values;
			}
		}
	}
	my $linked_seqs = $self->{'datastore'}->run_simple_query("SELECT EXISTS(SELECT id FROM sequence_bin)")->[0];
	if ($linked_seqs) {
		my @values = ( 'Any sequence data', 'No sequence data' );
		if ( $self->{'system'}->{'seqbin_size_threshold'} ) {
			foreach my $value ( split /,/, $self->{'system'}->{'seqbin_size_threshold'} ) {
				push @values, "Sequence bin size >= $value Mbp";
			}
		}
		push @filters,
		  $self->get_filter(
			'linked_sequences',
			\@values,
			{
				'text'    => 'Sequence bin',
				'tooltip' => 'sequence bin filter - Filter by whether the isolate record has sequence data attached.'
			}
		  );
	}
	if (@filters) {
		my $display = $q->param('no_js') ? 'block' : 'none';
		print "<fieldset id=\"filter_fieldset\" style=\"float:left;display:$display\" class=\"coolfieldset\"><legend>Filters</legend>\n";
		print "<div><ul>\n";
		print "<li><span style=\"white-space:nowrap\">$_</span></li>" foreach (@filters);
		print "</ul></div>\n</fieldset>";
	}
	return;
}

sub _print_isolate_locus_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $locus_list, $locus_labels ) = $self->get_field_selection_list( { 'loci' => 1, 'scheme_fields' => 1, 'sort_labels' => 1 } );
	if (@$locus_list) {
		my $display = $q->param('no_js') ? 'block' : 'none';
		print "<fieldset id=\"locus_fieldset\" style=\"float:left;display:$display\" class=\"coolfieldset\">\n";
		print "<legend>Allele designations/scheme fields</legend><div>\n";
		my $locus_fields = $q->param('no_js') ? 4 : ( $self->_highest_entered_fields('loci') || 1 );
		my $loci_field_heading = $locus_fields == 1 ? 'none' : 'inline';
		print "<span id=\"loci_field_heading\" style=\"display:$loci_field_heading\"><label for=\"c1\">Combine with: </label>\n";
		print $q->popup_menu( -name => 'c1', -id => 'c1', -values => [qw (AND OR)], );
		print "</span>\n<ul id=\"loci\">\n";

		for ( 1 .. $locus_fields ) {
			print "<li>\n";
			$self->_print_loci_fields( $_, $locus_fields, $locus_list, $locus_labels );
			print "</li>\n";
		}
		print "</ul>\n</div></fieldset>\n";
	}
	return;
}

sub _print_isolate_tag_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	return if !$self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM allele_sequences")->[0];
	my ( $locus_list, $locus_labels ) = $self->get_field_selection_list( { 'loci' => 1, 'scheme_fields' => 0, 'sort_labels' => 1 } );
	if (@$locus_list) {
		my $display = $q->param('no_js') ? 'block' : 'none';
		print "<fieldset id=\"tag_fieldset\" style=\"float:left;display:$display\" class=\"coolfieldset\">\n";
		print "<legend>Tagged sequences</legend><div>\n";
		my $locus_tag_fields = $q->param('no_js') ? 4 : ( $self->_highest_entered_fields('tags') || 1 );
		my $locus_tags_heading = $locus_tag_fields == 1 ? 'none' : 'inline';
		print "<span id=\"locus_tags_heading\" style=\"display:$locus_tags_heading\"><label for=\"c1\">Combine with: </label>\n";
		print $q->popup_menu( -name => 'c2', -id => 'c2', -values => [qw (AND OR)], );
		print "</span>\n<ul id=\"tags\">\n";

		for ( 1 .. $locus_tag_fields ) {
			print "<li>\n";
			$self->_print_locus_tag_fields( $_, $locus_tag_fields, $locus_list, $locus_labels );
			print "</li>\n";
		}
		print "</ul></div>\n</fieldset>\n";
	}
	return;
}

sub _print_isolate_display_fieldset {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $prefs  = $self->{'prefs'};
	print "<fieldset id=\"display_fieldset\" style=\"float:left\"><legend>Display/sort options</legend>\n";
	my ( $order_list, $labels ) = $self->get_field_selection_list( { isolate_fields => 1, loci => 1, scheme_fields => 1 } );
	print "<ul>\n<li><span style=\"white-space:nowrap\">\n<label for=\"order\" class=\"display\">Order by: </label>\n";
	print $self->popup_menu( -name => 'order', -id => 'order', -values => $order_list, -labels => $labels );
	print $q->popup_menu( -name => 'direction', -values => [ 'ascending', 'descending' ], -default => 'ascending' );
	print "</span></li>\n<li>";
	print $self->get_number_records_control;
	print "</li>\n</ul>\n</fieldset>\n";
	return;
}

sub _highest_entered_fields {
	my ( $self, $type ) = @_;
	my $param_name;
	if ( any { $type eq $_ } qw (provenance scheme table_fields) ) {
		$param_name = 't';
	} elsif ( $type eq 'loci' ) {
		$param_name = 'lt';
	} elsif ( $type eq 'tags' ) {
		$param_name = 'tt';
	}
	my $q = $self->{'cgi'};
	my $highest;
	for ( 1 .. MAX_ROWS ) {
		$highest = $_ if defined $q->param("$param_name$_") && $q->param("$param_name$_") ne '';
	}
	return $highest;
}
####END ISOLATE INTERFACE#######################################################
####START PROFILE INTERFACE#####################################################
sub _get_profile_select_items {
	my ( $self, $scheme_id ) = @_;
	my ( @selectitems, @orderitems, %cleaned );
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $primary_key;
	eval {
		$primary_key =
		  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )->[0];
	};
	if ($@) {
		$logger->error("No primary key - this should not have been called.");
		return;
	}
	push @selectitems, $primary_key;
	push @orderitems,  $primary_key;
	foreach my $locus (@$loci) {
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		$cleaned{$locus} = $locus;
		$cleaned{$locus} .= " ($locus_info->{'common_name'})" if $locus_info->{'common_name'};
		my $set_id = $self->get_set_id;
		if ($set_id) {
			my $set_cleaned = $self->{'datastore'}->get_set_locus_label( $locus, $set_id );
			$cleaned{$locus} = $set_cleaned if $set_cleaned;
		}
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
	foreach (qw (sender curator)) {
		push @selectitems, "$_ (id)", "$_ (surname)", "$_ (first_name)", "$_ (affiliation)";
		push @orderitems, $_;
	}
	push @selectitems, qw	(date_entered datestamp);
	$cleaned{'date_entered'} = 'date entered';
	( $cleaned{"$primary_key"} = $primary_key ) =~ tr/_/ /;
	return ( $primary_key, \@selectitems, \@orderitems, \%cleaned );
}

sub _print_scheme_fields {
	my ( $self, $row, $max_rows, $scheme_id, $selectitems, $labels ) = @_;
	my $q = $self->{'cgi'};
	print "<span style=\"white-space:nowrap\">\n";
	print $q->popup_menu( -name => "s$row", -values => $selectitems, -labels => $labels, -class => 'fieldlist' );
	print $q->popup_menu( -name => "y$row", -values => [OPERATORS] );
	print $q->textfield( -name => "t$row", -class => 'value_entry' );
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		if ( !$q->param('no_js') ) {
			my $page = $self->{'curate'} ? 'profileQuery' : 'query';
			print
"<a id=\"add_scheme_fields\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;fields=scheme&amp;scheme_id=$scheme_id&amp;row=$next_row&amp;no_header=1\" data-rel=\"ajax\" class=\"button\">&nbsp;+&nbsp;</a>\n";
			print " <a class=\"tooltip\" id=\"scheme_field_tooltip\" title=\"\">&nbsp;<i>i</i>&nbsp;</a>";
		}
	}
	print "</span>\n";
	return;
}

sub _print_profile_query_interface {
	my ($self)    = @_;
	my $system    = $self->{'system'};
	my $prefs     = $self->{'prefs'};
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	return if defined $scheme_id && $self->is_scheme_invalid( $scheme_id, { with_pk => 1 } );
	$self->print_scheme_section( { with_pk => 1 } );
	$scheme_id = $q->param('scheme_id');    #Will be set by scheme section method
	my $set_id = $self->get_set_id;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	say "<div class=\"box\" id=\"queryform\"><div class=\"scrollable\">";
	say $q->startform;
	say $q->hidden($_) foreach qw (db page scheme_id no_js);
	my $scheme_field_count = $q->param('no_js') ? 4 : ( $self->_highest_entered_fields('scheme') || 1 );
	my $scheme_field_heading = $scheme_field_count == 1 ? 'none' : 'inline';
	say "<div style=\"white-space:nowrap\">";
	say "<fieldset style=\"float:left\">\n<legend>Locus/scheme fields</legend>";
	say "<span id=\"scheme_field_heading\" style=\"display:$scheme_field_heading\"><label for=\"c0\">Combine searches with: </label>";
	say $q->popup_menu( -name => 'c0', -id => 'c0', -values => [ "AND", "OR" ] );
	say "</span><ul id=\"scheme_fields\">";
	my ( $primary_key, $selectitems, $orderitems, $cleaned ) = $self->_get_profile_select_items($scheme_id);

	foreach my $i ( 1 .. $scheme_field_count ) {
		print "<li>";
		$self->_print_scheme_fields( $i, $scheme_field_count, $scheme_id, $selectitems, $cleaned );
		say "</li>";
	}
	say "</ul>";
	say "</fieldset>";
	my @filters;
	if ( $self->{'config'}->{'ref_db'} ) {
		my $pmid = $self->{'datastore'}->run_list_query( "SELECT DISTINCT(pubmed_id) FROM profile_refs WHERE scheme_id=?", $scheme_id );
		if (@$pmid) {
			my $labels = $self->{'datastore'}->get_citation_hash($pmid);
			my @values = sort { $labels->{$a} cmp $labels->{$b} } keys %$labels;
			push @filters,
			  $self->get_filter(
				'publication',
				\@values,
				{
					labels => $labels,
					text   => 'Publication',
					tooltip =>
"publication filter - Select a publication to filter your search to only those isolates that match the selected publication."
				}
			  );
		}
	}
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach my $field (@$scheme_fields) {
		if ( $self->{'prefs'}->{"dropdown\_scheme_fields"}->{$scheme_id}->{$field} ) {
			my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
			my $value_clause = $scheme_field_info->{'type'} eq 'integer' ? 'CAST(value AS integer)' : 'value';
			my $values =
			  $self->{'datastore'}->run_list_query(
				"SELECT DISTINCT $value_clause FROM profile_fields WHERE scheme_id=? AND scheme_field=? ORDER BY $value_clause",
				$scheme_id, $field );
			next if !@$values;
			my $a_or_an = substr( $field, 0, 1 ) =~ /[aeiouAEIOU]/ ? 'an' : 'a';
			push @filters,
			  $self->get_filter(
				$field, $values,
				{
					text => $field,
					tooltip =>
"$field ($scheme_info->{'description'}) filter - Select $a_or_an $field to filter your search to only those profiles that match the selected $field."
				}
			  );
		}
	}
	say "<fieldset id=\"display_fieldset\" style=\"float:left\"><legend>Display/sort options</legend>";
	say "<ul>\n<li><span style=\"white-space:nowrap\">\n<label for=\"order\" class=\"display\">Order by: </label>";
	say $q->popup_menu( -name => 'order', -id => 'order', -values => $orderitems, -labels => $cleaned );
	say $q->popup_menu( -name => 'direction', -values => [ 'ascending', 'descending' ], -default => 'ascending' );
	say "</span></li>\n<li>";
	say $self->get_number_records_control;
	say "</li>\n</ul>\n</fieldset>";
	say "</div>\n<div style=\"clear:both\"></div>";

	if (@filters) {
		say "<fieldset style=\"float:left\">";
		say "<legend>Filter query by</legend>";
		say "<ul>";
		foreach (@filters) {
			say "<li><span style=\"white-space:nowrap\">$_</span></li>";
		}
		say "</ul>\n</fieldset>";
	}
	my $page = $self->{'curate'} ? 'profileQuery' : 'query';
	$self->print_action_fieldset( { page => $page, scheme_id => $scheme_id } );
	say $q->end_form;
	say "</div></div>";
	return;
}
####END PROFILE INTERFACE#######################################################
sub _run_isolate_query {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $system = $self->{'system'};
	my $view   = $system->{'view'};
	my $qry;
	my @errors;
	my $extended = $self->get_extended_attributes;
	if ( !defined $q->param('query') ) {
		$qry = $self->_generate_isolate_query_for_provenance_fields( \@errors );
		$qry = $self->_modify_isolate_query_for_filters( $qry, $extended );
		$qry = $self->_modify_isolate_query_for_designations( $qry, \@errors );
		$qry = $self->_modify_isolate_query_for_tags( $qry, \@errors );
		$qry .= " ORDER BY ";
		if ( defined $q->param('order') && ( $q->param('order') =~ /^la_(.+)\|\|/ || $q->param('order') =~ /^cn_(.+)/ ) ) {
			$qry .= "l_$1";
		} else {
			$qry .= $q->param('order') || 'id';
		}
		my $dir = ( defined $q->param('direction') && $q->param('direction') eq 'descending' ) ? 'desc' : 'asc';
		$qry .= " $dir,$self->{'system'}->{'view'}.id;";
	} else {
		$qry = $q->param('query');
	}
	if (@errors) {
		local $" = '<br />';
		print "<div class=\"box\" id=\"statusbad\"><p>Problem with search criteria:</p>\n";
		print "<p>@errors</p></div>\n";
	} elsif ( $qry !~ /\(\)/ ) {
		my @hidden_attributes;
		push @hidden_attributes, qw (c0 c1 c2);
		for ( 1 .. MAX_ROWS ) {
			push @hidden_attributes, "s$_", "t$_", "y$_", "ls$_", "ly$_", "lt$_", "ts$_", "tt$_";
		}
		foreach ( @{ $self->{'xmlHandler'}->get_field_list() } ) {
			push @hidden_attributes, "$_\_list";
			my $extatt = $extended->{$_};
			if ( ref $extatt eq 'ARRAY' ) {
				foreach my $extended_attribute (@$extatt) {
					push @hidden_attributes, "$_\..$extended_attribute\_list";
				}
			}
		}
		push @hidden_attributes, qw(no_js publication_list project_list linked_sequences_list);
		my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
		foreach my $scheme_id (@$schemes) {
			push @hidden_attributes, "scheme_$scheme_id\_profile_status_list";
			my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
			push @hidden_attributes, "scheme_$scheme_id\_$_\_list" foreach (@$scheme_fields);
		}
		my $view = $self->{'system'}->{'view'};
		$qry =~ s/ datestamp/ $view\.datestamp/g;     #datestamp exists in other tables and can be ambiguous on complex queries
		$qry =~ s/\(datestamp/\($view\.datestamp/g;
		$self->paged_display( $self->{'system'}->{'view'}, $qry, '', \@hidden_attributes );
	} else {
		say "<div class=\"box\" id=\"statusbad\">Invalid search performed.  Try to <a href=\"$self->{'system'}->{'script_name'}?db="
		  . "$self->{'instance'}&amp;page=browse\">browse all records</a>.</div>";
	}
	return;
}

sub get_grouped_fields {
	my ( $self, $field, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	$field =~ s/^f_// if $options->{'strip_prefix'};
	my @groupedfields;
	for ( 1 .. 10 ) {
		if ( $self->{'system'}->{"fieldgroup$_"} ) {
			my @grouped = ( split /:/, $self->{'system'}->{"fieldgroup$_"} );
			@groupedfields = split /,/, $grouped[1] if $field eq $grouped[0];
		}
	}
	return @groupedfields;
}

sub _grouped_field_query {
	my ( $self, $groupedfields, $data, $errors_ref ) = @_;
	my $text     = $data->{'text'};
	my $operator = $data->{'operator'};
	my $view     = $self->{'system'}->{'view'};
	my $buffer   = "$data->{'modifier'} (";
	if ( $operator eq 'NOT' ) {
		foreach (@$groupedfields) {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($_);
			if ( $text eq 'null' ) {
				$buffer .= ' OR ' if $_ ne $groupedfields->[0];
				$buffer .= "($view.$_ IS NOT NULL)";
			} else {
				$buffer .= ' AND ' if $_ ne $groupedfields->[0];
				if ( $thisfield->{'type'} ne 'text' ) {
					$buffer .= "(NOT CAST($view.$_ AS text) = E'$text' OR $view.$_ IS NULL)";
				} else {
					$buffer .= "(NOT upper($view.$_) = upper(E'$text') OR $view.$_ IS NULL)";
				}
			}
		}
	} elsif ( $operator eq "contains" ) {
		foreach (@$groupedfields) {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($_);
			$buffer .= ' OR ' if $_ ne $groupedfields->[0];
			if ( $thisfield->{'type'} ne 'text' ) {
				$buffer .= "CAST($view.$_ AS text) LIKE E'\%$text\%'";
			} else {
				$buffer .= "upper($view.$_) LIKE upper(E'\%$text\%')";
			}
		}
	} elsif ( $operator eq "NOT contain" ) {
		foreach (@$groupedfields) {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($_);
			$buffer .= ' AND ' if $_ ne $groupedfields->[0];
			if ( $thisfield->{'type'} ne 'text' ) {
				$buffer .= "(NOT CAST($view.$_ AS text) LIKE E'\%$text\%' OR $view.$_ IS NULL)";
			} else {
				$buffer .= "(NOT upper($view.$_) LIKE upper(E'\%$text\%') OR $view.$_ IS NULL)";
			}
		}
	} elsif ( $operator eq '=' ) {
		foreach (@$groupedfields) {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($_);
			$buffer .= ' OR ' if $_ ne $groupedfields->[0];
			if ( $thisfield->{'type'} ne 'text' ) {
				$buffer .= $text eq 'null' ? "$view.$_ IS NULL" : "CAST($view.$_ AS text) = E'$text'";
			} else {
				$buffer .= $text eq 'null' ? "$view.$_ IS NULL" : "upper($view.$_) = upper(E'$text')";
			}
		}
	} else {
		foreach (@$groupedfields) {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($_);
			return
			  if $self->check_format( { field => $_, text => $text, type => $thisfield->{'type'}, operator => $data->{'operator'} },
				$errors_ref );
			$buffer .= ' OR ' if $_ ne $groupedfields->[0];
			if ( $thisfield->{'type'} ne 'text' ) {
				$buffer .= "(CAST($view.$_ AS text) $operator E'$text' AND $view.$_ is not null)";
			} else {
				$buffer .= "($view.$_ $operator E'$text' AND $view.$_ is not null)";
			}
		}
	}
	$buffer .= ')';
	return $buffer;
}

sub _generate_isolate_query_for_provenance_fields {
	my ( $self, $errors_ref ) = @_;
	my $q           = $self->{'cgi'};
	my $view        = $self->{'system'}->{'view'};
	my $qry         = "SELECT * FROM $view WHERE (";
	my $andor       = $q->param('c0') || 'AND';
	my $first_value = 1;
	foreach my $i ( 1 .. MAX_ROWS ) {
		if ( defined $q->param("t$i") && $q->param("t$i") ne '' ) {
			my $field = $q->param("s$i");
			$field =~ s/^f_//;
			my @groupedfields = $self->get_grouped_fields($field);
			my $thisfield     = $self->{'xmlHandler'}->get_field_attributes($field);
			my $extended_isolate_field;
			if ( $field =~ /^e_(.*)\|\|(.*)/ ) {
				$extended_isolate_field = $1;
				$field                  = $2;
				my $att_info =
				  $self->{'datastore'}
				  ->run_simple_query_hashref( "SELECT * FROM isolate_field_extended_attributes WHERE isolate_field=? AND attribute=?",
					$extended_isolate_field, $field );
				$thisfield->{'type'} = $att_info->{'value_format'};
				$thisfield->{'type'} = 'int' if $thisfield->{'type'} eq 'integer';
			}
			my $operator = $q->param("y$i");
			my $text     = $q->param("t$i");
			$self->process_value( \$text );
			next
			  if $self->check_format( { field => $field, text => $text, type => lc( $thisfield->{'type'} // '' ), operator => $operator },
				$errors_ref );
			my $modifier = ( $i > 1 && !$first_value ) ? " $andor " : '';
			$first_value = 0;
			if ( $field =~ /(.*) \(id\)$/
				&& !BIGSdb::Utils::is_int($text) )
			{
				push @$errors_ref, "$field is an integer field.";
				next;
			}
			if ( any { $field =~ /(.*) \($_\)$/ } qw (id surname first_name affiliation) ) {
				$qry .= $modifier . $self->search_users( $field, $operator, $text, $view );
			} else {
				if (@groupedfields) {
					$qry .=
					  $self->_grouped_field_query( \@groupedfields, { text => $text, operator => $operator, modifier => $modifier },
						$errors_ref );
					next;
				}
				my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
				if ( !$extended_isolate_field ) {
					if ( !$self->{'xmlHandler'}->is_field($field) ) {
						push @$errors_ref, "$field is an invalid field.";
						next;
					}
					$field = "$view.$field";
				}
				my $args = {
					field                  => $field,
					extended_isolate_field => $extended_isolate_field,
					text                   => $text,
					modifier               => $modifier,
					type                   => $thisfield->{'type'}
				};
				if ( $operator eq 'NOT' ) {
					$args->{'not'} = 1;
					$qry .= $self->_provenance_equals_type_operator($args);
				} elsif ( $operator eq "contains" ) {
					$args->{'behaviour'} = '%text%';
					$qry .= $self->_provenance_like_type_operator($args);
				} elsif ( $operator eq 'starts with' ) {
					$args->{'behaviour'} = 'text%';
					$qry .= $self->_provenance_like_type_operator($args);
				} elsif ( $operator eq 'ends with' ) {
					$args->{'behaviour'} = '%text';
					$qry .= $self->_provenance_like_type_operator($args);
				} elsif ( $operator eq "NOT contain" ) {
					$args->{'behaviour'} = '%text%';
					$args->{'not'}       = 1;
					$qry .= $self->_provenance_like_type_operator($args);
				} elsif ( $operator eq '=' ) {
					$qry .= $self->_provenance_equals_type_operator($args);
				} else {
					my $labelfield = "$view.$self->{'system'}->{'labelfield'}";
					$qry .= $modifier;
					if ($extended_isolate_field) {
						$qry .= "$view.$extended_isolate_field IN (SELECT field_value FROM isolate_value_extended_attributes WHERE "
						  . "isolate_field='$extended_isolate_field' AND attribute='$field' AND value $operator E'$text')";
					} elsif ( $field eq $labelfield ) {
						$qry .= "($field $operator '$text' OR $view.id IN (SELECT isolate_id FROM isolate_aliases WHERE alias "
						  . "$operator E'$text'))";
					} else {
						if ( $text eq 'null' ) {
							push @$errors_ref, "$operator is not a valid operator for comparing null values.";
							next;
						}
						if ( defined $metaset ) {
							$qry .= "id IN (SELECT isolate_id FROM meta_$metaset WHERE $metafield $operator E'$text')";
						} else {
							$qry .= "$field $operator E'$text'";
						}
					}
				}
			}
		}
	}
	$qry .= ')';
	return $qry;
}

sub _provenance_equals_type_operator {
	my ( $self, $values ) = @_;
	my $buffer     = $values->{'modifier'};
	my $view       = $self->{'system'}->{'view'};
	my $labelfield = "$view.$self->{'system'}->{'labelfield'}";
	my $not        = $values->{'not'} ? 'NOT' : '';
	my $inv_not    = $values->{'not'} ? '' : 'NOT';
	if ( $values->{'extended_isolate_field'} ) {
		$buffer .=
		  $values->{'text'} eq 'null'
		  ? "$view.$values->{'extended_isolate_field'} $inv_not IN (SELECT field_value FROM isolate_value_extended_attributes WHERE "
		  . "isolate_field='$values->{'extended_isolate_field'}' AND attribute='$values->{'field'}')"
		  : "$view.$values->{'extended_isolate_field'} $not IN (SELECT field_value FROM isolate_value_extended_attributes WHERE "
		  . "isolate_field='$values->{'extended_isolate_field'}' AND attribute='$values->{'field'}' AND upper(value) = upper(E'$values->{'text'}'))";
	} elsif ( $values->{'field'} eq $labelfield ) {
		$buffer .=
		    "($not upper($values->{'field'}) = upper(E'$values->{'text'}') "
		  . ( $values->{'not'} ? ' AND ' : ' OR ' )
		  . "$view.id $not IN (SELECT isolate_id FROM isolate_aliases WHERE "
		  . "upper(alias) = upper(E'$values->{'text'}')))";
	} else {
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname( $values->{'field'} );
		if ( defined $metaset ) {
			my $andor = $not ? 'AND' : 'OR';
			if ( $values->{'text'} eq 'null' ) {
				$buffer .= "$view.id $not IN (SELECT isolate_id FROM meta_$metaset WHERE $metafield IS NULL) $andor id $inv_not "
				  . "IN (SELECT isolate_id FROM meta_$metaset)";
			} else {
				$buffer .=
				  lc( $values->{'type'} ) eq 'text'
				  ? "$view.id $not IN (SELECT isolate_id FROM meta_$metaset WHERE upper($metafield) = upper(E'$values->{'text'}') )"
				  : "$view.id $not IN (SELECT isolate_id FROM meta_$metaset WHERE $metafield = E'$values->{'text'}' )";
			}
		} else {
			my $null_clause = $values->{'not'} ? "OR $values->{'field'} IS NULL" : '';
			if ( lc( $values->{'type'} ) eq 'text' ) {
				$buffer .= (
					$values->{'text'} eq 'null'
					? "$values->{'field'} is $not null"
					: "($not upper($values->{'field'}) = upper(E'$values->{'text'}') $null_clause)"
				);
			} else {
				$buffer .= (
					$values->{'text'} eq 'null'
					? "$values->{'field'} is $not null"
					: "$not ($values->{'field'} = E'$values->{'text'}' $null_clause)"
				);
			}
		}
	}
	return $buffer;
}

sub _provenance_like_type_operator {
	my ( $self, $values ) = @_;
	my $buffer     = $values->{'modifier'};
	my $view       = $self->{'system'}->{'view'};
	my $labelfield = "$view.$self->{'system'}->{'labelfield'}";
	my $not        = $values->{'not'} ? 'NOT' : '';
	( my $text = $values->{'behaviour'} ) =~ s/text/$values->{'text'}/;
	if ( $values->{'extended_isolate_field'} ) {
		$buffer .= "$view.$values->{'extended_isolate_field'} $not IN (SELECT field_value FROM isolate_value_extended_attributes "
		  . "WHERE isolate_field='$values->{'extended_isolate_field'}' AND attribute='$values->{'field'}' AND value ILIKE E'$text')";
	} elsif ( $values->{'field'} eq $labelfield ) {
		my $andor = $values->{'not'} ? 'AND' : 'OR';
		$buffer .= "($not $values->{'field'} ILIKE E'$text' $andor $view.id $not IN (SELECT isolate_id FROM isolate_aliases WHERE "
		  . "alias ILIKE E'$text'))";
	} else {
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname( $values->{'field'} );
		if ( defined $metaset ) {
			$buffer .=
			  lc( $values->{'type'} ) eq 'text'
			  ? "$view.id $not IN (SELECT isolate_id FROM meta_$metaset WHERE $metafield ILIKE E'$text')"
			  : "$view.id $not IN (SELECT isolate_id FROM meta_$metaset WHERE CAST($metafield AS text) LIKE E'$text')";
		} else {
			my $null_clause = $values->{'not'} ? "OR $values->{'field'} IS NULL" : '';
			if ( $values->{'type'} ne 'text' ) {
				$buffer .= "($not CAST($values->{'field'} AS text) LIKE E'$text' $null_clause)";
			} else {
				$buffer .= "($not $values->{'field'} ILIKE E'$text' $null_clause)";
			}
		}
	}
	return $buffer;
}

sub _modify_isolate_query_for_filters {
	my ( $self, $qry, $extended ) = @_;

	#extended: extended attributes hashref;
	my $q             = $self->{'cgi'};
	my $view          = $self->{'system'}->{'view'};
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
	foreach my $field (@$field_list) {
		if ( defined $q->param("$field\_list") && $q->param("$field\_list") ne '' ) {
			my $value = $q->param("$field\_list");
			if ( $qry !~ /WHERE \(\)\s*$/ ) {
				$qry .= " AND ";
			} else {
				$qry = "SELECT * FROM $view WHERE ";
			}
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			if ( defined $metaset ) {
				$qry .= (
					( $value eq '<blank>' || $value eq 'null' )
					? "(id IN (SELECT isolate_id FROM meta_$metaset WHERE $metafield IS NULL) OR id NOT IN (SELECT isolate_id FROM "
					  . "meta_$metaset))"
					: "(id IN (SELECT isolate_id FROM meta_$metaset WHERE $metafield = E'$value'))"
				);
			} else {
				$qry .= ( ( $value eq '<blank>' || $value eq 'null' ) ? "$view.$field is null" : "$view.$field = '$value'" );
			}
		}
		my $extatt = $extended->{$field};
		if ( ref $extatt eq 'ARRAY' ) {
			foreach my $extended_attribute (@$extatt) {
				if ( defined $q->param("$field\..$extended_attribute\_list") && $q->param("$field\..$extended_attribute\_list") ne '' ) {
					my $value = $q->param("$field\..$extended_attribute\_list");
					$value =~ s/'/\\'/g;
					if ( $qry !~ /WHERE \(\)\s*$/ ) {
						$qry .= " AND ($field IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$field' "
						  . "AND attribute='$extended_attribute' AND value='$value'))";
					} else {
						$qry = "SELECT * FROM $view WHERE ($field IN (SELECT field_value FROM isolate_value_extended_attributes WHERE "
						  . "isolate_field='$field' AND attribute='$extended_attribute' AND value='$value'))";
					}
				}
			}
		}
	}
	$self->_modify_query_by_membership( \$qry, 'refs',            'publication_list', 'isolate_id', $view, 'pubmed_id' );
	$self->_modify_query_by_membership( \$qry, 'project_members', 'project_list',     'isolate_id', $view, 'project_id' );
	if ( $q->param('linked_sequences_list') ) {
		my $not         = '';
		my $size_clause = '';
		if ( $q->param('linked_sequences_list') eq 'No sequence data' ) {
			$not = ' NOT ';
		} elsif ( $q->param('linked_sequences_list') =~ />= ([\d\.]+) Mbp/ ) {
			my $size = $1 * 1000000;    #Mbp
			$size_clause = " GROUP BY isolate_id HAVING SUM(length(sequence)) >= $size";
		}
		if ( $qry !~ /WHERE \(\)\s*$/ ) {
			$qry .= " AND (${not}EXISTS (SELECT 1 FROM sequence_bin WHERE sequence_bin.isolate_id = $view.id$size_clause))";
		} else {
			$qry = "SELECT * FROM $view WHERE (${not}EXISTS (SELECT 1 FROM sequence_bin WHERE sequence_bin.isolate_id = "
			  . "$view.id$size_clause))";
		}
	}
	my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
	foreach my $scheme_id (@$schemes) {
		if ( defined $q->param("scheme_$scheme_id\_profile_status_list") && $q->param("scheme_$scheme_id\_profile_status_list") ne '' ) {
			my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
			if (@$scheme_loci) {
				my $allele_clause;
				my $first = 1;
				foreach my $locus (@$scheme_loci) {
					$locus =~ s/'/\\'/g;
					$allele_clause .= ' OR ' if !$first;
					$allele_clause .= "(locus=E'$locus')";
					$first = 0;
				}
				my $param  = $q->param("scheme_$scheme_id\_profile_status_list");
				my $clause = "(EXISTS (SELECT isolate_id FROM allele_designations WHERE $view.id=allele_designations.isolate_id AND "
				  . "($allele_clause) GROUP BY isolate_id HAVING COUNT(isolate_id)";
				my $locus_count = @$scheme_loci;
				given ($param) {
					when ('complete') { $clause .= "=$locus_count))" }
					when ('partial')  { $clause .= "<$locus_count))" }
					when ('started')  { $clause .= '>0))' }
					when ('incomplete') {
						$clause .= "<$locus_count) OR NOT (EXISTS (SELECT isolate_id FROM allele_designations WHERE "
						  . "$view.id=allele_designations.isolate_id AND ($allele_clause) GROUP BY isolate_id )))";
					}
					default {
						$clause = "(NOT (EXISTS (SELECT isolate_id FROM allele_designations WHERE $view.id=allele_designations.isolate_id "
						  . "AND ($allele_clause) GROUP BY isolate_id )))";
					}
				}
				if ( $qry !~ /WHERE \(\)\s*$/ ) {
					$qry .= "AND $clause";
				} else {
					$qry = "SELECT * FROM $view WHERE $clause";
				}
			}
		}
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		foreach my $field (@$scheme_fields) {
			if ( defined $q->param("scheme_$scheme_id\_$field\_list") && $q->param("scheme_$scheme_id\_$field\_list") ne '' ) {
				my $temp_table = $self->{'datastore'}->create_temp_isolate_scheme_table($scheme_id);
				my $value      = $q->param("scheme_$scheme_id\_$field\_list");
				$value =~ s/'/\\'/g;
				my $clause;
				my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
				$field = "scheme_$scheme_id\.$field";
				my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
				my ( %cleaned, %named, %scheme_named );

				foreach my $locus (@$scheme_loci) {
					( $cleaned{$locus}      = $locus ) =~ s/'/\\'/g;
					( $named{$locus}        = $locus ) =~ s/'/_PRIME_/g;
					( $scheme_named{$locus} = $locus ) =~ s/'/_PRIME_/g;
				}
				my @temp;
				foreach my $locus (@$scheme_loci) {
					push @temp,
					  $self->get_scheme_locus_query_clause( $scheme_id, $temp_table, $locus, $scheme_named{$locus}, $named{$locus} );
				}
				local $" = ' AND ';
				my $joined_query = "SELECT $temp_table.id FROM $temp_table INNER JOIN temp_scheme_$scheme_id AS scheme_$scheme_id ON @temp";
				$value =~ s/'/\\'/g;
				if ( $scheme_field_info->{'type'} eq 'integer' ) {
					$clause = "(EXISTS ($joined_query WHERE $view.id = $temp_table.id AND CAST($field AS int) = E'$value'))";
				} else {
					$clause = "(EXISTS ($joined_query WHERE $view.id = $temp_table.id AND UPPER($field) = UPPER(E'$value')))";
				}
				if ( $qry !~ /WHERE \(\)\s*$/ ) {
					$qry .= "AND $clause";
				} else {
					$qry = "SELECT * FROM $view WHERE $clause";
				}
			}
		}
	}
	return $qry;
}

sub _modify_query_by_membership {

	#Modify query for membership of PubMed paper or project
	my ( $self, $qry_ref, $table, $param, $article, $main_table, $query_field ) = @_;
	my $q = $self->{'cgi'};
	return if !$q->param($param);
	my @list = $q->param($param);
	my $subqry;
	if ( any { $_ eq 'any' } @list ) {
		$subqry = "$main_table.id IN (SELECT isolate_id FROM $table)";
	}
	if ( any { $_ eq 'none' } @list ) {
		$subqry .= ' OR ' if $subqry;
		$subqry .= "$main_table.id NOT IN (SELECT isolate_id FROM $table)";
	}
	if ( any { BIGSdb::Utils::is_int($_) } @list ) {
		my @int_list = grep { BIGSdb::Utils::is_int($_) } @list;
		$subqry .= ' OR ' if $subqry;
		local $" = ',';
		$subqry .= "$main_table.id IN (SELECT isolate_id FROM $table WHERE $query_field IN (@int_list))";
	}
	if ($subqry) {
		if ( $$qry_ref !~ /WHERE \(\)\s*$/ ) {
			$$qry_ref .= " AND ($subqry)";
		} else {
			$$qry_ref = "SELECT * FROM $main_table WHERE ($subqry)";
		}
	}
	return;
}

sub get_scheme_locus_query_clause {
	my ( $self, $scheme_id, $table, $locus, $scheme_named, $named ) = @_;
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);

	#Use correct cast to ensure that database indexes are used.
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
		if ( $scheme_info->{'allow_missing_loci'} ) {
			return "(COALESCE($table.$named,'N')=scheme_$scheme_id\.$scheme_named OR scheme_$scheme_id\.$scheme_named='N')";

			#			return "(CAST(COALESCE($named,'N') AS text)=CAST(scheme_$scheme_id\.$scheme_named AS text) "
			#			  . "OR scheme_$scheme_id\.$scheme_named='N')";
		} else {
			return "CAST($table.$named AS int)=scheme_$scheme_id\.$scheme_named";
		}
	} else {
		if ( $scheme_info->{'allow_missing_loci'} ) {
			return "COALESCE($table.$named,'N')=scheme_$scheme_id\.$scheme_named";
		} else {
			return "$table.$named=scheme_$scheme_id\.$scheme_named";
		}
	}
}

sub _modify_isolate_query_for_designations {
	my ( $self, $qry, $errors_ref ) = @_;
	my $q    = $self->{'cgi'};
	my $view = $self->{'system'}->{'view'};
	my ( %lqry, @lqry_blank, %combo );
	my $pattern     = LOCUS_PATTERN;
	my $andor       = defined $q->param('c1') && $q->param('c1') eq 'AND' ? ' AND ' : ' OR ';
	my $qry_started = $qry =~ /\(\)$/ ? 0 : 1;
	foreach my $i ( 1 .. MAX_ROWS ) {

		if ( defined $q->param("lt$i") && $q->param("lt$i") ne '' ) {
			if ( $q->param("ls$i") =~ /$pattern/ ) {
				my $locus            = $1;
				my $locus_info       = $self->{'datastore'}->get_locus_info($locus);
				my $unmodified_locus = $locus;
				$locus =~ s/'/\\'/g;
				my $operator = $q->param("ly$i");
				my $text     = $q->param("lt$i");
				next if $combo{"$locus\_$operator\_$text"};    #prevent duplicates
				$combo{"$locus\_$operator\_$text"} = 1;
				$self->process_value( \$text );

				if (   $text ne 'null'
					&& ( $locus_info->{'allele_id_format'} eq 'integer' )
					&& !BIGSdb::Utils::is_int($text) )
				{
					push @$errors_ref, "$unmodified_locus is an integer field.";
					next;
				} elsif ( !$self->is_valid_operator($operator) ) {
					push @$errors_ref, "$operator is not a valid operator.";
					next;
				}
				if ( $operator eq 'NOT' ) {
					$lqry{$locus} .= $andor if $lqry{$locus};
					$lqry{$locus} .= (
						( $text eq 'null' )
						? "(EXISTS (SELECT 1 WHERE allele_designations.locus=E'$locus'))"
						: "(allele_designations.locus=E'$locus' AND NOT upper(allele_designations.allele_id) = upper(E'$text'))"
					);
				} elsif ( $operator eq "contains" ) {
					$lqry{$locus} .= $andor if $lqry{$locus};
					$lqry{$locus} .=
					  "(allele_designations.locus=E'$locus' AND upper(allele_designations.allele_id) LIKE upper(E'\%$text\%'))";
				} elsif ( $operator eq "starts with" ) {
					$lqry{$locus} .= $andor if $lqry{$locus};
					$lqry{$locus} .=
					  "(allele_designations.locus=E'$locus' AND upper(allele_designations.allele_id) LIKE upper(E'$text\%'))";
				} elsif ( $operator eq "ends with" ) {
					$lqry{$locus} .= $andor if $lqry{$locus};
					$lqry{$locus} .=
					  "(allele_designations.locus=E'$locus' AND upper(allele_designations.allele_id) LIKE upper(E'\%$text'))";
				} elsif ( $operator eq "NOT contain" ) {
					$lqry{$locus} .= $andor if $lqry{$locus};
					$lqry{$locus} .=
					  "(allele_designations.locus=E'$locus' AND NOT upper(allele_designations.allele_id) LIKE upper(E'\%$text\%'))";
				} elsif ( $operator eq '=' ) {
					if ( $text eq 'null' ) {
						push @lqry_blank, "(id NOT IN (SELECT isolate_id FROM allele_designations WHERE locus=E'$locus'))";
					} else {
						$lqry{$locus} .= $andor if $lqry{$locus};
						$lqry{$locus} .=
						  $locus_info->{'allele_id_format'} eq 'text'
						  ? "(allele_designations.locus=E'$locus' AND upper(allele_designations.allele_id) = upper(E'$text'))"
						  : "(allele_designations.locus=E'$locus' AND allele_designations.allele_id = E'$text')";
					}
				} else {
					if ( $text eq 'null' ) {
						push @$errors_ref, "$operator is not a valid operator for comparing null values.";
						next;
					}
					$lqry{$locus} .= $andor if $lqry{$locus};
					if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
						$lqry{$locus} .=
						  "(allele_designations.locus=E'$locus' AND CAST(allele_designations.allele_id AS int) $operator E'$text')";
					} else {
						$lqry{$locus} .= "(allele_designations.locus=E'$locus' AND allele_designations.allele_id $operator E'$text')";
					}
				}
			}
		}
	}
	my @sqry;
	foreach my $i ( 1 .. MAX_ROWS ) {
		if ( defined $q->param("lt$i") && $q->param("lt$i") ne '' ) {
			if ( $q->param("ls$i") =~ /^s_(\d+)_(.*)/ ) {
				my ( $scheme_id, $field ) = ( $1, $2 );
				my $operator          = $q->param("ly$i");
				my $text              = $q->param("lt$i");
				my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
				my $scheme_info       = $self->{'datastore'}->get_scheme_info($scheme_id);
				$self->process_value( \$text );
				if (   $text ne 'null'
					&& ( $scheme_field_info->{'type'} eq 'integer' )
					&& !BIGSdb::Utils::is_int($text) )
				{
					push @$errors_ref, "$field is an integer field.";
					next;
				} elsif ( !$self->is_valid_operator($operator) ) {
					push @$errors_ref, "$operator is not a valid operator.";
					next;
				}
				$field = "scheme_$scheme_id\.$field";
				my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
				my ( %cleaned, %named, %scheme_named );
				foreach my $locus (@$scheme_loci) {
					( $cleaned{$locus}      = $locus ) =~ s/'/\\'/g;
					( $named{$locus}        = $locus ) =~ s/'/_PRIME_/g;
					( $scheme_named{$locus} = $locus ) =~ s/'/_PRIME_/g;
				}
				my $temp_table = $self->{'datastore'}->create_temp_isolate_scheme_table($scheme_id);
				my @temp;
				foreach my $locus (@$scheme_loci) {
					push @temp,
					  $self->get_scheme_locus_query_clause( $scheme_id, $temp_table, $locus, $scheme_named{$locus}, $named{$locus} );
				}
				local $" = ' AND ';
				my $joined_query = "SELECT $temp_table.id FROM $temp_table LEFT JOIN temp_scheme_$scheme_id AS scheme_$scheme_id ON @temp";
				$text =~ s/'/\\'/g;
				if ( $operator eq 'NOT' ) {
					push @sqry,
					  ( $text eq 'null' )
					  ? "($view.id NOT IN ($joined_query WHERE $field is null) AND $view.id IN ($joined_query))"
					  : "($view.id NOT IN ($joined_query WHERE upper($field)=upper(E'$text') AND $view.id IN ($joined_query)))";
				} elsif ( $operator eq "contains" ) {
					push @sqry,
					  $scheme_field_info->{'type'} eq 'integer'
					  ? "($view.id IN ($joined_query WHERE CAST($field AS text) ~* E'$text'))"
					  : "($view.id IN ($joined_query WHERE $field ~* E'$text'))";
				} elsif ( $operator eq "starts with" ) {
					push @sqry,
					  $scheme_field_info->{'type'} eq 'integer'
					  ? "($view.id IN ($joined_query WHERE CAST($field AS text) LIKE E'$text\%'))"
					  : "($view.id IN ($joined_query WHERE $field ILIKE E'$text\%'))";
				} elsif ( $operator eq "ends with" ) {
					push @sqry,
					  $scheme_field_info->{'type'} eq 'integer'
					  ? "($view.id IN ($joined_query WHERE CAST($field AS text) LIKE E'\%$text'))"
					  : "($view.id IN ($joined_query WHERE $field ILIKE E'\%$text'))";
				} elsif ( $operator eq "NOT contain" ) {
					push @sqry,
					  $scheme_field_info->{'type'} eq 'integer'
					  ? "($view.id IN ($joined_query WHERE CAST($field AS text) !~* E'$text'))"
					  : "($view.id IN ($joined_query WHERE $field !~* E'$text'))";
				} elsif ( $operator eq '=' ) {
					if ( $text eq 'null' ) {
						push @lqry_blank, "($view.id IN ($joined_query WHERE $field is null) OR $view.id NOT IN ($joined_query))";
					} else {
						push @sqry,
						  $scheme_field_info->{'type'} eq 'text'
						  ? "($view.id IN ($joined_query WHERE upper($field)=upper(E'$text')))"
						  : "($view.id IN ($joined_query WHERE $field=E'$text'))";
					}
				} else {
					if ( $text eq 'null' ) {
						push @$errors_ref, "$operator is not a valid operator for comparing null values.";
						next;
					}
					if ( $scheme_field_info->{'type'} eq 'integer' ) {
						push @sqry, "($view.id IN ($joined_query WHERE CAST($field AS int) $operator E'$text'))";
					} else {
						push @sqry, "($view.id IN ($joined_query WHERE $field $operator E'$text'))";
					}
				}
			}
		}
	}
	my $brace = @sqry ? '(' : '';
	if ( keys %lqry ) {
		local $" = ' OR ';
		my $modify = '';
		if ( defined $q->param('c1') && $q->param('c1') eq 'AND' ) {
			$modify = "GROUP BY id HAVING count(id)=" . scalar keys %lqry;
		}
		my @lqry = values %lqry;
		my $lqry = "$view.id IN (select distinct($view.id) FROM $view LEFT JOIN allele_designations ON $view.id="
		  . "allele_designations.isolate_id WHERE @lqry $modify)";
		if ( $qry =~ /\(\)$/ ) {
			$qry = "SELECT * FROM $view WHERE $brace$lqry";
		} else {
			$qry .= " AND $brace($lqry)";
		}
	}
	if (@lqry_blank) {
		local $" = ' ' . $q->param('c1') . ' ';
		my $modify = scalar keys %lqry ? $q->param('c1') : 'AND';
		if ( $qry =~ /\(\)$/ ) {
			$qry = "SELECT * FROM $view WHERE $brace@lqry_blank";
		} else {
			$qry .= keys %lqry ? " $modify" : ' AND';
			$qry .= " $brace(@lqry_blank)";
		}
	}
	if (@sqry) {
		my $andor = $q->param('c1') || '';
		local $" = " $andor ";
		my $sqry = "@sqry";
		if ( $qry =~ /\(\)$/ ) {
			$qry = "SELECT * FROM $view WHERE $sqry";
		} else {
			$qry .= ( keys %lqry || @lqry_blank ) ? " $andor" : ' AND';
			$qry .= " ($sqry)";
			$qry .= ')' if ( scalar keys %lqry or @lqry_blank );
		}
	}
	return $qry;
}

sub _modify_isolate_query_for_tags {
	my ( $self, $qry, $errors_ref ) = @_;
	my $q    = $self->{'cgi'};
	my $view = $self->{'system'}->{'view'};
	my @tag_queries;
	my $pattern = LOCUS_PATTERN;
	foreach my $i ( 1 .. MAX_ROWS ) {
		if ( defined $q->param("ts$i") && $q->param("ts$i") ne '' && defined $q->param("tt$i") && $q->param("tt$i") ne '' ) {
			my $action = $q->param("tt$i");
			my $locus;
			if ( $q->param("ts$i") ne 'any locus' ) {
				if ( $q->param("ts$i") =~ /$pattern/ ) {
					$locus = $1;
				}
				if ( !$self->{'datastore'}->is_locus($locus) ) {
					push @$errors_ref, "'$locus' is an invalid locus.";
					next;
				}
			} else {
				$locus = 'any locus';
			}
			$locus =~ s/'/\\'/g;
			my $temp_qry;
			my $seq_joined_table = "allele_sequences LEFT JOIN sequence_bin ON allele_sequences.seqbin_id = sequence_bin.id";
			my $locus_clause = $locus eq 'any locus' ? 'locus IS NOT NULL' : "locus=E'$locus'";
			if ( $action eq 'untagged' ) {
				$temp_qry = "$view.id NOT IN (SELECT DISTINCT isolate_id FROM $seq_joined_table WHERE $locus_clause)";
			} elsif ( $action eq 'tagged' ) {
				$temp_qry = "$view.id IN (SELECT isolate_id FROM $seq_joined_table WHERE $locus_clause)";
			} elsif ( $action eq 'complete' ) {
				$temp_qry = "$view.id IN (SELECT isolate_id FROM $seq_joined_table WHERE $locus_clause AND complete)";
			} elsif ( $action eq 'incomplete' ) {
				$temp_qry = "$view.id IN (SELECT isolate_id FROM $seq_joined_table WHERE $locus_clause AND NOT complete)";
			} elsif ( $action =~ /^flagged: ([\w\s:]+)$/ ) {
				my $flag              = $1;
				my $flag_joined_table = "sequence_flags LEFT JOIN sequence_bin ON sequence_flags.seqbin_id = sequence_bin.id";
				if ( $flag eq 'any' ) {
					$temp_qry = "$view.id IN (SELECT isolate_id FROM $flag_joined_table WHERE $locus_clause)";
				} elsif ( $flag eq 'none' ) {
					$temp_qry = "$view.id IN (SELECT isolate_id FROM $seq_joined_table WHERE $locus_clause) AND id NOT IN "
					  . "(SELECT isolate_id FROM $flag_joined_table WHERE $locus_clause)";
				} else {
					$temp_qry = "$view.id IN (SELECT isolate_id FROM $flag_joined_table WHERE $locus_clause AND flag='$flag')";
				}
			}
			push @tag_queries, $temp_qry if $temp_qry;
		}
	}
	if (@tag_queries) {
		my $andor = ( any { $q->param('c2') eq $_ } qw (AND OR) ) ? $q->param('c2') : '';
		local $" = " $andor ";
		if ( $qry !~ /WHERE \(\)\s*$/ ) {
			$qry .= " AND (@tag_queries)";
		} else {
			$qry = "SELECT * FROM $view WHERE (@tag_queries)";
		}
	}
	return $qry;
}

sub _run_profile_query {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $system = $self->{'system'};
	my $qry;
	my @errors;
	my $scheme_id   = BIGSdb::Utils::is_int( $q->param('scheme_id') ) ? $q->param('scheme_id') : 0;
	my $loci        = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
	if ( !defined $q->param('query') ) {
		my $scheme_view = $self->{'datastore'}->materialized_view_exists($scheme_id) ? "mv_scheme_$scheme_id" : "scheme_$scheme_id";
		$qry = "SELECT * FROM $scheme_view WHERE (";
		my $andor       = $q->param('c0');
		my $first_value = 1;
		foreach my $i ( 1 .. MAX_ROWS ) {
			if ( defined $q->param("t$i") && $q->param("t$i") ne '' ) {
				my $field = $q->param("s$i");
				my $is_locus;
				my $type;
				foreach (@$loci) {
					if ( $_ eq $field ) {
						$is_locus = 1;
						last;
					}
				}
				( my $cleaned = $field ) =~ s/'/_PRIME_/g;
				if ($is_locus) {
					$type = $self->{'datastore'}->get_locus_info($field)->{'allele_id_format'};
				} elsif ( $self->{'datastore'}->is_scheme_field( $scheme_id, $field ) ) {
					$type = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field )->{'type'};
				} elsif ( $field =~ /^date/ ) {
					$type = 'date';
				}
				my $operator = $q->param("y$i");
				my $text     = $q->param("t$i");
				$self->process_value( \$text );
				next
				  if !( $scheme_info->{'allow_missing_loci'} && $is_locus && $text eq 'N' && $operator ne '<' && $operator ne '>' )
				  && $self->check_format( { field => $field, text => $text, type => $type, operator => $operator }, \@errors );
				my $modifier = ( $i > 1 && !$first_value ) ? " $andor " : '';
				$first_value = 0;
				if ( $field =~ /(.*) \(id\)$/
					&& !BIGSdb::Utils::is_int($text) )
				{
					push @errors, "$field is an integer field.";
					next;
				}
				$qry .= $modifier;
				if ( any { $field =~ /(.*) \($_\)$/ } qw (id surname first_name affiliation) ) {
					$qry .= $self->search_users( $field, $operator, $text, $scheme_view );
				} else {
					my $equals =
					  $text eq 'null'
					  ? "$cleaned is null"
					  : ( $type eq 'text' ? "upper($cleaned) = upper('$text')" : "$cleaned = '$text'" );
					$equals .= " OR $cleaned = 'N'" if $is_locus && $scheme_info->{'allow_missing_loci'};
					given ($operator) {
						when ('NOT') { $qry .= $text eq 'null' ? "(not $equals)" : "((NOT $equals) OR $cleaned IS NULL)" }
						when ('contains')    { $qry .= "(upper($cleaned) LIKE upper('\%$text\%'))" }
						when ('starts with') { $qry .= "(upper($cleaned) LIKE upper('$text\%'))" }
						when ('ends with')   { $qry .= "(upper($cleaned) LIKE upper('\%$text'))" }
						when ('NOT contain') { $qry .= "(NOT upper($cleaned) LIKE upper('\%$text\%') OR $cleaned IS NULL)" }
						when ('=')           { $qry .= "($equals)" }
						default {
							$qry .= ( $type eq 'integer' ? "(to_number(textcat('0', $cleaned), text(99999999))" : "($cleaned" )
							  . " $operator '$text')"
						}
					}
				}
			}
		}
		$qry .= ')';
		my $primary_key =
		  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )->[0];
		if ( defined $q->param('publication_list') && $q->param('publication_list') ne '' ) {
			my $pmid = $q->param('publication_list');
			my $ids =
			  $self->{'datastore'}
			  ->run_list_query( "SELECT profile_id FROM profile_refs WHERE scheme_id=? AND pubmed_id=?", $scheme_id, $pmid );
			if ($pmid) {
				local $" = "','";
				if ( $qry !~ /WHERE \(\)\s*$/ ) {
					$qry .= " AND ($primary_key IN ('@$ids'))";
				} else {
					$qry = "SELECT * FROM $scheme_view WHERE ($primary_key IN ('@$ids'))";
				}
			}
		}
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		foreach (@$scheme_fields) {
			if ( defined $q->param("$_\_list") && $q->param("$_\_list") ne '' ) {
				my $value = $q->param("$_\_list");
				$value =~ s/'/\\'/g;
				if ( $qry !~ /WHERE \(\)\s*$/ ) {
					$qry .= " AND ($_ = '$value')";
				} else {
					$qry = "SELECT * FROM $scheme_view WHERE ($_ = '$value')";
				}
			}
		}
		my $order = $q->param('order') || $primary_key;
		my $dir = ( defined $q->param('direction') && $q->param('direction') eq 'descending' ) ? 'desc' : 'asc';
		my $pk_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
		my $profile_id_field = $pk_field_info->{'type'} eq 'integer' ? "lpad($primary_key,20,'0')" : $primary_key;
		if ( $self->{'datastore'}->is_locus($order) ) {
			my $locus_info = $self->{'datastore'}->get_locus_info($order);
			$order =~ s/'/_PRIME_/g;
			if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
				$order = "to_number(textcat('0', $order), text(99999999))";    #Handle arbitrary allele = 'N'
			}
		}
		$qry .= " ORDER BY" . ( $order ne $primary_key ? " $order $dir,$profile_id_field;" : " $profile_id_field $dir;" );
	} else {
		$qry = $q->param('query');
	}
	if (@errors) {
		local $" = '<br />';
		say "<div class=\"box\" id=\"statusbad\"><p>Problem with search criteria:</p>";
		say "<p>@errors</p></div>";
	} elsif ( $qry !~ /\(\)/ ) {
		my @hidden_attributes;
		push @hidden_attributes, 'c0', 'c1';
		foreach my $i ( 1 .. MAX_ROWS ) {
			push @hidden_attributes, "s$i", "t$i", "y$i", "ls$i", "ly$i", "lt$i";
		}
		foreach ( @{ $self->{'xmlHandler'}->get_field_list } ) {
			push @hidden_attributes, $_ . '_list';
		}
		push @hidden_attributes, qw (publication_list scheme_id no_js);
		$self->paged_display( 'profiles', $qry, '', \@hidden_attributes );
	} else {
		say "<div class=\"box\" id=\"statusbad\">Invalid search performed. Try to <a href=\"$self->{'system'}->{'script_name'}?db="
		  . "$self->{'instance'}&amp;page=browse&amp;scheme_id=$scheme_id\">browse all records</a>.</div>";
	}
	return;
}

sub is_valid_operator {
	my ( $self, $value ) = @_;
	my @operators = OPERATORS;
	return ( any { $value eq $_ } @operators ) ? 1 : 0;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	my $db_type = $self->{'system'}->{'dbtype'} eq 'isolates' ? 'Isolate' : 'Profile';
	return $self->{'curate'} ? "$db_type query/update - $desc" : "Search database - $desc";
}

sub search_users {
	my ( $self, $name, $operator, $text, $table ) = @_;
	my ( $field, $suffix ) = split / /, $name;
	$suffix =~ s/[\(\)\s]//g;
	my $qry         = "SELECT id FROM users WHERE ";
	my $equals      = $suffix ne 'id' ? "upper($suffix) = upper('$text')" : "$suffix = '$text'";
	my $contains    = $suffix ne 'id' ? "upper($suffix) LIKE upper('\%$text\%')" : "CAST($suffix AS text) LIKE ('\%$text\%')";
	my $starts_with = $suffix ne 'id' ? "upper($suffix) LIKE upper('$text\%')" : "CAST($suffix AS text) LIKE ('$text\%')";
	my $ends_with   = $suffix ne 'id' ? "upper($suffix) LIKE upper('\%$text')" : "CAST($suffix AS text) LIKE ('\%$text')";
	given ($operator) {
		when ('NOT')         { $qry .= "NOT $equals" }
		when ('contains')    { $qry .= $contains }
		when ('starts with') { $qry .= $starts_with }
		when ('ends with')   { $qry .= $ends_with }
		when ('NOT contain') { $qry .= "NOT $contains" }
		when ('=')           { $qry .= $equals }
		default              { $qry .= "$suffix $operator '$text'" }
	}
	my $ids = $self->{'datastore'}->run_list_query($qry);
	$ids = [-999] if !@$ids;    #Need to return an integer but not 0 since this is actually the setup user.
	local $" = "' OR $table.$field = '";
	return "($table.$field = '@$ids')";
}

sub check_format {

	#returns 1 if error
	my ( $self, $data, $error_ref ) = @_;
	my $error;
	if ( $data->{'text'} ne 'null' && defined $data->{'type'} ) {
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname( $data->{'field'} );
		if ( $data->{'type'} =~ /int/ ) {
			if ( !BIGSdb::Utils::is_int( $data->{'text'}, { do_not_check_range => 1 } ) ) {
				$error = ( $metafield // $data->{'field'} ) . " is an integer field.";
			} elsif ( $data->{'text'} > MAX_INT ) {
				$error = ( $metafield // $data->{'field'} ) . " is too big (largest allowed integer is " . MAX_INT . ').';
			}
		} elsif ( $data->{'type'} =~ /bool/ && !BIGSdb::Utils::is_bool( $data->{'text'} ) ) {
			$error = ( $metafield // $data->{'field'} ) . " is a boolean (true/false) field.";
		} elsif ( $data->{'type'} eq 'float' && !BIGSdb::Utils::is_float( $data->{'text'} ) ) {
			$error = ( $metafield // $data->{'field'} ) . " is a floating point number field.";
		} elsif (
			$data->{'type'} eq 'date' && (
				any {
					$data->{'operator'} eq $_;
				}
				( 'contains', 'NOT contain', 'starts with', 'ends with' )
			)
		  )
		{
			$error = "Searching a date field can not be done for the '$data->{'operator'}' operator.";
		} elsif ( $data->{'type'} eq 'date' && !BIGSdb::Utils::is_date( $data->{'text'} ) ) {
			$error = ( $metafield // $data->{'field'} ) . " is a date field - should be in yyyy-mm-dd format (or 'today' / 'yesterday').";
		}
	}
	if ( !$error && !$self->is_valid_operator( $data->{'operator'} ) ) {
		$error = "$data->{'operator'} is not a valid operator.";
	}
	push @$error_ref, $error if $error;
	return $error ? 1 : 0;
}

sub process_value {
	my ( $self, $value_ref ) = @_;
	$$value_ref =~ s/^\s*//;
	$$value_ref =~ s/\s*$//;
	$$value_ref =~ s/\\/\\\\/g;
	$$value_ref =~ s/'/\\'/g;
	return;
}
1;
