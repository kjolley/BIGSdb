/**
 * Written by Keith Jolley 
 * Copyright (c) 2021-2023, University of Oxford 
 * E-mail: keith.jolley@biology.ox.ac.uk
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

var currentRequest = null;
var lastAjaxUpdate = new Date().getTime();
var ajaxDelay = 1000;
const MOBILE_WIDTH = 480;

$(function() {
	showOrHideElements();
	$("select#add_field,label[for='add_field']").css("display", "inline");
	var fill_gaps = $("#fill_gaps").prop('checked');
	var open_new = $("#open_new").prop('checked');
	var grid;
	try {
		grid = new Muuri('#dashboard', {
			dragEnabled: true,
			layout: {
				fillGaps: fill_gaps
			},
			dragStartPredicate: function(item, e) {
				return enable_drag;
			}
		}).on('move', function() {
			setGridMargins(grid);
			saveLayout(grid);
		});
		if (order) {
			loadLayout(grid, order);
		}
	} catch (err) {
		console.log(err.message);
	}
	$("#record_age_slider").slider({
		min: 0,
		max: 7,
		value: recordAge,
		slide: function(event, ui) {
			$("#record_age").html(recordAgeLabels[ui.value]);
		},
		change: function(event, ui) {
			var age_url = url + "&page=dashboard&updateDashboard=1&type=" + dashboard_type;
			age_url += "&attribute=record_age&value=" + ui.value;
			if (typeof projectId !== 'undefined') {
				age_url += "&project_id=" + projectId;
			}
			$.ajax({
				url: age_url
			}).done(function(json) {
				$("#loaded_dashboard").val(JSON.parse(json).dashboard_name);
				$("#loaded_dashboard").prop("disabled", false);
				$("#delete_dashboard").css("display", "inline");
				$("#filter_age").html(recordAgeLabels[ui.value]);
				reloadAllElements();
			});
		}
	});
	$("#dashboard_panel_trigger,#close_dashboard_trigger").click(function() {
		$("#modify_dashboard_panel").toggle("slide", { direction: "right" }, "fast");
		$("#dashboard_panel_trigger").show();
		return false;
	});
	$("#dashboard_panel_trigger").show();
	$(document).mouseup(function(e) {
		var container = $("#modify_dashboard_panel");

		// if the target of the click isn't the container nor a
		// descendant of the container
		if (!container.is(e.target) && container.has(e.target).length === 0) {
			container.hide();
		}
	});
	$("#fill_gaps").change(function() {
		fill_gaps = $("#fill_gaps").prop('checked');
		try {
			grid._settings.layout.fillGaps = fill_gaps;
			grid.layout();
		} catch (err) {
			// Grid is empty.
		}
		var gaps_url = url + "&page=dashboard&updateDashboard=1&type=" + dashboard_type;
		if (typeof projectId !== 'undefined') {
			gaps_url += "&project_id=" + projectId;
		}
		gaps_url += "&attribute=fill_gaps&value=" + (fill_gaps ? 1 : 0);
		$.ajax({
			url: gaps_url
		}).done(function(json) {
			updateDashboardName(JSON.parse(json).dashboard_name);
		});
	});
	$("#enable_drag").change(function() {
		enable_drag = $("#enable_drag").prop('checked');
		$.ajax({
			url: url + "&page=dashboard&updateGeneralPrefs=1&attribute=enable_drag&value=" + (enable_drag ? 1 : 0)
		});
	});
	$("#edit_elements").change(function() {
		var edit_elements = $("#edit_elements").prop('checked');
		$.ajax(url + "&page=dashboard&updateGeneralPrefs=1&attribute=edit_elements&value=" + (edit_elements ? 1 : 0));
		$("span.dashboard_edit_element").css("display", edit_elements ? "inline" : "none");
	});
	$("#remove_elements").change(function() {
		var remove_elements = $("#remove_elements").prop('checked');
		$.ajax(url + "&page=dashboard&updateGeneralPrefs=1&attribute=remove_elements&value=" + (remove_elements ? 1 : 0));
		$("span.dashboard_remove_element").css("display", remove_elements ? "inline" : "none");
	});
	$("#open_new").change(function() {
		open_new = $("#open_new").prop('checked');
		$.ajax({
			url: url + "&page=dashboard&updateGeneralPrefs=1&attribute=open_new&value=" + (open_new ? 1 : 0)
		}).done(function() {
			reloadElementsWithURL();
		});
	});
	$("#include_old_versions").change(function() {
		var include_old_versions = $("#include_old_versions").prop('checked');
		var old_url = url + "&page=dashboard&updateDashboard=1&type=" + dashboard_type;
		if (typeof projectId !== 'undefined') {
			old_url += "&project_id=" + projectId;
		}
		old_url += "&attribute=include_old_versions&value=" + (include_old_versions ? 1 : 0);
		$.ajax({
			url: old_url
		}).done(function(json) {
			updateDashboardName(JSON.parse(json).dashboard_name);
			$("#filter_versions").html(include_old_versions ? 'all' : 'current');
			reloadAllElements();
		});
	});
	$("#dashboard_palette").change(function() {
		var name = $("#dashboard_palette").val();
		var change_dashboard_url = url + "&page=dashboard&updateDashboard=1&type=" + dashboard_type;
		if (typeof projectId !== 'undefined') {
			change_dashboard_url += "&project_id=" + projectId;
		}		
		change_dashboard_url += "&attribute=palette&value=" + name;
		$.ajax({
			url: change_dashboard_url
		}).done(function(json){
			updateDashboardName(JSON.parse(json).dashboard_name);
			reloadAllElements();
		});
	});
	$("#loaded_dashboard").change(function() {
		var name = $("#loaded_dashboard").val();
		var rename_url = url + "&page=dashboard&type=" + dashboard_type;
		if (typeof projectId !== 'undefined') {
			rename_url += "&project_id=" + projectId;
		}
		rename_url += "&updateDashboardName=" + encodeURIComponent(name);
		if (name.length) {
			$.ajax(rename_url);
		}
	});

	$("#switch_dashboard").change(function() {
		var id = $("#switch_dashboard").val();
		var switch_url = url + "&page=dashboard&setActiveDashboard=" + id + "&type=" + dashboard_type;
		if (typeof projectId !== 'undefined') {
			switch_url += "&project_id=" + projectId;
		}
		$.ajax({
			url: switch_url
		}).done(function() {
			//Prevent form reload message on Firefox - simulate click of the submit button instead.
			if ($("input#search").length) {
				$("input#search").trigger('click');
			} else {
				location.reload();
			}
		});
	});

	$("#add_element").click(function() {
		var nextId = getNextid();
		addElement(grid, nextId);
		setGridMargins(grid);
	});

	$("div#dashboard").on("click touchstart", ".dashboard_edit_element", function() {
		let id = $(this).attr('data-id');
		editElement(grid, id);
	});
	$("div#dashboard").on("click touchstart", ".dashboard_remove_element", function() {
		let id = $(this).attr('data-id');
		removeElement(grid, id);
	});
	$("div#dashboard").on("click touchstart", ".setup_element", function() {
		let id = $(this).attr('data-id');
		editElement(grid, id);
	});
	$("div#dashboard").on("click touchstart", ".dashboard_data_query_element", function() {
		let id = $(this).attr('data-id');
		let query_url = url + "&page=query";
		let params = getDataQueryParams(id);
		post(query_url, params);
	});
	$("div#dashboard").on("click touchstart", ".dashboard_data_explorer_element", function() {
		let id = $(this).attr('data-id');
		let explorer_url = url + "&page=explorer";
		let params = getDataExplorerParams(id);
		post(explorer_url, params);
	});
	applyFormatting();

	var dimension = ['width', 'height'];
	dimension.forEach((value) => {
		$(document).on("change", '.' + value + '_select', function(event) {
			var id = $(this).attr('id');
			var element_id = id.replace("_" + value, "");
			changeElementDimension(grid, element_id, value);
		});
	});
	$(document).on("change", '.element_option', function(event) {
		var id = $(this).attr('id');
		var attribute = id.replace(/^\d+_/, "");
		var element_id = id.replace("_" + attribute, "");
		var value;
		if (attribute == 'hide_mobile') {
			value = $(this).prop('checked');
			if (value) {
				$("div#element_" + element_id + " div.item-content").addClass("hide_mobile");
			} else {
				$("div#element_" + element_id + " div.item-content").removeClass("hide_mobile");
			}
		} else {
			value = $(this).val();
		}
		changeElementAttribute(grid, element_id, attribute, value);
	});
	$(document).on("click", '.marker_colour', function(event) {
		var id = $(this).attr('id');
		var attribute = 'marker_colour';
		var value = id.replace(/^\d+_/, "");
		var element_id = id.replace("_" + value, "");
		value = value.replace(/^marker_/, "");
		changeElementAttribute(grid, element_id, attribute, value);
	});
	$(document).on("click change touchstart mouseup keyup", '.marker_size', function(event) {
		var id = $(this).attr('id');
		var attribute = 'marker_size';
		var element_id = id.replace("_" + value, "");
		var value = $(this).slider("option", "value");
		var element_id = id.replace("_" + attribute, "");
		changeElementAttribute(grid, element_id, attribute, value);
	});
	$(document).on("change", '.palette_selector', function(event) {
		var id = $(this).attr('id');
		id = id.replace(/_palette$/, "");
		show_palette(id);
	});
	$('.multi_menu_trigger').on('click', function() {
		var trigger_id = this.id;
		var panel_id = trigger_id.replace('_trigger', '_panel');
		if ($("#" + panel_id).css('display') == 'none') {
			$("#" + panel_id).slideDown();
			$("#" + trigger_id).html('<span class="fas fa-minus"></span>');
		} else {
			$("#" + panel_id).slideUp();
			$("#" + trigger_id).html('<span class="fas fa-plus"></span>');
		}
	});
	$('a#dashboard_toggle').on('click', function() {
		$.get(url + "&page=dashboard&updateGeneralPrefs=1&attribute=default&value=0", function() {
			window.location = url;
		});
	});
	$(window).resize(function() {
		showOrHideElements();
		setGridMargins(grid)
		loadNewElements();
	});
	setGridMargins(grid);
	window.dispatchEvent(new Event('resize'));
});

function getDataQueryParams(id) {
	let params = {};
	if (elements[id]['post_data']) {
		params = elements[id]['post_data'];
	}
	params['page'] = 'query';
	params['db'] = instance;
	if (elements[id]['specific_values'] != null && elements[id]['visualisation_type'] == 'specific values') {
		let values = elements[id]['specific_values'];
		params['list'] = Array.isArray(values) ? values.join("\n") : values;
		params['attribute'] = elements[id]['field'];
	}
	params['sent'] = 1;
	if ($("#include_old_versions").prop('checked')) {
		params['include_old'] = 'on';
	}
	let recordAgeIndex = $("#record_age_slider").slider("value");
	if (recordAgeIndex > 0) {
		params['prov_field1'] = 'f_date_entered';
		params['prov_operator1'] = '>=';
		params['prov_value1'] = datestamps[recordAgeIndex];
	}
	if (typeof projectId !== 'undefined') {
		params['project_list'] = projectId;
	}
	return params;
}

function getDataExplorerParams(id) {
	let params = {};
	params['page'] = 'explorer';
	params['db'] = instance;
	params['field'] = elements[id]['field'];
	params['include_old_versions'] = $("#include_old_versions").prop('checked');
	params['record_age'] = $("#record_age_slider").length ? $("#record_age_slider").slider("value") : 0;
	if (elements[id]['specific_values'] != null) {
		params['specific_values'] = elements[id]['specific_values'];
	}
	if (typeof projectId !== 'undefined') {
		params['project_id'] = projectId;
	}
	return params;
}

function updateDashboardName(name) {
	$("#loaded_dashboard").val(name);
	$("#loaded_dashboard").prop("disabled", false);
	$("#delete_dashboard").css("display", "inline");
}

function setGridMargins(grid) {
	if (grid == null) {
		return;
	}
	let dashboard_width = Math.floor($("div#dashboard_panel").width() / 155) * 155;
	$("div#dashboard").css("width", dashboard_width);
	grid.on('layoutEnd', function() {
		grid.off('layoutEnd');
		let layout_width = 0
		grid.getItems().forEach(item => {
			let { left } = item.getPosition()
			let right = left + item.getWidth()
			layout_width = Math.max(layout_width, right)
		})
		if (layout_width < 300) {
			layout_width = 300;
		}
		layout_width += 10;
		if (layout_width > dashboard_width) {
			$("div#dashboard").css("width", dashboard_width);
		} else {
			$("div#dashboard").css("width", layout_width);
		}
	});
}

function showOrHideElements() {
	var small_screen = $(window).width() < MOBILE_WIDTH;
	$("div.hide_mobile").css("display", small_screen ? "none" : "block");
	$("div.hide_border").css("border", small_screen ? "0" : "1px solid #ccc");
	$.each(elements, function(index, element) {
		if (element['display'] == 'setup') {
			$("div#element_" + element['id'] + " div.item-content").css("display", "block");
		}
	});
}

//https://stackoverflow.com/questions/133925/javascript-post-request-like-a-form-submit
function post(path, params, method = 'post') {
	const form = document.createElement('form');
	form.method = method;
	form.action = path;

	for (const key in params) {
		if (params.hasOwnProperty(key)) {
			const hiddenField = document.createElement('input');
			hiddenField.type = 'hidden';
			hiddenField.name = key;
			hiddenField.value = Array.isArray(params[key]) ? JSON.stringify(params[key]) : params[key];
			form.appendChild(hiddenField);
		}
	}
	document.body.appendChild(form);
	form.submit();
}

function clean_value(value) {
	if (value == null) {
		return;
	}
	if (Array.isArray(value)) {
		value = value.map(function(el) {
			return el.trim();
		});
		value = value.filter(function(el) {
			return el != null && el != '';
		});
	} else {
		if (typeof value === 'string') {
			value = value.trim();
		}
	}
	return value;
}

function changeElementAttribute(grid, id, attribute, value) {
	if (typeof elements[id][attribute] !== 'undefined' && elements[id][attribute] === value) {
		return;
	}
	if (attribute === 'specific_values' && !Array.isArray(value)) {
		if (value.includes("\n")) {
			value = value.split("\n");
		} else {
			value = value.split();
		}
	}

	if (value == true || value == false) {
		value = value ? 1 : 0;
	} else {
		value = clean_value(value);
	}
	elements[id][attribute] = value;
	saveAndReloadElement(grid, id);
}

function applyFormatting() {
	fitty(".dashboard_big_number", {
		maxSize: 64,
		observeMutations: false
	});
	$(".item-content div.subtitle a").tooltip();
}

function getNextid() {
	if (Object.keys(elements).length === 0) {
		return 1;
	}
	var max = Math.max(...Object.keys(elements));
	return max + 1;
}

function addElement(grid, id) {
	if (Object.keys(elements).length === 0) {
		$("div#empty").html("");
	}
	var add_url = url + "&page=dashboard&type=" + dashboard_type;
	if (typeof projectId !== 'undefined') {
		add_url += "&project_id=" + projectId;
	}

	add_url += "&new=" + id;
	var field = $("#add_field").val();
	if (field) {
		add_url += "&field=" + field;
	}
	if (qryFile != null && qryFile.length) {
		add_url += "&qry_file=" + qryFile;
	}
	if (listFile != null && listFile.length && listAttribute != null && listAttribute.length) {
		add_url += "&list_file=" + listFile + "&list_attribute=" + listAttribute;
	}
	lastAjaxUpdate = new Date().getTime();
	$.get(add_url, function(json) {
		try {
			var div = document.createRange().createContextualFragment(JSON.parse(json).html);
			// Element may already exist if add button was clicked multiple
			// times before AJAX response was received.
			if (!(id in elements)) {
				grid.add([div.firstChild]);
				elements[id] = JSON.parse(json).element;
				saveElements(grid);
			}
			applyFormatting();
			showOrHideElements();
			$("div#element_" + id + " div.item-content").css("visibility", "visible");
			updateDashboardName(JSON.parse(json).dashboard_name);
			$("#delete_dashboard").css("display", "inline");
		} catch (err) {
			console.log(err.message);
		}
	});
}

function editElement(grid, id, setup) {
	$("span#control_" + id).hide();
	$("span#wait_" + id).show();
	var edit_url = url + "&page=dashboard&type=" + dashboard_type + "&control=" + id;
	if (typeof projectId !== 'undefined') {
		edit_url += "&project_id=" + projectId;
	}
	$.get(edit_url, function(html) {
		$(html).appendTo('body').modal();
		if ($("#edit_elements").prop("checked")) {
			$("span#control_" + id).show();
		}
		$("span#wait_" + id).hide();
		showOrHideControlElements(id);

		$("select.watermark_selector").fontIconPicker({
			theme: 'fip-darkgrey',
			emptyIconValue: 'none',
		});
		$("div.modal").on("change", "#" + id + "_visualisation_type", function() {
			showOrHideControlElements(id);
			checkAndShowVisualisation(grid, id);
		});
		$("div.modal").on("change", "#" + id + "_breakdown_display,#" +
			id + "_specific_value_display,#" +
			id + "_specific_values,#" +
			id + "_bar_colour_type", function() {
				showOrHideControlElements(id);
				checkAndShowVisualisation(grid, id);
			});
		$("div.modal").on($.modal.AFTER_CLOSE, function(event, modal) {
			$("div.modal").remove();
		});
	});
}

function showOrHideControlElements(id) {
	var visualisation_type = $("input[name='" + id + "_visualisation_type']:checked").val();
	var specific_value_display = $("#" + id + "_specific_value_display").val();
	var breakdown_display = $("#" + id + "_breakdown_display").val();

	//Hide all elements initially.
	$("fieldset#change_duration_control,fieldset#design_control,fieldset#order_control,fieldset#orientation_control,"
		+ "li#value_selector,li#breakdown_display_selector,li#specific_value_display_selector,"
		+ "li#top_value_selector,li#watermark_control,li#palette_control,li#text_colour_control,"
		+ "li#background_colour_control,li.gauge_colour,li#bar_colour_type,li#chart_colour,"
		+ "li#header_colour_control,li#header_background_colour_control,li#gps_map_control").css("display", "none");

	//Enable elements as required.
	if (elements[id]['display'] == 'record_count') {
		$("fieldset#change_duration_control,fieldset#design_control").css("display", "inline");
		$("li#text_colour_control,li#background_colour_control,li#watermark_control").css("display", "block");
	}

	else if (elements[id]['display'] == 'seqbin_size') {
		$("fieldset#design_control").css("display", "inline");
		$("li#chart_colour").css("display", "block");

	}

	else if (visualisation_type === 'specific values') {
		$("li#specific_value_display_selector,li#value_selector").css("display", "block");
		$("li#header_colour_control,li#header_background_colour_control").css("display", "none");
		if (specific_value_display === 'gauge') {
			$("fieldset#design_control").css("display", "inline");
			$("li.gauge_colour").css("display", "block");
			$("li#text_colour_control,li#background_colour_control").css("display", "none");
		} else if (specific_value_display === 'number') {
			$("fieldset#change_duration_control,fieldset#design_control").css("display", "inline");
			$("li#watermark_control,li#text_colour_control,li#background_colour_control").css("display", "block");

		}
	} else if (visualisation_type === 'breakdown') {
		$("li#breakdown_display_selector").css("display", "block");
		if (breakdown_display === 'bar') {
			$("fieldset#design_control,fieldset#order_control,fieldset#orientation_control,li#bar_colour_type")
				.css("display", "inline");
			var bar_colour_type = $("input[name='" + id + "_bar_colour_type']:checked").val();
			if (bar_colour_type === "continuous") {
				$("li#chart_colour").css("display", "block");
			}
		} else if (breakdown_display === 'cumulative') {
			$("fieldset#design_control").css("display", "inline");
			$("li#chart_colour").css("display", "block");
		} else if (breakdown_display === 'map') {
			$("fieldset#design_control").css("display", "inline");
			$("li#palette_control").css("display", "block");
			show_palette(id);
		} else if (breakdown_display === 'top') {
			$("fieldset#design_control").css("display", "inline");
			$("li#top_value_selector,li#header_colour_control,li#header_background_colour_control").css("display", "block");
		} else if (breakdown_display === 'gps_map') {
			$("fieldset#design_control").css("display", "inline");
			$("li#gps_map_control").css("display", "block");
		}
	}
}

function show_palette(id) {
	var palettes = {
		blue: colorbrewer.Blues[5],
		green: colorbrewer.Greens[5],
		purple: colorbrewer.Purples[5],
		orange: colorbrewer.Oranges[5],
		red: colorbrewer.Reds[5],
		'blue/green': colorbrewer.BuGn[5],
		'blue/purple': colorbrewer.BuPu[5],
		'green/blue': colorbrewer.GnBu[5],
		'orange/red': colorbrewer.OrRd[5],
		'purple/blue': colorbrewer.PuBu[5],
		'purple/blue/green': colorbrewer.PuBuGn[5],
		'purple/red': colorbrewer.PuRd[5],
		'red/purple': colorbrewer.RdPu[5],
		'yellow/green': colorbrewer.YlGn[5],
		'yellow/green/blue': colorbrewer.YlGnBu[5],
		'yellow/orange/brown': colorbrewer.YlOrBr[5],
		'yellow/orange/red': colorbrewer.YlOrRd[5]
	};
	var selected = $("#" + id + "_palette").val();
	for (var i = 0; i < 5; i++) {
		$("#palette_" + i).css("background", palettes[selected][i]);
	}

}

function checkAndShowVisualisation(grid, id) {
	var visualisation_type = $("input[name='" + id + "_visualisation_type']:checked").val();
	var breakdown_display = $("#" + id + "_breakdown_display").val();
	var specific_value_display = $("#" + id + "_specific_value_display").val();
	var specific_values = $("#" + id + "_specific_values").val();
	if (visualisation_type === 'specific values') {
		if (specific_value_display != '0' && specific_values.length != 0) {
			elements[id]['display'] = 'field';
			elements[id]['url'] = url + "&page=query";
			elements[id]['url_text'] = 'Query records';
		} else {
			changeElementAttribute(grid, id, 'display', 'setup');
		}
	} else if (visualisation_type === 'breakdown') {
		if (breakdown_display != 0) {
			changeElementAttribute(grid, id, 'display', 'field');
		} else {
			changeElementAttribute(grid, id, 'display', 'setup');
		}
	}
}

function reloadElement(id) {
	var reload_url = url + "&page=dashboard&type=" + dashboard_type;
	if (typeof projectId !== 'undefined') {
		reload_url += "&project_id=" + projectId;
	}
	reload_url += "&element=" + id;
	if (qryFile != null && qryFile.length) {
		reload_url += "&qry_file=" + qryFile;
	}
	if (listFile != null && listFile.length && listAttribute != null && listAttribute.length) {
		reload_url += "&list_file=" + listFile + "&list_attribute=" + listAttribute;
	}

	$.get(reload_url, function(json) {
		try {
			$("div#element_" + id + "> .item-content > .ajax_content").html(JSON.parse(json).html);
			elements[id] = JSON.parse(json).element;
			applyFormatting();
		} catch (err) {
			console.log(err.message);
		}
	});
}

function reloadAllElements() {
	$.each(Object.keys(elements), function(index, value) {
		reloadElement(value);
	});
}

function reloadElementsWithURL() {
	$.each(Object.keys(elements), function(index, value) {
		if (elements[value]['visualisation_type'] != 'specific values'
			&& elements[value]['breakdown_display'] == 'top') {
			reloadElement(value);
		}
	});
}

function loadNewElements() {
	$.each(Object.keys(elements), function(index, value) {
		if (!loadedElements[value] && !($(window).width() < MOBILE_WIDTH && elements[value]['hide_mobile'])) {
			reloadElement(value);
			loadedElements[value] = 1;
		}
	});
}

function removeElement(grid, id) {
	var item = grid.getItem($("div#element_" + id)[0]);
	grid.remove([item], { removeElements: true });
	delete elements[id];
	saveElements(grid);
	if (Object.keys(elements).length == 0) {
		$("div#empty").html(empty);
	}
}

function changeElementDimension(grid, id, attribute) {
	var item_content = $("div.item[data-id='" + id + "'] > div.item-content");
	var classes = item_content.attr('class');
	var class_list = classes.split(/\s+/);
	$.each(class_list, function(index, value) {
		if (value.includes('dashboard_element_' + attribute)) {
			item_content.removeClass(value);
		}
	});
	var new_dimension = $("input[name='" + id + "_" + attribute + "']:checked")
		.val();
	item_content.addClass("dashboard_element_" + attribute + new_dimension);
	elements[id][attribute] = Number(new_dimension);
	saveAndReloadElement(grid, id);
	grid.refreshItems().layout();
}

function saveElements(grid) {
	$.post(url, {
		db: instance,
		page: "dashboard",
		updateDashboard: 1,
		type: dashboard_type,
		project_id: (typeof projectId !== 'undefined' ? projectId : null),
		attribute: "elements",
		value: JSON.stringify(elements)
	});
	saveLayout(grid);
}

function saveAndReloadElement(grid, id) {
	currentRequest = $.ajax({
		url: url,
		type: 'POST',
		data: {
			db: instance,
			page: "dashboard",
			updateDashboard: 1,
			type: dashboard_type,
			project_id: (typeof projectId !== 'undefined' ? projectId : null),
			attribute: "elements",
			value: JSON.stringify(elements)
		},
		beforeSend: function() {
			if (currentRequest != null) {
				currentRequest.abort();
			}
		},
		success: function(json) {
			reloadElement(id);
			if (grid != null) {
				setGridMargins(grid);
			}
			updateDashboardName(JSON.parse(json).dashboard_name);
		}
	});
}

function serializeLayout(grid) {
	var itemIds = grid.getItems().map(function(item) {
		return item.getElement().getAttribute('data-id');
	});
	return JSON.stringify(itemIds);
}

function loadLayout(grid, serializedLayout) {
	var layout = JSON.parse(serializedLayout);
	var currentItems = grid.getItems();
	var currentItemIds = currentItems.map(function(item) {
		return item.getElement().getAttribute('data-id')
	});
	var newItems = [];
	var itemId;
	var itemIndex;

	for (var i = 0; i < layout.length; i++) {
		itemId = layout[i];
		itemIndex = currentItemIds.indexOf(itemId);
		if (itemIndex > -1) {
			newItems.push(currentItems[itemIndex])
		}
	}
	grid.sort(newItems, {
		layout: 'instant'
	});
}

function saveLayout(grid) {
	//Wait at least 1s after new elements have been added to prevent race condition
	//resulting in two dashboards being initiated.

	let time = new Date().getTime();
	let delay = 0;
	if (time - lastAjaxUpdate < ajaxDelay) {
		delay = ajaxDelay;
	}

	setTimeout(
		function() {
			lastAjaxUpdate = new Date().getTime();
			var layout = serializeLayout(grid);
			$.ajax({

				url: url,
				type: 'POST',
				data: {
					db: instance,
					page: "dashboard",
					updateDashboard: 1,
					type: dashboard_type,
					project_id: (typeof projectId !== 'undefined' ? projectId : null),
					attribute: "order",
					value: layout
				},
				success: function(json) {
					$("#loaded_dashboard").val(JSON.parse(json).dashboard_name);
					$("#loaded_dashboard").prop("disabled", false);
					$("#delete_dashboard").css("display", "inline");
				}
			});
		}, delay);
}

function resetDefaults() {
	$("#modify_dashboard_panel").toggle("slide", { direction: "right" }, "fast");
	var reset_url = url + "&resetDefaults=1&type=" + dashboard_type;
	if (typeof projectId !== 'undefined') {
		reset_url += "&project_id=" + projectId;
	}
	$.get(reset_url, function() {
		//Prevent form reload message on Firefox - simulate click of the submit button instead.
		if ($("input#search").length) {
			$("input#search").trigger('click');
		} else {
			location.reload();
		}
	});
}

function resetSeqbinRange(id) {
	delete elements[id]['min'];
	delete elements[id]['max'];
	saveAndReloadElement(null, id);
	$.ajax({
		url: url + "&seqbin_range=1",
		type: 'GET',
		success: function(json) {
			let range = JSON.parse(json).range;
			$("#seqbin_range_slider").slider("option", "values", [range.min, range.max]);
			$("#seqbin_min").html(range.min);
			$("#seqbin_max").html(range.max);
			$("#reset_seqbin_range").css("display", "none");
		}
	});
}

function createNew() {
	var new_url = url + "&newDashboard=1&type=" + dashboard_type;
	if (typeof projectId !== 'undefined') {
		new_url += "&project_id=" + projectId;
	}
	$.ajax({
		url: new_url,
		type: 'GET',
		success: function() {
			//Prevent form reload message on Firefox - simulate click of the submit button instead.
			if ($("input#search").length) {
				$("input#search").trigger('click');
			} else {
				location.reload();
			}
		}
	});
}

function get_marker_layer(jsonData, colour, size) {
	let colours = {
		red: 'rgb(255,0,0,0.7)',
		blue: 'rgb(0,0,255,0.7)',
		green: 'rgb(13,130,58,0.7)',
		purple: 'rgb(176,2,250,0.7)',
		orange: 'rgb(250,85,2,0.7)',
		yellow: 'rgb(252,207,3,0.7)',
		grey: 'rgb(48,48,48,0.7)'
	};
	let pstyles = [];
	for (let i = 0; i < 10; ++i) {
		let pstyle = new ol.style.Style({
			image: new ol.style.Circle({
				radius: parseInt(size) + i,
				fill: new ol.style.Fill({
					color: colours[colour]
				})
			})
		});
		pstyles.push(pstyle);
	}
	let thresholds = [1, 2, 5, 10, 25, 50, 100, 250, 500];
	let features = [];
	jsonData.forEach(function(e) {
		let coordinates = (e.label.match(/(\-?\d+\.?\d*),\s*(\-?\d+\.?\d*)/));
		if (coordinates != null) {
			let latitude = parseFloat(coordinates[1]);
			let longitude = parseFloat(coordinates[2]);
			let threshold;
			for (let i = 0; i < thresholds.length; ++i) {
				if (parseInt(e.value) <= thresholds[i]) {
					threshold = i;
					break;
				}
			}
			if (threshold == null) {
				threshold = thresholds.length;
			}
			let feature = new ol.Feature({
				geometry: new ol.geom.Point(ol.proj.fromLonLat([longitude, latitude])),
			});
			feature.setStyle(pstyles[threshold])
			features.push(feature);
		}
	});
	let vectorLayer = new ol.layer.Vector({
		source: new ol.source.Vector({
			features: features
		})
	})
	return vectorLayer;
}

function commify(x) {
	return x.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

//https://gist.github.com/krabs-github/ec56e4f1c12cddf86ae9c551aa9d9e04
function lightOrDark(color) {
	// If RGB --> Convert it to HEX: http://gist.github.com/983661
	color = +("0x" + color.slice(1).replace(
		color.length < 5 && /./g, '$&$&'
	)
	);

	r = color >> 16;
	g = color >> 8 & 255;
	b = color & 255;

	// HSP equation from http://alienryderflex.com/hsp.html
	hsp = Math.sqrt(
		0.299 * (r * r) +
		0.587 * (g * g) +
		0.114 * (b * b)
	);

	// Using the HSP value, determine whether the color is light or dark
	if (hsp > 127.5) {
		return 'light';
	}
	else {
		return 'dark';
	}
}

