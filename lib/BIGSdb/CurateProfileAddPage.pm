#Written by Keith Jolley
#Copyright (c) 2010-2014, University of Oxford
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
use Digest::MD5;
use Log::Log4perl qw(get_logger);
use List::MoreUtils qw(none any uniq);
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
	my ( $self, $value_ref ) = @_;
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
		$self->_clean_field( \$newdata->{"field:$field"} );
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
		$self->_clean_field( \$newdata->{"locus:$locus"} );
		my $field_bad = $self->is_locus_field_bad( $scheme_id, $locus, $newdata->{"locus:$locus"} );
		push @bad_field_buffer, $field_bad if $field_bad;
	}
	my @extra_inserts;
	my @new_pubmeds = split /\r?\n/, $q->param('pubmed');
	my $pubmed_error = 0;
	foreach my $new (@new_pubmeds) {
		chomp $new;
		next if $new eq '';
		if ( !BIGSdb::Utils::is_int($new) ) {
			push @bad_field_buffer, "PubMed ids must be integers" if !$pubmed_error;
			$pubmed_error = 1;
		} else {
			my $profile_id = $newdata->{"field:$primary_key"};
			$profile_id =~ s/'/\\'/g;
			push @extra_inserts, "INSERT INTO profile_refs (scheme_id,profile_id,pubmed_id,curator,datestamp) VALUES "
			  . "($scheme_id,E'$profile_id',$new,$newdata->{'field:curator'},'today')";
		}
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
		( my $cleaned_profile_id = $newdata->{"field:$primary_key"} ) =~ s/'/\\'/g;
		if ($insert) {
			my @inserts;
			my $qry;
			$qry = "INSERT INTO profiles (scheme_id,profile_id,sender,curator,date_entered,datestamp) VALUES "
			  . "($scheme_id,E'$cleaned_profile_id',$newdata->{'field:sender'},$newdata->{'field:curator'},'today','today')";
			push @inserts, $qry;
			foreach my $locus (@$loci) {
				( my $cleaned = $locus ) =~ s/'/\\'/g;
				$qry =
				    "INSERT INTO profile_members (scheme_id,locus,profile_id,allele_id,curator,datestamp) VALUES "
				  . "($scheme_id,E'$cleaned',E'$cleaned_profile_id',E'$newdata->{\"locus:$locus\"}',"
				  . "$newdata->{'field:curator'},'today')";
				push @inserts, $qry;
			}
			foreach my $field (@fields_with_values) {
				$qry =
				    "INSERT INTO profile_fields(scheme_id,scheme_field,profile_id,value,curator,datestamp) VALUES "
				  . "($scheme_id,E'$field',E'$cleaned_profile_id',E'$newdata->{\"field:$field\"}',"
				  . "$newdata->{'field:curator'},'today')";
				push @inserts, $qry;
			}
			push @inserts, @extra_inserts;
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
				$self->{'db'}->commit
				  && say "<div class=\"box\" id=\"resultsheader\"><p>$primary_key-$cleaned_profile_id added!</p>";
				say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=profileAdd&amp;scheme_id="
				  . "$scheme_id\">Add another</a> | <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">"
				  . "Back to main page</a></p></div>";
				$self->update_profile_history( $scheme_id, $newdata->{"field:$primary_key"}, "Profile added" );
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
	my ( @locus_temp, @values );
	foreach my $locus (@$loci) {
		next if $newdata->{"locus:$locus"} eq 'N';    #N can be any allele so can not be used to differentiate profiles
		( my $cleaned = $locus ) =~ s/'/\\'/g;
		push @locus_temp, "(locus=E'$cleaned' AND (allele_id=? OR allele_id='N'))";
		push @values,     $newdata->{"locus:$locus"};
	}
	local $" = ' OR ';
	$qry .= "(@locus_temp)";
	$qry .= ' GROUP BY profiles.profile_id having count(*)=' . scalar @locus_temp;

	#This may be called many times for batch inserts so cache query statements
	my $qry_hash = Digest::MD5::md5_hex($qry);
	if ( !$self->{'cache'}->{'sql'}->{$qry_hash} ) {
		$self->{'cache'}->{'sql'}->{$qry_hash} = $self->{'db'}->prepare($qry);
	}
	if (@locus_temp) {
		eval { $self->{'cache'}->{'sql'}->{$qry_hash}->execute(@values) };
		$logger->error($@) if $@;
		my @matching_profiles;
		while ( my ($match) = $self->{'cache'}->{'sql'}->{$qry_hash}->fetchrow_array ) {
			push @matching_profiles, $match;
		}
		$newdata->{"field:$primary_key"} //= '';
		if ( @matching_profiles && !( @matching_profiles == 1 && $matching_profiles[0] eq $newdata->{"field:$primary_key"} ) ) {
			if ( @locus_temp < @$loci ) {
				my $first_match;
				foreach (@matching_profiles) {
					if ( $_ ne $newdata->{"field:$primary_key"} ) {
						$first_match = $_;
						last;
					}
				}
				$msg .= "Profiles containing an arbitrary allele (N) at a particular locus may match profiles with actual values at "
				  . "that locus and cannot therefore be defined.  This profile matches $primary_key-$first_match";
				my $other_matches = @matching_profiles - 1;
				$other_matches-- if ( any { $newdata->{"field:$primary_key"} eq $_ } @matching_profiles );  #if updating don't match to self
				if ($other_matches) {
					$msg .= " and $other_matches other" . ( $other_matches > 1 ? 's' : '' );
				}
				$msg .= '.';
			} else {
				$msg .= "This allelic profile has already been defined as $primary_key-$matching_profiles[0].";
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
	say qq(<div class="box" id="queryform">);
	say qq(<div class="scrollable">);
	say "<p>Please fill in the fields below - required fields are marked with an exclamation mark (!).$msg</p>";
	say qq(<fieldset class="form" style="float:left"><legend>Record</legend>);
	my $qry = "select id,user_name,first_name,surname from users where id>0 order by surname";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error($@) if $@;
	my @users;
	my %usernames;
	my $loci         = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $fields       = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $longest_name = BIGSdb::Utils::get_largest_string_length( [ @$loci, @$fields ] );
	my $width        = int( 0.5 * $longest_name ) + 2;
	$width = 15 if $width > 15;
	$width = 6  if $width < 6;

	while ( my ( $userid, $username, $firstname, $surname ) = $sql->fetchrow_array ) {
		push @users, $userid;
		$usernames{$userid} = "$surname, $firstname ($username)";
	}
	$usernames{''} = ' ';    #Required for HTML5 validation.
	print $q->start_form;
	$q->param( sent => 1 );
	say $q->hidden($_) foreach qw (page db sent scheme_id);
	say qq(<ul style="white-space:nowrap">);
	my ( $label, $title ) = $self->get_truncated_label( $primary_key, 24 );
	my $title_attribute = $title ? " title=\"$title\"" : '';
	say qq(<li><label for="field:$primary_key" class="form" style="width:${width}em"$title_attribute>$label: !</label>);
	my $pk_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	my %html5_args = ( required => 'required' );
	$html5_args{'type'} = 'number' if $pk_field_info->{'type'} eq 'integer';
	say $self->textfield(
		-name  => "field:$primary_key",
		-id    => "field:$primary_key",
		-size  => $pk_field_info->{'type'} eq 'integer' ? 10 : 30,
		-value => $newdata->{$primary_key},
		%html5_args
	);
	say "</li>";

	foreach my $locus (@$loci) {
		%html5_args = ( required => 'required' );
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		$html5_args{'type'} = 'number' if $locus_info->{'allele_id_format'} eq 'integer' && !$scheme_info->{'allow_missing_loci'};
		my $cleaned = $self->clean_locus($locus);
		( $label, $title ) = $self->get_truncated_label( $cleaned, 24 );
		$title_attribute = $title ? " title=\"$title\"" : '';
		say qq(<li><label for="locus:$locus" class="form" style="width:${width}em"$title_attribute>$label: !</label>);
		say $self->textfield(
			-name  => "locus:$locus",
			-id    => "locus:$locus",
			-size  => 10,
			-value => $newdata->{"locus:$locus"},
			%html5_args
		);
		say "</li>";
	}
	say qq(<li><label for="field:sender" class="form" style="width:${width}em">sender: !</label>);
	say $self->popup_menu(
		-name    => 'field:sender',
		-id      => 'field:sender',
		-values  => [ '', @users ],
		-labels  => \%usernames,
		-default => $newdata->{'field:sender'}
	);
	say "</li>";
	foreach my $field (@$fields) {
		next if $field eq $primary_key;
		my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		%html5_args = ();
		$html5_args{'type'} = 'number' if $scheme_field_info->{'type'} eq 'integer';
		( $label, $title ) = $self->get_truncated_label( $field, 24 );
		$title_attribute = $title ? " title=\"$title\"" : '';
		say qq(<li><label for="field:$field" class="form" style="width:${width}em"$title_attribute>$label: </label>);
		say $self->textfield(
			-name  => "field:$field",
			-id    => "field:$field",
			-size  => $scheme_field_info->{'type'} eq 'integer' ? 10 : 50,
			-value => $newdata->{"field:$field"},
			%html5_args
		);
		say "</li>";
	}
	say qq(<li><label class="form" style="width:${width}em">curator: !</label><b>)
	  . $self->get_curator_name . ' ('
	  . $self->{'username'}
	  . ")</b></li>";
	say qq(<li><label class="form" style="width:${width}em">date_entered: !</label><b>) . $self->get_datestamp . "</b></li>";
	say qq(<li><label class="form" style="width:${width}em">datestamp: !</label><b>) . $self->get_datestamp . "</b></li>";
	say qq(<li><label for="pubmed" class="form" style="width:${width}em">PubMed ids:</label>);
	say $q->textarea( -name => 'pubmed', -id => 'pubmed', -rows => 2, -cols => 12, -style => 'width:10em' );
	say "</li></ul>";
	$self->print_action_fieldset( { scheme_id => $scheme_id } );
	say $q->end_form;
	say "</fieldset>";
	say "</div></div>";
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
	if ( !$self->{'cache'}->{'locus_info'}->{$locus} ) {    #may be called thousands of time during a batch add so cache.
		$self->{'cache'}->{'locus_info'}->{$locus} = $self->{'datastore'}->get_locus_info($locus);
	}
	my $locus_info = $self->{'cache'}->{'locus_info'}->{$locus};
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
	} else {
		if ( !defined $self->{'cache'}->{'seq_exists'}->{$locus}->{$value} ) {
			$self->{'cache'}->{'seq_exists'}->{$locus}->{$value} = $self->{'datastore'}->sequence_exists( $locus, $value );
		}
		if ( !$self->{'cache'}->{'seq_exists'}->{$locus}->{$value} ) {
			return "Allele $mapped $value has not been defined.";
		}
	}
	return;
}

sub define_missing_allele {
	my ( $self, $locus, $allele ) = @_;
	my $seq;
	if    ( $allele eq '0' ) { $seq = 'null allele' }
	elsif ( $allele eq 'N' ) { $seq = 'arbitrary allele' }
	else                     { return }
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

sub update_profile_history {
	my ( $self, $scheme_id, $profile_id, $action ) = @_;
	return if !$action || !$scheme_id || !$profile_id;
	my $curator_id = $self->get_curator_id;
	$action     =~ s/'/\\'/g;
	$profile_id =~ s/'/\\'/g;
	eval {
		$self->{'db'}->do(
"INSERT INTO profile_history (scheme_id,profile_id,timestamp,action,curator) VALUES ($scheme_id,E'$profile_id','now',E'$action',$curator_id)"
		);
	};
	if ($@) {
		$logger->error("Can't update history for scheme_id:$scheme_id profile:$profile_id '$action' $@");
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}
1;
