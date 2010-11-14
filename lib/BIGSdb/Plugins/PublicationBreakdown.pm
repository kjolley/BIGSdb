#PublicationBreakdown.pm - PublicationBreakdown plugin for BIGSdb
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
package BIGSdb::Plugins::PublicationBreakdown;
use strict;
use base qw(BIGSdb::Plugin);
use base qw(BIGSdb::IsolateInfoPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);

sub get_attributes {
	my %att = (
		name        => 'Publication Breakdown',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Breakdown of query results by publication',
		category    => 'Breakdown',
		buttontext  => 'Publications',
		menutext    => 'Publications',
		module      => 'PublicationBreakdown',
		version     => '1.0.0',
		dbtype      => 'isolates',
		section     => 'breakdown,postquery',
		input       => 'query',
		requires    => 'refdb',
		order       => 30,
	);
	return \%att;
}

sub run {
	my ($self)   = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	print "<h1>Publication breakdown of dataset</h1>\n";
	if ( !$self->{'config'}->{'refdb'} ) {
		print "<div class=\"box\" id=\"statusbad\">No reference database has been defined.</p></div>\n";
		return;
	}
	my %prefs;
	my $qry_ref = $self->get_query($query_file);
	return if ref $qry_ref ne 'SCALAR';
	my $qry = $$qry_ref;
	$qry =~ s/ORDER BY.*$//g;
	my $isolate_qry = $qry;
	$logger->debug("Breakdown query: $qry");
	return if !$self->create_temp_tables($qry_ref);
	$qry =~ s/SELECT \* FROM $self->{'system'}->{'view'}/SELECT id FROM $self->{'system'}->{'view'}/;
	my $new_qry = "SELECT DISTINCT(refs.pubmed_id) FROM refs WHERE refs.isolate_id IN ($qry)";
	my $sql = $self->{'db'}->prepare($new_qry);
	eval { $sql->execute(); };
	if ($@) {
		$logger->error("Can't execute $qry $@");
		return;
	}
	my @list;
	while ( my ($pmid) = $sql->fetchrow_array ) {
		push @list, $pmid if $pmid;
	}
	my $order;
	my $guid = $self->get_guid;
#	my $guid = $q->cookie( -name => 'guid' );
	try {
		$order = $self->{'prefstore'}->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'PublicationBreakdown', 'order' );
		$order = 'pmid'          if $order eq 'PubMed id';
		$order = 'isolates desc' if $order eq 'number of isolates';
	  }
	  catch BIGSdb::DatabaseNoRecordException with {
		$order = 'isolates desc';
	  };
	$order .= ',pmid' if !$order eq 'pmid';
	if ( $self->_create_temp_ref_table( \@list, \$isolate_qry ) ) {
		my $authornames = $self->_get_author_list;
		print "<div class=\"box\" id=\"queryform\">\n";
		print "Filter by author: \n";
		print $q->startform;
		foreach (qw (db name query_file)) {
			print $q->hidden($_);
		}
		print $q->hidden('page');
		print $q->popup_menu( -name => 'author', -values => $authornames );
		print $q->submit(-class=>'submit');
		print $q->endform;
		print "</div>\n";
		my $refquery = "SELECT * FROM temp_refs ORDER BY $order";
		my $sql      = $self->{'db'}->prepare($refquery);
		eval { $sql->execute; };

		if ($@) {
			$logger->error("Can't execute $refquery $@");
			return;
		}
		my $buffer;
		my $td = 1;
		while ( my $refdata = $sql->fetchrow_hashref ) {
			my $author_filter = $q->param('author');
			next if ( $author_filter && $author_filter ne 'All authors' && $refdata->{'authors'} !~ /$author_filter/ );
			$buffer .=
"<tr class=\"td$td\"><td><a href='http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=Retrieve&amp;db=PubMed&amp;list_uids=$refdata->{'pmid'}&amp;dopt=Abstract'>$refdata->{'pmid'}</a></td><td>$refdata->{'year'}</td><td style=\"text-align:left\">";
			if ( !$refdata->{'authors'} && !$refdata->{'title'} ) {
				$buffer .= "No details available.</td>\n";
			} else {
				$buffer .= "$refdata->{'authors'} ";
				$buffer .= "($refdata->{'year'}) " if $refdata->{'year'};
				$buffer .= "$refdata->{'journal'} ";
				$buffer .= "<b>$refdata->{'volume'}:</b> "
				  if $refdata->{'volume'};
				$buffer .= " $refdata->{'pages'}</td>\n";
			}
			$buffer .= "<td style=\"text-align:left\">$refdata->{'title'}</td>\n";
			if ( $query_file && $q->param('calling_page') ne 'browse' ) {
				$buffer .= "<td>$refdata->{'isolates'}</td>";
			}
			$buffer .= "<td>" . $self->get_link_button_to_ref( $refdata->{'pmid'} ) . "</td>\n";
			$buffer .= "</tr>\n";
			$td = $td == 1 ? 2 : 1;
		}
		if ($buffer) {
			print "<div class=\"box\" id=\"resultstable\">\n";
			print "<table class=\"tablesorter\" id=\"sortTable\">\n<thead>\n";
			print "<tr><th>PubMed id</th><th>Year</th><th>Citation</th><th>Title</th>";
			print "<th>Isolates in query</th>" if $query_file && $q->param('calling_page') ne 'browse';
			print "<th>Isolates in database</th><th class=\"{sorter: false}\">Display</th></tr>\n</thead>\n<tbody>\n";
			print "$buffer";
			print "</tbody></table>\n</div>\n";
		} else {
			print "<div class=\"box\" id=\"resultsheader\"><p>No PubMed records have been linked to isolates.</p></div>\n";
		}
	}
}

sub get_link_button_to_ref {
	my ( $self, $ref ) = @_;
	my $buffer;
	my $qry =
"SELECT COUNT(refs.isolate_id) FROM $self->{'system'}->{'view'} LEFT JOIN refs on refs.isolate_id=$self->{'system'}->{'view'}.id WHERE refs.pubmed_id=?";
	my $count = $self->{'datastore'}->run_simple_query( $qry, $ref )->[0];
	$buffer .= "$count</td><td>";
	my $q = $self->{'cgi'};
	$buffer .= $q->start_form;
	$q->param( 'curate', 1 ) if $self->{'curate'};
	$q->param( 'query',
"SELECT * FROM $self->{'system'}->{'view'} LEFT JOIN refs on refs.isolate_id=$self->{'system'}->{'view'}.id WHERE refs.pubmed_id='$ref' ORDER BY $self->{'system'}->{'view'}.id;"
	);
	$q->param( 'pmid', $ref );
	$q->param( 'page', 'pubquery' );

	foreach (qw (db page query curate pmid)) {
		$buffer .= $q->hidden($_);
	}
	$buffer .= $q->submit( -value => 'Display', -class => 'submit' );
	$buffer .= $q->end_form;
	return $buffer;
}

sub _create_temp_ref_table {
	my ( $self, $list, $qry_ref ) = @_;
	my %att = (
		'dbase_name' => $self->{'config'}->{'refdb'},
		'host'       => $self->{'system'}->{'host'},
		'port'       => $self->{'system'}->{'port'},
		'user'       => $self->{'system'}->{'user'},
		'password'   => $self->{'system'}->{'pass'}
	);
	my $dbr;
	my $continue = 1;
	try {
		$dbr = $self->{'dataConnector'}->get_connection( \%att );
	  }
	  catch BIGSdb::DatabaseConnectionException with {
		$continue = 0;
		print "<div class=\"box\" id=\"statusbad\"><p>Can not connect to reference database!</p></div>\n";
		$logger->error->("Can't connect to reference database");
	  };
	return if !$continue;
	my $create =
"CREATE TEMP TABLE temp_refs (pmid int, year int, journal text, volume text, pages text, title text, abstract text, authors text, isolates int);";
	eval { $self->{'db'}->do($create); };
	if ($@) {
		$logger->error("Can't create temporary reference table. $@");
		return;
	}
	my $qry1 = "SELECT pmid,year,journal,volume,pages,title,abstract FROM refs WHERE pmid=?";
	my $sql1 = $dbr->prepare($qry1);
	my $qry2 = "SELECT author FROM refauthors WHERE pmid=? ORDER BY position";
	my $sql2 = $dbr->prepare($qry2);
	my $qry3 = "SELECT surname,initials FROM authors WHERE id=?";
	my $sql3 = $dbr->prepare($qry3);
	my ( $qry4, $isolates );

	if ($qry_ref) {
		my $isolate_qry = $$qry_ref;
		$isolate_qry =~ s/\*/id/;
		$qry4 = "SELECT COUNT(*) FROM refs WHERE isolate_id IN ($isolate_qry) AND refs.pubmed_id=?";
	} else {
		$qry4 = "SELECT COUNT(*) FROM refs WHERE refs.pubmed_id=?";
	}
	my $sql4 = $self->{'db'}->prepare($qry4);
	foreach my $pmid (@$list) {
		eval { $sql1->execute($pmid); };
		if ($@) {
			$logger->error("Can't execute $qry1, value:$pmid $@");
			return;
		}
		my @refdata = $sql1->fetchrow_array;
		eval {
			$sql2->execute($pmid);
			return;
		};
		if ($@) {
			$logger->error("Can't execute $qry2, value:$pmid $@");
			return;
		}
		my @authors;
		while ( my ($author) = $sql2->fetchrow_array ) {
			eval { $sql3->execute($author); };
			if ($@) {
				$logger->error("Can't execute $qry3, value:$author $@");
				return;
			}
			my ( $surname, $initials ) = $sql3->fetchrow_array;
			push @authors, "$surname $initials";
		}
		$" = ', ';
		my $author_string = "@authors";
		eval { $sql4->execute($pmid); };
		if ($@) {
			$logger->error("Can't execute $qry4, value:$pmid $@");
			return;
		}
		my ($isolates) = $sql4->fetchrow_array;
		$" = "','";
		eval {
			if ( $refdata[0] )
			{
				$self->{'db'}->do( "INSERT INTO temp_refs VALUES ('@refdata','$author_string',$isolates)" );
			} else {
				$self->{'db'}->do("INSERT INTO temp_refs VALUES ($pmid,null,null,null,null,null,null,null,$isolates)");
			}
		};
		if ($@) {
			$logger->error( "Can't insert into temp_refs, values:'@refdata','$author_string'  $@" );
			return;
		}
	}
	return 1;
}

sub _get_author_list {
	my ($self) = @_;
	my @authornames;
	my $qry = "SELECT authors FROM temp_refs";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute; };
	if ($@) {
		$logger->error("Can't execute query '$qry' $@");
	}
	while ( my ($authorstring) = $sql->fetchrow_array() ) {
		push @authornames, split /, /, $authorstring;
	}
	my %templist = ();
	@authornames = grep ( $templist{$_}++ == 0, @authornames );
	%templist    = ();
	@authornames = sort { lc($a) cmp lc($b) } @authornames;
	unshift @authornames, 'All authors';
	return \@authornames;
}
1;


