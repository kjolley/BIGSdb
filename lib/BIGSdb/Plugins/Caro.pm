#Caro.pm - CARO project plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2024-2025, University of Oxford
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
package BIGSdb::Plugins::Caro;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugins::GenomeComparator);
use List::MoreUtils qw(uniq);
use BIGSdb::Exceptions;
use Bio::SeqIO;
use BIGSdb::Constants qw(:limits);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_RECORDS    => 2000;
use constant MAX_SEQ_LENGTH => 16_000;    #Excel has 16384 max columns.

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name    => 'CARO',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			},
			{
				name        => 'Priyanshu Raikwar',
				affiliation => 'University of Oxford, UK',
				email       => 'priyanshu.raikwar@biology.ox.ac.uk'
			},
			{
				name        => 'Seungwon Ko',
				affiliation => 'University of Oxford, UK',
				email       => 'seungwon.ko@kellogg.ox.ac.uk'
			}
		],
		description      => 'Calculation of mutation rates and locations',
		full_description => 'The plugin aligns sequences for a specified locus, or for a locus defined by an exemplar '
		  . 'sequence, for an isolate dataset. A mutation analysis is then performed on the alignment.',
		category   => 'Third party',
		buttontext => 'CARO Project',
		menutext   => 'CARO Project',
		module     => 'Caro',
		version    => '0.0.2',
		dbtype     => 'isolates',
		section    => 'analysis,postquery',
		input      => 'query',
		help       => 'tooltips',
		requires   => 'aligner,mafft,offline_jobs,caro',

		#		supports   => 'user_genomes',
		#		url        => "$self->{'config'}->{'doclink'}/data_analysis/snp_sites.html",
		order => 19,
		min   => 2,
		max   => $self->{'system'}->{'caro_record_limit'} // $self->{'config'}->{'caro_record_limit'} // MAX_RECORDS,
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
	if ( !$self->{'config'}->{'snp_sites_path'} ) {
		$self->print_bad_status( { message => q(snp-sites is not installed.) } );
		return;
	}
	return if $self->has_set_changed;
	if ( !-x $self->{'config'}->{'mafft_path'} ) {
		$logger->error('This plugin requires MAFFT to be installed and it is not.');
		$self->print_bad_status( { message => q(mafft_path is not defined.) } );
		return;
	}
	if ( $q->param('submit') ) {
		my $ids = $self->filter_list_to_ids( [ $q->multi_param('isolate_id') ] );
		my ( $pasted_cleaned_ids, $invalid_ids ) = $self->get_ids_from_pasted_list( { dont_clear => 1 } );
		push @$ids, @$pasted_cleaned_ids;
		@$ids = uniq @$ids;
		my @errors;
		if (@$invalid_ids) {
			local $" = ', ';
			push @errors, qq(The following isolates in your pasted list are invalid: @$invalid_ids.);
		}
		if ( $q->param('paste_seq') ) {
			my $seq       = $q->param('paste_seq');
			my $valid_dna = BIGSdb::Utils::is_valid_DNA( \$seq, { allow_ambiguous => 1 } );
			$seq =~ s/[\-\.\s]//gx;
			$q->param( paste_seq => $seq );
			if ( !$valid_dna ) {
				push @errors, q(The pasted sequence includes non-nucleotide characters. This field should )
				  . q(just contain DNA sequence with no FASTA header etc. IUPAC ambiguity codes are allowed.);
			} elsif ( length $seq > MAX_SEQ_LENGTH ) {
				my $length = BIGSdb::Utils::commify( length $seq );
				my $max    = BIGSdb::Utils::commify(MAX_SEQ_LENGTH);
				push @errors, qq(Pasted sequence is too long - max length is $max bp (yours is $length bp));
			}
		} elsif ( !$q->param('locus') ) {
			push @errors, q(You must either select a locus or paste in an exemplar sequence.);
		}
		if (@errors) {
			if ( @errors == 1 ) {
				$self->print_bad_status( { message => qq(@errors) } );
			} else {
				local $" = q(</p><p>);
				$self->print_bad_status( { message => q(Please address the following:), detail => qq(@errors) } );
			}
		}
		if ( !@errors ) {
			my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
			$q->delete('isolate_paste_list');
			$q->delete('isolate_id');
			my $params = $q->Vars;
			my $set_id = $self->get_set_id;
			$params->{'set_id'} = $set_id if $set_id;
			$params->{'curate'} = 1       if $self->{'curate'};
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
					isolates     => $ids,
					locus        => scalar $q->param('locus')
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
	$self->{'params'} = $params;
	my $aligner     = $self->{'params'}->{'aligner'} //= ( $self->{'config'}->{'mafft_path'} ? 'MAFFT' : 'MUSCLE' );
	my $isolate_ids = $self->{'jobManager'}->get_job_isolates($job_id);
	my $scan_data;
	$self->{'threads'} =
	  BIGSdb::Utils::is_int( $self->{'config'}->{'genome_comparator_threads'} )
	  ? $self->{'config'}->{'genome_comparator_threads'}
	  : 2;
	$self->{'params'}->{'finish_progress'} = 70;
	$self->{'params'}->{'align'}           = 1;
	my $locus;

	if ( $params->{'paste_seq'} ) {
		$locus = 'seq';
		my $seq        = $params->{'paste_seq'};
		my $fasta_file = $self->_create_ref_fasta( $job_id, \$seq );
		my $gb_file    = BIGSdb::Utils::fasta2genbank( $fasta_file, MAX_SEQ_LENGTH );
		my $seq_obj;
		eval {
			my $seqio_object = Bio::SeqIO->new( -file => $gb_file );
			$seq_obj = $seqio_object->next_seq;
		};
		if ($@) {
			BIGSdb::Exception::Plugin->throw('Invalid data in uploaded reference file.');
		}
		$scan_data = $self->assemble_data_for_reference_genome(
			{ job_id => $job_id, ids => $isolate_ids, cds => [ $seq_obj->get_SeqFeatures ] } );
		unlink $fasta_file;
	} else {
		$locus = $params->{'locus'};
		if ( defined $locus ) {
			$locus =~ s/^l_//x;
		}
		$scan_data = $self->assemble_data_for_defined_loci(
			{
				job_id => $job_id,
				ids    => $isolate_ids,
				loci   => [$locus]
			}
		);
	}
	$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => 70, stage => 'Aligning' } );
	( my $escaped_locus = $locus ) =~ s/[\/\|\']/_/gx;
	$escaped_locus =~ tr/ /_/;
	my $alignment_file = $self->_align(
		{
			aligner     => $aligner,
			job_id      => $job_id,
			isolate_ids => $isolate_ids,
			locus       => $locus,
			scan_data   => $scan_data
		}
	);
	if ( -e $alignment_file ) {
		$self->{'jobManager'}->update_job_output( $job_id,
			{ filename => "${job_id}_aligned.fas", description => 'Aligned sequences', compress => 1 } );
		$self->{'jobManager'}
		  ->update_job_status( $job_id, { percent_complete => 95, stage => 'Running mutation analysis' } );
		my $analysis = $params->{'analysis'} // 'n';
		$logger->error("Analysis: $analysis");
		my $output_file = "$self->{'config'}->{'tmp_dir'}/${job_id}.xlsx";
		eval {
			system( "$self->{'config'}->{'caro_path'} -a $alignment_file -t $analysis -o $output_file "
				  . "--mafft_path $self->{'config'}->{'mafft_path'} > /dev/null 2>&1" );
			$self->{'logger'}
			  ->error( "$self->{'config'}->{'caro_path'} -a $alignment_file -t $analysis -o $output_file "
				  . "--mafft_path $self->{'config'}->{'mafft_path'} > /dev/null 2>&1" );
		};
		$logger->error($@) if $@;
		if ( -e $output_file ) {
			$self->{'jobManager'}->update_job_output( $job_id,
				{ filename => "${job_id}.xlsx", description => 'Analysis output', compress => 1 } );
		}
	} else {
		$self->{'jobManager'}->update_job_status( $job_id, { message_html => 'No sequences found to align.' } );
	}
	$self->delete_temp_files("$job_id*");
	return;
}

sub _align {
	my ( $self, $args ) = @_;
	my ( $aligner, $job_id, $isolate_ids, $locus, $scan_data ) =
	  @{$args}{qw(aligner job_id isolate_ids locus scan_data)};
	my $fasta_file  = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}.fas";
	my $aligned_out = "$self->{'config'}->{'tmp_dir'}/${job_id}_aligned.fas";
	open( my $fasta_fh, '>:encoding(utf8)', $fasta_file )
	  || $self->{'logger'}->error("Cannot open $fasta_file for writing");
	my $seq_count = 0;
	my $isolate_names =
	  $self->{'datastore'}->run_query( "SELECT id,$self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'}",
		undef, { fetch => 'all_arrayref', slice => {} } );
	foreach my $isolate (@$isolate_names) {
		( my $name = $isolate->{ $self->{'system'}->{'labelfield'} } ) =~ s/\W/_/gx;
		$self->{'names'}->{ $isolate->{'id'} } = $name;
	}
	foreach my $isolate_id ( sort @$isolate_ids ) {
		my $seqs = $scan_data->{'isolate_data'}->{$isolate_id}->{'sequences'}->{$locus};
		$seqs = [$seqs] if !ref $seqs;
		my $seq_id = 0;
		my $name =
		  $self->{'datastore'}
		  ->run_query( "SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?",
			$isolate_id );
		foreach my $seq (@$seqs) {
			next if !defined $seq;
			$seq_id++;
			my $header_name = "$isolate_id|$name";
			$header_name .= "_$seq_id" if $seq_id > 1;
			say $fasta_fh ">$header_name";
			say $fasta_fh $seq;
			$seq_count++;
		}
	}
	close $fasta_fh;
	if ( $seq_count && -e $fasta_file ) {
		if (   $aligner eq 'MAFFT'
			&& $self->{'config'}->{'mafft_path'} )
		{
			my $threads =
			  BIGSdb::Utils::is_int( $self->{'config'}->{'mafft_threads'} )
			  ? $self->{'config'}->{'mafft_threads'}
			  : 1;
			system( "$self->{'config'}->{'mafft_path'} --thread $threads --quiet "
				  . "--preservecase $fasta_file > $aligned_out" );
		} elsif ( $aligner eq 'MUSCLE'
			&& $self->{'config'}->{'muscle_path'} )
		{
			my $max_mb = $self->{'config'}->{'max_muscle_mb'} // MAX_MUSCLE_MB;
			system( $self->{'config'}->{'muscle_path'},
				-in    => $fasta_file,
				-out   => $aligned_out,
				-maxmb => $max_mb,
				'-quiet'
			);
		} else {
			$self->{'logger'}->error('No aligner selected');
		}
	}
	unlink $fasta_file;
	return $aligned_out;
}

sub _create_ref_fasta {
	my ( $self, $job_id, $seq_ref ) = @_;
	my $filename = "$self->{'config'}->{'secure_tmp_dir'}/$job_id.fasta";
	open( my $fh, '>', $filename ) || $logger->error("Cannot open $filename for writing");
	say $fh '>seq';
	say $fh $$seq_ref;
	close $fh;
	return $filename;
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
	say q(<p><span class="flag" style="color:#c40d13">BETA test version</span></p>);
	say q(<p>This tool will create an alignment for a selected locus for the set of isolates chosen. Alternatively, )
	  . q(you can enter an exemplar sequence to use rather than selecting a locus. A mutation analysis will then be )
	  . q(performed.</p>);
	say q(<p>The mutation analysis code can be found at <a href="https://github.com/jeju2486/caro_project">)
	  . q(https://github.com/jeju2486/caro_project</a>.</p>);
	say qq(<p>Analysis is limited to $max_records isolates.</p>);
	say $q->start_form;
	say q(<div class="scrollable"><div class="flex_container" style="justify-content:left">);
	$self->print_seqbin_isolate_fieldset(
		{ use_all => 0, selected_ids => $selected_ids, isolate_paste_list => 1, allow_empty_list => 0 } );
	$self->_print_locus_fieldset;
	$self->_print_options_fieldset;
	$self->print_action_fieldset;
	say $q->hidden($_) foreach qw (page name db);
	say q(</div></div>);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _print_locus_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left"><legend>Select locus</legend>);
	my ( $locus_list, $locus_labels ) = $self->get_field_selection_list(
		{
			loci                   => 1,
			no_list_by_common_name => 1,
			analysis_pref          => 1,
			query_pref             => 0,
			sort_labels            => 1
		}
	);
	unshift @$locus_list, q();
	say q(<p>);
	if (@$locus_list) {

		#Following is eval'd because it may take a while to populate when a very large number of loci are defined.
		#If the user closes the connection while the page is loading it would otherwise lead to a 500 error.
		eval {
			say $self->popup_menu(
				-name     => 'locus',
				-id       => 'locus',
				-values   => $locus_list,
				-labels   => $locus_labels,
				-multiple => 'false',
			);
		};
	} else {
		say q(No defined loci available for analysis);
	}
	say q(</p>);
	say q(<p style="margin-bottom:0">Alternatively, paste in an exemplar sequence to use:</p>);
	say $q->textarea( -id => 'paste_seq', -name => 'paste_seq', -rows => 5, -columns => 40 );
	say q(</fieldset>);
	return;
}

sub _print_options_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left;height:12em"><legend>Options</legend><ul>);
	my $aligners = [];
	foreach my $aligner (qw(mafft muscle)) {
		push @$aligners, uc($aligner) if $self->{'config'}->{"${aligner}_path"};
	}
	if (@$aligners) {
		say q(<li><label for="aligner" class="display">Aligner: </label>);
		say $q->popup_menu( -name => 'aligner', -id => 'aligner', -values => $aligners );
		say q(</li>);
	}
	say q(<li><label for="analysis" class="display">Analysis: </label>);
	say $q->popup_menu(
		-name   => 'analysis',
		-id     => 'analysis',
		-values => [qw(n p both)],
		-labels => { n => 'nucleotide', p => 'protein' }
	);
	say q(</li>);
	say q(</ul></fieldset>);
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description( { formatted => 1 } );
	return "Caro Project - $desc";
}

sub get_plugin_javascript {
	my ($self) = @_;
	my $buffer = << "END";
\$(function () {
	\$('#locus').select2({placeholder:'Select locus...', allowClear: true});
	\$('#select2-locus-container').removeAttr('title');
	\$("#locus").change(function() {
		\$('#select2-locus-container').removeAttr('title');
	});
	\$("#paste_seq").on('input',function() {
		\$('#locus').prop('disabled', \$("#paste_seq").val().length ? true : false);
	});
});	



END
	return $buffer;
}

sub get_initiation_values {
	return { select2 => 1, billboard => 1 };
}
1;
