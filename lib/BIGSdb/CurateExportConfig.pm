#Written by Keith Jolley
#Copyright (c) 2011-2016, University of Oxford
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
	if (   !$self->{'datastore'}->is_table($table)
		&& !( $table eq 'samples' && @{ $self->{'xmlHandler'}->get_sample_field_list } ) )
	{
		say "Table '$table' is not defined.";
		return;
	}
	my $query_file = $q->param('query_file');
	my $qry        = $self->get_query_from_temp_file($query_file);
	if ( $q->param('list_file') ) {
		$self->{'datastore'}->create_temp_list_table( 'text', $q->param('list_file') );
	}
	if ( !$qry ) {
		say q(No query passed.);
		return;
	}
	if ( any { lc($qry) =~ /;\s*$_\s/x } (qw (insert delete update alter create drop)) ) {
		say q(Invalid query passed.);
		$logger->warn("Malicious SQL injection attempt '$qry'");
		return;
	}
	$self->_print_table_data( $table, $qry );
	if ( any { $table eq $_ } qw (user_groups projects experiments pcr probes schemes scheme_groups client_dbases) ) {
		my $parent_query = $qry;
		$parent_query =~ s/\*/id/x;
		$parent_query =~ s/ORDER\ BY.*//x;
		my %methods = (
			projects => sub {
				$qry = 'SELECT * FROM project_members WHERE project_id IN '
				  . "($parent_query) ORDER BY project_id,isolate_id";
				$self->_print_table_data( 'project_members', $qry );
			},
			experiments => sub {
				$qry = 'SELECT * FROM experiment_sequences WHERE experiment_id IN '
				  . "($parent_query) ORDER BY experiment_id,seqbin_id";
				$self->_print_table_data( 'experiment_sequences', $qry );
			},
			pcr => sub {
				$qry = "SELECT * FROM pcr_locus WHERE pcr_id IN ($parent_query) ORDER BY pcr_id,locus";
				$self->_print_table_data( 'pcr_locus', $qry );
			},
			probes => sub {
				$qry = "SELECT * FROM probe_locus WHERE probe_id IN ($parent_query) ORDER BY probe_id,locus";
				$self->_print_table_data( 'probe_locus', $qry );
			},
			schemes => sub {
				$qry = "SELECT * FROM scheme_members WHERE scheme_id IN ($parent_query) ORDER BY scheme_id,locus";
				$self->_print_table_data( 'scheme_members', $qry );
				$qry = "SELECT * FROM scheme_fields WHERE scheme_id IN ($parent_query) ORDER BY scheme_id,field";
				print "\n";
				$self->_print_table_data( 'scheme_fields', $qry );
			},
			scheme_groups => sub {
				$qry =
				    'SELECT * FROM scheme_group_group_members WHERE parent_group_id IN '
				  . "($parent_query) ORDER BY parent_group_id,group_id";
				$self->_print_table_data( 'scheme_group_group_members', $qry );
				$qry =
				    'SELECT * FROM scheme_group_scheme_members WHERE group_id IN '
				  . "($parent_query) ORDER BY group_id,scheme_id";
				print "\n";
				$self->_print_table_data( 'scheme_group_scheme_members', $qry );
			},
			user_groups => sub {
				$qry = 'SELECT * FROM user_group_members WHERE user_group IN '
				  . "($parent_query) ORDER BY user_id,user_group";
				$self->_print_table_data( 'user_group_members', $qry );
			},
			client_dbases => sub {
				$qry =
				    'SELECT * FROM client_dbase_loci WHERE client_dbase_id IN '
				  . "($parent_query) ORDER BY client_dbase_id,locus";
				$self->_print_table_data( 'client_dbase_loci', $qry );
				$qry =
				    'SELECT * FROM client_dbase_schemes WHERE client_dbase_id IN '
				  . "($parent_query) ORDER BY client_dbase_id,scheme_id";
				print "\n";
				$self->_print_table_data( 'client_dbase_schemes', $qry );
			}
		);
		if ( $methods{$table} ) {
			print "\n";
			$methods{$table}->();
		}
	}
	return;
}

sub _print_table_data {
	my ( $self, $table, $qry ) = @_;
	if ( $table eq 'allele_sequences' && $qry =~ /sequence_flags/ ) {
		$qry =~ s/SELECT\ \*/SELECT DISTINCT \*/x;
	}
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my ( @header, @fields );
	foreach (@$attributes) {
		push @header, $_->{'name'};
		push @fields, "$table.$_->{'name'}";
	}
	local $" = qq(\t);
	say $table;
	print q(-) x length $table;
	print qq(\n);
	say qq(@header);
	local $" = q(,);
	my $fields = qq(@fields);
	$qry =~ s/\*/$fields/x;
	my $dataset = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	$self->modify_dataset_if_needed( $table, $dataset );
	local $" = qq(\t);

	foreach my $data (@$dataset) {
		no warnings 'uninitialized';
		my $first = 1;
		foreach my $att (@$attributes) {
			print qq(\t) if !$first;
			print qq($data->{lc $att->{'name'}});
			$first = 0;
		}
		print qq(\n);
	}
	return;
}
1;
