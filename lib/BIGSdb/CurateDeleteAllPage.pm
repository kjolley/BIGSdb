#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
use base qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self)      = @_;
	my $q           = $self->{'cgi'};
	my $table       = $q->param('table');
	my $query       = $q->param('query');
	my $record_name = $self->get_record_name($table);
	print "<h1>Delete multiple $record_name records</h1>\n";
	if ( $table eq 'profiles' && $query =~ /SELECT \* FROM scheme_(\d+)/ ) {
		my $scheme_id = $1;
		my $pk_ref =
		  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE scheme_id=? AND primary_key", $scheme_id );
		if ( ref $pk_ref eq 'ARRAY' ) {
			my $pk = $pk_ref->[0];
			$query =~ s/SELECT \*/SELECT $pk/;
			$query =~ s/ORDER BY .*//;
			$query = "SELECT \* FROM profiles WHERE scheme_id=$scheme_id AND profile_id IN ($query)";
		}
	}
	if ( !$self->{'datastore'}->is_table($table) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Table $table does not exist!</p></div>\n";
		return;
	} elsif ( !$query ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No selection query passed!</p></div>\n";
		return;
	} elsif ( $query !~ /SELECT \* FROM $table/ ) {
		$logger->error("Table: $table; Query:$query");
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid query passed!</p></div>\n";
		return;
	} elsif ( !$self->can_modify_table($table) ) {
		print
		  "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to delete records from the $table table.</p></div>\n";
		return;
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' && !$self->is_admin && ( $table eq 'sequences' || $table eq 'sequence_refs' ) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Only administrators can batch delete from the $table table.</p></div>\n";
		return;
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) {
		my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
		foreach (@$schemes) {
			if ( $query =~ /temp_scheme_$_\s/ ) {
				try {
					$self->{'datastore'}->create_temp_scheme_table($_);
				} catch BIGSdb::DatabaseConnectionException with {
					print
"<div class=\"box\" id=\"statusbad\"><p>Can't copy data into temporary table - please check scheme configuration (more details will be in the log file).</p></div>\n";					
					$logger->error("Can't copy data to temporary table.");
				};
			}
		}
	}
	if ( $q->param('deleteAll') ) {
		my $delete_qry = $query;
		if (   ( $self->{'system'}->{'read_access'} eq 'acl' || ( $self->{'system'}->{'write_access'} && $self->{'system'}->{'write_access'} eq 'acl' ))
			&& $self->{'username'}
			&& !$self->is_admin )
		{
			if ( $table eq $self->{'system'}->{'view'} ) {
				$delete_qry =~ s/WHERE/AND/;
				$delete_qry =~ s/FROM $table/FROM isolates WHERE id IN (SELECT id FROM $self->{'system'}->{'view'})/;
			} elsif ( $table eq 'allele_designations' || $table eq 'sequence_bin' || $table eq 'isolate_aliases' ) {
				$delete_qry =~ s/WHERE/AND/;
				$delete_qry =~ s/FROM $table/FROM $table WHERE isolate_id IN (SELECT id FROM $self->{'system'}->{'view'})/;
			} elsif ( $self->{'system'}->{'dbtype'} eq 'isolates' && ( $table eq 'allele_sequences' || $table eq 'accession' ) ) {
				$delete_qry =~ s/WHERE/AND/;
				$delete_qry =~
s/FROM $table/FROM $table WHERE seqbin_id IN (SELECT seqbin_id FROM $table LEFT JOIN sequence_bin ON $table.seqbin_id=sequence_bin.id WHERE isolate_id IN (SELECT id FROM $self->{'system'}->{'view'}))/;
			} elsif ( $table eq 'user_groups' ) {

				#don't delete 'All users' table (id=0)
				$delete_qry =~ s/WHERE/AND/;
				$delete_qry =~ s/FROM $table/FROM $table WHERE id>0/;
			} elsif ( $table eq 'user_group_members' ) {
				$delete_qry =~ s/WHERE/AND/;
				$delete_qry =~ s/FROM $table/FROM $table WHERE user_group>0/;
			}
		}
		$delete_qry =~ s/ORDER BY.*//;
		if ( $table eq 'loci' && $delete_qry =~ /JOIN scheme_members/ && $delete_qry =~ /scheme_id is null/ ) {
			$delete_qry = "DELETE FROM loci WHERE id IN ($delete_qry)";
			$delete_qry =~ s/SELECT \*/SELECT id/;
		} elsif ( $table eq 'sequence_bin' && $delete_qry =~ /JOIN experiment_sequences/ ) {
			$delete_qry = "DELETE FROM sequence_bin WHERE id IN ($delete_qry)";
			$delete_qry =~ s/SELECT \*/SELECT id/;
		} elsif ($table eq 'allele_sequences' && ($delete_qry =~ /JOIN sequence_flags/ || $delete_qry =~ /JOIN sequence_bin/ || $delete_qry =~ /JOIN scheme_members/)){
			$delete_qry =~ s/SELECT \*/SELECT allele_sequences.seqbin_id,allele_sequences.locus,allele_sequences.start_pos,allele_sequences.end_pos/;
			$delete_qry = "DELETE FROM allele_sequences WHERE (seqbin_id,locus,start_pos,end_pos) IN ($delete_qry)";
		} elsif ($table eq 'allele_designations' && ($delete_qry =~ /JOIN scheme_members/)){
			$delete_qry =~ s/SELECT \*/SELECT allele_designations.isolate_id,allele_designations.locus,allele_designations.allele_id/;
			$delete_qry = "DELETE FROM allele_designations WHERE (isolate_id,locus,allele_id) IN ($delete_qry)";
		}
		$delete_qry =~ s/^SELECT \*/DELETE/;
		my $scheme_ids;
		my $profiles_affected;
		my $schemes_affected;
		if ($table eq 'loci' && $delete_qry =~ /JOIN scheme_members/ && $delete_qry !~ /scheme_id is null/){
			$schemes_affected = 1;
		}
		my @allele_designations;
		my @history;
		if ( ( $table eq 'scheme_members' || $table eq 'scheme_fields' ) && $self->{'system'}->{'dbtype'} eq 'sequences' ) {

			#Find what schemes are affected, then recreate scheme view
			my $scheme_qry = $query;
			$scheme_qry =~ s/SELECT \*/SELECT scheme_id/;
			$scheme_qry =~ s/ORDER BY.*//;
			$scheme_ids = $self->{'datastore'}->run_list_query($scheme_qry);
		} elsif ( $table eq 'schemes' && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
			my $scheme_qry = $query;
			$scheme_qry =~ s/SELECT \*/SELECT id/;
			$scheme_qry =~ s/ORDER BY.*//;
			$scheme_ids = $self->{'datastore'}->run_list_query($scheme_qry);
		} elsif ( $table eq 'sequences' && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
			my $seq_qry = $query;
			$seq_qry =~ s/SELECT \*/SELECT locus,allele_id/;
			$seq_qry =~ s/ORDER BY.*//;
			my $seq_sql = $self->{'db'}->prepare($seq_qry);
			eval { $seq_sql->execute };
			$logger->error($@) if $@;
			my @alleles;
			while ( my ( $locus, $allele_id ) = $seq_sql->fetchrow_array ) {
				$locus =~ s/'/\\'/g;
				push @alleles, "locus='$locus' AND allele_id='$allele_id'";
			}
			if (@alleles) {
				$" = ') OR (';
				$profiles_affected =
				  $self->{'datastore'}->run_simple_query("SELECT COUNT (DISTINCT profile_id) FROM profile_members WHERE (@alleles)")->[0];
			}
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
		}
		if ($profiles_affected) {
			my $plural = $profiles_affected == 1 ? '' : 's';
			print
"<div class=\"box\" id=\"statusbad\"><p>Alleles are referenced by $profiles_affected allelic profile$plural - can not delete!</p></div>\n";
			return;
		} elsif ($schemes_affected) {
			print
			  "<div class=\"box\" id=\"statusbad\"><p>Deleting these loci would affect scheme definitions - can not delete!</p></div>\n";
			return;
		}
		eval {
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
			} elsif ($table eq 'sequences'){
				$self->mark_cache_stale;
			}
		};
		if ($@) {
			print "<div class=\"box\" id=\"statusbad\"><p>Delete failed - transaction cancelled - no records have been touched.</p>";
			if ( $@ =~ /foreign key/ ) {
				print "<p>Selected records are referred to by other tables and can not be deleted.</p></div>\n";
				$logger->debug($@);
			} else {
				print "<p>This is a bug in the software or database structure.  Please report this to the database administrator.
				More details will be available in the error log.</p></div>\n";
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
					if ( $q->param('delete_pending') ) {
						$self->delete_pending_designations( $isolate_id, $locus );
					} else {
						$self->promote_pending_allele_designation( $isolate_id, $locus );
					}
					if ( $self->can_modify_table('allele_sequences') && $q->param('delete_tags') ) {
						eval { $seqtag_sql->execute( $isolate_id, $locus ); };
						if ($@) {
							$logger->error($@);
							$commit = 0;
						}
					}
				}
				if ($commit){
					$self->{'db'}->commit;
				} else {
					$self->{'db'}->rollback;
				}
			}
			print "<div class=\"box\" id=\"resultsheader\"><p>Records deleted.</p>";
			print "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Return to index</a></p></div>\n";
		}
	} else {
		if (   ( $table eq 'scheme_fields' || $table eq 'scheme_members' )
			&& $self->{'system'}->{'dbtype'} eq 'sequences'
			&& !$q->param('sent') )
		{
			print
"<div class=\"box\" id=\"warning\"><p>Please be aware that any modifications to the structure of this scheme will result in the
			removal of all data from it. This is done to ensure data integrity.  This does not affect allele designations, but any profiles
			will have to be reloaded.</p></div>\n";
		}
		my $count_qry = $query;
		if (   ( $self->{'system'}->{'read_access'} eq 'acl' || ($self->{'system'}->{'write_access'} && $self->{'system'}->{'write_access'} eq 'acl' ))
			&& $self->{'username'}
			&& !$self->is_admin )
		{
			if ( $table eq 'allele_designations' || $table eq 'sequence_bin' || $table eq 'isolate_aliases' ) {
				$count_qry =~ s/WHERE/AND/;
				$count_qry =~ s/FROM $table/FROM $table WHERE isolate_id IN (SELECT id FROM $self->{'system'}->{'view'})/;
			} elsif ( $self->{'system'}->{'dbtype'} eq 'isolates' && ( $table eq 'allele_sequences' || $table eq 'accession' ) ) {
				$count_qry =~ s/WHERE/AND/;
				$count_qry =~
s/FROM $table/FROM $table LEFT JOIN sequence_bin ON $table.seqbin_id=sequence_bin.id WHERE isolate_id IN (SELECT id FROM $self->{'system'}->{'view'})/;
			}
		}
		if ($table eq 'allele_sequences'){
			$count_qry =~ s/SELECT \*/SELECT COUNT(DISTINCT allele_sequences.seqbin_id||allele_sequences.locus||allele_sequences.start_pos||allele_sequences.end_pos)/;
		} else {
			$count_qry =~ s/SELECT \*/SELECT COUNT\(\*\)/;
		}
		$count_qry =~ s/ORDER BY.*//;
		my ($count) = $self->{'datastore'}->run_simple_query($count_qry)->[0];
		my $plural = $count == 1 ? '' : 's';
		print "<div class=\"box\" id=\"statusbad\">\n";
		print "<p>If you proceed, you will delete $count $record_name record$plural.  Please confirm that this is your intention.</p>\n";
		print $q->start_form;
		$q->param( 'deleteAll', 1 );
		print $q->hidden($_) foreach qw (page db query deleteAll table delete_pending delete_tags);
		print $q->submit( -label => 'Confirm deletion!', -class => 'submit' );
		print $q->end_form;
		$self->print_warning_sign;
		print "</div>\n";
	}
}

sub get_title {
	my ($self) = @_;
	my $desc  = $self->{'system'}->{'description'} || 'BIGSdb';
	my $table = $self->{'cgi'}->param('table');
	my $type  = $self->get_record_name($table);
	return "Delete multiple $type records - $desc";
}
1;
