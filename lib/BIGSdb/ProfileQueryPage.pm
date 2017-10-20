#Written by Keith Jolley
#Copyright (c) 2010-2017, University of Oxford
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
use BIGSdb::Constants qw(:interface OPERATORS);
use List::MoreUtils qw(any uniq);
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

sub _save_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $guid   = $self->get_guid;
	return if !$guid;
	foreach my $attribute (qw (scheme list filters)) {
		my $value = $q->param($attribute) ? 'on' : 'off';
		$self->{'prefstore'}->set_general( $guid, $self->{'system'}->{'db'}, "${attribute}_fieldset", $value );
	}
	return;
}

sub get_help_url {
	my ($self) = @_;
	if ( $self->{'curate'} ) {
		return "$self->{'config'}->{'doclink'}/curator_guide.html#updating-and-deleting-scheme-profile-definitions";
	} else {
		return "$self->{'config'}->{'doclink'}/data_query.html#querying-scheme-profile-definitions";
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return $self->{'curate'} ? "Profile query/update - $desc" : "Search/browse database - $desc";
}

sub print_content {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $q      = $self->{'cgi'};
	my $scheme_info;
	if    ( $q->param('no_header') )    { $self->_ajax_content; return }
	elsif ( $q->param('save_options') ) { $self->_save_options; return }
	my $desc = $self->get_db_description;
	say $self->{'curate'}
	  ? qq(<h1>Query/update profiles - $desc</h1>)
	  : qq(<h1>Search or browse profiles - $desc</h1>);
	my $qry;

	if ( !defined $q->param('currentpage') || $q->param('First') ) {
		say q(<noscript><div class="box statusbad"><p>This interface requires )
		  . q(that you enable Javascript in your browser.</p></div></noscript>);
		return if $self->_print_interface;    #Returns 1 if scheme is invalid
	}
	$self->_run_query if $q->param('submit') || defined $q->param('query_file');
	return;
}

sub initiate {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	$self->SUPER::initiate;
	$self->{'noCache'} = 1;
	if ( !$self->{'cgi'}->param('save_options') ) {
		my $guid = $self->get_guid;
		return if !$guid;
		foreach my $attribute (qw (list filters)) {
			my $value =
			  $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, "${attribute}_fieldset" );
			$self->{'prefs'}->{"${attribute}_fieldset"} = ( $value // '' ) eq 'on' ? 1 : 0;
		}
		my $value = $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, 'scheme_fieldset' );
		$self->{'prefs'}->{'scheme_fieldset'} = ( $value // '' ) eq 'off' ? 0 : 1;
	}
	return;
}

sub _print_interface {
	my ($self)    = @_;
	my $system    = $self->{'system'};
	my $prefs     = $self->{'prefs'};
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	return 1 if defined $scheme_id && $self->is_scheme_invalid( $scheme_id, { with_pk => 1 } );
	$self->print_scheme_section( { with_pk => 1 } );
	$scheme_id = $q->param('scheme_id');    #Will be set by scheme section method
	say q(<div class="box" id="queryform"><div class="scrollable">);
	say q(<p>Enter search criteria or leave blank to browse all records. Modify form parameters to filter or )
	  . q(enter a list of values.</p>);
	say $q->start_form;
	say $q->hidden($_) foreach qw (db page scheme_id);
	my $scheme_field_count = $self->_highest_entered_fields || 1;
	my $scheme_field_heading = $scheme_field_count == 1 ? 'none' : 'inline';
	say q(<div style="white-space:nowrap">);
	my $display = $self->{'prefs'}->{'scheme_fieldset'}
	  || $self->_highest_entered_fields ? 'inline' : 'none';
	say qq(<fieldset style="float:left;display:$display" id="scheme_fieldset"><legend>Locus/scheme fields</legend>);
	say qq(<span id="scheme_field_heading" style="display:$scheme_field_heading">)
	  . q(<label for="c0">Combine searches with: </label>);
	say $q->popup_menu( -name => 'c0', -id => 'c0', -values => [qw(AND OR)] );
	say q(</span><ul id="scheme_fields">);
	my ( $primary_key, $selectitems, $orderitems, $cleaned ) = $self->_get_select_items($scheme_id);

	foreach my $i ( 1 .. $scheme_field_count ) {
		print q(<li>);
		$self->_print_scheme_fields( $i, $scheme_field_count, $scheme_id, $selectitems, $cleaned );
		say q(</li>);
	}
	say q(</ul></fieldset>);
	$self->_print_list_fieldset($scheme_id);
	$self->_print_filter_fieldset($scheme_id);
	$self->_print_order_fieldset($scheme_id);
	$self->print_action_fieldset( { page => 'query', scheme_id => $scheme_id } );
	$self->_print_modify_search_fieldset;
	say q(</div>);
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub _print_filter_fieldset {
	my ( $self, $scheme_id ) = @_;
	my $q = $self->{'cgi'};
	my @filters;
	my $set_id = $self->get_set_id;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	if ( $self->{'config'}->{'ref_db'} ) {
		my $pmid = $self->{'datastore'}->run_query( 'SELECT DISTINCT(pubmed_id) FROM profile_refs WHERE scheme_id=?',
			$scheme_id, { fetch => 'col_arrayref' } );
		if (@$pmid) {
			my $labels = $self->{'datastore'}->get_citation_hash($pmid);
			my @values = sort { $labels->{$a} cmp $labels->{$b} } keys %$labels;
			push @filters,
			  $self->get_filter(
				'publication',
				\@values,
				{
					labels  => $labels,
					text    => 'Publication',
					tooltip => 'publication filter - Select a publication to filter your search '
					  . 'to only those isolates that match the selected publication.'
				}
			  );
		}
	}
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach my $field (@$scheme_fields) {
		if ( $self->{'prefs'}->{'dropdown_scheme_fields'}->{$scheme_id}->{$field} ) {
			my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
			my $value_clause = $scheme_field_info->{'type'} eq 'integer' ? 'CAST(value AS integer)' : 'value';
			my $values = $self->{'datastore'}->run_query(
				"SELECT DISTINCT $value_clause FROM profile_fields WHERE "
				  . "(scheme_id,scheme_field)=(?,?) ORDER BY $value_clause",
				[ $scheme_id, $field ],
				{ fetch => 'col_arrayref' }
			);
			next if !@$values;
			my $a_or_an = substr( $field, 0, 1 ) =~ /[aeiouAEIOU]/x ? 'an' : 'a';
			push @filters,
			  $self->get_filter(
				$field, $values,
				{
					text    => $field,
					tooltip => "$field ($scheme_info->{'name'}) filter - Select $a_or_an $field to "
					  . "filter your search to only those profiles that match the selected $field."
				}
			  );
		}
	}
	if (@filters) {
		say q(<fieldset id="filters_fieldset" style="float:left;display:none"><legend>Filters</legend>);
		say q(<ul>);
		say qq(<li><span style="white-space:nowrap">$_</span></li>) foreach @filters;
		say q(</ul></fieldset>);
		$self->{'filters_present'} = 1;
	}
	return;
}

sub _print_order_fieldset {
	my ( $self, $scheme_id ) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset id="display_fieldset" style="float:left"><legend>Display/sort options</legend>);
	say q(<ul><li><span style="white-space:nowrap"><label for="order" class="display">Order by: </label>);
	my ( $primary_key, $selectitems, $orderitems, $cleaned ) = $self->_get_select_items($scheme_id);
	say $q->popup_menu( -name => 'order', -id => 'order', -values => $orderitems, -labels => $cleaned );
	say $q->popup_menu( -name => 'direction', -values => [qw(ascending descending)], -default => 'ascending' );
	say q(</span></li><li>);
	say $self->get_number_records_control;
	say q(</li></ul></fieldset>);
	return;
}

sub _print_scheme_fields {
	my ( $self, $row, $max_rows, $scheme_id, $selectitems, $labels ) = @_;
	my $q = $self->{'cgi'};
	say q(<span style="white-space:nowrap">);
	say $q->popup_menu( -name => "s$row", -values => $selectitems, -labels => $labels, -class => 'fieldlist' );
	say $q->popup_menu( -name => "y$row", -values => [OPERATORS] );
	say $q->textfield( -name => "t$row", -class => 'value_entry' );
	if ( $row == 1 ) {
		my $next_row = $max_rows ? $max_rows + 1 : 2;
		print qq(<a id="add_scheme_fields" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=query&amp;fields=scheme_fields&amp;scheme_id=$scheme_id&amp;row=$next_row&amp;no_header=1" )
		  . q(data-rel="ajax" class="button">+</a> <a class="tooltip" id="scheme_field_tooltip" title="">)
		  . q(<span class="fa fa-info-circle"></span></a>);
	}
	say q(</span>);
	return;
}

sub _get_select_items {
	my ( $self, $scheme_id ) = @_;
	my ( @selectitems, @orderitems, %cleaned );
	my $loci        = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	if ( !defined $primary_key ) {
		$logger->error('No primary key - this should not have been called.');
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
	push @selectitems, qw(date_entered datestamp);
	$cleaned{'date_entered'} = 'date entered';
	( $cleaned{$primary_key} = $primary_key ) =~ tr/_/ /;
	return ( $primary_key, \@selectitems, \@orderitems, \%cleaned );
}

sub _run_query {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $system = $self->{'system'};
	my ( $qry, $list_file );
	my $errors = [];
	my $scheme_id = BIGSdb::Utils::is_int( $q->param('scheme_id') ) ? $q->param('scheme_id') : 0;
	if ( !defined $q->param('query_file') ) {
		( $qry, $list_file, $errors ) = $self->_generate_query($scheme_id);
		$q->param( list_file => $list_file );
	} else {
		$qry = $self->get_query_from_temp_file( $q->param('query_file') );
		if ( $q->param('list_file') ) {
			$self->{'datastore'}->create_temp_list_table( 'text', $q->param('list_file') );
		}
	}
	my $browse;
	if ( $qry =~ /\(\)/x ) {
		$qry =~ s/\ WHERE\ \(\)//x;
		$browse = 1;
	}
	if (@$errors) {
		local $" = '<br />';
		say q(<div class="box" id="statusbad"><p>Problem with search criteria:</p>);
		say qq(<p>@$errors</p></div>);
	} else {
		my @hidden_attributes;
		push @hidden_attributes, 'c0', 'c1';
		foreach my $i ( 1 .. MAX_ROWS ) {
			push @hidden_attributes, "s$i", "t$i", "y$i", "ls$i", "ly$i", "lt$i";
		}
		foreach ( @{ $self->{'xmlHandler'}->get_field_list } ) {
			push @hidden_attributes, $_ . '_list';
		}
		push @hidden_attributes, qw (publication_list scheme_id list list_file datatype);
		my $args = { table => 'profiles', query => $qry, browse => $browse, hidden_attributes => \@hidden_attributes };
		$args->{'passed_qry_file'} = $q->param('query_file') if defined $q->param('query_file');
		$self->paged_display($args);
	}
	return;
}

sub _is_locus_in_scheme {
	my ( $self, $scheme_id, $locus ) = @_;
	if ( !$self->{'cache'}->{'is_scheme_locus'}->{$scheme_id} ) {
		my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
		%{ $self->{'cache'}->{'is_scheme_locus'}->{$scheme_id} } = map { $_ => 1 } @$loci;
	}
	return $self->{'cache'}->{'is_scheme_locus'}->{$scheme_id}->{$locus};
}

sub _generate_query {
	my ( $self, $scheme_id ) = @_;
	my $q = $self->{'cgi'};
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my ( $qry, $errors ) = $self->_generate_query_from_locus_fields($scheme_id);
	( $qry, my $list_file ) = $self->_modify_by_list( $scheme_id, $qry );
	$q->param( datatype => 'text' );
	$qry = $self->_modify_query_for_filters( $scheme_id, $qry );
	my $primary_key   = $scheme_info->{'primary_key'};
	my $order         = $q->param('order') || $primary_key;
	my $dir           = ( defined $q->param('direction') && $q->param('direction') eq 'descending' ) ? 'desc' : 'asc';
	my $pk_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	my $profile_id_field = $pk_field_info->{'type'} eq 'integer' ? "lpad($primary_key,20,'0')" : $primary_key;

	if ( $self->{'datastore'}->is_locus($order) ) {
		my $locus_info = $self->{'datastore'}->get_locus_info($order);
		my $cleaned_order = $self->{'datastore'}->get_scheme_warehouse_locus_name( $scheme_id, $order );
		if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
			$order = "to_number(textcat('0', $cleaned_order), text(99999999))";    #Handle arbitrary allele = 'N'
		}
	}
	$qry .= ' ORDER BY' . ( $order ne $primary_key ? " $order $dir,$profile_id_field;" : " $profile_id_field $dir;" );
	return ( $qry, $list_file, $errors );
}

sub _get_data_type {
	my ( $self, $scheme_id, $field ) = @_;
	my %date_fields = map { $_ => 1 } qw(date_entered datestamp);
	my $is_locus = $self->_is_locus_in_scheme( $scheme_id, $field );
	if ($is_locus) {
		return $self->{'datastore'}->get_locus_info($field)->{'allele_id_format'};
	} elsif ( $self->{'datastore'}->is_scheme_field( $scheme_id, $field ) ) {
		return $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field )->{'type'};
	} elsif ( $date_fields{$field} ) {
		return 'date';
	}
	return;
}

sub _generate_query_from_locus_fields {
	my ( $self, $scheme_id ) = @_;
	my $q                = $self->{'cgi'};
	my $errors           = [];
	my $scheme_info      = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $qry              = "SELECT * FROM $scheme_warehouse WHERE (";
	my $andor            = $q->param('c0');
	my $first_value      = 1;
	my %standard_fields  = map { $_ => 1 } (
		'sender (id)',
		'sender (surname)',
		'sender (first_name)',
		'sender (affiliation)',
		'curator (id)',
		'curator (surname)',
		'curator (first_name)',
		'curator (affiliation)',
		'date_entered',
		'datestamp'
	);

	foreach my $i ( 1 .. MAX_ROWS ) {
		next if !defined $q->param("t$i") || $q->param("t$i") eq q();
		my $field = $q->param("s$i");
		my $type = $self->_get_data_type( $scheme_id, $field );
		if ( !defined $type && !$standard_fields{$field} ) {

			#Prevent cross-site scripting vulnerability
			( my $cleaned_field = $field ) =~ s/[^A-z].*$//x;
			push @$errors, "Field $cleaned_field is not recognized.";
			$logger->error("Attempt to modify fieldname: $field");
			next;
		}
		my $operator = $q->param("y$i") // '=';
		my $text = $q->param("t$i");
		$self->process_value( \$text );
		my $is_locus = $self->_is_locus_in_scheme( $scheme_id, $field );
		next
		  if !($scheme_info->{'allow_missing_loci'}
			&& $is_locus
			&& $text eq 'N'
			&& $operator ne '<'
			&& $operator ne '>' )
		  && $self->check_format( { field => $field, text => $text, type => $type, operator => $operator }, \@$errors );
		my $modifier = ( $i > 1 && !$first_value ) ? " $andor " : '';
		$first_value = 0;

		if ( $field =~ /(.*)\ \(id\)$/x
			&& !BIGSdb::Utils::is_int($text) )
		{
			push @$errors, "$field is an integer field.";
			next;
		}
		$qry .= $modifier;
		my $cleaned_field = $field;
		if ($is_locus) {
			$cleaned_field = $self->{'datastore'}->get_scheme_warehouse_locus_name( $scheme_id, $field );
		}
		if ( any { $field =~ /(.*)\ \($_\)$/x } qw (id surname first_name affiliation) ) {
			$qry .= $self->search_users( $field, $operator, $text, $scheme_warehouse );
		} else {
			my $equals =
			  lc($text) eq 'null'
			  ? "$cleaned_field is null"
			  : ( $type eq 'text' ? "UPPER($cleaned_field)=UPPER('$text')" : "$cleaned_field='$text'" );
			$equals .= " OR $cleaned_field='N'" if $is_locus && $scheme_info->{'allow_missing_loci'};
			my %modify = (
				'NOT' => lc($text) eq 'null' ? "(NOT $equals)" : "((NOT $equals) OR $cleaned_field IS NULL)",
				'contains'    => "(UPPER($cleaned_field) LIKE UPPER('\%$text\%'))",
				'starts with' => "(UPPER($cleaned_field) LIKE UPPER('$text\%'))",
				'ends with'   => "(UPPER($cleaned_field) LIKE UPPER('\%$text'))",
				'NOT contain' => "(NOT UPPER($cleaned_field) LIKE UPPER('\%$text\%') OR $cleaned_field IS NULL)",
				'='           => "($equals)"
			);
			if ( $modify{$operator} ) {
				$qry .= $modify{$operator};
			} else {
				if ( lc($text) eq 'null' ) {
					my $clean_operator = $operator;
					$clean_operator =~ s/>/&gt;/x;
					$clean_operator =~ s/</&lt;/x;
					push @$errors, "$clean_operator is not a valid operator for comparing null values.";
				}
				$qry .= (
					$type eq 'integer'
					? "(to_number(textcat('0', $cleaned_field), text(99999999))"
					: "($cleaned_field"
				) . " $operator '$text')";
			}
		}
	}
	$qry .= ')';
	return ( $qry, $errors );
}

sub _modify_query_for_filters {
	my ( $self, $scheme_id, $qry ) = @_;
	my $q                = $self->{'cgi'};
	my $scheme_info      = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $primary_key      = $scheme_info->{'primary_key'};
	if ( defined $q->param('publication_list') && $q->param('publication_list') ne '' ) {
		my $pmid = $q->param('publication_list');
		my $ids  = $self->{'datastore'}->run_query(
			'SELECT profile_id FROM profile_refs WHERE (scheme_id,pubmed_id)=(?,?)',
			[ $scheme_id, $pmid ],
			{ fetch => 'col_arrayref' }
		);
		if ($pmid) {
			local $" = q(',');
			if ( $qry !~ /WHERE\ \(\)\s*$/x ) {
				$qry .= " AND ($primary_key IN ('@$ids'))";
			} else {
				$qry = "SELECT * FROM $scheme_warehouse WHERE ($primary_key IN ('@$ids'))";
			}
		}
	}
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach my $field (@$scheme_fields) {
		if ( defined $q->param("${field}_list") && $q->param("${field}_list") ne '' ) {
			my $value = $q->param("${field}_list");
			$value =~ s/'/\\'/gx;
			if ( $qry !~ /WHERE\ \(\)\s*$/x ) {
				$qry .= " AND (UPPER($field) = UPPER(E'$value'))";
			} else {
				$qry = "SELECT * FROM $scheme_warehouse WHERE (UPPER($field)=UPPER(E'$value'))";
			}
		}
	}
	return $qry;
}

sub _modify_by_list {
	my ( $self, $scheme_id, $qry ) = @_;
	my $q = $self->{'cgi'};
	return $qry if !$q->param('list');
	my $field;
	if ( $q->param('attribute') =~ /^s_${scheme_id}_(.*)$/x ) {
		$field = $1;
		return $qry if !$self->{'datastore'}->is_scheme_field( $scheme_id, $field );
	} elsif ( $q->param('attribute') =~ /^l_(.*)$/x ) {
		my $locus = $1;
		return $qry if !$self->_is_locus_in_scheme( $scheme_id, $locus );
		$field = $self->{'datastore'}->get_scheme_warehouse_locus_name( $scheme_id, $locus );
	}
	my @list = split /\n/x, $q->param('list');
	@list = uniq @list;
	BIGSdb::Utils::remove_trailing_spaces_from_list( \@list );
	my $list = $self->clean_list( 'text', \@list );
	return $qry if !@list || ( @list == 1 && $list[0] eq q() );
	my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( 'text', $list, { table => 'temp_list' } );
	my $list_file  = BIGSdb::Utils::get_random() . '.list';
	my $full_path  = "$self->{'config'}->{'secure_tmp_dir'}/$list_file";
	open( my $fh, '>:encoding(utf8)', $full_path ) || $logger->error("Can't open $full_path for writing");
	say $fh $_ foreach @list;
	close $fh;
	my $scheme_warehouse = qq(mv_scheme_$scheme_id);

	if ( $qry !~ /WHERE\ \(\)\s*$/x ) {
		$qry .= ' AND ';
	} else {
		$qry = "SELECT * FROM $scheme_warehouse WHERE ";
	}
	$qry .= "($field IN (SELECT value FROM $temp_table))";
	return ( $qry, $list_file );
}

sub _print_list_fieldset {
	my ( $self, $scheme_id ) = @_;
	my $q = $self->{'cgi'};
	my ( $field_list, $labels );
	my $fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach (@$fields) {
		push @$field_list, "s_$scheme_id\_$_";
		( $labels->{"s_$scheme_id\_$_"} = $_ ) =~ tr/_/ /;
	}
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	foreach my $locus (@$loci) {
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		push @$field_list, "l_$locus";
		$labels->{"l_$locus"} = $self->clean_locus( $locus, { text_output => 1 } );
	}
	my $display = $self->{'prefs'}->{'list_fieldset'}
	  || $q->param('list') ? 'inline' : 'none';
	say qq(<fieldset id="list_fieldset" style="float:left;display:$display"><legend>Attribute values list</legend>);
	say q(Field:);
	say $q->popup_menu( -name => 'attribute', -values => $field_list, -labels => $labels );
	say q(<br />);
	say $q->textarea(
		-name        => 'list',
		-id          => 'list',
		-rows        => 6,
		-style       => 'width:100%',
		-placeholder => 'Enter list of values...'
	);
	say q(</fieldset>);
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $filters_fieldset_display = $self->{'prefs'}->{'filters_fieldset'}
	  || $self->filters_selected ? 'inline' : 'none';
	my $panel_js = $self->get_javascript_panel(qw(scheme list filters));
	my $buffer   = $self->SUPER::get_javascript;
	$buffer .= << "END";
\$(function () {
	\$('#filters_fieldset').css({display:"$filters_fieldset_display"});
   	\$('#scheme_field_tooltip').tooltip({ content: "<h3>Search values</h3><p>Empty field "
  		+ "values can be searched using the term 'null'. </p><h3>Number of fields</h3>"
  		+ "<p>Add more fields by clicking the '+' button.</p>"
  		+ "<h3>Query modifier</h3><p>Select 'AND' for the isolate query to match ALL search "
  		+ "terms, 'OR' to match ANY of these terms.</p>" 
   	});
   	$panel_js
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

sub _print_modify_search_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="panel">);
	say q(<a class="trigger" id="close_trigger" href="#"><span class="fa fa-lg fa-close"></span></a>);
	say q(<h2>Modify form parameters</h2>);
	say q(<p style="white-space:nowrap">Click to add or remove additional query terms:</p><ul>);
	my $scheme_fieldset_display = $self->{'prefs'}->{'scheme_fieldset'}
	  || $self->_highest_entered_fields ? HIDE : SHOW;
	say qq(<li><a href="" class="button" id="show_scheme">$scheme_fieldset_display</a>);
	say q(Locus/scheme field values</li>);
	my $list_fieldset_display = $self->{'prefs'}->{'list_fieldset'}
	  || $q->param('list') ? HIDE : SHOW;
	say qq(<li><a href="" class="button" id="show_list">$list_fieldset_display</a>);
	say q(Attribute values list</li>);

	if ( $self->{'filters_present'} ) {
		my $filter_fieldset_display = $self->{'prefs'}->{'filters_fieldset'}
		  || $self->filters_selected ? HIDE : SHOW;
		say qq(<li><a href="" class="button" id="show_filters">$filter_fieldset_display</a>);
		say q(Filters</li>);
	}
	say q(</ul>);
	my $save = SAVE;
	say qq(<a id="save_options" class="button" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=query&amp;save_options=1" style="display:none">$save</a> <span id="saving"></span><br />);
	say q(</div>);
	say q(<a class="trigger" id="panel_trigger" href="" style="display:none">Modify<br />form<br />options</a>);
	return;
}
1;
