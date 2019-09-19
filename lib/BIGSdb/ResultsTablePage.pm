#Written by Keith Jolley
#Copyright (c) 2010-2019, University of Oxford
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
package BIGSdb::ResultsTablePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Try::Tiny;
use List::MoreUtils qw(any);
use BIGSdb::Constants qw(:interface DATABANKS);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub _calculate_totals {
	my ( $self, $args ) = @_;
	my ( $table, $qry, $count, $passed_qry_file ) =
	  @{$args}{qw (table query count passed_qry_file)};
	my $q = $self->{'cgi'};
	$count //= $q->param('records');
	my $passed_qry;
	if ($passed_qry_file) {
		$passed_qry = $self->get_query_from_temp_file($passed_qry_file);
	} else {

		#query can get rewritten on route to this page - this enables the original query to be passed on
		$passed_qry_file = $self->make_temp_file($qry);
		$passed_qry      = $qry;
	}
	my $schemes = $self->{'datastore'}->run_query( 'SELECT id FROM schemes', undef, { fetch => 'col_arrayref' } );
	my $cschemes =
	  $self->{'datastore'}->run_query( 'SELECT id FROM classification_schemes', undef, { fetch => 'col_arrayref' } );
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $view = $self->{'system'}->{'view'};
		try {
			foreach my $scheme_id (@$schemes) {
				if (   $qry =~ /temp_(?:isolates|$view)_scheme_fields_$scheme_id\D/x
					|| $qry =~ /ORDER\ BY\ s_$scheme_id\D/x )
				{
					$self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
				}
				if ( $qry =~ /temp_(?:isolates|$view)_scheme_completion_$scheme_id\D/x ) {
					$self->{'datastore'}->create_temp_scheme_status_table($scheme_id);
				}
			}
			foreach my $cscheme_id (@$cschemes) {
				if ( $qry =~ /temp_cscheme_$cscheme_id\D/x ) {
					$self->{'datastore'}->create_temp_cscheme_table($cscheme_id);
				}
			}
		}
		catch {
			if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
				$self->print_bad_status(
					{ message => q(Cannot connect to remote database. The query cannot be performed.) } );
				$logger->error('Cannot create temporary table');
				return;
			} else {
				$logger->logdie($_);
			}
		};
	}
	if ( any { lc($qry) =~ /;\s*$_\s/x } (qw (insert delete update alter create drop)) ) {
		$self->print_bad_status( { message => q(Invalid query attempted.) } );
		$logger->warn("Malicious SQL injection attempt '$qry'");
		return;
	}

	#sort allele_id integers numerically
	my $sub = qq{(case when $table.allele_id ~ '^[0-9]+\$' THEN }
	  . qq{lpad\($table.allele_id,10,'0'\) else $table.allele_id end\)};
	$qry =~ s/ORDER\ BY\ (.+),\s*\S+\.allele_id(.*)/ORDER BY $1,$sub$2/x;
	$qry =~ s/ORDER\ BY\ \S+\.allele_id(.*)/ORDER BY $sub$1/x;
	if ( $q->param('displayrecs') ) {
		$self->{'prefs'}->{'displayrecs'} = $q->param('displayrecs') eq 'all' ? 0 : $q->param('displayrecs');
	}
	my $records;
	if ($count) {
		$records = $count;
	} else {
		my $qrycount = $qry;
		if ( $table eq 'allele_sequences' ) {

			#query may join the sequence_flags table giving more rows than allele sequences.
			$qrycount =~ s/SELECT\ \*/SELECT COUNT (DISTINCT allele_sequences.id)/x;
		}
		$qrycount =~ s/SELECT\ \*/SELECT COUNT (*)/x;
		$qrycount =~ s/ORDER\ BY.*//x;
		$records = $self->{'datastore'}->run_query($qrycount);
	}
	return {
		records  => $records,
		qry_file => $passed_qry_file
	};
}

sub paged_display {

	# $count is optional - if not provided it will be calculated, but this may not be the most
	# efficient algorithm, so if it has already been calculated prior to passing to this subroutine
	# it is better to not recalculate it.
	my ( $self, $args ) = @_;
	my ( $table, $qry, $message, $hidden_attributes, $count, $passed_qry_file ) =
	  @{$args}{qw (table query message hidden_attributes count passed_qry_file)};
	my $q = $self->{'cgi'};
	my ($record_calcs) = $self->_calculate_totals($args);
	return if !ref $record_calcs;
	my ( $records, $qry_file ) = @{$record_calcs}{qw(records qry_file)};
	$passed_qry_file //= $qry_file;
	$message = $q->param('message') if !$message;
	my $currentpage = $self->_get_current_page;
	$q->param( query_file  => $qry_file );
	$q->param( currentpage => $currentpage );
	$q->param( displayrecs => $self->{'prefs'}->{'displayrecs'} );
	$q->param( records     => $records );
	my $totalpages;

	if ( $self->{'prefs'}->{'displayrecs'} > 0 ) {
		$totalpages = $records / $self->{'prefs'}->{'displayrecs'};
	} else {
		$totalpages = 1;
		$self->{'prefs'}->{'displayrecs'} = 0;
	}
	my $bar_buffer_ref = $self->_get_pagebar(
		{
			table             => $table,
			currentpage       => $currentpage,
			totalpages        => $totalpages,
			message           => $message,
			hidden_attributes => $hidden_attributes
		}
	);
	$self->_print_results_header(
		{
			table           => $table,
			browse          => $args->{'browse'},
			records         => $records,
			message         => $message,
			currentpage     => $currentpage,
			totalpages      => $totalpages,
			passed_qry_file => $passed_qry_file,
			bar_buffer_ref  => $bar_buffer_ref
		}
	);
	return if !$records;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) {
		$self->_print_isolate_table( \$qry, $currentpage, $records );
	} elsif ( $table eq 'profiles' ) {
		$self->_print_profile_table( \$qry, $currentpage, $records );
	} elsif ( !$self->{'curate'} && $table eq 'refs' ) {
		$self->_print_publication_table( \$qry, $currentpage );
	} else {
		$self->_print_record_table( $table, \$qry, $currentpage, $records );
	}
	if (   $self->{'prefs'}->{'displayrecs'}
		&& $self->{'prefs'}->{'pagebar'} =~ /bottom/
		&& ( $currentpage > 1 || $currentpage < $totalpages ) )
	{
		say qq(<div class="box" id="resultsfooter">$$bar_buffer_ref</div>);
	}
	return;
}

sub _print_results_header {
	my ( $self, $args ) = @_;
	my ( $table, $browse, $records, $message, $currentpage, $totalpages, $passed_qry_file, $bar_buffer_ref ) =
	  @{$args}{qw(table browse records message currentpage totalpages passed_qry_file bar_buffer_ref)};
	say q(<div class="box" id="resultsheader">);
	if ($browse) {
		say q(<p>Browsing all records.</p>);
	}
	if ($records) {
		print qq(<p>$message</p>) if $message;
		my $plural = $records == 1 ? '' : 's';
		my $commify = BIGSdb::Utils::commify($records);
		print qq(<p>$commify record$plural returned);
		if ( $currentpage && $self->{'prefs'}->{'displayrecs'} ) {
			if ( $records > $self->{'prefs'}->{'displayrecs'} ) {
				my $first = ( ( $currentpage - 1 ) * $self->{'prefs'}->{'displayrecs'} ) + 1;
				my $last = $currentpage * $self->{'prefs'}->{'displayrecs'};
				if ( $last > $records ) {
					$last = $records;
				}
				print $first == $last ? " (record $first displayed)." : " ($first - $last displayed)";
			}
		}
		print '.';
		if ( !$self->{'curate'} || ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) ) {
			say qq( Click the hyperlink$plural for detailed information.);
		}
		say q(</p>);
		$self->_print_curate_headerbar_functions( $table, $passed_qry_file ) if $self->{'curate'};
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			$self->_print_project_add_function;
			$self->_print_publish_function;
		}
		$self->print_additional_headerbar_functions($passed_qry_file);
	} else {
		say q(<p>No records found!</p>);
	}
	if ( $self->{'prefs'}->{'pagebar'} =~ /top/
		&& ( $currentpage > 1 || $currentpage < $totalpages ) )
	{
		say $$bar_buffer_ref;
	}
	say q(</div>);
	return;
}

sub _get_pagebar {
	my ( $self, $args ) = @_;
	my ( $table, $currentpage, $totalpages, $message, $hidden_attributes ) =
	  @{$args}{qw(table currentpage totalpages message hidden_attributes)};
	my $q      = $self->{'cgi'};
	my $buffer = $q->start_form;
	$q->param( table => $table );
	$buffer .= $q->hidden($_)
	  foreach qw (query_file currentpage page db displayrecs order table direction sent records set_id);
	$buffer .= $q->hidden( message => $message ) if $message;

	#Make sure hidden_attributes don't duplicate the above
	$buffer .= $q->hidden($_) foreach @$hidden_attributes;
	if ( $currentpage > 1 || $currentpage < $totalpages ) {
		$buffer .= q(<table><tr><td>Page:</td>);
		if ( $currentpage > 1 ) {
			$buffer .= q(<td>);
			$buffer .= $q->submit( -name => 'First', -class => 'pagebar' );
			$buffer .= q(</td><td>);
			$buffer .= $q->submit( -name => $currentpage == 2 ? 'First' : '<', -label => ' < ', -class => 'pagebar' );
			$buffer .= q(</td>);
		}
		if ( $currentpage > 1 || $currentpage < $totalpages ) {
			my ( $first, $last );
			if   ( $currentpage < 9 ) { $first = 1 }
			else                      { $first = $currentpage - 8 }
			if ( $totalpages > ( $currentpage + 8 ) ) {
				$last = $currentpage + 8;
			} else {
				$last = $totalpages;
			}
			$buffer .= q(<td>);
			for ( my $i = $first ; $i < $last + 1 ; $i++ ) {   #don't use range operator as $last may not be an integer.
				if ( $i == $currentpage ) {
					$buffer .= qq(</td><th class="pagebar_selected">$i</th><td>);
				} else {
					$buffer .= $q->submit(
						-name => $i == 1 ? 'First' : 'pagejump',
						-value => $i,
						-label => $i,
						-class => 'pagebar'
					);
				}
			}
			$buffer .= q(</td>);
		}
		if ( $currentpage < $totalpages ) {
			$buffer .= q(<td>);
			$buffer .= $q->submit( -name => '>', -label => '>', -class => 'pagebar' );
			$buffer .= q(</td><td>);
			my $lastpage;
			if ( BIGSdb::Utils::is_int($totalpages) ) {
				$lastpage = $totalpages;
			} else {
				$lastpage = int $totalpages + 1;
			}
			$q->param( lastpage => $lastpage );
			$buffer .= $q->hidden('lastpage');
			$buffer .= $q->submit( -name => 'Last', -class => 'pagebar' );
			$buffer .= q(</td>);
		}
		$buffer .= qq(</tr></table>\n);
		$buffer .= $q->end_form;
	}
	return \$buffer;
}

sub _get_current_page {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $currentpage = $q->param('currentpage') ? $q->param('currentpage') : 1;
	return $currentpage + 1      if $q->param('>');
	return $currentpage - 1      if $q->param('<');
	return $q->param('pagejump') if $q->param('pagejump');
	return $q->param('lastpage') if $q->param('Last');
	return 1                     if $q->param('First');
	return $currentpage;
}

sub _print_curate_headerbar_functions {
	my ( $self, $table, $qry_filename ) = @_;
	my $q    = $self->{'cgi'};
	my $page = $q->param('page');
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) {
		$table = 'isolates';
	}
	if ( $self->can_modify_table($table) ) {
		$self->_print_delete_all_function($table);
		$self->_print_link_seq_to_experiment_function if $table eq 'sequence_bin';
		$self->_print_export_configuration_function($table);
		if (   ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes'
			&& $table eq 'sequences'
			&& $self->can_modify_table('sequences') )
		{
			$self->_print_set_sequence_flags_function;
		}
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		$self->_print_tag_scanning_function           if $self->can_modify_table('allele_sequences');
		$self->_print_modify_project_members_function if $self->can_modify_table('project_members');
	}
	$q->param( page => $page );    #reset
	return;
}

sub _print_project_add_function {
	my ($self) = @_;
	return if !$self->{'username'};
	return if !$self->{'addProjects'};
	my $q = $self->{'cgi'};
	return if $q->param('page') eq 'tableQuery';
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $projects  = $self->{'datastore'}->run_query(
		'SELECT p.id,p.short_description FROM project_users AS pu JOIN projects '
		  . 'AS p ON p.id=pu.project_id WHERE user_id=? AND admin ORDER BY UPPER(short_description)',
		$user_info->{'id'},
		{ fetch => 'all_arrayref', slice => {} }
	);
	return if !@$projects;
	my $project_ids = [0];
	my $labels = { 0 => 'Select project...' };

	foreach my $project (@$projects) {
		push @$project_ids, $project->{'id'};
		$labels->{ $project->{'id'} } = $project->{'short_description'};
	}
	say q(<fieldset><legend>Your projects</legend>);
	my $hidden_attributes = $self->get_hidden_attributes;
	say $q->start_form;
	say $q->popup_menu( -id => 'project', -name => 'project', -values => $project_ids, -labels => $labels );
	say $q->submit( -name => 'add_to_project', -label => 'Add these records', -class => BUTTON_CLASS );
	say qq(<span class="flash_message" style="margin-left:2em">$self->{'project_add_message'}</span>)
	  if $self->{'project_add_message'};
	say $q->hidden($_) foreach qw (db query_file temp_table_file table page);

	#Using print instead of say prevents blank line if attribute not set.
	print $q->hidden($_) foreach @$hidden_attributes;
	say $q->end_form;
	say q(</fieldset>);
	return;
}

sub _print_publish_function {
	my ($self) = @_;
	return if !$self->{'username'};
	my $q = $self->{'cgi'};
	return if $q->param('page') eq 'tableQuery';
	return if $q->param('page') eq 'plugin';
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	if ( $self->{'curate'} && $user_info->{'status'} ne 'submitter' ) {
		my $matched = $self->_get_query_private_records;
		return if !@$matched && !$q->param('publish');
	} else {
		my $matched = $self->_get_query_private_records( $user_info->{'id'} );
		return if !@$matched && !$q->param('publish');
	}
	say q(<fieldset><legend>Private records</legend>);
	my $label = $self->{'permissions'}->{'only_private'}
	  || !$self->can_modify_table('isolates') ? 'Request publication' : 'Publish';
	my $hidden_attributes = $self->get_hidden_attributes;
	say $q->start_form;
	say $q->submit( -name => 'publish', -label => $label, -class => BUTTON_CLASS );
	say qq(<span class="flash_message" style="margin-left:2em">$self->{'publish_message'}</span>)
	  if $self->{'publish_message'};
	say $q->hidden($_) foreach qw (db query_file list_file datatype table page);
	say $q->hidden($_) foreach @$hidden_attributes;
	say $q->end_form;
	say q(</fieldset>);
	return;
}

sub _get_query_private_records {
	my ( $self, $user_id ) = @_;
	my $ids = $self->get_query_ids;
	my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $ids );
	if ( !defined $user_id ) {
		return $self->{'datastore'}
		  ->run_query( "SELECT p.isolate_id FROM private_isolates p JOIN $temp_table t ON p.isolate_id=t.value",
			undef, { fetch => 'col_arrayref' } );
	} else {
		return $self->{'datastore'}->run_query(
			"SELECT p.isolate_id FROM private_isolates p JOIN $temp_table t ON p.isolate_id=t.value WHERE p.user_id=?",
			$user_id,
			{ fetch => 'col_arrayref' }
		);
	}
}

#Override in subclasses
sub get_hidden_attributes                { }
sub print_additional_headerbar_functions { }

sub _print_delete_all_function {
	my ( $self, $table ) = @_;
	return if !$self->can_delete_all;
	my $q = $self->{'cgi'};
	say q(<fieldset><legend>Delete</legend>);
	print $q->start_form;
	$q->param( page => 'deleteAll' );
	print $q->hidden($_) foreach qw (db page table query_file scheme_id list_file datatype);
	if ( $table eq 'allele_designations' ) {

		if ( $self->can_modify_table('allele_sequences') ) {
			say q(<ul><li>);
			say $q->checkbox( -name => 'delete_tags', -label => 'Delete corresponding sequence tags' );
			say q(</li></ul>);
		}
	}
	say $q->submit( -name => 'Delete ALL', -class => BUTTON_CLASS );
	say $q->end_form;
	say q(</fieldset>);
	return;
}

sub _print_link_seq_to_experiment_function {
	my ($self)            = @_;
	my $q                 = $self->{'cgi'};
	my $experiments_exist = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM experiments)');
	if ($experiments_exist) {
		say q(<fieldset><legend>Experiments</legend>);
		say $q->start_form;
		$q->param( page => 'linkToExperiment' );
		say $q->hidden($_) foreach qw (db page query_file list_file datatype);
		say $q->submit( -name => 'Link to experiment', -class => BUTTON_CLASS );
		say $q->end_form;
		say q(</fieldset>);
	}
	return;
}

sub _print_export_configuration_function {
	my ( $self, $table ) = @_;
	my $q = $self->{'cgi'};
	if (
		any { $table eq $_ }
		qw (schemes users user_groups user_group_members permissions projects project_members
		isolate_aliases accession experiments experiment_sequences allele_sequences loci locus_aliases
		pcr probes isolate_field_extended_attributes isolate_value_extended_attributes scheme_fields
		scheme_members scheme_groups scheme_group_scheme_members scheme_group_group_members locus_descriptions
		scheme_curators locus_curators sequences sequence_refs profile_refs locus_extended_attributes
		client_dbases client_dbase_loci client_dbase_schemes classification_schemes classification_group_fields
		validation_rules validation_conditions validation_rule_conditions)
	  )
	{
		say q(<fieldset><legend>Database configuration</legend>);
		say $q->start_form;
		$q->param( page => 'exportConfig' );
		say $q->hidden($_) foreach qw (db page table query_file list_file datatype);
		say $q->submit( -name => 'Export configuration/data', -class => BUTTON_CLASS );
		say $q->end_form;
		say q(</fieldset>);
	}
	return;
}

sub _print_tag_scanning_function {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="text-align:center"><legend>Tag scanning</legend>);
	say $q->start_form;
	$q->param( page => 'tagScan' );
	say $q->hidden($_) foreach qw (db page table query_file list_file datatype);
	say $q->submit( -name => 'Scan', -class => BUTTON_CLASS );
	say $q->end_form;
	say q(</fieldset>);
	return;
}

sub _print_modify_project_members_function {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $project_data =
	  $self->{'datastore'}->run_query( 'SELECT id,short_description FROM projects ORDER BY short_description',
		undef, { fetch => 'all_arrayref', slice => {} } );
	my ( @projects, %labels );
	foreach my $project (@$project_data) {
		push @projects, $project->{'id'};
		$labels{ $project->{'id'} } = $project->{'short_description'};
	}
	if (@projects) {
		say q(<fieldset><legend>Projects</legend>);
		unshift @projects, '';
		$labels{''} = 'Select project...';
		say $q->start_form;
		$q->param( page  => 'batchAdd' );
		$q->param( table => 'project_members' );
		say $q->hidden($_) foreach qw (db page table query_file list_file datatype);
		say $q->popup_menu( -name => 'project', -values => \@projects, -labels => \%labels );
		say $q->submit( -name => 'Link', -class => BUTTON_CLASS );
		say $q->end_form;
		say q(</fieldset>);
	}
	return;
}

sub _print_set_sequence_flags_function {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset><legend>Flags</legend>);
	say $q->start_form;
	$q->param( page => 'setAlleleFlags' );
	say $q->hidden($_) foreach qw (db page query_file list_file datatype);
	say $q->submit( -name => 'Batch set', -class => BUTTON_CLASS );
	say $q->end_form;
	say q(</fieldset>);
	return;
}

sub _get_composite_positions {
	my ($self) = @_;
	if ( !$self->{'composite_pos_determined'} ) {
		$self->{'cache'}->{'composites'}            = {};
		$self->{'cache'}->{'composite_display_pos'} = {};
		my $comp_data = $self->{'datastore'}->run_query( 'SELECT id,position_after FROM composite_fields',
			undef, { fetch => 'all_arrayref', slice => {} } );
		foreach my $comp (@$comp_data) {
			$self->{'cache'}->{'composite_display_pos'}->{ $comp->{'id'} }  = $comp->{'position_after'};
			$self->{'cache'}->{'composites'}->{ $comp->{'position_after'} } = 1;
		}
		$self->{'composite_pos_determined'} = 1;
	}
	return ( $self->{'cache'}->{'composites'}, $self->{'cache'}->{'composite_display_pos'} );
}

sub _print_isolate_table {
	my ( $self, $qryref, $page, $records ) = @_;
	my $pagesize   = $self->{'prefs'}->{'displayrecs'};
	my $q          = $self->{'cgi'};
	my $qry        = $$qryref;
	my $qry_limit  = $qry;
	my $is_curator = $self->is_curator;
	my $fields     = $self->{'xmlHandler'}->get_field_list( undef, { no_curate_only => !$is_curator } );
	push @$fields, 'new_version';
	my $view = $self->{'system'}->{'view'};
	local $" = ",$view.";
	my $field_string = "$view.@$fields";
	$qry_limit =~ s/SELECT\ ($view\.\*|\*)/SELECT $field_string/x;

	if ( $pagesize && $page ) {
		my $offset = ( $page - 1 ) * $pagesize;
		$qry_limit =~ s/;\s*$/ LIMIT $pagesize OFFSET $offset;/x;
	}
	$logger->debug("Passed query: $qry");
	my ( $sql, $limit_sql );
	$self->rewrite_query_ref_order_by( \$qry_limit );
	$limit_sql = $self->{'db'}->prepare($qry_limit);
	$logger->debug("Limit qry: $qry_limit");
	eval { $limit_sql->execute };
	if ($@) {
		$self->print_bad_status( { message => q(Invalid search performed) } );
		$logger->warn("Cannot execute query $qry_limit  $@");
		return;
	}
	my %data = ();
	$limit_sql->bind_columns( map { \$data{$_} } @$fields );    #quicker binding hash to arrayref than to use hashref
	my $set_id = $self->get_set_id;
	my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	say q(<div class="box" id="resultstable"><div class="scrollable"><table class="resultstable">);
	$self->_print_isolate_table_header( $schemes, $qry_limit );
	my $td = 1;
	local $" = '=? AND ';
	my $field_attributes;
	$field_attributes->{$_} = $self->{'xmlHandler'}->get_field_attributes($_) foreach (@$fields);
	$self->{'scheme_loci'}->{0} = $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $field_list =
	  $self->{'xmlHandler'}->get_field_list( $metadata_list, { no_curate_only => !$is_curator } );
	local $| = 1;
	my %id_used;

	while ( $limit_sql->fetchrow_arrayref ) {

		#Ordering by scheme field/locus can result in multiple rows per isolate if multiple values defined.
		next if $id_used{ $data{'id'} };
		$id_used{ $data{'id'} } = 1;
		my $profcomplete = 1;
		my $id;
		print qq(<tr class="td$td">);
		foreach my $thisfieldname (@$field_list) {
			$data{$thisfieldname} = '' if !defined $data{$thisfieldname};
			$data{$thisfieldname} =~ tr/\n/ /;
			if ( $self->{'prefs'}->{'maindisplayfields'}->{$thisfieldname} || $thisfieldname eq 'id' ) {
				if ( $thisfieldname eq 'id' ) {
					$id = $data{$thisfieldname};
					$self->_print_isolate_id_links( $id, \%data );
				} elsif ( $thisfieldname eq 'sender'
					|| $thisfieldname eq 'curator'
					|| ( ( $field_attributes->{'thisfieldname'}->{'userfield'} // '' ) eq 'yes' ) )
				{
					my $user_info = $self->{'datastore'}->get_user_info( $data{$thisfieldname} );
					print qq(<td>$user_info->{'first_name'} $user_info->{'surname'}</td>);
				} else {
					if ( $thisfieldname =~ /^meta_[^:]+:/x ) {
						my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($thisfieldname);
						my $value = $self->{'datastore'}->get_metadata_value( $id, $metaset, $metafield );
						print qq(<td>$value</td>);
					} else {
						print qq(<td>$data{$thisfieldname}</td>);
					}
				}
			}
			$self->_print_isolate_extended_attributes( $id, \%data, $thisfieldname );
			$self->_print_isolate_composite_fields( $id, \%data, $thisfieldname );
			$self->_print_isolate_aliases($id) if $thisfieldname eq $self->{'system'}->{'labelfield'};
		}
		$self->_print_isolate_eav_values($id);
		$self->_print_isolate_seqbin_values($id);
		$self->_print_isolate_publications($id);
		$self->_print_isolate_scheme_values( $schemes, $id );
		say q(</tr>);
		$td = $td == 1 ? 2 : 1;

		#Free up memory
		undef $self->{'allele_sequences'}->{$id};
		undef $self->{'designations'}->{$id};
		undef $self->{'allele_sequence_flags'}->{$id};
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
	}
	say q(</table></div>);
	$self->_print_plugin_buttons($records);
	say q(</div>);
	$sql->finish if $sql;
	return;
}

sub _print_isolate_id_links {
	my ( $self, $id, $data ) = @_;
	if ( $self->{'curate'} ) {
		say qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=isolateDelete&amp;id=$id" class="action">)
		  . DELETE
		  . q(</a></td>)
		  . qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=isolateUpdate&amp;id=$id" class="action">)
		  . EDIT
		  . q(</a></td>);
		if ( $self->can_modify_table('sequence_bin') ) {
			say qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=addSeqbin&amp;isolate_id=$id" class="action">)
			  . UPLOAD
			  . q(</a></td>);
		}
		if ( $self->{'system'}->{'view'} eq 'isolates' || $self->{'system'}->{'view'} eq 'temp_view' ) {
			print $data->{'new_version'}
			  ? qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'})
			  . qq(&amp;page=info&amp;id=$data->{'new_version'}">$data->{'new_version'}</a></td>)
			  : qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'})
			  . qq(&amp;page=newVersion&amp;id=$id" class="action">)
			  . ADD
			  . q(</a></td>);
		}
	}
	my $private_owner = $self->{'datastore'}->run_query( 'SELECT user_id FROM private_isolates WHERE isolate_id=?',
		$id, { cache => 'ResultsTablePage::print_isolate_id_links' } );
	my ( $private_title, $private_class ) = ( q(), q() );
	if ($private_owner) {
		$private_class = q( class="private_record");
		my $user_string = $self->{'datastore'}->get_user_string($private_owner);
		$private_title = qq( title="Private record - owned by $user_string");
	}
	my $set_id = $self->get_set_id;
	my $set_clause = $set_id ? qq(&amp;set_id=$set_id) : q();
	say qq(<td$private_class><a href="$self->{'system'}->{'script_name'}?page=info&amp;)
	  . qq(db=$self->{'instance'}$set_clause&amp;id=$id"$private_title>$id</a></td>);
	return;
}

sub _print_isolate_extended_attributes {
	my ( $self, $id, $data, $field ) = @_;
	if ( !$self->{'cache'}->{'extended'} ) {
		$self->{'cache'}->{'extended'} = $self->get_extended_attributes;
	}
	my $extatt = $self->{'cache'}->{'extended'}->{$field};
	if ( ref $extatt eq 'ARRAY' ) {
		foreach my $extended_attribute (@$extatt) {
			if ( $self->{'prefs'}->{'maindisplayfields'}->{"$field\..$extended_attribute"} ) {
				my $value = $self->{'datastore'}->run_query(
					'SELECT value FROM isolate_value_extended_attributes WHERE '
					  . '(isolate_field,attribute,field_value)=(?,?,?)',
					[ $field, $extended_attribute, $data->{$field} ],
					{ cache => 'ResultsTablePage::print_isolate_extended_attributes' }
				);
				print defined $value ? qq(<td>$value</td>) : q(<td></td>);
			}
		}
	}
	return;
}

sub _print_isolate_composite_fields {
	my ( $self, $id, $data, $field ) = @_;
	my ( $composites, $composite_display_pos ) = $self->_get_composite_positions;
	if ( $composites->{$field} ) {
		foreach my $current_field ( keys %$composite_display_pos ) {
			next if $composite_display_pos->{$current_field} ne $field;
			if ( $self->{'prefs'}->{'maindisplayfields'}->{$current_field} ) {
				my $value = $self->{'datastore'}->get_composite_value( $id, $current_field, $data );
				print defined $value ? qq(<td>$value</td>) : q(<td></td>);
			}
		}
	}
	return;
}

sub _print_isolate_aliases {
	my ( $self, $id ) = @_;
	if ( $self->{'prefs'}->{'maindisplayfields'}->{'aliases'} ) {
		my $aliases = $self->{'datastore'}->get_isolate_aliases($id);
		local $" = '; ';
		print qq(<td>@$aliases</td>);
	}
	return;
}

sub _print_isolate_eav_values {
	my ( $self, $id ) = @_;
	if ( !defined $self->{'cache'}->{'eav_fields'} ) {
		$self->{'cache'}->{'eav_fields'} = [];
		my $all_eav_fields = $self->{'datastore'}->get_eav_fields;
		foreach my $eav_field (@$all_eav_fields) {
			push @{ $self->{'cache'}->{'eav_fields'} }, $eav_field
			  if $self->{'prefs'}->{'maindisplayfields'}->{ $eav_field->{'field'} };
		}
	}
	my $eav_fields = $self->{'cache'}->{'eav_fields'};
	return if !@$eav_fields;
	my %table = (
		integer => 'eav_int',
		float   => 'eav_float',
		text    => 'eav_text',
		date    => 'eav_date',
		boolean => 'eav_boolean'
	);
	foreach my $eav_field (@$eav_fields) {
		my $table = $table{ $eav_field->{'value_format'} };
		my $value = $self->{'datastore'}->run_query(
			"SELECT value FROM $table WHERE (isolate_id,field)=(?,?)",
			[ $id, $eav_field->{'field'} ],
			{ cache => "ResutsTable::print_isolate_eav_values::$table" }
		);
		$value //= q();
		print qq(<td>$value</td>);
	}
	return;
}

sub _print_isolate_seqbin_values {
	my ( $self, $id ) = @_;
	if ( $self->{'prefs'}->{'display_seqbin_main'} || $self->{'prefs'}->{'display_contig_count'} ) {
		my $stats = $self->_get_seqbin_stats($id);
		print qq(<td>$stats->{'total_length'}</td>) if $self->{'prefs'}->{'display_seqbin_main'};
		print qq(<td>$stats->{'contigs'}</td>)      if $self->{'prefs'}->{'display_contig_count'};
	}
	return;
}

sub _get_seqbin_stats {
	my ( $self, $isolate_id ) = @_;
	my $stats = $self->{'datastore'}->run_query( 'SELECT contigs,total_length FROM seqbin_stats WHERE isolate_id=?',
		$isolate_id, { fetch => 'row_hashref', cache => 'ResultsTablePage::get_seqbin_stats' } );
	$stats = { contigs => 0, total_length => 0 } if !$stats;
	return $stats;
}

sub _print_isolate_publications {
	my ( $self, $isolate_id ) = @_;
	if ( $self->{'prefs'}->{'display_publications'} ) {
		my $pmids = $self->{'datastore'}->get_isolate_refs($isolate_id);
		my $citations = $self->{'datastore'}->get_citation_hash( $pmids, { link_pubmed => 1 } );
		my @formatted_list;
		foreach my $pmid ( sort { $citations->{$a} cmp $citations->{$b} } @$pmids ) {
			push @formatted_list, $citations->{$pmid};
		}
		local $" = '<br />';
		print qq(<td>@formatted_list</td>);
	}
	return;
}

sub _print_isolate_scheme_values {
	my ( $self, $schemes, $isolate_id ) = @_;
	my @scheme_ids;
	push @scheme_ids, $_->{'id'} foreach (@$schemes);
	foreach my $scheme_id ( @scheme_ids, 0 ) {
		next
		  if !$self->{'prefs'}->{'main_display_schemes'}->{$scheme_id} && $scheme_id;
		next
		  if ( $self->{'system'}->{'hide_unused_schemes'} // '' ) eq 'yes'
		  && !$self->{'cache'}->{'scheme_data_present'}->{$scheme_id}
		  && $scheme_id;
		$self->_print_isolate_table_scheme( $isolate_id, $scheme_id );
	}
	return;
}

sub _print_isolate_table_header {
	my ( $self, $schemes, $limit_qry ) = @_;
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $is_curator    = $self->is_curator;
	my $select_items =
	  $self->{'xmlHandler'}->get_field_list( $metadata_list, { no_curate_only => !$is_curator } );
	my $header_buffer = q(<tr>);
	my $col_count;
	my $extended = $self->get_extended_attributes;
	my ( $composites, $composite_display_pos ) = $self->_get_composite_positions;
	my $eav_fields = $self->{'datastore'}->get_eav_fieldnames;

	foreach my $col ( @$select_items, @$eav_fields ) {
		if ( $self->{'prefs'}->{'maindisplayfields'}->{$col} || $col eq 'id' ) {
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($col);
			( my $display_col = $metafield // $col ) =~ tr/_/ /;
			$header_buffer .= qq(<th>$display_col</th>);
			$col_count++;
		}
		if ( $composites->{$col} ) {
			foreach my $field ( keys %$composite_display_pos ) {
				next if $composite_display_pos->{$field} ne $col;
				if ( $self->{'prefs'}->{'maindisplayfields'}->{$field} ) {
					my $displayfield = $field;
					$displayfield =~ tr/_/ /;
					$header_buffer .= qq(<th>$displayfield</th>);
					$col_count++;
				}
			}
		}
		if ( $col eq $self->{'system'}->{'labelfield'} && $self->{'prefs'}->{'maindisplayfields'}->{'aliases'} ) {
			$header_buffer .= q(<th>aliases</th>);
			$col_count++;
		}
		my $extatt = $extended->{$col};
		if ( ref $extatt eq 'ARRAY' ) {
			foreach my $extended_attribute (@$extatt) {
				if ( $self->{'prefs'}->{'maindisplayfields'}->{"$col\..$extended_attribute"} ) {
					( my $display_field = $extended_attribute ) =~ tr/_/ /;
					$header_buffer .= qq(<th>$display_field</th>);
					$col_count++;
				}
			}
		}
	}
	my $fieldtype_header = q(<tr>);
	if ( $self->{'curate'} ) {
		$fieldtype_header .= q(<th rowspan="2">Delete</th><th rowspan="2">Update</th>);
		if ( $self->can_modify_table('sequence_bin') ) {
			$fieldtype_header .= q(<th rowspan="2">Sequence bin</th>);
		}
		$fieldtype_header .= q(<th rowspan="2">New version</th>)
		  if $self->{'system'}->{'view'} eq 'isolates' || $self->{'system'}->{'view'} eq 'temp_view';
	}
	$fieldtype_header .= qq(<th colspan="$col_count">Isolate fields);
	$fieldtype_header .= $self->get_tooltip(
		q(Isolate fields - You can select the isolate fields )
		  . q(that are displayed here by going to the options page.),
		{ style => 'color:white' }
	);
	$fieldtype_header .= q(</th>);
	my %pref_fields = (
		display_seqbin_main  => 'Seqbin size (bp)',
		display_contig_count => 'Contigs',
		display_publications => 'Publications'
	);
	foreach my $field (qw (display_seqbin_main display_contig_count display_publications)) {
		$fieldtype_header .= qq(<th rowspan="2">$pref_fields{$field}</th>) if $self->{'prefs'}->{$field};
	}
	my ( $scheme_field_type_header, $scheme_header ) = $self->_get_isolate_header_scheme_fields( $schemes, $limit_qry );
	$fieldtype_header .= $scheme_field_type_header;
	$header_buffer    .= $scheme_header;
	my @locus_header;
	my $loci = $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
	foreach my $locus (@$loci) {
		if ( $self->{'prefs'}->{'main_display_loci'}->{$locus} ) {
			my $aliases       = $self->{'datastore'}->get_locus_aliases($locus);
			my $cleaned_locus = $self->clean_locus($locus);
			local $" = ', ';
			push @locus_header, $cleaned_locus . ( @$aliases ? qq( <span class="comment">(@$aliases)</span>) : '' );
		}
	}
	my $locus_cols = @locus_header;
	if (@locus_header) {
		$fieldtype_header .= qq(<th colspan="$locus_cols">Loci</th>);
	}
	local $" = q(</th><th>);
	$header_buffer .= qq(<th>@locus_header</th>) if @locus_header;
	$fieldtype_header .= qq(</tr>\n);
	$header_buffer    .= qq(</tr>\n);
	print $fieldtype_header;
	print $header_buffer;
	return;
}

sub _get_isolate_header_scheme_fields {
	my ( $self, $schemes, $limit_qry ) = @_;
	my $field_type_header = q();
	my $header            = q();
	foreach my $scheme (@$schemes) {
		my $scheme_id = $scheme->{'id'};
		next if !$self->{'prefs'}->{'main_display_schemes'}->{$scheme_id};
		if ( $scheme_id && !defined $self->{'cache'}->{'scheme_data_present'}->{$scheme_id} ) {
			$self->{'cache'}->{'scheme_data_present'}->{$scheme_id} =
			  $self->_is_scheme_data_present( $limit_qry, $scheme_id );
		}
		next
		  if ( $self->{'system'}->{'hide_unused_schemes'} // '' ) eq 'yes'
		  && !$self->{'cache'}->{'scheme_data_present'}->{$scheme_id};
		if ( !$self->{'scheme_loci'}->{$scheme_id} ) {
			$self->{'scheme_loci'}->{$scheme_id} = $self->{'datastore'}->get_scheme_loci($scheme_id);
		}
		my @scheme_header;
		foreach ( @{ $self->{'scheme_loci'}->{$scheme_id} } ) {
			if ( $self->{'prefs'}->{'main_display_loci'}->{$_} ) {
				my $locus_header = $self->clean_locus($_);
				if ( $self->{'prefs'}->{'locus_alias'} ) {
					my $aliases = $self->{'datastore'}->get_locus_aliases($_);
					local $" = ', ';
					$locus_header .= qq( <span class="comment">(@$aliases)</span>) if @$aliases;
				}
				push @scheme_header, $locus_header;
			}
		}
		if ( !$self->{'scheme_fields'}->{$scheme_id} ) {
			$self->{'scheme_fields'}->{$scheme_id} = $self->{'datastore'}->get_scheme_fields($scheme_id);
		}
		if ( ref $self->{'scheme_fields'}->{$scheme_id} eq 'ARRAY' ) {
			foreach my $field_name ( @{ $self->{'scheme_fields'}->{$scheme_id} } ) {
				next if !$self->{'prefs'}->{'main_display_scheme_fields'}->{$scheme_id}->{$field_name};
				my $field = $field_name;
				$field =~ tr/_/ /;
				my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field_name );
				if ( $scheme_field_info->{'description'} ) {
					$field .= $self->get_tooltip( qq($field - $scheme_field_info->{'description'}),
						{ style => 'color:white' } );
				}
				push @scheme_header, $field;
			}
		}
		my $scheme_cols = @scheme_header;
		if ($scheme_cols) {
			$field_type_header .= qq(<th colspan="$scheme_cols">$scheme->{'name'}</th>);
		}
		local $" = q(</th><th>);
		$header .= qq(<th>@scheme_header</th>) if @scheme_header;
	}
	return ( $field_type_header, $header );
}

#Sorts by confirmed/provisional status, then numerical values, then alphabetical value.
sub _sort_allele_ids {
	my ( $self, $allele_designations, $locus ) = @_;
	no warnings 'numeric';    #might complain about numeric comparison with non-numeric data
	my @allele_ids =
	  sort { $allele_designations->{$locus}->{$a} cmp $allele_designations->{$locus}->{$b} || $a <=> $b || $a cmp $b }
	  keys %{ $allele_designations->{$locus} };
	return \@allele_ids;
}

sub _sort_scheme_field_values {
	my ( $self, $scheme_field_values, $field ) = @_;
	my @field_values = keys %{ $scheme_field_values->{ lc($field) } };
	no warnings 'numeric';    #might complain about numeric comparison with non-numeric data
	my @values = sort {
		     $scheme_field_values->{ lc($field) }->{$a} cmp $scheme_field_values->{ lc($field) }->{$b}
		  || $a <=> $b
		  || $a cmp $b
	} @field_values;
	return \@values;
}

sub _initiate_isolate_cache {
	my ( $self, $isolate_id, $scheme_id ) = @_;
	if ( !$self->{'scheme_fields'}->{$scheme_id} ) {
		$self->{'scheme_fields'}->{$scheme_id} = $self->{'datastore'}->get_scheme_fields($scheme_id);
	}
	if ( !$self->{'urls_defined'} && $self->{'prefs'}->{'hyperlink_loci'} ) {
		$self->_initiate_urls_for_loci;
	}
	if ( !$self->{'designations_retrieved'}->{$isolate_id} ) {
		$self->{'designations'}->{$isolate_id} =
		  $self->{'datastore'}->get_all_allele_designations( $isolate_id, { show_ignored => $self->{'curate'} } );
		$self->{'designations_retrieved'}->{$isolate_id} = 1;
	}
	return;
}

sub _get_designation_status {
	my ( $self, $allele_designations, $locus, $allele_id ) = @_;
	if ( ( $allele_designations->{$locus}->{$allele_id} // q() ) eq 'provisional'
		&& $self->{'prefs'}->{'mark_provisional_main'} )
	{
		return 'provisional';
	}
	if ( ( $allele_designations->{$locus}->{$allele_id} // q() ) eq 'ignore' ) {
		return 'ignore';
	}
	return;
}

sub _print_isolate_table_scheme {
	my ( $self, $isolate_id, $scheme_id ) = @_;
	$self->_initiate_isolate_cache( $isolate_id, $scheme_id );
	my $allele_designations = $self->{'designations'}->{$isolate_id};
	my $loci                = $self->{'scheme_loci'}->{$scheme_id};
	foreach my $locus (@$loci) {
		next if !$self->{'prefs'}->{'main_display_loci'}->{$locus};
		my @display_values;
		my $allele_ids = $self->_sort_allele_ids( $allele_designations, $locus );
		foreach my $allele_id (@$allele_ids) {
			my $status = $self->_get_designation_status( $allele_designations, $locus, $allele_id );
			my $display = q();
			$display .= qq(<span class="$status">) if $status;
			if (   defined $self->{'url'}->{$locus}
				&& $self->{'url'}->{$locus} ne ''
				&& $self->{'prefs'}->{'main_display_loci'}->{$locus}
				&& $self->{'prefs'}->{'hyperlink_loci'} )
			{
				my $url = $self->{'url'}->{$locus};
				$url =~ s/\[\?\]/$allele_id/gx;
				$display .= qq(<a href="$url">$allele_id</a>);
			} else {
				$display .= $allele_id;
			}
			$display .= q(</span>) if $status;
			push @display_values, $display;
		}
		local $" = ',';
		print qq(<td>@display_values);
		print $self->get_seq_detail_tooltips( $isolate_id, $locus, { allele_flags => 1 } )
		  if $self->{'prefs'}->{'sequence_details_main'};
		my $action = @display_values ? EDIT : ADD;
		print qq( <a href="$self->{'system'}->{'script_name'}?page=alleleUpdate&amp;db=$self->{'instance'}&amp;)
		  . qq(isolate_id=$isolate_id&amp;locus=$locus">$action</a>)
		  if $self->{'curate'};
		print q(</td>);
	}
	return
	     if !$scheme_id
	  || !@{ $self->{'scheme_fields'}->{$scheme_id} }
	  || !$self->{'prefs'}->{'main_display_schemes'}->{$scheme_id};
	my $scheme_fields = $self->{'scheme_fields'}->{$scheme_id};
	my $scheme_field_values = $self->{'datastore'}->get_scheme_field_values_by_isolate_id( $isolate_id, $scheme_id );
	foreach my $field (@$scheme_fields) {
		if ( $self->{'prefs'}->{'main_display_scheme_fields'}->{$scheme_id}->{$field} ) {
			my @values;
			my $field_values = $self->_sort_scheme_field_values( $scheme_field_values, $field );
			my $att = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
			foreach my $value (@$field_values) {
				$value = defined $value ? $value : q();
				next if $value eq q();
				my $formatted_value;
				my $provisional = ( $scheme_field_values->{ lc($field) }->{$value} // q() ) eq 'provisional' ? 1 : 0;
				$provisional = 0 if $value eq '';
				$formatted_value .= q(<span class="provisional">) if $provisional;
				if ( $self->{'prefs'}->{'hyperlink_loci'} && $att->{'url'} && $value ne q() ) {
					my $url = $att->{'url'};
					$url =~ s/\[\?\]/$value/gx;
					$url =~ s/\&/\&amp;/gx;
					$formatted_value .= qq(<a href="$url">$value</a>);
				} else {
					$formatted_value .= $value;
				}
				$formatted_value .= q(</span>) if $provisional;
				push @values, $formatted_value;
			}
			local $" = ',';
			print qq(<td>@values</td>);
		}
	}
	return;
}

sub _print_profile_table {
	my ( $self, $qryref, $page, $records ) = @_;
	my $pagesize  = $self->{'prefs'}->{'displayrecs'};
	my $q         = $self->{'cgi'};
	my $qry       = $$qryref;
	my $qry_limit = $qry;
	my $scheme_id;
	if ( $qry =~ /FROM\ m?v?_?scheme_(\d+)/x || $qry =~ /scheme_id='?(\d+)'?/x ) {
		$scheme_id = $1;
	}
	if ( !$scheme_id ) {
		$logger->error('No scheme id determined.');
		return;
	}
	if ( $pagesize && $page ) {
		my $offset = ( $page - 1 ) * $pagesize;
		$qry_limit =~ s/;\s*$/ LIMIT $pagesize OFFSET $offset;/x;
	}
	my ( $sql, $limit_sql );
	$limit_sql = $self->{'db'}->prepare($qry_limit);
	$logger->debug("Limit qry: $qry_limit");
	eval { $limit_sql->execute };
	if ($@) {
		$self->print_bad_status( { message => q(Invalid search performed.) } );
		$logger->warn("Cannot execute query $qry_limit  $@");
		return;
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	if ( !$primary_key ) {
		$self->print_bad_status(
			{
				message => q(No primary key field has been set for this scheme. )
				  . q(Profile browsing can not be done until this has been set.),
				navbar => 1
			}
		);
		return;
	}
	say q(<div class="box" id="resultstable"><div class="scrollable"><table class="resultstable"><tr>);
	say q(<th>Delete</th><th>Update</th>) if $self->{'curate'};
	print qq(<th>$primary_key);
	my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	if ( $scheme_field_info->{'description'} ) {
		say $self->get_tooltip( qq($primary_key - $scheme_field_info->{'description'}), { style => 'color:white' } );
	}
	say q(</th>);
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach (@$loci) {
		my $cleaned = $self->clean_locus($_);
		say qq(<th>$cleaned</th>);
	}
	foreach my $field (@$scheme_fields) {
		next if $primary_key eq $field;
		my $cleaned = $field;
		$cleaned =~ tr/_/ /;
		$scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		if ( $scheme_field_info->{'description'} ) {
			$cleaned .=
			  $self->get_tooltip( qq($cleaned - $scheme_field_info->{'description'}), { style => 'color:white' } );
		}
		say qq(<th>$cleaned</th>);
	}
	say q(</tr>);
	my $td            = 1;
	my $locus_indices = $self->{'datastore'}->get_scheme_locus_indices($scheme_id);

	#Run limited page query for display
	while ( my $data = $limit_sql->fetchrow_hashref ) {
		my $pk_value     = $data->{ lc($primary_key) };
		my $profcomplete = 1;
		print qq(<tr class="td$td">);
		if ( $self->{'curate'} ) {
			say qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=delete&amp;table=profiles&amp;scheme_id=$scheme_id&amp;profile_id=$pk_value" class="action">)
			  . DELETE
			  . q(</a></td>)
			  . qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=profileUpdate&amp;scheme_id=$scheme_id&amp;profile_id=$pk_value" class="action">)
			  . EDIT
			  . q(</a></td>);
			say qq(<td><a href="$self->{'system'}->{'script_name'}?page=profileInfo&amp;db=$self->{'instance'}&amp;)
			  . qq(scheme_id=$scheme_id&amp;profile_id=$pk_value&amp;curate=1">$pk_value</a></td>);
		} else {
			say qq(<td><a href="$self->{'system'}->{'script_name'}?page=profileInfo&amp;db=$self->{'instance'}&amp;)
			  . qq(scheme_id=$scheme_id&amp;profile_id=$pk_value">$pk_value</a></td>);
		}
		foreach my $locus (@$loci) {
			print qq(<td>$data->{'profile'}->[$locus_indices->{$locus}]</td>);
		}
		foreach (@$scheme_fields) {
			next if $_ eq $primary_key;
			print defined $data->{ lc($_) } ? qq(<td>$data->{lc($_)}</td>) : q(<td></td>);
		}
		say q(</tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</table></div>);
	$self->_print_plugin_buttons($records);
	say q(</div>);
	$sql->finish if $sql;
	return;
}

sub _print_plugin_buttons {
	my ( $self, $records ) = @_;
	my $q = $self->{'cgi'};
	return if $q->param('page') eq 'customize';
	my %no_show = map { $_ => 1 } qw(sequences history profile_history);
	return if $q->param('page') eq 'tableQuery' && $no_show{ $q->param('table') };
	my $seqdb_type = $q->param('page') eq 'alleleQuery' ? 'sequences' : 'schemes';
	my $plugin_categories =
	  $self->{'pluginManager'}
	  ->get_plugin_categories( 'postquery', $self->{'system'}->{'dbtype'}, { seqdb_type => $seqdb_type } );
	if (@$plugin_categories) {
		my %icon = (
			Breakdown     => 'fas fa-chart-pie',
			Export        => 'far fa-save',
			Analysis      => 'fas fa-chart-line',
			'Third party' => 'fas fa-external-link-alt',
			Miscellaneous => 'far fa-file-alt'
		);
		say q(<h2>Analysis tools:</h2>);
		my $set_id = $self->get_set_id;
		foreach my $category (@$plugin_categories) {
			my $cat_buffer;
			my $plugin_names = $self->{'pluginManager'}->get_appropriate_plugin_names(
				'postquery',
				$self->{'system'}->{'dbtype'},
				$category || 'none',
				{ set_id => $set_id, seqdb_type => $seqdb_type }
			);
			if (@$plugin_names) {
				my $plugin_buffer;
				$q->param( calling_page => scalar $q->param('page') );
				foreach my $plugin_name (@$plugin_names) {
					my $att = $self->{'pluginManager'}->get_plugin_attributes($plugin_name);
					next if $att->{'min'} && $att->{'min'} > $records;
					next if $att->{'max'} && $att->{'max'} < $records;
					$plugin_buffer .= $q->start_form( -style => 'float:left;margin-right:0.2em;margin-bottom:0.3em' );
					$q->param( page   => 'plugin' );
					$q->param( name   => $att->{'module'} );
					$q->param( set_id => $set_id );
					$plugin_buffer .= $q->hidden($_)
					  foreach qw (db page name calling_page scheme_id locus set_id list_file datatype);

					if ( ( $att->{'input'} // '' ) eq 'query' ) {
						$plugin_buffer .= $q->hidden('query_file');
						$plugin_buffer .= $q->hidden('temp_table_file');
					}
					$plugin_buffer .=
					  $q->submit( -label => ( $att->{'buttontext'} || $att->{'menutext'} ), -class => 'plugin_button' );
					$plugin_buffer .= $q->end_form;
				}
				if ($plugin_buffer) {
					$category = 'Miscellaneous' if !$category;
					$cat_buffer .=
					    q(<div><span style="float:left;text-align:right;width:8em;)
					  . q(white-space:nowrap;margin-right:0.5em">)
					  . qq(<span class="fa-fw fa-lg $icon{$category} main_icon" style="margin-right:0.2em">)
					  . qq(</span>$category:</span>)
					  . q(<div style="margin-left:8.5em;margin-bottom:0.2em">);
					$cat_buffer .= $plugin_buffer;
					$cat_buffer .= q(</div></div>);
				}
			}
			say qq($cat_buffer<div style="clear:both"></div>) if $cat_buffer;
		}
	}
	return;
}

sub _hide_field {
	my ( $self, $attr ) = @_;
	return 1 if $attr->{'hide'};
	return 1 if $attr->{'hide_public'} && !$self->{'curate'};
	return 1 if $attr->{'main_display'} eq 'no';
	return;
}

sub _get_record_table_info {
	my ( $self, $table ) = @_;
	my $q = $self->{'cgi'};
	my ( @headers, @display, @qry_fields, %type, %foreign_key, %labels );
	my $user_variable_fields = 0;
	my $attributes           = $self->{'datastore'}->get_table_field_attributes($table);
	foreach my $attr (@$attributes) {
		next if $table eq 'sequence_bin' && $attr->{'name'} eq 'sequence';
		next if $self->_hide_field($attr);
		push @display,    $attr->{'name'};
		push @qry_fields, "$table.$attr->{'name'}";
		my $cleaned = $attr->{'name'};
		$cleaned =~ tr/_/ /;
		my %overridable =
		  map { $_ => 1 } qw (isolate_display main_display query_field query_status dropdown analysis disable);
		if ( $overridable{ $attr->{'name'} } && $table ne 'projects' ) {
			$cleaned .= '*';
			$user_variable_fields = 1;
		}
		if ( !$attr->{'hide_query'} ) {
			push @headers, $cleaned;
			push @headers, 'isolate id' if $table eq 'experiment_sequences' && $attr->{'name'} eq 'experiment_id';
			push @headers, 'sequence length'
			  if $q->param('page') eq 'tableQuery' && $table eq 'sequences' && $attr->{'name'} eq 'sequence';
			push @headers, 'sequence length' if $q->param('page') eq 'alleleQuery' && $attr->{'name'} eq 'sequence';
			push @headers, 'flag'            if $table eq 'allele_sequences'       && $attr->{'name'} eq 'complete';
			push @headers, 'citation'        if $attr->{'name'} eq 'pubmed_id';
		}
		$type{ $attr->{'name'} }        = $attr->{'type'};
		$foreign_key{ $attr->{'name'} } = $attr->{'foreign_key'};
		$labels{ $attr->{'name'} }      = $attr->{'labels'};
	}
	my $extended_attributes;
	my $linked_data;
	if ( $q->param('page') eq 'alleleQuery' && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $locus = $q->param('locus');
		if ( $self->{'datastore'}->is_locus($locus) ) {
			$extended_attributes =
			  $self->{'datastore'}->run_query(
				'SELECT field,url FROM locus_extended_attributes WHERE locus=? AND main_display ORDER BY field_order',
				$locus, { fetch => 'all_arrayref', slice => {} } );
			foreach my $ext_att (@$extended_attributes) {
				( my $cleaned = $ext_att->{'field'} ) =~ tr/_/ /;
				push @headers, $cleaned;
			}
			my $databanks =
			  $self->{'datastore'}
			  ->run_query( 'SELECT DISTINCT databank FROM accession WHERE locus=?',
				$locus, { fetch => 'col_arrayref' } );
			push @headers, sort @$databanks;
			if ( $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM sequence_refs WHERE locus=?)', $locus ) )
			{
				push @headers, 'Publications';
			}
			$linked_data = $self->_data_linked_to_locus($locus);
			push @headers, 'linked data values' if $linked_data;
		}
	} elsif ( $table eq 'sequence_bin' ) {
		$extended_attributes =
		  $self->{'datastore'}
		  ->run_query( 'SELECT key FROM sequence_attributes ORDER BY key', undef, { fetch => 'col_arrayref' } );
		my @cleaned = @$extended_attributes;
		tr/_/ / foreach @cleaned;
		push @headers, @cleaned;
	}
	if ( $self->_show_allele_flags ) {
		push @headers, 'flags';
	}
	return (
		{
			headers              => \@headers,
			qry_fields           => \@qry_fields,
			display              => \@display,
			type                 => \%type,
			foreign_key          => \%foreign_key,
			labels               => \%labels,
			extended_attributes  => $extended_attributes,
			linked_data          => $linked_data,
			user_variable_fields => $user_variable_fields
		}
	);
}

sub _show_allele_flags {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if (
		(
			( $q->param('page') eq 'tableQuery' && $q->param('table') eq 'sequences' )
			|| $q->param('page') eq 'alleleQuery'
		)
		&& ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes'
	  )
	{
		return 1;
	}
	return;
}

sub _get_page_query {
	my ( $self, $qry_ref, $table, $page ) = @_;
	my $pagesize = $self->{'prefs'}->{'displayrecs'};
	my $qry      = $$qry_ref;
	if ( $pagesize && $page ) {
		my $offset = ( $page - 1 ) * $pagesize;
		$qry =~ s/;/ LIMIT $pagesize OFFSET $offset;/x;
	}
	my $table_info = $self->_get_record_table_info($table);
	my $qry_fields = $table_info->{'qry_fields'};
	local $" = ',';
	my $fields = "@$qry_fields";
	if ( $table eq 'allele_sequences' && $qry =~ /sequence_flags/x ) {
		$qry =~ s/\*/DISTINCT $fields/x;
	} else {
		$qry =~ s/\*/$fields/x;
	}
	return $qry;
}

sub _print_record_table {
	my ( $self, $table, $qryref, $page, $records ) = @_;
	my $q = $self->{'cgi'};
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) {
		$logger->error('Record table should not be called for isolates');
		return;
	}
	my $qry = $self->_get_page_query( $qryref, $table, $page );
	my $dataset = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	return if !@$dataset;
	$self->modify_dataset_if_needed( $table, $dataset );
	local $" = q(</th><th>);
	say q(<div class="box" id="resultstable"><div class="scrollable"><table class="resultstable">);
	say q(<tr>);

	if ( $self->{'curate'} ) {
		print q(<th>Delete</th>);
		print q(<th>Update</th>) if $table !~ /refs$/x;
	}
	my $table_info = $self->_get_record_table_info($table);
	my ( $headers, $display, $extended_attributes ) = @{$table_info}{qw(headers display extended_attributes)};
	say qq(<th>@$headers</th></tr>);
	my $td         = 1;
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my %hide_field;
	foreach my $data (@$dataset) {
		my @query_values;
		my %primary_key;
		local $" = '&amp;';
		foreach my $att (@$attributes) {
			if ( $att->{'primary_key'} ) {
				$primary_key{ $att->{'name'} } = 1;
				my $value = $data->{ $att->{'name'} };
				$value = CGI::Util::escape($value);
				push @query_values, "$att->{'name'}=$value";
			}
			$hide_field{ $att->{'name'} } = 1 if $att->{'hide_query'};
		}
		print qq(<tr class="td$td">);
		if ( $self->{'curate'} ) {
			print qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=delete&amp;table=$table&amp;@query_values" class="action">)
			  . DELETE
			  . q(</a></td>);
			if ( $table eq 'allele_sequences' ) {
				print qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=tagUpdate&amp;@query_values" class="action">)
				  . EDIT
				  . q(</a></td>);
			} elsif ( $table !~ /refs$/x ) {    #no editable values in ref tables
				print qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=update&amp;table=$table&amp;@query_values" class="action">)
				  . EDIT
				  . q(</a></td>);
			}
		}
		my $set_id = $self->get_set_id;
		my $scheme_info =
		    $data->{'scheme_id'}
		  ? $self->{'datastore'}->get_scheme_info( $data->{'scheme_id'}, { set_id => $set_id } )
		  : undef;
		foreach my $field (@$display) {
			next if $hide_field{$field};
			$self->_print_record_field(
				{
					table        => $table,
					table_info   => $table_info,
					data         => $data,
					field        => $field,
					primary_key  => \%primary_key,
					query_values => \@query_values,
					scheme_info  => $scheme_info
				}
			);
		}
		if ( $q->param('page') eq 'alleleQuery' ) {
			$self->_print_sequences_extended_fields( $headers, $extended_attributes, $data );
		} elsif ( $table eq 'sequence_bin' ) {
			$self->_print_seqbin_extended_fields( $extended_attributes, $data->{'id'} );
		}
		if ( $table_info->{'linked_data'} ) {
			my $field_values =
			  $self->{'datastore'}
			  ->get_client_data_linked_to_allele( $data->{'locus'}, $data->{'allele_id'}, { table_format => 1 } );
			print defined $field_values
			  ? qq(<td style="text-align:left">$field_values->{'formatted'}</td>)
			  : q(<td></td>);
		}
		if ( $self->_show_allele_flags ) {
			my $flags = $self->{'datastore'}->get_allele_flags( $data->{'locus'}, $data->{'allele_id'} );
			local $" = '</a> <a class="seqflag_tooltip">';
			print @$flags ? qq(<td><a class="seqflag_tooltip">@$flags</a></td>) : q(<td></td>);
		}
		say q(</tr>);
		$td = $td == 2 ? 1 : 2;
	}
	say q(</table></div>);
	if ( $table_info->{'user_variable_fields'} ) {
		say q(<p class="comment">* Default values are displayed for this field. )
		  . q(These may be overridden by user preference.</p>);
	}
	$self->_print_plugin_buttons( $qryref, $records ) if !$self->{'curate'};
	say q(</div>);
	return;
}

sub _print_seqbin_extended_fields {
	my ( $self, $extended_attributes, $seqbin_id ) = @_;
	my $seq_atts = $self->{'datastore'}->run_query( 'SELECT key,value FROM sequence_attribute_values WHERE seqbin_id=?',
		$seqbin_id, { fetch => 'all_arrayref', slice => {} } );
	my %ext_data;
	foreach my $data (@$seq_atts) {
		$ext_data{ $data->{'key'} } = $data->{'value'};
	}
	foreach (@$extended_attributes) {
		my $value = $ext_data{$_} // q();
		print qq(<td>$value</td>);
	}
	return;
}

sub _print_sequences_extended_fields {
	my ( $self, $headers, $extended_attributes, $data ) = @_;
	my %headers = map { $_ => 1 } @$headers;
	foreach my $attribute (@$extended_attributes) {
		my $value = $self->{'datastore'}->run_query(
			'SELECT value FROM sequence_extended_attributes WHERE (locus,field,allele_id)=(?,?,?)',
			[ $data->{'locus'}, $attribute->{'field'}, $data->{'allele_id'} ],
			{ cache => 'ResultsTablePage::print_record_table::alleleQuery_extatt' }
		);
		if ( defined $value ) {
			if ( $attribute->{'url'} ) {
				( my $url = $attribute->{'url'} ) =~ s/\[\?\]/$value/gx;
				$value = qq(<a href="$url">$value</a>);
			}
			print qq(<td>$value</td>);
		} else {
			print q(<td></td>);
		}
	}
	my @databanks = DATABANKS;
	foreach my $databank (sort @databanks) {
		if ( $headers{$databank} ) {
			my $accessions = $self->{'datastore'}->run_query(
				'SELECT databank,databank_id FROM accession WHERE (locus,allele_id,databank)=(?,?,?)',
				[ $data->{'locus'}, $data->{'allele_id'}, $databank ],
				{ fetch => 'all_arrayref', slice => {} }
			);
			my @values;
			if ( defined $accessions ) {
				foreach my $accession (@$accessions) {
					if ( $accession->{'databank'} eq 'ENA' ) {
						push @values,
						  qq(<a href="http://www.ebi.ac.uk/ena/data/view/$accession->{'databank_id'}">)
						  . qq($accession->{'databank_id'}</a>);
					} elsif ( $accession->{'databank'} eq 'Genbank' ) {
						push @values,
						  qq(<a href="https://www.ncbi.nlm.nih.gov/nuccore/$accession->{'databank_id'}">)
						  . qq($accession->{'databank_id'}</a>);
					} else {
						push @values, $accession->{'databank_id'};
					}
				}
			}
			local $" = '; ';
			print qq(<td>@values</td>);
		}
	}
	if ( $headers{'Publications'} ) {
		my $pmids = $self->{'datastore'}->run_query(
			'SELECT pubmed_id FROM sequence_refs WHERE (locus,allele_id)=(?,?)',
			[ $data->{'locus'}, $data->{'allele_id'} ],
			{
				fetch => 'col_arrayref'
			}
		);
		my @values;
		foreach my $pmid (@$pmids) {
			push @values, qq(<a href="https://www.ncbi.nlm.nih.gov/pubmed/$pmid">$pmid</a>);
		}
		local $" = '; ';
		print qq(<td>@values</td>);
	}
	return;
}

sub _print_record_field {
	my ( $self, $args ) = @_;
	my ( $table, $table_info, $data, $field, $primary_key, $query_values, $scheme_info ) =
	  @{$args}{qw(table table_info data field primary_key query_values scheme_info)};
	my $fields_to_query = {};
	my %user_field = map { $_ => 1 } qw(sender curator curator_id user_id);
	$data->{ lc($field) } //= '';
	if ( $primary_key->{$field} && !$self->{'curate'} ) {
		$self->_print_pk_field($args);
		return;
	}
	if ( $table_info->{'type'}->{$field} eq 'bool' ) {
		$self->_print_bool_field($args);
		return;
	}
	if ( ( $field =~ /sequence$/x || $field =~ /^primer/x ) && $field ne 'coding_sequence' ) {
		if ( length( $data->{ lc($field) } ) > 60 ) {
			my $full_seq = $data->{ lc($field) };
			my $seq = BIGSdb::Utils::truncate_seq( \$full_seq, 30 );
			print qq(<td class="seq">$seq</td>);
		} else {
			print qq(<td class="seq">$data->{lc($field)}</td>);
		}
		print q(<td>) . ( length $data->{'sequence'} ) . q(</td>) if $table eq 'sequences';
		return;
	}
	if ( $user_field{$field} ) {
		my $user_info = $self->{'datastore'}->get_user_info( $data->{ lc($field) } );
		print qq(<td>$user_info->{'first_name'} $user_info->{'surname'}</td>);
		return;
	}
	if ( $table_info->{'foreign_key'}->{$field} && $table_info->{'labels'}->{$field} ) {
		$self->_print_fk_field_with_label($args);
		return;
	}
	if ( $field eq 'pubmed_id' ) {
		print qq(<td>$data->{'pubmed_id'}</td>);
		my $citation =
		  $self->{'datastore'}
		  ->get_citation_hash( [ $data->{'pubmed_id'} ], { formatted => 1, no_title => 1, link_pubmed => 1 } );
		print qq(<td>$citation->{$data->{ 'pubmed_id'}}</td>);
		return;
	}
	if ( ( $table eq 'experiment_sequences' ) && $field eq 'seqbin_id' ) {
		my ( $isolate_id, $isolate ) = $self->get_isolate_id_and_name_from_seqbin_id( $data->{'seqbin_id'} );
		print qq[<td>$isolate_id) $isolate</td>];
	}
	if ( $field eq 'isolate_id' ) {
		my $isolate_name = $self->get_isolate_name_from_id( $data->{'isolate_id'} );
		print $isolate_name
		  ? qq[<td>$data->{'isolate_id'}) $isolate_name</td>]
		  : qq[<td>$data->{'isolate_id'}</td>];
	} else {
		my $value = $data->{ lc($field) };
		if ( !$self->{'curate'}
			&& ( ( $field eq 'locus' && $table ne 'set_loci' ) || ( $table eq 'loci' && $field eq 'id' ) ) )
		{
			$value = $self->clean_locus($value);
		} else {
			$value =~ s/&/&amp;/gx;
			if ( $table !~ /history/x ) {
				$value =~ s/>/&gt;/gx;
				$value =~ s/</&lt;/gx;
			}
		}
		print $field eq 'action' ? qq(<td style="text-align:left">$value</td>) : qq(<td>$value</td>);
	}
	return;
}

sub _print_bool_field {
	my ( $self, $args ) = @_;
	my ( $table, $data, $field ) = @{$args}{qw(table data field)};
	my $value = $data->{ lc($field) } ? TRUE : FALSE;
	print qq(<td>$value</td>);
	if ( $table eq 'allele_sequences' && $field eq 'complete' ) {
		my $flags = $self->{'datastore'}->get_sequence_flags( $data->{'id'} );
		local $" = q(</a> <a class="seqflag_tooltip">);
		print @$flags ? qq(<td><a class="seqflag_tooltip">@$flags</a></td>) : q(<td></td>);
	}
	return;
}

sub _print_fk_field_with_label {
	my ( $self, $args ) = @_;
	my ( $table, $table_info, $data, $field ) = @{$args}{qw(table table_info data field)};
	if ( !$self->{'cache'}->{'qry'}->{$field} ) {
		my @fields_to_query;
		my @values = split /\|/x, $table_info->{'labels'}->{$field};
		foreach (@values) {
			if ( $_ =~ /\$(.*)/x ) {
				push @fields_to_query, $1;
			}
		}
		$self->{'cache'}->{'fields_to_query'}->{$field} = \@fields_to_query;
		local $" = ',';
		$self->{'cache'}->{'qry'}->{$field} =
		  "SELECT @fields_to_query FROM $table_info->{'foreign_key'}->{$field} WHERE id=?";
	}
	my @labels = $self->{'datastore'}->run_query(
		$self->{'cache'}->{'qry'}->{$field},
		$data->{ lc($field) },
		{ cache => "ResultsTablePage::print_record_field::$field" }
	);
	my $value = $table_info->{'labels'}->{$field};
	my $i     = 0;
	foreach ( @{ $self->{'cache'}->{'fields_to_query'}->{$field} } ) {
		$value =~ s/\$$_/$labels[$i]/x;
		$i++;
	}
	$value =~ s/[\|\$]//gx;
	$value =~ s/&/\&amp;/gx;
	print qq(<td>$value</td>);
	return;
}

sub _print_pk_field {
	my ( $self, $args ) = @_;
	my ( $table, $field, $data, $query_values, $scheme_info ) = @{$args}{qw(table field data query_values scheme_info)};
	my $value;
	if ( $field eq 'isolate_id' ) {
		$value = $data->{ lc($field) } . ') ' . $self->get_isolate_name_from_id( $data->{ lc($field) } );
	} else {
		$value = $data->{ lc($field) };
	}
	$value = $self->clean_locus( $value, { strip_links => 1 } );
	my %methods = (
		sequences => sub {
			print qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=alleleInfo&amp;@$query_values">$value</a></td>);
		},
		history => sub {
			if ( $field eq 'isolate_id' ) {
				print qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=info&amp;id=$data->{'isolate_id'}">$value</a></td>);
			} else {
				$value =~ s/\..*$//x;    #Remove fractions of second from output
				print qq(<td>$value</td>);
			}
		},
		profile_history => sub {
			if ( $field eq 'profile_id' ) {
				print qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=profileInfo&amp;scheme_id=$data->{'scheme_id'}&amp;)
				  . qq(profile_id=$data->{'profile_id'}">$value</a></td>);
			} else {
				if ( $field eq 'timestamp' ) { $value =~ s/\..*$//x }
				elsif ( $field eq 'scheme_id' ) { $value = $scheme_info->{'name'} }
				print qq(<td>$value</td>);
			}
		},
		schemes => sub {
			print qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=schemeInfo&scheme_id=$data->{'id'}">$data->{'id'}</a></td>);
		},
		loci => sub {
			print qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=locusInfo&locus=$data->{'id'}">$data->{'id'}</a></td>);
		},
		scheme_fields => sub {
			if ( $field eq 'scheme_id' ) {
				$value = $scheme_info->{'name'};
			}
			print qq(<td>$value</td>);
		}
	);
	if ( $methods{$table} ) {
		$methods{$table}->();
	} else {
		print qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=recordInfo&amp;table=$table&amp;@$query_values">$value</a></td>);
	}
	return;
}

#This function requires that datastore->create_temp_ref_table has been
#run by the calling code.
sub _print_publication_table {
	my ( $self, $qryref, $page ) = @_;
	my $q        = $self->{'cgi'};
	my $pagesize = $self->{'prefs'}->{'displayrecs'};
	my $qry      = $$qryref;
	if ( $pagesize && $page ) {
		my $offset = ( $page - 1 ) * $pagesize;
		$qry =~ s/;/ LIMIT $pagesize OFFSET $offset;/x;
	}
	my $data = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	my $buffer;
	my $td = 1;
	foreach my $refdata (@$data) {
		my $author_filter = $q->param('author');
		next if ( $author_filter && $author_filter ne 'All authors' && $refdata->{'authors'} !~ /$author_filter/x );
		$refdata->{'year'} ||= '';
		$buffer .=
		    qq(<tr class="td$td">)
		  . qq(<td><a href="https://www.ncbi.nlm.nih.gov/pubmed/$refdata->{'pmid'}">$refdata->{'pmid'}</a></td>)
		  . qq(<td>$refdata->{'year'}</td><td style=\"text-align:left">);
		if ( !$refdata->{'authors'} && !$refdata->{'title'} ) {
			$buffer .= qq(No details available.</td>\n);
		} else {
			$buffer .= qq($refdata->{'authors'} );
			$buffer .= qq(($refdata->{'year'}) ) if $refdata->{'year'};
			$buffer .= qq($refdata->{'journal'} );
			$buffer .= qq(<b>$refdata->{'volume'}:</b> )
			  if $refdata->{'volume'};
			$buffer .= qq( $refdata->{'pages'}</td>\n);
		}
		$buffer .=
		  defined $refdata->{'title'} ? qq(<td style="text-align:left">$refdata->{'title'}</td>) : q(<td></td>);
		if ( defined $q->param('calling_page') && $q->param('calling_page') ne 'browse' && !$q->param('all_records') ) {
			$buffer .= qq(<td>$refdata->{'isolates'}</td>);
		}
		$buffer .= q(<td>) . $self->get_link_button_to_ref( $refdata->{'pmid'}, { class => 'submit' } ) . qq(</td>\n);
		$buffer .= qq(</tr>\n);
		$td = $td == 1 ? 2 : 1;
	}
	if ($buffer) {
		say q(<div class="box" id="resultstable">);
		say q(<div class="scrollable">);
		say q(<table class="resultstable"><thead>);
		say q(<tr><th>PubMed id</th><th>Year</th><th>Citation</th><th>Title</th>);
		say q(<th>Isolates in query</th>)
		  if defined $q->param('calling_page') && $q->param('calling_page') ne 'browse' && !$q->param('all_records');
		say q(<th>Isolates in database</th></tr></thead><tbody>);
		say $buffer;
		say q(</tbody></table></div></div>);
	} else {
		say q(<div class="box" id="resultsheader"><p>No PubMed records have been linked to isolates.</p></div>);
	}
	return;
}

sub _is_scheme_data_present {
	my ( $self, $qry, $scheme_id ) = @_;
	return $self->{'cache'}->{$qry}->{$scheme_id} if defined $self->{'cache'}->{$qry}->{$scheme_id};
	if ( !$self->{'cache'}->{$qry}->{'ids'} ) {
		$self->{'cache'}->{$qry}->{'ids'} = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	}
	my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	foreach my $isolate_id ( @{ $self->{'cache'}->{$qry}->{'ids'} } ) {

		#use Datastore::get_all_allele_designations rather than Datastore::get_all_allele_ids
		#because even though the latter is faster, the former will need to be called to display
		#the data in the table and the results can be cached.
		if ( !$self->{'designations_retrieved'}->{$isolate_id} ) {
			$self->{'designations'}->{$isolate_id} =
			  $self->{'datastore'}->get_all_allele_designations( $isolate_id, { show_ignored => $self->{'curate'} } );
			$self->{'designations_retrieved'}->{$isolate_id} = 1;
		}
		my $allele_designations = $self->{'designations'}->{$isolate_id};
		if ( !$self->{'sequences_retrieved'}->{$isolate_id} ) {
			$self->{'allele_sequences'}->{$isolate_id} =
			  $self->{'datastore'}->get_all_allele_sequences( $isolate_id, { keys => 'locus' } );
			$self->{'sequences_retrieved'}->{$isolate_id} = 1;
		}
		my $allele_seqs = $self->{'allele_sequences'}->{$isolate_id};
		foreach my $locus (@$scheme_loci) {

			#Don't count allele_id '0' if it is the only designation.
			if (
				(
					$allele_designations->{$locus}
					&& !( keys %{ $allele_designations->{$locus} } == 1 && $allele_designations->{$locus}->{'0'} )
				)
				|| $allele_seqs->{$locus}
			  )
			{
				$self->{'cache'}->{$qry}->{$scheme_id} = 1;
				return 1;
			}
		}
	}
	$self->{'cache'}->{$qry}->{$scheme_id} = 0;
	return 0;
}

sub _data_linked_to_locus {
	my ( $self, $locus ) = @_;
	return $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS (SELECT * FROM client_dbase_loci_fields WHERE locus=?)', $locus );
}

sub _initiate_urls_for_loci {
	my ($self) = @_;
	my $url_data =
	  $self->{'datastore'}->run_query( 'SELECT id,url FROM loci', undef, { fetch => 'all_arrayref', slice => {} } );
	foreach my $data (@$url_data) {
		( $self->{'url'}->{ $data->{'id'} } ) = $data->{'url'};
		$self->{'url'}->{ $data->{'id'} } =~ s/&/&amp;/gx if $data->{'url'};
	}
	$self->{'urls_defined'} = 1;
	return;
}

sub add_to_project {
	my ($self) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'isolates';
	my $q          = $self->{'cgi'};
	my $project_id = $q->param('project');
	return if !$project_id || !BIGSdb::Utils::is_int($project_id);
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $is_admin =
	  $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM project_users WHERE (project_id,user_id)=(?,?) AND admin)',
		[ $project_id, $user_info->{'id'} ] );
	if ( !$is_admin ) {
		$logger->error( "User $self->{'username'} attempted to add isolates to project "
			  . "$project_id for which they are not an admin." );
		return;
	}
	my $ids = $self->get_query_ids;
	my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $ids );
	my @restrict_clauses;
	my $project = $self->{'datastore'}->run_query( 'SELECT restrict_user,restrict_usergroup FROM projects WHERE id=?',
		$project_id, { fetch => 'row_hashref' } );
	if ( $project->{'restrict_user'} ) {
		push @restrict_clauses,
		  qq($temp_table.value IN (SELECT id FROM $self->{'system'}->{'view'} WHERE sender=$user_info->{'id'}));
	}
	if ( $project->{'restrict_usergroup'} ) {
		push @restrict_clauses,
		    qq[$temp_table.value IN (SELECT id FROM $self->{'system'}->{'view'} WHERE sender IN ]
		  . q[(SELECT user_id FROM user_group_members WHERE user_group IN ]
		  . qq[(SELECT user_group FROM user_group_members WHERE user_id=$user_info->{'id'})))];
	}
	local $" = ' OR ';
	my $restrict_clause =
	  @restrict_clauses
	  ? qq( AND (@restrict_clauses))
	  : q();
	my @msg;
	my $to_add = $self->{'datastore'}->run_query(
		"SELECT COUNT(value) FROM $temp_table WHERE value NOT IN(SELECT isolate_id "
		  . "FROM project_members WHERE project_id=?)$restrict_clause",
		$project_id
	);
	my $plural = $to_add == 1 ? q() : q(s);
	push @msg, "$to_add record$plural added";
	my $already_in = $self->{'datastore'}->run_query(
		"SELECT COUNT(value) FROM $temp_table WHERE value IN(SELECT isolate_id "
		  . 'FROM project_members WHERE project_id=?)',
		$project_id
	);
	$plural = $already_in == 1 ? q() : q(s);
	push @msg, "$already_in record$plural from this query already in project" if $already_in;
	local $" = q(; );
	my $message = qq(@msg.);
	eval {
		$self->{'db'}->do( 'INSERT INTO project_members (project_id,isolate_id,curator,datestamp) '
			  . "SELECT $project_id,value,$user_info->{'id'},'now' FROM $temp_table WHERE value NOT IN "
			  . "(SELECT isolate_id FROM project_members WHERE project_id=$project_id)$restrict_clause" );
	};

	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		$self->{'project_add_message'} = $message;
	}
	return;
}

sub confirm_publication {
	my ($self) = @_;
	say q(<h1>Confirm publication</h1>);
	say q(<div class="box" id="statusbad">);
	say q(<fieldset style="float:left"><legend>Warning</legend>);
	say q(<span class="warning_icon fas fa-exclamation-triangle fa-5x fa-pull-left"></span>);
	say q(<p>Please confirm that you wish to make these isolates public.</p>);
	say q(</fieldset>);
	my $q = $self->{'cgi'};
	say $q->start_form;
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Confirm' } );
	say $q->hidden( confirm_publish => 1 );
	say $q->hidden($_) foreach qw(db page query_file);
	say $q->end_form;
	my $query_file = $q->param('query_file');
	$self->print_navigation_bar(
		{
			back_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=query&amp;query_file=$query_file)
		}
	);
	say q(</div>);
	return;
}

sub publish {
	my ($self) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'isolates';
	my $q         = $self->{'cgi'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $matched;
	if ( $self->{'curate'} && $user_info->{'status'} ne 'submitter' ) {
		$matched = $self->_get_query_private_records;
	} else {
		$matched = $self->_get_query_private_records( $user_info->{'id'} );
	}
	my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $matched );
	my $request_only = $self->{'permissions'}->{'only_private'} || !$self->can_modify_table('isolates') ? 1 : 0;
	my $message;
	my $count = @$matched;
	my $plural = $count == 1 ? q() : q(s);
	my $qry;
	if (@$matched) {

		if ($request_only) {
			$qry =
			  "UPDATE private_isolates SET request_publish=TRUE WHERE isolate_id IN (SELECT value FROM $temp_table)";
			$message = "Publication requested for $count record$plural.";
		} else {
			$qry     = "DELETE FROM private_isolates WHERE isolate_id IN (SELECT value FROM $temp_table)";
			$message = "$count record$plural now public.";
		}
		eval { $self->{'db'}->do($qry); };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
			$self->{'publish_message'} = $message;
		}
	} else {
		$q->delete('publish');
	}
	return;
}

sub get_query_ids {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	return [] if !$q->param('query_file');
	my $qry  = $self->get_query_from_temp_file( scalar $q->param('query_file') );
	my $view = $self->{'system'}->{'view'};
	$qry =~ s/ORDER\ BY.*$//gx;
	$qry =~ s/SELECT\ \*/SELECT $view.id/x;
	$self->create_temp_tables( \$qry );

	if ( $q->param('list_file') && $q->param('datatype') ) {
		$self->{'datastore'}->create_temp_list_table( scalar $q->param('datatype'), scalar $q->param('list_file') );
	}
	my $ids = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	return $ids;
}
1;
