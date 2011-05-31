#CodonUsage.pm - Codon usage plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2011, University of Oxford
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
package BIGSdb::Plugins::CodonUsage;
use strict;
use base qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
my %codons_per_aa = (
	'A' => 4,
	'C' => 2,
	'D' => 2,
	'E' => 2,
	'F' => 2,
	'G' => 4,
	'H' => 2,
	'I' => 3,
	'K' => 2,
	'L' => 6,
	'M' => 1,
	'N' => 2,
	'P' => 4,
	'Q' => 2,
	'R' => 6,
	'S' => 6,
	'T' => 4,
	'V' => 4,
	'W' => 1,
	'Y' => 2,
	'*' => 3
);
my %translate = (
	'GCA' => 'A',
	'GCC' => 'A',
	'GCG' => 'A',
	'GCT' => 'A',
	'TGC' => 'C',
	'TGT' => 'C',
	'GAC' => 'D',
	'GAT' => 'D',
	'GAA' => 'E',
	'GAG' => 'E',
	'TTC' => 'F',
	'TTT' => 'F',
	'GGA' => 'G',
	'GGC' => 'G',
	'GGG' => 'G',
	'GGT' => 'G',
	'CAC' => 'H',
	'CAT' => 'H',
	'ATA' => 'I',
	'ATC' => 'I',
	'ATT' => 'I',
	'AAA' => 'K',
	'AAG' => 'K',
	'CTA' => 'L',
	'CTC' => 'L',
	'CTG' => 'L',
	'CTT' => 'L',
	'TTA' => 'L',
	'TTG' => 'L',
	'ATG' => 'M',
	'AAC' => 'N',
	'AAT' => 'N',
	'CCA' => 'P',
	'CCC' => 'P',
	'CCG' => 'P',
	'CCT' => 'P',
	'CAA' => 'Q',
	'CAG' => 'Q',
	'AGA' => 'R',
	'AGG' => 'R',
	'CGA' => 'R',
	'CGC' => 'R',
	'CGG' => 'R',
	'CGT' => 'R',
	'AGC' => 'S',
	'AGT' => 'S',
	'TCA' => 'S',
	'TCC' => 'S',
	'TCG' => 'S',
	'TCT' => 'S',
	'ACA' => 'T',
	'ACC' => 'T',
	'ACG' => 'T',
	'ACT' => 'T',
	'GTA' => 'V',
	'GTC' => 'V',
	'GTG' => 'V',
	'GTT' => 'V',
	'TGG' => 'W',
	'TAC' => 'Y',
	'TAT' => 'Y',
	'TAA' => '*',
	'TAG' => '*',
	'TGA' => '*'
);

sub get_attributes {
	my %att = (
		name        => 'CodonUsage',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Determine codon usage for specified loci for an isolate database query',
		category    => 'Breakdown',
		buttontext  => 'Codons',
		menutext    => 'Codon usage',
		module      => 'CodonUsage',
		version     => '1.0.0',
		dbtype      => 'isolates',
		section     => 'analysis,postquery',
		input       => 'query',
		requires    => 'offline_jobs',
		system_flag => 'CodonUsage',
		order       => 13
	);
	return \%att;
}

sub run {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	print "<h1>Codon usage analysis</h1>\n";
	my $list;
	my $qry_ref;
	if ( $q->param('list') ) {
		foreach ( split /\n/, $q->param('list') ) {
			chomp;
			push @$list, $_;
		}
	} elsif ($query_file) {
		my $qry_ref = $self->get_query($query_file);
		return if ref $qry_ref ne 'SCALAR';
		my $view = $self->{'system'}->{'view'};
		return if !$self->create_temp_tables($qry_ref);
		$$qry_ref =~ s/SELECT ($view\.\*|\*)/SELECT $view.id/;
		$self->rewrite_query_ref_order_by($qry_ref) if $self->{'system'}->{'dbtype'} eq 'isolates';
		$list = $self->{'datastore'}->run_list_query($$qry_ref);
	} else {
		$list = \@;;
	}
	if ( $q->param('submit') ) {
		my @param_names = $q->param;
		my @fields_selected;
		foreach (@param_names) {
			push @fields_selected, $_ if $_ =~ /^l_/ or $_ =~ /s_\d+_l_/;
		}
		if ( !@fields_selected ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No fields have been selected!</p></div>\n";
		} else {
			my $params = $q->Vars;
			( my $list = $q->param('list') ) =~ s/[\r\n]+/\|\|/g;
			$params->{'list'} = $list;
			my $job_id = $self->{'jobManager'}->add_job(
				{
					'dbase_config' => $self->{'instance'},
					'ip_address'   => $q->remote_host,
					'module'       => 'CodonUsage',
					'parameters'   => $params
				}
			);
			print <<"HTML";
<div class="box" id="resultstable">
<p>This analysis has been submitted to the job queue.</p>
<p>Please be aware that this job may take some time depending on the number of sequences to analyse
and how busy the server is.</p>
<p><a href="$self->{'script_name'}?db=$self->{'instance'}&amp;page=job&amp;id=$job_id">
Follow the progress of this job and view the output.</a></p> 	
</div>	
HTML
			return;
		}
	}
	print <<"HTML";
<div class="box" id="queryform">
<p>This plugin will analyse the codon usage for individual loci and overall for an isolate.  Only loci that 
have a corresponding database containing sequences, or with sequences tagged,  
can be included.  It is important to note that correct identification of codons can only be achieved for loci
for which the correct ORF has been set (if they are not in reading frame 1).  Partial sequnces from the sequence
bin will not be analysed. Please check the loci that you 
would like to include.</p>
HTML
	my $options = { 'default_select' => 0, 'translate' => 0, 'options_heading' => 'Sequence retrieval' };
	$self->print_sequence_export_form( 'id', $list, undef, $options );
	print "</div>\n";
}

sub get_extra_form_elements {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $buffer = "<fieldset style=\"float:left\">\n<legend>Codons</legend>\n";
	$buffer .= "<p>Select codon order:</p>\n";
	$buffer .= $q->radio_group(
		-name      => 'codonorder',
		-values    => [ 'alphabetical', 'cg_ending_first' ],
		-labels    => { 'cg_ending_first' => 'C or G ending codons first' },
		-linebreak => 'true'
	);
	$buffer .= "</fieldset>\n";
	return $buffer;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	my $rscu_by_isolate = "$self->{'config'}->{'tmp_dir'}/$job_id\_rscu_by_isolate.txt";
	my $number_by_isolate = "$self->{'config'}->{'tmp_dir'}/$job_id\_number_by_isolate.txt";
	my $rscu_by_locus   = "$self->{'config'}->{'tmp_dir'}/$job_id\_rscu_by_locus.txt";
	my $number_by_locus = "$self->{'config'}->{'tmp_dir'}/$job_id\_number_by_locus.txt";
	my $isolate_sql;
	if ( $params->{'includes'} ) {
		my @includes = split /\|\|/, $params->{'includes'};
		$"           = ',';
		$isolate_sql = $self->{'db'}->prepare("SELECT @includes FROM $self->{'system'}->{'view'} WHERE id=?");
	}
	my $seqbin_sql =
	  $self->{'db'}->prepare(
"SELECT substring(sequence from start_pos for end_pos-start_pos+1),reverse FROM allele_sequences LEFT JOIN sequence_bin ON allele_sequences.seqbin_id = sequence_bin.id WHERE isolate_id=? AND locus=? AND complete ORDER BY allele_sequences.datestamp LIMIT 1"
	  );
	my @problem_ids;
	my $start = 1;
	my $end;
	my $no_output = 1;

	#reorder loci by genome order, schemes then by name (genome order may not be set)
	my $locus_qry =
"SELECT id,scheme_id from loci left join scheme_members on loci.id = scheme_members.locus order by genome_position,scheme_members.scheme_id,id";
	my $locus_sql = $self->{'db'}->prepare($locus_qry);
	eval { $locus_sql->execute; };
	if ($@) {
		$logger->error("Can't execute $@");
	}
	my @selected_fields;
	my %picked;
	while ( my ( $locus, $scheme_id ) = $locus_sql->fetchrow_array ) {
		if ( ( $scheme_id && $params->{"s_$scheme_id\_l_$locus"} ) || ( !$scheme_id && $params->{"l_$locus"} ) ) {
			push @selected_fields, $locus if !$picked{$locus};
			$picked{$locus} = 1;
		}
	}
	my @list = split /\|\|/, $params->{'list'};
	if ( !@list ) {
		my $qry = "SELECT id FROM $self->{'system'}->{'view'} ORDER BY id";
		@list = @{ $self->{'datastore'}->run_list_query($qry) };
	}
	my $progress = 0;
	my ( $locus_codon_count, $locus_aa_count, $total_codon_count, $total_aa_count, $rscu );
	my %includes;
	foreach my $locus_name (@selected_fields) {
		my $locus;
		my $locus_info = $self->{'datastore'}->get_locus_info($locus_name);
		my $common_length;
		try {
			$locus = $self->{'datastore'}->get_locus($locus_name);
		}
		catch BIGSdb::DataException with {
			$logger->warn("Invalid locus '$locus_name' passed.");
		};
		my $temp      = BIGSdb::Utils::get_random();
		my $temp_file = "$self->{'config'}->{secure_tmp_dir}/$temp.txt";
		my $cusp_file = "$self->{'config'}->{secure_tmp_dir}/$temp.cusp";
		$" = '|';
		foreach my $id (@list) {
			open( my $fh_cusp_in, '>', "$temp_file" ) or $logger->error("could not open temp file $temp_file");
			my @includes;
			next if !BIGSdb::Utils::is_int($id);
			if ( $params->{'includes'} ) {
				eval { $isolate_sql->execute($id); };
				if ($@) {
					$logger->error("Can't execute $@");
				}
				@includes = $isolate_sql->fetchrow_array;
				foreach (@includes) {
					$_ =~ tr/ /_/;
				}
				$includes{$id} = "|@includes";
			}
			if ($id) {
				print $fh_cusp_in ">$id\n";
			} else {
				push @problem_ids, $id;
				next;
			}
			my $allele_id = $self->{'datastore'}->get_allele_id( $id, $locus_name );
			my $allele_seq;
			if ( $locus_info->{'data_type'} eq 'DNA' ) {
				try {
					$allele_seq = $locus->get_allele_sequence($allele_id);
				}
				catch BIGSdb::DatabaseConnectionException with {

					#do nothing
				};
			}
			my $seqbin_seq;
			eval { $seqbin_sql->execute( $id, $locus_name ); };
			if ($@) {
				$logger->error("Can't execute, $@");
			} else {
				my $reverse;
				( $seqbin_seq, $reverse ) = $seqbin_sql->fetchrow_array;
				if ($reverse) {
					$seqbin_seq = BIGSdb::Utils::reverse_complement($seqbin_seq);
				}
			}
			my $seq;
			if ( ref $allele_seq && $$allele_seq && $seqbin_seq ) {
				$seq = $params->{'chooseseq'} eq 'seqbin' ? $seqbin_seq : $$allele_seq;
			} elsif ( ref $allele_seq && $$allele_seq && !$seqbin_seq ) {
				$seq = $$allele_seq;
			} elsif ($seqbin_seq) {
				$seq = $seqbin_seq;
			} else {
			}
			$seq = BIGSdb::Utils::chop_seq( $seq, $locus_info->{'orf'} || 1 );
			print $fh_cusp_in "$seq\n";
			close $fh_cusp_in;
			system( "$self->{'config'}->{'emboss_path'}/cusp", '-sequence', $temp_file, '-outfile', $cusp_file, '-warning', 'false' );
			if ( -e $cusp_file ) {
				open( my $fh_cusp, '<', $cusp_file );
				while (<$fh_cusp>) {
					next if $_ =~ /^#/ || $_ eq '';
					my ( $codon, $aa, undef, undef, $number ) = split /\s+/, $_;
					$locus_codon_count->{$locus_name}->{$codon} += $number;
					$locus_aa_count->{$locus_name}->{$aa} += $number;
					$total_codon_count->{$id}->{$codon}    += $number;
					$total_aa_count->{$id}->{$aa}          += $number;
				}
				close $fh_cusp;
			}
			unlink $cusp_file, $temp_file;
		}
		$progress++;
		my $complete = int( 90 * $progress / scalar @selected_fields );    #go up to 90%
		$self->{'jobManager'}->update_job_status( $job_id, { 'percent_complete' => $complete } );
	}
	my $message_html;
	$" = "\t";
	my @codons = $self->_get_codons;
	if ( $params->{'codonorder'} eq 'alphabetical' ) {
		@codons = sort @codons;
	}
	open( my $fh_rscu_by_isolate, '>', $rscu_by_isolate )
	  or $logger->error("Can't open output file $rscu_by_isolate for writing");
	open( my $fh_number_by_isolate, '>', $number_by_isolate )
	  or $logger->error("Can't open output file $rscu_by_isolate for writing");
	open( my $fh_rscu_by_locus, '>', $rscu_by_locus )
	  or $logger->error("Can't open output file $rscu_by_locus for writing");
	open( my $fh_number_by_locus, '>', $number_by_locus )
	  or $logger->error("Can't open output file $number_by_isolate for writing");	  
	print $fh_rscu_by_isolate "Isolate\t@codons\n";
	print $fh_number_by_isolate "Isolate\t@codons\n";
	$progress = 0;
	foreach my $id (@list) {
		$no_output = 0;
		print $fh_rscu_by_isolate "$id$includes{$id}";
		print $fh_number_by_isolate "$id$includes{$id}";
		foreach my $codon (@codons) {
			my $aa       = $translate{$codon};
			my $expected = $total_aa_count->{$id}->{$aa} / $codons_per_aa{$aa};
			my $rscu     = $expected ? ( $total_codon_count->{$id}->{$codon} / $expected ) : 1;    #test for divide by zero
			$rscu = BIGSdb::Utils::decimal_place( $rscu, 3 );
			print $fh_rscu_by_isolate "\t$rscu";
			print $fh_number_by_isolate "\t$total_codon_count->{$id}->{$codon}";
		}
		print $fh_rscu_by_isolate "\n";
		print $fh_number_by_isolate "\n";
		$progress++;
		my $complete = 90 + int( 5 * $progress / scalar @list );                        #go up to 95%
		$self->{'jobManager'}->update_job_status( $job_id, { 'percent_complete' => $complete } );
	}
	$" = "\t";
	print $fh_rscu_by_locus "Locus\t@codons\n";
	print $fh_number_by_locus "Locus\t@codons\n";
	$progress = 0;
	foreach my $locus (@selected_fields){
		$no_output = 0;
		print $fh_rscu_by_locus "$locus";
		print $fh_number_by_locus "$locus";
		foreach my $codon (@codons) {
			my $aa       = $translate{$codon};
			my $expected = $locus_aa_count->{$locus}->{$aa} / $codons_per_aa{$aa};
			my $rscu     = $expected ? ( $locus_codon_count->{$locus}->{$codon} / $expected ) : 1;   
			$rscu = BIGSdb::Utils::decimal_place( $rscu, 3 );
			print $fh_rscu_by_locus "\t$rscu";
			print $fh_number_by_locus "\t$locus_codon_count->{$locus}->{$codon}";
		}
		print $fh_rscu_by_locus "\n";
		print $fh_number_by_locus "\n";
		$progress++;
		my $complete = 95 + int( 5 * $progress / scalar @selected_fields );                        #go up to 100%
		$self->{'jobManager'}->update_job_status( $job_id, { 'percent_complete' => $complete } );
	}
	foreach (qw ($fh_rscu_by_isolate $fh_number_by_isolate $fh_rscu_by_locus $fh_number_by_locus)){
		close $_;
	}
	if (@problem_ids) {
		$"            = ', ';
		$message_html = "<p>The following ids could not be processed (they do not exist): @problem_ids.</p>\n";
	}
	if ($no_output) {
		$message_html .= "<p>No output generated.  Please ensure that your sequences have been defined for these isolates.</p>\n";
	} else {
		$self->{'jobManager'}->update_job_output( $job_id,
			{ 'filename' => "$job_id\_rscu_by_isolate.txt", 'description' => 'Relative synonymous codon usage (RSCU) by isolate' } );
		$self->{'jobManager'}->update_job_output( $job_id,
			{ 'filename' => "$job_id\_number_by_isolate.txt", 'description' => 'Absolute frequency of codon usage by isolate' } );
		$self->{'jobManager'}->update_job_output( $job_id,
			{ 'filename' => "$job_id\_rscu_by_locus.txt", 'description' => 'Relative synonymous codon usage (RSCU) by locus' } );
		$self->{'jobManager'}->update_job_output( $job_id,
			{ 'filename' => "$job_id\_number_by_locus.txt", 'description' => 'Absolute frequency of codon usage by locus' } );	
	}
	$self->{'jobManager'}->update_job_status( $job_id, { 'message_html' => $message_html } ) if $message_html;
}

sub _get_codons {
	my @codons;
	foreach my $third (qw (C G A T)) {
		foreach my $second (qw (C G A T)) {
			foreach my $first (qw (C G A T)) {
				push @codons, "$first$second$third";
			}
		}
	}
	return @codons;
}
1;
