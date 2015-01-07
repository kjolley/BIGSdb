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
package BIGSdb::ListQueryPage;
use strict;
use warnings;
use 5.010;
use List::MoreUtils qw(uniq);
use parent qw(BIGSdb::QueryPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Page qw(LOCUS_PATTERN);
use constant INVALID_VALUE => 1;

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { general => 1, main_display => 1, isolate_display => 0, analysis => 0, query_field => 1 };
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "List query - $desc";
}

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/data_query.html#retrieving-list-of-isolates-or-profiles";
}

sub print_content {
	my ($self)    = @_;
	my $system    = $self->{'system'};
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	my $set_id    = $self->get_set_id;
	my $scheme_info;
	my $primary_key;
	my $desc = $self->get_db_description;

	if ( $system->{'dbtype'} eq 'sequences' ) {
		say "<h1>Query profiles by matching a field against a list - $desc</h1>";
		return if defined $scheme_id && $self->is_scheme_invalid( $scheme_id, { with_pk => 1 } );
		$self->print_scheme_section( { with_pk => 1 } );
		$scheme_id = $q->param('scheme_id');    #Will be set by scheme section method
	} else {
		say "<h1>Query $desc database matching a field against a list</h1>";
	}
	my $qry;
	if ( !defined $q->param('currentpage')
		|| $q->param('First') )
	{
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			$self->_print_query_interface;
		} else {
			$self->_print_query_interface($scheme_id);
		}
	}
	if ( defined $q->param('query_file')
		or ( $q->param('attribute') && $q->param('list') ) )
	{
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			$self->_run_isolate_query;
		} else {
			$self->_run_profile_query;
		}
	}
	return;
}

sub _print_query_interface {
	my ( $self, $scheme_id ) = @_;
	my $q = $self->{'cgi'};
	my ( $field_list, $order_list, $labels, $order_labels );
	my @grouped_fields;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		( $order_list, $order_labels ) =
		  $self->get_field_selection_list( { isolate_fields => 1, loci => 1, scheme_fields => 1, sender_attributes => 0, } );
		( $field_list, $labels ) = $self->get_field_selection_list(
			{ isolate_fields => 1, loci => 1, scheme_fields => 1, sender_attributes => 1, extended_attributes => 1 } );
		my $grouped = $self->{'xmlHandler'}->get_grouped_fields;
		foreach (@$grouped) {
			push @grouped_fields, "f_$_";
			( $labels->{"f_$_"} = $_ ) =~ tr/_/ /;
		}
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
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
		$order_list   = $field_list;
		$order_labels = $labels;
	}
	say qq(<div class="box" id="queryform"><div class="scrollable">);
	say $q->start_form;
	say qq(<fieldset id="attribute_fieldset" style="float:left"><legend>Please select attribute</legend>);
	my @select_items = ( @grouped_fields, @$field_list );
	say $q->popup_menu( -name => 'attribute', -values => \@select_items, -labels => $labels );
	say qq(</fieldset><div style="clear:both"></div>);
	say qq(<fieldset id="list_fieldset" style="float:left"><legend>Enter your list of attribute values below (one per line)</legend>);
	say $q->textarea( -name => 'list', -rows => 8, -cols => 40 );
	say "</fieldset>";

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say qq(<fieldset style="float:left"><legend>Filters</legend>);
		say $self->get_old_version_filter;
		say '</fieldset>';
	}
	say qq(<fieldset id="display_fieldset" style="float:left"><legend>Display/sort options</legend>);
	say qq(<ul><li><span style="white-space:nowrap"><label for="order" class="display">Order by: </label>);
	say $q->popup_menu( -name => 'order', -id => 'order', -values => $order_list, -labels => $order_labels );
	say $q->popup_menu( -name => 'direction', -values => [qw(ascending descending)], -default => 'ascending' );
	say "</span></li><li>";
	say $self->get_number_records_control;
	say "</li></ul></fieldset>";
	$self->print_action_fieldset( { scheme_id => $scheme_id } );
	say $q->hidden($_) foreach qw (page db scheme_id);
	say $q->end_form;
	say "</div></div>";
	return;
}

sub _run_profile_query {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $scheme_id = BIGSdb::Utils::is_int( $q->param('scheme_id') ) ? $q->param('scheme_id') : 0;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	my $field       = $q->param('attribute');
	my ( $datatype, $fieldtype );
	if ( $field =~ /^l_(.*)$/ || $field =~ /^la_(.*)\|\|/ ) {
		$field     = $1;
		$datatype  = $scheme_info->{'allow_missing_loci'} ? 'text' : $self->{'datastore'}->get_locus_info($field)->{'allele_id_format'};
		$fieldtype = 'locus';
	} elsif ( $field =~ /^s_(\d+)\_(.*)$/ ) {
		$scheme_id = $1;
		$field     = $2;
		$datatype  = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field )->{'type'};
		$fieldtype = 'scheme_field';
	}
	my $qry;
	my $query_file = $q->param('query_file') ? "$self->{'config'}->{'secure_tmp_dir'}/" . $q->param('query_file') : undef;
	my $list_file  = $q->param('list_file')  ? "$self->{'config'}->{'secure_tmp_dir'}/" . $q->param('list_file')  : undef;
	if ( !( defined $query_file && -e $query_file && defined $list_file && -e $list_file && defined $q->param('datatype') ) ) {
		$q->delete($_) foreach qw(query_file list_file datatype);    #Clear if temp files have been deleted.
		my @list = split /\n/, $q->param('list');
		@list = uniq @list;
		$self->{'db'}->do("CREATE TEMP TABLE temp_list (value $datatype)");
		$list_file = BIGSdb::Utils::get_random() . '.list';
		my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$list_file";
		open( my $list_fh, '>', $full_path ) || $logger->error("Can't open $list_file for writing");
		my $valid_values = 0;

		foreach my $value (@list) {
			next if $self->_format_value( $field, $datatype, \$value ) == INVALID_VALUE;
			next if !defined $value;
			say $list_fh $value;
			$self->{'db'}->do( 'INSERT INTO temp_list VALUES (?)', undef, ($value) );
			$valid_values++;
		}
		close $list_fh;
		if ( !$valid_values ) {
			say "<div class=\"box\" id=\"statusbad\"><p>No valid values entered.</p></div>";
			return;
		}
		my $scheme_view = $self->{'datastore'}->materialized_view_exists($scheme_id) ? "mv_scheme_$scheme_id" : "scheme_$scheme_id";
		$qry =
"SELECT * FROM $scheme_view WHERE $scheme_view.$primary_key IN (SELECT $scheme_view.$primary_key FROM $scheme_view INNER JOIN temp_list ON ";
		( my $cleaned = $field ) =~ s/'/_PRIME_/g;
		$qry .=
		  $datatype eq 'text' || ( $fieldtype eq 'locus' && $scheme_info->{'allow_missing_loci'} )
		  ? "UPPER($scheme_view.$cleaned) = UPPER(temp_list.value))"
		  : "CAST($scheme_view.$cleaned AS INT) = temp_list.value)";
		$qry .= " ORDER BY ";
		if ( $q->param('order') =~ /^la_(.*)\|\|/ || $q->param('order') =~ /^l_(.*)/ ) {
			my $locus = $1;
			( my $cleaned = $locus ) =~ s/'/_PRIME_/;
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
				$qry .= "to_number(textcat('0', $cleaned), text(99999999))";
			} else {
				$qry .= "$cleaned";
			}
		} elsif ( $q->param('order') =~ /s_\d+_(.*)/ ) {
			my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $1 );
			$qry .= $field_info->{'type'} eq 'integer' ? "CAST($1 AS int)" : $1;
		}
		my $dir = $q->param('direction') eq 'descending' ? 'desc' : 'asc';
		my $pk_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
		my $profile_id_field = $pk_field_info->{'type'} eq 'integer' ? "lpad($primary_key,20,'0')" : $primary_key;
		$qry .= " $dir,$profile_id_field;";
		$q->param( datatype  => $datatype );
		$q->param( list_file => $list_file );
	} else {
		$qry = $self->get_query_from_temp_file( $q->param('query_file') );
		$self->{'datastore'}->create_temp_list_table( $q->param('datatype'), $q->param('list_file') );
	}
	my @hidden_attributes = qw(list attribute scheme_id list_file datatype);
	my $args = { table => 'profiles', query => $qry, hidden_attributes => \@hidden_attributes };
	$args->{'passed_qry_file'} = $q->param('query_file') if defined $q->param('query_file');
	$self->paged_display($args);
	return;
}

sub _run_isolate_query {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $field  = $q->param('attribute');
	my @groupedfields = $self->get_grouped_fields( $field, { strip_prefix => 1 } );
	my $label_field = $self->{'system'}->{'labelfield'};
	my ( $datatype, $fieldtype, $scheme_id );
	my @list = split /\n/, $q->param('list');
	@list = uniq @list;
	my $tempqry;
	my $extended_isolate_field;
	my $locus_pattern = LOCUS_PATTERN;
	my $view          = $self->{'system'}->{'view'};
	my $qry;
	my $query_file = $q->param('query_file') ? "$self->{'config'}->{'secure_tmp_dir'}/" . $q->param('query_file') : undef;
	my $list_file  = $q->param('list_file')  ? "$self->{'config'}->{'secure_tmp_dir'}/" . $q->param('list_file')  : undef;

	if ( !( defined $query_file && -e $query_file && defined $list_file && -e $list_file && defined $q->param('datatype') ) ) {
		$q->delete($_) foreach qw(query_file list_file datatype);    #Clear if temp files have been deleted.
		if ( $field =~ /^f_(.*)$/ ) {
			$field = $1;
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			$datatype = $thisfield->{'type'};
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			$fieldtype = defined $metaset ? 'metafield' : 'isolate';
		} elsif ( $field =~ /$locus_pattern/ ) {
			$field    = $1;
			$datatype = $self->{'datastore'}->get_locus_info($field)->{'allele_id_format'};
			$field =~ s/\'/\\'/g;
			$fieldtype = 'locus';
		} elsif ( $field =~ /^s_(\d+)\_(.*)$/ ) {
			$scheme_id = $1;
			$field     = $2;
			$datatype  = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field )->{'type'};
			$fieldtype = 'scheme_field';
		} elsif ( $field =~ /^e_(.*)\|\|(.*)/ ) {
			$extended_isolate_field = $1;
			$field                  = $2;
			$datatype               = 'text';
			$fieldtype              = 'extended_isolate';
		}
		$datatype //= 'text';

		#Create a temporary table of values.  This will be used for querying some fields, e.g. id, isolate name,
		#loci and scheme fields.  These are the ones where a user is likely to paste in a long list. Other
		#(more complicated field types) will use a built-up query.
		$self->{'db'}->do("CREATE TEMP TABLE temp_list (value $datatype)");
		$list_file = BIGSdb::Utils::get_random() . '.list';
		my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$list_file";
		open( my $list_fh, '>', $full_path ) || $logger->error("Can't open $list_file for writing");
		my $valid_values = 0;
		my $do_not_use_table;
		foreach my $value (@list) {
			next if $self->_format_value( $field, $datatype, \$value ) == INVALID_VALUE;
			next if !defined $value;
			say $list_fh $value;
			$self->{'db'}->do( 'INSERT INTO temp_list VALUES (?)', undef, ($value) );
			$valid_values++;
			$tempqry .= " OR " if $tempqry;
			if ( $fieldtype eq 'isolate' ) {
				$do_not_use_table = 1;
				if (   $field =~ /(.*) \(id\)$/
					|| $field =~ /(.*) \(surname\)$/
					|| $field =~ /(.*) \(first_name\)$/
					|| $field =~ /(.*) \(affiliation\)$/ )
				{
					$tempqry .= $self->search_users( $field, '=', $value, $self->{'system'}->{'view'} );
				} elsif ( scalar @groupedfields ) {
					$tempqry .= " (";
					my $first = 1;
					for my $x ( 0 .. @groupedfields - 1 ) {
						my $thisfield = $self->{'xmlHandler'}->get_field_attributes( $groupedfields[$x] );
						next if $thisfield->{'type'} eq 'int' && !BIGSdb::Utils::is_int($value);
						$tempqry .= ' OR ' if !$first;
						if ( $thisfield->{'type'} eq 'int' ) {
							$tempqry .= "$view.$groupedfields[$x] = E'$value'";
						} else {
							$tempqry .= "upper($view.$groupedfields[$x]) = upper(E'$value')";
						}
						$first = 0;
					}
					$tempqry .= ')';
				} else {
					$do_not_use_table = 0;
				}
			} elsif ( $fieldtype eq 'metafield' ) {
				my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
				$tempqry .= $datatype eq 'text' ? "upper($metafield) = upper(E'$value')" : "$metafield = E'$value'";
			} elsif ( $fieldtype eq 'extended_isolate' ) {
				my $parent_field_type = $self->{'xmlHandler'}->get_field_attributes($extended_isolate_field)->{'type'};
				$tempqry .=
				  $parent_field_type eq 'int' ? "CAST($view.$extended_isolate_field AS text)" : "$view.$extended_isolate_field";
				$tempqry .= " IN (SELECT field_value FROM isolate_value_extended_attributes WHERE "
				  . "isolate_field='$extended_isolate_field' AND attribute='$field' AND upper(value) = upper(E'$value'))";
				$do_not_use_table = 1;
			}
		}
		close $list_fh;
		if ( !$valid_values ) {
			say "<div class=\"box\" id=\"statusbad\"><p>No valid values entered.</p></div>";
			return;
		}
		if ( $fieldtype eq 'isolate' || $extended_isolate_field ) {
			if ( $field eq $label_field ) {    #use temp table
				$qry =
				    "SELECT * FROM $view WHERE ($view.id IN (SELECT $view.id FROM $view INNER JOIN temp_list ON UPPER($view.$label_field) "
				  . "= UPPER(temp_list.value)) OR $view.id IN (SELECT isolate_aliases.isolate_id FROM isolate_aliases INNER JOIN temp_list "
				  . "ON UPPER(isolate_aliases.alias) = UPPER(temp_list.value)))";
			} elsif ($do_not_use_table) {
				$qry = "SELECT * FROM $view WHERE ($tempqry)";    #use list query
			} else {                                              #use temp table
				$qry = "SELECT * FROM $view WHERE ($view.id IN (SELECT $view.id FROM $view INNER JOIN temp_list ON ";
				$qry .=
				  $datatype =~ /int/
				  ? "$view.$field = temp_list.value))"
				  : "UPPER($view.$field) = UPPER(temp_list.value)))";
			}
		} elsif ( $fieldtype eq 'metafield' ) {    #use list query
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			$qry = "SELECT * FROM $view WHERE $view.id IN (SELECT isolate_id FROM meta_$metaset WHERE $tempqry)";
		} elsif ( $fieldtype eq 'locus' ) {        #use temp table
			$qry = "SELECT * FROM $view WHERE $view.id IN (SELECT DISTINCT($view.id) FROM $view INNER JOIN allele_designations ON $view.id="
			  . "allele_designations.isolate_id INNER JOIN temp_list ON allele_designations.locus = E'$field' AND ";
			$qry .=
			  $datatype eq 'text'
			  ? "UPPER(allele_designations.allele_id) = UPPER(temp_list.value))"
			  : "allele_designations.allele_id = CAST(temp_list.value AS text))";
		} elsif ( $fieldtype eq 'scheme_field' ) {    #use temp table
			my $isolate_scheme_field_view = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
			$qry =
			  $datatype eq 'text'
			  ? "SELECT * FROM $view WHERE $view.id IN (SELECT $isolate_scheme_field_view.id FROM $isolate_scheme_field_view INNER JOIN "
			  . "temp_list ON UPPER($isolate_scheme_field_view.$field) = UPPER(temp_list.value))"
			  : "SELECT * FROM $view WHERE $view.id IN (SELECT $isolate_scheme_field_view.id FROM $isolate_scheme_field_view INNER JOIN "
			  . "temp_list ON $isolate_scheme_field_view.$field = temp_list.value)";
		}
		if ( !$q->param('include_old') ) {
			$qry .= ' AND (new_version IS NULL)';
		}
		$qry .= " ORDER BY ";
		if ( $q->param('order') =~ /$locus_pattern/ ) {
			$qry .= "l_$1";
		} else {
			$qry .= $q->param('order');
		}
		my $dir = $q->param('direction') eq 'descending' ? 'desc' : 'asc';
		$qry .= " $dir,$self->{'system'}->{'view'}.id;";
		$q->param( datatype  => $datatype );
		$q->param( list_file => $list_file );
	} else {
		$qry = $self->get_query_from_temp_file( $q->param('query_file') );
		$self->{'datastore'}->create_temp_list_table( $q->param('datatype'), $q->param('list_file') );
	}
	my @hidden_attributes = qw(list attribute list_file datatype);
	my $args = { table => $self->{'system'}->{'view'}, query => $qry, hidden_attributes => \@hidden_attributes };
	$args->{'passed_qry_file'} = $q->param('query_file') if defined $q->param('query_file');
	$self->paged_display($args);
	return;
}

sub _format_value {
	my ( $self, $field, $data_type, $value_ref ) = @_;
	$$value_ref =~ s/^\s*//;
	$$value_ref =~ s/\s*$//;
	$$value_ref =~ s/[\r\n]//g;
	$$value_ref =~ s/'/\\'/g;
	return INVALID_VALUE
	  if lc($data_type) =~ /^int/
	  && !BIGSdb::Utils::is_int($$value_ref);
	return INVALID_VALUE
	  if $field =~ /(.*) \(id\)$/
	  && !BIGSdb::Utils::is_int($$value_ref);
	return INVALID_VALUE
	  if lc($data_type) eq 'date'
	  && !BIGSdb::Utils::is_date($$value_ref);
	return 0;
}
1;
