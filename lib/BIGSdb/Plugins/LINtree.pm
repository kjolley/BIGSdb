#LINtree.pm - LINtree wrapper for BIGSdb
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
package BIGSdb::Plugins::LINtree;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugins::ITOL);
use BIGSdb::Exceptions;
use List::MoreUtils qw(uniq);
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );

use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

use constant MAX_RECORDS     => 10_000;
use constant ITOL_UPLOAD_URL => 'https://itol.embl.de/batch_uploader.cgi';
use constant ITOL_DOMAIN     => 'itol.embl.de';
use constant ITOL_TREE_URL   => 'https://itol.embl.de/tree';

sub get_attributes {
	my ($self) = @_;
	my $att = {
		name    => 'LINtree',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			}
		],
		description      => 'Wrapper for LINtree',
		full_description => 'LINtree is a tool to infer prefix trees with branch lengths from sets of '
		  . 'Life Identification Number (LIN) &reg; (trademark registered by This Genomic Life, Inc., '
		  . 'Floyd, VA, USA) codes. Such LIN-based prefix trees are very useful to '
		  . 'reflect the (phylogenetic) relationships among genomes typed using cgMLST with LIN codes assigned.',
		category            => 'Third party',
		buttontext          => 'LINtree',
		menutext            => 'LINtree',
		module              => 'LINtree',
		version             => '1.0.0',
		dbtype              => 'isolates',
		section             => 'third_party,postquery',
		input               => 'query',
		help                => 'tooltips',
		requires            => 'offline_jobs,LINtree,seqbin,lincode_scheme',
		system_flag         => 'LINtree',
		url                 => "$self->{'config'}->{'doclink'}/data_analysis/lintree.html",
		order               => 39,
		min                 => 3,
		max                 => $self->_get_max_records,
		always_show_in_menu => 1,
		image               => '/images/plugins/LINtree/screenshot.png'
	};
	return $att;
}

sub _get_max_records {
	my ($self) = @_;
	return $self->{'system'}->{'lintree_record_limit'} // $self->{'config'}->{'lintree_record_limit'} // MAX_RECORDS;
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
		if ( !@ids || @ids < 2 ) {
			push @errors, q(You must select at least two valid isolate ids.);
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
			$params->{'set_id'} = $self->get_set_id;
			$params->{'curate'} = 1 if $self->{'curate'};
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

sub _print_info_panel {
	my ($self) = @_;
	say q(<div class="box" id="resultspanel">);
	say q(<p>This plugin is a wrapper for LINtree, a tool to infer prefix trees with branch lengths from sets )
	  . q(of Life Identification Number (LIN) &reg; (trademark registered by This Genomic Life, Inc, Floyd, VA, USA) )
	  . q(codes. Such LIN-based prefix trees are very useful to reflect the )
	  . q(phylogenetic relationships among genomes typed by cgMLST where LIN codes have been assigned. Only isolates )
	  . q(with an assigned LIN code can be included in the tree.</p>);
	if ( $self->{'config'}->{'itol_api_key'} ) {
		say q(<p>Once the tree has been generated it is uploaded to the Interactive Tree of Life online service:</p>);
	}
	say q(<p>LINtree has been developed by Alexis Criscuolo (1). The code can be found at )
	  . q(<a href="https://gitlab.pasteur.fr/GIPhy/LINtree" target="_blank">)
	  . q(https://gitlab.pasteur.fr/GIPhy/LINtree</a>.</p>);
	say q(<ol>);
	say q(<li>Genome Informatics & Phylogenetics (GIPhy), Centre de Ressources Biologiques )
	  . q(de l'Institut Pasteur (CRBIP), Institut Pasteur, Paris, France</li>);
	say q(</ol>);
	if ( $self->{'config'}->{'itol_api_key'} ) {
		say q(<p>iTOL is developed by: Ivica Letunic (1) and Peer Bork (2,3,4).</p>);
		say q(<ol style="overflow:hidden">);
		say q(<li>Biobyte solutions GmbH, Bothestr 142, 69126 Heidelberg, Germany</li>);
		say q(<li>European Molecular Biology Laboratory, Meyerhofstrasse 1, 69117 Heidelberg, Germany</li>);
		say q(<li>Max Delbr&uuml;ck Centre for Molecular Medicine, 13125 Berlin, Germany</li>);
		say q(<li>Department of Bioinformatics, Biocenter, University of W&uuml;rzburg, 97074 W&uuml;rzburg, )
		  . q(Germany</li>);
		say q(</ol>);
		say q(<p>Web site: <a href="https://itol.embl.de/">https://itol.embl.de/</a><br />);
		say
		  q(Publication: Letunic &amp; Bork (2021) Interactive tree of life (iTOL) v5: an online tool for phylogenetic )
		  . q(tree display and annotation. <a href="https://www.ncbi.nlm.nih.gov/pubmed/33885785">)
		  . q(<i>Nucleic Acids Res</i> <b>49(W1):</b>W293-6</a>.</p>);
	}
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
	my $selected_fields = ["f_$self->{'system'}->{'labelfield'}"];

	foreach my $scheme_id (@$lincode_schemes) {
		push @$selected_fields, "lin_$scheme_id";
	}
	if ( $self->{'config'}->{'itol_api_key'} ) {
		my $tooltip = $self->print_includes_fieldset(
			{
				title                    => 'iTOL datasets',
				description              => 'Select to create data overlays',
				name                     => 'itol_dataset',
				isolate_fields           => 1,
				nosplit_geography_points => 1,
				extended_attributes      => 1,
				scheme_fields            => 1,
				lincodes                 => 1,
				lincode_fields           => 1,
				classification_groups    => 1,
				eav_fields               => 1,
				size                     => 8,
				preselect                => $selected_fields
			}
		);
		$self->print_itol_datatype_fieldset;
	}

	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach qw (page name db);
	say q(</div>);
	say $q->end_form;
	say q(</div>);
	return;
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

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description( { formatted => 1 } );
	return "LINtree - $desc";
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	my $in_file          = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}.in";
	my $out_file         = "$self->{'config'}->{'tmp_dir'}/${job_id}.tree";
	my $err_file         = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}.err";
	my $isolate_ids      = $self->{'jobManager'}->get_job_isolates($job_id);
	my $locus_thresholds = $self->{'datastore'}
	  ->run_query( 'SELECT thresholds FROM lincode_schemes WHERE scheme_id=?', $params->{'scheme_id'} );
	my @locus_thresholds = split /\s*;\s*/x, $locus_thresholds;
	if ( !@locus_thresholds ) {
		BIGSdb::Exception::Plugin->throw('No thresholds found for LIN code scheme.');
	}
	my $locus_count = $self->{'datastore'}
	  ->run_query( 'SELECT COUNT(*) FROM scheme_members WHERE scheme_id=?', $params->{'scheme_id'} );
	if ( !$locus_count ) {
		BIGSdb::Exception::Plugin->throw('Scheme has no loci defined.');
	}
	my @pc_thresholds;
	foreach my $locus_threshold (@locus_thresholds) {
		push @pc_thresholds,
		  BIGSdb::Utils::decimal_place( 100 * ( $locus_count - $locus_threshold ) / $locus_count, 4 );
	}
	local $" = qq(\t);
	open( my $fh, '>:encoding(utf8)', $in_file ) || BIGSdb::Exception::Plugin->throw('Cannot write input file.');
	say $fh qq(@pc_thresholds);
	my $count         = 0;
	my $progress      = 0;
	my $last_progress = 0;
	$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Calculating LIN codes', percent_complete => 0 } );

	foreach my $isolate_id (@$isolate_ids) {
		my $lincode = $self->{'datastore'}->get_lincode_value( $isolate_id, $params->{'scheme_id'} );
		next if !defined $lincode || !@$lincode;
		local $" = q(_);
		say $fh qq($isolate_id\t@$lincode);
		$count++;
		$progress = int( 50 * ( $count / @$isolate_ids ) );
		if ( $progress > $last_progress ) {
			$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => $progress } );
			$last_progress = $progress;
		}
	}
	my $message;
	if ( $count < 3 ) {
		if ( $count == 0 ) {
			$message = q(No isolates have LIN codes assigned);
		} elsif ( $count == 1 ) {
			$message = q(Only 1 isolate has LIN codes assigned);
		} else {
			$message = qq(Only $count isolates have LIN codes assigned);
		}
		BIGSdb::Exception::Plugin->throw("Tree could not be generated. $message.");
	}
	close $fh;
	$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Running LINtree', percent_complete => 50 } );
	eval { system("$self->{'config'}->{'lintree_path'} $in_file > $out_file 2>$err_file") };
	if ( -s $err_file ) {
		my $error_ref = BIGSdb::Utils::slurp($err_file);
		$logger->error($$error_ref);
		BIGSdb::Exception::Plugin->throw('Error running LINtree.');
	}
	if ( -e $out_file ) {
		$self->{'jobManager'}->update_job_output(
			$job_id,
			{
				filename    => "${job_id}.tree",
				description => '10_Tree (Newick format)',
			}
		);

		my $message_html;
		if ( $self->{'config'}->{'itol_api_key'} ) {
			my $itol_file = $self->itol_upload(
				{
					job_id           => $job_id,
					params           => $params,
					identifiers      => $isolate_ids,
					message_html_ref => \$message_html
				}
			);
			if ( $params->{'itol_dataset'} && -e $itol_file ) {
				$self->{'jobManager'}->update_job_output( $job_id,
					{ filename => "$job_id.zip", description => '20_iTOL datasets (Zip format)' } );
			}
		}
	}
	$self->delete_temp_files("$job_id*");
	return;
}

1;
