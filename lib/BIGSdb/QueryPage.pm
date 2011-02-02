#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
use base qw(BIGSdb::Page);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant MAX_ROWS => 20;

sub initiate {
	my ($self) = @_;
	if ( $self->{'cgi'}->param('no_header') ) {
		$self->{'type'} = 'no_header';
		return;
	}
	$self->{'field_help'} = 1;
	$self->{'jQuery'}     = 1;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { 'general' => 1, 'main_display' => 1, 'isolate_display' => 0, 'analysis' => 0, 'query_field' => 1 };
}

sub get_javascript {
	my ($self)   = @_;
	my $max_rows = MAX_ROWS;
	my $buffer   = << "END";
\$(function () {
	\$('a[rel=ajax]').click(function(){
  		\$(this).attr('href', function(){
    		return(this.href.replace(/(.*)/, "javascript:loadContent\('\$1\'\)"));
    	});
  	});
});

function loadContent(url) {
	var row = parseInt(url.match(/row=(\\d+)/)[1]);
	var new_row = row+1;
	var fields = url.match(/fields=([provenance|loci|scheme]+)/)[1];
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
	return if !BIGSdb::Utils::is_int($row) || $row > 20 || $row < 2;
	if ( $system->{'dbtype'} eq 'isolates' ) {
		if ( $q->param('fields') eq 'provenance' ) {
			my ( $select_items, $labels ) = $self->_get_isolate_select_items;
			$self->_print_provenance_fields( $row, 0, $select_items, $labels );
		} elsif ( $q->param('fields') eq 'loci' ) {
			my ( $locus_list, $locus_labels ) =
			  $self->get_field_selection_list( { 'loci' => 1, 'scheme_fields' => 1, 'sort_labels' => 1 } );
			$self->_print_loci_fields( $row, 0, $locus_list, $locus_labels );
		}
	} elsif ( $system->{'dbtype'} eq 'sequences' ) {
		if ( $q->param('fields') eq 'scheme' ) {
			my $scheme_id = $q->param('scheme_id');
			my ( $primary_key, $select_items, $orderitems, $cleaned ) = $self->_get_profile_select_items($scheme_id);
			$self->_print_scheme_fields( $row, 0, $scheme_id, $select_items, $cleaned );
		}
	}
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
		$system->{'dbtype'} eq 'isolates' ? $self->_print_isolate_query_interface : $self->_print_profile_query_interface($scheme_id);
	}
	if ( $q->param('submit') || defined $q->param('query') ) {
		$system->{'dbtype'} eq 'isolates' ? $self->_run_isolate_query() : $self->_run_profile_query($scheme_id);
	} else {
		print "<p />\n";
	}
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
		print
"<a id=\"add_fields\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;fields=provenance&amp;row=$next_row&amp;no_header=1\" rel=\"ajax\" class=\"button\">&nbsp;+&nbsp;</a>\n";
		print
" <a class=\"tooltip\" title=\"Search values - Empty field values can be searched using the term \&lt;&shy;blank\&gt; or null. <p /><h3>Number of fields</h3>Add more fields by clicked the '+' button.\">&nbsp;<i>i</i>&nbsp;</a>"
		  if $self->{'prefs'}->{'tooltips'};
	}
	print "</span>\n";
}

sub _print_loci_fields {
	my ( $self, $row, $max_rows, $locus_list, $locus_labels ) = @_;
	my $loci_disabled = 1 if !@$locus_list;
	my $q = $self->{'cgi'};
	print "<span style=\"white-space:nowrap\">\n";
	if ($loci_disabled) {
		print $q->popup_menu( -name => "ls$row", -values => ['No loci available'], -disabled => 'disabled' );
		print $q->popup_menu( -name => "ly$row", -values => [ "=", "contains", ">", "<", "NOT", "NOT contain" ], -disabled => 'disabled' );
		print $q->textfield( -name => "lt$row", -class => 'value_entry', -disabled => 'disabled' );
	} else {
		print $q->popup_menu( -name => "ls$row", -values => $locus_list, -labels => $locus_labels, -class => 'fieldlist' );
		print $q->popup_menu( -name => "ly$row", -values => [ "=", "contains", ">", "<", "NOT", "NOT contain" ] );
		print $q->textfield( -name => "lt$row", -class => 'allele_entry' );
		if ( $row == 1 ) {
			my $next_row = $max_rows ? $max_rows + 1 : 2;
			print
"<a id=\"add_loci\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;fields=loci&amp;row=$next_row&amp;no_header=1\" rel=\"ajax\" class=\"button\">&nbsp;+&nbsp;</a>\n";
			print
" <a class=\"tooltip\" title=\"Search values - Empty field values can be searched using the term \&lt;&shy;blank\&gt; or null. <p /><h3>Number of fields</h3>The number of fields that can be combined can be set in the options page.\">&nbsp;<i>i</i>&nbsp;</a>"
			  if $self->{'prefs'}->{'tooltips'};
		}
	}
	print "</span>\n";
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
	print $q->startform();
	$q->param( 'table', $self->{'system'}->{'view'} );
	foreach (qw (db page table)) {
		print $q->hidden($_);
	}

	#Provenance/phenotype fields
	print "<div style=\"white-space:nowrap\"><fieldset>\n<legend>Isolate provenance/phenotype fields</legend>\n";
	my $prov_fields = $self->_highest_entered_fields('provenance') || 1;
	my $display_field_heading = $prov_fields == 1 ? 'none' : 'inline';
	print "<span id=\"prov_field_heading\" style=\"display:$display_field_heading\"><label for=\"c0\">Combine searches with: </label>\n";
	print $q->popup_menu( -name => 'c0', -id => 'c0', -values => [ "AND", "OR" ] );
	print
" <a class=\"tooltip\" title=\"query modifier - Select 'AND' for the isolate query to match ALL search terms, 'OR' to match ANY of these terms.\">&nbsp;<i>i</i>&nbsp;</a>"
	  if $self->{'prefs'}->{'tooltips'};
	print "</span>\n";
	print "<ul id=\"provenance\">\n";
	my ( $select_items, $labels ) = $self->_get_isolate_select_items;
	my $i;

	for ( $i = 1 ; $i <= $prov_fields ; $i++ ) {
		print "<li>\n";
		$self->_print_provenance_fields( $i, $prov_fields, $select_items, $labels );
		print "</li>\n";
	}
	print "</ul>\n";
	print "</fieldset>\n";

	#Loci/scheme fields
	my ( $locus_list, $locus_labels ) = $self->get_field_selection_list( { 'loci' => 1, 'scheme_fields' => 1, 'sort_labels' => 1 } );
	print "<fieldset>\n";
	print "<legend>Filter with locus or scheme fields</legend>\n";
	my $locus_fields = $self->_highest_entered_fields('loci') || 1;
	my $loci_field_heading = $locus_fields == 1 ? 'none' : 'inline';
	print "<span id=\"loci_field_heading\" style=\"display:$loci_field_heading\"><label for=\"c1\">Combine with: </label>\n";
	if ( !@$locus_list ) {
		print $q->popup_menu( -name => 'c1', -id => 'c1', -values => [ "AND", "OR" ], -disabled => 'disabled' );
	} else {
		print $q->popup_menu( -name => 'c1', -id => 'c1', -values => [ "AND", "OR" ], );
		print
" <a class=\"tooltip\" title=\"query modifier - Select 'AND' to filter the isolate query to match ALL allele or scheme search terms, 'OR' to match ANY of these terms.\">&nbsp;<i>i</i>&nbsp;</a>"
		  if $self->{'prefs'}->{'tooltips'};
	}
	print "</span>\n<ul id=\"loci\">\n";
	for ( my $i = 1 ; $i <= $locus_fields ; $i++ ) {
		print "<li>\n";
		$self->_print_loci_fields( $i, $locus_fields, $locus_list, $locus_labels );
		print "</li>\n";
	}
	print "</ul>\n";
	print "</fieldset></div>\n";

	#Filters
	my @filters;
	my $extended = $self->get_extended_attributes;
	foreach my $field ( @{ $self->{'xmlHandler'}->get_field_list() } ) {
		my %thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
		my @dropdownlist;
		my %dropdownlabels;
		if ( $prefs->{'dropdownfields'}->{$field} ) {
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
				if (   $field eq 'sender'
					|| $field eq 'curator'
					|| ( $thisfield{'userfield'} && $thisfield{'userfield'} eq 'yes' ) )
				{
					my $qry = "SELECT DISTINCT($field) FROM $system->{'view'}";
					my $sql = $self->{'db'}->prepare($qry);
					$sql->execute()
					  or $logger->error("Can't execute query '$qry'");
					my @userids;
					while ( my ($value) = $sql->fetchrow_array ) {
						push @userids, $value;
					}
					if (@userids) {
						$"   = ' OR id=';
						$qry = "SELECT id,first_name,surname FROM users where id=@userids ORDER BY surname";
						$sql = $self->{'db'}->prepare($qry);
						$sql->execute()
						  or $logger->error("Can't execute query '$qry'");
						while ( my @userdata = $sql->fetchrow_array ) {
							push @dropdownlist, $userdata[0];
							if ( $userdata[2] eq 'applicable' ) {
								$dropdownlabels{ $userdata[0] } = "not applicable";
							} else {
								$dropdownlabels{ $userdata[0] } = "$userdata[2], $userdata[1]";
							}
						}
					}
				} else {
					my $qry = "SELECT DISTINCT($field) FROM $system->{'view'}";
					my $sql = $self->{'db'}->prepare($qry);
					$sql->execute()
					  or $logger->error("Can't execute query '$qry'");
					while ( my ($value) = $sql->fetchrow_array ) {
						push @dropdownlist, $value;
					}
				}
			}
			my $buffer = "<label for=\"$field\_list\" class=\"filter\">$field: </label>\n";
			$" = ' ';
			$buffer .= $q->popup_menu(
				-name   => $field . '_list',
				-id     => $field . '_list',
				-values => [ '', @dropdownlist ],
				-labels => \%dropdownlabels,
				-class  => 'filter'
			);
			my $a_or_an = substr( $field, 0, 1 ) =~ /[aeiouAEIOU]/ ? 'an' : 'a';
			$buffer .=
" <a class=\"tooltip\" title=\"$field filter - Select $a_or_an $field to filter your search to only those isolates that match the selected $field.\">&nbsp;<i>i</i>&nbsp;</a>"
			  if $self->{'prefs'}->{'tooltips'};
			push @filters, $buffer;
		}
		my $extatt = $extended->{$field};
		if ( ref $extatt eq 'ARRAY' ) {
			foreach my $extended_attribute (@$extatt) {
				if ( $self->{'prefs'}->{'dropdownfields'}->{"$field\..$extended_attribute"} ) {
					my $values = $self->{'datastore'}->run_list_query(
						"SELECT DISTINCT value FROM isolate_value_extended_attributes WHERE isolate_field=? AND attribute=? ORDER BY value",
						$field, $extended_attribute
					);
					my $buffer =
					  "<label for=\"$field\..$extended_attribute\_list\" class=\"filter\">$field\..$extended_attribute: </label>\n";
					$" = ' ';
					$buffer .= $q->popup_menu(
						-name   => "$field\..$extended_attribute" . '_list',
						-id     => "$field\..$extended_attribute" . '_list',
						-values => [ '', @$values ],
						-class  => 'filter'
					);
					my $a_or_an = substr( $extended_attribute, 0, 1 ) =~ /[aeiouAEIOU]/ ? 'an' : 'a';
					$buffer .=
" <a class=\"tooltip\" title=\"$field\..$extended_attribute filter - Select $a_or_an $extended_attribute to filter your search to only those isolates that match the selected $field.\">&nbsp;<i>i</i>&nbsp;</a>"
					  if $self->{'prefs'}->{'tooltips'};
					push @filters, $buffer;
				}
			}
		}
	}
	if ( $prefs->{'dropdownfields'}->{'publications'} && $self->{'config'}->{'refdb'} ) {
		my $pmid = $self->{'datastore'}->run_list_query("SELECT DISTINCT(pubmed_id) FROM refs");
		my $buffer;
		if (@$pmid) {
			my $labels = $self->{'datastore'}->get_citation_hash($pmid);
			my $buffer = "<label for=\"publication_list\" class=\"filter\">Publication: </label>\n";
			$" = ' ';
			$buffer .= $q->popup_menu(
				-name   => 'publication_list',
				-id     => 'publication_list',
				-values => [ '', sort { $labels->{$a} cmp $labels->{$b} } keys %$labels ],
				-labels => $labels,
				-class  => 'filter'
			);
			$buffer .=
" <a class=\"tooltip\" title=\"publication filter - Select a publication to filter your search to only those isolates that match the selected publication.\">&nbsp;<i>i</i>&nbsp;</a>"
			  if $self->{'prefs'}->{'tooltips'};
			push @filters, $buffer;
		}
	}
	if ( $prefs->{'dropdownfields'}->{'projects'} ) {
		my $sql = $self->{'db'}->prepare("SELECT id, short_description FROM projects ORDER BY short_description");
		eval { $sql->execute; };
		if ($@) {
			$logger->error("Can't execute $@");
		}
		my ( @project_ids, %labels );
		while ( my ( $id, $desc ) = $sql->fetchrow_array ) {
			push @project_ids, $id;
			$labels{$id} = $desc;
		}
		if (@project_ids) {
			my $buffer = "<label for=\"project_list\" class=\"filter\">Project: </label>\n";
			$" = ' ';
			$buffer .= $q->popup_menu(
				-name   => 'project_list',
				-id     => 'project_list',
				-values => [ '', @project_ids ],
				-labels => \%labels,
				-class  => 'filter'
			);
			$buffer .=
" <a class=\"tooltip\" title=\"project filter - Select a project to filter your search to only those isolates belonging to it.\">&nbsp;<i>i</i>&nbsp;</a>"
			  if $self->{'prefs'}->{'tooltips'};
			push @filters, $buffer;
		}
	}
	my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes ORDER BY display_order,id");
	foreach (@$schemes) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info($_);
		my $field       = "scheme_$_\_profile_status";
		if ( $prefs->{'dropdownfields'}->{$field} ) {
			my $buffer = "<label for=\"$field\_list\" class=\"filter\">$scheme_info->{'description'} profiles: </label>\n";
			$" = ' ';
			$buffer .= $q->popup_menu(
				-name   => "$field\_list",
				-id     => "$field\_list",
				-values => [ '', 'complete', 'incomplete', 'partial', 'not started' ],
				-class  => 'filter'
			);
			$buffer .=
" <a class=\"tooltip\" title=\"$scheme_info->{'description'} profile completion filter - Select whether the isolates should have complete, partial, or unstarted profiles.\">&nbsp;<i>i</i>&nbsp;</a>"
			  if $self->{'prefs'}->{'tooltips'};
			push @filters, $buffer;
		}
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($_);
		foreach my $field (@$scheme_fields) {
			if ( $self->{'prefs'}->{"dropdown\_scheme_fields"}->{$_}->{$field} ) {
				( my $cleaned = $field ) =~ tr/_/ /;
				my $buffer =
				  "<label for=\"scheme\_$_\_$field\_list\" class=\"filter\">$cleaned ($scheme_info->{'description'}): </label>\n";
				my $values = $self->{'datastore'}->get_scheme($_)->get_distinct_fields($field);
				$" = ' ';
				$buffer .= $q->popup_menu(
					-name   => "scheme\_$_\_$field\_list",
					-id     => "scheme\_$_\_$field\_list",
					-values => [ '', @$values ],
					-class  => 'filter'
				);
				my $a_or_an = substr( $field, 0, 1 ) =~ /[aeiouAEIOU]/ ? 'an' : 'a';
				$buffer .=
" <a class=\"tooltip\" title=\"$cleaned ($scheme_info->{'description'}) filter - Select $a_or_an $cleaned to filter your search to only those isolates that match the selected $cleaned.\">&nbsp;<i>i</i>&nbsp;</a>"
				  if $self->{'prefs'}->{'tooltips'};
				push @filters, $buffer if @$values;
			}
		}
	}
	if ( $prefs->{'dropdownfields'}->{'linked_sequences'} ) {
		my $buffer = "<label for=\"linked_sequences\" class=\"filter\">Linked sequence: </label>\n";
		$" = ' ';
		$buffer .= $q->popup_menu(
			-name   => 'linked_sequences',
			-id     => "linked_sequences",
			-values => [ '', 'with linked sequences', 'without linked sequences' ],
			-class  => 'filter'
		);
		$buffer .=
" <a class=\"tooltip\" title=\"linked sequence filter - Filter by whether sequences have been linked with the isolate record.\">&nbsp;<i>i</i>&nbsp;</a>"
		  if $self->{'prefs'}->{'tooltips'};
		push @filters, $buffer;
	}
	if (@filters) {
		print "<div style=\"white-space:nowrap\"><fieldset><legend>Filter query by</legend>\n";
		print "<ul>\n";
		foreach (@filters) {
			print "<li><span style=\"white-space:nowrap\">$_</span></li>";
		}
		print "</ul>\n</fieldset>";
	}
	print "<fieldset class=\"display\">\n";
	( my $order_list, $labels ) = $self->get_field_selection_list( { 'isolate_fields' => 1, 'loci' => 1, 'scheme_fields' => 1 } );
	print "<ul>\n<li><span style=\"white-space:nowrap\">\n<label for=\"order\" class=\"display\">Order by: </label>\n";
	print $q->popup_menu( -name => 'order', -id => 'order', -values => $order_list, -labels => $labels );
	print $q->popup_menu( -name => 'direction', -values => [ 'ascending', 'descending' ], -default => 'ascending' );
	print "</span></li>\n<li><span style=\"white-space:nowrap\">\n";
	if ( $q->param('displayrecs') ) {
		$prefs->{'displayrecs'} = $q->param('displayrecs');
	}
	print "<label for=\"displayrecs\" class=\"display\">Display: </label>\n";
	print $q->popup_menu(
		-name    => 'displayrecs',
		-id      => 'displayrecs',
		-values  => [ '10', '25', '50', '100', '200', '500', 'all' ],
		-default => $prefs->{'displayrecs'}
	);
	print " records per page&nbsp;";
	print
" <a class=\"tooltip\" title=\"Records per page - Analyses use the full query dataset, rather than just the page shown.\">&nbsp;<i>i</i>&nbsp;</a>"
	  if $self->{'prefs'}->{'tooltips'};
	print "</span></li>\n\n";
	my $page = $self->{'curate'} ? 'isolateQuery' : 'query';
	print
"</ul><span style=\"float:left\"><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page\" class=\"resetbutton\">Reset</a></span><span style=\"float:right\">";
	print $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
	print "</span></fieldset>\n";
	print "</div>\n" if @filters;
	print $q->end_form;
	print "</div>\n</div>\n";
}

sub _highest_entered_fields {
	my ( $self, $type ) = @_;
	my $param_name = ( $type eq 'provenance' || $type eq 'scheme' ) ? 't' : 'lt';
	my $q = $self->{'cgi'};
	my $highest;
	for ( my $i = 1 ; $i < MAX_ROWS ; $i++ ) {
		if ( defined $q->param("$param_name$i") ) {
			$highest = $i;
		}
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
		$cleaned{$_} =~ tr/_/ /;
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
		push @selectitems, "$_ (id)";
		push @selectitems, "$_ (surname)";
		push @selectitems, "$_ (first_name)";
		push @selectitems, "$_ (affiliation)";
		push @orderitems,  $_;
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
		print
"<a id=\"add_scheme_fields\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;fields=scheme&amp;scheme_id=$scheme_id&amp;row=$next_row&amp;no_header=1\" rel=\"ajax\" class=\"button\">&nbsp;+&nbsp;</a>\n";
		print
" <a class=\"tooltip\" title=\"Search values - Empty field values can be searched using the term \&lt;&shy;blank\&gt; or null. <p /><h3>Number of fields</h3>Add more fields by clicked the '+' button.\">&nbsp;<i>i</i>&nbsp;</a>"
		  if $self->{'prefs'}->{'tooltips'};
	}
	print "</span>\n";
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
	foreach (qw (db page scheme_id)) {
		print $q->hidden($_);
	}
	my $scheme_fields = $self->_highest_entered_fields('scheme') || 1;
	my $scheme_field_heading = $scheme_fields == 1 ? 'none' : 'inline';
	print "<div style=\"white-space:nowrap\"><fieldset>\n<legend>Locus/scheme fields</legend>\n";
	print "<span id=\"scheme_field_heading\" style=\"display:$scheme_field_heading\"><label for=\"c0\">Combine searches with: </label>\n";
	print $q->popup_menu( -name => 'c0', -id => 'c0', -values => [ "AND", "OR" ] );
	print
" <a class=\"tooltip\" title=\"query modifier - Select 'AND' for the isolate query to match ALL search terms, 'OR' to match ANY of these terms.\">&nbsp;<i>i</i>&nbsp;</a>"
	  if $self->{'prefs'}->{'tooltips'};
	print "</span><ul id=\"scheme_fields\">\n";
	for ( my $i = 1 ; $i <= $scheme_fields ; $i++ ) {
		print "<li>";
		$self->_print_scheme_fields( $i, $scheme_fields, $scheme_id, $selectitems, $cleaned );
		print "</li>\n";
	}
	print "</ul>\n";
	print "</fieldset>\n";
	my @filters;
	if ( $prefs->{'dropdownfields'}->{'publications'} && $self->{'config'}->{'refdb'} ) {
		my $pmid = $self->{'datastore'}->run_list_query( "SELECT DISTINCT(pubmed_id) FROM profile_refs WHERE scheme_id=?", $scheme_id );
		if (@$pmid) {
			my $labels = $self->{'datastore'}->get_citation_hash($pmid);
			my $buffer = "<label for=\"publication_list\" class=\"filter\">Publication: </label>\n";
			$" = ' ';
			$buffer .= $q->popup_menu(
				-name   => 'publication_list',
				-id     => 'publication_list',
				-values => [ '', sort { $labels->{$a} cmp $labels->{$b} } keys %$labels ],
				-labels => $labels,
				-class  => 'filter'
			);
			$buffer .=
" <a class=\"tooltip\" title=\"publication filter - Select a publication to filter your search to only those isolates that match the selected publication.\">&nbsp;<i>i</i>&nbsp;</a>"
			  if $self->{'prefs'}->{'tooltips'};
			push @filters, $buffer;
		}
	}
	my $schemes;
	if ( $self->{'system'}->{'db_type'} eq 'isolates' ) {
		$schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes ORDER BY display_order,id");
	} else {
		@$schemes = ($scheme_id);
	}
	foreach (@$schemes) {
		my $scheme_info   = $self->{'datastore'}->get_scheme_info($_);
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($_);
		foreach my $field (@$scheme_fields) {
			if ( $self->{'prefs'}->{"dropdown\_scheme_fields"}->{$_}->{$field} ) {
				( my $cleaned = $field ) =~ tr/_/ /;
				my $buffer = "<label for=\"$field\_list\" class=\"filter\">$cleaned ($scheme_info->{'description'}): </label>\n";
				my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $_, $field );
				my $value_clause;
				if ( $scheme_field_info->{'type'} eq 'integer' ) {
					$value_clause = 'CAST(value AS integer)';
				} else {
					$value_clause = 'value';
				}
				my $values =
				  $self->{'datastore'}->run_list_query(
					"SELECT DISTINCT $value_clause FROM profile_fields WHERE scheme_id=? AND scheme_field=? ORDER BY $value_clause",
					$_, $field );
				$" = ' ';
				$buffer .=
				  $q->popup_menu( -name => "$field\_list", -id => "$field\_list", -values => [ '', @$values ], -class => 'filter' );
				my $a_or_an = substr( $field, 0, 1 ) =~ /[aeiouAEIOU]/ ? 'an' : 'a';
				$buffer .=
" <a class=\"tooltip\" title=\"$cleaned ($scheme_info->{'description'}) filter - Select $a_or_an $cleaned to filter your search to only those isolates that match the selected $cleaned.\">&nbsp;<i>i</i>&nbsp;</a>"
				  if $self->{'prefs'}->{'tooltips'};
				push @filters, $buffer;
			}
		}
	}
	print "<fieldset class=\"display\">\n";
	print "<ul>\n<li><span style=\"white-space:nowrap\">\n<label for=\"order\" class=\"display\">Order by: </label>\n";
	$" = ' ';
	print $q->popup_menu( -name => 'order', -id => 'order', -values => $orderitems, -labels => $cleaned );
	print $q->popup_menu( -name => 'direction', -values => [ 'ascending', 'descending' ], -default => 'ascending' );
	print "</span></li>\n<li><span style=\"white-space:nowrap\">\n";
	print "<label for=\"displayrecs\" class=\"display\">Display: </label>\n";

	if ( $q->param('displayrecs') ) {
		$prefs->{'displayrecs'} = $q->param('displayrecs');
	}
	print $q->popup_menu(
		-name    => 'displayrecs',
		-id      => 'displayrecs',
		-values  => [ '10', '25', '50', '100', '200', '500', 'all' ],
		-default => $prefs->{'displayrecs'}
	);
	print " records per page&nbsp;";
	print
" <a class=\"tooltip\" title=\"Records per page - Analyses use the full query dataset, rather than just the page shown.\">&nbsp;<i>i</i>&nbsp;</a>"
	  if $self->{'prefs'}->{'tooltips'};
	print "</span></li>\n\n";
	my $page = $self->{'curate'} ? 'profileQuery' : 'query';
	print
"</ul><span style=\"float:left\"><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;scheme_id=$scheme_id\" class=\"resetbutton\">Reset</a></span><span style=\"float:right\">";
	print $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
	print "</span></fieldset>\n";
	print "</div>\n";

	if (@filters) {
		print "<fieldset>\n";
		print "<legend>Filter query by</legend>\n";
		print "<ul>\n";
		foreach (@filters) {
			print "<li><span style=\"white-space:nowrap\">$_</span></li>";
		}
		print "</ul>\n</fieldset>";
	}
	print $q->end_form;
	print "</div></div>\n";
}
####END PROFILE INTERFACE#######################################################
sub _run_isolate_query {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $system = $self->{'system'};
	my $qry;
	my @errors;
	my $extended = $self->get_extended_attributes;
	if ( !defined $q->param('query') ) {
		$qry = "SELECT * FROM $system->{'view'} WHERE (";
		my $andor       = $q->param('c0');
		my $first_value = 1;
		for ( my $i = 1 ; $i <= MAX_ROWS ; $i++ ) {
			if ( $q->param("t$i") ne '' ) {
				my $field = $q->param("s$i");
				$field =~ s/^f_//;
				my @groupedfields;
				for ( my $x = 1 ; $x < 11 ; $x++ ) {
					if ( $system->{"fieldgroup$x"} ) {
						my @grouped = ( split /:/, $system->{"fieldgroup$x"} );
						if ( $field eq $grouped[0] ) {
							@groupedfields = split /,/, $grouped[1];
						}
					}
				}
				my %thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
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
				$text =~ s/^\s*//;
				$text =~ s/\s*$//;
				$text =~ s/'/\\'/g;
				if (   $text ne '<blank>'
					&& $text ne 'null'
					&& ( lc( $thisfield{'type'} ) eq 'int' )
					&& !BIGSdb::Utils::is_int($text) )
				{
					push @errors, "$field is an integer field.";
					next;
				} elsif ( $text ne '<blank>'
					&& $text ne 'null'
					&& ( lc( $thisfield{'type'} ) eq 'float' )
					&& !BIGSdb::Utils::is_float($text) )
				{
					push @errors, "$field is a floating point number field.";
					next;
				} elsif ( $text ne '<blank>'
					&& $text ne 'null'
					&& lc( $thisfield{'type'} ) eq 'date'
					&& !BIGSdb::Utils::is_date($text) )
				{
					push @errors, "$field is a date field - should be in yyyy-mm-dd format (or 'today' / 'yesterday').";
					next;
				} elsif ( !$self->is_valid_operator($operator) ) {
					push @errors, "$operator is not a valid operator.";
					next;
				}
				my $modifier = '';
				if ( $i > 1 && !$first_value ) {
					$modifier = " $andor ";
				}
				$first_value = 0;
				if ( $field =~ /(.*) \(id\)$/
					&& !BIGSdb::Utils::is_int($text) )
				{
					push @errors, "$field is an integer field.";
					next;
				}
				if ( any { $field =~ /(.*) \($_\)$/ } qw (id surname first_name affiliation) ) {
					$qry .= $modifier . $self->search_users( $field, $operator, $text, $self->{'system'}->{'view'} );
				} else {
					if ( $operator eq 'NOT' ) {
						if ( scalar @groupedfields ) {
							$qry .= "$modifier (";
							for ( my $x = 0 ; $x < scalar @groupedfields ; $x++ ) {
								my %thisfield = $self->{'xmlHandler'}->get_field_attributes( $groupedfields[$x] );
								if ( $text eq '<blank>' || $text eq 'null' ) {
									$qry .= ' OR ' if $x != 0;
									$qry .= "($groupedfields[$x] IS NOT NULL)";
								} else {
									$qry .= ' AND ' if $x != 0;
									if ( $thisfield{'type'} eq 'int' ) {
										$qry .= "(NOT CAST($groupedfields[$x] AS text) = '$text' OR $groupedfields[$x] IS NULL)";
									} else {
										$qry .= "(NOT upper($groupedfields[$x]) = upper('$text') OR $groupedfields[$x] IS NULL)";
									}
								}
							}
							$qry .= ')';
						} elsif ($extended_isolate_field) {
							$qry .= $modifier
							  . (
								( $text eq '<blank>' || $text eq 'null' )
								? "$extended_isolate_field IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$extended_isolate_field' AND attribute='$field')"
								: "$extended_isolate_field NOT IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$extended_isolate_field' AND attribute='$field' AND upper(value)=upper('$text'))"
							  );
						} elsif ( $field eq $self->{'system'}->{'labelfield'} ) {
							$qry .= $modifier
							  . "(NOT upper($field) = upper('$text') AND id NOT IN (SELECT isolate_id FROM isolate_aliases WHERE upper(alias) = upper('$text')))";
						} else {
							if ( $thisfield{'type'} eq 'int' ) {
								$qry .= $modifier
								  . (
									( $text eq '<blank>' || $text eq 'null' )
									? "$field is not null"
									: "NOT ($field = '$text' OR $field IS NULL)"
								  );
							} else {
								$qry .= $modifier
								  . (
									( $text eq '<blank>' || $text eq 'null' )
									? "$field is not null"
									: "(NOT upper($field) = upper('$text') OR $field IS NULL)"
								  );
							}
						}
					} elsif ( $operator eq "contains" ) {
						if ( scalar @groupedfields ) {
							$qry .= "$modifier (";
							for ( my $x = 0 ; $x < scalar @groupedfields ; $x++ ) {
								my %thisfield = $self->{'xmlHandler'}->get_field_attributes( $groupedfields[$x] );
								$qry .= ' OR ' if $x != 0;
								if ( $thisfield{'type'} eq 'int' ) {
									$qry .= "CAST($groupedfields[$x] AS text) LIKE '\%$text\%'";
								} else {
									$qry .= "upper($groupedfields[$x]) LIKE upper('\%$text\%')";
								}
							}
							$qry .= ')';
						} elsif ($extended_isolate_field) {
							$qry .= $modifier
							  . "$extended_isolate_field IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$extended_isolate_field' AND attribute='$field' AND upper(value) LIKE upper('\%$text\%'))";
						} elsif ( $field eq $self->{'system'}->{'labelfield'} ) {
							$qry .= $modifier
							  . "(upper($field) LIKE upper('\%$text\%') OR id IN (SELECT isolate_id FROM isolate_aliases WHERE upper(alias) LIKE upper('\%$text\%')))";
						} else {
							if ( $thisfield{'type'} eq 'int' ) {
								$qry .= $modifier . "CAST($field AS text) LIKE '\%$text\%'";
							} else {
								$qry .= $modifier . "upper($field) LIKE upper('\%$text\%')";
							}
						}
					} elsif ( $operator eq "NOT contain" ) {
						if ( scalar @groupedfields ) {
							$qry .= "$modifier (";
							for ( my $x = 0 ; $x < scalar @groupedfields ; $x++ ) {
								my %thisfield = $self->{'xmlHandler'}->get_field_attributes( $groupedfields[$x] );
								$qry .= ' AND ' if $x != 0;
								if ( $thisfield{'type'} eq 'int' ) {
									$qry .= "(NOT CAST($groupedfields[$x] AS text) LIKE '\%$text\%' OR $groupedfields[$x] IS NULL)";
								} else {
									$qry .= "(NOT upper($groupedfields[$x]) LIKE upper('\%$text\%') OR $groupedfields[$x] IS NULL)";
								}
							}
							$qry .= ')';
						} elsif ($extended_isolate_field) {
							$qry .= $modifier
							  . "$extended_isolate_field NOT IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$extended_isolate_field' AND attribute='$field' AND upper(value) LIKE upper('\%$text\%'))";
						} elsif ( $field eq $self->{'system'}->{'labelfield'} ) {
							$qry .= $modifier
							  . "(NOT upper($field) LIKE upper('\%$text\%') AND id NOT IN (SELECT isolate_id FROM isolate_aliases WHERE upper(alias) LIKE upper('\%$text\%')))";
						} else {
							if ( $thisfield{'type'} eq 'int' ) {
								$qry .= $modifier . "(NOT CAST($field AS text) LIKE '\%$text\%' OR $field IS NULL)";
							} else {
								$qry .= $modifier . "(NOT upper($field) LIKE upper('\%$text\%') OR $field IS NULL)";
							}
						}
					} elsif ( $operator eq '=' ) {
						if ( scalar @groupedfields ) {
							$qry .= "$modifier (";
							for ( my $x = 0 ; $x < scalar @groupedfields ; $x++ ) {
								my %thisfield = $self->{'xmlHandler'}->get_field_attributes( $groupedfields[$x] );
								$qry .= ' OR ' if $x != 0;
								if ( $thisfield{'type'} eq 'int' ) {
									$qry .=
									  ( $text eq '<blank>' || $text eq 'null' )
									  ? "$groupedfields[$x] IS NULL"
									  : "CAST($groupedfields[$x] AS text) = '$text'";
								} else {
									$qry .=
									  ( $text eq '<blank>' || $text eq 'null' )
									  ? "$groupedfields[$x] IS NULL"
									  : "upper($groupedfields[$x]) = upper('$text')";
								}
							}
							$qry .= ')';
						} elsif ($extended_isolate_field) {
							$qry .= $modifier
							  . (
								( $text eq '<blank>' || $text eq 'null' )
								? "$extended_isolate_field NOT IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$extended_isolate_field' AND attribute='$field')"
								: "$extended_isolate_field IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$extended_isolate_field' AND attribute='$field' AND upper(value) = upper('$text'))"
							  );
						} elsif ( $field eq $self->{'system'}->{'labelfield'} ) {
							$qry .= $modifier
							  . "(upper($field) = upper('$text') OR id IN (SELECT isolate_id FROM isolate_aliases WHERE upper(alias) = upper('$text')))";
						} elsif ( lc( $thisfield{'type'} ) eq 'text' ) {
							$qry .= $modifier
							  . ( ( $text eq '<blank>' || $text eq 'null' ) ? "$field is null" : "upper($field) = upper('$text')" );
						} else {
							$qry .= $modifier . ( ( $text eq '<blank>' || $text eq 'null' ) ? "$field is null" : "$field = '$text'" );
						}
					} else {
						if ( scalar @groupedfields ) {
							$qry .= "$modifier (";
							for ( my $x = 0 ; $x < scalar @groupedfields ; $x++ ) {
								my %thisfield = $self->{'xmlHandler'}->get_field_attributes( $groupedfields[$x] );
								if ( $thisfield{'type'} eq 'int'
									&& !BIGSdb::Utils::is_int($text) )
								{
									push @errors, "$groupedfields[$x] is an integer field.";
									next;
								} elsif ( $thisfield{'type'} eq 'float'
									&& !BIGSdb::Utils::is_float($text) )
								{
									push @errors, "$groupedfields[$x] is a floating point number field.";
									next;
								}
								$qry .= ' OR ' if $x != 0;
								%thisfield = $self->{'xmlHandler'}->get_field_attributes( $groupedfields[$x] );
								if ( $thisfield{'type'} eq 'int' ) {
									$qry .= "(CAST($groupedfields[$x] AS text) $operator '$text' AND $groupedfields[$x] is not null)";
								} else {
									$qry .= "($groupedfields[$x] $operator '$text' AND $groupedfields[$x] is not null)";
								}
							}
							$qry .= ')';
						} elsif ($extended_isolate_field) {
							$qry .= $modifier
							  . "$extended_isolate_field IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$extended_isolate_field' AND attribute='$field' AND value $operator '$text')";
						} elsif ( $field eq $self->{'system'}->{'labelfield'} ) {
							$qry .= $modifier
							  . "($field $operator '$text' OR id IN (SELECT isolate_id FROM isolate_aliases WHERE alias $operator '$text'))";
						} else {
							if ( $text eq 'null' ) {
								push @errors, "$operator is not a valid operator for comparing null values.";
								next;
							}
							$qry .= $modifier . "$field $operator '$text'";
						}
					}
				}
			}
		}
		$qry .= ')';
		foreach ( @{ $self->{'xmlHandler'}->get_field_list() } ) {
			if ( $q->param( $_ . '_list' ) ne '' ) {
				my $value = $q->param( $_ . '_list' );
				if ( $qry !~ /WHERE \(\)\s*$/ ) {
					$qry .= " AND ";
				} else {
					$qry = "SELECT * FROM $system->{'view'} WHERE ";
				}
				$qry .= ( ( $value eq '<blank>' || $value eq 'null' ) ? "$_ is null" : "$_ = '$value'" );
			}
			my $extatt = $extended->{$_};
			if ( ref $extatt eq 'ARRAY' ) {
				foreach my $extended_attribute (@$extatt) {
					if ( $q->param("$_\..$extended_attribute\_list") ne '' ) {
						my $value = $q->param("$_\..$extended_attribute\_list");
						$value =~ s/'/\\'/g;
						if ( $qry !~ /WHERE \(\)\s*$/ ) {
							$qry .=
" AND ($_ IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$_' AND attribute='$extended_attribute' AND value='$value'))";
						} else {
							$qry =
"SELECT * FROM $system->{'view'} WHERE ($_ IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$_' AND attribute='$extended_attribute' AND value='$value'))";
						}
					}
				}
			}
		}
		if ( $q->param('publication_list') ne '' ) {
			my $pmid = $q->param('publication_list');
			my $ids = $self->{'datastore'}->run_list_query( "SELECT isolate_id FROM refs WHERE pubmed_id=?", $pmid );
			if ($pmid) {
				$" = "','";
				if ( $qry !~ /WHERE \(\)\s*$/ ) {
					$qry .= " AND (id IN ('@$ids'))";
				} else {
					$qry = "SELECT * FROM $system->{'view'} WHERE (id IN ('@$ids'))";
				}
			}
		}
		if ( $q->param('project_list') ne '' ) {
			my $project_id = $q->param('project_list');
			if ($project_id) {
				$" = "','";
				if ( $qry !~ /WHERE \(\)\s*$/ ) {
					$qry .= " AND (id IN (SELECT isolate_id FROM project_members WHERE project_id='$project_id'))";
				} else {
					$qry =
"SELECT * FROM $system->{'view'} WHERE (id IN (SELECT isolate_id FROM project_members WHERE project_id='$project_id'))";
				}
			}
		}
		if ( $q->param('linked_sequences') ) {
			my $not;
			if ( $q->param('linked_sequences') =~ /without/ ) {
				$not = ' NOT';
			}
			if ( $qry !~ /WHERE \(\)\s*$/ ) {
				$qry .= " AND (id$not IN (SELECT isolate_id FROM sequence_bin))";
			} else {
				$qry = "SELECT * FROM $system->{'view'} WHERE (id$not IN (SELECT isolate_id FROM sequence_bin))";
			}
		}
		my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
		foreach my $scheme_id (@$schemes) {
			if ( $q->param("scheme_$scheme_id\_profile_status_list") ne '' ) {
				my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
				if (@$scheme_loci) {
					my $allele_clause;
					my $first = 1;
					foreach my $locus (@$scheme_loci) {
						$allele_clause .= ' OR ' if !$first;
						$allele_clause .= "(locus='$locus' AND allele_id IS NOT NULL)";
						$first = 0;
					}
					my $param = $q->param("scheme_$scheme_id\_profile_status_list");
					my $clause;
					if ( $param eq 'complete' ) {
						$clause =
"(id IN (SELECT isolate_id FROM allele_designations WHERE $allele_clause GROUP BY isolate_id HAVING COUNT(isolate_id)= "
						  . scalar @$scheme_loci . '))';
					} elsif ( $param eq 'partial' ) {
						$clause =
"(id IN (SELECT isolate_id FROM allele_designations WHERE $allele_clause GROUP BY isolate_id HAVING COUNT(isolate_id)< "
						  . scalar @$scheme_loci . '))';
					} elsif ( $param eq 'incomplete' ) {
						$clause =
"(id IN (SELECT isolate_id FROM allele_designations WHERE $allele_clause GROUP BY isolate_id HAVING COUNT(isolate_id)< "
						  . scalar @$scheme_loci
						  . ") OR id NOT IN (SELECT isolate_id FROM allele_designations WHERE $allele_clause GROUP BY isolate_id )) ";
					} else {
						$clause = "(id NOT IN (SELECT isolate_id FROM allele_designations WHERE $allele_clause GROUP BY isolate_id ))";
					}
					if ( $qry !~ /WHERE \(\)\s*$/ ) {
						$qry .= "AND $clause";
					} else {
						$qry = "SELECT * FROM $system->{'view'} WHERE $clause";
					}
				}
			}
			my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
			foreach my $field (@$scheme_fields) {
				if ( $q->param("scheme_$scheme_id\_$field\_list") ne '' ) {
					my $value = $q->param("scheme_$scheme_id\_$field\_list");
					$value =~ s/'/\\'/g;
					my $clause;
					$field = "scheme_$scheme_id\.$field";
					my $scheme_loci  = $self->{'datastore'}->get_scheme_loci($scheme_id);
					my $joined_table = "SELECT id FROM $system->{'view'}";
					$" = ',';
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
					$" = ' AND ';
					$joined_table .= " @temp WHERE";
					undef @temp;
					foreach (@$scheme_loci) {
						push @temp, "$_.locus='$_'";
					}
					$joined_table .= " @temp";
					my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
					if ( $scheme_field_info->{'type'} eq 'integer' ) {
						$clause = "(id IN ($joined_table AND CAST($field AS int) = '$value'))";
					} else {
						$clause = "(id IN ($joined_table AND $field = '$value'))";
					}
					if ( $qry !~ /WHERE \(\)\s*$/ ) {
						$qry .= "AND $clause";
					} else {
						$qry = "SELECT * FROM $system->{'view'} WHERE $clause";
					}
				}
			}
		}
		my @lqry;
		my @lqry_blank;
		my %combo;
		for ( my $i = 1 ; $i <= MAX_ROWS ; $i++ ) {
			if ( $q->param("lt$i") ne '' ) {
				if ( $q->param("ls$i") =~ /^l_(.+)/ || $q->param("ls$i") =~ /^la_(.+)\|\|/ || $q->param("ls$i") =~ /^cn_(.+)/ ) {
					my $locus = $1;
					$locus =~ s/'/\\'/g;
					my $locus_info = $self->{'datastore'}->get_locus_info($locus);
					my $operator   = $q->param("ly$i");
					my $text       = $q->param("lt$i");
					if ( $combo{"$locus\_$operator\_$text"} ) {
						next;    #prevent duplicates
					}
					$combo{"$locus\_$operator\_$text"} = 1;
					$text =~ s/^\s*//;
					$text =~ s/\s*$//;
					$text =~ s/'/\\'/g;
					if (   $text ne '<blank>'
						&& $text ne 'null'
						&& ( $locus_info->{'allele_id_format'} eq 'integer' )
						&& !BIGSdb::Utils::is_int($text) )
					{
						push @errors, "$locus is an integer field.";
						next;
					} elsif ( !$self->is_valid_operator($operator) ) {
						push @errors, "$operator is not a valid operator.";
						next;
					}
					if ( $operator eq 'NOT' ) {
						push @lqry,
						  (
							( $text eq '<blank>' || $text eq 'null' )
							? "(EXISTS (SELECT 1 WHERE allele_designations.locus='$locus'))"
							: "(allele_designations.locus='$locus' AND NOT upper(allele_designations.allele_id) = upper('$text'))"
						  );
					} elsif ( $operator eq "contains" ) {
						push @lqry, "(allele_designations.locus='$locus' AND upper(allele_designations.allele_id) LIKE upper('\%$text\%'))";
					} elsif ( $operator eq "NOT contain" ) {
						push @lqry,
						  "(allele_designations.locus='$locus' AND NOT upper(allele_designations.allele_id) LIKE upper('\%$text\%'))";
					} elsif ( $operator eq '=' ) {
						if ( $text eq '<blank>' || $text eq 'null' ) {
							push @lqry_blank, "(id NOT IN (SELECT isolate_id FROM allele_designations WHERE locus='$locus'))";
						} else {
							push @lqry,
							  $locus_info->{'allele_id_format'} eq 'text'
							  ? "(allele_designations.locus='$locus' AND upper(allele_designations.allele_id) = upper('$text'))"
							  : "(allele_designations.locus='$locus' AND allele_designations.allele_id = '$text')";
						}
					} else {
						if ( $text eq 'null' ) {
							push @errors, "$operator is not a valid operator for comparing null values.";
							next;
						}
						if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
							push @lqry,
							  "(allele_designations.locus='$locus' AND CAST(allele_designations.allele_id AS int) $operator '$text')";
						} else {
							push @lqry, "(allele_designations.locus='$locus' AND allele_designations.allele_id $operator '$text')";
						}
					}
				}
			}
		}
		my @sqry;
		for ( my $i = 1 ; $i <= MAX_ROWS ; $i++ ) {
			if ( $q->param("lt$i") ne '' ) {
				if ( $q->param("ls$i") =~ /^s_(\d+)_(.*)/ ) {
					my $scheme_id         = $1;
					my $field             = $2;
					my $operator          = $q->param("ly$i");
					my $text              = $q->param("lt$i");
					my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
					$text =~ s/^\s*//;
					$text =~ s/\s*$//;
					$text =~ s/'/\\'/g;

					if (   $text ne '<blank>'
						&& $text ne 'null'
						&& ( $scheme_field_info->{'type'} eq 'integer' )
						&& !BIGSdb::Utils::is_int($text) )
					{
						push @errors, "$field is an integer field.";
						next;
					} elsif ( !$self->is_valid_operator($operator) ) {
						push @errors, "$operator is not a valid operator.";
						next;
					}
					$field = "scheme_$scheme_id\.$field";
					my $scheme_loci  = $self->{'datastore'}->get_scheme_loci($scheme_id);
					my $joined_table = "SELECT id FROM $system->{'view'}";
					$" = ',';
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
					$" = ' AND ';
					$joined_table .= " @temp WHERE";
					undef @temp;
					foreach (@$scheme_loci) {
						push @temp, "$_.locus='$_'";
					}
					$joined_table .= " @temp";
					$" = ',';
					if ( $operator eq 'NOT' ) {
						push @sqry, ( $text eq '<blank>' || $text eq 'null' )
						  ? "(id NOT IN ($joined_table AND $field is null))"
						  : "(id NOT IN ($joined_table AND $field='$text'))";
					} elsif ( $operator eq "contains" ) {
						push @sqry,
						  $scheme_field_info->{'type'} eq 'integer'
						  ? "(id IN ($joined_table AND CAST($field AS text) ~* '$text'))"
						  : "(id IN ($joined_table AND $field ~* '$text'))";
					} elsif ( $operator eq "NOT contain" ) {
						push @sqry,
						  $scheme_field_info->{'type'} eq 'integer'
						  ? "(id IN ($joined_table AND CAST($field AS text) !~* '$text'))"
						  : "(id IN ($joined_table AND $field !~* '$text'))";
					} elsif ( $operator eq '=' ) {
						if ( $text eq '<blank>' || $text eq 'null' ) {
							push @lqry_blank, "(id IN ($joined_table AND $field is null))";
						} else {
							push @sqry, $scheme_field_info->{'type'} eq 'text'
							  ? "(id IN ($joined_table AND upper($field)=upper('$text')))"
							  : "(id IN ($joined_table AND $field='$text'))";
						}
					} else {
						if ( $scheme_field_info->{'type'} eq 'integer' ) {
							push @sqry, "(id IN ($joined_table AND CAST($field AS int) $operator '$text'))";
						} else {
							push @sqry, "(id IN ($joined_table AND $field $operator '$text'))";
						}
					}
				}
			}
		}
		my $brace = @sqry ? '(' : '';
		if (@lqry) {
			$" = ' OR ';
			my $modify;
			if ( $q->param('c1') eq 'AND' ) {
				$modify = "GROUP BY id HAVING count(id)=" . scalar @lqry;
			}
			my $lqry =
"id IN (select distinct(id) FROM $system->{'view'} LEFT JOIN allele_designations ON $system->{'view'}.id=allele_designations.isolate_id WHERE @lqry $modify)";
			if ( $qry =~ /\(\)$/ ) {
				$qry = "SELECT * FROM $system->{'view'} WHERE $brace$lqry";
			} else {
				$qry .= " AND $brace($lqry)";
			}
		}
		if (@lqry_blank) {
			$" = ' ' . $q->param('c1') . ' ';
			my $modify = @lqry ? $q->param('c1') : 'AND';
			if ( $qry =~ /\(\)$/ ) {
				$qry = "SELECT * FROM $system->{'view'} WHERE $brace@lqry_blank";
			} else {
				$qry .= " $modify $brace(@lqry_blank)";
			}
		}
		if (@sqry) {
			my $andor = $q->param('c1');
			$" = " $andor ";
			my $sqry = "@sqry";
			if ( $qry =~ /\(\)$/ ) {
				$qry = "SELECT * FROM $system->{'view'} WHERE $sqry";
			} else {
				$qry .= " $andor $sqry";
				$qry .= ')' if ( @lqry or @lqry_blank );
			}
		}
		$qry .= " ORDER BY ";
		if ( $q->param('order') =~ /^la_(.+)\|\|/ || $q->param('order') =~ /^cn_(.+)/ ) {
			$qry .= "l_$1";
		} else {
			$qry .= $q->param('order') || 'id';
		}
		my $dir = $q->param('direction') eq 'descending' ? 'desc' : 'asc';
		$qry .= " $dir,$self->{'system'}->{'view'}.id;";
	} else {
		$qry = $q->param('query');
	}
	if (@errors) {
		$" = '<br />';
		print "<div class=\"box\" id=\"statusbad\"><p>Problem with search criteria:</p>\n";
		print "<p>@errors</p></div>\n";
	} elsif ( $qry !~ /\(\)/ ) {
		my @hidden_attributes;
		push @hidden_attributes, 'c0', 'c1';
		for ( my $i = 1 ; $i <= MAX_ROWS ; $i++ ) {
			push @hidden_attributes, "s$i", "t$i", "y$i", "ls$i", "ly$i", "lt$i";
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
		push @hidden_attributes, 'publication_list';
		push @hidden_attributes, 'linked_sequences';
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
		for ( my $i = 1 ; $i <= MAX_ROWS ; $i++ ) {
			if ( $q->param("t$i") ne '' ) {
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
				$text =~ s/^\s*//;
				$text =~ s/\s*$//;
				$text =~ s/'/\\'/g;
				if (   $text ne '<blank>'
					&& $text ne 'null'
					&& ( $type eq 'integer' )
					&& !BIGSdb::Utils::is_int($text) )
				{
					push @errors, "$field is an integer field.";
					next;
				} elsif ( $text ne '<blank>'
					&& $text ne 'null'
					&& ( $type eq 'float' )
					&& !BIGSdb::Utils::is_float($text) )
				{
					push @errors, "$field is a floating point number field.";
					next;
				} elsif ( $text ne '<blank>'
					&& $text ne 'null'
					&& $type eq 'date'
					&& !BIGSdb::Utils::is_date($text) )
				{
					push @errors, "$field is a date field - should be in yyyy-mm-dd format (or 'today' / 'yesterday').";
					next;
				} elsif ( !$self->is_valid_operator($operator) ) {
					push @errors, "$operator is not a valid operator.";
					next;
				}
				my $modifier = '';
				if ( $i > 1 && !$first_value ) {
					$modifier = " $andor ";
				}
				$first_value = 0;
				if ( $field =~ /(.*) \(id\)$/
					&& !BIGSdb::Utils::is_int($text) )
				{
					push @errors, "$field is an integer field.";
					next;
				}
				if ( any { $field =~ /(.*) \($_\)$/ } qw (id surname first_name affiliation) ) {
					$qry .= $modifier . $self->search_users( $field, $operator, $text, "scheme\_$scheme_id" );
				} else {
					if ( $operator eq 'NOT' ) {
						$qry .= $modifier
						  . (
							( $text eq '<blank>' || $text eq 'null' )
							? "$cleaned is not null"
							: "(NOT upper($cleaned) = upper('$text') OR $cleaned IS NULL)"
						  );
					} elsif ( $operator eq "contains" ) {
						$qry .= $modifier . "upper($cleaned) LIKE upper('\%$text\%')";
					} elsif ( $operator eq "NOT contain" ) {
						$qry .= $modifier . "(NOT upper($cleaned) LIKE upper('\%$text\%') OR $cleaned IS NULL)";
					} elsif ( $operator eq '=' ) {
						if ( $type eq 'text' ) {
							$qry .= $modifier
							  . ( ( $text eq '<blank>' || $text eq 'null' ) ? "$cleaned is null" : "upper($field) = upper('$text')" );
						} else {
							$qry .= $modifier . ( ( $text eq '<blank>' || $text eq 'null' ) ? "$cleaned is null" : "$cleaned = '$text'" );
						}
					} else {
						if ( $type eq 'integer' ) {
							$qry .= $modifier . "CAST($cleaned AS int) $operator '$text'";
						} else {
							$qry .= $modifier . "$cleaned $operator '$text'";
						}
					}
				}
			}
		}
		$qry .= ')';
		my $primary_key =
		  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )->[0];
		if ( $q->param('publication_list') ne '' ) {
			my $pmid = $q->param('publication_list');
			my $ids =
			  $self->{'datastore'}
			  ->run_list_query( "SELECT profile_id FROM profile_refs WHERE scheme_id=? AND pubmed_id=?", $scheme_id, $pmid );
			if ($pmid) {
				$" = "','";
				if ( $qry !~ /WHERE \(\)\s*$/ ) {
					$qry .= " AND ($primary_key IN ('@$ids'))";
				} else {
					$qry = "SELECT * FROM scheme_$scheme_id WHERE ($primary_key IN ('@$ids'))";
				}
			}
		}
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		foreach (@$scheme_fields) {
			if ( $q->param("$_\_list") ne '' ) {
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
		my $dir = $q->param('direction') eq 'descending' ? 'desc' : 'asc';
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
		$" = '<br />';
		print "<div class=\"box\" id=\"statusbad\"><p>Problem with search criteria:</p>\n";
		print "<p>@errors</p></div>\n";
	} elsif ( $qry !~ /\(\)/ ) {
		my @hidden_attributes;
		push @hidden_attributes, 'c0', 'c1';
		for ( my $i = 1 ; $i <= MAX_ROWS ; $i++ ) {
			push @hidden_attributes, "s$i", "t$i", "y$i", "ls$i", "ly$i", "lt$i";
		}
		foreach ( @{ $self->{'xmlHandler'}->get_field_list() } ) {
			push @hidden_attributes, $_ . '_list';
		}
		push @hidden_attributes, qw (publication_list scheme_id);
		$self->paged_display( 'profiles', $qry, '', \@hidden_attributes );
		print "<p />\n";
	} else {
		print
"<div class=\"box\" id=\"statusbad\">Invalid search performed. Try to <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=browse&amp;scheme_id=$scheme_id\">browse all records</a>.</div>\n";
	}
}

sub is_valid_operator {
	my ( $self, $value ) = @_;
	return 1
	  if $value eq '='
		  || $value eq 'contains'
		  || $value eq '>'
		  || $value eq '<'
		  || $value eq 'NOT'
		  || $value eq 'NOT contain';
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	if ( $self->{'curate'} ) {
		return "Isolate query/update - $desc";
	}
	return "Search database - $desc";
}

sub search_users {
	my ( $self, $name, $operator, $text, $table ) = @_;
	my ( $field, $suffix ) = split / /, $name;
	$suffix =~ s/[\(\)\s]//g;
	my $qry = "SELECT id FROM users WHERE ";
	if ( $operator eq 'NOT' ) {
		$qry .= "NOT upper($suffix) = upper('$text')";
	} elsif ( $operator eq "contains" ) {
		$qry .= "upper($suffix) LIKE upper('\%$text\%')";
	} elsif ( $operator eq "NOT contain" ) {
		$qry .= "NOT upper($suffix) LIKE upper('\%$text\%')";
	} elsif ( $operator eq '=' ) {
		if ( $suffix ne 'id' ) {
			$qry .= "upper($suffix) = upper('$text')";
		} else {
			$qry .= "$suffix $operator '$text'";
		}
	} else {
		$qry .= "$suffix $operator '$text'";
	}
	my $ids = $self->{'datastore'}->run_list_query($qry);
	if (@$ids) {
		$" = "' OR $field = '";
		return "($table.$field = '@$ids')";
	} else {
		return "($table.$field = '0')";
	}
}
1;
