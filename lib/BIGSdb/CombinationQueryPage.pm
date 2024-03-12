#Written by Keith Jolley
#Copyright (c) 2010-2024, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
use Try::Tiny;
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Constants qw(LOCUS_PATTERN);

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (tooltips jQuery addProjects allowExpand);
	$self->{'noCache'} = 1 if ( $self->{'system'}->{'sets'} // '' ) eq 'yes';
	$self->set_level1_breadcrumbs;
	return;
}

sub get_title {
	my ($self) = @_;
	return 'Search by locus combinations';
}

sub get_help_url {
	my ($self) = @_;
	return $self->{'system'}->{'dbtype'} eq 'sequences'
	  ? "$self->{'config'}->{'doclink'}/data_query/0040_search_allelic_profiles.html"
	  : "$self->{'config'}->{'doclink'}/data_query/0070_querying_isolate_data.html#querying-by-allelic-profile";
}

sub print_content {
	my ($self)    = @_;
	my $system    = $self->{'system'};
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id') // 0;
	my $desc      = $self->get_db_description;
	$self->populate_submission_params;
	if ( ( $self->{'system'}->{'dbtype'} // q() ) eq 'isolates' ) {
		if ( $q->param('add_to_project') ) {
			$self->add_to_project;
		}
		if ( $q->param('publish') ) {
			$self->publish;
		}
	}
	my $title = $self->get_title;
	say qq(<h1>$title</h1>);
	if ( ( $self->{'system'}->{'dbtype'} // q() ) eq 'sequences' ) {
		my $schemes = $self->{'datastore'}->get_scheme_list( { with_pk => 1 } );
		if ( !@$schemes ) {
			$self->print_bad_status(
				{ message => 'There are no indexed schemes defined in this database.', navbar => 1 } );
			return;
		}
	}
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
		$self->_print_interface($scheme_id);
	}
	if ( defined $q->param('temp_table_file') ) {
		my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/" . $q->param('temp_table_file');
		if ( !-e $full_path ) {
			$logger->error("Temporary file $full_path does not exist");
			$self->print_bad_status( { message => q(Temporary file does not exist. Please repeat query.) } );
			$scheme_id = $q->param('scheme_id');                    #Will be set by scheme section method
			$scheme_id = 0 if !BIGSdb::Utils::is_int($scheme_id);
			$self->_print_interface($scheme_id);
			return;
		}
		$self->{'datastore'}->create_temp_combinations_table_from_file( scalar $q->param('temp_table_file') );
	}
	if (   defined $q->param('query_file')
		or defined $q->param('submit') )
	{
		$self->_run_query($scheme_id);
	}
	return;
}

sub _loci_have_common_names {
	my ( $self, $scheme_id ) = @_;
	if ($scheme_id) {
		return $self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT id FROM loci l JOIN scheme_members sm ON l.id=sm.locus '
			  . 'WHERE scheme_id=? AND common_name IS NOT NULL)',
			$scheme_id
		);
	}
	return $self->{'datastore'}->run_query('SELECT EXISTS(SELECT id FROM loci WHERE common_name IS NOT NULL)');
}

sub _get_show_common_names_button {
	my ($self) = @_;
	return
		q(<span id="common_names_button" style="margin-left:1em;margin-bottom:1em;display:block">)
	  . q(<a id="show_common_names" class="small_submit" style="cursor:pointer">)
	  . q(<span id="show_common_names_text" style="display:inline"><span class="fa fas fa-eye"></span> )
	  . q(Show</span><span id="hide_common_names_text" style="display:none">)
	  . q(<span class="fa fas fa-eye-slash"></span> Hide</span> )
	  . q(common names</a></span>);
}

sub get_javascript {
	my $buffer = << "END";
\$(function () {
	\$( "#show_common_names" ).click(function() {
		if (\$("span#show_common_names_text").css('display') == 'none'){
			\$("span#show_common_names_text").css('display', 'inline');
			\$("span#hide_common_names_text").css('display', 'none');
		} else {
			\$("span#show_common_names_text").css('display', 'none');
			\$("span#hide_common_names_text").css('display', 'inline');
		}
		\$("span.locus_common_name").toggle();
		set_profile_widths();
	});
});
function set_profile_widths(){
	\$("dl.profile dt").css("width","auto").css("max-width","none");
	var maxWidth = Math.max.apply( null, \$("dl.profile dt").map( function () {
    	return \$(this).outerWidth(true);
	}).get() );
	\$("dl.profile dt").css("width",'calc(' + maxWidth + 'px - 1em)')
		.css("max-width",'calc(' + maxWidth + 'px - 1em)');	
	\$("dl.profile input").css("border","0");
}
END
	return $buffer;
}

sub _autofill {
	my ( $self, $scheme_id ) = @_;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	my $q           = $self->{'cgi'};
	my @errors;
	my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	if ( $scheme_field_info->{'type'} eq 'integer' && !BIGSdb::Utils::is_int( scalar $q->param($primary_key) ) ) {
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
			} catch {
				if ( $_->isa('BIGSdb::Exception::Database::Configuration') ) {
					push @errors, 'Error retrieving information from remote database - check configuration.';
				} else {
					$logger->logdie($_);
				}
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

sub _print_interface {
	my ( $self, $scheme_id ) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="queryform">);
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	my $set_id      = $self->get_set_id;
	my $loci =
		$scheme_id
	  ? $self->{'datastore'}->get_scheme_loci($scheme_id)
	  : $self->{'datastore'}->get_loci( { query_pref => 1, set_id => $set_id, do_not_order => 1 } );
	if ( !$scheme_id ) {
		@$loci = sort @$loci;    #Otherwise it's sorted by scheme order.
	}
	my $scheme_fields;
	$scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id) if $scheme_id;
	my $errors = [];
	if ( $primary_key && $q->param('Autofill') ) {
		$errors = $self->_autofill( $scheme_id, $loci );
	}
	say q(<div class="scrollable">);
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $scheme_info->{'allow_presence'} ) {
		say q(<p>Note that although this scheme allows profiles to be defined by locus presence )
		  . q((including incomplete sequences), results here will only include isolates where allele )
		  . q(designations have been assigned.</p>);
	}
	say $q->start_form;

	#Hidden button fires if user presses Enter but it mimics clicking the Search button (which is not
	#the first button on the page). Otherwise, the 'Autofill' button would be used.
	say q(<button style="overflow: visible !important; height: 0 !important; width: 0 !important; margin: 0 )
	  . q(!important; border: 0 !important; padding: 0 !important; display: block !important;" )
	  . q(type="submit" name="submit" value="Search"></button>);
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
		say $q->submit( -name => 'Autofill', -class => 'small_submit' ) if $first;
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
	say $q->popup_menu(
		-name   => 'order',
		-id     => 'order',
		-values => $order_by,
		-labels => $dropdown_labels,
		-class  => 'fieldlist'
	);
	say $q->popup_menu( -name => 'direction', -values => [ 'ascending', 'descending' ], -default => 'ascending' );
	say q(</span></li><li>);
	say $self->get_number_records_control;
	say q(</li></ul></fieldset></div>);
	$self->print_action_fieldset( { submit_label => 'Search', scheme_id => $scheme_id } );
	say $q->hidden($_) foreach qw (db page scheme_id);
	say $q->hidden( sent => 1 );
	say $q->end_form;
	say q(</div></div>);

	if (@$errors) {
		local $" = q(<br />);
		$self->print_bad_status( { message => q(Problem with search criteria:), detail => qq(@$errors) } );
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
	if ( $self->_loci_have_common_names($scheme_id) ) {
		say $self->_get_show_common_names_button;
	}
	my $all_integers = 1;
	foreach my $locus (@$loci) {
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		if ( $locus_info->{'allele_id_format'} ne 'integer' ) {
			$all_integers = 0;
			last;
		}
	}
	my @display_loci;
	my (%label);
	foreach my $locus (@$loci) {
		push @display_loci, "l_$locus";
		my $cleaned_locus = $self->clean_locus( $locus, { common_name_class => 'locus_common_name' } );
		$label{"l_$locus"} = $cleaned_locus;
	}
	my $class = $all_integers ? 'int_entry' : 'allele_entry';
	foreach my $locus (@display_loci) {
		say q(<dl class="profile" style="float:left">);
		say qq(<dt>$label{$locus}</dt>);
		say q(<dd style="min-height:initial">);
		say $q->textfield( -name => $locus, -class => $class, -style => 'text-align:center' );
		say q(</dd>);
		say q(</dl>);
	}
	say q(</fieldset>);
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
			&& !( $scheme_info->{'allow_presence'}     && $values{$locus} eq 'P' )
		  )
		{
			my @can_use;
			push @can_use, 'arbitrary values (N)' if $scheme_info->{'allow_missing_loci'};
			push @can_use, 'locus presence (P)'   if $scheme_info->{'allow_presence'};
			my $arbitrary_msg = q();
			if (@can_use) {
				local $" = ' and ';
				$arbitrary_msg = ucfirst(qq(@can_use may also be used.));
			}
			push @errors, "$locus is an integer field. $arbitrary_msg";
			next;
		}
		next if $values{$locus} eq '';
		my $table = $self->{'system'}->{'dbtype'} eq 'isolates' ? 'ad' : 'pm';
		my $locus_qry;
		if ( $values{$locus} eq 'N' ) {
			$locus_qry = "($table.locus=E'$cleaned_locus'";    #don't match allele_id because it can be anything
		} elsif ( $values{$locus} eq 'P' ) {
			$locus_qry = "($table.locus=E'$cleaned_locus' AND ($table.allele_id != '0')";
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
	my $create_temp_table;
	if (@lqry) {
		local $" = ' OR ';
		my $required_matches = $q->param('matches_list') // 0;
		$required_matches = @lqry if $required_matches == @loci;
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {

			#Account for paralogous hits - only count each locus once. It is, however, much quicker
			#not using DISTINCT if we don't need it.
			my $count_item = $scheme_info->{'allow_missing_loci'} ? 'DISTINCT(ad.locus)' : '*';
			$create_temp_table =
				"CREATE TEMP TABLE count_table AS SELECT $view.id,COUNT($count_item) AS count FROM $view "
			  . "JOIN allele_designations ad ON $view.id=ad.isolate_id WHERE @lqry GROUP BY $view.id";
		} else {
			$create_temp_table =
				'CREATE TEMP TABLE count_table AS SELECT pm.profile_id AS id,COUNT(*) AS count FROM profile_members pm '
			  . "WHERE pm.scheme_id=$scheme_id AND (@lqry) GROUP BY pm.profile_id";
		}
		$create_temp_table .= ';CREATE INDEX ON count_table(count)';
		eval { $self->{'db'}->do($create_temp_table); };
		if ( $required_matches == 0 ) {    #Find out the greatest number of matches
			my $match = $self->{'datastore'}->run_query('SELECT MAX(count) FROM count_table');
			if ($match) {
				$required_matches = $match;
				$msg              = $self->_get_match_msg( $match, scalar @lqry );
			}
		}
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			$qry = "SELECT * FROM $view WHERE $view.id IN (SELECT id FROM count_table WHERE count>=$required_matches)";
		} else {
			$qry =
				"SELECT * FROM $scheme_warehouse WHERE $scheme_warehouse.$scheme_info->{'primary_key'} IN "
			  . "(SELECT id FROM count_table WHERE count>=$required_matches)";
		}
	}
	if ($create_temp_table) {
		my $temp_table_sql_file = $self->_make_temp_table_file;
		$q->param( temp_table_file => $temp_table_sql_file );
	}
	$self->_modify_qry_by_filters( \$qry );
	$self->_add_query_ordering( \$qry, $scheme_id );
	return ( $qry, $msg, \@errors );
}

sub _make_temp_table_file {
	my ($self) = @_;
	my ( $filename, $full_file_path );
	my $data = $self->{'datastore'}->run_query( 'SELECT * FROM count_table', undef, { fetch => 'all_arrayref' } );
	do {
		$filename       = BIGSdb::Utils::get_random() . '.txt';
		$full_file_path = "$self->{'config'}->{'secure_tmp_dir'}/$filename";
	} while ( -e $full_file_path );
	my $buffer;
	local $" = qq(\t);
	$buffer .= qq(@$_\n) foreach @$data;
	open( my $fh, '>:encoding(utf8)', $full_file_path ) || $logger->error("Cannot open $full_file_path for writing");
	print $fh $buffer if $buffer;
	close $fh;
	return $filename;
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
		my $pk_info     = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $scheme_info->{'primary_key'} );
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
		$qry = $self->get_query_from_temp_file( scalar $q->param('query_file') );
	}
	if (@$errors) {
		local $" = '<br />';
		$self->print_bad_status( { message => q(Problem with search criteria:), detail => qq(@$errors) } );
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
		push @hidden_attributes, qw(scheme_id matches_list temp_table_file);
		my $table = $self->{'system'}->{'dbtype'} eq 'isolates' ? $self->{'system'}->{'view'} : 'profiles';
		my $args  = { table => $table, query => $qry, message => $msg, hidden_attributes => \@hidden_attributes };
		$args->{'passed_qry_file'} = $q->param('query_file') if defined $q->param('query_file');
		$self->paged_display($args);
	} else {
		$self->print_bad_status( { message => q(Invalid search performed.) } );
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
