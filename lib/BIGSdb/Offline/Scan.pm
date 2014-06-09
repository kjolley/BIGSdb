#Written by Keith Jolley
#Copyright (c) 2010-2014, University of Oxford
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
package BIGSdb::Offline::Scan;
use strict;
use warnings;
no warnings 'io';    #Prevent false warning message about STDOUT being reopened.
use parent qw(BIGSdb::Offline::Script BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Scan');
use List::MoreUtils qw( any none);
use Error qw(:try);
use BIGSdb::Page qw(SEQ_METHODS SEQ_FLAGS LOCUS_PATTERN);

sub blast {
	my ( $self, $params, $locus, $isolate_id, $file_prefix, $locus_prefix ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $program;
	if ( $locus_info->{'data_type'} eq 'DNA' ) {
		$program = $params->{'tblastx'} ? 'tblastx' : 'blastn';
	} else {
		$program = 'blastx';
	}
	my $temp_infile  = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_file.txt";
	my $temp_outfile = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_outfile.txt";
	my $clean_locus  = $locus;
	$clean_locus =~ s/\W/_/g;
	$clean_locus = $1 if $clean_locus =~ /(\w*)/;    #avoid taint check
	my $temp_fastafile = "$self->{'config'}->{'secure_tmp_dir'}/$locus_prefix\_fastafile_$clean_locus.txt";
	$temp_fastafile =~ s/\\/\\\\/g;
	$temp_fastafile =~ s/'/__prime__/g;
	my $outfile_url = "$file_prefix\_outfile.txt";

	#create fasta index
	#only need to create this once for each locus (per run), so check if file exists first
	#this should then be deleted by the calling function!
	if ( !-e $temp_fastafile ) {
		open( my $fasta_fh, '>', $temp_fastafile ) or $logger->error("Can't open temp file $temp_fastafile for writing");
		if ( $locus_info->{'dbase_name'} ) {
			my $ok = 1;
			try {
				my $seqs_ref = $self->{'datastore'}->get_locus($locus)->get_all_sequences;
				return if !keys %$seqs_ref;
				foreach ( keys %$seqs_ref ) {
					next if !length $seqs_ref->{$_};
					say $fasta_fh ">$_\n$seqs_ref->{$_}";
				}
			}
			catch BIGSdb::DatabaseConfigurationException with {
				$ok = 0;
			};
			return if !$ok;
		} else {
			return if !$locus_info->{'reference_sequence'};
			say $fasta_fh ">ref\n$locus_info->{'reference_sequence'}";
		}
		close $fasta_fh;
		my $dbtype = $locus_info->{'data_type'} eq 'DNA' ? 'nucl' : 'prot';
		system( "$self->{'config'}->{'blast+_path'}/makeblastdb", ( -in => $temp_fastafile, -logfile => '/dev/null', -dbtype => $dbtype ) );
	}

	#create query fasta file
	#only need to create this once for each isolate (per run), so check if file exists first
	#this should then be deleted by the calling function!
	my $seq_count = 0;
	if ( !-e $temp_infile ) {
		my $experiment      = $params->{'experiment_list'};
		my $distinct_clause = $experiment ? ' DISTINCT' : '';
		my $qry             = "SELECT$distinct_clause sequence_bin.id,sequence FROM sequence_bin ";
		$qry .= "LEFT JOIN experiment_sequences ON sequence_bin.id=seqbin_id " if $experiment;
		$qry .= "WHERE sequence_bin.isolate_id=?";
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
		if ($experiment) {
			if ( !BIGSdb::Utils::is_int($experiment) ) {
				$logger->error("Invalid experiment $experiment");
				return;
			}
			$qry .= " AND experiment_id=?";
			push @criteria, $experiment;
		}
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute(@criteria) };
		$logger->error($@) if $@;
		open( my $infile_fh, '>', $temp_infile ) or $logger->error("Can't open temp file $temp_infile for writing");
		while ( my $seq_data = $sql->fetchrow_arrayref ) {
			$seq_count++;
			say $infile_fh ">$seq_data->[0]\n$seq_data->[1]";
		}
		close $infile_fh;
		open( my $seqcount_fh, '>', "$temp_infile\_seqcount" ) or $logger->error("Can't open temp file $temp_infile\_seqcount for writing");
		say $seqcount_fh $seq_count;
		close $seqcount_fh;
	} else {
		open( my $seqcount_fh, '<', "$temp_infile\_seqcount" ) or $logger->error("Can't open temp file $temp_infile\_seqcount for reading");
		$seq_count = $1 if <$seqcount_fh> =~ /(\d+)/;
		close $seqcount_fh;
	}
	my ( $pcr_products, $probe_matches );
	if ( $locus_info->{'pcr_filter'} && $params->{'pcr_filter'} ) {
		if ( $self->{'config'}->{'ipcress_path'} ) {
			$pcr_products = $self->_simulate_PCR( $temp_infile, $locus );
			if ( ref $pcr_products ne 'ARRAY' ) {
				$logger->error("PCR filter is set for locus $locus but no reactions are defined.");
				return;
			}
			return if !@$pcr_products;
		} else {
			$logger->error("Ipcress path is not set in bigsdb.conf.  PCR simulation can not be done so whole genome will be used.");
		}
	}
	if ( $locus_info->{'probe_filter'} && $params->{'probe_filter'} ) {
		$probe_matches = $self->_simulate_hybridization( $temp_infile, $locus );
		if ( ref $probe_matches ne 'ARRAY' ) {
			$logger->error("Probe filter is set for locus $locus but no probes are defined.");
			return;
		}
		return if !@$probe_matches;
	}
	$self->{'db'}->commit;    #prevent idle in transaction table locks
	if ( -e $temp_fastafile && !-z $temp_fastafile ) {
		my $blastn_word_size = ( defined $params->{'word_size'} && $params->{'word_size'} =~ /(\d+)/ ) ? $1 : 15;
		my $word_size = $program eq 'blastn' ? $blastn_word_size : 3;
		my $blast_threads = $self->{'config'}->{'blast_threads'} || 1;
		my $filter = $program eq 'blastn' ? 'dust' : 'seg';
		my %params = (
			-num_threads     => $blast_threads,
			-max_target_seqs => 1000,
			-word_size       => $word_size,
			-db              => $temp_fastafile,
			-query           => $temp_infile,
			-out             => $temp_outfile,
			-outfmt          => 6,
			-$filter         => 'no'
		);
		$params{'-comp_based_stats'} = 0 if $program ne 'blastn';    #Will not return some matches with low-complexity regions otherwise.
		system( "$self->{'config'}->{'blast+_path'}/$program", %params );
		my ( $exact_matches, $matched_regions, $partial_matches );
		my $pcr_filter   = !$params->{'pcr_filter'}   ? 0 : $locus_info->{'pcr_filter'};
		my $probe_filter = !$params->{'probe_filter'} ? 0 : $locus_info->{'probe_filter'};

		if ( -e "$self->{'config'}->{'secure_tmp_dir'}/$outfile_url" ) {
			( $exact_matches, $matched_regions ) = $self->_parse_blast_exact(
				{
					locus         => $locus,
					blast_file    => $outfile_url,
					pcr_filter    => $pcr_filter,
					pcr_products  => $pcr_products,
					probe_filter  => $probe_filter,
					probe_matches => $probe_matches
				}
			);
			if (
				( !@$exact_matches || $params->{'partial_when_exact'} )
				|| (   $locus_info->{'pcr_filter'}
					&& !$params->{'pcr_filter'}
					&& $locus_info->{'probe_filter'}
					&& !$params->{'probe_filter'} )
			  )
			{
				$partial_matches = $self->_parse_blast_partial(
					{
						params                => $params,
						locus                 => $locus,
						exact_matched_regions => $matched_regions,
						blast_file            => $outfile_url,
						pcr_filter            => $pcr_filter,
						pcr_products          => $pcr_products,
						probe_filter          => $probe_filter,
						probe_matches         => $probe_matches
					}
				);
			}
		} else {
			$logger->debug("$self->{'config'}->{'secure_tmp_dir'}/$outfile_url does not exist");
		}
		return ( $exact_matches, $partial_matches );
	}

	#Calling function should delete working files.  This is not done here as they can be re-used
	#if multiple loci are being scanned for the same isolate.
	return;
}

sub run_script {
	my ($self)  = @_;
	my $params  = $self->{'params'};
	my $options = $self->{'options'};
	my @isolate_ids = split( "\0", $params->{'isolate_id'} );
	throw BIGSdb::DataException("Invalid isolate_ids passed") if !@isolate_ids;
	my $loci = $self->{'options'}->{'loci'};
	throw BIGSdb::DataException("Invalid loci passed") if ref $loci ne 'ARRAY';
	my $labels = $self->{'options'}->{'labels'};
	$self->{'system'}->{'script_name'} = $self->{'options'}->{'script_name'};
	my ( @js, @js2, @js3, @js4 );
	my $show_key;
	my $td = 1;
	my $new_alleles;
	my $new_seqs_found;
	my %isolates_to_tag;
	my $last_id_checked;
	my $match_limit_reached;
	my $out_of_time;
	my $start_time   = time;
	my $locus_prefix = BIGSdb::Utils::get_random();
	my @isolates_in_project;
	my $file_prefix = BIGSdb::Utils::get_random();

	if ( $options->{'project_id'} && BIGSdb::Utils::is_int( $options->{'project_id'} ) ) {
		my $list_ref =
		  $self->{'datastore'}->run_list_query( "SELECT isolate_id FROM project_members WHERE project_id=?", $options->{'project_id'} );
		@isolates_in_project = @$list_ref;
	}
	my $match        = 0;
	my $seq_filename = $self->{'config'}->{'tmp_dir'} . "/$options->{'scan_job'}\_unique_sequences.txt";
	open( my $seqs_fh, '>', $seq_filename ) or $logger->error("Can't open $seq_filename for writing");
	say $seqs_fh "locus\tallele_id\tstatus\tsequence";
	close $seqs_fh;
	$self->_write_status( $options->{'scan_job'}, "start_time:$start_time", { reset => 1 } );
	$self->_write_match( $options->{'scan_job'}, undef, { reset => 1 } );
	$logger->info("Scan $self->{'instance'}:$options->{'scan_job'} ($options->{'curator_name'}) started");
	my $table_file = "$self->{'config'}->{'secure_tmp_dir'}/$options->{'scan_job'}_table.html";
	unlink $table_file;    #delete file if scan restarted

	foreach my $isolate_id (@isolate_ids) {
		next if $options->{'project_id'} && none { $isolate_id == $_ } @isolates_in_project;
		if ( $match >= $options->{'limit'} ) {
			$match_limit_reached = 1;
			$self->_write_status( $options->{'scan_job'}, "match_limit_reached:1" );
			$self->_write_status( $options->{'scan_job'}, "last_isolate:$isolate_id" );
			last;
		}
		if ( time >= $start_time + $options->{'time_limit'} ) {
			$out_of_time = 1;
			$self->_write_status( $options->{'scan_job'}, "time_limit_reached:1" );
			$self->_write_status( $options->{'scan_job'}, "last_isolate:$isolate_id" );
			last;
		}
		my $status = $self->_read_status( $options->{'scan_job'} );
		last if $status->{'request_stop'};
		next if $isolate_id eq '' || $isolate_id eq 'all';
		next if !$self->is_allowed_to_view_isolate($isolate_id);
		my %locus_checked;
		my $pattern = LOCUS_PATTERN;
		foreach my $locus_id (@$loci) {
			$status = $self->_read_status( $options->{'scan_job'} );
			last if $status->{'request_stop'};
			my $row_buffer;
			my $locus = $locus_id =~ /$pattern/ ? $1 : undef;
			if ( !defined $locus ) {
				$logger->error("Locus name not extracted: Input was '$locus_id'");
				next;
			}
			next if $locus_checked{$locus};    #prevent multiple checking when locus selected individually and as part of scheme.
			$locus_checked{$locus} = 1;
			if ( $match >= $options->{'limit'} ) {
				$match_limit_reached = 1;
				$self->_write_status( $options->{'scan_job'}, "match_limit_reached:1" );
				$self->_write_status( $options->{'scan_job'}, "last_isolate:$isolate_id" );
				last;
			}
			if ( time >= $start_time + $options->{'time_limit'} ) {
				$out_of_time = 1;
				$self->_write_status( $options->{'scan_job'}, "time_limit_reached:1" );
				$self->_write_status( $options->{'scan_job'}, "last_isolate:$isolate_id" );
				last;
			}
			my $existing_allele_ids = $self->{'datastore'}->get_allele_ids( $isolate_id, $locus );
			next if !$params->{'rescan_alleles'} && @$existing_allele_ids;
			next if !$params->{'rescan_seqs'} && $self->{'datastore'}->allele_sequence_exists( $isolate_id, $locus );
			my ( $exact_matches, $partial_matches ) = $self->blast( $params, $locus, $isolate_id, $file_prefix, $locus_prefix );
			my $off_end;
			my $i = 1;
			my $new_designation;

			if ( ref $exact_matches && @$exact_matches ) {
				my %new_matches;
				foreach my $match (@$exact_matches) {
					my $match_key = "$match->{'seqbin_id'}\|$match->{'predicted_start'}|$match->{'predicted_end'}";
					( my $buffer, $off_end, $new_designation ) = $self->_get_row(
						{
							isolate_id => $isolate_id,
							labels     => $labels,
							locus      => $locus,
							id         => $i,
							match      => $match,
							td         => $td,
							exact      => 1,
							js         => \@js,
							js2        => \@js2,
							js3        => \@js3,
							js4        => \@js4,
							warning    => $new_matches{$match_key}
						}
					);
					$row_buffer .= $buffer;
					$new_matches{$match_key} = 1;
					$show_key = 1 if $off_end;
					$td = $td == 1 ? 2 : 1;
					$self->_write_match( $options->{'scan_job'}, "$isolate_id:$locus:$i" );
					$i++;
				}
				$isolates_to_tag{$isolate_id} = 1;
			}
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			if ( ref $partial_matches && @$partial_matches && ( !@$exact_matches || $params->{'partial_when_exact'} ) ) {
				my %new_matches;
				foreach my $match (@$partial_matches) {
					my $match_key = "$match->{'seqbin_id'}\|$match->{'predicted_start'}|$match->{'predicted_end'}";
					( my $buffer, $off_end, $new_designation ) = $self->_get_row(
						{
							isolate_id => $isolate_id,
							labels     => $labels,
							locus      => $locus,
							id         => $i,
							match      => $match,
							td         => $td,
							exact      => 0,
							js         => \@js,
							js2        => \@js2,
							js3        => \@js3,
							js4        => \@js4,
							warning    => $new_matches{$match_key}
						}
					);
					$row_buffer .= $buffer;
					$new_matches{$match_key} = 1;
					if ($off_end) {
						$show_key = 1;
					} else {
						my $seq = $self->extract_seq_from_match($match);
						$new_seqs_found = 1;
						my $new = 1;
						foreach ( @{ $new_alleles->{$locus} } ) {
							if ( $seq eq $_ ) {
								$new = 0;
							}
						}
						if ($new) {
							push @{ $new_alleles->{$locus} }, $seq;
							open( my $seqs_fh, '>>', $seq_filename ) or $logger->error("Can't open $seq_filename for appending");
							say $seqs_fh "$locus\t\tWGS: automated extract\t$seq";
							close $seqs_fh;
						}
					}
					$td = $td == 1 ? 2 : 1;
					$self->_write_match( $options->{'scan_job'}, "$isolate_id:$locus:$i" );
					$i++;
				}
				$isolates_to_tag{$isolate_id} = 1;
			} elsif ( $params->{'mark_missing'}
				&& !( ref $exact_matches   && @$exact_matches )
				&& !( ref $partial_matches && @$partial_matches ) )
			{
				$row_buffer = $self->_get_missing_row( $isolate_id, $labels, $locus, \@js, \@js2, );
				if ($row_buffer) {
					$new_designation              = 1;
					$td                           = $td == 1 ? 2 : 1;
					$isolates_to_tag{$isolate_id} = 1;
					$self->_write_match( $options->{'scan_job'}, "$isolate_id:$locus:$i" );
				}
			}
			if ($row_buffer) {
				open( my $fh, '>>', $table_file ) || $logger->error("Can't open $table_file for appending");
				say $fh $row_buffer;
				close $fh;
			}
			$match++ if $new_designation;
		}

		#delete isolate working files
		my @files = glob("$self->{'config'}->{'secure_tmp_dir'}/*$file_prefix*");
		foreach (@files) { unlink $1 if /^(.*BIGSdb.*)$/ }
		$last_id_checked = $isolate_id;
	}

	#delete locus working files
	my @files = glob("$self->{'config'}->{'secure_tmp_dir'}/*$locus_prefix*");
	foreach (@files) { unlink $1 if /^(.*BIGSdb.*)$/ }
	if ($match) {
		open( my $fh, '>>', $table_file ) || $logger->error("Can't open $table_file for appending");
		local $" = ';';
		say $fh "<tr class=\"td\">" . ( "<td></td>" x 14 ) . "<td>";
		say $fh "<input type=\"button\" value=\"All\" onclick='@js' class=\"smallbutton\" />"   if @js;
		say $fh "<input type=\"button\" value=\"None\" onclick='@js2' class=\"smallbutton\" />" if @js2;
		say $fh "</td><td>";
		say $fh "<input type=\"button\" value=\"All\" onclick='@js3' class=\"smallbutton\" />"  if @js3;
		say $fh "<input type=\"button\" value=\"None\" onclick='@js4' class=\"smallbutton\" />" if @js4;
		say $fh "</td><td></td></tr>";
		close $fh;
	}
	my $stop_time = time;
	$self->_write_status( $options->{'scan_job'}, "allele_off_contig:1" ) if $show_key;
	$self->_write_status( $options->{'scan_job'}, "new_matches:$match" );
	$self->_write_status( $options->{'scan_job'}, "new_seqs_found:1" )    if $new_seqs_found;
	my @isolates_to_tag = sort { $a <=> $b } keys %isolates_to_tag;
	local $" = ',';
	$self->_write_status( $options->{'scan_job'}, "tag_isolates:@isolates_to_tag" );
	$self->_write_status( $options->{'scan_job'}, "loci:@$loci" );
	$self->_write_status( $options->{'scan_job'}, "stop_time:$stop_time" );
	$logger->info("Scan $self->{'instance'}:$options->{'scan_job'} ($options->{'curator_name'}) finished");
	return;
}

sub extract_seq_from_match {
	my ( $self, $match ) = @_;
	my $length = $match->{'predicted_end'} - $match->{'predicted_start'} + 1;
	my $seq =
	  $self->{'datastore'}
	  ->run_query( "SELECT substring(sequence from $match->{'predicted_start'} for $length) FROM sequence_bin WHERE id=?",
		$match->{'seqbin_id'} );
	$seq = BIGSdb::Utils::reverse_complement($seq) if $match->{'reverse'};
	$seq = uc($seq);
	return $seq;
}

sub _get_row {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $labels, $locus, $id, $match, $td, $exact, $js, $js2, $js3, $js4, $warning ) =
	  @{$args}{qw (isolate_id labels locus id match td exact js js2 js3 js4 warning)};
	my $q      = $self->{'cgi'};
	my $params = $self->{'params'};
	my $class  = $exact ? '' : " class=\"partialmatch\"";
	my $tooltip;
	my $new_designation = 0;
	my $existing_alleles = $self->{'datastore'}->get_allele_ids( $isolate_id, $locus );

	if ( @$existing_alleles && ( any { $match->{'allele'} eq $_ } @$existing_alleles ) ) {
		$tooltip = $self->_get_designation_tooltip( $isolate_id, $locus, 'existing' );
	} elsif (
		$match->{'allele'} && @$existing_alleles && (
			none {
				$match->{'allele'} eq $_;
			}
			@$existing_alleles
		)
	  )
	{
		$tooltip = $self->_get_designation_tooltip( $isolate_id, $locus, 'clashing' );
	}
	my $seqbin_length = $self->{'datastore'}->run_query( "SELECT length(sequence) FROM sequence_bin WHERE id=?", $match->{'seqbin_id'} );
	my $off_end;
	my $hunt_for_start_end = ( !$exact && $params->{'hunt'} ) ? 1 : 0;
	my $original_start     = $match->{'predicted_start'};
	my $original_end       = $match->{'predicted_end'};
	my ( $predicted_start, $predicted_end );
	my $complete_tooltip = '';
	my ( $complete_gene, $status );
	my $buffer = '';

	#Hunt for nearby start and stop codons.  Walk in from each end by 3 bases, then out by 3 bases, then in by 6 etc.
	my @runs = $hunt_for_start_end ? qw (-3 3 -6 6 -9 9 -12 12 -15 15 -18 18) : ();
  RUN: foreach ( 0, @runs ) {
		my @end_to_adjust = $hunt_for_start_end ? ( 1, 2 ) : (0);
		foreach my $end (@end_to_adjust) {
			if ( $end == 1 ) {
				if (   ( !$status->{'start'} && $match->{'reverse'} )
					|| ( !$status->{'stop'} && !$match->{'reverse'} ) )
				{
					$match->{'predicted_end'} = $original_end + $_;
				}
			} elsif ( $end == 2 ) {
				if (   ( !$status->{'stop'} && $match->{'reverse'} )
					|| ( !$status->{'start'} && !$match->{'reverse'} ) )
				{
					$match->{'predicted_start'} = $original_start + $_;
				}
			}
			if ( BIGSdb::Utils::is_int( $match->{'predicted_start'} ) && $match->{'predicted_start'} < 1 ) {
				$match->{'predicted_start'} = '1*';
				$off_end = 1;
			}
			if ( BIGSdb::Utils::is_int( $match->{'predicted_end'} ) && $match->{'predicted_end'} > $seqbin_length ) {
				$match->{'predicted_end'} = "$seqbin_length\*";
				$off_end = 1;
			}
			$predicted_start = $match->{'predicted_start'};
			$predicted_start =~ s/\*//;
			$predicted_end = $match->{'predicted_end'};
			$predicted_end =~ s/\*//;
			my $predicted_length = $predicted_end - $predicted_start + 1;
			$predicted_length = 1 if $predicted_length < 1;
			my $seq =
			  $self->{'datastore'}
			  ->run_query( "SELECT substring(sequence from $predicted_start for $predicted_length) FROM sequence_bin WHERE id=?",
				$match->{'seqbin_id'} );

			if ($seq) {
				$seq = BIGSdb::Utils::reverse_complement($seq) if $match->{'reverse'};
				( $complete_gene, $status ) = $self->is_complete_gene( $seq, { return_status => 1 } );
				if ($complete_gene) {
					$complete_tooltip = "<a class=\"cds\" title=\"CDS - this is a complete coding sequence including start and "
					  . "terminating stop codons with no internal stop codons.\">CDS</a>";
					last RUN;
				}
			}
		}
	}
	if ( $hunt_for_start_end && !$complete_gene ) {
		$match->{'predicted_end'}   = $original_end;
		$predicted_end              = $original_end;
		$match->{'predicted_start'} = $original_start;
		$predicted_start            = $original_start;
		if ( $match->{'predicted_start'} < 1 ) {
			$match->{'predicted_start'} = '1*';
			$off_end = 1;
		}
		if ( $match->{'predicted_end'} > $seqbin_length ) {
			$match->{'predicted_end'} = "$seqbin_length\*";
			$off_end = 1;
		}
	}
	my $cleaned_locus = $self->clean_locus($locus);
	my $locus_info    = $self->{'datastore'}->get_locus_info($locus);
	my $translate     = ( $locus_info->{'coding_sequence'} || $locus_info->{'data_type'} eq 'peptide' ) ? 1 : 0;
	my $orf           = $locus_info->{'orf'} || 1;
	if ($warning) {
		$buffer .= "<tr class=\"warning\">";
	} else {
		$buffer .= "<tr class=\"td$td\">";
	}
	$buffer .= "<td>"
	  . ( $labels->{$isolate_id} || $isolate_id )
	  . "</td><td$class>"
	  . ( $exact ? 'exact' : 'partial' )
	  . "</td><td$class>$cleaned_locus";
	$buffer .= "</td>";
	$tooltip ||= '';
	$buffer .= "<td$class>$match->{'allele'}$tooltip</td>";
	$buffer .= "<td>$match->{'identity'}</td>";
	$buffer .= "<td>$match->{'alignment'}</td>";
	$buffer .= "<td>$match->{'length'}</td>";
	$buffer .= "<td>$match->{'e-value'}</td>";
	$buffer .= "<td>$match->{'seqbin_id'} </td>";
	$buffer .= "<td>$match->{'start'}</td>";
	$buffer .= "<td>$match->{'end'} </td>";
	$buffer .= $off_end ? "<td class=\"incomplete\">$match->{'predicted_start'}</td>" : "<td>$match->{'predicted_start'}</td>";
	$match->{'reverse'} ||= 0;
	$buffer .= $off_end ? "<td class=\"incomplete\">" : "<td>";
	$buffer .=
	    "$match->{'predicted_end'} <a target=\"_blank\" class=\"extract_tooltip\" href=\"$self->{'system'}->{'script_name'}?"
	  . "db=$self->{'instance'}&amp;page=extractedSequence&amp;seqbin_id=$match->{'seqbin_id'}&amp;start=$predicted_start&amp;"
	  . "end=$predicted_end&amp;reverse=$match->{'reverse'}&amp;translate=$translate&amp;orf=$orf\">extract&nbsp;&rarr;</a>"
	  . "$complete_tooltip</td>";
	$buffer .= "<td style=\"font-size:2em\">" . ( $match->{'reverse'} ? '&larr;' : '&rarr;' ) . "</td><td>";
	my $seq_disabled = 0;
	$cleaned_locus = $self->clean_checkbox_id($locus);
	$cleaned_locus =~ s/\\/\\\\/g;
	$exact = 0 if $warning;

	if (   $exact
		&& ( !@$existing_alleles || ( none { $match->{'allele'} eq $_ } @$existing_alleles ) )
		&& $match->{'allele'} ne 'ref'
		&& !$params->{'tblastx'} )
	{
		$buffer .= $q->checkbox(
			-name    => "id_$isolate_id\_$locus\_allele_$id",
			-id      => "id_$isolate_id\_$cleaned_locus\_allele_$id",
			-label   => '',
			-checked => $exact
		);
		$buffer .= $q->hidden( "id_$isolate_id\_$locus\_seqbin_id_$id", $match->{'seqbin_id'} );
		push @$js,  "\$(\"#id_$isolate_id\_$cleaned_locus\_allele_$id\").prop(\"checked\",true)";
		push @$js2, "\$(\"#id_$isolate_id\_$cleaned_locus\_allele_$id\").prop(\"checked\",false)";
		$new_designation = 1;
	} else {
		$buffer .= $q->checkbox( -name => "id_$isolate_id\_$locus\_allele_$id", -label => '', disabled => 'disabled' );
	}
	$buffer .= "</td><td>";
	my $existing_allele_sequence = $self->{'datastore'}->run_query(
		"SELECT id FROM allele_sequences WHERE seqbin_id=? AND locus=? AND start_pos=? AND end_pos=?",
		[ $match->{'seqbin_id'}, $locus, $predicted_start, $predicted_end ],
		{ fetch => 'row_hashref', cache => 'Scan::get_row_existing_allele_sequence' }
	);
	if ( !$existing_allele_sequence ) {
		$buffer .= $q->checkbox(
			-name    => "id_$isolate_id\_$locus\_sequence_$id",
			-id      => "id_$isolate_id\_$cleaned_locus\_sequence_$id",
			-label   => '',
			-checked => $exact
		);
		push @$js3, "\$(\"#id_$isolate_id\_$cleaned_locus\_sequence_$id\").prop(\"checked\",true)";
		push @$js4, "\$(\"#id_$isolate_id\_$cleaned_locus\_sequence_$id\").prop(\"checked\",false)";
		$new_designation = 1;
		$buffer .= "</td><td>";
		my ($default_flags);
		if ( $locus_info->{'flag_table'} && $exact ) {
			$default_flags = $self->{'datastore'}->get_locus($locus)->get_flags( $match->{'allele'} );
		}
		if ( ref $default_flags eq 'ARRAY' && @$default_flags > 1 ) {
			$buffer .= $q->popup_menu(
				-name     => "id_$isolate_id\_$locus\_sequence_$id\_flag",
				-id       => "id_$isolate_id\_$cleaned_locus\_sequence_$id\_flag",
				-values   => [SEQ_FLAGS],
				-default  => $default_flags,
				-multiple => 'multiple',
			);
		} else {
			$buffer .= $q->popup_menu(
				-name    => "id_$isolate_id\_$locus\_sequence_$id\_flag",
				-id      => "id_$isolate_id\_$cleaned_locus\_sequence_$id\_flag",
				-values  => [ '', SEQ_FLAGS ],
				-default => $default_flags,
			);
		}
	} else {
		$buffer .= $q->checkbox( -name => "id_$isolate_id\_$locus\_sequence_$id", -label => '', disabled => 'disabled' );
		$seq_disabled = 1;
		$buffer .= "</td><td>";
		my $flags = $self->{'datastore'}->get_sequence_flags( $existing_allele_sequence->{'id'} );
		foreach (@$flags) {
			$buffer .= " <a class=\"seqflag_tooltip\">$_</a>";
		}
	}
	if ($exact) {
		$buffer .= $q->hidden( "id_$isolate_id\_$locus\_allele_id_$id", $match->{'allele'} );
	}
	if ( !$seq_disabled ) {
		$buffer .= $q->hidden( "id_$isolate_id\_$locus\_start_$id",     $predicted_start );
		$buffer .= $q->hidden( "id_$isolate_id\_$locus\_end_$id",       $predicted_end );
		$buffer .= $q->hidden( "id_$isolate_id\_$locus\_reverse_$id",   $match->{'reverse'} );
		$buffer .= $q->hidden( "id_$isolate_id\_$locus\_complete_$id",  1 ) if !$off_end;
		$buffer .= $q->hidden( "id_$isolate_id\_$locus\_seqbin_id_$id", $match->{'seqbin_id'} );
	}
	$buffer .= "</td></tr>";
	return ( $buffer, $off_end, $new_designation );
}

sub _get_missing_row {
	my ( $self, $isolate_id, $labels, $locus, $js, $js2, ) = @_;
	my $q                  = $self->{'cgi'};
	my $existing_alleles   = $self->{'datastore'}->get_allele_ids( $isolate_id, $locus );
	my $existing_sequences = $self->{'datastore'}->get_allele_sequence( $isolate_id, $locus );
	my $cleaned_locus      = $self->clean_locus($locus);
	my $buffer;
	if ( @$existing_alleles || @$existing_sequences ) {
		print ' ';    #try to prevent time-out.
		return $buffer;
	}
	$buffer .= "<tr class=\"provisional\">";
	$buffer .= "<td>" . ( $labels->{$isolate_id} || $isolate_id ) . "</td><td>missing</td><td>$cleaned_locus";
	$buffer .= "</td>";
	$buffer .= "<td>0</td>";
	$buffer .= "<td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td>";
	$cleaned_locus = $self->clean_checkbox_id($locus);
	$cleaned_locus =~ s/\\/\\\\/g;
	$buffer .= $q->checkbox(
		-name    => "id_$isolate_id\_$locus\_allele_1",
		-id      => "id_$isolate_id\_$cleaned_locus\_allele_1",
		-label   => '',
		-checked => 'checked'
	);
	$buffer .= $q->hidden( "id_$isolate_id\_$locus\_allele_id_1", 0 );
	push @$js,  "\$(\"#id_$isolate_id\_$cleaned_locus\_allele_1\").prop(\"checked\",true)";
	push @$js2, "\$(\"#id_$isolate_id\_$cleaned_locus\_allele_1\").prop(\"checked\",false)";
	$buffer .= "</td><td></td><td></td>";
	$buffer .= "</tr>\n";
	return $buffer;
}

sub _parse_blast_exact {
	my ( $self, $args ) = @_;
	my ( $locus, $blast_file, $pcr_filter, $pcr_products, $probe_filter, $probe_matches ) =
	  @{$args}{qw (locus blast_file pcr_filter pcr_products probe_filter probe_matches)};
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$blast_file";
	open( my $blast_fh, '<', $full_path ) || ( $logger->error("Can't open BLAST output file $full_path. $!"), return \@; );
	my @matches;
	my $lengths;
	my $matched_already;
	my $region_matched_already;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
  LINE: while ( my $line = <$blast_fh> ) {
		my $match;
		next if !$line || $line =~ /^#/;
		my @record = split /\s+/, $line;
		if ( $record[2] == 100 ) {    #identity
			my $length;
			if ( ref $lengths ne 'HASH' ) {
				if ( $record[1] eq 'ref' ) {
					$lengths->{'ref'} = $self->{'datastore'}->run_query( "SELECT length(reference_sequence) FROM loci WHERE id=?",
						$locus, { cache => 'Scan::parse_blast_exact' } );
				} else {
					$lengths = $self->{'datastore'}->get_locus($locus)->get_all_sequence_lengths;
				}
			}
			next if !defined $lengths->{ $record[1] };
			$length = $lengths->{ $record[1] };
			if (
				(
					(
						$record[8] == 1             #sequence start position
						&& $record[9] == $length    #end position
					)
					|| (
						$record[8] == $length       #sequence start position (reverse complement)
						&& $record[9] == 1          #end position
					)
				)
				&& !$record[4]                      #no gaps
			  )
			{
				$match->{'seqbin_id'} = $record[0];
				$match->{'allele'}    = $record[1];
				$match->{'identity'}  = $record[2];
				$match->{'alignment'} = $self->{'cgi'}->param('tblastx') ? ( $record[3] * 3 ) : $record[3];
				$match->{'length'}    = $length;
				if ( $record[6] < $record[7] ) {
					$match->{'start'} = $record[6];
					$match->{'end'}   = $record[7];
				} else {
					$match->{'start'} = $record[7];
					$match->{'end'}   = $record[6];
				}
				if ($pcr_filter) {
					my $within_amplicon = 0;
					foreach (@$pcr_products) {
						next
						  if $match->{'seqbin_id'} != $_->{'seqbin_id'}
						  || $match->{'start'} < $_->{'start'}
						  || $match->{'end'} > $_->{'end'};
						$within_amplicon = 1;
					}
					next LINE if !$within_amplicon;
				}
				if ($probe_filter) {
					next LINE if !$self->_probe_filter_match( $locus, $match, $probe_matches );
				}
				$match->{'predicted_start'} = $match->{'start'};
				$match->{'predicted_end'}   = $match->{'end'};
				if ( ( $record[8] > $record[9] && $record[7] > $record[6] ) || ( $record[8] < $record[9] && $record[7] < $record[6] ) ) {
					$match->{'reverse'} = 1;
				} else {
					$match->{'reverse'} = 0;
				}
				$match->{'e-value'} = $record[10];
				next if $matched_already->{ $match->{'allele'} }->{ $match->{'predicted_start'} };
				push @matches, $match;
				$matched_already->{ $match->{'allele'} }->{ $match->{'predicted_start'} }           = 1;
				$region_matched_already->{ $match->{'seqbin_id'} }->{ $match->{'predicted_start'} } = 1;
				last if $locus_info->{'match_longest'};
			}
		}
	}
	close $blast_fh;
	return \@matches, $region_matched_already;
}

sub _parse_blast_partial {
	my ( $self, $args ) = @_;
	my ( $params, $locus, $exact_matched_regions, $blast_file, $pcr_filter, $pcr_products, $probe_filter, $probe_matches ) =
	  @{$args}{qw (params locus exact_matched_regions blast_file pcr_filter pcr_products probe_filter probe_matches)};
	my @matches;
	my $identity  = $params->{'identity'};
	my $alignment = $params->{'alignment'};
	$identity  = 70 if !BIGSdb::Utils::is_int($identity);
	$alignment = 50 if !BIGSdb::Utils::is_int($alignment);
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$blast_file";
	open( my $blast_fh, '<', $full_path ) || ( $logger->error("Can't open BLAST output file $full_path. $!"), return \$; );
	my %lengths;
  LINE: while ( my $line = <$blast_fh> ) {
		next if !$line || $line =~ /^#/;
		my @record = split /\s+/, $line;
		if ( !$lengths{ $record[1] } ) {
			if ( $record[1] eq 'ref' ) {
				$lengths{ $record[1] } =
				  $self->{'datastore'}
				  ->run_query( "SELECT length(reference_sequence) FROM loci WHERE id=?", $locus, { cache => 'Scan::parse_blast_partial' } );
			} else {
				my $seq_ref = $self->{'datastore'}->get_locus($locus)->get_allele_sequence( $record[1] );
				next if !$$seq_ref;
				$lengths{ $record[1] } = length($$seq_ref);
			}
		}
		next if !defined $lengths{ $record[1] };
		my $length = $lengths{ $record[1] };
		if ( $params->{'tblastx'} ) {
			$record[3] *= 3;
		}
		my $quality = $record[3] * $record[2];    #simple metric of alignment length x percentage identity
		if ( $record[3] >= $alignment * 0.01 * $length && $record[2] >= $identity ) {
			my $match;
			$match->{'quality'}   = $quality;
			$match->{'seqbin_id'} = $record[0];
			$match->{'allele'}    = $record[1];
			$match->{'identity'}  = $record[2];
			$match->{'length'}    = $length;
			$match->{'alignment'} = $record[3];
			if ( ( $record[8] > $record[9] && $record[7] > $record[6] ) || ( $record[8] < $record[9] && $record[7] < $record[6] ) ) {
				$match->{'reverse'} = 1;
			} else {
				$match->{'reverse'} = 0;
			}
			if ( $record[6] < $record[7] ) {
				$match->{'start'} = $record[6];
				$match->{'end'}   = $record[7];
			} else {
				$match->{'start'} = $record[7];
				$match->{'end'}   = $record[6];
			}
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

			#Don't handle exact matches - these are handled elsewhere.
			next if $exact_matched_regions->{ $match->{'seqbin_id'} }->{ $match->{'predicted_start'} };
			$match->{'e-value'} = $record[10];
			if ($pcr_filter) {
				my $within_amplicon = 0;
				foreach (@$pcr_products) {
					next
					  if $match->{'seqbin_id'} != $_->{'seqbin_id'}
					  || $match->{'start'} < $_->{'start'}
					  || $match->{'end'} > $_->{'end'};
					$within_amplicon = 1;
				}
				next LINE if !$within_amplicon;
			}
			if ($probe_filter) {
				next LINE if !$self->_probe_filter_match( $locus, $match, $probe_matches );
			}

			#check if match already found with same predicted start or end points
			my $exists;
			foreach (@matches) {
				if (
					$_->{'seqbin_id'} == $match->{'seqbin_id'}
					&& (   $_->{'predicted_start'} == $match->{'predicted_start'}
						|| $_->{'predicted_end'} == $match->{'predicted_end'} )
				  )
				{
					$exists = 1;
				}
			}
			if ( !$exists ) {
				push @matches, $match;
			}
		}
	}
	close $blast_fh;

	#Only return the number of matches selected by 'partial_matches' parameter
	@matches = sort { $b->{'quality'} <=> $a->{'quality'} } @matches;
	my $partial_matches = $params->{'partial_matches'};
	$partial_matches = 1 if !BIGSdb::Utils::is_int($partial_matches) || $partial_matches < 1;
	while ( @matches > $partial_matches ) {
		pop @matches;
	}
	return \@matches;
}

sub _get_designation_tooltip {
	my ( $self, $isolate_id, $locus, $status ) = @_;
	my $class;
	my $text;
	if ( $status eq 'existing' ) {
		$class = 'existing_tooltip';
		$text  = 'existing';
	} else {
		$class = 'clashing_tooltip';
		$text  = 'conflict';
	}
	my $designations = $self->{'datastore'}->get_allele_designations( $isolate_id, $locus );
	my $plural = @$designations == 1 ? '' : 's';
	my $buffer = "Existing designation$plural - ";
	foreach my $designation (@$designations) {
		my $sender = $self->{'datastore'}->get_user_info( $designation->{'sender'} );
		$buffer .= "allele: $designation->{'allele_id'} ";
		$buffer .= "($designation->{'comments'}) "
		  if $designation->{'comments'};
		$buffer .= "[$sender->{'first_name'} $sender->{'surname'}; $designation->{'method'}; $designation->{'datestamp'}]<br />";
	}
	return " <a class=\"$class\" title=\"$buffer\">$text</a>";
}

sub is_complete_gene {
	my ( $self, $seq, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $status;

	#Check that sequence has an initial start codon,
	my $start = substr( $seq, 0, 3 );
	$status->{'start'} = 1 if any { $start eq $_ } qw (ATG GTG TTG);

	#and a stop codon
	my $stop = substr( $seq, -3 );
	$status->{'stop'} = 1 if any { $stop eq $_ } qw (TAA TGA TAG);

	#is a multiple of 3
	$status->{'in_frame'} = 1 if length($seq) / 3 == int( length($seq) / 3 );

	#and has no internal stop codons
	$status->{'no_internal_stops'} = 1;
	for ( my $i = 0 ; $i < length($seq) - 3 ; $i += 3 ) {
		my $codon = substr( $seq, $i, 3 );
		$status->{'no_internal_stops'} = 0 if any { $codon eq $_ } qw (TAA TGA TAG);
	}
	if ( $status->{'start'} && $status->{'stop'} && $status->{'in_frame'} && $status->{'no_internal_stops'} ) {
		return $options->{'return_status'} ? ( 1, $status ) : 1;
	}
	return $options->{'return_status'} ? ( 0, $status ) : 0;
}

sub _write_status {

	#Write status to a file in secure_tmp that can be read by viewing page.
	my ( $self, $scan_job, $data, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $status_file = "$self->{'config'}->{'secure_tmp_dir'}/$scan_job\_status.txt";
	unlink $status_file if $options->{'reset'};
	open( my $fh, '>>', $status_file ) || $logger->error("Can't open $status_file for appending");
	say $fh $data;
	close $fh;
	return;
}

sub _read_status {
	my ( $self, $scan_job ) = @_;
	my $status_file = "$self->{'config'}->{'secure_tmp_dir'}/$scan_job\_status.txt";
	my %data;
	return \%data if !-e $status_file;
	open( my $fh, '<', $status_file ) || $logger->error("Can't open $status_file for reading. $!");
	while (<$fh>) {
		if ( $_ =~ /^(.*):(.*)$/ ) {
			$data{$1} = $2;
		}
	}
	close $fh;
	return \%data;
}

sub _write_match {

	#Write matches to a file in secure_tmp that can be read by tagging page.
	my ( $self, $scan_job, $data, $options ) = @_;
	$data //= '';
	$options = {} if ref $options ne 'HASH';
	my $match_file = "$self->{'config'}->{'secure_tmp_dir'}/$scan_job\_matches.txt";
	unlink $match_file if $options->{'reset'};
	open( my $fh, '>>', $match_file ) || $logger->error("Can't open $match_file for appending");
	say $fh $data;
	close $fh;
	return;
}

sub _simulate_PCR {
	my ( $self, $fasta_file, $locus ) = @_;
	my $q = $self->{'cgi'};
	my $reactions =
	  $self->{'datastore'}
	  ->run_list_query_hashref( "SELECT pcr.* FROM pcr LEFT JOIN pcr_locus ON pcr.id = pcr_locus.pcr_id WHERE locus=?", $locus );
	return if !@$reactions;
	my $temp          = BIGSdb::Utils::get_random();
	my $reaction_file = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_reactions.txt";
	my $results_file  = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_results.txt";
	open( my $fh, '>', $reaction_file ) || $logger->error("Can't open $reaction_file for writing");
	my $max_primer_mismatch = 0;
	my $conditions;

	foreach (@$reactions) {
		foreach my $primer (qw (primer1 primer2)) {
			$_->{$primer} =~ tr/ //;
		}
		my $min_length = $_->{'min_length'} || 1;
		my $max_length = $_->{'max_length'} || 50000;
		$max_primer_mismatch = $_->{'max_primer_mismatch'} if $_->{'max_primer_mismatch'} > $max_primer_mismatch;
		if ( $q->param('alter_pcr_mismatches') && $q->param('alter_pcr_mismatches') =~ /([\-\+]\d)/ ) {
			my $delta = $1;
			$max_primer_mismatch += $delta;
			$max_primer_mismatch = 0 if $max_primer_mismatch < 0;
		}
		print $fh "$_->{'id'}\t$_->{'primer1'}\t$_->{'primer2'}\t$min_length\t$max_length\n";
		$conditions->{ $_->{'id'} } = $_;
	}
	close $fh;
	system(
"$self->{'config'}->{'ipcress_path'} --input $reaction_file --sequence $fasta_file --mismatch $max_primer_mismatch --pretty false > $results_file 2> /dev/null"
	);
	my @pcr_products;
	open( $fh, '<', $results_file ) || $logger->error("Can't open $results_file for reading");
	while (<$fh>) {
		if ( $_ =~ /^ipcress:/ ) {
			my ( undef, $seq_id, $reaction_id, $length, undef, $start, $mismatch1, undef, $end, $mismatch2, $desc ) = split /\s+/, $_;
			next if $desc =~ /single/;    #product generated by one primer only.
			my ( $seqbin_id, undef ) = split /:/, $seq_id;
			$logger->debug("Seqbin_id:$seqbin_id; $start-$end; mismatch1:$mismatch1; mismatch2:$mismatch2");
			next
			  if $mismatch1 > $conditions->{$reaction_id}->{'max_primer_mismatch'}
			  || $mismatch2 > $conditions->{$reaction_id}->{'max_primer_mismatch'};
			my $product =
			  { 'seqbin_id' => $seqbin_id, 'start' => $start, 'end' => $end, 'mismatch1' => $mismatch1, 'mismatch2' => $mismatch2 };
			push @pcr_products, $product;
		}
	}
	close $fh;
	unlink $reaction_file, $results_file;
	return \@pcr_products;
}

sub _simulate_hybridization {
	my ( $self, $fasta_file, $locus ) = @_;
	my $q      = $self->{'cgi'};
	my $probes = $self->{'datastore'}->run_list_query_hashref(
"SELECT probes.id,probes.sequence,probe_locus.* FROM probes LEFT JOIN probe_locus ON probes.id = probe_locus.probe_id WHERE locus=?",
		$locus
	);
	return if !@$probes;
	my $file_prefix      = BIGSdb::Utils::get_random();
	my $probe_fasta_file = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_probe.txt";
	my $results_file     = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_results.txt";
	open( my $fh, '>', $probe_fasta_file ) or $logger->error("Can't open temp file $probe_fasta_file for writing");
	my %probe_info;

	foreach (@$probes) {
		$_->{'sequence'} =~ s/\s//g;
		print $fh ">$_->{'id'}\n$_->{'sequence'}\n";
		$_->{'max_mismatch'} = 0 if !$_->{'max_mismatch'};
		if ( $q->param('alter_probe_mismatches') && $q->param('alter_probe_mismatches') =~ /([\-\+]\d)/ ) {
			my $delta = $1;
			$_->{'max_mismatch'} += $delta;
			$_->{'max_mismatch'} = 0 if $_->{'max_mismatch'} < 0;
		}
		$_->{'max_gaps'} = 0 if !$_->{'max_gaps'};
		$_->{'min_alignment'} = length $_->{'sequence'} if !$_->{'min_alignment'};
		$probe_info{ $_->{'id'} } = $_;
	}
	close $fh;
	system( "$self->{'config'}->{'blast+_path'}/makeblastdb", ( -in => $fasta_file, -logfile => '/dev/null', -dbtype => 'nucl' ) );
	my $blast_threads = $self->{'config'}->{'blast_threads'} || 1;
	system(
		"$self->{'config'}->{'blast+_path'}/blastn",
		(
			-task            => 'blastn',
			-num_threads     => $blast_threads,
			-max_target_seqs => 1000,
			-db              => $fasta_file,
			-out             => $results_file,
			-query           => $probe_fasta_file,
			-outfmt          => 6,
			-dust            => 'no'
		)
	);
	my @matches;
	if ( -e $results_file ) {
		open( $fh, '<', $results_file ) || $logger->error("Can't open $results_file for reading");
		while (<$fh>) {
			my @record = split /\t/, $_;
			my $match;
			$match->{'probe_id'}  = $record[0];
			$match->{'seqbin_id'} = $record[1];
			$match->{'alignment'} = $record[3];
			next if $match->{'alignment'} < $probe_info{ $match->{'probe_id'} }->{'min_alignment'};
			$match->{'mismatches'} = $record[4];
			next if $match->{'mismatches'} > $probe_info{ $match->{'probe_id'} }->{'max_mismatch'};
			$match->{'gaps'} = $record[5];
			next if $match->{'gaps'} > $probe_info{ $match->{'probe_id'} }->{'max_gaps'};

			if ( $record[8] < $record[9] ) {
				$match->{'start'} = $record[8];
				$match->{'end'}   = $record[9];
			} else {
				$match->{'start'} = $record[9];
				$match->{'end'}   = $record[8];
			}
			$logger->debug("Seqbin: $match->{'seqbin_id'}; Start: $match->{'start'}; End: $match->{'end'}");
			push @matches, $match;
		}
		close $fh;
		unlink $results_file;
	}
	unlink $probe_fasta_file;
	return \@matches;
}

sub _probe_filter_match {
	my ( $self, $locus, $blast_match, $probe_matches ) = @_;
	my $good_match = 0;
	foreach my $match (@$probe_matches) {
		if ( !$self->{'probe_locus'}->{$locus}->{ $match->{'probe_id'} } ) {
			$self->{'probe_locus'}->{$locus}->{ $match->{'probe_id'} } = $self->{'datastore'}->run_query(
				"SELECT * FROM probe_locus WHERE locus=? AND probe_id=?",
				[ $locus, $match->{'probe_id'} ],
				{ fetch => 'row_hashref' }
			);
		}
		next if $blast_match->{'seqbin_id'} != $match->{'seqbin_id'};
		my $probe_distance = -1;
		if ( $blast_match->{'start'} > $match->{'end'} ) {
			$probe_distance = $blast_match->{'start'} - $match->{'end'};
		}
		if ( $blast_match->{'end'} < $match->{'start'} ) {
			my $end_distance = $match->{'start'} - $blast_match->{'end'};
			if ( ( $end_distance < $probe_distance ) || ( $probe_distance == -1 ) ) {
				$probe_distance = $end_distance;
			}
		}
		next if ( $probe_distance > $self->{'probe_locus'}->{$locus}->{ $match->{'probe_id'} }->{'max_distance'} ) || $probe_distance == -1;
		return 1;
	}
	return 0;
}
1;
