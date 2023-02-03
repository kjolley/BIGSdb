#Written by Keith Jolley
#Copyright (c) 2010-2023, University of Oxford
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
package BIGSdb::DownloadSeqbinPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	$self->{'attachment'} =
	  BIGSdb::Utils::is_int( scalar $q->param('isolate_id') )
	  ? ( 'id-' . $q->param('isolate_id') . '.fas' )
	  : 'isolate.fas';
	$self->{'type'} = 'text';
	return;
}

sub print_content {
	my ($self) = @_;
	my $isolate_id = $self->{'cgi'}->param('isolate_id');
	if ( !$isolate_id ) {
		say q(No isolate id passed.);
		return;
	} elsif ( !BIGSdb::Utils::is_int($isolate_id) ) {
		say q(Isolate id must be an integer.);
		return;
	}
	local $| = 1;
	my $data = $self->{'datastore'}->run_query(
		'SELECT s.id,s.original_designation,s.sequence,s.remote_contig FROM sequence_bin s '
		  . "JOIN $self->{'system'}->{'view'} v ON s.isolate_id=v.id WHERE isolate_id=? ORDER BY id",
		$isolate_id,
		{ fetch => 'all_arrayref' }
	);
	my $remote_contig_records = $self->{'datastore'}->run_query(
		'SELECT r.seqbin_id,r.uri FROM remote_contigs r JOIN sequence_bin s ON r.seqbin_id = s.id AND '
		  . "s.isolate_id=? JOIN $self->{'system'}->{'view'} v ON s.isolate_id=v.id",
		$isolate_id,
		{ fetch => 'all_hashref', key => 'seqbin_id' }
	);
	my $remote_uri_list = [];
	push @$remote_uri_list, $remote_contig_records->{$_}->{'uri'} foreach keys %$remote_contig_records;
	my $remote_contig_seqs;
	eval { $remote_contig_seqs = $self->{'contigManager'}->get_remote_contigs_by_list($remote_uri_list); };
	$logger->error($@) if $@;

	foreach my $contig ( sort { length( $b->[2] ) <=> length( $a->[2] ) } @$data ) {
		my ( $id, $orig, $seq ) = @$contig;
		$seq = $remote_contig_seqs->{ $remote_contig_records->{$id}->{'uri'} } if !$seq;
		print ">$id";
		print " $orig" if $orig;
		print "\n";
		my $seq_ref = BIGSdb::Utils::break_line( \$seq, 60 );
		eval { say $$seq_ref};    #If client drops connection this can result in Apache error.
		if ($@) {
			$logger->error($@) if $@ !~ /Broken\spipe/x && $@ !~ /connection\sabort/x;
			last;
		}
		if ( $ENV{'MOD_PERL'} ) {
			return if $self->{'mod_perl_request'}->connection->aborted;
			$self->{'mod_perl_request'}->rflush;
		}
	}
	if ( !@$data ) {
		say qq(No sequence available for isolate id#$isolate_id.);
	}
	return;
}
1;
