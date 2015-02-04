#Written by Keith Jolley
#Copyright (c) 2010-2014, University of Oxford
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
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self)      = @_;
	my $q           = $self->{'cgi'};
	my $table       = $q->param('table');
	my $query_file  = $q->param('query_file');
	my $query       = $self->get_query_from_temp_file($query_file);
	my $record_name = $self->get_record_name($table);
	say "<h1>Delete multiple $record_name records</h1>";
	if (!$self->can_delete_all){
		say q(<div class="box" id="statusbad"><p>Your user account is not allowed to delete all records.</p></div>);
		return;
	}
	if ( $table eq 'profiles' && $query =~ /SELECT \* FROM m?v?_?scheme_(\d+)/ ) {
		my $scheme_id = $1;
		my $pk = $self->{'datastore'}->run_query( "SELECT field FROM scheme_fields WHERE scheme_id=? AND primary_key", $scheme_id );
		if ($pk) {
			$query =~ s/SELECT \*/SELECT $pk/;
			$query =~ s/ORDER BY .*//;
			$query = "SELECT \* FROM profiles WHERE scheme_id=$scheme_id AND profile_id IN ($query)";
		}
	}
	if ( !$self->{'datastore'}->is_table($table) && !( $table eq 'samples' && @{ $self->{'xmlHandler'}->get_sample_field_list } ) ) {
		say qq(<div class="box" id="statusbad"><p>Table $table does not exist!</p></div>);
		return;
	} elsif ( !$query ) {
		say qq(<div class="box" id="statusbad"><p>No selection query passed!</p></div>);
		return;
	} elsif ( $query !~ /SELECT \* FROM $table/ ) {
		$logger->error("Table: $table; Query:$query");
		say qq(<div class="box" id="statusbad"><p>Invalid query passed!</p></div>);
		return;
	} elsif ( !$self->can_modify_table($table) ) {
		say qq(<div class="box" id="statusbad"><p>Your user account is not allowed to delete records from the $table table.</p></div>);
		return;
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' && !$self->is_admin && ( $table eq 'sequences' || $table eq 'sequence_refs' ) ) {
		say qq(<div class="box" id="statusbad"><p>Only administrators can batch delete from the $table table.</p></div>);
		return;
	}
	if ( $q->param('datatype') && $q->param('list_file') ) {
		$self->{'datastore'}->create_temp_list_table( $q->param('datatype'), $q->param('list_file') );
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		my $schemes = $self->{'datastore'}->run_query("SELECT id FROM schemes", undef, {fetch=>'col_arrayref'});
		foreach my $scheme_id (@$schemes) {
			if ( $query =~ /temp_scheme_$scheme_id\s/ ) {
				try {
					$self->{'datastore'}->create_temp_scheme_table($scheme_id);
					$self->{'datastore'}->create_temp_isolate_scheme_loci_view($scheme_id);
				}
				catch BIGSdb::DatabaseConnectionException with {
					say qq(<div class="box" id="statusbad"><p>Can't copy data into temporary table - please check scheme configuration )
					  . qq[(more details will be in the log file).</p></div>];
					$logger->error("Can't copy data to temporary table.");
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

sub _delete {
	my ( $self, $table, $query ) = @_;
	my $delete_qry = $query;
	my $q          = $self->{'cgi'};
	$delete_qry =~ s/ORDER BY.*//;
	if ( $table eq 'loci' && $delete_qry =~ /JOIN scheme_members/ && $delete_qry =~ /scheme_id is null/ ) {
		$delete_qry = "DELETE FROM loci WHERE id IN ($delete_qry)";
		$delete_qry =~ s/SELECT \*/SELECT id/;
	} elsif ( $table eq 'sequence_bin' && $delete_qry =~ /JOIN experiment_sequences/ ) {
		$delete_qry = "DELETE FROM sequence_bin WHERE id IN ($delete_qry)";
		$delete_qry =~ s/SELECT \*/SELECT id/;
	} elsif ( $table eq 'allele_sequences'
		&& ( $delete_qry =~ /JOIN sequence_flags/ || $delete_qry =~ /JOIN sequence_bin/ || $delete_qry =~ /JOIN scheme_members/ ) )
	{
		$delete_qry =~ s/SELECT \*/SELECT allele_sequences.id/;
		$delete_qry = "DELETE FROM allele_sequences WHERE id IN ($delete_qry)";
	} elsif ( $table eq 'allele_designations' && ( $delete_qry =~ /JOIN scheme_members/ ) ) {
		$delete_qry =~ s/SELECT \*/SELECT allele_designations.isolate_id,allele_designations.locus,allele_designations.allele_id/;
		$delete_qry = "DELETE FROM allele_designations WHERE (isolate_id,locus,allele_id) IN ($delete_qry)";
	}
	$delete_qry =~ s/^SELECT \*/DELETE/;
	my $scheme_ids;
	my $schemes_affected;
	my $ids_affected;
	if ( $table eq 'loci' && $delete_qry =~ /JOIN scheme_members/ && $delete_qry !~ /scheme_id is null/ ) {
		$schemes_affected = 1;
	}
	my @allele_designations;
	my @history;
	if ( ( $table eq 'scheme_members' || $table eq 'scheme_fields' ) && $self->{'system'}->{'dbtype'} eq 'sequences' ) {

		#Find what schemes are affected, then recreate scheme view
		my $scheme_qry = $query;
		$scheme_qry =~ s/SELECT \*/SELECT scheme_id/;
		$scheme_qry =~ s/ORDER BY.*//;
		$scheme_ids = $self->{'datastore'}->run_query( $scheme_qry, undef, { fetch => 'col_arrayref' } );
	} elsif ( $table eq 'schemes' && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $scheme_qry = $query;
		$scheme_qry =~ s/SELECT \*/SELECT id/;
		$scheme_qry =~ s/ORDER BY.*//;
		$scheme_ids = $self->{'datastore'}->run_query( $scheme_qry, undef, { fetch => 'col_arrayref' } );
	} elsif ( $table eq 'allele_designations' ) {

		#Update isolate history if removing allele_designations, allele_sequences, aliases
		my $check_qry = $query;
		$check_qry =~ s/SELECT \*/SELECT allele_designations.isolate_id,allele_designations.locus,allele_designations.allele_id/;
		my $check_sql = $self->{'db'}->prepare($check_qry);
		eval { $check_sql->execute };
		$logger->error($@) if $@;
		while ( my ( $isolate_id, $locus, $allele_id ) = $check_sql->fetchrow_array ) {
			push @history,             "$isolate_id|$locus: designation '$allele_id' deleted";
			push @allele_designations, "$isolate_id|$locus";
		}
	} elsif ( $table eq 'isolates' ) {
		( my $id_qry = $delete_qry ) =~ s/DELETE/SELECT id/;
		$ids_affected = $self->{'datastore'}->run_query( $id_qry, undef, { fetch => 'col_arrayref' } );
	}
	if ($schemes_affected) {
		say qq(<div class="box" id="statusbad"><p>Deleting these loci would affect scheme definitions - can not delete!</p></div>);
		return;
	}
	eval {
		if ( ref $ids_affected eq 'ARRAY' )
		{
			foreach my $isolate_id (@$ids_affected) {
				my $old_version = $self->{'datastore'}->run_query( "SELECT id FROM $self->{'system'}->{'view'} WHERE new_version=?",
					$isolate_id, { cache => 'CurateIsolateDeletePage::get_old_version' } );
				my $field_values = $self->{'datastore'}->get_isolate_field_values($isolate_id);
				my $new_version  = $field_values->{'new_version'};
				if ( $new_version && $old_version ) {    #Deleting intermediate version - update old version to point to newer version
					$self->{'db'}->do( 'UPDATE isolates SET new_version=? WHERE id=?', undef, $new_version, $old_version );
				} elsif ($old_version) {                 #Deleting latest version - remove link to this version in old version
					$self->{'db'}->do( 'UPDATE isolates SET new_version=NULL WHERE id=?', undef, $old_version );
				}
			}
		}
		$self->{'db'}->do($delete_qry);
		if ( ( $table eq 'scheme_members' || $table eq 'scheme_fields' ) && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
			foreach (@$scheme_ids) {
				$self->remove_profile_data($_);
				$self->drop_scheme_view($_);
				$self->create_scheme_view($_);
			}
		} elsif ( $table eq 'schemes' && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
			foreach (@$scheme_ids) {
				$self->drop_scheme_view($_);
			}
		} elsif ( $table eq 'sequences' ) {
			$self->mark_cache_stale;
		} elsif ( $table eq 'profiles' ) {
			my $scheme_id = $q->param('scheme_id');
			$self->refresh_material_view($scheme_id);
		}
	};
	if ($@) {
		say qq(<div class="box" id="statusbad"><p>Delete failed - transaction cancelled - no records have been touched.</p>);
		if ( $@ =~ /foreign key/ ) {
			say "<p>Selected records are referred to by other tables and can not be deleted.</p>";
			if ( $table eq 'sequences' ) {
				say "<p>Alleles can belong to profiles so check these.</p>";
			}
			say "</div>";
			$logger->debug($@);
		} else {
			say "<p>This is a bug in the software or database structure.  Please report this to the database administrator. "
			  . "More details will be available in the error log.</p></div>";
			$logger->error($@);
		}
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		foreach (@history) {
			my ( $isolate_id, $message ) = split /\|/, $_;
			$self->update_history( $isolate_id, $message );
		}
		if ( $table eq 'allele_designations' && @allele_designations ) {
			my $commit = 1;
			my $seqtag_sql =
			  $self->{'db'}
			  ->prepare("DELETE FROM allele_sequences WHERE seqbin_id IN (SELECT id FROM sequence_bin WHERE isolate_id=?) AND locus=?");
			foreach (@allele_designations) {
				my ( $isolate_id, $locus ) = split /\|/, $_;
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
		say qq(<div class="box" id="resultsheader"><p>Records deleted.</p>);
		say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Return to index</a></p></div>);
	}
	return;
}

sub _print_interface {
	my ( $self, $table, $query_file ) = @_;
	my $query = $self->get_query_from_temp_file($query_file);
	my $q     = $self->{'cgi'};
	if (   ( $table eq 'scheme_fields' || $table eq 'scheme_members' )
		&& $self->{'system'}->{'dbtype'} eq 'sequences'
		&& !$q->param('sent') )
	{
		say qq(<div class="box" id="warning"><p>Please be aware that any modifications to the structure of this scheme will )
		  . qq(result in the removal of all data from it. This is done to ensure data integrity.  This does not affect allele designations, )
		  . qq(but any profiles will have to be reloaded.</p></div>);
	}
	my $count_qry = $query;
	if ( $table eq 'allele_sequences' ) {    #Query may join the sequence_flags table giving more rows than allele sequences.
		$count_qry =~ s/SELECT \*/SELECT COUNT(DISTINCT allele_sequences.id)/;
	} else {
		$count_qry =~ s/SELECT \*/SELECT COUNT\(\*\)/;
	}
	$count_qry =~ s/ORDER BY.*//;
	my $count = $self->{'datastore'}->run_query($count_qry);
	my $plural = $count == 1 ? '' : 's';
	say qq(<div class="box" id="statusbad">);
	my $record_name = $self->get_record_name($table);
	say "<p>If you proceed, you will delete $count $record_name record$plural.  Please confirm that this is your intention.</p>";
	say $q->start_form;
	$q->param( 'deleteAll', 1 );
	say $q->hidden($_) foreach qw (page db query_file deleteAll table delete_tags scheme_id list_file datatype);
	say $q->submit( -label => 'Confirm deletion!', -class => 'submit' );
	say $q->end_form;
	$self->print_warning_sign;
	say "</div>";
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc  = $self->{'system'}->{'description'} || 'BIGSdb';
	my $table = $self->{'cgi'}->param('table');
	my $type  = $self->get_record_name($table);
	return "Delete multiple $type records - $desc";
}
1;
