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
package BIGSdb::ConfigCheckPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	say "<h1>Configuration check - $desc</h1>";
	if ( !( $self->{'permissions'}->{'modify_loci'} || $self->{'permissions'}->{'modify_schemes'} || $self->is_admin ) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>You do not have permission to view this page.</p></div>";
		return;
	}
	say "<div class=\"box\" id=\"resultstable\">";
	say "<h2>Helper applications</h2>";
	say "<div class=\"scrollable\"><table class=\"resultstable\"><tr><th>Program</th><th>Path</th><th>Installed</th>"
	  . "<th>Executable</th></tr>";
	my %helpers;
	{
		no warnings 'uninitialized';
		%helpers = (
			'EMBOSS infoalign' => $self->{'config'}->{'emboss_path'} . '/infoalign',
			'EMBOSS sixpack'   => $self->{'config'}->{'emboss_path'} . '/sixpack',
			'EMBOSS stretcher' => $self->{'config'}->{'emboss_path'} . '/stretcher',
			'blastn'           => $self->{'config'}->{'blast+_path'} . '/blastn',
			'blastp'           => $self->{'config'}->{'blast+_path'} . '/blastp',
			'blastx'           => $self->{'config'}->{'blast+_path'} . '/blastx',
			'tblastx'          => $self->{'config'}->{'blast+_path'} . '/tblastx',
			'makeblastdb'      => $self->{'config'}->{'blast+_path'} . '/makeblastdb',
			'mafft'            => $self->{'config'}->{'mafft_path'},
			'muscle'           => $self->{'config'}->{'muscle_path'},
			'ipcress'          => $self->{'config'}->{'ipcress_path'},
			'mogrify'          => $self->{'config'}->{'mogrify_path'},
		);
	}
	my $td = 1;
	foreach ( sort { $a cmp $b } keys %helpers ) {
		say "<tr class=\"td$td\"><td>$_</td><td>$helpers{$_}</td><td>"
		  . ( -e ( $helpers{$_} ) ? '<span class="statusgood">ok</span>' : '<span class="statusbad">X</span>' )
		  . "</td><td>"
		  . ( -x ( $helpers{$_} ) ? '<span class="statusgood">ok</span>' : '<span class="statusbad">X</span>' )
		  . "</td></tr>";
		$td = $td == 1 ? 2 : 1;
	}
	say "</table></div>";
	local $| = 1;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say "<h2>Locus databases</h2>";
		my $set_id = $self->get_set_id;
		my $set_clause =
		  $set_id
		  ? "AND (id IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes "
		  . "WHERE set_id=$set_id)) OR id IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
		  : '';
		my $loci = $self->{'datastore'}->run_list_query("SELECT id FROM loci WHERE dbase_name IS NOT null $set_clause ORDER BY id");
		$td = 1;
		if (@$loci) {
			say "<div class=\"scrollable\"><table class=\"resultstable\"><tr><th>Locus</th><th>Database</th><th>Host</th><th>Port</th>"
			  . "<th>Table</th><th>Primary id field</th><th>Secondary id field</th><th>Secondary id field value</th>"
			  . "<th>Sequence field</th><th>Database accessible</th><th>Sequence query</th><th>Sequences assigned</th></tr>";
			foreach (@$loci) {
				if ( $ENV{'MOD_PERL'} ) {
					$self->{'mod_perl_request'}->rflush;
					return if $self->{'mod_perl_request'}->connection->aborted;
				}
				my $locus_info = $self->{'datastore'}->get_locus_info($_);
				next if !$locus_info->{'dbase_name'};
				my $cleaned = $self->clean_locus($_);
				print "<tr class=\"td$td\"><td>$cleaned</td><td>$locus_info->{'dbase_name'}</td><td>"
				  . ( $locus_info->{'dbase_host'} || 'localhost' )
				  . "</td><td>"
				  . ( $locus_info->{'dbase_port'} || 5432 )
				  . "</td><td>"
				  . ( $locus_info->{'dbase_table'} || '' )
				  . "</td><td>"
				  . ( $locus_info->{'dbase_id_field'} || '' )
				  . "</td><td>"
				  . ( $locus_info->{'dbase_id2_field'} || '' )
				  . "</td><td>"
				  . ( $locus_info->{'dbase_id2_value'} || '' )
				  . "</td><td>"
				  . ( $locus_info->{'dbase_seq_field'} || '' )
				  . "</td><td>";
				my $locus_db = $self->{'datastore'}->get_locus($_)->{'db'};
				if ( !$locus_db ) {
					say '<span class="statusbad">X</span>';
				} else {
					say '<span class="statusgood">ok</span>';
				}
				print "</td><td>";
				my $seq;
				eval { $seq = $self->{'datastore'}->get_locus($_)->get_allele_sequence('1'); };
				if ( $@ || ( ref $seq eq 'SCALAR' && defined $$seq && $$seq =~ /^\(/ ) ) {

					#seq can contain opening brace if sequence_field = table by mistake
					$logger->debug("$_; $@");
					say '<span class="statusbad">X</span>';
				} else {
					say '<span class="statusgood">ok</span>';
				}
				say "</td><td>";
				my $seqs;
				eval { $seqs = $self->{'datastore'}->get_locus($_)->get_all_sequences; };
				if ( $@ || ( ref $seqs eq 'HASH' && scalar keys %$seqs == 0 ) ) {
					$logger->debug("$_; $@");
					say '<span class="statusbad">X</span>';
				} else {
					say '<span class="statusgood">' . scalar keys(%$seqs) . '</span>';
				}
				say "</td></tr>";
				$td = $td == 1 ? 2 : 1;
			}
			say "</table></div>";
		} else {
			say "<p>No loci with databases defined.</p>";
		}
		print "<h2>Scheme databases</h2>";
		$set_clause = $set_id ? "AND id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)" : '';
		my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes WHERE dbase_name IS NOT NULL $set_clause ORDER BY id");
		$td = 1;
		if (@$schemes) {
			say "<div class=\"scrollable\"><table class=\"resultstable\"><tr><th>Scheme description</th><th>Database</th>"
			  . "<th>Host</th><th>Port</th><th>Table</th><th>Database accessible</th><th>Profile query</th></tr>";
			foreach my $scheme_id (@$schemes) {
				my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
				$scheme_info->{'description'} =~ s/&/&amp;/g;
				print "<tr class=\"td$td\"><td>$scheme_info->{'description'}</td><td>"
				  . ( $scheme_info->{'dbase_name'} || '' )
				  . "</td><td>"
				  . ( $scheme_info->{'dbase_host'} || 'localhost' )
				  . "</td><td>"
				  . ( $scheme_info->{'dbase_port'} || 5432 )
				  . "</td><td>"
				  . ( $scheme_info->{'dbase_table'} || '' )
				  . "</td><td>";
				if ( $self->{'datastore'}->get_scheme($scheme_id)->get_db ) {
					print '<span class="statusgood">ok</span>';
				} else {
					print '<span class="statusbad">X</span>';
				}
				print "</td><td>";
				eval { $self->{'datastore'}->get_scheme($scheme_id)->get_field_values_by_designations( {} ) };
				if ($@) {
					print '<span class="statusbad">X</span>';
				} else {
					print '<span class="statusgood">ok</span>';
				}
				say "</td></tr>";
				$td = $td == 1 ? 2 : 1;
			}
			say "</table></div>";
		} else {
			say "<p>No schemes with databases defined.</p>";
		}
	} else {

		#profiles databases
		my $client_dbs = $self->{'datastore'}->run_list_query("SELECT id FROM client_dbases ORDER BY id");
		my $buffer;
		foreach (@$client_dbs) {
			my $client      = $self->{'datastore'}->get_client_db($_);
			my $client_info = $self->{'datastore'}->get_client_db_info($_);
			$buffer .=
			    "<tr class=\"td$td\"><td>$client_info->{'name'}</td><td>$client_info->{'description'}</td>"
			  . "<td>$client_info->{'dbase_name'}</td><td>"
			  . ( $client_info->{'dbase_host'} || 'localhost' ) . "</td>
			<td>" . ( $client_info->{'dbase_port'} || 5432 ) . "</td><td>";
			eval {
				my $sql = $client->get_db->prepare("SELECT * FROM allele_designations LIMIT 1");
				$sql->execute;
			};
			if ($@) {
				$buffer .= '<span class="statusbad">X</span>';
			} else {
				$buffer .= '<span class="statusgood">ok</span>';
			}
			$buffer .= "</td></tr>\n";
		}
		if ($buffer) {
			say "<h2>Client databases</h2>";
			say "<div class=\"scrollable\"><table class=\"resultstable\"><tr><th>Name</th><th>Description</th><th>Database</th>"
			  . "<th>Host</th><th>Port</th><th>Database accessible</th></tr>";
			say $buffer;
			say "</table></div>";
		}
	}
	say "</div>";
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Configuration check - $desc";
}
1;
