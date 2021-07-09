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
use BIGSdb::Constants qw(:design :interface :limits);
use Try::Tiny;
use JSON;
use Data::Dumper;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant {
	LAYOUT_TEST               => 0,           #TODO Remove
	COUNT_MAIN_TEXT_COLOUR    => '#404040',
	COUNT_BACKGROUND_COLOUR   => '#79cafb',
	GENOMES_MAIN_TEXT_COLOUR  => '#404040',
	GENOMES_BACKGROUND_COLOUR => '#7ecc66'
};

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
	if ( $q->param('setup') ) {
		$self->_ajax_controls( scalar $q->param('setup'), { setup => 1 } );
		return;
	}
	if ( $q->param('new') ) {
		$self->_ajax_new( scalar $q->param('new') );
		return;
	}
	if ( $q->param('element') ) {
		$self->_ajax_get( scalar $q->param('element') );
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
	my ( $self, $id, $options ) = @_;
	my $elements = $self->_get_elements;
	my $element  = $elements->{$id};
	my $q        = $self->{'cgi'};
	say q(<div class="modal">);
	say $options->{'setup'} ? q(<h2>Setup visual element</h2>) : q(<h2>Modify visual element</h2>);
	say qq(<p>Field: $element->{'name'}</p>);
	$self->_get_size_controls( $id, $element );
	my %data_methods = (
		record_count => sub {
			$self->_get_change_duration_control( $id, $element );
		}
	);
	if ( $data_methods{ $element->{'display'} } ) {
		say q(<fieldset><legend>Data selection</legend><ul>);
		$data_methods{ $element->{'display'} }->();
		say q(</ul></fieldset>);
	}
	my %interface_methods = (
		record_count => sub {
			$self->_get_text_colour_control( $id, $element );
			$self->_get_watermark_control( $id, $element );
		}
	);
	if ( $interface_methods{ $element->{'display'} } ) {
		say q(<fieldset><legend>Interface</legend><ul>);
		$interface_methods{ $element->{'display'} }->();
		say q(</ul></fieldset>);
	}
	say q(</div>);
	return;
}

sub _get_size_controls {
	my ( $self, $id, $element ) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset><legend>Size</legend>);
	say q(<ul><li><span class="fas fa-arrows-alt-h fa-fw"></span> );
	say $q->radio_group(
		-name    => "${id}_width",
		-id      => "${id}_width",
		-class   => 'width_select',
		-values  => [ 1, 2, 3, 4 ],
		-default => $element->{'width'}
	);
	say q(</li><li><span class="fas fa-arrows-alt-v fa-fw"></span> );
	say $q->radio_group(
		-name    => "${id}_height",
		-id      => "${id}_height",
		-class   => 'height_select',
		-values  => [ 1, 2, 3 ],
		-default => $element->{'height'}
	);
	say q(</li></ul>);
	say q(</fieldset>);
	return;
}

sub _get_change_duration_control {
	my ( $self, $id, $element ) = @_;
	my $q = $self->{'cgi'};
	say q(<li>);
	say q(<label for="change_duration">Show change</label>);
	say $q->popup_menu(
		-name   => "${id}_change_duration",
		-id     => "${id}_change_duration",
		-class  => 'element_option',
		-values => [qw(none week month year)],
		-labels => {
			none  => 'do not show',
			week  => 'past week',
			month => 'past month',
			year  => 'past year'
		},
		-default => $element->{'change_duration'}
	);
	say q(</li>);
	return;
}

sub _get_text_colour_control {
	my ( $self, $id, $element ) = @_;
	my $q = $self->{'cgi'};
	my $default = $element->{'main_text_colour'} // COUNT_MAIN_TEXT_COLOUR;
	say q(<li><label for="text_colour">Main text colour</label>);
	say qq(<input type="color" id="${id}_main_text_colour" value="$default" class="element_option colour_selector">);
	say q(</li><li>);
	$default = $element->{'background_colour'} // COUNT_BACKGROUND_COLOUR;
	say q(<li><label for="text_colour">Main background</label>);
	say qq(<input type="color" id="${id}_background_colour" value="$default" )
	  . q(class="element_option colour_selector">);
	say q(</li>);
	return;
}

sub _get_watermark_control {
	my ( $self, $id, $element ) = @_;
	my $q = $self->{'cgi'};
	my @labels =
	  qw(bacteria bacterium biohazard bug capsules clock dna globe pills syringe tablets users virus viruses);
	my $values = [];
	my $labels = {};
	foreach my $label (@labels) {
		push @$values, "fas fa-$label";
		$labels->{"fas fa-$label"} = $label;
	}
	my %renamed_icons = (
		'fas fa-circle-notch'  => 'plasmid',
		'fas fa-notes-medical' => 'medical notes',
		'far fa-calendar-alt'  => 'calendar',
		'fas fa-file-alt'      => 'document'
	);
	foreach my $value ( keys %renamed_icons ) {
		push @$values, $value;
		$labels->{$value} = $renamed_icons{$value};
	}
	@$values = sort { $labels->{$a} cmp $labels->{$b} } @$values;
	unshift @$values, 'none';
	say q(<li><label for="watermark">Watermark</label>);
	say $self->popup_menu(
		-id      => "${id}_watermark",
		-values  => $values,
		-labels  => $labels,
		-class   => 'element_option watermark_selector',
		-default => $element->{'watermark'} // 'none',
	);
	say q(</li>);
	return;
}

sub _ajax_new {
	my ( $self, $id ) = @_;
	my $element = {
		id     => $id,
		order  => $id,
		width  => 1,
		height => 1,
	};
	if (LAYOUT_TEST) {
		$element->{'name'}    = "Test element $id";
		$element->{'display'} = 'test';
	} else {
		my $default_elements = {
			sp_count => {
				name              => ucfirst("$self->{'system'}->{'labelfield'} count"),
				display           => 'record_count',
				change_duration   => 'week',
				main_text_colour  => COUNT_MAIN_TEXT_COLOUR,
				background_colour => COUNT_BACKGROUND_COLOUR,
				watermark         => 'fas fa-bacteria',
				url               => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=query&submit=1"
			},
			sp_genomes => {
				name              => 'Genome count',
				display           => 'record_count',
				genomes           => 1,
				change_duration   => 'week',
				main_text_colour  => GENOMES_MAIN_TEXT_COLOUR,
				background_colour => GENOMES_BACKGROUND_COLOUR,
				watermark         => 'fas fa-dna',
				url =>
				  "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=query&genomes=1&submit=1"
			}
		};
		my $q     = $self->{'cgi'};
		my $field = $q->param('field');
		if ( $default_elements->{$field} ) {
			$element = { %$element, %{ $default_elements->{$field} } };
		} else {
			( my $display_field = $field ) =~ s/^[f]_//x;
			$element->{'name'}    = $display_field;
			$element->{'field'}   = $field;
			$element->{'display'} = 'setup';
		}
	}
	say encode_json(
		{
			element => $element,
			html    => $self->_get_element_html($element)
		}
	);
	return;
}

sub _ajax_get {
	my ( $self, $id ) = @_;
	my $elements = $self->_get_elements;
	if ( $elements->{$id} ) {
		say encode_json(
			{
				element => $elements->{$id},
				html    => $self->_get_element_content( $elements->{$id} )
			}
		);
		return;
	}
	say encode_json(
		{
			html => '<p>Invalid element!</p>'
		}
	);
	return;
}

sub _get_dashboard_empty_message {
	my ($self) = @_;
	return q(<p><span class="dashboard_empty_message">Dashboard contains no elements!</span></p>)
	  . q(<p>Go to dashboard settings to add visualisations.</p>);
}

sub _print_main_section {
	my ($self) = @_;
	my $elements = $self->_get_elements;
	say q(<div style="min-height:400px"><div id="empty">);
	if ( !keys %$elements ) {
		say $self->_get_dashboard_empty_message;
	}
	say q(</div>);
	say q(<div id="dashboard" class="grid">);
	my %display_immediately = map { $_ => 1 } qw(test setup record_count);
	my $ajax_load = [];
	foreach my $element ( sort { $elements->{$a}->{'order'} <=> $elements->{$b}->{'order'} } keys %$elements ) {
		my $display = $elements->{$element}->{'display'};
		if ( $display_immediately{$display} ) {
			say $self->_get_element_html( $elements->{$element} );
		} else {
			say $self->_load_element_html_by_ajax( $elements->{$element} );
			push @$ajax_load, $element;
		}
	}
	say q(</div></div>);
	if (@$ajax_load) {
		$self->_print_ajax_load_code($ajax_load);
	}
	return;
}

sub _print_ajax_load_code {
	my ( $self, $element_ids ) = @_;
	local $" = q(,);
	say q[<script>];
	say q[$(function () {];
	foreach my $element_id (@$element_ids) {
		say << "JS"
	var element_ids = [@$element_ids];
	\$.each(element_ids, function(index,value){
		\$.ajax({
	    	url:"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=dashboard&element=" + value
	    }).done(function(json){
	       	try {
	       	    \$("div#element_" + value + " > .item-content > .ajax_content").html(JSON.parse(json).html);
	       	} catch (err) {
	       		console.log(err.message);
	       	} 	          	    
	    });			
	});    
JS
	}
	say q[});];
	say q(</script>);
	return;
}

sub _get_elements {
	my ($self) = @_;
	my $elements = {};
	if ( defined $self->{'prefs'}->{'dashboard.elements'} ) {
		eval { $elements = decode_json( $self->{'prefs'}->{'dashboard.elements'} ); };
		if (@$) {
			$logger->error('Invalid JSON in dashboard.elements.');
		}
		return $elements;
	}
	if (LAYOUT_TEST) {
		return $self->_get_test_elements;
	}
	return $elements;
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
	$buffer .= $self->_get_element_controls($element);
	$buffer .= q(<div class="ajax_content" style="position:relative;overflow:hidden">);
	$buffer .= $self->_get_element_content($element);
	$buffer .= q(</div></div></div>);
	return $buffer;
}

sub _load_element_html_by_ajax {
	my ( $self, $element ) = @_;
	my $buffer       = qq(<div id="element_$element->{'id'}" data-id="$element->{'id'}" class="item">);
	my $width_class  = "dashboard_element_width$element->{'width'}";
	my $height_class = "dashboard_element_height$element->{'height'}";
	$buffer .= qq(<div class="item-content $width_class $height_class">);
	$buffer .= $self->_get_element_controls($element);
	$buffer .= q(<div class="ajax_content" style="position:relative;overflow:hidden">)
	  . q(<span class="dashboard_wait_ajax fas fa-sync-alt fa-spin"></span></div>);
	$buffer .= q(</div></div>);
	return $buffer;
}

sub _get_element_content {
	my ( $self, $element ) = @_;
	my %display = (
		test         => sub { $self->_get_test_element_content($element) },
		setup        => sub { $self->_get_setup_element_content($element) },
		record_count => sub { $self->_get_count_element_content($element) }
	);
	if ( $display{ $element->{'display'} } ) {
		return $display{ $element->{'display'} }->();
	}
	return q();
}

sub _get_test_element_content {
	my ( $self, $element ) = @_;
	my $buffer =
	    qq(<p style="font-size:3em;padding-top:0.75em;color:#aaa">$element->{'id'}</p>)
	  . q(<p style="text-align:center;font-size:0.9em;margin-top:-2em">)
	  . qq(W<span id="$element->{'id'}_width">$element->{'width'}</span>; )
	  . qq(H<span id="$element->{'id'}_height">$element->{'height'}</span></p>);
	return $buffer;
}

sub _get_setup_element_content {
	my ( $self, $element ) = @_;
	my $buffer = q(<div><p style="font-size:2em;padding-top:0.75em;color:#aaa">Setup</p>);
	$buffer .= q(<p style="font-size:0.8em;overflow:hidden;text-overflow:ellipsis;margin-top:-1em">)
	  . qq($element->{'name'}</p>);
	$buffer .= qq(<p><span data-id="$element->{'id'}" class="setup_element fas fa-wrench"></span></p>);
	$buffer .= q(</div>);
	return $buffer;
}

sub _get_count_element_content {
	my ( $self, $element ) = @_;
	my $buffer            = qq(<div class="title">$element->{'name'}</div>);
	my $text_colour       = $element->{'main_text_colour'} // COUNT_MAIN_TEXT_COLOUR;
	my $background_colour = $element->{'background_colour'} // COUNT_BACKGROUND_COLOUR;
	my $qry               = "SELECT COUNT(*) FROM $self->{'system'}->{'view'}";
	my @filters;
	push @filters, 'new_version IS NULL' if !$self->{'prefs'}->{'dashboard.include_old_versions'};
	my $genome_size = $self->{'system'}->{'min_genome_size'} // $self->{'config'}->{'min_genome_size'}
	  // MIN_GENOME_SIZE;
	push @filters, "id IN (SELECT isolate_id FROM seqbin_stats WHERE total_length>=$genome_size)"
	  if $element->{'genomes'};
	local $" = ' AND ';
	$qry .= " WHERE @filters" if @filters;
	my $count      = $self->{'datastore'}->run_query($qry);
	my $nice_count = BIGSdb::Utils::commify($count);
	$buffer .=
	    qq(<div style="background-image:linear-gradient(#fff,$background_colour,#fff);)
	  . q(margin-top:-1em;padding:2em 0.5em 0 0.5em;height:100%"><p><span class="dashboard_big_number" )
	  . qq(style="color:$text_colour">$nice_count</span></p>);

	if ( $element->{'change_duration'} && $count > 0 ) {
		my %allowed = map { $_ => 1 } qw(week month year);
		if ( $allowed{ $element->{'change_duration'} } ) {
			$qry = "SELECT COUNT(*) FROM $self->{'system'}->{'view'} WHERE "
			  . "date_entered <= now()-interval '1 $element->{'change_duration'}'";
			$qry .= " AND @filters" if @filters;
			my $past_count = $self->{'datastore'}->run_query($qry);
			if ($past_count) {
				my $increase      = $count - $past_count;
				my $nice_increase = BIGSdb::Utils::commify($increase);
				my $class         = $increase ? 'increase' : 'no_change';
				$buffer .= qq(<p class="dashboard_comment $class"><span class="fas fa-caret-up"></span> )
				  . qq($nice_increase [$element->{'change_duration'}]</p>);
			}
		}
	}
	$buffer .= $self->_add_element_watermark($element);
	$buffer .= q(</div>);
	return $buffer;
}

sub _add_element_watermark {
	my ( $self, $element ) = @_;
	return if ( $element->{'watermark'} // q() ) !~ /^fa[r|s]\ fa\-/x;
	my $buffer = qq(<span class="dashboard_watermark $element->{'watermark'}"></span>);
	return $buffer;
}

sub _get_element_controls {
	my ( $self, $element ) = @_;
	my $id = $element->{'id'};
	my $display = $self->{'prefs'}->{'dashboard.remove_elements'} ? 'inline' : 'none';
	my $buffer =
	    qq(<span data-id="$id" id="remove_$id" )
	  . qq(class="dashboard_remove_element far fa-trash-alt" style="display:$display"></span>)
	  . qq(<span data-id="$id" id="wait_$id" class="dashboard_wait fas fa-sync-alt )
	  . q(fa-spin" style="display:none"></span>);
	$display = $self->{'prefs'}->{'dashboard.edit_elements'} ? 'inline' : 'none';
	$buffer .=
	    qq(<span data-id="$id" id="control_$id" class="dashboard_edit_element fas fa-sliders-h" )
	  . qq(style="display:$display"></span>);
	if ( $element->{'url'} ) {
		$buffer .= qq(<span <span data-id="$id" id="explore_$id" class="dashboard_explore_element fas fa-share"></span>);
	}
	return $buffer;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery noCache muuri modal fitty bigsdb.dashboard);
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
	foreach my $ajax_param (qw(updatePrefs control resetDefaults new setup element)) {
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
	  map { $_ => 1 }
	  qw(layout fill_gaps enable_drag edit_elements remove_elements order elements default include_old_versions);
	if ( !$allowed_attributes{$attribute} ) {
		$logger->error("Invalid attribute - $attribute");
		return;
	}
	$attribute = "dashboard.$attribute";
	if ( $attribute eq 'layout' ) {
		my %allowed_values = map { $_ => 1 } ( 'left-top', 'right-top', 'left-bottom', 'right-bottom' );
		return if !$allowed_values{$value};
	}
	my %boolean_attributes =
	  map { $_ => 1 } qw(fill_gaps enable_drag edit_elements remove_elements include_old_versions);
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
	my $layout               = $self->{'prefs'}->{'dashboard.layout'}               // 'left-top';
	my $fill_gaps            = $self->{'prefs'}->{'dashboard.fill_gaps'}            // 1;
	my $enable_drag          = $self->{'prefs'}->{'dashboard.enable_drag'}          // 0;
	my $edit_elements        = $self->{'prefs'}->{'dashboard.edit_elements'}        // 0;
	my $remove_elements      = $self->{'prefs'}->{'dashboard.remove_elements'}      // 0;
	my $include_old_versions = $self->{'prefs'}->{'dashboard.include_old_versions'} // 0;
	my $q                    = $self->{'cgi'};
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
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'enable_drag',
		-id      => 'enable_drag',
		-label   => 'Enable drag',
		-checked => $enable_drag ? 'checked' : undef
	);
	say q(</li></ul>);
	say q(</fieldset>);
	say q(<fieldset><legend>Filters</legend>);
	say q(<ul><li>);
	say $q->checkbox(
		-name    => 'include_old_versions',
		-id      => 'include_old_versions',
		-label   => 'Include old record versions',
		-checked => $include_old_versions ? 'checked' : undef
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
	say q(<ul><li>);

	if ( !LAYOUT_TEST ) {
		$self->_print_field_selector;
	}
	say q(<a id="add_element" class="small_submit" style="white-space:nowrap">Add element</a>);
	say q(</li></ul>);
	say q(</fieldset>);
	say q(<div style="clear:both"></div>);
	say q(<div style="margin-top:2em">);
	say q(<a onclick="resetDefaults()" class="small_reset">Reset</a> Return to defaults);
	say q(</div></div>);
	return;
}

sub _print_field_selector {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $fields, $labels ) = $self->get_field_selection_list(
		{
			ignore_prefs        => 1,
			isolate_fields      => 1,
			scheme_fields       => 0,
			extended_attributes => 0,
			eav_fields          => 0,
		}
	);
	my $values           = [];
	my $group_members    = {};
	my $attributes       = $self->{'xmlHandler'}->get_all_field_attributes;
	my $eav_fields       = $self->{'datastore'}->get_eav_fields;
	my $eav_field_groups = { map { $_->{'field'} => $_->{'category'} } @$eav_fields };
	my %ignore           = map { $_ => 1 } ( 'f_id', "f_$self->{'system'}->{'labelfield'}" );

	foreach my $field (@$fields) {
		next if $ignore{$field};
		if ( $field =~ /^s_/x ) {
			push @{ $group_members->{'Schemes'} }, $field;
		}
		if ( $field =~ /^[f|e]_/x ) {
			( my $stripped_field = $field ) =~ s/^[f|e]_//x;
			$stripped_field =~ s/[\|\||\s].+$//x;
			if ( $attributes->{$stripped_field}->{'group'} ) {
				push @{ $group_members->{ $attributes->{$stripped_field}->{'group'} } }, $field;
			} else {
				push @{ $group_members->{'General'} }, $field;
			}
		}
		if ( $field =~ /^eav_/x ) {
			( my $stripped_field = $field ) =~ s/^eav_//x;
			if ( $eav_field_groups->{$stripped_field} ) {
				push @{ $group_members->{ $eav_field_groups->{$stripped_field} } }, $field;
			} else {
				push @{ $group_members->{'General'} }, $field;
			}
		}
	}
	my @group_list = split /,/x, ( $self->{'system'}->{'field_groups'} // q() );
	push @{ $group_members->{'Special'} }, 'sp_count', 'sp_genomes';
	$labels->{'sp_count'}   = "$self->{'system'}->{'labelfield'} count";
	$labels->{'sp_genomes'} = 'genome count';
	my @eav_groups = split /,/x, ( $self->{'system'}->{'eav_groups'} // q() );
	push @group_list, @eav_groups if @eav_groups;
	push @group_list, ( 'Loci', 'Schemes' );

	foreach my $group ( 'Special', undef, @group_list ) {
		my $name = $group // 'General';
		$name =~ s/\|.+$//x;
		if ( ref $group_members->{$name} ) {
			push @$values, $q->optgroup( -name => $name, -values => $group_members->{$name}, -labels => $labels );
		}
	}
	say q(<label for="add_field">Field:</label>);
	say $q->popup_menu(
		-name     => 'add_field',
		-id       => 'add_field',
		-values   => $values,
		-labels   => $labels,
		-multiple => 'true',
		-style    => 'max-width:10em'
	);
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $order = $self->{'prefs'}->{'dashboard.order'} // q();
	my $enable_drag = $self->{'prefs'}->{'dashboard.enable_drag'} ? 'true' : 'false';
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
var url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}";
var elements = $json_elements;
var order = '$order';
var instance = "$self->{'instance'}";
var empty='$empty';
var enable_drag=$enable_drag;

END
	return $buffer;
}
1;
