#SchemeBreakdown.pm - SchemeBreakdown plugin for BIGSdb
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
package BIGSdb::Plugins::SchemeBreakdown;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use BIGSdb::Page qw(BUTTON_CLASS);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name        => 'Scheme Breakdown',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Breakdown of scheme fields and alleles',
		category    => 'Breakdown',
		buttontext  => 'Schemes/alleles',
		menutext    => 'Scheme and alleles',
		module      => 'SchemeBreakdown',
		version     => '1.1.7',
		section     => 'breakdown,postquery',
		url         => "$self->{'config'}->{'doclink'}/data_analysis.html#scheme-and-allele-breakdown",
		input       => 'query',
		requires    => 'js_tree',
		order       => 20,
		dbtype      => 'isolates'
	);
	return \%att;
}

sub get_option_list {
	my ($self) = @_;
	my @list = (
		{
			name        => 'order',
			description => 'Order results by',
			optlist     => 'field/allele name;frequency',
			default     => 'frequency'
		},
	);
	if ( $self->{'config'}->{'chartdirector'} ) {
		push @list,
		  (
			{ name => 'style',  description => 'Pie chart style',  optlist => 'pie;doughnut', default => 'doughnut' },
			{ name => 'threeD', description => 'Enable 3D effect', default => 1 },
			{ name => 'transparent', description => 'Enable transparent palette', default => 1 }
		  );
	}
	return \@list;
}

sub get_hidden_attributes {
	my @hidden = qw (field type field_breakdown);
	return \@hidden;
}

sub run {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $format     = $q->param('format');
	if ( $format eq 'text' ) {
		say qq(Scheme field and allele breakdown of dataset\n) if !$q->param('download');
	} else {
		say q(<h1>Scheme field and allele breakdown of dataset</h1>);
	}
	return if $self->has_set_changed;
	my $loci = $self->{'datastore'}->run_query( 'SELECT id FROM loci ORDER BY id', undef, { fetch => 'col_arrayref' } );
	if ( !scalar @$loci ) {
		say q(<div class="box" id="statusbad"><p>No loci are defined for this database.</p></div>);
		return;
	}
	my $qry_ref = $self->get_query($query_file);
	return if ref $qry_ref ne 'SCALAR';
	return if !$self->create_temp_tables($qry_ref);
	if ( $q->param('field_breakdown') || $q->param('download') ) {
		my $ids = $self->get_ids_from_query($qry_ref);
		my $list_table = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $ids );
		$self->_do_analysis($list_table);
		return;
	}
	say q(<div class="box" id="queryform"><div class="scrollable">);
	$self->_print_tree;
	say q(</div></div>);
	my $schemes =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id FROM schemes ORDER BY display_order,description', undef, { fetch => 'col_arrayref' } );
	my @selected_schemes;
	foreach ( @$schemes, 0 ) {
		push @selected_schemes, $_ if $q->param("s_$_");
	}
	return if !@selected_schemes;
	local $| = 1;
	say q(<div class="hideonload"><p>Please wait - calculating (do not refresh) ...</p>)
	  . q(<p><span class="main_icon fa fa-refresh fa-spin fa-4x"></span></p></div>);
	$self->{'mod_perl_request'}->rflush if $ENV{'MOD_PERL'};
	my $ids = $self->get_ids_from_query($qry_ref);
	my $list_table = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $ids );
	say q(<div class="box" id="resultstable">);

	foreach my $scheme_id (@selected_schemes) {
		say q(<div class="scrollable">);
		$self->_print_scheme_table( $list_table, $scheme_id );
		say q(</div>);
	}
	say q(</div>);
	return;
}

sub _do_analysis {
	my ( $self, $list_table ) = @_;
	my $q          = $self->{'cgi'};
	my $field_type = 'text';
	my ( $field, $scheme_id );
	my $temp_table;
	my $qry;
	if ( $q->param('type') eq 'field' ) {
		if ( $q->param('field') =~ /^(\d+)_(.*)$/x ) {
			$scheme_id = $1;
			$field     = $2;
			if ( !$self->{'datastore'}->is_scheme_field( $scheme_id, $field ) ) {
				say q(<div class="box" id="statusbad"><p>Invalid field passed for analysis!</p></div>);
				$logger->error( q(Invalid field passed for analysis. Field is set as ') . $q->param('field') . q('.) );
				return;
			}
			my $scheme_fields_qry;
			my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
			if ( $scheme_info->{'dbase_name'} ) {
				my $continue = 1;
				try {
					$temp_table = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
					$qry        = "SELECT DISTINCT(${temp_table}.$field),COUNT(${temp_table}.$field) FROM $list_table "
					  . "LEFT JOIN $temp_table ON $list_table.value=$temp_table.id GROUP BY $temp_table.$field";
				}
				catch BIGSdb::DatabaseConnectionException with {
					say qq("<div class="box" id="statusbad"><p>The database for scheme $scheme_id is not accessible. )
					  . q(This may be a configuration problem.</p></div>);
					$continue = 0;
				};
				return if !$continue;
			}
		} else {
			say q(<div class="box" id="statusbad"><p>Invalid field passed for analysis!</p></div>);
			$logger->error( q(Invalid field passed for analysis. Field is set as ') . $q->param('field') . q('.) );
			return;
		}
	} elsif ( $q->param('type') eq 'locus' ) {
		my $locus = $q->param('field');
		$field = $locus;
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		$field_type = $locus_info->{'allele_id_format'};
		my $allele_id_term = $field_type eq 'integer' ? 'CAST(allele_id AS integer)' : 'allele_id';
		$locus =~ s/'/\\'/gx;
		$qry =
		    "SELECT DISTINCT($allele_id_term),COUNT(allele_id) FROM $list_table LEFT JOIN allele_designations ON "
		  . "$list_table.value=allele_designations.isolate_id AND allele_designations.locus=E'$locus' "
		  . 'GROUP BY allele_designations.allele_id';
	} else {
		say q(<div class="box" id="statusbad"><p>Invalid field passed for analysis!</p></div>);
		$logger->error( q(Invalid field passed for analysis. Field type is set as ') . $q->param('type') . q('.) );
		return;
	}
	my $order;
	my $guid = $self->get_guid;
	my $temp_fieldname;
	if ( $q->param('type') eq 'locus' ) {
		$temp_fieldname = 'allele_id';
	} else {
		$temp_fieldname = defined $scheme_id ? "$temp_table\.$field" : $field;
	}
	my $field_order =
	    $field_type eq 'text'
	  ? $temp_fieldname
	  : "CAST($temp_fieldname AS int)";
	try {
		$order =
		  $self->{'prefstore'}->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'SchemeBreakdown', 'order' );
		if ( $order eq 'frequency' ) {
			$order = "COUNT($temp_fieldname) desc, $field_order";
		} else {
			$order = $field_order;
		}
	}
	catch BIGSdb::DatabaseNoRecordException with {
		$order = "COUNT($temp_fieldname) desc, $field_order";
	};
	$qry .= " ORDER BY $order";
	my $total = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM $list_table");
	if ( $q->param('download') ) {
		$self->_download_alleles( $field, $qry );
	} else {
		$self->_breakdown_field( $field, $qry, $total );
	}
	return;
}

sub _breakdown_field {
	my ( $self, $field, $qry, $total ) = @_;
	my $q            = $self->{'cgi'};
	my $heading      = $q->param('type') eq 'field' ? $field : $q->param('field');
	my $html_heading = '';
	if ( $q->param('type') eq 'locus' ) {
		my $locus = $q->param('field');
		my @other_display_names;
		local $" = '; ';
		my $aliases = $self->{'datastore'}->get_locus_aliases($locus);
		push @other_display_names, @$aliases if @$aliases;
		$html_heading .= qq( <span class="comment">(@other_display_names)</span>) if @other_display_names;
	}
	my $td     = 1;
	my $format = $q->param('format');
	if ( $format eq 'text' ) {
		say qq(Total: $total isolates\n);
		say qq($heading\tFrequency\tPercentage);
	} else {
		say q(<div class="box" id="resultstable"><div class="scrollable">);
		say q(<h2>Frequency table</h2>);
		say qq(<p>Total: $total isolates</p>);
		say q(<table class="tablesorter" id="sortTable">);
		$heading = $self->clean_locus($heading) if $q->param('type') eq 'locus';
		say qq(<thead><tr><th>$heading$html_heading</th><th>Frequency</th><th>Percentage</th></tr></thead>);
	}
	my ( @labels, @values );
	$qry =~ s/\*/COUNT(\*)/x;
	my $data = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref' } );
	foreach my $allele (@$data) {
		my ( $allele_id, $count ) = @$allele;
		if ($count) {
			my $percentage = BIGSdb::Utils::decimal_place( $count * 100 / $total, 2 );
			if ( $format eq 'text' ) {
				say qq($allele_id\t$count\t$percentage);
			} else {
				say qq(<tr class=\"td$td\"><td>);
				if ( $allele_id eq '' ) {
					say q(No value);
				} else {
					my $url;
					if ( $q->param('type') eq 'locus' ) {
						$url = $self->{'datastore'}->get_locus_info( $q->param('field') )->{'url'} || '';
						$url =~ s/&/&amp;/gx;
						$url =~ s/\[\?\]/$allele_id/x;
					}
					say $url ? qq(<a href="$url">$allele_id</a>) : $allele_id;
				}
				say qq(</td><td>$count</td><td>$percentage</td></tr>);
				$td = $td == 1 ? 2 : 1;
			}
			push @labels, ( $allele_id ne '' ) ? $allele_id : q(No value);
			push @values, $count;
		}
	}
	if ( $format ne 'text' ) {
		say q(</table>);
		my $query_file_att = $q->param('query_file') ? ( q(&amp;query_file=) . $q->param('query_file') ) : undef;
		say $q->start_form;
		say q(<p style="margin-top:0.5em">Download: );
		say $q->submit( -name => 'field_breakdown', -label => 'Tab-delimited text', -class => BUTTON_CLASS );
		say q(</p>);
		$q->param( format => 'text' );
		say $q->hidden($_) foreach qw (query_file field type page name db format list_file datatype);
		say $q->end_form;
		say q(</div></div>);

		if ( $self->{'config'}->{'chartdirector'} ) {
			my %prefs;
			my $guid = $self->get_guid;
			foreach (qw (threeD transparent )) {
				try {
					$prefs{$_} =
					  $self->{'prefstore'}
					  ->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'SchemeBreakdown', $_ );
					$prefs{$_} = $prefs{$_} eq 'true' ? 1 : 0;
				}
				catch BIGSdb::DatabaseNoRecordException with {
					$prefs{$_} = 1;
				};
			}
			try {
				$prefs{'style'} =
				  $self->{'prefstore'}
				  ->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'SchemeBreakdown', 'style' );
			}
			catch BIGSdb::DatabaseNoRecordException with {
				$prefs{'style'} = 'doughnut';
			};
			my $temp = BIGSdb::Utils::get_random();
			BIGSdb::Charts::piechart( \@labels, \@values, "$self->{'config'}->{'tmp_dir'}/${temp}_pie.png",
				24, 'small', \%prefs, { no_transparent => 1 } );
			say q(<div class="box" id="chart"><div class="scrollable">);
			say q(<h2>Charts</h2>);
			say q(<p>Click to enlarge.</p>);
			say q(<fieldset><legend>Pie chart</legend>);
			say qq(<a href="/tmp/${temp}_pie.png" data-rel="lightbox-1" class="lightbox" )
			  . qq(title="Pie chart: $heading breakdown"><img src="/tmp/${temp}_pie.png" )
			  . qq(alt="Pie chart: $heading breakdown" style="width:200px;border:1px dashed black" /></a>);
			say q(</fieldset>);
			BIGSdb::Charts::barchart( \@labels, \@values, "$self->{'config'}->{'tmp_dir'}/${temp}_bar.png",
				'small', \%prefs, { no_transparent => 1 } );
			say q(<fieldset><legend>Bar chart</legend>);
			say qq(<a href="/tmp/${temp}_bar.png" data-rel="lightbox-1" class="lightbox" )
			  . qq(title="Bar chart: $heading breakdown"><img src="/tmp/${temp}_bar.png" )
			  . qq(alt="Bar chart: $heading breakdown" style="width:200px;border:1px dashed black" /></a>);
			say q(</fieldset>);
			say q(</div></div>);
		}
		say q(<div style="clear:both"></div>);
	}
	return;
}

sub _print_scheme_table {
	my ( $self, $list_table, $scheme_id ) = @_;
	my $q      = $self->{'cgi'};
	my $set_id = $self->get_set_id;
	return
	  if !$self->{'prefs'}->{'analysis_schemes'}->{$scheme_id}
	  && $scheme_id;
	my ( $fields, $loci );
	if ($scheme_id) {
		$fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		$loci = $self->{'datastore'}->get_scheme_loci( $scheme_id, ( { profile_name => 0, analysis_pref => 1 } ) );
	} else {
		$loci = $self->{'datastore'}->get_loci_in_no_scheme( { analyse_pref => 1, set_id => $set_id } );
		$fields = \@;;
	}
	return if !@$loci && !@$fields;
	my $rows = ( @$fields >= @$loci ? @$fields : @$loci ) || 1;
	my $scheme_info;
	if ($scheme_id) {
		$scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
	} else {
		$scheme_info->{'description'} = 'Loci not in schemes';
	}
	my $scheme_fields_qry;
	my $temp_table;
	if ( $scheme_id && $scheme_info->{'dbase_name'} && @$fields ) {
		my $continue = 1;
		try {
			$temp_table        = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
			$scheme_fields_qry = "SELECT * FROM $list_table LEFT JOIN $temp_table ON $list_table.value=$temp_table.id";
		}
		catch BIGSdb::DatabaseConnectionException with {
			say q(<div class="box" id="statusbad"><p>The database for scheme $scheme_id is not accessible. )
			  . q(This may be a configuration problem.</p></div>);
			$continue = 0;
		};
		return if !$continue;
	}
	( my $desc = $scheme_info->{'description'} ) =~ s/&/&amp;/gx;
	local $| = 1;
	say qq(<h2>$desc</h2>);
	say q(<table class="resultstable"><tr>);
	say q(<th colspan="3">Fields</th>) if @$fields;
	say q(<th colspan="4">Alleles</th></tr><tr>);
	say q(<th>Field name</th><th>Unique values</th><th>Analyse</th>) if @$fields;
	say q(<th>Locus</th><th>Unique alleles</th><th>Analyse</th><th>Download</th>);
	say q(</tr>);
	my $td = 1;
	say qq(<tr class="td$td">);
	my $field_values;

	if ( $scheme_info->{'dbase_name'} && @$fields ) {
		my $scheme_query = $scheme_fields_qry;
		local $" = ",$temp_table.";
		my $field_string = "$temp_table.@$fields";
		$scheme_query =~ s/\*/$field_string/x;
		my $data = $self->{'datastore'}->run_query( $scheme_query, undef, { fetch => 'all_arrayref' } );
		foreach my $values (@$data) {
			my $i = 0;
			foreach my $field (@$fields) {
				$field_values->{$field}->{ $values->[$i] } = 1 if defined $values->[$i];
				$i++;
			}
		}
	}
	for my $i ( 0 .. $rows - 1 ) {
		say qq(<tr class="td$td">) if $i;
		my $display;
		if (@$fields) {
			$display = $fields->[$i] || '';
			$display =~ tr/_/ /;
			say qq(<td>$display</td>);
			if ( $scheme_info->{'dbase_name'} && @$fields && $fields->[$i] ) {
				my $value = keys %{ $field_values->{ $fields->[$i] } };
				say qq(<td>$value</td><td>);
				if ($value) {
					say $q->start_form;
					say q(<button type="submit" class="plugin fa fa-pie-chart smallbutton"></button>);
					$q->param( field           => "$scheme_id\_$fields->[$i]" );
					$q->param( type            => 'field' );
					$q->param( field_breakdown => 1 );
					say $q->hidden($_)
					  foreach qw (page name db query_file type field field_breakdown list_file datatype);
					say $q->end_form;
				}
				say q(</td>);
			} else {
				say q(<td></td><td></td>);
			}
		}
		$display = $self->clean_locus( $loci->[$i] );
		my $locus_aliases = [];
		if ( defined $loci->[$i] && $self->{'prefs'}->{'locus_alias'} ) {
			$locus_aliases = $self->{'datastore'}->get_locus_aliases( $loci->[$i] );
		}
		if (@$locus_aliases) {
			local $" = ', ';
			$display .= qq( <span class="comment">(@$locus_aliases)</span>);
			$display =~ tr/_/ /;
		}
		print defined $display ? qq(<td>$display</td>) : q(<td></td>);
		if ( $loci->[$i] ) {
			my $locus_query = "SELECT COUNT(DISTINCT(allele_id)) FROM $list_table LEFT JOIN allele_designations ON "
			  . "allele_designations.isolate_id=$list_table.value";
			$locus_query .= ' WHERE locus=?';
			$locus_query .= q( AND status != 'ignore');
			my $value =
			  $self->{'datastore'}
			  ->run_query( $locus_query, $loci->[$i], { cache => 'SchemeBreakdown::print_scheme_table:loci' } );
			say qq(<td>$value</td>);
			if ($value) {
				say q(<td>);
				say $q->start_form;
				say q(<button type="submit" class="plugin fa fa-pie-chart smallbutton"></button>);
				$q->param( field => $loci->[$i] );
				$q->param( type  => 'locus' );
				say $q->hidden( field_breakdown => 1 );
				say $q->hidden($_) foreach qw (page name db query_file field type list_file datatype);
				say $q->end_form;
				say q(</td><td>);
				say $q->start_form;
				say q(<button type="submit" class="main fa fa-download smallbutton"></button>);
				say $q->hidden( download => 1 );
				$q->param( format => 'text' );
				say $q->hidden($_) foreach qw (page name db query_file field type format list_file datatype);
				say $q->end_form;
				say q(</td>);
			} else {
				say q(<td></td><td></td>);
			}
		} else {
			say q(<td></td><td></td><td></td>);
		}
		say q(</tr>);
		$td = $td == 1 ? 2 : 1;
	}
	print "</table>\n";
	if ( $ENV{'MOD_PERL'} ) {
		$self->{'mod_perl_request'}->rflush;
		return if $self->{'mod_perl_request'}->connection->aborted;
	}
	return;
}

sub _download_alleles {
	my ( $self, $locus, $qry ) = @_;
	my $alleles = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	my $locus_obj = $self->{'datastore'}->get_locus($locus);
	foreach my $allele (@$alleles) {
		next if !defined $allele->{'allele_id'};
		try {
			my $seq_ref = $locus_obj->get_allele_sequence( $allele->{'allele_id'} );
			my $formatted_seq_ref = BIGSdb::Utils::break_line( $seq_ref, 60 );
			say ">$allele->{'allele_id'}";
			$$formatted_seq_ref = q(-) if length $$formatted_seq_ref == 0;
			say $$formatted_seq_ref;
		}
		catch BIGSdb::BIGSException with {
			$logger->error("Locus $locus is misconfigured.");
		};
	}
	return;
}

sub _print_tree {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say $q->start_form;
	say q(<p>Select schemes or groups of schemes within the tree.  A breakdown of the individual fields )
	  . q(and loci belonging to these schemes will then be performed.</p>);
	say q(<noscript><p class="highlight">You need to enable Javascript in order to select schemes )
	  . q(for analysis.</p></noscript>);
	say q(<fieldset style="float:left"><legend>Select schemes</legend>);
	say q(<div id="tree" class="tree" style="display:none; height:10em; width:30em">);
	say $self->get_tree( undef, { no_link_out => 1, select_schemes => 1, analysis_pref => 1 } );
	say q(</div></fieldset>);
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Select' } );
	my $set_id = $self->get_set_id;
	$q->param( set_id => $set_id );
	say $q->hidden($_) foreach qw(db page name query_file set_id list_file datatype);
	say $q->end_form;
	return;
}

sub get_plugin_javascript {
	my ($self) = @_;
	my $buffer = << "END";
\$(function () {
	\$('#tree').show();
});
	
END
	return $buffer;
}
1;
