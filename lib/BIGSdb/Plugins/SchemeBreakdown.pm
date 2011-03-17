#SchemeBreakdown.pm - SchemeBreakdown plugin for BIGSdb
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
package BIGSdb::Plugins::SchemeBreakdown;
use strict;
use base qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);

sub get_attributes {
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
		version     => '1.0.3',
		section     => 'breakdown,postquery',
		input       => 'query',
		requires    => '',
		order       => 20,
		dbtype      => 'isolates'
	);
	return \%att;
}

sub get_option_list {
	my ($self) = @_;
	my @list =
	  ( { name => 'order', description => 'Order results by', optlist => 'field/allele name;frequency', default => 'frequency' }, );
	if ( $self->{'config'}->{'chartdirector'} ) {
		push @list,
		  (
			{ name => 'style',       description => 'Pie chart style',            optlist => 'pie;doughnut', default => 'doughnut' },
			{ name => 'threeD',      description => 'Enable 3D effect',           default => 1 },
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
	my ($self)   = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $format     = $q->param('format');
	my $field;
	if ( $format eq 'text' ) {
		print "Scheme field and allele breakdown of dataset\n\n";
	} else {
		print "<h1>Scheme field and allele breakdown of dataset</h1>\n";
	}
	my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes ORDER BY display_order,id");
	my $loci = $self->{'datastore'}->run_list_query("SELECT id FROM loci ORDER BY id");
	if ( !scalar @$loci ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No loci are defined for this database.</p></div>\n";
		return;
	}
	my $qry_ref = $self->get_query($query_file);
	return if ref $qry_ref ne 'SCALAR';
	my $qry = $$qry_ref;
	
	$qry =~ s/ORDER BY.*$//g;
	$logger->debug("Breakdown query: $qry");
	return if !$self->create_temp_tables($qry_ref);
		my $locus_info_sql = $self->{'db'}->prepare("SELECT id,common_name FROM loci WHERE common_name IS NOT NULL");
	eval { $locus_info_sql->execute; };    
	if ($@) {
		$logger->error("Can't execute $@");
	}
	my $locus_info = $locus_info_sql->fetchall_hashref('id');
	if ( $q->param('field_breakdown') ) {
		my $field_query = $qry;
		my $field_type  = 'text';
		if ( $q->param('type') eq 'field' ) {
			if ( $q->param('field') =~ /^(\d+)_(.*)$/ ) {
				my $scheme_id = $1;
				$field = $2;
				if ( !$self->{'datastore'}->is_scheme_field( $scheme_id, $field ) ) {
					print "<div class=\"box\" id=\"statusbad\"><p>Invalid field passed for analysis!</p></div>\n";
					$logger->error( "Invalid field passed for analysis. Field is set as '" . $q->param('field') . "'." );
					return;
				}
				my $scheme_fields_qry;
				my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
				if ( $scheme_info->{'dbase_name'} ) {
					my $continue = 1;
					try {
						$scheme_fields_qry = $self->_get_scheme_fields_sql($scheme_id);
						$self->{'datastore'}->create_temp_scheme_table($scheme_id);
					}
					catch BIGSdb::DatabaseConnectionException with {
						print
"<div class=\"box\" id=\"statusbad\"><p>The database for scheme $scheme_id is not accessible.  This may be a configuration problem.</p></div>\n";
						$continue = 0;
					};
					return if !$continue;
				}
				$field_query = $$scheme_fields_qry;
				my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
				$field_type = $scheme_field_info->{'type'};
				if ( $field_type eq 'integer' ) {
					$field_query =~ s/\*/DISTINCT(CAST($field AS int)),COUNT($field)/;
				} else {
					$field_query =~ s/\*/DISTINCT($field),COUNT($field)/;
				}
				if ( $qry =~ /SELECT \* FROM refs/ || $qry =~ /SELECT \* FROM $self->{'system'}->{'view'} LEFT JOIN refs/) {
					$field_query =~
					  s/FROM $self->{'system'}->{'view'}/FROM $self->{'system'}->{'view'} LEFT JOIN refs ON refs.isolate_id=id/;
				}
				if ( $qry =~ /WHERE (.*)$/ ) {
					$field_query .= " AND $1";
				}
				$field_query .= " GROUP BY scheme_$scheme_id.$field";
			} else {
				print "<div class=\"box\" id=\"statusbad\"><p>Invalid field passed for analysis!</p></div>\n";
				$logger->error( "Invalid field passed for analysis. Field is set as '" . $q->param('field') . "'." );
				return;
			}
		} elsif ( $q->param('type') eq 'locus' ) {
			my $locus = $q->param('field');
			if ( !$self->{'datastore'}->is_locus($locus) ) {
				print "<div class=\"box\" id=\"statusbad\"><p>Invalid locus passed for analysis!</p></div>\n";
				$logger->error( "Invalid locus passed for analysis. Locus is set as '" . $q->param('field') . "'." );
				return;
			}
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			$locus =~ s/'/\\'/g;
			$field_type = $locus_info->{'allele_id_format'};
			$field_query =~
s/SELECT \* FROM $self->{'system'}->{'view'}/SELECT \* FROM $self->{'system'}->{'view'} LEFT JOIN allele_designations ON isolate_id=id/;
			if ( $field_type eq 'integer' ) {
				$field_query =~ s/\*/DISTINCT(CAST(allele_id AS int)),COUNT(allele_id)/;
			} else {
				$field_query =~ s/\*/DISTINCT(allele_id),COUNT(allele_id)/;
			}
			if ( $field_query =~ /WHERE/ ) {
				$field_query =~ s/WHERE (.*)$/WHERE \($1\)/;
				$field_query .= " AND locus='$locus'";
			} else {
				$field_query .= " WHERE locus='$locus'";
			}
			$field_query =~
s/refs RIGHT JOIN $self->{'system'}->{'view'}/refs RIGHT JOIN $self->{'system'}->{'view'} LEFT JOIN allele_designations ON isolate_id=id/;
			$field_query .= " GROUP BY allele_id";
		} else {
			print "<div class=\"box\" id=\"statusbad\"><p>Invalid field passed for analysis!</p></div>\n";
			$logger->error( "Invalid field passed for analysis. Field type is set as '" . $q->param('type') . "'." );
			return;
		}
		my $order;
		my $guid = $self->get_guid;
		my $temp_fieldname = $q->param('type') eq 'locus' ? 'allele_id' : $field;
		try {
			$order = $self->{'prefstore'}->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'SchemeBreakdown', 'order' );
			if ( $order eq 'frequency' ) {
				$order = "COUNT($temp_fieldname) desc";
			} else {
				$order =
				    $field_type eq 'text'
				  ? $temp_fieldname
				  : "CAST($temp_fieldname AS int)";
			}
		}
		catch BIGSdb::DatabaseNoRecordException with {
			$order = "COUNT($temp_fieldname) desc";
		};
		$field_query .= " ORDER BY $order";
		$field_query = "SET enable_nestloop = off; " . $field_query;
		my $sql = $self->{'db'}->prepare($field_query);
		eval { $sql->execute(); };
		if ($@) {
			$logger->error("Can't execute $field_query $@");
		}
		my $heading = $q->param('type') eq 'field' ? $field : $q->param('field');
		my $html_heading;
		if ( $q->param('type') eq 'locus' ) {
			my $locus = $q->param('field');
			my @other_display_names;
			push @other_display_names, $locus_info->{$locus}->{'common_name'} if $locus_info->{$locus}->{'common_name'};
			$" = '; ';
			my $aliases =
			  $self->{'datastore'}->run_list_query( "SELECT alias FROM locus_aliases WHERE locus=? ORDER BY alias", $locus );
			 push @other_display_names, @$aliases if @$aliases;
			$html_heading .= " <span class=\"comment\">(@other_display_names)</span>" if @other_display_names;
		}
		$heading =~ tr/_/ /;
		my $td = 1;
		if ( $format ne 'text' ) {
			print "<div class=\"box\" id=\"resultstable\"><div class=\"scrollable\">";
			print "<table><tr><td style=\"vertical-align:top\">\n";
		}
		$qry =~ s/\*/COUNT(\*)/;
		my $total = $self->{'datastore'}->run_simple_query($qry)->[0];
		if ( $format eq 'text' ) {
			print "Total: $total isolates\n\n";
			print "$heading\tFrequency\tPercentage\n";
		} else {
			print "<p>Total: $total isolates</p>\n";
			
			print "<table class=\"tablesorter\" id=\"sortTable\">\n";
			print "<thead><tr><th>$heading$html_heading</th><th>Frequency</th><th>Percentage</th></tr></thead>\n";
		}
		my ( @labels, @values );
		while ( my ( $allele_id, $count ) = $sql->fetchrow_array ) {
			if ($count) {
				my $percentage = BIGSdb::Utils::decimal_place( $count * 100 / $total, 2 );
				if ( $format eq 'text' ) {
					print "$allele_id\t$count\t$percentage\n";
				} else {
					print "<tr class=\"td$td\"><td>";
					if ($allele_id eq ''){
						print 'No value';
					} else {
						my $url;
						if ($q->param('type') eq 'locus'){
							$url = $self->{'datastore'}->get_locus_info($q->param('field'))->{'url'};
							$url =~ s/\&/\&amp;/g;
							$url =~ s/\[\?\]/$allele_id/;
						}
						if ($url){
							print "<a href=\"$url\">$allele_id</a>";
						} else {
							print $allele_id;
						}
					}
					print "</td><td>$count</td><td>$percentage</td></tr>\n";
					$td = $td == 1 ? 2 : 1;
				}
				push @labels, ($allele_id ne '') ? $allele_id : 'No value';
				push @values, $count;
			}
		}
		if ( $format ne 'text' ) {
			print "</table>\n";
			print "</td><td style=\"vertical-align:top; padding-left:2em\">\n";
			my $query_file_att = "&amp;query_file=" . $q->param('query_file') if $q->param('query_file');
			print $q->start_form;
			print $q->submit( -name => 'field_breakdown', -label => 'Tab-delimited text', -class => 'smallbutton' );
			$q->param( 'format', 'text' );
			foreach (qw (query_file field type page name db format)) {
				print $q->hidden($_);
			}
			print $q->end_form;
			if ( $self->{'config'}->{'chartdirector'} ) {
				my %prefs;
				foreach (qw (threeD transparent )) {
					try {
						$prefs{$_} = $self->{'prefstore'}->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'SchemeBreakdown', $_ );
						$prefs{$_} = $prefs{$_} eq 'true' ? 1 : 0;
					}
					catch BIGSdb::DatabaseNoRecordException with {
						$prefs{$_} = 1;
					};
				}
				try {
					$prefs{'style'} =
					  $self->{'prefstore'}->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'SchemeBreakdown', 'style' );
				}
				catch BIGSdb::DatabaseNoRecordException with {
					$prefs{'style'} = 'doughnut';
				};
				my $temp = BIGSdb::Utils::get_random();
				BIGSdb::Charts::piechart( \@labels, \@values, "$self->{'config'}->{'tmp_dir'}/$temp\_$field\_pie.png",
					24, 'small', \%prefs );
				print "<img src=\"/tmp/$temp\_$field\_pie.png\" alt=\"pie chart\" />\n";
				BIGSdb::Charts::barchart( \@labels, \@values, "$self->{'config'}->{'tmp_dir'}/$temp\_$field\_bar.png", 'small', \%prefs );
				print "<img src=\"/tmp/$temp\_$field\_bar.png\" alt=\"bar chart\" />\n";
			}
			print "</td></tr></table>\n";
			print "</div></div>\n";
		}
		return;
	}
	print "<div class=\"box\" id=\"resultstable\">\n<table class=\"resultstable\">\n";
	print "<tr><th rowspan=\"2\">Scheme</th><th colspan=\"3\">Fields</th><th colspan=\"3\">Alleles</th></tr>\n";
	print "<tr><th>Field name</th><th>Unique values</th><th>Analyse</th><th>Locus</th><th>Unique alleles</th><th>Analyse</th></tr>\n";
	my $td = 1;
	$| = 1;
	my $alias_sql  = $self->{'db'}->prepare("SELECT alias FROM locus_aliases WHERE locus=?");
	foreach my $scheme_id ( @$schemes, 0 ) {
		next
		  if !$self->{'prefs'}->{'analysis_schemes'}->{$scheme_id}
			  && $scheme_id;
		my ( $fields, $loci );
		if ($scheme_id) {
			$fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
			$loci = $self->{'datastore'}->get_scheme_loci( $scheme_id, ({'profile_name' => 0, 'analyse_prefs' => 1}) );
		} else {
			$loci   = $self->{'datastore'}->get_loci_in_no_scheme(1);
			$fields = \@;;
		}
		next if !@$loci && !@$fields;
		my $rows = ( scalar @$fields >= scalar @$loci ? scalar @$fields : scalar @$loci )
		  || 1;
		my $scheme_info;
		if ($scheme_id) {
			$scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
		} else {
			$scheme_info->{'description'} = 'None';
		}
		my $scheme_fields_qry;
		if ( $scheme_id && $scheme_info->{'dbase_name'} && @$fields ) {
			my $continue = 1;
			try {
				$scheme_fields_qry = $self->_get_scheme_fields_sql($scheme_id);
				$self->{'datastore'}->create_temp_scheme_table($scheme_id);
			}
			catch BIGSdb::DatabaseConnectionException with {
				print "</table>\n</div>\n";
				print
"<div class=\"box\" id=\"statusbad\"><p>The database for scheme $scheme_id is not accessible.  This may be a configuration problem.</p></div>\n";
				$continue = 0;
			};
			return if !$continue;
		}
		print "<tr class=\"td$td\"><td rowspan=\"$rows\">$scheme_info->{'description'}</td>";
		for ( my $i = 0 ; $i < $rows ; $i++ ) {
			print "<tr class=\"td$td\">" if $i;
			my $display = $fields->[$i];
			$display =~ tr/_/ /;
			print "<td>$display</td>";
			if ( $scheme_info->{'dbase_name'} && @$fields && $fields->[$i] ) {
				my $scheme_query = $$scheme_fields_qry;
				
				$scheme_query =~ s/\*/COUNT (DISTINCT($fields->[$i]))/;
				if ( $qry =~ /SELECT \* FROM refs/ || $qry =~ /SELECT \* FROM $self->{'system'}->{'view'} LEFT JOIN refs/) {
					$scheme_query =~
					  s/FROM $self->{'system'}->{'view'}/FROM $self->{'system'}->{'view'} LEFT JOIN refs ON refs.isolate_id=id/;
				} 
				if ( $qry =~ /WHERE (.*)$/ ) {
					$scheme_query .= " AND ($1)";
				}
				$scheme_query = "SET enable_nestloop = off; " . $scheme_query;
				my $sql = $self->{'db'}->prepare($scheme_query);
				$logger->debug($scheme_query);
				
				eval { $sql->execute; };
				if ($@) {
					$logger->error("Can't execute $scheme_query $@");
				}
				my ($value) = $sql->fetchrow_array;
				print "<td>$value</td><td>";
				if ($value) {
					print $q->start_form;
					print $q->submit( -label => 'Breakdown', -class => 'smallbutton' );
					print $q->hidden( 'field',           "$scheme_id\_$fields->[$i]" );
					print $q->hidden( 'type',            'field' );
					print $q->hidden( 'field_breakdown', 1 );
					foreach (qw (page name db query_file)) {
						print $q->hidden($_);
					}
					print $q->end_form;
				}
				print "</td>";
			} else {
				print "<td /><td />";
			}
			$display = $loci->[$i];
			my @other_display_names;
			push @other_display_names, $locus_info->{$loci->[$i]}->{'common_name'} if $locus_info->{$loci->[$i]}->{'common_name'};
			if ( $self->{'prefs'}->{'locus_alias'} ) {
				eval { $alias_sql->execute( $loci->[$i] ); };
				if ($@) {
					$logger->error("Can't execute alias check $@");
				} else {
					while ( my ($alias) = $alias_sql->fetchrow_array ) {
						push @other_display_names, $alias;
					}
				}
				
			}
			$display .= " <span class=\"comment\">(@other_display_names)</span>" if @other_display_names;
			$display =~ tr/_/ /;
			print "<td>$display</td>";
			if ( $loci->[$i] ) {
				my $cleaned_locus = $loci->[$i];
				$cleaned_locus =~ s/'/\\'/g;
				
				my $locus_query = $qry;
				
				$locus_query =~
s/SELECT \* FROM $self->{'system'}->{'view'}/SELECT \* FROM $self->{'system'}->{'view'} LEFT JOIN allele_designations ON isolate_id=id/;
				$locus_query =~ s/\*/COUNT (DISTINCT(allele_id))/;
				if ( $locus_query =~ /WHERE/ ) {
					$locus_query =~ s/WHERE (.*)$/WHERE \($1\)/;
					$locus_query .= " AND locus='$cleaned_locus'";
				} else {
					$locus_query .= " WHERE locus='$cleaned_locus'";
				}
				$locus_query =~
s/refs RIGHT JOIN $self->{'system'}->{'view'}/refs RIGHT JOIN $self->{'system'}->{'view'} LEFT JOIN allele_designations ON isolate_id=id/;
				my $sql = $self->{'db'}->prepare($locus_query);
				eval { $sql->execute(); };
				if ($@) {
					$logger->error("Can't execute $locus_query $@");
				}
				my ($value) = $sql->fetchrow_array;
				print "<td>$value</td><td>";
				if ($value) {
					print $q->start_form;
					print $q->submit( -label => 'Breakdown', -class => 'smallbutton' );
					print $q->hidden( 'field',           $loci->[$i] );
					print $q->hidden( 'type',            'locus' );
					print $q->hidden( 'field_breakdown', 1 );
					foreach (qw (page name db query_file)) {
						print $q->hidden($_);
					}
					print $q->end_form;
				}
				print "</td>";
			} else {
				print "<td /><td />\n";
			}
			print "</tr>\n";
		}
		$td = $td == 1 ? 2 : 1;
	}
	print "</table>\n";
	print "</div>\n";
}

sub _get_scheme_fields_sql {
	my ( $self, $scheme_id ) = @_;
	my $scheme_loci   = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	$" = ',';
	my $joined_table = "SELECT * FROM $self->{'system'}->{'view'}";
	$" = ',';
	foreach (@$scheme_loci) {
		$joined_table .= " left join allele_designations AS $_ on $_.isolate_id = $self->{'system'}->{'view'}.id";
	}
	$joined_table .= " left join temp_scheme_$scheme_id AS scheme_$scheme_id ON ";
	my @temp;
	foreach (@$scheme_loci) {
		my $locus_info = $self->{'datastore'}->get_locus_info($_);
		push @temp,
		  $locus_info->{'allele_id_format'} eq 'integer'
		  ? " CAST($_.allele_id AS int)=scheme_$scheme_id\.$_"
		  : " $_.allele_id=scheme_$scheme_id\.$_";
	}
	$" = ' AND ';
	$joined_table .= " @temp WHERE";
	undef @temp;
	foreach (@$scheme_loci) {
		push @temp, "$_.locus='$_'";
	}
	$joined_table .= " @temp";
	return \$joined_table;
}
1;
