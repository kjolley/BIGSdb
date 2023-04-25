#Written by Keith Jolley
#Copyright (c) 2012-2020, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
use 5.010;
use parent qw(BIGSdb::CuratePage);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Constants qw(ALLELE_FLAGS);

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Batch set allele flags</h1>);
	my $query_file = $q->param('query_file');
	if ( !$query_file ) {
		$self->print_bad_status( { message => q(No query file passed.) } );
		return;
	}
	my $qry = $self->get_query_from_temp_file($query_file);
	if ( !$qry ) {
		$self->print_bad_status( { message => q(No query passed.) } );
		return;
	}
	if ( $q->param('list_file') ) {
		$self->{'datastore'}->create_temp_list_table( 'text', $q->param('list_file') );
	}
	my $alleles    = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	my $loci       = $self->_get_loci_from_alleles($alleles);
	my $curator_id = $self->get_curator_id;
	if ( !$self->is_admin ) {
		foreach my $locus ( keys %$loci ) {
			if ( !$self->{'datastore'}->is_allowed_to_modify_locus_sequences( $locus, $curator_id ) ) {
				$self->print_bad_status(
					{
						message => qq(Your user account isn't allowed to modify $locus sequences.)
					}
				);
				return;
			}
		}
	}
	if ( $q->param('submit') ) {
		$self->_update($alleles);
		return;
	}
	$self->_print_interface($alleles);
	return;
}

sub get_title {
	my ($self) = @_;
	return q(Batch set allele flags);
}

sub _print_interface {
	my ( $self, $alleles ) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="queryform">);
	say q(<p>Select the flags to set - this will override all existing flags on these alleles. )
	  . q(Clear all checkboxes to remove existing flags.</p>);
	my $count = @$alleles;
	my $plural = @$alleles > 1 ? q(s) : q();
	say qq(<p>$count allele$plural selected.</p>);
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Flags</legend>);
	say $q->checkbox_group( -name => 'flags', -values => [ALLELE_FLAGS], -linebreak => 'true' );
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Set' } );
	say $q->hidden($_) foreach qw (db page query_file list_file);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _update {
	my ( $self, $alleles ) = @_;
	my $sql_delete = $self->{'db'}->prepare('DELETE FROM allele_flags WHERE locus=? AND allele_id=?');
	my $sql_insert =
	  $self->{'db'}->prepare('INSERT INTO allele_flags (locus,allele_id,flag,curator,datestamp) VALUES (?,?,?,?,?)');
	my $curator_id = $self->get_curator_id;
	eval {
		foreach my $allele (@$alleles) {
			$sql_delete->execute( $allele->{'locus'}, $allele->{'allele_id'} );
			foreach my $flag ( $self->{'cgi'}->param('flags') ) {
				$sql_insert->execute( $allele->{'locus'}, $allele->{'allele_id'}, $flag, $curator_id, 'now' )
				  if any { $flag eq $_ } ALLELE_FLAGS;
			}
		}
	};
	if ($@) {
		$self->print_bad_status( { message => 'Update failed!' } );
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->print_good_status( { message => 'Flags updated.' } );
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
