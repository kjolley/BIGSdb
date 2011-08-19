#FieldBreakdown.pm - TwoFieldBreakdown plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
use base qw(BIGSdb::Plugin);
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
		version     => '1.0.2',
		dbtype      => 'isolates',
		section     => 'breakdown,postquery',
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
	print "<h1>Two field breakdown of dataset</h1>\n";
	my $format = $q->param('format');
	$self->{'extended'} = $self->get_extended_attributes;
	if ( !$q->param('function') ) {
		$self->_print_interface;
		return;
	}
	my %prefs;
	my $query_file = $q->param('query_file');
	my $qry_ref    = $self->get_query($query_file);
	return if ref $qry_ref ne 'SCALAR';
	my $qry = $$qry_ref;
	$qry =~ s/ORDER BY.*$//g;
	$logger->debug("Breakdown query: $qry");
	return if !$self->create_temp_tables($qry_ref);

	if ( $q->param('function') eq 'breakdown' ) {
		$self->_breakdown( \$qry );
	}
}

sub _print_interface {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<div class=\"box\" id=\"queryform\">\n";
	print "<div class=\"scrollable\">\n";
	print "<p>Here you can create a table breaking down one field by another, e.g. breakdown of serogroup by year.</p>\n";
	print $q->startform;
	$q->param( 'function', 'breakdown' );
	print $q->hidden($_) foreach qw (db page name function query_file);
	my ( $headings, $labels ) =
	  $self->get_field_selection_list( { 'isolate_fields' => 1, 'extended_attributes' => 1, 'loci' => 1, 'scheme_fields' => 1 } );
	print "<table>";
	print "<tr><td align='right'>Select first field:</td>\n";
	print "<td>\n";
	print $q->popup_menu( -name => 'field1', -values => $headings, -labels => $labels );
	print "</td>\n";
	print "<td rowspan=\"2\" style=\"padding-left:1em\">";
	print "Display:<br />\n";
	print $q->radio_group(
		-name      => 'display',
		-values    => [ 'values only', 'values and percentages', 'percentages only' ],
		-default   => 'values only',
		-linebreak => 'true'
	);
	print "</td><td rowspan=\"2\">";
	print "Calculate percentages by:<br /> ";
	print $q->radio_group( -name => 'calcpc', -values => [ 'dataset', 'row', 'column' ], -default => 'dataset', -linebreak => 'true' );
	print "</td></tr>\n";
	print "<tr><td align='right' valign='top'>Select second field:</td><td valign='top'>\n";
	print $q->popup_menu( -name => 'field2', -values => $headings, -labels => $labels );
	print "</td></tr>\n";
	print "<tr><td>";
	print $q->reset( -class => 'reset' );
	print "</td><td colspan=\"3\" style=\"text-align:right\">";
	print $q->submit( -class => 'submit', -label => 'Submit' );
	print "</td></tr>\n</table>\n";
	print $q->endform;
	print "</div>\n</div>\n";
}

sub _breakdown {
	my ( $self, $qry_ref ) = @_;
	my $q      = $self->{'cgi'};
	my $field1 = $q->param('field1');
	my $field2 = $q->param('field2');
	if ( $q->param('reverse') ) {
		$field1 = $q->param('field2');
		$field2 = $q->param('field1');
		$q->param( 'field1', $field1 );
		$q->param( 'field2', $field2 );
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
		print "<div class=\"box\" id=\"statusbad\"><p>You must select two <em>different</em> fields.</p></div>\n";
		return;
	}
	my ( $display, $calcpc );
	my ( $grandtotal, $datahash_ref, $field1total_ref, $field2total_ref, $clean_field1, $clean_field2, $print_field1, $print_field2 );
	try {
		( $grandtotal, $datahash_ref, $field1total_ref, $field2total_ref, $clean_field1, $clean_field2, $print_field1, $print_field2 ) =
		  $self->_get_value_frequency_hashes( $field1, $field2, $qry_ref );
	}
	catch BIGSdb::DatabaseConnectionException with {
		print
"<div class=\"box\" id=\"statusbad\"><p>The database for the scheme of one of your selected fields is inaccessible.  This may be a configuration problem.</p></div>\n";
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
		$print_field1 = "$field1..$attribute1";
	}
	if ($attribute2) {
		$print_field2 = "$field2..$attribute2";
	}
	my ( %datahash, %field1total, %field2total );
	eval {
		%datahash    = %$datahash_ref;
		%field1total = %$field1total_ref;
		%field2total = %$field2total_ref;
	};
	if ( $@ =~ /HASH reference/ ) {
		$logger->debug($@);
		print "<div class=\"box\" id=\"statusbad\"><p>No data retrieved.</p></div>\n";
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
		print
"<div class=\"box\" id=\"statusbad\"><p>One of your selected fields has more than 2000 values - calculation has been disabled to prevent your browser locking up.</p>";
		print "<p>$print_field1: " . ( scalar keys %datahash ) . "<br />";
		print "$print_field2: $numfield2</p>\n";
		print "</div>\n";
		return;
	}
	if ( $q->param('toggledisplay') ) {
		if ( $q->param('toggledisplay') eq 'Show values only' ) {
			$q->param( 'display', 'values only' );
		} elsif ( $q->param('toggledisplay') eq 'Show values and percentages' ) {
			$q->param( 'display', 'values and percentages' );
		} elsif ( $q->param('toggledisplay') eq 'Show percentages only' ) {
			$q->param( 'display', 'percentages only' );
		}
	}
	if ( $q->param('display') ) {
		$display = $q->param('display');
	} else {
		$display = 'values only';
	}
	if ( $q->param('togglepc') ) {
		if ( $q->param('togglepc') eq 'Calculate percentages by row' ) {
			$q->param( 'calcpc', 'row' );
		} elsif ( $q->param('togglepc') eq 'Calculate percentages by column' ) {
			$q->param( 'calcpc', 'column' );
		} elsif ( $q->param('togglepc') eq 'Calculate percentages by dataset' ) {
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
	print "<div class=\"box\" id=\"resultstable\">\n";
	print "<h2>Breakdown of $print_field1 by $print_field2:</h2>\n";
	print $fh "Breakdown of $print_field1 by $print_field2:\n";
	print "<p>Selected options: Display $display. ";
	print $fh "Selected options: Display $display. ";

	if ( $display ne 'values only' ) {
		print "Calculate percentages by $calcpc.";
		print $fh "Calculate percentages by $calcpc.";
	}
	print "</p>\n";
	print $fh "\n\n";
	print "<table><tr><td>\n";
	print $q->startform;
	print $q->hidden($_) foreach qw (db page name function query_file field1 field2 display calcpc);
	print $q->submit( -name => 'reverse', -value => 'Reverse axes', -class => 'submit' );
	print $q->endform;
	print "</td><td>\n";
	print $q->startform;
	print $q->hidden($_) foreach qw (db page name function query_file field1 field2 display calcpc);
	my %toggle =
	  ( 'values only' => 'values and percentages', 'values and percentages' => 'percentages only', 'percentages only' => 'values only' );
	print $q->submit( -name => 'toggledisplay', -label => ( 'Show ' . $toggle{ $q->param('display') } ), -class => 'submit' );
	print $q->endform;
	print "</td>\n";

	if ( $q->param('display') ne 'values only' ) {
		print "<td>";
		print $q->startform;
		print $q->hidden($_) foreach qw (db page name function query_file field1 field2 display calcpc);
		my %toggle = ( 'dataset' => 'row', 'row' => 'column', 'column' => 'dataset' );
		print $q->submit( -name => 'togglepc', -label => ( 'Calculate percentages by ' . $toggle{ $q->param('calcpc') } ),
			-class => 'submit' );
		print $q->endform;
		print "</td>\n";
	}
	print "</tr></table>\n";
	print "<div class=\"scrollable\">\n";
	print "<table class=\"tablesorter\" id=\"sortTable\">\n<thead>\n";
	print "<tr><td /><td colspan=\"$numfield2\" class=\"header\">$print_field2</td></tr>\n";
	print $fh "$print_field1\t$print_field2\n";
	$" = "</th><th class=\"{sorter: 'digit'}\">";
	print
"<tr><th>$print_field1</th><th class=\"{sorter: 'digit'}\">@field2values</th><th class=\"{sorter: 'digit'}\">Total</th></tr></thead><tbody>\n";
	$" = "\t";
	print $fh "\t@field2values\tTotal\n";
	my $td = 1;
	{
		no warnings;    #might complain about numeric comparison with non-numeric data
		for my $field1value ( sort { $a <=> $b || $a cmp $b } keys %datahash ) {
			my $total = 0;
			print "<tr class=\"td$td\"><td>$field1value</td>\n";
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
					print "<td></td>\n";
					print $fh "\t";
				} else {
					if ( $q->param('display') eq 'values and percentages' ) {
						print "<td>$value ($percentage%)</td>\n";
						print $fh "\t$value ($percentage%)";
					} elsif ( $q->param('display') eq 'percentages only' ) {
						print "<td>$percentage</td>\n";
						print $fh "\t$percentage";
					} else {
						print "<td>$value</td>\n";
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
				print "<td>$total ($percentage%)</td></tr>\n";
				print $fh "\t$total ($percentage%)\n";
			} elsif ( $q->param('display') eq 'percentages only' ) {
				print "<td>$percentage</td></tr>\n";
				print $fh "\t$percentage\n";
			} else {
				print "<td>$total</td></tr>\n";
				print $fh "\t$total\n";
			}
			$td = $td == 1 ? 2 : 1;    #row stripes
		}
	};
	print "</tbody><tbody><tr class=\"total\"><td>Total</td>\n";
	print $fh "Total";
	foreach my $field2value (@field2values) {
		my $percentage;
		if ( $q->param('calcpc') eq 'column' ) {
			$percentage = 100;
		} else {
			$percentage = BIGSdb::Utils::decimal_place( ( $field2total{$field2value} / $grandtotal ) * 100, 1 );
		}
		if ( $q->param('display') eq 'values and percentages' ) {
			print "<td>$field2total{$field2value} ($percentage%)</td>";
			print $fh "\t$field2total{$field2value} ($percentage%)";
		} elsif ( $q->param('display') eq 'percentages only' ) {
			print "<td>$percentage</td>";
			print $fh "\t$percentage";
		} else {
			print "<td>$field2total{$field2value}</td>";
			print $fh "\t$field2total{$field2value}";
		}
	}
	if ( $q->param('display') eq 'values and percentages' ) {
		print "<td>$grandtotal (100%)</td></tr>\n";
		print $fh "\t$grandtotal (100%)\n";
	} elsif ( $q->param('display') eq 'percentages only' ) {
		print "<td>100</td></tr>\n";
		print $fh "\t100\n";
	} else {
		print "<td>$grandtotal</td></tr>\n";
		print $fh "\t$grandtotal\n";
	}
	print "</tbody></table></div>\n";
	close $fh;
	print "<p><a href='/tmp/$temp1.txt'>Download as tab-delimited text.</a></p>\n";

	#Chartdirector
	if ( scalar keys %datahash < 31 && scalar @field2values < 31 ) {
		if ( $self->{'config'}->{'chartdirector'} ) {
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
			print "<div class=\"scrollable\" style=\"background:white; border: 1px solid black\">\n";
			for ( my $i = 0 ; $i < 2 ; $i++ ) {
				my $chart = new XYChart( 1000, 500 );
				$chart->setPlotArea( 100, 40, 580, 300 );
				$chart->setBackground(0x00FFFFFF);
				$chart->setTransparentColor(0x00FFFFFF);
				$chart->addLegend( 700, 10 );
				$chart->xAxis()->setLabels( \@field2values )->setFontAngle(60);
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
				for my $field1value ( sort { $field1total{$b} <=> $field1total{$a} || $a cmp $b } keys %datahash ) {
					if ( $field1value ne 'No value' ) {
						my @dataset;
						foreach my $field2value (@field2values) {
							if ( !$datahash{$field1value}{$field2value} ) {
								push @dataset, 0;
							} else {
								push @dataset, $datahash{$field1value}{$field2value};
							}
						}
						$layer->addDataSet( \@dataset, -1, $field1value );
					}
				}

				#Put unassigned or no value at end
				my @specials = ( 'Unassigned', 'No value', 'unspecified' );
				foreach my $specialvalue (@specials) {
					if ( $datahash{$specialvalue} ) {
						my @dataset;
						foreach my $field2value (@field2values) {
							if ( !$datahash{$specialvalue}{$field2value} ) {
								push @dataset, 0;
							} else {
								push @dataset, $datahash{$specialvalue}{$field2value};
							}
						}
						$layer->addDataSet( \@dataset, -1, $specialvalue );
					}
				}
				if ( !$i ) {
					$chart->addTitle( "Values", "arial.ttf", 14 );
					my $filename = "$temp1\_$field1\_$field2.png";
					if ( $filename =~ /(BIGSdb.*\.png)/ ) {
						$filename = $1;    #untaint
					}
					$chart->makeChart("$self->{'config'}->{'tmp_dir'}\/$filename");
					print "<img src=\"/tmp/$filename\" alt=\"$field1 vs $field2\" />";
				} else {
					$chart->addTitle( "Percentages", "arial.ttf", 14 );
					my $filename = "$temp1\_$field1\_$field2\_pc.png";
					if ( $filename =~ /(BIGSdb.*\.png)/ ) {
						$filename = $1;    #untaint
					}
					$chart->makeChart("$self->{'config'}->{'tmp_dir'}\/$filename");
					print "<img src=\"/tmp/$filename\" alt=\"$field1 vs $field2 percentage chart\" />";
				}
			}
			print "</div>\n";
		}
	}
	print "</div>\n";
}

sub _get_value_frequency_hashes {
	my ( $self, $field1, $field2, $qry_ref ) = @_;
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
			$field_type{$_} = 'field';
			$print{$_}      = $clean{$_};
		} elsif ( $self->{'datastore'}->is_locus( $clean{$_} ) ) {
			$field_type{$_} = 'locus';
			$print{$_}      = $clean{$_};
			$clean{$_} =~ s/'/\\'/g;
		} else {
			if ( $_ =~ /^s_(\d+)_(.*)/ ) {
				my $scheme_id = $1;
				my $field     = $2;
				if ( $self->{'datastore'}->is_scheme_field( $scheme_id, $field ) ) {
					$field_type{$_} = 'scheme_field';
					$scheme_id{$_}  = $scheme_id;
					$clean{$_}      = $field;
					$print{$_}      = $clean{$_};
					my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id{$_} );
					$print{$_} .= " ($scheme_info->{'description'})";
				}
			}
		}
		$print{$_} =~ tr/_/ /;
	}
	if ( $field_type{$field1} eq $field_type{$field2} && $field_type{$field1} eq 'field' ) {
		$$qry_ref =~ s/SELECT \*/SELECT $clean{$field1},$clean{$field2}/;
	} elsif ( $field_type{$field1} eq 'field' && $field_type{$field2} eq 'locus' ) {
		$$qry_ref =~
s/SELECT \* FROM $self->{'system'}->{'view'}/SELECT $self->{'system'}->{'view'}.$clean{$field1},allele_id AS field2 FROM $self->{'system'}->{'view'} LEFT JOIN allele_designations ON id=isolate_id AND locus='$clean{$field2}'/;
	} elsif ( $field_type{$field2} eq 'field' && $field_type{$field1} eq 'locus' ) {
		$$qry_ref =~
s/SELECT \* FROM $self->{'system'}->{'view'}/SELECT allele_id AS field1,$self->{'system'}->{'view'}.$clean{$field2} FROM $self->{'system'}->{'view'} LEFT JOIN allele_designations ON id=isolate_id AND locus='$clean{$field1}'/;
	} elsif ( $field_type{$field1} eq 'field' && $field_type{$field2} eq 'scheme_field' ) {
		$self->_modify_qry_f_s( $qry_ref, \%clean, \%scheme_id, $field1, $field2 );
	} elsif ( $field_type{$field2} eq 'field' && $field_type{$field1} eq 'scheme_field' ) {
		$self->_modify_qry_f_s( $qry_ref, \%clean, \%scheme_id, $field2, $field1, 1 );
	} elsif ( $field_type{$field1} eq 'locus' && $field_type{$field2} eq 'locus' ) {
		$$qry_ref =~
s/SELECT \* FROM $self->{'system'}->{'view'}/SELECT field1.allele_id AS field1,field2.allele_id AS field2 FROM $self->{'system'}->{'view'} LEFT JOIN allele_designations AS field1 ON id=field1.isolate_id AND field1.locus='$clean{$field1}' LEFT JOIN allele_designations AS field2 ON id=field2.isolate_id AND field2.locus='$clean{$field2}'/;
	} elsif ( $field_type{$field1} eq 'locus' && $field_type{$field2} eq 'scheme_field' ) {
		$self->_modify_qry_f_s( $qry_ref, \%clean, \%scheme_id, $field1, $field2 );
		$$qry_ref =~
s/SELECT (.*?) FROM $self->{'system'}->{'view'}/SELECT $1 FROM $self->{'system'}->{'view'} LEFT JOIN allele_designations AS field1 ON id=isolate_id AND locus='$clean{$field1}'/;
		$clean{$field1} =~ s/'/\\'/;
		$$qry_ref =~ s/$clean{$field1}/field1.allele_id/;
	} elsif ( $field_type{$field2} eq 'locus' && $field_type{$field1} eq 'scheme_field' ) {
		$self->_modify_qry_f_s( $qry_ref, \%clean, \%scheme_id, $field2, $field1, 1 );
		$$qry_ref =~
s/SELECT (.*?) FROM $self->{'system'}->{'view'}/SELECT $1 FROM $self->{'system'}->{'view'} LEFT JOIN allele_designations AS field2 ON id=isolate_id AND locus='$clean{$field2}'/;
		$clean{$field2} =~ s/'/\\'/;
		$$qry_ref =~ s/$clean{$field2}/field2.allele_id/;
	} elsif ( $field_type{$field2} eq 'scheme_field' && $field_type{$field1} eq 'scheme_field' ) {
		$self->_modify_qry_s_s( $qry_ref, \%clean, \%scheme_id, $field1, $field2 );
	} else {
		return;
	}

	#In some circumstances, such as selecting a scheme field as one of the query fields, when the dataset
	#had been filtered based on a scheme field, the query planner chose a plan with multiple nested loops
	#due to poor estimation of the number of rows returned for particular subqueries.  On a test database
	#switching the enable_nestloop setting to off speeded up the calculation from many minutes to a couple
	#of seconds.
	#
	#Disabled now as more recent PostgreSQL versions don't seem to have the problem.
	#
	#	$$qry_ref = "SET enable_nestloop = off; " . $$qry_ref
	#	  if ( $field_type{$field1} eq 'scheme_field' || $field_type{$field2} eq 'scheme_field' );
	$logger->debug($$qry_ref);
	my $sql = $self->{'db'}->prepare($$qry_ref);
	eval { $sql->execute };
	$logger->error($@) if $@;
	while ( my ( $value1, $value2 ) = $sql->fetchrow_array ) {
		foreach ( $value1, $value2 ) {
			$_ = 'No value' if !defined $_ || $_ eq '';
		}
		$datahash->{$value1}->{$value2}++;
		$grandtotal++;
		$field1total->{$value1}++;
		$field2total->{$value2}++;
	}
	return ( $grandtotal, $datahash, $field1total, $field2total, $clean{$field1}, $clean{$field2}, $print{$field1}, $print{$field2} );
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
				$lookup->[0]->{$value1} = 'No value' if $lookup->[0]->{$value1} eq '';
				$lookup->[1]->{$value2} = 'No value' if $lookup->[1]->{$value2} eq '';
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

sub _modify_qry_f_s {

	#field1 is an isolate field, field2 is a scheme field
	my ( $self, $qry_ref, $clean_ref, $scheme_id_ref, $field1, $field2, $switch ) = @_;
	try {
		$self->{'datastore'}->create_temp_scheme_table( $scheme_id_ref->{$field2} );
	}
	catch BIGSdb::DatabaseConnectionException with {
		$logger->error("Can't copy data to temporary table.");
	};
	my $scheme_sql_ref = $self->_get_scheme_fields_sql( $scheme_id_ref->{$field2} );
	$$qry_ref =~ s/WHERE/AND/;
	foreach ( $field1, $field2 ) {
		if (   $clean_ref->{$_} eq 'datestamp'
			|| $clean_ref->{$_} eq 'date_entered'
			|| $clean_ref->{$_} eq 'sender'
			|| $clean_ref->{$_} eq 'curator' )
		{
			$clean_ref->{$_} = $self->{'system'}->{'view'} . ".$clean_ref->{$_}";
		}
	}
	if ($switch) {
		$$qry_ref =~
s/SELECT \* FROM $self->{'system'}->{'view'}/SELECT $clean_ref->{$field2},$clean_ref->{$field1} FROM $self->{'system'}->{'view'} $$scheme_sql_ref/;
	} else {
		$$qry_ref =~
s/SELECT \* FROM $self->{'system'}->{'view'}/SELECT $clean_ref->{$field1},$clean_ref->{$field2} FROM $self->{'system'}->{'view'} $$scheme_sql_ref/;
	}
	if ( $$qry_ref =~ /pubmed_id/ ) {
		$$qry_ref =~ s/LEFT JOIN refs on refs.isolate_id=$self->{'system'}->{'view'}.id//;
		$$qry_ref =~ s/FROM $self->{'system'}->{'view'}/FROM $self->{'system'}->{'view'} LEFT JOIN refs ON refs.isolate_id=id/;
	}
}

sub _modify_qry_s_s {

	#both fields are scheme fields
	my ( $self, $qry_ref, $clean_ref, $scheme_id_ref, $field1, $field2 ) = @_;
	try {
		$self->{'datastore'}->create_temp_scheme_table( $scheme_id_ref->{$field1} );
		$self->{'datastore'}->create_temp_scheme_table( $scheme_id_ref->{$field2} );
	}
	catch BIGSdb::DatabaseConnectionException with {
		$logger->error("Can't copy data to temporary table.");
	};
	my $scheme_loci = $self->{'datastore'}->get_scheme_loci( $scheme_id_ref->{$field1} );
	my $scheme_sql = $self->_join_table( $scheme_id_ref->{$field1}, $scheme_loci );
	if ( $scheme_id_ref->{$field1} != $scheme_id_ref->{$field2} ) {
		my $scheme_loci = $self->{'datastore'}->get_scheme_loci( $scheme_id_ref->{$field2} );
		$scheme_sql .= $self->_join_table( $scheme_id_ref->{$field2}, $scheme_loci );
	}

	#$$qry_ref =~ s/WHERE/AND/;
	$$qry_ref =~
s/SELECT \* FROM $self->{'system'}->{'view'}/SELECT scheme_$scheme_id_ref->{$field1}.$clean_ref->{$field1},scheme_$scheme_id_ref->{$field2}.$clean_ref->{$field2} FROM $self->{'system'}->{'view'} $scheme_sql/;
	if ( $$qry_ref =~ /pubmed_id/ ) {
		$$qry_ref =~ s/LEFT JOIN refs on refs.isolate_id=$self->{'system'}->{'view'}.id//;
		$$qry_ref =~ s/FROM $self->{'system'}->{'view'}/FROM $self->{'system'}->{'view'} LEFT JOIN refs ON refs.isolate_id=id/;
	}
}

sub _join_table {
	my ( $self, $scheme_id, $scheme_loci ) = @_;
	$" = ',';
	my $joined_table;
	$" = ',';
	foreach (@$scheme_loci) {
		$joined_table .=
" left join allele_designations AS s_$scheme_id\_$_ on s_$scheme_id\_$_.isolate_id = $self->{'system'}->{'view'}.id and s_$scheme_id\_$_.locus='$_'";
	}
	$joined_table .= " left join temp_scheme_$scheme_id AS scheme_$scheme_id ON ";
	my @temp;
	foreach (@$scheme_loci) {
		my $locus_info = $self->{'datastore'}->get_locus_info($_);
		push @temp, $locus_info->{'allele_id_format'} eq 'integer'
		  ? " CAST(s_$scheme_id\_$_.allele_id AS int)=scheme_$scheme_id\.$_"
		  : " s_$scheme_id\_$_.allele_id=scheme_$scheme_id\.$_";
	}
	$" = ' AND ';
	$joined_table .= " @temp";
	return $joined_table;
}

sub _get_scheme_fields_sql {
	my ( $self, $scheme_id ) = @_;
	my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $joined_table = $self->_join_table( $scheme_id, $scheme_loci );
	$joined_table .= " WHERE";
	my @temp;
	foreach (@$scheme_loci) {
		push @temp, "s_$scheme_id\_$_.locus='$_'";
	}
	$" = ' AND ';
	$joined_table .= " @temp";
	return \$joined_table;
}
1;
