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
		my $set_id = $self->get_set_id;
		my $loci   = $self->{'datastore'}->get_scheme_loci($scheme_id);
		foreach my $locus (@$loci) {
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			push @$field_list, "l_$locus";
			$labels->{"l_$locus"} = $locus;
			$labels->{"l_$locus"} .= " ($locus_info->{'common_name'})" if $locus_info->{'common_name'};
			if ($set_id) {
				my $set_cleaned = $self->{'datastore'}->get_set_locus_label( $locus, $set_id );
				$labels->{"l_$locus"} = $set_cleaned if $set_cleaned;
			}
		}
		$order_list   = $field_list;
		$order_labels = $labels;
	}
	say "<div class=\"box\" id=\"queryform\">\n<div class=\"scrollable\">";
	say $q->start_form;
	say "<fieldset id=\"attribute_fieldset\" style=\"float:left\"><legend>Please select attribute</legend>";
	my @select_items = ( @grouped_fields, @$field_list );
	say $q->popup_menu( -name => 'attribute', -values => \@select_items, -labels => $labels );
	say "</fieldset><div style=\"clear:both\"></div>";
	say "<fieldset id=\"list_fieldset\" style=\"float:left\"><legend>Enter your list of attribute values below (one per line)</legend>";
	say $q->textarea( -name => 'list', -rows => 8, -cols => 40 );
	say "</fieldset>";
	say "<fieldset id=\"display_fieldset\" style=\"float:left\"><legend>Display/sort options</legend>";
	say "<ul>\n<li><span style=\"white-space:nowrap\">\n<label for=\"order\" class=\"display\">Order by: </label>";
	say $q->popup_menu( -name => 'order', -id => 'order', -values => $order_list, -labels => $order_labels );
	say $q->popup_menu( -name => 'direction', -values => [ 'ascending', 'descending' ], -default => 'ascending' );
	say "</span></li>\n<li>";
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
		$datatype  = $self->{'datastore'}->get_locus_info($field)->{'allele_id_format'};
		$fieldtype = 'locus';
	} elsif ( $field =~ /^s_(\d+)\_(.*)$/ ) {
		$scheme_id = $1;
		$field     = $2;
		$datatype  = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field )->{'type'};
		$fieldtype = 'scheme_field';
	}
	my @list = split /\n/, $q->param('list');
	my $tempqry;
	@list = uniq @list;
	foreach my $value (@list) {
		next if $self->_format_value( $field, $datatype, \$value ) == INVALID_VALUE;
		if ($value) {
			$tempqry .= " OR " if $tempqry;
			if ( $fieldtype eq 'scheme_field' || $fieldtype eq 'locus' ) {
				( my $cleaned = $field ) =~ s/'/_PRIME_/g;
				$tempqry .=
				  $datatype eq 'text'
				  ? "upper($cleaned)=upper(E'$value')"
				  : "$cleaned=E'$value'";
			}
		}
	}
	if ( !$tempqry ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No valid values entered.</p></div>";
		return;
	}
	my $scheme_view = $self->{'datastore'}->materialized_view_exists($scheme_id) ? "mv_scheme_$scheme_id" : "scheme_$scheme_id";
	my $qry = "SELECT * FROM $scheme_view WHERE $tempqry";
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
	my @hidden_attributes = qw(list attribute scheme_id);
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
	my ( $datatype, $fieldtype, $scheme_id, $joined_query );
	my @list = split /\n/, $q->param('list');
	@list = uniq @list;
	my $tempqry;
	my $extended_isolate_field;
	my $locus_pattern = LOCUS_PATTERN;
	my $view          = $self->{'system'}->{'view'};

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
		my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
		my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
		my $temp_table  = $self->{'datastore'}->create_temp_isolate_scheme_table($scheme_id);
		my ( %cleaned, %named, %scheme_named );

		foreach my $locus (@$scheme_loci) {
			( $cleaned{$locus}      = $locus ) =~ s/'/\\'/g;
			( $named{$locus}        = $locus ) =~ s/'/_PRIME_/g;
			( $scheme_named{$locus} = $locus ) =~ s/'/_PRIME_/g;
		}
		my @temp;
		foreach my $locus (@$scheme_loci) {
			push @temp, $self->get_scheme_locus_query_clause( $scheme_id, $temp_table, $locus, $scheme_named{$locus}, $named{$locus} );
		}
		local $" = ' AND ';
		$joined_query = "SELECT $temp_table.id FROM $temp_table INNER JOIN temp_scheme_$scheme_id AS scheme_$scheme_id ON @temp";
	} elsif ( $field =~ /^e_(.*)\|\|(.*)/ ) {
		$extended_isolate_field = $1;
		$field                  = $2;
		$datatype               = 'text';
		$fieldtype              = 'extended_isolate';
	}
	foreach my $value (@list) {
		next if $self->_format_value( $field, $datatype, \$value ) == INVALID_VALUE;
		if ($value) {
			$tempqry .= " OR " if $tempqry;
			if ( $fieldtype eq 'isolate' ) {
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
				} elsif ( $field eq $self->{'system'}->{'labelfield'} ) {
					$tempqry .= "(upper($self->{'system'}->{'labelfield'}) = upper('$value') OR $view.id IN "
					  . "(SELECT isolate_id FROM isolate_aliases WHERE upper(alias) = upper(E'$value')))";
				} elsif ( $datatype eq 'text' ) {
					$tempqry .= "upper($view.$field) = upper(E'$value')";
				} else {
					$tempqry .= "$view.$field = E'$value'";
				}
			} elsif ( $fieldtype eq 'metafield' ) {
				my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
				$tempqry .= $datatype eq 'text' ? "upper($metafield) = upper(E'$value')" : "$metafield = E'$value'";
			} elsif ( $fieldtype eq 'locus' ) {
				$tempqry .=
				  $datatype eq 'text'
				  ? "(allele_designations.locus=E'$field' AND upper(allele_designations.allele_id) = upper(E'$value'))"
				  : "(allele_designations.locus=E'$field' AND allele_designations.allele_id = E'$value')";
			} elsif ( $fieldtype eq 'scheme_field' ) {
				$tempqry .=
				  $datatype eq 'text'
				  ? "upper(scheme_$scheme_id\.$field)=upper(E'$value')"
				  : "$field=E'$value'";
			} elsif ( $fieldtype eq 'extended_isolate' ) {
				$tempqry .= "$view.$extended_isolate_field IN (SELECT field_value FROM isolate_value_extended_attributes WHERE "
				  . "isolate_field='$extended_isolate_field' AND attribute='$field' AND upper(value) = upper(E'$value'))";
			}
		}
	}
	if ( !$tempqry ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No valid values entered.</p></div>";
		return;
	}
	my $qry;
	if ( $fieldtype eq 'isolate' || $extended_isolate_field ) {
		$qry = "SELECT * FROM $view WHERE ($tempqry)";
	} elsif ( $fieldtype eq 'metafield' ) {
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
		$qry = "SELECT * FROM $view WHERE $view.id IN (SELECT isolate_id FROM meta_$metaset WHERE $tempqry)";
	} elsif ( $fieldtype eq 'locus' ) {
		$qry = "SELECT * FROM $view WHERE $view.id IN (SELECT distinct($view.id) FROM $view LEFT JOIN allele_designations "
		  . "ON $view.id=allele_designations.isolate_id WHERE $tempqry)";
	} elsif ( $fieldtype eq 'scheme_field' ) {
		$qry = "SELECT * FROM $view WHERE $view.id IN ($joined_query AND ($tempqry))";
	}
	$qry .= " ORDER BY ";
	if ( $q->param('order') =~ /$locus_pattern/ ) {
		$qry .= "l_$1";
	} else {
		$qry .= $q->param('order');
	}
	my $dir = $q->param('direction') eq 'descending' ? 'desc' : 'asc';
	$qry .= " $dir,$self->{'system'}->{'view'}.id;";
	my @hidden_attributes = qw(list attribute);
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
