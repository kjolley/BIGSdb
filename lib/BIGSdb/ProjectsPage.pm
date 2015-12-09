#Written by Keith Jolley
#Copyright (c) 2014-2015, University of Oxford
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
package BIGSdb::ProjectsPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery jQuery.tablesort);
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	say "<h1>Main projects defined in the $desc database</h1>";
	my $projects = $self->{'datastore'}->run_query(
		'SELECT * FROM projects WHERE list AND id IN (SELECT project_id FROM project_members WHERE isolate_id IN '
		  . "(SELECT id FROM $self->{'system'}->{'view'})) ORDER BY id",
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
	if ( !@$projects ) {
		say q(<div class="box" id="statusbad"><p>There are no listable projects defined in this database.</p></div>);
		return;
	}
	say q(<div class="box" id="resultstable"><div class="scrollable">);
	say q(<table class="tablesorter" id="sortTable">);
	say q(<thead><tr><th>Project id</th><th>Short description</th><th class="{sorter: false}">Full description</th>)
	  . q(<th>Isolates</th><th class="{sorter: false}">Browse</th></tr></thead><tbody>);
	my $td = 1;
	foreach my $project (@$projects) {
		my $isolates = $self->{'datastore'}->run_query(
			'SELECT COUNT(*) FROM project_members WHERE project_id=? AND isolate_id IN '
			  . "(SELECT id FROM $self->{'system'}->{'view'} WHERE new_version IS NULL)",
			$project->{'id'},
			{ cache => 'ProjectsPage::print_content' }
		);
		$project->{'full_description'} //= q();
		say qq(<tr class="td$td"><td>$project->{'id'}</td><td>$project->{'short_description'}</td>)
		  . qq(<td>$project->{'full_description'}</td><td>$isolates</td><td>);
		say $q->start_form( -style => 'display:inline' );
		$q->param( project_list => $project->{'id'} );
		$q->param( submit       => 1 );
		$q->param( page         => 'query' );
		say $q->hidden($_) foreach qw(db page project_list submit);
		say $q->submit( -value => 'Browse', -class => 'submit' );
		say $q->end_form;
		say q(</td></tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</tbody></table>);
	say q(</div></div>);
	return;
}

sub get_javascript {
	return <<"JS";
\$(document).ready(function() 
    { 
        \$("#sortTable").tablesorter({widgets:['zebra']}); 
    } 
); 	
JS
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Projects - $desc";
}
1;
