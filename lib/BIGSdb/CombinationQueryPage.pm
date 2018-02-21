#Written by Keith Jolley
#Copyright (c) 2010-2018, University of Oxford
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
package BIGSdb::CombinationQueryPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::QueryPage);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Constants qw(LOCUS_PATTERN);

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (tooltips jQuery addProjects);
	$self->{'noCache'} = 1 if ( $self->{'system'}->{'sets'} // '' ) eq 'yes';
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Search database by combinations of scheme loci - $desc";
}

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/data_query.html#querying-by-allelic-profile";
}

sub print_content {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $q      = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id') // 0;
	my $desc = $self->get_db_description;
	$self->populate_submission_params;
	if ( ( $self->{'system'}->{'dbtype'} // q() ) eq 'isolates' ) {
		if ( $q->param('add_to_project') ) {
			$self->add_to_project;
		}
		if ( $q->param('publish') ) {
			$self->publish;
		}
	}
	say "<h1>Search $desc database by combinations of loci</h1>";
	if ( !defined $q->param('currentpage')
		|| $q->param('First') )
	{
		my $with_pk  = $self->{'system'}->{'dbtype'} eq 'sequences' ? 1 : 0;
		my $all_loci = $self->{'system'}->{'dbtype'} eq 'isolates'  ? 1 : 0;
		return
		  if $scheme_id
		  && $self->is_scheme_invalid( $scheme_id, { with_pk => $with_pk, all_loci => $all_loci } );
		$self->print_scheme_section( { with_pk => $with_pk, all_loci => $all_loci } );
		$scheme_id = $q->param('scheme_id');                    #Will be set by scheme section method
		$scheme_id = 0 if !BIGSdb::Utils::is_int($scheme_id);
		$self->_print_query_interface($scheme_id);
	}
	if (   defined $q->param('query_file')
		or defined $q->param('submit') )
	{
		$self->_run_query($scheme_id);
	}
	return;
}

sub _autofill {
	my ( $self, $scheme_id ) = @_;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	my $q           = $self->{'cgi'};
	my @errors;
	my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	if ( $scheme_field_info->{'type'} eq 'integer' && !BIGSdb::Utils::is_int( $q->param($primary_key) ) ) {
		push @errors, "$primary_key is an integer field.";
	}
	my $loci     = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $pk_value = $q->param($primary_key);
	if ( !@errors ) {
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			my $indices = $self->{'datastore'}->get_scheme_locus_indices($scheme_id);
			try {
				my $loci_values =
				  $self->{'datastore'}->get_scheme($scheme_id)->get_profile_by_primary_keys( [$pk_value] );
				foreach my $locus (@$loci) {
					$q->param( "l_$locus" => $loci_values->[ $indices->{$locus} ] );
				}
			}
			catch BIGSdb::DatabaseConfigurationException with {
				push @errors, 'Error retrieving information from remote database - check configuration.';
			};
		} else {
			my $scheme_warehouse = "mv_scheme_$scheme_id";
			my $qry              = "SELECT profile FROM $scheme_warehouse WHERE $primary_key=?";
			my $profile          = $self->{'datastore'}->run_query( $qry, $pk_value );
			my $locus_indices    = $self->{'datastore'}->get_scheme_locus_indices($scheme_id);
			foreach my $locus (@$loci) {
				$q->param( "l_$locus", $profile->[ $locus_indices->{$locus} ] );
			}
		}
	}
	return \@errors;
}

sub _get_col_width {
	my ( $self, $has_pk, $all_integers ) = @_;
	if ($has_pk) {
		return $all_integers ? 7 : 4;
	} else {
		return $all_integers ? 14 : 7;
	}
}

sub _print_query_interface {
	my ( $self, $scheme_id ) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="queryform">);
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	my $set_id      = $self->get_set_id;
	my $loci =
	    $scheme_id
	  ? $self->{'datastore'}->get_scheme_loci($scheme_id)
	  : $self->{'datastore'}->get_loci( { query_pref => 1, set_id => $set_id } );
	my $scheme_fields;
	$scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id) if $scheme_id;
	my $errors = [];

	if ( $primary_key && $q->param('Autofill') ) {
		$errors = $self->_autofill( $scheme_id, $loci );
	}
	say q(<div class="scrollable">);
	say $q->start_form;
	$self->_print_profile_table_fieldset( $scheme_id, $loci );
	if (
		$primary_key
		&& ( ( $self->{'system'}->{'dbtype'} eq 'isolates' && $scheme_info->{'dbase_id'} )
			|| $self->{'system'}->{'dbtype'} eq 'sequences' )
	  )
	{
		my $remote = $self->{'system'}->{'dbtype'} eq 'isolates' ? ' by searching remote database' : '';
		say qq(<fieldset id="autofill_fieldset" style="float:left"><legend>Autofill profile$remote</legend><ul>);
		my $first = 1;
		say qq(<li><label for="$primary_key" class="display">$primary_key: </label>);
		say $q->textfield( -name => $primary_key, -id => $primary_key, -class => 'allele_entry' );
		say $q->submit( -name => 'Autofill', -class => 'submit' ) if $first;
		$first = 0;
		say q(</li>);
		say q(</ul></fieldset>);
	}
	say q(<div style="clear:both">);
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say q(<fieldset style="float:left"><legend>Filters</legend><ul>);
		my $buffer = $self->get_project_filter( { class => 'display' } );
		say qq(<li>$buffer</li>) if $buffer;
		say q(<li>);
		say $self->get_old_version_filter;
		say q(</li></ul></fieldset>);
	}
	say q(<fieldset id="options_fieldset" style="float:left"><legend>Options</legend>);
	my ( @values, %labels );
	push @values, 0;
	foreach my $i ( reverse 1 .. @$loci ) {
		push @values, $i;
		$labels{$i} = qq($i or more matches);
	}
	$labels{0} = q(Exact or nearest match);
	$labels{ scalar @$loci } = q(Exact match only);
	say $self->get_filter( 'matches', \@values,
		{ labels => \%labels, text => 'Search', noblank => 1, class => 'display' } );
	say q(</fieldset>);
	say q(<fieldset id="display_fieldset" style="float:left"><legend>Display/sort options</legend>);
	say q(<ul><li><span style="white-space:nowrap"><label for="order" class="display">Order by: </label>);
	my ( $order_by, $dropdown_labels );

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		( $order_by, $dropdown_labels ) =
		  $self->get_field_selection_list( { isolate_fields => 1, loci => 1, scheme_fields => 1 } );
	} else {
		push @$order_by, "f_$primary_key";
		foreach my $field (@$scheme_fields) {
			push @$order_by, "f_$field" if $field ne $primary_key;
			$dropdown_labels->{"f_$field"} = $field;
			$dropdown_labels->{"f_$field"} =~ tr/_/ /;
		}
		foreach my $locus (@$loci) {
			push @$order_by, "f_$locus";
			$dropdown_labels->{"f_$locus"} = $self->clean_locus( $locus, { text_output => 1 } );
		}
	}
	say $q->popup_menu( -name => 'order', -id => 'order', -values => $order_by, -labels => $dropdown_labels );
	say $q->popup_menu( -name => 'direction', -values => [ 'ascending', 'descending' ], -default => 'ascending' );
	say q(</span></li><li>);
	say $self->get_number_records_control;
	say q(</li></ul></fieldset></div>);
	$self->print_action_fieldset( { scheme_id => $scheme_id } );
	say $q->hidden($_) foreach qw (db page scheme_id);
	say $q->hidden( sent => 1 );
	say $q->end_form;
	say q(</div></div>);

	if (@$errors) {
		local $" = q(<br />);
		say qq(<div class="box" id="statusbad"><p>Problem with search criteria:</p><p>@$errors</p></div>);
	}
	return;
}

sub _print_profile_table_fieldset {
	my ( $self, $scheme_id, $loci ) = @_;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	my $q           = $self->{'cgi'};
	say q(<fieldset id="profile_fieldset" style="float:left"><legend>Please enter your )
	  . q(allelic profile below. Blank loci will be ignored.</legend>);
	say q(<table class="queryform">);
	my $i = 0;
	my ( $header_row, $form_row );
	my $all_integers = 1;

	foreach my $locus (@$loci) {
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		if ( $locus_info->{'allele_id_format'} ne 'integer' ) {
			$all_integers = 0;
			last;
		}
	}
	my $max_per_row = $self->_get_col_width( $primary_key, $all_integers );
	my @display_loci;
	my (%label);
	foreach my $locus (@$loci) {
		push @display_loci, "l_$locus";
		my $cleaned_locus = $self->clean_locus($locus);
		$label{"l_$locus"} = $cleaned_locus;
		if ( !$scheme_id && $self->{'prefs'}->{'locus_alias'} && $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			my $locus_aliases = $self->{'datastore'}->get_locus_aliases($locus);
			foreach my $alias (@$locus_aliases) {
				my $value = "la_$locus||$alias";
				push @display_loci, $value;
				$alias =~ tr/_/ /;
				$label{$value} = qq($alias<br /><span class="comment">[$cleaned_locus]</span>);
			}
		}
	}
	foreach my $locus (@display_loci) {
		if ( $i == $max_per_row ) {
			say qq(<tr>$header_row</tr>);
			say qq(<tr>$form_row</tr>);
			undef $header_row;
			undef $form_row;
			$i = 0;
		}
		my $class = $all_integers ? 'int_entry' : 'allele_entry';
		$header_row .= qq(<th class="$class">$label{$locus}</th>);
		$form_row   .= q(<td>);
		$form_row   .= $q->textfield( -name => $locus, -class => $class, -style => 'text-align:center' );
		$form_row   .= q(</td>);
		$i++;
	}
	say qq(<tr>$header_row</tr>);
	say qq(<tr>$form_row</tr>);
	say q(</table></fieldset>);
	return;
}

sub _generate_query {
	my ( $self, $scheme_id ) = @_;
	my $scheme_info      = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $q                = $self->{'cgi'};
	my @params           = $q->param;
	my @errors;
	my $msg;
	my $qry;
	my @loci;
	my %values;
	my $pattern = LOCUS_PATTERN;

	foreach my $param (@params) {
		if ( $param =~ /$pattern/x ) {
			if ( $q->param($param) ne q() ) {
				push @loci, $1;
				if ( $values{$1} && $q->param($param) && $values{$1} ne $q->param($param) ) {
					my $aliases =
					  $self->{'datastore'}->run_query( 'SELECT alias FROM locus_aliases WHERE locus=? ORDER BY alias',
						$1, { fetch => 'col_arrayref' } );
					local $" = ', ';
					push @errors,
					    "Locus $1 has been defined with more than one value (due to an "
					  . 'alias for this locus also being used). The following alias(es) exist '
					  . "for this locus: @$aliases";
					next;
				}
				$values{$1} = $q->param($param);
			}
		}
	}
	my @lqry;
	foreach my $locus (@loci) {
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		$self->process_value( \$values{$locus} );
		( my $cleaned_locus = $locus ) =~ s/'/\\'/gx;
		if (
			(
				   $values{$locus} ne ''
				&& $locus_info->{'allele_id_format'} eq 'integer'
				&& !BIGSdb::Utils::is_int( $values{$locus} )
			)
			&& !( $scheme_info->{'allow_missing_loci'} && $values{$locus} eq 'N' )
		  )
		{
			my $arbitrary_msg = $scheme_info->{'allow_missing_loci'} ? ' Arbitrary values (N) may also be used.' : '';
			push @errors, "$locus is an integer field.$arbitrary_msg";
			next;
		}
		next if $values{$locus} eq '';
		my $table = $self->{'system'}->{'dbtype'} eq 'isolates' ? 'ad' : 'pm';
		my $locus_qry;
		if ( $values{$locus} eq 'N' ) {
			$locus_qry = "($table.locus=E'$cleaned_locus'";    #don't match allele_id because it can be anything
		} else {
			my $arbitrary_clause = $scheme_info->{'allow_missing_loci'} ? q(,'N') : q();
			$locus_qry =
			  $locus_info->{'allele_id_format'} eq 'text'
			  ? "($table.locus=E'$cleaned_locus' AND (upper($table.allele_id) IN (upper(E'$values{$locus}')$arbitrary_clause))"
			  : "($table.locus=E'$cleaned_locus' AND ($table.allele_id IN (E'$values{$locus}'$arbitrary_clause))";
		}
		$locus_qry .= ')';
		push @lqry, $locus_qry;
	}
	my $view = $self->{'system'}->{'view'};
	if (@lqry) {
		local $" = ' OR ';
		my $required_matches = $q->param('matches_list') // 0;
		$required_matches = @lqry if $required_matches == @loci;
		my $lqry;
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			$lqry = "(SELECT DISTINCT($view.id) FROM $view LEFT JOIN allele_designations ad ON "
			  . "$view.id=ad.isolate_id WHERE @lqry";
		} else {
			$lqry = "(SELECT pm.profile_id FROM profile_members pm WHERE pm.scheme_id=$scheme_id AND (@lqry)";
		}
		if ( $required_matches == 0 ) {    #Find out the greatest number of matches
			my $match = $self->_find_best_match_count( $scheme_id, \@lqry );
			if ($match) {
				$required_matches = $match;
				$msg = $self->_get_match_msg( $match, scalar @lqry );
			}
		}
		$lqry .=
		  $self->{'system'}->{'dbtype'} eq 'isolates'
		  ? " GROUP BY $view.id HAVING count($view.id)>=$required_matches)"
		  : " GROUP BY pm.profile_id HAVING count(pm.profile_id)>=$required_matches)";
		$qry =
		  $self->{'system'}->{'dbtype'} eq 'isolates'
		  ? "SELECT * FROM $view WHERE $view.id IN $lqry"
		  : "SELECT * FROM $scheme_warehouse WHERE $scheme_warehouse.$scheme_info->{'primary_key'} IN $lqry";
	}
	$self->_modify_qry_by_filters( \$qry );
	$self->_add_query_ordering( \$qry, $scheme_id );
	$logger->error($qry);
	return ( $qry, $msg, \@errors );
}

sub _add_query_ordering {
	my ( $self, $qry_ref, $scheme_id ) = @_;
	my $q = $self->{'cgi'};
	$$qry_ref .= ' ORDER BY ';
	my $dir = ( $q->param('direction') // q() ) eq 'descending' ? 'desc' : 'asc';
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $order_field = $q->param('order');
		my $pattern     = LOCUS_PATTERN;
		if ( $order_field =~ /$pattern/x ) {
			if ( $self->{'datastore'}->is_locus($1) ) {
				$$qry_ref .= "l_$1";
			} else {
				$$qry_ref .= 'f_id';    #Invalid order field entered
			}
		} elsif ( $order_field =~ /s_(\d+)_(\S+)/x ) {
			if ( $self->{'datastore'}->is_scheme_field( $1, $2 ) ) {
				$$qry_ref .= $order_field;
			} else {
				$$qry_ref .= 'f_id';    #Invalid order field entered
			}
		} else {
			if ( $order_field =~ /f_(.+)/x && $self->{'xmlHandler'}->is_field($1) ) {
				$$qry_ref .= $order_field;
			} else {
				$$qry_ref .= 'f_id';    #Invalid order field entered
			}
		}
		my $view = $self->{'system'}->{'view'};
		$$qry_ref .= " $dir,$view.id;";
	} else {
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		my $pk_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $scheme_info->{'primary_key'} );
		my $profile_id_field =
		  $pk_info->{'type'} eq 'integer'
		  ? "lpad($scheme_info->{'primary_key'},20,'0')"
		  : $scheme_info->{'primary_key'};
		my $order_field = $q->param('order') // $profile_id_field;
		$order_field =~ s/^f_//x;
		if ( $order_field eq $scheme_info->{'primary_key'} ) {
			$$qry_ref .= "$profile_id_field $dir;";
		} elsif ( $self->{'datastore'}->is_locus($order_field) ) {
			my $locus_info = $self->{'datastore'}->get_locus_info($order_field);
			$order_field = $self->{'datastore'}->get_scheme_warehouse_locus_name( $scheme_id, $order_field );
			$order_field =~ s/'/_PRIME_/gx;
			$$qry_ref .=
			  $locus_info->{'allele_id_format'} eq 'integer'
			  ? "to_number(textcat('0', $order_field), text(99999999))"
			  : $order_field;
			$$qry_ref .= " $dir,$profile_id_field;";
		} elsif ( $self->{'datastore'}->is_scheme_field( $scheme_id, $order_field ) ) {
			my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $order_field );
			$$qry_ref .= $field_info->{'type'} eq 'integer' ? "CAST($order_field AS int)" : $order_field;
			$$qry_ref .= " $dir,$profile_id_field;";
		} else {
			$$qry_ref .= "$profile_id_field $dir;";    #Invalid order field entered
		}
	}
	return;
}

sub _find_best_match_count {
	my ( $self, $scheme_id, $lqry ) = @_;
	my $q = $self->{'cgi'};
	local $" = ' OR ';
	my $match_qry;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $view = $self->{'system'}->{'view'};
		$match_qry =
		  "SELECT COUNT($view.id) FROM $view LEFT JOIN allele_designations ad ON $view.id=isolate_id WHERE (@$lqry) ";
		my $project_id = $q->param('project_list');
		if ( BIGSdb::Utils::is_int($project_id) ) {
			$match_qry .= " AND $view.id IN (SELECT isolate_id FROM project_members WHERE project_id=$project_id) ";
		}
		$match_qry .= "GROUP BY $view.id ORDER BY count($view.id) desc LIMIT 1";
	} else {
		$match_qry =
		    'SELECT COUNT(p.profile_id) FROM profiles p LEFT JOIN profile_members pm ON p.profile_id=pm.profile_id '
		  . "AND p.scheme_id=pm.scheme_id AND pm.scheme_id=$scheme_id WHERE @$lqry GROUP BY p.profile_id ORDER BY "
		  . 'COUNT(p.profile_id) desc LIMIT 1';
	}
	my $match = $self->{'datastore'}->run_query($match_qry);
	return $match;
}

sub _get_match_msg {
	my ( $self, $match, $total_loci ) = @_;
	my $term   = $match > 1  ? 'loci' : 'locus';
	my $plural = $match == 1 ? ''     : 'es';
	return $match == $total_loci
	  ? "Exact match$plural found ($match $term)."
	  : "Nearest match: $match $term.";
}

sub _run_query {
	my ( $self, $scheme_id ) = @_;
	my $q = $self->{'cgi'};
	my $qry;
	my $msg;
	my $errors = [];
	if ( !defined $q->param('query_file') ) {
		( $qry, $msg, $errors ) = $self->_generate_query($scheme_id);
	} else {
		$qry = $self->get_query_from_temp_file( $q->param('query_file') );
	}
	if (@$errors) {
		local $" = '<br />';
		say q(<div class="box" id="statusbad"><p>Problem with search criteria:</p>);
		say "<p>@$errors</p></div>";
	} elsif ( $qry !~ /^\ ORDER\ BY/x ) {
		my @hidden_attributes;
		push @hidden_attributes, $_ foreach qw(scheme matches project_list);
		my $set_id = $self->get_set_id;
		my $loci =
		    $scheme_id
		  ? $self->{'datastore'}->get_scheme_loci($scheme_id)
		  : $self->{'datastore'}->get_loci( { query_pref => 1, set_id => $set_id } );
		foreach my $locus (@$loci) {
			push @hidden_attributes, "l_$locus" if $q->param("l_$locus");
		}
		push @hidden_attributes, qw(scheme_id matches_list);
		my $table = $self->{'system'}->{'dbtype'} eq 'isolates' ? $self->{'system'}->{'view'} : 'profiles';
		my $args = { table => $table, query => $qry, message => $msg, hidden_attributes => \@hidden_attributes };
		$args->{'passed_qry_file'} = $q->param('query_file') if defined $q->param('query_file');
		$self->paged_display($args);
	} else {
		say q(<div class="box" id="statusbad">Invalid search performed.</div>);
	}
	return;
}

sub _modify_qry_by_filters {
	my ( $self, $qry_ref ) = @_;
	return if $self->{'system'}->{'dbtype'} eq 'sequences';
	my $q    = $self->{'cgi'};
	my $view = $self->{'system'}->{'view'};
	if ( $$qry_ref && ( $q->param('project_list') // '' ) ne '' ) {
		my $project_id = $q->param('project_list');
		if ($project_id) {
			$$qry_ref .= " AND $view.id IN (SELECT isolate_id FROM project_members WHERE project_id=$project_id)";
		}
	}
	if ( $$qry_ref && !$q->param('include_old') ) {
		$$qry_ref .= " AND ($view.new_version IS NULL)";
	}
	return;
}
1;
