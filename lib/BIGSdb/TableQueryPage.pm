#Written by Keith Jolley
#Copyright (c) 2010, University of Oxford
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
use base qw(BIGSdb::QueryPage);
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
	foreach (qw (tooltips jQuery)){
		$self->{$_} = 1;
	}
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { 'general' => 1, 'main_display' => 0, 'isolate_display' => 0, 'analysis' => 0, 'query_field' => 0 };
}

sub print_content {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $q      = $self->{'cgi'};
	my $table  = $q->param('table');
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
		|| $q->param('pagejump') eq '1'
		|| $q->param('First') )
	{
		if (!$q->param('no_js')){
			print "<noscript><div class=\"id\" id=\"statusbad\"><p>The dynamic customisation of this interface requires that you enable Javascript in your
		browser. Alternatively, you can use a <a href=\"$self->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=$table&amp;no_js=1\">non-Javascript 
		version</a> that has 4 combinations of fields.</p></div></noscript>\n";
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
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	my $record = $self->get_record_name( $self->{'cgi'}->param('table') );
	return "Query $record information - $desc";
}

sub _get_select_items {
	my ($self,$table) = @_;
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my ( @select_items, @order_by );
	if ( $table eq 'allele_sequences' || $table eq 'experiment_sequences' ) {
		push @select_items, 'isolate_id';
		push @select_items, $self->{'system'}->{'labelfield'};
	}
	foreach (@$attributes) {
		if ( $_->{'name'} eq 'sender' || $_->{'name'} eq 'curator' || $_->{'name'} eq 'user_id' ) {
			push @select_items, "$_->{'name'} (id)";
			push @select_items, "$_->{'name'} (surname)";
			push @select_items, "$_->{'name'} (first_name)";
			push @select_items, "$_->{'name'} (affiliation)";
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
	return (\@select_items,\%labels,\@order_by, $attributes);
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
}

sub _ajax_content {
	my ($self, $table) = @_;
	my $system = $self->{'system'};
	my $q      = $self->{'cgi'};
	my $row    = $q->param('row');
	return if !BIGSdb::Utils::is_int($row) || $row > MAX_ROWS || $row < 2;
	my ( $select_items, $labels ) = $self->_get_select_items($table);
	$self->_print_table_fields( $table, $row, 0, $select_items, $labels );
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
	my ($select_items, $labels, $order_by, $attributes) = $self->_get_select_items($table);
	print "<div class=\"box\" id=\"queryform\"><div class=\"scrollable\">\n";
	my $table_fields;
	if ($q->param('no_js')){
		$table_fields = 4;
	} else {
		$table_fields = $self->_highest_entered_fields('table_fields') || 1;
	}
	my $cleaned = $table;
	$cleaned =~ tr/_/ /;
	print "<p>Please enter your search criteria below (or leave blank and submit to return all records).";
	if ( !$self->{'curate'} && $table ne 'samples' ) {
		print " Matching $cleaned will be returned and you will then be able to update their display and query settings.";
	}
	print "</p>\n";
	print $q->startform();
	foreach (qw (db page table no_js)) {
		print $q->hidden($_);
	}
	print "<div style=\"white-space:nowrap\"><fieldset>\n<legend>Search criteria</legend>\n";
	my $table_field_heading = $table_fields == 1 ? 'none' : 'inline';
	print "<span id=\"table_field_heading\" style=\"display:$table_field_heading\"><label for=\"c0\">Combine searches with: </label>\n";
	print $q->popup_menu( -name => 'c0', -id => 'c0', -values => [ "AND", "OR" ] );
	print "</span>\n";
	print "<ul id=\"table_fields\">\n";
	for ( my $i = 1 ; $i <= $table_fields ; $i++ ) {
		print "<li>";
		$self->_print_table_fields($table, $i, $table_fields, $select_items, $labels);
		print "</li>\n";
	}
	print "</ul>\n";
	print "</fieldset>\n";
	print "<fieldset class=\"display\">\n";
	print "<ul>\n<li><span style=\"white-space:nowrap\">\n<label for=\"order\" class=\"display\">Order by: </label>\n";
	$" = ' ';
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
	my @username;
	my $qry = "SELECT id,first_name,surname FROM users WHERE id>0 ORDER BY surname ";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute(); };

	if ($@) {
		$logger->error("Can't execute: $qry");
	} else {
		$logger->debug("Query: $qry");
	}
	while ( my @data = $sql->fetchrow_array() ) {
		push @username, $data[0];
		$labels{ $data[0] } = "$data[2], $data[1]";
	}
	foreach (@$attributes) {
		if ( $_->{'optlist'} || $_->{'type'} eq 'bool' || $_->{'dropdown_query'} eq 'yes' ) {
			( my $clean = $_->{name} ) =~ tr/_/ /;
			my $buffer = "<label for=\"$_->{'name'}\_list\" class=\"filter\">$clean: </label>\n";
			if ( $_->{'dropdown_query'} eq 'yes' ) {
				my %desc;
				my @values;
				my @fields_to_query;
				if ( $_->{'foreign_key'} ) {
					if ( $_->{'labels'} ) {
						my @values = split /\|/, $_->{'labels'};
						foreach (@values) {
							if ( $_ =~ /\$(.*)/ ) {
								push @fields_to_query, $1;
							}
						}
						$" = ',';
						my $qry = "select id,@fields_to_query from $_->{'foreign_key'} ORDER BY @fields_to_query";
						my $sql = $self->{'db'}->prepare($qry) or die;
						eval { $sql->execute; };
						if ($@) {
							$logger->error("Can't execute: $qry");
						} else {
							$logger->debug("Query: $qry");
						}
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
					$" = ',';
					if ( $_->{'foreign_key'} eq 'users' ) {
						@values = @{ $self->{'datastore'}->run_list_query("SELECT id FROM users WHERE id>0 ORDER BY @fields_to_query") };
					} else {
						@values = @{ $self->{'datastore'}->run_list_query("SELECT id FROM $_->{foreign_key} ORDER BY @fields_to_query") };
						next if !@values;
						foreach (@values) {
							if ( !defined $desc{$_} ) {
								( $desc{$_} = $_ ) =~ tr/_/ /;
							}
						}
					}
				} else {
					@values = @{ $self->{'datastore'}->run_list_query("SELECT distinct($_->{name}) FROM $table ORDER BY $_->{name}") };
				}
				if (   $_->{'name'} eq 'sender'
					|| $_->{'name'} eq 'curator' )
				{
					$buffer .= $q->popup_menu(
						-name   => "$_->{'name'}\_list",
						-id     => "$_->{'name'}\_list",
						-values => [ '', @username ],
						-labels => \%labels
					);
				} else {
					$buffer .= $q->popup_menu(
						-name   => "$_->{'name'}\_list",
						-id     => "$_->{'name'}\_list",
						-values => [ '', @values ],
						-labels => \%desc
					);
				}
			} elsif ( $_->{'optlist'} ) {
				my @options = split /;/, $_->{'optlist'};
				$buffer .= $q->popup_menu( -name => $_->{'name'} . '_list', -id => $_->{'name'} . '_list', -values => [ '', @options ] );
			} elsif ( $_->{'type'} eq 'bool' ) {
				$buffer .=
				  $q->popup_menu( -name => $_->{'name'} . '_list', -id => $_->{'name'} . '_list', -values => [ '', 'true', 'false' ] );
			}
			if ( $_->{'tooltip'} ) {
				$_->{'tooltip'} =~ tr/_/ /;
				$_->{'tooltip'} =~ s/ - / filter - /;
				$_->{'tooltip'} =~ s/ - / - Select a value to filter your search to only those with the selected attribute. /;
				$buffer .= " <a class=\"tooltip\" title=\"$_->{'tooltip'}\">&nbsp;<i>i</i>&nbsp;</a>";
			}
			push @filters, $buffer;
		}
	}
	if ( $table eq 'loci' ) {
		my %labels;
		my @schemes;
		my $qry = "SELECT id,description FROM schemes ORDER BY display_order,id";
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute(); };
		if ($@) {
			$logger->error("Can't execute: $qry");
		} else {
			$logger->debug("Query: $qry");
		}
		while ( my @data = $sql->fetchrow_array() ) {
			push @schemes, $data[0];
			$labels{ $data[0] } = $data[1];
		}
		push @schemes, 0;
		$labels{0} = 'No scheme';
		my $buffer = "<label for=\"scheme_list\" class=\"filter\">scheme: </label>\n";
		$buffer .= $q->popup_menu(
			-name   => 'scheme_list',
			-id     => 'scheme_list',
			-values => [ '', @schemes ],
			-labels => \%labels,
			-class  => 'filter'
		);
		$buffer .=
" <a class=\"tooltip\" title=\"scheme filter - Click the checkbox and select a scheme to filter your search to only those belonging to the selected scheme.\">&nbsp;<i>i</i>&nbsp;</a>";
		push @filters, $buffer;
	} elsif ( $table eq 'sequence_bin' ) {
		my %labels;
		my @experiments;
		my $qry = "SELECT id,description FROM experiments ORDER BY description";
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute(); };
		if ($@) {
			$logger->error("Can't execute: $qry");
		} else {
			$logger->debug("Query: $qry");
		}
		while ( my @data = $sql->fetchrow_array() ) {
			push @experiments, $data[0];
			$labels{ $data[0] } = $data[1];
		}
		if ( @experiments > 1 ) {
			my $buffer = "<label for=\"experiment_list\" class=\"filter\">experiment: </label>\n";
			$" = ' ';
			$buffer .= $q->popup_menu(
				-name   => 'experiment_list',
				-id     => 'experiment_list',
				-values => [ '', @experiments ],
				-labels => \%labels,
				-class  => 'filter'
			);
			$buffer .=
" <a class=\"tooltip\" title=\"experiment filter - Click the checkbox and select an experiment to filter your search to only those sequences linked to the selected experiment.\">&nbsp;<i>i</i>&nbsp;</a>";
			push @filters, $buffer;
		}
	}
	if (@filters) {
		print "<fieldset>\n";
		print "<legend>Filter query by</legend>\n";
		print "<ul>\n";
		foreach (@filters) {
			print "<li><span style=\"white-space:nowrap\">$_</span></li>";
		}
		print "</ul>\n</fieldset>";
	}
	print $q->endform;
	print "</div></div>\n";
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
		for ( my $i = 1 ; $i <= MAX_ROWS ; $i++ ) {
			if ( $q->param("t$i") ne '' ) {
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
				} elsif ( !$self->is_valid_operator($operator) ) {
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
					$qry .= $modifier . $self->_search_by_isolate_id( $operator, $text );
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
				} elsif (any {$field =~ /(.*) \($_\)$/} qw (id surname first_name affiliation)) {
					$qry .= $modifier . $self->search_users( $field, $operator, $text, $table );
				} else {
					if ( $operator eq 'NOT' ) {
						if ( $text eq '<blank>' || $text eq 'null' ) {
							$qry .= $modifier . "$field is not null";
						} else {
							if ( $thisfield->{'type'} ne 'text' ) {
								$qry .= $modifier . "NOT CAST($field AS text) = '$text'";
							} else {
								$qry .= $modifier . "NOT upper($field) = upper('$text')";
							}
						}
					} elsif ( $operator eq "contains" ) {
						if ( $thisfield->{'type'} ne 'text' ) {
							$qry .= $modifier . "CAST($field AS text) LIKE '\%$text\%'";
						} else {
							$qry .= $modifier . "upper($field) LIKE upper('\%$text\%')";
						}
					} elsif ( $operator eq "NOT contain" ) {
						if ( $thisfield->{'type'} ne 'text' ) {
							$qry .= $modifier . "NOT CAST($field AS text) LIKE '\%$text\%'";
						} else {
							$qry .= $modifier . "NOT upper($field) LIKE upper('\%$text\%')";
						}
					} elsif ( $operator eq '=' ) {
						if ( lc( $thisfield->{'type'} ) eq 'text' ) {
							$qry .= $modifier
							  . ( ( $text eq '<blank>' || $text eq 'null' ) ? "$field is null" : "upper($field) = upper('$text')" );
						} else {
							$qry .= $modifier . ( ( $text eq '<blank>' || $text eq 'null' ) ? "$field is null" : "$field = '$text'" );
						}
					} else {
						$qry .= $modifier . "$field $operator '$text'";
					}
				}
			}
		}
		if (
			$q->param('scheme_list') ne ''
			&& (   $table eq 'loci'
				|| $table eq 'scheme_fields'
				|| $table eq 'schemes'
				|| $table eq 'scheme_members'
				|| $table eq 'client_dbase_schemes' )
		  )
		{
			if ( $table eq 'loci' ) {
				$qry2 = "SELECT * FROM loci LEFT JOIN scheme_members ON loci.id = scheme_members.locus WHERE scheme_id";
			} elsif ( $table eq 'schemes' ) {
				$qry2 = "SELECT * FROM schemes WHERE id";
			} else {
				$qry2 = "SELECT * FROM $table WHERE scheme_id";
			}
			if ( $q->param('scheme_list') eq '0' ) {
				$qry2 .= " IS NULL";
			} else {
				$qry2 .= "='" . $q->param('scheme_list') . "'";
			}
			if ($qry) {
				$qry2 .= " AND ($qry)";
			}
		} elsif ( $q->param('experiment_list') ne ''
			&& ( $table eq 'sequence_bin' ) )
		{
			my $experiment = $q->param('experiment_list');
			if ( BIGSdb::Utils::is_int($experiment) ) {
				$qry2 =
"SELECT * FROM sequence_bin LEFT JOIN experiment_sequences ON sequence_bin.id = experiment_sequences.seqbin_id WHERE experiment_id = $experiment";
			} else {
				$qry2 = "SELECT * FROM $table WHERE ($qry)";
			}
		} else {
			$qry2 = "SELECT * FROM $table WHERE ($qry)";
		}
		foreach (@$attributes) {
			if ( $q->param( $_->{'name'} . '_list' ) ne '' ) {
				my $value = $q->param( $_->{'name'} . '_list' );
				if ( $qry2 !~ /WHERE \(\)\s*$/ ) {
					$qry2 .= " AND ";
				} else {
					$qry2 = "SELECT * FROM $table WHERE ";
				}
				$value =~ s/'/\\'/g;
				$qry2 .= ( ( $value eq '<blank>' || $value eq 'null' ) ? "$_ is null" : "$_->{'name'} = '$value'" );
			}
		}
		$qry2 .= " ORDER BY ";
		$qry2 .= $q->param('order');
		my $dir = $q->param('direction') eq 'descending' ? 'desc' : 'asc';
		my @primary_keys = $self->{'datastore'}->get_primary_keys($table);
		$" = ',';
		$qry2 .= " $dir,@primary_keys;";
	} else {
		$qry2 = $q->param('query');
	}
	my @hidden_attributes;
	push @hidden_attributes, 'c0';
	for ( my $i = 1 ; $i <= MAX_ROWS ; $i++ ) {
		push @hidden_attributes, "s$i", "t$i", "y$i";
	}
	foreach (@$attributes) {
		push @hidden_attributes, $_->{'name'} . '_list';
	}
	push @hidden_attributes, 'no_js';
	if (@errors) {
		$" = '<br />';
		print "<div class=\"box\" id=\"statusbad\"><p>Problem with search criteria:</p>\n";
		print "<p>@errors</p></div>\n";
	} elsif ( $qry2 !~ /\(\)/ ) {
		if (
			   ( $self->{'system'}->{'read_access'} eq 'acl' || $self->{'system'}->{'write_access'} eq 'acl' )
			&& $self->{'username'}
			&& !$self->is_admin
			&& $self->{'system'}->{'dbtype'} eq 'isolates'
			&& (   $table eq 'allele_designations'
				|| $table eq 'sequence_bin'
				|| $table eq 'isolate_aliases'
				|| $table eq 'accession'
				|| $table eq 'allele_sequences'
				|| $table eq 'samples' )
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
		my $qry = "SELECT * FROM $table ORDER BY ";
		$qry .= $q->param('order');
		my $dir = $q->param('direction') eq 'descending' ? 'desc' : 'asc';
		my @primary_keys = $self->{'datastore'}->get_primary_keys($table);
		$" = ',';
		$qry .= " $dir,@primary_keys;";
		$self->paged_display( $table, $qry, '', \@hidden_attributes );
		print "<p />\n";
	}
}

sub print_results_header_insert {
	my ( $self, $filename ) = @_;
	return if $self->{'curate'};
	my $q = $self->{'cgi'};
	return if $q->param('table') eq 'samples';
	print "<table><tr><td>";
	my $record = $self->get_record_name( $q->param('table') );
	print $q->start_form;
	print $q->submit( -name => 'customize', -label => "Customize $record options", -class => 'submit' );
	print $q->hidden('db');
	print $q->hidden( 'filename', $filename );
	print $q->hidden('table');
	$q->param( 'page', 'customize' );
	print $q->hidden('page');
	print $q->end_form;
	print "</td></tr></table>\n";
}

sub _search_by_isolate_id {
	my ( $self, $operator, $text ) = @_;
	my $qry =
"seqbin_id IN (SELECT sequence_bin.id FROM sequence_bin LEFT JOIN $self->{'system'}->{'view'} ON isolate_id = $self->{'system'}->{'view'}.id WHERE ";
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
"seqbin_id IN (SELECT sequence_bin.id FROM sequence_bin LEFT JOIN $self->{'system'}->{'view'} ON isolate_id = $self->{'system'}->{'view'}.id WHERE ";
	} elsif ( $table eq 'sequence_bin' ) {
		$qry =
"id IN (SELECT sequence_bin.id FROM sequence_bin LEFT JOIN $self->{'system'}->{'view'} ON isolate_id = $self->{'system'}->{'view'}.id WHERE ";
	} elsif ( $table eq 'allele_designations' || $table eq 'project_members' || $table eq 'isolate_aliases' || $table eq 'samples' ) {
		$qry = "isolate_id IN (SELECT id FROM $self->{'system'}->{'view'} WHERE ";
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
1;
