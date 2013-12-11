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
package BIGSdb::CurateProfileUpdatePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateProfileAddPage);
use List::MoreUtils qw(none);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say "<h1>Update profile</h1>";
	my ( $scheme_id, $profile_id ) = ( $q->param('scheme_id'), $q->param('profile_id') );
	if ( !$scheme_id ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No scheme_id passed.</p></div>";
		return;
	} elsif ( !BIGSdb::Utils::is_int($scheme_id) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Scheme_id must be an integer.</p></div>";
		return;
	} elsif ( !$profile_id ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No profile_id passed.</p></div>";
		return;
	} elsif ( !$self->can_modify_table('profiles') ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to modify profiles.</p></div>";
		return;
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
	my $qry         = "SELECT * FROM profiles WHERE scheme_id=? AND profile_id=?";
	my $sql         = $self->{'db'}->prepare($qry);
	eval { $sql->execute( $scheme_id, $profile_id ) };
	$logger->error($@) if $@;
	my $profile_data = $sql->fetchrow_hashref;
	if ( !$profile_data->{'profile_id'} ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No profile from scheme $scheme_id ($scheme_info->{'description'}) with profile_id "
		  . "= '$profile_id' exists.</p></div>";
		return;
	}
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $allele_qry    = "SELECT allele_id FROM profile_members WHERE scheme_id=? AND locus=? AND profile_id=?";
	my $allele_sql    = $self->{'db'}->prepare($allele_qry);
	my $allele_data;
	foreach my $locus (@$loci) {
		eval { $allele_sql->execute( $scheme_id, $locus, $profile_id ) };
		if ($@) {
			$logger->error("Can't execute allele check");
		} else {
			( $allele_data->{$locus} ) = $allele_sql->fetchrow_array;
		}
	}
	my $field_qry = "SELECT value FROM profile_fields WHERE scheme_id=? AND scheme_field=? AND profile_id=?";
	my $field_sql = $self->{'db'}->prepare($field_qry);
	my $field_data;
	foreach my $field (@$scheme_fields) {
		eval { $field_sql->execute( $scheme_id, $field, $profile_id ) };
		if ($@) {
			$logger->error("Can't execute field check");
		} else {
			( $field_data->{$field} ) = $field_sql->fetchrow_array;
		}
	}
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
	my $pk_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	my $args = {
		scheme_id    => $scheme_id,
		primary_key  => $primary_key,
		profile_id   => $profile_id,
		profile_data => $profile_data,
		field_data   => $field_data,
		allele_data  => $allele_data
	};
	if ( $q->param('sent') ) {
		$self->_update($args);
	}
	$self->_print_interface($args);
	return;
}

sub _update {
	my ( $self, $args ) = @_;
	my ( $scheme_id, $primary_key, $profile_id, $allele_data, $field_data, $profile_data ) =
	  @{$args}{qw(scheme_id primary_key profile_id allele_data field_data profile_data)};
	my %newdata;
	my @bad_field_buffer;
	my $update = 1;
	my ( %locus_changed, %field_changed );
	my $q               = $self->{'cgi'};
	my $loci            = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields   = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $profile_changed = 0;
	my $set_id          = $self->get_set_id;

	foreach my $locus (@$loci) {
		$newdata{"locus:$locus"} = $q->param("locus:$locus");
		$self->_clean_field( \$newdata{"locus:$locus"} );
		my $field_bad = $self->is_locus_field_bad( $scheme_id, $locus, $newdata{"locus:$locus"} );
		push @bad_field_buffer, $field_bad if $field_bad;
		if ( $allele_data->{$locus} ne $newdata{"locus:$locus"} ) {
			$locus_changed{$locus} = 1;
			$profile_changed = 1;
		}
	}
	if ( !@bad_field_buffer && $profile_changed ) {
		$newdata{"field:$primary_key"} = $profile_id;
		my ( $exists, $msg ) = $self->profile_exists( $scheme_id, $primary_key, \%newdata );
		push @bad_field_buffer, $msg if $exists;
	}
	foreach my $field (@$scheme_fields) {
		next if $field eq $primary_key;
		$newdata{"field:$field"} = $q->param("field:$field");
		$self->_clean_field( \$newdata{"field:$field"} );
		my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		if ( $field_info->{'type'} eq 'integer' && $newdata{"field:$field"} ne '' && !BIGSdb::Utils::is_int( $newdata{"field:$field"} ) ) {
			push @bad_field_buffer, "Field '$field' must be an integer.";
		}
		$field_data->{$field} = defined $field_data->{$field} ? $field_data->{$field} : '';
		if ( $field_data->{$field} ne $newdata{"field:$field"} ) {
			$field_changed{$field} = 1;
		}
	}
	$newdata{"field:sender"} = $q->param("field:sender");
	if ( !BIGSdb::Utils::is_int( $newdata{'field:sender'} ) ) {
		push @bad_field_buffer, "Field 'sender' is invalid.";
	}
	if ( $profile_data->{'sender'} ne $newdata{'field:sender'} ) {
		$field_changed{'sender'} = 1;
	}
	my @extra_inserts;
	(my $cleaned_profile_id = $profile_id) =~ s/'/\\'/g;
	my $curator_id = $self->get_curator_id;
	my $existing_pubmeds =
	  $self->{'datastore'}
	  ->run_list_query( "SELECT pubmed_id FROM profile_refs WHERE scheme_id=? AND profile_id=?", $scheme_id, $profile_id );
	my @new_pubmeds = split /\r?\n/, $q->param('pubmed');
	my $pubmed_error = 0;
	my @updated_field;

	foreach my $new (@new_pubmeds) {
		chomp $new;
		next if $new eq '';
		if ( !@$existing_pubmeds || none { $new eq $_ } @$existing_pubmeds ) {
			if ( !BIGSdb::Utils::is_int($new) ) {
				push @bad_field_buffer, "PubMed ids must be integers.</p>" if !$pubmed_error;
				$pubmed_error = 1;
			}
			push @extra_inserts, "INSERT INTO profile_refs (scheme_id,profile_id,pubmed_id,curator,datestamp) "
			  . "VALUES ($scheme_id,E'$cleaned_profile_id',$new,$curator_id,'today')";
			push @updated_field, "new reference: 'Pubmed#$new'";
		}
	}
	foreach my $existing (@$existing_pubmeds) {
		if ( !@new_pubmeds || none { $existing eq $_ } @new_pubmeds ) {
			push @extra_inserts, "DELETE FROM profile_refs WHERE scheme_id=scheme_id AND profile_id=E'$cleaned_profile_id' AND pubmed_id=$existing";
			push @updated_field, "deleted reference: 'Pubmed#$existing'";
		}
	}
	if (@bad_field_buffer) {
		say "<div class=\"box\" id=\"statusbad\"><p>There are problems with your record submission.  "
		  . "Please address the following:</p>";
		local $" = '<br />';
		say "<p>@bad_field_buffer</p></div>";
	} elsif ( !%locus_changed && !%field_changed && !@extra_inserts ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No fields were changed.</p></div>";
	} else {
		my $success = 1;
		foreach my $locus ( keys %locus_changed ) {
			my $sql_update =
			  $self->{'db'}
			  ->prepare("UPDATE profile_members SET allele_id=?,datestamp=?,curator=? WHERE scheme_id=? AND locus=? AND profile_id=?");
			eval { $sql_update->execute( $newdata{"locus:$locus"}, 'today', $curator_id, $scheme_id, $locus, $profile_id ); };
			if ($@) {
				$logger->error($@);
				$self->{'db'}->rollback;
				$success = 0;
			}
			push @updated_field, "$locus: '$allele_data->{$locus}' -> '$newdata{\"locus:$locus\"}'";
		}
		if ($success) {
			foreach my $field ( keys %field_changed ) {
				if ( $field eq 'sender' ) {
					my $sql_update =
					  $self->{'db'}->prepare("UPDATE profiles SET sender=?,datestamp=?,curator=? WHERE scheme_id=? AND profile_id=?");
					eval { $sql_update->execute( $newdata{"field:sender"}, 'today', $curator_id, $scheme_id, $profile_id ); };
					if ($@) {
						$logger->error($@);
						$self->{'db'}->rollback;
						$success = 0;
					}
					push @updated_field, "$field: '$profile_data->{$field}' -> '$newdata{\"field:$field\"}'";
				} else {
					if ( defined $field_data->{$field} && $field_data->{$field} ne '' ) {
						if ( $newdata{"field:$field"} eq '' ) {
							my $sql_update =
							  $self->{'db'}->prepare("DELETE FROM profile_fields WHERE scheme_id=? AND scheme_field=? AND profile_id=?");
							eval { $sql_update->execute( $scheme_id, $field, $profile_id ); };
						} else {
							my $sql_update =
							  $self->{'db'}->prepare( "UPDATE profile_fields SET value=?,datestamp=?,curator=? WHERE scheme_id=? "
								  . "AND scheme_field=? AND profile_id=?" );
							eval {
								$sql_update->execute( $newdata{"field:$field"}, 'today', $curator_id, $scheme_id, $field, $profile_id );
							};
						}
						if ($@) {
							$logger->error($@);
							$self->{'db'}->rollback;
							$success = 0;
						}
					} else {
						my $sql_update =
						  $self->{'db'}->prepare(
							"INSERT INTO profile_fields (scheme_id,scheme_field,profile_id,value,curator,datestamp) VALUES (?,?,?,?,?,?)");
						eval { $sql_update->execute( $scheme_id, $field, $profile_id, $newdata{"field:$field"}, $curator_id, 'today' ) };
						if ($@) {
							$logger->error($@);
							$self->{'db'}->rollback;
							$success = 0;
						}
					}
					push @updated_field, "$field: '$field_data->{$field}' -> '$newdata{\"field:$field\"}'";
				}
			}
		}
		if ( $success && ( keys %locus_changed || keys %field_changed ) ) {
			my $sql_update = $self->{'db'}->prepare("UPDATE profiles SET datestamp=?,curator=? WHERE scheme_id=? AND profile_id=?");
			eval { $sql_update->execute( 'today', $curator_id, $scheme_id, $profile_id ); };
			if ($@) {
				$logger->error($@);
				$self->{'db'}->rollback;
				$success = 0;
			}
		}
		if ($success) {
			local $" = ';';
			eval { $self->{'db'}->do("@extra_inserts") };
			if ($@) {
				$logger->error($@);
				$self->{'db'}->rollback;
				$success = 0;
			}
		}
		if ($success) {
			$self->refresh_material_view($scheme_id);
			$self->{'db'}->commit;
			say "<div class=\"box\" id=\"resultsheader\"><p>Updated!</p>";
			say "<p><a href=\"" . $q->script_name . "?db=$self->{'instance'}\">Back to main page</a></p></div>";
			$logger->info("Updated profile scheme_id:$scheme_id profile_id:$profile_id");
			local $" = '<br />';
			$self->update_profile_history( $scheme_id, $profile_id, "@updated_field" );
			return;
		} else {
			say "<div class=\"box\" id=\"statusbad\"><p>Update failed - transaction cancelled - no records have been touched.</p></div>";
			$logger->error("Can't update profile: $@");
		}
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Update profile - $desc";
}

sub _print_interface {
	my ( $self, $args ) = @_;
	my ( $scheme_id, $profile_id, $profile_data, $field_data, $primary_key, $allele_data ) =
	  @{$args}{qw(scheme_id profile_id profile_data field_data primary_key allele_data)};
	my $q           = $self->{'cgi'};
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
	say qq(<div class="box" id="queryform">);
	say qq(<div class="scrollable" style="white-space:nowrap">);
	my $qry = "select id,user_name,first_name,surname from users WHERE id>0 order by surname";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error($@) if $@;
	my @users;
	my %usernames;

	while ( my ( $userid, $username, $firstname, $surname ) = $sql->fetchrow_array ) {
		push @users, $userid;
		$usernames{$userid} = "$surname, $firstname ($username)";
	}
	$usernames{''} = ' ';    #Required for HTML5 validation.
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $longest_name  = BIGSdb::Utils::get_largest_string_length( [ @$loci, @$scheme_fields ] );
	my $width         = int( 0.5 * $longest_name ) + 2;
	$width = 15 if $width > 15;
	$width = 6  if $width < 6;
	print $q->start_form;
	say qq(<fieldset class="form" style="float:left"><legend>Record</legend>);

	if ( !$q->param('sent') ) {
		say "<p>Update your record as required - required fields are marked with an exclamation mark (!):</p>";
	}
	$q->param( sent => 1 );
	print $q->hidden($_) foreach qw (page db sent scheme_id profile_id);
	say "<ul>";
	my ( $label, $title ) = $self->get_truncated_label( $primary_key, 24 );
	my $title_attribute = $title ? " title=\"$title\"" : '';
	say qq(<li><label class="form" style="width:${width}em"$title_attribute>$label: !</label>);
	say "<b>$profile_id</b></li>";
	my $set_id = $self->get_set_id;

	foreach my $locus (@$loci) {
		my %html5_args = ( required => 'required' );
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		$html5_args{'type'} = 'number' if $locus_info->{'allele_id_format'} eq 'integer' && !$scheme_info->{'allow_missing_loci'};
		my $mapped = $self->{'datastore'}->get_set_locus_label( $locus, $set_id ) // $locus;
		my ( $label, $title ) = $self->get_truncated_label( $mapped, 24 );
		my $title_attribute = $title ? " title=\"$title\"" : '';
		say qq(<li><label for="locus:$locus" class="form" style="width:${width}em"$title_attribute>$label: !</label>);
		say $self->textfield(
			-name => "locus:$locus",
			-id   => "locus:$locus",
			-size => $locus_info->{'allele_id_format'} eq 'integer' ? 10 : 20,
			-value => $q->param("locus:$locus") // $allele_data->{$locus},
			%html5_args
		);
		say "</li>";
	}
	foreach my $field (@$scheme_fields) {
		next if $field eq $primary_key;
		my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		my %html5_args;
		$html5_args{'type'} = 'number' if $field_info->{'type'} eq 'integer';
		my ( $label, $title ) = $self->get_truncated_label( $field, 24 );
		my $title_attribute = $title ? " title=\"$title\"" : '';
		say qq(<li><label for="field:$field" class="form" style="width:${width}em"$title_attribute>$label: </label>);
		say $q->textfield(
			-name => "field:$field",
			-id   => "field:$field",
			-size => $field_info->{'type'} eq 'integer' ? 10 : 50,
			-value => $q->param("field:$field") // $field_data->{$field},
			%html5_args
		);
		say "</li>";
	}
	say qq(<li><label for="field:sender" class="form" style="width:${width}em">sender: !</label>);
	say $q->popup_menu(
		-name    => 'field:sender',
		-id      => 'field:sender',
		-values  => [ '', @users ],
		-labels  => \%usernames,
		-default => $q->param('field:sender') // $profile_data->{'sender'}
	);
	say "</li>";
	say qq(<li><label class="form" style="width:${width}em">curator: !</label><b>);
	say $self->get_curator_name() . ' (' . $self->{'username'} . ")</b></li>";
	say qq(<li><label class="form" style="width:${width}em">date_entered: !</label><b>);
	say "$profile_data->{'date_entered'}</b></li>";
	say qq(<li><label class="form" style="width:${width}em">datestamp: !</label><b>);
	say $self->get_datestamp . "</b></li>";
	my $pubmed_list =
	  $self->{'datastore'}->run_list_query( "SELECT pubmed_id FROM profile_refs WHERE scheme_id=? AND profile_id=? ORDER BY pubmed_id",
		$scheme_id, $profile_id );
	say qq(<li><label for="pubmed" class="form" style="width:${width}em">PubMed ids:</label>);
	local $" = "\n";
	say $q->textarea( -name => 'pubmed', -id => 'pubmed', -rows => 2, -cols => 12, -style => 'width:10em', -default => "@$pubmed_list" );
	say "</li>";
	say "</ul>";
	say "</fieldset>";
	$self->print_action_fieldset( { scheme_id => $scheme_id, profile_id => $profile_id } );
	say $q->end_form;
	say "</div></div>";
	return;
}
1;
