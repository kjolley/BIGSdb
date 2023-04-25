#Written by Keith Jolley
#Copyright (c) 2010-2020, University of Oxford
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
package BIGSdb::CurateDatabankScanPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use BIGSdb::Constants qw(:interface);
use Log::Log4perl qw(get_logger);
use Try::Tiny;
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (tooltips jQuery noCache);
	$self->set_level1_breadcrumbs;
	return;
}

sub print_content {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $accession = $q->param('accession');
	say q(<h1>Scan EMBL/Genbank record for loci</h1>);
	if ( !$self->can_modify_table('loci') ) {
		$self->print_bad_status(
			{
				message => q(Your user account is not allowed to add records to the loci table.)
			}
		);
		return;
	}
	$self->_print_interface;
	if ($accession) {
		$self->_print_results($accession);
	}
	return;
}

sub _print_interface {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="queryform">);
	say q(<p>This function allows you to scan an EMBL or Genbank (whole genome) )
	  . q(file in order to create a batch upload file for setting up new loci.</p>);
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Please enter accession number</legend>);
	say q(<label for="accession">Accession: </label>);
	say $q->textfield( -name => 'accession', -id => 'accession', -size => 20, -required => 'required' );
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Primary identifier</legend>);
	my %labels = ( gene => 'gene name', locus_tag => 'locus tag' );
	say $q->radio_group(
		-name      => 'identifier',
		-values    => [qw(locus_tag gene)],
		-labels    => \%labels,
		-linebreak => 'true'
	);
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach qw(db page);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _print_results {
	my ( $self, $accession ) = @_;

	#Setting retrievaltype prevents a fork which can result in error message being displayed twice
	#when run under cgi-bin.
	my $seq_db = Bio::DB::GenBank->new( -retrievaltype => 'tempfile' );
	$seq_db->verbose(2);    #convert warn to exception
	my $seq_obj;
	try {
		$seq_obj = $seq_db->get_Seq_by_acc($accession);
	}
	catch {
		my $err = shift;
		$logger->debug($err);
	};
	if ( !$seq_obj ) {
		$self->print_bad_status( { message => q(No data returned.) } );
		return;
	}
	my $prefix      = BIGSdb::Utils::get_random();
	my $table_file  = "$self->{'config'}->{'tmp_dir'}/$prefix.txt";
	my $allele_file = "$self->{'config'}->{'tmp_dir'}/def_$prefix.txt";
	say q(<div class="box" id="resultspanel" style="display:none"><div class="scrollable">);
	my ( $text, $excel ) = ( TEXT_FILE, EXCEL_FILE );
	say qq(<div class="file_output"><h2>Download table</h2><a href="/tmp/$prefix.txt">)
	  . qq(<span style="float:left" title="Tab-delimited text format.">$text</span></a>)
	  . qq(<a href="/tmp/$prefix.xlsx">)
	  . qq(<span style="float:left;margin-right:1em" title="Excel format.">$excel<span></a>)
	  . q(<div style="width:90%;margin-top:1em">Suitable for batch upload of loci.</div></div>);
	say qq(<div class="file_output"><h2>Download alleles</h2><a href="/tmp/def_$prefix.txt">)
	  . qq(<span style="float:left" title="Tab-delimited text format.">$text</span></a>)
	  . qq(<a href="/tmp/def_$prefix.xlsx">)
	  . qq(<span style="float:left;margin-right:1em" title="Excel format.">$excel<span></a>)
	  . q(<div style="width:90%;margin-top:1em">Suitable for defining the first allele in the )
	  . q(seqdef database.</div></div>);
	say q(</div></div>);
	say q(<div class="box" id="resultstable">);
	say q(<h2>Annotation information</h2>);
	my $list = [];
	my @cds;

	foreach ( $seq_obj->get_SeqFeatures ) {
		push @cds, $_ if $_->primary_tag eq 'CDS';
	}
	my %att = (
		accession   => $accession,
		version     => $seq_obj->seq_version,
		type        => $seq_obj->alphabet,
		length      => $seq_obj->length,
		description => $seq_obj->description,
		cds         => scalar @cds
	);
	my %abb = ( cds => 'coding regions' );
	foreach my $field (qw (accession version type length description cds)) {
		if ( $att{$field} ) {
			my $field_name = $abb{$field} || $field;
			push @$list, { title => $field_name, data => $att{$field} };
		}
	}
	say $self->get_list_block($list);
	if ( !@cds ) {
		say q(</div>);
		$self->print_bad_status( { message => 'Accession contains no sequences' } );
		say q(<script>failed=1;</script>);
		return;
	}
	say q(<h2>Coding sequences</h2>);
	say q(<table class="resultstable"><tr><th>Locus</th><th>Aliases</th><th>Product</th><th>Length</th></tr>);
	open( my $fh, '>', $table_file ) || $logger->error("Cannot open $table_file for writing");
	say $fh qq(id\taliases\tdata_type\tallele_id_format\tdescription\tlength\tlength_varies\tcoding_sequence\t)
	  . qq(main_display\tisolate_display\tquery_field\tanalysis\treference_sequence);
	open( my $fh_allele, '>', $allele_file ) || $logger->error("Cannot open $allele_file for writing");
	say $fh_allele qq(locus\tallele_id\tsequence\tstatus);
	local $| = 1;
	my $td = 1;
	my @locus_error;
	my $table_buffer = q();

	foreach my $cds (@cds) {
		local $" = q(; );
		my @aliases;
		my $locus;
		my @tags =
		  $self->{'cgi'}->param('identifier') eq 'locus_tag'
		  ? qw (locus_tag old_locus_tag gene gene_synonym)
		  : qw (gene gene_synonym locus_tag old_locus_tag);
		foreach (@tags) {
			my @values = $cds->has_tag($_) ? $cds->get_tag_values($_) : ();
			foreach my $value (@values) {
				if ($locus) {
					push @aliases, $value;
				} else {
					$locus = $value;
				}
			}
		}
		$locus //= 'undefined';
		my %tags;
		foreach (qw (product note location primary_tag)) {
			( $tags{$_} ) = $cds->get_tag_values($_) if $cds->has_tag($_);
		}
		$tags{'product'} //= '';
		$table_buffer .= qq(<tr class="td$td"><td>$locus</td><td>@aliases</td><td>$tags{'product'} );
		$table_buffer .= $self->get_tooltip(qq($locus - $tags{'note'})) if $tags{'note'};
		my $length = $cds->length;
		$table_buffer .= qq(</td><td>$length</td></tr>);
		$td = $td == 1 ? 2 : 1;
		my %type_lookup = ( dna => 'DNA', rna => 'RNA', protein => 'peptide' );
		try {
			my $sequence = $cds->seq->seq;
			local $" = q(;);
			say $fh qq($locus\t@aliases\t$type_lookup{$att{'type'}}\tinteger\t$tags{'product'}\t$length\tTRUE\tTRUE\t)
			  . qq(FALSE\tallele only\tTRUE\tTRUE\t$sequence);
			say $fh_allele qq($locus\t1\t$sequence\tunchecked);
		}
		catch {
			my $err = shift;
			$logger->debug($err);
			push @locus_error, $locus;
		};
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
	}
	print $fh_allele "\n";    #Seems to be needed for Excel conversion.
	close $fh;
	close $fh_allele;
	$table_buffer .= q(</table></div>);
	if (@locus_error) {
		local $" = q (, );
		my $plural       = @locus_error == 1 ? q()   : q(s);
		my $locus_plural = @locus_error == 1 ? q(us) : q(i);
		say qq(<p>Sequence$plural for the following loc$locus_plural could not be extracted: @locus_error.</p>);
	}
	say $table_buffer if $table_buffer;
	BIGSdb::Utils::text2excel( $table_file,  { max_width => 30 } );
	BIGSdb::Utils::text2excel( $allele_file, { max_width => 30 } );
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $buffer = << "END";
var failed = 0;
\$(function () {
	if (!failed){
	 \$("#resultspanel").css('display','block');
	}
});
END
	return $buffer;
}

sub get_title {
	return q(Scan EMBL/Genbank record);
}
1;
