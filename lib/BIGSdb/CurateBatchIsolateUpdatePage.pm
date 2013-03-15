#Written by Keith Jolley
#Copyright (c) 2010-2013, University of Oxford
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
package BIGSdb::CurateBatchIsolateUpdatePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<h1>Batch isolate update</h1>\n";
	if ( !$self->can_modify_table('isolates') || !$self->can_modify_table('allele_designations') ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to update "
		  . "either isolate records or allele designations.</p></div>";
		return;
	}
	if ( $q->param('update') ) {
		$self->_update;
	} elsif ( $q->param('data') ) {
		$self->_check;
	} else {
		print <<"HTML";
<div class="box" id="queryform">
<p>This page allows you to batch update provenance fields or allele designations for multiple isolates.</p>
<ul><li>  The first line, containing column headings, will be ignored.</li>
<li> The first column should be the isolate id (or unique field that you are selecting isolates on).  If a 
secondary selection field is used (so that together the combination of primary and secondary fields are unique), 
this should be entered in the second column.</li>
<li>The next column should contain the field/locus name and then the 
final column should contain the value to be entered, e.g.<br />
<pre style="font-size:1.2em">
id	field	value
2	country	USA
2	abcZ	5
</pre>
</li>
<li> The columns should be separated by tabs. Any other columns will be ignored.</li>
<li> If you wish to blank a field, enter '&lt;blank&gt;' as the value.</li>
<li>The script is compatible with STARS output files.</li></ul>
<p>Please enter the field(s) that you are selecting isolates on.  Values used must be unique within this field or 
combination of fields, i.e. only one isolate has the value(s) used.  Usually the database id will be used.</p>
HTML
		my $set_id        = $self->get_set_id;
		my $metadata_list = $self->{'datastore'}->get_set_metadata( $set_id, { curate => 1 } );
		my $fields        = $self->{'xmlHandler'}->get_field_list($metadata_list);
		say $q->start_form;
		say $q->hidden($_) foreach qw (db page);
		say "<fieldset><legend>Options</legend>";
		say "<ul><li><label for=\"idfield1\" class=\"filter\">Primary selection field: </label>";
		say $q->popup_menu( -name => 'idfield1', -id => 'idfield1', -values => $fields );
		say "</li><li><label for=\"idfield2\" class=\"filter\">Optional selection field: </label>";
		unshift @$fields, '<none>';
		say $q->popup_menu( -name => 'idfield2', -id => 'idfield2', -values => $fields );
		say "</li><li>";
		say $q->checkbox( -name => 'overwrite', -label => 'Overwrite existing data', -checked => 0 );
		say "</li></ul></fieldset>";
		say "<p>Please paste in your data below:</p>";
		say $q->textarea( -name => 'data', -rows => 15, -columns => 40, -override => 1 );
		say "<span style=\"float:left\">";
		say $q->reset( -class => 'reset' );
		say "</span>\n<span style=\"float:right;padding-right:2em\">";
		say $q->submit( -label => 'Submit', -class => 'submit' );
		say "</span>";
		say $q->endform;
		say "<div style=\"clear:both;padding-top:1em\"><p><a href=\"$self->{'system'}->{'script_name'}"
		  . "?db=$self->{'instance'}\">Back to main page</a></p></div>";
		say "</div>";
	}
	return;
}

sub _get_id_fields {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $idfield1 = $q->param('idfield1');
	my ( $metaset1, $metafield1 ) = $self->get_metaset_and_fieldname($idfield1);
	my $idfield2 = $q->param('idfield2');
	my ( $metaset2, $metafield2 ) = $self->get_metaset_and_fieldname($idfield2);
	return {
		field1     => $idfield1,
		metaset1   => $metaset1,
		metafield1 => $metafield1,
		field2     => $idfield2,
		metaset2   => $metaset2,
		metafield2 => $metafield2
	};
}

sub _get_match_joined_table {
	my ($self) = @_;
	my $id     = $self->_get_id_fields;
	my $table  = $self->{'system'}->{'view'};
	$table .= " LEFT JOIN meta_$id->{'metaset1'} ON $self->{'system'}->{'view'}.id = meta_$id->{'metaset1'}.isolate_id"
	  if defined $id->{'metaset1'};
	$table .= " LEFT JOIN meta_$id->{'metaset2'} ON $self->{'system'}->{'view'}.id = meta_$id->{'metaset2'}.isolate_id"
	  if defined $id->{'metaset2'};
	return $table;
}

sub _get_field_and_match_joined_table {
	my ( $self, $field ) = @_;
	my $table = $self->_get_match_joined_table;
	my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
	if ( defined $metaset && $table !~ /meta_$metaset / ) {
		$table .= " LEFT JOIN meta_$metaset ON $self->{'system'}->{'view'}.id=meta_$metaset.isolate_id";
	}
	return $table;
}

sub _get_match_criteria {
	my ($self) = @_;
	my $id = $self->_get_id_fields;
	my $match = ( defined $id->{'metaset1'} ? "meta_$id->{'metaset1'}.$id->{'metafield1'}" : $id->{'field1'} ) . "=?";
	$match .= " AND " . ( defined $id->{'metaset2'} ? "meta_$id->{'metaset2'}.$id->{'metafield2'}" : $id->{'field2'} ) . "=?"
	  if $id->{'field2'} ne '<none>';
	return $match;
}

sub _check {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $data   = $q->param('data');
	my @rows = split /\n/, $data;
	if ( @rows < 2 ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Nothing entered.  Make sure you include a header line.</p>";
		say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchIsolateUpdate\">Back</a></p></div>";
		return;
	}
	if ( $q->param('idfield1') eq $q->param('idfield2') ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Please select different id fields.<p></div>";
		return;
	}
	my $buffer = "<div class=\"box\" id=\"resultstable\">\n";
	my $id     = $self->_get_id_fields;
	$buffer .= "<p>The following changes will be made to the database.  Please check that this is what you intend and "
	  . "then press 'Submit'.  If you do not wish to make these changes, press your browser's back button.</p>\n";
	my $extraheader = $id->{'field2'} ne '<none>' ? "<th>$id->{'field2'}</th>" : '';
	$buffer .= "<table class=\"resultstable\"><tr><th>Transaction</th><th>$id->{'field1'}</th>$extraheader<th>Field</th>"
	  . "<th>New value</th><th>Value currently in database</th><th>Action</th></tr>\n";
	my $i = 0;
	my ( @id, @id2, @field, @value, @update );
	my $td          = 1;
	my $match_table = $self->_get_match_joined_table;
	my $match       = $self->_get_match_criteria;
	my $qry         = "SELECT COUNT(*) FROM $match_table WHERE $match";
	my $sql         = $self->{'db'}->prepare($qry);
	$qry =~ s/COUNT\(\*\)/id/;
	my $sql_id     = $self->{'db'}->prepare($qry);
	my $prefix     = BIGSdb::Utils::get_random();
	my $file       = "$self->{'config'}->{'secure_tmp_dir'}/$prefix.txt";
	my $table_rows = 0;

	foreach my $row (@rows) {
		my @cols = split /\t/, $row;
		next if @cols < 3;
		if ( $id->{'field2'} eq '<none>' ) {
			( $id[$i], $field[$i], $value[$i] ) = split /\t/, $row;
		} else {
			( $id[$i], $id2[$i], $field[$i], $value[$i] ) = split /\t/, $row;
		}
		$id[$i] =~ s/%20/ /g;
		$id2[$i] ||= '';
		$id2[$i] =~ s/%20/ /g;
		$value[$i] =~ s/\s*$//g if defined $value[$i];
		my $displayvalue = $value[$i];
		my $badField     = 0;
		my $is_locus     = $self->{'datastore'}->is_locus( $field[$i] );

		if ( !( $self->{'xmlHandler'}->is_field( $field[$i] ) || $is_locus ) ) {
			$badField = 1;
		}
		$update[$i] = 0;
		my ( $oldvalue, $action );
		if ( $i && defined $value[$i] && $value[$i] ne '' ) {
			if ( !$badField ) {
				my $count;
				my @args;
				push @args, $id[$i];
				push @args, $id2[$i] if $id->{'field2'} ne '<none>';

				#check if allowed to edit
				my $error;
				eval { $sql_id->execute(@args) };
				if ($@) {
					if ( $@ =~ /integer/ ) {
						say "<div class=\"box\" id=\"statusbad\"><p>Your id field(s) contain text characters but the "
						  . "field can only contain integers.</p></div>";
						$logger->debug($@);
						return;
					}
				}
				my @not_allowed;
				while ( my ($id) = $sql_id->fetchrow_array ) {
					if ( !$self->is_allowed_to_view_isolate($id) ) {
						push @not_allowed, $id;
					}
				}
				if (@not_allowed) {
					local $" = ', ';
					say "<div class=\"box\" id=\"statusbad\"><p>You are not allowed to edit the following isolate "
					  . "records: @not_allowed.</p></div>";
					return;
				}

				#Check if id exists
				eval {
					$sql->execute(@args);
					($count) = $sql->fetchrow_array;
				};
				if ( $@ || $count == 0 ) {
					$oldvalue = "<span class=\"statusbad\">no editable record with $id->{'field1'}='$id[$i]'";
					$oldvalue .= " and $id->{'field2'}='$id2[$i]'" if $id->{'field2'} ne '<none>';
					$oldvalue .= "</span>";
					$action = "<span class=\"statusbad\">no action</span>";
				} elsif ( $count > 1 ) {
					$oldvalue = "<span class=\"statusbad\">duplicate records with $id->{'field1'}='$id[$i]'";
					$oldvalue .= " and $id->{'field2'}='$id2[$i]'" if $id->{'field2'} ne '<none>';
					$oldvalue .= "</span>";
					$action = "<span class=\"statusbad\">no action</span>";
				} else {
					my $qry;
					my @args;
					my $table = $self->_get_field_and_match_joined_table( $field[$i] );
					if ($is_locus) {
						$qry = "SELECT allele_id FROM allele_designations LEFT JOIN $table ON "
						  . "$self->{'system'}->{'view'}.id=allele_designations.isolate_id WHERE locus=? AND $match";
						push @args, $field[$i];
					} else {
						my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname( $field[$i] );
						$qry = "SELECT " . ( $metafield // $field[$i] ) . " FROM $table WHERE $match";
					}
					my $sql2 = $self->{'db'}->prepare($qry);
					push @args, $id[$i];
					push @args, $id2[$i] if $id->{'field2'} ne '<none>';
					eval { $sql2->execute(@args) };
					$logger->error($@) if $@;
					$oldvalue = $sql2->fetchrow_array;
					if (   !defined $oldvalue
						|| $oldvalue eq ''
						|| $q->param('overwrite') )
					{
						$oldvalue = "&lt;blank&gt;"
						  if !defined $oldvalue || $oldvalue eq '';
						my $problem = $self->is_field_bad( $self->{'system'}->{'view'}, $field[$i], $value[$i], 'update' );
						if ($is_locus) {
							my $locus_info = $self->{'datastore'}->get_locus_info( $field[$i] );
							if ( $locus_info->{'allele_id_format'} eq 'integer' && !BIGSdb::Utils::is_int( $value[$i] ) ) {
								$problem = "invalid allele id (must be an integer)";
							}
						}
						if ($problem) {
							$action = "<span class=\"statusbad\">no action - $problem</span>";
						} else {
							if ( $value[$i] eq $oldvalue || ($value[$i] eq '<blank>' && $oldvalue eq '&lt;blank&gt;') ) {
								$action = "<span class=\"statusbad\">no action - new value unchanged</span>";
								$update[$i] = 0;
							} else {
								$action = "<span class=\"statusgood\">update field with new value</span>";
								$update[$i] = 1;
							}
						}
					} else {
						$action = "<span class=\"statusbad\">no action - value already in db</span>";
					}
				}
			} else {
				$oldvalue = "<span class=\"statusbad\">field not recognised</span>";
				$action   = "<span class=\"statusbad\">no action</span>";
			}
			$displayvalue =~ s/<blank>/&lt;blank&gt;/;
			if ( $id->{'field2'} ne '<none>' ) {
				$buffer .= "<tr class=\"td$td\"><td>$i</td><td>$id[$i]</td><td>$id2[$i]</td><td>$field[$i]</td>"
				  . "<td>$displayvalue</td><td>$oldvalue</td><td>$action</td></tr>\n";
			} else {
				$buffer .= "<tr class=\"td$td\"><td>$i</td><td>$id[$i]</td><td>$field[$i]</td><td>$displayvalue</td>"
				  . "<td>$oldvalue</td><td>$action</td></tr>";
			}
			$table_rows++;
			$td = $td == 1 ? 2 : 1;
		}
		$value[$i] =~ s/(<blank>|null)// if defined $value[$i];
		$i++;
	}
	if ($table_rows) {
		say $buffer;
		say "</table><p />";
		open( my $fh, '>', $file ) or $logger->error("Can't open temp file $file for writing");
		foreach my $i ( 0 .. @rows - 1 ) {
			if ( $update[$i] ) {
				say $fh "$id[$i]\t$id2[$i]\t$field[$i]\t$value[$i]";
			}
		}
		close $fh;
		say $q->start_form;
		$q->param( 'idfield1', $id->{'field1'} );
		$q->param( 'idfield2', $id->{'field2'} );
		$q->param( 'update',   1 );
		$q->param( 'file',     "$prefix.txt" );
		say $q->hidden($_) foreach qw (db page idfield1 idfield2 update file);
		say $q->submit( -label => 'Submit', -class => 'submit' );
		say $q->endform;
	} else {
		say "<div class=\"box\" id=\"statusbad\"><p>No valid values to update.</p>";
	}
	say "<p /><p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back to main page</a></p>\n</div>";
	return;
}

sub _update {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $id     = $self->_get_id_fields;
	my $file   = $q->param('file');
	my $transaction;
	my $i = 1;
	open( my $fh, '<', "$self->{'config'}->{'secure_tmp_dir'}/$file" ) or $logger->error("Can't open $file for reading");
	while ( my $line = <$fh> ) {
		chomp $line;
		my @record = split /\t/, $line;
		$transaction->{$i}->{'id'}    = $record[0];
		$transaction->{$i}->{'id2'}   = $record[1];
		$transaction->{$i}->{'field'} = $record[2];
		$transaction->{$i}->{'value'} = $record[3];
		$i++;
	}
	close $fh;
	say "<div class=\"box\" id=\"resultsheader\">";
	say "<h2>Updating database ...</h2>";
	my $nochange     = 1;
	my $curator_id   = $self->get_curator_id;
	my $curator_name = $self->get_curator_name;
	say "User: $curator_name<br />";
	my $datestamp = $self->get_datestamp;
	say "Datestamp: $datestamp<br />";
	my $tablebuffer;
	my $td          = 1;
	my $match_table = $self->_get_match_joined_table;
	my $match       = $self->_get_match_criteria;

	foreach my $i ( sort { $a <=> $b } keys %$transaction ) {
		my ( $id1, $id2, $field, $value ) =
		  ( $transaction->{$i}->{'id'}, $transaction->{$i}->{'id2'}, $transaction->{$i}->{'field'}, $transaction->{$i}->{'value'} );
		my ( $isolate_id, $old_value );
		$nochange = 0;
		my ( $qry, $qry2 );
		my $is_locus = $self->{'datastore'}->is_locus($field);
		my ( @args, @args2 );
		if ($is_locus) {
			my @id_args;
			my $id_qry = "SELECT $self->{'system'}->{'view'}.id FROM $match_table WHERE $match";
			push @id_args, $id1;
			push @id_args, $id2 if $id->{'field2'} ne '<none>';
			my $sql_id = $self->{'db'}->prepare($id_qry);
			eval { $sql_id->execute(@id_args) };
			$logger->error($@) if $@;
			($isolate_id) = $sql_id->fetchrow_array;

			#if existing designation set, demote it to pending
			my $existing_ref = $self->{'datastore'}->get_allele_designation( $isolate_id, $field );
			if ( ref $existing_ref eq 'HASH' ) {
				$old_value = $existing_ref->{'allele_id'};

				#delete existing pending designations with same allele_id
				my $pending_designations = $self->{'datastore'}->get_pending_allele_designations( $isolate_id, $field );
				foreach (@$pending_designations) {
					if (   $_->{'allele_id'} eq $existing_ref->{'allele_id'}
						&& $_->{'sender'} eq $existing_ref->{'sender'}
						&& $_->{'method'} eq 'manual' )
					{
						my $delete_sql =
						  $self->{'db'}->prepare("DELETE FROM pending_allele_designations WHERE isolate_id=? and locus=? AND allele_id=?");
						eval { $delete_sql->execute( $isolate_id, $field, $value ) };
						$logger->error($@) if $@;
					}
				}
				my $delete_sql = $self->{'db'}->prepare("DELETE FROM allele_designations WHERE isolate_id=? and locus=?");
				eval { $delete_sql->execute( $isolate_id, $field ) };
				$logger->error($@) if $@;
			}
			my $isolate_ref =
			  $self->{'datastore'}->run_simple_query( "SELECT sender FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id );
			$qry = "INSERT INTO allele_designations (isolate_id,locus,allele_id,sender,status,method,curator,date_entered,datestamp) "
			  . "VALUES (?,?,?,?,?,?,?,?,?)";
			push @args, ( $isolate_id, $field, $value, $isolate_ref->[0], 'confirmed', 'manual', $curator_id, 'now', 'now' );

			#delete from pending if it matches the new designation
			$qry2 .= ";DELETE FROM pending_allele_designations WHERE isolate_id=? AND locus=? AND allele_id=? AND sender=? AND method=?";
			push @args2, ( $isolate_id, $field, $value, $isolate_ref->[0], 'manual' );
		} else {
			my @id_args = ($id1);
			push @id_args, $id2 if $id->{'field2'} ne '<none>';
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			push @args, ( ($value // '') eq '' ? undef : $value );
			if ( defined $metaset ) {
				my $record_exists = $self->{'datastore'}->run_simple_query(
"SELECT EXISTS(SELECT * FROM meta_$metaset WHERE isolate_id IN (SELECT $self->{'system'}->{'view'}.id FROM $match_table WHERE $match))",
					@id_args
				)->[0];
				$isolate_id =
				  $self->{'datastore'}->run_simple_query( "SELECT $self->{'system'}->{'view'}.id FROM $match_table WHERE $match", @id_args )
				  ->[0];
				if ($record_exists) {
					$qry = "UPDATE meta_$metaset SET $metafield=? WHERE isolate_id=?";
				} else {
					$qry = "INSERT INTO meta_$metaset VALUES SET ($metafield, $isolate_id) = (?,?)";
				}
				push @args, $isolate_id;
				my $old_value_ref =
				  $self->{'datastore'}->run_simple_query( "SELECT $metafield FROM meta_$metaset WHERE isolate_id=?", $isolate_id );
				$old_value = ref $old_value_ref eq 'ARRAY' ? $old_value_ref->[0] : undef;
			} else {
				$qry = "UPDATE isolates SET $field=?,datestamp=?,curator=? WHERE id IN (SELECT $self->{'system'}->{'view'}.id "
				  . "FROM $match_table WHERE $match)";
				push @args, ( 'now', $curator_id, @id_args );
				my $id_qry = $qry;
				$id_qry =~ s/UPDATE isolates .*? WHERE/SELECT id,$field FROM isolates WHERE/;
				my $sql_id = $self->{'db'}->prepare($id_qry);
				eval { $sql_id->execute(@id_args) };
				$logger->error($@) if $@;
				( $isolate_id, $old_value ) = $sql_id->fetchrow_array;
			}
		}
		$tablebuffer .= "<tr class=\"td$td\"><td>$id->{'field1'}='$id1'";
		$tablebuffer .= " AND $id->{'field2'}='$id2'" if $id->{'field2'} ne '<none>';
		$value //= '&lt;blank&gt;';
		$tablebuffer .= "</td><td>$field</td><td>$value</td>";
		my $update_sql = $self->{'db'}->prepare($qry);
		eval {
			$update_sql->execute(@args);
			if ($qry2) {
				my $delete_sql = $self->{'db'}->prepare($qry2);
				$delete_sql->execute(@args2);
			}
		};
		if ($@) {
			$logger->error($@);
			$tablebuffer .= "<td class=\"statusbad\">can't update!</td></tr>\n";
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
			$tablebuffer .= "<td class=\"statusgood\">done!</td></tr>\n";
			$old_value //= '';
			$value = '' if $value eq '&lt;blank&gt;';
			$self->update_history( $isolate_id, "$field: '$old_value' -> '$value'" ) if $old_value ne $value;
		}
		$td = $td == 1 ? 2 : 1;
	}
	if ($nochange) {
		say "<p>No changes to be made.</p>";
	} else {
		say "<p /><table class=\"resultstable\"><tr><th>Condition</th><th>Field</th><th>New value</th>"
		  . "<th>Status</th></tr>$tablebuffer</table>";
	}
	say "<p /><p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back to main page</a></p>\n</div>";
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Batch Isolate Update - $desc";
}
1;
