#Written by Keith Jolley
#Copyright (c) 2010-2018, University of Oxford
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
use BIGSdb::Constants qw(:interface);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return qq(Update or delete composite field - $desc);
}

sub print_content {
	my ($self) = @_;
	say q(<h1>Update or delete composite field</h1>);
	$self->_create_query_table;
	return;
}

sub _create_query_table {
	my ($self) = @_;
	my $field_count = $self->{'datastore'}->run_query('SELECT COUNT(*) FROM composite_fields');
	if ($field_count) {
		my $plural = $field_count > 1 ? q(s) : q();
		say qq(<div class="box" id="resultsheader">$field_count composite field$plural defined.</div>);
	} else {
		$self->print_bad_status( { message => q(No composite fields have been defined.), navbar => 1 } );
		return;
	}
	say q(<div class="box" id="resultstable">);
	say q(<table class="resultstable"><tr><th>Delete</th><th>Update</th><th>field name</th>)
	  . q(<th>position after</th><th>main display</th><th>definition</th><th>missing data</th></tr>);
	my $td               = 1;
	my $composite_fields = $self->{'datastore'}->run_query( 'SELECT * FROM composite_fields ORDER BY position_after',
		undef, { fetch => 'all_arrayref', slice => {} } );
	foreach my $data (@$composite_fields) {
		say qq(<tr class="td$td"><td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=delete&amp;&amp;table=composite_fields&amp;id=$data->{'id'}" class="action">)
		  . DELETE
		  . q(</a></td>)
		  . qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=compositeUpdate&amp;)
		  . qq(id=$data->{'id'}" class="action">)
		  . EDIT
		  . q(</a></td>);
		say qq(<td>$data->{'id'}</td><td>$data->{'position_after'}</td><td>)
		  . ( $data->{'main_display'} ? q(true) : q(false) )
		  . q(</td>);
		my ( $value, $missing );
		my $values =
		  $self->{'datastore'}
		  ->run_query( 'SELECT * FROM composite_field_values WHERE composite_field_id=? ORDER BY field_order',
			$data->{'id'},
			{ fetch => 'all_arrayref', slice => {}, cache => 'CurateCompositeQueryPage::create_query_table_values' } );
		foreach my $field_value (@$values) {
			if ( $field_value->{'field'} =~ /^f_(.+)/x ) {
				my $field = $1;
				if ( !$self->{'xmlHandler'}->is_field($field) ) {
					$field .= q( (INVALID VALUE));
				}
				$value   .= qq(<span class="field">[$field]</span>);
				$missing .= qq(<span class="field">$field_value->{'empty_value'}</span>)
				  if defined $field_value->{'empty_value'};
				next;
			}
			if ( $field_value->{'field'} =~ /^l_(.+)/x ) {
				my $locus = $1;
				if ( !$self->{'datastore'}->is_locus($locus) ) {
					$locus .= q( (INVALID VALUE));
				}
				$value   .= qq(<span class="locus">[$locus]</span>);
				$missing .= qq(<span class="locus">$field_value->{'empty_value'}</span>)
				  if defined $field_value->{'empty_value'};
				next;
			}
			if ( $field_value->{'field'} =~ /^s_(\d+)_(.+)/x ) {
				my ( $scheme_id, $field ) = ( $1, $2 );
				if ( !$self->{'datastore'}->is_scheme_field( $scheme_id, $field ) ) {
					$field .= q( (INVALID VALUE));
				}
				$value   .= qq(<span class="scheme">[scheme $scheme_id:$field]</span>);
				$missing .= qq(<span class="scheme">$field_value->{'empty_value'}</span>)
				  if defined $field_value->{'empty_value'};
				next;
			}
			if ( $field_value->{'field'} =~ /^t_(.+)/x ) {
				$value   .= qq(<span class="text">$1</span>);
				$missing .= qq(<span class="text">$1</span>);
			}
		}
		say defined $value   ? qq(<td>$value</td>)   : q(<td></td>);
		say defined $missing ? qq(<td>$missing</td>) : q(<td></td>);
		say q(</tr>);
		$td = $td == 1 ? 2 : 1;    #row stripes
	}
	say q(</table></div>);
	return;
}
1;
