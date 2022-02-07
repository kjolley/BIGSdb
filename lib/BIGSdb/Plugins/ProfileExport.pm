#ProfileExport.pm - Plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2018-2022, University of Oxford
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
package BIGSdb::Plugins::ProfileExport;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use List::MoreUtils qw(uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name    => 'Profile Export',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@zoo.ox.ac.uk',
			}
		],
		description => 'Export file of allelic profile definitions following a scheme query',
		category    => 'Export',
		menutext    => 'Profiles',
		buttontext  => 'Profiles',
		module      => 'ProfileExport',
		version     => '1.3.0',
		dbtype      => 'sequences',
		seqdb_type  => 'schemes',
		input       => 'query',
		section     => 'profile_info,export,postquery',
		url         => "$self->{'config'}->{'doclink'}/data_export/profile_export.html",
		requires    => 'offline_jobs',
		order       => 15,
		image       => '/images/plugins/ProfileExport/screenshot.png'
	);
	return \%att;
}

sub run {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	say q(<h1>Export allelic profiles</h1>);
	return if $self->has_set_changed;
	return if defined $scheme_id && $self->is_scheme_invalid( $scheme_id, { with_pk => 1 } );
	if ( !$q->param('submit') ) {
		$self->print_scheme_section( { with_pk => 1 } );
		$scheme_id = $q->param('scheme_id');    #Will be set by scheme section method
	}
	if ( !defined $scheme_id ) {
		$self->print_bad_status( { message => q(Invalid scheme selected.), navbar => 1 } );
		return;
	}
	if ( $q->param('submit') ) {
		if ( $self->attempted_spam( \( scalar $q->param('list') ) ) ) {
			$self->print_bad_status( { message => q(Invalid data detected in list.), navbar => 1 } );
		} else {
			my $params = $q->Vars;
			$params->{'set_id'} = $self->get_set_id;
			my @list = split /[\r\n]+/x, $q->param('list');
			@list = uniq @list;
			if ( !@list ) {
				my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
				my $pk          = $scheme_info->{'primary_key'};
				my $pk_info     = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $pk );
				my $qry         = 'SELECT profile_id FROM profiles WHERE scheme_id=? ORDER BY ';
				$qry .= $pk_info->{'type'} eq 'integer' ? 'CAST(profile_id AS INT)' : 'profile_id';
				my $id_list = $self->{'datastore'}->run_query( $qry, $scheme_id, { fetch => 'col_arrayref' } );
				@list = @$id_list;
			}
			delete $params->{'list'};
			my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
			my $job_id    = $self->{'jobManager'}->add_job(
				{
					dbase_config => $self->{'instance'},
					ip_address   => $q->remote_host,
					module       => 'ProfileExport',
					parameters   => $params,
					username     => $self->{'username'},
					email        => $user_info->{'email'},
					profiles     => \@list
				}
			);
			say $self->get_job_redirect($job_id);
			return;
		}
	}
	$self->_print_interface($scheme_id);
	return;
}

sub _print_interface {
	my ( $self, $scheme_id ) = @_;
	my $q           = $self->{'cgi'};
	my $query_file  = $q->param('query_file');
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $pk          = $scheme_info->{'primary_key'};
	say q(<div class="box" id="queryform">);
	say q(<p>This script will export allelic profiles in tab-delimited text and Excel formats.</p>);
	my $list = $self->get_id_list( $pk, $query_file );
	say $q->start_form;
	say q(<div class="flex_container" style="justify-content:left">);
	$self->print_id_fieldset( { fieldname => $pk, list => $list } );
	my ( $locus_list, $locus_labels ) =
	  $self->get_field_selection_list( { loci => 1, analysis_pref => 1, query_pref => 0, sort_labels => 1 } );
	say q(<fieldset><legend>Provenance</legend>);
	say q(<ul><li>);
	say $q->checkbox( -name => 'include_sender', label => 'Include sender details' );
	say q(</li><li>);
	say $q->checkbox( -name => 'include_curator', label => 'Include curator details' );
	say q(</li><li>);
	say $q->checkbox( -name => 'include_datestamps', label => 'Include datestamps' );
	say q(<li></ul>);
	say q(</field>);
	$self->print_action_fieldset( { no_reset => 1 } );
	say q(<div style="clear:both"></div>);
	my $set_id = $self->get_set_id;
	$q->param( set_id => $set_id );
	say $q->hidden($_) foreach qw (db page name query_file scheme_id set_id list_file datatype);
	say q(</div>);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _get_classification_schemes {
	my ( $self, $scheme_id ) = @_;
	return $self->{'datastore'}
	  ->run_query( 'SELECT id,name FROM classification_schemes WHERE scheme_id=? ORDER BY display_order,id',
		$scheme_id, { fetch => 'all_arrayref', slice => {} } );
}

sub _get_classification_groups {
	my ( $self, $scheme_id ) = @_;
	my $data =
	  $self->{'datastore'}
	  ->run_query( 'SELECT cg_scheme_id,group_id,profile_id FROM classification_group_profiles WHERE scheme_id=?',
		$scheme_id, { fetch => 'all_arrayref', slice => {} } );
	my $groups = {};
	foreach my $values (@$data) {
		$groups->{ $values->{'cg_scheme_id'} }->{ $values->{'profile_id'} } = $values->{'group_id'};
	}
	return $groups;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	$self->set_offline_view($params);
	$self->{'exit'} = 0;
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1 } ) x 3; #Allow temp files to be cleaned on kill signals
	my $scheme_id        = $params->{'scheme_id'};
	my $scheme_info      = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $pk               = $scheme_info->{'primary_key'};
	my $filename         = "$self->{'config'}->{'tmp_dir'}/${job_id}.txt";
	my $ids              = $self->{'jobManager'}->get_job_profiles( $job_id, $scheme_id );
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $progress         = 0;
	my $progress_max     = 50;
	my @problem_ids;
	my @header = ($pk);
	my $loci   = $self->{'datastore'}->get_scheme_loci($scheme_id);

	foreach my $locus (@$loci) {
		my $locus_name = $self->clean_locus( $locus, { text_output => 1, no_common_name => 1 } );
		push @header, $locus_name;
	}
	my $fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach my $field (@$fields) {
		push @header, $field if $field ne $pk;
	}
	my $cg_schemes = $self->_get_classification_schemes($scheme_id);
	my $c_groups   = $self->_get_classification_groups($scheme_id);
	foreach my $cg_scheme (@$cg_schemes) {
		push @header, $cg_scheme->{'name'};
	}
	my $lincodes_defined = $self->{'datastore'}->are_lincodes_defined($scheme_id);
	if ($lincodes_defined) {
		push @header, 'LINcode';
	}
	if ( $params->{'include_sender'} ) {
		push @header, qw(sender sender_affiliation);
	}
	if ( $params->{'include_curator'} ) {
		push @header, qw(curator curator_affiliation);
	}
	if ( $params->{'include_datestamps'} ) {
		push @header, qw(date_entered datestamp);
	}
	local $" = qq(\t);
	my $buffer        = qq(@header\n);
	my $indices       = $self->{'datastore'}->get_scheme_locus_indices($scheme_id);
	my $pk_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $pk );
	$self->_sort_ids( $pk_field_info->{'type'}, $ids );
	foreach my $profile_id (@$ids) {
		my $data = $self->{'datastore'}->run_query( "SELECT * FROM $scheme_warehouse WHERE $pk=?",
			$profile_id, { fetch => 'row_hashref', cache => 'ProfileExport::get_profile' } );
		if ( !$data ) {
			push @problem_ids, $profile_id;
			next;
		}
		my $pk_value = $data->{ lc($pk) };
		$buffer .= $pk_value;
		foreach my $locus (@$loci) {
			$buffer .= qq(\t$data->{'profile'}->[$indices->{$locus}]);
		}
		foreach my $field (@$fields) {
			next if $field eq $pk;
			my $value = $data->{ lc($field) } // q();
			$buffer .= qq(\t$value);
		}
		foreach my $cg_schemes (@$cg_schemes) {
			my $group_id = $c_groups->{ $cg_schemes->{'id'} }->{$pk_value} // q();
			$buffer .= qq(\t$group_id);
		}
		if ($lincodes_defined) {
			my $lincode =
			  $self->{'datastore'}->run_query( 'SELECT lincode FROM lincodes WHERE (scheme_id,profile_id)=(?,?)',
				[ $scheme_id, $profile_id ] ) // [];
			local $" = q(_);
			$buffer .= qq(\t@$lincode);
		}
		if ( $params->{'include_sender'} ) {
			my $sender = $self->{'datastore'}->get_user_info( $data->{'sender'} );
			my $name   = $sender->{'first_name'};
			$name .= q( ) if $name;
			$name .= $sender->{'surname'} // q();
			$buffer .= qq(\t$name);
			$buffer .= $sender->{'affiliation'} ? qq(\t$sender->{'affiliation'}) : qq(\t);
		}
		if ( $params->{'include_curator'} ) {
			my $curator = $self->{'datastore'}->get_user_info( $data->{'curator'} );
			my $name    = $curator->{'first_name'};
			$name .= q( ) if $name;
			$name .= $curator->{'surname'} // q();
			$buffer .= qq(\t$name);
			$buffer .= $curator->{'affiliation'} ? qq(\t$curator->{'affiliation'}) : qq(\t);
		}
		if ( $params->{'include_datestamps'} ) {
			$buffer .= qq(\t$data->{'date_entered'}\t$data->{'datestamp'});
		}
		$buffer .= qq(\n);
		if ( $self->{'exit'} ) {
			$self->{'jobManager'}->update_job_status( $job_id, { status => 'terminated' } );
			return;
		}
		$progress++;
		if ( !( $progress % 100 ) ) {    #Only update progress every 100 records
			my $complete = int( $progress_max * $progress / @$ids );
			$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => $complete } );
		}
	}
	$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => $progress_max } );
	open( my $fh, '>:encoding(utf8)', $filename )
	  or $logger->error("Cannot open output file $filename for writing");
	say $fh $buffer;
	close $fh;
	if (@problem_ids) {
		local $" = q(, );
		my $html =
		  qq(<p class="statusbad">The following profiles are not valid and have been excluded: @problem_ids.</p>);
		$self->{'jobManager'}->update_job_status( $job_id, { message_html => $html } );
	}
	$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Creating Excel file' } );
	my $excel_file = BIGSdb::Utils::text2excel(
		$filename,
		{
			worksheet => 'Profiles',
			tmp_dir   => $self->{'config'}->{'secure_tmp_dir'},
		}
	);
	$self->{'jobManager'}->update_job_output(
		$job_id,
		{
			filename      => "$job_id.txt",
			description   => '10_Profiles - Tab-delimited text (text)',
			compress      => 1,
			keep_original => 0
		}
	);
	if ( -e $excel_file ) {
		$self->{'jobManager'}->update_job_output( $job_id,
			{ filename => "$job_id.xlsx", description => '20_Profiles - Excel format (Excel)', compress => 1 } );
	}
	return;
}

sub _sort_ids {
	my ( $self, $type, $ids ) = @_;
	if ( $type eq 'integer' ) {
		no warnings 'numeric';    #User may have pasted in text data
		@$ids = sort { $a <=> $b } @$ids;
	} else {
		@$ids = sort { $a cmp $b } @$ids;
	}
	return;
}
1;
