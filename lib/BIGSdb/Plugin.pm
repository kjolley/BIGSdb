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
package BIGSdb::Plugin;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::TreeViewPage);
use Error qw(:try);
use Log::Log4perl qw(get_logger);
use List::MoreUtils qw(any uniq);
use BIGSdb::Page qw(FLANKING LOCUS_PATTERN);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_TREE_NODES => 1000;

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

sub print_extra_fields {

	#override in subclass
	return '';
}

sub print_options {

	#override in subclass
	return '';
}

sub print_extra_options {

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

function isolate_list_show() {
	\$("#isolate_paste_list_div").show(500);
	\$("#isolate_list_show_button").hide(0);
	\$("#isolate_list_hide_button").show(0);
}

function isolate_list_hide() {
	\$("#isolate_paste_list_div").hide(500);
	\$("#isolate_paste_list").val('');
	\$("#isolate_list_show_button").show(0);
	\$("#isolate_list_hide_button").hide(0);
}

function locus_list_show() {
	\$("#locus_paste_list_div").show(500);
	\$("#locus_list_show_button").hide(0);
	\$("#locus_list_hide_button").show(0);
}

function locus_list_hide() {
	\$("#locus_paste_list_div").hide(500);
	\$("#locus_paste_list").val('');
	\$("#locus_list_show_button").show(0);
	\$("#locus_list_hide_button").hide(0);
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
	return if $self->{'temp_tables_created'};
	my $qry      = $$qry_ref;
	my $q        = $self->{'cgi'};
	my $format   = $q->param('format') || 'html';
	my $schemes  = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
	my $continue = 1;
	try {

		foreach (@$schemes) {
			if ( $qry =~ /temp_isolates_scheme_fields_$_\s/ ) {
				$self->{'datastore'}->create_temp_isolate_scheme_fields_view($_);
			}
			if ( $qry =~ /temp_scheme_$_\s/ || $qry =~ /ORDER BY s_$_\_/ ) {
				$self->{'datastore'}->create_temp_scheme_table($_);
				$self->{'datastore'}->create_temp_isolate_scheme_loci_view($_);
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
	if ( $q->param('list_file') && $q->param('datatype') ) {
		$self->{'datastore'}->create_temp_list_table( $q->param('datatype'), $q->param('list_file') );
	}
	$self->{'temp_tables_created'} = 1;
	return $continue;
}

sub delete_temp_files {
	my ( $self, $wildcard ) = @_;
	my @files = glob("$self->{'config'}->{'secure_tmp_dir'}/$wildcard");
	foreach (@files) { unlink $1 if /^(.*BIGSdb.*)$/ }
	return;
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
	if ( @$option_list && $q->param('format') eq 'html' ) {
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

sub _print_fields {
	my ( $self, $args ) = @_;
	my ( $fields, $prefix, $num_columns, $labels, $default_select ) = @{$args}{qw(fields prefix num_columns labels default_select)};
	my $q                 = $self->{'cgi'};
	my $fields_per_column = BIGSdb::Utils::round_up( @$fields / $num_columns );
	say "<div style=\"float:left;margin-bottom:1em\"><ul>";
	my $i = 0;
	foreach my $field (@$fields) {
		my $label = $labels->{$field} || $field;
		$label =~ s/^.*___//;         #only show extended field.
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
		push @js,          "\$(\"#$id\").prop(\"checked\",true)";
		push @js2,         "\$(\"#$id\").prop(\"checked\",false)";
		push @isolate_js,  "\$(\"#$id\").prop(\"checked\",true)";
		push @isolate_js2, "\$(\"#$id\").prop(\"checked\",false)";
	}
	say $q->start_form;
	say "<fieldset style=\"float:left\"><legend>Isolate fields</legend>";
	my %labels;
	$self->_print_fields(
		{ fields => \@display_fields, prefix => 'f', num_columns => 3, labels => \%labels, default_select => $default_select } );
	$self->_print_all_none_buttons( \@isolate_js, \@isolate_js2, 'smallbutton' );
	say "</fieldset>";
	if ( $options->{'include_composites'} ) {
		my $composites = $self->{'datastore'}->run_list_query("SELECT id FROM composite_fields ORDER BY id");
		if (@$composites) {
			my ( @com_js, @com_js2 );
			foreach (@$composites) {
				push @js,      "\$(\"#c_$_\").prop(\"checked\",true)";
				push @js2,     "\$(\"#c_$_\").prop(\"checked\",false)";
				push @com_js,  "\$(\"#c_$_\").prop(\"checked\",true)";
				push @com_js2, "\$(\"#c_$_\").prop(\"checked\",false)";
			}
			print "<fieldset style=\"float:left\"><legend>Composite fields";
			print " <a class=\"tooltip\" title=\"Composite fields - These are constructed from combinations of other fields "
			  . "(some of which may come from external databases).  Including composite fields will slow down the processing.\">&nbsp;<i>i</i>&nbsp;</a>";
			say "</legend>";
			$self->_print_fields( { fields => $composites, prefix => 'c', num_columns => 1, labels => \%labels, default_select => 0 } );
			$self->_print_all_none_buttons( \@com_js, \@com_js2, 'smallbutton' );
			say "</fieldset>";
		}
	}
	$self->print_extra_fields;
	$self->print_isolates_locus_fieldset;
	$self->print_scheme_fieldset( { fields_or_loci => 1 } );
	$self->print_options;
	$self->print_extra_options;
	$self->print_action_fieldset( { no_reset => 1 } );
	say "<div style=\"clear:both\"></div>";
	$q->param( set_id => $set_id );
	say $q->hidden($_) foreach qw (db page name query_file set_id list_file datatype);
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
			$_ =~ s/\s*$//;
			push @$list, $_;
		}
	} elsif ($query_file) {
		my $qry_ref = $self->get_query($query_file);
		return if ref $qry_ref ne 'SCALAR';
		return if !$self->create_temp_tables($qry_ref);
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			my $view = $self->{'system'}->{'view'};
			$$qry_ref =~ s/SELECT ($view\.\*|\*)/SELECT $view\.$pk/;
			$self->rewrite_query_ref_order_by($qry_ref);
		}
		$list = $self->{'datastore'}->run_list_query($$qry_ref);
	} else {
		$list = [];
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

sub get_loci_from_pasted_list {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	my ( @cleaned_loci, @invalid_loci );
	if ( $q->param('locus_paste_list') ) {
		my @list = split /\n/, $q->param('locus_paste_list');
		foreach my $locus (@list) {
			next if $locus =~ /^\s*$/;
			$locus =~ s/^\s*//;
			$locus =~ s/\s*$//;
			my $real_name;
			my $set_id = $self->get_set_id;
			if ($set_id) {
				$real_name = $self->{'datastore'}->get_set_locus_real_id( $locus, $set_id );
			} else {
				$real_name = $locus;
			}
			if ( $self->{'datastore'}->is_locus($real_name) ) {
				push @cleaned_loci, $real_name;
			} else {
				push @invalid_loci, $locus;
			}
		}
		$q->delete('locus_paste_list') if !@invalid_loci && !$options->{'dont_clear'};
	}
	return ( \@cleaned_loci, \@invalid_loci );
}

sub get_ids_from_pasted_list {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	my ( @cleaned_ids, @invalid_ids );
	if ( $q->param('isolate_paste_list') ) {
		my @list = split /\n/, $q->param('isolate_paste_list');
		foreach my $id (@list) {
			next if $id =~ /^\s*$/;
			$id =~ s/^\s*//;
			$id =~ s/\s*$//;
			if ( BIGSdb::Utils::is_int($id) && $self->isolate_exists($id) ) {
				push @cleaned_ids, $id;
			} else {
				push @invalid_ids, $id;
			}
		}
		$q->delete('isolate_paste_list') if !@invalid_ids && !$options->{'dont_clear'};
	}
	return ( \@cleaned_ids, \@invalid_ids );
}

sub isolate_exists {
	my ( $self, $id ) = @_;
	if ( !$self->{'sql'}->{'id_exists'} ) {
		$self->{'sql'}->{'id_exists'} = $self->{'db'}->prepare("SELECT EXISTS(SELECT id FROM $self->{'system'}->{'view'} WHERE id=?)");
	}
	eval { $self->{'sql'}->{'id_exists'}->execute($id) };
	$logger->error($@) if $@;
	my $exists = $self->{'sql'}->{'id_exists'}->fetchrow_array;
	return $exists;
}

sub print_sequence_export_form {
	my ( $self, $pk, $list, $scheme_id, $options ) = @_;
	$logger->error("No primary key passed") if !defined $pk;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	say $q->start_form;
	say "<fieldset style=\"float:left\">\n<legend>Select $pk" . "s</legend>";
	local $" = "\n";
	say "<p style=\"padding-right:2em\">Paste in list of ids to include, start a new<br />line for each. "
	  . "Leave blank to include all ids.</p>";
	@$list = uniq @$list;
	say $q->textarea( -name => 'list', -rows => 5, -cols => 25, -default => "@$list" );
	say "</fieldset>";
	my ( $locus_list, $locus_labels ) =
	  $self->get_field_selection_list( { loci => 1, analysis_pref => 1, query_pref => 0, sort_labels => 1 } );
	$self->print_includes_fieldset( { scheme_id => $scheme_id } );

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->print_isolates_locus_fieldset( { locus_paste_list => 1 } );
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
		if ( $options->{'align'} ) {
			say $q->checkbox( -name => 'align', -id => 'align', -label => 'Align sequences' );
			say "<br />";
			my @aligners;
			foreach my $aligner (qw(mafft muscle)) {
				push @aligners, uc($aligner) if $self->{'config'}->{"$aligner\_path"};
			}
			if (@aligners) {
				say "Aligner: ";
				say $q->popup_menu( -name => 'aligner', -id => 'aligner', -values => \@aligners );
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
	$self->print_action_fieldset( { no_reset => 1 } );
	say "<div style=\"clear:both\"></div>";
	my $set_id = $self->get_set_id;
	$q->param( set_id => $set_id );
	say $q->hidden($_) foreach qw (db page name query_file scheme_id set_id list_file datatype);
	say $q->end_form;
	return;
}

sub has_set_changed {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $set_id = $self->get_set_id;
	if ( $q->param('set_id') && $set_id ) {
		if ( $q->param('set_id') != $set_id ) {
			say qq(<div class="box" id="statusbad"><p>The dataset has been changed since this plugin was started.  Please )
			  . qq(repeat the query.</p></div>);
			return 1;
		}
	}
	return;
}

sub print_includes_fieldset {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	my ( @fields, $labels );
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $set_id        = $self->get_set_id;
		my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
		my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
		foreach my $field (@$field_list) {
			next if any { $field eq $_ } qw (id datestamp date_entered curator sender);
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			push @fields, $field;
			( $labels->{$field} = $metafield // $field ) =~ tr/_/ /;
		}
	} else {
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields( $options->{'scheme_id'} );
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $options->{'scheme_id'}, { get_pk => 1 } );
		foreach (@$scheme_fields) {
			push @fields, $_ if $_ ne $scheme_info->{'primary_key'};
		}
	}
	if (@fields) {
		my $title = $options->{'title'} // 'Include in identifier';
		say "<fieldset style=\"float:left\">\n<legend>$title</legend>";
		say $q->scrolling_list(
			-name     => 'includes',
			-id       => 'includes',
			-values   => \@fields,
			-labels   => $labels,
			-size     => 10,
			-default  => $options->{'preselect'},
			-multiple => 'true'
		);
		say "</fieldset>";
	}
	return;
}

sub print_seqbin_isolate_fieldset {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	my ( $ids, $labels ) = $self->get_isolates_with_seqbin($options);
	say "<fieldset style=\"float:left\">\n<legend>Isolates</legend>";
	if (@$ids) {
		say "<div style=\"float:left\">";
		say $self->popup_menu(
			-name     => 'isolate_id',
			-id       => 'isolate_id',
			-values   => $ids,
			-labels   => $labels,
			-size     => 8,
			-multiple => 'true',
			-default  => $options->{'selected_ids'},
		);
		my $list_button = '';
		if ( $options->{'isolate_paste_list'} ) {
			my $show_button_display = $q->param('isolate_paste_list') ? 'none'    : 'display';
			my $hide_button_display = $q->param('isolate_paste_list') ? 'display' : 'none';
			$list_button =
			    qq(<input type="button" id="isolate_list_show_button" onclick='isolate_list_show()' value="Paste list" )
			  . qq(style="margin-top:1em; display:$show_button_display" class="smallbutton" />)
			  . qq(<input type="button" id="isolate_list_hide_button" onclick='isolate_list_hide()' value="Hide list" )
			  . qq(style="margin-top:1em; display:$hide_button_display" class="smallbutton" />);
		}
		print <<"HTML";
	<div style="text-align:center"><input type="button" onclick='listbox_selectall("isolate_id",true)' value="All" style="margin-top:1em" 
	class="smallbutton" /><input type="button" onclick='listbox_selectall("isolate_id",false)' value="None" style="margin-top:1em" 
	class="smallbutton" />$list_button</div></div>
HTML
		if ( $options->{'isolate_paste_list'} ) {
			my $display = $q->param('isolate_paste_list') ? 'block' : 'none';
			say "<div id=\"isolate_paste_list_div\" style=\"float:left; display:$display\">";
			say $q->textarea(
				-name        => 'isolate_paste_list',
				-id          => 'isolate_paste_list',
				-cols        => 12,
				-rows        => 7,
				-placeholder => 'Paste list of isolate ids...'
			);
			say "</div>";
		}
	} else {
		say "No isolates available<br />for analysis";
	}
	say "</fieldset>";
	return;
}

sub print_isolates_locus_fieldset {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	say "<fieldset id=\"locus_fieldset\" style=\"float:left\">\n<legend>Loci</legend>";
	my ( $locus_list, $locus_labels ) =
	  $self->get_field_selection_list( { loci => 1, analysis_pref => 1, query_pref => 0, sort_labels => 1 } );
	if (@$locus_list) {
		say "<div style=\"float:left\">";
		say $self->popup_menu(
			-name     => 'locus',
			-id       => 'locus',
			-values   => $locus_list,
			-labels   => $locus_labels,
			-size     => 8,
			-multiple => 'true'
		);
		my $list_button = '';
		if ( $options->{'locus_paste_list'} ) {
			my $show_button_display = $q->param('locus_paste_list') ? 'none'    : 'display';
			my $hide_button_display = $q->param('locus_paste_list') ? 'display' : 'none';
			$list_button =
			    qq(<input type="button" id="locus_list_show_button" onclick='locus_list_show()' value="Paste list" )
			  . qq(style="margin-top:1em; display:$show_button_display" class="smallbutton" />)
			  . qq(<input type="button" id="locus_list_hide_button" onclick='locus_list_hide()' value="Hide list" )
			  . qq(style="margin-top:1em; display:$hide_button_display" class="smallbutton" />);
		}
		say <<"HTML";
<div style="text-align:center"><input type="button" onclick='listbox_selectall("locus",true)' value="All" style="margin-top:1em" class="smallbutton" />
<input type="button" onclick='listbox_selectall("locus",false)' value="None" style="margin-top:1em" class="smallbutton" />$list_button</div></div>
HTML
		if ( $options->{'locus_paste_list'} ) {
			my $display = $q->param('locus_paste_list') ? 'block' : 'none';
			say "<div id=\"locus_paste_list_div\" style=\"float:left; display:$display\">";
			say $q->textarea(
				-name        => 'locus_paste_list',
				-id          => 'locus_paste_list',
				-cols        => 12,
				-rows        => 7,
				-placeholder => 'Paste list of locus primary names...'
			);
			say "</div>";
		}
	} else {
		say "No loci available<br />for analysis";
	}
	say "</fieldset>";
	return;
}

sub print_scheme_locus_fieldset {
	my ( $self, $scheme_id, $options ) = @_;
	my $locus_list = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $set_id     = $self->get_set_id;
	my %labels;
	( $labels{$_} = $self->{'datastore'}->get_set_locus_label( $_, $set_id ) ) foreach (@$locus_list);
	say "<fieldset style=\"float:left\"><legend>Select loci</legend>";
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
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	say "<fieldset style=\"float:left\"><legend>Restrict included sequences by</legend><ul>";
	my $buffer = $self->get_sequence_method_filter( { class => 'parameter' } );
	say "<li>$buffer</li>" if $buffer;
	$buffer = $self->get_project_filter( { class => 'parameter' } );
	say "<li>$buffer</li>" if $buffer;
	$buffer = $self->get_experiment_filter( { class => 'parameter' } );
	say "<li>$buffer</li>" if $buffer;

	if ( $options->{'min_length'} ) {
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

sub add_scheme_loci {

	#Merge scheme loci into locus arrayref.  This deletes CGI params so don't call more than once.
	my ( $self, $loci ) = @_;
	my $q          = $self->{'cgi'};
	my $scheme_ids = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
	push @$scheme_ids, 0;
	my @selected_schemes;
	foreach my $scheme_id (@$scheme_ids) {
		next if !$q->param("s_$scheme_id");
		push @selected_schemes, $scheme_id;
		$q->delete("s_$scheme_id");
	}
	my %locus_selected = map { $_ => 1 } @$loci;
	my $set_id = $self->get_set_id;
	foreach my $scheme_id (@selected_schemes) {
		my $scheme_loci =
		    $scheme_id
		  ? $self->{'datastore'}->get_scheme_loci($scheme_id)
		  : $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
		foreach my $locus (@$scheme_loci) {
			if ( !$locus_selected{$locus} ) {
				push @$loci, $locus;
				$locus_selected{$locus} = 1;
			}
		}
	}
	return;
}

sub order_loci {

	#Reorder loci by scheme member order (if seqdefdb), genome order then by name (genome order may not be set)
	my ( $self, $loci, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my %loci = map { $_ => 1 } @$loci;
	my $qry;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' || !$options->{'scheme_id'} ) {
		$qry = "SELECT id FROM loci ORDER BY genome_position,id";
	} else {
		$logger->logdie("Invalid scheme_id passed.") if !BIGSdb::Utils::is_int( $options->{'scheme_id'} );
		$qry = "SELECT id FROM loci INNER JOIN scheme_members ON loci.id=scheme_members.locus AND scheme_id=$options->{'scheme_id'} "
		  . "ORDER BY field_order,genome_position,id";
	}
	my $ordered = $self->{'datastore'}->run_list_query($qry);
	my @list;
	foreach my $locus (@$ordered) {
		push @list, $locus if $loci{$locus};
	}
	return \@list;
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

sub get_scheme_field_values {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $field, $scheme_id ) = @{$args}{qw(isolate_id field scheme_id )};
	my $data = $self->{'datastore'}->get_scheme_field_values_by_isolate_id( $isolate_id, $scheme_id );
	no warnings 'numeric';
	my @values = sort { $a <=> $b || $a cmp $b } keys %{ $data->{ lc $field } };
	return \@values;
}
1;
