#Written by Keith Jolley
#Copyright (c) 2011-2013, University of Oxford
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
package BIGSdb::CurateExportConfig;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{'type'} = 'text';
	return;
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $table  = $q->param('table');
	if ( !$self->{'datastore'}->is_table($table) && !( $table eq 'samples' && @{ $self->{'xmlHandler'}->get_sample_field_list } ) ) {
		say "Table '$table' is not defined.";
		return;
	}
	my $query_file = $q->param('query_file');
	my $qry        = $self->get_query_from_temp_file($query_file);
	if ( !$qry ) {
		say "No query passed.";
		return;
	}
	if ( any { lc($qry) =~ /;\s*$_\s/ } (qw (insert delete update alter create drop)) ) {
		say "Invalid query passed.";
		$logger->warn("Malicious SQL injection attempt '$qry'");
		return;
	}
	$self->_print_table_data( $table, $qry );
	if ( any { $table eq $_ } qw (user_groups projects experiments pcr probes schemes scheme_groups client_dbases) ) {
		my $parent_query = $qry;
		$parent_query =~ s/\*/id/;
		$parent_query =~ s/ORDER BY.*//;
		if ( $table eq 'projects' ) {
			$qry = "SELECT * FROM project_members WHERE project_id IN ($parent_query\) ORDER BY project_id,isolate_id";
			print "\n";
			$self->_print_table_data( 'project_members', $qry );
		} elsif ( $table eq 'experiments' ) {
			$qry = "SELECT * FROM experiment_sequences WHERE experiment_id IN ($parent_query\) ORDER BY experiment_id,seqbin_id";
			print "\n";
			$self->_print_table_data( 'experiment_sequences', $qry );
		} elsif ( $table eq 'pcr' ) {
			$qry = "SELECT * FROM pcr_locus WHERE pcr_id IN ($parent_query\) ORDER BY pcr_id,locus";
			print "\n";
			$self->_print_table_data( 'pcr_locus', $qry );
		} elsif ( $table eq 'probes' ) {
			$qry = "SELECT * FROM probe_locus WHERE probe_id IN ($parent_query\) ORDER BY probe_id,locus";
			print "\n";
			$self->_print_table_data( 'probe_locus', $qry );
		} elsif ( $table eq 'schemes' ) {
			$qry = "SELECT * FROM scheme_members WHERE scheme_id IN ($parent_query\) ORDER BY scheme_id,locus";
			print "\n";
			$self->_print_table_data( 'scheme_members', $qry );
			$qry = "SELECT * FROM scheme_fields WHERE scheme_id IN ($parent_query\) ORDER BY scheme_id,field";
			print "\n";
			$self->_print_table_data( 'scheme_fields', $qry );
		} elsif ( $table eq 'scheme_groups' ) {
			$qry = "SELECT * FROM scheme_group_group_members WHERE parent_group_id IN ($parent_query\) ORDER BY parent_group_id,group_id";
			print "\n";
			$self->_print_table_data( 'scheme_group_group_members', $qry );
			$qry = "SELECT * FROM scheme_group_scheme_members WHERE group_id IN ($parent_query\) ORDER BY group_id,scheme_id";
			print "\n";
			$self->_print_table_data( 'scheme_group_scheme_members', $qry );
		} elsif ( $table eq 'user_groups' ) {
			$qry = "SELECT * FROM user_group_members WHERE user_group IN ($parent_query\) ORDER BY user_id,user_group";
			print "\n";
			$self->_print_table_data( 'user_group_members', $qry );
		} elsif ( $table eq 'client_dbases' ) {
			$qry = "SELECT * FROM client_dbase_loci WHERE client_dbase_id IN ($parent_query\) ORDER BY client_dbase_id,locus";
			print "\n";
			$self->_print_table_data( 'client_dbase_loci', $qry );
			$qry = "SELECT * FROM client_dbase_schemes WHERE client_dbase_id IN ($parent_query\) ORDER BY client_dbase_id,scheme_id";
			print "\n";
			$self->_print_table_data( 'client_dbase_schemes', $qry );
		}
	}
	return;
}

sub _print_table_data {
	my ( $self, $table, $qry ) = @_;
	if ( $table eq 'allele_sequences' && $qry =~ /sequence_flags/ ) {
		$qry =~ s/SELECT \*/SELECT DISTINCT \*/;
	}
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my ( @header, @fields );
	foreach (@$attributes) {
		push @header, $_->{'name'};
		push @fields, "$table.$_->{'name'}";
	}
	local $" = "\t";
	say "$table";
	print '-' x length $table;
	print "\n";
	say "@header";
	local $" = ',';
	my $fields = "@fields";
	$qry =~ s/\*/$fields/;
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error($@) if $@;
	local $" = "\t";

	while ( my @data = $sql->fetchrow_array ) {
		no warnings 'uninitialized';
		say "@data";
	}
	return;
}
1;
