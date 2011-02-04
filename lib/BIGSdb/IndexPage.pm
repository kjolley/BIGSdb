#Written by Keith Jolley
#Copyright (c) 2010, University of Oxford
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
package BIGSdb::IndexPage;
use strict;
use base qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { 'general' => 0, 'main_display' => 0, 'isolate_display' => 0, 'analysis' => 0, 'query_field' => 0 };
}

sub print_content {
	my ($self)     = @_;
	my $desc       = $self->{'system'}->{'description'};
	my $scriptName = $self->{'system'}->{'script_name'};
	my $instance   = $self->{'instance'};
	my $system     = $self->{'system'};
	my $q          = $self->{'cgi'};
	print "<h1>Welcome to the $desc database</h1>";

	#Check if banner file exists, if so print it
	my $bannerfile = "$self->{'dbase_config_dir'}/$self->{'instance'}/banner.html";
	if ( -e $bannerfile ) {
		print "<div class=\"box\" id=\"banner\"><p>\n";
		$self->print_file($bannerfile);
		print "</p></div>\n";
	}
	print "<div class=\"box\" id=\"index\">\n";
	print "<div class=\"scrollable\">\n";
	print "<table><tr><td style=\"vertical-align:top\">";

	print "<img src=\"/images/icons/64x64/search.png\" alt=\"\" />\n";
	print "<h2>Query database</h2>\n";
	print "<ul class=\"toplevel\">\n";
	my $scheme_count_with_pk =
	  $self->{'datastore'}->run_simple_query(
"SELECT COUNT (DISTINCT schemes.id) FROM schemes RIGHT JOIN scheme_members ON schemes.id=scheme_members.scheme_id JOIN scheme_fields ON schemes.id=scheme_fields.scheme_id WHERE primary_key"
	  )->[0];
	my $qry =
	  $system->{'dbtype'} eq 'isolates'
	  ? "SELECT DISTINCT schemes.id,schemes.description FROM schemes RIGHT JOIN scheme_members ON schemes.id=scheme_members.scheme_id ORDER BY schemes.id"
	  : "SELECT DISTINCT schemes.id,schemes.description FROM schemes RIGHT JOIN scheme_members ON schemes.id=scheme_members.scheme_id JOIN scheme_fields ON schemes.id=scheme_fields.scheme_id WHERE primary_key ORDER BY schemes.id";
	my $scheme_data = $self->{'datastore'}->run_list_query_hashref($qry);
	my ( @scheme_ids, %desc );

	foreach (@$scheme_data) {
		push @scheme_ids, $_->{'id'};
		$desc{ $_->{'id'} } = $_->{'description'};
	}
	if ( $system->{'dbtype'} eq 'isolates' ) {
		print "<li><a href=\"$scriptName?page=query&amp;db=$instance\">Search database</a> - advanced queries.</li>\n
<li><a href=\"$scriptName?page=browse&amp;db=$instance\">Browse database</a> - peruse all records.</li>\n";
	} elsif ( $system->{'dbtype'} eq 'sequences' ) {
		print "<li><a href=\"$scriptName?db=$instance&amp;page=sequenceQuery\">Sequence query</a> - query an allele sequence.</li>";
		print
"<li><a href=\"$scriptName?db=$instance&amp;page=batchSequenceQuery\">Batch sequence query</a> - query multiple sequences in FASTA format.</li>\n";
		print "<li><a href=\"$scriptName?page=alleleQuery&amp;db=$instance\">Sequence attribute search</a> - find alleles by matching
	 attributes.</li>\n";
		if ( $scheme_count_with_pk == 1 ) {
			foreach (@$scheme_data) {
				print
"<li><a href=\"$scriptName?page=browse&amp;db=$instance&amp;scheme_id=$_->{'id'}\">Browse $_->{'description'} profiles</a></li>";
				print
"<li><a href=\"$scriptName?page=query&amp;db=$instance&amp;scheme_id=$_->{'id'}\">Search $_->{'description'} profiles</a></li>";
				print
"<li><a href=\"$scriptName?page=listQuery&amp;db=$instance&amp;scheme_id=$_->{'id'}\">List</a> - find $_->{'description'} profiles matched to entered list</li>";
				print
"<li><a href=\"$scriptName?page=batchProfiles&amp;db=$instance&amp;scheme_id=$_->{'id'}\">Batch profile query</a> - lookup $_->{'description'} profiles copied from a spreadsheet.</li>";
			}
		} elsif ( $scheme_count_with_pk > 1 ) {
			print "<li>Scheme profile queries:";
			print $q->start_form;
			print "<table>";
			print << "TOOLTIPS";
<tr><td />
<td style="text-align:center"><a class="tooltip" title="Browse - Peruse all records.">&nbsp;<i>i</i>&nbsp;</a></td>
<td style="text-align:center"><a class="tooltip" title="Search - Advanced searching.">&nbsp;<i>i</i>&nbsp;</a></td>
<td style="text-align:center"><a class="tooltip" title="List - Find matches to an entered list.">&nbsp;<i>i</i>&nbsp;</a></td>
<td style="text-align:center"><a class="tooltip" title="Profile query - Search by combinations of alleles</a> - including partial matching.">&nbsp;<i>i</i>&nbsp;</a></td>
<td style="text-align:center"><a class="tooltip" title="Batch profile query - Look up multiple profiles copied from a spreadsheet.">&nbsp;<i>i</i>&nbsp;</a></td>
</tr>				
TOOLTIPS
			print "<tr><td>";
			print $q->popup_menu( -name => 'scheme_id', -values => \@scheme_ids, -labels => \%desc );
			print $q->hidden('db');
			print "</td>\n";
			my %labels =
			  ( 'browse' => 'Browse', 'query' => 'Search', 'listQuery' => 'List', 'profiles' => 'Profiles', 'batchProfiles' => 'Batch' );
			foreach (qw (browse query listQuery profiles batchProfiles)) {
				print "<td>";
				print "<button type=\"submit\" name=\"page\" value=\"$_\" class=\"smallbutton\">$labels{$_}</button>\n";
				print "</td>\n";
			}
			print "</tr>\n";
			print "</table>";
			print $q->end_form;
			print "</li>\n";
		}
	}
	my $loci_defined = $self->{'datastore'}->run_simple_query("SELECT COUNT(id) FROM loci")->[0];
	if ($loci_defined) {
		if ( $system->{'dbtype'} eq 'isolates' ) {
			print "<li>Search by combinations of loci (profiles) - including partial matching.<ul>";
			my $scheme_count_with_members =
			  $self->{'datastore'}->run_simple_query(
				"SELECT COUNT (DISTINCT schemes.id) FROM schemes RIGHT JOIN scheme_members ON schemes.id=scheme_members.scheme_id")->[0];
			if ( $scheme_count_with_members > 1 ) {
				print "<li>";
				print $q->start_form;
				print $q->popup_menu( -name => 'scheme_id', -values => \@scheme_ids, -labels => \%desc );
				print $q->hidden('db');
				print " <button type=\"submit\" name=\"page\" value=\"profiles\" class=\"smallbutton\">Combinations</button>\n";
				print $q->end_form;
				print "</li>\n";
			} else {
				my $i = 0;
				my $buffer;
				foreach (@$scheme_data) {
					$desc =~ s/\&/\&amp;/g;
					$buffer .= $i ? '| ' : '<li>';
					$buffer .= "<a href=\"$scriptName?page=profiles&amp;scheme_id=$_->{'id'}&amp;db=$instance\">$_->{'description'}</a>\n";
					$i++;
				}
				$buffer .= "</li>" if $buffer;
				print $buffer;
			}
			print "<li><a href=\"$scriptName?page=profiles&amp;scheme_id=0&amp;db=$instance\">All loci</a></li>\n";
			print "</ul>\n</li>\n";
		} elsif ( $system->{'dbtype'} eq 'sequences' && $scheme_count_with_pk == 1 ) {
			my $buffer;
			my $first = 1;
			my $i     = 0;
			$buffer .=
"<li><a href=\"$scriptName?page=profiles&amp;db=$instance&amp;scheme_id=$scheme_data->[0]->{'id'}\">Search by combinations of $scheme_data->[0]->{'description'} alleles</a> - including partial matching.";
			$buffer .= "</li>" if $buffer;
			$buffer .= "</ul>\n</li>\n" if $buffer && $scheme_count_with_pk > 1;
			print $buffer;
		}
	}
	if ( $system->{'dbtype'} eq 'isolates' ) {
		print "<li><a href=\"$scriptName?page=listQuery&amp;db=$instance\">List query</a> - find isolates by matching
	 a field to an entered list.</li>\n";
		my $sample_fields = $self->{'xmlHandler'}->get_sample_field_list;
		if (@$sample_fields) {
			print
"<li><a href=\"$scriptName?page=tableQuery&amp;table=samples&amp;db=$instance\">Sample management</a> - culture/DNA storage tracking</li>\n";
		}
	}
	print "</ul>";
	if ( $system->{'dbtype'} eq 'sequences' ) {
		print "<img src=\"/images/icons/64x64/download.png\" alt=\"\" />\n";
		print "<h2>Downloads</h2>\n";
		my $group_count = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM scheme_groups")->[0];
		print "<ul class=\"toplevel\"><li><a href=\"$scriptName?page=downloadAlleles&amp;db=$instance"
		  . ( $group_count ? '&amp;tree=1' : '' )
		  . "\">Allele sequences</a></li>\n";
		my $buffer;
		my $first = 1;
		my $i     = 0;
		if ( $scheme_count_with_pk > 1 ) {
			$buffer .= "<li>";
			$buffer .= $q->start_form;
			$buffer .= $q->popup_menu( -name => 'scheme_id', -values => \@scheme_ids, -labels => \%desc );
			$buffer .= $q->hidden('db');
			$buffer .=
			  " <button type=\"submit\" name=\"page\" value=\"downloadProfiles\" class=\"smallbutton\">Download profiles</button>\n";
			$buffer .= $q->end_form;
		} elsif ( $scheme_count_with_pk == 1 ) {
			$buffer .=
"<li><a href=\"$scriptName?page=downloadProfiles&amp;db=$instance&amp;scheme_id=$scheme_data->[0]->{'id'}\">$scheme_data->[0]->{'description'} profiles</a>";
		}
		$buffer .= "</li>" if $buffer;
		print $buffer;
		print "</ul>\n";
	}
	print "</td><td style=\"vertical-align:top;padding-left:1em\">";
	print "<img src=\"/images/icons/64x64/preferences.png\" alt=\"\" />\n";
	print "
<h2>Option settings</h2>
<ul class=\"toplevel\">
<li><a href=\"$scriptName?page=options&amp;db=$instance\">
Set general options</a>";
	print " - including isolate table field handling" if $self->{'system'}->{'dbtype'} eq 'isolates';
	print "</li>\n";
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		print "<li>Set display and query options for 
<a href=\"$scriptName?page=tableQuery&amp;table=loci&amp;db=$instance\">locus</a>, 
<a href=\"$scriptName?page=tableQuery&amp;table=schemes&amp;db=$instance\">schemes</a> or 
<a href=\"$scriptName?page=tableQuery&amp;table=scheme_fields&amp;db=$instance\">scheme fields</a>.</li>";
	}
	print "</ul>\n";
	print "<img src=\"/images/icons/64x64/information.png\" alt=\"\" />\n";
	print "<h2>General statistics</h2>\n<ul class=\"toplevel\">\n";
	my $maxdate;
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $allele_count = $self->{'datastore'}->run_simple_query("SELECT COUNT (*) FROM sequences");
		foreach (qw (sequences profiles profile_refs accession)) {
			my $date = $self->{'datastore'}->run_simple_query("SELECT MAX(datestamp) FROM $_");
			if ( $date->[0] && $date->[0] gt $maxdate ) {
				$maxdate = $date->[0];
			}
		}
		print "<li>Number of sequences: $allele_count->[0]</li>";
		if ( $scheme_count_with_pk == 1 ) {
			foreach (@$scheme_data) {
				my $profile_count =
				  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM profiles WHERE scheme_id=?", $scheme_data->[0]->{'id'} )
				  ->[0];
				print "<li>Number of profiles ($scheme_data->[0]->{'description'}): $profile_count</li>\n";
			}
		} elsif ( $scheme_count_with_pk > 1 ) {
			print "<li>Number of profiles: <a id=\"toggle1\" class=\"showhide\">Show</a>\n";
			print "<a id=\"toggle2\" class=\"hideshow\">Hide</a><div class=\"hideshow\"><ul>";
			foreach (@$scheme_data) {
				my $profile_count =
				  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM profiles WHERE scheme_id=?", $_->{'id'} )->[0];
				$_->{'description'} =~ s/\&/\&amp;/g;
				print "<li>$_->{'description'}: $profile_count</li>\n";
			}
			print "</ul></div></li>\n";
		}
	} else {
		my $isolate_count = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM $self->{'system'}->{'view'}")->[0];
		foreach (qw (isolates isolate_aliases allele_designations pending_allele_designations allele_sequences refs loci)) {
			my $date = $self->{'datastore'}->run_simple_query("SELECT MAX(datestamp) FROM $_");
			if ( $date->[0] && $date->[0] gt $maxdate ) {
				$maxdate = $date->[0];
			}
		}
		print "<li>Isolates: $isolate_count ";
		print "</li>";
	}
	print "<li>Last updated: $maxdate</li>" if $maxdate;
	print "</ul>";
	print "</td></tr></table>\n";
	print "</div></div>\n";
	my $plugins = $self->{'pluginManager'}->get_appropriate_plugin_names( 'breakdown|export|analysis|miscellaneous', $system->{'dbtype'} );
	if (@$plugins) {
		print "<div class=\"box\" id=\"plugins\"><div class=\"scrollable\">\n<table><tr>";
		my $active_plugin;
		foreach (qw (breakdown export analysis miscellaneous)) {
			$q->param( 'page', 'index' );
			$plugins = $self->{'pluginManager'}->get_appropriate_plugin_names( $_, $system->{'dbtype'} );
			next if !@$plugins;
			my $buffer = "<td style=\"vertical-align:top\">\n";
			$buffer.= "<img src=\"/images/icons/64x64/$_.png\" alt=\"\" />\n";
			$buffer.= "<h2>" . ucfirst($_) . "</h2>\n<ul class=\"toplevel\">\n";
			foreach (@$plugins) {
				my $att      = $self->{'pluginManager'}->get_plugin_attributes($_);
				my $menuitem = $att->{'menutext'};
				if ( $system->{'dbtype'} eq 'sequences' && $att->{'seqdb_type'} eq 'schemes' ) {
					my $temp_buffer;
					my $first = 1;
					my $i     = 0;
					if ( $scheme_count_with_pk > 1 ) {
						$temp_buffer .= "<li>";
						$temp_buffer .= $q->start_form;
						$temp_buffer .= $q->popup_menu( -name => 'scheme_id', -values => \@scheme_ids, -labels => \%desc );
						$q->param( 'page', 'plugin' );
						foreach (qw (db page)) {
							$temp_buffer .= $q->hidden($_);
						}
						$temp_buffer .=
						  " <button type=\"submit\" name=\"name\" value=\"$att->{'module'}\" class=\"smallbutton\">$menuitem</button>\n";
						$temp_buffer .= $q->end_form;
						$temp_buffer .= "</li>\n";
						$active_plugin = 1;
					} elsif ( $scheme_count_with_pk == 1 ) {
						$temp_buffer .=
"<li><a href=\"$scriptName?page=plugin&amp;name=$att->{'module'}&amp;db=$instance&amp;scheme_id=$scheme_data->[0]->{'id'}\">$menuitem</a></li>";
						$active_plugin=1
					}
					$buffer.= $temp_buffer;
				} else {
					$buffer.= "<li><a href=\"$scriptName?db=$instance&amp;page=plugin&amp;name=$att->{'module'}\">$menuitem</a>";
					$buffer.= " - $att->{'menu_description'}" if $att->{'menu_description'};
					$buffer.= "</li>\n";
					$active_plugin=1
				}
			}
			$buffer.= "</ul>\n";
			$buffer.= "</td>\n";
			print $buffer if $active_plugin;
		}
		print "</tr></table>\n";
		print "</div>\n</div>\n";
	}
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return $desc;
}
1;
