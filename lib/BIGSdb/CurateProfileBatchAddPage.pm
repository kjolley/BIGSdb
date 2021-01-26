#Written by Keith Jolley
#Copyright (c) 2010-2021, University of Oxford
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
use BIGSdb::Utils;
use BIGSdb::Constants qw(:interface);
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
	if ( !$self->can_modify_table('profiles') ) {
		say q(<h1>Batch insert profiles</h1>);
		$self->print_bad_status( { message => q(Your user account is not allowed to add new profiles.) } );
		return;
	}
	if ($set_id) {
		if ( !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id ) ) {
			say q(<h1>Batch insert profiles</h1>);
			$self->print_bad_status( { message => q(The selected scheme is inaccessible.) } );
			return;
		}
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	say qq(<h1>Batch insert $scheme_info->{'name'} profiles</h1>);
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $primary_key   = $scheme_info->{'primary_key'};
	if ( !$primary_key ) {
		$self->print_bad_status(
			{
				message => q(This scheme doesn't have a primary key field defined.  )
				  . q(Profiles cannot be entered until this has been done.)
			}
		);
		return;
	} elsif ( !@$loci ) {
		$self->print_bad_status(
			{
				message => q(This scheme doesn't have any loci belonging to it.  )
				  . q(Profiles cannot be entered until there is at least one locus defined.)
			}
		);
		return;
	}
	if ( $q->param('checked_buffer') ) {
		$self->_upload($scheme_id);
	} elsif ( $q->param('data') && $q->param('submit') ) {
		$self->_check($scheme_id);
	} else {
		if ( $q->param('submission_id') ) {
			$self->_set_submission_params( scalar $q->param('submission_id') );
		}
		my $icon = $self->get_form_icon( 'profiles', 'plus' );
		say $icon;
		$self->_print_interface($scheme_id);
	}
	return;
}

sub get_title {
	my $self        = shift;
	my $table       = $self->{'cgi'}->param('table');
	my $scheme_id   = $self->{'cgi'}->param('scheme_id');
	my $scheme_desc = '';
	if ( $scheme_id && BIGSdb::Utils::is_int($scheme_id) ) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
		$scheme_desc = $scheme_info->{'name'} || '';
	}
	my $type = $self->get_record_name($table);
	return "Batch add new $scheme_desc profiles";
}

sub _is_pk_used {
	my ( $self, $scheme_id, $profile_id ) = @_;
	return $self->{'datastore'}->run_query(
		'SELECT EXISTS(SELECT * FROM profiles WHERE (scheme_id,profile_id)=(?,?)) OR '
		  . 'EXISTS(SELECT * FROM retired_profiles WHERE (scheme_id,profile_id)=(?,?))',
		[ $scheme_id, $profile_id, $scheme_id, $profile_id ],
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

sub _get_field_data {
	my ( $self, $scheme_id, $options ) = @_;
	my $scheme_info   = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key   = $scheme_info->{'primary_key'};
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my @mapped_loci;
	my $is_field          = {};
	my $is_locus          = {};
	my $scheme_field_info = {};
	foreach my $locus (@$loci) {
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		my $mapped = $self->clean_locus( $locus, { text_output => 1, no_common_name => 1 } );
		push @mapped_loci, $mapped;
		$is_locus->{$locus} = 1;
	}
	my $field_order   = [ $primary_key, @$loci ];
	my $cleaned_order = [ $primary_key, @mapped_loci ];
	foreach my $field (@$scheme_fields) {
		$is_field->{$field} = 1;
		$scheme_field_info->{$field} = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		next if $field eq $primary_key;
		push @$field_order,   $field;
		push @$cleaned_order, $field;
	}
	foreach my $field (qw (sender curator date_entered datestamp)) {
		push @$field_order,   $field;
		push @$cleaned_order, $field;
	}
	return {
		field_order       => $field_order,
		cleaned_order     => $cleaned_order,
		is_locus          => $is_locus,
		is_field          => $is_field,
		scheme_field_info => $scheme_field_info
	};
}

sub _get_sender {
	my ( $self, $scheme_id ) = @_;
	my $q = $self->{'cgi'};
	my $sender_message;
	my $sender = $q->param('sender');
	if ( !$sender ) {
		$self->print_bad_status( { message => q(Please enter a sender for this submission.) } );
		$self->_print_interface($scheme_id);
		return 1;
	} elsif ( $sender == -1 ) {
		$sender_message = qq(<p>Using sender field in pasted data.</p>\n);
	} else {
		my $sender_ref = $self->{'datastore'}->get_user_info($sender);
		if ( !$sender_ref ) {
			$self->print_bad_status( { message => q(Sender is unrecognized.) } );
			$self->_print_interface($scheme_id);
			return 1;
		}
		$sender_message = qq(<p>Sender: $sender_ref->{'first_name'} $sender_ref->{'surname'}</p>\n);
	}
	return ( 0, $sender, $sender_message );
}

sub _check {
	my ( $self, $scheme_id ) = @_;
	my $loci        = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	my $q           = $self->{'cgi'};
	my @checked_buffer;
	my $field_data = $self->_get_field_data($scheme_id);
	my ( $field_order, $cleaned_order, $is_locus, $is_field, $scheme_field_info ) =
	  @{$field_data}{qw(field_order cleaned_order is_locus is_field scheme_field_info)};
	local $" = q(</th><th>);
	my $table_buffer = qq(<table class="resultstable"><tr><th>@$cleaned_order</th></tr>);
	my ( $error, $sender, $sender_message ) = $self->_get_sender($scheme_id);
	return if $error;
	my $problems             = {};
	my @records              = split /\n/x, $q->param('data');
	my $td                   = 1;
	my $submitted_header_row = shift @records;
	my ( $file_header_pos, $pk_included ) = $self->_get_file_header_positions( $submitted_header_row, $primary_key );
	my $integer_pk = $self->_is_integer_primary_key($scheme_id);
	my $pk;
	$pk = $self->next_id( 'profiles', $scheme_id ) if $integer_pk;
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
			$pk = $data[ $file_header_pos->{$primary_key} ];
		}
		$record_count++;
		$row_buffer .= qq(<tr class="td$td">);
		foreach my $field (@$field_order) {
			my $value;
			my $problem;
			if ( $field eq $primary_key ) {
				$header_row .= "$primary_key\t"
				  if $first_record && !$pk_included;
				$value = $pk;
				if ( $self->{'datastore'}->is_profile_retired( $scheme_id, $pk ) ) {
					$problems->{$pk} .= "$primary_key-$value has been retired.<br />";
					$problem = 1;
				}
			}
			if ( $field eq 'datestamp' || $field eq 'date_entered' ) {
				$value = BIGSdb::Utils::get_datestamp();
			} elsif ( $field eq 'sender' ) {
				if ( defined $file_header_pos->{$field} ) {
					$value = $data[ $file_header_pos->{$field} ];
					$header_row .= "$field\t" if $first_record;
					my $invalid_sender = $self->_is_sender_invalid($value);
					if ($invalid_sender) {
						$problems->{$pk} .= $invalid_sender;
						$problem = 1;
					}
				} elsif ( BIGSdb::Utils::is_int( scalar $q->param('sender') ) && $q->param('sender') != -1 ) {
					$value = $q->param('sender');
				} else {
					$problems->{$pk} .= 'Sender not set.<br />';
					$problem = 1;
				}
			} elsif ( $field eq 'curator' ) {
				$value = $self->get_curator_id;
			} else {
				if ( defined $file_header_pos->{$field} ) {
					$header_row .= "$field\t" if $first_record;
					$value = $data[ $file_header_pos->{$field} ];
				}
			}
			$value = defined $value ? $value : '';
			if ( $is_locus->{$field} ) {
				push @profile, $value;
				$newdata{"locus:$field"} = $value;
				my $field_bad = $self->is_locus_field_bad( $scheme_id, $field, $value );
				if ($field_bad) {
					$problems->{$pk} .= "$field_bad<br />";
					$problem = 1;
				}
			} elsif ( $is_field->{$field} && defined $value ) {
				if ( $scheme_field_info->{$field}->{'primary_key'} && $value eq '' ) {
					$problems->{ $pk // '' } .= "Field $field is required and must not be left blank.<br />";
					$problem = 1;
				} elsif ( $scheme_field_info->{$field}->{'type'} eq 'integer'
					&& $value ne ''
					&& !BIGSdb::Utils::is_int($value) )
				{
					$problems->{$pk} .= "Field $field must be an integer.<br />";
					$problem = 1;
				}
			}
			my $display_value = $value;
			if ( !$problem ) {
				$row_buffer .= qq(<td>$display_value</td>);
			} else {
				$row_buffer .= qq(<td><font color="red">$display_value</font></td>);
			}
			$checked_record .= qq($value\t)
			  if defined $file_header_pos->{$field}
			  or ( $field eq $primary_key );
		}
		push @checked_buffer, $header_row if $first_record;
		$first_record = 0;
		my $args = {
			scheme_id   => $scheme_id,
			scheme_info => $scheme_info,
			primary_key => $primary_key,
			loci        => $loci,
			newdata     => \%newdata,
			pk          => $pk,
			problems    => $problems,
			profile     => \@profile
		};
		next RECORD if $self->_check_profile_exists($args);
		$self->_check_pk_exists($args);
		$self->_check_pk_used_already($args);
		next RECORD if $self->_check_duplicate_profile($args);
		$row_buffer   .= qq(</tr>\n);
		$table_buffer .= $row_buffer;
		$td = $td == 1 ? 2 : 1;    #row stripes
		$checked_record =~ s/\t$//x;
		push @checked_buffer, $checked_record;
	}
	$table_buffer .= qq(</table>\n);
	if ( !$record_count ) {
		$self->print_bad_status(
			{
				message  => q(No valid data entered. Make sure you have included the header line.),
				navbar   => 1,
				back_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=profileBatchAdd&amp;scheme_id=$scheme_id)
			}
		);
		return;
	}
	if (%$problems) {
		$self->_print_bad_import_status( $problems, $primary_key );
	} else {
		say qq(<div class="box" id="resultsheader"><h2>Import status</h2>$sender_message<p>No obvious )
		  . q(problems identified so far.</p>);
		my $filename = $self->make_temp_file(@checked_buffer);
		say $q->start_form;
		say $q->hidden($_) foreach qw (page table db sender scheme_id submission_id);
		say $q->hidden( checked_buffer => $filename );
		$self->print_action_fieldset( { submit_label => 'Import data', no_reset => 1 } );
		say $q->end_form;
		say q(</div>);
	}
	say q(<div class="box" id="resultstable"><h2>Data to be imported</h2>);
	say q(<p>The following table shows your data.  Any field coloured red has a problem and needs to be checked.</p>);
	say q(<div class="scrollable">);
	say $table_buffer;
	say q(</div></div>);
	return;
}

sub _get_file_header_positions {
	my ( $self, $headerRow, $primary_key ) = @_;
	$headerRow =~ s/\r//gx;
	my @fileheaderFields = split /\t/x, $headerRow;
	my $pos              = {};
	my $i                = 0;
	my $pk_included;
	my $set_id = $self->get_set_id;
	foreach my $field (@fileheaderFields) {
		my $mapped = $self->{'submissionHandler'}->map_locus_name( $field, $set_id );
		$pos->{$mapped} = $i;
		$i++;
		$pk_included = 1 if $field eq $primary_key;
	}
	return ( $pos, $pk_included );
}

sub _check_profile_exists {
	my ( $self, $args ) = @_;
	my ( $scheme_id, $primary_key, $loci, $newdata, $pk, $problems ) =
	  @{$args}{qw(scheme_id primary_key loci newdata pk problems)};
	my $q = $self->{'cgi'};
	my %designations = map { $_ => $newdata->{"locus:$_"} } @$loci;
	my $ret =
	  $self->{'datastore'}->check_new_profile( $scheme_id, \%designations, $newdata->{"field:$primary_key"} );
	if ( $ret->{'exists'} ) {
		return 1 if $q->param('ignore_existing');
		$problems->{$pk} .= "$ret->{'msg'}<br />";
	} elsif ( $ret->{'err'} ) {
		$problems->{$pk} .= "$ret->{'msg'}<br />";
	}
	return;
}

sub _check_pk_exists {
	my ( $self, $args ) = @_;
	my ( $scheme_id, $primary_key, $pk, $problems ) = @{$args}{qw(scheme_id primary_key pk problems)};
	my $pk_exists = $self->{'datastore'}->run_query(
		'SELECT EXISTS(SELECT * FROM profiles WHERE (scheme_id,profile_id)=(?,?))',
		[ $scheme_id, $pk ],
		{ cache => 'CurateProfileBatchAddPage::check::pk_check' }
	);
	if ($pk_exists) {
		$problems->{$pk} .= "The primary key '$primary_key-$pk' already exists in the database.<br />";
	}
	return;
}

sub _check_pk_used_already {
	my ( $self, $args )     = @_;
	my ( $pk,   $problems ) = @{$args}{qw( pk problems)};
	if ( $self->{'pks_so_far'}->{ $pk // q() } ) {
		$problems->{$pk} .= 'This primary key has been included more than once in this submission.<br />';
	}
	$self->{'pks_so_far'}->{ $pk // q() } = 1;
	return;
}

sub _print_bad_import_status {
	my ( $self, $problems, $primary_key ) = @_;
	say q(<div class="box" id="statusbad"><h2>Import status</h2>);
	say q(<div class="scrollable">);
	say q(<table class="resultstable">);
	say qq(<tr><th>$primary_key</th><th>Problem(s)</th></tr>);
	my $td = 1;
	{
		no warnings 'numeric';
		foreach my $id ( sort { $a <=> $b || $a cmp $b } keys %$problems ) {
			say qq(<tr class="td$td"><td>$id</td><td style="text-align:left">$problems->{$id}</td></tr>);
			$td = $td == 1 ? 2 : 1;
		}
	}
	say q(</table></div></div>);
	return;
}

sub _is_sender_invalid {
	my ( $self, $sender ) = @_;
	if ( !BIGSdb::Utils::is_int($sender) ) {
		return q(Sender must be an integer.<br />);
	} else {
		my $sender_exists = $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM users WHERE id=? AND id>0)',
			$sender, { cache => 'CurateProfileBatchAddPage::check:sender_exists' } );
		if ( !$sender_exists ) {
			return qq("Sender '$sender' does not exist.<br />);
		}
	}
	return;
}

#Checks if profile matches another in this submission using arbitrary matches against allele 'N'.
sub _check_duplicate_profile {
	my ( $self, $args ) = @_;
	my ( $scheme_info, $profile, $pk, $problems ) =
	  @{$args}{qw(scheme_info profile pk problems)};
	my $q = $self->{'cgi'};
	no warnings 'uninitialized';
	local $" = ',';
	if ( $self->{'profiles_so_far'}->{"@$profile"} && none { $_ eq '' } @$profile ) {
		return 1 if $q->param('ignore_duplicates');
		$problems->{$pk} .= qq(The profile '@$profile' has been included more than once in this submission.<br />);
	} elsif ( $scheme_info->{'allow_missing_loci'} ) {
		foreach my $profile_string ( keys %{ $self->{'profiles_so_far'}->{"@$profile"} } ) {
			my $it_matches = 1;
			my @existing_profile = split /,/x, $profile_string;
			foreach my $i ( 0 .. @$profile - 1 ) {
				if (   $profile->[$i] ne $existing_profile[$i]
					&& $profile->[$i] ne 'N'
					&& $existing_profile[$i] ne 'N' )
				{
					$it_matches = 0;
					last;
				}
			}
			$problems->{$pk} .=
			    qq(The profile '@$profile' matches another profile in this submission when considering that )
			  . q(arbitrary allele 'N' can match any other allele.<br />)
			  if $it_matches;
		}
	}
	$self->{'profiles_so_far'}->{"@$profile"} = 1;
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
		$self->print_bad_status(
			{
				message => q(The temp file containing the checked profiles does not exist.),
				detail =>
				  q(Upload cannot proceed.  Make sure that you haven't used the back button and are attempting to )
				  . q(re-upload already submitted data.  Please report this if the problem persists.),
				navbar   => 1,
				back_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=profileBatchAdd&amp;scheme_id=$scheme_id)
			}
		);
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
	if ( $tmp_file =~ /^(.*\/BIGSdb_[0-9_]+)$/x ) {
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
		my ( @mv_fields, @mv_values );
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
			push @inserts,
			  {
				statement => 'INSERT INTO profile_members (scheme_id,locus,profile_id,allele_id,curator,'
				  . 'datestamp) VALUES (?,?,?,?,?,?)',
				arguments => [ $scheme_id, $locus, $profile_id, $data[ $fieldorder{$locus} ], $curator, 'now' ]
			  };
			push @mv_fields, $locus;
			push @mv_values, $data[ $fieldorder{$locus} ];
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
			push @mv_fields, $field;
			push @mv_values, $data[ $fieldorder{$field} ];
		}
		eval {
			foreach my $insert (@inserts) {
				$self->{'db'}->do( $insert->{'statement'}, undef, @{ $insert->{'arguments'} } );
			}
		};
		if ($@) {
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
			$logger->error($@);
			return;
		}
	}
	$self->{'db'}->commit;
	my $submission_id = $q->param('submission_id');
	my $detail;
	if ($submission_id) {
		my $url = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit&amp;)
		  . qq(submission_id=$submission_id&amp;curate=1);
		$detail = qq(Don't forget to <a href="$url">close the submission</a>!);
	}
	$self->print_good_status(
		{
			message       => q(Profiles added.),
			detail        => $detail,
			navbar        => 1,
			submission_id => $submission_id,
			more_text     => q(Add more),
			more_url      => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=profileBatchAdd&amp;scheme_id=$scheme_id)
		}
	);
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
	say q(<div class="box" id="queryform"><h2>Instructions</h2>)
	  . q(<p>This page allows you to upload profiles as tab-delimited text or copied from a spreadsheet.</p>)
	  . q(<ul><li>Field header names must be included and fields can be in any order. Optional fields can be omitted )
	  . q(if you wish.</li>);
	if ( $self->_is_integer_primary_key($scheme_id) ) {
		my $article = $primary_key =~ /^[AaEeIiOoUu]/x ? 'an' : 'a';
		say qq(<li>You can choose whether or not to include $article $primary_key field - if it is omitted, the next )
		  . qq(available $primary_key will be used automatically.  If however, you include it in the header line, then )
		  . q(you must also provide it for each profile record.</li>);
	}
	say q(</ul><h2>Templates</h2>);
	my ( $text, $excel ) = ( TEXT_FILE, EXCEL_FILE );
	say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableHeader&amp;)
	  . qq(table=profiles&amp;scheme_id=$scheme_id" title="Tab-delimited text header">$text</a>)
	  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=excelTemplate&amp;)
	  . qq(table=profiles&amp;scheme_id=$scheme_id" title="Excel format">$excel</a></p>);
	say q(<h2>Upload</h2>);
	say $q->start_form;
	my ( $users, $user_names ) = $self->{'datastore'}->get_users( { blank_message => 'Select sender ...' } );
	$user_names->{-1} = 'Override with sender field';
	say q[<fieldset style="float:left"><legend>Please paste in tab-delimited text ]
	  . q[(<strong>include a field header as the first line</strong>)</legend>];
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

sub get_help_url {
	my ($self) = @_;
	return
	  "$self->{'config'}->{'doclink'}/curator_guide/0060_adding_new_profiles.html#batch-profile-upload"
	  ;
}
1;
