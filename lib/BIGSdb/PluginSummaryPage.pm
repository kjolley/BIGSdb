#Written by Keith Jolley
#Copyright (c) 2020, University of Oxford
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
package BIGSdb::PluginSummaryPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant CAT_ORDER => qw(breakdown export analysis third_party miscellaneous);

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my %allowed_categories = map { $_ => 1 } qw(analysis export);
	my $cat = $q->param('category') // q(all);
	if ( $allowed_categories{$cat} ) {
		my $display_cat = ucfirst($cat);
		say qq(<h1>$display_cat plugins</h1>);
	} else {
		say q(<h1>Plugins</h1>);
		$cat = 'all';
	}
	my $sub_cats = $self->_get_sub_cats($cat);
	if ( !keys %$sub_cats ) {
		$self->print_bad_status(
			{
				message => q(There are no plugins installed for this category.),
			}
		);
		return;
	}
	my $set_id = $self->get_set_id;
	say q(<div class="box" id="resultspanel">);
	$self->_print_anchor_list($sub_cats);
	foreach my $cat (CAT_ORDER) {
		next if !$sub_cats->{$cat};
		( my $display_cat = ucfirst($cat) ) =~ s/_/ /gx;
		if ( keys %$sub_cats > 1 ) {
			say qq(<a name="$cat"></a><h2>$display_cat</h2>);
		}
		my $plugin_names =
		  $self->{'pluginManager'}
		  ->get_appropriate_plugin_names( $cat, $self->{'system'}->{'dbtype'}, undef, { set_id => $set_id } );
		if ( @$plugin_names > 1 ) {
			my @links;
			foreach my $plugin_name (@$plugin_names) {
				my $plugin = $self->{'pluginManager'}->get_plugin_attributes($plugin_name);
				push @links, qq(<a href="#$plugin_name">$plugin->{'menutext'}</a>);
			}
			local $" = q( | );
			say qq(<p>$display_cat plugins - Jump to: @links</p>);
		}
		foreach my $plugin_name (@$plugin_names) {
			my $plugin = $self->{'pluginManager'}->get_plugin_attributes($plugin_name);
			say qq(<a name="$plugin_name"></a><h3>$plugin->{'menutext'}</h3>);
			say qq(<p>Summary: $plugin->{'description'}</p>)      if $plugin->{'description'};
			say qq(<p>$plugin->{'full_description'}</p>) if $plugin->{'full_description'};
			if ( $plugin->{'url'} ) {
				my $external_link = q();
				if ( ( lc( $plugin->{'url'} ) =~ /https?:\/\/(.*?)\/+/x ) ) {
					my $domain = $1;
					$external_link =
					    q( <span class="link">)
					  . qq($domain<span class="fa fas fa-external-link-alt" style="margin-left:0.5em"></span></span>);
				}
				say qq(<p><a href="$plugin->{'url'}" target="_blank">Documentation</a>$external_link</p>);
			}
			say qq(<p style="margin:2em 0"><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=plugin&amp;name=$plugin_name" class="launchbutton">Launch plugin</a></p>);
			if ( $plugin->{'image'} ) {
				say qq(<img class="plugin_image" src="$plugin->{'image'}" title="$plugin->{'menutext'}" />);
			}
		}
	}
	say q(</div>);
	return;
}

sub _print_anchor_list {
	my ( $self, $sub_cats ) = @_;
	return if keys %$sub_cats <= 1;
	my @list;
	foreach my $cat (CAT_ORDER) {
		( my $display_cat = ucfirst($cat) ) =~ s/_/ /gx;
		push @list, qq(<a href="#$cat">$display_cat</a>) if $sub_cats->{$cat};
	}
	local $" = q( | );
	say qq(<p>Categories - Jump to: @list</p>);
	return;
}

sub _get_sub_cats {
	my ( $self, $cat ) = @_;
	my %subcats = (
		export   => [qw(export)],
		analysis => [qw(breakdown analysis third_party)],
		all      => [qw(breakdown export analysis third_party miscellaneous)]
	);
	my $set_id         = $self->get_set_id;
	my $subcat_plugins = {};
	foreach my $subcat ( @{ $subcats{$cat} } ) {
		my $plugins =
		  $self->{'pluginManager'}
		  ->get_appropriate_plugin_names( $subcat, $self->{'system'}->{'dbtype'}, undef, { set_id => $set_id } );
		$subcat_plugins->{$subcat} = scalar @$plugins if @$plugins;
	}
	return $subcat_plugins;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description || 'BIGSdb';
	return qq(Plugin summary - $desc);
}
1;
