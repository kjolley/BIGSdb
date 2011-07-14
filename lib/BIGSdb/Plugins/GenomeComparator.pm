#GenomeComparator.pm - Genome comparison plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
use base qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use Apache2::Connection ();
use List::MoreUtils qw(uniq any);
use BIGSdb::Page 'SEQ_METHODS';

sub get_attributes {
	my %att = (
		name        => 'GenomeComparator',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Compare genomes at defined loci or against loci defined in a reference genome',
		category    => 'Genome',
		buttontext  => 'Genome Camparator',
		menutext    => 'Genome comparator',
		module      => 'GenomeComparator',
		version     => '1.1.4',
		dbtype      => 'isolates',
		section     => 'analysis',
		order       => 30,
		requires    => 'muscle,offline_jobs',
		help        => 'tooltips',
		system_flag => 'GenomeComparator'
	);
	return \%att;
}

sub get_plugin_javascript {
	my $buffer = << "END";
function listbox_selectall(listID, isSelect) {
	var listbox = document.getElementById(listID);
	for(var count=0; count < listbox.options.length; count++) {
		listbox.options[count].selected = isSelect;
	}
}

function enable_seqs(){
	var accession_element = document.getElementById('accession');
	if (accession_element.value.length){
		document.getElementById('locus').disabled=true;
		document.getElementById('scheme_id').disabled=true;
	} else {
		document.getElementById('locus').disabled=false;
		document.getElementById('scheme_id').disabled=false;
	}
}
	
END
	return $buffer;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	my @loci = split /\|\|/, $params->{'locus'};
	my @ids  = split /\|\|/, $params->{'isolate_id'};
	my $filtered_ids = $self->_filter_ids_by_project( \@ids, $params->{'project'} );
	my @scheme_ids = split /\|\|/, $params->{'scheme_id'};
	my $accession = $params->{'accession'};
	if ( !@$filtered_ids ) {
		$self->{'jobManager'}->update_job_status(
			$job_id,
			{
				'status' => 'failed',
				'message_html' =>
"<p>You must include one or more isolates. Make sure your selected isolates haven't been filtered to none by selecting a project.</p>"
			}
		);
		return;
	}
	if ( !$accession && !@loci && !@scheme_ids ) {
		$self->{'jobManager'}->update_job_status( $job_id,
			{ 'status' => 'failed', 'message_html' => "<p>You must select one or more loci or schemes, or a genome accession number.</p>" }
		);
		return;
	}
	if ($accession) {
		my $seq_db = new Bio::DB::GenBank;
		$seq_db->verbose(2);    #convert warn to exception
		my $seq_obj;
		try {
			$seq_obj = $seq_db->get_Seq_by_acc($accession);
		}
		catch Bio::Root::Exception with {
			$self->{'jobManager'}->update_job_status(
				$job_id,
				{
					'status'       => 'failed',
					'message_html' => "<p /><p class=\"statusbad\">No data returned for accession number #$accession.</p>"
				}
			);
			my $err = shift;
			$logger->debug($err);
		};
		return if !$seq_obj;
		$self->_analyse_by_reference( $job_id, $params, $accession, $seq_obj, $filtered_ids );
	} else {
		$self->_add_scheme_loci( $params, \@loci );
		$self->_analyse_by_loci( $job_id, $params, \@loci, $filtered_ids );
	}
}

sub run {
	my ($self) = @_;
	print "<h1>Genome Comparator</h1>\n";
	my $q = $self->{'cgi'};
	if ( $q->param('submit') ) {
		my @ids          = $q->param('isolate_id');
		my $filtered_ids = $self->_filter_ids_by_project( \@ids, $q->param('project') );
		my $continue     = 1;
		if ( !@$filtered_ids ) {
			print
"<div class=\"box\" id=\"statusbad\"><p>You must include one or more isolates. Make sure your selected isolates haven't been filtered to none by selecting a project.</p></div>\n";
			$continue = 0;
		}
		my @loci       = $q->param('locus');
		my @scheme_ids = $q->param('scheme_id');
		my $accession  = $q->param('accession');
		if ( !$accession && !@loci && !@scheme_ids && $continue ) {
			print
"<div class=\"box\" id=\"statusbad\"><p>You must select one or more loci or schemes, or a genome accession number.</p></div>\n";
			$continue = 0;
		}
		if ($continue) {
			my $params = $q->Vars;
			my $job_id = $self->{'jobManager'}->add_job(
				{
					'dbase_config' => $self->{'instance'},
					'ip_address'   => $q->remote_host,
					'module'       => 'GenomeComparator',
					'parameters'   => $params
				}
			);
			print <<"HTML";
<div class="box" id="resultstable">
<p>This analysis has been submitted to the job queue.</p>
<p>Please be aware that this job may take a long time depending on the number of comparisons
and how busy the server is.</p>
<p><a href="$self->{'script_name'}?db=$self->{'instance'}&amp;page=job&amp;id=$job_id">
Follow the progress of this job and view the output.</a></p> 	
</div>	
HTML
			return;
		}
	}
	$self->_print_interface;
}

sub _print_interface {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $view   = $self->{'system'}->{'view'};
	my $qry =
"SELECT DISTINCT $view.id,$view.$self->{'system'}->{'labelfield'} FROM sequence_bin LEFT JOIN $view ON $view.id=sequence_bin.isolate_id ORDER BY $view.id";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute; };
	$logger->error($@) if $@;
	my @ids;
	my %labels;

	while ( my ( $id, $isolate ) = $sql->fetchrow_array ) {
		push @ids, $id;
		$labels{$id} = "$id) $isolate";
	}
	if ( !@ids ) {
		print "<div class=\"box\" id=\"statusbad\"><p>There are no sequences in the sequence bin.</p></div>\n";
		return;
	}
	print "<div class=\"box\" id=\"queryform\">\n";
	print "<p>Please select the required isolate ids and loci for comparison - use ctrl or shift to make 
	  multiple selections. In addition to selecting individual loci, you can choose to include all loci defined in schemes
	  by selecting the appropriate scheme description. Alternatively, you can enter the accession number for an
	  annotated reference genome and compare using the loci defined in that.</p>\n";
	my $loci = $self->{'datastore'}->get_loci( { 'query_pref' => 0, 'seq_defined' => 1 } );
	my %cleaned;
	foreach (@$loci) {
		( $cleaned{$_} = $_ ) =~ tr/_/ /;
	}
	print $q->start_form( -onMouseMove => 'enable_seqs()' );
	print "<div class=\"scrollable\">\n";
	print "<fieldset style=\"float:left\">\n<legend>Isolates</legend>\n";
	print $q->scrolling_list(
		-name     => 'isolate_id',
		-id       => 'isolate_id',
		-values   => \@ids,
		-labels   => \%labels,
		-size     => 8,
		-multiple => 'true'
	);
	print
"<div style=\"text-align:center\"><input type=\"button\" onclick='listbox_selectall(\"isolate_id\",true)' value=\"All\" style=\"margin-top:1em\" class=\"smallbutton\" />\n";
	print
"<input type=\"button\" onclick='listbox_selectall(\"isolate_id\",false)' value=\"None\" style=\"margin-top:1em\" class=\"smallbutton\" /></div>\n";
	print "</fieldset>\n";
	print "<fieldset style=\"float:left\">\n<legend>Loci</legend>\n";
	print $q->scrolling_list( -name => 'locus', -id => 'locus', -values => $loci, -labels => \%cleaned, -size => 8, -multiple => 'true' );
	print
"<div style=\"text-align:center\"><input type=\"button\" onclick='listbox_selectall(\"locus\",true)' value=\"All\" style=\"margin-top:1em\" class=\"smallbutton\" />\n";
	print
"<input type=\"button\" onclick='listbox_selectall(\"locus\",false)' value=\"None\" style=\"margin-top:1em\" class=\"smallbutton\" /></div>\n";
	print "</fieldset>\n";
	print "<fieldset style=\"float:left\">\n<legend>Schemes</legend>\n";
	my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes ORDER BY display_order,id");
	my %scheme_desc;

	foreach (@$schemes) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info($_);
		$scheme_desc{$_} = $scheme_info->{'description'};
	}
	push @$schemes, 0;
	$scheme_desc{0} = 'No scheme';
	print $q->scrolling_list(
		-name     => 'scheme_id',
		-id       => 'scheme_id',
		-values   => $schemes,
		-labels   => \%scheme_desc,
		-size     => 8,
		-multiple => 'true'
	);
	print
"<div style=\"text-align:center\"><input type=\"button\" onclick='listbox_selectall(\"scheme_id\",true)' value=\"All\" style=\"margin-top:1em\" class=\"smallbutton\" />\n";
	print
"<input type=\"button\" onclick='listbox_selectall(\"scheme_id\",false)' value=\"None\" style=\"margin-top:1em\" class=\"smallbutton\" /></div>\n";
	print "</fieldset>\n";
	print "<fieldset style=\"float:left\">\n<legend>Reference genome</legend>\n";
	print "<p>Enter accession number:</p>\n";
	$" = ' ';
	print $q->textfield(
		-name      => 'accession',
		-id        => 'accession',
		-size      => 10,
		-maxlength => 20,
		-onKeyUp   => 'enable_seqs()',
		-onBlur    => 'enable_seqs()'
	);
	print
" <a class=\"tooltip\" title=\"Reference genome - Use of a reference genome will override any locus or scheme settings.\">&nbsp;<i>i</i>&nbsp;</a>";
	print "</fieldset>\n";
	print "<fieldset style=\"float:left\">\n<legend>Parameters</legend>\n";
	print "<ul><li><label for =\"identity\" class=\"parameter\">Min % identity:</label>\n";
	print $q->popup_menu(
		-name    => 'identity',
		-id      => 'identity',
		-values  => [qw(50 55 60 65 70 75 80 85 90 91 92 93 94 95 96 97 98 99 100)],
		-default => 70
	);
	print " <a class=\"tooltip\" title=\"Minimum % identity - Match required for partial matching.\">&nbsp;<i>i</i>&nbsp;</a></li>";
	print "<li><label for=\"alignment\" class=\"parameter\">Min % alignment:</label>\n";
	print $q->popup_menu(
		-name    => 'alignment',
		-id      => 'alignment',
		-values  => [qw(10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 91 92 93 94 95 96 97 98 99 100)],
		-default => 50
	);
	print
" <a class=\"tooltip\" title=\"Minimum % alignment - Percentage of allele sequence length required to be aligned for partial matching.\">&nbsp;<i>i</i>&nbsp;</a></li>";
	print "<li><label for=\"word_size\" class=\"parameter\">BLASTN word size:</label>\n";
	print $q->popup_menu(
		-name    => 'word_size',
		-id      => 'word_size',
		-values  => [qw(8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28)],
		-default => 15
	);
	print
" <a class=\"tooltip\" title=\"BLASTN word size - This is the length of an exact match required to initiate an extension. Larger values increase speed at the expense of sensitivity.\">&nbsp;<i>i</i>&nbsp;</a></li>\n";
	print "<li>";
	print $q->checkbox( -name => 'align', -label => 'Produce alignments' );
	print
" <a class=\"tooltip\" title=\"Alignments - Alignments will be produced in muscle for any loci that vary between isolates when analysing by reference genome. This may slow the analysis considerably.\">&nbsp;<i>i</i>&nbsp;</a></li>\n";
	print "</ul>\n";
	print "</fieldset>\n";
	print "<fieldset style=\"float:left\">\n<legend>Restrict included sequences by</legend>\n";
	print "<table><tr><td style=\"text-align:right\">Sequence method: </td><td style=\"text-align:left\">";
	print $q->popup_menu( -name => 'seq_method', -values => [ '', SEQ_METHODS ] );
	print
" <a class=\"tooltip\" title=\"Sequence method - Only include sequences generated from the selected method.\">&nbsp;<i>i</i>&nbsp;</a>";
	print "</td></tr>\n";
	my $project_list = $self->{'datastore'}->run_list_query_hashref("SELECT id,short_description FROM projects ORDER BY short_description");
	my @projects;
	undef %labels;

	foreach (@$project_list) {
		push @projects, $_->{'id'};
		$labels{ $_->{'id'} } = $_->{'short_description'};
	}
	if (@projects) {
		unshift @projects, '';
		print "<tr><td style=\"text-align:right\">Project: </td><td style=\"text-align:left\">";
		print $q->popup_menu( -name => 'project', -values => \@projects, -labels => \%labels );
		print
" <a class=\"tooltip\" title=\"Projects - Filter isolate list to only include those belonging to a specific project.\">&nbsp;<i>i</i>&nbsp;</a>";
		print "</td></tr>\n";
	}
	my $experiment_list = $self->{'datastore'}->run_list_query_hashref("SELECT id,description FROM experiments ORDER BY description");
	my @experiments;
	undef %labels;
	foreach (@$experiment_list) {
		push @experiments, $_->{'id'};
		$labels{ $_->{'id'} } = $_->{'description'};
	}
	if (@experiments) {
		unshift @experiments, '';
		print "<tr><td style=\"text-align:right\">Experiment: </td><td>";
		print $q->popup_menu( -name => 'experiment', -values => \@experiments, -labels => \%labels );
		print
" <a class=\"tooltip\" title=\"Experiments - Only include sequences that have been linked to the specified experiment.\">&nbsp;<i>i</i>&nbsp;</a>";
		print "</td></tr>\n";
	}
	print "</table>\n";
	print "</fieldset>\n";
	print "</div>\n";
	print "<table style=\"width:95%\"><tr><td style=\"text-align:left\">";
	print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;name=GenomeComparator\" class=\"resetbutton\">Reset</a></td><td style=\"text-align:right\" colspan=\"4\">";
	print $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
	print "</td></tr></table>\n";
	print $q->hidden($_) foreach (qw (page name db));
	print $q->end_form;
	print "</div>\n";
}

sub _filter_ids_by_project {
	my ( $self, $ids, $project_id ) = @_;
	return $ids if !$project_id;
	my $ids_in_project = $self->{'datastore'}->run_list_query( "SELECT isolate_id FROM project_members WHERE project_id = ?", $project_id );
	my @filtered_ids;
	foreach my $id (@$ids) {
		push @filtered_ids, $id if any { $id eq $_ } @$ids_in_project;
	}
	return \@filtered_ids;
}

sub _analyse_by_loci {
	my ( $self, $job_id, $params, $loci, $ids ) = @_;
	if ( @$ids < 2 ) {
		$self->{'jobManager'}->update_job_status(
			$job_id,
			{
				'status' => 'failed',
				'message_html' =>
"<p>You must select at least two isolates for comparison against defined loci. Make sure your selected isolates haven't been filtered to less than two by selecting a project.</p>"
			}
		);
		return;
	}
	my %isolate_FASTA;
	foreach (@$ids) {
		$isolate_FASTA{$_} = $self->_create_isolate_FASTA( $_, $job_id, $params );
	}
	open( my $fh, '>', "$self->{'config'}->{'tmp_dir'}/$job_id.txt" );
	my $html_buffer = "<h3>Analysis against defined loci</h3>\n";
	print $fh "Analysis against defined loci\n";
	print $fh "Time: " . ( localtime(time) ) . "\n\n";
	my $blastn_word_size = $params->{'word_size'} =~ /^(\d+)$/ ? $1 : 15;
	$html_buffer .= "<div class=\"scrollable\"><table class=\"resultstable\"><tr><th>Locus</th>";
	print $fh "Locus";
	my %names;
	my $isolate;

	foreach my $id (@$ids) {
		my $isolate_ref =
		  $self->{'datastore'}->run_simple_query( "SELECT $self->{'system'}->{'labelfield'} FROM isolates WHERE id=?", $id );
		if ( ref $isolate_ref eq 'ARRAY' ) {
			$names{$id} = $isolate_ref->[0];
			$isolate = ' (' . ( $isolate_ref->[0] ) . ')' if ref $isolate_ref eq 'ARRAY';
		}
		$html_buffer .= "<th>$id$isolate</th>";
		print $fh "\t$id$isolate";
	}
	$html_buffer .= "</tr>";
	print $fh "\n";
	my $td = 1;
	@$loci = uniq @$loci;
	my $progress = 0;
	foreach my $locus (@$loci) {
		my $locus_FASTA = $self->_create_locus_FASTA_db( $locus, $job_id );
		my $cleaned_locus = $self->clean_locus($locus);
		$html_buffer .= "<tr class=\"td$td\"><td>$cleaned_locus</td>";
		print $fh $locus;
		my $new_allele = 1;
		my %new;
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		foreach my $id (@$ids) {
			$id = $1 if $id =~ /(\d*)/;    #avoid taint check
			my $out_file = "$self->{'config'}->{'secure_tmp_dir'}/$job_id\_isolate_$id\_outfile.txt";
			if ( $locus_info->{'data_type'} eq 'DNA' ) {
				$self->_blast( $blastn_word_size, $locus_FASTA, $isolate_FASTA{$id}, $out_file );
			} else {
				$self->_blast( 3, $locus_FASTA, $isolate_FASTA{$id}, $out_file, 1 );
			}
			my $match = $self->_parse_blast_by_locus( $locus, $out_file, $params );
			if ( ref $match ne 'HASH' ) {
				$html_buffer .= "<td>X</td>";
				print $fh "\tX";
			} elsif ( $match->{'exact'} ) {
				$html_buffer .= "<td>$match->{'allele'}</td>";
				print $fh "\t$match->{'allele'}";
			} else {
				my $seq = $self->_extract_sequence($match);
				my $found;
				foreach ( keys %new ) {
					if ( $seq eq $new{$_} ) {
						$html_buffer .= "<td>new#$_</td>\n";
						print $fh "\tnew#$_";
						$found = 1;
					}
				}
				if ( !$found ) {
					$new{$new_allele} = $seq;
					$html_buffer .= "<td>new#$new_allele</td>";
					print $fh "\tnew#$new_allele";
					$new_allele++;
				}
			}
		}
		$html_buffer .= "</tr>";
		print $fh "\n";
		$td = $td == 1 ? 2 : 1;
		system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$job_id\_fastafile*";
		$progress++;
		my $complete = int( 100 * $progress / scalar @$loci );
		my $close_table = ( $progress != scalar @$loci ) ? '</table></div>' : '';
		$self->{'jobManager'}
		  ->update_job_status( $job_id, { 'percent_complete' => $complete, 'message_html' => "$html_buffer$close_table" } );
	}
	$html_buffer .= "</table></div>\n";
	$self->{'jobManager'}->update_job_status( $job_id, { 'message_html' => "$html_buffer" } );
	close $fh;
	system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$job_id\*";
	$self->{'jobManager'}->update_job_output( $job_id, { 'filename' => "$job_id.txt", 'description' => 'Main output file' } );
}

sub _add_scheme_loci {
	my ( $self, $params, $loci ) = @_;
	my @scheme_ids = split /\|\|/, $params->{'scheme_id'};
	my %locus_selected;
	$locus_selected{$_} = 1 foreach (@$loci);
	foreach (@scheme_ids) {
		my $scheme_loci = $_ ? $self->{'datastore'}->get_scheme_loci($_) : $self->{'datastore'}->get_loci_in_no_scheme;
		foreach my $locus (@$scheme_loci) {
			if ( !$locus_selected{$locus} ) {
				push @$loci, $locus;
				$locus_selected{$locus} = 1;
			}
		}
	}
}

sub _analyse_by_reference {
	my ( $self, $job_id, $params, $accession, $seq_obj, $ids ) = @_;
	my @cds;
	foreach ( $seq_obj->get_SeqFeatures ) {
		push @cds, $_ if $_->primary_tag eq 'CDS';
	}
	open( my $fh,       '>', "$self->{'config'}->{'tmp_dir'}/$job_id.txt" );
	open( my $align_fh, '>', "$self->{'config'}->{'tmp_dir'}/$job_id\_align.txt" );
	my $html_buffer = "<h3>Analysis by reference genome</h3>";
	print $fh "Analysis by reference genome\n\n";
	print $fh "Time: " . ( localtime(time) ) . "\n\n";
	my %att = (
		'accession'   => $accession,
		'version'     => $seq_obj->seq_version,
		'type'        => $seq_obj->alphabet,
		'length'      => $seq_obj->length,
		'description' => $seq_obj->description,
		'cds'         => scalar @cds
	);
	my %abb = ( 'cds' => 'coding regions' );
	$html_buffer .= "<table class=\"resultstable\">";
	my $td = 1;

	foreach (qw (accession version type length description cds)) {
		if ( $att{$_} ) {
			$html_buffer .= "<tr class=\"td$td\"><th>" . ( $abb{$_} || $_ ) . "</th><td style=\"text-align:left\">$att{$_}</td></tr>";
			print $fh ( $abb{$_} || $_ ) . ": $att{$_}\n";
			$td = $td == 1 ? 2 : 1;
		}
	}
	$html_buffer .= "</table>";
	$self->{'jobManager'}->update_job_status( $job_id, { 'message_html' => $html_buffer } );
	my %isolate_FASTA;
	my $prefix = BIGSdb::Utils::get_random();
	$isolate_FASTA{$_} = $self->_create_isolate_FASTA_db( $_, $prefix ) foreach (@$ids);
	my %loci;
	my $blastn_word_size = $params->{'word_size'} =~ /^(\d+)$/ ? $1 : 15;
	my ( $exacts, $exact_except_ref, $all_missing, $truncated_loci, $varying_loci );
	my $progress = 0;
	my $total = ( $params->{'align'} && scalar @$ids > 1 ) ? ( scalar @cds * 2 ) : scalar @cds;

	foreach my $cds (@cds) {
		$progress++;
		my $complete = int( 100 * $progress / $total );
		$self->{'jobManager'}->update_job_status( $job_id, { 'percent_complete' => $complete } );
		my @aliases;
		my $locus;
		my %seqs;
		foreach (qw (gene gene_synonym locus_tag old_locus_tag)) {
			my @values = $cds->has_tag($_) ? $cds->get_tag_values($_) : ();
			foreach my $value (@values) {
				if ($locus) {
					push @aliases, $value;
				} else {
					$locus = $value;
				}
			}
		}
		$" = '|';
		my $locus_name = $locus;
		$locus_name .= "|@aliases" if @aliases;	
		my $seq = $cds->seq->seq;
		$seqs{'ref'} = $seq;
		my @tags;
		try {
			push @tags, $_ foreach ( $cds->each_tag_value('product') );
		}
		catch Bio::Root::Exception with {
			my $err = shift;
			$logger->debug($err);
			$html_buffer .=
			  "\n<p /><p class=\"statusbad\">Error: There are no product tags defined in record with supplied accession number.</p>\n";
			$self->{'jobManager'}->update_job_status( $job_id, { 'message_html' => $html_buffer } );
		};
		return if !@tags;
		my $start = $cds->start;
		$" = '; ';
		my $desc                 = "@tags";
		my $length               = length $seq;
		my $ref_seq_file         = $self->_create_reference_FASTA_file( \$seq, $prefix );
		my $seqbin_length_sql    = $self->{'db'}->prepare("SELECT length(sequence) FROM sequence_bin where id=?");
		my $all_exact            = 1;
		my $missing_in_all       = 1;
		my $exact_except_for_ref = 1;
		my $truncated_locus      = 0;
		my $first                = 1;
		my $first_seq;
		my $previous_seq;

		foreach my $id (@$ids) {
			$id = $1 if $id =~ /(\d*)/;    #avoid taint check
			my $out_file = "$self->{'config'}->{'secure_tmp_dir'}/$prefix\_isolate_$id\_outfile.txt";
			$self->_blast( $blastn_word_size, $isolate_FASTA{$id}, $ref_seq_file, $out_file );
			my $match = $self->_parse_blast_ref( \$seq, $out_file, $params );
			my $extracted_seq;
			my $seqbin_length;
			if ( ref $match eq 'HASH' ) {
				$missing_in_all = 0;
				if ( $match->{'identity'} == 100 && $match->{'alignment'} == $length ) {
					$exact_except_for_ref = 0;
				} else {
					$all_exact = 0;					
				}
				eval { $seqbin_length_sql->execute( $match->{'seqbin_id'} ); };
				$logger->error($@) if $@;
				($seqbin_length) = $seqbin_length_sql->fetchrow_array;
				if ( $match->{'predicted_start'} < 1 ) {
					$match->{'predicted_start'} = 1;
					$truncated_locus = 1;
				} elsif ( $match->{'predicted_start'} > $seqbin_length ) {
					$match->{'predicted_start'} = $seqbin_length;
					$truncated_locus = 1;
				}
				if ( $match->{'predicted_end'} < 1 ) {
					$match->{'predicted_end'} = 1;
					$truncated_locus = 1;
				} elsif ( $match->{'predicted_end'} > $seqbin_length ) {
					$match->{'predicted_end'} = $seqbin_length;
					$truncated_locus = 1;
				}
				$extracted_seq = $self->_extract_sequence($match);
				$seqs{$id} = $extracted_seq;
				if ($first) {
					$previous_seq = $extracted_seq;
				} else {
					if ( $extracted_seq ne $previous_seq ) {
						$exact_except_for_ref = 0;
					}
				}
			} else {
				$all_exact            = 0;
				$exact_except_for_ref = 0;
			}
			$first = 0;
		}
		if ($all_exact) {
			$exacts->{$locus_name}->{'length'} = length $seq;
			$exacts->{$locus_name}->{'desc'}   = $desc;
			$exacts->{$locus_name}->{'start'}  = $start;
		} elsif ($missing_in_all) {
			$all_missing->{$locus_name}->{'length'} = length $seq;
			$all_missing->{$locus_name}->{'desc'}   = $desc;
			$all_missing->{$locus_name}->{'start'}  = $start;
		} elsif ($exact_except_for_ref) {
			$exact_except_ref->{$locus_name}->{'length'} = length $seq;
			$exact_except_ref->{$locus_name}->{'desc'}   = $desc;
			$exact_except_ref->{$locus_name}->{'start'}  = $start;
		} elsif ($truncated_locus) {
			$truncated_loci->{$locus_name}->{'length'} = length $seq;
			$truncated_loci->{$locus_name}->{'desc'}   = $desc;
			$truncated_loci->{$locus_name}->{'start'}  = $start;
		} else {
			$varying_loci->{$locus_name}->{$_} = $seqs{$_} foreach ( keys %seqs );
			$varying_loci->{$locus_name}->{'desc'}  = $desc;
			$varying_loci->{$locus_name}->{'start'} = $start;
		}
	}
	print $fh "\n###\n\n";
	$self->_print_variable_loci( $job_id, \$html_buffer, $fh, $align_fh, $params, $ids, $varying_loci );
	print $fh "\n###\n\n";
	$self->_print_missing_in_all( \$html_buffer, $fh, $all_missing );
	print $fh "\n###\n\n";
	$self->_print_exact_matches( \$html_buffer, $fh, $exacts, $params );
	print $fh "\n###\n\n";
	$self->_print_exact_except_ref( \$html_buffer, $fh, $exact_except_ref );
	print $fh "\n###\n\n";
	$self->_print_truncated_loci( \$html_buffer, $fh, $truncated_loci );
	$self->{'jobManager'}->update_job_status( $job_id, { 'message_html' => $html_buffer } );
	close $fh;
	close $align_fh;
	system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$prefix\*";
	$self->{'jobManager'}->update_job_output( $job_id, { 'filename' => "$job_id.txt", 'description' => 'Main output file' } );

	if ( @$ids > 1 && $params->{'align'} ) {
		$self->{'jobManager'}->update_job_output( $job_id, { 'filename' => "$job_id\_align.txt", 'description' => 'Alignments' } );
	}
}

sub _print_variable_loci {
	my ( $self, $job_id, $buffer_ref, $fh, $fh_align, $params, $ids, $loci ) = @_;
	return if ref $loci ne 'HASH';
	$$buffer_ref .= "<h3>Loci with sequence differences between isolates:</h3>";
	print $fh "Loci with sequence differences between isolates\n";
	print $fh "-----------------------------------------------\n\n";
	$$buffer_ref .= "<p>Each unique allele is defined a number starting at 1. Missing alleles are marked as 'X'.</p>";
	print $fh "Each unique allele is defined a number starting at 1. Missing alleles are marked as 'X'.\n\n";
	$$buffer_ref .= "<p>Variable loci: " . ( scalar keys %$loci ) . "</p>";
	print $fh "Variable loci: " . ( scalar keys %$loci ) . "\n\n";
	$$buffer_ref .= "<div class=\"scrollable\">";
	$$buffer_ref .=
"<table class=\"resultstable\"><tr><th>Locus</th><th>Product</th><th>Sequence length</th><th>Genome position</th><th>Reference genome</th>";
	print $fh "Locus\tProduct\tSequence length\tGenome position\tReference genome";
	my %names;
	my $isolate;

	foreach my $id (@$ids) {
		my $isolate_ref =
		  $self->{'datastore'}
		  ->run_simple_query( "SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?", $id );
		if ( ref $isolate_ref eq 'ARRAY' ) {
			$names{$id} = $isolate_ref->[0];
			$isolate = ' (' . ( $isolate_ref->[0] ) . ')' if ref $isolate_ref eq 'ARRAY';
		}
		$$buffer_ref .= "<th>$id$isolate</th>";
		print $fh "\t$id$isolate";
	}
	$$buffer_ref .= "</tr>";
	print $fh "\n";
	my $td = 1;
	my $count;
	my $temp     = BIGSdb::Utils::get_random();
	my $progress = 0;
	my $total    = 2 * ( scalar keys %$loci );    #need to show progress from 50 - 100%

	foreach ( sort keys %$loci ) {
		$progress++;
		my $complete = 50 + int( 100 * $progress / $total );
		$self->{'jobManager'}->update_job_status( $job_id, { 'percent_complete' => $complete } ) if $params->{'align'};
		my $fasta_file = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_$_.fasta";
		my $muscle_out = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_$_.muscle";
		open( my $fasta_fh, '>', $fasta_file );
		my %alleles;
		my $allele        = 1;
		my $cleaned_locus = $self->clean_locus($_);
		my $length        = length( $loci->{$_}->{'ref'} );
		my $start         = $loci->{$_}->{'start'};
		$$buffer_ref .=
		  "<tr class=\"td$td\"><td>$cleaned_locus</td><td>$loci->{$_}->{'desc'}</td><td>$length</td><td>$start</td><td>1</td>";
		print $fh "$_\t$loci->{$_}->{'desc'}\t$length\t$start\t1";
		$alleles{1} = $loci->{$_}->{'ref'};
		print $fasta_fh ">ref\n";
		print $fasta_fh "$loci->{$_}->{'ref'}\n";

		foreach my $id (@$ids) {
			my $this_allele;
			if ( !$loci->{$_}->{$id} ) {
				$this_allele = 'X';
			} else {
				print $fasta_fh ">$names{$id}\n";
				print $fasta_fh "$loci->{$_}->{$id}\n";
				my $i;
				for ( $i = 1 ; $i <= $allele ; $i++ ) {
					if ( $loci->{$_}->{$id} eq $alleles{$i} ) {
						$this_allele = $i;
					}
				}
				if ( !$this_allele ) {
					$allele++;
					$this_allele = $allele;
					$alleles{$this_allele} = $loci->{$_}->{$id};
				}
			}
			$$buffer_ref .= "<td>$this_allele</td>";
			print $fh "\t$this_allele";
		}
		$$buffer_ref .= "</tr>";
		print $fh "\n";
		$td = $td == 1 ? 2 : 1;
		close $fasta_fh;
		if ( $params->{'align'} ) {
			system( $self->{'config'}->{'muscle_path'}, '-in', $fasta_file, '-out', $muscle_out, '-quiet', '-clw' );
			if ( -e $muscle_out ) {
				open( my $muscle_fh, '<', $muscle_out );
				print $fh_align "$_\n";
				print $fh_align '-' x ( length $_ ) . "\n\n";
				while ( my $line = <$muscle_fh> ) {
					print $fh_align $line;
				}
				close $muscle_out;
				unlink $muscle_out;
			}
		}
		unlink $fasta_file;
	}
	$$buffer_ref .= "</table></div>";
}

sub _print_exact_matches {
	my ( $self, $buffer_ref, $fh, $exacts, $params ) = @_;
	return if ref $exacts ne 'HASH';
	$$buffer_ref .= "<h3>Exactly matching loci</h3>\n";
	print $fh "Exactly matching loci\n";
	print $fh "---------------------\n\n";
	$$buffer_ref .= "<p>These loci are identical in all isolates";
	print $fh "These loci are identical in all isolates";
	if ( $params->{'accession'} ) {
		$$buffer_ref .= ", including the reference genome";
		print $fh ", including the reference genome";
	}
	$$buffer_ref .= ".</p>";
	print $fh ".\n\n";
	$$buffer_ref .= "<p>Matches: " . ( scalar keys %$exacts ) . "</p>";
	print $fh "Matches: " . ( scalar keys %$exacts ) . "\n\n";
	$self->_print_locus_table( $buffer_ref, $fh, $exacts );
}

sub _print_exact_except_ref {
	my ( $self, $buffer_ref, $fh, $exacts ) = @_;
	return if ref $exacts ne 'HASH';
	$$buffer_ref .= "<h3>Loci exactly the same in all compared genomes except the reference</h3>";
	print $fh "Loci exactly the same in all compared genomes except the reference\n";
	print $fh "------------------------------------------------------------------\n\n";
	$$buffer_ref .= "<p>Matches: " . ( scalar keys %$exacts ) . "</p>";
	print $fh "Matches: " . ( scalar keys %$exacts ) . "\n\n";
	$self->_print_locus_table( $buffer_ref, $fh, $exacts );
}

sub _print_missing_in_all {
	my ( $self, $buffer_ref, $fh, $missing ) = @_;
	return if ref $missing ne 'HASH';
	$$buffer_ref .= "<h3>Loci missing in all isolates</h3>";
	print $fh "Loci missing in all isolates\n";
	print $fh "----------------------------\n\n";
	$$buffer_ref .= "<p>Missing loci: " . ( scalar keys %$missing ) . "</p>";
	print $fh "Missing loci: " . ( scalar keys %$missing ) . "\n\n";
	$self->_print_locus_table( $buffer_ref, $fh, $missing );
}

sub _print_truncated_loci {
	my ( $self, $buffer_ref, $fh, $truncated ) = @_;
	return if ref $truncated ne 'HASH';
	$$buffer_ref .= "<h3>Loci that are truncated in some isolates</h3>";
	print $fh "Loci that are truncated in some isolates\n";
	print $fh "----------------------------------------\n\n";
	$$buffer_ref .= "<p>Truncated: " . ( scalar keys %$truncated ) . "</p>";
	print $fh "Truncated: " . ( scalar keys %$truncated ) . "\n\n";
	$$buffer_ref .= "<p>These loci are incomplete and located at the ends of contigs in at least one isolate.</p>";
	print $fh "These loci are incomplete and located at the ends of contigs in at least one isolate.\n\n";
	$self->_print_locus_table( $buffer_ref, $fh, $truncated );
}

sub _print_locus_table {
	my ( $self, $buffer_ref, $fh, $loci ) = @_;
	$$buffer_ref .= "<div class=\"scrollable\">";
	$$buffer_ref .= "<table class=\"resultstable\"><tr><th>Locus</th><th>Product</th><th>Sequence length</th><th>Genome position</th>";
	print $fh "Locus\tProduct\tSequence length\tGenome position";
	$$buffer_ref .= "</tr>";
	print $fh "\n";
	my $td = 1;
	foreach ( sort keys %$loci ) {
		my $cleaned_locus = $self->clean_locus($_);
		$$buffer_ref .=
"<tr class=\"td$td\"><td>$cleaned_locus</td><td>$loci->{$_}->{'desc'}</td><td>$loci->{$_}->{'length'}</td><td>$loci->{$_}->{'start'}</td></tr>\n";
		print $fh "$_\t$loci->{$_}->{'desc'}\t$loci->{$_}->{'length'}\t$loci->{$_}->{'start'}\n";
		$td = $td == 1 ? 2 : 1;
	}
	$$buffer_ref .= "</table>\n";
	$$buffer_ref .= "</div>\n";
}

sub _extract_sequence {
	my ( $self, $match ) = @_;
	my $start  = $match->{'predicted_start'};
	my $end    = $match->{'predicted_end'};
	my $length = abs( $end - $start ) + 1;
	if ( $end < $start ) {
		$start = $end;
	}
	my $seq_ref =
	  $self->{'datastore'}
	  ->run_simple_query( "SELECT substring(sequence from $start for $length) FROM sequence_bin WHERE id=?", $match->{'seqbin_id'} );
	if ( ref $seq_ref eq 'ARRAY' ) {
		if ( $match->{'reverse'} ) {
			return BIGSdb::Utils::reverse_complement( $seq_ref->[0] );
		}
		return $seq_ref->[0];
	}
}

sub _blast {
	my ( $self, $word_size, $fasta_file, $in_file, $out_file, $blastx ) = @_;
	my $program = $blastx ? 'blastx' : 'blastn';
	if ( $self->{'config'}->{'blast+_path'} ) {
		my $blast_threads = $self->{'config'}->{'blast_threads'} || 1;
		my $filter = $program eq 'blastn' ? 'dust' : 'seg';
		system(
"$self->{'config'}->{'blast+_path'}/$program -num_threads $blast_threads -max_target_seqs 10 -parse_deflines -word_size $word_size -db $fasta_file -query $in_file -out $out_file -outfmt 6 -$filter no"
		);
	} else {
		system(
"$self->{'config'}->{'blast_path'}/blastall -b 10 -p $program -W $word_size -d $fasta_file -i $in_file -o $out_file -m8 -F F 2> /dev/null"
		);
	}
}

sub _parse_blast_by_locus {

	#return best match
	my ( $self, $locus, $blast_file, $params ) = @_;
	my $identity  = BIGSdb::Utils::is_int( $params->{'identity'} )  ? $params->{'identity'}  : 70;
	my $alignment = BIGSdb::Utils::is_int( $params->{'alignment'} ) ? $params->{'alignment'} : 50;
	my $full_path = "$blast_file";
	open( my $blast_fh, '<', $full_path ) || ( $logger->error("Can't open BLAST output file $full_path. $!"), return \$; );
	my $match;
	my $quality;    #simple metric of alignment length x percentage identity
	my $ref_seq_sql = $self->{'db'}->prepare("SELECT length(reference_sequence) FROM loci WHERE id=?");
	my %lengths;

	while ( my $line = <$blast_fh> ) {
		next if !$line || $line =~ /^#/;
		my @record = split /\s+/, $line;
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
			$match->{'reverse'}   = 1
			  if ( ( $record[8] > $record[9] && $record[7] > $record[6] ) || ( $record[8] < $record[9] && $record[7] < $record[6] ) );
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
	close $blast_fh;
	return $match;
}

sub _parse_blast_ref {

	#return best match
	my ( $self, $seq_ref, $blast_file, $params ) = @_;
	my $identity  = BIGSdb::Utils::is_int( $params->{'identity'} )  ? $params->{'identity'}  : 70;
	my $alignment = BIGSdb::Utils::is_int( $params->{'alignment'} ) ? $params->{'alignment'} : 50;
	open( my $blast_fh, '<', $blast_file ) || ( $logger->error("Can't open BLAST output file $blast_file. $!"), return \$; );
	my $match;
	my $quality;    #simple metric of alignment length x percentage identity
	my $ref_length = length $$seq_ref;
	while ( my $line = <$blast_fh> ) {
		next if !$line || $line =~ /^#/;
		my @record = split /\s+/, $line;
		my $this_quality = $record[3] * $record[2];
		if ( $this_quality > $quality && $record[3] >= $alignment * 0.01 * $ref_length && $record[2] > $identity ) {
			$quality              = $this_quality;
			$match->{'seqbin_id'} = $record[1];
			$match->{'identity'}  = $record[2];
			$match->{'alignment'} = $record[3];
			$match->{'start'}     = $record[8];
			$match->{'end'}       = $record[9];
			$match->{'reverse'} = 1 if ( $record[8] > $record[9] );
			if ( $ref_length > $match->{'alignment'} ) {

				if ( $match->{'reverse'} ) {
					$match->{'predicted_start'} = $match->{'start'} - $ref_length + $record[6];
					$match->{'predicted_end'}   = $match->{'end'} + $record[7] - 1;
				} else {
					$match->{'predicted_start'} = $match->{'start'} - $record[6] + 1;
					$match->{'predicted_end'}   = $match->{'end'} + $ref_length - $record[7];
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
		}
	}
	close $blast_fh;
	return $match;
}

sub _create_locus_FASTA_db {
	my ( $self, $locus, $prefix ) = @_;
	my $clean_locus = $locus;
	$clean_locus =~ s/\W/_/g;
	$clean_locus = $1 if $locus =~ /(\w*)/;    #avoid taint check
	my $temp_fastafile = "$self->{'config'}->{'secure_tmp_dir'}/$prefix\_fastafile_$clean_locus.txt";
	$temp_fastafile =~ s/\\/\\\\/g;
	$temp_fastafile =~ s/'/__prime__/g;
	if ( !-e $temp_fastafile ) {
		open( my $fasta_fh, '>', $temp_fastafile );
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		if ( $locus_info->{'dbase_name'} ) {
			my $seqs_ref = $self->{'datastore'}->get_locus($locus)->get_all_sequences;
			foreach ( keys %$seqs_ref ) {
				next if !length $seqs_ref->{$_};
				print $fasta_fh ">$_\n$seqs_ref->{$_}\n";
			}
		} else {
			print $fasta_fh ">ref\n$locus_info->{'reference_sequence'}\n";
		}
		close $fasta_fh;
		if ( $self->{'config'}->{'blast+_path'} ) {
			my $dbtype = $locus_info->{'data_type'} eq 'DNA' ? 'nucl' : 'prot';
			system("$self->{'config'}->{'blast+_path'}/makeblastdb -in $temp_fastafile -logfile /dev/null -parse_seqids -dbtype $dbtype");
		} else {
			if ( $locus_info->{'data_type'} eq 'DNA' ) {
				system("$self->{'config'}->{'blast_path'}/formatdb -i $temp_fastafile -p F -o T");
			} else {
				system("$self->{'config'}->{'blast_path'}/formatdb -i $temp_fastafile -p T -o T");
			}
		}
	}
	return $temp_fastafile;
}

sub _create_reference_FASTA_file {
	my ( $self, $seq_ref, $prefix ) = @_;
	my $temp_fastafile = "$self->{'config'}->{'secure_tmp_dir'}/$prefix\_fastafile.txt";
	open( my $fasta_fh, '>', $temp_fastafile );
	print $fasta_fh ">ref\n$$seq_ref\n";
	close $fasta_fh;
	return $temp_fastafile;
}

sub _create_isolate_FASTA {
	my ( $self, $isolate_id, $prefix, $params ) = @_;
	my $qry =
"SELECT DISTINCT id,sequence FROM sequence_bin LEFT JOIN experiment_sequences ON sequence_bin.id=seqbin_id LEFT JOIN project_members ON sequence_bin.isolate_id = project_members.isolate_id WHERE sequence_bin.isolate_id=?";
	my @criteria = ($isolate_id);
	my $method   = $params->{'seq_method'};
	if ($method) {
		if ( !any { $_ eq $method } SEQ_METHODS ) {
			$logger->error("Invalid method $method");
			return;
		}
		$qry .= " AND method=?";
		push @criteria, $method;
	}
	my $project = $params->{'project'};
	if ($project) {
		if ( !BIGSdb::Utils::is_int($project) ) {
			$logger->error("Invalid project $project");
			return;
		}
		$qry .= " AND project_id=?";
		push @criteria, $project;
	}
	my $experiment = $params->{'experiment'};
	if ($experiment) {
		if ( !BIGSdb::Utils::is_int($experiment) ) {
			$logger->error("Invalid experiment $experiment");
			return;
		}
		$qry .= " AND experiment_id=?";
		push @criteria, $experiment;
	}
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute(@criteria); };
	$logger->error($@) if $@;
	$isolate_id = $1 if $isolate_id =~ /(\d*)/;    #avoid taint check
	my $temp_infile = "$self->{'config'}->{'secure_tmp_dir'}/$prefix\_isolate_$isolate_id.txt";
	open( my $infile_fh, '>', $temp_infile );
	while ( my ( $id, $seq ) = $sql->fetchrow_array ) {
		print $infile_fh ">$id\n$seq\n";
	}
	close $infile_fh;
	return $temp_infile;
}

sub _create_isolate_FASTA_db {
	my ( $self, $isolate_id, $prefix ) = @_;
	my $temp_infile = $self->_create_isolate_FASTA( $isolate_id, $prefix );
	if ( $self->{'config'}->{'blast+_path'} ) {
		system("$self->{'config'}->{'blast+_path'}/makeblastdb -in $temp_infile -logfile /dev/null -parse_seqids -dbtype nucl");
	} else {
		system("$self->{'config'}->{'blast_path'}/formatdb -i $temp_infile -p F -o T");
	}
	return $temp_infile;
}
1;
