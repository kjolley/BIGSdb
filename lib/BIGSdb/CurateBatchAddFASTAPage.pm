#Written by Keith Jolley
#Copyright (c) 2013-2019, University of Oxford
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
package BIGSdb::CurateBatchAddFASTAPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateAddPage);
use BIGSdb::Utils;
use BIGSdb::Offline::BatchFASTASequenceCheck;
use Log::Log4perl qw(get_logger);
use Try::Tiny;
use List::MoreUtils qw(any none);
use IO::String;
use Bio::SeqIO;
use Digest::MD5;
use constant SUCCESS => 1;
use constant FAILURE => 2;
use BIGSdb::Constants qw(:interface SEQ_STATUS HAPLOID DIPLOID IDENTITY_THRESHOLD);
my $logger = get_logger('BIGSdb.Page');

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/curator_guide.html#upload-using-a-fasta-file";
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Batch insert sequences</h1>);
	if ( $q->param('upload_file') ) {
		$self->_upload( $q->param('upload_file') );
		return;
	} elsif ( $q->param('submit') ) {
		if ( !$self->can_modify_table('sequences') ) {
			my $locus = $q->param('locus');
			$self->print_bad_status(
				{
					message => qq(Your user account is not allowed to add $locus alleles to the database.),
					navbar  => 1
				}
			);
			return;
		}
		my @missing;
		foreach my $field (qw (locus status sender sequence)) {
			push @missing, $field if !$q->param($field);
		}
		if (@missing) {
			local $" = q(, );
			$self->print_bad_status(
				{
					message => qq(Please complete the form. The following fields are missing: @missing),
					navbar  => 1
				}
			);
			$self->_print_interface;
			return;
		}
		if ( $self->_check == FAILURE ) {
			$self->_print_interface;
			return;
		}
		return;
	}
	$self->_print_interface;
	return;
}

sub _print_interface {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $set_id = $self->get_set_id;
	say q(<div class="box" id="queryform">);
	say q(<div class="scrollable">);
	say q(<p>This page allows you to upload allele sequence data in FASTA format. )
	  . q(The identifiers in the FASTA file will be used unless you select the option to use the next )
	  . q(available id (loci with integer ids only). Do not include the locus name in the identifier )
	  . q(in the FASTA file.</p>);
	my $extended_attributes =
	  $self->{'datastore'}->run_query('SELECT EXISTS(SELECT locus FROM locus_extended_attributes)');
	say q(<p>Please note that you can not use this page to upload sequences for loci with extended attributes.</p>)
	  if $extended_attributes;
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Enter parameters</legend><ul>);
	my ( $values, $desc ) = $self->{'datastore'}->get_locus_list(
		{
			set_id                 => $set_id,
			no_list_by_common_name => 1,
			no_extended_attributes => 1,
			locus_curator          => ( $self->is_admin ? undef : $self->get_curator_id )
		}
	);
	say q(<li><label for="locus" class="form" style="width:5em">locus:!</label>);
	say $q->popup_menu(
		-name     => 'locus',
		-id       => 'locus',
		-values   => [ '', @$values ],
		-labels   => $desc,
		-required => 'required'
	);
	say q(</li><li><label for="status" class="form" style="width:5em">status:!</label>);
	say $q->popup_menu( -name => 'status', -id => 'status', -values => [ '', SEQ_STATUS ], -required => 'required' );
	my ( $users, $user_names ) = $self->{'datastore'}->get_users( { blank_message => 'Select sender ...' } );
	say q(<li><label for="sender" class="form" style="width:5em">sender:!</label>);
	say $q->popup_menu(
		-name     => 'sender',
		-id       => 'sender',
		-values   => [ '', @$users ],
		-labels   => $user_names,
		-required => 'required'
	);
	say q(<li><label for="sequence" class="form" style="width:5em">sequence<br />(FASTA):!</label>);
	say $q->textarea( -name => 'sequence', -id => 'sequence', -rows => 10, -cols => 60, -required => 'required' );
	say q(</li><li>);
	say $q->checkbox(
		-name  => 'complete_CDS',
		-label => 'Reject all sequences that are not complete reading frames - these must have a start and '
		  . 'in-frame stop codon at the ends and no internal stop codons. Existing sequences are also ignored.'
	);
	say q(</li><li>);
	say $q->checkbox( -name => 'ignore_similarity', -label => 'Override sequence similarity check' );
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'use_next_id',
		-label   => 'Use next available id (only for loci with integer ids)',
		-checked => 'checked'
	);
	say q(</li></ul></fieldset>);
	$self->print_action_fieldset( { 'submit_label' => 'Check' } );
	say $q->hidden($_) foreach qw(db page set_id submission_id);
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub _check {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $locus, $sender, $sequence ) = ( $q->param('locus'), $q->param('sender'), $q->param('sequence') );
	if (   !$sender
		|| !BIGSdb::Utils::is_int($sender)
		|| !$self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM users WHERE id=?)', $sender ) )
	{
		$self->print_bad_status( { message => q(Sender is required and must exist in the users table.), navbar => 1 } );
		return FAILURE;
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $seqin;
	my $continue = 1;
	my @seq_data;
	my $stringfh_in = IO::String->new($sequence);
	try {
		$seqin = Bio::SeqIO->new( -fh => $stringfh_in, -format => 'fasta' );
		while ( my $seq_object = $seqin->next_seq ) {
			my $seq = $seq_object->seq // '';
			$seq =~ s/[\-\.\s]//gx;
			$seq = uc($seq);
			push @seq_data, { id => $seq_object->id, seq => $seq };
		}
	}
	catch {
		$self->print_bad_status( { message => q(Sequence is not in valid FASTA format.), navbar => 1 } );
		$continue = 0;    #Can't return from inside catch block
	};
	return FAILURE if !$continue;
	say q(<div id="results"><div class="box" id="resultspanel">)
	  . q(<div><span class="wait_icon fas fa-sync-alt fa-spin fa-4x" style="margin-right:0.5em"></span>)
	  . q(<span class="wait_message">Checking sequences - Please wait.</span></div>)
	  . q(<div id="progress"></div></div>)
	  . q(<noscript><div class="box statusbad"><p>Please enable Javascript in your browser</p></div></noscript></div>);
	my $prefix = BIGSdb::Utils::get_random();
	say $self->_get_polling_javascript($prefix);

	#Use double fork to prevent zombie processes on apache2-mpm-worker
	defined( my $kid = fork ) or $logger->error('cannot fork');
	if ($kid) {
		waitpid( $kid, 0 );
	} else {
		defined( my $grandkid = fork ) || $logger->error('Kid cannot fork');
		if ($grandkid) {
			CORE::exit(0);
		} else {
			open STDIN,  '<', '/dev/null' || $logger->error("Cannot detach STDIN: $!");
			open STDOUT, '>', '/dev/null' || $logger->error("Cannot detach STDOUT: $!");
			open STDERR, '>&STDOUT' || $logger->error("Cannot detach STDERR: $!");
			$self->_run_helper( $prefix, \@seq_data );
		}
		CORE::exit(0);
	}
	return SUCCESS;
}

sub _get_polling_javascript {
	my ( $self, $results_prefix ) = @_;
	my $status_file   = "/tmp/${results_prefix}_status.json";
	my $html_file     = "/tmp/${results_prefix}.html";
	my $max_poll_time = 10_000;
	my $error         = $self->print_bad_status(
		{
			message  => 'Could not find results file',
			detail   => 'Please try re-uploading sequences.',
			get_only => 1
		}
	);
	my $buffer = << "END";
<script>//<![CDATA[

var error_seen = 0;
\$(function () {	
	getResults(500);
});

function getResults(poll_time) {	
	\$.ajax({
		url: "$status_file",
		dataType: 'json',
		cache: false,
		success: function(data){
			if (data.status == 'complete'){	
				\$.get("$html_file", function(html){
					\$("div#results").html(html);
				});		
			} else if (data.status == 'running'){
				\$("div#progress").html('<p style="font-size:5em;color:#888;margin-left:1.5em;margin-top:1em">' 
				+ data.progress + '%</p>');
				// Wait and poll again - increase poll time by 0.5s each time.
				poll_time += 500;
				if (poll_time > $max_poll_time){
					poll_time = $max_poll_time;
				}
				setTimeout(function() { 
           	        getResults(poll_time); 
                }, poll_time);
 			} else {
				\$("div#results").html();
			}
		},
		error: function (){
			if (error_seen > 10){
				\$("div#results").html('$error');
				return;
			}
			error_seen++;
			setTimeout(function() { 
            	getResults(poll_time); 
            }, poll_time);           
		}
	});
}
//]]></script>
END
	return $buffer;
}

sub _run_helper {
	my ( $self, $prefix, $seq_data ) = @_;
	my $q         = $self->{'cgi'};
	my $set_id    = $self->get_set_id;
	my $check_obj = BIGSdb::Offline::BatchFASTASequenceCheck->new(
		{
			config_dir       => $self->{'config_dir'},
			lib_dir          => $self->{'lib_dir'},
			dbase_config_dir => $self->{'dbase_config_dir'},
			host             => $self->{'system'}->{'host'},
			port             => $self->{'system'}->{'port'},
			user             => $self->{'system'}->{'user'},
			password         => $self->{'system'}->{'password'},
			options          => {
				always_run        => 1,
				set_id            => $set_id,
				script_name       => $self->{'system'}->{'script_name'},
				locus             => $q->param('locus'),
				seq_data          => $seq_data,
				ignore_existing   => $q->param('ignore_existing') ? 1 : 0,
				complete_CDS      => $q->param('complete_CDS') ? 1 : 0,
				ignore_similarity => $q->param('ignore_similarity') ? 1 : 0,
				username          => $self->{'username'},
				status            => $q->param('status'),
				sender            => $q->param('sender')
			},
			instance => $self->{'instance'},
			logger   => $logger
		}
	);
	return $check_obj->run($prefix);
}

sub _upload {
	my ( $self, $upload_file ) = @_;
	my $q = $self->{'cgi'};
	if ( !-e $upload_file || -z $upload_file ) {
		$self->print_bad_status(
			{ message => q(Temporary upload file is not available. Cannot upload.), navbar => 1 } );
		return;
	}
	my $seqin = Bio::SeqIO->new( -file => $upload_file, -format => 'fasta' );
	my $sql =
	  $self->{'db'}->prepare( 'INSERT INTO sequences (locus,allele_id,sequence,status,date_entered,'
		  . 'datestamp,sender,curator) VALUES (?,?,?,?,?,?,?,?)' );
	my $submission_id = $q->param('submission_id');
	my $allele_submission =
	  $submission_id ? $self->{'submissionHandler'}->get_allele_submission($submission_id) : undef;
	my $sql_submission =
	  $self->{'db'}
	  ->prepare('UPDATE allele_submission_sequences SET (status,assigned_id)=(?,?) WHERE (submission_id,seq_id)=(?,?)');
	eval {
		while ( my $seq_object = $seqin->next_seq ) {
			$sql->execute( $q->param('locus'), $seq_object->id, $seq_object->seq, $q->param('status'), 'now', 'now',
				$q->param('sender'), $self->get_curator_id );
			if ( $allele_submission && $allele_submission->{'locus'} eq $q->param('locus') ) {
				my $submission_seqs = $allele_submission->{'seqs'};
				foreach my $seq (@$submission_seqs) {
					if ( uc( $seq->{'sequence'} ) eq uc( $seq_object->seq ) ) {
						$sql_submission->execute( 'assigned', $seq_object->id, $submission_id, $seq->{'seq_id'} );
					}
				}
			}
		}
	};
	if ($@) {
		$self->print_bad_status( { message => 'Upload failed!' } );
		$logger->error($@);
		$self->{'db'}->rollback;
		return;
	}
	my $detail;
	if ($submission_id) {
		my $url =
		    qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit&amp;)
		  . qq(submission_id=$submission_id&amp;curate=1);
		$detail = qq(Don't forget to <a href="$url">close the submission</a>!);
	}
	$self->print_good_status(
		{
			message       => q(Sequences added.),
			detail        => $detail,
			navbar        => 1,
			submission_id => $submission_id,
			more_url => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddFasta"
		}
	);
	$self->{'db'}->commit;
	$self->mark_locus_caches_stale( [ $q->param('locus') ] );
	$self->update_blast_caches;
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Batch add new allele sequence records (FASTA) - $desc";
}
1;
