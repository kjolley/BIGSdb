#SeqbinBreakdown.pm - SeqbinBreakdown plugin for BIGSdb
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
package BIGSdb::Plugins::SeqbinBreakdown;
use strict;
use warnings;
use parent qw(BIGSdb::Plugin BIGSdb::SeqbinPage);
use Log::Log4perl qw(get_logger);
use POSIX qw(ceil);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use BIGSdb::Page qw(SEQ_METHODS);

sub get_attributes {
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
		version     => '1.0.3',
		dbtype      => 'isolates',
		section     => 'breakdown,postquery',
		input       => 'query',
		order       => 80,
		system_flag => 'SeqbinBreakdown'
	);
	return \%att;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { 'general' => 0, 'main_display' => 0, 'isolate_display' => 0, 'analysis' => 0, 'query_field' => 0 };
	return;
}

sub get_option_list {
	my @methods = ( 'all', SEQ_METHODS );
	local $" = ';';
	my @list = ( { name => 'method', description => 'Filter by sequencing method', optlist => "@methods", default => 'all' }, );
	return \@list;
}

sub run {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $qry_ref    = $self->get_query($query_file);
	print "<h1>Breakdown of sequence bin contig properties</h1>\n";
	if ( ref $qry_ref ne 'SCALAR' ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Error retrieving query.</p></div>\n";
		return;
	}
	my $qry = $$qry_ref;
	$qry =~ s/ORDER BY.*$//g;
	$logger->debug("Breakdown query: $qry");
	return if !$self->create_temp_tables($qry_ref);
	my $view = $self->{'system'}->{'view'};
	$qry =~ s/SELECT ($view\.\*|\*)/SELECT id/;
	my %prefs;
	my $guid = $self->get_guid;
	try {
		$prefs{'method'} = $self->{'prefstore'}->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'SeqbinBreakdown', 'method' );
	}
	catch BIGSdb::DatabaseNoRecordException with {
		$prefs{'method'} = 'all';
	};
	my $method_clause = $prefs{'method'} ne 'all' ? " AND method='$prefs{'method'}'" : '';
	my $seqbin_count =
	  $self->{'datastore'}->run_list_query("SELECT COUNT(*) FROM sequence_bin WHERE isolate_id IN ($qry)$method_clause")->[0];
	if ( !$seqbin_count ) {
		print "<div class=\"box\" id=\"statusbad\"><p>There are no sequences stored for any of the selected isolates generated with "
		  . "the sequence method (set in options).</p></div>\n";
		return;
	}
	$qry .= " ORDER BY id";
	my $ids = $self->{'datastore'}->run_list_query($qry);
	my $sql =
	  $self->{'db'}->prepare( "SELECT COUNT(sequence), SUM(length(sequence)),MIN(length(sequence)),MAX(length(sequence)), "
		  . "CEIL(AVG(length(sequence))), CEIL(STDDEV_SAMP(length(sequence))) FROM sequence_bin WHERE isolate_id=?$method_clause" );
	my $sql_name = $self->{'db'}->prepare("SELECT $self->{'system'}->{'labelfield'} FROM $view WHERE id=?");
	my $sql_contig_lengths =
	  $self->{'db'}
	  ->prepare( "SELECT length(sequence) FROM sequence_bin WHERE isolate_id=?$method_clause ORDER BY " . "length(sequence) DESC" );
	my $sql_tagged =
	  $self->{'db'}->prepare( "SELECT COUNT(DISTINCT locus) FROM allele_sequences LEFT JOIN sequence_bin ON seqbin_id = "
		  . "sequence_bin.id WHERE isolate_id=?" );
	my $labelfield = ucfirst( $self->{'system'}->{'labelfield'} );
	my $temp       = BIGSdb::Utils::get_random();
	open( my $fh, '>', "$self->{'config'}->{'tmp_dir'}/$temp.txt" )
	  or $logger->error("Can't open temp file $self->{'config'}->{'tmp_dir'}/$temp.txt for writing");
	print << "HTML"
<div class="box" id="resultstable">
<table class="tablesorter" id="sortTable">
<thead>
<tr><th>Isolate id</th><th>$labelfield</th><th>Contigs</th><th>Total length</th><th>Min</th><th>Max</th><th>Mean</th><th>&sigma;</th>
<th>N50</th><th>N90</th><th>N95</th><th>% Alleles designated</th><th>% Loci tagged</th><th>Sequence bin</th></tr>
</thead>
<tbody>
HTML
	  ;
	print $fh "Isolate id\t$labelfield\tContigs\tTotal length\tMin\tMax\tMean\tStdDev\t"
	  . "N50\tN90\tN95\t%Allele designated\t%Loci tagged\n";
	my $td = 1;
	local $| = 1;
	my ($data);
	my $loci = $self->{'datastore'}->get_loci;

	foreach (@$ids) {
		eval {
			$sql->execute($_);
			$sql_name->execute($_);
			$sql_contig_lengths->execute($_);
		};
		if ($@) {
			$logger->error($@);
			return;
		}
		my @single_isolate_lengths;
		my ( $contigs, $sum, $min, $max, $mean, $stddev ) = $sql->fetchrow_array;
		while ( my ($length) = $sql_contig_lengths->fetchrow_array ) {
			push @{ $data->{'lengths'} }, $length;
			push @single_isolate_lengths, $length;
		}
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
		next if !$contigs;
		my ($isolate) = $sql_name->fetchrow_array;
		my $allele_designations = $self->{'datastore'}->get_all_allele_ids($_);
		my $percent_alleles = BIGSdb::Utils::decimal_place( 100 * ( scalar keys %$allele_designations ) / @$loci, 1 );
		eval { $sql_tagged->execute($_) };
		$logger->error($@) if $@;
		my ($tagged) = $sql_tagged->fetchrow_array;
		my $percent_tagged = BIGSdb::Utils::decimal_place( 100 * ( $tagged / @$loci ), 1 );
		my $n_stats = $self->get_N_stats( $sum, \@single_isolate_lengths );
		print "<tr class=\"td$td\"><td>$_</td>";
		print "<td>$isolate</td><td>$contigs</td><td>$sum</td><td>$min</td><td>$max</td><td>$mean</td>";
		print defined $stddev ? "<td>$stddev</td>" : '<td />';
		print "<td>$n_stats->{'N50'}</td><td>$n_stats->{'N90'}</td><td>$n_stats->{'N95'}</td>"
		  . "<td>$percent_alleles</td><td>$percent_tagged</td>";
		print
"<td><a href=\"$self->{'system'}->{'script_name'}?page=seqbin&amp;db=$self->{'instance'}&amp;isolate_id=$_\" class=\"extract_tooltip\" target=\"_blank\">Display &rarr;</a></td></tr>\n";
		print $fh "$_\t$isolate\t$contigs\t$sum\t$min\t$max\t$mean\t";
		print $fh "$stddev" if defined $stddev;
		print $fh "\t$n_stats->{'N50'}\t$n_stats->{'N90'}\t$n_stats->{'N95'}\t$percent_alleles\t$percent_tagged\n";
		push @{ $data->{'contigs'} }, $contigs;
		push @{ $data->{'sum'} },     $sum;
		push @{ $data->{'mean'} },    $mean;
		$td = $td == 1 ? 2 : 1;
	}
	print "</tbody></table>\n";
	close $fh;
	print "<p><a href=\"/tmp/$temp.txt\">Download in tab-delimited text format</a></p>\n";
	print "</div>\n";
	$self->_print_charts( $data, $temp ) if $self->{'config'}->{'chartdirector'};
	return;
}

sub _print_charts {
	my ( $self, $data, $prefix ) = @_;
	print "<div class=\"box\" id=\"resultsfooter\">\n";
	my %title =
	  ( 'contigs' => 'Number of contigs', 'sum' => 'Total length', 'mean' => 'Mean contig length', 'lengths' => 'Contig lengths' );
	print "<p>Click on the following charts to enlarge</p>\n";
	foreach (qw (contigs sum mean lengths)) {
		my $stats = BIGSdb::Utils::stats( $data->{$_} );
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
		my ( $histogram, $min, $max ) = BIGSdb::Utils::histogram( $width, $data->{$_} );
		my ( @labels, @values );
		foreach my $i ( $min .. $max ) {
			push @labels, $i * $width;
			push @values, $histogram->{$i};
		}
		my %prefs = ( 'offset_label' => 1, 'x-title' => $title{$_}, 'y-title' => 'Frequency' );
		BIGSdb::Charts::barchart( \@labels, \@values, "$self->{'config'}->{'tmp_dir'}/$prefix\_histogram_$_.png", 'large', \%prefs );
		print "<div style=\"float:left;padding-right:1em\">\n";
		print "<h2>$title{$_}</h2>\n";
		print "Overall mean: "
		  . BIGSdb::Utils::decimal_place( $stats->{'mean'}, 1 )
		  . "; &sigma;: "
		  . BIGSdb::Utils::decimal_place( $stats->{'std'}, 1 )
		  . "<br />";
		print
"<a href=\"/tmp/$prefix\_histogram_$_.png\" target=\"_blank\"><img src=\"/tmp/$prefix\_histogram_$_.png\" alt=\"$_ histogram\" style=\"width:300px; border:0\" /></a>\n";
		if ( $_ eq 'lengths' ) {
			my $filename  = BIGSdb::Utils::get_random() . '.txt';
			my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
			if ( open( my $fh, '>', $full_path ) ) {
				foreach my $length ( sort { $a <=> $b } @{ $data->{'lengths'} } ) {
					print $fh "$length\n";
				}
				close $fh;
				print "<p><a href=\"/tmp/$filename\">Download lengths</a></p>\n" if -e $full_path && !-z $full_path;
			} else {
				$logger->error("Can't open $full_path for writing");
			}
		}
		print "</div>\n";
	}
	print "<div style=\"clear:both\"></div></div>\n";
	return;
}
1;
