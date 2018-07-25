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
package BIGSdb::OptionsPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Constants qw(:interface);

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery jQuery.columnizer noCache );
	return;
}

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/data_query.html#user-configurable-options";
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
	my $desc = $self->{'system'}->{'description'};
	$self->{'extended'} = $self->get_extended_attributes if $self->{'system'}->{'dbtype'} eq 'isolates';
	say q(<h1>Set database options</h1>);
	if ( !$q->cookie('guid') ) {
		$self->print_bad_status(
			{
				message => q(In order to store options, a cookie needs to be saved on your computer. )
				  . q(Cookies appear to be disabled, however.  Please enable them in your browser )
				  . q(settings to proceed.),
				navbar => 1
			}
		);
		return;
	}
	say q(<div class="box" id="resultsheader"><p>Here you can set options for your use of the website.  )
	  . qq(Options are remembered between sessions and affect the current database ($desc) only. If some )
	  . q(of the options don't appear to set when you next go to a query page, try refreshing the )
	  . q(page (Shift + Refresh) as some pages are cached by your browser.</p></div>);
	say $q->start_form;
	$q->param( page => 'options' );
	say $q->hidden($_) foreach qw(page db);

	#Prevent rendering artefacts - only display once accordion is populated
	my $visible = $self->{'system'}->{'dbtype'} eq 'isolates' ? 'hidden' : 'visible';
	say qq(<div class="box queryform" style="visibility:$visible">);
	say q(<div id="accordion">);
	$self->_print_general_options;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->_print_main_results_options;
		$self->_print_main_results_field_options;
		$self->_print_main_results_sparse_field_options;
		$self->_print_isolate_record_options;
		$self->_print_isolate_query_fields_options;
	}
	say q(</div></div>);
	say qq(<div class="box reset" style="visibility:$visible">);
	say q(<h2>Reset</h2>);
	say q(<p>Click the reset button to remove all user settings for this database - )
	  . q(this includes locus and scheme field preferences.</p>);
	say $q->submit( -name => 'reset', -label => 'Reset all to defaults', -class => RESET_BUTTON_CLASS );
	say q(</div>);
	say $q->end_form;
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Options - $desc";
}

sub set_options {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $prefs     = $self->{'prefs'};
	my $prefstore = $self->{'prefstore'};
	if ( $q->param('set') ) {
		my $guid = $self->get_guid;
		return if !$guid;
		my $dbname = $self->{'system'}->{'db'};
		foreach my $action (qw (displayrecs alignwidth flanking )) {
			$prefstore->set_general( $guid, $dbname, $action, $prefs->{$action} )
			  if BIGSdb::Utils::is_int( $prefs->{$action} ) && $prefs->{$action} >= 0;
		}
		$prefstore->set_general( $guid, $dbname, 'pagebar', $prefs->{'pagebar'} );
		foreach my $action (qw (hyperlink_loci tooltips)) {
			$prefstore->set_general( $guid, $dbname, $action, $prefs->{$action} ? 'on' : 'off' );
		}
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			$self->_set_isolate_options( $guid, $dbname );
		}
		$prefstore->update_datestamp($guid);
	} elsif ( $q->param('reset') ) {
		my $guid = $self->get_guid;
		$prefstore->delete_guid($guid) if $guid;
	}
	return;
}

sub _set_isolate_options {
	my ( $self, $guid, $dbname ) = @_;
	my $prefstore        = $self->{'prefstore'};
	my $prefs            = $self->{'prefs'};
	my $field_attributes = $self->{'xmlHandler'}->get_all_field_attributes;
	$prefstore->delete_all_field_settings( $guid, $dbname );
	foreach my $action (
		qw (mark_provisional_main mark_provisional sequence_details_main display_seqbin_main
		display_contig_count locus_alias update_details sequence_details allele_flags
		sample_details display_publications)
	  )
	{
		$prefstore->set_general( $guid, $dbname, $action, $prefs->{$action} ? 'on' : 'off' );
	}
	my $set_id         = $self->get_set_id;
	my $extended       = $self->get_extended_attributes;
	my $metadata_list  = $self->{'datastore'}->get_set_metadata($set_id);
	my $field_list     = $self->{'xmlHandler'}->get_field_list($metadata_list);
	my $eav_field_list = $self->{'datastore'}->get_eav_fieldnames;
	foreach my $field (@$field_list) {
		next if $field eq 'id';
		my $display_default = $field_attributes->{$field}->{'maindisplay'} eq 'no' ? 0 : 1;
		if ( $prefs->{'maindisplayfields'}->{$field} != $display_default ) {
			$prefstore->set_field( $guid, $dbname, $field, 'maindisplay',
				$prefs->{'maindisplayfields'}->{$field} ? 'true' : 'false' );
		}
		my $dropdown_default = ( $field_attributes->{$field}->{'dropdown'} // q() ) eq 'yes' ? 1 : 0;
		if ( $prefs->{'dropdownfields'}->{$field} != $dropdown_default ) {
			$prefstore->set_field( $guid, $dbname, $field, 'dropdown',
				$prefs->{'dropdownfields'}->{$field} ? 'true' : 'false' );
		}
		my $extatt = $extended->{$field} // [];
		foreach my $extended_attribute (@$extatt) {
			if ( $prefs->{'maindisplayfields'}->{"${field}..$extended_attribute"} ) {
				$prefstore->set_field( $guid, $dbname, "${field}..$extended_attribute", 'maindisplay', 'true' );
			}
			if ( $prefs->{'dropdownfields'}->{"${field}..$extended_attribute"} ) {
				$prefstore->set_field( $guid, $dbname, "${field}..$extended_attribute", 'dropdown', 'true' );
			}
		}
	}
	foreach my $field (@$eav_field_list) {
		if ( $prefs->{'maindisplayfields'}->{$field} ) {
			$prefstore->set_field( $guid, $dbname, $field, 'maindisplay', 'true' );
		}
	}
	if ( !$prefs->{'maindisplayfields'}->{'aliases'} ) {
		$prefstore->set_field( $guid, $dbname, 'aliases', 'maindisplay', 'false' );
	}
	my $composites = $self->{'datastore'}
	  ->run_query( 'SELECT id,main_display FROM composite_fields', undef, { fetch => 'all_arrayref', slice => {} } );
	foreach my $field (@$composites) {
		my $display_default = $field->{'main_display'};
		if ( $prefs->{'maindisplayfields'}->{ $field->{'id'} } != $display_default ) {
			$prefstore->set_field( $guid, $dbname, $field->{'id'}, 'maindisplay',
				$prefs->{'maindisplayfields'}->{ $field->{'id'} } ? 'true' : 'false' );
		}
	}
	my $schemes =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id,query_status FROM schemes', undef, { fetch => 'all_arrayref', slice => {} } );
	foreach my $scheme (@$schemes) {
		my $field   = "scheme_$scheme->{'id'}_profile_status";
		my $default = $scheme->{'query_status'};
		if ( $prefs->{'dropdownfields'}->{$field} != $default ) {
			$prefstore->set_field( $guid, $dbname, $field, 'dropdown',
				$prefs->{'dropdownfields'}->{$field} ? 'true' : 'false' );
		}
	}
	if ( !$prefs->{'dropdownfields'}->{'Publications'} ) {
		$prefstore->set_field( $guid, $dbname, 'Publications', 'dropdown', 'false' );
	}
	return;
}

sub get_javascript {
	my ($self) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'isolates';
	my $buffer = << "END";
\$(function() {
	\$("#provenance_field_display").columnize({width:300,buildOnce:true});
	\$("#sparse_field_display").columnize({width:300,buildOnce:true});
	\$("#dropdown_query_filters").columnize({width:400,buildOnce:true});
	\$("#accordion").accordion({heightStyle:"content"});
	\$(".batch").css("display","inline");
	\$("div.box").css("visibility","visible");
});
END
	return $buffer;
}

sub _print_general_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $prefs  = $self->{'prefs'};
	say q(<h2>General options</h2><div class="options">);
	say q(<ul id="general">);
	say q(<li><span style="white-space:nowrap"><label for="displayrecs">Display </label>);
	say $q->popup_menu(
		-name    => 'displayrecs',
		-id      => 'displayrecs',
		-values  => [qw (10 25 50 100 200 500 all)],
		-default => $prefs->{'displayrecs'}
	);
	say q( records per page.</span></li>);
	say q(<li>);
	say q(<span style="white-space:nowrap"><label for="pagebar">Page bar position: </label>);
	say $q->popup_menu(
		-name    => 'pagebar',
		-id      => 'pagebar',
		-values  => [ 'top and bottom', 'top only', 'bottom only' ],
		-default => $prefs->{'pagebar'}
	);
	say q(</span></li>);
	say q(<li><span style="white-space:nowrap"><label for="alignwidth">Display </label>);
	say $q->popup_menu(
		-name    => 'alignwidth',
		-id      => 'alignwidth',
		-values  => [qw (50 60 70 80 90 100 110 120 130 140 150)],
		-default => $prefs->{'alignwidth'}
	);
	say q( nucleotides per line in sequence alignments.</span></li>);

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say q(<li><span style="white-space:nowrap"><label for="flanking">Display </label>);
		say $q->popup_menu(
			-name    => 'flanking',
			-id      => 'flanking',
			-values  => [FLANKING],
			-default => $prefs->{'flanking'}
		);
		say q( nucleotides of flanking sequence (where available).</span></li>);
		say q(<li>);
		say $q->checkbox(
			-name    => 'locus_alias',
			-checked => $prefs->{'locus_alias'},
			-label   => 'Display locus aliases if set.'
		);
		say q(</li>);
	}
	say q(<li>);
	say $q->checkbox(
		-name    => 'tooltips',
		-checked => $prefs->{'tooltips'},
		-label   => 'Enable tooltips (beginner\'s mode).'
	);
	say q(</li></ul>);
	say $q->submit( -name => 'set', -label => 'Set options', -class => BUTTON_CLASS );
	say q(</div>);
	return;
}

sub _print_main_results_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $prefs  = $self->{'prefs'};
	say q(<h2>Main results table - display options</h2>);
	say q(<div class="options">);
	my $options = [
		{
			-name    => 'hyperlink_loci',
			-checked => $prefs->{'hyperlink_loci'},
			-label   => 'Hyperlink allele designations where possible.'
		},
		{
			-name    => 'mark_provisional_main',
			-checked => $prefs->{'mark_provisional_main'},
			-label   => 'Differentiate provisional allele designations.'
		},
		{
			-name    => 'sequence_details_main',
			-checked => $prefs->{'sequence_details_main'},
			-label   => 'Display information about sequence bin records tagged with locus information (tooltip).'
		},
		{
			-name    => 'display_seqbin_main',
			-checked => $prefs->{'display_seqbin_main'},
			-label   => 'Display sequence bin size.'
		},
		{
			-name    => 'display_contig_count',
			-checked => $prefs->{'display_contig_count'},
			-label   => 'Display contig count.'
		},
		{
			-name    => 'display_publications',
			-checked => $prefs->{'display_publications'},
			-label   => 'Display publications.'
		}
	];
	say q(<ul id="main_results">);
	foreach my $option (@$options) {
		say q(<li>);
		say $q->checkbox(%$option);
		say q(</li>);
	}
	say q(</ul>);
	say $q->submit( -name => 'set', -label => 'Set options', -class => BUTTON_CLASS );
	say q(</div>);
	return;
}

sub _print_isolate_record_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $prefs  = $self->{'prefs'};
	say q(<h2>Isolate record display</h2>);
	say q(<div class="options">);
	say q(<ul id="isolate_record">);
	say q(<li>);
	say $q->checkbox(
		-name    => 'mark_provisional',
		-checked => $prefs->{'mark_provisional'},
		-label   => 'Differentiate provisional allele designations.'
	);
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'update_details',
		-checked => $prefs->{'update_details'},
		-label   => 'Display sender, curator and last updated details for allele designations (tooltip).'
	);
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'sequence_details',
		-checked => $prefs->{'sequence_details'},
		-label   => 'Display information about sequence bin records tagged with locus information (tooltip).'
	);
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'allele_flags',
		-checked => $prefs->{'allele_flags'},
		-label   => 'Display information about whether alleles have flags defined in sequence '
		  . 'definition database (shown in sequence detail tooltip).'
	);
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'sample_details',
		-checked => $prefs->{'sample_details'},
		-label   => 'Display full information about sample records (tooltip).'
	);
	say q(</li></ul>);
	say $q->submit( -name => 'set', -label => 'Set options', -class => BUTTON_CLASS );
	say q(</div>);
	return;
}

sub _print_main_results_field_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $prefs  = $self->{'prefs'};
	say q(<h2>Main results table - provenance field selection</h2>);
	say q(<div><p>Select the isolate provenance fields that you wish to be displayed in the main results )
	  . q(table following a query. Settings for displaying locus and scheme data can be made by performing a )
	  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=loci">)
	  . q(locus</a>, )
	  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=schemes">)
	  . q(scheme</a> or )
	  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=)
	  . q(scheme_fields">scheme field</a> query and then selecting the 'Customize' option.</p>);
	say q(<div class="scrollable">);
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
	my ( @js, @js2, @js3, %composites, %composite_display_pos, %composite_main_display );
	my $comp_data = $self->{'datastore'}->run_query( 'SELECT id,position_after,main_display FROM composite_fields',
		undef, { fetch => 'all_arrayref', slice => {} } );

	foreach my $comp (@$comp_data) {
		$composite_display_pos{ $comp->{'id'} }  = $comp->{'position_after'};
		$composite_main_display{ $comp->{'id'} } = $comp->{'main_display'};
		$composites{ $comp->{'position_after'} } = 1;
	}
	say q(<div id="provenance_field_display">);
	say q(<ul>);
	foreach my $field (@$field_list) {
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
		if ( $field ne 'id' ) {
			say q(<li>);
			( my $id = "field_$field" ) =~ tr/:/_/;
			say $q->checkbox(
				-name    => "field_$field",
				-id      => $id,
				-checked => $prefs->{'maindisplayfields'}->{$field},
				-value   => 'checked',
				-label   => $metafield // $field
			);
			say q(</li>);
			push @js,  qq(\$("#$id").prop("checked",true));
			push @js2, qq(\$("#$id").prop("checked",false));
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			my $maindisplay_value = ( $thisfield->{'maindisplay'} // '' ) eq 'no' ? 'false' : 'true';
			push @js3, qq(\$("#$id").prop("checked",$maindisplay_value));
			my $extatt = $self->{'extended'}->{$field};

			if ( ref $extatt eq 'ARRAY' ) {
				foreach my $extended_attribute (@$extatt) {
					say q(<li>);
					say $q->checkbox(
						-name    => "extended_$field..$extended_attribute",
						-id      => "extended_$field\___$extended_attribute",
						-checked => $prefs->{'maindisplayfields'}->{"$field\..$extended_attribute"},
						-value   => 'checked',
						-label   => $extended_attribute
					);
					say q(</li>);
					push @js,  qq(\$("#extended_$field\___$extended_attribute").prop("checked",true));
					push @js2, qq(\$("#extended_$field\___$extended_attribute").prop("checked",false));
					push @js3, qq(\$("#extended_$field\___$extended_attribute").prop("checked",false));
				}
			}
			if ( $field eq $self->{'system'}->{'labelfield'} ) {
				say q(<li>);
				say $q->checkbox(
					-name    => 'field_aliases',
					-id      => 'field_aliases',
					-checked => $prefs->{'maindisplayfields'}->{'aliases'},
					-value   => 'checked',
					-label   => 'aliases'
				);
				say q(</li>);
				push @js,  q($("#field_aliases").prop("checked",true));
				push @js2, q($("#field_aliases").prop("checked",false));
				my $value = $self->{'system'}->{'maindisplay_aliases'}
				  && $self->{'system'}->{'maindisplay_aliases'} eq 'yes' ? 'true' : 'false';
				push @js3, qq(\$("#field_aliases").prop("checked",$value));
			}
		}
		if ( $composites{$field} ) {
			foreach ( keys %composite_display_pos ) {
				next if $composite_display_pos{$_} ne $field;
				say q(<li>);
				say $q->checkbox(
					-name    => "field_$_",
					-id      => "field_$_",
					-checked => $prefs->{'maindisplayfields'}->{$_},
					-value   => 'checked',
					-label   => $_
				);
				say q(</li>);
				push @js,  qq(\$("#field_$_").prop("checked",true));
				push @js2, qq(\$("#field_$_").prop("checked",false));
				my $value = $composite_main_display{$_} ? 'true' : 'false';
				push @js3, qq(\$("#field_$_").prop("checked",$value));
			}
		}
	}
	say q(</ul></div></div>);
	say q(<div style="clear:both;padding-bottom:0.5em">);
	local $" = ';';
	my $all_none_class = RESET_BUTTON_CLASS;
	say qq(<input type="button" value="All" onclick='@js' class="batch $all_none_class" style="display:none" />);
	say qq(<input type="button" value="None" onclick='@js2' class="batch $all_none_class" style="display:none" />);
	say qq(<input type="button" value="Default" onclick='@js3' class="batch $all_none_class" style="display:none" />);
	say $q->submit( -name => 'set', -label => 'Set options', -class => BUTTON_CLASS );
	say q(</div></div>);
	return;
}

sub _print_main_results_sparse_field_options {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $prefs      = $self->{'prefs'};
	my $eav_fields = $self->{'datastore'}->get_eav_fields;
	return if !@$eav_fields;
	say q(<h2>Main results table - phenotypic field selection</h2>);
	say q(<div><p>Select the isolate fields that you wish to be displayed in the main results table )
	  . q(following a query.</p>);
	my ( @js, @js2 );
	say q(<div class="scrollable">);
	say q(<div id="sparse_field_display">);
	say q(<ul>);

	foreach my $eav_field (@$eav_fields) {
		my $field = $eav_field->{'field'};
		say q(<li>);
		( my $id = "field_$field" ) =~ tr/:/_/;
		say $q->checkbox(
			-name    => "field_$field",
			-id      => $id,
			-checked => $prefs->{'maindisplayfields'}->{$field},
			-value   => 'checked',
			-label   => $field
		);
		say q(</li>);
		push @js,  qq(\$("#$id").prop("checked",true));
		push @js2, qq(\$("#$id").prop("checked",false));
		my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
		my $maindisplay_value = ( $thisfield->{'maindisplay'} // '' ) eq 'no' ? 'false' : 'true';
	}
	say q(</ul>);
	say q(</div></div>);
	say q(<div style="clear:both;padding-bottom:0.5em">);
	local $" = ';';
	my $all_none_class = RESET_BUTTON_CLASS;
	say qq(<input type="button" value="All" onclick='@js' class="batch $all_none_class" style="display:none" />);
	say qq(<input type="button" value="None" onclick='@js2' class="batch $all_none_class" style="display:none" />);
	say $q->submit( -name => 'set', -label => 'Set options', -class => BUTTON_CLASS );
	say q(</div></div>);
	return;
}

sub _print_isolate_query_fields_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $prefs  = $self->{'prefs'};
	say q(<h2>Query filters</h2>);
	say q(<div><p>Select the fields for which you would like dropdown lists containing known values )
	  . q(on which to filter query results. These will be available in the filters section of the query )
	  . q(interface.</p>);
	say q(<div class="scrollable">);
	say q(<div id="dropdown_query_filters">);
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
	my @checkfields   = @$field_list;
	my %labels;

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
		foreach my $scheme (@$schemes) {
			my $field = "scheme_$scheme->{'id'}\_profile_status";
			push @checkfields, $field;
			$labels{$field} = "$scheme->{'name'} profile completion";
		}
		push @checkfields, 'Publications';
	}
	my ( @js, @js2, @js3 );
	say q(<div><ul>);
	foreach my $field (@checkfields) {
		next if $field eq 'id';
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
		( my $id = "dropfield_$field" ) =~ tr/:/_/;
		say q(<li>);
		say $q->checkbox(
			-name    => "dropfield_$field",
			-id      => $id,
			-checked => $prefs->{'dropdownfields'}->{$field},
			-value   => 'checked',
			-label   => $labels{$field} || ( $metafield // $field )
		);
		say q(</li>);
		push @js,  qq(\$("#$id").prop("checked",true));
		push @js2, qq(\$("#$id").prop("checked",false));
		my $value;

		if ( $field =~ /^scheme_(\d+)_profile_status/x ) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($1);
			$value = $scheme_info->{'query_status'} ? 'true' : 'false';
		} elsif ( $field eq 'Publications' ) {
			$value =
			  ( $self->{'system'}->{'no_publication_filter'} // '' ) eq 'yes' ? 'false' : 'true';
		} else {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			$value = ( ( $thisfield->{'dropdown'} // '' ) eq 'yes' ) ? 'true' : 'false';
		}
		push @js3, qq(\$("#$id").prop("checked",$value));
		my $extatt = $self->{'extended'}->{$field} // [];
		foreach my $extended_attribute (@$extatt) {
			say q(<li>);
			say $q->checkbox(
				-name    => "dropfield_e_$field\..$extended_attribute",
				-id      => "dropfield_e_$field\___$extended_attribute",
				-checked => $prefs->{'dropdownfields'}->{"$field\..$extended_attribute"},
				-value   => 'checked',
				-label   => $extended_attribute
			);
			say q(</li>);
			push @js,  qq(\$("#dropfield_e_$field\___$extended_attribute").prop("checked",true));
			push @js2, qq(\$("#dropfield_e_$field\___$extended_attribute").prop("checked",false));
			push @js3, qq(\$("#dropfield_e_$field\___$extended_attribute").prop("checked",false));
		}
	}
	say q(</ul></div>);
	say q(</div><div style="clear:both;padding-bottom:0.5em">);
	local $" = ';';
	my $all_none_class = RESET_BUTTON_CLASS;
	say qq(<input type="button" value="All" onclick='@js' class="batch $all_none_class" style="display:none" />);
	say qq(<input type="button" value="None" onclick='@js2' class="batch $all_none_class" style="display:none" />);
	say qq(<input type="button" value="Default" onclick='@js3' class="batch $all_none_class" style="display:none" />);
	say $q->submit( -name => 'set', -label => 'Set options', -class => BUTTON_CLASS );
	say q(</div></div></div>);
	return;
}
1;
