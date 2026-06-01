/**
 * Written by Keith Jolley 
 * Copyright (c) 2026, University of Oxford 
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
$(function() {

	$("#show_closed").click(function() {
		$("a#show_closed").hide();
		$("a#hide_closed").show();
		$("#closed").slideDown(500, "easeInOutQuad");
		return false;
	});
	$("#hide_closed").click(function() {
		$("a#show_closed").show();
		$("a#hide_closed").hide();
		$("#closed").slideUp(500, "easeInOutQuad");
		return false;
	});
	$('a#toggle_notifications').click(function(event) {
		event.preventDefault();
		$(this).attr('href', function() {
			$.ajax({
				url: this.href,
				cache: false,
				success: function() {
					if ($('span#notify_text').text() == 'ON') {
						$('span#notify_text').text('OFF');
					} else {
						$('span#notify_text').text('ON');
					}
				}
			});
		});
	});
	if ($('#all_curator_methods_on').is(":visible")) {
		render_expanded_curator_grid()
	} else {
		render_contracted_curator_grid()
	}

	$('a#toggle_all_curator_methods').click(function(event) {
		event.preventDefault();
		$(this).attr('href', function() {
			$('#all_curator_methods_off').toggle();
			$('#all_curator_methods_on').toggle();
			$("div.curategroup").hide();
			$("div.grid").each(function(index, element) {

				let packery = Packery.data(element);
				if (packery) {
					packery.destroy();
				}
			});
			if ($('#all_curator_methods_on').is(":visible")) {
				console.log('show all curator methods');
				$("#toggle_all_curator_methods").addClass("toggle_on");
				render_expanded_curator_grid();
			} else {
				console.log('show contracted curator methods');
				$("h3.curator_heading").hide();
				$("#toggle_all_curator_methods").removeClass("toggle_on");
				render_contracted_curator_grid();
			}
			$.ajax({
				url: this.href,
				cache: false,
			});
		});
	});
	$('a#toggle_all_admin_methods').click(function(event) {
		event.preventDefault();
		$(this).attr('href', function() {
			$('#all_admin_methods_off').toggle();
			$('#all_admin_methods_on').toggle();
		});
		var categories = ["locus", "scheme", "set", "client", "field", "misc"];
		if ($('#all_admin_methods_on').is(':visible')) {
			for (var i = 0; i < categories.length; i++) {
				if ($('#' + categories[i] + '_admin_methods_off').is(':visible')) {
					$('#toggle_' + categories[i] + '_admin_methods').click();
				}
			}
		} else {
			for (var i = 0; i < categories.length; i++) {
				if ($('#' + categories[i] + '_admin_methods_on').is(':visible')) {
					$('#toggle_' + categories[i] + '_admin_methods').click();
				}
			}
		}
	});
	var categories = ["misc_admin", "locus_admin", "scheme_admin", "set_admin", "client_admin", "field_admin"];
	for (var i = 0; i < categories.length; i++) {
		var cat = categories[i]
		bind_toggle(cat);
	}

	if (related_dbs > 1) {
		$("#related_db_trigger,#close_related_db").click(function() {
			$("#related_db_panel").toggle("slide", { direction: "right" }, "fast", function() {
				if ($("#related_db_panel").is(":visible")) {
					$("#modal_overlay").addClass("open");
				} else {
					$("#modal_overlay").removeClass("open");
				}
			});
			return false;
		});
	}

	//Close panel
	$(document).mouseup(function(e) {
		// if the target of the click isn't the container nor a
		// descendant of the container
		var trigger = $("#related_db_trigger");
		var container = $("#related_db_panel");
		if (!container.is(e.target) && container.has(e.target).length === 0 &&
			!trigger.is(e.target) && trigger.has(e.target).length === 0) {
			container.hide();
			$("#modal_overlay").removeClass("open");
		}
	});
});

function render_contracted_curator_grid() {
	const $cards = $("div.curategroup[data-type='curator'][data-default='show']");
	const $grid = $("#curator_collapsed")
	$grid.append($cards);
	$("p.curate_info").show();
	$("a.tooltip").hide();
	$("div.curategroup").addClass("contracted").removeClass("expanded");
	$cards.show();
	$grid.packery({
		itemSelector: ".curategroup",
		gutter: 10,
	});
	console.log($cards);
}

function render_expanded_curator_grid() {
	const sections = ['user', 'isolate', 'seqbin', 'loci', 'schemes', 'metadata'];
	$("p.curate_info").hide();
	$("a.tooltip").show();
	$("div.curategroup").addClass("expanded").removeClass("contracted");
	
	
	sections.forEach(function(section) {
		let $section_cards = $("div.curategroup[data-type='curator'][data-section='" + section + "']").sort(function(a, b) {
			return $(a).data('order') - $(b).data('order');
		});

		console.log($section_cards);
		if ($section_cards.length > 0) {
			$("h3#curate_heading_" + section).show();

			let $grid = $("#curator_" + section)
			$grid.append($section_cards);
			$section_cards.show();
			$grid.packery({
				itemSelector: ".curategroup",
				gutter: 5,
			});

		}
	});
}

function bind_toggle(cat) {
	$('a#toggle_' + cat + '_methods').click(function(event) {
		event.preventDefault();
		$(this).attr('href', function() {
			$('#' + cat + '_methods_off').toggle();
			$('#' + cat + '_methods_on').toggle();
			$('.' + cat).fadeToggle(200, '', function() {
				$('#admin_grid').packery();
			});
			$.ajax({
				url: this.href,
				cache: false,
			});
		});
		var categories = ["locus", "scheme", "set", "client", "field", "misc"];
		var all_hidden = 1;
		var all_shown = 1;
		for (var i = 0; i < categories.length; i++) {
			if ($('#' + categories[i] + '_admin_methods_on').is(':visible')) {
				all_hidden = 0;
			}
			if ($('#' + categories[i] + '_admin_methods_off').is(':visible')) {
				all_shown = 0;
			}
		}
		if (all_hidden) {
			$('#all_admin_methods_off').css('display', 'inline');
			$('#all_admin_methods_on').css('display', 'none');
		} else {
			$('#all_admin_methods_on').css('display', 'inline');
			$('#all_admin_methods_off').css('display', 'none');
		}
		if (all_shown) {
			$('#all_admin_methods_on').css('display', 'inline');
			$('#all_admin_methods_off').css('display', 'none');
		} else {
			$('#all_admin_methods_off').css('display', 'inline');
			$('#all_admin_methods_on').css('display', 'none');
		}
	});
}

var delay = (function() {
	var timer = 0;
	return function(callback, ms) {
		clearTimeout(timer);
		timer = setTimeout(callback, ms);
	};
})();