#Written by Keith Jolley
#Copyright (c) 2011-2015, University of Oxford
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
use BIGSdb::Constants qw(RESET_BUTTON_CLASS);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub _get_refresh_time {
	my ( $self, $job ) = @_;
	my $complete = $job->{'percent_complete'};
	my $elapsed = $job->{'elapsed'} // 0;
	return ( int( $elapsed / $complete ) || 1 ) * 5 if $complete > 0;
	return 60 if $elapsed > 300;
	return 20 if $elapsed > 120;
	return 10 if $elapsed > 60;
	return 5;    #update page frequently for the first minute
}

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
	return if any { $job->{'status'} =~ /^$_/x } qw (finished failed terminated cancelled rejected);
	if ( $job->{'status'} eq 'started' ) {
		$self->{'refresh'} = $self->_get_refresh_time($job);
	} else {
		$self->{'refresh'} = 5;    #not started
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

sub _print_status {
	my ( $self, $job ) = @_;
	( my $submit_time = $job->{'submit_time'} ) =~ s/\.\d+$//x;    #remove fractions of second
	( my $start_time = $job->{'start_time'} ? $job->{'start_time'} : q() ) =~ s/\.\d+$//x;
	( my $stop_time  = $job->{'stop_time'}  ? $job->{'stop_time'}  : q() ) =~ s/\.\d+$//x;
	$job->{'percent_complete'} = 'indeterminate ' if $job->{'percent_complete'} == -1;
	if ( $job->{'status'} eq 'submitted' ) {
		my $jobs_in_queue = $self->{'jobManager'}->get_jobs_ahead_in_queue( $job->{'id'} );
		if ($jobs_in_queue) {
			my $plural = $jobs_in_queue == 1 ? '' : 's';
			$job->{'status'} .= qq( ($jobs_in_queue unstarted job$plural ahead in queue));
		} else {
			$job->{'status'} .= q( (first in queue));
		}
	} elsif ( $job->{'status'} =~ /^rejected/x ) {
		$job->{'status'} =~ s/(BIGSdb_\d+_\d+_\d+)/
		<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=job&amp;id=$1">$1<\/a>/x;
	}
	say q(<div class="box" id="resultspanel"><div class="scrollable">);
	say q(<h2>Status</h2>);
	say q(<dl class="data">);
	say qq(<dt>Job id</dt><dd>$job->{'id'}</dd>);
	say qq(<dt>Submit time</dt><dd>$submit_time</dd>);
	say qq(<dt>Status</dt><dd>$job->{'status'}</dd>);
	say qq(<dt>Start time</dt><dd>$start_time</dd>) if $start_time;
	say
qq(<dt>Progress</dt><dd><noscript>$job->{'percent_complete'}%</noscript><div id="progressbar" style="width:18em"></div></dd>);
	say qq(<dt>Stage</dt><dd>$job->{'stage'}</dd>) if $job->{'stage'};
	say qq(<dt>Stop time</dt><dd>$stop_time</dd>)  if $stop_time;
	my ( $field, $value );
	eval 'use Time::Duration';    ## no critic (ProhibitStringyEval)

	if ($@) {
		if ( $job->{'total_time'} ) {
			( $field, $value ) = ( 'Total time', int( $job->{'total_time'} ) . q( s) );
		} elsif ( $job->{'elapsed'} ) {
			( $field, $value ) = ( 'Elapsed time', int( $job->{'elapsed'} ) . q( s) );
		}
	} else {
		if ( $job->{'total_time'} ) {
			( $field, $value ) = ( 'Total time', duration( $job->{'total_time'} ) );
			$value = '<1 second' if $value eq 'just now';
		} elsif ( $job->{'elapsed'} ) {
			( $field, $value ) = ( 'Elapsed time', duration( $job->{'elapsed'} ) );
			$value = '<1 second' if $value eq 'just now';
		}
	}
	say qq(<dt>$field</dt><dd>$value</dd>) if $value;
	say q(</dl>);
	say q(</div></div>);
	return;
}

sub _get_nice_refresh_time {
	my ( $self, $job ) = @_;
	eval 'use Time::Duration';    ## no critic (ProhibitStringyEval)
	my $refresh;
	if ($@) {
		$refresh = $self->{'refresh'} . ' seconds';
	} else {
		$refresh = duration( $self->{'refresh'} );
	}
	return $refresh;
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $id     = $q->param('id');
	if ( ( $q->param('output') // '' ) eq 'archive' ) {
		$self->_tar_archive($id);
		return;
	}
	print q(<h1>Job status viewer</h1>);
	if ( !defined $id || $id !~ /BIGSdb_\d+/x ) {
		say q(<div class="box" id="statusbad">);
		say q(<p>The submitted job id is invalid.</p>);
		say q(</div>);
		return;
	}
	my $job = $self->{'jobManager'}->get_job($id);
	if ( ref $job ne 'HASH' || !$job->{'id'} ) {
		say q(<div class="box" id="statusbad">);
		say q(<p>The submitted job does not exist.</p>);
		say q(</div>);
		return;
	}
	if ( $q->param('cancel') ) {
		if ( $self->_can_user_cancel_job($job) ) {
			$self->{'jobManager'}->cancel_job( $job->{'id'} );
		}
	}
	$self->_print_status($job);
	$self->_print_output($job);
	say q(<div class="box" id="resultsfooter">);
	if ( $job->{'status'} eq 'started' ) {
		say qq(<p>Progress: $job->{'percent_complete'}%);
		say qq(<br />Stage: $job->{'stage'}) if $job->{'stage'};
		say q(</p>);
	}
	$self->_print_cancel_button($job) if $job->{'status'} eq 'started' || $job->{'status'} =~ /^submitted/x;
	my $refresh = $self->_get_nice_refresh_time($job);
	say qq(<p>This page will reload in $refresh. You can refresh it any time, )
	  . q(or bookmark it and close your browser if you wish.</p>)
	  if $self->{'refresh'};
	if ( $self->{'config'}->{'results_deleted_days'}
		&& BIGSdb::Utils::is_int( $self->{'config'}->{'results_deleted_days'} ) )
	{
		say q(<p>Please note that job results will remain on the server for )
		  . qq($self->{'config'}->{'results_deleted_days'} days.</p></div>);
	} else {
		say q(<p>Please note that job results will not be stored on the server indefinitely.</p></div>);
	}
	return;
}

sub _print_output {
	my ( $self, $job ) = @_;
	my $output = $self->{'jobManager'}->get_job_output( $job->{'id'} );
	return if !( $job->{'message_html'} || ref $output eq 'HASH' );
	say q(<div class="box" id="resultstable">);
	say q(<h2>Output</h2>);
	say $job->{'message_html'} if $job->{'message_html'};
	my @buffer;
	my $include_in_tar = 0;

	foreach my $description ( sort keys(%$output) ) {
		my ( $link_text, $comments ) = split /\|/x, $description;
		$link_text =~ s/^\d{2}_//x;    #Descriptions can start with 2 digit number for ordering
		$link_text =~ s/\(text\)/<span class="fa fa-file-text-o" style="color:black"><\/span>/x;
		$link_text =~ s/\(Excel\)/<span class="fa fa-file-excel-o" style="color:green"><\/span>/x;
		my $text = qq(<li><a href="/tmp/$output->{$description}">$link_text</a>);
		$text .= qq( - $comments) if $comments;
		my $size = -s qq($self->{'config'}->{'tmp_dir'}/$output->{$description}) // 0;
		if ( $size > ( 1024 * 1024 ) ) {                                                              #1Mb
			my $size_in_MB = BIGSdb::Utils::decimal_place( $size / ( 1024 * 1024 ), 1 );
			$text .= qq( ($size_in_MB MB));
		}
		$include_in_tar++ if $size < ( 10 * 1024 * 1024 );                                            #10MB
		if ( $output->{$description} =~ /\.png$/x ) {
			my $title = $link_text . ( $comments ? qq( - $comments) : q() );
			$text .=
			    qq(<br /><a href="/tmp/$output->{$description}" data-rel="lightbox-1" class="lightbox" )
			  . qq(title="$title"><img src="/tmp/$output->{$description}" alt="" )
			  . q(style="max-width:200px;border:1px dashed black" /></a> (click to enlarge));
		}
		$text .= q(</li>);
		push @buffer, $text;
	}
	my $tar_msg =
	  $include_in_tar < ( keys %$output )
	  ? q( (only files <10MB included - download larger files separately))
	  : q();
	push @buffer,
	  qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=job&amp;id=$job->{'id'}&amp;output=archive">Tar file containing output files</a>$tar_msg</li>)
	  if $job->{'status'} eq 'finished' && $include_in_tar > 1;
	if (@buffer) {
		local $" = qq(\n);
		say qq(<ul>@buffer</ul>);
	}
	say q(</div>);
	return;
}

sub _print_cancel_button {
	my ( $self, $job ) = @_;
	return if !$self->_can_user_cancel_job($job);
	my $button_class = RESET_BUTTON_CLASS;
	say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=job&amp;)
	  . qq(id=$job->{'id'}&amp;cancel=1" class="$button_class ui-button-text-only ">)
	  . q(<span class="ui-button-text">Cancel job!</span></a> Clicking this will request that the )
	  . q(job is cancelled.</p>);
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
	return if !defined $id || $id !~ /BIGSdb_\d+/x;
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
