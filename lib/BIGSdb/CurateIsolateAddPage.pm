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
package BIGSdb::CurateIsolateAddPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateAddPage);
use List::MoreUtils qw(uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant SUCCESS => 1;

sub print_content {
	my ($self) = @_;
	print "<h1>Add new isolate</h1>\n";
	if ( !$self->can_modify_table('isolates') ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to add records to the isolates table.</p></div>\n";
		return;
	}
	my $q = $self->{'cgi'};
	my %newdata;
	foreach my $field ( @{ $self->{'xmlHandler'}->get_field_list } ) {
		if ( $q->param($field) ) {
			$newdata{$field} = $q->param($field);
		} else {
			my %thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			if ( $thisfield{'type'} eq 'int'
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
	my $q = $self->{'cgi'};
	my $loci = $self->{'datastore'}->get_loci( { 'query_pref' => 1 } );
	@$loci = uniq @$loci;
	my @bad_field_buffer;
	my $insert = 1;
	foreach my $required ( '1', '0' ) {
		foreach my $field ( @{ $self->{'xmlHandler'}->get_field_list } ) {
			my %thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			my $required_field = !( ( $thisfield{'required'} // '' ) eq 'no' );
			if (   ( $required_field && $required )
				|| ( !$required_field && !$required ) )
			{
				if ( $field eq 'curator' ) {
					$newdata->{$field} = $self->get_curator_id;
				} elsif ( $field eq 'datestamp'
					|| $field eq 'date_entered' )
				{
					$newdata->{$field} = $self->get_datestamp;
				} else {
					$newdata->{$field} = $q->param($field);
				}
				my $bad_field = $self->is_field_bad( $self->{'system'}->{'view'}, $field, $newdata->{$field} );
				if ($bad_field) {
					push @bad_field_buffer, "Field '$field': $bad_field";
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
		print "<div class=\"box\" id=\"statusbad\"><p>There are problems with your record submission.  Please address the following:</p>\n";
		local $" = '<br />';
		print "<p>@bad_field_buffer</p></div>\n";
		$insert = 0;
	}
	if ($insert) {
		if ( $self->id_exists( $newdata->{'id'} ) ) {
			print "<div class=\"box\" id=\"statusbad\"><p>id-$newdata->{'id'} has already been defined - "
			  . "please choose a different id number.</p></div>\n";
			$insert = 0;
		}
		return $self->_insert($newdata) if $insert;
	}
	return;
}

sub _insert {
	my ( $self, $newdata ) = @_;
	my $q = $self->{'cgi'};
	my $loci = $self->{'datastore'}->get_loci( { query_pref => 1 } );
	@$loci = uniq @$loci;
	my $insert = 1;
	my @fields_with_values;
	foreach ( @{ $self->{'xmlHandler'}->get_field_list } ) {
		push @fields_with_values, $_ if $newdata->{$_} ne '';
	}
	my @inserts;
	my $qry;
	$qry = "INSERT INTO isolates ";
	local $" = ',';
	$qry .= "(@fields_with_values";
	$qry .= ') VALUES (';
	foreach (@fields_with_values) {
		$newdata->{$_} =~ s/'/\\'/g;
		$newdata->{$_} =~ s/\r//g;
		$newdata->{$_} =~ s/\n/ /g;
		$qry .= "E'$newdata->{$_}',";
	}
	$qry =~ s/,$//;
	$qry .= ')';
	push @inserts, $qry;

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
		  "INSERT INTO refs (isolate_id,pubmed_id,curator,datestamp) VALUES ($newdata->{'id'}," . "$new,$newdata->{'curator'},'today')";
	}
	if ($insert) {
		local $" = ';';
		eval { $self->{'db'}->do("@inserts"); };
		if ($@) {
			print "<div class=\"box\" id=\"statusbad\"><p>Insert failed - transaction cancelled - no records have been touched.</p>\n";
			if ( $@ =~ /duplicate/ && $@ =~ /unique/ ) {
				print "<p>Data entry would have resulted in records with either duplicate ids or another unique field with "
				  . "duplicate values.</p>\n";
			} else {
				print "<p>Error message: $@</p>\n";
				$logger->error("Insert failed: $qry  $@");
			}
			print "</div>\n";
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit
			  && print "<div class=\"box\" id=\"resultsheader\"><p>id-$newdata->{'id'} added!</p>";
			print "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=isolateAdd\">Add another</a> | "
			  . "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
			return SUCCESS;
		}
	}
	return;
}

sub _print_interface {
	my ( $self, $newdata ) = @_;
	my $loci = $self->{'datastore'}->get_loci( { 'query_pref' => 1 } );
	@$loci = uniq @$loci;
	my $q = $self->{'cgi'};
	print "<div class=\"box\" id=\"queryform\"><p>Please fill in the fields below - required fields are " . "
	marked with an exclamation mark (!).</p>\n";
	print "<div class=\"scrollable\">\n";
	my $qry = "SELECT id,user_name,first_name,surname FROM users WHERE id>0 ORDER BY surname";
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
	print $q->hidden($_) foreach qw(page db sent);
	my $field_list = $self->{'xmlHandler'}->get_field_list;
	if ( @$field_list > 15 ) {
		print "<span style=\"float:right\">";
		print $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
		print "</span>\n";
	}
	print "<fieldset><legend>Isolate fields</legend>";
	print "<table>\n";

	#Display required fields first
	foreach my $required ( '1', '0' ) {
		foreach my $field (@$field_list) {
			my %thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			my $required_field = !( ( $thisfield{'required'} // '' ) eq 'no' );
			if (   ( $required_field && $required )
				|| ( !$required_field && !$required ) )
			{
				print "<tr><td style=\"text-align:right\">$field: ";
				if ($required) {
					print '!';
				}
				print "</td><td style=\"text-align:left\">";
				if ( $thisfield{'optlist'} ) {
					my @optlist;
					foreach my $option ( $self->{'xmlHandler'}->get_field_option_list($field) ) {
						push @optlist, $option;
					}
					print $q->popup_menu( -name => $field, -values => [ '', @optlist ], -default => $newdata->{$field} );
				} elsif ( $thisfield{'type'} eq 'bool' ) {
					print $q->popup_menu( -name => $field, -values => [ '', 'true', 'false' ], -default => $newdata->{$field} );
				} elsif ( lc($field) eq 'datestamp'
					|| lc($field) eq 'date_entered' )
				{
					print "<b>" . $self->get_datestamp . "</b>\n";
				} elsif ( lc($field) eq 'curator' ) {
					print "<b>" . $self->get_curator_name . ' (' . $self->{'username'} . ")</b>\n";
				} elsif (
					lc($field) eq 'sender'
					|| lc($field) eq 'sequenced_by'
					|| (   $thisfield{'userfield'}
						&& $thisfield{'userfield'} eq 'yes' )
				  )
				{
					print $q->popup_menu( -name => $field, -values => [ '', @users ], -labels => \%usernames,
						-default => $newdata->{$field}, );
				} else {
					if ( $thisfield{'length'} && $thisfield{'length'} > 60 ) {
						print $q->textarea( -name => $field, -rows => 3, -cols => 40, -default => $newdata->{$field} );
					} else {
						print $q->textfield( -name => $field, -size => $thisfield{'length'}, -default => $newdata->{$field} );
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
	print $q->textarea( -name => 'aliases', -rows => 2, -cols => 12, -style => 'width:10em' );
	print "</td></tr>\n";
	print "<tr><td style=\"text-align:right\">PubMed ids: </td><td>";
	print $q->textarea( -name => 'pubmed', -rows => 2, -cols => 12, -style => 'width:10em' );
	print "</td></tr>\n";
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
	print "</table>\n";
	print "</fieldset>\n";
	print "<fieldset><legend>Allele designations</legend>\n<table>$locus_buffer</table></fieldset>" if @$loci;
	print "<div style=\"margin-bottom:2em\">\n<span style=\"float:left\"><a href=\"$self->{'system'}->{'script_name'}?"
	  . " db=$self->{'instance'}&amp;page=isolateAdd\" class=\"resetbutton\">Reset</a></span><span style=\"float:right\">";
	print $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
	print "</span></div>\n";
	print $q->end_form;
	print "</div></div>\n";
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Add new isolate - $desc";
}
1;
