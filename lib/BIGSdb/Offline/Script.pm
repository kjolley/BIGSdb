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
package BIGSdb::Offline::Script;
use strict;
use warnings;
use parent qw(BIGSdb::Application);
use CGI;
use DBI;
use Error qw(:try);
use Log::Log4perl qw(get_logger);
use List::MoreUtils qw(any uniq);
use BIGSdb::Dataconnector;
use BIGSdb::Datastore;
use BIGSdb::BIGSException;
use BIGSdb::Parser;
$ENV{'PATH'} = '/bin:/usr/bin';              ##no critic #so we don't foul taint check
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};    # Make %ENV safer

sub new {
	my ( $class, $options ) = @_;
	my $self = {};
	$self->{'system'}           = {};
	$self->{'config'}           = {};
	$self->{'cgi'}              = CGI->new;
	$self->{'xmlHandler'}       = undef;
	$self->{'invalidXML'}       = 0;
	$self->{'dataConnector'}    = BIGSdb::Dataconnector->new;
	$self->{'datastore'}        = undef;
	$self->{'pluginManager'}    = undef;
	$self->{'db'}               = undef;
	$self->{'options'}          = $options->{'options'};
	$self->{'params'}           = $options->{'params'};
	$self->{'instance'}         = $options->{'instance'};
	$self->{'logger'}           = $options->{'logger'};
	$self->{'config_dir'}       = $options->{'config_dir'};
	$self->{'lib_dir'}          = $options->{'lib_dir'};
	$self->{'dbase_config_dir'} = $options->{'dbase_config_dir'};
	$self->{'host'}             = $options->{'host'};
	$self->{'port'}             = $options->{'port'};
	$self->{'user'}             = $options->{'user'};
	$self->{'password'}         = $options->{'password'};
	bless( $self, $class );

	if ( !defined $self->{'logger'} ) {
		Log::Log4perl->init_once("$self->{'config_dir'}/script_logging.conf");
		$self->{'logger'} = get_logger('BIGSdb.Script');
	}
	$self->_go;
	return $self;
}

sub initiate {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $full_path = "$self->{'dbase_config_dir'}/$self->{'instance'}/config.xml";
	$self->{'xmlHandler'} = BIGSdb::Parser->new;
	my $parser = XML::Parser::PerlSAX->new( Handler => $self->{'xmlHandler'} );
	eval { $parser->parse( Source => { SystemId => $full_path } ); };
	if ($@) {
		$self->{'logger'}->fatal("Invalid XML description: $@") if $self->{'instance'} ne '';
		return;
	}
	$self->{'system'} = $self->{'xmlHandler'}->get_system_hash;
	$self->{'system'}->{'host'}     = $self->{'host'}     || 'localhost';
	$self->{'system'}->{'port'}     = $self->{'port'}     || 5432;
	$self->{'system'}->{'user'}     = $self->{'user'}     || 'apache';
	$self->{'system'}->{'password'} = $self->{'password'} || 'remote';
	$self->{'system'}->{'locus_superscript_prefix'} ||= 'no';
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->{'system'}->{'view'}       ||= 'isolates';
		$self->{'system'}->{'labelfield'} ||= 'isolate';
		if ( !$self->{'xmlHandler'}->is_field( $self->{'system'}->{'labelfield'} ) ) {
			$self->{'logger'}->error( "The defined labelfield '$self->{'system'}->{'labelfield'}' does not exist in the database.  "
				  . "Please set the labelfield attribute in the system tag of the database XML file." );
		}
	}
	$self->set_system_overrides;
	$self->{'dataConnector'}->initiate( $self->{'system'}, $self->{'config'} );
	$self->db_connect;
	$self->setup_datastore if $self->{'db'};
	return;
}

sub get_load_average {
	my $uptime = `uptime`;
	return $1 if $uptime =~ /load average:\s+([\d\.]+)/;
	throw BIGSdb::DataException("Can't determine load average");
}

sub _go {
	my ($self) = @_;
	my $load_average;
	$self->read_config_file( $self->{'config_dir'} );
	my $max_load = $self->{'config'}->{'max_load'} || 8;
	try {
		$load_average = $self->get_load_average;
	}
	catch BIGSdb::DataException with {
		$self->{'logger'}->fatal("Can't determine load average ... aborting!");
		exit;
	};
	if ( $load_average > $max_load ) {
		$self->{'logger'}->info("Load average = $load_average. Threshold is set at $max_load. Aborting.");
		if ( $self->{'options'}->{'throw_busy_exception'} ) {
			throw BIGSdb::ServerBusyException("Exception: Load average = $load_average");
		}
		return;
	}
	$self->read_host_mapping_file( $self->{'config_dir'} );
	$self->initiate;
	$self->run_script;
	return;
}

sub run_script {

	#override in subclass
}

sub get_isolates_with_linked_seqs {

	#options set in $self->{'options}
	#$self->{'options}->{'p'}: comma-separated list of projects
	#$self->{'options}->{'i'}: comma-separated list of isolate ids (ignored if 'p' used)
	my ($self) = @_;
	my $qry;
	local $" = ',';
	if ( $self->{'options'}->{'p'} ) {
		my @projects = split /,/, $self->{'options'}->{'p'};
		die "Invalid project list.\n" if any { !BIGSdb::Utils::is_int($_) } @projects;
		$qry = "SELECT DISTINCT isolate_id FROM sequence_bin WHERE isolate_id IN (SELECT isolate_id FROM project_members WHERE project_id "
		  . "IN (@projects)) AND isolate_id IN (SELECT id FROM $self->{'system'}->{'view'})";
	} elsif ( $self->{'options'}->{'i'} ) {
		my @ids = split /,/, $self->{'options'}->{'i'};
		die "Invalid isolate id list.\n" if any { !BIGSdb::Utils::is_int($_) } @ids;
		$qry = "SELECT DISTINCT isolate_id FROM sequence_bin WHERE isolate_id IN (@ids) AND isolate_id IN (SELECT id FROM "
		  . "$self->{'system'}->{'view'})";
	} else {
		$qry = "SELECT DISTINCT isolate_id FROM sequence_bin WHERE isolate_id IN (SELECT id FROM $self->{'system'}->{'view'})";
	}
	$qry .= " ORDER BY isolate_id";
	return $self->{'datastore'}->run_list_query($qry);
}

sub get_loci_with_ref_db {

	#options set in $self->{'options}
	#$self->{'options}->{'s'}: comma-separated list of schemes
	#$self->{'options}->{'l'}: comma-separated list of loci (ignored if 's' used)
	my ($self) = @_;
	my $qry;
	my $ref_db_loci_qry = "SELECT id FROM loci WHERE dbase_name IS NOT NULL AND dbase_table IS NOT NULL";
	if ( $self->{'options'}->{'s'} ) {
		my @schemes = split /,/, $self->{'options'}->{'s'};
		die "Invalid scheme list.\n" if any { !BIGSdb::Utils::is_int($_) } @schemes;
		local $" = ',';
		$qry = "SELECT locus FROM scheme_members WHERE scheme_id IN (@schemes) AND locus IN ($ref_db_loci_qry) "
		  . "ORDER BY scheme_id,field_order";
	} elsif ( $self->{'options'}->{'l'} ) {
		my @loci = split /,/, $self->{'options'}->{'l'};
		local $" = "','";
		$qry = "$ref_db_loci_qry AND id IN ('@loci')";
	} else {
		$qry = "$ref_db_loci_qry ORDER BY id";
	}
	my $loci = $self->{'datastore'}->run_list_query($qry);
	@$loci = uniq @$loci;
	return $loci;
}

sub get_project_isolates {
	my ( $self, $project_id ) = @_;
	return if !BIGSdb::Utils::is_int($project_id);
	return $self->{'datastore'}->run_list_query( "SELECT isolate_id FROM project_members WHERE project_id=?", $project_id );
}

sub delete_temp_files {
	my ( $self, $wildcard ) = @_;
	my @file_list = glob($wildcard);
	foreach my $file (@file_list) {
		unlink $1 if $file =~ /(.*BIGSdb.*)/;    #untaint
	}
	return;
}
1;
