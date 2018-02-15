#Written by Keith Jolley
#(c) 2010-2018, University of Oxford
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
use parent qw(BIGSdb::BaseApplication);
use BIGSdb::AjaxMenu;
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
use BIGSdb::IDList;
use BIGSdb::IndexPage;
use BIGSdb::IsolateInfoPage;
use BIGSdb::IsolateQueryPage;
use BIGSdb::JobsListPage;
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
use Error qw(:try);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Application_Initiate');
use List::MoreUtils qw(any);
use Config::Tiny;
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
		ajaxMenu           => 'AjaxMenu',
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
1;
