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
package BIGSdb::CurateDatabankScanPage;
use strict;
use warnings;
use parent qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $q    = $self->{'cgi'};
	my $accession = $q->param('accession');
	print "<h1>Scan EMBL/Ganbank record for loci</h1>";
	if ( !$self->can_modify_table('loci') ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to add records to the loci table.</p></div>\n";
		return;
	}
	print "<div class=\"box\" id=\"queryform\">\n";
	print "<p>This function allows you to scan an EMBL or Genbank (whole genome) file in order to create a batch upload file for setting up new loci.</p>\n";
	print $q->start_form;
	print "<table><tr><td>Please enter accession number: </td><td>";
	print $q->textfield( -name => 'accession', -size => 20 );
	print "</td><td>\n";
	print $q->submit( -label => 'Submit', -class => 'submit' );
	print "</td></tr>\n</table>\n";

	print $q->hidden($_) foreach qw(db page);
	print $q->end_form;
	print "</div>\n";
	if ( $accession ) {
		my $seq_db = new Bio::DB::GenBank;
		$seq_db->verbose(2);    #convert warn to exception
		my $seq_obj;
		try {
			$seq_obj = $seq_db->get_Seq_by_acc( $accession );
		}
		catch Bio::Root::Exception with {
			print "<div class=\"box\" id=\"statusbad\"><p>No data returned.</p></div>\n";
			my $err = shift;
			$logger->debug($err);
		};
		return if !$seq_obj;
		print "<div class=\"box\" id=\"resultstable\">\n";
		my $temp = BIGSdb::Utils::get_random();
		open (my $fh, '>' , "$self->{'config'}->{'tmp_dir'}/$temp.txt");
		print "<p><a href=\"/tmp/$temp.txt\">Download tab-delimited text</a> (suitable for editing in a spreadsheet or batch upload of loci). Please wait for page to finish loading.</p>\n";
		print "<table class=\"resultstable\">";
		my $td =1 ;
		my @cds;
		foreach ($seq_obj->get_SeqFeatures){
			push @cds, $_ if $_->primary_tag eq 'CDS';
		}
		my %att = (
			'accession' => $accession,
			'version' => $seq_obj->seq_version,
			'type' => $seq_obj->alphabet,
			'length' => $seq_obj->length,
			'description' => $seq_obj->description,
			'cds' => scalar @cds
		);
		my %abb = (
			'cds' => 'coding regions'
		);

		foreach (qw (accession version type length description cds)){
			if ($att{$_}){
				print "<tr class=\"td$td\"><th>". ($abb{$_} || $_) ."</th><td style=\"text-align:left\">$att{$_}</td></tr>\n";
				$td = $td == 1 ? 2 : 1;
			}
		}
		print "<tr><td colspan=\"2\">";
		print "<table style=\"width:100%\"><tr><th>Locus</th><th>Aliases</th><th>Product</th><th>Length</th></tr>\n";
		$"=', ';
		print $fh "id\tdata_type\tallele_id_format\tdescription\tlength\tlength_varies\tcoding_sequence\tmain_display\tisolate_display\tquery_field\tanalysis\treference_sequence\n";
		foreach my $cds (@cds){
			$"='; ';
			my @aliases;
			my $locus;
			foreach (qw (gene gene_synonym locus_tag old_locus_tag)){
				my @values =  $cds->has_tag($_) ? $cds->get_tag_values($_): ();
				foreach my $value (@values) {
					if ($locus){
						push @aliases, $value;
					} else {
						$locus = $value;
					}
				}
			}
			my %tags;
			foreach (qw (product note location primary_tag)){
				($tags{$_}) =  $cds->get_tag_values($_) if $cds->has_tag($_);
			}
			print "<tr class=\"td$td\"><td>$locus</td><td>@aliases</td><td>$tags{'product'} ";
			print "<a class=\"tooltip\" title=\"$locus - $tags{'note'}\">&nbsp;<i>i</i>&nbsp;</a>" if $tags{'note'};
			print "</td><td>".($cds->length)."</td></tr>";
			$td = $td == 1 ? 2 : 1;
			my %type_lookup = (
				'dna' => 'DNA',
				'rna' => 'RNA',
				'protein' => 'peptide'
			);
			print $fh "$locus\t$type_lookup{$att{'type'}}\tinteger\t$tags{'product'}\t". ($cds->length)."\tTRUE\tTRUE\tFALSE\tallele only\tTRUE\tTRUE\t".($cds->seq->seq)."\n";
		}
		close $fh;
		print "</table>\n";
		print "</td></tr>\n";
		print "</table>";
		print "</div>\n"
	}
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Scan EMBL/Genbank record - $desc";
}
1;
