#Written by Keith Jolley
#Copyright (c) 2013-2015, University of Oxford
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
	if ( !$scheme_id ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No scheme_id passed.</p></div>";
		return;
	} elsif ( !BIGSdb::Utils::is_int($scheme_id) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Scheme_id must be an integer.</p></div>";
		return;
	} elsif ( !$self->can_modify_table('profiles') ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to update profiles.</p></div>";
		return;
	} elsif ($set_id) {
		if ( !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id ) ) {
			say "<div class=\"box\" id=\"statusbad\"><p>The selected scheme is inaccessible.</p></div>";
			return;
		}
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	say "<h1>Batch profile update ($scheme_info->{'description'})</h1>";
	if ( !defined $scheme_info->{'primary_key'} ) {
		say "<div class=\"box\" id=\"statusbad\"><p>The selected scheme has no primary key.</p></div>";
		return;
	}
	if ( $q->param('update') ) {
		$self->_update;
	} elsif ( $q->param('data') ) {
		$self->_check;
	} else {
		print <<"HTML";
<div class="box" id="queryform">
<p>This page allows you to batch update allelic combinations or associated fields for multiple profiles.</p>
<ul><li>The first line, containing column headings, will be ignored.</li>
<li>The first column should be the primary key ($scheme_info->{'primary_key'}).</li>
<li>The next column should contain the field/locus name and then the final column should contain the value to be entered, e.g.<br />
<pre style="font-size:1.2em">
ST  field   value
5   abcZ    7
5   adk     3
</pre>
</li>
<li>The columns should be separated by tabs. Any other columns will be ignored.</li>
<li>If you wish to blank a field, enter '&lt;blank&gt;' as the value.</li></ul>
HTML
		say $q->start_form;
		say $q->hidden($_) foreach qw (db page scheme_id);
		say "<fieldset style=\"float:left\"><legend>Please paste in your data below:</legend>";
		say $q->textarea( -name => 'data', -rows => 15, -columns => 40, -override => 1 );
		say "</fieldset>";
		say "<fieldset style=\"float:left\"><legend>Options</legend>";
		say "<ul><li>";
		say $q->checkbox( -name => 'overwrite', -label => 'Overwrite existing data', -checked => 0 );
		say "</li></ul></fieldset>";
		$self->print_action_fieldset( { scheme_id => $scheme_id } );
		say $q->endform;
		say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back to main page</a></p></div>";
	}
	return;
}

sub _check {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	my $data      = $q->param('data');
	my @rows = split /\n/, $data;
	if ( @rows < 2 ) {
		say qq(<div class="box" id="statusbad"><p>Nothing entered.  Make sure you include a header line.</p>);
		say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchProfileUpdate&amp;)
		  . qq(scheme_id=$scheme_id">Back</a></p></div>);
		return;
	}
	my $set_id      = $self->get_set_id;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	my $pk          = $scheme_info->{'primary_key'};
	if ( !defined $pk ) {
		$logger->error("No primary key defined for scheme $scheme_id");
		say qq(<div class="box" id="statusbad"><p>The selected scheme has no primary key.</p></div>);
		return;
	}
	my $buffer = qq(<div class="box" id="resultstable"><div class="scrollable">\n);
	$buffer .= "<p>The following changes will be made to the database.  Please check that this is what you intend and "
	  . "then press 'Submit'.  If you do not wish to make these changes, press your browser's back button.</p>\n";
	$buffer .= qq(<fieldset style="float:left"><legend>Updates</legend>);
	$buffer .= qq(<table class="resultstable"><tr><th>Transaction</th><th>$scheme_info->{'primary_key'}</th><th>Field</th>)
	  . qq(<th>New value</th><th>Value currently in database</th><th>Action</th></tr>\n);
	my $scheme_loci   = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my ( %mapped, %reverse_mapped );

	foreach my $locus (@$scheme_loci) {
		my $mapped = $self->clean_locus( $locus, { text_output => 1, no_common_name => 1 } );
		$mapped{$locus}          = $mapped;
		$reverse_mapped{$mapped} = $locus;
	}
	map { $mapped{$_} = $_; $reverse_mapped{$_} = $_ } @$scheme_fields;
	my $i          = 0;
	my $td         = 1;
	my $prefix     = BIGSdb::Utils::get_random();
	my $file       = "$self->{'config'}->{'secure_tmp_dir'}/$prefix.txt";
	my $table_rows = 0;
	my ( @id, @field, @value, @update );
	my %locus_changes_for_pk;

	foreach my $row (@rows) {
		my @cols = split /\t/, $row;
		next if @cols < 3;
		( $id[$i], $field[$i], $value[$i] ) = split /\t/, $row;
		$id[$i] =~ s/%20/ /g;
		if ( defined $value[$i] ) {
			$value[$i] =~ s/\s*$//;
			$value[$i] =~ s/^\s*//;
		}
		my $displayvalue = $value[$i];
		my $bad_field    = 0;
		my $field_type;
		if ( any { $field[$i] eq $mapped{$_} } @$scheme_loci ) {
			$field_type = 'locus';
		} elsif (
			any {
				$field[$i] eq $_;
			}
			@$scheme_fields
		  )
		{
			$field_type = 'field';
		} else {
			$bad_field = 1;
		}
		$update[$i] = 0;
		my ( $old_value, $action );
		if ( $i && defined $value[$i] && $value[$i] ne '' ) {
			if ( !$bad_field ) {
				my @args;
				push @args, $id[$i];
				my $profile_data = $self->{'datastore'}->run_query( "SELECT * FROM scheme_$scheme_id WHERE $pk=?",
					$id[$i], { fetch => 'row_hashref', cache => 'CurateBatchProfileUpdatePage::check::select' } );
				if ( !$profile_data ) {
					$old_value = "<span class=\"statusbad\">no editable record with $pk='$id[$i]'";
					$old_value .= "</span>";
					$action = "<span class=\"statusbad\">no action</span>";
				} else {
					$old_value = $profile_data->{ lc( $reverse_mapped{ $field[$i] } ) };
					if (   !defined $old_value
						|| $old_value eq ''
						|| $q->param('overwrite') )
					{
						$old_value = "&lt;blank&gt;"
						  if !defined $old_value || $old_value eq '';
						my $problem;
						if ( $field_type eq 'locus' ) {
							my $locus_info = $self->{'datastore'}->get_locus_info( $reverse_mapped{ $field[$i] } );
							if ( $value[$i] eq '<blank>' ) {
								$problem = "this is a required field and cannot be left blank";
							} elsif ( $locus_info->{'allele_id_format'} eq 'integer'
								&& !BIGSdb::Utils::is_int( $value[$i] )
								&& !( $scheme_info->{'allow_missing_loci'} && $value[$i] eq 'N' ) )
							{
								$problem = "invalid allele id (must be an integer)";
							} elsif ( !$self->{'datastore'}->sequence_exists( $reverse_mapped{ $field[$i] }, $value[$i] ) ) {
								$problem = "allele has not been defined";
							} elsif ( $value[$i] ne $old_value ) {
								my %new_profile;
								foreach my $locus (@$scheme_loci) {
									$new_profile{"locus:$locus"} = $profile_data->{ lc($locus) };
								}
								$new_profile{"locus:$reverse_mapped{$field[$i]}"} = $value[$i];
								$new_profile{"field:$pk"}                         = $id[$i];
								my ( $exists, $msg ) = $self->profile_exists( $scheme_id, $pk, \%new_profile );
								if ($exists) {
									$problem = "would result in duplicate profile. $msg";
								}
							}
							$locus_changes_for_pk{ $id[$i] }++;
							if ( $locus_changes_for_pk{ $id[$i] } > 1 ) {
								$problem = "profile updates are limited to one locus change"
								  ;    #too difficult to check if new profile already exists otherwise
							}
						} elsif ( $field_type eq 'field' ) {
							my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field[$i] );
							if ( $value[$i] eq '<blank>' && $field[$i] eq $pk ) {
								$problem = "this is a required field and cannot be left blank";
							} elsif ( $field_info->{'type'} eq 'integer' && !BIGSdb::Utils::is_int( $value[$i] ) ) {
								$problem = "invalid field value (must be an integer)";
							} elsif ( $field[$i] eq $pk && $value[$i] ne $old_value ) {
								my $new_pk_exists =
								  $self->{'datastore'}->run_query( "SELECT EXISTS(SELECT $pk FROM scheme_$scheme_id WHERE $pk=?)",
									$value[$i], { cache => 'CurateBatchProfileUpdatePage::check::pkexists' } );
								$problem = "new $pk already exists" if $new_pk_exists;
							}
						}
						if ($problem) {
							$action = qq(<span class="statusbad">no action - $problem</span>);
						} else {
							if ( $value[$i] eq $old_value || ( $value[$i] eq '<blank>' && $old_value eq '&lt;blank&gt;' ) ) {
								$action = qq(<span class="statusbad">no action - new value unchanged</span>);
								$update[$i] = 0;
							} else {
								$action = qq(<span class="statusgood">update field with new value</span>);
								$update[$i] = 1;
							}
						}
					} else {
						$action = "<span class=\"statusbad\">no action - value already in db</span>";
					}
				}
			} else {
				$old_value = qq(<span class="statusbad">field not recognised</span>);
				$action    = qq(<span class="statusbad">no action</span>);
			}
			$displayvalue =~ s/<blank>/&lt;blank&gt;/;
			$buffer .= qq(<tr class="td$td"><td>$i</td><td>$id[$i]</td><td>$field[$i]</td><td>$displayvalue</td>)
			  . qq(<td>$old_value</td><td>$action</td></tr>);
			$table_rows++;
			$td = $td == 1 ? 2 : 1;
		}
		$value[$i] =~ s/(<blank>|null)// if defined $value[$i];
		$i++;
	}
	if ($table_rows) {
		say $buffer;
		say "</table></fieldset>";
		open( my $fh, '>', $file ) or $logger->error("Can't open temp file $file for writing");
		foreach my $i ( 0 .. @rows - 1 ) {
			say $fh "$id[$i]\t$reverse_mapped{$field[$i]}\t$value[$i]" if $update[$i];
		}
		close $fh;
		say $q->start_form;
		$q->param( update => 1 );
		$q->param( file   => "$prefix.txt" );
		say $q->hidden($_) foreach qw (db page update file scheme_id);
		$self->print_action_fieldset( { submit_label => 'Update', no_reset => 1 } );
		say $q->endform;
	} else {
		say qq(<div class="box" id="statusbad"><p>No valid values to update.</p>);
	}
	say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p>\n</div></div>);
	return;
}

sub _update {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	my $file      = $q->param('file');
	my $transaction;
	my $i = 1;
	open( my $fh, '<', "$self->{'config'}->{'secure_tmp_dir'}/$file" ) or $logger->error("Can't open $file for reading");
	while ( my $line = <$fh> ) {
		chomp $line;
		my @record = split /\t/, $line;
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
	say qq(<div class="box" id="resultsheader">);
	say "<h2>Updating database ...</h2>";
	my $curator_id   = $self->get_curator_id;
	my $curator_name = $self->get_curator_name;
	say "User: $curator_name<br />";
	my $datestamp = BIGSdb::Utils::get_datestamp();
	say "Datestamp: $datestamp<br />";
	my $tablebuffer;
	my $td           = 1;
	my $changes      = 0;
	my $update_error = 0;
	my @history_updates;

	foreach my $i ( sort { $a <=> $b } keys %$transaction ) {
		my ( $id, $field, $value ) = ( $transaction->{$i}->{'id'}, $transaction->{$i}->{'field'}, $transaction->{$i}->{'value'} );
		my $old_record = $self->{'datastore'}->run_query( "SELECT * FROM scheme_$scheme_id WHERE $scheme_info->{'primary_key'}=?",
			$id, { fetch => 'row_hashref', cache => 'CurateBatchProfileUpdatePage::update::select' } );
		my $old_value = $old_record->{ lc($field) };
		my $is_locus  = $self->{'datastore'}->is_locus($field);
		my @updates;
		if ($is_locus) {
			push @updates,
			  {
				statement => "UPDATE profile_members SET (allele_id,curator,datestamp)=(?,?,?) WHERE (scheme_id,locus,profile_id)=(?,?,?)",
				arguments => [ $value, $curator_id, 'now', $scheme_id, $field, $id ]
			  };
		} else {
			my $field_exists =
			  $self->{'datastore'}
			  ->run_query( "SELECT EXISTS(SELECT * FROM profile_fields WHERE (scheme_id,scheme_field,profile_id)=(?,?,?))",
				[$scheme_id, $field, $id],{cache=>'CurateBatchProfileUpdatePage::update::fieldexists'} );
			if ($field_exists) {
				if ( !defined $value ) {
					push @updates,
					  {
						statement => "DELETE FROM profile_fields WHERE (scheme_id,scheme_field,profile_id)=(?,?,?)",
						arguments => [ $scheme_id, $field, $id ]
					  };
				} else {
					push @updates,
					  {
						statement => "UPDATE profile_fields SET (value,curator,datestamp)=(?,?,?) WHERE "
						  . "(scheme_id,scheme_field,profile_id)=(?,?,?)",
						arguments => [ $value, $curator_id, 'now', $scheme_id, $field, $id ]
					  };
				}
			} else {
				push @updates, {
					statement => "INSERT INTO profile_fields (scheme_id,scheme_field,profile_id,value,curator,datestamp) "
					  . "VALUES (?,?,?,?,?,?)",
					arguments => [ $scheme_id, $field, $id, $value, $curator_id, 'now' ]
				};
			}
			if ( $field eq $scheme_info->{'primary_key'} ) {
				push @updates,
				  {
					statement => "UPDATE profiles SET (profile_id,curator,datestamp)=(?,?,?) WHERE (scheme_id,profile_id)=(?,?)",
					arguments => [ $value, $curator_id, 'now', $scheme_id, $id ]
				  };
			}
		}
		$tablebuffer .= qq(<tr class="td$td"><td>$id</td>);
		$value     //= '&lt;blank&gt;';
		$old_value //= '&lt;blank&gt;';
		$tablebuffer .= "<td>$mapped{$field}</td><td>$old_value</td><td>$value</td>";
		$changes = 1 if @updates;
		eval { $self->{'db'}->do( $_->{'statement'}, undef, @{ $_->{'arguments'} } ) foreach @updates };
		if ($@) {
			$logger->error($@);
			$tablebuffer .= qq(<td class="statusbad">can't update!</td></tr>\n);
			$update_error = 1;
		} else {
			$tablebuffer .= qq(<td class="statusgood">OK</td></tr>\n);
			$old_value //= '';
			$old_value = ''     if $old_value eq '&lt;blank&gt;';
			$value     = ''     if $value     eq '&lt;blank&gt;';
			$id        = $value if $field     eq $scheme_info->{'primary_key'};
			push @history_updates, { id => $id, action => "$field: '$old_value' -> '$value'" };
		}
		$td = $td == 1 ? 2 : 1;
		last if $update_error;
	}
	if ( !$changes ) {
		say "<p>No changes to be made.</p>";
	} else {
		say qq(<table class="resultstable"><tr><th>$scheme_info->{'primary_key'}</th><th>Field</th><th>Old value</th>)
		  . qq(<th>New value</th><th>Status</th></tr>$tablebuffer</table>);
		if ($update_error) {
			$self->{'db'}->rollback;
			say "<p>Transaction failed - no changes made.</p>";
		} else {
			$self->{'db'}->commit;
			$self->refresh_material_view($scheme_id);
			$self->update_profile_history( $scheme_id, $_->{'id'}, $_->{'action'} ) foreach @history_updates;
			say "<p>Transaction complete - database updated.</p>";
		}
	}
	say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p>\n</div>);
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Batch Profile Update - $desc";
}
1;
