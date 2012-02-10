#TagStatus.pm - Tag status plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2011-2012, University of Oxford
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
package BIGSdb::Plugins::TagStatus;
use strict;
use warnings;
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use Apache2::Connection ();
use constant COLOURS     => qw(eee c22 22c c4c);    #none; designations only; tags only; both
use constant IMAGE_WIDTH => 1200;

sub get_attributes {
	my %att = (
		name        => 'Tag Status',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Breakdown status of sequence tagging and designation by locus',
		category    => 'Breakdown',
		buttontext  => 'Tag status',
		menutext    => 'Tag status',
		module      => 'TagStatus',
		version     => '1.0.1',
		dbtype      => 'isolates',
		section     => 'breakdown,postquery',
		requires    => 'mogrify',
		system_flag => 'TagStatus',
		input       => 'query',
		order       => 95,
		max         => 1000
	);
	return \%att;
}

sub run {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $qry_ref    = $self->get_query($query_file);
	my $ids        = $self->get_ids_from_query($qry_ref);
	if ( ref $ids ne 'ARRAY' || !@$ids ) {
		print "<div class=\"box statusbad\"><p>No isolates to analyse.</p></div>\n";
		return;
	}
	if ( $q->param('isolate_id') && BIGSdb::Utils::is_int( $q->param('isolate_id') ) ) {
		$self->_breakdown_isolate( $q->param('isolate_id') );
	} else {
		print "<h1>Tag status</h1>\n";
		$self->_print_schematic($ids);
	}
	return;
}

sub _breakdown_isolate {
	my ( $self, $id ) = @_;
	my $isolate = $self->{'datastore'}->run_simple_query_hashref( "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?", $id );
	if ( !defined $isolate ) {
		print "<h1>Tag status</h1>\n";
		print "<div class=\"box statusbad\"><p>Invalid isolate passed.</p></div>\n";
		return;
	}
	print "<h1>Tag status: Isolate id#$id ($isolate->{$self->{'system'}->{'labelfield'}})</h1>\n";
	print "<div class=\"box\" id=\"resultstable\">\n";
	my $allele_ids = $self->{'datastore'}->get_all_allele_ids($id);
	my $tags       = $self->{'datastore'}->get_all_allele_sequences($id);
	my $schemes    = $self->{'datastore'}->run_list_query_hashref("SELECT id,description FROM schemes ORDER BY description");
	print "<table class=\"resultstable\">\n<tr><th>Scheme</th><th>Locus</th><th>Allele designation</th><th>Sequence tag</th></tr>\n";
	my $td       = 1;
	my $tagged   = "background:#aaf; color:white";
	my $untagged = "background:red";

	foreach my $scheme (@$schemes) {
		my $first = 1;
		my $scheme_loci = $self->{'datastore'}->get_scheme_loci( $scheme->{'id'}, { 'profile_name' => 0, 'analysis_pref' => 1 } );
		( my $desc = $scheme->{'description'} ) =~ s/&/&amp;/g;
		print "<tr class=\"td$td\"><th rowspan=\"" . @$scheme_loci . "\">$desc</th>";
		foreach my $locus (@$scheme_loci) {
			print "<tr class=\"td$td\">" if !$first;
			my $cleaned = $self->clean_locus($locus);
			print "<td>$cleaned</td>";
			print defined $allele_ids->{$locus} ? "<td style=\"$tagged\">$allele_ids->{$locus}</td>" : "<td style=\"$untagged\" />";
			print defined $tags->{$locus} ? "<td style=\"$tagged\"></td>" : "<td style=\"$untagged\" />";
			print "</tr>\n";
			$first = 0;
		}
		$td = $td == 1 ? 2 : 1;
	}
	my $no_scheme_loci = $self->{'datastore'}->get_loci_in_no_scheme(1);
	my $first          = 1;
	print "<tr class=\"td$td\"><th rowspan=\"" . @$no_scheme_loci . "\">Loci</th>";
	foreach my $locus (@$no_scheme_loci) {
		print "<tr class=\"td$td\">" if !$first;
		my $cleaned = $self->clean_locus($locus);
		print "<td>$cleaned</td>";
		print defined $allele_ids->{$locus} ? "<td style=\"$tagged\">$allele_ids->{$locus}</td>" : "<td style=\"$untagged\" />";
		print defined $tags->{$locus} ? "<td style=\"$tagged\"></td>" : "<td style=\"$untagged\" />";
		print "</tr>\n";
		$first = 0;
	}
	print "</table>\n";
	print "<div class=\"scrollable\">\n";
	print "</div>\n</div>\n";
	return;
}

sub _print_schematic {
	my ( $self, $ids ) = @_;
	my @loci;
	my $schemes = $self->{'datastore'}->run_list_query_hashref("SELECT id,description FROM schemes ORDER BY description");
	my %scheme_loci;
	my @image_map;
	my $i = 0;
	foreach (@$schemes) {
		my $scheme_loci = $self->{'datastore'}->get_scheme_loci( $_->{'id'}, { 'profile_name' => 0, 'analysis_pref' => 1 } );
		push @loci, @$scheme_loci;
		$scheme_loci{ $_->{'id'} } = $scheme_loci;
		( my $desc = $_->{'description'} ) =~ s/&/&amp;/g;
		my $j = $i + @$scheme_loci - 1;
		push @image_map, "<area shape=\"rect\" coords=\"I=$i,0,J=$j,20\" title=\"$desc\" alt=\"$desc\" />\n";
		$i = $j + 1;
	}
	my $no_scheme_loci = $self->{'datastore'}->get_loci_in_no_scheme(1);
	my $j              = $i + @$no_scheme_loci - 1;
	push @image_map, "<area shape=\"rect\" coords=\"I=$i,0,J=$j,20\" title=\"Loci not in scheme\" alt=\"Loci not in scheme\" />\n";
	my $scaling = IMAGE_WIDTH / $j;
	foreach (@image_map) {
		if ( $_ =~ /I=(\d+)/ ) {
			my $new_value = int( $scaling * $1 );
			$_ =~ s/I=\d+/$new_value/;
		}
		if ( $_ =~ /J=(\d+)/ ) {
			my $new_value = int( $scaling * $1 );
			$_ =~ s/J=\d+/$new_value/;
		}
	}
	push @loci, @$no_scheme_loci;
	if ( !@loci ) {
		print "<div class=\"box statusbad\"><p>No loci to analyse.</p></div>\n";
		return;
	}
	print "<div class=\"box\" id=\"resultstable\">\n";
	print "<p>Bars represent loci by schemes arranged in alphabetical order.  If a locus appears in more than one scheme "
	. "it will appear more than once in this graphic.  Click on the id hyperlink for a detailed breakdown for an isolate.</p>\n";
	my @colours = COLOURS;
	print "<h2>Key</h2>\n";
	print "<p><span style=\"color: #$colours[1]; font-weight:600\">Allele designated only</span> | "
	  . "<span style=\"color: #$colours[2]; font-weight:600\">Sequence tagged only</span> | "
	  . "<span style=\"color: #$colours[3]; font-weight:600\">Allele designated + sequence tagged</span></p>";
	print "<map id=\"schemes\" name=\"schemes\">\n@image_map</map>\n";
	print "<div class=\"scrollable\">\n";
	print "<table class=\"resultstable\"><tr><th>Id</th><th>Isolate</th><th>Designation status</th></tr>\n";
	my $isolate_sql = $self->{'db'}->prepare("SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?");
	my $td          = 1;
	my $prefix      = BIGSdb::Utils::get_random();
	local $| = 1;

	foreach my $id (@$ids) {
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
		my @designations;
		eval { $isolate_sql->execute($id) };
		$logger->error($@) if $@;
		my ($isolate)  = $isolate_sql->fetchrow_array;
		my $allele_ids = $self->{'datastore'}->get_all_allele_ids($id);
		my $tags       = $self->{'datastore'}->get_all_allele_sequences($id);
		my $url        = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;name=TagStatus&amp;isolate_id=$id";
		print "<tr class=\"td$td\"><td><a href=\"$url\">$id</a></td><td>$isolate</td>";

		foreach my $scheme (@$schemes) {
			my @loci = @{ $scheme_loci{ $scheme->{'id'} } };
			foreach my $locus (@loci) {
				my $value = defined $allele_ids->{$locus} ? 1 : 0;
				$value += defined $tags->{$locus} ? 2 : 0;
				push @designations, $value;
			}
		}
		foreach my $locus (@$no_scheme_loci) {
			my $value = defined $allele_ids->{$locus} ? 1 : 0;
			$value += defined $tags->{$locus} ? 2 : 0;
			push @designations, $value;
		}
		my $designation_filename = "$self->{'config'}->{'tmp_dir'}/$prefix\_$id\_designation.svg";
		$self->_make_svg( $designation_filename, \@designations );
		system(
"$self->{'config'}->{'mogrify_path'} -format png $designation_filename $self->{'config'}->{'tmp_dir'}/$prefix\_$id\_designation.png"
		);
		unlink $designation_filename;
		print "<td><img src=\"/tmp/$prefix\_$id\_designation.png\" alt=\"\" width=\""
		  . IMAGE_WIDTH
		  . "px\" height=\"20px\" usemap=\"#schemes\" style=\"border:0\" /></td></tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	print "</table>\n</div></div>\n";
	return;
}

sub _make_svg {
	my ( $self, $filename, $values ) = @_;
	open( my $fh, '>', $filename ) or $logger->error("could not open $filename for writing.");
	my $width = @$values;
	print $fh <<"SVG";
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 20001102//EN"
   "http://www.w3.org/TR/2000/CR-SVG-20001102/DTD/svg-20001102.dtd">
   <svg xmlns="http://www.w3.org/2000/svg"
     xmlns:xlink="http://www.w3.org/1999/xlink" width="$width" height="20" viewBox="0 0 $width 10">
SVG
	my $pos     = 0;
	my @colours = COLOURS;
	foreach (@$values) {
		print $fh "<line x1=\"$pos\" y1=\"0\" x2=\"$pos\" y2=\"20\" style=\"stroke-width: 1; stroke: #$colours[$_];\" />\n";
		$pos++;
	}
	print $fh "</svg>\n";
	close $fh;
	return;
}
1;
