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
use parent qw(BIGSdb::TreeViewPage);
use Error qw(:try);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use Bio::Seq;
use BIGSdb::Utils;
use BIGSdb::BIGSException;
use BIGSdb::Page 'SEQ_METHODS';
use List::MoreUtils qw(none);
use File::Path qw(make_path remove_tree);
use POSIX;
use constant COVERAGE        => qw(<20x 20-49x 50-99x +100x);
use constant READ_LENGTH     => qw(<100 100-199 200-299 300-499 +500);
use constant ASSEMBLY        => ( 'de novo', 'mapped' );
use constant MAX_UPLOAD_SIZE => 32 * 1024 * 1024;                        #32Mb

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
	my $q = $self->{'cgi'};
	if ( $q->param('abort') && $q->param('submission_id') && $q->param('confirm') ) {
		$self->_abort_submission( $q->param('submission_id') );
	} elsif ( $q->param('finalize') ) {
		$self->_finalize_submission( $q->param('submission_id') );
	} elsif ( $q->param('tar') ) {
		$self->_tar_archive( $q->param('submission_id') );
		return;
	} elsif ( $q->param('view') ) {
		$self->_view_submission( $q->param('submission_id') );
		return;
	}
	say "<h1>Manage submissions</h1>";
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	if ( !$user_info ) {
		say qq(<div class="box" id="queryform"><p>You are not a recognized user.  Submissions are disabled.</p></div>);
		return;
	}
	if ( $q->param('alleles') ) {
		if ( $q->param('submit') ) {
			$self->_update_allele_prefs;
		}
		$self->_submit_alleles;
		return;
	}
	say qq(<div class="box" id="resultstable"><div class="scrollable">);
	my $incomplete = $self->{'datastore'}->run_query(
		"SELECT * FROM submissions WHERE (submitter,status)=(?,?) ORDER BY datestamp asc",
		[ $user_info->{'id'}, 'started' ],
		{ fetch => 'all_arrayref', slice => {}, cache => 'SubmitPage::print_content' }
	);
	if (@$incomplete) {
		say qq(<h2>Submission in process</h2>);
		say qq(<p>Please note that you must either proceed with or abort the in process submission before you can start another.</p>);
		foreach my $submission (@$incomplete) {    #There should only be one but this isn't enforced at the database level.
			say qq(<dl class="data"><dt>Submission</dt><dd>$submission->{'id'}</dd>);
			say qq(<dt>Datestamp</dt><dd>$submission->{'datestamp'}</dd>);
			say qq(<dt>Type</dt><dd>$submission->{'type'}</dd>);
			if ( $submission->{'type'} eq 'alleles' ) {
				my $allele_submission = $self->_get_allele_submission( $submission->{'id'} );
				if ($allele_submission) {
					say qq(<dt>Locus</dt><dd>$allele_submission->{'locus'}</dd>);
					my $seq_count = @{ $allele_submission->{'seqs'} };
					say qq(<dt>Sequences</dt><dd>$seq_count</dd>);
				}
				say qq(<dt>Action</dt><dd><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit&amp;)
				  . qq($submission->{'type'}=1&amp;abort=1&amp;no_check=1">Abort</a> | )
				  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit&amp;$submission->{'type'}=1&amp;)
				  . qq(continue=1">Continue</a>);
			}
			say qq(</dl>);
		}
	} else {
		say qq(<h2>Submit new data</h2>);
		say
		  qq(<p>Data submitted here will go in to a queue for handling by a curator or by an automated script.  You will be able to track )
		  . qq(the status of any submission.</p>);
		say qq(<ul><li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit&amp;alleles=1">Submit alleles</a>)
		  . qq(</li>);
		say qq(</ul>);
	}
	my $pending = $self->{'datastore'}->run_query(
		"SELECT * FROM submissions WHERE (submitter,status)=(?,?) ORDER BY datestamp asc",
		[ $user_info->{'id'}, 'pending' ],
		{ fetch => 'all_arrayref', slice => {}, cache => 'SubmitPage::print_content' }
	);
	if (@$pending) {
		say qq(<h2>Pending submissions</h2>);
		say qq(<p>You have the following submissions pending curation:</p>);
		say qq(<table class="resultstable"><tr><th>Submission id</th><th>Datestamp</th><th>Type</th><th>Details</th></tr>);
		my $td = 1;
		foreach my $submission (@$pending) {
			my $url = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit&amp;)
			  . qq(submission_id=$submission->{'id'}&amp;view=1);
			say qq(<tr class="td$td"><td><a href="$url">$submission->{'id'}</a></td>);
			say qq(<td>$submission->{'datestamp'}</td><td>$submission->{'type'}</td>);
			my $details = '';
			if ( $submission->{'type'} eq 'alleles' ) {
				my $allele_submission = $self->_get_allele_submission( $submission->{'id'} );
				my $allele_count      = @{ $allele_submission->{'seqs'} };
				my $plural            = $allele_count == 1 ? '' : 's';
				$details = "$allele_count $allele_submission->{'locus'} sequence$plural";
			}
			say qq(<td>$details</td></tr>);
			$td = $td == 1 ? 2 : 1;
		}
		say qq(</table>);
	}
	say qq(</div></div>);
	return;
}

sub _print_allele_warnings {
	my ( $self, $warnings ) = @_;
	return if ref $warnings ne 'ARRAY' || !@$warnings;
	my @info = @$warnings;
	local $" = "<br />";
	my $plural = @info == 1 ? '' : 's';
	say qq(<div class="box" id="statuswarn"><h2>Warning$plural:</h2><p>@info</p><p>Warnings do not prevent submission )
	  . qq(but may result in the submission being rejected depending on curation criteria.</p></div>);
	return;
}

sub _abort_submission {
	my ( $self, $submission_id ) = @_;
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	eval { $self->{'db'}->do( "DELETE FROM submissions WHERE (id,submitter)=(?,?)", undef, $submission_id, $user_info->{'id'} ) };
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		$self->_delete_submission_files($submission_id);
	}
	return;
}

sub _delete_submission_files {
	my ( $self, $submission_id ) = @_;
	my $dir = $self->_get_submission_dir($submission_id);
	remove_tree $1 if $dir =~ /^($self->{'config'}->{'submission_dir'}\/BIGSdb[^\/]+$)/;
	return;
}

sub _finalize_submission {
	my ( $self, $submission_id ) = @_;
	my $q = $self->{'cgi'};
	my $type = $self->{'datastore'}->run_query( "SELECT type FROM submissions WHERE id=?", $submission_id );
	return if !$type;
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	eval {
		if ( $type eq 'alleles' )
		{
			$self->{'db'}->do(
				"UPDATE allele_submissions SET (technology,read_length,coverage,assembly,software)=(?,?,?,?,?) "
				  . "WHERE submission_id=? AND submission_id IN (SELECT id FROM submissions WHERE submitter=?)",
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
		$self->{'db'}
		  ->do( "UPDATE submissions SET status='pending' WHERE (id,submitter)=(?,?)", undef, $submission_id, $user_info->{'id'} );
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub _submit_alleles {
	my ($self)        = @_;
	my $q             = $self->{'cgi'};
	my $submission_id = $self->_get_started_submission;
	$q->param( submission_id => $submission_id );
	my $ret;
	if ($submission_id) {
		my $allele_submission = $self->_get_allele_submission($submission_id);
		my $fasta_string;
		foreach my $seq ( @{ $allele_submission->{'seqs'} } ) {
			$fasta_string .= '>' . $seq->id . "\n";
			$fasta_string .= $seq->seq . "\n";
		}
		if ( !$q->param('no_check') ) {
			$ret = $self->{'datastore'}->check_new_alleles_fasta( $allele_submission->{'locus'}, \$fasta_string );
			$self->_print_allele_warnings( $ret->{'info'} );
		}
		$self->_presubmit_alleles( $submission_id, undef );
		return;
	} elsif ( $q->param('submit') || $q->param('continue') || $q->param('abort') ) {
		$ret = $self->_check_new_alleles;
		if ( $ret->{'err'} ) {
			my @err = @{ $ret->{'err'} };
			local $" = "<br />";
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
	say qq(<div class="box" id="queryform"><div class="scrollable">);
	say qq(<h2>Submit new alleles</h2>);
	say qq(<p>You need to make a separate submission for each locus for which you have new alleles - this is because different loci may )
	  . qq(have different curators.  You can submit any number of new sequences for a single locus as one submission. Sequences should be )
	  . qq(trimmed to the correct start/end sites for the selected locus.</p>);
	my $set_id = $self->get_set_id;
	my ( $loci, $labels );
	say $q->start_form;
	my $schemes =
	  $self->{'datastore'}->run_query( "SELECT id FROM schemes ORDER BY display_order,description", undef, { fetch => 'col_arrayref' } );

	if ( @$schemes > 1 ) {
		say qq(<fieldset id="scheme_fieldset" style="float:left;display:none"><legend>Filter loci by scheme</legend>);
		say qq(<div id="tree" class="scheme_tree" style="float:left;max-height:initial">);
		say $self->get_tree( undef, { no_link_out => 1, select_schemes => 1 } );
		say qq(</div>);
		say $q->submit( -name => 'filter', -id => 'filter', -label => 'Filter', -class => 'submit' );
		say qq(</fieldset>);
		my @selected_schemes;
		foreach ( @$schemes, 0 ) {
			push @selected_schemes, $_ if $q->param("s_$_");
		}
		my $scheme_loci = @selected_schemes ? $self->_get_scheme_loci( \@selected_schemes ) : undef;
		( $loci, $labels ) = $self->{'datastore'}->get_locus_list( { only_include => $scheme_loci, set_id => $set_id } );
	} else {
		( $loci, $labels ) = $self->{'datastore'}->get_locus_list( { set_id => $set_id } );
	}
	say qq(<fieldset style="float:left"><legend>Select locus</legend>);
	say $q->popup_menu( -name => 'locus', -id => 'locus', -values => $loci, -labels => $labels, -size => 9, -required => 'required' );
	say qq(</fieldset>);
	$self->_print_sequence_details_fieldset($submission_id);
	say qq(<fieldset style="float:left"><legend>FASTA or single sequence</legend>);
	say $q->textarea( -name => 'fasta', -cols => 30, -rows => 5, -id => 'fasta', -required => 'required' );
	say qq(</fieldset>);
	say $q->hidden($_) foreach qw(db page alleles);
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->end_form;
	say qq(</div></div>);
	return;
}

sub _print_sequence_details_fieldset {
	my ( $self, $submission_id ) = @_;
	my $q = $self->{'cgi'};
	say qq(<fieldset style="float:left"><legend>Sequence details</legend>);
	say qq(<ul><li><label for="technology" class="parameter">technology:!</label>);
	my $allele_submission = $submission_id ? $self->_get_allele_submission($submission_id) : undef;
	my $att_labels = { '' => ' ' };    #Required for HTML5 validation
	say $q->popup_menu(
		-name     => 'technology',
		-id       => 'technology',
		-values   => [ '', SEQ_METHODS ],
		-labels   => $att_labels,
		-required => 'required',
		-default  => $allele_submission->{'technology'} // $self->{'prefs'}->{'submit_allele_technology'}
	);
	say qq(<li><label for="read_length" id="read_length_label" class="parameter">read length:</label>);
	say $q->popup_menu(
		-name    => 'read_length',
		-id      => 'read_length',
		-values  => [ '', READ_LENGTH ],
		-labels  => $att_labels,
		-default => $allele_submission->{'read_length'} // $self->{'prefs'}->{'submit_allele_read_length'}
	);
	say qq(</li><li><label for="coverage" id="coverage_label" class="parameter">coverage:</label>);
	say $q->popup_menu(
		-name    => 'coverage',
		-id      => 'coverage',
		-values  => [ '', COVERAGE ],
		-labels  => $att_labels,
		-default => $allele_submission->{'coverage'} // $self->{'prefs'}->{'submit_allele_coverage'}
	);
	say qq(</li><li><label for="assembly" class="parameter">assembly:!</label>);
	say $q->popup_menu(
		-name     => 'assembly',
		-id       => 'assembly',
		-values   => [ '', ASSEMBLY ],
		-labels   => $att_labels,
		-required => 'required',
		-default  => $allele_submission->{'assembly'} // $self->{'prefs'}->{'submit_allele_assembly'}
	);
	say qq(</li><li><label for="software" class="parameter">assembly software:!</label>);
	say $q->textfield(
		-name     => 'software',
		-id       => 'software',
		-required => 'required',
		-default  => $allele_submission->{'software'} // $self->{'prefs'}->{'submit_allele_software'}
	);
	say qq(</li></ul>);
	say qq(</fieldset>);
	return;
}

sub _check_new_alleles {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $locus  = $q->param('locus');
	if ( !$locus ) {
		return { err => ['No locus is selected.'] };
	}
	$locus =~ s/^cn_//;
	$q->param( locus => $locus );
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( !$locus_info ) {
		return { err => ['Locus $locus is not recognized.'] };
	}
	my $seqs = {};
	if ( $q->param('fasta') ) {
		my $fasta_string = $q->param('fasta');
		$fasta_string = ">seq\n$fasta_string" if $fasta_string !~ /^\s*>/;
		return $self->{'datastore'}->check_new_alleles_fasta( $locus, \$fasta_string );
	}
	return;
}

sub _start_submission {
	my ( $self, $type ) = @_;
	$logger->logdie("Invalid submission type '$type'") if none { $type eq $_ } qw (alleles);
	my $submission_id = 'BIGSdb_' . strftime( "%Y%m%d%H%M%S", localtime ) . "_$$\_" . int( rand(99999) );
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	eval {
		$self->{'db'}->do( "INSERT INTO submissions (id,type,submitter,datestamp,status) VALUES (?,?,?,?,?)",
			undef, $submission_id, $type, $user_info->{'id'}, 'now', 'started' );
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return $submission_id;
}

sub _get_started_submission {
	my ($self) = @_;
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	return $self->{'datastore'}->run_query(
		"SELECT id FROM submissions WHERE (submitter,status)=(?,?)",
		[ $user_info->{'id'}, 'started' ],
		{ cache => 'SubmitPage::get_started_submission' }
	);
}

sub _get_submission {
	my ( $self, $submission_id ) = @_;
	$logger->logcarp("No submission_id passed") if !$submission_id;
	return $self->{'datastore'}->run_query( "SELECT * FROM submissions WHERE id=?",
		$submission_id, { fetch => 'row_hashref', cache => 'SubmitPage::get_submission' } );
}

sub _get_allele_submission {
	my ( $self, $submission_id ) = @_;
	$logger->logcarp("No submission_id passed") if !$submission_id;
	my $submission = $self->{'datastore'}->run_query( "SELECT * FROM allele_submissions WHERE submission_id=?",
		$submission_id, { fetch => 'row_hashref', cache => 'SubmitPage::get_allele_submission' } );
	return if !$submission;
	my $seq_data = $self->{'datastore'}->run_query( "SELECT * FROM allele_submission_sequences WHERE submission_id=?",
		$submission_id, { fetch => 'all_arrayref', slice => {} } );
	my @seqs;
	foreach my $seq (@$seq_data) {
		my $seq_obj = Bio::PrimarySeq->new( -id => $seq->{'seq_id'}, -seq => $seq->{'sequence'} );
		push @seqs, $seq_obj;
	}
	$submission->{'seqs'} = \@seqs;
	return $submission;
}

sub _presubmit_alleles {
	my ( $self, $submission_id, $seqs ) = @_;
	$seqs //= [];
	return if !$submission_id && !@$seqs;
	my $q = $self->{'cgi'};
	my $locus;
	if ($submission_id) {
		my $allele_submission = $self->_get_allele_submission($submission_id);
		$locus = $allele_submission->{'locus'} // '';
		$seqs  = $allele_submission->{'seqs'}  // [];
	} else {
		$locus         = $q->param('locus');
		$submission_id = $self->_start_submission('alleles');
		eval {
			$self->{'db'}->do(
				"INSERT INTO allele_submissions (submission_id,locus,technology,read_length,coverage,assembly,"
				  . "software) VALUES (?,?,?,?,?,?,?)",
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
			my $insert_sql =
			  $self->{'db'}->prepare("INSERT INTO allele_submission_sequences (submission_id,seq_id,sequence) VALUES (?,?,?)");
			foreach my $seq (@$seqs) {
				eval { $insert_sql->execute( $submission_id, $seq->id, $seq->seq ) };
				if ($@) {
					$logger->error($@);
					$self->{'db'}->rollback;
					return;
				}
			}
			$self->_write_allele_FASTA($submission_id);
		}
		$self->{'db'}->commit;
	}
	if ( $q->param('file_upload') ) {
		my $upload_file = $self->_upload_files($submission_id);
	}
	if ( $q->param('delete') ) {
		my $files = $self->_get_submission_files($submission_id);
		my $i     = 0;
		my $dir   = $self->_get_submission_dir($submission_id) . '/supporting_files';
		foreach my $file (@$files) {
			if ( $q->param("file$i") ) {
				if ( $file->{'filename'} =~ /^([^\/]+)$/ ) {
					my $filename = $1;
					unlink "$dir/$filename" || $logger->error("Cannot delete $dir/$filename.");
				}
				$q->delete("file$i");
			}
			$i++;
		}
	}
	say qq(<div class="box" id="resultstable"><div class="scrollable">);
	if ( $q->param('abort') ) {
		say qq(<div style="float:left">);
		$self->print_warning_sign( { no_div => 1 } );
		say qq(</div>);
		say $q->start_form;
		$self->print_action_fieldset( { no_reset => 1, submit_label => 'Abort submission!' } );
		$q->param( confirm       => 1 );
		$q->param( submission_id => $submission_id );
		say $q->hidden($_) foreach qw(db page submission_id abort confirm);
		say $q->end_form;
	}
	say qq(<h2>Submission: $submission_id</h2>);
	say $q->start_form;
	$self->_print_sequence_details_fieldset($submission_id);
	my $plural = @$seqs == 1 ? '' : 's';
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ($locus_info) {
		say qq(<fieldset style="float:left"><legend>Sequences</legend>);
		my $fasta_icon = $self->get_file_icon('FAS');
		say qq(<p>You are submitting the following $locus sequence$plural: <a href="/submissions/$submission_id/sequences.fas">)
		  . qq(Download$fasta_icon</a></p>);
		say qq(<table class="resultstable">);
		my $cds = $locus_info->{'data_type'} eq 'DNA' && $locus_info->{'complete_cds'} ? '<th>Complete CDS</th>' : '';
		say qq(<tr><th>Identifier</th><th>Length</th><th>Sequence</th>$cds</tr>);
		my $td = 1;
		foreach my $seq (@$seqs) {
			my $id       = $seq->id;
			my $length   = length $seq->seq;
			my $sequence = BIGSdb::Utils::truncate_seq( \$seq->seq, 40 );
			$cds = '';
			if ( $locus_info->{'data_type'} eq 'DNA' && $locus_info->{'complete_cds'} ) {
				$cds = BIGSdb::Utils::is_complete_cds( \$seq->seq )->{'cds'} ? '<td>yes</td>' : '<td>no</td>';
			}
			say qq(<tr class="td$td"><td>$id</td><td>$length</td><td class="seq">$sequence</td>$cds</tr>);
			$td = $td == 1 ? 2 : 1;
		}
		say qq(</table>);
		say qq(</fieldset>);
	} else {
		$logger->error("Invalid submission $submission_id - no locus info.");
	}
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Finalize submission!' } );
	$q->param( finalize      => 1 );
	$q->param( submission_id => $submission_id );
	say $q->hidden($_) foreach qw(db page locus submit finalize submission_id);
	say $q->end_form;
	say qq(<fieldset style="float:left"><legend>Supporting files</legend>);
	say qq(<p>Please upload any supporting files required for curation.  Ensure that these are named unambiguously or add an explanatory )
	  . qq(note so that they can be linked to the appropriate sequence.  Individual filesize is limited to )
	  . BIGSdb::Utils::get_nice_size(MAX_UPLOAD_SIZE)
	  . qq(.</p>);
	say $q->start_form;
	print $q->filefield( -name => 'file_upload', -id => 'file_upload', -multiple );
	say $q->submit( -name => 'Upload files', -class => 'submitbutton ui-button ui-widget ui-state-default ui-corner-all' );
	$q->param( no_check => 1 );
	say $q->hidden($_) foreach qw(db page alleles locus submit submission_id no_check);
	say $q->end_form;
	my $files = $self->_get_submission_files($submission_id);

	if (@$files) {
		say $q->start_form;
		$self->_print_submission_file_table( $submission_id, { delete_checkbox => 1 } );
		$q->param( delete => 1 );
		say $q->hidden($_) foreach qw(db page alleles delete no_check);
		say $q->submit( -label => 'Delete selected files', -class => 'submitbutton ui-button ui-widget ui-state-default ui-corner-all' );
		say $q->end_form;
	}
	say qq(</fieldset>);
	say qq(</div></div>);
	return;
}

sub _print_message_fieldset {
	my ($self, $submission_id) = @_;
	
	
}

sub _print_submission_file_table {
	my ( $self, $submission_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q     = $self->{'cgi'};
	my $files = $self->_get_submission_files($submission_id);
	return if !@$files;
	my $buffer = qq(<table class="resultstable"><tr><th>Filename</th><th>Size</th>);
	$buffer .= qq(<th>Delete</th>) if $options->{'delete_checkbox'};
	$buffer .= qq(</tr>\n);
	my $td = 1;
	my $i  = 0;

	foreach my $file (@$files) {
		$buffer .= qq(<tr class="td$td"><td><a href="/submissions/$submission_id/supporting_files/$file->{'filename'}">)
		  . qq($file->{'filename'}</a></td><td>$file->{'size'}</td>);
		if ( $options->{'delete_checkbox'} ) {
			$buffer .= qq(<td>);
			$buffer .= $q->checkbox( -name => "file$i", -label => '' );
			$buffer .= qq(</td>);
		}
		$i++;
		$buffer .= qq(</tr>\n);
		$td = $td == 2 ? 1 : 2;
	}
	$buffer .= qq(</table>);
	return $buffer if $options->{'get_only'};
	say $buffer;
	return;
}

sub _get_submission_files {
	my ( $self, $submission_id ) = @_;
	my $dir = $self->_get_submission_dir($submission_id) . "/supporting_files";
	return [] if !-e $dir;
	my @files;
	opendir( my $dh, $dir ) || $logger->error("Can't open directory $dir");
	while ( my $filename = readdir $dh ) {
		next if $filename =~ /^\./;
		next if $filename =~ /^submission/;    #Temp file created by script
		push @files, { filename => $filename, size => BIGSdb::Utils::get_nice_size( -s "$dir/$filename" ) };
	}
	closedir $dh;
	return \@files;
}

sub _get_submission_dir {
	my ( $self, $submission_id ) = @_;
	return "$self->{'config'}->{'submission_dir'}/$submission_id";
}

sub _upload_files {
	my ( $self, $submission_id ) = @_;
	my $q         = $self->{'cgi'};
	my @filenames = $q->param('file_upload');
	my $i         = 0;
	my $dir       = $self->_get_submission_dir($submission_id) . '/supporting_files';
	if ( !-e $dir ) {
		make_path $dir || $logger->error("Cannot create $dir directory.");
	}
	foreach my $fh2 ( $q->upload('file_upload') ) {
		if ( $filenames[$i] =~ /([A-z0-9_\-\.'\ \(\)]+)/ ) {
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
	return \@filenames;
}

sub _view_submission {
	my ( $self, $submission_id ) = @_;
	my $submission = $self->_get_submission($submission_id);
	if ( !$submission ) {
		say qq(<div class="box" id="statusbad"><p>Invalid submission passed.</p></div>);
		return;
	}
	say qq(<h1>Submission summary</h1>);
	say qq(<div class="box" id="resultstable"><div class="scrollable">);
	say qq(<h2>Submission: $submission_id</h2>);
	say qq(<fieldset style="float:left"><legend>Summary</legend>);
	say qq(<dl class="data"><dt>type</dt><dd>$submission->{'type'}</dd>);
	my $user_string = $self->{'datastore'}->get_user_string( $submission->{'submitter'}, { email => 1, affiliation => 1 } );
	say qq(<dt>submitter</dt><dd>$user_string</dd>);
	say qq(<dt>datestamp</dt><dd>$submission->{'datestamp'}</dd>);
	say qq(<dt>status</dt><dd>$submission->{'status'}</dd>);

	if ( $submission->{'type'} eq 'alleles' ) {
		my $allele_submission = $self->_get_allele_submission($submission_id);
		say qq(<dt>locus</dt><dd>$allele_submission->{'locus'}</dd>);
		my $allele_count = @{ $allele_submission->{'seqs'} };
		my $fasta_icon   = $self->get_file_icon('FAS');
		say qq(<dt>sequences</dt><dd><a href="/submissions/$submission_id/sequences.fas">$allele_count$fasta_icon</a></dd>);
	}
	say qq(</dl></fieldset>);
	my $file_table = $self->_print_submission_file_table( $submission_id, { get_only => 1 } );
	if ($file_table) {
		say qq(<fieldset style="float:left"><legend>Supporting files</legend>);
		say $file_table;
		say qq(</fieldset>);
	}
	say qq(<fieldset style="float:left"><legend>Archive</legend>);
	say qq(<p>Archive of submission and any supporting files:</p>);
	my $tar_icon = $self->get_file_icon('TAR');
	say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit&amp;submission_id=$submission_id&amp;)
	  . qq(tar=1">Download$tar_icon</a></p>);
	say qq(</fieldset>);
	say qq(</div></div>);
	return;
}

sub _write_allele_FASTA {
	my ( $self, $submission_id ) = @_;
	my $allele_submission = $self->_get_allele_submission($submission_id);
	my $seqs              = $allele_submission->{'seqs'};
	return if !@$seqs;
	my $dir = $self->_get_submission_dir($submission_id);
	$dir = $dir =~ /^($self->{'config'}->{'submission_dir'}\/BIGSdb[^\/]+$)/ ? $1 : undef;    #Untaint
	make_path $dir;
	my $filename = 'sequences.fas';
	open( my $fh, '>', "$dir/$filename" ) || $logger->error("Can't open $dir/$filename for writing");

	foreach my $seq (@$seqs) {
		say $fh '>' . $seq->id;
		say $fh $seq->seq;
	}
	close $fh;
	return $filename;
}

sub _tar_archive {
	my ( $self, $submission_id ) = @_;
	return if !defined $submission_id || $submission_id !~ /BIGSdb_\d+/;
	my $submission = $self->_get_submission($submission_id);
	return if !$submission;
	my $submission_dir = $self->_get_submission_dir($submission_id);
	$submission_dir = $submission_dir =~ /^($self->{'config'}->{'submission_dir'}\/BIGSdb[^\/]+)$/ ? $1 : undef;    #Untaint
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
		  $_ ? $self->{'datastore'}->get_scheme_loci($_) : $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
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
	$self->{'pref_requirements'} = { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return " Manage submissions - $desc ";
}
1;
