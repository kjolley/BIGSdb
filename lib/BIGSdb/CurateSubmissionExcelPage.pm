#Written by Keith Jolley
#Copyright (c) 2014-2019, University of Oxford
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
use BIGSdb::Constants qw(SEQ_METHODS :limits);
use Excel::Writer::XLSX;
use Excel::Writer::XLSX::Utility;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

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

	if ( !$self->{'datastore'}->is_table($table) ) {
		$worksheet->write( 'A1', "Table $table does not exist!" );
		return;
	}
	my $headers = [];
	if ( $table eq 'profiles' ) {
		if ( $self->{'system'}->{'dbtype'} eq 'sequences' && BIGSdb::Utils::is_int($scheme_id) ) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
			my $set_id = $self->get_set_id;
			if ($scheme_info) {
				push @$headers, 'id' if $q->param('id_field');
				push @$headers, $scheme_info->{'primary_key'}
				  if $scheme_info->{'primary_key'} && !$q->param('no_fields');
				my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
				foreach my $locus (@$loci) {
					my $label = $self->clean_locus( $locus, { text_output => 1, no_common_name => 1 } );
					push @$headers, $label // $locus;
				}
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
		$self->_print_isolate_allowed_loci( $workbook->add_worksheet('allowed_loci') );
		$self->_print_isolate_eav_fields($workbook);
	}
	foreach my $field (@$headers) {
		push @{ $self->{'values'}->{$field} }, $field;
		$worksheet->write( 0, $col, $field, $self->{'header_format'} );
		if ( $table eq 'isolates' ) {
			$self->_print_isolate_allowed_values( $allowed_values_worksheet, $field,
				{ eav_field => $self->{'datastore'}->is_eav_field($field) } );
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
	if (   $self->{'xmlHandler'}->is_field($field)
		|| $field eq 'sequence_method'
		|| $self->{'datastore'}->is_eav_field($field) )
	{
		my $options;
		if ( $self->{'datastore'}->is_eav_field($field) ) {
			my $eav_field = $self->{'datastore'}->get_eav_field($field);
			return if !$eav_field->{'option_list'};
			@$options = split /\s*;\s*/x, $eav_field->{'option_list'};
		} else {
			$options = $self->{'xmlHandler'}->get_field_option_list($field);
			$options = [SEQ_METHODS] if $field eq 'sequence_method';
		}
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
	my ( $self, $worksheet, $field, $options ) = @_;
	state $col = 0;
	my $option_list = [];
	if ( $options->{'eav_field'} ) {
		my $eav_field = $self->{'datastore'}->get_eav_field($field);
		return if !$eav_field->{'option_list'} || $eav_field->{'no_curate'};
		@$option_list = split /\s*;\s*/x, $eav_field->{'option_list'};
	} else {
		$option_list = $self->{'xmlHandler'}->get_field_option_list($field);
		$option_list = [SEQ_METHODS] if $field eq 'sequence_method';
	}
	my $col_width = 5;
	my $field_length = int( 0.9 * ( length $field ) + 2 );
	$col_width = $field_length if $field_length > $col_width;
	if (@$option_list) {
		$worksheet->write( 0, $col, $field, $self->{'header_format'} );
		my $row = 1;
		foreach my $value (@$option_list) {
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

sub _print_isolate_allowed_loci {
	my ( $self, $worksheet, $field ) = @_;
	my $set_id = $self->get_set_id;
	my @col_max_length = ( 13, 13, 7 );
	$worksheet->write( 0, 0, 'primary name', $self->{'header_format'} );
	$worksheet->write( 0, 1, 'common name',  $self->{'header_format'} );
	$worksheet->write( 0, 2, 'aliases',      $self->{'header_format'} );
	my $loci = $self->{'datastore'}->get_loci( { set_id => $set_id } );
	my $row = 1;
	foreach my $locus ( sort { lc($a) cmp lc($b) } @$loci ) {
		my $locus_info = $self->{'datastore'}->get_locus_info( $locus, { set_id => $set_id } );
		my $aliases    = $self->{'datastore'}->get_locus_aliases($locus);
		my $primary    = $locus_info->{'set_name'} // $locus;
		$col_max_length[0] = length $primary if length $primary > $col_max_length[0];
		$worksheet->write( $row, 0, $primary );
		my $common = $locus_info->{'set_common_name'} // $locus_info->{'common_name'} // '';
		$worksheet->write( $row, 1, $common );
		$col_max_length[1] = length $common if length $common > $col_max_length[1];
		local $" = q(; );
		$worksheet->write( $row, 2, "@$aliases" );
		$col_max_length[2] = length("@$aliases") if length("@$aliases") > $col_max_length[2];
		$row++;
	}
	foreach my $col ( 0 .. 2 ) {
		my $length = int( 0.9 * ( $col_max_length[$col] ) + 2 );
		$worksheet->set_column( $col, $col, $length );
	}
	return;
}

sub _print_isolate_eav_fields {
	my ( $self, $workbook ) = @_;
	my $eav_fields = $self->{'datastore'}->get_eav_fieldnames( { curate => 1 } );
	return if !@$eav_fields;
	my $field_name = $self->{'system'}->{'eav_fields'} // 'phenotypic_fields';
	$field_name =~ s/\s/_/gx;
	my $worksheet = $workbook->add_worksheet($field_name);
	$worksheet->write( 0, 0, 'field', $self->{'header_format'} );
	my $row = 1;

	foreach my $field (@$eav_fields) {
		$worksheet->write( $row, 0, $field );
		$row++;
	}
	return;
}
1;
