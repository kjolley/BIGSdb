#PresenceAbsence.pm - Presence/Absence export plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2012, University of Oxford
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
package BIGSdb::Plugins::PresenceAbsence;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use List::MoreUtils qw(none);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

sub get_attributes {
	my %att = (
		name        => 'Presence/Absence',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Export presence/absence status of loci for dataset generated from query results',
		category    => 'Export',
		buttontext  => 'Presence/Absence',
		menutext    => 'Presence/absence status of loci',
		module      => 'PresenceAbsence',
		version     => '1.0.0',
		dbtype      => 'isolates',
		section     => 'export,postquery',
		input       => 'query',
		requires    => 'js_tree',
		order       => 16
	);
	return \%att;
}

sub run {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $desc       = $self->get_db_description;
	say "<h1>Export presence/absence status of loci - $desc</h1>";
	my $list = $self->get_id_list( 'id', $query_file );
	if ( $q->param('submit') ) {
		my $loci_selected = $self->get_selected_loci;
		my $scheme_ids    = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
		push @$scheme_ids, 0;
		if ( !@$loci_selected && none { $q->param("s_$_") } @$scheme_ids ) {
			print "<div class=\"box\" id=\"statusbad\"><p>You must select one or more loci";
			print " or schemes" if $self->{'system'}->{'dbtype'} eq 'isolates';
			say ".</p></div>";
		} else {
			if ( !@$list ) {
				my $qry = "SELECT id FROM $self->{'system'}->{'view'} ORDER BY id";
				$list = $self->{'datastore'}->run_list_query($qry);
			}
			say "<div class=\"box\" id=\"resultstable\">";
			say "<p>Please wait for processing to finish (do not refresh page).</p>";
			print "<p>Output file being generated ...";
			my $filename    = ( BIGSdb::Utils::get_random() ) . '.txt';
			my $full_path   = "$self->{'config'}->{'tmp_dir'}/$filename";
			my $problem_ids = $self->_write_output( $list, $loci_selected, $full_path );
			say " done</p>";
			say "<p><a href=\"/tmp/$filename\">Output file</a> (right-click to save)</p>";
			say "</div>";

			if (@$problem_ids) {
				local $" = '; ';
				say "<div class=\"box\" id=\"statusbad\"><p>The following ids could not be processed "
				  . "(they do not exist): @$problem_ids.</p></div>";
			}
			return;
		}
	}
	print <<"HTML";
<div class="box" id="queryform">
<p>This script will export data showing whether a locus has had an allele designated, a sequence tagged, or both. 
Please check the loci that you would like to include.  Alternatively select one or more schemes to include all loci 
that are members of the scheme.</p>
HTML
	$self->print_sequence_export_form( 'id', $list, undef, { no_options => 1 } );
	say "</div>";
	return;
}

sub get_extra_form_elements {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say "<fieldset style=\"float:left\">\n<legend>Options</legend>";
	say "<ul><li style=\"padding-bottom:1em\">Mark present if :<br />";
	my %labels =
	  ( both => 'either designations or tags set', designations => 'allele designations defined', tags => 'sequence tags defined' );
	say $q->radio_group( -name => 'presence', -value => [qw(both designations tags)], -labels => \%labels, -linebreak => 'true' );
	say "</li><li><label for=\"present\" class=\"parameter\">Symbol for present: </label>";
	say $q->popup_menu( -name => 'present', -id => 'present', -value => [qw (O Y *)] );
	say "</li><li><label for=\"absent\" class=\"parameter\">Symbol for absent: </label>";
	say $q->popup_menu( -name => 'absent', -id => 'absent', -value => [ qw (X N -), ' ' ], );
	say "</li></ul></fieldset>";
	return;
}

sub _write_output {
	my ( $self, $list, $loci, $filename, ) = @_;
	my $q = $self->{'cgi'};
	my @problem_ids;
	my $isolate_sql;
	my @includes = $q->param('includes');
	if (@includes) {
		local $" = ',';
		$isolate_sql = $self->{'db'}->prepare("SELECT @includes FROM $self->{'system'}->{'view'} WHERE id=?");
	}
	local $| = 1;
	my $i = 0;
	my $j = 0;
	open( my $fh, '>', $filename )
	  or $logger->error("Can't open temp file $filename for writing");
	my $selected_loci = $self->order_selected_loci;
	print $fh 'id';
	print $fh "\t$_" foreach (@includes);

	foreach my $locus (@$selected_loci) {
		my $locus_name = $self->clean_locus( $locus, { text_output => 1 } );
		print $fh "\t$locus_name";
	}
	print $fh "\n";
	foreach my $id (@$list) {
		print "." if !$i;
		print " " if !$j;
		if ( !$i && $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
		$id =~ s/[\r\n]//g;
		my $allele_ids = $self->{'datastore'}->get_all_allele_ids($id);
		my $tags       = $self->{'datastore'}->get_all_allele_sequences($id);
		print $fh $id;
		if (@includes) {
			eval { $isolate_sql->execute($id) };
			$logger->error($@) if $@;
			my @include_values = $isolate_sql->fetchrow_array;
			local $" = "\t";
			no warnings 'uninitialized';
			print $fh "\t@include_values";
		}
		my $present = $q->param('present') || 'O';
		my $absent  = $q->param('absent')  || 'X';
		foreach my $locus (@$selected_loci) {
			my $value = '';
			given ( $q->param('presence') ) {
				when ('designations') { $value = $allele_ids->{$locus} ? $present : $absent }
				when ('tags')         { $value = $tags->{$locus}       ? $present : $absent }
				default { $value = ( $allele_ids->{$locus} || $tags->{$locus} ) ? $present : $absent }
			}
			print $fh "\t$value";
		}
		print $fh "\n";
		$i++;
		if ( $i == 50 ) {
			$i = 0;
			$j++;
		}
		$j = 0 if $j == 10;
	}
	close $fh;
	return \@problem_ids;
}
1;
