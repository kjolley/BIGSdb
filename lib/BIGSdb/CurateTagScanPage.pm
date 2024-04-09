#Written by Keith Jolley
#Copyright (c) 2010-2024, University of Oxford
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
package BIGSdb::CurateTagScanPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage BIGSdb::TreeViewPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use List::MoreUtils qw(uniq any none);
use Try::Tiny;
use Time::Duration;
use BIGSdb::Constants qw(:interface SEQ_METHODS SEQ_FLAGS LOCUS_PATTERN);
use BIGSdb::Offline::Scan;
##DEFAUT SCAN PARAMETERS#############
my $MIN_IDENTITY             = 70;
my $MIN_ALIGNMENT            = 50;
my $WORD_SIZE                = 20;
my $PARTIAL_MATCHES          = 1;
my $LIMIT_MATCHES            = 200;
my $LIMIT_TIME               = 5;
my $PARTIAL_WHEN_EXACT       = 'off';
my $LOCI_TOGETHER            = 'off';
my $TBLASTX                  = 'off';
my $HUNT_START               = 'off';
my $HUNT_STOP                = 'off';
my $HUNT_STOP_PERCENT        = 5;
my $CHECK_INCOMPLETE         = 'on';
my $CHECK_INCOMPLETE_PERCENT = 100;
my $OVERRIDE_VIEW            = 'off';
my $RESCAN_ALLELES           = 'off';
my $RESCAN_SEQS              = 'off';
my $TYPE_ALLELES             = 'off';
my $MARK_MISSING             = 'off';

sub get_javascript {
	my ($self) = @_;
	my %check_values = ( on => 'true', off => 'false' );
	my $buffer;
	if ( !$self->{'cgi'}->param('tag') ) {
		$buffer .= << "END";
\$(function () {	
	\$("html, body").animate({ scrollTop: \$(document).height()-\$(window).height() });	
	\$(window).on('resize scroll', function() {
		render_multiselect();
	});
	\$("div.scrollable").on('scroll', function() {
		render_multiselect();
	});
	render_multiselect();
});	

function render_multiselect(){
	\$('.multiselect:inViewport').multiselect({
		selectedList: 1,
		header: false,
		noneSelectedText: '',
		menuHeight: 250,
		classes: 'filter'	
	});
	\$('.multiselect:inViewport').multiselect("refresh");
}

\$.expr[':'].inViewport = function (el) {
	el.style.display = '';
    var rect = el.getBoundingClientRect();
    return (
        rect.top >= 0 &&
        rect.left >= 0 &&
        rect.bottom <= (window.innerHeight || document.documentElement.clientHeight) &&
        rect.right <= (window.innerWidth || document.documentElement.clientWidth)
    );
};		
END
	}
	my $q = $self->{'cgi'};
	return $buffer if $q->param('submit');    #Process has forked - cannot make database calls.
	$buffer .= $self->get_list_javascript;
	$buffer .= << "END";
function use_defaults() {
	\$("#identity").val($MIN_IDENTITY);
	\$("#alignment").val($MIN_ALIGNMENT);
	\$("#word_size").val($WORD_SIZE);
	\$("#partial_matches").val($PARTIAL_MATCHES);
	\$("#limit_matches").val($LIMIT_MATCHES);
	\$("#limit_time").val($LIMIT_TIME);
	\$("#loci_together").prop(\"checked\",$check_values{$LOCI_TOGETHER});
	\$("#tblastx").prop(\"checked\",$check_values{$TBLASTX});
	\$("#hunt_start").prop(\"checked\",$check_values{$HUNT_START});
	\$("#hunt_stop").prop(\"checked\",$check_values{$HUNT_STOP});
	\$("#hunt_stop_percent").val($HUNT_STOP_PERCENT);
	\$("#check_incomplete").prop(\"checked\",$check_values{$CHECK_INCOMPLETE});
	\$("#check_incomplete_percent").val($CHECK_INCOMPLETE_PERCENT);
	\$("#partial_when_exact").prop(\"checked\",$check_values{$PARTIAL_WHEN_EXACT});
	\$("#override_view").prop(\"checked\",$check_values{$OVERRIDE_VIEW});
	\$("#rescan_alleles").prop(\"checked\",$check_values{$RESCAN_ALLELES});
	\$("#rescan_seqs").prop(\"checked\",$check_values{$RESCAN_SEQS});
	\$("#type_alleles").prop(\"checked\",$check_values{$TYPE_ALLELES});
	\$("#mark_missing").prop(\"checked\",$check_values{$MARK_MISSING});
}
	
END
	$buffer .= $self->get_tree_javascript( { checkboxes => 1, check_schemes => 1 } );
	return $buffer;
}

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/curator_guide/0180_web_based_scanning.html";
}

sub _get_refresh_time {
	my ( $self, $elapsed ) = @_;
	my %refresh_by_elapsed = ( 120 => 5, 300 => 10, 600 => 30, 3600 => 60 );
	my $refresh;
	foreach my $mins ( sort { $a <=> $b } keys %refresh_by_elapsed ) {
		if ( $elapsed < $mins ) {
			$refresh = $refresh_by_elapsed{$mins};
			last;
		}
	}
	$refresh //= 300;
	return $refresh;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (tooltips jQuery jQuery.jstree jQuery.multiselect noCache allowExpand);
	$self->set_level1_breadcrumbs;
	my $q = $self->{'cgi'};
	if ( $q->param('submit') ) {
		my $loci        = $self->_get_selected_loci;
		my @isolate_ids = split( "\0", ( $q->param('isolate_id') // '' ) );
		my ( $pasted_cleaned_ids, $invalid_ids ) = $self->get_ids_from_pasted_list( { dont_clear => 1 } );
		push @isolate_ids, @$pasted_cleaned_ids;
		@isolate_ids = uniq @isolate_ids;
		return if !@$loci || !@isolate_ids;
	}
	if ( $q->param('submit') || $q->param('results') ) {
		$self->{'scan_job'} = $q->param('scan') || BIGSdb::Utils::get_random();
		my $scan_job = $self->{'scan_job'} =~ /^(BIGSdb_[0-9_]+)$/x ? $1 : undef;
		my $status   = $self->_read_status($scan_job);
		return if $status->{'server_busy'};
		if ( !$status->{'stop_time'} ) {
			if ( $status->{'start_time'} ) {
				if ( !$q->param('results') ) {
					$self->{'refresh'} = 5;
				} else {
					my $elapsed = time - $status->{'start_time'};
					$self->{'refresh'} = $self->_get_refresh_time($elapsed);
				}
			} else {
				$self->{'refresh'} = 5;
			}
			if ( $status->{'request_stop'} ) {
				$self->{'refresh'} = 1;
			}
			$self->{'refresh_page'} = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;"
			  . "page=tagScan&amp;scan=$scan_job&amp;results=1";
		}
		if ( $q->param('stop') ) {
			$self->_request_stop($scan_job);
			$self->{'refresh'} = 1 if !$status->{'stop_time'};
		}
	}
	if ( $q->param('parameters') ) {
		my $scan_job = $q->param('parameters');
		my $filename = "$self->{'config'}->{'secure_tmp_dir'}/${scan_job}_parameters";
		if ( -e $filename ) {
			open( my $fh, '<', $filename ) || $logger->error("Can't open $filename for reading");
			my $temp_q = CGI->new( \*$fh );    # Temp CGI object to read in parameters
			close $fh;
			my $params = $temp_q->Vars;
			foreach my $key ( keys %$params ) {
				next if any { $key eq $_ } qw (submit);
				$q->param( $key => $temp_q->multi_param($key) );
			}
		}
	}
	return;
}

sub _request_stop {
	my ( $self, $scan_job ) = @_;
	my $status_file = "$self->{'config'}->{'secure_tmp_dir'}/$scan_job\_status.txt";
	open( my $fh, '>>', $status_file ) || $logger->error("Can't open $status_file for appending");
	say $fh 'request_stop:1';
	close $fh;
	return;
}

sub _print_interface {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $ids, $labels ) = $self->get_isolates_with_seqbin;
	if ( !@$ids ) {
		$self->print_bad_status( { message => q(This database view contains no genomes.) } );
		return;
	} elsif ( !$self->can_modify_table('allele_sequences') ) {
		$self->print_bad_status( { message => q(Your user account is not allowed to tag sequences.) } );
		return;
	}
	say q(<div class="box" id="queryform">);
	say $self->get_form_icon( 'allele_sequences', 'scan' );
	say q(<p style="margin-right:10%">Please select the required isolate ids and loci for sequence scanning - )
	  . q(use Ctrl or Shift to make multiple selections. In addition to selecting individual loci, you can choose )
	  . q(to include all loci defined in schemes by selecting the appropriate scheme description. By default, loci )
	  . q(are only scanned for an isolate when no allele designation has been made or sequence tagged. You can )
	  . q(choose to rescan loci with existing designations or tags by selecting the appropriate options.</p>);
	my $guid = $self->get_guid;
	my $general_prefs;
	if ($guid) {
		$general_prefs = $self->{'prefstore'}->get_all_general_prefs( $guid, $self->{'system'}->{'db'} );
	}
	if ( $q->param('datatype') && $q->param('list_file') ) {
		$self->{'datastore'}->create_temp_list_table( scalar $q->param('datatype'), scalar $q->param('list_file') );
	}
	my $query_file = $q->param('query_file');
	my $query      = $self->get_query_from_temp_file($query_file);
	my $selected_ids;
	if ( $q->param('isolate_id') ) {
		my @ids = $q->multi_param('isolate_id');
		$selected_ids = \@ids;
	} elsif ( defined $query ) {
		$selected_ids = $self->_get_ids($query);
	} else {
		$selected_ids = [];
	}
	say $q->start_form;
	say q(<div class="scrollable">);
	say q(<div class="flex_container" style="justify-content:left">);
	$self->print_seqbin_isolate_fieldset(
		{ selected_ids => $selected_ids, size => 11, isolate_paste_list => 1, only_genomes => 1 } );
	my @selected_loci = $q->multi_param('locus');
	$self->print_isolates_locus_fieldset(
		{ selected_loci => \@selected_loci, locus_paste_list => 1, size => 11, analysis_pref => 0 } );
	say q(<fieldset><legend>Schemes</legend>);
	say q(<noscript><p class="highlight">Enable Javascript to select schemes.</p></noscript>);
	say q(<div id="tree" class="tree" style="height:220px; width:20em">);
	say $self->get_tree( undef, { no_link_out => 1, select_schemes => 1, analysis_pref => 1 } );
	say q(</div></fieldset>);
	$self->_print_parameter_fieldset($general_prefs);

	#Only show repetitive loci fields if PCR or probe locus links have been set
	my $pcr_links   = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM pcr_locus)');
	my $probe_links = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM probe_locus)');
	if ( $pcr_links + $probe_links ) {
		say q(<fieldset><legend>Repetitive loci</legend>);
		say q(<ul>);
		if ($pcr_links) {
			say q(<li>);
			say $q->checkbox( -name => 'pcr_filter', -label => 'Filter by PCR', -checked => 'checked' );
			say $self->get_tooltip( q(Filter by PCR - Loci can be defined by a simulated PCR reaction(s) )
				  . q(so that only regions of the genome predicted to be amplified will be recognised in the scan. )
				  . q(De-selecting this option will ignore this filter and the whole sequence bin will be scanned )
				  . q(instead.  Partial matches will also be returned (up to the number set in the parameters) even )
				  . q(if exact matches are found.  De-selecting this option will be necessary if the gene in question )
				  . q(is incomplete due to being located at the end of a contig since it cannot then be bounded by )
				  . q(PCR primers.) );
			say q(</li><li><label for="alter_pcr_mismatches" class="parameter">&Delta; PCR mismatch:</label>);
			say $q->popup_menu(
				-name    => 'alter_pcr_mismatches',
				-id      => 'alter_pcr_mismatches',
				-values  => [qw (-3 -2 -1 0 +1 +2 +3)],
				-default => 0
			);
			say $self->get_tooltip( q(Change primer mismatch - Each defined PCR reaction will have a )
				  . q(parameter specifying the allowed number of mismatches per primer. You can increase or decrease )
				  . q(this value here, altering the stringency of the reaction.) );
			say q(</li>);
		}
		if ($probe_links) {
			say q(<li>);
			say $q->checkbox( -name => 'probe_filter', -label => 'Filter by probe', -checked => 'checked' );
			say $self->get_tooltip( q(Filter by probe - Loci can be defined by a simulated hybridization )
				  . q(reaction(s) so that only regions of the genome predicted to be within a set distance of a )
				  . q(hybridization sequence will be recognised in the scan. De-selecting this option will ignore this )
				  . q(filter and the whole sequence bin will be scanned instead.  Partial matches will also be returned )
				  . q((up to the number set in the parameters) even if exact matches are found.) );
			say q(</li><li><label for="alter_probe_mismatches" class="parameter">&Delta; Probe mismatch:</label>);
			say $q->popup_menu(
				-name    => 'alter_probe_mismatches',
				-id      => 'alter_probe_mismatches',
				-values  => [qw (-3 -2 -1 0 +1 +2 +3)],
				-default => 0
			);
			say $self->get_tooltip( q(Change probe mismatch - Each hybridization reaction will have a )
				  . q(parameter specifying the allowed number of mismatches. You can increase or decrease this value )
				  . q(here, altering the stringency of the reaction.) );
			say q(</li>);
		}
		say q(</ul></fieldset>);
	}
	say q(<fieldset><legend>Restrict included sequences by</legend>);
	say q(<ul>);
	my $buffer = $self->get_sequence_method_filter( { class => 'parameter' } );
	say qq(<li>$buffer</li>) if $buffer;
	$buffer = $self->get_project_filter( { class => 'parameter' } );
	say qq(<li>$buffer</li>) if $buffer;
	say q(</ul></fieldset>);
	say q(</div>);
	$self->print_action_fieldset( { submit_label => 'Scan' } );
	say q(</div>);
	say $q->hidden($_) foreach qw (page db);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _print_parameter_fieldset {
	my ( $self, $general_prefs ) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="position:relative"><legend>Parameters</legend>)
	  . q(<input type="button" class="small_submit" style="position:absolute;right:6em;z-index:1" )
	  . q(value="Defaults" onclick="use_defaults()" />)
	  . q(<ul><li><label for="identity" class="parameter">Min % identity:</label>);
	say $q->popup_menu(
		-name    => 'identity',
		-id      => 'identity',
		-values  => [ 50 .. 100 ],
		-default => $general_prefs->{'scan_identity'} // $MIN_IDENTITY
	);
	say $self->get_tooltip(q(Minimum % identity - Match required for partial matching.));
	say q(</li><li><label for="alignment" class="parameter">Min % alignment:</label>);
	say $q->popup_menu(
		-name    => 'alignment',
		-id      => 'alignment',
		-values  => [ 30 .. 100 ],
		-default => $general_prefs->{'scan_alignment'} // $MIN_ALIGNMENT
	);
	say $self->get_tooltip( q(Minimum % alignment - Percentage of allele sequence length )
		  . q(required to be aligned for partial matching.) );
	say q(</li><li><label for="word_size" class="parameter">BLASTN word size:</label>);
	say $q->popup_menu(
		-name    => 'word_size',
		-id      => 'word_size',
		-values  => [ 7 .. 30 ],
		-default => $general_prefs->{'scan_word_size'} // $WORD_SIZE
	);
	say $self->get_tooltip( q(BLASTN word size - This is the length of an exact match required )
		  . q(to initiate an extension. Larger values increase speed at the expense of sensitivity.) );
	say q(</li><li><label for="partial_matches" class="parameter">Return up to:</label>);
	say $q->popup_menu(
		-name    => 'partial_matches',
		-id      => 'partial_matches',
		-values  => [ 1 .. 10 ],
		-default => $general_prefs->{'scan_partial_matches'} // $PARTIAL_MATCHES
	);
	say q( partial match(es)</li><li><label for="limit_matches" class="parameter">Stop after:</label>);
	say $q->popup_menu(
		-name    => 'limit_matches',
		-id      => 'limit_matches',
		-values  => [qw(10 20 30 40 50 100 200 500 1000 2000 5000 10000 20000)],
		-default => $general_prefs->{'scan_limit_matches'} // $LIMIT_MATCHES
	);
	say q( new matches);
	say $self->get_tooltip( q(Stop after matching - Limit the number of previously )
		  . q(undesignated matches. You may wish to terminate the search after finding a set number of new )
		  . q(matches.  You will be able to tag any sequences found and next time these won't be searched )
		  . q((by default) so this enables you to tag in batches. If scanning all loci together you may get )
		  . q(more results than this as it will complete the scan for an isolate and return all results found )
		  . q(so far.) );
	say q(</li><li><label for="limit_time" class="parameter">Stop after:</label>);
	say $q->popup_menu(
		-name    => 'limit_time',
		-id      => 'limit_time',
		-values  => [qw(1 2 5 10 15 30 60 120 180 240 300)],
		-default => $general_prefs->{'scan_limit_time'} // $LIMIT_TIME
	);
	say q( minute(s));
	say $self->get_tooltip( q(Stop after time - Searches against lots of loci or for )
		  . q(multiple isolates may take a long time. You may wish to terminate the search after a set time.  )
		  . q(You will be able to tag any sequences found and next time these won't be searched (by default) so )
		  . q(this enables you to tag in batches.) );
	say q(</li><li>);

	if ( ( $self->{'system'}->{'fast_scan'} // q() ) eq 'yes' ) {
		say $q->checkbox(
			-name    => 'loci_together',
			-id      => 'loci_together',
			-label   => 'Scan selected loci together',
			-checked => ( ( $general_prefs->{'scan_loci_together'} // q() ) eq 'on' )
			? 'checked'
			: ''
		);
		say $self->get_tooltip( q(Scan loci together - This should be quicker if scanning multiple loci but it )
			  . q(will take longer for the first results to be returned. This scan uses defined exemplar alleles to reduce )
			  . q(the search space. This is less sensitive than scanning all alleles, so it may miss some matches.) );
		say q(</li><li>);
	}
	if ( ( $self->{'system'}->{'tblastx_tagging'} // q() ) eq 'yes' ) {
		say q(<li><span class="warning">);
		say $q->checkbox(
			-name    => 'tblastx',
			-id      => 'tblastx',
			-label   => 'Use TBLASTX',
			-checked => ( ( $general_prefs->{'scan_tblastx'} // q() ) eq 'on' )
			? 'checked'
			: ''
		);
		say $self->get_tooltip( q(TBLASTX - Compares the six-frame translation of your nucleotide )
			  . q(query against the six-frame translation of the sequences in the sequence bin.  This can be )
			  . q(VERY SLOW (a few minutes for each comparison). Use with caution.<br /><br />Partial matches )
			  . q(may be indicated even when an exact match is found if the matching allele contains a partial )
			  . q(codon at one of the ends.  Identical matches will be indicated if the translated sequences )
			  . q(match even if the nucleotide sequences don't. For this reason, allele designation tagging is )
			  . q(disabled for TBLASTX matching.) );
		say q(</li>);
	}
	say q(<li>);
	say $q->checkbox(
		-name    => 'hunt_start',
		-id      => 'hunt_start',
		-label   => 'Hunt for nearby start codons',
		-checked => ( ( $general_prefs->{'scan_hunt_start'} // q() ) eq 'on' )
		? 'checked'
		: ''
	);
	say $self->get_tooltip( q(Hunt for start codons - If the aligned sequence is not an )
		  . q(exact match to an existing allele and is not a complete coding sequence with start and stop )
		  . q(codons at the ends, selecting this option will hunt for a start codon by walking in and out from the )
		  . q(end in complete codons for up to 6 amino acids.) );
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'hunt_stop',
		-id      => 'hunt_stop',
		-label   => 'Hunt for stop codons within ',
		-checked => ( ( $general_prefs->{'scan_hunt_stop'} // q() ) eq 'on' )
		? 'checked'
		: ''
	);
	say $q->popup_menu(
		-name    => 'hunt_stop_percent',
		-id      => 'hunt_stop_percent',
		-values  => [ 1 .. 25 ],
		-default => $general_prefs->{'scan_hunt_stop_percent'} // 5
	);
	say q(% length difference of match);
	say $self->get_tooltip( q(Hunt for stop codons - If the aligned sequence is not an )
		  . q(exact match to an existing allele and is not a complete coding sequence with start and stop )
		  . q(codons at the ends, selecting this option will hunt for an in-frame stop codon within the )
		  . q(specified %distance (either longer or shorter) of the matched allele length.) );
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'check_incomplete',
		-id      => 'check_incomplete',
		-label   => q(Check 'tag sequence' box for incomplete alleles matching at ),
		-checked => ( ( $general_prefs->{'scan_check_incomplete'} // 'on' ) eq 'on' )
		? 'checked'
		: ''
	);
	say $q->popup_menu(
		-name    => 'check_incomplete_percent',
		-id      => 'check_incomplete_percent',
		-values  => [ 90 .. 100 ],
		-default => $general_prefs->{'scan_check_incomplete_percent'} // 100
	);
	say q(% identity to closest allele);
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'partial_when_exact',
		-id      => 'partial_when_exact',
		-label   => 'Return partial matches even when exact matches are found',
		-checked => ( ( $general_prefs->{'scan_partial_when_exact'} // q() ) eq 'on' )
		? 'checked'
		: q()
	);
	say q(</li><li>);

	if ( $self->{'system'}->{'views'} ) {
		say $q->checkbox(
			-name    => 'override_view',
			-id      => 'override_view',
			-label   => 'Override locus view restrictions',
			-checked => ( ( $general_prefs->{'scan_override_view'} // q() ) eq 'on' )
			? 'checked'
			: q()
		);
		say $self->get_tooltip( q[Override view restriction - Some loci are restricted by an isolate view so that ]
			  . q[only isolates that belong to a view will be scanned against them (this is used, for example, to restrict ]
			  . q[some loci to only particular species or types). Select to override this restriction.] );
		say q(</li><li>);
	}
	say $q->checkbox(
		-name    => 'rescan_alleles',
		-id      => 'rescan_alleles',
		-label   => 'Rescan even if allele designations are already set',
		-checked => ( ( $general_prefs->{'scan_rescan_alleles'} // q() ) eq 'on' )
		? 'checked'
		: q()
	);
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'rescan_seqs',
		-id      => 'rescan_seqs',
		-label   => 'Rescan even if allele sequences are tagged',
		-checked => ( ( $general_prefs->{'scan_rescan_seqs'} // q() ) eq 'on' )
		? 'checked'
		: q()
	);
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'type_alleles',
		-id      => 'type_alleles',
		-label   => 'Use only type alleles to identify locus',
		-checked => ( ( $general_prefs->{'scan_type_alleles'} // q() ) eq 'on' )
		? 'checked'
		: q()
	);
	say $self->get_tooltip( q(Type alleles - Constrain the search space to contain only type alleles. These )
		  . q(are defined in the sequence record. This can prevent more variable alleles being defined over time. )
		  . q(If the locus region is identified then a full database lookup will be used to identify a known allele.)
		  . q(<br /><br />)
		  . q(Note that if no type alleles have been defined then you will not find any matches!) );
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'mark_missing',
		-id      => 'mark_missing',
		-label   => q(Mark missing sequences as provisional allele '0'),
		-checked => ( ( $general_prefs->{'scan_mark_missing'} // q() ) eq 'on' )
		? 'checked'
		: q()
	);
	say q(</li></ul></fieldset>);
	return;
}

sub _get_selected_loci {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my @loci   = $q->multi_param('locus');
	my ( $pasted_cleaned_loci, $invalid_loci ) = $self->get_loci_from_pasted_list;
	push @loci, "l_$_" foreach @$pasted_cleaned_loci;
	$q->param( locus => @loci );
	$self->_add_scheme_loci( \@loci );
	@loci = uniq sort @loci;
	return \@loci;
}

sub _scan {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $time_limit = ( int( $q->param('limit_time') ) || 5 ) * 60;
	my $loci       = $self->_get_selected_loci;
	my @ids        = $q->multi_param('isolate_id');
	my ( $pasted_cleaned_ids, $invalid_ids ) = $self->get_ids_from_pasted_list;
	push @ids, @$pasted_cleaned_ids;
	@ids = uniq sort { $a <=> $b } @ids;
	$q->param( isolate_id => @ids );

	if ( !@ids ) {
		$self->print_bad_status( { message => q(You must select one or more isolates.) } );
		$self->_print_interface;
		return;
	}
	if ( !@$loci ) {
		$self->print_bad_status( { message => q(You must select one or more loci or schemes.) } );
		$self->_print_interface;
		return;
	}

	#Store scan attributes in pref database
	my $guid = $self->get_guid;
	if ($guid) {
		my $dbname = $self->{'system'}->{'db'};
		foreach (
			qw (identity alignment word_size partial_matches limit_matches limit_time
			tblastx hunt_start hunt_stop hunt_stop_percent partial_when_exact check_incomplete
			check_incomplete_percent override_view rescan_alleles rescan_seqs type_alleles
			mark_missing loci_together)
		  )
		{
			my $value = ( defined $q->param($_) && $q->param($_) ne '' ) ? $q->param($_) : 'off';
			$self->{'prefstore'}->set_general( $guid, $dbname, "scan_$_", $value );
		}
	}
	my $limit =
	  BIGSdb::Utils::is_int( scalar $q->param('limit_matches') )
	  ? $q->param('limit_matches')
	  : $LIMIT_MATCHES;
	my $scan_job = $self->{'scan_job'} =~ /^(BIGSdb_[0-9_]+)$/x ? $1 : undef;
	$self->_save_parameters($scan_job);
	my $project_id   = $q->param('project_list');
	my $curator_name = $self->get_curator_name;
	my $user_info    = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my ( undef, $labels ) = $self->get_isolates_with_seqbin( { hyperlink => 1 } );

	#Use double fork to prevent zombie processes on apache2-mpm-worker
	defined( my $kid = fork ) or $logger->error('cannot fork');
	if ($kid) {
		waitpid( $kid, 0 );
	} else {
		defined( my $grandkid = fork ) or $logger->error('Kid cannot fork');
		if ($grandkid) {
			CORE::exit(0);
		} else {
			open STDIN,  '<', '/dev/null' || $logger->error("Can't detach STDIN: $!");
			open STDOUT, '>', '/dev/null' || $logger->error("Can't detach STDOUT: $!");
			open STDERR, '>&STDOUT' || $logger->error("Can't detach STDERR: $!");
			my $options = {
				labels                       => $labels,
				limit                        => $limit,
				time_limit                   => $time_limit,
				loci                         => $loci,
				project_id                   => $project_id,
				scan_job                     => $scan_job,
				script_name                  => $self->{'system'}->{'script_name'},
				curator_name                 => $curator_name,
				throw_webscan_busy_exception => 1
			};
			my $params = $q->Vars;
			$params->{'ip_address'} = $ENV{'REMOTE_ADDR'};
			$params->{'username'}   = $self->{'username'};
			$params->{'email'}      = $user_info->{'email'};
			$params->{'scannew'}    = 1;

			if ( $params->{'loci_together'} ) {
				$params->{'exemplar'}             = 1;
				$params->{'scan_partial_matches'} = 100;
			}
			try {
				my $scan = BIGSdb::Offline::Scan->new(
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
				$scan->db_disconnect;
			} catch {
				if ( $_->isa('BIGSdb::Exception::Server::Busy') ) {
					my $status_file = "$self->{'config'}->{'secure_tmp_dir'}/$scan_job\_status.txt";
					open( my $fh, '>', $status_file ) || $logger->error("Can't open $status_file for writing");
					say $fh 'server_busy:1';
					close $fh;
				} else {
					$logger->logdie($_);
				}
			};
			CORE::exit(0);
		}
	}
	say q(<div class="box" id="resultsheader"><p>You will be forwarded to the results page shortly.  Click )
	  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagScan&amp;)
	  . qq(scan=$scan_job&amp;results=1\">here</a> if you're not.</p></div>);
	return;
}

sub _tag {
	my ($self) = @_;
	my ( @updates, @allele_updates, @sequence_updates, $history );
	my ( undef, $labels ) = $self->get_isolates_with_seqbin;
	my $q                 = $self->{'cgi'};
	my $curator_id        = $self->get_curator_id;
	my $scan_job          = $q->param('scan');
	my $match_list        = $self->_read_matches($scan_job);
	my $designation_added = {};

	foreach my $match (@$match_list) {
		if ( $match =~ /^(\d+):(.+):(\d+)$/x ) {
			my ( $isolate_id, $locus, $id ) = ( $1, $2, $3 );
			next if !$self->is_allowed_to_view_isolate($isolate_id);
			my $display_locus = $self->clean_locus($locus);
			my $seqbin_id     = $q->param("id_$isolate_id\_$locus\_seqbin_id_$id");
			if ( $q->param("id_$isolate_id\_$locus\_allele_$id")
				&& defined $q->param("id_$isolate_id\_$locus\_allele_id_$id") )
			{
				my $allele_id      = $q->param("id_$isolate_id\_$locus\_allele_id_$id");
				my $set_allele_ids = $self->{'datastore'}->get_allele_ids( $isolate_id, $locus );
				my $seqbin_sender;
				if ($seqbin_id) {    #Seqbin id may not exist if scanning for missing alleles.
					$seqbin_sender = $self->{'datastore'}->run_query( 'SELECT sender FROM sequence_bin WHERE id=?',
						$seqbin_id, { cache => 'CurateTagScanPage::tag::seqbin_sender' } );
				}
				my $sender = $seqbin_sender // $self->get_curator_id;
				my $status = $allele_id ? 'confirmed' : 'provisional';
				if ( ( none { $allele_id eq $_ } @$set_allele_ids )
					&& !$designation_added->{$isolate_id}->{$locus}->{$allele_id} )
				{
					push @updates,
					  {
						statement =>
						  'INSERT INTO allele_designations (isolate_id,locus,allele_id,sender,status,method,curator,'
						  . 'date_entered,datestamp,comments) VALUES (?,?,?,?,?,?,?,?,?,?)',
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
				my $start  = $q->param("id_$isolate_id\_$locus\_start_$id");
				my $end    = $q->param("id_$isolate_id\_$locus\_end_$id");
				my $exists = $self->{'datastore'}->run_query(
					'SELECT EXISTS(SELECT * FROM allele_sequences WHERE '
					  . '(seqbin_id,locus,start_pos,end_pos)=(?,?,?,?))',
					[ $seqbin_id, $locus, $start, $end ],
					{ cache => 'CurateTagScanPage::tag::sequence_exists' }
				);
				next if $exists;
				my $reverse  = $q->param("id_$isolate_id\_$locus\_reverse_$id")  ? 'TRUE' : 'FALSE';
				my $complete = $q->param("id_$isolate_id\_$locus\_complete_$id") ? 'TRUE' : 'FALSE';
				push @updates,
				  {
					statement => 'INSERT INTO allele_sequences (seqbin_id,locus,start_pos,end_pos,reverse,'
					  . 'complete,curator,datestamp) VALUES (?,?,?,?,?,?,?,?)',
					arguments => [ $seqbin_id, $locus, $start, $end, $reverse, $complete, $curator_id, 'now' ]
				  };
				push @sequence_updates,
				  ( $labels->{$isolate_id} || $isolate_id ) . ": $display_locus:  Seqbin id: $seqbin_id; $start-$end";
				push @{ $history->{$isolate_id} },
				  "$locus: sequence tagged. Seqbin id: $seqbin_id; $start-$end (sequence bin scan)";
				my $args = {
					isolate_id => $isolate_id,
					locus      => $locus,
					id         => $id,
					seqbin_id  => $seqbin_id,
					start      => $start,
					end        => $end,
					updates    => \@updates
				};
				$self->_add_flag_updates($args);
				$self->_add_intron_updates($args);
			}
		}
	}
	if (@updates) {
		eval {
			foreach my $update (@updates) {
				$self->{'db'}->do( $update->{'statement'}, undef, @{ $update->{'arguments'} } );
			}
		};
		if ($@) {
			my $err = $@;
			my $detail;
			if ( $err =~ /duplicate/ && $err =~ /unique/ ) {
				$detail = q(Data entry would have resulted in records with either duplicate ids )
				  . q(or another unique field with duplicate values.);
			} else {
				$logger->error($err);
			}
			$self->print_bad_status(
				{
					message => q(Database update failed - transaction cancelled - no records have been touched.),
					detail  => $detail
				}
			);
			$self->{'db'}->rollback;
			return;
		} else {
			$self->{'db'}->commit;
			$self->print_good_status(
				{
					message    => 'Database updated.',
					navbar     => 1,
					reload_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagScan&amp;)
					  . qq(parameters=$scan_job)
				}
			);
			say q(<div class="box" id="resultstable">);
			local $" = qq(<br />\n);
			if (@allele_updates) {
				say q(<h2>Allele designations set</h2>);
				say qq(<p>@allele_updates</p>);
			}
			if (@sequence_updates) {
				say q(<h2>Allele sequences set</h2>);
				say qq(<p>@sequence_updates</p>);
			}
			if ( ref $history eq 'HASH' ) {
				foreach ( keys %$history ) {
					my @message = @{ $history->{$_} };
					local $" = q(<br />);
					$self->update_history( $_, "@message" );
				}
			}
			say q(</div>);
		}
	} else {
		$self->print_bad_status(
			{
				message    => q(No updates required.),
				navbar     => 1,
				reload_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagScan&amp;)
				  . qq(parameters=$scan_job)
			}
		);
	}
	return;
}

sub _add_flag_updates {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $locus, $id, $seqbin_id, $start, $end, $updates ) =
	  @{$args}{qw(isolate_id locus id seqbin_id start end updates)};
	my $q     = $self->{'cgi'};
	my @flags = $q->multi_param("id_${isolate_id}_${locus}_sequence_${id}_flag");
	return if !@flags;
	my $curator_id = $self->get_curator_id;

	#Need to find out the autoincrementing id for the just added tag
	foreach my $flag (@flags) {
		next if $flag eq q();
		push @$updates,
		  {
			statement => 'INSERT INTO sequence_flags (id,flag,datestamp,curator) SELECT allele_sequences.id,'
			  . '?,?,? FROM allele_sequences WHERE (seqbin_id,locus,start_pos,end_pos)=(?,?,?,?)',
			arguments => [ $flag, 'now', $curator_id, $seqbin_id, $locus, $start, $end ]
		  };
	}
	return;
}

sub _add_intron_updates {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $locus, $id, $seqbin_id, $start, $end, $updates ) =
	  @{$args}{qw(isolate_id locus id seqbin_id start end updates)};
	my $q       = $self->{'cgi'};
	my $introns = $q->param("id_${isolate_id}_${locus}_introns_$id") // q();
	return if !$introns;
	my @introns = split /,/x, $introns;
	foreach my $intron (@introns) {
		if ( $intron =~ /^(\d+)\-(\d+)$/x ) {
			my $intron_start = $1;
			my $intron_end   = $2;
			next if $intron_start > $intron_end;
			push @$updates,
			  {
				statement => 'INSERT INTO introns (id,start_pos,end_pos) SELECT allele_sequences.id,?,? '
				  . 'FROM allele_sequences WHERE (seqbin_id,locus,start_pos,end_pos)=(?,?,?,?)',
				arguments => [ $intron_start, $intron_end, $seqbin_id, $locus, $start, $end ]
			  };
		}
	}
	return;
}

sub _show_results {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $scan_job = $q->param('scan');
	$scan_job = $scan_job =~ /^(BIGSdb_[0-9_]+)$/x ? $1 : undef;
	if ( !defined $scan_job ) {
		$self->print_bad_status( { message => q(Invalid job id passed.) } );
		return;
	}
	my $filename = "$self->{'config'}->{'secure_tmp_dir'}/$scan_job\_table.html";
	my $status   = $self->_read_status($scan_job);
	if ( $status->{'server_busy'} ) {
		$self->print_bad_status(
			{
				message => q(The server is currently too busy to run your scan. )
				  . q(Please wait a few minutes and then try again.)
			}
		);
		return;
	} elsif ( !$status->{'start_time'} ) {
		$self->print_bad_status( { message => q(The requested job does not exist.) } );
		return;
	}
	say q(<div class="box" id="resultstable">);
	say $q->start_form;
	if ( !-s $filename ) {
		if ( $status->{'stop_time'} ) {
			say q(<p>No matches found.</p>);
			$self->print_navigation_bar(
				{
					reload_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagScan&amp;)
					  . qq(parameters=$scan_job)
				}
			);
		} else {
			say q(<p><span class="wait_icon fas fa-sync-alt fa-spin fa-4x" style="margin-right:0.5em"></span>)
			  . q(<span class="wait_message">No results yet ... Please wait.</span></p>);
		}
	} else {
		say q(<div class="scrollable"><table class="resultstable"><tr><th>Isolate</th><th>Match</th>)
		  . q(<th>Locus</th><th>Allele</th><th>% identity</th><th>Alignment length</th><th>Allele length</th>)
		  . q(<th>E-value</th><th>Sequence bin id</th><th>Start</th><th>End</th><th>Predicted start</th>)
		  . q(<th>Predicted end</th><th>Orientation</th><th>First stop codon</th><th>Designate allele</th>)
		  . q(<th>Tag sequence</th>)
		  . q(<th>Flag);
		say $self->get_tooltip(
			q(Flag - Set a status flag for the sequence.  You need to also )
			  . q(tag the sequence for any flag to take effect.),
			{ style => 'color:white' }
		);
		say q(</th></tr>);
		$self->print_file($filename);
		say q(</table></div>);
		say q(<p>* Allele continues beyond end of contig</p>) if $status->{'allele_off_contig'};
	}
	if ( -s $filename && $status->{'stop_time'} ) {
		if ( $status->{'tag_isolates'} ) {
			my @isolates_to_tag = split /,/x, $status->{'tag_isolates'};
			$q->param( 'isolate_id_list', @isolates_to_tag );
			my @loci = split /,/x, $status->{'loci'};
			$q->param( 'loci', @loci );
			say $q->hidden($_) foreach qw(isolate_id_list loci);
		}
		say $q->hidden($_) foreach qw(db page scan);
		$self->print_action_fieldset(
			{
				no_reset     => 1,
				submit_name  => 'tag',
				submit_label => 'Tag alleles/sequences'
			}
		);
		say q(<div style="clear:both"></div>);
	}
	say $q->end_form;
	if ( $status->{'new_seqs_found'} ) {
		my ( $text_file, $fasta_file ) = ( TEXT_FILE, FASTA_FILE );
		say q(<h2>New unique sequences</h2>);
		say q(<p>Sequences in tabular text or FASTA format can be used to facilitate rapid upload of )
		  . q(new sequences to a sequence definition database for allele assignment.</p>);
		say qq(<p><a href="/tmp/${scan_job}_unique_sequences.txt" title="Tab-delimited text format" )
		  . qq(target="_blank">$text_file</a>)
		  . qq(<a href="/tmp/${scan_job}_unique_sequences.fasta" title="FASTA format" )
		  . qq(target="_blank">$fasta_file</a>);
		say q(</p>);
	}
	say q(</div>);
	say q(<div class="box" id="resultsfooter">);
	my $elapsed      = $status->{'start_time'} ? $status->{'start_time'} - ( $status->{'stop_time'} // time ) : undef;
	my $refresh_time = duration( $self->{'refresh'} );
	my $elapsed_time = $elapsed ? duration($elapsed) : undef;
	if ( $status->{'match_limit_reached'} ) {
		say "<p>Match limit reached (checked up to id-$status->{'last_isolate'}).</p>";
		$self->_request_stop($scan_job);
	} elsif ( $status->{'time_limit_reached'} ) {
		say "<p>Time limit reached (checked up to id-$status->{'last_isolate'}).</p>";
		$self->_request_stop($scan_job);
	}
	say q(<p>);
	say q(<b>Started:</b> ) . scalar localtime( $status->{'start_time'} ) . q(<br />) if $status->{'start_time'};
	say q(<b>Finished:</b> ) . scalar localtime( $status->{'stop_time'} ) . q(<br />) if $status->{'stop_time'};
	say qq(<b>Elapsed time:</b> $elapsed_time)                                        if $elapsed_time;
	say q(</p>);
	if ( !$status->{'stop_time'} ) {
		say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagScan&amp;)
		  . qq(scan=$self->{'scan_job'}&amp;results=1&amp;stop=1" class="reset">Stop job!</a></p>)
		  . q(<p>Clicking this will request that the job )
		  . q(finishes allowing new designations to be made.  Please allow a few seconds for it to stop.</p>);
	}
	if ( $self->{'refresh'} ) {
		say qq(<p>This page will reload in $refresh_time. You can refresh it any time, or bookmark it, )
		  . q(close your browser and return to it later if you wish.</p>);
	}
	if ( BIGSdb::Utils::is_int( $self->{'config'}->{'results_deleted_days'} ) ) {
		say q(<p>Please note that scan results will remain on the server for )
		  . qq($self->{'config'}->{'results_deleted_days'} days.</p></div>);
	} else {
		say q(<p>Please note that scan results will not be stored on the server indefinitely.</p></div>);
	}
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Sequence tag scan</h1>);
	if ( $q->param('tag') ) {
		$self->_tag;
	} elsif ( $q->param('results') ) {
		$self->_show_results;
	} elsif ( $q->param('submit') ) {
		$self->_scan;
	} else {
		$self->_print_interface;
	}
	return;
}

sub get_title {
	return 'Sequence tag scan';
}

sub _add_scheme_loci {
	my ( $self, $loci_ref ) = @_;
	my $q = $self->{'cgi'};
	my $scheme_ids =
	  $self->{'datastore'}->run_query( 'SELECT id FROM schemes ORDER BY id', undef, { fetch => 'col_arrayref' } );
	push @$scheme_ids, 0;    #loci not belonging to a scheme.
	my %locus_selected = map { $_ => 1 } @$loci_ref;
	my $set_id         = $self->get_set_id;
	foreach (@$scheme_ids) {
		next if !$q->param("s_$_");
		my $scheme_loci =
			$_
		  ? $self->{'datastore'}->get_scheme_loci($_)
		  : $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
		foreach my $locus (@$scheme_loci) {
			if ( !$locus_selected{$locus} ) {
				push @$loci_ref, "l_$locus";
				$locus_selected{$locus} = 1;
			}
		}
	}
	return;
}

sub _get_ids {
	my ( $self, $qry ) = @_;
	$qry =~ s/ORDER\ BY.*$//gx;
	return if !$self->create_temp_tables( \$qry );
	$qry =~ s/SELECT\ \*/SELECT id/x;
	my $ids = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	@$ids = sort { $a <=> $b } @$ids;
	return $ids;
}

sub _read_status {
	my ( $self, $scan_job ) = @_;
	my $status_file = "$self->{'config'}->{'secure_tmp_dir'}/$scan_job\_status.txt";
	my %data;
	return \%data if !-e $status_file;
	open( my $fh, '<', $status_file ) || $logger->error("Can't open $status_file for reading. $!");
	while (<$fh>) {
		if ( $_ =~ /^(.*):(.*)$/x ) {
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
		if ( $_ =~ /^(\d+):(.*)$/x ) {
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
