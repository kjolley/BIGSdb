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
	if ($('#all_curator_methods_on').is(":visible") || always_show_hidden == 1) {
		render_expanded_curator_grid()
	} else {
		render_contracted_curator_grid()
	}

	$('a#toggle_all_curator_methods').click(function(event) {
		event.preventDefault();
		$(this).attr('href', function() {
			$('#all_curator_methods_off').toggle();
			$('#all_curator_methods_on').toggle();
			$("div.curategroup[data-type='curator']").hide();
			$("div.grid[data-type='curator']").each(function(index, element) {

				let packery = Packery.data(element);
				if (packery) {
					packery.destroy();
				}
			});
			if ($('#all_curator_methods_on').is(":visible")) {
				$("#toggle_all_curator_methods").addClass("toggle_on");
				render_expanded_curator_grid();
			} else {
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
			$('a#toggle_all_admin_methods').addClass("toggle_on");
		} else {
			for (var i = 0; i < categories.length; i++) {
				if ($('#' + categories[i] + '_admin_methods_on').is(':visible')) {
					$('#toggle_' + categories[i] + '_admin_methods').click();
				}
			}
			$('a#toggle_all_admin_methods').removeClass("toggle_on");
		}
	});
	var categories = ["general_admin", "misc_admin", "locus_admin", "scheme_admin", "set_admin", "client_admin", "field_admin"];
	for (var i = 0; i < categories.length; i++) {
		var cat = categories[i]
		bind_toggle(cat);
		render_admin_grid(categories[i])
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

function render_admin_grid(category) {

	let cat = category.replace("_admin", "");
	let $cards = $("div.curategroup[data-type='admin'][data-section='" + cat + "']");
	if ($cards.length > 0) {
		$("h3#admin_heading_" + cat).show();
	}
	let $grid = $("#" + category);
	$grid.append($cards);
	$("div.curategroup[data-type='admin'][data-section='" + cat + "'] p.curate_info").hide();
	if ($("a#toggle_tooltips").hasClass('tooltips_enabled')) {
		$("div.curategroup[data-type='admin'][data-section='" + cat + "'] a.tooltip").show();
	}
	$("div.curategroup[data-type='admin'][data-section='" + cat + "']").addClass("expanded").removeClass("contracted");
	$cards.show();
	$grid.packery({
		itemSelector: ".curategroup",
		gutter: 5,
	});
	if ($("#" + category + "_methods_on").is(':visible') || category === 'general_admin') {

		$("h3#admin_heading_" + cat).show();
		$grid.show();
	} else {
		$("h3#admin_heading_" + cat).hide();
		$grid.hide();
	}
}

function render_contracted_curator_grid() {
	const $cards = $("div.curategroup[data-type='curator'][data-default='show']");
	const $grid = $("#curator_collapsed")
	$grid.append($cards);
	$("div.curategroup[data-type='curator'] p.curate_info").show();
	$("div.curategroup[data-type='curator'] a.curator_tooltip").hide();
	$("div.curategroup[data-type='curator'] a.curator_tooltip").removeClass("tooltip");
	$("div.curategroup[data-type='curator']").addClass("contracted").removeClass("expanded");
	$cards.show();
	$grid.packery({
		itemSelector: ".curategroup",
		gutter: 10,
	});
}

function render_expanded_curator_grid() {
	const sections = ['user', 'isolate', 'seqbin', 'loci', 'schemes', 'metadata'];
	$("div.curategroup[data-type='curator'] p.curate_info").hide();
	$("div.curategroup[data-type='curator'] a.curator_tooltip").addClass("tooltip");
	if ($("a#toggle_tooltips").hasClass("tooltips_enabled")) { //THIS IS NOT WORKING!
		$("div.curategroup[data-type='curator'] a.curator_tooltip").show();
	} else if ($("a#toggle_tooltips").hasClass("tooltips_disabled")) {
		$("div.curategroup[data-type='curator'] a.curator_tooltip").hide();
	}
	$("div.curategroup[data-type='curator']").addClass("expanded").removeClass("contracted");

	sections.forEach(function(section) {
		let $section_cards = $("div.curategroup[data-type='curator'][data-section='" + section + "']").sort(function(a, b) {
			return $(a).data('order') - $(b).data('order');
		});

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
			$('#' + cat + '_methods_off').toggle(0);
			$('#' + cat + '_methods_on').toggle(0, function() {
				admin_cat = cat.replace("_admin", "");
				console.log(admin_cat)
				if ($('#' + cat + '_methods_on').is(":visible")) {
					$("h3#admin_heading_" + admin_cat).show();
					$('#toggle_' + cat + '_methods').addClass("toggle_on");
					$("div#" + cat).show();
					$("div#" + cat).packery("layout");
				} else {
					$("h3#admin_heading_" + admin_cat).hide();
					$('#toggle_' + cat + '_methods').removeClass("toggle_on");
					$("div#" + cat).hide();
				}
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
					$('a#toggle_all_admin_methods').removeClass("toggle_on");
				} else {
					$('#all_admin_methods_on').css('display', 'inline');
					$('#all_admin_methods_off').css('display', 'none');
					$('a#toggle_all_admin_methods').addClass("toggle_on");
				}
				if (all_shown) {
					$('#all_admin_methods_on').css('display', 'inline');
					$('#all_admin_methods_off').css('display', 'none');
					$('a#toggle_all_admin_methods').addClass("toggle_on");
				} else {
					$('#all_admin_methods_off').css('display', 'inline');
					$('#all_admin_methods_on').css('display', 'none');
					$('a#toggle_all_admin_methods').removeClass("toggle_on");
				}
			});
			$.ajax({
				url: this.href,
				cache: false,
			});
		});

	});
}

var delay = (function() {
	var timer = 0;
	return function(callback, ms) {
		clearTimeout(timer);
		timer = setTimeout(callback, ms);
	};
})();