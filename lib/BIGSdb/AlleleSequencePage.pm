#Written by Keith Jolley
#Copyright (c) 2010-2018, University of Oxford
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
		my $update_buffer = '';
		if ( $self->{'curate'} ) {
			$update_buffer =
			    qq( <a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagUpdate&amp;id=)
			  . qq($id" class="smallbutton">Update</a>\n);
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
		my $display = $self->format_seqbin_sequence(
			{
				seqbin_id => $seqbin_id,
				reverse   => $reverse,
				start     => $start_pos,
				end       => $end_pos,
				translate => $translate,
				orf       => $orf,
				flanking  => $flanking
			}
		);
		$buffer .= $self->get_option_fieldset;
		$buffer .= q(<div style="clear:both"></div>);
		$buffer .= qq(<h2>Sequence</h2>\n);
		$buffer .= qq(<div class="seq">$display->{'seq'}</div>\n);
		if ($translate) {
			$buffer .= qq(<h2>Translation</h2>\n);
			my @stops = @{ $display->{'internal_stop'} };
			if (@stops) {
				my $plural = @stops == 1 ? '' : 's';
				local $" = ', ';
				$buffer .= qq[<span class="highlight">Internal stop codon$plural at position$plural: @stops ]
				  . qq[(numbering includes upstream flanking sequence).</span>\n];
			}
			$buffer .= qq(<pre class="sixpack">\n);
			$buffer .= $display->{'sixpack'};
			$buffer .= qq(</pre>\n);
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
