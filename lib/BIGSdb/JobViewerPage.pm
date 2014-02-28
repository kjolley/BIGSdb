#Written by Keith Jolley
#Copyright (c) 2011-2013, University of Oxford
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
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $id     = $q->param('id');
	if ( ( $q->param('output') // '' ) eq 'archive' ) {
		$self->{'type'}       = 'tar';
		$self->{'attachment'} = "$id.tar";
		$self->{'noCache'}    = 1;
		return;
	} else {
		$self->{$_} = 1 foreach qw(jQuery jQuery.slimbox jQuery.tablesort noCache);
	}
	return if !defined $id;
	my $job = $self->{'jobManager'}->get_job($id);
	return if !$job->{'status'};
	return if any { $job->{'status'} =~ /^$_/ } qw (finished failed terminated cancelled rejected);
	my $complete = $job->{'percent_complete'};
	my $elapsed = $job->{'elapsed'} // 0;
	if ( $job->{'status'} eq 'started' ) {

		if ( $complete > 0 ) {
			$self->{'refresh'} = ( int( $elapsed / $complete ) || 1 ) * 5;
		} elsif ( $elapsed > 300 ) {
			$self->{'refresh'} = 60;
		} elsif ( $elapsed > 120 ) {
			$self->{'refresh'} = 20;
		} elsif ( $elapsed > 60 ) {
			$self->{'refresh'} = 10;
		} else {
			$self->{'refresh'} = 5;    #update page frequently for the first minute
		}
	} else {
		$self->{'refresh'} = 5;        #not started
	}
	if ( $q->param('cancel') ) {
		$self->{'refresh'} = 1;
	}
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $id     = $q->param('id');
	my $job    = $self->{'jobManager'}->get_job($id);
	my $percent = $job->{'percent_complete'} // 0;
	if ( $percent == -1 ) {
		my $buffer = << "END";
\$(function () {
	\$("html, body").animate({ scrollTop: \$(document).height()-\$(window).height() });	
	\$("#progressbar").progressbar({value: false});
});
END
		return $buffer;
	}
	my $buffer = << "END";
\$(function () {
	\$("html, body").animate({ scrollTop: \$(document).height()-\$(window).height() });	
	\$("#progressbar")
		.progressbar({	value: $percent	})
		.children('.ui-progressbar-value')
    	.html($percent + '%')
    	.css("display", "block");
    \$("#sortTable").tablesorter({widgets:['zebra']});     
});
END
	return $buffer;
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $id     = $q->param('id');
	if ( ( $q->param('output') // '' ) eq 'archive' ) {
		$self->_tar_archive($id);
		return;
	}
	print "<h1>Job status viewer</h1>";
	if ( !defined $id || $id !~ /BIGSdb_\d+/ ) {
		print "<div class=\"box\" id=\"statusbad\">\n";
		print "<p>The submitted job id is invalid.</p>\n";
		print "</div>";
		return;
	}
	my $job = $self->{'jobManager'}->get_job($id);
	if ( ref $job ne 'HASH' || !$job->{'id'} ) {
		print "<div class=\"box\" id=\"statusbad\">\n";
		print "<p>The submitted job does not exist.</p>\n";
		print "</div>\n";
		return;
	}
	if ( $q->param('cancel') ) {
		if ( $self->_can_user_cancel_job($job) ) {
			$self->{'jobManager'}->cancel_job( $job->{'id'} );
		}
	}
	( my $submit_time = $job->{'submit_time'} ) =~ s/\.\d+$//;    #remove fractions of second
	( my $start_time = $job->{'start_time'} ? $job->{'start_time'} : '' ) =~ s/\.\d+$//;
	( my $stop_time  = $job->{'stop_time'}  ? $job->{'stop_time'}  : '' ) =~ s/\.\d+$//;
	$job->{'percent_complete'} = 'indeterminate ' if $job->{'percent_complete'} == -1;
	if ( $job->{'status'} eq 'submitted' ) {
		my $jobs_in_queue = $self->{'jobManager'}->get_jobs_ahead_in_queue($id);
		if ($jobs_in_queue) {
			my $plural = $jobs_in_queue == 1 ? '' : 's';
			$job->{'status'} .= " ($jobs_in_queue unstarted job$plural ahead in queue)";
		} else {
			$job->{'status'} .= " (first in queue)";
		}
	} elsif ( $job->{'status'} =~ /^rejected/ ) {
		$job->{'status'} =~
		  s/(BIGSdb_\d+_\d+_\d+)/<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=job&amp;id=$1">$1<\/a>/;
	}
	print << "HTML";
<div class="box" id="resultstable">
<h2>Status</h2>
<table class="resultstable">
<tr class="td1"><th style="text-align:right">Job id: </th><td style="text-align:left">$id</td></tr>
<tr class="td2"><th style="text-align:right">Submit time: </th><td style="text-align:left">$submit_time</td></tr>
<tr class="td1"><th style="text-align:right">Status: </th><td style="text-align:left">$job->{'status'}</td></tr>
<tr class="td2"><th style="text-align:right">Start time: </th><td style="text-align:left">$start_time</td></tr>
<tr class="td1"><th style="text-align:right">Progress: </th><td style="text-align:left">
<noscript>$job->{'percent_complete'}%</noscript>
<div id="progressbar"></div></td></tr>
HTML
	my $td = 2;
	if ( $job->{'stage'} ) {
		print "<tr class=\"td$td\"><th style=\"text-align:right\">Stage: </th><td style=\"text-align:left\">$job->{'stage'}</td></tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	if ($stop_time) {
		print "<tr class=\"td$td\"><th style=\"text-align:right\">Stop time: </th><td style=\"text-align:left\">$stop_time</td></tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	my ( $field, $value, $refresh );
	eval "use Time::Duration;";    ## no critic (ProhibitStringyEval)
	if ($@) {
		if ( $job->{'total_time'} ) {
			( $field, $value ) = ( 'Total time', int( $job->{'total_time'} ) . ' s' );
		} elsif ( $job->{'elapsed'} ) {
			( $field, $value ) = ( 'Elapsed time', int( $job->{'elapsed'} ) . ' s' );
		}
		$refresh = $self->{'refresh'} . ' seconds';
	} else {
		if ( $job->{'total_time'} ) {
			( $field, $value ) = ( 'Total time', duration( $job->{'total_time'} ) );
			$value = '<1 second' if $value eq 'just now';
		} elsif ( $job->{'elapsed'} ) {
			( $field, $value ) = ( 'Elapsed time', duration( $job->{'elapsed'} ) );
			$value = '<1 second' if $value eq 'just now';
		}
		$refresh = duration( $self->{'refresh'} );
	}
	print "<tr class=\"td$td\"><th style=\"text-align:right\">$field: </th><td style=\"text-align:left\">$value</td></tr>\n"
	  if $field && $value;
	print "</table><h2>Output</h2>";
	my $output = $self->{'jobManager'}->get_job_output($id);
	if ( !( $job->{'message_html'} || ref $output eq 'HASH' ) ) {
		print "<p>No output yet.</p>\n";
	} else {
		print "$job->{'message_html'}" if $job->{'message_html'};
		my @buffer;
		if ( ref $output eq 'HASH' ) {
			my $include_in_tar = 0;
			foreach ( sort keys(%$output) ) {
				my ( $link_text, $comments ) = split /\|/, $_;
				$link_text =~ s/^\d{2}_//;    #Descriptions can start with 2 digit number for ordering
				my $text = "<li><a href=\"/tmp/$output->{$_}\">$link_text</a>";
				$text .= " - $comments" if $comments;
				my $size = -s "$self->{'config'}->{'tmp_dir'}/$output->{$_}" // 0;
				if ( $size > ( 1024 * 1024 ) ) {    #1Mb
					my $size_in_MB = BIGSdb::Utils::decimal_place( $size / ( 1024 * 1024 ), 1 );
					$text .= " ($size_in_MB MB)";
				}
				$include_in_tar++ if $size < ( 10 * 1024 * 1024 );    #10MB
				if ( $output->{$_} =~ /\.png$/ ) {
					my $title = $link_text . ( $comments ? " - $comments" : '' );
					$text .=
					    "<br /><a href=\"/tmp/$output->{$_}\" data-rel=\"lightbox-1\" class=\"lightbox\" title=\"$title\">"
					  . "<img src=\"/tmp/$output->{$_}\" alt=\"\" style=\"max-width:200px;border:1px dashed black\" /></a>"
					  . " (click to enlarge)";
				}
				$text .= "</li>";
				push @buffer, $text;
			}
			my $tar_msg = $include_in_tar < ( keys %$output ) ? ' (only files <10MB included - download larger files separately)' : '';
			push @buffer,
			  "<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=job&amp;id=$id&amp;"
			  . "output=archive\">Tar file containing output files</a>$tar_msg</li>"
			  if $job->{'status'} eq 'finished' && $include_in_tar > 1;
		}
		if (@buffer) {
			local $" = "\n";
			print "<ul>\n@buffer</ul>\n";
		}
	}
	print "</div><div class=\"box\" id=\"resultsfooter\">";
	if ( $job->{'status'} eq 'started' ) {
		say "<p>Progress: $job->{'percent_complete'}%";
		say "<br />Stage: $job->{'stage'}" if $job->{'stage'};
		say "</p>";
	}
	$self->_print_cancel_button($job) if $job->{'status'} eq 'started' || $job->{'status'} =~ /^submitted/;
	print "<p>This page will reload in $refresh. You can refresh it any time, or bookmark it and close your browser if you wish.</p>"
	  if $self->{'refresh'};
	if ( $self->{'config'}->{'results_deleted_days'} && BIGSdb::Utils::is_int( $self->{'config'}->{'results_deleted_days'} ) ) {
		print "<p>Please note that job results will remain on the server for $self->{'config'}->{'results_deleted_days'} days.</p></div>";
	} else {
		print "<p>Please note that job results will not be stored on the server indefinitely.</p></div>";
	}
	return;
}

sub _print_cancel_button {
	my ( $self, $job ) = @_;
	return if !$self->_can_user_cancel_job($job);
	say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=job&amp;id=$job->{'id'}&amp;"
	  . "cancel=1\" class=\"resetbutton ui-button ui-widget ui-state-default ui-corner-all ui-button-text-only \">"
	  . "<span class=\"ui-button-text\">Cancel job!</span></a> Clicking this will request that the job is cancelled.</p>";
	return;
}

sub _can_user_cancel_job {
	my ( $self, $job ) = @_;
	if ( $job->{'email'} ) {
		return 1 if $self->{'username'} && $self->{'username'} eq $job->{'username'};
	} elsif ( $job->{'ip_address'} ) {    #public database, no logins.  Allow if IP address matches.
		return 1 if $ENV{'REMOTE_ADDR'} && $job->{'ip_address'} eq $ENV{'REMOTE_ADDR'};
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Job status viewer - $desc";
}

sub _tar_archive {
	my ( $self, $id ) = @_;
	return if !defined $id || $id !~ /BIGSdb_\d+/;
	my $job    = $self->{'jobManager'}->get_job($id);
	my $output = $self->{'jobManager'}->get_job_output($id);
	if ( ref $output eq 'HASH' ) {
		my @filenames;
		foreach my $desc ( sort keys(%$output) ) {
			my $full_path = "$self->{'config'}->{'tmp_dir'}/$output->{$desc}";
			if ( -e $full_path && -s $full_path < ( 10 * 1024 * 1024 ) ) {    #smaller than 10MB
				push @filenames, $output->{$desc};
			}
		}
		if (@filenames) {
			local $" = ' ';
			my $command = "cd $self->{'config'}->{'tmp_dir'} && tar -cf - @filenames";
			if ( $ENV{'MOD_PERL'} ) {
				print `$command`;    # http://modperlbook.org/html/6-4-8-Output-from-System-Calls.html
			} else {
				system $command || $logger->error("Can't create tar: $?");
			}
		}
	}
	return;
}
1;
