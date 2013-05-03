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
package BIGSdb::SeqbinPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::IsolateInfoPage);
use BIGSdb::SeqbinToEMBL;
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');
use POSIX qw(ceil);

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (tooltips jQuery jQuery.slimbox jQuery.jstree);
	return;
}

sub print_content {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $isolate_id = $q->param('isolate_id');
	if ( !defined $isolate_id ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Isolate id not specified.</p></div>";
		return;
	}
	if ( !BIGSdb::Utils::is_int($isolate_id) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Isolate id must be an integer.</p></div>";
		return;
	}
	my $exists = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id )->[0];
	if ( !$exists ) {
		say "<div class=\"box\" id=\"statusbad\"><p>The database contains no record of this isolate.</p></div>";
		return;
	}
	my @name = $self->get_name($isolate_id);
	local $" = ' ';
	if (@name) {
		say "<h1>Sequence bin for @name</h1>";
	} else {
		say "<h1>Sequence bin for isolate id $isolate_id</h1>";
	}
	my $qry = "SELECT id,length(sequence) AS length,original_designation,method,comments,sender,curator,date_entered,datestamp "
	  . "FROM sequence_bin WHERE isolate_id=? ORDER BY length(sequence) desc";
	my $length_data = $self->{'datastore'}->run_list_query_hashref( $qry, $isolate_id );
	my $count = @$length_data;
	if ( !$count ) {
		say "<div class=\"box statusbad\"><p>This isolate has no sequence data attached.</p></div>";
		return;
	}
	say "<div class=\"box\" id=\"resultsheader\">";
	say "<div style=\"float:left\">";
	say "<h2>Contig summary statistics</h2>";
	say "<ul>\n<li>Number of contigs: $count</li>";
	my ( $data, $lengths, $n_stats );
	if ( $count > 1 ) {
		$data = $self->{'datastore'}->run_simple_query(
			"SELECT SUM(length(sequence)),MIN(length(sequence)),MAX(length(sequence)),CEIL(AVG(length(sequence))), "
			  . "CEIL(STDDEV_SAMP(length(sequence))) FROM sequence_bin WHERE isolate_id=?",
			$isolate_id
		);
		$lengths =
		  $self->{'datastore'}
		  ->run_list_query( "SELECT length(sequence) FROM sequence_bin WHERE isolate_id=? ORDER BY length(sequence) desc", $isolate_id );
		$n_stats = $self->get_N_stats( $data->[0], $lengths );
		print <<"HTML"
	<li>Total length: $data->[0]</li>
	<li>Minimum length: $data->[1]</li>
	<li>Maximum length: $data->[2]</li>
	<li>Mean length: $data->[3]</li>
	<li>&sigma; length: $data->[4]</li>
	<li>N50: $n_stats->{'N50'}</li>
	<li>N90: $n_stats->{'N90'}</li>
	<li>N95: $n_stats->{'N95'}</li>
	</ul>
HTML
	} else {
		my $length =
		  $self->{'datastore'}->run_simple_query( "SELECT length(sequence) FROM sequence_bin WHERE isolate_id=?", $isolate_id )->[0];
		say "<li>Length: $length</li>\n</ul>";
	}
	say "<ul><li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadSeqbin&amp;"
	  . "isolate_id=$isolate_id\">Download sequences (FASTA format)</a></li>";
	say "<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=embl&amp;isolate_id=$isolate_id\">"
	  . "Download sequences with annotations (EMBL format)</a></li></ul>";
	say "</div>";
	if ( $count > 1 ) {
		print "<div style=\"float:left;padding-left:2em\">\n";
		print "<h2>Contig size distribution</h2>\n";
		my $temp = BIGSdb::Utils::get_random();
		open( my $fh_output, '>', "$self->{'config'}->{'tmp_dir'}/$temp.txt" )
		  or $logger->error("Can't open temp file $self->{'config'}->{'tmp_dir'}/$temp.txt for writing");
		foreach my $length (@$lengths) {
			print $fh_output "$length\n";
		}
		close $fh_output;
		my $bins =
		  ceil( ( 3.5 * $data->[4] ) / $count**0.33 )
		  ;    #Scott's choice [Scott DW (1979). On optimal and data-based histograms. Biometrika 66(3):605–610]
		$bins = 1 if !$bins;
		my $width = ( $data->[2] - $data->[1] ) / $bins;

		#round width to nearest 500
		$width = int( $width - ( $width % 500 ) ) || 500;
		my ( $histogram, $min, $max ) = BIGSdb::Utils::histogram( $width, $lengths );
		my ( @labels, @values );
		foreach my $i ( $min .. $max ) {
			push @labels, $i * $width;
			push @values, $histogram->{$i};
		}
		if ( $self->{'config'}->{'chartdirector'} ) {
			my %prefs = ( 'offset_label' => 1, 'x-title' => 'Contig size (bp)', 'y-title' => 'Frequency' );
			BIGSdb::Charts::barchart( \@labels, \@values, "$self->{'config'}->{'tmp_dir'}/$temp\_large_histogram.png",
				'large', \%prefs, { no_transparent => 1 } );
			say "<a href=\"/tmp/$temp\_large_histogram.png\" rel=\"lightbox-1\" class=\"lightbox\" title=\"Contig size distribution\">"
			  . "<img src=\"/tmp/$temp\_large_histogram.png\" alt=\"Contig size distribution\" style=\"width:200px;border:1px "
			  . "dashed black\" /></a><br />Click to enlarge";
		}
		say "<ul><li><a href=\"/tmp/$temp.txt\">Download lengths</a></li></ul></div>";
		if ( $self->{'config'}->{'chartdirector'} ) {
			print "<div style=\"float:left;padding-left:2em\">\n";
			print "<h2>Cumulative contig length</h2>\n";
			my ( @contig_labels, @cumulative );
			push @contig_labels, $_ foreach ( 1 .. $count );
			my $total_length = 0;
			foreach (@$length_data) {
				$total_length += $_->{'length'};
				push @cumulative, $total_length;
			}
			my %prefs = ( 'offset_label' => 1, 'x-title' => 'Contig number', 'y-title' => 'Cumulative length' );
			BIGSdb::Charts::linechart( \@contig_labels, \@cumulative, "$self->{'config'}->{'tmp_dir'}/$temp\_cumulative_length.png",
				'large', \%prefs, { no_transparent => 1 } );
			say "<a href=\"/tmp/$temp\_cumulative_length.png\" rel=\"lightbox-1\" class=\"lightbox\" title=\"Cumulative contig length\">"
			  . "<img src=\"/tmp/$temp\_cumulative_length.png\" alt=\"Cumulative contig length\" style=\"width:200px;border:1px "
			  . "dashed black\" /></a></div>";
		}
	}
	say "<div style=\"clear:both\"></div>";
	say "</div><div class=\"box\" id=\"resultstable\">";
	say "<div class=\"scrollable\">";
	say "<table class=\"resultstable\"><tr><th>Sequence</th><th>Sequencing method</th><th>Original designation</th><th>Length</th>"
	  . "<th>Comments</th><th>Locus</th><th>Start</th><th>End</th><th>Direction</th><th>EMBL format</th><th>Artemis <a class=\"tooltip\" "
	  . "title=\"Artemis - This will launch Artemis using Java WebStart.  The contig annotations should open within Artemis but this "
	  . "may depend on your operating system and version of Java.  If the annotations do not open within Artemis, download the EMBL "
	  . "file locally and load manually in to Artemis.\">&nbsp;<i>i</i>&nbsp;</a></th>";
	if ( $self->{'curate'} && ( $self->{'permissions'}->{'modify_loci'} || $self->is_admin ) ) {
		say "<th>Renumber <a class=\"tooltip\" title=\"Renumber - You can use the numbering of the sequence tags to automatically "
		  . "set the genome order position for each locus. This will be used to order the sequences when exporting FASTA or XMFA files."
		  . "\">&nbsp;<i>i</i>&nbsp;</a></th>";
	}
	print "</tr>\n";
	my $td     = 1;
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? "AND (locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes "
	  . "WHERE set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';
	$qry = "SELECT * FROM allele_sequences WHERE seqbin_id = ? $set_clause ORDER BY start_pos";
	my $seq_sql = $self->{'db'}->prepare($qry);
	local $" = 1;

	foreach my $data (@$length_data) {
		eval { $seq_sql->execute( $data->{'id'} ) };
		$logger->error($@) if $@;
		my $allele_count =
		  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM allele_sequences WHERE seqbin_id=? $set_clause", $data->{'id'} )
		  ->[0];
		my $first = 1;
		if ($allele_count) {
			print "<tr class=\"td$td\">";
			my $open_td = "<td rowspan=\"$allele_count\" style=\"vertical-align:top\">";
			print "$open_td$data->{'id'}</td>";
			print "$open_td$data->{'method'}</td>";
			$data->{'original_designation'} ||= '';
			print "$open_td$data->{'original_designation'}</td>";
			print "$open_td$data->{'length'}</td>";
			$data->{'comments'} ||= '';
			print "$open_td$data->{'comments'}</td>";

			while ( my $allele_seq = $seq_sql->fetchrow_hashref ) {
				print "<tr class=\"td$td\">" if !$first;
				my $cleaned_locus = $self->clean_locus( $allele_seq->{'locus'} );
				print "<td>$cleaned_locus "
				  . ( $allele_seq->{'complete'} ? '' : '*' )
				  . "</td><td>$allele_seq->{'start_pos'}</td><td>$allele_seq->{'end_pos'}</td>";
				print "<td style=\"font-size:2em\">" . ( $allele_seq->{'reverse'} ? '&larr;' : '&rarr;' ) . "</td>";
				if ($first) {
					print "<td rowspan=\"$allele_count\" style=\"vertical-align:top\">";
					print $q->start_form;
					$q->param( 'page',      'embl' );
					$q->param( 'seqbin_id', $data->{'id'} );
					print $q->hidden($_) foreach qw (page db seqbin_id);
					print $q->submit( -name => 'EMBL', -class => 'smallbutton' );
					print $q->end_form;
					print "</td><td rowspan=\"$allele_count\" style=\"vertical-align:top\">";
					my $jnlp = $self->_make_artemis_jnlp( $data->{'id'} );
					print $q->start_form( -method => 'get', -action => "/tmp/$jnlp" );
					print $q->submit( -name => 'Artemis', -class => 'smallbutton' );
					print $q->end_form;
					print "</td>";

					if ( $self->{'curate'} && ( $self->{'permissions'}->{'modify_loci'} || $self->is_admin ) ) {
						print "<td rowspan=\"$allele_count\" style=\"vertical-align:top\">";
						print $q->start_form;
						$q->param( 'page',      'renumber' );
						$q->param( 'seqbin_id', $data->{'id'} );
						print $q->hidden($_) foreach qw (page db seqbin_id);
						print $q->submit( -name => 'Renumber', -class => 'smallbutton' );
						print $q->end_form;
						print "</td>";
					}
				}
				say "</tr>";
				$first = 0;
			}
		} else {
			print "<tr class=\"td$td\"><td>$data->{'id'}</td>";
			print defined $data->{'method'} ? "<td>$data->{'method'}</td>" : '<td />';
			print defined $data->{'original_designation'} ? "<td>$data->{'original_designation'}</td>" : '<td />';
			print "<td>$data->{'length'}</td>";
			print defined $data->{'comments'} ? "<td>$data->{'comments'}</td>" : '<td />';
			print "<td /><td /><td /><td /><td /><td />";
			print "<td />" if $self->{'curate'};
			say "</tr>";
		}
		$td = $td == 1 ? 2 : 1;
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
	}
	say "</table></div>\n</div>";
	return;
}

sub _make_artemis_jnlp {
	my ( $self, $seqbin_id ) = @_;
	my $temp          = BIGSdb::Utils::get_random();
	my $jnlp_filename = "$temp\_$seqbin_id.jnlp";

	# if access is not public or access is via curation interface then
	# EMBL files will need to be created and placed in a public location
	# for Artemis to be able to load them.  Public access databases can
	# create the EMBL file on demand, which is quicker and prevents cluttering
	# the temporary directory.
	my $url;
	if ( $self->{'system'}->{'read_access'} ne 'public' || $self->{'curate'} ) {
		my $embl_filename = "$temp\_$seqbin_id.embl";
		open( my $fh_embl, '>', "$self->{'config'}->{'tmp_dir'}/$embl_filename" );
		my %page_attributes = (
			'system'    => $self->{'system'},
			'cgi'       => $self->{'cgi'},
			'instance'  => $self->{'instance'},
			'datastore' => $self->{'datastore'},
			'db'        => $self->{'db'},
		);
		my $seqbin_to_embl = BIGSdb::SeqbinToEMBL->new(%page_attributes);
		print $fh_embl $seqbin_to_embl->write_embl( [$seqbin_id], { 'get_buffer' => 1 } );
		close $fh_embl;
		$url = "http://" . $self->{'cgi'}->virtual_host . "/tmp/$embl_filename";
	} else {
		$url =
		    'http://'
		  . $self->{'cgi'}->virtual_host
		  . "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=embl&amp;seqbin_id=$seqbin_id";
	}
	open( my $fh, '>', "$self->{'config'}->{'tmp_dir'}/$jnlp_filename" )
	  || $logger->error("Can't open $self->{'config'}->{'tmp_dir'}/$jnlp_filename for writing.");
	print $fh <<"JNLP";
<?xml version="1.0" encoding="UTF-8"?>
<jnlp
        spec="1.0+"
        codebase="http://www.sanger.ac.uk/resources/software/artemis/java/"
        href="artemis.jnlp">
         <information>
           <title>Artemis</title>
           <vendor>Sanger Institute</vendor> 
           <homepage href="http://www.sanger.ac.uk/resources/software/artemis/"/>
           <description>Artemis</description>
           <description kind="short">DNA sequence viewer and annotation tool.
           </description>
           <offline-allowed/>
         </information>
         <security>
           <all-permissions/>
         </security>
         <resources>
           <j2se version="1.5+" initial-heap-size="32m" max-heap-size="400m"/>
           <jar href="sartemis.jar"/>
           <property name="com.apple.mrj.application.apple.menu.about.name" value="Artemis" />
           <property name="artemis.environment" value="UNIX" />
           <property name="j2ssh" value="" />
           <property name="apple.laf.useScreenMenuBar" value="true" />
         </resources>
         <application-desc main-class="uk.ac.sanger.artemis.components.ArtemisMain">
           <argument>$url</argument>
         </application-desc>
</jnlp>
JNLP
	close $fh;
	return $jnlp_filename;
}

sub get_title {
	my ($self) = @_;
	my $isolate_id = $self->{'cgi'}->param('isolate_id');
	return " Invalid isolate id " if !BIGSdb::Utils::is_int($isolate_id);
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	if ($isolate_id) {
		my @name = $self->get_name($isolate_id);
		local $" = ' ';
		return "Sequence bin: id-$isolate_id (@name)" if $name[1];
	}
	return "Sequence bin - $desc";
}

sub get_N_stats {

	#Array of lengths must be in descending length order.
	my ( $self, $total_length, $contig_length_arrayref ) = @_;
	my $n50_target = 0.5 * $total_length;
	my $n90_target = 0.1 * $total_length;
	my $n95_target = 0.05 * $total_length;
	my $stats;
	my $running_total = $total_length;
	foreach my $length (@$contig_length_arrayref) {
		$running_total -= $length;
		$stats->{'N50'} = $length if !defined $stats->{'N50'} && $running_total <= $n50_target;
		$stats->{'N90'} = $length if !defined $stats->{'N90'} && $running_total <= $n90_target;
		$stats->{'N95'} = $length if !defined $stats->{'N95'} && $running_total <= $n95_target;
	}
	return $stats;
}
1;
