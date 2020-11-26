#Written by Keith Jolley
#Copyright (c) 2020, University of Oxford
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
package BIGSdb::Plugins::Helpers::SpeciesIDFork;
use strict;
use warnings;
use 5.010;
use Parallel::ForkManager;
use BIGSdb::Plugins::Helpers::SpeciesID;
use constant MAX_THREADS => 4;

sub new {
	my ( $class, $params ) = @_;
	my $self = {};
	$self->{'config_dir'}       = $params->{'config_dir'};
	$self->{'lib_dir'}          = $params->{'lib_dir'};
	$self->{'dbase_config_dir'} = $params->{'dbase_config_dir'};
	$self->{'logger'}           = $params->{'logger'};
	$self->{'config'}           = $params->{'config'};
	$self->{'instance'}         = $params->{'instance'};
	$self->{'job_id'}           = $params->{'options'}->{'job_id'};
	$self->{'threads'}          = $params->{'options'}->{'threads'};
	$self->{'scan_genome'}      = $params->{'options'}->{'scan_genome'};
	bless( $self, $class );
	return $self;
}

sub run {
	my ( $self, $ids ) = @_;
	my $threads = $self->{'threads'} // MAX_THREADS;
	my $pm      = Parallel::ForkManager->new($threads);
	my $results = {};
	$pm->run_on_finish(
		sub {
			my ( $pid, $exit_code, $ident, $exit_signal, $core_dump, $ret_data ) = @_;
			$results->{ $ret_data->{'values'}->{'isolate_id'} } = $ret_data;
		}
	);
	foreach my $isolate_id (@$ids) {

		# Forks and returns the pid for the child:
		my $pid = $pm->start and next;
		my $id_obj = BIGSdb::Plugins::Helpers::SpeciesID->new(
			{
				config_dir       => $self->{'config_dir'},
				lib_dir          => $self->{'lib_dir'},
				dbase_config_dir => $self->{'dbase_config_dir'},
				host             => $self->{'system'}->{'host'},
				port             => $self->{'system'}->{'port'},
				user             => $self->{'system'}->{'user'},
				password         => $self->{'system'}->{'password'},
				options          => {
					always_run           => 1,
					throw_busy_exception => 0,
					job_id               => $self->{'job_id'},
					scan_genome          => $self->{'scan_genome'}
				},
				instance => $self->{'instance'},
				logger   => $self->{'logger'}
			}
		);
		my $result = $id_obj->run($isolate_id);
		$pm->finish( 0, $result );    # Terminates the child process
	}
	$pm->wait_all_children;
	return $results;
}
1;
