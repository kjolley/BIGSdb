#Written by Keith Jolley
#Copyright (c) 2010-2012, University of Oxford
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
use base qw(BIGSdb::Page);
use List::MoreUtils qw(any none);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant MAX_ROWS => 20;
use BIGSdb::Page qw(SEQ_FLAGS LOCUS_PATTERNS);

sub initiate {
	my ($self) = @_;
	if ( $self->{'cgi'}->param('no_header') ) {
		$self->{'type'} = 'no_header';
		return;
	}
	$self->{$_} = 1 foreach qw (field_help tooltips jQuery jQuery.coolfieldset);
	return;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { 'general' => 1, 'main_display' => 1, 'isolate_display' => 0, 'analysis' => 0, 'query_field' => 1 };
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $max_rows = MAX_ROWS;
	my $locus_collapse  = $self->_highest_entered_fields('loci') ? 'false' : 'true';
	my $tag_collapse    = $self->_highest_entered_fields('tags') ? 'false' : 'true';
	my $filter_collapse = $self->_filters_selected               ? 'false' : 'true';
	my $buffer          = << "END";
\$(function () {
	\$('a[rel=ajax]').click(function(){
  		\$(this).attr('href', function(){
    		return(this.href.replace(/(.*)/, "javascript:loadContent\('\$1\'\)"));
    	});
  	});
  	\$('#locus_fieldset').coolfieldset({speed:"fast", collapsed:$locus_collapse});
   	\$('#tag_fieldset').coolfieldset({speed:"fast", collapsed:$tag_collapse});
  	\$('#filter_fieldset').coolfieldset({speed:"fast", collapsed:$filter_collapse});
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
	my $scheme_id;
	my $scheme_info;
	if ( $q->param('no_header') ) {
		$self->_ajax_content;
		return;
	}
	if ( $system->{'dbtype'} eq 'sequences' ) {
		$scheme_id = $q->param('scheme_id');
		if ( !$scheme_id ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No scheme id passed.</p></div>\n";
			return;
		} elsif ( !BIGSdb::Utils::is_int($scheme_id) ) {
			print "<div class=\"box\" id=\"statusbad\">Scheme id must be an integer.</p></div>\n";
			return;
		} else {
			$scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
			if ( !$scheme_info ) {
				print "<div class=\"box\" id=\"statusbad\">Scheme does not exist.</p></div>\n";
				return;
			}
			if ( $self->{'curate'} ) {
				print "<h1>Query/update $scheme_info->{'description'} profiles</h1>\n";
			} else {
				print "<h1>Search $scheme_info->{'description'} profiles</h1>\n";
			}
		}
	} else {
		if ( $self->{'curate'} ) {
			print "<h1>Isolate query/update</h1>\n";
		} else {
			print "<h1>Search $system->{'description'} database</h1>\n";
		}
	}
	my $qry;
	if ( !defined $q->param('currentpage')
		|| $q->param('First') )
	{
		if ( !$q->param('no_js') ) {
			my $scheme_clause = $system->{'dbtype'} eq 'sequences' ? "&amp;scheme_id=$scheme_id" : '';
			print
"<noscript><div class=\"statusbad_no_resize\"><p>The dynamic customisation of this interface requires that you enable Javascript in your
		browser. Alternatively, you can use a <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query$scheme_clause&amp;no_js=1\">non-Javascript 
		version</a> that has 4 combinations of fields.</p></div></noscript>\n";
		}
		if ( $system->{'dbtype'} eq 'isolates' ) {
			$self->_print_isolate_query_interface;
		} else {
			$self->_print_profile_query_interface($scheme_id);
		}
	}
	if ( $q->param('submit') || defined $q->param('query') ) {
		if ( $system->{'dbtype'} eq 'isolates' ) {
			$self->_run_isolate_query;
		} else {
			$self->_run_profile_query($scheme_id);
		}
	} else {
		print "<p />\n";
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
	print $q->popup_menu( -name => "y$row", -values => [ "=", "contains", ">", "<", "NOT", "NOT contain" ] );
	print $q->textfield( -name => "t$row", -class => 'value_entry' );
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		if ( !$q->param('no_js') ) {
			my $page = $self->{'curate'} ? 'isolateQuery' : 'query';
			print
"<a id=\"add_fields\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;fields=provenance&amp;row=$next_row&amp;no_header=1\" rel=\"ajax\" class=\"button\">&nbsp;+&nbsp;</a>\n";
			print
" <a class=\"tooltip\" title=\"Search values - Empty field values can be searched using the term 'null'. <p /><h3>Number of fields</h3><p>Add more fields by clicking the '+' button.</p><h3>Query modifier</h3><p>Select 'AND' for the isolate query to match ALL search terms, 'OR' to match ANY of these terms.</p>\">&nbsp;<i>i</i>&nbsp;</a>";
		}
	}
	print "</span>\n";
	return;
}

sub _print_loci_fields {
	my ( $self, $row, $max_rows, $locus_list, $locus_labels ) = @_;
	unshift @$locus_list, '';
	my $q = $self->{'cgi'};
	print "<span style=\"white-space:nowrap\">\n";
	print $q->popup_menu( -name => "ls$row", -values => $locus_list, -labels => $locus_labels, -class => 'fieldlist' );
	print $q->popup_menu( -name => "ly$row", -values => [ "=", "contains", ">", "<", "NOT", "NOT contain" ] );
	print $q->textfield( -name => "lt$row", -class => 'value_entry' );
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		if ( !$q->param('no_js') ) {
			my $page = $self->{'curate'} ? 'isolateQuery' : 'query';
			print
"<a id=\"add_loci\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;fields=loci&amp;row=$next_row&amp;no_header=1\" rel=\"ajax\" class=\"button\">&nbsp;+&nbsp;</a>\n";
			print
" <a class=\"tooltip\" title=\"Search values - Empty field values can be searched using the term 'null'. <p /><h3>Number of fields</h3><p>Add more fields by clicking the '+' button.</p><h3>Query modifier</h3><p>Select 'AND' for the isolate query to match ALL search terms, 'OR' to match ANY of these terms.</p>\">&nbsp;<i>i</i>&nbsp;</a>";
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
	print $q->popup_menu( -name => "ts$row", -values => $locus_list, -labels => $locus_labels, -class => 'fieldlist' );
	print ' is ';
	my @values = qw(untagged tagged complete incomplete);
	push @values, "flagged: $_" foreach ( 'any', 'none', SEQ_FLAGS );
	unshift @values, '';
	print $q->popup_menu( -name => "tt$row", -values => \@values );

	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		if ( !$q->param('no_js') ) {
			my $page = $self->{'curate'} ? 'isolateQuery' : 'query';
			print
"<a id=\"add_tags\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;fields=tags&amp;row=$next_row&amp;no_header=1\" rel=\"ajax\" class=\"button\">&nbsp;+&nbsp;</a>\n";
			print
" <a class=\"tooltip\" title=\"Number of fields - Add more fields by clicking the '+' button.</p><h3>Query modifier</h3><p>Select 'AND' for the isolate query to match ALL search terms, 'OR' to match ANY of these terms.</p>\">&nbsp;<i>i</i>&nbsp;</a>";
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
	print "<div class=\"box\" id=\"queryform\"><div class=\"scrollable\">\n";
	print $q->startform;
	$q->param( 'table', $self->{'system'}->{'view'} );
	print $q->hidden($_) foreach qw (db page table no_js);
	print "<div style=\"white-space:nowrap\">\n";
	$self->_print_isolate_fields_fieldset;
	$self->_print_isolate_display_fieldset;
	print "<div style=\"clear:both\"></div>";
	$self->_print_isolate_locus_fieldset;
	$self->_print_isolate_tag_fieldset;
	$self->_print_isolate_filter_fieldset;
	my $page = $self->{'curate'} ? 'isolateQuery' : 'query';
	print
"<div style=\"clear:both\"><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page\" class=\"resetbutton\">Reset</a><span style=\"float:right\">";
	print $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
	print "</span></div>";
	print "</div>\n";
	print $q->end_form;
	print "</div>\n</div>\n";
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
		return $self->_print_isolate_filter_fieldset( { 'selected' => 1 } );
	}
}

sub _print_isolate_filter_fieldset {

	#option 'selected' will return '1' if any filter is selected
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $prefs = $self->{'prefs'};
	my $q     = $self->{'cgi'};
	my @filters;
	my $extended = $self->get_extended_attributes;
	foreach my $field ( @{ $self->{'xmlHandler'}->get_field_list } ) {
		my %thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
		my @dropdownlist;
		my %dropdownlabels;
		if ( $prefs->{'dropdownfields'}->{$field} ) {
			if (   $field eq 'sender'
				|| $field eq 'curator'
				|| ( $thisfield{'userfield'} && $thisfield{'userfield'} eq 'yes' ) )
			{
				push @filters, $self->get_user_filter( $field, $self->{'system'}->{'view'} );
				return 1 if $options->{'selected'} && $q->param("$field\_list");
			} else {
				if ( $thisfield{'optlist'} ) {
					@dropdownlist = $self->{'xmlHandler'}->get_field_option_list($field);
					$dropdownlabels{$_} = $_ foreach (@dropdownlist);
					if (   $thisfield{'required'}
						&& $thisfield{'required'} eq 'no' )
					{
						push @dropdownlist, '<blank>';
						$dropdownlabels{'<blank>'} = '<blank>';
					}
				} else {
					my $qry = "SELECT DISTINCT($field) FROM $self->{'system'}->{'view'} ORDER BY $field";
					my $sql = $self->{'db'}->prepare($qry);
					eval { $sql->execute };
					$logger->error($@) if $@;
					while ( my ($value) = $sql->fetchrow_array ) {
						push @dropdownlist, $value;
					}
				}
				my $a_or_an = substr( $field, 0, 1 ) =~ /[aeiouAEIOU]/ ? 'an' : 'a';
				push @filters,
				  $self->get_filter(
					$field,
					\@dropdownlist,
					{
						'labels' => \%dropdownlabels,
						'tooltip' =>
"$field filter - Select $a_or_an $field to filter your search to only those isolates that match the selected $field."
					}
				  );
				return 1 if $options->{'selected'} && $q->param("$field\_list");
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
							'tooltip' =>
"$field\..$extended_attribute filter - Select $a_or_an $extended_attribute to filter your search to only those isolates that match the selected $field."
						}
					  );
					return 1 if $options->{'selected'} && $q->param("$field\..$extended_attribute\_list");
				}
			}
		}
	}
	if ( $self->{'config'}->{'refdb'} ) {
		my $pmid = $self->{'datastore'}->run_list_query("SELECT DISTINCT(pubmed_id) FROM refs");
		my $buffer;
		if (@$pmid) {
			my $labels = $self->{'datastore'}->get_citation_hash($pmid);
			my @values = sort { $labels->{$a} cmp $labels->{$b} } keys %$labels;
			unshift @values, 'not linked to any publication';
			unshift @values, 'linked to any publication';
			push @filters,
			  $self->get_filter(
				'publication',
				\@values,
				{
					'labels' => $labels,
					'text'   => 'Publication',
					'tooltip' =>
"publication filter - Select a publication to filter your search to only those isolates that match the selected publication."
				}
			  );
			return 1 if $options->{'selected'} && $q->param('publication_list');
		}
	}
	my $buffer = $self->get_project_filter( { 'any' => 1 } );
	push @filters, $buffer if $buffer;
	return 1 if $options->{'selected'} && $q->param('project_list');
	my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes ORDER BY display_order,id");
	foreach (@$schemes) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info($_);
		my $field       = "scheme_$_\_profile_status";
		if ( $prefs->{'dropdownfields'}->{$field} ) {
			push @filters,
			  $self->get_filter(
				$field,
				[ 'complete', 'incomplete', 'partial', 'started', 'not started' ],
				{
					'text' => "$scheme_info->{'description'} profiles",
					'tooltip' =>
"$scheme_info->{'description'} profile completion filter - Select whether the isolates should have complete, partial, or unstarted profiles."
				}
			  );
			return 1 if $options->{'selected'} && $q->param("$field\_list");
		}
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($_);
		foreach my $field (@$scheme_fields) {
			if ( $self->{'prefs'}->{"dropdown\_scheme_fields"}->{$_}->{$field} ) {
				my $values = $self->{'datastore'}->get_scheme($_)->get_distinct_fields($field);
				my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $_, $field );
				if ( $scheme_field_info->{'type'} eq 'integer' ) {
					@$values = sort { $a <=> $b } @$values;
				}
				my $a_or_an = substr( $field, 0, 1 ) =~ /[aeiouAEIOU]/ ? 'an' : 'a';
				push @filters,
				  $self->get_filter(
					"scheme\_$_\_$field",
					$values,
					{
						'text' => "$field ($scheme_info->{'description'})",
						'tooltip' =>
"$field ($scheme_info->{'description'}) filter - Select $a_or_an $field to filter your search to only those isolates that match the selected $field."
					}
				  ) if @$values;
				return 1 if $options->{'selected'} && $q->param("scheme\_$_\_$field\_list");
			}
		}
	}
	my $linked_seqs = $self->{'datastore'}->run_simple_query("SELECT EXISTS(SELECT id FROM sequence_bin)")->[0];
	if ( $linked_seqs ) {
		push @filters,
		  $self->get_filter(
			'linked_sequences',
			[ 'with linked sequences', 'without linked sequences' ],
			{
				'text'    => 'Linked sequence',
				'tooltip' => 'linked sequence filter - Filter by whether sequences have been linked with the isolate record.'
			}
		  );
		return 1 if $options->{'selected'} && $q->param("linked_sequences_list");
	}
	return 0 if $options->{'selected'};
	if (@filters) {
		print "<fieldset id=\"filter_fieldset\" style=\"float:left\" class=\"coolfieldset\"><legend>Filters</legend>\n";
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
		print "<fieldset id=\"locus_fieldset\" style=\"float:left\" class=\"coolfieldset\">\n";
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
		print "<fieldset id=\"tag_fieldset\" style=\"float:left\" class=\"coolfieldset\">\n";
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
	my ( $order_list, $labels ) = $self->get_field_selection_list( { 'isolate_fields' => 1, 'loci' => 1, 'scheme_fields' => 1 } );
	print "<ul>\n<li><span style=\"white-space:nowrap\">\n<label for=\"order\" class=\"display\">Order by: </label>\n";
	print $q->popup_menu( -name => 'order', -id => 'order', -values => $order_list, -labels => $labels );
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
		$logger->error("No primary key - this should not have been called");
	}
	push @selectitems, $primary_key;
	push @orderitems,  $primary_key;
	foreach (@$loci) {
		my $locus_info = $self->{'datastore'}->get_locus_info($_);
		$cleaned{$_} = $_;
		$cleaned{$_} .= " ($locus_info->{'common_name'})" if $locus_info->{'common_name'};
		push @selectitems, $_;
		push @orderitems,  $_;
	}
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach (@$scheme_fields) {
		next if $_ eq $primary_key;
		( $cleaned{$_} = $_ ) =~ tr/_/ /;
		push @selectitems, $_;
		push @orderitems,  $_;
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
	print $q->popup_menu( -name => "y$row", -values => [ "=", "contains", ">", "<", "NOT", "NOT contain" ] );
	print $q->textfield( -name => "t$row", -class => 'value_entry' );
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		if ( !$q->param('no_js') ) {
			my $page = $self->{'curate'} ? 'profileQuery' : 'query';
			print
"<a id=\"add_scheme_fields\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;fields=scheme&amp;scheme_id=$scheme_id&amp;row=$next_row&amp;no_header=1\" rel=\"ajax\" class=\"button\">&nbsp;+&nbsp;</a>\n";
			print
" <a class=\"tooltip\" title=\"Search values - Empty field values can be searched using the term 'null'. <p /><h3>Number of fields</h3><p>Add more fields by clicking the '+' button.</p><h3>Query modifier</h3><p>Select 'AND' for the isolate query to match ALL search terms, 'OR' to match ANY of these terms.</p>\">&nbsp;<i>i</i>&nbsp;</a>";
		}
	}
	print "</span>\n";
	return;
}

sub _print_profile_query_interface {
	my ( $self, $scheme_id ) = @_;
	my $system = $self->{'system'};
	my $prefs  = $self->{'prefs'};
	my $q      = $self->{'cgi'};
	my ( $primary_key, $selectitems, $orderitems, $cleaned ) = $self->_get_profile_select_items($scheme_id);
	if ( !$primary_key ) {
		print
"<div class=\"box\" id=\"statusbad\"><p>No primary key field has been set for this scheme.  Profile querying can not be done until this has been set.</p></div>\n";
		return;
	}
	print "<div class=\"box\" id=\"queryform\"><div class=\"scrollable\">\n";
	print $q->startform;
	print $q->hidden($_) foreach qw (db page scheme_id no_js);
	my $scheme_field_count = $q->param('no_js') ? 4 : ( $self->_highest_entered_fields('scheme') || 1 );
	my $scheme_field_heading = $scheme_field_count == 1 ? 'none' : 'inline';
	print "<div style=\"white-space:nowrap\">";
	print "<fieldset style=\"float:left\">\n<legend>Locus/scheme fields</legend>\n";
	print "<span id=\"scheme_field_heading\" style=\"display:$scheme_field_heading\"><label for=\"c0\">Combine searches with: </label>\n";
	print $q->popup_menu( -name => 'c0', -id => 'c0', -values => [ "AND", "OR" ] );
	print "</span><ul id=\"scheme_fields\">\n";

	foreach my $i ( 1 .. $scheme_field_count ) {
		print "<li>";
		$self->_print_scheme_fields( $i, $scheme_field_count, $scheme_id, $selectitems, $cleaned );
		print "</li>\n";
	}
	print "</ul>\n";
	print "</fieldset>\n";
	my @filters;
	if ( $self->{'config'}->{'refdb'} ) {
		my $pmid = $self->{'datastore'}->run_list_query( "SELECT DISTINCT(pubmed_id) FROM profile_refs WHERE scheme_id=?", $scheme_id );
		if (@$pmid) {
			my $labels = $self->{'datastore'}->get_citation_hash($pmid);
			my @values = sort { $labels->{$a} cmp $labels->{$b} } keys %$labels;
			push @filters,
			  $self->get_filter(
				'publication',
				\@values,
				{
					'labels' => $labels,
					'text'   => 'Publication',
					'tooltip' =>
"publication filter - Select a publication to filter your search to only those isolates that match the selected publication."
				}
			  );
		}
	}
	my $scheme_info   = $self->{'datastore'}->get_scheme_info($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach my $field (@$scheme_fields) {
		if ( $self->{'prefs'}->{"dropdown\_scheme_fields"}->{$scheme_id}->{$field} ) {
			my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
			my $value_clause = $scheme_field_info->{'type'} eq 'integer' ? 'CAST(value AS integer)' : 'value';
			my $values =
			  $self->{'datastore'}->run_list_query(
				"SELECT DISTINCT $value_clause FROM profile_fields WHERE scheme_id=? AND scheme_field=? ORDER BY $value_clause",
				$scheme_id, $field );
			my $a_or_an = substr( $field, 0, 1 ) =~ /[aeiouAEIOU]/ ? 'an' : 'a';
			push @filters,
			  $self->get_filter(
				$field, $values,
				{
					'text' => "$field ($scheme_info->{'description'})",
					'tooltip' =>
"$field ($scheme_info->{'description'}) filter - Select $a_or_an $field to filter your search to only those profiles that match the selected $field."
				}
			  );
		}
	}
	print "<fieldset id=\"display_fieldset\" style=\"float:left\"><legend>Display/sort options</legend>\n";
	print "<ul>\n<li><span style=\"white-space:nowrap\">\n<label for=\"order\" class=\"display\">Order by: </label>\n";
	print $q->popup_menu( -name => 'order', -id => 'order', -values => $orderitems, -labels => $cleaned );
	print $q->popup_menu( -name => 'direction', -values => [ 'ascending', 'descending' ], -default => 'ascending' );
	print "</span></li>\n<li>\n";
	print $self->get_number_records_control;
	print "</li>\n</ul>\n</fieldset>\n";
	print "</div>\n<div style=\"clear:both\"></div>";

	if (@filters) {
		print "<fieldset style=\"float:left\">\n";
		print "<legend>Filter query by</legend>\n";
		print "<ul>\n";
		foreach (@filters) {
			print "<li><span style=\"white-space:nowrap\">$_</span></li>";
		}
		print "</ul>\n</fieldset>";
	}
	my $page = $self->{'curate'} ? 'profileQuery' : 'query';
	print
"<div style=\"clear:both\"><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;scheme_id=$scheme_id\" class=\"resetbutton\">Reset</a><span style=\"float:right\">";
	print $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
	print "</span></div>\n";
	print $q->end_form;
	print "</div></div>\n";
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
		foreach (@$schemes) {
			push @hidden_attributes, "scheme_$_\_profile_status_list";
		}
		my $view = $self->{'system'}->{'view'};
		$qry =~ s/ datestamp/ $view\.datestamp/g;     #datestamp exists in other tables and can be ambiguous on complex queries
		$qry =~ s/\(datestamp/\($view\.datestamp/g;
		$self->paged_display( $self->{'system'}->{'view'}, $qry, '', \@hidden_attributes );
		print "<p />\n";
	} else {
		print
"<div class=\"box\" id=\"statusbad\">Invalid search performed.  Try to <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=browse\">browse all records</a>.</div>\n";
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
	my $view = $self->{'system'}->{'view'};
	my $buffer   = "$data->{'modifier'} (";
	if ( $operator eq 'NOT' ) {
		foreach (@$groupedfields) {
			my %thisfield = $self->{'xmlHandler'}->get_field_attributes($_);
			if ( $text eq 'null' ) {
				$buffer .= ' OR ' if $_ ne $groupedfields->[0];
				$buffer .= "($view.$_ IS NOT NULL)";
			} else {
				$buffer .= ' AND ' if $_ ne $groupedfields->[0];
				if ( $thisfield{'type'} ne 'text' ) {
					$buffer .= "(NOT CAST($view.$_ AS text) = E'$text' OR $view.$_ IS NULL)";
				} else {
					$buffer .= "(NOT upper($view.$_) = upper(E'$text') OR $view.$_ IS NULL)";
				}
			}
		}
	} elsif ( $operator eq "contains" ) {
		foreach (@$groupedfields) {
			my %thisfield = $self->{'xmlHandler'}->get_field_attributes($_);
			$buffer .= ' OR ' if $_ ne $groupedfields->[0];
			if ( $thisfield{'type'} ne 'text' ) {
				$buffer .= "CAST($view.$_ AS text) LIKE E'\%$text\%'";
			} else {
				$buffer .= "upper($view.$_) LIKE upper(E'\%$text\%')";
			}
		}
	} elsif ( $operator eq "NOT contain" ) {
		foreach (@$groupedfields) {
			my %thisfield = $self->{'xmlHandler'}->get_field_attributes($_);
			$buffer .= ' AND ' if $_ ne $groupedfields->[0];
			if ( $thisfield{'type'} ne 'text' ) {
				$buffer .= "(NOT CAST($view.$_ AS text) LIKE E'\%$text\%' OR $view.$_ IS NULL)";
			} else {
				$buffer .= "(NOT upper($view.$_) LIKE upper(E'\%$text\%') OR $view.$_ IS NULL)";
			}
		}
	} elsif ( $operator eq '=' ) {
		foreach (@$groupedfields) {
			my %thisfield = $self->{'xmlHandler'}->get_field_attributes($_);
			$buffer .= ' OR ' if $_ ne $groupedfields->[0];
			if ( $thisfield{'type'} ne 'text' ) {
				$buffer .= $text eq 'null' ? "$view.$_ IS NULL" : "CAST($view.$_ AS text) = E'$text'";
			} else {
				$buffer .= $text eq 'null' ? "$view.$_ IS NULL" : "upper($view.$_) = upper(E'$text')";
			}
		}
	} else {
		foreach (@$groupedfields) {
			my %thisfield = $self->{'xmlHandler'}->get_field_attributes($_);
			return
			  if $self->_check_format( { field => $_, text => $text, type => $thisfield{'type'}, operator => $data->{'operator'} },
				$errors_ref );
			$buffer .= ' OR ' if $_ ne $groupedfields->[0];
			%thisfield = $self->{'xmlHandler'}->get_field_attributes($_);
			if ( $thisfield{'type'} ne 'text' ) {
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
			my %thisfield     = $self->{'xmlHandler'}->get_field_attributes($field);
			my $extended_isolate_field;
			if ( $field =~ /^e_(.*)\|\|(.*)/ ) {
				$extended_isolate_field = $1;
				$field                  = $2;
				my $att_info =
				  $self->{'datastore'}
				  ->run_simple_query_hashref( "SELECT * FROM isolate_field_extended_attributes WHERE isolate_field=? AND attribute=?",
					$extended_isolate_field, $field );
				$thisfield{'type'} = $att_info->{'value_format'};
				$thisfield{'type'} = 'int' if $thisfield{'type'} eq 'integer';
			}
			my $operator = $q->param("y$i");
			my $text     = $q->param("t$i");
			$self->process_value( \$text );
			next
			  if $self->_check_format( { field => $field, text => $text, type => lc( $thisfield{'type'} ), operator => $operator },
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
				$qry .= $modifier . $self->search_users( $field, $operator, $text, $self->{'system'}->{'view'} );
			} else {
				if (@groupedfields) {
					$qry .=
					  $self->_grouped_field_query( \@groupedfields, { text => $text, operator => $operator, modifier => $modifier },
						$errors_ref );
					next;
				}
				$field = $self->{'system'}->{'view'} . '.' . $field if !$extended_isolate_field;
				my $labelfield = $self->{'system'}->{'view'} . '.' . $self->{'system'}->{'labelfield'};
				
				if ( $operator eq 'NOT' ) {
					if ($extended_isolate_field) {
						$qry .= $modifier
						  . (
							( $text eq 'null' )
							? "$extended_isolate_field IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$extended_isolate_field' AND attribute='$field')"
							: "$extended_isolate_field NOT IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$extended_isolate_field' AND attribute='$field' AND upper(value)=upper(E'$text'))"
						  );
					} elsif ( $field eq $labelfield ) {
						$qry .= $modifier
						  . "(NOT upper($field) = upper(E'$text') AND id NOT IN (SELECT isolate_id FROM isolate_aliases WHERE upper(alias) = upper(E'$text')))";
					} else {
						if ( $thisfield{'type'} eq 'int' || $thisfield{'type'} eq 'date' ) {
							$qry .=
							  $modifier . ( ( $text eq 'null' ) ? "$field is not null" : "NOT ($field = E'$text' OR $field IS NULL)" );
						} else {
							$qry .= $modifier
							  . ( ( $text eq 'null' ) ? "$field is not null" : "(NOT upper($field) = upper(E'$text') OR $field IS NULL)" );
						}
					}
				} elsif ( $operator eq "contains" ) {
					if ($extended_isolate_field) {
						$qry .= $modifier
						  . "$extended_isolate_field IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$extended_isolate_field' AND attribute='$field' AND upper(value) LIKE upper(E'\%$text\%'))";
					} elsif ( $field eq $labelfield ) {
						$qry .= $modifier
						  . "(upper($field) LIKE upper('\%$text\%') OR $view.id IN (SELECT isolate_id FROM isolate_aliases WHERE upper(alias) LIKE upper(E'\%$text\%')))";
					} else {
						if ( $thisfield{'type'} eq 'int' ) {
							$qry .= $modifier . "CAST($field AS text) LIKE E'\%$text\%'";
						} else {
							$qry .= $modifier . "upper($field) LIKE upper(E'\%$text\%')";
						}
					}
				} elsif ( $operator eq "NOT contain" ) {
					if ($extended_isolate_field) {
						$qry .= $modifier
						  . "$extended_isolate_field NOT IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$extended_isolate_field' AND attribute='$field' AND upper(value) LIKE upper(E'\%$text\%'))";
					} elsif ( $field eq $labelfield ) {
						$qry .= $modifier
						  . "(NOT upper($field) LIKE upper(E'\%$text\%') AND id NOT IN (SELECT isolate_id FROM isolate_aliases WHERE upper(alias) LIKE upper(E'\%$text\%')))";
					} else {
						if ( $thisfield{'type'} ne 'text' ) {
							$qry .= $modifier . "(NOT CAST($field AS text) LIKE E'\%$text\%' OR $field IS NULL)";
						} else {
							$qry .= $modifier . "(NOT upper($field) LIKE upper(E'\%$text\%') OR $field IS NULL)";
						}
					}
				} elsif ( $operator eq '=' ) {
					if ($extended_isolate_field) {
						$qry .= $modifier
						  . (
							( $text eq 'null' )
							? "$extended_isolate_field NOT IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$extended_isolate_field' AND attribute='$field')"
							: "$extended_isolate_field IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$extended_isolate_field' AND attribute='$field' AND upper(value) = upper(E'$text'))"
						  );
					} elsif ( $field eq $labelfield ) {
						$qry .= $modifier
						  . "(upper($field) = upper(E'$text') OR $view.id IN (SELECT isolate_id FROM isolate_aliases WHERE upper(alias) = upper(E'$text')))";
					} elsif ( lc( $thisfield{'type'} ) eq 'text' ) {
						$qry .= $modifier . ( $text eq 'null' ? "$field is null" : "upper($field) = upper(E'$text')" );
					} else {
						$qry .= $modifier . ( $text eq 'null' ? "$field is null" : "$field = E'$text'" );
					}
				} else {
					if ($extended_isolate_field) {
						$qry .= $modifier
						  . "$extended_isolate_field IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$extended_isolate_field' AND attribute='$field' AND value $operator E'$text')";
					} elsif ( $field eq $labelfield ) {
						$qry .= $modifier
						  . "($field $operator '$text' OR $view.id IN (SELECT isolate_id FROM isolate_aliases WHERE alias $operator E'$text'))";
					} else {
						if ( $text eq 'null' ) {
							push @$errors_ref, "$operator is not a valid operator for comparing null values.";
							next;
						}
						$qry .= $modifier . "$field $operator E'$text'";
					}
				}
			}
		}
	}
	$qry .= ')';
	return $qry;
}

sub _modify_isolate_query_for_filters {
	my ( $self, $qry, $extended ) = @_;

	#extended: extended attributes hashref;
	my $q    = $self->{'cgi'};
	my $view = $self->{'system'}->{'view'};
	foreach ( @{ $self->{'xmlHandler'}->get_field_list() } ) {
		if ( defined $q->param("$_\_list") && $q->param("$_\_list") ne '' ) {
			my $value = $q->param("$_\_list");
			if ( $qry !~ /WHERE \(\)\s*$/ ) {
				$qry .= " AND ";
			} else {
				$qry = "SELECT * FROM $view WHERE ";
			}
			$qry .= ( ( $value eq '<blank>' || $value eq 'null' ) ? "$_ is null" : "$_ = '$value'" );
		}
		my $extatt = $extended->{$_};
		if ( ref $extatt eq 'ARRAY' ) {
			foreach my $extended_attribute (@$extatt) {
				if ( defined $q->param("$_\..$extended_attribute\_list") && $q->param("$_\..$extended_attribute\_list") ne '' ) {
					my $value = $q->param("$_\..$extended_attribute\_list");
					$value =~ s/'/\\'/g;
					if ( $qry !~ /WHERE \(\)\s*$/ ) {
						$qry .=
" AND ($_ IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$_' AND attribute='$extended_attribute' AND value='$value'))";
					} else {
						$qry =
"SELECT * FROM $view WHERE ($_ IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$_' AND attribute='$extended_attribute' AND value='$value'))";
					}
				}
			}
		}
	}
	if ( defined $q->param('publication_list') && $q->param('publication_list') ne '' ) {
		my $pmid = $q->param('publication_list');
		my $ref_qry;
		if ( $pmid eq 'linked to any publication' ) {
			$ref_qry = "$view.id IN (SELECT isolate_id FROM refs)";
		} elsif ( $pmid eq 'not linked to any publication' ) {
			$ref_qry = "$view.id NOT IN (SELECT isolate_id FROM refs)";
		} elsif ( BIGSdb::Utils::is_int($pmid) ) {
			$ref_qry = "$view.id IN (SELECT isolate_id FROM refs WHERE pubmed_id=$pmid)";
		} else {
			undef $pmid;
		}
		if ($pmid) {
			if ( $qry !~ /WHERE \(\)\s*$/ ) {
				$qry .= " AND ($ref_qry)";
			} else {
				$qry = "SELECT * FROM $view WHERE ($ref_qry)";
			}
		}
	}
	if ( defined $q->param('project_list') && $q->param('project_list') ne '' ) {
		my $project_id = $q->param('project_list');
		my $project_qry;
		if ( $project_id eq 'belonging to any project' ) {
			$project_qry = "$view.id IN (SELECT isolate_id FROM project_members)";
		} elsif ( $project_id eq 'not belonging to any project' ) {
			$project_qry = "$view.id NOT IN (SELECT isolate_id FROM project_members)";
		} elsif ( BIGSdb::Utils::is_int($project_id) ) {
			$project_qry = "$view.id IN (SELECT isolate_id FROM project_members WHERE project_id='$project_id')";
		} else {
			undef $project_id;
		}
		if ($project_id) {
			if ( $qry !~ /WHERE \(\)\s*$/ ) {
				$qry .= " AND ($project_qry)";
			} else {
				$qry = "SELECT * FROM $view WHERE ($project_qry)";
			}
		}
	}
	if ( $q->param('linked_sequences_list') ) {
		my $not = '';
		if ( $q->param('linked_sequences_list') =~ /without/ ) {
			$not = ' NOT';
		}
		if ( $qry !~ /WHERE \(\)\s*$/ ) {
			$qry .= " AND (id$not IN (SELECT isolate_id FROM sequence_bin))";
		} else {
			$qry = "SELECT * FROM $view WHERE ($view.id$not IN (SELECT isolate_id FROM sequence_bin))";
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
					$allele_clause .= "(locus=E'$locus' AND allele_id IS NOT NULL)";
					$first = 0;
				}
				my $param = $q->param("scheme_$scheme_id\_profile_status_list");
				my $clause;
				if ( $param eq 'complete' ) {
					$clause =
"($view.id IN (SELECT isolate_id FROM allele_designations WHERE $allele_clause GROUP BY isolate_id HAVING COUNT(isolate_id)= "
					  . scalar @$scheme_loci . '))';
				} elsif ( $param eq 'partial' ) {
					$clause =
"($view.id IN (SELECT isolate_id FROM allele_designations WHERE $allele_clause GROUP BY isolate_id HAVING COUNT(isolate_id)< "
					  . scalar @$scheme_loci . '))';
				} elsif ( $param eq 'started' ) {
					$clause =
"($view.id IN (SELECT isolate_id FROM allele_designations WHERE $allele_clause GROUP BY isolate_id HAVING COUNT(isolate_id)>0))";
				} elsif ( $param eq 'incomplete' ) {
					$clause =
"($view.id IN (SELECT isolate_id FROM allele_designations WHERE $allele_clause GROUP BY isolate_id HAVING COUNT(isolate_id)< "
					  . scalar @$scheme_loci
					  . ") OR id NOT IN (SELECT isolate_id FROM allele_designations WHERE $allele_clause GROUP BY isolate_id )) ";
				} else {
					$clause = "(id NOT IN (SELECT isolate_id FROM allele_designations WHERE $allele_clause GROUP BY isolate_id ))";
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
				my $value = $q->param("scheme_$scheme_id\_$field\_list");
				$value =~ s/'/\\'/g;
				my $clause;
				my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
				$field = "scheme_$scheme_id\.$field";
				my $scheme_loci  = $self->{'datastore'}->get_scheme_loci($scheme_id);
				my $joined_table = "SELECT $view.id FROM $view";
				foreach (@$scheme_loci) {
					$joined_table .= " left join allele_designations AS $_ on $_.isolate_id = $self->{'system'}->{'view'}.id";
				}
				$joined_table .= " left join temp_scheme_$scheme_id AS scheme_$scheme_id ON ";
				my @temp;
				foreach (@$scheme_loci) {
					my $locus_info = $self->{'datastore'}->get_locus_info($_);
					if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
						push @temp, " CAST($_.allele_id AS int)=scheme_$scheme_id\.$_";
					} else {
						push @temp, " $_.allele_id=scheme_$scheme_id\.$_";
					}
				}
				local $" = ' AND ';
				$joined_table .= " @temp WHERE";
				undef @temp;
				foreach (@$scheme_loci) {
					push @temp, "$_.locus='$_'";
				}
				$joined_table .= " @temp";
				if ( $scheme_field_info->{'type'} eq 'integer' ) {
					$clause = "($view.id IN ($joined_table AND CAST($field AS int) = '$value'))";
				} else {
					$clause = "($view.id IN ($joined_table AND $field = '$value'))";
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

sub _modify_isolate_query_for_designations {
	my ( $self, $qry, $errors_ref ) = @_;
	my $q    = $self->{'cgi'};
	my $view = $self->{'system'}->{'view'};
	my ( %lqry, @lqry_blank, %combo );
	my @locus_patterns = LOCUS_PATTERNS;
	my $andor = defined $q->param('c1') && $q->param('c1') eq 'AND' ? ' AND ' : ' OR ';
	foreach my $i ( 1 .. MAX_ROWS ) {
		if ( defined $q->param("lt$i") && $q->param("lt$i") ne '' ) {
			if ( $q->param("ls$i") ~~ @locus_patterns ) {
				my $locus      = $1;
				my $locus_info = $self->{'datastore'}->get_locus_info($locus);
				$locus =~ s/'/\\'/g;
				my $operator = $q->param("ly$i");
				my $text     = $q->param("lt$i");
				next if $combo{"$locus\_$operator\_$text"};    #prevent duplicates
				$combo{"$locus\_$operator\_$text"} = 1;
				$self->process_value(\$text);
				if (   $text ne 'null'
					&& ( $locus_info->{'allele_id_format'} eq 'integer' )
					&& !BIGSdb::Utils::is_int($text) )
				{
					push @$errors_ref, "$locus is an integer field.";
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
				$self->process_value(\$text);
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
				my $scheme_loci  = $self->{'datastore'}->get_scheme_loci($scheme_id);
				my $joined_table = "SELECT $view.id FROM $view";
				foreach (@$scheme_loci) {
					$joined_table .= " left join allele_designations AS $_ on $_.isolate_id = $self->{'system'}->{'view'}.id";
				}
				$joined_table .= " left join temp_scheme_$scheme_id AS scheme_$scheme_id ON ";
				my @temp;
				foreach (@$scheme_loci) {
					my $locus_info = $self->{'datastore'}->get_locus_info($_);
					if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
						push @temp, " CAST($_.allele_id AS int)=scheme_$scheme_id\.$_";
					} else {
						push @temp, " $_.allele_id=scheme_$scheme_id\.$_";
					}
				}
				local $" = ' AND ';
				$joined_table .= " @temp WHERE";
				undef @temp;
				foreach (@$scheme_loci) {
					push @temp, "$_.locus='$_'";
				}
				$joined_table .= " @temp";
				if ( $operator eq 'NOT' ) {
					push @sqry, ( $text eq 'null' )
					  ? "($view.id NOT IN ($joined_table AND $field is null))"
					  : "($view.id NOT IN ($joined_table AND $field='$text'))";
				} elsif ( $operator eq "contains" ) {
					push @sqry,
					  $scheme_field_info->{'type'} eq 'integer'
					  ? "($view.id IN ($joined_table AND CAST($field AS text) ~* '$text'))"
					  : "($view.id IN ($joined_table AND $field ~* '$text'))";
				} elsif ( $operator eq "NOT contain" ) {
					push @sqry,
					  $scheme_field_info->{'type'} eq 'integer'
					  ? "($view.id IN ($joined_table AND CAST($field AS text) !~* '$text'))"
					  : "($view.id IN ($joined_table AND $field !~* '$text'))";
				} elsif ( $operator eq '=' ) {
					if ( $text eq 'null' ) {
						push @lqry_blank, "($view.id IN ($joined_table AND $field is null))";
					} else {
						push @sqry,
						  $scheme_field_info->{'type'} eq 'text'
						  ? "($view.id IN ($joined_table AND upper($field)=upper('$text')))"
						  : "($view.id IN ($joined_table AND $field='$text'))";
					}
				} else {
					if ( $scheme_field_info->{'type'} eq 'integer' ) {
						push @sqry, "($view.id IN ($joined_table AND CAST($field AS int) $operator '$text'))";
					} else {
						push @sqry, "($view.id IN ($joined_table AND $field $operator '$text'))";
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
		my $lqry =
"$view.id IN (select distinct($view.id) FROM $view LEFT JOIN allele_designations ON $view.id=allele_designations.isolate_id WHERE @lqry $modify)";
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
			$qry .= " $modify $brace(@lqry_blank)";
		}
	}
	if (@sqry) {
		my $andor = $q->param('c1') || '';
		local $" = " $andor ";
		my $sqry = "@sqry";
		if ( $qry =~ /\(\)$/ ) {
			$qry = "SELECT * FROM $view WHERE $sqry";
		} else {
			$qry .= " $andor $sqry";
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
	my @locus_patterns = LOCUS_PATTERNS;
	foreach my $i ( 1 .. MAX_ROWS ) {
		if ( defined $q->param("ts$i") && $q->param("ts$i") ne '' && defined $q->param("tt$i") && $q->param("tt$i") ne '' ) {
			my $action = $q->param("tt$i");
			my $locus;
			if ( $q->param("ts$i") ne 'any locus' ) {
				if ( $q->param("ts$i") ~~ @locus_patterns ) {
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
			} elsif ( $action =~ /^flagged: ([\w\s]+)$/ ) {
				my $flag              = $1;
				my $flag_joined_table = "sequence_flags LEFT JOIN sequence_bin ON sequence_flags.seqbin_id = sequence_bin.id";
				if ( $flag eq 'any' ) {
					$temp_qry = "$view.id IN (SELECT isolate_id FROM $flag_joined_table WHERE $locus_clause)";
				} elsif ( $flag eq 'none' ) {
					$temp_qry =
"$view.id IN (SELECT isolate_id FROM $seq_joined_table WHERE $locus_clause) AND id NOT IN (SELECT isolate_id FROM $flag_joined_table WHERE $locus_clause)";
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
	my ( $self, $scheme_id ) = @_;
	my $q      = $self->{'cgi'};
	my $system = $self->{'system'};
	my $qry;
	my @errors;
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	if ( !defined $q->param('query') ) {
		$qry = "SELECT * FROM scheme_$scheme_id WHERE (";
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
				next if $self->_check_format( { field => $field, text => $text, type => $type, operator => $operator }, \@errors );
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
					$qry .= $self->search_users( $field, $operator, $text, "scheme\_$scheme_id" );
				} else {
					my $equals =
					  $text eq 'null'
					  ? "$cleaned is null"
					  : ( $type eq 'text' ? "upper($cleaned) = upper('$text')" : "$cleaned = '$text'" );
					given ($operator) {
						when ('NOT') { $qry .= $text eq 'null' ? "(not $equals)" : "((NOT $equals) OR $cleaned IS NULL)" }
						when ('contains')    { $qry .= "(upper($cleaned) LIKE upper('\%$text\%'))" }
						when ('NOT contain') { $qry .= "(NOT upper($cleaned) LIKE upper('\%$text\%') OR $cleaned IS NULL)" }
						when ('=')           { $qry .= "($equals)" }
						default { $qry .= ( $type eq 'integer' ? "(CAST($cleaned AS int)" : "($cleaned" ) . " $operator '$text')" }
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
					$qry = "SELECT * FROM scheme_$scheme_id WHERE ($primary_key IN ('@$ids'))";
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
					$qry = "SELECT * FROM scheme_$scheme_id WHERE ($_ = '$value')";
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
				$order = "CAST($order AS int)";
			}
		}
		$qry .= " ORDER BY" . ( $order ne $primary_key ? " $order $dir,$profile_id_field;" : " $profile_id_field $dir;" );
	} else {
		$qry = $q->param('query');
	}
	if (@errors) {
		local $" = '<br />';
		print "<div class=\"box\" id=\"statusbad\"><p>Problem with search criteria:</p>\n";
		print "<p>@errors</p></div>\n";
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
		print "<p />\n";
	} else {
		print
"<div class=\"box\" id=\"statusbad\">Invalid search performed. Try to <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=browse&amp;scheme_id=$scheme_id\">browse all records</a>.</div>\n";
	}
	return;
}

sub is_valid_operator {
	my ( $self, $value ) = @_;
	return ( any { $value eq $_ } ( qw (= contains > < NOT), 'NOT contain' ) ) ? 1 : 0;
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
	my $qry      = "SELECT id FROM users WHERE ";
	my $equals   = $suffix ne 'id' ? "upper($suffix) = upper('$text')" : "$suffix = '$text'";
	my $contains = $suffix ne 'id' ? "upper($suffix) LIKE upper('\%$text\%')" : "CAST($suffix AS text) LIKE ('\%$text\%')";
	given ($operator) {
		when ('NOT')         { $qry .= "NOT $equals" }
		when ('contains')    { $qry .= $contains }
		when ('NOT contain') { $qry .= "NOT $contains" }
		when ('=')           { $qry .= $equals }
		default              { $qry .= "$suffix $operator '$text'" }
	}
	my $ids = $self->{'datastore'}->run_list_query($qry);
	$ids = [0] if !@$ids;
	local $" = "' OR $table.$field = '";
	return "($table.$field = '@$ids')";
}

sub _check_format {

	#returns 1 if error
	my ( $self, $data, $error_ref ) = @_;
	my $error;
	if ( $data->{'text'} ne 'null' && defined $data->{'type'} ) {
		if ( $data->{'type'} =~ /int/ && !BIGSdb::Utils::is_int( $data->{'text'} ) ) {
			$error = "$data->{'field'} is an integer field.";
		} elsif ( $data->{'type'} eq 'float' && !BIGSdb::Utils::is_float( $data->{'text'} ) ) {
			$error = "$data->{'field'} is a floating point number field.";
		} elsif ( $data->{'type'} eq 'date' && !BIGSdb::Utils::is_date( $data->{'text'} ) ) {
			$error = "$data->{'field'} is a date field - should be in yyyy-mm-dd format (or 'today' / 'yesterday').";
		} elsif ( $data->{'type'} eq 'date'
			&& ( $data->{'operator'} eq 'contains' || $data->{'operator'} eq 'NOT contain' ) )
		{
			$error = "Searching a date field can not be done for 'contains' or 'NOT contain' operators.";
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
	$$value_ref =~ s/'/\\'/g;
	return;
}
1;
