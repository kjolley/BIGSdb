#ITol.pm - Phylogenetic tree plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2016-2025, University of Oxford
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
package BIGSdb::Plugins::ITOL;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugins::GrapeTree);
use BIGSdb::Utils;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Try::Tiny;
use List::MoreUtils qw(uniq);
use File::Copy;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use LWP::UserAgent;
use constant MAX_RECORDS     => 2000;
use constant MAX_SEQS        => 100_000;
use constant ITOL_UPLOAD_URL => 'https://itol.embl.de/batch_uploader.cgi';
use constant ITOL_DOMAIN     => 'itol.embl.de';
use constant ITOL_TREE_URL   => 'https://itol.embl.de/tree';

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name    => 'iTOL',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			}
		],
		description      => 'Phylogenetic trees with data overlays',
		full_description => 'The ITOL plugin allows you to generate and visualise phylogenetic trees calculated from '
		  . 'concatenated sequence alignments of selected loci (or the loci belonging to a particular scheme). '
		  . 'Currently, only Neighbour-joining trees are supported. Datasets can include metadata which allows nodes '
		  . 'in the resultant tree to be coloured. Datasets are uploaded to the <a href="https://itol.embl.de/">'
		  . 'Interactive Tree of Life website</a> (<a href="https://www.ncbi.nlm.nih.gov/pubmed/27095192">'
		  . 'Letunic &amp; Bork 2016 <i>Nucleic Acids Res</i> 44(W1):W242-5</a>) for visualisation.',
		category   => 'Third party',
		buttontext => 'iTOL',
		menutext   => 'iTOL',
		module     => 'ITOL',
		version    => '1.8.0',
		dbtype     => 'isolates',
		section    => 'third_party,postquery',
		input      => 'query',
		help       => 'tooltips',
		requires   => 'aligner,offline_jobs,js_tree,clustalw,itol_api_key,itol_project_name',
		supports   => 'user_genomes',
		url        => "$self->{'config'}->{'doclink'}/data_analysis/itol.html",
		order      => 35,
		min        => 2,
		max => $self->{'system'}->{'itol_record_limit'} // $self->{'config'}->{'itol_record_limit'} // MAX_RECORDS,
		always_show_in_menu => 1,
		image               => '/images/plugins/ITOL/screenshot.png'
	);
	return \%att;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description( { formatted => 1 } );
	return "iTOL - Interactive Tree of Life - $desc";
}

sub run {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $title  = $self->get_title;
	say qq(<h1>$title</h1>);
	return if $self->has_set_changed;
	my $allow_alignment = 1;
	if ( !-x $self->{'config'}->{'muscle_path'} && !-x $self->{'config'}->{'mafft_path'} ) {
		$logger->error( 'This plugin requires an aligner (MAFFT or MUSCLE) to be installed and one is not. '
			  . 'Please install one of these or check the settings in bigsdb.conf.' );
		$allow_alignment = 0;
	}
	my $attr = $self->get_attributes;
	if ( $q->param('submit') ) {
		if ($q->param('tree_gen')){
			my $guid = $self->get_guid;
			eval {
				$self->{'prefstore'}->set_plugin_attribute( $guid, $self->{'system'}->{'db'},
					$attr->{'module'}, 'tree_gen', scalar $q->param('tree_gen') );
			};
		}
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
		my @errors;

		if (@$invalid_ids) {
			local $" = ', ';
			push @errors, qq(The following isolates in your pasted list are invalid: @$invalid_ids.);
		}
		$q->param( user_genome_filename => scalar $q->param('user_upload') );
		my $user_upload;
		if ( $q->param('user_upload') ) {
			$user_upload = $self->upload_user_file;
		}
		if ( ( !@ids || @ids < 2 ) && !$user_upload ) {
			push @errors, q(You must select at least two valid isolate ids.);
		}
		if (@$invalid_loci) {
			local $" = q(, );
			push @errors, qq(The following loci in your pasted list are invalid: @$invalid_loci.);
		}
		if ( !@$loci_selected ) {
			push @errors, q(You must select one or more loci or schemes.);
		}
		my $total_seqs  = @$loci_selected * @ids;
		my $max_records = $self->{'system'}->{ lc("$attr->{'module'}_record_limit") }
		  // $self->{'config'}->{ lc("$attr->{'module'}_record_limit") } // MAX_RECORDS;
		my $max_seqs = $self->{'system'}->{ lc("$attr->{'module'}_seq_limit") }
		  // $self->{'config'}->{ lc("$attr->{'module'}_seq_limit") } // MAX_SEQS;
		my $commify_max_records = BIGSdb::Utils::commify($max_records);
		my $commify_max_seqs    = BIGSdb::Utils::commify($max_seqs);
		my $commify_total_seqs  = BIGSdb::Utils::commify($total_seqs);
		if ( $total_seqs > $max_seqs && $q->param('tree_gen') eq 'sequences' ) {
			push @errors, qq(Output is limited to a total of $commify_max_seqs sequences )
			  . qq((records x loci). You have selected $commify_total_seqs.);
		}
		if ( @ids > $max_records ) {
			my $commify_total_records = BIGSdb::Utils::commify( scalar @ids );
			push @errors, qq(Output is limited to a total of $commify_max_records records. )
			  . qq(You have selected $commify_total_records.);
		}
		if (@errors) {
			if ( @errors == 1 ) {
				$self->print_bad_status( { message => qq(@errors) } );
			} else {
				local $" = q(</p><p>);
				$self->print_bad_status( { message => q(Please address the following:), detail => qq(@errors) } );
			}
		} else {
			$self->set_scheme_param;
			my $params = $q->Vars;
			$params->{'set_id'} = $self->get_set_id;
			$params->{'curate'} = 1 if $self->{'curate'};
			$q->delete('list');
			$q->delete('isolate_paste_list');
			foreach my $field_dataset (qw(itol_dataset include_fields)) {
				my @dataset = $q->multi_param($field_dataset);
				$q->delete($field_dataset);
				local $" = '|_|';
				$params->{$field_dataset} = "@dataset";
			}
			$params->{'user_upload'} = $user_upload if $user_upload;
			my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
			my $job_id    = $self->{'jobManager'}->add_job(
				{
					dbase_config => $self->{'instance'},
					ip_address   => $q->remote_host,
					module       => $attr->{'module'},
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
	}
	$self->print_info_panel;
	$self->_print_interface(
		{
			max_records => $self->{'system'}->{ lc("$attr->{'module'}_record_limit") }
			  // $self->{'config'}->{ lc("$attr->{'module'}_record_limit") },
			max_seqs => $self->{'system'}->{ lc("$attr->{'module'}_seq_limit") }
			  // $self->{'config'}->{ lc("$attr->{'module'}_seq_limit") }
		}
	);
	return;
}

sub _print_interface {
	my ( $self, $options ) = @_;
	my $q                   = $self->{'cgi'};
	my $max_records         = $options->{'max_records'} // MAX_RECORDS;
	my $max_seqs            = $options->{'max_seqs'}    // MAX_SEQS;
	my $commify_max_records = BIGSdb::Utils::commify($max_records);
	my $commify_max_seqs    = BIGSdb::Utils::commify($max_seqs);
	my $scheme_id           = $q->param('scheme_id');
	my $query_file          = $q->param('query_file');
	my $or_profiles         = $self->{'config'}->{'grapetree_path'} ? q( or allelic profiles) : q();
	say q(<div class="box" id="queryform">);
	say qq(<p>This tool will generate neighbor-joining trees from concatenated nucleotide sequences$or_profiles. )
	  . q(For sequencr trees, only DNA loci that have a corresponding database containing allele sequence identifiers, )
	  . q(or DNA and peptide loci with genome sequences, can be included. Please check the loci that you )
	  . q(would like to include. Alternatively select one or more schemes to include all loci that are members )
	  . q(of the scheme.</p>);
	say qq(<p>Analysis is limited to $commify_max_records records.</p>);
	say qq(<p>If generating a tree by aligning sequences then it is also limited to $commify_max_seqs sequences )
	  . q((records x loci).</p>);
	my $list = $self->get_id_list( 'id', $query_file );
	say $q->start_form;
	say q(<div class="flex_container" style="justify-content:left">);
	$self->print_seqbin_isolate_fieldset( { use_all => 1, selected_ids => $list, isolate_paste_list => 1 } );
	my $atts = $self->get_attributes;

	#Subclassed plugins may not yet support uploaded genomes.
	$self->print_user_genome_upload_fieldset if ( $atts->{'supports'} // q() ) =~ /user_genomes/x;
	$self->print_isolates_locus_fieldset( { locus_paste_list => 1, no_all_none => 1 } );
	$self->print_recommended_scheme_fieldset( { no_clear => 1 } );
	$self->print_scheme_fieldset;
	$self->print_extra_form_elements;
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach qw (page name db);
	say q(</div>);
	say $q->end_form;
	say q(</div>);
	return;
}

sub print_tree_type_fieldset {
	my ($self) = @_;
	return if !$self->{'config'}->{'grapetree_path'};
	my $q = $self->{'cgi'};
	my $guid = $self->get_guid;
	my $default;
	my $attr = $self->get_attributes;
			eval {
				$default = $self->{'prefstore'}->get_plugin_attribute( $guid, $self->{'system'}->{'db'},
					$attr->{'module'}, 'tree_gen' );
			};
	
	say q(<fieldset style="float:left"><legend>Tree generation</legend>);
	say q(<p>Generate trees from:</p>);
	say q(<ul><li>);
	say $q->radio_group(
		-id        => 'tree_gen',
		-name      => 'tree_gen',
		-values    => [ 'profiles', 'sequences' ],
		-default   => $default // 'sequences',
		-linebreak => 'true'
	);
	say q(</li></ul>);
	say q(</fieldset>);
	return;
}

sub print_extra_form_elements {
	my ($self) = @_;
	my $tooltip =
	  $self->get_tooltip( q(Datasets - These are not available for uploaded genomes since they require )
		  . q(metadata or designations to be tagged within the database.</p>)
		  . q(<p>Use Shift/Ctrl to select multiple values (depending on your system).</p>) );
	$self->print_tree_type_fieldset;
	$self->print_includes_fieldset(
		{
			title                    => 'iTOL datasets',
			description              => "Select to create data overlays $tooltip",
			name                     => 'itol_dataset',
			isolate_fields           => 1,
			nosplit_geography_points => 1,
			extended_attributes      => 1,
			scheme_fields            => 1,
			classification_groups    => 1,
			eav_fields               => 1,
			size                     => 8,
			preselect                => ["f_$self->{'system'}->{'labelfield'}"]
		}
	);
	say q(<fieldset style="float:left"><legend>iTOL data type</legend>);
	my $q      = $self->{'cgi'};
	my $labels = { text_label => 'text labels', colour_strips => 'coloured strips' };
	say $q->radio_group(
		-name      => 'data_type',
		-values    => [qw(text_label colour_strips)],
		-labels    => $labels,
		-linebreak => 'true'
	);
	say q(</fieldset>);
	return;
}

sub get_plugin_javascript {
	my ($self) = @_;
	my $buffer = << "END";

\$(function () {
	\$('#locus,#itol_dataset,#recommended_schemes').multiselect({
 		classes: 'filter',
 		menuHeight: 250,
 		menuWidth: 400,
 		selectedList: 8
  	}).multiselectfilter();
  	\$("a#clear_user_upload").on("click", function(){
  		\$("input#user_upload").val("");
  	});
});

END
	return $buffer;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	my $ret_val = $self->generate_tree_files( $job_id, $params );
	my ( $message_html, $fasta_file, $failed ) = @{$ret_val}{qw(message_html fasta_file failed )};
	if ( !$failed ) {
		$self->check_connection($job_id);
		my $identifiers = $self->{'jobManager'}->get_job_isolates($job_id);
		push @$identifiers, keys %{ $self->{'reverse_name_map'} }
		  if ref $self->{'reverse_name_map'} eq 'HASH';
		my $itol_file = $self->_itol_upload( $job_id, $params, $identifiers, \$message_html );
		if ( $params->{'itol_dataset'} && -e $itol_file ) {
			$self->{'jobManager'}->update_job_output( $job_id,
				{ filename => "$job_id.zip", description => '30_iTOL datasets (Zip format)' } );
		}
	}
	$self->{'jobManager'}->update_job_status( $job_id, { message_html => $message_html } ) if $message_html;
	return;
}

sub generate_tree_files {
	my ( $self, $job_id, $params ) = @_;
	$params->{'tree_gen'} //= 'sequences';
	if ( $params->{'tree_gen'} eq 'profiles' ) {
		return $self->_generate_tree_files_from_profiles( $job_id, $params );
	} else {
		return $self->_generate_tree_files_from_sequences( $job_id, $params );
	}
}

sub _generate_tree_files_from_profiles {
	my ( $self, $job_id, $params ) = @_;
	$self->set_offline_view($params);
	$self->{'params'} = $params;
	my $profiles_file = "$self->{'config'}->{'tmp_dir'}/${job_id}_profiles.txt";
	my $ids           = $self->{'jobManager'}->get_job_isolates($job_id);
	my $user_genomes  = $self->process_uploaded_genomes( $job_id, $ids, $params );
	my $loci          = $self->{'jobManager'}->get_job_loci($job_id);
	$self->generate_profile_file(
		{
			job_id              => $job_id,
			file                => $profiles_file,
			isolates            => $ids,
			user_genomes        => $user_genomes,
			loci                => $loci,
			params              => $params,
			rename_user_genomes => 1
		}
	);

	my ( $message_html, $failed );
	my $prefix     = BIGSdb::Utils::get_random();
	my $error_file = "$self->{'config'}->{'secure_tmp_dir'}/${prefix}_grapetree";
	my $tree_file  = "$self->{'config'}->{'tmp_dir'}/${job_id}.nwk";
	my $cmd;

	if ( !defined $self->{'config'}->{'python3_path'} && $self->{'config'}->{'grapetree_path'} =~ /python/x ) {

		#Path includes full command for running GrapeTree (recommended)
		$cmd = "$self->{'config'}->{'grapetree_path'} --profile $profiles_file --method NJ 2>$error_file > $tree_file ";
	} else {

		#Separate variables for GrapeTree directory and Python path (legacy)
		my $python = $self->{'config'}->{'python3_path'} // '/usr/bin/python3';
		$cmd = "$python $self->{'config'}->{'grapetree_path'}/grapetree.py --profile "
		  . "$profiles_file --method NJ 2>$error_file > $tree_file ";
	}
	eval { system($cmd); };
	if ( $? || -e $error_file ) {
		my $error_ref = BIGSdb::Utils::slurp($error_file);
		$logger->error($$error_ref) if $$error_ref;
		$failed = 1                 if $?;
		unlink $error_file;
	}
	if ( -e $tree_file ) {
		$self->{'jobManager'}->update_job_output(
			$job_id,
			{
				filename    => "${job_id}.nwk",
				description => '20_Tree (Newick format)',
			}
		);
	}

	return {
		message_html => $message_html,
		newick_file  => $tree_file,
		failed       => $failed
	};
}

sub _generate_tree_files_from_sequences {
	my ( $self, $job_id, $params ) = @_;
	$self->set_offline_view($params);
	$self->{'params'}                = $params;
	$self->{'params'}->{'align'}     = 1;
	$self->{'params'}->{'align_all'} = 1;
	$params->{'aligner'}             = $self->{'config'}->{'mafft_path'} ? 'MAFFT' : 'MUSCLE';
	$self->{'threads'} =
	  BIGSdb::Utils::is_int( $self->{'config'}->{'genome_comparator_threads'} )
	  ? $self->{'config'}->{'genome_comparator_threads'}
	  : 2;
	$self->{'exit'} = 0;
	local @SIG{qw (INT TERM HUP)} =
	  ( sub { $self->{'exit'} = 1 } ) x 3;    #Allow temp files to be cleaned on kill signals
	my $ids          = $self->{'jobManager'}->get_job_isolates($job_id);
	my $user_genomes = $self->process_uploaded_genomes( $job_id, $ids, $params );
	my $loci         = $self->{'jobManager'}->get_job_loci($job_id);
	my $filename     = "$self->{'config'}->{'tmp_dir'}/$job_id.xmfa";
	( $ids, my $missing ) = $self->filter_missing_isolates($ids);
	my ( $message_html, $failed );
	my $scan_data;
	eval {
		$scan_data = $self->assemble_data_for_defined_loci(
			{ job_id => $job_id, ids => $ids, user_genomes => $user_genomes, loci => $loci } );
	};
	if ($@) {
		$logger->error($@);
		if ( $@ =~ /No\ valid\ isolate\ ids/x ) {
			$message_html = q(<p>No valid isolate ids in list.</p>);
		}
		return { message_html => $message_html, failed => 1 };
	}
	my $isolates_with_no_sequence = $self->_find_isolates_with_no_seq($scan_data);
	my $paralogous                = [];
	if ( @$ids - @$missing < 2 ) {
		$message_html = q(<p>There are fewer than 2 valid ids in the list - tree cannot be generated.</p>);
		return { message_html => $message_html, failed => 1 };
	} else {
		my %missing_seq = map { $_ => 1 } @$isolates_with_no_sequence;
		@$paralogous = sort keys %{ $scan_data->{'paralogous'} };
		if ( @$paralogous == @$loci ) {
			$message_html = q(<p>All loci are paralogous in at least one isolate - tree cannot be generated.</p>);
			return { message_html => $message_html, failed => 1 };
		}
		my $filtered_list = [];
		foreach my $id (@$ids) {
			push @$filtered_list, $id if !$missing_seq{$id};
		}
		if ( @$filtered_list < 2 ) {
			$message_html = q(<p>There are fewer than 2 valid ids containing sequence for the selected loci )
			  . q(in the list - tree cannot be generated.</p>);
			return { message_html => $message_html, failed => 1 };
		}
		$self->align(
			{
				job_id        => $job_id,
				by_ref        => 1,
				ids           => $filtered_list,
				scan_data     => $scan_data,
				no_output     => 1,
				no_paralogous => 1
			}
		);
	}
	if ( $self->{'exit'} ) {
		$self->{'jobManager'}->update_job_status( $job_id, { status => 'terminated' } );
		unlink $filename;
		return { failed => 1 };
	}
	if (@$missing) {
		local $" = ', ';
		$message_html .= qq(<p>The following ids could not be processed (they do not exist): @$missing.</p>\n);
	}
	if (@$paralogous) {
		local $" = ', ';
		if ( @$paralogous < 10 ) {
			$message_html .=
				q(<p>The following loci are paralogous, resulting in multiple hits within at least one )
			  . qq(isolate: @$paralogous. These have been removed from the analysis. See Excel output for )
			  . qq(details.</p>\n);
		} else {
			my $num = @$paralogous;
			$message_html .= qq(<p>$num loci were paralogous, resulting in multiple hits within at least one )
			  . qq(isolate. These have been removed from the analysis. See Excel output for details.</p>\n);
		}
		$self->_generate_paralogous_report( $job_id, $scan_data );
	}
	if (@$isolates_with_no_sequence) {
		local $" = ', ';
		my $missing_count = @$isolates_with_no_sequence;
		if ( $missing_count < 10 ) {
			$message_html .= q(<p>The following ids had no sequences for all the selected loci: )
			  . qq(@$isolates_with_no_sequence.</p><p>They have been removed from the analysis.</p>\n);
		} else {
			$message_html .= qq(<p>$missing_count ids had no sequences for all the selected loci. They have been )
			  . q(removed from the analysis.</p>);
		}
	}
	my ( $fasta_file, $newick_file );
	try {
		$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Generating FASTA file from aligned blocks' } );
		$fasta_file = BIGSdb::Utils::xmfa2fasta($filename);
		if ( -e $fasta_file ) {
			$self->{'jobManager'}
			  ->update_job_output( $job_id, { filename => "$job_id.fas", description => '10_Concatenated FASTA' } );
		}
		$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Constructing NJ tree' } );
		$newick_file = "$self->{'config'}->{'tmp_dir'}/$job_id.ph";
		my $cmd = "$self->{'config'}->{'clustalw_path'} -tree -infile=$fasta_file > /dev/null";
		system $cmd;
		if ( -e $newick_file ) {
			$self->{'jobManager'}
			  ->update_job_output( $job_id, { filename => "$job_id.ph", description => '20_NJ tree (Newick format)' } );
		} else {
			$logger->error('Tree file has not been generated.');
			if ( !-e $self->{'config'}->{'clustalw_path'} ) {
				$logger->error("CLUSTALW program does not exist at $self->{'config'}->{'clustalw_path'}.");
			} elsif ( !-x $self->{'config'}->{'clustalw_path'} ) {
				$logger->error("CLUSTALW program at $self->{'config'}->{'clustalw_path'} is not executable.");
			} else {
				$logger->debug(
					"CLUSTALW program has been found at $self->{'config'}->{'clustalw_path'} and is executable.");
			}
			$failed = 1;
		}
	} catch {
		if ( $_->isa('BIGSdb::Exception::File::CannotOpen') ) {
			$logger->error('Cannot create FASTA file from XMFA.');
			$failed = 1;
		} else {
			$logger->logdie($_);
		}
	};
	unlink $filename if -e "$filename.gz";
	return {
		message_html => $message_html,
		fasta_file   => $fasta_file,
		newick_file  => $newick_file,
		failed       => $failed
	};
}

sub _generate_paralogous_report {
	my ( $self, $job_id, $scan_data ) = @_;
	my @loci = sort keys %{ $scan_data->{'paralogous'} };
	local $" = qq(\t);
	my $text_file = "$self->{'config'}->{'tmp_dir'}/${job_id}_paralogous.txt";
	open( my $fh, '>:encoding(utf8)', $text_file ) || $logger->error("Cannot open $text_file for writing");
	say $fh qq(id\t$self->{'system'}->{'labelfield'}\t@loci);
	foreach my $isolate_id ( sort { $a <=> $b } keys %{ $scan_data->{'isolate_data'} } ) {
		my $paralogous = $scan_data->{'isolate_data'}->{$isolate_id}->{'paralogous'};
		next if !@$paralogous;
		my %paralogous = map { $_ => 1 } @$paralogous;
		my $name       = $self->get_isolate_name_from_id($isolate_id);
		print $fh qq($isolate_id\t$name);
		foreach my $locus (@loci) {
			print $fh qq(\t);
			print $fh $paralogous{$locus} ? q(x) : q();
		}
		print $fh qq(\n);
	}
	close $fh;
	if ( -e $text_file ) {
		my $excel =
		  BIGSdb::Utils::text2excel( $text_file,
			{ worksheet => 'Paralogous', tmp_dir => $self->{'config'}->{'secure_tmp_dir'} } );
		my $excel_file = "$self->{'config'}->{'tmp_dir'}/${job_id}_paralogous.xlsx";
		if ( -e $excel_file ) {
			$self->{'jobManager'}->update_job_output(
				$job_id,
				{
					filename    => "${job_id}_paralogous.xlsx",
					description => '40_Paralogous loci (Excel format)',
					compress    => 1
				}
			);
		}
		unlink $text_file;
	}
	return;
}

sub _find_isolates_with_no_seq {
	my ( $self, $scan_data ) = @_;
	my @ids        = sort { $a <=> $b } keys %{ $scan_data->{'isolate_data'} };
	my @paralogous = sort keys %{ $scan_data->{'paralogous'} };
	my %paralogous = map { $_ => 1 } @paralogous;
	my @no_seqs;
	foreach my $id ( sort @ids ) {
		my @loci        = keys %{ $scan_data->{'isolate_data'}->{$id}->{'sequences'} };
		my $all_missing = 1;
		foreach my $locus (@loci) {
			next if $paralogous{$locus};
			if ( $scan_data->{'isolate_data'}->{$id}->{'sequences'}->{$locus} ) {
				$all_missing = 0;
			}
		}
		push @no_seqs, $id if $all_missing;
	}
	return \@no_seqs;
}

sub _itol_upload {
	my ( $self, $job_id, $params, $identifiers, $message_html ) = @_;
	$self->{'jobManager'}
	  ->update_job_status( $job_id, { stage => 'Uploading tree files to iTOL', percent_complete => 95 } );
	my $tree_file =
	  $params->{'tree_gen'} eq 'profiles'
	  ? "$self->{'config'}->{'tmp_dir'}/$job_id.nwk"
	  : "$self->{'config'}->{'tmp_dir'}/$job_id.ph";
	my $itol_tree_filename = "$self->{'config'}->{'tmp_dir'}/$job_id.tree";
	copy( $tree_file, $itol_tree_filename ) or $logger->error("Copy failed: $!");
	chdir $self->{'config'}->{'tmp_dir'};
	my $zip = Archive::Zip->new;
	$zip->addFile("$job_id.tree");
	my @files_to_delete = ($itol_tree_filename);

	if ( $params->{'itol_dataset'} ) {
		my @itol_dataset_fields = split /\|_\|/x, $params->{'itol_dataset'};
		my $i = 1;
		foreach my $field (@itol_dataset_fields) {
			my $colour = BIGSdb::Utils::get_heatmap_colour_style( $i, scalar @itol_dataset_fields, { rgb => 1 } );
			$i++;
			my $file = $self->_create_itol_dataset( $job_id, $params->{'data_type'}, $identifiers, $field, $colour );
			next if !$file;
			( my $new_name = $field ) =~ s/\|\|/_/x;
			$zip->addFile( $file, $new_name );
			push @files_to_delete, $file;
		}
	}
	unless ( $zip->writeToFileNamed("$job_id.zip") == AZ_OK ) {
		$logger->error("Cannot write $job_id.zip");
	}
	unlink @files_to_delete;
	my $desc     = $self->get_db_description;
	my $uploader = LWP::UserAgent->new( agent => 'BIGSdb' );
	my $response = $uploader->post(
		ITOL_UPLOAD_URL,
		Content_Type => 'form-data',
		Content      => [
			zipFile         => ["$job_id.zip"],
			APIkey          => "$self->{'config'}->{'itol_api_key'}",
			projectName     => "$self->{'config'}->{'itol_project_name'}",
			treeDescription => $desc
		]
	);
	if ( $response->is_success ) {
		if ( !$response->content ) {
			$$message_html .= q(<p class="statusbad">iTOL upload failed. iTOL returned no tree link.</p>);
		} else {
			my @res = split /\n/x, $response->content;
			my $err;

			#check for an upload error
			foreach my $res_line (@res) {
				if ( $res_line =~ /^ERR/x ) {
					$err .= $res_line;
				}
			}
			if ($err && $err !~ /Couldn't\sfind\sID/x) {
				$$message_html .= q(<p class="statusbad">iTOL encountered an error but may have been )
				  . qq(able to make a tree. iTOL returned the following error message:\n\n$err</p>);
				$logger->error($err);
			}
			foreach my $res_line (@res) {
				if ( $res_line =~ /^SUCCESS:\ (\S+)/x ) {
					my $url    = ITOL_TREE_URL . "/$1";
					my $domain = ITOL_DOMAIN;
					$$message_html .= q(<p style="margin-top:2em;margin-bottom:2em">)
					  . qq(<a href="$url" target="_blank" class="launchbutton">Launch iTOL</a></p>);
					last;
				}
			}
		}
		$self->{'jobManager'}->update_job_status( $job_id, { message_html => $$message_html } );
	} else {
		$logger->error( $response->as_string );
		$$message_html .= q(<p class="statusbad">iTOL upload failed.</p>);
		$self->{'jobManager'}->update_job_status( $job_id, { message_html => $$message_html } );
	}
	return "$self->{'config'}->{'tmp_dir'}/$job_id.zip";
}

sub _create_itol_dataset {
	my ( $self, $job_id, $data_type, $identifiers, $field, $colour ) = @_;
	my $field_info = $self->_get_field_type($field);
	my ( $type, $name, $extended_field, $scheme_id, $cscheme_id ) =
	  @{$field_info}{qw(type field extended_field scheme_id cscheme_id)};
	$extended_field //= q();
	$name           //= q();
	( my $cleaned_ext_field = $extended_field ) =~ s/'/\\'/gx;
	my $scheme_field_desc;
	my $scheme_temp_table = q();
	my @ids;

	foreach my $identifier (@$identifiers) {
		if ( $identifier =~ /^(u?\d+)/x ) {
			push @ids, $self->{'reverse_name_map'}->{$1} // $1;
		}
	}
	if ( $type eq 'scheme_field' ) {
		my $set_id      = $self->get_set_id;
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
		$scheme_field_desc = "$name ($scheme_info->{'name'})";
		$scheme_temp_table = $self->_create_scheme_field_temp_table( \@ids, $scheme_id, $name );
	}
	my $eav_table         = q();
	my $cleaned_eav_field = q();
	if ( $type eq 'eav_field' ) {
		$eav_table = $self->{'datastore'}->get_eav_field_table($name);
		( $cleaned_eav_field = $name ) =~ s/'/\\'/gx;
	}
	my $cscheme_temp_table   = q();
	my $cleaned_cscheme_name = q();
	my $pk_field             = q();
	if ( $type eq 'classification_group' ) {
		$cscheme_temp_table = $self->{'datastore'}->create_temp_cscheme_table($cscheme_id);
		( $scheme_id, $cleaned_cscheme_name ) = $self->{'datastore'}
		  ->run_query( 'SELECT scheme_id,name FROM classification_schemes WHERE id=?', $cscheme_id );
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		$pk_field          = $scheme_info->{'primary_key'};
		$scheme_temp_table = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
	}
	return if !$type;
	my %dataset_label = (
		field                => $name,
		extended_field       => $extended_field,
		eav_field            => $name,
		scheme_field         => $scheme_field_desc,
		classification_group => $cleaned_cscheme_name
	);
	my $filename = "${job_id}_$field";
	$filename .= qq(_$scheme_id) if $scheme_id;
	my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
	open( my $fh, '>:encoding(utf8)', $filename ) || $logger->error("Cannot open $filename for writing");
	my $dataset_type = {
		text_label    => 'TEXT',
		colour_strips => 'COLORSTRIP'
	};
	$data_type //= 'text_label';
	say $fh "DATASET_$dataset_type->{$data_type}";
	say $fh 'SEPARATOR TAB';
	say $fh "DATASET_LABEL\t$dataset_label{$type}";
	say $fh "COLOR\t$colour";
	my $value_colour = {};

	#Find out how many distinct values there are in dataset
	if ( !$self->{'temp_list_created'} ) {
		$self->{'datastore'}->create_temp_list_table_from_array( 'int', \@ids, { table => $job_id } );
		$self->{'temp_list_created'} = 1;
	}
	my $distinct_qry = {
		field => "SELECT DISTINCT($name) FROM $self->{'system'}->{'view'} "
		  . "WHERE id IN (SELECT value FROM $job_id) AND $name IS NOT NULL ORDER BY $name",
		extended_field => 'SELECT DISTINCT(e.value) FROM isolate_value_extended_attributes AS e '
		  . "JOIN $self->{'system'}->{'view'} AS i ON e.isolate_field='$name' AND e.attribute=E'$cleaned_ext_field' "
		  . "AND e.field_value=i.$name WHERE i.id IN (SELECT value FROM $job_id) AND e.value IS NOT NULL "
		  . 'ORDER BY e.value',
		eav_field => "SELECT DISTINCT(eav.value) FROM $eav_table AS eav JOIN $self->{'system'}->{'view'} AS i "
		  . "ON eav.isolate_id=i.id AND eav.field=E'$cleaned_eav_field' WHERE i.id IN (SELECT value FROM $job_id) "
		  . 'AND eav.value IS NOT NULL ORDER BY eav.value',
		scheme_field         => "SELECT DISTINCT(value) FROM $scheme_temp_table WHERE value IS NOT NULL ORDER BY value",
		classification_group => "SELECT DISTINCT(group_id) FROM $cscheme_temp_table c JOIN $scheme_temp_table s ON "
		  . "c.profile_id=s.$pk_field WHERE s.id IN (SELECT value FROM $job_id) ORDER BY group_id"
	};
	my $distinct_values =
	  $self->{'datastore'}->run_query( $distinct_qry->{$type}, undef, { fetch => 'col_arrayref' } );
	if ( !$self->{'cache'}->{'attributes'}->{$name} ) {
		my $att = $self->{'xmlHandler'}->get_field_attributes($name);
		if ( ( $att->{'multiple'} // q() ) eq 'yes' && ( $att->{'optlist'} // q() ) eq 'yes' ) {
			$self->{'cache'}->{'optlist'}->{$name} = $self->{'xmlHandler'}->get_field_option_list($name);
		}
		$self->{'cache'}->{'attributes'}->{$name} = $att;
	}
	if ( ( $self->{'cache'}->{'attributes'}->{$name}->{'multiple'} // q() ) eq 'yes' ) {
		my @new_list;
		foreach my $value (@$distinct_values) {
			local $" = q(; );
			if ( $self->{'cache'}->{'optlist'}->{$name} ) {
				my $reordered_value =
				  BIGSdb::Utils::arbitrary_order_list( $self->{'cache'}->{'optlist'}->{$name}, $value );
				push @new_list, qq(@$reordered_value);
			} else {
				my @reordered_value =
				  $self->{'cache'}->{'attributes'}->{$name}->{'type'} ne 'text'
				  ? sort { $a <=> $b } @$value
				  : sort { $a cmp $b } @$value;
				push @new_list, qq(@reordered_value);
			}
		}
		@$distinct_values = @new_list;
	}
	my $distinct = @$distinct_values;
	my $i        = 1;
	my $all_ints = BIGSdb::Utils::all_ints($distinct_values);
	foreach my $value ( sort { $all_ints ? $a <=> $b : $a cmp $b } @$distinct_values ) {
		if ( $type eq 'field' && $self->{'datastore'}->field_needs_conversion($name) ) {
			$value = $self->{'datastore'}->convert_field_value( $name, $value );
		}
		$value_colour->{$value} = BIGSdb::Utils::get_rainbow_gradient_colour( $i, $distinct );
		$i++;
	}
	my $init_output = { colour_strips => \&colour_strips_init };
	if ( $init_output->{$data_type} ) {
		say $fh $init_output->{$data_type}->( $dataset_label{$type}, $value_colour );
	}
	say $fh 'DATA';
	my $row_output = {
		text_label    => \&text_label_output,
		colour_strips => \&colour_strips_output
	};
	my $qry = {
		field          => "SELECT $name FROM $self->{'system'}->{'view'} WHERE id=?",
		extended_field => 'SELECT e.value FROM isolate_value_extended_attributes AS e '
		  . "JOIN $self->{'system'}->{'view'} AS i ON e.isolate_field='$name' AND "
		  . "e.attribute=E'$cleaned_ext_field' AND e.field_value=i.$name WHERE i.id=?",
		eav_field            => "SELECT value FROM $eav_table WHERE isolate_id=? AND field=E'$cleaned_eav_field'",
		scheme_field         => "SELECT value FROM $scheme_temp_table WHERE id=?",
		classification_group => "SELECT group_id FROM $cscheme_temp_table c JOIN $scheme_temp_table s "
		  . "ON c.profile_id=s.$pk_field WHERE s.id=?"
	};
	my $buffer = q();
	foreach my $identifier (@$identifiers) {
		if ( $identifier =~ /^(u?\d+)/x ) {
			my $id = $self->{'reverse_name_map'}->{$1} // $1;
			my $data =
			  $self->{'datastore'}->run_query( $qry->{$type}, $id, { cache => "ITol::itol_dataset::$field" } );
			next if !defined $data;
			if ( $self->{'datastore'}->field_needs_conversion($name) ) {
				$data = $self->{'datastore'}->convert_field_value( $name, $data );
			}
			if ( ( $self->{'cache'}->{'attributes'}->{$name}->{'multiple'} // q() ) eq 'yes' ) {
				local $" = q(; );
				if ( $self->{'cache'}->{'optlist'}->{$name} ) {
					my $reordered_value =
					  BIGSdb::Utils::arbitrary_order_list( $self->{'cache'}->{'optlist'}->{$name}, $data );
					$data = qq(@$reordered_value);
				} else {
					my @reordered_value =
					  $self->{'cache'}->{'attributes'}->{$name}->{'type'} ne 'text'
					  ? sort { $a <=> $b } @$data
					  : sort { $a cmp $b } @$data;
					$data = qq(@reordered_value);
				}
			}
			$identifier =~ s/,/_/gx;
			my @args = ( $identifier, $data, $value_colour->{$data} );
			$buffer .= $row_output->{$data_type}->(@args) . qq(\n);
		}
	}
	say $fh $buffer;
	close $fh;
	return $filename;
}

sub colour_strips_init {
	my ( $field, $value_colour ) = @_;
	my $buffer = qq(LEGEND_TITLE\t$field\n);
	my ( @colours, @labels );
	my @values   = keys %$value_colour;
	my $all_ints = BIGSdb::Utils::all_ints( \@values );
	foreach my $value ( sort { $all_ints ? $a <=> $b : $a cmp $b } @values ) {
		push @colours, $value_colour->{$value};
		push @labels,  $value;
	}
	local $" = qq(\t);
	my @shapes = (2) x @labels;
	$buffer .= qq(LEGEND_SHAPES\t@shapes\n);
	$buffer .= qq(LEGEND_COLORS\t@colours\n);
	$buffer .= qq(LEGEND_LABELS\t@labels\n);
	$buffer .= qq(BORDER_WIDTH\t1\n);
	return $buffer;
}

sub text_label_output {
	my ( $identifier, $value, $colour ) = @_;
	return qq($identifier\t$value\t-1\t$colour\tnormal\t1);
}

sub colour_strips_output {
	my ( $identifier, $value, $colour ) = @_;
	return qq($identifier\t$colour\t$value);
}

sub _create_scheme_field_temp_table {
	my ( $self, $ids, $scheme_id, $field ) = @_;
	my $temp_table = "temp_${scheme_id}_$field";
	eval {
		$self->{'db'}->do("CREATE TEMP table $temp_table (id int, value text,PRIMARY KEY (id))");
		foreach my $id (@$ids) {
			my $values =
			  $self->get_scheme_field_values( { isolate_id => $id, scheme_id => $scheme_id, field => $field } );
			next if !defined $values->[0];
			local $" = q(; );
			no warnings 'uninitialized';    #Values may be null
			$self->{'db'}->do( "INSERT INTO $temp_table VALUES (?,?)", undef, $id, "@$values" );
		}
	};
	$logger->error($@) if $@;
	return $temp_table;
}

sub _get_field_type {
	my ( $self, $field ) = @_;
	if ( $field =~ /^f_(.+)/x ) {
		if ( $self->{'xmlHandler'}->is_field($1) ) {
			return { type => 'field', field => $1 };
		}
	}
	if ( $field =~ /^e_(.+)\|\|(.+)/x ) {
		if (
			$self->{'xmlHandler'}->is_field($1)
			&& $self->{'datastore'}->run_query(
				'SELECT EXISTS(SELECT * FROM isolate_field_extended_attributes '
				  . 'WHERE (isolate_field,attribute)=(?,?))',
				[ $1, $2 ]
			)
		  )
		{
			return { type => 'extended_field', field => $1, extended_field => $2 };
		}
	}
	if ( $field =~ /^s_(\d+)_(.+)/x ) {
		if ( $self->{'datastore'}->is_scheme_field( $1, $2 ) ) {
			return { type => 'scheme_field', scheme_id => $1, field => $2 };
		}
	}
	if ( $field =~ /^eav_(.+)/x ) {
		if ( $self->{'datastore'}->is_eav_field($1) ) {
			return { type => 'eav_field', field => $1 };
		}
	}
	if ( $field =~ /^cg_(\d+)_group$/x ) {
		return { type => 'classification_group', cscheme_id => $1 };
	}
	return;
}

sub print_info_panel {
	my ($self) = @_;
	my $logo = '/images/plugins/ITOL/logo.png';
	say q(<div class="box" id="resultspanel">);
	say q(<div style="float:left">);
	say qq(<img src="$logo" style="width:100px;margin-right:2em" />);
	say q(</div>);
	say q(<p>This plugin uploads data for analysis within the Interactive Tree of Life online service:</p>);
	say q(<p>iTOL is developed by: Ivica Letunic (1) and Peer Bork (2,3,4)</p>);
	say q(<ol style="overflow:hidden">);
	say q(<li>Biobyte solutions GmbH, Bothestr 142, 69126 Heidelberg, Germany</li>);
	say q(<li>European Molecular Biology Laboratory, Meyerhofstrasse 1, 69117 Heidelberg, Germany</li>);
	say q(<li>Max Delbr&uuml;ck Centre for Molecular Medicine, 13125 Berlin, Germany</li>);
	say q(<li>Department of Bioinformatics, Biocenter, University of W&uuml;rzburg, 97074 W&uuml;rzburg, Germany</li>);
	say q(</ol>);
	say q(<p>Web site: <a href="https://itol.embl.de/">https://itol.embl.de/</a><br />);
	say q(Publication: Letunic &amp; Bork (2021) Interactive tree of life (iTOL) v5: an online tool for phylogenetic )
	  . q(tree display and annotation. <a href="https://www.ncbi.nlm.nih.gov/pubmed/33885785">)
	  . q(<i>Nucleic Acids Res</i> <b>49(W1):</b>W293-6</a>.</p>);
	say q(</div>);
	return;
}
1;
