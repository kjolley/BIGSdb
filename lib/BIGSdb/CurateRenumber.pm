#Written by Keith Jolley
#Copyright (c) 2010-2012, University of Oxford
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
use parent qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery jQuery.tablesort);
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
	return "Renumber locus genome positions - $desc";
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if (!($self->{'permissions'}->{'modify_loci'} || $self->is_admin)){
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account does not have permission to modify loci.</p></div>\n";
		return;
	}
	print "<h1>Renumber locus genome positions based on tagged sequences</h1>";
	my $seqbin_id = $q->param('seqbin_id');
	if (!$seqbin_id || !BIGSdb::Utils::is_int($seqbin_id)){
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid sequence bin id.</p></div>\n";
		return;
	}
	print "<div class=\"box\" id=\"resultstable\">\n";

	print "<p>You have selected to renumber the genome positions set in the locus table based on the tagged sequences in sequence id#$seqbin_id.</p>";
	my $sql = $self->{'db'}->prepare("SELECT locus,start_pos FROM allele_sequences WHERE seqbin_id=? ORDER BY start_pos");
	eval { $sql->execute($seqbin_id) };
	$logger->error($@) if $@;
	if ($q->param('renumber')){
		if ($q->param('blank')){
			eval {
				$self->{'db'}->do("UPDATE loci SET genome_position = null");
			};
			if ($@){
				$logger->error("Can't remove genome positions");
				print "<p class=\"statusbad\">Can't remove existing genome positions</p>\n";
				$self->{'db'}->rollback;
				return;
			} 
		}
		my $update_sql = $self->{'db'}->prepare("UPDATE loci SET genome_position=?,datestamp='today' WHERE id=?");
		while (my ($locus,$pos) = $sql->fetchrow_array){
			eval { $update_sql->execute($pos,$locus) };
			if ($@){
				$logger->error("Can't update genome positions $@");
				$self->{'db'}->rollback;
				print "<p class=\"statusbad\">Can't update genome positions</p>\n";
				return;
			}
		}
		$self->{'db'}->commit;
		print "<p class=\"statusgood\">Done!</p>\n";
		print "</div>\n";
		return;
	}
	print $q->start_form;
	print $q->checkbox(-name=>'blank',-label=>'Remove positions for loci not tagged in this sequence');
	print "<p>\n";
	print $q->submit(-name=>'renumber', -label=>'Renumber', -class=>'submit');
	print "</p>\n";
	print $q->hidden($_) foreach qw (db page seqbin_id);
	print $q->end_form;
	print "<p>The following designations will be made:</p>";

	print "<table class=\"tablesorter\" id=\"sortTable\">\n";
	print "<thead><tr><th>Locus</th><th>Existing genome position<th>New genome position</th></tr></thead>\n<tbody>\n";
	my $td = 1;
	my $existing_sql = $self->{'db'}->prepare("SELECT genome_position FROM loci WHERE id=?");
	while (my ($locus,$pos) = $sql->fetchrow_array){
		eval { $existing_sql->execute($locus) };
		$logger->error($@) if $@;
		my ($existing) = $existing_sql->fetchrow_array;
		print "<tr class=\"td$td\"><td>$locus</td>";
		print defined $existing ? "<td>$existing</td>" : '<td></td>';
		print "<td>$pos</td></tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	print "</tbody></table>\n";
	print "</div>\n";
}

1;