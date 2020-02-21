#Written by Keith Jolley
#Copyright (c) 2020, University of Oxford
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
package BIGSdb::SeqbinToGFF3;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{'type'} = 'gff3';
	return;
}

sub print_content {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $seqbin_ids = [];
	if ( BIGSdb::Utils::is_int( scalar $q->param('seqbin_id') ) ) {
		push @$seqbin_ids, $q->param('seqbin_id');
	} elsif ( BIGSdb::Utils::is_int( scalar $q->param('isolate_id') ) ) {
		$seqbin_ids = $self->{'datastore'}->run_query(
			'SELECT id FROM sequence_bin WHERE isolate_id=?',
			scalar $q->param('isolate_id'),
			{ fetch => 'col_arrayref' }
		);
	}
	if ( !@$seqbin_ids ) {
		say 'Invalid isolate or sequence bin id.';
		return;
	}
	$self->_write_gff3($seqbin_ids);
	return;
}

sub _write_gff3 {
	my ( $self, $seqbin_ids ) = @_;
	my %lengths;
	foreach my $seqbin_id (@$seqbin_ids) {
		my $seq_ref = $self->{'contigManager'}->get_contig($seqbin_id);
		my $seq     = $self->{'datastore'}->run_query(
			'SELECT s.sequence,s.original_designation,r.uri FROM sequence_bin s LEFT JOIN remote_contigs r '
			  . 'ON s.id=r.seqbin_id WHERE s.id=?',
			$seqbin_id,
			{ fetch => 'row_hashref', cache => 'SeqbinToEMBL::write_embl::seq' }
		);
		if ( !$seq->{'sequence'} && $seq->{'uri'} ) {
			my $contig_record = $self->{'contigManager'}->get_remote_contig( $seq->{'uri'} );
			$seq->{$_} = $contig_record->{$_} foreach qw(sequence original_designation);
		}
		$lengths{$seqbin_id} = length $seq->{'sequence'};
	}
	say q(##gff-version 3);
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? 'AND (locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes '
	  . "WHERE set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';
	my $qry = "SELECT * FROM allele_sequences WHERE seqbin_id=? $set_clause ORDER BY start_pos";
	foreach my $seqbin_id (@$seqbin_ids) {
		say qq(##sequence-region $seqbin_id 1 $lengths{$seqbin_id});
		my $allele_sequences =
		  $self->{'datastore'}->run_query( $qry, $seqbin_id,
			{ fetch => 'all_arrayref', slice => {}, cache => 'SeqbinToEMBL::write_eff3::allele_sequences' } );
		foreach my $tag (@$allele_sequences) {
			if ( $tag->{'start_pos'} < 1 ) {
				$tag->{'start_pos'} = 1;
			}
			if ($tag->{'end_pos'} > $lengths{$seqbin_id}){
				$tag->{'end_pos'} = $lengths{$seqbin_id};
			}
			my $locus_info = $self->{'datastore'}->get_locus_info( $tag->{'locus'} );
			my $phase;

			#BIGSdb stored ORF as 1-6.  GFF expects 0-2.
			$locus_info->{'orf'} ||= 0;
			if    ( $locus_info->{'orf'} == 2 || $locus_info->{'orf'} == 5 ) { $phase = 1 }
			elsif ( $locus_info->{'orf'} == 3 || $locus_info->{'orf'} == 6 ) { $phase = 2 }
			else                                                             { $phase = 0 }
			my $strand   = $tag->{'reverse'}  ? '-' : '+';
			my $complete = $tag->{'complete'} ? 1   : 0;
			my $att = qq(locus_tag=$tag->{'locus'});
			$att .= q(;incomplete=1) if !$complete;
			if ( $locus_info->{'dbase_name'} ) {
				my $locus_desc = $self->{'datastore'}->get_locus( $tag->{'locus'} )->get_description;
				if ($locus_desc->{'product'}){
					$locus_desc->{'product'} =~ tr/[;|=]/_/;
					$att.=qq(;product=$locus_desc->{'product'}) if $locus_desc->{'product'};
				}
			}
			$att =~ s/\r?\n//x;
			say qq($seqbin_id\t$self->{'system'}->{'description'}\tgene\t$tag->{'start_pos'}\t)
			  . qq($tag->{'end_pos'}\t.\t$strand\t$phase\t$att);
		}
	}
	return;
}
1;
