#Written by Keith Jolley
#Copyright (c) 2011-2019, University of Oxford
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
use BIGSdb::Constants qw(:interface BUTTON_CLASS RESET_BUTTON_CLASS);
use List::MoreUtils qw(any);
use Time::Duration;
use JSON;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub _ajax {
	my ( $self, $function, $job_id ) = @_;
	my $job = $self->{'jobManager'}->get_job($job_id);
	if ( $function eq 'status' ) {
		my $jobs_in_queue = $self->{'jobManager'}->get_jobs_ahead_in_queue( $job->{'id'} );
		say encode_json(
			{
				status       => $job->{'status'},
				progress     => $job->{'percent_complete'},
				stage        => $job->{'stage'},
				elapsed      => $job->{'elapsed'} // 0,
				nice_elapsed => duration( $job->{'elapsed'} // 0 ),
				jobs_ahead   => $jobs_in_queue
			}
		);
		return;
	}
	if ( $function eq 'html' ) {
		print $job->{'message_html'} // q();
		return;
	}
	say 'Invalid function';
	return;
}

sub initiate {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $id     = $q->param('id');
	if ( $q->param('ajax') ) {
		$self->{'noCache'} = 1;
		$self->{'type'}    = 'no_header';
		return;
	}
	if ( ( $q->param('output') // '' ) eq 'archive' ) {
		$self->{'type'}       = 'tar';
		$self->{'attachment'} = "$id.tar";
		$self->{'noCache'}    = 1;
		return;
	} else {
		$self->{$_} = 1 foreach qw(jQuery jQuery.slimbox jQuery.tablesort packery noCache);
	}
	return if !defined $id;
	my $job = $self->{'jobManager'}->get_job($id);
	return if !$job->{'status'};
	return if any { $job->{'status'} =~ /^$_/x } qw (finished failed terminated cancelled rejected);
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $id     = $q->param('id');
	$id //= 'null';
	my $job        = $self->{'jobManager'}->get_job($id);
	my $percent    = $job->{'percent_complete'} // 0;
	my $reload_url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=job&id=$id";
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
    \$("#email").on('input',function(){
    	\$("#enable_notifications").prop('checked',true);
    });
    \$("#title").on('input',function(){
    	\$("#enable_notifications").prop('checked',true);
    });
    \$("#description").on('input',function(){
    	\$("#enable_notifications").prop('checked',true);
    });
    \$(".grid").packery();
    
    var complete = 0;
    get_status(5000);
});

function get_status(poll_time){
	var status_url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=job&id=$id&ajax=status";
	var html_url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=job&id=$id&ajax=html";
	var complete = 0;
	if (\$("#status").html() == 'finished'){
		\$(".elapsed").css('display','block');
		return;
	}
	\$.ajax({
		url: status_url,
		dataType: 'json',
		cache: false,
		success: function (json) {
			var status = json.status;
			if (status == 'submitted'){
				if (json.jobs_ahead) {
					var plural = json.jobs_ahead == 1 ? '' : 's';
					status += ' (' + json.jobs_ahead + ' unstarted job' + plural + ' ahead in queue)';
				} else {
					status += ' (first in queue)';
				}
			} else if (status == 'started') {
				var nice_elapsed = json.nice_elapsed;
	 			if (nice_elapsed == 'just now'){
	 				nice_elapsed = '< 1 second';
	 			}
	 			\$("#elapsed").html(nice_elapsed);
	 			\$(".elapsed").css('display','block');
			} else if (status == 'cancelled'){
				\$("div#cancel_refresh").css('display','none');
			}
			if (json.status == 'finished'){				 
				window.location.href = "$reload_url";							
			}
			\$("dd#status").html(status);
			\$("#progressbar")
				.progressbar({value: json.progress})
				.children('.ui-progressbar-value')
  			  	.html(json.progress + '%')
  			  	.css("display", "block");
  			\$("#footer_progress").html(json.progress);
  			var stage = json.stage == null ? '': json.stage;
  			\$(".stage").css('display',json.stage == null ? 'none' : 'block');
 			\$("dd#stage").html(stage);
 			\$("#footer_stage").html(stage);
 			

			if (json.status != 'started' && json.status != 'submitted'){
				complete = 1;
			} else {
				setTimeout(function() { 
					poll_time = get_poll_time(json.elapsed)
		        	get_status(poll_time);
		        }, poll_time);	
			}
			if (json.status == 'started'){
				\$("#footer_values").css('display','block');
			} 
			if (json.status != 'submitted'){
				\$.ajax({
					url: html_url,
					cache: false,
					success: function (html) {
						if (html !== ''){
							\$("div#resultstable").addClass('box');
							\$("div#resultstable").html('<h2>Output</h2>' + html);
							var focused = document.activeElement.id;
							if (focused != 'email' && focused != 'title' && focused != 'description'){
								\$("html, body").animate({ scrollTop: \$(document).height()-\$(window).height() });
							}	
						}
					}
				});
			}
		}
	});   	
}

function get_poll_time (elapsed){
	if (elapsed > 300) {return 60000}
	if (elapsed > 120) {return 20000};
	if (elapsed > 60) {return 10000};
	return 5000;	
}
END
	return $buffer;
}

sub _print_status {
	my ( $self, $job ) = @_;
	( my $submit_time = $job->{'submit_time'} ) =~ s/\.\d+$//x;                              #remove fractions of second
	( my $start_time  = $job->{'start_time'} ? $job->{'start_time'} : q() ) =~ s/\.\d+$//x;
	( my $stop_time   = $job->{'stop_time'} ? $job->{'stop_time'} : q() ) =~ s/\.\d+$//x;
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
	say q(<div style="float:left;margin-right:2em">);
	say q(<span class="main_icon fas fa-flag fa-3x fa-pull-left"></span>);
	say q(<h2>Status</h2>);
	say q(<dl class="data">);
	say qq(<dt>Job id</dt><dd>$job->{'id'}</dd>);
	say qq(<dt>Submit time</dt><dd>$submit_time</dd>);
	say qq(<dt>Status</dt><dd id="status">$job->{'status'}</dd>);
	say qq(<dt>Start time</dt><dd>$start_time</dd>) if $start_time;
	say qq(<dt>Progress</dt><dd id="progress"><noscript>$job->{'percent_complete'}%</noscript>)
	  . q(<div id="progressbar" style="width:18em;height:1.2em"></div></dd>);
	my $stage_display = $job->{'stage'} ? 'block' : 'none';
	$job->{'stage'} //= q();
	say q(<dt style="display:none" class="stage">Stage</dt>)
	  . qq(<dd style="display:none" id="stage" class="stage">$job->{'stage'}</dd>);
	say qq(<dt>Stop time</dt><dd>$stop_time</dd>) if $stop_time;
	my ( $field, $value );

	if ( $job->{'total_time'} ) {
		( $field, $value ) = ( 'Total time', duration( $job->{'total_time'} ) );
		$value = '<1 second' if $value eq 'just now';
	} else {
		( $field, $value ) = ( 'Elapsed time', duration( $job->{'elapsed'} ) );
		$value = '<1 second' if $value eq 'just now';
	}
	say qq(<dt class="elapsed" style="display:none">$field</dt>)
	  . qq(<dd class="elapsed" style="display:none" id="elapsed">$value</dd>);
	say q(</dl>);
	say q(</div>);
	$self->_print_notification_form($job);
	say q(</div></div>);
	return;
}

sub _print_notification_form {
	my ( $self, $job ) = @_;
	return if !$self->{'config'}->{'smtp_server'};
	return if $job->{'stop_time'};
	my $q = $self->{'cgi'};
	if ( $q->param('Update') ) {
		$self->_update_notifications( $job->{'id'} );
	}
	say q(<div style="float:left">);
	say q(<span class="main_icon fas fa-envelope fa-3x fa-pull-left"></span>);
	say q(<h2>Notification</h2>);
	say q(<p>Enter address for notification of job completion. You can also<br />)
	  . q(add a title and/or description to remind you of what the job is.<br />)
	  . q(<b>Tick 'Enable' checkbox and update to activate notification.</b></p>);
	say $q->start_form;
	say q(<dl class="data">);
	say q(<dt>E-mail address</dt><dd>);
	my $params = $self->{'jobManager'}->get_job_params( $job->{'id'} );
	my $default_email = $params->{'email'} // $job->{'email'};
	say $q->textfield( -id => 'email', -name => 'email', -default => $default_email, -size => 30 );
	say q(</dd>);
	say q(<dt>Title</dt><dd>);
	my $default_title = $params->{'title'};
	say $q->textfield( -id => 'title', -name => 'title', -default => $default_title, -size => 30 );
	say q(</dd>);
	say q(<dt>Description</dt><dd>);
	my $default_desc = $params->{'description'};
	say $q->textarea( -id => 'description', -name => 'description', -default => $default_desc, -cols => 25 );
	say q(</dd>);
	say q(<dt>Enable</dt><dd>);
	say $q->checkbox(
		-id      => 'enable_notifications',
		-name    => 'enable_notifications',
		-label   => '',
		-checked => $params->{'enable_notifications'}
	);
	say q(<strong style="margin-right:1em">) . ( $params->{'enable_notifications'} ? 'ON' : 'OFF' ) . q(</strong>);
	say $q->submit( -name => 'Update', -class => BUTTON_CLASS );
	say q(</dd>);
	say q(</dl>);
	say $q->hidden($_) foreach qw(db page id);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _update_notifications {
	my ( $self, $job_id ) = @_;
	my $q = $self->{'cgi'};
	$self->{'jobManager'}->update_notifications(
		$job_id,
		{
			email                => $q->param('email'),
			title                => $q->param('title'),
			description          => $q->param('description'),
			enable_notifications => $q->param('enable_notifications') ? 1 : 0,
			job_url => $q->url( -full => 1 ) . "?db=$self->{'instance'}&page=job&id=$job_id"
		}
	);
	return;
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $id     = $q->param('id');
	if ( $q->param('ajax') ) {
		$self->_ajax( $q->param('ajax'), $id );
		return;
	}
	if ( ( $q->param('output') // '' ) eq 'archive' ) {
		$self->_tar_archive($id);
		return;
	}
	print q(<h1>Job status viewer</h1>);
	if ( !defined $id || $id !~ /BIGSdb_\d+/x ) {
		$self->print_bad_status( { message => q(The submitted job id is invalid.), navbar => 1 } );
		return;
	}
	my $job = $self->{'jobManager'}->get_job($id);
	if ( ref $job ne 'HASH' || !$job->{'id'} ) {
		$self->print_bad_status( { message => q(The submitted job does not exist.), navbar => 1 } );
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
	say q(<p id="footer_values" style="display:none">)
	  . qq(Progress: <span id="footer_progress">$job->{'percent_complete'}</span>%);
	say q(<br />)
	  . qq(<span class="stage" style="display:none">Stage: <span id="footer_stage">$job->{'stage'}</span></span>);
	say q(</p>);
	if ( $job->{'status'} eq 'started' || $job->{'status'} =~ /^submitted/x ) {
		say q(<div id="cancel_refresh">);
		$self->_print_cancel_button($job);
		say q(<p>This page will periodically refresh. You can manually refresh it any time, )
		  . q(or bookmark it and close your browser if you wish.</p>);
		say q(</div>);
	}
	if ( BIGSdb::Utils::is_int( $self->{'config'}->{'results_deleted_days'} ) ) {
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
	if ( !( $job->{'message_html'} || ref $output eq 'HASH' ) ) {
		say q(<div id="resultstable"></div>);
		return;
	}
	say q(<div class="box" id="resultstable">);
	say q(<h2>Output</h2>);
	say $job->{'message_html'} if $job->{'message_html'};
	my @buffer;
	my $include_in_tar = 0;
	foreach my $description ( sort keys(%$output) ) {
		my ( $link_text, $comments ) = split /\|/x, $description;
		$link_text =~ s/^\d{2}_//x;    #Descriptions can start with 2 digit number for ordering
		my %icons = (
			txt   => TEXT_FILE,
			xlsx  => EXCEL_FILE,
			png   => IMAGE_FILE,
			svg   => IMAGE_FILE,
			fas   => FASTA_FILE,
			xmfa  => FASTA_FILE,
			aln   => ALIGN_FILE,
			align => ALIGN_FILE,
			json  => CODE_FILE
		);
		my $url       = qq(/tmp/$output->{$description});
		my $file_type = 'misc';
		if ( $url =~ /\.([A-z]+)$/x ) {
			$file_type = $1;
		}
		my $icon = $icons{$file_type} // MISC_FILE;
		my $text =
		    qq(<div class="file_output"><a href="$url">)
		  . qq(<span style="float:left;margin-right:1em">$icon</span></a>)
		  . qq(<div style="width:90%;margin-top:1em"><a href="$url">$link_text</a>);
		$text .= qq( - $comments) if $comments;
		my $size = -s qq($self->{'config'}->{'tmp_dir'}/$output->{$description}) // 0;
		if ( $size > ( 1024 * 1024 ) ) {    #1Mb
			my $size_in_MB = BIGSdb::Utils::decimal_place( $size / ( 1024 * 1024 ), 1 );
			$text .= qq( ($size_in_MB MB));
		}
		$include_in_tar++ if $size < ( 10 * 1024 * 1024 );    #10MB
		if ( $output->{$description} =~ /\.png$/x ) {
			my $title = $link_text . ( $comments ? qq( - $comments) : q() );
			$text .=
			    q(<div style="margin-top:1em;text-align:center">)
			  . qq(<a href="/tmp/$output->{$description}" data-rel="lightbox-1" class="lightbox" )
			  . qq(title="$title"><img src="/tmp/$output->{$description}" alt="" )
			  . q(style="max-width:200px;border:1px dashed black" /></a><p>(click to enlarge)</p></div>);
		}
		$text .= q(</div></div>);
		push @buffer, $text;
	}
	my $tar_msg =
	  $include_in_tar < ( keys %$output )
	  ? q( (only files <10MB included - download larger files separately))
	  : q();
	my $icon = ARCHIVE_FILE;
	my $url  = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=job&amp;id=$job->{'id'}&amp;output=archive);
	push @buffer,
	    qq(<div class="file_output"><a href="$url"><span style="float:left;margin-right:1em">$icon</span></a>)
	  . q(<div style="width:90%;margin-top:1em">)
	  . qq(<a href="$url">Tar file containing all output files</a>$tar_msg</div></div>)
	  if $job->{'status'} eq 'finished' && $include_in_tar > 1;
	if (@buffer) {
		local $" = qq(\n);
		say q(<h3>Files</h3>);
		say q(<div class="grid scrollable">);
		say qq(@buffer);
		say q(</div><div style="clear:both"></div>);
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
	  . q(<span class="ui-button-text">Cancel job!</span></a></p>);
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
