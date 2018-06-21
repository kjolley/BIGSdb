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
package BIGSdb::CurateIndexPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage BIGSdb::IndexPage BIGSdb::SubmitPage);
use Error qw(:try);
use List::MoreUtils qw(uniq none);
use BIGSdb::Constants qw(:interface);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery noCache packery tooltips);
	$self->choose_set;
	$self->{'system'}->{'only_sets'} = 'no' if $self->is_admin;
	my $guid = $self->get_guid;
	try {
		$self->{'prefs'}->{'all_curator_methods'} =
		  ( $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, 'all_curator_methods' ) // '' )
		  eq 'on' ? 1 : 0;
		$self->{'prefs'}->{'all_admin_methods'} =
		  ( $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, 'all_admin_methods' ) // '' ) eq
		  'on' ? 1 : 0;
	}
	catch BIGSdb::DatabaseNoRecordException with {
		$self->{'prefs'}->{'all_curator_methods'} = 0;
		$self->{'prefs'}->{'all_admin_methods'}   = 0;
	};
	$self->{'optional_curator_display'} = $self->{'prefs'}->{'all_curator_methods'} ? 'inline' : 'none';
	$self->{'optional_admin_display'}   = $self->{'prefs'}->{'all_admin_methods'}   ? 'inline' : 'none';
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $buffer = << "END";
\$(function () {
	\$( "#show_closed" ).click(function() {
		if (\$("span#show_closed_text").css('display') == 'none'){
			\$("span#show_closed_text").css('display', 'inline');
			\$("span#hide_closed_text").css('display', 'none');
		} else {
			\$("span#show_closed_text").css('display', 'none');
			\$("span#hide_closed_text").css('display', 'inline');
		}
		\$( "#closed" ).toggle( 'blind', {} , 500 );
		return false;
	});
	\$('a#toggle_notifications').click(function(event){		
		event.preventDefault();
  		\$(this).attr('href', function(){  		
	  		\$.ajax({
	  			url: this.href,
	  			cache: false,
	  			success: function () {
	  				if (\$('span#notify_text').text() == 'ON'){
	  					\$('span#notify_text').text('OFF');
	  				} else {
	  					\$('span#notify_text').text('ON');
	  				}
	  			}
	  		});
	   	});
	});
	\$('a#toggle_all_curator_methods').click(function(event){		
		event.preventDefault();
  		\$(this).attr('href', function(){  
  			\$('#all_curator_methods_off').toggle();	
	  		\$('#all_curator_methods_on').toggle();
	  		\$('.default_hide_curator').fadeToggle(200,'',function(){
	  			\$('#curator_grid').packery();
	  		});	
	  		\$.ajax({
	  			url: this.href,
	  			cache: false,
	  		});
	   	});
	});
	\$('a#toggle_all_admin_methods').click(function(event){		
		event.preventDefault();
  		\$(this).attr('href', function(){  
  			\$('#all_admin_methods_off').toggle();	
	  		\$('#all_admin_methods_on').toggle();
	  		\$('.default_hide_admin').fadeToggle(200,'',function(){
	  			\$('#admin_grid').packery();
	  		});	
	  		\$.ajax({
	  			url: this.href,
	  			cache: false,
	  		});
	   	});
	});
	var \$grid = \$(".grid").packery({
       	itemSelector: '.grid-item',
  		gutter: 5,
    });        
    \$(window).resize(function() {
    	delay(function(){
     			\$grid.packery();
    	}, 1000);
 	});
});
var delay = (function(){
  var timer = 0;
  return function(callback, ms){
    clearTimeout (timer);
    timer = setTimeout(callback, ms);
  };
})();	
END
	return $buffer;
}

sub _toggle_notifications {
	my ($self) = @_;
	return if !$self->{'username'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $new_status = $user_info->{'submission_emails'} ? 0 : 1;
	eval {
		$self->{'db'}
		  ->do( 'UPDATE users SET submission_emails=? WHERE user_name=?', undef, $new_status, $self->{'username'} );
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub _toggle_all_curator_methods {
	my ($self) = @_;
	my $new_value = $self->{'prefs'}->{'all_curator_methods'} ? 'off' : 'on';
	my $guid = $self->get_guid;
	try {
		$self->{'prefstore'}->set_general( $guid, $self->{'system'}->{'db'}, 'all_curator_methods', $new_value );
	}
	catch BIGSdb::DatabaseNoRecordException with {
		$logger->error('Cannot toggle show all curator methods');
	};
	return;
}

sub _toggle_all_admin_methods {
	my ($self) = @_;
	my $new_value = $self->{'prefs'}->{'all_admin_methods'} ? 'off' : 'on';
	my $guid = $self->get_guid;
	try {
		$self->{'prefstore'}->set_general( $guid, $self->{'system'}->{'db'}, 'all_admin_methods', $new_value );
	}
	catch BIGSdb::DatabaseNoRecordException with {
		$logger->error('Cannot toggle show all admin methods');
	};
	return;
}

sub _ajax_call {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('toggle_notifications') ) {
		$self->_toggle_notifications;
		return 1;
	}
	if ( $q->param('toggle_all_curator_methods') ) {
		$self->_toggle_all_curator_methods;
		return 1;
	}
	if ( $q->param('toggle_all_admin_methods') ) {
		$self->_toggle_all_admin_methods;
		return 1;
	}
	return;
}

sub _print_set_section {
	my ($self) = @_;
	if ( ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ) {
		$self->print_set_section;
	}
	return;
}

#Append to URLs to ensure unique caching.
sub _get_set_string {
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	my $set_string = $set_id ? qq(&amp;set_id=$set_id) : q();
	return $set_string;
}

sub _get_standard_links {
	my ($self) = @_;
	my $buffer = $self->_get_user_fields;
	return $buffer;
}

sub _get_seqdef_links {
	my ($self) = @_;
	my $buffer = $self->_get_locus_description_fields;
	$buffer .= $self->_get_sequence_fields;
	$buffer .= $self->_get_profile_fields;
	return $buffer;
}

sub _get_isolate_links {
	my ($self) = @_;
	my $buffer;
	$buffer .= $self->_get_isolate_fields;
	$buffer .= $self->_get_isolate_field_extended_attribute_field;
	$buffer .= $self->_get_projects;
	$buffer .= $self->_get_allele_designations;
	$buffer .= $self->_get_sequence_bin;
	$buffer .= $self->_get_allele_sequences;
	$buffer .= $self->_get_experiments;
	$buffer .= $self->_get_samples;
	return $buffer;
}

sub _get_admin_links {
	my ($self) = @_;
	my $buffer = q();
	$buffer .= $self->_get_permissions;
	$buffer .= $self->_get_user_passwords;
	$buffer .= $self->_get_config_check;
	$buffer .= $self->_get_cache_refresh;
	$buffer .= $self->_get_user_dbases;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$buffer .= $self->_get_isolate_field_extended_attributes;
		$buffer .= $self->_get_composite_fields;
		$buffer .= $self->_get_oauth_credentials;
	}

	#Only modify schemes/loci etc. when sets not selected.
	my $set_id = $self->get_set_id;
	return $buffer if $set_id;
	$buffer .= $self->_get_loci;

	#locus_aliases
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$buffer .= $self->_get_genome_filtering;
		$buffer .= $self->_get_sequence_attributes;
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		$buffer .= $self->_get_locus_extended_attributes;
	}
	$buffer .= $self->_get_schemes;
	$buffer .= $self->_get_scheme_groups;
	$buffer .= $self->_get_classification_schemes;
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		$buffer .= $self->_get_client_dbases;
		$buffer .= $self->_get_locus_curators;
		$buffer .= $self->_get_scheme_curators;
	}
	$buffer .= $self->_get_sets;
	return $buffer;
}

sub _get_user_fields {
	my ($self) = @_;
	my $buffer = q();
	my $import;
	if ( ( $self->{'permissions'}->{'import_site_users'} || $self->is_admin )
		&& $self->{'datastore'}->user_dbs_defined )
	{
		$import = 1;
	}
	my $modify_users = $self->can_modify_table('users');
	if ( $modify_users || $import ) {
		my $import_url = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=importUser);
		$buffer .= q(<div class="curategroup curategroup_users grid-item default_show_curator"><h2>Users</h2>);
		$buffer .= $self->_get_icon_group(
			'users', 'user',
			{
				add          => $modify_users,
				batch_add    => $modify_users,
				query        => $modify_users,
				import       => $import,
				import_url   => $import_url,
				import_label => 'Import user account from centralized user database'
			}
		);
		$buffer .= qq(</div>\n);
	}
	if ( $self->can_modify_table('user_groups') ) {
		$buffer .= q(<div class="curategroup curategroup_users grid-item default_hide_curator" )
		  . qq(style="display:$self->{'optional_curator_display'}"><h2>User groups</h2>);
		$buffer .= $self->_get_icon_group(
			'user_groups',
			'users',
			{
				add       => 1,
				batch_add => 1,
				query     => 1,
				info => 'User groups - Users can be members of user groups to facilitate setting access permissions.',
			}
		);
		$buffer .= qq(</div>\n);
	}
	if ( $self->can_modify_table('user_group_members') ) {
		$buffer .= q(<div class="curategroup curategroup_users grid-item default_hide_curator" )
		  . qq(style="display:$self->{'optional_curator_display'}"><h2>User group members</h2>);
		$buffer .= $self->_get_icon_group(
			'user_group_members',
			'user-friends',
			{
				add       => 1,
				batch_add => 1,
				query     => 1,
				info      => 'User group members - Add users to user groups to facilitate setting access permissions.'
			}
		);
		$buffer .= qq(</div>\n);
	}
	if ( ( $self->{'permissions'}->{'import_site_users'} || $self->is_admin )
		&& $self->{'datastore'}->user_dbs_defined )
	{
	}
	return $buffer;
}

sub _get_locus_description_fields {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('locus_descriptions');
	if ( !$self->is_admin ) {
		my $allowed =
		  $self->{'datastore'}
		  ->run_query( 'SELECT EXISTS(SELECT * FROM locus_curators WHERE curator_id=?)', $self->get_curator_id );
		return $buffer if !$allowed;
	}
	$buffer .= q(<div class="curategroup curategroup_locus_descriptions grid-item default_hide_curator" )
	  . qq(style="display:$self->{'optional_curator_display'}"><h2>Locus descriptions</h2>);
	$buffer .= $self->_get_icon_group(
		'locus_descriptions',
		'clipboard',
		{
			add       => 1,
			batch_add => 1,
			query     => 1
		}
	);
	$buffer .= qq(</div>\n);
	$buffer .= q(<div class="curategroup curategroup_locus_descriptions grid-item default_hide_curator" )
	  . qq(style="display:$self->{'optional_curator_display'}"><h2>Locus links</h2>);
	$buffer .= $self->_get_icon_group(
		'locus_links',
		'link',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Locus links - Hyperlinks to further information on the internet about a locus.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_sequence_fields {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('sequences');
	my $set_string = $self->_get_set_string;
	my $fasta_url  = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddFasta$set_string);
	$buffer .= q(<div class="curategroup curategroup_sequences grid-item default_show_curator"><h2>Sequences</h2>);
	$buffer .= $self->_get_icon_group(
		'sequences',
		'dna',
		{
			add         => 1,
			batch_add   => 1,
			query       => 1,
			fasta       => 1,
			fasta_url   => $fasta_url,
			fasta_label => 'Upload new sequences using a FASTA file containing new variants of a single locus.'
		}
	);
	$buffer .= qq(</div>\n);
	$buffer .= q(<div class="curategroup curategroup_sequences grid-item default_hide_curator" )
	  . qq(style="display:$self->{'optional_curator_display'}"><h2>Retired alleles</h2>);
	$buffer .= $self->_get_icon_group(
		'retired_allele_ids',
		'trash-alt',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Retired alleles - Alleles ids defined here will be prevented from being reused.'
		}
	);
	$buffer .= qq(</div>\n);
	$buffer .= q(<div class="curategroup curategroup_sequences grid-item default_hide_curator" )
	  . qq(style="display:$self->{'optional_curator_display'}"><h2>Allele accessions</h2>);
	$buffer .= $self->_get_icon_group(
		'accession',
		'external-link-alt',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Allele accessions - Associate sequences with Genbank/ENA accessions numbers.'
		}
	);
	$buffer .= qq(</div>\n);
	$buffer .= q(<div class="curategroup curategroup_sequences grid-item default_hide_curator" )
	  . qq(style="display:$self->{'optional_curator_display'}"><h2>Allele publications</h2>);
	$buffer .= $self->_get_icon_group(
		'sequence_refs',
		'book-open',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Allele references - Associate sequences with publications using PubMed id.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_profile_fields {
	my ($self) = @_;
	my $schemes;
	my $set_id = $self->get_set_id;
	if ( $self->is_admin ) {
		$schemes = $self->{'datastore'}->run_query(
			'SELECT DISTINCT id FROM schemes RIGHT JOIN scheme_members ON schemes.id=scheme_members.scheme_id '
			  . 'JOIN scheme_fields ON schemes.id=scheme_fields.scheme_id WHERE primary_key',
			undef,
			{ fetch => 'col_arrayref' }
		);
	} else {
		$schemes = $self->{'datastore'}->run_query(
			'SELECT scheme_id FROM scheme_curators WHERE curator_id=? AND '
			  . 'scheme_id IN (SELECT scheme_id FROM scheme_fields WHERE primary_key)',
			$self->get_curator_id,
			{ fetch => 'col_arrayref' }
		);
	}
	my $buffer = q();
	my %desc;
	foreach my $scheme_id (@$schemes)
	{    #Can only order schemes after retrieval since some can be renamed by set membership
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
		$desc{$scheme_id} = $scheme_info->{'name'};
	}
	my $curator_id = $self->get_curator_id;
	foreach my $scheme_id ( sort { $desc{$a} cmp $desc{$b} } @$schemes ) {
		next if $set_id && !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id );
		my $class   = q(default_show_curator);
		my $display = q();
		if ( !$self->{'datastore'}->is_scheme_curator( $scheme_id, $curator_id ) ) {
			$class   = q(default_hide_curator);
			$display = qq(style="display:$self->{'optional_curator_display'}");
		}
		$desc{$scheme_id} =~ s/\&/\&amp;/gx;
		$buffer .=
		    qq(<div class="curategroup curategroup_profiles grid-item $class" )
		  . qq($display><h2>$desc{$scheme_id} profiles</h2>);
		$buffer .= $self->_get_icon_group(
			undef, 'table',
			{
				add     => 1,
				add_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=profileAdd&amp;scheme_id=$scheme_id),
				batch_add     => 1,
				batch_add_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=profileBatchAdd&amp;scheme_id=$scheme_id),
				query     => 1,
				query_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=query&amp;scheme_id=$scheme_id),
				batch_update     => 1,
				batch_update_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=batchProfileUpdate&amp;scheme_id=$scheme_id)
			}
		);
		$buffer .= qq(</div>\n);
	}
	if ($buffer) {
		$buffer .= q(<div class="curategroup curategroup_profiles grid-item default_hide_curator" )
		  . qq(style="display:$self->{'optional_curator_display'}"><h2>Profile publications</h2>);
		$buffer .= $self->_get_icon_group(
			'profile_refs',
			'book-open',
			{
				add       => 1,
				batch_add => 1,
				query     => 1,
				info      => 'Profile references - Associate allelic profiles with publications using PubMed id.'
			}
		);
		$buffer .= qq(</div>\n);
		$buffer .= q(<div class="curategroup curategroup_profiles grid-item default_hide_curator" )
		  . qq(style="display:$self->{'optional_curator_display'}"><h2>Retired profiles</h2>);
		$buffer .= $self->_get_icon_group(
			'retired_profiles',
			'trash-alt',
			{
				add       => 1,
				batch_add => 1,
				query     => 1,
				info      => 'Retired profiles - Profile ids defined here will be prevented from being reused.'
			}
		);
		$buffer .= qq(</div>\n);
	}
	return $buffer;
}

sub _get_isolate_fields {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('isolates');
	my $exists  = $self->_isolates_exist;
	my $add_url = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=isolateAdd);
	my $batch_add_url =
	  qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=isolates);
	my $query_url        = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query);
	my $batch_update_url = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchIsolateUpdate);
	$buffer .= q(<div class="curategroup curategroup_isolates grid-item default_show_curator"><h2>Isolates</h2>);
	$buffer .= $self->_get_icon_group(
		'isolates',
		'file-alt',
		{
			add => $self->{'permissions'}->{'only_private'} ? 0 : 1,
			add_url          => $add_url,
			batch_add        => 1,
			batch_add_url    => $batch_add_url,
			query            => $exists,
			query_url        => $query_url,
			batch_update     => $exists,
			batch_update_url => $batch_update_url
		}
	);
	$buffer .= qq(</div>\n);

	if ($exists) {
		$buffer .= q(<div class="curategroup curategroup_isolates grid-item default_hide_curator" )
		  . qq(style="display:$self->{'optional_curator_display'}"><h2>Isolate aliases</h2>);
		$buffer .= $self->_get_icon_group(
			'isolate_aliases',
			'list-ul',
			{
				add       => 1,
				batch_add => 1,
				query     => 1,
				info      => 'Isolate aliases - Alternative names for isolates.'
			}
		);
		$buffer .= qq(</div>\n);
		$buffer .= q(<div class="curategroup curategroup_isolates grid-item default_hide_curator" )
		  . qq(style="display:$self->{'optional_curator_display'}"><h2>Publications</h2>);
		$buffer .= $self->_get_icon_group(
			'refs',
			'book-open',
			{
				add       => 1,
				batch_add => 1,
				query     => 1,
				info      => 'Publications - Associate isolates with publications using PubMed id.'
			}
		);
		$buffer .= qq(</div>\n);
	}
	$buffer .= q(<div class="curategroup curategroup_isolates grid-item default_hide_curator" )
	  . qq(style="display:$self->{'optional_curator_display'}"><h2>Retired isolates</h2>);
	$buffer .= $self->_get_icon_group(
		'retired_isolates',
		'trash-alt',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Retired isolates - Isolate ids defined here will not be reused.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_isolate_field_extended_attribute_field {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('isolate_value_extended_attributes');
	my $count = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM isolate_field_extended_attributes)');
	return $buffer if !$count;
	$buffer .= q(<div class="curategroup curategroup_isolates grid-item default_hide_curator" )
	  . qq(style="display:$self->{'optional_curator_display'}"><h2>Extended attributes</h2>);
	$buffer .= $self->_get_icon_group(
		'isolate_value_extended_attributes',
		'expand-arrows-alt',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Extended attributes - Data linked to isolate record field values.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_projects {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('projects');
	$buffer .= q(<div class="curategroup curategroup_projects grid-item default_hide_curator" )
	  . qq(style="display:$self->{'optional_curator_display'}"><h2>Projects</h2>);
	$buffer .= $self->_get_icon_group(
		'projects',
		'list-alt',
		{
			fa_class  => 'far',
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Projects - Group isolate records.'
		}
	);
	$buffer .= qq(</div>\n);
	my $projects = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM projects)');
	return $buffer if !$projects;
	return $buffer if !$self->_isolates_exist;
	$buffer .= q(<div class="curategroup curategroup_projects grid-item default_hide_curator" )
	  . qq(style="display:$self->{'optional_curator_display'}"><h2>Project members</h2>);
	$buffer .= $self->_get_icon_group(
		'project_members',
		'object-group',
		{
			fa_class  => 'far',
			add       => 1,
			batch_add => 1,
			query     => 1,
			info => 'Project members - Isolates belonging to projects. Isolates can belong to any number of projects.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_allele_designations {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('allele_designations');
	return $buffer if !$self->_isolates_exist;
	$buffer .= q(<div class="curategroup curategroup_designations grid-item default_hide_curator" )
	  . qq(style="display:$self->{'optional_curator_display'}"><h2>Allele designations</h2>);
	$buffer .= $self->_get_icon_group(
		'allele_designations',
		'table',
		{
			batch_add => 1,
			query     => 1,
			info =>
			  'Allele designations - Update individual allele designations from within the isolate update function.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_sequence_bin {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('sequence_bin');
	return $buffer if !$self->_isolates_exist;
	$buffer .=
	  q(<div class="curategroup curategroup_designations grid-item default_show_curator"><h2>Sequence bin</h2>);
	$buffer .= $self->_get_icon_group(
		'sequence_bin',
		'dna',
		{
			add     => 1,
			add_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=addSeqbin),
			batch_add     => 1,
			batch_add_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSeqbin),
			query         => 1,
			link          => ( $self->{'system'}->{'remote_contigs'} // q() ) eq 'yes' ? 1 : 0,
			link_url   => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddRemoteContigs),
			link_label => 'Link contigs stored in remote isolate database',
			info       => 'Sequence bin - The sequence bin for an isolate can contain sequences from any source, '
			  . 'but usually consists of genome assembly contigs.'
		}
	);
	$buffer .= qq(</div>\n);
	my $seqbin = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT id FROM sequence_bin)');
	return $buffer if !$seqbin;
	$buffer .= q(<div class="curategroup curategroup_designations grid-item default_hide_curator" )
	  . qq(style="display:$self->{'optional_curator_display'}"><h2>Sequence accessions</h2>);
	$buffer .= $self->_get_icon_group(
		'accession',
		'external-link-alt',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Accessions - Associate individual contigs in the '
			  . 'sequence bin with Genbank/ENA accessions numbers.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_allele_sequences {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('allele_sequences');
	return $buffer if !$self->_isolates_exist;
	my $seqbin = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT id FROM sequence_bin)');
	return $buffer if !$seqbin;
	$buffer .=
	  q(<div class="curategroup curategroup_designations grid-item default_show_curator"><h2>Sequence tags</h2>);
	$buffer .= $self->_get_icon_group(
		'allele_sequences',
		'tags',
		{
			query    => 1,
			scan     => 1,
			scan_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tagScan),
			info     => 'Sequence tags - Scan genomes to identify locus regions, '
			  . 'then tag these positions and allele designations.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_experiments {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('experiments');
	$buffer .= q(<div class="curategroup curategroup_experiments grid-item default_hide_curator" )
	  . qq(style="display:$self->{'optional_curator_display'}"><h2>Experiments</h2>);
	$buffer .= $self->_get_icon_group(
		'experiments',
		'flask',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Experiments - Set up experiments to group contigs in the sequence bin.'
		}
	);
	$buffer .= qq(</div>\n);
	my $experiments = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT id FROM experiments)');
	return $buffer if !$experiments;
	$buffer .= q(<div class="curategroup curategroup_experiments grid-item default_hide_curator" )
	  . qq(style="display:$self->{'optional_curator_display'}"><h2>Experiment contigs</h2>);
	$buffer .= $self->_get_icon_group(
		'experiment_sequences',
		'object-group',
		{
			fa_class  => 'far',
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Experiment contigs - Group contigs by experiment.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_samples {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('samples');
	my $sample_fields = $self->{'xmlHandler'}->get_sample_field_list;
	return $buffer if !@$sample_fields;
	return $buffer if !$self->_isolates_exist;
	$buffer .= q(<div class="curategroup curategroup_samples grid-item default_show_curator"><h2>Samples</h2>);
	$buffer .= $self->_get_icon_group(
		'samples',
		'vial',
		{
			batch_add => 1,
			query     => 1,
			info      => 'Sample storage records - These can also be added and updated from the isolate update page.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_permissions {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('permissions');
	$buffer .= q(<div class="curategroup curategroup_permissions grid-item default_show_admin"><h2>Permissions</h2>);
	$buffer .= $self->_get_icon_group(
		'permissions',
		'user-shield',
		{
			query     => 1,
			query_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=curatorPermissions),
			info      => q(Permissions - Set curator permissions for individual users - )
			  . q(these are only active for users with a status of 'curator' in the users table.)
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_user_dbases {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('user_dbases');
	$buffer .= q(<div class="curategroup curategroup_remote_dbases grid-item default_hide_admin" )
	  . qq(style="display:$self->{'optional_admin_display'}"><h2>User databases</h2>);
	$buffer .= $self->_get_icon_group(
		'user_dbases',
		'database',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'User databases - Add global databases containing site-wide user data - '
			  . 'these can be used to set up accounts that work across databases.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_oauth_credentials {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if ( $self->{'system'}->{'remote_contigs'} // q() ) ne 'yes';
	return $buffer if !$self->can_modify_table('oauth_credentials');
	$buffer .= q(<div class="curategroup curategroup_remote_dbases grid-item default_hide_admin" )
	  . qq(style="display:$self->{'optional_admin_display'}"><h2>OAuth credentials</h2>);
	$buffer .= $self->_get_icon_group(
		'oauth_credentials',
		'unlock-alt',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info => 'OAuth credentials - OAuth credentials for accessing contigs stored in remote BIGSdb databases.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_genome_filtering {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->{'permissions'}->{'modify_probes'} && !$self->is_admin;
	$buffer .= q(<div class="curategroup curategroup_loci grid-item default_hide_admin" )
	  . qq(style="display:$self->{'optional_admin_display'}"><h2>PCR reactions</h2>);
	$buffer .= $self->_get_icon_group(
		'pcr', 'vial',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'PCR reactions - Set up <i>in silico</i> PCR reactions. '
			  . 'These can be used to filter genomes for tagging to specific repetitive loci.'
		}
	);
	$buffer .= qq(</div>\n);
	if ( $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM pcr)') && $self->_loci_exist ) {
		$buffer .= q(<div class="curategroup curategroup_loci grid-item default_hide_admin" )
		  . qq(style="display:$self->{'optional_admin_display'}"><h2>PCR locus links</h2>);
		$buffer .= $self->_get_icon_group(
			'pcr_locus',
			'stream',
			{
				add       => 1,
				batch_add => 1,
				query     => 1,
				info      => 'Link a locus definition to an <i>in silico</i> PCR reaction. '
				  . 'For the locus to be matched, the region of DNA must be predicted to fall '
				  . 'within the PCR amplification product.'
			}
		);
		$buffer .= qq(</div>\n);
	}
	$buffer .= q(<div class="curategroup curategroup_loci grid-item default_hide_admin" )
	  . qq(style="display:$self->{'optional_admin_display'}"><h2>Nucleotide probes</h2>);
	$buffer .= $self->_get_icon_group(
		'probes', 'vial',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Nucleotide probes - Define nucleotide probes for <i>in silico</i> hybridization '
			  . 'reaction to filter genomes for tagging to specific repetitive loci.'
		}
	);
	$buffer .= qq(</div>\n);
	if ( $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM probes)') && $self->_loci_exist ) {
		$buffer .= q(<div class="curategroup curategroup_loci grid-item default_hide_admin" )
		  . qq(style="display:$self->{'optional_admin_display'}"><h2>Probe locus links</h2>);
		$buffer .= $self->_get_icon_group(
			'probe_locus',
			'stream',
			{
				add       => 1,
				batch_add => 1,
				query     => 1,
				info      => 'Link a locus to an <i>in silico</i> hybridization reaction. '
				  . 'For the locus to be matched, the region of DNA must be predicted to lie '
				  . 'within a specified distance of the probe sequence in the genome.'
			}
		);
		$buffer .= qq(</div>\n);
	}
	return $buffer;
}

sub _get_sequence_attributes {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('sequence_attributes');
	$buffer .= q(<div class="curategroup curategroup_designations grid-item default_hide_admin" )
	  . qq(style="display:$self->{'optional_admin_display'}"><h2>Sequence attributes</h2>);
	$buffer .= $self->_get_icon_group(
		'sequence_attributes',
		'code',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_locus_extended_attributes {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('locus_extended_attributes');
	return $buffer if !$self->_loci_exist;
	$buffer .= q(<div class="curategroup curategroup_loci grid-item default_hide_admin" )
	  . qq(style="display:$self->{'optional_admin_display'}"><h2>Locus extended attributes</h2>);
	$buffer .= $self->_get_icon_group(
		'locus_extended_attributes',
		'expand-arrows-alt',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_client_dbases {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('client_dbases');
	$buffer .= q(<div class="curategroup curategroup_remote_dbases grid-item default_hide_admin" )
	  . qq(style="display:$self->{'optional_admin_display'}"><h2>Client databases</h2>);
	$buffer .= $self->_get_icon_group(
		'client_dbases',
		'coins',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info => 'Client databases - Define isolate databases that use locus allele or scheme profile definitions '
			  . 'defined in this database - this enables backlinks and searches of these databases when you query '
			  . 'sequences or profiles in this database.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer if !$self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM client_dbases)');
	if ( $self->_loci_exist ) {
		$buffer .= q(<div class="curategroup curategroup_remote_dbases grid-item default_hide_admin" )
		  . qq(style="display:$self->{'optional_admin_display'}"><h2>Client database loci</h2>);
		$buffer .= $self->_get_icon_group(
			'client_dbase_loci',
			'sliders-h',
			{
				add       => 1,
				batch_add => 1,
				query     => 1,
				info      => 'Client database loci - Define loci that are used in client databases.'
			}
		);
		$buffer .= qq(</div>\n);
		$buffer .= q(<div class="curategroup curategroup_remote_dbases grid-item default_hide_admin" )
		  . qq(style="display:$self->{'optional_admin_display'}"><h2>Client database fields</h2>);
		$buffer .= $self->_get_icon_group(
			'client_dbase_loci_fields',
			'th-list',
			{
				add       => 1,
				batch_add => 1,
				query     => 1,
				info      => 'Client database fields linked to loci - Define fields in client database whose value '
				  . 'can be displayed when isolate has matching allele.'
			}
		);
		$buffer .= qq(</div>\n);
	}
	if ( $self->_schemes_exist ) {
		$buffer .= q(<div class="curategroup curategroup_remote_dbases grid-item default_hide_admin" )
		  . qq(style="display:$self->{'optional_admin_display'}"><h2>Client database schemes</h2>);
		$buffer .= $self->_get_icon_group(
			'client_dbase_schemes',
			'table',
			{
				add       => 1,
				batch_add => 1,
				query     => 1,
				info      => 'Client database scheme - Define schemes that are used in client databases. '
				  . 'You will also need to add the appropriate loci to the client database loci table.'
			}
		);
		$buffer .= qq(</div>\n);
	}
	return $buffer;
}

sub _get_locus_curators {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('locus_curators');
	$buffer .= q(<div class="curategroup curategroup_users grid-item default_show_admin"><h2>Locus curators</h2>);
	$buffer .= $self->_get_icon_group(
		'locus_curators',
		'user-tie',
		{
			add              => 1,
			batch_add        => 1,
			query            => 1,
			batch_update     => 1,
			batch_update_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . q(page=memberUpdate&amp;table=locus_curators),
			info => 'Locus curators - Define which curators can add or update sequences for particular loci.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_scheme_curators {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('scheme_curators');
	$buffer .= q(<div class="curategroup curategroup_users grid-item default_show_admin"><h2>Scheme curators</h2>);
	$buffer .= $self->_get_icon_group(
		'scheme_curators',
		'user-tie',
		{
			add              => 1,
			batch_add        => 1,
			query            => 1,
			batch_update     => 1,
			batch_update_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . q(page=memberUpdate&amp;table=scheme_curators),
			info => 'Scheme curators - Define which curators can add or update profiles for particular schemes.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_user_passwords {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if $self->{'system'}->{'authentication'} ne 'builtin';
	return $buffer if !$self->{'permissions'}->{'set_user_passwords'} && !$self->is_admin;
	$buffer .= q(<div class="curategroup curategroup_users grid-item default_show_admin"><h2>User passwords</h2>);
	$buffer .= $self->_get_icon_group(
		undef, 'key',
		{
			set       => 1,
			set_url   => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=setPassword),
			set_label => 'Set passwords',
			info      => 'Set user password - Set a user password to enable them to log on '
			  . 'or change an existing password.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_config_check {
	my ($self) = @_;
	my $buffer = q();
	return $buffer
	  if !$self->{'permissions'}->{'modify_loci'} && !$self->{'permissions'}->{'modify_schemes'} && !$self->is_admin;
	$buffer .= q(<div class="curategroup curategroup_maintenance grid-item default_show_admin">)
	  . q(<h2>Configuration check</h2>);
	$buffer .= $self->_get_icon_group(
		undef,
		'clipboard-check',
		{
			action     => 1,
			action_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=configCheck&amp;)
			  . q(show_probs_only=1),
			action_label => 'Check',
			info         => 'Configuration check - Checks database connectivity for loci and schemes and '
			  . 'that required helper applications are properly installed.'
		}
	);
	$buffer .= qq(</div>\n);
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		$buffer .= q(<div class="curategroup curategroup_maintenance grid-item default_show_admin">)
		  . q(<h2>Configuration repair</h2>);
		$buffer .= $self->_get_icon_group(
			undef, 'wrench',
			{
				action       => 1,
				action_url   => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=configRepair),
				action_label => 'Repair',
				info         => 'Configuration repair - Rebuild scheme tables'
			}
		);
		$buffer .= qq(</div>\n);
	}
	return $buffer;
}

sub _get_cache_refresh {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->is_admin || $self->{'system'}->{'dbtype'} ne 'isolates' || !$self->_cache_tables_exists;
	$buffer .=
	  q(<div class="curategroup curategroup_maintenance grid-item default_show_admin">) . q(<h2>Cache refresh</h2>);
	$buffer .= $self->_get_icon_group(
		undef,
		'sync-alt',
		{
			action       => 1,
			action_url   => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=refreshCache),
			action_label => 'Refresh',
			info         => 'Scheme caches - Update one or all scheme field caches.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_loci {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('loci');
	$buffer .= q(<div class="curategroup curategroup_loci grid-item default_hide_admin" )
	  . qq(style="display:$self->{'optional_admin_display'}"><h2>Loci</h2>);
	$buffer .= $self->_get_icon_group(
		'loci',
		'sliders-h',
		{
			add        => 1,
			batch_add  => 1,
			query      => 1,
			scan       => 1,
			scan_label => 'Databank scan',
			scan_url   => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=databankScan)
		}
	);
	$buffer .= qq(</div>\n);
	$buffer .= q(<div class="curategroup curategroup_loci grid-item default_hide_admin" )
	  . qq(style="display:$self->{'optional_admin_display'}"><h2>Locus aliases</h2>);
	$buffer .= $self->_get_icon_group(
		'locus_aliases',
		'list-ul',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Locus aliases - Alternative names for loci. These can also be set when you batch add loci.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_isolate_field_extended_attributes {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('isolate_field_extended_attributes');
	$buffer .= q(<div class="curategroup curategroup_isolates grid-item default_hide_admin" )
	  . qq(style="display:$self->{'optional_admin_display'}"><h2>Extended attribute fields</h2>);
	$buffer .= $self->_get_icon_group(
		'isolate_field_extended_attributes',
		'expand-arrows-alt',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Extended attribute fields - '
			  . 'Define additional attributes linked to a particular isolate record field.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_composite_fields {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('composite_fields');
	$buffer .= q(<div class="curategroup curategroup_isolates grid-item default_hide_admin" )
	  . qq(style="display:$self->{'optional_admin_display'}"><h2>Composite fields</h2>);
	$buffer .= $self->_get_icon_group(
		'composite_fields',
		'cubes',
		{
			add       => 1,
			query     => 1,
			query_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=compositeQuery),
			info      => 'Composite fields - '
			  . 'Consist of a combination of different isolate, loci or scheme fields.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_schemes {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('schemes');
	$buffer .= q(<div class="curategroup curategroup_schemes grid-item default_hide_admin" )
	  . qq(style="display:$self->{'optional_admin_display'}"><h2>Schemes</h2>);
	$buffer .= $self->_get_icon_group(
		'schemes',
		'table',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Schemes - Schemes consist of collections of loci, '
			  . 'optionally containing a primary key field, e.g. MLST'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer if !$self->_schemes_exist;
	$buffer .= q(<div class="curategroup curategroup_schemes grid-item default_hide_admin" )
	  . qq(style="display:$self->{'optional_admin_display'}"><h2>Scheme fields</h2>);
	$buffer .= $self->_get_icon_group(
		'scheme_fields',
		'th-list',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Scheme fields - Define which fields belong to a scheme'
		}
	);
	$buffer .= qq(</div>\n);

	if ( $self->_loci_exist ) {
		$buffer .= q(<div class="curategroup curategroup_schemes grid-item default_hide_admin" )
		  . qq(style="display:$self->{'optional_admin_display'}"><h2>Scheme members</h2>);
		$buffer .= $self->_get_icon_group(
			'scheme_members',
			'object-group',
			{
				fa_class  => 'far',
				add       => 1,
				batch_add => 1,
				query     => 1,
				info      => 'Scheme members - Define which loci belong to a scheme'
			}
		);
		$buffer .= qq(</div>\n);
	}
	return $buffer;
}

sub _get_scheme_groups {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('scheme_groups');
	$buffer .= q(<div class="curategroup curategroup_schemes grid-item default_hide_admin" )
	  . qq(style="display:$self->{'optional_admin_display'}"><h2>Scheme groups</h2>);
	$buffer .= $self->_get_icon_group(
		'scheme_groups',
		'sitemap',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Scheme groups - Define groups in to which schemes can belong - '
			  . 'groups can also belong to other groups to create a hierarchy.'
		}
	);
	$buffer .= qq(</div>\n);
	if ( $self->_schemes_exist ) {
		$buffer .= q(<div class="curategroup curategroup_schemes grid-item default_hide_admin" )
		  . qq(style="display:$self->{'optional_admin_display'}"><h2>Group members (schemes)</h2>);
		$buffer .= $self->_get_icon_group(
			'scheme_group_scheme_members',
			'object-group',
			{
				fa_class  => 'far',
				add       => 1,
				batch_add => 1,
				query     => 1,
				info      => 'Scheme group members - Define which schemes belong to a group.'
			}
		);
		$buffer .= qq(</div>\n);
	}
	if ( $self->_scheme_groups_exist ) {
		$buffer .= q(<div class="curategroup curategroup_schemes grid-item default_hide_admin" )
		  . qq(style="display:$self->{'optional_admin_display'}"><h2>Group members (groups)</h2>);
		$buffer .= $self->_get_icon_group(
			'scheme_group_group_members',
			'object-group',
			{
				fa_class  => 'far',
				add       => 1,
				batch_add => 1,
				query     => 1,
				info      => 'Scheme group members - Define which scheme groups belong to a parent group. '
				  . 'Use this to construct a hierarchy of schemes.'
			}
		);
		$buffer .= qq(</div>\n);
	}
	return $buffer;
}

sub _get_classification_schemes {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('classification_schemes');
	$buffer .= q(<div class="curategroup curategroup_schemes grid-item default_hide_admin" )
	  . qq(style="display:$self->{'optional_admin_display'}"><h2>Classification schemes</h2>);
	$buffer .= $self->_get_icon_group(
		'classification_schemes',
		'object-group',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Classification schemes - Set up for clustering '
			  . 'of scheme profiles at different locus difference thresholds.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_sets {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('sets');
	return $buffer if ( $self->{'system'}->{'sets'} // '' ) ne 'yes';
	$buffer .= q(<div class="curategroup curategroup_sets grid-item default_hide_admin" )
	  . qq(style="display:$self->{'optional_admin_display'}"><h2>Sets</h2>);
	$buffer .= $self->_get_icon_group(
		'sets', 'hands',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info => 'Sets - Describe a collection of loci and schemes that can be treated like a stand-alone database.'
		}
	);
	return $buffer if !$self->_sets_exist;
	$buffer .= qq(</div>\n);

	if ( $self->_loci_exist ) {
		$buffer .= q(<div class="curategroup curategroup_sets grid-item default_hide_admin" )
		  . qq(style="display:$self->{'optional_admin_display'}"><h2>Set loci</h2>);
		$buffer .= $self->_get_icon_group(
			'set_loci',
			'object-group',
			{
				fa_class  => 'far',
				add       => 1,
				batch_add => 1,
				query     => 1,
				info      => 'Set loci - Define loci belonging to a set.'
			}
		);
		$buffer .= qq(</div>\n);
	}
	if ( $self->_schemes_exist ) {
		$buffer .= q(<div class="curategroup curategroup_sets grid-item default_hide_admin" )
		  . qq(style="display:$self->{'optional_admin_display'}"><h2>Set schemes</h2>);
		$buffer .= $self->_get_icon_group(
			'set_schemes',
			'object-group',
			{
				fa_class  => 'far',
				add       => 1,
				batch_add => 1,
				query     => 1,
				info      => 'Set schemes - Define schemes belonging to a set.'
			}
		);
		$buffer .= qq(</div>\n);
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $metadata_list = $self->{'xmlHandler'}->get_metadata_list;
		if (@$metadata_list) {
			$buffer .= q(<div class="curategroup curategroup_sets grid-item default_hide_admin" )
			  . qq(style="display:$self->{'optional_admin_display'}"><h2>Set metadata</h2>);
			$buffer .= $self->_get_icon_group(
				'set_metadata',
				'object-group',
				{
					fa_class  => 'far',
					add       => 1,
					batch_add => 1,
					query     => 1,
					info      => 'Set metadata - Add metadata collection to sets.'
				}
			);
			$buffer .= qq(</div>\n);
		}
		if ( $self->{'system'}->{'views'} ) {
			$buffer .= q(<div class="curategroup curategroup_sets grid-item default_hide_admin" )
			  . qq(style="display:$self->{'optional_admin_display'}"><h2>Set views</h2>);
			$buffer .= $self->_get_icon_group(
				'set_view',
				'glasses',
				{
					add       => 1,
					batch_add => 1,
					query     => 1,
					info      => 'Set views - Set database views linked to sets.'
				}
			);
			$buffer .= qq(</div>\n);
		}
	}
	return $buffer;
}

sub _get_icon_group {
	my ( $self, $table, $icon, $options ) = @_;
	my $fa_class      = $options->{'fa_class'} // 'fas';
	my $set_string    = $self->_get_set_string;
	my $links         = 0;
	my $records_exist = $table ? $self->{'datastore'}->run_query("SELECT EXISTS(SELECT * FROM $table)") : 1;
	foreach my $value (qw(add batch_add link query import fasta batch_update scan set action)) {
		$links++ if $options->{$value};
	}
	$links-- if $options->{'query'} && !$records_exist;
	my $pos = 4.8 - BIGSdb::Utils::decimal_place( $links * 2.2 / 2, 1 );
	my $buffer = q(<span style="position:relative">);
	if ( $options->{'info'} ) {
		$buffer .= q(<span style="position:absolute;right:2em;bottom:6.5em">);
		$buffer .= qq(<a style="cursor:help" title="$options->{'info'}" class="tooltip">);
		$buffer .= q(<span class="curate_icon_highlight curate_icon_info fas fa-info-circle"></span>);
		$buffer .= qq(</a></span>\n);
	}
	$buffer .= qq(<span class="curate_icon fa-7x fa-fw $fa_class fa-$icon"></span>);
	if ( $options->{'add'} ) {
		my $url = $options->{'add_url'}
		  // qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;table=$table);
		$buffer .= qq(<span style="position:absolute;left:${pos}em;bottom:1em">);
		$buffer .= qq(<a href="$url$set_string" title="Add" class="curate_icon_link">);
		$buffer .= q(<span class="curate_icon_highlight curate_icon_plus fas fa-plus"></span>);
		$buffer .= qq(</a></span>\n);
		$pos += 2.2;
	}
	if ( $options->{'batch_add'} ) {
		my $url = $options->{'batch_add_url'}
		  // qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=$table);
		$buffer .= qq(<span style="position:absolute;left:${pos}em;bottom:1em">);
		$buffer .= qq(<a href="$url$set_string" title="Batch add" class="curate_icon_link">);
		$buffer .= q(<span class="curate_icon_highlight curate_icon_plus fas fa-plus" )
		  . qq(style="left:0.5em;bottom:-0.8em;font-size:1.5em"></span>\n);
		$buffer .= q(<span class="curate_icon_highlight curate_icon_plus fas fa-plus"></span>);
		$buffer .= qq(</a></span>\n);
		$pos += 2.2;
	}
	if ( $options->{'link'} ) {
		my $text = $options->{'link_label'} // 'Link';
		$buffer .= qq(<span style="position:absolute;left:${pos}em;bottom:1em">);
		$buffer .= qq(<a href="$options->{'link_url'}$set_string" title="$text" class="curate_icon_link">);
		$buffer .= q(<span class="curate_icon_highlight curate_icon_link_remote fas fa-link"></span>);
		$buffer .= qq(</a></span>\n);
		$pos += 2.2;
	}
	if ( $options->{'fasta'} ) {
		my $text = $options->{'fasta_label'} // 'Upload FASTA';
		$buffer .= qq(<span style="position:absolute;left:${pos}em;bottom:-1em">);
		$buffer .= qq(<a href="$options->{'fasta_url'}" title="$text" class="curate_icon_link">);
		$buffer .= q(<span class="curate_icon_highlight  fa-stack" style="font-size:1em">);
		$buffer .= q(<span class="fas fa-file fa-stack-2x curate_icon_fasta"></span>);
		$buffer .= q(<span class="fa-stack-1x filetype-text" style="top:0.25em">FAS</span>);
		$buffer .= q(</span>);
		$buffer .= qq(</a></span>\n);
		$pos += 2.2;
	}
	if ( $options->{'query'} && $records_exist ) {
		my $url = $options->{'query_url'}
		  // qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=$table);
		$buffer .= qq(<span style="position:absolute;left:${pos}em;bottom:1em">);
		$buffer .= qq(<a href="$url$set_string" title="Update/delete" class="curate_icon_link">);
		$buffer .= q(<span class="curate_icon_highlight curate_icon_query fas fa-search"></span>);
		$buffer .=
		    q(<span class="curate_icon_highlight curate_icon_edit fas fa-pencil-alt" )
		  . qq(style="left:0.8em;bottom:-0.5em;font-size:1.2em"></span>\n);
		$buffer .=
		    q(<span class="curate_icon_highlight curate_icon_delete fas fa-times" )
		  . qq(style="left:0.8em;bottom:-1.5em;font-size:1.2em"></span>\n);
		$buffer .= qq(</a></span>\n);
		$pos += 2.2;
	}
	if ( $options->{'import'} ) {
		my $text = $options->{'import_label'} // 'Import';
		$buffer .= qq(<span style="position:absolute;left:${pos}em;bottom:1em">);
		$buffer .= qq(<a href="$options->{'import_url'}" title="$text" class="curate_icon_link">);
		$buffer .= q(<span class="curate_icon_highlight curate_icon_import fas fa-arrow-left"></span>);
		$buffer .= qq(</a></span>\n);
		$pos += 2.2;
	}
	if ( $options->{'batch_update'} ) {
		my $text = $options->{'batch_update_label'} // 'Batch Update';
		$buffer .= qq(<span style="position:absolute;left:${pos}em;bottom:1em">);
		$buffer .= qq(<a href="$options->{'batch_update_url'}$set_string" title="$text" class="curate_icon_link">);
		$buffer .= q(<span class="curate_icon_highlight curate_icon_batch_edit fas fa-pencil-alt"></span>);
		$buffer .= q(<span class="curate_icon_highlight curate_icon_batch_edit fas fa-plus" )
		  . qq(style="left:0em;bottom:-0.8em;font-size:1.5em"></span>\n);
		$buffer .= qq(</a></span>\n);
		$pos += 2.2;
	}
	if ( $options->{'scan'} ) {
		my $text = $options->{'scan_label'} // 'Scan';
		$buffer .= qq(<span style="position:absolute;left:${pos}em;bottom:1em">);
		$buffer .= qq(<a href="$options->{'scan_url'}" title="$text" class="curate_icon_link">);
		$buffer .= q(<span class="curate_icon_highlight curate_icon_scan_barcode fas fa-barcode"></span>);
		$buffer .= q(<span class="curate_icon_highlight curate_icon_scan_query fas fa-search" )
		  . qq(style="left:0.8em;bottom:-1.4em;font-size:1.5em"></span>\n);
		$buffer .= qq(</a></span>\n);
		$pos += 2.2;
	}
	if ( $options->{'set'} ) {
		my $text = $options->{'set_label'} // 'Set';
		$buffer .= qq(<span style="position:absolute;left:${pos}em;bottom:1em">);
		$buffer .= qq(<a href="$options->{'set_url'}" title="$text" class="curate_icon_link">);
		$buffer .= q(<span class="curate_icon_highlight curate_icon_set fas fa-edit"></span>);
		$buffer .= qq(</a></span>\n);
		$pos += 2.2;
	}
	if ( $options->{'action'} ) {
		my $text = $options->{'action_label'} // 'Action';
		$buffer .= qq(<span style="position:absolute;left:${pos}em;bottom:1em">);
		$buffer .= qq(<a href="$options->{'action_url'}" title="$text" class="curate_icon_link">);
		$buffer .= q(<span class="curate_icon_highlight curate_icon_action fas fa-chevron-circle-right"></span>);
		$buffer .= qq(</a></span>\n);
		$pos += 2.2;
	}
	$buffer .= q(</span>);
	return $buffer;
}

sub print_content {
	my ($self)      = @_;
	my $script_name = $self->{'system'}->{'script_name'};
	my $instance    = $self->{'instance'};
	my $system      = $self->{'system'};
	return if $self->_ajax_call;
	my $desc = $self->get_db_description;
	say qq(<h1>Database curator's interface - $desc</h1>);
	$self->_print_set_section;
	my $buffer = $self->_get_standard_links;

	if ( $system->{'dbtype'} eq 'isolates' ) {
		$buffer .= $self->_get_isolate_links;
	} elsif ( $system->{'dbtype'} eq 'sequences' ) {
		$buffer .= $self->_get_seqdef_links;
	}
	my $can_do_something;
	if ($buffer) {
		$can_do_something = 1;
		say q(<div class="box" id="curator">);
		my $toggle_status = $self->_get_curator_toggle_status( \$buffer );
		if ( $toggle_status->{'show_toggle'} ) {
			say q(<div style="float:right">);
			say q(<a id="toggle_all_curator_methods" style="text-decoration:none" )
			  . qq(href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=index&amp;toggle_all_curator_methods=1">);
			my $off = $self->{'prefs'}->{'all_curator_methods'} ? 'none'   : 'inline';
			my $on  = $self->{'prefs'}->{'all_curator_methods'} ? 'inline' : 'none';
			say q(<span id="all_curator_methods_off" class="toggle_icon fas fa-toggle-off fa-2x" )
			  . qq(style="display:$off" title="Showing common functions"></span>);
			say q(<span id="all_curator_methods_on" class="toggle_icon fas fa-toggle-on fa-2x" )
			  . qq(style="display:$on" title="Showing all authorized functions"></span>);
			say q(Show all</a>);
			say q(</div>);
		}
		say q(<span class="main_icon fas fa-user-tie fa-3x fa-pull-left"></span>);
		say q(<h2>Curator functions</h2>);
		say q(<div class="grid" id="curator_grid">);
		say $buffer;
		say q(</div>);
		say q(<div style="clear:both"></div>);
		say q(</div>);

		if ( $toggle_status->{'always_show_hidden'} ) {
			say q[<script>$(function() {$(".default_hide_curator").css("display","inline");]
			  . q[$("#curator_grid").packery()});</script>];
		}
	}

	$buffer = $self->_get_admin_links;
	if ($buffer) {
		$can_do_something = 1;
		say q(<div class="box" id="admin">);
		my $toggle_status = $self->_get_admin_toggle_status( \$buffer );
		if ( $toggle_status->{'show_toggle'} ) {
			say q(<div style="float:right">);
			say q(<a id="toggle_all_admin_methods" style="text-decoration:none" )
			  . qq(href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=index&amp;toggle_all_admin_methods=1">);
			my $off = $self->{'prefs'}->{'all_admin_methods'} ? 'none'   : 'inline';
			my $on  = $self->{'prefs'}->{'all_admin_methods'} ? 'inline' : 'none';
			say q(<span id="all_admin_methods_off" class="toggle_icon fas fa-toggle-off fa-2x" )
			  . qq(style="display:$off" title="Showing common admin functions"></span>);
			say q(<span id="all_admin_methods_on" class="toggle_icon fas fa-toggle-on fa-2x" )
			  . qq(style="display:$on" title="Showing all admin and configuration functions"></span>);
			say q(Show all</a>);
			say q(</div>);
		}
		say q(<span class="config_icon fas fa-user-cog fa-3x fa-pull-left"></span>);
		say q(<h2>Admin functions</h2>);
		say q(<div class="grid" id="admin_grid">);
		say $buffer;
		say q(</div>);
		say q(<div style="clear:both"></div>);
		say q(</div>);

		if ( $toggle_status->{'always_show_hidden'} ) {
			say q[<script>$(function() {$(".default_hide_admin").css("display","inline");]
			  . q[$("#admin_grid").packery()});</script>];
		}
	}
		if ( ( $self->{'system'}->{'submissions'} // '' ) eq 'yes' ) {
		$self->_print_submission_section;
	}
	if ( $self->{'datastore'}->user_dbs_defined ) {
		$self->_print_account_requests_section;
	}
	if ( !$can_do_something ) {
		$self->print_bad_status(
			{
				    message => q(Although you are set as a curator/submitter, )
				  . q(you haven't been granted specific permission to do anything.  Please contact the )
				  . q(database administrator to set your appropriate permissions.)
			}
		);
	}
	return;
}

sub _get_curator_toggle_status {
	my ( $self, $buffer_ref ) = @_;
	my $hidden  = $$buffer_ref =~ /default_hide_curator/x ? 1 : 0;
	my $default = $$buffer_ref =~ /default_show_curator/x ? 1 : 0;
	my $show_toggle = ( $hidden && $default ) ? 1 : 0;
	my $always_show_hidden;
	if ( $hidden && !$default ) {
		$always_show_hidden = 1;
	}
	return { show_toggle => $show_toggle, always_show_hidden => $always_show_hidden };
}

sub _get_admin_toggle_status {
	my ( $self, $buffer_ref ) = @_;
	my $hidden  = $$buffer_ref =~ /default_hide_admin/x ? 1 : 0;
	my $default = $$buffer_ref =~ /default_show_admin/x ? 1 : 0;
	my $show_toggle = ( $hidden && $default ) ? 1 : 0;
	my $always_show_hidden;
	if ( $hidden && !$default ) {
		$always_show_hidden = 1;
	}
	return { show_toggle => $show_toggle, always_show_hidden => $always_show_hidden };
}

sub _cache_tables_exists {
	my ($self) = @_;
	my $exists =
	  $self->{'datastore'}
	  ->run_query(q(SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name LIKE 'temp_%')));
	return $exists;
}

sub _print_submission_section {
	my ($self) = @_;
	my $buffer         = $self->print_submissions_for_curation( { get_only => 1 } );
	my $closed_buffer  = $self->_get_closed_submission_section;
	my $publish_buffer = $self->_get_publication_requests;
	return if !$buffer && !$closed_buffer && !$publish_buffer;
	say q(<div class="box" id="submissions"><div class="scrollable">);
	say q(<span class="main_icon fas fa-upload fa-3x fa-pull-left"></span>);
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $on_or_off =
	  $user_info->{'submission_emails'}
	  ? 'ON'
	  : 'OFF';
	say qq(<div style="float:right"><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . q(page=index&amp;toggle_notifications=1" id="toggle_notifications" class="no_link">)
	  . q(<span class="main_icon fas fa-envelope fa-lg fa-pull-left">)
	  . qq(</span>Notifications: <span id="notify_text" style="font-weight:600">$on_or_off</span></a></div>);

	if ($buffer) {
		say $buffer;
	} else {
		say q(<h2>Submissions</h2>);
		say q(<p>No pending submissions.</p>);
	}
	say $self->_get_publication_requests;
	say $self->_get_closed_submission_section;
	say q(</div></div>);
	return;
}

sub _get_closed_submission_section {
	my ($self) = @_;
	my $closed_buffer =
	  $self->print_submissions_for_curation( { status => 'closed', show_outcome => 1, get_only => 1 } );
	my $buffer = q();
	if ($closed_buffer) {
		$buffer .= $self->print_navigation_bar( { no_home => 1, closed_submissions => 1, get_only => 1 } );
		$buffer .=
		  q(<div id="closed" style="display:none"><h2>Closed submissions for which you had curator rights</h2>);
		my $days = $self->get_submission_days;
		$buffer .= q(<p>The following submissions are now closed - they will remain here until )
		  . qq(removed by the submitter or for $days days.);
		$buffer .= $closed_buffer;
		$buffer .= q(</div>);
	}
	return $buffer;
}

sub _get_publication_requests {
	my ($self) = @_;
	return if ( $self->{'system'}->{'dbtype'} // q() ) ne 'isolates';
	return q() if !$self->can_modify_table('isolates');
	my $requests =
	  $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM private_isolates WHERE request_publish)');
	return q() if !$requests;
	my $buffer    = q(<h2>Publication requests</h2>);
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	if ( $user_info->{'status'} ne 'submitter' ) {
		$buffer .=
		    q(<p>There are user requests to publish some private data. Please click the 'Browse' links in the table )
		  . q(below to see these records and to choose whether to publish them.</p>);
	}
	my $users = $self->{'datastore'}->run_query(
		"SELECT DISTINCT(i.sender) FROM $self->{'system'}->{'view'} i JOIN private_isolates p ON i.id=p.isolate_id "
		  . 'WHERE p.request_publish ORDER BY i.sender',
		undef,
		{ fetch => 'col_arrayref' }
	);
	$buffer .= q(<table class="resultstable"><tr><th>Sender</th><th>Isolates</th><th>Display</th></tr>);
	my $td = 1;
	foreach my $user_id (@$users) {
		my $user_string = $self->{'datastore'}->get_user_string( $user_id, { email => 1 } );
		my $isolate_count = $self->{'datastore'}->run_query(
			'SELECT COUNT(*) FROM private_isolates p JOIN isolates i ON p.isolate_id=i.id '
			  . 'WHERE request_publish AND sender=?',
			$user_id
		);
		my $link = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;"
		  . "prov_field1=f_sender%20%28id%29&amp;prov_value1=$user_id&amp;private_records_list=4&amp;submit=1";
		$buffer .= qq(<tr class="td$td"><td>$user_string</td><td>$isolate_count</td><td>)
		  . qq(<a href="$link"><span class="fas fa-binoculars action browse"></span></a></td></tr>);
		$td = $td == 1 ? 2 : 1;
	}
	$buffer .= q(</table>);
	return $buffer;
}

sub _print_account_requests_section {
	my ($self) = @_;
	my $curator = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	return
	  if !( $curator->{'account_request_emails'}
		&& ( $self->{'permissions'}->{'import_site_users'} || $self->is_admin ) );
	my $q = $self->{'cgi'};
	$self->_reject_user if ( $q->param('reject') );
	$self->_import_user if ( $q->param('import') );
	my $user_dbs = $self->{'datastore'}->get_user_dbs;
	my @user_details;

	foreach my $user_db (@$user_dbs) {
		my $configs =
		  $self->{'datastore'}->get_configs_using_same_database( $user_db->{'db'}, $self->{'system'}->{'db'} );
		foreach my $config (@$configs) {
			my $users =
			  $self->{'datastore'}
			  ->run_query( 'SELECT user_name,datestamp FROM pending_requests WHERE dbase_config=? ORDER BY datestamp',
				$config, { db => $user_db->{'db'}, fetch => 'all_arrayref', slice => {} } );
			foreach my $user (@$users) {
				my $user_info = $self->{'datastore'}->run_query( 'SELECT * FROM users WHERE user_name=?',
					$user->{'user_name'}, { db => $user_db->{'db'}, fetch => 'row_hashref' } );
				$user_info->{'request_date'} = $user->{'datestamp'};
				$user_info->{'user_db'}      = $user_db->{'id'};
				push @user_details, $user_info;
			}
		}
	}
	return if !@user_details;
	say q(<div class="box" id="account_requests">);
	say q(<span class="main_icon fas fa-user fa-3x fa-pull-left"></span>);
	say q(<h2>Account requests</h2>);
	say q(<p>Please note that accepting or rejecting these requests does not currently notify the user.</p>);
	say q(<div class="scrollable">);
	say q(<table class="resultstable">);
	say q(<tr><th>Accept</th><th>Reject</th><th>First name</th><th>Surname</th>)
	  . q(<th>Affiliation</th><th>E-mail</th><th>Date requested</th></tr>);
	my $td = 1;
	my ( $good, $bad ) = ( GOOD, BAD );

	foreach my $user (@user_details) {
		say qq(<tr class="td$td"><td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(import=$user->{'user_name'}&amp;user_db=$user->{'user_db'}">$good</a></td>)
		  . qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(reject=$user->{'user_name'}&amp;user_db=$user->{'user_db'}">$bad</a></td>)
		  . qq(<td>$user->{'first_name'}</td><td>$user->{'surname'}</td>)
		  . qq(<td>$user->{'affiliation'}</td><td><a href="mailto:$user->{'email'}">$user->{'email'}</a></td>)
		  . qq(<td>$user->{'request_date'}</td></tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</table>);
	say q(</div>);
	say q(</div>);
	return;
}

sub _reject_user {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $user_name, $user_db ) = ( $q->param('reject'), $q->param('user_db') );
	return if !$user_name || !BIGSdb::Utils::is_int($user_db);
	my $db = $self->{'datastore'}->get_user_db($user_db);
	my $configs = $self->{'datastore'}->get_configs_using_same_database( $db, $self->{'system'}->{'db'} );
	eval {
		foreach my $config (@$configs) {
			$db->do( 'DELETE FROM pending_requests WHERE (dbase_config,user_name)=(?,?)', undef, $config, $user_name );
		}
	};
	if ($@) {
		$logger->error($@);
		$db->rollback;
	} else {
		$db->commit;
	}
	return;
}

sub _import_user {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $user_name, $user_db ) = ( $q->param('import'), $q->param('user_db') );
	return if !$user_name || !BIGSdb::Utils::is_int($user_db);
	my $db         = $self->{'datastore'}->get_user_db($user_db);
	my $configs    = $self->{'datastore'}->get_configs_using_same_database( $db, $self->{'system'}->{'db'} );
	my $id         = $self->next_id('users');
	my $curator_id = $self->get_curator_id;
	eval {
		$self->{'db'}->do(
			'INSERT INTO users (id,user_name,status,date_entered,datestamp,curator,submission_emails,'
			  . 'account_request_emails,user_db) VALUES (?,?,?,?,?,?,?,?,?)',
			undef, $id, $user_name, 'user', 'now', 'now', $curator_id, 'false', 'false', $user_db
		);

		#We need to identify all registered configs that use the same database
		foreach my $config (@$configs) {
			$db->do( 'INSERT INTO registered_users (dbase_config,user_name,datestamp) VALUES (?,?,?)',
				undef, $config, $user_name, 'now' );
			$db->do( 'DELETE FROM pending_requests WHERE (dbase_config,user_name)=(?,?)', undef, $config, $user_name );
		}
	};
	if ($@) {
		$logger->error($@);
		$db->rollback;
		$self->{'db'}->rollback;
	} else {
		$db->commit;
		$self->{'db'}->commit;
	}
	return;
}

sub _isolates_exist {
	my ($self) = @_;
	return $self->{'datastore'}->run_query( "SELECT EXISTS(SELECT * FROM $self->{'system'}->{'view'})",
		undef, { cache => 'CurateIndexPage::isolates_exist' } );
}

sub _schemes_exist {
	my ($self) = @_;
	return $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM schemes)', undef, { cache => 'CurateIndexPage::schemes_exist' } );
}

sub _loci_exist {
	my ($self) = @_;
	return $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM loci)', undef, { cache => 'CurateIndexPage::loci_exist' } );
}

sub _scheme_groups_exist {
	my ($self) = @_;
	return $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM scheme_groups)');
}

sub _sets_exist {
	my ($self) = @_;
	return $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM sets)');
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Curator's interface - $desc";
}
1;
