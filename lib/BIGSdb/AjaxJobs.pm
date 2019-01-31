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
package BIGSdb::AjaxJobs;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use JSON;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant DEFAULT_TIME => 60 * 12;    #12h

sub initiate {
	my ($self) = @_;
	$self->{'type'}    = 'text';
	$self->{'noCache'} = 1;
	return;
}

sub print_content {
	my ($self)  = @_;
	my $q       = $self->{'cgi'};
	if ($q->param('summary')){
		$self->_summary_stats;
		return;
	}
	my $minutes = $q->param('minutes');
	my $time = $minutes // DEFAULT_TIME;
	if ( !BIGSdb::Utils::is_int($time) ) {
		$logger->error('Invalid time passed - should be an integer (minutes)');
		$time = DEFAULT_TIME;
	}
	my $temporal_data   = $self->{'jobManager'}->get_job_temporal_data($time);
	my $times           = {};
	my $begin_time      = $self->{'jobManager'}->get_period_timestamp($time);
	my $initial_queued  = 0;
	my $initial_running = 0;
	foreach my $t (@$temporal_data) {
		if ( $t->{'submit_time'} lt $begin_time ) {
			if ( !$t->{'start_time'} || $t->{'start_time'} gt $begin_time ) {
				$initial_queued++;
			} else {
				$initial_running++;
			}
			$times->{ $self->_trimmed_time( $t->{'stop_time'} ) }->{'stop'}++ if $t->{'stop_time'};
		} else {
			$times->{ $self->_trimmed_time( $t->{'submit_time'} ) }->{'submit'}++;
			$times->{ $self->_trimmed_time( $t->{'start_time'} ) }->{'start'}++ if $t->{'start_time'};
			$times->{ $self->_trimmed_time( $t->{'stop_time'} ) }->{'stop'}++   if $t->{'stop_time'};
		}
	}
	my $status =
	  [ { time => $self->_trimmed_time($begin_time), queued => $initial_queued, running => $initial_running } ];
	my $queued  = $initial_queued;
	my $running = $initial_running;
	foreach my $time ( sort keys %$times ) {
		if ( $times->{$time}->{'submit'} ) {
			$queued += $times->{$time}->{'submit'};
		}
		if ( $times->{$time}->{'start'} ) {
			$queued -= $times->{$time}->{'start'};
			$running += $times->{$time}->{'start'};
		}
		if ( $times->{$time}->{'stop'} ) {
			$running -= $times->{$time}->{'stop'};
		}
		push @$status, { time => $time, queued => $queued, running => $running };
	}
	my $now = $self->_trimmed_time( $self->{'jobManager'}->get_period_timestamp(0) );
	push @$status, { time => $now, queued => $status->[-1]->{'queued'}, running => $status->[-1]->{'running'} };
	my $format = $q->param('format') // 'json';
	if ( $format eq 'json' ) {
		say encode_json($status);
	} else {
		say qq(time\tqueued\trunning);
		say qq($_->{'time'}\t$_->{'queued'}\t$_->{'running'}) foreach @$status;
	}
	return;
}

sub _trimmed_time {
	my ( $self, $time ) = @_;
	return substr( $time, 0, 19 );
}

sub _summary_stats {
	my ($self) = @_;
	my $stats = $self->{'jobManager'}->get_summary_stats;
	say encode_json($stats);
	return;
}
1;
