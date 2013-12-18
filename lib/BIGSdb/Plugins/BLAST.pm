#BLAST.pm - BLAST plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2013, University of Oxford
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
	$self->{'pref_requirements'} = { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub get_attributes {
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
		version     => '1.1.3',
		dbtype      => 'isolates',
		section     => 'analysis,postquery',
		input       => 'query',
		order       => 32,
		help        => 'tooltips',
		system_flag => 'BLAST'
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
	my $sql =
	  $self->{'db'}->prepare( "SELECT DISTINCT $view.id,$view.$self->{'system'}->{'labelfield'} FROM $view WHERE $view.id IN "
		  . "(SELECT isolate_id FROM sequence_bin) ORDER BY $view.id" );
	eval { $sql->execute };
	$logger->error($@) if $@;
	my @ids;
	my %labels;

	while ( my ( $id, $isolate ) = $sql->fetchrow_array ) {
		push @ids, $id;
		$labels{$id} = "$id) $isolate";
	}
	print "<h1>BLAST</h1>\n";
	if ( !@ids ) {
		say "<div class=\"box\" id=\"statusbad\"><p>There are no sequences in the sequence bin.</p></div>";
		return;
	}
	$self->_print_interface( \@ids, \%labels );
	return if !( $q->param('submit') && $q->param('sequence') );
	@ids = $q->param('isolate_id');
	if ( !@ids ) {
		say "<div class=\"box\" id=\"statusbad\"><p>You must select one or more isolates.</p></div>";
		return;
	}
	my @includes = $q->param('includes');
	my %meta_labels;
	foreach my $field (@includes) {
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
		$meta_labels{$field} = $metafield;
	}
	my $isolate_sql = $self->{'db'}->prepare("SELECT * FROM $self->{'system'}->{'view'} WHERE id=?");
	my $seq         = $q->param('sequence');
	print "<div class=\"box\" id=\"resultstable\">\n";
	my $header_buffer = "<table class=\"resultstable\">\n";
	my $labelfield    = $self->{'system'}->{'labelfield'};
	( my $display_label = ucfirst($labelfield) ) =~ tr/_/ /;
	$header_buffer .= "<tr><th>Isolate id</th><th>$display_label</th>";
	$header_buffer .= "<th>" . ( $meta_labels{$_} // $_ ) . '</th>' foreach @includes;
	$header_buffer .= "<th>% identity</th><th>Alignment length</th><th>Mismatches</th><th>Gaps</th><th>Seqbin id</th><th>Start</th>"
	  . "<th>End</th><th>Orientation</th><th>E-value</th><th>Bit score</th></tr>\n";
	my $first        = 1;
	my $some_results = 0;
	$sql = $self->{'db'}->prepare("SELECT $labelfield FROM $self->{'system'}->{'view'} WHERE id=?");
	my $td                = 1;
	my $temp              = BIGSdb::Utils::get_random();
	my $out_file          = "$temp.txt";
	my $out_file_flanking = "$temp\_flanking.txt";
	my $out_file_table    = "$temp\_table.txt";
	open( my $fh_output_table, '>>', "$self->{'config'}->{'tmp_dir'}/$out_file_table" )
	  or $logger->error("Can't open temp file $self->{'config'}->{'tmp_dir'}/$out_file_table for writing");
	print $fh_output_table "Isolate id\t$display_label\t";
	print $fh_output_table ( $meta_labels{$_} // $_ ) . "\t" foreach @includes;
	say $fh_output_table "% identity\tAlignment length\tMismatches\tGaps\tSeqbin id\tStart\tEnd\tOrientation\tE-value\tBit score";
	close $fh_output_table;

	foreach my $id (@ids) {
		my $matches = $self->_blast( $id, \$seq );
		next if !$q->param('show_no_match') && ( ref $matches ne 'ARRAY' || !@$matches );
		print $header_buffer if $first;
		my @include_values;
		if (@includes) {
			eval { $isolate_sql->execute($id) };
			$logger->error($@) if $@;
			my $include_data = $isolate_sql->fetchrow_hashref;
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
		eval { $sql->execute($id) };
		$logger->error($@) if $@;
		my ($label)     = $sql->fetchrow_array;
		my $rows        = @$matches;
		my $first_match = 1;
		my $flanking = $q->param('flanking') // $self->{'prefs'}->{'flanking'};

		foreach my $match (@$matches) {
			my $file_buffer;
			if ($first_match) {
				print "<tr class=\"td$td\"><td rowspan=\"$rows\" style=\"vertical-align:top\">"
				  . "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=info&amp;id=$id\">$id</a>"
				  . "</td><td rowspan=\"$rows\" style=\" vertical-align:top\">$label</td>";
			} else {
				print "<tr class=\"td$td\">";
			}
			print "<td>$_</td>" foreach @include_values;
			$file_buffer .= "$id\t$label";
			$file_buffer .= "\t$_" foreach @include_values;
			foreach my $attribute (qw(identity alignment mismatches gaps seqbin_id start end)) {
				print "<td>$match->{$attribute}";
				if ( $attribute eq 'end' ) {
					$match->{'reverse'} ||= 0;
					print " <a target=\"_blank\" class=\"extract_tooltip\" href=\"$self->{'system'}->{'script_name'}?"
					  . "db=$self->{'instance'}&amp;page=extractedSequence&amp;translate=1&amp;no_highlight=1&amp;"
					  . "seqbin_id=$match->{'seqbin_id'}&amp;start=$match->{'start'}&amp;end=$match->{'end'}&amp;"
					  . "reverse=$match->{'reverse'}&amp;flanking=$flanking\">extract&nbsp;&rarr;</a>";
				}
				print "</td>";
				$file_buffer .= "\t$match->{$attribute}";
			}
			print "<td style=\"font-size:2em\">" . ( $match->{'reverse'} ? '&larr;' : '&rarr;' ) . "</td>";
			$file_buffer .= $match->{'reverse'} ? "\tReverse" : "\tForward";
			foreach (qw(e_value bit_score)) {
				print "<td>$match->{$_}</td>";
				$file_buffer .= "\t$match->{$_}";
			}
			say "</tr>";
			$first_match = 0;
			my $start  = $match->{'start'};
			my $end    = $match->{'end'};
			my $length = abs( $end - $start + 1 );
			my $qry    = "SELECT substring(sequence from $start for $length) AS seq,substring(sequence from ($start-$flanking) "
			  . "for $flanking) AS upstream,substring(sequence from ($end+1) for $flanking) AS downstream FROM sequence_bin WHERE id=?";
			my $seq_ref = $self->{'datastore'}->run_simple_query_hashref( $qry, $match->{'seqbin_id'} );
			$seq_ref->{'seq'}        = BIGSdb::Utils::reverse_complement( $seq_ref->{'seq'} )        if $match->{'reverse'};
			$seq_ref->{'upstream'}   = BIGSdb::Utils::reverse_complement( $seq_ref->{'upstream'} )   if $match->{'reverse'};
			$seq_ref->{'downstream'} = BIGSdb::Utils::reverse_complement( $seq_ref->{'downstream'} ) if $match->{'reverse'};
			my $fasta_id = ">$id|$label|$match->{'seqbin_id'}|$start\n";
			my $seq_with_flanking;

			if ( $match->{'reverse'} ) {
				$seq_with_flanking = BIGSdb::Utils::break_line( $seq_ref->{'downstream'} . $seq_ref->{'seq'} . $seq_ref->{'upstream'}, 60 );
			} else {
				$seq_with_flanking = BIGSdb::Utils::break_line( $seq_ref->{'upstream'} . $seq_ref->{'seq'} . $seq_ref->{'downstream'}, 60 );
			}
			open( my $fh_output, '>>', "$self->{'config'}->{'tmp_dir'}/$out_file" )
			  or $logger->error("Can't open temp file $self->{'config'}->{'tmp_dir'}/$out_file for writing");
			open( my $fh_output_flanking, '>>', "$self->{'config'}->{'tmp_dir'}/$out_file_flanking" )
			  or $logger->error("Can't open temp file $self->{'config'}->{'tmp_dir'}/$out_file_flanking for writing");
			print $fh_output $fasta_id;
			print $fh_output_flanking $fasta_id;
			print $fh_output BIGSdb::Utils::break_line( $seq_ref->{'seq'}, 60 ) . "\n";
			print $fh_output_flanking $seq_with_flanking . "\n";
			close $fh_output;
			close $fh_output_flanking;
			open( my $fh_output_table, '>>', "$self->{'config'}->{'tmp_dir'}/$out_file_table" )
			  or $logger->error("Can't open temp file $self->{'config'}->{'tmp_dir'}/$out_file_table for writing");
			say $fh_output_table $file_buffer;
			close $fh_output_table;
		}
		if ( !@$matches ) {
			say "<tr class=\"td$td\"><td><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=info&amp;id=$id\">"
			  . "$id</a></td><td>$label</td><td>0</td><td colspan=\"9\" /></tr>";
			open( my $fh_output_table, '>>', "$self->{'config'}->{'tmp_dir'}/$out_file_table" )
			  or $logger->error("Can't open temp file $self->{'config'}->{'tmp_dir'}/$out_file_table for writing");
			say $fh_output_table "$id\t$label\t0";
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
		say "</table>";
		say "<p style=\"margin-top:1em\">Download <a href=\"/tmp/$out_file\">FASTA</a> | "
		  . "<a href=\"/tmp/$out_file_flanking\">FASTA with flanking</a>";
		say " <a class=\"tooltip\" title=\"Flanking sequence - You can change the amount of flanking sequence exported by selecting "
		  . "the appropriate length in the options page.\">&nbsp;<i>i</i>&nbsp;</a> | ";
		say "<a href=\"/tmp/$out_file_table\">Table (tab-delimited text)</a>";
		say "</p>";
	} else {
		say "<p>No matches found.</p>";
	}
	say "</div>";
	return;
}

sub _print_interface {
	my ( $self, $ids, $labels ) = @_;
	my $q            = $self->{'cgi'};
	my $query_file   = $q->param('query_file');
	my $qry_ref      = $self->get_query($query_file);
	my $selected_ids = defined $query_file ? $self->get_ids_from_query($qry_ref) : [];
	say "<div class=\"box\" id=\"queryform\">";
	say "<p>Please select the required isolate ids to BLAST against (use ctrl or shift to make multiple selections) and paste in your "
	  . "query sequence.  Nucleotide or peptide sequences can be queried.</p>";
	say $q->start_form;
	say "<div class=\"scrollable\">";
	say "<fieldset style=\"float:left\">\n<legend>Isolates</legend>";
	say $q->scrolling_list(
		-name     => 'isolate_id',
		-id       => 'isolate_id',
		-values   => $ids,
		-labels   => $labels,
		-size     => 8,
		-multiple => 'true',
		-default  => $selected_ids
	);
	say "<div style=\"text-align:center\"><input type=\"button\" onclick='listbox_selectall(\"isolate_id\",true)' "
	  . "value=\"All\" style=\"margin-top:1em\" class=\"smallbutton\" />\n";
	say "<input type=\"button\" onclick='listbox_selectall(\"isolate_id\",false)' value=\"None\" "
	  . "style=\"margin-top:1em\" class=\"smallbutton\" /></div>\n";
	say "</fieldset>";
	say "<fieldset style=\"float:left\"><legend>Paste sequence</legend>";
	say $q->textarea( -name => 'sequence', -rows => 8, -cols => 70 );
	say "</fieldset>";
	say "<fieldset style=\"float:left\">\n<legend>Include in results table</legend>";
	my @fields;
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);

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
	say "</fieldset>";
	say "<fieldset style=\"float:left\">\n<legend>Parameters</legend>";
	say "<ul><li><label for=\"word_size\" class=\"parameter\">BLASTN word size:</label>";
	say $q->popup_menu( -name => 'word_size', -id => 'word_size', -values => [ 7 .. 28 ], -default => 11 );
	say " <a class=\"tooltip\" title=\"BLASTN word size - This is the length of an exact match required to initiate an "
	  . "extension. Larger values increase speed at the expense of sensitivity.\">&nbsp;<i>i</i>&nbsp;</a></li>";
	say "<li><label for=\"scores\" class=\"parameter\">BLASTN scoring:</label>";
	my %labels;

	foreach (BLASTN_SCORES) {
		my @values = split /,/, $_;
		$labels{$_} = "reward:$values[0]; penalty:$values[1]; gap open:$values[2]; gap extend:$values[3]";
	}
	say $q->popup_menu( -name => 'scores', -id => 'scores', -values => [BLASTN_SCORES], -labels => \%labels, -default => '2,-3,5,2' );
	say " <a class=\"tooltip\" title=\"BLASTN scoring - This is a combination of rewards for identically matched nucleotides, "
	  . "penalties for mismatching nucleotides, gap opening costs and gap extension costs. Only the listed combinations are "
	  . "supported by the BLASTN algorithm.\">&nbsp;<i>i</i>&nbsp;</a>";
	say "</li><li><label for=\"hits\" class=\"parameter\">Hits per isolate:</label>";
	say $q->popup_menu( -name => 'hits', -id => 'hits', -values => [qw(1 2 3 4 5 6 7 8 9 10 20 30 40 50)], -default => 1 );
	say "</li><li><label for=\"flanking\" class=\"parameter\">Flanking length (bp):</label>";
	say $q->popup_menu( -name => 'flanking', -id => 'flanking', -values => [FLANKING], -default => $self->{'prefs'}->{'flanking'} );
	say " <a class=\"tooltip\" title=\"Flanking length - This is the length of flanking sequence (if present) that will be output "
	  . "in the secondary FASTA file.  The default value can be changed in the options page.\">&nbsp;<i>i</i>&nbsp;</a></li>";
	say "<li>";
	say $q->checkbox( -name => 'tblastx', label => 'Use TBLASTX' );
	say " <a class=\"tooltip\" title=\"TBLASTX - Compares the six-frame translation of your nucleotide query against the "
	  . "six-frame translation of the sequences in the sequence bin.\">&nbsp;<i>i</i>&nbsp;</a></li>";
	say "</ul>";
	say "</fieldset>";
	say "<fieldset style=\"float:left\">";
	say "<legend>Options</legend>";
	say "<ul><li>";
	say $q->checkbox( -name => 'show_no_match', label => 'Show 0% matches in table' );
	say "</li></ul>";
	say "</fieldset>";
	say "<fieldset style=\"float:left\">\n<legend>Restrict included sequences by</legend>";
	say "<ul>";
	my $buffer = $self->get_sequence_method_filter( { 'class' => 'parameter' } );
	say "<li>$buffer</li>" if $buffer;
	$buffer = $self->get_project_filter( { 'class' => 'parameter' } );
	say "<li>$buffer</li>" if $buffer;
	$buffer = $self->get_experiment_filter( { 'class' => 'parameter' } );
	say "<li>$buffer</li>" if $buffer;
	say "</ul>\n</fieldset>";
	$self->print_action_fieldset( { name => 'BLAST' } );
	say $q->hidden($_) foreach qw (db page name);
	say "</div>";
	say $q->end_form;
	say "</div>";
	return;
}

sub _blast {
	my ( $self, $isolate_id, $seq_ref ) = @_;
	my $q = $self->{'cgi'};
	$$seq_ref =~ s/>.+\n//g;    #Remove BLAST identifier lines if present
	my $seq_type = BIGSdb::Utils::sequence_type($$seq_ref);
	$$seq_ref =~ s/\s//g;
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
	open( my $queryfile_fh, '>', $temp_queryfile ) or $logger->error("Can't open temp file $temp_queryfile for writing");
	print $queryfile_fh ">query\n$$seq_ref\n";
	close $queryfile_fh;

	#create isolate FASTA database
	my $qry = "SELECT DISTINCT sequence_bin.id,sequence FROM sequence_bin LEFT JOIN experiment_sequences ON sequence_bin.id=seqbin_id "
	  . "LEFT JOIN project_members ON sequence_bin.isolate_id = project_members.isolate_id WHERE sequence_bin.isolate_id=?";
	my @criteria = ($isolate_id);
	my $method   = $q->param('seq_method_list');
	if ($method) {
		if ( !any { $_ eq $method } SEQ_METHODS ) {
			$logger->error("Invalid method $method");
			return;
		}
		$qry .= " AND method=?";
		push @criteria, $method;
	}
	my $project = $q->param('project_list');
	if ($project) {
		if ( !BIGSdb::Utils::is_int($project) ) {
			$logger->error("Invalid project $project");
			return;
		}
		$qry .= " AND project_id=?";
		push @criteria, $project;
	}
	my $experiment = $q->param('experiment_list');
	if ($experiment) {
		if ( !BIGSdb::Utils::is_int($experiment) ) {
			$logger->error("Invalid experiment $experiment");
			return;
		}
		$qry .= " AND experiment_id=?";
		push @criteria, $experiment;
	}
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute(@criteria); };
	$logger->error($@) if $@;
	open( my $fastafile_fh, '>', $temp_fastafile ) or $logger->error("Can't open temp file $temp_fastafile for writing");
	while ( my ( $id, $seq ) = $sql->fetchrow_array ) {
		print $fastafile_fh ">$id\n$seq\n";
	}
	close $fastafile_fh;
	return if -z $temp_fastafile;
	my $blastn_word_size = $q->param('word_size') =~ /(\d+)/ ? $1 : 11;
	my $hits             = $q->param('hits')      =~ /(\d+)/ ? $1 : 1;
	my $word_size = $program eq 'blastn' ? ($blastn_word_size) : 3;
	system( "$self->{'config'}->{'blast+_path'}/makeblastdb", ( -in => $temp_fastafile, -logfile => '/dev/null', -dbtype => 'nucl' ) );
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
		if ( ( any { $q->param('scores') eq $_ } BLASTN_SCORES ) && $q->param('scores') =~ /^(\d,-\d,\d+,\d)$/ ) {
			( $params{'-reward'}, $params{'-penalty'}, $params{'-gapopen'}, $params{'-gapextend'} ) = split /,/, $1;
		}
	}
	system( "$self->{'config'}->{'blast+_path'}/$program", %params );
	my $matches = $self->_parse_blast( $outfile_url, $hits );

	#clean up
	my @files = glob("$self->{'config'}->{'secure_tmp_dir'}/*$file_prefix*");
	foreach (@files) { unlink $1 if /^(.*BIGSdb.*)$/ }
	return $matches;
}

sub _parse_blast {
	my ( $self, $blast_file, $hits ) = @_;
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$blast_file";
	my @matches;
	my $rows;
	open( my $blast_fh, '<', $full_path ) || ( $logger->error("Can't open BLAST output file $full_path. $!"), return \$; );
	while ( my $line = <$blast_fh> ) {
		next if !$line || $line =~ /^#/;
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
	return if !$line || $line =~ /^#/;
	my @record = split /\s+/, $line;
	my $match;
	$match->{'seqbin_id'}  = $record[1];
	$match->{'identity'}   = $record[2];
	$match->{'alignment'}  = $record[3];
	$match->{'mismatches'} = $record[4];
	$match->{'gaps'}       = $record[5];
	$match->{'reverse'}    = 1
	  if ( ( $record[8] > $record[9] && $record[7] > $record[6] ) || ( $record[8] < $record[9] && $record[7] < $record[6] ) );

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
