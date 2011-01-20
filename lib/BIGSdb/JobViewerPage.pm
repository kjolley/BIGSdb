#Written by Keith Jolley
#Copyright (c) 2011, University of Oxford
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

package BIGSdb::JobViewerPage;
use strict;
use base qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{'jQuery'}  = 1;
	$self->{'noCache'} = 1;
	$self->{'refresh'} = 60;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<h1>Job status viewer</h1>";
	my $id = $q->param('id');
	if ($id !~ /BIGSdb_\d+/){
		print "<div class=\"box\" id=\"statusbad\">\n";
		print "<p>The submitted job id is invalid.</p>\n";
		print "</div>";
		return;
	}
	my ($job,$params,$output) = $self->{'jobManager'}->get_job($id);
	if (ref $job ne 'HASH' || !$job->{'id'}){
		print "<div class=\"box\" id=\"statusbad\">\n";
		print "<p>The submitted job does not exist.</p>\n";
		print "</div>\n";
		return;
	}
	(my $submit_time = $job->{'submit_time'}) =~ s/\.\d+$//; #remove fractions of second 
	(my $start_time = $job->{'start_time'}) =~ s/\.\d+$//;
	(my $stop_time = $job->{'stop_time'}) =~ s/\.\d+$//;
	print << "HTML";
<div class="box" id="resultstable">
<h2>Status</h2>
<table class="resultstable">
<tr class="td1"><th style="text-align:right">Job id: </th><td style="text-align:left">$id</td></tr>
<tr class="td2"><th style="text-align:right">Submit time: </th><td style="text-align:left">$submit_time</td></tr>
<tr class="td1"><th style="text-align:right">Status: </th><td style="text-align:left">$job->{'status'}</td></tr>
<tr class="td2"><th style="text-align:right">Start time: </th><td style="text-align:left">$start_time</td></tr>
<tr class="td1"><th style="text-align:right">Progress: </th><td style="text-align:left">$job->{'percent_complete'}%</td></tr>
<tr class="td2"><th style="text-align:right">Stop time: </th><td style="text-align:left">$stop_time</td></tr>
</table>
<h2>Output</h2>
HTML
	if (!($job->{'message_html'} || ref $output eq 'HASH')){
		print "<p>No output yet.</p>\n";
	} else {
		print "$job->{'message_html'}";
		my @buffer;
		if (ref $output eq 'HASH'){
			foreach (sort keys (%$output)){
				push @buffer, "<li><a href=\"/tmp/$output->{$_}\">$_</a></li>\n";
			}
		}
		if (@buffer){
			$"="\n";
			print "<ul>\n@buffer</ul>\n";
		}
	}
	print "<p>This page will reload in $self->{'refresh'} seconds.  You can refresh it any time, or bookmark it and close your browser if you wish.</p>\n";
	print "<p>Please note that job results will not be stored on the server indefinitely.</p>\n";
	print "</div>\n";
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Job status viewer - $desc";
}
1;