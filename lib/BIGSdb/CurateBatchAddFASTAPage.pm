#Written by Keith Jolley
#Copyright (c) 2013-2017, University of Oxford
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
use Log::Log4perl qw(get_logger);
use Error qw(:try);
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
			say q(<div class="box" id="statusbad"><p>Your user account is not allowed to )
			  . qq(add $locus alleles to the database.</p></div>);
			return;
		}
		my @missing;
		foreach my $field (qw (locus status sender sequence)) {
			push @missing, $field if !$q->param($field);
		}
		if (@missing) {
			local $" = q(, );
			say q(<div class="box" id="statusbad"><p>Please complete the form. )
			  . qq(The following fields are missing: @missing</p></div>);
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
		say q(<div class="box" id="statusbad"><p>Sender is required and must exist in the users table.</p></div>);
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
	catch Bio::Root::Exception with {
		say q(<div class="box" id="statusbad"><p>Sequence is not in valid FASTA format.</p></div>);
		$continue = 0;    #Can't return from inside catch block
	};
	return FAILURE if !$continue;
	say q(<div class="box" id="resultstable">);
	say q(<h2>Sequence check</h2>);
	say q(<div class="scrollable">);
	say q(<table class="resultstable" style="float:left;margin-right:1em">)
	  . q(<tr><th>Original designation</th><th>Allele id</th><th>Status</th></tr>);
	my $td      = 1;
	my $temp    = BIGSdb::Utils::get_random();
	my $outfile = "$self->{'config'}->{'secure_tmp_dir'}/$temp.fas";
	local $| = 1;

	foreach my $data (@seq_data) {
		my ( $status, $id, $message ) = $self->_check_sequence( $locus, $data );
		my $class = $status == SUCCESS ? 'statusgood' : 'statusbad';
		say qq(<tr class="td$td"><td>$data->{'id'}</td><td>$id</td><td class="$class">$message</td></tr>);
		$td = $td == 1 ? 2 : 1;
		if ( $status == SUCCESS ) {
			open( my $fh, '>>', $outfile ) || $logger->error("Can't open $outfile for writing");
			say $fh ">$id";
			say $fh $data->{'seq'};
			close $fh;
		}
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
	}
	say q(</table>);
	if ( -e $outfile && !-z $outfile ) {
		say $q->start_form;
		$self->print_action_fieldset( { submit_label => 'Upload valid sequences', no_reset => 1 } );
		say $q->hidden($_) foreach qw(db page locus status sender submission_id);
		say $q->hidden( 'upload_file', $outfile );
		say $q->end_form;
	} else {
		say q(<fieldset style="float:left"><legend>Sequence upload</legend>);
		say q(<p class="statusbad">No valid sequences to upload.</p>);
		say q(</fieldset>);
	}
	say q(</div></div>);
	return SUCCESS;
}

sub _check_sequence {
	my ( $self, $locus, $data ) = @_;
	my $q = $self->{'cgi'};
	if ( !$self->{'locus_info'} ) {
		$self->{'locus_info'} = $self->{'datastore'}->get_locus_info($locus);
	}
	my $allele_id;
	if ( $self->{'locus_info'}->{'allele_id_format'} eq 'integer' && $q->param('use_next_id') ) {
		if ( !defined $self->{'last_id'} ) {
			$allele_id = $self->{'datastore'}->get_next_allele_id($locus);
			$self->{'last_id'} = $allele_id;
		} else {
			$allele_id = $self->{'last_id'};
			my ( $exists, $retired );
			do {
				$allele_id++;
				$exists = $self->{'datastore'}->sequence_exists( $locus, $allele_id );
				$retired = $self->{'datastore'}->is_sequence_retired( $locus, $allele_id );
			} while $exists || $retired;
			$self->{'last_id'} = $allele_id;
		}
	} else {
		$allele_id = $data->{'id'};
	}
	my $msg = $self->_check_allele_id( $locus, $allele_id );
	return ( FAILURE, $allele_id, $msg ) if $msg;
	$msg = $self->_check_sequence_field( \$data->{'seq'} );
	return ( FAILURE, $allele_id, $msg ) if $msg;
	$msg = $self->_check_sequence_exists( $locus, \$data->{'seq'} );
	return ( FAILURE, $allele_id, $msg ) if $msg;
	$msg = $self->_check_sequence_similarity( $locus, \$data->{'seq'} );
	return ( FAILURE, $allele_id, $msg ) if $msg;

	#Check if allele is complete coding sequence
	if ( $self->{'locus_info'}->{'data_type'} eq 'DNA' && $q->param('complete_CDS') ) {
		my $cds_check = BIGSdb::Utils::is_complete_cds( $data->{'seq'} );
		if ( !$cds_check->{'cds'} ) {
			return ( FAILURE, $allele_id, ucfirst( $cds_check->{'err'} ) );
		}
	}
	$self->{'used_alleles'}->{$allele_id} = 1;
	$self->{'cache'}->{'seqs'}->{ $data->{'seq'} } = $allele_id;
	return ( SUCCESS, $allele_id, 'OK' );
}

sub _check_allele_id {
	my ( $self, $locus, $allele_id ) = @_;

	#Check allele_id is correct format
	if ( $self->{'locus_info'}->{'allele_id_format'} eq 'integer' && !BIGSdb::Utils::is_int($allele_id) ) {
		return 'Allele id is not an integer.';
	}
	if ( $self->{'locus_info'}->{'allele_id_regex'} && $allele_id !~ /$self->{'locus_info'}->{'allele_id_regex'}/x ) {
		return 'Allele id does not conform to required format.';
	}

	#Check id doesn't already exist and has not been retired.
	if ( $self->{'datastore'}->sequence_exists( $locus, $allele_id ) ) {
		return 'Allele id already exists.';
	}
	if ( $self->{'datastore'}->is_sequence_retired( $locus, $allele_id ) ) {
		return 'Allele id has been retired.';
	}

	#Check id isn't already submitted in this submission
	if ( $self->{'used_alleles'}->{$allele_id} ) {
		return 'Allele id already submitted in this upload.';
	}
	return;
}

sub _check_sequence_field {
	my ( $self, $seq_ref ) = @_;

	#Check invalid characters
	if (
		$self->{'locus_info'}->{'data_type'} eq 'DNA'
		&& !BIGSdb::Utils::is_valid_DNA(
			$$seq_ref, { diploid => ( ( $self->{'system'}->{'diploid'} // '' ) eq 'yes' ? 1 : 0 ) }
		)
	  )
	{
		my @chars = ( $self->{'system'}->{'diploid'} // '' ) eq 'yes' ? DIPLOID : HAPLOID;
		local $" = '|';
		return "Sequence contains non nucleotide (@chars) characters.";
	} elsif ( $self->{'locus_info'}->{'data_type'} eq 'peptide' && $$seq_ref =~ /[^GPAVLIMCFYWHKRQNEDST\*]/x ) {
		return 'Sequence contains non AA characters.';
	}

	#Check length
	my $length = length $$seq_ref;
	my $units =
	  $self->{'locus_info'}->{'data_type'} && $self->{'locus_info'}->{'data_type'} eq 'DNA' ? 'bp' : 'residues';
	if (   !$self->{'locus_info'}->{'length_varies'}
		&& defined $self->{'locus_info'}->{'length'}
		&& $self->{'locus_info'}->{'length'} != $length )
	{
		return "Sequence is $length $units long but this locus is set as a standard "
		  . "length of $self->{'locus_info'}->{'length'} $units.";
	} elsif ( $self->{'locus_info'}->{'min_length'} && $length < $self->{'locus_info'}->{'min_length'} ) {
		return "Sequence is $length $units long but this locus is set with a minimum "
		  . "length of $self->{'locus_info'}->{'min_length'} $units.";
	} elsif ( $self->{'locus_info'}->{'max_length'} && $length > $self->{'locus_info'}->{'max_length'} ) {
		return "Sequence is $length $units long but this locus is set with a maximum "
		  . "length of $self->{'locus_info'}->{'max_length'} $units.";
	}
	return;
}

sub _check_sequence_exists {
	my ( $self, $locus, $seq_ref ) = @_;

	#Check seq doesn't already exist
	my $exists =
	  $self->{'datastore'}
	  ->run_query( 'SELECT allele_id FROM sequences WHERE (locus,sequence)=(?,?)', [ $locus, $$seq_ref ] );
	if ( defined $exists ) {
		return "Sequence has already been defined as $locus-$exists.";
	}

	#Check sequence isn't already submitted in this submission
	my $seq_hash = Digest::MD5::md5_hex($$seq_ref);
	if ( $self->{'used_seq'}->{$seq_hash} ) {
		return 'Sequence already submitted in this upload.';
	}
	$self->{'used_seq'}->{$seq_hash} = 1;
	return;
}

sub _check_sequence_similarity {
	my ( $self, $locus, $seq_ref ) = @_;
	my $q = $self->{'cgi'};

	#Check allele is sufficiently similar to existing alleles
	return
	  if !($self->{'locus_info'}->{'data_type'} eq 'DNA'
		&& !$q->param('ignore_similarity')
		&& $self->{'datastore'}->sequences_exist($locus) );
	my $check = $self->{'datastore'}->check_sequence_similarity( $locus, $seq_ref );
	if ( !$check->{'similar'} ) {
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		my $id_threshold =
		  BIGSdb::Utils::is_float( $locus_info->{'id_check_threshold'} )
		  ? $locus_info->{'id_check_threshold'}
		  : IDENTITY_THRESHOLD;
		my $type = $locus_info->{'id_check_type_alleles'} ? q( type) : q();
		return qq[Sequence is too dissimilar to existing$type alleles (less than $id_threshold% identical or an ]
		  . q[alignment of less than 90% its length). ];
	} elsif ( $check->{'subsequence_of'} ) {
		return qq[Sequence is a sub-sequence of allele-$check->{'subsequence_of'}, i.e. it is identical over its ]
		  . q[complete length but is shorter.];
	} elsif ( $check->{'supersequence_of'} ) {
		return qq[Sequence is a super-sequence of allele $check->{'supersequence_of'}, i.e. it is identical over the ]
		  . q[complete length of this allele but is longer. ];
	}
	foreach my $test_seq ( keys %{ $self->{'cache'}->{'seqs'} } ) {
		if ( $$seq_ref =~ /$test_seq/x ) {
			return qq(Sequence is a super-sequence of allele $self->{'cache'}->{'seqs'}->{$test_seq} )
			  . q(submitted as part of this batch.);
		}
		if ( $test_seq =~ /$$seq_ref/x ) {
			return qq(Sequence is a sub-sequence of allele $self->{'cache'}->{'seqs'}->{$test_seq} )
			  . q(submitted as part of this batch.);
		}
	}
	return;
}

sub _upload {
	my ( $self, $upload_file ) = @_;
	my $q = $self->{'cgi'};
	if ( !-e $upload_file || -z $upload_file ) {
		say q(<div class="box" id="statusbad"><p>Temporary upload file is not available.  Cannot upload.</p></div>);
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
		say qq(<div class="box" id="statusbad"><p>Upload failed. $@</p></div>);
		$self->{'db'}->rollback;
		return;
	}
	say q(<div class="box" id="resultsheader"><p>Upload succeeded.</p><p>);
	my $more = MORE;
	$self->print_return_to_submission;
	$self->print_home_link;
	say qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddFasta" )
	  . qq(title="Upload more" style="margin-right:1em">$more</a></p>);
	say q(</div>);
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
