#Written by Keith Jolley
#Copyright (c) 2021, University of Oxford
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
#along with BIGSdb.  If not, see <https://www.gnu.org/licenses/>.
package BIGSdb::DataExplorerPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::DashboardPage);
use JSON;
use BIGSdb::Constants qw(RECORD_AGE);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant DEFAULT_ROWS => 15;

sub print_content {
	my ($self) = @_;
	my $title  = $self->get_title;
	my $q      = $self->{'cgi'};
	say qq(<h1>$title</h1>);
	my $field = $q->param('field');
	if ( !defined $field ) {
		$self->print_bad_status(
			{
				message => q(No field specified.),
			}
		);
		return;
	}
	my $display_field = $self->get_display_field($field);
	say q(<div class="box resultstable">);
	$self->_print_filters;
	say qq(<h2>Field: $display_field</h2>);
	my $params = {
		include_old_versions => $q->param('include_old_versions') eq 'true' ? 1 : 0,
		record_age => scalar $q->param('record_age')
	};
	my $values = $self->_get_values( $field, $params );
	my $count = keys %$values;
	say qq(<p>Unique values: <span id="unique_values">$count</span></p>);
	say q(<div id="table_div" class="scrollable" style="margin-top:2em">);
	say $self->_get_table( $field, $values, $params );
	say q(</div></div>);
	return;
}

sub _get_table {
	my ( $self, $field, $values, $params ) = @_;
	my $total = 0;
	$total += $values->{$_} foreach keys %$values;
	my $hide  = keys %$values > DEFAULT_ROWS;
	my $class = $hide ? q(expandable_retracted data_explorer) : q();
	my $table = qq(<div id="table" style="overflow:hidden" class="$class"><ul>);
	$table .= q(<table class="tablesorter"><thead><tr><th>Value</th><th>Frequency</th><th>Percentage</th></tr></thead>);
	$table .= q(<tbody>);
	foreach my $value ( sort { $values->{$b} <=> $values->{$a} } keys %$values ) {
		my $url = $self->_get_url( $field, $value, $params );
		my $percent = BIGSdb::Utils::decimal_place( 100 * $values->{$value} / $total, 2 );
		$table .= qq(<tr><td><a href="$url">$value</a></td><td>$values->{$value}</td><td>$percent</td></tr>);
	}
	$table .= q(</tbody></table></div>);
	if ($hide) {
		$table .= q(<div class="expand_link" id="expand_table"><span class="fas fa-chevron-down"></span></div>);
	}
	return $table;
}

sub _get_url {
	my ( $self, $field, $value, $params ) = @_;
	my $url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query";
	if ( $field =~ /^[f|e]_/x ) {
		$url .= "&prov_field1=$field&prov_value1=$value&submit=1";
	}
	if ( $params->{'include_old_versions'} ) {
		$url .= '&include_old=on';
	}
	if ( $params->{'record_age'} ) {
		my $row = $url =~ /prov_field1/x ? 2 : 1;
		my $datestamp = $self->get_record_age_datestamp( $params->{'record_age'} );
		$url .= "&prov_field$row=f_date_entered&prov_operator$row=>=&prov_value$row=$datestamp&submit=1";
	}
	return $url;
}

sub _get_values {
	my ( $self, $field, $params ) = @_;
	if ( $field =~ /^f_/x ) {
		$field =~ s/^f_//x;
		return $self->_get_primary_metadata_values( $field, $params );
	}
	if ( $field =~ /^e_(.*)\|\|(.*)/x ) {
		my ( $isolate_field, $attribute ) = ( $1, $2 );
		return $self->_get_extended_field_values( $isolate_field, $attribute, $params );
	}
	if ( $field =~ /^eav_(.*)/x ) {
		$field = $1;
		return $self->_get_eav_field_values( $field, $params );
	}
	if ( $field =~ /^s_(\d+)_(.*)/x ) {
		( my $scheme_id, $field ) = ( $1, $2 );
		return $self->_get_scheme_field_values( $scheme_id, $field, $params );
	}
	return 0;
}

sub _get_primary_metadata_values {
	my ( $self, $field, $params ) = @_;
	my $filters = $self->_get_filters($params);
	my $qry     = "SELECT $field AS label,COUNT(*) AS count FROM $self->{'system'}->{'view'} v";
	local $" = ' AND ';
	$qry .= " WHERE @$filters" if @$filters;
	$qry .= ' GROUP BY label';
	my $values =
	  $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	my $freqs = {};

	foreach my $value (@$values) {
		$freqs->{ $value->{'label'} } = $value->{'count'};
	}
	return $freqs;
}

#TODO Stub
sub _get_extended_field_values {
	return 0;
}

#TODO Stub
sub _get_eav_field_values {
	return 0;
}

#TODO Stub
sub _get_scheme_field_values {
	return 0;
}

sub _get_filters {
	my ( $self, $params ) = @_;
	my $filters = [];
	push @$filters, 'v.new_version IS NULL' if !$params->{'include_old_versions'};
	if ( $params->{'record_age'} ) {
		my $datestamp = $self->get_record_age_datestamp( $params->{'record_age'} );
		push @$filters, "v.id IN (SELECT id FROM $self->{'system'}->{'view'} WHERE date_entered>='$datestamp')";
	}
	return $filters;
}

sub _print_filters {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:right"><legend>Filters</legend>);
	say q(<ul><li>);
	say $q->checkbox(
		-name  => 'include_old_versions',
		-id    => 'include_old_versions',
		-value => 'true',
		-label => 'Include old record versions'
	);
	my $record_age = $q->param('record_age') // 0;
	my $record_age_labels = RECORD_AGE;
	say qq(</li><li>Record age: <span id="record_age">$record_age_labels->{$record_age}</span>);
	say q(<div id="record_age_slider" style="width:150px;margin-top:5px"></div>);
	say q(</li></ul>);
	say q(</fieldset>);
	return;
}

sub get_title {
	my ($self) = @_;
	return 'Data explorer';
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery noCache bigsdb.dataexplorer jQuery.tablesort);
	$self->set_level1_breadcrumbs;
	return;
}

sub get_javascript {
	my ($self) = @_;
	return if ( $self->{'system'}->{'dbtype'} // q() ) ne 'isolates';
	my $json              = JSON->new->allow_nonref;
	my $record_age_labels = $json->encode(RECORD_AGE);
	my $q                 = $self->{'cgi'};
	my $record_age        = $q->param('record_age') // 0;
	my $buffer            = << "END";
	var recordAgeLabels = $record_age_labels;
	var recordAge = $record_age;
END
	return $buffer;
}
1;
