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
package BIGSdb::DownloadSeqbinPage;
use strict;
use warnings;
use base qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{'type'} = 'text';
}

sub print_content {
	my ($self) = @_;
	my $isolate_id = $self->{'cgi'}->param('isolate_id');
	if ( !$isolate_id ) {
		print "No isolate id passed.\n";
		return;
	} elsif ( !BIGSdb::Utils::is_int($isolate_id) ) {
		print "Isolate id must be an integer.\n";
		return;
	}
	$| = 1;
	my $sql = $self->{'db'}->prepare("SELECT id,original_designation,sequence FROM sequence_bin WHERE isolate_id=? ORDER BY id");
	eval { $sql->execute($isolate_id) };
	if ($@) {
		$logger->error($@);
		print "Can't retrieve sequences.\n";
		return;
	}
	my $no_seqs = 1;
	while ( my ( $id, $orig, $seq ) = $sql->fetchrow_array ) {
		print ">$id";
		print "|$orig" if $orig;
		print "\n";
		my $seq_ref = BIGSdb::Utils::break_line( \$seq, 60 );
		print "$$seq_ref\n";
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
		$no_seqs = 0;
	}
	if ($no_seqs) {
		print "No sequences deposited for isolate id#$isolate_id.\n";
	}
}

1;
