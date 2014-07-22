#SeqbinBreakdown.pm - SeqbinBreakdown plugin for BIGSdb
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
package BIGSdb::Plugins::SeqbinBreakdown;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin BIGSdb::SeqbinPage);
use Log::Log4perl qw(get_logger);
use POSIX qw(ceil);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use BIGSdb::Page qw(SEQ_METHODS);
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
		version     => '1.1.0',
		dbtype      => 'isolates',
		section     => 'breakdown,postquery',
		input       => 'query',
		order       => 80,
		requires    => 'offline_jobs',
		system_flag => 'SeqbinBreakdown'
	);
	return \%att;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub run {
	my ($self) = @_;
	say "<h1>Breakdown of sequence bin contig properties</h1>";
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
			$error .= "<p>You must include one or more isolates. Make sure your selected isolates haven't been filtered to none by "
			  . "selecting a project.</p>\n";
		}
		if (@$invalid_ids) {
			local $" = ', ';
			$error .= "<p>The following isolates in your pasted list are invalid: @$invalid_ids.</p>";
		}
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
			} else {
				$self->_print_interface;
				$self->_print_table( \@$filtered_ids, $params );
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
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1 } ) x 3;    #Allow temp files to be cleaned on kill signals
	my $method     = $params->{'seq_method_list'};
	my $experiment = $params->{'experiment_list'};
	$self->_initiate_statement_handles( { method => $method, experiment => $experiment } );
	$self->{'system'}->{'script_name'} = $params->{'script_name'};
	my $isolate_ids = $self->{'jobManager'}->get_job_isolates($job_id);
	my ( $html_buffer, $text_buffer );
	my $td            = 1;
	my $data          = {};
	my $row           = 0;
	my $row_with_data = 0;
	my $disabled_html = @$isolate_ids > MAX_HTML_OUTPUT ? 1 : 0;

	if ($disabled_html) {
		$self->{'jobManager'}
		  ->update_job_status( $job_id, { message_html => "HTML output disabled as more than " . MAX_HTML_OUTPUT . " records selected." } );
	}
	foreach my $id (@$isolate_ids) {
		my $contig_info = $self->_get_isolate_contig_data($id);
		my ( $isolate_name, $contigs, $sum, $min, $max, $mean, $stddev, $single_isolate_lengths, $percent_alleles, $percent_tagged,
			$n_stats )
		  = @{$contig_info}{qw(isolate_name contigs sum min max mean stddev lengths percent_alleles percent_tagged n_stats)};
		$row++;
		next if !$contigs;
		$row_with_data++;
		$html_buffer .= $self->_get_html_table_row( $id, $contig_info, $td ) . "\n";
		$text_buffer .= $self->_get_text_table_row( $id, $contig_info ) . "\n";
		$td = $td == 1 ? 2 : 1;
		$self->_update_totals( $data, $contig_info );
		my $html_message = $self->_get_html_table_header . $html_buffer . "</tbody></table>";
		my $complete     = int( $row * 100 / @$isolate_ids );

		if ( $row % 20 == 0 || $row == @$isolate_ids ) {
			if ($disabled_html) {
				$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => $complete } );
			} else {
				$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => $complete, message_html => $html_message } );
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
		$self->{'jobManager'}
		  ->update_job_status( $job_id, { message_html => 'There are no records with contigs matching your criteria.' } );
	} else {
		my $job_file = "$self->{'config'}->{'tmp_dir'}/$job_id\.txt";
		open( my $job_fh, '>', $job_file ) || $logger->error("Can't open $job_file for writing");
		say $job_fh $self->_get_text_table_header;
		print $job_fh $text_buffer;
		close $job_fh;
		$self->{'jobManager'}
		  ->update_job_output( $job_id, { filename => "$job_id.txt", description => '01_Output in tab-delimited text format' } );
		my $excel_file =
		  BIGSdb::Utils::text2excel( $job_file, { worksheet => 'sequence bin stats', tmp_dir => $self->{'config'}->{'secure_tmp_dir'} } );
		if ( -e $excel_file ) {
			$self->{'jobManager'}->update_job_output( $job_id, { filename => "$job_id.xlsx", description => '02_Output in Excel format' } );
		}
		my $file_order = 10;
		foreach my $type (qw (contigs sum mean lengths)) {
			my $prefix = BIGSdb::Utils::get_random();
			my $chart_data = $self->_make_chart( $data, $prefix, $type );
			if ( $chart_data->{'file_name'} ) {
				my $full_filename = "$self->{'config'}->{'tmp_dir'}/$chart_data->{'file_name'}";
				if ( -e $full_filename ) {
					$self->{'jobManager'}->update_job_output( $job_id,
						{ filename => $chart_data->{'file_name'}, description => "$file_order\_$chart_data->{'title'}" } );
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
		say "<div class=\"box\" id=\"statusbad\"><p>Error retrieving query.</p></div>";
		return;
	}
	my $qry = $$qry_ref;
	$qry =~ s/ORDER BY.*$//g;
	$logger->debug("Breakdown query: $qry");
	my $view = $self->{'system'}->{'view'};
	$qry =~ s/SELECT ($view\.\*|\*)/SELECT id/;
	$qry .= " ORDER BY id";
	my $selected_ids;

	if ( $q->param('isolate_id') ) {
		my @ids = $q->param('isolate_id');
		$selected_ids = \@ids;
	} elsif ( defined $query_file ) {
		$selected_ids = $self->get_ids_from_query($qry_ref);
	} else {
		$selected_ids = [];
	}
	my $seqbin_exists = $self->{'datastore'}->run_query("SELECT EXISTS(SELECT * FROM sequence_bin WHERE isolate_id IN ($qry))");
	if ( !$seqbin_exists ) {
		say qq(<div class="box" id="statusbad"><p>There are no sequences stored for any of the selected isolates generated with )
		  . qq(the sequence method (set in options).</p></div>);
		return;
	}
	say qq(<div class="box" id="queryform">);
	say qq(<p>Please select the required isolate ids for comparison - use Ctrl or Shift to make multiple selections.</p>);
	say qq(<div class="scrollable">);
	say $q->start_form;
	$self->print_seqbin_isolate_fieldset( { selected_ids => $selected_ids, isolate_paste_list => 1 } );
	$self->print_sequence_filter_fieldset;
	$self->print_action_fieldset( { name => 'SeqbinBreakdown' } );
	say $q->hidden($_) foreach qw (page name db set_id);
	say $q->end_form;
	say "</div></div>";
	return;
}

sub _print_table {
	my ( $self, $ids, $params ) = @_;
	my $method     = $params->{'seq_method_list'};
	my $experiment = $params->{'experiment_list'};
	$self->_initiate_statement_handles( { method => $method, experiment => $experiment } );
	my $temp = BIGSdb::Utils::get_random();
	my $td   = 1;
	local $| = 1;
	my $data             = {};
	my $header_displayed = 0;
	say qq(<div class="box" id="resultstable"><div class="scrollable">);
	my $text_file = "$self->{'config'}->{'tmp_dir'}/$temp.txt";
	open( my $fh, '>', $text_file ) or $logger->error("Can't open temp file $text_file for writing");

	foreach my $id (@$ids) {
		my $contig_info = $self->_get_isolate_contig_data($id);
		my ( $isolate_name, $contigs, $sum, $min, $max, $mean, $stddev, $single_isolate_lengths, $percent_alleles, $percent_tagged,
			$n_stats )
		  = @{$contig_info}{qw(isolate_name contigs sum min max mean stddev lengths percent_alleles percent_tagged n_stats)};
		next if !$contigs;
		if ( !$header_displayed ) {
			say $fh $self->_get_text_table_header;
			say $self->_get_html_table_header;
			$header_displayed = 1;
		}
		say $self->_get_html_table_row( $id, $contig_info, $td );
		say $fh $self->_get_text_table_row( $id, $contig_info );
		$td = $td == 1 ? 2 : 1;
		$self->_update_totals( $data, $contig_info );
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
	}
	close $fh;
	if ($header_displayed) {
		say "</tbody></table>";
		say qq(<ul><li><a href="/tmp/$temp.txt">Download in tab-delimited text format</a></li>);
		my $excel_file =
		  BIGSdb::Utils::text2excel( $text_file, { worksheet => 'sequence bin stats', tmp_dir => $self->{'config'}->{'secure_tmp_dir'} } );
		if ( -e $excel_file ) {
			say qq(<li><a href="/tmp/$temp.xlsx">Download in Excel format</a></li>);
		}
		say "</ul>";
	} else {
		say "<p>There are no records with contigs matching your criteria.</p>";
	}
	say "</div></div>";
	$self->_print_charts( $data, $temp ) if $self->{'config'}->{'chartdirector'} && $header_displayed;
	return;
}

sub _update_totals {
	my ( $self, $data, $contig_info ) = @_;
	my ( $contigs, $sum, $mean, $lengths ) = @{$contig_info}{qw( contigs sum mean lengths )};
	push @{ $data->{'lengths'} }, @$lengths;
	push @{ $data->{'contigs'} }, $contigs;
	push @{ $data->{'sum'} },     $sum;
	push @{ $data->{'mean'} },    $mean;
	return;
}

sub _get_html_table_header {
	my ($self)     = @_;
	my $labelfield = ucfirst( $self->{'system'}->{'labelfield'} );
	my $buffer     = << "HTML";
<table class="tablesorter" id="sortTable">
<thead>
<tr><th>Isolate id</th><th>$labelfield</th><th>Contigs</th><th>Total length</th><th>Min</th><th>Max</th><th>Mean</th><th>&sigma;</th>
<th>N50</th><th>N90</th><th>N95</th><th>% Alleles designated</th><th>% Loci tagged</th><th>Sequence bin</th></tr>
</thead>
<tbody>
HTML
	return $buffer;
}

sub _get_html_table_row {
	my ( $self, $isolate_id, $contig_info, $td ) = @_;
	my ( $isolate_name, $contigs, $sum, $min, $max, $mean, $stddev, $single_isolate_lengths, $percent_alleles, $percent_tagged, $n_stats ) =
	  @{$contig_info}{qw(isolate_name contigs sum min max mean stddev lengths percent_alleles percent_tagged n_stats)};
	my $buffer = "<tr class=\"td$td\"><td>$isolate_id</td><td>$isolate_name</td><td>$contigs</td><td>$sum</td><td>$min</td>"
	  . "<td>$max</td><td>$mean</td>";
	$buffer .= defined $stddev ? "<td>$stddev</td>" : '<td></td>';
	$buffer .=
	    "<td>$n_stats->{'N50'}</td><td>$n_stats->{'N90'}</td><td>$n_stats->{'N95'}</td><td>$percent_alleles</td>"
	  . "<td>$percent_tagged</td><td><a href=\"$self->{'system'}->{'script_name'}?page=seqbin&amp;db=$self->{'instance'}&amp;"
	  . "isolate_id=$isolate_id\" class=\"extract_tooltip\" target=\"_blank\">Display &rarr;</a></td></tr>";
	return $buffer;
}

sub _get_text_table_header {
	my ($self) = @_;
	my $labelfield = ucfirst( $self->{'system'}->{'labelfield'} );
	return "Isolate id\t$labelfield\tContigs\tTotal length\tMin\tMax\tMean\tStdDev\tN50\tN90\tN95\t%Allele designated\t%Loci tagged";
}

sub _get_text_table_row {
	my ( $self, $isolate_id, $contig_info ) = @_;
	my ( $isolate_name, $contigs, $sum, $min, $max, $mean, $stddev, $single_isolate_lengths, $percent_alleles, $percent_tagged, $n_stats ) =
	  @{$contig_info}{qw(isolate_name contigs sum min max mean stddev lengths percent_alleles percent_tagged n_stats)};
	my $buffer = "$isolate_id\t$isolate_name\t$contigs\t$sum\t$min\t$max\t$mean\t";
	$buffer .= "$stddev" if defined $stddev;
	$buffer .= "\t$n_stats->{'N50'}\t$n_stats->{'N90'}\t$n_stats->{'N95'}\t$percent_alleles\t$percent_tagged";
	return $buffer;
}

sub _get_isolate_contig_data {
	my ( $self, $isolate_id ) = @_;
	eval { $self->{'sql'}->{'contig_info'}->execute( $isolate_id, @{ $self->{'criteria'} } ) };
	$logger->error($@) if $@;
	my $set_id = $self->get_set_id;
	my $data   = $self->{'sql'}->{'contig_info'}->fetchrow_hashref;
	if ( !$self->{'cache'}->{'loci'} ) {
		$self->{'cache'}->{'loci'} = $self->{'datastore'}->get_loci( { set_id => $set_id } );
	}
	if ( $data->{'contigs'} ) {
		$data->{'lengths'}      = $self->_get_contig_lengths($isolate_id);
		$data->{'isolate_name'} = $self->get_isolate_name_from_id($isolate_id);
		my $allele_designations = $self->{'datastore'}->get_all_allele_ids( $isolate_id, { set_id => $set_id } );
		$data->{'percent_alleles'} =
		  BIGSdb::Utils::decimal_place( 100 * ( scalar keys %$allele_designations ) / @{ $self->{'cache'}->{'loci'} }, 1 );
		my $tagged = $self->_get_tagged($isolate_id);
		$data->{'percent_tagged'} = BIGSdb::Utils::decimal_place( 100 * ( $tagged / @{ $self->{'cache'}->{'loci'} } ), 1 );
		$data->{'n_stats'} = BIGSdb::Utils::get_N_stats( $data->{'sum'}, $data->{'lengths'} );
	}
	return $data;
}

sub _get_contig_lengths {
	my ( $self, $isolate_id ) = @_;
	eval { $self->{'sql'}->{'contig_lengths'}->execute( $isolate_id, @{ $self->{'criteria'} } ) };
	$logger->error($@) if $@;
	my @lengths;
	while ( my ($length) = $self->{'sql'}->{'contig_lengths'}->fetchrow_array ) {
		push @lengths, $length;
	}
	return \@lengths;
}

sub _get_tagged {
	my ( $self, $isolate_id ) = @_;
	eval { $self->{'sql'}->{'tagged'}->execute($isolate_id) };
	$logger->error($@) if $@;
	my ($tagged) = $self->{'sql'}->{'tagged'}->fetchrow_array;
	return $tagged;
}

sub _initiate_statement_handles {
	my ( $self,   $args )       = @_;
	my ( $method, $experiment ) = @{$args}{qw (method experiment)};
	my $exclusion_clause = '';
	if ($method) {
		if ( !any { $_ eq $method } SEQ_METHODS ) {
			$logger->error("Invalid method $method");
			return;
		}
		$exclusion_clause .= " AND method=?";
		push @{ $self->{'criteria'} }, $method;
	}
	if ($experiment) {
		if ( !BIGSdb::Utils::is_int($experiment) ) {
			$logger->error("Invalid experiment $experiment");
			return;
		}
		$exclusion_clause .= " AND experiment_id=?";
		push @{ $self->{'criteria'} }, $experiment;
	}
	$self->{'sql'}->{'contig_info'} =
	  $self->{'db'}->prepare(
		    "SELECT COUNT(sequence) AS contigs, SUM(length(sequence)) AS sum,MIN(length(sequence)) AS min,MAX(length(sequence)) AS max, "
		  . "CEIL(AVG(length(sequence))) AS mean, CEIL(STDDEV_SAMP(length(sequence))) AS stddev FROM sequence_bin LEFT JOIN "
		  . "experiment_sequences ON sequence_bin.id=seqbin_id WHERE isolate_id=?$exclusion_clause" );
	$self->{'sql'}->{'contig_lengths'} =
	  $self->{'db'}->prepare( "SELECT length(sequence) FROM sequence_bin LEFT JOIN experiment_sequences "
		  . "ON sequence_bin.id=seqbin_id WHERE isolate_id=?$exclusion_clause ORDER BY length(sequence) DESC" );
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? "AND (locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes "
	  . "WHERE set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';
	$self->{'sql'}->{'tagged'} =
	  $self->{'db'}->prepare("SELECT COUNT(DISTINCT locus) FROM allele_sequences WHERE isolate_id=? $set_clause");
	return;
}

sub _make_chart {
	my ( $self, $data, $prefix, $type ) = @_;
	my %title      = ( contigs => 'Number of contigs', sum => 'Total length', mean => 'Mean contig length', lengths => 'Contig lengths' );
	my $stats      = BIGSdb::Utils::stats( $data->{$type} );
	my $chart_data = {};
	if ( $stats->{'count'} ) {
		my $bins =
		  ceil( ( 3.5 * $stats->{'std'} ) / $stats->{'count'}**0.33 )
		  ;    #Scott's choice [Scott DW (1979). On optimal and data-based histograms. Biometrika 66(3):605–610]
		$bins = 100 if $bins > 100;
		$bins = 1   if !$bins;
		my $width = ( $stats->{'max'} - $stats->{'min'} ) / $bins;
		my $round_to_nearest;
		if ( $width < 50 ) {
			$round_to_nearest = 5;
		} elsif ( $width < 100 ) {
			$round_to_nearest = 10;
		} elsif ( $width < 500 ) {
			$round_to_nearest = 50;
		} elsif ( $width < 1000 ) {
			$round_to_nearest = 100;
		} elsif ( $width < 5000 ) {
			$round_to_nearest = 500;
		} else {
			$round_to_nearest = 1000;
		}
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
		  BIGSdb::Utils::decimal_place( $stats->{'mean'}, 1 ) . "; &sigma;: " . BIGSdb::Utils::decimal_place( $stats->{'std'}, 1 );
		if ( $type eq 'lengths' ) {
			my $filename  = "$prefix\_lengths.txt";
			my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
			if ( open( my $fh, '>', $full_path ) ) {
				foreach my $length ( sort { $a <=> $b } @{ $data->{'lengths'} } ) {
					print $fh "$length\n";
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
	my ( $self, $data, $prefix ) = @_;
	say "<div class=\"box\" id=\"resultsfooter\">";
	say "<p>Click on the following charts to enlarge</p>";
	foreach my $type (qw (contigs sum mean lengths)) {
		my $chart_data = $self->_make_chart( $data, $prefix, $type );
		say "<div style=\"float:left;padding-right:1em\">";
		say "<h2>$chart_data->{'title'}</h2>";
		say "Overall mean: $chart_data->{'mean'}<br />";
		say "<a href=\"/tmp/$prefix\_histogram_$type.png\" data-rel=\"lightbox-1\" class=\"lightbox\" title=\"$chart_data->{'title'}\">"
		  . "<img src=\"/tmp/$prefix\_histogram_$type.png\" alt=\"$type histogram\" style=\"width:200px; border:1px dashed black\" /></a>";
		if ( $chart_data->{'lengths_file'} ) {
			my $lengths_full_path = "$self->{'config'}->{'tmp_dir'}/$chart_data->{'lengths_file'}";
			say "<p><a href=\"/tmp/$chart_data->{'lengths_file'}\">Download lengths</a></p>"
			  if -e $lengths_full_path && !-z $lengths_full_path;
		}
		say "</div>";
	}
	say "<div style=\"clear:both\"></div></div>";
	return;
}
1;
