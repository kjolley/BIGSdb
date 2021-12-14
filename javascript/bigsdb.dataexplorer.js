/**
 * Written by Keith Jolley 
 * Copyright (c) 2021, University of Oxford 
 * E-mail: keith.jolley@zoo.ox.ac.uk
 * 
 * This file is part of Bacterial Isolate Genome Sequence Database (BIGSdb).
 * 
 * BIGSdb is free software: you can redistribute it and/or modify it under the
 * terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version.
 * 
 * BIGSdb is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License along with
 * BIGSdb. If not, see <http://www.gnu.org/licenses/>.
 */

$(function() {
	$(".tablesorter").tablesorter({ widgets: ['zebra'] });
	$("#record_age_slider").slider({
		min: 0,
		max: 7,
		value: recordAge,
		slide: function(event, ui) {
			$("#record_age").html(recordAgeLabels[ui.value]);
		},
		change: function(event, ui) {
			$("#filter_age").html(recordAgeLabels[ui.value]);
			recordAge = ui.value;
			reloadTable();
		}
	});
	$("#include_old_versions").change(function() {
		reloadTable();
	});
	$("div#data_explorer").on("click touchstart", ".expand_link", function() {
		var field = this.id.replace('expand_', '');
		if ($('#' + field).hasClass('expandable_expanded')) {
			$('#' + field).switchClass('expandable_expanded', 'expandable_retracted data_explorer', 1000, "easeInOutQuad", function() {
				$('#expand_' + field).html('<span class="fas fa-chevron-down"></span>');
			});
		} else {
			$('#' + field).switchClass('expandable_retracted data_explorer', 'expandable_expanded', 1000, "easeInOutQuad", function() {
				$('#expand_' + field).html('<span class="fas fa-chevron-up"></span>');
			});
		}
	});
	$("div#data_explorer").on("change", ".option_check,.field_selector", function() {
		if (canAnalyse()) {
			$("#analyse").removeClass("disabled");
		} else {
			$("#analyse").addClass("disabled");
		}
	});
	$("div#data_explorer").on("click touchstart", "#analyse", function() {
		if (canAnalyse()) {
			runAnalysis();
		}
	});
	if (canAnalyse()){
		$("#analyse").removeClass("disabled");
	}
});

function canAnalyse() {
	let checkbox_selected = false;
	$(".option_check").each(function() {
		if (this.checked === true) {
			checkbox_selected = true;
		}
	});
	let field_selected = false;
	$(".field_selector").each(function() {
		if (this.value !== "") {
			field_selected = true;
		}
	});
	return checkbox_selected && field_selected;
}

function runAnalysis() {
	$("div#waiting").css("display", "block");
	let values = [];
	$(".option_check").each(function() {
		if (this.checked === true) {
			let name = this.id;
			name = name.replace("v", "");
			values.push(dataIndex[name]);
		}
	});
	let fields = [field];
	$(".field_selector").each(function() {
		if (this.value !== '') {
			fields.push(this.value);
		}
	});
	let params = {
		fields: fields,
			values: values,
			include_old_versions: $("#include_old_versions").is(":checked") ? 1 : 0,
			record_age: recordAge
	};
	$.ajax({
		url: url + "&page=explorer",
		type: "POST",
		data: {
			analyse: 1,
			db: instance,
			page: "explorer",
			params: JSON.stringify(params) 
		},
		success: function(json) {
			$("div#waiting").css("display", "none");
			$("#response_test").html(json);
		}
	});
}

function reloadTable() {
	$("div#waiting").css("display", "block");
	let includeOld = $("#include_old_versions").is(":checked") ? 1 : 0;
	$.ajax({
		url: url + "&page=explorer&updateTable=1&field=" + field + "&record_age=" + recordAge + "&include_old_versions=" + includeOld
	}).done(function(json) {
		let html = JSON.parse(json).html;
		$("div#table_div").html(html);
		$(".tablesorter").tablesorter({ widgets: ['zebra'] });
		$("div#waiting").css("display", "none");
		let count = (html.match(/value_row/g) || []).length;
		$("span#unique_values").html(count);
		let total = 0;
		$('td.value_count').each(function() {
			let count = $(this).html().replace(",", "");
			total += parseInt(count, 10) || 0;
		});
		$("span#total_records").html(commify(total));
		dataIndex = JSON.parse(json).index;
		$("#analyse").addClass("disabled");
	});
}

function commify(x) {
	return x.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}