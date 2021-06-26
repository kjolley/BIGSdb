#Written by Keith Jolley
#Copyright (c) 2021, University of Oxford
#E-mail: keith.jolley@zoo.ox.ac.uk
#
#This file is part of Bacterial Isolate Genome Sequence Database (BIGSdb).
#
#BIGSdb is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#BIGSdb is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
package BIGSdb::DashboardPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::IndexPage);
use BIGSdb::Constants qw(:design :interface);
use Try::Tiny;
use JSON;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant LAYOUT_TEST => 1;    #TODO Remove

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('updatePrefs') ) {
		$self->_update_prefs;
		return;
	}
	if ( $q->param('control') ) {
		$self->_ajax_controls( scalar $q->param('control') );
		return;
	}
	my $desc = $self->get_db_description( { formatted => 1 } );
	my $max_width = $self->{'config'}->{'page_max_width'} // PAGE_MAX_WIDTH;
	my $title_max_width = $max_width - 15;
	say q(<div class="flex_container" style="flex-direction:column;align-items:center">);
	say q(<div>);
	say qq(<div style="width:95vw;max-width:${title_max_width}px"></div>);
	say qq(<div id="title_container" style="max-width:${title_max_width}px">);
	say qq(<h1>$desc database</h1>);
	$self->print_general_announcement;
	$self->print_banner;

	if ( ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ) {
		$self->print_set_section;
	}
	say q(</div>);
	say qq(<div id="main_container" class="flex_container" style="max-width:${max_width}px">);
	say qq(<div class="index_panel" style="max-width:${max_width}px">);

	#	say q(<div id="waiting" class="dashboard_waiting"><span class="wait_icon fas fa-sync-alt fa-spin"></span></div>);
	$self->_print_main_section;
	say q(</div>);
	say q(</div>);
	say q(</div>);
	say q(</div>);
	$self->_print_modify_dashboard_fieldset;
	return;
}

sub _ajax_controls {
	my ( $self, $id ) = @_;
	my $elements = $self->_get_elements;
	use Data::Dumper;
	$logger->error( Dumper $elements->{$id} );
	my $q = $self->{'cgi'};
	say q(<div class="modal">);
	say qq(<h2>$elements->{$id}->{'name'} options</h2>);
	say q(<fieldset><legend>Size</legend>);
	say q(<ul><li><span class="fas fa-arrows-alt-h fa-fw"></span> );
	say $q->radio_group(
		-name    => "${id}_width",
		-id      => "${id}_width",
		-class   => 'width_select',
		-values  => [ 1, 2, 3, 4 ],
		-default => $elements->{$id}->{'w'}
	);
	say q(</li><li><span class="fas fa-arrows-alt-v fa-fw"></span> );
	say $q->radio_group(
		-name    => "${id}_height",
		-id      => "${id}_height",
		-class   => 'height_select',
		-values  => [ 1, 2, 3 ],
		-default => $elements->{$id}->{'h'}
	);
	say q(</li></ul>);
	say q(</fieldset>);
	say q(</div>);
	return;
}

sub _print_main_section {
	my ($self) = @_;
	say q(<div id="dashboard" class="grid">);
	my $elements = $self->_get_elements;
	$logger->error( Dumper $elements);
	foreach my $element ( sort { $elements->{$a}->{'order'} <=> $elements->{$b}->{'order'} } keys %$elements ) {
		$self->_print_element( $elements->{$element} );
	}
	say q(</div>);
	return;
}

sub _get_elements {
	my ($self) = @_;
	if ( $self->{'prefs'}->{'dashboard.elements'} ) {
		my $elements = {};
		eval { $elements = decode_json( $self->{'prefs'}->{'dashboard.elements'} ); };
		if (@$) {
			$logger->error('Invalid JSON in dashboard.elements.');
		}
		return $elements if keys %$elements;
	}
	if (LAYOUT_TEST) {
		return $self->_get_test_elements;
	}
}

sub _get_test_elements {
	my ($self) = @_;
	my $elements = {};
	for my $i ( 1 .. 10 ) {
		my $w = $i % 2 ? 1 : 2;
		$w = 3 if $i == 7;
		$w = 4 if $i == 4;
		my $h = $i == 2 ? 2 : 1;
		$elements->{$i} = {
			id      => $i,
			name    => "Test element $i",
			w       => $w,
			h       => $h,
			display => 'test',
			order   => $i
		};
	}
	return $elements;
}

sub _print_element {
	my ( $self, $element ) = @_;
	say qq(<div data-id="$element->{'id'}" class="item">);
	my $width_class  = "dashboard_element_width$element->{'w'}";
	my $height_class = "dashboard_element_height$element->{'h'}";
	say qq(<div class="item-content $width_class $height_class">);
	$self->_print_settings_button( $element->{'id'} );
	if ( $element->{'display'} eq 'test' ) {
		$self->_print_test_element_content($element);
	}
	say q(</div></div>);
	return;
}

sub _print_test_element_content {
	my ( $self, $element ) = @_;
	say qq(<p style="font-size:3em;padding-top:0.75em;text-align:center;color:#aaa">$element->{'id'}</p>);
	say q(<p style="text-align:center;font-size:0.9em;margin-top:-2em">)
	  . qq(W<span id="$element->{'id'}_width">$element->{'w'}</span>; )
	  . qq(H<span id="$element->{'id'}_height">$element->{'h'}</span></p>);
	return;
}

sub _print_settings_button {
	my ( $self, $id ) = @_;
	say
	  qq(<span data-id="$id" id="wait_$id" class="dashboard_wait fas fa-sync-alt fa-spin" style="display:none"></span>);
	say qq(<span data-id="$id" id="control_$id" class="dashboard_control fas fa-sliders-h"></span>);
	return;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery noCache muuri modal);
	$self->choose_set;
	$self->{'breadcrumbs'} = [];
	if ( $self->{'system'}->{'webroot'} ) {
		push @{ $self->{'breadcrumbs'} },
		  {
			label => $self->{'system'}->{'webroot_label'} // 'Organism',
			href => $self->{'system'}->{'webroot'}
		  };
	}
	push @{ $self->{'breadcrumbs'} },
	  { label => $self->{'system'}->{'formatted_description'} // $self->{'system'}->{'description'} };
	my $q = $self->{'cgi'};
	if ( $q->param('updatePrefs') || $q->param('control') || $q->param('resetDefaults') ) {
		$self->{'type'} = 'no_header';
	}
	my $guid = $self->get_guid;
	if ( $q->param('resetDefaults') ) {
		$self->{'prefstore'}->delete_dashboard_settings( $guid, $self->{'instance'} ) if $guid;
	}
	$self->{'prefs'} = $self->{'prefstore'}->get_all_general_prefs( $guid, $self->{'instance'} );
	return;
}

sub _update_prefs {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $attribute = $q->param('attribute');
	return if !defined $attribute;
	my $value = $q->param('value');
	return if !defined $value;
	my %allowed_attributes = map { $_ => 1 } qw(layout fill_gaps order);
	return if !$allowed_attributes{$attribute};
	$attribute = "dashboard.$attribute";

	if ( $attribute eq 'layout' ) {
		my %allowed_values = map { $_ => 1 } ( 'left-top', 'right-top', 'left-bottom', 'right-bottom' );
		return if !$allowed_values{$value};
	}
	my %boolean_attributes = map { $_ => 1 } qw(fill_gaps);
	if ( $boolean_attributes{$attribute} ) {
		my %allowed_values = map { $_ => 1 } ( 0, 1 );
		return if !$allowed_values{$value};
	}
	my %json_attributes = map { $_ => 1 } qw(order);
	if ( $json_attributes{$attribute} ) {
		if ( length( $value > 5000 ) ) {
			$logger->error("$attribute value too long.");
			return;
		}
		eval { decode_json($value); };
		if ($@) {
			$logger->error("Invalid JSON for $attribute attribute");
		}
	}
	my $guid = $self->get_guid;
	$self->{'prefstore'}->set_general( $guid, $self->{'instance'}, $attribute, $value );
	return;
}

sub print_panel_buttons {
	my ($self) = @_;
	say q(<span class="icon_button"><a class="trigger_button" id="panel_trigger" style="display:none">)
	  . q(<span class="fas fa-lg fa-wrench"></span><div class="icon_label">Modify display</div></a></span>);
	return;
}

sub _print_modify_dashboard_fieldset {
	my ($self) = @_;
	my $layout    = $self->{'prefs'}->{'dashboard.layout'}    // 'left-top';
	my $fill_gaps = $self->{'prefs'}->{'dashboard.fill_gaps'} // 1;
	my $q         = $self->{'cgi'};
	say q(<div id="modify_panel" class="panel">);
	say q(<a class="trigger" id="close_trigger" href="#"><span class="fas fa-lg fa-times"></span></a>);
	say q(<h2>Modify dashboard</h2>);
	say q(<ul style="list-style:none;margin-left:-2em">);
	say q(<li><label for="layout">Layout:</label>);
	say $q->popup_menu(
		-name   => 'layout',
		-id     => 'layout',
		-values => [ 'left-top', 'right-top', 'left-bottom', 'right-bottom' ],
		-labels => {
			'left-top'     => 'Left top',
			'right-top'    => 'Right top',
			'left-bottom'  => 'Left bottom',
			'right-bottom' => 'Right bottom'
		},
		-default => $layout
	);
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'fill_gaps',
		-id      => 'fill_gaps',
		-label   => 'Fill gaps',
		-checked => $fill_gaps ? 'checked' : undef
	);
	say q(</li></ul>);
	say q(<a onclick="resetDefaults()" class="small_reset">Reset</a> Return to defaults);
	say q(</div>);
	return;
}

sub get_javascript {
	my ($self)            = @_;
	my $url               = $self->{'system'}->{'script_name'};
	my $ajax_url          = "$url?db=$self->{'instance'}&page=dashboard&updatePrefs=1";
	my $modal_control_url = "$url?db=$self->{'instance'}&page=dashboard";
	my $reset_url         = "$url?db=$self->{'instance'}&page=dashboard&resetDefaults=1";
	my $order = $self->{'prefs'}->{'dashboard.order'} // 0;
	if ($order) {
		eval { decode_json($order); };
		if ($@) {
			$logger->error('Invalid order JSON');
			$order = 0;
		}
	}
	my $order_defined = $order ? 1 : 0;
	my $buffer = << "END";
var grid;
\$(function () {
	var layout = \$("#layout").val();
	var fill_gaps = \$("#fill_gaps").prop('checked');
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
	if ($order_defined){
		loadLayout(grid,'$order');
	}
	\$("#panel_trigger,#close_trigger").click(function(){		
		\$("#modify_panel").toggle("slide",{direction:"right"},"fast");
		\$("#panel_trigger").show();		
		return false;
	});
	\$("#panel_trigger").show();
	\$("#layout").change(function(){
		layout = \$("#layout").val();
		grid._settings.layout.alignRight = layout.includes('right');
		grid._settings.layout.alignBottom = layout.includes('bottom');
		grid.layout();
		\$.ajax("$ajax_url&attribute=layout&value=" + layout );	
	});
	\$("#fill_gaps").change(function(){
		fill_gaps = \$("#fill_gaps").prop('checked');
		grid._settings.layout.fillGaps = fill_gaps;
		grid.layout();
		\$.ajax("$ajax_url&attribute=fill_gaps&value=" + (fill_gaps ? 1 : 0) );	
	});
	\$(".dashboard_control").click(function(){
		var id=\$(this).attr('data-id');
		\$("span#control_" + id).hide();
		\$("span#wait_" + id).show();
		event.preventDefault();
		this.blur(); // Manually remove focus from clicked link.
		\$.get("${modal_control_url}&control=" + id, function(html) {
			\$(html).appendTo('body').modal();
			\$("span#control_" + id).show();
			\$("span#wait_" + id).hide();
		});
	});

	var dimension = ['width','height'];
	dimension.forEach((value) => {
		\$(document).on("change", '.' + value + '_select', function(event) { 
			var id = \$(this).attr('id');
			var element_id = id.replace("_" + value,"");
			changeElementDimension(element_id, value);
		});
	});
});

function changeElementDimension(id, attribute){	
	var item_content = \$("div.item[data-id='" + id + "'] > div.item-content");
	var classes = item_content.attr('class');
	var class_list = classes.split(/\\s+/);
	\$.each(class_list, function(index,value){
		if (value.includes('dashboard_element_' + attribute)){
			item_content.removeClass(value);
		}
	});
	var new_dimension = \$("input[name='" + id + "_" + attribute + "']:checked").val();
	item_content.addClass("dashboard_element_" + attribute + new_dimension); 
	\$("span#" + id + "_" + attribute).html(new_dimension);  	
    grid.refreshItems().layout();
}

function serializeLayout(grid) {
    var itemIds = grid.getItems().map(function (item) {
      return item.getElement().getAttribute('data-id');
    });
    return JSON.stringify(itemIds);
}

function saveLayout(grid) {
    var layout = serializeLayout(grid);
    \$.post("$url",{
    	db:"$self->{'instance'}",
    	page:"dashboard",
    	updatePrefs:1,
    	attribute:"order",
    	value:layout
    });
}

function loadLayout(grid, serializedLayout) {
  var layout = JSON.parse(serializedLayout);
  var currentItems = grid.getItems();
  var currentItemIds = currentItems.map(function (item) {
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
  grid.sort(newItems, {layout: 'instant'});
}

function resetDefaults(){
	\$("#modify_panel").toggle("slide",{direction:"right"},"fast");
	\$.get("$reset_url", function() {		
		\$("#layout").val("left-top");
		\$("#fill_gaps").prop("checked",true);
		 location.reload();
	});
}

END
	return $buffer;
}
1;
