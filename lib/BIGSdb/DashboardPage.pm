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
	if ( $q->param('new') ) {
		$self->_ajax_new( scalar $q->param('new') );
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
		-default => $elements->{$id}->{'width'}
	);
	say q(</li><li><span class="fas fa-arrows-alt-v fa-fw"></span> );
	say $q->radio_group(
		-name    => "${id}_height",
		-id      => "${id}_height",
		-class   => 'height_select',
		-values  => [ 1, 2, 3 ],
		-default => $elements->{$id}->{'height'}
	);
	say q(</li></ul>);
	say q(</fieldset>);
	say q(</div>);
	return;
}

sub _ajax_new {
	my ( $self, $id ) = @_;
	my $element;
	if (LAYOUT_TEST) {
		$element = {
			id      => $id,
			order   => $id,
			name    => "Test element $id",
			width   => 1,
			height  => 1,
			display => 'test',
		};
	}
	say encode_json(
		{
			element => $element,
			html    => $self->_get_element_html($element)
		}
	);
	return;
}

sub _get_dashboard_empty_message {
	my ($self) = @_;
	return
	    q(<div><p>)
	  . q(<span class="dashboard_empty_message">Dashboard contains no elements!</span></p>)
	  . q(<p>Go to dashboard settings to add visualisations.</p></div>);
}

sub _print_main_section {
	my ($self) = @_;
	say q(<div id="dashboard" class="grid" style="min-height:400px">);
	my $elements = $self->_get_elements;
	if ( !keys %$elements ) {
		say $self->_get_dashboard_empty_message;
		return;
	}
	foreach my $element ( sort { $elements->{$a}->{'order'} <=> $elements->{$b}->{'order'} } keys %$elements ) {
		say $self->_get_element_html( $elements->{$element} );
	}
	say q(</div>);
	return;
}

sub _get_elements {
	my ($self) = @_;
	if ( defined $self->{'prefs'}->{'dashboard.elements'} ) {
		my $elements = {};
		eval { $elements = decode_json( $self->{'prefs'}->{'dashboard.elements'} ); };
		if (@$) {
			$logger->error('Invalid JSON in dashboard.elements.');
		}
		return $elements;
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
			order   => $i,
			name    => "Test element $i",
			width   => $w,
			height  => $h,
			display => 'test',
		};
	}
	return $elements;
}

sub _get_element_html {
	my ( $self, $element ) = @_;
	my $buffer       = qq(<div id="element_$element->{'id'}" data-id="$element->{'id'}" class="item">);
	my $width_class  = "dashboard_element_width$element->{'width'}";
	my $height_class = "dashboard_element_height$element->{'height'}";
	$buffer .= qq(<div class="item-content $width_class $height_class">);
	$buffer .= $self->_get_element_controls( $element->{'id'} );
	if ( $element->{'display'} eq 'test' ) {
		$buffer .= $self->_get_test_element_content($element);
	}
	$buffer .= q(</div></div>);
	return $buffer;
	
}

sub _get_test_element_content {
	my ( $self, $element ) = @_;
	my $buffer =
	    qq(<p style="font-size:3em;padding-top:0.75em;text-align:center;color:#aaa">$element->{'id'}</p>)
	  . q(<p style="text-align:center;font-size:0.9em;margin-top:-2em">)
	  . qq(W<span id="$element->{'id'}_width">$element->{'width'}</span>; )
	  . qq(H<span id="$element->{'id'}_height">$element->{'height'}</span></p>);
	return $buffer;
}

sub _get_element_controls {
	my ( $self, $id ) = @_;
	my $display = $self->{'prefs'}->{'dashboard.remove_elements'} ? 'inline' : 'none';
	my $buffer =
	    qq(<span data-id="$id" id="control_$id" )
	  . qq(class="dashboard_remove_element far fa-trash-alt" style="display:$display"></span>)
	  . qq(<span data-id="$id" id="wait_$id" class="dashboard_wait fas fa-sync-alt )
	  . q(fa-spin" style="display:none"></span>);
	$display = $self->{'prefs'}->{'dashboard.edit_elements'} ? 'inline' : 'none';
	$buffer .=
	    qq(<span data-id="$id" id="control_$id" class="dashboard_edit_element fas fa-sliders-h" )
	  . qq(style="display:$display"></span>);
	return $buffer;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery noCache muuri modal bigsdb.dashboard);
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
	foreach my $ajax_param (qw(updatePrefs control resetDefaults new)) {
		if ( $q->param($ajax_param) ) {
			$self->{'type'} = 'no_header';
			last;
		}
	}
	my $guid = $self->get_guid;
	if ( $q->param('resetDefaults') ) {
		$self->{'prefstore'}->delete_dashboard_settings( $guid, $self->{'system'}->{'db'} ) if $guid;
	}
	$self->{'prefs'} = $self->{'prefstore'}->get_all_general_prefs( $guid, $self->{'system'}->{'db'} );
	return;
}

sub _update_prefs {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $attribute = $q->param('attribute');
	return if !defined $attribute;
	my $value = $q->param('value');
	return if !defined $value;
	my %allowed_attributes =
	  map { $_ => 1 } qw(layout fill_gaps edit_elements remove_elements order elements default);
	if ( !$allowed_attributes{$attribute} ) {
		$logger->error("Invalid attribute - $attribute");
		return;
	}
	$attribute = "dashboard.$attribute";
	if ( $attribute eq 'layout' ) {
		my %allowed_values = map { $_ => 1 } ( 'left-top', 'right-top', 'left-bottom', 'right-bottom' );
		return if !$allowed_values{$value};
	}
	my %boolean_attributes = map { $_ => 1 } qw(fill_gaps edit_elements remove_elements);
	if ( $boolean_attributes{$attribute} ) {
		my %allowed_values = map { $_ => 1 } ( 0, 1 );
		return if !$allowed_values{$value};
	}
	my %json_attributes = map { $_ => 1 } qw(order elements);
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
	$self->{'prefstore'}->set_general( $guid, $self->{'system'}->{'db'}, $attribute, $value );
	return;
}

sub print_panel_buttons {
	my ($self) = @_;
	say q(<span class="icon_button"><a class="trigger_button" id="panel_trigger" style="display:none">)
	  . q(<span class="fas fa-lg fa-wrench"></span><div class="icon_label">Dashboard settings</div></a></span>);
	say q(<span class="icon_button"><a class="trigger_button" id="dashboard_toggle">)
	  . q(<span class="fas fa-lg fa-th-list"></span><div class="icon_label">Index page</div></a></span>);
	return;
}

sub _print_modify_dashboard_fieldset {
	my ($self) = @_;
	my $layout          = $self->{'prefs'}->{'dashboard.layout'}          // 'left-top';
	my $fill_gaps       = $self->{'prefs'}->{'dashboard.fill_gaps'}       // 1;
	my $edit_elements   = $self->{'prefs'}->{'dashboard.edit_elements'}   // 0;
	my $remove_elements = $self->{'prefs'}->{'dashboard.remove_elements'} // 0;
	my $q               = $self->{'cgi'};
	say q(<div id="modify_panel" class="panel">);
	say q(<a class="trigger" id="close_trigger" href="#"><span class="fas fa-lg fa-times"></span></a>);
	say q(<h2>Dashboard settings</h2>);
	say q(<fieldset><legend>Layout</legend>);
	say q(<ul>);
	say q(<li><label for="layout">Orientation:</label>);
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
	say q(</fieldset>);
	say q(<fieldset><legend>Visual elements</legend>);
	say q(<ul><li>);
	say $q->checkbox(
		-name    => 'edit_elements',
		-id      => 'edit_elements',
		-label   => 'Enable options',
		-checked => $edit_elements ? 'checked' : undef
	);
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'remove_elements',
		-id      => 'remove_elements',
		-label   => 'Enable removal',
		-checked => $remove_elements ? 'checked' : undef
	);
	say q(</li></ul>);
	say q(</fieldset>);
	say q(<div style="clear:both"></div>);
	say q(<fieldset><legend>Visual elements</legend>);
	say q(<a id="add_element" class="small_submit">Add element</a>);
	say q(</fieldset>);
	say q(<div style="clear:both"></div>);
	say q(<div style="margin-top:2em">);
	say q(<a onclick="resetDefaults()" class="small_reset">Reset</a> Return to defaults);
	say q(</div></div>);
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $order = $self->{'prefs'}->{'dashboard.order'} // q();
	if ($order) {
		eval { decode_json($order); };
		if ($@) {
			$logger->error('Invalid order JSON');
			$order = q();
		}
	}
	my $elements      = $self->_get_elements;
	my $json_elements = encode_json($elements);
	my $empty         = $self->_get_dashboard_empty_message;
	my $buffer        = << "END";
var url = "$self->{'system'}->{'script_name'}";
var ajax_url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=dashboard&updatePrefs=1";
var reset_url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=dashboard&resetDefaults=1";
var modal_control_url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=dashboard";
var elements = $json_elements;
var order = '$order';
var instance = "$self->{'instance'}";
var empty='$empty';

END
	return $buffer;
}
1;
