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
	if (   !$self->{'datastore'}->is_table($table)
		&& !( $table eq 'samples' && @{ $self->{'xmlHandler'}->get_sample_field_list } ) )
	{
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
		if ( !$q->param('no_js') ) {
			say q(<noscript><div class="box statusbad"><p>The dynamic customisation of this interface requires )
			  . q(that you enable Javascript in your browser. Alternatively, you can use a )
			  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;)
			  . qq(table=$table&amp;no_js=1">non-Javascript version</a> that has 4 combinations of fields.</p>)
			  . q(</div></noscript>);
		}
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
		next if ( $att->{'hide_query'} // '' ) eq 'yes';
		if ( any { $att->{'name'} eq $_ } qw (sender curator user_id) ) {
			push @select_items, "$att->{'name'} (id)", "$att->{'name'} (surname)", "$att->{'name'} (first_name)",
			  "$att->{'name'} (affiliation)";
		} elsif ( $att->{'query_datestamp'} ) {
			push @select_items, "$att->{'name'} (date)";
		} else {
			push @select_items, $att->{'name'};
		}
		push @order_by, $att->{'name'};
		if ( $att->{'name'} eq 'isolate_id' ) {
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
		  . q(data-rel="ajax" class="button">+</a> <a class="tooltip" id="field_tooltip" title="">)
		  . q(<span class="fa fa-info-circle"></span></a>);
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
	my $table_fields = $q->param('no_js') ? 4 : ( $self->_highest_entered_fields || 1 );
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
	say $q->startform;
	say $q->hidden($_) foreach qw (db page table no_js);
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
		if (   $att->{'optlist'}
			|| $att->{'type'} eq 'bool'
			|| ( $att->{'dropdown_query'} && $att->{'dropdown_query'} eq 'yes' ) )
		{
			( my $tooltip = $att->{'tooltip'} ) =~ tr/_/ /;
			my $sub = 'Select a value to filter your search to only those with the selected attribute.';
			$tooltip =~ s/ - / filter - $sub/x;
			if ( ( $att->{'dropdown_query'} && $att->{'dropdown_query'} eq 'yes' ) ) {
				if (   $att->{'name'} eq 'sender'
					|| $att->{'name'} eq 'curator'
					|| ( $att->{'foreign_key'} // '' ) eq 'users' )
				{
					push @filters, $self->get_user_filter( $att->{'name'} );
				} elsif ( $att->{'name'} eq 'scheme_id' ) {
					push @filters, $self->get_scheme_filter;
				} elsif ( $att->{'name'} eq 'locus' ) {
					push @filters, $self->get_locus_filter;
				} elsif ( $table eq 'schemes' && $att->{'name'} eq 'description' ) {
					my $set_id = $self->get_set_id;
					my $scheme_list = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
					my @values;
					push @values, $_->{'description'} foreach @$scheme_list;
					push @filters, $self->get_filter( $att->{'name'}, \@values );
				} else {
					my $desc;
					my $values;
					my @fields_to_query;
					if ( $att->{'foreign_key'} ) {
						next if $att->{'name'} eq 'scheme_id';
						if ( $att->{'labels'} ) {
							( my $fields_ref, $desc ) = $self->get_all_foreign_key_fields_and_labels($att);
							@fields_to_query = @$fields_ref;
						} else {
							push @fields_to_query, 'id';
						}
						local $" = ',';
						$values =
						  $self->{'datastore'}
						  ->run_query( "SELECT id FROM $att->{'foreign_key'} ORDER BY @fields_to_query",
							undef, { fetch => 'col_arrayref' } );
						next if !@$values;
					} else {
						my $order        = $att->{'type'} eq 'text' ? "lower($att->{'name'})"       : $att->{'name'};
						my $empty_clause = $att->{'type'} eq 'text' ? " WHERE $att->{'name'} <> ''" : '';
						$values =
						  $self->{'datastore'}
						  ->run_query( "SELECT $att->{'name'} FROM $table$empty_clause ORDER BY $order",
							undef, { fetch => 'col_arrayref' } );
						@$values = uniq @$values;
					}
					push @filters, $self->get_filter( $att->{'name'}, $values, { labels => $desc } );
				}
			} elsif ( $att->{'optlist'} ) {
				my @options = split /;/x, $att->{'optlist'};
				push @filters, $self->get_filter( $att->{'name'}, \@options );
			} elsif ( $att->{'type'} eq 'bool' ) {
				push @filters, $self->get_filter( $att->{'name'}, [qw(true false)], { tooltip => $tooltip } );
			}
		}
	}
	if ( any { $table eq $_ } qw (loci allele_designations schemes) ) {
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
	say $q->endform;
	say q(</div></div>);
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
	my ( undef, undef, $order_by, undef ) = $self->_get_select_items($table);
	$q->delete('order')
	  if defined $q->param('order') && none { $q->param('order') eq $_ }
	@$order_by;    #Sanitize to prevent SQL injection attempts.

	if ( !defined $q->param('query_file') ) {
		( $qry, $errors ) = $self->_generate_query($table);
		if ( $table eq 'sequences' && $qry ) {
			$qry =~ s/sequences.sequence_length/length(sequences.sequence)/gx;
		}
		$self->_modify_isolates_for_view( $table, \$qry );
		$self->_modify_seqbin_for_view( $table, \$qry );
		$self->_modify_loci_for_sets( $table, \$qry );
		$self->_modify_schemes_for_sets( $table, \$qry );
		if (   ( $q->param('scheme_id_list') // '' ) ne ''
			&& BIGSdb::Utils::is_int( $q->param('scheme_id_list') )
			&& any { $table eq $_ }
			qw (loci scheme_fields schemes scheme_members client_dbase_schemes allele_designations allele_sequences) )
		{
			my $scheme_id = $q->param('scheme_id_list');
			my ( $identifier, $field );
			my %set_id_and_field = (
				loci                => sub { ( $identifier, $field ) = ( 'id',    'locus' ) },
				allele_designations => sub { ( $identifier, $field ) = ( 'locus', 'locus' ) },
				allele_sequences    => sub { ( $identifier, $field ) = ( 'locus', 'locus' ) },
				schemes             => sub { ( $identifier, $field ) = ( 'id',    'scheme_id' ) }
			);
			if ( $set_id_and_field{$table} ) {
				$set_id_and_field{$table}->();
			} else {
				( $identifier, $field ) = ( 'scheme_id', 'scheme_id' );
			}
			if ( $q->param('scheme_id_list') eq '0' ) {
				my $set_clause =
				  $set_id ? "WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)" : '';
				$qry2 = "SELECT * FROM $table WHERE $identifier NOT IN (SELECT $field FROM scheme_members $set_clause)";
			} else {
				$qry2 = "SELECT * FROM $table WHERE $identifier IN (SELECT $field FROM scheme_members "
				  . "WHERE scheme_id = $scheme_id)";
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
				$qry2 = 'SELECT * FROM sequence_bin LEFT JOIN experiment_sequences ON sequence_bin.id = '
				  . "experiment_sequences.seqbin_id WHERE experiment_id = $experiment";
				$qry2 .= " AND ($qry)" if $qry;
			} else {
				$qry2 = "SELECT * FROM $table WHERE ($qry)";
			}
		} elsif ( $table eq 'locus_descriptions' && $q->param('common_name_list') ne '' ) {
			my $common_name = $q->param('common_name_list');
			$common_name =~ s/'/\\'/gx;
			$qry2 = 'SELECT * FROM locus_descriptions LEFT JOIN loci ON loci.id = locus_descriptions.locus '
			  . "WHERE common_name = E'$common_name'";
			$qry2 .= " AND ($qry)" if $qry;
		} elsif ( $table eq 'allele_sequences' ) {
			$qry2 = $self->_process_allele_sequences_filters($qry);
		} elsif ( $table eq 'sequences' ) {
			$qry2 = $self->_process_sequences_filters($qry);
		} else {
			$qry ||= '';
			$qry2 = "SELECT * FROM $table WHERE ($qry)";
		}
		foreach (@$attributes) {
			my $param = $_->{'name'} . '_list';
			if ( defined $q->param($param) && $q->param($param) ne '' ) {
				my $value;
				if ( $_->{'name'} eq 'locus' ) {
					( $value = $q->param('locus_list') ) =~ s/^cn_//x;
				} else {
					$value = $q->param($param);
				}
				my $field = "$table." . $_->{'name'};
				if ( $qry2 !~ /WHERE\ \(\)\s*$/x ) {
					$qry2 .= ' AND ';
				} else {
					$qry2 = "SELECT * FROM $table WHERE ";
				}
				$value =~ s/'/\\'/gx;
				$qry2 .= ( $value eq 'null' ? "$_ is null" : "$field = E'$value'" );
			}
		}
		if ( $table eq 'sequences' ) {
			$qry2 .=
			  " AND $table.allele_id NOT IN ('0', 'N')"; #Alleles can be set to 0 or N for arbitrary profile definitions
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
	push @hidden_attributes, qw (no_js sequence_flag_list duplicates_list common_name_list scheme_id_list);
	if (@$errors) {
		local $" = '<br />';
		say q(<div class="box" id="statusbad"><p>Problem with search criteria:</p>);
		say qq(<p>@$errors</p></div>);
	} elsif ( $qry2 !~ /\(\)/x ) {
		my $args = { table => $table, query => $qry2, hidden_attributes => \@hidden_attributes };
		$args->{'passed_qry_file'} = $q->param('query_file') if defined $q->param('query_file');
		$self->paged_display($args);
	} else {
		$qry = "SELECT * FROM $table";

		#Alleles can be set to 0 or N for arbitrary profile definitions
		if ( $table eq 'sequences' ) {
			$qry .= " WHERE $table.allele_id NOT IN ('0', 'N')";
		}
		$qry .= " ORDER BY $table.";
		my $default_order;
		if    ( $table eq 'sequences' )       { $default_order = 'locus' }
		elsif ( $table eq 'history' )         { $default_order = 'timestamp' }
		elsif ( $table eq 'profile_history' ) { $default_order = 'timestamp' }
		else                                  { $default_order = 'id' }
		$qry .= $q->param('order') || $default_order;
		my $dir = $q->param('direction') eq 'descending' ? 'desc' : 'asc';
		my @primary_keys = $self->{'datastore'}->get_primary_keys($table);
		local $" = ",$table.";
		$qry .= " $dir,$table.@primary_keys;";
		$qry =~ s/sequences.sequence_length/length(sequences.sequence)/gx;
		my $args = { table => $table, query => $qry, hidden_attributes => \@hidden_attributes };
		$args->{'passed_qry_file'} = $q->param('query_file') if defined $q->param('query_file');
		$self->paged_display($args);
	}
	return;
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

sub _generate_query {
	my ( $self, $table ) = @_;
	my $q = $self->{'cgi'};
	my $qry;
	my @errors;
	my $andor       = $q->param('c0');
	my $first_value = 1;
	my $set_id      = $self->get_set_id;
	foreach my $i ( 1 .. MAX_ROWS ) {
		next if !defined $q->param("t$i") || $q->param("t$i") eq q();
		my $field    = $q->param("s$i");
		my $operator = $q->param("y$i") // '=';
		my $text     = $q->param("t$i");
		if ( $field eq 'locus' && $set_id ) {
			$text = $self->{'datastore'}->get_set_locus_real_id( $text, $set_id );
		}
		$self->process_value( \$text );
		my ( $thisfield, $clean_fieldname ) = $self->_get_field_attributes( $table, $field );

		#Field may not actually exist in table (e.g. isolate_id in allele_sequences)
		if ( $thisfield->{'type'} ) {
			next
			  if $self->check_format(
				{
					field           => $field,
					text            => $text,
					type            => lc( $thisfield->{'type'} ),
					operator        => $operator,
					clean_fieldname => $clean_fieldname
				},
				\@errors
			  );
		} elsif ( $field =~ /(.*)\ \(id\)$/x || $field eq 'isolate_id' ) {
			next
			  if $self->check_format( { field => $field, text => $text, type => 'int', operator => $operator },
				\@errors );
		}
		my $modifier = ( $i > 1 && !$first_value ) ? qq( $andor ) : q();
		$first_value = 0;
		my %table_without_isolate_id = map { $_ => 1 } qw (allele_sequences experiment_sequences);
		if ( ( $table eq 'allele_sequences' || $table eq 'experiment_sequences' ) && $field eq 'isolate_id' ) {
			$qry .= $modifier . $self->_search_by_isolate_id( $table, $operator, $text );
			next;
		}
		if ( $table eq 'sequence_bin' && $field =~ /^ext_/x ) {
			$qry .= $modifier
			  . $self->_modify_search_by_sequence_attributes( $field, $thisfield->{'type'}, $operator, $text );
			next;
		}
		my %table_linked_to_isolate = map { $_ => 1 }
		  qw (allele_sequences allele_designations experiment_sequences sequence_bin
		  project_members isolate_aliases samples history);
		if ( $table_linked_to_isolate{$table} && $field eq $self->{'system'}->{'labelfield'} ) {
			$qry .= $modifier . $self->_search_by_isolate( $table, $operator, $text );
			next;
		}
		if (
			any {
				$field =~ /(.*)\ \($_\)$/x;
			}
			qw (id surname first_name affiliation)
		  )
		{
			$qry .= $modifier . $self->search_users( $field, $operator, $text, $table );
			next;
		}
		if ( $field =~ /(.*)\ \(date\)$/x ) {
			$qry .= $modifier . $self->_search_timestamp_by_date( $1, $operator, $text, $table );
			next;
		}
		$qry .= $modifier;
		my %methods = (
			'NOT' => sub {
				if ( $text eq 'null' ) {
					$qry .= "$table.$field is not null";
				} else {
					$qry .=
					  $thisfield->{'type'} ne 'text'
					  ? "(NOT CAST($table.$field AS text) = '$text'"
					  : "(NOT upper($table.$field) = upper(E'$text')";
					$qry .= " OR $table.$field IS NULL)";
				}
			},
			'contains' => sub {
				$qry .=
				  $thisfield->{'type'} ne 'text'
				  ? "CAST($table.$field AS text) LIKE '\%$text\%'"
				  : "$table.$field ILIKE E'\%$text\%'";
			},
			'starts with' => sub {
				$qry .=
				  $thisfield->{'type'} ne 'text'
				  ? "CAST($table.$field AS text) LIKE '$text\%'"
				  : "$table.$field ILIKE E'$text\%'";
			},
			'ends with' => sub {
				$qry .=
				  $thisfield->{'type'} ne 'text'
				  ? "CAST($table.$field AS text) LIKE '\%$text'"
				  : "$table.$field ILIKE E'\%$text'";
			},
			'NOT contain' => sub {
				$qry .=
				  $thisfield->{'type'} ne 'text'
				  ? "(NOT CAST($table.$field AS text) LIKE '\%$text\%'"
				  : "(NOT $table.$field ILIKE E'\%$text\%'";
				$qry .= " OR $table.$field IS NULL)";
			},
			'=' => sub {
				if ( $thisfield->{'type'} eq 'text' ) {
					$qry .= ( $text eq 'null' ? "$table.$field is null" : "upper($table.$field) = upper(E'$text')" );
				} else {
					$qry .= ( $text eq 'null' ? "$table.$field is null" : "$table.$field = '$text'" );
				}
			}
		);
		if ( $methods{$operator} ) {
			$methods{$operator}->();
		} else {
			if ( ( $table eq 'sequences' || $table eq 'allele_designations' ) && $field eq 'allele_id' ) {
				if ( $self->_are_only_int_allele_ids_used && BIGSdb::Utils::is_int($text) ) {
					$qry .= "CAST($table.$field AS integer)";
				} else {
					$qry .= "$table.$field";
				}
				$qry .= " $operator E'$text'";
			} else {
				$qry .= "$table.$field $operator E'$text'";
			}
		}
	}
	return ( $qry, \@errors );
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
	if ( $table eq 'loci' ) { $identifier = 'id' }
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
	return if any { $q->param('table') eq $_ } qw (samples sequences history profile_history);
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

sub _search_by_isolate_id {
	my ( $self, $table, $operator, $text ) = @_;
	my $qry = "$table.seqbin_id IN (SELECT sequence_bin.id FROM sequence_bin LEFT JOIN "
	  . "$self->{'system'}->{'view'} ON isolate_id = $self->{'system'}->{'view'}.id WHERE ";
	my %terms = (
		'NOT'         => "NOT $self->{'system'}->{'view'}.id = $text",
		'contains'    => "CAST($self->{'system'}->{'view'}.id AS text) LIKE '\%$text\%'",
		'starts with' => "CAST($self->{'system'}->{'view'}.id AS text) LIKE '$text\%'",
		'ends with'   => "CAST($self->{'system'}->{'view'}.id AS text) LIKE '\%$text'",
		'NOT contain' => "NOT CAST($self->{'system'}->{'view'}.id AS text) LIKE '\%$text\%'"
	);
	if ( $terms{$operator} ) {
		$qry .= $terms{$operator};
	} else {
		$qry .= "$self->{'system'}->{'view'}.id $operator $text";
	}
	$qry .= ')';
	return $qry;
}

sub _modify_search_by_sequence_attributes {
	my ( $self, $field, $type, $operator, $text ) = @_;
	$field =~ s/^ext_//x;
	if ( $text eq 'null' ) {
		my $inv_not = $operator =~ /NOT/x ? q() : ' NOT';
		return "sequence_bin.id$inv_not IN (SELECT seqbin_id FROM sequence_attribute_values)";
	}
	my $not   = $operator =~ /NOT/x ? ' NOT' : '';
	my $qry   = "sequence_bin.id$not IN (SELECT seqbin_id FROM sequence_attribute_values WHERE key='$field' AND ";
	my %terms = (
		'contains'    => "value ILIKE E'%$text%'",
		'NOT contain' => "value ILIKE E'%$text%'",
		'starts with' => "value ILIKE E'$text%'",
		'ends with'   => "value ILIKE E'%$text'",
		'NOT'         => "UPPER(value) = UPPER(E'$text')",
		'='           => "UPPER(value) = UPPER(E'$text')"
	);
	if ( $terms{$operator} ) {
		$qry .= $terms{$operator};
	} else {
		if ( $type eq 'integer' ) { $qry .= "CAST(value AS INT) $operator CAST(E'$text' AS INT)" }
		elsif ( $type eq 'float' ) {
			$qry .= "CAST(value AS FLOAT) $operator CAST(E'$text' AS FLOAT)";
		} else {
			$qry .= "UPPER(value) $operator UPPER(E'$text')";
		}
	}
	$qry .= ')';
	return $qry;
}

sub _search_by_isolate {
	my ( $self, $table, $operator, $text ) = @_;
	my $att   = $self->{'xmlHandler'}->get_field_attributes( $self->{'system'}->{'labelfield'} );
	my $field = $self->{'system'}->{'labelfield'};
	my $qry;
	if ( $table eq 'allele_sequences' || $table eq 'experiment_sequences' ) {
		$qry = "$table.seqbin_id IN (SELECT sequence_bin.id FROM sequence_bin LEFT JOIN $self->{'system'}->{'view'} ON "
		  . "isolate_id = $self->{'system'}->{'view'}.id WHERE ";
	} elsif ( $table eq 'sequence_bin' ) {
		$qry = "sequence_bin.id IN (SELECT sequence_bin.id FROM sequence_bin LEFT JOIN $self->{'system'}->{'view'} ON "
		  . "isolate_id = $self->{'system'}->{'view'}.id WHERE ";
	} elsif (
		any {
			$table eq $_;
		}
		qw (allele_designations project_members isolate_aliases samples history)
	  )
	{
		$qry = "$table.isolate_id IN (SELECT id FROM $self->{'system'}->{'view'} WHERE ";
	} else {
		$logger->error("Invalid table $table");
		return;
	}
	my %methods = (
		NOT => sub {
			if ( $text eq '<blank>' || $text eq 'null' ) {
				$qry .= "$field is not null";
			} else {
				if ( $att->{'type'} eq 'int' ) {
					$qry .= "NOT CAST($field AS text) = E'$text'";
				} else {
					$qry .= "NOT upper($field) = upper(E'$text') AND $self->{'system'}->{'view'}.id NOT IN "
					  . "(SELECT isolate_id FROM isolate_aliases WHERE upper(alias) = upper(E'$text'))";
				}
			}
		},
		contains => sub {
			if ( $att->{'type'} eq 'int' ) {
				$qry .= "CAST($field AS text) LIKE E'\%$text\%'";
			} else {
				$qry .=
				  "upper($field) LIKE upper(E'\%$text\%') OR $self->{'system'}->{'view'}.id IN (SELECT isolate_id FROM "
				  . "isolate_aliases WHERE upper(alias) LIKE upper(E'\%$text\%'))";
			}
		},
		'starts with' => sub {
			if ( $att->{'type'} eq 'int' ) {
				$qry .= "CAST($field AS text) LIKE E'$text\%'";
			} else {
				$qry .=
				    "upper($field) LIKE upper(E'$text\%') OR $self->{'system'}->{'view'}.id IN (SELECT isolate_id FROM "
				  . "isolate_aliases WHERE upper(alias) LIKE upper(E'$text\%'))";
			}
		},
		'ends with' => sub {
			if ( $att->{'type'} eq 'int' ) {
				$qry .= "CAST($field AS text) LIKE E'\%$text'";
			} else {
				$qry .=
				    "upper($field) LIKE upper(E'\%$text') OR $self->{'system'}->{'view'}.id IN (SELECT isolate_id FROM "
				  . "isolate_aliases WHERE upper(alias) LIKE upper(E'\%$text'))";
			}
		},
		'NOT contain' => sub {
			if ( $att->{'type'} eq 'int' ) {
				$qry .= "NOT CAST($field AS text) LIKE E'\%$text\%'";
			} else {
				$qry .= "NOT upper($field) LIKE upper(E'\%$text\%') AND $self->{'system'}->{'view'}.id NOT IN "
				  . "(SELECT isolate_id FROM isolate_aliases WHERE upper(alias) LIKE upper(E'\%$text\%'))";
			}
		},
		'=' => sub {
			if ( lc( $att->{'type'} ) eq 'text' ) {
				$qry .= (
					( $text eq '<blank>' || $text eq 'null' )
					? "$field is null"
					: "upper($field) = upper(E'$text') OR $self->{'system'}->{'view'}.id IN "
					  . "(SELECT isolate_id FROM isolate_aliases WHERE upper(alias) = upper(E'$text'))"
				);
			} else {
				$qry .= ( ( $text eq '<blank>' || $text eq 'null' ) ? "$field is null" : "$field = E'$text'" );
			}
		}
	);
	if ( $methods{$operator} ) {
		$methods{$operator}->();
	} else {
		$qry .= "$field $operator E'$text'";
	}
	$qry .= ')';
	return $qry;
}

sub _process_allele_sequences_filters {
	my ( $self, $qry ) = @_;
	my $q = $self->{'cgi'};
	my $qry2;
	my @conditions;
	if ( any { $q->param($_) ne '' } qw (sequence_flag_list duplicates_list scheme_id_list) ) {
		if ( $q->param('sequence_flag_list') ne '' ) {
			if ( $q->param('sequence_flag_list') eq 'no flag' ) {
				$qry2 = 'SELECT * FROM allele_sequences LEFT JOIN sequence_flags ON '
				  . 'sequence_flags.id = allele_sequences.id';
				push @conditions, 'flag IS NULL';
			} else {
				$qry2 = 'SELECT * FROM allele_sequences INNER JOIN sequence_flags ON '
				  . 'sequence_flags.id = allele_sequences.id';
				if ( any { $q->param('sequence_flag_list') eq $_ } SEQ_FLAGS ) {
					push @conditions, q(flag = ') . $q->param('sequence_flag_list') . q(');
				}
			}
		}
		if ( $q->param('duplicates_list') ne '' ) {
			my $match = BIGSdb::Utils::is_int( $q->param('duplicates_list') ) ? $q->param('duplicates_list') : 1;
			my $not = $match == 1 ? 'NOT' : '';

			#no dups == NOT 2 or more
			$match = 2 if $match == 1;
			my $dup_qry = " WHERE (allele_sequences.locus,allele_sequences.isolate_id) $not IN (SELECT "
			  . "locus,isolate_id FROM allele_sequences GROUP BY locus,isolate_id HAVING count(*)>=$match)";
			if ($qry2) {
				$qry2 .= $dup_qry;
			} else {
				$qry2 = "SELECT * FROM allele_sequences$dup_qry";
			}
		}
		if ( $q->param('scheme_id_list') ne '' ) {
			my $scheme_qry =
			    'allele_sequences.locus IN (SELECT DISTINCT allele_sequences.locus FROM '
			  . 'allele_sequences LEFT JOIN scheme_members ON allele_sequences.locus = scheme_members.locus '
			  . 'WHERE scheme_id';
			if ( $q->param('scheme_id_list') eq '0' ) {
				$scheme_qry .= ' IS NULL)';
			} else {
				$scheme_qry .= '=' . $q->param('scheme_id_list') . ')';
			}
			if ($qry2) {
				$qry2 .= ( $q->param('duplicates_list') || $q->param('scheme_id_list') ) ? ' AND ' : ' WHERE ';
				$qry2 .= "($scheme_qry)";
			} else {
				$qry2 = "SELECT * FROM allele_sequences WHERE ($scheme_qry)";
			}
		}
		if (@conditions) {
			local $" = ') AND (';
			$qry2 .= $q->param('duplicates_list') ne '' ? ' AND' : ' WHERE';
			$qry2 .= " (@conditions)";
		}
		$qry2 .= " AND ($qry)" if $qry;
	} else {
		$qry ||= '';
		$qry2 = "SELECT * FROM allele_sequences WHERE ($qry)";
	}
	return $qry2;
}

sub _process_sequences_filters {
	my ( $self, $qry ) = @_;
	my $q = $self->{'cgi'};
	my $qry2;
	if ( ( $q->param('allele_flag_list') // '' ) ne '' && ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
		if ( $q->param('allele_flag_list') eq 'no flag' ) {
			$qry2 = 'SELECT * FROM sequences LEFT JOIN allele_flags ON allele_flags.locus = sequences.locus AND '
			  . 'allele_flags.allele_id = sequences.allele_id WHERE flag IS NULL';
		} else {
			$qry2 = 'SELECT * FROM sequences WHERE EXISTS (SELECT 1 FROM allele_flags WHERE '
			  . 'sequences.locus=allele_flags.locus AND sequences.allele_id=allele_flags.allele_id';
			if ( any { $q->param('allele_flag_list') eq $_ } ALLELE_FLAGS ) {
				$qry2 .= q( AND flag = ') . $q->param('allele_flag_list') . q(');
			}
			$qry2 .= ')';
		}
		$qry2 .= " AND ($qry)" if $qry;
	} else {
		$qry ||= '';
		$qry2 = "SELECT * FROM sequences WHERE ($qry)";
	}
	return $qry2;
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

sub _search_timestamp_by_date {
	my ( $self, $field, $operator, $text, $table ) = @_;
	if ( $operator eq 'NOT' ) {
		return "(NOT date($table.$field) = '$text')";
	}
	return "(date($table.$field) $operator '$text')";
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
