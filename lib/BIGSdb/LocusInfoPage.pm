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
package BIGSdb::LocusInfoPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $locus = $self->{'cgi'}->param('locus');
	return q(Invalid locus) if !$self->{'datastore'}->is_locus($locus);
	$locus =~ tr/_/ /;
	return qq(Locus information - $locus);
}

sub print_content {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $locus      = $q->param('locus');
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	$locus =~ s/%27/'/gx;    #Web-escaped locus
	my $set_id = $self->get_set_id;
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		say q(<h1>Locus information</h1>);
		say q(<div class="box" id="statusbad"><p>Invalid locus selected.</p></div>);
		return;
	} elsif ( $set_id && !$self->{'datastore'}->is_locus_in_set( $locus, $set_id ) ) {
		say q(<h1>Locus information</h1>);
		say q(<div class="box" id="statusbad"><p>The selected locus is unavailable.</p></div>);
		return;
	}
	my $cleaned_locus = $self->clean_locus($locus);
	say qq(<h1>Locus information - $cleaned_locus</h1>);
	say q(<div class="box" id="resultstable">);
	$self->_print_description($locus_info);
	$self->_print_aliases($locus_info);
	$self->_print_refs($locus_info);
	$self->_print_links($locus_info);
	$self->_print_curators($locus_info);
	$self->_print_schemes($locus_info);
	say q(</div>);
	return;
}

sub _print_description {
	my ( $self, $locus_info ) = @_;
	my $desc =
	  $self->{'datastore'}
	  ->run_query( 'SELECT * FROM locus_descriptions WHERE locus=?', $locus_info->{'id'}, { fetch => 'row_hashref' } );
	say q(<h2>Description</h2>);
	say q(<dl class="data">);
	if ( $locus_info->{'formatted_common_name'} ) {
		say qq(<dt>Common name</dt><dd>$locus_info->{'formatted_common_name'}</dd>);
	} elsif ( $locus_info->{'common_name'} ) {
		say qq(<dt>Common name</dt><dd>$locus_info->{'common_name'}</dd>);
	}
	say qq(<dt>Full name</dt><dd>$desc->{'full_name'}</dd>) if $desc->{'full_name'};
	say qq(<dt>Product</dt><dd>$desc->{'product'}</dd>)     if $desc->{'product'};
	say qq(<dt>Data type</dt><dd>$locus_info->{'data_type'}</dd>);
	if ( $locus_info->{'length_varies'} ) {
		print q(<dt>Variable length</dt><dd>);
		if ( $locus_info->{'min_length'} || $locus_info->{'max_length'} ) {
			print qq($locus_info->{'min_length'} min) if $locus_info->{'min_length'};
			print q(; )                               if $locus_info->{'min_length'} && $locus_info->{'max_length'};
			print qq($locus_info->{'max_length'} max) if $locus_info->{'max_length'};
		} else {
			print q(No limits set);
		}
		say q(</dd>);
	} else {
		say qq(<dt>Fixed length</dt><dd>$locus_info->{'length'} )
		  . ( $locus_info->{'data_type'} eq 'DNA' ? q(bp) : q(aa) )
		  . q(</dd>);
	}
	if ( $locus_info->{'data_type'} eq 'DNA' ) {
		my $cds = $locus_info->{'coding_sequence'} ? 'yes' : 'no';
		say qq(<dt>Coding sequence</dt><dd>$cds</dd>);
	}
	my $allele_count =
	  $self->{'datastore'}->run_query( q(SELECT COUNT(*) FROM sequences WHERE locus=? AND allele_id NOT IN ('N','0')),
		$locus_info->{'id'} );
	if ($allele_count) {
		my $seq_type = $locus_info->{'data_type'} eq 'DNA' ? 'Alleles' : 'Variants';
		say qq(<dt>$seq_type</dt><dd><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=alleleQuery&amp;locus=$locus_info->{'id'}&amp;submit=1">$allele_count</a></dd>);
	}
	say q(</dl>);
	if ( $desc->{'description'} ) {
		$desc->{'description'} =~ s/\n/<br \/>/gx;
		say qq(<p>$desc->{'description'}</p>);
	}
	return;
}

sub _print_aliases {
	my ( $self, $locus_info ) = @_;
	my $aliases =
	  $self->{'datastore'}
	  ->run_query( 'SELECT alias FROM locus_aliases WHERE locus=?', $locus_info->{'id'}, { fetch => 'col_arrayref' } );
	if (@$aliases) {
		say q(<h2>Aliases</h2>);
		say q(<p>This locus is also known as:</p><ul>);
		say qq(<li>$_</li>) foreach @$aliases;
		say q(</ul>);
	}
	return;
}

sub _print_refs {
	my ( $self, $locus_info ) = @_;
	my $refs =
	  $self->{'datastore'}
	  ->run_query( 'SELECT pubmed_id FROM locus_refs WHERE locus=?', $locus_info->{'id'}, { fetch => 'col_arrayref' } );
	if (@$refs) {
		say q(<h2>References</h2><ul>);
		my $citations =
		  $self->{'datastore'}->get_citation_hash( $refs, { all_authors => 1, formatted => 1, link_pubmed => 1 } );
		say qq(<li>$citations->{$_}</li>) foreach @$refs;
		say q(</ul>);
	}
	return;
}

sub _print_links {
	my ( $self, $locus_info ) = @_;
	my $q = $self->{'cgi'};
	my $links =
	  $self->{'datastore'}->run_query( 'SELECT url,description FROM locus_links WHERE locus=? ORDER BY link_order',
		$locus_info->{'id'}, { fetch => 'all_arrayref', slice => {} } );
	if (@$links) {
		say qq(<h2>Links</h2>\n<ul>);
		foreach my $link (@$links) {
			$link->{'url'} =~ s/\&/&amp;/gx;
			my $domain;
			if ( ( lc( $link->{'url'} ) =~ /http:\/\/(.*?)\/+/x ) ) {
				$domain = $1;
			}
			print qq(<li><a href="$link->{'url'}">$link->{'description'}</a>);
			if ( $domain && $domain ne $q->virtual_host ) {
				say qq( <span class="link"><span style="font-size:1.2em">&rarr;</span> $domain</span>);
			}
			say q(</li>);
		}
		say q(</ul>);
	}
	return;
}

sub _print_curators {
	my ( $self, $locus_info ) = @_;
	my $curators = $self->{'datastore'}->run_query(
		'SELECT curator_id FROM locus_curators WHERE locus=? AND '
		  . '(NOT hide_public OR hide_public IS NULL) ORDER BY curator_id',
		$locus_info->{'id'},
		{ fetch => 'col_arrayref' }
	);
	if (@$curators) {
		my $plural = @$curators > 1 ? q(s) : q();
		say qq(<h2>Curator$plural</h2>);
		say q(<p>This locus is curated by:</p>);
		say q(<ul>);
		foreach my $user_id (@$curators) {
			my $curator_info = $self->{'datastore'}->get_user_string( $user_id, { affiliation => 1, email => 1 } );
			say qq(<li>$curator_info</li>);
		}
		say q(</ul>);
	}
	return;
}

sub _print_schemes {
	my ( $self, $locus_info ) = @_;
	my $set_id  = $self->get_set_id;
	my $schemes = $self->{'datastore'}->run_query(
		'SELECT scheme_id FROM scheme_members WHERE locus=? ORDER BY scheme_id',
		$locus_info->{'id'}, { fetch => 'col_arrayref' }
	);
	my @valid_schemes;
	if ($set_id) {
		foreach my $scheme_id (@$schemes) {
			push @valid_schemes, $scheme_id if $self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id );
		}
	} else {
		@valid_schemes = @$schemes;
	}
	if (@valid_schemes) {
		my $plural = @valid_schemes > 1 ? 's' : '';
		say qq(<h2>Scheme$plural</h2>);
		say qq(<p>This locus is a member of the following scheme$plural:</p>);
		$self->_print_scheme_list( \@valid_schemes );
	}
	return;
}

sub _print_scheme_list {    #TODO Display scheme list in hierarchical tree.
	my ( $self, $scheme_list ) = @_;
	my $set_id = $self->get_set_id;
	say '<ul>';
	foreach my $scheme_id (@$scheme_list) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
		say "<li>$scheme_info->{'description'}</li>";
	}
	say '</ul>';
	return;
}
1;
