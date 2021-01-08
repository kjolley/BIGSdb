#Written by Keith Jolley
#Copyright (c) 2010-2021, University of Oxford
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
package BIGSdb::IsolateInfoPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::TreeViewPage);
use BIGSdb::Constants qw(:interface :limits);
use Log::Log4perl qw(get_logger);
use Try::Tiny;
use List::MoreUtils qw(none uniq);
my $logger = get_logger('BIGSdb.Page');
use constant ISOLATE_SUMMARY     => 1;
use constant LOCUS_SUMMARY       => 2;
use constant MAX_DISPLAY         => 1000;
use constant HIDE_PMIDS          => 4;
use constant HIDE_PROJECT_LENGTH => 50;

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 1, analysis => 0, query_field => 0 };
	return;
}

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/data_records.html#isolate-records";
}

sub initiate {
	my ($self) = @_;
	if ( $self->{'cgi'}->param('no_header') ) {
		$self->{'type'}    = 'no_header';
		$self->{'noCache'} = 1;
		return;
	}
	$self->{$_} = 1 foreach qw(jQuery jQuery.jstree jQuery.columnizer);
	$self->set_level1_breadcrumbs;
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $show_aliases = $self->{'prefs'}->{'locus_alias'} ? 'none'   : 'inline';
	my $hide_aliases = $self->{'prefs'}->{'locus_alias'} ? 'inline' : 'none';
	my $buffer       = << "END";
\$(function () {
	\$(document).ajaxComplete(function() {
		reloadTooltips();
		\$("span#show_aliases_text").css('display', '$show_aliases');
		\$("span#hide_aliases_text").css('display', '$hide_aliases');
		\$("span#tree_button").css('display', 'inline');
		if (\$("span").hasClass('aliases')){
			\$("span#aliases_button").css('display', 'inline');
		} else {
			\$("span#aliases_button").css('display', 'none');
		}
	});

	\$('.expand_link').on('click', function(){	
		var field = this.id.replace('expand_','');
	  	if (\$('#' + field).hasClass('expandable_expanded')) {
		  	\$('#' + field).switchClass('expandable_expanded','expandable_retracted',1000, "easeInOutQuad", function(){
		  		\$('#expand_' + field).html('<span class="fas fa-chevron-down"></span>');
		  	});	    
	    } else {
		  	\$('#' + field).switchClass('expandable_retracted','expandable_expanded',1000, "easeInOutQuad", function(){
		  		\$('#expand_' + field).html('<span class="fas fa-chevron-up"></span>');
		  	});	    
	  }
	});	
	
	\$( "#show_aliases" ).click(function() {
		if (\$("span#show_aliases_text").css('display') == 'none'){
			\$("span#show_aliases_text").css('display', 'inline');
			\$("span#hide_aliases_text").css('display', 'none');
			if (\$(window).width() >= 600){			
				\$(".data dt").css({"float":"left","clear":"left","width":"12em","text-align":"right"});
				\$(".data dd").css({"margin":"0 0 0 13em"});
			}
		} else {
			\$("span#show_aliases_text").css('display', 'none');
			\$("span#hide_aliases_text").css('display', 'inline');
			\$(".data dt").css({"float":"none","clear":"both","width":"initial","text-align":"initial"});
			\$(".data dd").css({"margin":"initial"});			
		}
		\$( "span.aliases" ).toggle();
		return false;
	});
	\$( "#show_tree" ).click(function() {		
		if (\$("span#show_tree_text").css('display') == 'none'){
			\$("span#show_tree_text").css('display', 'inline');
			\$("span#hide_tree_text").css('display', 'none');
		} else {
			\$("span#show_tree_text").css('display', 'none');
			\$("span#hide_tree_text").css('display', 'inline');
		}
		\$( "div#tree" ).toggle( 'highlight', {} , 500 );
		return false;
	});
	\$("#provenance").columnize({width:450});
	\$(".sparse").columnize({width:450,lastNeverTallest: true,doneFunc:function(){enable_slide_triggers();}});
	\$("#seqbin").columnize({width:300,lastNeverTallest: true});  
	if (!(\$("span").hasClass('aliases'))){
		\$("span#aliases_button").css('display', 'none');
	}
	\$(".slide_panel").click(function() {		
		\$(this).toggle("slide",{direction:"right"},"fast");
	});		
});

function enable_slide_triggers(){
	\$(".slide_trigger").off('click').click(function() {
		var id = \$(this).attr('id');
		var panel = id.replace('expand','slide');
		\$(".slide_panel:not(#" + panel +")").hide("slide",{direction:"right"},"fast");
		\$("#" + panel).toggle("slide",{direction:"right"},"fast");
	});
}

END
	$buffer .= $self->get_tree_javascript;
	return $buffer;
}

sub _get_child_group_scheme_tables {
	my ( $self, $group_id, $isolate_id, $level, $options ) = @_;
	$self->{'level'}     //= 1;
	$self->{'open_divs'} //= 0;
	my $child_groups = $self->{'datastore'}->run_query(
		'SELECT id FROM scheme_groups LEFT JOIN scheme_group_group_members ON scheme_groups.id=group_id '
		  . 'WHERE parent_group_id=? ORDER BY display_order,name',
		$group_id,
		{ fetch => 'col_arrayref', cache => 'IsolateInfoPage::_get_child_group_scheme_tables' }
	);
	my $parent_buffer;
	my $parent_group_info = $self->{'datastore'}->get_scheme_group_info($group_id);
	if ( $self->{'groups_with_data'}->{$group_id} ) {
		my $parent_level = $level - 1;
		if ( $self->{'open_divs'} > $parent_level ) {
			my $divs_to_close = $self->{'open_divs'} - $parent_level;
			for ( 0 .. $divs_to_close - 1 ) {
				$parent_buffer .= qq(</div>\n);
				$self->{'open_divs'}--;
			}
		}
		my $style = $options->{'no_render'} ? q() : q( style="float:left;padding-right:0.5em");
		$parent_buffer .=
		  qq(<div$style>\n) . qq(<h3 class="group group$parent_level">$parent_group_info->{'name'}</h3>\n);
		$self->{'open_divs'}++;
	}
	my $group_buffer = q();
	if (@$child_groups) {
		foreach my $child_group (@$child_groups) {
			if ( $self->{'groups_with_data'}->{$child_group} ) {
				my $group_info = $self->{'datastore'}->get_scheme_group_info($child_group);
				my $new_level  = $level;
				last if $new_level == 10;    #prevent runaway if child is set as the parent of a parental group
				if ( $new_level == $self->{'level'} && $new_level > 1 ) {
					$group_buffer .= qq(</div>\n);
					$self->{'open_divs'}--;
				}
				my $buffer = $self->_get_child_group_scheme_tables( $child_group, $isolate_id, ++$new_level, $options );
				$buffer .= $self->_get_group_scheme_tables( $child_group, $isolate_id, $options );
				$self->{'level'} = $level;
				$group_buffer .= $parent_buffer if $parent_buffer;
				undef $parent_buffer;
				if ($buffer) {
					$group_buffer .= $buffer;
				}
			}
		}
	} else {
		my $buffer = $self->_get_group_scheme_tables( $group_id, $isolate_id, $options );
		$group_buffer .= $parent_buffer if $parent_buffer;
		$group_buffer .= $buffer;
	}
	return $group_buffer;
}

sub _get_group_scheme_tables {
	my ( $self, $group_id, $isolate_id, $options ) = @_;
	my $set_id = $self->get_set_id;
	my $scheme_data = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	my ( $scheme_ids_ref, $desc_ref ) = $self->extract_scheme_desc($scheme_data);
	my $schemes = $self->{'datastore'}->run_query(
		'SELECT scheme_id FROM scheme_group_scheme_members LEFT JOIN schemes ON schemes.id=scheme_id '
		  . 'WHERE group_id=? ORDER BY display_order,description',
		$group_id,
		{ fetch => 'col_arrayref', cache => 'IsolateInfoPage::_get_group_scheme_tables' }
	);
	my $buffer = '';
	if (@$schemes) {
		foreach my $scheme_id (@$schemes) {
			next if !$self->{'prefs'}->{'isolate_display_schemes'}->{$scheme_id};
			next if none { $scheme_id eq $_ } @$scheme_ids_ref;
			if ( !$self->{'scheme_shown'}->{$scheme_id} ) {
				$buffer .= $self->_get_scheme( $scheme_id, $isolate_id, $self->{'curate'}, $options );
				$self->{'scheme_shown'}->{$scheme_id} = 1;
			}
		}
	}
	return $buffer;
}

sub _handle_scheme_ajax {
	my ( $self, $isolate_id ) = @_;
	my $q = $self->{'cgi'};
	return if !$q->param('no_header');
	my $should_display_items = $self->_should_display_items($isolate_id);
	if ( !$should_display_items ) {
		my $param;
		if ( BIGSdb::Utils::is_int( scalar $q->param('group_id') ) ) {
			$param = q(group_id=) . $q->param('group_id');
		} elsif ( BIGSdb::Utils::is_int( scalar $q->param('scheme_id') ) ) {
			$param = q(scheme_id=) . $q->param('scheme_id');
		}
		say q(Too many items to display - )
		  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=info&amp;)
		  . qq(id=$isolate_id&amp;function=scheme_display&amp;$param">display selected schemes separately.</a>);
		return 1;
	}
	if ( BIGSdb::Utils::is_int( scalar $q->param('group_id') ) ) {
		$self->_print_group_data( $isolate_id, scalar $q->param('group_id') );
		return 1;
	} elsif ( BIGSdb::Utils::is_int( scalar $q->param('scheme_id') ) ) {
		$self->_print_scheme_data( $isolate_id, scalar $q->param('scheme_id') );
		return 1;
	}
	return;
}

sub _print_group_data {
	my ( $self, $isolate_id, $group_id, $options ) = @_;
	$self->{'groups_with_data'} =
	  $self->get_tree( $isolate_id, { isolate_display => $self->{'curate'} ? 0 : 1, get_groups => 1 } );
	if ( $group_id == 0 ) {    #Other schemes (not part of a scheme group)
		$self->_print_other_schemes( $isolate_id, $options );
	} else {                   #Scheme group
		say $self->_get_child_group_scheme_tables( $group_id, $isolate_id, 1, $options );
		say $self->_get_group_scheme_tables( $group_id, $isolate_id, $options );
		$self->_close_divs;
	}
	return;
}

sub _print_scheme_data {
	my ( $self, $isolate_id, $scheme_id, $options ) = @_;
	if ( $scheme_id == -1 ) {    #All schemes/loci
		$self->{'groups_with_data'} =
		  $self->get_tree( $isolate_id, { isolate_display => $self->{'curate'} ? 0 : 1, get_groups => 1 } );
		$self->_print_all_loci( $isolate_id, $options );
	} else {
		say $self->_get_scheme( $scheme_id, $isolate_id, $self->{'curate'}, $options );
	}
	return;
}

sub _should_display_items {
	my ( $self, $isolate_id ) = @_;
	my $q     = $self->{'cgi'};
	my $items = 0;
	if ( BIGSdb::Utils::is_int( scalar $q->param('group_id') ) ) {
		my $group_id = $q->param('group_id');
		if ( $group_id == 0 ) {    #Other schemes (not part of a scheme group)
			my $scheme_ids = $self->{'datastore'}->run_query(
				'SELECT id FROM schemes WHERE id NOT IN (SELECT scheme_id FROM '
				  . 'scheme_group_scheme_members) ORDER BY display_order,description',
				undef,
				{ fetch => 'col_arrayref' }
			);
			foreach my $scheme_id (@$scheme_ids) {
				$items += $self->_get_display_items_in_scheme( $isolate_id, $scheme_id );
				return if $items > MAX_DISPLAY;
			}
		} else {                   #Scheme group
			my $schemes = $self->{'datastore'}->get_schemes_in_group($group_id);
			foreach my $scheme_id (@$schemes) {
				$items += $self->_get_display_items_in_scheme( $isolate_id, $scheme_id );
				return if $items > MAX_DISPLAY;
			}
		}
	} elsif ( BIGSdb::Utils::is_int( scalar $q->param('scheme_id') ) ) {
		my $scheme_id = $q->param('scheme_id');
		if ( $scheme_id == -1 ) {    #All schemes/loci
			my $set_id = $self->get_set_id;
			my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
			foreach my $scheme (@$schemes) {
				$items += $self->_get_display_items_in_scheme( $isolate_id, $scheme->{'id'} );
				return if $items > MAX_DISPLAY;
			}
			$items += $self->_get_display_items_in_scheme( $isolate_id, 0 );
		} else {
			$items = $self->_get_display_items_in_scheme( $isolate_id, $scheme_id );
		}
	}
	return if $items > MAX_DISPLAY;
	return 1;
}

sub _get_display_items_in_scheme {
	my ( $self, $isolate_id, $scheme_id ) = @_;
	my $items = 0;
	if ($scheme_id) {
		return 0 if !$self->{'prefs'}->{'isolate_display_schemes'}->{$scheme_id};
		my $should_display = $self->_should_display_scheme( $isolate_id, $scheme_id );
		return 0 if !$should_display;
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		foreach my $field (@$scheme_fields) {
			$items++ if $self->{'prefs'}->{'isolate_display_scheme_fields'}->{$scheme_id}->{$field};
		}
		my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
		foreach my $locus (@$loci) {
			$items++ if $self->{'prefs'}->{'isolate_display_loci'}->{$locus} ne 'hide';
		}
	} else {
		my $loci = $self->{'datastore'}->get_loci_in_no_scheme;
		my $list_table = $self->{'datastore'}->create_temp_list_table_from_array( 'text', $loci );
		my $loci_with_designations =
		  $self->{'datastore'}->run_query(
			"SELECT locus FROM allele_designations WHERE isolate_id=? AND locus IN (SELECT value FROM $list_table)",
			$isolate_id, { fetch => 'col_arrayref' } );
		my $loci_with_seqs =
		  $self->{'datastore'}->run_query(
			"SELECT locus FROM allele_sequences WHERE isolate_id=? AND locus IN (SELECT value FROM $list_table)",
			$isolate_id, { fetch => 'col_arrayref' } );
		foreach my $locus ( uniq( @$loci_with_designations, @$loci_with_seqs ) ) {
			$items++ if $self->{'prefs'}->{'isolate_display_loci'}->{$locus} ne 'hide';
		}
	}
	return $items;
}

sub _print_separate_scheme_data {
	my ( $self, $isolate_id ) = @_;
	my $q = $self->{'cgi'};
	if ( BIGSdb::Utils::is_int( scalar $q->param('group_id') ) ) {
		say q(<div class="box resultspanel large_scheme">);
		say q(<div id="profile" style="overflow:hidden;min-height:30em" class="expandable_retracted">);
		say $self->_get_show_aliases_button( 'block', { show_aliases => 0 } );
		$self->_print_group_data( $isolate_id, scalar $q->param('group_id'), { show_aliases => 0, no_render => 1 } );
		say q(</div>);
		say q(<div class="expand_link" id="expand_profile"><span class="fas fa-chevron-down"></span></div>);
		say q(</div>);
	} elsif ( BIGSdb::Utils::is_int( scalar $q->param('scheme_id') ) ) {
		say q(<div class="box resultspanel large_scheme">);
		say q(<div id="profile" style="overflow:hidden;min-height:30em" class="expandable_retracted">);
		say $self->_get_show_aliases_button( 'block', { show_aliases => 0, show_aliases => 0 } );
		$self->_print_scheme_data( $isolate_id, scalar $q->param('scheme_id'), { show_aliases => 0, no_render => 1 } );
		say q(</div>);
		say q(<div class="expand_link" id="expand_profile"><span class="fas fa-chevron-down"></span></div>);
		say q(</div>);
	} else {
		$self->print_bad_status(
			{
				message  => q(No scheme or group passed.),
				navbar   => 1,
				back_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=info&amp;id=$isolate_id)
			}
		);
	}
	return;
}

sub print_content {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $isolate_id = $q->param('id');
	my $set_id     = $self->get_set_id;
	my $scheme_data = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	return if $self->_handle_scheme_ajax($isolate_id);
	if ( !defined $isolate_id || $isolate_id eq '' ) {
		say q(<h1>Isolate information</h1>);
		say q(<div class="box statusbad"><p>No isolate id provided.</p></div>);
		return;
	} elsif ( !BIGSdb::Utils::is_int($isolate_id) ) {
		say q(<h1>Isolate information</h1>);
		$self->print_bad_status( { message => q(Isolate id must be an integer.) } );
		return;
	}
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		say q(<h1>Isolate information</h1>);
		$self->print_bad_status( { message => q(This function can only be called for isolate databases.) } );
		return;
	}
	my $data =
	  $self->{'datastore'}
	  ->run_query( "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id, { fetch => 'row_hashref' } );
	if ( !$data ) {
		say qq(<h1>Isolate information: id-$isolate_id</h1>);
		$self->print_bad_status( { message => q(The database contains no record of this isolate.) } );
		return;
	} elsif ( !$self->is_allowed_to_view_isolate($isolate_id) ) {
		say q(<h1>Isolate information</h1>);
		$self->print_bad_status(
			{
				message => q(Your user account does not have permission to view this record.),
			}
		);
		return;
	}
	my $identifier;
	if ( ( $data->{ $self->{'system'}->{'labelfield'} } // q() ) ne q() ) {
		my $field = $self->{'system'}->{'labelfield'};
		$field =~ tr/_/ /;
		$identifier = qq($field $data->{lc($self->{'system'}->{'labelfield'})} (id:$data->{'id'}));
	} else {
		$identifier = qq(id $data->{'id'});
	}
	if ( ( $q->param('function') // q() ) eq 'scheme_display' ) {
		say qq(<h1>Selected scheme/locus breakdown for $identifier</h1>);
		$self->_print_separate_scheme_data($isolate_id);
		return;
	}
	say qq(<h1>Full information on $identifier</h1>);
	$self->_print_action_panel($isolate_id) if $self->{'curate'};
	$self->_print_projects($isolate_id);
	say q(<div class="box" id="resultspanel">);
	say $self->get_isolate_record($isolate_id);
	my $tree_button =
	    q( <span id="tree_button" style="margin-left:1em;display:none">)
	  . q(<a id="show_tree" class="small_submit" style="cursor:pointer">)
	  . q(<span id="show_tree_text" style="display:none"><span class="fa fas fa-eye"></span> Show</span>)
	  . q(<span id="hide_tree_text" style="display:inline">)
	  . q(<span class="fa fas fa-eye-slash"></span> Hide</span> tree</a></span>);
	my $aliases_button = $self->_get_show_aliases_button;
	my $loci = $self->{'datastore'}->get_loci( { set_id => $set_id } );

	if ( @$loci && $self->_should_show_schemes($isolate_id) ) {
		say $self->_get_classification_group_data($isolate_id);
		say q(<div><span class="info_icon fas fa-2x fa-fw fa-table fa-pull-left" style="margin-top:0.3em"></span>);
		say qq(<h2 style="display:inline-block">Schemes and loci</h2>$tree_button$aliases_button<div>);
		if ( @$scheme_data < 3 && @$loci <= 100 ) {
			my $schemes =
			  $self->{'datastore'}
			  ->run_query( 'SELECT id FROM schemes ORDER BY display_order,id', undef, { fetch => 'col_arrayref' } );
			my $values_present;
			foreach ( @$schemes, 0 ) {
				next if $_ && !$self->{'prefs'}->{'isolate_display_schemes'}->{$_};
				my $buffer = $self->_get_scheme( $_, $isolate_id, $self->{'curate'} );
				if ($buffer) {
					say $buffer;
					say q(<div style="clear:both"></div>);
					$values_present = 1;
				}
			}
			if ( !$values_present ) {
				say q(<p>No alleles designated.</p>);
			}
		} else {
			say $self->_get_tree($isolate_id);
		}
		say q(</div></div>);
	}
	$self->_print_plugin_buttons($isolate_id);
	say q(</div>);
	return;
}

sub _should_show_schemes {
	my ( $self, $isolate_id ) = @_;
	return 1
	  if $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM allele_designations WHERE isolate_id=?)', $isolate_id );
	return 1
	  if $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM allele_sequences WHERE isolate_id=?)', $isolate_id );
	return;
}

sub _get_show_aliases_button {
	my ( $self, $display, $options ) = @_;
	$display //= 'none';
	my $show_aliases = $options->{'show_aliases'} // $self->{'prefs'}->{'locus_alias'} ? 'none'   : 'inline';
	my $hide_aliases = $options->{'show_aliases'} // $self->{'prefs'}->{'locus_alias'} ? 'inline' : 'none';
	return
	    qq(<span id="aliases_button" style="margin-left:1em;display:$display">)
	  . q(<a id="show_aliases" class="small_submit" style="cursor:pointer">)
	  . qq(<span id="show_aliases_text" style="display:$show_aliases"><span class="fa fas fa-eye"></span> )
	  . qq(show</span><span id="hide_aliases_text" style="display:$hide_aliases">)
	  . q(<span class="fa fas fa-eye-slash"></span> hide</span> )
	  . q(locus aliases</a></span>);
}

sub _print_plugin_buttons {
	my ( $self, $isolate_id ) = @_;
	my $q = $self->{'cgi'};
	my $plugin_categories = $self->{'pluginManager'}->get_plugin_categories( 'info', $self->{'system'}->{'dbtype'} );
	return if !@$plugin_categories;
	my $buffer;
	my %icon = (
		Breakdown     => 'fas fa-chart-pie',
		Export        => 'far fa-save',
		Analysis      => 'fas fa-chart-line',
		'Third party' => 'fas fa-external-link-alt',
		Miscellaneous => 'far fa-file-alt'
	);
	my $set_id = $self->get_set_id;
	foreach my $category (@$plugin_categories) {
		my $cat_buffer;
		my $plugin_names = $self->{'pluginManager'}->get_appropriate_plugin_names(
			'isolate_info',
			$self->{'system'}->{'dbtype'},
			$category || 'none',
			{ single_isolate => $isolate_id }
		);
		if (@$plugin_names) {
			my $plugin_buffer;
			$q->param( calling_page => scalar $q->param('page') );
			foreach my $plugin_name (@$plugin_names) {
				my $att = $self->{'pluginManager'}->get_plugin_attributes($plugin_name);
				next if $att->{'min'} && $att->{'min'} > 1;
				$plugin_buffer .= $q->start_form( -style => 'float:left;margin-right:0.2em;margin-bottom:0.3em' );
				$q->param( page           => 'plugin' );
				$q->param( name           => $att->{'module'} );
				$q->param( single_isolate => $isolate_id );
				$q->param( set_id         => $set_id );
				$plugin_buffer .= $q->hidden($_) foreach qw (db page name calling_page set_id single_isolate);
				$plugin_buffer .=
				  $q->submit( -label => ( $att->{'buttontext'} || $att->{'menutext'} ), -class => 'plugin_button' );
				$plugin_buffer .= $q->end_form;
			}
			if ($plugin_buffer) {
				$category = 'Miscellaneous' if !$category;
				$cat_buffer .=
				    q(<div><span style="float:left;text-align:right;width:8em;)
				  . q(white-space:nowrap;margin-right:0.5em">)
				  . qq(<span class="fa-fw fa-lg $icon{$category} info_plugin_icon" style="margin-right:0.2em">)
				  . qq(</span>$category:</span>)
				  . q(<div style="margin-left:8.5em;margin-bottom:0.2em">);
				$cat_buffer .= $plugin_buffer;
				$cat_buffer .= q(</div></div>);
			}
		}
		$buffer .= qq($cat_buffer<div style="clear:both"></div>) if $cat_buffer;
	}
	if ($buffer) {
		say q(<div><span class="info_icon fas fa-2x fa-fw fa-chart-bar fa-pull-left" style="margin-top:-0.2em"></span>);
		say q(<h2>Tools</h2>);
		say $buffer;
		say q(</div>);
	}
	return;
}

sub _close_divs {
	my ($self) = @_;
	if ( $self->{'open_divs'} ) {
		for ( 0 .. $self->{'open_divs'} - 1 ) {
			say q(</div>);
		}
		$self->{'open_divs'} = 0;
	}
	return;
}

sub _are_cgfields_defined {
	my ($self) = @_;
	return $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM classification_group_fields)');
}

sub _get_classification_group_data {
	my ( $self, $isolate_id ) = @_;
	my $view   = $self->{'system'}->{'view'};
	my $buffer = q();
	my $classification_schemes =
	  $self->{'datastore'}->run_query( 'SELECT * FROM classification_schemes ORDER BY display_order,name',
		undef, { fetch => 'all_arrayref', slice => {} } );
	my $td                = 1;
	my $cg_fields_defined = $self->_are_cgfields_defined;
	foreach my $cscheme (@$classification_schemes) {
		my ( $cg_buffer, $cgf_buffer );
		my $scheme_id = $cscheme->{'scheme_id'};
		my $cache_table_exists =
		  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)',
			["temp_isolates_scheme_fields_$scheme_id"] );
		if ( !$cache_table_exists ) {
			$logger->warn( "Scheme $scheme_id is not cached for this database.  Display of similar isolates "
				  . 'is disabled. You need to run the update_scheme_caches.pl script regularly against this '
				  . 'database to create these caches.' );
			return q();
		}
		my $scheme_info  = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		my $scheme_table = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
		my $pk           = $scheme_info->{'primary_key'};
		my $pk_values =
		  $self->{'datastore'}
		  ->run_query( "SELECT $pk FROM $scheme_table WHERE id=?", $isolate_id, { fetch => 'col_arrayref' } );
		if (@$pk_values) {
			my $cscheme_table = $self->{'datastore'}->create_temp_cscheme_table( $cscheme->{'id'} );

			#You may get multiple groups if you have a mixed sample
			my %group_displayed;
			foreach my $pk_value (@$pk_values) {
				my $groups = $self->{'datastore'}->run_query( "SELECT group_id FROM $cscheme_table WHERE profile_id=?",
					$pk_value, { fetch => 'col_arrayref' } );
				foreach my $group_id (@$groups) {
					next if $group_displayed{$group_id};
					my $isolate_count = $self->{'datastore'}->run_query(
						"SELECT COUNT(*) FROM $view WHERE $view.id IN (SELECT id FROM $scheme_table WHERE $pk IN "
						  . "(SELECT profile_id FROM $cscheme_table WHERE group_id=?)) AND new_version IS NULL",
						$group_id
					);
					if ( $isolate_count > 1 ) {
						my $cg_fields = $self->get_classification_group_fields( $cscheme->{'id'}, $group_id );
						$cgf_buffer .= qq($cg_fields<br />) if $cg_fields;
						my $url =
						    qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;)
						  . qq(designation_field1=cg_$cscheme->{'id'}_group&amp;designation_value1=$group_id&amp;)
						  . q(submit=1);
						$cg_buffer .= qq(group: <a href="$url">$group_id ($isolate_count isolates)</a><br />\n);
						$group_displayed{$group_id} = 1;
					}
				}
			}
		}
		if ($cg_buffer) {
			my $desc = $cscheme->{'description'};
			my $tooltip =
			    $desc
			  ? $self->get_tooltip(qq($cscheme->{'name'} - $desc))
			  : q();
			my $plural = $cscheme->{'inclusion_threshold'} == 1 ? q() : q(es);
			$buffer .=
			    qq(<tr class="td$td"><td>$cscheme->{'name'}$tooltip</td><td>$scheme_info->{'name'}</td>)
			  . qq(<td>Single-linkage</td><td>$cscheme->{'inclusion_threshold'}</td><td>$cscheme->{'status'}</td><td>)
			  . qq($cg_buffer</td>);
			if ($cg_fields_defined) {
				$buffer .= $cgf_buffer ? qq(<td>$cgf_buffer</td>) : q(<td></td>);
			}
			$buffer .= q(</tr>);
			$td = $td == 1 ? 2 : 1;
		}
	}
	if ($buffer) {
		my $fields_header = $cg_fields_defined ? q(<th>Fields</th>) : q();
		$buffer =
		    q(<div><span class="info_icon fas fa-2x fa-fw fa-sitemap fa-pull-left" )
		  . q(style="margin-top:-0.2em"></span>)
		  . q(<h2>Similar isolates (determined by classification schemes)</h2>)
		  . q(<p>Experimental schemes are subject to change and are not a stable part of the nomenclature.</p>)
		  . q(<div class="scrollable">)
		  . q(<table class="resultstable"><tr>)
		  . q(<th>Classification scheme</th><th>Underlying scheme</th><th>Clustering method</th>)
		  . qq(<th>Mismatch threshold</th><th>Status</th><th>Group</th>$fields_header</tr>)
		  . qq($buffer</table></div></div>);
	}
	return $buffer;
}

sub get_classification_group_fields {
	my ( $self, $cg_scheme_id, $group_id ) = @_;
	my $cgfv_table = $self->{'datastore'}->create_temp_cscheme_field_values_table($cg_scheme_id);
	my $data       = $self->{'datastore'}->run_query(
		"SELECT cgfv.* FROM $cgfv_table cgfv JOIN classification_group_fields "
		  . 'cgf ON cgf.cg_scheme_id=? AND cgfv.field=cgf.field WHERE '
		  . 'group_id=? ORDER BY cgf.field_order,cgf.field',
		[ $cg_scheme_id, $group_id ],
		{ fetch => 'all_arrayref', slice => {} }
	);
	my @values;
	foreach my $field (@$data) {
		push @values, qq($field->{'field'}: $field->{'value'});
	}
	local $" = q(; );
	return qq(@values);
}

sub _print_other_schemes {
	my ( $self, $isolate_id, $options ) = @_;
	my $scheme_ids = $self->{'datastore'}->run_query(
		'SELECT id FROM schemes WHERE id NOT IN (SELECT scheme_id FROM '
		  . 'scheme_group_scheme_members) ORDER BY display_order,description',
		undef,
		{ fetch => 'col_arrayref' }
	);
	foreach my $scheme_id (@$scheme_ids) {
		next if !$self->{'prefs'}->{'isolate_display_schemes'}->{$scheme_id};
		my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
		say $self->_get_scheme( $scheme_id, $isolate_id, $self->{'curate'}, $options );
	}
	return;
}

sub _print_all_loci {
	my ( $self, $isolate_id, $options ) = @_;
	my $groups_with_no_parents = $self->{'datastore'}->run_query(
		'SELECT id FROM scheme_groups WHERE id NOT IN (SELECT group_id '
		  . 'FROM scheme_group_group_members) ORDER BY display_order,name',
		undef,
		{ fetch => 'col_arrayref' }
	);
	if ( keys %{ $self->{'groups_with_data'} } ) {
		foreach my $group_id (@$groups_with_no_parents) {
			say $self->_get_child_group_scheme_tables( $group_id, $isolate_id, 1, $options );
			say $self->_get_group_scheme_tables( $group_id, $isolate_id, $options );
			$self->_close_divs;
		}
		if ( $self->{'groups_with_data'}->{0} ) {    #Schemes not in groups
			my $style = $options->{'no_render'} ? q() : q( style="float:left;padding-right:0.5em");
			say qq(<div$style><h3 class="group group0">Other schemes</h3>);
			$self->_print_other_schemes( $isolate_id, $options );
			say q(</div>);
		}
	} else {
		my $schemes =
		  $self->{'datastore'}
		  ->run_query( 'SELECT id FROM schemes ORDER BY display_order,id', undef, { fetch => 'col_arrayref' } );
		foreach (@$schemes) {
			next if !$self->{'prefs'}->{'isolate_display_schemes'}->{$_};
			say $self->_get_scheme( $_, $isolate_id, $self->{'curate'} );
		}
	}
	my $no_scheme_data = $self->_get_scheme( 0, $isolate_id, $self->{'curate'}, $options );
	if ($no_scheme_data) {    #Loci not in schemes
		my $style = $options->{'no_render'} ? q() : q( style="float:left;padding-right:0.5em");
		say qq(<div$style>);
		say q(<h3 class="group group0">&nbsp;</h3>);
		say $no_scheme_data;
		say q(</div>);
	}
	return;
}

sub _print_action_panel {
	my ( $self, $isolate_id ) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="resultsheader"><div class="scrollable">);
	my %titles = (
		isolateDelete => 'Delete record',
		isolateUpdate => 'Update record',
		addSeqbin     => 'Sequence bin',
		newVersion    => 'New version',
		tagScan       => 'Sequence tags',
		publish       => 'Make public',
	);
	my %labels = (
		isolateDelete => 'Delete',
		isolateUpdate => 'Update',
		addSeqbin     => 'Upload contigs',
		newVersion    => 'Create',
		tagScan       => 'Scan',
		publish       => 'Publish'
	);
	$q->param( isolate_id => $isolate_id );
	my $page = $q->param('page');
	my $seqbin_exists =
	  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM seqbin_stats WHERE isolate_id=?)', $isolate_id );
	my $private =
	  $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM private_isolates WHERE isolate_id=?)', $isolate_id );

	foreach my $action (qw (isolateDelete isolateUpdate addSeqbin newVersion tagScan publish)) {
		next
		  if $action eq 'tagScan'
		  && ( !$seqbin_exists
			|| ( !$self->can_modify_table('allele_designations') && !$self->can_modify_table('allele_sequences') ) );
		next if $action eq 'addSeqbin' && !$self->can_modify_table('sequence_bin');
		next if $action eq 'publish'   && !$private;
		say qq(<fieldset style="float:left"><legend>$titles{$action}</legend>);
		say $q->start_form;
		$q->param( page => $action );
		say $q->hidden($_) foreach qw (db page id isolate_id);
		say q(<div style="text-align:center">);
		say $q->submit( -name => $labels{$action}, -class => 'small_submit' );
		say q(</div>);
		say $q->end_form;
		say q(</fieldset>);
	}
	$q->param( page => $page );    #Reset
	say q(</div></div>);
	return;
}

sub get_isolate_summary {
	my ( $self, $id ) = @_;
	return $self->get_isolate_record( $id, ISOLATE_SUMMARY );
}

sub get_loci_summary {
	my ( $self, $id ) = @_;
	return $self->get_isolate_record( $id, LOCUS_SUMMARY );
}

sub get_isolate_record {
	my ( $self, $id, $summary_view ) = @_;
	$summary_view ||= 0;
	my $buffer;
	my $q = $self->{'cgi'};
	my $data =
	  $self->{'datastore'}
	  ->run_query( "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?", $id, { fetch => 'row_hashref' } );
	if ( !$data ) {
		$logger->error("Record $id does not exist");
		BIGSdb::Exception::Database::NoRecord->throw("Record $id does not exist");
	}
	$buffer .= q(<div class="scrollable">);
	if ( $summary_view == LOCUS_SUMMARY ) {
		$buffer .= $self->_get_tree($id);
	} else {
		$buffer .= $self->_get_provenance_fields( $id, $data, $summary_view );
		if ( !$summary_view ) {
			$buffer .= $self->_get_secondary_metadata_fields($id);
			$buffer .= $self->_get_version_links($id);
			$buffer .= $self->_get_ref_links($id);
			$buffer .= $self->_get_seqbin_link($id);
			$buffer .= $self->_get_annotation_metrics($id);
		}
	}
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_provenance_fields {
	my ( $self, $isolate_id, $data, $summary_view ) = @_;
	my $buffer;
	my ( $private_owner, $request_publish ) =
	  $self->{'datastore'}
	  ->run_query( 'SELECT user_id,request_publish FROM private_isolates WHERE isolate_id=?', $isolate_id );
	if ( defined $private_owner ) {
		my $user_string = $self->{'datastore'}->get_user_string($private_owner);
		my $request_string = $request_publish ? q( - publication requested.) : q();
		$buffer .=
		    q(<p style="float:right"><span class="main_icon fas fa-2x fa-user-secret"></span> )
		  . qq(<span class="warning" style="padding: 0.1em 0.5em">Private record owned by $user_string)
		  . qq($request_string</span></p>);
	}
	$buffer .= q(<div><span class="info_icon fas fa-2x fa-fw fa-globe fa-pull-left" style="margin-top:-0.2em"></span>);
	$buffer .= qq(<h2>Provenance/primary metadata</h2>\n);
	$buffer .= q(<div id="provenance">);
	my $list       = [];
	my $q          = $self->{'cgi'};
	my $set_id     = $self->get_set_id;
	my $is_curator = $self->is_curator;
	my $field_list = $self->{'xmlHandler'}->get_field_list( { no_curate_only => !$is_curator } );
	my ( %composites, %composite_display_pos );
	my $composite_data =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id,position_after FROM composite_fields', undef, { fetch => 'all_arrayref', slice => {} } );

	foreach (@$composite_data) {
		$composite_display_pos{ $_->{'id'} }  = $_->{'position_after'};
		$composites{ $_->{'position_after'} } = 1;
	}
	my $field_with_extended_attributes;
	if ( !$summary_view ) {
		$field_with_extended_attributes =
		  $self->{'datastore'}->run_query( 'SELECT DISTINCT isolate_field FROM isolate_field_extended_attributes',
			undef, { fetch => 'col_arrayref' } );
	}
	foreach my $field (@$field_list) {
		my $displayfield = $field;
		$displayfield =~ tr/_/ /;
		my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
		local $" = q(; );
		if ( !defined $data->{ lc($field) } ) {
			if ( $composites{$field} ) {
				my $composites =
				  $self->_get_composite_field_rows( $isolate_id, $data, $field, \%composite_display_pos );
				push @$list, @$composites if @$composites;
			}
			next;    #Do not print row
		}
		my ( $web, $value );
		if ( $thisfield->{'web'} ) {
			$web = $self->_get_web_links( $data, $field );
		} else {
			if ( ref $data->{ lc($field) } ) {
				if ( ( $thisfield->{'optlist'} // q() ) eq 'yes' ) {
					my $optlist = $self->{'xmlHandler'}->get_field_option_list($field);
					$data->{ lc($field) } =
					  BIGSdb::Utils::arbitrary_order_list( $optlist, $data->{ lc($field) } );
				} else {
					@{ $data->{ lc($field) } } =
					  $thisfield->{'type'} eq 'text'
					  ? sort { $a cmp $b } @{ $data->{ lc($field) } }
					  : sort { $a <=> $b } @{ $data->{ lc($field) } };
				}
			}
			$value = ref $data->{ lc($field) } ? qq(@{$data->{ lc($field) }}) : $data->{ lc($field) };
			$value = BIGSdb::Utils::escape_html($value);
		}
		my %user_field = map { $_ => 1 } qw(curator sender);
		if ( $user_field{$field} || ( $thisfield->{'userfield'} // '' ) eq 'yes' ) {
			push @$list, $self->_get_user_field( $summary_view, $field, $displayfield, $value, $data );
		} else {

			#https://stackoverflow.com/questions/6038061/regular-expression-to-find-urls-within-a-string
			## no critic (ProhibitComplexRegexes)
			if ( defined $value
				&& $value =~
				/((http|ftp|https):\/\/([\w_-]+(?:(?:\.[\w_-]+)+))([\w.,@?^=%&:\/~+#-]*[\w@?^=%&\/~+#-])?)/x )
			{
				my $url       = $1;
				my $hyperlink = qq(<a href="$url">$url</a>);
				$value =~ s/$url/$hyperlink/gx;
			}
			push @$list, { title => $displayfield, data => ( $web // $value ) } if $web || $value ne q();
		}
		if ( $field eq 'curator' ) {
			my $history = $self->_get_history_field($isolate_id);
			push @$list, $history if $history;
		}
		my %ext_attribute_field = map { $_ => 1 } @$field_with_extended_attributes;
		if ( $ext_attribute_field{$field} ) {
			my $ext_list = $self->_get_field_extended_attributes( $field, $value );
			push @$list, @$ext_list if @$ext_list;
		}
		if ( $field eq $self->{'system'}->{'labelfield'} ) {
			my $aliases = $self->{'datastore'}->get_isolate_aliases($isolate_id);
			if (@$aliases) {
				local $" = q(; );
				my $plural = @$aliases > 1 ? 'es' : '';
				push @$list, { title => "alias$plural", data => "@$aliases" };
			}
		}
		if ( $composites{$field} ) {
			my $composites = $self->_get_composite_field_rows( $isolate_id, $data, $field, \%composite_display_pos );
			push @$list, @$composites if @$composites;
		}
	}
	$buffer .= $self->get_list_block( $list, { columnize => 1 } );
	$buffer .= q(</div></div>);
	return $buffer;
}

sub _get_web_links {
	my ( $self, $data, $field ) = @_;
	my $q         = $self->{'cgi'};
	my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
	my $web;
	my @values = ref $data->{ lc($field) } ? @{ $data->{ lc($field) } } : ( $data->{ lc($field) } );
	my @links;
	my $domain;
	if ( ( lc( $thisfield->{'web'} ) =~ /https?:\/\/(.*?)\/+/x ) ) {
		$domain = $1;
	}
	foreach my $value (@values) {
		my $url = $thisfield->{'web'};
		$url =~ s/\[\\*\?\]/$value/x;
		$url =~ s/\&/\&amp;/gx;
		push @links, qq(<a href="$url">$value</a>);
	}
	if (@links) {
		local $" = q(; );
		$web = qq(@links);
	}
	if ( $domain && $domain ne $q->virtual_host ) {
		$web .= qq( <span class="link">$domain)
		  . q(<span class="fa fas fa-external-link-alt" style="margin-left:0.5em"></span></span>);
	}
	return $web;
}

sub _get_secondary_metadata_fields {
	my ( $self, $isolate_id ) = @_;
	my $buffer = q();
	my @slide_panel;
	my $eav_fields = $self->{'datastore'}->get_eav_fields;
	return $buffer if !@$eav_fields;
	my $data = {};
	foreach my $table (qw(eav_int eav_float eav_text eav_date eav_boolean)) {
		my $table_values = $self->{'datastore'}->run_query( "SELECT field,value FROM $table WHERE isolate_id=?",
			$isolate_id, { fetch => 'all_arrayref', slice => {} } );
		$data->{ $_->{'field'} } = $_->{'value'} foreach @$table_values;
	}
	return $buffer if !keys %$data;
	my $field_name    = $self->{'system'}->{'eav_fields'} // 'secondary metadata';
	my $uc_field_name = ucfirst($field_name);
	my $icon          = $self->{'system'}->{'eav_field_icon'} // 'fas fa-microscope';
	$buffer .= qq(<div><span class="info_icon fa-2x fa-fw $icon fa-pull-left" )
	  . qq(style="margin-top:-0.2em"></span><h2 style="display:inline">$uc_field_name</h2>\n);
	my $hide = keys %$data > MAX_EAV_FIELD_LIST ? 1 : 0;
	my $class = $hide ? q(expandable_retracted) : q();
	my $categories =
	  $self->{'datastore'}->run_query( 'SELECT DISTINCT category FROM eav_fields ORDER BY category NULLS LAST',
		undef, { fetch => 'col_arrayref' } );
	$buffer .= qq(<div id="sparse" style="overflow:hidden;margin-top:1em" class="$class">);

	foreach my $cat (@$categories) {
		my $list = [];
		foreach my $field (@$eav_fields) {
			if ( $field->{'category'} ) {
				next if !$cat || $cat ne $field->{'category'};
			} else {
				next if $cat;
			}
			my $fieldname = $field->{'field'};
			( my $cleaned = $fieldname ) =~ tr/_/ /;
			next if !defined $data->{$fieldname};
			my $value = $data->{$fieldname};
			if ( $field->{'conditional_formatting'} ) {
				$field->{'conditional_formatting'} =~ s/;;/__SEMICOLON__/gx;
				my @terms = split /\s*;\s*/x, $field->{'conditional_formatting'};
				foreach my $term (@terms) {
					my ( $check_value, $format ) = split /\s*\|\s*/x, $term;
					$format =~ s/__SEMICOLON__/;/gx;
					if ( $value eq $check_value ) {
						$value = $format;
					}
				}
			}
			if ( $field->{'html_message'} ) {
				my $link_text = $field->{'html_link_text'} // 'info';
				$value .= qq(&nbsp;<a id="expand_$field->{'field'}" class="slide_trigger">)
				  . qq(<span class="fas fa-caret-left"></span> $link_text</a>);
				push @slide_panel,
				  {
					field => $field,
					data  => $field->{'html_message'}
				  };
			}
			$value =~ s/;/;<br \/>/gx;
			$value =~ s/PMID:(\d+)/PMID:<a href="https:\/\/pubmed.ncbi.nlm.nih.gov\/$1">$1<\/a>/gx;
			push @$list,
			  {
				title => $cleaned,
				data  => $value
			  };
		}
		if ( @$categories && $categories->[0] && @$list ) {
			my $group_icon = $self->get_eav_group_icon($cat);
			$buffer .= q(<div style="margin-top:0.5em;padding-left:1.5em">);
			if ($group_icon) {
				$buffer .= qq(<span class="subinfo_icon fa-lg fa-fw $group_icon fa-pull-left" )
				  . qq(style="margin-right:0.5em"></span><h3 style="display:inline">$cat</h3>);
			} else {
				$buffer .= $cat ? qq(<h3>$cat</h3>) : q(<h3>Other</h3>);
			}
			$buffer .= q(</div>);
		}
		$buffer .= q(<div class="sparse">);
		$buffer .= $self->get_list_block( $list, { columnize => 1 } );
		$buffer .= q(</div>);
	}
	$buffer .= q(</div></div>);
	foreach my $spanel (@slide_panel) {
		$buffer .= qq(<div class="slide_panel" id="slide_$spanel->{'field'}->{'field'}">$spanel->{'data'});
		$buffer .= q(<p class="feint">Click to close</p>);
		$buffer .= qq(</div>\n);
	}
	if ($hide) {
		$buffer .= q(<div class="expand_link" id="expand_sparse"><span class="fas fa-chevron-down"></span></div>);
	}
	return $buffer;
}

sub _get_field_extended_attributes {
	my ( $self, $field, $value ) = @_;
	my $list = [];
	my $q    = $self->{'cgi'};
	my $attribute_order =
	  $self->{'datastore'}
	  ->run_query( 'SELECT attribute,field_order FROM isolate_field_extended_attributes WHERE isolate_field=?',
		$field, { fetch => 'all_arrayref', slice => {} } );
	my %order = map { $_->{'attribute'} => $_->{'field_order'} } @$attribute_order;
	my $attribute_list = $self->{'datastore'}->run_query(
		'SELECT attribute,value FROM isolate_value_extended_attributes WHERE (isolate_field,field_value)=(?,?)',
		[ $field, $value ],
		{ fetch => 'all_arrayref', slice => {} }
	);
	my %attributes = map { $_->{'attribute'} => $_->{'value'} } @$attribute_list;
	if ( keys %attributes ) {
		my $rows = keys %attributes || 1;
		foreach my $attribute ( sort { ( $order{$a} // 0 ) <=> ( $order{$b} // 0 ) } keys(%attributes) ) {
			my $url =
			  $self->{'datastore'}
			  ->run_query( 'SELECT url FROM isolate_field_extended_attributes WHERE (isolate_field,attribute)=(?,?)',
				[ $field, $attribute ] );
			my $att_web;
			if ($url) {
				$url =~ s/\[\?\]/$attributes{$attribute}/x;
				$url =~ s/\&/\&amp;/gx;
				my $domain;
				if ( ( lc($url) =~ /http:\/\/(.*?)\/+/x ) ) {
					$domain = $1;
				}
				$att_web = qq(<a href="$url">$attributes{$attribute}</a>) if $url;
				if ( $domain && $domain ne $q->virtual_host ) {
					$att_web .= qq( <span class="link"><span style="font-size:1.2em">&rarr;</span> $domain</span>);
				}
			}
			( my $display_field = $attribute ) =~ tr/_/ /;
			push @$list,
			  {
				title => $display_field,
				data  => ( $att_web || $attributes{$attribute} )
			  };
		}
	}
	return $list;
}

sub _get_user_field {
	my ( $self, $summary_view, $field, $display_field, $value, $data ) = @_;
	my $userdata = $self->{'datastore'}->get_user_info($value);
	my $colspan  = $summary_view ? 5 : 2;
	my $person   = qq($userdata->{first_name} $userdata->{surname});
	if ( !$summary_view && !( $field eq 'sender' && $data->{'sender'} == $data->{'curator'} ) ) {
		my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
		$person .= qq(, $userdata->{affiliation}) if $value > 0;
		if (
			$field eq 'curator'
			|| ( ( $field eq 'sender' || ( ( $thisfield->{'userfield'} // '' ) eq 'yes' ) )
				&& !$self->{'system'}->{'privacy'} )
		  )
		{
			if ( $value > 0 && $userdata->{'email'} =~ /@/x ) {
				$person .= qq( (E-mail: <a href="mailto:$userdata->{'email'}">$userdata->{'email'}</a>));
			}
		}
	}
	return {
		title => $display_field,
		data  => $person
	};
}

sub _get_history_field {
	my ( $self, $isolate_id ) = @_;
	my $q = $self->{'cgi'};
	my ( $history, $num_changes ) = $self->_get_history( $isolate_id, 10 );
	return if !$num_changes;
	my $plural = $num_changes == 1 ? '' : 's';
	my $title;
	$title = q(Update history - );
	foreach (@$history) {
		my $time = $_->{'timestamp'};
		$time =~ s/ \d\d:\d\d:\d\d\.\d+//x;
		my $action = $_->{'action'};
		if ( $action =~ /<br\ \/>/x ) {
			$action = q(multiple updates);
		}
		$action =~ s/[\r\n]//gx;
		$action =~ s/:.*//x;
		$title .= qq($time: $action<br />);
	}
	if ( $num_changes > 10 ) {
		$title .= q(more ...);
	}
	my $data       = qq(<a title="$title" class="update_tooltip">$num_changes update$plural</a>);
	my $set_id     = $self->get_set_id;
	my $set_clause = $set_id ? qq(&amp;set_id=$set_id) : q();
	$data .=
	    qq( <a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=tableQuery&amp;table=history&amp;s1=isolate_id&amp;t1=$isolate_id$set_clause&amp;)
	  . qq(order=timestamp&amp;direction=descending">show details</a>\n);
	return { title => 'update history', data => $data };
}

sub _get_composite_field_rows {
	my ( $self, $isolate_id, $data, $field_to_position_after, $composite_display_pos ) = @_;
	my $list = [];
	foreach ( keys %$composite_display_pos ) {
		next if $composite_display_pos->{$_} ne $field_to_position_after;
		my $displayfield = $_;
		$displayfield =~ tr/_/ /;
		my $value = $self->{'datastore'}->get_composite_value( $isolate_id, $_, $data );
		push @$list, { title => $displayfield, data => $value };
	}
	return $list;
}

sub _get_tree {
	my ( $self, $isolate_id ) = @_;
	my $buffer =
	  qq(<div class="scrollable"><div id="tree" class="scheme_tree" style="float:left;max-height:initial">\n);
	$buffer .=
	  qq(<noscript><p class="highlight">Enable Javascript to enhance your viewing experience.</p></noscript>\n);
	$buffer .= $self->get_tree( $isolate_id, { isolate_display => $self->{'curate'} ? 0 : 1 } );
	$buffer .= qq(</div>\n);
	$buffer .=
	    q(<div id="scheme_table" style="overflow:hidden; min-width:60%">)
	  . q(Navigate and select schemes within tree to display allele )
	  . qq(designations</div><div style="clear:both"></div></div>\n)
	  if $buffer !~ /No loci available/;
	return $buffer;
}

sub _get_loci_not_in_schemes {
	my ( $self, $isolate_id ) = @_;
	my $set_id = $self->get_set_id;
	my $loci;
	my $loci_in_no_scheme = $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
	my $loci_with_designations =
	  $self->{'datastore'}->run_query( 'SELECT locus FROM allele_designations WHERE isolate_id=?',
		$isolate_id, { fetch => 'col_arrayref' } );
	my %designations = map { $_ => 1 } @$loci_with_designations;
	my $loci_with_tags = $self->{'datastore'}
	  ->run_query( 'SELECT locus FROM allele_sequences WHERE isolate_id=?', $isolate_id, { fetch => 'col_arrayref' } );
	my %tags = map { $_ => 1 } @$loci_with_tags;

	foreach my $locus (@$loci_in_no_scheme) {
		next if !$designations{$locus} && !$tags{$locus};
		push @$loci, $locus;
	}
	return $loci // [];
}

sub _should_display_scheme {
	my ( $self, $isolate_id, $scheme_id, $summary_view ) = @_;
	my $set_id = $self->get_set_id;
	if ($set_id) {
		return if !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id );
	}
	my $designations_exist = $self->{'datastore'}->run_query(
		q[SELECT EXISTS(SELECT isolate_id FROM allele_designations LEFT JOIN scheme_members ON ]
		  . q[scheme_members.locus=allele_designations.locus WHERE (isolate_id,scheme_id)=(?,?) ]
		  . q[AND allele_id != '0')],
		[ $isolate_id, $scheme_id ],
		{ cache => 'IsolateInfoPage::should_display_scheme::designations' }
	);
	return 1 if $designations_exist;
	my $sequences_exist = $self->{'datastore'}->run_query(
		'SELECT EXISTS(SELECT isolate_id FROM allele_sequences LEFT JOIN scheme_members ON '
		  . 'allele_sequences.locus=scheme_members.locus WHERE (isolate_id,scheme_id)=(?,?))',
		[ $isolate_id, $scheme_id ],
		{ cache => 'IsolateInfoPage::should_display_scheme::sequences' }
	);
	return 1 if $sequences_exist;
	return;
}

sub _get_scheme_field_values {
	my ( $self, $scheme_id, $designations ) = @_;
	my %values;
	my $scheme_field_values =
	  $self->{'datastore'}->get_scheme_field_values_by_designations( $scheme_id, $designations );
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	if ( keys %$scheme_field_values ) {
		foreach my $field (@$scheme_fields) {
			no warnings 'numeric';    #might complain about numeric comparison with non-numeric data
			my @field_values =
			  sort {
				     $scheme_field_values->{ lc($field) }->{$a} cmp $scheme_field_values->{ lc($field) }->{$b}
				  || $a <=> $b
				  || $a cmp $b
			  }
			  keys %{ $scheme_field_values->{ lc($field) } };
			my $att = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
			foreach my $value (@field_values) {
				$value = defined $value ? $value : q();
				next if $value eq q();
				my $formatted_value;
				my $provisional = ( $scheme_field_values->{ lc($field) }->{$value} // '' ) eq 'provisional' ? 1 : 0;
				$formatted_value .= q(<span class="provisional">) if $provisional;
				if ( $att->{'url'} && $value ne q() ) {
					my $url = $att->{'url'};
					$url =~ s/\[\?\]/$value/gx;
					$url =~ s/\&/\&amp;/gx;
					$formatted_value .= qq(<a href="$url">$value</a>);
				} else {
					$formatted_value .= $value;
				}
				$formatted_value .= q(</span>) if $provisional;
				push @{ $values{$field} }, $formatted_value;
			}
			$values{$field} = ['Not defined'] if ref $values{$field} ne 'ARRAY';
		}
	} else {
		$values{$_} = ['Not defined'] foreach @$scheme_fields;
	}
	return \%values;
}

sub _get_scheme {
	my ( $self, $scheme_id, $isolate_id, $summary_view, $options ) = @_;
	my $q = $self->{'cgi'};
	my ( $locus_display_count, $scheme_fields_count ) = ( 0, 0 );
	my ( $loci, $scheme_fields, $scheme_info );
	my $set_id = $self->get_set_id;
	my $buffer = '';
	if ($scheme_id) {
		my $should_display = $self->_should_display_scheme( $isolate_id, $scheme_id, $summary_view );
		return '' if !$should_display;
		$scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		$loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
		foreach (@$loci) {
			$locus_display_count++ if $self->{'prefs'}->{'isolate_display_loci'}->{$_} ne 'hide';
		}
		$scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
		foreach (@$scheme_fields) {
			$scheme_fields_count++ if $self->{'prefs'}->{'isolate_display_scheme_fields'}->{$scheme_id}->{$_};
		}
	} else {
		$scheme_fields = [];
		$loci          = $self->_get_loci_not_in_schemes($isolate_id);
		if (@$loci) {
			foreach (@$loci) {
				$locus_display_count++ if $self->{'prefs'}->{'isolate_display_loci'}->{$_} ne 'hide';
			}
			$scheme_info->{'name'} = 'Loci not in schemes';
		}
	}
	return q() if !( $locus_display_count + $scheme_fields_count );
	my $style = $options->{'no_render'} ? q() : q(  style="float:left;padding-right:0.5em");
	$buffer .= qq(<div$style>\n);
	my $class = $options->{'no_render'} ? q() : q( class="scheme");
	$buffer .= qq(<h3$class><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=schemeInfo&amp;scheme_id=$scheme_id">$scheme_info->{'name'}</a></h3>\n);
	my $args = {
		loci                => $loci,
		summary_view        => $summary_view,
		scheme_id           => $scheme_id,
		scheme_fields_count => $scheme_fields_count,
		isolate_id          => $isolate_id,
		no_render           => $options->{'no_render'} ? 1 : 0,
		show_aliases        => $options->{'show_aliases'}
	};
	$buffer .= $self->get_scheme_flags( $scheme_id, { link => 1 } );
	$buffer .= $self->_get_scheme_values($args);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_scheme_values {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $loci, $scheme_id, $scheme_fields_count, $summary_view ) =
	  @{$args}{qw ( isolate_id loci scheme_id scheme_fields_count summary_view )};
	my $set_id = $self->get_set_id;
	my $allele_designations =
	  $self->{'datastore'}->get_scheme_allele_designations( $isolate_id, $scheme_id,
		{ set_id => $set_id, show_ignored => $self->{'curate'} } );
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	local $| = 1;
	my $buffer;
	$buffer .= q(<dl class="data">) if $args->{'no_render'};

	foreach my $locus (@$loci) {
		my $designations = $allele_designations->{$locus};
		next if $self->{'prefs'}->{'isolate_display_loci'}->{$locus} eq 'hide';
		$buffer .= $self->_get_locus_value(
			{
				isolate_id   => $isolate_id,
				locus        => $locus,
				designations => $designations,
				summary_view => $summary_view,
				no_render    => $args->{'no_render'} ? 1 : 0,
				show_aliases => $args->{'show_aliases'}
			}
		);
	}
	my $field_values =
	  $scheme_fields_count ? $self->_get_scheme_field_values( $scheme_id, $allele_designations ) : undef;
	foreach my $field (@$scheme_fields) {
		next if !$self->{'prefs'}->{'isolate_display_scheme_fields'}->{$scheme_id}->{$field};
		( my $cleaned = $field ) =~ tr/_/ /;
		my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		if ( $scheme_field_info->{'description'} ) {
			$cleaned .=
			  $self->get_tooltip( qq($field - $scheme_field_info->{'description'}), { style => 'color:white' } );
		}
		local $" = ', ';
		my $values = qq(@{$field_values->{$field}}) // q(-);
		if ( $args->{'no_render'} ) {
			$buffer .= qq(<dt>$cleaned</dt><dd>$values</dd>);
		} else {
			$buffer .= qq(<dl class="profile"><dt>$cleaned</dt><dd>$values</dd></dl>);
		}
	}
	$buffer .= q(</dl>) if $args->{'no_render'};
	return $buffer;
}

sub _get_locus_value {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $locus, $designations, $summary_view, $no_render, $show_aliases ) =
	  @{$args}{qw(isolate_id locus designations summary_view no_render show_aliases)};
	my $cleaned    = $self->clean_locus($locus);
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( $locus_info->{'description_url'} ) {
		$locus_info->{'description_url'} =~ s/\&/\&amp;/gx;
		$cleaned = qq(<a href="$locus_info->{'description_url'}">$cleaned</a>);
	}
	my $locus_aliases = $self->{'datastore'}->get_locus_aliases($locus);
	local $" = ';&nbsp;';
	my $alias_display = $show_aliases // $self->{'prefs'}->{'locus_alias'} ? 'inline' : 'none';
	my $display_title = $cleaned;
	$display_title .= qq(&nbsp;<span class="aliases" style="display:$alias_display">(@$locus_aliases)</span>)
	  if @$locus_aliases;
	my $display_value = q();
	my $first         = 1;

	foreach my $designation (@$designations) {
		$display_value .= q(, ) if !$first;
		my $status;
		if ( $designation->{'status'} eq 'provisional' ) {
			$status = 'provisional';
		} elsif ( $designation->{'status'} eq 'ignore' ) {
			$status = 'ignore';
		}
		$display_value .= qq(<span class="$status">) if $status;
		my $url = '';
		my @anchor_att;
		my $update_tooltip = '';
		if ( $self->{'prefs'}->{'update_details'} && $designation->{'allele_id'} ) {
			$update_tooltip = $self->get_update_details_tooltip( $cleaned, $designation );
			push @anchor_att, qq(title="$update_tooltip");
		}
		if ( $locus_info->{'url'} && $designation->{'allele_id'} ne 'deleted' && ( $status // '' ) ne 'ignore' ) {
			$url = $locus_info->{'url'};
			$url =~ s/\[\?\]/$designation->{'allele_id'}/gx;
			$url =~ s/\&/\&amp;/gx;
			push @anchor_att, qq(href="$url");
		}
		if (@anchor_att) {
			local $" = q( );
			$display_value .= qq(<a @anchor_att>$designation->{'allele_id'}</a>);
		} else {
			$display_value .= $designation->{'allele_id'};
		}
		$display_value .= q(</span>) if $status;
		$first = 0;
	}
	$display_value .=
	  $self->get_seq_detail_tooltips( $isolate_id, $locus,
		{ get_all => 1, allele_flags => $self->{'prefs'}->{'allele_flags'} } )
	  if $self->{'prefs'}->{'sequence_details'};
	my $action = @$designations ? EDIT : ADD;
	$display_value .=
	    qq( <a href="$self->{'system'}->{'script_name'}?page=alleleUpdate&amp;db=$self->{'instance'}&amp;)
	  . qq(isolate_id=$isolate_id&amp;locus=$locus" class="action">$action</a>)
	  if $self->{'curate'};
	$display_value .= q(&nbsp;) if !@$designations;

	#Display sequence if locus option set and we're not in a summary view
	if ( $self->{'prefs'}->{'isolate_display_loci'}->{$locus} eq 'sequence' && @$designations && !$summary_view ) {
		foreach my $designation (@$designations) {
			my $seq_name = '';
			if ( @$designations > 1 ) {
				$seq_name = "$locus\_$designation->{'allele_id'}: ";
				my $target_length = int( ( length $seq_name ) / 10 ) + 11;    #line label up with sequence blocks
				$seq_name = BIGSdb::Utils::pad_length( $seq_name, $target_length );
				$seq_name =~ s/ /&nbsp;/g;
			}
			my $sequence;
			try {
				my $sequence_ref =
				  $self->{'datastore'}->get_locus($locus)->get_allele_sequence( $designation->{'allele_id'} );
				$sequence = BIGSdb::Utils::split_line($$sequence_ref);
			}
			catch {
				if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
					$sequence = 'Cannot connect to database';
				}
				if ( $_->isa('BIGSdb::Exception::Database::Configuration') ) {
					$sequence = $_;
				}
			};
			$display_value .= qq(<br />\n$seq_name$sequence\n) if defined $sequence;
		}
	}
	my $buffer =
	  $no_render
	  ? qq(<dt>$display_title</dt><dd>$display_value</dd>)
	  : qq(<dl class="profile"><dt>$display_title</dt><dd>$display_value</dd></dl>);
	return $buffer;
}

sub get_title {
	my ( $self, $options ) = @_;
	return 'Isolate information' if $options->{'breadcrumb'};
	my $q          = $self->{'cgi'};
	my $isolate_id = $q->param('id');
	return q() if $q->param('no_header');
	return q(Invalid isolate id) if !BIGSdb::Utils::is_int($isolate_id);
	my $name  = $self->get_name($isolate_id);
	my $title = qq(Isolate information: id-$isolate_id);
	local $" = q( );
	$title .= qq( ($name)) if $name;
	$title .= qq( - $self->{'system'}->{'description'});
	return $title;
}

sub _get_history {
	my ( $self, $isolate_id, $limit ) = @_;
	my $limit_clause = $limit ? " LIMIT $limit" : '';
	my $count;
	my $history =
	  $self->{'datastore'}->run_query(
		"SELECT timestamp,action,curator FROM history where isolate_id=? ORDER BY timestamp desc$limit_clause",
		$isolate_id, { fetch => 'all_arrayref', slice => {} } );
	if ($limit) {    #need to count total
		$count = $self->{'datastore'}->run_query( 'SELECT COUNT(*) FROM history WHERE isolate_id=?', $isolate_id );
	} else {
		$count = @$history;
	}
	return $history, $count;
}

sub get_name {
	my ( $self, $isolate_id ) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'isolates';
	return $self->{'datastore'}
	  ->run_query( "SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?",
		$isolate_id );
}

sub _get_version_links {
	my ( $self, $isolate_id ) = @_;
	my $buffer       = '';
	my $old_versions = $self->_get_old_versions($isolate_id);
	my $new_versions = $self->_get_new_versions($isolate_id);
	my $list         = [];
	if (@$old_versions) {
		my @version_links;
		foreach my $version ( reverse @$old_versions ) {
			push @version_links, qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=info&amp;id=$version">$version</a>);
		}
		local $" = q(, );
		push @$list, { title => 'Older versions', data => qq(@version_links) };
	}
	if (@$new_versions) {
		my @version_links;
		foreach my $version (@$new_versions) {
			push @version_links, qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=info&amp;id=$version">$version</a>);
		}
		local $" = q(, );
		push @$list, { title => 'Newer versions', data => qq(@version_links) };
	}
	if (@$list) {
		$buffer .= q(<div><span class="info_icon fas fa-2x fa-fw fa-code-branch fa-pull-left" )
		  . q(style="margin-top:-0.2em"></span>);
		$buffer .= qq(<h2>Versions</h2>\n);
		$buffer .= qq(<p>More than one version of this isolate record exist.</p>\n);
		$buffer .= $self->get_list_block($list);
	}
	return $buffer;
}

sub _get_old_versions {
	my ( $self, $isolate_id ) = @_;
	my $next_id = $isolate_id;
	my @old_version;
	my %used;
	while (
		my $old_version = $self->{'datastore'}->run_query(
			"SELECT id FROM $self->{'system'}->{'view'} WHERE new_version=?",
			$next_id,
			{ cache => 'IsolateInfoPage::get_old_versions' }
		)
	  )
	{
		last if $used{$old_version};    #Prevent circular references locking up server.
		push @old_version, $old_version;
		$next_id = $old_version;
		$used{$old_version} = 1;
	}
	return \@old_version;
}

sub _get_new_versions {
	my ( $self, $isolate_id ) = @_;
	my $next_id = $isolate_id;
	my @new_version;
	my %used;
	while (
		my $new_version = $self->{'datastore'}->run_query(
			"SELECT new_version FROM $self->{'system'}->{'view'} WHERE id=?",
			$next_id,
			{ cache => 'IsolateInfoPage::get_new_versions' }
		)
	  )
	{
		last if $used{$new_version};    #Prevent circular references locking up server.
		push @new_version, $new_version;
		$next_id = $new_version;
		$used{$new_version} = 1;
	}
	return \@new_version;
}

sub _get_ref_links {
	my ( $self, $isolate_id ) = @_;
	my $pmids = $self->{'datastore'}->get_isolate_refs($isolate_id);
	return $self->get_refs($pmids);
}

sub get_refs {
	my ( $self, $pmids ) = @_;
	my $buffer = q();
	if (@$pmids) {
		$buffer .=
		  q(<div><span class="info_icon far fa-2x fa-fw fa-newspaper fa-pull-left" style="margin-top:-0.2em"></span>);
		my $count = @$pmids;
		my $plural = $count > 1 ? 's' : '';
		$buffer .= qq(<h2 style="display:inline">Publication$plural ($count)</h2>);
		my $hide = @$pmids > HIDE_PMIDS;
		my $class = $hide ? q(expandable_retracted) : q();
		$buffer .= qq(<div id="references" style="overflow:hidden" class="$class"><ul>);
		my $citations = $self->{'datastore'}->get_citation_hash(
			$pmids,
			{
				formatted            => 1,
				all_authors          => 1,
				state_if_unavailable => 1,
				link_pubmed          => 1
			}
		);

		foreach my $pmid ( sort { $citations->{$a} cmp $citations->{$b} } @$pmids ) {
			$buffer .= qq(<li style="padding-bottom:1em">$citations->{$pmid});
			$buffer .= $self->get_link_button_to_ref($pmid);
			$buffer .= qq(</li>\n);
		}
		$buffer .= qq(</ul></div>\n);
		if ($hide) {
			$buffer .=
			  q(<div class="expand_link" id="expand_references"><span class="fas fa-chevron-down"></span></div>);
		}
		$buffer .= q(</div>);
	}
	return $buffer;
}

sub _get_seqbin_link {
	my ( $self, $isolate_id ) = @_;
	$self->{'contigManager'}->update_isolate_remote_contig_lengths($isolate_id);
	my $seqbin_stats = $self->{'datastore'}->get_seqbin_stats( $isolate_id, { general => 1, lengths => 1 } );
	my $buffer       = q();
	my $q            = $self->{'cgi'};
	if ( $seqbin_stats->{'contigs'} ) {
		my $list = [];
		my $div_id = $seqbin_stats->{'contigs'} > 1 ? 'seqbin' : 'seqbin_no_columnize';
		my %commify =
		  map { $_ => BIGSdb::Utils::commify( $seqbin_stats->{$_} ) } qw(contigs total_length max_length mean_length);
		my $plural = $seqbin_stats->{'contigs'} == 1 ? '' : 's';
		$buffer .= q(<div>);
		$buffer .= q(<span class="info_icon fas fa-2x fa-fw fa-dna fa-pull-left" style="margin-top:-0.1em"></span>);
		$buffer .= qq(<h2>Sequence bin</h2>\n);
		$buffer .= qq(<div id="$div_id">);
		push @$list, { title => 'contigs', data => $commify{'contigs'} };

		if ( $seqbin_stats->{'contigs'} > 1 ) {
			my $lengths =
			  $self->{'datastore'}->run_query(
				'SELECT length(sequence) FROM sequence_bin WHERE isolate_id=? ORDER BY length(sequence) DESC',
				$isolate_id, { fetch => 'col_arrayref' } );
			my $n_stats = BIGSdb::Utils::get_N_stats( $seqbin_stats->{'total_length'}, $seqbin_stats->{'lengths'} );
			push @$list, { title => 'total length', data => "$commify{'total_length'} bp" };
			push @$list, { title => 'max length',   data => "$commify{'max_length'} bp" };
			push @$list, { title => 'mean length',  data => "$commify{'mean_length'} bp" };
			my %stats_labels = (
				N50 => 'N50 contig number',
				L50 => 'N50 length (L50)',
				N90 => 'N90 contig number',
				L90 => 'N90 length (L90)',
				N95 => 'N95 contig number',
				L95 => 'N95 length (L95)',
			);
			foreach my $stat (qw(N50 L50 N90 L90 N95 L95)) {
				my $value = BIGSdb::Utils::commify( $n_stats->{$stat} );
				push @$list,
				  {
					title => $stats_labels{$stat},
					data  => BIGSdb::Utils::commify( $n_stats->{$stat} )
				  };
			}
		} else {
			push @$list,
			  {
				title => 'length',
				data  => BIGSdb::Utils::commify( $seqbin_stats->{'total_length'} ) . ' bp'
			  };
		}
		my $set_id = $self->get_set_id;
		my $set_clause =
		  $set_id
		  ? 'AND (locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes '
		  . "WHERE set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
		  : '';
		my $tagged =
		  $self->{'datastore'}
		  ->run_query( "SELECT COUNT(DISTINCT locus) FROM allele_sequences WHERE isolate_id=? $set_clause",
			$isolate_id );
		$plural = $tagged == 1 ? 'us' : 'i';
		push @$list, { title => 'loci tagged', data => BIGSdb::Utils::commify($tagged) };
		my $columnize = $seqbin_stats->{'contigs'} > 1 ? 1 : 0;
		$buffer .= $self->get_list_block( $list, { columnize => $columnize, nowrap => 1 } );
		$buffer .= q(</div>);
		$buffer .=
		    q(<p style="margin-left:3em"><a class="small_submit" )
		  . qq(href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=seqbin&amp;isolate_id=$isolate_id">Show sequence bin</a></p>);
		$buffer .= q(</div>);
	}
	return $buffer;
}

sub _get_annotation_metrics {
	my ( $self, $isolate_id ) = @_;
	my $schemes = $self->{'datastore'}->run_query(
		'SELECT id,COUNT(*) AS loci FROM schemes s JOIN scheme_members m ON s.id=m.scheme_id '
		  . 'WHERE quality_metric GROUP BY id ORDER BY loci ASC',
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $min_genome_size =
	  $self->{'system'}->{'min_genome_size'} // $self->{'config'}->{'min_genome_size'} // MIN_GENOME_SIZE;
	my $has_genome =
	  $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM seqbin_stats WHERE isolate_id=? AND total_length>=?)',
		[ $isolate_id, $min_genome_size ] );
	my $set_id = $self->get_set_id;
	my $values = [];
	foreach my $scheme (@$schemes) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme->{'id'}, { set_id => $set_id } );
		if ( $scheme_info->{'view'} ) {
			next if !$self->{'datastore'}->is_isolate_in_view( $scheme_info->{'view'}, $isolate_id );
		}
		my $loci_designated = $self->{'datastore'}->run_query(
			'SELECT COUNT(DISTINCT(d.locus)) FROM allele_designations d JOIN scheme_members m ON '
			  . 'd.locus=m.locus WHERE (d.isolate_id,m.scheme_id)=(?,?)',
			[ $isolate_id, $scheme->{'id'} ],
			{ cache => 'IsolateInfo::annotation:metrics' }
		);
		my $data = {
			id            => $scheme_info->{'id'},
			name          => $scheme_info->{'name'},
			loci          => $scheme->{'loci'},
			designated    => $loci_designated,
			min_threshold => $scheme_info->{'quality_metric_bad_threshold'},
			max_threshold => $scheme_info->{'quality_metric_good_threshold'}
		};
		push @$values, $data;
	}
	return q() if !@$values;
	my $buffer = qq(<div id="annotation_metrics">\n);
	$buffer .= qq(<span class="info_icon fas fa-2x fa-fw fa-award fa-pull-left" style="margin-top:-0.2em"></span>\n);
	$buffer .= qq(<h2>Annotation quality metrics</h2>\n);
	$buffer .= qq(<div class="scrollable"><table class="resultstable">\n);
	$buffer .= q(<tr><th rowspan="2">Scheme</th><th rowspan="2">Scheme loci</th><th rowspan="2">Designated loci</th>)
	  . q(<th colspan="2">Annotation</th></tr>);
	$buffer .= qq(<tr><th style="min-width:5em">Score</th><th>Status</th></tr>\n);
	my $td = 1;
	my $scheme_count;

	foreach my $scheme (@$values) {
		next if !$scheme->{'loci'};
		next if !$scheme->{'designated'} && $scheme->{'loci'} > 1;
		next if !$scheme->{'designated'} && !$has_genome;
		my $percent = int( 100 * $scheme->{'designated'} / $scheme->{'loci'} );
		my $max_threshold = $scheme->{'max_threshold'} // $scheme->{'loci'};
		$max_threshold = $scheme->{'loci'} if $max_threshold > $scheme->{'loci'};
		my $min_threshold = $scheme->{'min_threshold'} // 0;
		$min_threshold = 0 if $min_threshold < 0;
		if ( $max_threshold < $min_threshold ) {
			$logger->error("Scheme $scheme->{'id'} ($scheme->{'name'}) has max_threshold < min_threshold");
			$min_threshold = 0;
			$max_threshold = $scheme->{'loci'};
		}
		$buffer .= qq(<tr class="td$td"><td>$scheme->{'name'}</td><td>$scheme->{'loci'}</td>)
		  . qq(<td>$scheme->{'designated'}</td>);
		my $min    = 100 * $min_threshold / $scheme->{'loci'};
		my $max    = 100 * $max_threshold / $scheme->{'loci'};
		my $middle = ( $min + $max ) / 2;
		my $colour = $self->_get_colour( $percent, { min => $min, max => $max, middle => $middle } );
		$buffer .=
		    q(<td><span style="position:absolute;font-size:0.8em;margin-left:-0.5em">)
		  . qq($percent</span>)
		  . qq(<div style="display:block-inline;margin-top:0.2em;background-color:\#$colour;)
		  . qq(border:1px solid #ccc;height:0.8em;width:$percent%"></div></td>);
		my $quality;
		$min_threshold = $scheme->{'min_threshold'} // $max_threshold;

		if ( $scheme->{'designated'} >= $max_threshold ) {
			$quality = GOOD;
		} elsif ( $scheme->{'designated'} < $min_threshold ) {
			$quality = BAD;
		} else {
			$quality = MEH;
		}
		$buffer .= qq(<td>$quality</td>);
		$buffer .= qq(</tr>\n);
		$td = $td == 1 ? 2 : 1;
		$scheme_count++;
	}
	return q() if !$scheme_count;
	$buffer .= qq(</table></div>\n);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_colour {
	my ( $self, $num, $options ) = @_;
	my $min    = $options->{'min'}    // 0;
	my $max    = $options->{'max'}    // 100;
	my $middle = $options->{'middle'} // 50;
	if ( $min > $max ) {
		$logger->error('Error in params - requirement is min < middle < max');
		$logger->error("Min: $min; Middle: $middle; Max: $max");
		return q(000000);
	}
	if ( $min == $middle ) {
		return $min == 0 ? q(FF0000) : q(00FF00);
	}
	my $scale = 255 / ( $middle - $min );
	return q(FF0000) if $num <= $min;    # lower boundry
	return q(00FF00) if $num >= $max;    # upper boundary
	if ( $num < $middle ) {
		return sprintf q(FF%02X00) => int( ( $num - $min ) * $scale );
	} else {
		return sprintf q(%02XFF00) => 255 - int( ( $num - $middle ) * $scale );
	}
}

sub _print_projects {
	my ( $self, $isolate_id ) = @_;
	my $projects = $self->{'datastore'}->run_query(
		q[SELECT short_description,full_description FROM projects WHERE full_description IS NOT NULL AND ]
		  . q[isolate_display AND NOT private AND id IN (SELECT project_id FROM project_members WHERE isolate_id=?) ]
		  . q[ORDER BY id],
		$isolate_id,
		{ fetch => 'all_arrayref', slice => {} }
	);
	if ( $self->{'username'} ) {
		my $user_info        = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		my $private_projects = $self->{'datastore'}->run_query(
			q[SELECT short_description||' (private)' AS short_description,full_description FROM projects WHERE ]
			  . q[length(full_description)>0 AND private AND id IN (SELECT project_id FROM project_members WHERE ]
			  . q[isolate_id=?) AND id IN (SELECT project_id FROM merged_project_users WHERE user_id=?) ORDER BY id],
			[ $isolate_id, $user_info->{'id'} ],
			{ fetch => 'all_arrayref', slice => {} }
		);
		push @$projects, @$private_projects;
	}
	if (@$projects) {
		say q(<div class="box" id="projects">);
		say q(<span class="info_icon fas fa-2x fa-fw fa-list-alt fa-pull-left" style="margin-top:0.3em"></span>);
		say q(<h2>Projects</h2>);
		my $hide = @$projects > 1;
		my $class = $hide ? q(expandable_retracted) : q();
		say qq(<div id="project_list" style="overflow:hidden" class="$class">);
		my $plural = @$projects == 1 ? '' : 's';
		say qq(<p>This isolate is a member of the following project$plural:</p>);
		say q(<dl class="projects">);

		foreach my $project (@$projects) {
			say qq(<dt>$project->{'short_description'}</dt>);
			say qq(<dd>$project->{'full_description'}</dd>);
		}
		say q(</dl>);
		say q(</div>);
		if ($hide) {
			say q(<div class="expand_link" id="expand_project_list"><span class="fas fa-chevron-down"></span></div>);
		}
		say q(</div>);
	}
	return;
}
1;
