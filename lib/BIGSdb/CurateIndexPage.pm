#Written by Keith Jolley
#Copyright (c) 2010-2012, University of Oxford
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
use parent qw(BIGSdb::CuratePage);
use Error qw(:try);
use List::MoreUtils qw(uniq none);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { general => 0, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub print_content {
	my ($self)       = @_;
	my $script_name  = $self->{'system'}->{'script_name'};
	my $instance     = $self->{'instance'};
	my $system       = $self->{'system'};
	my $curator_name = $self->get_curator_name;
	my $desc = $self->get_db_description;
	print "<h1>Database curator's interface - $desc</h1>\n";
	my $td = 1;
	my $buffer;
	my $can_do_something;

	#Display links for updating database records. Most curators will have access to most of these (but not curator permissions).
	foreach (qw (users user_groups user_group_members user_permissions)) {
		if ( $self->can_modify_table($_) ) {
			my $function = "_print_$_";
			try {
				$buffer .= $self->$function($td);
			}
			catch BIGSdb::DataException with {
				$td = $td == 1 ? 2 : 1;
			};
			$td = $td == 1 ? 2 : 1;
			$can_do_something = 1;
		}
	}
	if ( $system->{'dbtype'} eq 'isolates' ) {
		my @tables = qw (isolates);
		if (
			(
				$self->{'system'}->{'read_access'} eq 'acl'
				|| ( $self->{'system'}->{'write_access'} && $self->{'system'}->{'write_access'} eq 'acl' )
			)
		  )
		{
			push @tables, qw(isolate_user_acl isolate_usergroup_acl);
		}
		push @tables, qw (isolate_value_extended_attributes projects project_members isolate_aliases refs
		  allele_designations sequence_bin accession experiments experiment_sequences allele_sequences samples);
		foreach (@tables) {
			if ( $self->can_modify_table($_) ) {
				my $function  = "_print_$_";
				my $exception = 0;
				try {
					my $temp_value = $self->$function($td);
					$buffer .= $temp_value if $temp_value;
				}
				catch BIGSdb::DataException with {
					$exception = 1;
				};
				next if $exception;
				$td = $td == 1 ? 2 : 1;
				$can_do_something = 1;
			}
		}
	} elsif ( $system->{'dbtype'} eq 'sequences' ) {
		foreach (qw (locus_descriptions scheme_curators locus_curators sequences accession sequence_refs profiles profile_refs)) {
			if ( $self->can_modify_table($_) || $_ eq 'profiles' ) {    #profile permissions handled by ACL
				my $function = "_print_$_";
				try {
					my ( $temp_buffer, $returned_td ) = $self->$function($td);
					if ($temp_buffer) {
						$buffer .= $temp_buffer;
						$can_do_something = 1;
					}
					$td = $returned_td || ( $td == 1 ? 2 : 1 );
				};
			}
		}
	}
	if ($buffer) {
		print <<"HTML";
<div class="box" id="index">
<img src="/images/icons/64x64/edit.png" alt=\"\" />
<h2>Add, update or delete records</h2>
<table style="text-align:center"><tr><th>Record type</th><th>Add</th><th>Batch Add</th><th>Update or delete</th><th>Comments</th></tr>
$buffer
</table>
</div>
HTML
	}
	undef $buffer;
	$td = 1;

	#Display links for updating database configuration tables.
	#These are admin functions, some of which some curators may be allowed to access.
	my $set_id = $self->get_set_id;
	if ( !$set_id ) {    #only modify schemes/loci etc. when sets not being used otherwise it can get too confusing for a curator
		my @tables = qw (loci);
		my @skip_table;
		if ( $system->{'dbtype'} eq 'isolates' ) {
			push @tables, qw(locus_aliases pcr pcr_locus probes probe_locus isolate_field_extended_attributes composite_fields);
		} elsif ( $system->{'dbtype'} eq 'sequences' ) {
			push @tables, qw(locus_extended_attributes client_dbases client_dbase_loci client_dbase_schemes client_dbase_loci_fields);
		}
		if ( ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ) {
			push @tables, 'sets';
			my $set_count = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM sets")->[0];
			if ($set_count) {
				push @tables, qw( set_loci set_schemes);
				if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
					my $metadata_list = $self->{'xmlHandler'}->get_metadata_list;
					push @tables, 'set_metadata' if @$metadata_list;
					push @tables, 'set_view' if $self->{'system'}->{'views'};
				}
			}
		}
		push @tables, qw (schemes scheme_members scheme_fields scheme_groups scheme_group_scheme_members scheme_group_group_members);
		foreach my $table (@tables) {
			if ( $self->can_modify_table($table) && ( !@skip_table || none { $table eq $_ } @skip_table ) ) {
				my $function = "_print_$table";
				try {
					$buffer .= $self->$function($td);
				}
				catch BIGSdb::DataException with {
					$td = $td == 1 ? 2 : 1;
				};
				$td = $td == 1 ? 2 : 1;
				$can_do_something = 1;
			}
		}
	}
	my $list_buffer;
	if ( $self->{'system'}->{'authentication'} eq 'builtin' && ( $self->{'permissions'}->{'set_user_passwords'} || $self->is_admin ) ) {
		$list_buffer .= "<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=setPassword\">"
		  . "Set user passwords</a> - Set a user password to enable them to log on or change an existing password.</li>\n";
		$can_do_something = 1;
	}
	if ( $self->{'permissions'}->{'modify_loci'} || $self->{'permissions'}->{'modify_schemes'} || $self->is_admin ) {
		$list_buffer .=
		    "<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=configCheck\">"
		  . "Configuration check</a> - checks database connectivity for loci and schemes and that required helper "
		  . "applications are properly installed.</li>\n";
		if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
			$list_buffer .= "<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=configRepair\">"
			  . "Configuration repair</a> - Rebuild scheme tables</li>\n";
		}
		$can_do_something = 1;
	}
	if ( $buffer || $list_buffer ) {
		print <<"HTML";
<div class="box" id="restricted">
<img src="/images/icons/64x64/configure.png" alt=\"\" />
<h2>Database configuration</h2>
HTML
	}
	if ($buffer) {
		print <<"HTML";
<table style="text-align:center"><tr><th>Table</th><th>Add</th><th>Batch Add</th><th>Update or delete</th><th>Comments</th></tr>		
$buffer
</table>
HTML
	}
	if ($list_buffer) {
		print "<ul>\n$list_buffer</ul>\n";
	}
	if ( $buffer || $list_buffer ) {
		print "</div>\n";
	}
	if ( !$can_do_something ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Oh dear.  Although you are set as a curator, you haven't been granted specific "
		  . "permission to do anything.  Please contact the database administrator to set your appropriate permissions.</p></div>\n";
	}
	return;
}

sub _print_users {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'users', $td );
}

sub _print_user_group_members {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'user_group_members', $td, { comments => 'Add users to groups for setting access permissions.' } );
}

sub _print_user_permissions {
	my ( $self, $td ) = @_;
	return $self->_print_table(
		'user_permissions',
		$td,
		{
			comments => "Set curator permissions for individual users - these are only active for users with a status of 'curator' "
			  . "in the users table."
		}
	);
}

sub _print_user_groups {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'user_groups', $td,
		{ comments => 'Users can be members of these groups - use for setting access permissions.' } );
}

sub _print_isolates {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>isolates</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=isolateAdd">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=$self->{'system'}->{'view'}">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=isolateQuery">query</a> | 
<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=browse">browse</a> |
<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=listQuery">list</a> |
<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchIsolateUpdate">batch&nbsp;update</a></td>
<td></td></tr>
HTML
	return $buffer;
}

sub _print_isolate_aliases {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'isolate_aliases', $td, { comments => 'Add alternative names for isolates.' } );
}

sub _print_isolate_field_extended_attributes {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'isolate_field_extended_attributes',
		$td, { comments => 'Define additional attributes to associate with values of a particular isolate record field.' } );
}

sub _print_isolate_value_extended_attributes {
	my ( $self, $td ) = @_;
	my $count_att = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM isolate_field_extended_attributes")->[0];
	throw BIGSdb::DataException("No extended attributes") if !$count_att;
	return $self->_print_table( 'isolate_value_extended_attributes',
		$td, { title => 'isolate field extended attribute values', comments => 'Add values for additional isolate field attributes.' } );
}

sub _print_refs {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'refs', $td, { title => 'PubMed links' } );
}

sub _print_allele_designations {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>allele designations</td>
<td></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=allele_designations">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=allele_designations">?</a></td>
<td class="comment" style="text-align:left">Allele designations can be set within the isolate table functions.</td></tr>
HTML
	return $buffer;
}

sub _print_sequence_bin {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>sequences</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=sequence_bin">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSeqbin">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=sequence_bin">?</a></td>
<td class="comment" style="text-align:left">The sequence bin holds sequence contigs from any source.</td></tr>
HTML
	return $buffer;
}

sub _print_accession {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'accession', $td,
		{ title => 'accession number links', comments => 'Tag sequences with Genbank/EMBL accession number.' } );
}

sub _print_experiments {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'experiments', $td, { comments => 'Set up experiments to which sequences in the bin can belong.' } );
}

sub _print_experiment_sequences {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>experiment sequence links</td><td /><td />
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=experiment_sequences">?</a></td>
<td class="comment" style="text-align:left">Query/delete links associating sequences to experiments.</td></tr>	
HTML
	return $buffer;
}

sub _print_samples {
	my ( $self, $td ) = @_;
	my $sample_fields = $self->{'xmlHandler'}->get_sample_field_list;
	return if !@$sample_fields;
	my $buffer = <<"HTML";
<tr class="td$td"><td>sample storage records</td>
<td />
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=samples">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=samples">?</a></td>
<td class="comment" style="text-align:left">Add sample storage records.  These can also be added and updated from the isolate update page.</td></tr>	
HTML
	return $buffer;
}

sub _print_allele_sequences {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>sequence tags</td>
<td colspan="2"><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagScan">scan</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=allele_sequences">?</a></td>
<td class="comment" style="text-align:left" >Tag regions of sequences within the sequence bin with locus information.</td></tr>
HTML
	return $buffer;
}

sub _print_sequences {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>sequences (all loci)</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=sequences">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=sequences">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=sequences">?</a></td>
<td></td></tr>	
HTML
	my $loci;
	if ( $self->is_admin ) {
		$loci = $self->{'datastore'}->get_loci;
	} else {
		my $qry =
"SELECT locus_curators.locus from locus_curators LEFT JOIN loci ON locus=id LEFT JOIN scheme_members on loci.id = scheme_members.locus WHERE locus_curators.curator_id=? ORDER BY scheme_members.scheme_id,locus_curators.locus";
		$loci = $self->{'datastore'}->run_list_query( "$qry", $self->get_curator_id );
		@$loci = uniq @$loci;
	}
	return ( '', $td ) if !@$loci;
	$td = $td == 1 ? 2 : 1;
	if ( scalar @$loci < 15 ) {
		foreach (@$loci) {
			my $cleaned = $self->clean_locus($_);
			$buffer .= <<"HTML";
	<tr class="td$td"><td>$cleaned sequences</td>
	<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=sequences&amp;locus=$_">+</a></td>
	<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=sequences&amp;locus=$_">++</a></td>
	<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=sequences&amp;locus_list=$_">?</a></td>
	<td></td></tr>	
HTML
			$td = $td == 1 ? 2 : 1;
		}
	}
	return ( $buffer, $td );
}

sub _print_locus_descriptions {
	my ( $self, $td ) = @_;
	if ( !$self->is_admin ) {
		my $allowed =
		  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM locus_curators WHERE curator_id=?", $self->get_curator_id )->[0];
		return if !$allowed;
	}
	return $self->_print_table( 'locus_descriptions', $td );
}

sub _print_sets {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'sets', $td,
		{ comments => 'Sets describe a collection of loci and schemes that can be treated like a stand-alone database.' } );
}

sub _print_set_loci {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'set_loci', $td, { comments => 'Add loci to sets.' } );
}

sub _print_set_schemes {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'set_schemes', $td, { comments => 'Add schemes to sets.' } );
}

sub _print_set_metadata {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'set_metadata', $td, { comments => 'Add metadata collection to sets.' } );
}

sub _print_set_view {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'set_view', $td, { comments => 'Set database views linked to sets.' } );
}

sub _print_sequence_refs {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'sequence_refs', $td, { title => 'PubMed links (to sequences)' } );
}

sub _print_profiles {
	my ( $self, $td ) = @_;
	my $schemes;
	my $set_id = $self->get_set_id;
	if ( $self->is_admin ) {
		$schemes =
		  $self->{'datastore'}->run_list_query(
"SELECT DISTINCT id FROM schemes RIGHT JOIN scheme_members ON schemes.id=scheme_members.scheme_id JOIN scheme_fields ON schemes.id=scheme_fields.scheme_id WHERE primary_key ORDER BY id"
		  );
	} else {
		$schemes =
		  $self->{'datastore'}
		  ->run_list_query( "SELECT scheme_id FROM scheme_curators WHERE curator_id=? ORDER BY scheme_id", $self->get_curator_id );
	}
	my $buffer;
	foreach my $scheme_id (@$schemes) {
		next if $set_id && !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id );
		my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
		( my $clean_desc = $scheme_info->{'description'} ) =~ s/\&/\&amp;/g;
		$buffer .= <<"HTML";
<tr class="td$td"><td>$clean_desc profiles</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=profileAdd&amp;scheme_id=$scheme_id">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=profileBatchAdd&amp;scheme_id=$scheme_id">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=profileQuery&amp;scheme_id=$scheme_id">query</a> | 
<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=browse&amp;scheme_id=$scheme_id">browse</a> |
<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=listQuery&amp;scheme_id=$scheme_id">list</a></td>
<td></td></tr>
HTML
		$td = $td == 1 ? 2 : 1;
	}
	return ( $buffer, $td );
}

sub _print_scheme_curators {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>scheme curator control list</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=scheme_curators">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=scheme_curators">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=scheme_curators">query</a> |
<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=memberUpdate&amp;table=scheme_curators">batch</a></td>
<td style="text-align:left" class="comment">Define which curators can add or update profiles for particular schemes.</td></tr>

HTML
	return $buffer;
}

sub _print_locus_curators {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>locus curator control list</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=locus_curators">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=locus_curators">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=locus_curators">query</a> |
<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=memberUpdate&amp;table=locus_curators">batch</a></td>
<td style="text-align:left" class="comment">Define which curators can add or update sequences for particular loci.</td></tr>

HTML
	return $buffer;
}

sub _print_profile_refs {
	my ( $self, $td ) = @_;
	my $set_id = $self->get_set_id;
	if ($set_id) {
		my $schemes_in_set = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM set_schemes WHERE set_id=?", $set_id )->[0];
		return !$schemes_in_set;
	} else {
		my $scheme_count = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM schemes")->[0];
		return if !$scheme_count;
	}
	return $self->_print_table( 'profile_refs', $td, { title => 'PubMed links (to profiles)' } );
}

sub _print_projects {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'projects', $td, { comments => 'Set up projects to which isolates can belong.' } );
}

sub _print_project_members {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'project_members', $td, { requires => 'projects', comments => 'Add isolates to projects.' } );
}

sub _print_loci {
	my ( $self, $td ) = @_;
	my $locus_rowspan = $self->{'system'}->{'dbtype'} eq 'isolates' ? 2 : 1;
	my $buffer = <<"HTML";
<tr class="td$td"><td rowspan="$locus_rowspan">loci</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=loci">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=loci">++</a></td>
<td rowspan="$locus_rowspan"><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=loci">?</a></td>
<td style="text-align:left" class="comment" rowspan="$locus_rowspan"></td></tr>
HTML
	if ( $locus_rowspan = $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$buffer .= <<"HTML";
<tr class="td$td"><td colspan="2"><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=databankScan">databank scan</a></td></tr>
HTML
	}
	return $buffer;
}

sub _print_pcr {
	my ( $self, $td ) = @_;
	return $self->_print_table(
		'pcr', $td,
		{
			title    => 'PCR reactions',
			comments => 'Set up <i>in silico</i> PCR reactions.  These can be used to filter genomes for tagging to '
			  . 'specific repetitive loci.'
		}
	);
}

sub _print_pcr_locus {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'pcr_locus', $td,
		{ requires => 'pcr', title => 'PCR locus links', comments => 'Link a locus to an <i>in silico</i> PCR reaction.' } );
}

sub _print_probes {
	my ( $self, $td ) = @_;
	return $self->_print_table(
		'probes', $td,
		{
			title    => 'nucleotide probes',
			comments => 'Define nucleotide probes for <i>in silico</i> hybridization reaction to filter genomes for '
			  . 'tagging to specific repetitive loci.'
		}
	);
}

sub _print_probe_locus {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'probe_locus', $td,
		{ requires => 'probes', title => 'probe locus links', comments => 'Link a locus to an <i>in silico</i> hybridization reaction.' } );
}

sub _print_locus_aliases {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'locus_aliases', $td,
		{ requires => 'loci', comments => 'Add alternative names for loci.  These can also be set when you batch add loci.' } );
}

sub _print_client_dbases {
	my ( $self, $td ) = @_;
	return $self->_print_table(
		'client_dbases',
		$td,
		{
			title    => 'client databases',
			comments => 'Add isolate databases that use locus allele or scheme profile definitions defined in this database - this '
			  . 'enables backlinks and searches of these databases when you query sequences or profiles in this database.'
		}
	);
}

sub _print_client_dbase_loci_fields {
	my ( $self, $td ) = @_;
	return $self->_print_table(
		'client_dbase_loci_fields',
		$td,
		{
			requires => 'loci,client_dbases',
			title    => 'client database fields linked to loci',
			comments => 'Define fields in client database whose value can be displayed when isolate has matching allele.'
		}
	);
}

sub _print_locus_extended_attributes {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'locus_extended_attributes', $td,
		{ requires => 'loci', comments => 'Define additional fields to associate with sequences of a particular locus.' } );
}

sub _print_client_dbase_loci {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'client_dbase_loci', $td,
		{ requires => 'loci,client_dbases', title => 'client database loci', comments => 'Define loci that are used in client databases.' }
	);
}

sub _print_client_dbase_schemes {
	my ( $self, $td ) = @_;
	return $self->_print_table(
		'client_dbase_schemes',
		$td,
		{
			requires => 'schemes,client_dbases',
			title    => 'client database schemes',
			comments => 'Define schemes that are used in client databases. You will need to add the appropriate loci to the '
			  . 'client database loci table.'
		}
	);
}

sub _print_composite_fields {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>composite fields</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=composite_fields">+</a></td>
<td></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=compositeQuery">?</a></td>
<td style="text-align:left" class="comment">Used to construct composite fields consisting of fields from isolate, loci or scheme fields.</td></tr>
HTML
	return $buffer;
}

sub _print_schemes {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'schemes', $td, { comments => 'Describes schemes consisting of collections of loci, e.g. MLST.' } );
}

sub _print_scheme_groups {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'scheme_groups', $td,
		{ comments => 'Describes groups in to which schemes can belong - groups can also belong to other groups.' } );
}

sub _print_scheme_group_scheme_members {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'scheme_group_scheme_members', $td,
		{ requires => 'scheme_groups,schemes', comments => 'Defines which schemes belong to a group.' } );
}

sub _print_scheme_group_group_members {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'scheme_group_group_members', $td,
		{ requires => 'scheme_groups', comments => 'Defines which scheme groups belong to a parent group.' } );
}

sub _print_scheme_members {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'scheme_members', $td,
		{ requires => 'schemes,loci', comments => 'Defines which loci belong to a scheme.' } );
}

sub _print_scheme_fields {
	my ( $self, $td ) = @_;
	return $self->_print_table( 'scheme_fields', $td, { requires => 'schemes', comments => 'Defines which fields belong to a scheme.' } );
}

sub _print_isolate_user_acl {
	my ( $self, $td ) = @_;
	return $self->_print_table(
		'isolate_user_acl',
		$td,
		{
			title    => 'isolate user access control list',
			comments => 'Define which users can access or update specific isolate records.  It is usually easier to modify these '
			  . 'controls by searching or browsing isolates and selecting the appropriate options.'
		}
	);
}

sub _print_isolate_usergroup_acl {
	my ( $self, $td ) = @_;
	return $self->_print_table(
		'isolate_usergroup_acl',
		$td,
		{
			title    => 'isolate user group access control list',
			comments => 'Define which usergroups can access or update specific isolate records. It is usually easier to modify these '
			 . 'controls by searching or browsing isolates and selecting the appropriate options.'
		}
	);
}

sub _print_table {
	my ( $self, $table, $td, $values ) = @_;
	$values = {} if ref $values ne 'HASH';
	if ( $values->{'requires'} ) {
		my @requires = split /,/, $values->{'requires'};
		foreach my $required (@requires) {
			my $required_value_exists = $self->{'datastore'}->run_simple_query("SELECT EXISTS(SELECT * FROM $required)")->[0];
			throw BIGSdb::DataException("Required parent record does not exist.") if !$required_value_exists;
		}
	}
	my $title = $values->{'title'} // $table;
	$title =~ tr/_/ /;
	my $comments = $values->{'comments'} // '';
	my $buffer = <<"HTML";
<tr class="td$td"><td>$title</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=$table">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=$table">++</a></td>
HTML
	my $records_exist = $self->{'datastore'}->run_simple_query("SELECT EXISTS(SELECT * FROM $table)")->[0];
	$buffer .=
	  $records_exist
	  ? "<td><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=$table\">?</a></td>"
	  : '<td />';
	$buffer .= "<td style=\"text-align:left\" class=\"comment\">$comments</td></tr>";
	return $buffer;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Curator's interface - $desc";
}
1;
