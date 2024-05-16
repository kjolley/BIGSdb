#SNPSites.pm - Wrapper for snp-sites plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2024, University of Oxford
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
package BIGSdb::Plugins::SNPSites;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugins::GenomeComparator);
use BIGSdb::Constants qw(:limits);
use BIGSdb::Exceptions;
use List::MoreUtils qw(uniq);
use Digest::MD5;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

#use Try::Tiny;
#use List::MoreUtils qw(uniq);
#use File::Copy;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use constant MAX_RECORDS => 2000;

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name    => 'SNPSites',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			}
		],
		description      => 'Find SNPs in selected loci',
		full_description => 'The SNPSites plugin aligns sequences for specified loci for an isolate dataset. '
		  . 'The alignment is then passed to snp-sites to identify SNP positions.',
		category   => 'Third party',
		buttontext => 'SNPSites',
		menutext   => 'SNPSites',
		module     => 'SNPSites',
		version    => '1.0.0',
		dbtype     => 'isolates',
		section    => 'third_party,postquery',
		input      => 'query',
		help       => 'tooltips',
		requires   => 'aligner,offline_jobs,js_tree',
		supports   => 'user_genomes',

		#		url        => "$self->{'config'}->{'doclink'}/data_analysis/snp_sites.html",
		order => 80,
		min   => 2,
		max   => $self->{'system'}->{'snpsites_record_limit'} // $self->{'config'}->{'snpsites_record_limit'}
		  // MAX_RECORDS,
		always_show_in_menu => 1,

		#		image               => '/images/plugins/SNPSites/screenshot.png'
	);
	return \%att;
}

sub run {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $title  = $self->get_title;
	say qq(<h1>$title</h1>);
	return if $self->has_set_changed;
	if ( !-x $self->{'config'}->{'muscle_path'} && !-x $self->{'config'}->{'mafft_path'} ) {
		$logger->error( 'This plugin requires an aligner (MAFFT or MUSCLE) to be installed and one is not. '
			  . 'Please install one of these or check the settings in bigsdb.conf.' );
		$self->print_bad_status( { message => q(No aligner is defined.) } );
		return;
	}
	if ( $q->param('submit') ) {
		my $ids = $self->filter_list_to_ids( [ $q->multi_param('isolate_id') ] );
		my ( $pasted_cleaned_ids, $invalid_ids ) = $self->get_ids_from_pasted_list( { dont_clear => 1 } );
		push @$ids, @$pasted_cleaned_ids;
		@$ids = uniq @$ids;
		my $continue = 1;
		my @errors;
		if (@$invalid_ids) {
			local $" = ', ';
			push @errors, qq(The following isolates in your pasted list are invalid: @$invalid_ids.);
			$continue = 0;
		}
		$q->param( upload_filename      => scalar $q->param('ref_upload') );
		$q->param( user_genome_filename => scalar $q->param('user_upload') );
		if ( $q->param('align') && !defined $q->param('aligner') ) {
			foreach my $aligner (qw(mafft muscle)) {
				if ( $self->{'config'}->{"${aligner}_path"} ) {
					$q->param( aligner => $aligner );
					last;
				}
			}
		}
		my ( $ref_upload, $user_upload );
		if ( $q->param('user_upload') ) {
			$user_upload = $self->upload_user_file;
		}
		my $filtered_ids = $self->filter_ids_by_project( $ids, scalar $q->param('project_list') );
		if ( !@$filtered_ids && !$q->param('user_upload') ) {
			push @errors, q(You must include one or more isolates. Make sure your selected isolates )
			  . q(haven't been filtered to none by selecting a project.);
			$continue = 0;
		}
		my $attr        = $self->get_attributes;
		my $max_records = $attr->{'max'};
		if ( @$filtered_ids > $max_records ) {
			my $nice_max = BIGSdb::Utils::commify($max_records);
			my $selected = BIGSdb::Utils::commify( scalar @$filtered_ids );
			push @errors, qq(Analysis is limited to $nice_max isolates. You have selected $selected.);
			$continue = 0;
		}
		my $loci_selected = $self->get_selected_loci;
		my ( $pasted_cleaned_loci, $invalid_loci ) = $self->get_loci_from_pasted_list( { dont_clear => 1 } );
		$q->delete('locus');
		push @$loci_selected, @$pasted_cleaned_loci;
		@$loci_selected = uniq @$loci_selected;
		if (@$invalid_loci) {
			local $" = ', ';
			push @errors, qq(The following loci in your pasted list are invalid: @$invalid_loci.);
			$continue = 0;
		}
		$self->add_scheme_loci($loci_selected);
		$self->add_recommended_scheme_loci($loci_selected);
		my $accession = $q->param('accession') || $q->param('annotation');
		if ( !$accession && !$ref_upload && !@$loci_selected && $continue ) {
			push @errors,
			  q[You must either select one or more loci or schemes (make sure these haven't been filtered ]
			  . q[by your options), provide a genome accession number, or upload an annotated genome.];
			$continue = 0;
		}
		if (@errors) {
			if ( @errors == 1 ) {
				$self->print_bad_status( { message => qq(@errors) } );
			} else {
				local $" = q(</p><p>);
				$self->print_bad_status( { message => q(Please address the following:), detail => qq(@errors) } );
			}
		}
		$q->param( ref_upload  => $ref_upload )  if $ref_upload;
		$q->param( user_upload => $user_upload ) if $user_upload;
		$q->param( align       => 'on' );
		$q->param( align_all   => 'on' );
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		if ($continue) {
			$q->delete('isolate_paste_list');
			$q->delete('locus_paste_list');
			$q->delete('isolate_id');
			my $params = $q->Vars;
			my $set_id = $self->get_set_id;
			$params->{'set_id'} = $set_id if $set_id;
			$params->{'curate'} = 1       if $self->{'curate'};
			local $" = q(,);
			$params->{'cite_schemes'} = "@{$self->{'cite_schemes'}}";
			my $att    = $self->get_attributes;
			my $job_id = $self->{'jobManager'}->add_job(
				{
					dbase_config => $self->{'instance'},
					ip_address   => $q->remote_host,
					module       => $att->{'module'},
					priority     => $att->{'priority'},
					parameters   => $params,
					username     => $self->{'username'},
					email        => $user_info->{'email'},
					isolates     => $filtered_ids,
					loci         => $loci_selected
				}
			);
			say $self->get_job_redirect($job_id);
			return;
		}
	}
	$self->_print_interface;
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	$self->{'exit'} = 0;
	$self->{'threads'} =
	  BIGSdb::Utils::is_int( $self->{'config'}->{'genome_comparator_threads'} )
	  ? $self->{'config'}->{'genome_comparator_threads'}
	  : 2;

	#Allow temp files to be cleaned on kill signals
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1; $self->signal_kill_job($job_id) } ) x 3;
	$self->{'params'} = $params;
	my $loci         = $self->{'jobManager'}->get_job_loci($job_id);
	my $isolate_ids  = $self->{'jobManager'}->get_job_isolates($job_id);
	my $user_genomes = $self->process_uploaded_genomes( $job_id, $isolate_ids, $params );
	my $aligner      = $self->{'params'}->{'aligner'};
	if ( !@$isolate_ids && !keys %$user_genomes ) {
		$self->{'jobManager'}->update_job_status(
			$job_id,
			{
				message_html => q(<p class="statusbad">You must include one or more isolates. Make )
				  . q(sure your selected isolates haven't been filtered to none by selecting a project.</p>)
			}
		);
		return;
	}
	if ( !@$loci ) {
		$self->{'jobManager'}->update_job_status(
			$job_id,
			{
				message_html => q(<p class="statusbad">You must either select one or more loci or schemes.</p>)
			}
		);
		return;
	}
	if ( !$aligner ) {
		$self->{'jobManager'}->update_job_status(
			$job_id,
			{
				message_html => q(<p class="statusbad">No aligner has been specified.</p>)
			}
		);
		return;
	}
	my $scan_data = $self->assemble_data_for_defined_loci(
		{ job_id => $job_id, ids => $isolate_ids, user_genomes => $user_genomes, loci => $loci } );
	my $alignment_zip = "$self->{'config'}->{'tmp_dir'}/${job_id}_align.zip";
	foreach my $locus (@$loci) {
		last if $self->{'exit'};
		( my $escaped_locus = $locus ) =~ s/[\/\|\']/_/gx;
		$escaped_locus =~ tr/ /_/;
		my $alignment = $self->_align_locus(
			{
				aligner       => $aligner,
				job_id        => $job_id,
				isolate_ids   => $isolate_ids,
				locus         => $locus,
				escaped_locus => $escaped_locus,
				scan_data     => $scan_data
			}
		);
		if ( -e $alignment->{'alignment_file'} ) {
			$self->_zip_append($alignment_zip, $alignment->{'alignment_file'}, "$escaped_locus.aln");
			unlink $alignment->{'alignment_file'};
		}
	}
	if ( -e $alignment_zip ) {
		$self->{'jobManager'}
		  ->update_job_output( $job_id, { filename => "${job_id}_align.zip", description => 'Alignments (ZIP file)' } );
	}
	return;
}

sub _zip_append {
	my ( $self, $zip_file, $file_path, $renamed_file ) = @_;
	if ( -e $zip_file ) {
		my $zip = Archive::Zip->new;
		unless ( $zip->read($zip_file) == AZ_OK ) {
			$logger->error("Error reading zip file $zip_file");
			BIGSdb::Exception::Plugin->throw("Error reading zip file $zip_file");
		}
		my $file_member = $zip->addFile($file_path);
		$file_member->fileName($renamed_file);
		unless ( $zip->overwrite == AZ_OK ) {
			$logger->error("Error writing zip file $zip_file");
			BIGSdb::Exception::Plugin->throw("Error writing zip file $zip_file");
		}
	} else {
		my $zip         = Archive::Zip->new;
		my $file_member = $zip->addFile($file_path);
		$file_member->fileName($renamed_file);
		unless ( $zip->writeToFileNamed($zip_file) == AZ_OK ) {
			$logger->error("Error creating zip file $zip_file");
			BIGSdb::Exception::Plugin->throw("Error creating zip file $zip_file");
		}
	}
	chmod oct('0664'), $zip_file;
	return;
}

sub _align_locus {
	my ( $self, $args ) = @_;
	my ( $aligner, $job_id, $isolate_ids, $locus, $escaped_locus, $scan_data ) =
	  @{$args}{qw(aligner job_id isolate_ids locus escaped_locus scan_data)};
	my $fasta_file  = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}_$escaped_locus.fasta";
	my $aligned_out = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}_$escaped_locus.aln";
	my $alleles     = 0;
	open( my $fasta_fh, '>:encoding(utf8)', $fasta_file )
	  || $self->{'logger'}->error("Cannot open $fasta_file for writing");
	my $seqs = 0;
	my %seen;

	foreach my $isolate_id (@$isolate_ids) {
		my $seq = $scan_data->{'isolate_data'}->{$isolate_id}->{'sequences'}->{$locus};
		if ($seq) {
			my $seq_hash = Digest::MD5::md5_hex($seq);
			$seen{$seq_hash} = 1;
			say $fasta_fh ">$isolate_id";
			say $fasta_fh $seq;
			$seqs++;
		}
	}
	if ( $seqs && -e $fasta_file ) {
		if (   $aligner eq 'MAFFT'
			&& $self->{'config'}->{'mafft_path'} )
		{
			my $threads =
			  BIGSdb::Utils::is_int( $self->{'config'}->{'mafft_threads'} ) ? $self->{'config'}->{'mafft_threads'} : 1;
			system( "$self->{'config'}->{'mafft_path'} --thread $threads --quiet "
				  . "--preservecase --clustalout $fasta_file > $aligned_out" );
		} elsif ( $aligner eq 'MUSCLE'
			&& $self->{'config'}->{'muscle_path'} )
		{
			my $max_mb = $self->{'config'}->{'max_muscle_mb'} // MAX_MUSCLE_MB;
			system( $self->{'config'}->{'muscle_path'},
				-in    => $fasta_file,
				-out   => $aligned_out,
				-maxmb => $max_mb,
				'-quiet', '-clwstrict'
			);
		} else {
			$self->{'logger'}->error('No aligner selected');
		}
	}
	close $fasta_fh;
	unlink $fasta_file;
	return {
		alignment_file => $aligned_out,
		sequences      => $seqs,
		alleles        => scalar keys %seen
	};
}

sub _print_interface {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $qry_ref    = $self->get_query($query_file);
	my $selected_ids;
	if ( $q->param('isolate_id') ) {
		my @ids = $q->multi_param('isolate_id');
		$selected_ids = \@ids;
	} elsif ( defined $query_file ) {
		$selected_ids = $self->get_ids_from_query($qry_ref);
	} else {
		$selected_ids = [];
	}
	my $attr        = $self->get_attributes;
	my $max_records = $attr->{'max'};
	say q(<div class="box" id="queryform">);
	say q(<p>This tool will create alignments for each selected locus for the set of isolates chosen. The )
	  . q(<a href="https://github.com/sanger-pathogens/snp-sites" target="_blank">snp-sites</a> tool will then )
	  . q(be used to identify polymorphic sites. Please check the loci that you would like to include. Alternatively )
	  . q(select one or more schemes to include all loci that are members of the scheme.</p>);
	say qq(<p>Analysis is limited to $max_records isolates.</p>);
	say $q->start_form;
	say q(<div class="scrollable"><div class="flex_container" style="justify-content:left">);
	$self->print_seqbin_isolate_fieldset(
		{ use_all => 1, selected_ids => $selected_ids, isolate_paste_list => 1, allow_empty_list => 1 } );
	$self->print_user_genome_upload_fieldset;
	$self->print_isolates_locus_fieldset( { locus_paste_list => 1, no_all_none => 1 } );
	$self->print_scheme_fieldset;
	$self->print_recommended_scheme_fieldset( { no_clear => 1 } );
	$self->_print_options_fieldset;
	$self->print_action_fieldset( { name => 'GenomeComparator' } );
	say $q->hidden($_) foreach qw (page name db);
	say q(</div></div>);
	say $q->end_form;
	say q(</div>);
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description( { formatted => 1 } );
	return "SNPsites - $desc";
}

sub _print_options_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left;height:12em"><legend>Options</legend><ul><li>);
	my $aligners = [];
	foreach my $aligner (qw(mafft muscle)) {
		push @$aligners, uc($aligner) if $self->{'config'}->{"${aligner}_path"};
	}
	if (@$aligners) {
		say q(Aligner: );
		say $q->popup_menu( -name => 'aligner', -id => 'aligner', -values => $aligners );
		say q(</li><li>);
	}
	say q(</ul></fieldset>);
	return;
}

sub get_plugin_javascript {
	my ($self) = @_;
	my $buffer = << "END";
\$(function () {
	\$('#locus,#recommended_schemes').multiselect({
 		classes: 'filter',
 		menuHeight: 250,
 		menuWidth: 400,
 		selectedList: 8
  	}).multiselectfilter();
});	
END
	return $buffer;
}
1;
