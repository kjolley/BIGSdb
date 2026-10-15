#SeqTableExport.pm - Plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2014-2026, University of Oxford
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
package BIGSdb::Plugins::SeqTableExport;
use strict;
use warnings;
use 5.010;
use parent            qw(BIGSdb::Plugin);
use BIGSdb::Constants qw(:interface DATABANKS);
use Log::Log4perl     qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

sub get_attributes {
	my %att = (
		name    => 'Sequence Table Export',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			}
		],
		description => 'Export table of sequences and attributes following an allele attribute query',
		category    => 'Export',
		menutext    => 'Export table',
		buttontext  => 'Table',
		module      => 'SeqTableExport',
		version     => '1.3.0',
		dbtype      => 'sequences',
		seqdb_type  => 'sequences',
		input       => 'query',
		section     => 'postquery',
		order       => 50
	);
	return \%att;
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Export sequence attribute table</h1>);
	my $locus = $q->param('locus');
	$locus =~ s/^cn_//x;
	if ( !$locus ) {
		$self->print_bad_status( { message => q(No locus selected.), navbar => 1 } );
		$logger->error('No locus passed.');
		return;
	}
	my $query_file = $q->param('query_file');
	my $list_file  = $q->param('list_file');
	my $list       = $self->get_allele_id_list( $query_file, $list_file );
	if ( !@$list ) {
		$self->print_bad_status( { message => q(No sequences available from query.), navbar => 1 } );
		$logger->error('No sequences available.');
		return;
	}
	say q(<div class="box" id="resultspanel"><div class="scrollable">);
	say q(<h2>Export</h2>);
	my $filename  = $self->_create_table( $locus, $list );
	my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
	if ( -e $full_path ) {
		say q(<p>);
		my $text_file_icon = TEXT_FILE;
		print qq(<li><a href="/tmp/$filename" title="Tab-delimited text">$text_file_icon</a>);
		my $excel = BIGSdb::Utils::text2excel(
			$full_path,
			{
				max_width     => 25,
				field_options => {
					'linked data values' => { max_width => 60, align => 'left' }
				}
			}
		);
		if ( -e $excel ) {
			my $excel_file_icon = EXCEL_FILE;
			( my $excel_file = $filename ) =~ s/txt/xlsx/;
			say qq(<a href="/tmp/$excel_file" title="Excel file">$excel_file_icon</a>);
		}
		say q(</p>);
	} else {
		say q(<p>Output file not available.</p>);
	}
	say q(</div></div>);
	return;
}

sub _create_table {
	my ( $self, $locus, $list ) = @_;
	my $prefix        = BIGSdb::Utils::get_random();
	my $filename      = "$prefix.txt";
	my $full_path     = "$self->{'config'}->{'tmp_dir'}/$filename";
	my $headers       = $self->_get_headers($locus);
	my $header_exists = { map { $_ => 1 } @$headers };
	open( my $fh, '>:encoding(utf8)', $full_path ) || $logger->error("Can't open $full_path for writing");
	local $" = "\t";
	say $fh "@$headers";
	local $| = 1;
	say q(<div class="hideonload"><p>Please wait - calculating (do not refresh) ...</p>)
	  . q(<p><span class="wait_icon fas fa-sync-alt fa-spin fa-4x"></span></p></div>);

	if ( $ENV{'MOD_PERL'} ) {
		eval { $self->{'mod_perl_request'}->rflush };
	}
	foreach my $allele_id (@$list) {
		my @results;
		my $attributes = $self->_get_allele_attributes( $locus, $allele_id );
		push @results, @$attributes;
		my $ext_attributes = $self->_get_allele_extended_attributes( $locus, $allele_id );
		push @results, @$ext_attributes;
		my $peptide_mutations = $self->_get_allele_peptide_mutations( $locus, $allele_id );
		push @results, @$peptide_mutations;
		my $dna_mutations = $self->_get_allele_dna_mutations( $locus, $allele_id );
		push @results, @$dna_mutations;
		my $databank_values = $self->_get_allele_databank_values( $header_exists, $locus, $allele_id );
		push @results, @$databank_values;
		my $pubmed_values = $self->_get_allele_pubmed_values( $header_exists, $locus, $allele_id );
		push @results, $pubmed_values if $header_exists->{'PubMed'};

		if ( $header_exists->{'linked data values'} ) {
			push @results, $self->_get_linked_data_values( $locus, $allele_id );
		}
		my $flags = $self->{'datastore'}->get_allele_flags( $locus, $allele_id );
		local $" = q(; );
		push @results, qq(@$flags);
		local $" = qq(\t);
		say $fh qq(@results);
	}
	close $fh;
	return $filename;
}

sub _get_linked_data_values {
	my ( $self, $locus, $allele_id ) = @_;

	my $linked = $self->{'datastore'}->get_client_data_linked_to_allele( $locus, $allele_id );

	return q() if !$linked || !$linked->{'detailed_values'};

	my @values;
	local $" = q(; );
	foreach my $db ( sort keys %{ $linked->{'detailed_values'} } ) {
		foreach my $field ( sort keys %{ $linked->{'detailed_values'}->{$db} } ) {
			my @field_values;
			foreach my $entry ( @{ $linked->{'detailed_values'}->{$db}->{$field} } ) {
				push @field_values, qq($entry->{'value'} [n=$entry->{'frequency'}]);
			}
			push @values, qq($db $field: @field_values);
		}
	}
	return qq(@values);
}

sub _get_allele_attributes {
	my ( $self, $locus, $allele_id ) = @_;
	my $values = [];
	if ( !defined $self->{'cache'}->{'attributes'} ) {
		$self->{'cache'}->{'attributes'} = $self->{'datastore'}->get_table_field_attributes('sequences');
	}
	my $data = $self->{'datastore'}->run_query(
		'SELECT * FROM sequences WHERE (locus,allele_id)=(?,?)',
		[ $locus, $allele_id ],
		{ fetch => 'row_hashref', cache => 'SeqTableExport::create_table' }
	);
	foreach my $attribute ( @{ $self->{'cache'}->{'attributes'} } ) {
		next if $attribute->{'hide_public'};
		push @$values, $data->{ $attribute->{'name'} } // '';
		push @$values, length( $data->{'sequence'} ) if $attribute->{'name'} eq 'sequence';
	}
	return $values;
}

sub _get_allele_extended_attributes {
	my ( $self, $locus, $allele_id ) = @_;
	if ( !defined $self->{'cache'}->{'ext_attributes'} ) {
		$self->{'cache'}->{'ext_attributes'} =
		  $self->{'datastore'}
		  ->run_query( 'SELECT field FROM locus_extended_attributes WHERE locus=? ORDER BY field_order,field',
			$locus, { fetch => 'col_arrayref' } );
	}
	my $values   = [];
	my $ext_data = $self->{'datastore'}->run_query(
		'SELECT * FROM sequence_extended_attributes WHERE (locus,allele_id)=(?,?)',
		[ $locus, $allele_id ],
		{ fetch => 'all_hashref', key => 'field', cache => 'SeqTableExport::get_allele_extended_attributes' }
	);
	foreach my $ext_attribute ( @{ $self->{'cache'}->{'ext_attributes'} } ) {
		push @$values, $ext_data->{$ext_attribute}->{'value'} // '';
	}
	return $values;
}

sub _get_allele_peptide_mutations {
	my ( $self, $locus, $allele_id ) = @_;
	if ( !defined $self->{'cache'}->{'peptide_mutations'} ) {
		$self->{'cache'}->{'peptide_mutations'} =
		  $self->{'datastore'}
		  ->run_query( 'SELECT * FROM peptide_mutations WHERE locus=? ORDER BY reported_position,id',
			$locus, { fetch => 'all_arrayref', slice => {}, cache => 'SeqTableExport::get_allele_peptide_mutations' } );
	}
	my $values = [];
	foreach my $mutation ( @{ $self->{'cache'}->{'peptide_mutations'} } ) {
		my $data = $self->{'datastore'}->run_query(
			'SELECT * FROM sequences_peptide_mutations WHERE (locus,allele_id,mutation_id)=(?,?,?)',
			[ $locus, $allele_id, $mutation->{'id'} ],
			{ fetch => 'row_hashref', cache => 'SeqTableExport::get_sequence_peptide_mutation' }
		);
		my $value = q();
		if ($data) {
			if ( $data->{'is_wild_type'} ) {
				$value = "WT ($data->{'amino_acid'})";
			} elsif ( $data->{'is_mutation'} ) {
				( my $wt = $mutation->{'wild_type_aa'} ) =~ s/;//gx;
				$value = "$wt$mutation->{'reported_position'}$data->{'amino_acid'}";
			}
		}
		push @$values, $value;
	}
	return $values;
}

sub _get_allele_dna_mutations {
	my ( $self, $locus, $allele_id ) = @_;
	if ( !defined $self->{'cache'}->{'dna_mutations'} ) {
		$self->{'cache'}->{'dna_mutations'} =
		  $self->{'datastore'}->run_query( 'SELECT * FROM dna_mutations WHERE locus=? ORDER BY reported_position,id',
			$locus, { fetch => 'all_arrayref', slice => {}, cache => 'SeqTableExport::get_allele_dna_mutations' } );
	}
	my $values = [];
	foreach my $mutation ( @{ $self->{'cache'}->{'dna_mutations'} } ) {
		my $data = $self->{'datastore'}->run_query(
			'SELECT * FROM sequences_dna_mutations WHERE (locus,allele_id,mutation_id)=(?,?,?)',
			[ $locus, $allele_id, $mutation->{'id'} ],
			{ fetch => 'row_hashref', cache => 'SeqTableExport::get_allele_dna_mutation' }
		);
		my $value = q();
		if ($data) {
			if ( $data->{'is_wild_type'} ) {
				$value = "WT ($data->{'nucleotide'})";
			} elsif ( $data->{'is_mutation'} ) {
				( my $wt = $mutation->{'wild_type_nuc'} ) =~ s/;//gx;
				$value = "$wt$mutation->{'reported_position'}$data->{'nucleotide'}";
			}
		}
		push @$values, $value;
	}
	return $values;
}

sub _get_allele_databank_values {
	my ( $self, $header_exists, $locus, $allele_id ) = @_;
	local $" = '; ';
	my @databanks = DATABANKS;
	my $values    = [];
	foreach my $databank ( sort @databanks ) {
		next if !$header_exists->{$databank};
		my $accessions = $self->{'datastore'}->run_query(
			'SELECT databank,databank_id FROM accession WHERE (locus,allele_id,databank)=(?,?,?)',
			[ $locus, $allele_id, $databank ],
			{
				fetch => 'all_arrayref',
				slice => {},
				cache => 'SeqTableExport::get_allele_databank_values'
			}
		);
		my @values;
		foreach my $accession (@$accessions) {
			push @values, $accession->{'databank_id'};
		}
		push @$values, qq(@values);
	}
	return $values;
}

sub _get_allele_pubmed_values {
	my ( $self, $header_exists, $locus, $allele_id ) = @_;
	return if !$header_exists->{'PubMed'};
	my $pmids = $self->{'datastore'}->run_query(
		'SELECT pubmed_id FROM sequence_refs WHERE (locus,allele_id)=(?,?) ORDER BY pubmed_id',
		[ $locus, $allele_id ],
		{
			fetch => 'col_arrayref',
			cache => 'SeqTableExport::get_allele_pubmed_values'
		}
	);
	local $" = '; ';
	return qq(@$pmids);
}

sub _get_headers {
	my ( $self, $locus ) = @_;
	my $headers    = [];
	my $attributes = $self->{'datastore'}->get_table_field_attributes('sequences');
	foreach my $attribute (@$attributes) {
		next if $attribute->{'hide_public'};
		push @$headers, $attribute->{'name'};
		push @$headers, 'sequence length' if $attribute->{'name'} eq 'sequence';
	}
	my $prefix    = BIGSdb::Utils::get_random();
	my $filename  = "$prefix.txt";
	my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
	my $extended_attributes =
	  $self->{'datastore'}
	  ->run_query( 'SELECT field FROM locus_extended_attributes WHERE locus=? ORDER BY field_order,field',
		$locus, { fetch => 'col_arrayref' } );
	push @$headers, @$extended_attributes;
	my $peptide_mutations =
	  $self->{'datastore'}->run_query( 'SELECT * FROM peptide_mutations WHERE locus=? ORDER BY reported_position,id',
		$locus, { fetch => 'all_arrayref', slice => {} } );
	foreach my $mutation (@$peptide_mutations) {
		push @$headers, "SAV$mutation->{'reported_position'}";
	}
	my $dna_mutations =
	  $self->{'datastore'}->run_query( 'SELECT * FROM dna_mutations WHERE locus=? ORDER BY reported_position,id',
		$locus, { fetch => 'all_arrayref', slice => {} } );
	foreach my $mutation (@$dna_mutations) {
		push @$headers, "SNP$mutation->{'reported_position'}";
	}
	my $databanks =
	  $self->{'datastore'}->run_query( 'SELECT DISTINCT databank FROM accession WHERE locus=? ORDER BY databank',
		$locus, { fetch => 'col_arrayref' } );
	push @$headers, @$databanks;
	if ( $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM sequence_refs WHERE locus=?)', $locus ) ) {
		push @$headers, 'PubMed';
	}
	if (
		$self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM client_dbase_loci_fields ' . 'WHERE locus=? AND allele_query)', $locus
		)
	  )
	{
		push @$headers, 'linked data values';
	}
	if ( ( $self->{'system'}->{'allele_flags'} // q() ) eq 'yes' ) {
		push @$headers, 'flags';
	}
	return $headers;
}
1;
