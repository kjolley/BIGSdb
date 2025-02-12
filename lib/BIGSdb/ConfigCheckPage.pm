#Written by Keith Jolley
#Copyright (c) 2010-2025, University of Oxford
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
package BIGSdb::ConfigCheckPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use BIGSdb::Constants qw(GOOD BAD);
use constant {
	PG_MAJOR => 9,
	PG_MINOR => 5
};
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	say qq(<h1>Configuration check - $desc</h1>);
	if ( !( $self->{'permissions'}->{'modify_loci'} || $self->{'permissions'}->{'modify_schemes'} || $self->is_admin ) )
	{
		$self->print_bad_status( { message => q(You do not have permission to view this page.), navbar => 1 } );
		return;
	}
	$self->_check_postgres;
	$self->_check_helpers;
	local $| = 1;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->_check_locus_databases;
		$self->_check_scheme_databases;
		$self->_check_classification_scheme_databases;
		$self->_check_oauth_credentials;
	} else {
		$self->_check_client_databases;
	}
	return;
}

sub _check_postgres {
	my ($self) = @_;
	say q(<div class="box resultstable">);
	say q(<h2>PostgreSQL</h2>);
	my $version = $self->{'datastore'}->run_query('SHOW server_version');
	my $status  = q();
	if ( $version =~ /^(\d+)\.(\d+)\.?\d*\s/x ) {
		my ( $major, $minor ) = ( $1, $2 );
		$version = "$major.$minor";
		if ( $major > PG_MAJOR ) {
			$status = GOOD;
		} elsif ( $major == PG_MAJOR && $minor >= PG_MINOR ) {
			$status = GOOD;
		} else {
			$status = BAD;
		}
	}
	my $required = PG_MAJOR . '.' . PG_MINOR;
	say qq(<p>BIGSdb requires Pg $required or higher. You are running version $version. $status);
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
		clustalw           => $self->{'config'}->{'clustalw_path'},
		ipcress            => $self->{'config'}->{'ipcress_path'},
		GrapeTree          => $self->{'config'}->{'grapetree_path'},
		blat               => $self->{'config'}->{'blat_path'},
		weasyprint         => $self->{'config'}->{'weasyprint_path'},
		snp_sites          => $self->{'config'}->{'snp_sites_path'}
	);
	my $td = 1;
	say q(<h2>Helper applications</h2>);
	say q(<div class="scrollable"><table class="resultstable"><tr><th>Program</th>)
	  . q(<th>Path</th><th>Installed</th><th>Executable</th></tr>);
	foreach my $program ( sort { $a cmp $b } keys %helpers ) {
		my $status;
		if ( defined $helpers{'GrapeTree'} && $program eq 'GrapeTree' ) {
			my @files;
			my $all_present = 1;
			if ( !defined $self->{'config'}->{'python3_path'} && $self->{'config'}->{'grapetree_path'} =~ /python/x ) {

				#Path includes full command for running GrapeTree (recommended)
				@files = split( ' ', $self->{'config'}->{'grapetree_path'} );
			} else {

				#Separate variables for GrapeTree directory and Python path (legacy)
				push @files, ( $self->{'config'}->{'python3_path'} // '/usr/bin/python3' );
				push @files, "$self->{'config'}->{'grapetree_path'}/grapetree.py";
			}
			foreach my $file (@files) {    #Split Python interpreter and GrapeTree file
				$all_present = 0 if !-e $file;
			}
			$status = $all_present ? GOOD : BAD;
		} else {
			$status = defined $helpers{$program} && -e ( $helpers{$program} ) ? GOOD : BAD;
		}
		$helpers{$program} //= 'PATH NOT DEFINED';
		say qq(<tr class="td$td"><td>$program</td><td>$helpers{$program}</td><td>$status</td><td>);
		if ( $program ne 'GrapeTree' ) {    #Python script doesn't need to be executable
			say -x ( $helpers{$program} ) ? GOOD : BAD;
		}
		say q(</td></tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</table></div></div>);
	return;
}

sub _check_locus_databases {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box resultstable">);
	my $with_probs =
	  $q->param('show_probs_only')
	  ? q[ (only showing loci with potential problems - ]
	  . qq[<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=configCheck">]
	  . q[show all loci</a>)]
	  : q[];
	say qq(<h2>Locus databases$with_probs</h2>);
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? 'AND (id IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes '
	  . "WHERE set_id=$set_id)) OR id IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';
	my $loci =
	  $self->{'datastore'}->run_query( "SELECT id FROM loci WHERE dbase_name IS NOT null $set_clause ORDER BY id",
		undef, { fetch => 'col_arrayref' } );
	my $td = 1;

	if (@$loci) {
		say q(<div class="scrollable"><table class="resultstable"><tr><th>Locus</th><th>Database</th>)
		  . q(<th>Host</th><th>Port</th><th>Id field value</th><th>Database accessible</th>)
		  . q(<th>Sequence query</th><th>Sequences assigned</th></tr>);
	  LOCUS: foreach my $locus (@$loci) {
			if ( $ENV{'MOD_PERL'} ) {
				eval { $self->{'mod_perl_request'}->rflush };
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
			  . ( $locus_info->{'dbase_id'} // q() )
			  . q(</td><td>);
			if ( !$locus_db ) {
				$buffer .= BAD;
			} else {
				$buffer .= GOOD;
			}
			$buffer .= q(</td><td>);
			my $seq;
			my $seq_query_ok = 1;
			eval { $seq = $self->{'datastore'}->get_locus($locus)->get_allele_sequence('1'); };
			if ( $@ || ( ref $seq eq 'SCALAR' && defined $$seq && $$seq =~ /^\(/x ) ) {

				#seq can contain opening brace if sequence_field = table by mistake
				$logger->debug("$locus; $@");
				$buffer .= BAD;
				$seq_query_ok = 0;
			} else {
				$buffer .= GOOD;
			}
			$buffer .= q(</td><td>);
			my $locus_stats;
			eval { $locus_stats = $self->{'datastore'}->get_locus($locus)->get_stats; };
			if ( $@ || ( !$locus_stats->{'allele_count'} ) ) {
				$logger->debug("$locus; $@");
				$buffer .= BAD;
			} else {
				$buffer .= qq(<span class="statusgood">$locus_stats->{'allele_count'}</span>);
				next LOCUS if $q->param('show_probs_only') && $seq_query_ok;
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
	my $set_id     = $self->get_set_id;
	my $set_clause = $set_id ? "AND id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)" : '';
	my $schemes =
	  $self->{'datastore'}->run_query( "SELECT id FROM schemes WHERE dbase_name IS NOT NULL $set_clause ORDER BY id",
		undef, { fetch => 'col_arrayref' } );
	my $td = 1;
	if (@$schemes) {
		say q(<div class="scrollable"><table class="resultstable"><tr><th>Scheme description</th><th>Database</th>)
		  . q(<th>Host</th><th>Port</th><th>Id</th><th>Database accessible</th><th>Profile query</th></tr>);
		foreach my $scheme_id (@$schemes) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
			$scheme_info->{'name'} =~ s/&/&amp;/gx;
			print qq(<tr class="td$td"><td>$scheme_info->{'name'}</td><td>)
			  . ( $scheme_info->{'dbase_name'} // q() )
			  . q(</td><td>)
			  . ( $scheme_info->{'dbase_host'} // $self->{'system'}->{'host'} )
			  . q(</td><td>)
			  . ( $scheme_info->{'dbase_port'} // $self->{'system'}->{'port'} )
			  . q(</td><td>)
			  . ( $scheme_info->{'dbase_id'} // q() )
			  . q(</td><td>);
			eval { $self->{'datastore'}->get_scheme($scheme_id)->get_db };
			if ($@) {
				print BAD;
			} else {
				print GOOD;
			}
			print q(</td><td>);
			if ( !$scheme_info->{'primary_key'} ) {
				$logger->error("No primary key field set for scheme#$scheme_id ($scheme_info->{'name'}).");
				print BAD;
				next;
			}
			eval { $self->{'datastore'}->get_scheme($scheme_id)->get_field_values_by_designations( {} ) };
			if ($@) {
				print BAD;
			} else {
				print GOOD;
			}
			say q(</td></tr>);
			$td = $td == 1 ? 2 : 1;
		}
		say q(</table></div></div>);
	} else {
		say q(<p>No schemes with databases defined.</p></div>);
	}
	return;
}

sub _check_classification_scheme_databases {
	my ($self) = @_;
	my $cschemes =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id FROM classification_schemes ORDER BY id', undef, { fetch => 'col_arrayref' } );
	return if !@$cschemes;
	say q(<div class="box resultstable">);
	say q(<h2>Classification scheme databases</h2>);
	my $td = 1;
	if (@$cschemes) {
		say q(<div class="scrollable"><table class="resultstable"><tr><th>Classification scheme</th>)
		  . q(<th>Scheme</th><th>Database</th><th>Host</th><th>Port</th><th>Id</th><th>Database accessible</th>)
		  . q(<th>Seqdef classification scheme id</th><th>Classification data</th></tr>);
		foreach my $cscheme_id (@$cschemes) {
			my $cscheme_info = $self->{'datastore'}->get_classification_scheme_info($cscheme_id);
			my $scheme_info  = $self->{'datastore'}->get_scheme_info( $cscheme_info->{'scheme_id'} );
			$cscheme_info->{'name'} =~ s/&/&amp;/gx;
			$scheme_info->{'name'}  =~ s/&/&amp;/gx;
			print qq(<tr class="td$td"><td>$cscheme_info->{'id'}: $cscheme_info->{'name'}</td><td>)
			  . ("$scheme_info->{'id'}: $scheme_info->{'name'}")
			  . q(</td><td>)
			  . ( $scheme_info->{'dbase_name'} // q() )
			  . q(</td><td>)
			  . ( $scheme_info->{'dbase_host'} // $self->{'system'}->{'host'} )
			  . q(</td><td>)
			  . ( $scheme_info->{'dbase_port'} // $self->{'system'}->{'port'} )
			  . q(</td><td>)
			  . ( $scheme_info->{'dbase_id'} // q() )
			  . q(</td><td>);
			if ( $self->{'datastore'}->get_classification_scheme($cscheme_id)->get_db ) {
				print GOOD;
			} else {
				print BAD;
			}
			print qq(</td><td>$cscheme_info->{'seqdef_cscheme_id'}</td><td>);
			my $seqdef_db = $self->{'datastore'}->get_scheme( $cscheme_info->{'scheme_id'} )->get_db;
			my $exists    = $self->{'datastore'}->run_query(
				'SELECT EXISTS(SELECT * FROM classification_group_profiles WHERE cg_scheme_id=?)',
				$cscheme_info->{'seqdef_cscheme_id'},
				{ db => $seqdef_db }
			);
			if ($exists) {
				print GOOD;
			} else {
				print BAD;
			}
			my $classification_data = say q(</td></tr>);
			$td = $td == 1 ? 2 : 1;
		}
		say q(</table></div>);
	} else {
		say q(<p>No schemes with databases defined.</p>);
	}
	say q(</div>);
	return;
}

sub _check_oauth_credentials {
	my ($self) = @_;
	my $credentials = $self->{'datastore'}->run_query( 'SELECT * FROM oauth_credentials ORDER BY base_uri',
		undef, { fetch => 'all_arrayref', slice => {} } );
	return if !@$credentials;
	say q(<div class="box resultstable">);
	say q(<h2>OAuth credentials</h2>);
	say q(<table class="resultstable"><tr><th>Base URI</th><th>Accessible</th></tr>);
	my $td = 1;
	foreach my $details (@$credentials) {
		say qq(<tr class="td$td"><td>$details->{'base_uri'}</td><td>);
		my $ok = $self->{'contigManager'}->is_config_ok( $details->{'base_uri'} );
		say $ok ? GOOD : BAD;
		say q(</td></tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</table>);
	say q(</div>);
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
			$buffer .= BAD;
		} else {
			$buffer .= GOOD;
		}
		$buffer .= qq(</td></tr>\n);
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
	return 'Configuration check';
}
1;
