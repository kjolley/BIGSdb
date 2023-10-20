#ReporTree.pm - Wrapper for ReporTree pipeline
#Written by Keith Jolley
#Copyright (c) 2023, University of Oxford
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
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
#
package BIGSdb::Plugins::ReporTree;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugins::GrapeTree);
use List::MoreUtils qw(uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_RECORDS => 10_000;

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name    => 'ReporTree',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			}
		],
		description => 'Surveillance-oriented tool to strengthen the linkage between pathogen genetic '
		  . 'clusers and epidemiological data',
		full_description => 'A pivotal outcome of genomics surveillance is the identification of pathogen genetic '
		  . 'clusters/lineages and their characterization in terms of geotemporal spread or linkage to clinical and '
		  . 'demographic data. This task usually relies on the visual exploration of (large) phylogenetic trees (e.g. '
		  . 'Minimum Spanning Trees (MST) for bacteria or rooted SNP-based trees for viruses). As this may be a '
		  . 'non-trivial, non-reproducible and time consuming task, we developed ReporTree, a flexible pipeline '
		  . 'that facilitates the detection of genetic clusters and their linkage to epidemiological data. It is '
		  . 'described in <a href="https://pubmed.ncbi.nlm.nih.gov/37322495/">Mix&#227;o <i>et al.</i> 2023 <i>Genome '
		  . 'Med</i> 15:43</a>.',
		category            => 'Third party',
		buttontext          => 'ReporTree',
		menutext            => 'ReporTree',
		module              => 'ReporTree',
		version             => '1.0.0',
		dbtype              => 'isolates',
		section             => 'third_party,postquery',
		input               => 'query',
		help                => 'tooltips',
		requires            => 'offline_jobs,js_tree,ReporTree',
		url                 => "$self->{'config'}->{'doclink'}/data_analysis/reportree.html",
		order               => 70,
		min                 => 2,
		max                 => $self->_get_limit,
		always_show_in_menu => 1,
		image               => '/images/plugins/ReporTree/screenshot.png'
	);
	return \%att;
}

sub _get_limit {
	my ($self) = @_;
	my $limit = $self->{'system'}->{'reportree_limit'} // $self->{'config'}->{'reportree_limit'} // MAX_RECORDS;
	return $limit;
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>ReporTree</h1>);
	if ( $q->param('submit') ) {
		my $loci_selected = $self->get_selected_loci;
		my ( $pasted_cleaned_loci, $invalid_loci ) = $self->get_loci_from_pasted_list;
		$q->delete('locus');
		push @$loci_selected, @$pasted_cleaned_loci;
		@$loci_selected = uniq @$loci_selected;
		$self->add_scheme_loci($loci_selected);
		$self->add_recommended_scheme_loci($loci_selected);
		my @ids = $q->multi_param('isolate_id');
		my ( $pasted_cleaned_ids, $invalid_ids ) = $self->get_ids_from_pasted_list( { dont_clear => 1 } );
		push @ids, @$pasted_cleaned_ids;
		@ids = uniq @ids;
		my $continue = 1;
		my ( @errors, @info );

		if ( !@ids || @ids < 2 ) {
			push @errors, q(You must select at least two valid isolate id.);
		}
		if (@$invalid_ids) {
			local $" = q(, );
			push @info,
			  qq(The id list contained some invalid values - these will be ignored. Invalid values: @$invalid_ids.);
		}
		if ( !@$loci_selected ) {
			push @errors, q(You must select one or more loci or schemes.);
		}
		my $max_records         = $self->_get_limit;
		my $commify_max_records = BIGSdb::Utils::commify($max_records);
		if ( @ids > $max_records ) {
			my $commify_total_records = BIGSdb::Utils::commify( scalar @ids );
			push @errors, qq(Output is limited to a total of $commify_max_records records. )
			  . qq(You have selected $commify_total_records.);
		}
		if ( @errors || @info ) {
			say q(<div class="box" id="statusbad">);
			foreach my $msg ( @errors, @info ) {
				say qq(<p>$msg</p>);
			}
			say q(</div>);
			if (@errors) {
				$self->_print_interface;
				return;
			}
		}
		$self->set_scheme_param;
		my $params = $q->Vars;
		$params->{'set_id'} = $self->get_set_id;
		$params->{'curate'} = 1 if $self->{'curate'};
		$q->delete('list');
		$q->delete('isolate_paste_list');
		$q->delete('locus_paste_list');
		$q->delete('isolate_id');

		foreach my $field_dataset (qw(itol_dataset include_fields)) {
			my @dataset = $q->multi_param($field_dataset);
			$q->delete($field_dataset);
			local $" = '|_|';
			$params->{$field_dataset} = "@dataset";
		}
		$params->{'includes'} = $self->{'system'}->{'labelfield'} if $q->param('include_name');
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		my $job_id    = $self->{'jobManager'}->add_job(
			{
				dbase_config => $self->{'instance'},
				ip_address   => $q->remote_host,
				module       => 'ReporTree',
				parameters   => $params,
				username     => $self->{'username'},
				email        => $user_info->{'email'},
				loci         => $loci_selected,
				isolates     => \@ids
			}
		);
		say $self->get_job_redirect($job_id);
		return;
	}
	$self->_print_interface;
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	my $profile_file  = "$self->{'config'}->{'tmp_dir'}/${job_id}_profiles.txt";
	my $metadata_file = "$self->{'config'}->{'tmp_dir'}/${job_id}_metadata.txt";
	my $ids           = $self->{'jobManager'}->get_job_isolates($job_id);
	my $loci          = $self->{'jobManager'}->get_job_loci($job_id);
	( $ids, my $missing ) = $self->filter_missing_isolates($ids);
	if ( @$ids - @$missing < 2 ) {
		$self->{'jobManager'}->update_job_status(
			$job_id,
			{
				message_html => q(<p class="statusbad">There are fewer than 2 valid ids in the list - )
				  . q(report cannot be generated.</p>)
			}
		);
		return;
	}
	$self->generate_profile_file(
		{
			job_id   => $job_id,
			file     => $profile_file,
			isolates => $ids,
			loci     => $loci,
			params   => $params,
		}
	);
	$self->generate_metadata_file(
		{
			job_id   => $job_id,
			tsv_file => $metadata_file,
			params   => $params
		}
	);
	my %allowed_analysis = map { $_ => 1 } qw(grapetree HC);
	if ( !$allowed_analysis{ $params->{'analysis'} } ) {
		$logger->error("Invalid analysis: $params->{'analysis'}");
		$params->{'analysis'} = 'grapetree';
	}
	$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Running ReporTree', percent_complete => 70 } );
	my $partitions2report = q();
	my $threshold         = q();
	if ( $params->{'stability_regions'} ) {
		$partitions2report = q( --partitions2report stability_regions);
	} elsif ( $params->{'partitions'} && $params->{'partitions'} =~ /^\s*\d+(\s*,\s*\d+\s*)*$/x ) {
		( my $partitions = $params->{'partitions'} ) =~ s/\s//gx;
		$partitions2report = qq( --partitions2report $partitions);
		if ( $params->{'analysis'} eq 'grapetree' ) {
			$threshold = qq( --threshold $partitions);
		} elsif ( $params->{'analysis'} eq 'HC' ) {
			my @partitions = split /,/x, $partitions;
			local $" = q(,single-);
			$threshold = qq( --HC-threshold single-@partitions);
		}
	}
	my $cmd =
		"$self->{'config'}->{'reportree_path'} --allele-profile $profile_file --metadata $metadata_file "
	  . "--missing-code '-' --analysis $params->{'analysis'} --out $self->{'config'}->{'tmp_dir'}/$job_id$partitions2report"
	  . "$threshold > /dev/null 2>&1";
	eval { system($cmd); };
	if ($?) {
		BIGSdb::Exception::Plugin->throw('ReporTree analysis failed.');
	}
	$self->_update_output_files($job_id);
	return;
}

sub _update_output_files {
	my ( $self, $job_id ) = @_;
	opendir( my $dh, $self->{'config'}->{'tmp_dir'} );
	my @files = grep { /$job_id/x } readdir($dh);
	close $dh;
	my $i      = 50;
	my %format = (
		tsv => 'TSV',
		log => 'text',
		nwk => 'Newick',
		txt => 'text'
	);
	my %format_desc = (
		nwk => 'tree',
		log => 'log'
	);
	my $tree_file;

	foreach my $filename ( sort @files ) {
		next if $filename =~ /profiles.txt$/x || $filename =~ /metadata.txt/x;
		$tree_file = $filename if $filename =~ /\.nwk$/x;
		my ( $desc, $format );
		if ( $filename =~ /${job_id}_?([\w\d_]*)\.(\w+)$/x ) {
			( $desc, my $file_suffix ) = ( $1, $2 );
			$desc   = $1;
			$format = $format{$file_suffix} // $file_suffix;
			$desc ||= $format_desc{$file_suffix};
		}
		$self->{'jobManager'}->update_job_output(
			$job_id,
			{
				filename    => $filename,
				description => "${i}_$desc" . ( defined $format ? " ($format format)" : q() ),
			}
		);
		$i++;
	}
	if (   $self->{'config'}->{'MSTree_holder_rel_path'}
		&& defined $tree_file
		&& -e "$self->{'config'}->{'tmp_dir'}/${job_id}_metadata_w_partitions.tsv" )
	{
		$self->{'jobManager'}->update_job_status(
			$job_id,
			{
					message_html => q(<p style="margin-top:2em;margin-bottom:2em">)
				  . qq(<a href="$self->{'config'}->{'MSTree_holder_rel_path'}?tree=/tmp/$tree_file&amp;)
				  . qq(metadata=/tmp/${job_id}_metadata_w_partitions.tsv" target="_blank" )
				  . q(class="launchbutton">Launch GrapeTree</a></p>)
			}
		);
	}
	return;
}

sub _print_interface {
	my ( $self, $isolate_ids ) = @_;
	my $q = $self->{'cgi'};
	$self->print_info_panel;
	$self->print_scheme_selection_banner;
	say q(<div class="box" id="queryform">);
	say q(<p>This tool will generate reports from allelic profiles. Please check the loci that you would like to use. )
	  . q(Alternatively select one or more schemes to include all loci that are members of the scheme.</p>);
	my $limit         = $self->_get_limit;
	my $commify_limit = BIGSdb::Utils::commify($limit);
	say qq(<p>Analysis is limited to $commify_limit records.</p>);
	say $q->start_form;
	my $query_file = $q->param('query_file');
	my $list       = $self->get_id_list( 'id', $query_file );
	say q(<div class="flex_container" style="justify-content:left">);
	$self->print_seqbin_isolate_fieldset( { use_all          => 1, selected_ids => $list, isolate_paste_list => 1 } );
	$self->print_isolates_locus_fieldset( { locus_paste_list => 1 } );
	$self->print_recommended_scheme_fieldset;
	$self->print_scheme_fieldset( { fields_or_loci => 0 } );
	$self->print_includes_fieldset(
		{
			description              => 'Select fields to include in ReporTree metadata.',
			isolate_fields           => 1,
			nosplit_geography_points => 1,
			extended_attributes      => 1,
			scheme_fields            => 1,
			eav_fields               => 1,
			classification_groups    => 1,
			lincodes                 => 1,
			lincode_fields           => 1,
			size                     => 8
		}
	);
	$self->_print_parameters_fieldset;
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach qw (db page name);
	say q(</div>);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _print_parameters_fieldset {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $labels = { grapetree => 'GrapeTree' };
	say q(<fieldset style="float:left;height:12em"><legend>Options</legend>);
	say q(Analysis:);
	say q(<ul><li>);
	say $q->radio_group(
		-name      => 'analysis',
		-values    => [qw (grapetree HC)],
		-labels    => $labels,
		-default   => 'grapetree',
		-linebreak => 'true',
	);
	say q(</li><li>);
	say q(Report:</li><li>);
	say $q->checkbox( -id => 'stability_regions', -name => 'stability_regions', -label => 'Stability regions' );
	say q(</li><li>);
	say q(<span id="partitions_label">Partitions:</span> );
	say $q->textfield( -id => 'partitions', -name => 'partitions', -placeholder => 'list e.g. 4,7,15' );
	say $self->get_tooltip( q(Partitions - Comma-separated list of locus difference thresholds to report. )
		  . q(If this is left blank then all possible thresholds will be included.) );
	say q(</li></ul>);
	say q(</fieldset>);
	return;
}

sub get_plugin_javascript {
	my ($self) = @_;
	my $buffer = << "END";
function enable_partitions(){
	\$("#partitions").prop("disabled", \$("#stability_regions").prop("checked") ? true : false);
	\$("#partitions_label").css("color", \$("#stability_regions").prop("checked") ? '#888' : '#000');
}
	
\$(function () {
	enable_partitions();
	\$("#stability_regions").bind("input propertychange", function () {
		enable_partitions();
	});
});
END
	return $buffer;
}

sub print_info_panel {
	my ($self) = @_;
	my $logo = '/images/plugins/ReporTree/logo.png';
	say q(<div class="box" id="resultspanel">);
	say q(<div style="float:left">);
	say qq(<img src="$logo" style="width:200px" />);
	say q(</div>);
	say q(<p>This plugin creates the required input files for ReporTree and runs the tool to identify )
	  . q(and characterize genetic clusters.</p>);
	say q(<p>ReporTree is developed by: Ver&#243;nica Mix&#227;o (1), Miguel Pinto (1), Daniel Sobral (1), )
	  . q(Adriano Di Pasquale (2), Jo&#227;o Paulo Gomes (1), and V&#237;tor Borges (1)</p>);
	say q(<ol style="overflow:hidden">);
	say q(<li>Genomics and Bioinformatics Unit, Department of Infectious Diseases, National Institute of Health )
	  . q(Doutor Ricardo Jorge (INSA), Lisbon, Portugal.</li>);
	say q(<li>National Reference Centre (NRC) for Whole Genome Sequencing of Microbial Pathogens: Database and )
	  . q(Bioinformatics analysis (GENPAT), Istituto Zooprofilattico Sperimentale Dell'Abruzzo E del Molise )
	  . q("Giuseppe Caporale" (IZSAM), Teramo, Italy.</li>);
	say q(</ol>);
	say q(<p>Publication: Mix&#227;o <i>at al.</i> (2023) ReporTree: a surveillance-oriented tool to strengthen the )
	  . q(linkage between pathogen genetic clusters and epidemiological data )
	  . q(<a href="https://www.ncbi.nlm.nih.gov/pubmed/37322495"><i>Genome Med</i> <b>15:</b>43</a>.</p>);
	say q(</div>);
	return;
}
1;
