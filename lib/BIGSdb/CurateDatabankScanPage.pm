#Written by Keith Jolley
#Copyright (c) 2010-2013, University of Oxford
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
package BIGSdb::CurateDatabankScanPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $accession = $q->param('accession');
	say "<h1>Scan EMBL/Ganbank record for loci</h1>";
	if ( !$self->can_modify_table('loci') ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to add records to the loci table.</p></div>";
		return;
	}
	say "<div class=\"box\" id=\"queryform\">";
	say "<p>This function allows you to scan an EMBL or Genbank (whole genome) file in order to create a batch upload file for "
	  . "setting up new loci.</p>";
	say $q->start_form;
	say "<fieldset style=\"float:left\"><legend>Please enter accession number</legend>";
	say "<label for=\"accession\">Accession: </label>";
	say $q->textfield( -name => 'accession', -id => 'accession', -size => 20, -required => 'required' );
	say "</fieldset>";
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach qw(db page);
	say $q->end_form;
	say "</div>\n";

	if ($accession) {
		my $seq_db = Bio::DB::GenBank->new;
		$seq_db->verbose(2);    #convert warn to exception
		my $seq_obj;
		try {
			$seq_obj = $seq_db->get_Seq_by_acc($accession);
		}
		catch Bio::Root::Exception with {
			say "<div class=\"box\" id=\"statusbad\"><p>No data returned.</p></div>";
			my $err = shift;
			$logger->debug($err);
		};
		return if !$seq_obj;
		say "<div class=\"box\" id=\"resultstable\">";
		my $temp = BIGSdb::Utils::get_random();
		open( my $fh, '>', "$self->{'config'}->{'tmp_dir'}/$temp.txt" );
		say "<p><a href=\"/tmp/$temp.txt\">Download tab-delimited text</a> (suitable for editing in a spreadsheet or batch upload of "
		  . "loci). Please wait for page to finish loading.</p>";
		say "<h2>Annotation information</h2>";
		say "<dl class=\"data\">";
		my $td = 1;
		my @cds;

		foreach ( $seq_obj->get_SeqFeatures ) {
			push @cds, $_ if $_->primary_tag eq 'CDS';
		}
		my %att = (
			'accession'   => $accession,
			'version'     => $seq_obj->seq_version,
			'type'        => $seq_obj->alphabet,
			'length'      => $seq_obj->length,
			'description' => $seq_obj->description,
			'cds'         => scalar @cds
		);
		my %abb = ( 'cds' => 'coding regions' );
		foreach (qw (accession version type length description cds)) {
			if ( $att{$_} ) {
				say "<dt>" . ( $abb{$_} || $_ ) . "</dt><dd>$att{$_}</dd>";
				$td = $td == 1 ? 2 : 1;
			}
		}
		say "</dl>";
		say "<h2>Coding sequences</h2>";
		say "<table class=\"resultstable\"><tr><th>Locus</th><th>Aliases</th><th>Product</th><th>Length</th></tr>";
		say $fh "id\tdata_type\tallele_id_format\tdescription\tlength\tlength_varies\tcoding_sequence\tflag_table\tmain_display\t"
		  . "isolate_display\tquery_field\tanalysis\treference_sequence";
		foreach my $cds (@cds) {
			local $" = '; ';
			my @aliases;
			my $locus;
			foreach (qw (gene gene_synonym locus_tag old_locus_tag)) {
				my @values = $cds->has_tag($_) ? $cds->get_tag_values($_) : ();
				foreach my $value (@values) {
					if ($locus) {
						push @aliases, $value;
					} else {
						$locus = $value;
					}
				}
			}
			my %tags;
			foreach (qw (product note location primary_tag)) {
				( $tags{$_} ) = $cds->get_tag_values($_) if $cds->has_tag($_);
			}
			$tags{'product'} //= '';
			print "<tr class=\"td$td\"><td>$locus</td><td>@aliases</td><td>$tags{'product'} ";
			print "<a class=\"tooltip\" title=\"$locus - $tags{'note'}\">&nbsp;<i>i</i>&nbsp;</a>" if $tags{'note'};
			say "</td><td>" . ( $cds->length ) . "</td></tr>";
			$td = $td == 1 ? 2 : 1;
			my %type_lookup = ( 'dna' => 'DNA', 'rna' => 'RNA', 'protein' => 'peptide' );
			say $fh "$locus\t$type_lookup{$att{'type'}}\tinteger\t$tags{'product'}\t"
			  . ( $cds->length )
			  . "\tTRUE\tTRUE\tTRUE\tFALSE\tallele only\tTRUE\tTRUE\t"
			  . ( $cds->seq->seq );
		}
		close $fh;
		say "</table>";
		say "</div>";
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Scan EMBL/Genbank record - $desc";
}
1;
