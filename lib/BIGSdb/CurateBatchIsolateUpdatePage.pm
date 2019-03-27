#Written by Keith Jolley
#Copyright (c) 2010-2018, University of Oxford
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
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/curator_guide.html#batch-updating-multiple-isolate-records";
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Batch isolate update</h1>);
	if ( !$self->can_modify_table('isolates') || !$self->can_modify_table('allele_designations') ) {
		$self->print_bad_status(
			{
				message => q(Your user account is not allowed to update either )
				  . q(isolate records or allele designations.),
				navbar => 1
			}
		);
		return;
	}
	if ( $q->param('update') ) {
		$self->_update;
	} elsif ( $q->param('data') ) {
		foreach my $param (qw (idfield1 idfield2)) {
			if ( !$self->{'xmlHandler'}->is_field( $q->param($param) ) && $q->param($param) ne '<none>' ) {
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
<pre style="font-size:1.2em">
id	field	value
2	country	USA
2	abcZ	5
</pre>
</li>
<li> The columns should be separated by tabs. Any other columns will be ignored.</li>
<li> If you wish to blank a field, enter '&lt;blank&gt;' as the value.</li></ul>
<p>Please enter the field(s) that you are selecting isolates on.  Values used must be unique within this field or 
combination of fields, i.e. only one isolate has the value(s) used.  Usually the database id will be used.</p>
HTML
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata( $set_id, { curate => 1 } );
	my $fields        = $self->{'xmlHandler'}->get_field_list($metadata_list);
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
	$self->print_action_fieldset;
	say $q->end_form;
	$self->print_navigation_bar;
	say q(</div>);
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
	if ( defined $metaset && $table !~ /meta_$metaset\ /x ) {
		$table .= " LEFT JOIN meta_$metaset ON $self->{'system'}->{'view'}.id=meta_$metaset.isolate_id";
	}
	return $table;
}

sub _get_match_criteria {
	my ($self) = @_;
	my $id     = $self->_get_id_fields;
	my $view   = $self->{'system'}->{'view'};
	my $match =
	  ( defined $id->{'metaset1'} ? "meta_$id->{'metaset1'}.$id->{'metafield1'}" : "$view.$id->{'field1'}" ) . '=?';
	$match .= ' AND '
	  . ( defined $id->{'metaset2'} ? "meta_$id->{'metaset2'}.$id->{'metafield2'}" : "$view.$id->{'field2'}" ) . '=?'
	  if $id->{'field2'} ne '<none>';
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
	my ( $self, $field, $i, $is_locus ) = @_;
	my $set_id = $self->get_set_id;
	my ( $bad_field, $not_allowed_field );
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	if (
		!(
			   $self->{'xmlHandler'}->is_field( $field->[$i] )
			|| $self->{'datastore'}->is_eav_field( $field->[$i] )
			|| $is_locus
		)
	  )
	{
		#Check if there is an extended metadata field
		my $metadata_list = $self->{'datastore'}->get_set_metadata( $set_id, { curate => 1 } );
		my $meta_fields = $self->{'xmlHandler'}->get_field_list( $metadata_list, { meta_fields_only => 1 } );
		my $field_is_metafield = 0;
		foreach my $meta_field (@$meta_fields) {
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($meta_field);
			if ( $metafield eq $field->[$i] ) {
				$field->[$i] = "meta_$metaset:$metafield";    #Map to real field name if it is renamed in set.
				$field_is_metafield = 1;
			}
		}
		$bad_field = 1 if !$field_is_metafield;
	} elsif ( $field->[$i] eq 'sender' && $user_info->{'status'} eq 'submitter' ) {
		$not_allowed_field = 1;
	} elsif ( $self->{'datastore'}->is_eav_field( $field->[$i] ) ) {
		my $eav_field = $self->{'datastore'}->get_eav_field( $field->[$i] );
		$not_allowed_field = 1 if $eav_field->{'no_curate'};
	} else {
		my $att = $self->{'xmlHandler'}->get_field_attributes( $field->[$i] );
		$not_allowed_field = 1 if ( $att->{'no_curate'} // '' ) eq 'yes';
	}
	return ( $bad_field, $not_allowed_field );
}

sub _get_html_header {
	my ($self) = @_;
	my $id_fields = $self->_get_id_fields;
	my $extraheader = $id_fields->{'field2'} ne '<none>' ? "<th>$id_fields->{'field2'}</th>" : '';
	return qq(<table class="resultstable"><tr><th>Transaction</th><th>$id_fields->{'field1'}</th>$extraheader)
	  . qq(<th>Field</th><th>New value</th><th>Value(s) currently in database</th><th>Action</th></tr>\n);
}

sub _check {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $data   = $q->param('data');
	my @rows = split /\n/x, $data;
	return if $self->_failed_basic_checks( \@rows );
	my $buffer    = qq(<div class="box" id="resultstable">\n);
	my $id_fields = $self->_get_id_fields;
	$buffer .=
	    q(<p>The following changes will be made to the database.  Please check that this is what )
	  . q(you intend and then press 'Upload'.  If you do not wish to make these changes, press your )
	  . qq(browser's back button.</p>\n);
	$buffer .= $self->_get_html_header;
	my $i = 0;
	my ( @id, @id2, @field, @value );
	my $td          = 1;
	my $match_table = $self->_get_match_joined_table;
	my $match       = $self->_get_match_criteria;
	my $qry         = "SELECT COUNT(*) FROM $match_table WHERE $match";
	my $sql         = $self->{'db'}->prepare($qry);
	$qry =~ s/COUNT\(\*\)/id/x;
	my $sql_id      = $self->{'db'}->prepare($qry);
	my $table_rows  = 0;
	my $update_rows = [];

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
		my $is_locus      = $self->_is_locus( $field[$i], $i );
		my $is_eav_field  = $self->{'datastore'}->is_eav_field( $field[$i] );
		my ( $bad_field, $not_allowed_field ) = $self->_check_field_status( \@field, $i, $is_locus );
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
			$display_field =~ s/^meta_.*://x;
			if ( $id_fields->{'field2'} ne '<none>' ) {
				$buffer .= qq(<tr class="td$td"><td>$i</td><td>$id[$i]</td><td>$id2[$i]</td><td>$display_field</td>)
				  . qq(<td>$display_value</td><td>$old_value</td><td>$action</td></tr>\n);
			} else {
				$buffer .=
				    qq(<tr class="td$td"><td>$i</td><td>$id[$i]</td><td>$display_field</td><td>$display_value</td>)
				  . qq(<td>$old_value</td><td>$action</td></tr>);
			}
			$table_rows++;
			$td = $td == 1 ? 2 : 1;
		}
		$i++;
	}
	$buffer .= q(</table>);
	if ($table_rows) {
		say $buffer;
		$self->_display_update_form( $update_rows, $id_fields );
		say q(</div>);
	} else {
		$self->print_bad_status( { message => q(No valid values to update.), navbar => 1 } );
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
		say $q->hidden($_) foreach qw (db page idfield1 idfield2 update file designations);
		$self->print_action_fieldset( { no_reset => 1, submit_label => 'Upload' } );
		say $q->end_form;
	}
	$self->print_navigation_bar( { back_page => 'batchIsolateUpdate' } );
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

sub _check_field {
	my ( $self, $args ) = @_;
	my ( $field, $i, $is_locus, $is_eav_field, $match, $id, $id2, $id_fields, $value ) =
	  @{$args}{qw(field i is_locus is_eav_field match id id2 id_fields value)};
	my ( $old_value, $action );
	my $q = $self->{'cgi'};
	my @args;
	my $table = $self->_get_field_and_match_joined_table( $field->[$i] );
	my $qry;
	my $set_id      = $self->get_set_id;
	my $will_update = 0;

	if ($is_locus) {
		$qry = "SELECT allele_id FROM allele_designations LEFT JOIN $self->{'system'}->{'view'} ON "
		  . "$self->{'system'}->{'view'}.id=allele_designations.isolate_id WHERE locus=? AND $match";
		push @args, $field->[$i];
	} elsif ($is_eav_field) {
		my $eav_table = $self->{'datastore'}->get_eav_field_table( $field->[$i] );
		$qry = "SELECT value FROM $eav_table JOIN $table ON $eav_table.isolate_id=$self->{'system'}->{'view'}.id "
		  . "WHERE field=? AND $match";
		push @args, $field->[$i];
	} else {
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname( $field->[$i] );
		$qry = 'SELECT ' . ( $metafield // $field->[$i] ) . " FROM $table WHERE $match";
	}
	push @args, $id->[$i];
	push @args, $id2->[$i] if $id_fields->{'field2'} ne '<none>';
	my $old_values = $self->{'datastore'}->run_query( $qry, \@args, { fetch => 'col_arrayref' } );
	no warnings 'numeric';
	@$old_values = sort { $a <=> $b || $a cmp $b } @$old_values;
	local $" = ',';

	#Replace undef with empty string in list
	map { $_ //= q() } @$old_values;    ##no critic (ProhibitMutatingListFunctions)
	$old_value = "@$old_values";
	if (   !defined $old_value
		|| $old_value eq ''
		|| $q->param('overwrite') )
	{
		$old_value = q(&lt;blank&gt;)
		  if !defined $old_value || $old_value eq '';
		my $problem =
		  $self->{'submissionHandler'}->is_field_bad( 'isolates', $field->[$i], $value->[$i], 'update', $set_id );
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
			if (   ( any { $value->[$i] eq $_ } @$old_values )
				|| ( $value->[$i] eq '<blank>' && $old_value eq '&lt;blank&gt;' ) )
			{
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
				} else {
					$action = q(<span class="statusgood">update field with new value</span>);
				}
				$will_update = 1;
			}
		}
	} else {
		$action = q(<span class="statusbad">no action - value already in db</span>);
	}
	return ( $old_value, $action, $will_update );
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
	say q(<div class="box" id="resultsheader">);
	say q(<h2>Updating database ...</h2>);
	my $nochange     = 1;
	my $curator_id   = $self->get_curator_id;
	my $curator_name = $self->get_curator_name;
	say qq(User: $curator_name<br />);
	my $datestamp = BIGSdb::Utils::get_datestamp();
	say qq(Datestamp: $datestamp<br />);
	my $tablebuffer = q();
	my $td          = 1;
	my $match_table = $self->_get_match_joined_table;
	my $match       = $self->_get_match_criteria;
	my $view        = $self->{'system'}->{'view'};

	foreach my $record (@records) {
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
		my $isolate_id = $self->{'datastore'}->run_query( "SELECT $view.id FROM $match_table WHERE $match", \@id_args );

		if ($is_locus) {
			my $data = $self->prepare_allele_designation_update( $isolate_id, $field, $value, $deleted_designations );
			( $args, $qry, $delete_qry, $delete_args ) = @{$data}{qw(args qry delete_qry delete_args)};
		} elsif ($is_eav_field) {
			my $data = $self->_prepare_eav_update( $isolate_id, $field, $value );
			( $args, $qry, $old_value ) = @{$data}{qw(args qry old_value)};
		} else {
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			push @$args, ( ( $value // '' ) eq '' ? undef : $value );
			if ( defined $metaset ) {
				my $record_exists = $self->{'datastore'}->run_query(
					"SELECT EXISTS(SELECT * FROM meta_$metaset WHERE isolate_id IN "
					  . "(SELECT $view.id FROM $match_table WHERE $match))",
					\@id_args
				);
				if ($record_exists) {
					$qry = "UPDATE meta_$metaset SET $metafield=? WHERE isolate_id=?";
				} else {
					$qry = "INSERT INTO meta_$metaset ($metafield, isolate_id) VALUES (?,?)";
				}
				push @$args, $isolate_id;
				$old_value =
				  $self->{'datastore'}
				  ->run_query( "SELECT $metafield FROM meta_$metaset WHERE isolate_id=?", $isolate_id );
			} else {
				$qry =
				    "UPDATE isolates SET ($field,datestamp,curator)=(?,?,?) WHERE id IN "
				  . "(SELECT $view.id FROM $match_table WHERE $match)";
				push @$args, ( 'now', $curator_id, @id_args );
				my $id_qry = $qry;
				$id_qry =~ s/UPDATE\ isolates\ .*?\ WHERE/SELECT id,$field FROM isolates WHERE/x;
				( $isolate_id, $old_value ) = $self->{'datastore'}->run_query( $id_qry, \@id_args );
			}
		}
		$tablebuffer .= qq(<tr class="td$td"><td>$id->{'field1'}='$id1');
		$tablebuffer .= qq( AND $id->{'field2'}='$id2') if $id->{'field2'} ne '<none>';
		$value //= q(&lt;blank&gt;);
		( my $display_field = $field ) =~ s/^meta_.*://x;
		$tablebuffer .= qq(</td><td>$display_field</td><td>$value</td>);
		eval {
			if ($delete_qry) {
				$self->{'db'}->do( $delete_qry, undef, @$delete_args );
			}
			$self->{'db'}->do( $qry, undef, @$args );
		};
		if ($@) {
			$logger->error($@) if $@ !~ /duplicate/;    #Designation submitted twice in update - ignore if so
			$tablebuffer .= qq(<td class="statusbad">can't update!</td></tr>\n);
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
			$tablebuffer .= qq(<td class="statusgood">done!</td></tr>\n);
			$old_value //= '';
			$value = '' if $value eq '&lt;blank&gt;';
			( my $display_field = $field ) =~ s/^meta_.*://x;
			if ($is_locus) {
				if ( $q->param('designations') eq 'replace' ) {
					my $plural = @$deleted_designations == 1 ? '' : 's';
					local $" = ',';
					$self->update_history( $isolate_id,
						"$display_field: designation$plural '@$deleted_designations' deleted" )
					  if @$deleted_designations;
				}
				$self->update_history( $isolate_id, "$display_field: new designation '$value'" );
			} else {
				if ( $field eq 'id' ) {
					$isolate_id = $value;
				}
				$self->update_history( $isolate_id, "$display_field: '$old_value' -> '$value'" )
				  if $old_value ne $value;
			}
		}
		$td = $td == 1 ? 2 : 1;
	}
	if ($nochange) {
		say q(<p>No changes to be made.</p>);
	} else {
		say q(<table class="resultstable"><tr><th>Condition</th><th>Field</th>)
		  . qq(<th>New value</th><th>Status</th></tr>$tablebuffer</table>);
	}
	$self->print_navigation_bar( { back_page => 'batchIsolateUpdate' } );
	return;
}

sub prepare_allele_designation_update {
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
	  ->run_query( "SELECT EXISTS(SELECT * FROM $eav_table WHERE (isolate_id,field)=(?,?))", [ $isolate_id, $field ] )
	  ;
	if ($record_exists) {
		$qry = "UPDATE $eav_table SET value=? WHERE (isolate_id,field)=(?,?)";
		@$args = ( $value, $isolate_id, $field );
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
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Batch Isolate Update - $desc";
}
1;
