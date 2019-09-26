#Written by Keith Jolley
#Copyright (c) 2010-2019, University of Oxford
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
package BIGSdb::CurateIsolateUpdatePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateIsolateAddPage BIGSdb::TreeViewPage);
use BIGSdb::Utils;
use List::MoreUtils qw(none uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant SUCCESS => 1;

sub get_javascript {
	my ($self) = @_;
	my $buffer = << "END";
\$(function () {
	\$(document).ajaxComplete(function() {
		reloadTooltips();
	});
	if (!Modernizr.inputtypes.date){
 	   \$(".no_date_picker").css("display","inline");
    }
    \$("#aliases").on('keyup paste',alias_change); 
});
function alias_change(){
	console.log(\$("#aliases").val());
  	if (\$("#aliases").val().indexOf(";") > -1 || \$("#aliases").val().indexOf(",") > -1){
  		\$("span#alias_warning").html("Put each alias on a separate line - do not use semi-colon or comma to separate."); 		
  	} else {
  		\$("span#alias_warning").html("");
  	}
}
END
	$buffer .= $self->get_tree_javascript;
	return $buffer;
}

sub initiate {
	my ($self) = @_;
	if ( $self->{'cgi'}->param('no_header') ) {
		$self->{'type'}    = 'no_header';
		$self->{'noCache'} = 1;
		return;
	}
	$self->{$_} = 1 foreach qw(jQuery jQuery.jstree jQuery.columnizer modernizr jQuery.multiselect tooltips);
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Update isolate</h1>);
	my $isolate_id = $q->param('id');
	my $qry        = "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?";
	my $sql        = $self->{'db'}->prepare($qry);
	if ( !$isolate_id ) {
		$self->print_bad_status( { message => q(No id passed.), navbar => 1 } );
		return;
	} elsif ( !BIGSdb::Utils::is_int($isolate_id) ) {
		$self->print_bad_status( { message => q(Invalid id passed.), navbar => 1 } );
		return;
	} elsif ( !$self->can_modify_table('isolates')
		&& !$self->can_modify_table('allele_designations') )
	{
		$self->print_bad_status(
			{
				message => q(Your user account is not allowed to update isolate records.),
				navbar  => 1
			}
		);
		return;
	}
	eval { $sql->execute($isolate_id) };
	$logger->error($@) if $@;
	my $data = $sql->fetchrow_hashref;
	$self->add_existing_eav_data_to_hashref($data);
	if ( !$data->{'id'} ) {
		my $exists_in_isolates_table =
		  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM isolates WHERE id=?)', $q->param('id') );
		if ($exists_in_isolates_table) {
			$self->print_bad_status(
				{ message => qq(Isolate id-$isolate_id is not accessible from your account.), navbar => 1 } );
		} else {
			$self->print_bad_status( { message => qq(No record with id-$isolate_id exists.), navbar => 1 } );
		}
		return;
	}
	if ( $q->param('sent') ) {
		return if ( $self->_check($data) // 0 ) == SUCCESS;
	}
	$self->_print_interface($data);
	return;
}

sub _check {
	my ( $self, $data ) = @_;
	my $q = $self->{'cgi'};
	if ( !$self->can_modify_table('isolates') ) {
		$self->print_bad_status(
			{
				message => q(Your user account is not allowed to update isolate fields.),
				navbar  => 1
			}
		);
		return;
	}
	my $newdata = {};
	my @bad_field_buffer;
	my $set_id     = $self->get_set_id;
	my $field_list = $self->{'xmlHandler'}->get_field_list;
	foreach my $required ( 1, 0 ) {
		foreach my $field (@$field_list) {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			my $required_field = !( ( $thisfield->{'required'} // '' ) eq 'no' );
			if ( $required_field == $required ) {
				if ( $field eq 'curator' ) {
					$newdata->{$field} = $self->get_curator_id;
				} elsif ( $field eq 'datestamp' ) {
					$newdata->{$field} = BIGSdb::Utils::get_datestamp();
				} else {
					if ( ( $thisfield->{'multiple'} // q() ) eq 'yes' ) {
						$newdata->{$field} = scalar $q->multi_param($field) ? [ $q->multi_param($field) ] : q();
					} else {
						$newdata->{$field} = $q->param($field);
					}
				}
				my $bad_field =
				  $self->{'submissionHandler'}->is_field_bad( 'isolates', $field, $newdata->{$field}, undef, $set_id );
				if ($bad_field) {
					push @bad_field_buffer, qq(Field '$field': $bad_field.);
				}
			}
		}
	}
	my $eav_fields = $self->{'datastore'}->get_eav_fields;
	foreach my $eav_field (@$eav_fields) {
		my $field = $eav_field->{'field'};
		$newdata->{$field} = $q->param($field);
		my $bad_field =
		  $self->{'submissionHandler'}->is_field_bad( 'isolates', $field, $newdata->{$field}, undef, $set_id );
		if ($bad_field) {
			push @bad_field_buffer, qq(Field '$field': $bad_field.);
		}
	}
	if ( $self->alias_duplicates_name ) {
		push @bad_field_buffer, 'Aliases: duplicate isolate name - aliases are ALTERNATIVE names for the isolate.';
	}
	my $validation_failures = $self->{'submissionHandler'}->run_validation_checks($newdata);
	if (@$validation_failures) {
		push @bad_field_buffer, @$validation_failures;
	}
	$self->{'submissionHandler'}->cleanup_validation_rules;
	if (@bad_field_buffer) {
		local $" = '<br />';
		$self->print_bad_status(
			{
				message => q(There are problems with your record submission. Please address the following:),
				detail  => qq(@bad_field_buffer)
			}
		);
	} else {
		return $self->_update( $data, $newdata );
	}
	return;
}

sub _update {
	my ( $self, $data, $newdata ) = @_;
	my $q      = $self->{'cgi'};
	my $update = 1;
	my $qry    = '';
	my @values;
	local $" = ',';
	my $updated_field = [];
	my $set_id        = $self->get_set_id;
	my $field_list    = $self->{'xmlHandler'}->get_field_list;
	foreach my $field (@$field_list) {
		my $att = $self->{'xmlHandler'}->get_field_attributes($field);
		next if ( $att->{'no_curate'} // q() ) eq 'yes';
		if ( $att->{'type'} eq 'bool' ) {
			if    ( ( $data->{ lc($field) } // q() ) eq '1' ) { $data->{ lc($field) } = 'true' }
			elsif ( ( $data->{ lc($field) } // q() ) eq '0' ) { $data->{ lc($field) } = 'false' }
		}
		if ( $self->_field_changed( $field, $data, $newdata ) ) {
			my $cleaned = $self->clean_value( $newdata->{$field}, { no_escape => 1 } ) // '';
			if ( $cleaned ne '' ) {
				$qry .= "$field=?,";
				push @values, $cleaned;
			} else {
				$qry .= "$field=null,";
			}
			if ( $field ne 'datestamp' && $field ne 'curator' ) {
				local $" = q(; );
				my $old = ref $data->{ lc($field) } ? qq(@{$data->{lc($field)}}) : $data->{ lc($field) } // q();
				my $new = ref $newdata->{$field}    ? qq(@{$newdata->{$field}})  : $newdata->{$field};
				push @$updated_field, qq($field: '$old' -> '$new');
			}
		}
	}
	$qry =~ s/,$//x;
	if ($qry) {
		$qry = "UPDATE isolates SET $qry WHERE id=?";
		push @values, $data->{'id'};
	}
	my $eav_updates = $self->_prepare_eav_updates( $data->{'id'}, $newdata, $updated_field );
	my $alias_updates = $self->_prepare_alias_updates( $data->{'id'}, $newdata, $updated_field );
	my ( $pubmed_updates, $error ) = $self->_prepare_pubmed_updates( $data->{'id'}, $newdata, $updated_field );
	return if $error;
	if ($update) {
		if (@$updated_field) {
			eval {
				$self->{'db'}->do( $qry, undef, @values );
				foreach my $extra_update ( @$eav_updates, @$alias_updates, @$pubmed_updates ) {
					$self->{'db'}->do( $extra_update->{'statement'}, undef, @{ $extra_update->{'arguments'} } );
				}
			};
			if ($@) {
				my $detail;
				if ( $@ =~ /duplicate/x && $@ =~ /unique/x ) {
					$detail = q(Data update would have resulted in records with either duplicate ids or )
					  . q(another unique field with duplicate values.);
				} elsif ( $@ =~ /datestyle/ ) {
					$detail = q(Date fields must be entered in yyyy-mm-dd format.);
				} else {
					$logger->error($@);
				}
				$self->print_bad_status(
					{
						message => q(Update failed - transaction cancelled - no records have been touched.),
						detail  => $detail
					}
				);
				$self->{'db'}->rollback;
			} else {
				$self->{'db'}->commit;
				$self->print_good_status(
					{
						message        => q(Isolate updated.),
						navbar         => 1,
						query_more_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query)
					}
				);
				local $" = '<br />';
				$self->update_history( $data->{'id'}, "@$updated_field" );
				return SUCCESS;
			}
		} else {
			$self->print_bad_status(
				{
					message => q(No field changes have been made.),
					navbar  => 1
				}
			);
		}
	}
	return;
}

sub _field_changed {
	my ( $self, $field, $old_data, $new_data ) = @_;
	my $old = $old_data->{ lc($field) } // q();
	my $new = $new_data->{$field}       // q();

	#Don't need to look up attributes if values are the same.
	return if $old eq $new;

	#Need to check if field allows multiple values.
	my $att = $self->{'xmlHandler'}->get_field_attributes($field);
	if ( ( $att->{'multiple'} // q() ) eq 'yes' ) {
		local $" = q(; );
		my @sorted_old = ref $old ? sort @$old : ();
		my @sorted_new = ref $new ? sort @$new : ();
		return qq(@sorted_old) ne qq(@sorted_new);
	} else {
		return ( $old ne $new );
	}
}

sub _prepare_eav_updates {
	my ( $self, $isolate_id, $newdata, $updated_field ) = @_;
	my $q          = $self->{'cgi'};
	my $eav_update = [];
	my $eav_fields = $self->{'datastore'}->get_eav_fields;
	foreach my $eav_field (@$eav_fields) {
		next if $eav_field->{'no_curate'};
		my $field          = $eav_field->{'field'};
		my $table          = $self->{'datastore'}->get_eav_field_table($field);
		my $value          = $q->param($field);
		my $existing_value = $self->{'datastore'}->get_eav_field_value( $isolate_id, $field );
		if ( defined $value && $value ne q() ) {
			if ( $eav_field->{'value_format'} eq 'boolean' ) {
				$value = $value eq 'true' ? 1 : 0;
			}
			if ( defined $existing_value ) {
				if ( $existing_value ne $value ) {
					push @$eav_update,
					  {
						statement => "UPDATE $table SET value=? WHERE (isolate_id,field) = (?,?)",
						arguments => [ $value, $isolate_id, $field ]
					  };
					push @$updated_field, "$field: '$existing_value' -> '$value'";
				}
			} else {
				push @$eav_update,
				  {
					statement => "INSERT INTO $table (isolate_id,field,value) VALUES (?,?,?)",
					arguments => [ $isolate_id, $field, $value ]
				  };
				push @$updated_field, "$field: '' -> '$value'";
			}
		} elsif ( defined $existing_value ) {
			push @$eav_update,
			  {
				statement => "DELETE FROM $table WHERE (isolate_id,field) = (?,?)",
				arguments => [ $isolate_id, $field ]
			  };
			push @$updated_field, "$field: '$existing_value' -> ''";
		}
	}
	return $eav_update;
}

sub _prepare_alias_updates {
	my ( $self, $isolate_id, $newdata, $updated_field ) = @_;
	my $alias_update     = [];
	my $existing_aliases = $self->{'datastore'}->get_isolate_aliases($isolate_id);
	my $q                = $self->{'cgi'};
	my @new_aliases      = split /\r?\n/x, $q->param('aliases');
	@new_aliases = uniq(@new_aliases);
	foreach my $new (@new_aliases) {
		$new = $self->clean_value( $new, { no_escape => 1 } );
		next if $new eq '';
		if ( !@$existing_aliases || none { $new eq $_ } @$existing_aliases ) {
			push @$alias_update,
			  {
				statement => 'INSERT INTO isolate_aliases (isolate_id,alias,curator,datestamp) VALUES (?,?,?,?)',
				arguments => [ $isolate_id, $new, $newdata->{'curator'}, 'now' ]
			  };
			push @$updated_field, "new alias: '$new'";
		}
	}
	foreach my $existing (@$existing_aliases) {
		if ( !@new_aliases || none { $existing eq $_ } @new_aliases ) {
			push @$alias_update,
			  {
				statement => 'DELETE FROM isolate_aliases WHERE (isolate_id,alias)=(?,?)',
				arguments => [ $isolate_id, $existing ]
			  };
			push @$updated_field, "deleted alias: '$existing'";
		}
	}
	return $alias_update;
}

sub _prepare_pubmed_updates {
	my ( $self, $isolate_id, $newdata, $updated_field ) = @_;
	my $existing_pubmeds = $self->{'datastore'}->get_isolate_refs($isolate_id);
	my $q                = $self->{'cgi'};
	my $pubmed_update    = [];
	my @new_pubmeds      = split /\r?\n/x, $q->param('pubmed');
	@new_pubmeds = uniq(@new_pubmeds);
	foreach my $new (@new_pubmeds) {
		chomp $new;
		next if $new eq '';
		if ( !@$existing_pubmeds || none { $new eq $_ } @$existing_pubmeds ) {
			if ( !BIGSdb::Utils::is_int($new) ) {
				$self->print_bad_status( { message => q(PubMed ids must be integers.) } );
				return ( undef, 1 );
			}
			push @$pubmed_update,
			  {
				statement => 'INSERT INTO refs (isolate_id,pubmed_id,curator,datestamp) VALUES (?,?,?,?)',
				arguments => [ $isolate_id, $new, $newdata->{'curator'}, 'now' ]
			  };
			push @$updated_field, "new reference: 'Pubmed#$new'";
		}
	}
	foreach my $existing (@$existing_pubmeds) {
		if ( !@new_pubmeds || none { $existing eq $_ } @new_pubmeds ) {
			push @$pubmed_update,
			  {
				statement => 'DELETE FROM refs WHERE (isolate_id,pubmed_id)=(?,?)',
				arguments => [ $isolate_id, $existing ]
			  };
			push @$updated_field, "deleted reference: 'Pubmed#$existing'";
		}
	}
	return $pubmed_update;
}

sub _print_interface {
	my ( $self, $data ) = @_;
	my $q = $self->{'cgi'};
	say q(<div>);
	if ( $self->can_modify_table('isolates') ) {
		say q(<div class="box queryform" id="isolate_update" style="float:left;margin-right:0.5em">);
		say q(<div class="scrollable">);
		say $q->start_form;
		$q->param( 'sent', 1 );
		say $q->hidden($_) foreach qw(page db sent);
		$self->print_provenance_form_elements( $data, { update => 1 } );
		$self->print_sparse_field_form_elements( $data, { update => 1 } );
		$self->print_action_fieldset( { submit_label => 'Update', id => $data->{'id'} } );
		say $q->end_form;
		say q(</div></div>);
	}
	$self->_print_allele_designations($data) if $self->can_modify_table('allele_designations');
	say q(</div><div style="clear:both"></div>);
	return;
}

sub _print_allele_designations {
	my ( $self, $data ) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="alleles" style="float:left"><div class="scrollable">);
	say q(<fieldset style="float:left"><legend>Loci</legend>);
	my $isolate_record = BIGSdb::IsolateInfoPage->new(
		(
			system        => $self->{'system'},
			cgi           => $self->{'cgi'},
			instance      => $self->{'instance'},
			prefs         => $self->{'prefs'},
			prefstore     => $self->{'prefstore'},
			config        => $self->{'config'},
			datastore     => $self->{'datastore'},
			db            => $self->{'db'},
			xmlHandler    => $self->{'xmlHandler'},
			dataConnector => $self->{'dataConnector'},
			contigManager => $self->{'contigManager'},
			curate        => 1
		)
	);
	my $locus_summary = $isolate_record->get_loci_summary( $data->{'id'} );
	say $locus_summary;
	say $q->start_form;
	my $set_id = $self->get_set_id;
	my ( $loci, $labels ) = $self->{'datastore'}->get_locus_list( { set_id => $set_id } );
	say q(<label for="locus">Locus: </label>);
	say $q->popup_menu( -name => 'locus', -id => 'locus', -values => $loci, -labels => $labels );
	say $q->submit( -label => 'Add/update', -class => 'submit' );
	$q->param( page       => 'alleleUpdate' );
	$q->param( isolate_id => scalar $q->param('id') );
	say $q->hidden($_) foreach qw(db page isolate_id);
	say $q->end_form;
	say q(</fieldset></div></div>);
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Update isolate - $desc";
}
1;
