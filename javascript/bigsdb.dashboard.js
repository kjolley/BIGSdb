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

var currentRequest = null;

$(function () {
	var layout_test = $("#layout_test").prop('checked');
	$("select#add_field,label[for='add_field']").css("display",layout_test ? "none" : "inline");
	var layout = $("#layout").val();
	var fill_gaps = $("#fill_gaps").prop('checked');
	var grid;
	try {
		grid = new Muuri('.grid',{
			dragEnabled: true,
			layout: {
				alignRight : layout.includes('right'),
				alignBottom : layout.includes('bottom'),
				fillGaps: fill_gaps
			},
			dragStartPredicate: function (item, e){
				return enable_drag;
			}
		}).on('move', function () {
			saveLayout(grid);
		});
		if (order){
			loadLayout(grid, order);
		}
	} catch(err) {
		console.log(err.message);
	}

	$("#panel_trigger,#close_trigger").click(function(){		
		$("#modify_panel").toggle("slide",{direction:"right"},"fast");
		$("#panel_trigger").show();		
		return false;
	});
	$("#panel_trigger").show();
	$(document).mouseup(function(e) 
			{
		var container = $("#modify_panel");

		// if the target of the click isn't the container nor a
		// descendant of the container
		if (!container.is(e.target) && container.has(e.target).length === 0) 
		{
			container.hide();
		}
			});
	$("#layout").change(function(){
		layout = $("#layout").val();
		try {
			grid._settings.layout.alignRight = layout.includes('right');
			grid._settings.layout.alignBottom = layout.includes('bottom');		
			grid.layout();
		} catch(err){
			// Grid is empty.
		}
		$.ajax(url + "&page=dashboard&updatePrefs=1&attribute=layout&value=" + layout );	
	});
	$("#fill_gaps").change(function(){
		fill_gaps = $("#fill_gaps").prop('checked');
		try {
			grid._settings.layout.fillGaps = fill_gaps;		
			grid.layout();		
		} catch(err){
			// Grid is empty.
		}
		$.ajax(url + "&page=dashboard&updatePrefs=1&attribute=fill_gaps&value=" + (fill_gaps ? 1 : 0) );	
	});
	$("#enable_drag").change(function(){
		enable_drag = $("#enable_drag").prop('checked');
		$.ajax(url + "&page=dashboard&updatePrefs=1&attribute=enable_drag&value=" + (enable_drag ? 1 : 0) );

	});
	$("#edit_elements").change(function(){	
		var edit_elements = $("#edit_elements").prop('checked');
		$.ajax(url + "&page=dashboard&updatePrefs=1&attribute=edit_elements&value=" + (edit_elements ? 1 : 0) );
		$("span.dashboard_edit_element").css("display",edit_elements ? "inline" : "none");
	});
	$("#remove_elements").change(function(){	
		var remove_elements = $("#remove_elements").prop('checked');
		$.ajax(url + "&page=dashboard&updatePrefs=1&attribute=remove_elements&value=" + (remove_elements ? 1 : 0) );
		$("span.dashboard_remove_element").css("display",remove_elements ? "inline" : "none");
	});
	$("#layout_test").change(function(){	
		layout_test = $("#layout_test").prop('checked');
		$.ajax(url + "&page=dashboard&updatePrefs=1&attribute=layout_test&value=" + (layout_test ? 1 : 0) );
		$("select#add_field,label[for='add_field']").css("display",layout_test ? "none" : "inline");
	});
	$("#include_old_versions").change(function(){	
		var include_old_versions = $("#include_old_versions").prop('checked');
		$.ajax({
			url:url + "&page=dashboard&updatePrefs=1&attribute=include_old_versions&value=" + 
			(include_old_versions ? 1 : 0) 			
		}).done(function() {
			reloadAllElements(grid);
		});
	});


	$("#add_element").click(function(){	
		var nextId = getNextid();
		addElement(grid,nextId);
	});

	$("div#dashboard").on("click",".dashboard_edit_element",function(){
		var id=$(this).attr('data-id');
		editElement(grid,id);
	});
	$("div#dashboard").on("click",".dashboard_remove_element",function(){
		var id=$(this).attr('data-id');
		removeElement(grid,id);
	});
	$("div#dashboard").on("click",".setup_element",function(){
		var id=$(this).attr('data-id');
		editElement(grid,id);
	});
	$("div#dashboard").on("click",".dashboard_explore_element",function(){
		var id=$(this).attr('data-id');
		if (elements[id]['url']){
			var explore_url = elements[id]['url'];
			var params = {};
			if (elements[id]['post_data']){
			    params = elements[id]['post_data'];
			}
			params['sent'] = 1;
			if (explore_url.includes('&page=query') && $("#include_old_versions").prop('checked')){
			    params['include_old'] = 'on';
			}
			post(elements[id]['url'],params);
		}
	});	
	applyFormatting();

	var dimension = ['width','height'];
	dimension.forEach((value) => {
		$(document).on("change", '.' + value + '_select', function(event) { 
			var id = $(this).attr('id');
			var element_id = id.replace("_" + value,"");
			changeElementDimension(grid, element_id, value);
		});
	});
	$(document).on("change", '.element_option', function(event) { 
		var id = $(this).attr('id');
		var attribute = id.replace(/^\d+_/,"");
		var element_id = id.replace("_" + attribute,"");
		changeElementAttribute(grid, element_id, attribute, $(this).val() );
	});
	$('a#dashboard_toggle').on('click', function(){
		$.get(url + "&page=dashboard&updatePrefs=1&attribute=default&value=0",function(){
			window.location=url;	
		});	
	});	
});


//Post to the provided URL with the specified parameters.
//https://stackoverflow.com/questions/133925/javascript-post-request-like-a-form-submit/5533477#5533477
function post(path, parameters) {
    var form = $('<form></form>');

    form.attr("method", "post");
    form.attr("action", path);

    $.each(parameters, function(key, value) {
        var field = $('<input></input>');
        field.attr("type", "hidden");
        field.attr("name", key);
        field.attr("value", value);
        form.append(field);
    });

    // The form needs to be a part of the document in
    // order for us to be able to submit it.
    $(document.body).append(form);
    form.submit();
}

function clean_value(value){
	if (Array.isArray(value)){
		value = value.map(function (el) {
			return el.trim();
		});
		value = value.filter(function (el) {
            return el != null && el != '';
        });
	} else {
		value = value.trim();
	}
	return value;
}

function changeElementAttribute(grid, id, attribute, value){
    if (elements[id][attribute] === value){
        return;
    }
    if (attribute === 'specific_values' && !Array.isArray(value)){
        if (value.includes("\n")){
            value = value.split("\n");
        } else {
            value = value.split();
        }	    
    }
    value = clean_value(value);
    elements[id][attribute] = value;
    currentRequest = $.ajax({
        url:url,
        type:'POST',
        data:{
            db:instance,
            page:"dashboard",
            updatePrefs:1,
            attribute:"elements",
            value:JSON.stringify(elements)
        }, 
        beforeSend : function()    {           
            if(currentRequest != null) {
                currentRequest.abort();
            }
        },
        success: function(){
            reloadElement(grid,id);  	
        }
    });	
}

function applyFormatting(){
	fitty(".dashboard_big_number",{
		maxSize:64
	});
	$(".item-content div.subtitle a").tooltip();
}

function getNextid(){
	if (Object.keys(elements).length === 0){
		return 1;
	}
	var max = Math.max(...Object.keys(elements)); 
	return max+1;
}

function addElement(grid,id){
	if (Object.keys(elements).length === 0){
		$("div#empty").html(""); 
	}
	var add_url = url + "&page=dashboard&new=" + id;
	var field = $("#add_field").val();
	if (field){
		add_url += "&field=" + field;
	}

	$.get(add_url,function(json){
		try {
			var div = document.createRange().createContextualFragment(JSON.parse(json).html);
			// Element may already exist if add button was clicked multiple
			// times before AJAX response was received.
			if (!(id in elements)){
				grid.add([div.firstChild]);
				elements[id] = JSON.parse(json).element;
				saveElements(grid);
			}
			applyFormatting();
		} catch (err){
			console.log(err.message);
		}
	});	
}

function editElement(grid,id,setup){
	$("span#control_" + id).hide();
	$("span#wait_" + id).show();
	$.get(url + "&page=dashboard&control=" + id, function(html) {
		$(html).appendTo('body').modal();
		if ($("#edit_elements").prop("checked")){
			$("span#control_" + id).show();
		}
		$("span#wait_" + id).hide();
		show_or_hide_control_elements(grid,id);
		$("div.modal").on("change","#" + id + "_visualisation_type",function(){
			show_or_hide_control_elements(grid,id);

			check_and_show_visualisation(grid,id);
		});
		$("div.modal").on("change","#" + id + "_breakdown_display,#" + 
				id + "_specific_value_display,#" + 
				id + "_specific_values",function(){	
		    show_or_hide_control_elements(grid,id);
			check_and_show_visualisation(grid,id);
		});
		$("div.modal").on($.modal.AFTER_CLOSE, function(event, modal) {
			$("div.modal").remove();
		});
	});
}

function show_or_hide_control_elements(grid,id){
	var visualisation_type = $("input[name='" + id + "_visualisation_type']:checked").val();
	var specific_value_display = $("#" + id + "_specific_value_display").val();
	$("li#value_selector").css("display", visualisation_type === 'breakdown' ? 'none' : 'block');
	$("li#breakdown_display_selector").css("display",visualisation_type === 'breakdown' ? 'block' : 'none');
	$("li#specific_value_display_selector").css("display", visualisation_type === 'breakdown' ? 'none' : 'block');
	if (visualisation_type==='specific values'){
	    $("fieldset#change_duration_control").css("display",specific_value_display==='number' ? 'inline':'none');
	    $("fieldset#design_control").css("display",specific_value_display==='number' ? 'inline':'none');
	}
	
}

function check_and_show_visualisation(grid,id){
	var visualisation_type = $("input[name='" + id + "_visualisation_type']:checked").val();
	var breakdown_display = $("#" + id + "_breakdown_display").val();
	var specific_value_display = $("#" + id + "_specific_value_display").val();
	var specific_values = $("#" + id + "_specific_values").val();
	if (visualisation_type === 'specific values'){
		if (specific_value_display != '0' && specific_values.length != 0){
			changeElementAttribute(grid,id,'display','field');
		} else {
			changeElementAttribute(grid, id, 'display', 'setup');
		}
	}
}

function reloadElement(grid,id){
	$.get(url + "&page=dashboard&element=" + id,function(json){
		try {
			$("div#element_" + id + "> .item-content > .ajax_content").html(JSON.parse(json).html);
			elements[id] = JSON.parse(json).element;
			applyFormatting();
		} catch (err){
			console.log(err.message);
		}
	});
}

function reloadAllElements(grid){
	$.each(Object.keys(elements),function(index,value){
		reloadElement(grid,value);
	});
}

function removeElement(grid,id){
	var item = grid.getItem($("div#element_" + id)[0]);
	grid.remove([item],{ removeElements: true });
	delete elements[id];
	saveElements(grid);
	if (Object.keys(elements).length == 0){	
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
	$("span#" + id + "_" + attribute).html(new_dimension);
	elements[id][attribute] = Number(new_dimension);
	$.ajax({
        url:url,
        type:'POST',
        data:{
            db:instance,
            page:"dashboard",
            updatePrefs:1,
            attribute:"elements",
            value:JSON.stringify(elements)
        }, 
        success: function(){
            reloadElement(grid,id);     
        }
	});
	grid.refreshItems().layout();
}

function saveElements(grid){
	$.post(url,{
		db:instance,
		page:"dashboard",
		updatePrefs:1,
		attribute:"elements",
		value:JSON.stringify(elements)
	});
	saveLayout(grid);
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
		layout : 'instant'
	});
}

function saveLayout(grid) {
	var layout = serializeLayout(grid);
	$.post(url,{
		db:instance,
		page:"dashboard",
		updatePrefs:1,
		attribute:"order",
		value:layout
	});
}

function resetDefaults(){
	$("#modify_panel").toggle("slide",{direction:"right"},"fast");
	$.get(url + "&resetDefaults=1", function() {		
		$("#layout").val("left-top");
		$("#fill_gaps").prop("checked",true);
		$("#enable_drag").prop("checked",false);
		$("#edit_elements").prop("checked",false);
		$("#remove_elements").prop("checked",false);
		location.reload();
	});
}
