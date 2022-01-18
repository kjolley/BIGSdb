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
package BIGSdb::CurateBatchIsolateUpdatePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use BIGSdb::Utils;
use BIGSdb::Constants qw(:interface);
use List::MoreUtils qw(any uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/curator_guide/0110_batch_updating_isolates.html";
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Batch isolate update</h1>);
	if ( !$self->can_modify_table('isolates') || !$self->can_modify_table('allele_designations') ) {
		$self->print_bad_status(
			{
				message => q(Your user account is not allowed to update either )
				  . q(isolate records or allele designations.)
			}
		);
		return;
	}
	if ( $q->param('update') ) {
		$self->_update;
	} elsif ( $q->param('data') ) {
		foreach my $param (qw (idfield1 idfield2)) {
			if ( !$self->{'xmlHandler'}->is_field( scalar $q->param($param) ) && $q->param($param) ne '<none>' ) {
				$self->print_bad_status(
					{ message => q(Invalid selection field.), navbar => 1, back_page => 'batchIsolateUpdate' } );
				return;
			}
		}
		$self->_check;
	} else {
		$self->_print_interface;
	}
	return;
}

sub _print_interface {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print <<"HTML";
<div class="box" id="queryform">
<p>This page allows you to batch update provenance fields or allele designations for multiple isolates.</p>
<ul><li>  The first line, containing column headings, will be ignored.</li>
<li> The first column should be the isolate id (or unique field that you are selecting isolates on).  If a 
secondary selection field is used (so that together the combination of primary and secondary fields are unique), 
this should be entered in the second column.</li>
<li>The next column should contain the field/locus name and then the 
final column should contain the value to be entered, e.g.<br />
<pre>
id	field	value
2	country	USA
2	abcZ	5
</pre>
</li>
<li> The columns should be separated by tabs. Any other columns will be ignored.</li>
<li> If you wish to remove a field value, enter <em>&lt;blank&gt;</em> or <em>null</em> as the value.</li></ul>
<p>Please enter the field(s) that you are selecting isolates on.  Values used must be unique within this field or 
combination of fields, i.e. only one isolate has the value(s) used.  Usually the database id will be used.</p>
HTML
	my $set_id = $self->get_set_id;
	my $fields = $self->{'xmlHandler'}->get_field_list;
	say $q->start_form;
	say $q->hidden($_) foreach qw (db page);
	say q(<fieldset style="float:left"><legend>Please paste in your data below:</legend>);
	say $q->textarea( -name => 'data', -rows => 15, -columns => 40 );
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Options</legend>);
	say q(<ul><li><label for="idfield1" class="filter">Primary selection field: </label>);
	say $q->popup_menu( -name => 'idfield1', -id => 'idfield1', -values => $fields );
	say q(</li><li><label for="idfield2" class="filter">Optional selection field: </label>);
	unshift @$fields, '<none>';
	say $q->popup_menu( -name => 'idfield2', -id => 'idfield2', -values => $fields );
	say q(</li><li>);
	say $q->checkbox( -name => 'overwrite', -label => 'Update existing values', -checked => 0 );
	say q(</li></ul></fieldset>);
	say q(<fieldset style="float:left"><legend>Allele designations</legend>);
	say $q->radio_group(
		-name      => 'designations',
		-values    => [qw(add replace)],
		-labels    => { add => 'Add additional new designation', replace => 'Replace existing designations' },
		-linebreak => 'true'
	);
	say q(</fieldset>);
	my $multi_fields = $self->{'xmlHandler'}->get_field_list( { multivalue_only => 1 } );

	if (@$multi_fields) {
		say q(<fieldset style="float:left"><legend>Multi-value fields</legend>);
		say $q->radio_group(
			-name      => 'multi_value',
			-values    => [qw(add replace)],
			-labels    => { add => 'Add additional value', replace => 'Replace existing values' },
			-linebreak => 'true'
		);
		say q(</fieldset>);
	}
	$self->print_action_fieldset;
	say $q->end_form;
	say q(</div>);
	return;
}

sub _get_id_fields {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $idfield1 = $q->param('idfield1');
	my $idfield2 = $q->param('idfield2');
	return {
		field1 => $idfield1,
		field2 => $idfield2,
	};
}

sub _get_match_criteria {
	my ($self) = @_;
	my $id     = $self->_get_id_fields;
	my $view   = $self->{'system'}->{'view'};
	my $match  = "$view.$id->{'field1'}=?";
	$match .= " AND $view.$id->{'field2'}=?" if $id->{'field2'} ne '<none>';
	return $match;
}

sub _failed_basic_checks {
	my ( $self, $rows ) = @_;
	if ( @$rows < 2 ) {
		$self->print_bad_status(
			{
				message   => q(Nothing entered. Make sure you include a header line.),
				navbar    => 1,
				back_page => 'batchIsolateUpdate'
			}
		);
		return 1;
	}
	my $q = $self->{'cgi'};
	if ( $q->param('idfield1') eq $q->param('idfield2') ) {
		$self->print_bad_status(
			{
				message   => q(Please select different id fields.),
				navbar    => 1,
				back_page => 'batchIsolateUpdate'
			}
		);
		return 1;
	}
	return;
}

sub _is_locus {
	my ( $self, $field ) = @_;
	my $set_id = $self->get_set_id;
	if ($set_id) {
		my $locus = $self->{'datastore'}->get_set_locus_real_id( $field, $set_id );
		if ( $self->{'datastore'}->is_locus_in_set( $locus, $set_id ) ) {
			$field = $locus;    #Map to real locus name if it is renamed in set.
			return 1;
		}
	} else {
		return $self->{'datastore'}->is_locus($field);
	}
	return;
}

sub _check_field_status {
	my ( $self, $field, $is_locus ) = @_;
	my $set_id = $self->get_set_id;
	my ( $bad_field, $not_allowed_field );
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	if ( !( $self->{'xmlHandler'}->is_field($field) || $self->{'datastore'}->is_eav_field($field) || $is_locus ) ) {
		$bad_field = 1;
	}
	my %not_allowed = map { $_ => 1 } qw(id date_entered datestamp curator);
	if ( $not_allowed{$field} ) {
		$not_allowed_field = 1;
	} elsif ( $field eq 'sender' && $user_info->{'status'} eq 'submitter' ) {
		$not_allowed_field = 1;
	} elsif ( $self->{'datastore'}->is_eav_field($field) ) {
		my $eav_field = $self->{'datastore'}->get_eav_field($field);
		$not_allowed_field = 1 if $eav_field->{'no_curate'};
	} else {
		my $att = $self->{'xmlHandler'}->get_field_attributes($field);
		$not_allowed_field = 1 if ( $att->{'no_curate'} // '' ) eq 'yes';
	}
	return ( $bad_field, $not_allowed_field );
}

sub _get_table_header {
	my ($self) = @_;
	my $id_fields = $self->_get_id_fields;
	my $extraheader = $id_fields->{'field2'} ne '<none>' ? "<th>$id_fields->{'field2'}</th>" : '';
	return
	    q(<table class="resultstable" style="margin-bottom:1em">)
	  . qq(<tr><th>Transaction</th><th>$id_fields->{'field1'}</th>$extraheader)
	  . qq(<th>Field</th><th>New value</th><th>Value(s) currently in database</th><th>Action</th></tr>\n);
}

sub _check {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $data   = $q->param('data');
	my @rows = split /\n/x, $data;
	return if $self->_failed_basic_checks( \@rows );
	my $id_fields = $self->_get_id_fields;
	my $i         = 0;
	my ( @id, @id2, @field, @value );
	my $td    = 1;
	my $match = $self->_get_match_criteria;
	my $qry   = "SELECT COUNT(*) FROM $self->{'system'}->{'view'} WHERE $match";
	my $sql   = $self->{'db'}->prepare($qry);
	$qry =~ s/COUNT\(\*\)/id/x;
	my $sql_id       = $self->{'db'}->prepare($qry);
	my $table_rows   = 0;
	my $update_rows  = [];
	my $table_buffer = q();

	foreach my $row (@rows) {
		my @cols = split /\t/x, $row;
		next if @cols < 3;
		if ( $id_fields->{'field2'} eq '<none>' ) {
			( $id[$i], $field[$i], $value[$i] ) = split /\t/x, $row;
		} else {
			( $id[$i], $id2[$i], $field[$i], $value[$i] ) = split /\t/x, $row;
		}
		$id[$i] =~ s/%20/ /gx;
		$id2[$i] //= q();
		$id2[$i] =~ s/%20/ /gx;
		$value[$i] =~ s/\s*$//gx if defined $value[$i];
		my $display_value = $value[$i];
		my $display_field = $field[$i];
		my $is_locus      = $self->_is_locus( $field[$i] );
		my $is_eav_field  = $self->{'datastore'}->is_eav_field( $field[$i] );
		my ( $bad_field, $not_allowed_field ) = $self->_check_field_status( $field[$i], $is_locus );
		my ( $old_value, $action );

		if ( $i && defined $value[$i] && $value[$i] ne '' ) {
			if ( !$bad_field && !$not_allowed_field ) {
				my $count;
				my @args;
				push @args, $id[$i];
				push @args, $id2[$i] if $id_fields->{'field2'} ne '<none>';

				#check invalid query
				eval { $sql_id->execute(@args) };
				if ($@) {
					$self->_display_error($@);
					return;
				}

				#Check if id exists
				eval {
					$sql->execute(@args);
					($count) = $sql->fetchrow_array;
				};
				if ( $@ || $count == 0 ) {
					$old_value = qq(<span class="statusbad">no editable record with $id_fields->{'field1'}='$id[$i]');
					$old_value .= qq( and $id_fields->{'field2'}='$id2[$i]') if $id_fields->{'field2'} ne '<none>';
					$old_value .= q(</span>);
					$action = q(<span class="statusbad">no action</span>);
				} elsif ( $count > 1 ) {
					$old_value = qq(<span class="statusbad">duplicate records with $id_fields->{'field1'}='$id[$i]');
					$old_value .= qq( and $id_fields->{'field2'}='$id2[$i]') if $id_fields->{'field2'} ne '<none>';
					$old_value .= q(</span>);
					$action = q(<span class="statusbad">no action</span>);
				} else {
					( $old_value, $action, my $update ) = $self->_check_field(
						{
							field        => \@field,
							i            => $i,
							is_locus     => $is_locus,
							is_eav_field => $is_eav_field,
							match        => $match,
							id           => \@id,
							id2          => \@id2,
							id_fields    => $id_fields,
							value        => \@value,
						}
					);
					$value[$i] =~ s/(<blank>|null)//x if defined $value[$i];
					push @$update_rows, qq($id[$i]\t$id2[$i]\t$field[$i]\t$value[$i]) if $update;
				}
			} else {
				$old_value =
				  $not_allowed_field
				  ? q(<span class="statusbad">not allowed to modify</span>)
				  : q(<span class="statusbad">field not recognised</span>);
				$action = q(<span class="statusbad">no action</span>);
			}
			$display_value =~ s/<blank>/&lt;blank&gt;/x;
			if ( $id_fields->{'field2'} ne '<none>' ) {
				$table_buffer .=
				    qq(<tr class="td$td"><td>$i</td><td>$id[$i]</td><td>$id2[$i]</td><td>$display_field</td>)
				  . qq(<td>$display_value</td><td>$old_value</td><td>$action</td></tr>\n);
			} else {
				$table_buffer .=
				    qq(<tr class="td$td"><td>$i</td><td>$id[$i]</td><td>$display_field</td><td>$display_value</td>)
				  . qq(<td>$old_value</td><td>$action</td></tr>);
			}
			$table_rows++;
			$td = $td == 1 ? 2 : 1;
		}
		$i++;
	}
	if ($table_rows) {
		if ( !@$update_rows ) {
			$self->print_bad_status(
				{
					message => q(No valid changes to be made.),
				}
			);
		}
		say qq(<div class="box" id="resultstable">\n);
		if (@$update_rows) {
			say q(<p>The following changes will be made to the database.  Please check that this is what )
			  . q(you intend and then press 'Update'.  If you do not wish to make these changes, press your )
			  . q(browser's back button.</p>);
		}
		say $self->_get_table_header;
		say $table_buffer;
		say q(</table>);
		$self->_display_update_form( $update_rows, $id_fields );
		say q(</div>);
	} else {
		$self->print_bad_status( { message => q(No valid values to update.) } );
		return;
	}
	return;
}

sub _display_update_form {
	my ( $self, $update_rows, $id_fields ) = @_;
	my $q = $self->{'cgi'};
	if (@$update_rows) {
		my $prefix = BIGSdb::Utils::get_random();
		my $file   = "$self->{'config'}->{'secure_tmp_dir'}/$prefix.txt";
		open( my $fh, '>:encoding(utf8)', $file )
		  or $logger->error("Can't open temp file $file for writing");
		local $" = qq(\n);
		say $fh qq(@$update_rows);
		close $fh;
		say $q->start_form;
		$q->param( idfield1 => $id_fields->{'field1'} );
		$q->param( idfield2 => $id_fields->{'field2'} );
		$q->param( update   => 1 );
		$q->param( file     => "$prefix.txt" );
		say $q->hidden($_) foreach qw (db page idfield1 idfield2 update file designations multi_value);
		$self->print_action_fieldset( { no_reset => 1, submit_label => 'Update' } );
		say $q->end_form;
	}
	return;
}

sub _display_error {
	my ( $self, $err ) = @_;
	foreach my $type (qw (integer date float)) {
		if ( $err =~ /$type/x ) {
			$self->print_bad_status(
				{
					message => q(Your id field(s) contain text characters but the )
					  . qq(field can only contain ${type}s.),
				}
			);
			$self->_print_interface;
			return;
		}
	}
	return;
}

sub _get_old_values {
	my ( $self, $args ) = @_;
	my ( $field, $i, $is_locus, $is_eav_field, $match, $id, $id2, $id_fields, $value ) =
	  @{$args}{qw(field i is_locus is_eav_field match id id2 id_fields value)};
	my $qry;
	my $qry_args = [];
	if ($is_locus) {
		$qry = "SELECT allele_id FROM allele_designations LEFT JOIN $self->{'system'}->{'view'} ON "
		  . "$self->{'system'}->{'view'}.id=allele_designations.isolate_id WHERE locus=? AND $match";
		push @$qry_args, $field->[$i];
	} elsif ($is_eav_field) {
		my $eav_table = $self->{'datastore'}->get_eav_field_table( $field->[$i] );
		$qry =
		    "SELECT value FROM $eav_table JOIN $self->{'system'}->{'view'} ON "
		  . "$eav_table.isolate_id=$self->{'system'}->{'view'}.id "
		  . "WHERE field=? AND $match";
		push @$qry_args, $field->[$i];
	} else {
		$qry = "SELECT $field->[$i] FROM $self->{'system'}->{'view'} WHERE $match";
		if ( !$self->{'cache'}->{'attributes'}->{ $field->[$i] } ) {
			my $att = $self->{'xmlHandler'}->get_field_attributes( $field->[$i] );
			$self->{'cache'}->{'attributes'}->{ $field->[$i] } = $att;
			if ( ( $att->{'multiple'} // q() ) eq 'yes' && ( $att->{'optlist'} // q() ) eq 'yes' ) {
				$self->{'cache'}->{'optlist'}->{ $field->[$i] } =
				  $self->{'xmlHandler'}->get_field_option_list( $field->[$i] );
			}
		}
	}
	push @$qry_args, $id->[$i];
	push @$qry_args, $id2->[$i] if $id_fields->{'field2'} ne '<none>';
	my $old_values = $self->{'datastore'}->run_query( $qry, $qry_args, { fetch => 'col_arrayref' } );
	if ( ( $self->{'cache'}->{'attributes'}->{ $field->[$i] }->{'multiple'} // q() ) eq 'yes' ) {
		if ( ( $self->{'cache'}->{'attributes'}->{ $field->[$i] }->{'optlist'} // q() ) eq 'yes' ) {
			$old_values =
			  BIGSdb::Utils::arbitrary_order_list( $self->{'cache'}->{'optlist'}->{ $field->[$i] }, $old_values->[0] );
		} else {
			return [] if !defined $old_values->[0];
			@$old_values =
			  $self->{'cache'}->{'attributes'}->{ $field->[$i] }->{'type'} eq 'text'
			  ? sort { $a cmp $b } @{ $old_values->[0] }
			  : sort { $a <=> $b } @{ $old_values->[0] };
		}
	} else {
		no warnings 'numeric';
		@$old_values = sort { $a <=> $b || $a cmp $b } @$old_values;
	}
	return $old_values;
}

sub _check_field {
	my ( $self, $args ) = @_;
	my ( $field, $i, $is_locus, $is_eav_field, $match, $id, $id2, $id_fields, $value ) =
	  @{$args}{qw(field i is_locus is_eav_field match id id2 id_fields value)};
	my ( $old_value, $action );
	my $q = $self->{'cgi'};
	my @args;
	my $qry;
	my $set_id      = $self->get_set_id;
	my $will_update = 0;
	my $old_values  = $self->_get_old_values($args);
	my %multivalue_fields =
	  map { $_ => 1 } @{ $self->{'xmlHandler'}->get_field_list( { multivalue_only => 1 } ) };
	local $" = '; ';

	#Replace undef with empty string in list
	map { $_ //= q() } @$old_values;    ##no critic (ProhibitMutatingListFunctions)
	$old_value = qq(@$old_values);
	if ( !@$old_values || @$old_values == 1 && $old_values->[0] eq q() || $q->param('overwrite') ) {
		my $problem =
		  $self->{'submissionHandler'}->is_field_bad( 'isolates', $field->[$i], $value->[$i], 'update', $set_id );
		undef $problem
		  if ( $self->{'cache'}->{'attributes'}->{ $field->[$i] }->{'required'} // q() ) ne 'yes'
		  && ( $value->[$i] eq '<blank>' || $value->[$i] eq 'null' );
		if ($is_locus) {
			my $locus_info = $self->{'datastore'}->get_locus_info( $field->[$i] );
			if ( $locus_info->{'allele_id_format'} eq 'integer'
				&& !BIGSdb::Utils::is_int( $value->[$i] ) )
			{
				$problem = q(invalid allele id (must be an integer));
			}
		}
		if ($problem) {
			$action = qq(<span class="statusbad">no action - $problem</span>);
		} else {
			if (   ( $value->[$i] eq '<blank>' || $value->[$i] eq 'null' )
				&& $multivalue_fields{ $field->[$i] }
				&& $q->param('multi_value') eq 'add' )
			{
				$action =
q(<span class="statusbad">no action - cannot add a null value (set to replace existing values instead)</span>);
			} elsif ( $self->_are_values_the_same( $field->[$i], $value->[$i], $old_values ) ) {
				if ($is_locus) {
					$action = q(<span class="statusbad">no action - designation already set</span>);
				} else {
					$action = q(<span class="statusbad">no action - new value unchanged</span>);
				}
			} else {
				if ($is_locus) {
					if ( $q->param('designations') eq 'add' ) {
						$action = q(<span class="statusgood">add new designation</span>);
					} else {
						$action = q(<span class="statusgood">replace designation(s)</span>);
					}
				} elsif ( $multivalue_fields{ $field->[$i] } ) {
					if ( $q->param('multi_value') eq 'add' ) {
						$action = q(<span class="statusgood">add new value</span>);
					} else {
						$action = q(<span class="statusgood">replace value(s)</span>);
					}
				} else {
					$action = q(<span class="statusgood">update field with new value</span>);
				}
				$will_update = 1;
			}
		}
		$old_value = q(&lt;blank&gt;) if !@$old_values;
	} else {
		$action = q(<span class="statusbad">no action - value already in db</span>);
	}
	return ( $old_value, $action, $will_update );
}

sub _are_values_the_same {
	my ( $self, $field, $new, $old ) = @_;
	my $q   = $self->{'cgi'};
	my $att = $self->{'cache'}->{'attributes'}->{$field};
	if ( ( $att->{'multiple'} // q() ) eq 'yes' ) {
		$new = [ split /;/x, $new ];
		s/^\s+|\s+$//gx foreach @$new;
		@$new = uniq @$new;
	} else {
		$new =~ s/^\s+|\s+$//gx;
	}
	my %old = map { $_ => 1 } @$old;
	if ( ref $new ) {
		return 1 if ( $new->[0] eq '<blank>' || $new->[0] eq 'null' ) && !@$old;
		if ( $q->param('multi_value') eq 'add' ) {
			foreach my $new_value (@$new) {
				return 1 if $old{$new_value};
			}
		} else {
			return 0 if scalar @$new != scalar @$old;
			foreach my $new_value (@$new) {
				return 0 if !$old{$new_value};
			}
			my %new = map { $_ => 1 } @$new;
			foreach my $old_value (@$old) {
				return 0 if !$new{$old_value};
			}
			return 1;
		}
	} else {
		return 1 if ( $new eq '<blank>' || $new eq 'null' ) && !@$old;
		return 0 if !$old{$new};
		return 1 if $new eq $old->[0] && @$old == 1;
	}
	return;
}

sub _update {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $id     = $self->_get_id_fields;
	my $file   = $q->param('file');
	my @records;
	open( my $fh, '<:encoding(utf8)', "$self->{'config'}->{'secure_tmp_dir'}/$file" )
	  or $logger->error("Can't open $file for reading");
	while ( my $line = <$fh> ) {
		chomp $line;
		my @record = split /\t/x, $line;
		push @records, \@record;
	}
	close $fh;
	my $nochange    = 1;
	my $curator_id  = $self->get_curator_id;
	my $tablebuffer = q();
	my $td          = 1;
	my $match       = $self->_get_match_criteria;
	my $view        = $self->{'system'}->{'view'};
	my %multivalue_fields =
	  map { $_ => 1 } @{ $self->{'xmlHandler'}->get_field_list( { multivalue_only => 1 } ) };
	my $error;
	my ( $good, $bad ) = ( GOOD, BAD );
	my $validation_failures = {};
	my @history;

	foreach my $record (@records) {
		last if $error;
		my ( $id1, $id2, $field, $value ) = @$record;
		my $old_value;
		$nochange = 0;
		my ( $qry, $delete_qry );
		my $is_locus             = $self->{'datastore'}->is_locus($field);
		my $is_eav_field         = $self->{'datastore'}->is_eav_field($field);
		my $deleted_designations = [];
		my $args                 = [];
		my $delete_args          = [];
		my @id_args              = ($id1);
		push @id_args, $id2 if $id->{'field2'} ne '<none>';
		my $isolate_id = $self->{'datastore'}->run_query( "SELECT $view.id FROM $view WHERE $match", \@id_args );
		my $no_history;

		if ($is_locus) {
			my $data = $self->_prepare_allele_designation_update( $isolate_id, $field, $value, $deleted_designations );
			( $args, $qry, $delete_qry, $delete_args ) = @{$data}{qw(args qry delete_qry delete_args)};
		} elsif ($is_eav_field) {
			my $data = $self->_prepare_eav_update( $isolate_id, $field, $value );
			( $args, $qry, $old_value ) = @{$data}{qw(args qry old_value)};
		} else {
			my $att = $self->{'xmlHandler'}->get_field_attributes($field);
			$no_history = 1 if ( $att->{'curate_only'} // q() ) eq 'yes';
			if ( ( $att->{'multiple'} // q() ) eq 'yes' && defined $value && scalar $q->param('multi_value') ne 'add' )
			{
				$value = [ split /;/x, $value ];
				s/^\s+|\s+$//gx foreach @$value;
				@$value = uniq @$value;
			}
			push @$args, ( ( $value // q() ) eq q() || ( ref $value && !@$value ) ? undef : $value );
			if ( $multivalue_fields{$field} && scalar $q->param('multi_value') eq 'add' ) {
				$qry =
				    "UPDATE isolates SET ($field,datestamp,curator)=(ARRAY_APPEND($field,?),?,?) WHERE id IN "
				  . "(SELECT $view.id FROM $view WHERE $match)";
			} else {
				$qry =
				    "UPDATE isolates SET ($field,datestamp,curator)=(?,?,?) WHERE id IN "
				  . "(SELECT $view.id FROM $view WHERE $match)";
			}
			push @$args, ( 'now', $curator_id, @id_args );
			my $id_qry = $qry;
			$id_qry =~ s/UPDATE\ isolates\ .*?\ WHERE/SELECT id,$field FROM isolates WHERE/x;
			( $isolate_id, $old_value ) = $self->{'datastore'}->run_query( $id_qry, \@id_args );
		}
		$tablebuffer .= qq(<tr class="td$td"><td>$id->{'field1'}='$id1');
		$tablebuffer .= qq( AND $id->{'field2'}='$id2') if $id->{'field2'} ne '<none>';
		$value //= q(&lt;blank&gt;);
		$value = $self->_list_to_string($value);
		$tablebuffer .= qq(</td><td>$field</td><td>$value</td>);
		eval {
			if ($delete_qry) {
				$self->{'db'}->do( $delete_qry, undef, @$delete_args );
			}
			$self->{'db'}->do( $qry, undef, @$args );
		};
		if ($@) {
			if ( $@ =~ /duplicate/x ) {
				$tablebuffer .= qq(<td class="statusbad">$bad [duplicate]</td><td></td></tr>\n);
			} else {
				$tablebuffer .= qq(<td class="statusbad">$bad [unspecified error - check logs]</td><td></td></tr>\n);
			}
			$error = 1;
		} else {
			my $failures = $self->_run_validation_checks($isolate_id);
			if ( @$failures && @$failures > keys %{ $validation_failures->{$isolate_id} } ) {
				my @this_failure;

				#Only show new validation failure
				foreach my $failure (@$failures) {
					if ( !$validation_failures->{$isolate_id}->{$failure} ) {
						push @this_failure, $failure;
						$validation_failures->{$isolate_id}->{$failure} = 1;
					}
				}
				local $" = q(<br />);
				$tablebuffer .=
				    qq(<td>$bad</td><td class="statusbad" style="text-align:left">)
				  . qq(Failed validation - cannot update: @this_failure</td></tr>\n);
				$error = 1;
			} else {
				$tablebuffer .= qq(<td class="statusgood">$good</td><td></td></tr>\n);
				$old_value //= '';
				$old_value = $self->_list_to_string($old_value);
				$value = '' if $value eq '&lt;blank&gt;';
				if ($is_locus) {
					if ( $q->param('designations') eq 'replace' ) {
						my $plural = @$deleted_designations == 1 ? '' : 's';
						local $" = ',';
						push @history,
						  {
							isolate_id => $isolate_id,
							action     => "$field: designation$plural '@$deleted_designations' deleted"
						  }
						  if @$deleted_designations;
					}
					push @history,
					  {
						isolate_id => $isolate_id,
						action     => "$field: new designation '$value'"
					  };
				} else {
					if ( $field eq 'id' ) {
						$isolate_id = $value;
					}
					if ( $old_value ne $value && !$no_history ) {
						if ( $multivalue_fields{$field} && scalar $q->param('multi_value') eq 'add' ) {
							push @history,
							  {
								isolate_id => $isolate_id,
								action     => "$field value added: '$value'"
							  };
						} else {
							push @history,
							  {
								isolate_id => $isolate_id,
								action     => "$field: '$old_value' -> '$value'"
							  };
						}
					}
				}
			}
		}
		$td = $td == 1 ? 2 : 1;
	}
	$self->{'submissionHandler'}->cleanup_validation_rules;
	if ($nochange) {
		$self->print_bad_status(
			{
				message => q(No changes to be made.),
				detail  => q(No changes have been made!),
			}
		);
	} else {
		if ($error) {
			$self->print_bad_status(
				{
					message => q(Database changes rolled back due to errors.),
					detail  => q(No changes have been made!),
				}
			);
			$self->{'db'}->rollback;
		} else {
			$self->print_good_status(
				{
					message => q(Database updated.)
				}
			);
			$self->{'db'}->commit;
			foreach my $update (@history) {
				$self->update_history( $update->{'isolate_id'}, $update->{'action'} );
			}
		}
		say q(<div class="box" id="resultstable">);
		say q(<h2>Updates</h2>);
		say q(<table class="resultstable" style="margin-bottom:1em"><tr><th>Condition</th><th>Field</th>)
		  . qq(<th>New value</th><th>Status</th><th>Comments</th></tr>$tablebuffer</table>);
		say q(</div>);
	}
	return;
}

sub _run_validation_checks {
	my ( $self, $isolate_id ) = @_;
	my $fields     = $self->{'xmlHandler'}->get_field_list;
	my $eav_fields = $self->{'datastore'}->get_eav_fieldnames;
	my $new_data   = {};
	my $prov_data =
	  $self->{'datastore'}
	  ->run_query( "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id, { fetch => 'row_hashref' } );
	foreach my $field (@$fields) {
		$new_data->{$field} = $prov_data->{ lc($field) };
	}
	foreach my $field (@$eav_fields) {
		$new_data->{$field} = $self->{'datastore'}->get_eav_field_value( $isolate_id, $field );
	}
	my $validation_failures = $self->{'submissionHandler'}->run_validation_checks($new_data);
	return $validation_failures;
}

sub _list_to_string {
	my ( $self, $value ) = @_;
	if ( ref $value ) {
		local $" = q(; );
		$value = qq(@$value);
	}
	return $value;
}

sub _prepare_allele_designation_update {
	my ( $self, $isolate_id, $field, $value, $deleted_designations ) = @_;
	my $view       = $self->{'system'}->{'view'};
	my $q          = $self->{'cgi'};
	my $curator_id = $self->get_curator_id;
	my $sender     = $self->{'datastore'}->run_query( "SELECT sender FROM $view WHERE id=?", $isolate_id );
	my $qry        = 'INSERT INTO allele_designations (isolate_id,locus,allele_id,sender,status,method,curator,'
	  . 'date_entered,datestamp) VALUES (?,?,?,?,?,?,?,?,?)';
	my $args = [ $isolate_id, $field, $value, $sender, 'confirmed', 'manual', $curator_id, 'now', 'now' ];
	my $delete_args = [];
	my $delete_qry;

	if ( $q->param('designations') eq 'replace' ) {

		#Prepare allele deletion query
		$delete_qry = 'DELETE FROM allele_designations WHERE (isolate_id,locus)=(?,?)';
		$delete_args = [ $isolate_id, $field ];

		#Determine which alleles will be deleted for reporting in history
		my $existing_designations = $self->{'datastore'}->get_allele_designations( $isolate_id, $field );
		foreach my $designation (@$existing_designations) {
			push @$deleted_designations, $designation->{'allele_id'} if $designation->{'allele_id'} ne $value;
		}
	}
	return { qry => $qry, args => $args, delete_qry => $delete_qry, delete_args => $delete_args };
}

sub _prepare_eav_update {
	my ( $self, $isolate_id, $field, $value ) = @_;
	my ( $qry, $old_value );
	my $args      = [];
	my $view      = $self->{'system'}->{'view'};
	my $eav_table = $self->{'datastore'}->get_eav_field_table($field);
	my $record_exists =
	  $self->{'datastore'}
	  ->run_query( "SELECT EXISTS(SELECT * FROM $eav_table WHERE (isolate_id,field)=(?,?))", [ $isolate_id, $field ] );
	if ($record_exists) {
		if ( $value eq q() ) {
			$qry = "DELETE FROM $eav_table WHERE (isolate_id,field)=(?,?)";
			@$args = ( $isolate_id, $field );
		} else {
			$qry = "UPDATE $eav_table SET value=? WHERE (isolate_id,field)=(?,?)";
			@$args = ( $value, $isolate_id, $field );
		}
	} else {
		$qry = "INSERT INTO $eav_table (isolate_id,field,value) VALUES (?,?,?)";
		@$args = ( $isolate_id, $field, $value );
	}
	$old_value =
	  $self->{'datastore'}
	  ->run_query( "SELECT value FROM $eav_table WHERE (isolate_id,field)=(?,?)", [ $isolate_id, $field ] );
	return { qry => $qry, args => $args, old_value => $old_value };
}

sub get_title {
	my ($self) = @_;
	return 'Batch Isolate Update';
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery jQuery.multiselect noCache);
	my $q = $self->{'cgi'};
	if ( $q->param('update') || $q->param('data') ) {
		$self->{'processing'} = 1;
	}
	$self->set_level1_breadcrumbs;
	return;
}
1;
