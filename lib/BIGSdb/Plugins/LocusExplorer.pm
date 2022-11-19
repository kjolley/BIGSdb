#LocusExplorer.pm - Plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2022, University of Oxford
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
use 5.010;
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Bio::SeqIO;
use constant MAX_INSTANT_RUN => 100;
use constant MAX_SEQUENCES   => 2000;
use constant STYLESHEET      => 'https://pubmlst.org/css/bigsdb.min.css';

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name    => 'Locus Explorer',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@zoo.ox.ac.uk',
			}
		],
		description      => 'Tool for analysing allele sequences stored for particular locus',
		full_description => 'This plugin generates a schematic showing the polymorphic sites within a locus, '
		  . 'calculate the GC content, codon usage, and generate aligned translated sequences for selected alleles.',
		category   => 'Analysis',
		menutext   => 'Locus Explorer',
		module     => 'LocusExplorer',
		url        => "$self->{'config'}->{'doclink'}/data_analysis/locus_explorer.html",
		version    => '1.3.16',
		dbtype     => 'sequences',
		seqdb_type => 'sequences',
		input      => 'query',
		section    => 'postquery,analysis',
		requires   => 'aligner,offline_jobs',
		image      => '/images/plugins/LocusExplorer/screenshot.png',
		order      => 15
	);
	return \%att;
}

sub get_initiation_values {
	return { 'jQuery.tablesort' => 1 };
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
	my $stylesheet = $self->{'config'}->{'stylesheet'} // STYLESHEET;
	my $buffer =
	    qq(<!DOCTYPE html>\n)
	  . qq(<html><head><title>Polymorphic site analysis</title>\n)
	  . qq(<meta name="viewport" content="width=device-width" />\n)
	  . qq(<link rel="stylesheet" type="text/css" href="$stylesheet" media="Screen" />\n)
	  . qq(<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />\n</head><body>\n);
	return $buffer;
}

sub run {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $set_id = $self->get_set_id;
	my ( $display_loci, $cleaned ) = $self->{'datastore'}->get_locus_list( { set_id => $set_id } );
	my $query_file = $q->param('query_file');
	my $list_file  = $q->param('list_file');
	my $list       = $self->get_allele_id_list( $query_file, $list_file );
	say q(<h1>Locus Explorer</h1>);

	if ( !@$display_loci ) {
		$self->print_bad_status( { message => q(No loci have been defined for this database.) } );
		return;
	}
	if ( !$q->param('locus') ) {
		$q->param( locus => $display_loci->[0] );
	}
	my $locus = $q->param('locus');
	$locus =~ s/^cn_//x;
	my @allele_ids = $q->multi_param('allele_ids');
	if ( $q->param('submit') ) {
		my $total_seq_count =
		  $self->{'datastore'}
		  ->run_query( q(SELECT EXISTS(SELECT * FROM sequences WHERE locus=? AND allele_id NOT IN ('0','N'))), $locus );
		my $continue = 1;
		if ( !$self->{'datastore'}->is_locus($locus) ) {
			$self->print_bad_status( { message => q(Invalid locus.) } );
			$continue = 0;
		} elsif ( !$total_seq_count ) {
			$self->print_bad_status( { message => q(No sequences defined for this locus.) } );
			$continue = 0;
		} elsif ( !@allele_ids ) {
			$self->print_bad_status( { message => q(No sequences selected.) } );
			$continue = 0;
		}
		if ( !$continue ) {
			$q->delete('submit');
			$self->_print_interface( $locus, $display_loci, $cleaned, $list );
			return;
		}
	}
	my $analysis = $q->param('analysis') // '';
	if ($analysis) {
		if ( $analysis eq 'snp' ) {
			$self->_snp( $locus, \@allele_ids ) if $q->param('function') eq 'snp';
			$self->_site_explorer($locus) if $q->param('function') eq 'siteExplorer';
			return;
		} else {
			if ( $analysis eq 'codon' ) {
				$self->_codon( $locus, \@allele_ids );
				return;
			} elsif ( $analysis eq 'translate' ) {
				$self->_translate( $locus, \@allele_ids );
				return;
			}
		}
	}
	$self->_print_interface( $locus, $display_loci, $cleaned, $list );
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	my $locus = $params->{'locus'};
	$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => -1 } );    #indeterminate length of time
	$params->{'analysis'} //= 'snp';
	my @allele_ids = split /\|\|/x, $params->{'allele_ids'};
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( $params->{'analysis'} eq 'snp' ) {
		my ( $seqs, undef, $prefix ) = $self->_get_seqs( $params->{'locus'}, \@allele_ids );
		if ( !@$seqs ) {
			$self->{'jobManager'}
			  ->update_job_status( $job_id, { message_html => '<p>No sequences retrieved for analysis.</p>' } );
			return;
		}
		my $temp      = BIGSdb::Utils::get_random();
		my $html_file = "$self->{'config'}->{tmp_dir}/$temp.html";
		my ( $buffer, $freqs ) = $self->get_snp_schematic( $locus, $seqs, undef, $params->{'alignwidth'} );
		open( my $html_fh, '>', $html_file ) || $logger->error("Can't open $html_file for writing");
		print $html_fh $self->get_html_header($locus);
		say $html_fh q(<h1>Polymorphic site analysis</h1><div class="box" id="resultspanel">);
		print $html_fh $buffer;
		say $html_fh q(</div>);
		( $buffer, undef ) = $self->get_freq_table( $freqs, $locus_info );
		print $html_fh $buffer;
		say $html_fh q(</body></html>);
		$self->{'jobManager'}
		  ->update_job_output( $job_id, { filename => "$temp.html", description => 'Locus schematic (HTML format)' } );
		$self->delete_temp_files("$prefix*");
	} elsif ( $params->{'analysis'} eq 'translate' ) {
		my $orf = $locus_info->{'orf'} // 1;
		my $final_file = $self->_run_translate( $locus, \@allele_ids, { alignwidth => $params->{'alignwidth'} } );
		if ( -e $final_file ) {
			( my $rel_file_path = $final_file ) =~ s/.*\///x;
			$self->{'jobManager'}->update_job_output( $job_id,
				{ filename => $rel_file_path, description => 'Aligned translated sequence' } );
		}
	}
	return;
}

sub _print_interface {
	my ( $self, $locus, $display_loci, $cleaned, $list_ref ) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="queryform">);
	say $q->start_form;
	$q->param( function => 'snp' );
	say $q->hidden($_) foreach qw (db page function name);
	say q(<p>Please select locus for analysis:</p>);
	say q(<p><b>Locus: </b>);
	say $q->popup_menu( -name => 'locus', -id => 'locus', -values => $display_loci, -labels => $cleaned );
	say q( <span class="comment">Page will reload when changed</span></p>);
	my $desc_exists =
	  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM locus_descriptions WHERE locus=?)', $locus );

	if ($desc_exists) {
		say qq(<ul><li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=locusInfo&amp;)
		  . qq(locus=$locus">Further information</a> is available for this locus.</li></ul>);
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	return if !$locus_info;
	my $order = $locus_info->{'allele_id_format'} eq 'integer' ? 'CAST (allele_id AS integer)' : 'allele_id';
	my $max_sequences = MAX_SEQUENCES;
	my $allele_ids =
	  $self->{'datastore'}
	  ->run_query( "SELECT allele_id FROM sequences WHERE locus=? AND allele_id NOT IN ('0', 'N') ORDER BY $order",
		$locus, { fetch => 'col_arrayref' } );
	my $length_varies = $self->_does_seq_length_vary( $locus, $allele_ids );
	say qq(<p>Polymorphic site analysis is limited to $max_sequences sequences )
	  . q(for this locus since it requires alignment.</p>)
	  if $length_varies && @$allele_ids > MAX_SEQUENCES;
	say q(<fieldset style="float:left"><legend>Select sequences</legend>);
	say $q->scrolling_list(
		-name     => 'allele_ids',
		-id       => 'allele_ids',
		-values   => $allele_ids,
		-style    => 'width:100%',
		-size     => 6,
		-multiple => 'true',
		-default  => $list_ref
	);
	say q(<input type="button" onclick='listbox_selectall("allele_ids",true)' value="All" style="margin-top:1em" )
	  . q(class="small_submit" />);
	say q(<input type="button" onclick='listbox_selectall("allele_ids",false)' value="None" style="margin-top:1em" )
	  . q(class="small_submit" />);
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Select analysis</legend>);
	my $aligner_available = ( $self->{'config'}->{'muscle_path'} || $self->{'config'}->{'mafft_path'} ) ? 1 : 0;
	my $labels = {
		snp       => 'Polymorphic Sites - Display polymorphic site frequencies and sequence schematic',
		codon     => 'Codon - Calculate G+C content and codon usage',
		translate => 'Translate - Translate DNA to peptide sequences'
	};
	my @values;

	if ( !$length_varies || $aligner_available ) {
		push @values, 'snp';
	}
	if ( $self->{'config'}->{'emboss_path'} && $locus_info->{'data_type'} eq 'DNA' ) {
		push @values, 'codon';
		if ( $locus_info->{'coding_sequence'} && ( !$length_varies || $aligner_available ) ) {
			push @values, 'translate';
		}
	}
	say $q->radio_group( -name => 'analysis', -values => \@values, -labels => $labels, -linebreak => 'true' );
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->end_form;
	say q(</div>);
	return;
}

sub _get_seqs {
	my ( $self, $locus, $allele_ids, $options ) = @_;

	#options: count_only - don't align, just count how many sequences would be included.
	$options = {} if ref $options ne 'HASH';
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my @seqs;
	my $temp     = BIGSdb::Utils::get_random();
	my $tempfile = "$self->{'config'}->{'secure_tmp_dir'}/$temp.txt";
	open( my $fh, '>', $tempfile ) or $logger->error("could not open temp file $tempfile");
	my $i    = 0;
	my $data = $self->{'datastore'}->run_query( 'SELECT allele_id,sequence FROM sequences WHERE locus=?',
		$locus, { fetch => 'all_arrayref', slice => {} } );
	my %selected_id = map { $_ => 1 } @$allele_ids;

	foreach my $allele (@$data) {
		next if !$selected_id{ $allele->{'allele_id'} };
		push @seqs, $allele->{'sequence'};
		say $fh ">$allele->{'allele_id'}";
		say $fh $allele->{'sequence'};
		$i++;
	}
	close $fh;
	if ( $options->{'count_only'} ) {
		unlink $tempfile;
		return $i;
	}
	my $seq_file;
	my $aligned_file = "$self->{'config'}->{secure_tmp_dir}/$temp.aligned";
	if ( $self->_does_seq_length_vary( $locus, $allele_ids ) ) {
		if ( $options->{'print_status'} ) {
			local $| = 1;
			say q(<div class="hideonload"><p>Please wait - aligning (do not refresh) ...</p>)
			  . q(<p><span class="wait_icon fas fa-sync-alt fa-spin fa-4x"></span></p></div>);
			if ( $ENV{'MOD_PERL'} ) {
				$self->{'mod_perl_request'}->rflush;
				return if $self->{'mod_perl_request'}->connection->aborted;
			}
		}
		if ( -x $self->{'config'}->{'mafft_path'} ) {
			my $threads =
			  BIGSdb::Utils::is_int( $self->{'config'}->{'mafft_threads'} )
			  ? $self->{'config'}->{'mafft_threads'}
			  : 1;
			system(
				"$self->{'config'}->{'mafft_path'} --thread $threads --quiet --preservecase $tempfile > $aligned_file");
		} elsif ( -x $self->{'config'}->{'muscle_path'} ) {
			system( $self->{'config'}->{'muscle_path'}, '-in', $tempfile, '-fastaout', $aligned_file, '-quiet' );
		} else {
			$logger->error('No aligner available.');
		}
		my $seqio_object = Bio::SeqIO->new( -file => $aligned_file, -format => 'Fasta' );
		undef @seqs;
		while ( my $seq_object = $seqio_object->next_seq ) {
			push @seqs, $seq_object->seq;
		}
		$seq_file = "$temp.aligned";
	} else {
		$seq_file = "$temp.txt";
	}
	return ( \@seqs, $seq_file, $temp );
}

sub _snp {
	my ( $self, $locus, $allele_ids ) = @_;
	my $q = $self->{'cgi'};
	say '<h2>Polymorphic site analysis</h2>';
	my $locus_info    = $self->{'datastore'}->get_locus_info($locus);
	my $seq_count     = $self->_get_seqs( $locus, $allele_ids, { count_only => 1 } );
	my $max_sequences = MAX_SEQUENCES;
	my $allele_count  = @$allele_ids;
	my $length_varies = $self->_does_seq_length_vary( $locus, $allele_ids );
	if ( $seq_count <= MAX_INSTANT_RUN || !$length_varies ) {
		say q(<div class="box" id="resultspanel">);
		my $cleaned = $self->clean_locus($locus);
		say qq(<h2>$cleaned</h2>);
		my ( $seqs, $seq_file, $prefix ) = $self->_get_seqs( $locus, $allele_ids, { print_status => 1 } );
		my ( $buffer, $freqs ) = $self->get_snp_schematic( $locus, $seqs, $seq_file, $self->{'prefs'}->{'alignwidth'} );
		say $buffer;
		say q(</div>);
		( $buffer, undef ) = $self->get_freq_table( $freqs, $locus_info );
		say $buffer if $buffer;

		#Keep temp files as they are needed for site explorer function.
	} elsif ( $seq_count > $max_sequences && $length_varies ) {
		$self->print_bad_status(
			{
				message => q(This locus is variable length and will therefore require )
				  . qq(real-time alignment. Consequently this function is limited to $max_sequences sequences or )
				  . qq(fewer - you have selected $allele_count.),
				navbar => 1,
				back_url =>
				  qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;name=LocusExplorer)
			}
		);
	} else {
		$self->_submit_job( $locus, $allele_ids );
	}
	return;
}

sub _does_seq_length_vary {
	my ( $self, $locus, $allele_ids ) = @_;
	my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( 'text', $allele_ids );
	my $lengths =
	  $self->{'datastore'}->run_query( 'SELECT length(sequence) FROM sequences WHERE locus=? GROUP BY length(sequence)',
		$locus, { fetch => 'col_arrayref' } );
	return 1 if @$lengths > 1;
	return;
}

sub _submit_job {
	my ( $self, $locus, $allele_ids ) = @_;
	my $q      = $self->{'cgi'};
	my $params = $q->Vars;
	$q->delete('locus');
	$params->{'locus'} = $locus;
	local $" = q(||);
	$params->{'allele_id'}  = "@$allele_ids";
	$params->{'alignwidth'} = $self->{'prefs'}->{'alignwidth'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $job_id    = $self->{'jobManager'}->add_job(
		{
			dbase_config => $self->{'instance'},
			ip_address   => $q->remote_host,
			module       => 'LocusExplorer',
			parameters   => $params,
			username     => $self->{'username'},
			email        => $user_info->{'email'}
		}
	);
	say $self->get_job_redirect($job_id);
	return;
}

sub get_snp_schematic {
	my ( $self, $locus, $seqs, $seq_file, $align_width ) = @_;
	my $seq_count = scalar @$seqs;
	my $pagebuffer;
	my @linebuffer;
	my $ps         = 0;
	my $std_length = length( $seqs->[0] );
	my $freqs;
	for my $i ( 0 .. $std_length - 1 ) {

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
				$pagebuffer .= q(&nbsp;) x 7 . qq($line<br />\n);
			}
			undef @linebuffer;
			$pagebuffer .= $self->_get_seq_ruler( $i + 1, $length, $align_width );
			$pagebuffer .= qq(<br />\n);
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
			my $prop  = $nuc{$base} / $seq_count;
			my $class = $self->_get_prop_class($prop);
			if ($seq_file) {
				my $pos = $i + 1;
				$linebuffer[$linenumber] .=
				    qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . q(page=plugin&amp;name=LocusExplorer&amp;analysis=snp&amp;function=siteExplorer&amp;)
				  . qq(file=$seq_file&amp;locus=$locus&amp;pos=$pos" class="$class">$base</a>);
			} else {
				$linebuffer[$linenumber] .= qq(<span class="$class">$base</span>);
			}
			$linenumber++;
		}
		for ( my $j = $linenumber ; $j < 21 ; $j++ ) {
			$linebuffer[$j] .= q(&nbsp;);
		}
	}
	foreach my $line (@linebuffer) {
		( my $test = $line ) =~ tr/\&nbsp;//d;
		next if $test eq q();
		$pagebuffer .= q(&nbsp;) x 7 . qq($line<br />\n);
	}
	my $pluralps = $ps != 1        ? 's' : '';
	my $plural   = $seq_count != 1 ? 's' : '';
	my $locus_info        = $self->{'datastore'}->get_locus_info($locus);
	my $nuc_or_pep        = $locus_info->{'data_type'} eq 'peptide' ? 'amino acid' : 'nucleotide';
	my $allele_or_variant = $locus_info->{'data_type'} eq 'peptide' ? 'variant' : 'allele';
	my $buffer =
	    q(<div class="results">)
	  . qq(<p>The colour codes represent the percentage of ${allele_or_variant}s that have )
	  . qq(a particular $nuc_or_pep at each position. Click anywhere within )
	  . q(the sequence to drill down to allele and profile information. )
	  . q(The width of the display can be altered by going to the options )
	  . q(page - change this if the display goes off the page.</p>)
	  . qq(<p>$seq_count $allele_or_variant$plural included in analysis. )
	  . qq($ps polymorphic site$pluralps found.</p><p><b>Key: </b>);
	foreach my $low (qw (0 10 20 30 40 50 60 70 80 90)) {
		my $high = $low + 10;
		$buffer .= q( | )  if $low;
		$buffer .= qq(<span class="pc$high">);
		$buffer .= q(&gt;) if $low;
		$buffer .= qq($low - $high</span>);
	}
	$buffer .= qq(</p><div class="scrollable"><div class="seqmap" style="white-space:nowrap">\n);
	$buffer .= $pagebuffer;
	$buffer .= q(</div></div></div>);
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
	$ruler .= ( q(&nbsp;) x $num_spaces ) . $label[0]
	  if length($ruler) < $length;

	# First label on 1, rest on tens
	# Each label must occupy 9 characters
	for ( my $i = 1 ; $i < $num_labels ; $i++ ) {
		if ( $label[$i] ) {
			$num_spaces = 9 - length( $label[$i] );
			$label[$i] = ( q(&nbsp;) x $num_spaces ) . $label[$i];
			$ruler .= ( $label[$i] . q( ) );
		}
	}
	$ruler .= qq(\n);
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
	my ( $self, $locus ) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Site Explorer</h1>);
	my $pos       = $q->param('pos');
	my $temp_file = $q->param('file');
	if ( !$temp_file || !-e "$self->{'config'}->{'secure_tmp_dir'}/$temp_file" ) {
		$self->print_bad_status( { message => q(No sequence file passed.), navbar => 1 } );
		return;
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	say q(<div class="box" id="resultstable">);
	my $cleaned = $self->clean_locus($locus);
	say qq(<h2>$cleaned position $pos</h2>);
	my %seq;
	my $seqio_object =
	  Bio::SeqIO->new( -file => "$self->{'config'}->{'secure_tmp_dir'}/$temp_file", -format => 'fasta' );
	while ( my $seq_object = $seqio_object->next_seq ) {
		$seq{ $seq_object->seq } = $seq_object->id;
	}
	my $seq_count = keys %seq;
	say qq(<p>$seq_count alleles included in analysis.</p>);
	my %site;
	my %allele;
	foreach my $allele ( keys %seq ) {
		$site{ uc( substr( $allele, $pos - 1, 1 ) ) }++;
		push @{ $allele{ uc( substr( $allele, $pos - 1, 1 ) ) } }, $seq{$allele};
	}
	my $td          = 1;
	my $scheme_list = $self->{'datastore'}->run_query(
		'SELECT id,name FROM schemes LEFT JOIN scheme_members ON '
		  . 'scheme_id=schemes.id WHERE locus=? AND scheme_id IN (SELECT scheme_id FROM scheme_fields WHERE primary_key)',
		$locus,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my ( @schemes, %desc );
	foreach my $scheme (@$scheme_list) {
		push @schemes, $scheme->{'id'};
		$desc{ $scheme->{'id'} } = $scheme->{'name'};
	}
	say q(<table class="resultstable"><tr><th>Base</th><th>Number of alleles</th><th>Percentage of alleles</th>);
	say qq(<th>$desc{$_} profiles</th>) foreach @schemes;
	say q(</tr>);
	foreach my $base ( sort { $site{$b} <=> $site{$a} } ( keys(%site) ) ) {
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
		my @allelelist    = @{ $allele{$base} };
		my @sortedalleles = sort { $a <=> $b } @allelelist;
		my $pc            = BIGSdb::Utils::decimal_place( ( ( $site{$base} / $seq_count ) * 100 ), 2 );
		say qq(<tr class="td$td"><td>$base</td><td>$site{$base});
		if ( $site{$base} < 6 ) {
			local $" = ", $cleaned-";
			say qq(<br />($cleaned-@sortedalleles));
		}
		say qq(</td><td>$pc</td>);
		foreach my $scheme_id (@schemes) {
			my $locus_name = $self->{'datastore'}->get_scheme_warehouse_locus_name( $scheme_id, $locus );
			local $" = "' OR $locus_name='";
			my $qry      = "SELECT COUNT(*) FROM mv_scheme_$scheme_id WHERE $locus_name='@allelelist'";
			my $numSTs   = $self->{'datastore'}->run_query($qry);
			my $totalSTs = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM mv_scheme_$scheme_id");
			print "<td>$numSTs / $totalSTs";
			my $pcST;
			if ( $totalSTs == 0 ) {
				$pcST = '-';
			} else {
				$pcST = BIGSdb::Utils::decimal_place( ( ( $numSTs / $totalSTs ) * 100 ), 2 );
			}
			say qq(<br />($pcST\%)</td>);
		}
		say q(</tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</table></div>);
	return;
}

sub _get_selected_alleles {
	my ( $self, $locus, $allele_ids ) = @_;
	my %selected = map { $_ => 1 } @$allele_ids;
	my $alleles = $self->{'datastore'}->run_query( 'SELECT allele_id,sequence FROM sequences WHERE locus=?',
		$locus, { fetch => 'all_arrayref', slice => {} } );
	my @seqs;
	foreach my $allele (@$alleles) {
		next if !$selected{ $allele->{'allele_id'} };
		push @seqs, $allele->{'sequence'};
	}
	return \@seqs;
}

sub _codon {
	my ( $self, $locus, $allele_ids ) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Codon Usage</h1>);
	if ( !$self->{'config'}->{'emboss_path'} ) {
		$self->print_bad_status( { message => q(EMBOSS is not installed - function unavailable.), navbar => 1 } );
		return;
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $orf = $locus_info->{'orf'} // 1;
	say q(<div class="box" id="resultspanel"><div class="scrollable">);
	my $cleaned = $self->clean_locus($locus);
	say qq(<h2>$cleaned</h2>);
	say qq(<p>ORF used: $orf</p>);
	my $seqs      = $self->_get_selected_alleles( $locus, $allele_ids );
	my $seq_count = scalar @$seqs;
	my $plural    = $seq_count != 1 ? 's' : '';
	say qq(<p>$seq_count allele$plural included in analysis.</p>);
	my $temp     = BIGSdb::Utils::get_random();
	my $tempfile = "$self->{'config'}->{secure_tmp_dir}/$temp.txt";
	my $outfile  = "$self->{'config'}->{secure_tmp_dir}/$temp.cusp";
	open( my $fh, '>', "$tempfile" ) or $logger->error("could not open temp file $tempfile");
	my $i = 1;

	foreach (@$seqs) {
		my $seq = BIGSdb::Utils::chop_seq( $_, $orf );
		say $fh ">$i\n$seq";
		$i++;
	}
	close $fh;
	system("$self->{'config'}->{'emboss_path'}/cusp -sequence $tempfile -outfile $outfile 2> /dev/null");
	unlink $tempfile;
	my @codons;
	say q(<h3>GC content</h3>);
	say q(<p>);
	open $fh, '<', $outfile || $logger->error("Can't open $outfile for reading");

	while ( my $line = <$fh> ) {
		chomp $line;
		push @codons, $line if $line && $line !~ /^\#/x;
		if ( $line =~ /%/x ) {
			$line =~ s/\#//x;
			$line =~ s/\ GC/:\ GC/x;
			say qq($line<br />);
		}
	}
	close $fh;
	say q(</p></div></div>);
	return if !$locus_info->{'coding_sequence'};
	say q(<div class="box" id="resultstable"><div class="scrollable"><h3>Codons</h3>)
	  . q[<p>Fraction: Proportion of usage of a given codon among its ]
	  . q[redundant set (i.e. the set of codons which code for this ]
	  . q[codon's amino acid).<br />]
	  . q[Frequency: Usage of given codon per 1000 codons.</p>]
	  . q[<table class="tablesorter" id="sortTable"><thead><tr><th>Codon</th>]
	  . q[<th>Amino acid</th><th>Fraction</th><th>Frequency</th><th>Number</th></tr></thead>]
	  . q[<tbody>];
	local $" = '</td><td>';
	my $td = 1;
	foreach (@codons) {
		my @values = split /\s+/x, $_;
		say qq(<tr class="td$td"><td>@values</td></tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</tbody></table>);
	unlink $outfile;
	say q(</div></div>);
	return;
}

sub _translate {
	my ( $self, $locus, $allele_ids ) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Translate - aligned protein sequences</h1>);
	if ( !$self->{'config'}->{'emboss_path'} ) {
		$self->print_bad_status( { message => q(EMBOSS is not installed - function unavailable.), navbar => 1 } );
		return;
	}
	my $locus_info    = $self->{'datastore'}->get_locus_info($locus);
	my $max_sequences = MAX_SEQUENCES;
	my $allele_count  = @$allele_ids;
	my $length_varies = $self->_does_seq_length_vary( $locus, $allele_ids );
	if ( $allele_count <= MAX_INSTANT_RUN || !$length_varies ) {
		local $| = 1;
		say q(<div class="hideonload"><p>Please wait - aligning (do not refresh) ...</p>)
		  . q(<p><span class="wait_icon fas fa-sync-alt fa-spin fa-4x"></span></p></div>);
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
		my $orf = $locus_info->{'orf'} // 1;
		say q(<div class="box" id="resultspanel"><div class="scrollable">);
		my $cleaned = $self->clean_locus($locus);
		say qq(<h2>$cleaned</h2>);
		say qq(<p>ORF used: $orf</p>);
		my $plural = $allele_count != 1 ? 's' : '';
		say q(<p>The width of the alignment can be varied by going to the options page.</p>) if $allele_count > 1;
		say qq(<p>$allele_count allele$plural included in analysis.</p>);
		my $final_file = $self->_run_translate( $locus, $allele_ids );
		say q(<pre>);
		$self->print_file($final_file);
		say q(</pre></div></div>);
		unlink $final_file;
	} elsif ( $length_varies && @$allele_ids > MAX_SEQUENCES ) {
		$self->print_bad_status(
			{
				message => q(This locus is variable length and will therefore )
				  . qq(require real-time alignment. Consequently this function is limited to $max_sequences )
				  . qq(sequences or fewer - you have selected $allele_count.),
				navbar => 1,
				back_url =>
				  qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;name=LocusExplorer)
			}
		);
	} else {
		$self->_submit_job( $locus, $allele_ids );
	}
	return;
}

sub _run_translate {
	my ( $self, $locus, $allele_ids, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my %seqs_hash;
	my %selected = map { $_ => 1 } @$allele_ids;
	my $alleles = $self->{'datastore'}->run_query( 'SELECT allele_id,sequence FROM sequences WHERE locus=?',
		$locus, { fetch => 'all_arrayref', slice => {} } );
	foreach my $allele (@$alleles) {
		next if !$selected{ $allele->{'allele_id'} };
		$seqs_hash{ $allele->{'allele_id'} } = $allele->{'sequence'};
	}
	my $seq_count  = keys %seqs_hash;
	my $temp       = BIGSdb::Utils::get_random();
	my $temp_file  = "$self->{'config'}->{'secure_tmp_dir'}/$temp.txt";
	my $out_file   = "$self->{'config'}->{'tmp_dir'}/$temp.pep";
	my $final_file = "$self->{'config'}->{'tmp_dir'}/$temp.aln";
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $orf        = $locus_info->{'orf'} // 1;
	open( my $fh, '>', "$temp_file" ) or $logger->error("could not open temp file $temp_file");

	if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
		foreach ( sort { $a <=> $b } keys %seqs_hash ) {
			say $fh ">$_\n$seqs_hash{$_}";
		}
	} else {
		foreach ( sort { $a cmp $b } keys %seqs_hash ) {
			say $fh ">$_\n$seqs_hash{$_}";
		}
	}
	close $fh;
	my %orf_frame = (
		1 => 1,
		2 => 2,
		3 => 3,
		4 => -1,
		5 => -2,
		6 => -3
	);
	system( "$self->{'config'}->{'emboss_path'}/transeq -sequence $temp_file -outseq "
		  . "$out_file -frame $orf_frame{$orf} -trim -clean 2> /dev/null" );
	if ( $seq_count > 1 ) {
		if ( $self->_does_seq_length_vary( $locus, $allele_ids ) ) {
			my $aligned_file = "$self->{'config'}->{secure_tmp_dir}/$temp.aligned";
			if ( -x $self->{'config'}->{'mafft_path'} ) {
				my $threads =
				  BIGSdb::Utils::is_int( $self->{'config'}->{'mafft_threads'} )
				  ? $self->{'config'}->{'mafft_threads'}
				  : 1;
				system( "$self->{'config'}->{'mafft_path'} --thread $threads "
					  . "--quiet --preservecase $out_file > $aligned_file" );
			} elsif ( -x $self->{'config'}->{'muscle_path'} ) {
				system( $self->{'config'}->{'muscle_path'}, '-quiet', ( -in => $out_file, -out => $aligned_file ) );
			}
			unlink $out_file;
			$out_file = $aligned_file;
		}
		my $alignwidth = $options->{'alignwidth'} // $self->{'prefs'}->{'alignwidth'} // 100;
		system( "$self->{'config'}->{'emboss_path'}/showalign -nosimilarcase -width $alignwidth "
			  . "-sequence $out_file -outfile $final_file 2> /dev/null" );
		unlink $temp_file;
	} else {
		$final_file = $out_file;
	}
	return $final_file;
}

sub get_freq_table {
	my ( $self, $freqs, $locus_info ) = @_;
	my $buffer;
	return $buffer if ref $freqs ne 'HASH';
	my $temp     = BIGSdb::Utils::get_random();
	my $filename = $self->{'config'}->{'tmp_dir'} . "/$temp.txt";
	open( my $fh, '>', $filename ) or $logger->error("Can't open output file $filename");
	my $heading = $locus_info->{'data_type'} eq 'DNA' ? 'Nucleotide' : 'Amino acid';
	$buffer .= q(<div class="box" id="resultstable">);
	$buffer .= "<h2>$heading frequencies</h2>\n";
	say $fh "$heading frequencies";
	say $fh '-' x length("$heading frequencies");
	my @chars = $locus_info->{'data_type'} eq 'DNA' ? qw(A C G T -) : qw (G A L M F W K Q E S P V I C Y H R N D T -);
	my $cols = @chars * 2;
	$buffer .= q(<div class="scrollable">);
	$buffer .= q(<table class="tablesorter" id="sortTable"><thead><tr><th rowspan="2">Position</th>)
	  . qq(<th colspan="$cols" class="sorter-false">$heading</th></tr>);
	local $" = '</th><th>';
	$buffer .= qq(<tr><th>@chars</th>);
	local $" = '</th><th>%';
	$buffer .= qq(<th>\%@chars</th></tr></thead><tbody>);
	local $" = "\t";
	print $fh qq(Position\t@chars);
	local $" = "\t\%";
	say $fh qq(\t\%@chars);
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
			$buffer .= $percent > 0 ? qq(<td>$percent</td>) : q(<td></td>);
			print $fh $percent > 0 ? qq(\t$percent) : qq(\t);
		}
		$buffer .= qq(</tr>\n);
		print $fh qq(\n);
		$td = $td == 1 ? 2 : 1;
		$first = 0;
	}
	$buffer .= q(</tbody></table></div></div>);
	close $fh;
	$buffer .= q(<div class="box" id="resultsfooter"><p>Download: )
	  . qq(<a href="/tmp/$temp.txt">Tab-delimited text format</a></p></div>);
	return ( $buffer, "$temp.txt" );
}
1;
