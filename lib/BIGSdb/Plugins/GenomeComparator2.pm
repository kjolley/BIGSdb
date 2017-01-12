#GenomeComparator.pm - Genome comparison plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2017, University of Oxford
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
package BIGSdb::Plugins::GenomeComparator2;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use BIGSdb::Constants qw(SEQ_METHODS LOCUS_PATTERN :limits);

#use BIGSdb::Offline::Scan;
use BIGSdb::Offline::GCHelper;
use Digest::MD5;
use List::MoreUtils qw(uniq);
use Error qw(:try);
use JSON;
use Excel::Writer::XLSX;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_DISPLAY_TAXA => 150;
use constant MAX_GENOMES      => 1000;
use constant MAX_REF_LOCI     => 10000;

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name        => 'Genome Comparator',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Compare genomes at defined loci or against loci defined in a reference genome',
		category    => 'Analysis',
		buttontext  => 'GC2 beta',
		menutext    => 'Genome comparator 2 (beta)',
		module      => 'GenomeComparator2',
		version     => '2.0.0',
		dbtype      => 'isolates',
		section     => 'analysis,postquery',
		url         => "$self->{'config'}->{'doclink'}/data_analysis.html#genome-comparator",
		order       => 30,
		requires    => 'aligner,offline_jobs,js_tree',
		input       => 'query',
		help        => 'tooltips',
		system_flag => 'GenomeComparator',
		priority    => 1
	);
	return \%att;
}

sub run {
	my ($self) = @_;
	my $desc = $self->get_db_description;
	say qq(<h1>Genome Comparator - $desc</h1>);
	say q(<span class="flag" style="color:red">Version 2 BETA</span>);
	my $q = $self->{'cgi'};
	if ( $q->param('submit') ) {
		my @ids = $q->param('isolate_id');
		my ( $pasted_cleaned_ids, $invalid_ids ) = $self->get_ids_from_pasted_list( { dont_clear => 1 } );
		push @ids, @$pasted_cleaned_ids;
		@ids = uniq @ids;
		my $continue = 1;
		my $error;
		if (@$invalid_ids) {
			local $" = ', ';
			$error    = "<p>The following isolates in your pasted list are invalid: @$invalid_ids.</p>\n";
			$continue = 0;
		}
		$q->param( upload_filename => $q->param('ref_upload') );
		my $ref_upload;
		if ( $q->param('ref_upload') ) {
			$ref_upload = $self->_upload_ref_file;
		}
		my $filtered_ids = $self->filter_ids_by_project( \@ids, $q->param('project_list') );
		if ( !@$filtered_ids ) {
			$error .= '<p>You must include one or more isolates. Make sure your selected isolates '
			  . "haven't been filtered to none by selecting a project.</p>\n";
			$continue = 0;
		}
		my $max_genomes =
		  ( BIGSdb::Utils::is_int( $self->{'system'}->{'genome_comparator_limit'} ) )
		  ? $self->{'system'}->{'genome_comparator_limit'}
		  : MAX_GENOMES;
		if ( @$filtered_ids > $max_genomes ) {
			$error .=
			    "<p>Genome Comparator analysis is limited to $max_genomes isolates.  You have selected "
			  . @$filtered_ids
			  . ".</p>\n";
			$continue = 0;
		}
		my $loci_selected = $self->get_selected_loci;
		my ( $pasted_cleaned_loci, $invalid_loci ) = $self->get_loci_from_pasted_list( { dont_clear => 1 } );
		$q->delete('locus');
		push @$loci_selected, @$pasted_cleaned_loci;
		@$loci_selected = uniq @$loci_selected;
		if (@$invalid_loci) {
			local $" = ', ';
			$error .= "<p>The following loci in your pasted list are invalid: @$invalid_loci.</p>\n";
			$continue = 0;
		}
		$self->add_scheme_loci($loci_selected);
		my $filtered_loci = $self->_filter_loci($loci_selected);
		my $accession = $q->param('accession') || $q->param('annotation');
		if ( !$accession && !$ref_upload && !@$filtered_loci && $continue ) {
			$error .= q[<p>You must either select one or more loci or schemes (make sure these haven't been filtered ]
			  . qq[by your options), provide a genome accession number, or upload an annotated genome.</p>\n];
			$continue = 0;
		}
		if ($error) {
			say qq(<div class="box statusbad">$error</div>);
		}
		$q->param( ref_upload => $ref_upload ) if $ref_upload;
		if ( $q->param('calc_distances') ) {
			$q->param( align       => 'on' );
			$q->param( align_all   => 'on' );
			$q->param( include_ref => '' );
		}
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		if ($continue) {
			$q->delete('isolate_paste_list');
			$q->delete('locus_paste_list');
			$q->delete('isolate_id');
			my $params = $q->Vars;
			my $set_id = $self->get_set_id;
			$params->{'set_id'} = $set_id if $set_id;
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
					loci         => $filtered_loci
				}
			);
			say $self->get_job_redirect($job_id);
			return;
		}
	}
	$self->_print_interface;
	return;
}

sub _print_interface {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $qry_ref    = $self->get_query($query_file);
	my $selected_ids;
	if ( $q->param('isolate_id') ) {
		my @ids = $q->param('isolate_id');
		$selected_ids = \@ids;
	} elsif ( defined $query_file ) {
		$selected_ids = $self->get_ids_from_query($qry_ref);
	} else {
		$selected_ids = [];
	}
	my $guid = $self->get_guid;
	my $use_all;
	try {
		my $pref =
		  $self->{'prefstore'}->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'GenomeComparator', 'use_all' );
		$use_all = ( defined $pref && $pref eq 'true' ) ? 1 : 0;
	}
	catch BIGSdb::DatabaseNoRecordException with {
		$use_all = 0;
	};
	my $seqbin_values = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT id FROM sequence_bin)');
	if ( !$seqbin_values ) {
		say q(<div class="box" id="statusbad"><p>There are no sequences in the sequence bin.</p></div>);
		return;
	}
	$self->print_set_section if $q->param('select_sets');
	say q(<div class="box" id="queryform"><p>Please select the required isolate ids and loci for comparison - )
	  . q(use CTRL or SHIFT to make multiple selections in list boxes. In addition to selecting individual loci, )
	  . q(you can choose to include all loci defined in schemes by selecting the appropriate scheme description. )
	  . q(Alternatively, you can enter the accession number for an annotated reference genome and compare using )
	  . q(the loci defined in that.</p>);
	say $q->start_form;
	say q(<div class="scrollable">);
	$self->print_seqbin_isolate_fieldset(
		{ use_all => $use_all, selected_ids => $selected_ids, isolate_paste_list => 1 } );
	$self->print_isolates_locus_fieldset( { locus_paste_list => 1 } );
	$self->print_includes_fieldset(
		{
			title                 => 'Include in identifiers',
			preselect             => $self->{'system'}->{'labelfield'},
			include_scheme_fields => 1
		}
	);
	$self->print_scheme_fieldset;
	say q(<div style="clear:both"></div>);
	$self->_print_filter_locus_fieldset;

	#	$self->_print_reference_genome_fieldset;
	$self->_print_parameters_fieldset;

	#	$self->_print_distance_matrix_fieldset;
	$self->_print_alignment_fieldset;

	#	$self->_print_core_genome_fieldset;
	$self->print_sequence_filter_fieldset;
	$self->print_action_fieldset( { name => 'GenomeComparator' } );
	say $q->hidden($_) foreach qw (page name db);
	say q(</div>);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _print_filter_locus_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $has_peptide_loci =
	  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM loci WHERE data_type=?)', 'peptide' );
	my $has_complete_cds_loci = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM loci WHERE complete_cds)');
	return if !$has_peptide_loci && !$has_complete_cds_loci;
	say q(<fieldset style="float:left;height:12em"><legend>Filter loci</legend><ul>);
	if ($has_peptide_loci) {
		say q(<li>);
		say $q->checkbox(
			-name    => 'exclude_peptide_loci',
			-id      => 'exclude_peptide_loci',
			-label   => 'Exclude peptide loci',
			-checked => 'checked'
		);
		say q( <a class="tooltip" title="Exclude peptide loci - Peptide loci often cover regions that are already )
		  . q(covered by nucleotide loci. Scanning these also takes significantly longer.">)
		  . q(<span class="fa fa-info-circle"></span></a></li>);
	}
	if ($has_complete_cds_loci) {
		say q(<li>);
		say $q->checkbox(
			-name    => 'exclude_non_cds_loci',
			-id      => 'exclude_non_cds_loci',
			-label   => 'Exclude non complete CDS loci',
			-checked => 'checked'
		);
		say q( <a class="tooltip" title="Exclude non complete CDS loci - If you are doing a cgMLST type analysis, )
		  . q(you probably don't want to include loci that represent gene fragments.">)
		  . q(<span class="fa fa-info-circle"></span></a></li>);
	}
	say q(</ul></fieldset>);
	return;
}

sub _print_parameters_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left;height:12em"><legend>Parameters / options</legend>);
	say q(<ul><li><label for ="identity" class="parameter">Min % identity:</label>);
	say $q->popup_menu( -name => 'identity', -id => 'identity', -values => [ 30 .. 100 ], -default => 70 );
	say q( <a class="tooltip" title="Minimum % identity - Match required for partial matching.">)
	  . q(<span class="fa fa-info-circle"></span></a></li>);
	say q(<li><label for="alignment" class="parameter">Min % alignment:</label>);
	say $q->popup_menu( -name => 'alignment', -id => 'alignment', -values => [ 10 .. 100 ], -default => 50 );
	say q( <a class="tooltip" title="Minimum % alignment - Percentage of allele sequence length required to be )
	  . q(aligned for partial matching."><span class="fa fa-info-circle"></span></a></li>);
	say q(<li><label for="word_size" class="parameter">BLASTN word size:</label>);
	say $q->popup_menu( -name => 'word_size', -id => 'word_size', -values => [ 7 .. 30 ], -default => 20 );
	say q( <a class="tooltip" title="BLASTN word size - This is the length of an exact match required to )
	  . q(initiate an extension. Larger values increase speed at the expense of sensitivity.">)
	  . q(<span class="fa fa-info-circle"></span></a></li>);
	say q(</ul></fieldset>);
	return;
}

sub _print_alignment_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left;height:12em"><legend>Alignments</legend><ul><li>);
	say $q->checkbox( -name => 'align', -id => 'align', -label => 'Produce alignments', -onChange => 'enable_seqs()' );
	say q( <a class="tooltip" title="Alignments - Alignments will be produced in clustal format using the )
	  . q(selected aligner for any loci that vary between isolates. This may slow the analysis considerably.">)
	  . q(<span class="fa fa-info-circle"></span></a></li><li>);
	say $q->checkbox(
		-name     => 'include_ref',
		-id       => 'include_ref',
		-label    => 'Include ref sequences in alignment',
		-checked  => 1,
		-onChange => 'enable_seqs()'
	);
	say q(</li><li>);
	say $q->checkbox(
		-name     => 'align_all',
		-id       => 'align_all',
		-label    => 'Align all loci (not only variable)',
		-onChange => 'enable_seqs()'
	);
	say q(</li><li>);
	my @aligners;

	foreach my $aligner (qw(mafft muscle)) {
		push @aligners, uc($aligner) if $self->{'config'}->{"$aligner\_path"};
	}
	if (@aligners) {
		say q(Aligner: );
		say $q->popup_menu( -name => 'aligner', -id => 'aligner', -values => \@aligners );
		say q(</li><li>);
	}
	say q(</ul></fieldset>);
	return;
}

sub _filter_loci {
	my ( $self, $loci ) = @_;
	my $q = $self->{'cgi'};
	my $loci_info =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id,data_type,complete_cds FROM loci', undef, { fetch => 'all_arrayref', slice => {} } );
	my %peptide  = map { $_->{'id'} => $_->{'data_type'} eq 'peptide' ? 1 : 0 } @$loci_info;
	my %complete = map { $_->{'id'} => $_->{'complete_cds'}           ? 1 : 0 } @$loci_info;
	my $filtered = [];
	foreach my $locus (@$loci) {
		next if $q->param('exclude_peptide_loci') && $peptide{$locus};
		next if $q->param('exclude_non_cds_loci') && !$complete{$locus};
		push @$filtered, $locus;
	}
	return $filtered;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	$self->{'exit'} = 0;
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1 } ) x 3; #Allow temp files to be cleaned on kill signals
	$self->{'params'} = $params;
	my $loci        = $self->{'jobManager'}->get_job_loci($job_id);
	my $isolate_ids = $self->{'jobManager'}->get_job_isolates($job_id);
	my $accession   = $params->{'accession'} || $params->{'annotation'};
	my $ref_upload  = $params->{'ref_upload'};
	if ( !@$isolate_ids ) {
		$self->{'jobManager'}->update_job_status(
			$job_id,
			{
				message_html => q(<p class="statusbad">You must include one or more isolates. Make )
				  . q(sure your selected isolates haven't been filtered to none by selecting a project.</p>)
			}
		);
		return;
	}
	if ( !$accession && !$ref_upload && !@$loci ) {
		$self->{'jobManager'}->update_job_status(
			$job_id,
			{
				message_html => q(<p class="statusbad">You must either select one or more loci or schemes, )
				  . q(provide a genome accession number, or upload an annotated genome.</p>)
			}
		);
		return;
	}

	#	open( my $excel_fh, '>', \my $excel )
	#	  or $logger->error("Failed to open excel filehandle: $!");    #Store Excel file in scalar $excel
	#	$self->{'excel'}    = \$excel;
	#	$self->{'workbook'} = Excel::Writer::XLSX->new($excel_fh);
	#	$self->{'workbook'}->set_tempdir( $self->{'config'}->{'secure_tmp_dir'} );
	#	$self->{'workbook'}->set_optimization;                         #Reduce memory usage
	#	my $worksheet = $self->{'workbook'}->add_worksheet('all');
	#	$self->{'excel_format'}->{'header'} = $self->{'workbook'}->add_format(
	#		bg_color     => 'navy',
	#		color        => 'white',
	#		bold         => 1,
	#		align        => 'center',
	#		border       => 1,
	#		border_color => 'white'
	#	);
	#	$self->{'excel_format'}->{'locus'} = $self->{'workbook'}->add_format(
	#		bg_color     => '#D0D0D0',
	#		color        => 'black',
	#		align        => 'center',
	#		border       => 1,
	#		border_color => '#A0A0A0'
	#	);
	#	$self->{'excel_format'}->{'normal'} = $self->{'workbook'}->add_format( align => 'center' );
	if ( $accession || $ref_upload ) {
		my $seq_obj;
		if ($accession) {
			$accession =~ s/\s*//gx;
			my @local_annotations = glob("$params->{'dbase_config_dir'}/$params->{'db'}/annotations/$accession*");
			if (@local_annotations) {
				try {
					my $seqio_obj = Bio::SeqIO->new( -file => $local_annotations[0] );
					$seq_obj = $seqio_obj->next_seq;
				}
				catch Bio::Root::Exception with {
					throw BIGSdb::PluginException("Invalid data in local annotation $local_annotations[0].");
				};
			} else {
				my $seq_db = Bio::DB::GenBank->new;
				$seq_db->verbose(2);    #convert warn to exception
				try {
					$seq_obj = $seq_db->get_Seq_by_acc($accession);
				}
				catch Bio::Root::Exception with {
					my $err = shift;
					$logger->debug($err);
					throw BIGSdb::PluginException("No data returned for accession number $accession.");
				};
			}
		} else {
			if ( $ref_upload =~ /fas$/x || $ref_upload =~ /fasta$/x ) {
				try {
					BIGSdb::Utils::fasta2genbank("$self->{'config'}->{'tmp_dir'}/$ref_upload");
				}
				catch Bio::Root::Exception with {
					throw BIGSdb::PluginException('Invalid data in uploaded reference file.');
				};
				$ref_upload =~ s/\.(fas|fasta)$/\.gb/x;
			}
			eval {
				my $seqio_object = Bio::SeqIO->new( -file => "$self->{'config'}->{'tmp_dir'}/$ref_upload" );
				$seq_obj = $seqio_object->next_seq;
			};
			if ($@) {
				throw BIGSdb::PluginException('Invalid data in uploaded reference file.');
			}
			unlink "$self->{'config'}->{'tmp_dir'}/$ref_upload";
		}
		return if !$seq_obj;
		$self->_analyse_by_reference(
			{ job_id => $job_id, accession => $accession, seq_obj => $seq_obj, ids => $isolate_ids, } );
	} else {
		$self->_analyse_by_loci( { job_id => $job_id, loci => $loci, ids => $isolate_ids } );
	}
	return;
}

sub _analyse_by_loci {
	my ( $self, $data ) = @_;
	my ( $job_id, $loci, $ids, $worksheet ) = @{$data}{qw(job_id loci ids worksheet)};
	if ( @$ids < 2 ) {
		$self->{'jobManager'}->update_job_status(
			$job_id,
			{
				    message_html => q(<p class="statusbad">You must select at least two isolates for comparison )
				  . q(against defined loci. Make sure your selected isolates haven't been filtered to fewer )
				  . q(than two by selecting a project.</p>)
			}
		);
		return;
	}
	$self->{'html_buffer'} = qq(<h3>Analysis against defined loci</h3>\n);
	$self->{'file_buffer'} = qq(Analysis against defined loci\n);
	$self->{'file_buffer'} .= q(Time: ) . ( localtime(time) ) . qq(\n\n);
	$self->{'html_buffer'} .=
	    q(<p>Allele numbers are used where these have been defined, otherwise sequences )
	  . q(will be marked as 'New#1, 'New#2' etc. Missing alleles are marked as )
	  . q(<span style="background:black; color:white; padding: 0 0.5em">'X'</span>. Incomplete alleles )
	  . q((located at end of contig) are marked as )
	  . q(<span style="background:green; color:white; padding: 0 0.5em">'I'</span>.</p>);
	$self->{'file_buffer'} .=
	    q(Allele numbers are used where these have been defined, otherwise sequences will be )
	  . qq(marked as 'New#1, 'New#2' etc.\n)
	  . q(Missing alleles are marked as 'X'. Incomplete alleles (located at end of contig) )
	  . qq(are marked as 'I'.\n\n);
	$self->_print_isolate_header( 0, $ids, $worksheet );
	$self->_assemble_data( { by_reference => 0, job_id => $job_id, ids => $ids, loci => $loci } );
	$self->delete_temp_files("$job_id*");
	return;
}

sub _print_isolate_header {
	my ( $self, $by_reference, $ids, $worksheet ) = @_;
	my @header = 'Locus';
	$self->{'html_buffer'} .= q(<div class="scrollable"><table class="resultstable"><tr>);
	if ($by_reference) {
		push @header, ( 'Product', 'Sequence length', ' Genome position', 'Reference genome' );
	}
	foreach my $id (@$ids) {
		my $isolate = $self->_get_isolate_name($id);
		push @header, $isolate;
	}
	local $" = q(</th><th>);
	$self->{'html_buffer'} .= qq(<th>@header</th></tr>);
	local $" = "\t";
	$self->{'file_buffer'} .= qq(@header\n);
	my $col = 0;
	return if !defined $worksheet;
	foreach my $heading (@header) {
		$worksheet->write( 0, $col, $heading, $self->{'excel_format'}->{'header'} );
		$self->{'col_max_width'}->{$col} = length $heading
		  if length $heading > ( $self->{'col_max_width'}->{$col} // 0 );
		$col++;
	}
	$worksheet->freeze_panes( 1, 1 );
	return;
}

sub _get_isolate_name {
	my ( $self, $id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $isolate = $id;
	if ( $options->{'name_only'} ) {
		my $name = $self->{'datastore'}->get_isolate_field_values($id)->{ $self->{'system'}->{'labelfield'} };
		$isolate .= "|$name";
		return $isolate;
	}
	my $additional_fields = $self->_get_identifier( $id, { no_id => 1 } );
	$isolate .= " ($additional_fields)" if $additional_fields;
	return $isolate;
}

sub _get_identifier {
	my ( $self, $id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $value = $options->{'no_id'} ? '' : $id;
	my @includes;
	@includes = split /\|\|/x, $self->{'params'}->{'includes'} if $self->{'params'}->{'includes'};
	if (@includes) {
		my $include_data = $self->{'datastore'}->run_query( "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?",
			$id, { fetch => 'row_hashref', cache => 'GenomeComparator::get_identifier' } );
		my $first = 1;
		foreach my $field (@includes) {
			my $field_value;
			if ( $field =~ /s_(\d+)_([\w_]+)/x ) {
				my ( $scheme_id, $scheme_field ) = ( $1, $2 );
				my $scheme_values = $self->{'datastore'}->get_scheme_field_values_by_isolate_id( $id, $scheme_id );
				my @field_values = keys %{ $scheme_values->{ lc $scheme_field } };
				local $" = q(_);
				$field_value = qq(@field_values);
			} else {
				my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
				if ( defined $metaset ) {
					$field_value = $self->{'datastore'}->get_metadata_value( $id, $metaset, $metafield );
				} else {
					$field_value = $include_data->{$field} // q();
				}
			}
			$field_value =~ tr/[\(\):, ]/_/;
			$value .= '|' if !$first || !$options->{'no_id'};
			$first = 0;
			$value .= $field_value;
		}
	}
	return $value;
}

sub _assemble_data {
	my ( $self, $args ) = @_;
	my ( $by_reference, $job_id, $ids, $loci ) = @{$args}{qw(by_reference job_id ids loci )};
	$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Setting up job' } );
	my $locus_list   = $self->_create_list_file( $job_id, 'loci',     $loci );
	my $isolate_list = $self->_create_list_file( $job_id, 'isolates', $ids );
	my $THREADS      = 6;
	my $PROGRAM      = '/home/keith/git/BIGSdb/scripts/helpers/gc_scan.pl';
	local $" = q(,);
	my @params = (
		'--database'          => $self->{'params'}->{'db'},
		'--isolate_list_file' => $isolate_list,
		'--locus_list_file'   => $locus_list,
		'--threads'           => $THREADS,
		qw(--fast --exemplar --use_tagged)
	);
	local $" = q( );
	my $cmd  = "$PROGRAM @params";
	my $json = `$cmd`;
	my $data = decode_json($json);
	use Data::Dumper;
	$logger->error( Dumper $data);
	$self->_touch_output_files("$job_id*");                   #Prevents premature deletion by cleanup scripts
	return;
}

sub _create_list_file {
	my ( $self, $job_id, $suffix, $list ) = @_;
	my $filename = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}_$suffix.list";
	open( my $fh, '>', $filename ) || $logger->error("Cannot open $filename to write");
	say $fh $_ foreach (@$list);
	close $fh;
	return $filename;
}

sub _touch_output_files {
	my ( $self, $wildcard ) = @_;
	my @files = glob("$self->{'config'}->{'tmp_dir'}/$wildcard");
	foreach (@files) { utime( time(), time(), $1 ) if /^(.*BIGSdb.*)$/x }
	return;
}

sub get_plugin_javascript {
	my ($self) = @_;
	my $buffer = << "END";


function enable_seqs(){
	if (\$("#accession").val() || \$("#ref_upload").val() || \$("#annotation").val()){
		\$("#scheme_fieldset").hide(500);
		\$("#locus_fieldset").hide(500);
		\$("#tblastx").prop("disabled", false);
		\$("#use_tagged").prop("disabled", true);
		\$("#exclude_paralogous").prop("disabled", false);
		\$("#paralogous_options").prop("disabled", false);
	} else {
		\$("#scheme_fieldset").show(500);
		\$("#locus_fieldset").show(500);
		\$("#tblastx").prop("disabled", true);
		\$("#use_tagged").prop("disabled", false);
		\$("#exclude_paralogous").prop("disabled", true);
		\$("#paralogous_options").prop("disabled", true);
	}
	if (\$("#calc_distances").prop("checked")){
		\$("#align").prop("checked", true);
		\$("#align_all").prop("checked", true);
		\$("#include_ref").prop("checked", false);
	} else {
		\$("#align").prop("disabled", false);
	}
	if (\$("#align").prop("checked")){
		\$("#align_all").prop("disabled", false);
		\$("#aligner").prop("disabled", false);
	} else {
		\$("#align_all").prop("disabled", true);
		\$("#aligner").prop("disabled", true);
	}

	if ((\$("#accession").val() || \$("#ref_upload").val() || \$("#annotation").val()) && \$("#align").prop('checked')){
		\$("#include_ref").prop("disabled", false);
	} else {
		\$("#include_ref").prop("disabled", true);
	}
}

\$(function () {
	enable_seqs();
	\$("#accession").bind("input propertychange", function () {
		enable_seqs();
	});
});

END
	return $buffer;
}
1;
