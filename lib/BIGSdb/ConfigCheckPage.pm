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
package BIGSdb::ConfigCheckPage;
use strict;
use warnings;
use base qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	print "<h1>Configuration check - $desc</h1>";
	if ( !( $self->{'permissions'}->{'modify_loci'} || $self->{'permissions'}->{'modify_schemes'} || $self->is_admin ) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>You do not have permission to view this page.</p></div>\n";
		return;
	}
	print "<div class=\"box\" id=\"resultstable\">\n";
	print "<h2>Helper applications</h2>\n";
	print
"<div class=\"scrollable\"><table class=\"resultstable\"><tr><th>Program</th><th>Path</th><th>Installed</th><th>Executable</th></tr>\n";
	my %helpers;
	{
		no warnings 'uninitialized';
		%helpers = (
			'EMBOSS sixpack'   => $self->{'config'}->{'emboss_path'} . '/sixpack',
			'EMBOSS stretcher' => $self->{'config'}->{'emboss_path'} . '/stretcher',
			'BLAST blastall'   => $self->{'config'}->{'blast_path'} . '/blastall',
			'blastn'           => $self->{'config'}->{'blast+_path'} . '/blastn',
			'blastp'           => $self->{'config'}->{'blast+_path'} . '/blastp',
			'blastx'           => $self->{'config'}->{'blast+_path'} . '/blastx',
			'tblastx'          => $self->{'config'}->{'blast+_path'} . '/tblastx',
			'makeblastdb'      => $self->{'config'}->{'blast+_path'} . '/makeblastdb',
			'MUSCLE'           => $self->{'config'}->{'muscle_path'},
			'ipcress'          => $self->{'config'}->{'ipcress_path'},
			'mogrify'          => $self->{'config'}->{'mogrify_path'},
		);
	}
	my $td = 1;
	foreach ( sort { $a cmp $b } keys %helpers ) {
		print "<tr class=\"td$td\"><td>$_</td><td>$helpers{$_}</td><td>"
		  . ( -e ( $helpers{$_} ) ? '<span class="statusgood">ok</span>' : '<span class="statusbad">X</span>' )
		  . "</td><td>"
		  . ( -x ( $helpers{$_} ) ? '<span class="statusgood">ok</span>' : '<span class="statusbad">X</span>' )
		  . "</td></tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	print "</table></div>\n";
	$| = 1;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		print "<h2>Locus databases</h2>\n";
		my $loci = $self->{'datastore'}->get_loci;
		my $buffer;
		$td = 1;
		foreach (@$loci) {
			my $locus_info = $self->{'datastore'}->get_locus_info($_);
			next if !$locus_info->{'dbase_name'};
			$buffer .= "<tr class=\"td$td\"><td>$_</td><td>$locus_info->{'dbase_name'}</td>
			<td>" . ( $locus_info->{'dbase_host'}      || 'localhost' ) . "</td>
			<td>" . ( $locus_info->{'dbase_port'}      || 5432 ) . "</td>
			<td>" . ( $locus_info->{'dbase_table'}     || '' ) . "</td>
			<td>" . ( $locus_info->{'dbase_id_field'}  || '' ) . "</td>
			<td>" . ( $locus_info->{'dbase_id2_field'} || '' ) . "</td>
			<td>" . ( $locus_info->{'dbase_id2_value'} || '' ) . "</td>
			<td>" . ( $locus_info->{'dbase_seq_field'} || '' ) . "</td><td>";
			eval {
				my $locus_db = $self->{'datastore'}->get_locus($_)->{'db'};
			};
			if ($@) {
				$buffer .= '<span class="statusbad">X</span>';
			} else {
				$buffer .= '<span class="statusgood">ok</span>';
			}
			$buffer .= "</td><td>";
			my $seq;
			eval { $seq = $self->{'datastore'}->get_locus($_)->get_allele_sequence('1'); };
			if ( $@ || ( ref $seq eq 'SCALAR' && defined $$seq && $$seq =~ /^\(/ ) ) {

				#seq can contain opening brace if sequence_field = table by mistake
				$logger->debug("$_; $@");
				$buffer .= '<span class="statusbad">X</span>';
			} else {
				$buffer .= '<span class="statusgood">ok</span>';
			}
			$buffer .= "</td><td>";
			my $seqs;
			eval { $seqs = $self->{'datastore'}->get_locus($_)->get_all_sequences; };
			if ( $@ || ( ref $seqs eq 'HASH' && scalar keys %$seqs == 0 ) ) {
				$logger->debug("$_; $@");
				$buffer .= '<span class="statusbad">X</span>';
			} else {
				$buffer .= '<span class="statusgood">' . scalar keys(%$seqs) . '</span>';
			}
			$buffer .= "</td></tr>\n";
			$td = $td == 1 ? 2 : 1;
		}
		if ($buffer) {
			print "<div class=\"scrollable\"><table class=\"resultstable\"><tr><th>Locus</th><th>Database</th><th>Host</th><th>Port</th>
			<th>Table</th><th>Primary id field</th><th>Secondary id field</th><th>Secondary id field value</th>
			<th>Sequence field</th><th>Database accessible</th><th>Sequence query</th><th>Sequences assigned</th></tr>\n";
			print $buffer;
			print "</table></div>\n";
		} else {
			print "<p>No loci with databases defined.</p>\n";
		}
		print "<h2>Scheme databases</h2>";
		my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes WHERE dbase_name IS NOT NULL ORDER BY id");
		undef $buffer;
		$td = 1;
		foreach (@$schemes) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($_);
			$scheme_info->{'description'} =~ s/&/&amp;/g;
			$buffer .= "<tr class=\"td$td\"><td>$scheme_info->{'description'}</td><td>" . ( $scheme_info->{'dbase_name'} || '' ) . "</td>
			<td>" . ( $scheme_info->{'dbase_host'}  || 'localhost' ) . "</td>
			<td>" . ( $scheme_info->{'dbase_port'}  || 5432 ) . "</td>
			<td>" . ( $scheme_info->{'dbase_table'} || '' ) . "</td><td>";
			if ( $self->{'datastore'}->get_scheme($_)->get_db ) {
				$buffer .= '<span class="statusgood">ok</span>';
			} else {
				$buffer .= '<span class="statusbad">X</span>';
			}
			$buffer .= "</td><td>";
			my $loci = $self->{'datastore'}->get_scheme_loci($_);
			my @values;
			foreach (@$loci) {
				push @values, '1';
			}
			eval { $self->{'datastore'}->get_scheme($_)->get_field_values_by_profile( \@values ); };
			if ($@) {
				$buffer .= '<span class="statusbad">X</span>';
			} else {
				$buffer .= '<span class="statusgood">ok</span>';
			}
			$buffer .= "</td></tr>\n";
			$td = $td == 1 ? 2 : 1;
		}
		if ($buffer) {
			print
"<div class=\"scrollable\"><table class=\"resultstable\"><tr><th>Scheme description</th><th>Database</th><th>Host</th><th>Port</th>
			<th>Table</th><th>Database accessible</th><th>Profile query</th></tr>\n";
			print $buffer;
			print "</table></div>\n";
		} else {
			print "<p>No schemes with databases defined.</p>\n";
		}
	} else {

		#profiles databases
		my $client_dbs = $self->{'datastore'}->run_list_query("SELECT id FROM client_dbases ORDER BY id");
		my $buffer;
		foreach (@$client_dbs) {
			my $client      = $self->{'datastore'}->get_client_db($_);
			my $client_info = $self->{'datastore'}->get_client_db_info($_);
			$buffer .=
"<tr class=\"td$td\"><td>$client_info->{'name'}</td><td>$client_info->{'description'}</td><td>$client_info->{'dbase_name'}</td><td>"
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
			print "<h2>Client databases</h2>\n";
			print
"<div class=\"scrollable\"><table class=\"resultstable\"><tr><th>Name</th><th>Description</th><th>Database</th><th>Host</th><th>Port</th><th>Database accessible</th></tr>";
			print $buffer;
			print "</table></div>\n";
		}
	}
	print "</div>\n";
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Configuration check - $desc";
}
1;
