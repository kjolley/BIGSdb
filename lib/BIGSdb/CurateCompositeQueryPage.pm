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
package BIGSdb::CurateCompositeQueryPage;
use strict;
use warnings;
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
	my $q           = $self->{'cgi'};
	my $field_count = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM composite_fields")->[0];
	if ($field_count) {
		my $plural = $field_count > 1 ? 's' : '';
		print "<div class=\"box\" id=\"resultsheader\">$field_count composite field$plural defined.</div>\n";
	} else {
		print "<div class=\"box\" id=\"statusbad\">No composite fields have been defined.</div>\n";
		return;
	}
	my $qry = "SELECT * FROM composite_fields ORDER BY position_after";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error($@) if $@;
	print "<div class=\"box\" id=\"resultstable\">";
	print
"<table class=\"resultstable\"><tr><th>Delete</th><th>Update</th><th>field name</th><th>position after</th><th>main display</th><th>definition</th><th>missing data</th></tr>\n";
	my $td = 1;
	$qry = "SELECT * FROM composite_field_values WHERE composite_field_id = ? ORDER BY field_order";
	my $sql2 = $self->{'db'}->prepare($qry);

	while ( my $data = $sql->fetchrow_hashref ) {
		print "<tr class=\"td$td\"><td><a href=\""
		  . $q->script_name
		  . "?db=$self->{'instance'}&amp;page=delete&amp;&amp;table=composite_fields&amp;id=$data->{'id'}\">Delete</a></td><td><a href=\""
		  . $q->script_name
		  . "?db=$self->{'instance'}&amp;page=compositeUpdate&amp;id=$data->{'id'}\">Update</a></td>";
		print "<td>$data->{'id'}</td><td>$data->{'position_after'}</td><td>" . ( $data->{'main_display'} ? 'true' : 'false' ) . "</td>";
		eval { $sql2->execute( $data->{'id'} ) };
		$logger->error($@) if $@;
		my ( $value, $missing );

		#TODO check for invalid values
		while ( my $field_value = $sql2->fetchrow_hashref ) {
			if ( $field_value->{'field'} =~ /^f_(.+)/ ) {
				$value   .= "<span class=\"field\">[$1]</span>";
				$missing .= "<span class=\"field\">$field_value->{'empty_value'}</span>" if defined $field_value->{'empty_value'};
			} elsif ( $field_value->{'field'} =~ /^l_(.+)/ ) {
				$value   .= "<span class=\"locus\">[$1]</span>";
				$missing .= "<span class=\"locus\">$field_value->{'empty_value'}</span>" if defined $field_value->{'empty_value'};
			} elsif ( $field_value->{'field'} =~ /^s_(\d+)_(.+)/ ) {
				$value   .= "<span class=\"scheme\">[scheme $1:$2]</span>";
				$missing .= "<span class=\"scheme\">$field_value->{'empty_value'}</span>" if defined $field_value->{'empty_value'};
			} elsif ( $field_value->{'field'} =~ /^t_(.+)/ ) {
				$value   .= "<span class=\"text\">$1</span>";
				$missing .= "<span class=\"text\">$1</span>";
			}
		}
		print defined $value ? "<td>$value</td>" : "<td></td>";
		print defined $missing ? "<td>$missing</td>" : "<td></td>";
		print "</tr>\n";
		$td = $td == 1 ? 2 : 1;    #row stripes
	}
	print "</table>\n";
	print "</div>\n";
	return;
}
1;
