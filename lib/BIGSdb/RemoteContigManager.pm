#Written by Keith Jolley
#Copyright (c) 2017, University of Oxford
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
package BIGSdb::RemoteContigManager;
use strict;
use warnings;
use 5.010;
use BIGSdb::BIGSException;
use LWP::UserAgent;
use JSON;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Application_Authentication');

sub new {
	my ( $class, @atr ) = @_;
	my $self = {@atr};
	bless( $self, $class );
	$self->{'ua'} = LWP::UserAgent->new( agent => 'BIGSdb' );
	$logger->info('Remote contig manager set up.');
	return $self;
}

sub get_remote_contig {
	my ( $self, $uri ) = @_;
	my $response = $self->{'ua'}->get($uri);
	if ( $response->is_success ) {
		my $json;
		eval { $json = decode_json( $response->decoded_content ); };
		throw BIGSdb::DataException('Data is not JSON') if $@;
		return { json => $json };
	} else {
		throw BIGSdb::FileException("Cannot retrieve $uri");
	}
}
1;
