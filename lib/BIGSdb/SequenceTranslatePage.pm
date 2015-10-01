#Written by Keith Jolley
#Copyright (c) 2013-2015, University of Oxford
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
use BIGSdb::Constants qw(:interface);
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
	say q(<h1>Sequence translation</h1>);
	if ( !$self->{'config'}->{'emboss_path'} ) {
		$logger->fatal('EMBOSS not installed');
		say q(<div class="box" id="statusbad"><p>EMBOSS needs to be installed for this functionality.</p></div>)
		  ;
		return;
	}
	my $seq = $q->param('sequence') // '';
	$seq =~ s/[^acgtunACGTUN]//x;
	if ( !$seq ) {
		say q(<div class="box" id="statusbad"><p>No valid nucleotide sequence passed.</p></div>);
		return;
	}
	if ( length $seq < 3 ) {
		say q(<div class="box" id="statusbad"><p>Passed sequence is shorter than the length of )
		  . q(a codon so cannot be translated.</p></div>);
		return;
	}
	if ( length $seq > MAX_SEQ_LENGTH ) {
		my $max = MAX_SEQ_LENGTH;
		say q(<div class="box" id="statusbad"><p>Passed sequence is longer than the )
		  . qq(maximum permissible length ($max bp)</p></div>);
		return;
	}
	$seq = BIGSdb::Utils::reverse_complement($seq) if $q->param('reverse');
	$q->param( sequence => $seq );
	say q(<div class="box" id="queryform">);
	say q(<fieldset><legend>Modify sequence attributes</legend>);
	say $q->start_form;
	say q(<ul style="padding-bottom: 0.5em"><li>);
	say q(<label for="orf">ORF: </label>);
	say $q->popup_menu( -name => 'orf', -id => 'orf', -values => [qw(1 2 3)], -default => $orf );
	say q(</li></ul>);
	say q(<span style="float:left">);
	say $q->submit( -label => 'Reverse', -name => 'reverse', -class => BUTTON_CLASS );
	say q(</span>);
	say q(<span style="float:right">);
	say $q->submit( -label => 'Update', -class => BUTTON_CLASS );
	say q(</span>);
	say $q->hidden($_) foreach qw(db page sequence);
	say $q->end_form;
	say q(</fieldset></div>);
	my $formatted_seq = $self->format_sequence( { seq => $seq }, { translate => 1, orf => $orf } );
	say q(<div class="box" id="sequence"><div class="scrollable">);
	say q(<h2>Sequence</h2>);
	say q(<ul><li>Length: ) . ( length $seq ) . q( bp</li></ul>);
	say qq(<div class="seq">$formatted_seq->{'seq'}</div>);
	say q(<h2>Translation</h2>);
	my @stops = @{ $formatted_seq->{'internal_stop'} };

	if (@stops) {
		local $" = ', ';
		my $plural = @stops == 1 ? '' : 's';
		say qq(<span class="highlight">Internal stop codon$plural in ORF-$orf at position$plural: @stops.</span>);
	} else {
		say qq(<span class=\"statusgood\">No internal stop codons in ORF-$orf</span>);
	}
	say q(<pre class="sixpack">);
	say $formatted_seq->{'sixpack'};
	say q(</pre>);
	say q(</div></div>);
	return;
}
1;
