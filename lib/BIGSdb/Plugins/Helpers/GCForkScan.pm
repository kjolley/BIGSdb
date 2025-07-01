#Written by Keith Jolley
#Copyright (c) 2017-2025, University of Oxford
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
package BIGSdb::Plugins::Helpers::GCForkScan;
use Parallel::ForkManager;
use BIGSdb::Plugins::Helpers::GCHelper;
use Log::Log4perl qw(get_logger :nowarn);
use strict;
use warnings;
use 5.010;

sub new {
	my ( $class, $params ) = @_;
	my $self = {};
	$self->{'config_dir'}       = $params->{'config_dir'};
	$self->{'lib_dir'}          = $params->{'lib_dir'};
	$self->{'dbase_config_dir'} = $params->{'dbase_config_dir'};
	$self->{'logger'}           = $params->{'logger'};
	$self->{'config'}           = $params->{'config'};
	$self->{'jm_params'}        = $params->{'job_manager_params'};
	bless( $self, $class );
	return $self;
}

sub _get_job_manager {
	my ($self) = @_;
	return BIGSdb::OfflineJobManager->new(
		{
			config_dir       => $self->{'config_dir'},
			dbase_config_dir => $self->{'dbase_config_dir'},
			system           => $self->{'system'},
			%{ $self->{'jm_params'} }
		}
	);
}

sub run {
	my ( $self, $params ) = @_;
	my $by_ref          = $params->{'reference_file'} ? 1 : 0;
	my $finish_progress = $params->{'finish_progress'} // ( $params->{'align'} ? 20 : 80 );
	if ( $params->{'threads'} && $params->{'threads'} > 1 ) {
		my $script;
		$script =
		  BIGSdb::Plugins::Helpers::GCHelper->new(    #Create script object to use methods to determine isolate list
			{
				config_dir       => $self->{'config_dir'},
				lib_dir          => $self->{'lib_dir'},
				dbase_config_dir => $self->{'dbase_config_dir'},
				logger           => $self->{'logger'},
				options          => { query_only => 1, always_run => 1, no_user_db_needed => 1, %$params },
				instance         => $params->{'database'},
				params           => $params->{'user_params'}
			}
		  );
		my $isolates  = $script->get_isolates;
		my $need_scan = [];
		my $no_scan   = [];
		if ($by_ref) {
			$need_scan = $isolates;
		} else {
			my $locus_list_table =
			  $script->{'datastore'}->create_temp_list_table_from_array( 'text', $params->{'loci'} );
			foreach my $isolate_id (@$isolates) {
				my $designated_locus_count = $script->{'datastore'}->run_query(
					'SELECT COUNT(DISTINCT(locus)) FROM allele_designations ad JOIN '
					  . "$locus_list_table l ON ad.locus=l.value WHERE ad.isolate_id=?",
					$isolate_id,
					{ cache => 'GCForkScan::locus_count' }
				);
				if ( $designated_locus_count == @{ $params->{'loci'} }
					|| ( !$params->{'rescan_missing'} && $designated_locus_count >= 0.5 * @{ $params->{'loci'} } ) )
				{
					push @$no_scan, $isolate_id;
				} else {
					push @$need_scan, $isolate_id;
				}
			}
		}
		undef $script;

		my $data     = {};
		my $new_seqs = {};

		my $scan_finish_progress = int( $finish_progress * @$no_scan / @$isolates );
		if (@$no_scan) {

			local $" = q(,);
			my $data_lookup_helper = BIGSdb::Plugins::Helpers::GCHelper->new(
				{
					config_dir       => $self->{'config_dir'},
					lib_dir          => $self->{'lib_dir'},
					dbase_config_dir => $self->{'dbase_config_dir'},
					logger           => $self->{'logger'},
					options          => {
						i                 => qq(@$no_scan),
						always_run        => 1,
						fast              => 1,
						global_new        => 1,
						no_user_db_needed => 1,
						job_manager       => $self->_get_job_manager,
						no_scan           => 1,
						update_progress   => 1,
						finish_progress   => $scan_finish_progress,
						%$params
					},
					instance    => $params->{'database'},
					user_params => $params->{'user_params'},
					locus_data  => $params->{'locus_data'}
				}
			);
			$data = $data_lookup_helper->get_results;
		}

		my $pm =
		  Parallel::ForkManager->new( $params->{'threads'}, $self->{'config'}->{'secure_tmp_dir'} );
		my $isolate_count = 0;

		if ( $params->{'user_genomes'} ) {
			my $id = -1;
			foreach ( keys %{ $params->{'user_genomes'} } ) {
				unshift @$isolates, $id;
				$id--;
			}
		}
		if (@$need_scan) {
			my $range = $finish_progress - $scan_finish_progress;
			$pm->run_on_finish(
				sub {
					my ( $pid, $exit_code, $ident, $exit_signal, $core_dump, $ret_data ) = @_;
					$data->{$_} = $ret_data->{'designations'}->{$_} foreach keys %{ $ret_data->{'designations'} };
					$new_seqs->{ $ret_data->{'isolate_id'} }->{$_} = $ret_data->{'local_new_seqs'}->{$_}
					  foreach keys %{ $ret_data->{'local_new_seqs'} };
					$isolate_count++;
					if ( $params->{'job_id'} ) {
						my $percent_complete = int( $scan_finish_progress + ( $isolate_count * $range ) / @$isolates );
						if ( $isolate_count < @$isolates ) {
							my $next_id     = @$no_scan + $isolate_count + 1;
							my $job_manager = $self->_get_job_manager;
							$job_manager->update_job_status( $params->{'job_id'},
								{ percent_complete => $percent_complete, stage => "Scanning isolate record $next_id" }
							);
						}
					}
				}
			);
			foreach my $isolate_id (@$need_scan) {
				last if $self->_is_job_cancelled( $params->{'job_id'} );
				$pm->start and next;
				my $scan_helper = BIGSdb::Plugins::Helpers::GCHelper->new(
					{
						config_dir       => $self->{'config_dir'},
						lib_dir          => $self->{'lib_dir'},
						dbase_config_dir => $self->{'dbase_config_dir'},
						logger           => $self->{'logger'},
						options  => { i => $isolate_id, always_run => 1, fast => 1, no_user_db_needed => 1, %$params },
						instance => $params->{'database'},
						params   => $params->{'user_params'},
						locus_data => $params->{'locus_data'}
					}
				);
				my $isolate_data   = $scan_helper->get_results;
				my $local_new_seqs = $scan_helper->get_new_sequences;
				$pm->finish( 0,
					{ designations => $isolate_data, local_new_seqs => $local_new_seqs, isolate_id => $isolate_id } );
			}
			$pm->wait_all_children;
			$self->_correct_new_designations( $data, $new_seqs, $by_ref );

		}
		if ($by_ref) {
			$self->_rename_ref_designations($data);
		}
		return $data;
	}

	#Run non-threaded job
	my $scan_helper = BIGSdb::Plugins::Helpers::GCHelper->new(
		{
			config_dir       => $self->{'config_dir'},
			lib_dir          => $self->{'lib_dir'},
			dbase_config_dir => $self->{'dbase_config_dir'},
			logger           => $self->{'logger'},
			options          => {
				always_run        => 1,
				fast              => 1,
				global_new        => 1,
				no_user_db_needed => 1,
				job_manager       => $self->_get_job_manager,
				update_progress   => 1,
				finish_progress   => $finish_progress,
				%$params
			},
			instance    => $params->{'database'},
			user_params => $params->{'user_params'},
			locus_data  => $params->{'locus_data'}

		}
	);
	my $batch_data = $scan_helper->get_results;
	my $new_seqs   = $scan_helper->get_new_sequences;
	if ($by_ref) {
		$self->_rename_ref_designations($batch_data);
	}
	return $batch_data;
}

sub _is_job_cancelled {
	my ( $self, $job_id ) = @_;
	my $signal_file = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}.CANCEL";
	return 1 if -e $signal_file;
	return;
}

sub _correct_new_designations {
	my ( $self, $data, $new_seqs, $by_ref ) = @_;
	my @isolates;
	my %loci;
	foreach my $isolate_id ( sort { $a <=> $b } keys %$new_seqs ) {
		push @isolates, $isolate_id;
		foreach my $locus ( sort { $a cmp $b } keys %{ $new_seqs->{$isolate_id}->{'allele_lookup'} } ) {
			$loci{$locus} = 1;
		}
	}
	my @loci = sort keys %loci;
	foreach my $locus (@loci) {
		my $i = 1;
		my %hash_names;
		foreach my $isolate_id (@isolates) {
			foreach my $md5_hash ( keys %{ $new_seqs->{$isolate_id}->{'allele_lookup'}->{$locus} } ) {
				if ( !$hash_names{$md5_hash} ) {
					$hash_names{$md5_hash} = $by_ref ? ( $i + 1 ) : "new#$i";
					$i++;
				}
				$data->{$isolate_id}->{'designations'}->{$locus} = $hash_names{$md5_hash};
			}
		}
	}

	return;
}

sub _rename_ref_designations {
	my ( $self, $data ) = @_;
	foreach my $isolate_id ( keys %$data ) {
		foreach my $locus ( keys %{ $data->{$isolate_id}->{'designations'} } ) {
			$data->{$isolate_id}->{'designations'}->{$locus} =~ s/^new\#//x;
		}
	}
	return;
}
1;
