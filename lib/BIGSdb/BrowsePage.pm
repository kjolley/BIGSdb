#Written by Keith Jolley
#(c) 2010-2012, University of Oxford
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
use parent qw(BIGSdb::ResultsTablePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (field_help tooltips jQuery);
	return;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { general => 1, main_display => 1, isolate_display => 0, analysis => 0, query_field => 1 };
	return;
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
	my $set_id = $self->get_set_id;

	if ( $system->{'dbtype'} eq 'sequences' ) {
		$scheme_id = $q->param('scheme_id');
		if ( !$scheme_id ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No scheme id passed.</p></div>\n";
			return;
		} elsif ( !BIGSdb::Utils::is_int($scheme_id) ) {
			print "<div class=\"box\" id=\"statusbad\"><p>Scheme id must be an integer.</p></div>\n";
			return;
		} elsif ($set_id) {
			if ( !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id ) ) {
				print "<div class=\"box\" id=\"statusbad\"><p>The selected scheme is unavailable.</p></div>\n";
				return;
			}
		}
		$scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
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
	} else {
		my $desc = $self->get_db_description;
		print "<h1>Browse $desc database</h1>\n";
	}
	my $qry;
	if ( !defined $q->param('currentpage')
		|| $q->param('First') )
	{
		print "<div class=\"box\" id=\"queryform\">\n";
		print $q->startform;
		print "<div class=\"scrollable\">\n";
		print "<fieldset id=\"browse_fieldset\" style=\"float:left\"><legend>Please enter your browse criteria below.</legend>\n";
		print $q->hidden( 'sent', 1 );
		print $q->hidden($_) foreach qw (db page sent scheme_id);
		print "<ul>\n<li><span style=\"white-space:nowrap\">\n<label for=\"order\" class=\"display\">Order by: </label>\n";
		my $labels;
		my $order_by;

		if ( $system->{'dbtype'} eq 'isolates' ) {
			( $order_by, $labels ) = $self->get_field_selection_list( { 'isolate_fields' => 1, 'loci' => 1, 'scheme_fields' => 1 } );
		} elsif ( $system->{'dbtype'} eq 'sequences' ) {
			if ($primary_key) {
				push @$order_by, $primary_key;
				my $cleaned = $primary_key;
				$cleaned =~ tr/_/ /;
				$labels->{$primary_key} = $cleaned;
			}
			my $loci         = $self->{'datastore'}->get_scheme_loci($scheme_id);
			foreach my $locus (@$loci) {
				my $locus_info = $self->{'datastore'}->get_locus_info($locus);
				push @$order_by, $locus;
				my $cleaned = $locus;
				$cleaned .= " ($locus_info->{'common_name'})" if $locus_info->{'common_name'};
				$cleaned =~ tr/_/ /;
				my $set_cleaned = $self->{'datastore'}->get_set_locus_label($locus, $set_id);
				$cleaned = $set_cleaned if $set_cleaned;
				$labels->{$locus} = $cleaned;
			}
			my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
			foreach my $field (@$scheme_fields) {
				next if $field eq $primary_key;
				push @$order_by, $field;
				my $cleaned = $field;
				$cleaned =~ tr/_/ /;
				$labels->{$field} = $cleaned;
			}
			push @$order_by, qw (sender curator date_entered datestamp);
			$labels->{'date_entered'} = 'date entered';
			$labels->{'profile_id'}   = $primary_key;
		}
		print $q->popup_menu( -name => 'order', -id => 'order', -values => $order_by, -labels => $labels );
		print "</span></li><li><span style=\"white-space:nowrap\">\n<label for=\"direction\" class=\"display\">Direction: </label>\n";
		print $q->popup_menu( -name => 'direction', -id => 'direction', -values => [ 'ascending', 'descending' ], -default => 'ascending' );
		print "</span></li><li>";
		print $self->get_number_records_control;
		print "</li><li><span style=\"float:right\">";
		print $q->submit( -name => 'Browse all records', -class => 'submit' );
		print "</span></li></ul></fieldset></div>\n";
		print $q->endform;
		print "</div>\n";
	}
	if ( defined $q->param('sent') || defined $q->param('currentpage') ) {
		my $order;
		if ( $q->param('order') =~ /^la_(.+)\|\|/ || $q->param('order') =~ /^cn_(.+)/ ) {
			$order = "l_$1";
		} else {
			$order .= $q->param('order');
		}
		my $dir = $q->param('direction') && $q->param('direction') eq 'descending' ? 'desc' : 'asc';
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
	return;
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
