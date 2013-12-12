#!/usr/bin/perl -T
#
#bigsdb_getrefs.pl
#Written by Keith Jolley
#Copyright (c) 2003, 2009, 2012 University of Oxford
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

use strict;
use warnings;
use 5.010;
use DBI;
use LWP::Simple;
use XML::Parser;
use Bio::Biblio::IO;
use List::MoreUtils qw(uniq);
## no critic (RequireCarping)

my %tablelist;
my @refs;
my $conflist = $ARGV[0];

if ( !$ARGV[0] ) {
	print "Usage getrefs.pl <conf file>\n";
	exit(1);
}

#Read in database list from getrefs.conf
if ( -e $conflist ) {
	open( my $fh, '<', $conflist );
	while ( my $line = <$fh> ) {
		next if !$line || $line =~ /^#/;
		my ( $dbase, $list ) = split /\s+/, $line;
		$list =~ s/\n//g;
		$tablelist{$dbase} = $list;
	}
	close $fh;
} else {
	print "Configuration file '$conflist' does not exist!\n";
	exit(1);
}

#Find all PubMed references in reference tables
foreach my $dbase ( keys %tablelist ) {
	my @tables = split /,/, $tablelist{$dbase};
	foreach (@tables) {
		$_ =~ s/\s//g;
		my $db = DBI->connect( "DBI:Pg:dbname=$dbase", 'postgres' ) or die "couldn't open db" . DBI->errstr;
		my $sql;
		my $qry = "SELECT DISTINCT pubmed_id FROM $_;";
		$sql = $db->prepare($qry) or die "couldn't prepare";
		$sql->execute;
		while ( my ($ref) = $sql->fetchrow_array() ) {
			push @refs, $ref;
		}
		$sql->finish;
		$db->disconnect;
	}
}

@refs = uniq @refs;

my $db = DBI->connect( 'DBI:Pg:dbname=refs', 'postgres' ) or die "couldn't open template db" . DBI->errstr;

#Here we query website and extract reference data
foreach my $refid (@refs) {

	#Check whether the reference is already in the database
	my $retval = ( runquery("SELECT pmid FROM refs WHERE pmid=$refid;") );
	if ( !$retval ) {
		my $url = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=PubMed&id=$refid&report=medline&retmode=xml";
		if ( my $citationxml = get $url) {
			if ( $citationxml !~ /\*\*\* No Documents Found \*\*\*/ ) {
				my $io = Bio::Biblio::IO->new( '-data' => $citationxml, '-format' => 'pubmedxml' );
				sleep 10;    #Let's be nice to the remote server.
				my $bibref  = $io->next_bibref;
				next if !$bibref;
				my $pmid    = $bibref->pmid;
				my $title   = $bibref->title;
				my @authors = &getauthors($bibref);
				my @authorlist;
				foreach my $author (@authors) {
					my ( $surname, $initials );
					if ( $author =~ /([\w\s'-]+),(\w+)/ ) {
						$surname  = $1;
						$initials = $2;
						$surname =~ s/'/&#39;/g;
					}
					my $qry = "SELECT id FROM authors WHERE surname='$surname' AND initials='$initials';";
					my ($authorid) = runquery($qry);
					if ( !$authorid ) {
						print "surname: $surname; initials: $initials\n";
						$db->do("INSERT INTO authors (surname,initials) VALUES ('$surname', '$initials')");
						($authorid) = runquery($qry);
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

				if ( $bibref->date =~ /^(\d\d\d\d)/ ) {
					$year = $1;
				} else {
					$year = 0;
				}
				my $abstract = $bibref->abstract;
				$abstract //= '';
				$abstract =~ s/\'//g;
				$title    =~ s/\'//g;
				$journal  =~ s/\'//g;
				my $qry  = "SELECT pmid FROM refs WHERE pmid='$pmid';";
				my $indb = runquery($qry);
				if ( !$indb ) {
					local $" = '; ';
					print "pmid : $pmid\n";
					print "authors: @authors\n";
					print "@authorlist\n";
					print "year: $year\n";
					print "journal: $journal\n";
					print "volume: $volume\n";
					print "pages: $pages\n";
					print "title: $title\n";
					print "abstract: $abstract\n";
					print "\n\n";
					$db->do(
"INSERT INTO refs (pmid,year,journal,volume,pages,title,abstract) VALUES ('$pmid','$year','$journal','$volume','$pages','$title','$abstract')"
					  )
					  or print "Failed to insert id: $pmid!\n";
					my $pos = 1;

					foreach my $authorid (@authorlist) {
						$db->do("INSERT INTO refauthors (pmid,author,position) VALUES ($pmid,$authorid,$pos)")
						  or print "Failed to insert ref author: $pmid - $authorid!\n";
						$pos++;
					}
				}
			}
		} else {
			print "Ref $refid could not be retrieved.\n";
		}
	}
}

sub getauthors {
	my ($bibref) = @_;
	my $authors  = $bibref->authors;
	my @people   = @$authors;          #array ref of Bio::Biblio::Provider
	my @authors;
	foreach my $person (@people) {
		my $value = $person->lastname . ',' . $person->initials;
		$value =~ s/\'//g;
		push @authors, $value;
	}
	return @authors;
}

sub runquery {
	my ($qry) = @_;
	my $sql = $db->prepare($qry) or die "couldn't prepare" . $db->errstr;
	$sql->execute;
	return $sql->fetchrow_array;
}


