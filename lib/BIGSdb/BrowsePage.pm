#Written by Keith Jolley
#(c) 2010-2013, University of Oxford
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
use 5.010;
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
	my $set_id = $self->get_set_id;
	my $desc   = $self->get_db_description;

	if ( $system->{'dbtype'} eq 'sequences' ) {
		say "<h1>Browse profiles - $desc</h1>";
		$scheme_id = $q->param('scheme_id');
		return if defined $scheme_id && $self->is_scheme_invalid( $scheme_id, { with_pk => 1 } );
		$self->print_scheme_section( { with_pk => 1 } );
		$scheme_id = $q->param('scheme_id');    #Will be set by scheme section method
		$scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	} else {
		say "<h1>Browse $desc database</h1>";
	}
	my $qry;
	if ( !defined $q->param('currentpage')
		|| $q->param('First') )
	{
		say "<div class=\"box\" id=\"queryform\">";
		say $q->startform;
		say "<div class=\"scrollable\">";
		say "<fieldset id=\"browse_fieldset\" style=\"float:left\"><legend>Browse criteria</legend>";
		say $q->hidden( 'sent', 1 );
		say $q->hidden($_) foreach qw (db page sent scheme_id);
		say "<ul>\n<li><span style=\"white-space:nowrap\">\n<label for=\"order\" class=\"display\">Order by: </label>";
		my $labels;
		my $order_by;

		if ( $system->{'dbtype'} eq 'isolates' ) {
			( $order_by, $labels ) = $self->get_field_selection_list( { isolate_fields => 1, loci => 1, scheme_fields => 1 } );
		} elsif ( $system->{'dbtype'} eq 'sequences' ) {
			my $primary_key = $scheme_info->{'primary_key'};
			if ($primary_key) {
				push @$order_by, $primary_key;
				my $cleaned = $primary_key;
				$cleaned =~ tr/_/ /;
				$labels->{$primary_key} = $cleaned;
			}
			my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
			foreach my $locus (@$loci) {
				my $locus_info = $self->{'datastore'}->get_locus_info($locus);
				push @$order_by, $locus;
				my $cleaned = $locus;
				$cleaned .= " ($locus_info->{'common_name'})" if $locus_info->{'common_name'};
				$cleaned =~ tr/_/ /;
				my $set_cleaned = $self->{'datastore'}->get_set_locus_label( $locus, $set_id );
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
		say $self->popup_menu( -name => 'order', -id => 'order', -values => $order_by, -labels => $labels );
		say "</span></li><li><span style=\"white-space:nowrap\">\n<label for=\"direction\" class=\"display\">Direction: </label>";
		say $q->popup_menu( -name => 'direction', -id => 'direction', -values => [ 'ascending', 'descending' ], -default => 'ascending' );
		say "</span></li><li>";
		say $self->get_number_records_control;
		say "</li></ul></fieldset>";
		$self->print_action_fieldset( { no_reset => 1, submit_label => 'Browse all records' } );
		say "</div>";
		say $q->endform;
		say "</div>";
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
			my $pk_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $scheme_info->{'primary_key'} );
			my $profile_id_field =
			  $pk_field_info->{'type'} eq 'integer' ? "lpad($scheme_info->{'primary_key'},20,'0')" : $scheme_info->{'primary_key'};
			$order =~ s/'/_PRIME_/g;
			if ( $self->{'datastore'}->is_locus($order) ) {
				my $locus_info = $self->{'datastore'}->get_locus_info($order);
				if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
					$order = "to_number(textcat('0', $order), text(99999999))";    #Handle arbitrary allele = 'N'
				}
			}
			my $scheme_view = $self->{'datastore'}->materialized_view_exists($scheme_id) ? "mv_scheme_$scheme_id" : "scheme_$scheme_id";
			$qry .= "SELECT * FROM $scheme_view ORDER BY "
			  . ( $order ne $scheme_info->{'primary_key'} ? "$order $dir,$profile_id_field;" : "$profile_id_field $dir;" );
			$self->paged_display( 'profiles', $qry, '', ['scheme_id'] );
		}
	}
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
