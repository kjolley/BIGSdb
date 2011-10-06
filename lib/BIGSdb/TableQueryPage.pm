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
package BIGSdb::TableQueryPage;
use strict;
use warnings;
use base qw(BIGSdb::QueryPage);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant MAX_ROWS => 20;
use BIGSdb::Page qw(SEQ_FLAGS);

sub initiate {
	my ($self) = @_;
	if ( $self->{'cgi'}->param('no_header') ) {
		$self->{'type'} = 'no_header';
		return;
	}
	$self->{$_} = 1 foreach (qw (tooltips jQuery jQuery.coolfieldset));
	return;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { 'general' => 1, 'main_display' => 0, 'isolate_display' => 0, 'analysis' => 0, 'query_field' => 0 };
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
	}
	if ( !$self->{'datastore'}->is_table($table) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Table '$table' is not defined.</p></div>\n";
		return;
	}
	my $cleaned = $table;
	$cleaned =~ tr/_/ /;
	print "<h1>Query $cleaned for $system->{'description'} database</h1>\n";
	my $qry;
	if (   !defined $q->param('currentpage')
		|| (defined $q->param('pagejump') && $q->param('pagejump') eq '1')
		|| $q->param('First') )
	{
		if ( !$q->param('no_js') ) {
			print "<noscript><p class=\"highlight\">The dynamic customisation of this interface requires that you enable Javascript in your
		browser. Alternatively, you can use a <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=$table&amp;no_js=1\">non-Javascript 
		version</a> that has 4 combinations of fields.</p></noscript>\n";
		}
		$self->_print_query_interface();
	}
	if (   defined $q->param('query')
		or defined $q->param('t1') )
	{
		$self->_run_query();
	} else {
		print "<p />\n";
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	my $record = $self->get_record_name( $self->{'cgi'}->param('table') ) || 'record';
	return "Query $record information - $desc";
}

sub _get_select_items {
	my ( $self, $table ) = @_;
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my ( @select_items, @order_by );
	if ( $table eq 'allele_sequences' || $table eq 'experiment_sequences' ) {
		push @select_items, 'isolate_id';
		push @select_items, $self->{'system'}->{'labelfield'};
	}
	foreach (@$attributes) {
		if ( $_->{'name'} eq 'sender' || $_->{'name'} eq 'curator' || $_->{'name'} eq 'user_id' ) {
			push @select_items, "$_->{'name'} (id)", "$_->{'name'} (surname)", "$_->{'name'} (first_name)", "$_->{'name'} (affiliation)";
		} else {
			push @select_items, $_->{'name'};
		}
		push @order_by, $_->{'name'};
		if ( $_->{'name'} eq 'isolate_id' ) {
			push @select_items, $self->{'system'}->{'labelfield'};
		}
	}
	my %labels;
	foreach my $item (@select_items) {
		( $labels{$item} = $item ) =~ tr/_/ /;
	}
	return ( \@select_items, \%labels, \@order_by, $attributes );
}

sub _print_table_fields {

	#split so single row can be added by AJAX call
	my ( $self, $table, $row, $max_rows, $select_items, $labels ) = @_;
	my $q = $self->{'cgi'};
	print "<span style=\"white-space:nowrap\">\n";
	print $q->popup_menu( -name => "s$row", -values => $select_items, -labels => $labels, -class => 'fieldlist' );
	print $q->popup_menu( -name => "y$row", -values => [ "=", "contains", ">", "<", "NOT", "NOT contain" ] );
	print $q->textfield( -name => "t$row", -class => 'value_entry' );
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		print
"<a id=\"add_table_fields\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;fields=table_fields&amp;table=$table&amp;row=$next_row&amp;no_header=1\" rel=\"ajax\" class=\"button\">&nbsp;+&nbsp;</a>\n";
		print
" <a class=\"tooltip\" title=\"Search values - Empty field values can be searched using the term \&lt;&shy;blank\&gt; or null. <p /><h3>Number of fields</h3>Add more fields by clicking the '+' button.\">&nbsp;<i>i</i>&nbsp;</a>";
	}
	print "</span>\n";
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

sub _print_query_interface {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $prefs  = $self->{'prefs'};
	my $q      = $self->{'cgi'};
	my $table  = $q->param('table');
	if ( !$self->{'datastore'}->is_table($table) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Table '$table' is not defined.</p></div>\n";
		return;
	}
	my ( $select_items, $labels, $order_by, $attributes ) = $self->_get_select_items($table);
	print "<div class=\"box\" id=\"queryform\"><div class=\"scrollable\">\n";
	my $table_fields = $q->param('no_js') ? 4 : ( $self->_highest_entered_fields('table_fields') || 1 );
	my $cleaned = $table;
	$cleaned =~ tr/_/ /;
	print "<p>Please enter your search criteria below (or leave blank and submit to return all records).";
	if ( !$self->{'curate'} && $table ne 'samples' ) {
		print " Matching $cleaned will be returned and you will then be able to update their display and query settings.";
	}
	print "</p>\n";
	print $q->startform;
	print $q->hidden($_) foreach qw (db page table no_js);
	print "<div style=\"white-space:nowrap\"><fieldset>\n<legend>Search criteria</legend>\n";
	my $table_field_heading = $table_fields == 1 ? 'none' : 'inline';
	print "<span id=\"table_field_heading\" style=\"display:$table_field_heading\"><label for=\"c0\">Combine searches with: </label>\n";
	print $q->popup_menu( -name => 'c0', -id => 'c0', -values => [ "AND", "OR" ] );
	print "</span>\n";
	print "<ul id=\"table_fields\">\n";

	foreach my $i ( 1 .. $table_fields ) {
		print "<li>";
		$self->_print_table_fields( $table, $i, $table_fields, $select_items, $labels );
		print "</li>\n";
	}
	print "</ul>\n";
	print "</fieldset>\n";
	print "<fieldset class=\"display\">\n";
	print "<ul>\n<li><span style=\"white-space:nowrap\">\n<label for=\"order\" class=\"display\">Order by: </label>\n";
	print $q->popup_menu( -name => 'order', -id => 'order', -values => $order_by, -labels => $labels );
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
" <a class=\"tooltip\" title=\"Records per page - Analyses use the full query dataset, rather than just the page shown.\">&nbsp;<i>i</i>&nbsp;</a>";
	print "</span></li>\n\n";
	my $page = $self->{'curate'} ? 'profileQuery' : 'query';
	print
"</ul><span style=\"float:left\"><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=$table\" class=\"resetbutton\">Reset</a></span><span style=\"float:right\">";
	print $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
	print "</span></fieldset>\n";
	print "</div>\n";
	my @filters;
	my %labels;

	foreach (@$attributes) {
		if ( $_->{'optlist'} || $_->{'type'} eq 'bool' || ( $_->{'dropdown_query'} && $_->{'dropdown_query'} eq 'yes' ) ) {
			( my $tooltip = $_->{'tooltip'} ) =~ tr/_/ /;
			$tooltip =~ s/ - / filter - Select a value to filter your search to only those with the selected attribute. /;
			if ( ( $_->{'dropdown_query'} && $_->{'dropdown_query'} eq 'yes' ) ) {
				if ( $_->{'name'} eq 'sender' || $_->{'name'} eq 'curator' ) {
					push @filters, $self->get_user_filter( $_->{'name'}, $table );
				} else {
					my %desc;
					my @values;
					my @fields_to_query;
					if ( $_->{'foreign_key'} ) {
						if ( $_->{'labels'} ) {
							my @values = split /\|/, $_->{'labels'};
							foreach (@values) {
								push @fields_to_query, $1 if $_ =~ /\$(.*)/;
							}
							local $" = ',';
							my $qry = "select id,@fields_to_query from $_->{'foreign_key'} ORDER BY @fields_to_query";
							my $sql = $self->{'db'}->prepare($qry) or die;
							eval { $sql->execute; };
							$logger->error($@) if $@;
							while ( my ( $id, @labels ) = $sql->fetchrow_array ) {
								my $temp = $_->{'labels'};
								my $i    = 0;
								foreach (@fields_to_query) {
									$temp =~ s/$_/$labels[$i]/;
									$i++;
								}
								$temp =~ s/[\|\$]//g;
								$desc{$id} = $temp;
							}
						} else {
							push @fields_to_query, 'id';
						}
						local $" = ',';
						if ( $_->{'foreign_key'} eq 'users' ) {
							@values =
							  @{ $self->{'datastore'}->run_list_query("SELECT id FROM users WHERE id>0 ORDER BY @fields_to_query") };
						} else {
							@values =
							  @{ $self->{'datastore'}->run_list_query("SELECT id FROM $_->{foreign_key} ORDER BY @fields_to_query") };
							next if !@values;
						}
					} else {
						@values = @{ $self->{'datastore'}->run_list_query("SELECT distinct($_->{name}) FROM $table ORDER BY $_->{name}") };
					}
					push @filters, $self->get_filter( $_->{'name'}, \@values, { 'labels' => \%desc } );
				}
			} elsif ( $_->{'optlist'} ) {
				my @options = split /;/, $_->{'optlist'};
				push @filters, $self->get_filter( $_->{'name'}, \@options );
			} elsif ( $_->{'type'} eq 'bool' ) {
				push @filters, $self->get_filter( $_->{'name'}, [qw(true false)], { 'tooltip' => $tooltip } );
			}
		}
	}
	if ( $table eq 'loci' || $table eq 'allele_designations' ) {
		push @filters, $self->get_scheme_filter;
	} elsif ( $table eq 'sequence_bin' ) {
		my %labels;
		my @experiments;
		my $qry = "SELECT id,description FROM experiments ORDER BY description";
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute(); };
		$logger->error($@) if $@;
		while ( my @data = $sql->fetchrow_array() ) {
			push @experiments, $data[0];
			$labels{ $data[0] } = $data[1];
		}
		if (@experiments) {
			push @filters, $self->get_filter( 'experiment', \@experiments, { 'labels' => \%labels } );
		}
	} elsif ( $table eq 'locus_descriptions' ) {
		my %labels;
		my $common_names = $self->{'datastore'}->run_list_query("SELECT DISTINCT common_name FROM loci ORDER BY common_name");
		push @filters,
		  $self->get_filter( 'common_name', $common_names,
			{ 'tooltip' => 'common names filter - Select a name to filter your search to only those loci with the selected common name.' }
		  );
	} elsif ( $table eq 'allele_sequences' ) {
		push @filters, $self->get_scheme_filter;
		push @filters,
		  $self->get_filter(
			'sequence_flag',
			[ 'any flag', 'no flag', SEQ_FLAGS ],
			{ 'tooltip' => 'sequence flag filter - Select the appropriate value to filter tags to only those flagged accordingly.' }
		  );
		push @filters,
		  $self->get_filter(
			'duplicates',
			[qw (1 2 5 10 25 50)],
			{
				'text' => 'tags per isolate/locus',
				'labels' =>
				  { 1 => 'no duplicates', 2 => '2 or more', 5 => '5 or more', 10 => '10 or more', 25 => '25 or more', 50 => '50 or more' },
				'tooltip' =>
				  'Duplicates filter - Filter search to only those loci that have been tagged a specified number of times per isolate.'
			}
		  );
	}
	if (@filters) {
		print "<fieldset>\n<legend>Filter query by</legend>\n<ul>\n";
		print "<li><span style=\"white-space:nowrap\">$_</span></li>" foreach @filters;
		print "</ul>\n</fieldset>";
	}
	print $q->endform;
	print "</div></div>\n";
	return;
}

sub _run_query {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $system = $self->{'system'};
	my $table  = $q->param('table');
	my $prefs  = $self->{'prefs'};
	my ( $qry, $qry2 );
	my @errors;
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);

	if ( !defined $q->param('query') ) {
		my $andor       = $q->param('c0');
		my $first_value = 1;
		foreach my $i ( 1 .. MAX_ROWS ) {
			if ( defined $q->param("t$i") && $q->param("t$i") ne '' ) {
				my $field    = $q->param("s$i");
				my $operator = $q->param("y$i");
				my $text     = $q->param("t$i");
				$text =~ s/^\s*//;
				$text =~ s/\s*$//;
				$text =~ s/'/\\'/g;
				my $thisfield;
				foreach (@$attributes) {
					if ( $_->{'name'} eq $field ) {
						$thisfield = $_;
						last;
					}
				}
				if ($thisfield->{'type'}){ #field may not actually exist in table (e.g. isolate_id in allele_sequences)
					if (   $text ne '<blank>'
						&& $text ne 'null'
						&& ( $thisfield->{'type'} eq 'int' )
						&& !BIGSdb::Utils::is_int($text) )
					{
						push @errors, "$field is an integer field.";
						next;
					} elsif ( $text ne '<blank>'
						&& $text ne 'null'
						&& lc( $thisfield->{'type'} ) eq 'bool'
						&& !BIGSdb::Utils::is_bool($text) )
					{
						push @errors, "$field is a boolean field - should be in either true/false or 1/0.";
						next;
					} elsif ( $text ne '<blank>'
						&& $text ne 'null'
						&& lc( $thisfield->{'type'} ) eq 'date'
						&& !BIGSdb::Utils::is_date($text) )
					{
						push @errors, "$field is a date field - should be in yyyy-mm-dd format (or 'today' / 'yesterday').";
						next;
					}
				}
				if ( !$self->is_valid_operator($operator) ) {
					push @errors, "$operator is not a valid operator.";
					next;
				}
				my $modifier = '';
				if ( $i > 1 && !$first_value ) {
					$modifier = " $andor ";
				}
				$first_value = 0;
				if ( ( $field =~ /(.*) \(id\)$/ || $field eq 'isolate_id' )
					&& !BIGSdb::Utils::is_int($text) )
				{
					push @errors, "$field is an integer field.";
					next;
				}
				if ( ( $table eq 'allele_sequences' || $table eq 'experiment_sequences' ) && $field eq 'isolate_id' ) {
					$qry .= $modifier . $self->_search_by_isolate_id( $table, $operator, $text );
				} elsif (
					(
						any {
							$table eq $_;
						}
						qw (allele_sequences allele_designations experiment_sequences sequence_bin project_members isolate_aliases samples)
					)
					&& $field eq $self->{'system'}->{'labelfield'}
				  )
				{
					$qry .= $modifier . $self->_search_by_isolate( $table, $operator, $text );
				} elsif (
					any {
						$field =~ /(.*) \($_\)$/;
					}
					qw (id surname first_name affiliation)
				  )
				{
					$qry .= $modifier . $self->search_users( $field, $operator, $text, $table );
				} else {
					if ( $operator eq 'NOT' ) {
						if ( $text eq '<blank>' || $text eq 'null' ) {
							$qry .= $modifier . "$table.$field is not null";
						} else {
							if ( $thisfield->{'type'} ne 'text' ) {
								$qry .= $modifier . "NOT CAST($table.$field AS text) = '$text'";
							} else {
								$qry .= $modifier . "NOT upper($table.$field) = upper('$text')";
							}
						}
					} elsif ( $operator eq "contains" ) {
						if ( $thisfield->{'type'} ne 'text' ) {
							$qry .= $modifier . "CAST($table.$field AS text) LIKE '\%$text\%'";
						} else {
							$qry .= $modifier . "upper($table.$field) LIKE upper(E'\%$text\%')";
						}
					} elsif ( $operator eq "NOT contain" ) {
						if ( $thisfield->{'type'} ne 'text' ) {
							$qry .= $modifier . "NOT CAST($table.$field AS text) LIKE '\%$text\%'";
						} else {
							$qry .= $modifier . "NOT upper($table.$field) LIKE upper(E'\%$text\%')";
						}
					} elsif ( $operator eq '=' ) {
						if ( lc( $thisfield->{'type'} ) eq 'text' ) {
							$qry .= $modifier
							  . (
								( $text eq '<blank>' || $text eq 'null' )
								? "$table.$field is null"
								: "upper($table.$field) = upper(E'$text')"
							  );
						} else {
							$qry .= $modifier
							  . ( ( $text eq '<blank>' || $text eq 'null' ) ? "$table.$field is null" : "$table.$field = '$text'" );
						}
					} else {
						$qry .= $modifier . "$table.$field $operator E'$text'";
					}
				}
			}
		}
		if ( defined $q->param('scheme_id_list') && $q->param('scheme_id_list') ne ''
			&& any { $table eq $_ } qw (loci scheme_fields schemes scheme_members client_dbase_schemes allele_designations) )
		{
			if ( $table eq 'loci' ) {
				$qry2 = "SELECT * FROM loci LEFT JOIN scheme_members ON loci.id = scheme_members.locus WHERE scheme_id";
			} elsif ( $table eq 'allele_designations' ) {
				$qry2 =
"SELECT * FROM allele_designations LEFT JOIN scheme_members ON allele_designations.locus = scheme_members.locus WHERE scheme_id";
			} elsif ( $table eq 'schemes' ) {
				$qry2 = "SELECT * FROM schemes WHERE id";
			} else {
				$qry2 = "SELECT * FROM $table WHERE scheme_id";
			}
			if ( $q->param('scheme_id_list') eq '0' ) {
				$qry2 .= " IS NULL";
			} else {
				$qry2 .= "=" . $q->param('scheme_id_list');
			}
			if ($qry) {
				$qry2 .= " AND ($qry)";
			}
		} elsif ( $q->param('experiment_list')
			&& $q->param('experiment_list') ne ''
			&& ( $table eq 'sequence_bin' ) )
		{
			my $experiment = $q->param('experiment_list');
			if ( BIGSdb::Utils::is_int($experiment) ) {
				$qry2 =
"SELECT * FROM sequence_bin LEFT JOIN experiment_sequences ON sequence_bin.id = experiment_sequences.seqbin_id WHERE experiment_id = $experiment";
				$qry2 .= " AND ($qry)" if $qry;
			} else {
				$qry2 = "SELECT * FROM $table WHERE ($qry)";
			}
		} elsif ( $table eq 'locus_descriptions' && $q->param('common_name_list') ne '' ) {
			my $common_name = $q->param('common_name_list');
			$common_name =~ s/'/\\'/g;
			$qry2 =
			  "SELECT * FROM locus_descriptions LEFT JOIN loci ON loci.id = locus_descriptions.locus WHERE common_name = E'$common_name'";
			$qry2 .= " AND ($qry)" if $qry;
		} elsif ( $table eq 'allele_sequences' ) {
			$qry2 = $self->_process_allele_sequences_filters($qry);
		} else {
			$qry ||= '';
			$qry2 = "SELECT * FROM $table WHERE ($qry)";
		}
		foreach (@$attributes) {
			my $param = $_->{'name'} . '_list';
			if ( defined $q->param($param) && $q->param($param) ne '' ) {
				my $value = $q->param($param);
				my $field = "$table." . $_->{'name'};
				if ( $qry2 !~ /WHERE \(\)\s*$/ ) {
					$qry2 .= " AND ";
				} else {
					$qry2 = "SELECT * FROM $table WHERE ";
				}
				$value =~ s/'/\\'/g;
				$qry2 .= ( ( $value eq '<blank>' || $value eq 'null' ) ? "$_ is null" : "$field = E'$value'" );
			}
		}
		$qry2 .= " ORDER BY $table.";
		$qry2 .= $q->param('order');
		my $dir = $q->param('direction') eq 'descending' ? 'desc' : 'asc';
		my @primary_keys = $self->{'datastore'}->get_primary_keys($table);
		local $" = ",$table.";
		$qry2 .= " $dir,$table.@primary_keys;";
	} else {
		$qry2 = $q->param('query');
	}
	my @hidden_attributes;
	push @hidden_attributes, 'c0';
	foreach my $i ( 1 .. MAX_ROWS ) {
		push @hidden_attributes, "s$i", "t$i", "y$i";
	}
	push @hidden_attributes, $_->{'name'} . '_list' foreach (@$attributes);
	push @hidden_attributes, qw (no_js sequence_flag_list duplicates_list common_name_list scheme_id_list);
	if (@errors) {
		local $" = '<br />';
		print "<div class=\"box\" id=\"statusbad\"><p>Problem with search criteria:</p>\n";
		print "<p>@errors</p></div>\n";
	} elsif ( $qry2 !~ /\(\)/ ) {
		if (
			(
				$self->{'system'}->{'read_access'} eq 'acl'
				|| ( $self->{'system'}->{'write_access'} && $self->{'system'}->{'write_access'} eq 'acl' )
			)
			&& $self->{'username'}
			&& !$self->is_admin
			&& $self->{'system'}->{'dbtype'} eq 'isolates'
			&& any { $table eq $_ } qw (allele_designations sequence_bin isolate_aliases accession allele_sequences samples)
		  )
		{
			if ( $table eq 'accession' || $table eq 'allele_sequences' ) {
				$qry2 =~ s/WHERE/AND/;
				$qry2 =~
s/FROM $table/FROM $table LEFT JOIN sequence_bin ON $table.seqbin_id=sequence_bin.id WHERE isolate_id IN (SELECT id FROM $self->{'system'}->{'view'})/;
			} else {
				$qry2 =~ s/WHERE/WHERE isolate_id IN (SELECT id FROM $self->{'system'}->{'view'}) AND/
				  || $qry =~ s/FROM $table/FROM $table WHERE isolate_id IN (SELECT id FROM $self->{'system'}->{'view'})/;
			}
		}
		$self->paged_display( $table, $qry2, '', \@hidden_attributes );
		print "<p />\n";
	} else {
		my $qry = "SELECT * FROM $table ORDER BY $table.";
		$qry .= $q->param('order');
		my $dir = $q->param('direction') eq 'descending' ? 'desc' : 'asc';
		my @primary_keys = $self->{'datastore'}->get_primary_keys($table);
		local $" = ",$table.";
		$qry .= " $dir,$table.@primary_keys;";
		$self->paged_display( $table, $qry, '', \@hidden_attributes );
		print "<p />\n";
	}
	return;
}

sub print_results_header_insert {
	my ( $self, $filename ) = @_;
	return if $self->{'curate'};
	my $q = $self->{'cgi'};
	return if $q->param('table') eq 'samples';
	my $record = $self->get_record_name( $q->param('table') );
	print "<fieldset><legend>Customize</legend>\n";
	print $q->start_form;
	print $q->submit( -name => 'customize', -label => "$record options", -class => 'submit' );
	$q->param( 'page',     'customize' );
	$q->param( 'filename', $filename );
	print $q->hidden($_) foreach qw (db filename table page);
	print $q->end_form;
	print "</fieldset>\n";
	return;
}

sub _search_by_isolate_id {
	my ( $self, $table, $operator, $text ) = @_;
	my $qry =
"$table.seqbin_id IN (SELECT sequence_bin.id FROM sequence_bin LEFT JOIN $self->{'system'}->{'view'} ON isolate_id = $self->{'system'}->{'view'}.id WHERE ";
	if ( $operator eq 'NOT' ) {
		$qry .= "NOT $self->{'system'}->{'view'}.id = $text";
	} elsif ( $operator eq "contains" ) {
		$qry .= "CAST($self->{'system'}->{'view'}.id AS text) LIKE '\%$text\%'";
	} elsif ( $operator eq "NOT contain" ) {
		$qry .= "NOT CAST($self->{'system'}->{'view'}.id AS text) LIKE '\%$text\%'";
	} else {
		$qry .= "$self->{'system'}->{'view'}.id $operator $text";
	}
	$qry .= ')';
	return $qry;
}

sub _search_by_isolate {
	my ( $self, $table, $operator, $text ) = @_;
	my %att   = $self->{'xmlHandler'}->get_field_attributes( $self->{'system'}->{'labelfield'} );
	my $field = $self->{'system'}->{'labelfield'};
	my $qry;
	if ( $table eq 'allele_sequences' || $table eq 'experiment_sequences' ) {
		$qry =
"$table.seqbin_id IN (SELECT sequence_bin.id FROM sequence_bin LEFT JOIN $self->{'system'}->{'view'} ON isolate_id = $self->{'system'}->{'view'}.id WHERE ";
	} elsif ( $table eq 'sequence_bin' ) {
		$qry =
"sequence_bin.id IN (SELECT sequence_bin.id FROM sequence_bin LEFT JOIN $self->{'system'}->{'view'} ON isolate_id = $self->{'system'}->{'view'}.id WHERE ";
	} elsif ( $table eq 'allele_designations' || $table eq 'project_members' || $table eq 'isolate_aliases' || $table eq 'samples' ) {
		$qry = "$table.isolate_id IN (SELECT id FROM $self->{'system'}->{'view'} WHERE ";
	} else {
		$logger->error("Invalid table $table");
		return;
	}
	if ( $operator eq 'NOT' ) {
		if ( $text eq '<blank>' || $text eq 'null' ) {
			$qry .= "$field is not null";
		} else {
			if ( $att{'type'} eq 'int' ) {
				$qry .= "NOT CAST($field AS text) = '$text'";
			} else {
				$qry .=
"NOT upper($field) = upper('$text') AND $self->{'system'}->{'view'}.id NOT IN (SELECT isolate_id FROM isolate_aliases WHERE upper(alias) = upper('$text'))";
			}
		}
	} elsif ( $operator eq "contains" ) {
		if ( $att{'type'} eq 'int' ) {
			$qry .= "CAST($field AS text) LIKE '\%$text\%'";
		} else {
			$qry .=
"upper($field) LIKE upper('\%$text\%') OR $self->{'system'}->{'view'}.id IN (SELECT isolate_id FROM isolate_aliases WHERE upper(alias) LIKE upper('\%$text\%'))";
		}
	} elsif ( $operator eq "NOT contain" ) {
		if ( $att{'type'} eq 'int' ) {
			$qry .= "NOT CAST($field AS text) LIKE '\%$text\%'";
		} else {
			$qry .=
"NOT upper($field) LIKE upper('\%$text\%') AND $self->{'system'}->{'view'}.id NOT IN (SELECT isolate_id FROM isolate_aliases WHERE upper(alias) LIKE upper('\%$text\%'))";
		}
	} elsif ( $operator eq '=' ) {
		if ( lc( $att{'type'} ) eq 'text' ) {
			$qry .= (
				( $text eq '<blank>' || $text eq 'null' )
				? "$field is null"
				: "upper($field) = upper('$text') OR $self->{'system'}->{'view'}.id IN (SELECT isolate_id FROM isolate_aliases WHERE upper(alias) = upper('$text'))"
			);
		} else {
			$qry .= ( ( $text eq '<blank>' || $text eq 'null' ) ? "$field is null" : "$field = '$text'" );
		}
	} else {
		$qry .= "$field $operator '$text'";
	}
	$qry .= ')';
	return $qry;
}

sub _process_allele_sequences_filters {
	my ( $self, $qry ) = @_;
	my $q = $self->{'cgi'};
	my $qry2;
	if ( any { $q->param($_) ne '' } qw (sequence_flag_list duplicates_list scheme_id_list) ) {
		if ( $q->param('sequence_flag_list') ne '' ) {
			if ( $q->param('sequence_flag_list') eq 'no flag' ) {
				$qry2 =
"SELECT * FROM allele_sequences LEFT JOIN sequence_flags ON sequence_flags.seqbin_id = allele_sequences.seqbin_id AND sequence_flags.locus = allele_sequences.locus AND sequence_flags.start_pos = allele_sequences.start_pos AND sequence_flags.end_pos = allele_sequences.end_pos";
				$qry2 .= " AND flag IS NULL";
			} else {
				$qry2 =
"SELECT * FROM allele_sequences INNER JOIN sequence_flags ON sequence_flags.seqbin_id = allele_sequences.seqbin_id AND sequence_flags.locus = allele_sequences.locus AND sequence_flags.start_pos = allele_sequences.start_pos AND sequence_flags.end_pos = allele_sequences.end_pos";
				if ( any { $q->param('sequence_flag_list') eq $_ } SEQ_FLAGS ) {
					$qry2 .= " AND flag = '" . $q->param('sequence_flag_list') . "'";
				}
			}
		}
		if ( $q->param('duplicates_list') ne '' ) {
			my $match = BIGSdb::Utils::is_int( $q->param('duplicates_list') ) ? $q->param('duplicates_list') : 1;
			my $not = $match == 1 ? 'NOT' : '';
			$match = 2 if $match == 1;    #no dups == NOT 2 or more
			my $dup_qry =
" LEFT JOIN sequence_bin ON allele_sequences.seqbin_id = sequence_bin.id WHERE (allele_sequences.locus,sequence_bin.isolate_id) $not IN (SELECT allele_sequences.locus,sequence_bin.isolate_id FROM allele_sequences LEFT JOIN sequence_bin ON allele_sequences.seqbin_id = sequence_bin.id GROUP BY allele_sequences.locus,sequence_bin.isolate_id HAVING count(*)>=$match)";
			if ($qry2) {
				$qry2 .= $dup_qry;
			} else {
				$qry2 = "SELECT * FROM allele_sequences$dup_qry";
			}
		}
		if ( $q->param('scheme_id_list') ne '' ) {
			my $scheme_qry =
"allele_sequences.locus IN (SELECT DISTINCT allele_sequences.locus FROM allele_sequences LEFT JOIN scheme_members ON allele_sequences.locus = scheme_members.locus WHERE scheme_id";
			if ( $q->param('scheme_id_list') eq '0' ) {
				$scheme_qry .= " IS NULL)";
			} else {
				$scheme_qry .= "=" . $q->param('scheme_id_list') . ")";
			}
			if ($qry2) {
				$qry2 .= $q->param('duplicates_list') ne '' ? ' AND ' : ' WHERE ';
				$qry2 .= "($scheme_qry)";
			} else {
				$qry2 = "SELECT * FROM allele_sequences WHERE ($scheme_qry)";
			}
		}
		$qry2 .= " AND ($qry)" if $qry;
	} else {
		$qry ||= '';
		$qry2 = "SELECT * FROM allele_sequences WHERE ($qry)";
	}
	return $qry2;
}
1;
