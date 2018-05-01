#FastaExport.pm - Plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2012-2018, University of Oxford
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
		version     => '1.0.2',
		dbtype      => 'sequences',
		seqdb_type  => 'sequences',
		input       => 'query',
		section     => 'postquery',
		order       => 10
	);
	return \%att;
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Export FASTA file</h1>);
	my $locus = $q->param('locus');
	$locus =~ s/^cn_//x;
	if ( !$locus ) {
		$self->print_bad_status( { message => q(No locus passed.) } );
		$logger->error('No locus passed.');
		return;
	}
	my $query_file = $q->param('query_file');
	my $list_file  = $q->param('list_file');
	my $list       = $self->get_allele_id_list( $query_file, $list_file );
	if ( !@$list ) {
		$self->print_bad_status( { message => q(No sequences available from query.) } );
		$logger->error('No sequences available.');
		return;
	}
	my $temp      = BIGSdb::Utils::get_random();
	my $filename  = "$temp.fas";
	my $full_path = $self->{'config'}->{'tmp_dir'} . "/$filename";
	open( my $fh, '>', $full_path ) or $logger->error("Cannot open $full_path for writing.");
	foreach my $allele_id (@$list) {
		my $seq_data = $self->{'datastore'}->run_query(
			'SELECT allele_id,sequence FROM sequences WHERE (locus,allele_id)=(?,?)',
			[ $locus, $allele_id ],
			{ fetch => 'row_hashref', cache => 'FastaExport::run' }
		);
		say $fh ">$locus\_$seq_data->{'allele_id'}";
		my $seq = BIGSdb::Utils::break_line( $seq_data->{'sequence'}, 60 );
		say $fh $seq;
	}
	close $fh;
	if ( !-e $full_path ) {
		$self->print_bad_status( { message => q(Sequence file could not be generated.) } );
		$logger->error('Sequence file cannot be generated');
		return;
	}
	say q(<div class="box" id="resultspanel">);
	say q(<p>Sequences are available in FASTA format:</p>);
	my $cleaned_name = $self->clean_locus($locus);
	say qq(<ul><li>Locus: $cleaned_name</li>);
	my $plural = @$list == 1 ? '' : 's';
	say q(<li>) . (@$list) . qq( sequence$plural</li>);
	say qq(<li><a href="/tmp/$filename">Download</a></li>);
	say q(</ul></div>);
	return;
}
1;
