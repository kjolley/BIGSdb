#Written by Keith Jolley
#Copyright (c) 2010-2013, University of Oxford
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
use warnings;
use 5.010;
use parent qw(BIGSdb::TreeViewPage);
use Error qw(:try);
use Log::Log4perl qw(get_logger);
use List::MoreUtils qw(any);
use BIGSdb::Page qw(FLANKING LOCUS_PATTERN);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_TREE_NODES => 1000;

sub initiate {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	$q->param( 'format', 'html' ) if !defined $q->param('format');
	if ( $q->param('format') eq 'text' ) {
		$self->{'type'} = 'text';
	} else {
		$self->{$_} = 1 foreach qw(jQuery jQuery.tablesort jQuery.jstree jQuery.slimbox);
	}
	$self->{'noCache'} = 1 if ( $self->{'system'}->{'sets'} // '' ) eq 'yes';
	return;
}

sub get_attributes {

	#override in subclass
	return \%;;
}

sub get_option_list {

	#override in subclass
	return \@;;
}

sub get_extra_form_elements {

	#override in subclass
	return '';
}

sub get_extra_fields {

	#override in subclass
	return '';
}

sub get_hidden_attributes {

	#override in subclass
	return \@;;
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
	my ( $js, $tree_js );
	try {
		$js = $self->{'pluginManager'}->get_plugin($plugin_name)->get_plugin_javascript;
		my $requires = $self->{'pluginManager'}->get_plugin($plugin_name)->get_attributes->{'requires'};
		if ($requires) {
			$tree_js = $requires =~ /js_tree/ ? $self->get_tree_javascript( { checkboxes => 1, check_schemes => 1 } ) : '';
		} else {
			$tree_js = '';
		}
	}
	catch BIGSdb::InvalidPluginException with {
		my $message = $plugin_name ? "Plugin $plugin_name does not exist." : 'Plugin name not called.';
		$tree_js = '';
		$logger->warn($message);
	};
	$js .= <<"JS";
function listbox_selectall(listID, isSelect) {
	var listbox = document.getElementById(listID);
	for(var count=0; count < listbox.options.length; count++) {
		listbox.options[count].selected = isSelect;
	}
}

\$(document).ready(function() 
    { 
        \$("#sortTable").tablesorter({widgets:['zebra']});       
    } 
); 	
$tree_js
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
					say "Can not open temporary file.";
				} else {
					say "<div class=\"box\" id=\"statusbad\"><p>Can not open temporary file.</p></div>";
				}
				$logger->error("can't open temporary file $query_file. $@");
				return;
			}
		} else {
			if ( $self->{'cgi'}->param('format') eq 'text' ) {
				say "The temporary file containing your query does not exist. Please repeat your query.";
			} else {
				say "<div class=\"box\" id=\"statusbad\"><p>The temporary file containing your query does not exist. "
				  . "Please repeat your query.</p></div>";
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
			say "<div class=\"box\" id=\"statusbad\"><p>Can not connect to remote database.  The query can not be performed.</p></div>";
		} else {
			say "Can not connect to remote database.  The query can not be performed.";
		}
		$logger->error("Can't connect to remote database.");
		$continue = 0;
	};
	return $continue;
}

sub print_content {
	my ($self)      = @_;
	my $q           = $self->{'cgi'};
	my $plugin_name = $q->param('name');
	if ( !$self->{'pluginManager'}->is_plugin($plugin_name) ) {
		my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
		say "<h1>$desc</h1>";
		say "<div class=\"box\" id=\"statusbad\"><p>Invalid (or no) plugin called.</p></div>";
		return;
	}
	my $plugin;
	my $continue = 1;
	try {
		$plugin = $self->{'pluginManager'}->get_plugin($plugin_name);
	}
	catch BIGSdb::InvalidPluginException with {
		say "<div class=\"box\" id=\"statusbad\"><p>Plugin '$plugin_name' does not exist!</p></div>";
		$continue = 0;
	};
	my $att = $plugin->get_attributes;
	$plugin->{'username'} = $self->{'username'};
	my $dbtype = $self->{'system'}->{'dbtype'};
	if ( $att->{'dbtype'} !~ /$dbtype/ ) {
		say "<div class=\"box\" id=\"statusbad\"><p>This plugin is not compatible with this type of database ($dbtype).</p></div>";
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
			say $q->start_form;
			$q->param( 'update_options', 1 );
			say $q->hidden($_) foreach @{ $plugin->get_hidden_attributes() };
			say $q->hidden($_) foreach qw(page db name query_file update_options);
			say "<div id=\"hidefromnonJS\" class=\"hiddenbydefault\">";
			say "<div class=\"floatmenu\"><a id=\"toggle1\" class=\"showhide\">Show options</a>";
			say "<a id=\"toggle2\" class=\"hideshow\">Hide options</a></div>";
			say "<div class=\"hideshow\">";
			say "<div id=\"pluginoptions\"><table><tr><th>$att->{'name'} options</th></tr>";
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
				say "<tr class=\"td$td\"><td>";
				if ( $_->{'optlist'} ) {
					print $_->{'description'} . ': ';
					my @values = split /;/, $_->{'optlist'};
					say $q->popup_menu( -name => $_->{'name'}, -values => [@values], -default => $default );
				} else {
					say $q->checkbox( -name => $_->{'name'}, -label => $_->{'description'}, selected => $default );
				}
				say "</td></tr>";
				$td = $td == 1 ? 2 : 1;
			}
			say "<tr class=\"td$td\"><td style=\"text-align:center\">";
			say $q->submit( -name => 'reset', -label => 'Reset to defaults', -class => 'reset' );
			say $q->submit( -name => 'set',   -label => 'Set options',       -class => 'submit' );
			say "</td></tr>";
			say "</table></div>\n</div>\n</div>";
			say $q->end_form;
		} else {
			say "<div class=\"floatmenu\" >Options disabled (allow cookies to enable)</div>";
		}
	}
	$plugin->initiate_prefs;
	$plugin->initiate_view( $self->{'username'}, $self->{'curate'} );
	$plugin->run;
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc        = $self->get_db_description || 'BIGSdb';
	my $plugin_name = $self->{'cgi'}->param('name');
	my $att         = $self->{'pluginManager'}->get_plugin_attributes($plugin_name);
	if ( $att->{'menutext'} ) {
		return "$att->{'menutext'} - $desc";
	}
	return $desc;
}

sub print_fields {
	my ( $self, $fields, $prefix, $num_columns, $trim_prefix, $labels, $default_select ) = @_;
	my $q                 = $self->{'cgi'};
	my $fields_per_column = BIGSdb::Utils::round_up( @$fields / $num_columns );
	say "<div style=\"float:left;margin-bottom:1em\"><ul>";
	my $i = 0;
	foreach my $field (@$fields) {
		my $label = $labels->{$field} || $field;
		$label =~ s/^[lf]_// if $trim_prefix;
		$label =~ s/___/../;
		$label =~ s/^meta_[^:]+://;
		$label =~ tr/_/ /;
		my $id = $self->clean_checkbox_id("$prefix\_$field");
		print "<li>";
		print $q->checkbox( -name => "$prefix\_$field", -id => $id, -checked => $default_select, -value => 'checked', -label => $label );
		say "</li>";
		$i++;

		if ( $i == $fields_per_column && $field ne $fields->[-1] ) {
			$i = 0;
			say "</ul></div><div style=\"float:left;margin-bottom:1em\"><ul>";
		}
	}
	say "</ul></div>";
	say "<div style=\"clear:both\"></div>";
	return;
}

sub print_field_export_form {
	my ( $self, $default_select, $options ) = @_;
	my $q             = $self->{'cgi'};
	my $set_id        = $self->get_set_id;
	my $schemes       = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	my $loci          = $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $fields        = $self->{'xmlHandler'}->get_field_list($metadata_list);
	my @display_fields;
	my $extended = $options->{'extended_attributes'} ? $self->get_extended_attributes : undef;
	my ( @js, @js2, @isolate_js, @isolate_js2 );

	foreach my $field (@$fields) {
		push @display_fields, $field;
		push @display_fields, 'aliases' if $field eq $self->{'system'}->{'labelfield'};
		if ( $options->{'extended_attributes'} ) {
			my $extatt = $extended->{$field};
			if ( ref $extatt eq 'ARRAY' ) {
				foreach my $extended_attribute (@$extatt) {
					push @display_fields, "$field\_\_\_$extended_attribute";
				}
			}
		}
	}
	push @isolate_js,  @js;
	push @isolate_js2, @js2;
	foreach my $field (@display_fields) {
		( my $id = "f_$field" ) =~ tr/:/_/;
		push @js,          "\$(\"#$id\").attr(\"checked\",true)";
		push @js2,         "\$(\"#$id\").attr(\"checked\",false)";
		push @isolate_js,  "\$(\"#$id\").attr(\"checked\",true)";
		push @isolate_js2, "\$(\"#$id\").attr(\"checked\",false)";
	}
	say $q->start_form;
	say "<fieldset style=\"float:left\"><legend>Isolate fields</legend>";
	my %labels;
	$self->print_fields( \@display_fields, 'f', 3, 0, \%labels, $default_select );
	$self->_print_all_none_buttons( \@isolate_js, \@isolate_js2, 'smallbutton' );
	say "</fieldset>";
	if ( $options->{'include_composites'} ) {
		my $composites = $self->{'datastore'}->run_list_query("SELECT id FROM composite_fields ORDER BY id");
		if (@$composites) {
			my ( @com_js, @com_js2 );
			foreach (@$composites) {
				push @js,      "\$(\"#c_$_\").attr(\"checked\",true)";
				push @js2,     "\$(\"#c_$_\").attr(\"checked\",false)";
				push @com_js,  "\$(\"#c_$_\").attr(\"checked\",true)";
				push @com_js2, "\$(\"#c_$_\").attr(\"checked\",false)";
			}
			print "<fieldset style=\"float:left\"><legend>Composite fields";
			print " <a class=\"tooltip\" title=\"Composite fields - These are constructed from combinations of other fields "
			  . "(some of which may come from external databases).  Including composite fields will slow down the processing.\">&nbsp;<i>i</i>&nbsp;</a>";
			say "</legend>";
			$self->print_fields( $composites, 'c', 1, 0, \%labels, 0 );
			$self->_print_all_none_buttons( \@com_js, \@com_js2, 'smallbutton' );
			say "</fieldset>";
		}
	}
	$self->get_extra_fields;
	$self->print_isolates_locus_fieldset;
	$self->print_scheme_fieldset( { fields_or_loci => 1 } );
	say "<div style=\"clear:both\"></div>";
	say "<div style=\"text-align:right;padding-right:10em\">";
	say $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
	say "</div>";
	say $q->hidden($_) foreach qw (db page name query_file);
	say $q->end_form;
	return;
}

sub set_offline_view {
	my ( $self, $params ) = @_;
	my $set_id = $params->{'set_id'};
	if ( ( $self->{'system'}->{'view'} // '' ) eq 'isolates' && $set_id ) {
		my $view_ref = $self->{'datastore'}->run_simple_query( "SELECT view FROM set_view WHERE set_id=?", $set_id );
		$self->{'system'}->{'view'} = $view_ref->[0] if ref $view_ref eq 'ARRAY';
	}
	return;
}

sub get_id_list {
	my ( $self, $pk, $query_file ) = @_;
	my $q = $self->{'cgi'};
	my $list;
	if ( $q->param('list') ) {
		foreach ( split /\n/, $q->param('list') ) {
			chomp;
			push @$list, $_;
		}
	} elsif ($query_file) {
		my $qry_ref = $self->get_query($query_file);
		return if ref $qry_ref ne 'SCALAR';
		return if !$self->create_temp_tables($qry_ref);
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			my $view = $self->{'system'}->{'view'};
			$$qry_ref =~ s/SELECT ($view\.\*|\*)/SELECT $pk/;
			$self->rewrite_query_ref_order_by($qry_ref);
		}
		$list = $self->{'datastore'}->run_list_query($$qry_ref);
	} else {
		$list = \@;;
	}
	return $list;
}

sub get_selected_fields {
	my ($self)        = @_;
	my $q             = $self->{'cgi'};
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $fields        = $self->{'xmlHandler'}->get_field_list($metadata_list);
	my $extended      = $self->get_extended_attributes;
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
	my $loci       = $self->{'datastore'}->get_loci( { set_id => $set_id } );
	my $composites = $self->{'datastore'}->run_list_query("SELECT id FROM composite_fields");
	my $schemes    = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
	my @fields_selected;
	foreach (@display_fields) {
		push @fields_selected, "f_$_" if $q->param("f_$_");
	}
	foreach (@$composites) {
		push @fields_selected, "c_$_" if $q->param("c_$_");
	}
	my %picked;
	foreach (@$schemes) {
		my $scheme_members = $self->{'datastore'}->get_scheme_loci($_);
		foreach my $member (@$scheme_members) {
			push @fields_selected, "s_$_\_l_$member"
			  if $q->param("s_$_") && $q->param('scheme_members');
		}
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($_);
		foreach my $scheme_field (@$scheme_fields) {
			push @fields_selected, "s_$_\_f_$scheme_field"
			  if $q->param("s_$_") && $q->param('scheme_fields');
		}
	}
	my $selected_loci = $self->get_selected_loci;
	foreach my $locus (@$loci) {
		push @fields_selected, "l_$locus" if any { $locus eq $_ } @$selected_loci;
	}
	return \@fields_selected;
}

sub print_sequence_export_form {
	my ( $self, $pk, $list, $scheme_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	say $q->start_form;
	say "<fieldset style=\"float:left\">\n<legend>Select $pk" . "s</legend>";
	local $" = "\n";
	say "<p style=\"padding-right:2em\">Paste in list of ids to include, start a new<br />line for each. "
	  . "Leave blank to include all ids.</p>";
	say $q->textarea( -name => 'list', -rows => 5, -columns => 6, -default => "@$list" );
	say "</fieldset>";
	my ( $locus_list, $locus_labels ) =
	  $self->get_field_selection_list( { loci => 1, analysis_pref => 1, query_pref => 0, sort_labels => 1 } );

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say "<fieldset style=\"float:left\">\n<legend>Include in identifier row</legend>";
		my @fields;
		my $labels;
		my $set_id        = $self->get_set_id;
		my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
		my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
		foreach my $field (@$field_list) {
			next if any { $field eq $_ } qw (id datestamp date_entered curator sender);
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			push @fields, $field;
			( $labels->{$field} = $metafield // $field ) =~ tr/_/ /;
		}
		say $q->scrolling_list(
			-name     => 'includes',
			-id       => 'includes',
			-values   => \@fields,
			-labels   => $labels,
			-size     => 10,
			-multiple => 'true'
		);
		say "</fieldset>";
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->print_isolates_locus_fieldset;
		$self->print_scheme_fieldset;
	} else {
		$self->print_scheme_locus_fieldset( $scheme_id, $options );
	}
	if ( !$options->{'no_options'} ) {
		my $options_heading = $options->{'options_heading'} || 'Options';
		say "<fieldset style=\"float:left\">\n<legend>$options_heading</legend>";
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			say "If both allele designations and tagged sequences<br />exist for a locus, choose how you want these handled: ";
			say " <a class=\"tooltip\" title=\"Sequence retrieval - Peptide loci will only be retrieved from the sequence bin "
			  . "(as nucleotide sequences).\">&nbsp;<i>i</i>&nbsp;</a>";
			say "<br /><br />";
			my %labels = (
				seqbin             => 'Use sequences tagged from the bin',
				allele_designation => 'Use allele sequence retrieved from external database'
			);
			say $q->radio_group(
				-name      => 'chooseseq',
				-values    => [ 'seqbin', 'allele_designation' ],
				-labels    => \%labels,
				-linebreak => 'true'
			);
			say "<br />";
			if ( $options->{'ignore_seqflags'} ) {
				say $q->checkbox(
					-name    => 'ignore_seqflags',
					-label   => 'Do not include sequences with problem flagged ' . '(defined alleles will still be used)',
					-checked => 'checked'
				);
				say "<br />";
			}
			if ( $options->{'ignore_incomplete'} ) {
				say $q->checkbox( -name => 'ignore_incomplete', -label => 'Do not include incomplete sequences', -checked => 'checked' );
				say "<br />";
			}
			if ( $options->{'flanking'} ) {
				say "Include ";
				say $q->popup_menu( -name => 'flanking', -values => [FLANKING], -default => 0 );
				say " bp flanking sequence";
				say " <a class=\"tooltip\" title=\"Flanking sequence - This can only be included if you select to retrieve sequences "
				  . "from the sequence bin rather than from an external database.\">&nbsp;<i>i</i>&nbsp;</a>";
				say "<br />";
			}
		}
		if ( $options->{'translate'} ) {
			say $q->checkbox( -name => 'translate', -label => 'Translate sequences' );
			say "<br />";
		}
		if ( $options->{'in_frame'} ) {
			say $q->checkbox( -name => 'in_frame', -label => 'Concatenate in frame' );
			say "<br />";
		}
		say "</fieldset>";
	}
	say $self->get_extra_form_elements;
	say "<div style=\"clear:both\"></div>";
	say $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
	say $q->hidden($_) foreach qw (db page name query_file scheme_id);
	say $q->end_form;
	return;
}

sub print_seqbin_isolate_fieldset {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	my ( $ids, $labels ) = $self->get_isolates_with_seqbin($options);
	say "<fieldset style=\"float:left\">\n<legend>Isolates</legend>";
	say $q->scrolling_list(
		-name     => 'isolate_id',
		-id       => 'isolate_id',
		-values   => $ids,
		-labels   => $labels,
		-size     => 8,
		-multiple => 'true',
		-default  => $options->{'selected_ids'}
	);
	print <<"HTML";
<div style="text-align:center"><input type="button" onclick='listbox_selectall("isolate_id",true)' value="All" style="margin-top:1em" class="smallbutton" />
<input type="button" onclick='listbox_selectall("isolate_id",false)' value="None" style="margin-top:1em" class="smallbutton" /></div>
</fieldset>
HTML
	return;
}

sub print_isolates_locus_fieldset {
	my ($self) = @_;
	say "<fieldset id=\"locus_fieldset\" style=\"float:left\">\n<legend>Loci</legend>";
	my ( $locus_list, $locus_labels ) =
	  $self->get_field_selection_list( { loci => 1, analysis_pref => 1, query_pref => 0, sort_labels => 1 } );
	if (@$locus_list) {
		print $self->{'cgi'}->scrolling_list(
			-name     => 'locus',
			-id       => 'locus',
			-values   => $locus_list,
			-labels   => $locus_labels,
			-size     => 8,
			-multiple => 'true'
		);
		print <<"HTML";
<div style="text-align:center"><input type="button" onclick='listbox_selectall("locus",true)' value="All" style="margin-top:1em" class="smallbutton" />
<input type="button" onclick='listbox_selectall("locus",false)' value="None" style="margin-top:1em" class="smallbutton" /></div>
HTML
	} else {
		print "No loci available<br />for analysis";
	}
	say "</fieldset>";
	return;
}

sub print_scheme_locus_fieldset {
	my ( $self, $scheme_id, $options ) = @_;
	my ( @scheme_js, @scheme_js2 );
	my $locus_list = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $set_id     = $self->get_set_id;
	my %labels;
	( $labels{$_} = $self->{'datastore'}->get_set_locus_label( $_, $set_id ) ) foreach (@$locus_list);
	say "<fieldset><legend>Select loci</legend>";
	if (@$locus_list) {
		print $self->{'cgi'}->scrolling_list(
			-name     => 'locus',
			-id       => 'locus',
			-values   => $locus_list,
			-labels   => \%labels,
			-size     => 8,
			-multiple => 'true'
		);
		print <<"HTML";
<div style="text-align:center"><input type="button" onclick='listbox_selectall("locus",true)' 
value="All" style="margin-top:1em" class="smallbutton" />
<input type="button" onclick='listbox_selectall("locus",false)' value="None" style="margin-top:1em" 
class="smallbutton" /></div>
HTML
	} else {
		say "No loci available<br />for analysis";
	}
	say "</fieldset>";
	return;
}

sub print_scheme_fieldset {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	print <<"HTML";
<fieldset id="scheme_fieldset" style="float:left"><legend>Schemes</legend>
<noscript><p class="highlight">Enable Javascript to select schemes.</p></noscript>
<div id="tree" class="tree" style="height:150px; width:20em">
HTML
	say $self->get_tree( undef, { no_link_out => 1, select_schemes => 1 } );
	say "</div>";
	if ( $options->{'fields_or_loci'} ) {
		say "<div style=\"padding-top:1em\"><ul><li>";
		say $q->checkbox( -name => 'scheme_fields', -label => 'Include all fields from selected schemes', -checked => 1 );
		say "</li><li>";
		say $q->checkbox( -name => 'scheme_members', -label => 'Include all loci from selected schemes', -checked => 1 );
		say "</li></ul></div>";
	}
	say "</fieldset>\n";
	return;
}

sub print_sequence_filter_fieldset {
	my ($self, $options) = @_;
	$options = {} if ref $options ne 'HASH';
	say "<fieldset style=\"float:left\"><legend>Restrict included sequences by</legend><ul>";
	my $buffer = $self->get_sequence_method_filter( { class => 'parameter' } );
	say "<li>$buffer</li>" if $buffer;
	$buffer = $self->get_project_filter( { class => 'parameter' } );
	say "<li>$buffer</li>" if $buffer;
	$buffer = $self->get_experiment_filter( { class => 'parameter' } );
	say "<li>$buffer</li>" if $buffer;
	if ($options->{'min_length'}){
		$buffer = $self->get_filter(
			'min_length',
			[qw (100 200 500 1000 2000 5000 10000 20000 50000 100000)],
			{
				text    => 'Minimum length',
				tooltip => 'minimum length filter - Only include sequences that are longer or equal to the specified length.',
				class   => 'parameter'
			}
		);
		say "<li>$buffer</li>";
	}
	say "</ul>\n</fieldset>\n";
	return;
}

sub filter_ids_by_project {
	my ( $self, $ids, $project_id ) = @_;
	return $ids if !$project_id;
	my $ids_in_project = $self->{'datastore'}->run_list_query( "SELECT isolate_id FROM project_members WHERE project_id = ?", $project_id );
	my @filtered_ids;
	foreach my $id (@$ids) {
		push @filtered_ids, $id if any { $id eq $_ } @$ids_in_project;
	}
	return \@filtered_ids;
}

sub get_selected_loci {
	my ($self) = @_;
	$self->escape_params;
	my @loci = $self->{'cgi'}->param('locus');
	my @loci_selected;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $pattern = LOCUS_PATTERN;
		foreach my $locus (@loci) {
			my $locus_name = $locus =~ /$pattern/ ? $1 : undef;
			push @loci_selected, "$locus_name" if defined $locus_name;
		}
	} else {
		@loci_selected = @loci;
	}
	return \@loci_selected;
}

sub order_selected_loci {

	#Reorder loci by genome order, schemes, then by name (genome order may not be set)
	#For offline jobs, pass in params from the job database.  Leave undefined for live jobs (will get CGI params).
	my ( $self, $params ) = @_;
	my $locus_qry = "SELECT id,scheme_id from loci left join scheme_members on loci.id = scheme_members.locus "
	  . "order by genome_position,scheme_members.scheme_id,id";
	my $locus_sql = $self->{'db'}->prepare($locus_qry);
	eval { $locus_sql->execute };
	$logger->error($@) if $@;
	my @selected;
	my %picked;
	my ( @selected_loci, @selected_schemes );

	if ( defined $params ) {
		@selected_loci    = split /\|\|/, ( $params->{'locus'}  // '' );
		@selected_schemes = split /\|\|/, ( $params->{'scheme'} // '' );
	} else {
		my $q = $self->{'cgi'};
		@selected_loci = $q->param('locus');
		my $set_id = $self->get_set_id;
		my $scheme_list = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
		foreach my $scheme (@$scheme_list) {
			push @selected_schemes, $scheme->{'id'} if $q->param("s_$scheme->{'id'}");
		}
		push @selected_schemes, 0 if $q->param('s_0');
	}
	my @selected_locus_names;
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		@selected_locus_names = @selected_loci;
	} else {
		my $pattern = LOCUS_PATTERN;
		foreach my $locus (@selected_loci) {
			my $locus_name = $locus =~ /$pattern/ ? $1 : undef;
			push @selected_locus_names, $locus_name if defined $locus_name;
		}
	}
	while ( my ( $locus, $scheme_id ) = $locus_sql->fetchrow_array ) {
		$scheme_id //= 0;
		if ( ( any { $scheme_id eq $_ } @selected_schemes ) || ( any { $locus eq $_ } @selected_locus_names ) ) {
			push @selected, $locus if !$picked{$locus};
			$picked{$locus} = 1;
		}
	}
	return \@selected;
}

sub set_scheme_param {

	#Set CGI param from scheme tree selections for passing to offline job.
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $scheme_ids = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
	push @$scheme_ids, 0;
	my @selected_schemes;
	foreach (@$scheme_ids) {
		next if !$q->param("s_$_");
		push @selected_schemes, $_;
		$q->delete("s_$_");
	}
	local $" = '||';
	my $scheme_string = "@selected_schemes";
	$q->param( 'scheme', $scheme_string );
	return;
}

sub _print_tree {
	my ( $self, $include_scheme_fields ) = @_;
	say "<p style=\"clear:both\">Click within the tree to select loci belonging to schemes or groups of schemes.</p>"
	  . "<p>If the tree is slow to update, you can try modifying your locus and 	scheme preferences by setting 'analysis' "
	  . "to false for any <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;"
	  . "table=schemes\">schemes</a> or <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;",
	  "table=loci\">loci</a> for which you do not plan to use in analysis tools.</p>";
	say "<noscript><p class=\"highlight\">Javascript needs to be enabled.</p></noscript>";
	say "<div id=\"tree\" class=\"tree\">";
	my $set_id = $self->get_set_id;
	my $options = { no_link_out => 1, list_loci => 1, analysis_pref => 1, set_id => $set_id };
	$options->{'scheme_fields'} = 1 if $include_scheme_fields;
	say $self->get_tree( undef, $options );
	say "</div>\n";
	return;
}

sub _print_all_none_buttons {
	my ( $self, $js1, $js2, $class ) = @_;
	if ( ref $js1 && ref $js2 ) {
		local $" = ',';
		say "<input type=\"button\" value=\"All\" class=\"$class\" onclick='@$js1' />";
		say "<input type=\"button\" value=\"None\" class=\"$class\" onclick='@$js2' />";
	}
	return;
}

sub get_ids_from_query {
	my ( $self, $qry_ref ) = @_;
	return if ref $qry_ref ne 'SCALAR';
	my $qry = $$qry_ref;
	$qry =~ s/ORDER BY.*$//g;
	return if !$self->create_temp_tables($qry_ref);
	my $view = $self->{'system'}->{'view'};
	$qry =~ s/SELECT ($view\.\*|\*)/SELECT id/;
	$qry .= " ORDER BY id";
	my $ids = $self->{'datastore'}->run_list_query($qry);
	return $ids;
}

sub escape_params {
	my ($self)      = @_;
	my $q           = $self->{'cgi'};
	my @param_names = $q->param;
	my %escapes =
	  ( '__prime__' => "'", '__slash__' => "\\", '__comma__' => ',', '__space__' => ' ', '_OPEN_' => "(", '_CLOSE_' => ")", '_GT_' => ">" );
	foreach my $param_name (@param_names) {
		my $key = $param_name;
		if ( any { $param_name =~ /$_/ } keys %escapes ) {
			foreach my $escape_string ( keys %escapes ) {
				$key =~ s/$escape_string/$escapes{$escape_string}/g;
			}
			$q->param( $key, $q->param($param_name) );
		}
	}
	return;
}
1;
