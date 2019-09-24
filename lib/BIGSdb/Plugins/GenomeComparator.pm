#GenomeComparator.pm - Genome comparison plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2019, University of Oxford
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
use parent qw(BIGSdb::Plugin);
use BIGSdb::Exceptions;
use BIGSdb::Constants qw(SEQ_METHODS LOCUS_PATTERN :limits);
use BIGSdb::GCForkScan;
use Bio::AlignIO;
use Bio::Seq;
use Bio::SeqIO;
use IO::Uncompress::Unzip qw(unzip $UnzipError);
use IO::String;
use Excel::Writer::XLSX;
use Digest::MD5;
use List::MoreUtils qw(uniq);
use Try::Tiny;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_DISPLAY_CELLS => 100_000;
use constant MAX_GENOMES       => 1000;
use constant MAX_REF_LOCI      => 10000;

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
		version     => '2.3.27',
		dbtype      => 'isolates',
		section     => 'analysis,postquery',
		url         => "$self->{'config'}->{'doclink'}/data_analysis/genome_comparator.html",
		order       => 31,
		requires    => 'aligner,offline_jobs,js_tree,seqbin',
		input       => 'query',
		help        => 'tooltips',
		system_flag => 'GenomeComparator',
		priority    => 0
	);
	return \%att;
}

sub get_initiation_values {
	return { 'jQuery.jstree' => 1 };
}

sub run {
	my ($self) = @_;
	my $desc = $self->get_db_description;
	say qq(<h1>Genome Comparator - $desc</h1>);
	my $q = $self->{'cgi'};
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
		my ( $ref_upload, $user_upload );
		if ( $q->param('ref_upload') ) {
			$ref_upload = $self->_upload_ref_file;
		}
		if ( $q->param('user_upload') ) {
			$user_upload = $self->_upload_user_file;
		}
		my $filtered_ids = $self->filter_ids_by_project( $ids, scalar $q->param('project_list') );
		if ( !@$filtered_ids && !$q->param('user_upload') ) {
			push @errors, q(You must include one or more isolates. Make sure your selected isolates )
			  . q(haven't been filtered to none by selecting a project.);
			$continue = 0;
		}
		my $max_genomes =
		  ( BIGSdb::Utils::is_int( $self->{'system'}->{'genome_comparator_limit'} ) )
		  ? $self->{'system'}->{'genome_comparator_limit'}
		  : MAX_GENOMES;
		if ( @$filtered_ids > $max_genomes ) {
			my $nice_max = BIGSdb::Utils::commify($max_genomes);
			my $selected = BIGSdb::Utils::commify( scalar @$filtered_ids );
			push @errors,
			  qq(Genome Comparator analysis is limited to $nice_max isolates. ) . qq(You have selected $selected.);
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
	my $guid = $self->get_guid;
	my $use_all;
	try {
		my $pref =
		  $self->{'prefstore'}->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'GenomeComparator', 'use_all' );
		$use_all = ( defined $pref && $pref eq 'true' ) ? 1 : 0;
	}
	catch {
		if ( $_->isa('BIGSdb::Exception::Database::NoRecord') ) {
			$use_all = 0;
		} elsif ( $_->isa('BIGSdb::Exception::Prefstore::NoGUID') ) {

			#Ignore
		} else {
			$logger->logdie($_);
		}
	};
	my $seqbin_values = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT id FROM sequence_bin)');
	if ( !$seqbin_values ) {
		$self->print_bad_status( { message => q(This database view contains no genomes.), navbar => 1 } );
		return;
	}
	$self->print_scheme_selection_banner;
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
	$self->print_user_genome_upload_fieldset;
	$self->print_isolates_locus_fieldset( { locus_paste_list => 1 } );
	$self->print_includes_fieldset(
		{
			title                 => 'Include in identifiers',
			preselect             => $self->{'system'}->{'labelfield'},
			include_scheme_fields => 1
		}
	);
	$self->print_recommended_scheme_fieldset;
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

sub _print_parameters_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left;height:12em"><legend>Parameters / options</legend>);
	say q(<ul><li><label for ="identity" class="parameter">Min % identity:</label>);
	say $q->popup_menu( -name => 'identity', -id => 'identity', -values => [ 30 .. 100 ], -default => 70 );
	say $self->get_tooltip(q(Minimum % identity - Match required for partial matching.));
	say q(</li><li><label for="alignment" class="parameter">Min % alignment:</label>);
	say $q->popup_menu( -name => 'alignment', -id => 'alignment', -values => [ 10 .. 100 ], -default => 50 );
	say $self->get_tooltip( q(Minimum % alignment - Percentage of allele sequence length required to be )
		  . q(aligned for partial matching.) );
	say q(</li><li><label for="word_size" class="parameter">BLASTN word size:</label>);
	say $q->popup_menu( -name => 'word_size', -id => 'word_size', -values => [ 7 .. 30 ], -default => 20 );
	say $self->get_tooltip( q(BLASTN word size - This is the length of an exact match required to )
		  . q(initiate an extension. Larger values increase speed at the expense of sensitivity.) );
	say q(</li></ul></fieldset>);
	return;
}

sub _print_reference_genome_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left; height:12em"><legend>Reference genome</legend>);
	say q(Enter accession number:<br />);
	say $q->textfield( -name => 'accession', -id => 'accession', -size => 10, -maxlength => 20 );
	say $self->get_tooltip(q(Reference genome - Use of a reference genome will override any locus or scheme settings.));
	say q(<br />);
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
	say $self->get_tooltip( q(Reference upload - File format is recognised by the extension in the )
		  . q(name.  Make sure your file has a standard extension, e.g. .gb, .embl, .fas.) );
	say q(</fieldset>);
	return;
}

sub _print_alignment_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left;height:12em"><legend>Alignments</legend><ul><li>);
	say $q->checkbox( -name => 'align', -id => 'align', -label => 'Produce alignments', -onChange => 'enable_seqs()' );
	say $self->get_tooltip( q(Alignments - Alignments will be produced in clustal format using the )
		  . q(selected aligner for any loci that vary between isolates. This may slow the analysis considerably.) );
	say q(</li><li>);
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
	say q(</li></ul></fieldset>);
	return;
}

sub _print_core_genome_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left;height:12em"><legend>Core genome analysis</legend><ul>);
	say q(<li><label for="core_threshold">Core threshold (%):</label>);
	say $q->popup_menu( -name => 'core_threshold', -id => 'core_threshold', -values => [ 80 .. 100 ], -default => 90 );
	say $self->get_tooltip( q(Core threshold - Percentage of isolates that locus must be present )
		  . q(in to be considered part of the core genome.) );
	say q(</li><li>);
	say $q->checkbox(
		-name     => 'calc_distances',
		-id       => 'calc_distances',
		-label    => 'Calculate mean distances',
		-onChange => 'enable_seqs()'
	);
	say $self->get_tooltip(
		q(Mean distance - This requires performing alignments of sequences so will take longer to perform.));
	say q(</li></ul></fieldset>);
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
	my $accession    = $params->{'accession'} || $params->{'annotation'};
	my $ref_upload   = $params->{'ref_upload'};
	my $user_genomes = $self->process_uploaded_genomes( $job_id, $isolate_ids, $params );
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
	if ( $accession || $ref_upload ) {
		$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Retrieving reference genome' } );
		my $seq_obj;
		if ($accession) {
			$accession =~ s/\s*//gx;
			my @local_annotations = glob("$params->{'dbase_config_dir'}/$params->{'db'}/annotations/$accession*");
			if (@local_annotations) {
				try {
					my $seqio_obj = Bio::SeqIO->new( -file => $local_annotations[0] );
					$seq_obj = $seqio_obj->next_seq;
				}
				catch {
					BIGSdb::Exception::Plugin->throw("Invalid data in local annotation $local_annotations[0].");
				};
			} else {
				my $seq_db = Bio::DB::GenBank->new;
				$seq_db->verbose(2);    #convert warn to exception
				try {
					my $str;
					open( my $fh, '>:encoding(utf8)', \$str ) || $logger->error('Cannot open file handle');

					#Temporarily suppress messages to STDERR
					{
						local *STDERR = $fh;
						$seq_obj = $seq_db->get_Seq_by_acc($accession);
					}
					close $fh;
				}
				catch {
					$logger->debug($_);
					BIGSdb::Exception::Plugin->throw("No data returned for accession number $accession.");
				};
			}
		} else {
			if ( $ref_upload =~ /fas$/x || $ref_upload =~ /fasta$/x ) {
				try {
					BIGSdb::Utils::fasta2genbank("$self->{'config'}->{'tmp_dir'}/$ref_upload");
				}
				catch {
					$logger->debug($_);
					my $error = q();
					if ( $_ =~ /(MSG.+)\n/x ) {
						$error = $1;
					}
					BIGSdb::Exception::Plugin->throw("Invalid data in uploaded reference FASTA file. $error");
				};
				$ref_upload =~ s/\.(fas|fasta)$/\.gb/x;
			}
			eval {
				my $seqio_object = Bio::SeqIO->new( -file => "$self->{'config'}->{'tmp_dir'}/$ref_upload" );
				$seq_obj = $seqio_object->next_seq;
			};
			if ($@) {
				BIGSdb::Exception::Plugin->throw('Invalid data in uploaded reference file.');
			}
		}
		return if !$seq_obj;
		$self->_analyse_by_reference(
			{
				job_id       => $job_id,
				accession    => $accession,
				seq_obj      => $seq_obj,
				ids          => $isolate_ids,
				user_genomes => $user_genomes
			}
		);
	} else {
		$self->_analyse_by_loci(
			{
				job_id       => $job_id,
				loci         => $loci,
				ids          => $isolate_ids,
				user_genomes => $user_genomes
			}
		);
	}
	return;
}

sub signal_kill_job {
	my ( $self, $job_id ) = @_;
	my $touch_file = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}.CANCEL";
	open( my $fh, '>', $touch_file ) || $logger->error("Cannot touch $touch_file");
	close $fh;
	return;
}

sub process_uploaded_genomes {
	my ( $self, $job_id, $isolate_ids, $params ) = @_;
	return if !$params->{'user_upload'};
	my $filename = "$self->{'config'}->{'tmp_dir'}/" . $params->{'user_upload'};
	if ( !-e $filename ) {
		BIGSdb::Exception::Plugin->throw('Uploaded data file not found.');
	}
	my $user_genomes = {};
	if ( $filename =~ /\.zip$/x ) {
		my $u = IO::Uncompress::Unzip->new($filename) or BIGSdb::Exception::Plugin->throw('Cannot open zip file.');
		my $status;
		for ( $status = 1 ; $status > 0 ; $status = $u->nextStream ) {
			my $stringfh_in;
			my ( $genome_name, $fasta_file );
			try {
				$fasta_file = $u->getHeaderInfo->{'Name'};
				( $genome_name = $fasta_file ) =~ s/\.(?:fas|fasta)$//x;
				my $buff;
				my $fasta;
				while ( ( $status = $u->read($buff) ) > 0 ) {
					$fasta .= $buff;
				}
				$stringfh_in = IO::String->new($fasta);
			}
			catch {
				BIGSdb::Exception::Plugin->throw('There is a problem with the contents of the zip file.');
			};
			try {
				my $seqin = Bio::SeqIO->new( -fh => $stringfh_in, -format => 'fasta' );
				while ( my $seq_object = $seqin->next_seq ) {
					my $seq = $seq_object->seq // '';
					$seq =~ s/[\-\.\s]//gx;
					push @{ $user_genomes->{$genome_name} }, { id => $seq_object->id, seq => $seq };
					$self->{'user_genomes'}->{$genome_name} = $seq_object->id;
				}
			}
			catch {
				BIGSdb::Exception::Plugin->throw("File $fasta_file in uploaded zip is not valid FASTA format.");
			};
			last if $status < 0;
		}
		BIGSdb::Exception::Plugin->throw("Error processing $filename: $!") if $status < 0;
	} else {
		try {
			( my $genome_name = $params->{'user_genome_filename'} ) =~ s/\.(?:fas|fasta)$//x;
			my $seqin = Bio::SeqIO->new( -file => $filename, -format => 'fasta' );
			while ( my $seq_object = $seqin->next_seq ) {
				my $seq = $seq_object->seq // '';
				$seq =~ s/[\-\.\s]//gx;
				push @{ $user_genomes->{$genome_name} }, { id => $seq_object->id, seq => $seq };
				$self->{'user_genomes'}->{$genome_name} = $seq_object->id;
			}
		}
		catch {
			BIGSdb::Exception::Plugin->throw('User genome file is not valid FASTA format.');
		};
	}
	$self->_create_temp_tables( $job_id, $isolate_ids, $user_genomes );
	return $user_genomes;
}

sub _create_temp_tables {
	my ( $self, $job_id, $isolate_ids, $user_genomes ) = @_;
	my $temp_list_table    = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $isolate_ids );
	my $isolate_table      = "${job_id}_isolates";
	my $isolate_table_view = "${job_id}_isolates_view";
	my $id                 = -1;
	my $map_id             = keys %$user_genomes;
	my $name_map           = {};
	my $reverse_name_map   = {};
	$self->{'db'}->do("CREATE TEMP table $isolate_table AS (SELECT * FROM $self->{'system'}->{'view'} LIMIT 0)");

	foreach my $genome_name ( reverse sort keys %$user_genomes ) {
		eval {
			$self->{'db'}->do( "INSERT INTO $isolate_table (id, $self->{'system'}->{'labelfield'}) VALUES (?,?)",
				undef, $id, $genome_name );
		};
		if ($@) {
			$logger->error('Invalid characters in user genome zip file.');
			BIGSdb::Exception::Plugin->throw('Invalid characters in uploaded zip file.');
		}
		unshift @$isolate_ids, $id;
		$name_map->{$id} = "u$map_id";
		$reverse_name_map->{"u$map_id"} = $id;
		$map_id--;
		$id--;
	}
	my $data = $self->{'datastore'}
	  ->run_query( "SELECT * FROM $isolate_table", undef, { fetch => 'all_arrayref', slice => {} } );
	$self->{'db'}->do( "CREATE TEMP view $isolate_table_view AS (SELECT i.* FROM $self->{'system'}->{'view'} i "
		  . "JOIN $temp_list_table t ON i.id=t.value) UNION SELECT * FROM $isolate_table" );
	$self->{'system'}->{'view'} = $isolate_table_view;
	$self->{'name_map'}         = $name_map;
	$self->{'reverse_name_map'} = $reverse_name_map;
	return;
}

sub _analyse_by_loci {
	my ( $self, $data ) = @_;
	my ( $job_id, $loci, $ids, $user_genomes, $worksheet ) =
	  @{$data}{qw(job_id loci ids user_genomes worksheet)};
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
	my $file_buffer = qq(Analysis against defined loci\n);
	$file_buffer .= q(Time: ) . ( localtime(time) ) . qq(\n\n);
	$file_buffer .=
	    q(Allele numbers are used where these have been defined, otherwise sequences will be )
	  . qq(marked as 'New#1, 'New#2' etc.\n)
	  . q(Missing alleles are marked as 'X'. Incomplete alleles (located at end of contig) )
	  . qq(are marked as 'I'.\n\n);
	my $scan_data = $self->assemble_data_for_defined_loci(
		{ job_id => $job_id, ids => $ids, user_genomes => $user_genomes, loci => $loci } );
	my $html_buffer = qq(<h3>Analysis against defined loci</h3>\n);
	if ( !$self->{'exit'} ) {
		$self->align( $job_id, 1, $ids, $scan_data );
		my $core_buffers = $self->_core_analysis( $scan_data, { ids => $ids, job_id => $job_id, by_reference => 0 } );
		my $table_cells = @$ids * @{ $scan_data->{'loci'} };
		if ( $table_cells <= MAX_DISPLAY_CELLS ) {
			$html_buffer .= $self->_get_html_output( 0, $ids, $scan_data );
			$self->{'jobManager'}->update_job_status( $job_id, { message_html => $html_buffer } );
		}
		my $dismat = $self->_generate_splits( $job_id, $scan_data );
		$self->_generate_excel_file(
			{
				job_id    => $job_id,
				by_ref    => 0,
				ids       => $ids,
				scan_data => $scan_data,
				dismat    => $dismat,
				core      => $core_buffers
			}
		);
		$file_buffer .= $self->_get_text_output( 0, $ids, $scan_data );
		$self->_output_file_buffer( $job_id, $file_buffer );
	}
	$self->delete_temp_files("$job_id*");
	return;
}

sub _analyse_by_reference {
	my ( $self, $data ) = @_;
	my ( $job_id, $accession, $seq_obj, $ids, $user_genomes, $worksheet ) =
	  @{$data}{qw(job_id accession seq_obj ids user_genomes worksheet)};
	my @cds;
	foreach my $feature ( $seq_obj->get_SeqFeatures ) {
		push @cds, $feature if $feature->primary_tag eq 'CDS';
	}
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
		BIGSdb::Exception::Plugin->throw('Invalid data in reference genome.');
	}
	if ( !@cds ) {
		BIGSdb::Exception::Plugin->throw('No loci defined in reference genome.');
	}
	my %abb = ( cds => 'coding regions' );
	my $html_buffer = q(<h3>Analysis by reference genome</h3>);
	$html_buffer .= q(<dl class="data">);
	my $td = 1;
	my $file_buffer = qq(Analysis by reference genome\n\nTime: ) . ( localtime(time) ) . qq(\n\n);
	foreach my $field (qw (accession version type length description cds)) {
		if ( $att{$field} ) {
			my $field_name = $abb{$field} // $field;
			$html_buffer .= qq(<dt>$field_name</dt><dd>$att{$field}</dd>\n);
			$file_buffer .= qq($field_name: $att{$field}\n);
			$td = $td == 1 ? 2 : 1;
		}
	}
	$html_buffer .= q(</dl>);
	$self->{'jobManager'}->update_job_status( $job_id, { message_html => $html_buffer } );
	my $max_ref_loci =
	  BIGSdb::Utils::is_int( $self->{'system'}->{'genome_comparator_max_ref_loci'} )
	  ? $self->{'system'}->{'genome_comparator_max_ref_loci'}
	  : MAX_REF_LOCI;
	if ( @cds > $max_ref_loci ) {
		my $nice_limit = BIGSdb::Utils::get_nice_size( $self->{'config'}->{'max_upload_size'} );
		my $cds_count  = @cds;
		BIGSdb::Exception::Plugin->throw( qq(Too many loci in reference genome - limit is set at $max_ref_loci. )
			  . qq(Your uploaded reference contains $cds_count loci.  Please note also that the uploaded )
			  . qq(reference is limited to $nice_limit (larger uploads will be truncated).) );
	}
	my $scan_data = $self->_assemble_data_for_reference_genome(
		{ job_id => $job_id, ids => $ids, user_genomes => $user_genomes, cds => \@cds } );
	if ( !$self->{'exit'} ) {
		$self->align( $job_id, 1, $ids, $scan_data );
		my $core_buffers = $self->_core_analysis( $scan_data, { ids => $ids, job_id => $job_id, by_reference => 1 } );
		my $table_cells = @$ids * @{ $scan_data->{'loci'} };
		if ( $table_cells <= MAX_DISPLAY_CELLS ) {
			$html_buffer .= $self->_get_html_output( 1, $ids, $scan_data );
			$self->{'jobManager'}->update_job_status( $job_id, { message_html => $html_buffer } );
		}
		$file_buffer .= $self->_get_text_output( 1, $ids, $scan_data );
		$self->_output_file_buffer( $job_id, $file_buffer );
		my $dismat = $self->_generate_splits( $job_id, $scan_data );
		$self->_generate_excel_file(
			{
				job_id    => $job_id,
				by_ref    => 1,
				ids       => $ids,
				scan_data => $scan_data,
				dismat    => $dismat,
				core      => $core_buffers
			}
		);
	}
	$self->delete_temp_files("$job_id*");
	return;
}

sub _get_text_underlined {
	my ( $self, $title ) = @_;
	my $buffer = qq($title\n);
	$buffer .= q(-) x length($title) . qq(\n\n);
	return $buffer;
}

sub _get_text_output {
	my ( $self, $by_ref, $ids, $scan_data ) = @_;
	my $buffer = qq(\n);
	$buffer .= $self->_get_text_underlined('All loci');
	if ($by_ref) {
		$buffer .=
		    qq(Each unique allele is defined a number starting at 1. Missing alleles are marked as 'X'. \n)
		  . qq(Incomplete alleles (located at end of contig) are marked as 'I'.\n\n);
	}
	$buffer .= $self->_get_text_table( $by_ref, $ids, $scan_data, $scan_data->{'loci'} );
	my $variable_count = @{ $scan_data->{'variable'} };
	if ($variable_count) {
		$buffer .= $self->_get_text_underlined('Loci with sequence differences among isolates');
		$buffer .= qq(Variable loci: $variable_count\n\n);
		$buffer .= $self->_get_text_table( $by_ref, $ids, $scan_data, $scan_data->{'variable'} );
	}
	my $missing_count = @{ $scan_data->{'missing_in_all'} };
	if ($missing_count) {
		$buffer .= $self->_get_text_underlined('Loci missing in all isolates');
		$buffer .= qq(Missing loci: $missing_count\n\n);
		$buffer .= $self->_get_text_table( $by_ref, $ids, $scan_data, $scan_data->{'missing_in_all'} );
	}
	my $identical_count = @{ $scan_data->{'identical_in_all'} };
	if ($identical_count) {
		$buffer .= $self->_get_text_underlined('Exactly matching loci');
		$buffer .= qq(Matches: $identical_count\n\n);
		$buffer .= $self->_get_text_table( $by_ref, $ids, $scan_data, $scan_data->{'identical_in_all'} );
	}
	if ($by_ref) {
		my $identical_except_ref_count = @{ $scan_data->{'identical_in_all_except_ref'} };
		if ($identical_except_ref_count) {
			$buffer .= $self->_get_text_underlined(
				'Loci exactly the same in all compared genomes with possible exception of the reference');
			$buffer .= qq(Matches: $identical_except_ref_count\n\n);
			$buffer .= $self->_get_text_table( $by_ref, $ids, $scan_data, $scan_data->{'identical_in_all_except_ref'} );
		}
	}
	my $incomplete_count = @{ $scan_data->{'incomplete_in_some'} };
	if ($incomplete_count) {
		$buffer .= $self->_get_text_underlined('Loci that are incomplete in some isolates');
		$buffer .= qq(Incomplete: $incomplete_count\n\n);
		$buffer .= $self->_get_text_table( $by_ref, $ids, $scan_data, $scan_data->{'incomplete_in_some'} );
	}
	$buffer .= $self->_get_unique_strain_text_table( $ids, $scan_data );
	$buffer .= $self->_get_paralogous_loci_text_table( $ids, $scan_data );
	return $buffer;
}

sub _output_file_buffer {
	my ( $self, $job_id, $buffer ) = @_;
	my $job_file = "$self->{'config'}->{'tmp_dir'}/$job_id.txt";
	open( my $job_fh, '>:encoding(utf8)', $job_file ) || $logger->error("Cannot open $job_file for writing");
	say $job_fh $buffer;
	close $job_fh;
	$self->{'jobManager'}
	  ->update_job_output( $job_id, { filename => "$job_id.txt", description => '01_Text output file' } );
	return;
}

sub _get_html_output {
	my ( $self, $by_ref, $ids, $scan_data ) = @_;
	my $buffer;
	$buffer .= q(<h3>All loci</h3>);
	if ($by_ref) {
		$buffer .=
		    q(<p>Each unique allele is defined a number starting at 1. Missing alleles are marked as )
		  . q(<span style="background:black; color:white; padding: 0 0.5em">'X'</span>. Incomplete alleles )
		  . q((located at end of contig) are marked as )
		  . q(<span style="background:green; color:white; padding: 0 0.5em">'I'</span>.</p>);
	} else {
		$buffer .=
		    q(<p>Allele numbers are used where these have been defined, otherwise sequences )
		  . q(will be marked as 'New#1, 'New#2' etc. Missing alleles are marked as )
		  . q(<span style="background:black; color:white; padding: 0 0.5em">'X'</span>. Incomplete alleles )
		  . q((located at end of contig) are marked as )
		  . q(<span style="background:green; color:white; padding: 0 0.5em">'I'</span>.</p>);
	}
	$buffer .= $self->_get_html_table( $by_ref, $ids, $scan_data, $scan_data->{'loci'} );
	my $variable_count = @{ $scan_data->{'variable'} };
	if ($variable_count) {
		$buffer .= q(<h3>Loci with sequence differences among isolates</h3>);
		$buffer .= qq(<p>Variable loci: $variable_count</p>);
		$buffer .= $self->_get_html_table( $by_ref, $ids, $scan_data, $scan_data->{'variable'} );
	}
	my $missing_count = @{ $scan_data->{'missing_in_all'} };
	if ($missing_count) {
		$buffer .= q(<h3>Loci missing in all isolates</h3>);
		$buffer .= qq(<p>Missing loci: $missing_count</p>);
		$buffer .= $self->_get_html_table( $by_ref, $ids, $scan_data, $scan_data->{'missing_in_all'} );
	}
	my $identical_count = @{ $scan_data->{'identical_in_all'} };
	if ($identical_count) {
		$buffer .= q(<h3>Exactly matching loci</h3>);
		$buffer .= q(<p>These loci are identical in all isolates.</p>);
		$buffer .= qq(<p>Matches: $identical_count</p>);
		$buffer .= $self->_get_html_table( $by_ref, $ids, $scan_data, $scan_data->{'identical_in_all'} );
	}
	if ($by_ref) {
		my $identical_except_ref_count = @{ $scan_data->{'identical_in_all_except_ref'} };
		if ($identical_except_ref_count) {
			$buffer .=
			  q(<h3>Loci exactly the same in all compared genomes with possible exception of the reference</h3>);
			$buffer .= qq(<p>Matches: $identical_except_ref_count</p>);
			$buffer .= $self->_get_html_table( $by_ref, $ids, $scan_data, $scan_data->{'identical_in_all_except_ref'} );
		}
	}
	my $incomplete_count = @{ $scan_data->{'incomplete_in_some'} };
	if ($incomplete_count) {
		$buffer .= q(<h3>Loci that are incomplete in some isolates</h3>);
		$buffer .= q(<p>These loci are incomplete and located at the ends of contigs in at least one isolate.</p>);
		$buffer .= qq(<p>Matches: $incomplete_count</p>);
		$buffer .= $self->_get_html_table( $by_ref, $ids, $scan_data, $scan_data->{'incomplete_in_some'} );
	}
	$buffer .= $self->_get_unique_strain_html_table( $ids, $scan_data );
	$buffer .= $self->_get_paralogous_loci_html_table( $ids, $scan_data );
	return $buffer;
}

sub _get_html_table {
	my ( $self, $by_ref, $ids, $scan_data, $loci ) = @_;
	my $total_records = @$ids;
	$total_records++ if $by_ref;
	my $buffer = q(<div class="scrollable"><table class="resultstable">);
	$buffer .= $self->_get_isolate_table_header( $by_ref, $ids, 'html' );
	my $td = 1;
	foreach my $locus (@$loci) {
		my %value_colour;
		my $locus_data = $scan_data->{'locus_data'}->{$locus};
		$buffer .= qq(<tr class="td$td">);
		if ($by_ref) {
			my $length = length( $locus_data->{'sequence'} );
			$buffer .= qq(<td>$locus_data->{'full_name'}</td><td>$locus_data->{'description'}</td>)
			  . qq(<td>$length</td><td>$locus_data->{'start'}</td>);
		} else {
			my $locus_name = $self->clean_locus($locus);
			my $desc       = $self->{'datastore'}->get_locus($locus)->get_description;
			$desc->{$_} //= q() foreach (qw(full_name product));
			$buffer .= qq(<td>$locus_name</td><td>$desc->{'full_name'}</td><td>$desc->{'product'}</td>);
		}
		my $colour = 0;
		if ($by_ref) {
			$colour++;
			$value_colour{'1'} = $colour;
			my $formatted_value = $self->_get_html_formatted_value( '1', $value_colour{'1'}, $total_records );
			$buffer .= $formatted_value;
		}
		foreach my $isolate_id (@$ids) {
			my $value = $scan_data->{'isolate_data'}->{$isolate_id}->{'designations'}->{$locus};
			if ( !$value_colour{$value} ) {
				$colour++;
				$value_colour{$value} = $colour;
			}
			my $formatted_value = $self->_get_html_formatted_value( $value, $value_colour{$value}, $total_records );
			$buffer .= $formatted_value;
		}
		$buffer .= qq(</tr>\n);
		$td = $td == 1 ? 2 : 1;
	}
	$buffer .= q(</table></div>);
	return $buffer;
}

sub _get_text_table {
	my ( $self, $by_ref, $ids, $scan_data, $loci ) = @_;
	my $buffer = $self->_get_isolate_table_header( $by_ref, $ids, 'text' );
	foreach my $locus (@$loci) {
		my $locus_data = $scan_data->{'locus_data'}->{$locus};
		if ($by_ref) {
			my $length = length( $locus_data->{'sequence'} );
			$buffer .= qq($locus_data->{'full_name'}\t$locus_data->{'description'}\t$length\t$locus_data->{'start'});
		} else {
			my $locus_name = $self->clean_locus( $locus, { text_output => 1 } );
			my $desc = $self->{'datastore'}->get_locus($locus)->get_description;
			$desc->{$_} //= q() foreach (qw(full_name product));
			$buffer .= qq($locus_name\t$desc->{'full_name'}\t$desc->{'product'});
		}
		if ($by_ref) {
			$buffer .= qq(\t1);
		}
		foreach my $isolate_id (@$ids) {
			my $value = $scan_data->{'isolate_data'}->{$isolate_id}->{'designations'}->{$locus};
			$value = 'X' if $value eq 'missing';
			$value = 'I' if $value eq 'incomplete';
			$buffer .= qq(\t$value);
		}
		$buffer .= qq(\n);
	}
	$buffer .= qq(\n###\n\n);
	return $buffer;
}

sub _get_html_formatted_value {
	my ( $self, $value, $colour, $id_count ) = @_;
	my %formatted = (
		incomplete => q(<td style="background:green;color:white">I</td>),
		missing    => q(<td style="background:black;color:white">X</td>)
	);
	if ( $formatted{$value} ) {
		return $formatted{$value};
	}
	my $style = BIGSdb::Utils::get_heatmap_colour_style( $colour, $id_count );
	return qq(<td style="$style">$value</td>);
}

sub _get_unique_strain_html_table {
	my ( $self, $ids, $data ) = @_;
	my $buffer       = q(<h3>Unique strains</h3>);
	my $strain_count = keys %{ $data->{'unique_strains'}->{'strain_counts'} };
	$buffer .= qq(<p>Unique strains: $strain_count</p>);
	$buffer .= q(<div class="scrollable"><table class="resultstable">);
	my @strain_hashes =
	  sort { $data->{'unique_strains'}->{'strain_counts'}->{$b} <=> $data->{'unique_strains'}->{'strain_counts'}->{$a} }
	  keys %{ $data->{'unique_strains'}->{'strain_counts'} };
	my $strain_num = 1;
	$buffer .= q(<tr>);

	foreach my $strain (@strain_hashes) {
		$buffer .= qq(<th>Strain $strain_num</th>);
		$strain_num++;
	}
	$buffer .= q(</tr><tr>);
	my $td = 1;
	foreach my $hash (@strain_hashes) {
		my $isolates        = $data->{'unique_strains'}->{'strain_isolates'}->{$hash};
		my @mapped_isolates = @$isolates;
		foreach my $isolate (@mapped_isolates) {
			if ( $isolate =~ /^(-\d+)/x ) {
				my $isolate_id = $1;
				my $mapped_id = $self->{'name_map'}->{$isolate_id} // $isolate_id;
				$isolate =~ s/$isolate_id/$mapped_id/x;
			}
		}
		local $" = q(<br />);
		$buffer .= qq(<td class="td$td">@mapped_isolates</td>);
		$td = $td == 1 ? 2 : 1;
	}
	$buffer .= q(</tr></table></div>);
	return $buffer;
}

sub _get_paralogous_loci_html_table {
	my ( $self, $ids, $data ) = @_;
	my $loci = $data->{'paralogous_in_all'};
	return q() if !@$loci;
	my $buffer = q(<h3>Potentially paralogous loci</h3>);
	$buffer .= q(<p>The table shows the loci that had multiple hits in every isolate )
	  . q((except those where the locus was absent).</p>);
	my $count = @$loci;
	$buffer .= qq(<p>Paralogous: $count</p>);
	$buffer .= q(<div class="scrollable"><table class="resultstable">);
	$buffer .= q(<tr><th>Locus</th><th>Isolate count</th></tr>);
	my $td = 1;

	foreach my $locus (@$loci) {
		my $isolate_count = $data->{'paralogous'}->{$locus};
		$buffer .= qq(<tr class="td$td"><td>$locus</td><td>$isolate_count</td></tr>);
		$td = $td == 1 ? 2 : 1;
	}
	$buffer .= q(</table></div>);
	return $buffer;
}

sub _get_unique_strain_text_table {
	my ( $self, $ids, $data ) = @_;
	my $buffer       = $self->_get_text_underlined('Unique strains');
	my $strain_count = keys %{ $data->{'unique_strains'}->{'strain_counts'} };
	$buffer .= qq(Unique strains: $strain_count\n\n);
	my @strain_hashes =
	  sort { $data->{'unique_strains'}->{'strain_counts'}->{$b} <=> $data->{'unique_strains'}->{'strain_counts'}->{$a} }
	  keys %{ $data->{'unique_strains'}->{'strain_counts'} };
	my $strain_num = 1;
	foreach my $strain (@strain_hashes) {
		$buffer .= qq(Strain $strain_num:\n);
		my $isolates        = $data->{'unique_strains'}->{'strain_isolates'}->{$strain};
		my @mapped_isolates = @$isolates;
		foreach my $isolate (@mapped_isolates) {
			if ( $isolate =~ /^(-\d+)/x ) {
				my $isolate_id = $1;
				my $mapped_id = $self->{'name_map'}->{$isolate_id} // $isolate_id;
				$isolate =~ s/$isolate_id/$mapped_id/x;
			}
		}
		foreach my $isolate (@mapped_isolates) {
			$buffer .= qq($isolate\n);
		}
		$buffer .= qq(\n);
		$strain_num++;
	}
	$buffer .= qq(###\n\n);
	return $buffer;
}

sub _get_paralogous_loci_text_table {
	my ( $self, $ids, $data ) = @_;
	my $loci = $data->{'paralogous_in_all'};
	return q() if !@$loci;
	my $buffer = $self->_get_text_underlined('Potentially paralogous loci');
	$buffer .= q(The table shows the loci that had multiple hits in every isolate )
	  . qq((except those where the locus was absent).\n\n);
	my $count = @$loci;
	$buffer .= qq(Paralogous: $count\n\n);
	$buffer .= qq(Locus\tIsolate count\n);

	foreach my $locus (@$loci) {
		my $isolate_count = $data->{'paralogous'}->{$locus};
		$buffer .= qq($locus\t$isolate_count\n);
	}
	return $buffer;
}

sub _get_isolate_table_header {
	my ( $self, $by_reference, $ids, $format ) = @_;
	my @header = 'Locus';
	if ($by_reference) {
		push @header, ( 'Product', 'Sequence length', ' Genome position', 'Reference genome' );
	} else {
		push @header, ( 'Full name', 'Product' );
	}
	foreach my $id (@$ids) {
		my $isolate = $self->_get_isolate_name($id);
		my $mapped_id = $self->{'name_map'}->{$id} // $id;
		$isolate =~ s/^$id/$mapped_id/x;
		push @header, $isolate;
	}
	if ( $format eq 'html' ) {
		local $" = q(</th><th>);
		return qq(<tr><th>@header</th></tr>);
	} else {
		local $" = qq(\t);
		return qq(@header\n);
	}
	return;
}

sub _get_isolate_name {
	my ( $self, $id, $options ) = @_;
	my $isolate = $self->{'name_map'}->{$id} // $id;
	if ( $options->{'name_only'} ) {
		if ( !$options->{'no_name'} ) {
			my $name = $self->{'datastore'}->get_isolate_field_values($id)->{ $self->{'system'}->{'labelfield'} };
			$isolate .= "|$name" if $name;
		}
		return $isolate;
	}
	my $additional_fields = $self->_get_identifier( $id, { no_id => 1 } );
	$isolate .= " ($additional_fields)" if $additional_fields;
	return $isolate;
}

sub _get_identifier {
	my ( $self, $id, $options ) = @_;
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
				$field_value = $include_data->{$field} // q();
			}
			$field_value =~ tr/[\(\):, ]/_/;
			$value .= '|' if !$first || !$options->{'no_id'};
			$first = 0;
			$value .= $field_value;
		}
	}
	return $value;
}

sub _generate_splits {
	my ( $self, $job_id, $data ) = @_;
	$self->{'jobManager'}
	  ->update_job_status( $job_id, { percent_complete => 80, stage => 'Generating distance matrix' } );
	my $dismat  = $self->_generate_distance_matrix($data);
	my $options = {
		truncated          => $self->{'params'}->{'truncated'},
		exclude_paralogous => $self->{'params'}->{'exclude_paralogous'},
		by_reference       => $data->{'by_ref'}
	};
	my $nexus_file = $self->_make_nexus_file( $job_id, $dismat, $options );
	$self->{'jobManager'}->update_job_output(
		$job_id,
		{
			filename    => $nexus_file,
			description => '20_Distance matrix (Nexus format)|Suitable for loading in to '
			  . '<a href="http://www.splitstree.org">SplitsTree</a>. Distances between taxa are '
			  . 'calculated as the number of loci with different allele sequences'
		}
	);
	return $dismat if ( keys %{ $data->{'isolate_data'} } ) > MAX_SPLITS_TAXA;
	$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => 90, stage => 'Generating NeighborNet' } );
	my $splits_img = "$job_id.png";
	$self->_run_splitstree( "$self->{'config'}->{'tmp_dir'}/$nexus_file",
		"$self->{'config'}->{'tmp_dir'}/$splits_img", 'PNG' );

	if ( -e "$self->{'config'}->{'tmp_dir'}/$splits_img" ) {
		$self->{'jobManager'}->update_job_output( $job_id,
			{ filename => $splits_img, description => '25_Splits graph (Neighbour-net; PNG format)' } );
	}
	$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => 95 } );
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
	return $dismat;
}

sub _generate_distance_matrix {
	my ( $self, $data ) = @_;
	my $dismat       = {};
	my $isolate_data = $data->{'isolate_data'};
	my $ignore_loci  = [];
	push @$ignore_loci, @{ $data->{'incomplete_in_some'} }
	  if ( $self->{'params'}->{'truncated'} // '' ) eq 'exclude';
	push @$ignore_loci, @{ $data->{'paralogous_in_all'} } if $self->{'params'}->{'exclude_paralogous'};
	my %ignore_loci = map { $_ => 1 } @$ignore_loci;
	if ( $data->{'by_ref'} ) {

		foreach my $locus ( @{ $data->{'loci'} } ) {
			$isolate_data->{0}->{'designations'}->{$locus} = '1';
		}
	}
	my @ids = sort { $a <=> $b } keys %$isolate_data;
	foreach my $i ( 0 .. @ids - 1 ) {
		foreach my $j ( 0 .. $i ) {
			$dismat->{ $ids[$i] }->{ $ids[$j] } = 0;
			foreach my $locus ( @{ $data->{'loci'} } ) {
				next if $ignore_loci{$locus};
				my $i_value = $isolate_data->{ $ids[$i] }->{'designations'}->{$locus};
				my $j_value = $isolate_data->{ $ids[$j] }->{'designations'}->{$locus};
				if ( $self->_is_different( $i_value, $j_value ) ) {
					$dismat->{ $ids[$i] }->{ $ids[$j] }++;
				}
			}
		}
	}
	return $dismat;
}

#Helper for distance matrix generation
sub _is_different {
	my ( $self, $i_value, $j_value ) = @_;
	my $different;
	if ( $i_value ne $j_value ) {
		if ( ( $self->{'params'}->{'truncated'} // q() ) eq 'pairwise_same' ) {
			if (   ( $i_value eq 'incomplete' && $j_value eq 'missing' )
				|| ( $i_value eq 'missing' && $j_value eq 'incomplete' )
				|| ( $i_value ne 'incomplete' && $j_value ne 'incomplete' ) )
			{
				$different = 1;
			}
		} else {
			$different = 1;
		}
	}
	return $different;
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
			my $mapped_id = $self->{'name_map'}->{$id} // $id;
			$labels{$id} =~ s/^$id/$mapped_id/x;
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
	open( my $nexus_fh, '>:encoding(utf8)', "$self->{'config'}->{'tmp_dir'}/$job_id.nex" )
	  || $logger->error("Cannot open $job_id.nex for writing");
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

sub _run_splitstree {
	my ( $self, $nexus_file, $output_file, $format ) = @_;
	if ( $self->{'config'}->{'splitstree_path'} && -x $self->{'config'}->{'splitstree_path'} ) {
		my $cmd =
		    qq($self->{'config'}->{'splitstree_path'} -g true -S true -x )
		  . qq('EXECUTE FILE=$nexus_file;EXPORTGRAPHICS format=$format file=$output_file REPLACE=yes;QUIT' )
		  . q(> /dev/null 2>&1);
		system($cmd);
	}
	return;
}

sub _is_isolate_name_selected {
	my ($self) = @_;
	my @includes;
	@includes = split /\|\|/x, $self->{'params'}->{'includes'} if $self->{'params'}->{'includes'};
	my %includes = map { $_ => 1 } @includes;
	return 1 if $includes{ $self->{'system'}->{'labelfield'} };
	return;
}

sub align {
	my ( $self, $job_id, $by_ref, $ids, $scan_data, $no_output ) = @_;
	my $params = $self->{'params'};
	return if !$params->{'align'};
	my $align_file       = "$self->{'config'}->{'tmp_dir'}/$job_id.align";
	my $align_stats_file = "$self->{'config'}->{'tmp_dir'}/$job_id.align_stats";
	my $xmfa_file        = "$self->{'config'}->{'tmp_dir'}/$job_id.xmfa";
	my $core_xmfa_file   = "$self->{'config'}->{'tmp_dir'}/${job_id}_core.xmfa";
	state $xmfa_start = 1;
	state $xmfa_end   = 1;
	my $temp                  = BIGSdb::Utils::get_random();
	my $loci                  = $params->{'align_all'} ? $scan_data->{'loci'} : $scan_data->{'variable'};
	my $progress_start        = 20;
	my $progress_total        = 50;
	my $locus_count           = 0;
	my $isolate_name_selected = $self->_is_isolate_name_selected;

	foreach my $locus (@$loci) {
		last if $self->{'exit'};
		my $progress = int( ( $progress_total * $locus_count ) / @$loci ) + $progress_start;
		$self->{'jobManager'}
		  ->update_job_status( $job_id, { percent_complete => $progress, stage => "Aligning locus: $locus" } );
		$locus_count++;
		( my $escaped_locus = $locus ) =~ s/[\/\|\']/_/gx;
		$escaped_locus =~ tr/ /_/;
		my $fasta_file  = "$self->{'config'}->{'secure_tmp_dir'}/${temp}_$escaped_locus.fasta";
		my $aligned_out = "$self->{'config'}->{'secure_tmp_dir'}/${temp}_$escaped_locus.aligned";
		my $seq_count   = 0;
		open( my $fasta_fh, '>:encoding(utf8)', $fasta_file ) || $logger->error("Cannot open $fasta_file for writing");
		my $names        = {};
		my $ids_to_align = [];

		if ( $by_ref && $params->{'include_ref'} ) {
			push @$ids_to_align, 'ref';
			$names->{'ref'} = 'ref';
			say $fasta_fh '>ref';
			say $fasta_fh $scan_data->{'locus_data'}->{$locus}->{'sequence'};
		}
		foreach my $id (@$ids) {
			push @$ids_to_align, $id;
			my $name = $self->_get_isolate_name( $id, { name_only => 1, no_name => !$isolate_name_selected } );
			$name =~ s/[\(\)]//gx;
			$name =~ tr/[:,. ]/_/;
			my $identifier = $self->{'name_map'}->{$id} // $id;
			$names->{$identifier} = $name;
			my $seq = $scan_data->{'isolate_data'}->{$id}->{'sequences'}->{$locus};
			if ($seq) {
				$seq_count++;
				say $fasta_fh ">$identifier";
				say $fasta_fh $seq;
			}
		}
		close $fasta_fh;
		my $core_threshold =
		  BIGSdb::Utils::is_int( $params->{'core_threshold'} ) ? $params->{'core_threshold'} : 100;
		my $core_locus = ( $scan_data->{'frequency'}->{$locus} * 100 / @$ids ) >= $core_threshold ? 1 : 0;
		$self->{'distances'}->{$locus} = $self->_run_alignment(
			{
				ids              => $ids_to_align,
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
				names            => $names,
				infoalign        => $no_output ? 0 : 1
			}
		);
		unlink $fasta_file;
	}
	return if $no_output;
	if ( -e $align_file && !-z $align_file ) {
		$self->{'jobManager'}->update_job_output( $job_id,
			{ filename => "${job_id}.align", description => '30_Alignments', compress => 1 } );
	}
	if ( -e $align_stats_file && !-z $align_stats_file ) {
		$self->{'jobManager'}->update_job_output( $job_id,
			{ filename => "${job_id}.align_stats", description => '31_Alignment stats', compress => 1 } );
	}
	if ( -e "$self->{'config'}->{'tmp_dir'}/${job_id}.xmfa" ) {
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
			$self->{'jobManager'}
			  ->update_job_status( $job_id, { stage => 'Converting XMFA to FASTA', percent_complete => 70 } );
			my $fasta_file =
			  BIGSdb::Utils::xmfa2fasta( "$self->{'config'}->{'tmp_dir'}/${job_id}.xmfa", { integer_ids => 1 } );
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
		catch {
			if ( $_->isa('BIGSdb::Exception::File::CannotOpen') ) {
				$logger->error('Cannot create FASTA file from XMFA.');
			} else {
				$logger->logdie($_);
			}
		};
	}
	if ( -e "$self->{'config'}->{'tmp_dir'}/${job_id}_core.xmfa" ) {
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
			$self->{'jobManager'}
			  ->update_job_status( $job_id, { stage => 'Converting core XMFA to FASTA', percent_complete => 75 } );
			my $fasta_file =
			  BIGSdb::Utils::xmfa2fasta( "$self->{'config'}->{'tmp_dir'}/${job_id}_core.xmfa", { integer_ids => 1 } );
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
		catch {
			if ( $_->isa('BIGSdb::Exception::File::CannotOpen') ) {
				$logger->error('Cannot create core FASTA file from XMFA.');
			} else {
				$logger->logdie($_);
			}
		};
	}
	return;
}

sub _run_alignment {
	my ( $self, $args ) = @_;
	my (
		$ids,        $names,         $locus,    $seq_count,      $aligned_out,
		$fasta_file, $align_file,    $xmfa_out, $xmfa_start_ref, $xmfa_end_ref,
		$core_locus, $core_xmfa_out, $infoalign
	  )
	  = @{$args}{
		qw (ids names locus seq_count aligned_out fasta_file align_file xmfa_out
		  xmfa_start_ref xmfa_end_ref core_locus core_xmfa_out infoalign)
	  };
	return if $seq_count <= 1;
	my $params = $self->{'params'};
	if ( $params->{'aligner'} eq 'MAFFT' && $self->{'config'}->{'mafft_path'} && -e $fasta_file && -s $fasta_file ) {
		my $threads =
		  BIGSdb::Utils::is_int( $self->{'config'}->{'mafft_threads'} ) ? $self->{'config'}->{'mafft_threads'} : 1;
		system( "$self->{'config'}->{'mafft_path'} --thread $threads --quiet "
			  . "--preservecase --clustalout $fasta_file > $aligned_out" );
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
			my $id = $seq->id;
			$xmfa_buffer .= ">$names->{$id}:$$xmfa_start_ref-$$xmfa_end_ref + $clean_locus\n";
			my $sequence = BIGSdb::Utils::break_line( $seq->seq, 60 );
			$xmfa_buffer .= "$sequence\n";
			$id_has_seq{$id} = 1;
			$seq_length = $seq->length if !$seq_length;
		}
		my $missing_seq = BIGSdb::Utils::break_line( ( '-' x $seq_length ), 60 );
		foreach my $id (@$ids) {
			my $identifier = $self->{'name_map'}->{$id} // $id;
			next if $id_has_seq{$identifier};
			$xmfa_buffer .= ">$names->{$identifier}:$$xmfa_start_ref-$$xmfa_end_ref + $clean_locus\n$missing_seq\n";
		}
		$xmfa_buffer .= '=';
		open( my $fh_xmfa, '>>:encoding(utf8)', $xmfa_out )
		  or $logger->error("Can't open output file $xmfa_out for appending");
		say $fh_xmfa $xmfa_buffer if $xmfa_buffer;
		close $fh_xmfa;
		if ($core_locus) {
			open( my $fh_core_xmfa, '>>:encoding(utf8)', $core_xmfa_out )
			  or $logger->error("Can't open output file $core_xmfa_out for appending");
			say $fh_core_xmfa $xmfa_buffer if $xmfa_buffer;
			close $fh_core_xmfa;
		}
		$$xmfa_start_ref = $$xmfa_end_ref + 1;
		open( my $align_fh, '>>:encoding(utf8)', $align_file )
		  || $logger->error("Can't open $align_file for appending");
		my $heading_locus = $self->clean_locus( $locus, { text_output => 1 } );
		say $align_fh "$heading_locus";
		say $align_fh '-' x ( length $heading_locus ) . "\n";
		close $align_fh;
		BIGSdb::Utils::append( $aligned_out, $align_file, { blank_after => 1 } );
		$args->{'alignment'} = $aligned_out;
		$distance = $self->_run_infoalign($args) if $infoalign;
		unlink $aligned_out;
	}
	return $distance;
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

sub _generate_excel_file {
	my ( $self, $args ) = @_;
	my ( $job_id, $by_ref, $ids, $scan_data, $dismat, $core ) =
	  @{$args}{qw(job_id by_ref ids scan_data dismat core)};
	$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Generating Excel file' } );
	open( my $excel_fh, '>', \my $excel )
	  || $logger->error("Failed to open excel filehandle: $!");    #Store Excel file in scalar $excel
	my $excel_data = \$excel;
	my $workbook   = Excel::Writer::XLSX->new($excel_fh);
	$workbook->set_tempdir( $self->{'config'}->{'secure_tmp_dir'} );
	$workbook->set_optimization;                                   #Reduce memory usage
	my $formats = {};
	$formats->{'header'} = $workbook->add_format(
		bg_color     => 'navy',
		color        => 'white',
		bold         => 1,
		align        => 'center',
		border       => 1,
		border_color => 'white'
	);
	$formats->{'locus'} = $workbook->add_format(
		bg_color     => '#D0D0D0',
		color        => 'black',
		align        => 'center',
		border       => 1,
		border_color => '#A0A0A0'
	);
	$formats->{'I'} = $workbook->add_format(
		bg_color     => 'green',
		color        => 'white',
		align        => 'center',
		border       => 1,
		border_color => 'white'
	);
	$formats->{'X'} = $workbook->add_format(
		bg_color     => 'black',
		color        => 'white',
		align        => 'center',
		border       => 1,
		border_color => 'white'
	);
	$formats->{'normal'}     = $workbook->add_format( align => 'center' );
	$formats->{'left-align'} = $workbook->add_format( align => 'left' );
	$args->{'workbook'}      = $workbook;
	$args->{'formats'}       = $formats;
	my $locus_set = {
		'all'             => $scan_data->{'loci'},
		'variable'        => $scan_data->{'variable'},
		'missing in all'  => $scan_data->{'missing_in_all'},
		'same in all'     => $scan_data->{'identical_in_all'},
		'same except ref' => $scan_data->{'identical_in_all_except_ref'},
		'incomplete'      => $scan_data->{'incomplete_in_some'}
	};

	foreach my $tab ( 'all', 'variable', 'missing in all', 'same in all', 'same except ref', 'incomplete' ) {
		next if $tab eq 'same except ref' && !$by_ref;
		$args->{'loci'} = $locus_set->{$tab};
		$args->{'tab'}  = $tab;
		$self->_write_excel_table_worksheet($args);
	}
	$self->_write_excel_unique_strains($args);
	$self->_write_excel_paralogous_loci($args);
	$self->_write_excel_distance_matrix( $dismat, $args );
	$self->_write_excel_core_analysis( $core, $args );
	$self->_write_excel_parameters($args);
	$self->_write_excel_citations($args);
	$workbook->close;
	my $excel_file = "$self->{'config'}->{'tmp_dir'}/$job_id.xlsx";
	open( $excel_fh, '>', $excel_file ) || $logger->error("Cannot open $excel_file for writing.");
	binmode $excel_fh;
	print $excel_fh $$excel_data;
	close $excel_fh;

	if ( -e $excel_file ) {
		$self->{'jobManager'}
		  ->update_job_output( $job_id, { filename => "$job_id.xlsx", description => '02_Excel format output' } );
	}
	return;
}

sub _write_excel_table_worksheet {
	my ( $self, $args ) = @_;
	my ( $workbook, $formats, $tab, $by_ref, $ids, $scan_data, $loci ) =
	  @{$args}{qw(workbook formats tab by_ref ids scan_data loci)};
	return if !@$loci;
	my $total_records = @$ids;
	$total_records++ if $by_ref;
	my @header = 'Locus';
	if ($by_ref) {
		push @header, ( 'Product', 'Sequence length', ' Genome position', 'Reference genome' );
	} else {
		push @header, ( 'Full name', 'Product' );
	}
	foreach my $id (@$ids) {
		my $isolate = $self->_get_isolate_name($id);
		my $mapped_id = $self->{'name_map'}->{$id} // $id;
		$isolate =~ s/^$id/$mapped_id/x;
		push @header, $isolate;
	}
	my $worksheet     = $workbook->add_worksheet($tab);
	my $col           = 0;
	my $col_max_width = {};
	foreach my $heading (@header) {
		$worksheet->write( 0, $col, $heading, $formats->{'header'} );
		if ( length $heading > ( $col_max_width->{$col} // 0 ) ) {
			$col_max_width->{$col} = length $heading;
		}
		$col++;
	}
	$worksheet->freeze_panes( 1, 1 );
	my $row = 0;
	foreach my $locus (@$loci) {
		$col = 0;
		$row++;
		my $colour = 0;
		my %value_colour;
		my $locus_data = $scan_data->{'locus_data'}->{$locus};
		if ($by_ref) {
			my @locus_desc = (
				$locus_data->{'full_name'},          $locus_data->{'description'},
				length( $locus_data->{'sequence'} ), $locus_data->{'start'}
			);
			foreach my $locus_value (@locus_desc) {
				$worksheet->write( $row, $col, $locus_value, $formats->{'locus'} );
				if ( length($locus_value) > ( $col_max_width->{$col} // 0 ) ) {
					$col_max_width->{$col} = length($locus_value);
				}
				$col++;
			}
			$colour++;
			$value_colour{1} = $colour;
			my $style = BIGSdb::Utils::get_heatmap_colour_style( $value_colour{1}, $total_records );
			if ( !$formats->{$colour} ) {
				my $excel_style =
				  BIGSdb::Utils::get_heatmap_colour_style( $value_colour{1}, $total_records, { excel => 1 } );
				$formats->{$colour} = $workbook->add_format(%$excel_style);
			}
			$worksheet->write( $row, $col, 1, $formats->{$colour} );
		} else {
			if ( length($locus) > ( $col_max_width->{$col} // 0 ) ) {
				$col_max_width->{$col} = length($locus);
			}
			$worksheet->write( $row, $col, $locus, $formats->{'locus'} );
			my $desc = $self->{'datastore'}->get_locus($locus)->get_description;
			$desc->{$_} //= q() foreach (qw(full_name product));
			foreach my $desc_field (qw(full_name product)) {
				$col++;
				$worksheet->write( $row, $col, $desc->{$desc_field}, $formats->{'locus'} );
				if ( length( $desc->{$desc_field} ) > ( $col_max_width->{$col} // 0 ) ) {
					$col_max_width->{$col} = length( $desc->{$desc_field} );
				}
			}
		}
		foreach my $isolate_id (@$ids) {
			$col++;
			my $value = $scan_data->{'isolate_data'}->{$isolate_id}->{'designations'}->{$locus};
			if ( $value eq 'missing' ) {
				$value = 'X';
				$worksheet->write( $row, $col, $value, $formats->{'X'} );
			} elsif ( $value eq 'incomplete' ) {
				$value = 'I';
				$worksheet->write( $row, $col, $value, $formats->{'I'} );
			} else {
				if ( !$value_colour{$value} ) {
					$colour++;
					$value_colour{$value} = $colour;
				}
				if ( !$formats->{$colour} ) {
					my $excel_style =
					  BIGSdb::Utils::get_heatmap_colour_style( $value_colour{$value}, $total_records, { excel => 1 } );
					$formats->{$colour} = $workbook->add_format(%$excel_style);
				}
				$worksheet->write( $row, $col, $value, $formats->{ $value_colour{$value} } );
			}
		}
	}
	foreach my $col ( keys %$col_max_width ) {
		$worksheet->set_column( $col, $col, $self->_excel_col_width( $col_max_width->{$col} ) );
	}
	return;
}

sub _excel_col_width {
	my ( $self, $length ) = @_;
	my $width = int( 0.9 * ($length) + 2 );
	$width = 50 if $width > 50;
	$width = 5  if $width < 5;
	return $width;
}

sub _write_excel_unique_strains {
	my ( $self, $args ) = @_;
	my ( $workbook, $formats, $by_ref, $ids, $scan_data ) = @{$args}{qw(workbook formats by_ref ids scan_data)};
	my $strain_count = keys %{ $scan_data->{'unique_strains'}->{'strain_counts'} };
	my @strain_hashes =
	  sort {
		$scan_data->{'unique_strains'}->{'strain_counts'}->{$b}
		  <=> $scan_data->{'unique_strains'}->{'strain_counts'}->{$a}
	  }
	  keys %{ $scan_data->{'unique_strains'}->{'strain_counts'} };
	my $num_strains = @strain_hashes;
	my $worksheet   = $workbook->add_worksheet('unique strains');
	my $col         = 0;

	foreach ( 1 .. $num_strains ) {
		$worksheet->write( 0, $col, "Strain $_", $formats->{'header'} );
		$col++;
	}
	$col = 0;

	#With Excel::Writer::XLSX->set_optimization() switched on, rows need to be written in sequential order
	#So we need to calculate them first, then write them afterwards.
	my $excel_values        = [];
	my $excel_col_max_width = [];
	my $strain_id           = 1;
	foreach my $strain (@strain_hashes) {
		my $row             = 1;
		my $max_length      = 5;
		my $isolates        = $scan_data->{'unique_strains'}->{'strain_isolates'}->{$strain};
		my @mapped_isolates = @$isolates;
		foreach my $isolate (@mapped_isolates) {
			if ( $isolate =~ /^(-\d+)/x ) {
				my $isolate_id = $1;
				my $mapped_id = $self->{'name_map'}->{$isolate_id} // $isolate_id;
				$isolate =~ s/$isolate_id/$mapped_id/x;
			}
		}
		foreach my $isolate (@mapped_isolates) {
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
	$worksheet->freeze_panes( 1, 0 );
	return;
}

sub _write_excel_paralogous_loci {
	my ( $self, $args ) = @_;
	my ( $workbook, $formats, $scan_data ) = @{$args}{qw(workbook formats scan_data)};
	my $loci = $scan_data->{'paralogous_in_all'};
	return if !@$loci;
	my $worksheet = $workbook->add_worksheet('paralogous loci');
	$worksheet->write( 0, 0, 'Locus',         $formats->{'header'} );
	$worksheet->write( 0, 1, 'Isolate count', $formats->{'header'} );
	my $row        = 1;
	my $max_length = 5;

	foreach my $locus (@$loci) {
		$max_length = length $locus if length $locus > $max_length;
		my $isolate_count = $scan_data->{'paralogous'}->{$locus};
		$worksheet->write( $row, 0, $locus,         $formats->{'normal'} );
		$worksheet->write( $row, 1, $isolate_count, $formats->{'normal'} );
		$row++;
	}
	my $excel_col_max_width = $self->_excel_col_width( $max_length + 2 );
	$worksheet->set_column( 0, 0, $excel_col_max_width );
	$worksheet->set_column( 1, 1, 15 );
	$worksheet->freeze_panes( 1, 0 );
	return;
}

sub _write_excel_distance_matrix {
	my ( $self, $dismat, $args ) = @_;
	my ( $workbook, $formats, $by_ref, $ids, $scan_data ) = @{$args}{qw(workbook formats by_ref ids scan_data)};
	my %labels;
	my @ids = sort { $a <=> $b } keys %$dismat;
	foreach my $id (@ids) {
		if ( $id == 0 ) {
			$labels{$id} = 'ref';
		} else {
			$labels{$id} = $self->_get_identifier($id);
			my $mapped_id = $self->{'name_map'}->{$id} // $id;
			$labels{$id} =~ s/^$id/$mapped_id/x;
		}
	}
	my $worksheet = $workbook->add_worksheet('distance matrix');
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
			if ( !$formats->{"d$value"} ) {
				my $excel_style = BIGSdb::Utils::get_heatmap_colour_style( $value, $max, { excel => 1 } );
				$formats->{"d$value"} = $workbook->add_format(%$excel_style);
			}
			$worksheet->write( $row, $col, $dismat->{ $ids[$i] }->{ $ids[$j] }, $formats->{"d$value"} );
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

sub _write_excel_core_analysis {
	my ( $self, $core, $args ) = @_;
	my ( $workbook, $formats, $by_ref, $ids, $scan_data ) = @{$args}{qw(workbook formats by_ref ids scan_data)};
	my $worksheet = $workbook->add_worksheet('core loci');
	$self->_write_excel_worksheet_table( $worksheet, $formats, $core->{'core_loci'} );
	$worksheet = $workbook->add_worksheet('locus presence');
	$self->_write_excel_worksheet_table( $worksheet, $formats, $core->{'presence'} );
	if ( $core->{'mean_distance'} ) {
		$worksheet = $workbook->add_worksheet('locus mean variation');
		$self->_write_excel_worksheet_table( $worksheet, $formats, $core->{'mean_distance'} );
	}
	return;
}

sub _write_excel_worksheet_table {
	my ( $self, $worksheet, $formats, $buffer ) = @_;
	my @lines = split /\n/x, $buffer;
	my ( $row, $col ) = ( 0, 0 );
	my $header        = shift @lines;
	my @headings      = split /\t/x, $header;
	my $col_max_width = {};
	foreach my $heading (@headings) {
		$worksheet->write( 0, $col, $heading, $formats->{'header'} );
		if ( length $heading > ( $col_max_width->{$col} // 0 ) ) {
			$col_max_width->{$col} = length $heading;
		}
		$col++;
	}
	foreach my $line (@lines) {
		$col = 0;
		$row++;
		my @values = split /\t/x, $line;
		foreach my $value (@values) {
			my $format = length $value > 20 ? $formats->{'left-align'} : $formats->{'normal'};
			$worksheet->write( $row, $col, $value, $format );
			if ( length($value) > ( $col_max_width->{$col} // 0 ) && length($value) <= 20 ) {
				$col_max_width->{$col} = length($value);
			}
			$col++;
		}
	}
	$worksheet->freeze_panes( 1, 0 );
	foreach my $col ( keys %$col_max_width ) {
		$worksheet->set_column( $col, $col, $self->_excel_col_width( $col_max_width->{$col} ) );
	}
	return;
}

sub _write_excel_parameters {
	my ( $self, $args ) = @_;
	my ( $ids, $job_id, $scan_data, $by_ref, $workbook, $formats ) =
	  @{$args}{qw(ids job_id scan_data by_ref workbook formats)};
	my $loci      = $scan_data->{'loci'};
	my $worksheet = $workbook->add_worksheet('parameters');
	my $row       = 0;
	$formats->{'heading'} = $workbook->add_format( size  => 14,      align => 'left', bold => 1 );
	$formats->{'key'}     = $workbook->add_format( align => 'right', bold  => 1 );
	$formats->{'value'}   = $workbook->add_format( align => 'left' );
	my $job = $self->{'jobManager'}->get_job($job_id);
	my $total_time;
	eval 'use Time::Duration';    ## no critic (ProhibitStringyEval)

	if ($@) {
		$total_time = int( $job->{'elapsed'} ) . ' s';
	} else {
		$total_time = duration( $job->{'elapsed'} );
		$total_time = '<1 second' if $total_time eq 'just now';
	}
	( my $submit_time = $job->{'submit_time'} ) =~ s/\..*?$//x;
	( my $start_time  = $job->{'start_time'} ) =~ s/\..*?$//x;
	( my $stop_time   = $job->{'query_time'} ) =~ s/\..*?$//x;

	#Job attributes
	my @parameters = (
		{ section => 'Job attributes', nospace => 1 },
		{ label   => 'Plugin version', value   => $self->get_attributes->{'version'} },
		{ label   => 'Job',            value   => $job_id },
		{ label   => 'Database',       value   => $job->{'dbase_config'} },
		{ label   => 'Submit time',    value   => $submit_time },
		{ label   => 'Start time',     value   => $start_time },
		{ label   => 'Stop time',      value   => $stop_time },
		{ label   => 'Total time',     value   => $total_time },
		{ label   => 'Isolates',       value   => scalar @$ids },
		{ label   => 'Analysis type',  value   => $by_ref ? 'against reference genome' : 'against defined loci' },
	);
	my $params = $self->{'params'};
	if ($by_ref) {
		push @parameters,
		  {
			label => 'Accession',
			value => $params->{'annotation'} || $params->{'accession'} || $params->{'upload_filename'}
		  };
	} else {
		push @parameters, { label => 'Loci', value => scalar @$loci };
	}

	#Parameters/options
	push @parameters,
	  (
		{ section => 'Parameters' },
		{ label   => 'Min % identity', value => $params->{'identity'} },
		{ label   => 'Min % alignment', value => $params->{'alignment'} },
		{ label   => 'BLASTN word size', value => $params->{'word_size'} },
	  );

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
	push @parameters, { label => 'Exclude paralogous loci', value => $params->{'exclude_paralogous'} ? 'yes' : 'no' };

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
			$worksheet->write( $row, 0, $parameter->{'section'}, $formats->{'heading'} );
		} else {
			$worksheet->write( $row, 0, $parameter->{'label'} . ':', $formats->{'key'} );
			$worksheet->write( $row, 1, $parameter->{'value'},       $formats->{'value'} );
		}
		$row++;
		next if !$parameter->{'label'};
		$longest_length = length( $parameter->{'label'} ) if length( $parameter->{'label'} ) > $longest_length;
	}
	$worksheet->set_column( 0, 0, $self->_excel_col_width($longest_length) );
	return;
}

sub _write_excel_citations {
	my ( $self,     $args )    = @_;
	my ( $workbook, $formats ) = @{$args}{qw(workbook formats)};
	my $params    = $self->{'params'};
	my $worksheet = $workbook->add_worksheet('citation');
	my %excel_format;
	$formats = $workbook->add_format( size => 12, align => 'left', bold => 1 );
	$formats = $workbook->add_format( align => 'left' );
	$worksheet->write( 0, 0, 'Please cite the following:',                         $excel_format{'heading'} );
	$worksheet->write( 2, 0, q(BIGSdb Genome Comparator),                          $excel_format{'heading'} );
	$worksheet->write( 3, 0, q(Jolley & Maiden (2010). BMC Bioinformatics 11:595), $excel_format{'value'} );
	my $row = 5;
	my @schemes = split /,/x, ( $params->{'cite_schemes'} // q() );

	foreach my $scheme_id (@schemes) {
		if ( $self->should_scheme_be_cited($scheme_id) ) {
			my $pmids =
			  $self->{'datastore'}->run_query( 'SELECT pubmed_id FROM scheme_refs WHERE scheme_id=? ORDER BY pubmed_id',
				$scheme_id, { fetch => 'col_arrayref' } );
			my $citations = $self->{'datastore'}->get_citation_hash($pmids);
			my $scheme_info =
			  $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $params->{'set_id'} } );
			$worksheet->write( $row, 0, $scheme_info->{'name'}, $excel_format{'heading'} );
			foreach my $pmid (@$pmids) {
				$row++;
				$worksheet->write( $row, 0, $citations->{$pmid}, $excel_format{'value'} );
			}
			$row += 2;
		}
	}
	return;
}

sub _upload_ref_file {
	my ($self) = @_;
	my $file = $self->upload_file( 'ref_upload', 'ref' );
	return $file;
}

sub _upload_user_file {
	my ($self) = @_;
	my $file = $self->upload_file( 'user_upload', 'user' );
	return $file;
}

sub assemble_data_for_defined_loci {
	my ( $self, $args ) = @_;
	my ( $job_id, $ids, $user_genomes, $loci ) = @{$args}{qw(job_id ids user_genomes loci )};
	$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Scanning isolate record 1' } );
	my $locus_list   = $self->create_list_file( $job_id, 'loci',     $loci );
	my $isolate_list = $self->create_list_file( $job_id, 'isolates', $ids );
	my $params       = {
		database          => $self->{'params'}->{'db'},
		isolate_list_file => $isolate_list,
		locus_list_file   => $locus_list,
		threads           => $self->{'threads'},
		job_id            => $job_id,
		exemplar          => 1,
		partial_matches   => 100,
		use_tagged        => 1,
		loci              => $loci
	};
	$params->{'user_genomes'} = $user_genomes if $user_genomes;
	$params->{$_} = $self->{'params'}->{$_} foreach keys %{ $self->{'params'} };
	delete $params->{'datatype'};    #This interferes with Script::get_selected_loci.
	my $data = $self->_run_helper($params);
	$self->_touch_output_files("$job_id*");    #Prevents premature deletion by cleanup scripts
	return $data;
}

sub _assemble_data_for_reference_genome {
	my ( $self, $args ) = @_;
	my ( $job_id, $ids, $user_genomes, $cds ) = @{$args}{qw(job_id ids user_genomes cds )};
	my $locus_data = {};
	my $loci       = [];
	my $locus_num  = 1;
	foreach my $cds_record (@$cds) {
		my ( $locus_name, $full_name, $seq_ref, $start, $desc ) =
		  $self->_extract_cds_details( $cds_record, $locus_num );
		next if !defined $locus_name;
		$locus_num++;
		$locus_data->{$locus_name} =
		  { full_name => $full_name, sequence => $$seq_ref, start => $start, description => $desc };
		push @$loci, $locus_name;
	}
	$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Scanning isolate record 1' } );
	my $isolate_list = $self->create_list_file( $job_id, 'isolates', $ids );
	my $ref_seq_file = $self->_create_reference_FASTA_file( $job_id, $locus_data );
	my $params = {
		database          => $self->{'params'}->{'db'},
		isolate_list_file => $isolate_list,
		reference_file    => $ref_seq_file,
		locus_count       => scalar @$loci,
		threads           => $self->{'threads'},
		job_id            => $job_id,
		user_params       => $self->{'params'},
		locus_data        => $locus_data,
		loci              => $loci
	};
	$params->{$_} = $self->{'params'}->{$_} foreach keys %{ $self->{'params'} };
	$params->{'user_genomes'} = $user_genomes if $user_genomes;
	my $data = $self->_run_helper($params);
	$self->_touch_output_files("$job_id*");    #Prevents premature deletion by cleanup scripts
	return $data;
}

sub _run_helper {
	my ( $self, $params ) = @_;
	$self->{'dataConnector'}->set_forks(1);
	my $scanner = BIGSdb::GCForkScan->new(
		{
			config_dir         => $self->{'params'}->{'config_dir'},
			lib_dir            => $self->{'params'}->{'lib_dir'},
			dbase_config_dir   => $self->{'params'}->{'dbase_config_dir'},
			job_id             => $params->{'job_id'},
			logger             => $logger,
			config             => $self->{'config'},
			job_manager_params => {
				host     => $self->{'jobManager'}->{'host'},
				port     => $self->{'jobManager'}->{'port'},
				user     => $self->{'jobManager'}->{'user'},
				password => $self->{'jobManager'}->{'password'}
			}
		}
	);
	return {} if $self->{'exit'};
	my $data = $scanner->run($params);
	$self->{'dataConnector'}->set_forks(0);
	my $by_ref = $params->{'reference_file'} ? 1 : 0;
	my $locus_attributes = $self->_get_locus_attributes( $by_ref, $data );
	my $unique_strains   = $self->_get_unique_strains($data);
	my $paralogous       = $self->_get_potentially_paralogous_loci($data);
	my $results          = $locus_attributes;
	$results->{'isolate_data'}   = $data;
	$results->{'by_ref'}         = $by_ref;
	$results->{'unique_strains'} = $unique_strains;
	$results->{'paralogous'}     = $paralogous;
	$results->{'locus_data'}     = $params->{'locus_data'} if $params->{'locus_data'};
	$results->{'loci'}           = $params->{'loci'} if $params->{'loci'};
	return $results;
}

sub _get_locus_attributes {
	my ( $self, $by_ref, $data ) = @_;
	my @isolates = keys %$data;
	my %loci;
	foreach my $locus ( keys %{ $data->{ $isolates[0] }->{'designations'} } ) {
		$loci{$locus} = 1;
	}
	my $paralogous           = [];
	my $missing              = [];
	my $variable             = [];
	my $identical            = [];
	my $identical_except_ref = [];
	my $incomplete_in_some   = [];
	my %not_counted          = map { $_ => 1 } qw(missing incomplete);
	my $frequency            = {};
	foreach my $locus ( sort keys %loci ) {
		my $paralogous_in_all = 1;
		my $missing_in_all    = 1;
		my $identical_in_all  = 0;
		my $incomplete        = 0;
		my $presence          = 0;
		my %variants_not_ref;
		my %variants_including_ref;
		if ($by_ref) {
			$variants_including_ref{'1'} = 1;
		}
		foreach my $isolate_id (@isolates) {
			my $allele = $data->{$isolate_id}->{'designations'}->{$locus};
			$variants_including_ref{$allele} = 1;
			$variants_not_ref{$allele}       = 1;
			if ( $allele eq 'incomplete' ) {
				$incomplete = 1;
			}
			if ( $allele ne 'missing' ) {
				$presence++;
				$missing_in_all = 0;
				my %isolate_paralogous = map { $_ => 1 } @{ $data->{$isolate_id}->{'paralogous'} };
				if ( !$isolate_paralogous{$locus} ) {
					$paralogous_in_all = 0;
				}
			}
		}
		if ( keys %variants_not_ref == 1 ) {
			my @variants = keys %variants_not_ref;
			my $allele   = $variants[0];
			if ( !$not_counted{$allele} ) {
				push @$identical_except_ref, $locus;
			}
		}
		if ( keys %variants_including_ref == 1 ) {
			my @variants = keys %variants_including_ref;
			my $allele   = $variants[0];
			if ( !$not_counted{$allele} ) {
				push @$identical, $locus;
			}
		}
		push @$paralogous, $locus if $paralogous_in_all && !$missing_in_all;
		push @$missing,    $locus if $missing_in_all;
		push @$variable,   $locus if keys %variants_not_ref > 1;
		push @$incomplete_in_some, $locus if $incomplete;
		$frequency->{$locus} = $presence;
	}
	return {
		paralogous_in_all           => $paralogous,
		missing_in_all              => $missing,
		variable                    => $variable,
		identical_in_all            => $identical,
		identical_in_all_except_ref => $identical_except_ref,
		incomplete_in_some          => $incomplete_in_some,
		frequency                   => $frequency
	};
}

sub _get_unique_strains {
	my ( $self, $data ) = @_;
	my @isolates = sort { $a <=> $b } keys %$data;
	my %loci;
	foreach my $locus ( keys %{ $data->{ $isolates[0] }->{'designations'} } ) {
		$loci{$locus} = 1;
	}
	my $strain_counts = {};
	my $strain_ids    = {};
	foreach my $isolate_id (@isolates) {
		my $profile;
		foreach my $locus ( sort keys %loci ) {
			$profile .= $data->{$isolate_id}->{'designations'}->{$locus} . '|';
		}
		my $profile_hash = Digest::MD5::md5_hex($profile);    #key could get very long otherwise
		$strain_counts->{$profile_hash}++;
		push @{ $strain_ids->{$profile_hash} }, $self->_get_isolate_name($isolate_id);
	}
	return { strain_counts => $strain_counts, strain_isolates => $strain_ids };
}

sub _get_potentially_paralogous_loci {
	my ( $self, $data ) = @_;
	my @isolates      = keys %$data;
	my $paralogous_in = {};
	foreach my $isolate_id (@isolates) {
		my $loci = $data->{$isolate_id}->{'paralogous'};
		foreach my $locus (@$loci) {
			$paralogous_in->{$locus}++;
		}
	}
	return $paralogous_in;
}

sub _extract_cds_details {
	my ( $self, $cds, $locus_num ) = @_;
	my ( $start, $desc );
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
	local $" = '|';
	my $locus_name = $locus // 'locus' . sprintf( '%05d', $locus_num );
	return if $locus_name =~ /^Bio::PrimarySeq=HASH/x;    #Invalid entry in reference file.
	my $full_name = $locus_name;
	$full_name .= "|@aliases" if @aliases;
	my $seq;
	try {
		$seq = $cds->seq->seq;
	}
	catch {
		if ( $_ =~ /MSG:([^\.]*\.)/x ) {
			BIGSdb::Exception::Plugin->throw("Invalid data in annotation: $1");
		} else {
			$logger->error($_);
			BIGSdb::Exception::Plugin->throw('Invalid data in annotation.');
		}
	};
	return if !$seq;
	my @tags;
	try {
		push @tags, $_ foreach ( $cds->each_tag_value('product') );
	}
	catch {
		push @tags, 'no product';
	};
	$start = $cds->start;
	local $" = '; ';
	$desc = "@tags";
	return ( $locus_name, $full_name, \$seq, $start, $desc );
}

sub _create_reference_FASTA_file {
	my ( $self, $job_id, $locus_data ) = @_;
	my $filename = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}_refseq.fasta";
	open( my $fh, '>', $filename ) || $logger->error("Cannot open $filename for writing");
	foreach my $locus ( keys %$locus_data ) {
		say $fh ">$locus";
		say $fh $locus_data->{$locus}->{'sequence'};
	}
	close $fh;
	return $filename;
}

sub _core_analysis {
	my ( $self, $data, $args ) = @_;
	my $loci = $data->{'loci'};
	return if !@$loci;
	my $excel_buffers = {};
	my $params        = $self->{'params'};
	my $core_count    = 0;
	my @core_loci;
	my $isolate_count = @{ $args->{'ids'} };
	my $locus_count   = @$loci;
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
	my $core_loci_buffer = "Locus\tSequence length\tGenome position\tIsolate frequency\tIsolate percentage\tCore";
	$core_loci_buffer .= "\tMean distance" if $params->{'calc_distances'};
	$core_loci_buffer .= "\n";
	my %range;

	foreach my $locus (@$loci) {
		my $locus_name;
		if ( !$args->{'by_reference'} ) {
			$locus_name = $self->clean_locus( $locus, { text_output => 1 } );
		} else {
			$locus_name = $locus;
		}
		my $length =
		  defined $data->{'locus_data'}->{$locus}->{'sequence'}
		  ? length( $data->{'locus_data'}->{$locus}->{'sequence'} )
		  : q();
		my $pos  = $data->{'locus_data'}->{$locus}->{'start'} // '';
		my $freq = $data->{'frequency'}->{$locus}             // 0;
		my $percentage = BIGSdb::Utils::decimal_place( $freq * 100 / $isolate_count, 1 );
		my $core;
		if ( $percentage >= $threshold ) {
			$core = 'Y';
			push @core_loci, $locus;
		} else {
			$core = '-';
		}
		$core_count++ if $percentage >= $threshold;
		$core_loci_buffer .= "$locus_name\t$length\t$pos\t$freq\t$percentage\t$core";
		$core_loci_buffer .= "\t" . BIGSdb::Utils::decimal_place( ( $self->{'distances'}->{$locus} // 0 ), 3 )
		  if $params->{'calc_distances'};
		$core_loci_buffer .= "\n";
		for ( my $upper_range = 5 ; $upper_range <= 100 ; $upper_range += 5 ) {
			$range{$upper_range}++ if $percentage >= ( $upper_range - 5 ) && $percentage < $upper_range;
		}
		$range{'all_isolates'}++ if $percentage == 100;
	}
	$core_loci_buffer .= "\nCore loci: $core_count\n";
	say $fh $core_loci_buffer;
	$excel_buffers->{'core_loci'} = $core_loci_buffer;
	my $presence_buffer = "Present in % of isolates\tNumber of loci\tPercentage (%) of loci\n";
	my ( @labels, @values );
	for ( my $upper_range = 5 ; $upper_range <= 100 ; $upper_range += 5 ) {
		my $label      = ( $upper_range - 5 ) . " - <$upper_range";
		my $value      = $range{$upper_range} // 0;
		my $percentage = BIGSdb::Utils::decimal_place( $value * 100 / $locus_count, 1 );
		$presence_buffer .= "$label\t$value\t$percentage\n";
		push @labels, $label;
		push @values, $value;
	}
	$range{'all_isolates'} //= 0;
	my $percentage = BIGSdb::Utils::decimal_place( $range{'all_isolates'} * 100 / $locus_count, 1 );
	$presence_buffer .= "100\t$range{'all_isolates'}\t$percentage\n";
	say $fh $presence_buffer;
	close $fh;
	$excel_buffers->{'presence'} = $presence_buffer;
	push @labels, 100;
	push @values, $range{'all_isolates'};
	$excel_buffers->{'mean_distance'} = $self->_core_mean_distance( $args, $out_file, \@core_loci, $loci )
	  if $params->{'calc_distances'};

	if ( -e $out_file ) {
		$self->{'jobManager'}->update_job_output( $args->{'job_id'},
			{ filename => "$args->{'job_id'}\_core.txt", description => '40_Locus presence frequency (text)' } );
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
	return $excel_buffers;
}

sub _core_mean_distance {
	my ( $self, $args, $out_file, $core_loci, $loci ) = @_;
	return if !@$core_loci;
	my $file_buffer;
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
				while ( $range < $distance ) { $range += $increment }
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
		while ( $range <= $largest_distance ) {
			$range += $increment;
			$range = ( int( ( $range * 10000.0 ) + 0.5 ) / 10000.0 );    #Set float precision
			my $label = '>' . ( $range - $increment ) . " - $range";
			my $value = $upper_range{$range} // 0;
			push @labels, $label;
			push @values, $value;
			$file_buffer .=
			  "$label\t$value\t"
			  . BIGSdb::Utils::decimal_place( ( ( $upper_range{$range} // 0 ) * 100 / @$core_loci ), 1 ) . "\n";
		}
		$file_buffer .=
		  "\n*Mean distance is the overall mean distance calculated from a computed consensus sequence.\n";
	}
	open( my $fh, '>>', $out_file ) || $logger->error("Cannot open $out_file for appending");
	say $fh "\nMean distances of core loci\n---------------------------\n";
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
	return $file_buffer;
}

sub _get_largest_distance {
	my ( $self, $core_loci, $loci ) = @_;
	my $largest = 0;
	foreach my $locus (@$core_loci) {
		$largest = $self->{'distances'}->{$locus} if $self->{'distances'}->{$locus} > $largest;
	}
	return $largest;
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
		\$("#recommended_scheme_fieldset").hide(500);
		\$("#locus_fieldset").hide(500);
		\$("#tblastx").prop("disabled", false);
		\$("#use_tagged").prop("disabled", true);
		\$("#exclude_paralogous").prop("disabled", false);
		\$("#paralogous_options").prop("disabled", false);
	} else {
		\$("#scheme_fieldset").show(500);
		\$("#recommended_scheme_fieldset").show(500);
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
