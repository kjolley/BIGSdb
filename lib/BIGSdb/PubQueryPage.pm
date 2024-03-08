#Written by Keith Jolley
#Copyright (c) 2010-2024, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
use parent qw(BIGSdb::IsolateQueryPage);
use Try::Tiny;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self)    = @_;
	my $system    = $self->{'system'};
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id') // 0;
	my %att       = (
		dbase_name => $self->{'config'}->{'ref_db'},
		host       => $self->{'config'}->{'dbhost'}     // $self->{'system'}->{'host'},
		port       => $self->{'config'}->{'dbport'}     // $self->{'system'}->{'port'},
		user       => $self->{'config'}->{'dbuser'}     // $self->{'system'}->{'user'},
		password   => $self->{'config'}->{'dbpassword'} // $self->{'system'}->{'password'}
	);
	say q(<h1>Publication dataset</h1>);
	my $dbr;
	my $continue = 1;
	try {
		$dbr = $self->{'dataConnector'}->get_connection( \%att );
	} catch {
		if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
			$self->print_bad_status( { message => q(No connection to reference database.), navbar => 1 } );
			$continue = 0;
		} else {
			$logger->logdie($_);
		}
	};
	return if !$continue;
	if ( $system->{'dbtype'} eq 'isolates' ) {
		my $refs_exist = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM refs)');
		if ( !$refs_exist ) {
			$self->print_bad_status( { message => q(No isolates have been linked to PubMed records.), navbar => 1 } );
			return;
		}
	} else {
		my $refs_exist =
		  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM profile_refs WHERE scheme_id=?)', $scheme_id );
		if ( !$refs_exist ) {
			$self->print_bad_status( { message => q(No profiles have been linked to PubMed records.), navbar => 1 } );
			return;
		}
	}
	my $pmid = $q->param('pmid');
	if ( !$pmid ) {
		$self->print_bad_status( { message => q(No pmid passed.), navbar => 1 } );
		return;
	}
	say qq[<h2>Citation query (PubMed id: <a href="https://pubmed.ncbi.nlm.nih.gov/$pmid" target="_blank">]
	  . qq[$pmid</a>)</h2>];
	say q(<div class="box" id="abstract">);
	$logger->error($@) if $@;
	my ( $year, $journal, $volume, $pages, $title, $abstract ) =
	  $self->{'datastore'}
	  ->run_query( 'SELECT year,journal,volume,pages,title,abstract FROM refs WHERE pmid=?', $pmid, { db => $dbr } );
	my $author_ids = $self->{'datastore'}->run_query( 'SELECT author FROM refauthors WHERE pmid=? ORDER BY position',
		$pmid, { db => $dbr, fetch => 'col_arrayref' } );
	my @author_list;
	foreach my $author_id (@$author_ids) {
		my ( $surname, $initials ) = $self->{'datastore'}->run_query( 'SELECT surname,initials FROM authors WHERE id=?',
			$author_id, { db => $dbr, cache => 'PubQueryPage::author' } );
		push @author_list, "$surname $initials";
	}
	$abstract = q(No abstract available) if !$abstract;
	say q(<p>);
	local $" = q(, );
	say qq(@author_list)                                 if @author_list;
	say qq( ($year))                                     if $year;
	say qq( <i>$journal</i> <b>$volume:</b>$pages<br />) if $journal && $volume && $pages;
	if ($title) {
		say qq(<b>$title</b><br />);
		say $abstract;
	} else {
		say q(No details available for this publication.);
	}
	say q(</p></div>);
	$q->param( curate => 1 ) if $self->{'curate'};
	my $table = $system->{'dbtype'} eq 'isolates' ? $self->{'system'}->{'view'} : 'profiles';
	my $qry;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$qry =
			"SELECT * FROM $self->{'system'}->{'view'} WHERE id IN (SELECT isolate_id FROM refs WHERE "
		  . "pubmed_id=$pmid)  AND new_version IS NULL ORDER BY $self->{'system'}->{'view'}.id;";
	} else {
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		my $primary_key = $scheme_info->{'primary_key'};
		$qry =
			"SELECT * FROM profile_refs LEFT JOIN mv_scheme_$scheme_id on "
		  . "profile_refs.profile_id=mv_scheme_${scheme_id}.$primary_key WHERE pubmed_id=$pmid "
		  . "AND profile_refs.scheme_id=$scheme_id ORDER BY $primary_key";
	}
	my $args = { table => $table, query => $qry, hidden_attributes => [qw (curate scheme_id pmid)] };
	$args->{'passed_qry_file'} = $q->param('query_file') if defined $q->param('query_file');
	if (   !defined $q->param('currentpage')
		|| ( defined $q->param('pagejump') && $q->param('pagejump') eq '1' )
		|| $q->param('First') )
	{
		$self->{'no_filters'} = 1;
		$self->print_dashboard_panel($args);
	}
	$self->paged_display($args);
	$self->print_modify_dashboard_fieldset( { no_filters => 1 } )
	  if $self->dashboard_enabled( { query_dashboard => 1 } );
	return;
}

sub get_title {
	my ($self) = @_;
	return q(Publication dataset);
}

sub print_panel_buttons {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if (   !defined $q->param('currentpage')
		|| ( defined $q->param('pagejump') && $q->param('pagejump') eq '1' )
		|| $q->param('First') )
	{
		if ( $self->dashboard_enabled( { query_dashboard => 1 } ) ) {
			say q(<span class="icon_button">)
			  . q(<a class="trigger_button" id="dashboard_panel_trigger" style="display:none">)
			  . q(<span class="fas fa-lg fa-tools"></span><span class="icon_label">Modify dashboard</span></a></span>);
		}
	}
	return;
}
1;
