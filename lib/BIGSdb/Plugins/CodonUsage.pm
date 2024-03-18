#CodonUsage.pm - Codon usage plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2011-2024, University of Oxford
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
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
package BIGSdb::Plugins::CodonUsage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use List::MoreUtils qw(none uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Try::Tiny;
use constant DEFAULT_LIMIT => 500;
my %codons_per_aa = (
	A   => 4,
	C   => 2,
	D   => 2,
	E   => 2,
	F   => 2,
	G   => 4,
	H   => 2,
	I   => 3,
	K   => 2,
	L   => 6,
	M   => 1,
	N   => 2,
	P   => 4,
	Q   => 2,
	R   => 6,
	S   => 6,
	T   => 4,
	V   => 4,
	W   => 1,
	Y   => 2,
	'*' => 3
);
my %translate = (
	GCA => 'A',
	GCC => 'A',
	GCG => 'A',
	GCT => 'A',
	TGC => 'C',
	TGT => 'C',
	GAC => 'D',
	GAT => 'D',
	GAA => 'E',
	GAG => 'E',
	TTC => 'F',
	TTT => 'F',
	GGA => 'G',
	GGC => 'G',
	GGG => 'G',
	GGT => 'G',
	CAC => 'H',
	CAT => 'H',
	ATA => 'I',
	ATC => 'I',
	ATT => 'I',
	AAA => 'K',
	AAG => 'K',
	CTA => 'L',
	CTC => 'L',
	CTG => 'L',
	CTT => 'L',
	TTA => 'L',
	TTG => 'L',
	ATG => 'M',
	AAC => 'N',
	AAT => 'N',
	CCA => 'P',
	CCC => 'P',
	CCG => 'P',
	CCT => 'P',
	CAA => 'Q',
	CAG => 'Q',
	AGA => 'R',
	AGG => 'R',
	CGA => 'R',
	CGC => 'R',
	CGG => 'R',
	CGT => 'R',
	AGC => 'S',
	AGT => 'S',
	TCA => 'S',
	TCC => 'S',
	TCG => 'S',
	TCT => 'S',
	ACA => 'T',
	ACC => 'T',
	ACG => 'T',
	ACT => 'T',
	GTA => 'V',
	GTC => 'V',
	GTG => 'V',
	GTT => 'V',
	TGG => 'W',
	TAC => 'Y',
	TAT => 'Y',
	TAA => '*',
	TAG => '*',
	TGA => '*'
);

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name    => 'Codon Usage',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			}
		],
		description      => 'Determine codon usage for specified loci for an isolate database query',
		full_description => 'The codon usage plugin calculates the absolute and relative synonymous codon usage by '
		  . 'isolate and by locus for any dataset or the whole database. Specific loci or the loci that are members '
		  . 'of a particular scheme can be chosen for analysis.',
		category    => 'Analysis',
		buttontext  => 'Codons',
		menutext    => 'Codon usage',
		module      => 'CodonUsage',
		url         => "$self->{'config'}->{'doclink'}/data_analysis/codon_usage.html",
		version     => '1.3.0',
		dbtype      => 'isolates',
		section     => 'analysis,postquery',
		input       => 'query',
		help        => 'tooltips',
		requires    => 'offline_jobs,js_tree',
		system_flag => 'CodonUsage',
		order       => 13,
		image       => '/images/plugins/CodonUsage/screenshot.png'
	);
	return \%att;
}

sub get_initiation_values {
	return { 'jQuery.jstree' => 1, 'jQuery.multiselect' => 1 };
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 1, query_field => 0 };
	return;
}

sub get_plugin_javascript {
	my $js = << "END";
\$(document).ready(function(){ 
	\$('#locus').multiselect({
 		classes: 'filter',
 		menuHeight: 250,
 		menuWidth: 400,
 		selectedList: 8
  	}).multiselectfilter();
}); 
END
	return $js;
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Codon usage analysis</h1>);
	if ( $q->param('submit') ) {
		my $loci_selected = $self->get_selected_loci;
		my ( $pasted_cleaned_loci, $invalid_loci ) = $self->get_loci_from_pasted_list;
		$q->delete('locus');
		push @$loci_selected, @$pasted_cleaned_loci;
		@$loci_selected = uniq @$loci_selected;
		$self->add_scheme_loci($loci_selected);
		if (@$invalid_loci) {
			local $" = q(, );
			$self->print_bad_status(
				{ message => qq(The following loci in your pasted list are invalid: @$invalid_loci.) } );
		} elsif ( !@$loci_selected ) {
			$self->print_bad_status( { message => q(You must select one or more loci or schemes.) } );
		} else {
			$self->set_scheme_param;
			my $params = $q->Vars;
			my @list   = split /[\r\n]+/x, $q->param('list');
			@list = uniq @list;
			if ( !@list ) {
				my $qry     = "SELECT id FROM $self->{'system'}->{'view'} ORDER BY id";
				my $id_list = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
				@list = @$id_list;
			}
			$q->delete('list');
			$params->{'set_id'} = $self->get_set_id;
			$params->{'curate'} = 1 if $self->{'curate'};
			my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
			my $job_id    = $self->{'jobManager'}->add_job(
				{
					dbase_config => $self->{'instance'},
					ip_address   => $q->remote_host,
					module       => 'CodonUsage',
					parameters   => $params,
					username     => $self->{'username'},
					email        => $user_info->{'email'},
					isolates     => \@list,
					loci         => $loci_selected
				}
			);
			say $self->get_job_redirect($job_id);
			return;
		}
	}
	my $limit = $self->{'system'}->{'codon_usage_limit'} // DEFAULT_LIMIT;
	say q[<div class="box" id="queryform"><p>This plugin will analyse the codon usage for individual loci ]
	  . q[and overall for an isolate.  Only loci that have a corresponding database containing sequences, ]
	  . q[or with sequences tagged, can be included.  It is important to note that correct identification ]
	  . q[of codons can only be achieved for loci for which the correct ORF has been set (if they are not ]
	  . q[in reading frame 1).  Partial sequnces from the sequence bin will not be analysed. Please check ]
	  . qq[the loci that you would like to include. Output is limited to $limit records.</p>];
	$self->_print_interface;
	say q(</div>);
	return;
}

sub _print_interface {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $list       = $self->get_id_list( 'id', $query_file );
	say $q->start_form;
	say q(<div class="flex_container" style="justify-content:left">);
	$self->print_id_fieldset( { fieldname => 'id', list => $list } );
	$self->print_isolates_locus_fieldset( { locus_paste_list => 1, no_all_none => 1 } );
	$self->print_scheme_fieldset;
	say q(<fieldset style="float:left"><legend>Sequence retrieval</legend>);
	say q(<p>If both allele designations and tagged sequences<br />)
	  . q(exist for a locus, choose how you want these handled: );
	say $self->get_tooltip( q(Sequence retrieval - Peptide loci will only be retrieved from the )
		  . q(sequence bin (as nucleotide sequences).) );
	say q(</p><ul><li>);
	my %labels = (
		seqbin             => 'Use sequences tagged from the bin',
		allele_designation => 'Use allele sequence retrieved from external database'
	);
	say $q->radio_group(
		-name      => 'chooseseq',
		-values    => [ 'seqbin', 'allele_designation' ],
		-labels    => \%labels,
		-linebreak => 'true'
	);
	say q(</li><li style="margin-top:0.5em">);
	say $q->checkbox(
		-name    => 'ignore_seqflags',
		-label   => 'Do not include sequences with problem flagged (defined alleles will still be used)',
		-checked => 'checked'
	);
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'ignore_incomplete',
		-label   => 'Do not include incomplete sequences',
		-checked => 'checked'
	);
	say q(</li><li>);
	say q(</ul></fieldset>);
	say q(<fieldset style="float:left"><legend>Codons</legend>);
	say q(<p>Select codon order:</p>);
	say $q->radio_group(
		-name      => 'codonorder',
		-values    => [ 'alphabetical', 'cg_ending_first' ],
		-labels    => { cg_ending_first => 'C or G ending codons first' },
		-linebreak => 'true'
	);
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1 } );
	say q(<div style="clear:both"></div>);
	my $set_id = $self->get_set_id;
	$q->param( set_id => $set_id );
	say $q->hidden($_) foreach qw (db page name query_file scheme_id set_id list_file datatype);
	say q(</div>);
	say $q->end_form;
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	$self->set_offline_view($params);
	my $rscu_by_isolate   = "$self->{'config'}->{'tmp_dir'}/${job_id}_rscu_by_isolate.txt";
	my $number_by_isolate = "$self->{'config'}->{'tmp_dir'}/${job_id}_number_by_isolate.txt";
	my $rscu_by_locus     = "$self->{'config'}->{'tmp_dir'}/${job_id}_rscu_by_locus.txt";
	my $number_by_locus   = "$self->{'config'}->{'tmp_dir'}/${job_id}_number_by_locus.txt";
	my $start             = 1;
	my $no_output         = 1;
	my $list              = $self->{'jobManager'}->get_job_isolates($job_id);
	my $loci              = $self->{'jobManager'}->get_job_loci($job_id);
	my $selected_loci     = $self->order_loci($loci);
	my $limit             = $self->{'system'}->{'codon_usage_limit'} // DEFAULT_LIMIT;

	if ( @$list > $limit ) {
		my $message_html =
		  qq(<p class="statusbad">Please note that output is limited to the first $limit records.</p>\n);
		$self->{'jobManager'}->update_job_status( $job_id, { message_html => $message_html } );
	}
	my $data = $self->_calculate( $job_id, $selected_loci, $list, $params );
	my ( $bad_ids, $locus_codon_count, $locus_aa_count, $total_codon_count, $total_aa_count ) =
	  @{$data}{qw(bad_ids locus_codon_count locus_aa_count total_codon_count total_aa_count)};
	my $message_html;
	local $" = "\t";
	my @codons = $self->_get_codons;
	if ( $params->{'codonorder'} eq 'alphabetical' ) {
		@codons = sort @codons;
	}
	open( my $fh_rscu_by_isolate, '>:encoding(utf8)', $rscu_by_isolate )
	  or $logger->error("Can't open output file $rscu_by_isolate for writing");
	open( my $fh_number_by_isolate, '>:encoding(utf8)', $number_by_isolate )
	  or $logger->error("Can't open output file $rscu_by_isolate for writing");
	open( my $fh_rscu_by_locus, '>:encoding(utf8)', $rscu_by_locus )
	  or $logger->error("Can't open output file $rscu_by_locus for writing");
	open( my $fh_number_by_locus, '>:encoding(utf8)', $number_by_locus )
	  or $logger->error("Can't open output file $number_by_isolate for writing");
	print $fh_rscu_by_isolate "Isolate\t@codons\n";
	print $fh_number_by_isolate "Isolate\t@codons\n";
	my $progress = 0;
	my $count    = 0;

	foreach my $id (@$list) {
		last if $count == $limit;
		$count++;
		next if $bad_ids->{$id};
		$no_output = 0;
		print $fh_rscu_by_isolate "$id";
		print $fh_number_by_isolate "$id";
		foreach my $codon (@codons) {
			$total_codon_count->{$id}->{$codon} ||= 0;
			my $aa = $translate{$codon};
			$total_aa_count->{$id}->{$aa} ||= 0;
			my $expected = $total_aa_count->{$id}->{$aa} / $codons_per_aa{$aa};
			my $rscu     = $expected ? ( $total_codon_count->{$id}->{$codon} / $expected ) : 1; #test for divide by zero
			$rscu = BIGSdb::Utils::decimal_place( $rscu, 3 );
			print $fh_rscu_by_isolate "\t$rscu";
			print $fh_number_by_isolate "\t$total_codon_count->{$id}->{$codon}";
		}
		print $fh_rscu_by_isolate "\n";
		print $fh_number_by_isolate "\n";
		$progress++;
		my $complete = 90 + int( 5 * $progress / @$list );    #go up to 95%
		$self->{'jobManager'}->update_job_status( $job_id, { 'percent_complete' => $complete } );
	}
	local $" = "\t";
	print $fh_rscu_by_locus "Locus\t@codons\n";
	print $fh_number_by_locus "Locus\t@codons\n";
	$progress = 0;
	my $set_id = $self->get_set_id;
	foreach my $locus (@$selected_loci) {
		my $display_locus = $self->clean_locus( $locus, { text_output => 1 } );
		$no_output = 0;
		print $fh_rscu_by_locus "$display_locus";
		print $fh_number_by_locus "$display_locus";
		foreach my $codon (@codons) {
			my $aa       = $translate{$codon};
			my $expected = ( $locus_aa_count->{$locus}->{$aa} // 0 ) / $codons_per_aa{$aa};
			my $rscu     = $expected ? ( $locus_codon_count->{$locus}->{$codon} / $expected ) : 1;
			$rscu = BIGSdb::Utils::decimal_place( $rscu, 3 );
			print $fh_rscu_by_locus "\t$rscu";
			print $fh_number_by_locus "\t" . ( $locus_codon_count->{$locus}->{$codon} // 0 );
		}
		print $fh_rscu_by_locus "\n";
		print $fh_number_by_locus "\n";
		$progress++;
		my $complete = 95 + int( 5 * $progress / scalar @$selected_loci );    #go up to 100%
		$self->{'jobManager'}->update_job_status( $job_id, { 'percent_complete' => $complete } );
	}
	close $fh_rscu_by_isolate;
	close $fh_number_by_isolate;
	close $fh_rscu_by_locus;
	close $fh_number_by_locus;
	if ( keys %$bad_ids ) {
		local $" = ', ';
		my @bad_ids = sort keys %$bad_ids;
		$message_html = qq(<p>The following ids could not be processed (they do not exist): @bad_ids</p>\n);
	}
	if ($no_output) {
		$message_html .= q(<p>No output generated.  Please ensure that your )
		  . qq(sequences have been defined for these isolates.</p>\n);
	} else {
		my %file_desc = (
			rscu_by_isolate   => 'Relative synonymous codon usage (RSCU) by isolate',
			number_by_isolate => 'Absolute frequency of codon usage by isolate',
			rscu_by_locus     => 'Relative synonymous codon usage (RSCU) by locus',
			number_by_locus   => 'Absolute frequency of codon usage by locus'
		);
		my $i = 0;
		foreach my $file ( sort keys %file_desc ) {
			$self->{'jobManager'}->update_job_output( $job_id,
				{ filename => "${job_id}_$file.txt", description => "0${i}_$file_desc{$file} (text)" } );
			$i++;
		}
		foreach my $file ( sort keys %file_desc ) {
			my $excel = BIGSdb::Utils::text2excel(
				"$self->{'config'}->{'tmp_dir'}/${job_id}_$file.txt",
				{ tmp_dir => $self->{'config'}->{'secure_tmp_dir'} }
			);
			if ( -e $excel ) {
				$self->{'jobManager'}->update_job_output(
					$job_id,
					{
						filename    => "${job_id}_$file.xlsx",
						description => "0${i}_$file_desc{$file} (Excel)"
					}
				);
				$i++;
			}
		}
	}
	$self->{'jobManager'}->update_job_status( $job_id, { 'message_html' => $message_html } ) if $message_html;
	return;
}

sub _calculate {
	my ( $self, $job_id, $loci, $ids, $params ) = @_;
	my $progress = 0;
	my $limit    = $self->{'system'}->{'codon_usage_limit'} // DEFAULT_LIMIT;
	my %bad_ids;
	my ( $locus_codon_count, $locus_aa_count, $total_codon_count, $total_aa_count );
	foreach my $locus_name (@$loci) {
		my $locus;
		my $locus_info = $self->{'datastore'}->get_locus_info($locus_name);
		try {
			$locus = $self->{'datastore'}->get_locus($locus_name);
		} catch {
			if ( $_->isa('BIGSdb::Exception::Data') ) {
				$logger->warn("Invalid locus '$locus_name' passed.");
			} else {
				$logger->logdie($_);
			}
		};
		my $temp      = BIGSdb::Utils::get_random();
		my $temp_file = "$self->{'config'}->{secure_tmp_dir}/$temp.txt";
		my $cusp_file = "$self->{'config'}->{secure_tmp_dir}/$temp.cusp";
		local $" = '|';
		my $count = 0;
		foreach my $id (@$ids) {
			last if $count == $limit;
			$count++;
			next if $bad_ids{$id};
			my $id_exists =
			  $self->{'datastore'}->run_query( "SELECT EXISTS(SELECT * FROM $self->{'system'}->{'view'} WHERE id=?)",
				$id, { cache => 'CodonUsage::run_job_id_exists' } );
			if ( !$id_exists ) {
				$bad_ids{$id} = 1;
				next;
			}
			my $allele_ids = $self->{'datastore'}->get_allele_ids( $id, $locus_name );
			my $allele_seq;
			if ( $locus_info->{'data_type'} eq 'DNA' ) {
				foreach my $allele_id (@$allele_ids) {
					try {
						my $seq = $locus->get_allele_sequence($allele_id);
						$allele_seq .= BIGSdb::Utils::chop_seq( $$seq, $locus_info->{'orf'} // 1 );
					} catch {

						#do nothing
					};
				}
			}
			my $seqbin_seq;
			my $ignore_seqflag;
			if ( $params->{'ignore_seqflags'} ) {
				$ignore_seqflag = 'AND flag IS NULL';
			}
			my $data = $self->{'datastore'}->run_query(
				'SELECT a.seqbin_id,a.start_pos,a.end_pos,a.reverse FROM allele_sequences a LEFT JOIN '
				  . 'sequence_flags f ON a.id=f.id WHERE (a.isolate_id,a.locus)=(?,?) AND complete '
				  . "$ignore_seqflag ORDER BY a.datestamp LIMIT 1",
				[ $id, $locus_name ],
				{ fetch => 'all_arrayref', slice => {}, cache => 'CodonUsage::run_job_seqbin' }
			);
			foreach my $allele_sequence (@$data) {
				my $seq_ref = $self->{'contigManager'}->get_contig_fragment(
					{
						seqbin_id => $allele_sequence->{'seqbin_id'},
						start     => $allele_sequence->{'start_pos'},
						end       => $allele_sequence->{'end_pos'},
						reverse   => $allele_sequence->{'reverse'}
					}
				);
				$seqbin_seq .= BIGSdb::Utils::chop_seq( $seq_ref->{'seq'}, $locus_info->{'orf'} || 1 );
			}
			my $seq;
			if ( $allele_seq && $seqbin_seq ) {
				$seq = $params->{'chooseseq'} eq 'seqbin' ? $seqbin_seq : $allele_seq;
			} elsif ( $allele_seq && !$seqbin_seq ) {
				$seq = $allele_seq;
			} elsif ($seqbin_seq) {
				$seq = $seqbin_seq;
			} else {    #no sequence
			}
			$seq //= '';
			open( my $fh_cusp_in, '>', "$temp_file" ) or $logger->error("could not open temp file $temp_file");
			print $fh_cusp_in ">$id\n$seq\n";
			close $fh_cusp_in;
			system( "$self->{'config'}->{'emboss_path'}/cusp -sequence $temp_file "
				  . "-outfile $cusp_file -warning false 2>/dev/null" );
			if ( -e $cusp_file ) {
				open( my $fh_cusp, '<', $cusp_file ) || $logger->error("Can't open $cusp_file for reading");
				while (<$fh_cusp>) {
					next if $_ =~ /^\#/x || $_ eq q();
					my ( $codon, $aa, undef, undef, $number ) = split /\s+/x, $_;
					$number ||= 0;
					$locus_codon_count->{$locus_name}->{$codon} += $number;
					$locus_aa_count->{$locus_name}->{$aa}       += $number;
					$total_codon_count->{$id}->{$codon}         += $number;
					$total_aa_count->{$id}->{$aa}               += $number;
				}
				close $fh_cusp;
			}
			unlink $cusp_file, $temp_file;
		}
		$progress++;
		my $complete = int( 90 * $progress / @$loci );    #go up to 90%
		$self->{'jobManager'}->update_job_status( $job_id, { 'percent_complete' => $complete } );
	}
	return {
		bad_ids           => \%bad_ids,
		locus_codon_count => $locus_codon_count,
		locus_aa_count    => $locus_aa_count,
		total_codon_count => $total_codon_count,
		total_aa_count    => $total_aa_count
	};
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
