#Written by Keith Jolley
#Copyright (c) 2012, University of Oxford
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
package BIGSdb::CurateBatchSetAlleleFlagsPage;
use strict;
use warnings;
use parent qw(BIGSdb::CuratePage);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Page qw(ALLELE_FLAGS);

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<h1>Batch set allele flags</h1>\n";
	my $filename = $q->param('filename');
	if ( !$filename ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No query file passed.</p>\n";
		return;
	}
	my $qry_ref = $self->get_query_from_file($filename);
	if ( !$$qry_ref ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No query passed.</p>\n";
		return;
	}
	my $alleles    = $self->{'datastore'}->run_list_query_hashref($$qry_ref);
	my $loci       = $self->_get_loci_from_alleles($alleles);
	my $curator_id = $self->get_curator_id;
	if ( !$self->is_admin ) {
		foreach my $locus ( keys %$loci ) {
			if ( !$self->{'datastore'}->is_allowed_to_modify_locus_sequences( $locus, $curator_id ) ) {
				print "<div class=\"box\" id=\"statusbad\"><p>Your user account isn't allowed to modify $locus sequences.</p>\n";
				return;
			}
		}
	}
	if ( $q->param('set') ) {
		$self->_update($alleles);
		return;
	}
	$self->_print_interface($alleles);
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Batch set allele flags - $desc";
}

sub _print_interface {
	my ( $self, $alleles ) = @_;
	my $q = $self->{'cgi'};
	print "<div class=\"box\" id=\"queryform\">\n";
	print "<p>Select the flags to set - this will override all existing flags on these alleles. "
	  . "Clear all checkboxes to remove existing flags.</p>";
	print "<p>" . @$alleles . " allele" . ( @$alleles > 1 ? 's' : '' ) . " selected.</p>\n";
	print $q->start_form;
	print $q->checkbox_group( -name => 'flags', -values => [ALLELE_FLAGS], -linebreak => 'true' );
	print $q->submit( -name => 'set', -class => 'submit', -label => 'Set' );
	print $q->hidden($_) foreach qw (db page filename);
	print $q->end_form;
	print "</div>\n";
	return;
}

sub _update {
	my ( $self, $alleles ) = @_;
	my $sql_delete = $self->{'db'}->prepare("DELETE FROM allele_flags WHERE locus=? AND allele_id=?");
	my $sql_insert = $self->{'db'}->prepare("INSERT INTO allele_flags (locus,allele_id,flag,curator,datestamp) VALUES (?,?,?,?,?)");
	my $curator_id = $self->get_curator_id;
	eval {
		foreach my $allele (@$alleles)
		{
			$sql_delete->execute( $allele->{'locus'}, $allele->{'allele_id'} );
			foreach my $flag ( $self->{'cgi'}->param('flags') ) {
				$sql_insert->execute( $allele->{'locus'}, $allele->{'allele_id'}, $flag, $curator_id, 'now' )
				  if any { $flag eq $_ } ALLELE_FLAGS;
			}
		}
	};
	if ($@) {
		print "<div class=\"box\" id=\"statusbad\"><p>Update failed.</p></div>\n";
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		print "<div class=\"box\" id=\"resultsheader\"><p>Flags updated.</p>\n";
		print "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
		$self->{'db'}->commit;
	}
	return;
}

sub _get_loci_from_alleles {
	my ( $self, $alleles ) = @_;
	my %loci;
	$loci{ $_->{'locus'} } = 1 foreach @$alleles;
	return \%loci;
}
1;
