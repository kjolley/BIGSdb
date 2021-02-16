#Written by Keith Jolley
#Copyright (c) 2010-2021, University of Oxford
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
package BIGSdb::CurateDeleteAllPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use JSON;
use Log::Log4perl qw(get_logger);
use Try::Tiny;
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $table      = $q->param('table');
	my $query_file = $q->param('query_file');
	my $query      = $self->get_query_from_temp_file($query_file);
	if ( $q->param('list_file') ) {
		my $data_type = $q->param('datatype') // 'text';
		$self->{'datastore'}->create_temp_list_table( $data_type, scalar $q->param('list_file') );
	}
	my $record_name = $self->{'system'}->{'dbtype'} eq 'isolates'
	  && $table eq $self->{'system'}->{'view'} ? 'isolate' : $self->get_record_name($table);
	say qq(<h1>Delete multiple $record_name records</h1>);
	if ( !$self->can_delete_all ) {
		$self->print_bad_status( { message => q(Your user account is not allowed to delete all records.) } );
		return;
	}
	if ( $table eq 'profiles' && $query =~ /SELECT\ \*\ FROM\ m?v?_?scheme_(\d+)/x ) {
		my $scheme_id = $1;
		my $pk =
		  $self->{'datastore'}
		  ->run_query( 'SELECT field FROM scheme_fields WHERE scheme_id=? AND primary_key', $scheme_id );
		if ($pk) {
			$query =~ s/SELECT\ \*/SELECT $pk/x;
			$query =~ s/ORDER\ BY\ .*//x;
			$query = "SELECT \* FROM profiles WHERE scheme_id=$scheme_id AND profile_id IN ($query)";
		}
	}
	if ( !$self->{'datastore'}->is_table($table) ) {
		$self->print_bad_status( { message => qq(Table $table does not exist!) } );
		return;
	}
	if ( !$query ) {
		$self->print_bad_status( { message => q(No selection query passed!) } );
		return;
	}
	if ( $query !~ /SELECT\ \*\ FROM\ $table/x ) {
		$logger->error("Table: $table; Query:$query");
		$self->print_bad_status( { message => q(Invalid query passed!) } );
		return;
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) {
		$table = 'isolates';
	}
	if ( !$self->can_modify_table($table) ) {
		$self->print_bad_status(
			{
				message => qq(Your user account is not allowed to delete records from the $table table.)
			}
		);
		return;
	}
	if (   $self->{'system'}->{'dbtype'} eq 'sequences'
		&& ( $table eq 'sequences' || $table eq 'sequence_refs' )
		&& !$self->is_admin
		&& $self->_contains_unpermitted_loci($query) )
	{
		$self->print_bad_status(
			{
				message => q(Deletion contains some alleles for loci that you are not a curator of.)
			}
		);
		return;
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		my $schemes = $self->{'datastore'}->run_query( 'SELECT id FROM schemes', undef, { fetch => 'col_arrayref' } );
		foreach my $scheme_id (@$schemes) {
			if ( $query =~ /temp_isolates_scheme_fields_$scheme_id\s/x ) {
				try {
					$self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
				}
				catch {
					if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
						$self->print_bad_status(
							{
								message => q(Cannot copy data into temporary table - please )
								  . q(check scheme configuration (more details will be in the log file).)
							}
						);
						$logger->error('Cannot copy data to temporary table.');
					} else {
						$logger->logdie($_);
					}
				};
			}
		}
	}
	if ( $q->param('deleteAll') ) {
		$self->_delete( $table, $query );
	} else {
		$self->_print_interface( $table, $query_file );
	}
	return;
}

sub _contains_unpermitted_loci {
	my ( $self, $query ) = @_;
	$query =~ s/SELECT\ \*/SELECT DISTINCT(locus)/x;
	$query =~ s/ORDER\ BY.*$//x;
	my $loci = $self->{'datastore'}->run_query( $query, undef, { fetch => 'col_arrayref' } );
	my $curator_id = $self->get_curator_id;
	foreach my $locus (@$loci) {
		return 1 if !$self->{'datastore'}->is_allowed_to_modify_locus_sequences( $locus, $curator_id );
	}
	return;
}

sub _delete {
	my ( $self, $table, $query ) = @_;
	my $delete_qry = $query;
	my $q          = $self->{'cgi'};
	$delete_qry =~ s/ORDER\ BY.*//x;
	my %subs = (
		allele_sequences => sub { $self->_sub_allele_sequences( \$delete_qry ) }
	);
	if ( $subs{$table} ) {
		$subs{$table}->();
	}
	$delete_qry =~ s/^SELECT\ \*/DELETE/x;
	my $ids_affected = [];
	my @allele_designations;
	my @history;

	#Find what schemes are affected, then recreate scheme view
	my $scheme_ids = $self->_get_affected_schemes( $table, $query );
	my $loci = $self->_get_affected_loci( $table, $query );
	if ( $table eq 'allele_designations' ) {

		#Update isolate history if removing allele_designations, allele_sequences, aliases
		my $check_qry = $query;
		$check_qry =~
		  s/SELECT\ \*/SELECT allele_designations.isolate_id,allele_designations.locus,allele_designations.allele_id/x;
		my $check_sql = $self->{'db'}->prepare($check_qry);
		eval { $check_sql->execute };
		$logger->error($@) if $@;
		while ( my ( $isolate_id, $locus, $allele_id ) = $check_sql->fetchrow_array ) {
			push @history,             "$isolate_id|$locus: designation '$allele_id' deleted";
			push @allele_designations, "$isolate_id|$locus";
		}
	} elsif ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		( my $id_qry = $delete_qry ) =~ s/DELETE/SELECT id/;
		$ids_affected = $self->{'datastore'}->run_query( $id_qry, undef, { fetch => 'col_arrayref' } );
	}
	eval {
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
			$self->_delete_isolate_list($ids_affected);
		} elsif ( $table eq 'profiles' ) {
			$self->_delete_profiles($delete_qry);
		} elsif ( $table eq 'sequences' ) {
			$self->_delete_alleles($delete_qry);
		} else {
			$self->{'db'}->do($delete_qry);
		}
		$self->_refresh_db_views( $table, $scheme_ids );
	};
	if ($@) {
		my $detail;
		if ( $@ =~ /foreign key/ ) {
			$detail = q(Selected records are referred to by other tables and cannot be deleted.);
			if ( $table eq 'sequences' ) {
				$detail .= q( Alleles can belong to profiles so check these.);
			}
			$logger->debug($@);
		} else {
			$detail = q(This is a bug in the software or database structure. Please report this to the )
			  . q(database administrator. More details will be available in the error log.);
			$logger->fatal($@);
		}
		$self->print_bad_status(
			{
				message => q(Delete failed - transaction cancelled - no records have been touched.),
				detail  => $detail
			}
		);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		foreach (@history) {
			my ( $isolate_id, $message ) = split /\|/x, $_;
			$self->update_history( $isolate_id, $message );
		}
		if ( $table eq 'allele_designations' && @allele_designations ) {
			my $commit = 1;
			my $seqtag_sql =
			  $self->{'db'}->prepare( 'DELETE FROM allele_sequences WHERE seqbin_id IN (SELECT id FROM '
				  . 'sequence_bin WHERE isolate_id=?) AND locus=?' );
			foreach (@allele_designations) {
				my ( $isolate_id, $locus ) = split /\|/x, $_;
				if ( $self->can_modify_table('allele_sequences') && $q->param('delete_tags') ) {
					eval { $seqtag_sql->execute( $isolate_id, $locus ); };
					if ($@) {
						$logger->error($@);
						$commit = 0;
					}
				}
			}
			if ($commit) {
				$self->{'db'}->commit;
			} else {
				$self->{'db'}->rollback;
			}
		}
		$self->print_good_status( { message => 'Records deleted.' } );
	}
	if ( $table eq 'sequences' ) {
		$self->mark_locus_caches_stale($loci);
		$self->update_blast_caches;
	}
	return;
}

sub _delete_isolate_list {
	my ( $self, $ids ) = @_;
	my $q          = $self->{'cgi'};
	my $user_info  = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $log_fields = [ 'id', $self->{'system'}->{'labelfield'} ];
	if ( $self->{'config'}->{'admin_log'} ) {
		my $fields = $self->{'xmlHandler'}->get_field_list;
		my $atts   = $self->{'xmlHandler'}->get_all_field_attributes;
		foreach my $field (@$fields) {
			next if $field eq 'id' || $field eq $self->{'system'}->{'labelfield'};
			if ( ( $atts->{$field}->{'log_delete'} // q() ) eq 'yes' ) {
				push @$log_fields, $field;
			}
		}
	}
	foreach my $isolate_id (@$ids) {
		my $old_version =
		  $self->{'datastore'}->run_query( "SELECT id FROM $self->{'system'}->{'view'} WHERE new_version=?",
			$isolate_id, { cache => 'CurateIsolateDeletePage::get_old_version' } );
		my $field_values = $self->{'datastore'}->get_isolate_field_values($isolate_id);
		my $new_version  = $field_values->{'new_version'};

		#Deleting intermediate version - update old version to point to newer version
		if ( $new_version && $old_version ) {
			$self->{'db'}->do( 'UPDATE isolates SET new_version=? WHERE id=?', undef, $new_version, $old_version );

			#Deleting latest version - remove link to this version in old version
		} elsif ($old_version) {
			$self->{'db'}->do( 'UPDATE isolates SET new_version=NULL WHERE id=?', undef, $old_version );
		}
		if ( $self->{'config'}->{'admin_log'} ) {
			local $" = q(,);
			my $record_data = $self->{'datastore'}->run_query( "SELECT @$log_fields FROM isolates WHERE id=?",
				$isolate_id, { fetch => 'row_hashref', cache => 'CurateDeleteAll::get_isolate' } );
			my $record = {};
			foreach my $field (@$log_fields) {
				$record->{$field} = $record_data->{ lc $field } if defined $record_data->{ lc $field };
			}
			$self->{'db'}->do(
				q(INSERT INTO log (timestamp,user_id,user_name,"table",record,action) VALUES (?,?,?,?,?,?)),
				undef, 'now', $user_info->{'id'}, $user_info->{'user_name'},
				'isolates', encode_json($record), 'delete'
			);
		}
		$self->{'db'}->do( 'DELETE FROM isolates WHERE id=?', undef, $isolate_id );
		if ( $q->param('retire') || $self->_retire_only ) {
			$self->{'db'}->do( 'INSERT INTO retired_isolates (isolate_id,curator,datestamp) VALUES (?,?,?)',
				undef, $isolate_id, $user_info->{'id'}, 'now' );
		}
	}
	return;
}

sub _delete_profiles {
	my ( $self, $delete_qry ) = @_;
	my $q          = $self->{'cgi'};
	my $curator_id = $self->get_curator_id;
	if ( $q->param('retire') || $self->_retire_only ) {
		my $qry = $delete_qry;
		$qry =~ s/DELETE/SELECT\ scheme_id,profile_id/x;
		my $to_retire = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
		$self->{'db'}->do($delete_qry);
		foreach my $profile (@$to_retire) {
			$self->{'db'}->do(
				'INSERT INTO retired_profiles (scheme_id,profile_id,curator,datestamp) VALUES (?,?,?,?)',
				undef,
				$profile->{'scheme_id'},
				$profile->{'profile_id'},
				$curator_id, 'now'
			);
		}
	} else {
		$self->{'db'}->do($delete_qry);
	}
	return;
}

sub _delete_alleles {
	my ( $self, $delete_qry ) = @_;
	my $q          = $self->{'cgi'};
	my $curator_id = $self->get_curator_id;
	if ( $q->param('retire') || $self->_retire_only ) {
		my $qry = $delete_qry;
		$qry =~ s/DELETE/SELECT\ locus,allele_id/x;
		my $to_retire = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
		$self->{'db'}->do($delete_qry);
		foreach my $profile (@$to_retire) {
			$self->{'db'}->do(
				'INSERT INTO retired_allele_ids (locus,allele_id,curator,datestamp) VALUES (?,?,?,?)',
				undef, $profile->{'locus'}, $profile->{'allele_id'},
				$curator_id, 'now'
			);
		}
	} else {
		$self->{'db'}->do($delete_qry);
	}
	return;
}

sub _refresh_db_views {
	my ( $self, $table, $scheme_ids ) = @_;
	my $q = $self->{'cgi'};
	if ( ( $table eq 'scheme_members' || $table eq 'scheme_fields' )
		&& $self->{'system'}->{'dbtype'} eq 'sequences' )
	{
		foreach (@$scheme_ids) {
			$self->remove_profile_data($_);
		}
		return;
	}
	return;
}

sub _sub_allele_sequences {
	my ( $self, $qry ) = @_;
	if (   $$qry =~ /JOIN\ sequence_flags/x
		|| $$qry =~ /JOIN\ sequence_bin/x
		|| $$qry =~ /JOIN\ scheme_members/x )
	{
		$$qry =~ s/SELECT\ \*/SELECT allele_sequences.id/x;
		$$qry = "DELETE FROM allele_sequences WHERE id IN ($$qry)";
	}
	return;
}

sub _get_affected_schemes {
	my ( $self, $table, $query ) = @_;
	return [] if $self->{'system'}->{'dbtype'} ne 'sequences';
	if ( $table eq 'scheme_members' || $table eq 'scheme_fields' ) {
		my $scheme_qry = $query;
		$scheme_qry =~ s/SELECT\ \*/SELECT scheme_id/x;
		$scheme_qry =~ s/ORDER\ BY.*//x;
		return $self->{'datastore'}->run_query( $scheme_qry, undef, { fetch => 'col_arrayref' } );
	} elsif ( $table eq 'schemes' ) {
		my $scheme_qry = $query;
		$scheme_qry =~ s/SELECT\ \*/SELECT id/x;
		$scheme_qry =~ s/ORDER\ BY.*//x;
		return $self->{'datastore'}->run_query( $scheme_qry, undef, { fetch => 'col_arrayref' } );
	}
	return [];
}

sub _get_affected_loci {
	my ( $self, $table, $query ) = @_;
	return [] if $self->{'system'}->{'dbtype'} ne 'sequences';
	if ( $table eq 'sequences' ) {
		my $locus_qry = $query;
		$locus_qry =~ s/SELECT\ \*/SELECT locus/x;
		$locus_qry =~ s/ORDER\ BY.*//x;
		return $self->{'datastore'}->run_query( $locus_qry, undef, { fetch => 'col_arrayref' } );
	}
	return [];
}

sub _print_interface {
	my ( $self, $table, $query_file ) = @_;
	my $query = $self->get_query_from_temp_file($query_file);
	my $q     = $self->{'cgi'};
	if (   ( $table eq 'scheme_fields' || $table eq 'scheme_members' )
		&& $self->{'system'}->{'dbtype'} eq 'sequences'
		&& !$q->param('sent') )
	{
		say q(<div class="box" id="warning"><p>Please be aware that any modifications to the structure of )
		  . q(this scheme will result in the removal of all data from it. This is done to ensure data integrity. )
		  . q(This does not affect allele designations, but any profiles will have to be reloaded.</p></div>);
	}
	my $count_qry = $query;

	#Query may join the sequence_flags table giving more rows than allele sequences.
	if ( $table eq 'allele_sequences' ) {
		$count_qry =~ s/SELECT\ \*/SELECT COUNT(DISTINCT allele_sequences.id)/x;
	} else {
		$count_qry =~ s/SELECT\ \*/SELECT COUNT\(\*\)/x;
	}
	$count_qry =~ s/ORDER\ BY.*//x;
	my $count  = $self->{'datastore'}->run_query($count_qry);
	my $plural = $count == 1 ? '' : 's';
	my %retire = map { $_ => 1 } qw(isolates profiles sequences);
	say q(<div class="box" id="statusbad">);
	say q(<fieldset style="float:left"><legend>Warning</legend>);
	say q(<span class="warning_icon fas fa-exclamation-triangle fa-5x fa-pull-left"></span>);
	my $record_name = $self->{'system'}->{'dbtype'} eq 'isolates'
	  && $table eq $self->{'system'}->{'view'} ? 'isolate' : $self->get_record_name($table);
	say qq(<p>If you proceed, you will delete $count $record_name record$plural.  )
	  . q(Please confirm that this is your intention.</p>);

	if ( $retire{$table} ) {
		say $self->_retire_only
		  ? q(<p>The identifiers will not be re-assigned.</p>)
		  : q(<p>The identifiers will not be re-assigned if you 'delete and retire'.</p>);
	}
	say q(</fieldset>);
	say $q->start_form;
	if ( $retire{$table} ) {
		if ( $self->_retire_only ) {
			$self->print_action_fieldset(
				{
					legend       => 'Confirm action',
					no_reset     => 1,
					submit       => 'retire',
					submit_label => 'Delete and Retire'
				}
			);
		} else {
			$self->print_action_fieldset(
				{
					legend        => 'Confirm action',
					submit_label  => 'Delete',
					submit2       => 'retire',
					submit2_label => 'Delete and retire',
					no_reset      => 1
				}
			);
		}
	} else {
		$self->print_action_fieldset( { legend => 'Confirm action', submit_label => 'Delete', no_reset => 1 } );
	}
	$q->param( deleteAll => 1 );
	say $q->hidden($_) foreach qw (page db query_file deleteAll table delete_tags scheme_id list_file datatype);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _retire_only {
	my ($self) = @_;
	return ( !defined $self->{'system'}->{'delete_retire_only'} && $self->{'config'}->{'delete_retire_only'} )
	  || ( $self->{'system'}->{'delete_retire_only'} // q() ) eq 'yes';
}

sub get_title {
	my ($self) = @_;
	my $table = $self->{'cgi'}->param('table');
	$table = 'isolates' if $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'};
	my $type = $self->get_record_name($table) // q();
	return "Delete multiple $type records";
}
1;
