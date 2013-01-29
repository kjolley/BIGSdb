#Written by Keith Jolley
#Copyright (c) 2013, University of Oxford
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
package BIGSdb::SequenceTranslatePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::ExtractedSequencePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant MAX_SEQ_LENGTH => 10000;

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Sequence translation - $desc";
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $orf = $q->param('orf') // 1;
	$orf = 1 if !( BIGSdb::Utils::is_int($orf) && $orf < 4 && $orf > 0 );
	say "<h1>Sequence translation</h1>";
	if ( !$self->{'config'}->{'emboss_path'} ) {
		$logger->fatal("EMBOSS not installed");
		say "<div class=\"box\" id=\"statusbad\"><p>EMBOSS needs to be installed for this functionality.</p></div>";
		return;
	}
	my $seq = $q->param('sequence') // '';
	$seq =~ s/[^acgtunACGTUN]//;
	if ( !$seq ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No valid nucleotide sequence passed.</p></div>";
		return;
	}
	if ( length $seq < 3 ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Passed sequence is shorter than the length of a codon so cannot be "
		  . "translated.</p></div>";
		return;
	}
	if ( length $seq > MAX_SEQ_LENGTH ) {
		my $max = MAX_SEQ_LENGTH;
		say "<div class=\"box\" id=\"statusbad\"><p>Passed sequence is longer than the maximum permissible length ($max bp)</p></div>";
		return;
	}
	$seq = BIGSdb::Utils::reverse_complement($seq) if $q->param('reverse');
	$q->param( 'sequence', $seq );
	say "<div class=\"box\" id=\"queryform\">";
	say "<fieldset><legend>Modify sequence attributes</legend>";
	say $q->start_form;
	say "<ul style=\"padding-bottom: 0.5em\"><li>";
	say "<label for=\"orf\">ORF: </label>";
	say $q->popup_menu( -name => 'orf', -id => 'orf', -values => [qw(1 2 3)], -default => $orf );
	say "</li></ul>";
	say "<span style=\"float:left\">";
	say $q->submit( -label => 'Reverse', -name => 'reverse', -class => 'submit' );
	say "</span>";
	say "<span style=\"float:right\">";
	say $q->submit( -label => 'Update', -class => 'submit' );
	say "</span>";
	say $q->hidden($_) foreach qw(db page sequence);
	say $q->end_form;
	say "</fieldset></div>";
	my $formatted_seq = $self->format_sequence( { seq => $seq }, { translate => 1, orf => $orf } );
	say "<div class=\"box\" id=\"sequence\"><div class=\"scrollable\">";
	say "<h2>Sequence</h2>";
	say "<ul><li>Length: " . ( length $seq ) . " bp</li></ul>";
	say "<div class=\"seq\">$formatted_seq->{'seq'}</div>";
	say "<h2>Translation</h2>";
	my @stops = @{ $formatted_seq->{'internal_stop'} };

	if (@stops) {
		local $" = ', ';
		my $plural = @stops == 1 ? '' : 's';
		say
"<span class=\"highlight\">Internal stop codon$plural in ORF-$orf at position$plural: @stops (numbering includes upstream flanking "
		  . "sequence).</span>";
	} else {
		say "<span class=\"statusgood\">No internal stop codons in ORF-$orf</span>";
	}
	say "<pre class=\"sixpack\">";
	say $formatted_seq->{'sixpack'};
	say "</pre>";
	say "</div></div>";
	return;
}
1;
