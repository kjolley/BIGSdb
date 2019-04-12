#FieldBreakdown.pm - FieldBreakdown plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2018-2019, University of Oxford
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
		name        => 'Field Breakdown',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Breakdown of query results by field',
		category    => 'Breakdown',
		buttontext  => 'Fields',
		menutext    => 'Single field',
		module      => 'FieldBreakdown',
		version     => '2.2.0',
		dbtype      => 'isolates',
		section     => 'breakdown,postquery',
		url         => "$self->{'config'}->{'doclink'}/data_analysis.html#field-breakdown",
		input       => 'query',
		order       => 10
	);
	return \%att;
}

sub get_initiation_values {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $values = { c3 => 1, filesaver => 1, noCache => 0, 'jQuery.tablesort' => 1, pluginJS => 'FieldBreakdown.js' };
	if ($self->_has_country_optlist){
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
	my $field_type = $self->_get_field_type($field);
	my $freqs      = [];
	my $methods    = {
		field => sub {
			my $att = $self->{'xmlHandler'}->get_field_attributes($field);
			$freqs =
			  $self->_get_field_freqs( $field,
				$att->{'type'} =~ /^(?:int|date)/x ? { order => 'label ASC', no_null => 1 } : undef );
		},
		eav_field => sub {
			my $att = $self->{'datastore'}->get_eav_field($field);
			$freqs =
			  $self->_get_eav_field_freqs( $field,
				$att->{'value_format'} =~ /^(?:int|date)/x ? { order => 'label ASC', no_null => 1 } : undef );
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
			$value->{'label'} = 'No value' if !defined $value->{'label'};
		}
	} else {
		$logger->error('Invalid field type');
		return;
	}
	return $freqs;
}

sub _show_table {
	my ( $self, $field ) = @_;
	my $freqs  = $self->_get_field_values($field);
	my $count  = @$freqs;
	my $plural = $count != 1 ? 's' : '';
	my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
	my $display_field = $metafield // $field;
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
		say qq(<tr class="td$td"><td>$record->{'label'}</td><td>$record->{'value'}</td>);
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
	my $freqs  = $self->_get_field_values($field);
	my $count  = @$freqs;
	my $plural = $count != 1 ? 's' : '';
	my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
	my $display_field = $metafield // $field;
	$display_field =~ s/^s_\d+_//x;
	$display_field =~ s/^.*\.\.//x;
	$display_field =~ tr/_/ /;
	my $buffer = qq($display_field\tFrequency\tPercentage\n);
	my $total  = 0;
	$total += $_->{'value'} foreach @$freqs;

	foreach my $record (@$freqs) {
		my $percentage = BIGSdb::Utils::decimal_place( ( $record->{'value'} / $total ) * 100, 2 );
		$buffer .= qq($record->{'label'}\t$record->{'value'}\t$percentage\n);
	}
	return $buffer;
}

sub _export_text {
	my ( $self, $field ) = @_;
	say $self->_get_text_table($field);
	return;
}

sub _export_excel {
	my ( $self,    $field )     = @_;
	my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
	my $display_field = $metafield // $field;
	$display_field =~ tr/_/ /;
	$display_field =~ s/^.*\.\.//x;
	$display_field =~ s/'//x;
	my $text_table = $self->_get_text_table($field);
	my $temp_file  = $self->make_temp_file($text_table);
	my $full_path  = "$self->{'config'}->{'secure_tmp_dir'}/$temp_file";
	BIGSdb::Utils::text2excel(
		$full_path,
		{
			stdout    => 1,
			worksheet => "$display_field breakdown",
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
		$self->_ajax( $q->param('field') );
		return;
	} elsif ( $q->param('export') && $q->param('format') ) {
		$self->_export( $q->param('export'), $q->param('format') );
		return;
	}
	my ( $fields, $labels ) = $self->_get_fields;
	say q(<h1>Field breakdown of dataset</h1>);
	say q(<div class="box" id="resultspanel">);
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
	say q(<div id="c3_chart" style="min-height:400px">);
	
	$self->print_loading_message;
	say q(</div>);
	say q(<div id="map"></div>);
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
		{ table => 1, excel => 1, text => 1, fasta => 1, image => 1, hide_div => 1, hide => ['fasta'] } )
	  ;
	return;
}

sub _print_map_controls {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset id="map_controls" class="c3_controls" )
	  . q(style="position:absolute;top:6em;right:1em;display:none"><legend>Controls</legend>);
	say q(<ul>);
	$self->_print_chart_types;
	say q(</ul></fieldset>);
	return;
}

sub _print_pie_controls {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset id="pie_controls" class="c3_controls" )
	  . q(style="position:absolute;top:6em;right:1em;display:none"><legend>Controls</legend>);
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
	say q(<fieldset id="bar_controls" class="c3_controls" )
	  . q(style="position:absolute;top:6em;right:1em;display:none"><legend>Controls</legend>);
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
	say q(<fieldset id="line_controls" class="c3_controls" )
	  . q(style="position:absolute;top:6em;right:1em;display:none"><legend>Controls</legend>);
	say q(<ul>);
	say q(<li><label for="height">Height:</label>);
	say q(<div id="line_height" style="display:inline-block;width:8em;margin-left:0.5em"></div></li>);
	$self->_print_chart_types;
	say q(</ul></fieldset>);
	return;
}

sub _get_fields {
	my ($self)         = @_;
	my $set_id         = $self->get_set_id;
	my $metadata_list  = $self->{'datastore'}->get_set_metadata($set_id);
	my $field_list     = $self->{'xmlHandler'}->get_field_list($metadata_list);
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
			$label =~ s/^$_://x foreach @$metadata_list;
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
		if ( !$allowed_types{$type} ) {
			$logger->error("Field $field has an unrecognized type: $type");
			$type = 'text';
		}
		push @type_values, qq('$field':'$type');
	}
	local $" = qq(,\n\t);
	my ($fields) = $self->_get_fields;
	my $buffer = q(var fields=) . encode_json($fields) . qq(;\n);
	$buffer .= qq(\tvar field_types = {@type_values};\n);
	if ($self->_has_country_optlist){
		my @map_fields;
		foreach my $field (qw(country)){
			push @map_fields,$field if $self->{'xmlHandler'}->is_field($field);
		}
		if (@map_fields){
			local $" = q(',');
			$buffer.=qq(var map_fields = ['@map_fields'];\n);
		}
	}
	return $buffer;
}

sub _get_loci_js {

	#Get all loci irrespective of whether analysis_prefs flag is set.
	#The list will be updated by an AJAX call, but we cannot tell who is logged in
	#when the Javascript is being prepared as this goes in the header.
	my ($self) = @_;
	my $loci = $self->{'datastore'}->get_loci;
	return q(var loci=) . encode_json($loci);
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
	return q(var schemes=) . encode_json($fields);
}

sub get_plugin_javascript {
	my ($self) = @_;
	my $has_valid_countries = $self->_has_country_optlist;
	my $query_params = $self->_get_query_params;
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
var url = "$url";
var prefs_ajax_url = "$plugin_prefs_ajax_url";

$types_js	
$loci_js
$schemes_js

\$(function () {
	\$.ajax({
		url: prefs_ajax_url
	})
	.done(function(data) {
		var prefObj = JSON.parse(data);
		if (prefObj.height){height=prefObj.height}; 
		if (prefObj.segments){segments=prefObj.segments};
		if (prefObj.pie == 0){pie=0} 	
  	})
  	.fail(function(response){
  		console.log(response);
  	});

  	\$('input[name="field_type"][value="fields"]').prop("checked", true);
  	var field = \$("#field").val();
	var initial_url = url + "&field=" + field;
	var rotate = is_vertical();
	

	get_ajax_prefs();
 	if (map_fields.includes(field)){
 		load_map(initial_url,field);
 	} else if (field_types[field] == 'integer'){
		load_bar(initial_url,field,rotate);
	} else if (field_types[field] == 'date'){
		load_line(initial_url,field,line);
	} else {
		load_pie(initial_url,field,segments);
	}	
	
	\$("#field").on("change",function(){
		\$("#c3_chart").css("min-height", "400px");
		d3.selectAll('svg').remove();
		\$("div#waiting").css("display","block");
		\$(".c3_controls").css("display", "none");			
		var rotate = is_vertical();
		var field = \$('#field').val();
		var new_url = url + "&field=" + field;
		if (map_fields.includes(field)){
 			load_map(new_url,field);
		} else if (field_types[field] == 'integer'){
			load_bar(new_url,field,rotate);
		} else if (field_types[field] == 'date'){
			load_line(new_url,field,line);
		} else {
			load_pie(new_url,field,segments);
		}	
    }); 
    
   	var field_type_radio = \$('input[name="field_type"]');
	field_type_radio.on("change",function(){
		var field_type = get_field_type();
		\$("#field").empty();
		var list = {
			fields: fields,
			loci: loci,
			schemes: schemes
		};
		
		\$.each(list[field_type], function(index, item){
			var value;
			var label;
			if (field_type == 'schemes'){
				label = item.label;
				value = item.field;
			} else {
				label = item.replace(/^.+\\.\\./, "");
				value = item;
			}
			jQuery('<option/>', {
       			value: value,
       			html: label
       		}).appendTo("#field"); 
		});
		\$("#field").change();
		fasta = field_type == 'loci' ? 1 : 0;
	});  

	position_controls();
	\$(window).resize(function() {
		position_controls();
	});
	
	\$("#export_image").off("click").click(function(){
		//fix back fill
		d3.select("#c3_chart").selectAll("path").attr("fill","none");	
		//fix no axes
		d3.select("#c3_chart").selectAll("path.domain").attr("stroke","black");
		//fix no tick
		d3.select("#c3_chart").selectAll(".tick line").attr("stroke","black");
		d3.select("#c3_chart").selectAll(".c3-axis-y2").attr("display","none");
		//Annoying 2nd x-axis
		//Hide both, then selectively show the first one.
		d3.select("#c3_chart").selectAll(".c3-axis-x").attr("display","none");
		d3.select("#c3_chart").select(".c3-axis-x").attr("display","inline");
		
		//map
		d3.select("#map").selectAll("path").attr("fill","none");	
		d3.select("#map").selectAll("path").attr("stroke","#444");
		d3.select("#map").selectAll(".background").attr("fill","none");
		var svg = d3.select("svg")
			.attr("xmlns","http://www.w3.org/2000/svg")
			.node().parentNode.innerHTML;
		svg = svg.replace(/<\\/svg>.*\$/,"</svg>");
		var blob = new Blob([svg],{type: "image/svg+xml"});		
		var filename = \$("#field").val().replace(/^.+\\.\\./, "") + ".svg";
		saveAs(blob, filename);
	});
});

function get_ajax_prefs(){
	\$.ajax({
  	url: prefs_ajax_url + "&loci=1"
  	}).done(function(data){
 		loci = JSON.parse(data);
   	}).fail(function(response){
  		console.log(response);
  	});
  	\$.ajax({
  		url: prefs_ajax_url + "&scheme_fields=1"
  	}).done(function(data){
 		schemes = JSON.parse(data);
   	}).fail(function(response){
  		console.log(response);
  	});
}

function position_controls(){
	if (\$(window).width() < 800){
		\$(".c3_controls").css("position", "static");
		\$(".c3_controls").css("float", "left");
	} else {
		\$(".c3_controls").css("position", "absolute");
		\$(".c3_controls").css("clear", "both");
	}
}

function is_vertical() {
	var orientation_radio = \$('input[name="orientation"]');
	var checked = orientation_radio.filter(function() {
	    	return \$(this).prop('checked');
	  	});
	var orientation = checked.val();
	return orientation == 'vertical' ? 1 : 0;
}

function get_field_type() {
	var field_type_radio = \$('input[name="field_type"]');
	var checked = field_type_radio.filter(function() {
		return \$(this).prop('checked');
	});
	var field_type = checked.val();
	return field_type;
}

function load_map(url,field){
	\$("#c3_chart").html("");	
	var colours = colorbrewer.Greens[5];
	
	
	d3.json(url).then(function(data) {
		var max = get_range_max(data);
		console.log(max);
		var	map = d3.geomap.choropleth()
			.geofile('/javascript/topojson/countries.json')
			.colors(colours)
			.column('value')
			.format(d3.format(",d"))
			.legend({
				width : 50,
				height : 120
			})
			.projection(d3.geoNaturalEarth)
			.duration(1000)
			.domain([ 0, max ])
			.valueScale(d3.scaleQuantize)
			.unitId('iso3')
			.postUpdate(function(){finished_map(url,field)});
		var selection = d3.select('#map').datum(data);
		map.draw(selection);
	});
}

//Choose max value so that ~5% of records are in top fifth.
function get_range_max(data) {
	var records = data.length;
	var target = parseInt(0.05 * records);
	var multiplier = 10;
	var max;
	
	while (true){
		var test = [1,2,5,10];
		for (var i = 0; i < test.length; i++) { 
			max = test[i] * multiplier;
			var top_division_start = max * 4 / 5;
			var in_top_fifth = 0;
			for (var j = 0; j < data.length; j++) { 
				if (data[j].value >= top_division_start){
					in_top_fifth++;
				}
			}
			if (in_top_fifth <= target){
				return max;
			}
		}
		multiplier = multiplier * 10;
		if (max > 10000000){
			return max;
		}
	}
}


function finished_map(url,field){
	\$("div#waiting").css("display","block");
	\$("#bar_controls").css("display","none");
	\$("#line_controls").css("display","none");
	\$("#pie_controls").css("display","none");
	\$(".transform_to_pie").css("display","inline");
	\$(".transform_to_donut").css("display","inline");
	\$(".transform_to_bar").css("display","none");
	\$(".transform_to_line").css("display","none");
	\$("#map_controls").css("display","block");
	\$(".transform_to_donut").off("click").click(function(){
		\$("div#waiting").css("display","block");
		d3.selectAll("svg").remove();
		load_pie(url,field,segments);		
		pie = 0;
		\$("#c3_chart").css("min-height", "400px");
	});
	\$(".transform_to_pie").off("click").click(function(){
		\$("div#waiting").css("display","block");
		d3.selectAll("svg").remove();
		load_pie(url,field,segments);
		pie = 1;
		\$("#c3_chart").css("min-height", "400px");
	});
	show_export_options();
	\$("div#waiting").css("display","none");
	\$("#c3_chart").css("min-height", 0);
	\$(".legend-bg").css("fill","none");	
}

function load_pie(url,field,max_segments) {
	\$("#bar_controls").css("display", "none");
	\$("#line_controls").css("display", "none");
	\$("#map_controls").css("display","none");
	var title = field.replace(/^.+\\.\\./, "");
	title = title.replace(/^s_\\d+_/,"");
	var f = d3.format(".1f");
	d3.json(url).then (function(jsonData) {			
		var data = pie_json_to_cols(jsonData,max_segments);
		
		//Load all data first otherwise a glitch causes one segment to be missing
		//when increasing number of segments.
		var all_data = pie_json_to_cols(jsonData,50);
		
		//Need to create 'Others' segment otherwise it won't display properly
		//if needed when reducing segment count.
		all_data.columns.push(['Others',0]);
		
		var plural = data.count == 1 ? "" : "s";
		title += " (" + data.count + " value" + plural + ")";
		var chart = c3.generate({
			bindto: '#c3_chart',
			title: {
				text: title
			},
			data: {
				columns: all_data.columns,
				type: pie ? 'pie' : 'donut',
				order: null,
				colors: {
					'Others': '#aaa'
				}
			},
			pie: {
				label: {
					show: true					
				},
				expand: false,
			},
			legend: {
				show: true,
				position: 'bottom'
			},
			size: {
				height: 500
			},
			tooltip: {
				format: {
					value: function (value, ratio, id){
						return value + " (" + f(ratio * 100) + "%)";
					}
				}
			}
		});
		chart.unload();
		chart.load({
			columns: data.columns,
		});	
		
		\$("#segments").on("slidechange",function(){
			var new_segments = \$("#segments").slider('value');
			\$("#segments_display").text(new_segments);
			if (segments != new_segments){
				set_prefs('segments',new_segments);
			}
			segments = new_segments;
			var data = pie_json_to_cols(jsonData,segments);
			chart.unload();
			chart.load({
				columns: data.columns,
			});	

		});
		if (max_segments != segments){
			var data = pie_json_to_cols(jsonData,segments);
			chart.unload();
			chart.load({
				columns: data.columns,
			});
		}
		\$(".transform_to_donut").off("click").click(function(){
			chart.transform('donut');
			\$(".transform_to_donut").css("display","none");
			\$(".transform_to_pie").css("display","inline");
			pie = 0;
			set_prefs('pie',0);
		});
		\$(".transform_to_pie").off("click").click(function(){
			chart.transform('pie');
			\$(".transform_to_pie").css("display","none");
			\$(".transform_to_donut").css("display","inline");
			pie = 1;
			set_prefs('pie',1);
		});
		\$(".transform_to_map").off("click").click(function(){
			\$(".transform_to_map").css("display","none");
			
			load_map(url,field);
			\$(".transform_to_pie").css("display","inline");
			\$(".transform_to_donut").css("display","inline");
			pie = 1;
			set_prefs('pie',1);
		});
		\$("#segment_control").css("display","block");
		\$("#segments").slider({min:5,max:50,value:segments});
		\$("#segments_display").text(segments);
		\$(".transform_to_map").css("display", map_fields.includes(field) ? "inline" : "none");
		\$(".transform_to_pie").css("display",pie ? "none" : "inline");
		\$(".transform_to_donut").css("display",pie ? "inline": "none");
		\$(".transform_to_bar").css("display","none");
		\$(".transform_to_line").css("display","none");
		\$("#pie_controls").css("display","block");
		show_export_options();
		\$("div#waiting").css("display","none");
	},function(error) {
		console.log(error);
		\$("#c3_chart").html('<p style="text-align:center;margin-top:5em">'
		 + '<span class="error_message">Error accessing data.</span></p>');
	});
}

function pie_json_to_cols(jsonData,segments){
	var columns = [];
	var first_other = [];
	var count = 0;
	var others = 0;
	var other_fields = 0;
	jsonData.forEach(function(e) {
		e.label = e.label.toString(); 
		count++;
		if (count >= segments){
			others += e.value;
			other_fields++;
			if (count == segments){
				first_other = [e.label, e.value];
			}
		} else {
			columns.push([e.label, e.value]);
		}
	}) 
	if (other_fields == 1){
		columns.push(first_other);
	} else if (other_fields > 1){
		columns.push(['Others',others]);
	}
	return {columns: columns, count: count};  
}

function load_line(url,field,cumulative) {
	\$("#bar_controls").css("display", "none");
	\$("#pie_controls").css("display", "none");
	\$("#map_controls").css("display","none");
	//Prevent multiple event firing after reloading
	\$("#line_height").off("slidechange");
	var data = [];
	var title = field.replace(/^.+\\.\\./, "");

	d3.json(url).then (function(jsonData) {
		var values = ['value'];
		var fields = ['date'];
		var count = 0;
		var total = 0;
		jsonData.forEach(function(e) {
			count++;
			
			fields.push(e.label);
			if (cumulative){
				total += e.value;
				values.push(total);
			} else {
				values.push(e.value);
			}
		});
		var plural = count == 1 ? "" : "s";
		title += " (" + count + " value" + plural + ")";
		
		var chart = c3.generate({
			bindto: '#c3_chart',
			title: {
				text: title
			},
			data: {
				x: 'date',
				columns: [
					fields,
					values
				],
				type: line ? 'line' : 'bar',
				order: 'asc',
			},			

			axis: {
				x: {
					type: 'timeseries',
					tick: {
                		format: '%Y-%m-%d',
                		count: 100,
                		rotate: 90,
                		fit: true
           			},
					height: 100
				}
			},
			legend: {
				show: false
			}
		});

		chart.resize({				
			height: height
		});
		
		\$(".transform_to_bar").off("click").click(function(){
			chart.unload();
			load_line(url,field,0);
			\$(".transform_to_bar").css("display","none");
			\$(".transform_to_line").css("display","inline");
			line = 0;
		});
		\$(".transform_to_line").off("click").click(function(){
			chart.unload();
			load_line(url,field,1);
			\$(".transform_to_line").css("display","none");
			\$(".transform_to_bar").css("display","inline");
			line = 1;
		});
		
		\$(".transform_to_line").css("display",line ? "none" : "inline");
		\$(".transform_to_bar").css("display",line ? "inline": "none");
		\$(".transform_to_pie").css("display","none");
		\$(".transform_to_donut").css("display","none");
		
		\$("#line_controls").css("display", "block");
		\$("#line_height").slider({min:300,max:800,value:height});
		\$("#line_height").on("slidechange",function(){
			var new_height = \$("#line_height").slider('value');
			height = new_height;
			chart.resize({				
				height: height
			});
			set_prefs('height',height);
		});
		show_export_options();
		\$("div#waiting").css("display","none");
	},function(error) {
		console.log(error);
		\$("#c3_chart").html('<p style="text-align:center;margin-top:5em">'
		 + '<span class="error_message">Error accessing data.</span></p>');
	});	
}

function load_bar_json(jsonData,field,rotate){
	\$("#line_controls").css("display", "none");
	\$("#pie_controls").css("display", "none");
	\$("#map_controls").css("display","none");
	\$("#bar_height").off("slidechange");
	var title = field.replace(/^.+\\.\\./, "");
	var count = Object.keys(jsonData).length;
	var plural = count == 1 ? "" : "s";
	title += " (" + count + " value" + plural + ")";
	
	var chart = c3.generate({
		bindto: '#c3_chart',
		title: {
			text: title
		},
		data: {
			json: jsonData,
			keys: {
				x: 'label',
				value: ['value']
			},
			type: 'bar',
		},	
		bar: {
			width: {
				ratio: 0.7
			}
		},
		axis: {
			rotated: rotate,
			x: {
				type: 'category',
				tick: {
					culling: true,
				},
				height: 100
			}
		},
		legend: {
			show: false
		},
		padding: {
			right: 20
		}
	});
	chart.resize({				
		height: height
	});
		
	\$("#bar_height").slider({min:300,max:800,value:height});
	\$("#bar_controls").css("display", "block");
	\$("#bar_height").on("slidechange",function(){
		var new_height = \$("#bar_height").slider('value');
		height = new_height;
		chart.resize({				
			height: height
		});
		set_prefs('height',height);
	});
	show_export_options();		
}

function load_bar(url,field,rotate) {
	d3.json(url).then (function(jsonData) {
		load_bar_json(jsonData,field,rotate);
		\$("div#waiting").css("display","none");
	},function(error) {
		console.log(error);
		\$("#c3_chart").html('<p style="text-align:center;margin-top:5em">'
		 + '<span class="error_message">Error accessing data.</span></p>');
	});
	var orientation_radio = \$('input[name="orientation"]');
	orientation_radio.on("change",function(){
		var field = \$('#field').val();
		rotate = is_vertical();
		//Reload by URL rather than from already downloaded JSON data
		//as it seems that the required unload() function currently has a memory leak.
		load_bar(url,field,rotate);
	});
}

function show_export_options () {
	var field = \$('#field').val();
	\$("a#export_table").attr("href", url + "&export=" + field + "&format=table");
	\$("a#export_excel").attr("href", url + "&export=" + field + "&format=xlsx");
	\$("a#export_text").attr("href", url + "&export=" + field + "&format=text");
	\$("a#export_fasta").attr("href", url + "&export=" + field + "&format=fasta");
	\$("a#export_fasta").css("display", fasta ? "inline" : "none");
	\$("#export").css("display", "block");
}

function set_prefs(attribute, value){
	\$.ajax(prefs_ajax_url + "&update=1&attribute=" + attribute + "&value=" + value);
}

JS
	return $buffer;
}

sub _ajax {
	my ( $self, $field ) = @_;
	my $freqs = $self->_get_field_values($field);
	say to_json($freqs);
	return;
}

sub _get_field_freqs {
	my ( $self, $field, $options ) = @_;
	my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
	my $qry;
	if ( defined $metaset ) {
		$qry = "SELECT m.$metafield AS label,COUNT(*) AS value FROM meta_$metaset m RIGHT JOIN "
		  . "$self->{'system'}->{'view'} v ON m.isolate_id=v.id JOIN id_list i ON v.id=i.value ";
	} else {
		$qry = "SELECT $field AS label,COUNT(*) AS value FROM $self->{'system'}->{'view'} v "
		  . 'JOIN id_list i ON v.id=i.value ';
	}
	$qry .= 'WHERE ' . ( $metafield // $field ) . ' IS NOT NULL ' if $options->{'no_null'};
	$qry .= 'GROUP BY label';
	my $order = $options->{'order'} ? $options->{'order'} : 'value DESC';
	$qry .= " ORDER BY $order";
	my $values = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	if ($field eq 'country'){
		my $countries = COUNTRIES;
		foreach my $value (@$values){
			$value->{'iso3'} = $countries->{$value->{'label'}}->{'iso3'} // q(XXX);
		}
	}
	return $values;
}

sub _get_eav_field_freqs {
	my ( $self, $field, $options ) = @_;
	my $eav_table = $self->{'datastore'}->get_eav_field_table($field);
	my $qry       = "SELECT e.value AS label,COUNT(*) AS value FROM $eav_table e RIGHT JOIN id_list i ON "
	  . 'e.isolate_id=i.value AND e.field=?';
	$qry .= 'WHERE value IS NOT NULL ' if $options->{'no_null'};
	$qry .= 'GROUP BY label';
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
