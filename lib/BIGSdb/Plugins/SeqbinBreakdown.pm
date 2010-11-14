#SeqbinBreakdown.pm - SeqbinBreakdown plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010, University of Oxford
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
use base qw(BIGSdb::Plugin);
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
		version     => '1.0.0',
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
}

sub get_option_list {
	my @methods = ('all', SEQ_METHODS);
	$"=';';
	my @list = (
		{
			name        => 'method',
			description => 'Filter by sequencing method',
			optlist     => "@methods",
			default     => 'all'
		},
	);
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
		$prefs{'method'} =
		  $self->{'prefstore'}
		  ->get_plugin_attribute( $guid, $self->{'system'}->{'db'},
			'SeqbinBreakdown', 'method' );
	  }
	  catch BIGSdb::DatabaseNoRecordException with {
		$prefs{'method'} = 'all';
	  };
	my $method_clause;
	if ($prefs{'method'} ne 'all'){
		$method_clause = " AND method='$prefs{'method'}'";
	}
	
	my $seqbin_count = $self->{'datastore'}->run_list_query("SELECT COUNT(*) FROM sequence_bin WHERE isolate_id IN ($qry)$method_clause")->[0];
	if (!$seqbin_count){
		print "<div class=\"box\" id=\"statusbad\"><p>There are no sequences stored for any of the selected isolates generated with the sequence method (set in options).</p></div>\n";
		return;
	}
	
	$qry .= " ORDER BY id";
	my $ids = $self->{'datastore'}->run_list_query($qry);
	my $sql =
	  $self->{'db'}->prepare(
"SELECT COUNT(sequence), SUM(length(sequence)),MIN(length(sequence)),MAX(length(sequence)), CEIL(AVG(length(sequence))), CEIL(STDDEV_SAMP(length(sequence))) FROM sequence_bin WHERE isolate_id=?$method_clause"
	  );
	my $sql_name = $self->{'db'}->prepare("SELECT $self->{'system'}->{'labelfield'} FROM $view WHERE id=?");
	my $labelfield = ucfirst($self->{'system'}->{'labelfield'});
	my $temp = BIGSdb::Utils::get_random();
	open( my $fh, '>', "$self->{'config'}->{'tmp_dir'}/$temp.txt" )
	  			or $logger->error("Can't open temp file $self->{'config'}->{'tmp_dir'}/$temp.txt for writing");
	print << "HTML"
<div class="box" id="resultstable">
<table class="tablesorter" id="sortTable">
<thead>
<tr><th>Isolate id</th><th>$labelfield</th><th>Contigs</th><th>Total length</th><th>Min</th><th>Max</th><th>Mean</th><th>&sigma;</th><th>Sequence bin</th></tr>
</thead>
<tbody>
HTML
	  ;
	print $fh "Isolate id\t$labelfield\tContigs\tTotal length\tMin\tMax\tMean\tStdDev\n";
	my $td = 1;
	$|=1;
	my ($data);
	foreach (@$ids) {
		eval {
			$sql->execute($_);
			$sql_name->execute($_);
		};
		if ($@){
			$logger->error("Can't execute $@");
			return;
		}
		my ($contigs,$sum,$min,$max,$mean,$stddev) = $sql->fetchrow_array;
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
		next if !$contigs;
		my ($isolate) = $sql_name->fetchrow_array;
		print "<tr class=\"td$td\"><td>$_</td><td>$isolate</td><td>$contigs</td><td>$sum</td><td>$min</td><td>$max</td><td>$mean</td><td>$stddev</td><td><a href=\"$self->{'system'}->{'scriptname'}?page=seqbin&amp;db=$self->{'instance'}&amp;isolate_id=$_\" class=\"extract_tooltip\" target=\"_blank\">Display &rarr;</a></td></tr>\n";
		print $fh "$_\t$isolate\t$contigs\t$sum\t$min\t$max\t$mean\t$stddev\n";
		push @{$data->{'contigs'}},$contigs;
		push @{$data->{'sum'}},$sum;
		push @{$data->{'mean'}},$mean;
		$td = $td == 1 ? 2 : 1;
		
	}
	print "</tbody></table>\n";
	close $fh;
	print "<p><a href=\"/tmp/$temp.txt\">Download in tab-delimited text format</a></p>\n";
	my %title = (
		'contigs' => 'Number of contigs',
		'sum' => 'Total length',
		'mean' => 'Mean contig length'
	);
	if ($self->{'config'}->{'chartdirector'}){
		print "<div><p>Click on the following charts to enlarge</p>\n";
		foreach (qw (contigs sum mean)){
			my $stats = BIGSdb::Utils::stats($data->{$_});

			my $bins =
			  ceil( ( 3.5 * $stats->{'std'} ) / $stats->{'count'} ** 0.33 )
			  ;    #Scott's choice [Scott DW (1979). On optimal and data-based histograms. Biometrika 66(3):605–610]
			$bins = 100 if $bins> 100;
			$bins = 1 if !$bins;
			my $width = ( $stats->{'max'} - $stats->{'min'} ) / $bins;
			
			my $round_to_nearest;
			if ($width < 50){
				$round_to_nearest = 5;
			} elsif ($width < 100){
				$round_to_nearest = 10;
			} elsif ($width < 500){
				$round_to_nearest = 50;
			} elsif ($width < 1000){
				$round_to_nearest = 100;
			} elsif ($width < 5000) {
				$round_to_nearest = 500;
			} else {
				$round_to_nearest = 1000;
			}	
			$width = int( $width - ( $width % $round_to_nearest ) ) || $round_to_nearest;
			
			
			my ( $histogram, $min, $max ) = BIGSdb::Utils::histogram( $width, $data->{$_} );
			my ( @labels, @values );
			for ( my $i = $min ; $i <= $max ; $i++ ) {
				push @labels, $i * $width;
				push @values, $histogram->{$i};
			}
			my %prefs = ( 'offset_label' => 1, 'x-title' => $title{$_}, 'y-title' => 'Frequency' );
			
			BIGSdb::Charts::barchart( \@labels, \@values, "$self->{'config'}->{'tmp_dir'}/$temp\_histogram_$_.png", 'large', \%prefs );
			print "<h2>$title{$_}</h2>\n";
			
			print "Overall mean: ". BIGSdb::Utils::decimal_place($stats->{'mean'},1) ."; &sigma;: ". BIGSdb::Utils::decimal_place($stats->{'std'},1)."<br />";	
			
			print "<a href=\"/tmp/$temp\_histogram_$_.png\" target=\"_blank\"><img src=\"/tmp/$temp\_histogram_$_.png\" alt=\"$_ histogram\" style=\"width:300px; border:0\" /></a>\n";
			
		}
		print "</div>\n";
	}
	print "</div>\n";
}


1;
