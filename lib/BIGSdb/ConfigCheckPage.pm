#Written by Keith Jolley
#Copyright (c) 2010-2016, University of Oxford
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
	say qq(<h1>Configuration check - $desc</h1>);
	if ( !( $self->{'permissions'}->{'modify_loci'} || $self->{'permissions'}->{'modify_schemes'} || $self->is_admin ) )
	{
		say q(<div class="box" id="statusbad"><p>You do not have permission to view this page.</p></div>);
		return;
	}
	$self->_check_helpers;
	local $| = 1;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->_check_locus_databases;
		$self->_check_scheme_databases;
	} else {
		$self->_check_client_databases;
	}
	return;
}

sub _check_helpers {
	my ($self) = @_;
	my %helpers;
	%helpers = (
		'EMBOSS infoalign' => $self->{'config'}->{'emboss_path'} . '/infoalign',
		'EMBOSS sixpack'   => $self->{'config'}->{'emboss_path'} . '/sixpack',
		'EMBOSS stretcher' => $self->{'config'}->{'emboss_path'} . '/stretcher',
		blastn             => $self->{'config'}->{'blast+_path'} . '/blastn',
		blastp             => $self->{'config'}->{'blast+_path'} . '/blastp',
		blastx             => $self->{'config'}->{'blast+_path'} . '/blastx',
		tblastx            => $self->{'config'}->{'blast+_path'} . '/tblastx',
		makeblastdb        => $self->{'config'}->{'blast+_path'} . '/makeblastdb',
		mafft              => $self->{'config'}->{'mafft_path'},
		muscle             => $self->{'config'}->{'muscle_path'},
		ipcress            => $self->{'config'}->{'ipcress_path'},
		mogrify            => $self->{'config'}->{'mogrify_path'},
	);
	my $td = 1;
	say q(<div class="box resultstable">);
	say q(<h2>Helper applications</h2>);
	say q(<div class="scrollable"><table class="resultstable"><tr><th>Program</th>)
	  . q(<th>Path</th><th>Installed</th><th>Executable</th></tr>);
	foreach my $program ( sort { $a cmp $b } keys %helpers ) {
		say qq(<tr class="td$td"><td>$program</td><td>$helpers{$program}</td><td>)
		  . (
			-e ( $helpers{$program} ) ? q(<span class="statusgood fa fa-check"></span>)
			: q(<span class="statusbad fa fa-times"></span>)
		  )
		  . q(</td><td>)
		  . (
			-x ( $helpers{$program} ) ? q(<span class="statusgood fa fa-check"></span>)
			: q(<span class="statusbad fa fa-times"></span>)
		  ) . q(</td></tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</table></div></div>);
	return;
}

sub _check_locus_databases {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box resultstable">);
	my $with_probs = $q->param('show_probs_only')
	  ? q[ (only showing loci with potential problems - ]
	  . qq[<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=configCheck">]
	  . q[show all loci</a>)]
	  : q[];
	say qq(<h2>Locus databases$with_probs</h2>);
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? 'AND (id IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes '
	  . 'WHERE set_id=$set_id)) OR id IN (SELECT locus FROM set_loci WHERE set_id=$set_id))'
	  : '';
	my $loci =
	  $self->{'datastore'}->run_query( "SELECT id FROM loci WHERE dbase_name IS NOT null $set_clause ORDER BY id",
		undef, { fetch => 'col_arrayref' } );
	my $td = 1;

	if (@$loci) {
		say q(<div class="scrollable"><table class="resultstable"><tr><th>Locus</th><th>Database</th>)
		  . q(<th>Host</th><th>Port</th><th>Table</th><th>Primary id field</th><th>Secondary id field</th>)
		  . q(<th>Secondary id field value</th><th>Sequence field</th><th>Database accessible</th>)
		  . q(<th>Sequence query</th><th>Sequences assigned</th></tr>);
	  LOCUS: foreach my $locus (@$loci) {
			if ( $ENV{'MOD_PERL'} ) {
				$self->{'mod_perl_request'}->rflush;
				return if $self->{'mod_perl_request'}->connection->aborted;
			}
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			next if !$locus_info->{'dbase_name'};
			my $cleaned  = $self->clean_locus($locus);
			my $locus_db = $self->{'datastore'}->get_locus($locus)->{'db'};
			my $buffer =
			    qq(<tr class="td$td"><td>$cleaned</td><td>$locus_info->{'dbase_name'}</td><td>)
			  . ( $locus_info->{'dbase_host'} // $self->{'system'}->{'host'} )
			  . q(</td><td>)
			  . ( $locus_info->{'dbase_port'} // $self->{'system'}->{'port'} )
			  . q(</td><td>)
			  . ( $locus_info->{'dbase_table'} // q() )
			  . q(</td><td>)
			  . ( $locus_info->{'dbase_id_field'} // q() )
			  . q(</td><td>)
			  . ( $locus_info->{'dbase_id2_field'} // q() )
			  . q(</td><td>)
			  . ( $locus_info->{'dbase_id2_value'} // q() )
			  . q(</td><td>)
			  . ( $locus_info->{'dbase_seq_field'} // q() )
			  . q(</td><td>);
			if ( !$locus_db ) {
				$buffer .= q(<span class="statusbad fa fa-times"></span>);
			} else {
				$buffer .= q(<span class="statusgood fa fa-check"></span>);
			}
			$buffer .= q(</td><td>);
			my $seq;
			eval { $seq = $self->{'datastore'}->get_locus($locus)->get_allele_sequence('1'); };
			if ( $@ || ( ref $seq eq 'SCALAR' && defined $$seq && $$seq =~ /^\(/x ) ) {

				#seq can contain opening brace if sequence_field = table by mistake
				$logger->debug("$locus; $@");
				$buffer .= q(<span class="statusbad fa fa-times"></span>);
			} else {
				$buffer .= q(<span class="statusgood fa fa-check"></span>);
			}
			$buffer .= q(</td><td>);
			my $seq_count;
			eval { $seq_count = $self->{'datastore'}->get_locus($locus)->get_sequence_count; };
			if ( $@ || ( $seq_count == 0 ) ) {
				$logger->debug("$locus; $@");
				$buffer .= q(<span class="statusbad fa fa-times"></span>);
			} else {
				$buffer .= qq(<span class="statusgood">$seq_count</span>);
				next LOCUS if $q->param('show_probs_only');
			}
			$buffer .= q(</td></tr>);
			say $buffer;
			$td = $td == 1 ? 2 : 1;
		}
		say q(</table></div>);
	} else {
		say q(<p class="statusbad">No loci with databases defined.</p>);
	}
	say q(</div>);
	return;
}

sub _check_scheme_databases {
	my ($self) = @_;
	say q(<div class="box resultstable">);
	say q(<h2>Scheme databases</h2>);
	my $set_id = $self->get_set_id;
	my $set_clause = $set_id ? "AND id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)" : '';
	my $schemes =
	  $self->{'datastore'}->run_query( "SELECT id FROM schemes WHERE dbase_name IS NOT NULL $set_clause ORDER BY id",
		undef, { fetch => 'col_arrayref' } );
	my $td = 1;
	if (@$schemes) {
		say q(<div class="scrollable"><table class="resultstable"><tr><th>Scheme description</th><th>Database</th>)
		  . q(<th>Host</th><th>Port</th><th>Table</th><th>Database accessible</th><th>Profile query</th></tr>);
		foreach my $scheme_id (@$schemes) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
			$scheme_info->{'description'} =~ s/&/&amp;/gx;
			print qq(<tr class="td$td"><td>$scheme_info->{'description'}</td><td>)
			  . ( $scheme_info->{'dbase_name'} // q() )
			  . q(</td><td>)
			  . ( $scheme_info->{'dbase_host'} // $self->{'system'}->{'host'} )
			  . q(</td><td>)
			  . ( $scheme_info->{'dbase_port'} // $self->{'system'}->{'port'} )
			  . q(</td><td>)
			  . ( $scheme_info->{'dbase_table'} // q() )
			  . q(</td><td>);
			if ( $self->{'datastore'}->get_scheme($scheme_id)->get_db ) {
				print q(<span class="statusgood fa fa-check"></span>);
			} else {
				print q(<span class="statusbad fa fa-times"></span>);
			}
			print q(</td><td>);
			eval { $self->{'datastore'}->get_scheme($scheme_id)->get_field_values_by_designations( {} ) };
			if ($@) {
				print q(<span class="statusbad fa fa-times"></span>);
			} else {
				print q(<span class="statusgood fa fa-check"></span>);
			}
			say q(</td></tr>);
			$td = $td == 1 ? 2 : 1;
		}
		say q(</table></div></div>);
	} else {
		say q(<p>No schemes with databases defined.</p>);
	}
	return;
}

sub _check_client_databases {
	my ($self) = @_;
	my $client_dbs =
	  $self->{'datastore'}->run_query( 'SELECT id FROM client_dbases ORDER BY id', undef, { fetch => 'col_arrayref' } );
	my $buffer;
	my $td = 1;
	foreach (@$client_dbs) {
		my $client      = $self->{'datastore'}->get_client_db($_);
		my $client_info = $self->{'datastore'}->get_client_db_info($_);
		$buffer .=
		    qq(<tr class="td$td"><td>$client_info->{'name'}</td><td>$client_info->{'description'}</td>)
		  . qq(<td>$client_info->{'dbase_name'}</td><td>)
		  . ( $client_info->{'dbase_host'} // $self->{'system'}->{'host'} )
		  . q(</td><td>)
		  . ( $client_info->{'dbase_port'} // $self->{'system'}->{'port'} )
		  . q(</td><td>);
		eval {
			my $sql = $client->get_db->prepare('SELECT * FROM allele_designations LIMIT 1');
			$sql->execute;
		};
		if ($@) {
			$buffer .= q(<span class="statusbad fa fa-times"></span>);
		} else {
			$buffer .= q(<span class="statusgood fa fa-check"></span>);
		}
		$buffer .= "</td></tr>\n";
	}
	if ($buffer) {
		say q(<div class="box resultstable">);
		say q(<h2>Client databases</h2>);
		say q(<div class="scrollable"><table class="resultstable"><tr><th>Name</th><th>Description</th>)
		  . q(<th>Database</th><th>Host</th><th>Port</th><th>Database accessible</th></tr>);
		say $buffer;
		say q(</table></div></div>);
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Configuration check - $desc";
}
1;
