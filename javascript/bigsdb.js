/**
 * Written by Keith Jolley 
 * Copyright (c) 2010-2023, University of Oxford 
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
	$('div.content a:not(.lightbox)').tooltip({
		track: false,
		show: { delay: 250 },
		showURL: false,
		showBody: " - ",
		fade: 250
	});
	$('.showhide').show();
	$("#hidefromnonJS").removeClass("hiddenbydefault");
	$(".hideonload").slideUp("normal");
	$('.hideshow').hide();
	$('#toggle1,#toggle2').click(function() {
		$('.showhide').toggle();
		$('.hideshow').toggle();
	});
	$('.flash_message').effect('highlight', {}, 2000).hide('fade', {}, 1000);

	$('a#toggle_tooltips,span#toggle').show();
	$('a#toggle_tooltips').click(function(event) {
		event.preventDefault();
		if ($('a#toggle_tooltips').hasClass('tooltips_enabled')) {
			$('a#toggle_tooltips').removeClass('tooltips_enabled');
			$('a#toggle_tooltips').addClass('tooltips_disabled');
			$('a#toggle_tooltips').prop('title', 'Enable tooltips');
		} else {
			$('a#toggle_tooltips').removeClass('tooltips_disabled');
			$('a#toggle_tooltips').addClass('tooltips_enabled');
			$('a#toggle_tooltips').prop('title', 'Disable tooltips');
		}
		$('.tooltip').toggle();
		$(this).attr('href', function() {
			$.ajax({
				url: this.href,
				cache: false,
			});
		});
	});

	show_expand_trigger();
	$('a#expand_trigger').click(function(event) {
		event.preventDefault();
		let expand = $('span#expand').is(":visible") ? 'on' : 'off';

		if ($('span#expand').is(":visible")) {
			$('span#expand, span#expand_label_expand').hide();
			$('span#contract, span#expand_label_contract').show();
		} else {
			$('span#expand, span#expand_label_expand').show();
			$('span#contract, span#expand_label_contract').hide();
		}
		set_page_width();

		$.ajax({
			url: this.href + "&update=1&attribute=expandPage&value=" + expand,
			cache: false,
		});
	});
	$('a#dark_trigger').click(function(event) {
		event.preventDefault();
		let dark_mode = $('span#dark_mode').is(":visible") ? 'on' : 'off';
		let theme = $('span#dark_mode').is(":visible") ? 'dark' : 'light';
		let config = $.urlParam('db');
		document.cookie = `${config}_theme=${theme}; path=/; max-age=31536000; samesite=lax`;
		if ($('span#dark_mode').is(":visible")) {
			$('span#dark_mode, span#mode_label_dark').hide();
			$('span#light_mode, span#mode_label_light').show();
			document.documentElement.dataset.theme = 'dark';
			if($.fn.jstree){
				$("#tree").jstree('set_theme','default-dark');
			}
		} else {
			$('span#dark_mode, span#mode_label_dark').show();
			$('span#light_mode, span#mode_label_light').hide();
			document.documentElement.dataset.theme = 'light';
			if($.fn.jstree){
				$("#tree").jstree('set_theme','default');
			}
		}
		$.ajax({
			url: this.href + "&update=1&attribute=darkMode&value=" + dark_mode,
			cache: false,
		});
	});	


	//Tooltips
	reloadTooltips();
	$('a#toggle_tooltips').prop('title', $('a#toggle_tooltips')
		.hasClass('tooltips_enabled') ? 'Disable tooltips' : 'Enable tooltips');

	//Add tooltip to truncated definition list titles
	$('dt').each(function() {
		if (this.offsetWidth + 1 < this.scrollWidth) {
			$(this).prop('title', $(this).text());
			$(this).tooltip();
			$(this).css('cursor', 'pointer');
		}
	});
	$(window).resize(function() {
		show_expand_trigger();
	});
	apply_select2();

	// hack to fix jquery 3.6 focus security patch that bugs auto search in select-2
	$(document).on('select2:open', () => {
		document.querySelector('.select2-search__field').focus();
	});
	$('.select2-selection__choice').removeAttr('title');
	$('.select2-selection__rendered').removeAttr('title');
	$(document).on('keydown', '.select2-selection', function(e) {
		if (e.key.length === 1 && !e.ctrlKey && !e.altKey && !e.metaKey) {
			const select = $(this)
				.closest('.select2-container')
				.prev('select');

			select.one('select2:open', function() {
				const search = document.querySelector(
					'.select2-container--open .select2-search__field'
				);
				search.value = e.key;
				$(search).trigger('input');
			});
			select.select2('open');
			e.preventDefault();
		}
	});
	let config = $.urlParam('db');
	let dark_or_light = getCookie(`${config}_theme`);
	if (dark_or_light){
		$('span#dark_mode,span#mode_label_dark').css('display',(dark_or_light === 'dark' ? 'none': 'inline'));
		$('span#light_mode,span#mode_label_light').css('display',(dark_or_light === 'dark' ? 'inline': 'none'));
	}
});

$.urlParam = function(name) {
	var results = new RegExp('[\?&]' + name + '=([^&#]*)').exec(window.location.href);
	if (results == null) {
		return null;
	}
	else {
		return results[1] || 0;
	}
}

function apply_select2() {
	if (window.jQuery && $.fn.select2) {
		$('select:not(.locuslist):not(.widelist):not(.filter):not(.no_init_select2):not([multiple])')
			.not('.select2-hidden-accessible')
			.each(function() {
				const $select = $(this);
				const hasEmptyOption = $select.find('option[value=""]').length > 0;	
				if (!$select.is(':visible') && !$select.hasClass('do_not_calc_width')) {
					$select.css('width', calcSelectWidth($select) + 'px');
				} 
				if (hasEmptyOption){
					$select.css("width", ($select.width() + 70) + 'px');
				}
				$select.select2({
					minimumResultsForSearch: 0,
					dropdownAutoWidth: true,
					placeholder: hasEmptyOption ? "" : undefined,
					allowClear: hasEmptyOption,
				});

			});
	}
}

function measureTextWidth(text, font) {
	const canvas = measureTextWidth.canvas || (measureTextWidth.canvas = document.createElement('canvas'));
	const ctx = canvas.getContext('2d');
	ctx.font = font;
	return ctx.measureText(text).width;
}

function calcSelectWidth($select) {
	const el = $select[0];
	const style = window.getComputedStyle(el);

	const font = style.font || [
		style.fontStyle,
		style.fontVariant,
		style.fontWeight,
		style.fontSize + '/' + style.lineHeight,
		style.fontFamily
	].join(' ');

	let max = 0;

	$select.find('option').each(function() {
		const text = (this.textContent || this.innerText || '').trim();
		max = Math.max(max, measureTextWidth(text, font));
	});

	const padding =
		(parseFloat(style.paddingLeft) || 0) +
		(parseFloat(style.paddingRight) || 0);

	const arrowAllowance = 32; // room for Select2 arrow + small buffer

	return Math.ceil(max + padding + arrowAllowance);
}

function set_page_width() {
	if ($('span#expand').is(":visible")) {
		$('div.main_content').css({ "max-width": max_width + 'px' });
		$('div#title_container').css({ "max-width": (max_width - 15) + 'px' })
	} else {
		$('div.main_content').css({ "max-width": "calc(100vw - 40px)" });
		$('div#title_container').css({ "max-width": "calc(100vw - 15px)" })
	}
}

function show_expand_trigger() {
	if ($(window).width() > max_width + 100) {
		$("a#expand_trigger").show();
	} else {
		$('a#expand_trigger').hide();
	}
}

function reloadTooltips() {
	var title = $("a[title],span[title]").not('.lightbox');
	$.each(title, function(index, value) {
		var value = $(this).attr('title');
		value = value.replace(/^([^<h3>].+?) - /, "<h3>$1</h3>");
		$(this).tooltip({ content: value });
	});
	title = $("label[title]").not('.lightbox');
	$.each(title, function(index, value) {
		var value = $(this).attr('title');
		$(this).tooltip({ content: value });
	});
}

function getCookie(name) {
	var dc = document.cookie;
	var prefix = name + "=";
	var begin = dc.indexOf("; " + prefix);
	if (begin == -1) {
		begin = dc.indexOf(prefix);
		if (begin != 0) return null;
	} else
		begin += 2;
	var end = document.cookie.indexOf(";", begin);
	if (end == -1)
		end = dc.length;
	return unescape(dc.substring(begin + prefix.length, end));
}