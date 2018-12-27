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
package BIGSdb::Plugins::FieldBreakdown2;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Try::Tiny;
use JSON;
use BIGSdb::Constants qw(:interface);

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
		buttontext  => 'Fields2',
		menutext    => 'Single field (2)',
		module      => 'FieldBreakdown2',
		version     => '2.0.0',
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
	my $values = { d3 => 1, noCache => 1 };
	if ( $q->param('field') ) {
		$values->{'type'} = 'json';
	}
	if ( $q->param('export') && $q->param('format') ) {
		if ( $q->param('format') eq 'text' ) {
			$values->{'attachment'} = $q->param('export') . '.txt';
		} elsif ( $q->param('format') eq 'xlsx' ) {
			$values->{'attachment'} = $q->param('export') . '.xlsx';
		}
	}
	return $values;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub _export {
	my ( $self, $field, $format ) = @_;
	my $formats = {
		table => sub { $self->_show_table($field) },
		xlsx  => sub { $self->_export_excel($field) },
		text  => sub { $self->_export_text($field) }
	};
	if ( $formats->{$format} ) {
		$formats->{$format}->();
	} else {
		say q(<h1>Field breakdown</h1>);
		$self->print_bad_status( { message => q(Invalid format selected.) } );
	}
	return;
}

sub _show_table {
	my ( $self, $field ) = @_;
	my $freqs = [];
	if ( $self->{'xmlHandler'}->is_field($field) ) {
		my $att = $self->{'xmlHandler'}->get_field_attributes($field);
		$freqs =
		  $self->_get_field_freqs( $field,
			$att->{'type'} =~ /^(?:int|date)/x ? { order => 'label ASC', no_null => 1 } : undef );
		foreach my $value (@$freqs) {
			$value->{'label'} = 'No value' if !defined $value->{'label'};
		}
	} elsif ( $field =~ /^(.+)\.\.(.+)$/x ) {
		my ( $std_field, $extended ) = ( $1, $2 );
		$freqs = $self->_get_extended_field_freqs( $std_field, $extended );
		foreach my $value (@$freqs) {
			$value->{'label'} = 'No value' if !defined $value->{'label'};
		}
	}
	my $count = @$freqs;
	my $plural = $count != 1 ? 's' : '';
	my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
	my $display_field = $metafield // $field;
	$display_field =~ tr/_/ /;
	$display_field =~ s/^.*\.\.//x;
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
	my $freqs = [];
	if ( $self->{'xmlHandler'}->is_field($field) ) {
		my $att = $self->{'xmlHandler'}->get_field_attributes($field);
		$freqs =
		  $self->_get_field_freqs( $field,
			$att->{'type'} =~ /^(?:int|date)/x ? { order => 'label ASC', no_null => 1 } : undef );
		foreach my $value (@$freqs) {
			$value->{'label'} = 'No value' if !defined $value->{'label'};
		}
	} elsif ( $field =~ /^(.+)\.\.(.+)$/x ) {
		my ( $std_field, $extended ) = ( $1, $2 );
		$freqs = $self->_get_extended_field_freqs( $std_field, $extended );
		foreach my $value (@$freqs) {
			$value->{'label'} = 'No value' if !defined $value->{'label'};
		}
	}
	my $count = @$freqs;
	my $plural = $count != 1 ? 's' : '';
	my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
	my $display_field = $metafield // $field;
	$display_field =~ tr/_/ /;
	$display_field =~ s/^.*\.\.//x;
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
	my $text_table = $self->_get_text_table($field);
	my $temp_file  = $self->make_temp_file($text_table);
	my $full_path  = "$self->{'config'}->{'secure_tmp_dir'}/$temp_file";
	BIGSdb::Utils::text2excel( $full_path,
		{ stdout => 1, worksheet => "$display_field breakdown", tmp_dir => $self->{'config'}->{'secure_tmp_dir'} } );
	unlink $full_path;
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
	say q(<label for="field">Select field:</label>);
	say $q->popup_menu( - name => 'field', id => 'field', values => $fields, labels => $labels );
	say q(<div id="c3_chart" style="min-height:400px"></div>);
	say q(<div id="error"></div>);
	$self->_print_bar_controls;
	$self->_print_line_controls;
	say q(<div style="clear:both"></div>);
	my ( $table, $excel, $text ) = ( EXPORT_TABLE, EXCEL_FILE, TEXT_FILE );
	say q(<div id="export" style="display:none">);
	say qq(<a id="export_table" title="Show as table" style="cursor:pointer">$table</a>);
	say qq(<a id="export_excel" title="Export Excel file" style="cursor:pointer">$excel</a>);
	say qq(<a id="export_text" title="Export text file" style="cursor:pointer">$text</a>);
	say q(</div></div>);
	return;
}

sub _print_bar_controls {
	my ( $self, $type ) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset id="bar_controls" class="c3_controls" )
	  . q(style="position:absolute;top:6em;right:1em;display:none"><legend>Controls</legend>);
	say q(<ul>);
	say q(<li><label for="orientation">Orientation:</label>);
	say $q->radio_group( -name => 'orientation', -values => [qw(horizontal vertical)], -default => 'horizontal' );
	say q(</li>);
	say q(<li><label for="height">Height:</label>);
	say q(<div id="bar_height" style="display:inline-block;width:8em"></div></li>);
	say q(</ul></fieldset>);
	return;
}

sub _print_line_controls {
	my ( $self, $type ) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset id="line_controls" class="c3_controls" )
	  . q(style="position:absolute;top:6em;right:1em;display:none"><legend>Controls</legend>);
	say q(<ul>);
	say q(<li><label for="height">Height:</label>);
	say q(<div id="line_height" style="display:inline-block;width:8em"></div></li>);
	say q(</ul></fieldset>);
	return;
}

sub _get_fields {
	my ($self)        = @_;
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
	my $expanded_list = [];
	my $labels        = {};
	my $no_show       = $self->_get_no_show_fields;
	my $extended      = $self->get_extended_attributes;
	foreach my $field (@$field_list) {
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

sub _get_field_types_js {
	my ($self) = @_;
	my $field_attributes = $self->{'xmlHandler'}->get_all_field_attributes;
	my %types = map { $field_attributes->{$_} => $field_attributes->{$_}->{'type'} } keys %$field_attributes;
	my @type_values;
	my %allowed_types = map { $_ => 1 } qw(integer text float date);
	foreach my $field ( keys %$field_attributes ) {
		my $type = lc( $field_attributes->{$field}->{'type'} );
		$type = 'integer' if $type eq 'int';
		if ( !$allowed_types{$type} ) {
			$logger->error("Field $field has an unrecognized type: $type");
			$type = 'text';
		}
		push @type_values, qq('$field':'$type');
	}
	local $" = qq(,\n\t);
	return qq(var field_types = {@type_values};\n);
}

sub get_plugin_javascript {
	my ($self)       = @_;
	my $field        = $self->_get_first_field;
	my $query_params = $self->_get_query_params;
	local $" = q(&);
	my $url = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=plugin&)
	  . qq(name=FieldBreakdown2&field=$field);
	my $export_url =
	  qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=plugin&) . q(name=FieldBreakdown2);
	my $param_string = @$query_params ? qq(&@$query_params) : q();
	$url        .= $param_string;
	$export_url .= $param_string;
	my $types_js = $self->_get_field_types_js;
	my $buffer   = <<"JS";
\$(function () {
	$types_js	
	load_pie("$url","$field",20);
	\$('#field').on("change",function(){
		\$(".c3_controls").css("display", "none");
		var field = \$('#field').val();
		var url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=plugin&name=FieldBreakdown2&field=" 
		+ field + "$param_string";
		if (field_types[field] == 'integer'){
			load_bar(url,field);
		} else if (field_types[field] == 'date'){
			load_line(url,field,true);
		} else {
			load_pie(url,field,20);
		}		
    });
    
    var orientation_radio = \$('input[name="orientation"]');
	orientation_radio.on("change",function(){
		var checked = orientation_radio.filter(function() {
	    	return \$(this).prop('checked');
	  	});
		var orientation = checked.val();
		var field = \$('#field').val();
		var url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=plugin&name=FieldBreakdown2&field=" 
		+ field + "$param_string";
		var rotate = orientation == 'vertical' ? 1 : 0;
		load_bar(url,field,rotate);
	});
	\$(window).resize(function() {
		if (\$(window).width() < 600){
			\$(".c3_controls").css("position", "static");
			\$(".c3_controls").css("float", "left");
		} else {
			\$(".c3_controls").css("position", "absolute");
			\$(".c3_controls").css("clear", "both");
		}
	});
	
});

function load_pie(url,field,max_segments) {
	\$("#bar_controls").css("display", "none");
	var data = [];
	var title = field.replace(/^.+\\.\\./, "");
	var f = d3.format(".1f");
	
	d3.json(url).then (function(jsonData) {
		var data = {};
		var fields = [];
		var count = 0;
		var others = 0;
		var other_fields = 0;
		jsonData.forEach(function(e) {
			e.label = e.label.toString(); 
			count++;
			if (count >= max_segments){
				others += e.value;
				other_fields++;
			} else {
			    fields.push(e.label);
			    data[e.label] = e.value;
			}
		}) 
		
		var plural = count == 1 ? "" : "s";
		title += " (" + count + " value" + plural + ")";
		if (others > 0){
			fields.push('Others');
			data['Others'] = others;
		}  
		var chart = c3.generate({
			bindto: '#c3_chart',
			title: {
				text: title
			},
			data: {
				json: [data],
				keys: {
					value: fields
				},
				type: 'pie',
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
				height: 600
			},
			tooltip: {
				format: {
					title: name,
					value: function (value, ratio, id){
						return value + " (" + f(ratio * 100) + "%)";
					}
				}
			}
		})
		show_export_options();
	});
}

function load_line(url,field,cumulative) {
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
		}) 
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
				type: 'line',
				order: 'asc',
			},			

			axis: {
				x: {
					type: 'timeseries',
					tick: {
                		format: '%Y-%m-%d',
                		count: 10,
                		rotate: 45,
                		fit: true
           			},
					height: 100
				}
			},
			legend: {
				show: false
			}
		});
		\$("#line_height").on("slidechange",function(){
			var height = \$("#line_height").slider('value');
			chart.resize({
				height: height
			});
		});
		
		\$("#line_controls").css("display", "block");
		\$("#line_height").slider({min:300,max:800,value:400});
		show_export_options();
	});
	
}

function load_bar(url,field,rotate) {
	var data = [];
	var title = field.replace(/^.+\\.\\./, "");

	d3.json(url).then (function(jsonData) {
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
				order: 'asc',
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
			}
		});
		\$("#bar_height").on("slidechange",function(){
			var height = \$("#bar_height").slider('value');
			chart.resize({
				height: height
			});
		});
	
		\$("#bar_height").slider({min:300,max:800,value:400});
		\$("input[name=orientation][value='horizontal']").prop("checked",(rotate ? false : true));
		\$("#bar_controls").css("display", "block");
		show_export_options();		
	});
}

function show_export_options () {
	var field = \$('#field').val();
	\$("a#export_table").attr("href", "$export_url&export=" + field + "&format=table");
	\$("a#export_excel").attr("href", "$export_url&export=" + field + "&format=xlsx");
	\$("a#export_text").attr("href", "$export_url&export=" + field + "&format=text");
	\$("#export").css("display", "block");
} 

JS
	return $buffer;
}

sub _ajax {
	my ( $self, $field ) = @_;
	if ( $self->{'xmlHandler'}->is_field($field) ) {
		my $att = $self->{'xmlHandler'}->get_field_attributes($field);
		my $freqs =
		  $self->_get_field_freqs( $field,
			$att->{'type'} =~ /^(?:int|date)/x ? { order => 'label ASC', no_null => 1 } : undef );
		foreach my $value (@$freqs) {
			$value->{'label'} = 'No value' if !defined $value->{'label'};
		}
		say to_json($freqs);
		return;
	}
	if ( $field =~ /^(.+)\.\.(.+)$/x ) {
		my ( $std_field, $extended ) = ( $1, $2 );
		my $freqs = $self->_get_extended_field_freqs( $std_field, $extended );
		foreach my $value (@$freqs) {
			$value->{'label'} = 'No value' if !defined $value->{'label'};
		}
		say to_json($freqs);
		return;
	}
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
	return $values;
}

sub _get_extended_field_freqs {
	my ( $self, $field, $extended, $options ) = @_;
	my $qry =
	    "SELECT e.value AS label,COUNT(*) AS value FROM $self->{'system'}->{'view'} v "
	  . "JOIN isolate_value_extended_attributes e ON v.$field=e.field_value JOIN id_list i ON v.id=i.value "
	  . 'WHERE (e.isolate_field,e.attribute)=(?,?) GROUP BY label';
	my $order = $options->{'order'} ? $options->{'order'} : 'value DESC';
	$qry .= " ORDER BY $order";
	my $values =
	  $self->{'datastore'}->run_query( $qry, [ $field, $extended ], { fetch => 'all_arrayref', slice => {} } );
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
