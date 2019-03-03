#!/usr/bin/env perl
#Written by Keith Jolley
#Copyright (c) 2003-2019 University of Oxford
#E-mail: keith.jolley@zoo.ox.ac.uk
#
#Find out which references are cited in the databases
#Grab details from PubMed and store in local database
##
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
#Databases are defined in a conf file with each database on a single
#line separated by white space and then a comma-separated list of tables
#that can contain reference information.
#e.g. the getrefs.conf file for an isolate and seqdef database looks like:
#
#pubmlst_bigsdb_neisseria_isolates               refs
#pubmlst_bigsdb_neisseria_seqdef                 profile_refs,sequence_refs,locus_refs
#
#
#Run the script from CRON as bigsdb_getrefs.pl <conf file>
#
#Please note that Bio::Biblio is no longer a part of BioPerl (since version 1.6.920).
#This can be installed from CPAN if a package isn't available with your Linux distribution.
#
#Version: 20190303
use strict;
use warnings;
use 5.010;
use DBI;
use LWP::Simple;
use XML::Parser;
use Bio::Biblio::IO;
use List::MoreUtils qw(uniq);
use Carp;
binmode( STDOUT, ':encoding(UTF-8)' );
my $refs_db = 'bigsdb_refs';
my %tablelist;
my $conflist = $ARGV[0];

if ( !$ARGV[0] ) {
	say 'Usage getrefs.pl <conf file>';
	exit(1);
}
my $dbr = DBI->connect( "DBI:Pg:dbname=$refs_db", undef, undef, { Username => 'postgres', pg_enable_utf8 => 1 } )
  or croak 'could not open db' . DBI->errstr;
main();

sub main {
	my $refs = get_pmids();

	#Here we query website and extract reference data
	foreach my $pmid (@$refs) {

		#Check whether the reference is already in the database
		my $retval = ( runquery( 'SELECT pmid FROM refs WHERE pmid=?', $pmid ) );
		next if $retval;
		my $url =
		  'http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?' . "db=PubMed&id=$pmid&report=medline&retmode=xml";
		if ( my $citationxml = get $url) {
			next if $citationxml =~ /\*\*\*\ No\ Documents\ Found\ \*\*\*/x;
			my $io = Bio::Biblio::IO->new( -data => $citationxml, -format => 'pubmedxml' );
			sleep 5;    #Let's be nice to the remote server.
			my $bibref = $io->next_bibref;
			next if !$bibref;
			my $pmid    = $bibref->pmid;
			my $title   = $bibref->title;
			my @authors = getauthors($bibref);
			my @authorlist;

			foreach my $author (@authors) {
				my ( $surname, $initials );
				if ( $author =~ /([\w\s'-]+),(\w+)/x ) {
					$surname  = $1;
					$initials = $2;
				}
				my $qry = 'SELECT id FROM authors WHERE (surname,initials)=(?,?)';
				my ($authorid) = runquery( $qry, $surname, $initials );
				if ( !$authorid ) {
					print "surname: $surname; initials: $initials\n";
					$dbr->do( 'INSERT INTO authors (surname,initials) VALUES (?,?)', undef, $surname, $initials );
					($authorid) = runquery( $qry, $surname, $initials );
				}
				push @authorlist, $authorid;
			}
			my $journal = $bibref->journal->medline_ta;
			$journal = ' ' if !$journal;
			my $volume = $bibref->volume;
			$volume = '[Epub ahead of print]' if !$volume;
			my $pages = $bibref->medline_page;
			$pages = ' ' if !$pages;
			my $year;

			if ( $bibref->date =~ /^(\d\d\d\d)/x ) {
				$year = $1;
			} else {
				$year = 0;
			}
			my $abstract = $bibref->abstract;
			$abstract //= '';
			my $qry = 'SELECT pmid FROM refs WHERE pmid=?';
			my $indb = runquery( $qry, $pmid );
			if ( !$indb ) {
				local $" = '; ';
				say "pmid : $pmid";
				say "authors: @authors";
				say "year: $year";
				say "journal: $journal";
				say "volume: $volume";
				say "pages: $pages";
				say "title: $title";
				say "abstract: $abstract";
				say "\n";
				$dbr->do( 'INSERT INTO refs (pmid,year,journal,volume,pages,title,abstract) VALUES (?,?,?,?,?,?,?)',
					undef, $pmid, $year, $journal, $volume, $pages, $title, $abstract )
				  or say "Failed to insert id: $pmid!";
				my $pos = 1;

				foreach my $authorid (@authorlist) {
					$dbr->do( 'INSERT INTO refauthors (pmid,author,position) VALUES (?,?,?)',
						undef, $pmid, $authorid, $pos )
					  or say "Failed to insert ref author: $pmid - $authorid!";
					$pos++;
				}
			}
		} else {
			say "Ref $pmid could not be retrieved.";
		}
	}
	return;
}

sub get_pmids {

	#Read in database list from getrefs.conf
	if ( -e $conflist ) {
		open( my $fh, '<', $conflist ) || croak "Can't open $conflist for reading";
		while ( my $line = <$fh> ) {
			next if !$line || $line =~ /^\#/x;
			my ( $dbase, $list ) = split /\s+/x, $line;
			$list =~ s/\n//gx;
			$tablelist{$dbase} = $list;
		}
		close $fh;
	} else {
		say "Configuration file '$conflist' does not exist!";
		exit(1);
	}

	#Find all PubMed references in reference tables
	my @refs;
	foreach my $dbase ( keys %tablelist ) {
		my @tables = split /,/x, $tablelist{$dbase};
		foreach my $table (@tables) {
			$table =~ s/\s//gx;
			my $db = DBI->connect( "DBI:Pg:dbname=$dbase", undef, undef, { Username => 'postgres' } )
			  or croak 'could not open db' . DBI->errstr;
			my $sql;
			my $qry = "SELECT DISTINCT pubmed_id FROM $table;";
			$sql = $db->prepare($qry) or croak 'could not prepare';
			$sql->execute;
			while ( my ($ref) = $sql->fetchrow_array ) {
				if ( length $ref < 4 ) {
					say "$dbase: Unlikely PMID $ref.";
					exit;
				}
				push @refs, $ref;
			}
			$sql->finish;
			$db->disconnect;
		}
	}
	@refs = uniq @refs;
	return \@refs;
}

sub getauthors {
	my ($bibref) = @_;
	my $authors = $bibref->authors;
	my @people = ref $authors eq 'ARRAY' ? @$authors : ();    #array ref of Bio::Biblio::Provider
	my @authors;
	foreach my $person (@people) {
		eval {
			my $value = $person->lastname . ',' . $person->initials;
			push @authors, $value;
		};
	}
	return @authors;
}

sub runquery {
	my ( $qry, @args ) = @_;
	my $sql = $dbr->prepare($qry) or croak 'could not prepare' . $dbr->errstr;
	$sql->execute(@args);
	return $sql->fetchrow_array;
}
