#PCR.pm - In silico PCR plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2019, University of Oxford
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
package BIGSdb::Plugins::PCR;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use BIGSdb::Exceptions;
use BIGSdb::Constants qw(:interface);
use List::MoreUtils qw(uniq);
use Log::Log4perl qw(get_logger);
use Try::Tiny;
use constant MAX_DISPLAY_TAXA     => 1000;
use constant MIN_PRIMER_LENGTH    => 13;
use constant MAX_WOBBLE_PERCENT   => 25;
use constant MAX_MISMATCH_PERCENT => 25;
my $logger = get_logger('BIGSdb.Plugins');

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name        => 'PCR',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => '<i>In silico</i> PCR tool for designing and testing primers',
		category    => 'Analysis',
		buttontext  => 'PCR',
		menutext    => 'In silico PCR',
		module      => 'PCR',
		version     => '1.0.0',
		dbtype      => 'isolates',
		section     => 'info,analysis,postquery',
		input       => 'query',
		help        => 'tooltips',
		system_flag => 'PCR',
		requires    => 'seqbin,ipcress',
		order       => 45,
		priority    => 0
	);
	return \%att;
}

sub run {
	my ($self) = @_;
	say q(<h1>In silico PCR</h1>);
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $qry_ref    = $self->get_query($query_file);
	my $selected_ids;
	my $seqbin_values = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT id FROM sequence_bin)');
	if ( !$seqbin_values ) {
		$self->print_bad_status( { message => q(This database view contains no genomes.), navbar => 1 } );
		return;
	}
	if ( $q->param('single_isolate') ) {
		if ( !BIGSdb::Utils::is_int( $q->param('single_isolate') ) ) {
			$self->print_bad_status( { message => q(Invalid isolate id passed.), navbar => 1 } );
			return;
		}
		if ( !$self->isolate_exists( $q->param('single_isolate'), { has_seqbin => 1 } ) ) {
			$self->print_bad_status(
				{
					message => q(Passed isolate id either does not exist or has no sequence bin data.),
					navbar  => 1
				}
			);
			return;
		}
	}
	if ( $q->param('isolate_id') ) {
		my @ids = $q->param('isolate_id');
		$selected_ids = \@ids;
	} elsif ( defined $query_file ) {
		$selected_ids = $self->get_ids_from_query($qry_ref);
	} else {
		$selected_ids = [];
	}
	if ( $q->param('submit') ) {
		my $job_submitted;
		try {    #No need to catch exception - just display error and query form.
			my $parameters = $self->_validate;
			$job_submitted = $self->_add_job($parameters);
		};
		return if $job_submitted;
	}
	$self->_print_interface($selected_ids);
	return;
}

sub _print_interface {
	my ( $self, $ids ) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="queryform">);
	say q(<p>Use this tool to simulate PCR reactions run using genomes stored in the database. This is useful )
	  . q(for designing and testing primers. The plugin is a wrapper for the exonerate )
	  . q(<a href="https://www.ebi.ac.uk/about/vertebrate-genomics/software/ipcress-manual">ipcress</a> program )
	  . q(written by Guy Slater.</p>);
	if ( !$q->param('single_isolate') ) {
		say q(<p>Please select the required isolate ids to run the PCR reaction against. )
		  . q(These isolate records must include genome sequences.</p>);
	}
	say $q->start_form;
	say q(<div class="scrollable">);
	if ( BIGSdb::Utils::is_int( $q->param('single_isolate') ) ) {
		my $isolate_id = $q->param('single_isolate');
		my $name       = $self->get_isolate_name_from_id($isolate_id);
		say q(<fieldset style="float:left"><legend>Selected record</legend>);
		say $self->get_list_block(
			[ { title => 'id', data => $isolate_id }, { title => $self->{'system'}->{'labelfield'}, data => $name } ],
			{ width => 6 } );
		say $q->hidden( isolate_id => $isolate_id );
		say q(</fieldset>);
	} else {
		$self->print_seqbin_isolate_fieldset( { selected_ids => $ids, isolate_paste_list => 1, only_genomes => 1 } );
	}
	say q(<fieldset style="float:left"><legend>Primer 1</legend>);
	say q(<ul><li>);
	say $q->textarea(
		-id          => 'primer1',
		-name        => 'primer1',
		-cols        => 20,
		-placeholder => 'Enter primer sequence',
		-required    => 'required'
	);
	say q(</li><li>);
	say q(<label for="mismatch1">Allowed mismatches:</label>);
	say $q->popup_menu(
		-id      => 'mismatch1',
		-name    => 'mismatch1',
		-values  => [ 0 .. 20 ],
		-default => 0
	);
	say q(</li></ul>);
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Primer 2</legend>);
	say q(<ul><li>);
	say $q->textarea(
		-id          => 'primer2',
		-name        => 'primer2',
		-cols        => 20,
		-placeholder => 'Enter primer sequence',
		-required    => 'required'
	);
	say q(</li><li>);
	say q(<label for="mismatch2">Allowed mismatches:</label>);
	say $q->popup_menu(
		-id      => 'mismatch2',
		-name    => 'mismatch2',
		-values  => [ 0 .. 20 ],
		-default => 0
	);
	say q(</li></ul>);
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Reported products</legend>);
	say q(<ul><li>);
	say q(<label for="min_length" class="display">Min length:</label>);
	say $self->textfield(
		-id    => 'min_length',
		-name  => 'min_length',
		-value => 0,
		-type  => 'number',
		-style => 'width:8em'
	);
	say q(</li><li>);
	say q(<label for="max_length" class="display">Max length:</label>);
	say $self->textfield(
		-id    => 'max_length',
		-name  => 'max_length',
		-value => 10_000,
		-type  => 'number',
		-style => 'width:8em'
	);
	say q(</li><li>);
	say $q->checkbox( -id => 'export', -name => 'export', -label => 'Export sequences' );
	say q(</li></ul>);
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach qw (page name db);
	say q(</div>);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _validate {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my @ids    = $q->param('isolate_id');
	my ( $pasted_cleaned_ids, $invalid_ids ) =
	  $self->get_ids_from_pasted_list( { dont_clear => 1, has_seqbin => 1 } );
	push @ids, @$pasted_cleaned_ids;
	@ids = uniq @ids;
	my $max_wobble = 0;
	my @errors;

	if ( !@ids ) {
		push @errors, 'No valid isolate records with genomes selected.';
	}
	( my $primer1 = $q->param('primer1') ) =~ s/\s//gx;
	if ( uc($primer1) =~ /[^ACGTURYSWKMBDHVN]/x ) {
		push @errors, 'Primer 1 contains non-nucleotide characters.';
	} else {
		my $primer1_wobble = () = uc($primer1) =~ /[^ACGTU]/gx;
		$max_wobble = $primer1_wobble if $primer1_wobble > $max_wobble;
		if ( 100 * $primer1_wobble / length($primer1) > MAX_WOBBLE_PERCENT ) {
			push @errors,
			  'Primer 1 has more than the allowed proportion (' . MAX_WOBBLE_PERCENT . '%) of wobble bases.';
		}
		my $mismatch1 = BIGSdb::Utils::is_int( $q->param('mismatch1') ) ? $q->param('mismatch1') : 0;
		if ( 100 * $mismatch1 / length($primer1) > MAX_MISMATCH_PERCENT ) {
			push @errors,
			    'The mismatch setting for primer 1 is too high. This can be no more than '
			  . MAX_MISMATCH_PERCENT
			  . '% of the length.';
		}
	}
	if ( length($primer1) < MIN_PRIMER_LENGTH ) {
		push @errors, 'Primer 1 is shorter than the minimum allowed length (' . MIN_PRIMER_LENGTH . ' bp).';
	}
	( my $primer2 = $q->param('primer2') ) =~ s/\s//gx;
	if ( uc($primer2) =~ /[^ACGTURYSWKMBDHVN]/x ) {
		push @errors, 'Primer 2 contains non-nucleotide characters.';
	} else {
		my $primer2_wobble = () = uc($primer2) =~ /[^ACGTU]/gx;
		$max_wobble = $primer2_wobble if $primer2_wobble > $max_wobble;
		if ( 100 * $primer2_wobble / length($primer2) > MAX_WOBBLE_PERCENT ) {
			push @errors,
			  'Primer 2 has more than the allowed proportion (' . MAX_WOBBLE_PERCENT . '%) of wobble bases.';
		}
		my $mismatch2 = BIGSdb::Utils::is_int( $q->param('mismatch2') ) ? $q->param('mismatch2') : 0;
		if ( 100 * $mismatch2 / length($primer2) > MAX_MISMATCH_PERCENT ) {
			push @errors,
			    'The mismatch setting for primer 2 is too high. This can be no more than '
			  . MAX_MISMATCH_PERCENT
			  . '% of the length.';
		}
	}
	if ( length($primer2) < MIN_PRIMER_LENGTH ) {
		push @errors, 'Primer 2 is shorter than the minimum allowed length (' . MIN_PRIMER_LENGTH . ' bp).';
	}
	my $min = $q->param('min_length');
	if ( !BIGSdb::Utils::is_int($min) ) {
		push @errors, 'Min value must be an integer.';
	}
	my $max = $q->param('max_length');
	if ( !BIGSdb::Utils::is_int($max) ) {
		push @errors, 'Max value must be an integer.';
	}
	my $mismatch1 = $q->param('mismatch1');
	if ( !BIGSdb::Utils::is_int($mismatch1) ) {
		push @errors, 'Allowed mismatches for primer 1 must be an integer.';
	}
	my $mismatch2 = $q->param('mismatch2');
	if ( !BIGSdb::Utils::is_int($mismatch2) ) {
		push @errors, 'Allowed mismatches for primer 2 must be an integer.';
	}
	if (@errors) {
		local $" = q(<br />);
		$self->print_bad_status(
			{
				message => 'Validation failed',
				detail  => qq(@errors)
			}
		);
		BIGSdb::Exception::Data->throw('Invalid parameters');
	}
	return {
		ids        => \@ids,
		primer1    => $primer1,
		primer2    => $primer2,
		mismatch1  => $mismatch1,
		mismatch2  => $mismatch2,
		min        => $min,
		max        => $max,
		max_wobble => $max_wobble,
		export     => $q->param('export') ? 1 : 0
	};
}

sub _add_job {
	my ( $self, $parameters ) = @_;
	my $q         = $self->{'cgi'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $ids       = $parameters->{'ids'};
	delete $parameters->{'ids'};
	my $att    = $self->get_attributes;
	my $job_id = $self->{'jobManager'}->add_job(
		{
			dbase_config => $self->{'instance'},
			ip_address   => $q->remote_host,
			module       => $att->{'module'},
			priority     => $att->{'priority'},
			parameters   => $parameters,
			username     => $self->{'username'},
			email        => $user_info->{'email'},
			isolates     => $ids,
		}
	);
	say $self->get_job_redirect($job_id);
	return 1;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	$self->{'exit'} = 0;
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1 } ) x 3;
	my $ids      = $self->{'jobManager'}->get_job_isolates($job_id);
	my $i        = 0;
	my $progress = 0;
	my @fields   = (
		'id', $self->{'system'}->{'labelfield'},
		'PCR +ve', 'products', 'contig', 'length', 'start', 'end', 'description'
	);
	local $" = q(</th><th>);
	my $table_header = qq(<table class="resultstable"><tr><th>@fields</th></tr>);
	my $table_footer = q(</table>);

	if ( @$ids > MAX_DISPLAY_TAXA ) {
		my $max_display_taxa = MAX_DISPLAY_TAXA;
		$self->{'jobManager'}->update_job_status( $job_id,
			{ message_html => "<p>Dynamically updated output disabled as >$max_display_taxa taxa selected.</p>" } );
	}
	my $row_buffer    = q();
	my $td            = 1;
	my $reaction_file = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}_reactions.txt";
	my $fasta_file    = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}_seq.fasta";
	my $results_file  = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}_results.txt";
	$self->_make_reaction_file( $reaction_file, $params );
	my $max_mismatch =
	  $params->{'mismatch1'} >= $params->{'mismatch2'} ? $params->{'mismatch1'} : $params->{'mismatch2'};

	#A wobble match can be misreported as a mismatch by ipcress.
	$max_mismatch += $params->{'max_wobble'};
	my ( $good, $bad ) = ( GOOD, BAD );
	my $summary     = [];
	my $export_seqs = [];
	foreach my $id (@$ids) {
		$self->_make_fasta_file( $fasta_file, $id );
		$progress = int( $i / @$ids * 100 );
		$i++;
		$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => $progress } );
		system( "$self->{'config'}->{'ipcress_path'} --input $reaction_file --sequence $fasta_file "
			  . "--mismatch $max_mismatch --pretty false > $results_file 2> /dev/null" );
		my $results     = $self->_parse_results( $results_file, $params );
		my $num_results = @$results;
		my $label       = $self->get_isolate_name_from_id($id);
		local $" = q(</td><td>);
		push @$summary, [ $id, $label, $num_results ? '+' : '-', $num_results ];

		if ( $num_results == 0 ) {
			$row_buffer .=
			  qq(<tr class="td$td"><td>$id</td><td>$label</td><td>$bad</td><td>0</td><td colspan="5"></td></tr>);
		} elsif ( $num_results == 1 ) {
			my @values = @{ $results->[0] }{qw(seqbin_id length start end description)};
			$row_buffer .=
			  qq(<tr class="td$td"><td>$id</td><td>$label</td><td>$good</td><td>1</td><td>@values</td></tr>);
		} else {
			my @values = @{ $results->[0] }{qw(seqbin_id length start end description)};
			$row_buffer .=
			    qq(<tr class="td$td"><td rowspan="$num_results">$id</td>)
			  . qq(<td rowspan="$num_results">$label</td><td rowspan="$num_results">$good</td>)
			  . qq(<td rowspan="$num_results">$num_results</td><td>@values</td></tr>);
			for my $i ( 1 .. $num_results - 1 ) {
				@values = @{ $results->[$i] }{qw(seqbin_id length start end description)};
				$row_buffer .= qq(<tr class="td$td"><td>@values</td></tr>);
			}
		}
		if ( @$ids <= MAX_DISPLAY_TAXA ) {
			my $table = $table_header . $row_buffer . $table_footer;
			$self->{'jobManager'}->update_job_status( $job_id,
				{ percent_complete => $progress, message_html => $table, stage => "Checked id: $id" } );
		} else {
			$self->{'jobManager'}
			  ->update_job_status( $job_id, { percent_complete => $progress, stage => "Checked id: $id" } );
		}
		if ( $params->{'export'} ) {
			my $j = 1;
			foreach my $product (@$results) {
				my $seqs = $self->_extract_seqs( $params, $product );
				push @$export_seqs, {
					id => qq(id:${id}_$j|$product->{'seqbin_id'}|)
					  . qq($product->{'start'}-$product->{'end'}|$product->{'description'})
					,
					seq => $seqs->{'seq'}
				};
				$j++;
			}
		}
		$td = $td == 1 ? 2 : 1;
		return if $self->{'exit'};
	}
	$self->_export_summary_tables( $job_id, $summary );
	unlink $reaction_file;
	unlink $fasta_file;
	unlink $results_file;
	if ($params->{'export'}){
		$self->_export_fasta($job_id,$export_seqs);
	}
	return;
}

sub _export_summary_tables {
	my ( $self, $job_id, $summary ) = @_;
	my $text_file = "$self->{'config'}->{'tmp_dir'}/${job_id}_summary.txt";
	open( my $fh, '>:encoding(utf8)', $text_file ) || $logger->error("Cannot open $text_file for writing");
	say $fh qq(id\tisolate\tPCR +ve\tproducts);
	foreach my $record (@$summary) {
		local $" = qq(\t);
		say $fh qq(@$record);
	}
	close $fh;
	$self->{'jobManager'}->update_job_output( $job_id,
		{ filename => "${job_id}_summary.txt", description => '01_Text format summary file' } );
	my $excel = BIGSdb::Utils::text2excel($text_file);
	if ( -e $excel ) {
		$self->{'jobManager'}->update_job_output( $job_id,
			{ filename => "${job_id}_summary.xlsx", description => '02_Excel format summary file' } );
	}
	return;
}

sub _export_fasta {
	my ($self, $job_id, $seqs) = @_;
	my $fasta_file = "$self->{'config'}->{'tmp_dir'}/${job_id}.fas";
	open( my $fh, '>:encoding(utf8)', $fasta_file ) || $logger->error("Cannot open $fasta_file for writing");
	foreach my $seq (@$seqs){
		say $fh qq(>$seq->{'id'});
		say $fh $seq->{'seq'};
	}
	close $fh;
	if ( -e $fasta_file ) {
		$self->{'jobManager'}->update_job_output( $job_id,
			{ filename => "${job_id}.fas", description => '03_FASTA file of predicted product sequences' } );
	}
	return;
}

sub _parse_results {
	my ( $self, $results_file, $params ) = @_;
	my $results = [];
	my $desc    = {
		forward  => 'forward',
		revcomp  => 'reverse',
		single_A => 'non-specific product (primer 1 only)',
		single_B => 'non-specific product (primer 2 only)'
	};
	open( my $fh, '<', $results_file ) || $logger->error("Cannot open $results_file for reading");
	while ( my $line = <$fh> ) {
		next if $line !~ /^ipcress:/x;
		my @values = split /\s/x, $line;
		my $product = {
			seqbin_id   => $values[1],
			length      => $values[3],
			start       => $values[5] + 1,
			end         => $values[8],
			description => $desc->{ $values[10] }
		};
		$product->{'seqbin_id'} =~ s/:.*//x;
		$product->{'end'} += ( $values[7] eq 'A' ) ? length( $params->{'primer1'} ) : length( $params->{'primer2'} );
		next if $self->_too_many_mismatches( $params, \@values, $product );
		push @$results, $product;
	}
	close $fh;
	return $results;
}

sub _too_many_mismatches {
	my ( $self, $params, $values, $product ) = @_;
	my $primer1_mismatch = $values->[4] eq 'A' ? $values->[6] : $values->[9];
	my $primer2_mismatch = $values->[4] eq 'B' ? $values->[6] : $values->[9];

	#If ipcress reports both primers are within mismatch range then return ok.
	return if $primer1_mismatch <= $params->{'mismatch1'} && $primer2_mismatch <= $params->{'mismatch2'};

	#ipcress, however, seems to have a bug that can over-report mismatches if
	#wobble bases are used (but it depends where in the primer sequence these appear).
	#If no wobble bases, then we can trust ipcress.
	if ( $params->{'max_wobble'} == 0 ) {
		return 1 if $primer1_mismatch > $params->{'mismatch1'};
		return 1 if $primer2_mismatch > $params->{'mismatch2'};
	}

	#If there are wobble bases then we need to check the primer region in returned sequences
	#and count the mismatches.
	my $seqs = $self->_extract_seqs( $params, $product );
	return 1 if $self->_count_mismatches( $params->{'primer1'}, $seqs->{'primer1'} ) > $params->{'mismatch1'};
	return 1 if $self->_count_mismatches( $params->{'primer2'}, $seqs->{'primer2'} ) > $params->{'mismatch2'};
	return;
}

sub _count_mismatches {
	my ( $self, $seq1, $seq2 ) = @_;
	if ( length($seq1) != length($seq2) ) {
		$logger->error('Sequences are different lengths - cannot count mismatches');
		return 0;
	}
	my $mismatches = 0;
	$seq1 = uc($seq1);
	$seq2 = uc($seq2);
	my $iupac = {
		A => [qw(A)],
		C => [qw(C)],
		G => [qw(G)],
		T => [qw(U T)],
		U => [qw(U T)],
		R => [qw(A G)],
		Y => [qw(C T)],
		S => [qw(G C)],
		W => [qw(A T)],
		K => [qw(G T)],
		M => [qw(A C)],
		B => [qw(C G T)],
		D => [qw(A G T)],
		H => [qw(A C T)],
		V => [qw(A C G)],
		N => [qw(A C G T)]
	};
  POS: for my $i ( 0 .. ( length $seq1 ) - 1 ) {
		my $seq1_base = substr( $seq1, $i, 1 );
		my $seq2_base = substr( $seq2, $i, 1 );
		next POS if $seq1_base eq $seq2_base;
		if ( $iupac->{$seq1_base} ) {
			foreach my $alt_base ( @{ $iupac->{$seq1_base} } ) {
				next POS if $alt_base eq $seq2_base;
			}
		} else {
			$logger->error("Unrecognized base '$seq1_base'");
		}
		$mismatches++;
	}
	return $mismatches;
}

sub _extract_seqs {
	my ( $self, $params, $product ) = @_;
	my $seq = $self->{'contigManager'}->get_contig_fragment(
		{
			seqbin_id => $product->{'seqbin_id'},
			start     => $product->{'start'},
			end       => $product->{'end'},
			reverse   => ( $product->{'description'} eq 'forward' ) ? 0 : 1
		}
	);
	my $primer1 = substr( $seq->{'seq'}, 0, length( $params->{'primer1'} ) );
	my $primer2 = BIGSdb::Utils::reverse_complement( substr( $seq->{'seq'}, -length( $params->{'primer2'} ) ) );
	return {
		seq     => $seq->{'seq'},
		primer1 => $primer1,
		primer2 => $primer2
	};
}

sub _make_reaction_file {
	my ( $self, $reaction_file, $params ) = @_;
	open( my $fh, '>', $reaction_file ) || $logger->error("Cannot open $reaction_file for writing");
	say $fh "reaction\t$params->{'primer1'}\t$params->{'primer2'}\t$params->{'min'}\t$params->{'max'}";
	close $fh;
	return;
}

sub _make_fasta_file {
	my ( $self, $fasta_file, $isolate_id ) = @_;
	my $seqbin_ids = $self->{'datastore'}
	  ->run_query( 'SELECT id FROM sequence_bin WHERE isolate_id=?', $isolate_id, { fetch => 'col_arrayref' } );
	my $contigs = $self->{'contigManager'}->get_contigs_by_list($seqbin_ids);
	open( my $fh, '>', $fasta_file ) || $logger->error("Cannot open $fasta_file for writing");
	foreach my $contig_id ( sort { $a <=> $b } keys %$contigs ) {
		say $fh qq(>$contig_id);
		say $fh $contigs->{$contig_id};
	}
	close $fh;
	return;
}
1;
