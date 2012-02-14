#Written by Keith Jolley
#Copyright (c) 2010-2012, University of Oxford
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
package BIGSdb::OptionsPage;
use strict;
use warnings;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Page qw(FLANKING);
use constant DISPLAY_COLUMNS => 4;
use constant QUERY_FILTER_COLUMNS => 3;

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery jQuery.coolfieldset noCache);
	return;
}

sub _toggle_option {
	my ( $self, $field ) = @_;
	my $prefs = $self->{'prefs'};
	my $value = $prefs->{$field} ? 'off' : 'on';
	my $guid  = $self->get_guid;
	return if !$guid;
	$self->{'prefstore'}->set_general( $guid, $self->{'system'}->{'db'}, $field, $value );
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('toggle_tooltips') ) {

		#AJAX call - don't display
		$self->_toggle_option('tooltips');
		return;
	}
	my $system = $self->{'system'};
	my $prefs  = $self->{'prefs'};
	my $desc   = $system->{'description'};
	$self->{'extended'} = $self->get_extended_attributes if $self->{'system'}->{'dbtype'} eq 'isolates';
	print "<h1>Set database options</h1>\n";
	if ( !$q->cookie('guid') ) {
		print <<"HTML";
<div class="box" id="statusbad">
<p>In order to store options, a cookie needs to be saved on your computer. Cookies appear to be disabled, 
however.  Please enable them in your browser settings to proceed.</p>
</div>
HTML
		return;
	}
	print <<"HTML";
<div class="box" id="resultsheader"><p>Here you can set options for your use of the website.  Options are
remembered between sessions and affect the current database ($desc) 
only. If some 
of the options don't appear to set when you next go to a query page, 
try refreshing the page (Shift + Refresh) as some pages are cached by 
your browser.</p></div>

HTML
	print $q->start_form;
	$q->param( 'page', 'options' );
	print $q->hidden($_) foreach qw(page db);
	print "<div class=\"box queryform\">\n";
	
	$self->_print_main_options;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->_print_isolate_table_fields_options;
		$self->_print_isolate_query_fields_options;
	}
	print "</div>\n";
	print "<div class=\"box reset\">\n";
	print "<h2>Reset</h2>\n";
	print "<p>Click the reset button to remove all user settings for this database - "
	  . "this includes locus and scheme field preferences.</p>\n";
	print $q->submit( -name => 'reset', -label => 'Reset all to defaults', -class => 'button' );
	print "</div>\n";
	print $q->end_form;
	return;
}

sub _print_form_buttons {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<div style=\"float:right;margin-top:-1.95em\">";
	print $q->submit( -name => 'set', -label => 'Set options', -class => 'submit' );
	print "</div>\n";
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Options - $desc";
}

sub set_options {
	my ($self)     = @_;
	my $stylesheet = $self->get_stylesheet;
	my $q          = $self->{'cgi'};
	my $prefs      = $self->{'prefs'};
	my $prefstore  = $self->{'prefstore'};
	my $system     = $self->{'system'};
	if ( $q->param('set') ) {
		my $guid = $self->get_guid;
		return if !$guid;
		my $dbname = $self->{'system'}->{'db'};
		foreach (qw (displayrecs alignwidth flanking )) {
			$prefstore->set_general( $guid, $dbname, $_, $prefs->{$_} ) if BIGSdb::Utils::is_int( $prefs->{$_} ) && $prefs->{$_} >= 0;
		}
		$prefstore->set_general( $guid, $dbname, 'pagebar', $prefs->{'pagebar'} );
		foreach (qw (hyperlink_loci tooltips)) {
			$prefstore->set_general( $guid, $dbname, $_, $prefs->{$_} ? 'on' : 'off' );
		}
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			foreach (
				qw (mark_provisional_main mark_provisional display_pending_main sequence_details_main locus_alias
				display_pending update_details sequence_details sample_details undesignated_alleles)
			  )
			{
				$prefstore->set_general( $guid, $dbname, $_, $prefs->{$_} ? 'on' : 'off' );
			}
			my $extended = $self->get_extended_attributes;
			foreach ( @{ $self->{'xmlHandler'}->get_field_list() } ) {
				$prefstore->set_field( $guid, $dbname, $_, 'maindisplay', $prefs->{'maindisplayfields'}->{$_} ? 'true' : 'false' );
				$prefstore->set_field( $guid, $dbname, $_, 'dropdown',    $prefs->{'dropdownfields'}->{$_}    ? 'true' : 'false' );
				my $extatt = $extended->{$_};
				if ( ref $extatt eq 'ARRAY' ) {
					foreach my $extended_attribute (@$extatt) {
						$prefstore->set_field( $guid, $dbname, "$_\..$extended_attribute", 'maindisplay',
							$prefs->{'maindisplayfields'}->{"$_\..$extended_attribute"} ? 'true' : 'false' );
						$prefstore->set_field( $guid, $dbname, "$_\..$extended_attribute", 'dropdown',
							$prefs->{'dropdownfields'}->{"$_\..$extended_attribute"} ? 'true' : 'false' );
					}
				}
			}
			$prefstore->set_field( $guid, $dbname, 'aliases', 'maindisplay',
				$prefs->{'maindisplayfields'}->{'aliases'} ? 'true' : 'false' );
			my $composites = $self->{'datastore'}->run_list_query("SELECT id FROM composite_fields");
			foreach (@$composites) {
				$prefstore->set_field( $guid, $dbname, $_, 'maindisplay', $prefs->{'maindisplayfields'}->{$_} ? 'true' : 'false' );
			}
			my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
			foreach (@$schemes) {
				my $field = "scheme_$_\_profile_status";
				$prefstore->set_field( $guid, $dbname, $field, 'dropdown', $prefs->{'dropdownfields'}->{$field} ? 'true' : 'false' );
			}
		}
		$prefstore->update_datestamp($guid);
	} elsif ( $q->param('reset') ) {
		my $guid = $self->get_guid;
		$prefstore->delete_guid($guid) if $guid;
	}
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $buffer = << "END";
\$(function () {
  	\$('#general_fieldset').coolfieldset({speed:"fast", collapsed:true});
  	\$('#isolate_display_fieldset').coolfieldset({speed:"fast", collapsed:true});
  	\$('#isolate_query_fieldset').coolfieldset({speed:"fast", collapsed:true});
 });
END
	return $buffer;
}

sub _print_main_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $prefs  = $self->{'prefs'};
	print "<h2 style=\"border:0\">Main interface options</h2>\n";
	print "<fieldset id=\"general_fieldset\" class=\"coolfieldset\">\n";
	print "<legend>Interface options (click to expand)</legend>\n";
	print "<div>";
	$self->_print_form_buttons;
	$self->_print_general_options;

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->_print_main_results_options;
		$self->_print_isolate_record_options;
	}
	print "</div></fieldset>\n";
	return;
}

sub _print_general_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $prefs  = $self->{'prefs'};
	print "<div class=\"options\"><h2>General</h2>\n";
	print "<ul id=\"general\">\n";
	print "<li><span style=\"white-space:nowrap\"><label for=\"displayrecs\">Display </label>\n";
	print $q->popup_menu(
		-name    => 'displayrecs',
		-id      => 'displayrecs',
		-values  => [qw (10 25 50 100 200 500 all)],
		-default => $prefs->{'displayrecs'}
	);
	print " records per page</span></li>\n";
	print "<li>";
	print "<span style=\"white-space:nowrap\"><label for=\"pagebar\">Page bar position: </label>\n";
	print $q->popup_menu(
		-name    => 'pagebar',
		-id      => 'pagebar',
		-values  => [ 'top and bottom', 'top only', 'bottom only' ],
		-default => $prefs->{'pagebar'}
	);
	print "</span></li>\n";
	print "<li><span style=\"white-space:nowrap\"><label for=\"alignwidth\">Display </label>\n";
	print $q->popup_menu(
		-name    => 'alignwidth',
		-id      => 'alignwidth',
		-values  => [qw (50 60 70 80 90 100 110 120 130 140 150)],
		-default => $prefs->{'alignwidth'}
	);
	print " nucleotides per line in sequence alignments</span></li>\n";

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		print "<li><span style=\"white-space:nowrap\"><label for=\"flanking\">Display </label>\n";
		print $q->popup_menu( -name => 'flanking', -id => 'flanking', -values => [FLANKING], -default => $prefs->{'flanking'} );
		print " nucleotides of flanking sequence (where available)</span></li>\n";
		print "<li>";
		print $q->checkbox( -name => 'locus_alias', -checked => $prefs->{'locus_alias'}, -label => 'Display locus aliases if set' );
		print "</li>\n";
	}
	print "<li>\n";
	print $q->checkbox( -name => 'tooltips', -checked => $prefs->{'tooltips'}, -label => 'Enable tooltips (beginner\'s mode)' );
	print "</li></ul></div>\n";
	return;
}

sub _print_main_results_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $prefs  = $self->{'prefs'};
	print "<div class=\"options\">\n";
	print "<h2>Main results table</h2>\n";
	print "<ul id=\"main_results\">\n";
	print "<li>\n";
	print $q->checkbox(
		-name    => 'hyperlink_loci',
		-checked => $prefs->{'hyperlink_loci'},
		-label   => 'Hyperlink allele designations where possible.'
	);
	print "</li><li>\n";
	print $q->checkbox(
		-name    => 'mark_provisional_main',
		-checked => $prefs->{'mark_provisional_main'},
		-label   => 'Differentiate provisional allele designations.'
	);
	print "</li><li>\n";
	print $q->checkbox(
		-name    => 'display_pending_main',
		-checked => $prefs->{'display_pending_main'},
		-label   => 'Display pending allele designations.'
	);
	print "</li><li>\n";
	print $q->checkbox(
		-name    => 'sequence_details_main',
		-checked => $prefs->{'sequence_details_main'},
		-label   => 'Display information about sequence bin records tagged with locus information (tooltip).'
	);
	print "</li></ul></div>\n";
	return;
}

sub _print_isolate_record_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $prefs  = $self->{'prefs'};
	print "<div class=\"options\">\n";
	print "<h2>Isolate record display</h2>\n";
	print "<ul id=\"isolate_record\">\n";
	print "<li>\n";
	print $q->checkbox(
		-name    => 'mark_provisional',
		-checked => $prefs->{'mark_provisional'},
		-label   => 'Differentiate provisional allele designations.'
	);
	print "</li><li>\n";
	print $q->checkbox( -name => 'display_pending', -checked => $prefs->{'display_pending'},
		-label => 'Display pending allele designations.' );
	print "</li><li>\n";
	print $q->checkbox(
		-name    => 'update_details',
		-checked => $prefs->{'update_details'},
		-label   => 'Display sender, curator and last updated details for allele designations (tooltip).'
	);
	print "</li><li>\n";
	print $q->checkbox(
		-name    => 'sequence_details',
		-checked => $prefs->{'sequence_details'},
		-label   => 'Display information about sequence bin records tagged with locus information (tooltip).'
	);
	print "</li><li>\n";
	print $q->checkbox(
		-name    => 'sample_details',
		-checked => $prefs->{'sample_details'},
		-label   => 'Display full information about sample records (tooltip).'
	);
	print "</li><li>\n";
	print $q->checkbox(
		-name    => 'undesignated_alleles',
		-checked => $prefs->{'undesignated_alleles'},
		-label =>
'Display all loci even where no allele is designated or sequence tagged (this may slow down display where hundreds of loci are defined).'
	);
	print "</li></ul></div>\n";
	return;
}

sub _print_isolate_table_fields_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $prefs  = $self->{'prefs'};
	print "<h2 style=\"border:0\">Isolate provenance field display</h2>\n";
	print "<p>Select the isolate provenance fields that you wish to be displayed in the main results table following a query. "
	 . "Settings for displaying locus and scheme data can be made by performing a <a href=\"$self->{'system'}->{'script_name'}?db="
	 . "$self->{'instance'}&amp;page=tableQuery&amp;table=loci\">locus</a>, <a href=\"$self->{'system'}->{'script_name'}?db="
	 . "$self->{'instance'}&amp;page=tableQuery&amp;table=schemes\">scheme</a> or <a href=\"$self->{'system'}->{'script_name'}?db="
	 . "$self->{'instance'}&amp;page=tableQuery&amp;table=scheme_fields\">scheme field</a> query and then selecting the 'Customize' "
	 . "option.</p>\n";
	print "<div class=\"scrollable\">\n";
	print "<fieldset id=\"isolate_display_fieldset\" class=\"coolfieldset widetable\">\n";
	print "<legend>Display options (click to expand)</legend><div>\n";
	$self->_print_form_buttons;
	my $i      = 0;
	my $cols   = 1;
	my $fields = $self->{'xmlHandler'}->get_field_list;
	my ( @js, @js2, @js3, %composites, %composite_display_pos, %composite_main_display );

	my $qry = "SELECT id,position_after,main_display FROM composite_fields";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };

	if ($@) {
		$logger->error($@);
	} else {
		while ( my @data = $sql->fetchrow_array ) {
			$composite_display_pos{ $data[0] }  = $data[1];
			$composite_main_display{ $data[0] } = $data[2];
			$composites{ $data[1] }             = 1;
		}
	}
	my @field_names;
	foreach my $field (@$fields){
		next if $field eq 'id';
		push @field_names, $field;
		if (ref $self->{'extended'} eq 'HASH' && ref $self->{'extended'}->{$field} eq 'ARRAY'){
			push @field_names, "$field..$_" foreach (@{ $self->{'extended'}->{$field} });
		}
		push @field_names, 'aliases' if $field eq $self->{'system'}->{'labelfield'};
		if ( $composites{$field} ) {
			foreach ( keys %composite_display_pos ) {
				next if $composite_display_pos{$_} ne $field;
				push @field_names, $_;
			}
		}
	}
	my $rel_widths = $self->_determine_column_widths(\@field_names, undef , DISPLAY_COLUMNS);
	print "<div style=\"float:left; width:$rel_widths->{0}%\">";
	print "<ul>\n";
	
	foreach my $field (@$fields) {
		if ( $field ne 'id' ) {
			print "<li>";
			print $q->checkbox(
				-name    => "field_$field",
				-id      => "field_$field",
				-checked => $prefs->{'maindisplayfields'}->{$field},
				-value   => 'checked',
				-label   => $field
			);
			print "</li>\n";
			push @js,  "\$(\"#field_$field\").attr(\"checked\",true)";
			push @js2, "\$(\"#field_$field\").attr(\"checked\",false)";
			my %thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			my $value = $thisfield{'maindisplay'} && $thisfield{'maindisplay'} eq 'no' ? 'false' : 'true';
			push @js3, "\$(\"#field_$field\").attr(\"checked\",$value)";
			$i++;
			$self->_check_new_column( scalar @field_names, \$i, \$cols,$rel_widths,  DISPLAY_COLUMNS);
			my $extatt = $self->{'extended'}->{$field};

			if ( ref $extatt eq 'ARRAY' ) {
				foreach my $extended_attribute (@$extatt) {
					print "<li>";
					print $q->checkbox(
						-name    => "extended_$field..$extended_attribute",
						-id      => "extended_$field\___$extended_attribute",
						-checked => $prefs->{'maindisplayfields'}->{"$field\..$extended_attribute"},
						-value   => 'checked',
						-label   => "$field..$extended_attribute"
					);
					print "</li>\n";
					push @js,  "\$(\"#extended_$field\___$extended_attribute\").attr(\"checked\",true)";
					push @js2, "\$(\"#extended_$field\___$extended_attribute\").attr(\"checked\",false)";
					push @js3, "\$(\"#extended_$field\___$extended_attribute\").attr(\"checked\",false)";
					$i++;
					$self->_check_new_column( scalar @field_names, \$i, \$cols,$rel_widths,  DISPLAY_COLUMNS );
				}
			}
			if ( $field eq $self->{'system'}->{'labelfield'} ) {
				print "<li>";
				print $q->checkbox(
					-name    => "field_aliases",
					-id      => "field_aliases",
					-checked => $prefs->{'maindisplayfields'}->{'aliases'},
					-value   => 'checked',
					-label   => 'aliases'
				);
				print "</li>\n";
				push @js,  "\$(\"#field_aliases\").attr(\"checked\",true)";
				push @js2, "\$(\"#field_aliases\").attr(\"checked\",false)";
				my $value =
				  $self->{'system'}->{'maindisplay_aliases'} && $self->{'system'}->{'maindisplay_aliases'} eq 'yes' ? 'true' : 'false';
				push @js3, "\$(\"#field_aliases\").attr(\"checked\",$value)";
				$i++;
				$self->_check_new_column( scalar @field_names, \$i, \$cols,$rel_widths,  DISPLAY_COLUMNS );
			}
		}
		if ( $composites{$field} ) {
			foreach ( keys %composite_display_pos ) {
				next if $composite_display_pos{$_} ne $field;
				print "<li>";
				print $q->checkbox(
					-name    => "field_$_",
					-id      => "field_$_",
					-checked => $prefs->{'maindisplayfields'}->{$_},
					-value   => 'checked',
					-label   => $_
				);
				print "</li>\n";
				push @js,  "\$(\"#field_$_\").attr(\"checked\",true)";
				push @js2, "\$(\"#field_$_\").attr(\"checked\",false)";
				my $value = $composite_main_display{$_} ? 'true' : 'false';
				push @js3, "\$(\"#field_$_\").attr(\"checked\",$value)";
				$i++;
				$self->_check_new_column( scalar @field_names, \$i, \$cols,$rel_widths,  DISPLAY_COLUMNS );
			}
		}
	}
	$cols++;
	print "</ul></div>\n";
	print "</div>";
	print "<div style=\"clear:both\">\n";
	local $" = ';';
	print "<input type=\"button\" value=\"All\" onclick='@js' class=\"smallbutton\" />\n";
	print "<input type=\"button\" value=\"None\" onclick='@js2' class=\"smallbutton\" />\n";
	print "<input type=\"button\" value=\"Default\" onclick='@js3' class=\"smallbutton\" />\n";
	print "<noscript><span class=\"comment\"> Enable javascript for select buttons to work!</span></noscript>\n";
	print "</div>";
	print "</fieldset></div>\n";
	return;
}

sub _print_isolate_query_fields_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $prefs  = $self->{'prefs'};
	print "<h2 style=\"border:0\">Isolate field dropdown query filters</h2>\n";
	print "<p>Select the fields for which you would like dropdown lists containing known values "
	 . "on which to filter query results.  These will be available in the filters section of the query interface.</p>\n";
	print "<div class=\"scrollable\">\n";
	print "<fieldset id=\"isolate_query_fieldset\" class=\"coolfieldset widetable\">\n";
	print "<legend>Query filters (click to expand)</legend><div>\n";
	$self->_print_form_buttons;
	my $i           = 0;
	my $cols        = 1;
	my $fields      = $self->{'xmlHandler'}->get_field_list;
	my @checkfields = @$fields;
	my %labels;

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes ORDER BY display_order,id");
		foreach (@$schemes) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($_);
			my $field       = "scheme_$_\_profile_status";
			push @checkfields, $field;
			$labels{$field} = "$scheme_info->{'description'} profile completion";
		}
	}
	my ( @js, @js2, @js3 );
	my @field_names;
	foreach (@checkfields){
		next if $_ eq 'id';
		push @field_names, $_;
		if (ref $self->{'extended'} eq 'HASH' && ref $self->{'extended'}->{$_}  eq 'ARRAY'){
			foreach my $ext_att( @{ $self->{'extended'}->{$_} }){
				push @field_names,"$_..$ext_att";
			}
		}
	}
	my $rel_widths = $self->_determine_column_widths(\@field_names, \%labels, QUERY_FILTER_COLUMNS);
	print "<div style=\"float:left; width:$rel_widths->{0}%\">";
	print "<ul>\n";
	
	foreach (@checkfields) {
		my %thisfield = $self->{'xmlHandler'}->get_field_attributes($_);
		if ( $_ ne 'id' ) {
			print "<li>";
			print $q->checkbox(
				-name    => "dropfield_$_",
				-id      => "dropfield_$_",
				-checked => $prefs->{'dropdownfields'}->{$_},
				-value   => 'checked',
				-label   => $labels{$_} || $_
			);
			print "</li>\n";
			push @js,  "\$(\"#dropfield_$_\").attr(\"checked\",true)";
			push @js2, "\$(\"#dropfield_$_\").attr(\"checked\",false)";
			my $value;
			if ($_ =~ /^scheme_(\d+)_profile_status/){
				my $scheme_info = $self->{'datastore'}->get_scheme_info($1);
				$value = $scheme_info->{'query_status'} ? 'true' : 'false';
			} else {
				my %thisfield = $self->{'xmlHandler'}->get_field_attributes($_);
				$value = ( $thisfield{'dropdown'} && $thisfield{'dropdown'} eq 'yes' ) ? 'true' : 'false';				
			}
			push @js3, "\$(\"#dropfield_$_\").attr(\"checked\",$value)";
			$i++;
			$self->_check_new_column( scalar @field_names, \$i, \$cols, $rel_widths, QUERY_FILTER_COLUMNS );
		}
		my $extatt = $self->{'extended'}->{$_};
		if ( ref $extatt eq 'ARRAY' ) {
			foreach my $extended_attribute (@$extatt) {
				print "<li>";
				print $q->checkbox(
					-name    => "dropfield_e_$_\..$extended_attribute",
					-id      => "dropfield_e_$_\___$extended_attribute",
					-checked => $prefs->{'dropdownfields'}->{"$_\..$extended_attribute"},
					-value   => 'checked',
					-label   => "$_\..$extended_attribute"
				);
				print "</li>\n";
				push @js,  "\$(\"#dropfield_e_$_\___$extended_attribute\").attr(\"checked\",true)";
				push @js2, "\$(\"#dropfield_e_$_\___$extended_attribute\").attr(\"checked\",false)";
				push @js3, "\$(\"#dropfield_e_$_\___$extended_attribute\").attr(\"checked\",false)";
				$i++;
				$self->_check_new_column( scalar @field_names, \$i, \$cols, $rel_widths, QUERY_FILTER_COLUMNS );
			}
		}
	}
	$cols++;
	print "</ul></div>\n";
	print "</div><div style=\"clear:both\">\n";
	local $" = ';';
	print "<input type=\"button\" value=\"All\" onclick='@js' class=\"smallbutton\" />\n";
	print "<input type=\"button\" value=\"None\" onclick='@js2' class=\"smallbutton\" />\n";
	print "<input type=\"button\" value=\"Default\" onclick='@js3' class=\"smallbutton\" />\n";
	print "<noscript><span class=\"comment\"> Enable javascript for select buttons to work!</span></noscript>\n";
	print "</div></fieldset></div>\n";
	return;
}

sub _check_new_column {
	my ( $self, $field_count, $count_ref, $cols_ref, $rel_widths, $cols ) = @_;
	return if !$rel_widths->{$$cols_ref};
	if ( $$count_ref >= ($field_count / ( $self->{'system'}->{'maxcols'} || $cols  ))) {
		print "</ul></div>\n<div style=\"float:left; width:$rel_widths->{$$cols_ref}%\; position: relative;\"><ul>\n";
		$$count_ref = 0;
		$$cols_ref++;
	}
	return;
}

sub _determine_column_widths {
	my ($self, $names_ref, $labels_ref, $columns) = @_;
	my $max_per_column = int(@$names_ref / $columns);
	$max_per_column++ if @$names_ref % $columns;
	my %max_width;
	my $i = 0;
	my $col = 0;
	my $max_length = 0;
	my $width_of_all_cols = 0;
	my $overall_count = 0;
	foreach (@$names_ref){
		my $length = length($labels_ref->{$_} || $_);
		$max_length = $length if $length > $max_length;
		$i++;
		$overall_count++;
		if ($i == $max_per_column || $overall_count == @$names_ref){
			$max_width{$col} = $max_length;
			$width_of_all_cols+=$max_length;
			$i = 0;
			$max_length = 0;
			$col++;
		}
	}
	my %relative_width;
	foreach (keys %max_width){
		$relative_width{$_} = int(100 * $max_width{$_} / $width_of_all_cols);
	}
	return \%relative_width;
}
1;
