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
package BIGSdb::CurateCompositeQueryPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Update or delete composite field - $desc";
}

sub print_content {
	my ($self) = @_;
	print "<h1>Update or delete composite field</h1>\n";
	$self->_create_query_table;
	return;
}

sub _create_query_table {
	my ($self)      = @_;
	my $field_count = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM composite_fields");
	if ($field_count) {
		my $plural = $field_count > 1 ? 's' : '';
		say qq(<div class="box" id="resultsheader">$field_count composite field$plural defined.</div>);
	} else {
		say qq(<div class="box" id="statusbad">No composite fields have been defined.</div>);
		return;
	}
	print qq(<div class="box" id="resultstable">);
	say qq(<table class="resultstable"><tr><th>Delete</th><th>Update</th><th>field name</th><th>position after</th><th>main display</th>)
	  . qq(<th>definition</th><th>missing data</th></tr>);
	my $td = 1;
	my $composite_fields =
	  $self->{'datastore'}
	  ->run_query( "SELECT * FROM composite_fields ORDER BY position_after", undef, { fetch => 'all_arrayref', slice => {} } );
	foreach my $data (@$composite_fields) {
		say qq(<tr class="td$td"><td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=delete&amp;&amp;)
		  . qq(table=composite_fields&amp;id=$data->{'id'}">Delete</a></td><td><a href="$self->{'system'}->{'script_name'}?)
		  . qq(db=$self->{'instance'}&amp;page=compositeUpdate&amp;id=$data->{'id'}">Update</a></td>);
		say qq(<td>$data->{'id'}</td><td>$data->{'position_after'}</td><td>) . ( $data->{'main_display'} ? 'true' : 'false' ) . "</td>";
		my ( $value, $missing );
		my $values =
		  $self->{'datastore'}->run_query( "SELECT * FROM composite_field_values WHERE composite_field_id=? ORDER BY field_order",
			$data->{'id'}, { fetch => 'all_arrayref', slice => {}, cache => 'CurateCompositeQueryPage::create_query_table_values' } );

		#TODO check for invalid values
		foreach my $field_value (@$values) {
			if ( $field_value->{'field'} =~ /^f_(.+)/ ) {
				$value .= "<span class=\"field\">[$1]</span>";
				$missing .= "<span class=\"field\">$field_value->{'empty_value'}</span>" if defined $field_value->{'empty_value'};
			} elsif ( $field_value->{'field'} =~ /^l_(.+)/ ) {
				$value .= "<span class=\"locus\">[$1]</span>";
				$missing .= "<span class=\"locus\">$field_value->{'empty_value'}</span>" if defined $field_value->{'empty_value'};
			} elsif ( $field_value->{'field'} =~ /^s_(\d+)_(.+)/ ) {
				$value .= "<span class=\"scheme\">[scheme $1:$2]</span>";
				$missing .= "<span class=\"scheme\">$field_value->{'empty_value'}</span>" if defined $field_value->{'empty_value'};
			} elsif ( $field_value->{'field'} =~ /^t_(.+)/ ) {
				$value   .= "<span class=\"text\">$1</span>";
				$missing .= "<span class=\"text\">$1</span>";
			}
		}
		say defined $value   ? "<td>$value</td>"   : "<td></td>";
		say defined $missing ? "<td>$missing</td>" : "<td></td>";
		say "</tr>";
		$td = $td == 1 ? 2 : 1;    #row stripes
	}
	say "</table></div>";
	return;
}
1;
