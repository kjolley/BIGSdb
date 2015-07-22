#FieldBreakdown.pm - TwoFieldBreakdown plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2015, University of Oxford
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
use BIGSdb::Page qw(BUTTON_CLASS);
use constant MAX_INSTANT_RUN => 10000;
use constant MAX_TABLE       => 2000;

sub get_attributes {
	my ($self) = @_;
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
		version     => '1.3.0',
		dbtype      => 'isolates',
		section     => 'breakdown,postquery',
		url         => "$self->{'config'}->{'doclink'}/data_analysis.html#two-field-breakdown",
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
	say q(<h1>Two field breakdown of dataset</h1>);
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
		$id_list =
		  $self->{'datastore'}
		  ->run_query( "SELECT id FROM $self->{'system'}->{'view'}", undef, { fetch => 'col_arrayref' } );
	}
	my $field1 = $q->param('field1');
	my $field2 = $q->param('field2');
	if ( $q->param('reverse') ) {
		( $field1, $field2 ) = $self->_reverse( $field1, $field2 );
	}
	my ( $attribute1, $attribute2 );
	if ( $field1 =~ /^e_(.*)\|\|(.*)$/x ) {
		$field1     = $1;
		$attribute1 = $2;
	}
	if ( $field2 =~ /^e_(.*)\|\|(.*)$/x ) {
		$field2     = $1;
		$attribute2 = $2;
	}
	if ( $field1 eq $field2 ) {
		say q(<div class="box" id="statusbad"><p>You must select two <em>different</em> fields.</p></div>);
		return;
	}
	return if ( $q->param('function') // '' ) ne 'breakdown';
	my $guid = $self->get_guid;

	#	my %prefs;
	my %options;
	foreach my $att (qw (threeD transparent)) {
		try {
			$options{$att} =
			  $self->{'prefstore'}->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'TwoFieldBreakdown', $att );
			$options{$att} = $options{$att} eq 'true' ? 1 : 0;
		}
		catch BIGSdb::DatabaseNoRecordException with {
			$options{$att} = 0;
		};
	}
	if ( @$id_list > MAX_INSTANT_RUN && $self->{'config'}->{'jobs_db'} ) {
		my $att       = $self->get_attributes;
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		my $params    = $q->Vars;
		delete $params->{$_} foreach qw(field1 field2);
		$params->{'field1'}      = $field1;
		$params->{'field2'}      = $field2;
		$params->{'attribute1'}  = $attribute1;
		$params->{'attribute2'}  = $attribute2;
		$params->{'threeD'}      = $options{'threeD'};
		$params->{'transparent'} = $options{'transparent'};
		my $job_id = $self->{'jobManager'}->add_job(
			{
				dbase_config => $self->{'instance'},
				ip_address   => $q->remote_host,
				module       => $att->{'module'},
				priority     => $att->{'priority'},
				parameters   => $params,
				username     => $self->{'username'},
				email        => $user_info->{'email'},
				isolates     => $id_list
			}
		);
		say q(<div class="box" id="resultstable">);
		say q(<p>This job has been submitted to the job queue.</p>);
		say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=job&amp;id=$job_id">Follow the progress of this job and view the output.</a></p></div>);
		return;
	}
	$self->_breakdown(
		{
			id_list     => $id_list,
			field1      => $field1,
			field2      => $field2,
			attribute1  => $attribute1,
			attribute2  => $attribute2,
			threeD      => $options{'threeD'},
			transparent => $options{'transparent'}
		}
	);
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	my $isolate_ids = $self->{'jobManager'}->get_job_isolates($job_id);
	$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => -1 } );    #indeterminate length of time
	my $continue = 1;
	my $freq_hashes;
	try {
		$freq_hashes = $self->_get_value_frequency_hashes( $params->{'field1'}, $params->{'field2'}, $isolate_ids );
	}
	catch BIGSdb::DatabaseConnectionException with {
		$continue = 0;
	};
	throw BIGSdb::PluginException( 'The database for the scheme of one of your selected '
		  . 'fields is inaccessible. This may be a configuration problem.' )
	  if !$continue;
	my ( $grand_total, $data, $clean_field1, $clean_field2, $print_field1, $print_field2 ) =
	  @{$freq_hashes}{qw(grand_total datahash cleanfield1 cleanfield2 printfield1 printfield2)};
	$self->_recalculate_for_attributes(
		{
			field1       => $params->{'field1'},
			attribute1   => $params->{'attribute1'},
			field2       => $params->{'field2'},
			attribute2   => $params->{'attribute2'},
			datahash_ref => $data
		}
	);
	my ( $field1_total, $field2_total ) = $self->_calculate_field_totals($data);
	$print_field1 = $params->{'attribute1'} if $params->{'attribute1'};
	$print_field2 = $params->{'attribute2'} if $params->{'attribute2'};
	my $field2values = $self->_get_field2_values($data);
	my $field1_count = keys %$data;
	my $field2_count = @$field2values;
	my $disable_html_table;
	$disable_html_table = 1 if $field1_count > MAX_TABLE || $field2_count > MAX_TABLE;
	my ( $display, $calcpc );

	if ( $params->{'display'} ) {
		$display = $params->{'display'};
	} else {
		$display = 'values only';
	}
	if ( $params->{'calcpc'} ) {
		$calcpc = $params->{'calcpc'};
	} else {
		$calcpc = 'dataset';
	}
	my $out_file    = "$self->{'config'}->{'tmp_dir'}/$job_id.txt";
	my $html_field1 = $self->{'datastore'}->is_locus($print_field1) ? $self->clean_locus($print_field1) : $print_field1;
	my $html_field2 = $self->{'datastore'}->is_locus($print_field2) ? $self->clean_locus($print_field2) : $print_field2;
	my $text_field1 =
	    $self->{'datastore'}->is_locus($print_field1)
	  ? $self->clean_locus( $print_field1, { text_output => 1 } )
	  : $print_field1;
	my $text_field2 =
	    $self->{'datastore'}->is_locus($print_field2)
	  ? $self->clean_locus( $print_field2, { text_output => 1 } )
	  : $print_field2;
	my $html_buffer;
	if ( !$disable_html_table ) {
		$html_buffer .= qq(<h2>Breakdown of $html_field1 by $html_field2:</h2>);
		$html_buffer .= qq(<p>Selected options: Display $display. );
		$html_buffer .= qq(Calculate percentages by $calcpc.) if $display ne 'values only';
		$html_buffer .= q(</p>);
	}
	open( my $fh, '>:encoding(utf8)', $out_file )
	  or $logger->error("Can't open temp file $out_file for writing");
	say $fh qq(Breakdown of $text_field1 by $text_field2:);
	print $fh qq(Selected options: Display $display. );
	print $fh qq(Calculate percentages by $calcpc.) if $display ne 'values only';
	say $fh qq(\n);
	my $args = {
		data          => $data,
		html_field1   => $html_field1,
		html_field2   => $html_field2,
		text_field1   => $text_field1,
		text_field2   => $text_field2,
		field1_total  => $field1_total,
		field2_total  => $field2_total,
		grand_total   => $grand_total,
		prefix        => $job_id,
		field1        => $params->{'field1'},
		field2        => $params->{'field2'},
		field2_values => $field2values,
		calcpc        => $params->{'calcpc'},
		display       => $params->{'display'}
	};
	my ( $html_table, $text_table ) = $self->_generate_tables($args);
	$html_buffer .= $$html_table;
	say $fh $$text_table;
	close $fh;
	$self->{'jobManager'}
	  ->update_job_status( $job_id, { message_html => qq(<div class="scrollable">$html_buffer</div>) } )
	  if !$disable_html_table;
	$self->{'jobManager'}
	  ->update_job_output( $job_id, { filename => "$job_id.txt", description => '01_Tab-delimited text' } );
	my $excel =
	  BIGSdb::Utils::text2excel( $out_file,
		{ worksheet => 'Breakdown', tmp_dir => $self->{'config'}->{'secure_tmp_dir'}, no_header => 1 } );
	$self->{'jobManager'}
	  ->update_job_output( $job_id, { filename => "$job_id.xlsx", description => '02_Excel format' } )
	  if -e $excel;
	$args->{'no_print'} = 1;
	$args->{$_} = $params->{$_} foreach qw(threeD transparent);
	my $charts = $self->_print_charts($args);
	my $i      = 3;

	foreach my $chart (@$charts) {
		$self->{'jobManager'}->update_job_output( $job_id,
			{ filename => $chart->{'filename'}, description => "0${i}_$chart->{'title'}" } );
		$i++;
	}
	return;
}

sub _print_interface {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="queryform">);
	say q(<div class="scrollable">);
	say q(<p>Here you can create a table breaking down one field by another, )
	  . q(e.g. breakdown of serogroup by year.</p>);
	say $q->startform;
	$q->param( function => 'breakdown' );
	say $q->hidden($_) foreach qw (db page name function query_file list_file datatype);
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
	say q(<fieldset style="float:left"><legend>Select fields</legend><ul><li>);
	say q(<label for="field1">Field 1:</label>);
	say $q->popup_menu( -name => 'field1', -id => 'field1', -values => $headings, -labels => $labels );
	say q(</li><li>);
	say q(<label for="field2">Field 2:</label>);
	say $q->popup_menu( -name => 'field2', -id => 'field2', -values => $headings, -labels => $labels );
	say q(</li></ul></fieldset>);
	say q(<fieldset style="float:left"><legend>Display</legend>);
	say $q->radio_group(
		-name      => 'display',
		-values    => [ 'values only', 'values and percentages', 'percentages only' ],
		-default   => 'values only',
		-linebreak => 'true'
	);
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Calculate percentages by</legend>);
	say $q->radio_group(
		-name      => 'calcpc',
		-values    => [ 'dataset', 'row', 'column' ],
		-default   => 'dataset',
		-linebreak => 'true'
	);
	say q(</fieldset>);
	$self->print_action_fieldset( { name => 'TwoFieldBreakdown' } );
	say $q->endform;
	say q(</div></div>);
	return;
}

sub _reverse {
	my ( $self, $field1, $field2 ) = @_;
	my $q = $self->{'cgi'};
	$field1 = $q->param('field2');
	$field2 = $q->param('field1');
	$q->param( field1 => $field1 );
	$q->param( field2 => $field2 );
	return ( $field1, $field2 );
}

sub _print_controls {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say $q->startform;
	say q(<fieldset style="float:left"><legend>Axes</legend>);
	say $q->hidden($_) foreach qw (db page name function query_file field1 field2 display calcpc list_file datatype);
	say $q->submit(
		-name  => 'reverse',
		-value => 'Reverse',
		-class => 'submitbutton ui-button ui-widget ui-state-default ui-corner-all'
	);
	say q(</fieldset>);
	say $q->endform;
	say $q->startform;
	say q(<fieldset style="float:left"><legend>Show</legend>);
	say $q->hidden($_) foreach qw (db page name function query_file field1 field2 display calcpc list_file datatype);
	my %display_toggle = (
		'values only'            => 'Values and percentages',
		'values and percentages' => 'Percentages only',
		'percentages only'       => 'Values only'
	);
	say $q->submit( -name => 'toggledisplay', -label => $display_toggle{ $q->param('display') },
		-class => BUTTON_CLASS );
	say q(</fieldset>);
	say $q->endform;

	if ( $q->param('display') ne 'values only' ) {
		say $q->startform;
		say q(<fieldset style="float:left"><legend>Calculate percentages</legend>);
		say $q->hidden($_)
		  foreach qw (db page name function query_file field1 field2 display calcpc list_file datatype);
		my %pc_toggle = ( dataset => 'row', row => 'column', column => 'dataset' );
		say q(<span style="text-align:center; display:block">);
		say $q->submit(
			-name  => 'togglepc',
			-label => ( 'By ' . $pc_toggle{ $q->param('calcpc') } ),
			-class => BUTTON_CLASS,
		);
		say q(</span></fieldset>);
		say $q->endform;
	}
	return;
}

sub _breakdown {
	my ( $self, $args ) = @_;
	my ( $id_list, $field1, $field2, $attribute1, $attribute2, $threeD, $transparent ) =
	  @{$args}{qw(id_list field1 field2 attribute1 attribute2 threeD transparent)};
	my $q = $self->{'cgi'};
	my $freq_hashes;
	try {
		$freq_hashes = $self->_get_value_frequency_hashes( $field1, $field2, $id_list );
	}
	catch BIGSdb::DatabaseConnectionException with {
		say q(<div class="box" id="statusbad"><p>The database for the scheme of one of your selected )
		  . q(fields is inaccessible. This may be a configuration problem.</p></div>);
		return;
	};
	my ( $grand_total, $data, $clean_field1, $clean_field2, $print_field1, $print_field2 ) =
	  @{$freq_hashes}{qw(grand_total datahash cleanfield1 cleanfield2 printfield1 printfield2)};
	$self->_recalculate_for_attributes(
		{
			field1       => $field1,
			attribute1   => $attribute1,
			field2       => $field2,
			attribute2   => $attribute2,
			datahash_ref => $data
		}
	);
	my ( $field1_total, $field2_total ) = $self->_calculate_field_totals($data);
	$print_field1 = $attribute1 if $attribute1;
	$print_field2 = $attribute2 if $attribute2;
	my $field2values = $self->_get_field2_values($data);
	my $field1_count = keys %$data;
	my $field2_count = @$field2values;
	my $disable_html_table;

	if ( $field1_count > MAX_TABLE || $field2_count > MAX_TABLE ) {
		my $max_table = MAX_TABLE;
		say qq(<div class="box" id="statusbad"><p>One of your selected fields has more than $max_table values - )
		  . q(table rendering has been disabled to prevent your browser locking up.</p>);
		say qq(<p>$print_field1: $field1_count<br />);
		say qq($print_field2: $field2_count</p>);
		say q(</div>);
		$disable_html_table = 1;
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
	my ( $display, $calcpc );
	if ( $q->param('display') ) {
		$display = $q->param('display');
	} else {
		$display = 'values only';
	}
	if ( $q->param('togglepc') ) {
		if ( $q->param('togglepc') eq 'By row' ) {
			$q->param( calcpc => 'row' );
		} elsif ( $q->param('togglepc') eq 'By column' ) {
			$q->param( calcpc => 'column' );
		} elsif ( $q->param('togglepc') eq 'By dataset' ) {
			$q->param( calcpc => 'dataset' );
		}
	}
	if ( $q->param('calcpc') ) {
		$calcpc = $q->param('calcpc');
	} else {
		$calcpc = 'dataset';
	}
	my $temp1       = BIGSdb::Utils::get_random();
	my $out_file    = "$self->{'config'}->{'tmp_dir'}/$temp1.txt";
	my $html_field1 = $self->{'datastore'}->is_locus($print_field1) ? $self->clean_locus($print_field1) : $print_field1;
	my $html_field2 = $self->{'datastore'}->is_locus($print_field2) ? $self->clean_locus($print_field2) : $print_field2;
	my $text_field1 =
	    $self->{'datastore'}->is_locus($print_field1)
	  ? $self->clean_locus( $print_field1, { text_output => 1 } )
	  : $print_field1;
	my $text_field2 =
	    $self->{'datastore'}->is_locus($print_field2)
	  ? $self->clean_locus( $print_field2, { text_output => 1 } )
	  : $print_field2;
	if ( !$disable_html_table ) {
		say q(<div class="box" id="resultstable">);
		say qq(<h2>Breakdown of $html_field1 by $html_field2:</h2>);
		say qq(<p>Selected options: Display $display. );
		say qq(Calculate percentages by $calcpc.) if $display ne 'values only';
		say q(</p>);
	}
	open( my $fh, '>:encoding(utf8)', $out_file )
	  or $logger->error("Can't open temp file $out_file for writing");
	say $fh qq(Breakdown of $text_field1 by $text_field2:);
	print $fh qq(Selected options: Display $display. );
	print $fh qq(Calculate percentages by $calcpc.) if $display ne 'values only';
	say $fh qq(\n);
	$self->_print_controls if !$disable_html_table;
	$args = {
		data          => $data,
		html_field1   => $html_field1,
		html_field2   => $html_field2,
		text_field1   => $text_field1,
		text_field2   => $text_field2,
		field1_total  => $field1_total,
		field2_total  => $field2_total,
		grand_total   => $grand_total,
		prefix        => $temp1,
		field1        => $field1,
		field2        => $field2,
		field2_values => $field2values,
		calcpc        => $q->param('calcpc'),
		display       => $q->param('display')
	};
	my ( $html_table, $text_table ) = $self->_generate_tables($args);
	say $fh $$text_table;
	close $fh;
	say qq(<div class="scrollable" style="clear:both">$$html_table</div></div>) if !$disable_html_table;
	my $excel =
	  BIGSdb::Utils::text2excel( $out_file,
		{ worksheet => 'Breakdown', tmp_dir => $self->{'config'}->{'secure_tmp_dir'}, no_header => 1 } );
	say qq(<div class="box" id="resultsfooter"><p>Download: <a href="/tmp/$temp1.txt">Tab-delimited text</a>);
	say qq( | <a href="/tmp/$temp1.xlsx">Excel format</a>) if $excel;
	say q(</p></div>);
	$args->{'threeD'}      = $threeD;
	$args->{'transparent'} = $transparent;
	$self->_print_charts($args);
	return;
}

sub _calculate_field_totals {
	my ( $self, $data ) = @_;
	my $field1_total = {};
	my $field2_total = {};
	foreach my $value1 ( keys %$data ) {
		foreach my $value2 ( keys %{ $data->{$value1} } ) {
			$field1_total->{$value1} += $data->{$value1}->{$value2};
			$field2_total->{$value2} += $data->{$value1}->{$value2};
		}
	}
	return ( $field1_total, $field2_total );
}

sub _get_field2_values {
	my ( $self, $data ) = @_;
	my @field2_values;
	for my $field1_value ( sort keys %$data ) {
		for my $field2_value ( sort keys %{ $data->{$field1_value} } ) {
			push @field2_values, $field2_value;
		}
	}
	@field2_values = uniq @field2_values;
	{
		no warnings;
		@field2_values = sort { $a <=> $b || $a cmp $b } @field2_values;
	}
	return \@field2_values;
}

sub _generate_tables {
	my ( $self, $args ) = @_;
	my (
		$data,         $html_field1,  $html_field2, $text_field1, $text_field2,
		$field1_total, $field2_total, $grand_total, $calcpc,      $display
	  )
	  = @{$args}
	  {qw(data html_field1 html_field2 text_field1 text_field2 field1_total field2_total grand_total calcpc display)};
	my $field2values = $self->_get_field2_values($data);
	my $field2_count = @$field2values;
	my ( $text_buffer, $html_buffer );
	$html_buffer .= q(<table class="tablesorter" id="sortTable"><thead>);
	my $field2_cols = $field2_count + 1;
	$html_buffer .= qq(<tr><td></td><td colspan="$field2_cols" class="header">$html_field2</td></tr>);
	local $" = q(</th><th class="{sorter:'digit'}">);
	$html_buffer .= qq(<tr><th>$html_field1</th><th class="{sorter:'digit'}">@$field2values</th>)
	  . q(<th class="{sorter:'digit'}">Total</th></tr></thead><tbody>);
	$text_buffer .= qq($text_field1\t$text_field2\n);
	local $" = qq(\t);
	$text_buffer .= qq(\t@$field2values\tTotal\n);
	my $td = 1;
	{
		no warnings 'numeric';    #might complain about numeric comparison with non-numeric data
		for my $field1value ( sort { $a <=> $b || $a cmp $b } keys %$data ) {
			my $total = 0;
			$html_buffer .= qq(<tr class="td$td"><td>$field1value</td>);
			$text_buffer .= $field1value;
			foreach my $field2value (@$field2values) {
				my $value = $data->{$field1value}->{$field2value} || 0;
				my $percentage;
				if ( $calcpc eq 'row' ) {
					$percentage = BIGSdb::Utils::decimal_place( ( $value / $field1_total->{$field1value} ) * 100, 1 );
				} elsif ( $calcpc eq 'column' ) {
					$percentage = BIGSdb::Utils::decimal_place( ( $value / $field2_total->{$field2value} ) * 100, 1 );
				} else {
					$percentage = BIGSdb::Utils::decimal_place( ( $value / $grand_total ) * 100, 1 );
				}
				$total += $value;
				if ( !$value ) {
					$html_buffer .= q(<td></td>);
					$text_buffer .= qq(\t);
				} else {
					if ( $display eq 'values and percentages' ) {
						$html_buffer .= qq(<td>$value ($percentage%)</td>);
						$text_buffer .= qq(\t$value ($percentage%));
					} elsif ( $display eq 'percentages only' ) {
						$html_buffer .= qq(<td>$percentage</td>);
						$text_buffer .= qq(\t$percentage);
					} else {
						$html_buffer .= qq(<td>$value</td>);
						$text_buffer .= qq(\t$value);
					}
				}
			}
			my $percentage;
			if ( $calcpc eq 'row' ) {
				$percentage = 100;
			} else {
				$percentage = BIGSdb::Utils::decimal_place( ( $field1_total->{$field1value} / $grand_total ) * 100, 1 );
			}
			if ( $display eq 'values and percentages' ) {
				$html_buffer .= qq(<td>$total ($percentage%)</td></tr>);
				$text_buffer .= qq(\t$total ($percentage%)\n);
			} elsif ( $display eq 'percentages only' ) {
				$html_buffer .= qq(<td>$percentage</td></tr>);
				$text_buffer .= qq(\t$percentage\n);
			} else {
				$html_buffer .= qq(<td>$total</td></tr>);
				$text_buffer .= qq(\t$total\n);
			}
			$td = $td == 1 ? 2 : 1;    #row stripes
		}
	};
	$html_buffer .= q(</tbody><tbody><tr class="total"><td>Total</td>);
	$text_buffer .= q(Total);
	foreach my $field2value (@$field2values) {
		my $percentage;
		if ( $calcpc eq 'column' ) {
			$percentage = 100;
		} else {
			$percentage = BIGSdb::Utils::decimal_place( ( $field2_total->{$field2value} / $grand_total ) * 100, 1 );
		}
		if ( $display eq 'values and percentages' ) {
			$html_buffer .= qq(<td>$field2_total->{$field2value} ($percentage%)</td>);
			$text_buffer .= qq(\t$field2_total->{$field2value} ($percentage%));
		} elsif ( $display eq 'percentages only' ) {
			$html_buffer .= qq(<td>$percentage</td>);
			$text_buffer .= qq(\t$percentage);
		} else {
			$html_buffer .= qq(<td>$field2_total->{$field2value}</td>);
			$text_buffer .= qq(\t$field2_total->{$field2value});
		}
	}
	if ( $display eq 'values and percentages' ) {
		$html_buffer .= qq(<td>$grand_total (100%)</td></tr>);
		$text_buffer .= qq(\t$grand_total (100%)\n);
	} elsif ( $display eq 'percentages only' ) {
		$html_buffer .= q(<td>100</td></tr>);
		$text_buffer .= qq(\t100\n);
	} else {
		$html_buffer .= qq(<td>$grand_total</td></tr>);
		$text_buffer .= qq(\t$grand_total\n);
	}
	$html_buffer .= q(</tbody></table>);
	return ( \$html_buffer, \$text_buffer );
}

sub _print_charts {
	my ( $self, $args ) = @_;
	my (
		$prefix,      $data,        $field1_total, $field2_values, $field1, $field2,
		$text_field1, $text_field2, $no_print,     $threeD,        $transparent
	  )
	  = @{$args}
	  {qw(prefix data field1_total field2_values field1 field2 text_field1 text_field2 no_print threeD transparent)};
	my $filename_info = [];
	if ( $self->{'config'}->{'chartdirector'} && keys %$data < 31 && @$field2_values < 31 ) {
		if ( !$no_print ) {
			say q(<div class="box" id="chart"><h2>Charts</h2>);
			say q(<p>Click to enlarge.</p>);
		}

		#		my $guid = $self->get_guid;
		#		my %prefs;
		#		foreach my $att (qw (threeD transparent)) {
		#			try {
		#				$prefs{$att} =
		#				  $self->{'prefstore'}
		#				  ->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'TwoFieldBreakdown', $att );
		#				$prefs{$att} = $prefs{$att} eq 'true' ? 1 : 0;
		#			}
		#			catch BIGSdb::DatabaseNoRecordException with {
		#				$prefs{$att} = 0;
		#			};
		#		}
		for my $i ( 0 .. 1 ) {
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
			$layer->set3D if $threeD;
			{
				no warnings 'once';
				$chart->setColors($perlchartdir::transparentPalette) if $transparent;
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
				$chart->addTitle( 'Values', 'arial.ttf', 14 );
				my $filename = "${prefix}_${field1}_$field2.png";
				if ( $filename =~ /(BIGSdb.*\.png)/x ) {
					$filename = $1;    #untaint
				}
				$chart->makeChart("$self->{'config'}->{'tmp_dir'}/$filename");
				if ( !$no_print ) {
					say q(<fieldset><legend>Values</legend>);
					say qq(<a href="/tmp/$filename" data-rel="lightbox-1" class="lightbox" )
					  . qq(title="$text_field1 vs $text_field2"><img src="/tmp/$filename" )
					  . qq(alt="$text_field1 vs $text_field2" style="width:200px;border:1px dashed black" />)
					  . q(</a></fieldset>);
				}
				push @$filename_info, { filename => $filename, title => "$text_field1 vs $text_field2 (values)" };
			} else {
				$chart->addTitle( 'Percentages', 'arial.ttf', 14 );
				my $filename = "${prefix}_${field1}_${field2}_pc.png";
				if ( $filename =~ /(BIGSdb.*\.png)/x ) {
					$filename = $1;    #untaint
				}
				$chart->makeChart("$self->{'config'}->{'tmp_dir'}/$filename");
				if ( !$no_print ) {
					say q(<fieldset><legend>Percentages</legend>);
					say qq(<a href="/tmp/$filename" data-rel="lightbox-1" class="lightbox" )
					  . qq(title="$text_field1 vs $text_field2 percentage chart"><img src="/tmp/$filename" )
					  . qq(alt="$text_field1 vs $text_field2 percentage chart" )
					  . q(style="width:200px;border:1px dashed black" /></a></fieldset>);
				}
				push @$filename_info, { filename => $filename, title => "$text_field1 vs $text_field2 (percentages)" };
			}
		}
		say q(</div>) if !$no_print;
	}
	return $filename_info;
}

sub _get_value_frequency_hashes {
	my ( $self, $field1, $field2, $id_list ) = @_;
	my $total_isolates = $self->{'datastore'}->run_query("SELECT COUNT(id) FROM $self->{'system'}->{'view'}");
	my $datahash;
	my $grand_total = 0;
	my %field_type;
	my %clean;
	my %print;
	( $clean{$field1} = $field1 ) =~ s/^[f|l]_//x;
	( $clean{$field2} = $field2 ) =~ s/^[f|l]_//x;
	my %scheme_id;

	foreach my $field ( $field1, $field2 ) {
		if ( $field =~ /^la_(.+)\|\|/x || $field =~ /^cn_(.+)/x ) {
			$clean{$field} = $1;
		}
		if ( $self->{'xmlHandler'}->is_field( $clean{$field} ) ) {
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			$field_type{$field} = defined $metaset ? 'metafield' : 'field';
			$metafield =~ tr/_/ / if defined $metafield;
			$print{$field} = $metafield // $clean{$field};
		} elsif ( $self->{'datastore'}->is_locus( $clean{$field} ) ) {
			$field_type{$field} = 'locus';
			$print{$field}      = $clean{$field};
		} else {
			if ( $field =~ /^s_(\d+)_(.*)/x ) {
				my $scheme_id    = $1;
				my $scheme_field = $2;
				if ( $self->{'datastore'}->is_scheme_field( $scheme_id, $scheme_field ) ) {
					$clean{$field}      = $scheme_field;
					$print{$field}      = $clean{$field};
					$field_type{$field} = 'scheme_field';
					$scheme_id{$field}  = $scheme_id;
					my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
					$print{$field} .= " ($scheme_info->{'description'})";
				}
			}
		}
	}
	foreach my $id ( uniq @$id_list ) {
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
				$grand_total++;
			}
		}
	}
	return (
		{
			grand_total => $grand_total,
			datahash    => $datahash,
			cleanfield1 => $clean{$field1},
			cleanfield2 => $clean{$field2},
			printfield1 => $print{$field1},
			printfield2 => $print{$field2}
		}
	);
}

#If number of records is >=50% of total records, query database and fetch all rows,
#otherwise call for each record in turn.
#Values are arrayref in an array representing field1 and field2.
sub _get_values {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $fields, $clean_fields, $field_type, $scheme_id, $options ) =
	  @{$args}{qw(isolate_id fields clean_fields field_type scheme_id options)};
	$options = {} if ref $options ne 'HASH';
	my @values;
	foreach my $field (@$fields) {
		my $values;
		my $sub_args = {
			isolate_id   => $isolate_id,
			field        => $field,
			clean_fields => $clean_fields,
			scheme_id    => $scheme_id,
			options      => $options
		};
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
			$self->{'cache'}->{$field} =
			  $self->{'datastore'}->run_query( "SELECT id,$clean_fields->{$field} FROM $self->{'system'}->{'view'}",
				undef, { fetch => 'all_hashref', key => 'id' } );
		}
		$value = $self->{'cache'}->{$field}->{$isolate_id}->{ $clean_fields->{$field} };
	} else {
		$value =
		  $self->{'datastore'}->run_query( "SELECT $clean_fields->{$field} FROM $self->{'system'}->{'view'} WHERE id=?",
			$isolate_id, { cache => "TwoFieldBreakdown::get_field_value::$field" } );
	}
	return $value;
}

sub _get_locus_values {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $field, $clean_fields, $options ) = @{$args}{qw(isolate_id field clean_fields options)};
	my $values = [];
	if ( $options->{'fetchall'} ) {
		if ( !$self->{'cache'}->{$field} ) {
			my $data = $self->{'datastore'}->run_query(
				q(SELECT isolate_id, allele_id FROM allele_designations WHERE locus=? AND status != 'ignore'),
				$clean_fields->{$field},
				{ fetch => 'all_arrayref' }
			);
			foreach (@$data) {
				push @{ $self->{'cache'}->{$field}->{ $_->[0] } }, $_->[1];
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
			$self->{'cache'}->{$field} = $self->{'datastore'}->run_query(
				"SELECT isolate_id,$metafield FROM meta_$metaset WHERE isolate_id IN "
				  . "(SELECT id FROM $self->{'system'}->{'view'})",
				undef,
				{ fetch => 'all_hashref', key => 'isolate_id' }
			);
		}
		$value = $self->{'cache'}->{$field}->{$isolate_id}->{$metafield};
	} else {
		$value = $self->{'datastore'}->run_query( "SELECT $metafield FROM meta_$metaset WHERE isolate_id=?",
			$isolate_id, { cache => "TwoFieldBreakdown::get_metafield_value::$field" } );
	}
	return $value;
}

sub _recalculate_for_attributes {
	my ( $self, $args ) = @_;
	my ( $field1, $attribute1, $field2, $attribute2, $datahash_ref ) =
	  @{$args}{qw( field1 attribute1 field2 attribute2 datahash_ref  )};
	my @field     = ( $field1,     $field2 );
	my @attribute = ( $attribute1, $attribute2 );
	my $new_hash;
	return if !$attribute[0] && !$attribute[1];
	my $lookup;
	foreach my $att_num ( 0 .. 1 ) {
		next if !defined $attribute[$att_num];
		my $data = $self->{'datastore'}->run_query(
			'SELECT field_value,value FROM isolate_value_extended_attributes WHERE (isolate_field,attribute)=(?,?)',
			[ $field[$att_num], $attribute[$att_num] ],
			{ fetch => 'all_arrayref' }
		);
		foreach (@$data) {
			my ( $field_value, $attribute_value ) = @$_;
			$lookup->[$att_num]->{$field_value} = $attribute_value;
		}
	}
	foreach my $value1 ( keys %$datahash_ref ) {
		foreach my $value2 ( keys %{ $datahash_ref->{$value1} } ) {
			$lookup->[0]->{$value1} = 'No value'
			  if !defined $lookup->[0]->{$value1} || $lookup->[0]->{$value1} eq '';
			$lookup->[1]->{$value2} = 'No value'
			  if !defined $lookup->[1]->{$value2} || $lookup->[1]->{$value2} eq '';
			if ( $attribute[0] && $attribute[1] ) {
				$new_hash->{ $lookup->[0]->{$value1} }->{ $lookup->[1]->{$value2} } +=
				  $datahash_ref->{$value1}->{$value2};
			} elsif ( $attribute[0] ) {
				$new_hash->{ $lookup->[0]->{$value1} }->{$value2} += $datahash_ref->{$value1}->{$value2};
			} elsif ( $attribute[1] ) {
				$new_hash->{$value1}->{ $lookup->[1]->{$value2} } += $datahash_ref->{$value1}->{$value2};
			}
		}
	}
	undef %$datahash_ref;
	%$datahash_ref = %$new_hash;
	return;
}
1;
