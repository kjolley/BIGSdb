#!/usr/bin/perl
#Create scheme profile caches in an isolate database
#
#Written by Keith Jolley
#Copyright (c) 2014-2023, University of Oxford
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
package BIGSdb::Offline::UpdateSchemeCaches;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Offline::Script);
use JSON;
use constant DAILY_REPLACE_LIMIT => 10_000;

sub run_script {
	my ($self) = @_;
	die "No connection to database (check logs).\n" if !defined $self->{'db'};
	die "This script can only be run against an isolate database.\n"
	  if ( $self->{'system'}->{'dbtype'} // '' ) ne 'isolates';
	my $status = { start_time => time };
	my $job_id = $self->add_job(
		'UpdateSchemeCaches',
		{
			temp_init  => 1,
			job_id     => $self->{'options'}->{'job_id'},
			username   => $self->{'options'}->{'username'},
			email      => $self->{'options'}->{'email'},
			ip_address => $self->{'options'}->{'ip_address'}
		}
	);
	eval { $self->{'db'}->do(q(SET lock_timeout = 30000)) };
	$self->{'logger'}->error($@) if $@;
	my $schemes       = [];
	my $scheme_status = [];
	my $cschemes      = [];

	if ( $self->{'options'}->{'schemes'} ) {
		my $divider = q(,);
		@$schemes      = split /$divider/x, $self->{'options'}->{'schemes'};
		$scheme_status = $schemes;
		foreach my $scheme_id (@$schemes) {
			if ( !BIGSdb::Utils::is_int($scheme_id) ) {
				die "Scheme id must be an integer - $scheme_id is not.\n";
			}
			my $cschemes_using_this_scheme =
			  $self->{'datastore'}->run_query( 'SELECT id FROM classification_schemes WHERE scheme_id=?',
				$scheme_id, { fetch => 'col_arrayref', cache => 'get_cschemes_from_scheme' } );
			push @$cschemes, @$cschemes_using_this_scheme if @$cschemes_using_this_scheme;
		}
	} else {
		$schemes =
		  $self->{'datastore'}
		  ->run_query( 'SELECT id FROM schemes WHERE dbase_name IS NOT NULL AND dbase_id IS NOT NULL ORDER BY id',
			undef, { fetch => 'col_arrayref' } );
		$scheme_status = $self->{'datastore'}->run_query(
			'SELECT id FROM schemes WHERE quality_metric OR '
			  . '(dbase_name IS NOT NULL AND dbase_id IS NOT NULL) ORDER BY id',
			undef,
			{ fetch => 'col_arrayref' }
		);
		$cschemes =
		  $self->{'datastore'}
		  ->run_query( 'SELECT id FROM classification_schemes', undef, { fetch => 'col_arrayref' } );
	}
	my $method = $self->{'options'}->{'method'} // 'full';
	if ( $method eq 'daily_replace' ) {
		my $count = $self->{'datastore'}->run_query(q(SELECT COUNT(*) FROM isolates WHERE datestamp='today'));
		if ( $count > DAILY_REPLACE_LIMIT ) {
			my $limit = DAILY_REPLACE_LIMIT;
			$self->{'logger'}->error( "Daily replace limit is $limit. $count records were modified today. "
				  . 'Scheme renewal cancelled. Run full refresh if necessary.' );
			$self->stop_job( $job_id, { temp_init => 1 } );
			return;
		}
	}
	my %used_for_metrics = map { $_ => 1 } @$scheme_status;
	foreach my $scheme_id (@$schemes) {
		$scheme_id =~ s/\s//gx;
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		if ( !$scheme_info ) {
			say "Scheme $scheme_id does not exist";
			next;
		}
		if ( !defined $scheme_info->{'primary_key'} ) {
			if ( !$self->{'options'}->{'q'} && !$used_for_metrics{$scheme_id} ) {
				say "Scheme $scheme_id ($scheme_info->{'name'}) does not have a primary key - skipping.";
			}
			next;
		}
		say "Updating scheme $scheme_id field cache ($scheme_info->{'name'}) - method: $method"
		  if !$self->{'options'}->{'q'};
		$self->update_job( $job_id, { temp_init => 1, status => { stage => "Scheme $scheme_id: fields ($method)" } } );
		$status->{'stage'} = "Scheme $scheme_id ($scheme_info->{'name'}): fields ($method)";
		$self->_write_status_file($status);
		$self->{'datastore'}->create_temp_isolate_scheme_fields_view(
			$scheme_id,
			{
				cache       => 1,
				method      => $method,
				reldate     => $self->{'options'}->{'reldate'},
				status      => $status,
				status_file => $self->{'options'}->{'status_file'}
			}
		);
	}
	foreach my $scheme_id (@$scheme_status) {
		$scheme_id =~ s/\s//gx;
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		if ( !$scheme_info ) {
			next;
		}
		say "Updating scheme $scheme_id completion status cache ($scheme_info->{'name'}) - method: $method"
		  if !$self->{'options'}->{'q'};
		my $stage = "Scheme $scheme_id ($scheme_info->{'name'}): completion status ($method)";
		$self->update_job( $job_id, { temp_init => 1, status => { stage => $stage } } );
		$status->{'stage'} = $stage;
		$self->_write_status_file($status);
		$self->{'datastore'}->create_temp_scheme_status_table(
			$scheme_id,
			{
				cache       => 1,
				method      => $method,
				reldate     => $self->{'options'}->{'reldate'},
				status      => $status,
				status_file => $self->{'options'}->{'status_file'}
			}
		);
		if ( $self->{'datastore'}->are_lincodes_defined($scheme_id) ) {
			say "Updating scheme $scheme_id LINcodes cache ($scheme_info->{'name'})"
			  if !$self->{'options'}->{'q'};
			$stage = "Scheme $scheme_id ($scheme_info->{'name'}): LINcodes";
			$self->update_job( $job_id, { temp_init => 1, status => { stage => $stage } } );
			$status->{'stage'} = $stage;
			$self->_write_status_file($status);
			$self->{'datastore'}->create_temp_lincodes_table( $scheme_id, { cache => 1 } );
			$self->{'datastore'}->create_temp_lincode_prefix_values_table( $scheme_id, { cache => 1 } );
		}
	}
	foreach my $cscheme_id (@$cschemes) {
		my $stage = "Cluster scheme $cscheme_id";
		$self->update_job( $job_id, { temp_init => 1, status => { stage => $stage } } );
		$status->{'stage'} = $stage;
		$self->_write_status_file($status);
		$self->{'datastore'}->create_temp_cscheme_table( $cscheme_id, { cache => 1 } );
		$self->{'datastore'}->create_temp_cscheme_field_values_table( $cscheme_id, { cache => 1 } );
	}
	eval { $self->{'db'}->do('SET lock_timeout = 0') };
	$self->{'logger'}->error($@) if $@;
	$self->stop_job( $job_id, { temp_init => 1 } );
	delete $status->{'stage'};
	$status->{'stop_time'} = time;
	$self->_write_status_file($status);
	return;
}

sub _write_status_file {
	my ( $self, $data ) = @_;
	return if !$self->{'options'}->{'status_file'};
	my $file_path;
	if ( $self->{'options'}->{'status_file'} =~ /($self->{'config'}->{'tmp_dir'}\/BIGSdb_\d+_\d+_\d+\.json)/x ) {
		$file_path = $1;    #Untaint.
	} else {
		$self->{'logger'}->error("Invalid status file $self->{'options'}->{'status_file'}");
	}
	my $json = encode_json($data);
	open( my $fh, '>', $file_path )
	  || $self->{'logger'}->error("Cannot open $file_path for writing");
	say $fh $json;
	close $fh;
	return;
}
1;
