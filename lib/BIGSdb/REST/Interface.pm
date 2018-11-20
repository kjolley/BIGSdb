#Written by Keith Jolley
#Copyright (c) 2014-2018, University of Oxford
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
use Dancer2 0.156;
use Try::Tiny;
use Net::OAuth;
$Net::OAuth::PROTOCOL_VERSION = Net::OAuth::PROTOCOL_VERSION_1_0A;
use POSIX qw(ceil);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Application_Initiate');
use BIGSdb::Exceptions;
use BIGSdb::Utils;
use BIGSdb::Constants qw(:login_requirements);
use BIGSdb::Offline::Blast;
use BIGSdb::REST::Routes::AlleleDesignations;
use BIGSdb::REST::Routes::Alleles;
use BIGSdb::REST::Routes::ClassificationSchemes;
use BIGSdb::REST::Routes::Contigs;
use BIGSdb::REST::Routes::Fields;
use BIGSdb::REST::Routes::Isolates;
use BIGSdb::REST::Routes::Loci;
use BIGSdb::REST::Routes::OAuth;
use BIGSdb::REST::Routes::Profiles;
use BIGSdb::REST::Routes::Projects;
use BIGSdb::REST::Routes::Resources;
use BIGSdb::REST::Routes::Schemes;
use BIGSdb::REST::Routes::Sequences;
use BIGSdb::REST::Routes::Submissions;
use BIGSdb::REST::Routes::Users;
use constant SESSION_EXPIRES => 3600 * 12;
use constant PAGE_SIZE       => 100;
hook before      => sub { _before() };
hook after       => sub { _after() };
hook after_error => sub { _after_error() };

sub new {
	my ( $class, $options ) = @_;
	my $self = {};
	$self->{'system'}            = {};
	$self->{'config'}            = {};
	$self->{'instance'}          = undef;
	$self->{'xmlHandler'}        = undef;
	$self->{'dataConnector'}     = BIGSdb::Dataconnector->new;
	$self->{'datastore'}         = undef;
	$self->{'submissionHandler'} = undef;
	$self->{'db'}                = undef;
	$self->{'config_dir'}        = $options->{'config_dir'};
	$self->{'lib_dir'}           = $options->{'lib_dir'};
	$self->{'dbase_config_dir'}  = $options->{'dbase_config_dir'};
	$self->{'host'}              = $options->{'host'};
	$self->{'port'}              = $options->{'port'};
	$self->{'user'}              = $options->{'user'};
	$self->{'password'}          = $options->{'password'};
	bless( $self, $class );
	$self->_initiate;
	set behind_proxy => $self->{'config'}->{'rest_behind_proxy'} ? 1 : 0;
	set serializer   => 'JSON';
	set self         => $self;
	return $self;
}

sub _initiate {
	my ($self) = @_;
	$self->read_config_file( $self->{'config_dir'} );
	$self->read_host_mapping_file( $self->{'config_dir'} );
	$self->{'logger'} = $logger;
	return;
}

#We cannot currently catch an error when the serializer encounters malformed
#JSON. It will log it, but will fail to deserialize body parameters. As far
#as the sender knows, there is no error, so this ensures that they get a
#400 response if there is a POST payload but no parameters deserialized.
sub check_post_payload {
	my ($self)      = @_;
	my $body        = request->body;
	my $body_params = body_parameters;
	if ( $body && !keys %$body_params ) {
		send_error( 'Malformed request', 400 );
	}
	my $length = length $body;
	if ( $length > $self->{'config'}->{'max_upload_size'} ) {
		my $nice_body_size = BIGSdb::Utils::get_nice_size($length);
		my $limit_size     = BIGSdb::Utils::get_nice_size( $self->{'config'}->{'max_upload_size'} );
		send_error( "POST body is too large ($nice_body_size) - limit is $limit_size", 413 );
	}
	return;
}

#Read database configs and connect before entering route.
sub _before {
	my $self         = setting('self');
	my $request_path = request->path();
	$self->{'instance'} = $request_path =~ /^\/db\/([\w\d\-_]+)/x ? $1 : '';
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
	$ENV{'PATH'} = '/bin:/usr/bin';    ## no critic (RequireLocalizedPunctuationVars) #so we don't foul taint check
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
			$logger->error( "The defined labelfield '$self->{'system'}->{'labelfield'}' does not exist in the "
				  . 'database. Please set the labelfield attribute in the system tag of the database XML file.' );
		}
	}
	$self->{'dataConnector'}->initiate( $self->{'system'}, $self->{'config'} );
	$self->db_connect;
	send_error( 'No access to databases - undergoing maintenance.', 503 ) if !$self->{'db'};
	$self->initiate_authdb if ( $self->{'system'}->{'authentication'} // '' ) eq 'builtin';
	$self->setup_datastore;
	$self->setup_remote_contig_manager;
	$self->{'datastore'}->initiate_userdbs if $self->{'instance'};
	return if !$self->{'system'}->{'dbtype'};    #We are in resources database
	_check_kiosk();
	_check_authorization();
	$self->_initiate_view;
	$self->_set_page_options;
	return;
}

sub _check_authorization {
	my $self             = setting('self');
	my $request_uri      = request->uri();
	my $authenticated_db = ( $self->{'system'}->{'read_access'} // '' ) ne 'public';
	my $oauth_route      = "/db/$self->{'instance'}/oauth/";
	my $submission_route = "/db/$self->{'instance'}/submissions";
	if ( $request_uri =~ /$submission_route/x ) {
		$self->setup_submission_handler;
	}
	if ( ( $authenticated_db && $request_uri !~ /^$oauth_route/x ) || $request_uri =~ /$submission_route/x ) {
		send_error( 'Unauthorized', 401 ) if !$self->_is_authorized;
	}
	my $login_requirement = $self->{'datastore'}->get_login_requirement;
	if ( $login_requirement == OPTIONAL && param('oauth_consumer_key') && $request_uri !~ /^$oauth_route/x ) {
		$self->_is_authorized;
	}
	return;
}

sub _check_kiosk {
	my $self = setting('self');
	return if !$self->{'system'}->{'kiosk'};
	if ( !$self->{'system'}->{'rest_kiosk'} ) {
		send_error( 'No routes available for this database configuration', 404 );
	}
	my $db = params->{'db'};
	if ( $self->{'system'}->{'rest_kiosk'} eq 'sequenceQuery' ) {
		my @allowed_routes = ( "POST /db/$db/loci/{locus}/sequence", "POST /db/$db/sequence",
			"POST /db/$db/schemes/{scheme_id}/sequence" );
		local $" = q(, );
		if ( request->method ne 'POST' ) {
			send_error(
				"Only the following sequence query routes are allowed for this database configuration: @allowed_routes",
				404
			);
		}
		my $route         = request->request_uri;
		my @allowed_regex = (
			qr/^\/db\/$db\/loci\/\w+\/sequence$/x,
			qr/^\/db\/$db\/sequence$/x, qr/^\/db\/$db\/schemes\/\d+\/sequence$/x
		);
		foreach my $allowed (@allowed_regex) {
			return if $route =~ $allowed;
		}
		send_error( 'Route is not allowed for this database configuration', 404 );
	}
	send_error( 'No routes available for this database configuration', 404 );
	return;
}

sub _set_page_options {
	my ($self) = @_;
	my $headers = request->headers;
	if ( BIGSdb::Utils::is_int( $headers->{'x-per-page'} ) ) {
		$self->{'page_size'} = $headers->{'x-per-page'} > 0 ? $headers->{'x-per-page'} : PAGE_SIZE;
	} else {
		$self->{'page_size'} =
		  ( BIGSdb::Utils::is_int( param('page_size') ) && param('page_size') > 0 ) ? param('page_size') : PAGE_SIZE;
	}
	$self->{'using_page_headers'} = ( $headers->{'x-offset'} || $headers->{'x-per-page'} ) ? 1 : 0;
	return;
}

sub get_page_values {
	my ( $self, $total ) = @_;
	my $headers = request->headers;
	my ( $page, $offset );
	my $total_pages = ceil( $total / $self->{'page_size'} );
	if ( $self->{'using_page_headers'} ) {    #Specifically passing paging info in headers
		$offset =
		  ( BIGSdb::Utils::is_int( $headers->{'x-offset'} ) && $headers->{'x-offset'} > 0 )
		  ? $headers->{'x-offset'}
		  : 0;
	} else {
		$page = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
		$offset = ( $page - 1 ) * $self->{'page_size'};
	}
	return {
		page        => $page,
		total_pages => $total_pages,
		offset      => $offset
	};
}

#Drop the connection because we may have hundreds of databases on the system.
#Keeping them all open will exhaust resources. This could be made optional
#for systems with only a few databases.
sub _after {
	my $self = setting('self');
	undef $self->{'username'};
	$self->{'dataConnector'}->drop_all_connections;
	return;
}

sub _after_error {
	my $self = setting('self');
	undef $self->{'username'};
	$self->{'dataConnector'}->drop_all_connections;
	return;
}

sub _is_authorized {
	my ($self) = @_;
	my $params = params;
	my $db     = param('db');
	if ( !param('oauth_consumer_key') ) {
		send_error( 'Unauthorized - Generate new session token.', 401 );
	}
	my $client = $self->{'datastore'}->run_query(
		'SELECT * FROM clients WHERE client_id=?',
		param('oauth_consumer_key'),
		{ db => $self->{'auth_db'}, fetch => 'row_hashref', cache => 'REST::get_client_secret' }
	);
	if ( !$client->{'client_secret'} ) {
		send_error( 'Unrecognized client', 403 );
	}
	my $client_name = $client->{'application'};
	$client_name .= " version $client->{'version'}" if $client->{'version'};
	$self->{'client_name'} = $client_name;
	$self->delete_old_sessions;
	my $session_token = $self->{'datastore'}->run_query(
		'SELECT * FROM api_sessions WHERE session=?',
		param('oauth_token') // q(),
		{ fetch => 'row_hashref', db => $self->{'auth_db'}, cache => 'REST::Interface::is_authorized::api_sessions' }
	);
	if ( !$session_token->{'secret'} ) {
		send_error( 'Invalid session token.  Generate new token (/get_session_token).', 401 );
	}
	my $dbase = $self->{'datastore'}->get_dbname_with_user_details( $session_token->{'username'} );
	if ( $dbase ne $session_token->{'dbase'} ) {
		send_error( 'Invalid session token.  Generate new token (/get_session_token).', 401 );
	}
	my $query_params = params('query');
	my $body_params  = params('body');
	my $extra_params = {};
	foreach my $param ( keys %$query_params, keys %$body_params ) {
		next if $param =~ /^oauth_/x;
		$extra_params->{$param} = $query_params->{$param} // $body_params->{$param};
	}
	my $request_params = {};
	$request_params->{$_} = param($_) foreach qw(
	  oauth_consumer_key
	  oauth_signature
	  oauth_signature_method
	  oauth_version
	  oauth_token
	  oauth_timestamp
	  oauth_nonce
	);
	my $request = eval {
		Net::OAuth->request('protected resource')->from_hash(
			$request_params,
			request_method  => request->method,
			request_url     => request->uri_base . request->path,
			consumer_secret => $client->{'client_secret'},
			token_secret    => $session_token->{'secret'},
			extra_params    => $extra_params
		);
	};

	if ($@) {
		if ( $@ =~ /Missing\ required\ parameter\ \'(\w+?)\'/x ) {
			send_error( "Invalid token request. Missing required parameter: $1.", 400 );
		} else {
			$self->{'logger'}->error($@);
			send_error( 'Invalid token request.', 400 );
		}
	}
	if ( !$request->verify ) {
		$self->{'logger'}->debug( 'Request string: ' . $request->signature_base_string );
		send_error( 'Signature verification failed.', 401 );
	}
	$self->_check_client_authorization($client);
	$self->{'username'} = $session_token->{'username'};
	$self->_check_user_authorization( $self->{'username'} );
	return 1;
}

sub _check_user_authorization {
	my ( $self, $username ) = @_;
	if ( !$self->is_user_allowed_access($username) ) {
		send_error( 'User is unauthorized to access this database.', 401 );
	}
	return;
}

sub _check_client_authorization {
	my ( $self, $client ) = @_;
	my ( $db_authorize, $db_submission, $db_curation ) = $self->{'datastore'}->run_query(
		'SELECT authorize,submission,curation FROM client_permissions WHERE (client_id,dbase)=(?,?)',
		[ param('oauth_consumer_key'), $self->{'system'}->{'db'} ],
		{ db => $self->{'auth_db'}, cache => 'REST::Interface::is_authorized::client_permissions' }
	);
	my $client_authorized;
	if ( $client->{'default_permission'} eq 'allow' ) {
		$client_authorized = ( !$db_authorize || $db_authorize eq 'allow' ) ? 1 : 0;
	} else {    #default deny
		$client_authorized = ( !$db_authorize || $db_authorize eq 'deny' ) ? 0 : 1;
	}
	if ( !$client_authorized ) {
		send_error( 'Client is unauthorized to access this database.', 401 );
	}
	my $method      = uc( request->method );
	my $request_uri = request->uri();
	if ( $method ne 'GET' ) {
		my $client_submission;
		if ( $client->{'default_submission'} ) {
			$client_submission = ( !defined $db_submission || $db_submission ) ? 1 : 0;
		} else {    #default deny
			$client_submission = ( !defined $db_submission || !$db_submission ) ? 0 : 1;
		}
		my $client_curation;
		if ( $client->{'default_curation'} ) {
			$client_curation = ( !defined $db_curation || $db_curation ) ? 1 : 0;
		} else {    #default deny
			$client_curation = ( !defined $db_curation || !$db_curation ) ? 0 : 1;
		}
		my $submission_route = "/db/$self->{'instance'}/submissions";
		if ( $request_uri =~ /$submission_route/x ) {
			if ( !$client_submission ) {
				send_error( 'Client is unauthorized to make submissions.', 401 );
			}
		}
	}
	return;
}

sub delete_old_sessions {
	my ($self) = @_;
	eval { $self->{'auth_db'}->do( 'DELETE FROM api_sessions WHERE start_time<?', undef, time - SESSION_EXPIRES ) };
	if ($@) {
		$self->{'auth_db'}->rollback;
		$self->{'logger'}->error($@);
	} else {
		$self->{'auth_db'}->commit;
	}
	return;
}

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
	my $args = {};
	$args->{'username'} = $self->{'username'} if $self->{'username'};
	my $set_id = $self->get_set_id;
	$args->{'set_id'} = $set_id if $set_id;
	$self->{'datastore'}->initiate_view($args);
	return;
}

#Get the contents of the rest_db database.
sub get_resources {
	my ($self) = @_;
	my $groups = $self->{'datastore'}->run_query( 'SELECT * FROM groups ORDER BY name',
		undef, { fetch => 'all_arrayref', slice => {}, cache => 'REST::Interface::get_resources::groups' } );
	my $resources = [];
	foreach my $group (@$groups) {
		my $group_resources =
		  $self->{'datastore'}
		  ->run_query( 'SELECT dbase_config FROM group_resources WHERE group_name=? ORDER BY dbase_config',
			$group->{'name'}, { fetch => 'col_arrayref', cache => 'REST::Interface::get_resources::resources' } );
		my @databases;
		foreach my $dbase_config (@$group_resources) {
			my $desc = $self->{'datastore'}->run_query( 'SELECT description FROM resources WHERE dbase_config=?',
				$dbase_config, { cache => 'REST::Interface::get_resources::desc' } );
			push @databases, { dbase_config => $dbase_config, description => $desc };
		}
		delete $group->{'long_description'} if !defined $group->{'long_description'};
		$group->{'databases'} = \@databases;
		push @$resources, $group if @databases;
	}
	return $resources;
}

sub get_paging {
	my ( $self, $route, $pages, $page, $offset ) = @_;
	response->push_header( X_PER_PAGE    => $self->{'page_size'} );
	response->push_header( X_OFFSET      => ( $offset // 0 ) );
	response->push_header( X_TOTAL_PAGES => $pages );
	my $paging = {};
	return $paging if param('return_all') || !$pages || $self->{'using_page_headers'};
	my $first_separator = $route =~ /\?/x ? '&' : '?';
	if ( $page > 1 ) {
		$paging->{'first'} = request->uri_base . "$route${first_separator}page=1&page_size=$self->{'page_size'}";
		$paging->{'previous'} =
		  request->uri_base . "$route${first_separator}page=" . ( $page - 1 ) . "&page_size=$self->{'page_size'}";
	}
	if ( $page < $pages ) {
		$paging->{'next'} =
		  request->uri_base . "$route${first_separator}page=" . ( $page + 1 ) . "&page_size=$self->{'page_size'}";
	}
	if ( $page != $pages ) {
		$paging->{'last'} = request->uri_base . "$route${first_separator}page=$pages&page_size=$self->{'page_size'}";
	}
	if (%$paging) {
		$paging->{'return_all'} = request->uri_base . "$route${first_separator}return_all=1";
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
			'SELECT set_name FROM set_loci WHERE set_id=? AND locus=?',
			[ $set_id, $locus ],
			{ fetch => 'row_array', cache => 'clean_locus' }
		);
		return $set_name if $set_name;
	}
	return $locus;
}

sub check_isolate_is_valid {
	my ( $self, $isolate_id ) = @_;
	$self->check_isolate_database;
	if ( !BIGSdb::Utils::is_int($isolate_id) ) {
		send_error( 'Isolate id must be an integer', 400 );
	}
	my $exists =
	  $self->{'datastore'}
	  ->run_query( "SELECT EXISTS(SELECT * FROM $self->{'system'}->{'view'} WHERE id=?)", $isolate_id );
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
	my ( $self, $scheme_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $set_id = $self->get_set_id;
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		send_error( 'Scheme id must be an integer.', 400 );
	}
	my $scheme_info =
	  $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => $options->{'pk'} } );
	if ( !$scheme_info ) {
		send_error( "Scheme $scheme_id does not exist.", 404 );
	}
	if ( $options->{'pk'} ) {
		my $primary_key = $scheme_info->{'primary_key'};
		if ( !$scheme_info ) {
			send_error( "Scheme $scheme_id does not exist.", 404 );
		} elsif ( !$primary_key ) {
			send_error( "Scheme $scheme_id does not have a primary key field.", 404 );
		}
	}
	return;
}

sub check_load_average {
	my ($self) = @_;
	my $load_average;
	my $max_load = $self->{'config'}->{'max_load'} // 8;
	try {
		$load_average = $self->get_load_average;
	}
	catch {
		if ( $_->isa('BIGSdb::Exception::Data') ) {
			$self->{'logger'}->fatal('Cannot determine load average ... aborting!');
			exit;
		} else {
			$logger->logdie($_);
		}
	};
	if ( $load_average > $max_load ) {
		$self->{'logger'}->info("Load average = $load_average. Threshold is set at $max_load. Aborting.");
		send_error( 'Server is too busy. Please try again later.', 503 );
	}
	return;
}

sub get_user_id {
	my ($self) = @_;
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	send_error( 'Unrecognized user.', 401 ) if !$user_info;
	return $user_info->{'id'};
}

sub add_filters {
	my ( $self, $qry, $allowed_args, $options ) = @_;
	my $params = params;
	my ( $added_after, $added_on, $updated_after, $updated_on, $alleles_added_after, $alleles_updated_after ) =
	  @{$params}{qw(added_after added_on updated_after updated_on alleles_added_after alleles_updated_after)}
	  ;
	my @terms;
	my $id = $options->{'id'} // 'id';
	my %methods = (
		added_after => sub {
			push @terms, qq(date_entered>'$added_after') if BIGSdb::Utils::is_date($added_after);
		},
		added_on => sub {
			push @terms, qq(date_entered='$added_on') if BIGSdb::Utils::is_date($added_on);
		},
		updated_after => sub {
			push @terms, qq(datestamp>'$updated_after') if BIGSdb::Utils::is_date($updated_after);
		},
		updated_on => sub {
			push @terms, qq(datestamp='$updated_on') if BIGSdb::Utils::is_date($updated_on);
		},
		alleles_added_after => sub {
			push @terms, qq($id IN (SELECT locus FROM sequences WHERE date_entered>'$alleles_added_after'))
			  if BIGSdb::Utils::is_date($alleles_added_after);
		},
		alleles_updated_after => sub {
			push @terms, qq($id IN (SELECT locus FROM locus_stats WHERE datestamp>'$alleles_updated_after'))
			  if BIGSdb::Utils::is_date($alleles_updated_after);
		}
	);
	foreach my $arg (@$allowed_args) {
		$methods{$arg}->() if $methods{$arg};
	}
	local $" = q( AND );
	my $and_or_where = $qry =~ /WHERE/x ? 'AND' : 'WHERE';
	$qry .= qq( $and_or_where (@terms)) if @terms;
	return $qry;
}

sub get_full_path {
	my ( $self, $path, $allowed_args ) = @_;
	$self->get_param_string($allowed_args);
	my $passed_params = $self->get_param_string($allowed_args);
	$path .= "?$passed_params" if $passed_params;
	return $path;
}

sub get_param_string {
	my ( $self, $allowed_args ) = @_;
	my @params;
	my $param_hash = request->query_parameters;
	foreach my $arg (@$allowed_args) {
		push @params, "$arg=$param_hash->{$arg}" if defined $param_hash->{$arg};
	}
	local $" = q(&);
	return "@params";
}

sub get_blast_object {
	my ( $self, $loci ) = @_;
	local $" = q(,);
	my $exemplar = ( $self->{'system'}->{'exemplars'} // q() ) eq 'yes' ? 1 : 0;
	$exemplar = 0 if @$loci == 1;
	my $blast_obj = BIGSdb::Offline::Blast->new(
		{
			config_dir       => $self->{'config_dir'},
			lib_dir          => $self->{'lib_dir'},
			dbase_config_dir => $self->{'dbase_config_dir'},
			host             => $self->{'system'}->{'host'},
			port             => $self->{'system'}->{'port'},
			user             => $self->{'system'}->{'user'},
			password         => $self->{'system'}->{'password'},
			options          => {
				l          => qq(@$loci),
				always_run => 1,
				exemplar   => $exemplar,
			},
			instance => $self->{'instance'},
			logger   => $self->{'logger'}
		}
	);
	return $blast_obj;
}

sub filter_match {
	my ( $self, $match, $options ) = @_;
	if ( $options->{'exact'} ) {
		my %filtered = map { $_ => int( $match->{$_} ) } qw(start end length);
		$filtered{'allele_id'}   = $match->{'allele'};
		$filtered{'orientation'} = $match->{'reverse'} ? 'reverse' : 'forward';
		$filtered{'contig'}      = $match->{'query'} if $match->{'query'} ne 'Query';
		return \%filtered;
	}
	my %filtered = map { $_ => int( $match->{$_} ) } qw(alignment length gaps mismatches);
	$filtered{'start'}       = int( $match->{'predicted_start'} );
	$filtered{'end'}         = int( $match->{'predicted_end'} );
	$filtered{'identity'}    = $match->{'identity'} + 0;                            #Numify
	$filtered{'allele_id'}   = $match->{'allele'};
	$filtered{'orientation'} = $match->{'reverse'} ? 'reverse' : 'forward';
	$filtered{'contig'}      = $match->{'query'} if $match->{'query'} ne 'Query';
	return \%filtered;
}
1;
