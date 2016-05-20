#Written by Keith Jolley
#Copyright (c) 2010-2016, University of Oxford
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
package BIGSdb::CurateIndexPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage BIGSdb::IndexPage BIGSdb::SubmitPage);
use Error qw(:try);
use List::MoreUtils qw(uniq none);
use BIGSdb::Constants qw(:interface);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery noCache);
	$self->choose_set;
	$self->{'system'}->{'only_sets'} = 'no' if $self->is_admin;
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $buffer = << "END";
\$(function () {
	\$( "#show_closed" ).click(function() {
		if (\$("span#show_closed_text").css('display') == 'none'){
			\$("span#show_closed_text").css('display', 'block');
			\$("span#hide_closed_text").css('display', 'none');
		} else {
			\$("span#show_closed_text").css('display', 'none');
			\$("span#hide_closed_text").css('display', 'block');
		}
		\$( "#closed" ).toggle( 'blind', {} , 500 );
		return false;
	});
	\$('a#toggle_notifications').click(function(event){		
		event.preventDefault();
  		\$(this).attr('href', function(){  		
	  		\$.ajax({
	  			url : this.href,
	  			success: function () {
	  				if (\$('span#notify_text').text() == 'ON'){
	  					\$('span#notify_text').text('OFF');
	  				} else {
	  					\$('span#notify_text').text('ON');
	  				}
	  			}
	  		});
	   	});
	});
});	
END
	return $buffer;
}

sub _toggle_notifications {
	my ($self) = @_;
	return if !$self->{'username'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $new_status = $user_info->{'submission_emails'} ? 0 : 1;
	eval {
		$self->{'db'}
		  ->do( 'UPDATE users SET submission_emails=? WHERE user_name=?', undef, $new_status, $self->{'username'} );
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub _ajax_call {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('toggle_notifications') ) {
		$self->_toggle_notifications;
		return 1;
	}
	return;
}

sub _print_set_section {
	my ($self) = @_;
	if ( ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ) {
		$self->print_set_section;
	}
	return;
}

#Append to URLs to ensure unique caching.
sub _get_set_string {
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	my $set_string = $set_id ? "&amp;set_id=$set_id" : '';
	return $set_string;
}

#Display links for updating database records. Most curators will have
#access to most of these (but not curator permissions).
sub _get_standard_links {
	my ( $self, $td_ref, $can_do_something ) = @_;
	my $set_id     = $self->get_set_id;
	my $set_string = $self->_get_set_string;
	my $buffer;
	foreach (qw (users user_groups user_group_members curator_permissions)) {
		if ( $self->can_modify_table($_) ) {
			my $function = "_print_$_";
			try {
				$buffer .= $self->$function( $$td_ref, $set_string );
			}
			catch BIGSdb::DataException with {
				$$td_ref = $$td_ref == 1 ? 2 : 1;
			};
			$$td_ref = $$td_ref == 1 ? 2 : 1;
			$$can_do_something = 1;
		}
	}
	return $buffer;
}

sub _get_isolate_links {
	my ( $self, $td_ref, $can_do_something ) = @_;
	my $set_id     = $self->get_set_id;
	my $set_string = $self->_get_set_string;
	my $buffer     = q();
	my @tables     = qw (isolates);
	push @tables, qw (isolate_value_extended_attributes projects project_members isolate_aliases refs
	  allele_designations sequence_bin accession experiments experiment_sequences allele_sequences samples);
	foreach (@tables) {

		if ( $self->can_modify_table($_) ) {
			my $function  = "_print_$_";
			my $exception = 0;
			try {
				my $temp_value = $self->$function( $$td_ref, $set_string );
				$buffer .= $temp_value if $temp_value;
			}
			catch BIGSdb::DataException with {
				$exception = 1;
			};
			next if $exception;
			$$td_ref = $$td_ref == 1 ? 2 : 1;
			$$can_do_something = 1;
		}
	}
	return $buffer;
}

sub _get_seqdef_links {
	my ( $self, $td_ref, $can_do_something ) = @_;
	my $set_id     = $self->get_set_id;
	my $set_string = $self->_get_set_string;
	my $buffer     = q();
	foreach (
		qw (locus_descriptions scheme_curators locus_curators sequences retired_allele_ids accession
		sequence_refs profiles profile_refs retired_profiles)
	  )
	{
		if ( $self->can_modify_table($_) || $_ eq 'profiles' ) {
			my $function = "_print_$_";
			try {
				my ( $temp_buffer, $returned_td ) = $self->$function( $$td_ref, $set_string );
				if ($temp_buffer) {
					$buffer .= $temp_buffer;
					$$can_do_something = 1;
				}
				$$td_ref = $returned_td || ( $$td_ref == 1 ? 2 : 1 );
			}
			catch BIGSdb::DataException with {    #Do nothing
			};
		}
	}
	return $buffer;
}

#Display links for updating database configuration tables.
#These are admin functions, some of which some curators may be allowed to access.
sub _get_admin_links {
	my ( $self, $can_do_something ) = @_;
	my $set_id = $self->get_set_id;
	my $buffer = q();
	my $td     = 1;

	#Only modify schemes/loci etc. when sets not selected.
	return q() if $set_id;
	my @tables = qw (loci);
	my @skip_table;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @tables,
		  qw(locus_aliases pcr pcr_locus probes probe_locus isolate_field_extended_attributes composite_fields
		  sequence_attributes);
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		push @tables, qw(locus_aliases locus_extended_attributes client_dbases client_dbase_loci client_dbase_schemes
		  client_dbase_loci_fields);
	}
	if ( ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ) {
		push @tables, 'sets';
		my $sets_exist = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM sets)');
		if ($sets_exist) {
			push @tables, qw( set_loci set_schemes);
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
				my $metadata_list = $self->{'xmlHandler'}->get_metadata_list;
				push @tables, 'set_metadata' if @$metadata_list;
				push @tables, 'set_view'     if $self->{'system'}->{'views'};
			}
		}
	}
	my $set_string = $self->_get_set_string;
	push @tables, qw (schemes scheme_members scheme_fields scheme_groups scheme_group_scheme_members
	  scheme_group_group_members classification_schemes classification_group_fields);
	foreach my $table (@tables) {
		if ( $self->can_modify_table($table) && ( !@skip_table || none { $table eq $_ } @skip_table ) ) {
			my $function = "_print_$table";
			try {
				$buffer .= $self->$function( $td, $set_string );
			}
			catch BIGSdb::DataException with {
				$td = $td == 1 ? 2 : 1;
			};
			$td = $td == 1 ? 2 : 1;
			$$can_do_something = 1;
		}
	}
	return $buffer;
}

sub print_content {
	my ($self)      = @_;
	my $script_name = $self->{'system'}->{'script_name'};
	my $instance    = $self->{'instance'};
	my $system      = $self->{'system'};
	return if $self->_ajax_call;
	my $curator_name = $self->get_curator_name;
	my $desc         = $self->get_db_description;
	say "<h1>Database curator's interface - $desc</h1>";
	my $td = 1;
	my $can_do_something;
	$self->_print_set_section;
	my $buffer = $self->_get_standard_links( \$td, \$can_do_something );
	my $set_id = $self->get_set_id;

	if ( $system->{'dbtype'} eq 'isolates' ) {
		$buffer .= $self->_get_isolate_links( \$td, \$can_do_something );
	} elsif ( $system->{'dbtype'} eq 'sequences' ) {
		$buffer .= $self->_get_seqdef_links( \$td, \$can_do_something );
	}
	if ($buffer) {
		say q(<div class="box" id="index">);
		say q(<span class="main_icon fa fa-edit fa-3x pull-left"></span>);
		say qq(<h2>Add, update or delete records</h2>\n)
		  . q(<table style="text-align:center"><tr><th>Record type</th><th>Add</th>)
		  . q(<th>Batch Add</th><th>Update or delete</th>)
		  . qq(<th>Comments</th></tr>\n$buffer</table></div>);
	}
	if ( ( $self->{'system'}->{'submissions'} // '' ) eq 'yes' ) {
		$self->_print_submission_section;
	}
	$buffer = $self->_get_admin_links( \$can_do_something );
	my $list_buffer = $self->_get_admin_list_links;
	$can_do_something = 1 if $list_buffer;
	if ( $buffer || $list_buffer ) {
		say q(<div class="box" id="restricted">);
		say q(<span class="config_icon fa fa-wrench fa-3x pull-left"></span>);
		say q(<h2>Database configuration</h2>);
		say q(<table style="text-align:center"><tr><th>Table</th><th>Add</th><th>Batch Add</th>)
		  . qq(<th>Update or delete</th><th>Comments</th></tr>$buffer</table>)
		  if $buffer;
		say qq(<ul>$list_buffer</ul>) if $list_buffer;
		say q(</div>);
	}
	if ( !$can_do_something ) {
		say q(<div class="box" id="statusbad"><p>Although you are set as a curator/submitter, )
		  . q(you haven't been granted specific permission to do anything.  Please contact the )
		  . q(database administrator to set your appropriate permissions.</p></div>);
	}
	return;
}

sub _get_admin_list_links {
	my ($self) = @_;
	my $list_buffer;
	if ( $self->{'system'}->{'authentication'} eq 'builtin'
		&& ( $self->{'permissions'}->{'set_user_passwords'} || $self->is_admin ) )
	{
		$list_buffer =
		    qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . q(page=setPassword">Set user passwords</a> - Set a user password to enable them to log on )
		  . qq(or change an existing password.</li>\n);
	}
	if ( $self->{'permissions'}->{'modify_loci'} || $self->{'permissions'}->{'modify_schemes'} || $self->is_admin ) {
		$list_buffer .=
		    qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=configCheck&amp;)
		  . q(show_probs_only=1">Configuration check</a> - Checks database connectivity for loci and schemes and )
		  . qq(that required helper applications are properly installed.</li>\n);
		if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
			$list_buffer .= qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=configRepair">Configuration repair</a> - Rebuild scheme tables</li>\n);
		}
	}
	if ( $self->is_admin && $self->{'system'}->{'dbtype'} eq 'isolates' && $self->_cache_tables_exists ) {
		$list_buffer .= qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=refreshCache">Refresh scheme caches</a> - Update one or all scheme field caches.</li>\n);
	}
	return $list_buffer;
}

sub _cache_tables_exists {
	my ($self) = @_;
	my $exists =
	  $self->{'datastore'}
	  ->run_query(q(SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name LIKE 'temp_%')));
	return $exists;
}

sub _print_users {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table( 'users', $td, { set_string => $set_string } );
}

sub _print_user_group_members {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'user_group_members',
		$td,
		{
			requires   => 'user_groups',
			comments   => 'Add users to groups for setting access permissions.',
			set_string => $set_string
		}
	);
}

sub _print_curator_permissions {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return
	    qq(<tr class="td$td"><td>curator permissions<td></td><td><td>)
	  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=curatorPermissions$set_string">)
	  . q(?</a></td><td class="comment" style="text-align:left">Set curator permissions for )
	  . q(individual users - these are only active for users with a status of 'curator' in the users table.</td></tr>);
}

sub _print_user_groups {            ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'user_groups',
		$td,
		{
			comments   => 'Users can be members of these groups - use for setting access permissions.',
			set_string => $set_string
		}
	);
}

sub _print_isolates {               ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	my $exists = $self->{'datastore'}->run_query("SELECT EXISTS(SELECT id FROM $self->{'system'}->{'view'})");
	my $query_cell =
	  $exists
	  ? qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query$set_string">)
	  . q(query/browse</a> | )
	  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=batchIsolateUpdate$set_string">batch&nbsp;update</a>)
	  : q();
	my $buffer =
	    qq(<tr class="td$td"><td>isolates</td>)
	  . qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=isolateAdd$set_string">+</a></td>)
	  . qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=batchAdd&amp;table=isolates$set_string">++</a></td><td>$query_cell</td>)
	  . q(<td class="comment" style="text-align:left">Query or browse for isolates to update or delete.</td></tr>);
	return $buffer;
}

sub _print_isolate_aliases {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'isolate_aliases',
		$td,
		{
			comments   => 'Add alternative names for isolates.',
			set_string => $set_string,
			requires   => $self->{'system'}->{'view'}
		}
	);
}

sub _print_isolate_field_extended_attributes { ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'isolate_field_extended_attributes',
		$td,
		{
			comments   => 'Define additional attributes to associate with values of a particular isolate record field.',
			set_string => $set_string
		}
	);
}

sub _print_isolate_value_extended_attributes { ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	my $count_att = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM isolate_field_extended_attributes)');
	throw BIGSdb::DataException('No extended attributes') if !$count_att;
	return $self->_print_table(
		'isolate_value_extended_attributes',
		$td,
		{
			title      => 'isolate field extended attribute values',
			comments   => 'Add values for additional isolate field attributes.',
			set_string => $set_string
		}
	);
}

sub _print_refs {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table( 'refs', $td,
		{ title => 'PubMed links', set_string => $set_string, requires => $self->{'system'}->{'view'} } );
}

sub _print_allele_designations {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	my $isolates_exists = $self->{'datastore'}->run_query("SELECT EXISTS(SELECT id FROM $self->{'system'}->{'view'})");
	throw BIGSdb::DataException('No isolates') if !$isolates_exists;
	my $exists = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT isolate_id FROM allele_designations)');
	my $query_cell =
	  $exists
	  ? qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;)
	  . qq(table=allele_designations$set_string">?</a>)
	  : q();
	my $buffer = <<"HTML";
<tr class="td$td"><td>allele designations</td>
<td></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=allele_designations$set_string">++</a></td>
<td>$query_cell</td>
<td class="comment" style="text-align:left">Allele designations can be set within the isolate table functions.</td></tr>
HTML
	return $buffer;
}

sub _print_sequence_bin {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	my $isolates_exists = $self->{'datastore'}->run_query("SELECT EXISTS(SELECT id FROM $self->{'system'}->{'view'})");
	throw BIGSdb::DataException('No isolates') if !$isolates_exists;
	my $exists = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT id FROM sequence_bin)');
	my $query_cell =
	  $exists
	  ? qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;)
	  . qq(table=sequence_bin$set_string">?</a>)
	  : q();
	my $buffer = <<"HTML";
<tr class="td$td"><td>sequences</td>
<td></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSeqbin$set_string">++</a></td>
<td>$query_cell</td>
<td class="comment" style="text-align:left">The sequence bin holds sequence contigs from any source.</td></tr>
HTML
	return $buffer;
}

sub _print_sequence_attributes {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	my $exists = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT key FROM sequence_attributes)');
	my $query_cell =
	  $exists
	  ? qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;)
	  . qq(table=sequence_attributes$set_string">?</a>)
	  : q();
	my $buffer = <<"HTML";
<tr class="td$td"><td>sequence attributes</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=sequence_attributes$set_string">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=sequence_attributes$set_string">++
</a></td>
<td>$query_cell</td>
<td class="comment" style="text-align:left">Define attributes that can be set for contigs in the sequence bin.</td></tr>
HTML
	return $buffer;
}

sub _print_accession {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'accession',
		$td,
		{
			title      => 'accession number links',
			comments   => 'Associate sequences with Genbank/EMBL accession number.',
			set_string => $set_string,
			requires   => $self->{'system'}->{'dbtype'} eq 'sequences' ? 'sequences' : 'sequence_bin'
		}
	);
}

sub _print_experiments {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table( 'experiments', $td,
		{ comments => 'Set up experiments to which sequences in the bin can belong.', set_string => $set_string } );
}

sub _print_experiment_sequences {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'experiment_sequences',
		$td,
		{
			requires   => 'projects',
			comments   => 'Add links associating sequences to experiments.',
			set_string => $set_string,
			requires   => 'experiments',
			no_add     => 1
		}
	);
}

sub _print_samples {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	my $sample_fields = $self->{'xmlHandler'}->get_sample_field_list;
	return if !@$sample_fields;
	my $buffer = <<"HTML";
<tr class="td$td"><td>sample storage records</td>
<td></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=samples$set_string">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=samples$set_string">?</a></td>
<td class="comment" style="text-align:left">Add sample storage records.  These can also be added and updated from the isolate update page.</td></tr>	
HTML
	return $buffer;
}

sub _print_allele_sequences {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	my $seqbin_exists = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT id FROM sequence_bin)');
	throw BIGSdb::DataException('No sequences in bin') if !$seqbin_exists;
	my $exists = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT seqbin_id FROM allele_sequences)');
	my $query_cell =
	  $exists
	  ? qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;)
	  . qq(table=allele_sequences$set_string">?</a>)
	  : q();
	my $buffer = <<"HTML";
<tr class="td$td"><td>sequence tags</td>
<td colspan="2"><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagScan$set_string">scan</a></td>
<td>$query_cell</td>
<td class="comment" style="text-align:left" >Tag regions of sequences within the sequence bin with locus information.</td></tr>
HTML
	return $buffer;
}

sub _print_sequences {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>sequences (all loci)</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=sequences$set_string">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=sequences$set_string">++</a> | 
<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddFasta$set_string">FASTA</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=sequences$set_string">?</a></td>
<td></td></tr>	
HTML
	my $locus_curator = $self->is_admin ? undef : $self->get_curator_id;
	my $set_id = $self->get_set_id;
	my ( $loci, undef ) =
	  $self->{'datastore'}
	  ->get_locus_list( { set_id => $set_id, locus_curator => $locus_curator, no_list_by_common_name => 1 } );
	return ( '', $td ) if !@$loci;
	$td = $td == 1 ? 2 : 1;
	if ( scalar @$loci < 15 ) {

		foreach (@$loci) {
			my $cleaned = $self->clean_locus($_);
			$buffer .= <<"HTML";
	<tr class="td$td"><td>$cleaned sequences</td>
	<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=sequences&amp;locus=$_$set_string">+</a></td>
	<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=sequences&amp;locus=$_$set_string">++</a></td>
	<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=sequences&amp;locus_list=$_$set_string">?</a></td>
	<td></td></tr>	
HTML
			$td = $td == 1 ? 2 : 1;
		}
	}
	return ( $buffer, $td );
}

sub _print_retired_allele_ids {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	if ( !$self->is_admin ) {
		my $allowed =
		  $self->{'datastore'}
		  ->run_query( 'SELECT EXISTS(SELECT * FROM locus_curators WHERE curator_id=?)', $self->get_curator_id );
		return if !$allowed;
	}
	return $self->_print_table(
		'retired_allele_ids',
		$td,
		{
			set_string => $set_string,
			requires   => 'loci',
			comments   => 'Allele ids defined here will be prevented from being used.'
		}
	);
}

sub _print_retired_profiles {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	my $set_id = $self->get_set_id;
	if ($set_id) {
		my $schemes_in_set =
		  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM set_schemes WHERE set_id=?)', $set_id );
		return !$schemes_in_set;
	} else {
		my $scheme_count = $self->{'datastore'}->run_query('SELECT COUNT(*) FROM schemes');
		return if !$scheme_count;
	}
	return $self->_print_table(
		'retired_profiles',
		$td,
		{
			set_string => $set_string,
			requires   => 'schemes',
			comments   => 'Scheme profiles defined here will be prevented from being used.'
		}
	);
}

sub _print_locus_descriptions {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	if ( !$self->is_admin ) {
		my $allowed =
		  $self->{'datastore'}
		  ->run_query( 'SELECT EXISTS(SELECT * FROM locus_curators WHERE curator_id=?)', $self->get_curator_id );
		return if !$allowed;
	}
	return $self->_print_table( 'locus_descriptions', $td, { set_string => $set_string } );
}

sub _print_sets {                  ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'sets', $td,
		{
			comments =>
			  'Sets describe a collection of loci and schemes that can be treated like a stand-alone database.',
			set_string => $set_string
		}
	);
}

sub _print_set_loci {              ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table( 'set_loci', $td,
		{ requires => 'sets,loci', comments => 'Add loci to sets.', set_string => $set_string } );
}

sub _print_set_schemes {           ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table( 'set_schemes', $td,
		{ requires => 'sets,schemes', comments => 'Add schemes to sets.', set_string => $set_string } );
}

sub _print_set_metadata {          ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table( 'set_metadata', $td,
		{ requires => 'sets', comments => 'Add metadata collection to sets.', set_string => $set_string } );
}

sub _print_set_view {              ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table( 'set_view', $td,
		{ requires => 'sets', comments => 'Set database views linked to sets.', set_string => $set_string } );
}

sub _print_sequence_refs {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table( 'sequence_refs', $td,
		{ title => 'PubMed links (to sequences)', set_string => $set_string } );
}

sub _print_profiles {         ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	my $schemes;
	my $set_id = $self->get_set_id;
	if ( $self->is_admin ) {
		$schemes = $self->{'datastore'}->run_query(
			'SELECT DISTINCT id FROM schemes RIGHT JOIN scheme_members ON schemes.id=scheme_members.scheme_id '
			  . 'JOIN scheme_fields ON schemes.id=scheme_fields.scheme_id WHERE primary_key',
			undef,
			{ fetch => 'col_arrayref' }
		);
	} else {
		$schemes = $self->{'datastore'}->run_query( 'SELECT scheme_id FROM scheme_curators WHERE curator_id=?',
			$self->get_curator_id, { fetch => 'col_arrayref' } );
	}
	my $buffer;
	my %desc;
	foreach my $scheme_id (@$schemes)
	{    #Can only order schemes after retrieval since some can be renamed by set membership
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
		$desc{$scheme_id} = $scheme_info->{'description'};
	}
	foreach my $scheme_id ( sort { $desc{$a} cmp $desc{$b} } @$schemes ) {
		next if $set_id && !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id );
		$desc{$scheme_id} =~ s/\&/\&amp;/gx;
		$buffer .=
		    qq(<tr class="td$td"><td>$desc{$scheme_id} profiles</td>)
		  . qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=profileAdd&amp;)
		  . qq(scheme_id=$scheme_id$set_string">+</a></td>)
		  . qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=profileBatchAdd&amp;)
		  . qq(scheme_id=$scheme_id$set_string">++</a></td>)
		  . qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;)
		  . qq(scheme_id=$scheme_id$set_string">query/browse/list</a> | )
		  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchProfileUpdate&amp;)
		  . qq(scheme_id=$scheme_id$set_string">batch update</a></td><td></td></tr>);
		$td = $td == 1 ? 2 : 1;
	}
	return ( $buffer, $td );
}

sub _print_scheme_curators {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>scheme curator control list</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=scheme_curators$set_string">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=scheme_curators$set_string">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=scheme_curators$set_string">query</a> |
<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=memberUpdate&amp;table=scheme_curators$set_string">batch</a></td>
<td style="text-align:left" class="comment">Define which curators can add or update profiles for particular schemes.</td></tr>

HTML
	return $buffer;
}

sub _print_locus_curators {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>locus curator control list</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=locus_curators$set_string">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=locus_curators$set_string">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=locus_curators$set_string">query</a> |
<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=memberUpdate&amp;table=locus_curators$set_string">batch</a></td>
<td style="text-align:left" class="comment">Define which curators can add or update sequences for particular loci.</td></tr>

HTML
	return $buffer;
}

sub _print_profile_refs {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	my $set_id = $self->get_set_id;
	if ($set_id) {
		my $schemes_in_set =
		  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM set_schemes WHERE set_id=?)', $set_id );
		return !$schemes_in_set;
	} else {
		my $scheme_count = $self->{'datastore'}->run_query('SELECT COUNT(*) FROM schemes');
		return if !$scheme_count;
	}
	return $self->_print_table( 'profile_refs', $td,
		{ title => 'PubMed links (to profiles)', set_string => $set_string } );
}

sub _print_projects {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'projects',
		$td,
		{
			comments   => 'Set up projects to which isolates can belong.',
			set_string => $set_string,
			requires   => $self->{'system'}->{'view'}
		}
	);
}

sub _print_project_members {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table( 'project_members', $td,
		{ requires => 'projects', comments => 'Add isolates to projects.', set_string => $set_string } );
}

sub _print_loci {               ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	my $exists = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT id FROM loci)');
	my $query_cell =
	  $exists
	  ? qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;)
	  . qq(table=loci$set_string">?</a>)
	  : q();
	my $buffer = <<"HTML";
<tr class="td$td"><td rowspan="2">loci</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=loci$set_string">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=loci$set_string">++</a></td>
<td rowspan="2">$query_cell</td>
<td style="text-align:left" class="comment" rowspan="2"></td></tr>
<tr class="td$td"><td colspan="2"><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=databankScan$set_string">
databank scan</a></td></tr>
HTML
	return $buffer;
}

sub _print_pcr {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'pcr', $td,
		{
			title    => 'PCR reactions',
			comments => 'Set up <i>in silico</i> PCR reactions.  These can be used to filter genomes for tagging to '
			  . 'specific repetitive loci.',
			set_string => $set_string
		}
	);
}

sub _print_pcr_locus {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'pcr_locus',
		$td,
		{
			requires   => 'pcr',
			title      => 'PCR locus links',
			comments   => 'Link a locus to an <i>in silico</i> PCR reaction.',
			set_string => $set_string
		}
	);
}

sub _print_probes {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'probes', $td,
		{
			title    => 'nucleotide probes',
			comments => 'Define nucleotide probes for <i>in silico</i> hybridization reaction to '
			  . 'filter genomes for tagging to specific repetitive loci.',
			set_string => $set_string
		}
	);
}

sub _print_probe_locus {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'probe_locus',
		$td,
		{
			requires   => 'probes',
			title      => 'probe locus links',
			comments   => 'Link a locus to an <i>in silico</i> hybridization reaction.',
			set_string => $set_string
		}
	);
}

sub _print_locus_aliases {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'locus_aliases',
		$td,
		{
			requires   => 'loci',
			comments   => 'Add alternative names for loci.  These can also be set when you batch add loci.',
			set_string => $set_string
		}
	);
}

sub _print_client_dbases {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'client_dbases',
		$td,
		{
			title    => 'client databases',
			comments => 'Add isolate databases that use locus allele or scheme profile definitions defined '
			  . 'in this database - this enables backlinks and searches of these databases when you query '
			  . 'sequences or profiles in this database.',
			set_string => $set_string
		}
	);
}

sub _print_client_dbase_loci_fields {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'client_dbase_loci_fields',
		$td,
		{
			requires => 'loci,client_dbases',
			title    => 'client database fields linked to loci',
			comments => 'Define fields in client database whose value can be '
			  . 'displayed when isolate has matching allele.',
			set_string => $set_string
		}
	);
}

sub _print_locus_extended_attributes {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'locus_extended_attributes',
		$td,
		{
			requires   => 'loci',
			comments   => 'Define additional fields to associate with sequences of a particular locus.',
			set_string => $set_string
		}
	);
}

sub _print_client_dbase_loci {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'client_dbase_loci',
		$td,
		{
			requires   => 'loci,client_dbases',
			title      => 'client database loci',
			comments   => 'Define loci that are used in client databases.',
			set_string => $set_string
		}
	);
}

sub _print_client_dbase_schemes {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'client_dbase_schemes',
		$td,
		{
			requires => 'schemes,client_dbases',
			title    => 'client database schemes',
			comments => 'Define schemes that are used in client databases. You will need to '
			  . 'add the appropriate loci to the client database loci table.',
			set_string => $set_string
		}
	);
}

sub _print_composite_fields {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	my $exists = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT id FROM composite_fields)');
	my $query_cell =
	  $exists
	  ? qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=compositeQuery$set_string">?</a>)
	  : q();
	my $buffer = <<"HTML";
<tr class="td$td"><td>composite fields</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=composite_fields$set_string">+</a></td>
<td></td><td>$query_cell</td>
<td style="text-align:left" class="comment">Used to construct composite fields consisting of fields from isolate, loci or scheme 
fields.</td></tr>
HTML
	return $buffer;
}

sub _print_schemes {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table( 'schemes', $td,
		{ comments => 'Describes schemes consisting of collections of loci, e.g. MLST.', set_string => $set_string } );
}

sub _print_scheme_groups {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'scheme_groups',
		$td,
		{
			comments   => 'Describes groups in to which schemes can belong - groups can also belong to other groups.',
			set_string => $set_string
		}
	);
}

sub _print_scheme_group_scheme_members {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'scheme_group_scheme_members',
		$td,
		{
			requires   => 'scheme_groups,schemes',
			comments   => 'Defines which schemes belong to a group.',
			set_string => $set_string
		}
	);
}

sub _print_scheme_group_group_members {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table(
		'scheme_group_group_members',
		$td,
		{
			requires   => 'scheme_groups',
			comments   => 'Defines which scheme groups belong to a parent group.',
			set_string => $set_string
		}
	);
}

sub _print_scheme_members {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table( 'scheme_members', $td,
		{ requires => 'schemes,loci', comments => 'Defines which loci belong to a scheme.', set_string => $set_string }
	);
}

sub _print_scheme_fields {     ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table( 'scheme_fields', $td,
		{ requires => 'schemes', comments => 'Defines which fields belong to a scheme.', set_string => $set_string } );
}

sub _print_classification_schemes {## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table( 'classification_schemes', $td,
		{ requires => 'schemes', comments => 'Defines classification schemes.', set_string => $set_string } );
}

sub _print_classification_group_fields {## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $td, $set_string ) = @_;
	return $self->_print_table( 'classification_group_fields', $td,
		{ requires => 'classification_schemes', comments => 'Defines which fields belong to a classification scheme.', set_string => $set_string } );
}

sub _print_table {
	my ( $self, $table, $td, $values ) = @_;
	$values = {} if ref $values ne 'HASH';
	my $set_string = $values->{'set_string'} // '';
	if ( $values->{'requires'} ) {
		my @requires = split /,/x, $values->{'requires'};
		foreach my $required (@requires) {
			my $required_value_exists = $self->{'datastore'}->run_query("SELECT EXISTS(SELECT * FROM $required)");
			throw BIGSdb::DataException('Required parent record does not exist.') if !$required_value_exists;
		}
	}
	my $title = $values->{'title'} // $table;
	$title =~ tr/_/ /;
	my $comments = $values->{'comments'} // '';
	my $buffer = qq(<tr class="td$td"><td>$title</td>);
	if ( !$values->{'no_add'} ) {
		$buffer .=
		    qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=add&amp;table=$table$set_string">+</a></td><td><a href="$self->{'system'}->{'script_name'}?)
		  . qq(db=$self->{'instance'}&amp;page=batchAdd&amp;table=$table$set_string">++</a></td>);
	} else {
		$buffer .= q(<td></td>) x 2;
	}
	my $records_exist = $self->{'datastore'}->run_query("SELECT EXISTS(SELECT * FROM $table)");
	$buffer .=
	  $records_exist
	  ? qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=tableQuery&amp;table=$table$set_string">?</a></td>)
	  : q(<td></td>);
	$buffer .= qq(<td style="text-align:left" class="comment">$comments</td></tr>);
	return $buffer;
}

sub _print_submission_section {
	my ($self) = @_;
	my $buffer = $self->print_submissions_for_curation( { get_only => 1 } );
	my $closed_buffer =
	  $self->print_submissions_for_curation( { status => 'closed', show_outcome => 1, get_only => 1 } );
	if ( $buffer || $closed_buffer ) {
		say q(<div class="box" id="submissions"><div class="scrollable">);
		say q(<span class="main_icon fa fa-upload fa-3x pull-left"></span>);
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		my $on_or_off =
		  $user_info->{'submission_emails'}
		  ? 'ON'
		  : 'OFF';
		say qq(<div style="float:right"><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . q(page=index&amp;toggle_notifications=1" id="toggle_notifications" class="no_link">)
		  . q(<span class="main_icon fa fa-envelope fa-lg pull-left">)
		  . qq(</span>Notifications: <span id="notify_text" style="font-weight:600">$on_or_off</span></a></div>);
		say $buffer if $buffer;
		if ($closed_buffer) {
			say q(<h2>Submissions</h2>) if !$buffer;
			my $class = RESET_BUTTON_CLASS;
			say qq(<a id="show_closed" class="$class ui-button-text-only" >)
			  . q(<span id="show_closed_text" class="ui-button-text" )
			  . q(style="display:block">Show closed submissions</span>)
			  . q(<span id="hide_closed_text" class="ui-button-text" )
			  . q(style="display:none">Hide closed submissions</span></a>);
			say q(<div id="closed" style="display:none">)
			  . q(<h2>Closed submissions for which you had curator rights</h2>);
			my $days = $self->get_submission_days;
			say q(<p>The following submissions are now closed - they will remain here until )
			  . qq(removed by the submitter or for $days days.);
			say $closed_buffer;
			say q(</div>);
		}
		say q(</div></div>);
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Curator's interface - $desc";
}
1;
