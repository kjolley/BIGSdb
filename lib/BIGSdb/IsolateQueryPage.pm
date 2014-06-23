#Written by Keith Jolley
#Copyright (c) 2010-2014, University of Oxford
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
package BIGSdb::IsolateQueryPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::QueryPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use List::MoreUtils qw(any none);
use BIGSdb::QueryPage qw(MAX_ROWS OPERATORS);
use BIGSdb::Page qw(LOCUS_PATTERN SEQ_FLAGS);
use constant WARN_IF_TAKES_LONGER_THAN_X_SECONDS => 5;

sub _ajax_content {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $q      = $self->{'cgi'};
	my $row    = $q->param('row');
	return if !BIGSdb::Utils::is_int($row) || $row > MAX_ROWS || $row < 2;
	if ( $q->param('fields') eq 'provenance' ) {
		my ( $select_items, $labels ) = $self->_get_select_items;
		$self->_print_provenance_fields( $row, 0, $select_items, $labels );
	} elsif ( $q->param('fields') eq 'loci' ) {
		my ( $locus_list, $locus_labels ) = $self->get_field_selection_list( { loci => 1, scheme_fields => 1, sort_labels => 1 } );
		$self->_print_loci_fields( $row, 0, $locus_list, $locus_labels );
	} elsif ( $q->param('fields') eq 'allele_status' ) {
		my ( $locus_list, $locus_labels ) = $self->get_field_selection_list( { loci => 1, scheme_fields => 0, sort_labels => 1 } );
		$self->_print_allele_status_fields( $row, 0, $locus_list, $locus_labels );
	} elsif ( $q->param('fields') eq 'tags' ) {
		my ( $locus_list, $locus_labels ) = $self->get_field_selection_list( { loci => 1, scheme_fields => 0, sort_labels => 1 } );
		$self->_print_locus_tag_fields( $row, 0, $locus_list, $locus_labels );
	}
	return;
}

sub _save_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $guid   = $self->get_guid;
	return if !$guid;
	foreach my $attribute (qw (allele_designations allele_status tag filter)) {
		my $value = $q->param($attribute) ? 'on' : 'off';
		$self->{'prefstore'}->set_general( $guid, $self->{'system'}->{'db'}, "$attribute\_fieldset", $value );
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return $self->{'curate'} ? "Isolate query/update - $desc" : "Search database - $desc";
}

sub print_content {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $q      = $self->{'cgi'};
	my $scheme_info;
	if    ( $q->param('no_header') )    { $self->_ajax_content; return }
	elsif ( $q->param('save_options') ) { $self->_save_options; return }
	my $desc = $self->get_db_description;
	say $self->{'curate'} ? "<h1>Isolate query/update</h1>" : "<h1>Search $desc database</h1>";
	my $qry;

	if ( !defined $q->param('currentpage') || $q->param('First') ) {
		if ( !$q->param('no_js') ) {
			say "<noscript><div class=\"box statusbad\"><p>The dynamic customisation of this interface requires that you enable "
			  . "Javascript in your browser. Alternatively, you can use a <a href=\"$self->{'system'}->{'script_name'}?db="
			  . "$self->{'instance'}&amp;page=query&amp;no_js=1\">non-Javascript version</a> that has 4 combinations "
			  . "of fields.</p></div></noscript>";
		}
		$self->_print_interface;
	}
	$self->_run_query if $q->param('submit') || defined $q->param('query_file');
	return;
}

sub _print_interface {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $prefs  = $self->{'prefs'};
	my $q      = $self->{'cgi'};
	say "<div class=\"box\" id=\"queryform\"><div class=\"scrollable\">";
	say $q->startform;
	$q->param( table => $self->{'system'}->{'view'} );
	say $q->hidden($_) foreach qw (db page table no_js);
	say "<div style=\"white-space:nowrap\">";
	$self->_print_provenance_fields_fieldset;
	$self->_print_display_fieldset;
	say "<div style=\"clear:both\"></div>";
	$self->_print_designations_fieldset;
	$self->_print_allele_status_fieldset;
	$self->_print_tag_fieldset;
	$self->_print_filter_fieldset;
	$self->print_action_fieldset;
	$self->_print_modify_search_fieldset;
	say "</div>";
	say $q->end_form;
	say "</div>\n</div>";
	return;
}

sub _print_provenance_fields_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say "<fieldset style=\"float:left\">\n<legend>Isolate provenance/phenotype fields</legend>";
	my $prov_fields = $q->param('no_js') ? 4 : ( $self->_highest_entered_fields('provenance') || 1 );
	my $display_field_heading = $prov_fields == 1 ? 'none' : 'inline';
	say "<span id=\"prov_field_heading\" style=\"display:$display_field_heading\"><label for=\"prov_andor\">Combine with: </label>";
	say $q->popup_menu( -name => 'prov_andor', -id => 'prov_andor', -values => [qw (AND OR)] );
	say "</span>\n<ul id=\"provenance\">";
	my ( $select_items, $labels ) = $self->_get_select_items;

	for ( 1 .. $prov_fields ) {
		say "<li>";
		$self->_print_provenance_fields( $_, $prov_fields, $select_items, $labels );
		say "</li>";
	}
	say "</ul>\n</fieldset>";
	return;
}

sub _print_display_fieldset {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $prefs  = $self->{'prefs'};
	say "<fieldset id=\"display_fieldset\" style=\"float:left\"><legend>Display/sort options</legend>";
	my ( $order_list, $labels ) = $self->get_field_selection_list( { isolate_fields => 1, loci => 1, scheme_fields => 1 } );
	say "<ul>\n<li><span style=\"white-space:nowrap\">\n<label for=\"order\" class=\"display\">Order by: </label>";
	say $self->popup_menu( -name => 'order', -id => 'order', -values => $order_list, -labels => $labels );
	say $q->popup_menu( -name => 'direction', -values => [ 'ascending', 'descending' ], -default => 'ascending' );
	say "</span></li>\n<li>";
	say $self->get_number_records_control;
	say "</li>\n</ul>\n</fieldset>";
	return;
}

sub _print_designations_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $locus_list, $locus_labels ) = $self->get_field_selection_list( { loci => 1, scheme_fields => 1, sort_labels => 1 } );
	if (@$locus_list) {
		my $display = $q->param('no_js') ? 'block' : 'none';
		print "<fieldset id=\"locus_fieldset\" style=\"float:left;display:$display\" >\n";
		print "<legend>Allele designations/scheme fields</legend><div>\n";
		my $locus_fields = $q->param('no_js') ? 4 : ( $self->_highest_entered_fields('loci') || 1 );
		my $loci_field_heading = $locus_fields == 1 ? 'none' : 'inline';
		print "<span id=\"loci_field_heading\" style=\"display:$loci_field_heading\"><label for=\"c1\">Combine with: </label>\n";
		print $q->popup_menu( -name => 'designation_andor', -id => 'designation_andor', -values => [qw (AND OR)], );
		print "</span>\n<ul id=\"loci\">\n";

		for ( 1 .. $locus_fields ) {
			say "<li>";
			$self->_print_loci_fields( $_, $locus_fields, $locus_list, $locus_labels );
			say "</li>";
		}
		say "</ul>\n</div></fieldset>";
	}
	return;
}

sub _print_allele_status_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $locus_list, $locus_labels ) = $self->get_field_selection_list( { loci => 1, scheme_fields => 0, sort_labels => 1 } );
	if (@$locus_list) {
		my $display = $q->param('no_js') ? 'block' : 'none';
		say "<fieldset id=\"allele_status_fieldset\" style=\"float:left;display:$display\">";
		say "<legend>Allele designation status</legend><div>";
		my $locus_fields = $q->param('no_js') ? 4 : ( $self->_highest_entered_fields('allele_status') || 1 );
		my $heading_display = $locus_fields == 1 ? 'none' : 'inline';
		say
"<span id=\"allele_status_field_heading\" style=\"display:$heading_display\"><label for=\"designation_andor\">Combine with: </label>";
		say $q->popup_menu( -name => 'status_andor', -id => 'status_andor', -values => [qw (AND OR)] );
		say "</span>\n<ul id=\"allele_status\">";

		for ( 1 .. $locus_fields ) {
			say "<li>";
			$self->_print_allele_status_fields( $_, $locus_fields, $locus_list, $locus_labels );
			say "</li>";
		}
		say "</ul>\n</div></fieldset>";
	}
	return;
}

sub _print_tag_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	return if !$self->{'datastore'}->run_simple_query("SELECT EXISTS(SELECT * FROM allele_sequences)")->[0];
	my ( $locus_list, $locus_labels ) = $self->get_field_selection_list( { loci => 1, scheme_fields => 0, sort_labels => 1 } );
	if (@$locus_list) {
		my $display = $q->param('no_js') ? 'block' : 'none';
		say "<fieldset id=\"tag_fieldset\" style=\"float:left;display:$display\">";
		say "<legend>Tagged sequence status</legend><div>";
		my $locus_tag_fields = $q->param('no_js') ? 4 : ( $self->_highest_entered_fields('tags') || 1 );
		my $locus_tags_heading = $locus_tag_fields == 1 ? 'none' : 'inline';
		say "<span id=\"locus_tags_heading\" style=\"display:$locus_tags_heading\"><label for=\"designation_andor\">Combine with: </label>";
		say $q->popup_menu( -name => 'tag_andor', -id => 'tag_andor', -values => [qw (AND OR)] );
		say "</span>\n<ul id=\"tags\">";

		for ( 1 .. $locus_tag_fields ) {
			say "<li>";
			$self->_print_locus_tag_fields( $_, $locus_tag_fields, $locus_list, $locus_labels );
			say "</li>";
		}
		say "</ul></div>\n</fieldset>";
		$self->{'tag_fieldset_exists'} = 1;
	}
	return;
}

sub _print_filter_fieldset {
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
						labels  => \%dropdownlabels,
						tooltip => "$display_field filter - Select $a_or_an $display_field to filter your search to only those "
						  . "isolates that match the selected $display_field.",
						capitalize_first => 1
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
							tooltip => "$field\..$extended_attribute filter - Select $a_or_an $extended_attribute to filter your "
							  . "search to only those isolates that match the selected $field."
						}
					  );
				}
			}
		}
	}
	if ( $self->{'prefs'}->{'dropdownfields'}->{'Publications'} ) {
		my $buffer = $self->get_isolate_publication_filter( { any => 1, multiple => 1 } );
		push @filters, $buffer if $buffer;
	}
	my $buffer = $self->get_project_filter( { any => 1, multiple => 1 } );
	push @filters, $buffer if $buffer;
	my $profile_filters = $self->_get_profile_filters;
	push @filters, @$profile_filters;
	my $linked_seqs = $self->{'datastore'}->run_simple_query("SELECT EXISTS(SELECT id FROM sequence_bin)")->[0];
	if ($linked_seqs) {
		my @values = ( 'Any sequence data', 'No sequence data' );
		if ( $self->{'system'}->{'seqbin_size_threshold'} ) {
			foreach my $value ( split /,/, $self->{'system'}->{'seqbin_size_threshold'} ) {
				push @values, "Sequence bin size >= $value Mbp";
			}
		}
		push @filters,
		  $self->get_filter( 'linked_sequences', \@values,
			{ text => 'Sequence bin', tooltip => 'sequence bin filter - Filter by whether the isolate record has sequence data attached.' }
		  );
	}
	if (@filters) {
		my $display = $q->param('no_js') ? 'block' : 'none';
		print "<fieldset id=\"filter_fieldset\" style=\"float:left;display:$display\"><legend>Filters</legend>\n";
		print "<div><ul>\n";
		print "<li><span style=\"white-space:nowrap\">$_</span></li>" foreach (@filters);
		print "</ul></div>\n</fieldset>";
		$self->{'filter_fieldset_exists'} = 1;
	}
	return;
}

sub _print_modify_search_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say qq(<div class="panel">);
	say qq(<a class="trigger" id="close_trigger" href="#">[X]</a>);
	say "<h2>Modify form parameters</h2>";
	say "<p>Click to add or remove additional query terms:</p>";
	say "<ul>";
	my $locus_fieldset_display = $self->{'prefs'}->{'allele_designations_fieldset'}
	  || $self->_highest_entered_fields('loci') ? 'Hide' : 'Show';
	say qq(<li><a href="" class="button" id="show_allele_designations">$locus_fieldset_display</a>);
	say "Allele designations/scheme field values</li>";
	my $allele_status_fieldset_display = $self->{'prefs'}->{'allele_status_fieldset'}
	  || $self->_highest_entered_fields('allele_status') ? 'Hide' : 'Show';
	say qq(<li><a href="" class="button" id="show_allele_status">$allele_status_fieldset_display</a>);
	say "Allele designation status</li>";

	if ( $self->{'tag_fieldset_exists'} ) {
		my $tag_fieldset_display = $self->{'prefs'}->{'tag_fieldset'} || $self->_highest_entered_fields('tags') ? 'Hide' : 'Show';
		say qq(<li><a href="" class="button" id="show_tags">$tag_fieldset_display</a>);
		say "Tagged sequence status</li>";
	}
	if ( $self->{'filter_fieldset_exists'} ) {
		my $filter_fieldset_display = $self->{'prefs'}->{'filter_fieldset'} || $self->filters_selected ? 'Hide' : 'Show';
		say qq(<li><a href="" class="button" id="show_filters">$filter_fieldset_display</a>);
		say "Filters</li>";
	}
	say "</ul>";
	say qq(<a id="save_options" class="button" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;)
	  . qq(save_options=1" style="display:none">Save options</a><br />);
	say "</div>";
	say qq(<a class="trigger" id="panel_trigger" href="" style="display:none">Modify<br />form<br />options</a>);
	return;
}

sub _get_profile_filters {
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	my @filters;
	my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	foreach my $scheme (@$schemes) {
		my $field = "scheme_$scheme->{'id'}\_profile_status";
		if ( $self->{'prefs'}->{'dropdownfields'}->{$field} ) {
			push @filters,
			  $self->get_filter(
				$field,
				[ 'complete', 'incomplete', 'partial', 'started', 'not started' ],
				{
					text    => "$scheme->{'description'} profiles",
					tooltip => "$scheme->{'description'} profile completion filter - Select whether the isolates should "
					  . "have complete, partial, or unstarted profiles.",
					capitalize_first => 1
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
						text    => "$field ($scheme->{'description'})",
						tooltip => "$field ($scheme->{'description'}) filter - Select $a_or_an $field to filter your search "
						  . "to only those isolates that match the selected $field.",
						capitalize_first => 1
					}
				  ) if @$values;
			}
		}
	}
	return \@filters;
}

sub _print_provenance_fields {
	my ( $self, $row, $max_rows, $select_items, $labels ) = @_;
	my $q = $self->{'cgi'};
	say "<span style=\"white-space:nowrap\">";
	say $q->popup_menu( -name => "prov_field$row", -values => $select_items, -labels => $labels, -class => 'fieldlist' );
	say $q->popup_menu( -name => "prov_operator$row", -values => [OPERATORS] );
	say $q->textfield( -name => "prov_value$row", -class => 'value_entry', -placeholder => 'Enter value...' );
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		if ( !$q->param('no_js') ) {
			say "<a id=\"add_fields\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;"
			  . "fields=provenance&amp;row=$next_row&amp;no_header=1\" data-rel=\"ajax\" class=\"button\">+</a>";
			say "<a class=\"tooltip\" id=\"prov_tooltip\" title=\"\">&nbsp;<i>i</i>&nbsp;</a>";
		}
	}
	say "</span>\n";
	return;
}

sub _print_allele_status_fields {
	my ( $self, $row, $max_rows, $locus_list, $locus_labels ) = @_;
	unshift @$locus_list, 'any locus';
	unshift @$locus_list, '';
	$locus_labels->{''} = ' ';    #Required for HTML5 validation.
	my $q = $self->{'cgi'};
	say "<span style=\"white-space:nowrap\">";
	say $self->popup_menu(
		-name   => "allele_sequence_field$row",
		-id     => "allele_sequence_field$row",
		-values => $locus_list,
		-labels => $locus_labels,
		-class  => 'fieldlist'
	);
	print ' is ';
	my $values = [ '', 'provisional', 'confirmed' ];
	my %labels = ( '' => ' ' );    #Required for HTML5 validation.
	say $q->popup_menu( -name => "allele_sequence_value$row", -id => "allele_sequence_value$row", -values => $values, -labels => \%labels );

	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		if ( !$q->param('no_js') ) {
			say "<a id=\"add_allele_status\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;"
			  . "fields=allele_status&amp;row=$next_row&amp;no_header=1\" data-rel=\"ajax\" class=\"button\">+</a>"
			  . " <a class=\"tooltip\" id=\"allele_status_tooltip\" title=\"\">&nbsp;<i>i</i>&nbsp;</a>";
		}
	}
	say "</span>";
	return;
}

sub _print_loci_fields {
	my ( $self, $row, $max_rows, $locus_list, $locus_labels ) = @_;
	unshift @$locus_list, '';
	$locus_labels->{''} = ' ';    #Required for HTML5 validation.
	my $q = $self->{'cgi'};
	say "<span style=\"white-space:nowrap\">";
	say $self->popup_menu(
		-name   => "designation_field$row",
		-id     => "designation_field$row",
		-values => $locus_list,
		-labels => $locus_labels,
		-class  => 'fieldlist'
	);
	say $q->popup_menu( -name => "designation_operator$row", -id => "designation_operator$row", -values => [OPERATORS] );
	say $q->textfield(
		-name        => "designation_value$row",
		-id          => "designation_value$row",
		-class       => 'value_entry',
		-placeholder => 'Enter value...'
	);

	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		if ( !$q->param('no_js') ) {
			say "<a id=\"add_loci\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;"
			  . "fields=loci&amp;row=$next_row&amp;no_header=1\" data-rel=\"ajax\" class=\"button\">+</a>"
			  . " <a class=\"tooltip\" id=\"loci_tooltip\" title=\"\">&nbsp;<i>i</i>&nbsp;</a>";
		}
	}
	say "</span>";
	return;
}

sub _print_locus_tag_fields {
	my ( $self, $row, $max_rows, $locus_list, $locus_labels ) = @_;
	unshift @$locus_list, 'any locus';
	unshift @$locus_list, '';
	my $q = $self->{'cgi'};
	print "<span style=\"white-space:nowrap\">\n";
	print $self->popup_menu(
		-name   => "tag_field$row",
		-id     => "tag_field$row",
		-values => $locus_list,
		-labels => $locus_labels,
		-class  => 'fieldlist'
	);
	print ' is ';
	my @values = qw(untagged tagged complete incomplete);
	push @values, "flagged: $_" foreach ( 'any', 'none', SEQ_FLAGS );
	unshift @values, '';
	my %labels = ( '' => ' ' );    #Required for HTML5 validation.
	say $q->popup_menu( -name => "tag_value$row", -id => "tag_value$row", values => \@values, -labels => \%labels );

	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		if ( !$q->param('no_js') ) {
			say "<a id=\"add_tags\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;"
			  . "fields=tags&amp;row=$next_row&amp;no_header=1\" data-rel=\"ajax\" class=\"button\">+</a>"
			  . " <a class=\"tooltip\" id=\"tag_tooltip\" title=\"\">&nbsp;<i>i</i>&nbsp;</a>";
		}
	}
	say "</span>";
	return;
}

sub _run_query {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $qry;
	my @errors;
	my $extended   = $self->get_extended_attributes;
	my $start_time = time;
	if ( !defined $q->param('query_file') ) {
		$qry = $self->_generate_query_for_provenance_fields( \@errors );
		$qry = $self->_modify_query_for_filters( $qry, $extended );
		$qry = $self->_modify_query_for_designations( $qry, \@errors );
		$qry = $self->_modify_query_for_tags( $qry, \@errors );
		$qry = $self->_modify_query_for_designation_status( $qry, \@errors );
		$qry .= " ORDER BY ";
		if ( defined $q->param('order') && ( $q->param('order') =~ /^la_(.+)\|\|/ || $q->param('order') =~ /^cn_(.+)/ ) ) {
			$qry .= "l_$1";
		} else {
			$qry .= $q->param('order') || 'id';
		}
		my $dir = ( defined $q->param('direction') && $q->param('direction') eq 'descending' ) ? 'desc' : 'asc';
		$qry .= " $dir,$self->{'system'}->{'view'}.id;";
	} else {
		$qry = $self->get_query_from_temp_file( $q->param('query_file') );
	}
	if (@errors) {
		local $" = '<br />';
		print "<div class=\"box\" id=\"statusbad\"><p>Problem with search criteria:</p>\n";
		print "<p>@errors</p></div>\n";
	} elsif ( $qry !~ /\(\)/ ) {
		my @hidden_attributes;
		push @hidden_attributes, qw (prov_andor designation_andor tag_andor status_andor);
		for ( 1 .. MAX_ROWS ) {
			push @hidden_attributes, "prov_field$_", "prov_value$_", "prov_operator$_", "designation_field$_",
			  "designation_operator$_", "designation_value$_", "tag_field$_", "tag_value$_", "allele_sequence_field$_",
			  "allele_sequence_value$_";
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
		my $args = { table => $self->{'system'}->{'view'}, query => $qry, hidden_attributes => \@hidden_attributes };
		$args->{'passed_qry_file'} = $q->param('query_file') if defined $q->param('query_file');
		$self->paged_display($args);
	} else {
		say "<div class=\"box\" id=\"statusbad\">Invalid search performed.  Try to <a href=\"$self->{'system'}->{'script_name'}?db="
		  . "$self->{'instance'}&amp;page=browse\">browse all records</a>.</div>";
	}
	my $elapsed = time - $start_time;
	if ( $elapsed > WARN_IF_TAKES_LONGER_THAN_X_SECONDS && $self->{'datastore'}->{'scheme_not_cached'} ) {
		$logger->warn( "$self->{'instance'}: Query took $elapsed seconds.  Schemes are not cached for this database.  You should "
			  . "consider running the update_scheme_caches.pl script regularly against this database to create these caches." );
	}
	return;
}

sub _generate_query_for_provenance_fields {
	my ( $self, $errors_ref ) = @_;
	my $q           = $self->{'cgi'};
	my $view        = $self->{'system'}->{'view'};
	my $qry         = "SELECT * FROM $view WHERE (";
	my $andor       = $q->param('prov_andor') || 'AND';
	my $first_value = 1;
	foreach my $i ( 1 .. MAX_ROWS ) {
		if ( defined $q->param("prov_value$i") && $q->param("prov_value$i") ne '' ) {
			my $field = $q->param("prov_field$i");
			$field =~ s/^f_//;
			my @groupedfields = $self->get_grouped_fields($field);
			my $thisfield     = $self->{'xmlHandler'}->get_field_attributes($field);
			my $extended_isolate_field;
			if ( $field =~ /^e_(.*)\|\|(.*)/ ) {
				$extended_isolate_field = $1;
				$field                  = $2;
				my $att_info = $self->{'datastore'}->run_query(
					"SELECT * FROM isolate_field_extended_attributes WHERE isolate_field=? AND attribute=?",
					[ $extended_isolate_field, $field ],
					{ fetch => 'row_hashref' }
				);
				$thisfield->{'type'} = $att_info->{'value_format'};
				$thisfield->{'type'} = 'int' if $thisfield->{'type'} eq 'integer';
			}
			my $operator = $q->param("prov_operator$i") // '=';
			my $text = $q->param("prov_value$i");
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

sub _grouped_field_query {
	my ( $self, $groupedfields, $data, $errors_ref ) = @_;
	my $text     = $data->{'text'};
	my $operator = $data->{'operator'} // '=';
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
	} elsif ( $operator eq "starts with" ) {
		foreach (@$groupedfields) {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($_);
			$buffer .= ' OR ' if $_ ne $groupedfields->[0];
			if ( $thisfield->{'type'} ne 'text' ) {
				$buffer .= "CAST($view.$_ AS text) LIKE E'$text\%'";
			} else {
				$buffer .= "upper($view.$_) LIKE upper(E'$text\%')";
			}
		}
	} elsif ( $operator eq "ends with" ) {
		foreach (@$groupedfields) {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($_);
			$buffer .= ' OR ' if $_ ne $groupedfields->[0];
			if ( $thisfield->{'type'} ne 'text' ) {
				$buffer .= "CAST($view.$_ AS text) LIKE E'\%$text'";
			} else {
				$buffer .= "upper($view.$_) LIKE upper(E'\%$text')";
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

sub _modify_query_for_filters {
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
	$self->_modify_query_by_membership( { qry_ref => \$qry, table => 'refs', param => 'publication_list', query_field => 'pubmed_id' } );
	$self->_modify_query_by_membership(
		{ qry_ref => \$qry, table => 'project_members', param => 'project_list', query_field => 'project_id' } );
	if ( $q->param('linked_sequences_list') ) {
		my $not         = '';
		my $size_clause = '';
		if ( $q->param('linked_sequences_list') eq 'No sequence data' ) {
			$not = ' NOT ';
		} elsif ( $q->param('linked_sequences_list') =~ />= ([\d\.]+) Mbp/ ) {
			my $size = $1 * 1000000;    #Mbp
			$size_clause = " AND seqbin_stats.total_length >= $size";
		}
		if ( $qry !~ /WHERE \(\)\s*$/ ) {
			$qry .= " AND (${not}EXISTS (SELECT 1 FROM seqbin_stats WHERE seqbin_stats.isolate_id = $view.id$size_clause))";
		} else {
			$qry = "SELECT * FROM $view WHERE (${not}EXISTS (SELECT 1 FROM seqbin_stats WHERE seqbin_stats.isolate_id = "
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
				  . "($allele_clause) GROUP BY isolate_id HAVING COUNT(DISTINCT (locus))";
				my $locus_count = @$scheme_loci;
				if    ( $param eq 'complete' ) { $clause .= "=$locus_count))" }
				elsif ( $param eq 'partial' )  { $clause .= "<$locus_count))" }
				elsif ( $param eq 'started' )  { $clause .= '>0))' }
				elsif ( $param eq 'incomplete' ) {
					$clause .= "<$locus_count) OR NOT (EXISTS (SELECT isolate_id FROM allele_designations WHERE "
					  . "$view.id=allele_designations.isolate_id AND ($allele_clause) GROUP BY isolate_id )))";
				} else {
					$clause = "(NOT (EXISTS (SELECT isolate_id FROM allele_designations WHERE $view.id=allele_designations.isolate_id "
					  . "AND ($allele_clause) GROUP BY isolate_id )))";
				}
				if ( $qry !~ /WHERE \(\)\s*$/ ) {
					$qry .= "AND $clause";
				} else {
					$qry = "SELECT * FROM $view WHERE $clause";
				}
			}
		}
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		foreach (@$scheme_fields) {
			my $field = $_;    #Copy field value rather than use reference directly since we modify it and it may be needed elsewhere.
			if ( ( $q->param("scheme_$scheme_id\_$field\_list") // '' ) ne '' ) {
				my $value = $q->param("scheme_$scheme_id\_$field\_list");
				$value =~ s/'/\\'/g;
				my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
				my $isolate_scheme_field_view = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
				$field = "$isolate_scheme_field_view\.$field";
				local $" = ' AND ';
				my $temp_qry = "SELECT $isolate_scheme_field_view.id FROM $isolate_scheme_field_view";
				$value =~ s/'/\\'/g;
				my $clause =
				  $scheme_field_info->{'type'} eq 'text'
				  ? "($view.id IN ($temp_qry WHERE UPPER($field) = UPPER(E'$value')))"
				  : "($view.id IN  ($temp_qry WHERE CAST($field AS int) = E'$value'))";

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
	my ( $self, $args ) = @_;
	my ( $qry_ref, $table, $param, $query_field ) = @{$args}{qw(qry_ref table param query_field)};
	my $q = $self->{'cgi'};
	return if !$q->param($param);
	my @list = $q->param($param);
	my $subqry;
	my $view = $self->{'system'}->{'view'};
	if ( any { $_ eq 'any' } @list ) {
		$subqry = "$view.id IN (SELECT isolate_id FROM $table)";
	}
	if ( any { $_ eq 'none' } @list ) {
		$subqry .= ' OR ' if $subqry;
		$subqry .= "$view.id NOT IN (SELECT isolate_id FROM $table)";
	}
	if ( any { BIGSdb::Utils::is_int($_) } @list ) {
		my @int_list = grep { BIGSdb::Utils::is_int($_) } @list;
		$subqry .= ' OR ' if $subqry;
		local $" = ',';
		$subqry .= "$view.id IN (SELECT isolate_id FROM $table WHERE $query_field IN (@int_list))";
	}
	if ($subqry) {
		if ( $$qry_ref !~ /WHERE \(\)\s*$/ ) {
			$$qry_ref .= " AND ($subqry)";
		} else {
			$$qry_ref = "SELECT * FROM $view WHERE ($subqry)";
		}
	}
	return;
}

sub _modify_query_for_designations {
	my ( $self, $qry, $errors_ref ) = @_;
	my $q    = $self->{'cgi'};
	my $view = $self->{'system'}->{'view'};
	my ( %lqry, @lqry_blank, %combo );
	my $pattern     = LOCUS_PATTERN;
	my $andor       = ( $q->param('designation_andor') // '' ) eq 'AND' ? ' AND ' : ' OR ';
	my $qry_started = $qry =~ /\(\)$/ ? 0 : 1;
	foreach my $i ( 1 .. MAX_ROWS ) {

		if ( defined $q->param("designation_value$i") && $q->param("designation_value$i") ne '' ) {
			if ( $q->param("designation_field$i") =~ /$pattern/ ) {
				my $locus            = $1;
				my $locus_info       = $self->{'datastore'}->get_locus_info($locus);
				my $unmodified_locus = $locus;
				$locus =~ s/'/\\'/g;
				my $operator = $q->param("designation_operator$i") // '=';
				my $text = $q->param("designation_value$i");
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
		if ( defined $q->param("designation_value$i") && $q->param("designation_value$i") ne '' ) {
			if ( $q->param("designation_field$i") =~ /^s_(\d+)_(.*)/ ) {
				my ( $scheme_id, $field ) = ( $1, $2 );
				my $operator          = $q->param("designation_operator$i") // '=';
				my $text              = $q->param("designation_value$i");
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
				my $isolate_scheme_field_view = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
				$field = "$isolate_scheme_field_view.$field";
				my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
				my $temp_qry    = "SELECT $isolate_scheme_field_view.id FROM $isolate_scheme_field_view";
				$text =~ s/'/\\'/g;
				if ( $operator eq 'NOT' ) {
					if ( $text eq 'null' ) {
						push @sqry, "($view.id NOT IN ($temp_qry WHERE $field IS NULL) AND $view.id IN ($temp_qry))";
					} else {
						push @sqry,
						  $scheme_field_info->{'type'} eq 'integer'
						  ? "($view.id NOT IN ($temp_qry WHERE CAST($field AS text)= E'$text' AND $view.id IN ($temp_qry)))"
						  : "($view.id NOT IN ($temp_qry WHERE upper($field)=upper(E'$text') AND $view.id IN ($temp_qry)))";
					}
				} elsif ( $operator eq "contains" ) {
					push @sqry,
					  $scheme_field_info->{'type'} eq 'integer'
					  ? "($view.id IN ($temp_qry WHERE CAST($field AS text) ~* E'$text'))"
					  : "($view.id IN ($temp_qry WHERE $field ~* E'$text'))";
				} elsif ( $operator eq "starts with" ) {
					push @sqry,
					  $scheme_field_info->{'type'} eq 'integer'
					  ? "($view.id IN ($temp_qry WHERE CAST($field AS text) LIKE E'$text\%'))"
					  : "($view.id IN ($temp_qry WHERE $field ILIKE E'$text\%'))";
				} elsif ( $operator eq "ends with" ) {
					push @sqry,
					  $scheme_field_info->{'type'} eq 'integer'
					  ? "($view.id IN ($temp_qry WHERE CAST($field AS text) LIKE E'\%$text'))"
					  : "($view.id IN ($temp_qry WHERE $field ILIKE E'\%$text'))";
				} elsif ( $operator eq "NOT contain" ) {
					push @sqry,
					  $scheme_field_info->{'type'} eq 'integer'
					  ? "($view.id IN ($temp_qry WHERE CAST($field AS text) !~* E'$text'))"
					  : "($view.id IN ($temp_qry WHERE $field !~* E'$text'))";
				} elsif ( $operator eq '=' ) {
					if ( $text eq 'null' ) {
						push @lqry_blank, "($view.id IN ($temp_qry WHERE $field IS NULL) OR $view.id NOT IN ($temp_qry))";
					} else {
						push @sqry, $scheme_field_info->{'type'} eq 'text'
						  ? "($view.id IN ($temp_qry WHERE upper($field)=upper(E'$text')))"
						  : "($view.id IN ($temp_qry WHERE $field=E'$text'))";
					}
				} else {
					if ( $text eq 'null' ) {
						push @$errors_ref, "$operator is not a valid operator for comparing null values.";
						next;
					}
					if ( $scheme_field_info->{'type'} eq 'integer' ) {
						push @sqry, "($view.id IN ($temp_qry WHERE CAST($field AS int) $operator E'$text'))";
					} else {
						push @sqry, "($view.id IN ($temp_qry WHERE $field $operator E'$text'))";
					}
				}
			}
		}
	}
	my $brace = @sqry ? '(' : '';
	if ( keys %lqry ) {
		local $" = ' OR ';
		my $modify = '';
		if ( ( $q->param('designation_andor') // '' ) eq 'AND' ) {
			$modify = "GROUP BY $view.id HAVING count($view.id)=" . scalar keys %lqry;
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
		local $" = ' ' . $q->param('designation_andor') . ' ';
		my $modify = scalar keys %lqry ? $q->param('designation_andor') : 'AND';
		if ( $qry =~ /\(\)$/ ) {
			$qry = "SELECT * FROM $view WHERE $brace@lqry_blank";
		} else {
			$qry .= keys %lqry ? " $modify" : ' AND';
			$qry .= " $brace(@lqry_blank)";
		}
	}
	if (@sqry) {
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

sub _modify_query_for_tags {
	my ( $self, $qry, $errors_ref ) = @_;
	my $q    = $self->{'cgi'};
	my $view = $self->{'system'}->{'view'};
	my @tag_queries;
	my $pattern = LOCUS_PATTERN;
	my $set_id  = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? "AND (locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes "
	  . "WHERE set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';
	foreach my $i ( 1 .. MAX_ROWS ) {

		if ( ( $q->param("tag_field$i") // '' ) ne '' && ( $q->param("tag_value$i") // '' ) ne '' ) {
			my $action = $q->param("tag_value$i");
			my $locus;
			if ( $q->param("tag_field$i") ne 'any locus' ) {
				if ( $q->param("tag_field$i") =~ /$pattern/ ) {
					$locus = $1;
				}
				if ( !$self->{'datastore'}->is_locus($locus) ) {
					push @$errors_ref, "Invalid locus selected.";
					next;
				}
			} else {
				$locus = 'any locus';
			}
			$locus =~ s/'/\\'/g;
			my $temp_qry;
			my $locus_clause = $locus eq 'any locus' ? "(locus IS NOT NULL $set_clause)" : "(locus=E'$locus' $set_clause)";
			if ( $action eq 'untagged' ) {
				$temp_qry = "$view.id NOT IN (SELECT DISTINCT isolate_id FROM allele_sequences WHERE $locus_clause)";
			} elsif ( $action eq 'tagged' ) {
				$temp_qry = "$view.id IN (SELECT isolate_id FROM allele_sequences WHERE $locus_clause)";
			} elsif ( $action eq 'complete' ) {
				$temp_qry = "$view.id IN (SELECT isolate_id FROM allele_sequences WHERE $locus_clause AND complete)";
			} elsif ( $action eq 'incomplete' ) {
				$temp_qry = "$view.id IN (SELECT isolate_id FROM allele_sequences WHERE $locus_clause AND NOT complete)";
			} elsif ( $action =~ /^flagged: ([\w\s:]+)$/ ) {
				my $flag              = $1;
				my $flag_joined_table = "sequence_flags LEFT JOIN allele_sequences ON sequence_flags.id = allele_sequences.id";
				if ( $flag eq 'any' ) {
					$temp_qry = "$view.id IN (SELECT allele_sequences.isolate_id FROM $flag_joined_table WHERE $locus_clause)";
				} elsif ( $flag eq 'none' ) {
					if ( $locus eq 'any locus' ) {
						push @$errors_ref, "Searching for any locus not flagged is not supported.  Choose a specific locus.";
					} else {
						$temp_qry = "$view.id IN (SELECT isolate_id FROM allele_sequences WHERE $locus_clause) AND id NOT IN "
						  . "(SELECT isolate_id FROM $flag_joined_table WHERE $locus_clause)";
					}
				} else {
					$temp_qry =
					  "$view.id IN (SELECT allele_sequences.isolate_id FROM $flag_joined_table WHERE $locus_clause AND flag='$flag')";
				}
			}
			push @tag_queries, $temp_qry if $temp_qry;
		}
	}
	if (@tag_queries) {
		my $andor = ( any { $q->param('tag_andor') eq $_ } qw (AND OR) ) ? $q->param('tag_andor') : '';
		local $" = " $andor ";
		if ( $qry !~ /WHERE \(\)\s*$/ ) {
			$qry .= " AND (@tag_queries)";
		} else {
			$qry = "SELECT * FROM $view WHERE (@tag_queries)";
		}
	}
	return $qry;
}

sub _modify_query_for_designation_status {
	my ( $self, $qry, $errors_ref ) = @_;
	my $q    = $self->{'cgi'};
	my $view = $self->{'system'}->{'view'};
	my @status_queries;
	my $pattern = LOCUS_PATTERN;
	my $set_id  = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? "AND (locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes "
	  . "WHERE set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';
	foreach my $i ( 1 .. MAX_ROWS ) {

		if (   defined $q->param("allele_sequence_field$i")
			&& $q->param("allele_sequence_field$i") ne ''
			&& defined $q->param("allele_sequence_value$i")
			&& $q->param("allele_sequence_value$i") ne '' )
		{
			my $action = $q->param("allele_sequence_field$i");
			my $locus;
			if ( $q->param("allele_sequence_field$i") ne 'any locus' ) {
				if ( $q->param("allele_sequence_field$i") =~ /$pattern/ ) {
					$locus = $1;
				}
				if ( !$self->{'datastore'}->is_locus($locus) ) {
					push @$errors_ref, "Invalid locus selected.";
					next;
				}
			} else {
				$locus = 'any locus';
			}
			my $status = $q->param("allele_sequence_value$i");
			if ( none { $status eq $_ } qw (provisional confirmed) ) {
				push @$errors_ref, "Invalid status selected.";
				next;
			}
			$locus =~ s/'/\\'/g;
			my $temp_qry;
			my $locus_clause = $locus eq 'any locus' ? 'locus IS NOT NULL' : "locus=E'$locus'";
			push @status_queries, "$view.id IN (SELECT isolate_id FROM allele_designations WHERE (allele_designations.$locus_clause "
			  . "AND status='$status' $set_clause))";
		}
	}
	if (@status_queries) {
		my $andor = ( any { $q->param('status_andor') eq $_ } qw (AND OR) ) ? $q->param('status_andor') : '';
		local $" = " $andor ";
		if ( $qry !~ /WHERE \(\)\s*$/ ) {
			$qry .= " AND (@status_queries)";
		} else {
			$qry = "SELECT * FROM $view WHERE (@status_queries)";
		}
	}
	return $qry;
}

sub get_javascript {
	my ($self) = @_;
	my $locus_fieldset_display = $self->{'prefs'}->{'allele_designations_fieldset'}
	  || $self->_highest_entered_fields('loci') ? 'inline' : 'none';
	my $allele_status_fieldset_display = $self->{'prefs'}->{'allele_status_fieldset'}
	  || $self->_highest_entered_fields('allele_status') ? 'inline' : 'none';
	my $tag_fieldset_display    = $self->{'prefs'}->{'tag_fieldset'}    || $self->_highest_entered_fields('tags') ? 'inline' : 'none';
	my $filter_fieldset_display = $self->{'prefs'}->{'filter_fieldset'} || $self->filters_selected                ? 'inline' : 'none';
	my $buffer                  = $self->SUPER::get_javascript;
	$buffer .= << "END";
\$(function () {
  	\$('#query_modifier').css({display:"block"});
   	\$('#locus_fieldset').css({display:"$locus_fieldset_display"});
   	\$('#allele_status_fieldset').css({display:"$allele_status_fieldset_display"});
   	\$('#tag_fieldset').css({display:"$tag_fieldset_display"});
   	\$('#filter_fieldset').css({display:"$filter_fieldset_display"});
  	\$('#prov_tooltip,#loci_tooltip').tooltip({ content: "<h3>Search values</h3><p>Empty field "
  		+ "values can be searched using the term 'null'. </p><h3>Number of fields</h3><p>Add more fields by clicking the '+' button."
  		+ "</p><h3>Query modifier</h3><p>Select 'AND' for the isolate query to match ALL search terms, 'OR' to match ANY of these terms."
  		+ "</p>" });
  	\$('#tag_tooltip,#allele_status_tooltip').tooltip({ content: "<h3>Number of fields</h3><p>Add more fields by clicking the '+' "
  		+ "button.</p>" });	
  	if (! Modernizr.touch){
  	 	\$('.multiselect').multiselect({noneSelectedText:'&nbsp;'});
  	}
  	
  	\$("#show_allele_designations").click(function() {
  		if(\$(this).text() == 'Hide'){\$('[id^="designation"]').val('')}
		\$("#locus_fieldset").toggle(100);
		\$(this).text(\$(this).text() == 'Show' ? 'Hide' : 'Show');
		\$("a#save_options").fadeIn();
		return false;
	});
	 \$("#show_allele_status").click(function() {
  		if(\$(this).text() == 'Hide'){\$('[id^="allele_sequence"]').val('')}
		\$("#allele_status_fieldset").toggle(100);
		\$(this).text(\$(this).text() == 'Show' ? 'Hide' : 'Show');
		\$("a#save_options").fadeIn();
		return false;
	});
	\$("#show_tags").click(function() {
  		if(\$(this).text() == 'Hide'){\$('[id^="tag"]').val('')}
		\$("#tag_fieldset").toggle(100);
		\$(this).text(\$(this).text() == 'Show' ? 'Hide' : 'Show');
		\$("a#save_options").fadeIn();
		return false;
	});
	\$("#show_filters").click(function() {
		if(\$(this).text() == 'Hide'){
			if (! Modernizr.touch){
				\$('.multiselect').multiselect("uncheckAll");
			}
			\$('[id\$="_list"]').val('');
		}
 		\$("#filter_fieldset").toggle(100);
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
		var allele_designations = \$("#show_allele_designations").text() == 'Show' ? 0 : 1;
		var allele_status = \$("#show_allele_status").text() == 'Show' ? 0 : 1;
		var tag = \$("#show_tags").text() == 'Show' ? 0 : 1;
		var filter = \$("#show_filters").text() == 'Show' ? 0 : 1;
	  	\$(this).attr('href', function(){  	
	  		\$("a#save_options").text('Saving ...');
	  		var new_url = this.href + "&allele_designations=" + allele_designations + "&allele_status=" + allele_status 
	  		  + "&tag=" + tag + "&filter=" + filter;
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
	var fields = url.match(/fields=([provenance|loci|allele_status|table_fields|tags]+)/)[1];
	if (fields == 'provenance'){			
		add_rows(url,fields,'fields',row,'prov_field_heading','add_fields');
	} else if (fields == 'loci'){
		add_rows(url,fields,'locus',row,'loci_field_heading','add_loci');
	} else if (fields == 'allele_status'){
		add_rows(url,fields,'allele_status',row,'allele_status_field_heading','add_allele_status');		
	} else if (fields == 'table_fields'){
		add_rows(url,fields,'table_field',row,'table_field_heading','add_table_fields');
	} else if (fields == 'tags'){
		add_rows(url,fields,'tag',row,'locus_tags_heading','add_tags');
	}
}
END
	return $buffer;
}

sub _get_select_items {
	my ($self) = @_;
	my ( $field_list, $labels ) =
	  $self->get_field_selection_list( { isolate_fields => 1, sender_attributes => 1, extended_attributes => 1 } );
	my $grouped = $self->{'xmlHandler'}->get_grouped_fields;
	my @grouped_fields;
	foreach (@$grouped) {
		push @grouped_fields, "f_$_";
		( $labels->{"f_$_"} = $_ ) =~ tr/_/ /;
	}
	my @select_items;
	foreach my $field (@$field_list) {
		push @select_items, $field;
		if ( $field eq "f_$self->{'system'}->{'labelfield'}" ) {
			push @select_items, @grouped_fields;
		}
	}
	return \@select_items, $labels;
}

sub _highest_entered_fields {
	my ( $self, $type ) = @_;
	my $param_name;
	if ( $type eq 'provenance' ) {
		$param_name = 'prov_value';
	} elsif ( $type eq 'loci' ) {
		$param_name = 'designation_value';
	} elsif ( $type eq 'allele_status' ) {
		$param_name = 'allele_sequence_value';
	} elsif ( $type eq 'tags' ) {
		$param_name = 'tag_value';
	}
	my $q = $self->{'cgi'};
	my $highest;
	for ( 1 .. MAX_ROWS ) {
		$highest = $_ if defined $q->param("$param_name$_") && $q->param("$param_name$_") ne '';
	}
	return $highest;
}

sub initiate {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	$self->SUPER::initiate;
	$self->{'noCache'} = 1;
	if ( !$self->{'cgi'}->param('save_options') ) {
		my $guid = $self->get_guid;
		return if !$guid;
		foreach my $attribute (qw (allele_designations allele_status tag filter)) {
			my $value = $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, "$attribute\_fieldset" );
			$self->{'prefs'}->{"$attribute\_fieldset"} = ( $value // '' ) eq 'on' ? 1 : 0;
		}
	}
	return;
}
1;
