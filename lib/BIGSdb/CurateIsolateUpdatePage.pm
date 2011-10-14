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
package BIGSdb::CurateIsolateUpdatePage;
use strict;
use warnings;
use base qw(BIGSdb::CuratePage);
use List::MoreUtils qw(none);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

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
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<h1>Update isolate</h1>\n";
	my $qry = "SELECT * FROM $self->{'system'}->{'view'} WHERE id = ?";
	my $sql = $self->{'db'}->prepare($qry);
	if ( !$q->param('id') ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No id passed.</p></div>\n";
		return;
	} elsif ( !$self->can_modify_table('isolates')
		&& !$self->can_modify_table('allele_designations')
		&& !$self->can_modify_table('samples') )
	{
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to update isolate records.</p></div>\n";
		return;
	}
	eval { $sql->execute( $q->param('id') ) };
	$logger->error($@) if $@;
	my $data = $sql->fetchrow_hashref();
	if ( !$$data{'id'} ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No record with id = " . $q->param('id') . " exists.</p></div>\n";
		return;
	}
	if ( $q->param('sent') ) {
		if ( !$self->can_modify_table('isolates') ) {
			print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to update isolate fields.</p></div>\n";
			return;
		}
		my %newdata;
		my @bad_field_buffer;
		my $update = 1;
		foreach my $required ( '1', '0' ) {
			foreach my $field ( @{ $self->{'xmlHandler'}->get_field_list } ) {
				my %thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
				my $required_field = !( $thisfield{'required'} && $thisfield{'required'} eq 'no' );
				if (   ( $required_field && $required )
					|| ( !$required_field && !$required ) )
				{
					if ( $field eq 'curator' ) {
						$newdata{$field} = $self->get_curator_id;
					} elsif ( $field eq 'datestamp' ) {
						$newdata{$field} = $self->get_datestamp;
					} else {
						$newdata{$field} = $q->param($field);
					}
					my $bad_field = $self->is_field_bad( $self->{'system'}->{'view'}, $field, $newdata{$field} );
					if ($bad_field) {
						push @bad_field_buffer, "Field '$field': $bad_field.";
					}
				}
			}
		}
		if (@bad_field_buffer) {
			print
			  "<div class=\"box\" id=\"statusbad\"><p>There are problems with your record submission.  Please address the following:</p>\n";
			$" = '<br />';
			print "<p>@bad_field_buffer</p></div>\n";
			$update = 0;
		}
		if ($update) {
			my $qry;
			$qry = "UPDATE isolates SET ";
			$"   = ',';
			my @updated_field;
			foreach ( @{ $self->{'xmlHandler'}->get_field_list } ) {
				$newdata{$_} = defined $newdata{$_} ? $newdata{$_} : '';
				$newdata{$_} =~ s/'/\\'/g;
				$newdata{$_} =~ s/\r//g;
				$newdata{$_} =~ s/\n/ /g;
				if ( $newdata{$_} ne '' ) {
					$qry .= "$_='" . $newdata{$_} . "',";
				} else {
					$qry .= "$_=null,";
				}
				$newdata{$_} =~ s/\\'/'/g;
				$data->{ lc($_) } = defined $data->{ lc($_) } ? $data->{ lc($_) } : '';
				if ( $_ ne 'datestamp' && $_ ne 'curator' && $data->{ lc($_) } ne $newdata{$_} ) {
					push @updated_field, "$_: '$data->{lc($_)}' -> '$newdata{$_}'";
				}
			}
			$qry =~ s/,$//;
			$qry .= " WHERE id='$data->{'id'}'";
			my @alias_update;
			my $existing_aliases =
			  $self->{'datastore'}
			  ->run_list_query( "SELECT alias FROM isolate_aliases WHERE isolate_id=? ORDER BY isolate_id", $data->{'id'} );
			my @new_aliases = split /\r?\n/, $q->param('aliases');
			foreach my $new (@new_aliases) {
				chomp $new;
				next if $new eq '';
				if ( !@$existing_aliases || none { $new eq $_ } @$existing_aliases ) {
					( my $clean_new = $new ) =~ s/'/\\'/g;
					push @alias_update,
"INSERT INTO isolate_aliases (isolate_id,alias,curator,datestamp) VALUES ($data->{'id'},'$clean_new',$newdata{'curator'},'today')";
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
					push @pubmed_update,
"INSERT INTO refs (isolate_id,pubmed_id,curator,datestamp) VALUES ($data->{'id'},'$clean_new',$newdata{'curator'},'today')";
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
						foreach ( @alias_update, @pubmed_update ) {
							$self->{'db'}->do($_);
						}
					};
					if ($@) {
						print
"<div class=\"box\" id=\"statusbad\"><p>Update failed - transaction cancelled - no records have been touched.</p>\n";
						if ( $@ =~ /duplicate/ && $@ =~ /unique/ ) {
							print
"<p>Data update would have resulted in records with either duplicate ids or another unique field with duplicate values.</p>\n";
						} elsif ( $@ =~ /datestyle/){
							print
"<p>Date fields must be entered in yyyy-mm-dd format.</p>\n";
						} else {
							$logger->error("Can't update: $@");
						}
						print "</div>\n";
						$self->{'db'}->rollback;					
					} else {
						$self->{'db'}->commit
						  && print "<div class=\"box\" id=\"resultsheader\"><p>Updated!</p>";
						print "<p><a href=\"" . $q->script_name . "?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
						$logger->debug("Update: $qry");
						local $" = '<br />';
						$self->update_history( $data->{'id'}, "@updated_field" );
						return;
					}
				} else {
					print "<div class=\"box\" id=\"resultsheader\"><p>No field changes have been made.</p>\n";
					print "<p><a href=\"" . $q->script_name . "?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
					return;
				}
			}
		}
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
	print "<div class=\"scrollable\">\n";
	print "<table><tr>";
	print "<td style=\"vertical-align:top\">\n";
	if ( $self->can_modify_table('isolates') ) {
		print "<div class=\"box\" id=\"queryform\">\n";
		if ( !$q->param('sent') ) {
			print "<h2>Isolate fields:</h2>\n";
			print "<p>Update your record as required:</p>\n";
		}
		print "<table><tr><td>";
		print $q->start_form;
		print $q->hidden($_) foreach qw(page db);
		print $q->hidden( 'sent', 1 );
		print "<table>\n";
		print "<tr><td colspan=\"2\" style=\"text-align:right\">";
		print $q->submit( -name => 'Update', -class => 'submit' );
		print "</td></tr>\n";

		#Display required fields first
		foreach my $required ( '1', '0' ) {
			foreach my $field ( @{ $self->{'xmlHandler'}->get_field_list } ) {
				my %thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
				if (
					!( $thisfield{'required'} && $thisfield{'required'} eq 'no' ) && $required
					|| ( ( $thisfield{'required'} && $thisfield{'required'} eq 'no' )
						&& $required == 0 )
				  )
				{
					print "<tr><td style=\"text-align:right\">$field: ";
					if ($required) {
						print '!';
					}
					print "</td><td style=\"text-align:left; width:90%\">";
					if ( $thisfield{'optlist'} ) {
						my @optlist = $self->{'xmlHandler'}->get_field_option_list($field);
						print $q->popup_menu( -name => $field, -values => [ '', @optlist ], -default => $$data{ lc($field) } );
					} elsif ( $thisfield{'type'} eq 'bool' ) {
						my $default;
						if (   $$data{ lc($field) } eq 't'
							|| $$data{ lc($field) } eq '1'
							|| $$data{ lc($field) } eq 'true' )
						{
							$default = 'true';
						} else {
							$default = 'false';
						}
						print $q->popup_menu( -name => $field, -values => [ '', 'true', 'false' ], -default => $default );
					} elsif ( $field eq 'id' ) {
						print "<b>$$data{'id'}</b>\n";
						print $q->hidden( 'id', $$data{'id'} );
					} elsif ( lc($field) eq 'curator' ) {
						print '<b>' . $self->get_curator_name . ' (' . $self->{'username'} . ")</b>\n";
					} elsif ( lc($field) eq 'date_entered' ) {
						print '<b>' . $$data{ lc($field) } . "</b>\n";
						print $q->hidden( 'date_entered', $$data{ lc($field) } );
					} elsif ( lc($field) eq 'datestamp' ) {
						print '<b>' . $self->get_datestamp . "</b>\n";
					} elsif (
						lc($field) eq 'sender'
						|| lc($field) eq 'sequenced_by'
						|| (   $thisfield{'userfield'}
							&& $thisfield{'userfield'} eq 'yes' )
					  )
					{
						print $q->popup_menu(
							-name    => $field,
							-values  => [ '', @users ],
							-labels  => \%usernames,
							-default => $$data{ lc($field) }
						);
					} else {
						if ( $thisfield{'length'} && $thisfield{'length'} > 60 ) {
							print $q->textarea( -name => $field, -rows => 3, -cols => 60, -default => $$data{ lc($field) } );
						} else {
							print $q->textfield( -name => $field, -size => $thisfield{'length'}, -default => $$data{ lc($field) } );
						}
					}
					if (   $field ne 'datestamp'
						&& $field ne 'date_entered'
						&& lc( $thisfield{'type'} ) eq 'date' )
					{
						print " format: yyyy-mm-dd";
					}
					print "</td></tr>\n";
				}
			}
		}
		print "<tr><td style=\"text-align:right\">aliases: </td><td>";
		my $aliases =
		  $self->{'datastore'}->run_list_query( "SELECT alias FROM isolate_aliases WHERE isolate_id=? ORDER BY alias", $q->param('id') );
		$" = "\n";
		print $q->textarea( -name => 'aliases', -rows => 2, -cols => 12, -style => 'width:10em', -default => "@$aliases" );
		print "</td></tr>\n";
		print "<tr><td style=\"text-align:right\">PubMed ids: </td><td>";
		my $pubmed =
		  $self->{'datastore'}->run_list_query( "SELECT pubmed_id FROM refs WHERE isolate_id=? ORDER BY pubmed_id", $q->param('id') );
		$" = "\n";
		print $q->textarea( -name => 'pubmed', -rows => 2, -cols => 12, -style => 'width:10em', -default => "@$pubmed" );
		print "</td></tr>\n";
		print "<tr><td>";
		print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=isolateUpdate&amp;id=$data->{'id'}\" class=\"resetbutton\">Reset</a>";
		print "</td><td style=\"text-align:right\">";
		print $q->submit( -name => 'Update', -class => 'submit' );
		print "</td></tr>\n";
		print "</table>\n";
		print $q->end_form;
		print "</td></tr></table>";
		print "</div>\n";
	}
	if ( $self->can_modify_table('samples') ) {
		my $sample_fields = $self->{'xmlHandler'}->get_sample_field_list;
		if (@$sample_fields) {
			print "<div class=\"box\" id=\"samples\">\n";
			print "<h2>Samples:</h2>\n";
			my $isolate_record = BIGSdb::IsolateInfoPage->new(
				(
					'system'        => $self->{'system'},
					'cgi'           => $self->{'cgi'},
					'instance'      => $self->{'instance'},
					'prefs'         => $self->{'prefs'},
					'prefstore'     => $self->{'prefstore'},
					'config'        => $self->{'config'},
					'datastore'     => $self->{'datastore'},
					'db'            => $self->{'db'},
					'xmlHandler'    => $self->{'xmlHandler'},
					'dataConnector' => $self->{'dataConnector'},
					'curate'        => 1
				)
			);
			print $isolate_record->get_sample_summary( $data->{'id'} );
			print
"<p /><p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=samples&amp;isolate_id=$data->{'id'}\" class=\"button\">&nbsp;Add new sample&nbsp;</a></p>\n";
			print "</div>\n";
		}
	}
	if ( $self->can_modify_table('allele_designations') ) {
		print "</td><td style=\"vertical-align:top; padding-left:1em\">\n"
		  if $self->can_modify_table('isolates') || $self->can_modify_table('samples');
		print "<div class=\"box\" id=\"alleles\">\n";
		print "<h2>Loci:</h2>\n";
		print
"<p>Allele designations are handled separately from isolate fields due to the potential complexity of multiple loci with set and pending designations.</p>\n";
		my $isolate_record = BIGSdb::IsolateInfoPage->new(
			(
				'system'        => $self->{'system'},
				'cgi'           => $self->{'cgi'},
				'instance'      => $self->{'instance'},
				'prefs'         => $self->{'prefs'},
				'prefstore'     => $self->{'prefstore'},
				'config'        => $self->{'config'},
				'datastore'     => $self->{'datastore'},
				'db'            => $self->{'db'},
				'xmlHandler'    => $self->{'xmlHandler'},
				'dataConnector' => $self->{'dataConnector'},
				'curate'        => 1
			)
		);
		my $locus_summary = $isolate_record->get_loci_summary( $data->{'id'} );
		$locus_summary =~ s /<table class=\"resultstable\">\s*<\/table>//;
		print $locus_summary;
		print "<p />\n";
		print $q->start_form;
		my $loci = $self->{'datastore'}->get_loci( { 'query_pref' => 1 } );
		print "Locus: ";
		print $q->popup_menu( -name => 'locus', -values => $loci );
		print $q->submit( -label => 'Add/update', -class => 'submit' );
		$q->param( 'page',       'alleleUpdate' );
		$q->param( 'isolate_id', $q->param('id') );
		print $q->hidden($_) foreach qw(db page isolate_id);
		print $q->end_form;
		print "</div>\n";
	}
	print "</td></tr></table>\n";
	print "</div>\n";
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Update isolate - $desc";
}
1;
