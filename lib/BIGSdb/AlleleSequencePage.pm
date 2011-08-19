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
package BIGSdb::AlleleSequencePage;
use strict;
use warnings;
use base qw(BIGSdb::IsolateInfoPage BIGSdb::ExtractedSequencePage);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self)   = @_;
	my $q          = $self->{'cgi'};
	my $isolate_id = $q->param('id');
	my $locus      = $q->param('locus');
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( !BIGSdb::Utils::is_int($isolate_id) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Isolate id must be an integer.</p></div>\n";
		return;
	}
	my $exists = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id )->[0];
	if ( !$exists ) {
		print "<div class=\"box\" id=\"statusbad\"><p>The database contains no record of this isolate.</p></div>\n";
		return;
	}
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid locus selected.</p></div>\n";
		return;
	}
	my @name = $self->get_name($isolate_id);
	my $display_locus = $self->clean_locus($locus);
	print "<h1>$display_locus allele sequence: id-$isolate_id";
	print " (@name)" if $name[1];
	print "</h1>\n";
	my $flanking = $self->{'prefs'}->{'flanking'};
	my $qry      =
"SELECT seqbin_id,start_pos,end_pos,reverse,complete,method FROM allele_sequences LEFT JOIN sequence_bin ON allele_sequences.seqbin_id = sequence_bin.id WHERE isolate_id=? AND locus=? ORDER BY complete desc,allele_sequences.datestamp";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute( $isolate_id, $locus ) };
	$logger->error($@) if $@;
	my $buffer;
	my $td = 1;
	while ( my ( $seqbin_id, $start_pos, $end_pos, $reverse, $complete, $method ) = $sql->fetchrow_array ) {
		$buffer .= "<tr><th colspan=\"3\">sequence bin id#$seqbin_id";
		if ($self->{'curate'}){
			$buffer .= "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagUpdate&amp;seqbin_id=$seqbin_id&amp;locus=$locus&amp;start_pos=$start_pos\" class=\"smallbutton\">Update</a>\n";
		}
		$buffer .= "</th></tr>\n";
		$buffer .=
"<tr class=\"td$td\"><th>start</th><td>$start_pos</td><td rowspan=\"6\" class=\"seq\" style=\"text-align:left\">";
		my $translate = ($locus_info->{'coding_sequence'} || $locus_info->{'data_type'} eq 'peptide') ? 1 : 0;
		my $orf = $locus_info->{'orf'} || 1;
		my $display = $self->display_sequence($seqbin_id,$reverse,$start_pos,$end_pos,$translate,$orf);
		$buffer .= $display->{'seq'};
		$buffer .="</td></tr>\n";
		$buffer .= "<tr class=\"td$td\"><th>end</th><td>$end_pos</td></tr>\n";
		my $length   = abs( $end_pos - $start_pos + 1 );
		$buffer .= "<tr class=\"td$td\"><th>length</th><td>$length</td></tr>\n";
		$buffer .=
		  "<tr class=\"td$td\"><th>orientation</th><td style=\"font-size:2em\">" . ( $reverse ? '&larr;' : '&rarr;' ) . "</td></tr>\n";
		$buffer .= "<tr class=\"td$td\"><th>complete</th><td>" . ( $complete ? 'yes' : 'no' ) . "</td></tr>\n";
		$buffer .= "<tr class=\"td$td\"><th>method</th><td>$method</td></tr>\n";
		if ($translate){
			$buffer .= "<tr class=\"td1\"><th>translation</th><td colspan=\"2\" style=\"text-align:left\">";
			my @stops = @{$display->{'internal_stop'}};
			if (@stops){
				$"=', ';
				$buffer .= "<span class=\"highlight\">Internal stop codon" . (@stops == 1 ? '' : 's') . " at position". (@stops == 1 ? '' : 's') . ": @stops (numbering includes upstream flanking sequence).</span>\n";
			}
			$buffer .= "<pre class=\"sixpack\">\n";
			$buffer .= $display->{'sixpack'};
			$buffer .= "</pre>\n";
			$buffer .= "</td></tr>\n";
		}

		$td = 1 ? 2 : 1;
	}
	if ($buffer) {
		print "<div class=\"box\" id=\"resultstable\">\n<div class=\"scrollable\">\n<table class=\"resultstable\">\n";
		print $buffer;
		print "</table>\n</div>\n</div>\n";
	} else {
		print "<div class=\"box\" id=\"statusbad\"><p>This isolate does not have a sequence defined for locus $display_locus.</p></div>\n";
	}
}

sub get_title {
	my ($self)   = @_;
	my $isolate_id = $self->{'cgi'}->param('id');
	my $locus      = $self->{'cgi'}->param('locus');
	return "Invalid isolate id" if !BIGSdb::Utils::is_int($isolate_id);
	return "Invalid locus"      if !$self->{'datastore'}->is_locus($locus);
	my @name = $self->get_name($isolate_id);
	( my $display_locus = $locus ) =~ tr/_/ /;
	my $title = "$display_locus allele sequence: id-$isolate_id";
	$title .= " (@name)" if $name[1];
	$title .= ' - ';
	$title .= "$self->{'system'}->{'description'}";
	return $title;
}
1;


