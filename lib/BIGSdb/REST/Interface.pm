#Written by Keith Jolley
#Copyright (c) 2014-2015, University of Oxford
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
package BIGSdb::REST::Interface;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Application);
use Dancer2;
use Error qw(:try);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Application_Initiate');
use BIGSdb::Utils;
use BIGSdb::REST::Routes::AlleleDesignations;
use BIGSdb::REST::Routes::Alleles;
use BIGSdb::REST::Routes::Contigs;
use BIGSdb::REST::Routes::Isolates;
use BIGSdb::REST::Routes::Loci;
use BIGSdb::REST::Routes::Profiles;
use BIGSdb::REST::Routes::Resources;
use BIGSdb::REST::Routes::Schemes;
use BIGSdb::REST::Routes::Users;
use constant PAGE_SIZE => 100;

sub new {
	my ( $class, $options ) = @_;
	my $self = {};
	$self->{'system'}           = {};
	$self->{'config'}           = {};
	$self->{'instance'}         = undef;
	$self->{'xmlHandler'}       = undef;
	$self->{'dataConnector'}    = BIGSdb::Dataconnector->new;
	$self->{'datastore'}        = undef;
	$self->{'db'}               = undef;
	$self->{'config_dir'}       = $options->{'config_dir'};
	$self->{'lib_dir'}          = $options->{'lib_dir'};
	$self->{'dbase_config_dir'} = $options->{'dbase_config_dir'};
	$self->{'host'}             = $options->{'host'};
	$self->{'port'}             = $options->{'port'};
	$self->{'user'}             = $options->{'user'};
	$self->{'password'}         = $options->{'password'};
	bless( $self, $class );
	$self->_initiate;
	set behind_proxy => $self->{'config'}->{'rest_behind_proxy'} ? 1 : 0;
	set serializer => 'JSON';    #Mutable isn't working with Dancer2.
	set self       => $self;
	return $self;
}

sub _initiate {
	my ( $self, ) = @_;
	$self->read_config_file( $self->{'config_dir'} );
	$self->read_host_mapping_file( $self->{'config_dir'} );
	return;
}

#Read database configs and connect before entering route.
hook before => sub {
	my $self        = setting('self');
	my $request_uri = request->uri();
	$self->{'instance'} = $request_uri =~ /^\/db\/([\w\d\-_]+)/ ? $1 : '';
	my $full_path = "$self->{'dbase_config_dir'}/$self->{'instance'}/config.xml";
	if ( !$self->{'instance'} ) {
		undef $self->{'system'};
		$self->{'system'}->{'db'} = $self->{'config'}->{'rest_db'};
	} elsif ( !-e $full_path ) {
		send_error( "Database $self->{'instance'} has not been defined", 404 );
	} else {
		$self->{'xmlHandler'} = BIGSdb::Parser->new;
		my $parser = XML::Parser::PerlSAX->new( Handler => $self->{'xmlHandler'} );
		eval { $parser->parse( Source => { SystemId => $full_path } ) };
		if ($@) {
			$logger->fatal("Invalid XML description: $@") if $self->{'instance'} ne '';
			undef $self->{'system'};
			return;
		}
		$self->{'system'} = $self->{'xmlHandler'}->get_system_hash;
	}
	$self->set_system_overrides;
	$ENV{'PATH'} = '/bin:/usr/bin';              ## no critic (RequireLocalizedPunctuationVars) #so we don't foul taint check
	delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};    # Make %ENV safer
	$self->{'system'}->{'read_access'} ||= 'public';                          #everyone can view by default
	$self->{'system'}->{'host'}        ||= $self->{'host'} || 'localhost';
	$self->{'system'}->{'port'}        ||= $self->{'port'} || 5432;
	$self->{'system'}->{'user'}        ||= $self->{'user'} || 'apache';
	$self->{'system'}->{'password'}    ||= $self->{'password'} || 'remote';
	if ( ( $self->{'system'}->{'dbtype'} // '' ) eq 'isolates' ) {
		$self->{'system'}->{'view'}       ||= 'isolates';
		$self->{'system'}->{'labelfield'} ||= 'isolate';
		if ( !$self->{'xmlHandler'}->is_field( $self->{'system'}->{'labelfield'} ) ) {
			$logger->error( "The defined labelfield '$self->{'system'}->{'labelfield'}' does not exist in the database.  "
				  . "Please set the labelfield attribute in the system tag of the database XML file." );
		}
	}
	if ( ( $self->{'system'}->{'dbtype'} // '' ) eq 'isolates' || ( $self->{'system'}->{'dbtype'} // '' ) eq 'sequences' ) {
		if ( ( $self->{'system'}->{'read_access'} // '' ) ne 'public' ) {
			send_error( 'Unauthorized', 401 );
		}
	}
	$self->{'dataConnector'}->initiate( $self->{'system'}, $self->{'config'} );
	$self->db_connect;
	$self->setup_datastore;
	$self->_initiate_view;
	$self->{'page_size'} = ( BIGSdb::Utils::is_int( param('page_size') ) && param('page_size') > 0 ) ? param('page_size') : PAGE_SIZE;
	return;
};

#Drop the connection because we may have hundreds of databases on the system.  Keeping them all open will exhaust resources.
#This could be made optional for systems with only a few databases.
hook after => sub {
	my $self = setting('self');
	$self->{'dataConnector'}->drop_all_connections;
};

sub get_set_id {
	my ($self) = @_;
	if ( ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ) {
		my $set_id = $self->{'system'}->{'set_id'};
		return $set_id if $set_id && BIGSdb::Utils::is_int($set_id);
	}
	return;
}

#Set view if defined in set.
sub _initiate_view {
	my ($self) = @_;
	return if ( $self->{'system'}->{'dbtype'} // '' ) ne 'isolates';
	my $set_id = $self->get_set_id;
	if ( defined $self->{'system'}->{'view'} && $set_id ) {
		if ( $self->{'system'}->{'views'} && BIGSdb::Utils::is_int($set_id) ) {
			my $view = $self->{'datastore'}->run_query( "SELECT view FROM set_view WHERE set_id=?", $set_id );
			$self->{'system'}->{'view'} = $view if defined $view;
		}
	}
	return;
}

#Get the contents of the rest_db database.
sub get_resources {
	my ($self) = @_;
	my $dbases =
	  $self->{'datastore'}->run_query( "SELECT * FROM resources ORDER BY name", undef, { fetch => 'all_arrayref', slice => {} } );
	return $dbases;
}

sub get_paging {
	my ( $self, $route, $pages, $page ) = @_;
	my $paging = {};
	if ( $page > 1 ) {
		$paging->{'first'} = request->uri_base . "$route?page=1&page_size=$self->{'page_size'}";
		$paging->{'previous'} = request->uri_base . "$route?page=" . ( $page - 1 ) . "&page_size=$self->{'page_size'}";
	}
	if ( $page < $pages ) {
		$paging->{'next'} = request->uri_base . "$route?page=" . ( $page + 1 ) . "&page_size=$self->{'page_size'}";
	}
	if ( $page != $pages ) {
		$paging->{'last'} = request->uri_base . "$route?page=$pages&page_size=$self->{'page_size'}";
	}
	return $paging;
}

sub clean_locus {
	my ( $self, $locus ) = @_;
	return if !defined $locus;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $set_id     = $self->get_set_id;
	if ($set_id) {
		my $set_name = $self->{'datastore'}->run_query(
			"SELECT set_name FROM set_loci WHERE set_id=? AND locus=?",
			[ $set_id, $locus ],
			{ fetch => 'row_array', cache => 'clean_locus' }
		);
		return $set_name if $set_name;
	}
	return $locus;
}

#Use method in case URL changes so we only need to change in one place.
sub get_pubmed_link {
	my ( $self, $pubmed_id ) = @_;

	#	return "http://www.ncbi.nlm.nih.gov/pubmed/$pubmed_id";
	return "http://www.ebi.ac.uk/europepmc/webservices/rest/search/query=EXT_ID:$pubmed_id&format=JSON&resulttype=core";
}

sub check_isolate_is_valid {
	my ( $self, $isolate_id ) = @_;
	$self->check_isolate_database;
	if ( !BIGSdb::Utils::is_int($isolate_id) ) {
		send_error( 'Isolate id must be an integer', 400 );
	}
	my $exists = $self->{'datastore'}->run_query( "SELECT EXISTS(SELECT * FROM $self->{'system'}->{'view'} WHERE id=?)", $isolate_id );
	if ( !$exists ) {
		send_error( "Isolate $isolate_id does not exist.", 404 );
	}
	return;
}

sub check_isolate_database {
	my ($self) = @_;
	if ( ( $self->{'system'}->{'dbtype'} // '' ) ne 'isolates' ) {
		send_error( 'This is not an isolates database.', 400 );
	}
	return;
}

sub check_seqdef_database {
	my ($self) = @_;
	if ( ( $self->{'system'}->{'dbtype'} // '' ) ne 'sequences' ) {
		send_error( 'This is not a sequence definition database.', 400 );
	}
	return;
}

sub check_scheme {
	my ( $self, $scheme_id ) = @_;
	my $set_id = $self->get_set_id;
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		send_error( 'Scheme id must be an integer.', 400 );
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
	if ( !$scheme_info ) {
		send_error( "Scheme $scheme_id does not exist.", 404 );
	}
	return;
}
1;
