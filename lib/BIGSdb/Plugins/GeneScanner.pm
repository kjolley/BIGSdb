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
package BIGSdb::Plugins::GeneScanner;
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
use constant MAX_RECORDS    => 5000;
use constant MAX_SEQ_LENGTH => 16_000;    #Excel has 16384 max columns.

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name    => 'GeneScanner',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			},
			{
				name        => 'Broncio Aguilar-Sanjuan',
				affiliation => 'University of Oxford, UK',
				email       => 'broncio.aguilarsanjuan@biology.ox.ac.uk',
			},
			{
				name        => 'Seungwon Ko',
				affiliation => 'University of Oxford, UK',
				email       => 'seungwon.ko@kellogg.ox.ac.uk'
			},
			{
				name        => 'Priyanshu Raikwar',
				affiliation => 'University of Oxford, UK',
				email       => 'priyanshu.raikwar@biology.ox.ac.uk'
			},

			{
				name        => 'Samuel Sheppard',
				affiliation => 'University of Oxford, UK',
				email       => 'samuel.sheppard@biology.ox.ac.uk'
			},
			{
				name        => 'Carolin Kobras',
				affiliation => 'University of Oxford, UK',
				email       => 'carolin.kobras@path.ox.ac.uk'
			}
		],
		description      => 'Calculation of mutation rates and locations',
		full_description => 'The plugin aligns sequences for a specified locus, or for a locus defined by an exemplar '
		  . 'sequence, for an isolate dataset. A mutation analysis is then performed on the alignment.',
		category   => 'Analysis',
		buttontext => 'GeneScanner',
		menutext   => 'GeneScanner',
		module     => 'GeneScanner',
		version    => '0.9.1',
		dbtype     => 'isolates',
		section    => 'analysis,postquery',
		input      => 'query',
		help       => 'tooltips',
		requires   => 'aligner,mafft,offline_jobs,genescanner',

		#		url        => "$self->{'config'}->{'doclink'}/data_analysis/genescanner.html",
		order => 19,
		min   => 2,
		max   => $self->{'system'}->{'genescanner_record_limit'} // $self->{'config'}->{'genescanner_record_limit'}
		  // MAX_RECORDS,
		always_show_in_menu => 1,

		#		image               => '/images/plugins/genescanner/screenshot.png'
	);
	return \%att;
}

sub _upload_group_file {
	my ($self) = @_;
	my $file = $self->upload_file( 'group_csv_upload', 'groups' );
	return $file;
}

sub _validate_group_csv {
	my ( $self, $filename, $valid_ids ) = @_;
	my %valid_ids = map { $_ => 1 } @$valid_ids;
	my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
	if ( !-e $full_path ) {
		return 'Group CSV file has not been uploaded.';
	}
	if ( !-s $full_path ) {
		return 'Group CSV file has no contents.';
	}

	open my $fh, '<:encoding(utf8)', $full_path or $logger->error("Cannot open file $full_path: $!");
	my $row = 0;
	while ( my $line = <$fh> ) {
		$line =~ s/^\s+|\s+$//x;
		$row++;
		if ( $row == 1 ) {
			if ( $line ne 'Isolate,Category' ) {
				return q(Header line of group CSV file should be 'Isolate,Category');
			}
			next;
		}

		next if !$line;
		my @fields = split /\s*,\s*/x, $line;
		if ( @fields != 2 ) {
			return "Row $row of group CSV file does not have 2 values.";
		}
		if ( $fields[0] !~ /^\d+$/x ) {
			return "Row $row id of group CSV file is not an integer.";
		}
		if ( !$valid_ids{ $fields[0] } ) {
			return "Row $row id ($fields[0]) of group CSV file is not in the selected dataset.";
		}
	}
	close $fh;
	return;
}

sub _validate_group_list {
	my ( $self, $valid_ids ) = @_;
	my $q         = $self->{'cgi'};
	my %valid_ids = map { $_ => 1 } @$valid_ids;
	my @ids       = split /\r?\n/x, scalar $q->param('group_list');
	my $row       = 0;
	foreach my $id (@ids) {
		$row++;
		next if !$id;
		$id =~ s/^\s+//x;
		$id =~ s/\s+$//x;
		if ( !BIGSdb::Utils::is_int($id) ) {
			return "Row $row id in group list is not an integer.";
		}
		if ( !$valid_ids{$id} ) {
			return "Row $row id in group list is not in the selected dataset.";
		}
	}
	return;
}

sub _validate_reference_id {
	my ( $self, $valid_ids ) = @_;
	my $q         = $self->{'cgi'};
	my %valid_ids = map { $_ => 1 } @$valid_ids;
	my $ref_id    = $q->param('reference');
	if ( !BIGSdb::Utils::is_int($ref_id) ) {
		return 'Reference id is not an integer.';
	}
	if ( !$valid_ids{$ref_id} ) {
		return 'Reference id is not in the selected dataset.';
	}
	return;
}

sub _rewrite_group_csv {
	my ( $self, $filename ) = @_;
	my $names              = $self->_get_isolate_names;
	my $temp               = BIGSdb::Utils::get_random();
	my $full_path          = "$self->{'config'}->{'tmp_dir'}/$filename";
	my $new_filename       = "${temp}_rewritten_groups.csv";
	my $new_file_full_path = "$self->{'config'}->{'tmp_dir'}/$new_filename";
	open my $fh,  '<:encoding(utf8)', $full_path or $logger->error("Cannot open file $full_path for reading: $!");
	open my $fh2, '>:encoding(utf8)', $new_file_full_path
	  or $logger->error("Cannot open file $new_file_full_path for writing: $!");
	my $row = 0;

	while ( my $line = <$fh> ) {
		$line =~ s/^\s+//x;
		$line =~ s/\s+$//x;
		next if !$line;
		my ( $id, $group ) = split /\s*,\s*/x, $line;
		if ( $row == 0 ) {
			say $fh2 $line;
		} else {
			say $fh2 "$id|$names->{$id},$group";
		}
		$row++;
	}
	close $fh;
	close $fh2;
	return $new_filename;
}

sub _write_group_csv_from_list {
	my ( $self, $valid_ids ) = @_;
	my $temp      = BIGSdb::Utils::get_random();
	my $filename  = "${temp}_groups.csv";
	my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
	my $q         = $self->{'cgi'};
	my @ids       = split /\r?\n/x, scalar $q->param('group_list');
	my %group2;
	my $names = $self->_get_isolate_names;

	foreach my $id (@ids) {
		next if !$id;
		$id =~ s/^\s+//x;
		$id =~ s/\s+$//x;
		$group2{$id} = 1;
	}
	open my $fh, '>:encoding(utf8)', $full_path
	  or $logger->error("Cannot open file $full_path for writing: $!");
	say $fh 'Isolate,Category';
	foreach my $id (@$valid_ids) {
		say $fh $group2{$id} ? "$id|$names->{$id},Group 2" : "$id|$names->{$id},Group 1";
	}
	close $fh;
	return $filename;
}

sub run {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $title  = $self->get_title;
	say qq(<h1>$title</h1>);
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
			my $valid_seq = BIGSdb::Utils::is_valid_DNA( \$seq, { allow_ambiguous => 1 } )
			  || BIGSdb::Utils::is_valid_peptide( \$seq );
			$seq =~ s/[\-\.\s]//gx;
			$q->param( paste_seq => $seq );
			if ( !$valid_seq ) {
				push @errors,
					q(The pasted sequence includes non-nucleotide or non-amino acid characters. )
				  . q(This field should just contain DNA or protein sequence with no FASTA header. IUPAC )
				  . q(nucleotide ambiguity codes are allowed.);
			} elsif ( length $seq > MAX_SEQ_LENGTH ) {
				my $length = BIGSdb::Utils::commify( length $seq );
				my $max    = BIGSdb::Utils::commify(MAX_SEQ_LENGTH);
				push @errors, qq(Pasted sequence is too long - max length is $max bp (yours is $length bp));
			}
		} elsif ( !$q->param('locus') ) {
			push @errors, q(You must either select a locus or paste in an exemplar sequence.);
		}
		my $group_csv_file;
		if ( $q->param('group_csv_upload') ) {
			my $uploaded_csv_file = $self->_upload_group_file;
			my $error             = $self->_validate_group_csv( $uploaded_csv_file, $ids );
			push @errors, $error if $error;
			if ( !@errors ) {
				$group_csv_file = $self->_rewrite_group_csv($uploaded_csv_file);
			}
		} elsif ( $q->param('group_list') ) {
			my $error = $self->_validate_group_list($ids);
			if ($error) {
				push @errors, $error;
			} else {
				$group_csv_file = $self->_write_group_csv_from_list($ids);
			}
		}
		if ( $q->param('reference') ) {
			my $error = $self->_validate_reference_id($ids);
			push @errors, $error if $error;
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
			$params->{'set_id'}         = $set_id if $set_id;
			$params->{'curate'}         = 1       if $self->{'curate'};
			$params->{'group_csv_file'} = $group_csv_file;
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
	my $frame = $self->{'params'}->{'frame'};

	if ( !( BIGSdb::Utils::is_int($frame) && $frame >= 1 && $frame <= 3 ) ) {
		$frame = 1;
	}
	my $locus;
	if ( $params->{'paste_seq'} ) {
		$locus = 'seq';
		my $seq        = $params->{'paste_seq'};
		my $fasta_file = $self->_create_ref_fasta( $job_id, \$seq );
		my $gb_file    = BIGSdb::Utils::fasta2genbank( $fasta_file, MAX_SEQ_LENGTH );
		my $seq_type   = BIGSdb::Utils::sequence_type( \$seq );
		my $seq_obj;
		eval {
			my $seqio_object = Bio::SeqIO->new( -file => $gb_file );
			$seq_obj = $seqio_object->next_seq;
		};
		if ($@) {
			BIGSdb::Exception::Plugin->throw('Invalid data in uploaded reference file.');
		}
		$scan_data = $self->assemble_data_for_reference_genome(
			{ job_id => $job_id, ids => $isolate_ids, cds => [ $seq_obj->get_SeqFeatures ], seq_type => $seq_type } );
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
		my $analysis      = $params->{'analysis'} // 'n';
		my $output_file   = "$self->{'config'}->{'tmp_dir'}/${job_id}.xlsx";
		my $groups_clause = q();
		if ( $params->{'group_csv_file'} ) {
			my $file = $params->{'group_csv_file'};
			$groups_clause = qq( --groups "$self->{'config'}->{'tmp_dir'}/$file");
		}
		my $reference_clause = q();
		if ( $params->{'reference'} ) {
			my $ref_id = $params->{'reference'};
			if ( BIGSdb::Utils::is_int($ref_id) ) {
				my $name =
				  $self->{'datastore'}
				  ->run_query( "SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?",
					$ref_id );
				$name =~ s/\W/_/gx;
				$reference_clause = qq( --reference "$ref_id|$name");
			}
		}
		my $snp_sites_clause = q( );
		if ( $params->{'snp_sites'} ) {
			$snp_sites_clause = qq( --snp_sites_path $self->{'config'}->{'snp_sites_path'} --vcf);
		}
		eval {
			system( "$self->{'config'}->{'genescanner_path'} -a $alignment_file -t $analysis -o $output_file "
				  . "--mafft_path $self->{'config'}->{'mafft_path'} --job_id $job_id --tmp_dir "
				  . "$self->{'config'}->{'secure_tmp_dir'} --frame $frame$groups_clause$reference_clause"
				  . "$snp_sites_clause > /dev/null 2>&1" );
		};
		$logger->error($@) if $@;
		if ( -e $output_file ) {
			$self->{'jobManager'}->update_job_output( $job_id,
				{ filename => "${job_id}.xlsx", description => 'Analysis output', compress => 1 } );
		}
		my $vcf_file = "$self->{'config'}->{'tmp_dir'}/${job_id}_aligned.vcf";
		if ( -e $vcf_file ) {
			$self->{'jobManager'}->update_job_output( $job_id,
				{ filename => "${job_id}_aligned.vcf", description => 'VCF file', compress => 1 } );
		}
	} else {
		$self->{'jobManager'}->update_job_status( $job_id, { message_html => 'No sequences found to align.' } );
	}
	$self->delete_temp_files("$job_id*");
	return;
}

sub _get_isolate_names {
	my ($self) = @_;
	my $names = {};
	my $isolate_names =
	  $self->{'datastore'}->run_query( "SELECT id,$self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'}",
		undef, { fetch => 'all_arrayref', slice => {} } );
	foreach my $isolate (@$isolate_names) {
		( my $name = $isolate->{ $self->{'system'}->{'labelfield'} } ) =~ s/\W/_/gx;
		$names->{ $isolate->{'id'} } = $name;
	}
	return $names;
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
	my $names     = $self->_get_isolate_names;
	foreach my $isolate_id ( sort @$isolate_ids ) {
		my $seqs = $scan_data->{'isolate_data'}->{$isolate_id}->{'sequences'}->{$locus};
		$seqs = [$seqs] if !ref $seqs;
		my $seq_id = 0;
		foreach my $seq (@$seqs) {
			next if !defined $seq;
			$seq_id++;
			my $header_name = "$isolate_id|$names->{$isolate_id}";
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
	$self->_print_analysis_fieldset;
	$self->_print_options_fieldset;
	$self->_print_group_fieldset;
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
	say q(<p style="margin-bottom:0">Alternatively, paste in an exemplar sequence to use<br />)
	  . q((this can be either a DNA or protein sequence):</p>);
	say $q->textarea( -id => 'paste_seq', -name => 'paste_seq', -rows => 5, -columns => 40 );
	say q(</fieldset>);
	return;
}

sub _print_analysis_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left;height:12em"><legend>Analysis</legend><ul>);
	say q(<li>);
	say $q->radio_group(
		-name      => 'analysis',
		-id        => 'analysis',
		-values    => [qw(n p both)],
		-labels    => { n => 'nucleotide', p => 'protein' },
		-linebreak => 'true'
	);
	say q(</li></ul></fieldset>);
	return;
}

sub _print_group_fieldset {
	my ($self)       = @_;
	my $q            = $self->{'cgi'};
	my $tooltip_text = << "TOOLTIP";
Groups - The dataset can be optionally divided into any number of groups which will be analysed separately. 
The format for the comma-separated values (CSV) file is:
<pre>
Isolate,Category
[id],[group name]
</pre>
where the group name can be any string, e.g.
<pre>
Isolate,Category
1,GroupA
2,GroupA
3,GroupB
4,GroupB
</pre>
Note that if an isolate id is not included in the CSV file, it will not be included in any group.
TOOLTIP
	my $tooltip = $self->get_tooltip($tooltip_text);
	say q(<fieldset style="float:left;max-width:350px"><legend>Groups</legend>);
	say qq(<p>Optionally upload a CSV file to group isolates for separate analysis. $tooltip</p>);
	say $q->filefield(
		-name  => 'group_csv_upload',
		-id    => 'group_csv_upload',
		-style => 'max-width:300px'
	);
	say q(<a id="clear_group_csv_upload" class="small_reset" title="Clear upload">)
	  . q(<span><span class="far fa-trash-can"></span></span></a>);
	say q(<p style="margin-top:1em">Alternatively, if you want to use just 2 groups you can enter id numbers for )
	  . q(isolates to add to group 2. All other isolates will be placed in group 1.</p>);
	say $q->textarea(
		-id          => 'group_list',
		-name        => 'group_list',
		-width       => 6,
		-rows        => 6,
		-placeholder => 'Enter group 2 ids (one per line)...'
	);
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
		say q(<li><label for="aligner" class="aligned width7">Aligner: </label>);
		say $q->popup_menu( -name => 'aligner', -id => 'aligner', -values => $aligners );
		say q(</li>);
	}
	say q(<li><label for="aligner" class="aligned width7">Reading frame: </label>);
	say $q->popup_menu( -name => 'frame', -id => 'frame', -values => [ 1 .. 3 ] );
	say q(</li></li>);
	say q(<li><label for="reference" class="aligned width7">Reference id: </label>);
	my $max = $self->{'datastore'}->run_query("SELECT MAX(id) FROM $self->{'system'}->{'view'}");
	say $self->textfield(
		-name  => 'reference',
		id     => 'reference',
		-type  => 'number',
		-min   => 1,
		-max   => $max,
		-style => 'width:6em',
		-value => scalar $q->param('reference')
	);
	my $tooltip =
	  $self->get_tooltip( 'Reference id - Id of sequence to treat as the reference (otherwise the first '
		  . 'sequence in the alignment is used by default)' );
	say $tooltip;

	if ( $self->{'config'}->{'snp_sites_path'} ) {
		say q(</li><li>);
		say $q->checkbox( -name => 'snp_sites', -id => 'snp_sites', -label => 'Run SNP-sites' );
	}
	say q(</li>);
	say q(</ul></fieldset>);
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description( { formatted => 1 } );
	return "GeneScanner - $desc";
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
	\$("a#clear_group_csv_upload").on("click", function(){
  		\$("input#group_csv_upload").val("");
  	});
});	



END
	return $buffer;
}

sub get_initiation_values {
	return { select2 => 1, billboard => 1 };
}
1;
