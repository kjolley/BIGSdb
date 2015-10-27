#Written by Keith Jolley
#Copyright (c) 2010-2015, University of Oxford
#E-mail: keith.jolley@zoo.ox.ac.uk
#
#This file is part of Bacterial Isolate Genome Sequence Database (BIGSdb).
#This module depends on Chartdirector being installed.
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
package BIGSdb::Charts;
use strict;
use warnings;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Charts');

sub piechart {

	#size = 'small' or 'large'
	my ( $labels, $data, $filename, $num_labels, $size, $prefs, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	$prefs->{'style'} = 'pie' if !$prefs->{'style'} || $prefs->{'style'} ne 'doughnut';

	#if there are more than $num_labels headings, display the top ones and group the rest
	my ( @grouped_labels, @grouped_data );
	my $explode;
	if ( $num_labels != 0 ) {
		if ( @$labels > $num_labels ) {
			my $i;
			for ( $i = 0 ; $i < $num_labels ; $i++ ) {
				push @grouped_labels, $$labels[$i];
				push @grouped_data,   $$data[$i];
			}
			my $allothers = 0;
			while ( $i < @$labels ) {
				$allothers += $$data[$i];
				$i++;
			}
			my $num_others = @$labels - $num_labels;
			push @grouped_labels, "all others ($num_others values)";
			$explode = @grouped_labels - 1;
			push @grouped_data, $allothers;
		} else {
			@grouped_labels = @$labels;
			@grouped_data   = @$data;
		}
	} else {
		@grouped_labels = @$labels;
		@grouped_data   = @$data;
	}
	my $chart;
	if ( $size eq 'small' ) {
		$chart = PieChart->new( 780, 350 );
		if ( $prefs->{'style'} eq 'doughnut' ) {
			$chart->setDonutSize( 390, 120, 100, 20 );
		} else {
			$chart->setPieSize( 390, 120, 100 );
		}
	} else {
		$chart = PieChart->new( 920, 500 );
		if ( $prefs->{'style'} eq 'doughnut' ) {
			$chart->setDonutSize( 450, 200, 170, 50 );
		} else {
			$chart->setPieSize( 450, 200, 170 );
		}
	}
	$chart->setLabelFormat('{label} ({value} - {percent}%)');
	{
		no warnings 'once';
		$chart->setColors($perlchartdir::transparentPalette) if $prefs->{'transparent'};
	}
	$chart->setStartAngle( 45, 0 );
	$chart->set3D() if $prefs->{'threeD'};
	$chart->setBackground(0x00FFFFFF);
	$chart->setTransparentColor(0x00FFFFFF) if !$options->{'no_transparent'};
	{
		no warnings 'once';
		$chart->setLabelLayout($perlchartdir::SideLayout);
	}
	$chart->setLineColor(0xD0000000);
	$chart->setExplode($explode) if $explode;
	$chart->setData( \@grouped_data, \@grouped_labels );
	$chart->makeChart($filename);
	return;
}

sub barchart {
	my ( $labels, $data, $filename, $size, $prefs, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $max_label_length = _find_length_of_largest_label($labels);
	my $preferred        = 10;
	my $values           = scalar @$labels;
	my $display_labels;
	if ( $values > 50 ) {
		my $pruning_factor = int( $values / 50 );

		#prune labels
		my $i = 0;
		foreach (@$labels) {
			if ( $i < $pruning_factor ) {
				push @$display_labels, '';
			} else {
				push @$display_labels, $_;
			}
			$i++;
			$i = 0 if $i > $pruning_factor;
		}
	} else {
		$display_labels = $labels;
	}
	my $y_offset = $max_label_length * 5;
	$y_offset += 10 if $prefs->{'x-title'};
	my $x_offset = $prefs->{'y-title'} ? 20 : 0;
	my ( $chart, $layer );
	if ( $size eq 'small' ) {
		$chart = XYChart->new( 780, 350 );
		$chart->setPlotArea( 30 + $x_offset, 20, 710, 300 - $y_offset );
		$layer = $chart->addBarLayer( $data, $chart->gradientColor( 0, 0, 0, 350, 0xf0f0f0, 0x404080 ) );
	} else {
		$chart = XYChart->new( 920, 500 );
		$chart->setPlotArea( 30 + $x_offset, 20, 800, 450 - $y_offset );
		$layer = $chart->addBarLayer( $data, $chart->gradientColor( 0, 0, 0, 500, 0xf0f0f0, 0x404080 ) );
	}
	$chart->setBackground(0x00FFFFFF);
	$chart->setTransparentColor(0x00FFFFFF) if !$options->{'no_transparent'};
	$layer->set3D if $prefs->{'threeD'};
	{
		no warnings 'once';
		$layer->setBarGap($perlchartdir::TouchBar);
	}
	$layer->setBorderColor( -1, 1 );
	my $angle = $max_label_length > 12 ? 90 : 45;
	$chart->xAxis()->setLabels($display_labels)->setFontAngle($angle);
	if ( $prefs->{'offset_label'} ) {
		$chart->xAxis->setTickOffset(-0.5);
		$chart->xAxis->setLabelOffset(-0.5);
	}
	$chart->yAxis()->setAutoScale( 0.1, 0.1, 1 );
	$chart->yAxis()->setMinTickInc(1);    # if ($config{'mintick'});
	if ( $prefs->{'x-title'} ) {
		$chart->xAxis->setTitle( $prefs->{'x-title'} );
	}
	if ( $prefs->{'y-title'} ) {
		$chart->yAxis->setTitle( $prefs->{'y-title'} );
	}
	$chart->makeChart($filename);
	return;
}

sub linechart {
	my ( $labels, $data, $filename, $size, $prefs, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $max_label_length = _find_length_of_largest_label($labels);
	my $preferred        = 10;
	my $values           = scalar @$labels;
	my $display_labels;
	if ( $values > 50 ) {
		my $pruning_factor = int( $values / 50 );

		#prune labels
		my $i = 0;
		foreach (@$labels) {
			if ( $i < $pruning_factor ) {
				push @$display_labels, '';
			} else {
				push @$display_labels, $_;
			}
			$i++;
			$i = 0 if $i > $pruning_factor;
		}
	} else {
		$display_labels = $labels;
	}
	my $y_offset = $max_label_length * 5;
	$y_offset += 10 if $prefs->{'x-title'};
	my $x_offset = $prefs->{'y-title'} ? 20 : 0;
	my ( $chart, $layer );
	if ( $size eq 'small' ) {
		$chart = XYChart->new( 780, 350 );
		$chart->setPlotArea( 50 + $x_offset, 20, 710, 300 - $y_offset );
	} else {
		$chart = XYChart->new( 920, 500 );
		$chart->setPlotArea( 50 + $x_offset, 20, 800, 450 - $y_offset );
	}
	$layer = $chart->addLineLayer2();
	{
		no warnings 'once';
		$layer->addDataSet( $data, 0x00000080 )->setDataSymbol( $perlchartdir::CircleSymbol, 5 );
	}
	$chart->setBackground(0x00FFFFFF);
	$chart->setTransparentColor(0x00FFFFFF) if !$options->{'no_transparent'};
	$layer->setBorderColor( -1, 1 );
	my $angle = $max_label_length > 12 ? 90 : 45;
	$chart->xAxis()->setLabels($display_labels)->setFontAngle($angle);
	$chart->xAxis->setTitle( $prefs->{'x-title'} ) if $prefs->{'x-title'};
	$chart->yAxis->setTitle( $prefs->{'y-title'} ) if $prefs->{'y-title'};
	$chart->makeChart($filename);
	return;
}

sub _find_length_of_largest_label {
	my ($label_ref) = @_;
	my $max = 0;
	foreach (@$label_ref) {
		if ( length $_ > $max ) {
			$max = length $_;
		}
	}
	return $max;
}
1;
