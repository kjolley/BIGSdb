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

package BIGSdb::CuratePubmedQueryPage;
use strict;
use warnings;
use parent qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $q    = $self->{'cgi'};
	print "<h1>PubMed link query/update</h1>\n";
	if ( $q->param('pubmed') ) {
		if ( $q->param('selected') ) {
			if ( !$self->can_modify_table('refs') ) {
				print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to changes references linked to isolates.</p></div>\n";
				return;
			}
			print "<div class=\"box\" id=\"resultsheader\">\n";
			print "<h2>Changes</h2>\n";
			my $pubmed = $q->param('pubmed');
			my @ids    = split /,/, $q->param('ids');
			my $qry    =
			  "SELECT COUNT(*) FROM refs WHERE isolate_id=? AND pubmed_id=?";
			my $sql = $self->{'db'}->prepare($qry);
			my $buffer;
			$buffer =
"<table class=\"resultstable\"><tr><th>Isolate</th><th>Change</th><th>Status</th></tr>\n";
			my $td = 1;
			my $count;

			foreach my $id (@ids) {
				eval { $sql->execute( $id, $pubmed ) };
				$logger->error($@) if $@;
				my ($set) = $sql->fetchrow_array;
				if ( !$q->param("id-$id") && $set ) {
					$buffer .=
"<tr class=\"td$td\"><td>$id</td><td>Remove link to $pubmed</td>\n";
					eval {
						my $qry =
"DELETE FROM refs WHERE isolate_id='$id' AND pubmed_id='$pubmed'";
						$self->{'db'}->do($qry);
					};
					if ($@) {
						$logger->error("Can't delete: $qry");
						$buffer .=
						"<td class=\"statusbad\">Failed</td></tr>\n";
					} else {
						$buffer .=
						"<td class=\"statusgood\">Done</td></tr>\n";
						$logger->debug("Deleted: $qry");
					}
					$self->{'db'}->commit();
					$count++;
					$td = $td == 1 ? 2 : 1;    #row stripes
				}
			}
			$buffer .= "</table>\n";
			if ($count) {
				print $buffer;
			} else {
				print "<p>No changes made.</p>\n";
			}
			print "<p><a href=\""
			  . $q->script_name
			  . "?db=$self->{'instance'}\">Back to main page</a></p>\n";
			  print "</div>\n";
			return;
		} else {
			my $pubmed = $q->param('pubmed');
			if ( !BIGSdb::Utils::is_int($pubmed) ) {
				print
"<div class=\"box\" id=\"statusbad\"><p>PubMed id number should be an integer!</p>\n";
				print "<p><a href=\""
				  . $q->script_name
				  . "?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
				return;
			}
			my $qry =
"SELECT isolate_id FROM refs RIGHT JOIN $self->{'system'}->{'view'} ON isolate_id=id WHERE isolate_id IS NOT NULL AND pubmed_id=? ORDER BY isolate_id";
			my $sql = $self->{'db'}->prepare($qry);
			eval { $sql->execute($pubmed) };
			$logger->error($@) if $@;
			my @ids;
			while ( my ($id) = $sql->fetchrow_array ) {
				push @ids, $id;
			}
			if ( !@ids ) {
				print
"<div class=\"box\" id=\"statusbad\"><p>There are no isolates linked to PubMed id#$pubmed.</p></div>\n";
				print "<p><a href=\""
				  . $q->script_name
				  . "?db=$self->{'instance'}\">Back to main page</a></p>\n";
				return;
			}
			my @headings;
			my $senderfield;
			my $i = 0;
			foreach my $field ( @{ $self->{'xmlHandler'}->get_field_list } ) {
				my %thisfield =
				  $self->{'xmlHandler'}->get_field_attributes($field);
				if (   $self->{'prefs'}->{'maindisplayfields'}->{$field}
					|| $field eq 'id' )
				{
					push @headings, $field;
					$i++;
				}
			}
			$" = ',';
			my $fieldlist = "@headings";
			$qry       =
			  "SELECT $fieldlist FROM $self->{'system'}->{'view'} WHERE id=?";
			$sql = $self->{'db'}->prepare($qry) or die;
			print "<div class=\"box\" id=\"resultstable\">\n";
			print "<h2>PubMed id#$pubmed</h2>\n";
			print
"<p>Deselect isolate ids that you no longer wish to associate with this PubMed id.</p>\n";
			$" = '</th><th>';
			print $q->start_form;
			print $q->submit( -name => 'Select All', -class=>'button' );
			print $q->submit( -name => 'Select None', -class=>'button' );
			print $q->hidden($_) foreach qw (page db pubmed);
			print $q->end_form;
			print "<p />\n";
			print $q->start_form;
			my $checked = 1;

			if ( $q->param('Select None') ) {
				$checked = 0;
			}
			print
"<table class=\"resultstable\"><tr><th>@headings</th><th>Linked</th></tr>\n";
			my $td = 1;
			$" = '</td><td>';
			$qry  = "SELECT first_name,surname FROM users WHERE id=?";
			my $sql2 = $self->{'db'}->prepare($qry);
			foreach my $id (@ids) {
				eval { $sql->execute($id) };
				$logger->error($@) if $@;
				my @data = $sql->fetchrow_array;
				foreach ( my $i = 0 ; $i < scalar @data ; $i++ ) {
					if (   $headings[$i] eq 'sender'
						or $headings[$i] eq 'curator' )
					{
						$data[$i] = $self->get_sender_fullname( $data[$i] );
					}
				}
				{
					no warnings 'uninitialized';
					print "<tr class=\"td$td\"><td>@data</td><td>";
				}
				print $q->checkbox(
					-name    => "id-$id",
					-label   => '',
					-checked => $checked
				);
				print "\n</td></tr>";
				$td = $td == 1 ? 2 : 1;    #row stripes
			}
			print "</table><p />\n";
			print $q->submit(-name=>'Update records',-class=>'submit');
			print $q->hidden($_) foreach qw (page db pubmed);
			$" = ',';
			print $q->hidden( 'ids',      "@ids" );
			print $q->hidden( 'selected', 1 );
			print $q->end_form;
		}
	} elsif ( $q->param('id') ) {
		my $id = $q->param('id');
		if ( $q->param('selected') ) {
			if ( !$self->can_modify_table('refs') ) {
				print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to changes references linked to isolates.</p></div>\n";
				return;
			}
			my @pmids = split /,/, $q->param('pmids');
			print "<div class=\"box\" id=\"resultsheader\">\n";
			print "<h2>Changes</h2>\n";
			my $id  = $q->param('id');
			my $qry =
			  "SELECT COUNT(*) FROM refs WHERE isolate_id=? AND pubmed_id=?";
			my $sql = $self->{'db'}->prepare($qry);
			my $buffer;
			$buffer =
"<table class=\"resultstable\"><tr><th>Isolate</th><th>Change</th><th>Status</th></tr>\n";
			my $td = 1;
			my $count;

			foreach my $pmid (@pmids) {
				eval { $sql->execute( $id, $pmid ) };
				$logger->error($@) if $@;
				my ($set) = $sql->fetchrow_array;
				if ( !$q->param("pmid-$pmid") && $set ) {
					$buffer .=
"<tr class=\"td$td\"><td>$id</td><td>Remove link to $pmid</td>\n";
					$self->{'db'}->do(
"DELETE FROM refs WHERE isolate_id='$id' AND pubmed_id='$pmid'"
					);
					$self->{'db'}->commit
					  && ( $buffer .=
						"<td class=\"statusgood\">Done</td></tr>\n" )
					  || ( $buffer .=
						"<td class=\"statusbad\">Failed</td></tr>\n" );
					$count++;
					$td = $td == 1 ? 2 : 1;    #row stripes
				}
			}
			$buffer .= "</table>\n";
			if ($count) {
				print $buffer;
			} else {
				print "<p>No changes made.</p>\n";
			}
			print "<p><a href=\""
			  . $q->script_name
			  . "?db=$self->{'instance'}\">Back to main page</a></p>\n";
			 print "</div>\n";
			return;
		} else {
			if ( !BIGSdb::Utils::is_int($id) ) {
				print
"<div class=\"box\" id=\"statusbad\"><p>Isolate id number should be an integer!</p>\n";
				print "<p><a href=\""
				  . $q->script_name
				  . "?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
				return;
			}
			my $exists =
			  $self->{'datastore'}->run_simple_query(
"SELECT COUNT(*) FROM $self->{'system'}->{'view'} WHERE id=?",$id
			  )->[0];
			if ( !$exists ) {
				print
				  "<div class=\"box\" id=\"statusbad\"><p>Isolate id#$id does not exist!</p>\n";
				print "<p><a href=\""
				  . $q->script_name
				  . "?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
				return;
			}
			print "<div class=\"box\" id=\"resultstable\">\n";
			print
"<p>If references are shown, you can unlink them from this record by deselecting the appropriate checkbox.</p>\n";
			
			my $qry = "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?";
			my $sql = $self->{'db'}->prepare($qry);
			eval { $sql->execute($id) };
			$logger->error($@) if $@;
			print $q->start_form;
			print "<table class=\"resultstable\">\n";
			my $data = $sql->fetchrow_hashref;
			my $td   = 1;
			foreach my $field ( @{ $self->{'xmlHandler'}->get_field_list } ) {
				if ( $$data{ lc($field) } ) {
					if ( $field eq 'sender' || $field eq 'curator' ) {
						my @userdata =
						  $self->_get_user_info( $$data{ lc($field) } );
						$$data{ lc($field) } =
						  "$userdata[0] $userdata[1] ($userdata[2])";
					}
					print
"<tr class=\"td$td\"><th>$field</th><td style=\"text-align:left\" colspan=\"4\">$$data{lc($field)}</td></tr>\n";
					$td = $td == 1 ? 2 : 1;    #row stripes
				}
			}
			$qry =
"SELECT pubmed_id FROM refs WHERE isolate_id=? ORDER BY pubmed_id";
			$sql = $self->{'db'}->prepare($qry);
			eval { $sql->execute($id) };
			$logger->error($@) if $@;
			my @pmids;
			while ( my ($pmid) = $sql->fetchrow_array ) {
				push @pmids, $pmid;
			}
			if ( !@pmids ) {
				print
"<tr class=\"td$td\"><th>reference</th><td class=\"statusbad\">No references set!</td></tr>\n";
			} else {
				foreach my $pmid (@pmids) {
					$self->_print_maintable_reference( 'reference', $pmid, $td );
					$td = $td == 1 ? 2 : 1;    #row stripes
				}
			}
			print "</table>\n";
			print $q->hidden($_) foreach qw (page db id);
			$" = ',';
			print $q->hidden( 'pmids',    "@pmids" );
			print $q->hidden( 'selected', 1 );
			print "<p />\n";
			print $q->submit(-name=>'Update',-class=>'submit');
			print $q->end_form;
		}
	} else {
		print "<div class=\"box\" id=\"queryform\">\n";
		print "<h2>Links by PubMed id</h2>\n";
		print "<p>Please enter PubMed id.</p>\n";
		print $q->start_form;
		print "<table><tr><td>PubMed id:</td><td>\n";
		print $q->textfield( -name => 'pubmed', -size => 12 );
		print "</td><td>\n";
		print $q->submit(-name=>'Retrieve',-class=>'submit');
		print "</td></tr></table>\n";
		print $q->hidden($_) foreach qw (page db);
		print $q->end_form;
		print "<h2>Links by isolate id</h2>\n";
		print "<p>Please enter isolate id.</p>\n";
		print $q->start_form;
		print "<table><tr><td>Isolate id:</td><td>\n";
		print $q->textfield( -name => 'id', -size => 12 );
		print "</td><td>\n";
		print $q->submit(-name=>'Retrieve',-class=>'submit');
		print "</td></tr></table>\n";
		print $q->hidden($_) foreach qw (page db);
		print $q->end_form;
	}
	print "</div>";
}

sub get_title {
	my ($self)   = @_;
	my $desc  = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Update or delete PubMed links - $desc";
}

sub _get_user_info {
	my ( $self, $userid, $fromprofiledb ) = @_;
	my $sql;
	my $qry =
	  "SELECT first_name,surname,affiliation,email FROM users WHERE id=?;";
	$sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute($userid) };
	$logger->error($@) if $@;
	return $sql->fetchrow_array;
}

sub _print_maintable_reference {
	my ( $self, $fieldname, $pmid, $td ) = @_;
	my $q = $self->{'cgi'};
	if ( $self->{'config'}->{'refdb'} ) {
		my %att = (
			dbase_name => $self->{'config'}->{'refdb'},
			host       => $self->{'system'}->{'host'},
			port       => $self->{'system'}->{'port'},
			user       => $self->{'system'}->{'user'},
			password   => $self->{'system'}->{'pass'}
		);
		my $dbr =
		  $self->{'datastore'}->get_data_connector->get_connection( \%att );
		if ($dbr) {
			my $sqlr =
			  $dbr->prepare(
				"SELECT year,journal,volume,pages,title FROM refs WHERE pmid=?"
			  );
			my $sqlr2 =
			  $dbr->prepare("SELECT surname,initials FROM authors WHERE id=?");
			eval { $sqlr->execute($pmid) };
			$logger->error($@) if $@;
			my $sqlr3 =
			  $dbr->prepare(
				"SELECT author FROM refauthors WHERE pmid=? ORDER BY position"
			  );
			eval { $sqlr3->execute($pmid) };
			$logger->error($@) if $@;
			my @authors;
			while ( my ($authorid) = $sqlr3->fetchrow_array ) {
				push @authors, $authorid;
			}
			my ( $year, $journal, $volume, $pages, $title ) =
			  $sqlr->fetchrow_array;
			undef my $temp;
			foreach my $author (@authors) {
				eval { $sqlr2->execute($author) };
				$logger->error($@) if $@;
				my ( $surname, $initials ) = $sqlr2->fetchrow_array();
				$temp .= "$surname $initials, ";
			}
			$temp =~ s/, $//;
			if ($title) {
				print
"<tr class=\"td$td\"><th>$fieldname</th><td align='left'><a href='http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=Retrieve&amp;db=PubMed&amp;list_uids=$pmid&amp;dopt=Abstract'>$pmid</a></td><td colspan=\"2\" align=\"left\">$temp ($year) <i>$journal</i> <b>$volume:</b>$pages<br />$title</td>\n";
			} else {
				print
"<tr class=\"td$td\"><th>$fieldname</th><td align='left'>$pmid</td><td colspan=\"2\" align='left'><a href='http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=Retrieve&amp;db=PubMed&amp;list_uids=$pmid&amp;dopt=Abstract'>PubMed Abstract</a></td>";
			}
			$sqlr->finish;
			$sqlr2->finish;
		} else {
			$logger->warn('Reference database not available.');
			print
"<tr class=\"td$td\"><th>$fieldname</th><td align='left'>$pmid</td><td align='left'><a href='http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=Retrieve&amp;db=PubMed&amp;list_uids=$pmid&amp;dopt=Abstract'>PubMed Abstract</a></td>";
		}
	} else {
		print
"<tr class=\"td$td\"><th>$fieldname</th><td align='left'>$pmid</td><td align='left'><a href='http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=Retrieve&amp;db=PubMed&amp;list_uids=$pmid&amp;dopt=Abstract'>PubMed Abstract</a></td>";
	}
	print "<td>";
	print $q->checkbox(
		-name    => "pmid-$pmid",
		-checked => 1,
		-label   => ''
	);
	print "</td>";
	print "</tr>\n";
}
1;


