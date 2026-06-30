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
	my $dir = "$self->{'lib_dir'}/BIGSdb/Plugins/HTML/$plugin";
	if ( !-d $dir ) {
		say q(<h1>Plugin viewer</h1>);
		return $self->print_bad_status( { message => q(Invalid plugin selected.) } );
	}
	say qq(<h1>$plugin viewer</h1>);
	my $function = $q->param('function');
	if ( !defined $function ) {
		opendir my $dh, $dir or $logger->error("Cannot open $dir for reading. $!");
		my @available;
		my @files  = readdir $dh;
		my $job_id = $q->param('job') // 'null';
		foreach my $file ( sort @files ) {
			next if $file =~ /^\./x;
			if ( $file =~ /(\w+)\.html$/x ) {
				my $function_name = $1;
				my $name          = ucfirst $function_name;
				push @available, qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=pluginViewer&amp;plugin=$plugin&amp;function=$function_name&amp;job=$job_id">$name</a>);

			}
		}
		closedir $dh;
		if ( !@available ) {
			$logger->error("No HTML template files available for $plugin.");
			return $self->print_bad_status( { message => qq(Function not passed for $plugin viewer.) } );
		}
		local $" = q(</li><li>);
		return $self->print_bad_status(
			{
				message => qq(Function not passed for $plugin viewer.),
				detail  => qq(Available functions are:<ul><li>@available</li></ul>)
			}
		);
	}
	if ( !-e "$self->{'lib_dir'}/BIGSdb/Plugins/HTML/$plugin/$function.html" ) {
		return $self->print_bad_status( { message => q(Viewer function not defined.) } );
	}
	my $content_ref = BIGSdb::Utils::slurp("$self->{'lib_dir'}/BIGSdb/Plugins/HTML/$plugin/$function.html");
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
