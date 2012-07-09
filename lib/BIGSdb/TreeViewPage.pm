#Written by Keith Jolley
#Copyright (c) 2011-2012, University of Oxford
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
package BIGSdb::TreeViewPage;
use strict;
use warnings;
use parent qw(BIGSdb::Page);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_tree_javascript {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	my $plugin_js;
	if ( $options->{'checkboxes'} ) {
		$plugin_js = <<"JS";
		"plugins" : [ "themes", "html_data", "checkbox"],
		"checkbox" : {
			"real_checkboxes" : true,
			"real_checkboxes_names" : function (n) { return [(n[0].id || Math.ceil(Math.random() * 10000)), 1]; }
		}
JS
	} else {
		$plugin_js = <<"JS";
		"plugins" : [ "themes", "html_data"]
JS
	}
	my $check_schemes_js = '';
	if ( $options->{'check_schemes'} ) {
		my $scheme_ids = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
		push @$scheme_ids, 0;
		foreach (@$scheme_ids) {
			if ( $q->param("s_$_") ) {
				$check_schemes_js .= <<"JS";
\$("#tree").bind("loaded.jstree", function (event, data) {
  		\$("#tree").jstree("check_node", \$("#s_$_"));
	});			
JS
			}
		}
	}
	my $buffer = << "END";
\$(function () {
	\$('a[rel=ajax]').click(function(){
  		\$(this).attr('href', function(){
  			if (this.href.match(/javascript.loadContent/)){
  				return;
  			};
    		return(this.href.replace(/(.*)/, "javascript:loadContent\('\$1&no_header=1\'\)"));
    	});
  	});
	$check_schemes_js
	\$("#tree").jstree({ 
		"core" : {
			"animation" : 200,
			"initially_open" : ["all_loci"]
		},
		"themes" : {
			"theme" : "default"
		},
$plugin_js		
	});	

});

function loadContent(url) {
	\$("#scheme_table").html('<img src=\"/javascript/themes/default/throbber.gif\" /> Loading ...').load(url,tooltip);
}

tooltip = function(e){
	\$('div.content a').tooltip({ 
	    track: true, 
	    delay: 0, 
	    showURL: false, 
	    showBody: " - ", 
	    fade: 250 
	});
};

END
	return $buffer;
}

sub get_tree {
	my ( $self, $isolate_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $page = $self->{'cgi'}->param('page');
	$page = 'info' if any { $page eq $_ } qw (isolateDelete isolateUpdate alleleUpdate);
	my $isolate_clause = defined $isolate_id ? "&amp;id=$isolate_id" : '';
	my $groups_with_no_parent =
	  $self->{'datastore'}->run_list_query(
		"SELECT id FROM scheme_groups WHERE id NOT IN (SELECT group_id FROM scheme_group_group_members) ORDER BY display_order,name");
	my $set_id = $self->get_set_id;
	my $set_clause = $set_id ? " AND id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)" : '';
	my $schemes_not_in_group =
	  $self->{'datastore'}->run_list_query_hashref(
"SELECT id,description FROM schemes WHERE id NOT IN (SELECT scheme_id FROM scheme_group_scheme_members) $set_clause ORDER BY display_order,description"
	  );
	my ( $buffer, $scheme_nodes );

	foreach (@$groups_with_no_parent) {
		my $group_info          = $self->{'datastore'}->get_scheme_group_info($_);
		my $group_scheme_buffer = $self->_get_group_schemes( $_, $isolate_id, $options );
		my $child_group_buffer  = $self->_get_child_groups( $_, $isolate_id, 1, $options );
		if ( $group_scheme_buffer || $child_group_buffer ) {
			$buffer .=
			  $options->{'no_link_out'}
			  ? "<li><a>$group_info->{'name'}</a>\n"
			  : "<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page$isolate_clause&amp;group_id=$_\" rel=\"ajax\">$group_info->{'name'}</a>\n";
			$buffer .= $group_scheme_buffer if $group_scheme_buffer;
			$buffer .= $child_group_buffer  if $child_group_buffer;
			$buffer .= "</li>\n";
		}
	}
	if (@$schemes_not_in_group) {
		my $data_exists = 0;
		my $temp_buffer;
		if (@$groups_with_no_parent) {
			$temp_buffer .=
			  $options->{'no_link_out'}
			  ? "<li><a>Other schemes</a><ul>"
			  : "<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page$isolate_clause&amp;group_id=0\" rel=\"ajax\">Other schemes</a><ul>";
		}
		foreach (@$schemes_not_in_group) {
			next if $options->{'isolate_display'} && !$self->{'prefs'}->{'isolate_display_schemes'}->{ $_->{'id'} };
			next if $options->{'analysis_pref'}   && !$self->{'prefs'}->{'analysis_schemes'}->{ $_->{'id'} };
			$_->{'description'} =~ s/&/\&amp;/g;
			if ( !defined $isolate_id || $self->_scheme_data_present( $_->{'id'}, $isolate_id ) ) {
				my $scheme_loci_buffer;
				if ( $options->{'list_loci'} ) {
					$scheme_loci_buffer = $self->_get_scheme_loci( $_->{'id'}, $isolate_id, $options );
					$data_exists = 1 if $scheme_loci_buffer;
				} else {
					$data_exists = 1;
				}
				if ( $options->{'no_link_out'} ) {
					my $id = $options->{'select_schemes'} ? " id=\"s_$_->{'id'}\"" : '';
					$temp_buffer .= "<li$id><a>$_->{'description'}</a>\n";
				} else {
					$temp_buffer .=
"<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page$isolate_clause&amp;scheme_id=$_->{'id'}\" rel=\"ajax\">$_->{'description'}</a>\n";
				}
				$temp_buffer .= $scheme_loci_buffer if $scheme_loci_buffer;
				$temp_buffer .= "</li>\n";
			}
		}
		$temp_buffer .= "</ul></li>" if @$groups_with_no_parent;
		$buffer .= $temp_buffer if $data_exists;
	}
	my $loci_not_in_schemes = $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
	if ( @$loci_not_in_schemes && ( !defined $isolate_id || $self->_data_not_in_scheme_present($isolate_id) ) ) {
		my $scheme_loci_buffer;
		if ( $options->{'list_loci'} ) {
			$scheme_loci_buffer = $self->_get_scheme_loci( 0, $isolate_id, $options ) if $options->{'list_loci'};
		}
		if ( !$options->{'list_loci'} || ( $options->{'list_loci'} && $scheme_loci_buffer ) ) {
			if ( $options->{'no_link_out'} ) {
				my $id = $options->{'select_schemes'} ? " id=\"s_0\"" : '';
				$buffer .= "<li$id><a>Loci not in schemes</a>\n";
			} else {
				$buffer .=
"<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page$isolate_clause&amp;scheme_id=0\" rel=\"ajax\">Loci not in schemes</a>\n";
			}
			$buffer .= $scheme_loci_buffer if $scheme_loci_buffer;
			$buffer .= "</li>\n";
		}
	}
	my $main_buffer;
	if ($buffer) {
		$main_buffer = "<ul>\n";
		$main_buffer .=
		  $options->{'no_link_out'}
		  ? "<li id=\"all_loci\"><a>All loci</a><ul>\n"
		  : "<li id=\"all_loci\"><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page$isolate_clause&amp;scheme_id=-1\" rel=\"ajax\">All loci</a><ul>\n";
		$main_buffer .= $buffer;
		$main_buffer .= "</ul>\n</li></ul>\n";
	} else {
		$main_buffer = "<ul><li><a>No loci available for analysis.</a></li></ul>\n";
	}
	return $main_buffer;
}

sub _get_group_schemes {
	my ( $self, $group_id, $isolate_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	my $buffer;
	my $set_id     = $self->get_set_id;
	my $set_clause = $set_id ? " AND scheme_id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)" : '';
	my $schemes    = $self->{'datastore'}->run_list_query(
		"SELECT scheme_id FROM scheme_group_scheme_members LEFT JOIN schemes ON schemes.id=scheme_id WHERE group_id=? "
		  . "$set_clause ORDER BY display_order,description",
		$group_id
	);
	if (@$schemes) {

		foreach my $scheme_id (@$schemes) {
			next if $options->{'isolate_display'} && !$self->{'prefs'}->{'isolate_display_schemes'}->{$scheme_id};
			next if $options->{'analysis_pref'}   && !$self->{'prefs'}->{'analysis_schemes'}->{$scheme_id};
			my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
			my $scheme_loci_buffer;
			if ( $options->{'list_loci'} ) {
				$scheme_loci_buffer = $self->_get_scheme_loci( $scheme_info->{'id'}, $isolate_id, $options );
				next if !$scheme_loci_buffer;
			}
			$scheme_info->{'description'} =~ s/&/\&amp;/g;
			my $page = $self->{'cgi'}->param('page');
			$page = 'info' if any { $page eq $_ } qw (isolateDelete isolateUpdate alleleUpdate);
			if ( defined $isolate_id ) {
				if ( $self->_scheme_data_present( $scheme_id, $isolate_id ) ) {
					$buffer .=
					  $options->{'no_link_out'}
					  ? "<li><a>$scheme_info->{'description'}</a>"
					  : "<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;id=$isolate_id&amp;"
					  . "scheme_id=$scheme_info->{'id'}\" rel=\"ajax\">$scheme_info->{'description'}</a>";
					$buffer .= $scheme_loci_buffer if $scheme_loci_buffer;
					$buffer .= "</li>\n";
				}
			} else {
				if ( $options->{'no_link_out'} ) {
					my $id = $options->{'select_schemes'} ? " id=\"s_$scheme_id\"" : '';
					$buffer .= "<li$id><a>$scheme_info->{'description'}</a>";
				} else {
					$buffer .= "<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;"
					  . "scheme_id=$scheme_info->{'id'}\" rel=\"ajax\">$scheme_info->{'description'}</a>";
				}
				$buffer .= $scheme_loci_buffer if $scheme_loci_buffer;
				$buffer .= "</li>\n";
			}
		}
	}
	return "<ul>\n$buffer</ul>\n" if $buffer;
	return;
}

sub _get_scheme_loci {
	my ( $self, $scheme_id, $isolate_id, $options ) = @_;
	my $analysis_pref = $self->{'system'}->{'dbtype'} eq 'isolates' ? 1 : 0;
	my ( $loci, $scheme_fields );
	if ($scheme_id) {
		$loci = $self->{'datastore'}->get_scheme_loci( $scheme_id, { 'profile_name' => 0, 'analysis_pref' => $analysis_pref } );
		if ( $options->{'scheme_fields'} ) {
			$scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		}
	} else {
		my $set_id = $self->get_set_id;
		$loci = $self->{'datastore'}->get_loci_in_no_scheme( { analyse_pref => $analysis_pref, set_id => $set_id } );
	}
	my $qry    = "SELECT id,common_name FROM loci WHERE common_name IS NOT NULL";
	my $cn_sql = $self->{'db'}->prepare($qry);
	eval { $cn_sql->execute };
	$logger->error($@) if $@;
	my $common_names = $cn_sql->fetchall_hashref('id');
	my $buffer;
	foreach (@$loci) {
		my $cleaned = $self->clean_checkbox_id($_);
		my $id      = $scheme_id ? "s_$scheme_id\_l_$cleaned" : "l_$cleaned";
		my $locus   = $self->clean_locus($_);
		$buffer .= "<li id=\"$id\"><a>$locus</a></li>\n";
	}
	foreach my $scheme_field (@$scheme_fields) {
		my $cleaned = $self->clean_checkbox_id($scheme_field);
		my $id      = "s_$scheme_id\_f_$cleaned";
		$scheme_field =~ tr/_/ /;
		$buffer .= "<li id=\"$id\"><a>$scheme_field</a></li>\n";
	}
	return "<ul>\n$buffer</ul>\n" if $buffer;
	return;
}

sub _get_child_groups {
	my ( $self, $group_id, $isolate_id, $level, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $buffer;
	my $child_groups = $self->{'datastore'}->run_list_query(
"SELECT id FROM scheme_groups LEFT JOIN scheme_group_group_members ON scheme_groups.id=group_id WHERE parent_group_id=? ORDER BY display_order,name",
		$group_id
	);
	if (@$child_groups) {
		foreach (@$child_groups) {
			my $group_info = $self->{'datastore'}->get_scheme_group_info($_);
			my $new_level  = $level;
			last if $new_level == 10;    #prevent runaway if child is set as the parent of a parental group
			my $group_scheme_buffer = $self->_get_group_schemes( $_, $isolate_id, $options );
			my $child_group_buffer = $self->_get_child_groups( $_, $isolate_id, ++$new_level, $options );
			if ( $group_scheme_buffer || $child_group_buffer ) {
				my $page = $self->{'cgi'}->param('page');
				$page = 'info' if any { $page eq $_ } qw (isolateDelete isolateUpdate alleleUpdate);
				if ( defined $isolate_id ) {
					$buffer .=
					  $options->{'no_link_out'}
					  ? "<li><a>$group_info->{'name'}</a>\n"
					  : "<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;id=$isolate_id&amp;group_id=$_\" rel=\"ajax\">$group_info->{'name'}</a>\n";
				} else {
					$buffer .=
					  $options->{'no_link_out'}
					  ? "<li><a>$group_info->{'name'}</a>\n"
					  : "<li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;group_id=$_\" rel=\"ajax\">$group_info->{'name'}</a>\n";
				}
				$buffer .= $group_scheme_buffer if $group_scheme_buffer;
				$buffer .= $child_group_buffer  if $child_group_buffer;
				$buffer .= "</li>";
			}
		}
	}
	return "<ul>\n$buffer</ul>\n" if $buffer;
	return;
}

sub _scheme_data_present {
	my ( $self, $scheme_id, $isolate_id ) = @_;
	if ( !$self->{'sql'}->{'scheme_data_designations'} ) {
		$self->{'sql'}->{'scheme_data_designations'} =
		  $self->{'db'}->prepare(
"SELECT EXISTS(SELECT * FROM allele_designations LEFT JOIN scheme_members ON allele_designations.locus=scheme_members.locus WHERE isolate_id=? AND scheme_id=?)"
		  );
	}
	eval { $self->{'sql'}->{'scheme_data_designations'}->execute( $isolate_id, $scheme_id ) };
	$logger->error($@) if $@;
	my ($designations_present) = $self->{'sql'}->{'scheme_data_designations'}->fetchrow_array;
	return 1 if $designations_present;
	if ( !$self->{'sql'}->{'scheme_data_sequences'} ) {
		$self->{'sql'}->{'scheme_data_sequences'} =
		  $self->{'db'}->prepare(
"SELECT EXISTS(SELECT * FROM allele_sequences LEFT JOIN scheme_members ON allele_sequences.locus=scheme_members.locus LEFT JOIN sequence_bin ON allele_sequences.seqbin_id=sequence_bin.id WHERE isolate_id=? AND scheme_id=?)"
		  );
	}
	eval { $self->{'sql'}->{'scheme_data_sequences'}->execute( $isolate_id, $scheme_id ) };
	$logger->error($@) if $@;
	my ($sequences_present) = $self->{'sql'}->{'scheme_data_sequences'}->fetchrow_array;
	return $sequences_present ? 1 : 0;
}

sub _data_not_in_scheme_present {
	my ( $self, $isolate_id ) = @_;
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? "SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)"
	  : "SELECT locus FROM scheme_members";
	my $designations =
	  $self->{'datastore'}
	  ->run_simple_query( "SELECT EXISTS(SELECT * FROM allele_designations WHERE isolate_id=? AND locus NOT IN ($set_clause))",
		$isolate_id )->[0];
	return 1 if $designations;
	my $sequences = $self->{'datastore'}->run_simple_query(
		"SELECT EXISTS(SELECT * FROM allele_sequences LEFT JOIN sequence_bin ON allele_sequences.seqbin_id=sequence_bin.id WHERE "
		  . "isolate_id=? AND locus NOT IN ($set_clause))",
		$isolate_id
	)->[0];
	return $sequences ? 1 : 0;
}
1;
