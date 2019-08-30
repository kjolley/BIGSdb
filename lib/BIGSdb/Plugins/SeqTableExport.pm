#SeqTableExport.pm - Plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2014-2019, University of Oxford
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
package BIGSdb::Plugins::SeqTableExport;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use BIGSdb::Constants qw(:interface DATABANKS);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

sub get_attributes {
	my %att = (
		name        => 'Sequence Table Export',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Export table of sequences and attributes following an allele attribute query',
		category    => 'Export',
		menutext    => 'Export table',
		buttontext  => 'Table',
		module      => 'SeqTableExport',
		version     => '1.1.0',
		dbtype      => 'sequences',
		seqdb_type  => 'sequences',
		input       => 'query',
		section     => 'postquery',
		order       => 20
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
	my $filename = $self->_create_table( $locus, $list );
	my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
	if ( -e $full_path ) {
		say q(<p>);
		my $text_file_icon = TEXT_FILE;
		print qq(<li><a href="/tmp/$filename" title="Tab-delimited text">$text_file_icon</a>);
		my $excel = BIGSdb::Utils::text2excel( $full_path, { max_width => 25 } );
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
	my $attributes = $self->{'datastore'}->get_table_field_attributes('sequences');
	my $extended_attributes =
	  $self->{'datastore'}->run_query( 'SELECT field FROM locus_extended_attributes WHERE locus=? ORDER BY field_order',
		$locus, { fetch => 'col_arrayref' } );
	my @att_header;
	foreach my $attribute (@$attributes) {
		next if $attribute->{'hide_public'};
		push @att_header, $attribute->{'name'};
		push @att_header, 'sequence length' if $attribute->{'name'} eq 'sequence';
	}
	my $prefix    = BIGSdb::Utils::get_random();
	my $filename  = "$prefix.txt";
	my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
	my @header    = @att_header;
	push @header, @$extended_attributes;
	my $databanks =
	  $self->{'datastore'}
	  ->run_query( 'SELECT DISTINCT databank FROM accession WHERE locus=?', $locus, { fetch => 'col_arrayref' } );
	push @header, sort @$databanks;

	if ( $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM sequence_refs WHERE locus=?)', $locus ) ) {
		push @header, 'PubMed';
	}
	if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
		push @header, 'flags';
	}
	my %header = map { $_ => 1 } @header;
	open( my $fh, '>:encoding(utf8)', $full_path ) || $logger->error("Can't open $full_path for writing");
	local $" = "\t";
	say $fh "@header";
	local $| = 1;
	say q(<div class="hideonload"><p>Please wait - calculating (do not refresh) ...</p>)
	  . q(<p><span class="wait_icon fas fa-sync-alt fa-spin fa-4x"></span></p></div>);
	$self->{'mod_perl_request'}->rflush if $ENV{'MOD_PERL'};

	foreach my $allele_id (@$list) {
		my $data = $self->{'datastore'}->run_query(
			'SELECT * FROM sequences WHERE (locus,allele_id)=(?,?)',
			[ $locus, $allele_id ],
			{ fetch => 'row_hashref', cache => 'SeqTableExport::create_table' }
		);
		my @results;
		foreach my $attribute (@$attributes) {
			next if $attribute->{'hide_public'};
			push @results, $data->{ $attribute->{'name'} } // '';
			push @results, length( $data->{'sequence'} ) if $attribute->{'name'} eq 'sequence';
		}
		my $ext_data = $self->{'datastore'}->run_query(
			'SELECT * FROM sequence_extended_attributes WHERE (locus,allele_id)=(?,?)',
			[ $locus, $allele_id ],
			{ fetch => 'all_hashref', key => 'field', cache => 'SeqTableExport::create_table_extended_attributes' }
		);
		foreach my $ext_attribute (@$extended_attributes) {
			push @results, $ext_data->{$ext_attribute}->{'value'} // '';
		}
		local $" = '; ';
		my @databanks = DATABANKS;
		foreach my $databank ( sort @databanks ) {
			if ( $header{$databank} ) {
				my $accessions = $self->{'datastore'}->run_query(
					'SELECT databank,databank_id FROM accession WHERE (locus,allele_id,databank)=(?,?,?)',
					[ $data->{'locus'}, $data->{'allele_id'}, $databank ],
					{ fetch => 'all_arrayref', slice => {} }
				);
				my @values;
				foreach my $accession (@$accessions) {
					push @values, $accession->{'databank_id'};
				}
				push @results, qq(@values);
			}
		}
		if ( $header{'PubMed'} ) {
			my $pmids = $self->{'datastore'}->run_query(
				'SELECT pubmed_id FROM sequence_refs WHERE (locus,allele_id)=(?,?)',
				[ $data->{'locus'}, $data->{'allele_id'} ],
				{
					fetch => 'col_arrayref'
				}
			);
			push @results, qq(@$pmids);
		}
		my $flags = $self->{'datastore'}->get_allele_flags( $locus, $allele_id );
		push @results, "@$flags";
		local $" = "\t";
		say $fh "@results";
	}
	close $fh;
	return $filename;
}
1;
