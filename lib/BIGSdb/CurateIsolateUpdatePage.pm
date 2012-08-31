#Written by Keith Jolley
#Copyright (c) 2010-2012, University of Oxford
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
use parent qw(BIGSdb::CuratePage BIGSdb::TreeViewPage);
use List::MoreUtils qw(none);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant SUCCESS => 1;

sub get_javascript {
	my ($self) = @_;
	return $self->get_tree_javascript;
}

sub initiate {
	my ($self) = @_;
	if ( $self->{'cgi'}->param('no_header') ) {
		$self->{'type'}    = 'no_header';
		$self->{'noCache'} = 1;
		return;
	}
	$self->{$_} = 1 foreach qw(jQuery jQuery.jstree);
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
	$self->_add_existing_metadata_to_hashref($data);
	if ( !$data->{'id'} ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No record with id = " . $q->param('id') . " exists.</p></div>";
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
	my $update        = 1;
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
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
				my $bad_field = $self->is_field_bad( $self->{'system'}->{'view'}, $field, $newdata{$field} );
				if ($bad_field) {
					push @bad_field_buffer, "Field '" . ( $metafield // $field ) . "': $bad_field.";
				}
			}
		}
	}
	if (@bad_field_buffer) {
		say "<div class=\"box\" id=\"statusbad\"><p>There are problems with your record submission.  "
		  . "Please address the following:</p>";
		local $" = '<br />';
		say "<p>@bad_field_buffer</p></div>";
		$update = 0;
	}
	return $self->_update( $data, \%newdata ) if $update;
	return;
}

sub _add_existing_metadata_to_hashref {
	my ( $self, $data ) = @_;
	my $metadata_list = $self->{'xmlHandler'}->get_metadata_list;
	foreach my $metadata_set (@$metadata_list) {
		my $metadata = $self->{'datastore'}->run_list_query_hashref( "SELECT * FROM $metadata_set WHERE isolate_id=?", $data->{'id'} );
		foreach my $metadata_ref (@$metadata) {
			foreach my $field ( keys %$metadata_ref ) {
				$data->{"$metadata_set:$field"} = $metadata_ref->{$field};
			}
		}
	}
	return;
}

sub _update {
	my ( $self, $data, $newdata ) = @_;
	my $q      = $self->{'cgi'};
	my $update = 1;
	my $qry    = '';
	local $" = ',';
	my @updated_field;
	my $set_id = $self->get_set_id;
	my %meta_fields;
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);

	foreach my $field (@$field_list) {
		$data->{ lc($field) } //= '';
		if ( $field ne 'datestamp' && $field ne 'curator' && $data->{ lc($field) } ne $newdata->{$field} ) {
			my $cleaned = $self->clean_value( $newdata->{$field} ) // '';
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			if ( defined $metaset ) {
				push @{ $meta_fields{$metaset} }, $metafield;
			} else {
				$qry .= $cleaned ne '' ? "$field=E'$cleaned'," : "$field=null,";
				push @updated_field, "$field: '$data->{lc($field)}' -> '$newdata->{$field}'";
			}
		}
	}
	$qry =~ s/,$//;
	$qry = "UPDATE isolates SET $qry WHERE id=$data->{'id'}" if $qry;
	my $metadata_updates = $self->_prepare_metaset_updates( \%meta_fields, $data, $newdata, \@updated_field );
	my @alias_update;
	my $existing_aliases =
	  $self->{'datastore'}->run_list_query( "SELECT alias FROM isolate_aliases WHERE isolate_id=? ORDER BY isolate_id", $data->{'id'} );
	my @new_aliases = split /\r?\n/, $q->param('aliases');
	foreach my $new (@new_aliases) {
		chomp $new;
		next if $new eq '';
		if ( !@$existing_aliases || none { $new eq $_ } @$existing_aliases ) {
			( my $clean_new = $new ) =~ s/'/\\'/g;
			push @alias_update, "INSERT INTO isolate_aliases (isolate_id,alias,curator,datestamp) VALUES ($data->{'id'},"
			  . "'$clean_new',$newdata->{'curator'},'today')";
			push @updated_field, "new alias: '$new'";
		}
	}
	foreach my $existing (@$existing_aliases) {
		if ( !@new_aliases || none { $existing eq $_ } @new_aliases ) {
			( my $clean_existing = $existing ) =~ s/'/\\'/g;
			push @alias_update,  "DELETE FROM isolate_aliases WHERE isolate_id=$data->{'id'} AND alias='$clean_existing'";
			push @updated_field, "deleted alias: '$existing'";
		}
	}
	my @pubmed_update;
	my $existing_pubmeds = $self->{'datastore'}->run_list_query( "SELECT pubmed_id FROM refs WHERE isolate_id=?", $data->{'id'} );
	my @new_pubmeds = split /\r?\n/, $q->param('pubmed');
	foreach my $new (@new_pubmeds) {
		chomp $new;
		next if $new eq '';
		if ( !@$existing_pubmeds || none { $new eq $_ } @$existing_pubmeds ) {
			( my $clean_new = $new ) =~ s/'/\\'/g;
			if ( !BIGSdb::Utils::is_int($clean_new) ) {
				print "<div class=\"box\" id=\"statusbad\"><p>PubMed ids must be integers.</p></div>\n";
				$update = 0;
			}
			push @pubmed_update, "INSERT INTO refs (isolate_id,pubmed_id,curator,datestamp) VALUES ($data->{'id'},"
			  . "'$clean_new',$newdata->{'curator'},'today')";
			push @updated_field, "new reference: 'Pubmed#$new'";
		}
	}
	foreach my $existing (@$existing_pubmeds) {
		if ( !@new_pubmeds || none { $existing eq $_ } @new_pubmeds ) {
			( my $clean_existing = $existing ) =~ s/'/\\'/g;
			push @pubmed_update, "DELETE FROM refs WHERE isolate_id=$data->{'id'} AND pubmed_id='$clean_existing'";
			push @updated_field, "deleted reference: 'Pubmed#$existing'";
		}
	}
	if ($update) {
		if (@updated_field) {
			eval {
				$self->{'db'}->do($qry);
				foreach ( @alias_update, @pubmed_update, @$metadata_updates ) {
					$self->{'db'}->do($_);
				}
			};
			if ($@) {
				say "<div class=\"box\" id=\"statusbad\"><p>Update failed - transaction cancelled - " . "no records have been touched.</p>";
				if ( $@ =~ /duplicate/ && $@ =~ /unique/ ) {
					say "<p>Data update would have resulted in records with either duplicate ids or "
					  . "another unique field with duplicate values.</p>";
				} elsif ( $@ =~ /datestyle/ ) {
					say "<p>Date fields must be entered in yyyy-mm-dd format.</p>";
				} else {
					$logger->error($@);
				}
				print "</div>\n";
				$self->{'db'}->rollback;
			} else {
				$self->{'db'}->commit
				  && say "<div class=\"box\" id=\"resultsheader\"><p>Updated!</p>";
				say "<p><a href=\"" . $q->script_name . "?db=$self->{'instance'}\">Back to main page</a></p></div>";
				local $" = '<br />';
				$self->update_history( $data->{'id'}, "@updated_field" );
				return SUCCESS;
			}
		} else {
			say "<div class=\"box\" id=\"resultsheader\"><p>No field changes have been made.</p>";
			say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back to main page</a></p></div>";
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
		  $self->{'datastore'}->run_simple_query( "SELECT EXISTS(SELECT * FROM meta_$metaset WHERE isolate_id=?)", $newdata->{'id'} )->[0];
		my @fields = @{ $meta_fields->{$metaset} };
		local $" = ',';
		my $qry =
		  $metadata_record_exists
		  ? "UPDATE meta_$metaset SET (@fields) = ("
		  : "INSERT INTO meta_$metaset (isolate_id,@fields) VALUES ($newdata->{'id'},";
		foreach my $field (@fields) {
			$qry .= ',' if $field ne $fields[0];
			my $cleaned = $self->clean_value( $newdata->{"meta_$metaset:$field"} );
			$qry .= $cleaned eq '' ? 'null' : "E'$cleaned'";
			push @$updated_field,
			  "$field: '" . $existing_data->{ lc("meta_$metaset:$field") } . "' -> '" . $newdata->{"meta_$metaset:$field"} . "'";
		}
		$qry .= ')';
		$qry .= " WHERE isolate_id = $newdata->{'id'}" if $metadata_record_exists;
		push @updates, $qry;
	}
	return \@updates;
}

sub _print_interface {
	my ( $self, $data ) = @_;
	my $q         = $self->{'cgi'};
	my $qry       = "select id,user_name,first_name,surname from users WHERE id>0 order by surname";
	my $user_data = $self->{'datastore'}->run_list_query_hashref($qry);
	my ( @users, %usernames );
	foreach my $user_hashref (@$user_data) {
		push @users, $user_hashref->{'id'};
		$usernames{ $user_hashref->{'id'} } = "$user_hashref->{'surname'}, $user_hashref->{'first_name'} ($user_hashref->{'user_name'})";
	}
	say "<div class=\"scrollable\">";
	say "<table><tr>";
	say "<td style=\"vertical-align:top\">";
	if ( $self->can_modify_table('isolates') ) {
		say "<div class=\"box\" id=\"queryform\">";
		if ( !$q->param('sent') ) {
			say "<h2>Isolate fields:</h2>";
			say "<p>Update your record as required:</p>";
		}
		say "<table><tr><td>";
		say $q->start_form;
		$q->param( 'sent', 1 );
		say $q->hidden($_) foreach qw(page db sent);
		say "<table>\n<tr><td colspan=\"2\" style=\"text-align:right\">";
		say $q->submit( -name => 'Update', -class => 'submit' );
		say "</td></tr>";
		my $set_id        = $self->get_set_id;
		my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
		my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);

		#Display required fields first
		foreach my $required ( 1, 0 ) {
			foreach my $field (@$field_list) {
				my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
				my $required_field = !( ( $thisfield->{'required'} // '' ) eq 'no' );
				my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
				$required_field = 0 if !$set_id && defined $metaset;    #Field can't be compulsory if part of a metadata collection.
				if ( $required_field == $required ) {
					print "<tr><td style=\"text-align:right\">" . ( $metafield // $field ) . ': ';
					print '!' if $required;
					print "</td><td style=\"text-align:left; width:90%\">";
					if ( $thisfield->{'optlist'} ) {
						my $optlist = $self->{'xmlHandler'}->get_field_option_list($field);
						say $q->popup_menu( -name => $field, -values => [ '', @$optlist ], -default => $data->{ lc($field) } );
					} elsif ( $thisfield->{'type'} eq 'bool' ) {
						my $default = $data->{ lc($field) } ~~ [qw (t 1 true)] ? 'true' : 'false';
						$default = undef if !defined $data->{ lc($field) };
						say $q->popup_menu( -name => $field, -values => [ '', 'true', 'false' ], -default => $default );
					} elsif ( $field eq 'id' ) {
						say "<b>$data->{'id'}</b>";
						say $q->hidden( 'id', $data->{'id'} );
					} elsif ( lc($field) eq 'curator' ) {
						say '<b>' . $self->get_curator_name . ' (' . $self->{'username'} . ")</b>";
					} elsif ( lc($field) eq 'date_entered' ) {
						say '<b>' . $data->{ lc($field) } . "</b>";
						say $q->hidden( 'date_entered', $data->{ lc($field) } );
					} elsif ( lc($field) eq 'datestamp' ) {
						say '<b>' . $self->get_datestamp . "</b>";
					} elsif ( lc($field) ~~ [qw(sender sequenced_by)] || ( $thisfield->{'userfield'} // '' ) eq 'yes' ) {
						say $q->popup_menu(
							-name    => $field,
							-values  => [ '', @users ],
							-labels  => \%usernames,
							-default => $data->{ lc($field) }
						);
					} else {
						if ( $thisfield->{'length'} && $thisfield->{'length'} > 60 ) {
							say $q->textarea( -name => $field, -rows => 3, -cols => 60, -default => $data->{ lc($field) } );
						} else {
							say $q->textfield( -name => $field, -size => $thisfield->{'length'}, -default => $data->{ lc($field) } );
						}
					}
					say " <span class=\"metaset\">Metadata: $metaset</span>" if !$set_id && defined $metaset;
					if ( ( none { lc($field) eq $_ } qw(datestamp date_entered) ) && lc( $thisfield->{'type'} ) eq 'date' ) {
						say " format: yyyy-mm-dd";
					}
					say "</td></tr>";
				}
			}
		}
		say "<tr><td style=\"text-align:right\">aliases: </td><td>";
		my $aliases =
		  $self->{'datastore'}->run_list_query( "SELECT alias FROM isolate_aliases WHERE isolate_id=? ORDER BY alias ", $q->param('id') );
		local $" = "\n";
		say $q->textarea( -name => 'aliases', -rows => 2, -cols => 12, -style => 'width:10em', -default => "@$aliases" );
		say "</td></tr>\n<tr><td style=\"text-align:right\">PubMed ids: </td><td>";
		my $pubmed =
		  $self->{'datastore'}
		  ->run_list_query( "SELECT pubmed_id FROM refs WHERE isolate_id=? ORDER BY pubmed_id", $q->param('id') );
		say $q->textarea( -name => 'pubmed', -rows => 2, -cols => 12, -style => 'width:10em', -default => "@$pubmed" );
		say "</td></tr>\n<tr><td><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=isolateUpdate&amp;"
		  . "id=$data->{'id'}\" class=\"resetbutton\">Reset</a></td><td style=\"text-align:right\">";
		say $q->submit( -name => 'Update', -class => 'submit' );
		say "</td></tr>\n</table>";
		say $q->end_form;
		say "</td></tr></table></div>";
	}
	$self->_print_samples($data)             if $self->can_modify_table('samples');
	$self->_print_allele_designations($data) if $self->can_modify_table('allele_designations');
	say "</td></tr></table></div>";
	return;
}

sub _print_allele_designations {
	my ( $self, $data ) = @_;
	my $q = $self->{'cgi'};
	say "</td><td style=\"vertical-align:top; padding-left:1em\">"
	  if $self->can_modify_table('isolates') || $self->can_modify_table('samples');
	say "<div class=\"box\" id=\"alleles\">\n<h2>Loci:</h2>";
	say "<p>Allele designations are handled separately from isolate fields due to the potential "
	  . "complexity of multiple loci with set and pending designations.</p>";
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
	$locus_summary =~ s /<table class=\"resultstable\">\s*<\/table>//;
	say $locus_summary;
	say "<p />";
	say $q->start_form;
	my $set_id = $self->get_set_id;
	my ( $loci, $labels ) = $self->{'datastore'}->get_locus_list( { set_id => $set_id } );
	say "<label for=\"locus\">Locus: </label>";
	say $q->popup_menu( -name => 'locus', -id => 'locus', -values => $loci, -labels => $labels );
	say $q->submit( -label => 'Add/update', -class => 'submit' );
	$q->param( 'page',       'alleleUpdate' );
	$q->param( 'isolate_id', $q->param('id') );
	say $q->hidden($_) foreach qw(db page isolate_id);
	say $q->end_form;
	say "</div>";
	return;
}

sub _print_samples {
	my ( $self, $data ) = @_;
	my $sample_fields = $self->{'xmlHandler'}->get_sample_field_list;
	if (@$sample_fields) {
		say "<div class=\"box\" id=\"samples\">";
		say "<h2>Samples:</h2>";
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
		say "<p /><p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;"
		  . "table=samples&amp;isolate_id=$data->{'id'}\" class=\"button\">&nbsp;Add new sample&nbsp;</a></p>";
		say "</div>";
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Update isolate - $desc";
}
1;
