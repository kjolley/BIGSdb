#Written by Keith Jolley
#Copyright (c) 2018-2019, University of Oxford
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
package BIGSdb::AjaxPrefs;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use JSON;

sub initiate {
	my ($self) = @_;
	$self->{'noCache'} = 1;
	$self->{'type'}    = 'no_header';
	return;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 1, query_field => 0 };
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('update') ) {
		$self->_update;
	} else {
		$self->_get;
	}
	return;
}

sub _get {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $guid   = $self->get_guid;
	if ( !$guid ) {
		say encode_json( { error => 1, message => 'No GUID.' } );
		return;
	}
	my $dbase = $self->{'system'}->{'db'};
	if ( $q->param('plugin') ) {
		my $data = $self->{'prefstore'}->get_plugin_attributes( $guid, $dbase, scalar $q->param('plugin') );
		say encode_json($data);
		return;
	}
	my $set_id = $self->get_set_id;
	if ( $q->param('loci') ) {
		my $data = $self->{'datastore'}->get_loci( { set_id => $set_id, analysis_pref => 1 } );
		@$data = sort @$data;
		say encode_json($data);
		return;
	}
	if ( $q->param('scheme_fields') ) {
		my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id, analysis_pref => 1, with_pk => 1 } );
		my $fields = [];
		foreach my $scheme (@$schemes) {
			my $scheme_fields = $self->{'datastore'}->get_scheme_fields( $scheme->{'id'} );
			foreach my $scheme_field (@$scheme_fields) {
				push @$fields,
				  {
					field => "s_$scheme->{'id'}_$scheme_field",
					label => "$scheme_field ($scheme->{'name'})"
				  };
			}
		}
		say encode_json($fields);
		return;
	}
	say encode_json( { error => 1, message => 'No valid parameters passed.' } );
	return;
}

sub _update {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $guid   = $self->get_guid;
	if ( !$guid ) {
		say encode_json( { error => 1, message => 'No GUID.' } );
		return;
	}
	my $dbase = $self->{'system'}->{'db'};
	foreach my $param (qw(attribute value plugin)) {
		my $value = $q->param($param);
		if ( !defined $value ) {
			say encode_json( { error => 1, message => "No $param set." } );
			return;
		}
	}
	eval {
		$self->{'prefstore'}->set_plugin_attribute(
			$guid, $dbase,
			scalar $q->param('plugin'),
			scalar $q->param('attribute'),
			scalar $q->param('value')
		);
	};
	if ($@) {
		say encode_json( { error => 1, message => 'Update failed.' } );
	} else {
		say encode_json( { message => 'Updated.' } );
	}
	return;
}
1;
