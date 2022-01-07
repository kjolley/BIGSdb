/**
 * Written by Keith Jolley 
 * Copyright (c) 2021-2022, University of Oxford 
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
	if (canAnalyse()) {
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
			let data = JSON.parse(json);
			d3.select("div#tree").select("svg").remove();
			d3.select("p#notes").style("display", "block");
			d3.select("div#field_labels").html('<p style="margin-left:100px">' + data.fields.cleaned.join("</p><p>") + "</p>");
			loadTree(data);
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
		d3.select("div#tree").select("svg").remove();
		d3.select("div#field_labels").html("");
		d3.select("p#notes").style("display", "none");
	});
}

//Function modified from https://observablehq.com/@d3/collapsible-tree
//Mike Bostock
//Copyright 2018-2020 Observable, Inc.
//ISC License
/*Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.*/
function loadTree(data) {
	const root = d3.hierarchy(data.hierarchy).copy().sort((a, b) => d3.descending(a.data.count, b.data.count));
	let fieldCount = data.fields.cleaned.length;
	let dx = 20;

	let margin = ({ top: 10, right: 120, bottom: 10, left: 40 });
	let width = d3.select('div#tree').node().getBoundingClientRect().width;
	let dy = width / (fieldCount + 1);
	let tree = d3.tree().nodeSize([dx, dy]);
	let diagonal = d3.linkHorizontal().x(d => d.y).y(d => d.x)

	root.x0 = dy / 2;
	root.y0 = 0;

	root.descendants().forEach((d, i) => {
		d.id = i;
		d._children = d.children;
		if (d.depth > 0) d.children = null;
	});

	const svg = d3.select("div#tree")
		.append("svg")
		.attr("viewBox", [-margin.left, -margin.top, width, dx])
		.style("font", "13px sans-serif")
		.style("user-select", "none");

	const gLink = svg.append("g")
		.attr("fill", "none")
		.attr("stroke", "#555")
		.attr("stroke-opacity", 0.4)
		.attr("stroke-width", 1.5);

	const gNode = svg.append("g")

	function update(source) {
		const duration = d3.event && d3.event.altKey ? 2500 : 250;
		const nodes = root.descendants().reverse();
		const links = root.links();

		// Compute the new tree layout.
		tree(root);

		let left = root;
		let right = root;
		root.eachBefore(node => {
			if (node.x < left.x) left = node;
			if (node.x > right.x) right = node;
		});

		const height = right.x - left.x + margin.top + margin.bottom;

		const transition = svg.transition()
			.duration(duration)
			.attr("viewBox", [-margin.left, left.x - margin.top, width, height])
			.tween("resize", window.ResizeObserver ? null : () => () => svg.dispatch("toggle"));

		// Update the nodes…
		const node = gNode.selectAll("g")
			.data(nodes, d => d.id);

		// Enter any new nodes at the parent's previous position.
		const nodeEnter = node.enter().append("g")
			.attr("transform", d => `translate(${source.y0},${source.x0})`)
			.attr("fill-opacity", 0)
			.attr("stroke-opacity", 0);

		const tooltip = d3.select("div#tooltip");

		nodeEnter.append("circle")
			.attr("r", 8)
			//			.attr("fill", d => d._children ? "#555" : "#999")
			.attr("fill", d => d._children ? "#559" : "#999")
			.attr("stroke-width", 10)
			.attr("cursor", d => d._children ? "pointer" : "auto")
			.on("click", (event, d) => {
				d.children = d.children ? null : d._children;
				update(d);
			})
			.on("mouseover", function(event, d) {
				if (d._children == null) {
					return;
				}
				tooltip.html("Click to expand/contract")
					.style("visibility", "visible");
			})
			.on("mouseout", function() { tooltip.style("visibility", "hidden"); })

		nodeEnter.append("text")
			.attr("dy", "0.31em")
			.attr("x", d => d._children ? -12 : 12)
			.attr("text-anchor", d => d._children ? "end" : "start")
			.text(function(d) {
				if (d.data.value && d.data.value.length > 25) {
					return d.data.value.substring(0, 22) + '...';
				} else {
					return d.data.value;
				}
			})
			.attr("cursor", "pointer")
			.on("click touchstart", (event, d) => {
				window.open(d.data.url);
			})
			.on("mouseover", function(event, d) {
				tooltip.html("Click to see records (" + d.data.count + ")")
					.style("visibility", "visible");
			})
			.on("mouseout", function() { tooltip.style("visibility", "hidden"); })
			.clone(true).lower()
			.attr("stroke-linejoin", "round")
			.attr("stroke-width", 3)
			.attr("stroke", "white");

		nodeEnter.filter(function(d) { return d.parent })
			.append("rect")
			.attr("width", d => d.parent ? (100 * d.data.count / d.parent.data.count) : 0)
			.attr("x", d => d._children ? -(100 * d.data.count / d.parent.data.count) - 12 : 12)
			.attr("y", d => 6)

			.attr("height", d => d.parent ? 1 : 0)
			.attr("stroke", 'blue')

		// Transition nodes to their new position.
		const nodeUpdate = node.merge(nodeEnter).transition(transition)
			.attr("transform", d => `translate(${d.y},${d.x})`)
			.attr("fill-opacity", 1)
			.attr("stroke-opacity", 1);

		// Transition exiting nodes to the parent's new position.
		const nodeExit = node.exit().transition(transition).remove()
			.attr("transform", d => `translate(${source.y},${source.x})`)
			.attr("fill-opacity", 0)
			.attr("stroke-opacity", 0);

		// Update the links…
		const link = gLink.selectAll("path")
			.data(links, d => d.target.id);

		// Enter any new links at the parent's previous position.
		const linkEnter = link.enter().append("path")
			.attr("d", d => {
				const o = { x: source.x0, y: source.y0 };
				return diagonal({ source: o, target: o });
			});

		// Transition links to their new position.
		link.merge(linkEnter).transition(transition)
			.attr("d", diagonal);

		// Transition exiting nodes to the parent's new position.
		link.exit().transition(transition).remove()
			.attr("d", d => {
				const o = { x: source.x, y: source.y };
				return diagonal({ source: o, target: o });
			});

		// Stash the old positions for transition.
		root.eachBefore(d => {
			d.x0 = d.x;
			d.y0 = d.y;
		});
	}
	update(root);
}

function commify(x) {
	return x.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}