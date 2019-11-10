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
package BIGSdb::GCAligner;
use BIGSdb::GCHelper;
use BIGSdb::Constants qw(:limits);
use Parallel::ForkManager;
use Log::Log4perl qw(get_logger :nowarn);
use strict;
use warnings;
use 5.010;

sub new {
	my ( $class, $params ) = @_;
	my $self = {};
	foreach my $param (
		qw(config_dir lib_dir dbase_config_dir logger config job_id ids
		scan_data no_output params threads isolate_names name_map clean_loci)
	  )
	{
		$self->{$param} = $params->{$param};
	}
	$self->{'jm_params'} = $params->{'job_manager_params'};
	bless( $self, $class );
	return $self;
}

sub _get_job_manager {
	my ($self) = @_;
	return BIGSdb::OfflineJobManager->new(
		{
			config_dir => $self->{'config_dir'},
			%{ $self->{'jm_params'} }
		}
	);
}

sub run {
	my ( $self, $params ) = @_;
	my $threads = BIGSdb::Utils::is_int( $self->{'threads'} ) ? $self->{'threads'} : 1;
	my $pm =
	  Parallel::ForkManager->new( $threads, $self->{'config'}->{'secure_tmp_dir'} );
	my $locus_count            = 0;
	my $start_progress         = 20;
	my $progress_for_alignment = 50;
	my $job_id                 = $self->{'job_id'};
	my $scan_data              = $self->{'scan_data'};
	my $temp                   = BIGSdb::Utils::get_random();
	my $ids                    = $self->{'ids'};
	my $loci                   = $self->{'params'}->{'align_all'} ? $scan_data->{'loci'} : $scan_data->{'variable'};
	my @locus_queue;
	my %finished;
	my $locus_details = {};
	$pm->run_on_finish(
		sub {
			my ( $pid, $exit_code, $ident, $exit_signal, $core_dump, $ret_data ) = @_;

			#If this locus is the first in the queue then process it and any sequential
			#loci that are available.
			my $current_locus_index = $ret_data->{'locus_index'};
			$locus_details->{ $loci->[$current_locus_index] } = $ret_data;
			$finished{$current_locus_index} = 1;
			return if $current_locus_index > $locus_queue[0];
			while ( @locus_queue && $finished{ $locus_queue[0] } ) {
				$locus_count++;
				my $percent_complete = $start_progress + int( ( $locus_count * $progress_for_alignment ) / @$loci );
				my $processed = shift @locus_queue;
				if ( $finished{$processed} ) {
					$self->{'distances'}->{ $loci->[$processed] } = $self->_process_alignment(
						$ids, $loci->[$processed],
						$locus_details->{ $loci->[$processed] }->{'aligned_file'},
						$locus_details->{ $loci->[$processed] }->{'core_locus'},
						$self->{'params'}->{'align_stats'}
					);
				}
				my $job_manager = $self->_get_job_manager;
				my $stage =
				  $ret_data->{'locus_index'} < @$loci - 1
				  ? q(Aligning ) . $loci->[ $current_locus_index + 1 ]
				  : q();
				$job_manager->update_job_status( $job_id, { percent_complete => $percent_complete, stage => $stage } );
			}
		}
	);
	foreach my $i ( 0 .. @$loci - 1 ) {
		last if $self->_is_job_cancelled($job_id);
		push @locus_queue, $i;
		$pm->start and next;
		my ( $aligned_file, $core_locus ) = $self->_run_alignment( $params, $temp, $loci->[$i] );
		$pm->finish( 0, { locus_index => $i, aligned_file => $aligned_file, core_locus => $core_locus } );
	}
	$pm->wait_all_children;
	return;
}

sub get_distances {
	my ($self) = @_;
	return $self->{'distances'};
}

sub _process_alignment {
	my ( $self, $ids, $locus, $aligned_out, $core_locus, $infoalign ) = @_;
	my $job_id           = $self->{'job_id'};
	my $xmfa_out         = "$self->{'config'}->{'tmp_dir'}/$job_id.xmfa";
	my $core_xmfa_out    = "$self->{'config'}->{'tmp_dir'}/${job_id}_core.xmfa";
	my $align_file       = "$self->{'config'}->{'tmp_dir'}/$job_id.align";
	my $align_stats_file = "$self->{'config'}->{'tmp_dir'}/$job_id.align_stats";
	state $xmfa_start = 1;
	state $xmfa_end   = 1;
	my $distance;

	if ( -e $aligned_out ) {
		my $align = Bio::AlignIO->new( -format => 'clustalw', -file => $aligned_out )->next_aln;
		my ( %id_has_seq, $seq_length );
		my $xmfa_buffer;
		my $clean_locus = $self->{'clean_loci'}->{$locus}->{'no_common'};
		foreach my $seq ( $align->each_seq ) {
			$xmfa_end = $xmfa_start + $seq->length - 1;
			my $id = $seq->id;
			$xmfa_buffer .= ">$self->{'isolate_names'}->{$id}:$xmfa_start-$xmfa_end + $clean_locus\n";
			my $sequence = BIGSdb::Utils::break_line( $seq->seq, 60 );
			$xmfa_buffer .= "$sequence\n";
			$id_has_seq{$id} = 1;
			$seq_length = $seq->length if !$seq_length;
		}
		my $missing_seq = BIGSdb::Utils::break_line( ( '-' x $seq_length ), 60 );
		foreach my $id (@$ids) {
			my $identifier = $self->{'name_map'}->{$id} // $id;
			next if $id_has_seq{$identifier};
			$xmfa_buffer .=
			  ">$self->{'isolate_names'}->{$identifier}:$xmfa_start-$xmfa_end + $clean_locus\n$missing_seq\n";
		}
		$xmfa_buffer .= '=';
		open( my $fh_xmfa, '>>:encoding(utf8)', $xmfa_out )
		  or $self->{'logger'}->error("Cannot open output file $xmfa_out for appending");
		say $fh_xmfa $xmfa_buffer if $xmfa_buffer;
		close $fh_xmfa;
		if ($core_locus) {
			open( my $fh_core_xmfa, '>>:encoding(utf8)', $core_xmfa_out )
			  or $self->{'logger'}->error("Can't open output file $core_xmfa_out for appending");
			say $fh_core_xmfa $xmfa_buffer if $xmfa_buffer;
			close $fh_core_xmfa;
		}
		$xmfa_start = $xmfa_end + 1;
		open( my $align_fh, '>>:encoding(utf8)', $align_file )
		  || $self->{'logger'}->error("Can't open $align_file for appending");
		my $heading_locus = $self->{'clean_loci'}->{$locus}->{'common'};
		say $align_fh "$heading_locus";
		say $align_fh '-' x ( length $heading_locus ) . "\n";
		close $align_fh;
		BIGSdb::Utils::append( $aligned_out, $align_file, { blank_after => 1 } );
		$distance = $self->_run_infoalign(
			{
				alignment        => $aligned_out,
				align_stats_file => $align_stats_file,
				locus            => $locus
			}
		) if $infoalign;
		unlink $aligned_out;
	}
	return $distance;
}

sub _run_alignment {
	my ( $self, $params, $temp, $locus ) = @_;
	my $scan_data = $self->{'scan_data'};
	( my $escaped_locus = $locus ) =~ s/[\/\|\']/_/gx;
	$escaped_locus =~ tr/ /_/;
	my $fasta_file  = "$self->{'config'}->{'secure_tmp_dir'}/${temp}_$escaped_locus.fasta";
	my $aligned_out = "$self->{'config'}->{'secure_tmp_dir'}/${temp}_$escaped_locus.aligned";
	my $seq_count   = 0;
	open( my $fasta_fh, '>:encoding(utf8)', $fasta_file )
	  || $self->{'logger'}->error("Cannot open $fasta_file for writing");
	my $names        = {};
	my $ids_to_align = [];

	if ( $self->{'by_ref'} && $params->{'include_ref'} ) {
		push @$ids_to_align, 'ref';
		$names->{'ref'} = 'ref';
		say $fasta_fh '>ref';
		say $fasta_fh $scan_data->{'locus_data'}->{$locus}->{'sequence'};
	}
	my $ids = $self->{'ids'};
	foreach my $id (@$ids) {
		push @$ids_to_align, $id;
		my $identifier = $self->{'name_map'}->{$id} // $id;
		my $seq = $scan_data->{'isolate_data'}->{$id}->{'sequences'}->{$locus};
		if ($seq) {
			$seq_count++;
			say $fasta_fh ">$identifier";
			say $fasta_fh $seq;
		}
	}
	close $fasta_fh;
	my $core_threshold =
	  BIGSdb::Utils::is_int( $params->{'core_threshold'} ) ? $params->{'core_threshold'} : 100;
	my $core_locus = ( $scan_data->{'frequency'}->{$locus} * 100 / @$ids ) >= $core_threshold ? 1 : 0;
	if ( $seq_count <= 1 ) {
		unlink $fasta_file;
		return ( $aligned_out, $core_locus );
	}
	if (   $self->{'params'}->{'aligner'} eq 'MAFFT'
		&& $self->{'config'}->{'mafft_path'}
		&& -e $fasta_file
		&& -s $fasta_file )
	{
		my $threads =
		  BIGSdb::Utils::is_int( $self->{'config'}->{'mafft_threads'} ) ? $self->{'config'}->{'mafft_threads'} : 1;
		system( "$self->{'config'}->{'mafft_path'} --thread $threads --quiet "
			  . "--preservecase --clustalout $fasta_file > $aligned_out" );
	} elsif ( $self->{'params'}->{'aligner'} eq 'MUSCLE'
		&& $self->{'config'}->{'muscle_path'}
		&& -e $fasta_file
		&& -s $fasta_file )
	{
		my $max_mb = $self->{'config'}->{'max_muscle_mb'} // MAX_MUSCLE_MB;
		system( $self->{'config'}->{'muscle_path'},
			-in    => $fasta_file,
			-out   => $aligned_out,
			-maxmb => $max_mb,
			'-quiet', '-clwstrict'
		);
	} else {
		$self->{'logger'}->error('No aligner selected');
	}
	unlink $fasta_file;
	return ( $aligned_out, $core_locus );
}

#Returns mean distance
sub _run_infoalign {
	my ( $self, $args ) = @_;
	my ( $alignment, $align_stats_file, $locus ) = @{$args}{qw(alignment align_stats_file locus)};
	if ( -e "$self->{'config'}->{'emboss_path'}/infoalign" ) {
		my $prefix  = BIGSdb::Utils::get_random();
		my $outfile = "$self->{'config'}->{'secure_tmp_dir'}/$prefix.infoalign";
		system( "$self->{'config'}->{'emboss_path'}/infoalign -sequence $alignment -outfile $outfile -nousa "
			  . '-nosimcount -noweight -nodescription 2> /dev/null' );
		open( my $fh_stats, '>>', $align_stats_file )
		  or $self->{'logger'}->error("Cannot open output file $align_stats_file for appending");
		my $heading_locus = $self->{'clean_loci'}->{$locus}->{'common'};
		print $fh_stats "$heading_locus\n";
		print $fh_stats '-' x ( length $heading_locus ) . "\n\n";
		close $fh_stats;

		if ( -e $outfile ) {
			BIGSdb::Utils::append( $outfile, $align_stats_file, { blank_after => 1 } );
			open( my $fh, '<', $outfile )
			  or $self->{'logger'}->error("Cannot open alignment stats file file $outfile for reading");
			my $row        = 0;
			my $total_diff = 0;
			while (<$fh>) {
				next if /^\#/x;
				my @values = split /\s+/x;
				my $diff   = $values[7];     # % difference from consensus
				$total_diff += $diff;
				$row++;
			}
			my $mean_distance = $total_diff / ( $row * 100 );
			close $fh;
			unlink $outfile;
			return $mean_distance;
		}
	}
	return;
}

sub _is_job_cancelled {
	my ( $self, $job_id ) = @_;
	my $signal_file = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}.CANCEL";
	return 1 if -e $signal_file;
	return;
}
1;
