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
package BIGSdb::CurateIsolateUpdatePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateIsolateAddPage BIGSdb::TreeViewPage);
use List::MoreUtils qw(none);
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
	\$("#sample").columnize({width:300});
});
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
	$self->{$_} = 1 foreach qw(jQuery jQuery.jstree jQuery.columnizer jQuery.multiselect);
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say "<h1>Update isolate</h1>";
	my $qry = "SELECT * FROM $self->{'system'}->{'view'} WHERE id = ?";
	my $sql = $self->{'db'}->prepare($qry);
	if ( !$q->param('id') ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No id passed.</p></div>";
		return;
	} elsif ( !BIGSdb::Utils::is_int( $q->param('id') ) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Invalid id passed.</p></div>";
		return;
	} elsif ( !$self->can_modify_table('isolates')
		&& !$self->can_modify_table('allele_designations')
		&& !$self->can_modify_table('samples') )
	{
		say "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to update isolate records.</p></div>";
		return;
	}
	eval { $sql->execute( $q->param('id') ) };
	$logger->error($@) if $@;
	my $data = $sql->fetchrow_hashref;
	$self->add_existing_metadata_to_hashref($data);
	if ( !$data->{'id'} ) {
		my $exists_in_isolates_table =
		  $self->{'datastore'}->run_query( "SELECT EXISTS(SELECT * FROM isolates WHERE id=?)", $q->param('id') );
		if ($exists_in_isolates_table) {
			say qq(<div class="box" id="statusbad"><p>Isolate id-) . $q->param('id') . qq( is not accessible from your account.</p></div>);
		} else {
			say qq(<div class="box" id="statusbad"><p>No record with id-) . $q->param('id') . qq( exists.</p></div>);
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
		say "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to update isolate fields.</p></div>";
		return;
	}
	my %newdata;
	my @bad_field_buffer;
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata( $set_id, { curate => 1 } );
	my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
	foreach my $required ( 1, 0 ) {
		foreach my $field (@$field_list) {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			my $required_field = !( ( $thisfield->{'required'} // '' ) eq 'no' );
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			$required_field = 0 if !$set_id && defined $metaset;    #Field can't be compulsory if part of a metadata collection.
			if ( $required_field == $required ) {
				if ( $field eq 'curator' ) {
					$newdata{$field} = $self->get_curator_id;
				} elsif ( $field eq 'datestamp' ) {
					$newdata{$field} = $self->get_datestamp;
				} else {
					$newdata{$field} = $q->param($field);
				}
				my $bad_field = $self->is_field_bad( 'isolates', $field, $newdata{$field} );
				if ($bad_field) {
					push @bad_field_buffer, "Field '" . ( $metafield // $field ) . "': $bad_field.";
				}
			}
		}
	}
	if ( $self->alias_duplicates_name ) {
		push @bad_field_buffer, "Aliases: duplicate isolate name - aliases are ALTERNATIVE names for the isolate.";
	}
	if (@bad_field_buffer) {
		say "<div class=\"box\" id=\"statusbad\"><p>There are problems with your record submission.  "
		  . "Please address the following:</p>";
		local $" = '<br />';
		say "<p>@bad_field_buffer</p></div>";
	} else {
		return $self->_update( $data, \%newdata );
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
	my @updated_field;
	my $set_id = $self->get_set_id;
	my %meta_fields;
	my $metadata_list = $self->{'datastore'}->get_set_metadata( $set_id, { curate => 1 } );
	my $field_list = $self->{'xmlHandler'}->get_field_list($metadata_list);

	foreach my $field (@$field_list) {
		$data->{ lc($field) } //= '';
		my $att = $self->{'xmlHandler'}->get_field_attributes($field);
		if ( $att->{'type'} eq 'bool' ) {
			if    ( $data->{ lc($field) } eq '1' ) { $data->{ lc($field) } = 'true' }
			elsif ( $data->{ lc($field) } eq '0' ) { $data->{ lc($field) } = 'false' }
		}
		if ( $data->{ lc($field) } ne $newdata->{$field} ) {
			my $cleaned = $self->clean_value( $newdata->{$field}, { no_escape => 1 } ) // '';
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			if ( defined $metaset ) {
				push @{ $meta_fields{$metaset} }, $metafield;
			} else {
				if ( $cleaned ne '' ) {
					$qry .= "$field=?,";
					push @values, $cleaned;
				} else {
					$qry .= "$field=null,";
				}
				if ( $field ne 'datestamp' && $field ne 'curator' ) {
					push @updated_field, "$field: '$data->{lc($field)}' -> '$newdata->{$field}'";
				}
			}
		}
	}
	$qry =~ s/,$//;
	if ($qry) {
		$qry = "UPDATE isolates SET $qry WHERE id=?";
		push @values, $data->{'id'};
	}
	my $metadata_updates = $self->_prepare_metaset_updates( \%meta_fields, $data, $newdata, \@updated_field );
	my @alias_update;
	my $existing_aliases = $self->{'datastore'}->get_isolate_aliases( $data->{'id'} );
	my @new_aliases = split /\r?\n/, $q->param('aliases');
	foreach my $new (@new_aliases) {
		chomp $new;
		next if $new eq '';
		if ( !@$existing_aliases || none { $new eq $_ } @$existing_aliases ) {
			push @alias_update,
			  {
				statement => "INSERT INTO isolate_aliases (isolate_id,alias,curator,datestamp) VALUES (?,?,?,?)",
				arguments => [ $data->{'id'}, $new, $newdata->{'curator'}, 'now' ]
			  };
			push @updated_field, "new alias: '$new'";
		}
	}
	foreach my $existing (@$existing_aliases) {
		if ( !@new_aliases || none { $existing eq $_ } @new_aliases ) {
			push @alias_update,
			  { statement => "DELETE FROM isolate_aliases WHERE (isolate_id,alias)=(?,?)", arguments => [ $data->{'id'}, $existing ] };
			push @updated_field, "deleted alias: '$existing'";
		}
	}
	my @pubmed_update;
	my $existing_pubmeds = $self->{'datastore'}->get_isolate_refs( $data->{'id'} );
	my @new_pubmeds = split /\r?\n/, $q->param('pubmed');
	foreach my $new (@new_pubmeds) {
		chomp $new;
		next if $new eq '';
		if ( !@$existing_pubmeds || none { $new eq $_ } @$existing_pubmeds ) {
			if ( !BIGSdb::Utils::is_int($new) ) {
				say qq(<div class="box" id="statusbad"><p>PubMed ids must be integers.</p></div>);
				$update = 0;
			}
			push @pubmed_update,
			  {
				statement => "INSERT INTO refs (isolate_id,pubmed_id,curator,datestamp) VALUES (?,?,?,?)",
				arguments => [ $data->{'id'}, $new, $newdata->{'curator'}, 'now' ]
			  };
			push @updated_field, "new reference: 'Pubmed#$new'";
		}
	}
	foreach my $existing (@$existing_pubmeds) {
		if ( !@new_pubmeds || none { $existing eq $_ } @new_pubmeds ) {
			push @pubmed_update,
			  { statement => "DELETE FROM refs WHERE (isolate_id,pubmed_id)=(?,?)", arguments => [ $data->{'id'}, $existing ] };
			push @updated_field, "deleted reference: 'Pubmed#$existing'";
		}
	}
	if ($update) {
		if (@updated_field) {
			eval {
				$self->{'db'}->do( $qry, undef, @values );
				foreach my $extra_update ( @alias_update, @pubmed_update, @$metadata_updates ) {
					$self->{'db'}->do( $extra_update->{'statement'}, undef, @{ $extra_update->{'arguments'} } );
				}
			};
			if ($@) {
				say qq(<div class="box" id="statusbad"><p>Update failed - transaction cancelled - no records have been touched.</p>);
				if ( $@ =~ /duplicate/ && $@ =~ /unique/ ) {
					say "<p>Data update would have resulted in records with either duplicate ids or "
					  . "another unique field with duplicate values.</p>";
				} elsif ( $@ =~ /datestyle/ ) {
					say "<p>Date fields must be entered in yyyy-mm-dd format.</p>";
				} else {
					$logger->error($@);
				}
				say "</div>";
				$self->{'db'}->rollback;
			} else {
				$self->{'db'}->commit
				  && say qq(<div class="box" id="resultsheader"><p>Updated!</p>);
				say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>);
				local $" = '<br />';
				$self->update_history( $data->{'id'}, "@updated_field" );
				return SUCCESS;
			}
		} else {
			say qq(<div class="box" id="resultsheader"><p>No field changes have been made.</p>);
			say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>);
		}
	}
	return;
}

sub _prepare_metaset_updates {
	my ( $self, $meta_fields, $existing_data, $newdata, $updated_field ) = @_;
	my @metasets = keys %$meta_fields;
	my @updates;
	foreach my $metaset (@metasets) {
		my $metadata_record_exists =
		  $self->{'datastore'}->run_query( "SELECT EXISTS(SELECT * FROM meta_$metaset WHERE isolate_id=?)", $newdata->{'id'} );
		my $fields = $meta_fields->{$metaset};
		local $" = ',';
		my $qry;
		my @values;
		if ($metadata_record_exists) {
			my @placeholders = ('?') x @$fields;
			$qry = "UPDATE meta_$metaset SET (@$fields) = (@placeholders)";
		} else {
			my @placeholders = ('?') x ( @$fields + 1 );
			$qry = "INSERT INTO meta_$metaset (isolate_id,@$fields) VALUES (@placeholders)";
			push @values, $newdata->{'id'};
		}
		foreach my $field (@$fields) {
			my $cleaned = $self->clean_value( $newdata->{"meta_$metaset:$field"}, { no_escape => 1 } );
			$cleaned = undef if $cleaned eq '';
			push @values, $cleaned;
			push @$updated_field,
			  "$field: '" . $existing_data->{ lc("meta_$metaset:$field") } . "' -> '" . $newdata->{"meta_$metaset:$field"} . "'";
		}
		if ($metadata_record_exists) {
			$qry .= " WHERE isolate_id=?";
			push @values, $newdata->{'id'};
		}
		push @updates, { statement => $qry, arguments => \@values };
	}
	return \@updates;
}

sub _print_interface {
	my ( $self, $data ) = @_;
	my $q = $self->{'cgi'};
	say "<div>";
	if ( $self->can_modify_table('isolates') ) {
		say qq(<div class="box queryform" id="isolate_update" style="float:left;margin-right:0.5em">);
		say qq(<div class="scrollable">);
		say $q->start_form;
		$q->param( 'sent', 1 );
		say $q->hidden($_) foreach qw(page db sent);
		$self->print_provenance_form_elements( $data, { update => 1 } );
		say $q->end_form;
		say "</div></div>";
	}
	$self->_print_samples($data)             if $self->can_modify_table('samples');
	$self->_print_allele_designations($data) if $self->can_modify_table('allele_designations');
	say "</div><div style=\"clear:both\"></div>";
	return;
}

sub _print_allele_designations {
	my ( $self, $data ) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="alleles" style="overflow:auto">);
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
	$q->param( isolate_id => $q->param('id') );
	say $q->hidden($_) foreach qw(db page isolate_id);
	say $q->end_form;
	say "</fieldset></div>";
	return;
}

sub _print_samples {
	my ( $self, $data ) = @_;
	my $sample_fields = $self->{'xmlHandler'}->get_sample_field_list;
	if (@$sample_fields) {
		say "<div class=\"box\" id=\"samples\" style=\"overflow:auto\">";
		say "<fieldset style=\"float:left\"><legend>Samples</legend>";
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
				curate        => 1
			)
		);
		say $isolate_record->get_sample_summary( $data->{'id'} );
		say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;"
		  . "table=samples&amp;isolate_id=$data->{'id'}\" class=\"button\">&nbsp;Add new sample&nbsp;</a></p>";
		say "</fieldset></div>";
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Update isolate - $desc";
}
1;
