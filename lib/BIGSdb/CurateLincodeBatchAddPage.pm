#Written by Keith Jolley
#Copyright (c) 2022, University of Oxford
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
package BIGSdb::CurateLincodeBatchAddPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use BIGSdb::Constants qw(:interface);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my $self        = shift;
	my $scheme_id   = $self->{'cgi'}->param('scheme_id');
	my $scheme_desc = q();
	if ( $scheme_id && BIGSdb::Utils::is_int($scheme_id) ) {
		my $set_id = $self->get_set_id;
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
		$scheme_desc = $scheme_info->{'name'} // q();
	}
	return "Batch add new $scheme_desc LINcodes";
}

sub print_content {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	my $set_id    = $self->get_set_id;
	if ( !$self->{'datastore'}->scheme_exists($scheme_id) ) {
		say q(<h1>Batch insert profiles</h1>);
		$self->print_bad_status( { message => q(Invalid scheme passed.) } );
		return;
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say q(<h1>Batch insert profiles</h1>);
		$self->print_bad_status(
			{
				message => q(You can only add profiles to a sequence/profile database - )
				  . q(this is an isolate database.)
			}
		);
		return;
	}
	my $title = $self->get_title;
	say qq(<h1>$title</h1>);
	if ( !$self->can_modify_table('lincodes') ) {
		$self->print_bad_status( { message => q(Your user account is not allowed to add new LINcodes.) } );
		return;
	}
	if ($set_id) {
		if ( !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id ) ) {
			$self->print_bad_status( { message => q(The selected scheme is inaccessible.) } );
			return;
		}
	}
	my $lincode_scheme = $self->{'datastore'}
	  ->run_query( 'SELECT * FROM lincode_schemes WHERE scheme_id=?', $scheme_id, { fetch => 'row_hashref' } );
	if ( !$lincode_scheme ) {
		$self->print_bad_status(
			{
				message => q(This scheme doesn't have LINcode thresholds defined for it.  )
				  . q(LINcodes cannot be entered until this has been done.)
			}
		);
		return;
	}
	if ( $q->param('checked_buffer') ) {
		$self->_upload($scheme_id);
	} elsif ( $q->param('data') && $q->param('submit') ) {
		$self->_check($scheme_id);
	} else {
		my $icon = $self->get_form_icon( 'profiles', 'plus' );
		say $icon;
		$self->_print_interface($scheme_id);
	}
	return;
}

sub _print_interface {
	my ( $self, $scheme_id ) = @_;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	say q(<div class="box" id="queryform"><h2>Instructions</h2>)
	  . qq(<p>This page allows you to upload LINcodes linked to $primary_key as tab-delimited text or copied )
	  . q(from a spreadsheet.</p>)
	  . q(<ul><li>Field header names must be included and fields can be in any order.</li>);
	say q(</ul><h2>Templates</h2>);
	my ( $text, $excel ) = ( TEXT_FILE, EXCEL_FILE );
	say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableHeader&amp;)
	  . qq(table=lincodes&amp;scheme_id=$scheme_id" title="Tab-delimited text header">$text</a>)
	  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=excelTemplate&amp;)
	  . qq(table=lincodes&amp;scheme_id=$scheme_id" title="Excel format">$excel</a></p>);
	say q(<h2>Upload</h2>);
	my $q = $self->{'cgi'};
	say $q->start_form;
	my ( $users, $user_names ) = $self->{'datastore'}->get_users( { blank_message => 'Select sender ...' } );
	$user_names->{-1} = 'Override with sender field';
	say q[<fieldset style="float:left"><legend>Please paste in tab-delimited text ]
	  . q[(<strong>include a field header as the first line</strong>)</legend>];
	say $q->hidden($_) foreach qw (page db scheme_id);
	say $q->textarea(
		-name     => 'data',
		-rows     => 20,
		-columns  => 80,
		-required => 'required',
		-style    => 'max-width:85vw'
	);
	say q(</fieldset>);
	$self->print_action_fieldset( { scheme_id => $scheme_id } );
	say $q->end_form;
	say q(</div>);
	return;
}

sub _check {
	my ( $self, $scheme_id ) = @_;
	my $q            = $self->{'cgi'};
	my @rows         = split /\n/x, $q->param('data');
	my $header_row   = shift @rows;
	my $header_check = $self->_check_headers( $scheme_id, $header_row );
	if ( $header_check->{'error'} ) {
		$self->print_bad_status(
			{
				message => $header_check->{'error'},
			}
		);
		$self->_print_interface($scheme_id);
		return;
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $pk_values = $self->{'datastore'}->run_query(
		'SELECT value FROM profile_fields WHERE (scheme_id,scheme_field)=(?,?)',
		[ $scheme_id, $scheme_info->{'primary_key'} ],
		{ fetch => 'col_arrayref' }
	);
	my %pk_values = map { $_ => 1 } @$pk_values;
	my $lincode_scheme =
	  $self->{'datastore'}
	  ->run_query( 'SELECT * FROM lincode_schemes WHERE scheme_id=?', $scheme_id, { fetch => 'row_hashref' } );
	my @thresholds = split /;/x, $lincode_scheme->{'thresholds'};
	my $i = 0;
	my @errors;
	my $data = [];

	foreach my $row (@rows) {
		$i++;
		$row =~ s/^\s+|\s+$//gx;
		next if !$row;
		my @values = split /\t/x, $row;
		if ( @values > $header_check->{'count'} ) {
			push @errors, "Row $i contains too many values.";
			next;
		}
		if ( @values < $header_check->{'count'} ) {
			push @errors, "Row $i contains too few values.";
			next;
		}
		my $pk_value = $values[ $header_check->{'positions'}->{ $scheme_info->{'primary_key'} } ];
		if ( !$pk_values{$pk_value} ) {
			push @errors, "$scheme_info->{'primary_key'} for row $i is not defined in scheme.";
			next;
		}
		my $record = { $scheme_info->{'primary_key'} => $pk_value };
		foreach my $threshold (@thresholds) {
			my $value = $values[ $header_check->{'positions'}->{"threshold_$threshold"} ];
			$value =~ s/^\s+|\s+$//gx;
			if ( !BIGSdb::Utils::is_int($value) ) {
				push @errors, "Row $i contains non-integer LINcode values.";
				last;
			}
			$record->{'thresholds'}->{$threshold} = $value;
		}
		push @$data, $record;
	}
	if (@errors) {
		local $" = q(<br />);
		$self->print_bad_status(
			{
				message => 'Data contains errors',
				detail  => "Your data contains the following errors:<p>@errors</p>"
			}
		);
	}
	use Data::Dumper;
	$logger->error( Dumper $data);
}

sub _check_headers {
	my ( $self, $scheme_id, $header_row ) = @_;
	$header_row //= q();
	$header_row =~ s/^\s+|\s+$//gx;
	return { error => 'Header row is empty.' } if !$header_row;
	my @fields = split /\t/x, $header_row;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $lincode_scheme =
	  $self->{'datastore'}
	  ->run_query( 'SELECT * FROM lincode_schemes WHERE scheme_id=?', $scheme_id, { fetch => 'row_hashref' } );
	my @thresholds = split /;/x, $lincode_scheme->{'thresholds'};
	my @expected_fields = ( $scheme_info->{'primary_key'} );
	push @expected_fields, "threshold_$_" foreach @thresholds;
	my %expected = map { $_ => 1 } @expected_fields;
	my %present;
	my @unrecognised;
	my @missing;
	my $positions = {};
	my $i         = 0;

	foreach my $field (@fields) {
		$field =~ s/^\s+|\s+$//gx;
		if ( !$expected{$field} ) {
			push @unrecognised, BIGSdb::Utils::escape_html($field);
		} else {
			$present{$field} = 1;
			$positions->{$field} = $i;
		}
		$i++;
	}
	foreach my $field (@expected_fields) {
		if ( !$present{$field} ) {
			push @missing, BIGSdb::Utils::escape_html($field);
		}
	}
	if (@unrecognised) {
		local $" = q(, );
		return { error => "Your data includes unrecognised field headers: @unrecognised." };
	}
	if (@missing) {
		local $" = q(, );
		return { error => "You data does not include required headers: @missing." };
	}
	return { positions => $positions, count => scalar keys %$positions };
}
1;
