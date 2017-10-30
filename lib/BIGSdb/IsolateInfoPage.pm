#Written by Keith Jolley
#Copyright (c) 2010-2017, University of Oxford
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
use BIGSdb::Constants qw(:interface);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
use List::MoreUtils qw(none uniq);
my $logger = get_logger('BIGSdb.Page');
use constant ISOLATE_SUMMARY => 1;
use constant LOCUS_SUMMARY   => 2;
use constant MAX_DISPLAY     => 1000;

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
	$self->{$_} = 1 foreach qw(jQuery tooltips jQuery.jstree jQuery.columnizer);
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $buffer = << "END";
\$(function () {
	\$(document).ajaxComplete(function() {
		reloadTooltips();
		\$("span#show_aliases_text").css('display', 'inline');
		\$("span#hide_aliases_text").css('display', 'none');
		\$("span#tree_button").css('display', 'inline');
		if (\$("span").hasClass('aliases')){
			\$("span#aliases_button").css('display', 'inline');
		} else {
			\$("span#aliases_button").css('display', 'none');
		}
	});
	\$( "#hidden_references" ).css('display', 'none');
	\$( "#show_refs" ).click(function() {
		if (\$("span#show_refs_text").css('display') == 'none'){
			\$("span#show_refs_text").css('display', 'inline');
			\$("span#hide_refs_text").css('display', 'none');
		} else {
			\$("span#show_refs_text").css('display', 'none');
			\$("span#hide_refs_text").css('display', 'inline');
		}
		\$( "#hidden_references" ).toggle( 'blind', {} , 500 );
		return false;
	});
	\$( "#sample_table" ).css('display', 'none');
	\$( "#show_samples" ).click(function() {
		if (\$("span#show_samples_text").css('display') == 'none'){
			\$("span#show_samples_text").css('display', 'inline');
			\$("span#hide_samples_text").css('display', 'none');
		} else {
			\$("span#show_samples_text").css('display', 'none');
			\$("span#hide_samples_text").css('display', 'inline');
		}
		\$( "#sample_table" ).toggle( 'blind', {} , 500 );
		return false;
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
	\$("#provenance").columnize({width:400});
	\$("#seqbin").columnize({
		width:300, 
		lastNeverTallest: true,
	});
	\$(".smallbutton").css('display', 'inline');
});

END
	$buffer .= $self->get_tree_javascript;
	return $buffer;
}

sub _get_child_group_scheme_tables {
	my ( $self, $group_id, $isolate_id, $level ) = @_;
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
		$parent_buffer .= qq(<div style="float:left;padding-right:0.5em">\n)
		  . qq(<h3 class="group group$parent_level">$parent_group_info->{'name'}</h3>\n);
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
				my $buffer = $self->_get_child_group_scheme_tables( $child_group, $isolate_id, ++$new_level );
				$buffer .= $self->_get_group_scheme_tables( $child_group, $isolate_id );
				$self->{'level'} = $level;
				$group_buffer .= $parent_buffer if $parent_buffer;
				undef $parent_buffer;
				if ($buffer) {
					$group_buffer .= $buffer;
				}
			}
		}
	} else {
		my $buffer = $self->_get_group_scheme_tables( $group_id, $isolate_id );
		$group_buffer .= $parent_buffer if $parent_buffer;
		$group_buffer .= $buffer;
	}
	return $group_buffer;
}

sub _get_group_scheme_tables {
	my ( $self, $group_id, $isolate_id ) = @_;
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
				$buffer .= $self->_get_scheme( $scheme_id, $isolate_id, $self->{'curate'} );
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
		if ( BIGSdb::Utils::is_int( $q->param('group_id') ) ) {
			$param = q(group_id=) . $q->param('group_id');
		} elsif ( BIGSdb::Utils::is_int( $q->param('scheme_id') ) ) {
			$param = q(scheme_id=) . $q->param('scheme_id');
		}
		say q(Too many items to display - )
		  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=info&amp;)
		  . qq(id=$isolate_id&amp;function=scheme_display&amp;$param">display selected schemes separately.</a>);
		return 1;
	}
	if ( BIGSdb::Utils::is_int( $q->param('group_id') ) ) {
		$self->_print_group_data( $isolate_id, $q->param('group_id') );
		return 1;
	} elsif ( BIGSdb::Utils::is_int( $q->param('scheme_id') ) ) {
		$self->_print_scheme_data( $isolate_id, $q->param('scheme_id') );
		return 1;
	}
	return;
}

sub _print_group_data {
	my ( $self, $isolate_id, $group_id ) = @_;
	$self->{'groups_with_data'} =
	  $self->get_tree( $isolate_id, { isolate_display => $self->{'curate'} ? 0 : 1, get_groups => 1 } );
	if ( $group_id == 0 ) {    #Other schemes (not part of a scheme group)
		$self->_print_other_schemes($isolate_id);
	} else {                   #Scheme group
		say $self->_get_child_group_scheme_tables( $group_id, $isolate_id, 1 );
		say $self->_get_group_scheme_tables( $group_id, $isolate_id );
		$self->_close_divs;
	}
	return;
}

sub _print_scheme_data {
	my ( $self, $isolate_id, $scheme_id ) = @_;
	if ( $scheme_id == -1 ) {    #All schemes/loci
		$self->{'groups_with_data'} =
		  $self->get_tree( $isolate_id, { isolate_display => $self->{'curate'} ? 0 : 1, get_groups => 1 } );
		$self->_print_all_loci($isolate_id);
	} else {
		say $self->_get_scheme( $scheme_id, $isolate_id, $self->{'curate'} );
	}
	return;
}

sub _should_display_items {
	my ( $self, $isolate_id ) = @_;
	my $q     = $self->{'cgi'};
	my $items = 0;
	if ( BIGSdb::Utils::is_int( $q->param('group_id') ) ) {
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
	} elsif ( BIGSdb::Utils::is_int( $q->param('scheme_id') ) ) {
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
	if ( BIGSdb::Utils::is_int( $q->param('group_id') ) ) {
		say q(<div class="box" id="resultspanel">);
		$self->_print_group_data( $isolate_id, $q->param('group_id') );
		say q(<div style="clear:both"></div>);
		say q(</div>);
	} elsif ( BIGSdb::Utils::is_int( $q->param('scheme_id') ) ) {
		say q(<div class="box" id="resultspanel">);
		$self->_print_scheme_data( $isolate_id, $q->param('scheme_id') );
		say q(<div style="clear:both"></div>);
		say q(</div>);
	} else {
		say q(<div class="box" id="statusbad"><p>No scheme or group passed.</p></div>);
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
		say qq(<h1>Isolate information: id-$isolate_id</h1>);
		say q(<div class="box" id="statusbad"><p>Isolate id must be an integer.</p></div>);
		return;
	}
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		say q(<h1>Isolate information</h1>);
		say q(<div class="box" id="statusbad"><p>This function can only be called for isolate databases.</p></div>);
		return;
	}
	my $data =
	  $self->{'datastore'}
	  ->run_query( "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id, { fetch => 'row_hashref' } );
	if ( !$data ) {
		say qq(<h1>Isolate information: id-$isolate_id</h1>);
		say q(<div class="box" id="statusbad"><p>The database contains no record of this isolate.</p></div>);
		return;
	} elsif ( !$self->is_allowed_to_view_isolate($isolate_id) ) {
		say q(<h1>Isolate information</h1>);
		say q(<div class="box" id="statusbad"><p>Your user account does not )
		  . q(have permission to view this record.</p></div>);
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
	if ( $self->{'cgi'}->param('history') ) {
		say q(<div class="box" id="resultstable">);
		say q(<h2>Update history</h2>);
		say $self->_get_update_history($isolate_id);
		my $back = BACK;
		my $set_clause = $set_id ? qq(&amp;set_id=$set_id) : q();
		say
		  qq(<p style="margin-top:1em"><a href="$self->{'system'}->{'script_name'}?page=info&amp;db=$self->{'instance'})
		  . qq($set_clause&amp;id=$isolate_id" title="Back">$back</a></p>);
		say q(</div>);
	} else {
		$self->_print_action_panel($isolate_id) if $self->{'curate'};
		$self->_print_projects($isolate_id);
		say q(<div class="box" id="resultspanel">);
		say $self->get_isolate_record($isolate_id);
		my $tree_button =
		    q( <span id="tree_button" style="margin-left:1em;display:none">)
		  . q(<a id="show_tree" class="smallbutton" style="cursor:pointer">)
		  . q(<span id="show_tree_text" style="display:none">show</span>)
		  . q(<span id="hide_tree_text" style="display:inline">hide</span> tree</a></span>);
		my $show_aliases = $self->{'prefs'}->{'locus_alias'} ? 'none'   : 'inline';
		my $hide_aliases = $self->{'prefs'}->{'locus_alias'} ? 'inline' : 'none';
		my $aliases_button =
		    q( <span id="aliases_button" style="margin-left:1em;display:none">)
		  . q(<a id="show_aliases" class="smallbutton" style="cursor:pointer">)
		  . qq(<span id="show_aliases_text" style="display:$show_aliases">)
		  . qq(show</span><span id="hide_aliases_text" style="display:$hide_aliases">hide</span> )
		  . q(locus aliases</a></span>);
		my $loci = $self->{'datastore'}->get_loci( { set_id => $set_id } );

		if (@$loci) {
			say $self->_get_classification_group_data($isolate_id);
			say qq(<h2>Schemes and loci$tree_button$aliases_button</h2>);
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
		}
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

sub _get_classification_group_data {
	my ( $self, $isolate_id ) = @_;
	my $view   = $self->{'system'}->{'view'};
	my $buffer = q();
	my $classification_schemes =
	  $self->{'datastore'}->run_query( 'SELECT * FROM classification_schemes ORDER BY display_order,name',
		undef, { fetch => 'all_arrayref', slice => {} } );
	my $td = 1;
	foreach my $cscheme (@$classification_schemes) {
		my $cg_buffer;
		my $scheme_id          = $cscheme->{'scheme_id'};
		my $cache_table_exists = $self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=? OR table_name=?)',
			[ "temp_isolates_scheme_fields_$scheme_id", "temp_${view}_scheme_fields_$scheme_id" ]
		);
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
			  ? qq( <a class="tooltip" title="$cscheme->{'name'} - $desc"> )
			  . q(<span class="fa fa-info-circle"></span></a>)
			  : q();
			my $plural = $cscheme->{'inclusion_threshold'} == 1 ? q() : q(es);
			$buffer .=
			    qq(<tr class="td$td"><td>$cscheme->{'name'}$tooltip</td><td>$scheme_info->{'name'}</td>)
			  . qq(<td>Single-linkage</td><td>$cscheme->{'inclusion_threshold'}</td><td>$cscheme->{'status'}</td><td>)
			  . qq($cg_buffer</td></tr>);
			$td = $td == 1 ? 2 : 1;
		}
	}
	if ($buffer) {
		$buffer =
		    q(<h2>Similar isolates (determined by classification schemes)</h2>)
		  . q(<p>Experimental schemes are subject to change and are not a stable part of the nomenclature.</p>)
		  . q(<div class="scrollable">)
		  . q(<div class="resultstable" style="float:left"><table class="resultstable"><tr>)
		  . q(<th>Classification scheme</th><th>Underlying scheme</th><th>Clustering method</th>)
		  . qq(<th>Mismatch threshold</th><th>Status</th><th>Group</th></tr>$buffer</table></div></div>);
	}
	return $buffer;
}

sub _print_other_schemes {
	my ( $self, $isolate_id ) = @_;
	my $scheme_ids = $self->{'datastore'}->run_query(
		'SELECT id FROM schemes WHERE id NOT IN (SELECT scheme_id FROM '
		  . 'scheme_group_scheme_members) ORDER BY display_order,description',
		undef,
		{ fetch => 'col_arrayref' }
	);
	foreach my $scheme_id (@$scheme_ids) {
		next if !$self->{'prefs'}->{'isolate_display_schemes'}->{$scheme_id};
		my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
		say $self->_get_scheme( $scheme_id, $isolate_id, $self->{'curate'} );
	}
	return;
}

sub _print_all_loci {
	my ( $self, $isolate_id ) = @_;
	my $groups_with_no_parents = $self->{'datastore'}->run_query(
		'SELECT id FROM scheme_groups WHERE id NOT IN (SELECT group_id '
		  . 'FROM scheme_group_group_members) ORDER BY display_order,name',
		undef,
		{ fetch => 'col_arrayref' }
	);
	if ( keys %{ $self->{'groups_with_data'} } ) {
		foreach my $group_id (@$groups_with_no_parents) {
			say $self->_get_child_group_scheme_tables( $group_id, $isolate_id, 1 );
			say $self->_get_group_scheme_tables( $group_id, $isolate_id );
			$self->_close_divs;
		}
		if ( $self->{'groups_with_data'}->{0} ) {    #Schemes not in groups
			say q(<div style="float:left;padding-right:0.5em"><h3 class="group group0">Other schemes</h3>);
			$self->_print_other_schemes($isolate_id);
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
	my $no_scheme_data = $self->_get_scheme( 0, $isolate_id, $self->{'curate'} );
	if ($no_scheme_data) {    #Loci not in schemes
		say q(<div style="float:left;padding-right:0.5em"><h3 class="group group0">&nbsp;</h3>);
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
		isolateDelete  => 'Delete record',
		isolateUpdate  => 'Update record',
		batchAddSeqbin => 'Sequence bin',
		newVersion     => 'New version',
		tagScan        => 'Sequence tags'
	);
	my %labels = (
		isolateDelete  => 'Delete',
		isolateUpdate  => 'Update',
		batchAddSeqbin => 'Upload contigs',
		newVersion     => 'Create',
		tagScan        => 'Scan'
	);
	$q->param( isolate_id => $isolate_id );
	my $page = $q->param('page');
	my $seqbin_exists =
	  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM seqbin_stats WHERE isolate_id=?)', $isolate_id );

	foreach my $action (qw (isolateDelete isolateUpdate batchAddSeqbin newVersion tagScan)) {
		next
		  if $action eq 'tagScan'
		  && ( !$seqbin_exists
			|| ( !$self->can_modify_table('allele_designations') && !$self->can_modify_table('allele_sequences') ) );
		next if $action eq 'batchAddSeqbin' && !$self->can_modify_table('sequences');
		say qq(<fieldset style="float:left"><legend>$titles{$action}</legend>);
		say $q->start_form;
		$q->param( page => $action );
		say $q->hidden($_) foreach qw (db page id isolate_id);
		say q(<div style="text-align:center">);
		say $q->submit( -name => $labels{$action}, -class => BUTTON_CLASS );
		say q(</div>);
		say $q->end_form;
		say q(</fieldset>);
	}
	$q->param( page => $page );                                                 #Reset
	say q(</div></div>);
	return;
}

sub _get_update_history {
	my ( $self,    $isolate_id )  = @_;
	my ( $history, $num_changes ) = $self->_get_history($isolate_id);
	my $buffer = q();
	if ($num_changes) {
		$buffer .= qq(<table class="resultstable"><tr><th>Timestamp</th><th>Curator</th><th>Action</th></tr>\n);
		my $td = 1;
		foreach (@$history) {
			my $curator_info = $self->{'datastore'}->get_user_info( $_->{'curator'} );
			my $time         = $_->{'timestamp'};
			$time =~ s/:\d\d\.\d+//x;
			my $action = $_->{'action'};
			$action =~ s/->/\&rarr;/gx;
			$buffer .=
			    qq(<tr class="td$td"><td style="vertical-align:top">$time</td>)
			  . qq(<td style="vertical-align:top">$curator_info->{'first_name'} $curator_info->{'surname'}</td>)
			  . qq(<td style="text-align:left">$action</td></tr>\n);
			$td = $td == 1 ? 2 : 1;
		}
		$buffer .= qq(</table>\n);
	}
	return $buffer;
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
		throw BIGSdb::DatabaseNoRecordException("Record $id does not exist");
	}
	$self->add_existing_metadata_to_hashref($data);
	$buffer .= q(<div class="scrollable">);
	if ( $summary_view == LOCUS_SUMMARY ) {
		$buffer .= $self->_get_tree($id);
	} else {
		$buffer .= $self->_get_provenance_fields( $id, $data, $summary_view );
		if ( !$summary_view ) {
			$buffer .= $self->_get_version_links($id);
			$buffer .= $self->_get_ref_links($id);
			$buffer .= $self->_get_seqbin_link($id);
			$buffer .= $self->get_sample_summary( $id, { hide => 1 } );
		}
	}
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_provenance_fields {
	my ( $self, $isolate_id, $data, $summary_view ) = @_;
	my $buffer = qq(<h2>Provenance/meta data</h2>\n);
	$buffer .= q(<div id="provenance"><dl class="data">);
	my $q             = $self->{'cgi'};
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata( $set_id, { curate => $self->{'curate'} } );
	my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
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
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
		my $displayfield = $metafield // $field;
		$displayfield .= qq( <span class="metaset">Metadata: $metaset</span>) if !$set_id && defined $metaset;
		$displayfield =~ tr/_/ /;
		my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
		next if ( $thisfield->{'curate_only'} // '' ) eq 'yes' && !$self->{'curate'};
		my $web;
		my $value = $data->{ lc($field) };
		$value = BIGSdb::Utils::escape_html($value);

		if ( !defined $value ) {
			if ( $composites{$field} ) {
				$buffer .= $self->_get_composite_field_rows( $isolate_id, $data, $field, \%composite_display_pos );
			}
			next;    #Do not print row
		} elsif ( $thisfield->{'web'} ) {
			my $url = $thisfield->{'web'};
			$url =~ s/\[\\*\?\]/$value/x;
			$url =~ s/\&/\&amp;/gx;
			my $domain;
			if ( ( lc($url) =~ /http:\/\/(.*?)\/+/x ) ) {
				$domain = $1;
			}
			$web = qq(<a href="$url">$value</a>);
			if ( $domain && $domain ne $q->virtual_host ) {
				$web .= qq( <span class="link"><span style="font-size:1.2em">&rarr;</span> $domain</span>);
			}
		}
		my %user_field = map { $_ => 1 } qw(curator sender);
		if ( $user_field{$field} || ( $thisfield->{'userfield'} // '' ) eq 'yes' ) {
			$buffer .= $self->_get_user_field( $summary_view, $field, $displayfield, $value, $data );
		} else {
			$buffer .= qq(<dt class="dontend">$displayfield</dt>\n);
			$buffer .= q(<dd>) . ( $web || $value ) . qq(</dd>\n);
		}
		$buffer .= $self->_get_history_field($isolate_id) if ( $field eq 'curator' );
		my %ext_attribute_field = map { $_ => 1 } @$field_with_extended_attributes;
		if ( $ext_attribute_field{$field} ) {
			$buffer .= $self->_get_field_extended_attributes( $field, $value );
		}
		if ( $field eq $self->{'system'}->{'labelfield'} ) {
			my $aliases = $self->{'datastore'}->get_isolate_aliases($isolate_id);
			if (@$aliases) {
				local $" = q(; );
				my $plural = @$aliases > 1 ? 'es' : '';
				$buffer .= qq(<dt class="dontend">alias$plural</dt>\n);
				$buffer .= qq(<dd>@$aliases</dd>\n);
			}
		}
		if ( $composites{$field} ) {
			$buffer .= $self->_get_composite_field_rows( $isolate_id, $data, $field, \%composite_display_pos );
		}
	}
	$buffer .= qq(</dl></div>\n);
	return $buffer;
}

sub _get_field_extended_attributes {
	my ( $self, $field, $value ) = @_;
	my $buffer = q();
	my $q      = $self->{'cgi'};
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
		foreach my $attribute ( sort { $order{$a} <=> $order{$b} } keys(%attributes) ) {
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
			$buffer .= qq(<dt class="dontend">$attribute</dt>\n);
			$buffer .= q(<dd>) . ( $att_web || $attributes{$attribute} ) . qq(</dd>\n);
		}
	}
	return $buffer;
}

sub _get_user_field {
	my ( $self, $summary_view, $field, $display_field, $value, $data ) = @_;
	my $userdata = $self->{'datastore'}->get_user_info($value);
	my $buffer;
	my $colspan = $summary_view ? 5 : 2;
	my $person = qq($userdata->{first_name} $userdata->{surname});
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
	$buffer .= qq(<dt class="dontend">$display_field</dt>\n);
	$buffer .= qq(<dd>$person</dd>\n);
	return $buffer;
}

sub _get_history_field {
	my ( $self, $isolate_id ) = @_;
	my $q      = $self->{'cgi'};
	my $buffer = q();
	my ( $history, $num_changes ) = $self->_get_history( $isolate_id, 10 );
	if ($num_changes) {
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
		$buffer .= qq(<dt class="dontend">update history</dt>\n);
		$buffer .= qq(<dd><a title="$title" class="update_tooltip">$num_changes update$plural</a>);
		my $refer_page = $q->param('page');
		my $set_id     = $self->get_set_id;
		my $set_clause = $set_id ? qq(&amp;set_id=$set_id) : q();
		$buffer .= qq( <a href="$self->{'system'}->{'script_name'}?page=info&amp;db=$self->{'instance'}&amp;)
		  . qq(id=$isolate_id&amp;history=1&amp;refer=$refer_page$set_clause">show details</a></dd>\n);
	}
	return $buffer;
}

sub _get_composite_field_rows {
	my ( $self, $isolate_id, $data, $field_to_position_after, $composite_display_pos ) = @_;
	my $buffer = '';
	foreach ( keys %$composite_display_pos ) {
		next if $composite_display_pos->{$_} ne $field_to_position_after;
		my $displayfield = $_;
		$displayfield =~ tr/_/ /;
		my $value = $self->{'datastore'}->get_composite_value( $isolate_id, $_, $data );
		$buffer .= qq(<dt class="dontend">$displayfield</dt>\n);
		$buffer .= qq(<dd>$value</dd>\n);
	}
	return $buffer;
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

sub get_sample_summary {
	my ( $self, $id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my ($sample_buffer) = $self->_get_samples($id);
	my $buffer = '';
	if ($sample_buffer) {
		my $display      = $options->{'hide'} ? 'none'   : 'inline';
		my $show_samples = $options->{'hide'} ? 'inline' : 'none';
		my $hide_samples = $options->{'hide'} ? 'none'   : 'inline';
		if ( $options->{'hide'} ) {
			$buffer .=
			    q(<h2>Samples<span style="margin-left:1em"><a id="show_samples" class="smallbutton" )
			  . q(style="cursor:pointer;display:none">)
			  . qq(<span id="show_samples_text" style="display:$show_samples">show</span>)
			  . qq(<span id="hide_samples_text" style="display:$hide_samples">hide</span></a></span></h2>\n);
		}
		$buffer .= qq(<table class="resultstable" id="sample_table">\n);
		$buffer .= $sample_buffer;
		$buffer .= qq(</table>\n);
	}
	return $buffer;
}

sub _get_samples {
	my ( $self, $id ) = @_;
	my $td            = 1;
	my $buffer        = q();
	my $sample_fields = $self->{'xmlHandler'}->get_sample_field_list;
	my ( @selected_fields, @clean_fields );
	foreach my $field (@$sample_fields) {
		next if $field eq 'isolate_id';
		my $attributes = $self->{'xmlHandler'}->get_sample_field_attributes($field);
		next if ( $attributes->{'maindisplay'} // '' ) eq 'no';
		push @selected_fields, $field;
		( my $clean = $field ) =~ tr/_/ /;
		push @clean_fields, $clean;
	}
	if (@selected_fields) {
		my $samples = $self->{'datastore'}->get_samples($id);
		my @sample_rows;
		foreach my $sample (@$samples) {
			foreach my $field (@$sample_fields) {
				if ( $field eq 'sender' || $field eq 'curator' ) {
					my $user_info = $self->{'datastore'}->get_user_info( $sample->{$field} );
					$sample->{$field} = qq($user_info->{'first_name'} $user_info->{'surname'});
				}
			}
			my $row = qq(<tr class="td$td">);
			if ( $self->{'curate'} ) {
				$row .=
				    qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=delete&amp;table=samples&amp;isolate_id=$id&amp;sample_id=$sample->{'sample_id'}">)
				  . qq(Delete</a></td><td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=update&amp;table=samples&amp;isolate_id=$id&amp;sample_id=$sample->{'sample_id'}">)
				  . q(Update</a></td>);
			}
			foreach my $field (@selected_fields) {
				$sample->{$field} = defined $sample->{$field} ? $sample->{$field} : '';
				if ( $field eq 'sample_id' && $self->{'prefs'}->{'sample_details'} ) {
					my $info = qq(Sample $sample->{$field} - );
					foreach my $field (@$sample_fields) {
						next if $field eq 'sample_id' || $field eq 'isolate_id';
						( my $clean = $field ) =~ tr/_/ /;
						$info .= qq($clean: $sample->{$field}&nbsp;<br />)
						  if defined $sample->{$field};    #nbsp added to stop Firefox truncating text
					}
					$row .= qq(<td>$sample->{$field}<span style=\"font-size:0.5em\"> </span>)
					  . qq(<a class="update_tooltip" title="$info">&nbsp;...&nbsp;</a></td>);
				} else {
					$row .= qq(<td>$sample->{$field}</td>);
				}
			}
			$row .= q(</tr>);
			push @sample_rows, $row;
			$td = $td == 1 ? 2 : 1;
		}
		if (@sample_rows) {
			my $rows = scalar @sample_rows + 1;
			local $" = q(</th><th>);
			$buffer .= q(<tr>);
			$buffer .= q(<td><table style="width:100%"><tr>);
			if ( $self->{'curate'} ) {
				$buffer .= q(<th>Delete</th><th>Update</th>);
			}
			$buffer .= qq(<th>@clean_fields</th></tr>);
			local $" = qq(\n);
			$buffer .= qq(@sample_rows);
			$buffer .= qq(</table></td></tr>\n);
		}
	}
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
	my $loci_with_tags =
	  $self->{'datastore'}
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
	my ( $self, $scheme_id, $isolate_id, $summary_view ) = @_;
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
	$buffer .= qq(<div style="float:left;padding-right:0.5em">\n);
	$buffer .= qq(<h3 class="scheme"><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=schemeInfo&amp;scheme_id=$scheme_id">$scheme_info->{'name'}</a></h3>\n);
	my @args = (
		{
			loci                => $loci,
			summary_view        => $summary_view,
			scheme_id           => $scheme_id,
			scheme_fields_count => $scheme_fields_count,
			isolate_id          => $isolate_id
		}
	);
	$buffer .= $self->get_scheme_flags( $scheme_id, { link => 1 } );
	$buffer .= $self->_get_scheme_values(@args);
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
	foreach my $locus (@$loci) {
		my $designations = $allele_designations->{$locus};
		next if $self->{'prefs'}->{'isolate_display_loci'}->{$locus} eq 'hide';
		$buffer .= $self->_get_locus_value(
			{
				isolate_id   => $isolate_id,
				locus        => $locus,
				designations => $designations,
				summary_view => $summary_view
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
			my $display = $self->{'prefs'}->{'tooltips'} ? 'inline' : 'none';
			$cleaned .= qq( <a class="tooltip" title="$field - $scheme_field_info->{'description'}" )
			  . qq(style="display:$display"><span class="fa fa-info-circle" style="color:white"></span></a>);
		}
		$buffer .= qq(<dl class="profile"><dt>$cleaned</dt><dd>);
		local $" = ', ';
		$buffer .= qq(@{$field_values->{$field}}) // q(-);
		$buffer .= q(</dd></dl>);
	}
	return $buffer;
}

sub _get_locus_value {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $locus, $designations, $summary_view ) = @{$args}{qw(isolate_id locus designations summary_view)};
	my $cleaned       = $self->clean_locus($locus);
	my $buffer        = qq(<dl class="profile"><dt>$cleaned);
	my $locus_info    = $self->{'datastore'}->get_locus_info($locus);
	my $locus_aliases = $self->{'datastore'}->get_locus_aliases($locus);
	local $" = ';&nbsp;';
	my $alias_display = $self->{'prefs'}->{'locus_alias'} ? 'inline' : 'none';
	$buffer .= qq(&nbsp;<span class="aliases" style="display:$alias_display">(@$locus_aliases)</span>)
	  if @$locus_aliases;

	if ( $locus_info->{'description_url'} ) {
		$locus_info->{'description_url'} =~ s/\&/\&amp;/gx;
		$buffer .= qq(&nbsp;<a href="$locus_info->{'description_url'}" class="info_tooltip">)
		  . q(<span class="fa fa-info-circle"></span></a>);
	}
	$buffer .= q(</dt><dd>);
	my $first = 1;
	foreach my $designation (@$designations) {
		$buffer .= q(, ) if !$first;
		my $status;
		if ( $designation->{'status'} eq 'provisional' ) {
			$status = 'provisional';
		} elsif ( $designation->{'status'} eq 'ignore' ) {
			$status = 'ignore';
		}
		$buffer .= qq(<span class="$status">) if $status;
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
			$buffer .= qq(<a @anchor_att>$designation->{'allele_id'}</a>);
		} else {
			$buffer .= $designation->{'allele_id'};
		}
		$buffer .= q(</span>) if $status;
		$first = 0;
	}
	$buffer .=
	  $self->get_seq_detail_tooltips( $isolate_id, $locus,
		{ get_all => 1, allele_flags => $self->{'prefs'}->{'allele_flags'} } )
	  if $self->{'prefs'}->{'sequence_details'};
	my $action = @$designations ? EDIT : ADD;
	$buffer .=
	    qq( <a href="$self->{'system'}->{'script_name'}?page=alleleUpdate&amp;db=$self->{'instance'}&amp;)
	  . qq(isolate_id=$isolate_id&amp;locus=$locus" class="action">$action</a>)
	  if $self->{'curate'};
	$buffer .= q(&nbsp;) if !@$designations;
	$buffer .= q(</dd>);

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
			catch BIGSdb::DatabaseConnectionException with {
				$sequence = 'Cannot connect to database';
			}
			catch BIGSdb::DatabaseConfigurationException with {
				my $ex = shift;
				$sequence = $ex->{-text};
			};
			$buffer .= qq(<dd class="seq" style="text-align:left">$seq_name$sequence</dd>\n) if defined $sequence;
		}
	}
	$buffer .= q(</dl>);
	return $buffer;
}

sub get_title {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $isolate_id = $q->param('id');
	return q() if $q->param('no_header');
	return q(Invalid isolate id) if !BIGSdb::Utils::is_int($isolate_id);
	my $name  = $self->get_name($isolate_id);
	my $title = qq(Isolate information: id-$isolate_id);
	local $" = q( );
	$title .= qq( ($name)) if $name;
	$title .= q( - );
	$title .= $self->{'system'}->{'description'};
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
	if ( @$old_versions || @$new_versions ) {
		$buffer .= qq(<h2>Versions</h2>\n);
		$buffer .= qq(<p>More than one version of this isolate record exist.</p>\n);
		$buffer .= q(<dl class="data">);
	}
	if (@$old_versions) {
		my @version_links;
		foreach my $version ( reverse @$old_versions ) {
			push @version_links, qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=info&amp;id=$version">$version</a>);
		}
		local $" = ', ';
		$buffer .= qq(<dt>Older versions</dt><dd>@version_links</dd>\n);
	}
	if (@$new_versions) {
		my @version_links;
		foreach my $version (@$new_versions) {
			push @version_links, qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=info&amp;id=$version">$version</a>);
		}
		local $" = q(, );
		$buffer .= qq(<dt>Newer versions</dt><dd>@version_links</dd>\n);
	}
	if ( @$old_versions || @$new_versions ) {
		$buffer .= qq(</dl>\n);
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
	my $buffer = '';
	if (@$pmids) {
		my $count = @$pmids;
		my $plural = $count > 1 ? 's' : '';
		$buffer .= qq(<h2 style="display:inline">Publication$plural ($count)</h2>);
		my $display = @$pmids > 4 ? 'none' : 'block';
		my ( $show, $hide ) = ( EYE_SHOW, EYE_HIDE );
		$buffer .=
		    q(<span style="margin-left:1em"><a id="show_refs" )
		  . qq(style="cursor:pointer"><span id="show_refs_text" title="Show references" style="display:inline">$show</span>)
		  . qq(<span id="hide_refs_text" title="Hide references" style="display:none">$hide</span></a></span>)
		  if $display eq 'none';
		my $id = $display eq 'none' ? 'hidden_references' : 'references';
		$buffer .= qq(<ul id="$id" style="display:$display">\n);
		my $citations =
		  $self->{'datastore'}->get_citation_hash( $pmids,
			{ formatted => 1, all_authors => 1, state_if_unavailable => 1, link_pubmed => 1 } );

		foreach my $pmid ( sort { $citations->{$a} cmp $citations->{$b} } @$pmids ) {
			$buffer .= qq(<li style="padding-bottom:1em">$citations->{$pmid});
			$buffer .= $self->get_link_button_to_ref($pmid);
			$buffer .= qq(</li>\n);
		}
		$buffer .= qq(</ul>\n);
	}
	return $buffer;
}

sub _get_seqbin_link {
	my ( $self, $isolate_id ) = @_;
	$self->{'remoteContigManager'}->update_isolate_remote_contig_lengths($isolate_id);
	my $seqbin_stats = $self->{'datastore'}->get_seqbin_stats( $isolate_id, { general => 1, lengths => 1 } );
	my $buffer       = q();
	my $q            = $self->{'cgi'};
	if ( $seqbin_stats->{'contigs'} ) {
		my %commify =
		  map { $_ => BIGSdb::Utils::commify( $seqbin_stats->{$_} ) } qw(contigs total_length max_length mean_length);
		my $plural = $seqbin_stats->{'contigs'} == 1 ? '' : 's';
		$buffer .= qq(<h2>Sequence bin</h2>\n);
		$buffer .= qq(<div id="seqbin"><dl class="data"><dt class="dontend">contigs</dt><dd>$commify{'contigs'}</dd>\n);
		if ( $seqbin_stats->{'contigs'} > 1 ) {
			my $n_stats = BIGSdb::Utils::get_N_stats( $seqbin_stats->{'total_length'}, $seqbin_stats->{'lengths'} );
			$buffer .= qq(<dt class="dontend">total length</dt><dd>$commify{'total_length'} bp</dd>\n);
			$buffer .= qq(<dt class="dontend">max length</dt><dd>$commify{'max_length'} bp</dd>\n);
			$buffer .= qq(<dt class="dontend">mean length</dt><dd>$commify{'mean_length'} bp</dd>\n);
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
				$buffer .= qq(<dt class="dontend">$stats_labels{$stat}</dt><dd>$value</dd>\n);
			}
		} else {
			$buffer .= qq(<dt class="dontend">length</dt><dd>$seqbin_stats->{'total_length'} bp</dd>);
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
		$tagged = BIGSdb::Utils::commify($tagged);
		$buffer .= qq(<dt class="dontend">loci tagged</dt><dd>$tagged</dd>\n);
		$buffer .= qq(<dt class="dontend">detailed breakdown</dt><dd>\n);
		$buffer .= $q->start_form;
		$q->param( curate => 1 ) if $self->{'curate'};
		$q->param( page => 'seqbin' );
		$q->param( isolate_id => $isolate_id );
		$buffer .= $q->hidden($_) foreach qw (db page curate isolate_id set_id);
		$buffer .= $q->submit( -value => 'Display', -class => 'smallbutton' );
		$buffer .= $q->end_form;
		$buffer .= qq(</dd></dl>\n);
		$q->param( page => 'info' );
		$buffer .= q(</div>);
	}
	return $buffer;
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
		say q(<div class="box" id="projects"><div class="scrollable">);
		say q(<h2>Projects</h2>);
		my $plural = @$projects == 1 ? '' : 's';
		say qq(<p>This isolate is a member of the following project$plural:</p>);
		say q(<dl class="projects">);
		foreach my $project (@$projects) {
			say qq(<dt>$project->{'short_description'}</dt>);
			say qq(<dd>$project->{'full_description'}</dd>);
		}
		say q(</dl></div></div>);
	}
	return;
}
1;
