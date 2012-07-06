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
package BIGSdb::IndexPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub initiate {
	my ($self) = @_;
	$self->{'jQuery'} = 1;
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $set_id = $self->get_set_id;
		my $scheme_data = $self->{'datastore'}->get_scheme_list( { with_pk => 1, set_id => $set_id } );
		$self->{'tooltips'} = 1 if @$scheme_data > 1;
	}
	return;
}

sub print_content {
	my ($self)      = @_;
	my $script_name = $self->{'system'}->{'script_name'};
	my $instance    = $self->{'instance'};
	my $system      = $self->{'system'};
	my $q           = $self->{'cgi'};
	my $desc        = $self->get_db_description;
	say "<h1>Welcome to the $desc database</h1>";
	$self->print_banner;
	print << "HTML";
<div class="box" id="index">
<div class="scrollable">
<div style="float:left;margin-right:1em">
<img src="/images/icons/64x64/search.png" alt="" />
<h2>Query database</h2>
<ul class="toplevel">
HTML
	my $set_id = $self->get_set_id;
	my $scheme_data =
	  $self->{'datastore'}->get_scheme_list( { with_pk => ( $self->{'system'}->{'dbtype'} eq 'sequences' ? 1 : 0 ), set_id => $set_id } );
	my ( $scheme_ids_ref, $desc_ref ) = $self->extract_scheme_desc($scheme_data);

	if ( $system->{'dbtype'} eq 'isolates' ) {
		say "<li><a href=\"$script_name?db=$instance&amp;page=query\">Search database</a> - advanced queries.</li>\n"
		  . "<li><a href=\"$script_name?db=$instance&amp;page=browse\">Browse database</a> - peruse all records.</li>";
	} elsif ( $system->{'dbtype'} eq 'sequences' ) {
		say "<li><a href=\"$script_name?db=$instance&amp;page=sequenceQuery\">Sequence query</a> - query an allele sequence.</li>\n"
		  . "<li><a href=\"$script_name?db=$instance&amp;page=batchSequenceQuery\">Batch sequence query</a> - query multiple sequences "
		  . "in FASTA format.</li>\n"
		  . "<li><a href=\"$script_name?db=$instance&amp;page=alleleQuery\">Sequence attribute search</a> - find alleles by matching "
		  . "attributes.</li>";
		if ( @$scheme_data == 1 ) {
			foreach (@$scheme_data) {
				print <<"HTML";
<li><a href="$script_name?db=$instance&amp;page=browse&amp;scheme_id=$_->{'id'}">Browse $_->{'description'} profiles</a></li>
<li><a href="$script_name?db=$instance&amp;page=query&amp;scheme_id=$_->{'id'}">Search $_->{'description'} profiles</a></li>
<li><a href="$script_name?db=$instance&amp;page=listQuery&amp;scheme_id=$_->{'id'}">List</a> - find $_->{'description'} 
profiles matched to entered list</li>
<li><a href="$script_name?db=$instance&amp;page=batchProfiles&amp;scheme_id=$_->{'id'}">Batch profile query</a> - lookup 
$_->{'description'} profiles copied from a spreadsheet.</li>
HTML
			}
		} elsif ( @$scheme_data > 1 ) {
			say "<li>Scheme profile queries:";
			say $q->start_form;
			say "<table>";
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
			say $q->popup_menu( -name => 'scheme_id', -values => $scheme_ids_ref, -labels => $desc_ref );
			say $q->hidden('db');
			say "</td>";
			my %labels = ( browse => 'Browse', query => 'Search', listQuery => 'List', profiles => 'Profiles', batchProfiles => 'Batch' );

			foreach (qw (browse query listQuery profiles batchProfiles)) {
				say "<td><button type=\"submit\" name=\"page\" value=\"$_\" class=\"smallbutton\">$labels{$_}</button></td>";
			}
			say "</tr>\n</table>";
			say $q->end_form;
			say "</li>";
		}
	}
	if ( $self->{'config'}->{'jobs_db'} ) {
		my $query_html_file = "$self->{'system'}->{'dbase_config_dir'}/$self->{'instance'}/contents/job_query.html";
		$self->print_file($query_html_file) if -e $query_html_file;
	}
	if ( $self->_are_loci_defined ) {
		if ( $system->{'dbtype'} eq 'isolates' ) {
			print "<li>Search by combinations of loci (profiles) - including partial matching.<ul>";
			if ( @$scheme_data > 1 ) {
				say '<li>';
				say $q->start_form;
				say $q->popup_menu( -name => 'scheme_id', -values => $scheme_ids_ref, -labels => $desc_ref );
				say $q->hidden('db');
				say " <button type=\"submit\" name=\"page\" value=\"profiles\" class=\"smallbutton\">Combinations</button>\n";
				say $q->end_form;
				say '</li>';
			} else {
				my $i = 0;
				my $buffer;
				foreach (@$scheme_data) {
					$desc =~ s/\&/\&amp;/g;
					$buffer .= $i ? '| ' : '<li>';
					$buffer .= "<a href=\"$script_name?db=$instance&amp;page=profiles&amp;scheme_id=$_->{'id'}\">$_->{'description'}</a>\n";
					$i++;
				}
				$buffer .= "</li>" if $buffer;
				say $buffer if $buffer;
			}
			say "<li><a href=\"$script_name?db=$instance&amp;page=profiles&amp;scheme_id=0\">All loci</a></li>";
			say "</ul>\n</li>";
		} elsif ( $system->{'dbtype'} eq 'sequences' && @$scheme_data == 1 ) {
			my $buffer;
			my $first = 1;
			my $i     = 0;
			$buffer .= "<li><a href=\"$script_name?db=$instance&amp;page=profiles&amp;scheme_id=$scheme_data->[0]->{'id'}\">"
			  . "Search by combinations of $scheme_data->[0]->{'description'} alleles</a> - including partial matching.";
			$buffer .= "</li>" if $buffer;
			$buffer .= "</ul>\n</li>" if $buffer && @$scheme_data > 1;
			say $buffer;
		}
	}
	if ( $system->{'dbtype'} eq 'isolates' ) {
		say "<li><a href=\"$script_name?db=$instance&amp;page=listQuery\">List query</a> - find isolates by matching "
		  . "a field to an entered list.</li>";
		my $sample_fields = $self->{'xmlHandler'}->get_sample_field_list;
		if (@$sample_fields) {
			say "<li><a href=\"$script_name?db=$instance&amp;page=tableQuery&amp;table=samples\">"
			  . "Sample management</a> - culture/DNA storage tracking</li>";
		}
	}
	say "</ul></div>";
	$self->_print_download_section($scheme_data) if $system->{'dbtype'} eq 'sequences';
	$self->_print_options_section;
	$self->_print_general_info_section($scheme_data);
	say "</div></div>";
	$self->_print_plugin_section($scheme_data);
	return;
}

sub _print_download_section {
	my ( $self,           $scheme_data ) = @_;
	my ( $scheme_ids_ref, $desc_ref )    = $self->extract_scheme_desc($scheme_data);
	my $q                   = $self->{'cgi'};
	my $seq_download_buffer = '';
	my $scheme_buffer       = '';
	my $group_count         = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM scheme_groups")->[0];
	if ( !( $self->{'system'}->{'disable_seq_downloads'} && $self->{'system'}->{'disable_seq_downloads'} eq 'yes' ) || $self->is_admin ) {
		$seq_download_buffer =
		    "<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadAlleles"
		  . ( $group_count ? '&amp;tree=1' : '' )
		  . "\">Allele sequences</a></li>\n";
	}
	my $first = 1;
	my $i     = 0;
	if ( @$scheme_data > 1 ) {
		$scheme_buffer .= "<li>";
		$scheme_buffer .= $q->start_form;
		$scheme_buffer .= $q->popup_menu( -name => 'scheme_id', -values => $scheme_ids_ref, -labels => $desc_ref );
		$scheme_buffer .= $q->hidden('db');
		$scheme_buffer .=
		  " <button type=\"submit\" name=\"page\" value=\"downloadProfiles\" class=\"smallbutton\">Download profiles</button>\n";
		$scheme_buffer .= $q->end_form;
		$scheme_buffer .= "</li>";
	} elsif ( @$scheme_data == 1 ) {
		$scheme_buffer .= "<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadProfiles&amp;scheme_id="
		  . "$scheme_data->[0]->{'id'}\">$scheme_data->[0]->{'description'} profiles</a></li>";
	}
	if ( $seq_download_buffer || $scheme_buffer ) {
		print << "DOWNLOADS";
<div style="float:left; margin-right:1em">
<img src="/images/icons/64x64/download.png" alt="" />
<h2>Downloads</h2>
<ul class="toplevel">
$seq_download_buffer
$scheme_buffer
</ul>	
</div>
DOWNLOADS
	}
	return;
}

sub _print_options_section {
	my ($self) = @_;
	print << "OPTIONS";
<div style="float:left; margin-right:1em">
<img src="/images/icons/64x64/preferences.png" alt="" />
<h2>Option settings</h2>
<ul class="toplevel">
<li><a href="$self->{'system'}->{'script_name'}?page=options&amp;db=$self->{'instance'}">
Set general options</a>
OPTIONS
	say " - including isolate table field handling" if $self->{'system'}->{'dbtype'} eq 'isolates';
	say "</li>";
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say "<li>Set display and query options for <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;"
		  . "page=tableQuery&amp;table=loci\">locus</a>, <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;"
		  . "page=tableQuery&amp;table=schemes\">schemes</a> or <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;"
		  . "page=tableQuery&amp;table=scheme_fields\">scheme fields</a>.</li>";
	}
	say "</ul>\n</div>";
	return;
}

sub _print_general_info_section {
	my ( $self, $scheme_data ) = @_;
	say "<div style=\"float:left; margin-right:1em\">";
	say "<img src=\"/images/icons/64x64/information.png\" alt=\"\" />";
	say "<h2>General information</h2>\n<ul class=\"toplevel\">";
	my $max_date;
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $allele_count = $self->_get_allele_count;
		my $tables       = [qw (sequences profiles profile_refs accession)];
		$max_date = $self->_get_max_date($tables);
		say "<li>Number of sequences: $allele_count</li>";
		if ( @$scheme_data == 1 ) {
			foreach (@$scheme_data) {
				my $profile_count =
				  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM profiles WHERE scheme_id=?", $scheme_data->[0]->{'id'} )
				  ->[0];
				say "<li>Number of profiles ($scheme_data->[0]->{'description'}): $profile_count</li>";
			}
		} elsif ( @$scheme_data > 1 ) {
			say "<li>Number of profiles: <a id=\"toggle1\" class=\"showhide\">Show</a>";
			say "<a id=\"toggle2\" class=\"hideshow\">Hide</a><div class=\"hideshow\"><ul>";
			foreach (@$scheme_data) {
				my $profile_count =
				  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM profiles WHERE scheme_id=?", $_->{'id'} )->[0];
				$_->{'description'} =~ s/\&/\&amp;/g;
				say "<li>$_->{'description'}: $profile_count</li>";
			}
			say "</ul></div></li>";
		}
	} else {
		my $isolate_count = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM $self->{'system'}->{'view'}")->[0];
		my @tables        = qw (isolates isolate_aliases allele_designations pending_allele_designations allele_sequences refs);
		$max_date = $self->_get_max_date( \@tables );
		print "<li>Isolates: $isolate_count</li>";
	}
	say "<li>Last updated: $max_date</li>" if $max_date;
	say "<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=version\">About BIGSdb</a></li>";
	say "</ul>\n</div>";
	return;
}

sub _print_plugin_section {
	my ( $self,           $scheme_data ) = @_;
	my ( $scheme_ids_ref, $desc_ref )    = $self->extract_scheme_desc($scheme_data);
	my $q = $self->{'cgi'};
	my $set_id = $self->get_set_id;
	my $plugins =
	  $self->{'pluginManager'}->get_appropriate_plugin_names( 'breakdown|export|analysis|miscellaneous', $self->{'system'}->{'dbtype'},{ set_id => $set_id } );
	if (@$plugins) {
		print "<div class=\"box\" id=\"plugins\"><div class=\"scrollable\">\n";
		my $active_plugin;
		foreach (qw (breakdown export analysis miscellaneous)) {
			$q->param( 'page', 'index' );
			$plugins = $self->{'pluginManager'}->get_appropriate_plugin_names( $_, $self->{'system'}->{'dbtype'},{ set_id => $set_id } );
			next if !@$plugins;
			my $buffer = "<div style=\"float:left; margin-right:1em\">\n";
			$buffer .= "<img src=\"/images/icons/64x64/$_.png\" alt=\"\" />\n";
			$buffer .= "<h2>" . ucfirst($_) . "</h2>\n<ul class=\"toplevel\">\n";
			foreach (@$plugins) {
				my $att      = $self->{'pluginManager'}->get_plugin_attributes($_);
				my $menuitem = $att->{'menutext'};
				if ( $self->{'system'}->{'dbtype'} eq 'sequences' && $att->{'seqdb_type'} eq 'schemes' ) {
					my $temp_buffer;
					my $first = 1;
					my $i     = 0;
					if ( @$scheme_data > 1 ) {
						$temp_buffer .= "<li>";
						$temp_buffer .= $q->start_form;
						$temp_buffer .= $q->popup_menu( -name => 'scheme_id', -values => $scheme_ids_ref, -labels => $desc_ref );
						$q->param( 'page', 'plugin' );
						$temp_buffer .= $q->hidden($_) foreach qw (db page);
						$temp_buffer .=
						  " <button type=\"submit\" name=\"name\" value=\"$att->{'module'}\" class=\"smallbutton\">$menuitem</button>\n";
						$temp_buffer .= $q->end_form;
						$temp_buffer .= "</li>\n";
						$active_plugin = 1;
					} elsif ( @$scheme_data == 1 ) {
						$temp_buffer .= "<li><a href=\"$self->{'system'}->{'script_name'}?page=plugin&amp;name=$att->{'module'}&amp;"
						  . "db=$self->{'instance'}&amp;scheme_id=$scheme_data->[0]->{'id'}\">$menuitem</a></li>";
						$active_plugin = 1;
					}
					$buffer .= $temp_buffer if $temp_buffer;
				} else {
					$buffer .= "<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;"
					  . "name=$att->{'module'}\">$menuitem</a>";
					$buffer .= " - $att->{'menu_description'}" if $att->{'menu_description'};
					$buffer .= "</li>\n";
					$active_plugin = 1;
				}
			}
			$buffer .= "</ul>\n</div>";
			say $buffer if $active_plugin;
		}
		say "</div>\n</div>";
	}
	return;
}

sub _get_max_date {
	my ( $self, $tables ) = @_;
	local $" = ' UNION SELECT MAX(datestamp) FROM ';
	my $qry          = "SELECT MAX(max_datestamp) FROM (SELECT MAX(datestamp) AS max_datestamp FROM @$tables) AS v";
	my $max_date_ref = $self->{'datastore'}->run_simple_query($qry);
	return ref $max_date_ref eq 'ARRAY' ? $max_date_ref->[0] : undef;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description || 'BIGSdb';
	return $desc;
}

sub _get_allele_count {
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? " WHERE locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE "
	  . "set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id)"
	  : '';
	return $self->{'datastore'}->run_simple_query("SELECT COUNT (*) FROM sequences$set_clause")->[0];
}

sub _are_loci_defined {
	my ($self) = @_;
	my $qry;
	my $set_id = $self->get_set_id;
	if ($set_id) {
		$qry =
		    "SELECT EXISTS(SELECT loci.id FROM loci LEFT JOIN set_loci ON loci.id = set_loci.locus "
		  . "WHERE id IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE "
		  . "set_id=$set_id)) OR id IN (SELECT locus FROM set_loci WHERE set_id=$set_id))";
	} else {
		$qry = "SELECT EXISTS(SELECT id FROM loci)";
	}
	return $self->{'datastore'}->run_simple_query($qry)->[0];
}
1;
