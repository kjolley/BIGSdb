#Written by Keith Jolley
#Copyright (c) 2021-2022, University of Oxford
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
use BIGSdb::Constants qw(:design :interface :limits :dashboard COUNTRIES LOCUS_PATTERN);
use Try::Tiny;
use List::Util qw( min max );
use JSON;
use POSIX qw(ceil);
use TOML qw(from_toml);
use Storable qw(dclone);
use Data::Dumper;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant {
	MAX_SEGMENTS                     => 20,
	COUNT_MAIN_TEXT_COLOUR           => '#404040',
	COUNT_BACKGROUND_COLOUR          => '#79cafb',
	HEADER_TEXT_COLOUR               => '#ffffff',
	HEADER_BACKGROUND_COLOUR         => '#729fcf',
	GENOMES_MAIN_TEXT_COLOUR         => '#404040',
	GENOMES_BACKGROUND_COLOUR        => '#7ecc66',
	SPECIFIC_FIELD_MAIN_TEXT_COLOUR  => '#404040',
	SPECIFIC_FIELD_BACKGROUND_COLOUR => '#d9e1ff',
	GAUGE_BACKGROUND_COLOUR          => '#a0a0a0',
	GAUGE_FOREGROUND_COLOUR          => '#0000ff',
	CHART_COLOUR                     => '#1f77b4',
	TOP_VALUES                       => 5,
	DASHBOARD_LIMIT                  => 20
};

sub print_content {
	my ($self) = @_;
	$self->{'view'} = $self->{'system'}->{'view'};
	my $desc = $self->get_db_description( { formatted => 1 } );
	if ( ( $self->{'system'}->{'dbtype'} // q() ) ne 'isolates' ) {
		say qq(<h1>$desc database</h1>);
		$self->print_bad_status(
			{
				message => q(Dashboards can only be displayed for isolate databases.),
			}
		);
		return;
	}
	my $q            = $self->{'cgi'};
	my %ajax_methods = (
		updateDashboard     => '_update_dashboard_prefs',
		updateDashboardName => '_update_dashboard_name',
		updateGeneralPrefs  => '_update_general_prefs',
		newDashboard        => '_ajax_new_dashboard',
		control             => '_ajax_controls',
		new                 => '_ajax_new',
		element             => '_ajax_get',
		seqbin_range        => '_ajax_get_seqbin_range',
		setActiveDashboard  => '_ajax_set_active'
	);
	foreach my $method ( sort keys %ajax_methods ) {
		my $sub = $ajax_methods{$method};
		if ( defined $q->param($method) ) {
			$self->$sub(
				scalar $q->param($method),
				{
					qry_file       => scalar $q->param('qry_file'),
					list_file      => scalar $q->param('list_file'),
					list_attribute => scalar $q->param('list_attribute')
				}
			);
			return;
		}
	}
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
	say qq(<div id="dashboard_panel" class="dashboard_panel" style="max-width:${index_panel_max_width}px">);
	$self->print_dashboard( { filter_display => 1 } );
	say q(</div>);
	say q(<div class="menu_panel" style="width:250px">);
	$self->print_menu( { dashboard => 1 } );
	say q(</div>);
	say q(</div>);
	say q(</div>);
	say q(</div>);
	$self->print_modify_dashboard_fieldset;
	return;
}

sub _ajax_controls {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
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
		seqbin_size => sub {
			$self->_print_design_control( $id, $element );
			$self->_print_seqbin_filter_control( $id, $element );
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

sub _ajax_get_seqbin_range {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self) = @_;
	my $range  = $self->_get_seqbin_standard_range;
	my $json   = JSON->new->allow_nonref;
	say $json->encode(
		{
			range => $range
		}
	);
	return;
}

sub _ajax_new_dashboard {       ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self) = @_;
	my $guid = $self->get_guid;
	$self->{'dashboard_id'} =
	  $self->{'prefstore'}->initiate_new_dashboard( $guid, $self->{'instance'}, $self->{'dashboard_type'}, 0 );
	if ( !defined $self->{'dashboard_id'} ) {
		$logger->error('Dashboard pref could not be initiated.');
	}
	my $dashboard_name = $self->{'prefstore'}->get_dashboard_name( $self->{'dashboard_id'} );
	my $json           = JSON->new->allow_nonref;
	say $json->encode(
		{
			dashboard_name => $dashboard_name
		}
	);
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
	if ( $element->{'display'} eq 'field' && !defined $element->{'field'} ) {
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
	if ( $element->{'field'} =~ /^s_(\d+)_(.*)/x ) {
		my $att = $self->{'datastore'}->get_scheme_field_info( $1, $2 );
		return $att->{'type'};
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
		&& $self->has_country_optlist )
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

sub has_country_optlist {
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
	say q(<li id="text_colour_control" style="display:none">);
	say qq(<input type="color" id="${id}_main_text_colour" value="$default" class="element_option colour_selector">);
	say qq(<label for="${id}_main_text_colour">Main text colour</label>);
	say q(</li><li>);
	$default = $element->{'background_colour'} // COUNT_BACKGROUND_COLOUR;
	say q(<li id="background_colour_control" style="display:none">);
	say qq(<input type="color" id="${id}_background_colour" value="$default" )
	  . q(class="element_option colour_selector">);
	say qq(<label for="${id}_background_colour">Main background</label>);
	say q(</li>);
	$default = $element->{'header_text_colour'} // HEADER_TEXT_COLOUR;
	say q(<li id="header_colour_control" style="display:none">);
	say qq(<input type="color" id="${id}_header_text_colour" value="$default" class="element_option colour_selector">);
	say qq(<label for="${id}_header_text_colour">Header text colour</label>);
	say q(</li><li>);
	$default = $element->{'header_background_colour'} // HEADER_BACKGROUND_COLOUR;
	say q(<li id="header_background_colour_control" style="display:none">);
	say qq(<input type="color" id="${id}_header_background_colour" value="$default" )
	  . q(class="element_option colour_selector">);
	say qq(<label for="${id}_header_background_colour">Header background</label>);
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
	say qq(<input type="color" id="${id}_chart_colour" value="$default" class="element_option colour_selector">);
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

sub _print_seqbin_filter_control {
	my ( $self, $id, $element ) = @_;
	my $q = $self->{'cgi'};
	my $max =
	  $self->{'datastore'}->run_query(
		"SELECT MAX(total_length) FROM seqbin_stats s JOIN $self->{'system'}->{'view'} v ON s.isolate_id=v.id");
	return if !$max;
	my $max_kb      = int( $max / 1000_000 );
	my $reset_range = 'inline';
	if ( !defined $element->{'min'} && !defined $element->{'max'} ) {
		my $range = $self->_get_seqbin_standard_range;
		$element->{'min'} //= $range->{'min'};
		$element->{'max'} //= $range->{'max'};
		$reset_range = 'none';
	}
	my $min_value = $element->{'min'} // 0;
	my $max_value = $element->{'max'} // $max_kb;
	say q(<fieldset id="seqbin_filter_control" style="float:left"><legend>Filter</legend>);
	say q(<p>Size: <span id="seqbin_min"></span> - <span id="seqbin_max"></span> Mbp</p>);
	say q(<div id="seqbin_range_slider" style="width:150px"></div>);
	say qq(<p style="margin-top:1em"><a id="reset_seqbin_range" onclick="resetSeqbinRange($element->{'id'})" )
	  . qq(class="small_reset" style="display:$reset_range;white-space:nowrap">Reset range</a></p>);
	say q(</fieldset>);
	say << "JS";
	
<script>
\$(function() {
	let max=$max_kb;
	\$("#seqbin_min").html($min_value);
	\$("#seqbin_max").html($max_value);
	\$("#seqbin_range_slider").slider({
      range: true,
      min: 0,
      max: $max_kb,
      step: 0.1,
      values: [ $min_value, $max_value ],
      slide: function( event, ui ) {
          \$("#seqbin_min").html(ui.values[0]);
          \$("#seqbin_max").html(ui.values[1]);         
      },
      change: function (event, ui){
      	  if(event.originalEvent){
	          elements[$element->{'id'}]['min'] = ui.values[0];
	          elements[$element->{'id'}]['max'] = ui.values[1];
	       	  saveAndReloadElement(null,$element->{'id'});
	       	  \$("#reset_seqbin_range").css("display","inline");
      	  }
      }
    });
});
</script>
JS
	return;
}

sub _ajax_new {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $id, $options ) = @_;
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
			url_text          => "Browse $self->{'system'}->{'labelfield'}s",
			hide_mobile       => 0
		},
		sp_genomes => {
			name              => 'Genome count',
			display           => 'record_count',
			genomes           => 1,
			change_duration   => 'week',
			main_text_colour  => GENOMES_MAIN_TEXT_COLOUR,
			background_colour => GENOMES_BACKGROUND_COLOUR,
			watermark         => 'fas fa-dna',
			post_data         => {
				genomes => 1,
			},
			url_text    => 'Browse genomes',
			hide_mobile => 0
		},
		sp_seqbin_size => {
			name        => 'Sequence size',
			display     => 'seqbin_size',
			genomes     => 1,
			hide_mobile => 1,
			width       => 2
		}
	};
	my $q     = $self->{'cgi'};
	my $field = $q->param('field');
	if ( $default_elements->{$field} ) {
		$element = { %$element, %{ $default_elements->{$field} } };
	} else {
		my $display_field = $self->get_display_field($field);
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
	my $dashboard_name = $self->{'prefstore'}->get_dashboard_name( $self->_get_dashboard_id );
	if ( defined $options->{'qry_file'} ) {
		$self->{'no_query_link'} = 1;
		my $qry = $self->get_query_from_temp_file( $options->{'qry_file'} );
		$qry =~ s/ORDER\sBY.*$//gx;
		$self->{'db'}->do("CREATE TEMP VIEW dashboard_view AS $qry");
		$self->{'view'} = 'dashboard_view';
	}
	my $json = JSON->new->allow_nonref;
	say $json->encode(
		{
			element        => $element,
			html           => $self->_get_element_html( $element, { new => 1 } ),
			dashboard_name => $dashboard_name
		}
	);
	return;
}

sub get_display_field {
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
			my $set_name =
			  $self->{'datastore'}
			  ->run_query( 'SELECT set_name FROM set_schemes WHERE set_id=? AND scheme_id=?', [ $set_id, $scheme_id ] );
			$desc = $set_name if defined $set_name;
		}
		$display_field = "$scheme_field ($desc)";
	}
	return $display_field;
}

sub _ajax_get {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $id, $options ) = @_;
	my $q = $self->{'cgi'};
	if ( $options->{'list_file'} && $options->{'list_attribute'} ) {
		my $attribute_data = $self->get_list_attribute_data( $options->{'list_attribute'} );
		$self->{'datastore'}->create_temp_list_table( $attribute_data->{'data_type'}, $options->{'list_file'} );
	}
	if ( defined $options->{'qry_file'} ) {
		$self->{'no_query_link'} = 1;
		my $qry = $self->get_query_from_temp_file( $options->{'qry_file'} );
		$qry =~ s/ORDER\sBY.*$//gx;
		$self->{'db'}->do("CREATE TEMP VIEW dashboard_view AS $qry");
		$self->{'view'} = 'dashboard_view';
	}
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

sub get_list_attribute_data {
	my ( $self, $attribute ) = @_;
	my $pattern = LOCUS_PATTERN;
	my ( $field, $extended_field, $scheme_id, $field_type, $data_type, $eav_table, $optlist, $multiple );
	if ( $attribute =~ /^s_(\d+)_(\S+)$/x ) {    ## no critic (ProhibitCascadingIfElse)
		$scheme_id  = $1;
		$field      = $2;
		$field_type = 'scheme_field';
		my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		$data_type = $scheme_field_info->{'type'};
		return if !$scheme_field_info;
	} elsif ( $attribute =~ /$pattern/x ) {
		$field      = $1;
		$field_type = 'locus';
		$data_type  = 'text';
		return if !$self->{'datastore'}->is_locus($field);
		$field =~ s/\'/\\'/gx;
	} elsif ( $attribute =~ /^f_(\S+)$/x ) {
		$field      = $1;
		$field_type = 'provenance';
		$field_type = 'labelfield'
		  if $field_type eq 'provenance' && $field eq $self->{'system'}->{'labelfield'};
		return if !$self->{'xmlHandler'}->is_field($field);
		my $field_info = $self->{'xmlHandler'}->get_field_attributes($field);
		$data_type = $field_info->{'type'};
		if ( ( $field_info->{'optlist'} // q() ) eq 'yes' ) {
			$optlist = $self->{'xmlHandler'}->get_field_option_list($field);
		}
		if ( ( $field_info->{'multiple'} // q() ) eq 'yes' ) {
			$multiple = 1;
		}
	} elsif ( $attribute =~ /^eav_(\S+)$/x ) {
		$field      = $1;
		$field_type = 'phenotypic';
		my $field_info = $self->{'datastore'}->get_eav_field($field);
		return if !$field_info;
		$data_type = $field_info->{'value_format'};
		$eav_table = $self->{'datastore'}->get_eav_table($data_type);
	} elsif ( $attribute =~ /^e_(.*)\|\|(.*)/x ) {
		$extended_field = $1;
		$field          = $2;
		$data_type      = 'text';
		$field_type     = 'extended_isolate';
	} elsif ( $attribute =~ /^gp_(.+)_(latitude|longitude)/x ) {
		$field      = $1;
		$field_type = "geography_point_$2";
		$data_type  = 'float';
	}
	$_ //= q() foreach ( $eav_table, $extended_field );
	return {
		field          => $field,
		eav_table      => $eav_table,
		extended_field => $extended_field,
		scheme_id      => $scheme_id,
		field_type     => $field_type,
		data_type      => $data_type,
		optlist        => $optlist,
		multiple       => $multiple
	};
}

sub _ajax_set_active {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $active_id ) = @_;
	return if $active_id < 0;
	my $q    = $self->{'cgi'};
	my $type = $q->param('type') // $self->{'dashboard_type'};
	my $guid = $self->get_guid;
	if ( BIGSdb::Utils::is_int($active_id) ) {
		$self->{'prefstore'}->set_active_dashboard( $guid, $self->{'instance'}, $active_id, $type, 0 );
	}
	return;
}

sub _get_dashboard_empty_message {
	my ($self) = @_;
	return q(<p><span class="dashboard_empty_message">Dashboard contains no elements!</span></p>)
	  . q(<p>Go to dashboard settings to add visualisations.</p>);
}

sub _print_filter_display {
	my ($self) = @_;
	my $versions   = $self->{'prefs'}->{'include_old_versions'} ? 'all' : 'current';
	my $age_labels = RECORD_AGE;
	my $record_age = $self->{'prefs'}->{'record_age'} // 0;
	say q(<div id="filter_display">Record versions: )
	  . qq(<span class="dashboard_filter" id="filter_versions">$versions</span>; )
	  . qq(Record creation: <span class="dashboard_filter" id="filter_age">$age_labels->{$record_age}</span></div>);
	return;
}

sub print_dashboard {
	my ( $self, $options ) = @_;
	my $elements = $self->_get_elements;
	say q(<div>);
	$self->_print_filter_display if ( $options->{'filter_display'} );
	say q(<div id="empty">);
	if ( !keys %$elements ) {
		say $self->_get_dashboard_empty_message;
	}
	say q(</div>);
	say q(<div id="dashboard" class="grid" style="margin:auto;max-width:90vw">);
	my %display_immediately = map { $_ => 1 } qw(setup record_count);
	my $already_loaded      = [];
	my $ajax_load           = [];
	foreach my $element ( sort { $elements->{$a}->{'order'} <=> $elements->{$b}->{'order'} } keys %$elements ) {
		my $display = $elements->{$element}->{'display'};
		next if !$display;
		if ( $display_immediately{$display} ) {
			if ( $options->{'qry_file'} && !$self->{'view_set_up'} ) {
				my $qry = $self->get_query_from_temp_file( $options->{'qry_file'} );
				$qry =~ s/ORDER\sBY.*$//gx;
				$self->{'db'}->do("CREATE TEMP VIEW dashboard_view AS $qry");
				$self->{'view'}        = 'dashboard_view';
				$self->{'view_set_up'} = 1;
			}
			say $self->_get_element_html( $elements->{$element} );
			push @$already_loaded, $element;
		} else {
			say $self->_get_element_html( $elements->{$element}, { by_ajax => 1 } );
			push @$ajax_load, $element;
		}
	}
	say q(</div></div>);
	if (@$ajax_load) {
		$self->_print_ajax_load_code(
			$already_loaded,
			$ajax_load,
			{
				qry_file       => $options->{'qry_file'},
				list_file      => $options->{'list_file'},
				list_attribute => $options->{'list_attribute'}
			}
		);
	}
	return;
}

sub _print_ajax_load_code {
	my ( $self, $already_loaded, $ajax_load_ids, $options ) = @_;
	my $qry_file_clause = $options->{'qry_file'} ? qq(&qry_file=$options->{'qry_file'}) : q();
	my $qry_file       = $options->{'qry_file'} // q();
	my $list_file      = $options->{'list_file'};
	my $list_attribute = $options->{'list_attribute'};
	my $list_file_clause =
	  defined $list_file && defined $list_attribute ? qq(&list_file=$list_file&list_attribute=$list_attribute) : q();
	my $filter_clause = $self->{'no_filters'} ? '&no_filters=1' : q();
	local $" = q(,);
	say q[<script>];
	say q[$(function () {];
	say << "JS";
	var element_ids = [@$ajax_load_ids];
	var already_loaded = [@$already_loaded];
	qryFile="$qry_file";
	
	if (!window.running){
		window.running = true;
		\$.each(already_loaded, function(index,value){
			loadedElements[value] = 1;
		});
		\$.each(element_ids, function(index,value){
			if (\$(window).width() < MOBILE_WIDTH && elements[value]['hide_mobile']){
				return;
			}
			loadedElements[value] = 1;
			\$.ajax({
		    	url:"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=dashboard$qry_file_clause"
		    	+ "$list_file_clause$filter_clause&type=$self->{'dashboard_type'}&element=" + value
		    }).done(function(json){
		       	try {
		       	    \$("div#element_" + value + " > .item-content > .ajax_content").html(JSON.parse(json).html);
		       	    applyFormatting();
		       	    
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
		return $self->{'prefs'}->{'elements'};
	}
	return $self->_get_default_elements;
}

sub _get_default_elements {
	my ($self)   = @_;
	my $elements = {};
	my $i        = 1;
	my $default_dashboard;
	my @possible_files = (
		"$self->{'dbase_config_dir'}/$self->{'instance'}/dashboard_$self->{'dashboard_type'}.toml",
		"$self->{'config_dir'}/dashboard_$self->{'dashboard_type'}.toml",
		"$self->{'dbase_config_dir'}/$self->{'instance'}/dashboard.toml",
		"$self->{'config_dir'}/dashboard.toml"
	);
	my $file_exists;
	foreach my $filename (@possible_files) {
		if ( -e $filename ) {
			$file_exists = 1;
			my $toml = BIGSdb::Utils::slurp($filename);
			my ( $data, $err ) = from_toml($$toml);
			if ( !$data->{'elements'} ) {
				$logger->error("Error parsing $filename: $err");
			} else {
				$default_dashboard = $data->{'elements'};
			}
			last;
		}
	}
	if ( !$file_exists ) {
		$default_dashboard =
		  $self->{'dashboard_type'} eq 'primary' ? DEFAULT_FRONTEND_DASHBOARD : DEFAULT_QUERY_DASHBOARD;
	}
	if ( !ref $default_dashboard || ref $default_dashboard ne 'ARRAY' ) {
		$logger->error('No default dashboard elements defined - using built-in default instead.');
		$default_dashboard =
		  $self->{'dashboard_type'} eq 'primary' ? DEFAULT_FRONTEND_DASHBOARD : DEFAULT_QUERY_DASHBOARD;
	}
	my $genome_size = $self->{'system'}->{'min_genome_size'} // $self->{'config'}->{'min_genome_size'}
	  // MIN_GENOME_SIZE;
	my $genomes_exists =
	  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM seqbin_stats WHERE total_length>?)', $genome_size );
	foreach my $element (@$default_dashboard) {
		next if $element->{'genomes'} && !$genomes_exists;
		next if $element->{'display'} eq 'field' && !$self->_field_exists( $element->{'field'} );
		next
		  if ( $element->{'visualisation_type'} // 'breakdown' ) eq 'breakdown'
		  && ( $element->{'breakdown_display'} // q() ) eq 'map'
		  && !$self->_should_display_map_element( $element->{'field'} );
		$element->{'id'}    = $i;
		$element->{'order'} = $i;
		$element->{'width'}  //= 1;
		$element->{'height'} //= 1;
		$elements->{$i} = $element;
		$i++;
	}
	return $elements;
}

sub _should_display_map_element {
	my ( $self, $field ) = @_;
	return 1 if $field eq 'f_country' && $self->_field_has_optlist('f_country');
	return 1 if $field eq 'e_country||continent';
	return;
}

sub _get_element_html {
	my ( $self, $element, $options ) = @_;
	my $mobile_class = $element->{'hide_mobile'} ? q( hide_mobile) : q();
	my $border       = $element->{'hide_mobile'} ? q( hide_border) : q();
	my $buffer       = qq(<div id="element_$element->{'id'}" data-id="$element->{'id'}" class="item$border">);
	my $width_class  = "dashboard_element_width$element->{'width'}";
	my $height_class = "dashboard_element_height$element->{'height'}";
	my $setup        = $element->{'display'} eq 'setup' ? q( style="display:block") : q();
	my $new_item     = $options->{'new'} ? q( new_item) : q();
	$buffer .= qq(<div class="item-content $width_class $height_class$mobile_class$new_item"$setup>);
	$buffer .= $self->_get_element_controls($element);
	$buffer .= q(<div class="ajax_content" style="overflow:hidden;height:100%;width:100%;">);

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
		seqbin_size  => sub { $self->_get_seqbin_size_element_content($element) },
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
	return if !defined $field;
	if ( $field =~ /^f_(.*)$/x ) {
		my $field_name = $1;
		return $self->{'xmlHandler'}->is_field($field_name);
	}
	if ( $field =~ /^e_(.+)\|\|(.+)$/x ) {
		return $self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM isolate_field_extended_attributes WHERE (isolate_field,attribute)=(?,?))',
			[ $1, $2 ] );
	}
	if ( $field =~ /^s_(\d+)_(.+)$/x ) {
		return $self->{'datastore'}
		  ->run_query( 'SELECT EXISTS(SELECT * FROM scheme_fields WHERE (scheme_id,field)=(?,?))', [ $1, $2 ] );
	}
	return;
}

sub _get_filters {
	my ( $self, $options ) = @_;
	my $q       = $self->{'cgi'};
	my $filters = [];
	if ( !$q->param('no_filters') ) {
		push @$filters, 'v.new_version IS NULL' if !$self->{'prefs'}->{'include_old_versions'};
		if ( $self->{'prefs'}->{'record_age'} ) {
			my $datestamp = $self->get_record_age_datestamp( $self->{'prefs'}->{'record_age'} );
			push @$filters, "v.id IN (SELECT id FROM $self->{'system'}->{'view'} WHERE date_entered>='$datestamp')";
		}
	}
	if ( $options->{'genomes'} ) {
		my $genome_size = $self->{'system'}->{'min_genome_size'} // $self->{'config'}->{'min_genome_size'}
		  // MIN_GENOME_SIZE;
		push @$filters, "v.id IN (SELECT isolate_id FROM seqbin_stats WHERE total_length>=$genome_size)";
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
			my $qry = "SELECT COUNT(*) FROM $self->{'view'} v WHERE "
			  . "v.date_entered <= now()-interval '1 $element->{'change_duration'}'";
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
	$buffer .= $self->_get_data_query_link($element);
	return $buffer;
}

sub _get_seqbin_standard_range {
	my ($self) = @_;
	my $qry = "SELECT total_length FROM seqbin_stats s JOIN $self->{'system'}->{'view'} v ON s.isolate_id=v.id";
	my $lengths = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	return {} if !@$lengths;
	my $stats = BIGSdb::Utils::stats($lengths);
	my ( $min, $max );
	if ( $stats->{'count'} == 1 ) {
		$min = $stats->{'mean'} / 1_000_000 - 1;
		$max = $stats->{'mean'} / 1_000_000 + 1;
	} else {    #Set min/max 3 std. deviations from mean
		$min = BIGSdb::Utils::decimal_place( ( $stats->{'mean'} - 3 * $stats->{'std'} ) / 1_000_000, 1 );
		$max =
		  BIGSdb::Utils::decimal_place( ( $stats->{'mean'} + 3 * $stats->{'std'} ) / 1_000_000, 1 );
	}
	if ( $min == $max ) {
		$min -= 1;
		$max += 1;
	}
	$min = 0 if $min < 0;
	return { min => $min, max => $max };
}

sub _get_seqbin_size_element_content {
	my ( $self, $element ) = @_;
	my $chart_colour = $element->{'chart_colour'} // CHART_COLOUR;
	my $qry = "SELECT total_length FROM seqbin_stats s JOIN $self->{'view'} v ON s.isolate_id=v.id";
	if ( !defined $element->{'min'} && !defined $element->{'max'} ) {
		my $range = $self->_get_seqbin_standard_range;
		$element->{'min'} //= $range->{'min'};
		$element->{'max'} //= $range->{'max'};
	}
	my $min_value = $element->{'min'};
	my $max_value = $element->{'max'};
	my $buffer    = qq(<div class="title">$element->{'name'}</div>);
	my $filters   = $self->_get_filters;
	local $" = ' AND ';
	push @$filters, "s.total_length>=$min_value*1000000" if defined $min_value;
	push @$filters, "s.total_length<=$max_value*1000000" if defined $max_value;
	$qry .= " WHERE @$filters" if @$filters;
	my $lengths = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );

	if ( !@$lengths ) {
		$buffer .= q(<p>No sequences in dataset.</p>);
		return $buffer;
	}
	my $stats      = BIGSdb::Utils::stats($lengths);
	my $chart_data = {};
	my $bins =
	  ceil( ( 3.5 * $stats->{'std'} ) / $stats->{'count'}**0.33 )
	  ;    #Scott's choice [Scott DW (1979). On optimal and data-based histograms. Biometrika 66(3):605–610]
	$bins = 70 if $bins > 70;
	$bins = 50 if !$bins;
	my $width            = $stats->{'max'} / $bins;
	my $round_to_nearest = $self->_get_rounded_width($width);
	$width = int( $width - ( $width % $round_to_nearest ) ) || $round_to_nearest;
	my ( $histogram, $min, $max ) = BIGSdb::Utils::histogram( $width, $lengths );
	my $histogram_data = [];
	my $largest_value  = 0;
	my @labels;

	if ( @$lengths == 1 ) {
		my $label = BIGSdb::Utils::decimal_place( $lengths->[0] / 1_000_000, 2 );
		push @$histogram_data,
		  {
			label  => $label,
			values => 1
		  };
		push @labels, $label;
	} else {
		foreach my $i ( $min .. $max ) {
			next if ( $i * $width / 1_000_000 ) < $min_value;
			my $label =
			  $i == 0
			  ? q(0-) . ( $width / 1_000_000 )
			  : ( ( $i * $width ) / 1_000_000 ) . q(-) . ( ( $i + 1 ) * $width / 1_000_000 );
			push @$histogram_data,
			  {
				label  => $label,
				values => $histogram->{$i}
			  };
			push @labels, $label if $histogram->{$i};
			if ( ( $histogram->{$i} // 0 ) > $largest_value ) {
				$largest_value = $histogram->{$i};
			}
		}
	}
	my $label_length = length( $labels[-1] );
	my $height       = ( $element->{'height'} * 150 ) - 40;
	$buffer .= qq(<div id="chart_$element->{'id'}" class="histogram" style="margin-top:-20px"></div>);
	my $json      = JSON->new->allow_nonref;
	my $json_data = $json->encode($histogram_data);
	local $" = q(",");
	my $label_string = qq("@labels");
	$buffer .= << "JS";
<script>
\$(function() {
	var labels = [$label_string];
	var label_shown = false;
	bb.generate({
		bindto: '#chart_$element->{'id'}',
		data: {
			json: $json_data,
			keys: {
				x: 'label',
				value: ['values']
			},
			type: 'bar',
			labels: {
				show: true,
				format: function (v,id,i,j){
					if (v === $largest_value && $element->{'width'} > 1){
						if (!label_shown && labels[i] != null){
							label_shown = true;
							return labels[i];
						}
					}
				},
				position: {
					x: 10
				}
			},
			color: function(){
				return "$chart_colour";
			}
		},	
		bar: {
			width: {
				ratio: 0.6
			}
		},

		axis: {
			x: {
				type: 'category',
				label: {
					text: 'total length (Mbp)',
					position: 'outer-center'
				},
				tick: {
					count: 2,
					multiline:false,
					text: {
						position: {
							x: -$label_length * 2
						}
					}
				}
			},
			y: {
				tick: {
					culling: {
						max: $element->{'height'} * 2 + 1
					},
					format: y => y % 1 > 0 ? y.toFixed(0) : y
				},
				padding: {
					top: 20
				}
			}
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
		legend: {
			show: false
		},
		padding: {
			top:10,
			right: 10
		},
		size: {
			height: $height
		},
	});
	d3.select(".bb-axis-x .tick text").attr("transform", "translate(20,0)");
});	

</script>
JS
	return $buffer;
}

sub _get_rounded_width {
	my ( $self, $width ) = @_;
	$width //= 0;
	return 5     if $width < 50;
	return 10    if $width < 100;
	return 50    if $width < 500;
	return 100   if $width < 1000;
	return 500   if $width < 5000;
	return 1000  if $width < 10000;
	return 50000 if $width < 500000;
	return 100000;
}

sub _get_colour_swatch {
	my ( $self, $element ) = @_;
	if ( $element->{'background_colour'} ) {
		return qq[<div style="background-image:linear-gradient(#fff,#fff 10%,$element->{'background_colour'},]
		  . q[#fff 90%,#fff);height:calc(100% - 10px);margin-top:5px;width:100%;position:absolute;z-index:-1"></div>];
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
		} else {
			$logger->error("Element $element->{'id'}: No chart type selected");
			$buffer .= $self->_get_setup_element_content($element);
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
	if ( $type eq 'geography_point' ) {
		$type = 'geography(POINT, 4326)';
		my $new_values = [];
		foreach my $value (@$values) {
			if ( $value =~ /^(\-?\d+\.?\d*),\s*(\-?\d+\.?\d*)/x ) {
				push @$new_values, $self->{'datastore'}->convert_coordinates_to_geography( $1, $2 );
			}
		}
		$values = $new_values;
	}
	my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( $type, $values );
	my $qry;
	my $view = $self->{'view'};
	if ( $type eq 'text' ) {
		$qry =
		  ( $att->{'multiple'} // q() ) eq 'yes'
		  ? "SELECT COUNT(*) FROM $view v WHERE UPPER(v.${field}::text)::text[] && "
		  . "ARRAY(SELECT UPPER(value) FROM $temp_table)"
		  : "SELECT COUNT(*) FROM $view v WHERE UPPER(v.$field) IN (SELECT UPPER(value) FROM $temp_table)";
	} else {
		$qry =
		  ( $att->{'multiple'} // q() ) eq 'yes'
		  ? "SELECT COUNT(*) FROM $view v WHERE v.$field && ARRAY(SELECT value FROM temp_list)"
		  : "SELECT COUNT(*) FROM $view v WHERE v.$field IN (SELECT value FROM $temp_table)";
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
	my $view       = $self->{'view'};
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
		my $qry = "SELECT COUNT(DISTINCT v.id) FROM $self->{'view'} v JOIN $scheme_table s ON v.id=s.id WHERE ";
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
	my $qry     = "SELECT $field AS label,COUNT(*) AS value FROM $self->{'view'} v ";
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
	if ( $self->{'datastore'}->field_needs_conversion($field) ) {
		foreach my $value (@$values) {
			next if !defined $value->{'label'};
			$value->{'label'} = $self->{'datastore'}->convert_field_value( $field, $value->{'label'} );
		}
	}
	return $values;
}

sub _get_extended_field_breakdown_values {
	my ( $self, $field, $attribute ) = @_;
	my $qry =
	    "SELECT COALESCE(e.value,'No value') AS label,COUNT(*) AS value FROM $self->{'view'} v "
	  . "LEFT JOIN isolate_value_extended_attributes e ON (v.$field,e.isolate_field,e.attribute)=(e.field_value,?,?) ";
	my $filters = $self->_get_filters;
	local $" = ' AND ';
	$qry .= "WHERE @$filters" if @$filters;
	$qry .= ' GROUP BY label ORDER BY value DESC';
	my $values =
	  $self->{'datastore'}->run_query( $qry, [ $field, $attribute ], { fetch => 'all_arrayref', slice => {} } );
	return $values;
}

sub _get_eav_field_breakdown_values {
	my ( $self, $field ) = @_;
	my $att   = $self->{'datastore'}->get_eav_field($field);
	my $table = $self->{'datastore'}->get_eav_field_table($field);
	my $qry   = "SELECT t.value AS label,COUNT(*) AS value FROM $table t RIGHT JOIN $self->{'view'} v "
	  . 'ON t.isolate_id = v.id AND t.field=?';
	my $filters = $self->_get_filters;
	local $" = ' AND ';
	$qry .= " WHERE @$filters" if @$filters;
	$qry .= ' GROUP BY label ORDER BY ';

	if (   $att->{'value_format'} eq 'integer'
		|| $att->{'value_format'} eq 'date'
		|| $att->{'value_format'} eq 'float' )
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
	    "SELECT s.$field AS label,COUNT(DISTINCT (v.id)) AS value FROM $self->{'view'} v "
	  . "LEFT JOIN $scheme_table s ON v.id=s.id";
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
			label         => $value->{'label'},
			display_label => $label,
			value         => $value->{'value'}
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
	$element->{'background_colour'} //= COUNT_BACKGROUND_COLOUR;
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
	$buffer .= $self->_get_data_query_link($element);
	$buffer .= $self->_get_data_explorer_link($element);
	return $buffer;
}

sub _get_total_record_count {
	my ( $self, $options ) = @_;
	my $qry     = "SELECT COUNT(*) FROM $self->{'view'} v";
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
	$buffer .= $self->_get_data_explorer_link($element);
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
	$buffer .= $self->_get_data_query_link($element);
	return $buffer;
}

sub _get_doughnut_pie_threshold {
	my ( $self, $data ) = @_;
	my $max_threshold = 0.10;    #Show segments that are >=10% of total
	my $total         = 0;
	$total += $_->{'value'} foreach @$data;
	return $max_threshold if !$total;
	my $running = 0;
	my $threshold = 0;
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
		$value->{'display_label'} =~ s/"/\\"/gx if defined $value->{'display_label'};
		my $label = $value->{'display_label'} // $value->{'label'};
		$value_count++;
		if ( $value_count >= MAX_SEGMENTS && @$data != MAX_SEGMENTS ) {
			$others += $value->{'value'};
			$others_values++;
		} else {
			push @$dataset, qq(                ["$label", $value->{'value'}]);
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
		$value->{'display_label'} =~ s/"/\\"/gx if defined $value->{'display_label'};
		push @$labels, $value->{'display_label'} // $value->{'label'};
		push @$values, $value->{'value'};
		$max = $value->{'value'} if $value->{'value'} > $max;
	}

	#Calc local max
	my $cols_either_side = int( @$data / ( $element->{'width'} * 3 ) );
	my %local_max;
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
		push @$local_max, $i if !$local_max{ $i - 1 };    #Don't label consecutive bars.
		$local_max{$i} = 1;
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
	$buffer .= $self->_get_data_explorer_link($element);
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
						if (v < max*0.05 || v == 1){
							return;
						}
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
     		padding: {
     			right: 10
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
	if ( $ticks > @{ $dataset->{'labels'} } ) {
		$ticks = @{ $dataset->{'labels'} };
	}
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
					min: 0,
					padding: {
						bottom: 0
					},
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
	  q(<p><span class="fas fa-ban" style="color:#44c;font-size:3em;text-shadow: 3px 3px 3px #999;"></span></p>);
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
	$buffer .= $self->_get_data_explorer_link($element);
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
	$buffer .= $self->_get_data_explorer_link($element);
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
	my $complete_data = $self->_get_field_breakdown_values($element);
	if ( !@$complete_data ) {
		return $self->_print_no_value_content($element);
	}
	my %word_counts;
	my %invalid_words = map { $_ => 1 } qw(of and the);
	foreach my $value (@$complete_data) {
		my @words =
		  length( $value->{'label'} ) > 12
		  ? split /\s/x, $value->{'label'}
		  : ( $value->{'label'} );
		foreach my $word (@words) {
			$word =~ s/[\[\]]//gx if @words > 1;
			next if $invalid_words{$word};
			$word_counts{$word} += $value->{'value'};
		}
	}
	my $data = [];
	foreach my $word ( keys %word_counts ) {
		push @$data,
		  {
			label => $word,
			value => $word_counts{$word}
		  };
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
	$buffer .= $self->_get_data_explorer_link($element);
	$buffer .= << "JS";
	<script>
	\$(function() {
		var layout = d3.layout.cloud()
	    .size([$width, $height])
	    .words($words)
	    .spiral('rectangular')
	    .rotate(function() { return ~~(Math.random() * 2) * 90; })
	    .fontSize(function(d) { return d.size*1.5; })
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
	my $header_colour     = $element->{'header_text_colour'}       // HEADER_TEXT_COLOUR;
	my $header_background = $element->{'header_background_colour'} // HEADER_BACKGROUND_COLOUR;
	my $data              = $self->_get_field_breakdown_values($element);
	if ( !@$data ) {
		return $self->_print_no_value_content($element);
	}
	my $buffer = $self->_get_title($element);
	$element->{'top_values'} //= TOP_VALUES;
	my $style = $element->{'height'} == 1
	  && $element->{'top_values'} == 5 ? 'line-height:100%;font-size:0.9em' : q();
	$buffer .= qq(<div class="subtitle">Top $element->{'top_values'} values</div>);
	$buffer .=
	    q(<div><table class="dashboard_table"><tr>)
	  . qq(<th style="color:$header_colour;background:$header_background">Value</th>)
	  . qq(<th style="color:$header_colour;background:$header_background">Frequency</th></tr>);
	my $td     = 1;
	my $count  = 0;
	my $target = $self->{'prefs'}->{'open_new'} ? q( target="_blank") : q();

	foreach my $value ( sort { $b->{'value'} <=> $a->{'value'} } @$data ) {
		next if !defined $value->{'label'} || $value->{'label'} eq 'No value';
		my $url           = $self->_get_query_url( $element, $value->{'label'} );
		my $nice_value    = BIGSdb::Utils::commify( $value->{'value'} );
		my $display_label = $value->{'display_label'} // $value->{'label'};
		$count++;
		my $formatted_value = $self->{'no_query_link'} ? $display_label : qq(<a href="$url"$target>$display_label</a>);
		$buffer .= qq(<tr class="td$td" style="$style"><td>$formatted_value</td><td>$nice_value</td></tr>);
		$td = $td == 1 ? 2 : 1;
		last if $count >= $element->{'top_values'};
	}
	$buffer .= q(</table>);
	$buffer .= $self->_get_data_explorer_link($element);
	$buffer .= q(</div>);
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
	my $display_data = [];
	foreach my $value (@$data) {
		push @$display_data,
		  {
			label => $value->{'display_label'} // $value->{'label'},
			value => $value->{'value'}
		  };
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
	my $dataset = $json->encode( { children => $display_data } );
	$buffer .= qq(<div id="chart_$element->{'id'}" class="treemap" style="margin-top:-25px"></div>);
	$buffer .= $self->_get_data_explorer_link($element);
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
    	.range([.8,1])

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
	    	.attr("x", function(d){ return d.x0+3})    // adjust position (further right)
	    	.attr("y", function(d){ 
	    		let cell_height = d.y1 - d.y0;
	    		return cell_height > 30 ? d.y0+20 : d.y0+ cell_height/2 + 5;// adjust position (lower)
	    	})    
	    	.text(function(d){
	    		let cell_width = d.x1 - d.x0;   	    						
	    		if (
	    			$total 
	    			&& d.data.value/$total >= 0.02 
	    			&& String(d.data.label).length <= cell_width / 6){
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
	my $countries = dclone(COUNTRIES);
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
	$buffer .= $self->_get_data_explorer_link($element);
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
	my $url   = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query";
	my $field = $element->{'field'};
	$value =~ s/\ /\%20/gx;
	if ( $element->{'field'} =~ /^[f|e]_/x ) {
		$field = 'f_sender%20(id)'  if $field eq 'f_sender';
		$field = 'f_curator%20(id)' if $field eq 'f_curator';
		my $type = $self->_get_field_type($element);
		if ( $type eq 'geography_point' ) {
			my ( $lat, $long ) = split /,%20/x, $value;
			$field =~ s/^f_/gp_/x;
			$url .= "&amp;prov_field1=${field}_latitude&amp;prov_value1=$lat&amp;"
			  . "prov_field2=${field}_longitude&amp;prov_value2=$long";
		} else {
			$url .= "&amp;prov_field1=$field&amp;prov_value1=$value";
		}
	}
	if ( $element->{'field'} =~ /^eav_/x ) {
		$url .= "&amp;phenotypic_field1=$field&amp;phenotypic_value1=$value";
	}
	if ( $element->{'field'} =~ /^s_\d+_/x ) {
		$url .= "&amp;designation_field1=$field&amp;designation_value1=$value";
	}
	if ( $self->{'prefs'}->{'include_old_versions'} ) {
		$url .= '&amp;include_old=on';
	}
	if ( $self->{'prefs'}->{'record_age'} ) {
		my $row;
		for ( my $i = 20 ; $i >= 0 ; $i-- ) {
			if ( $url =~ /prov_field$i/x ) {
				$row = $i + 1;
				last;
			}
			$row = 1;
		}
		my $datestamp = $self->get_record_age_datestamp( $self->{'prefs'}->{'record_age'} );
		$url .= "&amp;prov_field$row=f_date_entered&amp;prov_operator$row=>=&amp;prov_value$row=$datestamp";
	}
	$url .= '&amp;submit=1';
	return $url;
}

sub get_record_age_datestamp {
	my ( $self, $record_age ) = @_;
	return if !$record_age || !BIGSdb::Utils::is_int($record_age);
	if ( $self->{'cache'}->{'record_age'}->{$record_age} ) {
		return $self->{'cache'}->{'record_age'}->{$record_age};
	}
	my $periods = RECORD_AGE;
	my $period  = $periods->{$record_age};
	$period =~ s/past\s//x;
	$period = '1 ' . $period if $period !~ /^\d/x;
	$self->{'cache'}->{'record_age'}->{$record_age} =
	  $self->{'datastore'}->run_query("SELECT CAST(now()-interval '$period' AS date)");
	return $self->{'cache'}->{'record_age'}->{$record_age};
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

sub _get_data_query_link {
	my ( $self, $element ) = @_;
	return q() if $self->{'no_query_link'};
	my $buffer = q();
	$buffer .= qq(<span data-id="$element->{'id'}" class="dashboard_data_query_element fas fa-share">);
	if ( $element->{'url_text'} ) {
		$buffer .= qq(<span class="tooltip">$element->{'url_text'}</span>);
	}
	$buffer .= q(</span>);
	return $buffer;
}

sub _get_data_explorer_link {
	my ( $self, $element ) = @_;
	return q() if $self->{'no_query_link'};
	my $type = $self->_get_field_type($element);
	return q() if $type eq 'geography_point';
	my $buffer = q();
	$element->{'explorer_text'} //= 'Explore data';
	$buffer .= qq(<span data-id="$element->{'id'}" class="dashboard_data_explorer_element fas fa-search">);
	$buffer .= qq(<span class="tooltip">$element->{'explorer_text'}</span>);
	$buffer .= q(</span>);
	return $buffer;
}

sub initiate {
	my ($self) = @_;
	return if ( $self->{'system'}->{'dbtype'} // q() ) ne 'isolates';
	$self->{'dashboard_type'} = 'primary';
	$self->{$_} = 1
	  foreach
	  qw (jQuery noCache muuri modal fitty bigsdb.dashboard tooltips jQuery.fonticonpicker billboard d3.layout.cloud);
	$self->{'geomap'} = 1 if $self->has_country_optlist;
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
	foreach my $ajax_param (
		qw(updateGeneralPrefs updateDashboard updateDashboardName newDashboard setActiveDashboard control
		resetDefaults new setup element seqbin_range)
	  )
	{
		if ( $q->param($ajax_param) ) {
			$self->{'type'} = 'no_header';
			last;
		}
	}
	$self->get_or_set_dashboard_prefs;
	return;
}

sub get_or_set_dashboard_prefs {
	my ($self) = @_;
	my $guid   = $self->get_guid;
	my $q      = $self->{'cgi'};
	$self->{'dashboard_type'} = $q->param('type') if defined $q->param('type');
	my $dashboard_id =
	  $self->{'prefstore'}->get_active_dashboard( $guid, $self->{'instance'}, $self->{'dashboard_type'}, 0 );
	if ( $q->param('resetDefaults') ) {
		$self->{'prefstore'}->delete_dashboard( $dashboard_id, $guid, $self->{'instance'} ) if $guid;
		my $dashboards = $self->{'prefstore'}->get_dashboards( $guid, $self->{'instance'} );
		if (@$dashboards) {
			$self->{'prefstore'}->set_active_dashboard(
				$guid, $self->{'instance'},
				$dashboards->[0]->{'id'},
				$self->{'dashboard_type'}, 0
			);
		}
	}
	$self->{'prefs'} = $self->{'prefstore'}->get_general_dashboard_prefs( $guid, $self->{'instance'} );
	if ( defined $dashboard_id ) {
		my $dashboard = $self->{'prefstore'}->get_dashboard($dashboard_id);
		$self->{'prefs'}->{$_} = $dashboard->{$_} foreach ( keys %$dashboard );
	}
	return;
}

sub _update_dashboard_name {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $name   = $q->param('updateDashboardName');
	$name =~ s/^\s+|\s+$//x;
	return if !$name || !length($name) || length($name) > 15;
	my $guid = $self->get_guid;
	my $dashboard_id =
	  $self->{'prefstore'}->get_active_dashboard( $guid, $self->{'instance'}, $self->{'dashboard_type'}, 0 );
	$self->{'prefstore'}->update_dashboard_name( $dashboard_id, $guid, $self->{'instance'}, $name );
	return;
}

sub _update_general_prefs {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $attribute = $q->param('attribute');
	return if !defined $attribute;
	my $value = $q->param('value');
	return if !defined $value;
	my %allowed_attributes = map { $_ => 1 } qw(enable_drag edit_elements remove_elements open_new default);
	if ( !$allowed_attributes{$attribute} ) {
		$logger->error("Invalid attribute - $attribute");
		return;
	}
	my %allowed_values = map { $_ => 1 } ( 0, 1 );
	return if !$allowed_values{$value};
	my $guid = $self->get_guid;
	if ( $allowed_attributes{$attribute} ) {
		$self->{'prefstore'}->set_general_dashboard_switch_pref( $guid, $self->{'instance'}, $attribute, $value );
	}
	return;
}

sub _update_dashboard_prefs {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $attribute = $q->param('attribute');
	return if !defined $attribute;
	my $value = $q->param('value');
	return if !defined $value;
	my %allowed_attributes =
	  map { $_ => 1 }
	  qw(fill_gaps order elements include_old_versions open_new name record_age
	);

	if ( !$allowed_attributes{$attribute} ) {
		$logger->error("Invalid attribute - $attribute");
		return;
	}
	my $json = JSON->new->allow_nonref;
	my %boolean_attributes = map { $_ => 1 } qw(fill_gaps include_old_versions);
	if ( $boolean_attributes{$attribute} ) {
		my %allowed_values = map { $_ => 1 } ( 0, 1 );
		return if !$allowed_values{$value};
	}
	my $guid         = $self->get_guid;
	my $dashboard_id = $self->_get_dashboard_id;
	if ( $allowed_attributes{$attribute} ) {
		$self->{'prefstore'}
		  ->update_dashboard_attribute( $dashboard_id, $guid, $self->{'instance'}, $attribute, $value );
	}
	my $dashboard_name = $self->{'prefstore'}->get_dashboard_name($dashboard_id);
	say $json->encode(
		{
			dashboard_name => $dashboard_name
		}
	);
	return;
}

sub _get_dashboard_id {
	my ($self) = @_;
	return $self->{'dashboard_id'} if defined $self->{'dashboard_id'};
	my $guid = $self->get_guid;
	$self->{'dashboard_id'} =
	  $self->{'prefstore'}->get_active_dashboard( $guid, $self->{'instance'}, $self->{'dashboard_type'}, 0 );
	return $self->{'dashboard_id'} if defined $self->{'dashboard_id'};
	$self->{'dashboard_id'} =
	  $self->{'prefstore'}->initiate_new_dashboard( $guid, $self->{'instance'}, $self->{'dashboard_type'}, 0 );
	if ( !defined $self->{'dashboard_id'} ) {
		$logger->error('Dashboard pref could not be initiated.');
	}
	return $self->{'dashboard_id'};
}

sub print_panel_buttons {
	my ($self) = @_;
	say q(<span class="icon_button"><a class="trigger_button" id="dashboard_panel_trigger" style="display:none">)
	  . q(<span class="fas fa-lg fa-tools"></span><div class="icon_label">Modify dashboard</div></a></span>);
	say q(<span class="icon_button"><a class="trigger_button" id="dashboard_toggle">)
	  . q(<span class="fas fa-lg fa-th-list"></span><div class="icon_label">Index page</div></a></span>);
	return;
}

sub print_modify_dashboard_fieldset {
	my ( $self, $options ) = @_;
	my $enable_drag     = $self->{'prefs'}->{'enable_drag'}     // 0;
	my $edit_elements   = $self->{'prefs'}->{'edit_elements'}   // 1;
	my $remove_elements = $self->{'prefs'}->{'remove_elements'} // 0;
	my $open_new        = $self->{'prefs'}->{'open_new'}        // 1;
	my $fill_gaps       = $self->{'prefs'}->{'fill_gaps'}       // 1;
	my $q               = $self->{'cgi'};
	say q(<div id="modify_dashboard_panel" class="panel">);
	say q(<a class="trigger" id="close_dashboard_trigger" href="#"><span class="fas fa-lg fa-times"></span></a>);
	say q(<h2>Dashboard settings</h2>);
	say q(<fieldset><legend>Layout</legend>);
	say q(<form autocomplete="off">);    #Needed because Firefox autocomplete can override the values we set.
	say q(<ul><li>);
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
	say q(</form>);
	say q(</fieldset>);
	say q(<fieldset><legend>Links</legend>);
	say q(<ul><li>);
	say $q->checkbox(
		-name    => 'open_new',
		-id      => 'open_new',
		-label   => 'Open links in new tab',
		-checked => $open_new ? 'checked' : undef
	);
	say q(</li></ul>);
	say q(</fieldset>);
	$self->_print_filter_fieldset if !$options->{'no_filters'};
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
	$self->print_field_selector;
	say q(<a id="add_element" class="small_submit" style="white-space:nowrap">Add element</a>);
	say q(</li></ul>);
	say q(</fieldset>);
	$self->_print_dashboard_management_fieldset;
	return;
}

sub _print_filter_fieldset {
	my ($self) = @_;
	my $include_old_versions = $self->{'prefs'}->{'include_old_versions'} // 0;
	my $record_age           = $self->{'prefs'}->{'record_age'}           // 0;
	my $record_age_labels    = RECORD_AGE;
	my $q                    = $self->{'cgi'};
	say q(<fieldset><legend>Filters</legend>);
	say q(<form autocomplete="off">);    #Needed because Firefox autocomplete can override the values we set.
	say q(<ul><li>);
	say $q->checkbox(
		-name    => 'include_old_versions',
		-id      => 'include_old_versions',
		-label   => 'Include old record versions',
		-checked => $include_old_versions ? 'checked' : undef
	);
	say qq(</li><li>Record age: <span id="record_age">$record_age_labels->{$record_age}</span>);
	say q(<div id="record_age_slider" style="width:150px;margin-top:5px"></div>);
	say q(</li></ul>);
	say q(</form>);
	say q(</fieldset>);
	return;
}

sub _print_dashboard_management_fieldset {
	my ($self) = @_;
	my $guid = $self->get_guid;
	my $name;
	my $dashboard_id =
	  $self->{'prefstore'}->get_active_dashboard( $guid, $self->{'instance'}, $self->{'dashboard_type'}, 0 );
	my $dashboards = $self->{'prefstore'}->get_dashboards( $guid, $self->{'instance'} );
	my $ids        = [-1];
	my $labels     = { -1 => 'Select dashboard...' };
	if ( defined $dashboard_id ) {
		push @$ids, 0;
		$labels->{0} = "$self->{'dashboard_type'} default";
	} else {
		$dashboard_id = 0;
	}
	foreach my $dashboard (@$dashboards) {
		next if $dashboard->{'id'} == $dashboard_id;
		push @$ids, $dashboard->{'id'};
		$labels->{ $dashboard->{'id'} } = $dashboard->{'name'};
	}
	if ($dashboard_id) {
		$name = $self->{'prefstore'}->get_dashboard_name($dashboard_id);
	} else {
		$name = "$self->{'dashboard_type'} default";
	}
	my $q = $self->{'cgi'};
	say q(<fieldset><legend>Versions</legend>);
	say q(<form autocomplete="off">);    #Needed because Firefox will override the value we set for loaded_dashboard.
	say q(<ul><li>);
	say q(<label for="loaded_dashboard">Loaded:</label>);
	my %attributes = (
		-id        => 'loaded_dashboard',
		-name      => 'loaded_dashboard',
		-maxlength => 15,
		-style     => 'width:8em',
		-value     => $name
	);
	$attributes{'-disabled'} = 1 if $name eq "$self->{'dashboard_type'} default";
	say $q->textfield(%attributes);
	say q(</li>);

	if ( @$ids > 1 ) {
		say q(<li><label for="switch_dashboard">Switch:</label>);
		say $q->popup_menu(
			-id      => 'switch_dashboard',
			-name    => 'switch_dashboard',
			-labels  => $labels,
			-values  => $ids,
			-default => -1
		);
		say q(</li>);
	}
	say q(<li>);
	if ( @$ids > 1 ) {
		my $reset_display = $name eq 'query default' || $name eq 'primary default' ? q(none) : q(inline);
		say q(<a id="delete_dashboard" onclick="resetDefaults()" class="small_reset" )
		  . qq(style="display:$reset_display;white-space:nowrap"><span class="far fa-trash-alt"></span> Delete</a>);
	}
	if ( @$dashboards < DASHBOARD_LIMIT ) {
		say q(<a onclick="createNew()" class="small_submit">New dashboard</a>);
	}
	say q(</li></ul>);
	say q(</form>);
	say q(</fieldset>);
	return;
}

sub print_field_selector {
	my ( $self, $select_options, $field_options ) = @_;
	$select_options //= {
		ignore_prefs             => 1,
		isolate_fields           => 1,
		scheme_fields            => 1,
		extended_attributes      => 1,
		eav_fields               => 1,
		nosplit_geography_points => 1
	};
	my $q = $self->{'cgi'};
	my ( $fields, $labels ) = $self->get_field_selection_list($select_options);

	#Remove excluded field from list
	if ( $field_options->{'exclude_field'} ) {
		my $field_index = 0;
		foreach my $field (@$fields) {
			last if $fields->[$field_index] eq $field_options->{'exclude_field'};
			$field_index++;
		}
		splice( @$fields, $field_index, 1 ) if $field_index < @$fields;
	}
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
	push @{ $group_members->{'Special'} }, 'sp_count', 'sp_genomes', 'sp_seqbin_size'
	  if !$field_options->{'no_special'};
	$labels->{'sp_count'}       = "$self->{'system'}->{'labelfield'} count";
	$labels->{'sp_genomes'}     = 'genome count';
	$labels->{'sp_seqbin_size'} = 'sequence bin size';
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
	unshift @$values, q() if $field_options->{'no_default'};
	my $label = $field_options->{'label'} // 'Field';
	say qq(<label for="add_field">$label:</label>);
	say $q->popup_menu(
		-name => $field_options->{'name'} // 'add_field',
		-id   => $field_options->{'id'}   // 'add_field',
		-values   => $values,
		-labels   => $labels,
		-multiple => 'true',
		-style    => 'max-width:10em',
		-class    => 'field_selector'
	);
	return;
}

sub get_javascript {
	my ($self) = @_;
	return if ( $self->{'system'}->{'dbtype'} // q() ) ne 'isolates';
	my $order = $self->{'prefs'}->{'order'} // q();
	my $enable_drag = $self->{'prefs'}->{'enable_drag'} ? 'true' : 'false';
	my $json = JSON->new->allow_nonref;
	if ($order) {
		$order = $json->encode($order);
	}
	my $elements            = $self->_get_elements;
	my $json_elements       = $json->encode($elements);
	my $record_age_labels   = $json->encode(RECORD_AGE);
	my $record_age          = $self->{'prefs'}->{'record_age'} // 0;
	my $empty               = $self->_get_dashboard_empty_message;
	my $duration_datestamps = $self->{'datastore'}->run_query(
		q(SELECT CAST(now() AS DATE), CAST(now()-interval '5 years' AS DATE), )
		  . q(CAST(now()-interval '4 years' AS DATE), CAST(now()-interval '3 years' AS DATE), )
		  . q(CAST(now()-interval '2 years' AS DATE), CAST(now()-interval '1 year' AS DATE), )
		  . q(CAST(now()-interval '1 month' AS DATE), CAST(now()-interval '1 week' AS DATE)),
		undef,
		{ fetch => 'row_arrayref' }
	);
	my $datestamps = $json->encode($duration_datestamps);
	my $buffer     = << "END";
var url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}";
var elements = $json_elements;
var order = '$order';
var instance = "$self->{'instance'}";
var empty='$empty';
var enable_drag=$enable_drag;
var dashboard_type='primary';
var loadedElements = {};
var recordAgeLabels = $record_age_labels;
var recordAge = $record_age;
var datestamps = $datestamps;
var qryFile;
var listFile;
var listAttribute;
END
	return $buffer;
}
1;
