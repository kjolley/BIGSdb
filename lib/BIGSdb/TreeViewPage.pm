#Written by Keith Jolley
#Copyright (c) 2011-2016, University of Oxford
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
		my $scheme_ids =
		  $self->{'datastore'}->run_query( 'SELECT id FROM schemes', undef, { fetch => 'col_arrayref' } );
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
	\$("a[data-rel~='ajax']").click(function(){
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
	my $isolate_clause = defined $isolate_id ? qq(&amp;id=$isolate_id) : q();
	my $groups_with_no_parent = $self->{'datastore'}->run_query(
		'SELECT id FROM scheme_groups WHERE id NOT IN (SELECT group_id FROM '
		  . 'scheme_group_group_members) ORDER BY display_order,name',
		undef,
		{ fetch => 'col_arrayref' }
	);
	my $set_id               = $self->get_set_id;
	my $set_clause           = $set_id ? qq( AND id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)) : q();
	my $schemes_not_in_group = $self->{'datastore'}->run_query(
		'SELECT id,name FROM schemes WHERE id NOT IN (SELECT scheme_id FROM '
		  . "scheme_group_scheme_members) $set_clause ORDER BY display_order,name",
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $buffer;

	foreach my $group (@$groups_with_no_parent) {
		my $group_info          = $self->{'datastore'}->get_scheme_group_info($group);
		my $group_scheme_buffer = $self->_get_group_schemes( $group, $isolate_id, $options );
		my $child_group_buffer  = $self->_get_child_groups( $group, $isolate_id, 1, $options );
		if ( $group_scheme_buffer || $child_group_buffer ) {
			$buffer .=
			  $options->{'no_link_out'}
			  ? qq(<li><a>$group_info->{'name'}</a>\n)
			  : qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=$page$isolate_clause&amp;group_id=$group" )
			  . qq(rel="nofollow" data-rel="ajax">$group_info->{'name'}</a>\n);
			$buffer .= $group_scheme_buffer if $group_scheme_buffer;
			$buffer .= $child_group_buffer  if $child_group_buffer;
			$buffer .= qq(</li>\n);
		}
	}
	if (@$schemes_not_in_group) {
		my $data_exists = 0;
		my $temp_buffer;
		if (@$groups_with_no_parent) {
			$temp_buffer .=
			  $options->{'no_link_out'}
			  ? q(<li><a>Other schemes</a><ul>)
			  : qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page)
			  . qq($isolate_clause&amp;group_id=0" rel="nofollow" data-rel="ajax">Other schemes</a><ul>);
		}
		foreach my $scheme (@$schemes_not_in_group) {
			next
			  if $options->{'isolate_display'}
			  && !$self->{'prefs'}->{'isolate_display_schemes'}->{ $scheme->{'id'} };
			next if $options->{'analysis_pref'} && !$self->{'prefs'}->{'analysis_schemes'}->{ $scheme->{'id'} };
			$scheme->{'name'} =~ s/&/\&amp;/gx;
			if ( !defined $isolate_id || $self->_scheme_data_present( $scheme->{'id'}, $isolate_id ) ) {
				my $scheme_loci_buffer;
				$data_exists = 1;
				if ( $options->{'no_link_out'} ) {
					my $id = $options->{'select_schemes'} ? qq( id="s_$scheme->{'id'}") : q();
					$temp_buffer .= qq(<li$id><a>$scheme->{'name'}</a>\n);
				} else {
					$temp_buffer .=
					    qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
					  . qq(page=$page$isolate_clause&amp;scheme_id=$scheme->{'id'}" rel="nofollow" )
					  . qq(data-rel="ajax">$scheme->{'name'}</a>\n);
				}
				$temp_buffer .= $scheme_loci_buffer if $scheme_loci_buffer;
				$temp_buffer .= qq(</li>\n);
			}
		}
		$temp_buffer .= q(</ul></li>) if @$groups_with_no_parent;
		$buffer .= $temp_buffer if $data_exists;
	}
	my $loci_not_in_schemes = $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
	if ( @$loci_not_in_schemes && ( !defined $isolate_id || $self->_data_not_in_scheme_present($isolate_id) ) ) {
		if ( $options->{'no_link_out'} ) {
			my $id = $options->{'select_schemes'} ? q( id="s_0") : q();
			$buffer .= qq(<li$id><a>Loci not in schemes</a>\n);
		} else {
			$buffer .=
			    qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=$page$isolate_clause&amp;scheme_id=0" rel="nofollow" data-rel="ajax">)
			  . qq(Loci not in schemes</a>\n");
		}
		$buffer .= qq(</li>\n);
	}
	my $main_buffer;
	if ($buffer) {
		$main_buffer = qq(<ul>\n);
		$main_buffer .=
		  $options->{'no_link_out'}
		  ? qq(<li id="all_loci"><a>All loci</a><ul>\n)
		  : qq(<li id="all_loci"><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=$page$isolate_clause&amp;scheme_id=-1" rel="nofollow" data-rel="ajax">All loci</a><ul>\n);
		$main_buffer .= $buffer;
		$main_buffer .= qq(</ul>\n</li></ul>\n);
	} else {
		$main_buffer = qq(<ul><li><a>No loci available for analysis.</a></li></ul>\n);
	}
	if ( $options->{'get_groups'} ) {    #Just return a list of groups containing data
		my @groups = $main_buffer =~ /group_id=(\d+)/gx;
		my %groups = map { $_ => 1 } @groups;
		return \%groups;
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
	my $schemes    = $self->{'datastore'}->run_query(
		'SELECT scheme_id FROM scheme_group_scheme_members LEFT JOIN schemes ON schemes.id=scheme_id '
		  . "WHERE group_id=? $set_clause ORDER BY display_order,name",
		$group_id,
		{ fetch => 'col_arrayref' }
	);
	if (@$schemes) {

		foreach my $scheme_id (@$schemes) {
			next if $options->{'isolate_display'} && !$self->{'prefs'}->{'isolate_display_schemes'}->{$scheme_id};
			next if $options->{'analysis_pref'}   && !$self->{'prefs'}->{'analysis_schemes'}->{$scheme_id};
			my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
			my $scheme_loci_buffer;
			$scheme_info->{'name'} =~ s/&/\&amp;/gx;
			my $page = $self->{'cgi'}->param('page');
			$page = 'info' if any { $page eq $_ } qw (isolateDelete isolateUpdate alleleUpdate);
			if ( defined $isolate_id ) {

				if ( $self->_scheme_data_present( $scheme_id, $isolate_id ) ) {
					$buffer .=
					  $options->{'no_link_out'}
					  ? qq(<li><a>$scheme_info->{'name'}</a>)
					  : qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
					  . qq(page=$page&amp;id=$isolate_id&amp;scheme_id=$scheme_info->{'id'}" rel="nofollow" )
					  . qq(data-rel="ajax">$scheme_info->{'name'}</a>);
					$buffer .= $scheme_loci_buffer if $scheme_loci_buffer;
					$buffer .= qq(</li>\n);
				}
			} else {
				if ( $options->{'no_link_out'} ) {
					my $id = $options->{'select_schemes'} ? qq( id="s_$scheme_id") : q();
					$buffer .= qq(<li$id><a>$scheme_info->{'name'}</a>);
				} else {
					$buffer .=
					    qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
					  . qq(page=$page&amp;scheme_id=$scheme_info->{'id'}" rel="nofollow" data-rel="ajax">)
					  . qq($scheme_info->{'name'}</a>);
				}
				$buffer .= $scheme_loci_buffer if $scheme_loci_buffer;
				$buffer .= qq(</li>\n);
			}
		}
	}
	return qq(<ul>$buffer</ul>\n) if $buffer;
	return;
}

sub _get_child_groups {
	my ( $self, $group_id, $isolate_id, $level, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $buffer;
	my $child_groups = $self->{'datastore'}->run_query(
		'SELECT id FROM scheme_groups LEFT JOIN scheme_group_group_members ON '
		  . 'scheme_groups.id=group_id WHERE parent_group_id=? ORDER BY display_order,name',
		$group_id,
		{ fetch => 'col_arrayref' }
	);
	if (@$child_groups) {
		foreach my $group_id (@$child_groups) {
			my $group_info = $self->{'datastore'}->get_scheme_group_info($group_id);
			my $new_level  = $level;
			last if $new_level == 10;    #prevent runaway if child is set as the parent of a parental group
			my $group_scheme_buffer = $self->_get_group_schemes( $group_id, $isolate_id, $options );
			my $child_group_buffer = $self->_get_child_groups( $group_id, $isolate_id, ++$new_level, $options );
			if ( $group_scheme_buffer || $child_group_buffer ) {
				my $page = $self->{'cgi'}->param('page');
				$page = 'info' if any { $page eq $_ } qw (isolateDelete isolateUpdate alleleUpdate);
				if ( defined $isolate_id ) {
					$buffer .=
					  $options->{'no_link_out'}
					  ? qq(<li><a>$group_info->{'name'}</a>\n)
					  : qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
					  . qq(page=$page&amp;id=$isolate_id&amp;group_id=$group_id" rel="nofollow" data-rel="ajax">)
					  . qq($group_info->{'name'}</a>\n);
				} else {
					$buffer .=
					  $options->{'no_link_out'}
					  ? qq(<li><a>$group_info->{'name'}</a>\n)
					  : qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
					  . qq(page=$page&amp;group_id=$group_id" rel="nofollow" data-rel="ajax">)
					  . qq($group_info->{'name'}</a>\n);
				}
				$buffer .= $group_scheme_buffer if $group_scheme_buffer;
				$buffer .= $child_group_buffer  if $child_group_buffer;
				$buffer .= q(</li>);
			}
		}
	}
	return qq(<ul>\n$buffer</ul>\n) if $buffer;
	return;
}

sub _scheme_data_present {
	my ( $self, $scheme_id, $isolate_id ) = @_;
	my $designations_present = $self->{'datastore'}->run_query(
		    q[SELECT EXISTS(SELECT * FROM allele_designations LEFT JOIN scheme_members ON ]
		  . q[allele_designations.locus=scheme_members.locus WHERE isolate_id=? AND ]
		  . q[scheme_id=? AND allele_id !='0')],
		[ $isolate_id, $scheme_id ],
		{ cache => 'TreeViewPage::scheme_data_present::allele_designations' }
	);
	return 1 if $designations_present;
	my $sequences_present = $self->{'datastore'}->run_query(
		'SELECT EXISTS(SELECT * FROM allele_sequences LEFT JOIN scheme_members ON '
		  . 'allele_sequences.locus=scheme_members.locus WHERE isolate_id=? AND scheme_id=?)',
		[ $isolate_id, $scheme_id ],
		{ cache => 'TreeViewPage::scheme_data_present::allele_sequences' }
	);
	return 1 if $sequences_present;
	return;
}

sub _data_not_in_scheme_present {
	my ( $self, $isolate_id ) = @_;
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? 'SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT '
	  . "scheme_id FROM set_schemes WHERE set_id=$set_id)"
	  : 'SELECT locus FROM scheme_members';
	my $designations =
	  $self->{'datastore'}
	  ->run_query( "SELECT EXISTS(SELECT * FROM allele_designations WHERE isolate_id=? AND locus NOT IN ($set_clause))",
		$isolate_id );
	return 1 if $designations;
	my $sequences =
	  $self->{'datastore'}
	  ->run_query( "SELECT EXISTS(SELECT * FROM allele_sequences WHERE isolate_id=? AND locus NOT IN ($set_clause))",
		$isolate_id );
	return $sequences ? 1 : 0;
}
1;
