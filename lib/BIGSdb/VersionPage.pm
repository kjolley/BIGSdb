#Written by Keith Jolley
#Copyright (c) 2010-2022, University of Oxford
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
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

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
	return 'About BIGSdb';
}

sub print_about_bigsdb {
	my ($self) = @_;
	( my $version = $self->{'config'}->{'version'} ) =~ s/^v//x;
	say <<"HTML";
<div class="box resultspanel">
<h2>BIGSdb Version $version</h2>
<span class="main_icon far fa-copyright fa-3x fa-pull-left"></span>
<ul style="margin-left:3em">
<li>Written by Keith Jolley</li>
<li>Copyright &copy; University of Oxford, 2010-2022.</li>
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
<span class="main_icon fab fa-github fa-3x fa-pull-left"></span>
<ul style="margin-left:3em;padding-top:1em"><li>
Source code can be downloaded from <a href="https://github.com/kjolley/BIGSdb">
https://github.com/kjolley/BIGSdb</a>.
</li></ul>
<h2 style="margin-top:1.5em">Documentation</h2>
<span class="main_icon fas fa-book fa-3x fa-pull-left"></span>
<ul style="margin-left:3em">
<li>The home page for this software is  
<a href="https://pubmlst.org/software/bigsdb/" style="overflow-wrap:break-word">
https://pubmlst.org/software/bigsdb/</a>.</li>
<li>Full documentation can be found at <a href="https://bigsdb.readthedocs.io/">
https://bigsdb.readthedocs.io/</a>.</li></ul>
HTML
	if ( $self->{'config'}->{'jobs_db'} || ( $self->{'config'}->{'rest_db'} && $self->{'config'}->{'rest_log_to_db'} ) )
	{
		say q(<h2 style="margin-top:1.5em">Server status</h2>);
		say q(<span class="main_icon fas fa-tachometer-alt fa-3x fa-pull-left"></span>);
		my $buffer;
		my $links = 0;
		if ( $self->{'config'}->{'jobs_db'} ) {
			$buffer .= qq(<li><a href="$self->{'system'}->{'script_name'}?page=jobMonitor">Jobs monitor</a></li>);
			$links++;
		}
		if ( $self->{'config'}->{'rest_db'} && $self->{'config'}->{'rest_log_to_db'} ) {
			$buffer .= qq(<li><a href="$self->{'system'}->{'script_name'}?page=restMonitor">REST API monitor</a></li>);
			$links++;
		}
		my $margin = $links == 1 ? 2 : 1;
		say qq(<ul style="margin-left:3em;margin-top:${margin}em">);
		say $buffer;
		say q(</ul>);
	}
	if ( !$self->{'config'}->{'no_cookie_consent'} && $self->{'instance'} ) {
		say q(<h2 style="margin-top:1.5em">Cookies</h2>);
		say q(<span class="main_icon fas fa-cookie-bite fa-3x fa-pull-left"></span>);
		say q(<ul style="margin-left:3em;margin-top:1.5em">);
		say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=cookies">)
		  . q(Cookie policy</a></li>);
		say q(</ul>);
	}
	say q(</div>);
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
		my @authors;
		local $" = q(; <br />);
		if ( $attr->{'authors'} ) {
			foreach my $author_obj ( @{ $attr->{'authors'} } ) {
				my $author =
				  ( $author_obj->{'email'} // q() ) ne q()
				  ? qq(<a href="mailto:$author_obj->{'email'}">$author_obj->{'name'}</a>)
				  : $author_obj->{'name'};
				$author .= " ($author_obj->{'affiliation'})" if $author_obj->{'affiliation'};
				push @authors, $author;
			}
		}
		my $name       = defined $attr->{'url'} ? qq{<a href="$attr->{'url'}">$attr->{'name'}</a>} : $attr->{'name'};
		my $row_buffer = qq(<td>$name</td><td>@authors</td><td>$attr->{'description'}</td><td>$attr->{'version'}</td>);
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
		if ($enabled_buffer) {
			say q(<h3>Enabled plugins</h3>);
			say q(<table class="resultstable" style="text-align:left">);
			say q(<tr><th>Name</th><th>Author</th><th>Description</th><th>Version</th><th>Comments</th></tr>);
			say $enabled_buffer;
			say q(</table>);
		}
		say q(</div>);
		if ($disabled_buffer) {
			say q(<h3>Disabled plugins</h3>);
			say q(<div class="scrollable">);
			say q(<table class="resultstable" style="text-align:left">);
			say q(<tr><th>Name</th><th>Author</th><th>Description</th><th>Version</th><th>Disabled because</th></tr>);
			say $disabled_buffer;
			say q(</table>);
			say q(</div>);
		}
	}
	say q(</div>);
	return;
}

sub _reason_plugin_disabled {
	my ( $self, $attr ) = @_;
	if ( $attr->{'requires'} ) {
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
	my $blast_version = $self->_get_blast_version;
	if ($blast_version) {
		say qq(<li>BLAST: $blast_version</li>);
	}
	my $muscle_version = $self->_get_muscle_version;
	if ($muscle_version) {
		say qq(<li>MUSCLE: $muscle_version</li>);
	}
	my $mafft_version = $self->_get_mafft_version;
	if ($mafft_version) {
		say qq(<li>MAFFT: $mafft_version</li>);
	}
	say q(</ul>);
	say q(</div>);
	return;
}

sub _get_blast_version {
	my ($self) = @_;
	my $cmd = "$self->{'config'}->{'blast+_path'}/blastn -version";
	my $version_output;
	if ( $cmd =~ /^($self->{'config'}->{'blast+_path'}\/blastn\s\-version)/x ) {
		$version_output = `$1`;
	}
	if ( $version_output =~ /blastn:\s([\d\.\+]+)/x ) {
		return $1;
	}
	$logger->error('Cannot determine BLAST version');
	return;
}

sub _get_muscle_version {
	my ($self) = @_;
	return if !defined $self->{'config'}->{'muscle_path'};
	my $cmd = "$self->{'config'}->{'muscle_path'} -version";
	my $version_output;
	if ( $cmd =~ /^($self->{'config'}->{'muscle_path'}\s\-version)/x ) {
		$version_output = `$1`;
	}
	if ( $version_output =~ /MUSCLE\sv([\d\.]+)/x ) {
		return $1;
	}
	$logger->error('Cannot determine MUSCLE version');
	return;
}

sub _get_mafft_version {
	my ($self) = @_;
	return if !defined $self->{'config'}->{'mafft_path'};
	my $cmd = "$self->{'config'}->{'mafft_path'} --version 2>&1";
	my $version_output;
	if ( $cmd =~ /^($self->{'config'}->{'mafft_path'}\s\-\-version)/x ) {
		$version_output = `$1`;
	}
	if ( $version_output =~ /v([\d\.]+)/x ) {
		return $1;
	}
	$logger->error('Cannot determine MAFFT version');
	return;
}

sub initiate {
	my ($self) = @_;
	$self->{'jQuery'} = 1;
	$self->set_level1_breadcrumbs;
	return;
}
1;
