#FieldBreakdown.pm - FieldBreakdown plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2018, University of Oxford
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
package BIGSdb::Plugins::FieldBreakdown3;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Try::Tiny;
use JSON;

sub get_attributes {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $field = $q->param('field') // 'field';
	my %att = (
		name        => 'Field Breakdown',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Breakdown of query results by field',
		category    => 'Breakdown',
		buttontext  => 'Fields3',
		menutext    => 'Single field',
		module      => 'FieldBreakdown3',
		version     => '2.0.0',
		dbtype      => 'isolates',
		section     => 'breakdown,postquery',
		url         => "$self->{'config'}->{'doclink'}/data_analysis.html#field-breakdown",
		input       => 'query',

		#		requires      => 'chartdirector',
		#		text_filename => "$field\_breakdown.txt",
		#		xlsx_filename => "$field\_breakdown.xlsx",
		order => 12
	);
	return \%att;
}

sub get_initiation_values {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $values = { plotly => 1, noCache => 1 };
	if ( $q->param('field') ) {
		$values->{'type'} = 'json';
	}
	return $values;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub run {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $id_table = $self->_create_id_table;
	if ( $q->param('field') ) {
		$self->_ajax( $q->param('field') );
		return;
	}
	my ($fields,$labels) = $self->_get_fields;
	say q(<h1>Field breakdown of dataset</h1>);
	say q(<div class="box" id="resultspanel">);
	my $record_count = BIGSdb::Utils::commify( $self->_get_id_count );
	say qq(<p><b>Isolate records:</b> $record_count</p>);
	say q(<label for="field">Select field:</label>);
	say $q->popup_menu( - name => 'field', id => 'field', values => $fields, labels => $labels );
	say q(<div class="scrollable"><div id="chart" style="min-width:420px"></div></div>);
	say q(<div id="error" style="padding-bottom:4em"></div>);
	say q(</div>);
	return;
}

sub _get_fields {
	my ($self)        = @_;
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
	my $expanded_list = [];
	my $labels = {};
	my $no_show = $self->_get_no_show_fields;
	my $extended = $self->get_extended_attributes;
	foreach my $field (@$field_list) {
		next if $no_show->{$field};
		push @$expanded_list, $field;
		if ( ref $extended->{$field} eq 'ARRAY' ) {
			foreach my $attribute ( @{ $extended->{$field} } ) {
				push @$expanded_list, "${field}..$attribute";
				$labels->{"${field}..$attribute"} = $attribute;
			}
		}
	}
	return ($expanded_list, $labels);
}

sub _get_no_show_fields {
	my ($self) = @_;
	my %no_show = map { $_ => 1 } split /,/x, ( $self->{'system'}->{'noshow'} // q() );
	$no_show{'id'} = 1;
	$no_show{ $self->{'system'}->{'labelfield'} } = 1;
	return \%no_show;
}

sub _get_id_count {
	my ($self) = @_;
	return $self->{'datastore'}->run_query('SELECT COUNT(*) FROM id_list');
}

sub _get_first_field {
	my ($self)  = @_;
	my $fields  = $self->{'xmlHandler'}->get_field_list;
	my $no_show = $self->_get_no_show_fields;
	foreach my $field (@$fields) {
		next if $no_show->{$field};
		return $field;
	}
	return;
}

sub _get_query_params {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $params = [];
	foreach my $param (qw(query_file list_file datatype)) {
		push @$params, qq($param=) . $q->param($param) if $q->param($param);
	}
	return $params;
}

sub get_plugin_javascript {
	my ($self)       = @_;
	my $field        = $self->_get_first_field;
	my $query_params = $self->_get_query_params;
	local $" = q(&);
	my $url = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=plugin&)
	  . qq(name=FieldBreakdown3&field=$field);
	my $param_string = @$query_params ? qq(&@$query_params) : q();
	$url .= $param_string;
	my $buffer = <<"JS";
\$(function () {		
	load_pie("$url","$field");
	\$('#field').on("change",function(){
		var field = \$('#field').val();
		var url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=plugin&name=FieldBreakdown3&field=" 
		+ field + "$param_string";
		var panel_height = \$("#resultspanel").height();
		\$("#resultspanel").css("height",panel_height);
		load_pie(url, field);
    });
    \$(window).resize(function() {
    	var size = get_size();
 		Plotly.relayout('chart',{height:size.height,width:size.width});
 	});
});

function get_size() {
	var canvas = document.getElementById('resultspanel');
	var width;
	var height;
	if (canvas.scrollWidth < 800) {
		width = canvas.scrollWidth - 25;
		height = parseInt(canvas.scrollWidth *  0.9);
	} else {
		width = 800;
		height = 700;
	}
	return {width: width, height: height};
}

function load_pie(url,field) {
	var values = [];
	var labels = [];
	var display = [];
	var total = 0;
	var title = field.replace(/^.+\\.\\./, "");
	Plotly.d3.json(url, function(err, json) {
		if (err){
			\$("div#error").html('<p style="margin-top:2em"><span class="error_message">No data retrieved!</span></p>');
			return;
		}
		\$.each(json, function(d,i){
		    values.push(i.value);
		    labels.push(i.label);
		    total += i.value;
  		})
  		var min_to_display = parseInt(0.02 * total);
   		\$.each(json, function(d,i){
  			display.push(i.value >= min_to_display ? 'outside' : 'none');
  		})
  		var data = [{
  			values: values,
  			labels: labels,
  			textposition: display,
  			type: 'pie',
  			opacity: 0.8,
  			textinfo: 'label',
  			rotation: 60,
   		}];
   		var value_count = values.length;
  		var plural = value_count == 1 ? "" : "s";
 		title += " (" + value_count + " value" + plural + ")";
 		var size = get_size();
		var layout = {
			showlegend: false,
 			title: title,
  			font: {size: 14},
  			paper_bgcolor: 'rgba(0,0,0,0)',
  			plot_bgcolor: 'rgba(0,0,0,0)',
  			width: size.width,
  			height: size.height,
 		};
		Plotly.newPlot('chart', data, layout,{displayModeBar:false});
	});
}
JS
	return $buffer;
}

sub _ajax {
	my ( $self, $field ) = @_;
	if ( $self->{'xmlHandler'}->is_field($field) ) {
		my $freqs = $self->_get_field_freqs($field);
		foreach my $value (@$freqs) {
			$value->{'label'} = 'No value' if !defined $value->{'label'};
		}
		say to_json($freqs);
		return;
	}
	if ($field =~ /^(.+)\.\.(.+)$/x){
		my ($std_field, $extended) = ($1, $2);
		my $freqs = $self->_get_extended_field_freqs($std_field, $extended);
		foreach my $value (@$freqs) {
			$value->{'label'} = 'No value' if !defined $value->{'label'};
		}
		say to_json($freqs);
		return;
	}
	return;
}

sub _get_field_freqs {
	my ( $self, $field ) = @_;
	my $values = $self->{'datastore'}->run_query(
		"SELECT $field AS label,COUNT(*) AS value FROM $self->{'system'}->{'view'} v "
		  . 'JOIN id_list i ON v.id=i.value GROUP BY label',
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
	return $values;
}

sub _get_extended_field_freqs {
	my ( $self, $field, $extended ) = @_;
	my $values = $self->{'datastore'}->run_query(
		"SELECT e.value AS label,COUNT(*) AS value FROM $self->{'system'}->{'view'} v "
		  . "JOIN isolate_value_extended_attributes e ON v.$field=e.field_value JOIN id_list i ON v.id=i.value "
		  . 'WHERE (e.isolate_field,e.attribute)=(?,?) GROUP BY label',
		[ $field, $extended],
		{ fetch => 'all_arrayref', slice => {} }
	);
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
