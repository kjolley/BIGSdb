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
package BIGSdb::AjaxRest;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use JSON;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant DEFAULT_TIME     => 60 * 12;    #12h
use constant DEFAULT_INTERVAL => 2;

sub initiate {
	my ($self) = @_;
	$self->{'type'}    = 'text';
	$self->{'noCache'} = 1;
	return;
}

sub print_content {
	my ($self)  = @_;
	my $q       = $self->{'cgi'};
	my $minutes = $q->param('minutes');
	my $time = $minutes // DEFAULT_TIME;
	if ( !$self->{'config'}->{'rest_db'} ) {
		say encode_json( { error => 'REST db is not configured' } );
		return;
	}
	if ( !BIGSdb::Utils::is_int($time) ) {
		$logger->error('Invalid time passed - should be an integer (minutes)');
		$time = DEFAULT_TIME;
	}
	if ( $q->param('summary') ) {
		$self->_summary_stats($time);
		return;
	}
	my $width = $q->param('interval') // DEFAULT_INTERVAL;
	if ( !BIGSdb::Utils::is_int($width) ) {
		$logger->error('Invalid width passed - should be an integer (minutes)');
		$width = DEFAULT_INTERVAL;
	}
	my $buckets = $self->{'datastore'}->run_query(
		q[SET timezone TO 'UTC';]
		  . qq[SELECT * FROM generate_series(CAST(date_trunc('minute',now()-interval '$time minutes') AS timestamp),]
		  . qq[CAST(date_trunc('minute',now()) AS timestamp), '$width minutes') t],
		undef,
		{ fetch => 'col_arrayref' }
	);
	my $data = $self->{'datastore'}->run_query(
		q[SELECT width_bucket(timestamp,(select array_agg(t) AS result FROM ]
		  . qq[generate_series(CAST(date_trunc('minute',now()-interval '$time minutes') AS timestamp),]
		  . qq[CAST(date_trunc('minute',now()) AS timestamp), '$width minutes') t)]
		  . q[) bucket,avg(duration),count(*) AS count FROM log WHERE timestamp > ]
		  . qq[date_trunc('minute',now())-interval '$time minutes']
		  . q[GROUP BY bucket ORDER BY bucket],
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my %bucket_count = map { $buckets->[ $_->{'bucket'} - 1 ] => $_->{'count'} } @$data;
	my $return_data = [];
	foreach my $start_time (@$buckets) {
		push @$return_data,
		  {
			start => $start_time,
			hits  => $bucket_count{$start_time} // 0
		  };
	}
	say encode_json($return_data);
	return;
}

sub _summary_stats {
	my ( $self, $minutes ) = @_;
	my $data = $self->{'datastore'}->run_query(
		q(SELECT COUNT(*) hits,avg(duration) avg_response FROM log WHERE )
		  . qq(timestamp > now() - interval '$minutes minutes'),
		undef,
		{ fetch => 'row_hashref' }
	);
	my $response = {
		period       => int($minutes),
		hits         => int( $data->{'hits'} ),
		avg_response => int( $data->{'avg_response'} )
	};
	say encode_json($response);
	return;
}
1;
