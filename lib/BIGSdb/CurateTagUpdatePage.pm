#Written by Keith Jolley
#Copyright (c) 2010-2014, University of Oxford
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
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $id     = $q->param('id');
	say "<h1>Update sequence tag</h1>";
	if ( !BIGSdb::Utils::is_int($id) ) {
		say qq(<div class="box" id="statusbad"><p>Tag id must be an integer.</p></div>);
		return;
	}
	my $existing_tag = $self->{'datastore'}->run_simple_query_hashref( "SELECT * FROM allele_sequences WHERE id=?", $id );
	if ( !$existing_tag ) {
		say qq(<div class="box" id="statusbad"><p>Tag does not exist.</p></div>);
		return;
	}
	my ( $seqbin_id, $locus, $orig_start, $orig_end ) = @{$existing_tag}{qw(seqbin_id locus start_pos end_pos)};
	my $cleaned_locus = $self->clean_locus($locus);
	if ( $q->param('update') || $q->param('submit') ) {
		if ( !defined $q->param('new_start') || !BIGSdb::Utils::is_int( $q->param('new_start') ) ) {
			say qq(<div class="box" id="statusbad"><p>The start position must be an integer.  Resetting to initial values.</p></div>);
			$q->param( update => 0 );
			$q->param( submit => 0 );
		} elsif ( !defined $q->param('new_end') || !BIGSdb::Utils::is_int( $q->param('new_end') ) ) {
			say qq(<div class="box" id="statusbad"><p>The end position must be an integer.  Resetting to initial values.</p></div>);
			$q->param( update => 0 );
			$q->param( submit => 0 );
		} elsif ( $q->param('new_start') && $q->param('new_start') && $q->param('new_start') > $q->param('new_end') ) {
			say qq(<div class="box" id="statusbad"><p>The end position must be greater than the start.  Resetting to initial )
			  . "values.</p></div>";
			$q->param( update => 0 );
			$q->param( submit => 0 );
		}
	}
	my ( $start, $end, $reverse, $complete );
	if ( $q->param('update') || $q->param('submit') ) {
		$start    = $q->param('new_start');
		$end      = $q->param('new_end');
		$reverse  = $q->param('new_reverse');
		$complete = $q->param('new_complete');
	} else {
		$start = $existing_tag->{'start_pos'};
		$end   = $existing_tag->{'end_pos'};
		$q->param( new_start => $existing_tag->{'start_pos'} );
		$q->param( new_end   => $existing_tag->{'end_pos'} );
		$reverse = $existing_tag->{'reverse'};
		$q->param( new_reverse => $reverse );
		$complete = $existing_tag->{'complete'};
		$q->param( new_complete => $complete );
	}
	if ( $q->param('submit') ) {
		my @actions;
		my $reverse_flag  = $reverse  ? 'true' : 'false';
		my $complete_flag = $complete ? 'true' : 'false';
		my $curator_id    = $self->get_curator_id;
		( my $clean_locus = $locus ) =~ s/'/\\'/g;
		push @actions,
		  {
			statement => "UPDATE allele_sequences SET (start_pos,end_pos,reverse,complete,curator,datestamp) = "
			  . "(?,?,?,?,?,?) WHERE id=?",
			arguments => [ $start, $end, $reverse_flag, $complete_flag, $curator_id, 'now', $id ]
		  };
		my $existing_flags = $self->{'datastore'}->get_sequence_flags($id);
		my @new_flags      = $q->param('flags');

		foreach my $new_flag (@new_flags) {
			if ( !@$existing_flags || none { $new_flag eq $_ } @$existing_flags ) {
				push @actions,
				  {
					statement => "INSERT INTO sequence_flags (id,flag,datestamp,curator) VALUES (?,?,?,?)",
					arguments => [ $id, $new_flag, 'now', $curator_id ]
				  };
			}
		}
		foreach my $existing_flag (@$existing_flags) {
			if ( !@new_flags || none { $existing_flag eq $_ } @new_flags ) {
				push @actions, { statement => "DELETE FROM sequence_flags WHERE id=? AND flag=?", arguments => [ $id, $existing_flag ] };
			}
		}
		local $" = '<br />';
		eval {
			foreach my $action (@actions)
			{
				$self->{'db'}->do( $action->{'statement'}, undef, @{ $action->{'arguments'} } );
			}
		};
		if ($@) {
			my $error = $@;
			if ( $error =~ /duplicate/ ) {
				say qq(<div class="box" id="statusbad"><p>Update failed - a tag already exists for this locus between postions $start )
				  . qq(and $end on sequence seqbin#$seqbin_id</p><p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">)
				  . "Back to main page</a></p></div>";
			} else {
				say qq(<div class="box" id="statusbad"><p>Update failed - transaction cancelled - no records have been touched.</p>)
				  . qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>);
				$logger->error($error);
			}
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
			say qq(<div class="box" id="resultsheader"><p>Sequence tag updated!</p><p><a href="$self->{'system'}->{'script_name'}?)
			  . qq(db=$self->{'instance'}">Back to main page</a></p></div>);
			local $" = '<br />';
			my $isolate_id_ref = $self->{'datastore'}->run_simple_query( "SELECT isolate_id FROM sequence_bin WHERE id=?", $seqbin_id );
			if ( ref $isolate_id_ref eq 'ARRAY' ) {
				$self->update_history( $isolate_id_ref->[0], "$locus: sequence tag updated. Seqbin id: $seqbin_id; $start-$end" );
			}
			$q->param( 'start_pos' => $q->param('new_start') );
			$q->param( 'end_pos'   => $q->param('new_end') );
			$orig_start = $q->param('new_start');
			$orig_end   = $q->param('new_end');
		}
	}
	say qq(<div class="box" id="queryform"><div class="scrollable">);
	say $q->start_form;
	say qq(<fieldset style="float:left"><legend>Tag</legend>);
	say qq(<dl class="data"><dt>seqbin id</dt><dd>$seqbin_id</dd>);
	say "<dt>locus</dt><dd>$cleaned_locus</dd>";
	my $curator_name = $self->get_curator_name;
	say "<dt>curator</dt><dd>$curator_name</dd>";
	my $datestamp = $self->get_datestamp;
	say "<dt>datestamp</dt><dd>$datestamp</dd>";
	say "<dt>start</dt><dd>";
	say $q->textfield( -name => 'new_start', default => $start, -size => 10 );
	say "</dd><dt>end</dt><dd>";
	say $q->textfield( -name => 'new_end', default => $end, -size => 10 );
	say "</dd><dt>reverse</dt><dd>";
	say $q->checkbox( -name => 'new_reverse', -label => '', -value => 1, -checked => $reverse );
	say "</dd><dt>complete</dt><dd>";
	say $q->checkbox( -name => 'new_complete', -label => '', -value => 1, -checked => $complete );
	say "</dd></dl></fieldset>";
	my $flags = $self->{'datastore'}->get_sequence_flags($id);
	say qq(<fieldset style="float:left"><legend>Flags</legend>);
	say $q->scrolling_list( -name => 'flags', -id => 'flags', -values => [SEQ_FLAGS], -default => $flags, -size => 5, -multiple => 'true' );
	say qq(<p class="comment">Select/deselect multiple flags<br />by holding down Shift or Ctrl<br />while clicking with the mouse.</p>);
	say "</fieldset>";
	say qq(<fieldset style="float:left"><legend>Display</legend>);
	say $q->submit(
		-name  => 'update',
		-label => 'Update display',
		-class => 'submitbutton ui-button ui-widget ui-state-default ui-corner-all'
	);
	say "</fieldset>";
	$self->print_action_fieldset( { id => $id } );
	say $q->hidden($_) foreach qw(db page id seqbin_id locus start_pos end_pos reverse);
	say $q->end_form;
	say "</div></div>";
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
