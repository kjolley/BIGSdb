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
	my $output_file  = $self->{'options'}->{'output_html'};
	$self->_update_status_file($status_file,'running');
	foreach my $isolate_id (@$isolate_list) {
		my $remote_contigs = $self->{'datastore'}->run_query(
			'SELECT r.seqbin_id,r.uri FROM remote_contigs r INNER JOIN sequence_bin s ON r.seqbin_id=s.id AND '
			  . 's.isolate_id=? WHERE length IS NULL OR checksum IS NULL ORDER BY r.seqbin_id',
			$isolate_id,
			{ fetch => 'all_arrayref', slice => {} }
		);
		my $total_processed = 0;
		my $total_length    = 0;
		foreach my $contig (@$remote_contigs) {
			say $contig->{'uri'} if !$self->{'options'}->{'quiet'};
			my $contig_record = $self->{'remoteContigManager'}->get_remote_contig( $contig->{'uri'} );
			if ( $contig_record->{'sequence'} ) {
				my $length   = length( $contig_record->{'sequence'} );
				my $checksum = Digest::MD5::md5_hex( $contig_record->{'sequence'} );
				eval {
					$self->{'db'}->do( 'UPDATE remote_contigs SET (length,checksum)=(?,?) WHERE seqbin_id=?',
						undef, $length, $checksum, $contig->{'seqbin_id'} );
					$self->{'db'}->do(
						'UPDATE sequence_bin SET (method,original_designation,comments)=(?,?,?) WHERE id=?',
						undef,
						$contig_record->{'method'},
						$contig_record->{'original_designation'},
						$contig_record->{'comments'},
						$contig->{'seqbin_id'}
					);
				};
				if ($@) {
					$self->{'db'}->rollback;
					$self->{'logger'}->error($@);
				} else {
					$self->{'db'}->commit;
				}
				$total_length += $length;
				$total_processed++;
				$self->_write_results($output_file,$total_processed,$total_length);
			}
		}
	}
	$self->_update_status_file($status_file,'complete');
	return;
}

sub _update_status_file {
	my ( $self, $status_file, $status ) = @_;
	return if !$status_file;
	open( my $fh, '>', $status_file )
	  || $self->{'logger'}->error("Cannot touch $status_file");
	say $fh qq({"status":"$status"});
	close $fh;
	return;
}

sub _write_results {
	my ( $self, $file, $contigs, $length ) = @_;
	return if !$file;
	my $buffer = qq(<dl class="data"><dt>Contigs processed</dt><dd>$contigs</dd>);
	my $commify_length = BIGSdb::Utils::commify($length);
	$buffer .= qq(<dt>Total length</dt><dd>$commify_length bp</dd></dl>);
	$self->_write( $file, $buffer );
	return;
}

sub _write {
	my ( $self, $file, $text, $append ) = @_;
	return if !$file;
	my $open_type = $append ? '>>' : '>';
	open( my $fh, $open_type, $file ) || die "Cannot write to $file.\n";
	say $fh $text;
	close $fh;
	return;
}
1;
