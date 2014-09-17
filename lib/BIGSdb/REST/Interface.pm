#Written by Keith Jolley
#Copyright (c) 2014, University of Oxford
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
use BIGSdb::REST::Routes::Isolates;
use BIGSdb::REST::Routes::Loci;
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
	$self->{'dataConnector'}->initiate( $self->{'system'}, $self->{'config'} );
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
		undef $self->{'system'};
		return;
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
	$self->{'dataConnector'}->drop_connection( { host => $self->{'system'}->{'host'}, dbase_name => $self->{'system'}->{'db'} } );
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
	my $paging = [];
	if ( $page > 1 ) {
		push @$paging, { first => request->uri_base . "$route?page=1&page_size=$self->{'page_size'}" };
		push @$paging, { previous => request->uri_base . "$route?page=" . ( $page - 1 ) . "&page_size=$self->{'page_size'}" };
	}
	if ( $page < $pages ) {
		push @$paging, { next => request->uri_base . "$route?page=" . ( $page + 1 ) . "&page_size=$self->{'page_size'}" };
	}
	if ( $page != $pages ) {
		push @$paging, { last => request->uri_base . "$route?page=$pages&page_size=$self->{'page_size'}" };
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
	return "http://www.ncbi.nlm.nih.gov/pubmed/$pubmed_id";
}
1;
