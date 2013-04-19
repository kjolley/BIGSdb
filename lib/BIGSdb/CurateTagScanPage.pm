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
package BIGSdb::CurateTagScanPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage BIGSdb::TreeViewPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use List::MoreUtils qw(uniq any none);
use Apache2::Connection ();
use Error qw(:try);
use BIGSdb::Page qw(SEQ_METHODS SEQ_FLAGS LOCUS_PATTERN);
use BIGSdb::Offline::Scan;
##DEFAUT SCAN PARAMETERS#############
my $MIN_IDENTITY    = 70;
my $MIN_ALIGNMENT   = 50;
my $WORD_SIZE       = 15;
my $PARTIAL_MATCHES = 1;
my $LIMIT_MATCHES   = 200;
my $LIMIT_TIME      = 5;
my $TBLASTX         = 'off';
my $HUNT            = 'off';
my $RESCAN_ALLELES  = 'off';
my $RESCAN_SEQS     = 'off';
my $MARK_MISSING    = 'off';

sub get_javascript {
	my ($self) = @_;
	my %check_values = ( on => 'true', off => 'false' );
	my $buffer = << "END";
\$(function () {	
		\$("html, body").animate({ scrollTop: \$(document).height()-\$(window).height() });	
});	
	
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
	\$("#rescan_alleles").prop(\"checked\",$check_values{$RESCAN_ALLELES});
	\$("#rescan_seqs").prop(\"checked\",$check_values{$RESCAN_SEQS});
	\$("#mark_missing").prop(\"checked\",$check_values{$MARK_MISSING});
}
	
END
	$buffer .= $self->get_tree_javascript( { checkboxes => 1, check_schemes => 1 } );
	return $buffer;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (tooltips jQuery jQuery.jstree noCache);
	my $q = $self->{'cgi'};
	if ($q->param('submit') || $q->param('results')){
		$self->{'refresh'} = $q->param('results') ? 5 : 2;
		$self->{'scan_job'} = $q->param('scan') || BIGSdb::Utils::get_random();
		$self->{'refresh_page'} = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagScan&amp;scan=$self->{'scan_job'}&amp;results=1";
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
	my $selected_ids = $q->param('query') ? $self->_get_ids( $q->param('query') ) : [];
	say $q->start_form;
	say "<div class=\"scrollable\"><fieldset>\n<legend>Isolates</legend>";
	say $q->scrolling_list(
		-name     => 'isolate_id',
		-id       => 'isolate_id',
		-values   => $ids,
		-labels   => $labels,
		-size     => 11,
		-multiple => 'true',
		-default  => $selected_ids
	);
	say "<div style=\"text-align:center\"><input type=\"button\" onclick='listbox_selectall(\"isolate_id\",true)' value=\"All\" "
	  . "style=\"margin-top:1em\" class=\"smallbutton\" />";
	say "<input type=\"button\" onclick='listbox_selectall(\"isolate_id\",false)' value=\"None\" style=\"margin-top:1em\" "
	  . "class=\"smallbutton\" /></div>";
	say "</fieldset>";
	say "<fieldset>\n<legend>Loci</legend>";
	say $q->scrolling_list( -name => 'locus', -id => 'locus', -values => $loci, -labels => $locus_labels, -size => 11,
		-multiple => 'true' );
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
#	my $scan_job = BIGSdb::Utils::get_random();
#	say $q->hidden('scan', $scan_job);
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
		-values  => [qw(50 55 60 65 70 75 80 85 90 91 92 93 94 95 96 97 98 99 100)],
		-default => $general_prefs->{'scan_identity'} || $MIN_IDENTITY
	);
	say " <a class=\"tooltip\" title=\"Minimum % identity - Match required for partial matching.\">&nbsp;<i>i</i>&nbsp;</a></li>"
	  . "<li><label for =\"alignment\" class=\"parameter\">Min % alignment:</label>";
	say $q->popup_menu(
		-name    => 'alignment',
		-id      => 'alignment',
		-values  => [qw(30 35 40 45 50 55 60 65 70 75 80 85 90 91 92 93 94 95 96 97 98 99 100)],
		-default => $general_prefs->{'scan_alignment'} || $MIN_ALIGNMENT
	);
	say " <a class=\"tooltip\" title=\"Minimum % alignment - Percentage of allele sequence length required to be aligned for "
	  . "partial matching.\">&nbsp;<i>i</i>&nbsp;</a></li>"
	  . "<li><label for =\"word_size\" class=\"parameter\">BLASTN word size:</label>";
	say $q->popup_menu(
		-name    => 'word_size',
		-id      => 'word_size',
		-values  => [qw(7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28)],
		-default => $general_prefs->{'scan_word_size'} || $WORD_SIZE
	);
	say " <a class=\"tooltip\" title=\"BLASTN word size - This is the length of an exact match required to initiate an extension. "
	  . "Larger values increase speed at the expense of sensitivity.\">&nbsp;<i>i</i>&nbsp;</a></li>"
	  . "<li><label for =\"partial_matches\" class=\"parameter\">Return up to:</label>";
	say $q->popup_menu(
		-name    => 'partial_matches',
		-id      => 'partial_matches',
		-values  => [qw(1 2 3 4 5 6 7 8 9 10)],
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
			qw (identity alignment word_size partial_matches limit_matches limit_time tblastx hunt rescan_alleles rescan_seqs mark_missing))
		{
			my $value = ( defined $q->param($_) && $q->param($_) ne '' ) ? $q->param($_) : 'off';
			$self->{'prefstore'}->set_general( $guid, $dbname, "scan_$_", $value );
		}
	}
	$self->_add_scheme_loci( \@loci );
	my $tag_button = 1;
	my ( @js, @js2, @js3, @js4 );
	my $show_key;    #TODO need to get this back
	my $buffer;
	my $first = 1;
	my $new_alleles;
	my $limit = BIGSdb::Utils::is_int( $q->param('limit_matches') ) ? $q->param('limit_matches') : $LIMIT_MATCHES;
	my ( %allele_designation_set, %allele_sequence_tagged );
	my $out_of_time;
	my $match_limit_reached;
	my $new_seqs_found;     #TODO get this back
	my $last_id_checked;    #TODO get this back
	my $file_prefix  = BIGSdb::Utils::get_random();
	my $scan_job = $self->{'scan_job'} =~ /^(BIGSdb_[0-9_]+)$/ ? $1 : undef;
	
	my $project_id = $q->param('project_list');
	my %isolates_to_tag;    #TODO get this back too
		local $| = 1;
	
	local $SIG{CHLD} = 'IGNORE';    #prevent zombie processes if apache restarted during scan
	defined( my $pid = fork ) or $logger->error("cannot fork");

	unless ($pid) {
		open STDIN,  '<', '/dev/null';
    	open STDOUT, '>', '/dev/null';
    	open STDERR, '>&STDOUT';
		
		my $options = {
			labels => $labels,
			limit        => $limit,
			time_limit   => $time_limit,
			loci         => \@loci,
			project_id   => $project_id,
			file_prefix  => $file_prefix,
			scan_job => $scan_job,
			script_name  => $self->{'system'}->{'script_name'}
		};
		my $params      = $q->Vars;
		my $scan_thread = BIGSdb::Offline::Scan->new(
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
				instance         => $self->{'instance'}
			}
		);
		CORE::exit(0);
	}
	say "<div class=\"box\" id=\"resultsheader\"><p>You will be forwarded to the results page shortly.  Click "
	  . "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagScan&amp;scan=$scan_job&amp;results=1\">here</a> "
	  . "if you're not.</p></div>";
	return;
	
	

	
	
	
	if ($first) {
		$tag_button = 0;
	} else {
		$buffer .= "</table></div>\n";
		$buffer .= "<p>* Allele continues beyond end of contig</p>" if $show_key;
	}
	if ($tag_button) {
		local $" = ';';
		say "<tr class=\"td\"><td colspan=\"14\" /><td>";
		say "<input type=\"button\" value=\"All\" onclick='@js' class=\"smallbutton\" />"   if @js;
		say "<input type=\"button\" value=\"None\" onclick='@js2' class=\"smallbutton\" />" if @js2;
		say "</td><td>";
		say "<input type=\"button\" value=\"All\" onclick='@js3' class=\"smallbutton\" />"  if @js3;
		say "<input type=\"button\" value=\"None\" onclick='@js4' class=\"smallbutton\" />" if @js4;
		say "</td></tr>";
	}
	say $buffer                                                           if $buffer;
	say "<p>Time limit reached (checked up to id-$last_id_checked).</p>"  if $out_of_time;            #TODO make sure this is returned
	say "<p>Match limit reached (checked up to id-$last_id_checked).</p>" if $match_limit_reached;    #TODO make sure this is returned
	if ($new_seqs_found) {
		say "<p><a href=\"/tmp/$file_prefix\_unique_sequences.txt\" target=\"_blank\">New unique sequences</a>";
		say " <a class=\"tooltip\" title=\"Unique sequence - This is a list of new sequences (tab-delimited with locus name) of unique "
		  . "new sequences found in this search.  This can be used to facilitate rapid upload of new sequences to a sequence definition "
		  . "database for allele assignment.\">&nbsp;<i>i</i>&nbsp;</a></p>";
	}
	if ($tag_button) {
		$q->param( 'isolate_id_list', sort { $a <=> $b } keys %isolates_to_tag )
		  ;    #pass the isolates that appear in the table rather than whole selection.  Don't overwrite isolate_id param though
		       #or it will reset the isolate list selections.
		say $q->submit( -name => 'tag', -label => 'Tag alleles/sequences', -class => 'submit' );
		say "<noscript><p><span class=\"comment\"> Enable javascript for select buttons to work!</span></p></noscript>\n";
		foreach (
			qw (db page isolate_id isolate_id_list rescan_alleles rescan_seqs locus identity alignment limit_matches limit_time
			seq_method_list	experiment_list project_list tblastx hunt pcr_filter alter_pcr_mismatches probe_filter alter_probe_mismatches)
		  )
		{
			say $q->hidden($_);
		}
		say $q->hidden("s_$_") foreach @$scheme_ids;
	} else {
		say "<p>No sequence or allele tags to update.</p>";
	}
	say "</div>";
	return;
}

sub _tag {
	my ( $self, $labels ) = @_;
	my ( @updates, @allele_updates, @pending_allele_updates, @sequence_updates, $history );
	my $q = $self->{'cgi'};
	my $pending_sql =
	  $self->{'db'}
	  ->prepare("SELECT COUNT(*) FROM pending_allele_designations WHERE isolate_id=? AND locus=? AND allele_id=? AND sender=?");
	my $sequence_exists_sql =
	  $self->{'db'}->prepare("SELECT COUNT(*) FROM allele_sequences WHERE seqbin_id=? AND locus=? AND start_pos=? AND end_pos=?");
	my @params      = $q->param;
	my @isolate_ids = $q->param('isolate_id_list');
	my @loci        = $q->param('locus');
	my @scheme_ids  = $q->param('scheme_id');
	$self->_add_scheme_loci( \@loci );
	@loci = uniq @loci;
	my $sql        = $self->{'db'}->prepare("SELECT sender FROM sequence_bin WHERE id=?");
	my $curator_id = $self->get_curator_id;

	foreach my $isolate_id (@isolate_ids) {
		next if !$self->is_allowed_to_view_isolate($isolate_id);
		my %tested_locus;
		foreach (@loci) {
			$_ =~ s/^cn_//;
			$_ =~ s/^l_//;
			$_ =~ s/^la_//;
			$_ =~ s/\|\|.+//;
			next if $tested_locus{$_};
			$tested_locus{$_} = 1;
			my @ids;
			my %used;
			my $cleaned_locus = $_;
			$cleaned_locus =~ s/'/\\'/g;
			my $allele_id_to_set;
			my %pending_allele_ids_to_set;

			foreach my $id (@params) {
				next if $id !~ /$_/;
				next if $id !~ /\_$isolate_id\_/;
				my $allele_test = "id_$isolate_id\_$_\_allele";
				my $seq_test    = "id_$isolate_id\_$_\_sequence";
				if ( $id =~ /\Q$allele_test\E\_(\d+)/ || $id =~ /\Q$seq_test\E\_(\d+)/ ) {
					push @ids, $1 if !$used{$1};
					$used{$1} = 1;
				}
			}
			my $display_locus = $self->clean_locus($_);
			foreach my $id (@ids) {
				my $seqbin_id = $q->param("id_$isolate_id\_$_\_seqbin_id_$id");
				if ( $q->param("id_$isolate_id\_$_\_allele_$id") && defined $q->param("id_$isolate_id\_$_\_allele_id_$id") ) {
					my $allele_id = $q->param("id_$isolate_id\_$_\_allele_id_$id");
					my $set_allele_id = $self->{'datastore'}->get_allele_id( $isolate_id, $_ );
					eval { $sql->execute($seqbin_id) };
					$logger->error($@) if $@;
					my $seqbin_info = $sql->fetchrow_hashref;
					my $sender      = $allele_id ? $seqbin_info->{'sender'} : $self->get_curator_id;
					my $status      = $allele_id ? 'confirmed' : 'provisional';
					if ( !defined $set_allele_id && !defined $allele_id_to_set ) {
						push @updates,
						    "INSERT INTO allele_designations (isolate_id,locus,allele_id,sender,status,method,curator,"
						  . "date_entered,datestamp,comments) VALUES ($isolate_id,E'$cleaned_locus','$allele_id',$sender,'$status',"
						  . "'automatic',$curator_id,'today','today','Scanned from sequence bin')";
						$allele_id_to_set = $allele_id;
						push @allele_updates, ( $labels->{$isolate_id} || $isolate_id ) . ": $display_locus:  $allele_id";
						push @{ $history->{$isolate_id} }, "$_: new designation '$allele_id' (sequence bin scan)";
					} elsif (
						(
							   ( defined $set_allele_id && $set_allele_id ne $allele_id )
							|| ( defined $allele_id_to_set && $allele_id_to_set ne $allele_id )
						)
						&& !$pending_allele_ids_to_set{$allele_id}
					  )
					{
						eval { $pending_sql->execute( $isolate_id, $_, $allele_id, $sender ) };
						$logger->error($@) if $@;
						my ($exists) = $pending_sql->fetchrow_array;
						if ( !$exists ) {
							push @updates,
							    "INSERT INTO pending_allele_designations (isolate_id,locus,allele_id,sender,method,curator,"
							  . "date_entered,datestamp,comments) VALUES ($isolate_id,E'$cleaned_locus','$allele_id',$sender,'automatic',"
							  . "$curator_id,'today','today','Scanned from sequence bin')";
							$pending_allele_ids_to_set{$allele_id} = 1;
							push @pending_allele_updates,
							    ( $labels->{$isolate_id} || $isolate_id )
							  . ": $display_locus:  $allele_id (conflicts with existing designation '"
							  . ( ( $set_allele_id // '' ) eq '' ? $allele_id_to_set : $set_allele_id ) . "').";
							push @{ $history->{$isolate_id} }, "$_: new pending designation '$allele_id' (sequence bin scan)";
						}
					}
				}
				if ( $q->param("id_$isolate_id\_$_\_sequence_$id") ) {
					my $start = $q->param("id_$isolate_id\_$_\_start_$id");
					my $end   = $q->param("id_$isolate_id\_$_\_end_$id");
					eval { $sequence_exists_sql->execute( $seqbin_id, $_, $start, $end ) };
					$logger->error($@) if $@;
					my ($exists) = $sequence_exists_sql->fetchrow_array;
					if ( !$exists ) {
						my $reverse  = $q->param("id_$isolate_id\_$_\_reverse_$id")  ? 'TRUE' : 'FALSE';
						my $complete = $q->param("id_$isolate_id\_$_\_complete_$id") ? 'TRUE' : 'FALSE';
						push @updates,
						  "INSERT INTO allele_sequences (seqbin_id,locus,start_pos,end_pos,reverse,complete,curator,datestamp) "
						  . "VALUES ($seqbin_id,'$cleaned_locus',$start,$end,'$reverse','$complete',$curator_id,'today')";
						push @sequence_updates,
						  ( $labels->{$isolate_id} || $isolate_id ) . ": $display_locus:  Seqbin id: $seqbin_id; $start-$end";
						push @{ $history->{$isolate_id} }, "$_: sequence tagged. Seqbin id: $seqbin_id; $start-$end (sequence bin scan)";
						if ( $q->param("id_$isolate_id\_$_\_sequence_$id\_flag") ) {
							my @flags = $q->param("id_$isolate_id\_$_\_sequence_$id\_flag");
							foreach my $flag (@flags) {
								push @updates, "INSERT INTO sequence_flags (seqbin_id,locus,start_pos,end_pos,flag,datestamp,curator) "
								  . "VALUES ($seqbin_id,'$cleaned_locus',$start,$end,'$flag','today',$curator_id)";
							}
						}
					}
				}
			}
		}
	}
	if (@updates) {
		my $query;
		eval {
			foreach (@updates)
			{
				$query = $_;
				$self->{'db'}->do($_);
			}
		};
		if ($@) {
			my $err = $@;
			say "<div class=\"box\" id=\"statusbad\"><p>Database update failed - transaction cancelled - no records have been "
			  . "touched.</p>";
			if ( $err =~ /duplicate/ && $err =~ /unique/ ) {
				say "<p>Data entry would have resulted in records with either duplicate ids or another unique field with "
				  . "duplicate values.</p>";
				$logger->debug("$err $query");
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
			say "<p><a href=\"" . $q->script_name . "?db=$self->{'instance'}\">Back to main page</a></p></div>";
			say "<div class=\"box\" id=\"resultstable\">";
			local $" = "<br />\n";
			if (@allele_updates) {
				say "<h2>Allele designations set</h2>";
				say "<p>@allele_updates</p>";
			}
			if (@pending_allele_updates) {
				say "<h2>Pending allele designations set</h2>";
				say "<p>@pending_allele_updates</p>";
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
		say "<p><a href=\"$self->{'system'}->{'script_name'}db=$self->{'instance'}\">Back to main page</a></p></div>";
	}
	return;
}

sub _show_results {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $scan_job = $q->param('scan');
	$scan_job = $scan_job =~ /^(BIGSdb_[0-9_]+)$/ ? $1 : undef;
	if (!defined $scan_job){
		say "<div class=\"box\" id=\"statusbad\"><p>Invalid job id passed.</p></div>";
		return;
	}
	my $filename = "$self->{'config'}->{'secure_tmp_dir'}/$scan_job\_table.html";
	say "<div class=\"box\" id=\"resultstable\">";
		say $q->start_form;
	
	if (!-e $filename || !-s $filename){
		say "<p>No results yet ... please wait</p>";
	} else {
		say "<div class=\"scrollable\">\n<table class=\"resultstable\"><tr><th>Isolate</th><th>Match</th><th>Locus</th>"
	  . "<th>Allele</th><th>% identity</th><th>Alignment length</th><th>Allele length</th><th>E-value</th><th>Sequence bin id</th>"
	  . "<th>Start</th><th>End</th><th>Predicted start</th><th>Predicted end</th><th>Orientation</th><th>Designate allele</th>"
	  . "<th>Tag sequence</th><th>Flag <a class=\"tooltip\" title=\"Flag - Set a status flag for the sequence.  You need to also "
	  . "tag the sequence for any flag to take effect.\">&nbsp;<i>i</i>&nbsp;</a></th></tr>";
	  $self->print_file($filename);
	  say "</table></div>";
	}
	say $q->end_form;
	say "</div>";
	
	say "<div class=\"box\" id=\"resultsfooter\">";
	eval "use Time::Duration;";    ## no critic (ProhibitStringyEval)
	my $refresh;
	if ($@) {
		$refresh = $self->{'refresh'} . ' seconds';
	} else {
		$refresh = duration( $self->{'refresh'} );
	}


	
	say "<p>This page will reload in $refresh. You can refresh it any time, or bookmark it and close your browser if you wish.</p>"
	  if $self->{'refresh'};
	if ( $self->{'config'}->{'results_deleted_days'} && BIGSdb::Utils::is_int( $self->{'config'}->{'results_deleted_days'} ) ) {
		say "<p>Please note that job results will remain on the server for $self->{'config'}->{'results_deleted_days'} days.</p></div>";
	} else {
		say "<p>Please note that job results will not be stored on the server indefinitely.</p></div>";
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
	} elsif ( $q->param('results')){
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
	my %locus_selected;
	$locus_selected{$_} = 1 foreach @$loci_ref;
	foreach (@$scheme_ids) {
		next if !$q->param("s_$_");
		my $scheme_loci = $_ ? $self->{'datastore'}->get_scheme_loci($_) : $self->{'datastore'}->get_loci_in_no_scheme;
		foreach my $locus (@$scheme_loci) {
			if ( !$locus_selected{$locus} ) {
				push @$loci_ref, "l_$locus";
				$locus_selected{$locus} = 1;
			}
		}
	}
	return;
}

sub _simulate_PCR {
	my ( $self, $fasta_file, $locus ) = @_;
	my $q = $self->{'cgi'};
	my $reactions =
	  $self->{'datastore'}
	  ->run_list_query_hashref( "SELECT pcr.* FROM pcr LEFT JOIN pcr_locus ON pcr.id = pcr_locus.pcr_id WHERE locus=?", $locus );
	return if !@$reactions;
	my $temp          = BIGSdb::Utils::get_random();
	my $reaction_file = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_reactions.txt";
	my $results_file  = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_results.txt";
	open( my $fh, '>', $reaction_file );
	my $max_primer_mismatch = 0;
	my $conditions;

	foreach (@$reactions) {
		foreach my $primer (qw (primer1 primer2)) {
			$_->{$primer} =~ tr/ //;
		}
		my $min_length = $_->{'min_length'} || 1;
		my $max_length = $_->{'max_length'} || 50000;
		$max_primer_mismatch = $_->{'max_primer_mismatch'} if $_->{'max_primer_mismatch'} > $max_primer_mismatch;
		if ( $q->param('alter_pcr_mismatches') && $q->param('alter_pcr_mismatches') =~ /([\-\+]\d)/ ) {
			my $delta = $1;
			$max_primer_mismatch += $delta;
			$max_primer_mismatch = 0 if $max_primer_mismatch < 0;
		}
		print $fh "$_->{'id'}\t$_->{'primer1'}\t$_->{'primer2'}\t$min_length\t$max_length\n";
		$conditions->{ $_->{'id'} } = $_;
	}
	close $fh;
	system(
"$self->{'config'}->{'ipcress_path'} --input $reaction_file --sequence $fasta_file --mismatch $max_primer_mismatch --pretty false > $results_file 2> /dev/null"
	);
	my @pcr_products;
	open( $fh, '<', $results_file );
	while (<$fh>) {
		if ( $_ =~ /^ipcress:/ ) {
			my ( undef, $seq_id, $reaction_id, $length, undef, $start, $mismatch1, undef, $end, $mismatch2, $desc ) = split /\s+/, $_;
			next if $desc =~ /single/;    #product generated by one primer only.
			my ( $seqbin_id, undef ) = split /:/, $seq_id;
			$logger->debug("Seqbin_id:$seqbin_id; $start-$end; mismatch1:$mismatch1; mismatch2:$mismatch2");
			next
			  if $mismatch1 > $conditions->{$reaction_id}->{'max_primer_mismatch'}
				  || $mismatch2 > $conditions->{$reaction_id}->{'max_primer_mismatch'};
			my $product =
			  { 'seqbin_id' => $seqbin_id, 'start' => $start, 'end' => $end, 'mismatch1' => $mismatch1, 'mismatch2' => $mismatch2 };
			push @pcr_products, $product;
		}
	}
	close $fh;
	unlink $reaction_file, $results_file;
	return \@pcr_products;
}

sub _simulate_hybridization {
	my ( $self, $fasta_file, $locus ) = @_;
	my $q      = $self->{'cgi'};
	my $probes = $self->{'datastore'}->run_list_query_hashref(
"SELECT probes.id,probes.sequence,probe_locus.* FROM probes LEFT JOIN probe_locus ON probes.id = probe_locus.probe_id WHERE locus=?",
		$locus
	);
	return if !@$probes;
	my $file_prefix      = BIGSdb::Utils::get_random();
	my $probe_fasta_file = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_probe.txt";
	my $results_file     = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_results.txt";
	open( my $fh, '>', $probe_fasta_file ) or $logger->error("Can't open temp file $probe_fasta_file for writing");
	my %probe_info;

	foreach (@$probes) {
		$_->{'sequence'} =~ s/\s//g;
		print $fh ">$_->{'id'}\n$_->{'sequence'}\n";
		$_->{'max_mismatch'} = 0 if !$_->{'max_mismatch'};
		if ( $q->param('alter_probe_mismatches') && $q->param('alter_probe_mismatches') =~ /([\-\+]\d)/ ) {
			my $delta = $1;
			$_->{'max_mismatch'} += $delta;
			$_->{'max_mismatch'} = 0 if $_->{'max_mismatch'} < 0;
		}
		$_->{'max_gaps'} = 0 if !$_->{'max_gaps'};
		$_->{'min_alignment'} = length $_->{'sequence'} if !$_->{'min_alignment'};
		$probe_info{ $_->{'id'} } = $_;
	}
	close $fh;
	if ( $self->{'config'}->{'blast+_path'} ) {
		system("$self->{'config'}->{'blast+_path'}/makeblastdb -in $fasta_file -logfile /dev/null -parse_seqids -dbtype nucl");
		my $blast_threads = $self->{'config'}->{'blast_threads'} || 1;
		system(
"$self->{'config'}->{'blast+_path'}/blastn -task blastn -num_threads $blast_threads -max_target_seqs 1000 -parse_deflines -db $fasta_file -out $results_file -query $probe_fasta_file -outfmt 6 -dust no"
		);
	} else {
		my $seq_count = scalar @$probes;
		system("$self->{'config'}->{'blast_path'}/formatdb -i $fasta_file -p F -o T");
		system(
"$self->{'config'}->{'blast_path'}/blastall -B $seq_count -b 1000 -p blastn -d $fasta_file -i $probe_fasta_file -o $results_file -m8 -F F 2> /dev/null"
		);
	}
	my @matches;
	if ( -e $results_file ) {
		open( $fh, '<', $results_file );
		while (<$fh>) {
			my @record = split /\t/, $_;
			my $match;
			$match->{'probe_id'}  = $record[0];
			$match->{'seqbin_id'} = $record[1];
			$match->{'alignment'} = $record[3];
			next if $match->{'alignment'} < $probe_info{ $match->{'probe_id'} }->{'min_alignment'};
			$match->{'mismatches'} = $record[4];
			next if $match->{'mismatches'} > $probe_info{ $match->{'probe_id'} }->{'max_mismatch'};
			$match->{'gaps'} = $record[5];
			next if $match->{'gaps'} > $probe_info{ $match->{'probe_id'} }->{'max_gaps'};

			if ( $record[8] < $record[9] ) {
				$match->{'start'} = $record[8];
				$match->{'end'}   = $record[9];
			} else {
				$match->{'start'} = $record[9];
				$match->{'end'}   = $record[8];
			}
			$logger->debug("Seqbin: $match->{'seqbin_id'}; Start: $match->{'start'}; End: $match->{'end'}");
			push @matches, $match;
		}
		close $fh;
		unlink $results_file;
	}
	unlink $probe_fasta_file;
	return \@matches;
}

sub _probe_filter_match {
	my ( $self, $locus, $blast_match, $probe_matches ) = @_;
	my $good_match = 0;
	my %probe_info;
	foreach (@$probe_matches) {
		if ( !$probe_info{ $_->{'probe_id'} } ) {
			$probe_info{ $_->{'probe_id'} } =
			  $self->{'datastore'}
			  ->run_simple_query_hashref( "SELECT * FROM probe_locus WHERE locus=? AND probe_id=?", $locus, $_->{'probe_id'} );
		}
		next if $blast_match->{'seqbin_id'} != $_->{'seqbin_id'};
		my $probe_distance = -1;
		if ( $blast_match->{'start'} > $_->{'end'} ) {
			$probe_distance = $blast_match->{'start'} - $_->{'end'};
		}
		if ( $blast_match->{'end'} < $_->{'start'} ) {
			my $end_distance = $_->{'start'} - $blast_match->{'end'};
			if ( ( $end_distance < $probe_distance ) || ( $probe_distance == -1 ) ) {
				$probe_distance = $end_distance;
			}
		}
		next if ( $probe_distance > $probe_info{ $_->{'probe_id'} }->{'max_distance'} ) || $probe_distance == -1;
		$logger->debug("Probe distance: $probe_distance");
		return 1;
	}
	return 0;
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
1;
