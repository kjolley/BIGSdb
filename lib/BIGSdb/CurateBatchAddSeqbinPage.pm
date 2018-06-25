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
use File::Path qw(make_path remove_tree);
use BIGSdb::Constants qw(:interface SEQ_METHODS);
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
	my $field = $q->param('field');
	if ( $q->param('validate') && $q->param('temp_file') ) {
		$self->_validate( $field, $q->param('temp_file') );
		return;
	}
	if ( $q->param('upload') && $q->param('temp_file') ) {
		$self->_upload( $field, $q->param('temp_file') );
		return;
	}
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
	my $field_atts    = $self->{'xmlHandler'}->get_field_attributes($id_field);
	my $int_field     = $field_atts->{'type'} =~ /int/x ? 1 : 0;
	my @rows          = split /\r?\n/x, $$data;
	my $validated     = [];
	my $invalid       = {};
	my $number        = 0;
	my $id_used       = {};
	my $filename_used = {};
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
		if ( $id_used->{$id} ) {
			$invalid->{$number} = { id => $id, problem => "$id is listed more than once!" };
			next;
		}
		if ( $filename_used->{$filename} ) {
			$invalid->{$number} = { id => $id, problem => "Filename $filename is used more than once!" };
			next;
		}
		push @$validated => { row => $number, identifier => $id, id => $ids->[0], filename => $filename };
		$id_used->{$id}             = 1;
		$filename_used->{$filename} = 1;
	}
	my $temp_file = $self->_write_validated_temp_file($validated);
	return { invalid => $invalid, validated => $validated, temp_file => $temp_file };
}

sub _validate {
	my ( $self, $field, $temp_file ) = @_;
	my $q = $self->{'cgi'};
	if ( !$self->{'xmlHandler'}->is_field($field) ) {
		return { message => 'Selected field is not valid' };
	}
	my ( $validated, $failed );
	try {
		$validated = $self->_parse_validated_temp_file($temp_file);
	}
	catch BIGSdb::CannotOpenFileException with {
		$failed = 1;
	};
	if ($failed) {
		$self->_print_interface;
		$self->print_bad_status( { message => 'Cannot read temporary file. Please repeat upload' } );
		return;
	}
	say q(<div class="box resultstable"><div class="scrollable">);
	say q(<h2>Validation</h2>);
	say q(<table class="resultstable">);
	say q(<tr><th>id</th>);
	say qq(<th>$field</th>) if $field ne 'id';
	say qq(<th>$self->{'system'}->{'labelfield'}</th>)
	  if $field ne $self->{'system'}->{'labelfield'};
	say q(<th>filename</th><th>valid FASTA</th><th>contigs</th><th>total size</th></tr>);
	my $td      = 1;
	my $dir     = $self->_get_upload_dir;
	my $success = 0;
	my $failure = 0;

	foreach my $row (@$validated) {
		say qq(<tr class="td$td"><td>$row->{'id'}</td>);
		say qq(<td>$row->{'identifier'}</td>) if $field ne 'id';
		if ( $field ne $self->{'system'}->{'labelfield'} ) {
			my $name = $self->get_isolate_name_from_id( $row->{'id'} );
			say qq(<td>$name</td>);
		}
		say qq(<td>$row->{'filename'}</td>);
		my $filename = "$dir/$row->{'filename'}";
		my $seq_ref;
		my ( $good, $bad ) = ( GOOD, BAD );
		try {
			my $fasta_ref = BIGSdb::Utils::slurp($filename);
			$seq_ref = BIGSdb::Utils::read_fasta( $fasta_ref, { keep_comments => 1 } );
			say qq(<td><span class="statusbad">$good</td>);
			$success++;
		}
		catch BIGSdb::CannotOpenFileException with {
			say q(<td><span class="statusbad">Cannot open file</td>);
			$failure++;
		}
		catch BIGSdb::DataException with {
			my $exception = shift;
			my $msg =
			  $exception->{'-text'} =~ /format/x
			  ? 'Invalid format'
			  : 'Invalid DNA sequence';
			say qq(<td><span class="statusbad">$bad ($msg)</td>);
			$failure++;
		};
		if ($failure) {
			say q(<td>-</td><td>-</td>);
		} else {
			my $contigs = keys %$seq_ref;
			$contigs = BIGSdb::Utils::commify($contigs);
			my $size = 0;
			$size += length( $seq_ref->{$_} ) foreach keys %$seq_ref;
			$size = BIGSdb::Utils::commify($size);
			say qq(<td>$contigs</td><td>$size</td>);
		}
		say q(</tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</table>);
	if ($success) {
		my $plural = $success == 1 ? q() : q(s);
		say qq(<p>You can upload $success record$plural.</p>);
		say $q->start_form;
		say q(<fieldset style="float:left"><legend>Attributes</legend><ul>);
		my $sender;
		my $isolate_count = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM $self->{'system'}->{'view'}");
		my ( $users, $user_names ) = $self->{'datastore'}->get_users( { blank_message => 'Select sender ...' } );
		say q(</li><li><label for="sender" class="parameter">sender: !</label>);
		say $self->popup_menu(
			-name     => 'sender',
			-id       => 'sender',
			-values   => [ '', @$users ],
			-labels   => $user_names,
			-required => 'required',
			-default  => $sender
		);
		say q(</li><li><label for="method" class="parameter">method: </label>);
		my $method_labels = { '' => ' ' };
		say $q->popup_menu(
			-name   => 'method',
			-id     => 'method',
			-values => [ '', SEQ_METHODS ],
			-labels => $method_labels
		);
		my $seq_attributes =
		  $self->{'datastore'}->run_query( 'SELECT key,type,description FROM sequence_attributes ORDER BY key',
			undef, { fetch => 'all_arrayref', slice => {} } );

		if (@$seq_attributes) {
			foreach my $attribute (@$seq_attributes) {
				( my $label = $attribute->{'key'} ) =~ s/_/ /;
				say qq(<li><label for="$attribute->{'key'}" class="parameter">$label:</label>\n);
				say $q->textfield( -name => $attribute->{'key'}, -id => $attribute->{'key'} );
				if ( $attribute->{'description'} ) {
					say $self->get_tooltip(qq($attribute->{'key'} - $attribute->{'description'}.));
				}
			}
		}
		say q(</li></ul></fieldset><fieldset style="float:left"><legend>Options</legend>);
		say q(<ul><li>);
		say $q->checkbox( -name => 'size_filter', -label => q(Don't insert sequences shorter than ) );
		say $q->popup_menu( -name => 'size', -values => [qw(25 50 100 200 300 400 500 1000)], -default => 250 );
		say q( bps.</li>);
		say q(</ul></fieldset>);
		$self->print_action_fieldset( { submit_label => 'Upload validated contigs', no_reset => 1 } );
		$q->param( upload => 1 );
		say $q->hidden($_) foreach qw(db page field temp_file upload);
		say $q->end_form;
		$self->print_navigation_bar(
			{
				reload_url  => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSeqbin",
				reload_text => 'Restart'
			}
		);
	}
	say q(</div></div>);
	if ($failure) {
		my $plural = $failure == 1 ? q() : q(s);
		my %navbar;
		if ( !$success ) {
			%navbar = (
				navbar      => 1,
				reload_url  => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSeqbin",
				reload_text => 'Restart'
			);
		}
		$self->print_bad_status(
			{
				message => "$failure record$plural failed validation.",
				detail  => 'These cannot be uploaded.',
				%navbar
			}
		);
	}
	return;
}

sub _upload {
	my ( $self, $field, $temp_file ) = @_;
	my $q = $self->{'cgi'};
	if ( !$self->{'xmlHandler'}->is_field($field) ) {
		return { message => 'Selected field is not valid' };
	}
	my ( $validated, $failed );
	try {
		$validated = $self->_parse_validated_temp_file($temp_file);
	}
	catch BIGSdb::CannotOpenFileException with {
		$failed = 1;
	};
	if ($failed) {
		$self->_print_interface;
		$self->print_bad_status( { message => 'Cannot read temporary file. Please repeat upload' } );
		return;
	}
	my $dir = $self->_get_upload_dir;
	my $failure;
	my $seq_ref;
	my $qry = 'INSERT INTO sequence_bin (isolate_id,sequence,method,original_designation,'
	  . 'comments,sender,curator,date_entered,datestamp) VALUES (?,?,?,?,?,?,?,?,?)';
	my $insert_sql = $self->{'db'}->prepare($qry);
	my $curator    = $self->get_curator_id;
	my $sender     = $q->param('sender');

	if ( !$sender ) {
		$self->print_bad_status(
			{
				message     => 'No sender selected.',
				navbar      => 1,
				reload_url  => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSeqbin",
				reload_text => 'Restart'
			}
		);
	}
	my $seq_attributes = $self->{'datastore'}->run_query( 'SELECT key,type FROM sequence_attributes ORDER BY key',
		undef, { fetch => 'all_arrayref', slice => {} } );
	my @attribute_sql;
	if (@$seq_attributes) {
		foreach my $attribute (@$seq_attributes) {
			if ( $q->param( $attribute->{'key'} ) ) {
				( my $value = $q->param( $attribute->{'key'} ) ) =~ s/'/\\'/gx;
				$qry = q(INSERT INTO sequence_attribute_values (seqbin_id,key,value,curator,datestamp) VALUES )
				  . qq((?,'$attribute->{'key'}',E'$value',$curator,'now'));
				push @attribute_sql, $self->{'db'}->prepare($qry);
			}
		}
	}
	my $added = 0;
	foreach my $row (@$validated) {
		my $filename = "$dir/$row->{'filename'}";
		try {
			my $fasta_ref = BIGSdb::Utils::slurp($filename);
			$seq_ref = BIGSdb::Utils::read_fasta( $fasta_ref, { keep_comments => 1 } );
		}
		catch BIGSdb::CannotOpenFileException with {
			$failure = 1;
		}
		catch BIGSdb::DataException with {
			$failure = 1;
		};
		next if $failure;
		my $min_size = 0;
		if ( $q->param('size_filter') && BIGSdb::Utils::is_int( $q->param('size') ) ) {
			$min_size = $q->param('size');
		}
		eval {
			foreach my $seq_id ( keys %$seq_ref ) {
				next if length $seq_ref->{$seq_id} < $min_size;
				my ( $designation, $comments );
				if ( $seq_id =~ /(\S*)\s+(.*)/x ) {
					( $designation, $comments ) = ( $1, $2 );
				} else {
					$designation = $seq_id;
				}
				undef $designation if $designation eq q();
				foreach my $field (qw(method run_id assembly_id)) {
					$q->delete($field) if defined $q->param($field) && $q->param($field) eq q();
				}
				my @values = (
					$row->{'id'}, $seq_ref->{$seq_id}, $q->param('method') // undef,
					$designation, $comments, $sender, $curator, 'now', 'now'
				);
				$insert_sql->execute(@values);
				my $id = $self->{'db'}->last_insert_id( undef, undef, 'sequence_bin', 'id' );
				$_->execute($id) foreach @attribute_sql;
			}
		};
		if ($@) {
			$logger->error($@);
			$failure = 1;
		}
		$added++;
	}
	if ($failure) {
		local $" = ', ';
		$self->print_bad_status(
			{
				message     => 'Failed! - transaction cancelled - no records have been touched.',
				navbar      => 1,
				reload_url  => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSeqbin",
				reload_text => 'Restart'
			}
		);
		$self->{'db'}->rollback;
		return;
	}
	$self->{'db'}->commit;
	my $plural = $added == 1 ? q(y) : q(ies);
	$self->print_good_status(
		{
			message     => qq($added sequence assembl$plural uploaded.),
			navbar      => 1,
			reload_url  => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSeqbin",
			reload_text => 'Restart'
		}
	);
	return;
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
	if ( $q->param('Remove') ) {
		$self->_remove_row($temp_file);
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
	my $allowed_files = $self->_get_list_of_files($validated);
	if ( $q->param('file_upload') ) {
		$self->_upload_files($allowed_files);
	}
	my $icon = $self->get_form_icon( 'sequence_bin', 'plus' );
	my $buffer = qq($icon<div class="box resultstable"><div class="scrollable">);
	$buffer .= q(<p>Please upload the assembly contig files for each isolate record.<p>);
	$buffer .= $q->start_form;
	$buffer .= q(<table class="resultstable">);
	$buffer .= q(<tr><th rowspan="2">remove<br />row</th><th rowspan="2">id</th>);
	$buffer .= qq(<th rowspan="2">$field</th>) if $field ne 'id';
	$buffer .= qq(<th rowspan="2">$self->{'system'}->{'labelfield'}</th>)
	  if $field ne $self->{'system'}->{'labelfield'};
	$buffer .= q(<th colspan="2">current sequence bin state</th><th rowspan="2">filename</th>)
	  . q(<th rowspan="2">upload status</th></tr>);
	$buffer .= q(<tr><th>contigs</th><th>total size (bp)</th></tr>);
	my $td                = 1;
	my $to_upload         = 0;
	my $dir               = $self->_get_upload_dir;
	my $already_populated = 0;
	my @filenames;

	foreach my $row (@$validated) {
		$buffer .= qq(<tr class="td$td"><td>);
		$buffer .= $q->checkbox( -name => "cancel_$row->{'id'}", -label => '' );
		$buffer .= qq(</td><td>$row->{'id'}</td>);
		$buffer .= qq(<td>$row->{'identifier'}</td>) if $field ne 'id';
		if ( $field ne $self->{'system'}->{'labelfield'} ) {
			my $name = $self->get_isolate_name_from_id( $row->{'id'} );
			$buffer .= qq(<td>$name</td>);
		}
		my $stats = $self->{'datastore'}->get_seqbin_stats( $row->{'id'}, { general => 1 } );
		foreach my $att (qw(contigs total_length)) {
			my $value = BIGSdb::Utils::commify( $stats->{$att} ) || q(-);
			$buffer .= qq(<td>$value</td>);
		}
		$already_populated++ if $stats->{'total_length'};
		push @filenames, $row->{'filename'};
		my $filename = "$dir/$row->{'filename'}";
		$buffer .=
		  -e $filename
		  ? qq(<td><a href="/tmp/$self->{'system'}->{'db'}/$self->{'username'}/$row->{'filename'}">$row->{'filename'}</a></td>)
		  : qq(<td>$row->{'filename'}</td>);
		my ( $good, $bad ) = ( GOOD, BAD );
		if ( -e $filename ) {
			$buffer .= qq(<td>$good</td>);
		} else {
			$buffer .= qq(<td>$bad<?td>);
			$to_upload++;
		}
		$buffer .= q(</tr>);
		$td = $td == 1 ? 2 : 1;
	}
	$buffer .= q(<tr><td>);
	$buffer .= $q->submit( -name => 'Remove', -class => 'smallbutton' );
	$buffer .= q(</td><td colspan="6"></td></tr>);
	$buffer .= q(</table>);
	$q->param( temp_file => $temp_file );
	$buffer .= $q->hidden($_) foreach qw(db page field temp_file);
	$buffer .= $q->end_form;

	if ($already_populated) {
		my $plural = $already_populated == 1 ? q() : q(s);
		$self->print_warning(
			{
				message => qq(Sequences already uploaded for $already_populated record$plural),
				detail  => qq(Please note that $already_populated of your records already )
				  . q(has sequences uploaded. If you upload now, these sequences will be added to those already existing. )
				  . q(If you did not intend to add new contigs to an existing sequence bin, please remove the isolate )
				  . q(record from the table.)
			}
		);
	}
	say $buffer;
	if ($to_upload) {
		my $plural = $to_upload == 1 ? q() : q(s);
		say qq(<p class="statusbad">$to_upload FASTA file$plural left to upload.</p>);
		$self->_print_file_upload_fieldset;
	} else {
		say q(<p>All files uploaded. The sequences have not yet been validated. )
		  . q(This needs to be done before they can be added to the database.<p>);
		say $q->start_form;
		$self->print_action_fieldset( { submit_label => 'Validate', no_reset => 1 } );
		$q->param( validate => 1 );
		say $q->hidden($_) foreach qw(db page field temp_file validate);
		say $q->end_form;
	}

	#Drag and drop JS needs to read the temp_file param from page.
	say qq(<span id="temp_file" style="display:none">$temp_file</span>);
	local $" = q(|);
	say qq(<span id="filenames" style="display:none">@filenames</span>);
	say q(<div style="clear:both"></div>);
	$self->print_navigation_bar(
		{
			back     => 1,
			back_url => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSeqbin"
		}
	);
	say q(</div></div>);
	return;
}

sub _get_list_of_files {
	my ( $self, $validated ) = @_;
	my $files = [];
	foreach my $row (@$validated) {
		push @$files, $row->{'filename'};
	}
	return $files;
}

sub _remove_row {
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
	my $dir           = $self->_get_upload_dir;
	foreach my $row (@$validated) {
		if ( $q->param("cancel_$row->{'id'}") ) {
			if ( $row->{'filename'} =~ /([A-z0-9_\-\.'\ \(\#)]+)/x ) {
				unlink "$dir/$1";
			}
			next;
		}
		push @$new_validated, $row;
	}
	$self->_write_validated_temp_file( $new_validated, $temp_file );
	return;
}

sub _print_file_upload_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left"><legend>Contig assembly files</legend>);
	my $nice_file_size = BIGSdb::Utils::get_nice_size( $self->{'config'}->{'max_upload_size'} );
	say q(<p>Please upload contig assemblies with the filenames as you specified (indicated in the table). );
	say qq(Individual filesize is limited to $nice_file_size. You can upload up to $nice_file_size in one go, )
	  . q(although you can upload multiple times so that the total size of the upload can be larger.</p>);
	say $q->start_form( -id => 'file_upload_form' );
	say q(<div class="fallback">);
	print $q->filefield( -name => 'file_upload', -id => 'file_upload', -multiple );
	say $q->submit( -name => 'Upload files', -class => BUTTON_CLASS );
	say q(</div>);
	say q(<div class="dz-message">Drop files here or click to upload.</div>);
	say $q->hidden($_) foreach qw(db page field temp_file);
	say $q->end_form;
	say q(</fieldset>);
	return;
}

sub _upload_files {
	my ( $self, $allowed_files ) = @_;
	my $q         = $self->{'cgi'};
	my @filenames = $q->param('file_upload');
	my $i         = 0;
	my $dir       = $self->_get_upload_dir;
	$self->_mkpath($dir);
	my %allowed = map { $_ => 1 } @$allowed_files;
	foreach my $fh2 ( $q->upload('file_upload') ) {
		my $invalid;
		if ( $filenames[$i] =~ /([A-z0-9_\-\.'\ \(\\#)]+)/x ) {
			$filenames[$i] = $1;
		} else {
			$invalid = 1;
			$logger->error("Invalid filename $filenames[$i]!");
		}
		if ( !$allowed{ $filenames[$i] } ) {
			$self->print_bad_status(
				{
					message => 'Filename not recognized',
					detail  => "You have tried to upload $filenames[$i] but "
					  . 'this is not included in your list to upload.'
				}
			);
			return;
		}
		my $filename = "$dir/$filenames[$i]";
		$i++;
		next if -e $filename;    #Don't reupload if already done.
		my $buffer;
		open( my $fh, '>', $filename ) || $logger->error("Could not open $filename for writing.");
		binmode $fh2;
		binmode $fh;
		read( $fh2, $buffer, $self->{'config'}->{'max_upload_size'} );
		print $fh $buffer;
		close $fh;
	}
	return;
}

sub _mkpath {
	my ( $self, $dir ) = @_;
	my $save_u = umask();
	umask(0);
	##no critic (ProhibitLeadingZeros)
	make_path( $dir, { mode => 0775, error => \my $err } );
	if (@$err) {
		for my $diag (@$err) {
			my ( $path, $message ) = %$diag;
			if ( $path eq '' ) {
				$logger->error("general error: $message");
			} else {
				$logger->error("problem with $path: $message");
			}
		}
	}
	umask($save_u);
	return;
}

sub _remove_dir {
	my ( $self, $dir ) = @_;
	remove_tree( $dir, { error => \my $err } );
	if (@$err) {
		for my $diag (@$err) {
			my ( $file, $message ) = %$diag;
			if ( $file eq '' ) {
				$logger->error("general error: $message");
			} else {
				$logger->error("problem unlinking $file: $message");
			}
		}
	}
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

sub _get_upload_dir {
	my ($self) = @_;
	my $dir = "$self->{'config'}->{'tmp_dir'}/$self->{'system'}->{'db'}/$self->{'username'}";
	if ( $dir =~ /(.*)/x ) {
		$dir = $1;    #Untaint
	}
	return $dir;
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
		-placeholder => "1001\tisolate_1001.fasta\n1002\tisolate_1002.fasta",
		-required    => 'required'
	);
	say q(</fieldset>);
	$self->print_action_fieldset;
	say $q->hidden($_) foreach qw(db page);
	say $q->end_form;
	say q(</div></div>);
	my $dir = $self->_get_upload_dir;
	$self->_remove_dir($dir);
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Batch add new sequences - $desc";
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (tooltips jQuery dropzone noCache);
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $field  = $q->param('field');
	my $max = $self->{'config'}->{'max_upload_size'} / ( 1024 * 1024 );
	my $max_files = LIMIT * 2;    #Allow more in case some wrong files are selected
	my $buffer    = << "END";
\$(function () {
	var filenames = \$("span#filenames").text().split("|");
	\$("form#file_upload_form").dropzone({ 
		paramName: function() { return 'file_upload'; },
		parallelUploads: 6,
		maxFiles: $max_files,
		uploadMultiple: true,
		maxFilesize: $max,
		accept: function(file, done) {
   		if (jQuery.inArray(file.name,filenames) !== -1){
    			done();
    		} else {
    			done("Filename not in list.");
    		}
  		},
		init: function () {
        	this.on('queuecomplete', function () {
         		if (this.getUploadingFiles().length === 0 && this.getQueuedFiles().length === 0) {
	         		var url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;"
	         		+"page=batchAddSeqbin&amp;field=$field&amp;temp_file=" 
	         		+ \$("span#temp_file").text();
	             	location.href = url;
         		}
        	});
    	}
	});
	\$("form#file_upload_form").addClass("dropzone");
});

END
	return $buffer;
}
1;
