#DatabaseFields.pm - Database field description plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2012, University of Oxford
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

sub get_attributes {
	my %att = (
		name        => 'Database Fields',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Display description of fields defined for the current database',
		menutext    => 'Description of database fields',
		module      => 'DatabaseFields',
		version     => '1.0.1',
		section     => 'miscellaneous',
		order       => 10,
		dbtype      => 'isolates'
	);
	return \%att;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub run {
	my ($self) = @_;
	say "<h1>Description of database fields</h1>";
	say "<div class=\"box\" id=\"resultstable\">";
	say "<p>Order columns by clicking their headings. <a href=\"$self->{'system'}->{'script_name'}?"
	  . "db=$self->{'instance'}&amp;page=plugin&amp;name=DatabaseFields\">Reset default order</a>.</p>";
	say "<table class=\"tablesorter\" id=\"sortTable\">\n<thead>";
	say "<tr><th>field name</th><th>comments</th><th>data type</th><th class=\"{sorter: false}\">allowed values</th>"
	  . "<th>required</th></tr></thead>\n<tbody>";
	$self->_print_fields;
	say "</tbody></table>\n</div>";
	return;
}

sub _print_fields {
	my ($self)        = @_;
	my $q             = $self->{'cgi'};
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
	my $td            = 1;
	foreach my $field (@$field_list) {
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
		my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
		$thisfield->{'comments'} //= '';
		print "<tr class=\"td$td\"><td>"
		  . ( $metafield // $field )
		  . "</td><td>$thisfield->{'comments'}</td><td>$thisfield->{'type'}</td><td>";
		if ( $thisfield->{'optlist'} ) {
			my $option_list = $self->{'xmlHandler'}->get_field_option_list($field);
			say "$_<br />" foreach @$option_list;
		} elsif ( $field eq 'sender' || $field eq 'sequenced_by' || ( $thisfield->{'userfield'} // '' ) eq 'yes' ) {
			say "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=fieldValues&amp;field=f_sender\" "
			  . "target=\"_blank\">Click for list of sender ids</a>";
		} elsif ( $field eq 'curator' ) {
			say "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=fieldValues&amp;field=f_curator\" "
			  . "target=\"_blank\">Click for list of curator ids</a>";
		} else {
			print '-';
		}
		if ( $thisfield->{'composite'} ) {
			say "</td><td>n/a (composite field)</td></tr>";
		} elsif ( ( $thisfield->{'required'} // '' ) eq 'no' ) {
			say "</td><td>no</td></tr>";
		} else {
			say "</td><td>yes</td></tr>";
		}
		$td = $td == 1 ? 2 : 1;
	}
	return;
}
1;
