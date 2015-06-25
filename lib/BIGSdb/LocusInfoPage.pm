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
	return "Invalid locus" if !$self->{'datastore'}->is_locus($locus);
	$locus =~ tr/_/ /;
	return "Locus information - $locus";
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $locus  = $q->param('locus');
	$locus =~ s/%27/'/g;    #Web-escaped locus
	my $set_id = $self->get_set_id;
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		say "<h1>Locus information</h1>";
		say qq(<div class="box" id="statusbad"><p>Invalid locus selected.</p></div>);
		return;
	} elsif ( $set_id && !$self->{'datastore'}->is_locus_in_set( $locus, $set_id ) ) {
		say "<h1>Locus information</h1>";
		say qq(<div class="box" id="statusbad"><p>The selected locus is unavailable.</p></div>);
		return;
	}
	my $locus_info    = $self->{'datastore'}->get_locus_info($locus);
	my $cleaned_locus = $self->clean_locus($locus);
	say "<h1>Locus information - $cleaned_locus</h1>";
	my $desc = $self->{'datastore'}->run_query( "SELECT * FROM locus_descriptions WHERE locus=?", $locus, { fetch => 'row_hashref' } );
	say qq(<div class="box" id="resultstable">);
	say "<h2>Description</h2>";
	say "<ul>";

	if ( $locus_info->{'formatted_common_name'} ) {
		say "<li>Common name: $locus_info->{'formatted_common_name'}</li>";
	} elsif ( $locus_info->{'common_name'} ) {
		say "<li>Common name: $locus_info->{'common_name'}</li>";
	}
	say "<li>Full name: $desc->{'full_name'}</li>" if $desc->{'full_name'};
	say "<li>Product: $desc->{'product'}</li>"     if $desc->{'product'};
	say "<li>Data type: $locus_info->{'data_type'}</li>";
	if ( $locus_info->{'length_varies'} ) {
		print "<li>Variable length: ";
		if ( $locus_info->{'min_length'} || $locus_info->{'max_length'} ) {
			print "(";
			print "$locus_info->{'min_length'} min" if $locus_info->{'min_length'};
			print "; "                              if $locus_info->{'min_length'} && $locus_info->{'max_length'};
			print "$locus_info->{'max_length'} max" if $locus_info->{'max_length'};
			print ")";
		} else {
			print "No limits set";
		}
		say "</li>";
	} else {
		say "<li>Fixed length: $locus_info->{'length'} " . ( $locus_info->{'data_type'} eq 'DNA' ? 'bp' : 'aa' ) . "</li>";
	}
	if ( $locus_info->{'data_type'} eq 'DNA' ) {
		print "<li>" . ( $locus_info->{'coding_sequence'} ? 'Coding sequence' : 'Not coding sequence' );
		say "</li>";
	}
	my $allele_count = $self->{'datastore'}->run_query( "SELECT COUNT(*) FROM sequences WHERE locus=?", $locus );
	if ($allele_count) {
		my $seq_type = $locus_info->{'data_type'} eq 'DNA' ? 'allele' : 'variant';
		my $plural = $allele_count > 1 ? 's' : '';
		say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleQuery&amp;)
		  . qq(locus=$locus&amp;submit=1">$allele_count $seq_type$plural</a></li>);
	}
	say "</ul>";
	if ( $desc->{'description'} ) {
		$desc->{'description'} =~ s/\n/<br \/>/g;
		say "<p>$desc->{'description'}</p>";
	}
	my $aliases = $self->{'datastore'}->run_query( "SELECT alias FROM locus_aliases WHERE locus=?", $locus, { fetch => 'col_arrayref' } );
	if (@$aliases) {
		say "<h2>Aliases</h2>";
		say "<p>This locus is also known as:</p><ul>";
		foreach (@$aliases) {
			say "<li>$_</li>";
		}
		say "</ul>";
	}
	my $refs = $self->{'datastore'}->run_query( "SELECT pubmed_id FROM locus_refs WHERE locus=?", $locus, { fetch => 'col_arrayref' } );
	if (@$refs) {
		say "<h2>References</h2>\n<ul>";
		my $citations = $self->{'datastore'}->get_citation_hash( $refs, { all_authors => 1, formatted => 1, link_pubmed => 1 } );
		foreach (@$refs) {
			say "<li>$citations->{$_}</li>";
		}
		say "</ul>";
	}
	my $links = $self->{'datastore'}->run_query( "SELECT url,description FROM locus_links WHERE locus=? ORDER BY link_order",
		$locus, { fetch => 'all_arrayref', slice => {} } );
	if (@$links) {
		say "<h2>Links</h2>\n<ul>";
		foreach (@$links) {
			$_->{'url'} =~ s/\&/&amp;/g;
			my $domain;
			if ( ( lc( $_->{'url'} ) =~ /http:\/\/(.*?)\/+/ ) ) {
				$domain = $1;
			}
			print "<li><a href=\"$_->{'url'}\">$_->{'description'}</a>";
			if ( $domain && $domain ne $q->virtual_host ) {
				say " <span class=\"link\"><span style=\"font-size:1.2em\">&rarr;</span> $domain</span>";
			}
			say "</li>";
		}
		say "</ul>";
	}
	my $curators =
	  $self->{'datastore'}
	  ->run_query( "SELECT curator_id FROM locus_curators WHERE locus=? AND (NOT hide_public OR hide_public IS NULL) ORDER BY curator_id",
		$locus, { fetch => 'col_arrayref' } );
	if (@$curators) {
		my $plural = @$curators > 1 ? 's' : '';
		say "<h2>Curator$plural</h2>";
		say "<p>This locus is curated by:</p>";
		say '<ul>';
		foreach my $user_id (@$curators) {
			my $curator_info = $self->{'datastore'}->get_user_string( $user_id, { affiliation => 1, email => 1 } );
			say "<li>$curator_info</li>";
		}
		say '</ul>';
	}
	my $schemes =
	  $self->{'datastore'}
	  ->run_query( "SELECT scheme_id FROM scheme_members WHERE locus=? ORDER BY scheme_id", $locus, { fetch => 'col_arrayref' } );
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
		say "<h2>Scheme$plural</h2>";
		say "<p>This locus is a member of the following scheme$plural:</p>";
		$self->_print_schemes( \@valid_schemes );
	}
	say "</div>";
	return;
}

sub _print_schemes {    #TODO Display scheme list in hierarchical tree.
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
