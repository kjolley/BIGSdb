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
package BIGSdb::CurateIsolateAddPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateAddPage);
use List::MoreUtils qw(none uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant SUCCESS => 1;

sub print_content {
	my ($self) = @_;
	say "<h1>Add new isolate</h1>";
	if ( !$self->can_modify_table('isolates') ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to add records to the isolates table.</p></div>";
		return;
	}
	my $q = $self->{'cgi'};
	my %newdata;
	foreach my $field ( @{ $self->{'xmlHandler'}->get_field_list } ) {
		if ( $q->param($field) ) {
			$newdata{$field} = $q->param($field);
		} else {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			if ( $thisfield->{'type'} eq 'int'
				&& lc($field) eq 'id' )
			{
				$newdata{$field} = $self->next_id('isolates');
			}
		}
	}
	if ( $q->param('sent') ) {
		return if ( $self->_check( \%newdata ) // 0 ) == SUCCESS;
	}
	$self->_print_interface( \%newdata );
	return;
}

sub _check {
	my ( $self, $newdata ) = @_;
	my $q             = $self->{'cgi'};
	my $set_id        = $self->get_set_id;
	my $loci          = $self->{'datastore'}->get_loci( { query_pref => 1, set_id => $set_id } );
	my $metadata_list = $self->{'datastore'}->get_set_metadata( $set_id, { curate => 1 } );
	my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
	@$loci = uniq @$loci;
	my @bad_field_buffer;
	my $insert = 1;

	foreach my $required ( 1, 0 ) {
		foreach my $field (@$field_list) {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			my $required_field = !( ( $thisfield->{'required'} // '' ) eq 'no' );
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			$required_field = 0 if !$set_id && defined $metaset;    #Field can't be compulsory if part of a metadata collection.
			if ( $required_field == $required ) {
				if ( $field eq 'curator' ) {
					$newdata->{$field} = $self->get_curator_id;
				} elsif ( $field ~~ [qw(datestamp date_entered)] ) {
					$newdata->{$field} = $self->get_datestamp;
				} else {
					$newdata->{$field} = $q->param($field);
				}
				my $bad_field = $self->is_field_bad( $self->{'system'}->{'view'}, $field, $newdata->{$field} );
				if ($bad_field) {
					push @bad_field_buffer, "Field '" . ( $metafield // $field ) . "': $bad_field";
				}
			}
		}
	}
	foreach my $locus (@$loci) {
		if ( $q->param("locus:$locus") ) {
			$newdata->{"locus:$locus"}         = $q->param("locus:$locus");
			$newdata->{"locus:$locus\_status"} = $q->param("locus:$locus\_status");
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			if ( $locus_info->{'allele_id_format'} eq 'integer'
				&& !BIGSdb::Utils::is_int( $newdata->{"locus:$locus"} ) )
			{
				push @bad_field_buffer, "Locus '$locus': allele value must be an integer.";
			} elsif ( $locus_info->{'allele_id_regex'} && $newdata->{"locus:$locus"} !~ /$locus_info->{'allele_id_regex'}/ ) {
				push @bad_field_buffer,
				  "Locus '$locus' allele value is invalid - it must match the regular expression /$locus_info->{'allele_id_regex'}/";
			}
		}
	}
	if (@bad_field_buffer) {
		say "<div class=\"box\" id=\"statusbad\"><p>There are problems with your record submission.  Please address the following:</p>";
		local $" = '<br />';
		say "<p>@bad_field_buffer</p></div>";
		$insert = 0;
	}
	foreach ( keys %$newdata ) {    #Strip any trailing spaces
		if ( defined $newdata->{$_} ) {
			$newdata->{$_} =~ s/^\s*//g;
			$newdata->{$_} =~ s/\s*$//g;
		}
	}
	if ($insert) {
		if ( $self->id_exists( $newdata->{'id'} ) ) {
			say "<div class=\"box\" id=\"statusbad\"><p>id-$newdata->{'id'} has already been defined - "
			  . "please choose a different id number.</p></div>";
			$insert = 0;
		}
		return $self->_insert($newdata) if $insert;
	}
	return;
}

sub _prepare_metaset_insert {
	my ( $self, $meta_fields, $newdata ) = @_;
	my @metasets = keys %$meta_fields;
	my @inserts;
	foreach my $metaset (@metasets) {
		my @fields = @{ $meta_fields->{$metaset} };
		local $" = ',';
		my $qry = "INSERT INTO meta_$metaset (isolate_id,@fields) VALUES ($newdata->{'id'}";
		foreach my $field (@fields) {
			$qry .= ',';
			my $cleaned = $self->clean_value( $newdata->{"meta_$metaset:$field"} );
			$qry .= "E'$cleaned'";
		}
		$qry .= ')';
		push @inserts, $qry;
	}
	return \@inserts;
}

sub _insert {
	my ( $self, $newdata ) = @_;
	my $q      = $self->{'cgi'};
	my $set_id = $self->get_set_id;
	my $loci   = $self->{'datastore'}->get_loci( { query_pref => 1, set_id => $set_id } );
	@$loci = uniq @$loci;
	my $insert = 1;
	my @fields_with_values;
	my %meta_fields;
	my $metadata_list = $self->{'datastore'}->get_set_metadata( $set_id, { curate => 1 } );
	my $field_list = $self->{'xmlHandler'}->get_field_list($metadata_list);

	foreach my $field (@$field_list) {
		if ( $newdata->{$field} ne '' ) {
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			if ( defined $metaset ) {
				push @{ $meta_fields{$metaset} }, $metafield;
			} else {
				push @fields_with_values, $field;
			}
		}
	}
	my @inserts;
	local $" = ',';
	my $qry = "INSERT INTO isolates (@fields_with_values) VALUES (";
	foreach my $field (@fields_with_values) {
		$qry .= "," if $field ne $fields_with_values[0];
		my $cleaned = $self->clean_value( $newdata->{$field} );
		$qry .= "E'$cleaned'";
	}
	$qry .= ')';
	push @inserts, $qry;
	my $metadata_inserts = $self->_prepare_metaset_insert( \%meta_fields, $newdata );
	push @inserts, @$metadata_inserts;

	#Set read ACL for 'All users' group
	push @inserts, "INSERT INTO isolate_usergroup_acl (isolate_id,user_group_id,read,write) VALUES ($newdata->{'id'},0,true,false)";

	#Set read/write ACL for curator
	push @inserts, "INSERT INTO isolate_user_acl (isolate_id,user_id,read,write) VALUES ($newdata->{'id'},$newdata->{'curator'},true,true)";
	foreach my $locus (@$loci) {
		if ( $q->param("locus:$locus") ) {
			$qry =
			    "INSERT INTO allele_designations (isolate_id,locus,allele_id,sender,status,method,curator,date_entered,datestamp) "
			  . "VALUES ($newdata->{'id'},E'$locus',E'$newdata->{\"locus:$locus\"}',$newdata->{'sender'},'$newdata->{\"locus:$locus\_status\"}',"
			  . "'manual',$newdata->{'curator'},'today','today')";
			push @inserts, $qry;
		}
	}
	my @new_aliases = split /\r?\n/, $q->param('aliases');
	foreach my $new (@new_aliases) {
		$new =~ s/\s+$//;
		$new =~ s/^\s+//;
		next if $new eq '';
		( my $clean_new = $new ) =~ s/'/\\'/g;
		push @inserts, "INSERT INTO isolate_aliases (isolate_id,alias,curator,datestamp) VALUES ($newdata->{'id'},E'$clean_new',"
		  . "$newdata->{'curator'},'today')";
	}
	my @new_pubmeds = split /\r?\n/, $q->param('pubmed');
	foreach my $new (@new_pubmeds) {
		chomp $new;
		next if $new eq '';
		if ( !BIGSdb::Utils::is_int($new) ) {
			print "<div class=\"box\" id=\"statusbad\"><p>PubMed ids must be integers.</p></div>\n";
			$insert = 0;
		}
		push @inserts,
		  "INSERT INTO refs (isolate_id,pubmed_id,curator,datestamp) VALUES ($newdata->{'id'},$new,$newdata->{'curator'},'today')";
	}
	if ($insert) {
		local $" = ';';
		eval { $self->{'db'}->do("@inserts"); };
		if ($@) {
			print "<div class=\"box\" id=\"statusbad\"><p>Insert failed - transaction cancelled - no records have been touched.</p>\n";
			if ( $@ =~ /duplicate/ && $@ =~ /unique/ ) {
				say "<p>Data entry would have resulted in records with either duplicate ids or another unique field with "
				  . "duplicate values.</p>";
			} else {
				say "<p>Error message: $@</p>";
				$logger->error("Insert failed: $qry  $@");
			}
			print "</div>\n";
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit
			  && say "<div class=\"box\" id=\"resultsheader\"><p>id-$newdata->{'id'} added!</p>";
			say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=isolateAdd\">Add another</a> | "
			  . "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSeqbin&amp;"
			  . "isolate_id=$newdata->{'id'}\">Upload sequences</a> | "
			  . "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back to main page</a></p></div>";
			$self->update_history( $newdata->{'id'}, "Isolate record added" );
			return SUCCESS;
		}
	}
	return;
}

sub _print_interface {
	my ( $self, $newdata ) = @_;
	my $set_id = $self->get_set_id;
	my $loci = $self->{'datastore'}->get_loci( { query_pref => 1, set_id => $set_id } );
	@$loci = uniq @$loci;
	my $q = $self->{'cgi'};
	say "<div class=\"box\" id=\"queryform\"><p>Please fill in the fields below - required fields are "
	  . "marked with an exclamation mark (!).</p>";
	say "<div class=\"scrollable\">";
	my ( @users, %usernames );
	my $user_data =
	  $self->{'datastore'}
	  ->run_list_query_hashref("SELECT id,user_name,first_name,surname FROM users WHERE id>0 ORDER BY surname, first_name, user_name");

	foreach (@$user_data) {
		push @users, $_->{'id'};
		$usernames{ $_->{'id'} } = "$_->{'surname'}, $_->{'first_name'} ($_->{'user_name'})";
	}
	say $q->start_form;
	$q->param( 'sent', 1 );
	say $q->hidden($_) foreach qw(page db sent);
	my $metadata_list = $self->{'datastore'}->get_set_metadata( $set_id, { curate => 1 } );
	my $field_list = $self->{'xmlHandler'}->get_field_list($metadata_list);
	if ( @$field_list > 15 ) {
		say "<span style=\"float:right\">";
		say $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
		say "</span>";
	}
	say "<fieldset><legend>Isolate fields</legend>";
	say "<p><span class=\"metaset\">Metadata</span><span class=\"comment\">: These fields are available in the specified "
	  . "dataset only.</span></p>"
	  if !$set_id && @$metadata_list;
	say "<table>";

	#Display required fields first
	foreach my $required ( 1, 0 ) {
		foreach my $field (@$field_list) {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			my $required_field = !( ( $thisfield->{'required'} // '' ) eq 'no' );
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			$required_field = 0 if !$set_id && defined $metaset;    #Field can't be compulsory if part of a metadata collection.
			if ( $required_field == $required ) {
				print "<tr><td style=\"text-align:right\">" . ( $metafield // $field ) . ": ";
				print '!' if $required;
				print "</td><td style=\"text-align:left\">";
				if ( $thisfield->{'optlist'} ) {
					my $optlist = $self->{'xmlHandler'}->get_field_option_list($field);
					say $q->popup_menu(
						-name    => $field,
						-values  => [ '', @$optlist ],
						-default => ( $newdata->{$field} // $thisfield->{'default'} )
					);
				} elsif ( $thisfield->{'type'} eq 'bool' ) {
					say $q->popup_menu(
						-name   => $field,
						-values => [ '', 'true', 'false' ],
						-default => ( $newdata->{$field} // $thisfield->{'default'} )
					);
				} elsif ( lc($field) ~~ [qw(datestamp date_entered)] ) {
					say "<b>" . $self->get_datestamp . "</b>";
				} elsif ( lc($field) eq 'curator' ) {
					say "<b>" . $self->get_curator_name . ' (' . $self->{'username'} . ")</b>";
				} elsif ( lc($field) ~~ [qw(sender sequenced_by)] || ( $thisfield->{'userfield'} // '' ) eq 'yes' ) {
					say $q->popup_menu(
						-name    => $field,
						-values  => [ '', @users ],
						-labels  => \%usernames,
						-default => ( $newdata->{$field} // $thisfield->{'default'} )
					);
				} else {
					if ( ( $thisfield->{'length'} // 0 ) > 60 ) {
						say $q->textarea(
							-name    => $field,
							-rows    => 3,
							-cols    => 40,
							-default => ( $newdata->{$field} // $thisfield->{'default'} )
						);
					} else {
						say $q->textfield(
							-name    => $field,
							-size    => $thisfield->{'length'},
							-default => ( $newdata->{$field} // $thisfield->{'default'} )
						);
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
	say $q->textarea( -name => 'aliases', -rows => 2, -cols => 12, -style => 'width:10em' );
	say "</td></tr>";
	say "<tr><td style=\"text-align:right\">PubMed ids: </td><td>";
	say $q->textarea( -name => 'pubmed', -rows => 2, -cols => 12, -style => 'width:10em' );
	say "</td></tr>";
	my $locus_buffer;

	if ( @$loci <= 100 ) {
		foreach my $locus (@$loci) {
			my $cleaned = $self->clean_locus($locus);
			$locus_buffer .= "<tr><td style=\"text-align:right\">$cleaned: </td><td style=\"white-space: nowrap\">";
			$locus_buffer .= $q->textfield( -name => "locus:$locus", -size => 10, -default => $newdata->{$locus} );
			$locus_buffer .=
			  $q->popup_menu( -name => "locus:$locus\_status", -values => [qw(confirmed provisional)], -default => $newdata->{$locus}, );
			$locus_buffer .= "</td></tr>";
		}
	} else {
		$locus_buffer .= "<tr><td style=\"text-align:right\">Loci: </td><td style=\"white-space: nowrap\">Too many to display. "
		  . "You can batch add allele designations after entering isolate provenace data.</td></tr>\n";
	}
	say "</table>";
	say "</fieldset>";
	say "<fieldset><legend>Allele designations</legend>\n<table>$locus_buffer</table></fieldset>" if @$loci;
	say "<div style=\"margin-bottom:2em\">\n<span style=\"float:left\"><a href=\"$self->{'system'}->{'script_name'}?"
	  . "db=$self->{'instance'}&amp;page=isolateAdd\" class=\"resetbutton\">Reset</a></span><span style=\"float:right\">";
	say $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
	say "</span></div>";
	say $q->end_form;
	say "</div></div>";
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Add new isolate - $desc";
}
1;
