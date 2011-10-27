#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
use base qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<h1>Update profile</h1>\n";
	my ( $scheme_id, $profile_id ) = ( $q->param('scheme_id'), $q->param('profile_id') );
	if ( !$scheme_id ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No scheme_id passed.</p></div>\n";
		return;
	} elsif ( !BIGSdb::Utils::is_int($scheme_id) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Scheme_id must be an integer.</p></div>\n";
		return;
	} elsif ( !$profile_id ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No profile_id passed.</p></div>\n";
		return;
	} elsif ( !$self->can_modify_table('profiles') ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to modify profiles.</p></div>\n";
		return;
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
	my $qry         = "SELECT * FROM profiles WHERE scheme_id=? AND profile_id=?";
	my $sql         = $self->{'db'}->prepare($qry);
	eval { $sql->execute( $scheme_id, $profile_id ) };
	$logger->error($@) if $@;
	my $data = $sql->fetchrow_hashref;
	if ( !$$data{'profile_id'} ) {
		print
"<div class=\"box\" id=\"statusbad\"><p>No profile from scheme $scheme_id ($scheme_info->{'description'}) with profile_id = '$profile_id' exists.</p></div>\n";
		return;
	}
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $allele_qry    = "SELECT allele_id FROM profile_members WHERE scheme_id=? AND locus=? AND profile_id=?";
	my $allele_sql    = $self->{'db'}->prepare($allele_qry);
	my $allele_data;
	foreach (@$loci) {
		eval { $allele_sql->execute( $scheme_id, $_, $profile_id ) };
		if ($@) {
			$logger->error("Can't execute allele check");
		} else {
			( $allele_data->{$_} ) = $allele_sql->fetchrow_array;
		}
	}
	my $field_qry = "SELECT value FROM profile_fields WHERE scheme_id=? AND scheme_field=? AND profile_id=?";
	my $field_sql = $self->{'db'}->prepare($field_qry);
	my $field_data;
	foreach (@$scheme_fields) {
		eval { $field_sql->execute( $scheme_id, $_, $profile_id ) };
		if ($@) {
			$logger->error("Can't execute field check");
		} else {
			( $field_data->{$_} ) = $field_sql->fetchrow_array;
		}
	}
	my $primary_key;
	eval {
		$primary_key =
		  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )->[0];
	};
	if ( !$primary_key ) {
		print
"<div class=\"box\" id=\"statusbad\"><p>This scheme doesn't have a primary key field defined.  Profiles can not be entered until this has been done.</p></div>\n";
		return;
	} elsif ( !@$loci ) {
		print
"<div class=\"box\" id=\"statusbad\"><p>This scheme doesn't have any loci belonging to it.  Profiles can not be entered until there is at least one locus defined.</p></div>\n";
		return;
	}
	my $pk_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	if ( $q->param('sent') ) {
		my %newdata;
		my @bad_field_buffer;
		my $update = 1;
		my %locus_changed;
		my %field_changed;
		foreach (@$loci) {
			my $locus_info = $self->{'datastore'}->get_locus_info($_);
			$newdata{"locus:$_"} = $q->param("locus:$_");
			if ( !$newdata{"locus:$_"} ) {
				push @bad_field_buffer, "Locus '$_' is a required field.";
			} elsif ( $locus_info->{'allele_id_format'} eq 'integer' && !BIGSdb::Utils::is_int( $newdata{"locus:$_"} ) ) {
				push @bad_field_buffer, "Locus '$_' must be an integer.";
			}
			if ( $allele_data->{$_} ne $newdata{"locus:$_"} ) {
				$locus_changed{$_} = 1;
			}
		}
		foreach (@$scheme_fields) {
			next if $_ eq $primary_key;
			$newdata{"field:$_"} = $q->param("field:$_");
			my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $_ );
			if ( $field_info->{'type'} eq 'integer' && !BIGSdb::Utils::is_int( $newdata{"field:$_"} ) ) {
				push @bad_field_buffer, "Field '$_' must be an integer.";
			}
			$field_data->{$_} = defined $field_data->{$_} ? $field_data->{$_} : '';
			if ( $field_data->{$_} ne $newdata{"field:$_"} ) {
				$field_changed{$_} = 1;
			}
		}
		$newdata{"field:sender"} = $q->param("field:sender");
		if ( $data->{'sender'} ne $newdata{'field:sender'} ) {
			$field_changed{'sender'} = 1;
		}
		if (@bad_field_buffer) {
			print
			  "<div class=\"box\" id=\"statusbad\"><p>There are problems with your record submission.  Please address the following:</p>\n";
			local $" = '<br />';
			print "<p>@bad_field_buffer</p></div>\n";
		} elsif ( !%locus_changed && !%field_changed ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No fields were changed.</p></div>\n";
		} else {
			my $success    = 1;
			my $curator_id = $self->get_curator_id;
			my @updated_field;
			foreach ( keys %locus_changed ) {
				my $sql_update =
				  $self->{'db'}
				  ->prepare("UPDATE profile_members SET allele_id=?,datestamp=?,curator=? WHERE scheme_id=? AND locus=? AND profile_id=?");
				eval { $sql_update->execute( $newdata{"locus:$_"}, 'today', $curator_id, $scheme_id, $_, $profile_id ); };
				if ($@) {
					$logger->error("Can't update allele for locus '$_'.");
					$self->{'db'}->rollback;
					$success = 0;
				}
				push @updated_field, "$_: '$allele_data->{$_}' -> '$newdata{\"locus:$_\"}'";
			}
			foreach ( keys %field_changed ) {
				if ( $_ eq 'sender' ) {
					my $sql_update =
					  $self->{'db'}->prepare("UPDATE profiles SET sender=?,datestamp=?,curator=? WHERE scheme_id=? AND profile_id=?");
					eval { $sql_update->execute( $newdata{"field:sender"}, 'today', $curator_id, $scheme_id, $profile_id ); };
					if ($@) {
						$logger->error("Can't update sender for scheme:$scheme_id profile:'$profile_id'.");
						$self->{'db'}->rollback;
						$success = 0;
					}
					push @updated_field, "$_: '$data->{$_}' -> '$newdata{\"field:$_\"}'";
				} else {
					if ( defined $field_data->{$_} && $field_data->{$_} ne '') {
						my $sql_update =
						  $self->{'db'}->prepare(
							"UPDATE profile_fields SET value=?,datestamp=?,curator=? WHERE scheme_id=? AND scheme_field=? AND profile_id=?"
						  );
						eval { $sql_update->execute( $newdata{"field:$_"}, 'today', $curator_id, $scheme_id, $_, $profile_id ); };
						if ($@) {
							$logger->error("Can't update field $_ for scheme:$scheme_id profile:'$profile_id'.");
							$self->{'db'}->rollback;
							$success = 0;
						}
					} else {
						my $sql_update =
						  $self->{'db'}->prepare(
							"INSERT INTO profile_fields (scheme_id,scheme_field,profile_id,value,curator,datestamp) VALUES (?,?,?,?,?,?)");
						eval { $sql_update->execute( $scheme_id, $_, $profile_id, $newdata{"field:$_"}, $curator_id, 'today' ); };
						if ($@) {
							$logger->error("Can't add field $_ for scheme:$scheme_id profile:'$profile_id'. $@");
							$self->{'db'}->rollback;
							$success = 0;
						}
					}
					push @updated_field, "$_: '$field_data->{$_}' -> '$newdata{\"field:$_\"}'";
				}
			}
			if ( keys %locus_changed || keys %field_changed ) {
				my $sql_update = $self->{'db'}->prepare("UPDATE profiles SET datestamp=?,curator=? WHERE scheme_id=? AND profile_id=?");
				eval { $sql_update->execute( 'today', $curator_id, $scheme_id, $profile_id ); };
				if ($@) {
					$logger->error("Can't update datestamp for scheme:$scheme_id profile:'$profile_id'.");
					$self->{'db'}->rollback;
					$success = 0;
				}
			}
			if ($success) {
				$self->{'db'}->commit;
				print "<div class=\"box\" id=\"resultsheader\"><p>Updated!</p>";
				print "<p><a href=\"" . $q->script_name . "?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
				$logger->info("Updated profile scheme_id:$scheme_id profile_id:$profile_id");
				local $" = '<br />';
				$self->_update_profile_history( $scheme_id, $profile_id, "@updated_field" );
				return;
			} else {
				print "<div class=\"box\" id=\"statusbad\"><p>Update failed - transaction cancelled - no records have been touched.</p>\n";
				if ( $@ =~ /duplicate/ && $@ =~ /unique/ ) {
					print
"<p>Data update would have resulted in records with either duplicate ids or another unique field with duplicate values.</p>\n";
				} else {
					print "<p>Error message: $@</p>\n";
				}
				print "</div>\n";
				$logger->error("Can't update profile: $@");
			}
		}
	}
	print "<div class=\"box\" id=\"queryform\">\n";
	if ( !$q->param('sent') ) {
		print "<p>Update your record as required - required fields are marked with an exclamation mark (!):</p>\n";
	}
	$qry = "select id,user_name,first_name,surname from users WHERE id>0 order by surname";
	$sql = $self->{'db'}->prepare($qry);
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
	print "<table>\n";
	print "<tr><td style=\"text-align:right\">$primary_key: !</td><td><b>$profile_id</b></td></tr>";
	foreach (@$loci) {
		print "<tr><td style=\"text-align:right\">$_: !</td><td>";
		my $locus_info = $self->{'datastore'}->get_locus_info($_);
		print $q->textfield(
			-name    => "locus:$_",
			-size    => $locus_info->{'allele_id_format'} eq 'integer' ? 10 : 20,
			-default => $allele_data->{$_}
		);
		print "</td></tr>\n";
	}
	foreach (@$scheme_fields) {
		next if $_ eq $primary_key;
		print "<tr><td style=\"text-align:right\">$_: </td><td>";
		my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $_ );
		print $q->textfield( -name => "field:$_", -size => $field_info->{'type'} eq 'integer' ? 10 : 20, -default => $field_data->{$_} );
		print "</td></tr>\n";
	}
	print "<tr><td style=\"text-align:right\">sender: !</td><td>";
	print $q->popup_menu( -name => 'field:sender', -values => [ '', @users ], -labels => \%usernames, -default => $data->{'sender'} );
	print "</td></tr>\n";
	print "<tr><td style=\"text-align:right\">curator: !</td><td><b>";
	print $self->get_curator_name() . ' (' . $self->{'username'} . ")</b></td></tr>\n";
	print "<tr><td style=\"text-align:right\">date_entered: !</td><td><b>$data->{'date_entered'}</b></td></tr>\n";
	print "<tr><td style=\"text-align:right\">datestamp: !</td><td><b>" . $self->get_datestamp . "</b></td></tr>\n";
	print "<tr><td>";
	print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=profileUpdate&amp;scheme_id=$scheme_id&amp;profile_id=$data->{'profile_id'}\" class=\"resetbutton\">Reset</a>";
	print "</td><td style=\"text-align:right\">";
	print $q->submit( -name => 'Update', -class => 'submit' );
	print "</td></tr>\n";
	print "</table>\n";
	print $q->end_form;
	print "</div>\n";
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Update profile - $desc";
}

sub _update_profile_history {
	my ( $self, $scheme_id, $profile_id, $action ) = @_;
	return if !$action || !$scheme_id || !$profile_id;
	my $curator_id = $self->get_curator_id;
	$action =~ s/'/\\'/g;
	eval {
		$self->{'db'}->do(
"INSERT INTO profile_history (scheme_id,profile_id,timestamp,action,curator) VALUES ($scheme_id,'$profile_id','now',E'$action',$curator_id)"
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
