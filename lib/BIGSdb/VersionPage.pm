#Written by Keith Jolley
#Copyright (c) 2010-2017, University of Oxford
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
	$self->{'pref_requirements'} =
	  { general => 0, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub print_content {
	my ($self) = @_;
	say q(<h1>Bacterial Isolate Genome Sequence Database (BIGSdb)</h1>);
	$self->print_about_bigsdb;
	$self->_print_plugins;
	$self->_print_software_versions;
	return;
}

sub get_title {
	my ($self) = @_;
	return "BIGSdb Version $self->{'config'}->{'version'}";
}

sub print_about_bigsdb {
	my ($self) = @_;
	( my $version = $self->{'config'}->{'version'} ) =~ s/^v//x;
	say <<"HTML";
<div class="box resultspanel">
<h2>BIGSdb Version $version</h2>
<span class="main_icon fa fa-copyright fa-3x pull-left"></span>
<ul style="margin-left:1em">
<li>Written by Keith Jolley</li>
<li>Copyright &copy; University of Oxford, 2010-2017.</li>
<li><a href="http://www.biomedcentral.com/1471-2105/11/595">
Jolley &amp; Maiden <i>BMC Bioinformatics</i> 2010, <b>11:</b>595</a></li>
</ul>
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
can be found at <a href="http://www.gnu.org/licenses/gpl.html">
http://www.gnu.org/licenses/gpl.html</a>.</p>
<span class="main_icon fa fa-github fa-3x pull-left"></span>
<ul style="margin-left:1em;padding-top:1em"><li>
Source code can be downloaded from <a href="https://github.com/kjolley/BIGSdb">
https://github.com/kjolley/BIGSdb</a>.
</li></ul>
<h2>Documentation</h2>
<span class="main_icon fa fa-book fa-3x pull-left"></span>
<ul style="margin-left:1em">
<li>The home page for this software is  
<a href="https://pubmlst.org/software/database/bigsdb/">
https://pubmlst.org/software/database/bigsdb/</a>.</li>
<li>Full documentation can be found at <a href="http://bigsdb.readthedocs.io/">
http://bigsdb.readthedocs.io/</a>.</li></ul>
</div>
HTML
	return;
}

sub _print_plugins {
	my ($self) = @_;
	say q(<div class="box resultstable">);
	say q(<h2>Installed plugins</h2>);
	my $plugins = $self->{'pluginManager'}->get_installed_plugins;
	if ( !keys %{$plugins} ) {
		say q(<p>No plugins installed</p>);
		return;
	}
	say q(<p>Plugins may be disabled by the system administrator for specific databases where either )
	  . q(they're not appropriate or if they may take up too many resources on a public database.</p>);
	my ( $enabled_buffer, $disabled_buffer, %disabled_reason );
	my $etd = 1;
	my $dtd = 1;
	foreach my $plugin ( sort { $a cmp $b } keys %{$plugins} ) {
		my $attr = $plugins->{$plugin};
		$disabled_reason{$plugin} = $self->_reason_plugin_disabled($attr);
		foreach my $att (qw(min max)) {
			next if !defined $attr->{$att};
			$attr->{$att} = BIGSdb::Utils::commify( $attr->{$att} );
		}
		my $comments = '';
		if ( defined $attr->{'min'} && defined $attr->{'max'} ) {
			$comments .= "Limited to queries with between $attr->{'min'} and $attr->{'max'} results.";
		} elsif ( defined $attr->{'min'} ) {
			$comments .= "Limited to queries with at least $attr->{'min'} results.";
		} elsif ( defined $attr->{'max'} ) {
			$comments .= "Limited to queries with fewer than $attr->{'max'} results.";
		}
		my $author = defined $attr->{'email'}
		  && $attr->{'email'} ne '' ? qq(<a href="mailto:$attr->{'email'}">$attr->{'author'}</a>) : $attr->{'author'};
		$author .= " ($attr->{'affiliation'})" if $attr->{'affiliation'};
		my $name = defined $attr->{'url'} ? "<a href=\"$attr->{'url'}\">$attr->{'name'}</a>" : $attr->{'name'};
		my $row_buffer = qq(<td>$name</td><td>$author</td><td>$attr->{'description'}</td><td>$attr->{'version'}</td>);
		if ( $disabled_reason{$plugin} ) {
			$disabled_buffer .= qq(<tr class="td$dtd">$row_buffer<td>$disabled_reason{$plugin}</td></tr>);
			$dtd = $dtd == 1 ? 2 : 1;
		} else {
			$enabled_buffer .= qq(<tr class="td$etd">$row_buffer<td>$comments</td></tr>);
			$etd = $etd == 1 ? 2 : 1;
		}
	}
	if ( $enabled_buffer || $disabled_buffer ) {
		say q(<div class="scrollable">);
		say q(<table class="resultstable">);
		if ($enabled_buffer) {
			say q(<tr><th colspan="5">Enabled plugins</th></tr>);
			say q(<tr><th>Name</th><th>Author</th><th>Description</th><th>Version</th><th>Comments</th></tr>);
			say $enabled_buffer;
		}
		if ($disabled_buffer) {
			say q(<tr><th colspan="5">Disabled plugins</th></tr>);
			say q(<tr><th>Name</th><th>Author</th><th>Description</th><th>Version</th><th>Disabled because</th></tr>);
			say $disabled_buffer;
		}
		say q(</table></div>);
	}
	say q(</div>);
	return;
}

sub _reason_plugin_disabled {
	my ( $self, $attr ) = @_;
	if ( $attr->{'requires'} ) {
		return 'Chartdirector not installed.'
		  if !$self->{'config'}->{'chartdirector'} && $attr->{'requires'} =~ /chartdirector/;
		return 'Reference database not configured.'
		  if !$self->{'config'}->{'ref_db'}
		  && $attr->{'requires'} =~ /ref_?db/x;
		return 'Offline job manager not running.'
		  if !$self->{'config'}->{'jobs_db'}
		  && $attr->{'requires'} =~ /offline_jobs/;
		my %program_name =
		  ( emboss => 'EMBOSS', mafft => 'MAFFT', muscle => 'MUSCLE', mogrify => 'ImageMagick mogrify' );
		foreach my $program (qw(emboss muscle mogrify)) {
			return "$program_name{$program} not installed."
			  if !$self->{'config'}->{"${program}_path"}
			  && $attr->{'requires'} =~ /$program/x;
		}
		return 'Aligner (MUSCLE or MAFFT) not installed.'
		  if !$self->{'config'}->{'muscle_path'}
		  && !$self->{'config'}->{'mafft_path'}
		  && $attr->{'requires'} =~ /aligner/x;
	}
	my $dbtype = $self->{'system'}->{'dbtype'};
	return 'Only for ' . ( $dbtype eq 'isolates' ? 'seqdef' : 'isolate' ) . ' databases.'
	  if $attr->{'dbtype'} !~ /$dbtype/x;
	return 'Not specifically enabled for this database.'
	  if (
		   !( ( $self->{'system'}->{'all_plugins'} // '' ) eq 'yes' )
		&& $attr->{'system_flag'}
		&& (  !$self->{'system'}->{ $attr->{'system_flag'} }
			|| $self->{'system'}->{ $attr->{'system_flag'} } eq 'no' )
	  );
	return;
}

sub _print_software_versions {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box resultspanel">);
	say q(<h2>Software versions</h2>);
	my $pg_version = $self->{'datastore'}->run_query('SELECT version()');
	say q(<ul>);
	say qq(<li>Perl $]</li>);
	say qq(<li>$pg_version</li>);
	my $apache = $q->server_software;
	say qq(<li>$apache</li>);

	if ( $ENV{'MOD_PERL'} ) {
		say qq(<li>$ENV{'MOD_PERL'}</li>);
	}
	say q(</ul>);
	say q(</div>);
	return;
}
1;
