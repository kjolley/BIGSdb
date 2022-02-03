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
use JSON;
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
		$self->_upload( $scheme_id, scalar $q->param('checked_buffer') );
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
	my $lincode_pks =
	  $self->{'datastore'}
	  ->run_query( 'SELECT profile_id FROM lincodes WHERE scheme_id=?', $scheme_id, { fetch => 'col_arrayref' } );
	my %lincode_pks = map { $_ => 1 } @$lincode_pks;
	my %already_defined_here;
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
		if ( $lincode_pks{$pk_value} ) {
			push @errors, "LINcode has already been defined for row $i ($scheme_info->{'primary_key'}-$pk_value).";
			next;
		}
		if ( $already_defined_here{$pk_value} ) {
			push @errors,
			  "LINcode has been defined earlier in this upload for row $i ($scheme_info->{'primary_key'}-$pk_value).";
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
		$already_defined_here{$pk_value} = 1;
	}
	if (@errors) {
		local $" = q(<br />);
		$self->print_bad_status(
			{
				message => 'Data contains errors',
				detail  => "Your data contains the following errors:<p>@errors</p>"
			}
		);
		$self->_print_interface($scheme_id);
		return;
	}
	if ( !@$data ) {
		$self->print_bad_status(
			{
				message => 'No valid data',
				detail  => 'Your upload contains no valid LINcode data.'
			}
		);
		$self->_print_interface($scheme_id);
		return;
	}
	my $filename = $self->_write_checked_file($data);
	say q(<div class="box" id="resultsheader"><h2>Import status</h2><p>No obvious )
	  . q(problems identified so far.</p>);
	say $q->start_form;
	say $q->hidden($_) foreach qw (page db scheme_id);
	say $q->hidden( checked_buffer => $filename );
	$self->print_action_fieldset( { submit_label => 'Import data', no_reset => 1 } );
	say $q->end_form;
	say q(</div>);
	say q(<div class="box" id="resultstable"><h2>Data to be imported</h2>);
	say q(<div class="scrollable">);
	$self->_print_checked_data_table( $scheme_id, $data );
	say q(</div>);
	say q(</div>);
	return;
}

sub _print_checked_data_table {
	my ( $self, $scheme_id, $data ) = @_;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $lincode_scheme = $self->{'datastore'}
	  ->run_query( 'SELECT * FROM lincode_schemes WHERE scheme_id=?', $scheme_id, { fetch => 'row_hashref' } );
	my @thresholds = split /;/x, $lincode_scheme->{'thresholds'};
	my @headers = ( $scheme_info->{'primary_key'} );
	foreach my $threshold (@thresholds) {
		push @headers, "threshold_$threshold";
	}
	say q(<table class="resultstable">);
	local $" = q(</th><th>);
	say qq(<tr><th>@headers</th>);
	my $td = 1;
	foreach my $row (@$data) {
		print qq(<tr class="td$td"><td>$row->{$scheme_info->{'primary_key'}}</td>);
		foreach my $threshold (@thresholds) {
			print qq(<td>$row->{'thresholds'}->{$threshold}</td>);
		}
		say q(</tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</table>);
	return;
}

sub _write_checked_file {
	my ( $self, $data ) = @_;
	my $json      = JSON->new->allow_nonref;
	my $filename  = BIGSdb::Utils::get_random() . '.json';
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$filename";
	open( my $fh, '>:encoding(utf8)', $full_path ) || $logger->error("Cannot open $full_path for writing.");
	say $fh $json->encode($data);
	close $fh;
	return $filename;
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

sub _upload {
	my ( $self, $scheme_id, $checked_file ) = @_;
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$checked_file";
	my $json_ref  = BIGSdb::Utils::slurp($full_path);
	my $json      = JSON->new->allow_nonref;
	my $data      = $json->decode($$json_ref);
	my $lincode_scheme =
	  $self->{'datastore'}
	  ->run_query( 'SELECT * FROM lincode_schemes WHERE scheme_id=?', $scheme_id, { fetch => 'row_hashref' } );
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my @thresholds = split /;/x, $lincode_scheme->{'thresholds'};
	my $curator_id = $self->get_curator_id;
	eval {
		foreach my $record (@$data) {
			my $lincode = [];
			push @$lincode, $record->{'thresholds'}->{$_} foreach @thresholds;
			$self->{'db'}->do(
				'INSERT INTO lincodes(scheme_id,profile_id,lincode,curator,datestamp) VALUES (?,?,?,?,?)',
				undef,
				$scheme_id,
				$record->{ $scheme_info->{'primary_key'} },
				BIGSdb::Utils::get_pg_array( $lincode ),
				$curator_id,
				'now'
			);
		}
	};
	if ($@) {
		$logger->error($@);
		my $detail;
		if ( $@ =~ /duplicate/ && $@ =~ /unique/ ) {
			$detail =
			    q(<p>Data entry would have resulted in records with either duplicate ids or another )
			  . q(unique field with duplicate values.</p>);
		}
		$self->print_bad_status(
			{
				message => q(Database update failed - transaction cancelled - no records have been touched.),
				detail  => $detail
			}
		);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
			$self->print_good_status(
		{
			message       => q(LINcodes added.),
			navbar        => 1,
			more_text     => q(Add more),
			more_url      => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=lincodeBatchAdd&amp;scheme_id=$scheme_id)
		}
	);
	}
	return;
}
1;
