#Written by Keith Jolley
#Copyright (c) 2010-2013, University of Oxford
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
package BIGSdb::CurateTagUpdatePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage BIGSdb::ExtractedSequencePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Page qw(SEQ_FLAGS);
use List::MoreUtils qw(none);

sub print_content {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $seqbin_id  = $q->param('seqbin_id');
	my $locus      = $q->param('locus');
	my $orig_start = $q->param('start_pos');
	my $orig_end   = $q->param('end_pos');
	say "<h1>Update sequence tag</h1>";
	if ( !defined $seqbin_id || !BIGSdb::Utils::is_int($seqbin_id) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Seqbin_id must be an integer.</p></div>";
		return;
	} elsif ( !defined $locus || !$self->{'datastore'}->is_locus($locus) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Invalid locus specified.</p></div>";
		return;
	} elsif ( !defined $q->param('start_pos') || !BIGSdb::Utils::is_int( $q->param('start_pos') ) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Start position must be an integer.</p></div>";
		return;
	}
	my $cleaned_locus = $self->clean_locus($locus);
	my $seq_exists = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM sequence_bin WHERE id=?", $seqbin_id )->[0];
	if ( !$seq_exists ) {
		say "<div class=\"box\" id=\"statusbad\"><p>There is no sequence with sequence bin id#$seqbin_id.</p></div>";
		return;
	}
	if ( $q->param('Update display') || $q->param('Submit') ) {
		if ( !defined $q->param('new_start') || !BIGSdb::Utils::is_int( $q->param('new_start') ) ) {
			say "<div class=\"box\" id=\"statusbad\"><p>The start position must be an integer.  Resetting to initial values.</p></div>";
			$q->param( 'Update display', 0 );
			$q->param( 'Submit',         0 );
		} elsif ( !defined $q->param('new_end') || !BIGSdb::Utils::is_int( $q->param('new_end') ) ) {
			say "<div class=\"box\" id=\"statusbad\"><p>The end position must be an integer.  Resetting to initial values.</p></div>";
			$q->param( 'Update display', 0 );
			$q->param( 'Submit',         0 );
		} elsif ( $q->param('new_start') && $q->param('new_start') && $q->param('new_start') > $q->param('new_end') ) {
			say "<div class=\"box\" id=\"statusbad\"><p>The end position must be greater than the start.  Resetting to initial "
			  . "values.</p></div>";
			$q->param( 'Update display', 0 );
			$q->param( 'Submit',         0 );
		}
	}
	my $tag;
	my ( $start, $end, $reverse, $complete );
	if ( $q->param('Update display') || $q->param('Submit') ) {
		$start    = $q->param('new_start');
		$end      = $q->param('new_end');
		$reverse  = $q->param('new_reverse');
		$complete = $q->param('new_complete');
	} else {
		$start = $q->param('start_pos');
		$end   = $q->param('end_pos');
		$tag =
		  $self->{'datastore'}
		  ->run_simple_query_hashref( "SELECT * FROM allele_sequences WHERE seqbin_id=? AND locus=? AND start_pos=? AND end_pos=?",
			$seqbin_id, $locus, $start, $end );
		if ( !ref $tag ) {
			say "<div class=\"box\" id=\"statusbad\"><p>There is no tag set with the parameters passed.</p></div>";
			return;
		}
		$q->param( 'new_start', $tag->{'start_pos'} );
		$q->param( 'end_pos',   $end );
		$q->param( 'new_end',   $tag->{'end_pos'} );
		$reverse = $tag->{'reverse'};
		$q->param( 'new_reverse', $reverse );
		$complete = $tag->{'complete'};
		$q->param( 'new_complete', $complete );
	}
	if ( $q->param('Submit') ) {
		my @actions;
		my $reverse_flag  = $reverse  ? 'true' : 'false';
		my $complete_flag = $complete ? 'true' : 'false';
		my $curator_id    = $self->get_curator_id;
		if ( $start != $q->param('start_pos') || $end != $q->param('end_pos') ) {
			push @actions, "DELETE FROM allele_sequences WHERE seqbin_id=$seqbin_id AND locus='$locus' AND start_pos=$orig_start "
			  . "AND end_pos=$orig_end";
			push @actions, "INSERT INTO allele_sequences (seqbin_id,locus,start_pos,end_pos,reverse,complete,curator,datestamp) "
			  . "VALUES ($seqbin_id,'$locus',$start,$end,$reverse_flag,$complete_flag,$curator_id,'now')";
		} else {
			push @actions,
			    "UPDATE allele_sequences SET start_pos=$start, end_pos=$end, reverse=$reverse_flag, complete=$complete_flag, "
			  . "curator=$curator_id, datestamp='today' WHERE seqbin_id='$seqbin_id' AND locus='$locus' AND start_pos=$orig_start AND "
			  . "end_pos=$orig_end";
		}
		my $existing_flags =
		  $self->{'datastore'}
		  ->run_list_query( "SELECT flag FROM sequence_flags WHERE seqbin_id=? AND locus=? AND start_pos=? AND end_pos=? ORDER BY flag",
			$seqbin_id, $locus, $start, $end );
		my @new_flags = $q->param('flags');
		foreach my $new_flag (@new_flags) {
			if ( !@$existing_flags || none { $new_flag eq $_ } @$existing_flags ) {
				push @actions, "INSERT INTO sequence_flags (seqbin_id,locus,start_pos,end_pos,flag,datestamp,curator) VALUES "
				  . "($seqbin_id,'$locus',$start,$end,'$new_flag','now',$curator_id)";
			}
		}
		foreach my $existing_flag (@$existing_flags) {
			if ( !@new_flags || none { $existing_flag eq $_ } @new_flags ) {
				push @actions, "DELETE FROM sequence_flags WHERE seqbin_id=$seqbin_id AND locus='$locus' AND start_pos=$start "
				  . "AND end_pos=$end AND flag='$existing_flag'";
			}
		}
		local $" = '<br />';
		eval {
			foreach my $qry (@actions)
			{
				$self->{'db'}->do($qry);
			}
		};
		if ($@) {
			my $error = $@;
			if ( $error =~ /duplicate/ ) {
				say "<div class=\"box\" id=\"statusbad\"><p>Update failed - a tag already exists for this locus between postions $start "
				  . "and $end on sequence seqbin#$seqbin_id</p><p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">"
				  . "Back to main page</a></p></div>";
				$logger->error($error);
			} else {
				say "<div class=\"box\" id=\"statusbad\"><p>Update failed - transaction cancelled - no records have been touched.</p><p>"
				  . "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back to main page</a></p></div>";
				$logger->error($error);
			}
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
			say "<div class=\"box\" id=\"resultsheader\"><p>Sequence tag updated!</p><p><a href=\"$self->{'system'}->{'script_name'}?"
			  . "db=$self->{'instance'}\">Back to main page</a></p></div>";
			local $" = '<br />';
			my $isolate_id_ref = $self->{'datastore'}->run_simple_query( "SELECT isolate_id FROM sequence_bin WHERE id=?", $seqbin_id );
			if ( ref $isolate_id_ref eq 'ARRAY' ) {
				$self->update_history( $isolate_id_ref->[0], "$locus: sequenece tag updated. Seqbin id: $seqbin_id; $start-$end" );
			}
			$q->param( 'start_pos', $q->param('new_start') );
			$q->param( 'end_pos',   $q->param('new_end') );
			$orig_start = $q->param('new_start');
			$orig_end   = $q->param('new_end');
		}
	}
	say "<div class=\"box\" id=\"queryform\">";
	say $q->start_form;
	say "<table><tr><td>";
	say "<table>";
	say "<tr><td style=\"text-align:right\">seqbin id: </td><td><b>$seqbin_id</b></td></tr>";
	say "<tr><td style=\"text-align:right\">locus: </td><td><b>$cleaned_locus</b></td></tr>";
	my $curator_name = $self->get_curator_name;
	say "<tr><td style=\"text-align:right\">curator: </td><td><b>$curator_name</b></td></tr>";
	my $datestamp = $self->get_datestamp;
	say "<tr><td style=\"text-align:right\">curator: </td><td><b>$datestamp</b></td></tr>";
	say "</table>";
	say "<table><tr>";
	say "<td>Start: </td><td>";
	say $q->textfield( -name => 'new_start', default => $start, -size => 10 );
	say "</td><td>End: </td><td>";
	say $q->textfield( -name => 'new_end', default => $end, -size => 10 );
	say "</td><td>";
	say $q->checkbox( -name => 'new_reverse', -label => 'Reverse', -value => 1, -checked => $reverse );
	say "</td><td>";
	say $q->checkbox( -name => 'new_complete', -label => 'Complete', -value => 1, -checked => $complete );
	say "</td></tr></table>";
	say "</td><td>";
	my $flags = $self->{'datastore'}->run_list_query(
		"SELECT flag FROM sequence_flags WHERE seqbin_id=? AND locus=? AND start_pos=? AND end_pos=? ORDER BY flag",
		$seqbin_id, $locus, $q->param('start_pos'),
		$q->param('end_pos')
	);
	my $i = 1;
	say "Flags: <br />";
	say $q->scrolling_list( -name => 'flags', -id => 'flags', -values => [SEQ_FLAGS], -default => $flags, -size => 5, -multiple => 'true' );
	say "</td><td>";
	say "<span class=\"comment\"> Select/deselect multiple flags by holding down<br />Shift or Ctrl while clicking with the mouse</span>";
	say "</td></tr>";
	say "<tr><td>";
	say "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagUpdate&amp;seqbin_id=$seqbin_id&amp;"
	  . "locus=$locus&amp;start_pos=$orig_start&amp;end_pos=$orig_end\" class=\"resetbutton\">Reset</a>";
	say "</td><td style=\"text-align:right\">";
	say $q->submit( -name => 'Update display', -class => 'button' );
	say "</td><td>";
	say $q->submit( -name => 'Submit', -class => 'submit' );
	say "</td></tr>";
	say "</table>";
	say $q->hidden($_) foreach qw(db page seqbin_id locus start_pos end_pos reverse);
	say $q->end_form;
	say "</div>";
	say "<div class=\"box\" id=\"sequence\">";
	my $flanking = $self->{'prefs'}->{'flanking'} || 100;
	my $length = abs( $end - $start + 1 );
	say "<p class=\"seq\" style=\"text-align:left\">";
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $translate  = $locus_info->{'coding_sequence'} ? 1 : 0;
	my $orf        = $locus_info->{'orf'} || 1;
	my $display    = $self->format_seqbin_sequence(
		{ seqbin_id => $seqbin_id, reverse => $reverse, start => $start, end => $end, translate => $translate, orf => $orf } );
	say $display->{'seq'};
	say "</p>";

	if ($translate) {
		my @stops = @{ $display->{'internal_stop'} };
		if (@stops) {
			local $" = ', ';
			my $plural = @stops == 1 ? '' : 's';
			print "<span class=\"highlight\">Internal stop codon$plural at position$plural: @stops (numbering includes upstream "
			  . "flanking sequence).</span>";
		}
		say "<pre class=\"sixpack\">";
		say $display->{'sixpack'};
		say "</pre>";
	}
	say "</div>";
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Sequence tag update - $desc";
}
1;
