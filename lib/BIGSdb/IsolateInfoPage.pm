#Written by Keith Jolley
#Copyright (c) 2010-2024, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
use BIGSdb::Constants qw(:interface :limits COUNTRIES DEFAULT_CODON_TABLE NULL_TERMS);
use BIGSdb::JSContent;
use Log::Log4perl qw(get_logger);
use Try::Tiny;
use List::MoreUtils qw(none uniq);
use JSON;
use Template;
use Bio::Tools::CodonTable;
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
	my $field_attributes = $self->{'xmlHandler'}->get_all_field_attributes;
	foreach my $field ( keys %$field_attributes ) {
		if ( $field_attributes->{$field}->{'type'} eq 'geography_point'
			|| ( $field_attributes->{$field}->{'geography_point_lookup'} // q() ) eq 'yes' )
		{
			$self->{'ol'} = 1;
			last;
		}
	}
	$self->set_level1_breadcrumbs;
	return;
}

sub get_javascript {
	my ($self)       = @_;
	my $show_aliases = $self->{'prefs'}->{'locus_alias'} ? 'none'   : 'inline';
	my $hide_aliases = $self->{'prefs'}->{'locus_alias'} ? 'inline' : 'none';
	my $buffer       = << "END";
\$(function () {
	\$(document).ajaxComplete(function() {
		reloadTooltips();
		\$("span#show_aliases_text").css('display', '$show_aliases');
		\$("span#hide_aliases_text").css('display', '$hide_aliases');
		\$("span#show_common_names_text").css('display', 'inline');
		\$("span#hide_common_names_text").css('display', 'none');
		\$("span#tree_button").css('display', 'inline');
		if (\$("span").hasClass('aliases')){
			\$("span#aliases_button").css('display', 'inline');
		} else {
			\$("span#aliases_button").css('display', 'none');
		}
		if (\$("span").hasClass('locus_common_name')){
			\$("span#common_names_button").css('display', 'inline');
		} else {
			\$("span#common_names_button").css('display', 'none');
		}
		set_profile_widths();
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
	\$( "#show_common_names" ).click(function() {
		if (\$("span#show_common_names_text").css('display') == 'none'){
			\$("span#show_common_names_text").css('display', 'inline');
			\$("span#hide_common_names_text").css('display', 'none');
		} else {
			\$("span#show_common_names_text").css('display', 'none');
			\$("span#hide_common_names_text").css('display', 'inline');
		}
		\$("span.locus_common_name").toggle();
		set_profile_widths();
	});
	\$( "#show_aliases" ).click(function() {
		if (\$("span#show_aliases_text").css('display') == 'none'){
			\$("span#show_aliases_text").css('display', 'inline');
			\$("span#hide_aliases_text").css('display', 'none');
		} else {
			\$("span#show_aliases_text").css('display', 'none');
			\$("span#hide_aliases_text").css('display', 'inline');		
		}
		\$( "span.aliases" ).toggle();
		set_profile_widths();
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
	\$( ".show_lincode" ).click(function() {
		let scheme_id = this.id.replace('show_lcgroups_','');
		\$("#show_lcgroups_" + scheme_id).css('display','none');
		\$("#hide_lcgroups_" + scheme_id).css('display','inline');
		\$("#lc_table_" + scheme_id).css('display','block');
		\$(".lc_filtered_" + scheme_id).css('visibility','collapse');
		\$(".lc_unfiltered_" + scheme_id).css('visibility','visible');
	});	
	\$( ".hide_lincode" ).click(function() {
		let scheme_id = this.id.replace('hide_lcgroups_','');
		\$("#show_lcgroups_" + scheme_id).css('display','inline');
		\$("#hide_lcgroups_" + scheme_id).css('display','none');
		\$("#lc_table_" + scheme_id).css('display','none');
		\$(".lc_filtered_" + scheme_id).css('visibility','visible');
		\$(".lc_unfiltered_" + scheme_id).css('visibility','collapse');
	});	
	\$(".field_group").columnize({width:450});
	\$(".sparse").columnize({width:450,lastNeverTallest: true,doneFunc:function(){enable_slide_triggers();}});
	\$("#seqbin").columnize({width:300,lastNeverTallest: true});  
	if (!(\$("span").hasClass('aliases'))){
		\$("span#aliases_button").css('display', 'none');
	}
	\$(".slide_panel").click(function() {		
		\$(this).toggle("slide",{direction:"right"},"fast");
	});	
	\$("#show_csgroups").click(function() {		
		\$("#show_csgroups").css('display','none');
		\$("#hide_csgroups").css('display','inline');
		\$(".cs_table").css('display','block');
		\$(".cs_filtered").css('visibility','collapse');
		\$(".cs_unfiltered").css('visibility','visible');
	});
	\$("#hide_csgroups").click(function() {	
		\$("#show_csgroups").css('display','inline');
		\$("#hide_csgroups").css('display','none');
		\$(".cs_table").css('display','none');
		\$(".cs_filtered").css('visibility','visible');
		\$(".cs_unfiltered").css('visibility','collapse');
	});
	\$("#show_metric_fields").click(function() {
		\$("#hide_metric_fields").show();
		\$("#show_metric_fields").hide();
		\$("#metric_fields").show();
	})
	\$("#hide_metric_fields").click(function() {
		\$("#show_metric_fields").show();
		\$("#hide_metric_fields").hide();
		\$("#metric_fields").hide();
	})
	set_profile_widths();
});

function enable_slide_triggers(){
	\$(".slide_trigger").off('click').click(function() {
		var id = \$(this).attr('id');
		var panel = id.replace('expand','slide');
		\$(".slide_panel:not(#" + panel +")").hide("slide",{direction:"right"},"fast");
		\$("#" + panel).toggle("slide",{direction:"right"},"fast");
	});
}

function set_profile_widths(){
	\$("dl.profile dt.locus").css("width","auto").css("max-width","none");
	var maxWidth = Math.max.apply( null, \$("dl.profile dt.locus").map( function () {
    	return \$(this).outerWidth(true);
	}).get() );
	\$("dl.profile dt.locus").css("width",'calc(' + maxWidth + 'px - 1em)')
		.css("max-width",'calc(' + maxWidth + 'px - 1em)');	
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
	my $set_id      = $self->get_set_id;
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
			my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
			if ( $scheme_info->{'view'} ) {
				next if !$self->{'datastore'}->is_isolate_in_view( $scheme_info->{'view'}, $isolate_id );
			}
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
				my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
				if ( $scheme_info->{'view'} ) {
					next if !$self->{'datastore'}->is_isolate_in_view( $scheme_info->{'view'}, $isolate_id );
				}
				$items += $self->_get_display_items_in_scheme( $isolate_id, $scheme_id );
				return if $items > MAX_DISPLAY;
			}
		} else {    #Scheme group
			my $schemes = $self->{'datastore'}->get_schemes_in_group($group_id);
			foreach my $scheme_id (@$schemes) {
				my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
				if ( $scheme_info->{'view'} ) {
					next if !$self->{'datastore'}->is_isolate_in_view( $scheme_info->{'view'}, $isolate_id );
				}
				$items += $self->_get_display_items_in_scheme( $isolate_id, $scheme_id );
				return if $items > MAX_DISPLAY;
			}
		}
	} elsif ( BIGSdb::Utils::is_int( scalar $q->param('scheme_id') ) ) {
		my $scheme_id = $q->param('scheme_id');
		if ( $scheme_id == -1 ) {    #All schemes/loci
			my $set_id  = $self->get_set_id;
			my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
			foreach my $scheme (@$schemes) {
				my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme->{'id'} );
				if ( $scheme_info->{'view'} ) {
					next if !$self->{'datastore'}->is_isolate_in_view( $scheme_info->{'view'}, $isolate_id );
				}
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
		my $loci       = $self->{'datastore'}->get_loci_in_no_scheme;
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
		say q(<div class="box resultspanel">);
		say q(<div id="profile" style="overflow:hidden;min-height:30em" class="expandable_retracted">);
		say $self->get_show_aliases_button( 'inline', { show_aliases => 0 } );
		say $self->get_show_common_names_button('inline');
		$self->_print_group_data( $isolate_id, scalar $q->param('group_id'), { show_aliases => 0, no_render => 1 } );
		say q(</div>);
		say q(<div class="expand_link" id="expand_profile"><span class="fas fa-chevron-down"></span></div>);
		say q(</div>);
	} elsif ( BIGSdb::Utils::is_int( scalar $q->param('scheme_id') ) ) {
		say q(<div class="box resultspanel">);
		say q(<div id="profile" style="overflow:hidden;min-height:30em" class="expandable_retracted">);
		say $self->get_show_aliases_button( 'inline', { show_aliases => 0 } );
		say $self->get_show_common_names_button('inline');
		$self->_print_scheme_data( $isolate_id, scalar $q->param('scheme_id'), { show_aliases => 0, no_render => 0 } );
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
	my ($self)      = @_;
	my $q           = $self->{'cgi'};
	my $isolate_id  = $q->param('id');
	my $set_id      = $self->get_set_id;
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
	my $default_codon_table = $self->{'system'}->{'codon_table'} // DEFAULT_CODON_TABLE;
	my $codon_table         = $self->{'datastore'}->get_codon_table($isolate_id);
	if ( $codon_table != $default_codon_table ) {
		my $tables = Bio::Tools::CodonTable->tables;
		say q(<p>This isolate uses a different codon table than normal: )
		  . qq(<span class="highlightvalue">$tables->{$codon_table}</span>.</p>);
	}
	say $self->get_isolate_record($isolate_id);
	my $tree_button =
		q( <span id="tree_button" style="margin-left:1em;display:none">)
	  . q(<a id="show_tree" class="small_submit" style="cursor:pointer">)
	  . q(<span id="show_tree_text" style="display:none"><span class="fa fas fa-eye"></span> Show</span>)
	  . q(<span id="hide_tree_text" style="display:inline">)
	  . q(<span class="fa fas fa-eye-slash"></span> Hide</span> tree</a></span>);
	my $common_names_button = $self->get_show_common_names_button;
	my $aliases_button      = $self->get_show_aliases_button;
	my $loci                = $self->{'datastore'}->get_loci( { set_id => $set_id } );
	if ( @$loci && $self->_should_show_schemes($isolate_id) ) {
		$self->_show_lincode_matches($isolate_id);
		$self->_show_classification_schemes($isolate_id);
		say q(<div><span class="info_icon fas fa-2x fa-fw fa-table fa-pull-left" style="margin-top:0.3em"></span>);
		say q(<h2 style="display:inline-block">Schemes and loci</h2>)
		  . qq($tree_button$common_names_button$aliases_button<div>);
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

sub get_show_aliases_button {
	my ( $self, $display, $options ) = @_;
	$display //= 'none';
	my $show_aliases = $options->{'show_aliases'} // $self->{'prefs'}->{'locus_alias'} ? 'none'   : 'inline';
	my $hide_aliases = $options->{'show_aliases'} // $self->{'prefs'}->{'locus_alias'} ? 'inline' : 'none';
	return
		qq(<span id="aliases_button" style="margin-left:1em;display:$display">)
	  . q(<a id="show_aliases" class="small_submit" style="cursor:pointer">)
	  . qq(<span id="show_aliases_text" style="display:$show_aliases"><span class="fa fas fa-eye"></span> )
	  . qq(Show</span><span id="hide_aliases_text" style="display:$hide_aliases">)
	  . q(<span class="fa fas fa-eye-slash"></span> Hide</span> )
	  . q(aliases</a></span>);
}

sub get_show_common_names_button {
	my ( $self, $display ) = @_;
	$display //= 'none';
	return
		qq(<span id="common_names_button" style="margin-left:1em;display:$display">)
	  . q(<a id="show_common_names" class="small_submit" style="cursor:pointer">)
	  . q(<span id="show_common_names_text" style="display:inline"><span class="fa fas fa-eye"></span> )
	  . q(Show</span><span id="hide_common_names_text" style="display:none">)
	  . q(<span class="fa fas fa-eye-slash"></span> Hide</span> )
	  . q(common names</a></span>);
}

sub _print_plugin_buttons {
	my ( $self, $isolate_id ) = @_;
	my $q                 = $self->{'cgi'};
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
		say q(<div><span class="info_icon fas fa-2x fa-fw fa-chart-column fa-pull-left" style="margin-top:-0.2em">)
		  . q(</span>);
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

sub _show_lincode_matches {
	my ( $self, $isolate_id ) = @_;
	return if ( $self->{'system'}->{'show_lincode_matches'} // 'yes' ) eq 'no';
	my $set_id  = $self->get_set_id;
	my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id, with_pk => 1 } );
	my $buffer;
	foreach my $scheme (@$schemes) {
		next if !$self->{'datastore'}->are_lincodes_defined( $scheme->{'id'} );
		my $scheme_field_table = "temp_isolates_scheme_fields_$scheme->{'id'}";
		my $cache_table_exists =
		  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)',
			$scheme_field_table );
		if ( !$cache_table_exists ) {
			$logger->warn( "$self->{'instance'}: Scheme $scheme->{'id'} is not cached for this database.  "
				  . 'Display of similar isolates is disabled. You need to run the update_scheme_caches.pl script '
				  . 'regularly against this database to create these caches.' );
			next;
		}
		my $lincode_table = $self->{'datastore'}->create_temp_lincodes_table( $scheme->{'id'} );
		my $lincode       = $self->{'datastore'}->get_lincode_value( $isolate_id, $scheme->{'id'} );
		next if !defined $lincode;
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme->{'id'}, { get_pk => 1 } );
		my $pk_info     = $self->{'datastore'}->get_scheme_field_info( $scheme->{'id'}, $scheme_info->{'primary_key'} );
		local $" = q(_);
		$buffer .= $self->get_list_block(
			[
				{
					title => 'Scheme',
					data  => qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'})
					  . qq(&amp;page=schemeInfo&scheme_id=$scheme->{'id'}">$scheme->{'name'}</a>)
				},
				{
					title => 'LIN code',
					data  => qq(@$lincode)
				}
			]
		);
		my $lincode_scheme =
		  $self->{'datastore'}
		  ->run_query( 'SELECT * FROM lincode_schemes WHERE scheme_id=?', $scheme->{'id'}, { fetch => 'row_hashref' } );
		my $lincode_pk = $pk_info->{'type'} eq 'integer' ? 'CAST(l.profile_id AS int)' : 'l.profile_id';
		my @thresholds = split /\s*;\s*/x, $lincode_scheme->{'thresholds'};
		my $i          = 0;
		my $tdf        = 1;
		my $tdu        = 1;
		my $td         = 1;
		my $default_show =
		  BIGSdb::Utils::is_int( $self->{'system'}->{'show_lincode_thresholds'} )
		  ? $self->{'system'}->{'show_lincode_thresholds'}
		  : 5;
		$default_show = @thresholds if $default_show > @thresholds;
		my @filtered;
		my @unfiltered;

		foreach my $threshold (@thresholds) {
			my @prefix = @$lincode[ 0 .. $i ];
			my @lincode_query;
			my $pos = 1;
			foreach my $value (@prefix) {
				push @lincode_query, "lincode[$pos]=$value";
				$pos++;
			}
			local $" = q( AND );
			my $isolates = $self->{'datastore'}->run_query(
					"SELECT COUNT(DISTINCT v.id) FROM $self->{'system'}->{'view'} v JOIN $scheme_field_table sf ON "
				  . "v.id=sf.id JOIN $lincode_table l ON sf.$scheme_info->{'primary_key'}=$lincode_pk WHERE "
				  . "v.new_version IS NULL AND @lincode_query",
			);
			local $" = q(_);
			my $url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;designation_field1="
			  . "lin_$scheme->{'id'}&amp;amp;designation_operator1=starts%20with&amp;designation_value1=@prefix&submit=1";
			if ( @thresholds >= $default_show && $i >= ( @thresholds - $default_show ) ) {
				push @filtered,
					qq(<tr class="td$tdf lc_filtered_$scheme->{'id'}">)
				  . qq(<td style="text-align:left">@prefix</td>)
				  . qq(<td>$threshold</td><td><a href="$url">$isolates</a></td></tr>);
				$tdf = $tdf == 1 ? 2 : 1;
			}
			push @unfiltered,
				qq(<tr class="td$tdu lc_unfiltered_$scheme->{'id'}" style="visibility:collapse">)
			  . qq(<td style="text-align:left">@prefix</td>)
			  . qq(<td>$threshold</td><td><a href="$url">$isolates</a></td></tr>);
			$tdu = $tdu == 1 ? 2 : 1;
			$i++;
		}
		my $filtered_display = @filtered ? 'block' : 'none';
		my $hide_table_class = @filtered ? ''      : "lc_table_$scheme->{'id'}";
		local $" = q( );
		if ( @unfiltered > @filtered ) {
			$buffer .=
				qq(<p><a id="show_lcgroups_$scheme->{'id'}" class="show_lincode small_submit" )
			  . q(style="display:inline"><span class="fa fas fa-eye"></span> Show all thresholds</a>)
			  . qq(<a id="hide_lcgroups_$scheme->{'id'}" class="hide_lincode small_submit" style="display:none">)
			  . q(<span class="fa fas fa-eye-slash"></span> Hide larger thresholds</a></p>);
		}
		$buffer .=
			q(<div class="scrollable">)
		  . q(<table class="resultstable $hide_table_class" style="display:$filtered_display">)
		  . q(<tr><th>Prefix</th><th>Threshold</th>)
		  . qq(<th>Matching isolates</th></tr>@filtered@unfiltered);
		$buffer .= q(</table></div>);
	}
	if ($buffer) {
		say q(<div><span class="info_icon fas fa-2x fa-fw fa-sitemap fa-pull-left" )
		  . q(style="margin-top:-0.2em"></span><h2>Similar isolates (determined by LIN codes)</h2>)
		  . qq($buffer</div>);
	}
	return;
}

sub _show_classification_schemes {
	my ( $self, $isolate_id ) = @_;
	return if ( $self->{'system'}->{'show_classification_schemes'} // 'yes' ) eq 'no';
	my $classification_data = $self->_get_classification_group_data($isolate_id);
	say $self->_format_classification_data($classification_data);
	return;
}

sub _get_classification_group_data {
	my ( $self, $isolate_id ) = @_;
	my $view = $self->{'system'}->{'view'};
	my $classification_schemes =
	  $self->{'datastore'}->run_query( 'SELECT * FROM classification_schemes ORDER BY display_order,name',
		undef, { fetch => 'all_arrayref', slice => {} } );
	my $td   = 1;
	my $data = [];
	foreach my $cscheme (@$classification_schemes) {
		my ( $cg_buffer, $cgf_buffer );
		my $scheme_id = $cscheme->{'scheme_id'};
		next if !$self->{'prefs'}->{'isolate_display_schemes'}->{$scheme_id};
		my $cache_table_exists =
		  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)',
			["temp_isolates_scheme_fields_$scheme_id"] );
		if ( !$cache_table_exists ) {
			$logger->warn( "$self->{'instance'}: Scheme $scheme_id is not cached for this database.  "
				  . 'Display of similar isolates is disabled. You need to run the update_scheme_caches.pl script '
				  . 'regularly against this database to create these caches.' );
			return [];
		}
		my $scheme_info  = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		my $scheme_table = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
		my $pk           = $scheme_info->{'primary_key'};
		my $pk_values =
		  $self->{'datastore'}
		  ->run_query( "SELECT $pk FROM $scheme_table WHERE id=?", $isolate_id, { fetch => 'col_arrayref' } );
		my $max_isolate_count = 0;
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
						"SELECT COUNT(DISTINCT $view.id) FROM $view LEFT JOIN $scheme_table t ON $view.id=t.id "
						  . "LEFT JOIN $cscheme_table cs ON t.$pk=cs.profile_id WHERE group_id=? AND new_version "
						  . 'IS NULL',
						$group_id
					);
					next if !$isolate_count;
					my $cg_fields = $self->get_classification_group_fields( $cscheme->{'id'}, $group_id );
					$cgf_buffer .= qq($cg_fields<br />) if $cg_fields;
					my $url =
						qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;)
					  . qq(designation_field1=cg_$cscheme->{'id'}_group&amp;designation_value1=$group_id&amp;)
					  . q(submit=1);
					my $plural = $isolate_count == 1 ? q() : q(s);
					$cg_buffer .= qq(<a href="$url">$group_id</a> ($isolate_count isolate$plural)<br />\n);
					$max_isolate_count = $isolate_count if $isolate_count > $max_isolate_count;
					$group_displayed{$group_id} = 1;
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
			push @$data,
			  {
				cscheme => qq($cscheme->{'name'}$tooltip),
				scheme  => qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'})
				  . qq(&amp;page=schemeInfo&scheme_id=$scheme_id">$scheme_info->{'name'}</a>),
				method        => 'Single-linkage',
				threshold     => $cscheme->{'inclusion_threshold'},
				status        => $cscheme->{'status'},
				group         => $cg_buffer,
				fields        => $cgf_buffer,
				isolate_count => $max_isolate_count
			  };
		}
	}
	return $data;
}

sub _format_classification_data {
	my ( $self, $data ) = @_;
	my $buffer = q();
	return $buffer if !@$data;
	my $fields_defined;
	foreach my $row (@$data) {
		$fields_defined = 1 if defined $row->{'fields'};
	}
	my @filtered;
	my @unfiltered;
	my $tdf = 1;
	my $tdu = 1;
	foreach my $row (@$data) {
		my @values = @{$row}{qw(cscheme scheme method threshold status group)};
		push @values, $row->{'fields'} // q() if $fields_defined;
		local $" = q(</td><td>);
		push @unfiltered, qq(<tr class="td$tdu cs_unfiltered" style="visibility:collapse"><td>@values</td></tr>);
		$tdu = $tdu == 1 ? 2 : 1;
		if ( $row->{'isolate_count'} > 1 ) {
			push @filtered, qq(<tr class="td$tdf cs_filtered"><td>@values</td></tr>);
			$tdf = $tdf == 1 ? 2 : 1;
		}
	}
	my $filtered_display = @filtered ? 'block' : 'none';
	my $hide_table_class = @filtered ? ''      : 'cs_table';
	$buffer =
		q(<div><span class="info_icon fas fa-2x fa-fw fa-sitemap fa-pull-left" )
	  . q(style="margin-top:-0.2em"></span>)
	  . q(<h2>Similar isolates (determined by classification schemes)</h2>);
	if ( !@filtered ) {
		$buffer .=
			q(<p>No similar isolates at any threshold. )
		  . q(<a id="show_csgroups" class="small_submit" style="display:inline">)
		  . q(<span class="fa fas fa-eye"></span> Show groups</a>)
		  . q(<a id="hide_csgroups" class="small_submit" style="display:none">)
		  . q(<span class="fa fas fa-eye-slash"></span> Hide groups</a></p>);
	} elsif ( @unfiltered > @filtered ) {
		$buffer .=
			q(<p>Some groups only contain this isolate. )
		  . q(<a id="show_csgroups" class="small_submit" style="display:inline">)
		  . q(<span class="fa fas fa-eye"></span> Show single groups</a>)
		  . q(<a id="hide_csgroups" class="small_submit" style="display:none">)
		  . q(<span class="fa fas fa-eye-slash"></span> Hide single groups</a></p>);
	}
	$buffer .=
	  qq(<p class="$hide_table_class" style="display:$filtered_display">Experimental schemes are subject to change and )
	  . q(are not a stable part of the nomenclature.</p>)
	  . q(<div class="scrollable">)
	  . qq(<table class="resultstable $hide_table_class" style="display:$filtered_display"><tr>)
	  . q(<th>Classification scheme</th><th>Underlying scheme</th><th>Clustering method</th>)
	  . q(<th>Mismatch threshold</th><th>Status</th><th>Group</th>);
	$buffer .= q(<th>Fields</th>) if $fields_defined;
	$buffer .= qq(</tr>@filtered@unfiltered</table></div></div>);
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
		if ( $scheme_info->{'view'} ) {
			next if !$self->{'datastore'}->is_isolate_in_view( $scheme_info->{'view'}, $isolate_id );
		}
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
		foreach my $scheme_id (@$schemes) {
			next if !$self->{'prefs'}->{'isolate_display_schemes'}->{$scheme_id};
			my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
			if ( $scheme_info->{'view'} ) {
				next if !$self->{'datastore'}->is_isolate_in_view( $scheme_info->{'view'}, $isolate_id );
			}
			say $self->_get_scheme( $scheme_id, $isolate_id, $self->{'curate'} );
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
			$buffer .= $self->_get_grouped_fields( $id, $data );
			$buffer .= $self->_get_secondary_metadata_fields($id);
			$buffer .= $self->_get_version_links($id);
			$buffer .= $self->_get_ref_links($id);
			$buffer .= $self->_get_seqbin_link($id);
			$buffer .= $self->_get_assembly_checks($id);
			$buffer .= $self->_get_annotation_metrics( $id, $data );
			$buffer .= $self->_get_analysis($id);
		}
	}
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_analysis {
	my ( $self, $isolate_id ) = @_;
	my $analysis =
	  $self->{'datastore'}->run_query( 'SELECT name,results,datestamp FROM analysis_results WHERE isolate_id=?',
		$isolate_id, { fetch => 'all_arrayref', slice => {} } );
	return q() if !@$analysis;
	my $template_file = 'isolate_info_analysis.tt';
	return q()
	  if !-e "$self->{'config_dir'}/dbases/$self->{'instance'}/templates/$template_file"
	  && !-e "$self->{'config_dir'}/templates/$template_file";
	my $buffer =
	  q(<div><span class="info_icon fas fa-2x fa-fw fa-chart-line fa-pull-left" style="margin-top:-0.2em"></span>);
	$buffer .= qq(<h2>Analysis</h2>\n);
	my $data = {};

	foreach my $module (@$analysis) {
		$data->{ $module->{'name'} } = {
			datestamp => $module->{'datestamp'},
			results   => decode_json( $module->{'results'} )
		};
	}
	my $template = Template->new(
		{
			INCLUDE_PATH => "$self->{'config_dir'}/dbases/$self->{'instance'}/templates:$self->{'config_dir'}/templates"
		}
	);
	$data->{'get_colour'} = sub { BIGSdb::Utils::get_percent_colour(@_) };
	$data->{'isolate_id'} = $isolate_id;
	$data->{'instance'}   = $self->{'instance'};
	$data->{'config_dir'} = $self->{'config_dir'};
	my $template_output = q();
	$template->process( $template_file, $data, \$template_output ) || $logger->error( $template->error );
	return q() if ( $template_output // q() ) =~ /^\s*$/x;
	$buffer .= $template_output;
	$buffer .= q(</div>);
	return $buffer;
}

sub _show_private_owner {
	my ( $self, $isolate_id ) = @_;
	my ( $private_owner, $request_publish ) =
	  $self->{'datastore'}
	  ->run_query( 'SELECT user_id,request_publish FROM private_isolates WHERE isolate_id=?', $isolate_id );
	if ( defined $private_owner ) {
		my $user_string    = $self->{'datastore'}->get_user_string($private_owner);
		my $request_string = $request_publish ? q( - publication requested.) : q();
		return
			q(<p style="float:right"><span class="main_icon fas fa-2x fa-user-secret"></span> )
		  . qq(<span class="warning" style="padding: 0.1em 0.5em">Private record owned by $user_string)
		  . qq($request_string</span></p>);
	}
}

sub _get_provenance_fields {
	my ( $self, $isolate_id, $data, $summary_view, $group ) = @_;
	my $buffer;
	my ( $icon, $heading, $div_id );
	if ($group) {
		$icon    = $self->get_field_group_icon($group) // 'fas fa-list';
		$heading = $group;
		$div_id  = $group;
	} else {
		$buffer .= $self->_show_private_owner($isolate_id);
		$icon    = 'fas fa-globe';
		$heading = 'Provenance/primary metadata';
		$div_id  = 'provenance';
	}
	$buffer .= qq(<div><span class="info_icon fa-2x fa-fw $icon fa-pull-left" style="margin-top:-0.2em"></span>);
	$buffer .= qq(<h2>$heading</h2>\n);
	$buffer .= qq(<div id="$div_id" class="field_group">);
	my $list       = [];
	my $q          = $self->{'cgi'};
	my $set_id     = $self->get_set_id;
	my $is_curator = $self->is_curator;
	my $field_list = $self->{'xmlHandler'}->get_field_list( { no_curate_only => !$is_curator } );
	my $maps       = [];
	my ( $composites, $composite_display_pos ) = $self->_get_composites;
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
		next if !$group && $thisfield->{'group'};
		next if $group  && ( $thisfield->{'group'} // q() ) ne $group;
		next if $thisfield->{'prefixes'};
		next if ( $thisfield->{'isolate_display'} // q() ) eq 'no';
		local $" = q(; );

		if ( !defined $data->{ lc($field) } ) {
			if ( $composites->{$field} ) {
				my $composite_fields =
				  $self->_get_composite_field_rows( $isolate_id, $data, $field, $composite_display_pos );
				push @$list, @$composite_fields if @$composite_fields;
			}
			next;    #Do not print row
		}
		my ( $web, $value );
		if ( $thisfield->{'web'} ) {
			$web = $self->_get_web_links( $data, $field );
		} else {
			$value = $self->_get_field_value( $data, $field );
		}
		next if $self->_process_geography_fields(
			{
				data  => $data,
				field => $field,
				maps  => $maps
			}
		);
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
			my $prefix    = $thisfield->{'prefixed_by'} ? $data->{ lc( $thisfield->{'prefixed_by'} ) } : q();
			my $separator = $thisfield->{'prefix_separator'} // q();
			my $suffix    = $thisfield->{'suffix'}           // q();
			push @$list, { title => $displayfield, data => $prefix . $separator . ( $web // $value ) . $suffix }
			  if $web || $value ne q();
		}
		my %ext_attribute_field = map { $_ => 1 } @$field_with_extended_attributes;
		if ( $ext_attribute_field{$field} ) {
			my $ext_list = $self->_get_field_extended_attributes( $field, $data->{ lc($field) } );
			push @$list, @$ext_list;
		}
		if ( $composites->{$field} ) {
			my $composite_fields =
			  $self->_get_composite_field_rows( $isolate_id, $data, $field, $composite_display_pos );
			push @$list, @$composite_fields;
		}
		$self->_check_curator( $isolate_id, $list, $field );
		$self->_check_aliases( $isolate_id, $list, $field );
	}
	return q() if !@$list;
	$buffer .= $self->get_list_block( $list, { columnize => 1 } );
	$buffer .= q(</div></div>);
	$buffer .= $self->_get_map_section($maps);
	return $buffer;
}

sub _process_geography_fields {
	my ( $self, $args ) = @_;
	my ( $data, $field, $maps ) = @{$args}{qw(data field maps)};
	my $thisfield    = $self->{'xmlHandler'}->get_field_attributes($field);
	my $value        = $data->{$field};
	my $displayfield = $field;
	$displayfield =~ tr/_/ /;
	if ( $value && $thisfield->{'type'} eq 'geography_point' ) {
		my $geography = $self->{'datastore'}->get_geography_coordinates($value);
		my $map       = $geography;
		$map->{'field'} = ucfirst($displayfield);
		push @$maps, $geography;
		return 1;
	}
	if ( $value && ( $thisfield->{'geography_point_lookup'} // q() ) eq 'yes' ) {
		my $geography = $self->{'datastore'}->lookup_geography_point( $data, $field );
		if ( defined $geography->{'latitude'} ) {
			my $map = $geography;
			$map->{'field'}      = ucfirst($displayfield);
			$map->{'show_value'} = $value;
			$map->{'imprecise'}  = 1;
			push @$maps, $geography;
		}
	}
	return;
}

sub _get_composites {
	my ($self) = @_;
	my ( $composites, $composite_display_pos );
	my $composite_data =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id,position_after FROM composite_fields', undef, { fetch => 'all_arrayref', slice => {} } );
	foreach (@$composite_data) {
		$composite_display_pos->{ $_->{'id'} }  = $_->{'position_after'};
		$composites->{ $_->{'position_after'} } = 1;
	}
	return ( $composites, $composite_display_pos );
}

sub _check_curator {
	my ( $self, $isolate_id, $list, $field ) = @_;
	if ( $field eq 'curator' ) {
		my $history = $self->_get_history_field($isolate_id);
		push @$list, $history if $history;
	}
	return;
}

sub _check_aliases {
	my ( $self, $isolate_id, $list, $field ) = @_;
	if ( $field eq $self->{'system'}->{'labelfield'} ) {
		my $aliases = $self->{'datastore'}->get_isolate_aliases($isolate_id);
		if (@$aliases) {
			local $" = q(; );
			my $plural = @$aliases > 1 ? 'es' : '';
			push @$list, { title => "alias$plural", data => "@$aliases" };
		}
	}
	return;
}

sub _get_map_section {
	my ( $self, $maps ) = @_;
	return q() if !@$maps;
	my $buffer = q(<div><span class="info_icon fa-2x fa-fw fas fa-map fa-pull-left" style="margin-top:-0.2em"></span>);
	$buffer .= @$maps > 1 ? qq(<h2>Maps</h2>\n) : qq(<h2>$maps->[0]->{'field'}</h2>\n);
	my $i           = 1;
	my $map_options = $self->get_mapping_options;
	my @layers;
	my $layer_selection = {
		0 => sub { push @layers, BIGSdb::JSContent::get_ol_osm_layer() },
		1 => sub {
			push @layers, BIGSdb::JSContent::get_ol_osm_layer();
			push @layers, BIGSdb::JSContent::get_ol_maptiler_map_layer( $map_options->{'maptiler_key'} );
		},
		2 => sub {
			push @layers, BIGSdb::JSContent::get_ol_osm_layer();
			push @layers, BIGSdb::JSContent::get_ol_arcgis_world_imagery_layer();
			push @layers, BIGSdb::JSContent::get_ol_arcgis_hybdrid_ref_layer();
		},
		3 => sub {
			push @layers, BIGSdb::JSContent::get_ol_arcgis_world_streetmap_layer();
			push @layers, BIGSdb::JSContent::get_ol_arcgis_world_imagery_layer();
			push @layers, BIGSdb::JSContent::get_ol_arcgis_hybdrid_ref_layer();
		}
	};
	$layer_selection->{ $map_options->{'option'} }->();
	local $" = q(,);
	foreach my $map (@$maps) {
		$buffer .= q(<div style="float:left;margin:0 1em">);
		if ( @$maps > 1 ) {
			if ( $map->{'show_value'} ) {
				$buffer .= qq(<p><span class="data_title">$map->{'field'}:</span>$map->{'show_value'}</p>\n);
			} else {
				$buffer .=
				  qq(<p><span class="data_title">$map->{'field'}:</span>$map->{'latitude'}, $map->{'longitude'}</p>\n);
			}
		} else {
			if ( $map->{'show_value'} ) {
				$buffer .= qq(<p>$map->{'show_value'}</p>);
			} else {
				$buffer .= qq(<p>$map->{'latitude'}, $map->{'longitude'}</p>);
			}
		}
		$buffer .= qq(<div id="map$i" class="ol_map" style="position:relative">);
		if ( $map_options->{'option'} == 1 ) {
			$buffer .=
				q(<a href="https://www.maptiler.com" id="maptiler_logo" )
			  . q(style="display:none;position:absolute;left:10px;bottom:10px;z-index:10">)
			  . q(<img src="https://api.maptiler.com/resources/logo.svg" alt="MapTiler logo"></a>);
		}
		$buffer .= q(</div>);
		my $imprecise = $map->{'imprecise'} ? 1 : 0;
		$buffer .= <<"MAP";

<script>	
\$(document).ready(function() 	
    { 
      const layers = [
		@layers
	  ];
      let map = new ol.Map({
        target: 'map$i',
        layers: layers,
        view: new ol.View({
          center: ol.proj.fromLonLat([$map->{'longitude'}, $map->{'latitude'}]),
          zoom: 8 - $imprecise
        })
      });
      let pointer_style;
      if ($imprecise){
      	pointer_style = new ol.style.Style({
	        image: new ol.style.Circle({
	          radius: 20,
	          fill: new ol.style.Fill({
	          	color: 'rgb(0,0,255,0.2)'
	          	}),
	          stroke: new ol.style.Stroke({
	            color: [100,100,255], width: 2
	          })  
	        })
	      });
      } else {
	      pointer_style = new ol.style.Style({
	        image: new ol.style.Circle({
	          radius: 7,
	          stroke: new ol.style.Stroke({
	            color: [255,0,0], width: 2
	          })  
	        })
	      });
      }
      let layer = new ol.layer.Vector({
        source: new ol.source.Vector({
          features: [
             new ol.Feature({
                 geometry: new ol.geom.Point(ol.proj.fromLonLat([$map->{'longitude'}, $map->{'latitude'}]))
             })
          ]
        }), 
        style: pointer_style
     });
     map.addLayer(layer);
     \$("a#toggle_satellite$i").click(function(event){
     	if (layers[0].getVisible()){
     		layers[0].setVisible(false);
     		layers[1].setVisible(true);
     		if (typeof layers[2] !== 'undefined'){
     			layers[2].setVisible(true);
     		}
     		\$("a#maptiler_logo").show();
      		\$("span#satellite${i}_off").hide();
     		\$("span#satellite${i}_on").show();
     	} else {
     		layers[0].setVisible(true);
     		layers[1].setVisible(false);
     		if (typeof layers[2] !== 'undefined'){
     			layers[2].setVisible(false);
     		}
     		\$("a#maptiler_logo").hide();
     		\$("span#satellite${i}_on").hide();
     		\$("span#satellite${i}_off").show();
     	}
     });
     \$("a#recentre$i").click(function(event){
     	map.getView().animate({
     		center: ol.proj.fromLonLat([$map->{'longitude'}, $map->{'latitude'}]),
     		duration: 500
     	});
     });
   });

</script>
MAP
		$buffer .= q(<p style="margin-top:0.5em">);
		if ( $map_options->{'option'} > 0 ) {
			$buffer .=
				q(<span style="vertical-align:0.4em">Aerial view </span>)
			  . qq(<a class="toggle_satellite" id="toggle_satellite$i" style="cursor:pointer;margin-right:2em">)
			  . qq(<span class="fas fa-toggle-off toggle_icon fa-2x" id="satellite${i}_off"></span>)
			  . qq(<span class="fas fa-toggle-on toggle_icon fa-2x" id="satellite${i}_on" style="display:none">)
			  . q(</span></a>);
		}
		$buffer .=
			q(<span style="vertical-align:0.4em">Recentre </span>)
		  . qq(<a class="recentre" id="recentre$i" style="cursor:pointer;margin-right:2em">)
		  . qq(<span class="fas fa-crosshairs toggle_icon fa-2x" id="crosshairs$i"></span>)
		  . q(</a></p>);
		$buffer .= q(</div>);
		$i++;
	}
	$buffer .= q(</div><div style="clear:both"></div>);
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

sub _get_field_value {
	my ( $self, $data, $field ) = @_;
	my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
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
	my $value = ref $data->{ lc($field) } ? qq(@{$data->{ lc($field) }}) : $data->{ lc($field) };
	$value = BIGSdb::Utils::escape_html($value);
	return $value;
}

sub _get_grouped_fields {
	my ( $self, $isolate_id, $data ) = @_;
	my @group_list = split /,/x, ( $self->{'system'}->{'field_groups'} // q() );
	my $buffer     = q();
	foreach my $group (@group_list) {
		$group =~ s/\|.+$//x;
		$buffer .= $self->_get_provenance_fields( $isolate_id, $data, 0, $group );
	}
	return $buffer;
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
	my $hide  = keys %$data > MAX_EAV_FIELD_LIST ? 1                       : 0;
	my $class = $hide                            ? q(expandable_retracted) : q();
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
	my %order          = map { $_->{'attribute'} => $_->{'field_order'} } @$attribute_order;
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
	my %designations   = map { $_ => 1 } @$loci_with_designations;
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
	my $values = {};
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
				push @{ $values->{$field}->{'formatted'} },   $formatted_value;
				push @{ $values->{$field}->{'unformatted'} }, $value;
			}
			if ( ref $values->{$field}->{'formatted'} ne 'ARRAY' ) {
				$values->{$field}->{'formatted'}   = ['Not defined'];
				$values->{$field}->{'unformatted'} = [];
			}
		}
	} else {
		foreach my $field (@$scheme_fields) {
			$values->{$field}->{'formatted'}   = ['Not defined'];
			$values->{$field}->{'unformatted'} = [];
		}
	}
	return $values;
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
	  $self->{'datastore'}->get_scheme_allele_designations( $isolate_id, $scheme_id, { set_id => $set_id } );
	my $scheme_info   = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	local $| = 1;
	my $buffer = q();
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
	if ( $scheme_info->{'allow_presence'} ) {
		my $present = $self->{'datastore'}->run_query(
			'SELECT a.locus FROM allele_sequences a JOIN scheme_members s ON a.locus=s.locus '
			  . 'WHERE (a.isolate_id,s.scheme_id)=(?,?)',
			[ $isolate_id, $scheme_id ],
			{ fetch => 'col_arrayref' }
		);
		foreach my $locus (@$present) {
			next if defined $allele_designations->{$locus};
			$allele_designations->{$locus} = [
				{
					allele_id => 'P',
					status    => 'confirmed'
				}
			];
		}
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
		my @lowest_missing_profiles;
		my $min_missing;
		if ( $field eq $scheme_info->{'primary_key'} && $scheme_info->{'allow_missing_loci'} ) {
			my @pk_values =
			  ref $field_values->{$field}->{'unformatted'} ? @{ $field_values->{$field}->{'unformatted'} } : ();
			my %missing_count;
			if ( @pk_values > 1 ) {
				foreach my $profile_id (@pk_values) {
					my $profile = $self->{'datastore'}->get_profile_by_primary_key( $scheme_id, $profile_id );
					$min_missing //= @$profile;
					my $missing = grep { $_ eq 'N' } @$profile;
					if ( $missing < $min_missing ) {
						$min_missing = $missing;
					}
					$missing_count{$profile_id} = $missing;
				}
				foreach my $profile_id (@pk_values) {
					push @lowest_missing_profiles, $profile_id if $missing_count{$profile_id} == $min_missing;
				}
			}
		}
		my $values = qq(@{$field_values->{$field}->{'formatted'}}) // q(-);
		foreach my $profile_id (@lowest_missing_profiles) {
			my $title = "This profile has the fewest ($min_missing) missing loci";
			$values =~ s/>$profile_id</><span class="highlightvalue" title="$title">$profile_id<\/span></x;
		}
		if ( $args->{'no_render'} ) {
			$buffer .= qq(<dt>$cleaned</dt><dd>$values</dd>);
		} else {
			$buffer .= qq(<dl class="profile"><dt>$cleaned</dt><dd>$values</dd></dl>);
		}
	}
	if (   $scheme_info->{'primary_key'}
		&& $field_values->{ $scheme_info->{'primary_key'} }->{'formatted'}
		&& $self->{'datastore'}->are_lincodes_defined($scheme_id) )
	{
		$buffer .= $self->_get_lincode_values( $isolate_id, $scheme_id, $args );
	}
	$buffer .= q(</dl>) if $args->{'no_render'};
	return $buffer;
}

sub _get_lincode_values {
	my ( $self, $isolate_id, $scheme_id, $args ) = @_;
	my $lincode = $self->{'datastore'}->get_lincode_value( $isolate_id, $scheme_id );
	my $buffer  = q();
	if ( defined $lincode ) {
		local $" = q(_);
		my $lincode_string = qq(@$lincode);
		$buffer .=
		  $args->{'no_render'}
		  ? qq(<dt>LINcode</dt><dd>$lincode_string</dd>)
		  : qq(<dl class="profile"><dt>LINcode</dt><dd>$lincode_string</dd></dl>);
		my $prefix_table = $self->{'datastore'}->create_temp_lincode_prefix_values_table($scheme_id);
		my $data         = $self->{'datastore'}
		  ->run_query( "SELECT * FROM $prefix_table", undef, { fetch => 'all_arrayref', slice => {} } );
		my $prefix_values = {};
		foreach my $record (@$data) {
			$prefix_values->{ $record->{'field'} }->{ $record->{'prefix'} } = $record->{'value'};
		}
		my $prefix_fields =
		  $self->{'datastore'}
		  ->run_query( 'SELECT field FROM lincode_fields WHERE scheme_id=? ORDER BY display_order,field',
			$scheme_id, { fetch => 'col_arrayref' } );
		foreach my $field (@$prefix_fields) {
			my %used;
			my @prefixes = keys %{ $prefix_values->{$field} };
			my @values;
			foreach my $prefix (@prefixes) {
				if (   $lincode_string eq $prefix
					|| $lincode_string =~ /^${prefix}_/x && !$used{ $prefix_values->{$field}->{$prefix} } )
				{
					push @values, $prefix_values->{$field}->{$prefix};
					$used{ $prefix_values->{$field}->{$prefix} } = 1;
				}
			}
			@values = sort @values;
			local $" = q(; );
			next if !@values;
			$buffer .=
			  $args->{'no_render'}
			  ? qq(<dt>$field</dt><dd>@values</dd>)
			  : qq(<dl class="profile"><dt>$field</dt><dd>@values</dd></dl>);
		}
	}
	return $buffer;
}

sub _get_locus_value {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $locus, $designations, $summary_view, $no_render, $show_aliases ) =
	  @{$args}{qw(isolate_id locus designations summary_view no_render show_aliases)};
	my $cleaned    = $self->clean_locus( $locus, { common_name_class => 'locus_common_name' } );
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( $locus_info->{'description_url'} ) {
		$locus_info->{'description_url'} =~ s/\&/\&amp;/gx;
		$cleaned = qq(<a href="$locus_info->{'description_url'}">$cleaned</a>);
	}
	my $locus_aliases = $self->{'datastore'}->get_locus_aliases($locus);
	local $" = ';&nbsp;';
	my $alias_display = $show_aliases // $self->{'prefs'}->{'locus_alias'} ? 'inline' : 'none';
	my $display_title = $cleaned;
	$display_title .= qq(<span class="aliases" style="display:$alias_display">&nbsp;(@$locus_aliases)</span>)
	  if @$locus_aliases;
	my $display_value = q();
	my $first         = 1;

	foreach my $designation (@$designations) {
		$display_value .= q(, ) if !$first;
		my $status;
		if ( $designation->{'status'} eq 'provisional' ) {
			$status = 'provisional';
		}
		$display_value .= qq(<span class="$status">) if $status;
		my $url = '';
		my @anchor_att;
		my $update_tooltip = '';
		if ( $self->{'prefs'}->{'update_details'} && $designation->{'allele_id'} ) {
			$update_tooltip = $self->get_update_details_tooltip( $locus, $designation );
			push @anchor_att, qq(title="$update_tooltip");
		}
		if ( $locus_info->{'url'} && $designation->{'allele_id'} ne 'deleted' ) {
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
			} catch {
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
	  : qq(<dl class="profile"><dt class="locus">$display_title</dt><dd>$display_value</dd></dl>);
	return $buffer;
}

sub get_title {
	my ( $self, $options ) = @_;
	return 'Isolate information' if $options->{'breadcrumb'};
	my $q          = $self->{'cgi'};
	my $isolate_id = $q->param('id');
	return q()                   if $q->param('no_header');
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
		my $count  = @$pmids;
		my $plural = $count > 1 ? 's' : '';
		$buffer .= qq(<h2 style="display:inline">Publication$plural ($count)</h2>);
		my $hide  = @$pmids > HIDE_PMIDS;
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
		my $list   = [];
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
			my $n_stats = BIGSdb::Utils::get_N_stats( $seqbin_stats->{'total_length'}, $seqbin_stats->{'lengths'} );
			if ( $seqbin_stats->{'n50'} != $n_stats->{'N50'} ) {
				$logger->error( "$self->{'instance'} id-$isolate_id: N50 discrepancy with stored value. This should "
					  . 'not happen - has the seqbin_stats table been modified?' );
			}
			push @$list, { title => 'total length', data => "$commify{'total_length'} bp" };
			push @$list, { title => 'max length',   data => "$commify{'max_length'} bp" };
			push @$list, { title => 'mean length',  data => "$commify{'mean_length'} bp" };
			foreach my $stat (qw(N50 L50 N90 L90 N95 L95)) {
				my $value = BIGSdb::Utils::commify( $n_stats->{$stat} );
				push @$list,
				  {
					title => $stat,
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
		my $offline_stats_json =
		  $self->{'datastore'}->run_query( 'SELECT results FROM analysis_results WHERE (name,isolate_id)=(?,?)',
			[ 'AssemblyStats', $isolate_id ] );
		if ($offline_stats_json) {
			my $stats = decode_json($offline_stats_json);
			if ( $stats->{'length'} == $seqbin_stats->{'total_length'} ) {
				my %labels = (
					percent_GC => '%GC',
					N          => 'Ns'
				);
				foreach my $key (qw(percent_GC N gaps)) {
					push @$list,
					  {
						title => $labels{$key} // $key,
						data  => $stats->{$key}
					  } if defined $stats->{$key};
				}
			} else {
				$logger->error( "$self->{'instance'} id-$isolate_id: "
					  . 'Offline assembly stats total length does not match realtime calculated value. '
					  . 'Re-run update_assembly_stats.pl against this database to fix.' );
			}
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

sub _get_assembly_checks {
	my ( $self, $isolate_id ) = @_;
	return q() if !defined $self->{'assembly_checks'};
	return q()
	  if !$self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM seqbin_stats WHERE isolate_id=?)', $isolate_id );
	my $last_run =
	  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM last_run WHERE (isolate_id,name)=(?,?))',
		[ $isolate_id, 'AssemblyChecks' ] );
	my $results = $self->{'datastore'}->run_query( 'SELECT name,status FROM assembly_checks WHERE isolate_id=?',
		$isolate_id, { fetch => 'all_hashref', key => 'name' } );
	return q() if !$last_run && !keys %$results;
	my @checks;
	my @checks_to_perform =
	  ( [qw(max_contigs)], [qw(min_size max_size)], [qw(min_n50)], [qw(min_gc max_gc)], [qw(max_n)], [qw(max_gaps)] );

	foreach my $check (@checks_to_perform) {
		my $result;
		if ( @$check == 1 ) {
			$result = $self->_get_check_results( $results, $check->[0] );
		} else {
			$result = $self->_get_min_max_check_results( $results, @$check );
		}
		push @checks, $result if $result;
	}
	return q() if !@checks;
	my $buffer = qq(<div id="assembly_checks">\n);
	$buffer .= qq(<span class="info_icon fas fa-2x fa-fw fa-tasks fa-pull-left" style="margin-top:-0.2em"></span>\n);
	$buffer .= qq(<h2>Assembly checks</h2>\n);
	$buffer .= qq(<div class="scrollable"><table class="resultstable">\n);
	$buffer .= qq(<tr><th>Check</th><th>Status</th><th>Warn/fail reason</th></tr>\n);
	my $td = 1;

	foreach my $check (@checks) {
		$buffer .= qq(<tr class="td$td"><td>$check->{'name'}</td><td>);
		if ( $check->{'status'} eq 'passed' ) {
			$buffer .= GOOD;
		} elsif ( $check->{'status'} eq 'warn' ) {
			$buffer .= MEH;
		} elsif ( $check->{'status'} eq 'fail' ) {
			$buffer .= BAD;
		} else {
			$logger->error("No status set for $check->{'name'}");
		}
		$buffer .= q(</td><td style="text-align:left">);
		if ( $check->{'status'} ne 'passed' ) {
			$buffer .= $check->{'message'} // q();
		}
		$buffer .= qq(</td></tr>\n);
		$td = $td == 1 ? 2 : 1;
	}
	$buffer .= qq(</table></div>\n);
	$buffer .= q(</div>);
	return $buffer;
}

sub _get_check_results {
	my ( $self, $results, $name ) = @_;
	return if !$self->_check_exists($name);
	my %label = (
		max_contigs => 'Number of contigs',
		min_n50     => 'Minimum N50',
		max_n       => 'Number of Ns',
		max_gaps    => 'Number of gaps'
	);
	my $message = $self->{'assembly_checks'}->{$name}->{'message'} // q();
	if ( $results->{$name}->{'status'} ) {
		$message .=
		  qq[ ($results->{$name}->{'status'} threshold: ]
		  . BIGSdb::Utils::commify( $self->{'assembly_checks'}->{$name}->{ $results->{$name}->{'status'} } ) . q[)];
	}
	return {
		name    => $label{$name},
		message => $message,
		status  => $results->{$name}->{'status'} // 'passed'
	};
}

sub _get_min_max_check_results {
	my ( $self, $results, $min, $max ) = @_;
	my %label = (
		min_size => 'Assembly size',
		max_size => 'Assembly size',
		min_gc   => '%GC',
		max_gc   => '%GC'
	);
	foreach my $check ( $min, $max ) {
		if ( $self->_check_exists($check) && $self->{'assembly_checks'}->{$check}->{'fail'} != 0 ) {
			my $message = $self->{'assembly_checks'}->{$check}->{'message'} // q();
			if ( $results->{$check}->{'status'} ) {
				$message .=
					qq[ ($results->{$check}->{'status'} threshold: ]
				  . BIGSdb::Utils::commify( $self->{'assembly_checks'}->{$check}->{ $results->{$check}->{'status'} } )
				  . q[)];
				return {
					name    => $label{$check},
					message => $message,
					status  => $results->{$check}->{'status'} // 'passed'
				};
			}
		}
	}
	return {
		name   => $label{$min},
		status => 'passed'
	};
}

sub _check_exists {
	my ( $self, $check ) = @_;
	return $self->{'assembly_checks'}->{$check}->{'warn'} || $self->{'assembly_checks'}->{$check}->{'fail'};
}

sub _get_annotation_metrics {
	my ( $self, $isolate_id, $data ) = @_;
	my $prov_metrics    = $self->_get_provenance_annotation_metrics($data);
	my $scheme_metrics  = $self->_get_scheme_annotation_metrics($isolate_id);
	my $min_genome_size = $self->{'system'}->{'min_genome_size'} // $self->{'config'}->{'min_genome_size'}
	  // MIN_GENOME_SIZE;
	my $has_genome =
	  $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM seqbin_stats WHERE isolate_id=? AND total_length>=?)',
		[ $isolate_id, $min_genome_size ] );
	return q() if !$prov_metrics->{'total_fields'} && !@$scheme_metrics;
	my $prov_buffer = q(<h3>Provenance information</h3>);
	if ( $prov_metrics->{'total_fields'} ) {
		my $score         = int( 100 * $prov_metrics->{'annotated'} / $prov_metrics->{'total_fields'} );
		my $colour        = BIGSdb::Utils::get_percent_colour( $score, { min => 0, max => 100, middle => 50 } );
		my $min_threshold = $self->{'system'}->{'provenance_annotation_bad_threshold'}
		  // $self->{'config'}->{'provenance_annotation_bad_threshold'} // 75;
		my $quality;
		if ( $score == 100 ) {
			$quality = GOOD;
		} elsif ( $score < $min_threshold ) {
			$quality = BAD;
		} else {
			$quality = MEH;
		}
		my @missing;
		my @field_list = @{ $prov_metrics->{'field_list'} };
		local $" = q(</li><li>);
		foreach my $field_hash ( @{ $prov_metrics->{'fields'} } ) {
			my ($annotated) = values %$field_hash;
			push @missing, keys %$field_hash if !$annotated;
		}
		$prov_buffer .= qq(<div class="scrollable"><table class="resultstable">\n);
		$prov_buffer .= q(<tr><th rowspan="2">Fields used in metric</th><th rowspan="2">Fields completed</th>)
		  . qq(<th colspan="2">Annotation</th></tr>\n);
		$prov_buffer .= qq(<tr><th style="min-width:5em">Score</th><th>Status</th></tr>\n);
		$prov_buffer .=
			qq(<tr class="td1"><td>$prov_metrics->{'total_fields'} )
		  . q(<a id="showhide_metric_fields" style="cursor:pointer">)
		  . q(<span id="show_metric_fields" title="Show list" style="padding-left:2em" class="fa-regular fa-eye"></span>)
		  . q(<span id="hide_metric_fields" title="Hide list" style="display:none;padding-left:2em" )
		  . q(class="fa-regular fa-eye-slash"></span></a>)
		  . qq(<ul id="metric_fields" style="display:none;text-align:left"><li>@field_list</li></ul></td>);
		$prov_buffer .=
			qq(<td>$prov_metrics->{'annotated'}</td></td>)
		  . q(<td style="position:relative"><span )
		  . qq(style="position:absolute;font-size:0.8em;margin-left:-0.5em">$score</span>)
		  . qq(<div style="margin-top:0.2em;background-color:\#$colour;)
		  . qq(border:1px solid #ccc;height:0.8em;width:$score%"></div></td><td>$quality</td></tr>);
		$prov_buffer .= qq(</table></div>\n);
		if (@missing) {
			local $" = q(, );
			$prov_buffer .= qq(<p>Missing field values for: @missing</p>);
		}
	}
	my $scheme_buffer = qq(<h3>Scheme completion</h3><div class="scrollable"><table class="resultstable">\n);
	$scheme_buffer .=
		q(<tr><th rowspan="2">Scheme</th><th rowspan="2">Scheme loci</th><th rowspan="2">Designated loci</th>)
	  . q(<th colspan="2">Annotation</th></tr>);
	$scheme_buffer .= qq(<tr><th style="min-width:5em">Score</th><th>Status</th></tr>\n);
	my $td = 1;
	my $scheme_count;
	foreach my $scheme (@$scheme_metrics) {
		next if !$scheme->{'loci'};
		next if !$scheme->{'designated'} && $scheme->{'loci'} > 1;
		next if !$scheme->{'designated'} && !$has_genome;
		my $percent       = int( 100 * $scheme->{'designated'} / $scheme->{'loci'} );
		my $max_threshold = $scheme->{'max_threshold'} // $scheme->{'loci'};
		$max_threshold = $scheme->{'loci'} if $max_threshold > $scheme->{'loci'};
		my $min_threshold = $scheme->{'min_threshold'} // 0;
		$min_threshold = 0 if $min_threshold < 0;

		if ( $max_threshold < $min_threshold ) {
			$logger->error("Scheme $scheme->{'id'} ($scheme->{'name'}) has max_threshold < min_threshold");
			$min_threshold = 0;
			$max_threshold = $scheme->{'loci'};
		}
		$scheme_buffer .=
			qq(<tr class="td$td"><td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'})
		  . qq(&amp;page=schemeInfo&scheme_id=$scheme->{'id'}">$scheme->{'name'}</a></td><td>$scheme->{'loci'}</td>)
		  . qq(<td>$scheme->{'designated'}</td>);
		my $min    = 100 * $min_threshold / $scheme->{'loci'};
		my $max    = 100 * $max_threshold / $scheme->{'loci'};
		my $middle = ( $min + $max ) / 2;
		my $colour = BIGSdb::Utils::get_percent_colour( $percent, { min => $min, max => $max, middle => $middle } );
		$scheme_buffer .=
			q(<td style="position:relative"><span )
		  . qq(style="position:absolute;font-size:0.8em;margin-left:-0.5em">$percent</span>)
		  . qq(<div style="margin-top:0.2em;background-color:\#$colour;)
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
		$scheme_buffer .= qq(<td>$quality</td>);
		$scheme_buffer .= qq(</tr>\n);
		$td = $td == 1 ? 2 : 1;
		$scheme_count++;
	}
	$scheme_buffer .= qq(</table></div>\n);
	return q() if !$scheme_count && !$prov_metrics->{'total_fields'};
	my $buffer = qq(<div id="annotation_metrics">\n);
	$buffer .= qq(<span class="info_icon fas fa-2x fa-fw fa-award fa-pull-left" style="margin-top:-0.2em"></span>\n);
	$buffer .= qq(<h2>Annotation quality metrics</h2>\n);
	$buffer .= $prov_buffer   if $prov_metrics->{'total_fields'};
	$buffer .= $scheme_buffer if $scheme_count;
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_provenance_annotation_metrics {
	my ( $self, $data ) = @_;
	my $att           = $self->{'xmlHandler'}->get_all_field_attributes;
	my $fields        = $self->{'xmlHandler'}->get_field_list( { show_hidden => 1 } );
	my $results       = {};
	my %null_terms    = map { lc($_) => 1 } NULL_TERMS;
	my $count         = 0;
	my $total_fields  = 0;
	my $metric_fields = [];
	my $field_results = [];

	foreach my $field (@$fields) {
		next if ( $att->{$field}->{'annotation_metric'} // q() ) ne 'yes';
		$total_fields++;
		push @$metric_fields, $field;
		if ( defined $data->{ lc($field) } && !$null_terms{ lc( $data->{ lc($field) } ) } ) {
			$count++;
			push @$field_results, { $field => 1 };
		} else {
			push @$field_results, { $field => 0 };
		}
	}
	$results =
	  { total_fields => $total_fields, annotated => $count, field_list => $metric_fields, fields => $field_results };
	return $results;
}

sub _get_scheme_annotation_metrics {
	my ( $self, $isolate_id ) = @_;
	my $schemes = $self->{'datastore'}->run_query(
		'SELECT id,COUNT(*) AS loci FROM schemes s JOIN scheme_members m ON s.id=m.scheme_id '
		  . 'WHERE quality_metric GROUP BY id ORDER BY loci ASC',
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
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
	return $values;
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
		my $hide  = @$projects > 1;
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
