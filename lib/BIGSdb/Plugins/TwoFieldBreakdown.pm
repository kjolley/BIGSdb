#FieldBreakdown.pm - TwoFieldBreakdown plugin for BIGSdb
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
package BIGSdb::Plugins::TwoFieldBreakdown;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use List::MoreUtils qw(uniq any);

sub get_attributes {
	my %att = (
		name        => 'Two Field Breakdown',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Two field breakdown',
		category    => 'Breakdown',
		buttontext  => 'Two Field',
		menutext    => 'Two field',
		module      => 'TwoFieldBreakdown',
		version     => '1.2.0',
		dbtype      => 'isolates',
		section     => 'breakdown,postquery',
		url         => 'http://pubmlst.org/software/database/bigsdb/userguide/isolates/two_field_breakdown.shtml',
		input       => 'query',
		requires    => 'chartdirector',
		order       => 12
	);
	return \%att;
}

sub get_option_list {
	my @list = (
		{ name => 'threeD',      description => 'Enable 3D effect',           default => 0 },
		{ name => 'transparent', description => 'Enable transparent palette', default => 0 },
	);
	return \@list;
}

sub get_hidden_attributes {
	my @list = qw(field1 field2 display calcpc function);
	return \@list;
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say "<h1>Two field breakdown of dataset</h1>";
	my $format = $q->param('format');
	$self->{'extended'} = $self->get_extended_attributes;
	if ( !$q->param('function') ) {
		$self->_print_interface;
		return;
	}
	my %prefs;
	my $query_file = $q->param('query_file');
	my $id_list = $self->get_id_list( 'id', $query_file );
	if ( !@$id_list ) {
		$id_list = $self->{'datastore'}->run_list_query("SELECT id FROM $self->{'system'}->{'view'}");
	}
	$self->_breakdown($id_list) if $q->param('function') eq 'breakdown';
	return;
}

sub _print_interface {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say "<div class=\"box\" id=\"queryform\">";
	say "<div class=\"scrollable\">";
	say "<p>Here you can create a table breaking down one field by another, e.g. breakdown of serogroup by year.</p>";
	say $q->startform;
	$q->param( 'function', 'breakdown' );
	say $q->hidden($_) foreach qw (db page name function query_file);
	my $set_id = $self->get_set_id;
	my ( $headings, $labels ) = $self->get_field_selection_list(
		{
			isolate_fields      => 1,
			extended_attributes => 1,
			loci                => 1,
			query_pref          => 0,
			analysis_pref       => 1,
			scheme_fields       => 1,
			set_id              => $set_id
		}
	);
	say "<fieldset style=\"float:left\"><legend>Select fields</legend><ul><li>";
	say "<label for=\"field1\">Field 1:</label>";
	say $q->popup_menu( -name => 'field1', -id => 'field1', -values => $headings, -labels => $labels );
	say "</li><li>";
	say "<label for=\"field2\">Field 2:</label>";
	say $q->popup_menu( -name => 'field2', -id => 'field2', -values => $headings, -labels => $labels );
	say "</li></ul></fieldset>";
	say "<fieldset style=\"float:left\"><legend>Display</legend>";
	say $q->radio_group(
		-name      => 'display',
		-values    => [ 'values only', 'values and percentages', 'percentages only' ],
		-default   => 'values only',
		-linebreak => 'true'
	);
	say "</fieldset>";
	say "<fieldset style=\"float:left\"><legend>Calculate percentages by</legend>";
	say $q->radio_group( -name => 'calcpc', -values => [ 'dataset', 'row', 'column' ], -default => 'dataset', -linebreak => 'true' );
	say "</fieldset>";
	$self->print_action_fieldset( { name => 'TwoFieldBreakdown' } );
	say $q->endform;
	say "</div>\n</div>";
	return;
}

sub _reverse {
	my ( $self, $field1, $field2 ) = @_;
	my $q = $self->{'cgi'};
	$field1 = $q->param('field2');
	$field2 = $q->param('field1');
	$q->param( 'field1', $field1 );
	$q->param( 'field2', $field2 );
	return ( $field1, $field2 );
}

sub _print_controls {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say $q->startform;
	say qq(<fieldset style="float:left"><legend>Axes</legend>);
	say $q->hidden($_) foreach qw (db page name function query_file field1 field2 display calcpc);
	say $q->submit( -name => 'reverse', -value => 'Reverse', -class => 'submitbutton ui-button ui-widget ui-state-default ui-corner-all');
	say "</fieldset>";
	say $q->endform;
	say $q->startform;
	say qq(<fieldset style="float:left"><legend>Show</legend>);
	say $q->hidden($_) foreach qw (db page name function query_file field1 field2 display calcpc);
	my %display_toggle =
	  ( 'values only' => 'Values and percentages', 'values and percentages' => 'Percentages only', 'percentages only' => 'Values only' );
	say $q->submit( -name => 'toggledisplay', -label => $display_toggle{ $q->param('display') } , -class => 'submitbutton ui-button ui-widget ui-state-default ui-corner-all' );
	say "</fieldset>";
	say $q->endform;

	if ( $q->param('display') ne 'values only' ) {
		say $q->startform;
		say qq(<fieldset style="float:left"><legend>Calculate percentages</legend>);
		say $q->hidden($_) foreach qw (db page name function query_file field1 field2 display calcpc);
		my %pc_toggle = ( dataset => 'row', row => 'column', column => 'dataset' );
		say qq(<span style="text-align:center; display:block">);
		say $q->submit(
			-name  => 'togglepc',
			-label => ( 'By ' . $pc_toggle{ $q->param('calcpc') } ),
			-class => 'submitbutton ui-button ui-widget ui-state-default ui-corner-all',
		);
		say "</span></fieldset>";
		say $q->endform;
	}
	return;
}

sub _breakdown {
	my ( $self, $id_list ) = @_;
	my $q      = $self->{'cgi'};
	my $field1 = $q->param('field1');
	my $field2 = $q->param('field2');
	if ( $q->param('reverse') ) {
		( $field1, $field2 ) = $self->_reverse( $field1, $field2 );
	}
	my ( $attribute1, $attribute2 );
	if ( $field1 =~ /^e_(.*)\|\|(.*)$/ ) {
		$field1     = $1;
		$attribute1 = $2;
	}
	if ( $field2 =~ /^e_(.*)\|\|(.*)$/ ) {
		$field2     = $1;
		$attribute2 = $2;
	}
	if ( $field1 eq $field2 ) {
		say "<div class=\"box\" id=\"statusbad\"><p>You must select two <em>different</em> fields.</p></div>";
		return;
	}
	my ( $display, $calcpc );
	my ( $grandtotal, $datahash_ref, $field1total_ref, $field2total_ref, $clean_field1, $clean_field2, $print_field1, $print_field2 );
	try {
		( $grandtotal, $datahash_ref, $field1total_ref, $field2total_ref, $clean_field1, $clean_field2, $print_field1, $print_field2 ) =
		  $self->_get_value_frequency_hashes( $field1, $field2, $id_list );
	}
	catch BIGSdb::DatabaseConnectionException with {
		say "<div class=\"box\" id=\"statusbad\"><p>The database for the scheme of one of your selected fields is inaccessible.  "
		  . "This may be a configuration problem.</p></div>";
		return;
	};
	if ( $attribute1 || $attribute2 ) {
		$datahash_ref = $self->_recalculate_for_attributes( $field1, $attribute1, $field2, $attribute2, $datahash_ref );

		#Recalculate fieldtotals
		undef $field1total_ref;
		undef $field2total_ref;
		foreach my $value1 ( keys %$datahash_ref ) {
			foreach my $value2 ( keys %{ $datahash_ref->{$value1} } ) {
				$field1total_ref->{$value1} += $datahash_ref->{$value1}->{$value2};
				$field2total_ref->{$value2} += $datahash_ref->{$value1}->{$value2};
			}
		}
	}
	if ($attribute1) {
		$print_field1 = $attribute1;
	}
	if ($attribute2) {
		$print_field2 = $attribute2;
	}
	my ( %datahash, %field1total, %field2total );
	eval {
		%datahash    = %$datahash_ref;
		%field1total = %$field1total_ref;
		%field2total = %$field2total_ref;
	};
	if ( $@ =~ /HASH reference/ ) {
		$logger->debug($@);
		say "<div class=\"box\" id=\"statusbad\"><p>No data retrieved.</p></div>";
		return;
	}

	#get list of field2 values
	my @field2values;
	for my $field1value ( sort keys %datahash ) {
		for my $field2value ( sort keys %{ $datahash{$field1value} } ) {
			push @field2values, $field2value;
		}
	}
	@field2values = uniq @field2values;
	{
		no warnings;
		@field2values = sort { $a <=> $b || $a cmp $b } @field2values;
	}
	my $numfield2 = scalar @field2values + 1;
	if ( scalar keys %datahash > 2000 || $numfield2 > 2000 ) {
		say "<div class=\"box\" id=\"statusbad\"><p>One of your selected fields has more than 2000 values - calculation "
		  . "has been disabled to prevent your browser locking up.</p>";
		say "<p>$print_field1: " . ( scalar keys %datahash ) . "<br />";
		say "$print_field2: $numfield2</p>";
		say "</div>";
		return;
	}
	if ( $q->param('toggledisplay') ) {
		if ( $q->param('toggledisplay') eq 'Values only' ) {
			$q->param( display => 'values only' );
		} elsif ( $q->param('toggledisplay') eq 'Values and percentages' ) {
			$q->param( display => 'values and percentages' );
		} elsif ( $q->param('toggledisplay') eq 'Percentages only' ) {
			$q->param( display => 'percentages only' );
		}
	}
	if ( $q->param('display') ) {
		$display = $q->param('display');
	} else {
		$display = 'values only';
	}
	if ( $q->param('togglepc') ) {
		if ( $q->param('togglepc') eq 'By row' ) {
			$q->param( 'calcpc', 'row' );
		} elsif ( $q->param('togglepc') eq 'By column' ) {
			$q->param( 'calcpc', 'column' );
		} elsif ( $q->param('togglepc') eq 'By dataset' ) {
			$q->param( 'calcpc', 'dataset' );
		}
	}
	if ( $q->param('calcpc') ) {
		$calcpc = $q->param('calcpc');
	} else {
		$calcpc = 'dataset';
	}
	my $temp1    = BIGSdb::Utils::get_random();
	my $out_file = "$self->{'config'}->{'tmp_dir'}/$temp1.txt";
	open( my $fh, '>', $out_file )
	  or $logger->error("Can't open temp file $out_file for writing");
	say "<div class=\"box\" id=\"resultstable\">\n";
	my $html_field1 = $self->{'datastore'}->is_locus($print_field1) ? $self->clean_locus($print_field1) : $print_field1;
	my $html_field2 = $self->{'datastore'}->is_locus($print_field2) ? $self->clean_locus($print_field2) : $print_field2;
	my $text_field1 =
	  $self->{'datastore'}->is_locus($print_field1) ? $self->clean_locus( $print_field1, { text_output => 1 } ) : $print_field1;
	my $text_field2 =
	  $self->{'datastore'}->is_locus($print_field2) ? $self->clean_locus( $print_field2, { text_output => 1 } ) : $print_field2;
	say "<h2>Breakdown of $html_field1 by $html_field2:</h2>";
	say $fh "Breakdown of $text_field1 by $text_field2:";
	say "<p>Selected options: Display $display. ";
	print $fh "Selected options: Display $display. ";

	if ( $display ne 'values only' ) {
		say "Calculate percentages by $calcpc.";
		print $fh "Calculate percentages by $calcpc.";
	}
	say "</p>";
	say $fh "\n";
	$self->_print_controls;
	say "<div class=\"scrollable\" style=\"clear:both\">";
	say "<table class=\"tablesorter\" id=\"sortTable\">\n<thead>";
	say "<tr><td></td><td colspan=\"$numfield2\" class=\"header\">$html_field2</td></tr>";
	say $fh "$text_field1\t$text_field2";
	local $" = "</th><th class=\"{sorter: 'digit'}\">";
	say "<tr><th>$html_field1</th><th class=\"{sorter: 'digit'}\">@field2values</th><th class=\"{sorter: 'digit'}\">"
	  . "Total</th></tr></thead><tbody>";
	local $" = "\t";
	say $fh "\t@field2values\tTotal";
	my $td = 1;
	{
		no warnings 'numeric';    #might complain about numeric comparison with non-numeric data
		for my $field1value ( sort { $a <=> $b || $a cmp $b } keys %datahash ) {
			my $total = 0;
			say "<tr class=\"td$td\"><td>$field1value</td>";
			print $fh "$field1value";
			foreach my $field2value (@field2values) {
				my $value = $datahash{$field1value}{$field2value} || 0;
				my $percentage;
				if ( $q->param('calcpc') eq 'row' ) {
					$percentage = BIGSdb::Utils::decimal_place( ( $value / $field1total{$field1value} ) * 100, 1 );
				} elsif ( $q->param('calcpc') eq 'column' ) {
					$percentage = BIGSdb::Utils::decimal_place( ( $value / $field2total{$field2value} ) * 100, 1 );
				} else {
					$percentage = BIGSdb::Utils::decimal_place( ( $value / $grandtotal ) * 100, 1 );
				}
				$total += $value;
				if ( !$value ) {
					say "<td></td>";
					print $fh "\t";
				} else {
					if ( $q->param('display') eq 'values and percentages' ) {
						say "<td>$value ($percentage%)</td>";
						print $fh "\t$value ($percentage%)";
					} elsif ( $q->param('display') eq 'percentages only' ) {
						say "<td>$percentage</td>";
						print $fh "\t$percentage";
					} else {
						say "<td>$value</td>";
						print $fh "\t$value";
					}
				}
			}
			my $percentage;
			if ( $q->param('calcpc') eq 'row' ) {
				$percentage = 100;
			} else {
				$percentage = BIGSdb::Utils::decimal_place( ( $field1total{$field1value} / $grandtotal ) * 100, 1 );
			}
			if ( $q->param('display') eq 'values and percentages' ) {
				say "<td>$total ($percentage%)</td></tr>";
				say $fh "\t$total ($percentage%)";
			} elsif ( $q->param('display') eq 'percentages only' ) {
				say "<td>$percentage</td></tr>";
				say $fh "\t$percentage";
			} else {
				say "<td>$total</td></tr>";
				say $fh "\t$total";
			}
			$td = $td == 1 ? 2 : 1;    #row stripes
		}
	};
	say "</tbody><tbody><tr class=\"total\"><td>Total</td>";
	print $fh "Total";
	foreach my $field2value (@field2values) {
		my $percentage;
		if ( $q->param('calcpc') eq 'column' ) {
			$percentage = 100;
		} else {
			$percentage = BIGSdb::Utils::decimal_place( ( $field2total{$field2value} / $grandtotal ) * 100, 1 );
		}
		if ( $q->param('display') eq 'values and percentages' ) {
			say "<td>$field2total{$field2value} ($percentage%)</td>";
			print $fh "\t$field2total{$field2value} ($percentage%)";
		} elsif ( $q->param('display') eq 'percentages only' ) {
			say "<td>$percentage</td>";
			print $fh "\t$percentage";
		} else {
			say "<td>$field2total{$field2value}</td>";
			print $fh "\t$field2total{$field2value}";
		}
	}
	if ( $q->param('display') eq 'values and percentages' ) {
		say "<td>$grandtotal (100%)</td></tr>";
		say $fh "\t$grandtotal (100%)";
	} elsif ( $q->param('display') eq 'percentages only' ) {
		say "<td>100</td></tr>";
		say $fh "\t100";
	} else {
		say "<td>$grandtotal</td></tr>";
		say $fh "\t$grandtotal";
	}
	say "</tbody></table></div>";
	close $fh;
	say "<p><a href='/tmp/$temp1.txt'>Download as tab-delimited text.</a></p></div>";

	#Chartdirector
	$self->_print_charts(
		{
			prefix        => $temp1,
			field1        => $field1,
			field2        => $field2,
			html_field1   => $html_field1,
			html_field2   => $html_field2,
			text_field1   => $text_field1,
			text_field2   => $text_field2,
			data          => \%datahash,
			field1_total  => \%field1total,
			field2_values => \@field2values
		}
	);
	return;
}

sub _print_charts {
	my ( $self, $args ) = @_;
	my $prefix        = $args->{'prefix'};
	my $data          = $args->{'data'};
	my $field1_total  = $args->{'field1_total'};
	my $field2_values = $args->{'field2_values'};
	my $field1        = $args->{'field1'};
	my $field2        = $args->{'field2'};
	my $text_field1   = $args->{'text_field1'};
	my $text_field2   = $args->{'text_field2'};
	if ( $self->{'config'}->{'chartdirector'} && keys %$data < 31 && @$field2_values < 31 ) {
		print "<div class=\"box\" id=\"chart\"><h2>Charts</h2>";
		print "<p>Click to enlarge.</p>";
		my $guid = $self->get_guid;
		my %prefs;
		foreach (qw (threeD transparent)) {
			try {
				$prefs{$_} = $self->{'prefstore'}->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'TwoFieldBreakdown', $_ );
				$prefs{$_} = $prefs{$_} eq 'true' ? 1 : 0;
			}
			catch BIGSdb::DatabaseNoRecordException with {
				$prefs{$_} = 0;
			};
		}
		for ( my $i = 0 ; $i < 2 ; $i++ ) {
			my $chart = XYChart->new( 1000, 500 );
			$chart->setPlotArea( 100, 40, 580, 300 );
			$chart->setBackground(0x00FFFFFF);
			$chart->addLegend( 700, 10 );
			$chart->xAxis()->setLabels($field2_values)->setFontAngle(60);
			my $layer;
			if ( !$i ) {
				no warnings 'once';
				$layer = $chart->addBarLayer2( $perlchartdir::Stack, 0 );
			} else {
				no warnings 'once';
				$layer = $chart->addBarLayer2( $perlchartdir::Percentage, 0 );
			}
			$layer->set3D if $prefs{'threeD'};
			{
				no warnings 'once';
				$chart->setColors($perlchartdir::transparentPalette) if $prefs{'transparent'};
			}
			for my $field1value ( sort { $field1_total->{$b} <=> $field1_total->{$a} || $a cmp $b } keys %$data ) {
				if ( $field1value ne 'No value' ) {
					my @dataset;
					foreach my $field2value (@$field2_values) {
						if ( !$data->{$field1value}->{$field2value} ) {
							push @dataset, 0;
						} else {
							push @dataset, $data->{$field1value}->{$field2value};
						}
					}
					$layer->addDataSet( \@dataset, -1, $field1value );
				}
			}

			#Put unassigned or no value at end
			my @specials = ( 'Unassigned', 'No value', 'unspecified' );
			foreach my $specialvalue (@specials) {
				if ( $data->{$specialvalue} ) {
					my @dataset;
					foreach my $field2value (@$field2_values) {
						if ( !$data->{$specialvalue}->{$field2value} ) {
							push @dataset, 0;
						} else {
							push @dataset, $data->{$specialvalue}->{$field2value};
						}
					}
					$layer->addDataSet( \@dataset, -1, $specialvalue );
				}
			}
			if ( !$i ) {
				$chart->addTitle( "Values", "arial.ttf", 14 );
				my $filename = "$prefix\_$field1\_$field2.png";
				if ( $filename =~ /(BIGSdb.*\.png)/ ) {
					$filename = $1;    #untaint
				}
				$chart->makeChart("$self->{'config'}->{'tmp_dir'}\/$filename");
				say "<fieldset><legend>Values</legend>";
				say "<a href=\"/tmp/$filename\" data-rel=\"lightbox-1\" class=\"lightbox\" title=\"$text_field1 vs $text_field2\">"
				  . "<img src=\"/tmp/$filename\" alt=\"$text_field1 vs $text_field2\" style=\"width:200px; border: 1px dashed black\" /></a>";
				say "</fieldset>";
			} else {
				$chart->addTitle( "Percentages", "arial.ttf", 14 );
				my $filename = "$prefix\_$field1\_$field2\_pc.png";
				if ( $filename =~ /(BIGSdb.*\.png)/ ) {
					$filename = $1;    #untaint
				}
				$chart->makeChart("$self->{'config'}->{'tmp_dir'}\/$filename");
				say "<fieldset><legend>Percentages</legend>";
				say "<a href=\"/tmp/$filename\" data-rel=\"lightbox-1\" class=\"lightbox\"  title=\"$text_field1 vs $text_field2 "
				  . "percentage chart\"><img src=\"/tmp/$filename\" alt=\"$text_field1 vs $text_field2 percentage chart\"  "
				  . "style=\"width:200px;border:1px dashed black\" /></a></fieldset>";
			}
		}
		say "</div>";
	}
	return;
}

sub _get_value_frequency_hashes {
	my ( $self, $field1, $field2, $id_list ) = @_;
	my $total_isolates = $self->{'datastore'}->run_simple_query("SELECT COUNT(id) FROM $self->{'system'}->{'view'}")->[0];
	my $datahash;
	my $grandtotal = 0;

	#We need to calculate field1 and field2 totals so that we can
	#calculate percentages based on these.
	my $field1total;
	my $field2total;
	my %field_type;
	my %clean;
	my %print;
	( $clean{$field1} = $field1 ) =~ s/^[f|l]_//;
	( $clean{$field2} = $field2 ) =~ s/^[f|l]_//;
	foreach ( $field1, $field2 ) {

		if ( $_ =~ /^la_(.+)\|\|/ || $_ =~ /^cn_(.+)/ ) {
			$clean{$_} = $1;
		}
	}
	my %scheme_id;
	foreach ( $field1, $field2 ) {
		if ( $self->{'xmlHandler'}->is_field( $clean{$_} ) ) {
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($_);
			$field_type{$_} = defined $metaset ? 'metafield' : 'field';
			$metafield =~ tr/_/ / if defined $metafield;
			$print{$_} = $metafield // $clean{$_};
		} elsif ( $self->{'datastore'}->is_locus( $clean{$_} ) ) {
			$field_type{$_} = 'locus';
			$print{$_}      = $clean{$_};
		} else {
			if ( $_ =~ /^s_(\d+)_(.*)/ ) {
				my $scheme_id = $1;
				my $field     = $2;
				if ( $self->{'datastore'}->is_scheme_field( $scheme_id, $field ) ) {
					$clean{$_}      = $field;
					$print{$_}      = $clean{$_};
					$field_type{$_} = 'scheme_field';
					$scheme_id{$_}  = $scheme_id;
					my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
					$print{$_} .= " ($scheme_info->{'description'})";
				}
			}
		}
	}
	foreach my $id (uniq @$id_list) {
		my @values = $self->_get_values(
			{
				isolate_id   => $id,
				fields       => [ $field1, $field2 ],
				clean_fields => \%clean,
				field_type   => \%field_type,
				scheme_id    => \%scheme_id,
				options      => { fetchall => ( @$id_list / $total_isolates >= 0.5 ? 1 : 0 ) }
			}
		);
		foreach (qw (0 1)) {
			$values[$_] = ['No value'] if !@{ $values[$_] } || ( $values[$_]->[0] // '' ) eq '';
		}
		foreach my $field1_value ( @{ $values[0] } ) {
			next if !defined $field1_value;
			foreach my $field2_value ( @{ $values[1] } ) {
				next if !defined $field2_value;
				$datahash->{$field1_value}->{$field2_value}++;
				$grandtotal++;
				$field1total->{$field1_value}++;
				$field2total->{$field2_value}++;
			}
		}
	}
	return ( $grandtotal, $datahash, $field1total, $field2total, $clean{$field1}, $clean{$field2}, $print{$field1}, $print{$field2} );
}

sub _get_values {

	#If number of records is >=50% of total records, query database and fetch all rows, otherwise call for each record in turn.
	#Values are arrayref in an array representing field1 and field2.
	my ( $self, $args ) = @_;
	my ( $isolate_id, $fields, $clean_fields, $field_type, $scheme_id, $options ) =
	  @{$args}{qw(isolate_id fields clean_fields field_type scheme_id options)};
	$options = {} if ref $options ne 'HASH';
	my @values;
	foreach my $field (@$fields) {
		my $values;
		my $sub_args =
		  { isolate_id => $isolate_id, field => $field, clean_fields => $clean_fields, scheme_id => $scheme_id, options => $options };
		if    ( $field_type->{$field} eq 'field' ) { $values = [ $self->_get_field_value($sub_args) ] }
		elsif ( $field_type->{$field} eq 'locus' ) { $values = $self->_get_locus_values($sub_args) }
		elsif ( $field_type->{$field} eq 'scheme_field' ) {
			$values = $self->get_scheme_field_values(
				{ isolate_id => $isolate_id, scheme_id => $scheme_id->{$field}, field => $clean_fields->{$field} } );
		} elsif ( $field_type->{$field} eq 'metafield' ) {
			$values = [ $self->_get_metafield_value($sub_args) ];
		}
		push @values, $values;
	}
	return @values;
}

sub _get_field_value {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $field, $clean_fields, $options ) = @{$args}{qw(isolate_id field clean_fields options)};
	my $value;
	if ( $options->{'fetchall'} ) {
		if ( !$self->{'cache'}->{$field} ) {
			my $sql = $self->{'db'}->prepare("SELECT id, $clean_fields->{$field} FROM $self->{'system'}->{'view'}");
			eval { $sql->execute };
			$logger->error($@) if $@;
			$self->{'cache'}->{$field} = $sql->fetchall_hashref('id');
		}
		$value = $self->{'cache'}->{$field}->{$isolate_id}->{ $clean_fields->{$field} };
	} else {
		if ( !$self->{'sql'}->{'field_value'}->{$field} ) {
			$self->{'sql'}->{'field_value'}->{$field} =
			  $self->{'db'}->prepare("SELECT $clean_fields->{$field} FROM $self->{'system'}->{'view'} WHERE id=?");
		}
		eval { $self->{'sql'}->{'field_value'}->{$field}->execute($isolate_id) };
		$logger->error($@) if $@;
		($value) = $self->{'sql'}->{'field_value'}->{$field}->fetchrow_array;
	}
	return $value;
}

sub _get_locus_values {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $field, $clean_fields, $options ) = @{$args}{qw(isolate_id field clean_fields options)};
	my $values = [];
	if ( $options->{'fetchall'} ) {
		if ( !$self->{'cache'}->{$field} ) {
			my $sql = $self->{'db'}->prepare("SELECT isolate_id, allele_id FROM allele_designations WHERE locus=?");
			eval { $sql->execute( $clean_fields->{$field} ) };
			$logger->error($@) if $@;
			while ( my $data = $sql->fetchrow_arrayref ) {
				push @{ $self->{'cache'}->{$field}->{ $data->[0] } }, $data->[1];
			}
		}
		$values = $self->{'cache'}->{$field}->{$isolate_id} // [];
	} else {
		$values = $self->{'datastore'}->get_allele_ids( $isolate_id, $clean_fields->{$field} );
	}
	return $values;
}

sub _get_metafield_value {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $field, $clean_fields, $options ) = @{$args}{qw(isolate_id field clean_fields options)};
	my $value;
	my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname( $clean_fields->{$field} );
	if ( $options->{'fetchall'} ) {
		if ( !$self->{'cache'}->{$field} ) {
			my $sql =
			  $self->{'db'}->prepare(
				"SELECT isolate_id, $metafield FROM meta_$metaset WHERE isolate_id IN (SELECT id FROM $self->{'system'}->{'view'})");
			eval { $sql->execute };
			$logger->error($@) if $@;
			$self->{'cache'}->{$field} = $sql->fetchall_hashref('isolate_id');
		}
		$value = $self->{'cache'}->{$field}->{$isolate_id}->{$metafield};
	} else {
		if ( !$self->{'sql'}->{'field_value'}->{$field} ) {
			$self->{'sql'}->{'field_value'}->{$field} = $self->{'db'}->prepare("SELECT $metafield FROM meta_$metaset WHERE isolate_id=?");
		}
		eval { $self->{'sql'}->{'field_value'}->{$field}->execute($isolate_id) };
		$logger->error($@) if $@;
		($value) = $self->{'sql'}->{'field_value'}->{$field}->fetchrow_array;
	}
	return $value;
}

sub _recalculate_for_attributes {
	my ( $self, $field1, $attribute1, $field2, $attribute2, $datahash_ref ) = @_;
	my @field     = ( $field1,     $field2 );
	my @attribute = ( $attribute1, $attribute2 );
	my $new_hash;
	if ( $attribute[0] || $attribute[1] ) {
		my $lookup;
		foreach ( 0 .. 1 ) {
			my $sql =
			  $self->{'db'}
			  ->prepare("SELECT field_value,value FROM isolate_value_extended_attributes WHERE isolate_field=? AND attribute=?");
			eval { $sql->execute( $field[$_], $attribute[$_] ) };
			$logger->error($@) if $@;
			while ( my ( $field_value, $attribute_value ) = $sql->fetchrow_array ) {
				$lookup->[$_]->{$field_value} = $attribute_value;
			}
		}
		foreach my $value1 ( keys %$datahash_ref ) {
			foreach my $value2 ( keys %{ $datahash_ref->{$value1} } ) {
				$lookup->[0]->{$value1} = 'No value' if !defined $lookup->[0]->{$value1} || $lookup->[0]->{$value1} eq '';
				$lookup->[1]->{$value2} = 'No value' if !defined $lookup->[1]->{$value2} || $lookup->[1]->{$value2} eq '';
				if ( $attribute[0] && $attribute[1] ) {
					$new_hash->{ $lookup->[0]->{$value1} }->{ $lookup->[1]->{$value2} } += $datahash_ref->{$value1}->{$value2};
				} elsif ( $attribute[0] ) {
					$new_hash->{ $lookup->[0]->{$value1} }->{$value2} += $datahash_ref->{$value1}->{$value2};
				} elsif ( $attribute[1] ) {
					$new_hash->{$value1}->{ $lookup->[1]->{$value2} } += $datahash_ref->{$value1}->{$value2};
				}
			}
		}
	}
	return $new_hash;
}
1;
