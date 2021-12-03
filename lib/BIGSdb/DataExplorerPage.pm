#Written by Keith Jolley
#Copyright (c) 2021, University of Oxford
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
#along with BIGSdb.  If not, see <https://www.gnu.org/licenses/>.
package BIGSdb::DataExplorerPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::DashboardPage);
use BIGSdb::Constants qw(RECORD_AGE);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $title = $self->get_title;
	say qq(<h1>$title</h1>);
	
	my $q = $self->{'cgi'};
	my $field = $q->param('field');
	if (!defined $field){
		$self->print_bad_status(
			{
				message  => q(No field specified.),
			}
		);
		return
	}
	my $display_field = $self->get_display_field($field);
	say q(<div class="box resultstable">);
	say qq(<h2>Field: $display_field</h2>);
	say q(<div class="scrollable">);
	say q(<table class="resultstable"><tr><th>Value</th><th>Frequency</th><th>Proportion</th></tr>);
	
	say q(</table>);
	say q(</div>);
	say q(</div>);
	return;
}

sub get_title {
	my ($self) = @_;
	return 'Data explorer';
}

sub initiate {
	my ($self) = @_;
	$self->{'jQuery'} = 1;
	$self->set_level1_breadcrumbs;
	return;
}

1;
