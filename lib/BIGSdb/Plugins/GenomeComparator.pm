#GenomeComparator.pm - Genome comparison plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2012, University of Oxford
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
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use Apache2::Connection ();
use Bio::SeqIO;
use Bio::AlignIO;
use List::MoreUtils qw(uniq any none);
use Digest::MD5;
use BIGSdb::Page qw(SEQ_METHODS LOCUS_PATTERNS);
use constant MAX_UPLOAD_SIZE => 32768;
use constant MAX_SPLITS_TAXA => 200;
use constant MAX_DISPLAY_TAXA => 150;

sub get_attributes {
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
		version     => '1.4.0',
		dbtype      => 'isolates',
		section     => 'analysis,postquery',
		order       => 30,
		requires    => 'muscle,offline_jobs,js_tree',
		input       => 'query',
		help        => 'tooltips',
		system_flag => 'GenomeComparator'
	);
	return \%att;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { 'general' => 1, 'main_display' => 0, 'isolate_display' => 0, 'analysis' => 1, 'query_field' => 1 };
	return;
}

sub get_plugin_javascript {
	my ($self) = @_;
	my $buffer = << "END";
function listbox_selectall(listID, isSelect) {
	var listbox = document.getElementById(listID);
	for(var count=0; count < listbox.options.length; count++) {
		listbox.options[count].selected = isSelect;
	}
}

function enable_seqs(){
	if (\$("#accession").val() || \$("#ref_upload").val() || \$("#annotation").val()){
		\$("#scheme_fieldset").hide(500);
		\$("#locus_fieldset").hide(500);
		\$("#tblastx").attr("disabled", false);
		\$("#use_tagged").attr("disabled", true);
	} else {
		\$("#scheme_fieldset").show(500);
		\$("#locus_fieldset").show(500);
		\$("#tblastx").attr("disabled", true);
		\$("#use_tagged").attr("disabled", false);
	}
	if (\$("#align").attr('checked')){
		\$("#align_all").attr("disabled", false);
	} else {
		\$("#align_all").attr("disabled", true);
	}
	if ((\$("#accession").val() || \$("#ref_upload").val() || \$("#annotation").val()) && \$("#align").attr('checked')){
		\$("#include_ref").attr("disabled", false);
	} else {
		\$("#include_ref").attr("disabled", true);
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
	my @loci = split /\|\|/, $params->{'locus'} // '';
	my @ids = split /\|\|/, $params->{'isolate_id'};
	my $filtered_ids = $self->_filter_ids_by_project( \@ids, $params->{'project_list'} );
	my @scheme_ids = split /\|\|/, ( defined $params->{'scheme_id'} ? $params->{'scheme_id'} : '' );
	my $accession = $params->{'accession'} || $params->{'annotation'};
	my $ref_upload = $params->{'ref_upload'};
	if ( !@$filtered_ids ) {
		$self->{'jobManager'}->update_job_status(
			$job_id,
			{
				'status'       => 'failed',
				'message_html' => "<p class=\"statusbad\">You must include one or more isolates. Make "
				  . "sure your selected isolates haven't been filtered to none by selecting a project.</p>"
			}
		);
		return;
	}
	if ( !$accession && !$ref_upload && !@loci && !@scheme_ids ) {
		$self->{'jobManager'}->update_job_status(
			$job_id,
			{
				'status'       => 'failed',
				'message_html' => "<p class=\"statusbad\">You must either select one or more loci or schemes, "
				  . "provide a genome accession number, or upload an annotated genome.</p>"
			}
		);
		return;
	}
	if ( $accession || $ref_upload ) {
		my $seq_obj;
		if ($accession) {
			my $seq_db = Bio::DB::GenBank->new;
			$seq_db->verbose(2);    #convert warn to exception
			try {
				$seq_obj = $seq_db->get_Seq_by_acc($accession);
			}
			catch Bio::Root::Exception with {
				my $err = shift;
				$logger->debug($err);
				throw BIGSdb::PluginException("No data returned for accession number $accession.\n");
			};
		} else {
			eval {
				my $seqio_object = Bio::SeqIO->new( -file => "$self->{'config'}->{'tmp_dir'}/$ref_upload" );
				$seq_obj = $seqio_object->next_seq;
			};
			if ($@) {
				throw BIGSdb::PluginException("Invalid data in uploaded reference file.");
			}
			unlink "$self->{'config'}->{'tmp_dir'}/$ref_upload";
		}
		return if !$seq_obj;
		$self->_analyse_by_reference( $job_id, $params, $accession, $seq_obj, $filtered_ids );
	} else {
		$self->_add_scheme_loci( $params, \@loci );
		$self->_analyse_by_loci( $job_id, $params, \@loci, $filtered_ids );
	}
	return;
}

sub run {
	my ($self) = @_;
	my @patterns = LOCUS_PATTERNS;
	print "<h1>Genome Comparator</h1>\n";
	my $q = $self->{'cgi'};
	if ( $q->param('submit') ) {
		my @ids          = $q->param('isolate_id');
		my $ref_upload   = $q->param('ref_upload') ? $self->_upload_ref_file : undef;
		my $filtered_ids = $self->_filter_ids_by_project( \@ids, $q->param('project_list') );
		my $continue     = 1;
		if ( !@$filtered_ids ) {
			print "<div class=\"box\" id=\"statusbad\"><p>You must include one or more isolates. Make sure your "
			  . "selected isolates haven't been filtered to none by selecting a project.</p></div>\n";
			$continue = 0;
		}
		my @loci = $q->param('locus');
		my @cleaned_loci;
		foreach my $locus (@loci) {
			my $locus_name = $locus ~~ @patterns ? $1 : undef;
			push @cleaned_loci, $locus_name if defined $locus_name;
		}
		$q->param( 'locus', uniq @cleaned_loci );
		my $scheme_ids = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
		push @$scheme_ids, 0;
		my $accession = $q->param('accession') || $q->param('annotation');
		if ( !$accession && !$ref_upload && !@loci && ( none { $q->param("s_$_") } @$scheme_ids ) && $continue ) {
			print "<div class=\"box\" id=\"statusbad\"><p>You must either select one or more loci or schemes, provide "
			  . "a genome accession number, or upload an annotated genome.</p></div>\n";
			$continue = 0;
		}
		my @selected_schemes;
		foreach (@$scheme_ids) {
			next if !$q->param("s_$_");
			push @selected_schemes, $_;
			$q->delete("s_$_");
		}
		local $" = '||';
		my $scheme_string = "@selected_schemes";
		$q->param( 'scheme_id', $scheme_string );
		$q->param( 'ref_upload', $ref_upload ) if $ref_upload;
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		if ($continue) {
			my $params = $q->Vars;
			my $job_id = $self->{'jobManager'}->add_job(
				{
					'dbase_config' => $self->{'instance'},
					'ip_address'   => $q->remote_host,
					'module'       => 'GenomeComparator',
					'parameters'   => $params,
					'username'     => $self->{'username'},
					'email'        => $user_info->{'email'}
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
	my $format = $self->{'cgi'}->param('ref_upload') =~ /.+(\.\w+)$/ ? "$1" : '';
	my $filename = "$self->{'config'}->{'tmp_dir'}/$temp\_ref$format";
	my $buffer;
	my $buffer_size = MAX_UPLOAD_SIZE;
	open( my $fh, '>', $filename ) || $logger->error("Could not open $filename for writing.");
	my $fh2 = $self->{'cgi'}->upload('ref_upload');
	binmode $fh2;
	binmode $fh;
	print $fh $buffer while ( read( $fh2, $buffer, $buffer_size ) );
	close $fh;
	return "$temp\_ref$format";
}

sub _print_interface {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $view       = $self->{'system'}->{'view'};
	my $query_file = $q->param('query_file');
	my $qry_ref    = $self->get_query($query_file);
	my $selected_ids = defined $query_file ? $self->get_ids_from_query($qry_ref) : [];
	my $guid = $self->get_guid;
	my $qry;
	my $use_all;
	try {
		my $pref = $self->{'prefstore'}->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'GenomeComparator', 'use_all' );
		$use_all = ( defined $pref && $pref eq 'true' ) ? 1 : 0;
	}
	catch BIGSdb::DatabaseNoRecordException with {
		$use_all = 0;
	};
	if ($use_all) {
		$qry = "SELECT DISTINCT $view.id,$view.$self->{'system'}->{'labelfield'} FROM $view ORDER BY $view.id";
	} else {
		$qry = "SELECT DISTINCT $view.id,$view.$self->{'system'}->{'labelfield'} FROM sequence_bin LEFT JOIN $view "
		  . "ON $view.id=sequence_bin.isolate_id ORDER BY $view.id";
	}
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error($@) if $@;
	my @ids;
	my %labels;
	while ( my ( $id, $isolate ) = $sql->fetchrow_array ) {
		next if !defined $id;
		push @ids, $id;
		$labels{$id} = "$id) $isolate";
	}
	if ( !@ids ) {
		print "<div class=\"box\" id=\"statusbad\"><p>There are no sequences in the sequence bin.</p></div>\n";
		return;
	}
	print <<"HTML";
<div class="box" id="queryform">
<p>Please select the required isolate ids and loci for comparison - use ctrl or shift to make multiple 
selections. In addition to selecting individual loci, you can choose to include all loci defined in schemes 
by selecting the appropriate scheme description. Alternatively, you can enter the accession number for an 
annotated reference genome and compare using the loci defined in that.</p>
HTML
	my ( $locus_list, $locus_labels ) = $self->get_field_selection_list( { loci => 1, analysis_pref => 1, query_pref => 0, sort_labels => 1 } );
	print $q->start_form;
	print "<div class=\"scrollable\">\n";
	print "<fieldset style=\"float:left\">\n<legend>Isolates</legend>\n";
	print $q->scrolling_list(
		-name     => 'isolate_id',
		-id       => 'isolate_id',
		-values   => \@ids,
		-labels   => \%labels,
		-size     => 8,
		-multiple => 'true',
		-default  => $selected_ids
	);
	print <<"HTML";
<div style="text-align:center"><input type="button" onclick='listbox_selectall("isolate_id",true)' value="All" style="margin-top:1em" class="smallbutton" />
<input type="button" onclick='listbox_selectall("isolate_id",false)' value="None" style="margin-top:1em" class="smallbutton" /></div>
</fieldset>
<fieldset id="locus_fieldset" style="float:left">\n<legend>Loci</legend>
HTML
	print $q->scrolling_list(
		-name     => 'locus',
		-id       => 'locus',
		-values   => $locus_list,
		-labels   => $locus_labels,
		-size     => 8,
		-multiple => 'true'
	);
	print <<"HTML";
<div style="text-align:center"><input type="button" onclick='listbox_selectall("locus",true)' value="All" style="margin-top:1em" class="smallbutton" />
<input type="button" onclick='listbox_selectall("locus",false)' value="None" style="margin-top:1em" class="smallbutton" /></div>
</fieldset>
<fieldset id="scheme_fieldset" style="float:left"><legend>Schemes</legend>
<noscript><p class="highlight">Enable Javascript to select schemes.</p></noscript>
<div id="tree" class="tree" style="height:150px; width:20em">
HTML
	print $self->get_tree( undef, { no_link_out => 1, select_schemes => 1 } );
	print "</div>\n</fieldset>\n";
	print "<fieldset style=\"float:left\">\n<legend>Reference genome</legend>\n";
	print "Enter accession number:<br />\n";
	print $q->textfield( -name => 'accession', -id => 'accession', -size => 10, -maxlength => 20 );
	print " <a class=\"tooltip\" title=\"Reference genome - Use of a reference genome will override any locus "
	  . "or scheme settings.\">&nbsp;<i>i</i>&nbsp;</a><br />";

	if ( $self->{'system'}->{'annotation'} ) {
		my @annotations = split /;/, $self->{'system'}->{'annotation'};
		my @names = ('');
		my %labels;
		foreach (@annotations) {
			my ( $accession, $name ) = split /\|/, $_;
			if ( $accession && $name ) {
				push @names, $accession;
				$labels{$accession} = $name;
			}
		}
		if (@names) {
			print "or choose annotated genome:<br />\n";
			print $q->popup_menu(
				-name     => 'annotation',
				-id       => 'annotation',
				-values   => \@names,
				-labels   => \%labels,
				-onChange => 'enable_seqs()',
			);
		}
		print "<br />\n";
	}
	print "or upload Genbank/EMBL file:<br />";
	print $q->filefield( -name => 'ref_upload', -id => 'ref_upload', -size => 10, -maxlength => 512, -onChange => 'enable_seqs()', );
	print " <a class=\"tooltip\" title=\"Reference upload - File format is recognised by the extension in the "
	  . "name.  Make sure your file has a standard extension, e.g. .gb, .embl.\">&nbsp;<i>i</i>&nbsp;</a><br />\n";
	print "</fieldset>\n<fieldset style=\"float:left\">\n<legend>Parameters / options</legend>\n";
	print "<ul><li><label for =\"identity\" class=\"parameter\">Min % identity:</label>\n";
	print $q->popup_menu(
		-name    => 'identity',
		-id      => 'identity',
		-values  => [qw(30 35 40 45 50 55 60 65 70 75 80 85 90 91 92 93 94 95 96 97 98 99 100)],
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
	print "<li><span class=\"warning\">";
	print $q->checkbox( -name => 'tblastx', -id => 'tblastx', -label => 'Use TBLASTX' );
	print <<"HTML";
 <a class="tooltip" title="TBLASTX (analysis by reference genome only) - Compares the six-frame translation of your nucleotide 
query against the six-frame translation of the sequences in the sequence bin (sequences will be classed as identical if they 
result in the same translated sequence even if the nucleotide sequence is different).  This is SLOWER than BLASTN. Use with
caution.">&nbsp;<i>i</i>&nbsp;</a></span></li><li>
HTML
	print $q->checkbox( -name => 'align', -id => 'align', -label => 'Produce alignments (Clustal + XMFA)', -onChange => "enable_seqs()" );
	print <<"HTML";
 <a class=\"tooltip\" title=\"Alignments - Alignments will be produced in muscle for 
any loci that vary between isolates. This may slow the analysis considerably.">&nbsp;<i>i</i>&nbsp;</a></li><li>
HTML
	print $q->checkbox( -name => 'include_ref', -id => 'include_ref', -label => 'Include ref sequences in alignment', -checked => 1 );
	print "</li><li>";
	print $q->checkbox( -name => 'align_all', -id => 'align_all', -label => 'Align all loci (not only variable)' );
	print "</li><li>";
	print $q->checkbox( -name => 'use_tagged', -id => 'use_tagged', -label => 'Use tagged designations if available', -checked => 1 );
	print <<"HTML";
 <a class=\"tooltip\" title=\"Tagged desginations - Allele sequences will be extracted from the definition database based on allele 
designation rather than by BLAST.  This should be much quicker. Peptide loci, however, are always extracted using BLAST.">
&nbsp;<i>i</i>&nbsp;</a></li></ul></fieldset><fieldset style="float:left"><legend>Restrict included sequences by</legend><ul>
HTML
	my $buffer = $self->get_sequence_method_filter( { 'class' => 'parameter' } );
	print "<li>$buffer</li>" if $buffer;
	$buffer = $self->get_project_filter( { 'class' => 'parameter' } );
	print "<li>$buffer</li>" if $buffer;
	$buffer = $self->get_experiment_filter( { 'class' => 'parameter' } );
	print "<li>$buffer</li>" if $buffer;
	print "</ul>\n</fieldset>\n</div>\n";
	print "<table style=\"width:95%\"><tr><td style=\"text-align:left\">";
	print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;name=GenomeComparator\" class=\"resetbutton\">"
	  . "Reset</a></td><td style=\"text-align:right\" colspan=\"4\">";
	print $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
	print "</td></tr></table>\n";
	print $q->hidden($_) foreach qw (page name db);
	print $q->end_form;
	print "</div>\n";
	return;
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
				  "<p class=\"statusbad\">You must select at least two isolates for comparison against defined loci. Make sure "
				  . "your selected isolates haven't been filtered to fewer than two by selecting a project.</p>"
			}
		);
		return;
	}
	my %isolate_FASTA;
	foreach (@$ids) {
		$isolate_FASTA{$_} = $self->_create_isolate_FASTA( $_, $job_id, $params );
	}
	my $html_buffer = "<h3>Analysis against defined loci</h3>\n";
	my $file_buffer = "Analysis against defined loci\n";
	$file_buffer .= "Time: " . ( localtime(time) ) . "\n\n";
	$html_buffer .= "<p>Allele numbers are used where these have been defined, otherwise sequences will be marked as 'New#1, "
	  . "'New#2' etc. Missing alleles are marked as 'X'. Truncated alleles (located at end of contig) are marked as 'T'.</p>";
	$file_buffer .= "Allele numbers are used where these have been defined, otherwise sequences will be marked as 'New#1, "
	  . "'New#2' etc.\nMissing alleles are marked as 'X'. Truncated alleles (located at end of contig) are marked as 'T'.\n\n";
	$self->_print_isolate_header( 0, $ids, \$file_buffer, \$html_buffer, );
	$self->_run_comparison( 0, $job_id, $params, $ids, $loci, \$html_buffer, \$file_buffer );
	system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$job_id\*";
	return;
}

sub _generate_splits {
	my ( $self, $job_id, $values, $ignore_loci_ref ) = @_;
	my $dismat = $self->_generate_distance_matrix( $values, $ignore_loci_ref );
	my $nexus_file = $self->_make_nexus_file( $job_id, $dismat );
	$self->{'jobManager'}->update_job_output(
		$job_id,
		{
			filename => $nexus_file,
			description =>
			  '20_Distance matrix (Nexus format)|Suitable for loading in to <a href="http://www.splitstree.org">SplitsTree</a>. '
			  . 'Distances between taxa are calculated as the number of loci with different allele sequences'
		}
	);
	return if (keys %$values) > MAX_SPLITS_TAXA;
	my $splits_img = "$job_id.png";
	$self->_run_splitstree( "$self->{'config'}->{'tmp_dir'}/$nexus_file", "$self->{'config'}->{'tmp_dir'}/$splits_img", 'PNG' );
	if ( -e "$self->{'config'}->{'tmp_dir'}/$splits_img" ) {
		$self->{'jobManager'}
		  ->update_job_output( $job_id, { filename => $splits_img, description => '25_Splits graph (Neighbour-net; PNG format)' } );
	}
	$splits_img = "$job_id.svg";
	$self->_run_splitstree( "$self->{'config'}->{'tmp_dir'}/$nexus_file", "$self->{'config'}->{'tmp_dir'}/$splits_img", 'SVG' );
	if ( -e "$self->{'config'}->{'tmp_dir'}/$splits_img" ) {
		$self->{'jobManager'}->update_job_output(
			$job_id,
			{
				filename => $splits_img,
				description =>
				  '26_Splits graph (Neighbour-net; SVG format)|This can be edited in <a href="http://inkscape.org">Inkscape</a> or other '
				  . 'vector graphics editors'
			}
		);
	}
	return;
}

sub _generate_distance_matrix {
	my ( $self, $values, $ignore_loci_ref ) = @_;
	my @ids = sort { $a <=> $b } keys %$values;
	my $dismat;
	foreach my $i ( 0 .. @ids - 1 ) {
		foreach my $j ( 0 .. $i ) {
			$dismat->{ $ids[$i] }->{ $ids[$j] } = 0;
			foreach my $locus ( keys %{ $values->{ $ids[$i] } } ) {
				next if any { $locus eq $_ } @$ignore_loci_ref;
				if ( $values->{ $ids[$i] }->{$locus} ne $values->{ $ids[$j] }->{$locus} ) {
					$dismat->{ $ids[$i] }->{ $ids[$j] }++;
				}
			}
		}
	}
	return $dismat;
}

sub _run_splitstree {
	my ( $self, $nexus_file, $output_file, $format ) = @_;
	if ( $self->{'config'}->{'splitstree_path'} && -x $self->{'config'}->{'splitstree_path'} ) {
		system "$self->{'config'}->{'splitstree_path'} +g false -S true "
		  . "-x \"EXECUTE FILE=$nexus_file;EXPORTGRAPHICS format=$format file=$output_file REPLACE=yes;QUIT\"";
	}
	return;
}

sub _make_nexus_file {
	my ( $self, $job_id, $dismat ) = @_;
	my $timestamp = scalar localtime;
	my @ids = sort { $a <=> $b } keys %$dismat;
	my %labels;
	my $sql = $self->{'db'}->prepare("SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?");
	foreach (@ids) {
		if ( $_ == 0 ) {
			$labels{$_} = "ref";
		} else {
			eval { $sql->execute($_) };
			$logger->error($@) if $@;
			my ($name) = $sql->fetchrow_array;
			$name =~ tr/[\(\) ]/_/;
			$labels{$_} = "$_|$name";
		}
	}
	my $num_taxa = @ids;
	my $header   = <<"NEXUS";
#NEXUS
[Distance matrix calculated by BIGSdb Genome Comparator ($timestamp)]
[Jolley & Maiden 2010 BMC Bioinformatics 11:595]

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
	open( my $nexus_fh, '>', "$self->{'config'}->{'tmp_dir'}/$job_id.nex" ) || $logger->error("Can't open $job_id.nex for writing");
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

sub _add_scheme_loci {
	my ( $self, $params, $loci ) = @_;
	my @scheme_ids = split /\|\|/, ( defined $params->{'scheme_id'} ? $params->{'scheme_id'} : '' );
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
	return;
}

sub _analyse_by_reference {
	my ( $self, $job_id, $params, $accession, $seq_obj, $ids ) = @_;
	my @cds;
	foreach ( $seq_obj->get_SeqFeatures ) {
		push @cds, $_ if $_->primary_tag eq 'CDS';
	}
	my $html_buffer = "<h3>Analysis by reference genome</h3>";
	my %att;
	eval {
		%att = (
			'accession'   => $accession,
			'version'     => $seq_obj->seq_version,
			'type'        => $seq_obj->alphabet,
			'length'      => $seq_obj->length,
			'description' => $seq_obj->description,
			'cds'         => scalar @cds
		);
	};
	if ($@) {
		throw BIGSdb::PluginException("Invalid data in reference genome.");
	}
	my %abb = ( 'cds' => 'coding regions' );
	$html_buffer .= "<table class=\"resultstable\">";
	my $td = 1;
	my $file_buffer = "Analysis by reference genome\n\nTime: " . ( localtime(time) ) . "\n\n";
	foreach (qw (accession version type length description cds)) {
		if ( $att{$_} ) {
			$html_buffer .= "<tr class=\"td$td\"><th>" . ( $abb{$_} || $_ ) . "</th><td style=\"text-align:left\">$att{$_}</td></tr>";
			$file_buffer .= ( $abb{$_} || $_ ) . ": $att{$_}\n";
			$td = $td == 1 ? 2 : 1;
		}
	}
	$html_buffer .= "</table>";
	$self->{'jobManager'}->update_job_status( $job_id, { message_html => $html_buffer } );
	my %loci;
	$html_buffer .= "<h3>All loci</h3>\n";
	$file_buffer .= "\n\nAll loci\n--------\n\n";
	$html_buffer .= "<p>Each unique allele is defined a number starting at 1. Missing alleles are marked as 'X'. "
	  . "Truncated alleles (located at end of contig) are marked as 'T'.</p>";
	$file_buffer .= "Each unique allele is defined a number starting at 1. Missing alleles are marked as 'X'. \n"
	  . "Truncated alleles (located at end of contig) are marked as 'T'.\n\n";
	$self->_print_isolate_header( 1, $ids, \$file_buffer, \$html_buffer, );
	$self->_run_comparison( 1, $job_id, $params, $ids, \@cds, \$html_buffer, \$file_buffer );
	return;
}

sub _extract_cds_details {
	my ( $self, $cds, $seqs_total_ref, $seqs_ref ) = @_;
	my ( $locus_name, $length, $start, $desc );
	my @aliases;
	my $locus;
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
	local $" = ' | ';
	$locus_name = $locus;
	$locus_name .= " | @aliases" if @aliases;
	my $seq = $cds->seq->seq;
	return if !$seq;
	$$seqs_total_ref++;
	$seqs_ref->{'ref'} = $seq;
	my @tags;
	try {
		push @tags, $_ foreach ( $cds->each_tag_value('product') );
	}
	catch Bio::Root::Exception with {
		my $err = shift;
		$logger->debug($err);
		throw BIGSdb::DataException($err);
	};
	throw BIGSdb::DataException("No tags") if !@tags;
	$start = $cds->start;
	local $" = '; ';
	$desc = "@tags";
	return ( $locus_name, \$seq, $start, $desc );
}

sub _run_comparison {
	my ( $self, $by_reference, $job_id, $params, $ids, $cds, $html_buffer_ref, $file_buffer_ref ) = @_;
	my $progress    = 0;
	my $total       = ( $params->{'align'} && (@$ids > 1 || (@$ids == 1 && $by_reference && $params->{'align_all'})) ) ? ( @$cds * 2 ) : @$cds;
	my $seqs_total  = 0;
	my $close_table = '</table></div>';
	my $td          = 1;
	my ( $exacts, $exact_except_ref, $all_missing, $truncated_loci, $varying_loci );
	my ( $word_size, $program );
	my $job_file         = "$self->{'config'}->{'tmp_dir'}/$job_id.txt";
	my $align_file       = "$self->{'config'}->{'tmp_dir'}/$job_id\_align.txt";
	my $align_stats_file = "$self->{'config'}->{'tmp_dir'}/$job_id\_align_stats.txt";
	my $prefix           = BIGSdb::Utils::get_random();
	my $values;
	my %isolate_FASTA;
	$isolate_FASTA{$_} = $self->_create_isolate_FASTA_db( $_, $prefix ) foreach (@$ids);

	if ( $by_reference && $params->{'tblastx'} ) {
		$program   = 'tblastx';
		$word_size = 3;
	} else {
		$program = 'blastn';
		$word_size = $params->{'word_size'} =~ /^(\d+)$/ ? $1 : 15;
	}
	my $loci;
	foreach my $cds (@$cds) {
		my %seqs;
		my $seq_ref;
		my ( $locus_name, $locus_info, $length, $start, $desc, $ref_seq_file );
		if ($by_reference) {
			my $continue = 1;
			try {
				( $locus_name, $seq_ref, $start, $desc ) = $self->_extract_cds_details( $cds, \$seqs_total, \%seqs );
			}
			catch BIGSdb::DataException with {
				$$html_buffer_ref .=
"\n$close_table<p class=\"statusbad\">Error: There are no product tags defined in record with supplied accession number.</p>\n";
				$self->{'jobManager'}->update_job_status( $job_id, { status => 'failed', message_html => $$html_buffer_ref } );
				$continue = 0;
			};
			return if !$continue || ref $seq_ref ne 'SCALAR';
			$values->{'0'}->{$locus_name} = 1;
			$length = length $$seq_ref;
			$length = int( $length / 3 ) if $params->{'tblastx'};
			$ref_seq_file = $self->_create_reference_FASTA_file( $seq_ref, $prefix );
			$loci->{$locus_name}->{'ref'} = $$seq_ref;
		} else {
			$ref_seq_file = $self->_create_locus_FASTA_db( $cds, $job_id );
			$locus_name   = $self->clean_locus($cds);
			$locus_info   = $self->{'datastore'}->get_locus_info($cds);
		}
		my $seqbin_length_sql    = $self->{'db'}->prepare("SELECT length(sequence) FROM sequence_bin where id=?");
		my $all_exact            = 1;
		my $missing_in_all       = 1;
		my $exact_except_for_ref = 1;
		my $truncated_locus      = 0;
		my $first                = 1;
		my $first_seq;
		my $previous_seq = '';
		$$html_buffer_ref .= "<tr class=\"td$td\"><td>$locus_name</td>";
		$$file_buffer_ref .= "$locus_name";
		my %allele_seqs;

		if ($by_reference) {
			$$html_buffer_ref .= "<td>$desc</td><td>$length</td><td>$start</td><td>1</td>";
			$$file_buffer_ref .= "\t$desc\t$length\t$start\t1";
			$allele_seqs{$$seq_ref} = 1;
		}
		my $allele = $by_reference ? 1 : 0;
		my $colour = 0;
		my %value_colour;
		foreach my $id (@$ids) {
			$id = $1 if $id =~ /(\d*)/;    #avoid taint check
			my $out_file = "$self->{'config'}->{'secure_tmp_dir'}/$prefix\_isolate_$id\_outfile.txt";
			my $match;
			my $extracted_seq;
			my $value;
			if ( !$by_reference ) {
				if ( $params->{'use_tagged'} && $locus_info->{'data_type'} eq 'DNA' ) {
					my $allele_id = $self->{'datastore'}->get_allele_id( $id, $cds );
					if ( defined $allele_id ) {
						$match->{'exact'}  = 1;
						$match->{'allele'} = $allele_id;
						$value             = $allele_id;
						try {
							my $seq_ref = $self->{'datastore'}->get_locus($cds)->get_allele_sequence($allele_id);
							$extracted_seq = $$seq_ref if ref $seq_ref eq 'SCALAR';
							$seqs{$id} = $extracted_seq;
							$allele_seqs{$allele_id} = $extracted_seq;
						}
						catch BIGSdb::DatabaseConnectionException with {

							#ignore
							$logger->debug("No connection to $cds database");
						}
					}
				}
				if ( !$match->{'exact'} && !-z $ref_seq_file ) {
					if ( $locus_info->{'data_type'} eq 'DNA' ) {
						$self->_blast( $word_size, $ref_seq_file, $isolate_FASTA{$id}, $out_file, 'blastn' );
					} else {
						$self->_blast( 3, $ref_seq_file, $isolate_FASTA{$id}, $out_file, 'blastx' );
					}
					$match = $self->_parse_blast_by_locus( $cds, $out_file, $params );
					$value = $match->{'allele'} if $match->{'exact'};
				}
			} else {
				$self->_blast( $word_size, $isolate_FASTA{$id}, $ref_seq_file, $out_file, $program );
				$match = $self->_parse_blast_ref( $seq_ref, $out_file, $params );
			}
			my $seqbin_length;
			if ( ref $match eq 'HASH' && ( $match->{'identity'} || $match->{'allele'} ) ) {
				$missing_in_all = 0;
				if ($by_reference) {
					if ( $match->{'identity'} == 100 && $match->{'alignment'} >= $length ) {
						$exact_except_for_ref = 0;
					} else {
						$all_exact = 0;
					}
				}
				eval { $seqbin_length_sql->execute( $match->{'seqbin_id'} ); };
				$logger->error($@) if $@;
				($seqbin_length) = $seqbin_length_sql->fetchrow_array;
				if ( !$match->{'exact'} && $match->{'predicted_start'} && $match->{'predicted_end'} ) {
					if ( $match->{'predicted_start'} < 1 ) {
						$match->{'predicted_start'} = 1;
						$truncated_locus            = 1;
						$value                      = 'T';
					} elsif ( $match->{'predicted_start'} > $seqbin_length ) {
						$match->{'predicted_start'} = $seqbin_length;
						$truncated_locus            = 1;
						$value                      = 'T';
					}
					if ( $match->{'predicted_end'} < 1 ) {
						$match->{'predicted_end'} = 1;
						$truncated_locus          = 1;
						$value                    = 'T';
					} elsif ( $match->{'predicted_end'} > $seqbin_length ) {
						$match->{'predicted_end'} = $seqbin_length;
						$truncated_locus          = 1;
						$value                    = 'T';
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
							$exact_except_for_ref = 0;
						}
					}
				}
			} else {
				$all_exact            = 0;
				$exact_except_for_ref = 0;
			}
			if ( !$value ) {
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
			given ($value) {
				when ('T') { $style = 'background:green; color:white' }
				when ('X') { $style = 'background:black; color:white' }
				default {
					if ( !$value_colour{$value} ) {
						$colour++;
						$value_colour{$value} = $colour;
					}
					$style = BIGSdb::Utils::get_style( $value_colour{$value}, scalar @$ids );
				}
			}
			$self->{'style'}->{$locus_name}->{$value} = $style;
			$$html_buffer_ref .= "<td style=\"$style\">$value</td>";
			$$file_buffer_ref .= "\t$value";
			$first                        = 0;
			$values->{$id}->{$locus_name} = $value;
			$loci->{$locus_name}->{$id}   = $seqs{$id};
		}
		$td = $td == 1 ? 2 : 1;
		$$html_buffer_ref .= "</tr>\n";
		$$file_buffer_ref .= "\n";
		if ( !$by_reference ) {
			$all_exact = 0 if ( uniq (values %seqs // ()) ) > 1;
		}
		if ($all_exact) {
			$exacts->{$locus_name}->{'length'} = length $$seq_ref if $by_reference;
			$exacts->{$locus_name}->{'desc'}   = $desc;
			$exacts->{$locus_name}->{'start'}  = $start;
		} elsif ($missing_in_all) {
			$all_missing->{$locus_name}->{'length'} = length $$seq_ref if $by_reference;
			$all_missing->{$locus_name}->{'desc'}   = $desc;
			$all_missing->{$locus_name}->{'start'}  = $start;
		} elsif ( $exact_except_for_ref && $by_reference ) {
			$exact_except_ref->{$locus_name}->{'length'} = length $$seq_ref;
			$exact_except_ref->{$locus_name}->{'desc'}   = $desc;
			$exact_except_ref->{$locus_name}->{'start'}  = $start;
		} elsif ($truncated_locus) {
			$truncated_loci->{$locus_name}->{'length'} = length $$seq_ref if $by_reference;
			$truncated_loci->{$locus_name}->{'desc'}   = $desc;
			$truncated_loci->{$locus_name}->{'start'}  = $start;
		} else {
			$varying_loci->{$locus_name}->{'length'} = length $$seq_ref if $by_reference;
			$varying_loci->{$locus_name}->{$_} = $seqs{$_} foreach ( keys %seqs );
			$varying_loci->{$locus_name}->{'desc'}  = $desc;
			$varying_loci->{$locus_name}->{'start'} = $start;
		}
		$progress++;
		my $complete = int( 100 * $progress / $total );
		if (@$ids > MAX_DISPLAY_TAXA){
			$self->{'jobManager'}
		  ->update_job_status( $job_id, { percent_complete => $complete, message_html => "<p>Dynamically updated output disabled as >" . MAX_DISPLAY_TAXA . " taxa selected.</p>" } );
		} else {
			$self->{'jobManager'}
		  ->update_job_status( $job_id, { percent_complete => $complete, message_html => "$$html_buffer_ref$close_table" } );
		}
	}
	$$html_buffer_ref .= $close_table;
	open( my $job_fh, '>', $job_file ) || $logger->error("Can't open $job_file for writing");
	print $job_fh $$file_buffer_ref;
	close $job_fh;
	if ( $params->{'align'} ) {
		$self->_create_alignments( $job_id, $by_reference, $align_file, $align_stats_file, $ids,
			( $params->{'align_all'} ? $loci : $varying_loci ), $params );
		open( my $align_fh, '>>', $align_file ) || $logger->error("Can't open $align_file for appending");
		close $align_fh;
	}
	$self->_print_variable_loci( $by_reference, $ids, $html_buffer_ref, $job_file, $varying_loci, $values );
	$self->_print_missing_in_all( $by_reference, $ids, $html_buffer_ref, $job_file, $all_missing, $values );
	$self->_print_exact_matches( $by_reference, $ids, $html_buffer_ref, $job_file, $exacts, $params, $values );
	if ($by_reference) {
		$self->_print_exact_except_ref( $ids, $html_buffer_ref, $job_file, $exact_except_ref, $values );
	}
	$self->_print_truncated_loci( $by_reference, $ids, $html_buffer_ref, $job_file, $truncated_loci, $values );
	 if ( !$seqs_total && $by_reference ){
		$$html_buffer_ref .= "<p class=\"statusbad\">No sequences were extracted from reference file.</p>\n";
	 } else {
		$self->_identify_strains( $ids, $html_buffer_ref, $job_file, $loci, $values );
		$$html_buffer_ref = '' if @$ids > MAX_DISPLAY_TAXA;
		$self->{'jobManager'}->update_job_status( $job_id, { message_html => $$html_buffer_ref } );
	 }
	close $job_fh;
	system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$prefix\*";
	$self->{'jobManager'}->update_job_output( $job_id, { filename => "$job_id.txt", description => '01_Main output file' } );
	my @ignore_loci;
	push @ignore_loci, $_ foreach keys %$truncated_loci;
	$self->_generate_splits( $job_id, $values, \@ignore_loci );
	if ( $params->{'align'} && (@$ids > 1 || (@$ids == 1 && $by_reference && $params->{'align_all'}))) {
		$self->{'jobManager'}->update_job_output( $job_id, { filename => "$job_id\_align.txt", description => '30_Alignments' } )
		  if -e $align_file;
		$self->{'jobManager'}->update_job_output( $job_id, { filename => "$job_id\_align_stats.txt", description => '31_Alignment stats' } )
		  if -e $align_stats_file;
		if ( -e "$self->{'config'}->{'tmp_dir'}/$job_id\.xmfa" ) {
			$self->{'jobManager'}
			  ->update_job_output( $job_id, { filename => "$job_id.xmfa", description => '35_Extracted sequences (XMFA format)' } );
			try {
				my $fasta_file = BIGSdb::Utils::xmfa2fasta("$self->{'config'}->{'tmp_dir'}/$job_id\.xmfa");
				if ( -e $fasta_file ) {
					$self->{'jobManager'}->update_job_output( $job_id,
						{ filename => "$job_id.fas", description => '36_Concatenated aligned sequences (FASTA format)' } );
				}
			}
			catch BIGSdb::CannotOpenFileException with {
				$logger->error("Can't create FASTA file from XMFA.");
			};
		}
	}
	return;
}

sub _identify_strains {
	my ( $self, $ids, $buffer_ref, $job_file, $loci, $values ) = @_;
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
	$$buffer_ref .= "<h3>Unique strains</h3>";
	my $file_buffer = "\n###\n\n";
	$file_buffer .= "Unique strains\n";
	$file_buffer .= "--------------\n\n";
	my $num_strains = keys %strains;
	$$buffer_ref .= "<p>Unique strains: $num_strains</p>\n";
	$file_buffer .= "Unique strains: $num_strains\n";
	$$buffer_ref .= "<div class=\"scrollable\"><table><tr>";
	$$buffer_ref .= "<th>Strain $_</th>" foreach ( 1 .. $num_strains );
	$$buffer_ref .= "</tr>\n<tr>";
	my $td        = 1;
	my $strain_id = 1;

	foreach my $strain ( sort { $strains{$b} <=> $strains{$a} } keys %strains ) {
		$$buffer_ref .= "<td class=\"td$td\" style=\"vertical-align:top\">";
		$$buffer_ref .= "$_<br />\n" foreach @{ $strain_isolates->{$strain} };
		$$buffer_ref .= "</td>\n";
		$td = $td == 1 ? 2 : 1;
		$file_buffer .= "\nStrain $strain_id:\n";
		$file_buffer .= "$_\n" foreach @{ $strain_isolates->{$strain} };
		$strain_id++;
	}
	$$buffer_ref .= "</tr></table></div>\n";
	open( my $job_fh, '>>', $job_file ) || $logger->error("Can't open $job_file for appending");
	print $job_fh $file_buffer;
	close $job_fh;
	return;
}

sub _get_isolate_name {
	my ( $self, $id ) = @_;
	my $isolate = $id;
	my $isolate_ref =
	  $self->{'datastore'}->run_simple_query( "SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?", $id );
	if ( ref $isolate_ref eq 'ARRAY' ) {
		$isolate .= ' (' . ( $isolate_ref->[0] ) . ')' if ref $isolate_ref eq 'ARRAY';
	}
	return $isolate;
}

sub _print_isolate_header {
	my ( $self, $by_reference, $ids, $file_buffer_ref, $html_buffer_ref ) = @_;
	$$html_buffer_ref .= "<div class=\"scrollable\"><table class=\"resultstable\"><tr><th>Locus</th>";
	$$file_buffer_ref .= "Locus";
	if ($by_reference) {
		$$html_buffer_ref .= "<th>Product</th><th>Sequence length</th><th>Genome position</th><th>Reference genome</th>";
		$$file_buffer_ref .= "\tProduct\tSequence length\tGenome position\tReference genome";
	}
	foreach my $id (@$ids) {
		my $isolate = $self->_get_isolate_name($id);
		$$html_buffer_ref .= "<th>$isolate</th>";
		$$file_buffer_ref .= "\t$isolate";
	}
	$$html_buffer_ref .= "</tr>";
	$$file_buffer_ref .= "\n";
	return;
}

sub _print_variable_loci {
	my ( $self, $by_reference, $ids, $buffer_ref, $job_filename, $loci, $values ) = @_;
	return if ref $loci ne 'HASH';
	$$buffer_ref .= "<h3>Loci with sequence differences between isolates:</h3>";
	my $file_buffer = "\n###\n\n";
	$file_buffer .= "Loci with sequence differences between isolates\n";
	$file_buffer .= "-----------------------------------------------\n\n";
	$$buffer_ref .= "<p>Variable loci: " . ( scalar keys %$loci ) . "</p>";
	$file_buffer .= "Variable loci: " . ( scalar keys %$loci ) . "\n\n";
	open( my $job_fh, '>>', $job_filename ) || $logger->error("Can't open $job_filename for appending");
	print $job_fh $file_buffer;
	$self->_print_locus_table( $by_reference, $ids, $buffer_ref, $job_fh, $loci, $values );
	close $job_fh;
	return;
}

sub _create_alignments {
	my ( $self, $job_id, $by_reference, $align_file, $align_stats_file, $ids, $loci, $params ) = @_;
	my $count;
	my $temp       = BIGSdb::Utils::get_random();
	my $progress   = 0;
	my $total      = 2 * ( scalar keys %$loci );                      #need to show progress from 50 - 100%
	my $xmfa_out   = "$self->{'config'}->{'tmp_dir'}/$job_id.xmfa";
	my $xmfa_start = 1;
	my $xmfa_end;
	foreach my $locus ( sort keys %$loci ) {
		$progress++;
		my $complete = 50 + int( 100 * $progress / $total );
		$self->{'jobManager'}->update_job_status( $job_id, { 'percent_complete' => $complete } );
		( my $escaped_locus = $locus ) =~ s/[\/\|]/_/g;
		$escaped_locus =~ tr/ /_/;
		my $fasta_file = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_$escaped_locus.fasta";
		my $muscle_out = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_$escaped_locus.muscle";

		#my $start         = $loci->{$locus}->{'start'};
		my $seq_count = 0;
		open( my $fasta_fh, '>', $fasta_file ) || $logger->error("Can't open $fasta_file for writing");
		if ( $by_reference && $params->{'include_ref'} ) {
			print $fasta_fh ">ref\n";
			print $fasta_fh "$loci->{$locus}->{'ref'}\n";
			$seq_count++;
		}
		foreach my $id (@$ids) {
			if ( $loci->{$locus}->{$id} ) {
				$seq_count++;
				print $fasta_fh ">$id\n";
				print $fasta_fh "$loci->{$locus}->{$id}\n";
			}
		}
		close $fasta_fh;
		if ( $params->{'align'} ) {
			$self->_run_muscle(
				{
					ids              => $ids,
					locus            => $locus,
					seq_count        => $seq_count,
					muscle_out       => $muscle_out,
					fasta_file       => $fasta_file,
					align_file       => $align_file,
					align_stats_file => $align_stats_file,
					xmfa_out         => $xmfa_out,
					xmfa_start_ref   => \$xmfa_start,
					xmfa_end_ref     => \$xmfa_end,
				},
				$params
			);
		}
		unlink $fasta_file;
	}
	return;
}

sub _run_infoalign {
	my ( $self, $values, $params ) = @_;
	if ( -e "$self->{'config'}->{'emboss_path'}/infoalign" ) {
		my $prefix  = BIGSdb::Utils::get_random();
		my $outfile = "$self->{'config'}->{'secure_tmp_dir'}/$prefix.infoalign";
		system(
"$self->{'config'}->{'emboss_path'}/infoalign -sequence $values->{'alignment'} -outfile $outfile -nousa -nosimcount -noweight -nodescription 2> /dev/null"
		);
		open( my $fh_stats, '>>', $values->{'align_stats_file'} )
		  or $logger->error("Can't open output file $values->{'align_stats_file'} for appending");
		print $fh_stats "$values->{'locus'}\n";
		print $fh_stats '-' x ( length $values->{'locus'} ) . "\n\n";
		close $fh_stats;
		BIGSdb::Utils::append( $outfile, $values->{'align_stats_file'}, { blank_after => 1 } ) if -e $outfile;
	}
	return;
}

sub _run_muscle {

	#need values for ($ids, $locus, $seq_count, $muscle_out, $fasta_file, $align_file, $xmfa_out, $xmfa_start_ref, $xmfa_end_ref);
	my ( $self, $values, $params ) = @_;
	return if $values->{'seq_count'} <= 1;
	system( $self->{'config'}->{'muscle_path'}, '-in', $values->{'fasta_file'}, '-out', $values->{'muscle_out'}, '-quiet', '-clwstrict' );
	if ( -e $values->{'muscle_out'} && $values->{'seq_count'} > 1 ) {
		my $align = Bio::AlignIO->new( -format => 'clustalw', -file => $values->{'muscle_out'} )->next_aln;
		my ( %id_has_seq, $seq_length );
		open( my $fh_xmfa, '>>', $values->{'xmfa_out'} ) or $logger->error("Can't open output file $values->{'xmfa_out'} for appending");
		foreach my $seq ( $align->each_seq ) {
			${ $values->{'xmfa_end_ref'} } = ${ $values->{'xmfa_start_ref'} } + $seq->length - 1;
			print $fh_xmfa '>' . $seq->id . ":${$values->{'xmfa_start_ref'}}-${$values->{'xmfa_end_ref'}} + $values->{'locus'}\n";
			my $sequence = BIGSdb::Utils::break_line( $seq->seq, 60 );
			print $fh_xmfa "$sequence\n";
			$id_has_seq{ $seq->id } = 1;
			$seq_length = $seq->length if !$seq_length;
		}
		my $missing_seq = BIGSdb::Utils::break_line( ( '-' x $seq_length ), 60 );
		foreach my $id ( @{ $values->{'ids'} } ) {
			next if $id_has_seq{$id};
			print $fh_xmfa ">$id:${$values->{'xmfa_start_ref'}}-${$values->{'xmfa_end_ref'}} + $values->{'locus'}\n$missing_seq\n";
		}
		print $fh_xmfa "=\n";
		close $fh_xmfa;
		${ $values->{'xmfa_start_ref'} } = ${ $values->{'xmfa_end_ref'} } + 1;
		open( my $align_fh, '>>', $values->{'align_file'} ) || $logger->error("Can't open $values->{'align_file'} for appending");
		print $align_fh "$values->{'locus'}\n";
		print $align_fh '-' x ( length $values->{'locus'} ) . "\n\n";
		close $align_fh;
		BIGSdb::Utils::append( $values->{'muscle_out'}, $values->{'align_file'}, { blank_after => 1 } );
		$values->{'alignment'} = $values->{'muscle_out'};
		$self->_run_infoalign( $values, $params );
		unlink $values->{'muscle_out'};
	}
	return;
}

sub _print_exact_matches {
	my ( $self, $by_reference, $ids, $buffer_ref, $job_filename, $exacts, $params, $values ) = @_;
	return if ref $exacts ne 'HASH';
	$$buffer_ref .= "<h3>Exactly matching loci</h3>\n";
	my $file_buffer = "\n###\n\n";
	$file_buffer .= "Exactly matching loci\n";
	$file_buffer .= "---------------------\n\n";
	$$buffer_ref .= "<p>These loci are identical in all isolates";
	$file_buffer .= "These loci are identical in all isolates";
	if ( $params->{'accession'} ) {
		$$buffer_ref .= ", including the reference genome";
		$file_buffer .= ", including the reference genome";
	}
	$$buffer_ref .= ".</p>";
	$file_buffer .= ".\n\n";
	$$buffer_ref .= "<p>Matches: " . ( scalar keys %$exacts ) . "</p>";
	$file_buffer .= "Matches: " . ( scalar keys %$exacts ) . "\n\n";
	open( my $job_fh, '>>', $job_filename ) || $logger->error("Can't open $job_filename for appending");
	print $job_fh $file_buffer;
	$self->_print_locus_table( $by_reference, $ids, $buffer_ref, $job_fh, $exacts, $values );
	close $job_fh;
	return;
}

sub _print_exact_except_ref {
	my ( $self, $ids, $buffer_ref, $job_filename, $exacts, $values ) = @_;
	return if ref $exacts ne 'HASH';
	open( my $job_fh, '>>', $job_filename ) || $logger->error("Can't open $job_filename for appending");
	$$buffer_ref .= "<h3>Loci exactly the same in all compared genomes except the reference</h3>";
	print $job_fh "Loci exactly the same in all compared genomes except the reference\n";
	print $job_fh "------------------------------------------------------------------\n\n";
	$$buffer_ref .= "<p>Matches: " . ( scalar keys %$exacts ) . "</p>";
	print $job_fh "Matches: " . ( scalar keys %$exacts ) . "\n\n";
	$self->_print_locus_table( 1, $ids, $buffer_ref, $job_fh, $exacts, $values );
	close $job_fh;
	return;
}

sub _print_missing_in_all {
	my ( $self, $by_reference, $ids, $buffer_ref, $job_filename, $missing, $values ) = @_;
	return if ref $missing ne 'HASH';
	open( my $job_fh, '>>', $job_filename ) || $logger->error("Can't open $job_filename for appending");
	$$buffer_ref .= "<h3>Loci missing in all isolates</h3>";
	print $job_fh "\n###\n\n";
	print $job_fh "Loci missing in all isolates\n";
	print $job_fh "----------------------------\n\n";
	$$buffer_ref .= "<p>Missing loci: " . ( scalar keys %$missing ) . "</p>";
	print $job_fh "Missing loci: " . ( scalar keys %$missing ) . "\n\n";
	$self->_print_locus_table( $by_reference, $ids, $buffer_ref, $job_fh, $missing, $values );
	close $job_fh;
	return;
}

sub _print_truncated_loci {
	my ( $self, $by_reference, $ids, $buffer_ref, $job_filename, $truncated, $values ) = @_;
	return if ref $truncated ne 'HASH';
	$$buffer_ref .= "<h3>Loci that are truncated in some isolates</h3>";
	my $file_buffer = "\n###\n\n";
	$file_buffer .= "Loci that are truncated in some isolates\n";
	$file_buffer .= "----------------------------------------\n\n";
	$$buffer_ref .= "<p>Truncated: " . ( scalar keys %$truncated ) . "</p>";
	$file_buffer .= "Truncated: " . ( scalar keys %$truncated ) . "\n\n";
	$$buffer_ref .= "<p>These loci are incomplete and located at the ends of contigs in at least one isolate. "
	  . "They have been excluded from the distance matrix calculation.</p>";
	$file_buffer .= "These loci are incomplete and located at the ends of contigs in at least one isolate.\n\n";
	open( my $job_fh, '>>', $job_filename ) || $logger->error("Can't open $job_filename for appending");
	print $job_fh $file_buffer;
	$self->_print_locus_table( $by_reference, $ids, $buffer_ref, $job_fh, $truncated, $values );
	close $job_fh;
	return;
}

sub _print_locus_table {
	my ( $self, $by_reference, $ids, $buffer_ref, $fh, $loci, $values ) = @_;
	my $file_buffer;
	$self->_print_isolate_header( $by_reference, $ids, \$file_buffer, $buffer_ref );
	print $fh $file_buffer;
	my $td = 1;
	foreach my $locus ( sort keys %$loci ) {
		my $cleaned_locus = $self->clean_locus($locus);
		$$buffer_ref .= "<tr class=\"td$td\"><td>$cleaned_locus</td>";
		print $fh $locus;
		if ($by_reference) {
			my $length = $loci->{$locus}->{'length'};
			my $start  = $loci->{$locus}->{'start'};
			$$buffer_ref .= "<td>$loci->{$locus}->{'desc'}</td><td>$length</td><td>$start</td><td>1</td>";
			print $fh "\t$loci->{$locus}->{'desc'}\t$length\t$start\t1";
		}
		foreach my $id (@$ids) {
			my $style = $self->{'style'}->{$locus}->{ $values->{$id}->{$locus} };
			$$buffer_ref .= "<td style=\"$style\">$values->{$id}->{$locus}</td>";
			print $fh "\t$values->{$id}->{$locus}";
		}
		$$buffer_ref .= "</tr>\n";
		print $fh "\n";
		$td = $td == 1 ? 2 : 1;
	}
	$$buffer_ref .= "</table>\n";
	$$buffer_ref .= "</div>\n";
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
	my ( $self, $word_size, $fasta_file, $in_file, $out_file, $program ) = @_;
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
	return;
}

sub _parse_blast_by_locus {

	#return best match
	my ( $self, $locus, $blast_file, $params ) = @_;
	my $identity  = BIGSdb::Utils::is_int( $params->{'identity'} )  ? $params->{'identity'}  : 70;
	my $alignment = BIGSdb::Utils::is_int( $params->{'alignment'} ) ? $params->{'alignment'} : 50;
	my $full_path = "$blast_file";
	my $match;
	my $quality = 0;    #simple metric of alignment length x percentage identity
	my $ref_seq_sql = $self->{'db'}->prepare("SELECT length(reference_sequence) FROM loci WHERE id=?");
	my %lengths;
	my @blast;
	open( my $blast_fh, '<', $full_path ) || ( $logger->error("Can't open BLAST output file $full_path. $!"), return \$; );
	push @blast, $_ foreach <$blast_fh>;    #slurp file to prevent file handle remaining open during database queries.
	close $blast_fh;

	foreach my $line (@blast) {
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
			if ( ( $record[8] > $record[9] && $record[7] > $record[6] ) || ( $record[8] < $record[9] && $record[7] < $record[6] ) ) {
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
	my ( $self, $seq_ref, $blast_file, $params ) = @_;
	my $identity  = BIGSdb::Utils::is_int( $params->{'identity'} )  ? $params->{'identity'}  : 70;
	my $alignment = BIGSdb::Utils::is_int( $params->{'alignment'} ) ? $params->{'alignment'} : 50;
	my $match;
	my $quality    = 0;                  #simple metric of alignment length x percentage identity
	my $ref_length = length $$seq_ref;
	my $required_alignment = $params->{'tblastx'} ? int( $ref_length / 3 ) : $ref_length;
	my @blast;
	open( my $blast_fh, '<', $blast_file ) || ( $logger->error("Can't open BLAST output file $blast_file. $!"), return \$; );
	push @blast, $_ foreach <$blast_fh>;    #slurp file to prevent file handle remaining open during database queries.
	close $blast_fh;

	foreach my $line (@blast) {
		next if !$line || $line =~ /^#/;
		my @record = split /\s+/, $line;
		my $this_quality = $record[3] * $record[2];
		if ( $this_quality > $quality && $record[3] >= $alignment * 0.01 * $required_alignment && $record[2] >= $identity ) {
			$quality              = $this_quality;
			$match->{'seqbin_id'} = $record[1];
			$match->{'identity'}  = $record[2];
			$match->{'alignment'} = $record[3];
			$match->{'start'}     = $record[8];
			$match->{'end'}       = $record[9];
			if ( ( $record[8] > $record[9] && $record[7] > $record[6] ) || ( $record[8] < $record[9] && $record[7] < $record[6] ) ) {
				$match->{'reverse'} = 1;
			} else {
				$match->{'reverse'} = 0;
			}
			if ( $required_alignment > $match->{'alignment'} ) {
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
	open( my $fasta_fh, '>', $temp_fastafile ) || $logger->error("Can't open $temp_fastafile for writing");
	print $fasta_fh ">ref\n$$seq_ref\n";
	close $fasta_fh;
	return $temp_fastafile;
}

sub _create_isolate_FASTA {
	my ( $self, $isolate_id, $prefix, $params ) = @_;
	my $qry =
"SELECT DISTINCT id,sequence FROM sequence_bin LEFT JOIN experiment_sequences ON sequence_bin.id=seqbin_id LEFT JOIN project_members ON sequence_bin.isolate_id = project_members.isolate_id WHERE sequence_bin.isolate_id=?";
	my @criteria = ($isolate_id);
	my $method   = $params->{'seq_method_list'};
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
	my $experiment = $params->{'experiment_list'};
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
	open( my $infile_fh, '>', $temp_infile ) || $logger->error("Can't open $temp_infile for writing");
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
