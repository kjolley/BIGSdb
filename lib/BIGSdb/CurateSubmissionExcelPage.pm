#Written by Keith Jolley
#Copyright (c) 2014-2015, University of Oxford
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
package BIGSdb::CurateSubmissionExcelPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateTableHeaderPage);
use Excel::Writer::XLSX;
use Excel::Writer::XLSX::Utility;

sub initiate {
	my ($self) = @_;
	$self->{'type'}       = 'xlsx';
	$self->{'attachment'} = 'upload_template.xlsx';
	return;
}

sub print_content {
	my ($self) = @_;
	binmode(STDOUT);
	my $workbook  = Excel::Writer::XLSX->new( \*STDOUT );
	my $worksheet = $workbook->add_worksheet('submission');
	$self->{'header_format'} = $workbook->add_format;
	$self->{'header_format'}->set_align('center');
	$self->{'header_format'}->set_bold;
	my $q         = $self->{'cgi'};
	my $table     = $q->param('table') || '';
	my $scheme_id = $q->param('scheme_id');

	if ( !$self->{'datastore'}->is_table($table) && !@{ $self->{'xmlHandler'}->get_sample_field_list } ) {
		$worksheet->write( 'A1', "Table $table does not exist!" );
		return;
	}
	my $headers = [];
	if ( $table eq 'profiles' ) {
		if ( $self->{'system'}->{'dbtype'} eq 'sequences' && BIGSdb::Utils::is_int($scheme_id) ) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
			if ($scheme_info) {
				push @$headers, 'id' if $q->param('id_field');
				push @$headers, $scheme_info->{'primary_key'}
				  if $scheme_info->{'primary_key'} && !$q->param('no_fields');
				my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
				push @$headers, @$loci;
				my $fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
				foreach my $field (@$fields) {
					push @$headers, $field if $field ne $scheme_info->{'primary_key'} && !$q->param('no_fields');
				}
			} else {
				$worksheet->write( 'A1', 'Invalid scheme!' );
				return;
			}
		} else {
			$worksheet->write( 'A1', 'Invalid scheme!' );
			return;
		}
	} else {
		$headers = $self->get_headers($table);
		if ( $table eq 'isolates' && $q->param('addCols') ) {
			my @cols = split /,/x, $q->param('addCols');
			push @$headers, @cols;
		}
	}
	my $col = 0;
	my $allowed_values_worksheet;
	if ( $table eq 'isolates' ) {
		$allowed_values_worksheet = $workbook->add_worksheet('allowed_values');
	}
	foreach my $field (@$headers) {
		push @{ $self->{'values'}->{$field} }, $field;
		$worksheet->write( 0, $col, $field, $self->{'header_format'} );
		if ( $table eq 'isolates' ) {
			$self->_print_isolate_allowed_values( $allowed_values_worksheet, $field );
			$self->_set_isolate_validation( $worksheet, $field, $col );
			my $att = $self->{'xmlHandler'}->get_field_attributes($field);
			if ( $att->{'comments'} ) {
				$worksheet->write_comment( 0, $col, $att->{'comments'} );
			}
		}
		my $col_width = $self->_get_col_width($field);
		if ( $field eq 'aliases' ) {
			$worksheet->write_comment( 0, $col,
				"Aliases:\nEnter semi-colon (;) separated list of alternative names for this item." );
		} elsif ( $field eq 'references' ) {
			$worksheet->write_comment( 0, $col,
				"References:\nEnter semi-colon (;) separated list of PubMed ids of papers to associate with this item."
			);
		}
		$worksheet->set_column( $col, $col, $col_width );
		$col++;
	}
	$worksheet->set_selection( 1, 0 );
	return;
}

sub _get_col_width {
	my ( $self, $field ) = @_;
	my $values = $self->{'values'}->{$field};
	my $width  = 5;
	foreach my $value (@$values) {
		my $value_width = int( 0.9 * ( length $value ) + 2 );
		$width = $value_width if $value_width > $width;
	}
	return $width;
}

sub _set_isolate_validation {
	my ( $self, $worksheet, $field, $col ) = @_;
	if ( $self->{'xmlHandler'}->is_field($field) ) {
		my $options = $self->{'xmlHandler'}->get_field_option_list($field);
		if (@$options) {
			my $range_top = xl_rowcol_to_cell( 1, $self->{'allowed'}->{$field}->{'col'}, 1, 1 );
			my $range_bottom =
			  xl_rowcol_to_cell( $self->{'allowed'}->{$field}->{'row'}, $self->{'allowed'}->{$field}->{'col'}, 1, 1 );
			$worksheet->data_validation( 1, $col, 500, $col,
				{ validate => 'list', source => "allowed_values!$range_top:$range_bottom" } );
		}
	}
	return;
}

sub _print_isolate_allowed_values {
	my ( $self, $worksheet, $field ) = @_;
	state $col = 0;
	my $options      = $self->{'xmlHandler'}->get_field_option_list($field);
	my $col_width    = 5;
	my $field_length = int( 0.9 * ( length $field ) + 2 );
	$col_width = $field_length if $field_length > $col_width;
	if (@$options) {
		$worksheet->write( 0, $col, $field, $self->{'header_format'} );
		my $row = 1;
		foreach my $value (@$options) {
			$worksheet->write( $row, $col, $value );
			push @{ $self->{'values'}->{$field} }, $value;    #used for calculating column width
			my $length = int( 0.9 * ( length $value ) + 2 );
			$col_width = $length if $length > $col_width;
			$row++;
		}
		$self->{'allowed'}->{$field}->{'row'} = $row - 1;
		$self->{'allowed'}->{$field}->{'col'} = $col;
		$worksheet->set_column( $col, $col, $col_width );
		$col++;
	}
	return;
}
1;
