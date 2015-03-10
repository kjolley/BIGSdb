#Written by Keith Jolley
#Copyright (c) 2010-2015, University of Oxford
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
use 5.010;
use Error qw(:try);
use parent qw(BIGSdb::ResultsTablePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $q      = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id') // 0;
	my %att = (
		dbase_name => $self->{'config'}->{'ref_db'},
		host       => $system->{'host'},
		port       => $system->{'port'},
		user       => $system->{'user'},
		password   => $system->{'pass'}
	);
	say "<h1>Publications cited in the $system->{'description'} database</h1>";
	my $dbr;
	my $continue = 1;
	try {
		$dbr = $self->{'dataConnector'}->get_connection( \%att );
	}
	catch BIGSdb::DatabaseConnectionException with {
		say qq(<div class="box" id="statusbad"><p>No connection to reference database</p></div>);
		$continue = 0;
	};
	return if !$continue;
	if ( $system->{'dbtype'} eq 'isolates' ) {
		my $refs_exist = $self->{'datastore'}->run_query("SELECT EXISTS(SELECT * FROM refs)");
		if ( !$refs_exist ) {
			say qq(<div class="box" id="statusbad"><p>No isolates have been linked to PubMed records.</p></div>);
			return;
		}
	} else {
		my $refs_exist = $self->{'datastore'}->run_query( "SELECT EXISTS(SELECT * FROM profile_refs WHERE scheme_id=?)", $scheme_id );
		if ( !$refs_exist ) {
			say qq(<div class="box" id="statusbad"><p>No profiles have been linked to PubMed records.</p></div>);
			return;
		}
	}
	my $pmid = $q->param('pmid');
	if ( !$pmid ) {
		say qq(<div class="box" id="statusbad"><p>No pmid passed.</p>);
		return;
	}
	my $qry;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$qry = "SELECT * FROM $self->{'system'}->{'view'} LEFT JOIN refs on refs.isolate_id=$self->{'system'}->{'view'}.id "
		  . "WHERE pubmed_id=$pmid ORDER BY $self->{'system'}->{'view'}.id;";
	} else {
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		my $primary_key = $scheme_info->{'primary_key'};
		$qry = "SELECT * FROM profile_refs LEFT JOIN scheme_$scheme_id on profile_refs.profile_id=scheme_$scheme_id\.$primary_key "
		  . "WHERE pubmed_id=$pmid AND profile_refs.scheme_id=$scheme_id ORDER BY $primary_key";
	}
	say "<h2>Citation query (PubMed id: $pmid)</h2>";
	say "<div class=\"box\" id=\"abstract\">";
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
	say "<p>";
	say "$temp"                                        if $temp;
	say " ($year)"                                     if $year;
	say " <i>$journal</i> <b>$volume:</b>$pages<br />" if $journal && $volume && $pages;
	if ($title) {
		say "<b>$title</b><br />";
		say "$abstract</p>";
	} else {
		say "No details available for this publication.</p>";
	}
	say "</div>";
	$sql->finish;
	$sql2->finish;
	$q->param( curate => 1 ) if $self->{'curate'};
	my $table = $system->{'dbtype'} eq 'isolates' ? $self->{'system'}->{'view'} : 'profiles';
	my $args = { table => $table, query => $qry, hidden_attributes => [qw (curate scheme_id pmid)] };
	$args->{'passed_qry_file'} = $q->param('query_file') if defined $q->param('query_file');
	$self->paged_display($args);
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Publication query - $desc";
}
1;
