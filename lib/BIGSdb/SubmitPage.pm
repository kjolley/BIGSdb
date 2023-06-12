#Written by Keith Jolley
#Copyright (c) 2015-2023, University of Oxford
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
package BIGSdb::SubmitPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::TreeViewPage BIGSdb::CurateProfileAddPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Submissions');
use BIGSdb::Utils;
use BIGSdb::Constants qw(SEQ_METHODS :submissions :interface :design);
use List::MoreUtils qw(none);
use POSIX;
use JSON;
use constant LIMIT => 500;
use constant INF   => 9**99;

sub get_help_url {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('curate') ) {
		return "$self->{'config'}->{'doclink'}/curate_submissions.html";
	} else {
		return "$self->{'config'}->{'doclink'}/submissions.html";
	}
}

sub get_submission_days {
	my ($self) = @_;
	my $days = $self->{'system'}->{'submissions_deleted_days'} // $self->{'config'}->{'submissions_deleted_days'}
	  // SUBMISSIONS_DELETED_DAYS;
	$days = SUBMISSIONS_DELETED_DAYS if !BIGSdb::Utils::is_int($days);
	return $days;
}

sub get_javascript {
	my ($self)      = @_;
	my $q           = $self->{'cgi'};
	my $max         = $self->{'config'}->{'max_upload_size'} / ( 1024 * 1024 );
	my $max_files   = LIMIT;
	my $tree_js     = $self->get_tree_javascript( { checkboxes => 1, check_schemes => 1, submit_name => 'filter' } );
	my $submit_type = q();
	foreach my $type (qw(isolates genomes assemblies alleles profiles)) {
		if ( $q->param($type) ) {
			$submit_type = $type;
			last;
		}
	}
	my $submission_id = $q->param('submission_id') // q();
	my $links         = $self->get_related_databases;
	my $db_trigger    = q();
	if ( @$links > 1 ) {
		$db_trigger = << "END";
+\$("#related_db_trigger,#close_related_db").click(function(){		
		\$("#related_db_panel").toggle("slide",{direction:"right"},"fast");
		return false;
	});	
END
	}
	my $buffer = << "END";
\$(function () {
	\$("fieldset#scheme_fieldset").css("display","block");
	\$("#filter").click(function() {	
		var fields = ["technology", "assembly", "software", "read_length", "coverage", "locus", "fasta"];
		for (i=0; i<fields.length; i++){
			\$("#" + fields[i]).prop("required",false);
		}

	});	
	\$("#technology").change(function() {	
		check_technology();
	});
	check_technology();
	\$( "#show_closed" ).click(function() {
		if (\$("span#show_closed_text").css('display') == 'none'){
			\$("span#show_closed_text").css('display', 'inline');
			\$("span#hide_closed_text").css('display', 'none');
		} else {
			\$("span#show_closed_text").css('display', 'none');
			\$("span#hide_closed_text").css('display', 'inline');
		}
		\$( "#closed" ).toggle( 'blind', {} , 500 );
		return false;
	});
	\$("form#file_upload_form").dropzone({ 
		paramName: function() { return 'file_upload'; },
		parallelUploads: 6,
		maxFiles: $max_files,
		uploadMultiple: true,
		maxFilesize: $max,
		init: function () {
        	this.on('queuecomplete', function () {
         		if (this.getUploadingFiles().length === 0 && this.getQueuedFiles().length === 0) {
	         		var url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=submit";
	         		if ('$submit_type'.length){
	         			url += "&$submit_type=1";
	         		} else if ('$submission_id'.length){
	         			url += "&submission_id=$submission_id";
	         		}
	             	location.href = url;
         		}
        	});
    	}
	});
	\$("form#file_upload_form").addClass("dropzone");
	$db_trigger
	resize_rmlst_cell();
});

function resize_rmlst_cell(){
	var width=0;
	\$(".rmlst_result").each(function( index ) {
		if (\$(this).width() > width){
			width = \$(this).width();
		}
	});
	\$(".rmlst_cell").css("min-width", width + 20 + "px");
}

function status_markall(status){
	\$("select[name^='status_']").val(status);
}

function check_technology() {
	var fields = [ "read_length", "coverage"];
	for (i=0; i<fields.length; i++){
		if (\$("#technology").val() == 'Illumina'){			
			\$("#" + fields[i]).prop("required",true);
			\$("#" + fields[i] + "_label").text((fields[i]+":!").replace("_", " "));	
		} else {
			\$("#" + fields[i]).prop("required",false);
			\$("#" + fields[i] + "_label").text((fields[i]+":").replace("_", " "));
		}
	}	
}
$tree_js
END
	return $buffer;
}

sub initiate {
	my ($self)        = @_;
	my $q             = $self->{'cgi'};
	my $submission_id = $q->param('submission_id');
	if ( $q->param('tar') && $q->param('submission_id') ) {
		$self->{'type'}       = 'tar';
		$self->{'attachment'} = "$submission_id\.tar";
		$self->{'noCache'}    = 1;
		return;
	}
	$self->{$_} = 1 foreach qw (jQuery jQuery.jstree noCache tooltips dropzone);
	if ( $q->param('curate') ) {
		$self->set_level2_breadcrumbs('Curate submission');
	} elsif ( $q->param('alleles') || $q->param('profiles') || $q->param('isolate') || $q->param('genomes') ) {
		$self->set_level2_breadcrumbs('New submission');
	} else {
		$self->{'processing'} = 1 if defined $q->param('submission_id');
		foreach my $method (qw(abort finalize close remove cancel)) {
			if ( $q->param($method) ) {
				$self->{'processing'} = 0;
				last;
			}
		}
		$self->set_level1_breadcrumbs;
	}
	return;
}

sub print_content {
	my ($self) = @_;
	if ( ( $self->{'system'}->{'submissions'} // '' ) ne 'yes' || !$self->{'config'}->{'submission_dir'} ) {
		say q(<h1>Manage submissions</h1>);
		$self->print_bad_status( { message => q(The submission system is not enabled.) } );
		say q(<div style="position:relative;margin-top:-8em">);
		$self->print_related_database_panel;
		say q(</div>);
		return;
	}
	my $q = $self->{'cgi'};
	$self->choose_set;
	my $submission_id = $q->param('submission_id');
	if ($submission_id) {
		if ( $q->param('reopen') ) {
			$self->_reopen_submission($submission_id);
		}
		my %return_after = map { $_ => 1 } qw (tar view curate);
		my $action_performed;
		foreach my $action (qw (abort finalize close remove tar view curate cancel)) {
			if ( $q->param($action) ) {
				my $method = "_${action}_submission";
				$self->$method($submission_id);
				$action_performed = 1;
				return if $return_after{$action};
				last;
			}
		}
		if ( !$action_performed ) {
			foreach my $type (qw (alleles profiles isolates genomes assemblies)) {
				if ( $q->param($type) ) {
					last if $self->_user_over_quota;
					my $method = "_handle_$type";
					$self->$method;
					return;
				}
			}
		}
	}
	say q(<h1>Manage submissions</h1>);
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	if ( !$user_info ) {
		$self->print_bad_status( { message => q(You are not a recognized user. Submissions are disabled.) } );
		say q(<div style="position:relative;margin-top:-8em">);
		$self->print_related_database_panel;
		say q(</div>);
		return;
	}
	foreach my $type (qw (alleles profiles isolates genomes assemblies)) {
		if ( $q->param($type) ) {
			last if $self->_user_over_quota;
			my $method = "_handle_$type";
			$self->$method;
			return;
		}
	}
	my $submissions_to_show = $self->_any_pending_submissions_to_show;
	$self->_delete_old_submissions;
	my $closed_buffer =
	  $self->print_submissions_for_curation( { status => 'closed', show_outcome => 1, get_only => 1 } );
	if ( !$self->_print_started_submissions ) {    #Returns true if submissions in process
		say q(<div class="box" id="resultspanel"><div class="scrollable">);
		$self->_print_new_submission_links;
		if ( !$submissions_to_show ) {
			$self->print_navigation_bar( { closed_submissions => $closed_buffer ? 1 : 0 } );
		}
		say q(</div>);
		$self->print_related_database_panel;
		say q(</div>);
	}
	if ($submissions_to_show) {
		say q(<div class="box resultstable"><div class="scrollable">);
		$self->_print_pending_submissions;
		$self->print_submissions_for_curation;
		$self->_print_closed_submissions;
		$self->print_navigation_bar( { closed_submissions => $closed_buffer ? 1 : 0 } );
		say q(</div></div>);
	}
	if ($closed_buffer) {
		say q(<div class="box resultstable" id="closed" style="display:none"><div class="scrollable">);
		say q(<h2>Closed submissions for which you had curator rights</h2>);
		my $days = $self->get_submission_days;
		say q(<p>The following submissions are now closed - they will remain here until removed by the submitter or )
		  . qq(for $days days.);
		say $closed_buffer;
		say q(</div></div>);
	}
	return;
}

sub _any_pending_submissions_to_show {
	my ($self) = @_;
	return 1 if $self->_get_own_submissions('pending');
	return 1 if $self->print_submissions_for_curation( { get_only => 1 } );
	return 1 if $self->_get_own_submissions('closed');
	return;
}

sub _user_over_quota {
	my ($self) = @_;
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $total_limit =
	  BIGSdb::Utils::is_int( $self->{'system'}->{'total_pending_submissions'} )
	  ? $self->{'system'}->{'total_pending_submissions'}
	  : TOTAL_PENDING_LIMIT;
	my $total_pending =
	  $self->{'datastore'}->run_query(
		'SELECT COUNT(*) FROM submissions WHERE (submitter,status)=(?,?) AND (dataset IS NULL OR dataset = ?)',
		[ $user_info->{'id'}, 'pending', $self->{'instance'} ] );
	if ( $total_pending >= $total_limit ) {
		$self->print_bad_status(
			{
				message => q(Your account has too many pending submissions. )
				  . q(You will not be able to submit any more until these have been curated.)
			}
		);
		return 1;
	}
	my $daily_limit =
	  BIGSdb::Utils::is_int( $self->{'system'}->{'daily_pending_submissions'} )
	  ? $self->{'system'}->{'daily_pending_submissions'}
	  : DAILY_PENDING_LIMIT;
	my $daily_pending = $self->{'datastore'}->run_query(
		'SELECT COUNT(*) FROM submissions WHERE (submitter,status,date_submitted)=(?,?,?) '
		  . 'AND (dataset IS NULL OR dataset = ?)',
		[ $user_info->{'id'}, 'pending', 'now', $self->{'instance'} ]
	);
	if ( $daily_pending >= $daily_limit ) {
		$self->print_bad_status(
			{
					message => q(Your account has too many pending submissions )
				  . q(submitted today. You will not be able to submit any more until either tomorrow or )
				  . q(when these have been curated.)
			}
		);
		return 1;
	}
	return;
}

sub _handle_alleles {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $self->{'system'}->{'dbtype'} ne 'sequences' ) {
		$self->print_bad_status(
			{
				message => q(You cannot submit new allele sequences for definition in an isolate database.)
			}
		);
		return;
	}
	if ( $q->param('submit') ) {
		$self->_update_allele_prefs;
	}
	$self->_submit_alleles;
	return;
}

sub _handle_profiles {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $self->{'system'}->{'dbtype'} ne 'sequences' ) {
		$self->print_bad_status(
			{
				message => q(You cannot submit new profiles for definition in an isolate database.)
			}
		);
		return;
	}
	$self->_submit_profiles;
	return;
}

sub _handle_isolates {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		$self->print_bad_status(
			{
				message => q(You cannot submit new isolates to a sequence definition database.)
			}
		);
		return;
	}
	$self->_submit_isolates;
	return;
}

sub _handle_genomes {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		$self->print_bad_status(
			{
				message => q(You cannot submit new genomes to a sequence definition database.)
			}
		);
		return;
	}
	$self->_submit_isolates( { genomes => 1 } );
	return;
}

sub _handle_assemblies {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		$self->print_bad_status(
			{
				message => q(You cannot submit new genomes to a sequence definition database.)
			}
		);
		return;
	}
	$self->_submit_assemblies;
	return;
}

sub _print_new_submission_links {
	my ($self) = @_;
	say q(<h2>Submit new data</h2>);
	say q(<p>Data submitted here will go in to a queue for handling by a curator or by an automated script. You )
	  . q(will be able to track the status of any submission.</p>);
	say q(<h3>Submission type:</h3>);
	say q(<ul>);
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit&amp;)
		  . q(alleles=1">alleles</a></li>);

		#Don't allow profile submissions by default - they can be extracted from those records.
		#This ensures that every new profile has accompanying isolate data.
		if ( ( $self->{'system'}->{'profile_submissions'} // '' ) eq 'yes' ) {
			my $set_id = $self->get_set_id;
			my $schemes =
			  $self->{'datastore'}->get_scheme_list( { with_pk => 1, set_id => $set_id, submissions => 1 } );
			foreach my $scheme (@$schemes) {
				say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit)
				  . qq(&amp;profiles=1&amp;scheme_id=$scheme->{'id'}">$scheme->{'name'} profiles</a></li>);
			}
		}
		if ( $self->{'system'}->{'isolate_database'} && ( $self->{'system'}->{'isolate_submissions'} // q() ) eq 'yes' )
		{
			say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'system'}->{'isolate_database'}&amp;)
			  . q(page=submit&amp;isolates=1">isolates</a> (without assembly files) )
			  . q(<span class="link">Link to isolate database</span></li>);
			if ( ( $self->{'system'}->{'genome_submissions'} // q() ) ne 'no' ) {
				say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'system'}->{'isolate_database'}&amp;)
				  . q(page=submit&amp;genomes=1">genomes</a> (isolate records with assembly files) )
				  . q(<span class="link">Link to isolate database</span></li>);
			}
		}
	} else {    #Isolate database
		say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit&amp;)
		  . q(isolates=1">isolates</a> (without assembly files)</li>);
		if ( ( $self->{'system'}->{'genome_submissions'} // q() ) ne 'no' ) {
			say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit&amp;)
			  . q(genomes=1">genomes</a> (isolate records with assembly files)</li>);
			say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit&amp;)
			  . q(assemblies=1">assemblies</a> (to add to existing records)</li>);
		}
	}
	say q(</ul>);
	return;
}

sub _delete_old_submissions {
	my ($self) = @_;
	my $days = $self->get_submission_days;
	my $submissions =
	  $self->{'datastore'}->run_query(
		qq(SELECT id FROM submissions WHERE status IN ('closed','started') AND datestamp<now()-interval '$days days'),
		undef, { fetch => 'col_arrayref' } );
	foreach my $submission_id (@$submissions) {
		$self->{'submissionHandler'}->delete_submission($submission_id);
	}
	return;
}

sub _get_submissions_by_status {
	my ( $self, $status, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my ( $qry, $get_all, @args );
	if ( $options->{'get_all'} ) {
		$qry     = 'SELECT * FROM submissions WHERE status=? AND (dataset IS NULL OR dataset = ?) ORDER BY id';
		$get_all = 1;
		push @args, ( $status, $self->{'instance'} );
	} else {
		$qry =
		  'SELECT * FROM submissions WHERE (submitter,status)=(?,?) AND (dataset IS NULL OR dataset = ?) ORDER BY id';
		$get_all = 0;
		push @args, ( $user_info->{'id'}, $status, $self->{'instance'} );
	}
	my $submissions =
	  $self->{'datastore'}->run_query( $qry, \@args,
		{ fetch => 'all_arrayref', slice => {}, cache => "SubmitPage::get_submissions_by_status$get_all" } );
	return $submissions;
}

sub _print_started_submissions {
	my ($self) = @_;
	my $incomplete = $self->_get_submissions_by_status('started');
	if (@$incomplete) {
		say q(<div class="box" id="resultspanel"><div class="scrollable">);
		say q(<h2>Submission in process</h2>);
		say q(<p>Please note that you must either proceed with or abort the in process submission before you can )
		  . q(start another.</p>);
		foreach my $submission (@$incomplete) { #There should only be one but this isn't enforced at the database level.
			say qq(<dl class="data"><dt>Submission</dt><dd>$submission->{'id'}</dd>);
			say qq(<dt>Datestamp</dt><dd>$submission->{'datestamp'}</dd>);
			say qq(<dt>Type</dt><dd>$submission->{'type'}</dd>);
			if ( $submission->{'type'} eq 'alleles' ) {
				my $allele_submission = $self->{'submissionHandler'}->get_allele_submission( $submission->{'id'} );
				if ($allele_submission) {
					say qq(<dt>Locus</dt><dd>$allele_submission->{'locus'}</dd>);
					my $seq_count = @{ $allele_submission->{'seqs'} };
					say qq(<dt>Sequences</dt><dd>$seq_count</dd>);
				}
			} elsif ( $submission->{'type'} eq 'profiles' ) {
				my $profile_submission = $self->{'submissionHandler'}->get_profile_submission( $submission->{'id'} );
				if ($profile_submission) {
					my $scheme_id   = $profile_submission->{'scheme_id'};
					my $set_id      = $self->get_set_id;
					my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
					say qq(<dt>Scheme</dt><dd>$scheme_info->{'name'}</dd>);
					my $profile_count = @{ $profile_submission->{'profiles'} };
					say qq(<dt>Profiles</dt><dd>$profile_count</dd>);
				}
			}
			say qq(<dt>Action</dt><dd><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=submit&amp;$submission->{'type'}=1">Abort/Continue</a>);
			say q(</dl>);
		}
		say q(</div></div>);
		return 1;
	}
	return;
}

sub _get_own_submissions {
	my ( $self, $status, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $submissions = $self->_get_submissions_by_status( $status, { get_all => 0 } );
	my $buffer;
	if (@$submissions) {
		my $td     = 1;
		my $set_id = $self->get_set_id;
		my $table_buffer;
		foreach my $submission (@$submissions) {
			my $details        = q();
			my %details_method = (
				alleles    => '_get_allele_submission_details',
				profiles   => '_get_profile_submission_details',
				isolates   => '_get_isolate_submission_details',
				genomes    => '_get_isolate_submission_details',
				assemblies => '_get_assembly_submission_details'
			);
			if ( $details_method{ $submission->{'type'} } ) {
				my $method = $details_method{ $submission->{'type'} };
				$details = $self->$method($submission);
			}
			my $url = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit&amp;)
			  . qq(submission_id=$submission->{'id'}&amp;view=1);
			$table_buffer .=
				qq(<tr class="td$td"><td><a href="$url">$submission->{'id'}</a></td>)
			  . qq(<td>$submission->{'date_submitted'}</td><td>$submission->{'datestamp'}</td>)
			  . qq(<td>$submission->{'type'}</td>);
			$table_buffer .= qq(<td>$details</td>);
			if ( $options->{'show_outcome'} ) {
				my %style = FACE_STYLE;
				$table_buffer .= qq(<td><span $style{$submission->{'outcome'}}></span></td>);
			}
			if ( $options->{'allow_remove'} ) {
				$table_buffer .=
					qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=submit&amp;submission_id=$submission->{'id'}&amp;remove=1">)
				  . q(<span class="fas fa-lg fa-times"></span></a></td>);
			}
			$table_buffer .= q(</tr>);
			$td = $td == 1 ? 2 : 1;
		}
		if ($table_buffer) {
			$buffer .= q(<table class="resultstable"><tr><th>Submission id</th><th>Submitted</th><th>Updated</th>)
			  . q(<th>Type</th><th>Details</th>);
			$buffer .= q(<th>Outcome</th>) if $options->{'show_outcome'};
			$buffer .= q(<th>Remove</th>)  if $options->{'allow_remove'};
			$buffer .= q(</tr>);
			$buffer .= $table_buffer;
			$buffer .= q(</table>);
		}
	}
	return $buffer;
}

sub _get_allele_submission_details {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $submission ) = @_;
	my $set_id            = $self->get_set_id;
	my $allele_submission = $self->{'submissionHandler'}->get_allele_submission( $submission->{'id'} );
	my $allele_count      = @{ $allele_submission->{'seqs'} };
	my $plural            = $allele_count == 1 ? '' : 's';
	next if $set_id && !$self->{'datastore'}->is_locus_in_set( $allele_submission->{'locus'}, $set_id );
	my $clean_locus = $self->clean_locus( $allele_submission->{'locus'} );
	return "$allele_count $clean_locus sequence$plural";
}

sub _get_profile_submission_details {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $submission ) = @_;
	my $set_id             = $self->get_set_id;
	my $profile_submission = $self->{'submissionHandler'}->get_profile_submission( $submission->{'id'} );
	my $profile_count      = @{ $profile_submission->{'profiles'} };
	my $plural             = $profile_count == 1 ? '' : 's';
	next
	  if $set_id
	  && !$self->{'datastore'}->is_scheme_in_set( $profile_submission->{'scheme_id'}, $set_id );
	my $scheme_info =
	  $self->{'datastore'}->get_scheme_info( $profile_submission->{'scheme_id'}, { get_pk => 1, set_id => $set_id } );
	return "$profile_count $scheme_info->{'name'} profile$plural";
}

sub _get_isolate_submission_details {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $submission ) = @_;
	my $isolate_submission = $self->{'submissionHandler'}->get_isolate_submission( $submission->{'id'} );
	my $isolate_count      = @{ $isolate_submission->{'isolates'} };
	my $plural             = $isolate_count == 1 ? '' : 's';
	return "$isolate_count isolate$plural";
}

sub _get_assembly_submission_details {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $submission ) = @_;
	my $isolate_submission = $self->{'submissionHandler'}->get_assembly_submission( $submission->{'id'} );
	my $assembly_count     = @$isolate_submission;
	my $plural             = $assembly_count == 1 ? 'y' : 'ies';
	return "$assembly_count assembl$plural";
}

sub _print_pending_submissions {
	my ($self) = @_;
	my $buffer = $self->_get_own_submissions('pending');
	if ($buffer) {
		say q(<h2>Pending submissions</h2>);
		say q(<p>You have submitted the following submissions that are pending curation:</p>);
		say $buffer;
	}
	return;
}

sub print_submissions_for_curation {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	return if ( $self->{'system'}->{'submissions'} // '' ) ne 'yes';
	return if !$self->{'config'}->{'submission_dir'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	return if !$user_info || ( $user_info->{'status'} ne 'admin' && $user_info->{'status'} ne 'curator' );
	my $buffer;
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		$buffer .= $self->_get_allele_submissions_for_curation($options);
		$buffer .= $self->_get_profile_submissions_for_curation($options);
	} else {
		$buffer .= $self->_get_isolate_submissions_for_curation($options);
		$buffer .= $self->_get_assembly_submissions_for_curation($options);
	}
	return $buffer if $options->{'get_only'};
	say $buffer    if $buffer;
	return;
}

sub _get_allele_submissions_for_curation {
	my ( $self, $options ) = @_;
	my $status      = $options->{'status'} // 'pending';
	my $user_info   = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $submissions = $self->_get_submissions_by_status( $status, { get_all => 1 } );
	my $buffer;
	my $td     = 1;
	my $set_id = $self->get_set_id;
	foreach my $submission (@$submissions) {
		next if $submission->{'type'} ne 'alleles';
		my $allele_submission = $self->{'submissionHandler'}->get_allele_submission( $submission->{'id'} );
		next
		  if !($self->is_admin
			|| $self->{'datastore'}
			->is_allowed_to_modify_locus_sequences( $allele_submission->{'locus'}, $user_info->{'id'} ) );
		next if $set_id && !$self->{'datastore'}->is_locus_in_set( $allele_submission->{'locus'}, $set_id );
		my $submitter_string = $self->{'datastore'}->get_user_string( $submission->{'submitter'}, { email => 1 } );
		my $locus            = $self->clean_locus( $allele_submission->{'locus'} ) // $allele_submission->{'locus'};
		$buffer .=
			qq(<tr class="td$td"><td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=submit&amp;submission_id=$submission->{'id'}&amp;curate=1">$submission->{'id'}</a></td>)
		  . qq(<td>$submission->{'date_submitted'}</td><td>$submission->{'datestamp'}</td><td>$submitter_string</td>)
		  . qq(<td>$locus</td><td>$allele_submission->{'technology'}</td>);
		my $seq_count = @{ $allele_submission->{'seqs'} };
		$buffer .= qq(<td>$seq_count</td>);

		if ( $status eq 'closed' ) {
			my %style = FACE_STYLE;
			$buffer .= qq(<td><span $style{$submission->{'outcome'}}></span></td>);
		}
		$buffer .= qq(</tr>\n);
		$td = $td == 1 ? 2 : 1;
	}
	my $return_buffer = q();
	if ($buffer) {
		if ( $status eq 'closed' ) {
			$return_buffer .= q(<h3>Allele submissions</h3>);
		} else {
			$return_buffer .= qq(<h2>New allele sequence submissions waiting for curation</h2>\n);
			$return_buffer .= qq(<p>Your account is authorized to handle the following submissions:<p>\n);
			my $allele_curate_message = "$self->{'dbase_config_dir'}/$self->{'instance'}/allele_curate.html";
			$return_buffer .= $self->print_file( $allele_curate_message, { get_only => 1 } )
			  if -e $allele_curate_message;
		}
		$return_buffer .= q(<table class="resultstable"><tr><th>Submission id</th><th>Submitted</th><th>Updated</th>)
		  . q(<th>Submitter</th><th>Locus</th><th>Technology</th><th>Sequences</th>);
		$return_buffer .= q(<th>Outcome</th>) if $status eq 'closed';
		$return_buffer .= qq(</tr>\n);
		$return_buffer .= $buffer;
		$return_buffer .= qq(</table>\n);
	}
	return $return_buffer;
}

sub _get_profile_submissions_for_curation {
	my ( $self, $options ) = @_;
	my $status      = $options->{'status'} // 'pending';
	my $user_info   = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $submissions = $self->_get_submissions_by_status( $status, { get_all => 1 } );
	my $buffer;
	my $td     = 1;
	my $set_id = $self->get_set_id;
	foreach my $submission (@$submissions) {
		next if $submission->{'type'} ne 'profiles';
		my $profile_submission =
		  $self->{'submissionHandler'}->get_profile_submission( $submission->{'id'}, { count_only => 1 } );
		next
		  if !($self->is_admin
			|| $self->{'datastore'}->is_scheme_curator( $profile_submission->{'scheme_id'}, $user_info->{'id'} ) );
		next
		  if $set_id
		  && !$self->{'datastore'}->is_scheme_in_set( $profile_submission->{'scheme_id'}, $set_id );
		my $submitter_string = $self->{'datastore'}->get_user_string( $submission->{'submitter'}, { email => 1 } );
		my $scheme_info =
		  $self->{'datastore'}->get_scheme_info( $profile_submission->{'scheme_id'}, { set_id => $set_id } );
		$buffer .=
			qq(<tr class="td$td"><td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=submit&amp;submission_id=$submission->{'id'}&amp;curate=1">$submission->{'id'}</a></td>)
		  . qq(<td>$submission->{'date_submitted'}</td><td>$submission->{'datestamp'}</td><td>$submitter_string</td>)
		  . qq(<td>$scheme_info->{'name'}</td>);
		$buffer .= qq(<td>$profile_submission->{'count'}</td>);

		if ( $status eq 'closed' ) {
			my %style = FACE_STYLE;
			$buffer .= qq(<td><span $style{$submission->{'outcome'}}></span></td>);
		}
		$buffer .= qq(</tr>\n);
		$td = $td == 1 ? 2 : 1;
	}
	my $return_buffer = q();
	if ($buffer) {
		if ( $status eq 'closed' ) {
			$return_buffer .= q(<h3>Profile submissions</h3>);
		} else {
			$return_buffer .= qq(<h2>New allelic profile submissions waiting for curation</h2>\n);
			$return_buffer .= qq(<p>Your account is authorized to handle the following submissions:<p>\n);
			my $profile_curate_message = "$self->{'dbase_config_dir'}/$self->{'instance'}/profile_curate.html";
			$return_buffer .= $self->print_file( $profile_curate_message, { get_only => 1 } )
			  if -e $profile_curate_message;
		}
		$return_buffer .= q(<table class="resultstable"><tr><th>Submission id</th><th>Submitted</th><th>Updated</th>)
		  . q(<th>Submitter</th><th>Scheme</th><th>Profiles</th>);
		$return_buffer .= q(<th>Outcome</th>) if $status eq 'closed';
		$return_buffer .= qq(</tr>\n);
		$return_buffer .= $buffer;
		$return_buffer .= qq(</table>\n);
	}
	return $return_buffer;
}

sub _get_isolate_submissions_for_curation {
	my ( $self, $options ) = @_;
	my $status = $options->{'status'} // 'pending';
	return q() if !$self->can_modify_table('isolates');
	my $submissions = $self->_get_submissions_by_status( $status, { get_all => 1 } );
	my $buffer;
	my $td = 1;
	foreach my $submission (@$submissions) {
		next if $submission->{'type'} ne 'isolates' && $submission->{'type'} ne 'genomes';
		next if $submission->{'type'} eq 'genomes'  && !$self->can_modify_table('sequence_bin');
		my $isolate_submission = $self->{'submissionHandler'}->get_isolate_submission( $submission->{'id'} );
		my $submitter_string   = $self->{'datastore'}->get_user_string( $submission->{'submitter'}, { email => 1 } );
		my $isolate_count      = @{ $isolate_submission->{'isolates'} };
		$buffer .=
			qq(<tr class="td$td"><td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=submit&amp;submission_id=$submission->{'id'}&amp;curate=1">$submission->{'id'}</a></td>)
		  . qq(<td>$submission->{'date_submitted'}</td><td>$submission->{'datestamp'}</td><td>$submitter_string</td>)
		  . qq(<td>$isolate_count</td>);
		if ( $status eq 'closed' ) {
			my %style = FACE_STYLE;
			$buffer .= qq(<td><span $style{$submission->{'outcome'}}></span></td>);
		}
		$buffer .= qq(</tr>\n);
		$td = $td == 1 ? 2 : 1;
	}
	my $return_buffer = q();
	if ($buffer) {
		if ( $status eq 'closed' ) {
			$return_buffer .= q(<h3>Isolate submissions</h3>);
		} else {
			$return_buffer .= qq(<h2>New isolate submissions waiting for curation</h2>\n);
			$return_buffer .= qq(<p>Your account is authorized to handle the following submissions:<p>\n);
			my $isolate_curate_message = "$self->{'dbase_config_dir'}/$self->{'instance'}/isolate_curate.html";
			$return_buffer .= $self->print_file( $isolate_curate_message, { get_only => 1 } )
			  if -e $isolate_curate_message;
		}
		$return_buffer .= q(<table class="resultstable"><tr><th>Submission id</th><th>Submitted</th><th>Updated</th>)
		  . q(<th>Submitter</th><th>Isolates</th>);
		$return_buffer .= q(<th>Outcome</th>) if $status eq 'closed';
		$return_buffer .= qq(</tr>\n);
		$return_buffer .= $buffer;
		$return_buffer .= qq(</table>\n);
	}
	return $return_buffer;
}

sub _get_assembly_submissions_for_curation {
	my ( $self, $options ) = @_;
	my $status = $options->{'status'} // 'pending';
	return q() if !$self->can_modify_table('isolates');
	my $submissions = $self->_get_submissions_by_status( $status, { get_all => 1 } );
	my $buffer;
	my $td = 1;
	foreach my $submission (@$submissions) {
		next if $submission->{'type'} ne 'assemblies';
		next if !$self->can_modify_table('sequence_bin');
		my $assembly_submission = $self->{'submissionHandler'}->get_assembly_submission( $submission->{'id'} );
		my $submitter_string    = $self->{'datastore'}->get_user_string( $submission->{'submitter'}, { email => 1 } );
		my $assembly_count      = @$assembly_submission;
		$buffer .=
			qq(<tr class="td$td"><td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=submit&amp;submission_id=$submission->{'id'}&amp;curate=1">$submission->{'id'}</a></td>)
		  . qq(<td>$submission->{'date_submitted'}</td><td>$submission->{'datestamp'}</td><td>$submitter_string</td>)
		  . qq(<td>$assembly_count</td>);
		if ( $status eq 'closed' ) {
			my %style = FACE_STYLE;
			$buffer .= qq(<td><span $style{$submission->{'outcome'}}></span></td>);
		}
		$buffer .= qq(</tr>\n);
		$td = $td == 1 ? 2 : 1;
	}
	my $return_buffer = q();
	if ($buffer) {
		if ( $status eq 'closed' ) {
			$return_buffer .= q(<h3>Assembly submissions</h3>);
		} else {
			$return_buffer .= qq(<h2>New assembly submissions waiting for curation</h2>\n);
			$return_buffer .= qq(<p>Your account is authorized to handle the following submissions:<p>\n);
			my $isolate_curate_message = "$self->{'dbase_config_dir'}/$self->{'instance'}/isolate_curate.html";
			$return_buffer .= $self->print_file( $isolate_curate_message, { get_only => 1 } )
			  if -e $isolate_curate_message;
		}
		$return_buffer .= q(<table class="resultstable"><tr><th>Submission id</th><th>Submitted</th><th>Updated</th>)
		  . q(<th>Submitter</th><th>Assemblies</th>);
		$return_buffer .= q(<th>Outcome</th>) if $status eq 'closed';
		$return_buffer .= qq(</tr>\n);
		$return_buffer .= $buffer;
		$return_buffer .= qq(</table>\n);
	}
	return $return_buffer;
}

sub _print_closed_submissions {
	my ($self) = @_;
	my $buffer = $self->_get_own_submissions( 'closed', { show_outcome => 1, allow_remove => 1 } );
	if ($buffer) {
		say q(<h2>Recently closed submissions</h2>);
		my $days = $self->get_submission_days;
		say q(<p>You have submitted the following submissions which are now closed - they can be removed once )
		  . q(you have recorded the results.  Alternatively they will be removed automatically after )
		  . qq($days days.</p>);
		say $buffer;
	}
	return;
}

sub _print_allele_warnings {
	my ( $self, $warnings ) = @_;
	return if ref $warnings ne 'ARRAY' || !@$warnings;
	my @info = @$warnings;
	local $" = q(<br />);
	my $plural = @info == 1 ? '' : 's';
	say qq(<div class="box statuswarn"><h2>Warning$plural:</h2><p>@info</p><p>Warnings do not prevent submission )
	  . q(but may result in the submission being rejected depending on curation criteria.</p></div>);
	return;
}

sub _abort_submission {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $submission_id ) = @_;
	return if !$self->{'cgi'}->param('confirm');
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $submission =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id FROM submissions WHERE (id,submitter)=(?,?)', [ $submission_id, $user_info->{'id'} ] );
	$self->{'submissionHandler'}->delete_submission($submission_id) if $submission_id;
	return;
}

sub _delete_selected_submission_files {
	my ( $self, $submission_id ) = @_;
	my $q     = $self->{'cgi'};
	my $files = $self->_get_submission_files($submission_id);
	my $i     = 0;
	my $dir   = $self->{'submissionHandler'}->get_submission_dir($submission_id) . '/supporting_files';
	foreach my $file (@$files) {
		if ( $q->param("file$i") ) {
			if ( $file->{'filename'} =~ /^([^\/]+)$/x ) {
				my $filename = $1;
				unlink "$dir/$filename" || $logger->error("Cannot delete $dir/$filename.");
			}
			$q->delete("file$i");
		}
		$i++;
	}
	return;
}

sub _finalize_submission {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $submission_id ) = @_;
	my $q          = $self->{'cgi'};
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	return if !$submission || $submission->{'status'} ne 'started';
	$logger->info("$self->{'instance'}: New $submission->{'type'} submission");
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	eval {
		if ( $submission->{'type'} eq 'alleles' ) {
			$self->{'db'}->do(
				'UPDATE allele_submissions SET (technology,read_length,coverage,assembly,software)=(?,?,?,?,?) '
				  . 'WHERE submission_id=? AND submission_id IN (SELECT id FROM submissions WHERE submitter=?)',
				undef,
				scalar $q->param('technology'),
				scalar $q->param('read_length'),
				scalar $q->param('coverage'),
				scalar $q->param('assembly'),
				scalar $q->param('software'),
				$submission_id,
				$user_info->{'id'}
			);
		}
		$self->{'db'}->do(
			'UPDATE submissions SET (status,date_submitted,datestamp,email)=(?,?,?,?) WHERE (id,submitter)=(?,?)',
			undef, 'pending', 'now', 'now', $q->param('email') // undef,
			$submission_id, $user_info->{'id'}
		);
		$self->{'submissionHandler'}->write_db_file($submission_id);
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	my $guid = $self->get_guid;
	return if !$guid;
	$self->{'prefstore'}
	  ->set_general( $guid, $self->{'system'}->{'db'}, 'submit_email', $q->param('email') ? 'on' : 'off' );
	$self->{'submissionHandler'}->notify_curators($submission_id);
	return;
}

sub _submit_alleles {
	my ($self)        = @_;
	my $q             = $self->{'cgi'};
	my $submission_id = $self->_get_started_submission_id;
	$q->param( submission_id => $submission_id );
	my $ret;
	if ($submission_id) {
		my $allele_submission = $self->{'submissionHandler'}->get_allele_submission($submission_id);
		my $fasta_string;
		foreach my $seq ( @{ $allele_submission->{'seqs'} } ) {
			$fasta_string .= ">$seq->{'seq_id'}\n";
			$fasta_string .= "$seq->{'sequence'}\n";
		}
		if ( !$q->param('no_check') ) {
			$ret =
			  $self->{'submissionHandler'}->check_new_alleles_fasta( $allele_submission->{'locus'}, \$fasta_string );
			$self->_print_allele_warnings( $ret->{'info'} );
		}
		$self->_presubmit_alleles( $submission_id, undef );
		return;
	} elsif ( $q->param('submit') ) {
		$ret = $self->_check_new_alleles;
		if ( $ret->{'err'} ) {
			my @err = @{ $ret->{'err'} };
			local $" = '<br />';
			my $plural = @err == 1 ? '' : 's';
			$self->print_bad_status( { message => qq(Error$plural:), detail => qq(@err) } );
		} else {
			if ( $ret->{'info'} ) {
				$self->_print_allele_warnings( $ret->{'info'} );
			}
			$self->_presubmit_alleles( undef, $ret->{'seqs'} );
			return;
		}
	}
	say q(<div class="box" id="queryform">);
	say q(<h2>Submit new alleles</h2>);
	say q(<p>You need to make a separate submission for each locus for which you have new alleles - this is because )
	  . q(different loci may have different curators.  You can submit any number of new sequences for a single locus )
	  . q(as one submission. Sequences should be trimmed to the correct start/end sites for the selected locus.</p>);
	my $set_id = $self->get_set_id;
	my ( $loci, $labels );
	say $q->start_form;
	my $schemes = $self->{'datastore'}->run_query(
		'SELECT id FROM schemes WHERE id IN (SELECT sm.scheme_id FROM scheme_members sm '
		  . 'JOIN loci l ON sm.locus=l.id WHERE (no_submissions = FALSE OR no_submissions IS NULL)) '
		  . 'ORDER BY display_order,description',
		undef,
		{ fetch => 'col_arrayref' }
	);

	if ( @$schemes > 1 ) {
		say q(<fieldset id="scheme_fieldset" style="float:left;display:none"><legend>Filter loci by scheme</legend>);
		say q(<div id="tree" class="scheme_tree" style="float:left;max-height:initial">);
		say $self->get_tree( undef, { no_link_out => 1, select_schemes => 1, filter_no_submissions => 1 } );
		say q(</div>);
		say $q->submit( -name => 'filter', -id => 'filter', -label => 'Filter', -class => 'small_submit' );
		say q(</fieldset>);
		my @selected_schemes;
		foreach my $scheme_id ( @$schemes, 0 ) {
			push @selected_schemes, $scheme_id if $q->param("s_$scheme_id");
		}
		my $scheme_loci = @selected_schemes ? $self->_get_scheme_loci( \@selected_schemes ) : undef;
		( $loci, $labels ) =
		  $self->{'datastore'}->get_locus_list( { only_include => $scheme_loci, set_id => $set_id, submissions => 1 } );
	} else {
		( $loci, $labels ) = $self->{'datastore'}->get_locus_list( { set_id => $set_id, submissions => 1 } );
	}
	say q(<fieldset style="float:left;"><legend>Select locus</legend>);
	say $q->popup_menu(
		-name     => 'locus',
		-id       => 'locus',
		-values   => $loci,
		-labels   => $labels,
		-size     => 7,
		-required => 'required'
	);
	say q(</fieldset>);
	$self->_print_sequence_details_fieldset($submission_id);
	say q(<fieldset style="float:left"><legend>FASTA or single sequence</legend>);
	if ( $q->param('sequence_file') ) {
		my $filename = $q->param('sequence_file');
		$filename =~ s/[\.\/]//gx;    #Prevent directory traversal
		my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$filename";
		if ( -e $full_path ) {
			my $seq_ref = BIGSdb::Utils::slurp($full_path);
			$q->param( fasta => $$seq_ref );
		}
	}
	say $q->textarea(
		-name     => 'fasta',
		-rows     => 8,
		-id       => 'fasta',
		-required => 'required',
		-style    => 'max-width:800px;width:calc(100vw - 100px)'
	);
	say q(</fieldset>);
	say $q->hidden($_) foreach qw(db page alleles);
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->end_form;
	return;
}

sub _submit_profiles {
	my ($self)        = @_;
	my $q             = $self->{'cgi'};
	my $submission_id = $self->_get_started_submission_id;
	$q->param( submission_id => $submission_id );
	my $ret;
	if ($submission_id) {
		$self->_presubmit_profiles( $submission_id, undef );
		return;
	} elsif ( ( $q->param('submit') && $q->param('data') ) ) {
		my $scheme_id = $q->param('scheme_id');
		my $set_id    = $self->get_set_id;
		my $data      = $q->param('data');
		$ret = $self->{'submissionHandler'}->check_new_profiles( $scheme_id, $set_id, \$data );
		if ( $ret->{'err'} ) {
			my $err = $ret->{'err'};
			local $" = '<br />';
			my $plural = @$err == 1 ? '' : 's';
			$self->print_bad_status( { message => qq(Error$plural:), detail => qq(@$err) } );
		} elsif ( !@{ $ret->{'profiles'} } ) {
			$self->print_bad_status( { message => q(Error:), detail => 'No profiles in upload.' } );
		} else {
			$self->_presubmit_profiles( undef, $ret->{'profiles'} );
			return;
		}
	}
	my $scheme_id = $q->param('scheme_id');
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		$self->print_bad_status( { message => q(Scheme id must be an integer.) } );
		return;
	}
	my $set_id      = $self->get_set_id;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1, set_id => $set_id } );
	if ( !$scheme_info || !$scheme_info->{'primary_key'} ) {
		$self->print_bad_status( { message => q(Invalid scheme passed.) } );
		return;
	}
	say q(<div class="box" id="queryform">);
	say qq(<h2>Submit new $scheme_info->{'name'} profiles</h2>);
	say q(<p>Paste in your profiles for assignment using the template available below.</p>);
	say q(<h2>Templates</h2>);
	my ( $text, $excel ) = ( TEXT_FILE, EXCEL_FILE );
	say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableHeader&amp;)
	  . qq(table=profiles&amp;scheme_id=$scheme_id&amp;no_fields=1&amp;id_field=1" title="Download tab-delimited )
	  . qq(header for your spreadsheet">$text</a>)
	  . qq[<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=excelTemplate&amp;]
	  . qq[table=profiles&amp;scheme_id=$scheme_id&amp;no_fields=1&amp;id_field=1" title="Download submission template ]
	  . qq[(xlsx format)">$excel</a></p>];
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Please paste in tab-delimited text <b>)
	  . q((include a field header as the first line)</b></legend>);
	say $q->textarea(
		-name     => 'data',
		-rows     => 15,
		-required => 'required',
		-style    => 'max-width:800px;width:calc(100vw - 100px)'
	);
	say q(</fieldset>);
	say $q->hidden($_) foreach qw(db page profiles scheme_id);
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->end_form;
	say q(</div>);
	return;
}

sub _submit_isolates {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q             = $self->{'cgi'};
	my $submission_id = $self->_get_started_submission_id;
	$q->param( submission_id => $submission_id );
	if ($submission_id) {
		$self->_presubmit_isolates( { submission_id => $submission_id, options => $options } );
		return;
	} elsif ( ( $q->param('submit') && $q->param('data') ) ) {
		my $set_id = $self->get_set_id;
		my $data   = $q->param('data');
		$options->{'limit'} = LIMIT if $options->{'genomes'};
		my $ret = $self->{'submissionHandler'}->check_new_isolates( $set_id, \$data, $options );
		if ( $ret->{'err'} ) {
			my $err = $ret->{'err'};
			local $" = '<br />';
			my $plural = @$err == 1 ? '' : 's';
			s/'null'/<em>null<\/em>/gx foreach @$err;
			$self->print_bad_status( { message => qq(Error$plural:), detail => qq(@$err) } );
		} else {
			$self->_presubmit_isolates(
				{ isolates => $ret->{'isolates'}, positions => $ret->{'positions'}, options => $options } );
			return;
		}
	}
	my $set_id     = $self->get_set_id;
	my $set_clause = $set_id ? qq(&amp;set_id=$set_id) : q();
	say q(<div class="box" id="queryform"><div class="scrollable">);
	say q(<h2>Submit new isolates);
	say q( with genome assemblies) if $options->{'genomes'};
	say q(</h2>);
	say q(<p>Paste in your isolates for addition to the database using the template available below.</p>);
	say q(<ul><li>Optionally enter aliases (alternative names) for your isolates as a semi-colon)
	  . q( (;)-separated list.</li>);
	say q(<li>Optionally enter references for your isolates as a semi-colon (;)-separated list of PubMed ids.</li>);
	say q(<li>You can also upload additional allele fields along with the other isolate data - simply create a )
	  . q(new column with the locus name. );
	say q(By default, loci are not included with genome submissions since these can be extracted )
	  . q(directly from the genome.)
	  if $options->{'genomes'};
	say q(</li>);

	if ( $options->{'genomes'} ) {
		my $limit = LIMIT;
		say q(<li>Enter the name of the assembly contig FASTA file in the assembly_filename field and upload )
		  . q(this file as supporting data. FASTA files can be either uncompressed (.fas, .fasta) or )
		  . qq(gzip/zip compressed (.fas.gz, .fas.zip). <strong>Upload is limited to $limit files.</strong></li>);
		my @methods = SEQ_METHODS;
		local $" = q(, );
		say q(<li>Enter the name of the sequence method used in the sequence_method field )
		  . qq((allowed values: @methods)</li>);
	}
	say q(</ul>);
	my $contig_file_clause = $options->{'genomes'} ? '&amp;addCols=assembly_filename,sequence_method&noLoci=1' : q();
	my ( $text, $excel ) = ( TEXT_FILE, EXCEL_FILE );
	say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableHeader&amp;)
	  . qq(table=isolates&amp;order=scheme$set_clause$contig_file_clause" title="Download tab-delimited )
	  . qq(header for your spreadsheet">$text</a>)
	  . qq[<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=excelTemplate&amp;]
	  . qq[table=isolates&amp;order=scheme$set_clause$contig_file_clause" title="Download submission template ]
	  . qq[(xlsx format)">$excel</a></p>];
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Please paste in tab-delimited text <b>)
	  . q((include a field header as the first line)</b></legend>);
	say $q->textarea(
		-name     => 'data',
		-rows     => 15,
		-required => 'required',
		-style    => 'max-width:1400px;width:calc(100vw - 100px)'
	);
	say q(</fieldset>);
	say $q->hidden($_) foreach qw(db page isolates genomes);
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub _get_assembly_wrong_sender {
	my ( $self, $submission_id ) = @_;
	my $invalid_ids  = [];
	my $wrong_sender = [];
	my $cleaned_list = $self->{'datastore'}->run_query(
		'SELECT isolate_id AS id,isolate,filename FROM assembly_submissions WHERE '
		  . 'submission_id=? ORDER BY isolate_id',
		$submission_id,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	foreach my $record (@$cleaned_list) {
		my $sender = $self->{'datastore'}
		  ->run_query( "SELECT sender FROM $self->{'system'}->{'view'} WHERE id=?", $record->{'id'} );
		if ( !$sender ) {
			push @$invalid_ids, $record->{'id'};
		} elsif ( $sender != $submission->{'submitter'} ) {
			push @$wrong_sender, $record->{'id'};
		}
	}
	return { wrong_sender => $wrong_sender, invalid_ids => $invalid_ids };
}

sub _submit_assemblies {
	my ($self)        = @_;
	my $q             = $self->{'cgi'};
	my $submission_id = $self->_get_started_submission_id;
	$q->param( submission_id => $submission_id );
	my $checks;
	if ($submission_id) {
		$self->_presubmit_assemblies( { submission_id => $submission_id } );
		return;
	} elsif ( ( $q->param('submit') && $q->param('filenames') ) ) {
		my $data = $q->param('filenames');
		$checks = $self->_check_assemblies_isolate_records( \$data );
		if ( @{ $checks->{'cleaned_list'} } && !keys %{ $checks->{'errors'} } ) {
			$self->_presubmit_assemblies(
				{ cleaned_list => $checks->{'cleaned_list'}, wrong_sender => $checks->{'wrong_sender'} } );
			return;
		}
	}
	say q(<div class="box" id="queryform"><div class="scrollable">);
	say q(<h2>Add genome assemblies to existing isolate records</h2>);
	say q(<p>The first step in the upload process is to state which assembly contig FASTA file should be )
	  . q(linked to each isolate record. We use both the database id and the isolate name fields to cross-check )
	  . q(that the correct record is identified.</p>);
	my @seq_methods = SEQ_METHODS;
	local $" = q(, );
	say qq(<p>You also need to state the sequencing method for each assembly. Allowed values are: @seq_methods.</p>);
	my $limit = LIMIT;
	say qq(<p>You can upload up to $limit genomes at a time.</p>);
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Filenames</legend>);
	say q(<p>Paste in tab-delimited text, e.g. copied from a spreadsheet, consisting of 4 columns )
	  . qq( (database id, $self->{'system'}->{'labelfield'} name, method, FASTA filename). You need to ensure )
	  . q(that you use the full filename, including any suffix such as .fas or .fasta, which may be hidden by )
	  . q(your operating system. FASTA files may be either uncompressed (.fas, .fasta) or gzip/zip compressed )
	  . q((.fas.gz, .fas.zip).</p>);
	say $q->textarea(
		-id          => 'filenames',
		-name        => 'filenames',
		-cols        => 60,
		-rows        => 6,
		-placeholder => "1001\tisolate1\tIllumina\tisolate_1001.fasta\n1002\tisolate2\tIllumina\tisolate_1002.fasta",
		-required    => 'required'
	);
	say q(</fieldset>);
	say $q->hidden($_) foreach qw(db page isolates assemblies);
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->end_form;
	say q(</div></div>);

	if ( $checks->{'errors'} ) {
		my $table = q(<table class="resultstable"><th>Row</th><th>Error</th></tr>);
		my $td    = 1;
		foreach my $row ( sort { $a <=> $b } keys %{ $checks->{'errors'} } ) {
			$table .=
			  qq(<tr class="td$td"><td>$row</td><td style="text-align:left">$checks->{'errors'}->{$row}</td></tr>);
			$td = $td == 1 ? 2 : 1;
		}
		$table .= q(</table>);
		$self->print_bad_status(
			{
				message => 'Invalid data submitted',
				detail  => $table
			}
		);
	}
	return;
}

sub _check_assemblies_isolate_records {
	my ( $self, $data_ref ) = @_;
	my @records      = split /\r?\n/x, $$data_ref;
	my $errors       = {};
	my $wrong_sender = [];
	my $row          = 0;
	my $user_info    = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $cleaned      = [];
	my %id_used;
	my %filename_used;
	my %allowed_methods = map { $_ => 1 } SEQ_METHODS;
	my $limit           = LIMIT;

	foreach my $record (@records) {
		next if !$record;
		$row++;
		if ( $row > LIMIT ) {
			$errors->{$row} = "record limit reached - please only submit up to $limit records at a time.";
			last;
		}
		my ( $id, $isolate, $method, $filename ) = split /\t/x, $record;
		BIGSdb::Utils::remove_trailing_spaces_from_list( [ $id, $isolate, $method, $filename ] );
		if ( !BIGSdb::Utils::is_int($id) ) {
			my $value = BIGSdb::Utils::escape_html($id);
			$errors->{$row} = "invalid id - $value is not an integer.";
			next;
		}
		if (
			!$self->{'datastore'}->run_query(
				"SELECT EXISTS(SELECT * FROM $self->{'system'}->{'view'} WHERE id=?)",
				$id, { cache => 'SubmitPage::id_exists' }
			)
		  )
		{
			$errors->{$row} = "invalid id - no record accessible with id-$id.";
			next;
		}
		if ( !defined $isolate || $isolate eq q() ) {
			$errors->{$row} = 'no isolate value.';
			next;
		}
		if (
			!$self->{'datastore'}->run_query(
				qq[SELECT EXISTS(SELECT * FROM $self->{'system'}->{'view'} ]
				  . qq[WHERE (id,$self->{'system'}->{'labelfield'})=(?,?))],
				[ $id, $isolate ],
				{ cache => 'SubmitPage::isolate_matches_id' }
			)
		  )
		{
			$errors->{$row} = "isolate value does not match record for id-$id.";
			next;
		}
		if ( !defined $method || $method eq q() ) {
			$errors->{$row} = 'no method.';
			next;
		}
		if ( !$allowed_methods{$method} ) {
			$errors->{$row} = 'invalid sequencing method.';
			next;
		}
		if ( !defined $filename || $filename eq q() ) {
			$errors->{$row} = 'no filename.';
			next;
		}
		if ( $id_used{$id} ) {
			$errors->{$row} = "id-$id already submitted earlier in list.";
			next;
		}
		if ( $filename_used{$filename} ) {
			$errors->{$row} = 'filename already used earlier in list.';
			next;
		}
		if (
			$self->{'datastore'}->run_query(
				q[SELECT EXISTS(SELECT * FROM seqbin_stats WHERE isolate_id=?)],
				$id, { cache => 'SubmitPage::seqbin_exists' }
			)
		  )
		{
			$errors->{$row} = 'Record already has sequences defined.';
		}
		my $sender = $self->{'datastore'}->run_query( qq[SELECT sender FROM $self->{'system'}->{'view'} WHERE id=?],
			$id, { cache => 'SubmitPage::get_sender' } );
		if ( $sender != $user_info->{'id'} ) {
			push @$wrong_sender, $id;
		}
		$id_used{$id}             = 1;
		$filename_used{$filename} = 1;
		push @$cleaned,
		  {
			id              => $id,
			isolate         => $isolate,
			sequence_method => $method,
			filename        => $filename
		  };
	}
	return { cleaned_list => $cleaned, errors => $errors, wrong_sender => $wrong_sender };
}

sub _print_sequence_details_fieldset {
	my ( $self, $submission_id ) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left;min-height:12em"><legend>Sequence details</legend>);
	say q(<ul><li><label for="technology" class="parameter">technology:!</label>);
	my $allele_submission =
	  $submission_id ? $self->{'submissionHandler'}->get_allele_submission($submission_id) : undef;
	my $att_labels = { '' => ' ' };    #Required for HTML5 validation
	say $q->popup_menu(
		-name     => 'technology',
		-id       => 'technology',
		-values   => [ '', SEQ_METHODS ],
		-labels   => $att_labels,
		-required => 'required',
		-default  => $allele_submission->{'technology'} // $self->{'prefs'}->{'submit_allele_technology'}
	);
	say q(<li><label for="read_length" id="read_length_label" class="parameter">read length:</label>);
	say $q->popup_menu(
		-name    => 'read_length',
		-id      => 'read_length',
		-values  => [ '', READ_LENGTH ],
		-labels  => $att_labels,
		-default => $allele_submission->{'read_length'} // $self->{'prefs'}->{'submit_allele_read_length'}
	);
	say q(</li><li><label for="coverage" id="coverage_label" class="parameter">coverage:</label>);
	say $q->popup_menu(
		-name    => 'coverage',
		-id      => 'coverage',
		-values  => [ '', COVERAGE ],
		-labels  => $att_labels,
		-default => $allele_submission->{'coverage'} // $self->{'prefs'}->{'submit_allele_coverage'}
	);
	say q(</li><li><label for="assembly" class="parameter">assembly:!</label>);
	say $q->popup_menu(
		-name     => 'assembly',
		-id       => 'assembly',
		-values   => [ '', ASSEMBLY ],
		-labels   => $att_labels,
		-required => 'required',
		-default  => $allele_submission->{'assembly'} // $self->{'prefs'}->{'submit_allele_assembly'}
	);
	say q(</li><li><label for="software" class="parameter">assembly software:!</label>);
	say $q->textfield(
		-name     => 'software',
		-id       => 'software',
		-required => 'required',
		-default  => $allele_submission->{'software'} // $self->{'prefs'}->{'submit_allele_software'}
	);
	say q(</li><li>);
	say $q->checkbox( -name => 'ignore_length', -label => 'Sequence length outside usual range' );
	say $self->get_tooltip( q(Length check - If you select this checkbox your sequence must still be )
		  . q(trimmed to the standard start and end sites or it will be rejected by the curator.) );
	say q(</li></ul>);
	say q(</fieldset>);
	return;
}

sub _print_profile_table_fieldset {
	my ( $self, $submission_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q          = $self->{'cgi'};
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	return if !$submission;
	return if $submission->{'type'} ne 'profiles';
	my $profile_submission = $self->{'submissionHandler'}->get_profile_submission($submission_id);
	return if !$profile_submission;
	my $profiles    = $profile_submission->{'profiles'};
	my $scheme_id   = $profile_submission->{'scheme_id'};
	my $set_id      = $self->get_set_id;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );

	if ( $q->param('curate') && $q->param('update') ) {
		$self->_update_profile_submission_profile_status( $submission_id, $profiles );
	}
	say q(<fieldset style="float:left"><legend>Profiles</legend>);
	my $csv_icon = $self->get_file_icon('CSV');
	my $plural   = @$profiles == 1 ? '' : 's';
	say qq(<p>You are submitting the following $scheme_info->{'name'} profile$plural: )
	  . qq(<a href="/submissions/$submission_id/profiles.txt">Download$csv_icon</a></p>)
	  if ( $options->{'download_link'} );
	say $q->start_form;
	my $status = $self->_print_profile_table( $submission_id, $options );
	$self->_print_update_button( { mark_all => 1 } ) if $options->{'curate'} && !$status->{'all_assigned'};
	say $q->hidden($_) foreach qw(db page submission_id curate);
	say $q->end_form;
	local $" = q(,);
	my $pending_profiles_string = "@{$status->{'pending_profiles'}}";
	local $" = q( );

	if ( $options->{'curate'} && !$status->{'all_assigned_or_rejected'} ) {
		say $q->start_form( -action => $self->{'system'}->{'curate_script'} );
		say $q->submit( -name => 'Batch curate', -class => 'submit', -style => 'margin-top:0.5em' );
		my $page = $q->param('page');
		$q->param( page            => 'profileBatchAdd' );
		$q->param( scheme_id       => $scheme_id );
		$q->param( profile_indexes => $pending_profiles_string );
		say $q->hidden($_) foreach qw( db page submission_id scheme_id profile_indexes  );
		say $q->end_form;

		#Restore value
		$q->param( page => $page );
	}
	say q(</fieldset>);
	$self->{'all_assigned_or_rejected'} = $status->{'all_assigned_or_rejected'};
	return;
}

sub _print_isolate_table_fieldset {
	my ( $self, $submission_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q          = $self->{'cgi'};
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	return if !$submission;
	return if $submission->{'type'} ne 'isolates' && $submission->{'type'} ne 'genomes';
	my $isolate_submission = $self->{'submissionHandler'}->get_isolate_submission($submission_id);
	return if !$isolate_submission;
	my $isolates = $isolate_submission->{'isolates'};
	my $order    = $isolate_submission->{'order'};
	say q(<fieldset><legend>Isolates</legend>);
	my $csv_icon = $self->get_file_icon('CSV');
	my $plural   = @$isolates == 1 ? '' : 's';
	say qq(<p>You are submitting the following isolate$plural: )
	  . qq(<a href="/submissions/$submission_id/isolates.txt">Download$csv_icon</a></p>)
	  if ( $options->{'download_link'} );
	say $q->start_form;
	$self->_print_isolate_table( $submission_id, $options );
	say q(<p><span style="color:red">Missing contig assembly files are shown in red.</span>)
	  if $self->{'contigs_missing'};
	$self->_print_update_button( { record_status => 1 } ) if $options->{'curate'};
	say $q->hidden($_) foreach qw(db page submission_id curate);
	say $q->end_form;

	if ( $options->{'curate'} && !$submission->{'outcome'} && !$self->{'contigs_missing'} ) {
		say $q->start_form( -action => $self->{'system'}->{'curate_script'} );
		say $q->submit( -name => 'Batch curate', -class => 'submit', -style => 'margin-top:0.5em' );
		my $page = $q->param('page');
		$q->param( page   => 'batchAdd' );
		$q->param( table  => 'isolates' );
		$q->param( submit => 1 );
		say $q->hidden($_) foreach qw(db page submission_id table submit);
		say $q->end_form;

		#Restore value
		$q->param( page => $page );
	}
	say q(</fieldset>);
	say q(<div id="dialog"></div>);
	$self->{'all_assigned_or_rejected'} = $submission->{'outcome'} ? 1 : 0;
	return;
}

sub _print_assembly_table_fieldset {
	my ( $self, $submission_id, $options ) = @_;
	my $q          = $self->{'cgi'};
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	return if !$submission;
	return if $submission->{'type'} ne 'assemblies';
	my $add_genome_submission = $self->{'submissionHandler'}->get_assembly_submission($submission_id);
	return if !$add_genome_submission;
	my @isolates;
	push @isolates, $_->{'id'} foreach @$add_genome_submission;
	say q(<fieldset><legend>Assemblies</legend>);
	my $csv_icon = $self->get_file_icon('CSV');
	my $plural   = @isolates == 1 ? '' : 's';
	say qq(<p>You are submitting the following isolate$plural: ) if $options->{'download_link'};
	say $q->start_form;
	my $status = $self->_print_assembly_table( $submission_id, $options );
	say q(<p><span style="color:red">Missing contig assembly files are shown in red.</span>)
	  if $self->{'contigs_missing'};
	$self->_print_update_button( { record_status => 1, no_accepted => 1 } ) if $options->{'curate'};
	say $q->hidden($_) foreach qw(db page submission_id curate);
	say $q->end_form;

	if ( $options->{'curate'} && !$submission->{'outcome'} && !$self->{'contigs_missing'} ) {
		my $validated =
		  $self->{'datastore'}->run_query(
			'SELECT isolate_id AS id,sequence_method,filename FROM assembly_submissions WHERE submission_id=?',
			$submission_id, { fetch => 'all_arrayref', slice => {} } );
		$self->_write_validated_temp_file( $validated, "$submission_id.json" );
		say $q->start_form( -action => $self->{'system'}->{'curate_script'} );
		say $q->submit( -name => 'Batch upload', -class => 'submit', -style => 'margin-top:0.5em' );
		my $page = $q->param('page');
		$q->param( page      => 'batchAddSeqbin' );
		$q->param( validate  => 1 );
		$q->param( field     => 'id' );
		$q->param( temp_file => "$submission_id.json" );
		$q->param( sender    => $submission->{'submitter'} );
		say $q->hidden($_) foreach qw( db page submission_id field validate temp_file sender);
		say $q->end_form;

		#Restore value
		$q->param( page => $page );
	}
	say q(</fieldset>);
	$self->{'all_assigned_or_rejected'} = $submission->{'outcome'} ? 1 : 0;
	return;
}

sub _write_validated_temp_file {
	my ( $self, $validated, $filename ) = @_;
	my $json = encode_json($validated);
	my $full_file_path;
	if ($filename) {
		if ( $filename =~ /(BIGSdb_\d+_\d+_\d+\.json)/x ) {    #Untaint
			$full_file_path = "$self->{'config'}->{'secure_tmp_dir'}/$1";
		}
	} else {
		do {
			$filename       = BIGSdb::Utils::get_random() . '.json';
			$full_file_path = "$self->{'config'}->{'secure_tmp_dir'}/$filename";
		} while ( -e $full_file_path );
	}
	open( my $fh, '>:raw', $full_file_path ) || $logger->error("Cannot open $full_file_path for writing");
	say $fh $json;
	close $fh;
	return $filename;
}

sub _check_new_alleles {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $locus  = $q->param('locus');
	if ( !$locus ) {
		return { err => ['No locus is selected.'] };
	}
	$locus =~ s/^cn_//x;
	$q->param( locus => $locus );
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( !$locus_info ) {
		return { err => ["Locus $locus is not recognized."] };
	}
	if ( $q->param('fasta') ) {
		my $fasta_string = $q->param('fasta');
		$fasta_string =~ s/^\s*//x;
		$fasta_string =~ s/\n\s*/\n/xg;
		$fasta_string = ">seq\n$fasta_string" if $fasta_string !~ /^\s*>/x;
		return $self->{'submissionHandler'}
		  ->check_new_alleles_fasta( $locus, \$fasta_string, { ignore_length => ( $q->param('ignore_length') // 0 ) } );
	}
	return;
}

sub _start_submission {
	my ( $self, $type ) = @_;
	$logger->logdie("Invalid submission type '$type'")
	  if none { $type eq $_ } qw (alleles profiles isolates genomes assemblies);
	my $submission_id =
		'BIGSdb_'
	  . strftime( '%Y%m%d%H%M%S', localtime ) . '_'
	  . sprintf( '%06d', $$ ) . '_'
	  . sprintf( '%05d', int( rand(99999) ) );
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $dataset   = ( $self->{'system'}->{'separate_dataset'} // q() ) eq 'yes' ? $self->{'instance'} : undef;
	eval {
		$self->{'db'}->do(
			'INSERT INTO submissions (id,type,submitter,date_submitted,datestamp,status,dataset) '
			  . 'VALUES (?,?,?,?,?,?,?)',
			undef, $submission_id, $type, $user_info->{'id'}, 'now', 'now', 'started', $dataset
		);
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return $submission_id;
}

sub _get_started_submission_id {
	my ($self) = @_;
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	return $self->{'datastore'}->run_query(
		'SELECT id FROM submissions WHERE (submitter,status)=(?,?)',
		[ $user_info->{'id'}, 'started' ],
		{ cache => 'SubmitPage::get_started_submission' }
	);
}

sub _start_allele_submission {
	my ( $self, $submission_id, $locus, $seqs ) = @_;
	my $q = $self->{'cgi'};
	eval {
		$self->{'db'}->do(
			'INSERT INTO allele_submissions (submission_id,locus,technology,read_length,coverage,assembly,'
			  . 'software) VALUES (?,?,?,?,?,?,?)',
			undef,
			$submission_id,
			$locus,
			scalar $q->param('technology'),
			scalar $q->param('read_length'),
			scalar $q->param('coverage'),
			scalar $q->param('assembly'),
			scalar $q->param('software'),
		);
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
		return;
	}
	if (@$seqs) {
		my $index = 1;
		my $insert_sql =
		  $self->{'db'}->prepare(
			'INSERT INTO allele_submission_sequences (submission_id,index,seq_id,sequence,status) VALUES (?,?,?,?,?)');
		foreach my $seq (@$seqs) {
			eval {
				$insert_sql->execute( $submission_id, $index, ( $seq->{'seq_id'} // '' ),
					$seq->{'sequence'}, 'pending' );
			};
			if ($@) {
				$logger->error($@);
				$self->{'db'}->rollback;
				return;
			}
			$index++;
		}
		$self->{'submissionHandler'}->write_submission_allele_FASTA($submission_id);
	}
	$self->{'db'}->commit;
	return;
}

sub _start_profile_submission {
	my ( $self, $submission_id, $scheme_id, $profiles ) = @_;
	eval {
		$self->{'db'}->do( 'INSERT INTO profile_submissions (submission_id,scheme_id) VALUES (?,?)',
			undef, $submission_id, $scheme_id, );
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
		return;
	}
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	if (@$profiles) {
		my $index = 1;
		foreach my $profile (@$profiles) {
			eval {
				$self->{'db'}->do(
					'INSERT INTO profile_submission_profiles (index,submission_id,profile_id,status) VALUES (?,?,?,?)',
					undef, $index, $submission_id, $profile->{'id'}, 'pending'
				);
				foreach my $locus (@$loci) {
					$self->{'db'}->do(
						'INSERT INTO profile_submission_designations (submission_id,profile_id,locus,'
						  . 'allele_id) VALUES (?,?,?,?)',
						undef, $submission_id, $profile->{'id'}, $locus, $profile->{$locus}
					);
				}
			};
			if ($@) {
				$logger->error($@);
				$self->{'db'}->rollback;
				return;
			}
			$index++;
		}
		$self->{'submissionHandler'}->write_profile_csv($submission_id);
	}
	$self->{'db'}->commit;
	return;
}

sub _start_isolate_submission {
	my ( $self, $submission_id, $isolates, $positions ) = @_;
	eval {
		foreach my $field ( keys %$positions ) {
			$self->{'db'}->do( 'INSERT INTO isolate_submission_field_order (submission_id,field,index) VALUES (?,?,?)',
				undef, $submission_id, $field, $positions->{$field} );
		}
		my $i = 1;
		foreach my $isolate (@$isolates) {
			foreach my $field ( keys %$isolate ) {
				next if !defined $isolate->{$field} || $isolate->{$field} eq '';
				$self->{'db'}
				  ->do( 'INSERT INTO isolate_submission_isolates (submission_id,index,field,value) VALUES (?,?,?,?)',
					undef, $submission_id, $i, $field, $isolate->{$field} );
			}
			$i++;
		}
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
		return;
	}
	$self->{'db'}->commit;
	$self->{'submissionHandler'}->write_isolate_csv($submission_id);
	return;
}

sub _start_assemblies_submission {
	my ( $self, $submission_id, $cleaned_list ) = @_;
	eval {
		my $i = 1;
		foreach my $record (@$cleaned_list) {
			$self->{'db'}->do(
				'INSERT INTO assembly_submissions (submission_id,index,isolate_id,isolate,sequence_method,filename) '
				  . 'VALUES (?,?,?,?,?,?)',
				undef,
				$submission_id,
				$i,
				$record->{'id'},
				$record->{'isolate'},
				$record->{'sequence_method'},
				$record->{'filename'}
			);
			$i++;
		}
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
		return;
	}
	$self->{'db'}->commit;
	return;
}

sub _print_abort_form {
	my ( $self, $submission_id ) = @_;
	my $q = $self->{'cgi'};
	say $q->start_form;
	say $q->submit( -name => 'submit', -label => 'Abort submission', -class => 'small_submit' );
	$q->param( confirm       => 1 );
	$q->param( abort         => 1 );
	$q->param( submission_id => $submission_id );
	say $q->hidden($_) foreach qw(db page submission_id abort confirm);
	say $q->end_form;
	$q->param( abort => 0 );
	return;
}

sub _print_file_upload_fieldset {
	my ( $self, $submission_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	if ( $options->{'no_add'} ) {
		$self->_print_file_fieldset($submission_id);
		return;
	}
	if ( $submission_id =~ /(BIGSdb_\d+_\d+_\d+)/x ) {    #Untaint
		$submission_id = $1;
		if ( $q->param('file_upload') ) {
			$self->_upload_files($submission_id);
		}
		if ( $q->param('delete') ) {
			$self->_delete_selected_submission_files($submission_id);
			$q->delete('delete');
		}
	}
	say q(<fieldset style="float:left"><legend>Supporting files</legend>);
	my $nice_file_size = BIGSdb::Utils::get_nice_size( $self->{'config'}->{'max_upload_size'} );
	my $submission     = $self->{'submissionHandler'}->get_submission($submission_id);
	if ( $options->{'genomes'} ) {
		say q(<p>Please upload contig assemblies with the filenames as specified in the assembly_filename field. );
	} elsif ( $submission->{'type'} eq 'isolates' ) {
		say q(<p>Please upload any supporting files required for curation although it's usually not )
		  . q(necessary for isolate submissions. );
	} else {
		say q(<p>Please upload any supporting files required for curation. Ensure that these are named unambiguously )
		  . q(or add an explanatory note so that they can be linked to the appropriate submission item. );
	}
	say qq(You can upload up to $nice_file_size at a time. If your total submission is larger than this then )
	  . qq(drag and drop files in batches of up to $nice_file_size.</p>);
	say $q->start_form( -id => 'file_upload_form' );
	say q(<div class="fallback">);
	print $q->filefield( -name => 'file_upload', -id => 'file_upload', -multiple );
	say $q->submit( -name => 'Upload files', -class => 'small_submit' );
	say q(</div>);
	say q(<div class="dz-message">Drop files here or click to upload.</div>);
	$q->param( no_check => 1 );
	say $q->hidden($_)
	  foreach qw(db page alleles profiles isolates genomes assemblies locus submit submission_id no_check view);
	say $q->end_form;
	my $files = $self->_get_submission_files($submission_id);

	if (@$files) {
		say $q->start_form;
		say q(<h2>Uploaded files</h2>);
		$self->_print_submission_file_table( $submission_id,
			{ delete_checkbox => $submission->{'status'} eq 'started' ? 1 : 0 } );
		$q->param( delete => 1 );
		say $q->hidden($_)
		  foreach qw(db page alleles profiles isolates genomes assemblies locus submission_id delete no_check view);
		if ( $submission->{'status'} eq 'started' ) {
			say $q->submit( -label => 'Delete selected files', -class => 'small_submit' );
		}
		say $q->end_form;
	}
	say q(</fieldset>);
	return;
}

sub _presubmit_alleles {
	my ( $self, $submission_id, $seqs ) = @_;
	$seqs //= [];
	return if !$submission_id && !@$seqs;
	my $q = $self->{'cgi'};
	my $locus;
	if ( !$submission_id ) {
		$locus         = $q->param('locus');
		$submission_id = $self->_start_submission('alleles');
		$self->_start_allele_submission( $submission_id, $locus, $seqs );
	}
	my $allele_submit_message = "$self->{'dbase_config_dir'}/$self->{'instance'}/allele_submit.html";
	$self->print_file($allele_submit_message) if -e $allele_submit_message;
	say q(<div class="box" id="resultstable"><div class="scrollable">);
	$self->_print_abort_form($submission_id);
	say qq(<h2>Submission: $submission_id</h2>);
	$self->_print_file_upload_fieldset($submission_id);
	$self->_print_sequence_table_fieldset( $submission_id, { download_link => 1 } );
	say $q->start_form;
	$self->_print_sequence_details_fieldset($submission_id);
	$self->_print_email_fieldset($submission_id);
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Finalize submission!' } );
	$q->param( finalize      => 1 );
	$q->param( submission_id => $submission_id );
	say $q->hidden($_) foreach qw(db page locus submit finalize submission_id);
	say $q->end_form;
	$self->_print_message_fieldset($submission_id);
	say q(</div></div>);
	return;
}

sub _presubmit_profiles {
	my ( $self, $submission_id, $profiles ) = @_;
	$profiles //= [];
	return if !$submission_id && !@$profiles;
	my $scheme_id;
	my $q = $self->{'cgi'};
	if ( !$submission_id ) {
		$scheme_id     = $q->param('scheme_id');
		$submission_id = $self->_start_submission('profiles');
		$self->_start_profile_submission( $submission_id, $scheme_id, $profiles );
	}
	my $profile_submit_message = "$self->{'dbase_config_dir'}/$self->{'instance'}/profile_submit.html";
	$self->print_file($profile_submit_message) if -e $profile_submit_message;
	say q(<div class="box" id="resultstable"><div class="scrollable">);
	$self->_print_abort_form($submission_id);
	say qq(<h2>Submission: $submission_id</h2>);
	$self->_print_file_upload_fieldset($submission_id);
	$self->_print_profile_table_fieldset( $submission_id, { download_link => 1 } );
	say $q->start_form;
	$self->_print_email_fieldset($submission_id);
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Finalize submission!' } );
	$q->param( finalize      => 1 );
	$q->param( submission_id => $submission_id );
	say $q->hidden($_) foreach qw(db page submit finalize submission_id);
	say $q->end_form;
	$self->_print_message_fieldset($submission_id);
	say q(</div></div>);
	return;
}

sub _presubmit_isolates {
	my ( $self, $args ) = @_;
	my ( $submission_id, $isolates, $positions, $options ) = @{$args}{qw(submission_id isolates positions options)};
	$isolates //= [];
	return if !$submission_id && !@$isolates;
	my $q = $self->{'cgi'};
	if ( !$submission_id ) {
		my $type = $options->{'genomes'} ? 'genomes' : 'isolates';
		$submission_id = $self->_start_submission($type);
		$self->_start_isolate_submission( $submission_id, $isolates, $positions );
	}
	if ( !$options->{'genomes'} ) {
		if ( !$self->_are_any_alleles_designated($submission_id) ) {
			say q(<div class="box statuswarn"><p>Your isolate submission does not include any allele designations. )
			  . q(Please make sure that this is your intent. If it is not, then please abort the submission and )
			  . q(restart.</p></div>);
		} else {
			my $isolate_submit_message = "$self->{'dbase_config_dir'}/$self->{'instance'}/isolate_submit.html";
			if ( -e $isolate_submit_message ) {
				$self->print_file($isolate_submit_message);
			}
		}
	}
	say q(<div class="box" id="resultstable"><div class="scrollable">);
	$self->_print_abort_form($submission_id);
	say qq(<h2>Submission: $submission_id</h2>);
	$options->{'download_link'} = 1;
	$self->_print_file_upload_fieldset( $submission_id, $options ) if $options->{'genomes'};
	$self->_print_isolate_table_fieldset( $submission_id, $options );
	$self->_print_message_fieldset($submission_id);
	say $q->start_form;
	$self->_print_email_fieldset($submission_id);

	if ( $self->{'failed_validation'} ) {
		say q(<div style="clear:both"></div><div><p>One or more of your assemblies has <span class="fail">)
		  . q(failed basic validation</span> checks. This submission cannot be finalized. Please )
		  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit&amp;)
		  . qq(submission_id=$submission_id&amp;abort=1&amp;confirm=1">abort this submission</a>.</p></div>);
	} elsif ( !$self->{'contigs_missing'} ) {
		$self->print_action_fieldset( { no_reset => 1, submit_label => 'Finalize submission!' } );
	}
	$q->param( finalize      => 1 );
	$q->param( submission_id => $submission_id );
	say $q->hidden($_) foreach qw(db page submit finalize submission_id);
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub _are_any_alleles_designated {
	my ( $self, $submission_id ) = @_;
	my $fields =
	  $self->{'datastore'}->run_query( 'SELECT DISTINCT(field) FROM isolate_submission_isolates WHERE submission_id=?',
		$submission_id, { fetch => 'col_arrayref' } );
	my $set_id = $self->get_set_id;
	foreach my $field (@$fields) {
		if ($set_id) {
			$field = $self->{'datastore'}->get_set_locus_real_id( $field, $set_id );
		}
		if ( $self->{'datastore'}->is_locus( $field, { set_id => $set_id } ) ) {
			return 1;
		}
	}
	return;
}

sub _presubmit_assemblies {
	my ( $self, $args ) = @_;
	my ( $submission_id, $cleaned_list, $wrong_sender ) = @{$args}{qw(submission_id cleaned_list wrong_sender)};
	return if !$submission_id && !@$cleaned_list;
	my $q           = $self->{'cgi'};
	my $invalid_ids = [];
	if ( !$submission_id ) {
		$submission_id = $self->_start_submission('assemblies');
		$self->_start_assemblies_submission( $submission_id, $cleaned_list );
	} else {
		my $checks = $self->_get_assembly_wrong_sender($submission_id);
		$wrong_sender = $checks->{'wrong_sender'};
		$invalid_ids  = $checks->{'invalid_ids'};
	}
	if ( $wrong_sender || @$invalid_ids ) {
		$self->_print_assembly_warnings( $wrong_sender, $invalid_ids );
	}
	say q(<div class="box" id="resultstable"><div class="scrollable">);
	$self->_print_abort_form($submission_id);
	say qq(<h2>Submission: $submission_id</h2>);
	$self->_print_file_upload_fieldset( $submission_id, { download_link => 1 } );
	$self->_print_assembly_table_fieldset( $submission_id, { download_link => 1 } );
	$self->_print_message_fieldset($submission_id);
	say $q->start_form;
	$self->_print_email_fieldset($submission_id);

	if ( $self->{'failed_validation'} ) {
		say q(<div style="clear:both"></div><div><p>One or more of your assemblies has <span class="fail">)
		  . q(failed basic validation</span> checks. This submission cannot be finalized. Please )
		  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit&amp;)
		  . qq(submission_id=$submission_id&amp;abort=1&amp;confirm=1">abort this submission</a>.</p></div>);
	} elsif ( !$self->{'contigs_missing'} ) {
		$self->print_action_fieldset( { no_reset => 1, submit_label => 'Finalize submission!' } );
	}
	$q->param( finalize      => 1 );
	$q->param( submission_id => $submission_id );
	say $q->hidden($_) foreach qw(db page submit finalize submission_id);
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub _print_assembly_warnings {
	my ( $self, $wrong_sender, $invalid_ids ) = @_;
	my @ids = sort @$wrong_sender;
	return if !@$wrong_sender && ( !defined $invalid_ids || !@$invalid_ids );
	say q(<div class="box" id="resultspanel">);
	say q(<h2>Advisories</h2>);
	if ( defined $invalid_ids && @$invalid_ids ) {
		my $plural  = @$invalid_ids == 1 ? q()   : q(s);
		my $are_is  = @$invalid_ids == 1 ? q(is) : q(are);
		my $they_it = @$invalid_ids == 1 ? q(It) : q(They);
		say qq(<p>The following isolate id$plural $are_is no longer accessible: @$invalid_ids. )
		  . qq($they_it may have been removed since this submission was started.</p>);
	}
	if (@$wrong_sender) {
		my $plural = @$wrong_sender == 1 ? q() : q(s);
		local $" = q(, );
		say qq(<p>Note that you are not the original sender for the following isolate id$plural: @ids.</p>);
		print q(<p>You can still submit assemblies but please add a message to the curator to confirm why )
		  . q(you are adding assemblies for );
		print @$wrong_sender > 1 ? 'these isolates' : 'this isolate';
	}
	say q(.</p></div>);
	return;
}

sub _print_finalised_assembly_warning {
	my ( $self, $submission_id, $options ) = @_;
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	return if $submission->{'type'} ne 'assemblies';
	my $checks       = $self->_get_assembly_wrong_sender($submission_id);
	my $wrong_sender = $checks->{'wrong_sender'};
	my $invalid_ids  = $checks->{'invalid_ids'};
	if ( @$wrong_sender || @$invalid_ids ) {
		say q(<fieldset style="float:left;max-width:300px"><legend>Advisories</legend>);
		if (@$wrong_sender) {
			local $" = q(, );
			my $record_term = @$wrong_sender == 1 ? q(this record) : q(these records);
			if ( $options->{'view'} ) {
				say qq(<p class="warning">You are not the original sender for isolate ids: @$wrong_sender.</p>);
				print qq(<p>Please ensure that you should be modifying $record_term and add a message to the<br /> )
				  . q(curator to confirm why you should.</p>);
			}
			if ( $options->{'curate'} ) {
				say
				  qq(<p class="warning">The submitter is not the original sender for isolate ids: @$wrong_sender.</p>)
				  . qq(<p>This may be ok, but please check that the submitter should be modifying $record_term.</p>);
			}
		}
		say q(</fieldset>);
	}
	return;
}

sub _print_email_fieldset {
	my ( $self, $submission_id ) = @_;
	return if !$self->{'config'}->{'smtp_server'};
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	return if !$submission;
	my $sender_info = $self->{'datastore'}->get_user_info( $submission->{'submitter'} );
	return if $sender_info->{'email'} !~ /@/x;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left"><legend>E-mail</legend>);
	say qq(<p>Updates will be sent to $sender_info->{'email'}.</p>);
	my %checked;
	$checked{'checked'} = 'checked' if $self->{'prefs'}->{'submit_email'};
	say $q->checkbox( -name => 'email', label => 'E-mail submission updates', %checked );
	say q(</fieldset>);
	return;
}

sub _update_allele_submission_sequence_status {
	my ( $self, $submission_id, $seqs ) = @_;
	my $q = $self->{'cgi'};
	foreach my $seq (@$seqs) {
		my $status = $q->param("status_$seq->{'index'}");
		next if !defined $status;
		eval {
			$self->{'db'}->do( 'UPDATE allele_submission_sequences SET status=? WHERE (submission_id,seq_id)=(?,?)',
				undef, $status, $submission_id, $seq->{'seq_id'} );
		};
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
		}
	}
	return;
}

sub _update_profile_submission_profile_status {
	my ( $self, $submission_id, $profiles ) = @_;
	my $q = $self->{'cgi'};
	foreach my $profile (@$profiles) {
		my $status = $q->param("status_$profile->{'index'}");
		next if !defined $status;
		eval {
			$self->{'db'}->do( 'UPDATE profile_submission_profiles SET status=? WHERE (submission_id,index)=(?,?)',
				undef, $status, $submission_id, $profile->{'index'} );
		};
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
		}
	}
	return;
}

sub _update_isolate_submission_isolate_status {
	my ( $self, $submission_id ) = @_;
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	return if !$submission;
	my $q       = $self->{'cgi'};
	my %outcome = ( accepted => 'good', rejected => 'bad' );
	$self->{'submissionHandler'}->update_submission_outcome( $submission_id, $outcome{ $q->param('record_status') } );
	if ( $q->param('record_status') eq 'accepted' ) {
		say q[<script>$(function(){]
		  . q[$("#dialog").html("<p>Please note that changing the status of an isolate submission to ]
		  . q['accepted' does not automatically upload the records to the database. You need to 'Batch curate' ]
		  . q[the submission in order to upload the records. Change the staus back to 'pending' if you need ]
		  . q[to re-enable the 'Batch curate' button.</p>");$("#dialog").dialog({title:"Uploading isolates"});]
		  . q[});</script>];
	}
	return;
}

sub _print_sequence_table {
	my ( $self, $submission_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q                 = $self->{'cgi'};
	my $submission        = $self->{'submissionHandler'}->get_submission($submission_id);
	my $allele_submission = $self->{'submissionHandler'}->get_allele_submission($submission_id);
	my $seqs              = $allele_submission->{'seqs'};
	my $locus             = $allele_submission->{'locus'};
	my $locus_info        = $self->{'datastore'}->get_locus_info($locus);
	my $cds       = $locus_info->{'data_type'} eq 'DNA' && $locus_info->{'complete_cds'} ? '<th>Complete CDS</th>' : '';
	my $max_width = $self->{'config'}->{'page_max_width'} // PAGE_MAX_WIDTH;
	my $main_max_width = $max_width - 100;
	say qq(<div style="max-width:min(${main_max_width}px, 100vw - 100px)"><div class="scrollable">)
	  . q(<table class="resultstable" style="margin-bottom:0">);
	say qq(<tr><th>Identifier</th><th>Length</th><th>Sequence</th>$cds<th>Status</th><th>Query</th>)
	  . q(<th>Assigned allele</th></tr>);
	my ( $all_assigned, $all_rejected, $all_assigned_or_rejected ) = ( 1, 1, 1 );
	my $td           = 1;
	my $pending_seqs = [];

	foreach my $seq (@$seqs) {
		my $id       = $seq->{'seq_id'};
		my $length   = length $seq->{'sequence'};
		my $sequence = BIGSdb::Utils::truncate_seq( \$seq->{'sequence'}, 40 );
		$cds = '';
		if ( $locus_info->{'data_type'} eq 'DNA' && $locus_info->{'complete_cds'} ) {
			my $start_codons = $self->{'datastore'}->get_start_codons( { locus => $locus } );
			$cds = q(<td>)
			  . (
				BIGSdb::Utils::is_complete_cds( \$seq->{'sequence'}, { start_codons => $start_codons } )->{'cds'}
				? GOOD
				: BAD
			  ) . q(</td>);
		}
		my $display_id = BIGSdb::Utils::escape_html($id);
		say qq(<tr class="td$td"><td>$display_id</td><td>$length</td>);
		say qq(<td class="seq">$sequence</td>$cds);
		$seq->{'sequence'} =~ s/-//gx;
		my $assigned = $self->{'datastore'}->run_query(
			'SELECT allele_id FROM sequences WHERE (locus,md5(sequence))=(?,md5(?))',
			[ $allele_submission->{'locus'}, uc( $seq->{'sequence'} ) ],
			{ cache => 'SubmitPage::print_sequence_table_fieldset' }
		);
		if ( !defined $assigned ) {
			if ( defined $seq->{'assigned_id'} ) {
				$self->{'submissionHandler'}->clear_assigned_seq_id( $submission_id, $seq->{'seq_id'} );
			}
			if ( $seq->{'status'} eq 'assigned' ) {
				$self->{'submissionHandler'}->set_allele_status( $submission_id, $seq->{'seq_id'}, 'pending', undef );
			}
			push @$pending_seqs, $seq if $seq->{'status'} ne 'rejected';
		} else {
			if ( $seq->{'status'} eq 'pending' || $seq->{'status'} eq 'rejected' ) {
				$self->{'submissionHandler'}
				  ->set_allele_status( $submission_id, $seq->{'seq_id'}, 'assigned', $assigned );
				$seq->{'status'} = 'assigned';
			}
			$all_rejected = 0;
		}
		$assigned //= '';
		if ( $options->{'curate'} && !$assigned ) {
			say q(<td>);
			say $q->popup_menu(
				-name    => "status_$seq->{'index'}",
				-values  => [qw(pending rejected)],
				-default => $seq->{'status'}
			);
			say q(</td>);
			if ( $seq->{'status'} ne 'rejected' ) {
				$all_rejected             = 0;
				$all_assigned_or_rejected = 0;
			}
			$all_assigned = 0;
		} else {
			say qq(<td>$seq->{'status'}</td>);
		}
		my $query = QUERY;
		say qq(<td><a href="$self->{'system'}->{'query_script'}?db=$self->{'instance'}&amp;page=sequenceQuery&amp;)
		  . qq(locus=$locus&amp;submission_id=$submission_id&amp;populate_seqs=1&amp;index=$seq->{'index'}&amp;)
		  . qq(submit=1" target="_blank">$query</a></td>);
		my $edit = EDIT;
		if ( $options->{'curate'} && $seq->{'status'} ne 'rejected' && $assigned eq '' ) {
			say qq(<td><a href="$self->{'system'}->{'curate_script'}?db=$self->{'instance'}&amp;page=add&amp;)
			  . qq(table=sequences&amp;locus=$locus&amp;submission_id=$submission_id&amp;populate_seqs=1&amp;)
			  . qq(index=$seq->{'index'}&amp;sender=$submission->{'submitter'}&amp;status=unchecked">)
			  . qq(${edit}Curate</a></td>);
		} else {
			say qq(<td>$assigned</td>);
		}
		say q(</tr>);
		$td = $td == 1 ? 2 : 1;
		$self->{'mod_perl_request'}->rflush if $ENV{'MOD_PERL'};
	}
	say q(</table></div></div>);
	if ( $options->{'curate'} ) {
		my $outcome;
		if ( !@$pending_seqs ) {
			$outcome = $self->_get_outcome(
				{
					all_assigned => $all_assigned,
					all_rejected => $all_rejected
				}
			);
		} else {
			undef $outcome;
		}
		$self->{'submissionHandler'}->update_submission_outcome( $submission_id, $outcome );
	}
	return {
		all_assigned_or_rejected => $all_assigned_or_rejected,
		all_assigned             => $all_assigned,
		pending_seqs             => $pending_seqs
	};
}

sub _get_outcome {
	my ( $self,         $args )         = @_;
	my ( $all_assigned, $all_rejected ) = @{$args}{qw(all_assigned all_rejected)};
	if ($all_assigned) {
		return 'good';
	} elsif ($all_rejected) {
		return 'bad';
	}
	return 'mixed';
}

sub _print_profile_table {
	my ( $self, $submission_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q                  = $self->{'cgi'};
	my $submission         = $self->{'submissionHandler'}->get_submission($submission_id);
	my $profile_submission = $self->{'submissionHandler'}->get_profile_submission($submission_id);
	my $profiles           = $profile_submission->{'profiles'};
	my $scheme_id          = $profile_submission->{'scheme_id'};
	my $scheme_info        = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my ( $all_assigned, $all_rejected, $all_assigned_or_rejected ) = ( 1, 1, 1 );
	my $pending_profiles = [];
	my $loci             = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $max_width        = $self->{'config'}->{'page_max_width'} // PAGE_MAX_WIDTH;
	my $main_max_width   = $max_width - 100;
	say qq(<div style="max-width:min(${main_max_width}px, 100vw - 100px)"><div class="scrollable">)
	  . q(<table class="resultstable" style="margin-bottom:0">);
	say q(<tr><th>Identifier</th>);

	foreach my $locus (@$loci) {
		my $clean_locus = $self->clean_locus($locus);
		print qq(<th>$clean_locus</th>);
	}
	say qq(<th>Status</th><th>Query</th><th>Assigned $scheme_info->{'primary_key'}</th></tr>);
	my $td    = 1;
	my $index = 1;
	foreach my $profile ( @{ $profile_submission->{'profiles'} } ) {
		say qq(<tr class="td$td"><td>$profile->{'profile_id'}</td>);
		foreach my $locus (@$loci) {
			say qq(<td>$profile->{'designations'}->{$locus}</td>);
		}
		my $profile_status = $self->{'datastore'}->check_new_profile( $scheme_id, $profile->{'designations'} );
		my $assigned;
		if ( !$profile_status->{'exists'} ) {
			if ( defined $profile->{'assigned_id'} ) {
				$self->{'submissionHandler'}->clear_assigned_profile_id( $submission_id, $profile->{'profile_id'} );
				$profile->{'assigned_id'} = undef;
			}
			if ( $profile->{'status'} eq 'assigned' ) {
				$self->{'submissionHandler'}
				  ->set_profile_status( $submission_id, $profile->{'profile_id'}, 'pending', undef );
				$profile->{'status'} = 'pending';
			}
			push @$pending_profiles, $profile->{'index'} if $profile->{'status'} ne 'rejected';
		} else {
			$assigned = $profile_status->{'assigned'}->[0];
			if ( $profile->{'status'} ne 'assigned' || ( $profile->{'assigned_id'} // '' ) ne $assigned ) {
				$self->{'submissionHandler'}
				  ->set_profile_status( $submission_id, $profile->{'profile_id'}, 'assigned', $assigned );
				$profile->{'status'}      = 'assigned';
				$profile->{'assigned_id'} = $assigned;
			}
			$all_rejected = 0;
		}
		$assigned //= '';
		if ( $options->{'curate'} && !$assigned ) {
			say q(<td>);
			say $q->popup_menu(
				-name    => "status_$profile->{'index'}",
				-values  => [qw(pending rejected)],
				-default => $profile->{'status'}
			);
			say q(</td>);
			if ( $profile->{'status'} ne 'rejected' ) {
				$all_assigned_or_rejected = 0;
				$all_assigned_or_rejected = 0;
			}
			$all_assigned = 0;
		} else {
			say qq(<td>$profile->{'status'}</td>);
		}
		my $query = QUERY;
		say qq(<td><a href="$self->{'system'}->{'query_script'}?db=$self->{'instance'}&amp;page=profiles&amp;)
		  . qq(scheme_id=$scheme_id&amp;submission_id=$submission_id&amp;populate_profiles=1&amp;)
		  . qq(index=$profile->{'index'}&amp;submit=1" target="_blank">$query</a></td>);
		if ( $options->{'curate'} && $profile->{'status'} ne 'rejected' && $assigned eq '' ) {
			say qq(<td><a href="$self->{'system'}->{'curate_script'}?db=$self->{'instance'}&amp;page=profileAdd&amp;)
			  . qq(scheme_id=$scheme_id&amp;submission_id=$submission_id&amp;index=$index">)
			  . EDIT
			  . q(Curate</a></td>);
		} else {
			say qq(<td>$assigned</td>);
		}
		say q(</tr>);
		$td = $td == 1 ? 2 : 1;
		$index++;
	}
	if ( $options->{'curate'} ) {
		my $outcome;
		if ( !@$pending_profiles ) {
			$outcome = $self->_get_outcome(
				{
					all_assigned => $all_assigned,
					all_rejected => $all_rejected
				}
			);
		} else {
			undef $outcome;
		}
		$self->{'submissionHandler'}->update_submission_outcome( $submission_id, $outcome );
	}
	say q(</table></div></div>);
	return {
		all_assigned_or_rejected => $all_assigned_or_rejected,
		all_assigned             => $all_assigned,
		pending_profiles         => $pending_profiles
	};
}

sub _get_completed_schemes {
	my ( $self, $submission_id ) = @_;
	my $isolate_submission = $self->{'submissionHandler'}->get_isolate_submission($submission_id);
	my $fields =
	  $self->{'submissionHandler'}
	  ->get_populated_fields( $isolate_submission->{'isolates'}, $isolate_submission->{'order'} );
	my %populated = map { $_ => 1 } @$fields;
	my $set_id    = $self->get_set_id;
	my $schemes =
	  $self->{'datastore'}->get_scheme_list( { set_id => $set_id, with_pk => 1 } );
	my $list = [];
	foreach my $scheme (@$schemes) {
		my $loci          = $self->{'datastore'}->get_scheme_loci( $scheme->{'id'}, { profile_name => 1 } );
		my $all_populated = 1;
		foreach my $locus (@$loci) {
			if ( !$populated{$locus} ) {
				$all_populated = 0;
				last;
			}
		}
		push @$list, $scheme->{'id'} if $all_populated;
	}
	return $list;
}

sub _print_isolate_table {
	my ( $self, $submission_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q                  = $self->{'cgi'};
	my $submission         = $self->{'submissionHandler'}->get_submission($submission_id);
	my $isolate_submission = $self->{'submissionHandler'}->get_isolate_submission($submission_id);
	my $isolates           = $isolate_submission->{'isolates'};
	my $fields =
	  $self->{'submissionHandler'}
	  ->get_populated_fields( $isolate_submission->{'isolates'}, $isolate_submission->{'order'} );
	my $schemes       = $self->_get_completed_schemes($submission_id);
	my $scheme_fields = {};

	foreach my $scheme_id (@$schemes) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		if ( $scheme_info->{'primary_key'} ) {
			my $field = qq($scheme_info->{'primary_key'} ($scheme_info->{'name'}));
			push @$fields, $field;
			$scheme_fields->{$field} = {
				scheme_id => $scheme_id,
				field     => $scheme_info->{'primary_key'}
			};
		}
	}
	my $max_width      = $self->{'config'}->{'page_max_width'} // PAGE_MAX_WIDTH;
	my $main_max_width = $max_width - 100;
	say qq(<div style="max-width:min(${main_max_width}px, 100vw - 100px)"><div class="scrollable">)
	  . q(<table class="resultstable" style="margin-bottom:0"><tr>);
	say qq(<th>$_</th>) foreach @$fields;
	my $rmlst_analysis;
	if ( $submission->{'type'} eq 'genomes' ) {
		say q(<th>contigs</th><th>total length (bp)</th><th>N50</th>);
		$rmlst_analysis = $self->_get_rmlst_analysis($submission_id);
		say q(<th>rMLST species prediction</th>) if %$rmlst_analysis;
	}
	say q(</tr>);
	my $td = 1;
	local $" = q(</td><td>);
	my $files       = $self->_get_submission_files($submission_id);
	my %file_exists = map { $_->{'filename'} => 1 } @$files;
	my $dir         = $self->{'submissionHandler'}->get_submission_dir($submission_id) . '/supporting_files';
	my %filename_already_used;
	my $index = 0;

	foreach my $isolate (@$isolates) {
		$index++;
		my @values;
		foreach my $field (@$fields) {
			if ( $field eq 'assembly_filename' ) {
				if ( !-e "$dir/$isolate->{$field}" ) {
					push @values, qq(<span style="color:red">$isolate->{$field}</span>);
					$self->{'contigs_missing'} = 1;
				} else {
					if ( $filename_already_used{ $isolate->{$field} } ) {
						push @values, qq(<span style="color:red">$isolate->{$field} [duplicated]</span>);
						$self->{'contigs_missing'} = 1;
					} else {
						push @values, $isolate->{$field};
					}
					$filename_already_used{ $isolate->{$field} } = 1;
				}
			} elsif ( $scheme_fields->{$field} ) {
				my $scheme_loci = $self->{'datastore'}
				  ->get_scheme_loci( $scheme_fields->{$field}->{'scheme_id'}, { profile_name => 1 } );
				my $designations = {};
				foreach my $locus (@$scheme_loci) {
					$designations->{$locus} = [ { allele_id => $isolate->{$locus}, status => 'confirmed' } ];
				}
				my $field_values =
				  $self->{'datastore'}
				  ->get_scheme_field_values_by_designations( $scheme_fields->{$field}->{'scheme_id'},
					$designations, { no_convert => 1 } );
				my @pk_field_values =
				  keys %{ $field_values->{ lc $scheme_fields->{$field}->{'field'} } };
				push @values, $pk_field_values[0] // q(-);
			} else {
				push @values, $isolate->{$field} // q();
			}
		}
		say qq(<tr class="td$td"><td>@values</td>);
		if ( $submission->{'type'} eq 'genomes' ) {
			$self->_print_genome_stat_fields( $submission_id, $isolate->{'assembly_filename'}, $index );
		}
		say q(</tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</table></div></div>);
	return;
}

sub _print_assembly_table {
	my ( $self, $submission_id, $options ) = @_;
	my $submission          = $self->{'submissionHandler'}->get_submission($submission_id);
	my $assembly_submission = $self->{'submissionHandler'}->get_assembly_submission($submission_id);
	my $max_width           = $self->{'config'}->{'page_max_width'} // PAGE_MAX_WIDTH;
	my $main_max_width      = $max_width - 100;
	say qq(<div style="max-width:min(${main_max_width}px, 100vw - 100px)"><div class="scrollable">)
	  . q(<table class="resultstable" style="margin-bottom:0"><tr><th>id</th>)
	  . qq(<th>$self->{'system'}->{'labelfield'}</th><th>method</th><th>filename</th><th>contigs</th>)
	  . q(<th>total length (bp)</th><th>N50</th>);
	my $rmlst_analysis = $self->_get_rmlst_analysis($submission_id);
	say q(<th>rMLST species prediction</th>) if %$rmlst_analysis;
	say q(</tr>);
	my $td = 1;
	local $" = q(</td><td>);
	my $files       = $self->_get_submission_files($submission_id);
	my %file_exists = map { $_->{'filename'} => 1 } @$files;
	my $dir         = $self->{'submissionHandler'}->get_submission_dir($submission_id) . '/supporting_files';
	my %filename_already_used;
	my $index = 0;

	foreach my $record (@$assembly_submission) {
		my @values;
		push @values, ( $record->{$_} ) foreach qw(isolate_id isolate sequence_method);
		if ( !-e "$dir/$record->{'filename'}" ) {
			push @values, qq(<span style="color:red">$record->{'filename'}</span>);
			$self->{'contigs_missing'} = 1;
		} else {
			push @values, $record->{'filename'};
		}
		say qq(<tr class="td$td"><td>@values</td>);
		$self->_print_genome_stat_fields( $submission_id, $record->{'filename'}, $record->{'index'} );
		$td = $td == 1 ? 2 : 1;
	}
	say q(</table></div></div>);
	return;
}

sub _get_rmlst_analysis {
	my ( $self, $submission_id ) = @_;
	return $self->{'datastore'}->run_query( 'SELECT * FROM genome_submission_analysis WHERE submission_id=?',
		$submission_id, { fetch => 'all_hashref', key => 'index' } );
}

sub _print_genome_stat_fields {
	my ( $self, $submission_id, $assembly_filename, $index ) = @_;
	my $dir            = $self->{'submissionHandler'}->get_submission_dir($submission_id) . '/supporting_files';
	my $assembly_stats = $self->{'submissionHandler'}->get_assembly_stats($submission_id);
	return if !$assembly_filename;
	my $rmlst_analysis = $self->_get_rmlst_analysis($submission_id);
	my $colspan        = %$rmlst_analysis ? 4 : 3;
	if ( -e "$dir/$assembly_filename" ) {
		if ( !$assembly_stats->{$index} ) {
			$assembly_stats->{$index} =
			  $self->{'submissionHandler'}->calc_assembly_stats( $submission_id, $index, $assembly_filename );
		}
		if ( $assembly_stats->{$index}->{'total_length'} == 0 ) {
			say qq(<td colspan="$colspan" class="fail">Invalid file format</td>);
			$self->{'failed_validation'} = 1;
		} else {
			my $warn_max_contigs = $self->{'system'}->{'warn_max_contigs'} // $self->{'config'}->{'warn_max_contigs'}
			  // WARN_MAX_CONTIGS;
			my $max_contigs = $self->{'system'}->{'max_contigs'} // $self->{'config'}->{'max_contigs'} // MAX_CONTIGS;
			my $class       = q();
			if ( $assembly_stats->{$index}->{'contigs'} > $max_contigs ) {
				$class = 'fail';
				$self->{'failed_validation'} = 1;
			} elsif ( $assembly_stats->{$index}->{'contigs'} > $warn_max_contigs ) {
				$class = 'warning';
			}
			say qq(<td class="$class">) . BIGSdb::Utils::commify( $assembly_stats->{$index}->{'contigs'} ) . q(</td>);
			my $warn_min_total_length = $self->{'config'}->{'warn_min_total_length'}
			  // $self->{'system'}->{'warn_min_total_length'} // WARN_MIN_TOTAL_LENGTH;
			my $warn_max_total_length = $self->{'config'}->{'warn_max_total_length'}
			  // $self->{'system'}->{'warn_max_total_length'} // WARN_MAX_TOTAL_LENGTH;
			my $min_total_length = $self->{'config'}->{'min_total_length'} // $self->{'system'}->{'min_total_length'}
			  // MIN_TOTAL_LENGTH;
			my $max_total_length = $self->{'config'}->{'max_total_length'} // $self->{'system'}->{'max_total_length'}
			  // MAX_TOTAL_LENGTH;
			$class = q();
			if (   $assembly_stats->{$index}->{'total_length'} < $min_total_length
				|| $assembly_stats->{$index}->{'total_length'} > $max_total_length )
			{
				$class = 'fail';
				$self->{'failed_validation'} = 1;
			} elsif ( $assembly_stats->{$index}->{'total_length'} < $warn_min_total_length
				|| $assembly_stats->{$index}->{'total_length'} > $warn_max_total_length )
			{
				$class = 'warning';
			}
			say qq(<td class="$class">)
			  . BIGSdb::Utils::commify( $assembly_stats->{$index}->{'total_length'} )
			  . q(</td>);
			my $warn_min_n50 = $self->{'system'}->{'warn_min_n50'} // $self->{'config'}->{'warn_min_n50'}
			  // WARN_MIN_N50;
			my $min_n50 = $self->{'system'}->{'min_n50'} // $self->{'config'}->{'min_n50'} // MIN_N50;
			$class = q();
			if ( $assembly_stats->{$index}->{'n50'} < $min_n50 ) {
				$class = 'fail';
				$self->{'failed_validation'} = 1;
			} elsif ( $assembly_stats->{$index}->{'n50'} < $warn_min_n50 ) {
				$class = 'warning';
			}
			say qq(<td class="$class">) . BIGSdb::Utils::commify( $assembly_stats->{$index}->{'n50'} ) . q(</td>);
			$self->_print_rmlst_analysis( $rmlst_analysis, $index );
		}
	} else {
		if ( $assembly_stats->{$index} ) {
			$self->{'submissionHandler'}->remove_assembly_stats( $submission_id, $index );
		}
		say qq(<td colspan="$colspan">No sequence</td>);
	}
	return;
}

sub _print_rmlst_analysis {
	my ( $self, $rmlst_analysis, $index ) = @_;
	return if !%$rmlst_analysis;
	my $results = $rmlst_analysis->{$index}->{'results'};
	if ($results) {
		my $values = decode_json($results);
		if ( ref $values && ref $values eq 'ARRAY' ) {
			say q(<td><table style="width:100%;height:100%">);
			foreach my $result (@$values) {
				my $colour = BIGSdb::Utils::get_percent_colour( $result->{'support'} );
				say q(<tr>);
				say q(<td class="rmlst_cell" style="position:relative;text-align:left">)
				  . q(<span class="rmlst_result" style="position:absolute;margin-left:1em;font-size:0.8em;white-space:nowrap">)
				  . qq(<em>$result->{'taxon'}</em></span>)
				  . qq(<div style="margin-top:0.2em;background-color:#$colour;border:1px solid #ccc;)
				  . qq(height:0.9em;width:$result->{'support'}%"></div></td></tr>);
			}
			say q(</table></td>);
		} elsif ( ref $values eq 'HASH' && defined $values->{'failed'} ) {
			if ( $values->{'message'} eq 'No match' ) {
				my $tooltip =
				  $self->get_tooltip( q(No match - This means that no exactly matching rMLST alleles linked )
					  . q(exclusively to a single species were found. This may be due to the sequence being more variable )
					  . q(than normal, or may reflect a lack of coverage in the rMLST database.) );
				$values->{'message'} .= qq( $tooltip);
			}
			say qq(<td class="warning">$values->{'message'}</td>);
		} else {
			say q(<td></td>);
			$logger->error('Unrecognised JSON value.');
		}
	} else {
		say q(<td>pending</td>);
	}
	return;
}

sub _print_sequence_table_fieldset {
	my ( $self, $submission_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q          = $self->{'cgi'};
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	return if !$submission;
	return if $submission->{'type'} ne 'alleles';
	my $allele_submission = $self->{'submissionHandler'}->get_allele_submission($submission_id);
	return if !$allele_submission;
	my $seqs = $allele_submission->{'seqs'};

	if ( $q->param('curate') && $q->param('update') ) {
		$self->_update_allele_submission_sequence_status( $submission_id, $seqs );
	}
	my $locus      = $allele_submission->{'locus'};
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	say q(<fieldset style="float:left"><legend>Sequences</legend>);
	my $fasta_icon = $self->get_file_icon('FAS');
	my $plural     = @$seqs == 1 ? '' : 's';
	say qq(<p>You are submitting the following $allele_submission->{'locus'} sequence$plural: )
	  . qq(<a href="/submissions/$submission_id/sequences.fas">Download$fasta_icon</a></p>)
	  if ( $options->{'download_link'} );
	say $q->start_form;
	my $status = $self->_print_sequence_table( $submission_id, $options );
	$self->_print_update_button( { mark_all => 1 } ) if $options->{'curate'} && !$status->{'all_assigned'};
	say $q->hidden($_) foreach qw(db page submission_id curate);
	say $q->end_form;
	my $has_extended_attributes =
	  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM locus_extended_attributes WHERE locus=?)', $locus );

	if ( $options->{'curate'} && !$status->{'all_assigned_or_rejected'} && !$has_extended_attributes ) {
		say $q->start_form( -action => $self->{'system'}->{'curate_script'} );
		say $q->submit(
			-name  => 'Batch curate',
			-class => 'submit',
			-style => 'float:left;margin:0.5em 0.5em 0 0'
		);
		my $page = $q->param('page');
		$q->param( page         => 'batchAddFasta' );
		$q->param( locus        => $locus );
		$q->param( sender       => $submission->{'submitter'} );
		$q->param( status       => 'unchecked' );
		$q->param( sequence     => $self->_get_fasta_string( $status->{'pending_seqs'} ) );
		$q->param( complete_CDS => $locus_info->{'complete_cds'} ? 'on' : 'off' );
		say $q->hidden($_) foreach qw( db page submission_id locus sender status sequence complete_CDS );
		say $q->end_form;
		say $q->start_form( -action => $self->{'system'}->{'query_script'}, -target => '_blank' );
		say $q->submit( -name => 'Batch query', -class => 'submit', -style => 'float:left;margin-top:0.5em' );
		$q->param( page => 'batchSequenceQuery' );
		say $q->hidden($_) foreach qw( db page submission_id locus sequence );
		say $q->hidden( submit => 1 );
		say $q->end_form;
		$q->param( page => $page );    #Restore value
	}
	say q(</fieldset>);
	$self->{'all_assigned_or_rejected'} = $status->{'all_assigned_or_rejected'};
	return;
}

sub _print_update_button {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	say q(<div style="float:right">);
	if ( $options->{'mark_all'} ) {
		say q(<span style="margin-right:1em">)
		  . q(Mark all: <input type="button" onclick='status_markall("pending")' )
		  . q(value="Pending" class="small_reset" /><input type="button" )
		  . q(onclick='status_markall("rejected")' value="Rejected" class="small_reset" />)
		  . q(</span>);
	}
	my $values = $options->{'no_accepted'} ? [qw(pending rejected)] : [qw(pending accepted rejected)];
	if ( $options->{'record_status'} ) {
		say q(<label for="record_status">Record status:</label>);
		say $q->popup_menu(
			-name  => 'record_status',
			id     => 'record_status',
			values => $values
		);
	}
	say $q->submit( -name => 'update', -label => 'Update', -class => 'small_submit' );
	say q(</div>);
	return;
}

sub _print_message_fieldset {
	my ( $self, $submission_id, $options ) = @_;
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	my $q          = $self->{'cgi'};
	if ( $q->param('message') ) {
		my $user = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		if ( !$user ) {
			$logger->error('Invalid user.');
			return;
		}
		my $last_message =
		  $self->{'datastore'}->run_query(
			'SELECT message FROM messages WHERE (submission_id,user_id)=(?,?) ORDER BY timestamp DESC LIMIT 1',
			[ $submission_id, $user->{'id'} ] );
		if ( scalar $q->param('message') ne ( $last_message // q() ) ) {
			eval {
				$self->{'db'}->do( 'INSERT INTO messages (submission_id,timestamp,user_id,message) VALUES (?,?,?,?)',
					undef, $submission_id, 'now', $user->{'id'}, scalar $q->param('message') );
			};
			if ($@) {
				$logger->error($@);
				$self->{'db'}->rollback;
			} else {
				$self->{'db'}->commit;
				$self->{'submissionHandler'}
				  ->append_message( $submission_id, $user->{'id'}, scalar $q->param('message') );
				$self->{'submissionHandler'}->update_submission_datestamp($submission_id);
			}
			if ( $q->param('append_and_send') ) {
				my $desc    = $self->{'system'}->{'description'} || 'BIGSdb';
				my $subject = "$desc submission comment added - $submission_id";
				my $message = $self->{'submissionHandler'}->get_text_summary( $submission_id, { messages => 1 } );
				if ( $user->{'id'} == $submission->{'submitter'} ) {

					#Message from submitter
					$self->_send_message_from_submitter( $submission_id, $subject, $message,
						scalar $q->param('message') );
				} else {

					#Message to submitter
					$self->{'submissionHandler'}->email(
						$submission_id,
						{
							recipient => $submission->{'submitter'},
							sender    => $user->{'id'},
							subject   => $subject,
							message   => $message,
							cc_sender => 1
						}
					);
				}
			}
		}
		$q->delete('message');
	}
	my $buffer;
	my $qry = q(SELECT date_trunc('second',timestamp) AS timestamp,user_id,message FROM messages )
	  . q(WHERE submission_id=? ORDER BY timestamp asc);
	my $messages =
	  $self->{'datastore'}->run_query( $qry, $submission_id, { fetch => 'all_arrayref', slice => {} } );
	my $can_delete_last_message = $self->_can_delete_last_message($submission_id);
	if (@$messages) {
	  EXIT_IF: {
			if ( $can_delete_last_message && $q->param('delete_message') ) {
				my $last_message = $messages->[-1];
				$self->_delete_message(
					$submission_id,
					substr( $last_message->{'timestamp'}, 0, 19 ),
					$last_message->{'user_id'}
				);
				$messages =
				  $self->{'datastore'}->run_query( $qry, $submission_id, { fetch => 'all_arrayref', slice => {} } );
				last EXIT_IF if !@$messages;
				$can_delete_last_message = $self->_can_delete_last_message($submission_id);
			}
			$buffer .= q(<div class="scrollable">);
			$buffer .= q(<table class="resultstable" style="margin-bottom:0"><tr>);
			$buffer .= q(<th>Delete</th>) if $can_delete_last_message;
			$buffer .= q(<th>Timestamp</th><th>User</th><th>Message</th></tr>);
			my $td     = 1;
			my $delete = DELETE;
			my $count  = 0;

			foreach my $message (@$messages) {
				$count++;
				my $user_string = $self->{'datastore'}->get_user_string( $message->{'user_id'} );
				( my $message_text = $message->{'message'} ) =~ s/\r?\n/<br \/>/gx;
				$buffer .= qq(<tr class="td$td">);
				if ($can_delete_last_message) {
					my $view = $q->param('curate') ? 'curate' : 'view';
					$buffer .=
					  $count == @$messages
					  ? qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
					  . qq(page=submit&amp;submission_id=$submission_id&amp;delete_message=1&amp;$view=1">$delete</a></td>)
					  : q(<td></td>);
				}
				$buffer .= qq(<td>$message->{'timestamp'}</td><td>$user_string</td>)
				  . qq(<td style="text-align:left">$message_text</td></tr>);
				$td = $td == 1 ? 2 : 1;
			}
			$buffer .= q(</table></div>);
		}
	}
	if ( !$options->{'no_add'} ) {
		$buffer .= $q->start_form;
		$buffer .= q(<div>);
		$buffer .= $q->textarea( -name => 'message', -id => 'message', -style => 'width:100%;height:6em' );
		$buffer .= q(</div><div style="float:right">Message: );
		$buffer .= $q->submit(
			-name  => 'append_only',
			-label => 'Append',
			-class => 'small_submit',
			-style => 'margin-right:0.5em'
		);
		if ( $submission->{'status'} ne 'started' ) {
			$buffer .= $q->submit( -name => 'append_and_send', -label => 'Send now', -class => 'small_submit' );
		}
		$buffer .= q(</div>);
		$buffer .= $q->hidden($_) foreach qw(db page alleles profiles isolates genomes assemblies locus submit view
		  curate abort submission_id no_check );
		$buffer .= $q->end_form;
	}
	if ($buffer) {
		my $max_width      = $self->{'config'}->{'page_max_width'} // PAGE_MAX_WIDTH;
		my $main_max_width = $max_width - 100;
		say q(<fieldset style="float:left"><legend>Messages</legend>);
		say qq(<div style="max-width:min(${main_max_width}px, 100vw - 80px)">);
		say $buffer;
		say q(</div></fieldset>);
	}
	return;
}

sub _send_message_from_submitter {
	my ( $self, $submission_id, $subject, $message, $summary ) = @_;
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	my $curators   = $self->{'submissionHandler'}->get_curators($submission_id);
	foreach my $curator_id (@$curators) {
		my $curator_info = $self->{'datastore'}->get_user_info($curator_id);
		if ( $curator_info->{'submission_digests'} ) {
			my $user_db = $self->{'datastore'}->get_user_db( $curator_info->{'user_db'} );
			next if !defined $user_db;
			my $curator_username =
			  $self->{'datastore'}->run_query( 'SELECT user_name FROM users WHERE id=?', $curator_id );
			my $submitter_name = $self->{'datastore'}->get_user_string( $submission->{'submitter'} );
			eval {
				$user_db->do(
					'INSERT INTO submission_digests (user_name,timestamp,dbase_description,submission_id,'
					  . 'submitter,summary) VALUES (?,?,?,?,?,?)',
					undef,
					$curator_username,
					'now',
					$self->{'system'}->{'description'},
					$submission_id,
					$submitter_name,
					"Comment added: $summary"
				);
			};
			if ($@) {
				$logger->error($@);
				$user_db->rollback;
			} else {
				$user_db->commit;
			}
		} else {
			$self->{'submissionHandler'}->email(
				$submission_id,
				{
					recipient => $curator_id,
					sender    => $submission->{'submitter'},
					subject   => $subject,
					message   => $message,
				}
			);
		}
	}
	return;
}

sub _can_delete_last_message {
	my ( $self, $submission_id ) = @_;
	my $qry = q(SELECT timestamp,user_id,message FROM messages WHERE submission_id=? ORDER BY timestamp asc);
	my $messages =
	  $self->{'datastore'}->run_query( $qry, $submission_id, { fetch => 'all_arrayref', slice => {} } );
	my $last_message = $messages->[-1];
	my $datestamp    = BIGSdb::Utils::get_datestamp();
	my $user         = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $can_delete_last_message =
		 $last_message
	  && $last_message->{'user_id'} == $user->{'id'}
	  && substr( $last_message->{'timestamp'}, 0, 10 ) eq $datestamp ? 1 : 0;
	return $can_delete_last_message;
}

sub _delete_message {
	my ( $self, $submission_id, $timestamp, $user_id ) = @_;
	eval {
		$self->{'db'}->do(
			'DELETE FROM messages WHERE (submission_id,substring(CAST(timestamp AS text) '
			  . 'from 1 for 19),user_id)=(?,?,?)',
			undef, $submission_id, $timestamp, $user_id
		);
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	my $curators = $self->{'submissionHandler'}->get_curators($submission_id);
	my %user_db_sent;
	foreach my $curator_id (@$curators) {
		my $curator_info = $self->{'datastore'}->get_user_info($curator_id);
		next if !$curator_info->{'submission_digests'};
		next if $user_db_sent{ $curator_info->{'user_db'} };
		my $user_db = $self->{'datastore'}->get_user_db( $curator_info->{'user_db'} );
		next if !defined $user_db;
		eval {
			$user_db->do(
				'DELETE FROM submission_digests WHERE (submission_id,substring(CAST(timestamp AS text) '
				  . 'from 1 for 19))=(?,?)',
				undef, $submission_id, $timestamp
			);
		};
		if ($@) {
			$logger->error($@);
			$user_db->rollback;
		} else {
			$user_db->commit;
		}
		$user_db_sent{ $curator_info->{'user_db'} } = 1;
	}
	return;
}

sub _print_archive_fieldset {
	my ( $self, $submission_id ) = @_;
	say q(<fieldset style="float:left"><legend>Archive</legend>);
	say q(<p>Archive of submission and any supporting files:</p>);
	my $tar_icon = $self->get_file_icon('TAR');
	say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit&amp;)
	  . qq(submission_id=$submission_id&amp;tar=1">Download$tar_icon</a></p>);
	say q(</fieldset>);
	return;
}

sub _print_cancel_fieldset {
	my ( $self, $submission_id ) = @_;
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	my $user_info  = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	return if !defined $user_info;
	return if $submission->{'submitter'} != $user_info->{'id'};
	return if $submission->{'status'} ne 'pending';
	my $q = $self->{'cgi'};
	say $q->start_form;
	$self->print_action_fieldset(
		{
			legend       => 'Cancel submission',
			submit_label => 'Cancel',
			no_reset     => 1,
			text         => '<p>You can cancel the submission<br />if you have made a mistake.</p>'
		}
	);
	$q->param( cancel => 1 );
	say $q->hidden($_) foreach qw( db page submission_id cancel );
	say $q->end_form;
	return;
}

sub _print_close_submission_fieldset {
	my ( $self, $submission_id ) = @_;
	return if !$self->{'all_assigned_or_rejected'};    #Set in _print_sequence_table_fieldset.
	my $q = $self->{'cgi'};
	say $q->start_form;
	$q->param( close => 1 );
	say $q->hidden($_) foreach qw( db page submission_id close );
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Close submission' } );
	say $q->end_form;
	return;
}

sub _print_reopen_submission_fieldset {
	my ( $self, $submission_id ) = @_;
	my $q = $self->{'cgi'};
	say $q->start_form;
	$q->param( reopen => 1 );
	say $q->hidden($_) foreach qw( db page submission_id reopen curate);
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Re-open submission' } );
	say $q->end_form;
	return;
}

sub _print_submission_file_table {
	my ( $self, $submission_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q     = $self->{'cgi'};
	my $files = $self->_get_submission_files($submission_id);
	return if !@$files;
	my $buffer = q(<table class="resultstable"><tr><th>Filename</th><th>Size</th>);
	$buffer .= q(<th>Delete</th>) if $options->{'delete_checkbox'};
	$buffer .= qq(</tr>\n);
	my $td = 1;
	my $i  = 0;

	foreach my $file (@$files) {
		$buffer .=
			qq(<tr class="td$td"><td><a href="/submissions/$submission_id/supporting_files/$file->{'filename'}">)
		  . qq($file->{'filename'}</a></td><td>$file->{'size'}</td>);
		if ( $options->{'delete_checkbox'} ) {
			$buffer .= q(<td>);
			$buffer .= $q->checkbox( -name => "file$i", -label => '' );
			$buffer .= q(</td>);
		}
		$i++;
		$buffer .= qq(</tr>\n);
		$td = $td == 1 ? 2 : 1;
	}
	$buffer .= q(</table>);
	return $buffer if $options->{'get_only'};
	say $buffer;
	return;
}

sub _get_submission_files {
	my ( $self, $submission_id ) = @_;
	my $dir = $self->{'submissionHandler'}->get_submission_dir($submission_id) . '/supporting_files';
	return [] if !-e $dir;
	my @files;
	opendir( my $dh, $dir ) || $logger->error("Can't open directory $dir");
	while ( my $filename = readdir $dh ) {
		next if $filename =~ /^\./x;
		push @files, { filename => $filename, size => BIGSdb::Utils::get_nice_size( -s "$dir/$filename" ) };
	}
	closedir $dh;
	return \@files;
}

sub _upload_files {
	my ( $self, $submission_id ) = @_;
	my $q         = $self->{'cgi'};
	my @filenames = $q->multi_param('file_upload');
	my $i         = 0;
	my $dir       = $self->{'submissionHandler'}->get_submission_dir($submission_id) . '/supporting_files';
	if ( !-e $dir ) {
		$self->{'submissionHandler'}->mkpath($dir);
	}
	foreach my $fh2 ( $q->upload('file_upload') ) {
		if ( $filenames[$i] =~ /([A-z0-9_\-\.'\ \(\\#)]+)/x ) {
			$filenames[$i] = $1;
		} else {
			$filenames[$i] = 'file';
		}
		my $filename = "$dir/$filenames[$i]";
		$i++;
		next if -e $filename;    #Don't reupload if already done.
		my $buffer;
		open( my $fh, '>', $filename ) || $logger->error("Could not open $filename for writing.");
		binmode $fh2;
		binmode $fh;
		read( $fh2, $buffer, $self->{'config'}->{'max_upload_size'} );
		print $fh $buffer;
		close $fh;
	}
	return;
}

sub _print_file_fieldset {
	my ( $self, $submission_id ) = @_;
	my $file_table = $self->_print_submission_file_table( $submission_id, { get_only => 1 } );
	if ($file_table) {
		say q(<fieldset style="float:left"><legend>Supporting files</legend>);
		say $file_table;
		say q(</fieldset>);
	}
	return;
}

sub _print_summary {
	my ( $self, $submission_id ) = @_;
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	say q(<fieldset style="float:left"><legend>Summary</legend>);
	say qq(<dl class="data"><dt>type</dt><dd>$submission->{'type'}</dd>);
	my $user_string =
	  $self->{'datastore'}->get_user_string( $submission->{'submitter'}, { email => 1, affiliation => 1 } );
	say qq(<dt>submitter</dt><dd>$user_string</dd>);
	say qq(<dt>datestamp</dt><dd>$submission->{'datestamp'}</dd>);
	say qq(<dt>status</dt><dd>$submission->{'status'}</dd>);
	my %outcome = (
		good  => 'accepted - data uploaded',
		bad   => 'rejected - data not uploaded',
		mixed => 'mixed - submission partially accepted'
	);
	say qq(<dt>outcome</dt><dd>$outcome{$submission->{'outcome'}}</dd>) if $submission->{'outcome'};

	if ( defined $submission->{'curator'} ) {
		my $curator_string =
		  $self->{'datastore'}->get_user_string( $submission->{'curator'}, { email => 1, affiliation => 1 } );
		say qq(<dt>curator</dt><dd>$curator_string</dd>);
	}
	if ( $submission->{'type'} eq 'alleles' ) {
		my $allele_submission = $self->{'submissionHandler'}->get_allele_submission($submission_id);
		my $locus             = $self->clean_locus( $allele_submission->{'locus'} ) // $allele_submission->{'locus'};
		say qq(<dt>locus</dt><dd>$locus</dd>);
		my $allele_count   = @{ $allele_submission->{'seqs'} };
		my $fasta_icon     = $self->get_file_icon('FAS');
		my $submission_dir = $self->{'submissionHandler'}->get_submission_dir($submission_id);
		if ( !-e "$submission_dir/sequences.fas" ) {
			$self->{'submissionHandler'}->write_submission_allele_FASTA($submission_id);
			$logger->error("No submission FASTA file for allele submission $submission_id.");
		}
		say q(<dt>sequences</dt>)
		  . qq(<dd><a href="/submissions/$submission_id/sequences.fas">$allele_count$fasta_icon</a></dd>);
		say qq(<dt>technology</dt><dd>$allele_submission->{'technology'}</dd>);
		say qq(<dt>read length</dt><dd>$allele_submission->{'read_length'}</dd>)
		  if $allele_submission->{'read_length'};
		say qq(<dt>coverage</dt><dd>$allele_submission->{'coverage'}</dd>) if $allele_submission->{'coverage'};
		say qq(<dt>assembly</dt><dd>$allele_submission->{'assembly'}</dd>) if $allele_submission->{'assembly'};
		say qq(<dt>assembly software</dt><dd>$allele_submission->{'software'}</dd>)
		  if $allele_submission->{'software'};
	}
	say q(</dl></fieldset>);
	return;
}

#Check submission exists and curator has appropriate permissions.
sub _is_submission_valid {
	my ( $self, $submission_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	if ( !$submission_id ) {
		$self->print_bad_status( { message => q(No submission id passed.) } ) if !$options->{'no_message'};
		return;
	}
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	if ( !$submission ) {
		$self->print_bad_status( { message => qq(Submission '$submission_id' does not exist.) } )
		  if !$options->{'no_message'};
		return;
	}
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	if ( $options->{'curate'} ) {
		if ( !$user_info || ( $user_info->{'status'} ne 'admin' && $user_info->{'status'} ne 'curator' ) ) {
			$self->print_bad_status(
				{
					message => q(Your account does not have the required permissions to curate this submission.)
				}
			) if !$options->{'no_message'};
			return;
		}
		if ( $submission->{'type'} eq 'alleles' ) {
			my $allele_submission = $self->{'submissionHandler'}->get_allele_submission( $submission->{'id'} );
			my $curator_allowed =
			  $self->{'datastore'}
			  ->is_allowed_to_modify_locus_sequences( $allele_submission->{'locus'}, $user_info->{'id'} );
			if ( !( $self->is_admin || $curator_allowed ) ) {
				$self->print_bad_status(
					{
						message => q(Your account does not have the required )
						  . qq(permissions to curate new $allele_submission->{'locus'} sequences.)
					}
				) if !$options->{'no_message'};
				return;
			}
		}
	}
	if ( $options->{'user_owns'} ) {
		return if $submission->{'submitter'} != $user_info->{'id'};
	}
	return 1;
}

sub set_level2_breadcrumbs {
	my ( $self, $page ) = @_;
	$self->{'breadcrumbs'} = [
		{
			label => $self->{'system'}->{'webroot_label'} // 'Organism',
			href  => $self->{'system'}->{'webroot'}
		},
		{
			label => $self->{'system'}->{'formatted_description'} // $self->{'system'}->{'description'},
			href  => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}"
		},
		{
			label => 'Submissions',
			href  => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit"
		},
		{
			label => $page
		}
	];
	return;
}

sub _curate_submission {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $submission_id ) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Curate submission</h1>);
	return if !$self->_is_submission_valid( $submission_id, { curate => 1 } );
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	my $curate     = 1;
	if ( $submission->{'status'} eq 'closed' ) {
		$self->print_bad_status( { message => q(This submission is closed and cannot now be modified.) } );
		$curate = 0;
	}
	say q(<div class="box" id="resultstable">);
	say qq(<h2 style="overflow-x:auto;overflow-y:hidden">Submission: $submission_id</h2>);
	my %isolate_type = map { $_ => 1 } qw(isolates genomes assemblies);
	if ( $isolate_type{ $submission->{'type'} } && $q->param('curate') && $q->param('update') ) {
		$self->_update_isolate_submission_isolate_status($submission_id);
		$submission = $self->{'submissionHandler'}->get_submission($submission_id);
	}
	$self->_print_summary($submission_id);
	say q(<div style="clear:both"></div>);
	say q(<div class="flex_container" style="justify-content:left">);
	$self->_print_sequence_table_fieldset( $submission_id, { curate => $curate } );
	$self->_print_profile_table_fieldset( $submission_id, { curate => $curate } );
	$self->_print_isolate_table_fieldset( $submission_id, { curate => $curate } );
	$self->_print_assembly_table_fieldset( $submission_id, { curate => $curate } );
	$self->_print_finalised_assembly_warning( $submission_id, { curate => $curate } );
	$self->_print_file_fieldset($submission_id);
	$self->_print_message_fieldset($submission_id);
	$self->_print_archive_fieldset($submission_id);

	if ($curate) {
		$self->_print_close_submission_fieldset($submission_id);
	} else {
		$self->_print_reopen_submission_fieldset($submission_id);
	}
	say q(<div style="clear:both"></div>);
	my $page = $self->{'curate'} ? 'index' : 'submit';
	say q(</div></div>);
	return;
}

sub _view_submission {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $submission_id ) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Submission summary</h1>);
	return if !$self->_is_submission_valid($submission_id);
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	say q(<div class="box" id="resultstable">);
	say qq(<h2 style="overflow-x:auto">Submission: $submission_id</h2>);
	$self->_print_summary($submission_id);
	say q(<div style="clear:both"></div>);
	say q(<div class="flex_container" style="justify-content:left">);
	$self->_print_sequence_table_fieldset($submission_id);
	$self->_print_profile_table_fieldset($submission_id);
	$self->_print_file_upload_fieldset( $submission_id, { no_add => $submission->{'status'} eq 'closed' ? 1 : 0 } )
	  if $submission->{'type'} ne 'isolates';
	$self->_print_assembly_table_fieldset( $submission_id, { download_link => 1 } );
	$self->_print_finalised_assembly_warning( $submission_id, { view => 1 } );
	$self->_print_isolate_table_fieldset($submission_id);
	$self->_print_message_fieldset( $submission_id, { no_add => $submission->{'status'} eq 'closed' ? 1 : 0 } );
	$self->_print_archive_fieldset($submission_id);
	$self->_print_cancel_fieldset($submission_id);

	if ( $submission->{'status'} eq 'started' ) {
		say $q->start_form;
		$self->print_action_fieldset( { no_reset => 1, submit_label => 'Finalize submission!' } );
		say $q->hidden( finalize => 1 );
		say $q->hidden($_) foreach qw(db page locus submit finalize submission_id);
		say $q->end_form;
	}
	say q(</div></div>);
	return;
}

sub _close_submission {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $submission_id ) = @_;
	return if !$self->_is_submission_valid( $submission_id, { curate => 1, no_message => 1 } );
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	return if !$submission || $submission->{'status'} eq 'closed';    #Prevent refresh from re-sending E-mail
	my $curator_id = $self->get_curator_id;
	eval {
		$self->{'db'}->do( 'UPDATE submissions SET (status,datestamp,curator)=(?,?,?) WHERE id=?',
			undef, 'closed', 'now', $curator_id, $submission_id );
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	$submission = $self->{'submissionHandler'}->get_submission($submission_id);
	my $curator_info = $self->{'datastore'}->get_user_info($curator_id);
	$self->{'submissionHandler'}->remove_submission_from_digest($submission_id);
	if ( $submission->{'email'} ) {
		my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
		$self->{'submissionHandler'}->email(
			$submission_id,
			{
				recipient => $submission->{'submitter'},
				sender    => $curator_id,
				subject   => "$desc submission closed - $submission_id",
				message   => $self->{'submissionHandler'}
				  ->get_text_summary( $submission_id, { messages => 1, correspondence_first => 1 } ),
				cc_sender => $curator_info->{'submission_email_cc'}
			}
		);
	}
	return;
}

sub _remove_submission {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $submission_id ) = @_;
	return if !$self->_is_submission_valid( $submission_id, { no_message => 1, user_owns => 1 } );
	$self->{'submissionHandler'}->delete_submission($submission_id);
	return;
}

sub _cancel_submission {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $submission_id ) = @_;
	return if !$self->_is_submission_valid( $submission_id, { no_message => 1, user_owns => 1 } );
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	return if $submission->{'status'} ne 'pending';
	my $curators = $self->{'submissionHandler'}->get_curators($submission_id);
	my $desc     = $self->{'system'}->{'description'} || 'BIGSdb';
	my $subject  = "CANCELLED $submission->{'type'} submission ($desc) - $submission_id";
	my $message  = "This submission has been CANCELLED by the submitter.\n\n";
	$message .= $self->{'submissionHandler'}->get_text_summary( $submission_id, { messages => 1 } );
	$logger->info("$self->{'instance'}: Submission cancelled.");
	$self->{'submissionHandler'}->remove_submission_from_digest($submission_id);

	foreach my $curator_id (@$curators) {
		my $user_info = $self->{'datastore'}->get_user_info($curator_id);
		next if $user_info->{'submission_digests'};
		next if !$self->{'submissionHandler'}->can_email_curator($curator_id);
		$self->{'submissionHandler'}->email(
			$submission_id,
			{
				recipient => $curator_id,
				sender    => $submission->{'submitter'},
				subject   => $subject,
				message   => $message,
			}
		);
		$self->{'submissionHandler'}->write_flood_protection_file($curator_id);
	}
	$self->{'submissionHandler'}->delete_submission($submission_id);
	return;
}

sub _reopen_submission {
	my ( $self, $submission_id ) = @_;
	return if !$self->_is_submission_valid( $submission_id, { no_message => 1, curate => 1 } );
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	return if $submission->{'status'} ne 'closed';
	my $curator_id = $self->get_curator_id;
	my $message    = 'Submission re-opened.';
	eval {
		$self->{'db'}->do( 'UPDATE submissions SET (status,outcome,datestamp,curator)=(?,?,?,?) WHERE id=?',
			undef, 'pending', undef, 'now', $curator_id, $submission_id );
		$self->{'submissionHandler'}->update_submission_datestamp($submission_id);
		$self->{'db'}->do( 'INSERT INTO messages (submission_id,timestamp,user_id,message) VALUES (?,?,?,?)',
			undef, $submission_id, 'now', $curator_id, $message );
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		$self->{'submissionHandler'}->append_message( $submission_id, $curator_id, $message );
	}
	return;
}

sub _get_fasta_string {
	my ( $self, $seqs ) = @_;
	my $buffer;
	foreach my $seq (@$seqs) {
		$buffer .= ">$seq->{'seq_id'}\n";
		$buffer .= "$seq->{'sequence'}\n";
	}
	return $buffer;
}

sub _tar_submission {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $submission_id ) = @_;
	return if !defined $submission_id || $submission_id !~ /BIGSdb_\d+/x;
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	return if !$submission;
	my $submission_dir = $self->{'submissionHandler'}->get_submission_dir($submission_id);
	$submission_dir =
	  $submission_dir =~ /^($self->{'config'}->{'submission_dir'}\/BIGSdb[^\/]+)$/x ? $1 : undef;    #Untaint
	binmode STDOUT;
	local $" = ' ';
	my $command = "cd $submission_dir && tar -cf - *";

	#The output of system calls will not be sent to the browser when running under mod_perl.
	#This is also the case when running under Plack::App::CGIBin.
	#We can run commands using backticks to circumvent this issue.
	#https://github.com/kjolley/BIGSdb/issues/748
	#https://github.com/kjolley/BIGSdb/issues/751
	my $tar = `$command`;
	if ( length $tar ) {
		print $tar;
	} else {
		$logger->error('Cannot create tar output.');
	}
	return;
}

sub _update_allele_prefs {
	my ($self) = @_;
	my $guid = $self->get_guid;
	return if !$guid;
	my $q = $self->{'cgi'};
	foreach my $param (qw(technology read_length coverage assembly software)) {
		my $field = "submit_allele_$param";
		my $value = $q->param($param);
		next if !$value;
		$self->{'prefstore'}->set_general( $guid, $self->{'system'}->{'db'}, $field, $value );
	}
	return;
}

sub _get_scheme_loci {
	my ( $self, $scheme_ids ) = @_;
	my @loci;
	my %locus_selected;
	my $set_id = $self->get_set_id;
	foreach (@$scheme_ids) {
		my $scheme_loci =
			$_
		  ? $self->{'datastore'}->get_scheme_loci($_)
		  : $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
		foreach my $locus (@$scheme_loci) {
			if ( !$locus_selected{$locus} ) {
				push @loci, $locus;
				$locus_selected{$locus} = 1;
			}
		}
	}
	return \@loci;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub get_title {
	my ($self) = @_;
	return 'Submissions';
}

sub print_panel_buttons {
	my ($self) = @_;
	$self->print_related_dbases_button;
	return;
}
1;
