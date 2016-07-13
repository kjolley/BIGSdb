#Written by Keith Jolley
#Copyright (c) 2013-2016, University of Oxford
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
package BIGSdb::CurateBatchProfileUpdatePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateProfileUpdatePage);
use BIGSdb::Utils;
use List::MoreUtils qw(none any uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $set_id    = $self->get_set_id;
	my $scheme_id = $q->param('scheme_id');
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say q(<div class="box" id="statusbad"><p>You can only update profiles in a sequence/profile database - )
		  . q(this is an isolate database.</p></div>);
		return;
	}
	if ( !$scheme_id ) {
		say q(<div class="box" id="statusbad"><p>No scheme_id passed.</p></div>);
		return;
	}
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		say q(<div class="box" id="statusbad"><p>Scheme_id must be an integer.</p></div>);
		return;
	}
	if ( !$self->can_modify_table('profiles') ) {
		say q(<div class="box" id="statusbad"><p>Your user account is not allowed ) . q(to update profiles.</p></div>);
		return;
	}
	if ($set_id) {
		if ( !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id ) ) {
			say q(<div class="box" id="statusbad"><p>The selected scheme is inaccessible.</p></div>);
			return;
		}
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	say qq(<h1>Batch profile update ($scheme_info->{'description'})</h1>);
	if ( !defined $scheme_info->{'primary_key'} ) {
		say q(<div class="box" id="statusbad"><p>The selected scheme has no primary key.</p></div>);
		return;
	}
	if ( $q->param('update') ) {
		$self->_update;
	} elsif ( $q->param('data') ) {
		$self->_check;
	} else {
		say q(<div class="box" id="queryform"><p>This page allows you to batch update allelic combinations )
		  . q(or associated fields for multiple profiles.</p>)
		  . q(<ul><li>The first line, containing column headings, will be ignored.</li>)
		  . qq(<li>The first column should be the primary key ($scheme_info->{'primary_key'}).</li>)
		  . q(<li>The next column should contain the field/locus name and then the final column should )
		  . q(contain the value to be entered, e.g.<br />);
		say qq(<pre style="font-size:1.2em">\n)
		  . qq(ST  field   value\n)
		  . qq(5   abcZ    7\n)
		  . qq(5   adk     3\n)
		  . q(</pre>);
		say q(</li><li>The columns should be separated by tabs. Any other columns will be ignored.</li>)
		  . q(<li>If you wish to blank a field, enter '&lt;blank&gt;' as the value.</li></ul>);
		say $q->start_form;
		say $q->hidden($_) foreach qw (db page scheme_id);
		say q(<fieldset style="float:left"><legend>Please paste in your data below:</legend>);
		say $q->textarea( -name => 'data', -rows => 15, -columns => 40, -override => 1 );
		say q(</fieldset>);
		say q(<fieldset style="float:left"><legend>Options</legend>);
		say q(<ul><li>);
		say $q->checkbox( -name => 'overwrite', -label => 'Overwrite existing data', -checked => 0 );
		say q(</li></ul></fieldset>);
		$self->print_action_fieldset( { scheme_id => $scheme_id } );
		say $q->end_form;
		say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">)
		  . q(Back to main page</a></p></div>);
	}
	return;
}

sub _check {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	my $data      = $q->param('data');
	my @rows = split /\n/x, $data;
	if ( @rows < 2 ) {
		say q(<div class="box" id="statusbad"><p>Nothing entered.  Make sure you include a header line.</p>);
		say q(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchProfileUpdate&amp;)
		  . qq(scheme_id=$scheme_id">Back</a></p></div>);
		return;
	}
	my $set_id      = $self->get_set_id;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	my $pk_field    = $scheme_info->{'primary_key'};
	if ( !defined $pk_field ) {
		$logger->error("No primary key defined for scheme $scheme_id");
		say q(<div class="box" id="statusbad"><p>The selected scheme has no primary key.</p></div>);
		return;
	}
	my $scheme_loci   = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my ( %mapped, %reverse_mapped );
	foreach my $locus (@$scheme_loci) {
		my $mapped = $self->clean_locus( $locus, { text_output => 1, no_common_name => 1 } );
		$mapped{$locus}          = $mapped;
		$reverse_mapped{$mapped} = $locus;
	}
	foreach my $field (@$scheme_fields) {
		$mapped{$field}         = $field;
		$reverse_mapped{$field} = $field;
	}
	my @validated_actions;
	shift @rows;    #Remove header
	my $td = 1;
	my $buffer;
	my $indices = $self->{'datastore'}->get_scheme_locus_indices( $scheme_info->{'id'} );
	foreach my $row (@rows) {
		my @columns = split /\t/x, $row;
		BIGSdb::Utils::remove_trailing_spaces_from_list( \@columns );
		my ( $pk, $display_field, $value ) = @columns;
		my $field = $reverse_mapped{$display_field} // q();
		my $display_value = $self->_get_display_value($value);
		my $problem;
		my $args = {
			loci        => $scheme_loci,
			fields      => $scheme_fields,
			scheme_info => $scheme_info,
			pk          => $pk,
			field       => $field,
			value       => $value,
			problem     => \$problem
		};

		#Check field is locus or scheme field
		$args->{'field_type'} = $self->_check_field($args);

		#Check record exists
		$args->{'profile'} = $self->_check_profile($args);

		#Identify old value
		$args->{'old_value'} = $args->{'profile'}->{'profile'}->[ $indices->{$field} ];

		#Check if value already exists and 'overwrite' is not checked
		$self->_check_overwrite($args);
		$args->{'old_value'} //= q();

		#If locus, check that a value is provided
		$self->_check_locus_has_value($args);

		#If integer locus, check value format - allow 'N' if missing_data allowed
		$self->_check_locus_format($args);

		#If locus, check allele exists
		$self->_check_allele_exists($args);

		#Check that new value is different from old
		$self->_check_unchanged_value($args);

		#If locus, check that new profile doesn't already exist
		$self->_check_existing_profile($args);

		#If locus, check that an allele hasn't already been changed
		$self->_check_limited_profile_change($args);

		#If pk, check that value is not blank
		$self->_check_pk_field_not_empty($args);

		#If int field, check field format
		$self->_check_field_format($args);

		#If pk, check that profile_id not already defined or retired
		$self->_check_existing_profile_id($args);

		#Rewrite <blank> or null to undef
		if ( $value eq '<blank>' || lc($value) eq 'null' ) {
			undef $value;
		}
		my $action =
		  $problem
		  ? qq(<span class="statusbad">no action - $problem</span>)
		  : q(<span class="statusgood">update field with new value</span>);
		$buffer .= qq(<tr class="td$td"><td>$pk</td><td>$display_field</td><td>$display_value</td>)
		  . qq(<td>$args->{'old_value'}</td><td>$action</td></tr>);
		next if $problem;
		push @validated_actions, { pk => $pk, field => $field, value => $value };
	}
	if ($buffer) {
		say q(<div class="box" id="resultstable"><div class="scrollable">);
		say q(<p>The following changes will be made to the database.  Please check that this is what )
		  . q(you intend and then press 'Submit'.  If you do not wish to make these changes, press your )
		  . q(browser's back button.</p><fieldset style="float:left"><legend>Updates</legend>);
		say qq(<table class="resultstable"><tr><th>$scheme_info->{'primary_key'}</th>)
		  . q(<th>Field</th><th>New value</th><th>Value currently in database</th><th>Action</th></tr>);
		say $buffer;
		say q(</table></fieldset>);
		my $prefix = BIGSdb::Utils::get_random();
		my $file   = "$self->{'config'}->{'secure_tmp_dir'}/$prefix.txt";
		open( my $fh, '>', $file ) or $logger->error("Cannot open temp file $file for writing");

		foreach my $action (@validated_actions) {
			$action->{'value'} //= q();
			say $fh qq($action->{'pk'}\t$action->{'field'}\t$action->{'value'});
		}
		close $fh;
		say $q->start_form;
		$q->param( update => 1 );
		$q->param( file   => qq($prefix.txt) );
		say $q->hidden($_) foreach qw (db page update file scheme_id);
		$self->print_action_fieldset( { submit_label => 'Update', no_reset => 1 } );
		say $q->end_form;
	} else {
		say q(<div class="box" id="statusbad"><p>No valid values to update.</p>);
	}
	say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">)
	  . q(Back to main page</a></p></div></div>);
	return;
}

sub _get_display_value {
	my ( $self, $value ) = @_;
	$value =~ s/(<blank>|null)/&lt;blank&gt;/x;
	return $value;
}

sub _check_field {
	my ( $self, $args ) = @_;
	my ( $field, $fields, $loci, $problem ) = @$args{qw(field fields loci problem)};
	my %fields = map { $_ => 1 } @$fields;
	return 'field' if $fields{$field};
	my %loci = map { $_ => 1 } @$loci;
	return 'locus' if $loci{$field};
	$$problem = 'field not recognised';
	return;
}

sub _check_profile {
	my ( $self, $args ) = @_;
	my ( $pk, $scheme_info, $problem ) = @$args{qw(pk scheme_info problem)};
	return if $$problem;
	my $profile_data =
	  $self->{'datastore'}
	  ->run_query( "SELECT * FROM mv_scheme_$scheme_info->{'id'} WHERE $scheme_info->{'primary_key'}=?",
		$pk, { fetch => 'row_hashref', cache => 'CurateBatchProfileUpdatePage::check_profile' } );
	if ( !$profile_data ) {
		$$problem = "no editable record with $scheme_info->{'primary_key'}='$pk'";
	}
	return $profile_data;
}

sub _check_overwrite {
	my ( $self,      $args )    = @_;
	my ( $old_value, $problem ) = @$args{qw(old_value problem)};
	return if $$problem;
	return if $self->{'cgi'}->param('overwrite');
	if ( defined $old_value ) {
		$$problem = q(value already in db (select Overwrite checkbox if required));
	}
	return;
}

sub _check_locus_has_value {
	my ( $self, $args ) = @_;
	my ( $field_type, $field, $value, $problem ) = @$args{qw(field_type field value problem)};
	return if $$problem;
	return if ( $field_type // q() ) ne 'locus';
	my $locus_info = $self->{'datastore'}->get_locus_info($field);
	if ( $value eq '<blank>' || lc($value) eq 'null' ) {
		$$problem = q(this is a required field and cannot be left blank);
	}
	return;
}

sub _check_locus_format {
	my ( $self, $args ) = @_;
	my ( $field_type, $field, $value, $scheme_info, $problem ) = @$args{qw(field_type field value scheme_info problem)};
	return if $$problem;
	return if ( $field_type // q() ) ne 'locus';
	my $locus_info = $self->{'datastore'}->get_locus_info($field);
	if (   $locus_info->{'allele_id_format'} eq 'integer'
		&& !BIGSdb::Utils::is_int($value)
		&& !( $scheme_info->{'allow_missing_loci'} && $value eq 'N' ) )
	{
		$$problem = q(invalid allele id (must be an integer));
	}
	return;
}

sub _check_allele_exists {
	my ( $self, $args ) = @_;
	my ( $field_type, $field, $value, $problem ) = @$args{qw(field_type field value problem)};
	return if $$problem;
	return if ( $field_type // q() ) ne 'locus';
	if ( !$self->{'datastore'}->sequence_exists( $field, $value ) ) {
		$$problem = q(allele has not been defined);
	}
	return;
}

sub _check_unchanged_value {
	my ( $self, $args ) = @_;
	my ( $old_value, $value, $problem ) = @$args{qw(old_value value problem)};
	return if $$problem;
	if ( $old_value eq $value || ( $old_value eq q() && ( $value eq '<blank>' || lc($value) eq 'null' ) ) ) {
		$$problem = q(new value unchanged);
	}
	return;
}

sub _check_existing_profile {
	my ( $self, $args ) = @_;
	my ( $field_type, $field, $value, $scheme_info, $loci, $profile, $pk, $problem ) =
	  @$args{qw(field_type field value scheme_info loci profile pk problem)};
	return if $$problem;
	return if ( $field_type // q() ) ne 'locus';
	my %new_profile;
	my $indices = $self->{'datastore'}->get_scheme_locus_indices( $scheme_info->{'id'} );
	foreach my $locus (@$loci) {
		$new_profile{"locus:$locus"} = $profile->{'profile'}->[ $indices->{$locus} ];
	}
	$new_profile{"locus:$field"}                        = $value;
	$new_profile{"field:$scheme_info->{'primary_key'}"} = $pk;
	my %designations = map { $_ => $new_profile{"locus:$_"} } @$loci;
	my $ret = $self->{'datastore'}->check_new_profile( $scheme_info->{'id'}, \%designations, $pk );
	if ( $ret->{'exists'} ) {
		$$problem = qq(would result in duplicate profile. $ret->{'msg'});
	}
	return;
}

sub _check_limited_profile_change {
	my ( $self, $args ) = @_;
	my ( $field_type, $field, $scheme_info, $pk, $problem ) = @$args{qw(field_type field scheme_info pk problem)};
	return if $$problem;
	return if ( $field_type // q() ) ne 'locus';
	$self->{'locus_changes_for_pk'}->{ $scheme_info->{'id'} }->{$pk}++;
	if ( $self->{'locus_changes_for_pk'}->{ $scheme_info->{'id'} }->{$pk} > 1 ) {

		#too difficult to check if new profile already exists otherwise
		$$problem = q(profile updates are limited to one locus change);
	}
	return;
}

sub _check_pk_field_not_empty {
	my ( $self, $args ) = @_;
	my ( $field_type, $field, $value, $scheme_info, $problem ) = @$args{qw(field_type field value scheme_info problem)};
	return if $$problem;
	return if $field ne $scheme_info->{'primary_key'};
	if ( $value eq '<blank>' || lc($value) eq 'null' ) {
		$$problem = q(this is a required field and cannot be left blank);
	}
	return;
}

sub _check_field_format {
	my ( $self, $args ) = @_;
	my ( $field_type, $field, $value, $scheme_info, $problem ) = @$args{qw(field_type field value scheme_info problem)};
	return if $$problem;
	return if ( $field_type // q() ) ne 'field';
	my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_info->{'id'}, $field );
	if ( $field_info->{'type'} eq 'integer' && !BIGSdb::Utils::is_int($value) ) {
		$$problem = q(invalid field value (must be an integer));
	}
	return;
}

sub _check_existing_profile_id {
	my ( $self, $args ) = @_;
	my ( $field_type, $field, $value, $scheme_info, $problem ) = @$args{qw(field_type field value scheme_info problem)};
	return if $$problem;
	return if ( $field_type // q() ) ne 'field';
	my $new_pk_exists = $self->{'datastore'}->run_query(
		"SELECT EXISTS(SELECT $scheme_info->{'primary_key'} FROM mv_scheme_$scheme_info->{'id'} "
		  . "WHERE $scheme_info->{'primary_key'}=? UNION SELECT profile_id FROM retired_profiles "
		  . 'WHERE (scheme_id,profile_id)=(?,?))',
		[ $value, $scheme_info->{'id'}, $value ],
		{ cache => 'CurateBatchProfileUpdatePage::check::pkexists' }
	);
	if ($new_pk_exists) {
		$$problem = qq(new $scheme_info->{'primary_key'} already exists or has been retired) if $new_pk_exists;
	}
	return;
}

sub _update {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	my $file      = $q->param('file');
	my $transaction;
	my $i = 1;
	open( my $fh, '<', "$self->{'config'}->{'secure_tmp_dir'}/$file" )
	  or $logger->error("Can't open $file for reading");
	while ( my $line = <$fh> ) {
		chomp $line;
		my @record = split /\t/x, $line;
		$transaction->{$i}->{'id'}    = $record[0];
		$transaction->{$i}->{'field'} = $record[1];
		$transaction->{$i}->{'value'} = $record[2];
		$i++;
	}
	close $fh;
	my $scheme_info   = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $scheme_loci   = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my %mapped;
	foreach my $locus (@$scheme_loci) {
		$mapped{$locus} = $self->clean_locus( $locus, { text_output => 1, no_common_name => 1 } );
	}
	map { $mapped{$_} = $_ } @$scheme_fields;
	say q(<div class="box" id="resultsheader">);
	say q(<h2>Updating database ...</h2>);
	my $curator_id   = $self->get_curator_id;
	my $curator_name = $self->get_curator_name;
	say qq(User: $curator_name<br />);
	my $datestamp = BIGSdb::Utils::get_datestamp();
	say qq(Datestamp: $datestamp<br />);
	my $tablebuffer;
	my $td           = 1;
	my $changes      = 0;
	my $update_error = 0;
	my @history_updates;
	my $indices = $self->{'datastore'}->get_scheme_locus_indices( $scheme_info->{'id'} );

	foreach my $i ( sort { $a <=> $b } keys %$transaction ) {
		my ( $id, $field, $value ) =
		  ( $transaction->{$i}->{'id'}, $transaction->{$i}->{'field'}, $transaction->{$i}->{'value'} );
		my $old_record =
		  $self->{'datastore'}->run_query( "SELECT * FROM mv_scheme_$scheme_id WHERE $scheme_info->{'primary_key'}=?",
			$id, { fetch => 'row_hashref', cache => 'CurateBatchProfileUpdatePage::update::select' } );
		my $old_value;
		my $is_locus = $self->{'datastore'}->is_locus($field);
		if ($is_locus) {
			$old_value = $old_record->{'profile'}->[ $indices->{$field} ];
		} else {
			$old_value = $old_record->{ lc($field) };
		}
		my @updates;
		if ($is_locus) {
			push @updates,
			  {
				statement => 'UPDATE profile_members SET (allele_id,curator,datestamp)=(?,?,?) '
				  . 'WHERE (scheme_id,locus,profile_id)=(?,?,?)',
				arguments => [ $value, $curator_id, 'now', $scheme_id, $field, $id ]
			  };
		} else {
			my $field_exists = $self->{'datastore'}->run_query(
				'SELECT EXISTS(SELECT * FROM profile_fields WHERE (scheme_id,scheme_field,profile_id)=(?,?,?))',
				[ $scheme_id, $field, $id ],
				{ cache => 'CurateBatchProfileUpdatePage::update::fieldexists' }
			);
			if ($field_exists) {
				if ( !defined $value ) {
					push @updates,
					  {
						statement => 'DELETE FROM profile_fields WHERE (scheme_id,scheme_field,profile_id)=(?,?,?)',
						arguments => [ $scheme_id, $field, $id ]
					  };
				} else {
					push @updates,
					  {
						statement => 'UPDATE profile_fields SET (value,curator,datestamp)=(?,?,?) WHERE '
						  . '(scheme_id,scheme_field,profile_id)=(?,?,?)',
						arguments => [ $value, $curator_id, 'now', $scheme_id, $field, $id ]
					  };
				}
			} else {
				push @updates,
				  {
					statement => 'INSERT INTO profile_fields (scheme_id,scheme_field,profile_id,value,'
					  . 'curator,datestamp) VALUES (?,?,?,?,?,?)',
					arguments => [ $scheme_id, $field, $id, $value, $curator_id, 'now' ]
				  };
			}
			if ( $field eq $scheme_info->{'primary_key'} ) {
				push @updates,
				  {
					statement => 'UPDATE profiles SET (profile_id,curator,datestamp)=(?,?,?) WHERE '
					  . '(scheme_id,profile_id)=(?,?)',
					arguments => [ $value, $curator_id, 'now', $scheme_id, $id ]
				  };
			}
		}
		$tablebuffer .= qq(<tr class="td$td"><td>$id</td>);
		$value     //= q(&lt;blank&gt;);
		$old_value //= q(&lt;blank&gt;);
		$tablebuffer .= qq(<td>$mapped{$field}</td><td>$old_value</td><td>$value</td>);
		$changes = 1 if @updates;
		eval { $self->{'db'}->do( $_->{'statement'}, undef, @{ $_->{'arguments'} } ) foreach @updates };
		if ($@) {
			$logger->error($@);
			$tablebuffer .= qq(<td class="statusbad">can't update!</td></tr>\n);
			$update_error = 1;
		} else {
			$tablebuffer .= qq(<td class="statusgood">OK</td></tr>\n);
			$old_value //= q();
			$old_value = q()    if $old_value eq '&lt;blank&gt;';
			$value     = q()    if $value     eq '&lt;blank&gt;';
			$id        = $value if $field     eq $scheme_info->{'primary_key'};
			push @history_updates, { id => $id, action => qq($field: '$old_value' -> '$value') };
		}
		$td = $td == 1 ? 2 : 1;
		last if $update_error;
	}
	if ( !$changes ) {
		say q(<p>No changes to be made.</p>);
	} else {
		say qq(<table class="resultstable"><tr><th>$scheme_info->{'primary_key'}</th><th>Field</th><th>Old value</th>)
		  . qq(<th>New value</th><th>Status</th></tr>$tablebuffer</table>);
		if ($update_error) {
			$self->{'db'}->rollback;
			say q(<p>Transaction failed - no changes made.</p>);
		} else {
			$self->{'db'}->commit;
			$self->update_profile_history( $scheme_id, $_->{'id'}, $_->{'action'} ) foreach @history_updates;
			say q(<p>Transaction complete - database updated.</p>);
		}
	}
	say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>);
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Batch Profile Update - $desc";
}
1;
