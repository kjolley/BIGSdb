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

var grid;
$(function () {
	var layout = $("#layout").val();
	var fill_gaps = $("#fill_gaps").prop('checked');
	grid = new Muuri('.grid',{
		dragEnabled: true,
		layout: {
			alignRight : layout.includes('right'),
			alignBottom : layout.includes('bottom'),
			fillGaps: fill_gaps
		}		
	}).on('move', function () {
    	saveLayout(grid)
	});
	if (order_defined){
		loadLayout(grid, order);
	}
	$("#panel_trigger,#close_trigger").click(function(){		
		$("#modify_panel").toggle("slide",{direction:"right"},"fast");
		$("#panel_trigger").show();		
		return false;
	});
	$("#panel_trigger").show();
	$("#layout").change(function(){
		layout = $("#layout").val();
		grid._settings.layout.alignRight = layout.includes('right');
		grid._settings.layout.alignBottom = layout.includes('bottom');
		grid.layout();
		$.ajax(ajax_url + "&attribute=layout&value=" + layout );	
	});
	$("#fill_gaps").change(function(){
		fill_gaps = $("#fill_gaps").prop('checked');
		grid._settings.layout.fillGaps = fill_gaps;
		grid.layout();
		$.ajax(ajax_url + "&attribute=fill_gaps&value=" + (fill_gaps ? 1 : 0) );	
	});
	$(".dashboard_control").click(function(){
		var id=$(this).attr('data-id');
		$("span#control_" + id).hide();
		$("span#wait_" + id).show();
		event.preventDefault();
		this.blur(); // Manually remove focus from clicked link.
		$.get(modal_control_url + "&control=" + id, function(html) {
			$(html).appendTo('body').modal();
			$("span#control_" + id).show();
			$("span#wait_" + id).hide();
		});
	});

	var dimension = ['width','height'];
	dimension.forEach((value) => {
		$(document).on("change", '.' + value + '_select', function(event) { 
			var id = $(this).attr('id');
			var element_id = id.replace("_" + value,"");
			changeElementDimension(element_id, value);
		});
	});
});

function changeElementDimension(id, attribute) {
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
	grid.refreshItems().layout();
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
	$.get($reset_url, function() {		
		$("#layout").val("left-top");
		$("#fill_gaps").prop("checked",true);
		 location.reload();
	});
}
