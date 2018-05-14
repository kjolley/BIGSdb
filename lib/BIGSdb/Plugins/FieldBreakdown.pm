#FieldBreakdown.pm - FieldBreakdown plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2018, University of Oxford
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
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);

sub get_attributes {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $field = $q->param('field') // 'field';
	my %att = (
		name          => 'Field Breakdown',
		author        => 'Keith Jolley',
		affiliation   => 'University of Oxford, UK',
		email         => 'keith.jolley@zoo.ox.ac.uk',
		description   => 'Breakdown of query results by field',
		category      => 'Breakdown',
		buttontext    => 'Fields',
		menutext      => 'Single field',
		module        => 'FieldBreakdown',
		version       => '1.2.3',
		dbtype        => 'isolates',
		section       => 'breakdown,postquery',
		url           => "$self->{'config'}->{'doclink'}/data_analysis.html#field-breakdown",
		input         => 'query',
		requires      => 'chartdirector',
		text_filename => "$field\_breakdown.txt",
		xlsx_filename => "$field\_breakdown.xlsx",
		order         => 10
	);
	return \%att;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub get_option_list {
	my @list = (
		{ name => 'style',  description => 'Pie chart style',      optlist => 'pie;doughnut', default => 'doughnut' },
		{ name => 'small',  description => 'Display small charts', default => 1 },
		{ name => 'threeD', description => 'Enable 3D effect',     default => 1 },
		{ name => 'transparent', description => 'Enable transparent palette', default => 1 },
		{
			name        => 'breakdown_composites',
			description => 'Breakdown composite fields (will slow down display of statistics for large datasets)',
			default     => 0
		}
	);
	return \@list;
}

sub get_plugin_javascript {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $list_file  = $q->param('list_file');
	my $datatype   = $q->param('datatype');
	my $query_clause    = defined $query_file ? "&amp;query_file=$query_file" : '';
	my $listfile_clause = defined $list_file  ? "&amp;list_file=$list_file"   : '';
	my $datatype_clause = defined $datatype   ? "&amp;datatype=$datatype"     : '';
	my $script_name     = $self->{'system'}->{'script_name'};
	my $js              = << "END";
\$(function () {
	\$("#imagegallery a").click(function(event){
		event.preventDefault();
		var image = \$(this).attr("href");
		\$("img#placeholder").attr("src",image);
		var field = \$(this).attr("id");
		var display = field;
		display = display.replace(/^meta_[^:]+:/, "");
		display = display.replace(/_/g," ");
		display = display.replace(/^.*\\.\\./, "");
		\$("#field").empty();
		\$("#field").append(display);
		\$("#links").empty();
		var base_link = "$script_name?db=$self->{'instance'}&amp;page=plugin&amp;name=FieldBreakdown&amp;"
		 + "function=summary_table$query_clause$listfile_clause$datatype_clause&amp;field=" + field;
		\$("#links").append("Select: <a href='" + base_link + "&amp;format=html'>Table</a> | "
		  + "<a href='" + base_link + "&amp;format=text'>Tab-delimited text</a> | "
		  + "<a href='" + base_link + "&amp;format=xlsx'>Excel format</a>");
	});		
});
END
	return $js;
}

sub _use_composites {
	my ($self) = @_;
	my $use;
	my $guid = $self->get_guid;
	try {
		$use =
		  $self->{'prefstore'}
		  ->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'FieldBreakdown', 'breakdown_composites' );
		$use = $use eq 'true' ? 1 : 0;
	}
	catch BIGSdb::DatabaseNoRecordException with {
		$use = 0;
	};
	return $use;
}

sub run {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $format     = $q->param('format');
	local $| = 1;
	if ( !( defined $q->param('function') && $q->param('function') eq 'summary_table' ) ) {
		say q(<h1>Field breakdown of dataset</h1>);
		say q(<div class="hideonload"><p><b>Please wait for charts to be generated ...</b></p>)
		  . q(<p><span class="main_icon fas fa-sync-alt fa-spin fa-4x"></span></p></div>);
	}
	if ( $ENV{'MOD_PERL'} ) {
		$self->{'mod_perl_request'}->rflush;
		return if $self->{'mod_perl_request'}->connection->aborted;
	}
	my %prefs;
	$prefs{'breakdown_composites'} = $self->_use_composites;
	my $qry_ref = $self->get_query($query_file);
	return if ref $qry_ref ne 'SCALAR';
	my $qry = $$qry_ref;
	$qry =~ s/ORDER\ BY.*$//gx;
	return if !$self->create_temp_tables($qry_ref);
	$self->{'extended'} = $self->get_extended_attributes;

	if ( ( $q->param('function') // '' ) eq 'summary_table' ) {
		$self->_summary_table($qry);
		return;
	}
	$self->{'system'}->{'noshow'} //= q();
	my %noshow = map { $_ => 1 } split /,/x, $self->{'system'}->{'noshow'};
	$noshow{$_} = 1 foreach qw (id isolate datestamp date_entered curator sender comments);
	my $temp = BIGSdb::Utils::get_random();
	my ( $num_records, $value_frequency ) = $self->_get_value_frequency_hash( \$qry );
	my $first = 1;
	my ( $src, $name, $title );
	say q(<div class="box" id="resultsheader"><div id="imagegallery"><h2>Fields</h2><p>Select: );
	my ( %composites, %composite_display_pos );

	if ( $prefs{'breakdown_composites'} ) {
		my $comp_data = $self->{'datastore'}->run_query( 'SELECT id,position_after FROM composite_fields',
			undef, { fetch => 'all_arrayref', slice => {} } );
		foreach my $comp (@$comp_data) {
			$composite_display_pos{ $comp->{'id'} }  = $comp->{'position_after'};
			$composites{ $comp->{'position_after'} } = 1;
		}
	}
	my $display_name;
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
	my @expanded_list;
	foreach my $field (@$field_list) {
		push @expanded_list, $field;
		if ( ref $self->{'extended'}->{$field} eq 'ARRAY' ) {
			foreach my $attribute ( @{ $self->{'extended'}->{$field} } ) {
				push @expanded_list, "$field\.\.$attribute";
			}
		}
	}
	my $field_count = 0;
	foreach my $field (@expanded_list) {
		if ( !$noshow{$field} ) {
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			my $display = $metafield // $field;
			$display =~ tr/_/ /;
			$display =~ s/^.*\.\.//x;    #Only show extended attribute name and not parent field
			my $display_field = $field;
			my $num_values    = keys %{ $value_frequency->{$field} };
			my $plural        = $num_values != 1 ? 's' : '';
			$title = "$display - $num_values value$plural";
			print q( | ) if !$first;
			say qq(<a href="/tmp/$temp\_$field.png" id="$display_field" title="$title">$display</a>);
			$self->_create_chartdirector_chart( $field, $num_values, $value_frequency->{$field}, $temp, $query_file );

			if ($first) {
				$src          = "/tmp/$temp\_$field.png";
				$display_name = $display;
				$name         = $field;
				undef $first;
			}
			$field_count++;
			if ( $ENV{'MOD_PERL'} ) {
				$self->{'mod_perl_request'}->rflush;
			}
		}
		if ( $prefs{'breakdown_composites'} && $composites{$field} ) {
			print q( | ) if !$first;
			foreach my $field ( keys %composite_display_pos ) {
				next if $composite_display_pos{$field} ne $field;
				my $display = $field;
				$display =~ tr/_/ /;
				$title = "$display - This is a composite field";
				say qq(<a href="/tmp/$temp\_$field.png" id="$field" title="$title">$display</a>);
				$self->_create_chartdirector_chart( $field, 2, $value_frequency->{$field}, $temp, $query_file );
				if ($first) {
					$src          = "/tmp/$temp\_$field.png";
					$display_name = $display;
					$name         = $field;
					undef $first;
				}
				$field_count++;
			}
		}
	}
	say q(</p></div></div>);
	say q(<noscript><p class="highlight">Please enable Javascript to view breakdown charts in place.</p></noscript>);
	if ( !$field_count ) {
		$self->print_bad_status( { message => q(There are no displayable fields defined.) } );
		return;
	}
	say qq(<div class="box" id="chart"><h2 id="field">$display_name</h2><div class="scrollable">)
	  . qq(<img id="placeholder" src="$src" alt="breakdown chart" /></div></div>);
	my $query_clause      = defined $query_file ? qq(&amp;query_file=$query_file) : q();
	my $list_file         = $q->param('list_file');
	my $datatype          = $q->param('datatype');
	my $temp_table_file   = $q->param('temp_table_file');
	my $listfile_clause   = defined $list_file ? qq(&amp;list_file=$list_file) : q();
	my $datatype_clause   = defined $datatype ? qq(&amp;datatype=$datatype) : q();
	my $temp_table_clause = defined $temp_table_file ? qq(&amp;temp_table_file=$temp_table_file) : q();
	my $base_link =
	    qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;)
	  . qq(name=FieldBreakdown&amp;function=summary_table$query_clause$listfile_clause$datatype_clause)
	  . qq($temp_table_clause&amp;field=$name);
	say q(<div class="box" id="resultsfooter"><h2>Output format</h2><p id="links">Select: )
	  . qq(<a href="$base_link&amp;format=html">Table</a> | )
	  . qq(<a href="$base_link&amp;format=text">Tab-delimited text</a> | )
	  . qq(<a href="$base_link&amp;format=xlsx">Excel format</a></p></div>);
	return;
}

sub _create_chartdirector_chart {
	my ( $self, $field, $numvalues, $value_frequency_ref, $temp, $query_file ) = @_;
	my $q    = $self->{'cgi'};
	my $guid = $self->get_guid;
	my %prefs;
	foreach (qw (threeD transparent small)) {
		try {
			$prefs{$_} =
			  $self->{'prefstore'}->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'FieldBreakdown', $_ );
			$prefs{$_} = $prefs{$_} eq 'true' ? 1 : 0;
		}
		catch BIGSdb::DatabaseNoRecordException with {
			$prefs{$_} = 1;
		};
	}
	try {
		$prefs{'style'} =
		  $self->{'prefstore'}->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'FieldBreakdown', 'style' );
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
	if ( $field =~ /^(?:age_|age$|year_|year$)/x ) {
		no warnings 'numeric';    #might complain about numeric comparison with non-numeric data
		foreach my $key ( sort { $a <=> $b } keys %value_frequency ) {
			if ( !( $key eq 'No value/unassigned' && $numvalues > 1 ) ) {
				$key =~ s/&Delta;/deleted/gx;
				push @labels, $key;
				push @values, $value_frequency{$key};
			}
		}
		if (@labels) {
			BIGSdb::Charts::barchart( \@labels, \@values, "$self->{'config'}->{'tmp_dir'}/$temp\_$field.png",
				$size, \%prefs );
		}
	} else {
		no warnings 'numeric';    #might complain about numeric comparison with non-numeric data
		foreach my $key (
			sort { $value_frequency{$b} <=> $value_frequency{$a} || ( $a <=> $b ) || ( $a cmp $b ) }
			keys %value_frequency
		  )
		{
			$key =~ s/&Delta;/deleted/gx;
			push @labels, $key;
			push @values, $value_frequency{$key};
		}
		BIGSdb::Charts::piechart(
			{
				labels     => \@labels,
				data       => \@values,
				filename   => "$self->{'config'}->{'tmp_dir'}/$temp\_$field.png",
				num_labels => 24,
				size       => $size,
				prefs      => \%prefs
			}
		);
	}
	return;
}

sub _is_composite_field {
	my ( $self, $field ) = @_;
	$field //= q();
	my $is_composite =
	  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM composite_fields WHERE id=?)', $field );
	return $is_composite;
}

sub _summary_table {
	my ( $self, $qry ) = @_;
	my $q      = $self->{'cgi'};
	my $field  = $q->param('field');
	my $format = $q->param('format') // 'html';
	my ( $html_buffer, $text_buffer );
	if ( !$field ) {
		$html_buffer = q(<h1>Field breakdown</h1><div class="box" id="statusbad"><p>No field selected.</p></div>);
		$text_buffer = qq(No field selected.\n);
	}
	my $isolate_field = $field // q();
	$isolate_field =~ s/\.\..*$//x;    #Extended attributes separated from parent field by '..'
	if (   !$self->{'xmlHandler'}->is_field($isolate_field)
		&& !$self->_is_composite_field($field) )
	{
		$html_buffer = q(<h1>Field breakdown</h1><div class="box" id="statusbad"><p>Invalid field selected.</p></div>);
		$text_buffer = qq(Invalid file selected.\n);
	}
	if ( !$qry ) {
		$html_buffer = q(<h1>Field breakdown</h1><div class="box" id="statusbad"><p>No query selected.</p></div>);
		$text_buffer .= qq(No query selected.\n);
		return;
	}
	if ($html_buffer) {                #Missing parameters so exit
		say $format eq 'html' ? $html_buffer : $text_buffer;
		return;
	}
	my $td = 1;
	my ( @labels, @values );
	my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
	my $display_field = $metafield // $field;
	$display_field =~ tr/_/ /;
	$display_field =~ s/^.*\.\.//x;
	$html_buffer .= qq(<h1>Breakdown by $display_field</h1>);
	$text_buffer .= qq(Breakdown for $display_field\n) if $format eq 'text';
	$logger->debug("Breakdown query: $qry");
	my ( $num_records, $frequency ) = $self->_get_value_frequency_hash( \$qry, $isolate_field );
	my $value_frequency = $frequency->{$field};
	my $num_values      = keys %{$value_frequency};
	my $values_shown    = $num_values;

	if ( $value_frequency->{'No value/unassigned'} ) {
		$values_shown--;
	}
	my $plural = $num_values != 1 ? 's' : '';
	$html_buffer .= q(<div class="box" id="resultstable">);
	$html_buffer .= qq(<p>$num_values value$plural.</p>);
	$html_buffer .= qq(<table class="tablesorter" id="sortTable"><thead><tr><th>$display_field</th>)
	  . q(<th>Frequency</th><th>Percentage</th></tr></thead><tbody>);
	$text_buffer .= "$num_values value$plural.\n\n" if $format eq 'text';
	$text_buffer .= "$display_field\tfrequency\tpercentage\n";
	if ( $field =~ /^(?:age_|age$|year_|year$)/x ) {

		#sort keys numerically
		no warnings 'numeric';    #might complain about numeric comparison with non-numeric data
		foreach my $key ( sort { $a <=> $b } keys %$value_frequency ) {
			my $percentage = BIGSdb::Utils::decimal_place( ( $value_frequency->{$key} / $num_records ) * 100, 2 );
			$html_buffer .= qq(<tr class="td$td"><td>$key</td><td>$value_frequency->{$key}</td>)
			  . qq(<td style="text-align:center">$percentage%</td></tr>);
			$text_buffer .= "$key\t$value_frequency->{$key}\t$percentage\n";
			$td = $td == 1 ? 2 : 1;    #row stripes
		}
	} else {
		my $sorted_keys = $self->_sort_hash_keys($value_frequency);
		foreach my $key (@$sorted_keys) {
			push @labels, $key;
			push @values, $value_frequency->{$key};
			my $percentage = BIGSdb::Utils::decimal_place( ( $value_frequency->{$key} / $num_records ) * 100, 2 );
			$html_buffer .=
			    qq(<tr class="td$td"><td>$key</td><td style="text-align:center">$value_frequency->{$key}</td>)
			  . qq(<td style="text-align:center">$percentage%</td></tr>);
			$text_buffer .= "$key\t$value_frequency->{$key}\t$percentage\n";
			$td = $td == 1 ? 2 : 1;    #row stripes
		}
	}
	if ( $format eq 'html' ) {
		$html_buffer .= q(</tbody></table></div>);
		say $html_buffer;
	} else {
		if ( $q->param('format') eq 'xlsx' ) {
			my $temp_file = $self->make_temp_file($text_buffer);
			my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$temp_file";
			BIGSdb::Utils::text2excel( $full_path,
				{ stdout => 1, worksheet => "$field breakdown", tmp_dir => $self->{'config'}->{'secure_tmp_dir'} } );
			unlink $full_path;
		} else {
			say $text_buffer;
		}
	}
	return;
}

#Sory by value, then by key (numerical followed by alphabetical)
sub _sort_hash_keys {
	my ( $self, $hash ) = @_;
	no warnings 'numeric';    #might complain about numeric comparison with non-numeric data
	my @keys = sort { $hash->{$b} <=> $hash->{$a} || ( $a <=> $b ) || ( $a cmp $b ) } keys %$hash;
	return \@keys;
}

sub _get_value_frequency_hash {

	#if queryfield is left blank, a hash is created for all fields
	my ( $self, $qryref, $query_field ) = @_;
	my $qry = $$qryref;
	my $value_frequency;
	my $num_records;
	my $fields = $self->{'xmlHandler'}->get_field_list;
	my $view   = $self->{'system'}->{'view'};
	local $" = ",$view.";
	my $field_string = "$view.@$fields";
	$qry =~ s/SELECT\ ($view\.\*|\*)/SELECT $field_string/x;
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };

	if ($@) {
		$logger->error($@);
		say q(<h1>Field breakdown</h1>);
		$self->print_bad_status( { message => 'Analysis failed', navbar => 1 } );
	}
	my %data = ();
	$sql->bind_columns( map { \$data{$_} } @$fields );    #quicker binding hash to arrayref than to use hashref
	my $use_composites = $self->_use_composites;
	my $field_is_composite;
	if ( $use_composites && $query_field ) {
		$field_is_composite = $self->_is_composite_field($query_field);
	}
	my $composite_fields;
	if ($use_composites) {
		$composite_fields =
		  $self->{'datastore'}->run_query( 'SELECT id FROM composite_fields', undef, { fetch => 'col_arrayref' } );
	}
	my @field_list;
	my $format = $self->{'cgi'}->param('format');
	if ( $query_field && $query_field !~ /^meta_[^:]+:/x ) {
		push @field_list, ( 'id', $query_field );
	} else {
		@field_list = @$fields;
	}
	while ( $sql->fetchrow_arrayref ) {
		my $value;
		foreach my $field (@field_list) {
			if ( !$field_is_composite ) {
				$data{$field} //= q();
				if ( $data{$field} eq q() ) {
					$value = 'No value/unassigned';
				} else {
					$value = $data{$field};
					if ( $format eq 'text' ) {
						$value =~ s/&Delta;/deleted/gx;
					}
				}
				$value_frequency->{$field}->{$value}++;
			}
		}
		if ( $use_composites && !( !$field_is_composite && $query_field ) ) {
			foreach my $field (@$composite_fields) {
				$value = $self->{'datastore'}->get_composite_value( $data{'id'}, $field, \%data );
				if ( $format eq 'text' ) {
					$value =~ s/&Delta;/deleted/gx;
				}
				$value_frequency->{$field}->{$value}++;
			}
		}
		$num_records++;
	}

	#Extended attributes
	foreach my $field (@field_list) {
		my $extatt = $self->{'extended'}->{$field};
		next if ref $extatt ne 'ARRAY';
		foreach my $extended_attribute (@$extatt) {
			foreach ( keys %{ $value_frequency->{$field} } ) {
				my $value = $self->{'datastore'}->run_query(
					'SELECT value FROM isolate_value_extended_attributes WHERE '
					  . '(isolate_field,attribute,field_value)=(?,?,?)',
					[ $field, $extended_attribute, $_ ],
					{ cache => 'FieldBreakdown::get_value_frequency_hash::ext' }
				);
				$value = 'No value/unassigned' if !defined $value || $value eq '';
				$value_frequency->{"$field..$extended_attribute"}->{$value} += $value_frequency->{$field}->{$_};
			}
		}
	}

	#Metadata sets
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
	foreach my $field (@$field_list) {
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
		next if !defined $metaset;
		my $meta_data = $self->{'datastore'}->run_query( "SELECT isolate_id,$metafield FROM meta_$metaset",
			undef, { fetch => 'all_hashref', key => 'isolate_id' } );
		foreach my $isolate_id ( keys %{ $value_frequency->{'id'} } ) {
			my $value = $meta_data->{$isolate_id}->{$metafield};
			$value = 'No value/unassigned' if !defined $value || $value eq '';
			$value_frequency->{$field}->{$value}++;
		}
	}
	return $num_records, $value_frequency;
}
1;
