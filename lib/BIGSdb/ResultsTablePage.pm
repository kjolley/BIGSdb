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
package BIGSdb::ResultsTablePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Error qw(:try);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub paged_display {

	# $count is optional - if not provided it will be calculated, but this may not be the most
	# efficient algorithm, so if it has already been calculated prior to passing to this subroutine
	# it is better to not recalculate it.
	my ($self, $args) = @_;
	my ( $table, $qry, $message, $hidden_attributes, $count, $passed_qry_file ) =
	  @{$args}{qw (table query message hidden_attributes count passed_qry_file)};
	my $passed_qry;
	if ($passed_qry_file) {
		$passed_qry = $self->get_query_from_temp_file($passed_qry_file);
	} else {

		#query can get rewritten on route to this page - this enables the original query to be passed on
		$passed_qry_file = $self->make_temp_file($qry);
		$passed_qry      = $qry;
	}
	if ( $table eq 'allele_sequences' && $passed_qry =~ /sequence_flags/ ) {
		$self->{'db'}->do("SET enable_nestloop = off");
	}
	my $schemes  = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
	my $continue = 1;
	try {
		foreach (@$schemes) {
			if ( $qry =~ /temp_scheme_$_\s/ || $qry =~ /ORDER BY s_$_\_/ ) {
				$self->{'datastore'}->create_temp_scheme_table($_);
				$self->{'datastore'}->create_temp_isolate_scheme_table($_);
			}
		}
	}
	catch BIGSdb::DatabaseConnectionException with {
		print "<div class=\"box\" id=\"statusbad\"><p>Can not connect to remote database.  The query can not be performed.</p></div>\n";
		$logger->error("Can't create temporary table");
		$continue = 0;
	};
	return if !$continue;
	my $q = $self->{'cgi'};
	$message = $q->param('message') if !$message;

	#sort allele_id integers numerically
	$qry =~
s/ORDER BY (.+),\s*\S+\.allele_id(.*)/ORDER BY $1,\(case when $table.allele_id ~ '^[0-9]+\$' THEN lpad\($table.allele_id,10,'0'\) else $table.allele_id end\)$2/;
	$qry =~
s/ORDER BY \S+\.allele_id(.*)/ORDER BY \(case when $table.allele_id ~ '^[0-9]+\$' THEN lpad\($table.allele_id,10,'0'\) else $table.allele_id end\)$1/;
	my $totalpages = 1;
	my $bar_buffer;
	if ( $q->param('displayrecs') ) {
		$self->{'prefs'}->{'displayrecs'} = $q->param('displayrecs') eq 'all' ? 0 : $q->param('displayrecs');
	}
	my $currentpage = $q->param('currentpage') ? $q->param('currentpage') : 1;
	if    ( $q->param('>') )        { $currentpage++ }
	elsif ( $q->param('<') )        { $currentpage-- }
	elsif ( $q->param('pagejump') ) { $currentpage = $q->param('pagejump') }
	elsif ( $q->param('Last') )     { $currentpage = $q->param('lastpage') }
	elsif ( $q->param('First') )    { $currentpage = 1 }
	my $records;

	if ($count) {
		$records = $count;
	} else {
		my $qrycount = $qry;
		if ( $table eq 'allele_sequences' ) {

			#PK is seqbin_id, locus, start_pos, end_pos but you need to search for distinct combinations (not just COUNT(*)) because the
			#query may join the sequence_flags table giving more rows than allele sequences.
			$qrycount =~
s/SELECT \*/SELECT COUNT \(DISTINCT allele_sequences.seqbin_id||allele_sequences.locus||allele_sequences.start_pos||allele_sequences.end_pos\)/;
		}
		$qrycount =~ s/SELECT \*/SELECT COUNT \(\*\)/;
		$qrycount =~ s/ORDER BY.*//;
		$records = $self->{'datastore'}->run_simple_query($qrycount)->[0];
	}
	$q->param( 'query_file',  $passed_qry_file );
	$q->param( 'currentpage', $currentpage );
	$q->param( 'displayrecs', $self->{'prefs'}->{'displayrecs'} );
	if ( $self->{'prefs'}->{'displayrecs'} > 0 ) {
		$totalpages = $records / $self->{'prefs'}->{'displayrecs'};
	} else {
		$totalpages = 1;
		$self->{'prefs'}->{'displayrecs'} = 0;
	}
	$bar_buffer .= $q->start_form;
	$q->param( 'table', $table );
	$bar_buffer .= $q->hidden($_) foreach qw (query_file currentpage page db displayrecs order table direction sent);
	$bar_buffer .= $q->hidden( 'message', $message ) if $message;

	#Make sure hidden_attributes don't duplicate the above
	$bar_buffer .= $q->hidden($_) foreach @$hidden_attributes;
	if ( $currentpage > 1 || $currentpage < $totalpages ) {
		$bar_buffer .= "<table>\n<tr><td>Page:</td>\n";
		if ( $currentpage > 1 ) {
			$bar_buffer .= "<td>";
			$bar_buffer .= $q->submit( -name => 'First', -class => 'pagebar' );
			$bar_buffer .= "</td><td>";
			$bar_buffer .= $q->submit( -name => $currentpage == 2 ? 'First' : '<', -label => ' < ', -class => 'pagebar' );
			$bar_buffer .= "</td>";
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
			$bar_buffer .= "<td>";
			for ( my $i = $first ; $i < $last + 1 ; $i++ ) {    #don't use range operator as $last may not be an integer.
				if ( $i == $currentpage ) {
					$bar_buffer .= "</td><th class=\"pagebar_selected\">$i</th><td>";
				} else {
					$bar_buffer .=
					  $q->submit( -name => $i == 1 ? 'First' : 'pagejump', -value => $i, -label => " $i ", -class => 'pagebar' );
				}
			}
			$bar_buffer .= "</td>\n";
		}
		if ( $currentpage < $totalpages ) {
			$bar_buffer .= "<td>";
			$bar_buffer .= $q->submit( -name => '>', -label => ' > ', -class => 'pagebar' );
			$bar_buffer .= "</td><td>";
			my $lastpage;
			if ( BIGSdb::Utils::is_int($totalpages) ) {
				$lastpage = $totalpages;
			} else {
				$lastpage = int $totalpages + 1;
			}
			$q->param( 'lastpage', $lastpage );
			$bar_buffer .= $q->hidden('lastpage');
			$bar_buffer .= $q->submit( -name => 'Last', -class => 'pagebar' );
			$bar_buffer .= "</td>";
		}
		$bar_buffer .= "</tr></table>\n";
		$bar_buffer .= $q->endform;
	}
	print "<div class=\"box\" id=\"resultsheader\">\n";
	if ($records) {
		print "<p>$message</p>" if $message;
		my $plural = $records == 1 ? '' : 's';
		print "<p>$records record$plural returned";
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
			print " Click the hyperlink$plural for detailed information.";
		}
		print "</p>\n";
		$self->_print_curate_headerbar_functions( $table, $passed_qry_file ) if $self->{'curate'};
		$self->print_additional_headerbar_functions($passed_qry_file);
	} else {
		$logger->debug("Query: $qry");
		print "<p>No records found!</p>\n";
	}
	if ( $self->{'prefs'}->{'pagebar'} =~ /top/
		&& ( $currentpage > 1 || $currentpage < $totalpages ) )
	{
		print $bar_buffer;
	}
	print "</div>\n";
	return if !$records;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) {
		$self->_print_isolate_table( \$qry, $currentpage, $q->param('curate'), $records );
	} elsif ( $table eq 'profiles' ) {
		$self->_print_profile_table( \$qry, $currentpage, $q->param('curate'), $records );
	} elsif ( !$self->{'curate'} && $table eq 'refs' ) {
		$self->_print_publication_table( \$qry, $currentpage );
	} else {
		$self->_print_record_table( $table, \$qry, $currentpage, $records );
	}
	if (   $self->{'prefs'}->{'displayrecs'}
		&& $self->{'prefs'}->{'pagebar'} =~ /bottom/
		&& ( $currentpage > 1 || $currentpage < $totalpages ) )
	{
		print "<div class=\"box\" id=\"resultsfooter\">$bar_buffer</div>\n";
	}
	return;
}

sub _print_curate_headerbar_functions {
	my ( $self, $table, $qry_filename ) = @_;
	my $q    = $self->{'cgi'};
	my $page = $q->param('page');
	if ( $self->can_modify_table($table) ) {
		$self->_print_delete_all_function($table);
		$self->_print_link_seq_to_experiment_function if $table eq 'sequence_bin';
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
			$self->_print_access_control_function;
		}
		$self->_print_export_configuration_function($table);
		if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' && $table eq 'sequences' && $self->can_modify_table('sequences') ) {
			$self->_print_set_sequence_flags_function;
		}
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) {
		$self->_print_tag_scanning_function           if $self->can_modify_table('allele_sequences');
		$self->_print_modify_project_members_function if $self->can_modify_table('project_members');
	}
	$q->param( page => $page );    #reset
	return;
}

sub print_additional_headerbar_functions {

	#Override in subclass
}

sub _print_delete_all_function {
	my ( $self, $table ) = @_;
	my $q = $self->{'cgi'};
	print "<fieldset><legend>Delete</legend>\n";
	print $q->start_form;
	$q->param( 'page', 'deleteAll' );
	print $q->hidden($_) foreach qw (db page table query_file scheme_id);
	if ( $table eq 'allele_designations' ) {
		print "<ul><li>\n";
		if ( $self->can_modify_table('allele_sequences') ) {
			print $q->checkbox( -name => 'delete_tags', -label => 'Delete corresponding sequence tags' );
			print "</li>\n<li>\n";
		}
		print $q->checkbox( -name => 'delete_pending', -label => 'Delete corresponding pending designations' );
		print "</li></ul>\n";
	}
	print $q->submit( -name => 'Delete ALL', -class => 'submit' );
	print $q->end_form;
	print "</fieldset>";
	return;
}

sub _print_link_seq_to_experiment_function {
	my ($self)      = @_;
	my $q           = $self->{'cgi'};
	my $experiments = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM experiments")->[0];
	if ($experiments) {
		print "<fieldset><legend>Experiments</legend>\n";
		print $q->start_form;
		$q->param( 'page', 'linkToExperiment' );
		print $q->hidden($_) foreach qw (db page query_file);
		print $q->submit( -name => 'Link to experiment', -class => 'submit' );
		print $q->end_form;
		print "</fieldset>";
	}
	return;
}

sub _print_access_control_function {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $self->{'system'}->{'read_access'} eq 'acl' && $self->can_modify_table('isolate_user_acl') ) {
		print "<fieldset><legend>Access control</legend>\n";
		print $q->start_form;
		$q->param( 'page', 'isolateACL' );
		print $q->hidden($_) foreach qw (db page table query_file);
		print $q->submit( -name => 'Modify access', -class => 'submit' );
		print $q->end_form;
		print "</fieldset>";
	}
	return;
}

sub _print_export_configuration_function {
	my ( $self, $table ) = @_;
	my $q = $self->{'cgi'};
	if (
		any { $table eq $_ }
		qw (schemes users user_groups user_group_members user_permissions projects project_members isolate_aliases
		accession experiments experiment_sequences allele_sequences samples loci locus_aliases pcr probes isolate_field_extended_attributes
		isolate_value_extended_attributes scheme_fields scheme_members scheme_groups scheme_group_scheme_members scheme_group_group_members
		locus_descriptions scheme_curators locus_curators sequences sequence_refs profile_refs locus_extended_attributes client_dbases
		client_dbase_loci client_dbase_schemes)
	  )
	{
		print "<fieldset><legend>Database configuration</legend>\n";
		print $q->start_form;
		$q->param( 'page', 'exportConfig' );
		print $q->hidden($_) foreach qw (db page table query_file);
		print $q->submit( -name => 'Export configuration/data', -class => 'submit' );
		print $q->end_form;
		print "</fieldset>\n";
	}
	return;
}

sub _print_tag_scanning_function {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<fieldset style=\"text-align:center\"><legend>Tag scanning</legend>\n";
	print $q->start_form;
	$q->param( 'page', 'tagScan' );
	print $q->hidden($_) foreach qw (db page table query_file);
	print $q->submit( -name => 'Scan', -class => 'submit' );
	print $q->end_form;
	print "</fieldset>\n";
	return;
}

sub _print_modify_project_members_function {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my @projects;
	my $project_qry = "SELECT id,short_description FROM projects ORDER BY short_description";
	my $sql         = $self->{'db'}->prepare($project_qry);
	eval { $sql->execute };
	$logger->error($@) if $@;
	my %labels;

	while ( my @data = $sql->fetchrow_array ) {
		push @projects, $data[0];
		$labels{ $data[0] } = $data[1];
	}
	if (@projects) {
		print "<fieldset><legend>Projects</legend>\n";
		unshift @projects, '';
		$labels{''} = "Select project...";
		print $q->start_form;
		$q->param( 'page',  'batchAdd' );
		$q->param( 'table', 'project_members' );
		print $q->hidden($_) foreach qw (db page table query_file);
		print $q->popup_menu( -name => 'project', -values => \@projects, -labels => \%labels );
		print $q->submit( -name => 'Link', -class => 'submit' );
		print $q->end_form;
		print "</fieldset>\n";
	}
	return;
}

sub _print_set_sequence_flags_function {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<fieldset><legend>Flags</legend>\n";
	print $q->start_form;
	$q->param( page => 'setAlleleFlags' );
	print $q->hidden($_) foreach qw (db page query_file);
	print $q->submit( -name => 'Batch set', -class => 'submit' );
	print $q->end_form;
	print "</fieldset>\n";
	return;
}

sub _print_isolate_table {
	my ( $self, $qryref, $page, $records ) = @_;
	my $pagesize  = $self->{'prefs'}->{'displayrecs'};
	my $logger    = get_logger('BIGSdb.Page');
	my $q         = $self->{'cgi'};
	my $qry       = $$qryref;
	my $qry_limit = $qry;
	my $fields    = $self->{'xmlHandler'}->get_field_list;
	my $view      = $self->{'system'}->{'view'};
	local $" = ",$view.";
	my $field_string = "$view.@$fields";
	$qry_limit =~ s/SELECT ($view\.\*|\*)/SELECT $field_string/;

	if ( $pagesize && $page ) {
		my $offset = ( $page - 1 ) * $pagesize;
		$qry_limit =~ s/;\s*$/ LIMIT $pagesize OFFSET $offset;/;
	}
	if ( any { lc($qry) =~ /;\s*$_\s/ } (qw (insert delete update alter create drop)) ) {
		$logger->warn("Malicious SQL injection attempt '$qry'");
		return;
	}
	$logger->debug("Passed query: $qry");
	my ( $sql, $limit_sql );
	$self->rewrite_query_ref_order_by( \$qry_limit );
	$limit_sql = $self->{'db'}->prepare($qry_limit);
	$logger->debug("Limit qry: $qry_limit");
	eval { $limit_sql->execute };
	if ($@) {
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid search performed</p></div>\n";
		$logger->warn("Can't execute query $qry_limit  $@");
		return;
	}
	my %data = ();
	$limit_sql->bind_columns( map { \$data{$_} } @$fields );    #quicker binding hash to arrayref than to use hashref
	my ( %composites, %composite_display_pos );
	$qry = "SELECT id,position_after FROM composite_fields";
	$sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	if ($@) {
		$logger->error("Can't execute $qry $@");
	} else {
		while ( my @data = $sql->fetchrow_array ) {
			$composite_display_pos{ $data[0] } = $data[1];
			$composites{ $data[1] }            = 1;
		}
	}
	my $set_id = $self->get_set_id;
	my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	print "<div class=\"box\" id=\"resultstable\"><div class=\"scrollable\"><table class=\"resultstable\">\n";
	$self->_print_isolate_table_header( \%composites, \%composite_display_pos, $schemes, $qry_limit );
	my $td = 1;
	local $" = "=? AND ";
	my $field_attributes;
	$field_attributes->{$_} = $self->{'xmlHandler'}->get_field_attributes($_) foreach (@$fields);
	my $extended = $self->get_extended_attributes;
	my $attribute_sql =
	  $self->{'db'}->prepare("SELECT value FROM isolate_value_extended_attributes WHERE isolate_field=? AND attribute=? AND field_value=?");
	$self->{'scheme_loci'}->{0} = $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
	local $| = 1;

	while ( $limit_sql->fetchrow_arrayref ) {
		my $profcomplete = 1;
		my $id;
		print "<tr class=\"td$td\">";
		foreach my $thisfieldname (@$field_list) {
			$data{$thisfieldname} = '' if !defined $data{$thisfieldname};
			$data{$thisfieldname} =~ tr/\n/ /;
			if (   $self->{'prefs'}->{'maindisplayfields'}->{$thisfieldname}
				|| $thisfieldname eq 'id' )
			{
				if ( $thisfieldname eq 'id' ) {
					$id = $data{$thisfieldname};
					$id =~ s/ /\%20/g;
					$id =~ s/\+/\%2B/g;
					if ( $self->{'curate'} ) {
						print "<td><a href=\""
						  . $q->script_name
						  . "?db=$self->{'instance'}&amp;page=isolateDelete&amp;id=$id\">Delete</a></td><td><a href=\""
						  . $q->script_name
						  . "?db=$self->{'instance'}&amp;page=isolateUpdate&amp;id=$id\">Update</a></td>";
						if ( $self->can_modify_table('sequence_bin') ) {
							print "<td><a href=\""
							  . $q->script_name
							  . "?db=$self->{'instance'}&amp;page=batchAddSeqbin&amp;isolate_id=$id\">Upload</a></td>";
						}
						if ( $self->{'system'}->{'read_access'} eq 'acl' && $self->{'permissions'}->{'modify_isolates_acl'} ) {
							print "<td><a href=\""
							  . $q->script_name
							  . "?db=$self->{'instance'}&amp;page=isolateACL&amp;id=$id\">Modify</a></td>";
						}
					}
					print
"<td><a href=\"$self->{'system'}->{'script_name'}?page=info&amp;db=$self->{'instance'}&amp;id=$id\">$data{$thisfieldname}</a></td>";
				} elsif ( $data{$thisfieldname} eq '-999'
					|| $data{$thisfieldname} eq '0001-01-01' )
				{
					print "<td>.</td>";
				} elsif (
					$thisfieldname eq 'sender'
					|| $thisfieldname eq 'curator'
					|| (   $field_attributes->{'thisfieldname'}->{'userfield'}
						&& $field_attributes->{'thisfieldname'}->{'userfield'} eq 'yes' )
				  )
				{
					my $user_info = $self->{'datastore'}->get_user_info( $data{$thisfieldname} );
					print "<td>$user_info->{'first_name'} $user_info->{'surname'}</td>";
				} else {
					if ( $thisfieldname =~ /^meta_[^:]+:/ ) {
						my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($thisfieldname);
						my $value = $self->{'datastore'}->get_metadata_value( $id, $metaset, $metafield );
						print "<td>$value</td>";
					} else {
						print "<td>$data{$thisfieldname}</td>";
					}
				}
			}
			my $extatt = $extended->{$thisfieldname};
			if ( ref $extatt eq 'ARRAY' ) {
				foreach my $extended_attribute (@$extatt) {
					if ( $self->{'prefs'}->{'maindisplayfields'}->{"$thisfieldname\..$extended_attribute"} ) {
						eval { $attribute_sql->execute( $thisfieldname, $extended_attribute, $data{$thisfieldname} ) };
						$logger->error($@) if $@;
						my ($value) = $attribute_sql->fetchrow_array;
						print defined $value ? "<td>$value</td>" : '<td></td>';
					}
				}
			}
			if ( $composites{$thisfieldname} ) {
				foreach ( keys %composite_display_pos ) {
					next if $composite_display_pos{$_} ne $thisfieldname;
					if ( $self->{'prefs'}->{'maindisplayfields'}->{$_} ) {
						my $value = $self->{'datastore'}->get_composite_value( $id, $_, \%data );
						print defined $value ? "<td>$value</td>" : '<td></td>';
					}
				}
			}
			if ( $thisfieldname eq $self->{'system'}->{'labelfield'} && $self->{'prefs'}->{'maindisplayfields'}->{'aliases'} ) {
				my $aliases =
				  $self->{'datastore'}->run_list_query( "SELECT alias FROM isolate_aliases WHERE isolate_id=? ORDER BY alias", $id );
				local $" = '; ';
				print "<td>@$aliases</td>";
			}
		}
		if ( $self->{'prefs'}->{'display_seqbin_main'} ) {
			my $size = $self->_get_seqbin_size($id);
			print "<td>$size</td>";
		}

		#Print loci and scheme fields
		my @scheme_ids;
		push @scheme_ids, $_->{'id'} foreach (@$schemes);
		foreach my $scheme_id ( @scheme_ids, 0 ) {
			next
			  if !$self->{'prefs'}->{'main_display_schemes'}->{$scheme_id} && $scheme_id;
			next
			  if ( $self->{'system'}->{'hide_unused_schemes'} // '' ) eq 'yes'
			  && !$self->{'cache'}->{'scheme_data_present'}->{$scheme_id}
			  && $scheme_id;
			$self->_print_isolate_table_scheme( $id, $scheme_id );
		}
		print "</tr>\n";
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
	print "</table></div>\n";
	$self->_print_plugin_buttons($records) if !$self->{'curate'};
	print "</div>\n";
	$sql->finish if $sql;
	return;
}

sub _get_seqbin_size {
	my ( $self, $isolate_id ) = @_;
	if ( !$self->{'sql'}->{'seqbin_size'} ) {
		$self->{'sql'}->{'seqbin_size'} = $self->{'db'}->prepare("SELECT SUM(length(sequence)) FROM sequence_bin WHERE isolate_id=?");
	}
	eval { $self->{'sql'}->{'seqbin_size'}->execute($isolate_id); };
	$logger->error($@) if $@;
	my ($size) = $self->{'sql'}->{'seqbin_size'}->fetchrow_array // 0;
	return $size;
}

sub _print_isolate_table_header {
	my ( $self, $composites, $composite_display_pos, $schemes, $limit_qry ) = @_;
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $select_items  = $self->{'xmlHandler'}->get_field_list($metadata_list);
	my $header_buffer = "<tr>";
	my $col_count;
	my $extended = $self->get_extended_attributes;
	foreach my $col (@$select_items) {

		if (   $self->{'prefs'}->{'maindisplayfields'}->{$col}
			|| $col eq 'id' )
		{
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($col);
			( my $display_col = $metafield // $col ) =~ tr/_/ /;
			$header_buffer .= "<th>$display_col</th>";
			$col_count++;
		}
		if ( $composites->{$col} ) {
			foreach ( keys %$composite_display_pos ) {
				next if $composite_display_pos->{$_} ne $col;
				if ( $self->{'prefs'}->{'maindisplayfields'}->{$_} ) {
					my $displayfield = $_;
					$displayfield =~ tr/_/ /;
					$header_buffer .= "<th>$displayfield</th>";
					$col_count++;
				}
			}
		}
		if ( $col eq $self->{'system'}->{'labelfield'} && $self->{'prefs'}->{'maindisplayfields'}->{'aliases'} ) {
			$header_buffer .= "<th>aliases</th>";
			$col_count++;
		}
		my $extatt = $extended->{$col};
		if ( ref $extatt eq 'ARRAY' ) {
			foreach my $extended_attribute (@$extatt) {
				if ( $self->{'prefs'}->{'maindisplayfields'}->{"$col\..$extended_attribute"} ) {
					$header_buffer .= "<th>$col\..$extended_attribute</th>";
					$col_count++;
				}
			}
		}
	}
	my $fieldtype_header = "<tr>";
	if ( $self->{'curate'} ) {
		$fieldtype_header .= "<th rowspan=\"2\">Delete</th><th rowspan=\"2\">Update</th>";
		if ( $self->can_modify_table('sequence_bin') ) {
			$fieldtype_header .= "<th rowspan=\"2\">Sequence bin</th>";
		}
		if ( $self->{'system'}->{'read_access'} eq 'acl' && $self->{'permissions'}->{'modify_isolates_acl'} ) {
			$fieldtype_header .= "<th rowspan=\"2\">Access control</th>";
		}
	}
	$fieldtype_header .= "<th colspan=\"$col_count\">Isolate fields";
	$fieldtype_header .= " <a class=\"tooltip\" title=\"Isolate fields - You can select the isolate fields that are displayed here "
	  . "by going to the options page.\">&nbsp;<i>i</i>&nbsp;</a>";
	$fieldtype_header .= "</th>";
	$fieldtype_header .= "<th rowspan=\"2\">Seqbin size (bp)</th>" if $self->{'prefs'}->{'display_seqbin_main'};
	my $alias_sql = $self->{'db'}->prepare("SELECT alias FROM locus_aliases WHERE locus=?");
	$logger->error($@) if $@;
	local $" = '; ';

	foreach my $scheme (@$schemes) {
		my $scheme_id = $scheme->{'id'};
		next if !$self->{'prefs'}->{'main_display_schemes'}->{$scheme_id};
		if ( $scheme_id && !defined $self->{'cache'}->{'scheme_data_present'}->{$scheme_id} ) {
			$self->{'cache'}->{'scheme_data_present'}->{$scheme_id} = $self->_is_scheme_data_present( $limit_qry, $scheme_id );
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
				my @aliases;
				if ( $self->{'prefs'}->{'locus_alias'} ) {
					eval { $alias_sql->execute($_) };
					if ($@) {
						$logger->error("Can't execute alias check $@");
					} else {
						while ( my ($alias) = $alias_sql->fetchrow_array ) {
							push @aliases, $alias;
						}
					}
					local $" = ', ';
					$locus_header .= " <span class=\"comment\">(@aliases)</span>" if @aliases;
				}
				push @scheme_header, $locus_header;
			}
		}
		if ( !$self->{'scheme_fields'}->{$scheme_id} ) {
			$self->{'scheme_fields'}->{$scheme_id} = $self->{'datastore'}->get_scheme_fields($scheme_id);
		}
		if ( ref $self->{'scheme_fields'}->{$scheme_id} eq 'ARRAY' ) {
			foreach ( @{ $self->{'scheme_fields'}->{$scheme_id} } ) {
				if ( $self->{'prefs'}->{'main_display_scheme_fields'}->{$scheme_id}->{$_} ) {
					my $field = $_;
					$field =~ tr/_/ /;
					push @scheme_header, $field;
				}
			}
		}
		if ( scalar @scheme_header ) {
			$fieldtype_header .= "<th colspan=\"" . scalar @scheme_header . "\">$scheme->{'description'}</th>";
		}
		local $" = '</th><th>';
		$header_buffer .= "<th>@scheme_header</th>" if @scheme_header;
	}
	my @locus_header;
	my $loci = $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
	foreach (@$loci) {
		if ( $self->{'prefs'}->{'main_display_loci'}->{$_} ) {
			my @aliases;
			if ( $self->{'prefs'}->{'locus_alias'} ) {
				eval { $alias_sql->execute($_); };
				if ($@) {
					$logger->error("Can't execute alias check $@");
				} else {
					while ( my ($alias) = $alias_sql->fetchrow_array ) {
						$alias = $self->clean_locus($alias);
						push @aliases, $alias;
					}
				}
			}
			my $cleaned_locus = $self->clean_locus($_);
			local $" = ', ';
			push @locus_header, "$cleaned_locus" . ( @aliases ? " <span class=\"comment\">(@aliases)</span>" : '' );
		}
	}
	if (@locus_header) {
		$fieldtype_header .= "<th colspan=\"" . scalar @locus_header . "\">Loci</th>";
	}
	local $" = '</th><th>';
	$header_buffer .= "<th>@locus_header</th>" if @locus_header;
	$fieldtype_header .= "</tr>\n";
	$header_buffer    .= "</tr>\n";
	print $fieldtype_header;
	print $header_buffer;
	return;
}

sub _print_isolate_table_scheme {
	my ( $self, $isolate_id, $scheme_id ) = @_;
	if ( !$self->{'scheme_fields'}->{$scheme_id} ) {
		$self->{'scheme_fields'}->{$scheme_id} = $self->{'datastore'}->get_scheme_fields($scheme_id);
	}
	if ( !$self->{'scheme_info'}->{$scheme_id} ) {
		$self->{'scheme_info'}->{$scheme_id} = $self->{'datastore'}->get_scheme_info($scheme_id);
	}
	my ( @profile, $incomplete );
	if ( !$self->{'urls_defined'} && $self->{'prefs'}->{'hyperlink_loci'} ) {
		$self->_initiate_urls_for_loci;
	}
	if ( !$self->{'designations_retrieved'}->{$isolate_id} ) {
		$self->{'designations'}->{$isolate_id}           = $self->{'datastore'}->get_all_allele_designations($isolate_id);
		$self->{'designations_retrieved'}->{$isolate_id} = 1;
	}
	my $allele_designations = $self->{'designations'}->{$isolate_id};
	my %provisional_allele;
	my $loci = $self->{'scheme_loci'}->{$scheme_id};
	foreach my $locus (@$loci) {
		$allele_designations->{$locus}->{'status'} ||= 'confirmed';
		$provisional_allele{$locus} = 1
		  if $self->{'prefs'}->{'mark_provisional_main'} && $allele_designations->{$locus}->{'status'} eq 'provisional';
		next if !$self->{'prefs'}->{'main_display_loci'}->{$locus} && ( !$scheme_id || !@{ $self->{'scheme_fields'}->{$scheme_id} } );
		if ( $self->{'prefs'}->{'main_display_loci'}->{$locus} ) {
			print "<td>";
			print "<span class=\"provisional\">"
			  if $allele_designations->{$locus}->{'status'} eq 'provisional'
			  && $self->{'prefs'}->{'mark_provisional_main'};
			if (   defined $allele_designations->{$locus}->{'allele_id'}
				&& defined $self->{'url'}->{$locus}
				&& $self->{'url'}->{$locus} ne ''
				&& $self->{'prefs'}->{'main_display_loci'}->{$locus}
				&& $self->{'prefs'}->{'hyperlink_loci'} )
			{
				my $url = $self->{'url'}->{$locus};
				$url =~ s/\[\?\]/$allele_designations->{$locus}->{'allele_id'}/g;
				print "<a href=\"$url\">$allele_designations->{$locus}->{'allele_id'}</a>";
			} else {
				print defined $allele_designations->{$locus}->{'allele_id'} ? $allele_designations->{$locus}->{'allele_id'} : '';
			}
			print "</span>"
			  if $allele_designations->{$locus}->{'status'} eq 'provisional'
			  && $self->{'prefs'}->{'mark_provisional_main'};
			print $self->get_seq_detail_tooltips( $isolate_id, $locus ) if $self->{'prefs'}->{'sequence_details_main'};
			$self->_print_pending_tooltip( $isolate_id, $locus )
			  if $self->{'prefs'}->{'display_pending_main'} && defined $allele_designations->{$locus}->{'allele_id'};
			my $action = exists $allele_designations->{$locus}->{'allele_id'} ? 'update' : 'add';
			print
" <a href=\"$self->{'system'}->{'script_name'}?page=alleleUpdate&amp;db=$self->{'instance'}&amp;isolate_id=$isolate_id&amp;locus=$locus\" class=\"update\">$action</a>"
			  if $self->{'curate'};
			print "</td>";
		}
		if ($scheme_id) {
			push @profile, $allele_designations->{$locus}->{'allele_id'};
			$incomplete = 1 if !defined $allele_designations->{$locus}->{'allele_id'};
		}
	}
	return
	     if !$scheme_id
	  || !@{ $self->{'scheme_fields'}->{$scheme_id} }
	  || !$self->{'prefs'}->{'main_display_schemes'}->{$scheme_id};
	my $values;
	if ( ( !$incomplete || $self->{'scheme_info'}->{$scheme_id}->{'allow_missing_loci'} ) && @profile ) {
		$values = $self->{'datastore'}->get_scheme_field_values_by_profile( $scheme_id, \@profile );
	}
	my $scheme_fields = $self->{'scheme_fields'}->{$scheme_id};
	my $provisional_profile = $self->{'datastore'}->is_profile_provisional( $scheme_id, \@profile, \%provisional_allele );
	foreach my $field (@$scheme_fields) {
		if ( $self->{'prefs'}->{'main_display_scheme_fields'}->{$scheme_id}->{$field} ) {
			if ( ref $values eq 'HASH' ) {
				$values->{ lc($field) } = '' if !defined $values->{ lc($field) };
				if ( !$self->{'scheme_fields_info'}->{$scheme_id}->{$field} ) {
					$self->{'scheme_fields_info'}->{$scheme_id}->{$field} =
					  $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
				}
				my $url;
				if (   $self->{'prefs'}->{'hyperlink_loci'}
					&& $self->{'scheme_fields_info'}->{$scheme_id}->{$field}->{'url'} )
				{
					$url = $self->{'scheme_fields_info'}->{$scheme_id}->{$field}->{'url'};
					$url =~ s/\[\?\]/$values->{lc($field)}/g;
					$url =~ s/\&/\&amp;/g;
				}
				if ( $values->{ lc($field) } eq '-999' ) {
					$values->{ lc($field) } = '';
				}
				if ( defined $values->{ lc($field) } && $values->{ lc($field) } ne '' ) {
					print $provisional_profile ? "<td><span class=\"provisional\">"           : '<td>';
					print $url                 ? "<a href=\"$url\">$values->{lc($field)}</a>" : $values->{ lc($field) };
					print $provisional_profile ? '</span></td>'                               : '</td>';
				} else {
					print '<td></td>';
				}
			} else {
				print "<td></td>";
			}
		}
	}
	return;
}

sub _print_profile_table {
	my ( $self, $qryref, $page, $records ) = @_;
	my $pagesize  = $self->{'prefs'}->{'displayrecs'};
	my $logger    = get_logger('BIGSdb.Page');
	my $q         = $self->{'cgi'};
	my $qry       = $$qryref;
	my $qry_limit = $qry;
	my $scheme_id;
	if ( $qry =~ /FROM m?v?_?scheme_(\d+)/ || $qry =~ /scheme_id='?(\d+)'?/ ) {
		$scheme_id = $1;
	}
	if ( !$scheme_id ) {
		$logger->error("No scheme id determined.");
		return;
	}
	if ( $pagesize && $page ) {
		my $offset = ( $page - 1 ) * $pagesize;
		$qry_limit =~ s/;\s*$/ LIMIT $pagesize OFFSET $offset;/;
	}
	if ( any { lc($qry) =~ /;\s*$_\s/ } (qw (insert delete update alter create drop)) ) {
		$logger->warn("Malicious SQL injection attempt '$qry'");
		return;
	}
	$logger->debug("Passed query: $qry");
	my ( $sql, $limit_sql );
	$limit_sql = $self->{'db'}->prepare($qry_limit);
	$logger->debug("Limit qry: $qry_limit");
	eval { $limit_sql->execute };
	if ($@) {
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid search performed</p></div>\n";
		$logger->warn("Can't execute query $qry_limit  $@");
		return;
	}
	my $primary_key;
	eval {
		$primary_key =
		  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )->[0];
	};
	if ( !$primary_key ) {
		print
"<div class=\"box\" id=\"statusbad\"><p>No primary key field has been set for this scheme.  Profile browsing can not be done until this has been set.</p></div>\n";
		return;
	}
	print "<div class=\"box\" id=\"resultstable\"><div class=\"scrollable\"><table class=\"resultstable\">\n<tr>";
	print "<th>Delete</th><th>Update</th>" if $self->{'curate'};
	print "<th>$primary_key</th>";
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach (@$loci) {
		my $cleaned = $self->clean_locus($_);
		print "<th>$cleaned</th>";
	}
	foreach (@$scheme_fields) {
		next if $primary_key eq $_;
		my $cleaned = $_;
		$cleaned =~ tr/_/ /;
		print "<th>$cleaned</th>";
	}
	print "</tr>";
	my $td = 1;

	#Run limited page query for display
	while ( my $data = $limit_sql->fetchrow_hashref ) {
		my $pk_value     = $data->{ lc($primary_key) };
		my $profcomplete = 1;
		print "<tr class=\"td$td\">";
		if ( $self->{'curate'} ) {
			print "<td><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=delete&amp;table=profiles&amp;"
			  . "scheme_id=$scheme_id&amp;profile_id=$pk_value\">Delete</a></td><td><a href=\"$self->{'system'}->{'script_name'}?"
			  . "db=$self->{'instance'}&amp;page=profileUpdate&amp;scheme_id=$scheme_id&amp;profile_id=$pk_value\">Update</a></td>";
			print "<td><a href=\"$self->{'system'}->{'script_name'}?page=profileInfo&amp;db=$self->{'instance'}&amp;scheme_id=$scheme_id"
			  . "&amp;profile_id=$pk_value&amp;curate=1\">$pk_value</a></td>";
		} else {
			print "<td><a href=\"$self->{'system'}->{'script_name'}?page=profileInfo&amp;db=$self->{'instance'}&amp;"
			  . "scheme_id=$scheme_id&amp;profile_id=$pk_value\">$pk_value</a></td>";
		}
		foreach (@$loci) {
			( my $cleaned = $_ ) =~ s/'/_PRIME_/g;
			print "<td>$data->{lc($cleaned)}</td>";
		}
		foreach (@$scheme_fields) {
			next if $_ eq $primary_key;
			print defined $data->{ lc($_) } ? "<td>$data->{lc($_)}</td>" : '<td></td>';
		}
		print "</tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	print "</table></div>\n\n";
	if ( !$self->{'curate'} ) {
		$self->_print_plugin_buttons($records);
	}
	print "</div>\n";
	$sql->finish if $sql;
	return;
}

sub _print_plugin_buttons {
	my ( $self, $records ) = @_;
	my $q = $self->{'cgi'};
	return if $q->param('page') eq 'customize';
	return if $q->param('page') eq 'tableQuery' && any { $q->param('table') eq $_ } qw(sequences samples history profile_history);
	my $seqdb_type = $q->param('page') eq 'alleleQuery' ? 'sequences' : 'schemes';
	my $plugin_categories =
	  $self->{'pluginManager'}->get_plugin_categories( 'postquery', $self->{'system'}->{'dbtype'}, { seqdb_type => $seqdb_type } );
	if (@$plugin_categories) {
		say "\n<h2>Analysis tools:</h2>\n<div class=\"scrollable\">\n<table>";
		my $set_id = $self->get_set_id;
		foreach (@$plugin_categories) {
			my $cat_buffer;
			my $plugin_names = $self->{'pluginManager'}->get_appropriate_plugin_names(
				'postquery',
				$self->{'system'}->{'dbtype'},
				$_ || 'none',
				{ set_id => $set_id, seqdb_type => $seqdb_type }
			);
			if (@$plugin_names) {
				my $plugin_buffer;
				$q->param( 'calling_page', $q->param('page') );
				foreach (@$plugin_names) {
					my $att = $self->{'pluginManager'}->get_plugin_attributes($_);
					next if $att->{'min'} && $att->{'min'} > $records;
					next if $att->{'max'} && $att->{'max'} < $records;
					$plugin_buffer .= '<td>';
					$plugin_buffer .= $q->start_form;
					$q->param( 'page', 'plugin' );
					$q->param( 'name', $att->{'module'} );
					$plugin_buffer .= $q->hidden($_) foreach qw (db page name calling_page scheme_id locus);
					$plugin_buffer .= $q->hidden('query_file') if ( $att->{'input'} // '' ) eq 'query';
					$plugin_buffer .= $q->submit( -label => ( $att->{'buttontext'} || $att->{'menutext'} ), -class => 'pagebar' );
					$plugin_buffer .= $q->end_form;
					$plugin_buffer .= '</td>';
				}
				if ($plugin_buffer) {
					$_ = 'Miscellaneous' if !$_;
					$cat_buffer .= "<tr><td style=\"text-align:right\">$_: </td><td>\n<table><tr>\n";
					$cat_buffer .= $plugin_buffer;
					$cat_buffer .= "</tr>\n";
				}
			}
			say "$cat_buffer</table></td></tr>" if $cat_buffer;
		}
		say "</table></div>";
	}
	return;
}

sub _get_record_table_info {
	my ( $self, $table ) = @_;
	my $q = $self->{'cgi'};
	my ( @headers, @display, @qry_fields, %type, %foreign_key, %labels );
	my $user_variable_fields = 0;
	push @headers, 'isolate id' if $table eq 'allele_sequences';
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	foreach my $attr (@$attributes) {
		next if $table eq 'sequence_bin' && $attr->{'name'} eq 'sequence';
		next if $attr->{'hide'} eq 'yes' || ( $attr->{'public_hide'} eq 'yes' && !$self->{'curate'} ) || $attr->{'main_display'} eq 'no';
		push @display,    $attr->{'name'};
		push @qry_fields, "$table.$attr->{'name'}";
		my $cleaned = $attr->{'name'};
		$cleaned =~ tr/_/ /;
		if ( any { $attr->{'name'} eq $_ } qw (isolate_display main_display query_field query_status dropdown analysis) ) {
			$cleaned .= '*';
			$user_variable_fields = 1;
		}
		push @headers, $cleaned;
		push @headers, 'isolate id' if $table eq 'experiment_sequences' && $attr->{'name'} eq 'experiment_id';
		push @headers, 'sequence length' if $q->param('page') eq 'tableQuery' && $table eq 'sequences' && $attr->{'name'} eq 'sequence';
		push @headers, 'sequence length' if $q->param('page') eq 'alleleQuery'      && $attr->{'name'} eq 'sequence';
		push @headers, 'flag'            if $table            eq 'allele_sequences' && $attr->{'name'} eq 'complete';
		push @headers, 'citation'        if $attr->{'name'}   eq 'pubmed_id';
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
			  $self->{'datastore'}
			  ->run_list_query( "SELECT field FROM locus_extended_attributes WHERE locus=? ORDER BY field_order", $locus );
			if ( ref $extended_attributes eq 'ARRAY' ) {
				foreach (@$extended_attributes) {
					( my $cleaned = $_ ) =~ tr/_/ /;
					push @headers, $cleaned;
				}
			}
			$linked_data = $self->_data_linked_to_locus($locus);
			push @headers, 'linked data values' if $linked_data;
		}
	}
	if (   ( ( $q->param('page') eq 'tableQuery' && $q->param('table') eq 'sequences' ) || $q->param('page') eq 'alleleQuery' )
		&& ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' )
	{
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

sub _print_record_table {
	my ( $self, $table, $qryref, $page, $records ) = @_;
	my $pagesize = $self->{'prefs'}->{'displayrecs'};
	my $q        = $self->{'cgi'};
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) {
		$logger->error("Record table should not be called for isolates");
		return;
	}
	my $qry = $$qryref;
	if ( $pagesize && $page ) {
		my $offset = ( $page - 1 ) * $pagesize;
		$qry =~ s/;/ LIMIT $pagesize OFFSET $offset;/;
	}
	if ( any { lc($qry) =~ /;\s*$_\s/ } (qw (insert delete update alter create drop)) ) {
		$logger->warn("Malicious SQL injection attempt '$qry'");
		return;
	}
	my $table_info = $self->_get_record_table_info($table);
	my ( $headers, $qry_fields, $display, $extended_attributes ) =
	  ( $table_info->{'headers'}, $table_info->{'qry_fields'}, $table_info->{'display'}, $table_info->{'extended_attributes'} );
	local $" = ',';
	my $fields = "@$qry_fields";
	if ( $table eq 'allele_sequences' && $qry =~ /sequence_flags/ ) {
		$qry =~ s/\*/DISTINCT $fields/;
	} else {
		$qry =~ s/\*/$fields/;
	}
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error("Can't execute: $qry $@") if $@;
	my @retval = $sql->fetchrow_array;
	return if !@retval;
	$sql->finish;
	eval { $sql->execute };
	$logger->error($@) if $@;
	my %data = ();
	$sql->bind_columns( map { \$data{$_} } @$display );    #quicker binding hash to arrayref than to use hashref
	local $" = '</th><th>';
	print "<div class=\"box\" id=\"resultstable\"><div class=\"scrollable\"><table class=\"resultstable\">\n";
	print "<tr>";

	if ( $self->{'curate'} ) {
		print "<th>Delete</th>";
		print "<th>Update</th>" if $table !~ /refs$/;
	}
	print "<th>@$headers</th></tr>\n";
	my $td = 1;
	my ( %foreign_key_sql, $fields_to_query );
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	while ( $sql->fetchrow_arrayref ) {
		my @query_values;
		my %primary_key;
		local $" = "&amp;";
		foreach (@$attributes) {
			if ( $_->{'primary_key'} && $_->{'primary_key'} eq 'yes' ) {
				$primary_key{ $_->{'name'} } = 1;
				my $value = $data{ $_->{'name'} };
				$value =~ s/ /\%20/g;
				$value =~ s/\+/%2B/g;
				push @query_values, "$_->{'name'}=$value";
			}
		}
		print "<tr class=\"td$td\">";
		if ( $self->{'curate'} ) {
			print "<td><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=delete&amp;table=$table&amp;"
			  . "@query_values\">Delete</a></td>";
			if ( $table eq 'allele_sequences' ) {
				print "<td><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagUpdate&amp;@query_values\">"
				  . "Update</a></td>";
			} elsif ( $table !~ /refs$/ ) {    #no editable values in ref tables
				print "<td><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=update&amp;table=$table&amp;"
				  . "@query_values\">Update</a></td>";
			}
		}
		my $set_id = $self->get_set_id;
		my $scheme_info = $data{'scheme_id'} ? $self->{'datastore'}->get_scheme_info( $data{'scheme_id'}, { set_id => $set_id } ) : undef;
		foreach my $field (@$display) {
			$data{ lc($field) } //= '';
			if ( $primary_key{$field} && !$self->{'curate'} ) {
				my $value;
				if ( $field eq 'isolate_id' ) {
					$value = $data{ lc($field) } . ') ' . $self->get_isolate_name_from_id( $data{ lc($field) } );
				} else {
					$value = $data{ lc($field) };
				}
				$value = $self->clean_locus($value);
				given ($table) {
					when ('sequences') {
						print "<td><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleInfo&amp;"
						  . "@query_values\">$value</a></td>";
					}
					when ('history') {
						if ( $field eq 'isolate_id' ) {
							print "<td><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=info&amp;"
							  . "id=$data{'isolate_id'}\">$value</a></td>";
						} else {
							$value =~ s/\..*$//;    #Remove fractions of second from output
							print "<td>$value</td>";
						}
					}
					when ('profile_history') {
						my $set_id = $self->get_set_id;
						my $scheme_info = $self->{'datastore'}->get_scheme_info( $data{'scheme_id'}, { set_id => $set_id } );
						if ( $field eq 'profile_id' ) {
							print "<td><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=profileInfo&amp;"
							  . "scheme_id=$data{'scheme_id'}&amp;profile_id=$data{'profile_id'}\">$value</a></td>";
						} else {
							given ($field) {
								when ('timestamp') { $value =~ s/\..*$// }
								when ('scheme_id') { $value = $scheme_info->{'description'} }
							}
							print "<td>$value</td>";
						}
					}
					default {
						print "<td><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=recordInfo&amp;"
						  . "table=$table&amp;@query_values\">$value</a></td>";
					}
				}
			} elsif ( $table_info->{'type'}->{$field} eq 'bool' ) {
				if ( $data{ lc($field) } eq '' ) {
					print "<td></td>";
				} else {
					my $value = $data{ lc($field) } ? 'true' : 'false';
					print "<td>$value</td>";
				}
				if ( $table eq 'allele_sequences' && $field eq 'complete' ) {
					my $flags =
					  $self->{'datastore'}->get_sequence_flag( $data{'seqbin_id'}, $data{'locus'}, $data{'start_pos'}, $data{'end_pos'} );
					local $" = "</a> <a class=\"seqflag_tooltip\">";
					print @$flags ? "<td><a class=\"seqflag_tooltip\">@$flags</a></td>" : "<td></td>";
				}
			} elsif ( ( $field =~ /sequence$/ || $field =~ /^primer/ ) && $field ne 'coding_sequence' ) {
				if ( length( $data{ lc($field) } ) > 60 ) {
					my $seq = BIGSdb::Utils::truncate_seq( \$data{ lc($field) }, 30 );
					print "<td class=\"seq\">$seq</td>";
				} else {
					print "<td class=\"seq\">$data{lc($field)}</td>";
				}
				print "<td>" . ( length $data{'sequence'} ) . "</td>" if $table eq 'sequences';
			} elsif ( $field eq 'curator' || $field eq 'sender' ) {
				my $user_info = $self->{'datastore'}->get_user_info( $data{ lc($field) } );
				print "<td>$user_info->{'first_name'} $user_info->{'surname'}</td>";
			} elsif ( $table_info->{'foreign_key'}->{$field} && $table_info->{'labels'}->{$field} ) {
				my @fields_to_query;
				if ( !$foreign_key_sql{$field} ) {
					my @values = split /\|/, $table_info->{'labels'}->{$field};
					foreach (@values) {
						if ( $_ =~ /\$(.*)/ ) {
							push @fields_to_query, $1;
						}
					}
					$fields_to_query->{$field} = \@fields_to_query;
					local $" = ',';
					my $qry = "select @fields_to_query from $table_info->{'foreign_key'}->{$field} WHERE id=?";
					$foreign_key_sql{$field} = $self->{'db'}->prepare($qry) or die;
				}
				eval { $foreign_key_sql{$field}->execute( $data{ lc($field) } ) };
				$logger->error($@) if $@;
				while ( my @labels = $foreign_key_sql{$field}->fetchrow_array ) {
					my $value = $table_info->{'labels'}->{$field};
					my $i     = 0;
					foreach ( @{ $fields_to_query->{$field} } ) {
						$value =~ s/$_/$labels[$i]/;
						$i++;
					}
					$value =~ s/[\|\$]//g;
					$value =~ s/\&/\&amp;/g;
					print "<td>$value</td>";
				}
			} elsif ( $field eq 'pubmed_id' ) {
				print "<td>$data{'pubmed_id'}</td>";
				my $citation =
				  $self->{'datastore'}->get_citation_hash( [ $data{'pubmed_id'} ], { formatted => 1, no_title => 1, link_pubmed => 1 } );
				print "<td>$citation->{$data{ 'pubmed_id'}}</td>";
			} else {
				if ( ( $table eq 'allele_sequences' || $table eq 'experiment_sequences' ) && $field eq 'seqbin_id' ) {
					my ( $isolate_id, $isolate ) = $self->get_isolate_id_and_name_from_seqbin_id( $data{'seqbin_id'} );
					print "<td>$isolate_id) $isolate</td>";
				}
				if ( $field eq 'isolate_id' ) {
					print "<td>$data{'isolate_id'}) " . $self->get_isolate_name_from_id( $data{'isolate_id'} ) . "</td>";
				} else {
					my $value = $data{ lc($field) };
					if ( !$self->{'curate'} && ( ( $field eq 'locus' && $table ne 'set_loci' ) || ( $table eq 'loci' && $field eq 'id' ) ) )
					{
						$value = $self->clean_locus($value);
					} else {
						$value =~ s/\&/\&amp;/g;
					}
					print $field eq 'action' ? "<td style=\"text-align:left\">$value</td>" : "<td>$value</td>";
				}
			}
		}
		if ( $q->param('page') eq 'alleleQuery' && ref $extended_attributes eq 'ARRAY' ) {
			my $ext_sql =
			  $self->{'db'}->prepare("SELECT value FROM sequence_extended_attributes WHERE locus=? AND field=? AND allele_id=?");
			foreach (@$extended_attributes) {
				eval { $ext_sql->execute( $data{'locus'}, $_, $data{'allele_id'} ); };
				$logger->error($@) if $@;
				my ($value) = $ext_sql->fetchrow_array;
				print defined $value ? "<td>$value</td>" : '<td></td>';
			}
		}
		if ( $table_info->{'linked_data'} ) {
			my $field_values =
			  $self->{'datastore'}->get_client_data_linked_to_allele( $data{'locus'}, $data{'allele_id'}, { table_format => 1 } );
			print defined $field_values ? "<td style=\"text-align:left\">$field_values</td>" : '<td></td>';
		}
		if (   ( ( $q->param('page') eq 'tableQuery' && $q->param('table') eq 'sequences' ) || $q->param('page') eq 'alleleQuery' )
			&& ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' )
		{
			my $flags = $self->{'datastore'}->get_allele_flags( $data{'locus'}, $data{'allele_id'} );
			local $" = '</a> <a class="seqflag_tooltip">';
			print @$flags ? "<td><a class=\"seqflag_tooltip\">@$flags</a></td>" : '<td></td>';
		}
		print "</tr>\n";
		$td = $td == 2 ? 1 : 2;
	}
	print "</table></div>";
	if ( $table_info->{'user_variable_fields'} ) {
		print "<p class=\"comment\">* Default values are displayed for this field.  These may be overridden by user preference.</p>\n";
	}
	$self->_print_plugin_buttons( $qryref, $records ) if !$self->{'curate'};
	print "</div>\n";
	return;
}

sub _print_publication_table {

	#This function requires that datastore->create_temp_ref_table has been
	#run by the calling code.
	my ( $self, $qryref, $page ) = @_;
	my $q        = $self->{'cgi'};
	my $pagesize = $self->{'prefs'}->{'displayrecs'};
	my $qry      = $$qryref;
	if ( $pagesize && $page ) {
		my $offset = ( $page - 1 ) * $pagesize;
		$qry =~ s/;/ LIMIT $pagesize OFFSET $offset;/;
	}
	if ( any { lc($qry) =~ /;\s*$_\s/ } (qw (insert delete update alter create drop)) ) {
		$logger->warn("Malicious SQL injection attempt '$qry'");
		return;
	}
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	if ($@) {
		$logger->error("Can't execute $qry $@");
		return;
	}
	my $buffer;
	my $td = 1;
	while ( my $refdata = $sql->fetchrow_hashref ) {
		my $author_filter = $q->param('author');
		next if ( $author_filter && $author_filter ne 'All authors' && $refdata->{'authors'} !~ /$author_filter/ );
		$refdata->{'year'} ||= '';
		$buffer .= "<tr class=\"td$td\"><td><a href='http://www.ncbi.nlm.nih.gov/pubmed/$refdata->{'pmid'}'>$refdata->{'pmid'}</a></td>"
		  . "<td>$refdata->{'year'}</td><td style=\"text-align:left\">";
		if ( !$refdata->{'authors'} && !$refdata->{'title'} ) {
			$buffer .= "No details available.</td>\n";
		} else {
			$buffer .= "$refdata->{'authors'} ";
			$buffer .= "($refdata->{'year'}) " if $refdata->{'year'};
			$buffer .= "$refdata->{'journal'} ";
			$buffer .= "<b>$refdata->{'volume'}:</b> "
			  if $refdata->{'volume'};
			$buffer .= " $refdata->{'pages'}</td>\n";
		}
		$buffer .= defined $refdata->{'title'} ? "<td style=\"text-align:left\">$refdata->{'title'}</td>" : '<td></td>';
		if ( defined $q->param('calling_page') && $q->param('calling_page') ne 'browse' && !$q->param('all_records') ) {
			$buffer .= "<td>$refdata->{'isolates'}</td>";
		}
		$buffer .= "<td>" . $self->get_link_button_to_ref( $refdata->{'pmid'}, { class => 'submit' } ) . "</td>\n";
		$buffer .= "</tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	if ($buffer) {
		say "<div class=\"box\" id=\"resultstable\">";
		say "<div class=\"scrollable\">";
		say "<table class=\"resultstable\">\n<thead>";
		say "<tr><th>PubMed id</th><th>Year</th><th>Citation</th><th>Title</th>";
		say "<th>Isolates in query</th>"
		  if defined $q->param('calling_page') && $q->param('calling_page') ne 'browse' && !$q->param('all_records');
		say "<th>Isolates in database</th></tr>\n</thead>\n<tbody>";
		say $buffer;
		say "</tbody></table>\n</div></div>";
	} else {
		say "<div class=\"box\" id=\"resultsheader\"><p>No PubMed records have been linked to isolates.</p></div>";
	}
	return;
}

sub _is_scheme_data_present {
	my ( $self, $qry, $scheme_id ) = @_;
	return $self->{'cache'}->{$qry}->{$scheme_id} if defined $self->{'cache'}->{$qry}->{$scheme_id};
	if ( !$self->{'cache'}->{$qry}->{'ids'} ) {
		$qry =~ s/SELECT \*/SELECT id/;
		$self->{'cache'}->{$qry}->{'ids'} = $self->{'datastore'}->run_list_query($qry);
	}
	my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	foreach my $isolate_id ( @{ $self->{'cache'}->{$qry}->{'ids'} } ) {

		#use Datastore::get_all_allele_designations rather than Datastore::get_all_allele_ids
		#because even though the latter is faster, the former will need to be called to display
		#the data in the table and the results can be cached.
		if ( !$self->{'designations_retrieved'}->{$isolate_id} ) {
			$self->{'designations'}->{$isolate_id}           = $self->{'datastore'}->get_all_allele_designations($isolate_id);
			$self->{'designations_retrieved'}->{$isolate_id} = 1;
		}
		my $allele_designations = $self->{'designations'}->{$isolate_id};
		if ( !$self->{'sequences_retrieved'}->{$isolate_id} ) {
			$self->{'allele_sequences'}->{$isolate_id}    = $self->{'datastore'}->get_all_allele_sequences($isolate_id);
			$self->{'sequences_retrieved'}->{$isolate_id} = 1;
		}
		my $allele_seqs = $self->{'allele_sequences'}->{$isolate_id};
		foreach (@$scheme_loci) {
			if ( $allele_designations->{$_} || $allele_seqs->{$_} ) {
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
	my $qry;
	$locus =~ s/'/\\'/g;
	$qry = "SELECT EXISTS (SELECT * FROM client_dbase_loci_fields WHERE locus=E'$locus')";
	return $self->{'datastore'}->run_simple_query($qry)->[0];
}

sub _initiate_urls_for_loci {
	my ($self) = @_;
	my $locus_info_sql = $self->{'db'}->prepare("SELECT id,url FROM loci");
	eval { $locus_info_sql->execute };
	$logger->error($@) if $@;
	while ( my ( $locus, $url ) = $locus_info_sql->fetchrow_array ) {
		( $self->{'url'}->{$locus} ) = $url;
		$self->{'url'}->{$locus} =~ s/\&/\&amp;/g if $url;
	}
	$self->{'urls_defined'} = 1;
	return;
}

sub _print_pending_tooltip {
	my ( $self, $id, $locus ) = @_;
	my $pending = $self->{'datastore'}->get_pending_allele_designations( $id, $locus );
	if (@$pending) {
		my $pending_buffer = 'pending designations - ';
		foreach (@$pending) {
			my $sender = $self->{'datastore'}->get_user_info( $_->{'sender'} );
			$pending_buffer .= "allele: $_->{'allele_id'} ";
			$pending_buffer .= "($_->{'comments'}) "
			  if $_->{'comments'};
			$pending_buffer .= "[$sender->{'first_name'} $sender->{'surname'}; $_->{'method'}; $_->{'datestamp'}]<br />";
		}
		print " <a class=\"pending_tooltip\" title=\"$pending_buffer\">pending</a>";
	}
	return;
}
1;
