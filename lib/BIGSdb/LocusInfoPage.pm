#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
use base qw(BIGSdb::Page);
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
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		print "<h1>Locus information</h1>\n";
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid locus selected.</p></div>\n";
		return;
	}
	my $locus_info    = $self->{'datastore'}->get_locus_info($locus);
	my $cleaned_locus = $self->clean_locus($locus);
	print "<h1>Locus information - $cleaned_locus</h1>\n";
	my $desc = $self->{'datastore'}->run_simple_query_hashref( "SELECT * FROM locus_descriptions WHERE locus=?", $locus );
	if ( ref $desc ne 'HASH' ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No description is available for this locus.</p></div>\n";
		return;
	}
	print "<div class=\"box\" id=\"resultstable\">\n";
	print "<h2>Description</h2>\n";
	print "<ul>\n";
	print "<li>Common name: $locus_info->{'common_name'}</li>\n" if $locus_info->{'common_name'};
	print "<li>Full name: $desc->{'full_name'}</li>\n"           if $desc->{'full_name'};
	print "<li>Product: $desc->{'product'}</li>\n"               if $desc->{'product'};
	print "<li>Data type: $locus_info->{'data_type'}</li>\n";

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
		print "</li>\n";
	} else {
		print "<li>Fixed length: $locus_info->{'length'} " . ( $locus_info->{'data_type'} eq 'DNA' ? 'bp' : 'aa' ) . "</li>\n";
	}
	if ( $locus_info->{'data_type'} eq 'DNA' ) {
		print "<li>" . ( $locus_info->{'coding_sequence'} ? 'Coding sequence' : 'Not coding sequence' );
		print "</li>\n";
	}
	print "</ul>\n";
	if ($desc->{'description'}){
		$desc->{'description'} =~ s/\n/<br \/>/g;
		print "<p>$desc->{'description'}</p>";
	}
	my $aliases = $self->{'datastore'}->run_list_query( "SELECT alias FROM locus_aliases WHERE locus=?", $locus );
	if (@$aliases) {
		print "<h2>Aliases</h2>\n";
		print "<p>This locus is also known as:</p><ul>\n";
		foreach (@$aliases) {
			print "<li>$_</li>\n";
		}
		print "</ul>\n";
	}
	my $refs = $self->{'datastore'}->run_list_query( "SELECT pubmed_id FROM locus_refs WHERE locus=?", $locus );
	if (@$refs) {
		print "<h2>References</h2>\n<ul>\n";
		my $citations = $self->{'datastore'}->get_citation_hash( $refs, { 'all_authors' => 1, 'formatted' => 1, 'link_pubmed' => 1 } );
		foreach (@$refs) {
			print "<li>$citations->{$_}</li>\n";
		}
		print "</ul>\n";
	}
	my $links =
	  $self->{'datastore'}->run_list_query_hashref( "SELECT url,description FROM locus_links WHERE locus=? ORDER BY link_order", $locus );
	if (@$links) {
		print "<h2>Links</h2>\n<ul>\n";
		foreach (@$links) {
			$_->{'url'} =~ s/\&/&amp;/g;
			my $domain;
			if ( ( lc( $_->{'url'} ) =~ /http:\/\/(.*?)\/+/ ) ) {
				$domain = $1;
			}
			print "<li><a href=\"$_->{'url'}\">$_->{'description'}</a>";
			if ( $domain && $domain ne $q->virtual_host ) {
				print " <span class=\"link\"><span style=\"font-size:1.2em\">&rarr;</span> $domain</span>";
			}
			print "</li>\n";
		}
		print "</ul>\n";
	}
	print "</div>\n";
}
1;
