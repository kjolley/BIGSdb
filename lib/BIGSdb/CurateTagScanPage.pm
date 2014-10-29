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
package BIGSdb::CurateTagScanPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage BIGSdb::TreeViewPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use List::MoreUtils 0.28 qw(uniq any none);
use Apache2::Connection ();
use Error qw(:try);
use BIGSdb::Page qw(SEQ_METHODS SEQ_FLAGS LOCUS_PATTERN);
use BIGSdb::Offline::Scan;
##DEFAUT SCAN PARAMETERS#############
my $MIN_IDENTITY       = 70;
my $MIN_ALIGNMENT      = 50;
my $WORD_SIZE          = 20;
my $PARTIAL_MATCHES    = 1;
my $LIMIT_MATCHES      = 200;
my $LIMIT_TIME         = 5;
my $PARTIAL_WHEN_EXACT = 'off';
my $TBLASTX            = 'off';
my $HUNT               = 'off';
my $RESCAN_ALLELES     = 'off';
my $RESCAN_SEQS        = 'off';
my $MARK_MISSING       = 'off';

sub get_javascript {
	my ($self) = @_;
	my %check_values = ( on => 'true', off => 'false' );
	my $buffer;
	if ( !$self->{'cgi'}->param('tag') ) {
		$buffer .= << "END";
\$(function () {	
		\$("html, body").animate({ scrollTop: \$(document).height()-\$(window).height() });	
});			
END
	}
	$buffer .= << "END";
function listbox_selectall(listID, isSelect) {
	\$("#" + listID + " option").prop("selected",isSelect);
}

function use_defaults() {
	\$("#identity").val($MIN_IDENTITY);
	\$("#alignment").val($MIN_ALIGNMENT);
	\$("#word_size").val($WORD_SIZE);
	\$("#partial_matches").val($PARTIAL_MATCHES);
	\$("#limit_matches").val($LIMIT_MATCHES);
	\$("#limit_time").val($LIMIT_TIME);
	\$("#tblastx").prop(\"checked\",$check_values{$TBLASTX});
	\$("#hunt").prop(\"checked\",$check_values{$HUNT});
	\$("#partial_when_exact").prop(\"checked\",$check_values{$PARTIAL_WHEN_EXACT});
	\$("#rescan_alleles").prop(\"checked\",$check_values{$RESCAN_ALLELES});
	\$("#rescan_seqs").prop(\"checked\",$check_values{$RESCAN_SEQS});
	\$("#mark_missing").prop(\"checked\",$check_values{$MARK_MISSING});
}
	
END
	$buffer .= $self->get_tree_javascript( { checkboxes => 1, check_schemes => 1 } );
	return $buffer;
}

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/curator_guide.html#automated-web-based-sequence-tagging";
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (tooltips jQuery jQuery.jstree noCache);
	my $q = $self->{'cgi'};
	if ( $q->param('submit') || $q->param('results') ) {
		$self->{'scan_job'} = $q->param('scan') || BIGSdb::Utils::get_random();
		my $scan_job = $self->{'scan_job'} =~ /^(BIGSdb_[0-9_]+)$/ ? $1 : undef;
		my $status = $self->_read_status($scan_job);
		return if $status->{'server_busy'};
		if ( !$status->{'stop_time'} ) {
			if ( $status->{'start_time'} ) {
				if ( !$q->param('results') ) {
					$self->{'refresh'} = 5;
				} else {
					my $elapsed = time - $status->{'start_time'};
					if    ( $elapsed < 120 )  { $self->{'refresh'} = 5 }
					elsif ( $elapsed < 300 )  { $self->{'refresh'} = 10 }
					elsif ( $elapsed < 600 )  { $self->{'refresh'} = 30 }
					elsif ( $elapsed < 3600 ) { $self->{'refresh'} = 60 }
					else                      { $self->{'refresh'} = 300 }
				}
			} else {
				$self->{'refresh'} = 5;
			}
			$self->{'refresh_page'} =
			  "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagScan&amp;scan=$scan_job&amp;results=1";
		}
		if ( $q->param('stop') ) {
			my $status_file = "$self->{'config'}->{'secure_tmp_dir'}/$scan_job\_status.txt";
			open( my $fh, '>>', $status_file ) || $logger->error("Can't open $status_file for appending");
			say $fh "request_stop:1";
			close $fh;
			$self->{'refresh'} = 1;
		}
	}
	if ( $q->param('parameters') ) {
		my $scan_job = $q->param('parameters');
		my $filename = "$self->{'config'}->{'secure_tmp_dir'}/$scan_job\_parameters";
		if ( -e $filename ) {
			open( my $fh, '<', $filename ) || $logger->error("Can't open $filename for reading");
			my $temp_q = CGI->new( \*$fh );    # Temp CGI object to read in parameters
			close $fh;
			my $params = $temp_q->Vars;
			foreach my $key ( keys %$params ) {
				next if any { $key eq $_ } qw (submit);
				$q->param( $key, $temp_q->param($key) );
			}
		}
		my @ids = $q->param('isolate_id');
	}
	return;
}

sub _print_interface {
	my ( $self, $ids, $labels ) = @_;
	my $q = $self->{'cgi'};
	if ( !@$ids ) {
		say "<div class=\"box\" id=\"statusbad\"><p>There are no sequences in the sequence bin.</p></div>";
		return;
	} elsif ( !$self->can_modify_table('allele_sequences') ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to tag sequences.</p></div>";
		return;
	}
	say "<div class=\"box\" id=\"queryform\">";
	say "<p>Please select the required isolate ids and loci for sequence scanning - use ctrl or shift to make multiple selections. In "
	  . "addition to selecting individual loci, you can choose to include all loci defined in schemes by selecting the appropriate scheme "
	  . "description. By default, loci are only scanned for an isolate when no allele designation has been made or sequence tagged. You "
	  . "can choose to rescan loci with existing designations or tags by selecting the appropriate options.</p>";
	my ( $loci, $locus_labels ) = $self->get_field_selection_list( { loci => 1, query_pref => 0, sort_labels => 1 } );
	my $guid = $self->get_guid;
	my $general_prefs;
	if ($guid) {
		$general_prefs = $self->{'prefstore'}->get_all_general_prefs( $guid, $self->{'system'}->{'db'} );
	}
	if ( $q->param('datatype') && $q->param('list_file') ) {
		$self->{'datastore'}->create_temp_list_table( $q->param('datatype'), $q->param('list_file') );
	}
	my $query_file = $q->param('query_file');
	my $query      = $self->get_query_from_temp_file($query_file);
	my $selected_ids;
	if ( $q->param('isolate_id') ) {
		my @ids = $q->param('isolate_id');
		$selected_ids = \@ids;
	} elsif ( defined $query ) {
		$selected_ids = $self->_get_ids($query);
	} else {
		$selected_ids = [];
	}
	say $q->start_form;
	say "<div class=\"scrollable\"><fieldset>\n<legend>Isolates</legend>";
	say $self->popup_menu(
		-name     => 'isolate_id',
		-id       => 'isolate_id',
		-values   => $ids,
		-labels   => $labels,
		-size     => 11,
		-multiple => 'true',
		-default  => $selected_ids,
		-required => 'required'
	);
	say "<div style=\"text-align:center\"><input type=\"button\" onclick='listbox_selectall(\"isolate_id\",true)' value=\"All\" "
	  . "style=\"margin-top:1em\" class=\"smallbutton\" />";
	say "<input type=\"button\" onclick='listbox_selectall(\"isolate_id\",false)' value=\"None\" style=\"margin-top:1em\" "
	  . "class=\"smallbutton\" /></div>";
	say "</fieldset>";
	say "<fieldset>\n<legend>Loci</legend>";
	say $self->popup_menu( -name => 'locus', -id => 'locus', -values => $loci, -labels => $locus_labels, -size => 11, -multiple => 'true' );
	say "<div style=\"text-align:center\"><input type=\"button\" onclick='listbox_selectall(\"locus\",true)' value=\"All\" "
	  . "style=\"margin-top:1em\" class=\"smallbutton\" />";
	say "<input type=\"button\" onclick='listbox_selectall(\"locus\",false)' value=\"None\" style=\"margin-top:1em\" "
	  . "class=\"smallbutton\" /></div>";
	say "</fieldset>";
	say "<fieldset>\n<legend>Schemes</legend>";
	say "<noscript><p class=\"highlight\">Enable Javascript to select schemes.</p></noscript>";
	say "<div id=\"tree\" class=\"tree\" style=\"height:180px; width:20em\">";
	say $self->get_tree( undef, { no_link_out => 1, select_schemes => 1 } );
	say "</div>";
	say "</fieldset>";
	$self->_print_parameter_fieldset($general_prefs);

	#Only show repetitive loci fields if PCR or probe locus links have been set
	my $pcr_links   = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM pcr_locus")->[0];
	my $probe_links = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM probe_locus")->[0];
	if ( $pcr_links + $probe_links ) {
		say "<fieldset>\n<legend>Repetitive loci</legend>";
		say "<ul>";
		if ($pcr_links) {
			say "<li>";
			say $q->checkbox( -name => 'pcr_filter', -label => 'Filter by PCR', -checked => 'checked' );
			say " <a class=\"tooltip\" title=\"Filter by PCR - Loci can be defined by a simulated PCR reaction(s) so that only regions of "
			  . "the genome predicted to be amplified will be recognised in the scan. De-selecting this option will ignore this filter "
			  . "and the whole sequence bin will be scanned instead.  Partial matches will also be returned (up to the number set in the "
			  . "parameters) even if exact matches are found.  De-selecting this option will be necessary if the gene in question is "
			  . "incomplete due to being located at the end of a contig since it can not then be bounded by PCR primers.\">"
			  . "&nbsp;<i>i</i>&nbsp;</a>";
			say "</li>\n<li><label for=\"alter_pcr_mismatches\" class=\"parameter\">&Delta; PCR mismatch:</label>";
			say $q->popup_menu(
				-name    => 'alter_pcr_mismatches',
				-id      => 'alter_pcr_mismatches',
				-values  => [qw (-3 -2 -1 0 +1 +2 +3)],
				-default => 0
			);
			say " <a class=\"tooltip\" title=\"Change primer mismatch - Each defined PCR reaction will have a parameter specifying the "
			  . "allowed number of mismatches per primer. You can increase or decrease this value here, altering the stringency of the "
			  . "reaction.\">&nbsp;<i>i</i>&nbsp;</a>";
			say "</li>";
		}
		if ($probe_links) {
			say "<li>";
			say $q->checkbox( -name => 'probe_filter', -label => 'Filter by probe', -checked => 'checked' );
			say " <a class=\"tooltip\" title=\"Filter by probe - Loci can be defined by a simulated hybridization reaction(s) so that "
			  . "only regions of the genome predicted to be within a set distance of a hybridization sequence will be recognised in the "
			  . "scan. De-selecting this option will ignore this filter and the whole sequence bin will be scanned instead.  Partial "
			  . "matches will also be returned (up to the number set in the parameters) even if exact matches are found.\">"
			  . "&nbsp;<i>i</i>&nbsp;</a></li>";
			say "<li><label for=\"alter_probe_mismatches\" class=\"parameter\">&Delta; Probe mismatch:</label>";
			say $q->popup_menu(
				-name    => 'alter_probe_mismatches',
				-id      => 'alter_probe_mismatches',
				-values  => [qw (-3 -2 -1 0 +1 +2 +3)],
				-default => 0
			);
			say " <a class=\"tooltip\" title=\"Change probe mismatch - Each hybridization reaction will have a parameter specifying the "
			  . "allowed number of mismatches. You can increase or decrease this value here, altering the stringency of the reaction.\">"
			  . "&nbsp;<i>i</i>&nbsp;</a>";
			say "</li>";
		}
		say "</ul>\n</fieldset>";
	}
	say "<fieldset>\n<legend>Restrict included sequences by</legend>";
	say "<ul>";
	my $buffer = $self->get_sequence_method_filter( { class => 'parameter' } );
	say "<li>$buffer</li>" if $buffer;
	$buffer = $self->get_project_filter( { class => 'parameter' } );
	say "<li>$buffer</li>" if $buffer;
	$buffer = $self->get_experiment_filter( { class => 'parameter' } );
	say "<li>$buffer</li>" if $buffer;
	say "</ul></fieldset>";
	say "</div>";
	$self->print_action_fieldset( { submit_label => 'Scan' } );
	say $q->hidden($_) foreach qw (page db);
	say $q->end_form;
	say "</div>";
	return;
}

sub _print_parameter_fieldset {
	my ( $self, $general_prefs ) = @_;
	my $q = $self->{'cgi'};
	say "<fieldset>\n<legend>Parameters</legend>"
	  . "<input type=\"button\" class=\"smallbutton legendbutton\" value=\"Defaults\" onclick=\"use_defaults()\" />"
	  . "<ul><li><label for =\"identity\" class=\"parameter\">Min % identity:</label>";
	say $q->popup_menu(
		-name    => 'identity',
		-id      => 'identity',
		-values  => [ 50 .. 100 ],
		-default => $general_prefs->{'scan_identity'} || $MIN_IDENTITY
	);
	say " <a class=\"tooltip\" title=\"Minimum % identity - Match required for partial matching.\">&nbsp;<i>i</i>&nbsp;</a></li>"
	  . "<li><label for =\"alignment\" class=\"parameter\">Min % alignment:</label>";
	say $q->popup_menu(
		-name    => 'alignment',
		-id      => 'alignment',
		-values  => [ 30 .. 100 ],
		-default => $general_prefs->{'scan_alignment'} || $MIN_ALIGNMENT
	);
	say " <a class=\"tooltip\" title=\"Minimum % alignment - Percentage of allele sequence length required to be aligned for "
	  . "partial matching.\">&nbsp;<i>i</i>&nbsp;</a></li>"
	  . "<li><label for =\"word_size\" class=\"parameter\">BLASTN word size:</label>";
	say $q->popup_menu(
		-name    => 'word_size',
		-id      => 'word_size',
		-values  => [ 7 .. 30 ],
		-default => $general_prefs->{'scan_word_size'} || $WORD_SIZE
	);
	say " <a class=\"tooltip\" title=\"BLASTN word size - This is the length of an exact match required to initiate an extension. "
	  . "Larger values increase speed at the expense of sensitivity.\">&nbsp;<i>i</i>&nbsp;</a></li>"
	  . "<li><label for =\"partial_matches\" class=\"parameter\">Return up to:</label>";
	say $q->popup_menu(
		-name    => 'partial_matches',
		-id      => 'partial_matches',
		-values  => [ 1 .. 10 ],
		-default => $general_prefs->{'scan_partial_matches'} || $PARTIAL_MATCHES
	);
	say " partial match(es)</li>" . "<li><label for =\"limit_matches\" class=\"parameter\">Stop after:</label>";
	say $q->popup_menu(
		-name    => 'limit_matches',
		-id      => 'limit_matches',
		-values  => [qw(10 20 30 40 50 100 200 500 1000 2000 5000 10000 20000)],
		-default => $general_prefs->{'scan_limit_matches'} || $LIMIT_MATCHES
	);
	say " new matches "
	  . " <a class=\"tooltip\" title=\"Stop after matching - Limit the number of previously undesignated matches. You may wish to "
	  . "terminate the search after finding a set number of new matches.  You will be able to tag any sequences found and next time "
	  . "these won't be searched (by default) so this enables you to tag in batches.\">&nbsp;<i>i</i>&nbsp;</a></li>"
	  . "<li><label for =\"limit_time\" class=\"parameter\">Stop after:</label>";
	say $q->popup_menu(
		-name    => 'limit_time',
		-id      => 'limit_time',
		-values  => [qw(1 2 5 10 15 30 60 120 180 240 300)],
		-default => $general_prefs->{'scan_limit_time'} || $LIMIT_TIME
	);
	say " minute(s) "
	  . " <a class=\"tooltip\" title=\"Stop after time - Searches against lots of loci or for multiple isolates may take a long time. "
	  . "You may wish to terminate the search after a set time.  You will be able to tag any sequences found and next time these "
	  . "won't be searched (by default) so this enables you to tag in batches.\">&nbsp;<i>i</i>&nbsp;</a></li>";

	if ( $self->{'system'}->{'tblastx_tagging'} && $self->{'system'}->{'tblastx_tagging'} eq 'yes' ) {
		say "<li><span class=\"warning\">";
		say $q->checkbox(
			-name    => 'tblastx',
			-id      => 'tblastx',
			-label   => 'Use TBLASTX',
			-checked => ( $general_prefs->{'scan_tblastx'} && $general_prefs->{'scan_tblastx'} eq 'on' ) ? 'checked' : ''
		);
		say " <a class=\"tooltip\" title=\"TBLASTX - Compares the six-frame translation of your nucleotide query against "
		  . "the six-frame translation of the sequences in the sequence bin.  This can be VERY SLOW (a few minutes for "
		  . "each comparison. Use with caution.<br /><br />Partial matches may be indicated even when an exact match "
		  . "is found if the matching allele contains a partial codon at one of the ends.  Identical matches will be indicated "
		  . "if the translated sequences match even if the nucleotide sequences don't. For this reason, allele designation "
		  . "tagging is disabled for TBLASTX matching.\">&nbsp;<i>i</i>&nbsp;</a>"
		  . "</span></li>";
	}
	say "<li>";
	say $q->checkbox(
		-name    => 'hunt',
		-id      => 'hunt',
		-label   => 'Hunt for nearby start and stop codons',
		-checked => ( $general_prefs->{'scan_hunt'} && $general_prefs->{'scan_hunt'} eq 'on' ) ? 'checked' : ''
	);
	say " <a class=\"tooltip\" title=\"Hunt for start/stop codons - If the aligned sequence is not an exact match to an "
	  . "existing allele and is not a complete coding sequence with start and stop codons at the ends, selecting this "
	  . "option will hunt for these by walking in and out from the ends in complete codons for up to 6 amino acids.\">"
	  . "&nbsp;<i>i</i>&nbsp;</a>"
	  . "</li><li>";
	say $q->checkbox(
		-name    => 'partial_when_exact',
		-id      => 'partial_when_exact',
		-label   => 'Return partial matches even when exact matches are found',
		-checked => ( $general_prefs->{'partial_when_exact'} && $general_prefs->{'partial_when_exact'} eq 'on' ) ? 'checked' : ''
	);
	say "</li><li>";
	say $q->checkbox(
		-name    => 'rescan_alleles',
		-id      => 'rescan_alleles',
		-label   => 'Rescan even if allele designations are already set',
		-checked => ( $general_prefs->{'scan_rescan_alleles'} && $general_prefs->{'scan_rescan_alleles'} eq 'on' ) ? 'checked' : ''
	);
	say "</li><li>";
	say $q->checkbox(
		-name    => 'rescan_seqs',
		-id      => 'rescan_seqs',
		-label   => 'Rescan even if allele sequences are tagged',
		-checked => ( $general_prefs->{'scan_rescan_seqs'} && $general_prefs->{'scan_rescan_seqs'} eq 'on' ) ? 'checked' : ''
	);
	say "</li><li>";
	say $q->checkbox(
		-name    => 'mark_missing',
		-id      => 'mark_missing',
		-label   => "Mark missing sequences as provisional allele '0'",
		-checked => ( $general_prefs->{'scan_mark_missing'} && $general_prefs->{'scan_mark_missing'} eq 'on' ) ? 'checked' : ''
	);
	say "</li></ul>";
	say "</fieldset>";
	return;
}

sub _scan {
	my ( $self, $labels ) = @_;
	my $q          = $self->{'cgi'};
	my $time_limit = ( int( $q->param('limit_time') ) || 5 ) * 60;
	my @loci       = $q->param('locus');
	my @ids        = $q->param('isolate_id');
	my $scheme_ids = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
	push @$scheme_ids, 0;
	if ( !@ids ) {
		say "<div class=\"box\" id=\"statusbad\"><p>You must select one or more isolates.</p></div>";
		return;
	}
	if ( !@loci && none { $q->param("s_$_") } @$scheme_ids ) {
		say "<div class=\"box\" id=\"statusbad\"><p>You must select one or more loci or schemes.</p></div>";
		return;
	}

	#Store scan attributes in pref database
	my $guid = $self->get_guid;
	if ($guid) {
		my $dbname = $self->{'system'}->{'db'};
		foreach (
			qw (identity alignment word_size partial_matches limit_matches limit_time tblastx hunt rescan_alleles rescan_seqs mark_missing)
		  )
		{
			my $value = ( defined $q->param($_) && $q->param($_) ne '' ) ? $q->param($_) : 'off';
			$self->{'prefstore'}->set_general( $guid, $dbname, "scan_$_", $value );
		}
	}
	$self->_add_scheme_loci( \@loci );
	my $limit = BIGSdb::Utils::is_int( $q->param('limit_matches') ) ? $q->param('limit_matches') : $LIMIT_MATCHES;
	my $scan_job = $self->{'scan_job'} =~ /^(BIGSdb_[0-9_]+)$/ ? $1 : undef;
	$self->_save_parameters($scan_job);
	my $project_id = $q->param('project_list');

	#Use double fork to prevent zombie processes on apache2-mpm-worker
	defined( my $kid = fork ) or $logger->error("cannot fork");
	if ($kid) {
		waitpid( $kid, 0 );
	} else {
		defined( my $grandkid = fork ) or $logger->error("Kid cannot fork");
		if ($grandkid) {
			CORE::exit(0);
		} else {
			open STDIN,  '<', '/dev/null' || $logger->error("Can't read /dev/null: $!");
			open STDOUT, '>', '/dev/null' || $logger->error("Can't write to /dev/null: $!");
			my $options = {
				labels               => $labels,
				limit                => $limit,
				time_limit           => $time_limit,
				loci                 => \@loci,
				project_id           => $project_id,
				scan_job             => $scan_job,
				script_name          => $self->{'system'}->{'script_name'},
				curator_name         => $self->get_curator_name,
				throw_busy_exception => 1
			};
			my $params = $q->Vars;
			try {
				BIGSdb::Offline::Scan->new(
					{
						config_dir       => $self->{'config_dir'},
						lib_dir          => $self->{'lib_dir'},
						dbase_config_dir => $self->{'dbase_config_dir'},
						host             => $self->{'system'}->{'host'},
						port             => $self->{'system'}->{'port'},
						user             => $self->{'system'}->{'user'},
						password         => $self->{'system'}->{'password'},
						options          => $options,
						params           => $params,
						instance         => $self->{'instance'},
						logger           => $logger
					}
				);
			}
			catch BIGSdb::ServerBusyException with {
				my $status_file = "$self->{'config'}->{'secure_tmp_dir'}/$scan_job\_status.txt";
				open( my $fh, '>', $status_file ) || $logger->error("Can't open $status_file for writing");
				say $fh "server_busy:1";
				close $fh;
			};
			CORE::exit(0);
		}
	}
	say "<div class=\"box\" id=\"resultsheader\"><p>You will be forwarded to the results page shortly.  Click "
	  . "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagScan&amp;scan=$scan_job&amp;results=1\">here</a> "
	  . "if you're not.</p></div>";
	return;
}

sub _tag {
	my ( $self, $labels ) = @_;
	my ( @updates, @allele_updates, @sequence_updates, $history );
	my $q = $self->{'cgi'};
	my $sequence_exists_sql =
	  $self->{'db'}->prepare("SELECT COUNT(*) FROM allele_sequences WHERE seqbin_id=? AND locus=? AND start_pos=? AND end_pos=?");
	my $sql               = $self->{'db'}->prepare("SELECT sender FROM sequence_bin WHERE id=?");
	my $curator_id        = $self->get_curator_id;
	my $scan_job          = $q->param('scan');
	my $match_list        = $self->_read_matches($scan_job);
	my $designation_added = {};
	foreach my $match (@$match_list) {

		if ( $match =~ /^(\d+):(.+):(\d+)$/ ) {
			my ( $isolate_id, $locus, $id ) = ( $1, $2, $3 );
			next if !$self->is_allowed_to_view_isolate($isolate_id);
			my $display_locus = $self->clean_locus($locus);
			my $seqbin_id     = $q->param("id_$isolate_id\_$locus\_seqbin_id_$id");
			if ( $q->param("id_$isolate_id\_$locus\_allele_$id") && defined $q->param("id_$isolate_id\_$locus\_allele_id_$id") ) {
				my $allele_id = $q->param("id_$isolate_id\_$locus\_allele_id_$id");
				my $set_allele_ids = $self->{'datastore'}->get_allele_ids( $isolate_id, $locus );
				eval { $sql->execute($seqbin_id) };
				$logger->error($@) if $@;
				my $seqbin_info = $sql->fetchrow_hashref;
				my $sender      = $allele_id ? $seqbin_info->{'sender'} : $self->get_curator_id;
				my $status      = $allele_id ? 'confirmed' : 'provisional';
				if ( ( none { $allele_id eq $_ } @$set_allele_ids ) && !$designation_added->{$isolate_id}->{$locus}->{$allele_id} ) {
					push @updates,
					  {
						statement => "INSERT INTO allele_designations (isolate_id,locus,allele_id,sender,status,method,curator,"
						  . "date_entered,datestamp,comments) VALUES (?,?,?,?,?,?,?,?,?,?)",
						arguments => [
							$isolate_id, $locus, $allele_id, $sender, $status, 'automatic', $curator_id, 'now', 'now',
							'Scanned from sequence bin'
						]
					  };
					push @allele_updates, ( $labels->{$isolate_id} || $isolate_id ) . ": $display_locus:  $allele_id";
					push @{ $history->{$isolate_id} }, "$locus: new designation '$allele_id' (sequence bin scan)";
					$designation_added->{$isolate_id}->{$locus}->{$allele_id} = 1;
				}
			}
			if ( $q->param("id_$isolate_id\_$locus\_sequence_$id") ) {
				my $start = $q->param("id_$isolate_id\_$locus\_start_$id");
				my $end   = $q->param("id_$isolate_id\_$locus\_end_$id");
				eval { $sequence_exists_sql->execute( $seqbin_id, $locus, $start, $end ) };
				$logger->error($@) if $@;
				my ($exists) = $sequence_exists_sql->fetchrow_array;
				if ( !$exists ) {
					my $reverse  = $q->param("id_$isolate_id\_$locus\_reverse_$id")  ? 'TRUE' : 'FALSE';
					my $complete = $q->param("id_$isolate_id\_$locus\_complete_$id") ? 'TRUE' : 'FALSE';
					push @updates,
					  {
						statement => "INSERT INTO allele_sequences (seqbin_id,locus,start_pos,end_pos,reverse,complete,curator,datestamp) "
						  . "VALUES (?,?,?,?,?,?,?,?)",
						arguments => [ $seqbin_id, $locus, $start, $end, $reverse, $complete, $curator_id, 'now' ]
					  };
					push @sequence_updates,
					  ( $labels->{$isolate_id} || $isolate_id ) . ": $display_locus:  Seqbin id: $seqbin_id; $start-$end";
					push @{ $history->{$isolate_id} }, "$locus: sequence tagged. Seqbin id: $seqbin_id; $start-$end (sequence bin scan)";
					if ( $q->param("id_$isolate_id\_$locus\_sequence_$id\_flag") ) {
						my @flags = $q->param("id_$isolate_id\_$locus\_sequence_$id\_flag");
						foreach my $flag (@flags) {

							#Need to find out the autoincrementing id for the just added tag
							push @updates,
							  {
								statement => "INSERT INTO sequence_flags (id,flag,datestamp,curator) SELECT allele_sequences.id,"
								  . "?,?,? FROM allele_sequences WHERE (seqbin_id,locus,start_pos,end_pos)=(?,?,?,?)",
								arguments => [ $flag, 'now', $curator_id, $seqbin_id, $locus, $start, $end ]
							  };
						}
					}
				}
			}
		}
	}
	if (@updates) {
		eval {
			foreach my $update (@updates)
			{
				$self->{'db'}->do( $update->{'statement'}, undef, @{ $update->{'arguments'} } );
			}
		};
		if ($@) {
			my $err = $@;
			say qq(<div class="box" id="statusbad"><p>Database update failed - transaction cancelled - no records have been touched.</p>);
			if ( $err =~ /duplicate/ && $err =~ /unique/ ) {
				say "<p>Data entry would have resulted in records with either duplicate ids or another unique field with "
				  . "duplicate values.</p>";
			} else {
				say "<p>Error message: $err</p>";
				$logger->error($err);
			}
			say "</div>";
			$self->{'db'}->rollback;
			return;
		} else {
			$self->{'db'}->commit;
			say "<div class=\"box\" id=\"resultsheader\"><p>Database updated ok.</p>";
			say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back to main page</a> | "
			  . "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagScan&amp;parameters=$scan_job\">"
			  . "Reload scan form</a></p></div>";
			say "<div class=\"box\" id=\"resultstable\">";
			local $" = "<br />\n";
			if (@allele_updates) {
				say "<h2>Allele designations set</h2>";
				say "<p>@allele_updates</p>";
			}
			if (@sequence_updates) {
				say "<h2>Allele sequences set</h2>";
				say "<p>@sequence_updates</p>";
			}
			if ( ref $history eq 'HASH' ) {
				foreach ( keys %$history ) {
					my @message = @{ $history->{$_} };
					local $" = '<br />';
					$self->update_history( $_, "@message" );
				}
			}
			say "</div>";
		}
	} else {
		say "<div class=\"box\" id=\"resultsheader\"><p>No updates required.</p>";
		say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back to main page</a> | "
		  . "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagScan&amp;parameters=$scan_job\">"
		  . "Reload scan form</a></p></div>";
	}
	return;
}

sub _show_results {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $scan_job = $q->param('scan');
	$scan_job = $scan_job =~ /^(BIGSdb_[0-9_]+)$/ ? $1 : undef;
	if ( !defined $scan_job ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Invalid job id passed.</p></div>";
		return;
	}
	my $filename = "$self->{'config'}->{'secure_tmp_dir'}/$scan_job\_table.html";
	my $status   = $self->_read_status($scan_job);
	if ( $status->{'server_busy'} ) {
		say "<div class=\"box\" id=\"statusbad\"><p>The server is currently too busy to run your scan.  Please wait a few minutes "
		  . "and then try again.</p></div>";
		return;
	} elsif ( !$status->{'start_time'} ) {
		say "<div class=\"box\" id=\"statusbad\"><p>The requested job does not exist.</p></div>";
		return;
	}
	say "<div class=\"box\" id=\"resultstable\">";
	say $q->start_form;
	if ( !-s $filename ) {
		if ( $status->{'stop_time'} ) {
			say "<p>No matches found.</p>";
		} else {
			say "<p>No results yet ... please wait.</p>";
		}
	} else {
		say "<div class=\"scrollable\">\n<table class=\"resultstable\"><tr><th>Isolate</th><th>Match</th><th>Locus</th>"
		  . "<th>Allele</th><th>% identity</th><th>Alignment length</th><th>Allele length</th><th>E-value</th><th>Sequence bin id</th>"
		  . "<th>Start</th><th>End</th><th>Predicted start</th><th>Predicted end</th><th>Orientation</th><th>Designate allele</th>"
		  . "<th>Tag sequence</th><th>Flag <a class=\"tooltip\" title=\"Flag - Set a status flag for the sequence.  You need to also "
		  . "tag the sequence for any flag to take effect.\">&nbsp;<i>i</i>&nbsp;</a></th></tr>";
		$self->print_file($filename);
		say "</table></div>";
		say "<p>* Allele continues beyond end of contig</p>" if $status->{'allele_off_contig'};
	}
	if ( $status->{'new_seqs_found'} ) {
		say "<p><a href=\"/tmp/$scan_job\_unique_sequences.txt\" target=\"_blank\">New unique sequences</a>"
		  . " <a class=\"tooltip\" title=\"Unique sequence - This is a list of new unique sequences found in this search (tab-delimited "
		  . "with locus name). This can be used to facilitate rapid upload of new sequences to a sequence definition database for allele "
		  . "assignment.\">&nbsp;<i>i</i>&nbsp;</a></p>";
	}
	if ( -s $filename && $status->{'stop_time'} ) {
		if ( $status->{'tag_isolates'} ) {
			my @isolates_to_tag = split /,/, $status->{'tag_isolates'};
			$q->param( 'isolate_id_list', @isolates_to_tag );
			my @loci = split /,/, $status->{'loci'};
			$q->param( 'loci', @loci );
			say $q->hidden($_) foreach qw(isolate_id_list loci);
		}
		say $q->hidden($_) foreach qw(db page scan);
		say qq(<fieldset style="float:left"><legend>Action</legend>);
		say $q->submit(
			-name  => 'tag',
			-label => 'Tag alleles/sequences',
			-class => 'submitbutton ui-button ui-widget ui-state-default ui-corner-all'
		);
		say qq(</fieldset><div style="clear:both"></div>);
	}
	say $q->end_form;
	say "</div>";
	say "<div class=\"box\" id=\"resultsfooter\">";
	my $elapsed = $status->{'start_time'} ? $status->{'start_time'} - ( $status->{'stop_time'} // time ) : undef;
	my ( $refresh_time, $elapsed_time );
	eval "use Time::Duration;";    ## no critic (ProhibitStringyEval)
	if ($@) {
		$refresh_time = $self->{'refresh'} . ' seconds';
		$elapsed_time = $elapsed ? "$elapsed seconds" : undef;
	} else {
		$refresh_time = duration( $self->{'refresh'} );
		$elapsed_time = $elapsed ? duration($elapsed) : undef;
	}
	if ( $status->{'match_limit_reached'} ) {
		say "<p>Match limit reached (checked up to id-$status->{'last_isolate'}).</p>";
	} elsif ( $status->{'time_limit_reached'} ) {
		say "<p>Time limit reached (checked up to id-$status->{'last_isolate'}).</p>";
	}
	say "<p>";
	say "<b>Started:</b> " . scalar localtime( $status->{'start_time'} ) . '<br />' if $status->{'start_time'};
	say "<b>Finished:</b> " . scalar localtime( $status->{'stop_time'} ) . '<br />' if $status->{'stop_time'};
	say "<b>Elapsed time:</b> $elapsed_time"                                        if $elapsed_time;
	say "</p>";
	if ( !$status->{'stop_time'} ) {
		say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagScan&amp;scan=$self->{'scan_job'}&amp;"
		  . "results=1&amp;stop=1\" class=\"resetbutton ui-button ui-widget ui-state-default ui-corner-all ui-button-text-only \">"
		  . "<span class=\"ui-button-text\">Stop job!</span></a> Clicking this will request that the job finishes allowing new "
		  . "designations to be made.  Please allow a few seconds for it to stop.</p>";
	}
	if ( $self->{'refresh'} ) {
		say "<p>This page will reload in $refresh_time. You can refresh it any time, or bookmark it, close your browser and return "
		  . "to it later if you wish.</p>";
	}
	if ( $self->{'config'}->{'results_deleted_days'} && BIGSdb::Utils::is_int( $self->{'config'}->{'results_deleted_days'} ) ) {
		say "<p>Please note that scan results will remain on the server for $self->{'config'}->{'results_deleted_days'} days.</p></div>";
	} else {
		say "<p>Please note that scan results will not be stored on the server indefinitely.</p></div>";
	}
	return;
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $view   = $self->{'system'}->{'view'};
	my ( $ids, $labels ) = $self->get_isolates_with_seqbin;
	say "<h1>Sequence tag scan</h1>";
	if ( $q->param('tag') ) {
		$self->_tag($labels);
	} elsif ( $q->param('results') ) {
		$self->_show_results;
	} elsif ( $q->param('submit') ) {
		$self->_scan($labels);
	} else {
		$self->_print_interface( $ids, $labels );
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Sequence tag scan - $desc";
}

sub _add_scheme_loci {
	my ( $self, $loci_ref ) = @_;
	my $q          = $self->{'cgi'};
	my $scheme_ids = $self->{'datastore'}->run_list_query("SELECT id FROM schemes ORDER BY id");
	push @$scheme_ids, 0;    #loci not belonging to a scheme.
	my %locus_selected = map { $_ => 1 } @$loci_ref;
	my $set_id = $self->get_set_id;
	foreach (@$scheme_ids) {
		next if !$q->param("s_$_");
		my $scheme_loci =
		  $_ ? $self->{'datastore'}->get_scheme_loci($_) : $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
		foreach my $locus (@$scheme_loci) {
			if ( !$locus_selected{$locus} ) {
				push @$loci_ref, "l_$locus";
				$locus_selected{$locus} = 1;
			}
		}
	}
	return;
}

sub _create_temp_tables {
	my ( $self, $qry_ref ) = @_;
	my $qry      = $$qry_ref;
	my $schemes  = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
	my $continue = 1;
	try {
		foreach (@$schemes) {
			if ( $qry =~ /temp_scheme_$_\s/ || $qry =~ /ORDER BY s_$_\_/ ) {
				$self->{'datastore'}->create_temp_scheme_table($_);
				$self->{'datastore'}->create_temp_isolate_scheme_loci_view($_);
			}
		}
	}
	catch BIGSdb::DatabaseConnectionException with {
		$logger->error("Can't connect to remote database.");
		$continue = 0;
	};
	return $continue;
}

sub _get_ids {
	my ( $self, $qry ) = @_;
	$qry =~ s/ORDER BY.*$//g;
	return if !$self->_create_temp_tables( \$qry );
	$qry =~ s/SELECT \*/SELECT id/;
	my $ids = $self->{'datastore'}->run_list_query($qry);
	return $ids;
}

sub _read_status {
	my ( $self, $scan_job ) = @_;
	my $status_file = "$self->{'config'}->{'secure_tmp_dir'}/$scan_job\_status.txt";
	my %data;
	return \%data if !-e $status_file;
	open( my $fh, '<', $status_file ) || $logger->error("Can't open $status_file for reading. $!");
	while (<$fh>) {
		if ( $_ =~ /^(.*):(.*)$/ ) {
			$data{$1} = $2;
		}
	}
	close $fh;
	return \%data;
}

sub _read_matches {
	my ( $self, $scan_job ) = @_;
	my $match_file = "$self->{'config'}->{'secure_tmp_dir'}/$scan_job\_matches.txt";
	my @data;
	return \@data if !-e $match_file;
	open( my $fh, '<', $match_file ) || $logger->error("Can't open $match_file for reading. $!");
	while (<$fh>) {
		if ( $_ =~ /^(\d+):(.*)$/ ) {
			push @data, $_;
		}
	}
	close $fh;
	return \@data;
}

sub _save_parameters {
	my ( $self, $scan_job ) = @_;
	my $filename = "$self->{'config'}->{'secure_tmp_dir'}/$scan_job\_parameters";
	open( my $fh, '>', $filename ) || $logger->error("Can't open $filename for writing");
	$self->{'cgi'}->save( \*$fh );
	close $fh;
	return;
}
1;
