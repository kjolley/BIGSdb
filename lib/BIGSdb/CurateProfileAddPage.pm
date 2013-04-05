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
package BIGSdb::CurateProfileAddPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateAddPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant SUCCESS => 1;

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Add new profile - $desc";
}

sub print_content {
	my ($self)    = @_;
	my $scheme_id = $self->{'cgi'}->param('scheme_id');
	my $set_id    = $self->get_set_id;
	if ( !$self->{'datastore'}->scheme_exists($scheme_id) ) {
		say "<h1>Add new profile</h1>";
		say "<div class=\"box\" id=\"statusbad\"><p>Invalid scheme passed.</p></div>";
		return;
	} elsif ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say "<div class=\"box\" id=\"statusbad\"><p>You can only add profiles to a sequence/profile database - "
		  . "this is an isolate database.</p></div>";
		return;
	} elsif ( !$self->can_modify_table('profiles') ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to add new profiles.</p></div>";
		return;
	} elsif ($set_id) {
		if ( !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id ) ) {
			say "<div class=\"box\" id=\"statusbad\"><p>The selected scheme is inaccessible.</p></div>";
			return;
		}
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
	say "<h1>Add new $scheme_info->{'description'} profile</h1>";
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $primary_key;
	eval {
		$primary_key =
		  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )->[0];
	};
	if ( !$primary_key ) {
		say "<div class=\"box\" id=\"statusbad\"><p>This scheme doesn't have a primary key field defined.  Profiles can not be entered "
		  . "until this has been done.</p></div>";
		return;
	} elsif ( !@$loci ) {
		say "<div class=\"box\" id=\"statusbad\"><p>This scheme doesn't have any loci belonging to it.  Profiles can not be entered "
		  . "until there is at least one locus defined.</p></div>";
		return;
	}
	my %newdata;
	my $pk_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	my $q             = $self->{'cgi'};
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach my $field (@$scheme_fields) {
		my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		$newdata{"field:$field"} = $q->param("field:$field");
		if ( $field eq $primary_key && $pk_field_info->{'type'} eq 'integer' ) {
			$newdata{$primary_key} = $self->next_id( 'profiles', $scheme_id );
		}
	}
	if ( $q->param('sent') ) {
		return if $self->_upload( $scheme_id, $primary_key, \%newdata );
	}
	$self->_print_interface( $scheme_id, $primary_key, \%newdata );
	return;
}

sub _clean_field {
	my ($self, $value_ref) = @_;
	$$value_ref =~ s/\\/\\\\/g;
	$$value_ref =~ s/'/\\'/g;
	$$value_ref =~ s/^\s*//;
	$$value_ref =~ s/\s*$//;
	return;
}

sub _upload {
	my ( $self, $scheme_id, $primary_key, $newdata ) = @_;
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $q             = $self->{'cgi'};
	my @bad_field_buffer;
	my @fields_with_values;
	my $insert = 1;
	foreach my $field (@$scheme_fields) {
		$newdata->{"field:$field"} = $q->param("field:$field");
		$self->_clean_field(\$newdata->{"field:$field"});
		push @fields_with_values, $field if $newdata->{"field:$field"};
		my $field_bad = $self->_is_scheme_field_bad( $scheme_id, $field, $newdata->{"field:$field"} );
		if ($field_bad) {
			push @bad_field_buffer, $field_bad if $field_bad;
		}
	}
	$newdata->{"field:curator"} = $self->get_curator_id;
	$newdata->{"field:sender"}  = $q->param("field:sender");
	if ( !$newdata->{"field:sender"} ) {
		push @bad_field_buffer, "Field 'sender' requires a value.";
	} elsif ( !BIGSdb::Utils::is_int( $newdata->{'field:sender'} ) ) {
		push @bad_field_buffer, "Field 'sender' is invalid.";
	}
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	foreach my $locus (@$loci) {
		$newdata->{"locus:$locus"} = $q->param("locus:$locus");
		$self->_clean_field(\$newdata->{"locus:$locus"});
		my $field_bad = $self->is_locus_field_bad( $scheme_id, $locus, $newdata->{"locus:$locus"} );
		push @bad_field_buffer, $field_bad if $field_bad;
	}
	if (@bad_field_buffer) {
		say "<div class=\"box\" id=\"statusbad\"><p>There are problems with your record submission.  Please address the following:</p>";
		local $" = '<br />';
		say "<p>@bad_field_buffer</p></div>";
		$insert = 0;
	}

	#Make sure profile not already entered
	if ($insert) {
		my ( $exists, $msg ) = $self->profile_exists( $scheme_id, $primary_key, $newdata );
		say "<div class=\"box\" id=\"statusbad\"><p>$msg</p></div>" if $msg;
		$insert = 0 if $exists;
	}
	if ($insert) {
		my $pk_exists = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM profiles WHERE scheme_id=? AND profile_id=?",
			$scheme_id, $newdata->{"field:$primary_key"} )->[0];
		if ($pk_exists) {
			say "<div class=\"box\" id=\"statusbad\"><p>$primary_key-$newdata->{\"field:$primary_key\"} has already been defined - "
			  . "please choose a different $primary_key.</p></div>";
			$insert = 0;
		}
		my $sender_exists =
		  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM users WHERE id=?", $newdata->{'field:sender'} )->[0];
		if ( !$sender_exists ) {
			say "<div class=\"box\" id=\"statusbad\"><p>Invalid sender set.</p></div>";
			$insert = 0;
		}
		if ($insert) {
			my @inserts;
			my $qry;
			$qry = "INSERT INTO profiles (scheme_id,profile_id,sender,curator,date_entered,datestamp) VALUES "
			  . "($scheme_id,'$newdata->{\"field:$primary_key\"}',$newdata->{'field:sender'},$newdata->{'field:curator'},'today','today')";
			push @inserts, $qry;
			foreach my $locus (@$loci) {
				( my $cleaned = $locus ) =~ s/'/\\'/g;
				$qry =
				    "INSERT INTO profile_members (scheme_id,locus,profile_id,allele_id,curator,datestamp) VALUES "
				  . "($scheme_id,E'$cleaned','$newdata->{\"field:$primary_key\"}',E'$newdata->{\"locus:$locus\"}',"
				  . "$newdata->{'field:curator'},'today')";
				push @inserts, $qry;
			}
			foreach my $field (@fields_with_values) {
				$qry =
				    "INSERT INTO profile_fields(scheme_id,scheme_field,profile_id,value,curator,datestamp) VALUES "
				  . "($scheme_id,E'$field','$newdata->{\"field:$primary_key\"}',E'$newdata->{\"field:$field\"}',"
				  . "$newdata->{'field:curator'},'today')";
				push @inserts, $qry;
			}
			local $" = ';';
			eval {
				$self->{'db'}->do("@inserts");
				$self->refresh_material_view($scheme_id);
			};
			if ($@) {
				say "<div class=\"box\" id=\"statusbad\"><p>Insert failed - transaction cancelled - no records have been touched.</p>";
				if ( $@ =~ /duplicate/ && $@ =~ /unique/ ) {
					say "<p>Data entry would have resulted in records with either duplicate ids or another unique field with "
					  . "duplicate values.</p>";
				} else {
					$logger->error("Insert failed: @inserts  $@");
				}
				say "</div>";
				$self->{'db'}->rollback;
			} else {
				$newdata->{"field:$primary_key"} =~ s/\\'/'/g;
				$self->{'db'}->commit
				  && say "<div class=\"box\" id=\"resultsheader\"><p>$primary_key-$newdata->{\"field:$primary_key\"} added!</p>";
				say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=profileAdd&amp;scheme_id="
				  . "$scheme_id\">Add another</a> | <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">"
				  . "Back to main page</a></p></div>";
				return SUCCESS;
			}
		}
	}
	return;
}

sub profile_exists {
	my ( $self, $scheme_id, $primary_key, $newdata ) = @_;
	my ( $profile_exists, $msg );
	my $qry = "SELECT profiles.profile_id FROM profiles LEFT JOIN profile_members ON profiles.scheme_id = "
	  . "profile_members.scheme_id AND profiles.profile_id = profile_members.profile_id WHERE profiles.scheme_id=$scheme_id AND ";
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my @locus_temp;
	foreach my $locus (@$loci) {
		next if $newdata->{"locus:$locus"} eq 'N';    #N can be any allele so can not be used to differentiate profiles
		( my $cleaned = $locus ) =~ s/'/\\'/g;
		my $value = $newdata->{"locus:$locus"};
		$value =~ s/'/\\'/g;
		push @locus_temp, "(locus=E'$cleaned' AND (allele_id=E'$value' OR allele_id='N'))";
	}
	local $" = ' OR ';
	$qry .= "(@locus_temp)";
	$qry .= ' GROUP BY profiles.profile_id having count(*)=' . scalar @locus_temp;
	if (@locus_temp) {
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute };
		$logger->error($@) if $@;
		my ($value) = $sql->fetchrow_array;
		if ($value) {
			if ( @locus_temp < @$loci ) {
				$msg .= "Profiles containing an arbitrary allele (N) at a particular locus may match profiles with actual values at "
				  . "that locus and cannot therefore be defined.  This profile matches $primary_key-$value (possibly others too).";
			} else {
				$msg .= "This allelic profile has already been defined as $primary_key-$value.";
			}
			$profile_exists = 1;
		}
	} else {
		$msg .= "You cannot define a profile with every locus set to be an arbitrary value (N).";
		$profile_exists = 1;
	}
	return ( $profile_exists, $msg );
}

sub _print_interface {
	my ( $self, $scheme_id, $primary_key, $newdata ) = @_;
	my $q           = $self->{'cgi'};
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
	my $msg =
	  $scheme_info->{'allow_missing_loci'}
	  ? " This scheme allows profile definitions to contain missing alleles (designate "
	  . "these as '0') or ignored alleles (designate these as 'N')."
	  : '';
	say "<div class=\"box\" id=\"queryform\"><p>Please fill in the fields below - required fields are marked with an "
	  . "exclamation mark (!).$msg</p>";
	my $qry = "select id,user_name,first_name,surname from users where id>0 order by surname";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error($@) if $@;
	my @users;
	my %usernames;

	while ( my ( $userid, $username, $firstname, $surname ) = $sql->fetchrow_array ) {
		push @users, $userid;
		$usernames{$userid} = "$surname, $firstname ($username)";
	}
	print $q->start_form;
	$q->param( 'sent', 1 );
	say $q->hidden($_) foreach qw (page db sent scheme_id);
	say "<table>";
	say "<tr><td style=\"text-align: right\">$primary_key: !</td><td style=\"white-space: nowrap\">";
	my $pk_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	say $q->textfield(
		-name    => "field:$primary_key",
		-size    => $pk_field_info->{'type'} eq 'integer' ? 10 : 30,
		-default => $newdata->{$primary_key},
	);
	say "</td></tr>";
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);

	foreach my $locus (@$loci) {
		my $cleaned = $self->clean_locus($locus);
		say "<tr><td style=\"text-align:right\">$cleaned: !</td><td style=\"white-space: nowrap\">";
		say $q->textfield( -name => "locus:$locus", -size => 10, -default => $newdata->{$locus} );
		say "</td></tr>";
	}
	say "<tr><td style=\"text-align:right\">sender: !</td><td style=\"white-space: nowrap\">";
	say $q->popup_menu( -name => 'field:sender', -values => [ '', @users ], -labels => \%usernames, -default => $newdata->{'sender'} );
	say "</td></tr>";
	my $fields =
	  $self->{'datastore'}
	  ->run_list_query( "SELECT field FROM scheme_fields WHERE scheme_id=? AND NOT primary_key ORDER BY field_order", $scheme_id );
	foreach my $field (@$fields) {
		say "<tr><td style=\"text-align: right\">$field: </td><td style=\"white-space: nowrap\">";
		my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		say $q->textfield( -name => "field:$field", -size => $field_info->{'type'} eq 'integer' ? 10 : 30, -default => $newdata->{$field} );
		say "</td></tr>";
	}
	say "<tr><td style=\"text-align:right\">curator: </td><td style=\"white-space: nowrap\"><b>"
	  . $self->get_curator_name . ' ('
	  . $self->{'username'}
	  . ")</b></td></tr>";
	say "<tr><td style=\"text-align:right\">date_entered: </td><td style=\"white-space: nowrap\"><b>"
	  . $self->get_datestamp
	  . "</b></td></tr>";
	say "<tr><td style=\"text-align:right\">datestamp: </td><td style=\"white-space: nowrap\"><b>"
	  . $self->get_datestamp
	  . "</b></td></tr>";
	say "<tr><td>";
	say "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=profileAdd&amp;scheme_id=$scheme_id\" "
	  . "class=\"resetbutton\">Reset</a>";
	say "</td><td style=\"text-align:right; padding-left:2em\">";
	say $q->submit( -name => 'Submit', -class => 'submit' );
	say "</td></tr></table>";
	say $q->end_form;
	say "</div>";
	return;
}

sub _is_scheme_field_bad {
	my ( $self, $scheme_id, $field, $value ) = @_;
	my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
	if ( $scheme_field_info->{'primary_key'} && $value eq '' ) {
		return "Field '$field' is the primary key and requires a value.";
	} elsif ( $value ne ''
		&& $scheme_field_info->{'type'} eq 'integer'
		&& !BIGSdb::Utils::is_int($value) )
	{
		return "Field '$field' must be an integer.";
	} elsif ( $value ne '' && $scheme_field_info->{'value_regex'} && $value !~ /$scheme_field_info->{'value_regex'}/ ) {
		return "Field value is invalid - it must match the regular expression /$scheme_field_info->{'value_regex'}/.";
	}
}

sub is_locus_field_bad {
	my ( $self, $scheme_id, $locus, $value ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $set_id     = $self->get_set_id;
	my $mapped     = $self->{'datastore'}->get_set_locus_label( $locus, $set_id ) // $locus;
	if ( !defined $value || $value eq '' ) {
		return "Locus '$mapped' requires a value.";
	} elsif ( $value eq '0' || $value eq 'N' ) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
		if ( $scheme_info->{'allow_missing_loci'} ) {
			if ( !$self->{'datastore'}->sequence_exists( $locus, $value ) ) {
				$self->define_missing_allele( $locus, $value );
			}
			return;
		} else {
			return "Allele id value is invalid - this scheme does not allow missing (0) or arbitrary alleles (N) in the profile.";
		}
	} elsif ( $locus_info->{'allele_id_format'} eq 'integer' && !BIGSdb::Utils::is_int($value) ) {
		return "Locus '$mapped' must be an integer.";
	} elsif ( $locus_info->{'allele_id_regex'} && $value !~ /$locus_info->{'allele_id_regex'}/ ) {
		return "Allele id value is invalid - it must match the regular expression /$locus_info->{'allele_id_regex'}/.";
	} elsif ( !$self->{'datastore'}->sequence_exists( $locus, $value ) ) {
		return "Allele $mapped $value has not been defined.";
	}
	return;
}

sub define_missing_allele {
	my ( $self, $locus, $allele ) = @_;
	my $seq;
	given ($allele) {
		when ('0') { $seq = 'null allele' };
		when ('N') { $seq = 'arbitrary allele' }
		default    { return }
	}
	my $sql =
	  $self->{'db'}->prepare( "INSERT INTO sequences (locus, allele_id, sequence, sender, curator, date_entered, datestamp, "
		  . "status) VALUES (?,?,?,?,?,?,?,?)" );
	eval { $sql->execute( $locus, $allele, $seq, 0, 0, 'now', 'now', '' ) };
	if ($@) {
		$logger->error($@) if $@;
		$self->{'db'}->rollback;
		return;
	}
	$self->{'db'}->commit;
	return;
}
1;
