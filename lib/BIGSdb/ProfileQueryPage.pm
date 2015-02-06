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
package BIGSdb::ProfileQueryPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::QueryPage);
use BIGSdb::QueryPage qw(MAX_ROWS OPERATORS);
use List::MoreUtils qw(any );
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
		my ( $primary_key, $select_items, $orderitems, $cleaned ) = $self->_get_select_items($scheme_id);
		$self->_print_scheme_fields( $row, 0, $scheme_id, $select_items, $cleaned );
	}
	return;
}

sub get_help_url {
	my ($self) = @_;
	if ( $self->{'curate'} ) {
		return "$self->{'config'}->{'doclink'}/curator_guide.html#updating-and-deleting-scheme-profile-definitions";
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return $self->{'curate'} ? "Profile query/update - $desc" : "Search database - $desc";
}

sub print_content {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $q      = $self->{'cgi'};
	my $scheme_info;
	if ( $q->param('no_header') ) { $self->_ajax_content; return }
	my $desc = $self->get_db_description;
	say $self->{'curate'} ? "<h1>Query/update profiles - $desc</h1>" : "<h1>Search profiles - $desc</h1>";
	my $qry;

	if ( !defined $q->param('currentpage') || $q->param('First') ) {
		if ( !$q->param('no_js') ) {
			my $scheme_id = BIGSdb::Utils::is_int( $q->param('scheme_id') ) ? $q->param('scheme_id') : undef;
			my $scheme_clause = ( $system->{'dbtype'} eq 'sequences' && defined $scheme_id ) ? "&amp;scheme_id=$scheme_id" : '';
			say "<noscript><div class=\"box statusbad\"><p>The dynamic customisation of this interface requires that you enable "
			  . "Javascript in your browser. Alternatively, you can use a <a href=\"$self->{'system'}->{'script_name'}?db="
			  . "$self->{'instance'}&amp;page=query$scheme_clause&amp;no_js=1\">non-Javascript version</a> that has 4 combinations "
			  . "of fields.</p></div></noscript>";
		}
		$self->_print_interface;
	}
	$self->_run_query if $q->param('submit') || defined $q->param('query_file');
	return;
}

sub _print_interface {
	my ($self)    = @_;
	my $system    = $self->{'system'};
	my $prefs     = $self->{'prefs'};
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	return if defined $scheme_id && $self->is_scheme_invalid( $scheme_id, { with_pk => 1 } );
	$self->print_scheme_section( { with_pk => 1 } );
	$scheme_id = $q->param('scheme_id');    #Will be set by scheme section method
	say "<div class=\"box\" id=\"queryform\"><div class=\"scrollable\">";
	say $q->startform;
	say $q->hidden($_) foreach qw (db page scheme_id no_js);
	my $scheme_field_count = $q->param('no_js') ? 4 : ( $self->_highest_entered_fields || 1 );
	my $scheme_field_heading = $scheme_field_count == 1 ? 'none' : 'inline';
	say "<div style=\"white-space:nowrap\">";
	say "<fieldset style=\"float:left\">\n<legend>Locus/scheme fields</legend>";
	say "<span id=\"scheme_field_heading\" style=\"display:$scheme_field_heading\"><label for=\"c0\">Combine searches with: </label>";
	say $q->popup_menu( -name => 'c0', -id => 'c0', -values => [ "AND", "OR" ] );
	say "</span><ul id=\"scheme_fields\">";
	my ( $primary_key, $selectitems, $orderitems, $cleaned ) = $self->_get_select_items($scheme_id);

	foreach my $i ( 1 .. $scheme_field_count ) {
		print "<li>";
		$self->_print_scheme_fields( $i, $scheme_field_count, $scheme_id, $selectitems, $cleaned );
		say "</li>";
	}
	say "</ul>";
	say "</fieldset>";
	$self->_print_filter_fieldset($scheme_id);
	$self->print_action_fieldset( { page => 'query', scheme_id => $scheme_id } );
	say $q->end_form;
	say "</div></div>";
	return;
}

sub _print_filter_fieldset {
	my ( $self, $scheme_id ) = @_;
	my $q = $self->{'cgi'};
	my @filters;
	my $set_id = $self->get_set_id;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	if ( $self->{'config'}->{'ref_db'} ) {
		my $pmid =
		  $self->{'datastore'}
		  ->run_query( "SELECT DISTINCT(pubmed_id) FROM profile_refs WHERE scheme_id=?", $scheme_id, { fetch => 'col_arrayref' } );
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
			my $values = $self->{'datastore'}->run_query(
				"SELECT DISTINCT $value_clause FROM profile_fields WHERE scheme_id=? AND scheme_field=? ORDER BY $value_clause",
				[ $scheme_id, $field ],
				{ fetch => 'col_arrayref' }
			);
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
	my ( $primary_key, $selectitems, $orderitems, $cleaned ) = $self->_get_select_items($scheme_id);
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
	return;
}

sub _print_scheme_fields {
	my ( $self, $row, $max_rows, $scheme_id, $selectitems, $labels ) = @_;
	my $q = $self->{'cgi'};
	say "<span style=\"white-space:nowrap\">";
	say $q->popup_menu( -name => "s$row", -values => $selectitems, -labels => $labels, -class => 'fieldlist' );
	say $q->popup_menu( -name => "y$row", -values => [OPERATORS] );
	say $q->textfield( -name => "t$row", -class => 'value_entry' );
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		if ( !$q->param('no_js') ) {
			print "<a id=\"add_scheme_fields\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;"
			  . "fields=scheme_fields&amp;scheme_id=$scheme_id&amp;row=$next_row&amp;no_header=1\" data-rel=\"ajax\" "
			  . "class=\"button\">+</a>";
			say " <a class=\"tooltip\" id=\"scheme_field_tooltip\" title=\"\">&nbsp;<i>i</i>&nbsp;</a>";
		}
	}
	say "</span>";
	return;
}

sub _get_select_items {
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
	foreach (qw (sender curator)) {
		push @selectitems, "$_ (id)", "$_ (surname)", "$_ (first_name)", "$_ (affiliation)";
		push @orderitems, $_;
	}
	push @selectitems, qw	(date_entered datestamp);
	$cleaned{'date_entered'} = 'date entered';
	( $cleaned{"$primary_key"} = $primary_key ) =~ tr/_/ /;
	return ( $primary_key, \@selectitems, \@orderitems, \%cleaned );
}

sub _run_query {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $system = $self->{'system'};
	my $qry;
	my @errors;
	my $scheme_id   = BIGSdb::Utils::is_int( $q->param('scheme_id') ) ? $q->param('scheme_id') : 0;
	my $loci        = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
	if ( !defined $q->param('query_file') ) {
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
				my $operator = $q->param("y$i") // '=';
				my $text = $q->param("t$i");
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
					if ( $operator eq 'NOT' ) { $qry .= $text eq 'null' ? "(not $equals)" : "((NOT $equals) OR $cleaned IS NULL)" }
					elsif ( $operator eq 'contains' )    { $qry .= "(upper($cleaned) LIKE upper('\%$text\%'))" }
					elsif ( $operator eq 'starts with' ) { $qry .= "(upper($cleaned) LIKE upper('$text\%'))" }
					elsif ( $operator eq 'ends with' )   { $qry .= "(upper($cleaned) LIKE upper('\%$text'))" }
					elsif ( $operator eq 'NOT contain' ) { $qry .= "(NOT upper($cleaned) LIKE upper('\%$text\%') OR $cleaned IS NULL)" }
					elsif ( $operator eq '=' )           { $qry .= "($equals)" }
					else {
						$qry .= ( $type eq 'integer' ? "(to_number(textcat('0', $cleaned), text(99999999))" : "($cleaned" )
						  . " $operator '$text')";
					}
				}
			}
		}
		$qry .= ')';
		my $primary_key =
		  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )->[0];
		if ( defined $q->param('publication_list') && $q->param('publication_list') ne '' ) {
			my $pmid = $q->param('publication_list');
			my $ids  = $self->{'datastore'}->run_query(
				"SELECT profile_id FROM profile_refs WHERE scheme_id=? AND pubmed_id=?",
				[ $scheme_id, $pmid ],
				{ fetch => 'col_arrayref' }
			);
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
		$qry = $self->get_query_from_temp_file( $q->param('query_file') );
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
		my $args = { table => 'profiles', query => $qry, hidden_attributes => \@hidden_attributes };
		$args->{'passed_qry_file'} = $q->param('query_file') if defined $q->param('query_file');
		$self->paged_display($args);
	} else {
		say "<div class=\"box\" id=\"statusbad\">Invalid search performed. Try to <a href=\"$self->{'system'}->{'script_name'}?db="
		  . "$self->{'instance'}&amp;page=browse&amp;scheme_id=$scheme_id\">browse all records</a>.</div>";
	}
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $buffer = $self->SUPER::get_javascript;
	$buffer .= << "END";
\$(function () {
   	\$('#scheme_field_tooltip').tooltip({ content: "<h3>Search values</h3><p>Empty field "
  		+ "values can be searched using the term 'null'. </p><h3>Number of fields</h3><p>Add more fields by clicking the '+' button."
  		+ "</p><h3>Query modifier</h3><p>Select 'AND' for the isolate query to match ALL search terms, 'OR' to match ANY of these terms."
  		+ "</p>" });
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
1;
