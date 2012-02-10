#LocusExplorer.pm - Plugin for BIGSdb
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
package BIGSdb::Plugins::LocusExplorer;
use strict;
use warnings;
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use List::MoreUtils qw(none);
use Apache2::Connection ();
use Bio::SeqIO;

sub get_attributes {
	my %att = (
		name             => 'Locus Explorer',
		author           => 'Keith Jolley',
		affiliation      => 'University of Oxford, UK',
		email            => 'keith.jolley@zoo.ox.ac.uk',
		description      => 'Tool for analysing allele sequences stored for particular locus',
		menu_description => 'tool for analysing allele sequences stored for particular locus.',
		category         => 'Analysis',
		menutext         => 'Locus Explorer',
		module           => 'LocusExplorer',
		version          => '1.1.0',
		dbtype           => 'sequences',
		seqdb_type       => 'sequences',
		section          => 'analysis',
		requires         => 'muscle,offline_jobs',
		order            => 15
	);
	return \%att;
}

sub get_plugin_javascript {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $buffer = << "END";
\$(function () {
 \$("#locus").change(function(){
 	var locus_name = \$("#locus").val();
 	var url = '$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=plugin&name=LocusExplorer&locus=' + locus_name;
 	location.href=url;
  });
});
function listbox_selectall(listID, isSelect) {
	var listbox = document.getElementById(listID);
	for(var count=0; count < listbox.options.length; count++) {
		listbox.options[count].selected = isSelect;
	}
}
END
	return $buffer;
}

sub get_html_header {
	my ($self) = @_;
	my $buffer = << "HEADER";
<!DOCTYPE html
	PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
	 "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" lang="en-US" xml:lang="en-US">
<head>
<title>Polymorphic site analysis</title>
<style type="text/css">
body {
	font:0.85em/110% Arial,Helvetica,sans-serif;
	background:#fff;
	color:#000;
	margin: 0 1em;
}

h1 {
	font: italic 600 1.5em/110% Arial,Helvetica,sans-serif;
	text-align: left;
	line-height: 110%;
	color: #606080;
	border-top: solid #a0a0d0 3px;
	border-bottom: dotted #8080b0 1px;
	background: #f0f0f0;
}

h2 {
	font: 600 1.2em Arial,Helvetica,sans-serif; 
	color: #606060;
	border-bottom: dotted #8080b0 1px;
}

table {
	border: 1px solid #ddd;
	background: #ddd; 
	font-size: 0.9em; 
	border-spacing:1px;
	text-align: center;
}

th {background:#404090; color:#fff}
.td1 {background:#efefff}
.td2 {background:#efefef}
.A,.G,.T,.C {font-weight:600}
.A {color:green}
.G {color:black}
.T {color:red}
.C {color:blue}

div.results {
	background:#d5e0d5;	
	padding: 0.5em;
	border:1px solid #d0d0d0;
	-moz-box-shadow: 3px 3px 5px #dfdfdf;
	-webkit-box-shadow: 3px 3px 5px #dfdfdf;
	box-shadow: 3px 3px 5px #dfdfdf;
	-webkit-border-radius: 5px;
	-moz-border-radius: 5px;
	border-radius: 5px;
}

div.seqmap {
	overflow-x:auto;
	min-width:80%;
	font-family: Courier New, monospace;
}

.pc10,.pc20,.pc30,.pc40,.pc50,.pc60,.pc70,.pc80,.pc90,.pc100 {
	font-weight:bold; 
	color: white
}

.pc10 {background:#ff99ff; color:navy}
.pc20 {background:#cc66ff}
.pc30 {background:#9900cc}
.pc40 {background:#0066cc}
.pc50 {background:#3399ff}
.pc60 {background:#33ffff; color:navy}
.pc70 {background:#66cc00}
.pc80 {background:#339900}
.pc90 {background:#006600}
.pc100 {background:#000000}

</style>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
</head>
<body>
HEADER
	return $buffer;
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $display_loci, $cleaned ) = $self->{'datastore'}->get_locus_list;
	if ( !@$display_loci ) {
		print "<h1>Locus Explorer</h1>\n";
		print "<div class=\"box\" id=\"statusbad\"><p>No loci have been defined for this database.</p></div>\n";
		return;
	}
	if ( !$q->param('locus') ) {
		$q->param( 'locus', $display_loci->[0] );
	}
	my $locus = $q->param('locus');
	if ( $locus =~ /^cn_(.+)/ ) {
		$locus = $1;
		$q->param( 'locus', $locus );
	}
	if ( $q->param('snp') ) {
		$self->_snp           if $q->param('function') eq 'snp';
		$self->_site_explorer if $q->param('function') eq 'siteExplorer';
		return;
	} else {
		if ( $q->param('codon') ) {
			$self->_codon if $q->param('codon');
			return;
		} elsif ( $q->param('translate') ) {
			$self->_translate if $q->param('translate');
			return;
		}
	}
	$self->_print_interface( $locus, $display_loci, $cleaned );
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	my $locus = $params->{'locus'};
	if ( $locus =~ /^cn_(.+)/ ) {
		$locus = $1;
	}
	$self->{'jobManager'}->update_job_status( $job_id, { 'percent_complete' => -1 } );    #indeterminate length of time
	if ( $params->{'snp'} ) {
		my @allele_ids = split /\|\|/, $params->{'allele_ids'};
		my ( $seqs, undef ) = $self->_get_seqs( $params->{'locus'}, \@allele_ids );
		if ( !@$seqs ) {
			$self->{'jobManager'}->update_job_status( $job_id, { 'message_html' => "<p>No sequences retrieved for analysis.</p>" } );
			return;
		}
		my $temp      = BIGSdb::Utils::get_random();
		my $html_file = "$self->{'config'}->{tmp_dir}/$temp.html";
		my ( $buffer, $freqs ) = $self->get_snp_schematic( $locus, $seqs, undef, $params->{'alignwidth'} );
		open( my $html_fh, '>', $html_file );
		print $html_fh $self->get_html_header($locus);
		print $html_fh "<h1>Polymorphic site analysis</h1>\n<div class=\"box\" id=\"resultsheader\">\n";
		print $html_fh $buffer;
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		( $buffer, undef ) = $self->get_freq_table( $freqs, $locus_info );
		print $html_fh $buffer;
		print $html_fh "</div>\n</body>\n</html>\n";
		$self->{'jobManager'}
		  ->update_job_output( $job_id, { 'filename' => "$temp.html", 'description' => 'Locus schematic (HTML format)' } );
	}
}

sub _print_interface {
	my ( $self, $locus, $display_loci, $cleaned ) = @_;
	my $q = $self->{'cgi'};
	my $coding_loci =
	  $self->{'datastore'}->run_list_query( "SELECT id FROM loci WHERE data_type=? AND coding_sequence ORDER BY id", 'DNA' );
	print "<h1>Locus Explorer</h1>\n<div class=\"box\" id=\"queryform\">\n";
	print $q->start_form;
	$q->param( 'function', 'snp' );
	print $q->hidden($_) foreach qw (db page function name);
	print "<p>Please select locus for analysis:</p>\n";
	print "<p><b>Locus: </b>";
	print $q->popup_menu( -name => 'locus', -id => 'locus', -values => $display_loci, -labels => $cleaned );
	print " <span class=\"comment\">Page will reload when changed</span></p>";

	if ( $q->param('locus') ) {
		my $locus = $q->param('locus');
		my $desc_exists = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM locus_descriptions WHERE locus=?", $locus )->[0];
		if ($desc_exists) {
			print
"<ul><li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=locusInfo&amp;locus=$locus\">Further information</a> is available for this locus.</li></ul>\n";
		}
	}
	print "<fieldset>\n<legend>Select sequences</legend>\n";
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $order      = $locus_info->{'allele_id_format'} eq 'integer' ? 'CAST (allele_id AS integer)' : 'allele_id';
	my $allele_ids = $self->{'datastore'}->run_list_query( "SELECT allele_id FROM sequences WHERE locus=? ORDER BY $order", $locus );
	$" = ' ';
	print $q->scrolling_list(
		-name     => 'allele_ids',
		-id       => 'allele_ids',
		-values   => $allele_ids,
		-style    => 'width:100%',
		-size     => 6,
		-multiple => 'true'
	);
	print
"<br /><input type=\"button\" onclick='listbox_selectall(\"allele_ids\",true)' value=\"All\" style=\"margin-top:1em\" class=\"smallbutton\" />\n";
	print
"<input type=\"button\" onclick='listbox_selectall(\"allele_ids\",false)' value=\"None\" style=\"margin-top:1em\" class=\"smallbutton\" />\n";
	print "</fieldset>\n";
	print "<fieldset>\n<legend>Analysis functions</legend>\n";
	print "<table>";

	if ( !$locus_info->{'length_varies'} || $self->{'config'}->{'muscle_path'} ) {
		print "<tr><td style=\"text-align:right\">\n";
		print $q->submit( -name => 'snp', -label => 'Polymorphic sites', -class => 'submit' );
		print "</td><td>Display polymorphic site frequencies and sequence schematic</td></tr>\n";
	}
	if ( $self->{'config'}->{'emboss_path'} && $locus_info->{'data_type'} eq 'DNA' ) {
		print "<tr><td style=\"text-align:right\">\n";
		print $q->submit( -name => 'codon', -label => 'Codon', -class => 'submit' );
		print "</td><td>\nCalculate G+C content";
		print " and codon usage" if $locus_info->{'coding_sequence'};
		print "</td></tr>\n";
		if ( $locus_info->{'coding_sequence'} && ( !$locus_info->{'length_varies'} || $self->{'config'}->{'muscle_path'} ) ) {
			print "<tr><td style=\"text-align:right\">";
			print $q->submit( -name => 'translate', -label => 'Translate', -class => 'submit' );
			print "</td><td>Translate DNA to peptide sequences";
			print " (limited to 50 sequences)" if $locus_info->{'length_varies'} && @$allele_ids > 50;
			print "</td></tr>\n";
		}
	}
	print "</table>\n</fieldset>\n";
	print $q->endform;
	print "</div>\n";
}

sub _get_seqs {
	my ( $self, $locus, $allele_ids, $options ) = @_;

	#options: count_only - don't align, just count how many sequences would be included.
	$options = {} if ref $options ne 'HASH';
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $sql        = $self->{'db'}->prepare("SELECT allele_id,sequence FROM sequences WHERE locus=?");
	eval { $sql->execute($locus) };
	$logger->error($@) if $@;
	my @seqs;
	my $temp     = BIGSdb::Utils::get_random();
	my $tempfile = "$self->{'config'}->{'secure_tmp_dir'}/$temp.txt";
	open( my $fh, '>', $tempfile ) or $logger->error("could not open temp file $tempfile");
	my $i = 0;

	while ( my ( $allele_id, $seq ) = $sql->fetchrow_array ) {
		next if none { $_ eq $allele_id } @$allele_ids;
		push @seqs, $seq;
		print $fh ">$allele_id\n$seq\n";
		$i++;
	}
	close $fh;
	return $i if $options->{'count_only'};
	my $seq_file;
	my $muscle_file = "$self->{'config'}->{secure_tmp_dir}/$temp.muscle";
	if ( $self->{'config'}->{'muscle_path'} && $locus_info->{'length_varies'} && @seqs > 1 ) {
		print "<p>Please wait - aligning (do not refresh) ...</p>\n" if $options->{'print_status'};
		system( $self->{'config'}->{'muscle_path'}, '-in', $tempfile, '-fastaout', $muscle_file, '-quiet' );
		my $seqio_object = Bio::SeqIO->new( -file => $muscle_file, -format => 'Fasta' );
		undef @seqs;
		while ( my $seq_object = $seqio_object->next_seq ) {
			push @seqs, $seq_object->seq;
		}
		$seq_file = "$temp.muscle";
	} else {
		$seq_file = "$temp.txt";
	}
	return \@seqs, $seq_file;
}

sub _snp {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<h1>Polymorphic site analysis</h1>\n";
	my $locus = $q->param('locus');
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid locus.</p></div>\n";
		return;
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $total_seq_count = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM sequences WHERE locus=?", $locus )->[0];
	if ( !$total_seq_count ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No sequences defined for this locus.</p></div>\n";
		return;
	}
	my @allele_ids = $q->param('allele_ids');
	if ( !@allele_ids ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No sequences selected.</p></div>\n";
		return;
	}
	my $seq_count = $self->_get_seqs( $locus, \@allele_ids, { 'count_only' => 1 } );
	if ( $seq_count <= 50 || !$locus_info->{'length_varies'} ) {
		print "<div class=\"box\" id=\"resultsheader\">\n";
		my $cleaned = $self->clean_locus($locus);
		print "<h2>$cleaned</h2>\n";
		my ( $seqs, $seq_file ) = $self->_get_seqs( $locus, \@allele_ids, {'print_status' => 1} );
		my ( $buffer, $freqs ) = $self->get_snp_schematic( $locus, $seqs, $seq_file, $self->{'prefs'}->{'alignwidth'} );
		print $buffer;
		( $buffer, undef ) = $self->get_freq_table( $freqs, $locus_info );
		print $buffer if $buffer;
		print "</div>\n";
	} else {
		my $params = $q->Vars;
		$params->{'alignwidth'} = $self->{'prefs'}->{'alignwidth'};
		my $job_id = $self->{'jobManager'}->add_job(
			{
				'dbase_config' => $self->{'instance'},
				'ip_address'   => $q->remote_host,
				'module'       => 'LocusExplorer',
				'parameters'   => $params
			}
		);
		print <<"HTML";
<div class="box" id="resultstable">
<p>This analysis has been submitted to the job queue.</p>
<p>Please be aware that this job may take a long time depending on the number of sequences to align
and how busy the server is.  Alignment of hundreds of sequences can take many hours!</p>
<p>Since alignment is offloaded to a third-party application, the progress report will not be accurate.</p>
<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=job&amp;id=$job_id">
Follow the progress of this job and view the output.</a></p> 	
<p>Please note that the % complete value will only update after the alignment of each locus.</p>
</div>	
HTML
		return;
	}
}

sub get_snp_schematic {
	my ( $self, $locus, $seqs, $seq_file, $align_width ) = @_;
	my $seq_count = scalar @$seqs;
	my $pagebuffer;
	my @linebuffer;
	my $ps         = 0;
	my $std_length = length( $seqs->[0] );
	my $freqs;
	for ( my $i = 0 ; $i < $std_length ; $i++ ) {

		if ( $i % $align_width == 0 ) {
			my $length;
			if ( ( $i + $align_width ) > $std_length ) {
				$length = $std_length;
			} else {
				$length = $i + $align_width;
			}
			foreach my $line (@linebuffer) {
				( my $test = $line ) =~ tr/\&nbsp;//d;
				next if $test eq '';
				$pagebuffer .= "&nbsp;" x 7 . "$line<br />\n";
			}
			undef @linebuffer;
			$pagebuffer .= $self->_get_seq_ruler( $i + 1, $length, $align_width );
			$pagebuffer .= "<br />\n";
		}
		my %nuc;
		foreach (@$seqs) {
			my $base = substr( $_, $i, 1 );
			$nuc{ uc($base) }++;
		}
		$freqs->{ $i + 1 } = \%nuc if keys %nuc > 1;
		$ps++ if keys %nuc > 1;
		my $linenumber = 0;
		foreach my $base ( sort { $nuc{$b} <=> $nuc{$a} } ( keys(%nuc) ) ) {
			my $prop = $nuc{$base} / $seq_count;
			if ($seq_file) {
				$linebuffer[$linenumber] .=
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;name=LocusExplorer&amp;snp=1&amp;function=siteExplorer&amp;file=$seq_file&amp;locus=$locus&amp;pos="
				  . ( $i + 1 )
				  . "\" class=\""
				  . $self->_get_prop_class($prop)
				  . "\">$base</a>";
			} else {
				$linebuffer[$linenumber] .= "<span class=\"" . $self->_get_prop_class($prop) . "\">$base</span>";
			}
			$linenumber++;
		}
		for ( my $j = $linenumber ; $j < 21 ; $j++ ) {
			$linebuffer[$j] .= "&nbsp;";
		}
	}
	foreach (@linebuffer) {
		( my $test = $_ ) =~ tr/\&nbsp;//d;
		next if $test eq '';
		$pagebuffer .= "&nbsp;" x 7 . "$_<br />\n";
	}
	my $pluralps = $ps != 1        ? 's' : '';
	my $plural   = $seq_count != 1 ? 's' : '';
	my $buffer   = << "HTML";
<div class="results">
<p>The colour codes represent the percentage of alleles that have
a particular nucleotide at each position. Click anywhere within
the sequence to drill down to allele and profile information. 
The width of the display can be altered by going to the options 
page - change this if the display goes off the page.</p>
<p>$seq_count allele$plural included in analysis.  $ps polymorphic site$pluralps found.</p>
<p><b>Key: </b><span class="pc10">0 - 10%</span> | <span class="pc20">&gt;10 - 20%</span> | 
<span class="pc30">&gt;20 - 30%</span> | <span class="pc40">&gt;30 - 40%</span> | 
<span class="pc50">&gt;40 - 50%</span> | <span class="pc60">&gt;50 - 60%</span> | 
<span class="pc70">&gt;60 - 70%</span> | <span class="pc80">&gt;70 - 80%</span> | 
<span class="pc90">&gt;80 - 90%</span> | <span class="pc100">&gt;90 - 100%</span></p>
<div class=\"seqmap\">
$pagebuffer
</div>
</div>
HTML
	return ( $buffer, $freqs );
}

sub _get_seq_ruler {
	my ( $self, $start, $length, $width ) = @_;
	my $ruler      = '';
	my $num_labels = ( $width / 10 ) + 1;
	my @label;    # Position label every 10 bases
	push @label, $start;
	for ( my $i = 1 ; $i < $num_labels ; $i++ ) {
		my $value = $start - 1 + ( $i * 10 );
		push @label, $value if $value <= $length;
	}
	my $num_spaces = 8 - length( $label[0] );
	$ruler .= ( "&nbsp;" x $num_spaces ) . $label[0]
	  if length($ruler) < $length;

	# First label on 1, rest on tens
	# Each label must occupy 9 characters
	for ( my $i = 1 ; $i < $num_labels ; $i++ ) {
		if ( $label[$i] ) {
			$num_spaces = 9 - length( $label[$i] );
			$label[$i] = ( "&nbsp;" x $num_spaces ) . $label[$i];
			$ruler .= ( $label[$i] . " " );
		}
	}
	$ruler .= "\n";
	return $ruler;
}

sub _get_prop_class {

	#Return CSS class name for given proportion
	my ( $self, $prop ) = @_;
	if ( $prop <= 0.1 ) { return 'pc10' }
	if ( $prop <= 0.2 ) { return 'pc20' }
	if ( $prop <= 0.3 ) { return 'pc30' }
	if ( $prop <= 0.4 ) { return 'pc40' }
	if ( $prop <= 0.5 ) { return 'pc50' }
	if ( $prop <= 0.6 ) { return 'pc60' }
	if ( $prop <= 0.7 ) { return 'pc70' }
	if ( $prop <= 0.8 ) { return 'pc80' }
	if ( $prop <= 0.9 ) { return 'pc90' }
	return 'pc100';
}

sub _site_explorer {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<h1>Site Explorer</h1>\n";
	my $locus = $q->param('locus');
	my $pos   = $q->param('pos');
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid locus.</p></div>\n";
		return;
	}
	my $temp_file = $q->param('file');
	if ( !$temp_file || !-e "$self->{'config'}->{'secure_tmp_dir'}/$temp_file" ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No sequence file passed.</p></div>\n";
		return;
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	print "<div class=\"box\" id=\"resultsheader\">\n";
	my $cleaned = $self->clean_locus($locus);
	print "<h2>$cleaned position $pos</h2>\n";
	my %seq;
	my $seqio_object = Bio::SeqIO->new( -file => "$self->{'config'}->{'secure_tmp_dir'}/$temp_file", -format => 'fasta' );
	while ( my $seq_object = $seqio_object->next_seq ) {
		$seq{ $seq_object->seq } = $seq_object->id;
	}
	my $seq_count = keys %seq;
	print "<p>$seq_count alleles included in analysis.</p>\n";
	my %site;
	my %allele;
	foreach my $allele ( keys %seq ) {
		$site{ uc( substr( $allele, $pos - 1, 1 ) ) }++;
		push @{ $allele{ uc( substr( $allele, $pos - 1, 1 ) ) } }, $seq{$allele};
	}
	my $td = 1;
	my $sql =
	  $self->{'db'}->prepare(
"SELECT id,description FROM schemes LEFT JOIN scheme_members ON scheme_id=schemes.id WHERE locus=? AND scheme_id IN (SELECT scheme_id FROM scheme_fields WHERE primary_key)"
	  );
	eval { $sql->execute($locus) };
	$logger->error($@) if $@;
	my ( @schemes, %desc );
	while ( my ( $scheme_id, $desc ) = $sql->fetchrow_array ) {
		push @schemes, $scheme_id;
		$desc{$scheme_id} = $desc;
	}
	print "<table class=\"resultstable\"><tr><th>Base</th><th>Number of alleles</th><th>Percentage of alleles</th>";
	print "<th>$desc{$_} profiles</th>" foreach (@schemes);
	print "</tr>\n";
	foreach my $base ( sort { $site{$b} <=> $site{$a} } ( keys(%site) ) ) {
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
		my @allelelist    = @{ $allele{$base} };
		my @sortedalleles = sort { $a <=> $b } @allelelist;
		my $pc            = BIGSdb::Utils::decimal_place( ( ( $site{$base} / $seq_count ) * 100 ), 2 );
		print "<tr class=\"td$td\"><td>$base</td><td>$site{$base}";
		if ( $site{$base} < 6 ) {
			$" = ", $cleaned-";
			print "<br />($cleaned-@sortedalleles)\n";
		}
		print "</td><td>$pc</td>";
		$" = "' OR $locus='";
		foreach (@schemes) {
			my $qry      = "SELECT COUNT(*) FROM scheme_$_ WHERE $locus='@allelelist'";
			my $numSTs   = $self->{'datastore'}->run_simple_query($qry)->[0];
			my $totalSTs = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM scheme_$_")->[0];
			print "<td>$numSTs / $totalSTs";
			my $pcST;
			if ( $totalSTs == 0 ) {
				$pcST = '-';
			} else {
				$pcST = BIGSdb::Utils::decimal_place( ( ( $numSTs / $totalSTs ) * 100 ), 2 );
			}
			print "<br />($pcST\%)</td>";
		}
		print "</tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	print "</table>\n";
	print "</div>\n";
}

sub _codon {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<h1>Codon Usage</h1>\n";
	if ( !$self->{'config'}->{'emboss_path'} ) {
		print "<div class=\"box\" id=\"statusbad\"><p>EMBOSS is not installed - function unavailable.</p></div>\n";
		return;
	}
	my $locus = $q->param('locus');
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid locus.</p></div>\n";
		return;
	}
	my $total_seq_count = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM sequences WHERE locus=?", $locus )->[0];
	if ( !$total_seq_count ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No sequences defined for this locus.</p></div>\n";
		return;
	}
	my @allele_ids = $q->param('allele_ids');
	if ( !@allele_ids ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No sequences selected.</p></div>\n";
		return;
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $orf = $locus_info->{'orf'} || 1;
	print "<div class=\"box\" id=\"resultsheader\">\n";
	my $cleaned = $self->clean_locus($locus);
	print "<h2>$cleaned</h2>\n";
	print "<p>ORF used: $orf</p>\n";
	my $sql = $self->{'db'}->prepare("SELECT allele_id,sequence FROM sequences WHERE locus=?");
	eval { $sql->execute($locus) };
	$logger->error($@) if $@;
	my @seqs;

	while ( my ( $allele_id, $seq ) = $sql->fetchrow_array ) {
		next if none { $_ eq $allele_id } @allele_ids;
		push @seqs, $seq;
	}
	my $seq_count = scalar @seqs;
	my $plural = $seq_count != 1 ? 's' : '';
	print "<p>$seq_count allele$plural included in analysis.</p>\n";
	my $temp     = BIGSdb::Utils::get_random();
	my $tempfile = "$self->{'config'}->{secure_tmp_dir}/$temp.txt";
	my $outfile  = "$self->{'config'}->{secure_tmp_dir}/$temp.cusp";
	open( my $fh, '>', "$tempfile" ) or $logger->error("could not open temp file $tempfile");
	my $i = 1;

	foreach (@seqs) {
		my $seq = BIGSdb::Utils::chop_seq( $_, $orf );
		print $fh ">$i\n$seq\n";
		$i++;
	}
	close $fh;
	system("$self->{'config'}->{'emboss_path'}/cusp -sequence $tempfile -outfile $outfile 2> /dev/null");
	unlink $tempfile;
	my @codons;
	print "<h3>GC content</h3>";
	print "<p>\n";
	open $fh, '<', $outfile;

	while ( my $line = <$fh> ) {
		chomp $line;
		push @codons, $line if $line && $line !~ /^#/;
		if ( $line =~ /%/ ) {
			$line =~ s/#//;
			$line =~ s/ GC/: GC/;
			print "$line<br />\n";
		}
	}
	print "</p>";
	close $fh;
	if ( !$locus_info->{'coding_sequence'} ) {
		print "</div>\n";
		return;
	}
	print << "HTML";

<h3>Codons</h3>
<p>Fraction: Proportion of usage of a given codon among its 
redundant set (i.e. the set of codons which code for this 
codon's amino acid).<br />
Frequency: Usage of given codon per 1000 codons.</p>
<table class="tablesorter" id=\"sortTable\"><thead><tr><th>Codon</th>
<th>Amino acid</th><th>Fraction</th><th>Frequency</th><th>Number</th></tr></thead>
<tbody>
HTML
	$" = '</td><td>';
	my $td = 1;
	foreach (@codons) {
		my @values = split /\s+/, $_;
		print "<tr class=\"td$td\"><td>@values</td></tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	print "</tbody>\n</table>\n";
	unlink $outfile;
	print "</div>\n";
}

sub _translate {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<h1>Translate - aligned protein sequences</h1>\n";
	if ( !$self->{'config'}->{'emboss_path'} ) {
		print "<div class=\"box\" id=\"statusbad\"><p>EMBOSS is not installed - function unavailable.</p></div>\n";
		return;
	}
	my $locus = $q->param('locus');
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid locus.</p></div>\n";
		return;
	}
	my $total_seq_count = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM sequences WHERE locus=?", $locus )->[0];
	if ( !$total_seq_count ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No sequences defined for this locus.</p></div>\n";
		return;
	}
	my @allele_ids = $q->param('allele_ids');
	if ( !@allele_ids ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No sequences selected.</p></div>\n";
		return;
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( $locus_info->{'length_varies'} && @allele_ids > 50 ) {
		print
"<div class=\"box\" id=\"statusbad\"><p>This locus is variable length and will therefore require real-time alignment.  Consequently this function is limited to 50 sequences or fewer - you have selected "
		  . @allele_ids
		  . ".</p></div>\n";
		return;
	}
	my $orf = $locus_info->{'orf'} || 1;
	print "<div class=\"box\" id=\"resultsheader\">\n";
	my $cleaned = $self->clean_locus($locus);
	print "<h2>$cleaned</h2>";
	print "<p>ORF used: $orf</p>\n";
	my $sql = $self->{'db'}->prepare("SELECT allele_id,sequence FROM sequences WHERE locus=?");
	eval { $sql->execute($locus) };
	$logger->error($@) if $@;
	my %seqs_hash;
	while ( my ( $allele_id, $seq ) = $sql->fetchrow_array ) {
		next if none { $_ eq $allele_id } @allele_ids;
		$seqs_hash{$allele_id} = $seq;
	}
	my $seq_count = keys %seqs_hash;
	my $plural = $seq_count != 1 ? 's' : '';
	print "<p>The width of the alignment can be varied by going to the options page.</p>\n";
	print "<p>$seq_count allele$plural included in analysis.</p>\n";
	my $temp      = BIGSdb::Utils::get_random();
	my $tempfile  = "$self->{'config'}->{'secure_tmp_dir'}/$temp.txt";
	my $outfile   = "$self->{'config'}->{'secure_tmp_dir'}/$temp.pep";
	my $finalfile = "$self->{'config'}->{'secure_tmp_dir'}/$temp.aln";
	open( my $fh, '>', "$tempfile" ) or $logger->error("could not open temp file $tempfile");

	if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
		foreach ( sort { $a <=> $b } keys %seqs_hash ) {
			print $fh ">$_\n$seqs_hash{$_}\n";
		}
	} else {
		foreach ( sort { $a cmp $b } keys %seqs_hash ) {
			print $fh ">$_\n$seqs_hash{$_}\n";
		}
	}
	close $fh;
	system("$self->{'config'}->{'emboss_path'}/transeq -sequence $tempfile -outseq $outfile -frame $orf -trim -clean 2> /dev/null");
	if ( $self->{'config'}->{'muscle_path'} && $locus_info->{'length_varies'} ) {
		my $muscle_file = "$self->{'config'}->{secure_tmp_dir}/$temp.muscle";
		system( $self->{'config'}->{'muscle_path'}, '-in', $outfile, '-out', $muscle_file, '-quiet' );
		$outfile = $muscle_file;
	}
	system(
"$self->{'config'}->{'emboss_path'}/showalign -nosimilarcase -width $self->{'prefs'}->{'alignwidth'} -sequence $outfile -outfile $finalfile 2> /dev/null"
	);
	unlink $tempfile;
	print "<pre style=\"font-size:1.2em\">\n";
	$self->print_file($finalfile);
	print "</pre>\n";
	print "</div>\n";
	unlink $outfile;
	unlink $finalfile;
}

sub get_freq_table {
	my ( $self, $freqs, $locus_info ) = @_;
	my $buffer;
	return $buffer if ref $freqs ne 'HASH';
	my $temp     = BIGSdb::Utils::get_random();
	my $filename = $self->{'config'}->{'tmp_dir'} . "/$temp.txt";
	open( my $fh, '>', $filename ) or $logger->error("Can't open output file $filename");
	my $heading = $locus_info->{'data_type'} eq 'DNA' ? 'Nucleotide' : 'Amino acid';
	$buffer .= "<h2>$heading frequencies</h2>\n";
	print $fh "$heading frequencies\n";
	print $fh '-' x length("$heading frequencies") . "\n";
	my @chars = $locus_info->{'data_type'} eq 'DNA' ? qw(A C G T -) : qw (G A L M F W K Q E S P V I C Y H R N D T -);
	my $cols = @chars * 2;
	$buffer .= "<div class=\"scrollable\">\n";
	$buffer .=
"<table class=\"tablesorter\" id=\"sortTable\"><thead><tr><th rowspan=\"2\">Position</th><th colspan=\"$cols\" class=\"{sorter: false}\">$heading</th></tr>\n";
	$" = '</th><th>';
	$buffer .= "<tr><th>@chars</th>";
	$" = '</th><th>%';
	$buffer .= "<th>\%@chars</th></tr>\n</thead><tbody>\n";
	$" = "\t";
	print $fh "Position\t@chars";
	$" = "\t\%";
	print $fh "\t\%@chars\n";
	my $td = 1;
	my $total;
	my $first = 1;

	foreach ( sort { $a <=> $b } keys(%$freqs) ) {
		$buffer .= "<tr class=\"td$td\"><td>$_</td>";
		print $fh $_;
		foreach my $nuc (@chars) {
			$freqs->{$_}->{$nuc} ||= 0;
			$buffer .= "<td>$freqs->{$_}->{$nuc}</td>";
			print $fh "\t$freqs->{$_}->{$nuc}";
			$total += $freqs->{$_}->{$nuc} if $first;    #only calculate first time round
		}
		foreach my $nuc (@chars) {
			$freqs->{$_}->{$nuc} ||= 0;
			my $percent = BIGSdb::Utils::decimal_place( 100 * $freqs->{$_}->{$nuc} / $total, 2 );
			$buffer .= $percent > 0 ? "<td>$percent</td>" : "<td />";
			print $fh $percent > 0 ? "\t$percent" : "\t";
		}
		$buffer .= "</tr>\n";
		print $fh "\n";
		$td = $td == 1 ? 2 : 1;
		$first = 0;
	}
	$buffer .= "</tbody></table>\n</div>\n";
	close $fh;
	$buffer .= "<p><a href=\"/tmp/$temp.txt\">Tab-delimited text format</a></p>";
	return ( $buffer, "$temp.txt" );
}
1;
