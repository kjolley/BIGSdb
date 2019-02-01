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
use Apache2::Connection;
use parent qw(BIGSdb::BaseApplication);
use BIGSdb::AjaxJobs;
use BIGSdb::AjaxMenu;
use BIGSdb::AjaxPrefs;
use BIGSdb::AlleleInfoPage;
use BIGSdb::AlleleQueryPage;
use BIGSdb::AlleleSequencePage;
use BIGSdb::AuthorizeClientPage;
use BIGSdb::BatchProfileQueryPage;
use BIGSdb::ChangePasswordPage;
use BIGSdb::CombinationQueryPage;
use BIGSdb::Constants qw(:login_requirements);
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
use constant PAGES_NEEDING_JOB_MANAGER        => qw(plugin job jobs index login logout options);
use constant PAGES_NEEDING_SUBMISSION_HANDLER => qw(submit batchAddFasta profileAdd profileBatchAdd batchAdd
  batchIsolateUpdate isolateAdd isolateUpdate index logout);

sub print_page {
	my ($self) = @_;
	my $set_options = 0;
	my $cookies;
	my $query_page = ( $self->{'system'}->{'dbtype'} // '' ) eq 'isolates' ? 'IsolateQueryPage' : 'ProfileQueryPage';
	my %classes = (
		ajaxJobs           => 'AjaxJobs',
		ajaxMenu           => 'AjaxMenu',
		ajaxPrefs          => 'AjaxPrefs',
		alleleInfo         => 'AlleleInfoPage',
		alleleQuery        => 'AlleleQueryPage',
		alleleSequence     => 'AlleleSequencePage',
		authorizeClient    => 'AuthorizeClientPage',
		batchProfiles      => 'BatchProfileQueryPage',
		batchSequenceQuery => 'SequenceQueryPage',
		browse             => $query_page,
		changePassword     => 'ChangePasswordPage',
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
		plugin             => 'Plugin',
		privateRecords     => 'PrivateRecordsPage',
		profileInfo        => 'ProfileInfoPage',
		profiles           => 'CombinationQueryPage',
		projects           => 'ProjectsPage',
		recordInfo         => 'RecordInfoPage',
		registration       => 'UserRegistrationPage',
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
	if ( $self->{'db'} && $self->{'page'} ne 'registration' && $self->{'page'} ne 'usernameRemind' ) {
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
