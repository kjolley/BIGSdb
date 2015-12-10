#Written by Keith Jolley
#Copyright (c) 2015, University of Oxford
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
package BIGSdb::SubmitPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::TreeViewPage BIGSdb::CurateProfileAddPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Utils;
use BIGSdb::BIGSException;
use BIGSdb::Constants qw(MAX_UPLOAD_SIZE SEQ_METHODS :submissions :interface);
use List::MoreUtils qw(none);
use POSIX;

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
	my ($self) = @_;
	my $tree_js = $self->get_tree_javascript( { checkboxes => 1, check_schemes => 1 } );
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
			\$("span#show_closed_text").css('display', 'block');
			\$("span#hide_closed_text").css('display', 'none');
		} else {
			\$("span#show_closed_text").css('display', 'none');
			\$("span#hide_closed_text").css('display', 'block');
		}
		\$( "#closed" ).toggle( 'blind', {} , 500 );
		return false;
	});
});

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
	$self->{$_} = 1 foreach qw (jQuery jQuery.jstree noCache);
	return;
}

sub print_content {
	my ($self) = @_;
	if ( ( $self->{'system'}->{'submissions'} // '' ) ne 'yes' || !$self->{'config'}->{'submission_dir'} ) {
		say q(<h1>Manage submissions</h1>);
		say q(<div class="box" id="statusbad"><p>The submission system is not enabled.</p></div>);
		return;
	}
	my $q = $self->{'cgi'};
	$self->choose_set;
	my $submission_id = $q->param('submission_id');
	if ($submission_id) {
		my %return_after = map { $_ => 1 } qw (tar view curate);
		foreach my $action (qw (abort finalize close remove tar view curate)) {
			if ( $q->param($action) ) {
				my $method = "_$action\_submission";
				$self->$method($submission_id);
				return if $return_after{$action};
				last;
			}
		}
	}
	say q(<h1>Manage submissions</h1>);
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	if ( !$user_info ) {
		say q(<div class="box" id="statusbad"><p>You are not a recognized user.  Submissions are disabled.</p></div>);
		return;
	}
	foreach my $type (qw (alleles profiles isolates genomes)) {
		if ( $q->param($type) ) {
			my $method = "_handle_$type";
			$self->$method;
			return;
		}
	}
	$self->_delete_old_closed_submissions;
	say q(<div class="box resultstable"><div class="scrollable">);
	if ( !$self->_print_started_submissions ) {    #Returns true if submissions in process
		$self->_print_new_submission_links;
	}
	$self->_print_pending_submissions;
	$self->print_submissions_for_curation;
	$self->_print_closed_submissions;
	say qq(<p style="margin-top:1em"><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">)
	  . q(Return to index page</a></p>);
	my $closed_buffer =
	  $self->print_submissions_for_curation( { status => 'closed', show_outcome => 1, get_only => 1 } );
	if ($closed_buffer) {
		my $class = RESET_BUTTON_CLASS;
		say qq(<a id="show_closed" class="$class ui-button-text-only" >)
		  . q(<span id="show_closed_text" class="ui-button-text" )
		  . q(style="display:block">Show closed submissions</span>)
		  . q(<span id="hide_closed_text" class="ui-button-text" )
		  . q(style="display:none">Hide closed submissions</span></a>);
	}
	say q(</div></div>);
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

sub _handle_alleles {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $self->{'system'}->{'dbtype'} ne 'sequences' ) {
		say q(<div class="box" id="statusbad"><p>You cannot submit new allele sequences for definition in an )
		  . q(isolate database.<p></div>);
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
		say q(<div class="box" id="statusbad"><p>You cannot submit new profiles for definition in an )
		  . q(isolate database.<p></div>);
		return;
	}
	$self->_submit_profiles;
	return;
}

sub _handle_isolates {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		say q(<div class="box" id="statusbad"><p>You cannot submit new isolates to a )
		  . q(sequence definition database.<p></div>);
		return;
	}
	$self->_submit_isolates;
	return;
}

sub _handle_genomes {     ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		say q(<div class="box" id="statusbad"><p>You cannot submit new genomes to a )
		  . q(sequence definition database.<p></div>);
		return;
	}
	$self->_submit_isolates( { genomes => 1 } );
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

		#Don't allow profile submissions by default - theycan be extracted from those records.
		#This ensures that every new profile has accompanying isolate data.
		if ( ( $self->{'system'}->{'profile_submissions'} // '' ) eq 'yes' ) {
			my $set_id = $self->get_set_id;
			my $schemes = $self->{'datastore'}->get_scheme_list( { with_pk => 1, set_id => $set_id } );
			foreach my $scheme (@$schemes) {
				say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit)
				  . qq(&amp;profiles=1&amp;scheme_id=$scheme->{'id'}">$scheme->{'description'} profiles</a></li>);
			}
		}
	} else {    #Isolate database
		say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit&amp;)
		  . q(isolates=1">isolates</a></li>)
		  . qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit&amp;)
		  . q(genomes=1">genomes</a> (isolate records with associated assembly files)</li>);
	}
	say q(</ul>);
	return;
}

sub _delete_old_closed_submissions {
	my ($self) = @_;
	my $days = $self->get_submission_days;
	my $submissions =
	  $self->{'datastore'}
	  ->run_query( qq(SELECT id FROM submissions WHERE status=? AND datestamp<now()-interval '$days days'),
		'closed', { fetch => 'col_arrayref' } );
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
		$qry     = 'SELECT * FROM submissions WHERE status=? ORDER BY id';
		$get_all = 1;
		push @args, $status;
	} else {
		$qry     = 'SELECT * FROM submissions WHERE (submitter,status)=(?,?) ORDER BY id';
		$get_all = 0;
		push @args, ( $user_info->{'id'}, $status );
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
					say qq(<dt>Scheme</dt><dd>$scheme_info->{'description'}</dd>);
					my $profile_count = @{ $profile_submission->{'profiles'} };
					say qq(<dt>Profiles</dt><dd>$profile_count</dd>);
				}
			}
			say qq(<dt>Action</dt><dd><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=submit&amp;$submission->{'type'}=1">Abort/Continue</a>);
			say q(</dl>);
		}
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
			my $details = '';
			if ( $submission->{'type'} eq 'alleles' ) {
				my $allele_submission = $self->{'submissionHandler'}->get_allele_submission( $submission->{'id'} );
				my $allele_count = @{ $allele_submission->{'seqs'} };
				my $plural = $allele_count == 1 ? '' : 's';
				next if $set_id && !$self->{'datastore'}->is_locus_in_set( $allele_submission->{'locus'}, $set_id );
				my $clean_locus = $self->clean_locus( $allele_submission->{'locus'} );
				$details = "$allele_count $clean_locus sequence$plural";
			} elsif ( $submission->{'type'} eq 'profiles' ) {
				my $profile_submission = $self->{'submissionHandler'}->get_profile_submission( $submission->{'id'} );
				my $profile_count      = @{ $profile_submission->{'profiles'} };
				my $plural             = $profile_count == 1 ? '' : 's';
				next
				  if $set_id
				  && !$self->{'datastore'}->is_scheme_in_set( $profile_submission->{'scheme_id'}, $set_id );
				my $scheme_info =
				  $self->{'datastore'}
				  ->get_scheme_info( $profile_submission->{'scheme_id'}, { get_pk => 1, set_id => $set_id } );
				$details = "$profile_count $scheme_info->{'description'} profile$plural";
			} elsif ( $submission->{'type'} eq 'isolates' || $submission->{'type'} eq 'genomes' ) {
				my $isolate_submission = $self->{'submissionHandler'}->get_isolate_submission( $submission->{'id'} );
				my $isolate_count      = @{ $isolate_submission->{'isolates'} };
				my $plural             = $isolate_count == 1 ? '' : 's';
				$details = "$isolate_count isolate$plural";
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
				  . q(<span class="fa fa-lg fa-remove"></span></a></td>);
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
	}
	return $buffer if $options->{'get_only'};
	say $buffer if $buffer;
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
		my $locus = $self->clean_locus( $allele_submission->{'locus'} ) // $allele_submission->{'locus'};
		$buffer .=
		    qq(<tr class="td$td"><td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=submit&amp;submission_id=$submission->{'id'}&amp;curate=1">$submission->{'id'}</a></td>)
		  . qq(<td>$submission->{'date_submitted'}</td><td>$submission->{'datestamp'}</td><td>$submitter_string</td>)
		  . qq(<td>$locus</td>);
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
		}
		$return_buffer .= q(<table class="resultstable"><tr><th>Submission id</th><th>Submitted</th><th>Updated</th>)
		  . q(<th>Submitter</th><th>Locus</th><th>Sequences</th>);
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
		my $profile_submission = $self->{'submissionHandler'}->get_profile_submission( $submission->{'id'} );
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
		  . qq(<td>$scheme_info->{'description'}</td>);
		my $seq_count = @{ $profile_submission->{'profiles'} };
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
			$return_buffer .= q(<h3>Profile submissions</h3>);
		} else {
			$return_buffer .= qq(<h2>New allelic profile submissions waiting for curation</h2>\n);
			$return_buffer .= qq(<p>Your account is authorized to handle the following submissions:<p>\n);
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
		next if $submission->{'type'} eq 'genomes' && !$self->can_modify_table('sequence_bin');
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
	say qq(<div class="box" id="statuswarn"><h2>Warning$plural:</h2><p>@info</p><p>Warnings do not prevent submission )
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
	return if !$submission;
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	eval {
		if ( $submission->{'type'} eq 'alleles' )
		{
			$self->{'db'}->do(
				'UPDATE allele_submissions SET (technology,read_length,coverage,assembly,software)=(?,?,?,?,?) '
				  . 'WHERE submission_id=? AND submission_id IN (SELECT id FROM submissions WHERE submitter=?)',
				undef,
				$q->param('technology'),
				$q->param('read_length'),
				$q->param('coverage'),
				$q->param('assembly'),
				$q->param('software'),
				$submission_id,
				$user_info->{'id'}
			);
		}
		$self->{'db'}->do(
			'UPDATE submissions SET (status,datestamp,email)=(?,?,?) WHERE (id,submitter)=(?,?)',
			undef, 'pending', 'now', $q->param('email') // undef,
			$submission_id, $user_info->{'id'}
		);
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
			say qq(<div class="box" id="statusbad"><h2>Error$plural:</h2><p>@err</p></div>);
		} else {
			if ( $ret->{'info'} ) {
				$self->_print_allele_warnings( $ret->{'info'} );
			}
			$self->_presubmit_alleles( undef, $ret->{'seqs'} );
			return;
		}
	}
	say q(<div class="box" id="queryform"><div class="scrollable">);
	say q(<h2>Submit new alleles</h2>);
	say q(<p>You need to make a separate submission for each locus for which you have new alleles - this is because )
	  . q(different loci may have different curators.  You can submit any number of new sequences for a single locus )
	  . q(as one submission. Sequences should be trimmed to the correct start/end sites for the selected locus.</p>);
	my $set_id = $self->get_set_id;
	my ( $loci, $labels );
	say $q->start_form;
	my $schemes =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id FROM schemes ORDER BY display_order,description', undef, { fetch => 'col_arrayref' } );

	if ( @$schemes > 1 ) {
		say q(<fieldset id="scheme_fieldset" style="float:left;display:none"><legend>Filter loci by scheme</legend>);
		say q(<div id="tree" class="scheme_tree" style="float:left;max-height:initial">);
		say $self->get_tree( undef, { no_link_out => 1, select_schemes => 1 } );
		say q(</div>);
		say $q->submit( -name => 'filter', -id => 'filter', -label => 'Filter', -class => 'submit' );
		say q(</fieldset>);
		my @selected_schemes;
		foreach ( @$schemes, 0 ) {
			push @selected_schemes, $_ if $q->param("s_$_");
		}
		my $scheme_loci = @selected_schemes ? $self->_get_scheme_loci( \@selected_schemes ) : undef;
		( $loci, $labels ) =
		  $self->{'datastore'}->get_locus_list( { only_include => $scheme_loci, set_id => $set_id } );
	} else {
		( $loci, $labels ) = $self->{'datastore'}->get_locus_list( { set_id => $set_id } );
	}
	say q(<fieldset style="float:left"><legend>Select locus</legend>);
	say $q->popup_menu(
		-name     => 'locus',
		-id       => 'locus',
		-values   => $loci,
		-labels   => $labels,
		-size     => 9,
		-required => 'required'
	);
	say q(</fieldset>);
	$self->_print_sequence_details_fieldset($submission_id);
	say q(<fieldset style="float:left"><legend>FASTA or single sequence</legend>);
	say $q->textarea( -name => 'fasta', -cols => 30, -rows => 5, -id => 'fasta', -required => 'required' );
	say q(</fieldset>);
	say $q->hidden($_) foreach qw(db page alleles);
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->end_form;
	say q(</div></div>);
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
		$ret = $self->{'submissionHandler'}->check_new_profiles( $scheme_id, $set_id, \$q->param('data') );
		if ( $ret->{'err'} ) {
			my $err = $ret->{'err'};
			local $" = '<br />';
			my $plural = @$err == 1 ? '' : 's';
			say qq(<div class="box" id="statusbad"><h2>Error$plural:</h2><p>@$err</p></div>);
		} elsif ( !@{ $ret->{'profiles'} } ) {
			say q(<div class="box" id="statusbad"><h2>Error:</h2><p>No profiles in upload.</p></div>);
		} else {
			$self->_presubmit_profiles( undef, $ret->{'profiles'} );
			return;
		}
	}
	my $scheme_id = $q->param('scheme_id');
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		say q(<div class="box" id="statusbad"><p>Scheme id must be an integer</p></div>);
		return;
	}
	my $set_id = $self->get_set_id;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1, set_id => $set_id } );
	if ( !$scheme_info || !$scheme_info->{'primary_key'} ) {
		say q(<div class="box" id="statusbad"><p>Invalid scheme passed.</p></div>);
		return;
	}
	say q(<div class="box" id="queryform"><div class="scrollable">);
	say qq(<h2>Submit new $scheme_info->{'description'} profiles</h2>);
	say q(<p>Paste in your profiles for assignment using the template available below.</p>);
	say qq(<ul><li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableHeader&amp;)
	  . qq(table=profiles&amp;scheme_id=$scheme_id&amp;no_fields=1&amp;id_field=1">Download tab-delimited )
	  . q(header for your spreadsheet</a> - use 'Paste Special <span class="fa fa-arrow-circle-right"></span> Text' )
	  . q(to paste the data.</li>);
	say qq[<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=excelTemplate&amp;]
	  . qq[table=profiles&amp;scheme_id=$scheme_id&amp;no_fields=1&amp;id_field=1">Download submission template ]
	  . q[(xlsx format)</a></li></ul>];
	say $q->start_form;
	say q[<fieldset style="float:left"><legend>Please paste in tab-delimited text <b>(include a field header line)</b>]
	  . q(</legend>);
	say $q->textarea( -name => 'data', -rows => 20, -columns => 80, -required => 'required' );
	say q(</fieldset>);
	say $q->hidden($_) foreach qw(db page profiles scheme_id);
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->end_form;
	say q(</div></div>);
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
		my $ret = $self->{'submissionHandler'}->check_new_isolates( $set_id, \$q->param('data'), $options );
		if ( $ret->{'err'} ) {
			my $err = $ret->{'err'};
			local $" = '<br />';
			my $plural = @$err == 1 ? '' : 's';
			say qq(<div class="box" id="statusbad"><h2>Error$plural:</h2><p>@$err</p></div>);
		} else {
			$self->_presubmit_isolates(
				{ isolates => $ret->{'isolates'}, positions => $ret->{'positions'}, options => $options } );
			return;
		}
	}
	my $set_id = $self->get_set_id;
	my $set_clause = $set_id ? qq(&amp;set_id=$set_id) : q();
	say q(<div class="box" id="queryform"><div class="scrollable">);
	say q(<h2>Submit new isolates);
	say q( with associated genome assemblies) if $options->{'genomes'};
	say q(</h2>);
	say q(<p>Paste in your isolates for addition to the database using the template available below.</p>);
	say q(<ul><li>Enter aliases (alternative names) for your isolates as a semi-colon (;) separated list.</li>);
	say q(<li>Enter references for your isolates as a semi-colon (;) separated list of PubMed ids.</li>);
	say q(<li>You can also upload additional allele fields along with the other isolate data - simply create a )
	  . q(new column with the locus name.</li>);

	if ( $options->{'genomes'} ) {
		say q(<li>Enter the name of the assembly contig FASTA file in the assembly_filename field and upload )
		  . q(this file as supporting data.</li>);
	}
	say q(</ul>);
	my $contig_file_clause = $options->{'genomes'} ? '&amp;addCols=assembly_filename,sequence_method' : q();
	say qq(<ul><li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableHeader&amp;)
	  . qq(table=isolates$set_clause$contig_file_clause">Download tab-delimited )
	  . q(header for your spreadsheet</a> - use 'Paste Special <span class="fa fa-arrow-circle-right"></span> Text' )
	  . q(to paste the data.</li>);
	say qq[<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=excelTemplate&amp;]
	  . qq[table=isolates$set_clause$contig_file_clause">Download submission template ]
	  . q[(xlsx format)</a></li></ul>];
	say $q->start_form;
	say q[<fieldset style="float:left"><legend>Please paste in tab-delimited text <b>(include a field header line)</b>]
	  . q(</legend>);
	say $q->textarea( -name => 'data', -rows => 20, -columns => 80, -required => 'required' );
	say q(</fieldset>);
	say $q->hidden($_) foreach qw(db page isolates genomes);
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub _print_sequence_details_fieldset {
	my ( $self, $submission_id ) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left"><legend>Sequence details</legend>);
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
	my $plural = @$profiles == 1 ? '' : 's';
	say qq(<p>You are submitting the following $scheme_info->{'description'} profile$plural: )
	  . qq(<a href="/submissions/$submission_id/profiles.txt">Download$csv_icon</a></p>)
	  if ( $options->{'download_link'} );
	say $q->start_form;
	my $status = $self->_print_profile_table( $submission_id, $options );
	$self->_print_update_button if $options->{'curate'} && !$status->{'all_assigned'};
	say $q->hidden($_) foreach qw(db page submission_id curate);
	say $q->end_form;
	local $" = ',';
	my $pending_profiles_string = "@{$status->{'pending_profiles'}}";

	if ( $options->{'curate'} && !$status->{'all_assigned_or_rejected'} ) {
		say $q->start_form( -action => $self->{'system'}->{'curate_script'} );
		say $q->submit( -name => 'Batch curate', -class => BUTTON_CLASS );
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

	if ( $q->param('curate') && $q->param('update') ) {
		$self->_update_isolate_submission_isolate_status($submission_id);
		$submission = $self->{'submissionHandler'}->get_submission($submission_id);
	}
	say q(<fieldset style="float:left"><legend>Isolates</legend>);
	my $csv_icon = $self->get_file_icon('CSV');
	my $plural = @$isolates == 1 ? '' : 's';
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
	local $" = ',';

	if ( $options->{'curate'} && !$submission->{'outcome'} ) {
		say $q->start_form( -action => $self->{'system'}->{'curate_script'} );
		say $q->submit( -name => 'Batch curate', -class => BUTTON_CLASS );
		my $page = $q->param('page');
		$q->param( page   => 'batchAdd' );
		$q->param( table  => 'isolates' );
		$q->param( submit => 1 );
		say $q->hidden($_) foreach qw( db page submission_id table submit);
		say $q->end_form;

		#Restore value
		$q->param( page => $page );
	}
	say q(</fieldset>);
	$self->{'all_assigned_or_rejected'} = $submission->{'outcome'} ? 1 : 0;
	return;
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
		return { err => ['Locus $locus is not recognized.'] };
	}
	if ( $q->param('fasta') ) {
		my $fasta_string = $q->param('fasta');
		$fasta_string =~ s/^\s*//x;
		$fasta_string =~ s/\n\s*/\n/xg;
		$fasta_string = ">seq\n$fasta_string" if $fasta_string !~ /^\s*>/x;
		return $self->{'submissionHandler'}->check_new_alleles_fasta( $locus, \$fasta_string );
	}
	return;
}

sub _start_submission {
	my ( $self, $type ) = @_;
	$logger->logdie("Invalid submission type '$type'") if none { $type eq $_ } qw (alleles profiles isolates genomes);
	my $submission_id = 'BIGSdb_' . strftime( '%Y%m%d%H%M%S', localtime ) . "_$$\_" . int( rand(99999) );
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	eval {
		$self->{'db'}
		  ->do( 'INSERT INTO submissions (id,type,submitter,date_submitted,datestamp,status) VALUES (?,?,?,?,?,?)',
			undef, $submission_id, $type, $user_info->{'id'}, 'now', 'now', 'started' );
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
			$q->param('technology'),
			$q->param('read_length'),
			$q->param('coverage'),
			$q->param('assembly'),
			$q->param('software'),
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
			eval { $insert_sql->execute( $submission_id, $index, $seq->{'seq_id'}, $seq->{'sequence'}, 'pending' ) };
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
		foreach my $field ( keys %$positions )
		{
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

sub _print_abort_form {
	my ( $self, $submission_id ) = @_;
	my $q = $self->{'cgi'};
	say q(<div style="float:left">);
	say q(<span class="warning_icon fa fa-exclamation-triangle fa-4x pull-left"></span>);
	say q(</div>);
	say $q->start_form;
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Abort submission!' } );
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
		}
	}
	say q(<fieldset style="float:left"><legend>Supporting files</legend>);
	my $nice_file_size = BIGSdb::Utils::get_nice_size(MAX_UPLOAD_SIZE);
	if ( $options->{'genomes'} ) {
		say q(<p>Please upload contig assemblies with the filenames as specified in the assembly_filename field. );
	} else {
		say q(<p>Please upload any supporting files required for curation.  Ensure that these are named unambiguously )
		  . q(or add an explanatory note so that they can be linked to the appropriate submission item. );
	}
	say qq(Individual filesize is limited to $nice_file_size. You can upload up to $nice_file_size in one go, )
	  . q(although you can upload multiple times so that the total size of the submission can be larger.</p>);
	say $q->start_form;
	print $q->filefield( -name => 'file_upload', -id => 'file_upload', -multiple );
	say $q->submit( -name => 'Upload files', -class => BUTTON_CLASS );
	$q->param( no_check => 1 );
	say $q->hidden($_) foreach qw(db page alleles profiles isolates genomes locus submit submission_id no_check view);
	say $q->end_form;
	my $files = $self->_get_submission_files($submission_id);

	if (@$files) {
		say $q->start_form;
		$self->_print_submission_file_table( $submission_id, { delete_checkbox => 1 } );
		$q->param( delete => 1 );
		say $q->hidden($_)
		  foreach qw(db page alleles profiles isolates genomes locus submission_id delete no_check view);
		say $q->submit( -label => 'Delete selected files', -class => BUTTON_CLASS );
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
	say q(<div class="box" id="resultstable"><div class="scrollable">);
	$self->_print_abort_form($submission_id);
	say qq(<h2>Submission: $submission_id</h2>);
	$options->{'download_link'} = 1;
	$self->_print_file_upload_fieldset( $submission_id, $options );
	$self->_print_isolate_table_fieldset( $submission_id, $options );
	$self->_print_message_fieldset($submission_id);
	say $q->start_form;
	$self->_print_email_fieldset($submission_id);
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Finalize submission!' } )
	  if !$self->{'contigs_missing'};
	$q->param( finalize      => 1 );
	$q->param( submission_id => $submission_id );
	say $q->hidden($_) foreach qw(db page submit finalize submission_id);
	say $q->end_form;
	say q(</div></div>);
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
	my $q = $self->{'cgi'};
	my %outcome = ( accepted => 'good', rejected => 'bad' );
	$self->_update_submission_outcome( $submission_id, $outcome{ $q->param('record_status') } );
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
	my $cds = $locus_info->{'data_type'} eq 'DNA' && $locus_info->{'complete_cds'} ? '<th>Complete CDS</th>' : '';
	say q(<table class="resultstable">);
	say qq(<tr><th>Identifier</th><th>Length</th><th>Sequence</th>$cds<th>Status</th><th>Assigned allele</th></tr>);
	my ( $all_assigned, $all_rejected, $all_assigned_or_rejected ) = ( 1, 1, 1 );
	my $td              = 1;
	my $pending_seqs    = [];
	my $locus_seq_table = $self->{'datastore'}->create_temp_allele_table( $allele_submission->{'locus'} );

	foreach my $seq (@$seqs) {
		my $id       = $seq->{'seq_id'};
		my $length   = length $seq->{'sequence'};
		my $sequence = BIGSdb::Utils::truncate_seq( \$seq->{'sequence'}, 40 );
		$cds = '';
		if ( $locus_info->{'data_type'} eq 'DNA' && $locus_info->{'complete_cds'} ) {
			$cds =
			  BIGSdb::Utils::is_complete_cds( \$seq->{'sequence'} )->{'cds'}
			  ? q(<td><span class="fa fa-check fa-lg" style="color:green"></span></td>)
			  : q(<td><span class="fa fa-times fa-lg" style="color:red"></span></td>);
		}
		say qq(<tr class="td$td"><td>$id</td><td>$length</td>);
		say qq(<td class="seq">$sequence</td>$cds);
		my $assigned = $self->{'datastore'}->run_query(
			"SELECT allele_id FROM $locus_seq_table WHERE sequence=?",
			uc( $seq->{'sequence'} ),
			{ cache => 'SubmitPage::print_sequence_table_fieldset' }
		);
		if ( !defined $assigned ) {
			if ( defined $seq->{'assigned_id'} ) {
				$self->_clear_assigned_seq_id( $submission_id, $seq->{'seq_id'} );
			}
			if ( $seq->{'status'} eq 'assigned' ) {
				$self->_set_allele_status( $submission_id, $seq->{'seq_id'}, 'pending', undef );
			}
			push @$pending_seqs, $seq if $seq->{'status'} ne 'rejected';
		} else {
			if ( $seq->{'status'} eq 'pending' ) {
				$self->_set_allele_status( $submission_id, $seq->{'seq_id'}, 'assigned', $assigned );
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
		if ( $options->{'curate'} && $seq->{'status'} ne 'rejected' && $assigned eq '' ) {
			say qq(<td><a href="$self->{'system'}->{'curate_script'}?db=$self->{'instance'}&amp;page=add&amp;)
			  . qq(table=sequences&amp;locus=$locus&amp;submission_id=$submission_id&amp;index=$seq->{'index'}&amp;)
			  . qq(sender=$submission->{'submitter'}&amp;status=unchecked">)
			  . q(<span class="fa fa-lg fa-edit"></span>Curate</a></td>);
		} else {
			say qq(<td>$assigned</td>);
		}
		say q(</tr>);
		$td = $td == 1 ? 2 : 1;
		$self->{'mod_perl_request'}->rflush if $ENV{'MOD_PERL'};
	}
	say q(</table>);
	if ( $options->{'curate'} ) {
		my $outcome;
		if ( !@$pending_seqs ) {
			if ($all_assigned) {
				$outcome = 'good';
			} elsif ($all_rejected) {
				$outcome = 'bad';
			} else {
				$outcome = 'mixed';
			}
		} else {
			undef $outcome;
		}
		$self->_update_submission_outcome( $submission_id, $outcome );
	}
	return {
		all_assigned_or_rejected => $all_assigned_or_rejected,
		all_assigned             => $all_assigned,
		pending_seqs             => $pending_seqs
	};
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
	say q(<table class="resultstable">);
	say q(<tr><th>Identifier</th>);

	foreach my $locus (@$loci) {
		my $clean_locus = $self->clean_locus($locus);
		print qq(<th>$clean_locus</th>);
	}
	say qq(<th>Status</th><th>Assigned $scheme_info->{'primary_key'}</th></tr>);
	my $td    = 1;
	my $index = 1;
	foreach my $profile ( @{ $profile_submission->{'profiles'} } ) {
		say qq(<tr class="td$td"><td>$profile->{'profile_id'}</td>);
		foreach my $locus (@$loci) {
			say qq(<td>$profile->{'designations'}->{$locus}</td>);
		}
		my $scheme = $self->{'datastore'}->get_scheme($scheme_id);
		my $profile_status = $self->{'datastore'}->check_new_profile( $scheme_id, $profile->{'designations'} );
		my $assigned;
		if ( !$profile_status->{'exists'} ) {
			if ( defined $profile->{'assigned_id'} ) {
				$self->_clear_assigned_profile_id( $submission_id, $profile->{'profile_id'} );
				$profile->{'assigned_id'} = undef;
			}
			if ( $profile->{'status'} eq 'assigned' ) {
				$self->_set_profile_status( $submission_id, $profile->{'profile_id'}, 'pending', undef );
				$profile->{'status'} = 'pending';
			}
			push @$pending_profiles, $profile->{'index'} if $profile->{'status'} ne 'rejected';
		} else {
			$assigned = $profile_status->{'assigned'}->[0];
			if ( $profile->{'status'} ne 'assigned' || ( $profile->{'assigned_id'} // '' ) ne $assigned ) {
				$self->_set_profile_status( $submission_id, $profile->{'profile_id'}, 'assigned', $assigned );
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
		if ( $options->{'curate'} && $profile->{'status'} ne 'rejected' && $assigned eq '' ) {
			say qq(<td><a href="$self->{'system'}->{'curate_script'}?db=$self->{'instance'}&amp;page=profileAdd&amp;)
			  . qq(scheme_id=$scheme_id&amp;submission_id=$submission_id&amp;index=$index">)
			  . q(<span class="fa fa-lg fa-edit"></span>Curate</a></td>);
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
			if ($all_assigned) {
				$outcome = 'good';
			} elsif ($all_rejected) {
				$outcome = 'bad';
			} else {
				$outcome = 'mixed';
			}
		} else {
			undef $outcome;
		}
		$self->_update_submission_outcome( $submission_id, $outcome );
	}
	say q(</table>);
	return {
		all_assigned_or_rejected => $all_assigned_or_rejected,
		all_assigned             => $all_assigned,
		pending_profiles         => $pending_profiles
	};
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
	say q(<table class="resultstable"><tr>);
	say qq(<th>$_</th>) foreach @$fields;
	say q(</tr>);
	my $td = 1;
	local $" = q(</td><td>);
	my $i           = 1;
	my $files       = $self->_get_submission_files($submission_id);
	my %file_exists = map { $_->{'filename'} => 1 } @$files;
	my $dir         = $self->{'submissionHandler'}->get_submission_dir($submission_id) . '/supporting_files';
	my %filename_already_used;

	foreach my $isolate (@$isolates) {
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
			} else {
				push @values, $isolate->{$field} // q();
			}
		}
		say qq(<tr class="td$td"><td>@values</td></tr>);
		$td = $td == 1 ? 2 : 1;
		$i++;
	}
	say q(</table>);
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
	my $plural = @$seqs == 1 ? '' : 's';
	say qq(<p>You are submitting the following $allele_submission->{'locus'} sequence$plural: )
	  . qq(<a href="/submissions/$submission_id/sequences.fas">Download$fasta_icon</a></p>)
	  if ( $options->{'download_link'} );
	say $q->start_form;
	my $status = $self->_print_sequence_table( $submission_id, $options );
	$self->_print_update_button if $options->{'curate'} && !$status->{'all_assigned'};
	say $q->hidden($_) foreach qw(db page submission_id curate);
	say $q->end_form;
	my $has_extended_attributes =
	  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM locus_extended_attributes WHERE locus=?)', $locus );

	if ( $options->{'curate'} && !$status->{'all_assigned_or_rejected'} && !$has_extended_attributes ) {
		say $q->start_form( -action => $self->{'system'}->{'curate_script'} );
		say $q->submit( -name => 'Batch curate', -class => BUTTON_CLASS, -style => 'float:left' );
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
		say $q->submit( -name => 'Batch query', -class => BUTTON_CLASS, -style => 'float:left' );
		$q->param( page => 'batchSequenceQuery' );
		say $q->hidden($_) foreach qw( db page submission_id locus sequence );
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
	if ( $options->{'record_status'} ) {
		say q(<label for="record_status">Record status:</label>);
		say $q->popup_menu( -name => 'record_status', id => 'record_status',
			values => [qw(pending accepted rejected)] );
	}
	say $q->submit( -name => 'update', -label => 'Update', -class => BUTTON_CLASS );
	say q(</div>);
	return;
}

sub _clear_assigned_seq_id {
	my ( $self, $submission_id, $seq_id ) = @_;
	eval {
		$self->{'db'}->do( 'UPDATE allele_submission_sequences SET assigned_id=NULL WHERE (submission_id,seq_id)=(?,?)',
			undef, $submission_id, $seq_id );
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		$self->_update_submission_datestamp($submission_id);
	}
	return;
}

sub _clear_assigned_profile_id {
	my ( $self, $submission_id, $profile_id ) = @_;
	eval {
		$self->{'db'}
		  ->do( 'UPDATE profile_submission_profiles SET assigned_id=NULL WHERE (submission_id,profile_id)=(?,?)',
			undef, $submission_id, $profile_id );
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		$self->_update_submission_datestamp($submission_id);
	}
	return;
}

sub _set_allele_status {
	my ( $self, $submission_id, $seq_id, $status, $assigned_id ) = @_;
	eval {
		$self->{'db'}
		  ->do( 'UPDATE allele_submission_sequences SET (status,assigned_id)=(?,?) WHERE (submission_id,seq_id)=(?,?)',
			undef, $status, $assigned_id, $submission_id, $seq_id );
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		$self->_update_submission_datestamp($submission_id);
	}
	return;
}

sub _set_profile_status {
	my ( $self, $submission_id, $profile_id, $status, $assigned_id ) = @_;
	eval {
		$self->{'db'}->do(
			'UPDATE profile_submission_profiles SET (status,assigned_id)=(?,?) WHERE (submission_id,profile_id)=(?,?)',
			undef, $status, $assigned_id, $submission_id, $profile_id
		);
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		$self->_update_submission_datestamp($submission_id);
	}
	return;
}

sub _update_submission_datestamp {
	my ( $self, $submission_id ) = @_;
	eval { $self->{'db'}->do( 'UPDATE submissions SET datestamp=? WHERE id=?', undef, 'now', $submission_id ) };
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub _update_submission_outcome {
	my ( $self, $submission_id, $outcome ) = @_;
	eval { $self->{'db'}->do( 'UPDATE submissions SET outcome=? WHERE id=?', undef, $outcome, $submission_id ) };
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub _print_message_fieldset {
	my ( $self, $submission_id, $options ) = @_;
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	if ( $q->param('message') ) {
		my $user = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		if ( !$user ) {
			$logger->error('Invalid user.');
			return;
		}
		eval {
			$self->{'db'}->do( 'INSERT INTO messages (submission_id,timestamp,user_id,message) VALUES (?,?,?,?)',
				undef, $submission_id, 'now', $user->{'id'}, $q->param('message') );
		};
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
			$self->{'submissionHandler'}->append_message( $submission_id, $user->{'id'}, $q->param('message') );
			$q->delete('message');
			$self->_update_submission_datestamp($submission_id);
		}
		if ( $q->param('append_and_send') ) {
			my $desc    = $self->{'system'}->{'description'} || 'BIGSdb';
			my $subject = "$desc submission comment added - $submission_id";
			my $message = $self->{'submissionHandler'}->get_text_summary( $submission_id, { messages => 1 } );
			if ( $user->{'id'} == $submission->{'submitter'} ) {

				#Message from submitter
				my $curators = $self->{'submissionHandler'}->_get_curators($submission_id);
				foreach my $curator_id (@$curators) {
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
	my $buffer;
	my $qry = q(SELECT date_trunc('second',timestamp) AS timestamp,user_id,message FROM messages )
	  . q(WHERE submission_id=? ORDER BY timestamp asc);
	my $messages = $self->{'datastore'}->run_query( $qry, $submission_id, { fetch => 'all_arrayref', slice => {} } );
	if (@$messages) {
		$buffer .= q(<table class="resultstable"><tr><th>Timestamp</th><th>User</th><th>Message</th></tr>);
		my $td = 1;
		foreach my $message (@$messages) {
			my $user_string = $self->{'datastore'}->get_user_string( $message->{'user_id'} );
			( my $message_text = $message->{'message'} ) =~ s/\r?\n/<br \/>/gx;
			$buffer .= qq(<tr class="td$td"><td>$message->{'timestamp'}</td><td>$user_string</td>)
			  . qq(<td style="text-align:left">$message_text</td></tr>);
			$td = $td == 1 ? 2 : 1;
		}
		$buffer .= q(</table>);
	}
	if ( !$options->{'no_add'} ) {
		$buffer .= $q->start_form;
		$buffer .= q(<div>);
		$buffer .= $q->textarea( -name => 'message', -id => 'message', -style => 'width:100%' );
		$buffer .= q(</div><div style="float:right">Message: );
		$buffer .= $q->submit( -name => 'append_only', -label => 'Append', -class => BUTTON_CLASS );
		if ( $submission->{'email'} ) {
			$buffer .= $q->submit( -name => 'append_and_send', -label => 'Send now', -class => BUTTON_CLASS );
		}
		$buffer .= q(</div>);
		$buffer .= $q->hidden($_)
		  foreach qw(db page alleles profiles isolates genomes locus submit view curate abort submission_id no_check );
		$buffer .= $q->end_form;
	}
	say qq(<fieldset style="float:left"><legend>Messages</legend>$buffer</fieldset>) if $buffer;
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
	my @filenames = $q->param('file_upload');
	my $i         = 0;
	my $dir       = $self->{'submissionHandler'}->get_submission_dir($submission_id) . '/supporting_files';
	if ( !-e $dir ) {
		$self->{'submissionHandler'}->mkpath($dir);
	}
	foreach my $fh2 ( $q->upload('file_upload') ) {
		if ( $filenames[$i] =~ /([A-z0-9_\-\.'\ \(\)]+)/x ) {
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
		read( $fh2, $buffer, MAX_UPLOAD_SIZE );
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
		my $locus = $self->clean_locus( $allele_submission->{'locus'} ) // $allele_submission->{'locus'};
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
		say qq(<dt>assembly</dt><dd>$allele_submission->{'assembly'}</dd>);
		say qq(<dt>assembly software</dt><dd>$allele_submission->{'software'}</dd>);
	}
	say q(</dl></fieldset>);
	return;
}

#Check submission exists and curator has appropriate permissions.
sub _is_submission_valid {
	my ( $self, $submission_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	if ( !$submission_id ) {
		say q(<div class="box" id="statusbad"><p>No submission id passed.</p></div>) if !$options->{'no_message'};
		return;
	}
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	if ( !$submission ) {
		say qq(<div class="box" id="statusbad"><p>Submission '$submission_id' does not exist.</p></div>)
		  if !$options->{'no_message'};
		return;
	}
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	if ( $options->{'curate'} ) {
		if ( !$user_info || ( $user_info->{'status'} ne 'admin' && $user_info->{'status'} ne 'curator' ) ) {
			say q(<div class="box" id="statusbad"><p>Your account does not have the required )
			  . q(permissions to curate this submission.</p></div>)
			  if !$options->{'no_message'};
			return;
		}
		if ( $submission->{'type'} eq 'alleles' ) {
			my $allele_submission = $self->{'submissionHandler'}->get_allele_submission( $submission->{'id'} );
			my $curator_allowed =
			  $self->{'datastore'}
			  ->is_allowed_to_modify_locus_sequences( $allele_submission->{'locus'}, $user_info->{'id'} );
			if ( !( $self->is_admin || $curator_allowed ) ) {
				say q(<div class="box" id="statusbad"><p>Your account does not have the required )
				  . qq(permissions to curate new $allele_submission->{'locus'} sequences.</p></div>)
				  if !$options->{'no_message'};
				return;
			}
		}
	}
	if ( $options->{'user_owns'} ) {
		return if $submission->{'submitter'} != $user_info->{'id'};
	}
	return 1;
}

sub _curate_submission {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $submission_id ) = @_;
	say q(<h1>Curate submission</h1>);
	return if !$self->_is_submission_valid( $submission_id, { curate => 1 } );
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	my $curate     = 1;
	if ( $submission->{'status'} eq 'closed' ) {
		say q(<div class="box" id="statusbad"><p>This submission is closed and cannot now be modified.</p></div>);
		$curate = 0;
	}
	say q(<div class="box" id="resultstable"><div class="scrollable">);
	say qq(<h2>Submission: $submission_id</h2>);
	$self->_print_summary($submission_id);
	$self->_print_sequence_table_fieldset( $submission_id, { curate => $curate } );
	$self->_print_profile_table_fieldset( $submission_id, { curate => $curate } );
	$self->_print_isolate_table_fieldset( $submission_id, { curate => $curate } );
	$self->_print_file_fieldset($submission_id);
	$self->_print_message_fieldset($submission_id);
	$self->_print_archive_fieldset($submission_id);
	$self->_print_close_submission_fieldset($submission_id) if $curate;
	say q(</div></div>);
	return;
}

sub _view_submission {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $submission_id ) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Submission summary</h1>);
	return if !$self->_is_submission_valid($submission_id);
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	say q(<div class="box" id="resultstable"><div class="scrollable">);
	say qq(<h2>Submission: $submission_id</h2>);
	$self->_print_summary($submission_id);
	$self->_print_sequence_table_fieldset($submission_id);
	$self->_print_profile_table_fieldset($submission_id);
	$self->_print_isolate_table_fieldset($submission_id);
	$self->_print_file_upload_fieldset( $submission_id, { no_add => $submission->{'status'} eq 'closed' ? 1 : 0 } );
	$self->_print_message_fieldset( $submission_id, { no_add => $submission->{'status'} eq 'closed' ? 1 : 0 } );
	$self->_print_archive_fieldset($submission_id);
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
	if ( $submission->{'email'} ) {
		my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
		$self->{'submissionHandler'}->email(
			$submission_id,
			{
				recipient => $submission->{'submitter'},
				sender    => $curator_id,
				subject   => "$desc submission closed - $submission_id",
				message   => $self->{'submissionHandler'}->get_text_summary( $submission_id, { messages => 1 } ),
				cc_sender => 1
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

	if ( $ENV{'MOD_PERL'} ) {
		print `$command`;    # http://modperlbook.org/html/6-4-8-Output-from-System-Calls.html
	} else {
		system $command || $logger->error("Can't create tar: $?");
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
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return " Manage submissions - $desc ";
}
1;
