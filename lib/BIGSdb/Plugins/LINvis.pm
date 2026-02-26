#LINvis.pm - LIN hierarchical visualisation tool for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2026, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See thef
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
package BIGSdb::Plugins::LINvis;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use BIGSdb::Exceptions;
use List::MoreUtils qw(uniq);
use JSON;

use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

use constant MAX_RECORDS => 60_000;

sub get_attributes {
	my ($self) = @_;
	my $att = {
		name    => 'LINvis',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			}
		],
		description         => 'Dynamic hierarchical LIN code visualisation',
		full_description    => 'LINvis uses D3 circle-packing hierarchical visualisations to summarise LIN code data',
		category            => 'Analysis',
		buttontext          => 'LINvis',
		menutext            => 'LINvis',
		module              => 'LINvis',
		version             => '1.0.0',
		dbtype              => 'isolates',
		section             => 'analysis,postquery',
		input               => 'query',
		help                => 'tooltips',
		requires            => 'offline_jobs,seqbin,lincode_scheme',
		url                 => "$self->{'config'}->{'doclink'}/data_analysis/linvis.html",
		order               => 35,
		min                 => 1,
		max                 => $self->_get_max_records,
		always_show_in_menu => 1,
		image               => '/images/plugins/LINvis/screenshot.png'
	};
	return $att;
}

sub _get_max_records {
	my ($self) = @_;
	return $self->{'system'}->{'linvis_record_limit'} // $self->{'config'}->{'linvis_record_limit'} // MAX_RECORDS;
}

sub _print_info_panel {
	my ($self) = @_;
	my $logo = '/images/plugins/LINvis/logo.png';
	say q(<div class="box" id="resultspanel" style="min-height:180px">);
	say q(<div style="float:left">);
	say qq(<img src="$logo" style="height:150px;margin-right:50px;filter:drop-shadow(5px 5px 4px #888)" />);
	say q(</div>);
	say q(<p>LINvis displays a dataset of LIN&reg; code values as a hierarchical circle-packing visualisation.</p>);
	say q(<p>Hovering over each node will display the partial or full LIN code associated with it and you can choose )
	  . q(to set labels for any LIN code threshold.</p>);
	say q(<p class="comment">LIN is a trademark registered by This Genomic Life, Inc, Floyd, VA, USA.</p>);
	say q(</div>);
	return;
}

sub _print_interface {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $list       = $self->get_id_list( 'id', $query_file );

	say q(<div class="box" id="queryform">);
	say $q->start_form;
	say q(<div class="flex_container" style="justify-content:left">);
	$self->print_seqbin_isolate_fieldset( { only_genomes => 1, selected_ids => $list, isolate_paste_list => 1 } );
	$self->_print_lincode_scheme_fieldset;
	my $lincode_schemes =
	  $self->{'datastore'}->run_query( 'SELECT scheme_id FROM lincode_schemes', undef, { fetch => 'col_arrayref' } );
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach qw (page name db);
	say q(</div>);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _get_lincode_scheme_list {
	my ($self) = @_;
	my $schemes = $self->{'datastore'}->run_query(
		'SELECT scheme_id,name FROM lincode_schemes ls JOIN schemes s ON ls.scheme_id=s.id ORDER BY display_order,name',
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $scheme_ids = [];
	my $labels     = {};
	foreach my $scheme (@$schemes) {
		push @$scheme_ids, $scheme->{'scheme_id'};
		$labels->{ $scheme->{'scheme_id'} } = $scheme->{'name'};
	}
	return {
		scheme_ids => $scheme_ids,
		labels     => $labels
	};
}

sub _print_lincode_scheme_fieldset {
	my ($self)      = @_;
	my $q           = $self->{'cgi'};
	my $scheme_list = $self->_get_lincode_scheme_list;
	say q(<fieldset style="float:left"><legend>LIN code scheme</legend>);
	if ( @{ $scheme_list->{'scheme_ids'} } == 1 ) {
		say qq(<p><strong>$scheme_list->{'labels'}->{$scheme_list->{'scheme_ids'}->[0]}</strong></p>);
		say $q->hidden( scheme_id => $scheme_list->{'scheme_ids'}->[0] );
	} else {
		unshift @{ $scheme_list->{'scheme_ids'} }, q();
		$scheme_list->{'labels'}->{''} = 'Select scheme...';
		say $self->popup_menu(
			-id       => 'scheme_id',
			-name     => 'scheme_id',
			-values   => $scheme_list->{'scheme_ids'},
			-labels   => $scheme_list->{'labels'},
			-required => 1
		);
	}
	say q(</fieldset>);
	return;
}

sub run {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $title  = $self->get_title;
	say qq(<h1>$title</h1>);
	my $lincodes_defined = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM lincode_schemes)');
	if ( !$lincodes_defined ) {
		$self->print_bad_status(
			{
				message => q(LIN codes are not defined for this database.),
			}
		);
		return;
	}
	if ( $q->param('submit') ) {
		my @ids = $q->multi_param('isolate_id');
		my ( $pasted_cleaned_ids, $invalid_ids ) = $self->get_ids_from_pasted_list( { dont_clear => 1 } );
		push @ids, @$pasted_cleaned_ids;
		@ids = uniq @ids;
		my $continue = 1;
		my @errors;

		if (@$invalid_ids) {
			local $" = ', ';
			push @errors, qq(The following isolates in your pasted list are invalid: @$invalid_ids.);
		}
		if ( !@ids ) {
			push @errors, q(You must select at least one valid isolate ids.);
		}
		my $max_records = $self->_get_max_records;
		if ( @ids > $max_records ) {
			my $commify_max_records   = BIGSdb::Utils::commify($max_records);
			my $commify_total_records = BIGSdb::Utils::commify( scalar @ids );
			push @errors, qq(Output is limited to a total of $commify_max_records records. )
			  . qq(You have selected $commify_total_records.);
		}
		my $scheme_id = $q->param('scheme_id');
		if ( !BIGSdb::Utils::is_int($scheme_id) ) {
			push @errors, q(No valid LIN code scheme selected.);
		}
		if (@errors) {
			if ( @errors == 1 ) {
				$self->print_bad_status( { message => qq(@errors) } );
			} else {
				local $" = q(</p><p>);
				$self->print_bad_status( { message => q(Please address the following:), detail => qq(@errors) } );
			}
		} else {
			my $attr = $self->get_attributes;
			$self->set_scheme_param;
			my $params = $q->Vars;
			$params->{'set_id'}      = $self->get_set_id;
			$params->{'curate'}      = 1 if $self->{'curate'};
			$params->{'script_name'} = $self->{'system'}->{'script_name'};
			$q->delete($_) foreach qw(list isolate_paste_list);
			my @dataset = $q->multi_param('itol_dataset');
			$q->delete('itol_dataset');
			local $" = '|_|';
			$params->{'itol_dataset'} = "@dataset";

			my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
			my $job_id    = $self->{'jobManager'}->add_job(
				{
					dbase_config => $self->{'instance'},
					ip_address   => $q->remote_host,
					module       => $attr->{'module'},
					parameters   => $params,
					username     => $self->{'username'},
					email        => $user_info->{'email'},
					isolates     => \@ids
				}
			);
			say $self->get_job_redirect($job_id);
		}
		return;
	}
	$self->_print_info_panel;
	$self->_print_interface;
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	my $out_file    = "$self->{'config'}->{'tmp_dir'}/${job_id}.json";
	my $isolate_ids = $self->{'jobManager'}->get_job_isolates($job_id);

	my $count         = 0;
	my $progress      = 0;
	my $last_progress = 0;
	$self->{'jobManager'}
	  ->update_job_status( $job_id, { stage => 'Preparing hierarchical data file', percent_complete => 0 } );
	my $root = { name => 'root', children => [] };

	foreach my $isolate_id (@$isolate_ids) {

		my $lincode = $self->{'datastore'}->get_lincode_value( $isolate_id, $params->{'scheme_id'} );
		next if !defined $lincode || !@$lincode;
		my $node = $root;
		my $prefix;
		for my $bin ( 0 .. @$lincode - 1 ) {

			$prefix = $bin ? "${prefix}_$lincode->[$bin]" : $lincode->[0];
			$node   = $self->_child_node( $node, $prefix );

		}
		$node->{'value'} = ( $node->{'value'} || 0 ) + 1;

		$count++;
		$progress = int( 100 * ( $count / @$isolate_ids ) );
		if ( $progress > $last_progress ) {
			$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => $progress } );
			$last_progress = $progress;
		}
	}
	if ( !$count ) {
		BIGSdb::Exception::Plugin->throw('None of the isolates in the selected dataset have a LIN code assigned.');
	}
	$self->_aggregate($root);
	$self->_cleanup($root);
	open( my $fh, '>:encoding(utf8)', $out_file ) || BIGSdb::Exception::Plugin->throw('Cannot write input file.');
	say $fh encode_json($root);
	close $fh;
	if ( -e $out_file ) {
		$self->{'jobManager'}->update_job_output(
			$job_id,
			{
				filename    => "${job_id}.json",
				description => 'Frequencies (JSON)',
			}
		);
		$self->{'jobManager'}->update_job_status(
			$job_id,
			{
					message_html => q(<p style="margin-top:2em;margin-bottom:2em">)
				  . qq(<a href="$params->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=pluginViewer&amp;plugin=LINvis&job=$job_id" target="_blank" )
				  . q(class="launchbutton">Launch LINvis</a></p>)
			}
		);
	}
	return;
}

sub _child_node {
	my ( $self, $node, $prefix ) = @_;
	$node->{'_map'} //= {};
	if ( exists $node->{'_map'}{$prefix} ) {
		return $node->{'_map'}{$prefix};
	} else {
		my $child = { name => $prefix, children => [] };
		push @{ $node->{'children'} }, $child;
		$node->{'_map'}{$prefix} = $child;
		return $child;
	}
}

sub _aggregate {
	my ( $self, $node ) = @_;
	my $sum_children = 0;
	if ( exists $node->{'children'} && @{ $node->{'children'} } ) {
		for my $c ( @{ $node->{'children'} } ) {
			$sum_children += $self->_aggregate($c);
		}
	}
	$node->{'value'} = ( $node->{'value'} || 0 ) + $sum_children;
	return $node->{'value'};
}

sub _cleanup {
	my ( $self, $node ) = @_;
	delete $node->{'_map'} if exists $node->{'_map'};
	if ( exists $node->{'children'} ) {
		for my $c ( @{ $node->{'children'} } ) {
			$self->_cleanup($c);
		}
		delete $node->{'children'} unless @{ $node->{'children'} };
	}
	return $node;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description( { formatted => 1 } );
	return "LINvis - $desc";
}

1;
