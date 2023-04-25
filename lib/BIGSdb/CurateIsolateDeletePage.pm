#Written by Keith Jolley
#Copyright (c) 2010-2022, University of Oxford
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
package BIGSdb::CurateIsolateDeletePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::IsolateInfoPage BIGSdb::CuratePage);
use JSON;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery jQuery.columnizer);
	my $field_attributes = $self->{'xmlHandler'}->get_all_field_attributes;
	foreach my $field ( keys %$field_attributes ) {
		if ( $field_attributes->{$field}->{'type'} eq 'geography_point'
			|| ( $field_attributes->{$field}->{'geography_point_lookup'} // q() ) eq 'yes' )
		{
			$self->{'ol'} = 1;
			last;
		}
	}
	$self->set_level1_breadcrumbs;
	return;
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $id     = $q->param('id');
	my $buffer;
	say q(<h1>Delete isolate</h1>);
	if ( !$id ) {
		$self->print_bad_status( { message => q(No id passed.) } );
		return;
	} elsif ( !BIGSdb::Utils::is_int($id) ) {
		$self->print_bad_status( { message => q(Isolate id must be an integer.) } );
		return;
	}
	my $data = $self->{'datastore'}->get_isolate_field_values($id);
	if ( !$data ) {
		$self->print_bad_status(
			{
				message => qq(No record with id-$id exists or your account is not allowed to delete it.)
			}
		);
		return;
	}
	if ( !$self->can_modify_table('isolates') ) {
		$self->print_bad_status(
			{
				message => q(Your user account is not allowed to delete records in the isolates table.)
			}
		);
		return;
	}
	my $icon = $self->get_form_icon( 'isolates', 'trash' );
	$buffer .= qq(<div class="box" id="resultspanel">\n);
	$buffer .= $icon;
	$buffer .= q(<p>You have chosen to delete the following record. Select 'Delete and Retire' )
	  . q(to prevent the isolate id being reused.</p>);
	$buffer .= $q->start_form;
	$buffer .= $q->hidden($_) foreach qw (page db id);
	$buffer .= $q->end_form;
	my $isolate_record = BIGSdb::IsolateInfoPage->new(
		(
			system        => $self->{'system'},
			cgi           => $self->{'cgi'},
			instance      => $self->{'instance'},
			prefs         => $self->{'prefs'},
			prefstore     => $self->{'prefstore'},
			config        => $self->{'config'},
			datastore     => $self->{'datastore'},
			db            => $self->{'db'},
			xmlHandler    => $self->{'xmlHandler'},
			dataConnector => $self->{'dataConnector'},
			contigManager => $self->{'contigManager'},
			curate        => 1
		)
	);
	my $record_table = $isolate_record->get_isolate_record($id);
	$buffer .= $record_table;
	$buffer .= $q->start_form;
	$q->param( page => 'isolateDelete' );    #need to set as this may have changed if there is a seqbin display button
	$buffer .= $q->hidden($_) foreach qw (page db id);

	if ( $self->_retire_only ) {
		$buffer .= $self->print_action_fieldset(
			{
				get_only     => 1,
				no_reset     => 1,
				submit       => 'delete_and_retire',
				submit_label => 'Delete and Retire'
			}
		);
	} else {
		$buffer .= $self->print_action_fieldset(
			{
				get_only      => 1,
				no_reset      => 1,
				submit_label  => 'Delete',
				submit2       => 'delete_and_retire',
				submit2_label => 'Delete and Retire'
			}
		);
	}
	$buffer .= $q->end_form;
	$buffer .= "</div>\n";
	if ( $q->param('submit') || $q->param('delete_and_retire') ) {
		$self->_delete( $data->{'id'}, { retire => $q->param('delete_and_retire') ? 1 : 0 } );
		return;
	}
	print $buffer;
	return;
}

sub _retire_only {
	my ($self) = @_;
	return ( !defined $self->{'system'}->{'delete_retire_only'} && $self->{'config'}->{'delete_retire_only'} )
	  || ( $self->{'system'}->{'delete_retire_only'} // q() ) eq 'yes';
}

sub _delete {
	my ( $self, $isolate_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my @actions;
	my $old_version = $self->{'datastore'}->run_query( "SELECT id FROM $self->{'system'}->{'view'} WHERE new_version=?",
		$isolate_id, { cache => 'CurateIsolateDeletePage::get_old_version' } );
	my $field_values = $self->{'datastore'}->get_isolate_field_values($isolate_id);
	my $new_version  = $field_values->{'new_version'};
	if ( $new_version && $old_version ) {

		#Deleting intermediate version - update old version to point to newer version
		push @actions,
		  { statement => 'UPDATE isolates SET new_version=? WHERE id=?', arguments => [ $new_version, $old_version ] };
	} elsif ($old_version) {

		#Deleting latest version - remove link to this version in old version
		push @actions, { statement => 'UPDATE isolates SET new_version=NULL WHERE id=?', arguments => [$old_version] };
	}
	push @actions, { statement => 'DELETE FROM isolates WHERE id=?', arguments => [$isolate_id] };
	if ( $options->{'retire'} || $self->_retire_only ) {
		my $curator_id = $self->get_curator_id;
		push @actions,
		  {
			statement => 'INSERT INTO retired_isolates (isolate_id,curator,datestamp) VALUES (?,?,?)',
			arguments => [ $isolate_id, $curator_id, 'now' ]
		  };
	}
	if ( $self->{'config'}->{'admin_log'} ) {
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		my $record_data =
		  $self->{'datastore'}
		  ->run_query( 'SELECT * FROM isolates WHERE id=?', $isolate_id, { fetch => 'row_hashref' } );
		my $record = {
			id                                => $isolate_id,
			$self->{'system'}->{'labelfield'} => $record_data->{ $self->{'system'}->{'labelfield'} }
		};
		my $fields = $self->{'xmlHandler'}->get_field_list;
		my $atts   = $self->{'xmlHandler'}->get_all_field_attributes;
		foreach my $field (@$fields) {
			if ( ( $atts->{$field}->{'log_delete'} // q() ) eq 'yes' ) {
				$record->{$field} = $record_data->{ lc $field } if defined $record_data->{ lc $field };
			}
		}
		push @actions,
		  {
			statement => q(INSERT INTO log (timestamp,user_id,user_name,"table",record,action) VALUES (?,?,?,?,?,?)),
			arguments =>
			  [ 'now', $user_info->{'id'}, $user_info->{'user_name'}, 'isolates', encode_json($record), 'delete' ]
		  };
	}
	eval {
		foreach my $action (@actions) {
			$self->{'db'}->do( $action->{'statement'}, undef, @{ $action->{'arguments'} } );
		}
	};
	if ($@) {
		$self->print_bad_status(
			{ message => 'Delete failed - transaction cancelled - no records have been touched.' } );
		$logger->error("Delete failed: $@");
		$self->{'db'}->rollback;
		return;
	}
	$self->{'db'}->commit;
	$self->print_good_status(
		{
			message => qq(Isolate id:$isolate_id deleted!),
			navbar  => 1
		}
	);
	return;
}

sub get_title {
	return q(Delete isolate);
}
1;
