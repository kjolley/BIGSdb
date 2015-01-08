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
package BIGSdb::CurateIsolateAddPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateAddPage);
use List::MoreUtils qw(any none uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant SUCCESS => 1;

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/curator_guide.html#adding-isolate-records";
}

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
	my $user_info     = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
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
				} elsif ( $field eq 'sender' && $user_info->{'status'} eq 'submitter' ) {
					$newdata->{$field} = $self->get_curator_id;
				} elsif ( $field eq 'datestamp' || $field eq 'date_entered' ) {
					$newdata->{$field} = $self->get_datestamp;
				} else {
					$newdata->{$field} = $q->param($field);
				}
				my $bad_field = $self->is_field_bad( 'isolates', $field, $newdata->{$field} );
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
	my @inserts;    #TODO Rewrite to use placeholders
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
	foreach my $locus (@$loci) {
		if ( $q->param("locus:$locus") ) {
			$qry =
			    "INSERT INTO allele_designations (isolate_id,locus,allele_id,sender,status,method,curator,date_entered,datestamp) "
			  . "VALUES ($newdata->{'id'},E'$locus',E'$newdata->{\"locus:$locus\"}',$newdata->{'sender'},'confirmed',"
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
	my $q = $self->{'cgi'};
	say "<div class=\"box\" id=\"queryform\"><p>Please fill in the fields below - required fields are "
	  . "marked with an exclamation mark (!).</p>";
	say "<div class=\"scrollable\">";
	say $q->start_form;
	$q->param( 'sent', 1 );
	say $q->hidden($_) foreach qw(page db sent);
	$self->print_provenance_form_elements($newdata);
	$self->_print_allele_designation_form_elements($newdata);
	$self->print_action_fieldset;
	say $q->end_form;
	say "</div></div>";
	return;
}

sub print_provenance_form_elements {
	my ( $self, $newdata, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q         = $self->{'cgi'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my ( @users, %usernames );
	my $user_data;
	if ( $user_info->{'status'} eq 'submitter' ) {
		$user_data = $self->{'datastore'}->run_query(
			"SELECT id,user_name,first_name,surname FROM users WHERE id=? OR id IN (SELECT user_id FROM user_group_members WHERE "
			  . "user_group IN (SELECT user_group FROM user_group_members WHERE user_id=?)) ORDER BY surname, first_name, user_name",
			[ $user_info->{'id'}, $user_info->{'id'} ],
			{ fetch => 'all_arrayref', slice => {} }
		);
	} else {
		$user_data =
		  $self->{'datastore'}
		  ->run_query( "SELECT id,user_name,first_name,surname FROM users WHERE id>0 ORDER BY surname, first_name, user_name",
			undef, { fetch => 'all_arrayref', slice => {} } );
	}
	foreach (@$user_data) {
		push @users, $_->{'id'};
		$usernames{ $_->{'id'} } = "$_->{'surname'}, $_->{'first_name'} ($_->{'user_name'})";
	}
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata( $set_id, { curate => 1 } );
	my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
	say qq(<fieldset style="float:left"><legend>Isolate fields</legend>);
	say qq(<div style="white-space:nowrap">);
	say qq(<p><span class="metaset">Metadata</span><span class="comment">: These fields are available in the specified dataset )
	  . qq(only.</span></p>)
	  if !$set_id && @$metadata_list;
	my $longest_name = BIGSdb::Utils::get_largest_string_length($field_list);
	my $width        = int( 0.5 * $longest_name ) + 2;
	$width = 15 if $width > 15;
	$width = 6  if $width < 6;
	say "<ul>";

	#Display required fields first
	foreach my $required ( 1, 0 ) {
		foreach my $field (@$field_list) {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			my $required_field = !( ( $thisfield->{'required'} // '' ) eq 'no' );
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			$required_field = 0 if !$set_id && defined $metaset;    #Field can't be compulsory if part of a metadata collection.
			if ( $required_field == $required ) {
				my %html5_args;
				$html5_args{'required'} = 'required' if $required_field;
				$html5_args{'type'} = 'date' if $thisfield->{'type'} eq 'date' && !$thisfield->{'optlist'};
				if ( $field ne 'sender' && $thisfield->{'type'} eq 'int' && !$thisfield->{'optlist'} ) {
					$html5_args{'type'} = 'number';
					$html5_args{'min'}  = '1';
					$html5_args{'step'} = '1';
				}
				$html5_args{'min'} = $thisfield->{'min'} if $thisfield->{'type'} eq 'int' && defined $thisfield->{'min'};
				$html5_args{'max'} = $thisfield->{'max'} if $thisfield->{'type'} eq 'int' && defined $thisfield->{'min'};
				$html5_args{'pattern'} = $thisfield->{'regex'} if $thisfield->{'regex'};
				$thisfield->{'length'} = $thisfield->{'length'} // ( $thisfield->{'type'} eq 'int' ? 15 : 50 );
				( my $cleaned_name = $metafield // $field ) =~ tr/_/ /;
				my ( $label, $title ) = $self->get_truncated_label( $cleaned_name, 25 );
				my $title_attribute = $title ? " title=\"$title\"" : '';
				my $for =
				  ( none { $field eq $_ } qw (curator date_entered datestamp) )
				  ? " for=\"$field\""
				  : '';
				print "<li><label$for class=\"form\" style=\"width:${width}em\"$title_attribute>";
				print $label;
				print ':';
				print '!' if $required;
				say "</label>";

				if ( $field eq 'id' && $q->param('page') eq 'isolateUpdate' ) {
					say "<b>$newdata->{'id'}</b>";
					say $q->hidden('id');
				} elsif ( $thisfield->{'optlist'} ) {
					my $optlist = $self->{'xmlHandler'}->get_field_option_list($field);
					say $q->popup_menu(
						-name    => $field,
						-id      => $field,
						-values  => [ '', @$optlist ],
						-default => ( $newdata->{ lc($field) } // $thisfield->{'default'} ),
						%html5_args
					);
				} elsif ( $thisfield->{'type'} eq 'bool' ) {
					say $q->popup_menu(
						-name   => $field,
						-id     => $field,
						-values => [ '', 'true', 'false' ],
						-default => ( $newdata->{ lc($field) } // $thisfield->{'default'} )
					);
				} elsif ( lc($field) eq 'datestamp' ) {
					say "<b>" . $self->get_datestamp . "</b>";
				} elsif ( lc($field) eq 'date_entered' ) {
					if ( $options->{'update'} ) {
						say "<b>$newdata->{'date_entered'}</b>";
						say $q->hidden( 'date_entered', $newdata->{'date_entered'} );
					} else {
						say "<b>" . $self->get_datestamp . "</b>";
					}
				} elsif ( lc($field) eq 'curator' ) {
					say "<b>" . $self->get_curator_name . ' (' . $self->{'username'} . ")</b>";
				} elsif ( lc($field) eq 'sender' && $user_info->{'status'} eq 'submitter' && !$options->{'update'} ) {
					say "<b>" . $self->get_curator_name . ' (' . $self->{'username'} . ")</b>";
				} elsif ( lc($field) eq 'sender' || lc($field) eq 'sequenced_by' || ( $thisfield->{'userfield'} // '' ) eq 'yes' ) {
					say $q->popup_menu(
						-name    => $field,
						-id      => $field,
						-values  => [ '', @users ],
						-labels  => \%usernames,
						-default => ( $newdata->{ lc($field) } // $thisfield->{'default'} ),
						%html5_args
					);
				} else {
					if ( ( $thisfield->{'length'} // 0 ) > 60 ) {
						say $q->textarea(
							-name    => $field,
							-id      => $field,
							-rows    => 3,
							-cols    => 40,
							-default => ( $newdata->{ lc($field) } // $thisfield->{'default'} ),
							%html5_args
						);
					} else {
						say $self->textfield(
							name      => $field,
							id        => $field,
							size      => $thisfield->{'length'},
							maxlength => $thisfield->{'length'},
							value     => ( $newdata->{ lc($field) } // $thisfield->{'default'} ),
							%html5_args
						);
					}
				}
				say qq( <span class="metaset">Metadata: $metaset</span>) if !$set_id && defined $metaset;
				if ( $thisfield->{'comments'} ) {
					say qq(<a class="tooltip" title="$thisfield->{'comments'}">&nbsp;<i>i</i>&nbsp;</a>&nbsp;);
				}
				if ( ( none { lc($field) eq $_ } qw(datestamp date_entered) ) && lc( $thisfield->{'type'} ) eq 'date' ) {
					say " format: yyyy-mm-dd";
				}
				say "</li>";
			}
		}
	}
	my $aliases;
	if ( $options->{'update'} ) {
		$aliases = $self->{'datastore'}->get_isolate_aliases( $q->param('id') );
	} else {
		$aliases = [];
	}
	say qq(<li><label for="aliases" class="form" style="width:${width}em">aliases:&nbsp;</label>);
	local $" = "\n";
	say $q->textarea( -name => 'aliases', -id => 'aliases', -rows => 2, -cols => 12, -style => 'width:10em', -default => "@$aliases" );
	say "</li>";
	my $pubmed;
	if ( $options->{'update'} ) {
		$pubmed = $self->{'datastore'}->get_isolate_refs( $q->param('id') );
	} else {
		$pubmed = [];
	}
	say qq(<li><label for="pubmed" class="form" style="width:${width}em">PubMed ids:&nbsp;</label>);
	say $q->textarea( -name => 'pubmed', -id => 'pubmed', -rows => 2, -cols => 12, -style => 'width:10em', -default => "@$pubmed" );
	say "</li>";
	say "</ul>";
	if ( $options->{'update'} ) {
		$self->print_action_fieldset( { submit_label => 'Update', id => $newdata->{'id'} } );
	}
	say "</div></fieldset>";
	return;
}

sub _print_allele_designation_form_elements {
	my ( $self, $newdata ) = @_;
	my $locus_buffer;
	my $set_id = $self->get_set_id;
	my $q      = $self->{'cgi'};
	my $loci   = $self->{'datastore'}->get_loci( { query_pref => 1, set_id => $set_id } );
	@$loci = uniq @$loci;
	my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	my $schemes_with_display_order = any { defined $_->{'display_order'} } @$schemes;

	if ( @$loci <= 100 ) {
		foreach my $scheme (@$schemes) {
			$locus_buffer .= $self->_print_scheme_form_elements( $scheme->{'id'}, $newdata );
		}
		$locus_buffer .= $self->_print_scheme_form_elements( 0, $newdata );
	} elsif ($schemes_with_display_order) {
		foreach my $scheme (@$schemes) {
			next if !defined $scheme->{'display_order'};
			$locus_buffer .= $self->_print_scheme_form_elements( $scheme->{'id'}, $newdata );
		}
	} else {
		$locus_buffer .= "<p>Too many to display. You can batch add allele designations after entering isolate provenace data.</p>\n";
	}
	if (@$loci) {
		say "<div id=\"scheme_loci_add\" style=\"overflow:auto\">";
		say "<fieldset style=\"float:left\"><legend>Allele&nbsp;designations</legend>\n$locus_buffer</fieldset>";
		say "</div>";
	}
	return;
}

sub _print_scheme_form_elements {
	my ( $self, $scheme_id, $newdata ) = @_;
	my $q      = $self->{'cgi'};
	my $set_id = $self->get_set_id;
	my $loci;
	my $buffer = '';
	if ($scheme_id) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
		$loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
		$buffer = @$loci ? "<h3 class=\"scheme\" style=\"clear:both\">$scheme_info->{'description'}</h3>\n" : '';
	} else {
		$loci = $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
		$buffer = @$loci ? "<h3 class=\"scheme\" style=\"clear:both\">Loci not in a scheme</h3>\n" : '';
	}
	foreach my $locus (@$loci) {
		my $cleaned_name = $self->clean_locus($locus);
		$buffer .= "<dl class=\"profile\">";
		$buffer .= "<dt>$cleaned_name</dt><dd>";
		$buffer .= $q->textfield( -name => "locus:$locus", -id => "locus:$locus", -size => 10, -default => $newdata->{$locus} );
		$buffer .= "</dd></dl>";
	}
	return $buffer;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Add new isolate - $desc";
}
1;
