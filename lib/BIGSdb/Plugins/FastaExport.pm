#FastaExport.pm - Plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2012-2013, University of Oxford
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
package BIGSdb::Plugins::FastaExport;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use BIGSdb::Page qw(LOCUS_PATTERN);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

sub get_attributes {
	my %att = (
		name        => 'FASTA Export',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Export FASTA file of sequences following an allele attribute query',
		category    => 'Export',
		menutext    => 'Export FASTA',
		buttontext  => 'FASTA',
		module      => 'FastaExport',
		version     => '1.0.0',
		dbtype      => 'sequences',
		seqdb_type  => 'sequences',
		input       => 'query',
		section     => 'postquery',
		order       => 10
	);
	return \%att;
}

sub _get_id_list {
	my ( $self, $query_file ) = @_;
	if ($query_file) {
		my $qry_ref = $self->get_query($query_file);
		return if ref $qry_ref ne 'SCALAR';
		$$qry_ref =~ s/\*/allele_id/;
		my $ids = $self->{'datastore'}->run_list_query($$qry_ref);
		return $ids;
	}
	return \@;;
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say "<h1>Export FASTA file</h1>";
	my $locus = $q->param('locus');
	$locus =~ s/^cn_//;
	if ( !$locus ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No locus passed.</p></div>\n";
		$logger->error("No locus passed.");
		return;
	}
	my $query_file = $q->param('query_file');
	my $list       = $self->_get_id_list($query_file);
	if ( !@$list ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No sequences available from query.</p></div>\n";
		$logger->error("No sequences available.");
		return;
	}
	my $sql       = $self->{'db'}->prepare("SELECT allele_id,sequence FROM sequences WHERE locus=? AND allele_id=?");
	my $temp      = BIGSdb::Utils::get_random();
	my $filename  = "$temp.fas";
	my $full_path = $self->{'config'}->{'tmp_dir'} . "/$filename";
	open( my $fh, '>', $full_path ) or $logger->error("Can't open $full_path for writing.");
	foreach my $allele_id (@$list) {
		eval { $sql->execute( $locus, $allele_id ) };
		$logger->error($@) if $@;
		my $seq_data = $sql->fetchrow_hashref;
		say $fh ">$locus\_$seq_data->{'allele_id'}";
		my $seq = BIGSdb::Utils::break_line( $seq_data->{'sequence'}, 60 );
		say $fh $seq;
	}
	close $fh;
	if ( !-e $full_path ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Sequence file could not be generated.</p></div>\n";
		$logger->error("Sequence file can not be generated");
		return;
	}
	say "<div class=\"box\" id=\"resultsheader\">";
	say "<p>Sequences have been exported in FASTA format:</p>";
	my $cleaned_name = $self->clean_locus($locus);
	say "<ul><li>Locus: $cleaned_name</li>";
	my $plural = @$list == 1 ? '' : 's';
	say "<li>" . (@$list) . " sequence$plural</li>";
	say "<li><a href=\"/tmp/$filename\">Download</a></li>";
	say "</ul>";
	say "</div>";
	return;
}
1;
