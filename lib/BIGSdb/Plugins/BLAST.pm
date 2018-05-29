#BLAST.pm - BLAST plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2018, University of Oxford
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
package BIGSdb::Plugins::BLAST;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use Apache2::Connection ();
use List::MoreUtils qw(any uniq);
use constant MAX_INSTANT_RUN  => 10;
use constant MAX_DISPLAY_TAXA => 1000;
use constant MAX_TAXA         => 10_000;
use constant MAX_QUERY_LENGTH => 100_000;
use BIGSdb::Constants qw(SEQ_METHODS FLANKING);
{
	no warnings 'qw';
	use constant BLASTN_SCORES => qw(
	  1,-5,3,3
	  1,-4,1,2
	  1,-4,0,2
	  1,-4,2,1
	  1,-4,1,1
	  2,-7,2,4
	  2,-7,0,4
	  2,-7,4,2
	  2,-7,2,2
	  1,-3,2,2
	  1,-3,1,2
	  1,-3,0,2
	  1,-3,2,1
	  1,-3,1,1
	  2,-5,2,4
	  2,-5,0,4
	  2,-5,4,2
	  2,-5,2,2
	  1,-2,2,2
	  1,-2,1,2
	  1,-2,0,2
	  1,-2,3,1
	  1,-2,2,1
	  1,-2,1,1
	  2,-3,4,4
	  2,-3,2,4
	  2,-3,0,4
	  2,-3,3,3
	  2,-3,6,2
	  2,-3,5,2
	  2,-3,4,2
	  2,-3,2,2
	  3,-4,6,3
	  3,-4,5,3
	  3,-4,4,3
	  3,-4,6,2
	  3,-4,5,2
	  3,-4,4,2
	  4,-5,6,5
	  4,-5,5,5
	  4,-5,4,5
	  4,-5,3,5
	  1,-1,3,2
	  1,-1,2,2
	  1,-1,1,2
	  1,-1,0,2
	  1,-1,4,1
	  1,-1,3,1
	  1,-1,2,1
	  3,-2,5,5
	  5,-4,10,6
	  5,-4,8,6
	);
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 1, query_field => 0 };
	return;
}

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name        => 'BLAST',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'BLAST a query sequence against selected isolate data',
		category    => 'Analysis',
		buttontext  => 'BLAST',
		menutext    => 'BLAST',
		module      => 'BLAST',
		version     => '1.4.4',
		dbtype      => 'isolates',
		section     => 'analysis,postquery',
		input       => 'query',
		order       => 32,
		help        => 'tooltips',
		system_flag => 'BLAST',
		url         => "$self->{'config'}->{'doclink'}/data_analysis.html#blast",
		requires    => 'offline_jobs',
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

END
	return $buffer;
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>BLAST</h1>);
	if ( !( $q->param('submit') && $q->param('sequence') ) ) {
		$self->_print_interface;
		return;
	}
	my @ids = $q->param('isolate_id');
	my ( $pasted_cleaned_ids, $invalid_ids ) = $self->get_ids_from_pasted_list( { dont_clear => 1 } );
	push @ids, @$pasted_cleaned_ids;
	@ids = uniq @ids;
	if (@$invalid_ids) {
		local $" = ', ';
		$self->print_bad_status(
			{ message => qq(The following isolates in your pasted list are invalid: @$invalid_ids.) } );
		$self->_print_interface;
		return;
	}
	if ( !@ids ) {
		$self->print_bad_status( { message => q(You must select one or more isolates.) } );
		$self->_print_interface;
		return;
	}
	if ( @ids > MAX_TAXA ) {
		my $selected = BIGSdb::Utils::commify( scalar @ids );
		my $limit    = BIGSdb::Utils::commify(MAX_TAXA);
		$self->print_bad_status(
			{ message => qq(Analysis is restricted to $limit isolates. You have selected $selected.) } );
		$self->_print_interface;
		return;
	}
	if ( length $q->param('sequence') > MAX_QUERY_LENGTH ) {
		my $limit = BIGSdb::Utils::commify(MAX_QUERY_LENGTH);
		$self->print_bad_status( { message => qq(Query sequence is limited to a maximum of $limit characters.) } )
		  ;
		$self->_print_interface;
		return;
	}
	my @includes = $q->param('includes');
	my $seq      = $q->param('sequence');
	if ( @ids > MAX_INSTANT_RUN || $q->param('tblastx') ) {
		my $att       = $self->get_attributes;
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		$q->delete('isolate_paste_list');
		$q->delete('isolate_id');
		my $params = $q->Vars;
		$params->{'script_name'} = $self->{'system'}->{'script_name'};
		my $job_id = $self->{'jobManager'}->add_job(
			{
				dbase_config => $self->{'instance'},
				ip_address   => $q->remote_host,
				module       => $att->{'module'},
				priority     => $att->{'priority'},
				parameters   => $params,
				username     => $self->{'username'},
				email        => $user_info->{'email'},
				isolates     => \@ids
			}
		);
		say $self->get_job_redirect($job_id);
		return;
	}
	$self->_print_interface;
	my $prefix = BIGSdb::Utils::get_random();
	$self->_run_now(
		{
			prefix         => $prefix,
			ids            => \@ids,
			includes       => \@includes,
			seq_ref        => \$seq,
			show_no_match  => ( $q->param('show_no_match') // 0 ),
			flanking       => ( $q->param('flanking') // $self->{'prefs'}->{'flanking'} ),
			include_seqbin => ( $q->param('include_seqbin') // 0 )
		}
	);
	return;
}

sub _get_headers {
	my ( $self, $includes ) = @_;
	my %labels;
	foreach my $field (@$includes) {
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
		$labels{$field} = $metafield;
	}
	my ( $scheme_fields, $scheme_labels ) =
	  $self->get_field_selection_list( { scheme_fields => 1, analysis_pref => 1, ignore_prefs => 1 } );
	$labels{$_} = $scheme_labels->{$_} foreach @$scheme_fields;
	my $html_buffer   = qq(<table class="resultstable">\n);
	my $display_label = ucfirst( $self->{'system'}->{'labelfield'} );
	$html_buffer .= qq(<tr><th>Isolate id</th><th>$display_label</th>);
	$html_buffer .= q(<th>) . ( $labels{$_} // $_ ) . q(</th>) foreach @$includes;
	$html_buffer .= q(<th>% identity</th><th>Alignment length</th><th>Mismatches</th><th>Gaps</th><th>Seqbin id</th>)
	  . qq(<th>Start</th><th>End</th><th>Orientation</th><th>E-value</th><th>Bit score</th></tr>\n);
	my $text_buffer = "Isolate id\t$display_label\t";
	$text_buffer .= ( $labels{$_} // $_ ) . "\t" foreach @$includes;
	$text_buffer .=
	  "% identity\tAlignment length\tMismatches\tGaps\tSeqbin id\tStart\tEnd\tOrientation\tE-value\tBit score\n";
	return ( $html_buffer, $text_buffer );
}

sub _run_now {
	my ( $self, $args ) = @_;
	my ( $prefix, $ids, $includes, $seq_ref, $show_no_match, $flanking, $include_seqbin ) =
	  @{$args}{qw(prefix ids includes seq_ref show_no_match flanking include_seqbin)};
	my ( $html_header, $text_header ) = $self->_get_headers($includes);
	my $out_file                 = "$prefix.txt";
	my $out_file_flanking        = "$prefix\_flanking.txt";
	my $out_file_table           = "$prefix\_table.txt";
	my $out_file_table_full_path = "$self->{'config'}->{'tmp_dir'}/$out_file_table";
	my $file_buffer              = $text_header;
	my $first                    = 1;
	my $some_results             = 0;
	my $td                       = 1;
	my $params                   = $self->{'cgi'}->Vars;
	say q(<div class="box" id="resultstable">);

	foreach my $id (@$ids) {
		my $matches = $self->_blast( $id, $seq_ref, $params );
		next if !$show_no_match && ( ref $matches ne 'ARRAY' || !@$matches );
		print $html_header if $first;
		my $include_values = $self->_get_include_values( \@$includes, $id );
		$some_results = 1;
		my $rows        = @$matches;
		my $first_match = 1;
		foreach my $match (@$matches) {
			say $self->_get_prov_html_cells(
				{
					isolate_id     => $id,
					td             => $td,
					include_values => $include_values,
					is_match       => 1,
					rows           => $rows,
					first_match    => $first_match
				}
			);
			$file_buffer .= $self->_get_prov_text_cells( { isolate_id => $id, include_values => $include_values } );
			say $self->_get_match_attribute_html_cells( $match, $flanking );
			$file_buffer .= $self->_get_match_attribute_text_cells( $match, $flanking );
			$file_buffer .= qq(\n);
			$self->_append_fasta(
				{
					isolate_id        => $id,
					include_values    => $include_values,
					match             => $match,
					flanking          => $flanking,
					out_file          => $out_file,
					out_file_flanking => $out_file_flanking,
					include_seqbin    => $include_seqbin
				}
			);
			$first_match = 0;
		}
		if ( !@$matches ) {
			say $self->_get_prov_html_cells( { isolate_id => $id, td => $td, include_values => $include_values } );
			say q(<td>0</td><td colspan="9" /></tr>);
			$file_buffer .= $self->_get_prov_text_cells( { isolate_id => $id, include_values => $include_values } );
			$file_buffer .= qq(\t0\n);
		}
		$td = $td == 1 ? 2 : 1;
		$first = 0;
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
	}
	open( my $fh_output_table, '>', $out_file_table_full_path )
	  or $logger->error("Can't open temp file $out_file_table_full_path for writing");
	say $fh_output_table $file_buffer;
	close $fh_output_table;
	if ($some_results) {
		say q(</table>);
		say q(<p style="margin-top:1em">Download );
		say qq(<a href="/tmp/$out_file" target="_blank">FASTA</a> | ) if -e "$self->{'config'}->{'tmp_dir'}/$out_file";
		say qq(<a href="/tmp/$out_file_flanking" target="_blank">FASTA with flanking</a>)
		  . $self->get_tooltip( q(Flanking sequence - You can change the amount of flanking )
			  . q(sequence exported by selecting the appropriate length in the options page.) )
		  . q( | )
		  if -e "$self->{'config'}->{'tmp_dir'}/$out_file_flanking";
		say qq(<a href="/tmp/$out_file_table" target="_blank">Table (tab-delimited text)</a>);
		my $excel =
		  BIGSdb::Utils::text2excel( $out_file_table_full_path,
			{ worksheet => 'BLAST', tmp_dir => $self->{'config'}->{'secure_tmp_dir'} } );
		say qq(| <a href="/tmp/$prefix\_table.xlsx">Excel format</a>) if -e $excel;
		say q(</p>);
	} else {
		say q(<p>No matches found.</p>);
	}
	say q(</div>);
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	$self->{'exit'} = 0;

	#Terminate cleanly on kill signals
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1 } ) x 3;
	$self->{'system'}->{'script_name'} = $params->{'script_name'};
	my @includes = split /\|\|/x, ( $params->{'includes'} // q() );
	my ( $html_header, $text_header ) = $self->_get_headers( \@includes );
	my $out_file                 = "$job_id.txt";
	my $out_file_flanking        = "${job_id}_flanking.txt";
	my $out_file_table           = "${job_id}_table.txt";
	my $out_file_table_full_path = "$self->{'config'}->{'tmp_dir'}/$out_file_table";
	my $html_buffer;
	my $file_buffer  = $text_header;
	my $first        = 1;
	my $some_results = 0;
	my $td           = 1;
	my $ids          = $self->{'jobManager'}->get_job_isolates($job_id);
	my $flanking     = BIGSdb::Utils::is_int( $params->{'flanking'} ) ? $params->{'flanking'} : 100;
	my $progress     = 0;

	if ( @$ids > MAX_DISPLAY_TAXA ) {
		my $max_display_taxa = MAX_DISPLAY_TAXA;
		$self->{'jobManager'}->update_job_status( $job_id,
			{ message_html => "<p>Dynamically updated output disabled as >$max_display_taxa taxa selected.</p>" } );
	}
	foreach my $id (@$ids) {
		$progress++;
		my $complete = int( 100 * $progress / @$ids );
		my $matches = $self->_blast( $id, \$params->{'sequence'}, $params );
		if ( !$params->{'show_no_match'} && ( ref $matches ne 'ARRAY' || !@$matches ) ) {
			$self->{'jobManager'}
			  ->update_job_status( $job_id, { percent_complete => $complete, stage => "Checked id: $id" } );
			next;
		}
		$html_buffer .= $html_header if $first;
		my $include_values = $self->_get_include_values( \@includes, $id );
		$some_results = 1;
		my $rows        = @$matches;
		my $first_match = 1;
		foreach my $match (@$matches) {
			$html_buffer .= $self->_get_prov_html_cells(
				{
					isolate_id     => $id,
					td             => $td,
					include_values => $include_values,
					is_match       => 1,
					rows           => $rows,
					first_match    => $first_match
				}
			);
			$file_buffer .= $self->_get_prov_text_cells( { isolate_id => $id, include_values => $include_values } );
			$html_buffer .= $self->_get_match_attribute_html_cells( $match, $flanking );
			$file_buffer .= $self->_get_match_attribute_text_cells( $match, $flanking );
			$file_buffer .= qq(\n);
			$self->_append_fasta(
				{
					isolate_id        => $id,
					include_values    => $include_values,
					match             => $match,
					flanking          => $flanking,
					out_file          => $out_file,
					out_file_flanking => $out_file_flanking,
					include_seqbin    => $params->{'include_seqbin'} // 0
				}
			);
			$first_match = 0;
		}
		if ( !@$matches ) {
			$html_buffer .=
			  $self->_get_prov_html_cells( { isolate_id => $id, td => $td, include_values => $include_values } );
			$html_buffer .= q(<td>0</td><td colspan="9" /></tr>);
			$file_buffer .= $self->_get_prov_text_cells( { isolate_id => $id, include_values => $include_values } );
			$file_buffer .= qq(\t0\n);
		}
		my $message = "$html_buffer</table>";
		if ( @$ids <= MAX_DISPLAY_TAXA ) {
			$self->{'jobManager'}->update_job_status( $job_id,
				{ percent_complete => $complete, message_html => $message, stage => "Checked id: $id" } );
		} else {
			$self->{'jobManager'}
			  ->update_job_status( $job_id, { percent_complete => $complete, stage => "Checked id: $id" } );
		}
		$td = $td == 1 ? 2 : 1;
		$first = 0;
		return if $self->{'exit'};
	}
	if ($some_results) {
		open( my $fh_output_table, '>', $out_file_table_full_path )
		  or $logger->error("Can't open temp file $out_file_table_full_path for writing");
		say $fh_output_table $file_buffer;
		close $fh_output_table;
		$self->{'jobManager'}->update_job_output( $job_id, { filename => $out_file, description => '01_FASTA' } );
		$self->{'jobManager'}
		  ->update_job_output( $job_id, { filename => $out_file_flanking, description => '02_FASTA with flanking' } );
		$self->{'jobManager'}->update_job_output(
			$job_id,
			{
				filename      => $out_file_table,
				description   => '03_Table (tab-delimited text)',
				compress      => 1,
				keep_original => 1
			}
		);
		my $excel =
		  BIGSdb::Utils::text2excel( $out_file_table_full_path,
			{ worksheet => 'BLAST', tmp_dir => $self->{'config'}->{'secure_tmp_dir'} } );
		if ( -e $excel ) {
			$self->{'jobManager'}->update_job_output( $job_id,
				{ filename => "${job_id}_table.xlsx", description => '04_Table (Excel format)', compress => 1 } );
			unlink $out_file_table_full_path if -e "$out_file_table_full_path.gz";
		}
	} else {
		$self->{'jobManager'}
		  ->update_job_status( $job_id, { percent_complete => 100, message_html => '<p>No matches found.</p>' } );
	}
	return;
}

sub _append_fasta {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $include_values, $match, $flanking, $out_file, $out_file_flanking, $include_seqbin ) =
	  @{$args}{qw(isolate_id include_values match flanking out_file out_file_flanking include_seqbin)};
	my $start   = $match->{'start'};
	my $end     = $match->{'end'};
	my $seq_ref = $self->{'contigManager'}->get_contig_fragment(
		{
			seqbin_id => $match->{'seqbin_id'},
			start     => $start,
			end       => $end,
			reverse   => $match->{'reverse'},
			flanking  => $flanking
		}
	);
	my $label    = $self->_get_isolate_label($isolate_id);
	my $fasta_id = ">$isolate_id|$label";
	$fasta_id .= "|$match->{'seqbin_id'}|$start" if $include_seqbin;
	$fasta_id .= "|$_" foreach @$include_values;
	my $seq_with_flanking;

	if ( $match->{'reverse'} ) {
		$seq_with_flanking =
		  BIGSdb::Utils::break_line( $seq_ref->{'downstream'} . $seq_ref->{'seq'} . $seq_ref->{'upstream'}, 60 );
	} else {
		$seq_with_flanking =
		  BIGSdb::Utils::break_line( $seq_ref->{'upstream'} . $seq_ref->{'seq'} . $seq_ref->{'downstream'}, 60 );
	}
	open( my $fh_output, '>>', "$self->{'config'}->{'tmp_dir'}/$out_file" )
	  or $logger->error("Can't open temp file $self->{'config'}->{'tmp_dir'}/$out_file for writing");
	open( my $fh_output_flanking, '>>', "$self->{'config'}->{'tmp_dir'}/$out_file_flanking" )
	  or $logger->error("Can't open temp file $self->{'config'}->{'tmp_dir'}/$out_file_flanking for writing");
	say $fh_output $fasta_id;
	say $fh_output_flanking $fasta_id;
	say $fh_output BIGSdb::Utils::break_line( $seq_ref->{'seq'}, 60 );
	say $fh_output_flanking $seq_with_flanking;
	close $fh_output;
	close $fh_output_flanking;
	return;
}

sub _get_match_attribute_html_cells {
	my ( $self, $match, $flanking ) = @_;
	my $buffer;
	foreach my $attribute (qw(identity alignment mismatches gaps seqbin_id start end)) {
		$buffer .= qq(<td>$match->{$attribute});
		if ( $attribute eq 'end' ) {
			$match->{'reverse'} ||= 0;
			$buffer .=
			    qq( <a target="_blank" class="extract_tooltip" href="$self->{'system'}->{'script_name'}?)
			  . qq(db=$self->{'instance'}&amp;page=extractedSequence&amp;translate=1&amp;no_highlight=1&amp;)
			  . qq(seqbin_id=$match->{'seqbin_id'}&amp;start=$match->{'start'}&amp;end=$match->{'end'}&amp;)
			  . qq(reverse=$match->{'reverse'}&amp;flanking=$flanking">extract&nbsp;&rarr;</a>);
		}
		$buffer .= q(</td>);
	}
	$buffer .= q(<td style="font-size:2em">) . ( $match->{'reverse'} ? '&larr;' : '&rarr;' ) . q(</td>);
	foreach (qw(e_value bit_score)) {
		$buffer .= qq(<td>$match->{$_}</td>);
	}
	$buffer .= q(</tr>);
	return $buffer;
}

sub _get_match_attribute_text_cells {
	my ( $self, $match, $flanking ) = @_;
	my $buffer;
	foreach my $attribute (qw(identity alignment mismatches gaps seqbin_id start end)) {
		$buffer .= qq(\t$match->{$attribute});
	}
	$buffer .= $match->{'reverse'} ? qq(\tReverse) : qq(\tForward);
	foreach (qw(e_value bit_score)) {
		$buffer .= qq(\t$match->{$_});
	}
	return $buffer;
}

sub _get_isolate_label {
	my ( $self, $isolate_id ) = @_;
	if ( !$self->{'cache'}->{'label'}->{$isolate_id} ) {
		$self->{'cache'}->{'label'}->{$isolate_id} =
		  $self->{'datastore'}
		  ->run_query( "SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?",
			$isolate_id, { cache => 'BLAST::get_isolate_label' } );
	}
	return $self->{'cache'}->{'label'}->{$isolate_id};
}

sub _get_prov_html_cells {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $td, $include_values, $is_match, $rows, $first_match ) =
	  @{$args}{qw(isolate_id td include_values is_match rows first_match)};
	my $html_buffer;
	my $label = $self->_get_isolate_label($isolate_id);
	if ($is_match) {
		if ($first_match) {
			$html_buffer =
			    qq(<tr class="td$td"><td rowspan="$rows" style="vertical-align:top">)
			  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=info&amp;id=$isolate_id">)
			  . qq($isolate_id</a></td><td rowspan="$rows" style=" vertical-align:top">$label</td>);
			$html_buffer .= qq(<td rowspan="$rows" style="vertical-align:top">$_</td>) foreach @$include_values;
		} else {
			$html_buffer = qq(<tr class="td$td">);
		}
	} else {
		$html_buffer = qq(<tr class="td$td"><td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=info&amp;id=$isolate_id">$isolate_id</a></td><td>$label</td>);
		$html_buffer .= qq(<td>$_</td>) foreach @$include_values;
	}
	return $html_buffer;
}

sub _get_prov_text_cells {
	my ( $self,       $args )           = @_;
	my ( $isolate_id, $include_values ) = @{$args}{qw(isolate_id include_values  )};
	my $label  = $self->_get_isolate_label($isolate_id);
	my $buffer = qq($isolate_id\t$label);
	$buffer .= qq(\t$_) foreach @$include_values;
	return $buffer;
}

sub _get_include_values {
	my ( $self, $includes, $isolate_id ) = @_;
	my @include_values;
	if (@$includes) {
		my $include_data = $self->{'datastore'}->run_query( "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?",
			$isolate_id, { fetch => 'row_hashref', cache => 'BLAST::run_isolates' } );
		foreach my $field (@$includes) {
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			my $value;
			if ( defined $metaset ) {
				$value = $self->{'datastore'}->get_metadata_value( $isolate_id, $metaset, $metafield );
			} else {
				if ( $field =~ /s_(\d+)_(\w+)/x ) {
					my ( $scheme_id, $scheme_field ) = ( $1, $2 );
					my $scheme_field_values =
					  $self->{'datastore'}->get_scheme_field_values_by_isolate_id( $isolate_id, $scheme_id );
					no warnings 'numeric';    #might complain about numeric comparison with non-numeric data
					my @values =
					  sort {
						$scheme_field_values->{ lc($scheme_field) }->{$a}
						  cmp $scheme_field_values->{ lc($scheme_field) }->{$b}
						  || $a <=> $b
						  || $a cmp $b
					  }
					  keys %{ $scheme_field_values->{ lc($scheme_field) } };
					local $" = q(,);
					$value = "@values" // q();
				} else {
					$value = $include_data->{$field} // q();
				}
			}
			push @include_values, $value;
		}
	}
	return \@include_values;
}

sub _print_interface {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $qry_ref    = $self->get_query($query_file);
	my $selected_ids;
	if ( $q->param('isolate_id') ) {
		my @ids = $q->param('isolate_id');
		$selected_ids = \@ids;
	} elsif ( defined $query_file ) {
		$selected_ids = $self->get_ids_from_query($qry_ref);
	} else {
		$selected_ids = [];
	}
	say q(<div class="box" id="queryform">);
	say q(<p>Please select the required isolate ids to BLAST against (use CTRL or SHIFT to make multiple selections) )
	  . q(and paste in your query sequence.  Nucleotide or peptide sequences can be queried.</p>);
	say $q->start_form;
	say q(<div class="scrollable">);
	$self->print_seqbin_isolate_fieldset( { selected_ids => $selected_ids, isolate_paste_list => 1 } );
	say q(<fieldset style="float:left"><legend>Paste sequence</legend>);
	say $q->textarea( -name => 'sequence', -rows => 8, -cols => 70 );
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Include in results table</legend>);
	my @fields;
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
	my $labels        = {};

	foreach my $field (@$field_list) {
		next if $field eq $self->{'system'}->{'labelfield'};
		next if any { $field eq $_ } qw (id datestamp date_entered curator sender);
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
		push @fields, $field;
		( $labels->{$field} = $metafield // $field ) =~ tr/_/ /;
	}
	my ( $scheme_fields, $scheme_labels ) =
	  $self->get_field_selection_list( { scheme_fields => 1, analysis_pref => 1 } );
	push @fields, @$scheme_fields;
	$labels->{$_} = $scheme_labels->{$_} foreach @$scheme_fields;
	say $q->scrolling_list(
		-name     => 'includes',
		-id       => 'includes',
		-values   => \@fields,
		-labels   => $labels,
		-size     => 10,
		-multiple => 'true'
	);
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Parameters</legend>);
	say q(<ul><li><label for="word_size" class="parameter">BLASTN word size:</label>);
	say $q->popup_menu( -name => 'word_size', -id => 'word_size', -values => [ 7 .. 28 ], -default => 11 );
	say $self->get_tooltip( q(BLASTN word size - This is the length of an exact match required to initiate an )
		  . q(extension. Larger values increase speed at the expense of sensitivity.) );
	say q(</li><li><label for="scores" class="parameter">BLASTN scoring:</label>);
	my %labels;

	foreach (BLASTN_SCORES) {
		my @values = split /,/x, $_;
		$labels{$_} = "reward:$values[0]; penalty:$values[1]; gap open:$values[2]; gap extend:$values[3]";
	}
	say $q->popup_menu(
		-name    => 'scores',
		-id      => 'scores',
		-values  => [BLASTN_SCORES],
		-labels  => \%labels,
		-default => '2,-3,5,2'
	);
	say $self->get_tooltip( q(BLASTN scoring - This is a combination of rewards for identically )
		  . q(matched nucleotides, penalties for mismatching nucleotides, gap opening costs and gap extension )
		  . q(costs. Only the listed combinations are supported by the BLASTN algorithm.) );
	say q(</li><li><label for="hits" class="parameter">Hits per isolate:</label>);
	say $q->popup_menu(
		-name    => 'hits',
		-id      => 'hits',
		-values  => [qw(1 2 3 4 5 6 7 8 9 10 20 30 40 50)],
		-default => 1
	);
	say q(</li><li><label for="flanking" class="parameter">Flanking length (bp):</label>);
	say $q->popup_menu(
		-name    => 'flanking',
		-id      => 'flanking',
		-values  => [FLANKING],
		-default => $self->{'prefs'}->{'flanking'}
	);
	say $self->get_tooltip( q(Flanking length - This is the length of flanking sequence (if present) )
		  . q(that will be output in the secondary FASTA file.  The default value can be changed in the options page.)
	);
	say q(</li><li>);
	say $q->checkbox( -name => 'tblastx', label => 'Use TBLASTX' );
	say $self->get_tooltip( q(TBLASTX - Compares the six-frame translation of your nucleotide query )
		  . q(against the six-frame translation of the sequences in the sequence bin.) );
	say q(</li></ul></fieldset>);
	say q(<fieldset style="float:left"><legend>Options</legend>);
	say q(<ul><li>);
	say $q->checkbox( -name => 'show_no_match', label => 'Show isolates with no matches' );
	say q(</li><li>);
	say $q->checkbox( -name => 'include_seqbin', label => 'Include seqbin id and start position in FASTA' );
	say q(</li></ul></fieldset>);
	say q(<fieldset style="float:left"><legend>Restrict included sequences by</legend>);
	say q(<ul>);
	my $buffer = $self->get_sequence_method_filter( { 'class' => 'parameter' } );
	say qq(<li>$buffer</li>) if $buffer;
	$buffer = $self->get_project_filter( { 'class' => 'parameter' } );
	say qq(<li>$buffer</li>) if $buffer;
	$buffer = $self->get_experiment_filter( { 'class' => 'parameter' } );
	say qq(<li>$buffer</li>) if $buffer;
	say q(</ul></fieldset>);
	$self->print_action_fieldset( { name => 'BLAST' } );
	say $q->hidden($_) foreach qw (db page name);
	say q(</div>);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _blast {
	my ( $self, $isolate_id, $seq_ref, $form_params ) = @_;
	$$seq_ref =~ s/>.+\n//gx;    #Remove BLAST identifier lines if present
	my $seq_type = BIGSdb::Utils::sequence_type($$seq_ref);
	$$seq_ref =~ s/\s//gx;
	my $program;
	if ( $seq_type eq 'DNA' ) {
		$program = $form_params->{'tblastx'} ? 'tblastx' : 'blastn';
	} else {
		$program = 'tblastn';
	}
	my $file_prefix    = BIGSdb::Utils::get_random();
	my $temp_fastafile = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_file.txt";
	my $temp_outfile   = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_outfile.txt";
	my $temp_queryfile = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_query.txt";
	my $outfile_url    = "$file_prefix\_outfile.txt";

	#create query FASTA file
	open( my $queryfile_fh, '>', $temp_queryfile )
	  or $logger->error("Can't open temp file $temp_queryfile for writing");
	print $queryfile_fh ">query\n$$seq_ref\n";
	close $queryfile_fh;

	#create isolate FASTA database
	my $qry =
	    'SELECT DISTINCT s.id FROM sequence_bin s LEFT JOIN experiment_sequences e ON '
	  . 's.id=e.seqbin_id LEFT JOIN project_members p ON s.isolate_id = p.isolate_id '
	  . 'WHERE s.isolate_id=?';
	my @criteria = ($isolate_id);
	my $method   = $form_params->{'seq_method_list'};
	if ($method) {
		if ( !any { $_ eq $method } SEQ_METHODS ) {
			$logger->error("Invalid method $method");
			return [];
		}
		$qry .= ' AND method=?';
		push @criteria, $method;
	}
	my $project = $form_params->{'project_list'};
	if ($project) {
		if ( !BIGSdb::Utils::is_int($project) ) {
			$logger->error("Invalid project $project");
			return [];
		}
		$qry .= ' AND project_id=?';
		push @criteria, $project;
	}
	my $experiment = $form_params->{'experiment_list'};
	if ($experiment) {
		if ( !BIGSdb::Utils::is_int($experiment) ) {
			$logger->error("Invalid experiment $experiment");
			return [];
		}
		$qry .= ' AND experiment_id=?';
		push @criteria, $experiment;
	}
	my $seqbin_ids =
	  $self->{'datastore'}->run_query( $qry, \@criteria, { fetch => 'col_arrayref', cache => 'BLAST::blast' } );
	my $contigs = $self->{'contigManager'}->get_contigs_by_list($seqbin_ids);
	$self->{'db'}->commit;    #Prevent idle in transaction table lock.
	open( my $fastafile_fh, '>', $temp_fastafile )
	  or $logger->error("Can't open temp file $temp_fastafile for writing");
	foreach my $seqbin_id (@$seqbin_ids) {
		say $fastafile_fh ">$seqbin_id\n$contigs->{$seqbin_id}";
	}
	close $fastafile_fh;
	return [] if -z $temp_fastafile;
	my $blastn_word_size = $form_params->{'word_size'} =~ /(\d+)/x ? $1                  : 11;
	my $hits             = $form_params->{'hits'} =~ /(\d+)/x      ? $1                  : 1;
	my $word_size        = $program eq 'blastn'                    ? ($blastn_word_size) : 3;
	system( "$self->{'config'}->{'blast+_path'}/makeblastdb",
		( -in => $temp_fastafile, -logfile => '/dev/null', -dbtype => 'nucl' ) );
	my $blast_threads = $self->{'config'}->{'blast_threads'} || 1;
	my $filter = $program eq 'blastn' ? 'dust' : 'seg';
	my %params = (
		-num_threads     => $blast_threads,
		-max_target_seqs => $hits,
		-word_size       => $word_size,
		-db              => $temp_fastafile,
		-query           => $temp_queryfile,
		-out             => $temp_outfile,
		-outfmt          => 6,
		-$filter         => 'no'
	);

	if ( $program eq 'blastn' && $form_params->{'scores'} ) {
		if ( ( any { $form_params->{'scores'} eq $_ } BLASTN_SCORES )
			&& $form_params->{'scores'} =~ /^(\d,-\d,\d+,\d)$/x )
		{
			( $params{'-reward'}, $params{'-penalty'}, $params{'-gapopen'}, $params{'-gapextend'} ) = split /,/x, $1;
		}
	}
	system( "$self->{'config'}->{'blast+_path'}/$program", %params );
	my $matches = $self->_parse_blast( $outfile_url, $hits );

	#clean up
	my @files = glob("$self->{'config'}->{'secure_tmp_dir'}/*$file_prefix*");
	foreach (@files) { unlink $1 if /^(.*BIGSdb.*)$/x }
	return $matches;
}

sub _parse_blast {
	my ( $self, $blast_file, $hits ) = @_;
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$blast_file";
	my @matches;
	my $rows;
	open( my $blast_fh, '<', $full_path )
	  || ( $logger->error("Can't open BLAST output file $full_path. $!"), return \$; );
	while ( my $line = <$blast_fh> ) {
		next if !$line || $line =~ /^\#/x;
		my $match = $self->_extract_match_from_blast_result_line($line);
		push @matches, $match;
		$rows++;
		last if $rows == $hits;
	}
	close $blast_fh;
	return \@matches;
}

sub _extract_match_from_blast_result_line {
	my ( $self, $line ) = @_;
	return if !$line || $line =~ /^\#/x;
	my @record = split /\s+/x, $line;
	my $match;
	$match->{'seqbin_id'}  = $record[1];
	$match->{'identity'}   = $record[2];
	$match->{'alignment'}  = $record[3];
	$match->{'mismatches'} = $record[4];
	$match->{'gaps'}       = $record[5];
	$match->{'reverse'}    = 1
	  if ( ( $record[8] > $record[9] && $record[7] > $record[6] )
		|| ( $record[8] < $record[9] && $record[7] < $record[6] ) );

	if ( $record[8] < $record[9] ) {
		$match->{'start'} = $record[8];
		$match->{'end'}   = $record[9];
	} else {
		$match->{'start'} = $record[9];
		$match->{'end'}   = $record[8];
	}
	$match->{'e_value'}   = $record[10];
	$match->{'bit_score'} = $record[11];
	return $match;
}
1;
