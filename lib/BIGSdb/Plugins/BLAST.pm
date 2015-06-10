#BLAST.pm - BLAST plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2015, University of Oxford
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
use List::MoreUtils qw(any);
use BIGSdb::Page qw(SEQ_METHODS FLANKING);
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
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
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
		version     => '1.2.0',
		dbtype      => 'isolates',
		section     => 'analysis,postquery',
		input       => 'query',
		order       => 32,
		help        => 'tooltips',
		system_flag => 'BLAST',
		url         => "$self->{'config'}->{'doclink'}/data_analysis.html#blast"
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
	my $q      = $self->{'cgi'};
	my $view   = $self->{'system'}->{'view'};
	say q(<h1>BLAST</h1>);
	$self->_print_interface;
	return if !( $q->param('submit') && $q->param('sequence') );
	my @ids = $q->param('isolate_id');
	if ( !@ids ) {
		say q(<div class="box" id="statusbad"><p>You must select one or more isolates.</p></div>);
		return;
	}
	my @includes = $q->param('includes');
	my %meta_labels;
	foreach my $field (@includes) {
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
		$meta_labels{$field} = $metafield;
	}
	my $seq = $q->param('sequence');
	say q(<div class="box" id="resultstable">);
	my $header_buffer = qq(<table class="resultstable">\n);
	my $labelfield    = $self->{'system'}->{'labelfield'};
	( my $display_label = ucfirst($labelfield) ) =~ tr/_/ /;
	$header_buffer .= qq(<tr><th>Isolate id</th><th>$display_label</th>);
	$header_buffer .= q(<th>) . ( $meta_labels{$_} // $_ ) . q(</th>) foreach @includes;
	$header_buffer .= q(<th>% identity</th><th>Alignment length</th><th>Mismatches</th><th>Gaps</th><th>Seqbin id</th>)
	  . qq(<th>Start</th><th>End</th><th>Orientation</th><th>E-value</th><th>Bit score</th></tr>\n);
	my $first                    = 1;
	my $some_results             = 0;
	my $td                       = 1;
	my $prefix                   = BIGSdb::Utils::get_random();
	my $out_file                 = "$prefix.txt";
	my $out_file_flanking        = "$prefix\_flanking.txt";
	my $out_file_table           = "$prefix\_table.txt";
	my $out_file_table_full_path = "$self->{'config'}->{'tmp_dir'}/$out_file_table";
	open( my $fh_output_table, '>', $out_file_table_full_path )
	  or $logger->error("Can't open temp file $out_file_table_full_path for writing");
	print $fh_output_table "Isolate id\t$display_label\t";
	print $fh_output_table ( $meta_labels{$_} // $_ ) . "\t" foreach @includes;
	say $fh_output_table
	  "% identity\tAlignment length\tMismatches\tGaps\tSeqbin id\tStart\tEnd\tOrientation\tE-value\tBit score";
	close $fh_output_table;

	foreach my $id (@ids) {
		my $matches = $self->_blast( $id, \$seq );
		next if !$q->param('show_no_match') && ( ref $matches ne 'ARRAY' || !@$matches );
		print $header_buffer if $first;
		my @include_values;
		if (@includes) {
			my $include_data = $self->{'datastore'}->run_query( "SELECT * FROM $view WHERE id=?",
				$id, { fetch => 'row_hashref', cache => 'BLAST::run_isolates' } );
			foreach my $field (@includes) {
				my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
				my $value;
				if ( defined $metaset ) {
					$value = $self->{'datastore'}->get_metadata_value( $id, $metaset, $metafield );
				} else {
					$value = $include_data->{$field} // '';
				}
				push @include_values, $value;
			}
		}
		$some_results = 1;
		my $label =
		  $self->{'datastore'}
		  ->run_query( "SELECT $labelfield FROM $view WHERE id=?", $id, { cache => 'BLAST::run_label' } );
		my $rows        = @$matches;
		my $first_match = 1;
		my $flanking    = $q->param('flanking') // $self->{'prefs'}->{'flanking'};
		foreach my $match (@$matches) {
			my $file_buffer;
			if ($first_match) {
				print qq(<tr class="td$td"><td rowspan="$rows" style="vertical-align:top">)
				  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=info&amp;id=$id">)
				  . qq($id</a></td><td rowspan="$rows" style=" vertical-align:top">$label</td>);
			} else {
				print qq(<tr class="td$td">);
			}
			print qq(<td>$_</td>) foreach @include_values;
			$file_buffer .= qq($id\t$label);
			$file_buffer .= qq(\t$_) foreach @include_values;
			foreach my $attribute (qw(identity alignment mismatches gaps seqbin_id start end)) {
				print qq(<td>$match->{$attribute});
				if ( $attribute eq 'end' ) {
					$match->{'reverse'} ||= 0;
					print qq( <a target="_blank" class="extract_tooltip" href="$self->{'system'}->{'script_name'}?)
					  . qq(db=$self->{'instance'}&amp;page=extractedSequence&amp;translate=1&amp;no_highlight=1&amp;)
					  . qq(seqbin_id=$match->{'seqbin_id'}&amp;start=$match->{'start'}&amp;end=$match->{'end'}&amp;)
					  . qq(reverse=$match->{'reverse'}&amp;flanking=$flanking">extract&nbsp;&rarr;</a>);
				}
				print q(</td>);
				$file_buffer .= qq(\t$match->{$attribute});
			}
			print q(<td style="font-size:2em">) . ( $match->{'reverse'} ? '&larr;' : '&rarr;' ) . q(</td>);
			$file_buffer .= $match->{'reverse'} ? qq(\tReverse) : qq(\tForward);
			foreach (qw(e_value bit_score)) {
				print qq(<td>$match->{$_}</td>);
				$file_buffer .= qq(\t$match->{$_});
			}
			say q(</tr>);
			$first_match = 0;
			my $start  = $match->{'start'};
			my $end    = $match->{'end'};
			my $length = abs( $end - $start + 1 );
			my $qry =
			    qq[SELECT substring(sequence FROM $start for $length) AS seq,substring(sequence ]
			  . qq[FROM ($start-$flanking) FOR $flanking) AS upstream,substring(sequence FROM ($end+1) ]
			  . qq[FOR $flanking) AS downstream FROM sequence_bin WHERE id=?];
			my $seq_ref = $self->{'datastore'}->run_query( $qry, $match->{'seqbin_id'}, { fetch => 'row_hashref' } );
			$seq_ref->{'seq'}      = BIGSdb::Utils::reverse_complement( $seq_ref->{'seq'} )      if $match->{'reverse'};
			$seq_ref->{'upstream'} = BIGSdb::Utils::reverse_complement( $seq_ref->{'upstream'} ) if $match->{'reverse'};
			$seq_ref->{'downstream'} = BIGSdb::Utils::reverse_complement( $seq_ref->{'downstream'} )
			  if $match->{'reverse'};
			my $fasta_id = ">$id|$label";
			$fasta_id .= "|$match->{'seqbin_id'}|$start" if $q->param('include_seqbin');
			$fasta_id .= "|$_" foreach @include_values;
			my $seq_with_flanking;

			if ( $match->{'reverse'} ) {
				$seq_with_flanking =
				  BIGSdb::Utils::break_line( $seq_ref->{'downstream'} . $seq_ref->{'seq'} . $seq_ref->{'upstream'},
					60 );
			} else {
				$seq_with_flanking =
				  BIGSdb::Utils::break_line( $seq_ref->{'upstream'} . $seq_ref->{'seq'} . $seq_ref->{'downstream'},
					60 );
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
			open( my $fh_output_table, '>>', "$self->{'config'}->{'tmp_dir'}/$out_file_table" )
			  or $logger->error("Can't open temp file $self->{'config'}->{'tmp_dir'}/$out_file_table for writing");
			say $fh_output_table $file_buffer;
			close $fh_output_table;
		}
		if ( !@$matches ) {
			say qq(<tr class="td$td"><td><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=info&amp;id=$id\">$id</a></td><td>$label</td>);
			say qq(<td>$_</td>) foreach @include_values;
			say q(<td>0</td><td colspan="9" /></tr>);
			open( my $fh_output_table, '>>', "$self->{'config'}->{'tmp_dir'}/$out_file_table" )
			  or $logger->error("Can't open temp file $self->{'config'}->{'tmp_dir'}/$out_file_table for writing");
			print $fh_output_table qq($id\t$label);
			print $fh_output_table qq(\t$_) foreach @include_values;
			say $fh_output_table qq(\t0);
			close $fh_output_table;
		}
		$td = $td == 1 ? 2 : 1;
		$first = 0;
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
	}
	if ($some_results) {
		say q(</table>);
		say q(<p style="margin-top:1em">Download );
		say qq(<a href="/tmp/$out_file" target="_blank">FASTA</a> | ) if -e "$self->{'config'}->{'tmp_dir'}/$out_file";
		say qq(<a href="/tmp/$out_file_flanking" target="_blank">FASTA with flanking</a> | )
		  . q( <a class="tooltip" title="Flanking sequence - You can change the amount of flanking )
		  . q(sequence exported by selecting the appropriate length in the options page.">)
		  . q(<span class="fa fa-info-circle"></span></a> ) if -e "$self->{'config'}->{'tmp_dir'}/$out_file_flanking";;
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
	$self->print_seqbin_isolate_fieldset( { selected_ids => $selected_ids } );
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
	say q( <a class="tooltip" title="BLASTN word size - This is the length of an exact match required to initiate an )
	  . q(extension. Larger values increase speed at the expense of sensitivity."><span class="fa fa-info-circle">)
	  . q(</span></a></li>);
	say q(<li><label for="scores" class="parameter">BLASTN scoring:</label>);
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
	say q( <a class="tooltip" title="BLASTN scoring - This is a combination of rewards for identically )
	  . q(matched nucleotides, penalties for mismatching nucleotides, gap opening costs and gap extension )
	  . q(costs. Only the listed combinations are supported by the BLASTN algorithm.">)
	  . q(<span class="fa fa-info-circle"></span></a>);
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
	say q( <a class="tooltip" title="Flanking length - This is the length of flanking sequence (if present) )
	  . q(that will be output in the secondary FASTA file.  The default value can be changed in the options page.">)
	  . q(<span class="fa fa-info-circle"></span></a></li>);
	say q(<li>);
	say $q->checkbox( -name => 'tblastx', label => 'Use TBLASTX' );
	say q( <a class="tooltip" title="TBLASTX - Compares the six-frame translation of your nucleotide query )
	  . q(against the six-frame translation of the sequences in the sequence bin.">)
	  . q(<span class="fa fa-info-circle"></span></a></li>);
	say q(</ul></fieldset>);
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
	my ( $self, $isolate_id, $seq_ref ) = @_;
	my $q = $self->{'cgi'};
	$$seq_ref =~ s/>.+\n//gx;    #Remove BLAST identifier lines if present
	my $seq_type = BIGSdb::Utils::sequence_type($$seq_ref);
	$$seq_ref =~ s/\s//gx;
	my $program;
	if ( $seq_type eq 'DNA' ) {
		$program = $q->param('tblastx') ? 'tblastx' : 'blastn';
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
	    'SELECT DISTINCT sequence_bin.id,sequence FROM sequence_bin LEFT JOIN experiment_sequences ON '
	  . 'sequence_bin.id=seqbin_id LEFT JOIN project_members ON sequence_bin.isolate_id = project_members.isolate_id '
	  . 'WHERE sequence_bin.isolate_id=?';
	my @criteria = ($isolate_id);
	my $method   = $q->param('seq_method_list');
	if ($method) {
		if ( !any { $_ eq $method } SEQ_METHODS ) {
			$logger->error("Invalid method $method");
			return;
		}
		$qry .= ' AND method=?';
		push @criteria, $method;
	}
	my $project = $q->param('project_list');
	if ($project) {
		if ( !BIGSdb::Utils::is_int($project) ) {
			$logger->error("Invalid project $project");
			return;
		}
		$qry .= ' AND project_id=?';
		push @criteria, $project;
	}
	my $experiment = $q->param('experiment_list');
	if ($experiment) {
		if ( !BIGSdb::Utils::is_int($experiment) ) {
			$logger->error("Invalid experiment $experiment");
			return;
		}
		$qry .= ' AND experiment_id=?';
		push @criteria, $experiment;
	}
	my $data =
	  $self->{'datastore'}->run_query( $qry, \@criteria, { fetch => 'all_arrayref', cache => 'BLAST::blast' } );
	open( my $fastafile_fh, '>', $temp_fastafile )
	  or $logger->error("Can't open temp file $temp_fastafile for writing");
	foreach (@$data) {
		my ( $id, $seq ) = @$_;
		say $fastafile_fh ">$id\n$seq";
	}
	close $fastafile_fh;
	return if -z $temp_fastafile;
	my $blastn_word_size = $q->param('word_size') =~ /(\d+)/x ? $1 : 11;
	my $hits             = $q->param('hits')      =~ /(\d+)/x ? $1 : 1;
	my $word_size = $program eq 'blastn' ? ($blastn_word_size) : 3;
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

	if ( $program eq 'blastn' && $q->param('scores') ) {
		if ( ( any { $q->param('scores') eq $_ } BLASTN_SCORES ) && $q->param('scores') =~ /^(\d,-\d,\d+,\d)$/x ) {
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
