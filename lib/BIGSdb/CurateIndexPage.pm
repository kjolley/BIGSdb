#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
use base qw(BIGSdb::CuratePage);
use Error qw(:try);
use List::MoreUtils qw(uniq none);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { 'general' => 0, 'main_display' => 0, 'isolate_display' => 0, 'analysis' => 0, 'query_field' => 0 };
}

sub print_content {
	my ($self)       = @_;
	my $script_name  = $self->{'system'}->{'script_name'};
	my $instance     = $self->{'instance'};
	my $system       = $self->{'system'};
	my $curator_name = $self->get_curator_name;
	print "<h1>Database curator's interface - $system->{'description'}</h1>\n";
	my $td = 1;
	my $buffer;
	my $can_do_something;

	#Display links for updating database records. Most curators will have access to most of these (but not curator permissions).
	foreach (qw (users user_groups user_group_members user_permissions)) {
		if ( $self->can_modify_table($_) ) {
			my $function = "_print_$_";
			$buffer .= $self->$function($td);
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
		foreach (
			qw (locus_descriptions scheme_curators locus_curators sequences accession
			sequence_refs profiles profile_refs)
		  )
		{
			if ( $self->can_modify_table($_) || $_ eq 'profiles' ) {    #profile permissions handled by ACL
				my $function = "_print_$_";
				my ( $temp_buffer, $returned_td ) = $self->$function($td);
				$buffer .= $temp_buffer if $temp_buffer;
				$td = $returned_td || ( $td == 1 ? 2 : 1 );
				$can_do_something = 1 if $temp_buffer;
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
	my @tables = qw (loci);
	my @skip_table;
	if ( $system->{'dbtype'} eq 'isolates' ) {
		push @tables, qw(locus_aliases pcr pcr_locus probes probe_locus isolate_field_extended_attributes composite_fields);
	} elsif ( $system->{'dbtype'} eq 'sequences' ) {
		push @tables, qw(locus_extended_attributes client_dbases client_dbase_loci client_dbase_schemes client_dbase_loci_fields);
		my $client_db_count = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM client_dbases")->[0];
		if ( !$client_db_count ) {
			push @skip_table, qw (client_dbase_loci client_dbase_schemes client_dbase_loci_fields);
		}
	}
	push @tables, qw (schemes scheme_members scheme_fields scheme_groups scheme_group_scheme_members scheme_group_group_members);
	foreach my $table (@tables) {
		if ( $self->can_modify_table($table) && ( !@skip_table || none { $table eq $_ } @skip_table ) ) {
			my $function = "_print_$table";
			$buffer .= $self->$function($td);
			$td = $td == 1 ? 2 : 1;
			$can_do_something = 1;
		}
	}
	my $list_buffer;
	if ( $self->{'system'}->{'authentication'} eq 'builtin' && ( $self->{'permissions'}->{'set_user_passwords'} || $self->is_admin ) ) {
		$list_buffer .=
"<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=setPassword\">Set user passwords</a> - Set a user password to enable them to log on or change an existing password.</li>\n";
		$can_do_something = 1;
	}
	if ( $self->{'permissions'}->{'modify_loci'} || $self->{'permissions'}->{'modify_schemes'} || $self->is_admin ) {
		$list_buffer .= "<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=configCheck\">"
		. "Configuration check</a> - checks database connectivity for loci and schemes and that required helper "
		. "applications are properly installed.</li>\n";
		if ($self->{'system'}->{'dbtype'} eq 'sequences'){
			$list_buffer .= "<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=configRepair\">"
			. "Configuration repair</a> - Rebuild scheme tables</li>\n"
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
		print "<div class=\"box\" id=\"statusbad\"><p>Oh dear.  Although you are set as a curator, you haven't been granted specific
		permission to do anything.  Please contact the database administrator to set your appropriate permissions.</p></div>\n";
	}
}

sub _print_users {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>users</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=users">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=users">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=users">?</a></td>
<td></td></tr>
HTML
	return $buffer;
}

sub _print_user_group_members {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>user group members</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=user_group_members">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=user_group_members">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=user_group_members">?</a></td>
<td style="text-align:left" class="comment">Add users to groups for setting access permissions.</td></tr>
HTML
	return $buffer;
}

sub _print_user_permissions {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>user permissions</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=user_permissions">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=user_permissions">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=user_permissions">?</a></td>
<td style="text-align:left" class="comment">Set curator permissions for individual users - these are only active for users with a status of 'curator' in the users table.</td></tr>
HTML
	return $buffer;
}

sub _print_user_groups {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>user groups</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=user_groups">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=user_groups">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=user_groups">?</a></td>
<td style="text-align:left" class="comment">Users can be members of these groups - use for setting access permissions.</td></tr>
HTML
	return $buffer;
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
	my $buffer = <<"HTML";
<tr class="td$td"><td>isolate aliases</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=isolate_aliases">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=isolate_aliases">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=isolate_aliases">?</a></td>
<td class="comment" style="text-align:left">Add alternative names for isolates.</td></tr>
HTML
	return $buffer;
}

sub _print_isolate_field_extended_attributes {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>isolate field extended attributes</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=isolate_field_extended_attributes">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=isolate_field_extended_attributes">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=isolate_field_extended_attributes">?</a></td>
<td style="text-align:left" class="comment">Define additional attributes to associate with values of a particular isolate record field.</td></tr>
HTML
	return $buffer;
}

sub _print_isolate_value_extended_attributes {
	my ( $self, $td ) = @_;
	my $count_att = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM isolate_field_extended_attributes")->[0];
	throw BIGSdb::DataException("No extended attributes") if !$count_att;
	my $buffer = <<"HTML";
<tr class="td$td"><td>isolate field extended attribute values</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=isolate_value_extended_attributes">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=isolate_value_extended_attributes">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=isolate_value_extended_attributes">?</a></td>
<td style="text-align:left" class="comment">Add values for additional isolate field attributes.</td></tr>
HTML
	return $buffer;
}

sub _print_refs {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>PubMed links</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=refs">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=refs">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=pubmedQuery">?</a></td>
<td></td></tr>
HTML
	return $buffer;
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
	my $buffer = <<"HTML";
<tr class="td$td"><td>accession number links</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=accession">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=accession">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=accession">?</a></td>
<td class="comment" style="text-align:left">Tag sequences with Genbank/EMBL accession number.</td></tr>	
HTML
	return $buffer;
}

sub _print_experiments {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>experiments</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=experiments">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=experiments">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=experiments">?</a></td>
<td class="comment" style="text-align:left">Set up experiments to which sequences in the bin can belong.</td></tr>	
HTML
	return $buffer;
}

sub _print_experiment_sequences {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>experiment sequence links</td>
<td />
<td />
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
	my $buffer = <<"HTML";
<tr class="td$td"><td>locus descriptions</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=locus_descriptions">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=locus_descriptions">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=locus_descriptions">?</a></td>
<td></td></tr>
HTML
	return $buffer;
}

sub _print_sequence_refs {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>PubMed links (to sequences)</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=sequence_refs">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=sequence_refs">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=sequence_refs">?</a></td>
<td></td></tr>
HTML
	return $buffer;
}

sub _print_profiles {
	my ( $self, $td ) = @_;
	my $schemes;
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
	foreach (@$schemes) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info($_);
		( my $clean_desc = $scheme_info->{'description'} ) =~ s/\&/\&amp;/g;
		$buffer .= <<"HTML";
<tr class="td$td"><td>$clean_desc profiles</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=profileAdd&amp;scheme_id=$_">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=profileBatchAdd&amp;scheme_id=$_">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=profileQuery&amp;scheme_id=$_">query</a> | 
<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=browse&amp;scheme_id=$_">browse</a></td>
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
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=scheme_curators">?</a></td>
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
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=locus_curators">?</a></td>
<td style="text-align:left" class="comment">Define which curators can add or update sequences for particular loci.</td></tr>

HTML
	return $buffer;
}

sub _print_profile_refs {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>PubMed links (to profiles)</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=profile_refs">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=profile_refs">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=profile_refs">?</a></td>
<td></td></tr>
HTML
	return $buffer;
}

sub _print_projects {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>projects</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=projects">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=projects">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=projects">?</a></td>
<td style="text-align:left" class="comment">Set up projects to which isolates can belong.</td></tr>
HTML
}

sub _print_project_members {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>project members</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=project_members">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=project_members">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=project_members">?</a></td>
<td style="text-align:left" class="comment">Add isolates to projects.</td></tr>
HTML
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
	my $buffer = <<"HTML";
<tr class="td$td"><td>PCR reactions</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=pcr">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=pcr">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=pcr">?</a></td>
<td style="text-align:left" class="comment">Set up <i>in silico</i> PCR reactions.  These can be used to filter genomes for tagging to specific repetitive loci.</td></tr>
HTML
	return $buffer;
}

sub _print_pcr_locus {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>PCR locus links</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=pcr_locus">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=pcr_locus">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=pcr_locus">?</a></td>
<td style="text-align:left" class="comment">Link a locus to an <i>in silico</i> PCR reaction.</td></tr>
HTML
	return $buffer;
}

sub _print_probes {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>nucleotide probes</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=probes">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=probes">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=probes">?</a></td>
<td style="text-align:left" class="comment">Define nucleotide probes for <i>in silico</i> hybridization reaction to filter genomes for tagging to specific repetitive loci.</td></tr>
HTML
	return $buffer;
}

sub _print_probe_locus {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>probe locus links</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=probe_locus">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=probe_locus">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=probe_locus">?</a></td>
<td style="text-align:left" class="comment">Link a locus to an <i>in silico</i> hybridization reaction.</td></tr>
HTML
	return $buffer;
}

sub _print_locus_aliases {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>locus aliases</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=locus_aliases">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=locus_aliases">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=locus_aliases">?</a></td>
<td style="text-align:left" class="comment">Add alternative names for loci.  These can also be set when you batch add loci.</td></tr>
HTML
	return $buffer;
}

sub _print_client_dbases {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>client databases</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=client_dbases">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=client_dbases">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=client_dbases">?</a></td>
<td style="text-align:left" class="comment">Add isolate databases that use locus allele or scheme profile definitions defined in this database - this enables
backlinks and searches of these databases when you query sequences or profiles in this database.</td></tr>
HTML
	return $buffer;
}

sub _print_client_dbase_loci_fields {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>client database fields linked to loci</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=client_dbase_loci_fields">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=client_dbase_loci_fields">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=client_dbase_loci_fields">?</a></td>
<td style="text-align:left" class="comment">Define fields in client database whose value can be displayed when isolate has matching allele.</td></tr>
HTML
	return $buffer;
}

sub _print_locus_extended_attributes {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>locus extended attributes</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=locus_extended_attributes">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=locus_extended_attributes">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=locus_extended_attributes">?</a></td>
<td style="text-align:left" class="comment">Define additional fields to associate with sequences of a particular locus.</td></tr>
HTML
	return $buffer;
}

sub _print_client_dbase_loci {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>client database loci</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=client_dbase_loci">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=client_dbase_loci">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=client_dbase_loci">?</a></td>
<td style="text-align:left" class="comment">Define loci that are used in client databases.</td></tr>
HTML
	return $buffer;
}

sub _print_client_dbase_schemes {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>client database schemes</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=client_dbase_schemes">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=client_dbase_schemes">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=client_dbase_schemes">?</a></td>
<td style="text-align:left" class="comment">Define schemes that are used in client databases. You will need to add the appropriate loci to the client database loci table.</td></tr>
HTML
	return $buffer;
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
	my $buffer = <<"HTML";
<tr class="td$td"><td>schemes</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=schemes">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=schemes">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=schemes">?</a></td>
<td style="text-align:left" class="comment">Describes schemes consisting of collections of loci, e.g. MLST.</td></tr>
HTML
	return $buffer;
}

sub _print_scheme_groups {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>scheme groups</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=scheme_groups">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=scheme_groups">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=scheme_groups">?</a></td>
<td style="text-align:left" class="comment">Describes groups in to which schemes can belong - groups can also belong to other groups.</td></tr>
HTML
	return $buffer;
}

sub _print_scheme_group_scheme_members {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>scheme group scheme members</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=scheme_group_scheme_members">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=scheme_group_scheme_members">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=scheme_group_scheme_members">?</a></td>
<td style="text-align:left" class="comment">Defines which schemes belong to a group.</td></tr>
HTML
	return $buffer;
}

sub _print_scheme_group_group_members {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>scheme group group members</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=scheme_group_group_members">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=scheme_group_group_members">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=scheme_group_group_members">?</a></td>
<td style="text-align:left" class="comment">Defines which scheme groups belong to a parent group.</td></tr>
HTML
	return $buffer;
}

sub _print_scheme_members {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>scheme members</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=scheme_members">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=scheme_members">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=scheme_members">?</a></td>
<td style="text-align:left" class="comment">Defines which loci belong to a scheme.</td></tr>
HTML
	return $buffer;
}

sub _print_scheme_fields {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>scheme fields</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=scheme_fields">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=scheme_fields">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=scheme_fields">?</a></td>
<td style="text-align:left" class="comment">Defines which fields belong to a scheme.</td></tr>
HTML
	return $buffer;
}

sub _print_isolate_user_acl {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>isolate user access control list</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=isolate_user_acl">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=isolate_user_acl">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=isolate_user_acl">?</a></td>
<td style="text-align:left" class="comment">Define which users can access or update specific isolate records.  It is usually easier to modify these controls by searching or browsing isolates and selecting the appropriate options.</td></tr>
HTML
	return $buffer;
}

sub _print_isolate_usergroup_acl {
	my ( $self, $td ) = @_;
	my $buffer = <<"HTML";
<tr class="td$td"><td>isolate user group access control list</td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=isolate_usergroup_acl">+</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=isolate_usergroup_acl">++</a></td>
<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=isolate_usergroup_acl">?</a></td>
<td style="text-align:left" class="comment">Define which usergroups can access or update specific isolate records. It is usually easier to modify these controls by searching or browsing isolates and selecting the appropriate options.</td></tr>
HTML
	return $buffer;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Curator's interface - $desc";
}
1;
