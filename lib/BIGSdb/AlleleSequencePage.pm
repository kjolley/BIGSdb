#Written by Keith Jolley
#Copyright (c) 2010-2013, University of Oxford
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
use 5.010;
use parent qw(BIGSdb::IsolateInfoPage BIGSdb::ExtractedSequencePage);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery jQuery.columnizer);
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $buffer = << "END";
\$(function () {
	\$(".data").columnize({width:400});
});

END
	return $buffer;
}

sub print_content {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $isolate_id = $q->param('id');
	my $locus      = $q->param('locus');
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( !BIGSdb::Utils::is_int($isolate_id) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Isolate id must be an integer.</p></div>";
		return;
	}
	my $exists = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id )->[0];
	if ( !$exists ) {
		say "<div class=\"box\" id=\"statusbad\"><p>The database contains no record of this isolate.</p></div>";
		return;
	}
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Invalid locus selected.</p></div>";
		return;
	}
	my @name          = $self->get_name($isolate_id);
	my $display_locus = $self->clean_locus($locus);
	print "<h1>$display_locus allele sequence: id-$isolate_id";
	print " (@name)" if $name[1];
	say "</h1>";
	my $flanking = $self->{'prefs'}->{'flanking'};
	my $qry =
	    "SELECT seqbin_id,start_pos,end_pos,reverse,complete,method,length(sequence) AS seqlength FROM allele_sequences LEFT "
	  . "JOIN sequence_bin ON allele_sequences.seqbin_id = sequence_bin.id WHERE isolate_id=? AND locus=? ORDER BY "
	  . "complete desc,allele_sequences.datestamp";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute( $isolate_id, $locus ) };
	$logger->error($@) if $@;
	my $buffer;
	my $update_buffer = '';

	while ( my ( $seqbin_id, $start_pos, $end_pos, $reverse, $complete, $method, $seqlength ) = $sql->fetchrow_array ) {
		$buffer .= "<dl class=\"data\">";
		$buffer .= "<dt class=\"dontend\">sequence bin id</dt><dd>$seqbin_id</dd>";
		$buffer .= "<dt class=\"dontend\">contig length</dt><dd>$seqlength</dd>";
		if ( $self->{'curate'} ) {
			$update_buffer = " <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagUpdate&amp;seqbin_id="
			  . "$seqbin_id&amp;locus=$locus&amp;start_pos=$start_pos&amp;end_pos=$end_pos\" class=\"smallbutton\">Update</a>\n";
		}
		my $translate = ( $locus_info->{'coding_sequence'} || $locus_info->{'data_type'} eq 'peptide' ) ? 1 : 0;
		my $orf = $locus_info->{'orf'} || 1;
		$buffer .= "<dt class=\"dontend\">start</dt><dd>$start_pos</dd>\n";
		$buffer .= "<dt class=\"dontend\">end</dt><dd>$end_pos</dd>\n";
		my $length = abs( $end_pos - $start_pos + 1 );
		$buffer .= "<dt class=\"dontend\">length</dt><dd>$length</dd>\n";
		my $orientation = $reverse ? 'reverse' : 'forward';
		$buffer .= "<dt class=\"dontend\">orientation</dt><dd>$orientation</dd>\n";
		$buffer .= "<dt class=\"dontend\">complete</dt><dd>" . ( $complete ? 'yes' : 'no' ) . "</dd>\n";
		$buffer .= "<dt class=\"dontend\">method</dt><dd>$method</dd>\n";
		my $display = $self->format_seqbin_sequence(
			{ seqbin_id => $seqbin_id, reverse => $reverse, start => $start_pos, end => $end_pos, translate => $translate, orf => $orf } );
		$buffer .= "</dl>";
		$buffer .= "<h2>Sequence</h2>\n";
		$buffer .= "<div class=\"seq\">$display->{'seq'}</div>\n";

		if ($translate) {
			$buffer .= "<h2>Translation</h2>\n";
			my @stops = @{ $display->{'internal_stop'} };
			if (@stops) {
				my $plural = @stops == 1 ? '' : 's';
				local $" = ', ';
				$buffer .= "<span class=\"highlight\">Internal stop codon$plural at position$plural: @stops (numbering includes upstream "
				  . "flanking sequence).</span>\n";
			}
			$buffer .= "<pre class=\"sixpack\">\n";
			$buffer .= $display->{'sixpack'};
			$buffer .= "</pre>\n";
		}
	}
	if ($buffer) {
		say "<div class=\"box\" id=\"resultspanel\">\n<div class=\"scrollable\">";
		say "<h2>Contig position$update_buffer</h2>";
		say $buffer;
		say "</div></div>";
	} else {
		say "<div class=\"box\" id=\"statusbad\"><p>This isolate does not have a sequence defined for locus $display_locus.</p></div>";
	}
	return;
}

sub get_title {
	my ($self)     = @_;
	my $isolate_id = $self->{'cgi'}->param('id');
	my $locus      = $self->{'cgi'}->param('locus');
	return "Invalid isolate id" if !BIGSdb::Utils::is_int($isolate_id);
	return "Invalid locus" if !$self->{'datastore'}->is_locus($locus);
	my @name = $self->get_name($isolate_id);
	( my $display_locus = $locus ) =~ tr/_/ /;
	my $title = "$display_locus allele sequence: id-$isolate_id";
	$title .= " (@name)" if $name[1];
	$title .= ' - ';
	$title .= "$self->{'system'}->{'description'}";
	return $title;
}
1;
