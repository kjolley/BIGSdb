#Written by Keith Jolley
#Copyright (c) 2013-2022, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
use Bio::Tools::CodonTable;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant MAX_SEQ_LENGTH => 10000;

sub get_title {
	return 'Sequence translation';
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $orf = $q->param('orf') // 1;
	$orf = 1 if !( BIGSdb::Utils::is_int($orf) && $orf < 4 && $orf > 0 );
	say q(<h1>Sequence translation</h1>);
	if ( !$self->{'config'}->{'emboss_path'} ) {
		$logger->fatal('EMBOSS not installed');
		$self->print_bad_status( { message => q(EMBOSS needs to be installed for this functionality.), navbar => 1 } );
		return;
	}
	my $seq = $q->param('sequence') // '';
	$seq = $self->_strip_headers( \$seq );
	$seq =~ s/[^GATCBDHVRYKMSWNUNgatcbdhvrykmswnun]//gx;
	if ( !$seq ) {
		$self->print_bad_status( { message => q(No valid nucleotide sequence passed.), navbar => 1 } );
		return;
	}
	if ( length $seq < 3 ) {
		$self->print_bad_status(
			{
				message => q(Passed sequence is shorter than the length of a codon so cannot be translated.),
				navbar  => 1
			}
		);
		return;
	}
	if ( length $seq > MAX_SEQ_LENGTH ) {
		my $max = MAX_SEQ_LENGTH;
		$self->print_bad_status(
			{
				message => qq(Passed sequence is longer than the maximum permissible length ($max bp)),
				navbar  => 1
			}
		);
		return;
	}
	$seq = BIGSdb::Utils::reverse_complement($seq) if $q->param('reverse');
	$q->param( sequence => $seq );
	say q(<div class="box" id="queryform">);
	say q(<fieldset><legend>Modify sequence attributes</legend>);
	say $q->start_form;
	say q(<ul style="padding-bottom: 0.5em"><li>);
	say q(<label for="orf" class="display">ORF: </label>);
	say $q->popup_menu( -name => 'orf', -id => 'orf', -values => [qw(1 2 3)], -default => $orf );

	if ( ( $self->{'system'}->{'alternative_codon_tables'} // q() ) eq 'yes' ) {
		say q(</li></li>);
		my $tables = Bio::Tools::CodonTable->tables;
		my $labels = {};
		my @ids    = sort { $a <=> $b } keys %$tables;
		foreach my $id (@ids) {
			$labels->{$id} = "$id - $tables->{$id}";
		}
		my $default_codon_table = $self->{'datastore'}->get_codon_table;
		say q(<label for="codon_table" class="display">Codon table: </label>);
		say $q->popup_menu(
			-name    => 'codon_table',
			-id      => 'codon_table',
			-values  => [ '', @ids ],
			-labels  => $labels,
			-default => $default_codon_table
		);
	}
	say q(</li></ul>);
	say q(<span style="float:left">);
	say $q->submit( -label => 'Reverse', -name => 'reverse', -class => 'small_submit' );
	say q(</span>);
	say q(<span style="float:right">);
	say $q->submit( -label => 'Update', -class => 'small_submit' );
	say q(</span>);
	say $q->hidden($_) foreach qw(db page sequence);
	say $q->end_form;
	say q(</fieldset></div>);
	my $seq_feature = [ { feature => 'allele_seq', sequence => $seq } ];
	say q(<div class="box" id="sequence"><div class="scrollable">);
	say q(<h2>Sequence</h2>);
	say q(<ul><li>Length: ) . ( length $seq ) . q( bp</li></ul>);
	say q(<div class="seq">);
	say $self->format_sequence_features($seq_feature);
	say q(</div>);
	say q(<h2>Translation</h2>);
	
	my $codon_table = $q->param('codon_table') // $self->{'datastore'}->get_codon_table;

	if ( !BIGSdb::Utils::is_int($codon_table) ) {
		$codon_table = $self->{'datastore'}->get_codon_table;
	}
	if ( $codon_table =~ /^(\d*)$/x ) {
		$codon_table = $1;    #untaint
	}
	my $stops = $self->find_internal_stops( $seq_feature, $orf, { codon_table => $codon_table } );
	if (@$stops) {
		local $" = ', ';
		my $plural = @$stops == 1 ? '' : 's';
		say qq(<span class="highlight">Internal stop codon$plural in ORF-$orf at position$plural: @$stops.</span>);
	} else {
		say qq(<span class="statusgood">No internal stop codons in ORF-$orf</span>);
	}
	say q(<pre class="sixpack">);
	say $self->get_sixpack_display( $seq_feature, $orf, { codon_table => $codon_table } );
	say q(</pre>);
	say q(</div></div>);
	return;
}

sub _strip_headers {
	my ( $self, $seq_ref ) = @_;
	my @lines = split /\n/x, $$seq_ref;
	my $seq;
	foreach my $line (@lines) {
		next if $line =~ /^>/x;
		$seq .= $line;
	}
	return $seq;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery);
	$self->set_level1_breadcrumbs;
	return;
}
1;
