#Written by Keith Jolley
#Copyright (c) 2010, University of Oxford
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
use base qw(BIGSdb::CurateAddPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Add new profile - $desc";
}

sub print_content {
	my ($self)   = @_;
	my $scheme_id = $self->{'cgi'}->param('scheme_id');
	if ( !$self->{'datastore'}->scheme_exists($scheme_id) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid scheme passed.</p></div>\n";
		return;
	}  elsif ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		print
		  "<div class=\"box\" id=\"statusbad\"><p>You can only add profiles to a sequence/profile database - this is an isolate database.</p></div>\n";
		return;
	}	elsif ( !$self->can_modify_table('profiles') ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to add new profiles.</p></div>\n";
		return;
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
	print "<h1>Add new $scheme_info->{'description'} profile</h1>\n";
	my $loci        = $self->{'datastore'}->get_scheme_loci($scheme_id);
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
	my $added = 0;
	if ( $q->param('sent') ) {
		my @bad_field_buffer;
		my @fields_with_values;
		my $insert = 1;
		foreach my $field (@$scheme_fields) {
			$newdata{"field:$field"} = $q->param("field:$field");
			$newdata{"field:$field"} =~ s/\\/\\\\/g;
			$newdata{"field:$field"} =~ s/'/\\'/g;
			push @fields_with_values, $field if $newdata{"field:$field"};
			my $field_bad = $self->_is_scheme_field_bad( $scheme_id, $field, $newdata{"field:$field"} );
			if ($field_bad) {
				push @bad_field_buffer, $field_bad if $field_bad;
			}
		}
		$newdata{"field:curator"} = $self->get_curator_id;
		$newdata{"field:sender"}  = $q->param("field:sender");
		if ( !$newdata{"field:sender"} ) {
			push @bad_field_buffer, "Field 'sender' requires a value.";
		}
		foreach (@$loci) {
			$newdata{"locus:$_"} = $q->param("locus:$_");
			my $field_bad = $self->_is_locus_field_bad( $scheme_id, $_, $newdata{"locus:$_"} );
			push @bad_field_buffer, $field_bad if $field_bad;
		}
		if (@bad_field_buffer) {
			print "<div class=\"box\" id=\"statusbad\"><p>There are problems with your record submission.  Please address the following:</p>\n";
			$" = '<br />';
			print "<p>@bad_field_buffer</p></div>\n";
			$insert = 0;
		}

		#Make sure profile not already entered;
		if ($insert) {
			my $qry =
"SELECT profiles.profile_id FROM profiles LEFT JOIN profile_members ON profiles.scheme_id = profile_members.scheme_id AND profiles.profile_id = profile_members.profile_id WHERE profiles.scheme_id=$scheme_id AND ";
			my @locus_temp;
			foreach (@$loci) {
				(my $cleaned = $_) =~ s/'/\\'/g;
				push @locus_temp, "(locus='$cleaned' AND allele_id='$newdata{\"locus:$_\"}')";
			}
			$" = ' OR ';
			$qry .= "(@locus_temp)";
			$qry .= ' GROUP BY profiles.profile_id having count(*)=' . scalar @locus_temp;
			my $sql = $self->{'db'}->prepare($qry);
			eval { $sql->execute; };
			if ($@) {
				$logger->error("Can't execute $qry $@");
			}
			my ($value) = $sql->fetchrow_array;
			if ($value) {
				print "<div class=\"box\" id=\"statusbad\"><p>This allelic profile has already been defined as $primary_key-$value.</p></div>\n";
				$insert = 0;
			}
		}
		if ($insert) {
			my $pk_exists =
			  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM profiles WHERE scheme_id=? AND profile_id=?", $scheme_id, $newdata{"field:$primary_key"} )
			  ->[0];
			if ($pk_exists) {
				print
"<div class=\"box\" id=\"statusbad\"><p>$primary_key-$newdata{\"field:$primary_key\"} has already been defined - please choose a different $primary_key.</p></div>\n";
				$insert = 0;
			}
			my $sender_exists = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM users WHERE id=?",$newdata{'field:sender'})->[0];
			if (!$sender_exists){
				print
"<div class=\"box\" id=\"statusbad\"><p>Invalid sender set.</p></div>\n";
				$insert = 0;
			}
			if ($insert) {
				my @inserts;
				my $qry;
				$qry =
"INSERT INTO profiles (scheme_id,profile_id,sender,curator,date_entered,datestamp) VALUES ($scheme_id,'$newdata{\"field:$primary_key\"}',$newdata{'field:sender'},$newdata{'field:curator'},'today','today')";
				push @inserts, $qry;
				foreach (@$loci) {
					(my $cleaned = $_) =~ s/'/\\'/g;
					$qry =
"INSERT INTO profile_members (scheme_id,locus,profile_id,allele_id,curator,datestamp) VALUES ($scheme_id,'$cleaned','$newdata{\"field:$primary_key\"}','$newdata{\"locus:$_\"}',$newdata{'field:curator'},'today')";
					push @inserts, $qry;
				}
				foreach (@fields_with_values) {
					$qry =
"INSERT INTO profile_fields(scheme_id,scheme_field,profile_id,value,curator,datestamp) VALUES ($scheme_id,'$_','$newdata{\"field:$primary_key\"}','$newdata{\"field:$_\"}',$newdata{'field:curator'},'today')";
					push @inserts, $qry;
				}
				$" = ';';
				eval { 
					$self->{'db'}->do("@inserts");	
				 };
				if ($@) {
					print "<div class=\"box\" id=\"statusbad\"><p>Insert failed - transaction cancelled - no records have been touched.</p>\n";
					if ( $@ =~ /duplicate/ && $@ =~ /unique/ ) {
						print
"<p>Data entry would have resulted in records with either duplicate ids or another unique field with duplicate values.</p>\n";
					} else {
						print "<p>SQL: @inserts</p>";
						$logger->error("Insert failed: @inserts  $@");
						print "<p>Error message: $@</p>\n";
					}
					print "</div>\n";
					$self->{'db'}->rollback();
				} else {
					$added = 1;
					$self->{'db'}->commit()
					  && print "<div class=\"box\" id=\"resultsheader\"><p>$primary_key-$newdata{\"field:$primary_key\"} added!</p>";
					print "<p><a href=\""
					  . $q->script_name
					  . "?db=$self->{'instance'}&amp;page=profileAdd&amp;scheme_id=$scheme_id\">Add another</a> | <a href=\""
					  . $q->script_name
					  . "?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
					return;
				}
			}
		}
	}
	print "<div class=\"box\" id=\"queryform\"><p>Please fill in the fields below - required fields are marked with an exclamation mark (!).</p>\n";
	my $qry = "select id,user_name,first_name,surname from users where id>0 order by surname";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute(); };
	if ($@) {
		$logger->error("Can't execute: $qry");
	} else {
		$logger->debug("Query: $qry");
	}
	my @users;
	my %usernames;
	while ( my ( $userid, $username, $firstname, $surname ) = $sql->fetchrow_array ) {
		push @users, $userid;
		$usernames{$userid} = "$surname, $firstname ($username)";
	}
	print $q->start_form;
	$q->param( 'sent', 1 );
	foreach (qw (page db sent scheme_id)) {
		print $q->hidden($_);
	}
	print "<table>\n";
	print "<tr><td style=\"text-align: right\">$primary_key: !</td><td style=\"white-space: nowrap\">";
	print $q->textfield(
		-name    => "field:$primary_key",
		-size    => $pk_field_info->{'type'} eq 'integer' ? 10 : 30,
		-default => $newdata{$primary_key},
	);
	print "</td></tr>\n";
	foreach (@$loci) {
		my $cleaned = $_;
		$cleaned =~ tr/_/ /;
		print "<tr><td style=\"text-align:right\">$cleaned: !</td><td style=\"white-space: nowrap\">";
		print $q->textfield( -name => "locus:$_", -size => 10, -default => $newdata{$_}, );
		print "</td></tr>\n";
	}
	print "<tr><td style=\"text-align:right\">sender: !</td><td style=\"white-space: nowrap\">";
	print $q->popup_menu( -name => 'field:sender', -values => [ '', @users ], -labels => \%usernames, -default => $newdata{'sender'}, );
	print "</td></tr>\n";
	my $fields =
	  $self->{'datastore'}
	  ->run_list_query( "SELECT field FROM scheme_fields WHERE scheme_id=? AND NOT primary_key ORDER BY field_order", $scheme_id );
	foreach (@$fields) {
		print "<tr><td style=\"text-align: right\">$_: </td><td style=\"white-space: nowrap\">";
		my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $_ );
		print $q->textfield( -name => "field:$_", -size => $field_info->{'type'} eq 'integer' ? 10 : 30, -default => $newdata{$_}, );
		print "</td></tr>\n";
	}
	print "<tr><td style=\"text-align:right\">curator: </td><td style=\"white-space: nowrap\"><b>"
	  . $self->get_curator_name() . ' ('
	  . $self->{'username'}
	  . ")</b></td></tr>\n";
	print "<tr><td style=\"text-align:right\">date_entered: </td><td style=\"white-space: nowrap\"><b>"
	  . $self->get_datestamp()
	  . "</b></td></tr>\n";
	print "<tr><td style=\"text-align:right\">datestamp: </td><td style=\"white-space: nowrap\"><b>"
	  . $self->get_datestamp()
	  . "</b></td></tr>\n";
	print "<tr><td>";
	print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=profileAdd&amp;scheme_id=$scheme_id\" class=\"resetbutton\">Reset</a>";
	print "</td><td style=\"text-align:right; padding-left:2em\">";
	print $q->submit( -name => 'Submit',-class=>'submit' );
	print "</td></tr></table>\n";
	print $q->end_form;
	print "</div>\n";
}

sub _is_scheme_field_bad {
	my ( $self, $scheme_id, $field, $value ) = @_;
	my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
	if ( $scheme_field_info->{'primary_key'} && $value eq '' ) {
		return "Field '$field' is the primary key and requires a value.";
	} elsif ( $value ne '' && $scheme_field_info->{'type'} eq 'integer'
		&& !BIGSdb::Utils::is_int($value) )
	{
		return "Field '$field' must be an integer.";
	} elsif ( $value ne '' && $scheme_field_info->{'value_regex'} && $value !~ /$scheme_field_info->{'value_regex'}/ ) {
		return "Field value is invalid - it must match the regular expression /$scheme_field_info->{'value_regex'}/.";
	}
}

sub _is_locus_field_bad {
	my ( $self, $scheme_id, $locus, $value ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( !$value ) {
		return "Locus '$_' requires a value.";
	} elsif ( $locus_info->{'allele_id_format'} eq 'integer'
		&& !BIGSdb::Utils::is_int($value) )
	{
		return "Locus '$_' must be an integer.";
	} elsif ( $locus_info->{'allele_id_regex'} && $value !~ /$locus_info->{'allele_id_regex'}/ ) {
		return "Allele id value is invalid - it must match the regular expression /$locus_info->{'allele_id_regex'}/.";
	} elsif (!$self->{'datastore'}->sequence_exists($locus,$value)){
		return "Allele $locus $value has not been defined.";
	}
}
1;


