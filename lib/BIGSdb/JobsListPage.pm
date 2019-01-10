#Written by Keith Jolley
#Copyright (c) 2014-2019, University of Oxford
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
package BIGSdb::JobsListPage;
use strict;
use warnings;
use 5.010;
use Time::Piece;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery jQuery.tablesort noCache);
	$self->{'refresh'} = 60;
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

sub print_content {
	my ($self) = @_;
	my $desc = $self->get_db_description;
	my $days = $self->{'config'}->{'results_deleted_days'} // 7;
	my $days_plural = $days == 1 ? '' : 's';
	say qq(<h1>Jobs - $desc database</h1>);
	my $jobs = $self->{'jobManager'}->get_user_jobs( $self->{'instance'}, $self->{'username'}, $days );
	my $user = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	if ( !keys %$user ) {
		$self->print_bad_status( { message => q(No information about current user.), navbar => 1 } );
		return;
	}
	eval 'use Time::Duration';    ## no critic (ProhibitStringyEval)
	my $use_time_duration    = 1;
	my $nice_duration_header = q(<th class="{sorter: false}">Duration (description)</th>);
	if ($@) {
		$use_time_duration    = 0;
		$nice_duration_header = q();
	}
	say q(<div class="box" id="resultstable"><div class="scrollable">);
	say qq(<p>This page shows all offline jobs run by you in the past $days day$days_plural.<p>);
	say qq(<h2>User: $user->{'first_name'} $user->{'surname'}</h2>);
	say q(<p>Click on the job id to see results. You can also cancel queued and running jobs.</p>);
	say q(<table class="tablesorter" id="sortTable"><thead><tr><th class="{sorter: false}">Job</th>)
	  . q(<th>Analysis</th><th class="{sorter: false}">Size</th><th>Submitted</th><th>Started</th>)
	  . qq(<th>Finished</th><th>Duration (seconds)</th>$nice_duration_header<th>Status</th>)
	  . q(<th>Progress (%)</th><th>Stage</th></tr></thead><tbody>);
	foreach my $job (@$jobs) {
		if ( $job->{'total_time'} ) {
			$job->{'duration_s'} = int( $job->{'total_time'} );
		} elsif ( $job->{'elapsed'} ) {
			$job->{'duration_s'} = int( $job->{'elapsed'} );
		}
		if ( defined $job->{'duration_s'} && $use_time_duration ) {
			$job->{'duration'} = duration( $job->{'duration_s'} );
			$job->{'duration'} = '<1 second' if $job->{'duration'} eq 'just now';
		}
		if ( $job->{'status'} =~ /^rejected/x ) {
			my $url = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=job);
			$job->{'status'} =~ s/(BIGSdb_\d+_\d+_\d+)/<a href="$url&amp;id=$1">$1<\/a>/x;
		}
		say q(<tr>);
		my $size_stats = $self->_get_job_size_stats( $job->{'id'} );
		local $" = q(; );
		$job->{'size'} = qq(@$size_stats);
		foreach my $field (
			qw (id module size submit_time start_time stop_time duration_s duration status percent_complete stage))
		{
			next if $field eq 'duration' && !$use_time_duration;
			$job->{$field} //= '';
			$job->{$field} = substr( $job->{$field}, 0, 16 ) if $field =~ /time$/x;
			if ( $field eq 'id' ) {
				say qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=job&amp;)
				  . qq(id=$job->{'id'}">$job->{'id'}</a></td>);
			} else {
				say qq(<td>$job->{$field}</td>);
			}
		}
		say q(</tr>);
	}
	say q(</tbody></table>);
	say q(</div></div><div class="box" id="resultsfooter">);
	say q(<p>This page will refresh every 60 seconds.</p>);
	say q(</div>);
	return;
}

sub _get_job_size_stats {
	my ( $self, $job_id ) = @_;
	my $params = $self->{'jobManager'}->get_job_params($job_id);
	my @size_stats;
	my $isolates = $self->{'jobManager'}->get_job_isolates($job_id);
	push @size_stats, @$isolates . q( isolate) . ( @$isolates == 1 ? q() : q(s) ) if @$isolates;
	if ( $params->{'scheme_id'} ) {
		my $profiles = $self->{'jobManager'}->get_job_profiles( $job_id, $params->{'scheme_id'} );
		push @size_stats, @$profiles . q( profile) . ( @$profiles == 1 ? q() : q(s) ) if @$profiles;
	}
	my $loci = $self->{'jobManager'}->get_job_loci($job_id);
	push @size_stats, @$loci . q( loc) . ( @$loci == 1 ? q(us) : q(i) ) if @$loci;
	return \@size_stats;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return qq(Offline job list - $desc);
}
1;
