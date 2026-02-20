#Written by Keith Jolley
#Copyright (c) 2026, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
package BIGSdb::PluginViewerPage;
use strict;
use warnings;
use 5.010;
use parent        qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $plugin = $q->param('plugin');
	if ( !$plugin ) {
		say q(<h1>Plugin viewer</h1>);
		return $self->print_bad_status( { message => q(No plugin selected.) } );
	}
	if (  !-e "$self->{'lib_dir'}/BIGSdb/Plugins/HTML/$plugin.html" ) {
		say q(<h1>Plugin viewer</h1>);
		return $self->print_bad_status( { message => q(Invalid plugin selected.) } );
	}
	say qq(<h1>$plugin viewer</h1>);
	my $content_ref = BIGSdb::Utils::slurp("$self->{'lib_dir'}/BIGSdb/Plugins/HTML/$plugin.html");
	say $$content_ref;
	return;
}

sub get_title {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $plugin = $q->param('plugin');
	if ( $plugin && -e "$self->{'lib_dir'}/BIGSdb/Plugins/HTML/$plugin.html" ) {
		return "$plugin viewer";
	}
	return 'BIGSdb plugin viewer';
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery allowExpand);
	$self->set_level1_breadcrumbs;
	return;
}

1;
