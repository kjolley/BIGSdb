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
package BIGSdb::RestMonitorPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	return 'BIGSdb RESTful API Monitor';
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery c3);
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>RESTful API monitor</h1>);
	if ( !$self->{'config'}->{'rest_db'} ) {
		$self->print_bad_status(
			{
				message => 'The REST interface is not enabled',
				navbar  => 1
			}
		);
		return;
	}
	if ( !$self->{'config'}->{'rest_log_to_db'} ) {
		$self->print_bad_status(
			{
				message => 'Statistics are not being collected for the REST interface',
				navbar  => 1
			}
		);
		return;
	}
	say q(<div class="box resultspanel">);
	say q(<div id="summary">);
	say q(<div id="hits" class="dashboard_number" style="margin-right:1em"></div>);
	say q(<div id="rate" class="dashboard_number" style="margin-right:1em"></div>);
	say q(<div id="response" class="dashboard_number"></div>);
	say q(<div style="clear:both"></div>);
	say q(<div id="c3_chart" style="height:250px">);
	$self->print_loading_message( { top_margin => 0 } );
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
			default => 360,
			style   => 'margin-right:1em;margin-bottom:0.5em'
		}
	);
	say q(<span style="white-space:nowrap"><label for="interval">Interval:</label>);
	$labels = {
		1  => '1 minute',
		2  => '2 minutes',
		5  => '5 minutes',
		10 => '10 minutes',
		30 => '30 minutes',
		60 => '1 hour'
	};
	say $q->popup_menu(
		{
			id      => 'interval',
			values  => [ 1, 2, 5, 10, 30, 60 ],
			labels  => $labels,
			default => 5
		}
	);
	say q(</span>);
	say q(</div></div>);
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $url = "$self->{'system'}->{'script_name'}?page=ajaxRest";
	my $max_rest_hits_per_second_warn = $self->{'config'}->{'max_rest_hits_per_second_warn'} // 10;
	my $max_avg_response_warn         = $self->{'config'}->{'max_avg_response_warn'}         // 500;
	my $buffer                        = << "END";
var summary_interval;
var chart_interval;
var max_rest_hits_per_second_warn = $max_rest_hits_per_second_warn;
var max_avg_response_warn = $max_avg_response_warn;
\$(function () {
	var mins = \$("#period").val();
	if (typeof mins == 'undefined'){
		mins = 720;
	}
	var interval = \$("#interval").val();
	if (typeof interval == 'undefined'){
		mins = 2;
	}
	var url = "$url" + "&minutes=" + mins + "&interval=" + interval;
	load_chart(url);
	refresh_summary(url + "&summary=1");
	\$("#period_select").show();
	summary_interval = setInterval(function(){
		refresh_summary(url + "&summary=1");
	}, 30000);

	\$("#period").off("change").on("change",function(){
		clearInterval(summary_interval);
		mins = \$("#period").val();
		url = "$url" + "&minutes="+mins;
		refresh_summary(url + "&summary=1");	
		load_chart(url);	
		summary_interval = setInterval(function(){refresh_summary(url + "&summary=1")}, 30000);
	});	
	\$("#interval").off("change").on("change",function(){
		interval = \$("#interval").val();
		url = "$url" + "&minutes="+mins + "&interval=" + interval;
		load_chart(url);
	});			
});

function get_colour_function (max) {
	return d3.scaleLinear()
		.domain([0,max])
		.range(["#024fea", "#ea022c"])
      	.interpolate(d3.interpolateHcl);
}

function refresh_summary (url){
	d3.json(url).then (function(jsonData){
		var hits_per_second = jsonData.hits / (jsonData.period * 60);
		var rate_colour =  get_colour_function(max_rest_hits_per_second_warn);
		var colour_number = hits_per_second > max_rest_hits_per_second_warn ? max_rest_hits_per_second_warn : parseInt(hits_per_second);
		\$("#hits").html('<p class="dashboard_number_detail">Hits</p><p class="dashboard_number">' + jsonData.hits + '</p>');
		\$("#rate").html('<p class="dashboard_number_detail">Rate</p><p class="dashboard_number" style="color:' 
		+ rate_colour(colour_number) + '">' + parseInt(hits_per_second * 60) + '/min</p>');
		
		var response_colour =  get_colour_function(max_avg_response_warn);
		colour_number = jsonData.avg_response > max_avg_response_warn ? max_avg_response_warn : jsonData.avg_response;
		\$("#response").html('<p class="dashboard_number_detail">Avg response</p><p class="dashboard_number" style="color:' 
		+ response_colour(colour_number) + '">' + jsonData.avg_response + ' ms</p>');
		clearInterval(summary_interval);
		summary_interval = setInterval(function(){refresh_summary(url)}, 30000);
	});
}

function load_chart(url){
	var interval =parseInt(\$("#interval").val());
	d3.json(url).then (function(jsonData){
		var chart = c3.generate({
			bindto: '#c3_chart',
			title: {
				text: 'API requests'
			},
			data: {
				x: "start",
				xFormat: "%Y-%m-%d %H:%M:%S",
				json: jsonData,
				keys: {
					x: 'start',
					value: ['hits']
				},
				type: 'area-step',
			},
			line: {
				step: {
					type: "step-after"
				}
			},	
			axis: {
				x: {
					type: 'timeseries',
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
			},
			legend: {
				show: false
			},
			padding: {
				right: 20
			},
			tooltip: {
				format: {
				    title: function (x, index) {
					var timestamp = new Date(x);
					var timestamp2 = new Date(x);
					var offset = timestamp.getTimezoneOffset();
					timestamp.setMinutes( timestamp.getMinutes() - offset );
					timestamp2.setMinutes(timestamp2.getMinutes() + interval - offset);
					
					return (timestamp.getFullYear()
						+ "-" + ("0" + (timestamp.getMonth()+1)).slice(-2) + "-"
						+ ("0" + timestamp.getDate()).slice(-2) + " "
						+ ("0" + timestamp.getHours()).slice(-2) + ":"
					    + ("0" + timestamp.getMinutes()).slice(-2)
					    + " - "
						+ ("0" + timestamp2.getHours()).slice(-2) + ":"
					    + ("0" + timestamp2.getMinutes()).slice(-2));				
				    },
				    value: function (value, ratio, id, index) { return value }
				}
		    }
		});
		\$("div#waiting").css("display","none");
		clearInterval(chart_interval);
		chart_interval = setInterval(function(){load_chart(url)}, 30000);
	},function(error){
		console.log(error);
		\$("#c3_chart").html('<p style="text-align:center;margin-top:5em">'
		 + '<span class="error_message">Error accessing data.</span></p>');
	});
	
}
END
	return $buffer;
}
1;
