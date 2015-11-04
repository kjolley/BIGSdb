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
package BIGSdb::CurateRenumber;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery jQuery.tablesort);
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $js = <<"JS";
\$(document).ready(function() 
    { 
        \$("#sortTable").tablesorter({widgets:['zebra']}); 
    } 
); 	
JS
	return $js;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return qq(Renumber locus genome positions - $desc);
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( !( $self->{'permissions'}->{'modify_loci'} || $self->is_admin ) ) {
		say q(<div class="box" id="statusbad"><p>Your user account does not )
		  . q(have permission to modify loci.</p></div>);
		return;
	}
	say q(<h1>Renumber locus genome positions based on tagged sequences</h1>);
	my $seqbin_id = $q->param('seqbin_id');
	if ( !$seqbin_id || !BIGSdb::Utils::is_int($seqbin_id) ) {
		say q(<div class="box" id="statusbad"><p>Invalid sequence bin id.</p></div>);
		return;
	}
	if ( $q->param('renumber') ) {
		if ( $q->param('blank') ) {
			eval { $self->{'db'}->do('UPDATE loci SET genome_position=null') };
			if ($@) {
				$logger->error($@);
				say q(<p class="statusbad">Cannot remove existing genome positions</p>);
				$self->{'db'}->rollback;
				return;
			}
		}
		my $update_sql = $self->{'db'}->prepare(q(UPDATE loci SET genome_position=?,datestamp='now' WHERE id=?));
		my $locus_starts =
		  $self->{'datastore'}
		  ->run_query( 'SELECT locus,start_pos FROM allele_sequences WHERE seqbin_id=? ORDER BY start_pos',
			$seqbin_id, { fetch => 'all_arrayref', cache => 'CurateRenumber::get_locus_starts' } );
		foreach my $data (@$locus_starts) {
			my ( $locus, $pos ) = @$data;
			eval { $update_sql->execute( $pos, $locus ) };
			if ($@) {
				$logger->error($@);
				$self->{'db'}->rollback;
				say q(<p class="statusbad">Cannot update genome positions</p>);
				return;
			}
		}
		$self->{'db'}->commit;
		say q(<div class="box" id="resultsheader">Database updated!</p></div>);
		return;
	}
	say q(<div class="box" id="resultstable">);
	say q(<p>You have selected to renumber the genome positions set in the locus table based )
	  . qq(on the tagged sequences in sequence id#$seqbin_id.</p>);
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Option</legend>);
	say $q->checkbox( -name => 'blank', -label => 'Remove positions for loci not tagged in this sequence' );
	say q(</fieldset>);
	$self->print_action_fieldset( { submit_label => 'Renumber', no_reset => 1 } );
	say $q->hidden($_) foreach qw (db page seqbin_id);
	say $q->hidden( renumber => 1 );
	say $q->end_form;
	say q(<p>The following designations will be made:</p>);
	say q(<div class="scrollable">);
	say q(<table class="tablesorter" id="sortTable">);
	say q(<thead><tr><th>Locus</th><th>Existing genome position<th>New genome position</th></tr></thead><tbody>);
	my $td = 1;
	my $locus_starts =
	  $self->{'datastore'}
	  ->run_query( 'SELECT locus,start_pos FROM allele_sequences WHERE seqbin_id=? ORDER BY start_pos',
		$seqbin_id, { fetch => 'all_arrayref', cache => 'CurateRenumber::get_locus_starts' } );

	foreach my $data (@$locus_starts) {
		my ( $locus, $pos ) = @$data;
		my $existing =
		  $self->{'datastore'}->run_query( 'SELECT genome_position FROM loci WHERE id=?', $locus,
			{ cache => 'CurateRenumber:pos_exists' } );
		print qq(<tr class="td$td"><td>$locus</td>);
		print defined $existing ? qq(<td>$existing</td>) : q(<td></td>);
		say qq(<td>$pos</td></tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</tbody></table>);
	say q(</div></div>);
	return;
}
1;
