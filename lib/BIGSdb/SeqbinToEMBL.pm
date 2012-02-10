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
package BIGSdb::SeqbinToEMBL;
use IO::String;
use Bio::SeqIO;
use Bio::SeqFeature::Generic;
use strict;
use warnings;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{'type'} = 'embl';
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $isolate_id;
	my $seqbin_ids = [];
	if ( defined $q->param('seqbin_id') && $q->param('seqbin_id') =~ /^(\d+)$/ ) {
		push @$seqbin_ids, $1;
	} elsif ( defined $q->param('isolate_id') && $q->param('isolate_id') =~ /^(\d+)$/ ) {
		$isolate_id = $1;
		$seqbin_ids = $self->{'datastore'}->run_list_query( "SELECT id FROM sequence_bin WHERE isolate_id=?", $isolate_id );
	} else {
		print "Invalid isolate or sequence bin id.\n";
		return;
	}
	$self->write_embl($seqbin_ids);
	return;
}

sub write_embl {
	my ( $self, $seqbin_ids, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $buffer;
	foreach my $seqbin_id (@$seqbin_ids) {
		my $seq =
		  $self->{'datastore'}->run_simple_query(
			"SELECT isolate_id,sequence,method,comments,sender,curator,date_entered,datestamp FROM sequence_bin WHERE id=?", $seqbin_id );
		my $stringfh_in = IO::String->new( ">$seqbin_id\n" . $seq->[1] . "\n" );
		my $seqin       = Bio::SeqIO->new( -fh => $stringfh_in, -format => 'fasta' );
		my $seq_object  = $seqin->next_seq;
		my $accessions  = $self->{'datastore'}->run_list_query( "SELECT databank_id FROM accession WHERE seqbin_id=?", $seqbin_id );
		unshift @$accessions, $seqbin_id;
		local $" = '; ';
		$seq_object->accession_number("@$accessions") if @$accessions;
		$seq_object->desc( $seq->[3] );
		my $qry = "SELECT * FROM allele_sequences WHERE seqbin_id=?";
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute($seqbin_id) };
		$logger->error($@) if $@;

		while ( my $allele_sequence = $sql->fetchrow_hashref ) {
			my $locus_info = $self->{'datastore'}->get_locus_info( $allele_sequence->{'locus'} );
			my $frame;

			#BIGSdb stored ORF as 1-6.  BioPerl expects 0-2.
			$locus_info->{'orf'} ||= 0;
			if ( $locus_info->{'orf'} == 2 || $locus_info->{'orf'} == 5 ) {
				$frame = 1;
			} elsif ( $locus_info->{'orf'} == 3 || $locus_info->{'orf'} == 6 ) {
				$frame = 2;
			} else {
				$frame = 0;
			}
			$allele_sequence->{'start_pos'} = 1 if $allele_sequence->{'start_pos'} < 1;
			$allele_sequence->{'locus'} = $allele_sequence->{'locus'} . " ($locus_info->{'common_name'})" if $locus_info->{'common_name'};
			my $feature = Bio::SeqFeature::Generic->new(
				-start       => $allele_sequence->{'start_pos'},
				-end         => $allele_sequence->{'end_pos'},
				-primary_tag => 'CDS',
				-strand      => ( $allele_sequence->{'reverse'} ? -1 : 1 ),
				-frame       => $frame,
				-tag         => { gene => $allele_sequence->{'locus'}, product => $locus_info->{'description'} }
			);
			$seq_object->add_SeqFeature($feature);
		}
		my $str;
		my $stringfh_out = IO::String->new( \$str );
		my $seq_out = Bio::SeqIO->new( -fh => $stringfh_out, -format => 'embl' );
		$seq_out->write_seq($seq_object);
		if ($options->{'get_buffer'}){
			$buffer .= $str;
		} else {
			print $str;
		}
	}
	return $options->{'get_buffer'} ? $buffer: undef;
}
1;
