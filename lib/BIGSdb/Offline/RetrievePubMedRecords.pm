#Written by Keith Jolley
#Copyright (c) 2019, University of Oxford
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
package BIGSdb::Offline::RetrievePubMedRecords;
use strict;
use warnings;
use 5.010;
use List::MoreUtils qw(uniq);
use LWP::UserAgent;
use Bio::Biblio::IO;
use parent qw(BIGSdb::Offline::Script);

#This just initiates the script - we need to do this so that we can determine
#the database name without extracting PubMed ids.
sub run_script { }

sub get_dbase_name {
	my ($self) = @_;
	return $self->{'system'}->{'db'};
}

sub run {
	my ($self) = @_;
	return if !$self->{'system'}->{'db'};
	my ( $new_pmids, $suspicious ) = $self->_get_new_pmids;
	if ( @$suspicious && !$self->{'options'}->{'quiet'} && !$self->{'options'}->{'force'} ) {
		say qq($self->{'system'}->{'db'} suspicious PMIDs:);
		say q((use --force option to add these));
		say $_ foreach @$suspicious;
		print qq(\n);
	}
	if ( $self->{'options'}->{'force'} && @$suspicious ) {
		push @$new_pmids, @$suspicious;
	}
	return if !@$new_pmids;
	my $url = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?'
	  . 'db=PubMed&report=medline&retmode=xml&tool=BIGSdb&email=keith.jolley@zoo.ox.ac.uk';
	my $user_agent = LWP::UserAgent->new( agent => 'BIGSdb' );
	local $" = q(,);
	my $response = $user_agent->post( $url, content => "id=@$new_pmids" );
	my $xml = $response->content;
	return if $xml =~ /\*\*\*\ No\ Documents\ Found\ \*\*\*/x;
	my $io            = Bio::Biblio::IO->new( -data => $xml, -format => 'pubmedxml' );
	my $authors       = $self->{'datastore'}->get_available_authors;
	my %known_authors = map { ; qq($_->{'surname'}|$_->{'initials'}) => 1 } @$authors;

	while ( my $bibref = $io->next_bibref ) {
		my $pmid       = $bibref->pmid;
		my $title      = $bibref->title;
		my $author_ids = [];
		my @author_names;
		my @authors = ref $bibref->authors eq 'ARRAY' ? @{ $bibref->authors } : ();
		foreach my $author (@authors) {
			my $surname  = $author->lastname;
			my $initials = $author->initials;
			next if !defined $surname || !defined $initials;
			push @author_names, "$surname,$initials";
			if ( !$known_authors{"$surname|$initials"} ) {
				$self->{'datastore'}->add_author( $surname, $initials );
				$known_authors{"$surname|$initials"} = 1;
			}
			my $author_id = $self->{'datastore'}->get_author_id( $surname, $initials );
			push @$author_ids, $author_id if $author_id;
		}
		my $journal = $bibref->journal->medline_ta;
		$journal = ' ' if !$journal;
		my $volume = $bibref->volume;
		$volume = '[Epub ahead of print]' if !$volume;
		my $pages = $bibref->medline_page;
		$pages = ' ' if !$pages;
		my $year;
		if (   ( defined $bibref->date && $bibref->date =~ /^(\d\d\d\d)/x )
			|| ( defined $bibref->medline_date && $bibref->medline_date =~ /(\d\d\d\d)/x ) )
		{
			$year = $1;
		} else {
			$year = 0;
		}
		my $abstract = $bibref->abstract;
		$abstract //= '';
		if ( !$self->{'options'}->{'quiet'} ) {
			local $" = '; ';
			say "pmid : $pmid";
			say "authors: @author_names";
			say "year: $year";
			say "journal: $journal";
			say "volume: $volume";
			say "pages: $pages";
			say "title: $title";
			say "abstract: $abstract\n";
		}
		$self->{'datastore'}->add_reference(
			{
				pmid        => $pmid,
				year        => $year,
				journal     => $journal,
				volume      => $volume,
				pages       => $pages,
				title       => $title,
				abstract    => $abstract,
				author_list => $author_ids
			}
		);
	}
	sleep 2 if $self->{'options'}->{'pause'};
	return;
}

sub _get_new_pmids {
	my ($self) = @_;
	my @tables;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		@tables = qw(refs scheme_refs);
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		@tables = qw(profile_refs sequence_refs locus_refs scheme_refs);
	} else {
		$self->{'logger'}->error("$self->{'instance'} is not a valid sequence or isolate database configuration.");
		return;
	}
	my @pmids;
	foreach my $table (@tables) {
		my $pmids = $self->{'datastore'}
		  ->run_query( "SELECT DISTINCT pubmed_id FROM $table", undef, { fetch => 'col_arrayref' } );
		push @pmids, @$pmids;
	}
	@pmids = uniq sort { $a <=> $b } @pmids;
	my $downloaded_refs = $self->{'datastore'}->get_available_refs;
	my %downloaded = map { $_ => 1 } @$downloaded_refs;
	my %new;
	my %suspicious;
	my $last_id;
	foreach my $pmid (@pmids) {
		next if $downloaded{$pmid};
		if ( $last_id && $pmid == $last_id + 1 ) {    #Sequential PMIDs are unlikely to be correct
			$suspicious{$pmid}    = 1;
			$suspicious{$last_id} = 1;
			delete $new{$last_id};
		} elsif ( $pmid < 100_000 ) {                 #Very low PMIDs are unlikely to be correct
			$suspicious{$pmid} = 1;
		} else {
			$new{$pmid} = 1;
		}
		$last_id = $pmid;
	}
	my $new_list        = [ sort { $a <=> $b } keys %new ];
	my $suspicious_list = [ sort { $a <=> $b } keys %suspicious ];
	return ( $new_list, $suspicious_list );
}
1;
