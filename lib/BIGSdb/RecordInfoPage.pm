#Written by Keith Jolley
#Copyright (c) 2010-2015, University of Oxford
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
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $table  = $q->param('table');
	my $record = $self->get_record_name($table) // 'Record';
	my $title = qq($record information: ) . $self->_get_name;
	$title .= q( - );
	$title .= $self->{'system'}->{'description'};
	return $title;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $table  = $q->param('table') // '';
	my $record = $self->get_record_name($table);
	my $name   = $self->_get_name;
	if ( !$table || !$self->{'datastore'}->is_table($table) ) {
		say qq(<div class="box" id="statusbad"><p>Table $table isn't valid.</p></div>);
		return;
	}
	my @primary_keys = $self->{'datastore'}->get_primary_keys($table);
	my @values;
	foreach my $key (@primary_keys) {
		if ( !$q->param($key) ) {
			say qq(<div class="box" id="statusbad"><p>A value for the $key field is required )
			  . q(to display scheme field information but it wasn't provided.</p></div>);
			return;
		}
		push @values, $q->param($key);
	}
	local $" = '=? AND ';
	my $qry = "SELECT * FROM $table WHERE @primary_keys=?";
	local $" = ' ';
	my $data = $self->{'datastore'}->run_query( $qry, \@values, { fetch => 'row_hashref' } );
	if ( !$data ) {
		say q(<div class="box" id="statusbad"><p>Record does not exist.</p></div>);
		return;
	}
	say qq(<h1>Information on $record $name</h1>);
	print q(<div class="box" id="resultspanel"><div class="scrollable">);
	say q(<dl class="data">);
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	foreach my $att (@$attributes) {
		if ( !$self->{'curate'} ) {
			next if $att->{'name'} =~ /^dbase_/x;    #don't expose connection details
		}
		( my $cleaned_name = $att->{'name'} ) =~ tr/_/ /;
		say qq(<dt>$cleaned_name</dt>);
		my $value;
		if ( $att->{'type'} eq 'bool' ) {
			$value = $data->{ $att->{'name'} } ? 'true' : 'false';
		} else {
			$value = $data->{ $att->{'name'} };
		}
		if ( defined $value && $att->{'name'} =~ /url$/x ) {
			$value =~ s/\&/\&amp;/gx;
		} elsif ( defined $value && $att->{'name'} eq 'dbase_password' ) {
			$value =~ s/./\*/gx;
		} elsif ( $att->{'name'} eq 'scheme_id' ) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($value);
			if ($scheme_info) {
				$value = qq($value: $scheme_info->{'description'});
			}
		}
		if ( $att->{'name'} =~ /sequence$/x && $att->{'type'} ne 'bool' ) {
			$value = BIGSdb::Utils::split_line($value);
			say defined $value ? qq(<dd class="seq">$value</dd>) : q(<dd>&nbsp;</dd>);
		} elsif ( $att->{'name'} eq 'curator' or $att->{'name'} eq 'sender' ) {
			my $user = $self->{'datastore'}->get_user_info($value);
			say qq(<dd>$user->{'first_name'} $user->{'surname'}</dd>);
		} else {
			say defined $value ? qq(<dd>$value</dd>) : q(<dd>&nbsp;</dd>);
		}
	}
	say q(</dl>);
	say q(</div></div>);
	return;
}

sub _get_name {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $table  = $q->param('table');
	my @name;
	return '' if !$self->{'datastore'}->is_table($table);
	my @primary_keys = $self->{'datastore'}->get_primary_keys($table);
	foreach my $key (@primary_keys) {
		if ( scalar @primary_keys > 1 ) {
			push @name, "$key: " . $q->param($key) if $q->param($key);
		} else {
			push @name, $q->param($key) if $q->param($key);
		}
	}
	local $" = '; ';
	return "@name";
}
1;
