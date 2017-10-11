#!/usr/bin/perl
#Download and check lengths/checksum remote contigs.
#
#Written by Keith Jolley
#Copyright (c) 2017, University of Oxford
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
package BIGSdb::Offline::ProcessRemoteContigs;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Offline::Script);
use LWP::Simple;
use JSON;
use Digest::MD5;

sub run_script {
	my ($self) = @_;
	die "No connection to database (check logs).\n" if !defined $self->{'db'};
	die "This script can only be run against an isolate database.\n"
	  if ( $self->{'system'}->{'dbtype'} // '' ) ne 'isolates';
	my $isolates     = $self->get_isolates_with_linked_seqs;
	my $isolate_list = $self->filter_and_sort_isolates($isolates);
	my $status_file  = $self->{'options'}->{'status_file'};
	foreach my $isolate_id (@$isolate_list) {
		my $remote_contigs = $self->{'datastore'}->run_query(
			'SELECT r.seqbin_id,r.uri FROM remote_contigs r INNER JOIN sequence_bin s ON r.seqbin_id=s.id AND '
			  . 's.isolate_id=? WHERE length IS NULL OR checksum IS NULL ORDER BY r.seqbin_id',
			$isolate_id,
			{ fetch => 'all_arrayref', slice => {} }
		);
		foreach my $contig (@$remote_contigs) {
			say $contig->{'uri'};
			my $contig_record = $self->{'remoteContigManager'}->get_remote_contig($contig->{'uri'});
			use Data::Dumper;
			$self->{'logger'}->error(Dumper $contig_record);
		}
	}
	return;
}

sub _append {
	my ( $self, $text ) = @_;
	my $output_file = $self->{'options'}->{'output_file'};
	return if !$output_file;
	open( my $fh, '>>', $output_file ) || die "Cannot write to $output_file.\n";
	say $fh $text;
	close $fh;
	return;
}
1;
