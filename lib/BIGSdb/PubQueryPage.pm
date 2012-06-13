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
package BIGSdb::PubQueryPage;
use strict;
use warnings;
use Error qw(:try);
use parent qw(BIGSdb::ResultsTablePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self)    = @_;
	my $system    = $self->{'system'};
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	my %att       = (
		'dbase_name' => $self->{'config'}->{'ref_db'},
		'host'       => $system->{'host'},
		'port'       => $system->{'port'},
		'user'       => $system->{'user'},
		'password'   => $system->{'pass'}
	);
	print "<h1>Publications cited in the $system->{'description'} database</h1>\n";
	my $dbr;
	my $continue = 1;
	try {
		$dbr = $self->{'dataConnector'}->get_connection( \%att );
	} catch BIGSdb::DatabaseConnectionException with {
		print "<div class=\"box\" id=\"statusbad\"><p>No connection to reference database</p></div>\n";
		$continue = 0;
	};
	return if !$continue;
	
	if ( $system->{'dbtype'} eq 'isolates' ) {
		my $ref_count = $self->{'datastore'}->run_simple_query("SELECT COUNT (DISTINCT pubmed_id) FROM refs")->[0];
		if ( !$ref_count ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No isolates have been linked to PubMed records.</p></div>\n";
			return;
		}
	} else {
		my $ref_count =
		  $self->{'datastore'}->run_simple_query( "SELECT COUNT (DISTINCT pubmed_id) FROM profile_refs WHERE scheme_id=?", $scheme_id )
		  ->[0];
		if ( !$ref_count ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No profiles have been linked to PubMed records.</p></div>\n";
			return;
		}
	}
	if ( !$q->param('query') ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No query has been passed.</p></div>\n";
		return;
	}
	$q->param('query') =~ /pubmed_id=\'(\d*)\'/;
	my $pmid = $q->param('pmid') || $1;
	print "<h2>Citation query (PubMed id: $pmid)</h2>\n";
	print "<div class=\"box\" id=\"abstract\">\n";
	my $sql  = $dbr->prepare("SELECT year,journal,volume,pages,title,abstract FROM refs WHERE pmid=?");
	my $sql2 = $dbr->prepare("SELECT surname,initials FROM authors WHERE id=?");
	my $sql3 = $dbr->prepare("SELECT author FROM refauthors WHERE pmid=? ORDER BY position");
	eval { $sql->execute($pmid) };
	$logger->error($@) if $@;
	my ( $year, $journal, $volume, $pages, $title, $abstract ) = $sql->fetchrow_array;
	eval { $sql3->execute($pmid) };
	$logger->error($@) if $@;
	my @authors;

	while ( my ($authorid) = $sql3->fetchrow_array ) {
		push @authors, $authorid;
	}
	my $temp;
	foreach my $author (@authors) {
		eval { $sql2->execute($author) };
		$logger->error($@) if $@;
		my ( $surname, $initials ) = $sql2->fetchrow_array;
		$temp .= "$surname $initials, ";
	}
	$temp =~ s/, $// if $temp;
	$abstract = "No abstract available" if !$abstract; 
	print "<p>\n";
	print "$temp\n" if $temp;
	print " ($year)\n" if $year;
	print " <i>$journal</i> <b>$volume:</b>$pages<br />\n" if $journal && $volume && $pages; 	
	if ($title) {
		print "<b>$title</b><br />\n";
		print "$abstract</p>\n";
	} else {
		print "No details available for this publication.</p>";
	}
	print "</div>\n";
	$sql->finish;
	$sql2->finish;
	$q->param( 'curate', 1 ) if $self->{'curate'};
	$self->paged_display( $system->{'dbtype'} eq 'isolates' ? $self->{'system'}->{'view'} : 'profiles',
		$q->param('query'), '', [qw (curate scheme_id)] );
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Publication query - $desc";
}
1;
