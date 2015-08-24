#Written by Keith Jolley
#Copyright (c) 2010-2015, University of Oxford
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
use BIGSdb::ConfigCheckPage;
use BIGSdb::ConfigRepairPage;
use BIGSdb::CurateAddPage;
use BIGSdb::CurateAlleleUpdatePage;
use BIGSdb::CurateBatchAddFASTAPage;
use BIGSdb::CurateBatchAddPage;
use BIGSdb::CurateBatchAddSeqbinPage;
use BIGSdb::CurateBatchIsolateUpdatePage;
use BIGSdb::CurateBatchProfileUpdatePage;
use BIGSdb::CurateBatchSetAlleleFlagsPage;
use BIGSdb::CurateCompositeQueryPage;
use BIGSdb::CurateCompositeUpdatePage;
use BIGSdb::CurateDatabankScanPage;
use BIGSdb::CurateDeleteAllPage;
use BIGSdb::CurateDeletePage;
use BIGSdb::CurateExportConfig;
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
use BIGSdb::CurateRenumber;
use BIGSdb::CurateSubmissionExcelPage;
use BIGSdb::CurateTableHeaderPage;
use BIGSdb::CurateTagScanPage;
use BIGSdb::CurateTagUpdatePage;
use BIGSdb::CurateUpdatePage;
use BIGSdb::RefreshSchemeCachePage;
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub print_page {
	my ($self) = @_;
	my %classes = (
		add                => 'CurateAddPage',
		alleleInfo         => 'AlleleInfoPage',
		alleleQuery        => 'AlleleQueryPage',
		alleleSequence     => 'AlleleSequencePage',
		alleleUpdate       => 'CurateAlleleUpdatePage',
		authorizeClient    => 'AuthorizeClientPage',
		batchAdd           => 'CurateBatchAddPage',
		batchAddFasta      => 'CurateBatchAddFASTAPage',
		batchIsolateUpdate => 'CurateBatchIsolateUpdatePage',
		batchProfileUpdate => 'CurateBatchProfileUpdatePage',
		batchAddSeqbin     => 'CurateBatchAddSeqbinPage',
		browse             => 'BrowsePage',
		changePassword     => 'ChangePasswordPage',
		compositeQuery     => 'CurateCompositeQueryPage',
		compositeUpdate    => 'CurateCompositeUpdatePage',
		configCheck        => 'ConfigCheckPage',
		configRepair       => 'ConfigRepairPage',
		curatorPermissions => 'CuratePermissionsPage',
		databankScan       => 'CurateDatabankScanPage',
		delete             => 'CurateDeletePage',
		deleteAll          => 'CurateDeleteAllPage',
		downloadSeqbin     => 'DownloadSeqbinPage',
		embl               => 'SeqbinToEMBL',
		excelTemplate      => 'CurateSubmissionExcelPage',
		exportConfig       => 'CurateExportConfig',
		extractedSequence  => 'ExtractedSequencePage',
		fieldValues        => 'FieldHelpPage',
		index              => 'CurateIndexPage',
		info               => 'IsolateInfoPage',
		isolateAdd         => 'CurateIsolateAddPage',
		isolateDelete      => 'CurateIsolateDeletePage',
		isolateUpdate      => 'CurateIsolateUpdatePage',
		linkToExperiment   => 'CurateLinkToExperimentPage',
		listQuery          => 'ListQueryPage',
		memberUpdate       => 'CurateMembersPage',
		newVersion         => 'CurateNewVersionPage',
		options            => 'OptionsPage',
		profileAdd         => 'CurateProfileAddPage',
		profileBatchAdd    => 'CurateProfileBatchAddPage',
		profileInfo        => 'ProfileInfoPage',
		profileUpdate      => 'CurateProfileUpdatePage',
		pubquery           => 'PubQueryPage',
		query => ( ( $self->{'system'}->{'dbtype'} // '' ) eq 'isolates' ? 'IsolateQueryPage' : 'ProfileQueryPage' ),
		refreshCache   => 'RefreshSchemeCachePage',
		renumber       => 'CurateRenumber',
		seqbin         => 'SeqbinPage',
		setAlleleFlags => 'CurateBatchSetAlleleFlagsPage',
		setPassword    => 'ChangePasswordPage',
		submit         => 'SubmitPage',
		tableHeader    => 'CurateTableHeaderPage',
		tableQuery     => 'TableQueryPage',
		tagScan        => 'CurateTagScanPage',
		tagUpdate      => 'CurateTagUpdatePage',
		update         => 'CurateUpdatePage'
	);
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
		mod_perl_request => $self->{'mod_perl_request'},
		curate           => 1
	);
	my $page;
	my $continue = 1;
	my $auth_cookies_ref;
	if ( $self->{'error'} ) {
		$page_attributes{'error'} = $self->{'error'};
		$page = BIGSdb::ErrorPage->new(%page_attributes);
		$page->print_page_content;
		return;
	} else {
		( $continue, $auth_cookies_ref ) = $self->authenticate( \%page_attributes );
	}
	return if !$continue;
	my $user_status =
	  $self->{'datastore'}->run_query( 'SELECT status FROM users WHERE user_name=?', $page_attributes{'username'} );
	if ( !defined $user_status || ( $user_status eq 'user' ) ) {
		$page_attributes{'error'} = 'invalidCurator';
		$page = BIGSdb::ErrorPage->new(%page_attributes);
		$page->print_page_content;
		return;
	}
	if ( !$self->{'db'} ) {
		$page_attributes{'error'} = 'noConnect';
		$page = BIGSdb::ErrorPage->new(%page_attributes);
	} elsif ( !$self->{'prefstore'} ) {
		$page_attributes{'error'} = 'noPrefs';
		$page_attributes{'fatal'} = $self->{'fatal'};
		$page                     = BIGSdb::ErrorPage->new(%page_attributes);
	} elsif ( ( $self->{'system'}->{'disable_updates'} && $self->{'system'}->{'disable_updates'} eq 'yes' )
		|| ( $self->{'config'}->{'disable_updates'} && $self->{'config'}->{'disable_updates'} eq 'yes' ) )
	{
		$page_attributes{'error'}   = 'disableUpdates';
		$page_attributes{'message'} = $self->{'config'}->{'disable_update_message'}
		  || $self->{'system'}->{'disable_update_message'};
		$page_attributes{'fatal'} = $self->{'fatal'};
		$page = BIGSdb::ErrorPage->new(%page_attributes);
	} elsif ( $classes{ $self->{'page'} } ) {
		if ( ref $auth_cookies_ref eq 'ARRAY' ) {
			foreach (@$auth_cookies_ref) {
				push @{ $page_attributes{'cookies'} }, $_;
			}
		}
		$page = "BIGSdb::$classes{$self->{'page'}}"->new(%page_attributes);
	} else {
		$page_attributes{'error'} = 'unknown';
		$page = BIGSdb::ErrorPage->new(%page_attributes);
	}
	$page->print_page_content;
	return;
}
1;
