#Written by Keith Jolley
#Copyright (c) 2010-2019, University of Oxford
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
package BIGSdb::Curate;
use strict;
use warnings;
use parent qw(BIGSdb::Application);
use BIGSdb::AjaxMenu;
use BIGSdb::ConfigCheckPage;
use BIGSdb::ConfigRepairPage;
use BIGSdb::CurateAddPage;
use BIGSdb::CurateAddSeqbinPage;
use BIGSdb::CurateAlleleUpdatePage;
use BIGSdb::CurateBatchAddFASTAPage;
use BIGSdb::CurateBatchAddPage;
use BIGSdb::CurateBatchAddSeqbinPage;
use BIGSdb::CurateBatchAddSequencesPage;
use BIGSdb::CurateBatchIsolateUpdatePage;
use BIGSdb::CurateBatchProfileUpdatePage;
use BIGSdb::CurateBatchAddRemoteContigsPage;
use BIGSdb::CurateBatchSetAlleleFlagsPage;
use BIGSdb::CurateCompositeQueryPage;
use BIGSdb::CurateCompositeUpdatePage;
use BIGSdb::CurateDatabankScanPage;
use BIGSdb::CurateDeleteAllPage;
use BIGSdb::CurateDeletePage;
use BIGSdb::CurateExportConfig;
use BIGSdb::CurateGeocodingPage;
use BIGSdb::CurateImportUserPage;
use BIGSdb::CurateIndexPage;
use BIGSdb::CurateIsolateAddPage;
use BIGSdb::CurateIsolateDeletePage;
use BIGSdb::CurateIsolateUpdatePage;
use BIGSdb::CurateLinkToExperimentPage;
use BIGSdb::CurateMembersPage;
use BIGSdb::CurateNewVersionPage;
use BIGSdb::CuratePage;
use BIGSdb::CuratePermissionsPage;
use BIGSdb::CurateProfileAddPage;
use BIGSdb::CurateProfileBatchAddPage;
use BIGSdb::CurateProfileUpdatePage;
use BIGSdb::CuratePublishIsolate;
use BIGSdb::CurateRenumber;
use BIGSdb::CurateSubmissionExcelPage;
use BIGSdb::CurateTableHeaderPage;
use BIGSdb::CurateTagScanPage;
use BIGSdb::CurateTagUpdatePage;
use BIGSdb::CurateUpdatePage;
use BIGSdb::IDList;
use BIGSdb::RefreshSchemeCachePage;
use BIGSdb::Offline::UpdateSchemeCaches;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_page {
	my ($self) = @_;
	my $query_page =
	  ( ( $self->{'system'}->{'dbtype'} // '' ) eq 'isolates' ? 'IsolateQueryPage' : 'ProfileQueryPage' );
	my %classes = (
		ajaxMenu              => 'AjaxMenu',
		add                   => 'CurateAddPage',
		addSeqbin             => 'CurateAddSeqbinPage',
		alleleInfo            => 'AlleleInfoPage',
		alleleQuery           => 'AlleleQueryPage',
		alleleSequence        => 'AlleleSequencePage',
		alleleUpdate          => 'CurateAlleleUpdatePage',
		authorizeClient       => 'AuthorizeClientPage',
		batchAdd              => 'CurateBatchAddPage',
		batchAddFasta         => 'CurateBatchAddFASTAPage',
		batchAddRemoteContigs => 'CurateBatchAddRemoteContigsPage',
		batchIsolateUpdate    => 'CurateBatchIsolateUpdatePage',
		batchProfileUpdate    => 'CurateBatchProfileUpdatePage',
		batchAddSeqbin        => 'CurateBatchAddSeqbinPage',
		batchAddSequences     => 'CurateBatchAddSequencesPage',
		browse                => $query_page,
		changePassword        => 'ChangePasswordPage',
		compositeQuery        => 'CurateCompositeQueryPage',
		compositeUpdate       => 'CurateCompositeUpdatePage',
		configCheck           => 'ConfigCheckPage',
		configRepair          => 'ConfigRepairPage',
		curatorPermissions    => 'CuratePermissionsPage',
		databankScan          => 'CurateDatabankScanPage',
		delete                => 'CurateDeletePage',
		deleteAll             => 'CurateDeleteAllPage',
		downloadSeqbin        => 'DownloadSeqbinPage',
		embl                  => 'SeqbinToEMBL',
		excelTemplate         => 'CurateSubmissionExcelPage',
		exportConfig          => 'CurateExportConfig',
		extractedSequence     => 'ExtractedSequencePage',
		fieldValues           => 'FieldHelpPage',
		geocoding             => 'CurateGeocodingPage',
		importUser            => 'CurateImportUserPage',
		idList                => 'IDList',
		index                 => 'CurateIndexPage',
		info                  => 'IsolateInfoPage',
		isolateAdd            => 'CurateIsolateAddPage',
		isolateDelete         => 'CurateIsolateDeletePage',
		isolateUpdate         => 'CurateIsolateUpdatePage',
		linkToExperiment      => 'CurateLinkToExperimentPage',
		listQuery             => 'ListQueryPage',
		memberUpdate          => 'CurateMembersPage',
		newVersion            => 'CurateNewVersionPage',
		options               => 'OptionsPage',
		profileAdd            => 'CurateProfileAddPage',
		profileBatchAdd       => 'CurateProfileBatchAddPage',
		profileInfo           => 'ProfileInfoPage',
		profileUpdate         => 'CurateProfileUpdatePage',
		publish               => 'CuratePublishIsolate',
		pubquery              => 'PubQueryPage',
		query                 => $query_page,
		refreshCache          => 'RefreshSchemeCachePage',
		renumber              => 'CurateRenumber',
		seqbin                => 'SeqbinPage',
		setAlleleFlags        => 'CurateBatchSetAlleleFlagsPage',
		setPassword           => 'ChangePasswordPage',
		submit                => 'SubmitPage',
		tableHeader           => 'CurateTableHeaderPage',
		tableQuery            => 'TableQueryPage',
		tagScan               => 'CurateTagScanPage',
		tagUpdate             => 'CurateTagUpdatePage',
		update                => 'CurateUpdatePage',
		user                  => 'UserPage'
	);
	my %page_attributes = (
		system            => $self->{'system'},
		dbase_config_dir  => $self->{'dbase_config_dir'},
		config_dir        => $self->{'config_dir'},
		lib_dir           => $self->{'lib_dir'},
		cgi               => $self->{'cgi'},
		instance          => $self->{'instance'},
		prefs             => $self->{'prefs'},
		prefstore         => $self->{'prefstore'},
		config            => $self->{'config'},
		datastore         => $self->{'datastore'},
		db                => $self->{'db'},
		xmlHandler        => $self->{'xmlHandler'},
		submissionHandler => $self->{'submissionHandler'},
		contigManager     => $self->{'contigManager'},
		dataConnector     => $self->{'dataConnector'},
		mod_perl_request  => $self->{'mod_perl_request'},
		curate            => 1
	);
	my $page;
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
	} elsif ( $self->{'page'} eq 'user' && !$self->{'config'}->{'site_user_dbs'} ) {
		$page = BIGSdb::UserPage->new(%page_attributes);
		$page->print_page_content;
		return;
	} else {
		( $continue, $auth_cookies_ref ) = $self->authenticate( \%page_attributes );
	}
	return if !$continue;
	if ( $self->{'page'} ne 'user' ) {
		my $user_status =
		  $self->{'datastore'}->run_query( 'SELECT status FROM users WHERE user_name=?', $page_attributes{'username'} );
		if ( !defined $user_status || ( $user_status eq 'user' ) ) {
			$page_attributes{'error'} = 'invalidCurator';
			$page = BIGSdb::ErrorPage->new(%page_attributes);
			$page->print_page_content;
			if ( $page_attributes{'error'} ) {
				$self->{'handled_error'} = 1;
			}
			return;
		}
	}
	if ( !$self->{'db'} ) {
		$page_attributes{'error'} = 'noConnect';
		$page = BIGSdb::ErrorPage->new(%page_attributes);
		$page->print_page_content;
		if ( $page_attributes{'error'} ) {
			$self->{'handled_error'} = 1;
		}
		return;
	}
	if ( !$self->{'prefstore'} && $self->{'page'} ne 'user' ) {
		$page_attributes{'error'} = 'noPrefs';
		$page_attributes{'fatal'} = $self->{'fatal'};
		$page                     = BIGSdb::ErrorPage->new(%page_attributes);
		$page->print_page_content;
		if ( $page_attributes{'error'} ) {
			$self->{'handled_error'} = 1;
		}
		return;
	}
	if ( ( $self->{'system'}->{'disable_updates'} // q() ) eq 'yes'
		|| $self->{'config'}->{'disable_updates'} )
	{
		$page_attributes{'error'}   = 'disableUpdates';
		$page_attributes{'message'} = $self->{'config'}->{'disable_update_message'}
		  || $self->{'system'}->{'disable_update_message'};
		$page_attributes{'fatal'} = $self->{'fatal'};
		$page = BIGSdb::ErrorPage->new(%page_attributes);
		$page->print_page_content;
		return;
	}
	if ( $classes{ $self->{'page'} } ) {
		if ( ref $auth_cookies_ref eq 'ARRAY' ) {
			foreach (@$auth_cookies_ref) {
				push @{ $page_attributes{'cookies'} }, $_;
			}
		}
		$page = "BIGSdb::$classes{$self->{'page'}}"->new(%page_attributes);
		$page->print_page_content;
		return;
	}
	$page_attributes{'error'} = 'unknown';
	$page = BIGSdb::ErrorPage->new(%page_attributes);
	$page->print_page_content;
	if ( $page_attributes{'error'} ) {
		$self->{'handled_error'} = 1;
	}
	return;
}

#No need to initiate plugins in curator interface.
sub app_specific_initiation { }
1;
