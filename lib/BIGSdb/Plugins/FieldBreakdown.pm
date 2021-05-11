#FieldBreakdown.pm - FieldBreakdown plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2018-2021, University of Oxford
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
package BIGSdb::Plugins::FieldBreakdown;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use BIGSdb::Constants qw(COUNTRIES);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use JSON;

sub get_attributes {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my %att    = (
		name    => 'Field Breakdown',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@zoo.ox.ac.uk',
			}
		],
		description      => 'Breakdown of query results by field',
		full_description => 'The field breakdown plugin displays the frequency of each value for fields, '
		  . 'alleles and schemes. Output is in the form of dynamic charts, maps, and tables. Data can be '
		  . 'exported as an Excel file, SVG image, or FASTA file.',
		category   => 'Breakdown',
		buttontext => 'Fields',
		menutext   => 'Field breakdown',
		module     => 'FieldBreakdown',
		version    => '2.3.0',
		dbtype     => 'isolates',
		section    => 'breakdown,postquery',
		url        => "$self->{'config'}->{'doclink'}/data_analysis/field_breakdown.html",
		input      => 'query',
		order      => 10,
		image      => '/images/plugins/FieldBreakdown/screenshot.png'
	);
	return \%att;
}

sub get_initiation_values {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $values = { billboard => 1, filesaver => 1, noCache => 0, 'jQuery.tablesort' => 1, pluginJS => 'FieldBreakdown.js' };
	if ( $self->_has_country_optlist ) {
		$values->{'geomap'} = 1;
	}
	if ( $q->param('field') ) {
		$values->{'type'} = 'json';
	}
	if ( $q->param('export') && $q->param('format') ) {
		( my $field_name = $q->param('export') ) =~ s/^s_\d+_//x;
		my $format = {
			text  => 'txt',
			xlsx  => 'xlsx',
			fasta => 'fas'
		};
		if ( $format->{ $q->param('format') } ) {
			$values->{'attachment'} = "$field_name." . $format->{ $q->param('format') };
		}
	}
	return $values;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 1, query_field => 0 };
	return;
}

sub _has_country_optlist {
	my ($self) = @_;
	return if !$self->{'xmlHandler'}->is_field('country');
	my $thisfield = $self->{'xmlHandler'}->get_field_attributes('country');
	return $thisfield->{'optlist'} ? 1 : 0;
}

sub _export {
	my ( $self, $field, $format ) = @_;
	my $formats = {
		table => sub { $self->_show_table($field) },
		xlsx  => sub { $self->_export_excel($field) },
		text  => sub { $self->_export_text($field) },
		fasta => sub { $self->_export_fasta($field) }
	};
	if ( $formats->{$format} ) {
		$formats->{$format}->();
	} else {
		say q(<h1>Field breakdown</h1>);
		$self->print_bad_status( { message => q(Invalid format selected.) } );
	}
	return;
}

sub _get_field_type {
	my ( $self, $field ) = @_;
	if ( $self->{'xmlHandler'}->is_field($field) ) {
		return 'field';
	}
	if ( $self->{'datastore'}->is_eav_field($field) ) {
		return 'eav_field';
	}
	if ( $field =~ /^(.+)\.\.(.+)$/x ) {
		return 'extended_field';
	}
	if ( $field =~ /^s_\d+_.+$/x ) {
		return 'scheme_field';
	}
	if ( $self->{'datastore'}->is_locus($field) ) {
		return 'locus';
	}
	return;
}

sub _get_field_values {
	my ( $self, $field ) = @_;
	my $field_type = $self->_get_field_type($field) // q();
	my $freqs      = [];
	my $methods    = {
		field => sub {
			my $att = $self->{'xmlHandler'}->get_field_attributes($field);
			$freqs = $self->_get_field_freqs(
				$field, $att->{'type'} =~ /^(?:int|float|date)/x
				? { order => 'label ASC' }
				: undef
			);
		},
		eav_field => sub {
			my $att = $self->{'datastore'}->get_eav_field($field);
			$freqs =
			  $self->_get_eav_field_freqs( $field, $att->{'value_format'} =~ /^(?:int|float|date)/x
				? { order => 'label ASC' }
				: undef );
		},
		extended_field => sub {
			if ( $field =~ /^(.+)\.\.(.+)$/x ) {
				my ( $std_field, $extended ) = ( $1, $2 );
				$freqs = $self->_get_extended_field_freqs( $std_field, $extended );
			}
		},
		locus => sub {
			$freqs = $self->_get_allele_freqs($field);
		},
		scheme_field => sub {
			if ( $field =~ /^s_(\d+)_(.+)$/x ) {
				my ( $scheme_id, $scheme_field ) = ( $1, $2 );
				$freqs = $self->_get_scheme_field_freqs( $scheme_id, $scheme_field );
			}
		}
	};
	if ( $methods->{$field_type} ) {
		$methods->{$field_type}->();
		foreach my $value (@$freqs) {
			$value->{'label'} = 'No value'
			  if !defined $value->{'label'} || ( ref $value->{'label'} && !@{ $value->{'label'} } );
		}
	} else {
		$logger->error('Invalid field type');
		return $freqs;
	}
	return $freqs;
}

sub _show_table {
	my ( $self, $field ) = @_;
	my $freqs         = $self->_get_field_values($field);
	my $count         = @$freqs;
	my $plural        = $count != 1 ? 's' : '';
	my $display_field = $field;
	$display_field =~ s/^s_\d+_//x;
	$display_field =~ s/^.*\.\.//x;
	$display_field =~ tr/_/ /;
	say qq(<h1>Breakdown by $display_field</h1>);
	say q(<div class="box" id="resultstable">);
	say qq(<p>$count value$plural.</p>);
	say qq(<table class="tablesorter" id="sortTable"><thead><tr><th>$display_field</th>)
	  . q(<th>Frequency</th><th>Percentage</th></tr></thead><tbody>);
	my $td    = 1;
	my $total = 0;
	$total += $_->{'value'} foreach @$freqs;

	foreach my $record (@$freqs) {
		local $" = q(; );
		print qq(<tr class="td$td"><td>);
		print ref $record->{'label'} ? qq(@{$record->{'label'}}) : $record->{'label'};
		print qq(</td><td>$record->{'value'}</td>);
		my $percentage = BIGSdb::Utils::decimal_place( ( $record->{'value'} / $total ) * 100, 2 );
		say qq(<td>$percentage</td></tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</tbody></table></div>);
	say q(</div>);
	return;
}

sub _get_text_table {
	my ( $self, $field ) = @_;
	my $freqs         = $self->_get_field_values($field);
	my $count         = @$freqs;
	my $plural        = $count != 1 ? 's' : '';
	my $display_field = $field;
	$display_field =~ s/^s_\d+_//x;
	$display_field =~ s/^.*\.\.//x;
	$display_field =~ tr/_/ /;
	my $buffer = qq($display_field\tFrequency\tPercentage\n);
	my $total  = 0;
	$total += $_->{'value'} foreach @$freqs;

	foreach my $record (@$freqs) {
		local $" = q(; );
		my $label = ref $record->{'label'} ? qq(@{$record->{'label'}}) : $record->{'label'};
		my $percentage = BIGSdb::Utils::decimal_place( ( $record->{'value'} / $total ) * 100, 2 );
		$buffer .= qq($label\t$record->{'value'}\t$percentage\n);
	}
	return $buffer;
}

sub _export_text {
	my ( $self, $field ) = @_;
	say $self->_get_text_table($field);
	return;
}

sub _export_excel {
	my ( $self, $field ) = @_;
	my $display_field = $field;
	$display_field =~ tr/_/ /;
	$display_field =~ s/^.*\.\.//x;
	$display_field =~ s/'//x;
	my $text_table = $self->_get_text_table($field);
	my $temp_file  = $self->make_temp_file($text_table);
	my $full_path  = "$self->{'config'}->{'secure_tmp_dir'}/$temp_file";
	my $name       = substr( $display_field, 0, 30 );                      #Excel tab names cannot be >31 characters.
	BIGSdb::Utils::text2excel(
		$full_path,
		{
			stdout    => 1,
			worksheet => $name,
			tmp_dir   => $self->{'config'}->{'secure_tmp_dir'}
		}
	);
	unlink $full_path;
	return;
}

sub _export_fasta {
	my ( $self, $locus ) = @_;
	my $freqs      = $self->_get_field_values($locus);
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( !$locus_info ) {
		say 'Invalid locus selected.';
		return;
	}
	my @filtered_ids;
	my %invalid = map { $_ => 1 } ( 'No value', 'N', '0' );
	foreach my $allele (@$freqs) {
		next if $invalid{ $allele->{'label'} };
		next if $locus_info->{'allele_id_format'} eq 'integer' && !BIGSdb::Utils::is_int( $allele->{'label'} );
		push @filtered_ids, $allele->{'label'};
	}
	my $locus_obj = $self->{'datastore'}->get_locus($locus);
	foreach
	  my $allele_id ( sort { $locus_info->{'allele_id_format'} eq 'integer' ? $a <=> $b : $a cmp $b } @filtered_ids )
	{
		my $seq_ref = $locus_obj->get_allele_sequence($allele_id);
		my $formatted_seq_ref = BIGSdb::Utils::break_line( $seq_ref, 60 );
		$$formatted_seq_ref = q(-) if length $$formatted_seq_ref == 0;
		say qq(>$allele_id);
		say $$formatted_seq_ref;
	}
	return;
}

sub run {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $id_table = $self->_create_id_table;
	if ( $q->param('field') ) {
		$self->_ajax( scalar $q->param('field') );
		return;
	} elsif ( $q->param('export') && $q->param('format') ) {
		$self->_export( scalar $q->param('export'), scalar $q->param('format') );
		return;
	}
	my ( $fields, $labels ) = $self->_get_fields;
	say q(<h1>Field breakdown of dataset</h1>);
	say q(<div class="box" id="resultspanel" style="position:relative">);
	my $record_count = BIGSdb::Utils::commify( $self->_get_id_count );
	say qq(<p><b>Isolate records:</b> $record_count</p>);
	say q(<fieldset><legend>Field selection</legend><ul>);
	say q(<li><label for="field">Select field:</label>);
	say $q->popup_menu( - name => 'field', id => 'field', values => $fields, labels => $labels );
	say q(</li><li style="margin-top:0.5em"><label for="field_type">List:</label>);
	my $set_id = $self->get_set_id;
	my $loci   = $self->{'datastore'}->get_loci( { set_id => $set_id, analysis_pref => 1 } );
	my $types  = [qw(fields)];
	push @$types, 'loci' if @$loci;
	my $schemes = $self->{'datastore'}->get_scheme_list( { with_pk => 1, set_id => $set_id, analysis_pref => 1 } );
	push @$types, 'schemes' if @$schemes;
	say $q->radio_group( -name => 'field_type', -values => $types, -default => 'fields' );
	say q(</li></ul></fieldset>);
	say q(<div id="waiting" style="position:absolute;top:15em;left:1em;display:none">)
	  . q(<span class="wait_icon fas fa-sync-alt fa-spin fa-2x"></span></div>);
	say q(<div id="bb_chart" style="min-height:400px">);
	$self->print_loading_message;
	say q(</div>);
	say q(<div id="map" style="max-width:800px;margin-left:auto;margin-right:auto"></div>);
	$self->_print_map_controls;
	$self->_print_pie_controls;
	$self->_print_bar_controls;
	$self->_print_line_controls;
	say q(<div style="clear:both"></div>);
	$self->_print_export_buttons;
	say q(</div>);
	return;
}

sub _print_export_buttons {
	my ($self) = @_;
	say $self->get_export_buttons(
		{ table => 1, excel => 1, text => 1, fasta => 1, image => 1, hide_div => 1, hide => ['fasta'] } );
	return;
}

sub _print_map_controls {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset id="map_controls" class="bb_controls" )
	  . q(style="position:absolute;top:1em;right:1em;display:none"><legend>Controls</legend>);
	say q(<ul>);
	$self->_print_chart_types;
	say q(<style>.theme.fa-square {text-shadow: 2px 2px 2px #999;font-size:1.8em;margin-right:0.2em;cursor:pointer})
	  . q(</style>);
	say q(<li><span style="float:left;margin-right:0.5em">Theme:</span>)
	  . q(<div style="display:inline-block">)
	  . q(<span id="theme_grey" style="color:#636363" class="theme fas fa-square"></span>)
	  . q(<span id="theme_blue" style="color:#3182bd" class="theme fas fa-square"></span>)
	  . q(<span id="theme_green" style="color:#31a354" class="theme fas fa-square"></span>)
	  . q(<span id="theme_purple" style="color:#756bb1" class="theme fas fa-square"></span>)
	  . q(<span id="theme_orange" style="color:#e6550d" class="theme fas fa-square"></span>)
	  . q(<span id="theme_red" style="color:#de2d26" class="theme fas fa-square"></span>)
	  . q(<span id="expand_themes" style="cursor:pointer"><span id="themes_hidden" class="fas fa-chevron-right"></span>)
	  . q(<span id="themes_shown" class="fas fa-chevron-down" style="display:none"></span></span>)
	  . q(<br />)
	  . q(<span id="expanded_themes" style="display:none">)
	  . q(<span id="theme_blue_green" style="color:#b2e2e2;text-shadow:2px 2px 2px #006d2c" )
	  . q(class="theme fas fa-square"></span>)
	  . q(<span id="theme_blue_purple" style="color:#b3cde3;text-shadow:2px 2px 2px #810f7c" )
	  . q(class="theme fas fa-square"></span>)
	  . q(<span id="theme_green_blue" style="color:#bae4bc;text-shadow:2px 2px 2px #0868ac" )
	  . q(class="theme fas fa-square"></span>)
	  . q(<span id="theme_orange_red" style="color:#fdcc8a;text-shadow:2px 2px 2px #b30000" )
	  . q(class="theme fas fa-square"></span>)
	  . q(<span id="theme_purple_blue" style="color:#bdc9e1;text-shadow:2px 2px 2px #045a8d" )
	  . q(class="theme fas fa-square"></span>)
	  . q(<span id="theme_purple_blue_green" style="color:#bdc9e1;text-shadow:2px 2px 2px #016c59" )
	  . q(class="theme fas fa-square"></span>)
	  . q(<br />)
	  . q(<span id="theme_purple_red" style="color:#d7b5d8;text-shadow:2px 2px 2px #980043" )
	  . q(class="theme fas fa-square"></span>)
	  . q(<span id="theme_red_purple" style="color:#fbb4b9;text-shadow:2px 2px 2px #7a0177" )
	  . q(class="theme fas fa-square"></span>)
	  . q(<span id="theme_yellow_green" style="color:#c2e699;text-shadow:2px 2px 2px #006837" )
	  . q(class="theme fas fa-square"></span>)
	  . q(<span id="theme_yellow_green_blue" style="color:#a1dab4;text-shadow:2px 2px 2px #253494" )
	  . q(class="theme fas fa-square"></span>)
	  . q(<span id="theme_yellow_orange_brown" style="color:#fed98e;text-shadow:2px 2px 2px #993404" )
	  . q(class="theme fas fa-square"></span>)
	  . q(<span id="theme_yellow_orange_red" style="color:#fecc5c;text-shadow:2px 2px 2px #bd0026" )
	  . q(class="theme fas fa-square"></span>)
	  . q(</span></div></li>);
	say q(<li><label for="height">Range:</label>);
	say q(<div id="colour_range" style="display:inline-block;width:12em;margin-left:0.5em"></div></li>);
	say q(<li><label for="projection">Projection:</label>);
	say $q->popup_menu(
		-id     => 'projection',
		-values => [
			'Azimuthal Equal Area', 'Conic Equal Area', 'Equirectangular', 'Mercator',
			'Natural Earth',        'Robinson',         'Stereographic',   'Times',
			'Transverse Mercator',  'Winkel tripel'
		],
		-default => 'Natural Earth'
	);
	say q(</li>);
	say q(</ul></fieldset>);
	return;
}

sub _print_pie_controls {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset id="pie_controls" class="bb_controls" )
	  . q(style="position:absolute;top:1em;right:1em;display:none"><legend>Controls</legend>);
	say q(<ul>);
	say q(<li><label for="segments">Max segments:</label>);
	say q(<div id="segments" style="display:inline-block;width:8em;margin-left:0.5em"></div>);
	say q(<div id="segments_display" style="display:inline-block;width:3em;margin-left:1em"></div></li>);
	$self->_print_chart_types;
	say q(</ul></fieldset>);
	return;
}

sub _print_chart_types {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<li>);
	say q(<a class="chart_icon transform_to_pie" title="Pie chart" style="display:none">)
	  . q(<span class="chart_icon fas fa-2x fa-chart-pie" style="color:#448"></span></a>);
	say q(<a class="chart_icon transform_to_donut" title="Donut chart" style="display:none">)
	  . q(<span class="chart_icon fas fa-2x fa-dot-circle" style="color:#848"></span></a>);
	say q(<a class="chart_icon transform_to_map" title="Map chart" style="display:none">)
	  . q(<span class="chart_icon fas fa-2x fa-globe-africa" style="color:#484"></span></a>);
	say q(<a class="chart_icon transform_to_bar" title="Bar chart (discrete values)" style="display:none">)
	  . q(<span class="chart_icon fas fa-2x fa-chart-bar" style="color:#484"></span></a>);
	say q(<a class="chart_icon transform_to_line" title="Line chart (cumulative values)" style="display:none">)
	  . q(<span class="chart_icon fas fa-2x fa-chart-line" style="color:#844"></span></a>);
	say q(</li>);
	return;
}

sub _print_bar_controls {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset id="bar_controls" class="bb_controls" )
	  . q(style="position:absolute;top:1em;right:1em;display:none"><legend>Controls</legend>);
	say q(<ul>);
	say q(<li><label for="orientation">Orientation:</label>);
	say $q->radio_group( -name => 'orientation', -values => [qw(horizontal vertical)], -default => 'horizontal' );
	say q(</li>);
	say q(<li><label for="height">Height:</label>);
	say q(<div id="bar_height" style="display:inline-block;width:8em;margin-left:0.5em"></div></li>);
	say q(</ul></fieldset>);
	return;
}

sub _print_line_controls {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset id="line_controls" class="bb_controls" )
	  . q(style="position:absolute;top:1em;right:1em;display:none"><legend>Controls</legend>);
	say q(<ul>);
	say q(<li><label for="height">Height:</label>);
	say q(<div id="line_height" style="display:inline-block;width:8em;margin-left:0.5em"></div></li>);
	$self->_print_chart_types;
	say q(</ul></fieldset>);
	return;
}

sub _get_fields {
	my ($self)     = @_;
	my $set_id     = $self->get_set_id;
	my $is_curator = $self->is_curator;
	my $field_list =
	  $self->{'xmlHandler'}->get_field_list( { no_curate_only => !$is_curator } );
	my $eav_field_list = $self->{'datastore'}->get_eav_fieldnames;
	my $expanded_list  = [];
	my $labels         = {};
	my $no_show        = $self->_get_no_show_fields;
	my $extended       = $self->get_extended_attributes;
	foreach my $field ( @$field_list, @$eav_field_list ) {
		next if $no_show->{$field};
		push @$expanded_list, $field;
		if ( ref $extended->{$field} eq 'ARRAY' ) {
			foreach my $attribute ( @{ $extended->{$field} } ) {
				push @$expanded_list, "${field}..$attribute";
				( $labels->{"${field}..$attribute"} = $attribute ) =~ tr/_/ /;
			}
		} else {
			my $label = $field;
			$label =~ tr/_/ /;
			$labels->{$field} = $label;
		}
	}
	return ( $expanded_list, $labels );
}

sub _get_no_show_fields {
	my ($self) = @_;
	my %no_show = map { $_ => 1 } split /,/x, ( $self->{'system'}->{'noshow'} // q() );
	$no_show{$_} = 1 foreach qw(id sender curator);
	$no_show{ $self->{'system'}->{'labelfield'} } = 1;
	return \%no_show;
}

sub _get_id_count {
	my ($self) = @_;
	return $self->{'datastore'}->run_query('SELECT COUNT(*) FROM id_list');
}

sub _get_query_params {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $params = [];
	foreach my $param (qw(query_file list_file datatype temp_table_file)) {
		push @$params, qq($param=) . $q->param($param) if $q->param($param);
	}
	return $params;
}

sub _get_fields_js {
	my ($self) = @_;
	my $field_attributes = $self->{'xmlHandler'}->get_all_field_attributes;
	my %types = map { $field_attributes->{$_} => $field_attributes->{$_}->{'type'} } keys %$field_attributes;
	my @type_values;
	my %allowed_types = map { $_ => 1 } qw(integer text float date);
	foreach my $field ( keys %$field_attributes ) {
		my $type = lc( $field_attributes->{$field}->{'type'} );
		$type = 'integer' if $type eq 'int';
		$type = 'text'    if $type =~ /^bool/x;
		if ( $type eq 'date' && ( $field_attributes->{$field}->{'multiple'} // q() ) eq 'yes' ) {
			$type = 'text';
		}
		if ( !$allowed_types{$type} ) {
			$logger->error("Field $field has an unrecognized type: $type");
			$type = 'text';
		}
		push @type_values, qq('$field':'$type');
	}
	local $" = qq(,\n\t);
	my ($fields) = $self->_get_fields;
	my $buffer = q(var field_list=) . encode_json($fields) . qq(;\n);
	$buffer .= qq(\tvar field_types = {@type_values};\n);
	if ( $self->_has_country_optlist ) {
		my @map_fields = qw(country country..continent);
		local $" = q(',');
		$buffer .= qq(var map_fields = ['@map_fields'];\n);
	} else {
		$buffer .= qq(var map_fields = [];\n);
	}
	return $buffer;
}

sub _get_loci_js {

	#Get all loci irrespective of whether analysis_prefs flag is set.
	#The list will be updated by an AJAX call, but we cannot tell who is logged in
	#when the Javascript is being prepared as this goes in the header.
	my ($self) = @_;
	my $loci = $self->{'datastore'}->get_loci;
	return q(var locus_list=) . encode_json($loci);
}

sub _get_schemes_js {

	#Get all schemes irrespective of whether analysis_prefs flag is set.
	#The list will be updated by an AJAX call, but we cannot tell who is logged in
	#when the Javascript is being prepared as this goes in the header.
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id, with_pk => 1 } );
	my $fields = [];
	foreach my $scheme (@$schemes) {
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields( $scheme->{'id'} );
		foreach my $scheme_field (@$scheme_fields) {
			push @$fields,
			  {
				field => "s_$scheme->{'id'}_$scheme_field",
				label => "$scheme_field ($scheme->{'name'})"
			  };
		}
	}
	@$fields = sort { lc( $a->{'label'} ) cmp lc( $b->{'label'} ) } @$fields;
	return q(var scheme_list=) . encode_json($fields);
}

sub get_plugin_javascript {
	my ($self)              = @_;
	my $has_valid_countries = $self->_has_country_optlist;
	my $query_params        = $self->_get_query_params;
	my $guid                = $self->get_guid;
	my ( $theme, $projection );
	eval {
		$theme =
		  $self->{'prefstore'}->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'FieldBreakdown', 'theme' );
		$projection = $self->{'prefstore'}
		  ->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'FieldBreakdown', 'projection' );
	};
	$theme      //= 'theme_green';
	$projection //= 'Natural Earth';
	local $" = q(&);
	my $url = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=plugin&name=FieldBreakdown);
	my $plugin_prefs_ajax_url =
	  qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=ajaxPrefs&plugin=FieldBreakdown);
	my $prefs_ajax_url = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=ajaxPrefs);
	my $param_string = @$query_params ? qq(&@$query_params) : q();
	$url .= $param_string;
	my $types_js   = $self->_get_fields_js;
	my $loci_js    = $self->_get_loci_js;
	my $schemes_js = $self->_get_schemes_js;
	my $buffer     = <<"JS";
var height = 400;
var segments = 20;
var rotate = 0;
var pie = 1;
var line = 1;
var fasta = 0;
var theme = "$theme";
var projection = "$projection";
var url = "$url";
var prefs_ajax_url = "$plugin_prefs_ajax_url";

$types_js	
$loci_js
$schemes_js

JS
	return $buffer;
}

sub _ajax {
	my ( $self, $field ) = @_;
	my $q     = $self->{'cgi'};
	my $freqs = $self->_get_field_values($field);
	say to_json($freqs);
	return;
}

sub _get_field_freqs {
	my ( $self, $field, $options ) = @_;
	my $qry = "SELECT $field AS label,COUNT(*) AS value FROM $self->{'system'}->{'view'} v "
	  . 'JOIN id_list i ON v.id=i.value ';
	$qry .= 'GROUP BY label';
	my $order = $options->{'order'} ? $options->{'order'} : 'value DESC';
	$qry .= " ORDER BY $order";
	my $values = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	if ( $field eq 'country' ) {
		my $countries = COUNTRIES;
		foreach my $value (@$values) {
			$value->{'iso3'} = $countries->{ $value->{'label'} }->{'iso3'} // q(XXX);
		}
	}
	my $att = $self->{'xmlHandler'}->get_field_attributes($field);
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
		return $new_return_list;
	}
	return $values;
}

sub _get_eav_field_freqs {
	my ( $self, $field, $options ) = @_;
	my $eav_table = $self->{'datastore'}->get_eav_field_table($field);
	my $qry       = "SELECT e.value AS label,COUNT(*) AS value FROM $eav_table e RIGHT JOIN id_list i ON "
	  . 'e.isolate_id=i.value AND e.field=?';
	$qry .= ' GROUP BY label';
	my $order = $options->{'order'} ? $options->{'order'} : 'value DESC';
	$qry .= " ORDER BY $order";
	my $values = $self->{'datastore'}->run_query( $qry, $field, { fetch => 'all_arrayref', slice => {} } );
	return $values;
}

sub _get_extended_field_freqs {
	my ( $self, $field, $extended, $options ) = @_;
	my $qry =
	    "SELECT e.value AS label,COUNT(*) AS value FROM $self->{'system'}->{'view'} v "
	  . "JOIN id_list i ON v.id=i.value LEFT JOIN isolate_value_extended_attributes e ON v.$field=e.field_value "
	  . 'AND (e.isolate_field,e.attribute)=(?,?) GROUP BY label';
	my $order = $options->{'order'} ? $options->{'order'} : 'value DESC';
	$qry .= " ORDER BY $order";
	my $values =
	  $self->{'datastore'}->run_query( $qry, [ $field, $extended ], { fetch => 'all_arrayref', slice => {} } );
	if ( $extended eq 'continent' ) {
		foreach my $value (@$values) {
			my $label = $value->{'label'} // 'XXX';
			$label =~ tr/ /_/;
			$value->{'continent'} = $label;
		}
	}
	return $values;
}

sub _get_allele_freqs {
	my ( $self, $locus ) = @_;
	my $qry =
	    "SELECT a.allele_id AS label,COUNT(*) AS value FROM $self->{'system'}->{'view'} v "
	  . 'JOIN id_list i ON v.id=i.value LEFT JOIN allele_designations a ON a.isolate_id=v.id AND a.locus=? '
	  . 'GROUP BY label ORDER BY value DESC';
	my $values =
	  $self->{'datastore'}->run_query( $qry, $locus, { fetch => 'all_arrayref', slice => {} } );
	return $values;
}

sub _get_scheme_field_freqs {
	my ( $self, $scheme_id, $field ) = @_;
	my $scheme_table = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
	my $qry =
	    "SELECT s.$field AS label,COUNT(*) AS value FROM $self->{'system'}->{'view'} v "
	  . "JOIN $scheme_table s ON v.id=s.id JOIN id_list i ON v.id=i.value "
	  . 'GROUP BY label ORDER BY value DESC';
	my $values =
	  $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	return $values;
}

sub _create_id_table {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $ids        = [];
	if ($query_file) {
		$ids = $self->get_id_list( 'id', $query_file );
	} else {
		$ids = $self->{'datastore'}->run_query( "SELECT id FROM $self->{'system'}->{'view'} WHERE new_version IS NULL",
			undef, { fetch => 'col_arrayref' } );
	}
	$self->{'datastore'}->create_temp_list_table_from_array( 'int', $ids, { table => 'id_list' } );
	return;
}
1;
