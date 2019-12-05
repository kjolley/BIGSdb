#Written by Keith Jolley
#Copyright (c) 2010-2019, University of Oxford
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
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery jQuery.columnizer);
	return;
}

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/data_records.html#sequence-tag-records";
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
	if ( !defined $locus ) {
		say q(<h1>Allele sequence</h1>);
		$self->print_bad_status( { message => q(No locus passed.), navbar => 1 } );
		return;
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( !BIGSdb::Utils::is_int($isolate_id) ) {
		say q(<h1>Allele sequence</h1>);
		$self->print_bad_status( { message => q(Isolate id must be an integer.), navbar => 1 } );
		return;
	}
	my $exists =
	  $self->{'datastore'}
	  ->run_query( "SELECT EXISTS(SELECT * FROM $self->{'system'}->{'view'} WHERE id=?)", $isolate_id );
	if ( !$exists ) {
		say q(<h1>Allele sequence</h1>);
		$self->print_bad_status( { message => q(The database contains no record of this isolate.), navbar => 1 } );
		return;
	}
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		say q(<h1>Allele sequence</h1>);
		$self->print_bad_status( { message => q(Invalid locus selected.), navbar => 1 } );
		return;
	}
	$self->update_prefs if $q->param('reload');
	my @name          = $self->get_name($isolate_id);
	my $display_locus = $self->clean_locus($locus);
	print qq(<h1>$display_locus allele sequence: id-$isolate_id);
	print qq( (@name)) if $name[1];
	say q(</h1>);
	my $flanking = $q->param('flanking') // $self->{'prefs'}->{'flanking'};
	my $qry =
	    'SELECT a.id,a.seqbin_id,a.start_pos,a.end_pos,a.reverse,a.complete,s.method,'
	  . 'GREATEST(r.length,length(s.sequence)) AS seqlength FROM allele_sequences a LEFT JOIN sequence_bin s '
	  . 'ON a.seqbin_id = s.id LEFT JOIN remote_contigs r ON s.id=r.seqbin_id WHERE s.isolate_id=? AND a.locus=? '
	  . 'ORDER BY complete desc,a.datestamp';
	my $data = $self->{'datastore'}->run_query( $qry, [ $isolate_id, $locus ], { fetch => 'all_arrayref' } );
	my $buffer;

	foreach my $allele_sequence (@$data) {
		my ( $id, $seqbin_id, $start_pos, $end_pos, $reverse, $complete, $method, $seqlength ) = @$allele_sequence;
		my $introns =
		  $self->{'datastore'}
		  ->run_query( 'SELECT start_pos AS start,end_pos AS end FROM introns WHERE id=? ORDER BY start_pos',
			$id, { fetch => 'all_arrayref', slice => {} } );
		my $update_buffer = '';
		if ( $self->{'curate'} ) {
			my $intron_clause = q();
			if (@$introns) {
				my @introns;
				foreach my $intron (@$introns) {
					push @introns, qq($intron->{'start'}-$intron->{'end'});
				}
				local $" = q(,);
				$intron_clause = qq(&introns=@introns);
			}
			$update_buffer =
			    qq( <a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagUpdate&amp;id=)
			  . qq($id$intron_clause" class="smallbutton">Update</a>\n);
		}
		$buffer .= q(<div style="float:left">);
		$buffer .= qq(<h2>Contig position$update_buffer</h2>\n);
		my $list = [
			{ title => 'sequence bin id', data => $seqbin_id },
			{ title => 'contig length',   data => $seqlength },
			{ title => 'start',           data => $start_pos },
			{ title => 'end',             data => $end_pos },
			{ title => 'length',          data => abs( $end_pos - $start_pos + 1 ) },
			{ title => 'orientation',     data => $reverse ? 'reverse' : 'forward' },
			{ title => 'complete',        data => $complete ? 'yes' : 'no' }
		];
		push @$list, { title => 'method', data => $method } if $method;
		$buffer .= $self->get_list_block($list);
		$buffer .= q(</div>);
		my $translate = ( $locus_info->{'coding_sequence'} || $locus_info->{'data_type'} eq 'peptide' ) ? 1 : 0;
		my $orf = $locus_info->{'orf'} || 1;
		my $seq_features = $self->get_seq_features(
			{
				seqbin_id => $seqbin_id,
				reverse   => $reverse,
				start     => $start_pos,
				end       => $end_pos,
				flanking  => $flanking,
				introns   => $introns
			}
		);
		$buffer .= $self->get_option_fieldset;
		$buffer .= q(<div style="clear:both"></div>);
		$buffer .= qq(<h2>Sequence</h2>\n);
		$buffer .= q(<div class="seq">);
		$buffer .= $self->format_sequence_features($seq_features);
		$buffer .= q(</div>);

		if (@$introns) {
			$buffer .= q(<p style="margin-top:1em">Key: <span class="flanking">Flanking</span>; )
			  . q(<span class="exon">Exon</span>; <span class="intron">Intron</span></p>);
		}
		if ($translate) {
			$buffer .= qq(<h2>Translation</h2>\n);
			my $stops = $self->find_internal_stops( $seq_features, $orf );
			if (@$stops) {
				local $" = ', ';
				my $plural = @$stops == 1 ? q() : q(s);
				$buffer .= qq(<span class="highlight">Internal stop codon$plural at position$plural: @$stops )
				  . q((numbering includes upstream flanking sequence).</span>);
			}
			$buffer .= q(<pre class="sixpack">);
			$buffer .= $self->get_sixpack_display($seq_features);
			$buffer .= q(</pre>);
		}
	}
	if ($buffer) {
		say q(<div class="box" id="resultspanel"><div class="scrollable">);
		say $buffer;
		say q(</div></div>);
	} else {
		$self->print_bad_status(
			{
				message => qq(This isolate does not have a sequence defined for locus $display_locus.),
				navbar  => 1
			}
		);
	}
	return;
}

sub get_title {
	my ($self)     = @_;
	my $isolate_id = $self->{'cgi'}->param('id');
	my $locus      = $self->{'cgi'}->param('locus');
	return 'Invalid isolate id' if !BIGSdb::Utils::is_int($isolate_id);
	return 'Invalid locus' if !$self->{'datastore'}->is_locus($locus);
	my @name = $self->get_name($isolate_id);
	( my $display_locus = $locus ) =~ tr/_/ /;
	my $title = "$display_locus allele sequence: id-$isolate_id";
	$title .= " (@name)" if $name[1];
	$title .= " - $self->{'system'}->{'description'}";
	return $title;
}
1;
