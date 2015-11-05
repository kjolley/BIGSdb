#Written by Keith Jolley
#Copyright (c) 2010-2015, University of Oxford
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
	  BIGSdb::Utils::is_int( $q->param('isolate_id') )
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
	my $data =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id,original_designation,sequence FROM sequence_bin WHERE isolate_id=? ORDER BY id',
		$isolate_id, { fetch => 'all_arrayref' } );
	foreach my $contig (@$data) {
		my ( $id, $orig, $seq ) = @$contig;
		print ">$id";
		print "|$orig" if $orig;
		print "\n";
		my $seq_ref = BIGSdb::Utils::break_line( \$seq, 60 );
		say $$seq_ref;
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
	}
	if ( !@$data ) {
		say qq(No sequences deposited for isolate id#$isolate_id.);
	}
	return;
}
1;
