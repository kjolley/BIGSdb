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
		}
	});
	$('.expand_link').on('click', function() {
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
});