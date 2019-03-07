#Written by Keith Jolley
#Copyright (c) 2019, University of Oxford
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
package BIGSdb::Offline::BatchFASTASequenceCheck;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Offline::Script BIGSdb::CurateAddPage);
use constant SUCCESS => 1;
use constant FAILURE => 2;
use BIGSdb::Constants qw(:interface SEQ_STATUS HAPLOID DIPLOID IDENTITY_THRESHOLD);
my $logger;

sub run {
	my ( $self, $prefix ) = @_;
	$logger = $self->{'logger'};
	my $locus    = $self->{'options'}->{'locus'};
	my $seq_data = $self->{'options'}->{'seq_data'};
	$self->{'system'}->{'script_name'} = $self->{'options'}->{'script_name'};
		my $status_file = qq($self->{'config'}->{'tmp_dir'}/${prefix}_status.json);
	my $html_file   = qq($prefix.html);
	my $full_path   = qq($self->{'config'}->{'tmp_dir'}/$html_file);
	$self->_update_status_file( $status_file, 'running', 0 );
	my $q = $self->{'cgi'};
	my $buffer= q(<div class="box" id="resultstable">);
	$buffer.= q(<h2>Sequence check</h2>);
	$buffer.=  q(<div class="scrollable">);
	my $clean_locus = $self->clean_locus($locus);
	$buffer.=  qq(<p><b>Locus: </b>$clean_locus</p>);
	$buffer.=  q(<table class="resultstable" style="float:left;margin-right:1em">)
	  . q(<tr><th>Original designation</th><th>Allele id</th><th>Status</th></tr>);
	my $td      = 1;
#	my $temp    = BIGSdb::Utils::get_random();
	my $outfile = "$self->{'config'}->{'secure_tmp_dir'}/$prefix.fas";
	local $| = 1;
	my $i = 0;

	foreach my $data (@$seq_data) {
		my $progress = int( 100 * $i / @$seq_data );
		$self->_update_status_file( $status_file, 'running', $progress );
		$i++;
		my ( $status, $id, $message ) = $self->_check_sequence( $locus, $data );
		my $class = $status == SUCCESS ? 'statusgood' : 'statusbad';
		$buffer.=  qq(<tr class="td$td"><td>$data->{'id'}</td><td>$id</td><td class="$class">$message</td></tr>);
		$td = $td == 1 ? 2 : 1;
		if ( $status == SUCCESS ) {
			open( my $fh, '>>', $outfile ) || $logger->error("Cannot open $outfile for writing");
			say $fh ">$id";
			say $fh $data->{'seq'};
			close $fh;
		}

	}
	$self->_update_status_file( $status_file, 'complete', 100 );
	$buffer.=  q(</table>);
	if ( -e $outfile && !-z $outfile ) {
		$buffer.=  $q->start_form;
		$buffer.= $self->print_action_fieldset( { submit_label => 'Upload valid sequences', no_reset => 1,get_only=>1 } );
		$buffer.=  $q->hidden($_) foreach qw(db page locus status sender submission_id);
		$buffer.=  $q->hidden( 'upload_file', $outfile );
		$buffer.=  $q->end_form;
	} else {
		$buffer.=  q(<fieldset style="float:left"><legend>Sequence upload</legend>);
		$buffer.=  q(<p class="statusbad">No valid sequences to upload.</p>);
		$buffer.=  q(</fieldset>);
	}
	$buffer.=  q(</div></div>);
	open (my $fh, '>:encoding(utf8)', $full_path) || $logger->error("Cannot open $html_file for writing");
	say $fh $buffer;
	close $fh;
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
	  ->run_query( 'SELECT allele_id FROM sequences WHERE (locus,md5(sequence))=(?,md5(?))', [ $locus, $$seq_ref ] );
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
	my $check = $self->check_sequence_similarity( $locus, $seq_ref );
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

sub _update_status_file {
	my ( $self, $status_file, $status, $progress ) = @_;
	open( my $fh, '>', $status_file )
	  || $self->{'logger'}->error("Cannot touch $status_file");
	say $fh qq({"status":"$status","progress":$progress});
	close $fh;
	return;
}
1;
