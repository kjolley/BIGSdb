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
package BIGSdb::CurateProfileBatchAddPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateProfileAddPage);
use Log::Log4perl qw(get_logger);
use List::MoreUtils qw(none);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	my $set_id    = $self->get_set_id;
	if ( !$self->{'datastore'}->scheme_exists($scheme_id) ) {
		say q(<h1>Batch insert profiles</h1>);
		say q(<div class="box" id="statusbad"><p>Invalid scheme passed.</p></div>);
		return;
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say q(<h1>Batch insert profiles</h1>);
		say q(<div class="box" id="statusbad"><p>You can only add profiles to a sequence/profile database - )
		  . q(this is an isolate database.</p></div>);
		return;
	}
	if ( !$self->can_modify_table('profiles') ) {
		say q(<h1>Batch insert profiles</h1>);
		say q(<div class="box" id="statusbad"><p>Your user account is not allowed to add new profiles.</p></div>);
		return;
	}
	if ($set_id) {
		if ( !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id ) ) {
			say q(<h1>Batch insert profiles</h1>);
			say q(<div class="box" id="statusbad"><p>The selected scheme is inaccessible.</p></div>);
			return;
		}
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	print "<h1>Batch insert $scheme_info->{'description'} profiles</h1>\n";
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $primary_key   = $scheme_info->{'primary_key'};
	if ( !$primary_key ) {
		say q(<div class="box" id="statusbad"><p>This scheme doesn't have a primary key field defined.  )
		  . q(Profiles cannot be entered until this has been done.</p></div>);
		return;
	} elsif ( !@$loci ) {
		say q(<div class="box" id="statusbad"><p>This scheme doesn't have any loci belonging to it.  )
		  . q(Profiles cannot be entered until there is at least one locus defined.</p></div>);
		return;
	}
	if ( $q->param('checked_buffer') ) {
		$self->_upload($scheme_id);
	} elsif ( $q->param('data') && $q->param('submit') ) {
		$self->_check($scheme_id);
	} else {
		if ( $q->param('submission_id') ) {
			$self->_set_submission_params( $q->param('submission_id') );
		}
		$self->_print_interface($scheme_id);
	}
	return;
}

sub get_title {
	my $self        = shift;
	my $desc        = $self->{'system'}->{'description'} || 'BIGSdb';
	my $table       = $self->{'cgi'}->param('table');
	my $scheme_id   = $self->{'cgi'}->param('scheme_id');
	my $scheme_desc = '';
	if ( $scheme_id && BIGSdb::Utils::is_int($scheme_id) ) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
		$scheme_desc = $scheme_info->{'description'} || '';
	}
	my $type = $self->get_record_name($table);
	return "Batch add new $scheme_desc profiles - $desc";
}

sub _is_pk_used {
	my ( $self, $scheme_id, $profile_id ) = @_;
	return $self->{'datastore'}->run_query(
		'SELECT EXISTS(SELECT * FROM profiles WHERE (scheme_id,profile_id)=(?,?))',
		[ $scheme_id, $profile_id ],
		{ cache => 'CurateProfileBatchAddPage::is_pk_used' }
	);
}

#remove trailing spaces
sub _process_fields {
	my ( $self, $data ) = @_;
	foreach my $value (@$data) {
		$value =~ s/^\s+//x;
		$value =~ s/\s+$//x;
	}
	return;
}

sub _check {
	my ( $self, $scheme_id ) = @_;
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_info   = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key   = $scheme_info->{'primary_key'};
	my @mapped_loci;
	foreach my $locus (@$loci) {
		my $mapped = $self->clean_locus( $locus, { text_output => 1, no_common_name => 1 } );
		push @mapped_loci, $mapped;
	}
	my $q = $self->{'cgi'};
	my @checked_buffer;
	my @fieldorder = ( $primary_key, @$loci );
	my %is_field;
	my %is_locus;
	my $scheme_field_info;
	my %pks_so_far;
	my %profiles_so_far;
	local $" = '</th><th>';
	my $table_buffer = qq(<table class="resultstable"><tr><th>$primary_key</th><th>@mapped_loci</th>);

	foreach my $field (@$scheme_fields) {
		$is_field{$field} = 1;
		$scheme_field_info->{$field} = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		if ( $field ne $primary_key ) {
			push @fieldorder, $field;
			$table_buffer .= "<th>$field</th>";
		}
	}
	foreach my $field (qw (sender curator date_entered datestamp)) {
		$table_buffer .= "<th>$field</th>";
		push @fieldorder, $field;
	}
	$table_buffer .= "</tr>\n";
	my $sender_message;
	my $sender = $q->param('sender');
	my %problems;
	if ( !$sender ) {
		say q(<div class="box" id="statusbad"><p>Please enter a sender for this submission.</p></div>);
		$self->_print_interface($scheme_id);
		return;
	} elsif ( $sender == -1 ) {
		$sender_message = qq(<p>Using sender field in pasted data.</p>\n);
	} else {
		my $sender_ref = $self->{'datastore'}->get_user_info($sender);
		if ( !$sender_ref ) {
			say q(<div class="box" id="statusbad"><p>Sender is unrecognized.</p></div>);
			$self->_print_interface($scheme_id);
			return;
		}
		$sender_message = qq(<p>Sender: $sender_ref->{'first_name'} $sender_ref->{'surname'}</p>\n);
	}
	my @records   = split /\n/x, $q->param('data');
	my $td        = 1;
	my $headerRow = shift @records;
	$headerRow =~ s/\r//gx;
	my @fileheaderFields = split /\t/x, $headerRow;
	my %fileheaderPos;
	my $i = 0;
	my $pk_included;

	foreach my $field (@fileheaderFields) {
		my $mapped = $self->map_locus_name($field);
		$fileheaderPos{$mapped} = $i;
		$i++;
		$pk_included = 1 if $field eq $primary_key;
	}
	my $pk;
	my $integer_pk = $self->_is_integer_primary_key($scheme_id);
	$pk = $self->next_id( 'profiles', $scheme_id ) if $integer_pk;
	my %locus_format;
	foreach my $locus (@$loci) {
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		$locus_format{$locus} = $locus_info->{'allele_id_format'};
		$is_locus{$locus}     = 1;
	}
	my $first_record = 1;
	my $header_row;
	my $record_count;
  RECORD: foreach my $row (@records) {
		my $row_buffer;
		$row =~ s/\r//gx;
		next if $row =~ /^\s*$/x;
		my @profile;
		my %newdata;
		my $checked_record;
		my @data = split /\t/x, $row;
		$self->_process_fields( \@data );

		if ( $integer_pk && !$first_record && !$pk_included ) {
			do {
				$pk++;
			} while ( $self->_is_pk_used( $scheme_id, $pk ) );
		} elsif ($pk_included) {
			$pk = $data[ $fileheaderPos{$primary_key} ];
		}
		$record_count++;
		$row_buffer .= qq(<tr class="td$td">);
		$i = 0;
		foreach my $field (@fieldorder) {
			my $value;
			if ( $field eq $primary_key ) {
				$header_row .= "$primary_key\t"
				  if $first_record && !$pk_included;
				$value = $pk;
			}
			my $problem;
			if ( $field eq 'datestamp' || $field eq 'date_entered' ) {
				$value = $self->get_datestamp;
			} elsif ( $field eq 'sender' ) {
				if ( defined $fileheaderPos{$field} ) {
					$value = $data[ $fileheaderPos{$field} ];
					$header_row .= "$field\t" if $first_record;
					if ( !BIGSdb::Utils::is_int($value) ) {
						$problems{$pk} .= 'Sender must be an integer.<br />';
						$problem = 1;
					} else {
						my $sender_exists =
						  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM users WHERE id=? AND id>0)',
							$value, { cache => 'CurateProfileBatchAddPage::check:sender_exists' } );
						if ( !$sender_exists ) {
							$problems{$pk} .= "Sender '$value' does not exist.<br />";
							$problem = 1;
						}
					}
				} elsif ( BIGSdb::Utils::is_int( $q->param('sender') ) && $q->param('sender') != -1 ) {
					$value = $q->param('sender');
				} else {
					$problems{$pk} .= 'Sender not set.<br />';
					$problem = 1;
				}
			} elsif ( $field eq 'curator' ) {
				$value = $self->get_curator_id;
			} else {
				if ( defined $fileheaderPos{$field} ) {
					$header_row .= "$field\t" if $first_record;
					$value = $data[ $fileheaderPos{$field} ];
				}
			}
			$value = defined $value ? $value : '';
			if ( $is_locus{$field} ) {
				push @profile, $value;
				$newdata{"locus:$field"} = $value;
				my $field_bad = $self->is_locus_field_bad( $scheme_id, $field, $value );
				if ($field_bad) {
					$problems{$pk} .= "$field_bad<br />";
					$problem = 1;
				}
			} elsif ( $is_field{$field} && defined $value ) {
				if ( $scheme_field_info->{$field}->{'primary_key'} && $value eq '' ) {
					$problems{ $pk // '' } .= "Field $field is required and must not be left blank.<br />";
					$problem = 1;
				} elsif ( $scheme_field_info->{$field}->{'type'} eq 'integer'
					&& $value ne ''
					&& !BIGSdb::Utils::is_int($value) )
				{
					$problems{$pk} .= "Field $field must be an integer.<br />";
					$problem = 1;
				}
			}
			my $display_value = $value;
			if ( !$problem ) {
				$row_buffer .= "<td>$display_value</td>";
			} else {
				$row_buffer .= "<td><font color=\"red\">$display_value</font></td>";
			}
			$checked_record .= "$value\t"
			  if defined $fileheaderPos{$field}
			  or ( $field eq $primary_key );
		}
		push @checked_buffer, $header_row if $first_record;
		$first_record = 0;

		#check if profile exists
		my ( $profile_exists, $msg ) = $self->profile_exists( $scheme_id, $primary_key, \%newdata );
		if ($profile_exists) {
			next RECORD if $q->param('ignore_existing');
			$problems{$pk} .= "$msg<br />";
		}

		#check if primary key already exists
		my $pk_exists = $self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM profiles WHERE (scheme_id,profile_id)=(?,?))',
			[ $scheme_id, $pk ],
			{ cache => 'CurateProfileBatchAddPage::check::pk_check' }
		);
		if ($pk_exists) {
			$problems{$pk} .= "The primary key '$primary_key-$pk' already exists in the database.<br />";
		}
		if ( $pks_so_far{ $pk // q() } ) {
			$problems{$pk} .= 'This primary key has been included more than once in this submission.<br />';
		}
		{
			no warnings 'uninitialized';
			local $" = ',';
			if ( $profiles_so_far{"@profile"} && none { $_ eq '' } @profile ) {
				next RECORD if $q->param('ignore_duplicates');
				$problems{$pk} .= "The profile '@profile' has been included more than once in this submission.<br />";
			} elsif ( $scheme_info->{'allow_missing_loci'} ) {

				#Need to check if profile matches another in this submission using arbitrary matches against allele 'N'.
				foreach my $profile_string ( keys %profiles_so_far ) {
					my $it_matches = 1;
					my @existing_profile = split /,/x, $profile_string;
					foreach my $i ( 0 .. @profile - 1 ) {
						if (   $profile[$i] ne $existing_profile[$i]
							&& $profile[$i] ne 'N'
							&& $existing_profile[$i] ne 'N' )
						{
							$it_matches = 0;
							last;
						}
					}
					if ($it_matches) {
						$problems{$pk} .=
						    qq(The profile '@profile' matches another profile in this submission when considering that )
						  . q(arbitrary allele 'N' can match any other allele.);
						last;
					}
				}
			}
			$profiles_so_far{"@profile"} = 1;
		}
		$pks_so_far{ $pk // '' } = 1;
		$row_buffer   .= "</tr>\n";
		$table_buffer .= $row_buffer;
		$td = $td == 1 ? 2 : 1;    #row stripes
		$checked_record =~ s/\t$//x;
		push @checked_buffer, $checked_record;
	}
	$table_buffer .= "</table>\n";
	if ( !$record_count ) {
		say q(<div class="box" id="statusbad"><p>No valid data entered. Make sure )
		  . q(you've included the header line.</p></div>);
		return;
	}
	if (%problems) {
		say q(<div class="box" id="statusbad"><h2>Import status</h2>);
		say q(<div class="scrollable">);
		say q(<table class="resultstable">);
		say qq(<tr><th>$primary_key</th><th>Problem(s)</th></tr>);
		$td = 1;
		{
			no warnings 'numeric';
			foreach my $id ( sort { $a <=> $b || $a cmp $b } keys %problems ) {
				say qq(<tr class="td$td"><td>$id</td><td style="text-align:left">$problems{$id}</td></tr>);
				$td = $td == 1 ? 2 : 1;
			}
		}
		say q(</table></div></div>);
	} else {
		say qq(<div class="box" id="resultsheader"><h2>Import status</h2>$sender_message<p>No obvious )
		  . q(problems identified so far.</p>);
		my $filename = $self->make_temp_file(@checked_buffer);
		say $q->start_form;
		say $q->hidden($_) foreach qw (page table db sender scheme_id submission_id);
		say $q->hidden( checked_buffer => $filename );
		$self->print_action_fieldset( { submit_label => 'Import data', no_reset => 1 } );
		say $q->endform;
		say q(</div>);
	}
	say q(<div class="box" id="resultstable"><h2>Data to be imported</h2>);
	say q(<p>The following table shows your data.  Any field coloured red has a problem and needs to be checked.</p>);
	say q(<div class="scrollable">);
	say $table_buffer;
	say q(</div></div>);
	return;
}

sub _upload {
	my ( $self, $scheme_id ) = @_;
	my $q             = $self->{'cgi'};
	my $scheme_info   = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $tmp_file      = "$self->{'config'}->{'secure_tmp_dir'}/" . $q->param('checked_buffer');
	if ( !-e $tmp_file ) {
		say q(<div class="box" id="statusbad"><p>The temp file containing the checked profiles does not exist.</p>)
		  . q(<p>Upload cannot proceed.  Make sure that you haven't used the back button and are attempting to )
		  . q(re-upload already submitted data.  Please report this if the problem persists.<p></div>);
		$logger->error("Checked buffer file $tmp_file does not exist.");
		return;
	}
	my @records;
	if ( open( my $tmp_fh, '<:encoding(utf8)', $tmp_file ) ) {
		@records = <$tmp_fh>;
		close $tmp_fh;
	} else {
		$logger->error("Can't open $tmp_file for reading.");
	}
	if ( $tmp_file =~ /^(.*\/BIGSdb_[0-9_]+\.txt)$/x ) {
		$logger->info("Deleting temp file $tmp_file");
		unlink $1;
	} else {
		$logger->error("Can't delete temp file $tmp_file");
	}
	my $headerline = shift @records || '';
	$headerline =~ s/[\r\n]//gx;
	my @fieldorder = split /\t/x, $headerline;
	my %fieldorder;
	for my $i ( 0 .. @fieldorder - 1 ) {
		$fieldorder{ $fieldorder[$i] } = $i;
	}
	my $primary_key = $scheme_info->{'primary_key'};
	my @profile_ids;
	foreach my $row (@records) {
		$row =~ s/\r//gx;
		next if !$row;
		my @data = split /\t/x, $row;
		$self->_process_fields( \@data );
		my $profile_id = $data[ $fieldorder{$primary_key} ];
		my $sender;
		if ( $fieldorder{'sender'} && $data[ $fieldorder{'sender'} ] ) {
			$sender = $data[ $fieldorder{'sender'} ];
		} elsif ( $q->param('sender') ) {
			$sender = $q->param('sender');
		}
		my $curator = $self->get_curator_id;
		my @inserts;
		push @inserts,
		  {
			statement => 'INSERT INTO profiles (scheme_id,profile_id,sender,curator,'
			  . 'date_entered,datestamp) VALUES (?,?,?,?,?,?)',
			arguments => [ $scheme_id, $profile_id, $sender, $curator, 'now', 'now' ]
		  };
		push @profile_ids, $profile_id;
		foreach my $locus (@$loci) {
			my $mapped_locus = $self->map_locus_name($locus);
			push @inserts,
			  {
				statement => 'INSERT INTO profile_members (scheme_id,locus,profile_id,allele_id,curator,'
				  . 'datestamp) VALUES (?,?,?,?,?,?)',
				arguments => [ $scheme_id, $mapped_locus, $profile_id, $data[ $fieldorder{$locus} ], $curator, 'now' ]
			  };
		}
		foreach my $field (@$scheme_fields) {
			next
			  if !defined $fieldorder{$field}
			  || !defined $data[ $fieldorder{$field} ]
			  || $data[ $fieldorder{$field} ] eq q();
			push @inserts,
			  {
				statement => 'INSERT INTO profile_fields (scheme_id,scheme_field,profile_id,value,curator,'
				  . 'datestamp) VALUES (?,?,?,?,?,?)',
				arguments => [ $scheme_id, $field, $profile_id, $data[ $fieldorder{$field} ], $curator, 'now' ]
			  };
		}
		eval {
			foreach my $insert (@inserts)
			{
				$self->{'db'}->do( $insert->{'statement'}, undef, @{ $insert->{'arguments'} } );
			}
		};
		if ($@) {
			say q(<div class="box" id="statusbad"><p>Database update failed - transaction cancelled - )
			  . q(no records have been touched.</p>);
			if ( $@ =~ /duplicate/ && $@ =~ /unique/ ) {
				say q(<p>Data entry would have resulted in records with either duplicate ids or another )
				  . q(unique field with duplicate values.</p>);
			} else {
				say qq(<p>Error message: $@</p>);
			}
			say q(</div>);
			$self->{'db'}->rollback;
			$logger->error("Can't insert: $@");
			return;
		}
	}
	$self->refresh_material_view($scheme_id);
	$self->{'db'}->commit
	  && say q(<div class="box" id="resultsheader"><p>Database updated ok</p><p>);
	if ( $q->param('submission_id') ) {
		my $submission = $self->{'submissionHandler'}->get_submission( $q->param('submission_id') );
		if ($submission) {
			say qq(<a href="$self->{'system'}->{'query_script'}?db=$self->{'instance'}&amp;)
			  . qq(page=submit&amp;submission_id=$submission->{'id'}&amp;curate=1">Return to )
			  . q(submission</a> | );
		}
	}
	say qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>);
	foreach my $profile_id (@profile_ids) {
		$self->update_profile_history( $scheme_id, $profile_id, 'Profile added' );
	}
	return;
}

sub _print_interface {
	my ( $self, $scheme_id ) = @_;
	my $q           = $self->{'cgi'};
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	say q(<div class="box" id="queryform">)
	  . q(<p>This page allows you to upload profiles as tab-delimited text or copied from a spreadsheet.</p>)
	  . q(<ul><li>Field header names must be included and fields can be in any order. Optional fields can be omitted )
	  . q(if you wish.</li>);
	if ( $self->_is_integer_primary_key($scheme_id) ) {
		my $article = $primary_key =~ /^[AaEeIiOoUu]/x ? 'an' : 'a';
		say qq(<li>You can choose whether or not to include $article $primary_key field - if it is omitted, the next )
		  . qq(available $primary_key will be used automatically.  If however, you include it in the header line, then )
		  . q(you must also provide it for each profile record.</li>);
	}
	say qq(</ul><ul><li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableHeader&amp;)
	  . qq(table=profiles&amp;scheme_id=$scheme_id">Download tab-delimited header for your spreadsheet</a> - use )
	  . q(Paste Special <span class="fa fa-arrow-circle-right"></span> Text to paste the data.</li><li>)
	  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=excelTemplate&amp;)
	  . qq(table=profiles&amp;scheme_id=$scheme_id">Download submission template (xlsx format)</a></li></ul>);
	say $q->start_form;
	my ( $users, $user_names ) = $self->get_user_list_and_labels( { blank_message => 'Select sender ...' } );
	$user_names->{-1} = 'Override with sender field';
	say q[<fieldset style="float:left"><legend>Please paste in tab-delimited text ]
	  . q[(<strong>include a field header line</strong>)</legend>];
	say $q->hidden($_) foreach qw (page db scheme_id submission_id);
	say $q->textarea( -name => 'data', -rows => 20, -columns => 80, -required => 'required' );
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Parameters</legend>);
	say q(<label for="sender" class="form" style="width:5em">Sender:</label>);
	say $q->popup_menu(
		-name     => 'sender',
		-id       => 'sender',
		-values   => [ '', -1, @$users ],
		-labels   => $user_names,
		-required => 'required'
	);
	say q(<p class="comment">Value will be overridden if you include a sender field in your pasted data.</p>);
	say q(<ul><li>);
	say $q->checkbox( -name => 'ignore_existing', -label => 'Ignore previously defined profiles' );
	say q(</li><li>);
	say $q->checkbox( -name => 'ignore_duplicates', -label => 'Ignore duplicate profiles' );
	say q(</li></ul>);
	say q(</fieldset>);
	$self->print_action_fieldset( { scheme_id => $scheme_id } );
	say $q->end_form;
	say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back</a></p>);
	say q(</div>);
	return;
}

sub _is_integer_primary_key {
	my ( $self, $scheme_id ) = @_;
	my $integer_pk =
	  $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM scheme_fields WHERE (scheme_id,type)=(?,?) AND primary_key)',
		[ $scheme_id, 'integer' ] );
	return $integer_pk;
}

sub _set_submission_params {
	my ( $self, $submission_id ) = @_;
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	return if !$submission;
	my $profile_submission = $self->{'submissionHandler'}->get_profile_submission($submission_id);
	return if !$profile_submission;
	my $q    = $self->{'cgi'};
	my $loci = $self->{'datastore'}->get_scheme_loci( $profile_submission->{'scheme_id'} );
	$q->param( sender => $submission->{'submitter'} );
	local $" = qq(\t);
	my $buffer   = "@$loci\n";
	my $profiles = $profile_submission->{'profiles'};
	my @pending  = $q->param('profile_indexes') ? split /,/x, $q->param('profile_indexes') : ();
	my %pending  = map { $_ => 1 } @pending;

	foreach my $profile (@$profiles) {
		next if !$pending{ $profile->{'index'} };
		my @temp_profile;
		push @temp_profile, $profile->{'designations'}->{$_} foreach @$loci;
		$buffer .= "@temp_profile\n";
	}
	$q->param( data => $buffer );
	return;
}
1;
