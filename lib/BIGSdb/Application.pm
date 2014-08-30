#Written by Keith Jolley
#(c) 2010-2014, University of Oxford
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
use warnings;
use 5.010;
use BIGSdb::AlleleInfoPage;
use BIGSdb::AlleleQueryPage;
use BIGSdb::AlleleSequencePage;
use BIGSdb::BatchProfileQueryPage;
use BIGSdb::BIGSException;
use BIGSdb::BrowsePage;
use BIGSdb::ChangePasswordPage;
use BIGSdb::CurateSubmissionExcelPage;
use BIGSdb::CustomizePage;
use BIGSdb::Dataconnector;
use BIGSdb::Datastore;
use BIGSdb::DownloadAllelesPage;
use BIGSdb::DownloadProfilesPage;
use BIGSdb::DownloadSeqbinPage;
use BIGSdb::ErrorPage;
use BIGSdb::FieldHelpPage;
use BIGSdb::IndexPage;
use BIGSdb::IsolateInfoPage;
use BIGSdb::IsolateQueryPage;
use BIGSdb::JobsListPage;
use BIGSdb::JobViewerPage;
use BIGSdb::ListQueryPage;
use BIGSdb::LocusInfoPage;
use BIGSdb::LoginMD5;
use BIGSdb::OptionsPage;
use BIGSdb::Parser;
use BIGSdb::PluginManager;
use BIGSdb::Preferences;
use BIGSdb::ProfileInfoPage;
use BIGSdb::ProfileQueryPage;
use BIGSdb::CombinationQueryPage;
use BIGSdb::PubQueryPage;
use BIGSdb::QueryPage;
use BIGSdb::RecordInfoPage;
use BIGSdb::SeqbinPage;
use BIGSdb::SeqbinToEMBL;
use BIGSdb::SequenceQueryPage;
use BIGSdb::SequenceTranslatePage;
use BIGSdb::TableQueryPage;
use BIGSdb::VersionPage;
use BIGSdb::CGI::as_utf8;
use DBI;
use Error qw(:try);
use Log::Log4perl qw(get_logger);
use List::MoreUtils qw(any);
use Config::Tiny;

sub new {
	my ( $class, $config_dir, $lib_dir, $dbase_config_dir, $r, $curate ) = @_;
	my $self = {};
	$self->{'system'}           = {};
	$self->{'config'}           = {};
	$CGI::POST_MAX              = 50 * 1024 * 1024;             #Limit any uploads to 50Mb.
	$CGI::DISABLE_UPLOADS       = 0;
	$self->{'cgi'}              = CGI->new;
	$self->{'instance'}         = undef;
	$self->{'xmlHandler'}       = undef;
	$self->{'page'}             = undef;
	$self->{'invalidXML'}       = 0;
	$self->{'invalidDbType'}    = 0;
	$self->{'dataConnector'}    = BIGSdb::Dataconnector->new;
	$self->{'datastore'}        = undef;
	$self->{'pluginManager'}    = undef;
	$self->{'db'}               = undef;
	$self->{'mod_perl_request'} = $r;
	$self->{'fatal'}            = undef;
	$self->{'curate'}           = $curate;
	$self->{'config_dir'}       = $config_dir;
	$self->{'lib_dir'}          = $lib_dir;
	$self->{'dbase_config_dir'} = $dbase_config_dir;
	bless( $self, $class );
	$self->_initiate( $config_dir, $dbase_config_dir );
	$self->{'dataConnector'}->initiate( $self->{'system'}, $self->{'config'} );
	my $q = $self->{'cgi'};

	if ( !$self->{'error'} ) {
		$self->db_connect;
		if ( $self->{'db'} ) {
			$self->setup_datastore;
			$self->_setup_prefstore;
			if ( !$self->{'system'}->{'authentication'} ) {
				my $logger = get_logger('BIGSdb.Application_Authentication');
				$logger->logdie(
"No authentication attribute set - set to either 'apache' or 'builtin' in the system tag of the XML database description."
				);
			}
			$self->_initiate_authdb if $self->{'system'}->{'authentication'} eq 'builtin';
			$self->_initiate_jobmanager( $config_dir, $dbase_config_dir )
			  if !$self->{'curate'}
			  && ( any { $q->param('page') eq $_ } qw (plugin job jobs index logout options) )
			  && $self->{'config'}->{'jobs_db'};
		}
	}
	$self->initiate_plugins($lib_dir);
	$self->print_page;
	$self->_db_disconnect;
	return $self;
}

sub _initiate {
	my ( $self, $config_dir, $dbase_config_dir ) = @_;
	my $q = $self->{'cgi'};
	Log::Log4perl::MDC->put( "ip", $q->remote_host );
	$self->read_config_file($config_dir);
	$self->read_host_mapping_file($config_dir);
	my $logger = get_logger('BIGSdb.Application_Initiate');
	my $db = $self->{'cgi'}->param('db') || '';
	$self->{'instance'} = $db =~ /^([\w\d\-_]+)$/ ? $1 : '';
	my $full_path = "$dbase_config_dir/$self->{'instance'}/config.xml";

	if ( !-e $full_path ) {
		$logger->fatal("Database config file for '$self->{'instance'}' does not exist.");
		$self->{'error'} = 'invalidXML';
		return;
	}
	$self->{'xmlHandler'} = BIGSdb::Parser->new;
	my $parser = XML::Parser::PerlSAX->new( Handler => $self->{'xmlHandler'} );
	eval { $parser->parse( Source => { SystemId => $full_path } ) };
	if ($@) {
		$logger->fatal("Invalid XML description: $@") if $self->{'instance'} ne '';
		$self->{'error'} = 'invalidXML';
		return;
	}
	$self->{'system'} = $self->{'xmlHandler'}->get_system_hash;
	$self->set_system_overrides;
	if ( !defined $self->{'system'}->{'dbtype'}
		|| ( $self->{'system'}->{'dbtype'} ne 'sequences' && $self->{'system'}->{'dbtype'} ne 'isolates' ) )
	{
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
	$self->{'error'} = 'noAuthenticationSet' if !$self->{'system'}->{'authentication'};
	$self->{'system'}->{'script_name'} = $self->{'script_name'};
	$ENV{'PATH'} = '/bin:/usr/bin';    ## no critic (RequireLocalizedPunctuationVars) #so we don't foul taint check
	delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};    # Make %ENV safer
	$q->param( 'page', 'index' ) if !defined $q->param('page');
	$self->{'page'} = $q->param('page');
	$self->{'system'}->{'read_access'} ||= 'public';      #everyone can view by default
	$self->{'system'}->{'host'}        ||= 'localhost';
	$self->{'system'}->{'port'}        ||= 5432;
	$self->{'system'}->{'user'}        ||= 'apache';
	$self->{'system'}->{'password'}    ||= 'remote';
	$self->{'system'}->{'privacy'}     ||= 'yes';
	$self->{'system'}->{'privacy'} = $self->{'system'}->{'privacy'} eq 'no' ? 0 : 1;
	$self->{'system'}->{'locus_superscript_prefix'} ||= 'no';
	$self->{'system'}->{'dbase_config_dir'} = $dbase_config_dir;

	if ( ( $self->{'system'}->{'dbtype'} // '' ) eq 'isolates' ) {
		$self->{'system'}->{'view'}       ||= 'isolates';
		$self->{'system'}->{'labelfield'} ||= 'isolate';
		if ( !$self->{'xmlHandler'}->is_field( $self->{'system'}->{'labelfield'} ) ) {
			$logger->error( "The defined labelfield '$self->{'system'}->{'labelfield'}' does not exist in the database.  "
				  . "Please set the labelfield attribute in the system tag of the database XML file." );
		}
	}

	#Allow individual database configs to override system auth and pref databases and tmp directories
	$self->{'config'}->{'prefs_db'}       = $self->{'system'}->{'prefs_db'}       if defined $self->{'system'}->{'prefs_db'};
	$self->{'config'}->{'auth_db'}        = $self->{'system'}->{'auth_db'}        if defined $self->{'system'}->{'auth_db'};
	$self->{'config'}->{'tmp_dir'}        = $self->{'system'}->{'tmp_dir'}        if defined $self->{'system'}->{'tmp_dir'};
	$self->{'config'}->{'secure_tmp_dir'} = $self->{'system'}->{'secure_tmp_dir'} if defined $self->{'system'}->{'secure_tmp_dir'};

	#refdb attribute has been renamed ref_db for consistency with other databases (refdb still works)
	$self->{'config'}->{'ref_db'} //= $self->{'config'}->{'refdb'};
	$self->{'config'}->{'ref_db'} = $self->{'system'}->{'ref_db'} if defined $self->{'system'}->{'ref_db'};
	
	#dbase_job_quota attribute has been renamed job_quota for consistency (dbase_job_quota still works)
	$self->{'system'}->{'job_quota'} //= $self->{'system'}->{'dbase_job_quota'};
	return;
}

sub set_system_overrides {
	my ($self) = @_;
	my $override_file = "$self->{'dbase_config_dir'}/$self->{'instance'}/system.overrides";
	if ( -e $override_file ) {
		open( my $fh, '<', $override_file ) || get_logger('BIGSdb.Application_Initiate')->error("Can't open $override_file for reading");
		while ( my $line = <$fh> ) {
			next if $line =~ /^#/;
			$line =~ s/^\s+//;
			$line =~ s/\s+$//;
			if ( $line =~ /^([^=\s]+)\s*=\s*"([^"]+)"$/ ) {
				$self->{'system'}->{$1} = $2;
			}
		}
		close $fh;
	}
	return;
}

sub _initiate_authdb {
	my ($self) = @_;
	my $logger = get_logger('BIGSdb.Application_Initiate');
	my %att    = (
		dbase_name => $self->{'config'}->{'auth_db'},
		host       => $self->{'system'}->{'host'},
		port       => $self->{'system'}->{'port'},
		user       => $self->{'system'}->{'user'},
		password   => $self->{'system'}->{'password'},
	);
	try {
		$self->{'auth_db'} = $self->{'dataConnector'}->get_connection( \%att );
		$logger->info("Connected to authentication database '$self->{'config'}->{'auth_db'}'");
	}
	catch BIGSdb::DatabaseConnectionException with {
		$logger->error("Can not connect to authentication database '$self->{'config'}->{'auth_db'}'");
		$self->{'error'} = 'noAuth';
	};
	return;
}

sub initiate_plugins {
	my ( $self, $plugin_dir ) = @_;
	$self->{'pluginManager'} = BIGSdb::PluginManager->new(
		system           => $self->{'system'},
		cgi              => $self->{'cgi'},
		instance         => $self->{'instance'},
		prefstore        => $self->{'prefstore'},
		config           => $self->{'config'},
		datastore        => $self->{'datastore'},
		db               => $self->{'db'},
		xmlHandler       => $self->{'xmlHandler'},
		dataConnector    => $self->{'dataConnector'},
		mod_perl_request => $self->{'mod_perl_request'},
		jobManager       => $self->{'jobManager'},
		pluginDir        => $plugin_dir
	);
	return;
}

sub _initiate_jobmanager {
	my ( $self, $config_dir, $dbase_config_dir, ) = @_;
	$self->{'jobManager'} = BIGSdb::OfflineJobManager->new(
		{
			config_dir       => $config_dir,
			dbase_config_dir => $dbase_config_dir,
			host             => $self->{'system'}->{'host'},
			port             => $self->{'system'}->{'port'},
			user             => $self->{'system'}->{'user'},
			password         => $self->{'system'}->{'password'},
			system           => $self->{'system'}
		}
	);
	return;
}

sub read_config_file {
	my ( $self, $config_dir ) = @_;
	my $logger = get_logger('BIGSdb.Application_Initiate');
	my $config = Config::Tiny->new();
	$config = Config::Tiny->read("$config_dir/bigsdb.conf");
	foreach (
		qw ( prefs_db auth_db jobs_db max_load emboss_path tmp_dir secure_tmp_dir blast+_path blast_threads
		muscle_path	max_muscle_mb mafft_path mogrify_path ipcress_path splitstree_path reference refdb ref_db chartdirector
		disable_updates disable_update_message intranet debug results_deleted_days cache_days doclink)
	  )
	{
		$self->{'config'}->{$_} = $config->{_}->{$_};
	}
	$self->{'config'}->{'intranet'} ||= 'no';
	$self->{'config'}->{'cache_days'} //= 7;
	if ( $self->{'config'}->{'chartdirector'} ) {
		eval "use perlchartdir;";    ## no critic (ProhibitStringyEval)
		if ($@) {
			$logger->error("Chartdirector not installed! - Either install or set 'chartdirector=0' in bigsdb.conf");
			$self->{'config'}->{'chartdirector'} = 0;
		} else {
			eval "use BIGSdb::Charts;";    ## no critic (ProhibitStringyEval)
			if ($@) {
				$logger->error("Charts.pm not installed!");
			}
		}
	}
	$self->{'config'}->{'aligner'} = 1 if $self->{'config'}->{'muscle_path'} || $self->{'config'}->{'mafft_path'};
	$self->{'config'}->{'doclink'} //= 'http://bigsdb.readthedocs.org/en/latest';
	return;
}

sub read_host_mapping_file {
	my ( $self, $config_dir ) = @_;
	my $mapping_file = "$config_dir/host_mapping.conf";
	if ( -e $mapping_file ) {
		open( my $fh, '<', $mapping_file ) || get_logger('BIGSdb.Application_Initiate')->error("Can't open $mapping_file for reading");
		while (<$fh>) {
			next if /^\s+$/ || /^#/;
			my ( $host, $mapped ) = split /\s+/, $_;
			next if !$host || !$mapped;
			$self->{'config'}->{'host_map'}->{$host} = $mapped;
		}
		close $fh;
	}
	return;
}

sub _setup_prefstore {
	my ($self) = @_;
	my %att = (
		dbase_name => $self->{'config'}->{'prefs_db'},
		host       => $self->{'system'}->{'host'},
		port       => $self->{'system'}->{'port'},
		user       => $self->{'system'}->{'user'},
		password   => $self->{'system'}->{'password'},
	);
	my $pref_db;
	try {
		$pref_db = $self->{'dataConnector'}->get_connection( \%att );
	}
	catch BIGSdb::DatabaseConnectionException with {
		my $logger = get_logger('BIGSdb.Prefs');
		$logger->fatal("Can not connect to preferences database '$self->{'config'}->{'prefs_db'}'");
	};
	$self->{'prefstore'} = BIGSdb::Preferences->new( db => $pref_db );
	return;
}

sub setup_datastore {
	my ($self) = @_;
	$self->{'datastore'} = BIGSdb::Datastore->new(
		db            => $self->{'db'},
		dataConnector => $self->{'dataConnector'},
		system        => $self->{'system'},
		config        => $self->{'config'},
		xmlHandler    => $self->{'xmlHandler'}
	);
	return;
}

sub db_connect {
	my ($self) = @_;
	my %att = (
		dbase_name => $self->{'system'}->{'db'},
		host       => $self->{'system'}->{'host'},
		port       => $self->{'system'}->{'port'},
		user       => $self->{'system'}->{'user'},
		password   => $self->{'system'}->{'password'}
	);
	try {
		$self->{'db'} = $self->{'dataConnector'}->get_connection( \%att );
	}
	catch BIGSdb::DatabaseConnectionException with {
		my $logger = get_logger('BIGSdb.Application_Initiate');
		$logger->error("Can not connect to database '$self->{'system'}->{'db'}'");
	};
	return;
}

sub _db_disconnect {
	my ($self) = @_;
	$self->{'prefstore'}->finish_statement_handles if $self->{'prefstore'};
	undef $self->{'prefstore'};
	undef $self->{'datastore'};
	return;
}

sub print_page {
	my ($self) = @_;
	my $set_options = 0;
	my $cookies;
	my %classes = (
		index              => 'IndexPage',
		browse             => 'BrowsePage',
		query              => ( ( $self->{'system'}->{'dbtype'} // '' ) eq 'isolates' ? 'IsolateQueryPage' : 'ProfileQueryPage' ),
		pubquery           => 'PubQueryPage',
		listQuery          => 'ListQueryPage',
		info               => 'IsolateInfoPage',
		tableQuery         => 'TableQueryPage',
		options            => 'OptionsPage',
		profiles           => 'CombinationQueryPage',
		batchProfiles      => 'BatchProfileQueryPage',
		sequenceQuery      => 'SequenceQueryPage',
		batchSequenceQuery => 'SequenceQueryPage',
		sequenceTranslate  => 'SequenceTranslatePage',
		customize          => 'CustomizePage',
		recordInfo         => 'RecordInfoPage',
		version            => 'VersionPage',
		plugin             => 'Plugin',
		profileInfo        => 'ProfileInfoPage',
		downloadAlleles    => 'DownloadAllelesPage',
		downloadProfiles   => 'DownloadProfilesPage',
		downloadSeqbin     => 'DownloadSeqbinPage',
		seqbin             => 'SeqbinPage',
		embl               => 'SeqbinToEMBL',
		alleleSequence     => 'AlleleSequencePage',
		changePassword     => 'ChangePasswordPage',
		alleleInfo         => 'AlleleInfoPage',
		fieldValues        => 'FieldHelpPage',
		extractedSequence  => 'ExtractedSequencePage',
		alleleQuery        => 'AlleleQueryPage',
		locusInfo          => 'LocusInfoPage',
		job                => 'JobViewerPage',
		jobs               => 'JobsListPage',
		excelTemplate      => 'CurateSubmissionExcelPage'
	);
	my $page;
	my %page_attributes = (
		system           => $self->{'system'},
		dbase_config_dir => $self->{'dbase_config_dir'},
		config_dir       => $self->{'config_dir'},
		lib_dir          => $self->{'lib_dir'},
		cgi              => $self->{'cgi'},
		instance         => $self->{'instance'},
		prefs            => $self->{'prefs'},
		prefstore        => $self->{'prefstore'},
		config           => $self->{'config'},
		datastore        => $self->{'datastore'},
		db               => $self->{'db'},
		xmlHandler       => $self->{'xmlHandler'},
		dataConnector    => $self->{'dataConnector'},
		pluginManager    => $self->{'pluginManager'},
		mod_perl_request => $self->{'mod_perl_request'},
		jobManager       => $self->{'jobManager'},
		curate           => 0
	);
	my $continue = 1;
	my $auth_cookies_ref;

	if ( $self->{'error'} ) {
		$page_attributes{'error'} = $self->{'error'};
		$page = BIGSdb::ErrorPage->new(%page_attributes);
		$page->print_page_content;
		return;
	} elsif ( $self->{'system'}->{'read_access'} ne 'public' ) {
		( $continue, $auth_cookies_ref ) = $self->authenticate( \%page_attributes );
	}
	return if !$continue;
	if ( $self->{'page'} eq 'options'
		&& ( $self->{'cgi'}->param('set') || $self->{'cgi'}->param('reset') ) )
	{
		$page = BIGSdb::OptionsPage->new(%page_attributes);
		$page->initiate_prefs;
		$page->set_options;
		$self->{'page'} = 'index';
		$self->{'cgi'}->param( 'page', 'index' );    #stop prefs initiating twice
		$set_options = 1;
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
	$page->print_page_content;
	return;
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
			$page->print_page_content;
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
				$page->print_page_content;
			}
			catch BIGSdb::AuthenticationException with {

				#failed again
				$authenticated = 0;
			};
		};
	}
	if ($authenticated) {
		my $config_access = $self->{'system'}->{'default_access'} ? $self->_user_allowed_access( $page_attributes->{'username'} ) : 1;
		$page_attributes->{'permissions'} = $self->{'datastore'}->get_permissions( $page_attributes->{'username'} );
		if ( $page_attributes->{'permissions'}->{'disable_access'} ) {
			$page_attributes->{'error'} = 'accessDisabled';
			my $page = BIGSdb::ErrorPage->new(%$page_attributes);
			$page->print_page_content;
			$authenticated = 0;
		} elsif ( !$config_access ) {
			$page_attributes->{'error'} = 'configAccessDenied';
			my $page = BIGSdb::ErrorPage->new(%$page_attributes);
			$page->print_page_content;
			$authenticated = 0;
		}
	}
	return ( $authenticated, $auth_cookies_ref );
}

sub _user_allowed_access {
	my ( $self, $username ) = @_;
	if ( $self->{'system'}->{'default_access'} eq 'deny' ) {
		my $allow_file = "$self->{'dbase_config_dir'}/$self->{'instance'}/users.allow";
		return 1 if -e $allow_file && $self->_is_name_in_file( $username, $allow_file );
		return 0;
	} elsif ( $self->{'system'}->{'default_access'} eq 'allow' ) {
		my $deny_file = "$self->{'dbase_config_dir'}/$self->{'instance'}/users.deny";
		return 0 if -e $deny_file && $self->_is_name_in_file( $username, $deny_file );
		return 1;
	} else {
		return 0;
	}
}

sub _is_name_in_file {
	my ( $self, $name, $filename ) = @_;
	throw BIGSdb::FileException("File $filename does not exist") if !-e $filename;
	my $logger = get_logger('BIGSdb.Application_Authentication');
	open( my $fh, '<', $filename ) || $logger->error("Can't open $filename for reading");
	while ( my $line = <$fh> ) {
		next if $line =~ /^#/;
		$line =~ s/^\s+//;
		$line =~ s/\s+$//;
		if ( $line eq $name ) {
			close $fh;
			return 1;
		}
	}
	close $fh;
	return 0;
}
1;
