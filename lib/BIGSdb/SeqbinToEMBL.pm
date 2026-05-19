#Written by Keith Jolley
#Copyright (c) 2010-2026, University of Oxford
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
package BIGSdb::SeqbinToEMBL;
use strict;
use warnings;
use 5.010;
use IO::Handle;
use Bio::SeqIO;
use Bio::SeqFeature::Generic;
use parent        qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( ( scalar $q->param('format') // q() ) eq 'genbank' ) {
		$self->{'type'} = 'genbank';
	} else {
		$self->{'type'} = 'embl';
	}
	$self->{'noCache'} = 1;
	return;
}

sub print_content {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $seqbin_ids = [];
	if ( BIGSdb::Utils::is_int( scalar $q->param('seqbin_id') ) ) {
		if (
			$self->{'datastore'}->run_query(
				'SELECT EXISTS(SELECT * FROM sequence_bin WHERE isolate_id IN '
				  . "(SELECT id FROM $self->{'system'}->{'view'}) AND id=?)",
				scalar $q->param('seqbin_id')
			)
		  )
		{
			push @$seqbin_ids, scalar $q->param('seqbin_id');
		}
	} elsif ( BIGSdb::Utils::is_int( scalar $q->param('isolate_id') ) ) {
		$seqbin_ids = $self->{'datastore'}->run_query(
			"SELECT s.id FROM sequence_bin s JOIN $self->{'system'}->{'view'} v ON s.isolate_id=v.id "
			  . 'WHERE isolate_id=? ORDER BY id',
			scalar $q->param('isolate_id'),
			{ fetch => 'col_arrayref' }
		);
	}
	if ( !@$seqbin_ids ) {
		say 'Invalid isolate or sequence bin id.';
		return;
	}
	my $options;
	$options->{'format'} = $q->param('format') // 'embl';
	$self->_write_embl( $seqbin_ids, $options );
	return;
}

sub _write_embl {
	my ( $self, $seqbin_ids, $options ) = @_;
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? 'AND (locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes '
	  . "WHERE set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';

	my $temp_table     = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $seqbin_ids );
	my $seqbin_records = $self->{'datastore'}->run_query(
		"SELECT s.id, s.sequence,s.comments,r.uri FROM sequence_bin s JOIN $temp_table t ON s.id=t.value "
		  . 'LEFT JOIN remote_contigs r ON s.id=r.seqbin_id ORDER BY s.id',
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $accession_list =
	  $self->{'datastore'}
	  ->run_query( "SELECT seqbin_id,databank_id FROM accession a JOIN $temp_table t ON a.seqbin_id=t.value",
		undef, { fetch => 'all_arrayref', slice => {} } );
	my $accessions = {};
	foreach my $accession (@$accession_list) {
		push @{ $accessions->{ $accession->{'seqbin_id'} } }, $accession->{'databank_id'};
	}
	my $allele_sequences = $self->{'datastore'}->run_query(
		"SELECT a.* FROM allele_sequences a JOIN $temp_table t ON "
		  . "a.seqbin_id=t.value $set_clause ORDER BY a.seqbin_id,start_pos,locus",
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $allele_seqs_seqbin_id = {};
	foreach my $as (@$allele_sequences) {
		push @{ $allele_seqs_seqbin_id->{ $as->{'seqbin_id'} } }, $as;
	}
	foreach my $seq (@$seqbin_records) {
		if ( !$seq->{'sequence'} && $seq->{'uri'} ) {
			my $contig_record = $self->{'contigManager'}->get_remote_contig( $seq->{'uri'} );
			$seq->{'sequence'} = $contig_record->{'sequence'};
		}

		my $sequence   = $seq->{'sequence'} // q();
		my $seq_length = length $sequence;

		my $seq_object = Bio::Seq->new(
			-display_id => $seq->{'id'},
			-seq        => $sequence,
			-alphabet   => 'dna',
			-desc       => $seq->{'comments'} // q(),
		);
		unshift @{ $accessions->{ $seq->{'id'} } }, $seq->{'id'};
		local $" = '; ';
		$seq_object->accession_number("@{$accessions->{$seq->{'id'}}}");

		foreach my $allele_sequence ( @{ $allele_seqs_seqbin_id->{ $seq->{'id'} } } ) {
			my $locus_info = $self->{'datastore'}->get_locus_info( $allele_sequence->{'locus'} );
			my $frame;

			#BIGSdb stored ORF as 1-6.  BioPerl expects 0-2.
			$locus_info->{'orf'} ||= 0;
			if    ( $locus_info->{'orf'} == 2 || $locus_info->{'orf'} == 5 ) { $frame = 1 }
			elsif ( $locus_info->{'orf'} == 3 || $locus_info->{'orf'} == 6 ) { $frame = 2 }
			else                                                             { $frame = 0 }
			$allele_sequence->{'start_pos'} = 1           if $allele_sequence->{'start_pos'} < 1;
			$allele_sequence->{'end_pos'}   = $seq_length if $allele_sequence->{'end_pos'} > $seq_length;
			my ( $product, $desc );

			if ( $locus_info->{'dbase_name'} ) {
				if ( !defined $self->{'cache'}->{'locus_description'}->{ $allele_sequence->{'locus'} } ) {
					my $locus_desc = $self->{'datastore'}->get_locus( $allele_sequence->{'locus'} )->get_description;

					$self->{'cache'}->{'locus_description'}->{ $allele_sequence->{'locus'} } = $locus_desc;
				}
				my $locus_desc = $self->{'cache'}->{'locus_description'}->{ $allele_sequence->{'locus'} };
				$product = $locus_desc->{'product'};
				$desc    = $locus_desc->{'full_name'};
				$desc .= ' - ' if $desc && $locus_desc->{'description'};
				$desc .= $locus_desc->{'description'} // '';

			}

			#Cache alternative names because we now call this module from the Contigs batch downloader.
			#Previously it was only used for one isolate at a time so caching was not necessary.
			if ( !defined $self->{'cache'}->{'alternatives'}->{ $allele_sequence->{'locus'} } ) {
				my $alternatives = [];
				push @$alternatives, $locus_info->{'common_name'} if $locus_info->{'common_name'};
				my $aliases = $self->{'datastore'}->run_query(
					'SELECT alias FROM locus_aliases WHERE locus=? ORDER BY alias',
					$allele_sequence->{'locus'},
					{ fetch => 'col_arrayref', cache => 'SeqbinToEMBL::write_embl::locus_aliases' }
				);
				push @$alternatives, @$aliases;
				$self->{'cache'}->{'alternatives'}->{ $allele_sequence->{'locus'} } = $alternatives;
			}
			my $alternatives = $self->{'cache'}->{'alternatives'}->{ $allele_sequence->{'locus'} };
			if (@$alternatives) {
				$desc .= '; ' if $desc;
				local $" = q(, );
				my $plural = @$alternatives == 1 ? q() : q(s);
				$desc .= "Alternative name$plural: @$alternatives";
			}
			my $feature = Bio::SeqFeature::Generic->new(
				-start       => $allele_sequence->{'start_pos'},
				-end         => $allele_sequence->{'end_pos'},
				-primary_tag => 'CDS',
				-strand      => ( $allele_sequence->{'reverse'} ? -1 : 1 ),
				-frame       => $frame,
				-tag         => { gene => $allele_sequence->{'locus'}, product => $product, note => $desc }
			);
			$seq_object->add_SeqFeature($feature);
		}
		my $str;
		open( my $stringfh_out, '>:encoding(utf8)', \$str ) or $logger->error("Could not open string for writing: $!");
		my %allowed_format = map { $_ => 1 } qw(genbank embl);
		my $format         = $allowed_format{ $options->{'format'} } ? $options->{'format'} : 'embl';
		my $seq_out        = Bio::SeqIO->new( -fh => $stringfh_out, -format => $format );
		$seq_out->verbose(-1);    #Otherwise apache error log can fill rapidly on old version of BioPerl.
		$seq_out->write_seq($seq_object);
		close $stringfh_out;
		eval { print $str; };     #If client drops connection this can result in Apache error.

		if ($@) {
			$logger->error($@) if $@ !~ /Broken\spipe/x && $@ !~ /connection\sabort/x;
			last;
		}
	}
	return;
}
1;
