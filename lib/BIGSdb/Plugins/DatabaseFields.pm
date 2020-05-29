#DatabaseFields.pm - Database field description plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2020, University of Oxford
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
package BIGSdb::Plugins::DatabaseFields;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant HIDE_VALUES => 8;

sub get_attributes {
	my %att = (
		name        => 'Database Fields',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Display description of fields defined for the current database',
		menutext    => 'Description of database fields',
		module      => 'DatabaseFields',
		version     => '1.1.1',
		section     => 'miscellaneous',
		order       => 10,
		dbtype      => 'isolates'
	);
	return \%att;
}

sub get_initiation_values {
	return { 'jQuery.tablesort' => 1 };
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub run {
	my ($self) = @_;
	say q(<h1>Description of database fields</h1>);
	say q(<div class="box" id="resultstable"><div class="scrollable">);
	my $eav_fields = $self->{'datastore'}->get_eav_fieldnames;
	if (@$eav_fields) {
		say q(<span class="info_icon fas fa-2x fa-fw fa-globe fa-pull-left" style="margin-top:0.2em"></span>);
		say q(<h2>Provenace/primary metadata</h2>);
	}
	say q(<p>Order columns by clicking their headings. )
	  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;)
	  . q(name=DatabaseFields">Reset default order</a>.</p>);
	$self->_provenance_print_fields;
	if (@$eav_fields) {
		$self->_print_eav_fields;
	}
	say q(</div></div>);
	return;
}

sub _provenance_print_fields {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $set_id     = $self->get_set_id;
	my $is_curator = $self->is_curator;
	my $field_list = $self->{'xmlHandler'}->get_field_list( { no_curate_only => !$is_curator } );
	my $td = 1;
	say q(<table class="tablesorter" style="margin-bottom:1em"><thead>);
	say q(<tr><th>field name</th><th>comments</th><th>data type</th><th class="{sorter: false}">)
	  . q(allowed values</th><th>required</th><th>maximum length (characters)</th></tr></thead><tbody>);

	foreach my $field (@$field_list) {
		my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
		$thisfield->{'type'} = 'integer' if $thisfield->{'type'} =~ /^int/x;
		$thisfield->{'comments'} //= '';
		say qq(<tr class="td$td"><td>$field</td><td>$thisfield->{'comments'}</td>);
		my $multiple = ( $thisfield->{'multiple'} // q() ) eq 'yes' ? q( (multiple)) : q();
		say qq(<td>$thisfield->{'type'}$multiple</td>);
		say q(<td>);
		$self->_print_allowed_values($field);
		say q(</td>);

		if ( ( $thisfield->{'required'} // '' ) eq 'no' ) {
			say q(<td>no</td>);
		} else {
			say q(<td>yes</td>);
		}
		my $length = $thisfield->{'length'} // q(-);
		$length = q(-) if ( $thisfield->{'optlist'} // q() ) eq 'yes';
		say qq(<td>$length</td>);
		say q(</tr>);
		$td = $td == 1 ? 2 : 1;
		if ( $field eq $self->{'system'}->{'labelfield'} ) {
			say qq(<tr class="td$td"><td>aliases</td><td>alternative names for $self->{'system'}->{'labelfield'}</td>)
			  . q(<td>text (multiple)</td><td>-</td><td>no</td><td>-</td></tr>);
			$td = $td == 1 ? 2 : 1;
			say qq(<tr class="td$td"><td>references</td>)
			  . q(<td>PubMed ids that link to publications that describe or include record</td>)
			  . q(<td>integer (multiple)</td><td>-</td><td>no</td><td>-</td></tr>);
			$td = $td == 1 ? 2 : 1;
		}
	}
	say q(</tbody></table>);
	return;
}

sub _print_eav_fields {
	my ($self) = @_;
	my $field_name    = $self->{'system'}->{'eav_fields'} // 'secondary metadata';
	my $uc_field_name = ucfirst($field_name);
	my $icon          = $self->{'system'}->{'eav_field_icon'} // 'fas fa-microscope';
	say qq(<span class="info_icon fa-2x fa-fw $icon fa-pull-left" style="margin-top:-0.2em"> )
	  . qq(</span><h2 style="display:inline">$uc_field_name</h2>);
	my $eav_fields = $self->{'datastore'}->get_eav_fields;
	my $td         = 1;
	say q(<table class="tablesorter" style="margin-top:1em"><thead>);
	say q(<tr><th>field name</th><th>comments</th><th>data type</th><th class="{sorter: false}">)
	  . q(allowed values</th><th>required</th><th>maximum length (characters)</th></tr></thead><tbody>);

	foreach my $field (@$eav_fields) {
		$field->{'description'} //= q(-);
		say qq(<tr class="td$td"><td>$field->{'field'}</td><td>$field->{'description'}</td>);
		say qq(<td>$field->{'value_format'}</td>);
		if ( $field->{'option_list'} ) {
			my @values = split /;/x, $field->{'option_list'};
			my $hide   = @values > HIDE_VALUES;
			my $class  = $hide ? q(expandable_retracted) : q();
			say qq(<td><div id="$field->{'field'}" style="overflow:hidden" class="$class">);
			foreach my $option (@values) {
				$option = BIGSdb::Utils::escape_html($option);
				say qq($option<br />);
			}
			say qq(</div>\n);
			if ($hide) {
				say
qq(<div class="expand_link" id="expand_$field->{'field'}"><span class="fas fa-chevron-down"></span></div>);
			}
			say q(</td>);
		} else {
			say q(<td>);
			if ( defined $field->{'min_value'} || defined $field->{'max_value'} ) {
				print qq(min: $field->{'min_value'}) if defined $field->{'min_value'};
				print q(; )                          if defined $field->{'min_value'} && defined $field->{'max_value'};
				say qq(max: $field->{'max_value'})   if defined $field->{'max_value'};
			} else {
				say q(-);
			}
			say q(</td>);
		}
		say q(<td>no</td>);
		my $length = $field->{'length'} ? $field->{'length'} : '-';
		say qq(<td>$length</td></tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</tbody></table>);
	return;
}

sub _print_allowed_values {
	my ( $self, $field ) = @_;
	my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
	if ( $thisfield->{'optlist'} ) {
		my $option_list = $self->{'xmlHandler'}->get_field_option_list($field);
		my $hide        = @$option_list > HIDE_VALUES;
		my $class       = $hide ? q(expandable_retracted) : q();
		say qq(<div id="$field" style="overflow:hidden" class="$class">);
		foreach my $option (@$option_list) {
			$option = BIGSdb::Utils::escape_html($option);
			say qq($option<br />);
		}
		say qq(</div>\n);
		if ($hide) {
			say qq(<div class="expand_link" id="expand_$field"><span class="fas fa-chevron-down"></span></div>);
		}
		return;
	}
	if ( defined $thisfield->{'min'} || defined $thisfield->{'max'} ) {
		print qq(min: $thisfield->{'min'}) if defined $thisfield->{'min'};
		print q(; )                        if defined $thisfield->{'min'} && defined $thisfield->{'max'};
		say qq(max: $thisfield->{'max'})   if defined $thisfield->{'max'};
		return;
	}
	if ( $field eq 'sender' || $field eq 'sequenced_by' || ( $thisfield->{'userfield'} // '' ) eq 'yes' ) {
		say qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=fieldValues&amp;)
		  . q(field=f_sender" target="_blank">Click for list of sender ids</a>);
		return;
	}
	if ( $field eq 'curator' ) {
		say qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=fieldValues&amp;)
		  . q(field=f_curator" target="_blank">Click for list of curator ids</a>);
		return;
	}
	print q(-);
	return;
}

sub get_plugin_javascript {
	my ($self) = @_;
	my $buffer = << "END";
\$(function () {
	\$('.expand_link').on('click', function(){	
		var field = this.id.replace('expand_','');
	  	if (\$('#' + field).hasClass('expandable_expanded')) {
	  	\$('#' + field).switchClass('expandable_expanded','expandable_retracted',1000, "easeInOutQuad", function(){
	  		\$('#expand_' + field).html('<span class="fas fa-chevron-down"></span>');
	  	});	    
	  } else {
	  	\$('#' + field).switchClass('expandable_retracted','expandable_expanded',1000, "easeInOutQuad", function(){
	  		\$('#expand_' + field).html('<span class="fas fa-chevron-up"></span>');
	  	});	    
	  }
	});	
});

END
	return $buffer;
}
1;
