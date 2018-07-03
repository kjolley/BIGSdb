#Written by Keith Jolley
#Copyright (c) 2017-2018, University of Oxford
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
package BIGSdb::CuratePublishIsolate;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use BIGSdb::IsolateInfoPage;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Publish isolate record</h1>);
	my $isolate_id = $q->param('isolate_id');
	if ( !BIGSdb::Utils::is_int($isolate_id) || !$self->isolate_exists($isolate_id) ) {
		$self->print_bad_status( { message => q(Invalid isolate id passed.), navbar => 1 } );
		return;
	}
	if ( !$self->can_modify_table('isolates') ) {
		$self->print_bad_status(
			{
				message => q(Your account doesn't have permission ) . q(to modify isolate records.),
				navbar  => 1
			}
		);
		return;
	}
	my $curator_id = $self->get_curator_id;
	my $is_owner   = $self->_is_owner($isolate_id);
	my $request_only;
	my $no_further_action;
	if ( $q->param('publish') && !$request_only ) {
		if ( $self->_publish($isolate_id) ) {
			$self->print_good_status( { message => q(Isolate is now publicly accessible.) } );
		} else {
			$self->print_bad_status( { message => q(Isolate could not be made public.) } );
		}
		$no_further_action = 1;
	} elsif ( $q->param('request') && $is_owner ) {
		if ( $self->_request($isolate_id) ) {
			$self->print_good_status(
				{ message => q(Publication has been requested. ) . q(Isolate is now viewable by curators.) } );
		} else {
			$self->print_bad_status( { message => q(Publication request could not be made.) } );
		}
		$no_further_action = 1;
	} elsif ( ( $is_owner && $self->{'permissions'}->{'only_private'} ) || !$self->can_modify_table('isolates') ) {
		say q(<div class="box" id="resultsheader"><p>Your account does not have permission to directly make )
		  . q(isolates public. You can, however, send a request to a curator for this to happen.</p></div>);
		$request_only = 1;
	}
	$self->_print_interface( $isolate_id, { no_further_action => $no_further_action, request => $request_only } );
	return;
}

sub _is_owner {
	my ( $self, $isolate_id ) = @_;
	my $curator_id = $self->get_curator_id;
	return $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM private_isolates WHERE (isolate_id,user_id)=(?,?))',
		[ $isolate_id, $curator_id ] );
}

sub _publish {
	my ( $self, $isolate_id ) = @_;
	my $isolate_accessible = $self->{'datastore'}
	  ->run_query( "SELECT EXISTS(SELECT * FROM $self->{'system'}->{'view'} WHERE id=?)", $isolate_id );
	if ( $self->_is_owner($isolate_id) || ( $self->can_modify_table('isolates') && $isolate_accessible ) ) {
		eval { $self->{'db'}->do( 'DELETE FROM private_isolates WHERE isolate_id=?', undef, $isolate_id ); };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
			return;
		} else {
			$self->{'db'}->commit;
			return 1;
		}
	}
	return;
}

sub _request {
	my ( $self, $isolate_id ) = @_;
	eval {
		$self->{'db'}->do( 'UPDATE private_isolates SET request_publish=TRUE WHERE isolate_id=?', undef, $isolate_id );
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
		return;
	}
	$self->{'db'}->commit;
	return 1;
}

sub _print_interface {
	my ( $self, $isolate_id, $options ) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="queryform">);
	my $isolate_record = BIGSdb::IsolateInfoPage->new(
		(
			system        => $self->{'system'},
			cgi           => $self->{'cgi'},
			instance      => $self->{'instance'},
			config        => $self->{'config'},
			datastore     => $self->{'datastore'},
			db            => $self->{'db'},
			xmlHandler    => $self->{'xmlHandler'},
			dataConnector => $self->{'dataConnector'},
			contigManager => $self->{'contigManager'},
			curate        => 1
		)
	);
	say $isolate_record->get_isolate_summary( $isolate_id, 1 );
	my $label;
	if ( !$options->{'no_further_action'} ) {
		say $q->start_form;
		if ( $options->{'request'} ) {
			$label = 'Request publication';
			say $q->hidden( request => 1 );
		} else {
			$label = 'Publish';
			say $q->hidden( publish => 1 );
		}
		$self->print_action_fieldset( { submit_label => $label, no_reset => 1 } );
		say $q->hidden($_) foreach qw(db page isolate_id);
		say $q->end_form;
	}
	$self->print_navigation_bar;
	say q(</div>);
	return;
}

sub get_title {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	my $isolate_id = $q->param('isolate_id');
	if ( BIGSdb::Utils::is_int($isolate_id) ) {
		return "Publish id-$isolate_id - $desc";
	}
	return "Publish isolate - $desc";
}
1;
