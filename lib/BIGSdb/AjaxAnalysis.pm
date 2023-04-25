#Written by Keith Jolley
#Copyright (c) 2021, University of Oxford
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
package BIGSdb::AjaxAnalysis;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use JSON;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{'type'}    = 'text';
	$self->{'noCache'} = 1;
	return;
}

sub print_content {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $isolate_id = $q->param('isolate_id');
	my $name       = $q->param('name');
	if ( !defined $isolate_id ) {
		say encode_json( { error => 'isolate_id must be provided.' } );
		return;
	}
	if ( !BIGSdb::Utils::is_int($isolate_id) ) {
		say encode_json( { error => 'isolate_id must be an integer.' } );
		return;
	}
	if ( !defined $name ) {
		say encode_json( { error => 'Analysis name must be provided.' } );
		return;
	}
	my $data = $self->{'datastore'}
	  ->run_query( 'SELECT results FROM analysis_results WHERE (isolate_id,name)=(?,?)', [ $isolate_id, $name ] );
	$data //= encode_json( {} );
	say $data;
	return;
}
1;
