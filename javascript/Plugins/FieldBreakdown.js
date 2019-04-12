/*FieldBreakdown.pm - FieldBreakdown plugin for BIGSdb
Written by Keith Jolley
Copyright (c) 2018-2019, University of Oxford
E-mail: keith.jolley@zoo.ox.ac.uk

This file is part of Bacterial Isolate Genome Sequence Database (BIGSdb).

BIGSdb is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

BIGSdb is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.*/

$(function () {
	$.ajax({
		url: prefs_ajax_url
	})
	.done(function(data) {
		var prefObj = JSON.parse(data);
		if (prefObj.height){height=prefObj.height}; 
		if (prefObj.segments){segments=prefObj.segments};
		if (prefObj.pie == 0){pie=0} 	
  	})
  	.fail(function(response){
  		console.log(response);
  	});

  	$('input[name="field_type"][value="fields"]').prop("checked", true);
  	var field = $("#field").val();
	var initial_url = url + "&field=" + field;
	var rotate = is_vertical();
	

	get_ajax_prefs();
 	if (map_fields.includes(field)){
 		load_map(initial_url,field);
 	} else if (field_types[field] == 'integer'){
		load_bar(initial_url,field,rotate);
	} else if (field_types[field] == 'date'){
		load_line(initial_url,field,line);
	} else {
		load_pie(initial_url,field,segments);
	}	
	
	$("#field").on("change",function(){
		$("#c3_chart").css("min-height", "400px");
		d3.selectAll('svg').remove();
		$("div#waiting").css("display","block");
		$(".c3_controls").css("display", "none");			
		var rotate = is_vertical();
		var field = $('#field').val();
		var new_url = url + "&field=" + field;
		if (map_fields.includes(field)){
 			load_map(new_url,field);
		} else if (field_types[field] == 'integer'){
			load_bar(new_url,field,rotate);
		} else if (field_types[field] == 'date'){
			load_line(new_url,field,line);
		} else {
			load_pie(new_url,field,segments);
		}	
    }); 
    
   	var field_type_radio = $('input[name="field_type"]');
	field_type_radio.on("change",function(){
		var field_type = get_field_type();
		$("#field").empty();
		var list = {
			fields: field_list,
			loci: locus_list,
			schemes: scheme_list
		};
		
		$.each(list[field_type], function(index, item){
			var value;
			var label;
			if (field_type == 'schemes'){
				label = item.label;
				value = item.field;
			} else {
				label = item.replace(/^.+\.\./, "");
				value = item;
			}
			jQuery('<option/>', {
       			value: value,
       			html: label
       		}).appendTo("#field"); 
		});
		$("#field").change();
		fasta = field_type == 'loci' ? 1 : 0;
	});  

	position_controls();
	$(window).resize(function() {
		position_controls();
	});
	
	$("#export_image").off("click").click(function(){
		// fix back fill
		d3.select("#c3_chart").selectAll("path").attr("fill","none");	
		// fix no axes
		d3.select("#c3_chart").selectAll("path.domain").attr("stroke","black");
		// fix no tick
		d3.select("#c3_chart").selectAll(".tick line").attr("stroke","black");
		d3.select("#c3_chart").selectAll(".c3-axis-y2").attr("display","none");
		// Annoying 2nd x-axis
		// Hide both, then selectively show the first one.
		d3.select("#c3_chart").selectAll(".c3-axis-x").attr("display","none");
		d3.select("#c3_chart").select(".c3-axis-x").attr("display","inline");
		
		// map
		d3.select("#map").selectAll("path").attr("fill","none");	
		d3.select("#map").selectAll("path").attr("stroke","#444");
		d3.select("#map").selectAll(".background").attr("fill","none");
		var svg = d3.select("svg")
			.attr("xmlns","http://www.w3.org/2000/svg")
			.node().parentNode.innerHTML;
		svg = svg.replace(/<\/svg>.*$/,"</svg>");
		var blob = new Blob([svg],{type: "image/svg+xml"});		
		var filename = $("#field").val().replace(/^.+\.\./, "") + ".svg";
		saveAs(blob, filename);
	});
});

function get_ajax_prefs(){
	$.ajax({
  	url: prefs_ajax_url + "&loci=1"
  	}).done(function(data){
 		loci = JSON.parse(data);
   	}).fail(function(response){
  		console.log(response);
  	});
  	$.ajax({
  		url: prefs_ajax_url + "&scheme_fields=1"
  	}).done(function(data){
 		schemes = JSON.parse(data);
   	}).fail(function(response){
  		console.log(response);
  	});
}

function position_controls(){
	if ($(window).width() < 800){
		$(".c3_controls").css("position", "static");
		$(".c3_controls").css("float", "left");
	} else {
		$(".c3_controls").css("position", "absolute");
		$(".c3_controls").css("clear", "both");
	}
}

function is_vertical() {
	var orientation_radio = $('input[name="orientation"]');
	var checked = orientation_radio.filter(function() {
	    	return $(this).prop('checked');
	  	});
	var orientation = checked.val();
	return orientation == 'vertical' ? 1 : 0;
}

function get_field_type() {
	var field_type_radio = $('input[name="field_type"]');
	var checked = field_type_radio.filter(function() {
		return $(this).prop('checked');
	});
	var field_type = checked.val();
	return field_type;
}

function load_map(url,field){
	var div_width = $("#map").width();
	$("#c3_chart").html("");
	var unit_id = field == 'country' ? 'iso3' : 'continent';
	var units = field == 'country' ? 'units' : 'continents';
	var geo_file = field == 'country' ? '/javascript/topojson/countries.json' : '/javascript/topojson/continents.json';
	var colours = colorbrewer.Greens[5];
	d3.json(url).then(function(data) {
		var max = get_range_max(data);
		console.log(max);
		var	map = d3.geomap.choropleth()
			.geofile(geo_file)
			.colors(colours)
			.column('value')
			.format(d3.format(",d"))
			.legend({
				width : 50,
				height : 120
			})
			.projection(d3.geoNaturalEarth)
			.duration(1000)
			.domain([ 0, max ])
			.valueScale(d3.scaleQuantize)
			.unitId(unit_id)
			.units(units)
			.postUpdate(function(){finished_map(url,field)});
		var selection = d3.select('#map').datum(data);
		map.draw(selection);
		$(window).resize(function() {
			delay(function(){
				if (div_width != $("#map").width()){
					div_width = $("#map").width();
					$("#map").html("");
					load_map(url,field);
				}
			}, 500);		
		});	
	});
}

var delay = (function() {
	var timer = 0;
	return function(callback, ms){
		clearTimeout(timer);
		timer = setTimeout(callback, ms);	
	};
})();

// Choose max value so that ~5% of records are in top fifth (40% if <= 10 records).
function get_range_max(data) {
	var records = data.length;
	var percent_in_top_fifth = records > 10 ? 0.05 : 0.4;
	var target = parseInt(percent_in_top_fifth * records);
	var multiplier = 10;
	var max;
	
	while (true){
		var test = [1,2,5,10];
		for (var i = 0; i < test.length; i++) { 
			max = test[i] * multiplier;
			var top_division_start = max * 4 / 5;
			var in_top_fifth = 0;
			for (var j = 0; j < data.length; j++) { 
				if (data[j].value >= top_division_start){
					in_top_fifth++;
				}
			}
			if (in_top_fifth <= target){
				return max;
			}
		}
		multiplier = multiplier * 10;
		if (max > 10000000){
			return max;
		}
	}
}


function finished_map(url,field){
	$("div#waiting").css("display","block");
	$("#bar_controls").css("display","none");
	$("#line_controls").css("display","none");
	$("#pie_controls").css("display","none");
	$(".transform_to_pie").css("display","inline");
	$(".transform_to_donut").css("display","inline");
	$(".transform_to_bar").css("display","none");
	$(".transform_to_line").css("display","none");
	$("#map_controls").css("display","block");
	$(".transform_to_donut").off("click").click(function(){
		$("div#waiting").css("display","block");
		d3.selectAll("svg").remove();
		load_pie(url,field,segments);		
		pie = 0;
		$("#c3_chart").css("min-height", "400px");
	});
	$(".transform_to_pie").off("click").click(function(){
		$("div#waiting").css("display","block");
		d3.selectAll("svg").remove();
		load_pie(url,field,segments);
		pie = 1;
		$("#c3_chart").css("min-height", "400px");
	});
	show_export_options();
	$("div#waiting").css("display","none");
	$("#c3_chart").css("min-height", 0);
	$(".legend-bg").css("fill","none");	
}

function load_pie(url,field,max_segments) {
	$("#bar_controls").css("display", "none");
	$("#line_controls").css("display", "none");
	$("#map_controls").css("display","none");
	var title = field.replace(/^.+\.\./, "");
	title = title.replace(/^s_\d+_/,"");
	var f = d3.format(".1f");
	d3.json(url).then (function(jsonData) {			
		var data = pie_json_to_cols(jsonData,max_segments);
		
		// Load all data first otherwise a glitch causes one segment to be
		// missing
		// when increasing number of segments.
		var all_data = pie_json_to_cols(jsonData,50);
		
		// Need to create 'Others' segment otherwise it won't display properly
		// if needed when reducing segment count.
		all_data.columns.push(['Others',0]);
		
		var plural = data.count == 1 ? "" : "s";
		title += " (" + data.count + " value" + plural + ")";
		var chart = c3.generate({
			bindto: '#c3_chart',
			title: {
				text: title
			},
			data: {
				columns: all_data.columns,
				type: pie ? 'pie' : 'donut',
				order: null,
				colors: {
					'Others': '#aaa'
				}
			},
			pie: {
				label: {
					show: true					
				},
				expand: false,
			},
			legend: {
				show: true,
				position: 'bottom'
			},
			size: {
				height: 500
			},
			tooltip: {
				format: {
					value: function (value, ratio, id){
						return value + " (" + f(ratio * 100) + "%)";
					}
				}
			}
		});
		chart.unload();
		chart.load({
			columns: data.columns,
		});	
		
		$("#segments").on("slidechange",function(){
			var new_segments = $("#segments").slider('value');
			$("#segments_display").text(new_segments);
			if (segments != new_segments){
				set_prefs('segments',new_segments);
			}
			segments = new_segments;
			var data = pie_json_to_cols(jsonData,segments);
			chart.unload();
			chart.load({
				columns: data.columns,
			});	

		});
		if (max_segments != segments){
			var data = pie_json_to_cols(jsonData,segments);
			chart.unload();
			chart.load({
				columns: data.columns,
			});
		}
		$(".transform_to_donut").off("click").click(function(){
			chart.transform('donut');
			$(".transform_to_donut").css("display","none");
			$(".transform_to_pie").css("display","inline");
			pie = 0;
			set_prefs('pie',0);
		});
		$(".transform_to_pie").off("click").click(function(){
			chart.transform('pie');
			$(".transform_to_pie").css("display","none");
			$(".transform_to_donut").css("display","inline");
			pie = 1;
			set_prefs('pie',1);
		});
		$(".transform_to_map").off("click").click(function(){
			$(".transform_to_map").css("display","none");
			
			load_map(url,field);
			$(".transform_to_pie").css("display","inline");
			$(".transform_to_donut").css("display","inline");
			pie = 1;
			set_prefs('pie',1);
		});
		$("#segment_control").css("display","block");
		$("#segments").slider({min:5,max:50,value:segments});
		$("#segments_display").text(segments);
		$(".transform_to_map").css("display", map_fields.includes(field) ? "inline" : "none");
		$(".transform_to_pie").css("display",pie ? "none" : "inline");
		$(".transform_to_donut").css("display",pie ? "inline": "none");
		$(".transform_to_bar").css("display","none");
		$(".transform_to_line").css("display","none");
		$("#pie_controls").css("display","block");
		show_export_options();
		$("div#waiting").css("display","none");
	},function(error) {
		console.log(error);
		$("#c3_chart").html('<p style="text-align:center;margin-top:5em">'
		 + '<span class="error_message">Error accessing data.</span></p>');
	});
}

function pie_json_to_cols(jsonData,segments){
	var columns = [];
	var first_other = [];
	var count = 0;
	var others = 0;
	var other_fields = 0;
	jsonData.forEach(function(e) {
		e.label = e.label.toString(); 
		count++;
		if (count >= segments){
			others += e.value;
			other_fields++;
			if (count == segments){
				first_other = [e.label, e.value];
			}
		} else {
			columns.push([e.label, e.value]);
		}
	}) 
	if (other_fields == 1){
		columns.push(first_other);
	} else if (other_fields > 1){
		columns.push(['Others',others]);
	}
	return {columns: columns, count: count};  
}

function load_line(url,field,cumulative) {
	$("#bar_controls").css("display", "none");
	$("#pie_controls").css("display", "none");
	$("#map_controls").css("display","none");
	// Prevent multiple event firing after reloading
	$("#line_height").off("slidechange");
	var data = [];
	var title = field.replace(/^.+\.\./, "");

	d3.json(url).then (function(jsonData) {
		var values = ['value'];
		var fields = ['date'];
		var count = 0;
		var total = 0;
		jsonData.forEach(function(e) {
			count++;
			
			fields.push(e.label);
			if (cumulative){
				total += e.value;
				values.push(total);
			} else {
				values.push(e.value);
			}
		});
		var plural = count == 1 ? "" : "s";
		title += " (" + count + " value" + plural + ")";
		
		var chart = c3.generate({
			bindto: '#c3_chart',
			title: {
				text: title
			},
			data: {
				x: 'date',
				columns: [
					fields,
					values
				],
				type: line ? 'line' : 'bar',
				order: 'asc',
			},			

			axis: {
				x: {
					type: 'timeseries',
					tick: {
                		format: '%Y-%m-%d',
                		count: 100,
                		rotate: 90,
                		fit: true
           			},
					height: 100
				}
			},
			legend: {
				show: false
			}
		});

		chart.resize({				
			height: height
		});
		
		$(".transform_to_bar").off("click").click(function(){
			chart.unload();
			load_line(url,field,0);
			$(".transform_to_bar").css("display","none");
			$(".transform_to_line").css("display","inline");
			line = 0;
		});
		$(".transform_to_line").off("click").click(function(){
			chart.unload();
			load_line(url,field,1);
			$(".transform_to_line").css("display","none");
			$(".transform_to_bar").css("display","inline");
			line = 1;
		});
		
		$(".transform_to_line").css("display",line ? "none" : "inline");
		$(".transform_to_bar").css("display",line ? "inline": "none");
		$(".transform_to_pie").css("display","none");
		$(".transform_to_donut").css("display","none");
		
		$("#line_controls").css("display", "block");
		$("#line_height").slider({min:300,max:800,value:height});
		$("#line_height").on("slidechange",function(){
			var new_height = $("#line_height").slider('value');
			height = new_height;
			chart.resize({				
				height: height
			});
			set_prefs('height',height);
		});
		show_export_options();
		$("div#waiting").css("display","none");
	},function(error) {
		console.log(error);
		$("#c3_chart").html('<p style="text-align:center;margin-top:5em">'
		 + '<span class="error_message">Error accessing data.</span></p>');
	});	
}

function load_bar_json(jsonData,field,rotate){
	$("#line_controls").css("display", "none");
	$("#pie_controls").css("display", "none");
	$("#map_controls").css("display","none");
	$("#bar_height").off("slidechange");
	var title = field.replace(/^.+\.\./, "");
	var count = Object.keys(jsonData).length;
	var plural = count == 1 ? "" : "s";
	title += " (" + count + " value" + plural + ")";
	
	var chart = c3.generate({
		bindto: '#c3_chart',
		title: {
			text: title
		},
		data: {
			json: jsonData,
			keys: {
				x: 'label',
				value: ['value']
			},
			type: 'bar',
		},	
		bar: {
			width: {
				ratio: 0.7
			}
		},
		axis: {
			rotated: rotate,
			x: {
				type: 'category',
				tick: {
					culling: true,
				},
				height: 100
			}
		},
		legend: {
			show: false
		},
		padding: {
			right: 20
		}
	});
	chart.resize({				
		height: height
	});
		
	$("#bar_height").slider({min:300,max:800,value:height});
	$("#bar_controls").css("display", "block");
	$("#bar_height").on("slidechange",function(){
		var new_height = $("#bar_height").slider('value');
		height = new_height;
		chart.resize({				
			height: height
		});
		set_prefs('height',height);
	});
	show_export_options();		
}

function load_bar(url,field,rotate) {
	d3.json(url).then (function(jsonData) {
		load_bar_json(jsonData,field,rotate);
		$("div#waiting").css("display","none");
	},function(error) {
		console.log(error);
		$("#c3_chart").html('<p style="text-align:center;margin-top:5em">'
		 + '<span class="error_message">Error accessing data.</span></p>');
	});
	var orientation_radio = $('input[name="orientation"]');
	orientation_radio.on("change",function(){
		var field = $('#field').val();
		rotate = is_vertical();
		// Reload by URL rather than from already downloaded JSON data
		// as it seems that the required unload() function currently has a
		// memory leak.
		load_bar(url,field,rotate);
	});
}

function show_export_options () {
	var field = $('#field').val();
	$("a#export_table").attr("href", url + "&export=" + field + "&format=table");
	$("a#export_excel").attr("href", url + "&export=" + field + "&format=xlsx");
	$("a#export_text").attr("href", url + "&export=" + field + "&format=text");
	$("a#export_fasta").attr("href", url + "&export=" + field + "&format=fasta");
	$("a#export_fasta").css("display", fasta ? "inline" : "none");
	$("#export").css("display", "block");
}

function set_prefs(attribute, value){
	$.ajax(prefs_ajax_url + "&update=1&attribute=" + attribute + "&value=" + value);
}