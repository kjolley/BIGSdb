#Written by Keith Jolley
#Copyright (c) 2019, University of Oxford
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
package BIGSdb::JobMonitorPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	return 'BIGSdb Jobs Monitor';
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery c3);
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Jobs Monitor</h1>);
	if ( !$self->{'config'}->{'jobs_db'} ) {
		$self->print_bad_status(
			{
				message => 'Offline jobs are disabled',
				navbar  => 1
			}
		);
		return;
	}
	say q(<div class="box resultspanel">);
	say q(<div id="summary">);
	say q(<div id="running" class="dashboard_number"></div>);
	say q(<div id="queued" class="dashboard_number"></div>);
	say q(<div id="day" class="dashboard_number optional"></div>);
	if ( ( $self->{'config'}->{'results_deleted_days'} // 0 ) >= 7 ) {
		say q(<div id="week" class="dashboard_number optional"></div>);
	}
	if ( $self->{'config'}->{'rest_db'} && $self->{'config'}->{'rest_log_to_db'} ) {
		say q(<div id="links" class="dashboard_link">)
		  . qq(<a href="$self->{'system'}->{'script_name'}?page=restMonitor" title="RESTful API monitor">)
		  . q(<span class="fas fa-code fa-3x"></span></a></div>);
	}
	say q(<div style="clear:both"></div>);
	say q(</div>);
	say q(<div id="c3_chart" style="height:250px">);
	$self->print_loading_message;
	say q(</div>);
	say q(<div id="period_select" style="display:none"><label for="period">Period:</label>);
	my $labels = {
		30   => '30 minutes',
		60   => '1 hour',
		120  => '2 hours',
		360  => '6 hours',
		720  => '12 hours',
		1440 => '24 hours',
		2880 => '2 days',
		4320 => '3 days',
		5760 => '4 days',
		7200 => '5 days'
	};
	say $q->popup_menu(
		{
			id      => 'period',
			values  => [ 30, 60, 120, 360, 720, 1440, 2880, 4320, 5760, 7200 ],
			labels  => $labels,
			default => 720
		}
	);
	say q(</div></div>);
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $url = "$self->{'system'}->{'script_name'}?page=ajaxJobs";
	my $max_queued_colour_warn  = $self->{'config'}->{'max_queued_colour_warn'}  // 10;
	my $max_running_colour_warn = $self->{'config'}->{'max_running_colour_warn'} // 10;
	my $buffer                  = << "END";
var chart_interval;
var summary_interval;
var max_running_colour_warn = $max_running_colour_warn;
var max_queued_colour_warn = $max_queued_colour_warn;
\$(function () {
	var mins = \$("#period").val();
	if (typeof mins == 'undefined'){
		mins = 720;
	}
	load_chart("$url&minutes=" + mins);
	refresh_summary("$url&summary=1");
	
	showhide_optional_dashboard_numbers();
	showhide_optional_dashboard_links();
	\$(window).resize(function() {
		showhide_optional_dashboard_numbers();
		showhide_optional_dashboard_links();
	});
});

function showhide_optional_dashboard_numbers(){
	if (\$(window).width() < 600){
		\$(".optional").hide();
	} else {
		\$(".optional").show();
	}
}

function showhide_optional_dashboard_links(){
	if (\$(window).width() < 680){
		\$(".dashboard_link").hide();
	} else {
		\$(".dashboard_link").show();
	}
}

function load_chart(url){	
	d3.json(url).then (function(jsonData){
		var time = ["time"];
		var queued = ["queued"];
		var running = ["running"];
		jsonData.forEach(function(e) {
			time.push(e.time);
			queued.push(e.queued);
			running.push(e.running);
		});
		var chart = c3.generate({
			bindto: "#c3_chart",
			title: {
				text: "Queued and running jobs"
	    	},
			data: {
				x: "time",
				xFormat: "%Y-%m-%d %H:%M:%S",
				columns: [
					time,
					queued,
					running
				],
				types: {
					queued: "area-step",
					running: "area-step"
				},				
			},
			line: {
				step: {
					type: "step-after"
				}
			},
			point: {
				show: false
			},
			axis: {
				x: {
					type: "timeseries",
					tick: {
						format: function(x) {
						    var timestamp = new Date(x);
						    var offset = timestamp.getTimezoneOffset();
						    timestamp.setMinutes( timestamp.getMinutes() - offset );
						    return ("0" + timestamp.getHours()).slice(-2) + ":" + ("0" + timestamp.getMinutes()).slice(-2);
						},
						count: 6
					}

				},
				y: {
		    		tick: {
						format: function (x) {
	                    	if (x != Math.floor(x)) {
								var tick = d3.selectAll('.c3-axis-y g.tick').filter(function () {
		                    		var text = d3.select(this).select('text').text();
		                    		return +text === x;
	                      		}).style('opacity', 0);
								return '';
	                    	}
	                    	return x;
						}
           			}  
       			}
			},
			padding: {
				right:20
			},
		    tooltip: {
				format: {
				    title: function (x, index) {
					var timestamp = new Date(x);
					var offset = timestamp.getTimezoneOffset();
					timestamp.setMinutes( timestamp.getMinutes() - offset );
					return (timestamp.getFullYear()
						+ "-" + ("0" + (timestamp.getMonth()+1)).slice(-2) + "-"
						+ ("0" + timestamp.getDate()).slice(-2) + " "
						+ ("0" + timestamp.getHours()).slice(-2)) + ":"
					        + ("0" + timestamp.getMinutes()).slice(-2);
					
				    },
				    value: function (value, ratio, id, index) { return value }
				}
		    }
		});
		\$(".c3-title").css("font-weight","600");
		\$("#period_select").show();
		chart_interval = setInterval(function(){refresh_chart(chart,url)}, 30000);
		\$("#period").off("change").on("change",function(){
			clearInterval(chart_interval);
			var mins = \$("#period").val();
			url = "$url&minutes="+mins;
			refresh_chart(chart, url);			
			chart_interval = setInterval(function(){refresh_chart(chart,url)}, 30000);
		});		
	},function(error){
		console.log(error);
		\$("#c3_chart").html('<p style="text-align:center;margin-top:5em">'
		 + '<span class="error_message">Error accessing data.</span></p>');
	});	
}

function refresh_chart (chart, url){
	d3.json(url).then (function(jsonData){
		var time = ["time"];
		var queued = ["queued"];
		var running = ["running"];
		jsonData.forEach(function(e) {
			time.push(e.time);
			queued.push(e.queued);
			running.push(e.running);
		});
		chart.load({			
			columns: [
				time,
				queued,
				running
			]				
		});
	});
}

function get_colour_function (max) {
	return d3.scaleLinear()
		.domain([0,max])
		.range(["#024fea", "#ea022c"])
      	.interpolate(d3.interpolateHcl);
}

function refresh_summary (url){
	d3.json(url).then (function(jsonData){
		var running_colour =  get_colour_function(max_running_colour_warn);
		var colour_number = jsonData.running > max_running_colour_warn ? max_running_colour_warn : jsonData.running;
 		\$("#running").html('<p class="dashboard_number_detail">Running</p><p class="dashboard_number" style="color:' 
		+ running_colour(colour_number) + '">' + jsonData.running + '</p>');
		var queue_colour = get_colour_function(max_queued_colour_warn);
		var queue_number = jsonData.queued > max_queued_colour_warn ? max_queued_colour_warn : jsonData.queued;
		\$("#queued").html('<p class="dashboard_number_detail">Queued</p><p class="dashboard_number" style="color:' 
		+ queue_colour(queue_number) + '">' + jsonData.queued + '</p>');
		\$("#day").html('<p class="dashboard_number_detail">Past 24h</p><p class="dashboard_number">' + 
		jsonData.day + '</p>');
		if (typeof jsonData.week != "undefined"){
			\$("#week").html('<p class="dashboard_number_detail">Past week</p><p class="dashboard_number">' + 
			jsonData.week + '</p>');
		}
		clearInterval(summary_interval);
		summary_interval = setInterval(function(){refresh_summary(url)}, 30000);
	});
}

END
	return $buffer;
}
1;
