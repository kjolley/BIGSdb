#PublicationBreakdown.pm - PublicationBreakdown plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2018, University of Oxford
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
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin BIGSdb::ResultsTablePage);
use List::MoreUtils qw(any uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);

sub get_attributes {
	my ($self) = @_;
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
		version     => '1.1.6',
		dbtype      => 'isolates',
		section     => 'breakdown,postquery',
		url         => "$self->{'config'}->{'doclink'}/data_query.html#retrieving-isolates-by-linked-publication",
		input       => 'query',
		requires    => 'ref_db',
		order       => 30,
	);
	return \%att;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Publication breakdown of dataset</h1>);
	return if $self->has_set_changed;
	if ( !$self->{'config'}->{'ref_db'} ) {
		say q(<div class="box" id="statusbad">No reference database has been defined.</p></div>);
		return;
	}
	my $query_file = $q->param('query_file');
	if ( !$query_file ) {
		$query_file = $self->make_temp_file("SELECT * FROM $self->{'system'}->{'view'}");
		$q->param( query_file => $query_file );
	}
	my $qry_ref = $self->get_query($query_file);
	return if ref $qry_ref ne 'SCALAR';
	my $qry = $$qry_ref;
	$qry =~ s/ORDER\ BY.*$//gx;
	my $isolate_qry = $qry;
	return if !$self->create_temp_tables( \$qry );
	$qry =~ s/SELECT\ \*\ FROM\ $self->{'system'}->{'view'}/
	SELECT id FROM $self->{'system'}->{'view'}/x;
	my $new_qry = "SELECT DISTINCT(refs.pubmed_id) FROM refs WHERE refs.isolate_id IN ($qry)";
	my $list    = $self->{'datastore'}->run_query( $new_qry, undef, { fetch => 'col_arrayref' } );
	my $guid    = $self->get_guid;

	if ( $self->{'datastore'}->create_temp_ref_table( $list, \$isolate_qry ) ) {
		say q(<div class="box" id="queryform">);
		say $q->start_form;
		$q->param( all_records => 1 ) if !$query_file;
		say $q->hidden($_) foreach qw (db name page all_records query_file list_file datatype);
		say q(<fieldset style="float:left"><legend>Filter query by</legend>);
		my $author_list = $self->_get_author_list;
		say q(<ul><li><label for="author_list" class="display">Author:</label>);
		say $q->popup_menu( -name => 'author_list', -id => 'author_list', -values => $author_list );
		say q(</li><li><label for="year_list" class="display">Year:</label>);
		my $year_list =
		  $self->{'datastore'}
		  ->run_query( 'SELECT DISTINCT year FROM temp_refs ORDER BY year', undef, { fetch => 'col_arrayref' } );
		unshift @$year_list, 'All years';
		say $q->popup_menu( -name => 'year_list', -id => 'year_list', -values => $year_list );
		say q(</li></ul></fieldset>);
		say q(<fieldset style="float:left"><legend>Display</legend>);
		say q(<ul><li><label for="order" class="display">Order by: </label>);
		my %labels = ( pmid => 'Pubmed id', first_author => 'first author', isolates => 'number of isolates' );
		my @order_list = qw(pmid authors year title isolates);
		say $q->popup_menu(
			-name    => 'order',
			-id      => 'order',
			-values  => \@order_list,
			-labels  => \%labels,
			-default => 'isolates'
		);
		say $q->popup_menu(
			-name    => 'direction',
			-values  => [qw (asc desc)],
			-labels  => { asc => 'ascending', desc => 'descending' },
			-default => 'desc'
		);
		say q(</li><li><label for="displayrecs" class="display">Display: </label>);
		$self->{'prefs'}->{'displayrecs'} = $q->param('displayrecs') if $q->param('displayrecs');
		say $q->popup_menu(
			-name    => 'displayrecs',
			-id      => 'displayrecs',
			-values  => [qw (10 25 50 100 200 500 all)],
			-default => $self->{'prefs'}->{'displayrecs'}
		);
		say q( records per page</li></ul></fieldset>);
		$self->print_action_fieldset( { no_reset => 1 } );
		say $q->end_form;
		say q(</div>);
		my @filters;
		my $author =
		  ( any { defined $q->param('author_list') && $q->param('author_list') eq $_ } @$author_list )
		  ? $q->param('author_list')
		  : 'All authors';
		$author =~ s/'/\\'/gx;
		push @filters, "authors LIKE E'%$author%'" if $author ne 'All authors';
		my $year = BIGSdb::Utils::is_int( $q->param('year_list') ) ? $q->param('year_list') : q();
		push @filters, qq(year=$year) if $year;
		local $" = q( AND );
		my $filter_string = @filters ? qq( WHERE @filters) : q();
		my $order =
		  ( any { defined $q->param('order') && $q->param('order') eq $_ } @order_list )
		  ? $q->param('order')
		  : 'isolates';
		my $dir =
		  ( any { defined $q->param('direction') && $q->param('direction') eq $_ } qw(desc asc) )
		  ? $q->param('direction')
		  : 'desc';

		#Make sure the following SQL ends with a ;
		#Paging will break otherwise!
		my $refquery          = "SELECT * FROM temp_refs$filter_string ORDER BY $order $dir;";
		my @hidden_attributes = qw (name all_records author_list year_list list_file temp_table_file datatype);
		$self->paged_display(
			{
				table             => 'refs',
				query             => $refquery,
				hidden_attributes => \@hidden_attributes,
				passed_qry_file   => $query_file
			}
		);
		return;
	}
}

sub _get_author_list {
	my ($self) = @_;
	my @author_names;
	my $author_lists =
	  $self->{'datastore'}->run_query( 'SELECT authors FROM temp_refs', undef, { fetch => 'col_arrayref' } );
	foreach my $author_string (@$author_lists) {
		next if !defined $author_string;
		my @temp_list = split /, /x, $author_string;
		foreach my $name (@temp_list) {
			$name =~ s/^\s*//x;
			push @author_names, $name if $name !~ /^\s*$/x;
		}
	}
	@author_names = sort { lc($a) cmp lc($b) } uniq @author_names;
	unshift @author_names, 'All authors';
	return \@author_names;
}
1;
