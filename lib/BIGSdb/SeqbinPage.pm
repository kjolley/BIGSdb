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

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/data_records.html#sequence-bin-records";
}

sub print_content {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $isolate_id = $q->param('isolate_id');
	if ( !defined $isolate_id ) {
		say q(<div class="box" id="statusbad"><p>Isolate id not specified.</p></div>);
		return;
	}
	if ( !BIGSdb::Utils::is_int($isolate_id) ) {
		say q(<div class="box" id="statusbad"><p>Isolate id must be an integer.</p></div>);
		return;
	}
	my $exists =
	  $self->{'datastore'}
	  ->run_query( "SELECT EXISTS(SELECT * FROM $self->{'system'}->{'view'} WHERE id=?)", $isolate_id );
	if ( !$exists ) {
		say q(<div class="box" id="statusbad"><p>The database contains no record of this isolate.</p></div>);
		return;
	}
	my $name = $self->get_name($isolate_id);
	if ($name) {
		say qq(<h1>Sequence bin for $name</h1>);
	} else {
		say qq(<h1>Sequence bin for isolate id $isolate_id</h1>);
	}
	my $qry = 'SELECT id,length(sequence) AS length,original_designation,method,comments,sender,'
	  . 'curator,date_entered,datestamp FROM sequence_bin WHERE isolate_id=? ORDER BY length(sequence) desc';
	my $length_data = $self->{'datastore'}->run_query( $qry, $isolate_id, { fetch => 'all_arrayref', slice => {} } );
	my $count = @$length_data;
	if ( !$count ) {
		say q(<div class="box statusbad"><p>This isolate has no sequence data attached.</p></div>);
		return;
	}
	$self->_print_stats( $isolate_id, $length_data );
	$self->_print_contig_table( $isolate_id, $length_data );
	return;
}

sub _print_stats {
	my ( $self, $isolate_id, $length_data ) = @_;
	my $count = @$length_data;
	say q(<div class="box" id="resultsheader">);
	say q(<div style="float:left">);
	say q(<h2>Contig summary statistics</h2>);
	say qq(<dl class="data"><dt>Contigs</dt><dd>$count</dd>);
	my ( $data, $lengths, $n_stats );
	if ( $count > 1 ) {
		$data = $self->{'datastore'}->run_query(
			'SELECT SUM(length(sequence)),MIN(length(sequence)),MAX(length(sequence)),CEIL(AVG(length(sequence))), '
			  . 'CEIL(STDDEV_SAMP(length(sequence))) FROM sequence_bin WHERE isolate_id=?',
			$isolate_id,
			{ fetch => 'row_arrayref' }
		);
		$lengths =
		  $self->{'datastore'}
		  ->run_query( 'SELECT length(sequence) FROM sequence_bin WHERE isolate_id=? ORDER BY length(sequence) desc',
			$isolate_id, { fetch => 'col_arrayref' } );
		$n_stats = BIGSdb::Utils::get_N_stats( $data->[0], $lengths );
		my %stats_labels = (
			N50 => 'N50 contig number',
			L50 => 'N50 length (L50)',
			N90 => 'N90 contig number',
			L90 => 'N90 length (L90)',
			N95 => 'N95 contig number',
			L95 => 'N95 length (L95)',
		);
		say qq(<dt>Total length</dt><dd>$data->[0]</dd>);
		say qq(<dt>Minimum length</dt><dd>$data->[1]</dd>);
		say qq(<dt>Maximum length</dt><dd>$data->[2]</dd>);
		say qq(<dt>Mean length</dt><dd>$data->[3]</dd>);
		say qq(<dt>&sigma; length</dt><dd>$data->[4]</dd>);
		say qq(<dt>$stats_labels{$_}</dt><dd>$n_stats->{$_}</dd>) foreach qw(N50 L50 N90 L90 N95 L95);
		say q(</dl>);
	} else {
		my $length =
		  $self->{'datastore'}
		  ->run_query( 'SELECT length(sequence) FROM sequence_bin WHERE isolate_id=?', $isolate_id );
		say qq(<dt>Length</dt><dd>$length</dd></dl>);
	}
	say qq(<ul><li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=downloadSeqbin&amp;isolate_id=$isolate_id">Download sequences (FASTA format)</a></li>);
	say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=embl&amp;)
	  . qq(isolate_id=$isolate_id">Download sequences with annotations (EMBL format)</a></li></ul>);
	say q(</div>);
	if ( $count > 1 ) {
		say q(<div style="float:left;padding-left:2em">);
		say q(<h2>Contig size distribution</h2>);
		my $temp = BIGSdb::Utils::get_random();
		open( my $fh_output, '>', "$self->{'config'}->{'tmp_dir'}/$temp.txt" )
		  or $logger->error("Can't open temp file $self->{'config'}->{'tmp_dir'}/$temp.txt for writing");
		foreach my $length (@$lengths) {
			say $fh_output $length;
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
			BIGSdb::Charts::barchart( \@labels, \@values, "$self->{'config'}->{'tmp_dir'}/${temp}_large_histogram.png",
				'large', \%prefs, { no_transparent => 1 } );
			say qq(<a href="/tmp/${temp}_large_histogram.png" data-rel="lightbox-1" class="lightbox" )
			  . qq(title="Contig size distribution"><img src="/tmp/$temp\_large_histogram.png" alt="Contig size distribution" )
			  . q(style="width:200px;border:1px dashed black" /></a><br />Click to enlarge);
		}
		say qq(<ul><li><a href="/tmp/$temp.txt">Download lengths</a></li></ul></div>);
		if ( $self->{'config'}->{'chartdirector'} ) {
			say q(<div style="float:left;padding-left:2em">);
			say q(<h2>Cumulative contig length</h2>);
			my ( @contig_labels, @cumulative );
			push @contig_labels, $_ foreach ( 1 .. $count );
			my $total_length = 0;
			foreach (@$length_data) {
				$total_length += $_->{'length'};
				push @cumulative, $total_length;
			}
			my %prefs = ( offset_label => 1, 'x-title' => 'Contig number', 'y-title' => 'Cumulative length' );
			BIGSdb::Charts::linechart( \@contig_labels, \@cumulative,
				"$self->{'config'}->{'tmp_dir'}/${temp}_cumulative_length.png",
				'large', \%prefs, { no_transparent => 1 } );
			say qq(<a href="/tmp/${temp}_cumulative_length.png" data-rel="lightbox-1" class="lightbox" )
			  . qq(title="Cumulative contig length"><img src="/tmp/${temp}_cumulative_length.png" )
			  . q(alt="Cumulative contig length" style="width:200px;border:1px dashed black" /></a></div>);
		}
	}
	say q(<div style="clear:both"></div></div>);
	return;
}

sub _print_contig_table {
	my ( $self, $isolate_id, $length_data ) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="resultstable">);
	say q(<div class="scrollable">);
	my $seq_attributes =
	  $self->{'datastore'}
	  ->run_query( 'SELECT key FROM sequence_attributes ORDER BY key', undef, { fetch => 'col_arrayref' } );
	my @cleaned_attributes = @$seq_attributes;
	s/_/ / foreach @cleaned_attributes;
	local $" = q(</th><th>);
	my $att_headings = @cleaned_attributes ? qq(<th>@cleaned_attributes</th>) : q();
	say q(<table class="resultstable"><tr><th>Sequence</th><th>Sequencing method</th>)
	  . qq(<th>Original designation</th><th>Length</th><th>Comments</th>$att_headings<th>Locus</th>)
	  . q(<th>Start</th><th>End</th><th>Direction</th><th>EMBL format</th><th>Artemis )
	  . q(<a class="tooltip" title="Artemis - This will launch Artemis using Java WebStart. )
	  . q(The contig annotations should open within Artemis but this may depend on your operating system )
	  . q(and version of Java.  If the annotations do not open within Artemis, download the EMBL file )
	  . q(locally and load manually in to Artemis."><span class="fa fa-info-circle" style="color:white"></span>)
	  . q(</a></th>);

	if ( $self->{'curate'} && ( $self->{'permissions'}->{'modify_loci'} || $self->is_admin ) ) {
		say q(<th>Renumber <a class="tooltip" title="Renumber - You can use the numbering of the )
		  . q(sequence tags to automatically set the genome order position for each locus. This will )
		  . q(be used to order the sequences when exporting FASTA or XMFA files.">)
		  . q(<span class="fa fa-info-circle" style="color:white"></span></a></th>);
	}
	say q(</tr>);
	my $td     = 1;
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? 'AND (locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes '
	  . "WHERE set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';
	local $| = 1;
	foreach my $data (@$length_data) {
		$logger->error($@) if $@;
		my $allele_count =
		  $self->{'datastore'}->run_query( "SELECT COUNT(*) FROM allele_sequences WHERE seqbin_id=? $set_clause",
			$data->{'id'}, { cache => 'SeqbinPage::print_content::count' } );
		my $att_values =
		  $self->{'datastore'}->run_query( 'SELECT key,value FROM sequence_attribute_values WHERE seqbin_id=?',
			$data->{'id'}, { fetch => 'all_hashref', key => 'key', cache => 'SeqbinPage::print_content::keyvalue' } );
		my $first = 1;
		if ($allele_count) {
			print qq(<tr class="td$td">);
			my $open_td = qq(<td rowspan="$allele_count" style="vertical-align:top">);
			print qq($open_td$data->{'id'}</td>);
			print qq($open_td$data->{'method'}</td>);
			$data->{'original_designation'} //= q();
			print qq($open_td$data->{'original_designation'}</td>);
			print qq($open_td$data->{'length'}</td>);
			$data->{'comments'} //= q();
			print qq($open_td$data->{'comments'}</td>);

			foreach my $att (@$seq_attributes) {
				$att_values->{$att}->{'value'} //= '';
				print qq($open_td$att_values->{$att}->{'value'}</td>);
			}
			my $allele_seqs =
			  $self->{'datastore'}
			  ->run_query( "SELECT * FROM allele_sequences WHERE seqbin_id=? $set_clause ORDER BY start_pos",
				$data->{'id'},
				{ fetch => 'all_arrayref', slice => {}, cache => 'SeqbinPage::print_content::allele_sequences' } );
			foreach my $allele_seq (@$allele_seqs) {
				print "<tr class=\"td$td\">" if !$first;
				my $cleaned_locus = $self->clean_locus( $allele_seq->{'locus'} );
				say qq(<td>$cleaned_locus )
				  . ( $allele_seq->{'complete'} ? '' : '*' )
				  . qq(</td><td>$allele_seq->{'start_pos'}</td><td>$allele_seq->{'end_pos'}</td>);
				say q(<td style="font-size:2em">) . ( $allele_seq->{'reverse'} ? q(&larr;) : q(&rarr;) ) . q(</td>);
				if ($first) {
					say qq(<td rowspan="$allele_count" style="vertical-align:top">);
					say $q->start_form;
					$q->param( page      => 'embl' );
					$q->param( seqbin_id => $data->{'id'} );
					say $q->hidden($_) foreach qw (page db seqbin_id);
					say $q->submit( -name => 'EMBL', -class => 'smallbutton' );
					say $q->end_form;
					say qq(</td><td rowspan="$allele_count" style="vertical-align:top">);
					my $jnlp = $self->_make_artemis_jnlp( $data->{'id'} );
					say $q->start_form( -method => 'get', -action => "/tmp/$jnlp" );
					say $q->submit( -name => 'Artemis', -class => 'smallbutton' );
					say $q->end_form;
					say q(</td>);

					if ( $self->{'curate'} && ( $self->{'permissions'}->{'modify_loci'} || $self->is_admin ) ) {
						say qq(<td rowspan="$allele_count" style="vertical-align:top">);
						say $q->start_form;
						$q->param( page      => 'renumber' );
						$q->param( seqbin_id => $data->{'id'} );
						say $q->hidden($_) foreach qw (page db seqbin_id);
						say $q->submit( -name => 'Renumber', -class => 'smallbutton' );
						say $q->end_form;
						say q(</td>);
					}
				}
				say q(</tr>);
				$first = 0;
			}
		} else {
			say qq(<tr class="td$td"><td>$data->{'id'}</td>);
			say defined $data->{'method'} ? qq(<td>$data->{'method'}</td>) : q(<td /></td>);
			say defined $data->{'original_designation'} ? qq(<td>$data->{'original_designation'}</td>) : q(<td></td>);
			say qq(<td>$data->{'length'}</td>);
			print defined $data->{'comments'} ? qq(<td>$data->{'comments'}</td>) : q(<td></td>);
			foreach my $att (@$seq_attributes) {
				$att_values->{$att}->{'value'} //= q();
				say qq(<td>$att_values->{$att}->{'value'}</td>);
			}
			say q(<td></td><td></td><td></td><td></td><td></td><td></td>);
			say q(<td></td>) if $self->{'curate'};
			say q(</tr>);
		}
		$td = $td == 1 ? 2 : 1;
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
	}
	say q(</table></div></div>);
	return;
}

sub _make_artemis_jnlp {
	my ( $self, $seqbin_id ) = @_;
	my $temp          = BIGSdb::Utils::get_random();
	my $jnlp_filename = "${temp}_$seqbin_id.jnlp";

	# if access is not public or access is via curation interface then
	# EMBL files will need to be created and placed in a public location
	# for Artemis to be able to load them.  Public access databases can
	# create the EMBL file on demand, which is quicker and prevents cluttering
	# the temporary directory.
	my $url;
	my $ssl = $self->{'cgi'}->https;
	my $prefix = $ssl ? 'https://' : 'http://';
	if ( $self->{'system'}->{'read_access'} ne 'public' || $self->{'curate'} ) {
		my $embl_filename = "$temp\_$seqbin_id.embl";
		my $full_path     = "$self->{'config'}->{'tmp_dir'}/$embl_filename";
		open( my $fh_embl, '>', $full_path ) || $logger->error("Can't open $full_path for writing");
		my %page_attributes = (
			system    => $self->{'system'},
			cgi       => $self->{'cgi'},
			instance  => $self->{'instance'},
			datastore => $self->{'datastore'},
			db        => $self->{'db'},
		);
		my $seqbin_to_embl = BIGSdb::SeqbinToEMBL->new(%page_attributes);
		print $fh_embl $seqbin_to_embl->write_embl( [$seqbin_id], { get_buffer => 1 } );
		close $fh_embl;
		$url = $prefix . $self->{'cgi'}->virtual_host . qq(/tmp/$embl_filename);
	} else {
		$url =
		    $prefix
		  . $self->{'cgi'}->virtual_host
		  . qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=embl&amp;seqbin_id=$seqbin_id);
	}
	open( my $fh, '>', "$self->{'config'}->{'tmp_dir'}/$jnlp_filename" )
	  || $logger->error("Can't open $self->{'config'}->{'tmp_dir'}/$jnlp_filename for writing.");
	print $fh <<"JNLP";
<?xml version="1.0" encoding="UTF-8"?>
<jnlp spec="1.0+" codebase="http://www.genedb.org/artemis/">
 <information>
   <title>Artemis</title>
   <vendor>Sanger Institute</vendor> 
   <homepage href="http://www.sanger.ac.uk/resources/software/artemis/"/>
   <description>Artemis</description>
   <description kind="short">DNA sequence viewer and annotation tool.</description>
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
	return 'Invalid isolate id' if !BIGSdb::Utils::is_int($isolate_id);
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	if ($isolate_id) {
		my $name = $self->get_name($isolate_id);
		return qq(Sequence bin: id-$isolate_id ($name)) if $name;
	}
	return qq(Sequence bin - $desc);
}
1;
