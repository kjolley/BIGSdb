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
package BIGSdb::Plugin;
use strict;
use base qw(BIGSdb::Page);
use Error qw(:try);
use Log::Log4perl qw(get_logger);
use List::MoreUtils qw(any);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_TREE_NODES => 1000;

sub initiate {
	my ($self) = @_;
	if ( $self->{'cgi'}->param('format') eq 'text' ) {
		$self->{'type'} = 'text';
	} else {
		$self->{$_} = 1 foreach qw(jQuery jQuery.tablesort jQuery.jstree);
	}
}

sub get_attributes {

	#override in subclass
	return \%;
}

sub get_option_list {

	#override in subclass
	return \@;
}

sub get_extra_form_elements {

	#override in subclass
	return '';
}

sub get_hidden_attributes {

	#override in subclass
	return \@;
}

sub get_plugin_javascript {

	#override in subclass
	return '';
}

sub run {

	#override in subclass
}

sub run_job {

	#used to run offline job
	#override in subclass
}

sub get_javascript {
	my ($self) = @_;
	my $plugin_name = $self->{'cgi'}->param('name');
	my $js;
	try {
		$js = $self->{'pluginManager'}->get_plugin($plugin_name)->get_plugin_javascript;
	}
	catch BIGSdb::InvalidPluginException with {
		$logger->error("Plugin $plugin_name does not exist");
	};
	$js .= <<"JS";
\$(document).ready(function() 
    { 
        \$("#sortTable").tablesorter({widgets:['zebra']});       
        \$("#tree").jstree({ 
			"core" : {
				"animation" : 200,
				"initially_open" : ["all_loci"],
				
			},
			"themes" : {
				"theme" : "default"
			},
			"plugins" : [ "themes", "html_data", "checkbox"],
			"checkbox" : {
				"real_checkboxes" : true,
				"real_checkboxes_names" : function (n) { return [(n[0].id || Math.ceil(Math.random() * 10000)), 1]; }
			}
		});

        // toggle: hide all elements with class onload
        \$('.toggle').hide();
        // capture clicks on the toggle links
        \$('.toggleLink').click(function() {
            \$(this).next('.toggle').toggle();
            return false;
        }); 
    } 
); 	
JS
	return $js;
}

sub get_query {
	my ( $self, $query_file ) = @_;
	my $qry;
	if ( !$query_file ) {
		$qry = "SELECT * FROM $self->{'system'}->{'view'} ORDER BY id";
	} else {
		if ( -e "$self->{'config'}->{'secure_tmp_dir'}/$query_file" ) {
			my $fh;
			if ( open( $fh, '<', "$self->{'config'}->{'secure_tmp_dir'}/$query_file" ) ) {
				$qry = <$fh>;
				close $fh;
			} else {
				if ( $self->{'cgi'}->param('format') eq 'text' ) {
					print "Can not open temporary file.\n";
				} else {
					print "<div class=\"box\" id=\"statusbad\"><p>Can not open temporary file.</p></div>\n";
				}
				$logger->error("can't open temporary file $query_file. $@");
				return;
			}
		} else {
			if ( $self->{'cgi'}->param('format') eq 'text' ) {
				print "The temporary file containing your query does not exist. Please repeat your query.\n";
			} else {
				print
"<div class=\"box\" id=\"statusbad\"><p>The temporary file containing your query does not exist. Please repeat your query.</p></div>\n";
			}
			return;
		}
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $view = $self->{'system'}->{'view'};
		$qry =~ s/([\s\(])datestamp/$1$view.datestamp/g;
		$qry =~ s/([\s\(])date_entered/$1$view.date_entered/g;
	}
	return \$qry;
}

sub create_temp_tables {
	my ( $self, $qry_ref ) = @_;
	my $qry      = $$qry_ref;
	my $format   = $self->{'cgi'}->param('format') || 'html';
	my $schemes  = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
	my $continue = 1;
	try {
		foreach (@$schemes) {
			if ( $qry =~ /temp_scheme_$_\s/ || $qry =~ /ORDER BY s_$_\_/ ) {
				$self->{'datastore'}->create_temp_scheme_table($_);
			}
		}
	}
	catch BIGSdb::DatabaseConnectionException with {
		if ( $format ne 'text' ) {
			print "<div class=\"box\" id=\"statusbad\"><p>Can not connect to remote database.  The query can not be performed.</p></div>\n";
		} else {
			print "Can not connect to remote database.  The query can not be performed.\n";
		}
		$continue = 0;
	};
	return $continue;
}

sub print_content {
	my ($self)      = @_;
	my $q           = $self->{'cgi'};
	my $plugin_name = $q->param('name');
	if ( !$self->{'pluginManager'}->is_plugin($plugin_name) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>This is not a valid plugin.</p></div>";
		return;
	}
	my $plugin;
	my $continue = 1;
	try {
		$plugin = $self->{'pluginManager'}->get_plugin($plugin_name);
	}
	catch BIGSdb::InvalidPluginException with {
		print "<div class=\"box\" id=\"statusbad\"><p>Plugin '$plugin_name' does not exist!</p></div>\n";
		$continue = 0;
	};
	my $att = $plugin->get_attributes;
	$plugin->{'username'} = $self->{'username'};
	my $dbtype = $self->{'system'}->{'dbtype'};
	if ( $att->{'dbtype'} !~ /$dbtype/ ) {
		print "<div class=\"box\" id=\"statusbad\"><p>This plugin is not compatible with this type of database ($dbtype).</p></div>\n";
		$continue = 0;
	}
	return if !$continue;
	my $option_list = $plugin->get_option_list();
	my $cookies_disabled;
	if ( @$option_list && $q->param('format') ne 'text' ) {
		if ( $q->param('update_options') ) {
			my $guid = $self->get_guid;
			if ($guid) {
				if ( $q->param('set') ) {
					foreach (@$option_list) {
						my $value;
						if ( $_->{'optlist'} ) {
							$value = $q->param( $_->{'name'} );
						} else {
							$value = $q->param( $_->{'name'} ) ? 'true' : 'false';
						}
						$self->{'prefstore'}->set_plugin_attribute( $guid, $self->{'system'}->{'db'}, $plugin_name, $_->{'name'}, $value );
					}
					$self->{'prefstore'}->update_datestamp($guid);
				} elsif ( $q->param('reset') ) {
					foreach (@$option_list) {
						$self->{'prefstore'}->delete_plugin_attribute( $guid, $self->{'system'}->{'db'}, $plugin_name, $_->{'name'} );
						my $value;
						if ( $_->{'optlist'} ) {
							$value = $_->{'default'};
						} else {
							$value = $_->{'default'} ? 'on' : 'off';
						}
						$q->param( $_->{'name'}, $value );
					}
				}
			} else {
				$cookies_disabled = 1;
			}
		}
		if ( !$cookies_disabled ) {
			my $att = $self->{'pluginManager'}->get_plugin_attributes($plugin_name);
			print $q->start_form;
			$q->param( 'update_options', 1 );
			print $q->hidden($_) foreach @{ $plugin->get_hidden_attributes() };
			print $q->hidden($_) foreach qw(page db name query_file update_options);
			print "<div id=\"hidefromnonJS\" class=\"hiddenbydefault\">\n";
			print "<div class=\"floatmenu\"><a id=\"toggle1\" class=\"showhide\">Show options</a>\n";
			print "<a id=\"toggle2\" class=\"hideshow\">Hide options</a></div>\n";
			print "<div class=\"hideshow\">\n";
			print "<div id=\"pluginoptions\"><table><tr><th>$att->{'name'} options</th></tr>\n";
			my $td   = 1;
			my $guid = $self->get_guid;

			foreach (@$option_list) {
				my $default;
				try {
					$default = $self->{'prefstore'}->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, $plugin_name, $_->{'name'} );
					if ( $default eq 'true' || $default eq 'false' ) {
						$default = $default eq 'true' ? 1 : 0;
					}
				}
				catch BIGSdb::DatabaseNoRecordException with {
					$default = $_->{'default'};
				};
				print "<tr class=\"td$td\"><td>\n";
				if ( $_->{'optlist'} ) {
					print $_->{'description'} . ': ';
					my @values = split /;/, $_->{'optlist'};
					print $q->popup_menu( -name => $_->{'name'}, -values => [@values], -default => $default );
				} else {
					print $q->checkbox( -name => $_->{'name'}, -label => $_->{'description'}, selected => $default );
				}
				print "</td></tr>\n";
				$td = $td == 1 ? 2 : 1;
			}
			print "<tr class=\"td$td\"><td style=\"text-align:center\">";
			print $q->submit( -name => 'reset', -label => 'Reset to defaults', -class => 'reset' );
			print $q->submit( -name => 'set',   -label => 'Set options',       -class => 'submit' );
			print "</td></tr>\n";
			print "</table></div>\n</div>\n</div>\n";
			print $q->end_form;
		} else {
			print "<div class=\"floatmenu\" >Options disabled (allow cookies to enable)</div>\n";
		}
	}
	$plugin->initiate_prefs;
	$plugin->run();
}

sub get_title {
	my ($self) = @_;
	my $desc        = $self->{'system'}->{'description'} || 'BIGSdb';
	my $plugin_name = $self->{'cgi'}->param('name');
	my $att         = $self->{'pluginManager'}->get_plugin_attributes($plugin_name);
	if ( $att->{'menutext'} ) {
		return "$att->{'menutext'} - $desc";
	}
	return $desc;
}

sub print_fields {
	my ( $self, $fields, $prefix, $num_columns, $trim_prefix, $labels, $default_select, $toggle ) = @_;
	my $q                 = $self->{'cgi'};
	my $fields_per_column = BIGSdb::Utils::round_up( @$fields / $num_columns );
	my @cols;
	my $i = 0;
	my $j = 0;
	foreach (@$fields) {
		$cols[$i][$j] = $_;
		$j++;
		if ( $j == $fields_per_column ) {
			$j = 0;
			$i++;
		}
	}
	$toggle = $toggle ? "class=\"toggle\"" : "";
	print "<table $toggle>";
	my $row = 0;
	do {
		print "<tr>";
		for ( my $i = 0 ; $i < $num_columns ; $i++ ) {
			last if !$cols[$i][$row];
			my $field = $cols[$i][$row];
			my $label = $labels->{$field} || $field;
			$label =~ s/^[lf]_// if $trim_prefix;
			$label =~ s/___/../;
			$label =~ tr/_/ /;
			my $id = $self->clean_checkbox_id("$prefix\_$field");
			print "<td style=\"padding-left:1em\">";
			my $value = $prefix eq 'c' ? 0 : $default_select;
			print $q->checkbox( -name => "$prefix\_$field", -id => $id, -checked => $value, -value => 'checked', -label => $label );
			print "</td>\n";
		}
		print "</tr>\n";
		$row++;
	} while ( $cols[0][$row] );
	print "</table>";
}

sub print_field_export_form {
	my ( $self, $default_select, $output_format_list, $options ) = @_;
	my $q       = $self->{'cgi'};
	my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes ORDER BY display_order,id");
	my $loci    = $self->{'datastore'}->get_loci_in_no_scheme;
	my $fields  = $self->{'xmlHandler'}->get_field_list;
	my @display_fields;
	my $extended = $options->{'extended_attributes'} ? $self->get_extended_attributes : undef;
	my ( @js, @js2, @isolate_js, @isolate_js2 );

	foreach (@$fields) {
		push @display_fields, $_;
		push @display_fields, 'aliases' if $_ eq $self->{'system'}->{'labelfield'};
		if ( $options->{'extended_attributes'} ) {
			my $extatt = $extended->{$_};
			if ( ref $extatt eq 'ARRAY' ) {
				foreach my $extended_attribute (@$extatt) {
					push @display_fields, "$_\_\_\_$extended_attribute";
				}
			}
		}
	}
	push @isolate_js,  @js;
	push @isolate_js2, @js2;
	foreach (@display_fields) {
		push @js,          "\$(\"#f_$_\").attr(\"checked\",true)";
		push @js2,         "\$(\"#f_$_\").attr(\"checked\",false)";
		push @isolate_js,  "\$(\"#f_$_\").attr(\"checked\",true)";
		push @isolate_js2, "\$(\"#f_$_\").attr(\"checked\",false)";
	}
	print $q->start_form;
	if ( ref $output_format_list eq 'ARRAY' && @$output_format_list ) {
		print "<p>Please select output format: ";
		print $q->popup_menu( -name => 'format', -values => $output_format_list );
		print "</p>\n";
	}
	print "<div class='fieldsection'>";
	print "<h2>Isolate fields</h2>\n";
	my %labels;
	$self->_print_all_none_buttons( \@isolate_js, \@isolate_js2, 'smallbutton rightbutton' );
	$self->print_fields( \@display_fields, 'f', 6, 0, \%labels, $default_select, 0 );
	print "</div>";
	if ($options->{'include_composites'}) {
		my $composites = $self->{'datastore'}->run_list_query("SELECT id FROM composite_fields ORDER BY id");
		if (@$composites) {
			my ( @com_js, @com_js2 );
			foreach (@$composites) {
				push @js,      "\$(\"#c_$_\").attr(\"checked\",true)";
				push @js2,     "\$(\"#c_$_\").attr(\"checked\",false)";
				push @com_js,  "\$(\"#c_$_\").attr(\"checked\",true)";
				push @com_js2, "\$(\"#c_$_\").attr(\"checked\",false)";
			}
			print "<div class='fieldsection'>";
			print "<h2>Composite fields ";
			print " <a class=\"tooltip\" title=\"Composite fields - These are constructed from combinations of other fields "
				 ."(some of which may come from external databases).  Including composite fields will slow down the processing.\">&nbsp;<i>i</i>&nbsp;</a>";
			print "</h2>\n";
			$self->_print_all_none_buttons( \@com_js, \@com_js2, 'smallbutton rightbutton' );
			$self->print_fields( $composites, 'c', 6, 0, \%labels, $default_select, 0 );
			print "</div>";
		}
	}
	my $total_loci = $self->{'datastore'}->get_loci( { 'analysis_pref' => 1 } );
	if ( @$total_loci <= MAX_TREE_NODES ) {
		print "<h2>Schemes and loci</h2>\n";
		$self->_print_tree(1);
	} else {
		my $qry    = "SELECT id,common_name FROM loci WHERE common_name IS NOT NULL";
		my $cn_sql = $self->{'db'}->prepare($qry);
		eval { $cn_sql->execute; };
		$logger->error($@) if $@;
		my $common_names = $cn_sql->fetchall_hashref('id');
		foreach (@$schemes) {
			my $scheme_members = $self->{'datastore'}->get_scheme_loci($_);
			my $scheme_fields  = $self->{'datastore'}->get_scheme_fields($_);
			my $scheme_info    = $self->{'datastore'}->get_scheme_info($_);
			if ( @$scheme_members or @$scheme_fields ) {
				( my $heading = $scheme_info->{'description'} ) =~ s/\&/\&amp;/g;
				print "<div class='fieldsection'>";
				print "<h2>$heading</h2>\n";
				my @values;
				my $labels;
				my ( @scheme_js, @scheme_js2 );
				foreach my $member (@$scheme_members) {
					my $cleaned_member = $self->clean_checkbox_id($member);
					push @values,     "l_$member";
					push @js,         "\$(\"#s_$_\_l_$cleaned_member\").attr(\"checked\",true)";
					push @js2,        "\$(\"#s_$_\_l_$cleaned_member\").attr(\"checked\",false)";
					push @scheme_js,  "\$(\"#s_$_\_l_$cleaned_member\").attr(\"checked\",true)";
					push @scheme_js2, "\$(\"#s_$_\_l_$cleaned_member\").attr(\"checked\",false)";
					$labels->{"l_$member"} = "$member ($common_names->{$member}->{'common_name'})"
					  if $common_names->{$member}->{'common_name'};
				}
				foreach my $scheme_field (@$scheme_fields) {
					push @values,     "f_$scheme_field";
					push @js,         "\$(\"#s_$_\_f_$scheme_field\").attr(\"checked\",true)";
					push @js2,        "\$(\"#s_$_\_f_$scheme_field\").attr(\"checked\",false)";
					push @scheme_js,  "\$(\"#s_$_\_f_$scheme_field\").attr(\"checked\",true)";
					push @scheme_js2, "\$(\"#s_$_\_f_$scheme_field\").attr(\"checked\",false)";
				}
				$self->_print_all_none_buttons( \@scheme_js, \@scheme_js2, 'smallbutton rightbutton' );
				print "<input type=\"button\" value=\"Show/Hide List\" class=\"toggleLink smallbutton rightbutton\" />\n";
				$self->print_fields( \@values, "s_$_", 10, 1, $labels, $default_select, 1 );
				print "</div>";
			}
		}
		if (@$loci) {
			print "<div class='fieldsection'>";
			print "<h2>Loci not belonging to any scheme</h2>\n";
			my ( @scheme_js, @scheme_js2 );
			foreach (@$loci) {
				my $cleaned = $self->clean_checkbox_id($_);
				push @js,         "\$(\"#l_$cleaned\").attr(\"checked\",true)";
				push @js2,        "\$(\"#l_$cleaned\").attr(\"checked\",false)";
				push @scheme_js,  "\$(\"#l_$cleaned\").attr(\"checked\",true)";
				push @scheme_js2, "\$(\"#l_$cleaned\").attr(\"checked\",false)";
			}
			my %labels;
			$self->_print_all_none_buttons( \@scheme_js, \@scheme_js2, 'smallbutton rightbutton' );
			print "<input type=\"button\" value=\"Show/Hide List\" class=\"toggleLink smallbutton rightbutton\" />\n";
			$self->print_fields( $loci, 'l', 12, 0, \%labels, $default_select, 1 );
			print "</div>";
		}
		$" = ';';
		print "<input type=\"button\" value=\"Select all\" onclick='@js' style=\"margin-top:1em\" class=\"button\" />\n";
		print "<input type=\"button\" value=\"Select none\" onclick='@js2' style=\"margin-top:1em\" class=\"button\" />\n";
		print "<noscript><span class=\"comment\"> Enable javascript for select buttons to work!</span></noscript>\n";
	}
	print $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
	print $q->hidden($_) foreach qw (db page name query_file);
	print $q->end_form;
}

sub get_selected_fields {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $fields   = $self->{'xmlHandler'}->get_field_list;
	my $extended = $self->get_extended_attributes;
	my @display_fields;
	$self->escape_params;

	foreach (@$fields) {
		push @display_fields, $_;
		push @display_fields, 'aliases' if $_ eq $self->{'system'}->{'labelfield'};
		my $extatt = $extended->{$_};
		if ( ref $extatt eq 'ARRAY' ) {
			foreach my $extended_attribute (@$extatt) {
				push @display_fields, "$_\_\_\_$extended_attribute";
			}
		}
	}
	my $loci       = $self->{'datastore'}->get_loci_in_no_scheme;
	my $composites = $self->{'datastore'}->run_list_query("SELECT id FROM composite_fields");
	my $schemes    = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
	my @fields_selected;
	foreach (@display_fields) {
		push @fields_selected, "f_$_" if $q->param("f_$_");
	}
	foreach (@$composites) {
		push @fields_selected, "c_$_" if $q->param("c_$_");
	}
	foreach (@$schemes) {
		my $scheme_members = $self->{'datastore'}->get_scheme_loci($_);
		foreach my $member (@$scheme_members) {
			push @fields_selected, "s_$_\_l_$member"
			  if $q->param("s_$_\_l_$member");
		}
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($_);
		foreach my $scheme_field (@$scheme_fields) {
			push @fields_selected, "s_$_\_f_$scheme_field"
			  if $q->param("s_$_\_f_$scheme_field");
		}
	}
	foreach (@$loci) {
		push @fields_selected, "l_$_" if $q->param("l_$_");
	}
	return \@fields_selected;
}

sub print_sequence_export_form {
	my ( $self, $pk, $list, $scheme_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	print $q->start_form;
	print "<fieldset style=\"float:left\">\n<legend>Select $pk" . "s</legend>\n";
	$" = "\n";
	print
"<p style=\"padding-right:2em\">Paste in list of ids to include, start a new<br />line for each.  Leave blank to include all ids.</p>\n";
	print $q->textarea( -name => 'list', -rows => 5, -columns => 6, -default => "@$list" );
	print "</fieldset>\n";

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		print "<fieldset style=\"float:left\">\n<legend>Include in identifier row</legend>";
		my @fields;
		my $labels;
		foreach my $field ( @{ $self->{'xmlHandler'}->get_field_list } ) {
			next if any { $field eq $_ } qw (id datestamp date_entered curator sender);
			push @fields, $field;
			( $labels->{$field} = $field ) =~ tr/_/ /;
		}
		print $q->scrolling_list(
			-name     => 'includes',
			-id       => 'includes',
			-values   => \@fields,
			-labels   => $labels,
			-size     => 10,
			-multiple => 'true'
		);
		print "</fieldset>\n";
		my $options_heading = $options->{'options_heading'} || 'Options';
		print "<fieldset style=\"float:left\">\n<legend>$options_heading</legend>";
		print "If both allele designations and tagged sequences<br />exist for a locus, choose how you want these handled: ";
		print
" <a class=\"tooltip\" title=\"Sequence retrieval - Peptide loci will only be retrieved from the sequence bin (as nucleotide sequences).\">&nbsp;<i>i</i>&nbsp;</a>";
		print "<br /><br />";
		my %labels = (
			'seqbin'             => 'Use sequences tagged from the bin',
			'allele_designation' => 'Use allele sequence retrieved from external database'
		);
		print $q->radio_group( -name => 'chooseseq', -values => [ 'seqbin', 'allele_designation' ], -labels => \%labels,
			-linebreak => 'true' );
		print "<br />\n";
		print $q->checkbox( -name => 'translate', -label => 'Translate sequences' ) if $options->{'translate'};
		print $q->checkbox( -name => 'ignore_seqflags', -label => 'Do not include sequences with problem flagged', -checked => 'checked' )
		  if $options->{'ignore_seqflags'};
		print "</fieldset>\n";
	}
	print $self->get_extra_form_elements;
	my $loci = $self->{'datastore'}->get_loci( { 'analysis_pref' => 1 } );
	if ( !$scheme_id && @$loci <= MAX_TREE_NODES ) {

		#There are currently performance issues with the hierarchical Javascript tree, so don't display it once
		#the number of loci go over a certain threshold.
		$self->_print_tree;
	} else {
		my ( @js, @js2 );
		my $schemes;
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			$schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes ORDER BY display_order,id");
		} else {
			push @$schemes, $scheme_id || 0;
		}
		my $qry    = "SELECT id,common_name FROM loci WHERE common_name IS NOT NULL";
		my $cn_sql = $self->{'db'}->prepare($qry);
		eval { $cn_sql->execute; };
		$logger->error($@) if $@;
		my $common_names = $cn_sql->fetchall_hashref('id');
		print "<div style=\"clear:both\">\n";
		foreach my $scheme_id (@$schemes) {
			my ( @scheme_js, @scheme_js2 );
			my $scheme_members = $self->{'datastore'}->get_scheme_loci($scheme_id);
			my $scheme_info    = $self->{'datastore'}->get_scheme_info($scheme_id);
			if (@$scheme_members) {
				( my $heading = $scheme_info->{'description'} ) =~ s/\&/\&amp;/g;
				print "<div class='fieldsection'>";
				print "<h2>$heading</h2>\n";
				my @values;
				my $labels;
				foreach my $member (@$scheme_members) {
					my $cleaned_member = $self->clean_checkbox_id($member);
					push @values,     "l_$member";
					push @js,         "\$(\"#s_$scheme_id\_l_$cleaned_member\").attr(\"checked\",true)";
					push @js2,        "\$(\"#s_$scheme_id\_l_$cleaned_member\").attr(\"checked\",false)";
					push @scheme_js,  "\$(\"#s_$scheme_id\_l_$cleaned_member\").attr(\"checked\", true)";
					push @scheme_js2, "\$(\"#s_$scheme_id\_l_$cleaned_member\").attr(\"checked\", false)";
					$labels->{"l_$member"} = "$member ($common_names->{$member}->{'common_name'})"
					  if $common_names->{$member}->{'common_name'};
				}
				if (!$q->param('scheme_id')){
					$self->_print_all_none_buttons( \@scheme_js, \@scheme_js2, 'smallbutton rightbutton' );
					print "<input type=\"button\" value=\"Show/Hide List\" class=\"toggleLink smallbutton rightbutton\" />\n";
				}
				$self->print_fields( \@values, "s_$scheme_id", 10, 1, $labels, $options->{'default_select'}, $q->param('scheme_id') ? 0 : 1 );
				print "</div>";
			}
		}
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			my $loci =
			  $self->{'datastore'}->run_list_query(
"SELECT id FROM loci WHERE id NOT IN (SELECT DISTINCT locus FROM scheme_members) AND (id IN (SELECT DISTINCT locus FROM allele_designations LEFT JOIN loci ON allele_designations.locus = loci.id AND loci.data_type = 'DNA' AND loci.dbase_name IS NOT NULL AND loci.dbase_id_field IS NOT NULL AND loci.dbase_seq_field IS NOT NULL) OR id IN (SELECT DISTINCT locus FROM allele_sequences)) ORDER BY id"
			  );
			if (@$loci) {
				print "<div class='fieldsection'>";
				print "<h2>Loci not belonging to any scheme</h2>\n";
				my ( @scheme_js, @scheme_js2 );
				foreach (@$loci) {
					my $cleaned = $self->clean_checkbox_id($_);
					push @js,         "\$(\"#l_$cleaned\").attr(\"checked\",true)";
					push @js2,        "\$(\"#l_$cleaned\").attr(\"checked\",false)";
					push @scheme_js,  "\$(\"#l_$cleaned\").attr(\"checked\",true)";
					push @scheme_js2, "\$(\"#l_$cleaned\").attr(\"checked\",false)";
				}
				my %labels;
				$self->_print_all_none_buttons( \@scheme_js, \@scheme_js2, 'smallbutton rightbutton' );
				print "<input type=\"button\" value=\"Show/Hide List\" class=\"toggleLink smallbutton rightbutton\" />\n";
				$self->print_fields( $loci, 'l', 12, 0, \%labels, $options->{'default_select'}, 1 );
				print "</div>";
			}
		}
		$" = ';';
		print "</div>\n";
		print "<input type=\"button\" value=\"Select all\" onclick='@js' style=\"margin-top:1em\" class=\"button\" />\n";
		print "<input type=\"button\" value=\"Select none\" onclick='@js2' style=\"margin-top:1em\" class=\"button\" />\n";
		print "<noscript><span class=\"comment\"> Enable javascript for select buttons to work!</span></noscript>\n";
	}
	print $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
	print $q->hidden($_) foreach qw (db page name query_file scheme_id);
	print $q->end_form;
}

sub _print_tree {
	my ( $self, $include_scheme_fields ) = @_;
	print "<p style=\"clear:both\">Click within the tree to select loci belonging to schemes or groups of schemes.</p>
	<p>If the tree is slow to update, you can try modifying your locus and
	scheme preferences by setting 'analysis' to false for any <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=schemes\">schemes</a>
	 or <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=loci\">loci</a> for which you do not plan to use in analysis tools.</p>\n";
	print "<noscript><p class=\"highlight\">Javascript needs to be enabled.</p></noscript>\n";
	print "<div id=\"tree\" class=\"tree\">\n";
	my $options = { 'no_link_out' => 1, 'list_loci' => 1, 'analysis_pref' => 1 };
	$options->{'scheme_fields'} = 1 if $include_scheme_fields;
	print $self->get_tree( undef, $options );
	print "</div>\n";
}

sub _print_all_none_buttons {
	my ( $self, $js1, $js2, $class, $prefix ) = @_;
	if ( ref $js1 && ref $js2 ) {
		print "<input type=\"button\" value=\"". $prefix ."None\" class=\"$class\" onclick='@$js2' />\n";
		print "<input type=\"button\" value=\"". $prefix ."All\" class=\"$class\" onclick='@$js1' />\n";
	}
}

1;
