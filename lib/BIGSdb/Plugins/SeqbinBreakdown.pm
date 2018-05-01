#SeqbinBreakdown.pm - SeqbinBreakdown plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2017, University of Oxford
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
package BIGSdb::Plugins::SeqbinBreakdown;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin BIGSdb::SeqbinPage);
use Log::Log4perl qw(get_logger);
use POSIX qw(ceil);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use BIGSdb::Constants qw(SEQ_METHODS);
use List::MoreUtils qw(any uniq);
use constant MAX_INSTANT_RUN => 100;
use constant MAX_HTML_OUTPUT => 2000;

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name        => 'Sequence Bin Breakdown',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Breakdown of sequence bin contig properties',
		category    => 'Breakdown',
		buttontext  => 'Sequence bin',
		menutext    => 'Sequence bin',
		module      => 'SeqbinBreakdown',
		url         => "$self->{'config'}->{'doclink'}/data_analysis.html#sequence-bin-breakdown",
		version     => '1.4.1',
		dbtype      => 'isolates',
		section     => 'breakdown,postquery',
		input       => 'query',
		order       => 80,
		requires    => 'offline_jobs,js_tree',
		system_flag => 'SeqbinBreakdown'
	);
	return \%att;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 1, query_field => 0 };
	return;
}

sub run {
	my ($self) = @_;
	say q(<h1>Breakdown of sequence bin contig properties</h1>);
	return if $self->has_set_changed;
	my $q = $self->{'cgi'};
	if ( $q->param('submit') ) {
		my @ids = $q->param('isolate_id');
		my ( $pasted_cleaned_ids, $invalid_ids ) = $self->get_ids_from_pasted_list( { dont_clear => 1 } );
		push @ids, @$pasted_cleaned_ids;
		@ids = sort { $a <=> $b } uniq @ids;
		my $error;
		my $filtered_ids = $self->filter_ids_by_project( \@ids, $q->param('project_list') );
		if ( !@$filtered_ids ) {
			$error .= q(<p>You must include one or more isolates. Make sure your selected isolates haven't )
			  . q(been filtered to none by selecting a project.</p>);
		}
		if (@$invalid_ids) {
			local $" = ', ';
			$error .= qq(<p>The following isolates in your pasted list are invalid: @$invalid_ids.</p>);
		}
		my $loci_selected = $self->get_selected_loci;
		my ( $pasted_cleaned_loci, $invalid_loci ) = $self->get_loci_from_pasted_list( { dont_clear => 1 } );
		$q->delete('locus');
		push @$loci_selected, @$pasted_cleaned_loci;
		@$loci_selected = uniq @$loci_selected;
		if (@$invalid_loci) {
			local $" = ', ';
			$error .= qq(<p>The following loci in your pasted list are invalid: @$invalid_loci.</p>\n);
		}
		$self->add_scheme_loci($loci_selected);
		if ($error) {
			say qq(<div class="box statusbad">$error</div>);
			$self->_print_interface;
		} else {
			my $params = $q->Vars;
			if ( @$filtered_ids > MAX_INSTANT_RUN ) {
				$q->delete('isolate_paste_list');
				$q->delete('isolate_id');
				my $set_id = $self->get_set_id;
				$params->{'set_id'} = $set_id if $set_id;
				$params->{'script_name'} = $self->{'system'}->{'script_name'};
				my $att       = $self->get_attributes;
				my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
				my $job_id    = $self->{'jobManager'}->add_job(
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
			} else {
				$self->_print_interface;
				$self->_print_table( $filtered_ids, $loci_selected, $params );
			}
		}
	} else {
		$self->_print_interface;
	}
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	$self->{'exit'} = 0;
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1 } ) x 3; #Allow temp files to be cleaned on kill signals
	my ( $statements, $arguments ) = $self->_get_query_statements($params);
	$self->{'system'}->{'script_name'} = $params->{'script_name'};
	my $isolate_ids = $self->{'jobManager'}->get_job_isolates($job_id);
	my $loci        = $self->{'jobManager'}->get_job_loci($job_id);
	my ( $html_buffer, $text_buffer );
	my $td            = 1;
	my $data          = {};
	my $row           = 0;
	my $row_with_data = 0;
	my $disabled_html = @$isolate_ids > MAX_HTML_OUTPUT ? 1 : 0;

	if ($disabled_html) {
		$self->{'jobManager'}->update_job_status( $job_id,
			{ message_html => 'HTML output disabled as more than ' . MAX_HTML_OUTPUT . ' records selected.' } );
	}
	my $locus_count = @$loci;
	foreach my $id (@$isolate_ids) {
		my $contig_info = $self->_get_isolate_contig_data( $id, $loci, $statements, $arguments, $params );
		$row++;
		next if !$contig_info->{'contigs'};
		$row_with_data++;
		$html_buffer .= $self->_get_html_table_row( $id, $contig_info, $td, $params ) . "\n";
		$text_buffer .= $self->_get_text_table_row( $id, $contig_info, $params ) . "\n";
		$td = $td == 1 ? 2 : 1;
		$self->_update_totals( $data, $contig_info );
		my $html_message =
		    qq(<p>Loci selected: $locus_count</p>)
		  . q(<div class="scrollable">)
		  . $self->_get_html_table_header($params)
		  . $html_buffer
		  . q(</tbody></table></div>);
		my $complete = int( $row * 100 / @$isolate_ids );

		if ( $row % 20 == 0 || $row == @$isolate_ids ) {
			if ($disabled_html) {
				$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => $complete } );
			} else {
				$self->{'jobManager'}
				  ->update_job_status( $job_id, { percent_complete => $complete, message_html => $html_message } );
			}
		}
		if ( $self->{'exit'} ) {
			my $job = $self->{'jobManager'}->get_job($job_id);
			if ( $job->{'status'} && $job->{'status'} ne 'cancelled' ) {
				$self->{'jobManager'}->update_job_status( $job_id, { status => 'terminated' } );
			}
			return;
		}
	}
	if ( !$row_with_data ) {
		$self->{'jobManager'}->update_job_status( $job_id,
			{ message_html => 'There are no records with contigs matching your criteria.' } );
	} else {
		my $job_file = "$self->{'config'}->{'tmp_dir'}/$job_id\.txt";
		open( my $job_fh, '>', $job_file ) || $logger->error("Can't open $job_file for writing");
		say $job_fh $self->_get_text_table_header(
			{ gc => $params->{'gc'}, contig_analysis => $params->{'contig_analysis'} } );
		print $job_fh $text_buffer;
		close $job_fh;
		$self->{'jobManager'}->update_job_output( $job_id,
			{ filename => "$job_id.txt", description => '01_Output in tab-delimited text format' } );
		my $excel_file =
		  BIGSdb::Utils::text2excel( $job_file,
			{ worksheet => 'sequence bin stats', tmp_dir => $self->{'config'}->{'secure_tmp_dir'} } );
		if ( -e $excel_file ) {
			$self->{'jobManager'}->update_job_output( $job_id,
				{ filename => "$job_id.xlsx", description => '02_Output in Excel format' } );
		}
		my $file_order = 10;
		my @types      = qw(contigs sum);
		push @types, qw(mean lengths) if $params->{'contig_analysis'};
		foreach my $type (@types) {
			my $prefix = BIGSdb::Utils::get_random();
			my $chart_data = $self->_make_chart( $data, $prefix, $type );
			if ( $chart_data->{'file_name'} ) {
				my $full_filename = "$self->{'config'}->{'tmp_dir'}/$chart_data->{'file_name'}";
				if ( -e $full_filename ) {
					$self->{'jobManager'}->update_job_output(
						$job_id,
						{
							filename    => $chart_data->{'file_name'},
							description => "$file_order\_$chart_data->{'title'}"
						}
					);
				}
			}
			$file_order++;
			if ( $chart_data->{'lengths_file'} ) {
				my $lengths_full_path = "$self->{'config'}->{'tmp_dir'}/$chart_data->{'lengths_file'}";
				$self->{'jobManager'}->update_job_output( $job_id,
					{ filename => $chart_data->{'lengths_file'}, description => "$file_order\_Download lengths" } )
				  if -e $lengths_full_path && !-z $lengths_full_path;
			}
		}
	}
	return;
}

sub _print_interface {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $qry_ref    = $self->get_query($query_file);
	if ( ref $qry_ref ne 'SCALAR' ) {
		$self->print_bad_status( { message => q(Error retrieving query.), navbar => 1 } );
		return;
	}
	my $qry = $$qry_ref;
	$qry =~ s/ORDER\ BY.*$//gx;
	$logger->debug("Breakdown query: $qry");
	my $view = $self->{'system'}->{'view'};
	$qry =~ s/SELECT\ ($view\.\*|\*)/SELECT id/x;
	$qry .= ' ORDER BY id';
	my $selected_ids;

	if ( $q->param('isolate_id') ) {
		my @ids = $q->param('isolate_id');
		$selected_ids = \@ids;
	} elsif ( defined $query_file ) {
		$selected_ids = $self->get_ids_from_query($qry_ref);
	} else {
		$selected_ids = [];
	}
	my $seqbin_exists =
	  $self->{'datastore'}->run_query("SELECT EXISTS(SELECT * FROM sequence_bin WHERE isolate_id IN ($qry))");
	if ( !$seqbin_exists ) {
		$self->print_bad_status(
			{
				message => q(There are no available sequences stored for any of the selected isolates.),
				navbar  => 1
			}
		);
		return;
	}
	say q(<div class="box" id="queryform">);
	say q(<p>Please select the required isolate ids for comparison - use Ctrl or Shift to make multiple )
	  . q(selections.  Select loci/schemes to use for calculating percentage of alleles designated or tagged.</p>);
	say q(<div class="scrollable">);
	say $q->start_form;
	$self->print_seqbin_isolate_fieldset( { selected_ids => $selected_ids, isolate_paste_list => 1 } );
	$self->print_isolates_locus_fieldset( { locus_paste_list => 1 } );
	$self->print_scheme_fieldset;
	$self->_print_options_fieldset;
	$self->print_sequence_filter_fieldset;
	$self->print_action_fieldset( { name => 'SeqbinBreakdown' } );
	say $q->hidden($_) foreach qw (page name db set_id);
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub _print_options_fieldset {
	my ($self) = @_;
	return if ( $self->{'system'}->{'remote_contigs'} // q() ) eq 'yes';
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left"><legend>Options</legend><ul><li>);
	say $q->checkbox( -name => 'contig_analysis', -label => 'Contig analysis (min, max, N50 etc.)' );
	say q(</li><li>);
	say $q->checkbox( -name => 'gc', -label => 'Calculate %GC' );
	say q(</li></ul></fieldset>);
	return;
}

sub _print_table {
	my ( $self, $ids, $loci, $params ) = @_;
	my ( $statements, $arguments ) = $self->_get_query_statements($params);
	my $temp = BIGSdb::Utils::get_random();
	my $td   = 1;
	local $| = 1;
	my $data             = {};
	my $header_displayed = 0;
	my $locus_count      = @$loci;
	say q(<div class="box" id="resultstable"><div class="scrollable">);
	say qq(<p>Loci selected: $locus_count</p>);
	my $text_file = "$self->{'config'}->{'tmp_dir'}/$temp.txt";
	open( my $fh, '>', $text_file ) or $logger->error("Can't open temp file $text_file for writing");

	foreach my $id (@$ids) {
		my $contig_info = $self->_get_isolate_contig_data( $id, $loci, $statements, $arguments, $params );
		next if !$contig_info->{'contigs'};
		if ( !$header_displayed ) {
			say $fh $self->_get_text_table_header($params);
			say $self->_get_html_table_header($params);
			$header_displayed = 1;
		}
		say $self->_get_html_table_row( $id, $contig_info, $td, $params );
		say $fh $self->_get_text_table_row( $id, $contig_info, $params );
		$td = $td == 1 ? 2 : 1;
		$self->_update_totals( $data, $contig_info );
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
	}
	close $fh;
	if ($header_displayed) {
		say q(</tbody></table>);
		say qq(<ul><li><a href="/tmp/$temp.txt">Download in tab-delimited text format</a></li>);
		my $excel_file =
		  BIGSdb::Utils::text2excel( $text_file,
			{ worksheet => 'sequence bin stats', tmp_dir => $self->{'config'}->{'secure_tmp_dir'} } );
		if ( -e $excel_file ) {
			say qq(<li><a href="/tmp/$temp.xlsx">Download in Excel format</a></li>);
		}
		say q(</ul>);
	} else {
		say q(<p>There are no records with contigs matching your criteria.</p>);
	}
	say q(</div></div>);
	$self->_print_charts( $data, $temp, $params ) if $self->{'config'}->{'chartdirector'} && $header_displayed;
	return;
}

sub _update_totals {
	my ( $self, $data, $contig_info ) = @_;
	my ( $contigs, $sum, $mean, $lengths ) = @{$contig_info}{qw( contigs sum mean lengths )};
	push @{ $data->{'lengths'} }, @$lengths if ref $lengths;
	push @{ $data->{'contigs'} }, $contigs;
	push @{ $data->{'sum'} },     $sum;
	push @{ $data->{'mean'} },    $mean;
	return;
}

sub _get_html_table_header {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $labelfield = ucfirst( $self->{'system'}->{'labelfield'} );
	my $gc = $options->{'gc'} ? q(<th>Mean %GC</th>) : q();
	my $buffer =
	    q(<table class="tablesorter" id="sortTable"><thead>)
	  . qq(<tr><th>Isolate id</th><th>$labelfield</th><th>Contigs</th><th>Total length</th>);
	if ( $options->{'contig_analysis'} ) {
		$buffer .=
		    q(<th>Min</th>)
		  . q(<th>Max</th><th>Mean</th><th>&sigma;</th><th>N50 contig number</th><th>N50 contig length (L50)</th>)
		  . q(<th>N90 contig number</th><th>N90 contig length (L90)</th><th>N95 contig number</th>)
		  . q(<th>N95 contig length (L95)</th>);
	}
	$buffer .= qq($gc<th>Alleles designated</th><th>% Alleles designated</th>)
	  . q(<th>Loci tagged</th><th>% Loci tagged</th><th>Sequence bin</th></tr></thead><tbody>);
	return $buffer;
}

sub _get_html_table_row {
	my ( $self, $isolate_id, $contig_info, $td, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my ( $isolate_name, $contigs, $sum, $min, $max, $mean, $stddev, $single_isolate_lengths, $gc, $allele_designations,
		$percent_alleles, $tagged, $percent_tagged, $n_stats )
	  = @{$contig_info}{
		qw(isolate_name contigs sum min max mean stddev lengths gc
		  allele_designations percent_alleles tagged percent_tagged n_stats)
	  };
	my $q      = $self->{'cgi'};
	my $buffer = qq(<tr class="td$td"><td>$isolate_id</td><td>$isolate_name</td><td>$contigs</td>) . qq(<td>$sum</td>);
	if ( $options->{'contig_analysis'} ) {
		$buffer .= qq(<td>$min</td><td>$max</td><td>$mean</td>);
		$buffer .= defined $stddev ? qq(<td>$stddev</td>) : q(<td></td>);
		$buffer .= qq(<td>$n_stats->{'N50'}</td><td>$n_stats->{'L50'}</td><td>$n_stats->{'N90'}</td>)
		  . qq(<td>$n_stats->{'L90'}</td><td>$n_stats->{'N95'}</td><td>$n_stats->{'L95'}</td>);
	}
	$buffer .= qq(<td>$gc</td>) if $options->{'gc'};
	$buffer .=
	    qq(<td>$allele_designations</td><td>$percent_alleles</td><td>$tagged</td><td>$percent_tagged</td><td>)
	  . qq(<a href="$self->{'system'}->{'script_name'}?page=seqbin&amp;db=$self->{'instance'}&amp;)
	  . qq(isolate_id=$isolate_id" class="extract_tooltip" target="_blank">Display &rarr;</a></td></tr>);
	return $buffer;
}

sub _get_text_table_header {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $labelfield = ucfirst( $self->{'system'}->{'labelfield'} );
	my $gc         = $options->{'gc'} ? "%GC\t" : '';
	my $header     = qq(Isolate id\t$labelfield\tContigs\tTotal length);
	if ( $options->{'contig_analysis'} ) {
		$header .=
		    qq(\tMin\tMax\tMean\tStdDev\tN50 contig number\t)
		  . qq(N50 contig length (L50)\tN90 contig number\tN90 contig length (L90)\tN95 contig number\t)
		  . q(N95 contig length (L95));
	}
	$header .= qq(\t${gc}Alleles designated\t%Alleles designated\tLoci tagged\t%Loci tagged);
	return $header;
}

sub _get_text_table_row {
	my ( $self, $isolate_id, $contig_info, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my ( $isolate_name, $contigs, $sum, $min, $max, $mean, $stddev, $single_isolate_lengths, $gc, $allele_designations,
		$percent_alleles, $tagged, $percent_tagged, $n_stats )
	  = @{$contig_info}{
		qw(isolate_name contigs sum min max mean stddev lengths gc allele_designations
		  percent_alleles tagged percent_tagged n_stats)
	  };
	my $buffer = qq($isolate_id\t$isolate_name\t$contigs\t$sum);
	if ( $options->{'contig_analysis'} ) {
		$buffer .= qq(\t$min\t$max\t$mean\t);
		$buffer .= $stddev if defined $stddev;
		$buffer .= qq(\t$n_stats->{'N50'}\t$n_stats->{'L50'}\t$n_stats->{'N90'}\t$n_stats->{'L90'}\t)
		  . qq($n_stats->{'N95'}\t$n_stats->{'L95'});
	}
	$buffer .= qq(\t$gc) if $options->{'gc'};
	$buffer .= qq(\t$allele_designations\t$percent_alleles\t$tagged\t$percent_tagged);
	return $buffer;
}

sub _get_isolate_contig_data {
	my ( $self, $isolate_id, $loci, $statements, $arguments, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $values = [ $isolate_id, @$arguments ];
	my $q      = $self->{'cgi'};
	my $set_id = $self->get_set_id;
	my $data   = $self->{'datastore'}->run_query( $statements->{'contig_info'},
		$values, { fetch => 'row_hashref', cache => 'SeqbinBreakdown::contig_info' } );
	my %selected_loci = map { $_ => 1 } @$loci;
	if ( $data->{'contigs'} ) {

		if ( $options->{'contig_analysis'} ) {
			$data->{'lengths'} = $self->{'datastore'}->run_query( $statements->{'contig_lengths'},
				$values, { fetch => 'col_arrayref', cache => 'SeqbinBreakdown::contig_lengths' } );
		}
		$data->{'isolate_name'} = $self->get_isolate_name_from_id($isolate_id);
		my $allele_designations = $self->{'datastore'}->get_all_allele_ids( $isolate_id, { set_id => $set_id } );
		$data->{'allele_designations'} = 0;
		foreach my $locus ( keys %$allele_designations ) {
			$data->{'allele_designations'}++ if $selected_loci{$locus};
		}
		$data->{'percent_alleles'} =
		  @$loci ? BIGSdb::Utils::decimal_place( 100 * $data->{'allele_designations'} / @$loci, 1 ) : '-';
		my $allele_sequences = $self->{'datastore'}->get_all_allele_sequences($isolate_id);
		$data->{'tagged'} = 0;
		foreach my $locus ( keys %$allele_sequences ) {
			$data->{'tagged'}++ if $selected_loci{$locus};
		}
		$data->{'percent_tagged'} = @$loci ? BIGSdb::Utils::decimal_place( 100 * $data->{'tagged'} / @$loci, 1 ) : '-';
		$data->{'n_stats'} = BIGSdb::Utils::get_N_stats( $data->{'sum'}, $data->{'lengths'} );
	}
	if ( $options->{'gc'} ) {
		my $gc_value = $self->{'datastore'}
		  ->run_query( $statements->{'gc'}, $values, { fetch => 'row_array', cache => 'SeqbinBreakdown::gc' } );
		$data->{'gc'} = BIGSdb::Utils::decimal_place( ( $gc_value // 0 ) * 100, 1 );
	}
	return $data;
}

sub _get_query_statements {
	my ( $self, $args ) = @_;
	my ( $method, $experiment, $contig_analysis ) = @{$args}{qw (seq_method_list experiment_list contig_analysis)};
	my $exclusion_clause = '';
	my $arguments        = [];
	my $use_seqbin_table;
	if ($method) {
		if ( !any { $_ eq $method } SEQ_METHODS ) {
			$logger->error("Invalid method $method");
			return;
		}
		$exclusion_clause .= ' AND method=?';
		push @$arguments, $method;
		$use_seqbin_table = 1;
	}
	if ($experiment) {
		if ( !BIGSdb::Utils::is_int($experiment) ) {
			$logger->error("Invalid experiment $experiment");
			return;
		}
		$exclusion_clause .= ' AND experiment_id=?';
		push @$arguments, $experiment;
		$use_seqbin_table = 1;
	}
	my $statements = {
		contig_lengths => q[SELECT length(sequence) FROM sequence_bin LEFT JOIN experiment_sequences ]
		  . qq[ON sequence_bin.id=seqbin_id WHERE isolate_id=?$exclusion_clause ORDER BY length(sequence) DESC],
		gc => q[select SUM(CAST(length(regexp_replace(sequence,'[^GCgc]+','','g')) AS float))/]
		  . q[GREATEST(SUM(length(sequence)),1) AS gc FROM sequence_bin LEFT JOIN experiment_sequences ON ]
		  . qq[sequence_bin.id=seqbin_id WHERE isolate_id=?$exclusion_clause GROUP BY isolate_id ]
	};
	if ( $contig_analysis || $use_seqbin_table ) {
		$statements->{'contig_info'} =
		    q[SELECT COUNT(sequence) AS contigs, SUM(length(sequence)) AS sum,MIN(length(sequence)) ]
		  . q[AS min,MAX(length(sequence)) AS max, CEIL(AVG(length(sequence))) AS mean, ]
		  . q[CEIL(STDDEV_SAMP(length(sequence))) AS stddev FROM sequence_bin LEFT JOIN ]
		  . qq[experiment_sequences ON sequence_bin.id=seqbin_id WHERE isolate_id=?$exclusion_clause];
	} else {
		$statements->{'contig_info'} = q[SELECT contigs,total_length AS sum FROM seqbin_stats WHERE isolate_id=?];
	}
	return ( $statements, $arguments );
}

sub _get_rounded_width {
	my ( $self, $width );
	$width //= 0;
	return 5   if $width < 50;
	return 10  if $width < 100;
	return 50  if $width < 500;
	return 100 if $width < 1000;
	return 500 if $width < 5000;
	return 1000;
}

sub _make_chart {
	my ( $self, $data, $prefix, $type, $params ) = @_;
	my %title = (
		contigs => 'Number of contigs',
		sum     => 'Total length',
		mean    => 'Mean contig length',
		lengths => 'Contig lengths'
	);
	my $stats      = BIGSdb::Utils::stats( $data->{$type} );
	my $chart_data = {};
	if ( $stats->{'count'} ) {
		my $bins =
		  ceil( ( 3.5 * $stats->{'std'} ) / $stats->{'count'}**0.33 )
		  ;    #Scott's choice [Scott DW (1979). On optimal and data-based histograms. Biometrika 66(3):605–610]
		$bins = 100 if $bins > 100;
		$bins = 1   if !$bins;
		my $width            = ( $stats->{'max'} - $stats->{'min'} ) / $bins;
		my $round_to_nearest = $self->_get_rounded_width($width);
		$width = int( $width - ( $width % $round_to_nearest ) ) || $round_to_nearest;
		my ( $histogram, $min, $max ) = BIGSdb::Utils::histogram( $width, $data->{$type} );
		my ( @labels, @values );

		foreach my $i ( $min .. $max ) {
			push @labels, $i * $width;
			push @values, $histogram->{$i};
		}
		my %prefs = ( offset_label => 1, 'x-title' => $title{$type}, 'y-title' => 'Frequency' );
		$chart_data->{'file_name'} = "$prefix\_histogram_$type.png";
		my $full_filename = "$self->{'config'}->{'tmp_dir'}/$chart_data->{'file_name'}";
		$chart_data->{'title'} = $title{$type};
		BIGSdb::Charts::barchart( \@labels, \@values, $full_filename, 'large', \%prefs, { no_transparent => 1 } );
		$chart_data->{'mean'} =
		    BIGSdb::Utils::decimal_place( $stats->{'mean'}, 1 )
		  . '; &sigma;: '
		  . BIGSdb::Utils::decimal_place( $stats->{'std'}, 1 );
		if ( $type eq 'lengths' ) {
			my $filename  = "${prefix}_lengths.txt";
			my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
			if ( open( my $fh, '>', $full_path ) ) {
				foreach my $length ( sort { $a <=> $b } @{ $data->{'lengths'} } ) {
					say $fh $length;
				}
				close $fh;
				$chart_data->{'lengths_file'} = $filename;
			} else {
				$logger->error("Can't open $full_path for writing");
			}
		}
	}
	return $chart_data;
}

sub _print_charts {
	my ( $self, $data, $prefix, $params ) = @_;
	say q(<div class="box" id="resultsfooter">);
	say q(<p>Click on the following charts to enlarge</p>);
	my @types = qw(contigs sum);
	push @types, qw(mean lengths) if $params->{'contig_analysis'};
	foreach my $type (@types) {
		my $chart_data = $self->_make_chart( $data, $prefix, $type, $params );
		say q(<div style="float:left;padding-right:1em">);
		say qq(<h2>$chart_data->{'title'}</h2>);
		say qq(Overall mean: $chart_data->{'mean'}<br />);
		say qq(<a href="/tmp/$prefix\_histogram_$type.png" data-rel="lightbox-1" class="lightbox" )
		  . qq(title="$chart_data->{'title'}"><img src="/tmp/$prefix\_histogram_$type.png" alt="$type histogram" )
		  . q(style="width:200px; border:1px dashed black" /></a>);
		if ( $chart_data->{'lengths_file'} ) {
			my $lengths_full_path = "$self->{'config'}->{'tmp_dir'}/$chart_data->{'lengths_file'}";
			say qq(<p><a href="/tmp/$chart_data->{'lengths_file'}">Download lengths</a></p>)
			  if -e $lengths_full_path && !-z $lengths_full_path;
		}
		say q(</div>);
	}
	say q(<div style="clear:both"></div></div>);
	return;
}
1;
