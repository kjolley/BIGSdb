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
	my $scheme_id = $args->{'scheme_id'};
	my %newdata;
	my @bad_field_buffer;
	my $update = 1;
	my ( %locus_changed, %field_changed );
	my $q               = $self->{'cgi'};
	my $loci            = $self->{'datastore'}->get_scheme_loci( $scheme_id );
	my $scheme_fields   = $self->{'datastore'}->get_scheme_fields( $scheme_id );
	my $profile_changed = 0;
	my $set_id = $self->get_set_id;
	foreach my $locus (@$loci) {
		$newdata{"locus:$locus"} = $q->param("locus:$locus");
		$self->_clean_field(\$newdata{"locus:$locus"});
		my $field_bad = $self->is_locus_field_bad( $scheme_id, $locus, $newdata{"locus:$locus"} );
		push @bad_field_buffer, $field_bad if $field_bad;
		if ( $args->{'allele_data'}->{$locus} ne $newdata{"locus:$locus"} ) {
			$locus_changed{$locus} = 1;
			$profile_changed = 1;
		}
	}
	if ( !@bad_field_buffer && $profile_changed ) {
		my ( $exists, $msg ) = $self->profile_exists( $scheme_id, $args->{'primary_key'}, \%newdata );
		push @bad_field_buffer, $msg if $exists;
	}
	foreach my $field (@$scheme_fields) {
		next if $field eq $args->{'primary_key'};
		$newdata{"field:$field"} = $q->param("field:$field");
		$self->_clean_field(\$newdata{"field:$field"});
		my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		if ( $field_info->{'type'} eq 'integer' && !BIGSdb::Utils::is_int( $newdata{"field:$field"} ) ) {
			push @bad_field_buffer, "Field '$field' must be an integer.";
		}
		$args->{'field_data'}->{$field} = defined $args->{'field_data'}->{$field} ? $args->{'field_data'}->{$field} : '';
		if ( $args->{'field_data'}->{$field} ne $newdata{"field:$field"} ) {
			$field_changed{$field} = 1;
		}
	}
	$newdata{"field:sender"} = $q->param("field:sender");
	if ( !BIGSdb::Utils::is_int( $newdata{'field:sender'} ) ) {
		push @bad_field_buffer, "Field 'sender' is invalid.";
	}
	if ( $args->{'profile_data'}->{'sender'} ne $newdata{'field:sender'} ) {
		$field_changed{'sender'} = 1;
	}
	if (@bad_field_buffer) {
		say "<div class=\"box\" id=\"statusbad\"><p>There are problems with your record submission.  "
		  . "Please address the following:</p>";
		local $" = '<br />';
		print "<p>@bad_field_buffer</p></div>\n";
	} elsif ( !%locus_changed && !%field_changed ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No fields were changed.</p></div>";
	} else {
		my $success    = 1;
		my $curator_id = $self->get_curator_id;
		my @updated_field;
		foreach my $locus ( keys %locus_changed ) {
			my $sql_update =
			  $self->{'db'}
			  ->prepare("UPDATE profile_members SET allele_id=?,datestamp=?,curator=? WHERE scheme_id=? AND locus=? AND profile_id=?");
			eval {
				$sql_update->execute( $newdata{"locus:$locus"}, 'today', $curator_id, $scheme_id, $locus, $args->{'profile_id'} );
			};
			if ($@) {
				$logger->error($@);
				$self->{'db'}->rollback;
				$success = 0;
			}
			push @updated_field, "$locus: '$args->{'allele_data'}->{$locus}' -> '$newdata{\"locus:$locus\"}'";
		}
		foreach my $field ( keys %field_changed ) {
			if ( $field eq 'sender' ) {
				my $sql_update =
				  $self->{'db'}->prepare("UPDATE profiles SET sender=?,datestamp=?,curator=? WHERE scheme_id=? AND profile_id=?");
				eval {
					$sql_update->execute( $newdata{"field:sender"}, 'today', $curator_id, $scheme_id, $args->{'profile_id'} );
				};
				if ($@) {
					$logger->error($@);
					$self->{'db'}->rollback;
					$success = 0;
				}
				push @updated_field, "$field: '$args->{'profile_data'}->{$field}' -> '$newdata{\"field:$field\"}'";
			} else {
				if ( defined $args->{'field_data'}->{$field} && $args->{'field_data'}->{$field} ne '' ) {
					my $sql_update =
					  $self->{'db'}->prepare(
						"UPDATE profile_fields SET value=?,datestamp=?,curator=? WHERE scheme_id=? AND scheme_field=? AND profile_id=?");
					eval {
						$sql_update->execute( $newdata{"field:$field"},
							'today', $curator_id, $scheme_id, $field, $args->{'profile_id'} );
					};
					if ($@) {
						$logger->error($@);
						$self->{'db'}->rollback;
						$success = 0;
					}
				} else {
					my $sql_update =
					  $self->{'db'}->prepare(
						"INSERT INTO profile_fields (scheme_id,scheme_field,profile_id,value,curator,datestamp) VALUES (?,?,?,?,?,?)");
					eval {
						$sql_update->execute( $scheme_id, $field, $args->{'profile_id'}, $newdata{"field:$field"},
							$curator_id, 'today' );
					};
					if ($@) {
						$logger->error($@);
						$self->{'db'}->rollback;
						$success = 0;
					}
				}
				push @updated_field, "$field: '$args->{'field_data'}->{$field}' -> '$newdata{\"field:$field\"}'";
			}
		}
		if ( keys %locus_changed || keys %field_changed ) {
			my $sql_update = $self->{'db'}->prepare("UPDATE profiles SET datestamp=?,curator=? WHERE scheme_id=? AND profile_id=?");
			eval { $sql_update->execute( 'today', $curator_id, $scheme_id, $args->{'profile_id'} ); };
			if ($@) {
				$logger->error($@);
				$self->{'db'}->rollback;
				$success = 0;
			}
		}
		if ($success) {
			$self->refresh_material_view( $scheme_id );
			$self->{'db'}->commit;
			say "<div class=\"box\" id=\"resultsheader\"><p>Updated!</p>";
			say "<p><a href=\"" . $q->script_name . "?db=$self->{'instance'}\">Back to main page</a></p></div>";
			$logger->info("Updated profile scheme_id:$scheme_id profile_id:$args->{'profile_id'}");
			local $" = '<br />';
			$self->update_profile_history( $scheme_id, $args->{'profile_id'}, "@updated_field" );
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

sub _print_interface {
	my ( $self, $args ) = @_;
	my $q = $self->{'cgi'};
	say "<div class=\"box\" id=\"queryform\"><div class=\"scrollable\">";
	if ( !$q->param('sent') ) {
		say "<p>Update your record as required - required fields are marked with an exclamation mark (!):</p>";
	}
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
	print $q->start_form;
	$q->param( 'sent', 1 );
	print $q->hidden($_) foreach qw (page db sent scheme_id profile_id);
	say "<table>";
	say "<tr><td style=\"text-align:right\">$args->{'primary_key'}: !</td><td><b>$args->{'profile_id'}</b></td></tr>";
	my $loci          = $self->{'datastore'}->get_scheme_loci( $args->{'scheme_id'} );
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields( $args->{'scheme_id'} );
	my $set_id = $self->get_set_id;

	foreach my $locus (@$loci) {
		my $mapped = $self->{'datastore'}->get_set_locus_label($locus, $set_id) // $locus;
		say "<tr><td style=\"text-align:right\">$mapped: !</td><td>";
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		print $q->textfield(
			-name    => "locus:$locus",
			-size    => $locus_info->{'allele_id_format'} eq 'integer' ? 10 : 20,
			-default => $args->{'allele_data'}->{$locus}
		);
		print "</td></tr>\n";
	}
	foreach my $field (@$scheme_fields) {
		next if $field eq $args->{'primary_key'};
		say "<tr><td style=\"text-align:right\">$field: </td><td>";
		my $field_info = $self->{'datastore'}->get_scheme_field_info( $args->{'scheme_id'}, $field );
		say $q->textfield(
			-name    => "field:$field",
			-size    => $field_info->{'type'} eq 'integer' ? 10 : 20,
			-default => $args->{'field_data'}->{$field}
		);
		say "</td></tr>";
	}
	say "<tr><td style=\"text-align:right\">sender: !</td><td>";
	say $q->popup_menu(
		-name    => 'field:sender',
		-values  => [ '', @users ],
		-labels  => \%usernames,
		-default => $args->{'profile_data'}->{'sender'}
	);
	say "</td></tr>";
	say "<tr><td style=\"text-align:right\">curator: !</td><td><b>";
	say $self->get_curator_name() . ' (' . $self->{'username'} . ")</b></td></tr>";
	say "<tr><td style=\"text-align:right\">date_entered: !</td><td><b>$args->{'profile_data'}->{'date_entered'}</b></td></tr>";
	say "<tr><td style=\"text-align:right\">datestamp: !</td><td><b>" . $self->get_datestamp . "</b></td></tr>";
	say "</table>";
	$self->print_action_fieldset({scheme_id => $args->{'scheme_id'}, profile_id => $args->{'profile_id'}});
	say $q->end_form;
	say "</div></div>";
	return;
}
1;
