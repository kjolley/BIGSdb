#DatabaseFields.pm - Database field description plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
use base qw(BIGSdb::Plugin);
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
	$self->{'pref_requirements'} = { 'general' => 0, 'main_display' => 0, 'isolate_display' => 0, 'analysis' => 0, 'query_field' => 0 };
}

sub run {
	my ($self) = @_;
	print "<h1>Description of database fields</h1>\n";
	print "<div class=\"box\" id=\"resultstable\">\n";
	print "<p>Order columns by clicking their headings. <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;name=DatabaseFields\">Reset default order</a>.</p>\n";
	print "<table class=\"tablesorter\" id=\"sortTable\">\n<thead>\n";
	print "<tr><th>field name</th><th>comments</th><th>data type</th><th class=\"{sorter: false}\">allowed values</th><th>required</th></tr></thead>\n<tbody>";
	$self->_print_fields;
	print "</tbody></table>\n</div>\n";
}

sub _print_fields {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $field_list = $self->{'xmlHandler'}->get_field_list;
	my $td         = 1;
	foreach (@$field_list) {
		my %thisfield = $self->{'xmlHandler'}->get_field_attributes($_);
		$thisfield{'comments'} = '' if !$thisfield{'comments'};
		print "<tr class=\"td$td\"><td>$_</td><td>$thisfield{'comments'}</td><td>$thisfield{'type'}</td><td>";
		if ( $thisfield{'optlist'} ) {
			foreach ( $self->{'xmlHandler'}->get_field_option_list($_) ) {
				print "$_<br />\n";
			}
		} elsif ( $_ eq 'sender'
			or $_ eq 'sequenced_by' || ( $thisfield{'userfield'} && $thisfield{'userfield'} eq 'yes' ) )
		{
			print "<a href=\""
			  . $q->script_name
			  . "?db=$self->{'instance'}&amp;page=fieldValues&amp;field=f_sender\" target=\"_blank\">Click for list of sender ids</a>";
		} elsif ( $_ eq 'curator' ) {
			print "<a href=\""
			  . $q->script_name
			  . "?db=$self->{'instance'}&amp;page=fieldValues&amp;field=f_curator\" target=\"_blank\">Click for list of curator ids</a>";
		} else {
			print '-';
		}
		if ( $thisfield{'composite'} ) {
			print "</td><td>n/a (composite field)</td></tr>\n";
		} elsif ( $thisfield{'required'} && $thisfield{'required'} eq 'no' ) {
			print "</td><td>no</td></tr>\n";
		} else {
			print "</td><td>yes</td></tr>\n";
		}
		$td = $td == 1 ? 2 : 1;
	}
}
1;
