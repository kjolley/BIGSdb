#Written by Keith Jolley
#(c) 2010-2019, University of Oxford
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
use version; our $VERSION = version->declare('v1.23.2');
use Apache2::Connection;
use parent qw(BIGSdb::BaseApplication);
use BIGSdb::AjaxJobs;
use BIGSdb::AjaxMenu;
use BIGSdb::AjaxPrefs;
use BIGSdb::AjaxRest;
use BIGSdb::AlleleInfoPage;
use BIGSdb::AlleleQueryPage;
use BIGSdb::AlleleSequencePage;
use BIGSdb::AuthorizeClientPage;
use BIGSdb::BatchProfileQueryPage;
use BIGSdb::ChangePasswordPage;
use BIGSdb::CGI::as_utf8;
use BIGSdb::CombinationQueryPage;
use BIGSdb::Constants qw(:login_requirements);
use BIGSdb::CookiesPage;
use BIGSdb::CurateSubmissionExcelPage;
use BIGSdb::CustomizePage;
use BIGSdb::DownloadAllelesPage;
use BIGSdb::DownloadProfilesPage;
use BIGSdb::DownloadSeqbinPage;
use BIGSdb::ErrorPage;
use BIGSdb::FieldHelpPage;
use BIGSdb::DownloadFilePage;
use BIGSdb::IDList;
use BIGSdb::IndexPage;
use BIGSdb::IsolateInfoPage;
use BIGSdb::IsolateQueryPage;
use BIGSdb::JobsListPage;
use BIGSdb::JobMonitorPage;
use BIGSdb::JobViewerPage;
use BIGSdb::LocusInfoPage;
use BIGSdb::Login;
use BIGSdb::OptionsPage;
use BIGSdb::PrivateRecordsPage;
use BIGSdb::ProfileInfoPage;
use BIGSdb::ProfileQueryPage;
use BIGSdb::ProjectsPage;
use BIGSdb::PubQueryPage;
use BIGSdb::QueryPage;
use BIGSdb::RecordInfoPage;
use BIGSdb::RestMonitorPage;
use BIGSdb::SchemeInfoPage;
use BIGSdb::SeqbinPage;
use BIGSdb::SequenceQueryPage;
use BIGSdb::SequenceTranslatePage;
use BIGSdb::SubmitPage;
use BIGSdb::TableQueryPage;
use BIGSdb::UserPage;
use BIGSdb::UserProjectsPage;
use BIGSdb::UserRegistrationPage;
use BIGSdb::VersionPage;
use BIGSdb::Offline::Blast;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Application_Initiate');
use List::MoreUtils qw(any);
use Config::Tiny;
use Try::Tiny;
use constant PAGES_NEEDING_AUTHENTICATION     => qw(authorizeClient changePassword userProjects submit login logout);
use constant PAGES_NEEDING_JOB_MANAGER        => qw(plugin job jobs index login logout options ajaxJobs);
use constant PAGES_NEEDING_SUBMISSION_HANDLER => qw(submit batchAddFasta profileAdd profileBatchAdd batchAdd
  batchAddSequences batchIsolateUpdate isolateAdd isolateUpdate index logout);
use constant PAGES_NOT_NEEDING_PLUGINS => qw(ajaxJobs jobMonitor ajaxRest restMonitor);

sub new {
	my ( $class, $config_dir, $lib_dir, $dbase_config_dir, $r, $curate ) = @_;
	my $self = {};
	$self->{'system'}           = {};
	$self->{'config'}           = {};
	$self->{'instance'}         = undef;
	$self->{'xmlHandler'}       = undef;
	$self->{'page'}             = undef;
	$self->{'invalidXML'}       = 0;
	$self->{'invalidDbType'}    = 0;
	$self->{'dataConnector'}    = BIGSdb::Dataconnector->new;
	$self->{'datastore'}        = undef;
	$self->{'db'}               = undef;
	$self->{'mod_perl_request'} = $r;
	$self->{'fatal'}            = undef;
	$self->{'curate'}           = $curate;
	$self->{'config_dir'}       = $config_dir;
	$self->{'lib_dir'}          = $lib_dir;
	$self->{'dbase_config_dir'} = $dbase_config_dir;
	bless( $self, $class );
	$self->read_config_file($config_dir);
	$self->{'config'}->{'version'} = $VERSION;
	$self->{'max_upload_size_mb'} = $self->{'config'}->{'max_upload_size'};
	$ENV{'TMPDIR'} =    ## no critic (RequireLocalizedPunctuationVars)
	  $self->{'config'}->{'secure_tmp_dir'};

	#Under SSL if upload size > CGI::POST_MAX then call will fail but not return useful message.
	#The following will stop a ridiculously large upload (>2GB).
	$CGI::POST_MAX        = 2 * 1024 * 1024 * 1024;
	$CGI::DISABLE_UPLOADS = 0;
	$self->{'cgi'}        = CGI->new;
	$self->_initiate( $config_dir, $dbase_config_dir );
	$self->{'dataConnector'}->initiate( $self->{'system'}, $self->{'config'} );
	$self->{'pages_needing_authentication'} = { map { $_ => 1 } PAGES_NEEDING_AUTHENTICATION };
	$self->{'pages_needing_authentication'}->{'user'} = 1 if $self->{'config'}->{'site_user_dbs'};
	my $q = $self->{'cgi'};
	$self->initiate_authdb
	  if $self->{'config'}->{'site_user_dbs'} || ( $self->{'system'}->{'authentication'} // q() ) eq 'builtin';
	my %job_manager_pages = map { $_ => 1 } PAGES_NEEDING_JOB_MANAGER;

	if ( $self->{'instance'} && !$self->{'error'} ) {
		$self->db_connect;
		if ( $self->{'db'} ) {
			$self->setup_datastore;
			$self->_setup_prefstore;
			if ( !$self->{'system'}->{'authentication'} ) {
				$logger->logdie( q(No authentication attribute set - set to either 'apache' or 'builtin' )
					  . q(in the system tag of the XML database description.) );
			}
			$self->{'datastore'}->initiate_userdbs;
			$self->initiate_jobmanager( $config_dir, $dbase_config_dir )
			  if $job_manager_pages{ $q->param('page') }
			  && $self->{'config'}->{'jobs_db'};
			my %submission_handler_pages = map { $_ => 1 } PAGES_NEEDING_SUBMISSION_HANDLER;
			$self->setup_submission_handler if $submission_handler_pages{ $q->param('page') };
			$self->setup_remote_contig_manager;
		}
	} elsif ( !$self->{'instance'} ) {
		if ( $self->{'page'} eq 'ajaxJobs' ) {
			$self->initiate_jobmanager( $config_dir, $dbase_config_dir );
		} elsif ( $self->{'page'} eq 'ajaxRest' && $self->{'config'}->{'rest_db'} ) {
			$self->{'system'}->{'db'} = $self->{'config'}->{'rest_db'};
			$self->db_connect;
			if ( $self->{'db'} ) {
				$self->setup_datastore;
			}
		} else {
			if ( $self->{'config'}->{'site_user_dbs'} ) {

				#Set db to one of these, connect and then inititate Datastore etc.
				#We can change the Datastore db later if needed.
				$self->{'system'}->{'db'}          = $self->{'config'}->{'site_user_dbs'}->[0]->{'dbase'};
				$self->{'system'}->{'description'} = $self->{'config'}->{'site_user_dbs'}->[0]->{'name'};
				$self->{'system'}->{'webroot'}     = '/';
				$self->db_connect;
				if ( $self->{'db'} ) {
					$self->setup_datastore;
				}
			}
		}
	}
	$self->app_specific_initiation;
	$self->print_page;
	$self->_db_disconnect;

	#Prevent apache appending its own error pages.
	if ( $self->{'handled_error'} && $ENV{'MOD_PERL'} ) {
		$self->{'mod_perl_request'}->rflush;
		$self->{'mod_perl_request'}->status(200);
	}
	return $self;
}

sub _initiate {
	my ( $self, $config_dir, $dbase_config_dir ) = @_;
	my $q = $self->{'cgi'};
	Log::Log4perl::MDC->put( 'ip', $q->remote_host );
	$self->read_host_mapping_file($config_dir);
	my $content_length = $ENV{'CONTENT_LENGTH'} // 0;
	if ( $content_length > $self->{'max_upload_size_mb'} ) {
		$self->{'error'} = 'tooBig';
		my $size = BIGSdb::Utils::get_nice_size($content_length);
		$logger->fatal("Attempted upload too big - $size.");
		return;
	}
	my $db = $q->param('db');
	$q->param( page => 'index' ) if !defined $q->param('page');

	#Prevent cross-site scripting vulnerability
	( my $cleaned_page = $q->param('page') ) =~ s/[^A-z].*$//x;
	$q->param( page => $cleaned_page );
	$self->{'page'} = $q->param('page');
	return if $self->_is_job_page;
	return if $self->_is_rest_page;
	return if $self->_is_user_page;
	$self->{'instance'} = $db =~ /^([\w\d\-_]+)$/x ? $1 : '';
	my $full_path = "$dbase_config_dir/$self->{'instance'}/config.xml";

	if ( !-e $full_path ) {
		$logger->fatal("Database config file for '$self->{'instance'}' does not exist.");
		$self->{'error'} = 'missingXML';
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
	$self->_check_kiosk_page;
	$self->set_system_overrides;
	if ( !defined $self->{'system'}->{'dbtype'}
		|| ( $self->{'system'}->{'dbtype'} ne 'sequences' && $self->{'system'}->{'dbtype'} ne 'isolates' ) )
	{
		$self->{'error'} = 'invalidDbType';
	}
	$self->{'script_name'} = $q->script_name || 'bigsdb.pl';
	if ( $self->{'curate'} && $self->{'system'}->{'curate_path_includes'} ) {
		if ( $self->{'script_name'} !~ /$self->{'system'}->{'curate_path_includes'}/x ) {
			$self->{'error'} = 'invalidScriptPath';
			$logger->error("Invalid curate script path - $self->{'script_name'}");
		}
	} elsif ( !$self->{'curate'} && $self->{'system'}->{'script_path_includes'} ) {
		if ( $self->{'script_name'} !~ /$self->{'system'}->{'script_path_includes'}/x ) {
			$self->{'error'} = 'invalidScriptPath';
			$logger->error("Invalid script path - $self->{'script_name'}");
		}
	}
	if ( !$self->{'system'}->{'authentication'} ) {
		$self->{'error'} = 'noAuthenticationSet';
	} elsif ( $self->{'system'}->{'authentication'} ne 'apache' && $self->{'system'}->{'authentication'} ne 'builtin' )
	{
		$self->{'error'} = 'invalidAuthenticationSet';
	}
	$self->{'system'}->{'script_name'} = $self->{'script_name'};
	$self->{'system'}->{'query_script'}  //= $self->{'config'}->{'query_script'}  // 'bigsdb.pl';
	$self->{'system'}->{'curate_script'} //= $self->{'config'}->{'curate_script'} // 'bigscurate.pl';
	$ENV{'PATH'} = '/bin:/usr/bin';    ## no critic (RequireLocalizedPunctuationVars) #so we don't foul taint check
	delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};    # Make %ENV safer
	$self->{'page'} = $q->param('page');
	$self->{'system'}->{'read_access'} //= 'public';    #everyone can view by default
	$self->set_dbconnection_params;
	$self->{'system'}->{'privacy'} //= 'yes';
	$self->{'system'}->{'privacy'} = $self->{'system'}->{'privacy'} eq 'no' ? 0 : 1;
	$self->{'system'}->{'locus_superscript_prefix'} //= 'no';
	$self->{'system'}->{'dbase_config_dir'} = $dbase_config_dir;

	if ( ( $self->{'system'}->{'dbtype'} // '' ) eq 'isolates' ) {
		$self->{'system'}->{'view'}       //= 'isolates';
		$self->{'system'}->{'labelfield'} //= 'isolate';
		if ( !$self->{'xmlHandler'}->is_field( $self->{'system'}->{'labelfield'} ) ) {
			$logger->error(
				    qq(The defined labelfield '$self->{'system'}->{'labelfield'}' does not exist in the database. )
				  . q(Please set the labelfield attribute in the system tag of the database XML file.) );
		}
	}

	#refdb attribute has been renamed ref_db for consistency with other databases (refdb still works)
	$self->{'config'}->{'ref_db'} //= $self->{'config'}->{'refdb'};

	#Allow individual database configs to override system auth and pref databases and tmp directories
	foreach (qw (prefs_db auth_db tmp_dir secure_tmp_dir ref_db)) {
		$self->{'config'}->{$_} = $self->{'system'}->{$_} if defined $self->{'system'}->{$_};
	}

	#dbase_job_quota attribute has been renamed job_quota for consistency (dbase_job_quota still works)
	$self->{'system'}->{'job_quota'} //= $self->{'system'}->{'dbase_job_quota'};
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
	catch {
		if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
			$logger->fatal("Cannot connect to preferences database '$self->{'config'}->{'prefs_db'}'");
		} else {
			$logger->logdie($_);
		}
	};
	$self->{'prefstore'} = BIGSdb::Preferences->new( db => $pref_db );
	return;
}

sub _db_disconnect {
	my ($self) = @_;
	$self->{'prefstore'}->finish_statement_handles if $self->{'prefstore'};
	undef $self->{'prefstore'};
	undef $self->{'datastore'};
	return;
}

sub _check_kiosk_page {
	my ($self) = @_;
	return if !$self->{'system'}->{'kiosk'};
	my $q = $self->{'cgi'};
	if ( $self->{'system'}->{'kiosk_allowed_pages'} ) {
		my %allowed_pages = map { $_ => 1 } split /,/x, $self->{'system'}->{'kiosk_allowed_pages'};
		return if $allowed_pages{ $q->param('page') };
	}
	$q->param( page => $self->{'system'}->{'kiosk'} ) if $self->{'system'}->{'kiosk'};
	return;
}

#This is not for the REST interface, just web pages that are used to monitor the REST interface.
sub _is_rest_page {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my %rest_page = map { $_ => 1 } qw(ajaxRest restMonitor);
	if ( $rest_page{ $q->param('page') } ) {
		$self->{'system'}->{'dbtype'} = 'rest';
		$self->{'system'}->{'script_name'} =
		  $q->script_name || ( $self->{'curate'} ? 'bigscurate.pl' : 'bigsdb.pl' );
		return 1;
	}
	return;
}

sub _is_job_page {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my %job_page = map { $_ => 1 } qw(ajaxJobs jobMonitor);
	if ( $job_page{ $q->param('page') } ) {
		$self->{'system'}->{'dbtype'} = 'job';
		$self->{'system'}->{'script_name'} =
		  $q->script_name || ( $self->{'curate'} ? 'bigscurate.pl' : 'bigsdb.pl' );
		return 1;
	}
	return;
}

sub _is_user_page {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( !$q->param('db') || $q->param('page') eq 'user' ) {
		$self->{'system'}->{'read_access'} = 'public';
		$self->{'system'}->{'dbtype'}      = 'user';
		$self->{'system'}->{'script_name'} =
		  $q->script_name || ( $self->{'curate'} ? 'bigscurate.pl' : 'bigsdb.pl' );
		my %non_user_page = map { $_ => 1 } qw(logout changePassword registration usernameRemind resetPassword);
		$self->{'page'} = 'user' if !$non_user_page{ $self->{'page'} };
		$q->param( page => 'user' ) if !$non_user_page{ $q->param('page') };
		return 1;
	}
	return;
}

sub print_page {
	my ($self) = @_;
	my $set_options = 0;
	my $cookies;
	my $query_page = ( $self->{'system'}->{'dbtype'} // '' ) eq 'isolates' ? 'IsolateQueryPage' : 'ProfileQueryPage';
	my %classes = (
		ajaxJobs           => 'AjaxJobs',
		ajaxMenu           => 'AjaxMenu',
		ajaxPrefs          => 'AjaxPrefs',
		ajaxRest           => 'AjaxRest',
		alleleInfo         => 'AlleleInfoPage',
		alleleQuery        => 'AlleleQueryPage',
		alleleSequence     => 'AlleleSequencePage',
		authorizeClient    => 'AuthorizeClientPage',
		batchProfiles      => 'BatchProfileQueryPage',
		batchSequenceQuery => 'SequenceQueryPage',
		browse             => $query_page,
		changePassword     => 'ChangePasswordPage',
		cookies            => 'CookiesPage',
		customize          => 'CustomizePage',
		downloadAlleles    => 'DownloadAllelesPage',
		downloadFiles      => 'DownloadFilePage',
		downloadProfiles   => 'DownloadProfilesPage',
		downloadSeqbin     => 'DownloadSeqbinPage',
		embl               => 'SeqbinToEMBL',
		excelTemplate      => 'CurateSubmissionExcelPage',
		extractedSequence  => 'ExtractedSequencePage',
		fieldValues        => 'FieldHelpPage',
		idList             => 'IDList',
		index              => 'IndexPage',
		info               => 'IsolateInfoPage',
		job                => 'JobViewerPage',
		jobMonitor         => 'JobMonitorPage',
		jobs               => 'JobsListPage',
		listQuery          => $query_page,
		locusInfo          => 'LocusInfoPage',
		options            => 'OptionsPage',
		pubquery           => 'PubQueryPage',
		query              => $query_page,
		resetPassword      => 'UserRegistrationPage',
		plugin             => 'Plugin',
		privateRecords     => 'PrivateRecordsPage',
		profileInfo        => 'ProfileInfoPage',
		profiles           => 'CombinationQueryPage',
		projects           => 'ProjectsPage',
		recordInfo         => 'RecordInfoPage',
		registration       => 'UserRegistrationPage',
		restMonitor        => 'RestMonitorPage',
		schemeInfo         => 'SchemeInfoPage',
		seqbin             => 'SeqbinPage',
		sequenceQuery      => 'SequenceQueryPage',
		sequenceTranslate  => 'SequenceTranslatePage',
		submit             => 'SubmitPage',
		tableHeader        => 'CurateTableHeaderPage',
		tableQuery         => 'TableQueryPage',
		user               => 'UserPage',
		userProjects       => 'UserProjectsPage',
		usernameRemind     => 'UserRegistrationPage',
		version            => 'VersionPage'
	);
	my $page;
	my %page_attributes = (
		system               => $self->{'system'},
		dbase_config_dir     => $self->{'dbase_config_dir'},
		config_dir           => $self->{'config_dir'},
		lib_dir              => $self->{'lib_dir'},
		cgi                  => $self->{'cgi'},
		instance             => $self->{'instance'},
		prefs                => $self->{'prefs'},
		prefstore            => $self->{'prefstore'},
		config               => $self->{'config'},
		datastore            => $self->{'datastore'},
		db                   => $self->{'db'},
		auth_db              => $self->{'auth_db'},
		xmlHandler           => $self->{'xmlHandler'},
		submissionHandler    => $self->{'submissionHandler'},
		contigManager        => $self->{'contigManager'},
		dataConnector        => $self->{'dataConnector'},
		pluginManager        => $self->{'pluginManager'},
		mod_perl_request     => $self->{'mod_perl_request'},
		jobManager           => $self->{'jobManager'},
		needs_authentication => $self->{'pages_needing_authentication'}->{ $self->{'page'} },
		curate               => 0
	);
	my $continue = 1;
	my $auth_cookies_ref;

	if ( $self->{'error'} ) {
		$page_attributes{'error'}              = $self->{'error'};
		$page_attributes{'max_upload_size_mb'} = $self->{'max_upload_size_mb'};
		$page                                  = BIGSdb::ErrorPage->new(%page_attributes);
		$page->print_page_content;
		if ( $page_attributes{'error'} ) {
			$self->{'handled_error'} = 1;
		}
		return;
	}
	if (   $self->{'db'}
		&& $self->{'page'} ne 'registration'
		&& $self->{'page'} ne 'usernameRemind'
		&& $self->{'page'} ne 'resetPassword' )
	{
		my $login_requirement = $self->{'datastore'}->get_login_requirement;
		if (   $login_requirement != NOT_ALLOWED
			|| $self->{'pages_needing_authentication'}->{ $self->{'page'} } )
		{
			( $continue, $auth_cookies_ref ) = $self->authenticate( \%page_attributes );
			return if !$continue;
		}
	}
	if ( $self->{'page'} eq 'options'
		&& ( $self->{'cgi'}->param('set') || $self->{'cgi'}->param('reset') ) )
	{
		$page = BIGSdb::OptionsPage->new(%page_attributes);
		$page->initiate_prefs;
		$page->set_options;
		$self->{'page'} = 'index';
		$self->{'cgi'}->param( page => 'index' );    #stop prefs initiating twice
		$set_options = 1;
	}
	if ( $self->{'instance'} && !$self->{'db'} ) {
		$page_attributes{'error'} = 'noConnect';
		$page = BIGSdb::ErrorPage->new(%page_attributes);
	} elsif ( $self->{'instance'} && !$self->{'prefstore'} ) {
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
	if ( $page_attributes{'error'} ) {
		$self->{'handled_error'} = 1;
	}
	return;
}

sub app_specific_initiation {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my %no_plugins = map { $_ => 1 } PAGES_NOT_NEEDING_PLUGINS;
	return if $no_plugins{ $q->param('page') };
	$self->initiate_plugins;
	return;
}

sub authenticate {
	my ( $self, $page_attributes ) = @_;
	my $auth_cookies_ref;
	my $reset_password;
	my $authenticated = 1;
	my $q             = $self->{'cgi'};
	$self->{'system'}->{'authentication'} //= 'builtin';
	if ( $self->{'system'}->{'authentication'} eq 'apache' ) {
		if ( $q->remote_user ) {
			$page_attributes->{'username'} = $q->remote_user;
		} else {
			$page_attributes->{'error'} = 'userNotAuthenticated';
			my $page = BIGSdb::ErrorPage->new(%$page_attributes);
			$page->print_page_content;
			$authenticated = 0;
			$self->{'handled_error'} = 1;
		}
	} else {    #use built-in authentication
		$page_attributes->{'auth_db'} = $self->{'auth_db'};
		$page_attributes->{'vars'}    = $q->Vars;
		if ( !$self->{'instance'} && $self->{'config'}->{'site_user_dbs'} ) {
			$page_attributes->{'show_domains'} = 1;
			$page_attributes->{'system'}->{'db'} = $q->param('db') if $q->param('db');
		}
		my $page = BIGSdb::Login->new(%$page_attributes);
		my $logging_out;
		if ( $self->{'page'} eq 'logout' ) {
			$auth_cookies_ref = $page->logout;
			$page->set_cookie_attributes($auth_cookies_ref);
			$self->{'page'} = 'index';
			$logging_out = 1;
		}
		my $login_requirement = $self->{'datastore'}->get_login_requirement;
		if (   $login_requirement != NOT_ALLOWED
			|| $self->{'pages_needing_authentication'}->{ $self->{'page'} } )
		{
			try {
				BIGSdb::Exception::Authentication->throw('logging out') if $logging_out;
				$page_attributes->{'username'} = $page->login_from_cookie;
				$self->{'page'} = 'changePassword' if $self->{'system'}->{'password_update_required'};
			}
			catch {
				if ( $_->isa('BIGSdb::Exception::Authentication') ) {
					$logger->debug('No cookie set - asking for log in');
					if (   $login_requirement == REQUIRED
						|| $self->{'pages_needing_authentication'}->{ $self->{'page'} } )
					{
						if ( $q->param('no_header') ) {
							$page_attributes->{'error'} = 'ajaxLoggedOut';
							$page = BIGSdb::ErrorPage->new(%$page_attributes);
							$page->print_page_content;
							$authenticated = 0;
						} else {
							my $args = {};
							$args->{'dbase_name'} = $q->param('db') if $q->param('page') eq 'user';
							try {
								( $page_attributes->{'username'}, $auth_cookies_ref, $reset_password ) =
								  $page->secure_login($args);
							}
							catch {    #failed again
								$authenticated = 0;
							};
						}
					}
				} else {
					$logger->logdie($_);
				}
			};
		}
		if ( $login_requirement == OPTIONAL && $self->{'page'} eq 'login' ) {
			$self->{'page'} = 'index';
		}
	}
	if ($reset_password) {
		$self->{'system'}->{'password_update_required'} = 1;
		$q->{'page'}                                    = 'changePassword';
		$self->{'page'}                                 = 'changePassword';
	}
	if ( $authenticated && $page_attributes->{'username'} ) {
		my $config_access = $self->is_user_allowed_access( $page_attributes->{'username'} );
		$page_attributes->{'permissions'} = $self->{'datastore'}->get_permissions( $page_attributes->{'username'} );
		if ( $page_attributes->{'permissions'}->{'disable_access'} ) {
			$page_attributes->{'error'} = 'accessDisabled';
			my $page = BIGSdb::ErrorPage->new(%$page_attributes);
			$page->print_page_content;
			$authenticated = 0;
			$self->{'handled_error'} = 1;
		} elsif ( !$config_access ) {
			$page_attributes->{'error'} = 'configAccessDenied';
			my $page = BIGSdb::ErrorPage->new(%$page_attributes);
			$page->print_page_content;
			$authenticated = 0;
			$self->{'handled_error'} = 1;
		}
	}
	return ( $authenticated, $auth_cookies_ref );
}
1;
