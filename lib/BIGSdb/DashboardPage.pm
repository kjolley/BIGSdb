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
	COUNT_MAIN_TEXT_COLOUR           => '#404040',
	COUNT_BACKGROUND_COLOUR          => '#79cafb',
	GENOMES_MAIN_TEXT_COLOUR         => '#404040',
	GENOMES_BACKGROUND_COLOUR        => '#7ecc66',
	SPECIFIC_FIELD_MAIN_TEXT_COLOUR  => '#404040',
	SPECIFIC_FIELD_BACKGROUND_COLOUR => '#d9e1ff'
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
	my ( $self, $id ) = @_;
	my $elements = $self->_get_elements;
	my $element  = $elements->{$id};
	my $q        = $self->{'cgi'};
	say q(<div class="modal">);
	say q(<h2>Modify visual element</h2>);
	say qq(<p><strong>Field: $element->{'name'}</strong></p>);
	$self->_get_size_controls( $id, $element );

	if ( $element->{'display'} eq 'setup' || $element->{'display'} eq 'field' ) {
		$self->_print_visualisation_type_controls( $id, $element );
		$self->_print_chart_type_controls( $id, $element );
	}
	my %controls = (
		record_count => sub {
			$self->_print_design_control( $id, $element );
			$self->_print_change_duration_control( $id, $element );
		},
		field => sub {
			$self->_print_design_control( $id, $element, { display => 'none' } );
			$self->_print_change_duration_control( $id, $element, { display => 'none' } );
		},
		setup => sub {
			$self->_print_change_duration_control( $id, $element, { display => 'none' } );
			$self->_print_design_control( $id, $element, { display => 'none' } );
		},
	);
	if ( $controls{ $element->{'display'} } ) {
		$controls{ $element->{'display'} }->();
	}
	say q(</div>);
	return;
}

sub _print_visualisation_type_controls {
	my ( $self, $id, $element ) = @_;
	my $q = $self->{'cgi'};
	$element->{'visualisation_type'} //= 'breakdown';
	say q(<fieldset><legend>Visualisation type</legend>);
	say q(<ul><li>);
	say $q->radio_group(
		-id        => "${id}_visualisation_type",
		-name      => "${id}_visualisation_type",
		-label     => 'Type',
		-values    => [ 'breakdown', 'specific values' ],
		-default   => $element->{'visualisation_type'},
		-class     => 'element_option',
		-linebreak => 'true'
	);
	say q(</li>);
	my $display = $element->{'visualisation_type'} eq 'specific values' ? 'block' : 'none';
	say qq(<li id="value_selector" style="display:$display">);

	if ( $self->_field_has_optlist( $element->{'field'} ) ) {
		say q(<label>Select value(s):</label><br />);
		my $values = $self->_get_field_values( $element->{'field'} );
		say $self->popup_menu(
			-name     => "${id}_specific_values",
			-id       => "${id}_specific_values",
			-values   => $values,
			-style    => 'max-width:14em',
			-default  => $element->{'specific_values'},
			-class    => 'element_option',
			-multiple => 'true'
		);
	} else {
		my $html5_args = $self->_get_html5_args( $element->{'field'} );
		local $" = qq(\n);
		say q(<label>Enter value(s):</label><br />);
		say $q->textarea(
			-name  => "${id}_specific_values",
			-id    => "${id}_specific_values",
			-class => 'element_option',
			-style => 'width:14em',
			-value => ref $element->{'specific_values'}
			? qq(@{$element->{'specific_values'}})
			: $element->{'specific_values'},
			-placeholder => 'One value per line...',
		);
	}
	say q(</li>);
	say q(</fieldset>);
	return;
}

sub _get_html5_args {
	my ( $self, $field ) = @_;
	my $html5_args = { required => 'required' };
	if ( $field =~ /^f_(.*)/x ) {
		my $att = $self->{'xmlHandler'}->get_field_attributes($1);
		if ( !$att->{'optlist'} ) {
			if ( $att->{'type'} =~ /^int/x ) {
				@{$html5_args}{qw(type min step)} = qw(number 0 1);
			}
			if ( $att->{'type'} eq 'float' ) {
				@{$html5_args}{qw(type step)} = qw(number any);
			}
			if ( $att->{'type'} eq 'date' ) {
				$html5_args->{'type'} = 'date';
			}
			if ( $att->{'type'} =~ /^int/x || $att->{'type'} eq 'float' || $att->{'type'} eq 'date' ) {
				$html5_args->{'min'} = $att->{'min'} if defined $att->{'min'};
				$html5_args->{'max'} = $att->{'max'} if defined $att->{'max'};
			}
			$html5_args->{'pattern'} = $att->{'regex'} if $att->{'regex'};
		}
	}
	return $html5_args;
}

sub _field_has_optlist {
	my ( $self, $field ) = @_;
	if ( $field =~ /^f_(.*)/x ) {
		my $attributes = $self->{'xmlHandler'}->get_field_attributes($1);
		return 1 if $attributes->{'optlist'};
		return 1 if $attributes->{'type'} =~ /^bool/x;
	}
	return;
}

sub _print_chart_type_controls {
	my ( $self, $id, $element ) = @_;
	my $q = $self->{'cgi'};
	$element->{'visualisation_type'} //= 'breakdown';
	my $breakdown_display = $element->{'visualisation_type'} eq 'breakdown' ? 'block' : 'none';
	my $value_display     = $element->{'visualisation_type'} eq 'breakdown' ? 'none'  : 'block';
	say q(<fieldset><legend>Display element</legend>);
	say qq(<ul><li id="breakdown_display_selector" style="display:$breakdown_display">);
	say q(<label for="breakdown_display">Element: </label>);
	say $q->popup_menu(
		-name    => "${id}_breakdown_display",
		-id      => "${id}_breakdown_display",
		-values  => [qw(0 doughnut pie)],
		-labels  => { 0 => 'Select...' },
		-class   => 'element_option',
		-default => $element->{'breakdown_display'}
	);
	say qq(</li><li id="specific_value_display_selector" style="display:$value_display">);
	say q(<label for="specific_value_display">Element: </label>);
	say $q->popup_menu(
		-name    => "${id}_specific_value_display",
		-id      => "${id}_specific_value_display",
		-values  => [qw(0 number gauge)],
		-labels  => { 0 => 'Select...' },
		-class   => 'element_option',
		-default => $element->{'specific_value_display'}
	);
	say q(</li></ul>);
	say q(</fieldset>);
	return;
}

sub _get_field_values {
	my ( $self, $field ) = @_;
	if ( $field =~ /^f_(.*)/x ) {
		my $attributes = $self->{'xmlHandler'}->get_field_attributes($1);
		if ( $attributes->{'optlist'} ) {
			return $self->{'xmlHandler'}->get_field_option_list($1);
		}
		if ( $attributes->{'type'} =~ /^bool/x ) {
			return [qw(true false)];
		}
	}
	return [];
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

sub _print_change_duration_control {
	my ( $self, $id, $element, $options ) = @_;
	my $display = $options->{'display'} // 'inline';
	my $q = $self->{'cgi'};
	say qq(<fieldset id="change_duration_control" style="display:$display">) . q(<legend>Rate of change</legend><ul>);
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
	say q(</ul></fieldset>);
	return;
}

sub _print_design_control {
	my ( $self, $id, $element, $options ) = @_;
	my $display = $options->{'display'} // 'inline';
	say qq(<fieldset id="design_control" style="display:$display"><legend>Design</legend><ul>);
	$self->_print_text_colour_control( $id, $element );
	$self->_print_watermark_control( $id, $element );
	say q(</ul></fieldset>);
	return;
}

sub _print_text_colour_control {
	my ( $self, $id, $element, $options ) = @_;
	my $display = $options->{'display'} // 'block';
	my $q       = $self->{'cgi'};
	my $default = $element->{'main_text_colour'} // COUNT_MAIN_TEXT_COLOUR;
	say qq(<li class="text_colour_control" style="display:$display"><label for="text_colour">Main text colour</label>);
	say qq(<input type="color" id="${id}_main_text_colour" value="$default" class="element_option colour_selector">);
	say q(</li><li>);
	$default = $element->{'background_colour'} // COUNT_BACKGROUND_COLOUR;
	say qq(<li class="background_colour_control" style="display:$display">)
	  . q(<label for="text_colour">Main background</label>);
	say qq(<input type="color" id="${id}_background_colour" value="$default" )
	  . q(class="element_option colour_selector">);
	say q(</li>);
	return;
}

sub _print_watermark_control {
	my ( $self, $id, $element ) = @_;
	my $q      = $self->{'cgi'};
	my $values = [];
	my $labels = {};
	my $icons  = [
		{ 'fas fa-bacteria'        => 'bacteria' },
		{ 'fas fa-bacterium'       => 'bacterium' },
		{ 'fas fa-virus'           => 'virus' },
		{ 'fas fa-viruses'         => 'viruses' },
		{ 'fas fa-bug'             => 'bug' },
		{ 'fas fa-biohazard'       => 'biohazard' },
		{ 'fas fa-circle-notch'    => 'plasmid' },
		{ 'fas fa-pills'           => 'medicine;treatment;pills' },
		{ 'fas fa-capsules'        => 'medicine;treatment;capsules' },
		{ 'fas fa-tablets'         => 'medicine;treatment;tablets' },
		{ 'fas fa-syringe'         => 'medicine;treatment;vaccine;syringe' },
		{ 'fas fa-dna'             => 'DNA' },
		{ 'fas fa-microscope'      => 'microscope' },
		{ 'fas fa-globe'           => 'country;globe' },
		{ 'fas fa-globe-africa'    => 'country;Africa' },
		{ 'fas fa-globe-americas'  => 'country;Americas' },
		{ 'fas fa-globe-asia'      => 'country;Asia' },
		{ 'fas fa-globe-europe'    => 'country;Europe' },
		{ 'fas fa-map'             => 'region;map' },
		{ 'fas fa-city'            => 'region;city' },
		{ 'fas fa-school'          => 'school' },
		{ 'fas fa-hospital'        => 'hospital' },
		{ 'fas fa-clock'           => 'clock' },
		{ 'far fa-calendar-alt'    => 'calendar' },
		{ 'fas fa-user'            => 'user' },
		{ 'fas fa-users'           => 'users' },
		{ 'fas fa-baby'            => 'age;baby' },
		{ 'fas fa-child'           => 'age;child' },
		{ 'fas fa-mars'            => 'gender;sex;male' },
		{ 'fas fa-venus'           => 'gender;sex;female' },
		{ 'fas fa-venus-mars'      => 'gender;sex' },
		{ 'fas fa-glass-cheers'    => 'risk factor:drinking' },
		{ 'fas fa-weight'          => 'risk factor:weight' },
		{ 'fas fa-smoking'         => 'risk factor:smoking' },
		{ 'fas fa-notes-medical'   => 'diagnosis;medical notes' },
		{ 'fas fa-allergies'       => 'diagnosis:allergies' },
		{ 'fas fa-head-side-cough' => 'diagnosis;cough' },
		{ 'fas fa-heartbeat'       => 'diagnosis;heartbeat' },
		{ 'fas fa-vials'           => 'diagnosis;vials' },
		{ 'fas fa-stethoscope'     => 'diagnosis;stethoscope' },
		{ 'fas fa-user-md'         => 'diagnosis;doctor' },
		{ 'fas fa-file-alt'        => 'document' }
	];
	foreach my $icon (@$icons) {
		push @$values, keys %$icon;
		foreach my $key ( keys %$icon ) {
			$labels->{$key} = $icon->{$key};
		}
	}
	unshift @$values, '';
	say q(<li><label for="watermark">Watermark</label>);
	say $self->popup_menu(
		-name    => "${id}_watermark",
		-id      => "${id}_watermark",
		-values  => $values,
		-labels  => $labels,
		-class   => 'element_option watermark_selector',
		-default => $element->{'watermark'} // '',
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
	if ( $self->{'prefs'}->{'dashboard.layout_test'} ) {
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
				url               => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=query",
				post_data         => {
					db   => $self->{'instance'},
					page => 'query'
				},
				url_text => 'Browse isolates'
			},
			sp_genomes => {
				name              => 'Genome count',
				display           => 'record_count',
				genomes           => 1,
				change_duration   => 'week',
				main_text_colour  => GENOMES_MAIN_TEXT_COLOUR,
				background_colour => GENOMES_BACKGROUND_COLOUR,
				watermark         => 'fas fa-dna',
				url               => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=query",
				post_data         => {
					db      => $self->{'instance'},
					page    => 'query',
					genomes => 1,
				},
				url_text => 'Browse genomes'
			}
		};
		my $q = $self->{'cgi'};
		my $field = $q->param('layout_test') ? q() : $q->param('field');
		if ( $default_elements->{$field} ) {
			$element = { %$element, %{ $default_elements->{$field} } };
		} else {
			( my $display_field = $field ) =~ s/^[f]_//x;
			$element->{'name'}              = ucfirst($display_field);
			$element->{'field'}             = $field;
			$element->{'display'}           = 'setup';
			$element->{'change_duration'}   = 'week';
			$element->{'background_colour'} = SPECIFIC_FIELD_BACKGROUND_COLOUR;
			$element->{'main_text_colour'}  = SPECIFIC_FIELD_MAIN_TEXT_COLOUR;
			my %default_watermarks = (
				f_country => 'fas fa-globe',
				f_region  => 'fas fa-map',
				f_sex     => 'fas fa-venus-mars',
				f_disease => 'fas fa-notes-medical',
				f_year    => 'far fa-calendar-alt'
			);

			if ( $default_watermarks{$field} ) {
				$element->{'watermark'} = $default_watermarks{$field};
			}
		}
	}
	my $json = JSON->new->allow_nonref;
	say $json->encode(
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
	my $json     = JSON->new->allow_nonref;
	if ( $elements->{$id} ) {
		say $json->encode(
			{
				element => $elements->{$id},
				html    => $self->_get_element_content( $elements->{$id} )
			}
		);
		return;
	}
	say $json->encode(
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
	       	    applyFormatting();
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
		my $json = JSON->new->allow_nonref;
		eval { $elements = $json->decode( $self->{'prefs'}->{'dashboard.elements'} ); };
		if (@$) {
			$logger->error('Invalid JSON in dashboard.elements.');
		}
		return $elements;
	}
	if ( $self->{'prefs'}->{'dashboard.layout_test'} ) {
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
	$buffer .= q(<div class="ajax_content" style="position:absolute;overflow:hidden;height:100%;width:100%">);
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
	$buffer .= q(<div class="ajax_content" style="position:absolute;overflow:hidden;height:100%;width:100%">)
	  . q(<span class="dashboard_wait_ajax fas fa-sync-alt fa-spin"></span></div>);
	$buffer .= q(</div></div>);
	return $buffer;
}

sub _get_element_content {
	my ( $self, $element ) = @_;
	my %display = (
		test         => sub { $self->_get_test_element_content($element) },
		setup        => sub { $self->_get_setup_element_content($element) },
		record_count => sub { $self->_get_count_element_content($element) },
		field        => sub { $self->_get_field_element_content($element) }
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
	my $buffer = $self->_get_colour_swatch($element);
	$buffer .= qq(<div class="title">$element->{'name'}</div>);
	my $text_colour       = $element->{'main_text_colour'}  // COUNT_MAIN_TEXT_COLOUR;
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
	my $count = $self->{'datastore'}->run_query($qry);
	my ( $change_duration, $increase );

	if ( $element->{'change_duration'} && $count > 0 ) {
		my %allowed = map { $_ => 1 } qw(week month year);
		if ( $allowed{ $element->{'change_duration'} } ) {
			$change_duration = $element->{'change_duration'};
			$qry             = "SELECT COUNT(*) FROM $self->{'system'}->{'view'} WHERE "
			  . "date_entered <= now()-interval '1 $element->{'change_duration'}'";
			$qry .= " AND @filters" if @filters;
			my $past_count = $self->{'datastore'}->run_query($qry);
			$increase = $count - ( $past_count // 0 );
		}
	}
	$buffer .= $self->_get_big_number_content(
		{
			element           => $element,
			number            => $count,
			background_colour => $background_colour,
			text_colour       => $text_colour,
			change_duration   => $change_duration,
			increase          => $increase
		}
	);
	$buffer .= $self->_get_explore_link($element);
	return $buffer;
}

sub _get_colour_swatch {
	my ( $self, $element ) = @_;
	if ( $element->{'background_colour'} ) {
		return
		    qq(<div id="$element->{'id'}_background" )
		  . qq(style="background-image:linear-gradient(#fff,#fff 10%,$element->{'background_colour'},#fff 90%,#fff);)
		  . q(height:100%;width:100%;position:absolute;z-index:-1"></div>);
	}
	return q();
}

sub _get_big_number_content {
	my ( $self, $args ) = @_;
	my ( $element, $number, $background_colour, $text_colour, $increase, $change_duration ) =
	  @{$args}{qw(element number background_colour text_colour increase change_duration)};
	my $nice_count = BIGSdb::Utils::commify($number);
	my $buffer     = q(<p style="margin:0 10px">)
	  . qq(<span class="dashboard_big_number" style="color:$text_colour">$nice_count</span></p>);
	if ( $change_duration && defined $increase ) {
		my $nice_increase = BIGSdb::Utils::commify($increase);
		my $class = $increase ? 'increase' : 'no_change';
		$buffer .= qq(<p class="dashboard_comment $class"><span class="fas fa-caret-up"></span> )
		  . qq($nice_increase [$change_duration]</p>);
	}
	$buffer .= $self->_add_element_watermark($element);
	return $buffer;
}

sub _get_field_element_content {
	my ( $self, $element ) = @_;
	my $buffer = $self->_get_colour_swatch($element);
	$buffer .= qq(<div class="title">$element->{'name'}</div>);
	if ( $element->{'visualisation_type'} eq 'specific values' ) {
		if ( ( $element->{'specific_value_display'} // q() ) eq 'number' ) {
			$buffer .= $self->_get_field_specific_value_number_content($element);
		}
	}
	$buffer .= q(</div>);
	return $buffer;
}

sub _get_field_specific_value_number_content {
	my ( $self, $element ) = @_;
	my $text_colour       = $element->{'main_text_colour'}  // SPECIFIC_FIELD_MAIN_TEXT_COLOUR;
	my $background_colour = $element->{'background_colour'} // SPECIFIC_FIELD_BACKGROUND_COLOUR;
	my $value_count       = @{ $element->{'specific_values'} };
	my $plural = $value_count == 1 ? q() : q(s);
	local $" = q(, );
	my $title =
	  $value_count <= ( $element->{'width'} // 1 ) * 2
	  ? qq(@{$element->{'specific_values'}})
	  : qq(<a title="@{$element->{'specific_values'}}">$value_count values selected</a>);
	my $buffer = qq(<div class="subtitle">$title</div>);
	my $count  = 0;
	my ( $increase, $change_duration );

	if ( $element->{'field'} =~ /^f_/x ) {
		( my $field = $element->{'field'} ) =~ s/^f_//x;
		my $att        = $self->{'xmlHandler'}->get_field_attributes($field);
		my $type       = $att->{'type'} // 'text';
		my $values     = $self->_filter_list( $type, $element->{'specific_values'} );
		my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( $type, $values );
		my $qry;
		my $view = $self->{'system'}->{'view'};
		if ( $type eq 'text' ) {
			$qry =
			  ( $att->{'multiple'} // q() ) eq 'yes'
			  ? "SELECT COUNT(*) FROM $view WHERE UPPER(${field}::text)::text[] && "
			  . "ARRAY(SELECT UPPER(value) FROM $temp_table)"
			  : "SELECT COUNT(*) FROM $view WHERE UPPER($field) IN (SELECT UPPER(value) FROM $temp_table)";
		} else {
			$qry =
			  ( $att->{'multiple'} // q() ) eq 'yes'
			  ? "SELECT COUNT(*) FROM $view WHERE $field && ARRAY(SELECT value FROM temp_list)"
			  : "SELECT COUNT(*) FROM $view WHERE $field IN (SELECT value FROM $temp_table)";
		}
		my @filters;
		push @filters, 'new_version IS NULL' if !$self->{'prefs'}->{'dashboard.include_old_versions'};
		local $" = ' AND ';
		$qry .= " AND @filters" if @filters;
		$count = $self->{'datastore'}->run_query($qry);
		if ( $element->{'change_duration'} && $count > 0 ) {
			my %allowed = map { $_ => 1 } qw(week month year);
			if ( $allowed{ $element->{'change_duration'} } ) {
				$change_duration = $element->{'change_duration'};
				$qry .= " AND date_entered <= now()-interval '1 $element->{'change_duration'}'";
				my $past_count = $self->{'datastore'}->run_query($qry);
				$increase = $count - ( $past_count // 0 );
			}
		}
	}
	$buffer .= $self->_get_big_number_content(
		{
			element           => $element,
			number            => $count,
			background_colour => $background_colour,
			text_colour       => $text_colour,
			change_duration   => $change_duration,
			increase          => $increase
		}
	);
	$buffer .= $self->_get_explore_link($element);
	return $buffer;
}

sub _filter_list {
	my ( $self, $type, $list ) = @_;
	my $values = [];
	foreach my $value (@$list) {
		if ( $type =~ /^int/x ) {
			push @$values, $value if BIGSdb::Utils::is_int($value);
			next;
		}
		if ( $type =~ /^bool/x ) {
			push @$values, $value if BIGSdb::Utils::is_bool($value);
			next;
		}
		if ( $type eq 'float' ) {
			push @$values, $value if BIGSdb::Utils::is_float($value);
			next;
		}
		if ( $type eq 'date' ) {
			push @$values, $value if BIGSdb::Utils::is_date($value);
			next;
		}
		push @$values, $value;
	}
	return $values;
}

sub _add_element_watermark {
	my ( $self, $element ) = @_;
	return q() if ( $element->{'watermark'} // q() ) !~ /^fa[r|s]\ fa\-/x;
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
	return $buffer;
}

sub _get_explore_link {
	my ( $self, $element ) = @_;
	my $buffer = q();
	if ( $element->{'url'} ) {
		$buffer .=
qq(<span data-id="$element->{'id'}" id="explore_$element-{'id'}" class="dashboard_explore_element fas fa-share">);
		if ( $element->{'url_text'} ) {
			$buffer .= qq(<span class="tooltip">$element->{'url_text'}</span>);
		}
		$buffer .= q(</span>);
	}
	return $buffer;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery noCache muuri modal fitty bigsdb.dashboard tooltips jQuery.fonticonpicker);
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
	  qw(layout fill_gaps enable_drag edit_elements remove_elements order elements default include_old_versions
	  layout_test visualisation_type specific_values
	);

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
	  map { $_ => 1 }
	  qw(fill_gaps enable_drag edit_elements remove_elements include_old_versions visualisation_type
	);
	if ( $boolean_attributes{$attribute} ) {
		my %allowed_values = map { $_ => 1 } ( 0, 1 );
		return if !$allowed_values{$value};
	}
	my $json = JSON->new->allow_nonref;
	my %json_attributes = map { $_ => 1 } qw(order elements);
	if ( $json_attributes{$attribute} ) {
		if ( length( $value > 5000 ) ) {
			$logger->error("$attribute value too long.");
			return;
		}
		eval { $json->decode($value); };
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
	my $layout_test          = $self->{'prefs'}->{'dashboard.layout_test'}          // 0;
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

	#TODO Remove for production.
	say q(<li style="border-width:3px;border-color:red;border-top-style:solid;)
	  . q(border-bottom-style:solid;margin-bottom:1em">);
	say $q->checkbox(
		-name    => 'layout_test',
		-id      => 'layout_test',
		-label   => 'Layout test',
		-checked => $layout_test ? 'checked' : undef
	);
	say q(</li>);
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
	$self->_print_field_selector;
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
	my $json = JSON->new->allow_nonref;
	if ($order) {
		eval { $json->encode($order); };
		if ($@) {
			$logger->error('Invalid order JSON');
			$order = q();
		}
	}
	my $elements      = $self->_get_elements;
	my $json_elements = $json->encode($elements);
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
