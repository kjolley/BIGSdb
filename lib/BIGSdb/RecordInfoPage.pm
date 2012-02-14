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
package BIGSdb::RecordInfoPage;
use strict;
use warnings;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $table  = $q->param('table');
	my $record = $self->get_record_name($table);
	my $title  = "$record information: " . $self->_get_name();
	$title .= ' - ';
	$title .= "$self->{'system'}->{'description'}";
	return $title;
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $table  = $q->param('table');
	my $record = $self->get_record_name($table);
	my $name   = $self->_get_name();
	if ( !$table or !$self->{'datastore'}->is_table($table) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Table '$table' isn't valid.</p></div>\n";
		return;
	}
	my @primary_keys = $self->{'datastore'}->get_primary_keys($table);
	my @values;
	foreach (@primary_keys) {
		if ( !$q->param($_) ) {
			print
"<div class=\"box\" id=\"statusbad\"><p>A $_ field is required to display scheme field information but it wasn't provided.</p></div>\n";
			return;
		}
		push @values, $q->param($_);
	}
	$" = '=? AND ';
	my $qry = "SELECT * FROM $table WHERE @primary_keys=?";
	$" = ' ';
	my $data = $self->{'datastore'}->run_simple_query_hashref( $qry, @values );
	if ( !$data ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Record does not exist.</p></div>\n";
		return;
	}
	print "<h1>Information on $record $name</h1>\n";
	print "<div class=\"box\" id=\"resultstable\">\n";
	print "<table class=\"resultstable\">\n";
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my $td         = 1;
	foreach (@$attributes) {
		( my $cleaned_name = $_->{name} ) =~ tr/_/ /;
		print "<tr class=\"td$td\"><th style=\"text-align:right\">$cleaned_name&nbsp;</th>";
		my $value;
		if ( $_->{'type'} eq 'bool' ) {
			$value = $data->{ $_->{'name'} } ? 'true' : 'false';
		} else {
			$value = $data->{ $_->{'name'} };
		}
		if ( defined $value && $_->{'name'} eq 'url' ) {
			$value =~ s/\&/\&amp;/g;
		} elsif ( defined $value && $_->{'name'} eq 'dbase_password' ) {
			$value =~ s/./\*/g;
		} elsif ( $_->{'name'} eq 'scheme_id' ) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($value);
			if ($scheme_info) {
				$value = "$value: " . $scheme_info->{'description'};
			}
		}
		if ( $_->{'name'} =~ /sequence$/ ) {
			$value = BIGSdb::Utils::split_line($value);
			print defined $value ? "<td style=\"text-align:left\" class=\"seq\">$value</td>" : '<td />';
			print '</tr>';
		} elsif ( $_->{'name'} eq 'curator' or $_->{'name'} eq 'sender' ) {
			my $user = $self->{'datastore'}->get_user_info($value);
			print "<td style=\"text-align:left\">$user->{'first_name'} $user->{'surname'}</td></tr>";
		} else {
			print defined $value ? "<td style=\"text-align:left\">$value</td>" : '<td />';
			print '</tr>';
		}
		$td = $td == 1 ? 2 : 1;
		if ( $_->{'name'} eq 'isolate_id' ) {
			print "<tr class=\"td$td\"><th style=\"text-align:right\">isolate&nbsp;</th><td style=\"text-align:left\">"
			  . $self->get_isolate_name_from_id( $data->{ $_->{'name'} } )
			  . "</td></tr>";
			$td = $td == 1 ? 2 : 1;
		}
	}
	print "</table>\n";
	print "</div>\n";
}

sub _get_name {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $table  = $q->param('table');
	my @name;
	my @primary_keys = $self->{'datastore'}->get_primary_keys($table);
	foreach (@primary_keys) {
		if ( scalar @primary_keys > 1 ) {
			push @name, "$_: " . $q->param($_) if $q->param($_);
		} else {
			push @name, $q->param($_) if $q->param($_);
		}
	}
	$" = '; ';
	return "@name";
}
1;
