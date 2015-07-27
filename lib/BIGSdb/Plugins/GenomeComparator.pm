#GenomeComparator.pm - Genome comparison plugin for BIGSdb
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
package BIGSdb::Plugins::GenomeComparator;
use strict;
use warnings;
use 5.010;
use feature 'state';
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use Apache2::Connection ();
use Bio::Seq;
use Bio::SeqIO;
use Bio::AlignIO;
use List::MoreUtils qw(uniq any none);
use Digest::MD5;
use Excel::Writer::XLSX;
use BIGSdb::Page qw(SEQ_METHODS LOCUS_PATTERN);
use constant MAX_UPLOAD_SIZE  => 32 * 1024 * 1024;    #32MB
use constant MAX_SPLITS_TAXA  => 200;
use constant MAX_DISPLAY_TAXA => 150;
use constant MAX_GENOMES      => 1000;
use constant MAX_REF_LOCI     => 10000;
use constant MAX_MUSCLE_MB    => 4 * 1024;            #4GB

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name        => 'Genome Comparator',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Compare genomes at defined loci or against loci defined in a reference genome',
		category    => 'Analysis',
		buttontext  => 'Genome Comparator',
		menutext    => 'Genome comparator',
		module      => 'GenomeComparator',
		version     => '1.7.5',
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

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 1, query_field => 1 };
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

sub get_option_list {
	my @list = ( { name => 'use_all', description => 'List isolates without sequence bin data' }, );
	return \@list;
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
	open( my $excel_fh, '>', \my $excel )
	  or $logger->error("Failed to open excel filehandle: $!");    #Store Excel file in scalar $excel
	$self->{'excel'}    = \$excel;
	$self->{'workbook'} = Excel::Writer::XLSX->new($excel_fh);
	$self->{'workbook'}->set_tempdir( $self->{'config'}->{'secure_tmp_dir'} );
	$self->{'workbook'}->set_optimization;                         #Reduce memory usage
	my $worksheet = $self->{'workbook'}->add_worksheet('all');
	$self->{'excel_format'}->{'header'} = $self->{'workbook'}->add_format(
		bg_color     => 'navy',
		color        => 'white',
		bold         => 1,
		align        => 'center',
		border       => 1,
		border_color => 'white'
	);
	$self->{'excel_format'}->{'locus'} = $self->{'workbook'}->add_format(
		bg_color     => '#D0D0D0',
		color        => 'black',
		align        => 'center',
		border       => 1,
		border_color => '#A0A0A0'
	);
	$self->{'excel_format'}->{'normal'} = $self->{'workbook'}->add_format( align => 'center' );

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
			{
				job_id    => $job_id,
				accession => $accession,
				seq_obj   => $seq_obj,
				ids       => $isolate_ids,
				worksheet => $worksheet
			}
		);
	} else {
		$self->_analyse_by_loci( { job_id => $job_id, loci => $loci, ids => $isolate_ids, worksheet => $worksheet } );
	}
	return;
}

sub run {
	my ($self)  = @_;
	my $pattern = LOCUS_PATTERN;
	my $desc    = $self->get_db_description;
	print "<h1>Genome Comparator - $desc</h1>\n";
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
		my $accession = $q->param('accession') || $q->param('annotation');
		if ( !$accession && !$ref_upload && !@$loci_selected && $continue ) {
			$error .= '<p>You must either select one or more loci or schemes, provide '
			  . "a genome accession number, or upload an annotated genome.</p>\n";
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
			print <<"HTML";
<div class="box" id="resultstable">
<p>This analysis has been submitted to the job queue.</p>
<p>Please be aware that this job may take a long time depending on the number of comparisons
and how busy the server is.</p>
<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=job&amp;id=$job_id">
Follow the progress of this job and view the output.</a></p> 	
</div>	
HTML
			return;
		}
	}
	$self->_print_interface;
	return;
}

sub _upload_ref_file {
	my ($self) = @_;
	my $temp = BIGSdb::Utils::get_random();
	my $format = $self->{'cgi'}->param('ref_upload') =~ /.+(\.\w+)$/x ? $1 : q();
	my $filename = "$self->{'config'}->{'tmp_dir'}/$temp\_ref$format";
	my $buffer;
	open( my $fh, '>', $filename ) || $logger->error("Could not open $filename for writing.");
	my $fh2 = $self->{'cgi'}->upload('ref_upload');
	binmode $fh2;
	binmode $fh;
	read( $fh2, $buffer, MAX_UPLOAD_SIZE );
	print $fh $buffer;
	close $fh;
	return "$temp\_ref$format";
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
	my $qry;
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
	print <<"HTML";
<div class="box" id="queryform">
<p>Please select the required isolate ids and loci for comparison - use ctrl or shift to make multiple 
selections. In addition to selecting individual loci, you can choose to include all loci defined in schemes 
by selecting the appropriate scheme description. Alternatively, you can enter the accession number for an 
annotated reference genome and compare using the loci defined in that.</p>
HTML
	say $q->start_form;
	say q(<div class="scrollable">);
	$self->print_seqbin_isolate_fieldset(
		{ use_all => $use_all, selected_ids => $selected_ids, isolate_paste_list => 1 } );
	$self->print_isolates_locus_fieldset( { locus_paste_list => 1 } );
	$self->print_includes_fieldset(
		{ title => 'Include in identifiers', preselect => $self->{'system'}->{'labelfield'} } );
	$self->print_scheme_fieldset;
	say q(<div style="clear:both"></div>);
	$self->_print_reference_genome_fieldset;
	$self->_print_parameters_fieldset;
	$self->_print_distance_matrix_fieldset;
	$self->_print_alignment_fieldset;
	$self->_print_core_genome_fieldset;
	$self->print_sequence_filter_fieldset;
	$self->print_action_fieldset( { name => 'GenomeComparator' } );
	say $q->hidden($_) foreach qw (page name db);
	say q(</div>);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _print_reference_genome_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left; height:12em"><legend>Reference genome</legend>);
	say q(Enter accession number:<br />);
	say $q->textfield( -name => 'accession', -id => 'accession', -size => 10, -maxlength => 20 );
	say q( <a class="tooltip" title="Reference genome - Use of a reference genome will override any locus )
	  . q(or scheme settings."><span class="fa fa-info-circle"></span></a><br />);
	my $set_id = $self->get_set_id;
	my $set_annotation =
	  ( $set_id && $self->{'system'}->{"set_$set_id\_annotation"} )
	  ? $self->{'system'}->{"set_$set_id\_annotation"}
	  : '';

	if ( $self->{'system'}->{'annotation'} || $set_annotation ) {
		my @annotations = $self->{'system'}->{'annotation'} ? split /;/x, $self->{'system'}->{'annotation'} : ();
		my @set_annotations = $set_annotation ? split /;/x, $set_annotation : ();
		push @annotations, @set_annotations;
		my @names = ('');
		my %labels;
		$labels{''} = ' ';
		foreach (@annotations) {
			my ( $accession, $name ) = split /\|/x, $_;
			if ( $accession && $name ) {
				push @names, $accession;
				$labels{$accession} = $name;
			}
		}
		if (@names) {
			say q(or choose annotated genome:<br />);
			say $q->popup_menu(
				-name     => 'annotation',
				-id       => 'annotation',
				-values   => \@names,
				-labels   => \%labels,
				-onChange => 'enable_seqs()',
			);
		}
		say q(<br />);
	}
	say q(or upload Genbank/EMBL/FASTA file:<br />);
	say $q->filefield( -name => 'ref_upload', -id => 'ref_upload', -onChange => 'enable_seqs()' );
	say q( <a class="tooltip" title="Reference upload - File format is recognised by the extension in the )
	  . q(name.  Make sure your file has a standard extension, e.g. .gb, .embl, .fas.">)
	  . q(<span class="fa fa-info-circle"></span></a>);
	say q(</fieldset>);
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
	say q(<li><span class="warning">);
	say $q->checkbox( -name => 'tblastx', -id => 'tblastx', -label => 'Use TBLASTX' );
	say q[ <a class="tooltip" title="TBLASTX (analysis by reference genome only) - Compares the six-frame ]
	  . q[translation of your nucleotide query against the six-frame translation of the sequences in the ]
	  . q[sequence bin (sequences will be classed as identical if they result in the same translated sequence ]
	  . q[even if the nucleotide sequence is different).  This is SLOWER than BLASTN. Use with caution.">]
	  . q[<span class="fa fa-info-circle"></span></a></span></li><li>];
	say $q->checkbox(
		-name    => 'use_tagged',
		-id      => 'use_tagged',
		-label   => 'Use tagged designations if available',
		-checked => 1
	);
	say q( <a class="tooltip" title="Tagged desginations - Allele sequences will be extracted from the )
	  . q(definition database based on allele designation rather than by BLAST.  This should be much quicker."> )
	  . q(<span class="fa fa-info-circle"></span></a></li><li>);
	say $q->checkbox( -name => 'disable_html', -id => 'disable_html', -label => 'Disable HTML output' );
	say q( <a class="tooltip" title="Disable HTML - Select this option if you are analysing very large numbers )
	  . q(of loci which may cause your browser problems in rendering the output table.">)
	  . q(<span class="fa fa-info-circle"></span></a></li></ul></fieldset>);
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

sub _print_core_genome_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left;height:12em"><legend>Core genome analysis</legend><ul>);
	say q(<li><label for="core_threshold">Core threshold (%):</label>);
	say $q->popup_menu( -name => 'core_threshold', -id => 'core_threshold', -values => [ 80 .. 100 ], -default => 90 );
	say q( <a class="tooltip" title="Core threshold - Percentage of isolates that locus must be present )
	  . q(in to be considered part of the core genome."><span class="fa fa-info-circle"></span></a></li><li>);
	say $q->checkbox(
		-name     => 'calc_distances',
		-id       => 'calc_distances',
		-label    => 'Calculate mean distances',
		-onChange => 'enable_seqs()'
	);
	say q( <a class="tooltip" title="Mean distance - This requires performing alignments of sequences so will )
	  . q(take longer to perform."><span class="fa fa-info-circle"></span></a></li></ul></fieldset>);
	return;
}

sub _print_distance_matrix_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left;height:12em"><legend>Distance matrix calculation</legend>);
	say q(With incomplete loci:);
	say q(<ul><li>);
	my $labels = {
		exclude       => 'Completely exclude from analysis',
		include_as_T  => 'Treat as distinct allele',
		pairwise_same => 'Ignore in pairwise comparison'
	};
	say $q->radio_group(
		-name      => 'truncated',
		-values    => [qw (exclude include_as_T pairwise_same)],
		-labels    => $labels,
		-default   => 'pairwise_same',
		-linebreak => 'true'
	);
	say q(</li><li style="border-top:1px dashed #999;padding-top:0.2em">);
	say $q->checkbox(
		-name    => 'exclude_paralogous',
		-id      => 'exclude_paralogous',
		-label   => 'Exclude paralogous loci',
		-checked => 'checked'
	);
	say q(</li><li>);
	$labels = { all => 'paralogous in all isolates', any => 'paralogous in any isolate' };
	say $q->radio_group(
		-name      => 'paralogous_options',
		-id        => 'paralogous_options',
		-values    => [qw(all any)],
		-labels    => $labels,
		-linebreak => 'true'
	);
	say q(</li></ul></fieldset>);
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
	$self->_run_comparison(
		{ by_reference => 0, job_id => $job_id, ids => $ids, cds => $loci, worksheet => $worksheet } );
	$self->delete_temp_files("$job_id*");
	return;
}

sub _generate_splits {
	my ( $self, $job_id, $values, $ignore_loci_ref, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Generating distance matrix' } );
	my $dismat = $self->_generate_distance_matrix( $values, $ignore_loci_ref, $options );
	my $nexus_file = $self->_make_nexus_file( $job_id, $dismat, $options );
	$self->_add_distance_matrix_worksheet($dismat);
	$self->{'jobManager'}->update_job_output(
		$job_id,
		{
			filename    => $nexus_file,
			description => '20_Distance matrix (Nexus format)|Suitable for loading in to '
			  . '<a href="http://www.splitstree.org">SplitsTree</a>. Distances between taxa are '
			  . 'calculated as the number of loci with different allele sequences'
		}
	);
	return if ( keys %$values ) > MAX_SPLITS_TAXA;
	$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Generating NeighborNet' } );
	my $splits_img = "$job_id.png";
	$self->_run_splitstree( "$self->{'config'}->{'tmp_dir'}/$nexus_file",
		"$self->{'config'}->{'tmp_dir'}/$splits_img", 'PNG' );

	if ( -e "$self->{'config'}->{'tmp_dir'}/$splits_img" ) {
		$self->{'jobManager'}->update_job_output( $job_id,
			{ filename => $splits_img, description => '25_Splits graph (Neighbour-net; PNG format)' } );
	}
	$splits_img = "$job_id.svg";
	$self->_run_splitstree( "$self->{'config'}->{'tmp_dir'}/$nexus_file",
		"$self->{'config'}->{'tmp_dir'}/$splits_img", 'SVG' );
	if ( -e "$self->{'config'}->{'tmp_dir'}/$splits_img" ) {
		$self->{'jobManager'}->update_job_output(
			$job_id,
			{
				filename    => $splits_img,
				description => '26_Splits graph (Neighbour-net; SVG format)|This can be edited in '
				  . '<a href="http://inkscape.org">Inkscape</a> or other vector graphics editors'
			}
		);
	}
	return;
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
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			my $field_value;
			if ( defined $metaset ) {
				$field_value = $self->{'datastore'}->get_metadata_value( $id, $metaset, $metafield );
			} else {
				$field_value = $include_data->{$field} // '';
			}
			$field_value =~ tr/[\(\):, ]/_/;
			$value .= '|' if !$first || !$options->{'no_id'};
			$first = 0;
			$value .= "$field_value";
		}
	}
	return $value;
}

sub _generate_distance_matrix {
	my ( $self, $values, $ignore_loci_ref, $options ) = @_;
	my @ids = sort { $a <=> $b } keys %$values;
	my %ignore_loci = map { $_ => 1 } @$ignore_loci_ref;
	my $dismat;
	foreach my $i ( 0 .. @ids - 1 ) {
		foreach my $j ( 0 .. $i ) {
			$dismat->{ $ids[$i] }->{ $ids[$j] } = 0;
			foreach my $locus ( keys %{ $values->{ $ids[$i] } } ) {
				next if $ignore_loci{$locus};
				if ( $values->{ $ids[$i] }->{$locus} ne $values->{ $ids[$j] }->{$locus} ) {
					if ( ( $options->{'truncated'} // '' ) eq 'pairwise_same' ) {
						if (   ( $values->{ $ids[$i] }->{$locus} eq 'I' && $values->{ $ids[$j] }->{$locus} eq 'X' )
							|| ( $values->{ $ids[$i] }->{$locus} eq 'X' && $values->{ $ids[$j] }->{$locus} eq 'I' )
							|| ( $values->{ $ids[$i] }->{$locus} ne 'I' && $values->{ $ids[$j] }->{$locus} ne 'I' ) )
						{
							$dismat->{ $ids[$i] }->{ $ids[$j] }++;
						}
					} else {
						$dismat->{ $ids[$i] }->{ $ids[$j] }++;
					}
				}
			}
		}
	}
	return $dismat;
}

sub _run_splitstree {
	my ( $self, $nexus_file, $output_file, $format ) = @_;
	if ( $self->{'config'}->{'splitstree_path'} && -x $self->{'config'}->{'splitstree_path'} ) {
		system( $self->{'config'}->{'splitstree_path'},
			'+g', 'false', '-S', 'true', '-x',
			"EXECUTE FILE=$nexus_file;EXPORTGRAPHICS format=$format file=$output_file REPLACE=yes;QUIT" );
	}
	return;
}

sub _make_nexus_file {
	my ( $self, $job_id, $dismat, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $timestamp = scalar localtime;
	my @ids = sort { $a <=> $b } keys %$dismat;
	my %labels;
	foreach my $id (@ids) {
		if ( $id == 0 ) {
			$labels{$id} = 'ref';
		} else {
			$labels{$id} = $self->_get_identifier($id);
		}
	}
	my $num_taxa         = @ids;
	my $truncated_labels = {
		exclude       => 'completely excluded from analysis',
		include_as_T  => 'included as a special allele indistinguishable from other incomplete alleles',
		pairwise_same => 'ignored in pairwise comparisons unless locus is missing in one isolate'
	};
	my $truncated  = "[Incomplete loci are $truncated_labels->{$options->{'truncated'}}]";
	my $paralogous = '';
	if ( $options->{'by_reference'} ) {
		$paralogous =
		  '[Paralogous loci ' . ( $options->{'exclude_paralogous'} ? 'excluded from' : 'included in' ) . ' analysis]';
	}
	my $header = <<"NEXUS";
#NEXUS
[Distance matrix calculated by BIGSdb Genome Comparator ($timestamp)]
[Jolley & Maiden 2010 BMC Bioinformatics 11:595]
$truncated
$paralogous

BEGIN taxa;
   DIMENSIONS ntax = $num_taxa;	

END;

BEGIN distances;
   DIMENSIONS ntax = $num_taxa;
   FORMAT
      triangle=LOWER
      diagonal
      labels
      missing=?
   ;
MATRIX
NEXUS
	open( my $nexus_fh, '>', "$self->{'config'}->{'tmp_dir'}/$job_id.nex" )
	  || $logger->error("Can't open $job_id.nex for writing");
	print $nexus_fh $header;
	foreach my $i ( 0 .. @ids - 1 ) {
		print $nexus_fh $labels{ $ids[$i] };
		print $nexus_fh "\t" . $dismat->{ $ids[$i] }->{ $ids[$_] } foreach ( 0 .. $i );
		print $nexus_fh "\n";
	}
	print $nexus_fh "   ;\nEND;\n";
	close $nexus_fh;
	return "$job_id.nex";
}

sub _add_distance_matrix_worksheet {
	my ( $self, $dismat ) = @_;
	my %labels;
	my @ids = sort { $a <=> $b } keys %$dismat;
	foreach my $id (@ids) {
		if ( $id == 0 ) {
			$labels{$id} = 'ref';
		} else {
			$labels{$id} = $self->_get_identifier($id);
		}
	}
	my $worksheet = $self->{'workbook'}->add_worksheet('distance matrix');
	my $max       = $self->_get_max_from_dismat($dismat);
	my $col       = 1;
	foreach my $i ( 0 .. @ids - 1 ) {
		$worksheet->write( 0, $col, $labels{ $ids[$i] } );
		$col++;
	}
	my $row = 1;
	$col = 0;
	foreach my $i ( 0 .. @ids - 1 ) {
		$worksheet->write( $row, $col, $labels{ $ids[$i] } );
		foreach my $j ( 0 .. $i ) {
			$col++;
			my $value = $dismat->{ $ids[$i] }->{ $ids[$j] };
			if ( !$self->{'excel_format'}->{"d$value"} ) {
				my $excel_style = BIGSdb::Utils::get_heatmap_colour_style( $value, $max, { excel => 1 } );
				$self->{'excel_format'}->{"d$value"} = $self->{'workbook'}->add_format(%$excel_style);
			}
			$worksheet->write( $row, $col, $dismat->{ $ids[$i] }->{ $ids[$j] }, $self->{'excel_format'}->{"d$value"} );
		}
		$col = 0;
		$row++;
	}
	$worksheet->freeze_panes( 1, 1 );
	return;
}

sub _get_max_from_dismat {
	my ( $self, $dismat ) = @_;
	my $max = 0;
	my @ids = sort { $a <=> $b } keys %$dismat;
	foreach my $i ( 0 .. @ids - 1 ) {
		foreach my $j ( 0 .. $i ) {
			my $value = $dismat->{ $ids[$i] }->{ $ids[$j] };
			$max = $value if $value > $max;
		}
	}
	return $max;
}

sub _analyse_by_reference {
	my ( $self, $data ) = @_;
	my ( $job_id, $accession, $seq_obj, $ids, $worksheet ) = @{$data}{qw(job_id accession seq_obj ids worksheet)};
	my @cds;
	foreach ( $seq_obj->get_SeqFeatures ) {
		push @cds, $_ if $_->primary_tag eq 'CDS';
	}
	$self->{'html_buffer'} = q(<h3>Analysis by reference genome</h3>);
	my %att;
	eval {
		%att = (
			accession   => $accession,
			version     => $seq_obj->seq_version,
			type        => $seq_obj->alphabet,
			length      => $seq_obj->length,
			description => $seq_obj->description,
			cds         => scalar @cds,
		);
	};
	if ($@) {
		throw BIGSdb::PluginException('Invalid data in reference genome.');
	}
	my %abb = ( cds => 'coding regions' );
	$self->{'html_buffer'} .= q(<table class="resultstable">);
	my $td = 1;
	$self->{'file_buffer'} = qq(Analysis by reference genome\n\nTime: ) . ( localtime(time) ) . qq(\n\n);
	foreach (qw (accession version type length description cds)) {
		if ( $att{$_} ) {
			$self->{'html_buffer'} .=
			  qq(<tr class="td$td"><th>) . ( $abb{$_} || $_ ) . qq(</th><td style="text-align:left">$att{$_}</td></tr>);
			$self->{'file_buffer'} .= ( $abb{$_} || $_ ) . ": $att{$_}\n";
			$td = $td == 1 ? 2 : 1;
		}
	}
	$self->{'html_buffer'} .= q(</table>);
	$self->{'jobManager'}->update_job_status( $job_id, { message_html => $self->{'html_buffer'} } );
	my $max_ref_loci =
	  BIGSdb::Utils::is_int( $self->{'system'}->{'genome_comparator_max_ref_loci'} )
	  ? $self->{'system'}->{'genome_comparator_max_ref_loci'}
	  : MAX_REF_LOCI;
	if ( @cds > $max_ref_loci ) {
		my $max_upload_size = MAX_UPLOAD_SIZE / ( 1024 * 1024 );
		my $cds_count = @cds;
		throw BIGSdb::PluginException( qq(Too many loci in reference genome - limit is set at $max_ref_loci. )
			  . qq(Your uploaded reference contains $cds_count loci.  Please note also that the uploaded )
			  . qq(reference is limited to $max_upload_size MB (larger uploads will be truncated).) );
	}
	$self->{'html_buffer'} .= "<h3>All loci</h3>\n";
	$self->{'file_buffer'} .= "\n\nAll loci\n--------\n\n";
	$self->{'html_buffer'} .=
	    q(<p>Each unique allele is defined a number starting at 1. Missing alleles are marked as )
	  . q(<span style="background:black; color:white; padding: 0 0.5em">'X'</span>. Incomplete alleles )
	  . q((located at end of contig) are marked as )
	  . q(<span style="background:green; color:white; padding: 0 0.5em">'I'</span>.</p>);
	$self->{'file_buffer'} .=
	    qq(Each unique allele is defined a number starting at 1. Missing alleles are marked as 'X'. \n)
	  . qq(Incomplete alleles (located at end of contig) are marked as 'I'.\n\n);
	$self->_print_isolate_header( 1, $ids, $worksheet );
	$self->_run_comparison(
		{ by_reference => 1, job_id => $job_id, ids => $ids, cds => \@cds, worksheet => $worksheet } );
	return;
}

sub _extract_cds_details {
	my ( $self, $cds, $seqs_total_ref ) = @_;
	my ( $locus_name, $length, $start, $desc );
	my @aliases;
	my $locus;
	foreach (qw (locus_tag gene gene_synonym old_locus_tag)) {
		my @values = $cds->has_tag($_) ? $cds->get_tag_values($_) : ();
		foreach my $value (@values) {
			if ($locus) {
				push @aliases, $value;
			} else {
				$locus = $value;
			}
		}
	}
	local $" = ' | ';
	$locus_name = $locus;
	$locus_name .= " | @aliases" if @aliases;
	return if $locus_name =~ /^Bio::PrimarySeq=HASH/x;    #Invalid entry in reference file.
	my $seq;
	try {
		$seq = $cds->seq->seq;
	}
	catch Bio::Root::Exception with {
		my $err = shift;
		if ( $err =~ /MSG:([^\.]*\.)/x ) {
			throw BIGSdb::PluginException("Invalid data in annotation: $1");
		} else {
			$logger->error($err);
			throw BIGSdb::PluginException('Invalid data in annotation.');
		}
	};
	return if !$seq;
	$$seqs_total_ref++;
	my @tags;
	try {
		push @tags, $_ foreach ( $cds->each_tag_value('product') );
	}
	catch Bio::Root::Exception with {
		push @tags, 'no product';
	};
	$start = $cds->start;
	local $" = '; ';
	$desc = "@tags";
	return ( $locus_name, \$seq, $start, $desc );
}

sub _run_comparison {
	my ( $self, $args ) = @_;
	my ( $by_reference, $job_id, $ids, $cds, $worksheet ) = @{$args}{qw(by_reference job_id ids cds worksheet)};
	my ( $progress, $seqs_total, $td, $order_count ) = ( 0, 0, 1, 1 );
	my $params      = $self->{'params'};
	my $total       = @$cds;
	my $close_table = '</table></div>';
	my ( $locus_class, $presence, $order, $values, $match_count, $word_size, $program );
	my $job_file         = "$self->{'config'}->{'tmp_dir'}/$job_id.txt";
	my $align_file       = "$self->{'config'}->{'tmp_dir'}/$job_id\.align";
	my $align_stats_file = "$self->{'config'}->{'tmp_dir'}/$job_id\.align_stats";
	my $xmfa_file        = "$self->{'config'}->{'tmp_dir'}/$job_id.xmfa";
	my $core_xmfa_file   = "$self->{'config'}->{'tmp_dir'}/$job_id\_core.xmfa";
	my $prefix           = BIGSdb::Utils::get_random();
	my %isolate_FASTA;

	if ( $by_reference && $params->{'tblastx'} ) {
		$program   = 'tblastx';
		$word_size = 3;
	} else {
		$program = 'blastn';
		$word_size = $params->{'word_size'} =~ /^(\d+)$/x ? $1 : 15;
	}
	my $loci;
	my $row          = 0;
	my $num_isolates = @$ids;
	$num_isolates++ if $by_reference;    #Need to include the reference genome
	foreach my $cds (@$cds) {
		next if $self->{'exit'};
		$row++;
		my %seqs;
		my $seq_ref;
		my ( $locus_name, $locus_info, $length, $start, $desc, $ref_seq_file );
		if ($by_reference) {
			my $continue = 1;
			( $locus_name, $seq_ref, $start, $desc ) = $self->_extract_cds_details( $cds, \$seqs_total );
			next if ref $seq_ref ne 'SCALAR';
			$values->{'0'}->{$locus_name} = 1;
			$length = length $$seq_ref;
			$length = int( $length / 3 ) if $params->{'tblastx'};
			$ref_seq_file = $self->_create_reference_FASTA_file( $seq_ref, $prefix );
			$loci->{$locus_name}->{'length'} = $length;
			$loci->{$locus_name}->{'start'}  = $start;
		} else {
			$ref_seq_file                    = $self->_create_locus_FASTA_db( $cds, $job_id );
			$locus_name                      = $cds;
			$locus_info                      = $self->{'datastore'}->get_locus_info($cds);
			$loci->{$locus_name}->{'start'}  = $locus_info->{'genome_position'};
			$loci->{$locus_name}->{'length'} = $locus_info->{'length'};
		}
		$order->{$locus_name} = $order_count;
		$order_count++;
		my %status       = ( all_exact => 1, all_missing => 1, exact_except_ref => 1, truncated => 0 );
		my $first        = 1;
		my $previous_seq = '';
		my ( $cleaned_locus_name, $text_locus_name );
		if ($by_reference) {
			$cleaned_locus_name = $locus_name;
			$text_locus_name    = $locus_name;
		} else {
			$cleaned_locus_name = $self->clean_locus($locus_name);
			$text_locus_name = $self->clean_locus( $locus_name, { text_output => 1 } );
		}
		$self->{'html_buffer'} .= "<tr class=\"td$td\"><td>$cleaned_locus_name</td>";
		$self->{'file_buffer'} .= $text_locus_name;
		my $col = 0;
		$worksheet->write( $row, $col, $text_locus_name, $self->{'excel_format'}->{'locus'} );
		$self->{'col_max_width'}->{$col} = length($text_locus_name)
		  if length($text_locus_name) > ( $self->{'col_max_width'}->{$col} // 0 );
		my %allele_seqs;
		my $colour = 0;
		my %value_colour;

		if ($by_reference) {
			my @locus_desc = ( $desc, $length, $start );
			foreach my $locus_value (@locus_desc) {
				$self->{'html_buffer'} .= "<td>$locus_value</td>";
				$self->{'file_buffer'} .= "\t$locus_value";
				$col++;
				$worksheet->write( $row, $col, $locus_value, $self->{'excel_format'}->{'locus'} );
				$self->{'col_max_width'}->{$col} = length($locus_value)
				  if length($locus_value) > ( $self->{'col_max_width'}->{$col} // 0 );
			}
			$allele_seqs{$$seq_ref} = 1;
			$col++;
			$colour++;
			$value_colour{1} = $colour;
			my $style = BIGSdb::Utils::get_heatmap_colour_style( $value_colour{1}, $num_isolates );
			$self->{'html_buffer'} .= "<td style=\"$style\">1</td>";
			$self->{'file_buffer'} .= "\t1";

			if ( !$self->{'excel_format'}->{$colour} ) {
				my $excel_style =
				  BIGSdb::Utils::get_heatmap_colour_style( $value_colour{1}, $num_isolates, { excel => 1 } );
				$self->{'excel_format'}->{$colour} = $self->{'workbook'}->add_format(%$excel_style);
			}
			$worksheet->write( $row, $col, 1, $self->{'excel_format'}->{$colour} );
		}
		my $allele = $by_reference ? 1 : 0;
		$self->{'jobManager'}->update_job_status( $job_id, { stage => "Analysing locus: $locus_name" } );
		foreach my $id (@$ids) {
			next if $self->{'exit'};
			$col++;
			$id = $1 if $id =~ /(\d*)/x;    #avoid taint check
			if ( !-e "$self->{'config'}->{'secure_tmp_dir'}/$prefix\_isolate_$id.txt" ) {
				if ($by_reference) {
					$isolate_FASTA{$id} = $self->_create_isolate_FASTA_db( $id, $prefix );
				} else {
					$isolate_FASTA{$id} = $self->_create_isolate_FASTA( $id, $prefix );
				}
			}
			my $out_file = "$self->{'config'}->{'secure_tmp_dir'}/$prefix\_isolate_$id\_outfile.txt";
			my ( $match, $value, $extracted_seq );
			if ( !$by_reference ) {
				( $match, $value, $extracted_seq ) = $self->_scan_by_locus(
					$id, $cds,
					\%seqs,
					\%allele_seqs,
					{
						word_size         => $word_size,
						out_file          => $out_file,
						ref_seq_file      => $ref_seq_file,
						isolate_fasta_ref => \%isolate_FASTA
					}
				);
			} else {
				$self->_blast(
					{
						word_size  => $word_size,
						fasta_file => $isolate_FASTA{$id},
						in_file    => $ref_seq_file,
						out_file   => $out_file,
						program    => $program
					}
				);
				$match = $self->_parse_blast_ref( $seq_ref, $out_file );
			}
			$match_count->{$id}->{$locus_name} = $match->{'good_matches'} // 0;
			if ( ref $match eq 'HASH' && ( $match->{'identity'} || $match->{'allele'} ) ) {
				$status{'all_missing'} = 0;
				if ($by_reference) {
					if ( $match->{'identity'} == 100 && $match->{'alignment'} >= $length ) {
						$status{'exact_except_ref'} = 0;
					} else {
						$status{'all_exact'} = 0;
					}
				}
				if ( !$match->{'exact'} && $match->{'predicted_start'} && $match->{'predicted_end'} ) {
					my $seqbin_length =
					  $self->{'datastore'}->run_query( 'SELECT length(sequence) FROM sequence_bin where id=?',
						$match->{'seqbin_id'}, { cache => 'GenomeComparator::run_comparison_seqbin_length' } );
					foreach (qw (predicted_start predicted_end)) {
						if ( $match->{$_} < 1 ) {
							( $match->{$_}, $status{'truncated'}, $value ) = ( 1, 1, 'I' );
						} elsif ( $match->{$_} > $seqbin_length ) {
							( $match->{$_}, $status{'truncated'}, $value ) = ( $seqbin_length, 1, 'I' );
						}
					}
				}
				if ( !$extracted_seq ) {
					$extracted_seq = $self->_extract_sequence($match);
					$seqs{$id} = $extracted_seq;
				}
				if ($by_reference) {
					if ($first) {
						$previous_seq = $extracted_seq;
					} else {
						if ( $extracted_seq ne $previous_seq ) {
							$status{'exact_except_ref'} = 0;
						}
					}
				}
			} else {
				( $status{'all_exact'}, $status{'exact_except_ref'} ) = ( 0, 0 );
			}
			if ( !$value ) {    #Don't use '!defined $value' because allele '0' means missing.
				if ($extracted_seq) {
					if ( $allele_seqs{$extracted_seq} ) {
						$value = $allele_seqs{$extracted_seq};
					} else {
						$allele++;
						$value = $by_reference ? $allele : "new#$allele";
						$allele_seqs{$extracted_seq} = $value;
					}
				} else {
					$value = 'X';
				}
			}
			my $style;
			if ( $value eq 'I' ) {
				$style = 'background:green; color:white';
				$value_colour{'I'} = 'I';
				if ( !$self->{'excel_format'}->{'I'} ) {
					$self->{'excel_format'}->{'I'} = $self->{'workbook'}->add_format(
						bg_color     => 'green',
						color        => 'white',
						align        => 'center',
						border       => 1,
						border_color => 'white'
					);
				}
				$value_colour{$value} = 'I';
			} elsif ( $value eq 'X' ) {
				$style = 'background:black; color:white';
				$value_colour{'X'} = 'X';
				if ( !$self->{'excel_format'}->{'X'} ) {
					$self->{'excel_format'}->{'X'} = $self->{'workbook'}->add_format(
						bg_color     => 'black',
						color        => 'white',
						align        => 'center',
						border       => 1,
						border_color => 'white'
					);
				}
			} else {
				if ( !$value_colour{$value} ) {
					$colour++;
					$value_colour{$value} = $colour;
				}
				$style = BIGSdb::Utils::get_heatmap_colour_style( $value_colour{$value}, $num_isolates );
				if ( !$self->{'excel_format'}->{$colour} ) {
					my $excel_style =
					  BIGSdb::Utils::get_heatmap_colour_style( $value_colour{$value}, $num_isolates, { excel => 1 } );
					$self->{'excel_format'}->{$colour} = $self->{'workbook'}->add_format(%$excel_style);
				}
			}
			$presence->{$locus_name}++ if $value ne 'X';
			$self->{'style'}->{$locus_name}->{$value} = $style;
			$self->{'html_buffer'} .= "<td style=\"$style\">$value</td>";
			$self->{'file_buffer'} .= "\t$value";
			$worksheet->write( $row, $col, $value, $self->{'excel_format'}->{ $value_colour{$value} } );
			$first = 0;
			$values->{$id}->{$locus_name} = $value;
			$seqs{$id} //= undef;    #Ensure key exists even if sequence doesn't.
		}
		$self->{'datastore'}->finish_with_locus($locus_name);
		$td = $td == 1 ? 2 : 1;
		$self->{'html_buffer'} .= "</tr>\n";
		$self->{'file_buffer'} .= "\n";
		if ( !$by_reference ) {
			my @values = grep { defined } values %seqs;
			$status{'all_exact'} = 0 if ( uniq @values ) > 1;
		}
		my $variable_locus = 0;
		foreach my $class (qw (all_exact all_missing exact_except_ref truncated varying)) {
			next if !$status{$class} && $class ne 'varying';
			next if $class eq 'exact_except_ref' && !$by_reference;
			$locus_class->{$class}->{$locus_name}->{'length'} = length $$seq_ref if $by_reference;
			$locus_class->{$class}->{$locus_name}->{'desc'}   = $desc;
			$locus_class->{$class}->{$locus_name}->{'start'}  = $start;
			$variable_locus = 1 if $class eq 'varying';
			last;
		}
		if ( $params->{'align'} && ( $variable_locus || $params->{'align_all'} ) ) {
			$seqs{'ref'} = $$seq_ref if $by_reference;
			my $core_threshold =
			  BIGSdb::Utils::is_int( $params->{'core_threshold'} ) ? $params->{'core_threshold'} : 100;
			my $core_locus = ( $presence->{$locus_name} * 100 / @$ids ) >= $core_threshold ? 1 : 0;
			$self->_align(
				{
					job_id           => $job_id,
					locus            => $locus_name,
					seqs             => \%seqs,
					align_file       => $align_file,
					align_stats_file => $align_stats_file,
					xmfa_file        => $xmfa_file,
					core_xmfa_file   => $core_xmfa_file,
					locus            => $locus_name,
					core_locus       => $core_locus
				}
			);
		}
		%seqs = ();
		$progress++;
		my $complete         = int( 100 * $progress / $total );
		my $max_display_taxa = MAX_DISPLAY_TAXA;
		if ( @$ids > $max_display_taxa || $params->{'disable_html'} ) {
			my $message =
			  $params->{'disable_html'}
			  ? '<p>Dynamically updated output disabled.</p>'
			  : "<p>Dynamically updated output disabled as >$max_display_taxa taxa selected.</p>";
			$self->{'jobManager'}
			  ->update_job_status( $job_id, { percent_complete => $complete, message_html => $message } );
		} else {
			my $msg = $self->{'html_buffer'} . $close_table;
			$self->{'jobManager'}
			  ->update_job_status( $job_id, { percent_complete => $complete, message_html => $msg } );
			undef $msg;
		}
		$self->delete_temp_files("$job_id*fastafile*\.txt*") if !$by_reference;
		$self->_touch_temp_files("$prefix*");    #Prevent removal of isolate FASTA db by cleanup script
		$self->{'db'}->commit;                   #prevent idle in transaction table locks
	}
	$self->{'html_buffer'} .= $close_table;
	if ( $self->{'exit'} ) {
		my $job = $self->{'jobManager'}->get_job_status($job_id);
		if ( $job->{'status'} && $job->{'status'} ne 'cancelled' ) {
			$self->{'jobManager'}->update_job_status( $job_id, { status => 'terminated' } );
		}
		$self->delete_temp_files("$prefix*");
		return;
	}
	foreach my $col ( keys %{ $self->{'col_max_width'} } ) {
		$worksheet->set_column( $col, $col, $self->_excel_col_width( $self->{'col_max_width'}->{$col} ) );
	}
	$self->_print_reports(
		$ids, $loci,
		{
			job_id       => $job_id,
			job_file     => $job_file,
			by_reference => $by_reference,
			locus_class  => $locus_class,
			values       => $values,
			seqs_total   => $seqs_total,
			ids          => $ids,
			presence     => $presence,
			match_count  => $match_count,
			order        => $order,
			set_id       => $params->{'set_id'},
		}
	);
	$self->delete_temp_files("$prefix*");
	$self->_touch_output_files("$job_id*");    #Prevents premature deletion by cleanup scripts
	return;
}

sub _touch_output_files {
	my ( $self, $wildcard ) = @_;
	my @files = glob("$self->{'config'}->{'tmp_dir'}/$wildcard");
	foreach (@files) { utime( time(), time(), $1 ) if /^(.*BIGSdb.*)$/x }
	return;
}

sub _touch_temp_files {
	my ( $self, $wildcard ) = @_;
	my @files = glob("$self->{'config'}->{'secure_tmp_dir'}/$wildcard");
	foreach (@files) { utime( time(), time(), $1 ) if /^(.*BIGSdb.*)$/x }
	return;
}

sub _print_reports {
	my ( $self, $ids, $loci, $args ) = @_;
	my $params = $self->{'params'};
	my ( $job_id, $values, $locus_class, $job_file, $match_count ) =
	  @{$args}{qw (job_id values locus_class job_file match_count )};
	my $align_file       = "$self->{'config'}->{'tmp_dir'}/$job_id\.align";
	my $align_stats_file = "$self->{'config'}->{'tmp_dir'}/$job_id\.align_stats";
	open( my $job_fh, '>', $job_file ) || $logger->error("Can't open $job_file for writing");
	print $job_fh $self->{'file_buffer'};
	close $job_fh;
	return if $self->{'exit'};
	my %table_args =
	  ( by_reference => $args->{'by_reference'}, ids => $ids, job_filename => $job_file, values => $values );
	$self->_print_variable_loci( { loci => $locus_class->{'varying'}, %table_args } );
	$self->_print_missing_in_all( { loci => $locus_class->{'all_missing'}, %table_args } );
	$self->_print_exact_matches( { loci => $locus_class->{'all_exact'}, %table_args } );

	if ( $args->{'by_reference'} ) {
		$self->_print_exact_except_ref( { loci => $locus_class->{'exact_except_ref'}, %table_args } );
	}
	$self->_print_truncated_loci(
		{ loci => $locus_class->{'truncated'}, truncated_param => $params->{'truncated'}, %table_args } );
	if ( !$args->{'seqs_total'} && $args->{'by_reference'} ) {
		$self->{'html_buffer'} .= "<p class=\"statusbad\">No sequences were extracted from reference file.</p>\n";
		$self->{'jobManager'}->update_job_status( $job_id, { message_html => $self->{'html_buffer'} } );
		return;
	} else {
		$self->_identify_strains( $ids, $job_file, $loci, $values );
		$self->{'html_buffer'} = '' if @$ids > MAX_DISPLAY_TAXA || $params->{'disable_html'};
		$self->{'jobManager'}->update_job_status( $job_id, { message_html => $self->{'html_buffer'} } );
	}
	my @paralogous;
	if ( $args->{'by_reference'} ) {
		@paralogous = $self->_print_paralogous_loci( $ids, $job_file, $loci, $match_count );
		$self->{'html_buffer'} = '' if @$ids > MAX_DISPLAY_TAXA || $params->{'disable_html'};
	}
	$self->{'jobManager'}->update_job_status( $job_id, { message_html => $self->{'html_buffer'} } );
	$self->{'jobManager'}
	  ->update_job_output( $job_id, { filename => "$job_id.txt", description => '01_Text output file' } );
	my @ignore_loci;
	push @ignore_loci, keys %{ $locus_class->{'truncated'} } if ( $params->{'truncated'} // '' ) eq 'exclude';
	push @ignore_loci, @paralogous if $params->{'exclude_paralogous'};
	$self->_generate_splits(
		$job_id, $values,
		\@ignore_loci,
		{
			truncated          => $params->{'truncated'},
			exclude_paralogous => $params->{'exclude_paralogous'},
			by_reference       => $args->{'by_reference'}
		}
	);
	if ( $params->{'align'} && ( @$ids > 1 || ( @$ids == 1 && $args->{'by_reference'} ) ) ) {
		$self->{'jobManager'}->update_job_output( $job_id,
			{ filename => "$job_id\.align", description => '30_Alignments', compress => 1 } )
		  if -e $align_file && !-z $align_file;
		$self->{'jobManager'}->update_job_output( $job_id,
			{ filename => "$job_id\.align_stats", description => '31_Alignment stats', compress => 1 } )
		  if -e $align_stats_file && !-z $align_stats_file;
		if ( -e "$self->{'config'}->{'tmp_dir'}/$job_id\.xmfa" ) {
			$self->{'jobManager'}->update_job_output(
				$job_id,
				{
					filename      => "$job_id.xmfa",
					description   => '35_Extracted sequences (XMFA format)',
					compress      => 1,
					keep_original => 1
				}
			);
			try {
				$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Converting XMFA to FASTA' } );
				my $fasta_file =
				  BIGSdb::Utils::xmfa2fasta( "$self->{'config'}->{'tmp_dir'}/$job_id\.xmfa", { integer_ids => 1 } );
				if ( -e $fasta_file ) {
					$self->{'jobManager'}->update_job_output(
						$job_id,
						{
							filename    => "$job_id.fas",
							description => '36_Concatenated aligned sequences (FASTA format)',
							compress    => 1
						}
					);
				}
			}
			catch BIGSdb::CannotOpenFileException with {
				$logger->error('Cannot create FASTA file from XMFA.');
			};
		}
		if ( -e "$self->{'config'}->{'tmp_dir'}/$job_id\_core.xmfa" ) {
			$self->{'jobManager'}->update_job_output(
				$job_id,
				{
					filename      => "$job_id\_core.xmfa",
					description   => '37_Extracted core sequences (XMFA format)',
					compress      => 1,
					keep_original => 1
				}
			);
			try {
				$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Converting core XMFA to FASTA' } );
				my $fasta_file =
				  BIGSdb::Utils::xmfa2fasta( "$self->{'config'}->{'tmp_dir'}/$job_id\_core.xmfa",
					{ integer_ids => 1 } );
				if ( -e $fasta_file ) {
					$self->{'jobManager'}->update_job_output(
						$job_id,
						{
							filename    => "$job_id\_core.fas",
							description => '38_Concatenated core aligned sequences (FASTA format)',
							compress    => 1
						}
					);
				}
			}
			catch BIGSdb::CannotOpenFileException with {
				$logger->error('Cannot create core FASTA file from XMFA.');
			};
		}
	}
	$self->_core_analysis( $loci, $args );
	$self->_report_parameters( $ids, $loci, $args );
	$self->{'workbook'}->close;
	my $excel_file = "$self->{'config'}->{'tmp_dir'}/$job_id.xlsx";
	open( my $excel_fh, '>', $excel_file ) || $logger->error("Can't open $excel_file for writing.");
	binmode $excel_fh;
	print $excel_fh ${ $self->{'excel'} };
	close $excel_fh;
	$self->{'jobManager'}
	  ->update_job_output( $job_id, { filename => "$job_id.xlsx", description => '02_Excel format' } )
	  if -e $excel_file;
	return;
}

sub _report_parameters {
	my ( $self, $ids, $loci, $args ) = @_;
	my $worksheet = $self->{'workbook'}->add_worksheet('parameters');
	my $row       = 0;
	my %excel_format;
	$excel_format{'heading'} = $self->{'workbook'}->add_format( size  => 14,      align => 'left', bold => 1 );
	$excel_format{'key'}     = $self->{'workbook'}->add_format( align => 'right', bold  => 1 );
	$excel_format{'value'}   = $self->{'workbook'}->add_format( align => 'left' );
	my $job = $self->{'jobManager'}->get_job( $args->{'job_id'} );
	my $total_time;
	eval 'use Time::Duration';    ## no critic (ProhibitStringyEval)

	if ($@) {
		$total_time = int( $job->{'elapsed'} ) . ' s';
	} else {
		$total_time = duration( $job->{'elapsed'} );
		$total_time = '<1 second' if $total_time eq 'just now';
	}
	( my $submit_time = $job->{'submit_time'} ) =~ s/\..*?$//x;
	( my $start_time  = $job->{'start_time'} )  =~ s/\..*?$//x;
	( my $stop_time   = $job->{'query_time'} )  =~ s/\..*?$//x;

	#Job attributes
	my @parameters = (
		{ section => 'Job attributes', nospace => 1 },
		{ label   => 'Plugin version', value   => $self->get_attributes->{'version'} },
		{ label   => 'Job',            value   => $args->{'job_id'} },
		{ label   => 'Database',       value   => $job->{'dbase_config'} },
		{ label   => 'Submit time',    value   => $submit_time },
		{ label   => 'Start time',     value   => $start_time },
		{ label   => 'Stop time',      value   => $stop_time },
		{ label   => 'Total time',     value   => $total_time },
		{ label   => 'Isolates',       value   => scalar @$ids },
		{
			label => 'Analysis type',
			value => $args->{'by_reference'} ? 'against reference genome' : 'against defined loci'
		},
	);
	my $params = $self->{'params'};
	if ( $args->{'by_reference'} ) {
		push @parameters,
		  {
			label => 'Accession',
			value => $params->{'annotation'} || $params->{'accession'} || $params->{'upload_filename'}
		  };
	} else {
		push @parameters, { label => 'Loci', value => scalar keys %$loci };
	}

	#Parameters/options
	push @parameters,
	  (
		{ section => 'Parameters' },
		{ label   => 'Min % identity', value => $params->{'identity'} },
		{ label   => 'Min % alignment', value => $params->{'alignment'} },
		{ label   => 'BLASTN word size', value => $params->{'word_size'} },
		{ label   => 'Use TBLASTX', value => $params->{'tblastx'} ? 'yes' : 'no' }
	  );
	if ( !$args->{'by_reference'} ) {
		push @parameters, ( { label => 'Use tagged designations', value => $params->{'use_tagged'} ? 'yes' : 'no' } );
	}

	#Distance matrix
	my $labels = {
		exclude       => 'Completely exclude from analysis',
		include_as_T  => 'Treat as distinct allele',
		pairwise_same => 'Ignore in pairwise comparison'
	};
	push @parameters,
	  (
		{ section => 'Distance matrix calculation' },
		{ label   => 'Incomplete loci', value => lc( $labels->{ $params->{'truncated'} } ) }
	  );
	if ( $args->{'by_reference'} ) {
		push @parameters,
		  { label => 'Exclude paralogous loci', value => $params->{'exclude_paralogous'} ? 'yes' : 'no' };
		if ( $params->{'exclude_paralogous'} ) {
			$labels = { all => 'paralogous in all isolates', any => 'paralogous in any isolate' };
			push @parameters,
			  { label => 'Paralogous locus definitions', value => $labels->{ $params->{'paralogous_options'} } };
		}
	}

	#Alignments
	push @parameters,
	  ( { section => 'Alignments' }, { label => 'Produce alignments', value => $params->{'align'} ? 'yes' : 'no' } );
	if ( $params->{'align'} ) {
		push @parameters,
		  (
			{ label => 'Align all', value => $params->{'align_all'} ? 'yes' : 'no' },
			{ label => 'Aligner', value => $params->{'aligner'} }
		  );
	}

	#Core genome analysis
	push @parameters,
	  (
		{ section => 'Core genome analysis' },
		{ label   => 'Core threshold %', value => $params->{'core_threshold'} },
		{ label   => 'Calculate mean distances', value => $params->{'calc_distances'} ? 'yes' : 'no' }
	  );
	my $longest_length = 0;
	foreach my $parameter (@parameters) {
		if ( $parameter->{'section'} ) {
			$row++ if !$parameter->{'nospace'};
			$worksheet->write( $row, 0, $parameter->{'section'}, $excel_format{'heading'} );
		} else {
			$worksheet->write( $row, 0, $parameter->{'label'} . ':', $excel_format{'key'} );
			$worksheet->write( $row, 1, $parameter->{'value'},       $excel_format{'value'} );
		}
		$row++;
		next if !$parameter->{'label'};
		$longest_length = length( $parameter->{'label'} ) if length( $parameter->{'label'} ) > $longest_length;
	}
	$worksheet->set_column( 0, 0, $self->_excel_col_width($longest_length) );
	return;
}

sub _excel_col_width {
	my ( $self, $length ) = @_;
	my $width = int( 0.9 * ($length) + 2 );
	$width = 50 if $width > 50;
	$width = 5  if $width < 5;
	return $width;
}

sub _core_analysis {
	my ( $self, $loci, $args ) = @_;
	return if ref $loci ne 'HASH';
	my $params     = $self->{'params'};
	my $core_count = 0;
	my @core_loci;
	my $isolate_count = @{ $args->{'ids'} };
	my $locus_count   = keys %$loci;
	my $order         = $args->{'order'};
	my $out_file      = "$self->{'config'}->{'tmp_dir'}/$args->{'job_id'}\_core.txt";
	open( my $fh, '>', $out_file ) || $logger->error("Can't open $out_file for writing");
	say $fh 'Core genome analysis';
	say $fh "--------------------\n";
	say $fh 'Parameters:';
	say $fh "Min % identity: $params->{'identity'}";
	say $fh "Min % alignment: $params->{'alignment'}";
	say $fh "BLASTN word size: $params->{'word_size'}";
	my $threshold =
	  ( $params->{'core_threshold'} && BIGSdb::Utils::is_int( $params->{'core_threshold'} ) )
	  ? $params->{'core_threshold'}
	  : 90;
	say $fh "Core threshold (percentage of isolates that contain locus): $threshold\%\n";
	print $fh "Locus\tSequence length\tGenome position\tIsolate frequency\tIsolate percentage\tCore";
	print $fh "\tMean distance" if $params->{'calc_distances'};
	print $fh "\n";
	my %range;

	foreach my $locus ( sort { $order->{$a} <=> $order->{$b} } keys %$loci ) {
		my $locus_name;
		if ( !$args->{'by_reference'} ) {
			$locus_name = $self->clean_locus( $locus, { text_output => 1 } );
		} else {
			$locus_name = $locus;
		}
		my $length = $loci->{$locus}->{'length'}   // '';
		my $pos    = $loci->{$locus}->{'start'}    // '';
		my $freq   = $args->{'presence'}->{$locus} // 0;
		my $percentage = BIGSdb::Utils::decimal_place( $freq * 100 / $isolate_count, 1 );
		my $core;
		if ( $percentage >= $threshold ) {
			$core = 'Y';
			push @core_loci, $locus;
		} else {
			$core = '-';
		}
		$core_count++ if $percentage >= $threshold;
		print $fh "$locus_name\t$length\t$pos\t$freq\t$percentage\t$core";
		print $fh "\t" . BIGSdb::Utils::decimal_place( ( $self->{'distances'}->{$locus} // 0 ), 3 )
		  if $params->{'calc_distances'};
		print $fh "\n";
		for ( my $upper_range = 5 ; $upper_range <= 100 ; $upper_range += 5 ) {
			$range{$upper_range}++ if $percentage >= ( $upper_range - 5 ) && $percentage < $upper_range;
		}
		$range{'all_isolates'}++ if $percentage == 100;
	}
	say $fh "\nCore loci: $core_count\n";
	say $fh "Present in % of isolates\tNumber of loci\tPercentage (%) of loci";
	my ( @labels, @values );
	for ( my $upper_range = 5 ; $upper_range <= 100 ; $upper_range += 5 ) {
		my $label      = ( $upper_range - 5 ) . " - <$upper_range";
		my $value      = $range{$upper_range} // 0;
		my $percentage = BIGSdb::Utils::decimal_place( $value * 100 / $locus_count, 1 );
		say $fh "$label\t$value\t$percentage";
		push @labels, $label;
		push @values, $value;
	}
	$range{'all_isolates'} //= 0;
	my $percentage = BIGSdb::Utils::decimal_place( $range{'all_isolates'} * 100 / $locus_count, 1 );
	say $fh "100\t$range{'all_isolates'}\t$percentage";
	push @labels, 100;
	push @values, $range{'all_isolates'};
	close $fh;
	$self->_core_mean_distance( $args, $out_file, \@core_loci, $loci ) if $params->{'calc_distances'};

	if ( -e $out_file ) {
		$self->{'jobManager'}->update_job_output( $args->{'job_id'},
			{ filename => "$args->{'job_id'}\_core.txt", description => '40_Locus presence frequency' } );
	}
	if ( $self->{'config'}->{'chartdirector'} ) {
		my $image_file = "$self->{'config'}->{'tmp_dir'}/$args->{'job_id'}\_core.png";
		BIGSdb::Charts::barchart(
			\@labels, \@values, $image_file, 'large',
			{ 'x-title'      => 'Present in % of isolates', 'y-title' => 'Number of loci' },
			{ no_transparent => 1 }
		);
		if ( -e $image_file ) {
			$self->{'jobManager'}->update_job_output(
				$args->{'job_id'},
				{
					filename    => "$args->{'job_id'}\_core.png",
					description => '41_Locus presence frequency chart (PNG format)'
				}
			);
		}
	}
	return;
}

sub _core_mean_distance {
	my ( $self, $args, $out_file, $core_loci, $loci ) = @_;
	return if !@$core_loci;
	my $file_buffer = "\nMean distances of core loci\n---------------------------\n\n";
	my $largest_distance = $self->_get_largest_distance( $core_loci, $loci );
	my ( @labels, @values );
	if ( !$largest_distance ) {
		$file_buffer .= "All loci are identical.\n";
	} else {
		my $increment;

		#Aim to have <50 points
		foreach (qw(0.0001 0.0002 0.0005 0.001 0.002 0.005 0.01 0.02)) {
			if ( ( $largest_distance / $_ ) <= 50 ) {
				$increment = $_;
				last;
			}
		}
		$increment //= 0.02;
		my %upper_range;
		foreach my $locus (@$core_loci) {
			my $range = 0;
			if ( $self->{'distances'}->{$locus} ) {
				my $distance = $self->{'distances'}->{$locus} =~ /^([\d\.]+)$/x ? $1 : 0;    #untaint
				do( $range += $increment ) until $range >= $distance;
			}
			$upper_range{$range}++;
		}
		$file_buffer .= "Mean distance*\tFrequency\tPercentage\n";
		$file_buffer .= "0\t"
		  . ( $upper_range{0} // 0 ) . "\t"
		  . BIGSdb::Utils::decimal_place( ( ( $upper_range{0} // 0 ) * 100 / @$core_loci ), 1 ) . "\n";
		my $range = 0;
		push @labels, 0;
		push @values, $upper_range{0} // 0;
		do {
			$range += $increment;
			$range = ( int( ( $range * 10000.0 ) + 0.5 ) / 10000.0 );    #Set float precision
			my $label = '>' . ( $range - $increment ) . " - $range";
			my $value = $upper_range{$range} // 0;
			push @labels, $label;
			push @values, $value;
			$file_buffer .=
			  "$label\t$value\t"
			  . BIGSdb::Utils::decimal_place( ( ( $upper_range{$range} // 0 ) * 100 / @$core_loci ), 1 ) . "\n";
		} until ( $range > $largest_distance );
		$file_buffer .=
		  "\n*Mean distance is the overall mean distance " . "calculated from a computed consensus sequence.\n";
	}
	open( my $fh, '>>', $out_file ) || $logger->error("Can't open $out_file for appending");
	say $fh $file_buffer;
	close $fh;
	if ( @labels && $self->{'config'}->{'chartdirector'} ) {
		my $image_file = "$self->{'config'}->{'tmp_dir'}/$args->{'job_id'}\_core2.png";
		BIGSdb::Charts::barchart(
			\@labels, \@values, $image_file, 'large',
			{ 'x-title'      => 'Overall mean distance', 'y-title' => 'Number of loci' },
			{ no_transparent => 1 }
		);
		if ( -e $image_file ) {
			$self->{'jobManager'}->update_job_output(
				$args->{'job_id'},
				{
					filename    => "$args->{'job_id'}\_core2.png",
					description => '42_Overall mean distance (from consensus sequence) '
					  . 'of core genome alleles (PNG format)'
				}
			);
		}
	}
	return;
}

sub _get_largest_distance {
	my ( $self, $core_loci, $loci ) = @_;
	my $largest = 0;
	foreach my $locus (@$core_loci) {
		$largest = $self->{'distances'}->{$locus} if $self->{'distances'}->{$locus} > $largest;
	}
	return $largest;
}

sub _scan_by_locus {
	my ( $self, $isolate_id, $locus, $seqs_ref, $allele_seqs_ref, $args ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my ( $match, @values, $extracted_seq );
	if ( $self->{'params'}->{'use_tagged'} ) {
		my $allele_ids = $self->{'datastore'}->get_allele_ids( $isolate_id, $locus );
		@$allele_ids = sort @$allele_ids;
		if (@$allele_ids) {
			$match->{'exact'} = 1;
			@{ $match->{'allele'} } = @$allele_ids;
		}
		foreach my $allele_id (@$allele_ids) {
			push @values, $allele_id;
			if ( $allele_id ne '0' ) {
				try {
					my $seq_ref = $self->{'datastore'}->get_locus($locus)->get_allele_sequence($allele_id);
					my $db_allele_seq = $$seq_ref if ref $seq_ref eq 'SCALAR';
					if ( $locus_info->{'data_type'} eq 'DNA' ) {
						$seqs_ref->{$isolate_id}       .= $db_allele_seq;
						$allele_seqs_ref->{$allele_id} .= $db_allele_seq;
						$extracted_seq = $db_allele_seq;
					} else {
						my $allele_sequences = $self->{'datastore'}->get_allele_sequence( $isolate_id, $locus );
						foreach my $allele_seq (@$allele_sequences) {
							my $seq = $self->_extract_sequence(
								{
									seqbin_id       => $allele_seq->{'seqbin_id'},
									predicted_start => $allele_seq->{'start_pos'},
									predicted_end   => $allele_seq->{'end_pos'},
									reverse         => $allele_seq->{'reverse'}
								}
							);
							my $seq_obj = Bio::Seq->new( -seq => $seq, -alphabet => 'dna' );
							my $translated_seq = $seq_obj->translate->seq;
							if ( $translated_seq eq $db_allele_seq ) {
								$seqs_ref->{$isolate_id}       .= $seq;
								$allele_seqs_ref->{$allele_id} .= $seq;
								$extracted_seq=  $seq;
								last;
							}
						}
					}
				}
				catch BIGSdb::DatabaseConnectionException with {
					$logger->debug("No connection to $locus database");    #ignore
				};
			}
		}
		if ( $locus_info->{'data_type'} eq 'peptide' &&  !$seqs_ref->{$isolate_id} ) {
			#The allele designation may be set but if we can't find the sequence in the bin, then
			#we don't know the exact nucleotide sequence of a peptide locus.
			$match->{'exact'} = 0;
		}
	}
	if ( !$match->{'exact'} && !-z $args->{'ref_seq_file'} ) {
		if ( $locus_info->{'data_type'} eq 'DNA' ) {
			$self->_blast(
				{
					word_size  => $args->{'word_size'},
					fasta_file => $args->{'ref_seq_file'},
					in_file    => $args->{'isolate_fasta_ref'}->{$isolate_id},
					out_file   => $args->{'out_file'},
					program    => 'blastn',
					options    => { max_target_seqs => 500 }
				}
			);
		} else {
			$self->_blast(
				{
					word_size  => 3,
					fasta_file => $args->{'ref_seq_file'},
					in_file    => $args->{'isolate_fasta_ref'}->{$isolate_id},
					out_file   => $args->{'out_file'},
					program    => 'blastx'
				}
			);
			
		}
		$match = $self->_parse_blast_by_locus( $locus, $args->{'out_file'} );
		@values = ( $match->{'allele'} ) if $match->{'exact'};
	}
	local $" = ',';
	return ( $match, "@values", $extracted_seq );
}

sub _print_paralogous_loci {
	my ( $self, $ids, $job_file, $loci, $match_count ) = @_;
	my $td = 1;
	my ( $table_buffer, $file_table_buffer, %paralogous_loci );
	my $params = $self->{'params'};
	foreach my $locus ( sort keys %$loci ) {
		my $paralogous_in_any = 0;
		my $paralogous_in_all = 1;
		my $missing_in_all    = 1;
		my $row_buffer        = "<tr class=\"td$td\"><td>$locus</td>";
		my $text_row_buffer   = $locus;
		foreach my $id (@$ids) {
			$row_buffer      .= "<td>$match_count->{$id}->{$locus}</td>";
			$text_row_buffer .= "\t$match_count->{$id}->{$locus}";
			if ( $match_count->{$id}->{$locus} > 0 ) {
				$missing_in_all = 0;
			}
			if ( $match_count->{$id}->{$locus} == 1 ) {
				$paralogous_in_all = 0;
			}
			if ( $match_count->{$id}->{$locus} > 1 ) {
				$paralogous_in_any = 1;
			}
		}
		$paralogous_in_all = 0 if $missing_in_all;
		if ( $params->{'paralogous_options'} eq 'any' ) {
			$paralogous_loci{$locus} = 1 if $paralogous_in_any;
		} elsif ( $params->{'paralogous_options'} eq 'all' ) {
			$paralogous_loci{$locus} = 1 if $paralogous_in_all;
		}
		$row_buffer      .= "</tr>\n";
		$text_row_buffer .= "\n";
		if ( $paralogous_loci{$locus} ) {
			$table_buffer      .= $row_buffer;
			$file_table_buffer .= $text_row_buffer;
			$td = $td == 1 ? 2 : 1;
		}
	}
	if ($table_buffer) {
		$self->{'html_buffer'} .= "<h3>Potentially paralogous loci</h3>\n";
		my $msg =
		  $params->{'paralogous_options'} eq 'any'
		  ? 'The table shows the number of matches where there was more than one hit matching the BLAST '
		  . 'thresholds in at least one genome. Depending on your BLAST parameters this is likely to '
		  . 'overestimate the number of paralogous loci.'
		  : 'The table shows the number of matches where there was more than one hit matching the BLAST '
		  . 'thresholds in all genomes (except where the locus was absent).';
		$self->{'html_buffer'} .= qq(<p>$msg</p>\n);
		$self->{'html_buffer'} .= q(<p>Paralogous: ) . ( keys %paralogous_loci ) . qq(</p>\n);
		$self->{'html_buffer'} .= q(<table class="resultstable"><tr><th>Locus</th>);
		my $file_buffer = "\n###\n\n";
		$file_buffer .= "Potentially paralogous loci\n";
		$file_buffer .= "---------------------------\n";
		$file_buffer .= "$msg\n\n";
		$file_buffer .= 'Paralogous: ' . ( keys %paralogous_loci ) . "\n\n";
		$file_buffer .= 'Locus';
		my $worksheet = $self->{'workbook'}->add_worksheet('paralogous loci');
		$worksheet->write( 0, 0, 'Locus', $self->{'excel_format'}->{'header'} );
		my $col       = 1;
		my $max_width = 5;

		foreach my $id (@$ids) {
			my $name = $self->_get_isolate_name($id);
			$self->{'html_buffer'} .= "<th>$name</th>";
			$file_buffer .= "\t$name";
			$worksheet->write( 0, $col, $name, $self->{'excel_format'}->{'header'} );
			$max_width = length $name if length $name > $max_width;
			$col++;
		}
		$file_buffer           .= "\n";
		$self->{'html_buffer'} .= "</tr>\n";
		$self->{'html_buffer'} .= $table_buffer;
		$self->{'html_buffer'} .= "</table>\n";
		$file_buffer           .= $file_table_buffer;
		open( my $job_fh, '>>', $job_file ) || $logger->error("Can't open $job_file for appending");
		say $job_fh $file_buffer;
		close $job_fh;
		my $row = 1;

		foreach my $locus ( sort keys %paralogous_loci ) {
			$worksheet->write( $row, 0, $locus, $self->{'excel_format'}->{'header'} );
			$col = 1;
			foreach my $id (@$ids) {
				$worksheet->write( $row, $col, $match_count->{$id}->{$locus}, $self->{'excel_format'}->{'normal'} );
				$col++;
			}
			$row++;
		}
		$worksheet->set_column( 0, 0, $self->_excel_col_width($max_width) );
		$worksheet->freeze_panes( 1, 0 );
	}
	return ( keys %paralogous_loci );
}

sub _identify_strains {
	my ( $self, $ids, $job_file, $loci, $values ) = @_;
	my %strains;
	my $strain_isolates;
	foreach my $id (@$ids) {
		my $profile;
		foreach my $locus ( keys %$loci ) {
			$profile .= $values->{$id}->{$locus} . '|';
		}
		my $profile_hash = Digest::MD5::md5_hex($profile);    #key could get very long otherwise
		$strains{$profile_hash}++;
		push @{ $strain_isolates->{$profile_hash} }, $self->_get_isolate_name($id);
	}
	$self->{'html_buffer'} .= '<h3>Unique strains</h3>';
	my $file_buffer = "\n###\n\n";
	$file_buffer .= "Unique strains\n";
	$file_buffer .= "--------------\n\n";
	my $num_strains = keys %strains;
	$self->{'html_buffer'} .= qq(<p>Unique strains: $num_strains</p>\n);
	$file_buffer           .= qq(Unique strains: $num_strains\n);
	$self->{'html_buffer'} .= q(<div class="scrollable"><table><tr>);
	$self->{'html_buffer'} .= qq(<th>Strain $_</th>) foreach ( 1 .. $num_strains );
	$self->{'html_buffer'} .= q(</tr><tr>);
	my $td        = 1;
	my $strain_id = 1;
	my $worksheet = $self->{'workbook'}->add_worksheet('unique strains');
	my $col       = 0;

	foreach ( 1 .. $num_strains ) {
		$worksheet->write( 0, $col, "Strain $_", $self->{'excel_format'}->{'header'} );
		$col++;
	}
	$col = 0;

	#With Excel::Writer::XLSX->set_optimization() switched on, rows need to be written in sequential order
	#So we need to calculate them first, then write them afterwards.
	my $excel_values        = [];
	my $excel_col_max_width = [];
	foreach my $strain ( sort { $strains{$b} <=> $strains{$a} } keys %strains ) {
		$self->{'html_buffer'} .= "<td class=\"td$td\" style=\"vertical-align:top\">";
		$self->{'html_buffer'} .= "$_<br />\n" foreach @{ $strain_isolates->{$strain} };
		$self->{'html_buffer'} .= "</td>\n";
		$td = $td == 1 ? 2 : 1;
		$file_buffer .= "\nStrain $strain_id:\n";
		$file_buffer .= "$_\n" foreach @{ $strain_isolates->{$strain} };
		my $row        = 1;
		my $max_length = 5;

		foreach my $isolate ( @{ $strain_isolates->{$strain} } ) {
			$excel_values->[$row]->[$col] = $isolate;
			$max_length = length $isolate if length $isolate > $max_length;
			$row++;
		}
		$excel_col_max_width->[$col] = $self->_excel_col_width($max_length);
		$col++;
		$strain_id++;
	}
	for my $row ( 1 .. @$excel_values - 1 ) {
		for my $col ( 0 .. @{ $excel_values->[$row] } - 1 ) {
			$worksheet->write( $row, $col, $excel_values->[$row]->[$col], $self->{'excel_format'}->{'normal'} );
		}
	}
	for my $col ( 0 .. @$excel_col_max_width - 1 ) {
		$worksheet->set_column( $col, $col, $excel_col_max_width->[$col] );
	}
	$self->{'html_buffer'} .= "</tr></table></div>\n";
	open( my $job_fh, '>>', $job_file ) || $logger->error("Can't open $job_file for appending");
	print $job_fh $file_buffer;
	close $job_fh;
	$worksheet->freeze_panes( 1, 0 );
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

sub _print_variable_loci {
	my ( $self, $args ) = @_;
	my ( $by_reference, $ids, $job_filename, $loci, $values ) = @{$args}{qw(by_reference ids job_filename loci values)};
	return if ref $loci ne 'HASH';
	$self->{'html_buffer'} .= '<h3>Loci with sequence differences among isolates:</h3>';
	my $file_buffer = "\n###\n\n";
	$file_buffer .= "Loci with sequence differences among isolates\n";
	$file_buffer .= "---------------------------------------------\n\n";
	$self->{'html_buffer'} .= '<p>Variable loci: ' . ( scalar keys %$loci ) . '</p>';
	$file_buffer .= 'Variable loci: ' . ( scalar keys %$loci ) . "\n\n";
	open( my $job_fh, '>>', $job_filename ) || $logger->error("Can't open $job_filename for appending");
	print $job_fh $file_buffer;
	close $job_fh;
	my $worksheet = $self->{'workbook'}->add_worksheet('variable');
	$self->_print_locus_table( { worksheet => $worksheet, %$args } );
	return;
}

sub _align {
	my ( $self, $args ) = @_;
	my ( $job_id, $locus, $seqs, $align_file, $align_stats_file, $xmfa_file, $core_locus, $core_xmfa_file ) =
	  @{$args}{qw(job_id locus seqs align_file align_stats_file xmfa_file core_locus core_xmfa_file)};
	my $params = $self->{'params'};
	state $xmfa_start = 1;
	state $xmfa_end   = 1;
	my $temp = BIGSdb::Utils::get_random();
	( my $escaped_locus = $locus ) =~ s/[\/\|\']/_/gx;
	$escaped_locus =~ tr/ /_/;
	my $fasta_file  = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_$escaped_locus.fasta";
	my $aligned_out = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_$escaped_locus.aligned";
	my $seq_count   = 0;
	open( my $fasta_fh, '>', $fasta_file ) || $logger->error("Can't open $fasta_file for writing");
	no warnings 'numeric';
	my @ids = sort { $a <=> $b || $a cmp $b } keys %$seqs;
	my %names;
	my @ids_to_align;

	foreach my $id (@ids) {
		next if $id eq 'ref' && !$self->{'params'}->{'include_ref'};
		push @ids_to_align, $id;
		my $name = $id ne 'ref' ? $self->_get_isolate_name( $id, { name_only => 1 } ) : 'ref';
		$name =~ s/[\(\)]//gx;
		$name =~ s/ /|/;         #replace space separating id and name
		$name =~ tr/[:, ]/_/;
		$names{$id} = $name;
		if ( $seqs->{$id} ) {
			$seq_count++;
			say $fasta_fh ">$name";
			say $fasta_fh "$seqs->{$id}";
		}
	}
	close $fasta_fh;
	if ( $params->{'align'} ) {
		$self->{'distances'}->{$locus} = $self->_run_alignment(
			{
				ids              => \@ids_to_align,
				locus            => $locus,
				seq_count        => $seq_count,
				aligned_out      => $aligned_out,
				fasta_file       => $fasta_file,
				align_file       => $align_file,
				core_locus       => $core_locus,
				align_stats_file => $align_stats_file,
				xmfa_out         => $xmfa_file,
				core_xmfa_out    => $core_xmfa_file,
				xmfa_start_ref   => \$xmfa_start,
				xmfa_end_ref     => \$xmfa_end,
				names            => \%names
			}
		);
	}
	unlink $fasta_file;
	return;
}

sub _run_infoalign {

	#returns mean distance
	my ( $self, $values ) = @_;
	if ( -e "$self->{'config'}->{'emboss_path'}/infoalign" ) {
		my $prefix  = BIGSdb::Utils::get_random();
		my $outfile = "$self->{'config'}->{'secure_tmp_dir'}/$prefix.infoalign";
		system(
			"$self->{'config'}->{'emboss_path'}/infoalign -sequence $values->{'alignment'} -outfile $outfile -nousa "
			  . '-nosimcount -noweight -nodescription 2> /dev/null' );
		open( my $fh_stats, '>>', $values->{'align_stats_file'} )
		  or $logger->error("Can't open output file $values->{'align_stats_file'} for appending");
		my $heading_locus = $self->clean_locus( $values->{'locus'}, { text_output => 1 } );
		print $fh_stats "$heading_locus\n";
		print $fh_stats '-' x ( length $heading_locus ) . "\n\n";
		close $fh_stats;

		if ( -e $outfile ) {
			BIGSdb::Utils::append( $outfile, $values->{'align_stats_file'}, { blank_after => 1 } );
			open( my $fh, '<', $outfile )
			  or $logger->error("Can't open alignment stats file file $outfile for reading");
			my $row        = 0;
			my $total_diff = 0;
			while (<$fh>) {
				next if /^\#/x;
				my @values = split /\s+/x;
				my $diff   = $values[7];     # % difference from consensus
				$total_diff += $diff;
				$row++;
			}
			my $mean_distance = $total_diff / ( $row * 100 );
			close $fh;
			unlink $outfile;
			return $mean_distance;
		}
	}
	return;
}

sub _run_alignment {
	my ( $self, $args ) = @_;
	my (
		$ids,        $names,    $locus,          $seq_count,    $aligned_out, $fasta_file,
		$align_file, $xmfa_out, $xmfa_start_ref, $xmfa_end_ref, $core_locus,  $core_xmfa_out
	  )
	  = @{$args}{
		qw (ids names locus seq_count aligned_out fasta_file align_file xmfa_out
		  xmfa_start_ref xmfa_end_ref core_locus core_xmfa_out )
	  };
	return if $seq_count <= 1;
	my $params = $self->{'params'};
	if ( $params->{'aligner'} eq 'MAFFT' && $self->{'config'}->{'mafft_path'} && -e $fasta_file && -s $fasta_file ) {
		my $threads =
		  BIGSdb::Utils::is_int( $self->{'config'}->{'mafft_threads'} ) ? $self->{'config'}->{'mafft_threads'} : 1;
		system(
"$self->{'config'}->{'mafft_path'} --thread $threads --quiet --preservecase --clustalout $fasta_file > $aligned_out"
		);
	} elsif ( $params->{'aligner'} eq 'MUSCLE'
		&& $self->{'config'}->{'muscle_path'}
		&& -e $fasta_file
		&& -s $fasta_file )
	{
		my $max_mb = $self->{'config'}->{'max_muscle_mb'} // MAX_MUSCLE_MB;
		system( $self->{'config'}->{'muscle_path'},
			-in    => $fasta_file,
			-out   => $aligned_out,
			-maxmb => $max_mb,
			'-quiet', '-clwstrict'
		);
	} else {
		$logger->error('No aligner selected');
	}
	my $distance;
	if ( -e $aligned_out ) {
		my $align = Bio::AlignIO->new( -format => 'clustalw', -file => $aligned_out )->next_aln;
		my ( %id_has_seq, $seq_length );
		my $xmfa_buffer;
		my $clean_locus = $self->clean_locus( $locus, { text_output => 1, no_common_name => 1 } );
		foreach my $seq ( $align->each_seq ) {
			$$xmfa_end_ref = $$xmfa_start_ref + $seq->length - 1;
			$xmfa_buffer .= '>' . $seq->id . ":$$xmfa_start_ref-$$xmfa_end_ref + $clean_locus\n";
			my $sequence = BIGSdb::Utils::break_line( $seq->seq, 60 );
			$xmfa_buffer .= "$sequence\n";
			my ($id) = split /\|/x, $seq->id;
			$id_has_seq{$id} = 1;
			$seq_length = $seq->length if !$seq_length;
		}
		my $missing_seq = BIGSdb::Utils::break_line( ( '-' x $seq_length ), 60 );
		foreach my $id (@$ids) {
			next if $id_has_seq{$id};
			$xmfa_buffer .= ">$names->{$id}:$$xmfa_start_ref-$$xmfa_end_ref + $clean_locus\n$missing_seq\n";
		}
		$xmfa_buffer .= '=';
		open( my $fh_xmfa, '>>', $xmfa_out ) or $logger->error("Can't open output file $xmfa_out for appending");
		say $fh_xmfa $xmfa_buffer if $xmfa_buffer;
		close $fh_xmfa;
		if ($core_locus) {
			open( my $fh_core_xmfa, '>>', $core_xmfa_out )
			  or $logger->error("Can't open output file $core_xmfa_out for appending");
			say $fh_core_xmfa $xmfa_buffer if $xmfa_buffer;
			close $fh_core_xmfa;
		}
		$$xmfa_start_ref = $$xmfa_end_ref + 1;
		open( my $align_fh, '>>', $align_file ) || $logger->error("Can't open $align_file for appending");
		my $heading_locus = $self->clean_locus( $locus, { text_output => 1 } );
		say $align_fh "$heading_locus";
		say $align_fh '-' x ( length $heading_locus ) . "\n";
		close $align_fh;
		BIGSdb::Utils::append( $aligned_out, $align_file, { blank_after => 1 } );
		$args->{'alignment'} = $aligned_out;
		$distance = $self->_run_infoalign($args);
		unlink $aligned_out;
	}
	return $distance;
}

sub _print_exact_matches {
	my ( $self, $args ) = @_;
	my ( $by_reference, $ids, $job_filename, $exacts, $values ) =
	  @{$args}{qw(by_reference ids job_filename loci values)};
	return if ref $exacts ne 'HASH';
	$self->{'html_buffer'} .= "<h3>Exactly matching loci</h3>\n";
	my $file_buffer = "\n###\n\n";
	$file_buffer           .= "Exactly matching loci\n";
	$file_buffer           .= "---------------------\n\n";
	$self->{'html_buffer'} .= '<p>These loci are identical in all isolates';
	$file_buffer           .= 'These loci are identical in all isolates';
	if ( $self->{'params'}->{'accession'} ) {
		$self->{'html_buffer'} .= ', including the reference genome';
		$file_buffer .= ', including the reference genome';
	}
	$self->{'html_buffer'} .= '.</p>';
	$file_buffer           .= ".\n\n";
	$self->{'html_buffer'} .= '<p>Matches: ' . ( scalar keys %$exacts ) . '</p>';
	$file_buffer .= 'Matches: ' . ( scalar keys %$exacts ) . "\n\n";
	open( my $job_fh, '>>', $job_filename ) || $logger->error("Can't open $job_filename for appending");
	print $job_fh $file_buffer;
	close $job_fh;
	my $worksheet = $self->{'workbook'}->add_worksheet('same in all');
	$self->_print_locus_table( { worksheet => $worksheet, %$args } );
	return;
}

sub _print_exact_except_ref {
	my ( $self, $args ) = @_;
	my ( $by_reference, $ids, $job_filename, $exacts, $values ) =
	  @{$args}{qw(by_reference ids job_filename loci values)};
	return if ref $exacts ne 'HASH';
	open( my $job_fh, '>>', $job_filename ) || $logger->error("Can't open $job_filename for appending");
	$self->{'html_buffer'} .= '<h3>Loci exactly the same in all compared genomes except the reference</h3>';
	print $job_fh "\n###\n\n";
	print $job_fh "Loci exactly the same in all compared genomes except the reference\n";
	print $job_fh "------------------------------------------------------------------\n\n";
	$self->{'html_buffer'} .= '<p>Matches: ' . ( scalar keys %$exacts ) . '</p>';
	print $job_fh 'Matches: ' . ( scalar keys %$exacts ) . "\n\n";
	close $job_fh;
	my $worksheet = $self->{'workbook'}->add_worksheet('same except ref');
	$self->_print_locus_table( { worksheet => $worksheet, %$args } );
	return;
}

sub _print_missing_in_all {
	my ( $self, $args ) = @_;
	my ( $by_reference, $ids, $job_filename, $missing, $values ) =
	  @{$args}{qw(by_reference ids job_filename loci values)};
	return if ref $missing ne 'HASH';
	open( my $job_fh, '>>', $job_filename ) || $logger->error("Can't open $job_filename for appending");
	$self->{'html_buffer'} .= '<h3>Loci missing in all isolates</h3>';
	print $job_fh "\n###\n\n";
	print $job_fh "Loci missing in all isolates\n";
	print $job_fh "----------------------------\n\n";
	$self->{'html_buffer'} .= '<p>Missing loci: ' . ( scalar keys %$missing ) . '</p>';
	print $job_fh 'Missing loci: ' . ( scalar keys %$missing ) . "\n\n";
	close $job_fh;
	my $worksheet = $self->{'workbook'}->add_worksheet('missing in all');
	$self->_print_locus_table( { worksheet => $worksheet, %$args } );
	return;
}

sub _print_truncated_loci {
	my ( $self, $args ) = @_;
	my ( $by_reference, $ids, $job_filename, $truncated, $truncated_param, $values ) =
	  @{$args}{qw(by_reference ids job_filename loci truncated_param values)};
	return if ref $truncated ne 'HASH';
	$self->{'html_buffer'} .= '<h3>Loci that are incomplete in some isolates</h3>';
	my $file_buffer = "\n###\n\n";
	$file_buffer .= "Loci that are incomplete in some isolates\n";
	$file_buffer .= "-----------------------------------------\n\n";
	$self->{'html_buffer'} .= '<p>Incomplete: ' . ( scalar keys %$truncated ) . '</p>';
	$file_buffer .= 'Incomplete: ' . ( scalar keys %$truncated ) . "\n\n";
	$self->{'html_buffer'} .=
	  '<p>These loci are incomplete and located at the ' . 'ends of contigs in at least one isolate. ';

	if ( $truncated_param eq 'exclude' ) {
		$self->{'html_buffer'} .= 'They have been excluded from the distance matrix calculation.';
	}
	$self->{'html_buffer'} .= '</p>';
	$file_buffer .= "These loci are incomplete and located at the ends of contigs in at least one isolate.\n\n";
	open( my $job_fh, '>>', $job_filename ) || $logger->error("Can't open $job_filename for appending");
	print $job_fh $file_buffer;
	close $job_fh;
	my $worksheet = $self->{'workbook'}->add_worksheet('incomplete');
	$self->_print_locus_table( { worksheet => $worksheet, %$args } );
	return;
}

sub _print_locus_table {
	my ( $self, $args ) = @_;
	my ( $by_reference, $ids, $job_filename, $loci, $values, $worksheet ) =
	  @{$args}{qw(by_reference ids job_filename loci values worksheet)};
	$self->_print_isolate_header( $by_reference, $ids, $worksheet );
	my $td = 1;
	my $text_buffer;
	my $row          = 0;
	my $num_isolates = @$ids;
	$num_isolates++ if $by_reference;
	my %excel_format;

	foreach my $locus ( sort keys %$loci ) {
		my $col = 0;
		$row++;
		my $cleaned_locus = $self->clean_locus($locus);
		$self->{'html_buffer'} .= qq(<tr class="td$td"><td>$cleaned_locus</td>);
		my $text_locus = $self->clean_locus( $locus, { text_output => 1 } );
		$text_buffer .= $text_locus;
		$worksheet->write( $row, $col, $text_locus, $self->{'excel_format'}->{'locus'} );
		my $colour = 0;
		my %value_colour;
		$value_colour{'X'} = 'X';
		$value_colour{'I'} = 'I';

		if ($by_reference) {
			foreach my $locus_value (qw(desc length start)) {
				$self->{'html_buffer'} .= "<td>$loci->{$locus}->{$locus_value}</td>";
				$text_buffer .= "\t$loci->{$locus}->{$locus_value}";
				$col++;
				$worksheet->write( $row, $col, $loci->{$locus}->{$locus_value}, $self->{'excel_format'}->{'locus'} );
			}
			$col++;
			$colour++;
			$value_colour{1} = $colour;
			my $style = BIGSdb::Utils::get_heatmap_colour_style( $value_colour{1}, $num_isolates );
			$self->{'html_buffer'} .= qq(<td style="$style">1</td>);
			$self->{'file_buffer'} .= qq(\t1);
			if ( !$excel_format{$colour} ) {
				my $excel_style =
				  BIGSdb::Utils::get_heatmap_colour_style( $value_colour{1}, $num_isolates, { excel => 1 } );
				$excel_format{$colour} = $self->{'workbook'}->add_format(%$excel_style);
			}
			$worksheet->write( $row, $col, 1, $excel_format{$colour} );
		}
		foreach my $id (@$ids) {
			$col++;
			my $style = $self->{'style'}->{$locus}->{ $values->{$id}->{$locus} };
			$self->{'html_buffer'} .= qq(<td style="$style">$values->{$id}->{$locus}</td>);
			$text_buffer .= qq(\t$values->{$id}->{$locus});
			if ( !$value_colour{ $values->{$id}->{$locus} } ) {
				$colour++;
				$value_colour{ $values->{$id}->{$locus} } = $colour;
			}
			$worksheet->write(
				$row, $col,
				$values->{$id}->{$locus},
				$self->{'excel_format'}->{ $value_colour{ $values->{$id}->{$locus} } }
			);
		}
		$self->{'html_buffer'} .= "</tr>\n";
		$text_buffer .= "\n";
		$td = $td == 1 ? 2 : 1;
	}
	open( my $job_fh, '>>', $job_filename ) || $logger->error("Can't open $job_filename for appending");
	print $job_fh $text_buffer;
	close $job_fh;
	$self->{'html_buffer'} .= "</table>\n";
	$self->{'html_buffer'} .= "</div>\n";
	if ($worksheet) {
		foreach my $col ( keys %{ $self->{'col_max_width'} } ) {
			$worksheet->set_column( $col, $col, $self->_excel_col_width( $self->{'col_max_width'}->{$col} ) );
		}
	}
	return;
}

sub _extract_sequence {
	my ( $self, $match ) = @_;
	my $start = $match->{'predicted_start'};
	my $end   = $match->{'predicted_end'};
	return if !defined $start || !defined $end;
	my $length = abs( $end - $start ) + 1;
	if ( $end < $start ) {
		$start = $end;
	}
	my $seq =
	  $self->{'datastore'}
	  ->run_query( "SELECT substring(sequence from $start for $length) FROM sequence_bin WHERE id=?",
		$match->{'seqbin_id'} );
	if ( $match->{'reverse'} ) {
		return BIGSdb::Utils::reverse_complement($seq);
	}
	$self->{'db'}->commit;
	return $seq;
}

sub _blast {
	my ( $self, $args ) = @_;
	my ( $word_size, $fasta_file, $in_file, $out_file, $program, $options ) =
	  @{$args}{qw(word_size fasta_file in_file out_file program options)};
	$options = {} if ref $options ne 'HASH';
	my $blast_threads = $self->{'config'}->{'blast_threads'} || 1;
	my $filter = $program eq 'blastn' ? 'dust' : 'seg';
	my %params = (
				-num_threads     => $blast_threads,
			-max_target_seqs => $options->{'max_target_seqs'} // 10,
			-word_size       => $word_size,
			-db              => $fasta_file,
			-query           => $in_file,
			-out             => $out_file,
			-outfmt          => 6,
			-$filter         => 'no'
	);
	$params{'-comp_based_stats'} = 0 if $program ne 'blastn' && $program ne 'tblastx'; 
	system(	"$self->{'config'}->{'blast+_path'}/$program",%params	);
	return;
}

sub _parse_blast_by_locus {

	#return best match
	my ( $self, $locus, $blast_file ) = @_;
	my $params    = $self->{'params'};
	my $identity  = BIGSdb::Utils::is_int( $params->{'identity'} ) ? $params->{'identity'} : 70;
	my $alignment = BIGSdb::Utils::is_int( $params->{'alignment'} ) ? $params->{'alignment'} : 50;
	my $full_path = "$blast_file";
	my $match;
	my $quality = 0;    #simple metric of alignment length x percentage identity
	my $ref_seq_sql = $self->{'db'}->prepare('SELECT length(reference_sequence) FROM loci WHERE id=?');
	my %lengths;
	my @blast;
	open( my $blast_fh, '<', $full_path )
	  || ( $logger->error("Can't open BLAST output file $full_path. $!"), return \$; );
	push @blast, $_ foreach <$blast_fh>;    #slurp file to prevent file handle remaining open during database queries.
	close $blast_fh;

	foreach my $line (@blast) {
		next if !$line || $line =~ /^\#/x;
		my @record = split /\s+/x, $line;
		if ( !$lengths{ $record[1] } ) {
			if ( $record[1] eq 'ref' ) {
				eval {
					$ref_seq_sql->execute($locus);
					( $lengths{ $record[1] } ) = $ref_seq_sql->fetchrow_array;
				};
				$logger->error($@) if $@;
			} else {
				my $seq_ref = $self->{'datastore'}->get_locus($locus)->get_allele_sequence( $record[1] );
				$lengths{ $record[1] } = length($$seq_ref);
			}
		}
		my $length       = $lengths{ $record[1] };
		my $this_quality = $record[3] * $record[2];
		if (   ( !$match->{'exact'} && $record[2] == 100 && $record[3] == $length )
			|| ( $this_quality > $quality && $record[3] > $alignment * 0.01 * $length && $record[2] >= $identity ) )
		{
			#Always score exact match higher than a longer partial match
			next if $match->{'exact'} && !( $record[2] == 100 && $record[3] == $length );
			$quality              = $this_quality;
			$match->{'seqbin_id'} = $record[0];
			$match->{'allele'}    = $record[1];
			$match->{'identity'}  = $record[2];
			$match->{'length'}    = $length;
			$match->{'alignment'} = $record[3];
			$match->{'start'}     = $record[6];
			$match->{'end'}       = $record[7];

			if (   ( $record[8] > $record[9] && $record[7] > $record[6] )
				|| ( $record[8] < $record[9] && $record[7] < $record[6] ) )
			{
				$match->{'reverse'} = 1;
			} else {
				$match->{'reverse'} = 0;
			}
			$match->{'exact'} = 1 if $match->{'identity'} == 100 && $match->{'alignment'} == $length;
			if ( $length > $match->{'alignment'} ) {
				if ( $match->{'reverse'} ) {
					if ( $record[8] < $record[9] ) {
						$match->{'predicted_start'} = $match->{'start'} - $length + $record[9];
						$match->{'predicted_end'}   = $match->{'end'} + $record[8] - 1;
					} else {
						$match->{'predicted_start'} = $match->{'start'} - $length + $record[8];
						$match->{'predicted_end'}   = $match->{'end'} + $record[9] - 1;
					}
				} else {
					if ( $record[8] < $record[9] ) {
						$match->{'predicted_start'} = $match->{'start'} - $record[8] + 1;
						$match->{'predicted_end'}   = $match->{'end'} + $length - $record[9];
					} else {
						$match->{'predicted_start'} = $match->{'start'} - $record[9] + 1;
						$match->{'predicted_end'}   = $match->{'end'} + $length - $record[8];
					}
				}
			} else {
				$match->{'predicted_start'} = $match->{'start'};
				$match->{'predicted_end'}   = $match->{'end'};
			}
		}
	}
	return $match;
}

sub _parse_blast_ref {

	#return best match
	my ( $self, $seq_ref, $blast_file ) = @_;
	my $params    = $self->{'params'};
	my $identity  = BIGSdb::Utils::is_int( $params->{'identity'} ) ? $params->{'identity'} : 70;
	my $alignment = BIGSdb::Utils::is_int( $params->{'alignment'} ) ? $params->{'alignment'} : 50;
	my $final_match;
	my $quality    = 0;                  #simple metric of alignment length x percentage identity
	my $ref_length = length $$seq_ref;
	my $required_alignment = $params->{'tblastx'} ? int( $ref_length / 3 ) : $ref_length;
	my @blast;
	open( my $blast_fh, '<', $blast_file )
	  || ( $logger->error("Can't open BLAST output file $blast_file. $!"), return \$; );
	push @blast, $_ foreach <$blast_fh>;    #slurp file to prevent file handle remaining open during database queries.
	close $blast_fh;
	my $criteria_matches = 0;

	foreach my $line (@blast) {
		next if !$line || $line =~ /^\#/x;
		my @record = split /\s+/x, $line;
		my $this_quality = $record[3] * $record[2];
		if ( $record[3] >= $alignment * 0.01 * $required_alignment && $record[2] >= $identity ) {
			my $this_match = $self->_extract_match( \@record, $required_alignment, $ref_length );
			$criteria_matches++;
			if ( $this_quality > $quality ) {
				$quality     = $this_quality;
				$final_match = $this_match;
			}
		}
	}
	if ( $criteria_matches > 1 ) {    #only check if match sequences are different if there are more than 1
		my $good_matches = 0;
		my @existing_match_seqs;
		foreach my $line (@blast) {
			next if !$line || $line =~ /^\#/x;
			my @record = split /\s+/x, $line;
			if ( $record[3] >= $alignment * 0.01 * $required_alignment && $record[2] >= $identity ) {
				my $this_match        = $self->_extract_match( \@record, $required_alignment, $ref_length );
				my $match_seq         = $self->_extract_sequence($this_match);
				my $seq_already_found = 0;
				foreach my $existing_match_seq (@existing_match_seqs) {
					if ( $match_seq eq $existing_match_seq ) {    #Only count different alleles
						$seq_already_found = 1;
						last;
					}
				}
				if ( !$seq_already_found ) {
					push @existing_match_seqs, $match_seq;
					$good_matches++;
				}
			}
		}
		$final_match->{'good_matches'} = $good_matches;
	} else {
		$final_match->{'good_matches'} = $criteria_matches;
	}
	return $final_match;
}

sub _extract_match {
	my ( $self, $record, $required_alignment, $ref_length ) = @_;
	my $match;
	$match->{'seqbin_id'} = $record->[1];
	$match->{'identity'}  = $record->[2];
	$match->{'alignment'} = $record->[3];
	$match->{'start'}     = $record->[8];
	$match->{'end'}       = $record->[9];
	if (   ( $record->[8] > $record->[9] && $record->[7] > $record->[6] )
		|| ( $record->[8] < $record->[9] && $record->[7] < $record->[6] ) )
	{
		$match->{'reverse'} = 1;
	} else {
		$match->{'reverse'} = 0;
	}
	if ( $required_alignment > $match->{'alignment'} ) {
		if ( $match->{'reverse'} ) {
			$match->{'predicted_start'} = $match->{'start'} - $ref_length + $record->[6];
			$match->{'predicted_end'}   = $match->{'end'} + $record->[7] - 1;
		} else {
			$match->{'predicted_start'} = $match->{'start'} - $record->[6] + 1;
			$match->{'predicted_end'}   = $match->{'end'} + $ref_length - $record->[7];
		}
	} else {
		if ( $match->{'reverse'} ) {
			$match->{'predicted_start'} = $match->{'end'};
			$match->{'predicted_end'}   = $match->{'start'};
		} else {
			$match->{'predicted_start'} = $match->{'start'};
			$match->{'predicted_end'}   = $match->{'end'};
		}
	}
	return $match;
}

sub _create_locus_FASTA_db {
	my ( $self, $locus, $prefix ) = @_;
	my $clean_locus = $locus;
	$clean_locus =~ s/\W/_/gx;
	if ( $locus =~ /(\w*)/x ) { $clean_locus = $1 }    #untaint
	my $temp_fastafile = "$self->{'config'}->{'secure_tmp_dir'}/$prefix\_fastafile_$clean_locus.txt";
	$temp_fastafile =~ s/\\/\\\\/gx;
	$temp_fastafile =~ s/'/__prime__/gx;
	if ( !-e $temp_fastafile ) {
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		my $file_buffer;
		if ( $locus_info->{'dbase_name'} ) {
			my $seqs_ref = $self->{'datastore'}->get_locus($locus)->get_all_sequences;
			foreach ( keys %$seqs_ref ) {
				next if !length $seqs_ref->{$_};
				$file_buffer .= ">$_\n$seqs_ref->{$_}\n";
			}
		} else {
			$file_buffer .= ">ref\n$locus_info->{'reference_sequence'}\n";
		}
		open( my $fasta_fh, '>', $temp_fastafile ) || $logger->error("Can't open $temp_fastafile for writing");
		print $fasta_fh $file_buffer if $file_buffer;
		close $fasta_fh;
		my $dbtype = $locus_info->{'data_type'} eq 'DNA' ? 'nucl' : 'prot';
		system( "$self->{'config'}->{'blast+_path'}/makeblastdb",
			( -in => $temp_fastafile, -logfile => '/dev/null', -dbtype => $dbtype ) );
	}
	return $temp_fastafile;
}

sub _create_reference_FASTA_file {
	my ( $self, $seq_ref, $prefix ) = @_;
	my $temp_fastafile = "$self->{'config'}->{'secure_tmp_dir'}/$prefix\_fastafile.txt";
	open( my $fasta_fh, '>', $temp_fastafile ) || $logger->error("Can't open $temp_fastafile for writing");
	print $fasta_fh ">ref\n$$seq_ref\n";
	close $fasta_fh;
	return $temp_fastafile;
}

sub _create_isolate_FASTA {
	my ( $self, $isolate_id, $prefix ) = @_;
	my $qry = 'SELECT DISTINCT id,sequence FROM sequence_bin LEFT JOIN experiment_sequences ON '
	  . 'sequence_bin.id=seqbin_id WHERE sequence_bin.isolate_id=?';
	my @criteria = ($isolate_id);
	my $method   = $self->{'params'}->{'seq_method_list'};
	if ($method) {
		if ( !any { $_ eq $method } SEQ_METHODS ) {
			$logger->error("Invalid method $method");
			return;
		}
		$qry .= ' AND method=?';
		push @criteria, $method;
	}
	my $experiment = $self->{'params'}->{'experiment_list'};
	if ($experiment) {
		if ( !BIGSdb::Utils::is_int($experiment) ) {
			$logger->error("Invalid experiment $experiment");
			return;
		}
		$qry .= ' AND experiment_id=?';
		push @criteria, $experiment;
	}
	my $contigs =
	  $self->{'datastore'}
	  ->run_query( $qry, \@criteria, { fetch => 'all_arrayref', cache => 'GenomeComparator::create_isolate_FASTA' } );
	if ( $isolate_id =~ /(\d*)/x ) { $isolate_id = $1 }    #untaint
	my $temp_infile = "$self->{'config'}->{'secure_tmp_dir'}/$prefix\_isolate_$isolate_id.txt";
	open( my $infile_fh, '>', $temp_infile ) || $logger->error("Can't open $temp_infile for writing");
	foreach (@$contigs) {
		say $infile_fh ">$_->[0]\n$_->[1]";
	}
	close $infile_fh;
	$self->{'db'}->commit;
	return $temp_infile;
}

sub _create_isolate_FASTA_db {
	my ( $self, $isolate_id, $prefix ) = @_;
	my $temp_infile = $self->_create_isolate_FASTA( $isolate_id, $prefix );
	system( "$self->{'config'}->{'blast+_path'}/makeblastdb",
		( -in => $temp_infile, -logfile => '/dev/null', -dbtype => 'nucl' ) );
	return $temp_infile;
}
1;
