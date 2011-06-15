#FieldBreakdown.pm - FieldBreakdown plugin for BIGSdb
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
package BIGSdb::Plugins::FieldBreakdown;
use strict;
use base qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);

sub get_attributes {
	my %att = (
		name        => 'Field Breakdown',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Breakdown of query results by field',
		category    => 'Breakdown',
		buttontext  => 'Fields',
		menutext    => 'Single field',
		module      => 'FieldBreakdown',
		version     => '1.0.0',
		dbtype      => 'isolates',
		section     => 'breakdown,postquery',
		input       => 'query',
		requires    => 'chartdirector',
		order       => 10
	);
	return \%att;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { 'general' => 0, 'main_display' => 0, 'isolate_display' => 0, 'analysis' => 0, 'query_field' => 0 };
}

sub get_option_list {
	my @list = (
		{
			name        => 'style',
			description => 'Pie chart style',
			optlist     => 'pie;doughnut',
			default     => 'doughnut'
		},
		{
			name        => 'small',
			description => 'Display small charts',
			default     => 1
		},
		{
			name        => 'threeD',
			description => 'Enable 3D effect',
			default     => 1
		},
		{
			name        => 'transparent',
			description => 'Enable transparent palette',
			default     => 1
		},
		{
			name        => 'breakdown_composites',
			description =>
'Breakdown composite fields (will slow down display of statistics for large datasets)',
			default => 0
		}
	);
	return \@list;
}

sub get_plugin_javascript {
	my ($self)   = @_;
	my $q           = $self->{'cgi'};
	my $query_file  = $q->param('query_file');
	my $script_name = $self->{'system'}->{'script_name'};
	my $links       = my $js = << "END";
\$(function () {
	\$("#imagegallery a").click(function(event){
		event.preventDefault();
		var image = \$(this).attr("href");
		\$("img#placeholder").attr("src",image);
		var field = \$(this).attr("name");
		var display = field;
		display = display.replace(/_/g," ");
		
		\$("#field").empty();
		\$("#field").append(display);
		\$("#links").empty();
		\$("#links").append("<p><a href='$script_name?db=$self->{'instance'}&amp;page=plugin&amp;name=FieldBreakdown&amp;function=summary_table&amp;query_file=$query_file&amp;field=" + field + "&amp;format=html'>Display table</a> | <a href='$script_name?db=$self->{'instance'}&amp;page=plugin&amp;name=FieldBreakdown&amp;function=summary_table&amp;query_file=$query_file&amp;field=" + field + "&amp;format=text'>Tab-delimited text</a></p>");
	});		
});
END
	return $js;
}

sub _use_composites {
	my ($self) = @_;
	my $use;
	my $guid = $self->get_guid;
	#my $guid = $self->{'cgi'}->cookie( -name => 'guid' );
	try {
		$use = $self->{'prefstore'}->get_plugin_attribute(
			$guid,            $self->{'system'}->{'db'},
			'FieldBreakdown', 'breakdown_composites'
		);
		$use = $use eq 'true' ? 1 : 0;
	  }
	  catch BIGSdb::DatabaseNoRecordException with {
		$use = 0;
	  };
	return $use;
}

sub run {
	my ($self)   = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $format     = $q->param('format');
	if ( $q->param('function') ne 'summary_table' ) {
		print "<h1>Field breakdown of dataset</h1>\n";
		print
"<script type=\"text/javascript\">\n//<![CDATA[\ndocument.write('<p id=\"hideonload\"><b>Please wait for charts to be generated ...</b></p>')\n//]]>\n</script>\n";
	}
	my %prefs;
	$prefs{'breakdown_composites'} = $self->_use_composites;
	my $qry_ref = $self->get_query($query_file);
	return if ref $qry_ref ne 'SCALAR';
	my $qry = $$qry_ref;
	$qry =~ s/ORDER BY.*$//g;
	$logger->debug("Breakdown query: $qry");
	return if !$self->create_temp_tables($qry_ref);
	
	$self->{'extended'} = $self->get_extended_attributes;

	if ( $q->param('function') eq 'summary_table' ) {
		$self->_summary_table($qry);
		return;
	}
	$| = 1;
	my %noshow;
	if ( $self->{'system'}->{'noshow'} ) {
		foreach ( split /,/, $self->{'system'}->{'noshow'} ) {
			$noshow{$_} = 1;
		}
	}
	foreach (qw (id isolate datestamp date_entered curator sender comments)) {
		$noshow{$_} = 1;
	}
	my $temp = BIGSdb::Utils::get_random();
	print "<div id=\"imagegallery\">\n";
	my ( $num_records, $value_frequency ) =
	  $self->_get_value_frequency_hash( \$qry );
	my $first = 1;
	my ( $src, $name, $title );
	print "<p>";
	my ( %composites, %composite_display_pos );

	if ( $prefs{'breakdown_composites'} ) {
		my $qry = "SELECT id,position_after FROM composite_fields";
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute; };
		if ($@) {
			$logger->error("Can't execute $qry");
		} else {
			while ( my @data = $sql->fetchrow_array() ) {
				$composite_display_pos{ $data[0] } = $data[1];
				$composites{ $data[1] }            = 1;
			}
		}
	}
	my $display_name;
	my $field_list = $self->{'xmlHandler'}->get_field_list();
	my @expanded_list;
	foreach (@$field_list){
		push @expanded_list,$_;
		if (ref $self->{'extended'}->{$_} eq 'ARRAY'){
			foreach my $attribute (@{$self->{'extended'}->{$_}}){
				push @expanded_list,"$_\.\.$attribute";
			} 
		}
	}
	foreach my $field ( @expanded_list ) {
		if ( !$noshow{$field} ) {
			my $display = $field;
			$display =~ tr/_/ /;
			my $display_field = $field;
			
			my $num_values = keys %{ $value_frequency->{$field} };
			my $plural = $num_values != 1 ? 's' : '';
			$title = "$display - $num_values value$plural";
			print " | " if !$first;
			print
"<a href=\"/tmp/$temp\_$field.png\" name=\"$display_field\" title=\"$title\">$display</a>";
			$self->_create_chartdirector_chart( $field, $num_values,
				$value_frequency->{$field},
				$temp, $query_file );

			if ($first) {
				$src          = "/tmp/$temp\_$field.png";
				$display_name = "$display";
				$name         = "$field";
				undef $first;
			}
			if ( $ENV{'MOD_PERL'} ) {
				$self->{'mod_perl_request'}->rflush;
			}
		}
		if ( $prefs{'breakdown_composites'} && $composites{$field} ) {
			print " | " if !$first;
			foreach ( keys %composite_display_pos ) {
				next if $composite_display_pos{$_} ne $field;
				my $display = $_;
				$display =~ tr/_/ /;
				$title = "$display - This is a composite field";
				print
"<a href=\"/tmp/$temp\_$_.png\" name=\"$_\" title=\"$title\">$display</a>";
				$self->_create_chartdirector_chart( $_, 2,
					$value_frequency->{$_},
					$temp, $query_file );
				if ($first) {
					$src          = "/tmp/$temp\_$_.png";
					$display_name = "$display";
					$name         = $_;
					undef $first;
				}
			}
		}
	}
	print "</p></div>\n";
	print
"<noscript><p class=\"highlight\">Please enable Javascript to view breakdown charts in place.</p></noscript>\n";
	print "<h2 id=\"field\">$display_name</h2>\n";
	print
"<div class=\"box\" id=\"chart\"><img id=\"placeholder\" src=\"$src\" alt=\"breakdown chart\" /></div>\n";
	print
"<p id=\"links\"><a href='$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;name=FieldBreakdown&amp;function=summary_table&amp;query_file=$query_file&amp;field=$name&amp;format=html'>Display table</a> | <a href='$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;name=FieldBreakdown&amp;function=summary_table&amp;query_file=$query_file&amp;field=$name&amp;format=text'>Tab-delimited text</a></p>\n";
}

sub _create_chartdirector_chart {
	my ( $self, $field, $numvalues, $value_frequency_ref, $temp, $query_file ) =
	  @_;
	my $q = $self->{'cgi'};
	my $guid = $self->get_guid;
	my %prefs;
	foreach (qw (threeD transparent small)) {
		try {
			$prefs{$_} =
			  $self->{'prefstore'}
			  ->get_plugin_attribute( $guid, $self->{'system'}->{'db'},
				'FieldBreakdown', $_ );
			$prefs{$_} = $prefs{$_} eq 'true' ? 1 : 0;
		  }
		  catch BIGSdb::DatabaseNoRecordException with {
			$prefs{$_} = 1;
		  };
	}
	try {
		$prefs{'style'} =
		  $self->{'prefstore'}
		  ->get_plugin_attribute( $guid, $self->{'system'}->{'db'},
			'FieldBreakdown', 'style' );
	  }
	  catch BIGSdb::DatabaseNoRecordException with {
		$prefs{'style'} = 'doughnut';
	  };
	my %value_frequency = %{$value_frequency_ref};
	my ( @labels, @values );
	my $values_shown = $numvalues;
	if ( $value_frequency{'No value/unassigned'} ) {
		$values_shown--;
	}
	my $plural      = $values_shown != 1 ? 's' : '';
	my $script_name = $self->{'system'}->{'script_name'};
	my $size        = $prefs{'small'} ? 'small' : 'large';
	if (   $field =~ /^age_/
		or $field =~ /^age$/
		or $field =~ /^year_/
		or $field =~ /^year$/ )
	{
		no warnings
		  ;    #might complain about numeric comparison with non-numeric data
		foreach my $key ( sort { $a <=> $b } keys %value_frequency ) {
			if ( !( $key eq 'No value/unassigned' && $numvalues > 1 ) ) {
				$key =~ s/&Delta;/deleted/g;
				push @labels, $key;
				push @values, $value_frequency{$key};
			}
		}
		if (@labels) {
			BIGSdb::Charts::barchart( \@labels, \@values,
				"$self->{'config'}->{'tmp_dir'}/$temp\_$field.png",
				$size, \%prefs );
		}
	} else {
		no warnings
		  ;    #might complain about numeric comparison with non-numeric data
		foreach my $key (
			sort {
				     $value_frequency{$b} <=> $value_frequency{$a}
				  || ( $a <=> $b )
				  || ( $a cmp $b )
			} keys %value_frequency
		  )
		{
			$key =~ s/&Delta;/deleted/g;
			push @labels, $key;
			push @values, $value_frequency{$key};
		}
		BIGSdb::Charts::piechart( \@labels, \@values,
			"$self->{'config'}->{'tmp_dir'}/$temp\_$field.png",
			24, $size, \%prefs );
	}
}

sub _is_composite_field {
	my ( $self, $field ) = @_;
	my $is_composite = 
		$self->{'datastore'}->run_simple_query(
			"SELECT COUNT(*) FROM composite_fields WHERE id=?", $field )->[0];
	return $is_composite;
}

sub _summary_table {
	my ( $self, $qry ) = @_;
	my $q      = $self->{'cgi'};
	my $field  = $q->param('field');
	my $format = $q->param('format') || 'html';
	if ( !$field ) {
		if ( $format ne 'text' ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No field selected.</p></div>\n";
		} else {
			print "No field selected.\n";
		}
		return;
	}
	my $isolate_field = $field;
	$isolate_field =~ s/\.\..*$//; #Extended attributes separated from parent field by '..'
	if (   !$self->{'xmlHandler'}->is_field($isolate_field)
		&& !$self->_is_composite_field($field) )
	{
		if ( $format ne 'text' ) {
			print
			  "<div class=\"box\" id=\"statusbad\"><p>Invalid field selected.</p></div>\n";
		} else {
			print "Invalid file selected.\n";
		}
		return;
	}
	if ( !$qry ) {
		if ( $format ne 'text' ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No query selected.</p></div>\n";
		} else {
			print "No query selected.\n";
		}
		return;
	}
	my $td = 1;
	my ( @labels, @values );
	my $display_field = $field;
	$display_field =~ tr/_/ /;
	if ( $format eq 'html' ) {
		print "<h1>Breakdown by $display_field</h1>\n";
	} else {
		print "Breakdown for $display_field\n\n";
	}
	$logger->debug("Breakdown query: $qry");
	my ( $num_records, $frequency ) =
	  $self->_get_value_frequency_hash( \$qry, $isolate_field );
	my $value_frequency = $frequency->{$field};
	my $num_values      = keys %{$value_frequency};
	my $values_shown    = $num_values;
	if ( $value_frequency->{'No value/unassigned'} ) {
		$values_shown--;
	}
	my $plural = $num_values != 1 ? 's' : '';
	if ( $format eq 'html' ) {
		print "<div class=\"box\" id=\"resultstable\">";
		print "<p>$num_values value$plural.</p>\n";
		print
"<table class=\"tablesorter\" id=\"sortTable\"><thead><tr><th>$field</th><th>Frequency</th><th>Percentage</th></tr></thead><tbody>\n";
	} else {
		print "$num_values value$plural.\n\n";
		print "$field\tfrequency\tpercentage\n";
	}
	if (   $field =~ /^age_/
		or $field =~ /^age$/
		or $field =~ /^year_/
		or $field =~ /^year$/ )
	{

		#sort keys numerically
		no warnings
		  ;    #might complain about numeric comparison with non-numeric data
		foreach my $key ( sort { $a <=> $b } keys %$value_frequency ) {
			my $percentage =
			  BIGSdb::Utils::decimal_place(
				( $value_frequency->{$key} / $num_records ) * 100, 2 );
			if ( $format eq 'html' ) {
				print
"<tr class=\"td$td\"><td>$key</td><td>$value_frequency->{$key}</td><td style=\"text-align:center\">$percentage%</td></tr>\n";
			} else {
				print "$key\t$value_frequency->{$key}\t$percentage\n";
			}
			$td = $td == 1 ? 2 : 1;    #row stripes
		}
	} else {
		no warnings
		  ;    #might complain about numeric comparison with non-numeric data
		foreach my $key (
			sort {
				     $value_frequency->{$b} <=> $value_frequency->{$a}
				  || ( $a <=> $b )
				  || ( $a cmp $b )
			} keys %$value_frequency
		  )
		{
			push @labels, $key;
			push @values, $value_frequency->{$key};
			my $percentage =
			  BIGSdb::Utils::decimal_place(
				( $value_frequency->{$key} / $num_records ) * 100, 2 );
			if ( $format eq 'html' ) {
				print
"<tr class=\"td$td\"><td>$key</td><td style=\"text-align:center\">$value_frequency->{$key}</td><td style=\"text-align:center\">$percentage%</td></tr>\n";
			} else {
				print "$key\t$value_frequency->{$key}\t$percentage\n";
			}
			$td = $td == 1 ? 2 : 1;    #row stripes
		}
	}
	if ( $format eq 'html' ) {
		print "</tbody></table></div>";
	}
}

sub _get_value_frequency_hash {

	#if queryfield is left blank, a hash is created for all fields
	my ( $self, $qryref, $query_field ) = @_;
	my $qry = $$qryref;
	my $value_frequency;
	my $num_records;
	my $fields = $self->{'xmlHandler'}->get_field_list();
	my $view   = $self->{'system'}->{'view'};
	$" = ",$view.";
	my $field_string = "$view.@$fields";
	$qry =~ s/SELECT ($view\.\*|\*)/SELECT $field_string/;
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute(); };

	if ($@) {
		$logger->error("Can't execute $qry");
	}
	my %data = ();
	$sql->bind_columns( map { \$data{$_} } @$fields )
	  ;    #quicker binding hash to arrayref than to use hashref
	my $use_composites = $self->_use_composites;
	my $field_is_composite;
	if ( $use_composites && $query_field ) {
		$field_is_composite = $self->_is_composite_field($query_field);
	}
	my $composite_fields;
	if ($use_composites) {
		$composite_fields =
		  $self->{'datastore'}
		  ->run_list_query("SELECT id FROM composite_fields");
	}
	my $value;
	my @field_list;
	my $format = $self->{'cgi'}->param('format');
	if ($query_field) {
		push @field_list, $query_field;
	} else {
		@field_list = @$fields;
	}
		
	while ( $sql->fetchrow_arrayref() ) {
		foreach my $field (@field_list) {
			if (   $data{$field} eq '-999'
				|| $data{$field} eq '0001-01-01'
				|| $data{$field} eq '' )
			{
				$value = 'No value/unassigned';
			} else {
				$value = $data{$field};
				if ( $format eq 'text' ) {
					$value =~ s/&Delta;/deleted/g;
				}
			}
			$value_frequency->{$field}->{$value}++;
			

			
		}
		if ( $use_composites && !( !$field_is_composite && $query_field ) ) {
			foreach (@$composite_fields) {
				$value =
				  $self->{'datastore'}
				  ->get_composite_value( $data{'id'}, $_, \%data );
				if ( $format eq 'text' ) {
					$value =~ s/&Delta;/deleted/g;
				}
				$value_frequency->{$_}->{$value}++;
			}
		}
		$num_records++;
	}
	
	#Extended attributes
	my $sql_extended = $self->{'db'}->prepare("SELECT value FROM isolate_value_extended_attributes WHERE isolate_field=? AND attribute=? AND field_value=?");	
	foreach my $field (@field_list){
		my $extatt = $self->{'extended'}->{$field}; 
		if (ref $extatt eq 'ARRAY'){
			foreach my $extended_attribute (@$extatt){
				foreach (keys %{$value_frequency->{$field}}){
					eval {
						$sql_extended->execute($field,$extended_attribute,$_)
					};
					my ($value) = $sql_extended->fetchrow_array;
					$value = 'No value/unassigned' if $value eq '';
					$value_frequency->{"$field..$extended_attribute"}->{$value} += $value_frequency->{$field}->{$_};
				}
			}
		}
	}
	return $num_records, $value_frequency;
}
1;


