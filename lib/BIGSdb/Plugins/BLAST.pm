#BLAST.pm - BLAST plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2012, University of Oxford
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

sub get_attributes {
	my %att = (
		name        => 'BLAST',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'BLAST a query sequence against selected isolate data',
		category    => 'Genome',
		buttontext  => 'BLAST',
		menutext    => 'BLAST',
		module      => 'BLAST',
		version     => '1.0.2',
		dbtype      => 'isolates',
		section     => 'analysis',
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
	my $qry =
"SELECT DISTINCT $view.id,$view.$self->{'system'}->{'labelfield'} FROM sequence_bin LEFT JOIN $view ON $view.id=sequence_bin.isolate_id ORDER BY $view.id";
	my $sql = $self->{'db'}->prepare($qry);
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
		print "<div class=\"box\" id=\"statusbad\"><p>There are no sequences in the sequence bin.</p></div>\n";
		return;
	}
	$self->_print_interface( \@ids, \%labels );
	return if !( $q->param('submit') && $q->param('sequence') );
	@ids = $q->param('isolate_id');
	if ( !@ids ) {
		print "<div class=\"box\" id=\"statusbad\"><p>You must select one or more isolates.</p></div>\n";
		return;
	}
	my $seq = $q->param('sequence');
	print "<div class=\"box\" id=\"resultstable\">\n";
	my $header_buffer = "<table class=\"resultstable\">\n";
	my $labelfield    = $self->{'system'}->{'labelfield'};
	( my $display_label = ucfirst($labelfield) ) =~ tr/_/ /;
	$header_buffer .=
"<tr><th>Isolate id</th><th>$display_label</th><th>% identity</th><th>Alignment length</th><th>Mismatches</th><th>Gaps</th><th>Seqbin id</th><th>Start</th><th>End</th><th>Orientation</th><th>E-value</th><th>Bit score</th></tr>\n";
	my $first        = 1;
	my $some_results = 0;
	$sql = $self->{'db'}->prepare("SELECT $labelfield FROM $self->{'system'}->{'view'} WHERE id=?");
	my $td                = 1;
	my $temp              = BIGSdb::Utils::get_random();
	my $out_file          = "$temp.txt";
	my $out_file_flanking = "$temp\_flanking.txt";

	foreach (@ids) {
		my $matches = $self->_blast( $_, \$seq );
		next if ref $matches ne 'ARRAY' || !@$matches;
		print $header_buffer if $first;
		$some_results = 1;
		eval { $sql->execute($_) };
		$logger->error($@) if $@;
		my ($label)     = $sql->fetchrow_array;
		my $rows        = @$matches;
		my $first_match = 1;
		my $flanking = $q->param('flanking') // $self->{'prefs'}->{'flanking'};
		foreach my $match (@$matches) {
			if ($first_match) {
				print
"<tr class=\"td$td\"><td rowspan=\"$rows\" style=\"vertical-align:top\">$_</td><td rowspan=\"$rows\" style=\" vertical-align:top\">$label</td>";
			} else {
				print "<tr class=\"td$td\">";
			}
			foreach my $attribute (qw(identity alignment mismatches gaps seqbin_id start end)) {
				print "<td>$match->{$attribute}";
				if ( $attribute eq 'end' ) {
					$match->{'reverse'} ||= 0;
					print
" <a target=\"_blank\" class=\"extract_tooltip\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=extractedSequence&amp;translate=1&amp;no_highlight=1&amp;seqbin_id=$match->{'seqbin_id'}&amp;start=$match->{'start'}&amp;end=$match->{'end'}&amp;reverse=$match->{'reverse'}&amp;flanking=$flanking\">extract&nbsp;&rarr;</a>";
				}
				print "</td>";
			}
			print "<td style=\"font-size:2em\">" . ( $match->{'reverse'} ? '&larr;' : '&rarr;' ) . "</td>";
			print "<td>$match->{$_}</td>" foreach qw(e_value bit_score);
			print "</tr>\n";
			$first_match = 0;
			my $start    = $match->{'start'};
			my $end      = $match->{'end'};
			my $length   = abs( $end - $start + 1 );
			my $qry =
"SELECT substring(sequence from $start for $length) AS seq,substring(sequence from ($start-$flanking) for $flanking) AS upstream,substring(sequence from ($end+1) for $flanking) AS downstream FROM sequence_bin WHERE id=?";
			my $seq_ref = $self->{'datastore'}->run_simple_query_hashref( $qry, $match->{'seqbin_id'} );
			$seq_ref->{'seq'}        = BIGSdb::Utils::reverse_complement( $seq_ref->{'seq'} )        if $match->{'reverse'};
			$seq_ref->{'upstream'}   = BIGSdb::Utils::reverse_complement( $seq_ref->{'upstream'} )   if $match->{'reverse'};
			$seq_ref->{'downstream'} = BIGSdb::Utils::reverse_complement( $seq_ref->{'downstream'} ) if $match->{'reverse'};
			my $fasta_id = ">$_|$label|$match->{'seqbin_id'}|$start\n";
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
		}
		$td = $td == 1 ? 2 : 1;
		$first = 0;
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			if ( $self->{'mod_perl_request'}->connection->aborted ) {
				return;
			}
		}
	}
	if ($some_results) {
		print "</table>\n";
		print
"<p style=\"margin-top:1em\">Download <a href=\"/tmp/$out_file\">FASTA</a> | <a href=\"/tmp/$out_file_flanking\">FASTA with flanking</a>";
		print
" <a class=\"tooltip\" title=\"Flanking sequence - You can change the amount of flanking sequence exported by selecting the appropriate length in the options page.\">&nbsp;<i>i</i>&nbsp;</a>";
		print "</p>\n";
	} else {
		print "<p>No matches found.</p>\n";
	}
	print "</div>\n";
	return;
}

sub _print_interface {
	my ( $self, $ids, $labels ) = @_;
	my $q = $self->{'cgi'};
	print "<div class=\"box\" id=\"queryform\">\n";
	print "<p>Please select the required isolate ids to BLAST against (use ctrl or shift to make 
	  multiple selections) and paste in your query sequence.  Nucleotide or peptide sequences can be queried.</p>\n";
	print $q->start_form;
	print "<div class=\"scrollable\">\n";
	print "<fieldset style=\"float:left\">\n<legend>Isolates</legend>\n";
	print $q->scrolling_list(
		-name     => 'isolate_id',
		-id       => 'isolate_id',
		-values   => $ids,
		-labels   => $labels,
		-size     => 8,
		-multiple => 'true'
	);
	print
"<div style=\"text-align:center\"><input type=\"button\" onclick='listbox_selectall(\"isolate_id\",true)' value=\"All\" style=\"margin-top:1em\" class=\"smallbutton\" />\n";
	print
"<input type=\"button\" onclick='listbox_selectall(\"isolate_id\",false)' value=\"None\" style=\"margin-top:1em\" class=\"smallbutton\" /></div>\n";
	print "</fieldset>\n";
	print "<fieldset style=\"float:left\"><legend>Paste sequence</legend>\n";
	print $q->textarea( -name => 'sequence', -rows => '8', -cols => '70' );
	print "</fieldset>\n";
	print "<fieldset style=\"float:left\">\n<legend>Parameters</legend>\n";
	print "<ul><li><label for=\"word_size\" class=\"parameter\">BLASTN word size:</label>\n";
	print $q->popup_menu(
		-name    => 'word_size',
		-id      => 'word_size',
		-values  => [qw(7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28)],
		-default => 11
	);
	print
" <a class=\"tooltip\" title=\"BLASTN word size - This is the length of an exact match required to initiate an extension. Larger values increase speed at the expense of sensitivity.\">&nbsp;<i>i</i>&nbsp;</a></li>";
	print "<li><label for=\"hits\" class=\"parameter\">Hits per isolate:</label>\n";
	print $q->popup_menu( -name => 'hits', -id => 'hits', -values => [qw(1 2 3 4 5 6 7 8 9 10 20 30 40 50)], -default => 1 );
	print "</li><li><label for=\"flanking\" class=\"parameter\">Flanking length (bp):</label>\n";
	print $q->popup_menu( -name => 'flanking', -id => 'flanking', -values => [ FLANKING ], -default => $self->{'prefs'}->{'flanking'} );
	print
" <a class=\"tooltip\" title=\"Flanking length - This is the length of flanking sequence (if present) that will be output in the secondary FASTA file.  The default value can be changed in the options page.\">&nbsp;<i>i</i>&nbsp;</a>";

	print "</li>\n<li>\n";
	print $q->checkbox( -name => 'tblastx', label => 'Use TBLASTX' );
	print
" <a class=\"tooltip\" title=\"TBLASTX - Compares the six-frame translation of your nucleotide query against the six-frame translation of the sequences in the sequence bin.\">&nbsp;<i>i</i>&nbsp;</a></li>";
	print "</ul>\n";
	print "</fieldset>\n";
	print "<fieldset style=\"float:left\">\n<legend>Restrict included sequences by</legend>\n";
	print "<ul>\n";
	my $buffer = $self->get_sequence_method_filter( { 'class' => 'parameter' } );
	print "<li>$buffer</li>" if $buffer;
	$buffer = $self->get_project_filter( { 'class' => 'parameter' } );
	print "<li>$buffer</li>" if $buffer;
	$buffer = $self->get_experiment_filter( { 'class' => 'parameter' } );
	print "<li>$buffer</li>" if $buffer;
	print "</ul>\n</fieldset>\n";
	print "<table style=\"width:95%\"><tr><td style=\"text-align:left\">";
	print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;name=BLAST\" class=\"resetbutton\">Reset</a></td><td style=\"text-align:right\" colspan=\"3\">";
	print $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
	print "</td></tr></table>\n";
	print $q->hidden($_) foreach qw (db page name);
	print "</div>\n";
	print $q->end_form;
	print "</div>\n";
	return;
}

sub _blast {
	my ( $self, $isolate_id, $seq_ref ) = @_;
	$$seq_ref =~ s/>.+\n//g; #Remove BLAST identifier lines if present
	my $seq_type = BIGSdb::Utils::sequence_type($$seq_ref);
	$$seq_ref =~ s/\s//g;
	my $program;
	if ( $seq_type eq 'DNA' ) {
		$program = $self->{'cgi'}->param('tblastx') ? 'tblastx' : 'blastn';
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
	my $qry =
"SELECT DISTINCT sequence_bin.id,sequence FROM sequence_bin LEFT JOIN experiment_sequences ON sequence_bin.id=seqbin_id LEFT JOIN project_members ON sequence_bin.isolate_id = project_members.isolate_id WHERE sequence_bin.isolate_id=?";
	my @criteria = ($isolate_id);
	my $method   = $self->{'cgi'}->param('seq_method_list');
	if ($method) {
		if ( !any { $_ eq $method } SEQ_METHODS ) {
			$logger->error("Invalid method $method");
			return;
		}
		$qry .= " AND method=?";
		push @criteria, $method;
	}
	my $project = $self->{'cgi'}->param('project_list');
	if ($project) {
		if ( !BIGSdb::Utils::is_int($project) ) {
			$logger->error("Invalid project $project");
			return;
		}
		$qry .= " AND project_id=?";
		push @criteria, $project;
	}
	my $experiment = $self->{'cgi'}->param('experiment_list');
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
	my $blastn_word_size = $self->{'cgi'}->param('word_size') =~ /(\d+)/ ? $1 : 11;
	my $hits             = $self->{'cgi'}->param('hits')      =~ /(\d+)/ ? $1 : 1;
	my $word_size = $program eq 'blastn' ? ($blastn_word_size) : 3;
	if ( $self->{'config'}->{'blast+_path'} ) {
		system("$self->{'config'}->{'blast+_path'}/makeblastdb -in $temp_fastafile -logfile /dev/null -parse_seqids -dbtype nucl");
		my $blast_threads = $self->{'config'}->{'blast_threads'} || 1;
		my $filter = $program eq 'blastn' ? 'dust' : 'seg';
		system(
"$self->{'config'}->{'blast+_path'}/$program -num_threads $blast_threads -max_target_seqs 10 -parse_deflines -word_size $word_size -db $temp_fastafile -query $temp_queryfile -out $temp_outfile -outfmt 6 -$filter no"
		);
	} else {
		system("$self->{'config'}->{'blast_path'}/formatdb -i $temp_fastafile -p F -o T");
		system(
"$self->{'config'}->{'blast_path'}/blastall -b $hits -p $program -W $word_size -d $temp_fastafile -i $temp_queryfile -o $temp_outfile -m8 -F F 2> /dev/null"
		);
	}
	my $matches = $self->_parse_blast( $outfile_url, $hits );

	#clean up
	system "rm -f $self->{'config'}->{'secure_tmp_dir'}/*$file_prefix*";
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
