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
package BIGSdb::VersionPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { general => 0, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub print_content {
	my ($self) = @_;
	print <<"HTML";

<h1>Bacterial Isolate Genome Sequence Database (BIGSdb)</h1>
<div class="box" id="resultstable">
<h2>Version $BIGSdb::main::VERSION</h2>
<p>Written by Keith Jolley<br />
Copyright &copy; University of Oxford, 2010-2013.<br />
<a href="http://www.biomedcentral.com/1471-2105/11/595">Jolley &amp; Maiden <i>BMC Bioinformatics</i> 2010, <b>11:</b>595</a></p>
<p>
BIGSdb is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.</p>

<p>BIGSdb is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.</p>

<p>Full details of the GNU General Public License
can be found at <a href="http://www.gnu.org/licenses/gpl.html">http://www.gnu.org/licenses/gpl.html</a>.</p>

<p>Details of this software and the latest version can be downloaded from 
<a href="http://pubmlst.org/software/database/bigsdb/">
http://pubmlst.org/software/database/bigsdb/</a>.</p>
HTML
	$self->_print_plugins;
	say "</div>";
	return;
}

sub get_title {
	return "BIGSdb Version $BIGSdb::main::VERSION";
}

sub _print_plugins {
	my ($self) = @_;
	say "<h2>Installed plugins</h2>";
	my $plugins = $self->{'pluginManager'}->get_installed_plugins;
	if ( !keys %{$plugins} ) {
		say "<p>No plugins installed</p>";
		return;
	}
	say "<p>Plugins may be disabled by the system administrator for specific databases where either they're not appropriate"
	  . " or if they may take up too many resources on a public database.</p>";
	my ( $enabled_buffer, $disabled_buffer, %disabled_reason );
	my $dbtype = $self->{'system'}->{'dbtype'};
	my $etd    = 1;
	my $dtd    = 1;
	foreach ( sort { $a cmp $b } keys %{$plugins} ) {
		my $attr = $plugins->{$_};
		if ( $attr->{'requires'} ) {
			$disabled_reason{$_} = 'Chartdirector not installed.'
			  if !$self->{'config'}->{'chartdirector'}
				  && $attr->{'requires'} =~ /chartdirector/;
			$disabled_reason{$_} = 'Reference database not configured.'
			  if !$self->{'config'}->{'ref_db'}
				  && $attr->{'requires'} =~ /ref_?db/;
			$disabled_reason{$_} = 'EMBOSS not installed.'
			  if !$self->{'config'}->{'emboss_path'}
				  && $attr->{'requires'} =~ /emboss/;
			$disabled_reason{$_} = 'MUSCLE not installed.'
			  if !$self->{'config'}->{'muscle_path'}
				  && $attr->{'requires'} =~ /muscle/;
			$disabled_reason{$_} = 'ImageMagick mogrify not installed.'
			  if !$self->{'config'}->{'mogrify_path'}
				  && $attr->{'requires'} =~ /mogrify/;
			$disabled_reason{$_} = 'Offline job manager not running.'
			  if !$self->{'config'}->{'jobs_db'}
				  && $attr->{'requires'} =~ /offline_jobs/;
		}
		$disabled_reason{$_} = 'Not specifically enabled for this database.'
		  if (
			   !( ( $self->{'system'}->{'all_plugins'} // '' ) eq 'yes' )
			&& $attr->{'system_flag'}
			&& (  !$self->{'system'}->{ $attr->{'system_flag'} }
				|| $self->{'system'}->{ $attr->{'system_flag'} } eq 'no' )
		  );
		$disabled_reason{$_} = 'Only for ' . ( $dbtype eq 'isolates' ? 'seqdef' : 'isolate' ) . ' databases.'
		  if $attr->{'dbtype'} !~ /$dbtype/;
		my $comments = '';
		if ( defined $attr->{'min'} && defined $attr->{'max'} ) {
			$comments .= "Limited to queries with between $attr->{'min'} and $attr->{'max'} results.";
		} elsif ( defined $attr->{'min'} ) {
			$comments .= "Limited to queries with at least $attr->{'min'} results.";
		} elsif ( defined $attr->{'max'} ) {
			$comments .= "Limited to queries with fewer than $attr->{'max'} results.";
		}
		my $author =
		  defined $attr->{'email'}
		  && $attr->{'email'} ne '' ? "<a href=\"mailto:$attr->{'email'}\">$attr->{'author'}</a>" : $attr->{'author'};
		$author .= " ($attr->{'affiliation'})" if $attr->{'affiliation'};
		my $name = defined $attr->{'url'} ? "<a href=\"$attr->{'url'}\">$attr->{'name'}</a>" : $attr->{'name'};
		my $row_buffer = "<td>$name</td><td>$author</td><td>$attr->{'description'}</td><td>$attr->{'version'}</td>";
		if ( $disabled_reason{$_} ) {
			$disabled_buffer .= "<tr class=\"td$dtd\">$row_buffer<td>$disabled_reason{$_}</td></tr>";
			$dtd = $dtd == 1 ? 2 : 1;
		} else {
			$enabled_buffer .= "<tr class=\"td$etd\">$row_buffer<td>$comments</td></tr>";
			$etd = $etd == 1 ? 2 : 1;
		}
	}
	if ( $enabled_buffer || $disabled_buffer ) {
		say "<table class=\"resultstable\">";
		if ($enabled_buffer) {
			say "<tr><th colspan=\"5\">Enabled plugins</th></tr>";
			say "<tr><th>Name</th><th>Author</th><th>Description</th><th>Version</th><th>Comments</th></tr>";
			say $enabled_buffer;
		}
		if ($disabled_buffer) {
			say "<tr><th colspan=\"5\">Disabled plugins</th></tr>";
			say "<tr><th>Name</th><th>Author</th><th>Description</th><th>Version</th><th>Disabled because</th></tr>";
			say $disabled_buffer;
		}
		say "</table>";
	}
	return;
}
1;
