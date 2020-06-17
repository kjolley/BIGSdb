//Version 20200617

$(function () {
	$('div.content a:not(.lightbox)').tooltip({ 
	    track: false, 
	    show: {delay: 250}, 
	    showURL: false, 
	    showBody: " - ", 
	    fade: 250 
	});
	$('.showhide').show();
	$("#hidefromnonJS").removeClass("hiddenbydefault");
	$(".hideonload").slideUp("normal");
	$('.hideshow').hide();
	$('#toggle1,#toggle2').click(function(){
      $('.showhide').toggle();
      $('.hideshow').toggle();
    });	
	$('.flash_message').effect('highlight',{},2000).hide('fade',{},1000);
	
	$('a#toggle_tooltips,span#toggle').show();
	$('a#toggle_tooltips').click(function(event){		
		event.preventDefault();
		$('.tooltip').toggle();
	  	$(this).attr('href', function(){  		
	  		$.ajax({
	  			url: this.href,
	  			cache: false,
	  		});
	   	});
	});
	show_expand_trigger();
	$('a#expand_trigger').click(function(event){
		if ($('span#expand').is(":visible")){
			$('div.main_content').css({"max-width":"calc(100vw - 40px)"});
			$('span#expand').hide();
			$('span#contract').show();
		} else {
			$('div.main_content').css({"max-width":max_width + 'px'});
			$('span#expand').show();
			$('span#contract').hide();
		}
	});
	$("a#expand_trigger").show().animate({backgroundColor: "#9cc"},500);
	
	//Tooltips
	reloadTooltips();
	
	//Add tooltip to truncated definition list titles
	$('dt').each(function(){
		if( this.offsetWidth + 1 < this.scrollWidth){
			$(this).prop('title', $(this).text());
			$(this).tooltip();
			$(this).css('cursor', 'pointer');
		}
	});
	$(window).resize(function() {
		show_expand_trigger();
	});
	
});

$.urlParam = function(name){
    var results = new RegExp('[\?&]' + name + '=([^&#]*)').exec(window.location.href);
    if (results==null){
       return null;
    }
    else{
       return results[1] || 0;
    }
}

function show_expand_trigger() {
	if ($(window).width() > max_width){
		$('a#expand_trigger').show();
	} else {
		$('a#expand_trigger').hide();
	}
}

function reloadTooltips() {
	var title = $("a[title]" ).not('.lightbox');
	$.each(title, function(index, value) {
		var value = $(this).attr('title');
		value = value.replace(/^([^<h3>].+?) - /,"<h3>$1</h3>");
		$(this).tooltip({content: value});
	});
	title = $("label[title]" ).not('.lightbox');
	$.each(title, function(index, value) {
		var value = $(this).attr('title');
		$(this).tooltip({content: value});
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