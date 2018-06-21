#Written by Keith Jolley
#Copyright (c) 2018, University of Oxford
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
package BIGSdb::CurateBatchAddSeqbinPage;
use strict;
use warnings;
use 5.010;
use JSON;
use parent qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
use BIGSdb::Constants qw(:interface);
my $logger = get_logger('BIGSdb.Page');
use constant LIMIT => 100;

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Batch upload sequence assemblies to multiple isolate records</h1>);
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		$self->print_bad_status(
			{ message => q(This function can only be called for an isolate database.), navbar => 1 } );
		return;
	} elsif ( !$self->can_modify_table('sequence_bin') ) {
		$self->print_bad_status(
			{
				message => q(Your user account is not allowed to upload sequences to the database.),
				navbar  => 1
			}
		);
		return;
	}
	my $upload_id = $q->param('upload_id') // BIGSdb::Utils::get_random();
	if ( $upload_id !~ /BIGSdb_\d+_\d+_\d+/x ) {
		$self->print_bad_status(
			{
				message     => q(Upload id is invalid. Please restart upload.),
				navbar      => 1,
				reload_url  => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSeqbin",
				reload_text => 'Restart'
			}
		);
		return;
	}
	$q->param( upload_id => $upload_id );
	my $field = $q->param('field');
	if ( $q->param('filenames') ) {
		my $check_data = $self->_check( $field, \$q->param('filenames') );
		if ( $check_data->{'message'} ) {
			$self->_print_interface;
			$self->print_bad_status( { message => $check_data->{'message'} } );
			return;
		}
		if ( keys %{ $check_data->{'invalid'} } ) {
			$self->_print_interface;
			$self->_print_problems($check_data);
			return;
		}
		if ( !@{ $check_data->{'validated'} } ) {
			$self->_print_interface;
			$self->print_bad_status( { message => 'No valid data submitted' } );
			return;
		}
		$self->_file_upload( $field, $check_data->{'temp_file'} );
		return;
	}
	if ( $field && $q->param('temp_file') ) {
		$self->_file_upload( $field, $q->param('temp_file') );
		return;
	}
	$self->_print_interface;
	return;
}

sub _check {
	my ( $self, $id_field, $data ) = @_;
	my $q = $self->{'cgi'};
	if ( !$self->{'xmlHandler'}->is_field($id_field) ) {
		return { message => 'Selected field is not valid' };
	}
	my $field_atts = $self->{'xmlHandler'}->get_field_attributes($id_field);
	my $int_field  = $field_atts->{'type'} =~ /int/x ? 1 : 0;
	my @rows       = split /\r?\n/x, $$data;
	my $validated  = [];
	my $invalid    = {};
	my $number     = 0;
	foreach my $row (@rows) {
		$row =~ s/^\s+|\s+$//x;
		next if !$row;
		$number++;
		my ( $id, $filename, @extra_cols ) = split /\t/x, $row;
		if ( !$filename ) {
			$invalid->{$number} = { id => $id, problem => 'No filename!' };
			next;
		}
		if ( $filename =~ /\//x ) {
			$invalid->{$number} = { id => $id, problem => 'Filename should not include directory path!' };
			next;
		}
		if (@extra_cols) {
			$invalid->{$number} = { id => $id, problem => 'Too many columns!' };
			next;
		}
		s/^\s+|\s+$//gx foreach ( $id, $filename );    #Trim trailing spaces
		if ( $int_field && !BIGSdb::Utils::is_int($id) ) {
			$invalid->{$number} =
			  { id => $id, problem => "$id_field is an integer field - you provided a non-integer value" };
			next;
		}
		my $ids = $self->{'datastore'}->run_query( "SELECT id FROM $self->{'system'}->{'view'} WHERE $id_field=?",
			$id, { fetch => 'col_arrayref', cache => 'CurateBatchAddSeqbin::check_id' } );
		my $matching_records = @$ids;
		if ( !$matching_records ) {
			$invalid->{$number} = { id => $id, problem => 'No matching record!' };
			next;
		}
		if ( $matching_records > 1 ) {
			$invalid->{$number} =
			  { id => $id, problem => "$matching_records matching records - cannot uniquely identify!" };
			next;
		}
		push @$validated => { row => $number, identifier => $id, id => $ids->[0], filename => $filename };
	}
	my $temp_file = $self->_write_validated_temp_file($validated);
	return { invalid => $invalid, validated => $validated, temp_file => $temp_file };
}

sub _print_problems {
	my ( $self, $check_data ) = @_;
	my $td = 1;
	my @table_rows;
	foreach my $row ( sort keys %{ $check_data->{'invalid'} } ) {
		push @table_rows, qq(<tr class="td$td"><td>$row</td><td>$check_data->{'invalid'}->{$row}->{'id'}</td>)
		  . qq(<td style="text-align:left">$check_data->{'invalid'}->{$row}->{'problem'}</td></tr>);
		$td = $td == 1 ? 2 : 1;
	}
	my $table =
	  qq(<table class="resultstable"><tr><th>Row</th><th>identifier</th><th>Problem</th></tr>@table_rows</table>);
	$self->print_bad_status( { message => 'Invalid data submitted', detail => $table } );
	return;
}

sub _file_upload {
	my ( $self, $field, $temp_file ) = @_;
	my $q = $self->{'cgi'};
	my $upload_id = $q->param('upload_id') // q();
	if ( $upload_id !~ /BIGSdb_\d+_\d+_\d+/x ) {
		$self->print_bad_status(
			{
				message     => q(Upload id is invalid. Please restart upload.),
				navbar      => 1,
				reload_url  => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSeqbin",
				reload_text => 'Restart'
			}
		);
		return;
	}
	if ( $q->param('Cancel') ) {
		$self->_cancel($temp_file);
	}
	my $validated = [];
	my $failed;
	try {
		$validated = $self->_parse_validated_temp_file($temp_file);
	}
	catch BIGSdb::CannotOpenFileException with {
		$failed = 1;
	};
	if ($failed) {
		$self->_print_interface;
		$self->print_bad_status( { message => 'Cannot read temporary file.' } );
		return;
	}
	if ( !@$validated ) {
		$self->print_bad_status(
			{
				message     => 'No records selected.',
				navbar      => 1,
				reload_url  => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSeqbin",
				reload_text => 'Restart'
			}
		);
		return;
	}
	say q(<div class="box resultstable"><div class="scrollable">);
	say q(<p>Please upload the assembly contig files for each isolate record.<p>);
	say $q->start_form;
	say q(<table class="resultstable">);
	say q(<tr><th rowspan="2">Cancel</th><th rowspan="2">id</th>);
	say qq(<th rowspan="2">$field</th>) if $field ne 'id';
	say qq(<th rowspan="2">$self->{'system'}->{'labelfield'}</th>) if $field ne $self->{'system'}->{'labelfield'};
	say q(<th colspan="2">Current sequence bin state</th><th rowspan="2">filename</th>)
	  . q(<th rowspan="2">Upload status</th></tr>);
	say q(<tr><th>Contigs</th><th>Total size (bp)</th></tr>);
	my $td        = 1;
	my $to_upload = 0;

	foreach my $row (@$validated) {
		say qq(<tr class="td$td"><td>);
		say $q->checkbox( -name => "cancel_$row->{'id'}", -label => '' );
		say qq(</td><td>$row->{'id'}</td>);
		say qq(<td>$row->{'identifier'}</td>) if $field ne 'id';
		if ( $field ne $self->{'system'}->{'labelfield'} ) {
			my $name = $self->get_isolate_name_from_id( $row->{'id'} );
			say qq(<td>$name</td>);
		}
		my $stats = $self->{'datastore'}->get_seqbin_stats( $row->{'id'}, { general => 1 } );
		foreach my $att (qw(contigs total_length)) {
			my $value = BIGSdb::Utils::commify( $stats->{$att} ) || q(-);
			say qq(<td>$value</td>);
		}
		my $filename = "$self->{'config'}->{'tmp_dir'}/${upload_id}_$row->{'filename'}";
		say -e $filename
		  ? qq(<td><a href="/tmp/${upload_id}_$row->{'filename'}">$row->{'filename'}</a></td>)
		  : qq(<td>$row->{'filename'}</td>);
		my ( $good, $bad ) = ( GOOD, BAD );
		if ( -e $filename ) {
			say qq(<td>$good</td>);
		} else {
			say qq(<td>$bad<?td>);
			$to_upload++;
		}
		say q(</tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</table>);
	say $q->submit( -name => 'Cancel', -class => 'smallbutton' );
	$q->param( temp_file => $temp_file );
	say $q->hidden($_) foreach qw(db page upload_id field temp_file);
	say $q->end_form;
	if ($to_upload) {
		my $plural = $to_upload == 1 ? q() : q(s);
		say qq(<p class="statusbad">$to_upload FASTA file$plural left to upload.</p>);
	}
	$self->_print_file_upload_fieldset;
	$self->print_navigation_bar(
		{
			back     => 1,
			back_url => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSeqbin"
		}
	);
	say q(</div></div>);
	return;
}

sub _cancel {
	my ( $self, $temp_file ) = @_;
	my $q = $self->{'cgi'};
	my $failed;
	my $validated;
	try {
		$validated = $self->_parse_validated_temp_file($temp_file);
	}
	catch BIGSdb::CannotOpenFileException with {
		$failed = 1;
	};
	return if $failed;
	my $new_validated = [];
	foreach my $row (@$validated) {
		next if $q->param("cancel_$row->{'id'}");
		push @$new_validated, $row;
	}
	$self->_write_validated_temp_file( $new_validated, $temp_file );
	return;
}

sub _print_file_upload_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};

	#	if ( $submission_id =~ /(BIGSdb_\d+_\d+_\d+)/x ) {    #Untaint
	#		$submission_id = $1;
	if ( $q->param('file_upload') ) {

		#			$self->_upload_files($submission_id);
	}
	if ( $q->param('delete') ) {

		#			$self->_delete_selected_submission_files($submission_id);
	}

	#	}
	say q(<fieldset style="float:left"><legend>Contig assembly files</legend>);
	my $nice_file_size = BIGSdb::Utils::get_nice_size( $self->{'config'}->{'max_upload_size'} );
	say q(<p>Please upload contig assemblies with the filenames as you specified (indicated in the table). );
	say qq(Individual filesize is limited to $nice_file_size. You can upload up to $nice_file_size in one go, )
	  . q(although you can upload multiple times so that the total size of the submission can be larger.</p>);
	say $q->start_form;
	print $q->filefield( -name => 'file_upload', -id => 'file_upload', -multiple );
	say $q->submit( -name => 'Upload files', -class => BUTTON_CLASS );

	#	$q->param( no_check => 1 );
	say $q->hidden($_) foreach qw(db page upload_id);
	say $q->end_form;
##	my $files = $self->_get_submission_files($submission_id);
	#	if (@$files) {
	#		say $q->start_form;
	#		$self->_print_submission_file_table( $submission_id, { delete_checkbox => 1 } );
	#		$q->param( delete => 1 );
	#		say $q->hidden($_)
	#		  foreach qw(db page alleles profiles isolates genomes locus submission_id delete no_check view);
	#		say $q->submit( -label => 'Delete selected files', -class => BUTTON_CLASS );
	#		say $q->end_form;
	#	}
	say q(</fieldset>);
	return;
}

sub _write_validated_temp_file {
	my ( $self, $validated, $filename ) = @_;
	my $json = encode_json($validated);
	my $full_file_path;
	if ($filename) {
		if ( $filename =~ /(BIGSdb_\d+_\d+_\d+\.txt)/x ) {    #Untaint
			$full_file_path = "$self->{'config'}->{'secure_tmp_dir'}/$1";
		}
	} else {
		do {
			$filename       = BIGSdb::Utils::get_random() . '.txt';
			$full_file_path = "$self->{'config'}->{'secure_tmp_dir'}/$filename";
		} while ( -e $full_file_path );
	}
	open( my $fh, '>:raw', $full_file_path ) || $logger->error("Cannot open $full_file_path for writing");
	say $fh $json;
	close $fh;
	return $filename;
}

sub _parse_validated_temp_file {
	my ( $self, $filename ) = @_;
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$filename";
	my $json_ref  = BIGSdb::Utils::slurp($full_path);
	my $data      = decode_json($$json_ref);
	return $data;
}

sub _print_interface {
	my ($self) = @_;
	my $icon = $self->get_form_icon( 'sequence_bin', 'plus' );
	say $icon;
	my $q = $self->{'cgi'};
	say q(<div class="box queryform"><div class="scrollable">);
	say q(<p>This function allows you to upload assembly contig files for multiple records together.</p>);
	say q(<p>The first step in the upload process is to state which assembly contig FASTA file should be linked to )
	  . q(each isolate record. You can use any provenance metadata field that uniquely identifies an isolate.</p>);
	my $limit = LIMIT;
	say qq(<p>You can upload up to $limit genomes at a time.</p>);
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Identifying field name</legend>);
	say q(<label for="field">Field:</label>);
	my $fields = $self->{'xmlHandler'}->get_field_list;
	say $q->popup_menu( -id => 'field', -name => 'field', -values => $fields );
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Filenames</legend>);
	say q(<p>Paste in tab-delimited text, e.g. copied from a spreadsheet, consisting of two columns. The first column )
	  . q(should be the value for the isolate identifier field (specified above), and the second should be the )
	  . q(filename that you are going to upload. You need to ensure that you use the full filename, including any )
	  . q(suffix such as .fas or .fasta, which may be hidden by your operating system.</p>);
	say $q->textarea(
		-id          => 'filenames',
		-name        => 'filenames',
		-cols        => 40,
		-rows        => 6,
		-placeholder => "1001\tisolate_1001.fasta\n1002\tisolate_1002.fasta"
	);
	say q(</fieldset>);
	$self->print_action_fieldset;
	say $q->hidden($_) foreach qw(db page upload_id);
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Batch add new sequences - $desc";
}
1;
