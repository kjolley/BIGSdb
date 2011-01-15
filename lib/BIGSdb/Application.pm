#Written by Keith Jolley
#(c) 2010, University of Oxford
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
package BIGSdb::Application;
use strict;
use Time::HiRes qw(gettimeofday);
use Error qw(:try);
use Log::Log4perl qw(get_logger);
use Config::Tiny;

sub new {
	my ( $class, $config_dir, $plugin_dir, $dbase_config_dir, $r, $curate ) = @_;
	my $self = {};
	$self->{'system'}           = {};
	$self->{'config'}           = {};
	$self->{'cgi'}              = new CGI;
	$self->{'instance'}         = undef;
	$self->{'xmlHandler'}       = undef;
	$self->{'page'}             = undef;
	$self->{'invalidXML'}       = 0;
	$self->{'invalidDbType'}    = 0;
	$self->{'dataConnector'}    = new BIGSdb::Dataconnector;
	$self->{'datastore'}        = undef;
	$self->{'pluginManager'}    = undef;
	$self->{'db'}               = undef;
	$self->{'mod_perl_request'} = $r;
	$self->{'fatal'}            = undef;
	$self->{'start_time'}       = gettimeofday();
	$self->{'curate'}           = $curate;
	bless( $self, $class );
	$self->_initiate( $config_dir, $dbase_config_dir );
	$self->{'dataConnector'}->initiate($self->{'system'});
	my $logger_benchmark = get_logger('BIGSdb.Application_Benchmark');

	if ( !$self->{'error'} ) {
		$self->db_connect();
		if ( $self->{'db'} ) {
			$self->_setup_datastore();
			$self->_setup_prefstore();
			$self->_initiate_authdb if $self->{'system'}->{'authentication'} eq 'builtin';
			$self->_initiate_plugins($plugin_dir);
		}
	}
	( my $elapsed = gettimeofday() - $self->{'start_time'} ) =~ s/(^\d{1,}\.\d{4}).*$/$1/;
	$logger_benchmark->debug("Time to initiate : $elapsed seconds");
	$self->print_page($dbase_config_dir);
	$self->_db_disconnect();
	return $self;
}

sub DESTROY {
	my ($self) = @_;
	return
	  if !$self->{'start_time'};    #DESTROY can be called twice (By Object::Destroyer then by GC)
	my $logger  = get_logger('BIGSdb.Application_Benchmark');
	my $end     = gettimeofday();
	my $elapsed = $end - $self->{'start_time'};
	$elapsed =~ s/(^\d{1,}\.\d{4}).*$/$1/;
	$logger->info("Total Time to process $self->{'page'} page: $elapsed seconds");
}

sub _initiate {
	my ( $self, $config_dir, $dbase_config_dir ) = @_;
	my $q = $self->{'cgi'};
	Log::Log4perl::MDC->put( "ip", $q->remote_host );
	$self->_read_config_file($config_dir);
	my $logger = get_logger('BIGSdb.Application_Initiate');
	$self->{'instance'} = $1 if $self->{'cgi'}->param('db') =~ /^([\w\d\-_]+)$/;
	my $full_path = "$dbase_config_dir/$self->{'instance'}/config.xml";
	$self->{'xmlHandler'} = BIGSdb::Parser->new();
	my $parser = XML::Parser::PerlSAX->new( Handler => $self->{'xmlHandler'} );
	eval { $parser->parse( Source => { SystemId => $full_path } ); };

	if ($@) {
		$logger->fatal("Invalid XML description: $@");
		$self->{'error'} = 'invalidXML';
		return;
	}
	$self->{'system'} = $self->{'xmlHandler'}->get_system_hash();
	if ( $self->{'system'}->{'dbtype'} ne 'sequences' && $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		$self->{'error'} = 'invalidDbType';
	}
	$self->{'script_name'} = $q->script_name || 'bigsdb.pl';
	if ( $self->{'curate'} && $self->{'system'}->{'curate_path_includes'} ) {
		if ( $self->{'script_name'} !~ /$self->{'system'}->{'curate_path_includes'}/ ) {
			$self->{'error'} = 'invalidScriptPath';
		}
	} elsif ( !$self->{'curate'} && $self->{'system'}->{'script_path_includes'} ) {
		if ( $self->{'script_name'} !~ /$self->{'system'}->{'script_path_includes'}/ ) {
			$self->{'error'} = 'invalidScriptPath';
		}
	}
	$self->{'error'}                   = 'noAuthenticationSet' if !$self->{'system'}->{'authentication'};
	$self->{'system'}->{'read_access'} = 'public'              if !$self->{'system'}->{'read_access'};      #everyone can view by default
	$self->{'system'}->{'script_name'} = $self->{'script_name'};
	$ENV{'PATH'} = '/bin:/usr/bin';                                                                         #so we don't foul taint check
	delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};                                                               # Make %ENV safer
	$self->{'page'} = $q->param('page') || 'index';
	$self->{'system'}->{'host'} = 'localhost' if !$self->{'system'}->{'host'};
	$self->{'system'}->{'port'} = 5432        if !$self->{'system'}->{'port'};
	$self->{'system'}->{'user'} = 'apache'    if !$self->{'system'}->{'user'};
	$self->{'system'}->{'password'} = 'remote'
	  if !$self->{'system'}->{'password'};
	
	$self->{'system'}->{'privacy'} = $self->{'system'}->{'privacy'} eq 'no' ? 0 : 1;
	if ($self->{'system'}->{'dbtype'} eq 'isolates'){
		$self->{'system'}->{'view'} = 'isolates' if !$self->{'system'}->{'view'};
		$self->{'system'}->{'labelfield'} = 'isolate' if !$self->{'system'}->{'labelfield'};
		if (!$self->{'xmlHandler'}->is_field($self->{'system'}->{'labelfield'})){
			$logger->error("The defined labelfield '$self->{'system'}->{'labelfield'}' does not exist in the database.  Please set the labelfield attribute in the system tag of the database XML file.");
		}
	}
}




sub _initiate_authdb {
	my ($self) = @_;
	my $logger = get_logger('BIGSdb.Application_Initiate');
	my %att    = (
		'dbase_name' => $self->{'config'}->{'auth_db'},
		'host'       => $self->{'system'}->{'host'},
		'port'       => $self->{'system'}->{'port'},
		'user'       => $self->{'system'}->{'user'},
		'password'   => $self->{'system'}->{'password'},
		'writable'   => 1
	);
	try {
		$self->{'auth_db'} = $self->{'dataConnector'}->get_connection( \%att );
		$logger->info("Connected to authentication database '$self->{'config'}->{'auth_db'}'");
	}
	catch BIGSdb::DatabaseConnectionException with {
		$logger->error("Can not connect to authentication database '$self->{'config'}->{'auth_db'}'");
		$self->{'error'} = 'noAuth';
		return;
	};
}

sub initiate_view {

	#create view containing only isolates that are allowed to be viewed by user
	my ( $self, $attributes ) = @_;
	my $logger     = get_logger('BIGSdb.Application_Initiate');
	my $username   = $attributes->{'username'};
	my $status_ref = $self->{'datastore'}->run_simple_query( "SELECT status FROM users WHERE user_name=?", $username );
	return if ref $status_ref ne 'ARRAY' || $status_ref->[0] eq 'admin';
	my $write_clause;
	if ( $attributes->{'curate'} ) {

		#You need to be able to read and write to a record to view it in the curator's interface
		$write_clause = " AND write=true";
	}
	my $view_clause = << "SQL";
SELECT * FROM $self->{'system'}->{'view'} WHERE id IN (SELECT isolate_id FROM isolate_user_acl 
LEFT JOIN users ON isolate_user_acl.user_id = users.id WHERE user_name='$username' AND read$write_clause) OR 
id IN (SELECT isolate_id FROM isolate_usergroup_acl LEFT JOIN user_group_members 
ON user_group_members.user_group=isolate_usergroup_acl.user_group_id LEFT JOIN users 
ON user_group_members.user_id=users.id WHERE users.user_name ='$username' AND read$write_clause)
SQL
	if ($username) {
		eval { $self->{'db'}->do("CREATE TEMP VIEW tmp_userview AS $view_clause"); };
		if ($@) {
			$logger->error("Can't create user view $@");
			$self->{'db'}->rollback;
		} else {
			$self->{'system'}->{'view'} = 'tmp_userview';
		}
	}
}



sub _initiate_plugins {
	my ( $self, $plugin_dir ) = @_;
	$self->{'pluginManager'} = BIGSdb::PluginManager->new(
		'system'           => $self->{'system'},
		'cgi'              => $self->{'cgi'},
		'instance'         => $self->{'instance'},
		'prefstore'        => $self->{'prefstore'},
		'config'           => $self->{'config'},
		'datastore'        => $self->{'datastore'},
		'db'               => $self->{'db'},
		'xmlHandler'       => $self->{'xmlHandler'},
		'dataConnector'    => $self->{'dataConnector'},
		'mod_perl_request' => $self->{'mod_perl_request'},
		'pluginDir'        => $plugin_dir
	);
}

sub _read_config_file {
	my ( $self, $config_dir ) = @_;
	my $logger = get_logger('BIGSdb.Application_Initiate');
	my $config = Config::Tiny->new();
	$config = Config::Tiny->read("$config_dir/bigsdb.conf");
	foreach (
		qw ( prefs_db auth_db jobs_db emboss_path tmp_dir secure_tmp_dir blast_path muscle_path mogrify_path
		reference refdb chartdirector)
	  )
	{
		$self->{'config'}->{$_} = $config->{_}->{$_};
	}
	if ( $self->{'config'}->{'chartdirector'} ) {
		eval "use perlchartdir;";
		if ($@) {
			$logger->error("Chartdirector not installed! - Either install or set 'chartdirector=0' in bigsdb.conf");
			$self->{'config'}->{'chartdirector'} = 0;
		} else {
			eval "use BIGSdb::Charts;";
			if ($@) {
				$logger->error("Charts.pm not installed!");
			}
		}
	}
}

sub _setup_prefstore {
	my ($self) = @_;
	my %att = (
		'dbase_name' => $self->{'config'}->{'prefs_db'},
		'host'       => $self->{'system'}->{'host'},
		'port'       => $self->{'system'}->{'port'},
		'user'       => $self->{'system'}->{'user'},
		'password'   => $self->{'system'}->{'password'},
		'writable'   => 1
	);
	my $pref_db;
	try {
		$pref_db = $self->{'dataConnector'}->get_connection( \%att );
	}
	catch BIGSdb::DatabaseConnectionException with {
		my $logger = get_logger('BIGSdb.Prefs');
		$logger->fatal("Can not connect to preferences database '$self->{'config'}->{'prefs_db'}'");
		return;
	};
	$self->{'prefstore'} = BIGSdb::Preferences->new( ( 'db' => $pref_db ) );
}

sub _setup_datastore {
	my ($self) = @_;
	$self->{'datastore'} = BIGSdb::Datastore->new(
		(
			'db'            => $self->{'db'},
			'dataConnector' => $self->{'dataConnector'},
			'system'        => $self->{'system'},
			'config'        => $self->{'config'},
			'xmlHandler'    => $self->{'xmlHandler'}
		)
	);
}

sub db_connect {
	my ($self) = @_;
	my %att = (
		'dbase_name' => $self->{'system'}->{'db'},
		'host'       => $self->{'system'}->{'host'},
		'port'       => $self->{'system'}->{'port'},
		'user'       => $self->{'system'}->{'user'},
		'password'   => $self->{'system'}->{'password'}
	);
	try {
		$self->{'db'} = $self->{'dataConnector'}->get_connection( \%att );
	}
	catch BIGSdb::DatabaseConnectionException with {
		my $logger = get_logger('BIGSdb.Application_Initiate');
		$logger->error("Can not connect to database '$self->{'system'}->{'db'}'");
		return;
	};
}

sub _db_disconnect {
	my ($self) = @_;
	$self->{'prefstore'}->finish_statement_handles if $self->{'prefstore'};
	undef $self->{'prefstore'};
	undef $self->{'datastore'};
}

sub print_page {
	my ( $self, $dbase_config_dir ) = @_;
	my $set_options = 0;
	my $cookies;
	my %classes = (
		'index'              => 'IndexPage',
		'browse'             => 'BrowsePage',
		'query'              => 'QueryPage',
		'pubquery'           => 'PubQueryPage',
		'listQuery'          => 'ListQueryPage',
		'info'               => 'IsolateInfoPage',
		'tableQuery'         => 'TableQueryPage',
		'options'            => 'OptionsPage',
		'profiles'           => 'ProfileQueryPage',
		'batchProfiles'      => 'BatchProfileQueryPage',
		'sequenceQuery'      => 'SequenceQueryPage',
		'batchSequenceQuery' => 'SequenceQueryPage',
		'customize'          => 'CustomizePage',
		'recordInfo'         => 'RecordInfoPage',
		'version'            => 'VersionPage',
		'plugin'             => 'Plugin',
		'profileInfo'        => 'ProfileInfoPage',
		'downloadAlleles'    => 'DownloadAllelesPage',
		'downloadProfiles'   => 'DownloadProfilesPage',
		'downloadSeqbin'     => 'DownloadSeqbinPage',
		'seqbin'             => 'SeqbinPage',
		'embl'               => 'SeqbinToEMBL',
		'alleleSequence'     => 'AlleleSequencePage',
		'changePassword'     => 'ChangePasswordPage',
		'alleleInfo'         => 'AlleleInfoPage',
		'fieldValues'        => 'FieldHelpPage',
		'extractedSequence'  => 'ExtractedSequencePage',
		'alleleQuery'		 => 'AlleleQueryPage',
		'locusInfo'			 => 'LocusInfoPage'
	);
	my $page;
	my %page_attributes = (
		'system'           => $self->{'system'},
		'dbase_config_dir' => $dbase_config_dir,
		'cgi'              => $self->{'cgi'},
		'instance'         => $self->{'instance'},
		'prefs'            => $self->{'prefs'},
		'prefstore'        => $self->{'prefstore'},
		'config'           => $self->{'config'},
		'datastore'        => $self->{'datastore'},
		'db'               => $self->{'db'},
		'xmlHandler'       => $self->{'xmlHandler'},
		'dataConnector'    => $self->{'dataConnector'},
		'pluginManager'    => $self->{'pluginManager'},
		'mod_perl_request' => $self->{'mod_perl_request'},
	);
	my $continue = 1;
	my $auth_cookies_ref;

	if ( $self->{'error'} ) {
		$page_attributes{'error'} = $self->{'error'};
		$page = BIGSdb::ErrorPage->new(%page_attributes);
		$page->print();
		return;
	} elsif ( $self->{'system'}->{'read_access'} ne 'public' ) {
		( $continue, $auth_cookies_ref ) = $self->authenticate( \%page_attributes );
	}
	return if !$continue;
	if ( $self->{'system'}->{'read_access'} eq 'acl' ) {
		$self->initiate_view( \%page_attributes );    #replace current view with one containing only isolates viewable by user
		$page_attributes{'system'} = $self->{'system'};
	}
	if ( $self->{'page'} eq 'options'
		&& ( $self->{'cgi'}->param('set') || $self->{'cgi'}->param('reset') ) )
	{
		$page           = BIGSdb::OptionsPage->new(%page_attributes);
		$page->initiate_prefs;
		$page->set_options;
		$self->{'page'} = 'index';
		$self->{'cgi'}->param('page','index'); #stop prefs initiating twice
		$set_options    = 1;
		
	}
	if ( !$self->{'db'} ) {
		$page_attributes{'error'} = 'noConnect';
		$page = BIGSdb::ErrorPage->new(%page_attributes);
	} elsif ( !$self->{'prefstore'} ) {
		$page_attributes{'error'} = 'noPrefs';
		$page_attributes{'fatal'} = $self->{'fatal'};
		$page                     = BIGSdb::ErrorPage->new(%page_attributes);
	} elsif ( $classes{ $self->{'page'} } ) {
		$page_attributes{'cookies'} = $cookies;
		if ( ref $auth_cookies_ref eq 'ARRAY' ) {
			foreach (@$auth_cookies_ref) {
				push @{ $page_attributes{'cookies'} }, $_;
			}
		}
		$page_attributes{'setOptions'} = $set_options;
		$page = "BIGSdb::$classes{$self->{'page'}}"->new(%page_attributes);
	} else {
		$page_attributes{'error'} = 'unknown';
		$page = BIGSdb::ErrorPage->new(%page_attributes);
	}
	$page->print();
}

sub authenticate {
	my ( $self, $page_attributes ) = @_;
	my $auth_cookies_ref;
	my $authenticated = 1;
	if ( $self->{'system'}->{'authentication'} eq 'apache' ) {
		if ( $self->{'cgi'}->remote_user ) {
			$page_attributes->{'username'} = $self->{'cgi'}->remote_user;
		} else {
			$page_attributes->{'error'} = 'userNotAuthenticated';
			my $page = BIGSdb::ErrorPage->new(%$page_attributes);
			$page->print();
			$authenticated = 0;
		}
	} else {    #use built-in authentication
		my $logger = get_logger('BIGSdb.Application_Authentication');
		$page_attributes->{'auth_db'} = $self->{'auth_db'};
		$page_attributes->{'vars'}    = $self->{'cgi'}->Vars;
		my $page = BIGSdb::LoginMD5->new(%$page_attributes);
		my $logging_out;
		if ( $self->{'page'} eq 'logout' ) {
			$auth_cookies_ref = $page->logout;
			$page->set_cookie_attributes($auth_cookies_ref);
			$self->{'page'} = 'index';
			$logging_out = 1;
		}
		try {
			throw BIGSdb::AuthenticationException('logging out') if $logging_out;
			$page_attributes->{'username'} = $page->login_from_cookie;
		}
		catch BIGSdb::AuthenticationException with {
			$logger->info("No cookie set - asking for log in");
			try {
				( $page_attributes->{'username'}, $auth_cookies_ref ) = $page->secure_login;
			}
			catch BIGSdb::CannotOpenFileException with {
				$page_attributes->{'error'} = 'userAuthenticationFiles';
				$page = BIGSdb::ErrorPage->new(%$page_attributes);
				$page->print();
			}
			catch BIGSdb::AuthenticationException with {

				#failed again
				$authenticated = 0;
			};
		};
	}
	if ($authenticated) {
		$page_attributes->{'permissions'} = $self->{'datastore'}->get_permissions( $page_attributes->{'username'} );
		if ( $page_attributes->{'permissions'}->{'disable_access'} ) {
			$page_attributes->{'error'} = 'accessDisabled';
			my $page = BIGSdb::ErrorPage->new(%$page_attributes);
			$page->print();
			$authenticated = 0;
		}
	}
	return ( $authenticated, $auth_cookies_ref );
}
1;
