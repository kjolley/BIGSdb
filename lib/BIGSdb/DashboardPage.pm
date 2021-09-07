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
use BIGSdb::Constants qw(:design :interface :limits :dashboard COUNTRIES);
use Try::Tiny;
use List::Util qw( min max );
use JSON;
use POSIX qw(ceil);
use TOML qw(from_toml);
use Data::Dumper;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant {
	MAX_SEGMENTS                     => 20,
	COUNT_MAIN_TEXT_COLOUR           => '#404040',
	COUNT_BACKGROUND_COLOUR          => '#79cafb',
	GENOMES_MAIN_TEXT_COLOUR         => '#404040',
	GENOMES_BACKGROUND_COLOUR        => '#7ecc66',
	SPECIFIC_FIELD_MAIN_TEXT_COLOUR  => '#404040',
	SPECIFIC_FIELD_BACKGROUND_COLOUR => '#d9e1ff',
	GAUGE_BACKGROUND_COLOUR          => '#a0a0a0',
	GAUGE_FOREGROUND_COLOUR          => '#0000ff',
	CHART_COLOUR                     => '#1f77b4',
	TOP_VALUES                       => 5,
	MOBILE_WIDTH                     => 480
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
	my $max_width             = $self->{'config'}->{'page_max_width'} // PAGE_MAX_WIDTH;
	my $index_panel_max_width = $max_width - 250;
	my $title_max_width       = $max_width - 15;
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
	say qq(<div class="index_panel" style="max-width:${index_panel_max_width}px;min-width:65%">);
	$self->_print_main_section;
	say q(</div>);
	say q(<div class="menu_panel" style="width:250px">);
	$self->print_menu;
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
	$self->_print_size_controls( $id, $element );

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
	say q(</li><li id="top_value_selector" style="display:none">);
	say q(<label>Show top: </label>);
	my $values = $self->_get_field_values( $element->{'field'} );
	say $self->popup_menu(
		-name   => "${id}_top_values",
		-id     => "${id}_top_values",
		-values => [ 3, 5, 10 ],
		-labels => {
			3  => '3 values',
			5  => '5 values',
			10 => '10 values'
		},
		-default => $element->{'top_values'} // TOP_VALUES,
		-class => 'element_option',
	);
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
	if ( $field =~ /^e_/x ) {
		return 1;
	}
	if ( $field =~ /^eav_(.*)/x ) {
		my $attributes = $self->{'datastore'}->get_eav_field($1);
		return 1 if $attributes->{'option_list'};
		return 1 if $attributes->{'value_format'} eq 'boolean';
	}
	return;
}

sub _get_field_type {
	my ( $self, $element ) = @_;
	if ( !defined $element->{'field'} ) {
		$logger->error('No field defined');
		return;
	}
	if ( $element->{'field'} =~ /^f_(.*)$/x ) {
		my $field = $1;
		my $att   = $self->{'xmlHandler'}->get_field_attributes($field);
		return $att->{'type'};
	}
	if ( $element->{'field'} =~ /^e_(.*)\|\|(.*)/x ) {
		my $extended_isolate_field = $1;
		my $field                  = $2;
		my $att                    = $self->{'datastore'}->run_query(
			'SELECT * FROM isolate_field_extended_attributes WHERE (isolate_field,attribute)=(?,?)',
			[ $extended_isolate_field, $field ],
			{ fetch => 'row_hashref' }
		);
		return $att->{'value_format'};
	}
	if ( $element->{'field'} =~ /^eav_(.*)/x ) {
		my $att = $self->{'datastore'}->get_eav_field($1);
		return $att->{'value_format'};
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
	say qq(<label for="${id}_breakdown_display">Element: </label>);
	my $field_type = lc( $self->_get_field_type($element) );
	my @breakdown_charts =
	  $field_type eq 'date'
	  ? qw(bar cumulative doughnut pie)
	  : qw(bar doughnut pie top treemap);

	if ( $self->_field_has_optlist( $element->{'field'} ) ) {
		push @breakdown_charts, 'word';
	}
	if ( ( $element->{'field'} eq 'f_country' || $element->{'field'} eq 'e_country||continent' )
		&& $self->_has_country_optlist )
	{
		push @breakdown_charts, 'map';
	}
	say $q->popup_menu(
		-name    => "${id}_breakdown_display",
		-id      => "${id}_breakdown_display",
		-values  => [ 0, @breakdown_charts ],
		-labels  => { 0 => 'Select...', top => 'top values', map => 'world map', word => 'word cloud' },
		-class   => 'element_option',
		-default => $element->{'breakdown_display'}
	);
	say qq(</li><li id="specific_value_display_selector" style="display:$value_display">);
	say qq(<label for="${id}_specific_value_display">Element: </label>);
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

sub _has_country_optlist {
	my ($self) = @_;
	return if !$self->{'xmlHandler'}->is_field('country');
	my $thisfield = $self->{'xmlHandler'}->get_field_attributes('country');
	return $thisfield->{'optlist'} ? 1 : 0;
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
	if ( $field =~ /^e_(.*)\|\|(.*)/x ) {
		my $isolate_field = $1;
		my $attribute     = $2;
		return $self->{'datastore'}->run_query(
			'SELECT DISTINCT value FROM isolate_value_extended_attributes WHERE '
			  . '(isolate_field,attribute)=(?,?) ORDER BY value',
			[ $isolate_field, $attribute ],
			{ fetch => 'col_arrayref' }
		);
	}
	if ( $field =~ /^eav_(.*)/x ) {
		my $att = $self->{'datastore'}->get_eav_field($1);
		if ( $att->{'option_list'} ) {
			return [ split /;/x, $att->{'option_list'} ];
		}
		if ( $att->{'value_format'} eq 'boolean' ) {
			return [qw(true false)];
		}
	}
	return [];
}

sub _print_size_controls {
	my ( $self, $id, $element ) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left"><legend>Size</legend>);
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
	say q(</li><li>);
	say $q->checkbox(
		-name    => "${id}_hide_mobile",
		-id      => "${id}_hide_mobile",
		-label   => 'Hide on small screens',
		-class   => 'element_option',
		-checked => $element->{'hide_mobile'} // 1
	);
	say q(</li></ul>);
	say q(</fieldset>);
	return;
}

sub _print_change_duration_control {
	my ( $self, $id, $element, $options ) = @_;
	my $display = $options->{'display'} // 'inline';
	my $q = $self->{'cgi'};
	say qq(<fieldset id="change_duration_control" style="float:left;display:$display">)
	  . q(<legend>Rate of change</legend><ul>);
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
	say qq(<fieldset id="design_control" style="float:left;display:$display"><legend>Design</legend><ul>);
	$self->_print_colour_control( $id, $element );
	$self->_print_watermark_control( $id, $element );
	$self->_print_palette_control( $id, $element );
	say q(</ul></fieldset>);
	return;
}

sub _print_colour_control {
	my ( $self, $id, $element ) = @_;
	my $q = $self->{'cgi'};
	my $default = $element->{'main_text_colour'} // COUNT_MAIN_TEXT_COLOUR;
	say q(<li id="text_colour_control">);
	say qq(<input type="color" id="${id}_main_text_colour" value="$default" class="element_option colour_selector">);
	say qq(<label for="${id}_main_text_colour">Main text colour</label>);
	say q(</li><li>);
	$default = $element->{'background_colour'} // COUNT_BACKGROUND_COLOUR;
	say q(<li id="background_colour_control">);
	say qq(<input type="color" id="${id}_background_colour" value="$default" )
	  . q(class="element_option colour_selector">);
	say qq(<label for="${id}_background_colour">Main background</label>);
	say q(</li>);
	$default = $element->{'gauge_background_colour'} // GAUGE_BACKGROUND_COLOUR;
	say q(<li class="gauge_colour" style="display:none">);
	say qq(<input type="color" id="${id}_gauge_background_colour" value="$default" )
	  . q(class="element_option colour_selector">);
	say qq(<label for="${id}_gauge_background_colour">Gauge background</label>);
	say q(</li>);
	$default = $element->{'gauge_foreground_colour'} // GAUGE_FOREGROUND_COLOUR;
	say q(<li class="gauge_colour" style="display:none">);
	say qq(<input type="color" id="${id}_gauge_foreground_colour" value="$default" )
	  . q(class="element_option colour_selector">);
	say qq(<label for="${id}_gauge_foreground_colour">Gauge foreground</label>);
	say q(</li>);
	say qq(<li id="bar_colour_type" style="display:none"><label for="${id}_bar_colour_type">Value type:<br /></label>);
	say $q->radio_group(
		-name      => "${id}_bar_colour_type",
		-id        => "${id}_bar_colour_type",
		-class     => 'element_option',
		-values    => [qw(categorical continuous)],
		-default   => $element->{'bar_colour_type'} // 'categorical',
		-linebreak => 'true'
	);
	$default = $element->{'chart_colour'} // CHART_COLOUR;
	say q(<li id="chart_colour" style="display:none">);
	say qq(<input type="color" id="${id}_chart_colour" value="$default" ) . q(class="element_option colour_selector">);
	say qq(<label for="${id}_chart_colour">Chart colour</label>);
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
		{ 'fas fa-bong'            => 'risk factor:water pipe' },
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
	say qq(<li id="watermark_control"><label for="${id}_watermark">Watermark</label>);
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

sub _print_palette_control {
	my ( $self, $id, $element ) = @_;
	say q(<li id="palette_control" style="display:none">);
	say q(<div style="margin-top:-0.5em">);
	print qq(<span class="palette_item" id="palette_$_"></span>) for ( 0 .. 4 );
	say q(</div>);
	say qq(<label for="${id}_palette">Palette:</label>);
	my $values = [ sort keys %{ $self->_get_palettes } ];
	my $q      = $self->{'cgi'};
	say $q->popup_menu(
		-name    => "${id}_palette",
		-id      => "${id}_palette",
		-values  => $values,
		-class   => 'element_option palette_selector',
		-default => $element->{'palette'} // 'green'
	);
	say q(</li>);
	return;
}

sub _ajax_new {
	my ( $self, $id ) = @_;
	my $element = {
		id    => $id,
		order => $id,
	};
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
			url_text    => "Browse $self->{'system'}->{'labelfield'}s",
			hide_mobile => 0
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
			url_text    => 'Browse genomes',
			hide_mobile => 0
		}
	};
	my $q     = $self->{'cgi'};
	my $field = $q->param('field');
	if ( $default_elements->{$field} ) {
		$element = { %$element, %{ $default_elements->{$field} } };
	} else {
		my $display_field = $self->_get_display_field($field);
		$display_field =~ tr/_/ /;
		$element->{'name'}              = ucfirst($display_field);
		$element->{'field'}             = $field;
		$element->{'display'}           = 'setup';
		$element->{'change_duration'}   = 'week';
		$element->{'background_colour'} = SPECIFIC_FIELD_BACKGROUND_COLOUR;
		$element->{'main_text_colour'}  = SPECIFIC_FIELD_MAIN_TEXT_COLOUR;
		my %default_watermarks = (
			f_country              => 'fas fa-globe',
			'e_country||continent' => 'fas fa-globe',
			f_region               => 'fas fa-map',
			f_sex                  => 'fas fa-venus-mars',
			f_disease              => 'fas fa-notes-medical',
			f_year                 => 'far fa-calendar-alt'
		);

		if ( $default_watermarks{$field} ) {
			$element->{'watermark'} = $default_watermarks{$field};
		}
	}
	$element->{'width'}       //= 1;
	$element->{'height'}      //= 1;
	$element->{'hide_mobile'} //= 1;
	my $json = JSON->new->allow_nonref;
	say $json->encode(
		{
			element => $element,
			html    => $self->_get_element_html($element)
		}
	);
	return;
}

sub _get_display_field {
	my ( $self, $field ) = @_;
	my $display_field = $field;
	if ( $field =~ /^f_/x ) {
		$display_field =~ s/^f_//x;
	}
	if ( $field =~ /^e_/x ) {
		$display_field =~ s/^e_//x;
		$display_field =~ s/.*\|\|//x;
	}
	if ( $field =~ /^eav_/x ) {
		$display_field =~ s/^eav_//x;
	}
	if ( $field =~ /^s_(\d+)_(.*)$/x ) {
		my ( $scheme_id, $scheme_field ) = ( $1, $2 );
		my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
		my $desc        = $scheme_info->{'name'};
		my $set_id      = $self->get_set_id;
		if ($set_id) {
			my $set_name = $self->{'datastore'}
			  ->run_query( 'SELECT set_name FROM set_schemes WHERE set_id=? AND scheme_id=?', [ $set_id, $scheme_id ] );
			$desc = $set_name if defined $set_name;
		}
		$display_field = "$scheme_field ($desc)";
	}
	return $display_field;
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
			html => $self->_get_invalid_element_content
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
	say q(<div><div id="empty">);
	if ( !keys %$elements ) {
		say $self->_get_dashboard_empty_message;
	}
	say q(</div>);
	say q(<div id="dashboard" class="grid">);
	my %display_immediately = map { $_ => 1 } qw(setup record_count);
	my $already_loaded      = [];
	my $ajax_load           = [];
	foreach my $element ( sort { $elements->{$a}->{'order'} <=> $elements->{$b}->{'order'} } keys %$elements ) {
		my $display = $elements->{$element}->{'display'};
		next if !$display;
		if ( $display_immediately{$display} ) {
			say $self->_get_element_html( $elements->{$element} );
			push @$already_loaded, $element;
		} else {
			say $self->_get_element_html( $elements->{$element}, { by_ajax => 1 } );
			push @$ajax_load, $element;
		}
	}
	say q(</div></div>);
	if (@$ajax_load) {
		$self->_print_ajax_load_code( $already_loaded, $ajax_load );
	}
	return;
}

#TODO Try to fill width of panel rather than leaving large right-hand gutter.
sub _print_ajax_load_code {
	my ( $self, $already_loaded, $ajax_load_ids ) = @_;
	local $" = q(,);
	say q[<script>];
	say q[$(function () {];
	say << "JS";
	var element_ids = [@$ajax_load_ids];
	var already_loaded = [@$already_loaded];
	if (!window.running){
		window.running = true;
		\$.each(already_loaded, function(index,value){
			loadedElements[value] = 1;
		});
		\$.each(element_ids, function(index,value){
			if (\$("div#dashboard").width() < MOBILE_WIDTH && elements[value]['hide_mobile']){
				return;
			}
			\$.ajax({
		    	url:"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=dashboard&element=" + value
		    }).done(function(json){
		       	try {
		       	    \$("div#element_" + value + " > .item-content > .ajax_content").html(JSON.parse(json).html);
		       	    applyFormatting();
		       	    loadedElements[value] = 1;
		       	} catch (err) {
		       		console.log(err.message);
		       	} 	          	    
		    });			
		}); 
	}
JS
	say q[});];
	say q(</script>);
	return;
}

sub _get_elements {
	my ($self) = @_;
	if ( defined $self->{'prefs'}->{'elements'} ) {
		my $elements = {};
		my $json     = JSON->new->allow_nonref;
		eval { $elements = $json->decode( $self->{'prefs'}->{'elements'} ); };
		if (@$) {
			$logger->error('Invalid JSON in elements.');
		}
		return $elements;
	}
	return $self->_get_default_elements;
}

sub _get_default_elements {
	my ($self)   = @_;
	my $elements = {};
	my $i        = 1;
	my $default_dashboard;
	if ( -e "$self->{'dbase_config_dir'}/$self->{'instance'}/dashboard.toml" ) {
		my $toml = BIGSdb::Utils::slurp("$self->{'dbase_config_dir'}/$self->{'instance'}/dashboard.toml");
		my ( $data, $err ) = from_toml($$toml);
		if ( !$data->{'elements'} ) {
			$logger->error("Error parsing $self->{'dbase_config_dir'}/$self->{'instance'}/dashboard.toml: $err");
		} else {
			$default_dashboard = $data->{'elements'};
		}
	} elsif ( -e "$self->{'config_dir'}/dashboard.toml" ) {
		my $toml = BIGSdb::Utils::slurp("$self->{'config_dir'}/dashboard.toml");
		my ( $data, $err ) = from_toml($$toml);
		if ( !$data->{'elements'} ) {
			$logger->error("Error parsing $self->{'config_dir'}/dashboard.toml: $err");
		} else {
			$default_dashboard = $data->{'elements'};
		}
	} else {
		$default_dashboard = DEFAULT_DASHBOARD;
	}
	if ( !ref $default_dashboard || ref $default_dashboard ne 'ARRAY' ) {
		$logger->error('No default dashboard elements defined - using built-in default instead.');
		$default_dashboard = DEFAULT_DASHBOARD;
	}
	my $genome_size = $self->{'system'}->{'min_genome_size'} // $self->{'config'}->{'min_genome_size'}
	  // MIN_GENOME_SIZE;
	my $genomes_exists =
	  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM seqbin_stats WHERE total_length>?)', $genome_size );
	foreach my $element (@$default_dashboard) {
		next if $element->{'genomes'} && !$genomes_exists;
		next if $element->{'display'} eq 'field' && !$self->_field_exists( $element->{'field'} );
		$element->{'id'}    = $i;
		$element->{'order'} = $i;
		if ( $element->{'url_attributes'} ) {
			$element->{'url'} =
			  "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&$element->{'url_attributes'}";
			delete $element->{'url_attributes'};
			$element->{'post_data'}->{'db'} = $self->{'instance'};
		}
		$element->{'width'}  //= 1;
		$element->{'height'} //= 1;
		$elements->{$i} = $element;
		$i++;
	}
	return $elements;
}

sub _get_element_html {
	my ( $self, $element, $options ) = @_;
	my $mobile_class = $element->{'hide_mobile'} ? q( hide_mobile) : q();
	my $buffer       = qq(<div id="element_$element->{'id'}" data-id="$element->{'id'}" class="item">);
	my $width_class  = "dashboard_element_width$element->{'width'}";
	my $height_class = "dashboard_element_height$element->{'height'}";
	my $setup        = $element->{'display'} eq 'setup' ? q( style="display:block") : q();
	$buffer .= qq(<div class="item-content $width_class $height_class$mobile_class"$setup>);
	$buffer .= $self->_get_element_controls($element);
	$buffer .= q(<div class="ajax_content" style="overflow:hidden;height:100%;width:100%">);
	if ( $options->{'by_ajax'} ) {
		$buffer .= q(<span class="dashboard_wait_ajax fas fa-sync-alt fa-spin"></span>);
	} else {
		$buffer .= $self->_get_element_content($element);
	}
	$buffer .= q(</div></div></div>);
	return $buffer;
}

sub _get_element_content {
	my ( $self, $element ) = @_;
	my %display = (
		setup        => sub { $self->_get_setup_element_content($element) },
		record_count => sub { $self->_get_count_element_content($element) },
		field        => sub { $self->_get_field_element_content($element) }
	);
	if ( $display{ $element->{'display'} } ) {
		return $display{ $element->{'display'} }->();
	}
	return q();
}

sub _get_invalid_element_content {
	my ($self) = @_;
	my $buffer = $self->_get_colour_swatch( { background_colour => '#ffe7e6' } );
	$buffer .= q(<div class="title">Invalid element</div>);
	$buffer .= q(<p><span class="fas fa-exclamation-triangle" )
	  . q(style="color:#c44;font-size:3em;text-shadow: 3px 3px 3px #999;"></span></p>);
	$buffer .= q(<p>Refresh page.</p>);
	$buffer .= q(<script>window.location.reload(true);</script>);
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

sub _field_exists {
	my ( $self, $field ) = @_;
	if ( $field =~ /^f_(.*)$/x ) {
		my $field_name = $1;
		return $self->{'xmlHandler'}->is_field($field_name);
	}
	if ( $field =~ /^e_(.+)\|\|(.+)$/x ) {
		return $self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM isolate_field_extended_attributes WHERE (isolate_field,attribute)=(?,?))',
			[ $1, $2 ] );
	}
	return;
}

sub _get_filters {
	my ( $self, $options ) = @_;
	my $filters = [];
	push @$filters, 'new_version IS NULL' if !$self->{'prefs'}->{'include_old_versions'};
	if ( $options->{'genomes'} ) {
		my $genome_size = $self->{'system'}->{'min_genome_size'} // $self->{'config'}->{'min_genome_size'}
		  // MIN_GENOME_SIZE;
		push @$filters, "id IN (SELECT isolate_id FROM seqbin_stats WHERE total_length>=$genome_size)";
	}
	return $filters;
}

sub _get_count_element_content {
	my ( $self, $element ) = @_;
	my $buffer = $self->_get_colour_swatch($element);
	$buffer .= qq(<div class="title">$element->{'name'}</div>);
	my $text_colour = $element->{'main_text_colour'} // COUNT_MAIN_TEXT_COLOUR;
	my $count = $self->_get_total_record_count( { genomes => $element->{'genomes'} } );
	my ( $change_duration, $increase );
	if ( $element->{'change_duration'} && $count > 0 ) {
		my %allowed = map { $_ => 1 } qw(week month year);
		if ( $allowed{ $element->{'change_duration'} } ) {
			$change_duration = $element->{'change_duration'};
			my $filters = $self->_get_filters(
				{
					genomes => $element->{'genomes'}
				}
			);
			my $qry = "SELECT COUNT(*) FROM $self->{'system'}->{'view'} WHERE "
			  . "date_entered <= now()-interval '1 $element->{'change_duration'}'";
			local $" = ' AND ';
			$qry .= " AND @$filters" if @$filters;
			my $past_count = $self->{'datastore'}->run_query($qry);
			$increase = $count - ( $past_count // 0 );
		}
	}
	$buffer .= $self->_get_big_number_content(
		{
			element         => $element,
			number          => $count,
			text_colour     => $text_colour,
			change_duration => $change_duration,
			increase        => $increase
		}
	);
	$buffer .= $self->_add_element_watermark($element);
	$buffer .= $self->_get_explore_link($element);
	return $buffer;
}

sub _get_colour_swatch {
	my ( $self, $element ) = @_;
	if ( $element->{'background_colour'} ) {
		return qq[<div style="background-image:linear-gradient(#fff,#fff 10%,$element->{'background_colour'},]
		  . q[#fff 90%,#fff);height:100%;width:100%;position:absolute;z-index:-1"></div>];
	}
	return q();
}

sub _get_big_number_content {
	my ( $self, $args ) = @_;
	my ( $element, $number, $text_colour, $increase, $change_duration ) =
	  @{$args}{qw(element number text_colour increase change_duration)};
	my $nice_count = BIGSdb::Utils::commify($number);
	my $buffer     = q(<p style="margin:0 10px">)
	  . qq(<span class="dashboard_big_number" style="color:$text_colour">$nice_count</span></p>);
	if ( $change_duration && defined $increase ) {
		my $nice_increase = BIGSdb::Utils::commify($increase);
		my $class = $increase ? 'increase' : 'no_change';
		$buffer .= qq(<p class="dashboard_comment $class"><span class="fas fa-caret-up"></span> )
		  . qq($nice_increase [$change_duration]</p>);
	}
	return $buffer;
}

sub _get_field_element_content {
	my ( $self, $element ) = @_;
	$element->{'visualisation_type'} //= 'breakdown';
	my $buffer;
	if ( $element->{'visualisation_type'} eq 'specific values' ) {
		my $chart_type = $element->{'specific_value_display'} // q();
		my %methods = (
			number => sub { $self->_get_field_specific_value_number_content($element) },
			gauge  => sub { $self->_get_field_specific_value_gauge_content($element) }
		);
		if ( $methods{$chart_type} ) {
			$buffer .= $methods{$chart_type}->();
		}
	} elsif ( $element->{'visualisation_type'} eq 'breakdown' ) {
		my $chart_type = $element->{'breakdown_display'} // q();
		my %methods = (
			bar        => sub { $self->_get_field_breakdown_bar_content($element) },
			doughnut   => sub { $self->_get_field_breakdown_doughnut_content($element) },
			pie        => sub { $self->_get_field_breakdown_pie_content($element) },
			cumulative => sub { $self->_get_field_breakdown_cumulative_content($element) },
			word       => sub { $self->_get_field_breakdown_wordcloud_content($element) },
			top        => sub { $self->_get_field_breakdown_top_values_content($element) },
			treemap    => sub { $self->_get_field_breakdown_treemap_content($element) },
			map        => sub { $self->_get_field_breakdown_map_content($element) },
		);
		if ( $methods{$chart_type} ) {
			$buffer .= $methods{$chart_type}->();
		}
	}
	$buffer .= q(</div>);
	return $buffer;
}

sub _get_title {
	my ( $self, $element ) = @_;
	return qq(<div class="title">$element->{'name'}</div>);
}

sub _get_multiselect_field_subtitle {
	my ( $self, $element ) = @_;
	local $" = q(, );
	my $value_count = ref $element->{'specific_values'} ? @{ $element->{'specific_values'} } : 0;
	my $title =
	  $value_count <= ( $element->{'width'} // 1 ) * 2
	  ? qq(@{$element->{'specific_values'}})
	  : qq(<a title="@{$element->{'specific_values'}}">$value_count values selected</a>);
	return qq(<div class="subtitle">$title</div>);
}

sub _get_specific_field_value_counts {
	my ( $self, $element ) = @_;
	my $count = 0;
	my $data;
	if ( $element->{'field'} =~ /^f_/x ) {
		$data = $self->_get_provenance_field_counts($element);
	}
	if ( $element->{'field'} =~ /^e_/x ) {
		$data = $self->_get_extended_field_counts($element);
	}
	if ( $element->{'field'} =~ /^eav_/x ) {
		$data = $self->_get_eav_field_counts($element);
	}
	if ( $element->{'field'} =~ /^s_\d+_/x ) {
		$data = $self->_get_scheme_field_counts($element);
	}
	return $data;
}

sub _get_provenance_field_counts {
	my ( $self, $element ) = @_;
	( my $field = $element->{'field'} ) =~ s/^f_//x;
	my $att    = $self->{'xmlHandler'}->get_field_attributes($field);
	my $type   = $att->{'type'} // 'text';
	my $values = $self->_filter_list( $type, $element->{'specific_values'} );
	if ( ( $att->{'optlist'} // q() ) eq 'yes' ) {
		my $optlist = $self->{'xmlHandler'}->get_field_option_list($field);
		my %used = map { $_ => 1 } @$values;
		foreach my $value (@$values) {
			my $subvalues = $self->_get_sub_values( $value, $optlist );
			foreach my $subvalue (@$subvalues) {
				push @$values, $subvalue if !$used{$subvalue};
				$used{$subvalue} = 1;
			}
		}
	}
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
	my $filters = $self->_get_filters;
	local $" = ' AND ';
	$qry .= " AND @$filters" if @$filters;
	my $count = $self->{'datastore'}->run_query($qry);
	my $data = { count => $count };
	if ( $element->{'change_duration'} && $count > 0 ) {
		my %allowed = map { $_ => 1 } qw(week month year);
		if ( $allowed{ $element->{'change_duration'} } ) {
			$data->{'change_duration'} = $element->{'change_duration'};
			$qry .= " AND date_entered <= now()-interval '1 $element->{'change_duration'}'";
			my $past_count = $self->{'datastore'}->run_query($qry);
			$data->{'increase'} = $count - ( $past_count // 0 );
		}
	}
	return $data;
}

sub _get_extended_field_counts {
	my ( $self, $element ) = @_;
	my ( $field, $attribute );
	if ( $element->{'field'} =~ /^e_(.*)\|\|(.*)/x ) {
		$field     = $1;
		$attribute = $2;
	} else {
		$logger->error("Invalid extended attribute: $element->{'field'}");
		return {};
	}
	my $type       = $self->_get_field_type($element);
	my $values     = $self->_filter_list( $type, $element->{'specific_values'} );
	my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( $type, $values );
	my $view       = $self->{'system'}->{'view'};
	my $qry = "SELECT COUNT(*) FROM $view v JOIN isolate_value_extended_attributes a ON v.$field = a.field_value AND "
	  . "a.attribute=? WHERE a.value IN (SELECT value FROM $temp_table)";
	my $filters = $self->_get_filters;
	local $" = ' AND ';
	$qry .= " AND @$filters" if @$filters;
	my $count = $self->{'datastore'}->run_query( $qry, $attribute );
	my $data = { count => $count };

	if ( $element->{'change_duration'} && $count > 0 ) {
		my %allowed = map { $_ => 1 } qw(week month year);
		if ( $allowed{ $element->{'change_duration'} } ) {
			$data->{'change_duration'} = $element->{'change_duration'};
			$qry .= " AND date_entered <= now()-interval '1 $element->{'change_duration'}'";
			my $past_count = $self->{'datastore'}->run_query( $qry, $attribute );
			$data->{'increase'} = $count - ( $past_count // 0 );
		}
	}
	return $data;
}

sub _get_eav_field_counts {
	my ( $self, $element ) = @_;
	( my $field = $element->{'field'} ) =~ s/^eav_//x;
	my $att        = $self->{'datastore'}->get_eav_field($field);
	my $type       = $att->{'value_format'};
	my $values     = $self->_filter_list( $type, $element->{'specific_values'} );
	my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( $type, $values );
	my $view       = $self->{'system'}->{'view'};
	my $table      = $self->{'datastore'}->get_eav_field_table($field);
	my $qry        = "SELECT COUNT(*) FROM $table t JOIN $view v ON t.isolate_id = v.id AND t.field=? WHERE ";
	if ( $type eq 'text' ) {
		$qry .= "UPPER(t.value) IN (SELECT UPPER(value) FROM $temp_table)";
	} else {
		$qry .= "t.value IN (SELECT value FROM $temp_table)";
	}
	my $filters = $self->_get_filters;
	local $" = ' AND ';
	$qry .= " AND @$filters" if @$filters;
	my $count = $self->{'datastore'}->run_query( $qry, $field );
	my $data = { count => $count };
	if ( $element->{'change_duration'} && $count > 0 ) {
		my %allowed = map { $_ => 1 } qw(week month year);
		if ( $allowed{ $element->{'change_duration'} } ) {
			$data->{'change_duration'} = $element->{'change_duration'};
			$qry .= " AND v.date_entered <= now()-interval '1 $element->{'change_duration'}'";
			my $past_count = $self->{'datastore'}->run_query( $qry, $field );
			$data->{'increase'} = $count - ( $past_count // 0 );
		}
	}
	return $data;
}

sub _get_scheme_field_counts {
	my ( $self, $element ) = @_;
	if ( $element->{'field'} =~ /^s_(\d+)_(.*)/x ) {
		my ( $scheme_id, $field ) = ( $1, $2 );
		my $scheme_table      = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
		my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		my $type              = $scheme_field_info->{'type'};
		my $values            = $self->_filter_list( $type, $element->{'specific_values'} );
		my $temp_table        = $self->{'datastore'}->create_temp_list_table_from_array( $type, $values );

		#We include the DISTINCT clause below because an isolate may have more than 1 row in the scheme
		#cache table. This happens if the isolate has multiple STs (due to multiple allele hits).
		my $qry =
		  "SELECT COUNT(DISTINCT v.id) FROM $self->{'system'}->{'view'} v JOIN $scheme_table s ON v.id=s.id WHERE ";
		if ( $type eq 'text' ) {
			$qry .= "UPPER(s.$field) IN (SELECT UPPER(value) FROM $temp_table)";
		} else {
			$qry .= "s.$field IN (SELECT value FROM $temp_table)";
		}
		my $filters = $self->_get_filters;
		local $" = ' AND ';
		$qry .= " AND @$filters" if @$filters;
		my $count = $self->{'datastore'}->run_query($qry);
		my $data = { count => $count };
		if ( $element->{'change_duration'} && $count > 0 ) {
			my %allowed = map { $_ => 1 } qw(week month year);
			if ( $allowed{ $element->{'change_duration'} } ) {
				$data->{'change_duration'} = $element->{'change_duration'};
				$qry .= " AND v.date_entered <= now()-interval '1 $element->{'change_duration'}'";
				my $past_count = $self->{'datastore'}->run_query($qry);
				$data->{'increase'} = $count - ( $past_count // 0 );
			}
		}
		return $data;
	}
	$logger->error("Error in scheme field $element->{'field'}");
	return { count => 0 };
}

sub _get_field_breakdown_values {
	my ( $self, $element ) = @_;
	if ( $element->{'field'} =~ /^f_/x ) {
		( my $field = $element->{'field'} ) =~ s/^f_//x;
		return $self->_get_primary_metadata_breakdown_values($field);
	}
	if ( $element->{'field'} =~ /^e_(.*)\|\|(.*)/x ) {
		my ( $isolate_field, $attribute ) = ( $1, $2 );
		return $self->_get_extended_field_breakdown_values( $isolate_field, $attribute );
	}
	if ( $element->{'field'} =~ /^eav_(.*)/x ) {
		my $field = $1;
		return $self->_get_eav_field_breakdown_values($field);
	}
	if ( $element->{'field'} =~ /^s_(\d+)_(.*)/x ) {
		my ( $scheme_id, $field ) = ( $1, $2 );
		return $self->_get_scheme_field_breakdown_values( $scheme_id, $field );
	}
	return [];
}

sub _get_primary_metadata_breakdown_values {
	my ( $self, $field ) = @_;
	my $att     = $self->{'xmlHandler'}->get_field_attributes($field);
	my $qry     = "SELECT $field AS label,COUNT(*) AS value FROM $self->{'system'}->{'view'} v ";
	my $filters = $self->_get_filters;
	local $" = ' AND ';
	$qry .= " WHERE @$filters" if @$filters;
	$qry .= ' GROUP BY label ORDER BY ';
	if ( lc( $att->{'type'} ) =~ /^int/x || lc( $att->{'type'} ) eq 'date' || lc( $att->{'type'} ) eq 'float' ) {
		$qry .= $field;
	} else {
		$qry .= 'value DESC';
	}
	my $values = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	if ( ( $att->{'multiple'} // q() ) eq 'yes' ) {
		my %new_values;
		if ( ( $att->{'optlist'} // q() ) eq 'yes' ) {
			my $optlist = $self->{'xmlHandler'}->get_field_option_list($field);
			foreach my $value (@$values) {
				my $sorted_label = BIGSdb::Utils::arbitrary_order_list( $optlist, $value->{'label'} );
				local $" = q(; );
				my $new_label = qq(@$sorted_label);
				$new_values{$new_label} += $value->{'value'};
			}
		} else {
			foreach my $value (@$values) {
				if ( !defined $value->{'label'} ) {
					$value->{'label'} = ['No value'];
				}
				my @sorted_label =
				  $att->{'type'} ne 'text'
				  ? sort { $a <=> $b } @{ $value->{'label'} }
				  : sort { $a cmp $b } @{ $value->{'label'} };
				local $" = q(; );
				my $new_label = qq(@sorted_label);
				$new_values{$new_label} += $value->{'value'};
			}
		}
		my $new_return_list = [];
		foreach my $label ( sort { $new_values{$b} <=> $new_values{$a} || $a cmp $b } keys %new_values ) {
			push @$new_return_list,
			  {
				label => $label eq q() ? 'No value' : $label,
				value => $new_values{$label}
			  };
		}
		$values = $new_return_list;
	}
	if ( ( $att->{'userfield'} // q() ) eq 'yes' || $field eq 'sender' || $field eq 'curator' ) {
		$values = $self->_rewrite_user_field_values($values);
	}
	return $values;
}

sub _get_extended_field_breakdown_values {
	my ( $self, $field, $attribute ) = @_;
	my $qry =
	    "SELECT COALESCE(e.value,'No value') AS label,COUNT(*) AS value FROM $self->{'system'}->{'view'} v "
	  . "LEFT JOIN isolate_value_extended_attributes e ON v.$field=e.field_value "
	  . 'AND (e.isolate_field,e.attribute)=(?,?) ';
	my $filters = $self->_get_filters;
	local $" = ' AND ';
	$qry .= "AND @$filters" if @$filters;
	$qry .= ' GROUP BY label ORDER BY value DESC';
	my $values =
	  $self->{'datastore'}->run_query( $qry, [ $field, $attribute ], { fetch => 'all_arrayref', slice => {} } );
	return $values;
}

sub _get_eav_field_breakdown_values {
	my ( $self, $field ) = @_;
	my $att   = $self->{'datastore'}->get_eav_field($field);
	my $table = $self->{'datastore'}->get_eav_field_table($field);
	my $qry   = "SELECT t.value AS label,COUNT(*) AS value FROM $table t RIGHT JOIN $self->{'system'}->{'view'} v "
	  . 'ON t.isolate_id = v.id AND t.field=?';
	my $filters = $self->_get_filters;
	local $" = ' AND ';
	$qry .= " WHERE @$filters" if @$filters;
	$qry .= ' GROUP BY label ORDER BY ';

	if ( $att->{'value_format'} eq 'integer' || $att->{'value_format'} eq 'date' || $att->{'value_format'} eq 'float' )
	{
		$qry .= 'label';
	} else {
		$qry .= 'value DESC';
	}
	my $values = $self->{'datastore'}->run_query( $qry, $field, { fetch => 'all_arrayref', slice => {} } );
	return $values;
}

sub _get_scheme_field_breakdown_values {
	my ( $self, $scheme_id, $field ) = @_;
	my $scheme_table = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);

	#We include the DISTINCT clause below because an isolate may have more than 1 row in the scheme
	#cache table. This happens if the isolate has multiple STs (due to multiple allele hits).
	my $qry =
	    "SELECT s.$field AS label,COUNT(DISTINCT (v.id)) AS value FROM $self->{'system'}->{'view'} v "
	  . "JOIN $scheme_table s ON v.id=s.id";
	my $filters = $self->_get_filters;
	local $" = ' AND ';
	$qry .= " WHERE @$filters" if @$filters;
	$qry .= ' GROUP BY label ORDER BY value DESC';
	my $values =
	  $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	return $values;
}

sub _rewrite_user_field_values {
	my ( $self, $values ) = @_;
	my $new_values = [];
	foreach my $value (@$values) {
		my $label = $self->{'datastore'}->get_user_string( $value->{'label'}, { affiliation => 1 } );
		$label =~ s/\r?\n/ /gx;
		push @$new_values,
		  {
			label => $label,
			value => $value->{'value'}
		  };
	}
	return $new_values;
}

sub _get_sub_values {
	my ( $self, $value, $optlist ) = @_;
	return if !ref $optlist;
	return if $value =~ /\[.+\]$/x;
	my $subvalues;
	foreach my $option (@$optlist) {
		push @$subvalues, $option if $option =~ /^$value\ \[.+\]$/ix;
	}
	return $subvalues;
}

sub _get_field_specific_value_number_content {
	my ( $self, $element ) = @_;
	my $text_colour = $element->{'main_text_colour'} // SPECIFIC_FIELD_MAIN_TEXT_COLOUR;
	my $buffer = $self->_get_colour_swatch($element);
	$buffer .= $self->_get_title($element);
	$buffer .= $self->_get_multiselect_field_subtitle($element);
	my $data = $self->_get_specific_field_value_counts($element);
	$buffer .= $self->_get_big_number_content(
		{
			element         => $element,
			number          => $data->{'count'},
			text_colour     => $text_colour,
			change_duration => $data->{'change_duration'},
			increase        => $data->{'increase'}
		}
	);
	$buffer .= $self->_add_element_watermark($element);
	$buffer .= $self->_get_explore_link($element);
	return $buffer;
}

sub _get_total_record_count {
	my ( $self, $options ) = @_;
	my $qry     = "SELECT COUNT(*) FROM $self->{'system'}->{'view'}";
	my $filters = $self->_get_filters(
		{
			genomes => $options->{'genomes'}
		}
	);
	local $" = ' AND ';
	$qry .= " WHERE @$filters" if @$filters;
	my $count = $self->{'datastore'}->run_query($qry);
	return $count;
}

sub _get_field_specific_value_gauge_content {
	my ( $self, $element ) = @_;
	my $data   = $self->_get_specific_field_value_counts($element);
	my $total  = $self->_get_total_record_count;
	my $height = $element->{'height'} == 1 ? 100 : 200;
	if ( $element->{'width'} == 1 ) {
		$height = 80;
	}
	my $nice_count = BIGSdb::Utils::commify( $data->{'count'} );
	my $background = $element->{'gauge_background_colour'} // GAUGE_BACKGROUND_COLOUR;
	my $colour     = $element->{'gauge_foreground_colour'} // GAUGE_FOREGROUND_COLOUR;
	my $buffer     = $self->_get_title($element);
	$buffer .= $self->_get_multiselect_field_subtitle($element);
	$buffer .= qq(<div id="chart_$element->{'id'}"></div>);
	$buffer .= << "JS";
	<script>
	\$(function() {
		bb.generate({
			data: {
				columns: [
					["values", $data->{'count'}]
				],
				type: "gauge" 
			},
			legend: {
				show: false
			},
			color: {
				pattern: ["$colour"],
				threshold: {
					values: [0]
				}
			},
 			interaction: {
 				enabled: false
 			},
			gauge: {
				background:"$background",
				min: 0,
				max: $total,
				label: {
					format: function(value, ratio){
						return commify(value) + "\\n(" + (100 * ratio).toFixed(1) + "%)";
					},
					extents: function (value, isMax){
						return isMax ? commify($total) : 0;
					}
				}
			},
			size: {
				height: $height
			},
			bindto: "#chart_$element->{'id'}"
		});
	});
	</script>
JS
	$buffer .= $self->_get_explore_link($element);
	return $buffer;
}

sub _get_doughnut_pie_threshold {
	my ( $self, $data ) = @_;
	my $max_threshold = 0.10;    #Show segments that are >=10% of total
	my $total         = 0;
	$total += $_->{'value'} foreach @$data;
	return $max_threshold if !$total;
	my $running = 0;
	my $threshold;
	foreach my $value (@$data) {
		$running += $value->{'value'};

		#Show first third of segments if >=2%
		if ( $running >= ( $total / 3 ) && ( $value->{'value'} / $total ) >= 0.02 ) {
			$threshold = $value->{'value'} / $total;
			last;
		}
	}
	return $threshold >= $max_threshold ? $max_threshold : $threshold;
}

sub _get_doughnut_pie_dataset {
	my ( $self, $data ) = @_;
	my $dataset       = [];
	my $others        = 0;
	my $others_values = 0;
	my $value_count   = 0;
	foreach my $value (@$data) {
		$value->{'label'} //= 'No value';
		$value->{'label'} =~ s/"/\\"/gx;
		$value_count++;
		if ( $value_count >= MAX_SEGMENTS && @$data != MAX_SEGMENTS ) {
			$others += $value->{'value'};
			$others_values++;
		} else {
			push @$dataset, qq(                ["$value->{'label'}", $value->{'value'}]);
		}
	}
	my $others_label;
	if ($others) {
		$others_label = "Others ($others_values values)";
		push @$dataset, qq(                ["Others ($others_values values)", $others]);
	}
	return {
		others_label => $others_label // 'Others',
		dataset => $dataset
	};
}

sub _get_bar_dataset {
	my ( $self, $element ) = @_;
	my $labels    = [];
	my $values    = [];
	my $local_max = [];
	my $max       = 0;
	my $data      = $self->_get_field_breakdown_values($element);
	foreach my $value (@$data) {
		next if !defined $value->{'label'};
		$value->{'label'} =~ s/"/\\"/gx;
		push @$labels, $value->{'label'};
		push @$values, $value->{'value'};
		$max = $value->{'value'} if $value->{'value'} > $max;
	}

	#Calc local max
	my $cols_either_side = int( @$data / ( $element->{'width'} * 3 ) );
  POS: for my $i ( 0 .. @$values - 1 ) {
		my $lower = $i >= $cols_either_side ? $i - $cols_either_side : 0;
		for my $j ( $lower .. $i ) {
			next if $i == $j;
			next POS if $values->[$j] > $values->[$i];
		}
		my $upper = $i <= @$values - 1 - $cols_either_side ? $i + $cols_either_side : @$values - 1;
		for my $j ( $i .. $upper ) {
			next if $i == $j;
			next POS if $values->[$j] > $values->[$i];
		}
		push @$local_max, $i;
	}
	my $dataset = {
		count     => scalar @$data,
		max       => $max,
		labels    => $labels,
		values    => $values,
		local_max => $local_max
	};
	local $" = q(,);
	return $dataset;
}

sub _get_cumulative_dataset {
	my ( $self, $element ) = @_;
	my $dataset    = $self->_get_bar_dataset($element);
	my $cumulative = [];
	my $running    = 0;
	foreach my $value ( @{ $dataset->{'values'} } ) {
		$running += $value;
		push @$cumulative, $running;
	}
	$dataset->{'cumulative'} = $cumulative;
	return $dataset;
}

sub _get_field_breakdown_bar_content {
	my ( $self, $element ) = @_;
	my $dataset = $self->_get_bar_dataset($element);
	if ( !$dataset->{'count'} ) {
		return $self->_print_no_value_content($element);
	}
	my $height = ( $element->{'height'} * 150 ) - 25;
	local $" = q(",");
	my $cat_string = qq("@{$dataset->{'labels'}}");
	local $" = q(,);
	my $value_string     = qq(@{$dataset->{'values'}});
	my $local_max_string = qq(@{$dataset->{'local_max'}});
	my $bar_colour_type  = $element->{'bar_colour_type'} // 'categorical';
	my $chart_colour     = $element->{'chart_colour'} // CHART_COLOUR;
	my $buffer           = $self->_get_title($element);
	$buffer .= qq(<div id="chart_$element->{'id'}" class="pie" style="margin-top:-20px"></div>);
	local $" = q(,);
	$buffer .= << "JS";
	<script>
	\$(function() {
		var labels = [$cat_string];
		var values = [$value_string];
		var label_count = $dataset->{'count'};
		var max = $dataset->{'max'};
		var local_max = [$local_max_string];
		var bar_colour_type = "$bar_colour_type";
		bb.generate({
			data: {
				columns: [
					["values",@{$dataset->{'values'}}]
				],
				type: "bar",
				labels: {
					show: true,
					format: function (v,id,i,j){
						if (label_count<=6){
							return labels[i];
						}
						if (String(labels[i]).length<=3 
							&& label_count<=(10*$element->{'width'}) 
							&& i % (5-$element->{'width'})==0){
								return labels[i];
						}
						if (String(labels[i]).length <=6 && local_max.includes(i)){
							return labels[i];
						}
						if (v === max){
							return labels[i];
						}
					}
				},
				color: function(color,d){
					if (bar_colour_type === 'continuous'){
						return "$chart_colour";
					} else {
						return d3.schemeCategory10[d.index % 10];
					}
				}
			},
			axis: {
				x: {
					type: "category",
					categories: [$cat_string],
					tick: {
						show: false,
						text: {
							show: false
						}
					},
					padding: {
						right: 1
					}
				},
				y: {
					padding: {
						top: 15
					},
					tick: {
						culling: true
					} 
				}
			},
			size: {
				height: $height
			},
			legend: {
				show: false
			},
			tooltip: {
	    		position: function(data, width, height, element) {
	         		return {
	             		top: -20,
	             		left: 0
	         		}
	         	},
	         	format: {
	         		value: function(name, ratio, id){
	         			return d3.format(",")(name) 	         			  
	         		} 
	         	}
     		},
     		bar: {

     		},     		
			bindto: "#chart_$element->{'id'}"
		});
	});
	</script>
JS
	return $buffer;
}

sub _get_field_breakdown_cumulative_content {
	my ( $self, $element ) = @_;
	$element->{'width'}  //= 1;
	$element->{'height'} //= 3;
	my $dataset = $self->_get_cumulative_dataset($element);
	my $height  = ( $element->{'height'} * 150 ) - 25;
	my $ticks   = $element->{'width'};
	local $" = q(",");
	my $date_string = qq("@{$dataset->{'labels'}}");
	local $" = q(,);
	my $value_string = qq(@{$dataset->{'cumulative'}});
	my $chart_colour = $element->{'chart_colour'} // CHART_COLOUR;
	my $buffer       = $self->_get_title($element);
	$buffer .= qq(<div id="chart_$element->{'id'}" style="margin-top:-20px"></div>);
	local $" = q(,);
	$buffer .= << "JS";
	<script>
	\$(function() {
		var values = [$value_string];
		var days_span = Math.round(( Date.parse("$dataset->{'labels'}->[-1]") - Date.parse("$dataset->{'labels'}->[0]") ) / 86400000);
		var ms_span = 1000*60*60*24*days_span; 
		bb.generate({
			data: {
				x: "x",
				columns: [
					["x",$date_string ],
					["values",$value_string]
				],
				type: "line",
				color: function(color,d){
					return "$chart_colour";
				}
			},
			axis: {
				x: {
					type: "timeseries",
					tick: {
						count: $ticks,
						format: "%Y-%m-%d"
					},
					padding: {
						right: $element->{'width'} == 1 ? 0 : ms_span / (3*$element->{'width'})
					}
				},
				y: {
					tick: {
						culling: true
					} 
				}
			},
			point: {
				r: 1,
				focus: {
					expand: {
						r: 5
					}
				}	
			},
			size: {
				height: $height
			},
			legend: {
				show: false
			},
			tooltip: {
	    		position: function(data, width, height, element) {
	         		return {
	             		top: -20,
	             		left: 0
	         		}
	         	},
	         	format: {
	         		title: function(x) {
						return d3.timeFormat("%Y-%m-%d")(x);
	         		},
	         		value: function(name, ratio, id){
	         			return d3.format(",")(name) 	         			  
	         		} 
	         	}
     		}, 		
			bindto: "#chart_$element->{'id'}"
		});
	});
	</script>
JS
	return $buffer;
}

sub _print_no_value_content {
	my ( $self, $element ) = @_;
	my $buffer = $self->_get_colour_swatch( { background_colour => '#ccc' } );
	$buffer .= $self->_get_title($element);
	$buffer .=
	  q(<p><span class="fas fa-ban" ) . q(style="color:#44c;font-size:3em;text-shadow: 3px 3px 3px #999;"></span></p>);
	$buffer .= q(<p>No values in dataset.</p>);
	return $buffer;
}

sub _get_field_breakdown_doughnut_content {
	my ( $self, $element ) = @_;
	my $min_dimension = min( $element->{'height'}, $element->{'width'} ) // 1;
	my $height        = ( $min_dimension * 150 ) - 25;
	my $data          = $self->_get_field_breakdown_values($element);
	if ( !@$data ) {
		return $self->_print_no_value_content($element);
	}
	my $threshold    = $self->_get_doughnut_pie_threshold($data);
	my $dataset      = $self->_get_doughnut_pie_dataset($data);
	my $centre_title = q();
	my ( $margin_top, $label_show );
	my $buffer;
	if ( $min_dimension == 1 || length( $element->{'name'} ) > 50 ) {
		$buffer .= $self->_get_title($element);
		$margin_top = -20;
		$label_show = 'false';
	} else {
		$centre_title = $element->{'name'};
		$margin_top   = 20;
		$label_show   = 'true';
	}
	local $" = qq(,\n);
	my $others_label = $data->[-1] =~ /^Others/x ? $data->[-1] : 'Others';
	$buffer .= qq(<div id="chart_$element->{'id'}" class="doughnut" style="margin-top:${margin_top}px"></div>);
	$buffer .= << "JS";
	<script>
	\$(function() {
		bb.generate({
			data: {
				columns: [
					@{$dataset->{'dataset'}}
				],
				type: "donut",
				order: null,
				colors: {
					'$dataset->{'others_label'}': '#aaa'
				}
			},
			size: {
				height: $height
			},
			legend: {
				show: false
			},
			tooltip: {
	    		position: function(data, width, height, element) {
	         		return {
	             		top: -20,
	             		left: 0
	         		}
	         	},
	         	format: {
	         		value: function(name, ratio, id){
	         			return $height <= 125 
	         			  ? d3.format(",")(name) 
	         			  : d3.format(",")(name) + " (" + d3.format(".1f")(100 * ratio) + "%)";
	         		} 
	         	}
     		},
     		donut: {
     			title: "$centre_title",
     			label: {
     				show: $label_show,
     				format:  function(value, ratio, id){
     					var label = id.replace(" ","\\n");	
		         		return label;
	         		},
	         		threshold: $threshold	         		
     			}
     		},     		
			bindto: "#chart_$element->{'id'}"
		});
	});
	</script>
JS
	return $buffer;
}

sub _get_field_breakdown_pie_content {
	my ( $self, $element ) = @_;
	my $min_dimension = min( $element->{'height'}, $element->{'width'} ) // 1;
	my $height        = ( $min_dimension * 150 ) - 25;
	my $data          = $self->_get_field_breakdown_values($element);
	if ( !@$data ) {
		return $self->_print_no_value_content($element);
	}
	my $threshold  = $self->_get_doughnut_pie_threshold($data);
	my $dataset    = $self->_get_doughnut_pie_dataset($data);
	my $buffer     = $self->_get_title($element);
	my $label_show = $min_dimension == 1 || length( $element->{'name'} ) > 50 ? 'false' : 'true';
	local $" = qq(,\n);
	$buffer .= qq(<div id="chart_$element->{'id'}" class="pie" style="margin-top:-20px"></div>);
	$buffer .= << "JS";
	<script>
	\$(function() {
		bb.generate({
			data: {
				columns: [
					@{$dataset->{'dataset'}}
				],
				type: "pie",
				order: null,
				colors: {
					'$dataset->{'others_label'}': '#aaa'
				}
			},
			size: {
				height: $height
			},
			legend: {
				show: false
			},
			tooltip: {
	    		position: function(data, width, height, element) {
	         		return {
	             		top: -20,
	             		left: 0
	         		}
	         	},	         	
	         	format: {
	         		value: function(name, ratio, id){
	         			return $height <= 125 
	         			  ? d3.format(",")(name) 
	         			  : d3.format(",")(name) + " (" + d3.format(".1f")(100 * ratio) + "%)";
	         		}
	         	}
     		},
     		pie: {
     			label: {
     				show: $label_show,
     				format:  function(value, ratio, id){
     					var label = id.replace(" ","\\n");	
		         		return label;
	         		},
	         		threshold: $threshold
     			}
     		},     		
			bindto: "#chart_$element->{'id'}"
		});
	});
	</script>
JS
	return $buffer;
}

sub _get_field_breakdown_wordcloud_content {
	my ( $self, $element ) = @_;
	my $data = $self->_get_field_breakdown_values($element);
	if ( !@$data ) {
		return $self->_print_no_value_content($element);
	}
	my $largest      = 0;
	my $longest_term = 10 * min( $element->{'width'}, $element->{'height'}, 2 );
	my %ignore_word  = map { $_ => 1 } qw(and or);
	my %rename;
	foreach my $value (@$data) {
		next if !defined $value->{'label'} || $value->{'label'} eq 'No value';
		$largest = $value->{'value'} if $value->{'value'} > $largest;
	}
	foreach my $value (@$data) {
		if ( length $value->{'label'} > $longest_term && $value->{'value'} > 0.5 * $largest ) {
			if ( $value->{'label'} !~ /\s/x ) {
				$rename{ $value->{'label'} } = substr( $value->{'label'}, 0, $longest_term ) . '...';
			} else {
				my @words = split /\s/x, $value->{'label'};
				my $new_label;
				foreach my $word (@words) {
					if ( !length $new_label ) {
						$new_label .= $word;
						next;
					}
					if ( length($new_label) + length($word) + 1 > $longest_term ) {
						$new_label = $new_label;
						last;
					}
					$new_label = "$new_label $word";
				}
				$rename{ $value->{'label'} } = $new_label;
			}
		}
	}
	my $dataset  = [];
	my $min_size = 10;
	my $max_size = min( $element->{'width'}, $element->{'height'} ) * 0.5 + 15;
	foreach my $value (@$data) {
		next if !defined $value->{'label'} || $value->{'label'} eq 'No value';
		my $freq = $value->{'value'} / $largest;
		my $size = int( $max_size * $freq ) + $min_size;
		push @$dataset,
		  {
			text => $rename{ $value->{'label'} } // $value->{'label'},
			size => $size,
			colour => ( $value->{'value'} / $largest )
		  };
	}
	my $json   = JSON->new->allow_nonref;
	my $words  = $json->encode($dataset);
	my $height = ( $element->{'height'} * 150 ) - 25;
	my $width  = $element->{'width'} * 150;
	my $buffer = $self->_get_title($element);
	$buffer .= qq(<div id="chart_$element->{'id'}" style="margin-top:-20px"></div>);
	$buffer .= << "JS";
	<script>
	\$(function() {
		var layout = d3.layout.cloud()
	    .size([$width, $height])
	    .words($words)
	    .spiral('rectangular')
	    .rotate(function() { return ~~(Math.random() * 2) * 90; })
	    .fontSize(function(d) { return d.size; })
	    .on("end", draw);

		layout.start();
		
		function draw(words) {
		  d3.select("div#chart_" + $element->{'id'}).append("svg")
		      .attr("width", layout.size()[0])
		      .attr("height", layout.size()[1])
		    .append("g")
		      .attr("transform", "translate(" + layout.size()[0] / 2 + "," + layout.size()[1] / 2 + ")")
		    .selectAll("text")
		      .data(words)
		    .enter().append("text")
		      .style("font-size", function(d) { return d.size + "px"; })
		      .style("font-family","serif")   
			  .style("fill", function(d) { return d3.interpolateTurbo(d.colour);})
		      .attr("text-anchor", "middle")
		      .attr("transform", function(d) {
		        return "translate(" + [d.x, d.y] + ")rotate(" + d.rotate + ")";
		      })
		      .text(function(d) { return d.text; });
		}		
	});
	</script>
JS
	return $buffer;
}

sub _get_field_breakdown_top_values_content {
	my ( $self, $element ) = @_;
	my $data = $self->_get_field_breakdown_values($element);
	if ( !@$data ) {
		return $self->_print_no_value_content($element);
	}
	my $buffer = $self->_get_title($element);
	$element->{'top_values'} //= TOP_VALUES;
	my $style = $element->{'height'} == 1
	  && $element->{'top_values'} == 5 ? 'line-height:100%;font-size:0.9em' : q();
	$buffer .= qq(<div class="subtitle">Top $element->{'top_values'} values</div>);
	$buffer .= q(<div><table class="dashboard_table"><tr><th>Value</th><th>Frequency</th></tr>);
	my $td    = 1;
	my $count = 0;

	foreach my $value ( sort { $b->{'value'} <=> $a->{'value'} } @$data ) {
		next if !defined $value->{'label'} || $value->{'label'} eq 'No value';
		my $url = $self->_get_query_url( $element, $value->{'label'} );
		my $nice_value = BIGSdb::Utils::commify( $value->{'value'} );
		$count++;
		$buffer .= qq(<tr class="td$td" style="$style"><td><a href="$url">)
		  . qq($value->{'label'}</a></td><td>$nice_value</td></tr>);
		$td = $td == 1 ? 2 : 1;
		last if $count >= $element->{'top_values'};
	}
	$buffer .= q(</table></div>);
	return $buffer;
}

#Modified from https://www.d3-graph-gallery.com/graph/treemap_custom.html
sub _get_field_breakdown_treemap_content {
	my ( $self, $element ) = @_;
	my $data = $self->_get_field_breakdown_values($element);
	if ( !@$data ) {
		return $self->_print_no_value_content($element);
	}
	my $total = 0;
	foreach my $value (@$data) {
		if ( !defined $value->{'label'} ) {
			$value->{'label'} = 'No value';
		}
		$total += $value->{'value'};
	}
	my $min_dimension = min( $element->{'height'}, $element->{'width'} ) // 1;
	my $buffer =
	    qq(<div id="chart_$element->{'id'}_tooltip" style="position:absolute;top:0;left:0px;display:none;z-index:1">)
	  . q(<table class="bb-tooltip"><tbody><tr>)
	  . qq(<td><span id="chart_$element->{'id'}_background"></span>)
	  . qq(<span id="chart_$element->{'id'}_label" style="width:initial"></span></td>)
	  . qq(<td><span id="chart_$element->{'id'}_value" style="width:initial"></span>)
	  . qq(<span id="chart_$element->{'id'}_percent" style="width:initial"></span></td>)
	  . q(</tr></tbody></table></div>);
	$buffer .= $self->_get_title($element);
	my $height  = ( $element->{'height'} * 150 ) - 40;
	my $width   = $element->{'width'} * 150;
	my $json    = JSON->new->allow_nonref;
	my $dataset = $json->encode( { children => $data } );
	$buffer .= qq(<div id="chart_$element->{'id'}" class="treemap" style="margin-top:-20px"></div>);
	$buffer .= << "JS";
<script>
\$(function() {
	var data = $dataset;

	// set the dimensions and margins of the graph
	var margin = {top: 10, right: 10, bottom: 10, left: 10},
  	width = $width - margin.left - margin.right,
  	height = $height - margin.top - margin.bottom;

	// append the svg object to the body of the page
	var svg = d3.select("#chart_$element->{'id'}")
	.append("svg")
 		.attr("width", width + margin.left + margin.right)
		.attr("height", height + margin.top + margin.bottom)
	.append("g")
  		.attr("transform",
        	`translate(\${margin.left}, \${margin.top})`);

  	// Give the data to this cluster layout:
  	// Here the size of each leave is given in the 'value' field in input data
  	var root = d3.hierarchy(data).sum(function(d){ return d.value}) 

  	// Then d3.treemap computes the position of each element of the hierarchy
  	d3.treemap()
    	.size([width, height])
    	.paddingTop(5)
    	.paddingRight(0)
    	.paddingInner($min_dimension)      // Padding between each rectangle
    	(root)

  	// prepare a color scale
  	var color = d3.scaleOrdinal(d3.schemeCategory10)

  	// And a opacity scale
  	var opacity = d3.scaleLinear()
    	.domain([10, 30])
    	.range([.5,1])

  	// use this information to add rectangles:
  	svg
	    .selectAll("rect")
	    .data(root.leaves())
	    .join("rect")
	      	.attr('x', function (d) { return d.x0; })
	      	.attr('y', function (d) { return d.y0; })
	      	.attr('width', function (d) { return d.x1 - d.x0; })
	      	.attr('height', function (d) { return d.y1 - d.y0; })
	      	.style("stroke", "black")
	      	.style("fill", function(d){ return color(d.data.label)} )
	      	.style("opacity", function(d){ return opacity(d.data.value)})
			.on("mouseover touchstart", function(event,d){
	    		d3.select("#chart_$element->{'id'}_label").html([d.data.label]);
	    		d3.select("#chart_$element->{'id'}_value").html([d3.format(",d")(d.data.value)]);
	    		d3.select("#chart_$element->{'id'}_percent").html(
	    		$total 
	    		? ["(" + d3.format(".1f")((100 * d.data.value)/$total) + "%)"] 
	    		: [""]);
	    		d3.select("#chart_$element->{'id'}_background").style("background",color(d.data.label));
	    		d3.select("#chart_$element->{'id'}_tooltip").style("display","block");
	    	})
	    	.on("mouseout", function(){
	    		d3.select("#chart_$element->{'id'}_tooltip").style("display","none");
	    	});

  	
  	// and to add the text labels
  	svg
	    .selectAll("text")
	    .data(root.leaves())
	    .enter()
	    .append("text")
	    	.attr("x", function(d){ return d.x0+5})    // +10 to adjust position (more right)
	    	.attr("y", function(d){ return d.y0+20})    // +20 to adjust position (lower)
	    	.text(function(d){
	    		var cell_width = d.x1 - d.x0;    				
	    		if (
	    			$total 
	    			&& d.data.value/$total >= 0.05 
	    			&& String(d.data.label).length <= $min_dimension * d.data.value/$total * 100){
		    			return d.data.label
	    		}
	    		return ""; 
	    	})
	    	.attr("font-size", "12px")
	    	.attr("fill", "white")
	    	.style("pointer-events","none")
	    	.call(wrap, 100)
	    	
			function wrap(text, width) {
		    	text.each(function () {
			        var text = d3.select(this),
			            words = text.text().split(/\\s+/).reverse(),
			            word,
			            line = [],
			            lineNumber = 0,
			            lineHeight = 1.1, // ems
			            x = text.attr("x"),
			            y = text.attr("y"),
			            dy = 0, //parseFloat(text.attr("dy")),
			            tspan = text.text(null)
			                        .append("tspan")
			                        .attr("x", x)
			                        .attr("y", y)
			                        .attr("dy", dy + "em");
			        while (word = words.pop()) {
			            line.push(word);
			            tspan.text(line.join(" "));
			            if (tspan.node().getComputedTextLength() > width) {
			                line.pop();
			                tspan.text(line.join(" "));
			                line = [word];
			                tspan = text.append("tspan")
			                            .attr("x", x)
			                            .attr("y", y)
			                            .attr("dy", ++lineNumber * lineHeight + dy + "em")
			                            .text(word);
			            }
			        }
		    	});
			} 
			
			//Hide legend when touching outside area.
			d3.select("#element_$element->{'id'}").on("touchstart", function(event,d){
				if (event.target.nodeName !== 'rect'){
					d3.select("#chart_$element->{'id'}_tooltip").style("display","none");
				}
			});  	
	});    	    	
	</script>
JS
	return $buffer;
}

sub _get_field_breakdown_map_content {
	my ( $self, $element ) = @_;
	my $data = $self->_get_field_breakdown_values($element);
	if ( !@$data ) {
		return $self->_print_no_value_content($element);
	}
	my $countries = COUNTRIES;
	foreach my $value (@$data) {
		if ( $element->{'field'} eq 'f_country' ) {
			$value->{'iso3'} = $countries->{ $value->{'label'} }->{'iso3'} // q(XXX);
		} else {
			$value->{'continent'} = $value->{'label'} // q(XXX);
			$value->{'continent'} =~ s/\s/_/gx;
		}
	}
	my $buffer =
	    qq(<div id="chart_$element->{'id'}_tooltip" style="position:absolute;top:0;left:0px;display:none;z-index:1">)
	  . q(<table class="bb-tooltip"><tbody><tr>)
	  . qq(<td><span id="chart_$element->{'id'}_background"></span>)
	  . qq(<span id="chart_$element->{'id'}_label" style="width:initial"></span></td>)
	  . qq(<td><span id="chart_$element->{'id'}_value" style="width:initial"></span>)
	  . qq(<span id="chart_$element->{'id'}_percent" style="width:initial"></span></td>)
	  . q(</tr></tbody></table></div>);
	$buffer .= $self->_get_title($element);
	my $unit_id = $element->{'field'} eq 'f_country' ? 'iso3'                       : 'continent';
	my $units   = $element->{'field'} eq 'f_country' ? 'units'                      : 'continents';
	my $merge   = $element->{'field'} eq 'f_country' ? q(data = merge_terms(data);) : q();
	my %max_width = (
		1 => 200,
		2 => 500,
		3 => 600
	);
	my $width = min( $element->{'width'} * 150, $max_width{ $element->{'height'} } );
	my $top_margin = $element->{'height'} == 1 && $element->{'width'} == 1 ? '-10px' : '-10px';
	my $json       = JSON->new->allow_nonref;
	my $dataset    = $json->encode($data);
	my $geo_file =
	  $element->{'field'} eq 'f_country'
	  ? '/javascript/topojson/countries.json'
	  : '/javascript/topojson/continents.json';
	my $freq_key = $element->{'field'} eq 'f_country' ? 'iso3' : 'name';
	my $palettes = $self->_get_palettes;
	$element->{'palette'} //= 'green';
	my $palette = $palettes->{ $element->{'palette'} };
	$buffer .= qq(<div id="chart_$element->{'id'}" class="map" style="margin-top:$top_margin"></div>);
	$buffer .= << "JS";
<script>
\$(function() {
	var colours = $palette;
	var data = $dataset;
	$merge
	var freqs = data.reduce(function(map, obj){
		map[obj.label] = obj.value;
		return map;
	}, {});
	var range = get_range(data);
	var vw = \$("#chart_$element->{'id'}").width();
	var vw_unit = Math.max(Math.floor(vw/150),1);
	var width = $element->{'width'} > vw_unit ? vw_unit : $element->{'width'};
	var legend_pos = {
		1: {
			1: {x:0, y:0},
			2: {x:0, y:0},
			3: {x:0, y:0}
		},
		2: {
			1: {x:-30, y:0},
			2: {x:0, y:50},
			3: {x:0, y:50}
		},
		3: {
			1: {x: -50, y:0},
			2: {x: 20, y:120},
			3: {x: 20, y:120}
		},
		4: {
			1: {x:-50, y:0},
			2: {x:0, y:140},
			3: {x:50, y:160}
		}
	};
	var f = d3.format(",d");
	var	map = d3.geomap.choropleth()
		.geofile("$geo_file")
		.width(Math.min($width,document.documentElement.clientWidth-30))
		.colors(colours)
		.column('value')
		.format(d3.format(",d"))
		.legend(width == 1 ? false : {width:50,height:100})
		.domain([ 0, range.recommended ])
		.valueScale(d3.scaleQuantize)
		.unitId("$unit_id")
		.units("$units")
		.postUpdate(function(){
			var legend = d3.select("#chart_$element->{'id'} .legend");
			legend.attr("transform","translate(" + 
				legend_pos[width][$element->{'height'}]['x'] + "," + 
				legend_pos[width][$element->{'height'}]['y'] + ")");
			d3.selectAll("#chart_$element->{'id'} path.unit").selectAll("title").remove();
			d3.selectAll("#chart_$element->{'id'} path.unit")
				.on("mouseover touchstart", function(event,d){				
					d3.select("#chart_$element->{'id'}_label").html([d.properties.name]);
					var value = freqs[d.properties.$freq_key] == null ? 0 : f(freqs[d.properties.$freq_key]);
					d3.select("#chart_$element->{'id'}_value").html([value]);
					var colour_index = Math.floor((5 * freqs[d.properties.$freq_key] / range.recommended),1);
					if (isNaN(colour_index)){
						d3.select("#chart_$element->{'id'}_background").style("background","#ccc");
					} else {
						if (colour_index > 4){
							colour_index = 4;
						}
						d3.select("#chart_$element->{'id'}_background").style("background",colours[colour_index]);
					}
					d3.select("#chart_$element->{'id'}_tooltip").style("display","block");
				})
				.on("mouseout", function(){
					d3.select("#chart_$element->{'id'}_tooltip").style("display","none");
	    		});
		});
	var selection = d3.select("#chart_$element->{'id'}").datum(data);
	map.draw(selection);
}); 

function merge_terms(data){
	var iso3_counts = {};
	for (var i = 0; i < data.length; i++) { 
		if (typeof iso3_counts[data[i].iso3] == 'undefined'){
			iso3_counts[data[i].iso3] = data[i].value;
		} else {
			iso3_counts[data[i].iso3] += data[i].value;
		}
	}
	var merged = [];
	var iso3 = Object.keys(iso3_counts);
	for (var i=0; i < iso3.length; i++){
		merged.push({label:iso3[i], iso3: iso3[i], value: iso3_counts[iso3[i]]});
	}
	return merged;
}

// Choose recommended value so that ~5% of records are in top fifth (25% if <= 10 records).
function get_range(data) {
	var records = data.length;
	var percent_in_top_fifth = records > 10 ? 0.05 : 0.25;
	var target = parseInt(percent_in_top_fifth * records);
	var multiplier = 10;
	var max;
	var recommended;
	var options = [];
	var finish;	
	while (true){
		var test = [1,2,5];
		for (var i = 0; i < test.length; i++) { 
			max = test[i] * multiplier;
			options.push(max);
			if (recommended && options.length >= 5){
				finish = 1;
				break;
			}
			var top_division_start = max * 4 / 5;
			var in_top_fifth = 0;
			for (var j = 0; j < data.length; j++) { 
				if (data[j].value >= top_division_start){
					in_top_fifth++;
				}
			}
			if (in_top_fifth <= target && !recommended){
				recommended = max;
			}
		}
		if (finish){
			break;
		}
		multiplier = multiplier * 10;
		if (max > 10000000){
			if (!recommended){
				recommended = max;
			}
			break;
		}
	}
	return {
		recommended : recommended,
		options: options.slice(-5)
	}
}  	    	
</script>
JS
	return $buffer;
}

sub _get_palettes {
	my ($self) = @_;
	return {
		blue                  => 'colorbrewer.Blues[5]',
		green                 => 'colorbrewer.Greens[5]',
		purple                => 'colorbrewer.Purples[5]',
		orange                => 'colorbrewer.Oranges[5]',
		red                   => 'colorbrewer.Reds[5]',
		'blue/green'          => 'colorbrewer.BuGn[5]',
		'blue/purple'         => 'colorbrewer.BuPu[5]',
		'green/blue'          => 'colorbrewer.GnBu[5]',
		'orange/red'          => 'colorbrewer.OrRd[5]',
		'purple/blue'         => 'colorbrewer.PuBu[5]',
		'purple/blue/green'   => 'colorbrewer.PuBuGn[5]',
		'purple/red'          => 'colorbrewer.PuRd[5]',
		'red/purple'          => 'colorbrewer.RdPu[5]',
		'yellow/green'        => 'colorbrewer.YlGn[5]',
		'yellow/green/blue'   => 'colorbrewer.YlGnBu[5]',
		'yellow/orange/brown' => 'colorbrewer.YlOrBr[5]',
		'yellow/orange/red'   => 'colorbrewer.YlOrRd[5]',
	};
}

sub _get_query_url {
	my ( $self, $element, $value ) = @_;
	my $url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query";
	$value =~ s/\ /\%20/gx;
	if ( $element->{'field'} =~ /^[f|e]_/x ) {
		$url .= "&prov_field1=$element->{'field'}&prov_value1=$value&submit=1";
	}
	if ( $element->{'field'} =~ /^eav_/x ) {
		$url .= "&phenotypic_field1=$element->{'field'}&phenotypic_value1=$value&submit=1";
	}
	if ( $element->{'field'} =~ /^s_\d+_/x ) {
		$url .= "&designation_field1=$element->{'field'}&designation_value1=$value&submit=1";
	}
	if ( $self->{'prefs'}->{'include_old_versions'} ) {
		$url .= '&include_old=on';
	}
	return $url;
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
	my $display = $self->{'prefs'}->{'remove_elements'} ? 'inline' : 'none';
	my $buffer =
	    qq(<span data-id="$id" id="remove_$id" )
	  . qq(class="dashboard_remove_element far fa-trash-alt" style="display:$display"></span>)
	  . qq(<span data-id="$id" id="wait_$id" class="dashboard_wait fas fa-sync-alt )
	  . q(fa-spin" style="display:none"></span>);
	$display = ( $self->{'prefs'}->{'edit_elements'} // 1 ) ? 'inline' : 'none';
	$buffer .=
	    qq(<span data-id="$id" id="control_$id" class="dashboard_edit_element fas fa-sliders-h" )
	  . qq(style="display:$display"></span>);
	return $buffer;
}

sub _get_explore_link {
	my ( $self, $element ) = @_;
	my $buffer = q();
	if ( $element->{'url'} ) {
		$buffer .= qq(<span data-id="$element->{'id'}" id="explore_$element->{'id'}" )
		  . q(class="dashboard_explore_element fas fa-share">);
		if ( $element->{'url_text'} ) {
			$buffer .= qq(<span class="tooltip">$element->{'url_text'}</span>);
		}
		$buffer .= q(</span>);
	}
	return $buffer;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1
	  foreach
	  qw (jQuery noCache muuri modal fitty bigsdb.dashboard tooltips jQuery.fonticonpicker billboard d3.layout.cloud);
	$self->{'geomap'} = 1 if $self->_has_country_optlist;
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
		$self->{'prefstore'}->delete_dashboard_settings( $guid, $self->{'instance'} ) if $guid;
	}
	$self->{'prefs'} = $self->{'prefstore'}->get_primary_dashboard_prefs( $guid, $self->{'instance'} );
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
	);

	if ( !$allowed_attributes{$attribute} ) {
		$logger->error("Invalid attribute - $attribute");
		return;
	}
	if ( $attribute eq 'layout' ) {
		my %allowed_values = map { $_ => 1 } ( 'left-top', 'right-top', 'left-bottom', 'right-bottom' );
		return if !$allowed_values{$value};
	}
	my %boolean_attributes =
	  map { $_ => 1 }
	  qw(fill_gaps enable_drag edit_elements remove_elements include_old_versions
	);
	if ( $boolean_attributes{$attribute} ) {
		my %allowed_values = map { $_ => 1 } ( 0, 1 );
		return if !$allowed_values{$value};
	}
	my $json = JSON->new->allow_nonref;
	my %json_attributes = map { $_ => 1 } qw(order elements);
	if ( $json_attributes{$attribute} ) {
		if ( length($value) > 5000 ) {
			$logger->error("$attribute value too long.");
			return;
		}
		eval { $json->decode($value); };
		if ($@) {
			$logger->error("Invalid JSON for $attribute attribute");
		}
	}
	my $guid = $self->get_guid;
	$self->{'prefstore'}->set_primary_dashboard_pref( $guid, $self->{'instance'}, $attribute, $value );
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
	my $layout               = $self->{'prefs'}->{'layout'}               // 'left-top';
	my $fill_gaps            = $self->{'prefs'}->{'fill_gaps'}            // 1;
	my $enable_drag          = $self->{'prefs'}->{'enable_drag'}          // 0;
	my $edit_elements        = $self->{'prefs'}->{'edit_elements'}        // 1;
	my $remove_elements      = $self->{'prefs'}->{'remove_elements'}      // 0;
	my $include_old_versions = $self->{'prefs'}->{'include_old_versions'} // 0;
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
			scheme_fields       => 1,
			extended_attributes => 1,
			eav_fields          => 1,
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
	my $order = $self->{'prefs'}->{'order'} // q();
	my $enable_drag = $self->{'prefs'}->{'enable_drag'} ? 'true' : 'false';
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
var loadedElements = {};

END
	return $buffer;
}
1;
