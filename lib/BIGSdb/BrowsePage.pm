#Written by Keith Jolley
#(c) 2010-2011, University of Oxford
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
package BIGSdb::BrowsePage;
use strict;
use warnings;
use base qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (field_help tooltips jQuery);
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { 'general' => 1, 'main_display' => 1, 'isolate_display' => 0, 'analysis' => 0, 'query_field' => 1 };
}

sub print_content {
	my ($self)   = @_;
	my $system   = $self->{'system'};
	my $prefs    = $self->{'prefs'};
	my $instance = $self->{'instance'};
	my $q        = $self->{'cgi'};
	my $scheme_id;
	my $scheme_info;
	my $primary_key;

	if ( $system->{'dbtype'} eq 'sequences' ) {
		
		$scheme_id = $q->param('scheme_id');
		if ( !$scheme_id ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No scheme id passed.</p></div>\n";
			return;
		} elsif ( !BIGSdb::Utils::is_int($scheme_id) ) {
			print "<div class=\"box\" id=\"statusbad\"><p>Scheme id must be an integer.</p></div>\n";
			return;
		} else {
			$scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
			if ( !$scheme_info ) {
				print "<div class=\"box\" id=\"statusbad\">Scheme does not exist.</p></div>\n";
				return;
			}
			print "<h1>Browse $scheme_info->{'description'} profiles</h1>\n";
			eval {
				$primary_key =
				  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )
				  ->[0];
			};
			if ( !$primary_key ) {
				print
"<div class=\"box\" id=\"statusbad\"><p>No primary key field has been set for this scheme.  Profile browsing can not be done until this has been set.</p></div>\n";
				return;
			}
		}
	} else {
		print "<h1>Browse $system->{'description'} database</h1>\n";
	}
	my $qry;
	if ( !defined $q->param('currentpage')
		|| $q->param('First') )
	{
		print "<div class=\"box\" id=\"queryform\">\n";
		print "<p>Please enter your browse criteria below:</p>\n";
		print "<table><tr><td>\n";
		print $q->startform;
		print $q->hidden( 'sent', 1 );
		print $q->hidden($_) foreach qw (db page sent scheme_id);
		print "<table style=\"border-spacing:0\">\n";
		print "<tr><td style=\"text-align:right\">Order by: </td><td>\n";
		my $labels;
		my $order_by;
		if ( $system->{'dbtype'} eq 'isolates' ) {
			( $order_by, $labels ) = $self->get_field_selection_list( {
			'isolate_fields' => 1,
			'loci' => 1,
			'scheme_fields' => 1 
			});
		} elsif ( $system->{'dbtype'} eq 'sequences' ) {
			if ($primary_key) {
				push @$order_by, $primary_key;
				my $cleaned = $primary_key;
				$cleaned =~ tr/_/ /;
				$labels->{$primary_key} = $cleaned;
			}
			my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
			foreach (@$loci) {
				my $locus_info = $self->{'datastore'}->get_locus_info($_);
				push @$order_by, $_;
				my $cleaned = $_;
				$cleaned .= " ($locus_info->{'common_name'})" if $locus_info->{'common_name'};
				$cleaned =~ tr/_/ /;
				$labels->{$_} = $cleaned;
			}
			my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
			foreach (@$scheme_fields) {
				next if $_ eq $primary_key;
				push @$order_by, $_;
				my $cleaned = $_;
				$cleaned =~ tr/_/ /;
				$labels->{$_} = $cleaned;
			}
			push @$order_by, qw (sender curator date_entered datestamp);
			$labels->{'date_entered'} = 'date entered';
			$labels->{'profile_id'}   = $primary_key;
		}
		print $q->popup_menu( -name => 'order', -values => $order_by, -labels => $labels );
		print "</td></tr>";
		print "<tr><td style=\"text-align:right\">Direction </td><td>\n";
		print $q->popup_menu( -name => 'direction', -values => [ 'ascending', 'descending' ], -default => 'ascending' );
		print "</td></tr>\n";
		print "<tr><td style=\"text-align:right\">Display </td><td>\n";
		$prefs->{'displayrecs'} = $q->param('displayrecs') if $q->param('displayrecs');
		print $q->popup_menu(
			-name    => 'displayrecs',
			-values  => [ '10', '25', '50', '100', '200', '500', 'all' ],
			-default => $prefs->{'displayrecs'}
		);
		print " records per page&nbsp;";
		print
" <a class=\"tooltip\" title=\"Records per page - Analyses use the full query dataset, rather than just the page shown.\">&nbsp;<i>i</i>&nbsp;</a>";
		print "&nbsp;";
		print "</td></tr>\n";
		print "<tr><td style=\"text-align:right\" colspan=\"2\">\n";
		print $q->submit( -name => 'Browse all records', -class => 'submit' );
		print "</td></tr></table>\n";
		print $q->endform;
		print "</td></tr></table></div>\n";
	}
	if ( defined $q->param('sent') || defined $q->param('currentpage') ) {
		my $order;
		if ( $q->param('order') =~ /^la_(.+)\|\|/ || $q->param('order') =~ /^cn_(.+)/ ) {
			$order = "l_$1";
		} else {
			$order .= $q->param('order');
		}
		my $dir = $q->param('direction') eq 'descending' ? 'desc' : 'asc';
		if ( $system->{'dbtype'} eq 'isolates' ) {
			my $qry = "SELECT * FROM $system->{'view'} ORDER BY $order $dir,$self->{'system'}->{'view'}.id;";
			$self->paged_display( $self->{'system'}->{'view'}, $qry );
		} elsif ( $system->{'dbtype'} eq 'sequences' ) {
			my $pk_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
			my $profile_id_field = $pk_field_info->{'type'} eq 'integer' ? "lpad($primary_key,20,'0')" : $primary_key;
			if ( $self->{'datastore'}->is_locus($order) ) {
				my $locus_info = $self->{'datastore'}->get_locus_info($order);
				if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
					$order = "CAST($order AS int)";
				}
			}
			$order =~ s/'/_PRIME_/g;
			$qry .= "SELECT * FROM scheme_$scheme_id ORDER BY "
			  . ( $order ne $primary_key ? "$order $dir,$profile_id_field;" : "$profile_id_field $dir;" );
			$self->paged_display( 'profiles', $qry, '', ['scheme_id'] );
		}
	}
	print "<p />\n";
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		return "Browse whole database - $desc";
	} else {
		return "Browse profiles - $desc";
	}
}
1;
