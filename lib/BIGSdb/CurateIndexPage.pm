#Written by Keith Jolley
#Copyright (c) 2010-2025, University of Oxford
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
package BIGSdb::CurateIndexPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage BIGSdb::IndexPage BIGSdb::SubmitPage);
use Try::Tiny;
use List::MoreUtils qw(uniq none);
use BIGSdb::Constants qw(:interface DEFAULT_DOMAIN);
use Email::Sender::Transport::SMTP;
use Email::Sender::Simple qw(try_to_sendmail);
use Email::MIME;
use Email::Valid;
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
	$self->{$_} = 1 foreach qw (jQuery noCache packery tooltips allowExpand);
	$self->choose_set;
	$self->{'system'}->{'only_sets'} = 'no' if $self->is_admin;
	my $guid = $self->get_guid;
	foreach my $method (
		qw(all_curator_methods misc_admin_methods locus_admin_methods scheme_admin_methods
		set_admin_methods client_admin_methods field_admin_methods)
	  )
	{
		try {
			$self->{'prefs'}->{$method} =
			  ( $self->{'prefstore'}->get_general_pref( $guid, $self->{'system'}->{'db'}, $method ) // '' ) eq 'on'
			  ? 1
			  : 0;
		} catch {
			if ( $_->isa('BIGSdb::Exception::Database::NoRecord') ) {
				$self->{'prefs'}->{$method} = 0;
			} else {
				$logger->logdie($_);
			}
		};
	}
	$self->{'optional_curator_display'} = $self->{'prefs'}->{'all_curator_methods'} ? 'inline' : 'none';

	#Check admin links to see what potentially can be displayed.
	my @methods = qw(misc_admin locus_admin scheme_admin set_admin client_admin field_admin);
	foreach my $method (@methods) {
		$self->{"optional_${method}_display"} = 'inline';
	}
	my $admin_links = $self->_get_admin_links;
	my $categories  = 0;
	foreach my $method (@methods) {
		if ( $admin_links =~ /$method/x ) {
			$categories++;
		}
	}
	if ( $categories == 1 && $admin_links !~ /default_show_admin/x ) {
		foreach my $method (@methods) {
			$self->{"optional_${method}_display"} = 'inline';
		}
		return;
	}
	foreach my $method (@methods) {
		$self->{"optional_${method}_display"} =
		  $self->{'prefs'}->{"${method}_methods"} ? 'inline' : 'none';
	}
	$self->{'breadcrumbs'} = [];
	if ( $self->{'system'}->{'webroot'} ) {
		push @{ $self->{'breadcrumbs'} },
		  {
			label => $self->{'system'}->{'webroot_label'} // 'Organism',
			href  => $self->{'system'}->{'webroot'}
		  };
	}
	push @{ $self->{'breadcrumbs'} },
	  { label => $self->{'system'}->{'formatted_description'} // $self->{'system'}->{'description'} };
	return;
}

sub get_javascript {
	my ($self)     = @_;
	my $links      = $self->get_related_databases;
	my $db_trigger = q();
	if ( @$links > 1 ) {
		$db_trigger = << "END";
+\$("#related_db_trigger,#close_related_db").click(function(){		
		\$("#related_db_panel").toggle("slide",{direction:"right"},"fast");
		return false;
	});	
END
	}
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
		});
		var categories = ["locus","scheme","set","client","field","misc"];
		if (\$('#all_admin_methods_on').is(':visible')){
			for (var i=0; i<categories.length; i++){
				if (\$('#' + categories[i] + '_admin_methods_off').is(':visible')){
					\$('#toggle_' + categories[i] + '_admin_methods').click();	
				}
			}
		} else {
			for (var i=0; i<categories.length; i++){
				if (\$('#' + categories[i] + '_admin_methods_on').is(':visible')){
					\$('#toggle_' + categories[i] + '_admin_methods').click();	
				}
			}
		}
	});
	var categories = ["misc_admin","locus_admin","scheme_admin","set_admin","client_admin","field_admin"];
	for (var i=0; i<categories.length; i++){
		var cat = categories[i]
		bind_toggle(cat);
	}
	var \$grid = \$(".grid").packery({
       	itemSelector: '.grid-item',
  		gutter: 10,
  		stamp: '.stamp'
    });        
    \$(window).resize(function() {
    	delay(function(){
     			\$grid.packery({
     				gutter:10
     			});
    	}, 1000);
 	});
 	\$("#expand,#contract").click(function(){
 		delay(function(){
     			\$grid.packery({
     				gutter:10
     			});
    	}, 3000);
 	});
	$db_trigger
	\$(".curate_icon_link").on("mouseenter", function(){
		\$(".curate_icon_highlight", this).addClass("fa-beat");
	});
	\$(".curate_icon_link").on("mouseleave", function(){
		\$(".curate_icon_highlight", this).removeClass("fa-beat");
	});
});

function bind_toggle (cat){
	\$('a#toggle_' + cat + '_methods').click(function(event){	
		event.preventDefault();
 		\$(this).attr('href', function(){  
  			\$('#' + cat + '_methods_off').toggle();	
	  		\$('#' + cat + '_methods_on').toggle();
	  		\$('.' + cat).fadeToggle(200,'',function(){
	  			\$('#admin_grid').packery();
	  		});	
	  		\$.ajax({
	  			url: this.href,
	  			cache: false,
	  		});
	   	});
	   	var categories = ["locus","scheme","set","client","field","misc"];
	   	var all_hidden = 1;
	   	var all_shown = 1;
	   	for (var i=0; i<categories.length; i++){	
		  	if (\$('#' + categories[i] + '_admin_methods_on').is(':visible')){
				all_hidden = 0;
			}
			if (\$('#' + categories[i] + '_admin_methods_off').is(':visible')){
				all_shown = 0;
			}
		}
		if (all_hidden){
			\$('#all_admin_methods_off').css('display','inline');	
	  		\$('#all_admin_methods_on').css('display','none');
		} else {
			\$('#all_admin_methods_on').css('display','inline');	
	  		\$('#all_admin_methods_off').css('display','none');
		}
		if (all_shown){
			\$('#all_admin_methods_on').css('display','inline');	
	  		\$('#all_admin_methods_off').css('display','none');
		} else {
			\$('#all_admin_methods_off').css('display','inline');	
	  		\$('#all_admin_methods_on').css('display','none');
		}
	});
}

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
	my $user_info  = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
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

sub _toggle_methods {
	my ( $self, $category ) = @_;
	my $new_value = $self->{'prefs'}->{"${category}_methods"} ? 'off' : 'on';
	my $guid      = $self->get_guid;
	try {
		$self->{'prefstore'}->set_general( $guid, $self->{'system'}->{'db'}, "${category}_methods", $new_value );
	} catch {
		if ( $_->isa('BIGSdb::Exception::Database::NoRecord') ) {
			$logger->error("Cannot toggle show $category methods");
		} else {
			$logger->logdie($_);
		}
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
	foreach my $cat (qw(all_curator misc_admin locus_admin scheme_admin set_admin client_admin field_admin)) {
		if ( $q->param("toggle_${cat}_methods") ) {
			$self->_toggle_methods($cat);
			return 1;
		}
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
	my ($self)     = @_;
	my $set_id     = $self->get_set_id;
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
	$buffer .= $self->_get_classification_field_values;
	$buffer .= $self->_get_lincode_prefix_values;
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
	$buffer .= $self->_get_geography_point_lookup;
	return $buffer;
}

sub _get_admin_links {
	my ($self) = @_;
	my $buffer = q();
	$buffer .= $self->_get_permissions;
	$buffer .= $self->_get_user_passwords;
	$buffer .= $self->_get_config_check;
	$buffer .= $self->_get_blast_cache_refresh;
	$buffer .= $self->_get_scheme_cache_refresh;
	$buffer .= $self->_get_user_dbases;
	$buffer .= $self->_get_curator_configs;

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$buffer .= $self->_get_geocoding;
		$buffer .= $self->_get_eav_fields;
		$buffer .= $self->_get_isolate_field_extended_attributes;
		$buffer .= $self->_get_composite_fields;
		$buffer .= $self->_get_validation_rules;
		$buffer .= $self->_get_oauth_credentials;
		$buffer .= $self->_get_query_interfaces;
	}

	#Only modify schemes/loci etc. when sets not selected.
	my $set_id = $self->get_set_id;
	return $buffer if $set_id;
	$buffer .= $self->_get_loci;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$buffer .= $self->_get_genome_filtering;
		$buffer .= $self->_get_sequence_attributes;
		$buffer .= $self->_get_analysis_fields;
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		$buffer .= $self->_get_locus_extended_attributes;
		$buffer .= $self->_get_mutation_fields;
	}
	$buffer .= $self->_get_schemes;
	$buffer .= $self->_get_scheme_groups;
	$buffer .= $self->_get_classification_schemes;
	$buffer .= $self->_get_lincode_schemes;
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		$buffer .= $self->_get_lincodes;
		$buffer .= $self->_get_client_dbases;
		$buffer .= $self->_get_locus_curators;
		$buffer .= $self->_get_scheme_curators;
	}
	$buffer .= $self->_get_sets;
	return $buffer;
}

sub _get_geocoding {
	my ($self) = @_;
	return q() if !$self->is_admin;
	my $buffer =
		q(<div class="curategroup curategroup_geocoding grid-item field_admin" )
	  . qq(style="display:$self->{'optional_field_admin_display'}"><h2>Geocoding setup</h2>);
	$buffer .= $self->_get_icon_group(
		undef,
		'globe-africa',
		{
			action       => 1,
			action_url   => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=geocoding),
			action_label => 'Setup',
			info         => 'Geocoding - Set up standard country names and continent links.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_geography_point_lookup {
	my ($self) = @_;
	return q() if !$self->can_modify_table('geography_point_lookup');
	return     if ( $self->{'system'}->{'dbtype'} // q() ) ne 'isolates';
	my $atts = $self->{'xmlHandler'}->get_all_field_attributes;
	my $lookup_fields;
	foreach my $field ( keys %$atts ) {
		if ( ( $atts->{$field}->{'geography_point_lookup'} // q() ) eq 'yes' ) {
			$lookup_fields = 1;
			last;
		}
	}
	return q() if !$lookup_fields;
	if ( !$self->{'datastore'}->run_query(q(SELECT to_regclass('geography_point_lookup'))) ) {
		$logger->fatal(
				'Your database configuration contains one or more fields with the geography_point_lookup attribute set '
			  . 'but your database does not contain the geography_point_lookup table. You need to ensure that PostGIS '
			  . 'is installed and run the isolatedb_geocoding.sql SQL script against the database to set this up.' );
		undef $atts->{$_}->{'geography_point_lookup'} foreach keys %$atts;
		return q();
	}
	my $buffer = q(<div class="curategroup curategroup_projects grid-item default_hide_curator" )
	  . qq(style="display:$self->{'optional_curator_display'}"><h2>Geopoint field lookup</h2>);
	$buffer .= $self->_get_icon_group(
		'geography_point_lookup',
		'globe-europe',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Geopoint lookup - Set GPS coordinates for geographic field values.'
		}
	);
	$buffer .= q(</div>);
	return $buffer;
}

sub _get_user_fields {
	my ($self) = @_;
	my $buffer = q();
	my ( $import, $query_only );
	if ( ( $self->{'permissions'}->{'import_site_users'} || $self->is_admin )
		&& $self->{'datastore'}->user_dbs_defined )
	{
		$import = 1;
	}
	if ( $self->{'permissions'}->{'query_users'} ) {
		$query_only = 1;
	}
	my $modify_users = $self->can_modify_table('users');
	if ( $modify_users || $import || $query_only ) {
		my $import_url = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=importUser);
		$buffer .= q(<div class="curategroup curategroup_users grid-item default_show_curator"><h2>Users</h2>);
		$buffer .= $self->_get_icon_group(
			'users', 'user',
			{
				add          => $modify_users,
				batch_add    => $modify_users,
				query        => $modify_users,
				query_only   => $query_only && !$modify_users,
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
	return $buffer if !$self->_loci_exist;
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
	return $buffer if !$self->_loci_exist;
	my $set_string = $self->_get_set_string;
	my $batch_add_url =
	  qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSequences$set_string);
	my $fasta_url = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddFasta$set_string);
	$buffer .= q(<div class="curategroup curategroup_sequences grid-item default_show_curator"><h2>Sequences</h2>);
	$buffer .= $self->_get_icon_group(
		'sequences',
		'dna',
		{
			add           => 1,
			batch_add     => 1,
			batch_add_url => $batch_add_url,
			query         => 1,
			fasta         => 1,
			fasta_url     => $fasta_url,
			fasta_label   => 'Upload new sequences using a FASTA file containing new variants of a single locus.'
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
		my $set_clause = $set_id ? qq( AND id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)) : q();
		$schemes = $self->{'datastore'}->run_query(
			'SELECT DISTINCT id FROM schemes RIGHT JOIN scheme_members ON schemes.id=scheme_members.scheme_id '
			  . "JOIN scheme_fields ON schemes.id=scheme_fields.scheme_id WHERE primary_key$set_clause",
			undef,
			{ fetch => 'col_arrayref' }
		);
	} else {
		my $set_clause = $set_id ? qq( AND scheme_id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)) : q();
		$schemes = $self->{'datastore'}->run_query(
			'SELECT scheme_id FROM scheme_curators WHERE curator_id=? AND '
			  . "scheme_id IN (SELECT scheme_id FROM scheme_fields WHERE primary_key)$set_clause",
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
		next if $self->{'prefs'}->{'disable_schemes'}->{$scheme_id};
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

sub _get_mutation_fields {
	my ($self) = @_;
	my $buffer = q();
	if ( $self->can_modify_table('dna_mutations') && $self->_locus_type_exists('DNA') ) {
		$buffer .= q(<div class="curategroup curategroup_loci grid-item locus_admin" )
		  . qq(style="display:$self->{'optional_locus_admin_display'}"><h2>Single nucleotide polymorphisms</h2>);
		$buffer .= $self->_get_icon_group(
			'dna_mutations',
			'dna',
			{
				add       => 1,
				batch_add => 1,
				query     => 1
			}
		);
		$buffer .= qq(</div>\n);
	}
	if ( $self->can_modify_table('peptide_mutations')
		&& ( $self->_locus_type_exists('peptide') || $self->_locus_type_exists('DNA') ) )
	{
		$buffer .= q(<div class="curategroup curategroup_loci grid-item locus_admin" )
		  . qq(style="display:$self->{'optional_locus_admin_display'}"><h2>Single AA variations</h2>);
		$buffer .= $self->_get_icon_group(
			'peptide_mutations',
			'dna',
			{
				add       => 1,
				batch_add => 1,
				query     => 1
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
			add              => $self->{'permissions'}->{'only_private'} ? 0 : 1,
			add_url          => $add_url,
			batch_add        => $self->{'permissions'}->{'only_private'} ? 0 : 1,
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
		if ( ( $self->{'system'}->{'alternative_codon_tables'} // q() ) eq 'yes' ) {
			$buffer .= q(<div class="curategroup curategroup_isolates grid-item default_hide_curator" )
			  . qq(style="display:$self->{'optional_curator_display'}"><h2>Codon tables</h2>);
			$buffer .= $self->_get_icon_group(
				'codon_tables',
				'table',
				{
					add       => 1,
					batch_add => 1,
					query     => 1,
					info      => 'Codon tables - Set alternative codon tables for specific isolates.'
				}
			);
			$buffer .= qq(</div>\n);
		}
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
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	if ( $user_info->{'status'} eq 'curator' || $user_info->{'status'} eq 'admin' ) {
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
	}
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
			info      =>
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
			add           => 1,
			add_url       => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=addSeqbin),
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

sub _get_permissions {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('permissions');
	$buffer .= q(<div class="curategroup curategroup_permissions grid-item default_show_admin"><h2>Permissions</h2>);
	$buffer .= $self->_get_icon_group(
		'permissions',
		'user-shield',
		{
			query             => 1,
			always_show_query => 1,
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
	$buffer .= q(<div class="curategroup curategroup_remote_dbases grid-item misc_admin" )
	  . qq(style="display:$self->{'optional_misc_admin_display'}"><h2>User databases</h2>);
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

sub _get_curator_configs {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('curator_configs');
	$buffer .= q(<div class="curategroup curategroup_remote_dbases grid-item misc_admin" )
	  . qq(style="display:$self->{'optional_misc_admin_display'}"><h2>Curator configs</h2>);
	$buffer .= $self->_get_icon_group(
		'curator_configs',
		'user-tie',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Curator configs - Limit users to curator access only from specific database '
			  . 'configurations. If a curator does not have a value set here, then they can curate using '
			  . 'any configurations that their other permissions allow them to use.'
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
	$buffer .= q(<div class="curategroup curategroup_remote_dbases grid-item misc_admin" )
	  . qq(style="display:$self->{'optional_misc_admin_display'}"><h2>OAuth credentials</h2>);
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
	$buffer .= q(<div class="curategroup curategroup_loci grid-item locus_admin" )
	  . qq(style="display:$self->{'optional_locus_admin_display'}"><h2>PCR reactions</h2>);
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
		$buffer .= q(<div class="curategroup curategroup_loci grid-item locus_admin" )
		  . qq(style="display:$self->{'optional_locus_admin_display'}"><h2>PCR locus links</h2>);
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
	$buffer .= q(<div class="curategroup curategroup_loci grid-item locus_admin" )
	  . qq(style="display:$self->{'optional_locus_admin_display'}"><h2>Nucleotide probes</h2>);
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
		$buffer .= q(<div class="curategroup curategroup_loci grid-item locus_admin" )
		  . qq(style="display:$self->{'optional_locus_admin_display'}"><h2>Probe locus links</h2>);
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
	$buffer .= q(<div class="curategroup curategroup_designations grid-item field_admin" )
	  . qq(style="display:$self->{'optional_field_admin_display'}"><h2>Sequence attributes</h2>);
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
	$buffer .= q(<div class="curategroup curategroup_loci grid-item locus_admin" )
	  . qq(style="display:$self->{'optional_locus_admin_display'}"><h2>Locus extended attributes</h2>);
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
	$buffer .= q(<div class="curategroup curategroup_remote_dbases grid-item client_admin" )
	  . qq(style="display:$self->{'optional_client_admin_display'}"><h2>Client databases</h2>);
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
		$buffer .= q(<div class="curategroup curategroup_remote_dbases grid-item client_admin" )
		  . qq(style="display:$self->{'optional_client_admin_display'}"><h2>Client database loci</h2>);
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
		$buffer .= q(<div class="curategroup curategroup_remote_dbases grid-item client_admin" )
		  . qq(style="display:$self->{'optional_client_admin_display'}"><h2>Client database fields</h2>);
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
		$buffer .= q(<div class="curategroup curategroup_remote_dbases grid-item client_admin" )
		  . qq(style="display:$self->{'optional_client_admin_display'}"><h2>Client database schemes</h2>);
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
	if ( $self->_classification_schemes_exist ) {
		$buffer .= q(<div class="curategroup curategroup_remote_dbases grid-item client_admin" )
		  . qq(style="display:$self->{'optional_client_admin_display'}"><h2>Client database classification schemes</h2>);
		$buffer .= $self->_get_icon_group(
			'client_dbase_cschemes',
			'object-group',
			{
				add       => 1,
				batch_add => 1,
				query     => 1,
				info      => 'Client database classification scheme - Define classification schemes that are used in '
				  . 'client databases.'
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
	return $buffer if !$self->_loci_exist;
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
	return $buffer if !$self->_schemes_exist;
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
	  if !$self->{'permissions'}->{'modify_loci'}
	  && !$self->{'permissions'}->{'modify_schemes'}
	  && !$self->is_admin;
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

sub _get_blast_cache_refresh {
	my ($self) = @_;
	my $buffer = q();
	my $loci   = $self->{'datastore'}->get_loci;
	return $buffer
	  if !$self->is_admin || $self->{'system'}->{'dbtype'} ne 'sequences' || !@$loci;
	$buffer .= q(<div class="curategroup curategroup_maintenance grid-item default_show_admin"><h2>BLAST caches</h2>);
	$buffer .= $self->_get_icon_group(
		undef, 'eraser',
		{
			action       => 1,
			action_url   => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=refreshCache),
			action_label => 'Clear caches',
			info         => 'BLAST caches - Mark caches stale.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_scheme_cache_refresh {
	my ($self) = @_;
	my $buffer = q();
	return $buffer
	  if !( $self->is_admin || $self->{'permissions'}->{'refresh_scheme_caches'} )
	  || $self->{'system'}->{'dbtype'} ne 'isolates'
	  || !$self->_cache_tables_exists;
	$buffer .= q(<div class="curategroup curategroup_maintenance grid-item default_show_admin"><h2>Cache refresh</h2>);
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
	$buffer .= q(<div class="curategroup curategroup_loci grid-item locus_admin" )
	  . qq(style="display:$self->{'optional_locus_admin_display'}"><h2>Loci</h2>);
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
	return $buffer if !$self->_loci_exist;
	$buffer .= q(<div class="curategroup curategroup_loci grid-item locus_admin" )
	  . qq(style="display:$self->{'optional_locus_admin_display'}"><h2>Locus aliases</h2>);
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
	$buffer .= q(<div class="curategroup curategroup_isolates grid-item field_admin" )
	  . qq(style="display:$self->{'optional_field_admin_display'}"><h2>Extended attribute fields</h2>);
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

sub _get_eav_fields {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('eav_fields');
	$buffer .= q(<div class="curategroup curategroup_isolates grid-item field_admin" )
	  . qq(style="display:$self->{'optional_field_admin_display'}"><h2>Sparse fields</h2>);
	$buffer .= $self->_get_icon_group(
		'eav_fields',
		'microscope',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Sparse fields - Define fields that are likely to contain sparsely populated '
			  . 'values, i.e. fields that only a minority of records will have values for. It is '
			  . 'inefficient to define these as separate columns in the main isolates table. This is particularly '
			  . 'appropriate if you have 10s-100s of such fields to define.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_analysis_fields {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('analysis_fields');
	$buffer .= q(<div class="curategroup curategroup_isolates grid-item field_admin" )
	  . qq(style="display:$self->{'optional_field_admin_display'}"><h2>Analysis fields</h2>);
	$buffer .= $self->_get_icon_group(
		'analysis_fields',
		'chart-line',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Analysis fields - Define fields that can appear in the output of arbitray '
			  . 'analysis run by external tools, e.g. Kleborate, rMLST species id. These save analysis '
			  . 'results as a JSON string within the analysis_results table. By registering particular '
			  . 'fields you can allow BIGSdb to use these results for queries or further analysis.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_composite_fields {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('composite_fields');
	$buffer .= q(<div class="curategroup curategroup_isolates grid-item field_admin" )
	  . qq(style="display:$self->{'optional_field_admin_display'}"><h2>Composite fields</h2>);
	$buffer .= $self->_get_icon_group(
		'composite_fields',
		'cubes',
		{
			add       => 1,
			query     => 1,
			query_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=compositeQuery),
			info      => 'Composite fields - Consist of a combination of different isolate, loci or scheme fields.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_query_interfaces {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('query_interfaces');
	$buffer .= q(<div class="curategroup curategroup_isolates grid-item misc_admin" )
	  . qq(style="display:$self->{'optional_misc_admin_display'}"><h2>Query interfaces</h2>);
	$buffer .= $self->_get_icon_group(
		'query_interfaces',
		'shapes',
		{
			add   => 1,
			query => 1,
			info  => 'Query interfaces - Define query interfaces with pre-selected fields.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer if !$self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM query_interfaces)');
	$buffer .= q(<div class="curategroup curategroup_isolates grid-item misc_admin" )
	  . qq(style="display:$self->{'optional_misc_admin_display'}"><h2>Query interface fields</h2>);
	$buffer .= $self->_get_icon_group(
		'query_interface_fields',
		'cube',
		{
			add   => 1,
			query => 1,
			info  => 'Interface fields - Add pre-selected fields to query interfaces.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_validation_rules {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('validation_rules');
	$buffer .= q(<div class="curategroup curategroup_isolates grid-item field_admin" )
	  . qq(style="display:$self->{'optional_field_admin_display'}"><h2>Validation conditions</h2>);
	$buffer .= $self->_get_icon_group(
		'validation_conditions',
		'check-circle',
		{
			add       => 1,
			query     => 1,
			batch_add => 1,
			info      => 'Validation conditions - Conditions that must be matched for a validation to fail. '
			  . 'Multiple conditions can be combined to create a rule.'
		}
	);
	$buffer .= qq(</div>\n);
	$buffer .= q(<div class="curategroup curategroup_isolates grid-item field_admin" )
	  . qq(style="display:$self->{'optional_field_admin_display'}"><h2>Validation rules</h2>);
	$buffer .= $self->_get_icon_group(
		'validation_rules',
		'ban',
		{
			add       => 1,
			query     => 1,
			batch_add => 1,
			info      => 'Validation rules - Advanced rules restricting values in provenance '
			  . 'metadata fields depending on values in other fields.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer
	  if !$self->{'datastore'}
	  ->run_query('SELECT EXISTS(SELECT * FROM validation_rules) AND EXISTS(SELECT * FROM validation_conditions)');
	$buffer .= q(<div class="curategroup curategroup_isolates grid-item field_admin" )
	  . qq(style="display:$self->{'optional_field_admin_display'}"><h2>Rule conditions</h2>);
	$buffer .= $self->_get_icon_group(
		'validation_rule_conditions',
		'tasks',
		{
			add       => 1,
			query     => 1,
			batch_add => 1,
			info      => 'Rule conditions - Conditions that must be fulfilled to fail a validation rule.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_schemes {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('schemes');
	$buffer .= q(<div class="curategroup curategroup_schemes grid-item scheme_admin" )
	  . qq(style="display:$self->{'optional_scheme_admin_display'}"><h2>Schemes</h2>);
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
	$buffer .= q(<div class="curategroup curategroup_schemes grid-item scheme_admin" )
	  . qq(style="display:$self->{'optional_scheme_admin_display'}"><h2>Scheme fields</h2>);
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
		$buffer .= q(<div class="curategroup curategroup_schemes grid-item scheme_admin" )
		  . qq(style="display:$self->{'optional_scheme_admin_display'}"><h2>Scheme members</h2>);
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
	return $buffer if !$self->_schemes_exist;
	$buffer .= q(<div class="curategroup curategroup_schemes grid-item scheme_admin" )
	  . qq(style="display:$self->{'optional_scheme_admin_display'}"><h2>Scheme groups</h2>);
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
		$buffer .= q(<div class="curategroup curategroup_schemes grid-item scheme_admin" )
		  . qq(style="display:$self->{'optional_scheme_admin_display'}"><h2>Group members (schemes)</h2>);
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
		$buffer .= q(<div class="curategroup curategroup_schemes grid-item scheme_admin" )
		  . qq(style="display:$self->{'optional_scheme_admin_display'}"><h2>Group members (groups)</h2>);
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
	return $buffer if !$self->_schemes_exist;
	return $buffer if !$self->can_modify_table('classification_schemes');
	$buffer .= q(<div class="curategroup curategroup_schemes grid-item scheme_admin" )
	  . qq(style="display:$self->{'optional_scheme_admin_display'}"><h2>Classification schemes</h2>);
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
	return $buffer if !$self->_classification_schemes_exist;
	$buffer .= q(<div class="curategroup curategroup_schemes grid-item scheme_admin" )
	  . qq(style="display:$self->{'optional_scheme_admin_display'}"><h2>Classification group fields</h2>);
	$buffer .= $self->_get_icon_group(
		'classification_group_fields',
		'object-group',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Classification group fields - Additional fields that can be associated with '
			  . 'classification scheme groups.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_classification_field_values {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM classification_group_fields)');
	$buffer .= q(<div class="curategroup curategroup_schemes grid-item default_hide_curator" )
	  . qq(style="display:$self->{'optional_curator_display'}"><h2>Classification group field values</h2>);
	$buffer .= $self->_get_icon_group(
		'classification_group_field_values',
		'object-group',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'Classification group field values - Associate values with particular classification groups.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_lincode_prefix_values {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->{'system'}->{'dbtype'} eq 'sequences';
	return $buffer if !$self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM lincode_fields)');
	$buffer .= q(<div class="curategroup curategroup_schemes grid-item default_hide_curator" )
	  . qq(style="display:$self->{'optional_curator_display'}"><h2>LINcode prefix nomenclature</h2>);
	$buffer .= $self->_get_icon_group(
		'lincode_prefixes',
		'grip-horizontal',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'LINcode prefix values - Link LINcode prefixes to nomenclature values.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_lincode_schemes {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->_schemes_exist( { with_pk => 1 } );
	return $buffer if !$self->can_modify_table('lincode_schemes');
	$buffer .= q(<div class="curategroup curategroup_schemes grid-item scheme_admin" )
	  . qq(style="display:$self->{'optional_scheme_admin_display'}"><h2>LINcode schemes</h2>);
	$buffer .= $self->_get_icon_group(
		'lincode_schemes',
		'object-group',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'LINcode schemes - Set up LINcode clustering '
			  . 'of scheme profiles at different locus difference thresholds.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer if !$self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM lincode_schemes)');
	$buffer .= q(<div class="curategroup curategroup_schemes grid-item scheme_admin" )
	  . qq(style="display:$self->{'optional_scheme_admin_display'}"><h2>LINcode fields</h2>);
	$buffer .= $self->_get_icon_group(
		'lincode_fields',
		'th-list',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info      => 'LINcode fields - Set up fields to associate LINcode prefixes to nomenclature terms.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer;
}

sub _get_lincodes {
	my ($self) = @_;
	return q() if !$self->is_admin;
	my $schemes;
	my $set_id     = $self->get_set_id;
	my $set_clause = $set_id ? qq( AND id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)) : q();
	$schemes = $self->{'datastore'}->run_query(
		'SELECT DISTINCT ls.scheme_id FROM lincode_schemes ls RIGHT JOIN scheme_members sm ON '
		  . 'ls.scheme_id=sm.scheme_id JOIN scheme_fields sf ON ls.scheme_id=sf.scheme_id '
		  . "WHERE primary_key$set_clause",
		undef,
		{ fetch => 'col_arrayref' }
	);
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
			$display = qq(style="display:$self->{'optional_scheme_admin_display'}");
		}
		$desc{$scheme_id} =~ s/\&/\&amp;/gx;
		$buffer .=
			q(<div class="curategroup curategroup_profiles grid-item scheme_admin" )
		  . qq($display><h2>$desc{$scheme_id} LINcodes</h2>);
		$buffer .= $self->_get_icon_group(
			undef,
			'grip-horizontal',
			{
				batch_add     => 1,
				batch_add_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=lincodeBatchAdd&amp;scheme_id=$scheme_id)
			}
		);
		$buffer .= qq(</div>\n);
	}
	return $buffer;
}

sub _get_sets {
	my ($self) = @_;
	my $buffer = q();
	return $buffer if !$self->can_modify_table('sets');
	return $buffer if ( $self->{'system'}->{'sets'} // '' ) ne 'yes';
	$buffer .= q(<div class="curategroup curategroup_sets grid-item set_admin" )
	  . qq(style="display:$self->{'optional_set_admin_display'}"><h2>Sets</h2>);
	$buffer .= $self->_get_icon_group(
		'sets', 'hands',
		{
			add       => 1,
			batch_add => 1,
			query     => 1,
			info => 'Sets - Describe a collection of loci and schemes that can be treated like a stand-alone database.'
		}
	);
	$buffer .= qq(</div>\n);
	return $buffer if !$self->_sets_exist;

	if ( $self->_loci_exist ) {
		$buffer .= q(<div class="curategroup curategroup_sets grid-item set_admin" )
		  . qq(style="display:$self->{'optional_set_admin_display'}"><h2>Set loci</h2>);
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
		$buffer .= q(<div class="curategroup curategroup_sets grid-item set_admin" )
		  . qq(style="display:$self->{'optional_set_admin_display'}"><h2>Set schemes</h2>);
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
		if ( $self->{'system'}->{'views'} ) {
			$buffer .= q(<div class="curategroup curategroup_sets grid-item set_admin" )
			  . qq(style="display:$self->{'optional_set_admin_display'}"><h2>Set views</h2>);
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
	my $fa_class   = $options->{'fa_class'} // 'fas';
	my $set_string = $self->_get_set_string;
	my $links      = 0;

	#Checking a large seqdef db sequences table can be slow on PostgreSQL 9.3.
	#We can instead use the locus_stats table.
	my $check_table = $table;
	$check_table = 'locus_stats' if ( $table // q() ) eq 'sequences';
	my $records_exist = $table ? $self->{'datastore'}->run_query("SELECT EXISTS(SELECT * FROM $check_table)") : 1;
	foreach my $value (qw(add batch_add link query query_only import fasta batch_update scan set action)) {
		$links++ if $options->{$value};
	}
	$links--
	  if ( $options->{'query'} || $options->{'query_only'} ) && !$records_exist && !$options->{'always_show_query'};
	my $buffer;
	if ( $options->{'info'} ) {
		$buffer .= q(<span style="position:absolute;right:1.5em;top:0.2em">);
		$buffer .= qq(<a style="cursor:help" title="$options->{'info'}" class="tooltip">);
		$buffer .= q(<span class="curate_icon_highlight curate_icon_info fas fa-info-circle"></span>);
		$buffer .= qq(</a></span>\n);
	}
	$buffer .=
	  qq(<span class="curate_icon_span"><span class="curate_icon fa-7x fa-fw $fa_class fa-$icon"></span></span>);
	$buffer .= q(<span class="curate_buttonbar">);
	my $pos = 5.7 - BIGSdb::Utils::decimal_place( $links * 2.2 / 2, 1 );
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
		$pos -= 0.5;
		$buffer .= qq(<span style="position:absolute;left:${pos}em;bottom:1em">);
		$buffer .= qq(<a href="$options->{'fasta_url'}" title="$text" class="curate_icon_link">);
		$buffer .= q(<span class="curate_icon_highlight fa-stack" style="font-size:1em">);
		$buffer .= q(<span class="fas fa-file fa-stack-2x curate_icon_fasta"></span>);
		$buffer .= q(<span class="fa-stack-1x filetype-text" style="top:0.25em">FAS</span>);
		$buffer .= q(</span>);
		$buffer .= qq(</a></span>\n);
		$pos += 2.2;
	}
	if ( $records_exist || $options->{'always_show_query'} ) {
		if ( $options->{'query'} ) {
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
		} elsif ( $options->{'query_only'} ) {
			my $url = $options->{'query_url'}
			  // qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=$table);
			$buffer .= qq(<span style="position:absolute;left:${pos}em;bottom:1em">);
			$buffer .= qq(<a href="$url$set_string" title="Query" class="curate_icon_link">);
			$buffer .= q(<span class="curate_icon_highlight curate_icon_query fas fa-search"></span>);
			$buffer .= qq(</a></span>\n);
			$pos += 2.2;
		}
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
		  . qq(style="left:0em;bottom:-0.5em;font-size:1.5em"></span>\n);
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
	my $desc = $self->get_db_description( { formatted => 1 } );
	say qq(<h1 style="padding-top:0.3em">Database curator's interface - $desc</h1>);
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
			say q(<span style="vertical-align:0.4em">Show all</span></a>);
			say q(</div>);
		}
		say q(<span class="main_icon fas fa-user-tie fa-3x fa-pull-left"></span>);
		say q(<h2>Curator functions</h2>);
		say q(<div class="grid" id="curator_grid">);
		say $buffer;
		say q(</div>);
		say q(<div style="clear:both"></div>);
		$self->print_related_database_panel;
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
		$self->_print_admin_toggles( \$buffer );
		say q(<span class="config_icon fas fa-user-cog fa-3x fa-pull-left"></span>);
		say q(<h2>Admin functions</h2>);
		say q(<div class="grid" id="admin_grid">);
		say q(<div class="grid-item stamp" style="position:absolute;right:0;width:100px;height:178px;z-index:0"></div>);
		say $buffer;
		say q(</div>);
		say q(<div style="clear:both"></div>);
		say q(</div>);
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

sub print_panel_buttons {
	my ($self) = @_;
	$self->print_related_dbases_button;
	return;
}

sub _print_admin_toggles {
	my ( $self, $buffer ) = @_;
	say q(<div style="position:absolute;right:16px;z-index:9">);
	say q(<ul style="list-style:none;padding-left:0">);
	my %label = (
		locus  => 'Loci',
		scheme => 'Schemes',
		set    => 'Sets',
		client => 'Clients',
		field  => 'Fields',
		misc   => 'Misc'
	);
	my %expanded = ( misc => 'miscellaenous' );
	my $count    = 0;
	my $all_on   = 1;
	my $toggle_buffer;

	foreach my $category (qw(locus scheme set client field misc)) {
		next if !ref $buffer || $$buffer !~ /${category}_admin/x;
		$count++;
		my $off      = $self->{'prefs'}->{"${category}_admin_methods"} ? 'none'   : 'inline';
		my $on       = $self->{'prefs'}->{"${category}_admin_methods"} ? 'inline' : 'none';
		my $expanded = $expanded{$category} // $category;
		$toggle_buffer .=
			qq(<li><a id="toggle_${category}_admin_methods" style="text-decoration:none" )
		  . qq(href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=index&amp;toggle_${category}_admin_methods=1">)
		  . qq(<span id="${category}_admin_methods_off" class="toggle_icon fas fa-toggle-off fa-2x" )
		  . qq(style="display:$off" title="Not showing $expanded admin functions"></span>)
		  . qq(<span id="${category}_admin_methods_on" class="toggle_icon fas fa-toggle-on fa-2x" )
		  . qq(style="display:$on" title="Showing $expanded admin and configuration functions"></span> )
		  . qq(<span style="vertical-align:0.4em">$label{$category}</span></a></li>);
		$all_on = 0 if !$self->{'prefs'}->{"${category}_admin_methods"};
	}
	if ( $count > 1 || ( $count == 1 && $$buffer =~ /default_show_admin/x ) ) {
		say $toggle_buffer;
	}
	if ( $count > 1 ) {
		my $off = $all_on ? 'none'   : 'inline';
		my $on  = $all_on ? 'inline' : 'none';
		say q(<li><a id="toggle_all_admin_methods" style="text-decoration:none" )
		  . qq(href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=index&amp;toggle_all_admin_methods=1">)
		  . q(<span id="all_admin_methods_off" class="toggle_icon fas fa-toggle-off fa-2x" )
		  . qq(style="display:$off" title="Not showing all admin functions"></span>)
		  . q(<span id="all_admin_methods_on" class="toggle_icon fas fa-toggle-on fa-2x" )
		  . qq(style="display:$on" title="Showing all admin and configuration functions"></span> )
		  . q(<span style="vertical-align:0.4em">Show all</span></a></li>);
	}
	say q(</ul>);
	say q(</div>);
	return;
}

sub _get_curator_toggle_status {
	my ( $self, $buffer_ref ) = @_;
	my $hidden      = $$buffer_ref =~ /default_hide_curator/x ? 1 : 0;
	my $default     = $$buffer_ref =~ /default_show_curator/x ? 1 : 0;
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
	  ->run_query(q(SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name LIKE 'temp_scheme%')));
	return $exists;
}

sub _print_submission_section {
	my ($self)         = @_;
	my $buffer         = $self->print_submissions_for_curation( { get_only => 1 } );
	my $closed_buffer  = $self->_get_closed_submission_section;
	my $publish_buffer = $self->_get_publication_requests;
	return if !$buffer && !$closed_buffer && !$publish_buffer;
	say q(<div class="box" id="submissions"><div class="scrollable">);
	say q(<span class="main_icon fas fa-upload fa-3x fa-pull-left"></span>);
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );

	if ( !$user_info->{'user_db'} ) {
		my $on_or_off =
		  $user_info->{'submission_emails'}
		  ? 'ON'
		  : 'OFF';
		say qq(<div style="float:right"><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . q(page=index&amp;toggle_notifications=1" id="toggle_notifications" class="no_link">)
		  . q(<span class="main_icon fas fa-envelope fa-lg fa-pull-left">)
		  . qq(</span>Notifications: <span id="notify_text" style="font-weight:600">$on_or_off</span></a></div>);
	}
	if ($buffer) {
		say $buffer;
	} else {
		say q(<h2>Submissions</h2>);
		say q(<p>No pending submissions.</p>);
	}
	say $publish_buffer;
	say $closed_buffer;
	say q(</div></div>);
	return;
}

sub _get_closed_submission_section {
	my ($self) = @_;
	my $closed_buffer =
	  $self->print_submissions_for_curation( { status => 'closed', show_outcome => 1, get_only => 1 } );
	my $buffer = q();
	if ($closed_buffer) {
		$buffer .= $self->print_navigation_bar( { closed_submissions => 1, get_only => 1 } );
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

sub _reject_publication {
	my ($self) = @_;
	return     if ( $self->{'system'}->{'dbtype'} // q() ) ne 'isolates';
	return q() if !$self->can_modify_table('isolates');
	my $q       = $self->{'cgi'};
	my $user_id = $q->param('reject_publication');
	return if !BIGSdb::Utils::is_int($user_id);
	my $to_publish = $self->{'datastore'}
	  ->run_query( 'SELECT COUNT(*) FROM private_isolates WHERE request_publish AND user_id=?', $user_id );
	return if !$to_publish;
	eval { $self->{'db'}->do( 'UPDATE private_isolates SET request_publish=FALSE WHERE user_id=?', undef, $user_id ); };

	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		my $curator_id = $self->get_curator_id;
		my $curator_string =
		  $self->{'datastore'}->get_user_string( $curator_id, { email => 1, text_email => 1, affiliation => 1 } );
		my $plural         = $to_publish == 1 ? q() : q(s);
		my $db_description = $self->get_db_description;
		$self->_send_email(
			$user_id,
			"Private isolate publication request rejected ($db_description)",
			"Your recent request to publish $to_publish private isolate$plural has been rejected by $curator_string. "
			  . 'Please contact them if you wish to query this.'
		);
	}
	return;
}

sub _accept_publication {
	my ($self) = @_;
	return     if ( $self->{'system'}->{'dbtype'} // q() ) ne 'isolates';
	return q() if !$self->can_modify_table('isolates');
	my $q       = $self->{'cgi'};
	my $user_id = $q->param('accept_publication');
	return if !BIGSdb::Utils::is_int($user_id);
	my $to_publish = $self->{'datastore'}
	  ->run_query( 'SELECT COUNT(*) FROM private_isolates WHERE request_publish AND user_id=?', $user_id );
	return if !$to_publish;
	my $curator_id = $self->get_curator_id;
	eval {
		$self->{'db'}->do(
			'INSERT INTO embargo_history (isolate_id,timestamp,action,embargo,curator) '
			  . 'SELECT isolate_id,?,?,?,? FROM private_isolates WHERE request_publish AND user_id=?',
			undef, 'now', 'Record made public', undef, $curator_id, $user_id
		);
		$self->{'db'}->do( 'DELETE FROM private_isolates WHERE request_publish AND user_id=?', undef, $user_id );
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		my $curator_string =
		  $self->{'datastore'}->get_user_string( $curator_id, { email => 1, text_email => 1, affiliation => 1 } );
		my $plural         = $to_publish == 1 ? q() : q(s);
		my $db_description = $self->get_db_description;
		$self->_send_email(
			$user_id,
			"Private isolate publication request accepted ($db_description)",
			"Your recent request to publish $to_publish private isolate$plural has been accepted by $curator_string. "
			  . 'These isolates are now public.'
		);
	}
	return;
}

sub _send_email {
	my ( $self, $user_id, $subject, $message ) = @_;
	my $user_info      = $self->{'datastore'}->get_user_info($user_id);
	my $address        = Email::Valid->address( $user_info->{'email'} );
	my $domain         = $self->{'config'}->{'domain'}                  // DEFAULT_DOMAIN;
	my $sender_address = $self->{'config'}->{'automated_email_address'} // "no_reply\@$domain";
	return if !$address;
	my $transport = Email::Sender::Transport::SMTP->new(
		{
			host => $self->{'config'}->{'smtp_server'} // 'localhost',
			port => $self->{'config'}->{'smtp_port'}   // 25,
		}
	);
	my $email = Email::MIME->create(
		header_str => [
			To      => $address,
			From    => $sender_address,
			Subject => $subject
		],
		attributes => {
			encoding => 'quoted-printable',
			charset  => 'UTF-8',
		},
		body_str => $message
	);
	eval { try_to_sendmail( $email, { transport => $transport } ) || $logger->error("Cannot send E-mail to $address"); };
	$logger->error($@) if $@;
	return;
}

sub _get_publication_requests {
	my ($self) = @_;
	return     if ( $self->{'system'}->{'dbtype'} // q() ) ne 'isolates';
	return q() if !$self->can_modify_table('isolates');
	my $q = $self->{'cgi'};
	$self->_reject_publication if $q->param('reject_publication');
	$self->_accept_publication if $q->param('accept_publication');
	my $requests =
	  $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM private_isolates WHERE request_publish)');
	return q() if !$requests;
	my $users = $self->{'datastore'}->run_query(
		"SELECT DISTINCT(i.sender) FROM $self->{'system'}->{'view'} i JOIN private_isolates p ON i.id=p.isolate_id "
		  . 'WHERE p.request_publish ORDER BY i.sender',
		undef,
		{ fetch => 'col_arrayref' }
	);
	return if !@$users;
	my $buffer    = q(<h2>Publication requests</h2>);
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );

	if ( $user_info->{'status'} ne 'submitter' ) {
		$buffer .=
			q(<p>There are user requests to publish some private data. Please click the 'Display' links in the table )
		  . q(below to see these records and to choose whether to publish them. The user will be notified automatically )
		  . q(if you accept or deny the request.</p>);
	}
	$buffer .= q(<table class="resultstable"><tr><th>Deny request</th><th>Sender</th><th>Isolates</th>)
	  . q(<th>Display</th><th>Accept request</tr>);
	my $td = 1;
	foreach my $user_id (@$users) {
		my $user_string   = $self->{'datastore'}->get_user_string( $user_id, { email => 1 } );
		my $isolate_count = $self->{'datastore'}->run_query(
			'SELECT COUNT(*) FROM private_isolates p JOIN isolates i ON p.isolate_id=i.id '
			  . 'WHERE request_publish AND sender=?',
			$user_id
		);
		my $link = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;"
		  . "prov_field1=f_sender%20%28id%29&amp;prov_value1=$user_id&amp;private_records_list=5&amp;submit=1";
		$buffer .=
			qq(<tr class="td$td"><td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(reject_publication=$user_id"><span class="statusbad fas fa-times action"></span></a></td>)
		  . qq(<td>$user_string</td><td>$isolate_count</td>)
		  . qq(<td><a href="$link"><span class="fas fa-binoculars action browse"></span></a></td>)
		  . qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(accept_publication=$user_id"><span class="statusgood fas fa-check action"></span></a></td></tr>);
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
	$self->_reject_user if $q->param('reject');
	$self->_import_user if $q->param('import');
	my $user_dbs = $self->{'datastore'}->get_user_dbs;
	my @user_details;

	foreach my $user_db (@$user_dbs) {
		my $configs =
		  $self->{'datastore'}->get_configs_using_same_database( $user_db->{'db'}, $self->{'system'}->{'db'} );
		foreach my $config (@$configs) {
			my $users = $self->{'datastore'}->run_query(
				'SELECT user_name,datestamp FROM pending_requests WHERE dbase_config=? '
				  . 'ORDER BY datestamp,user_name',
				$config,
				{ db => $user_db->{'db'}, fetch => 'all_arrayref', slice => {} }
			);
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
	my $extra_headings = q();
	if ( $self->{'config'}->{'site_user_country'} ) {
		$extra_headings .= q(<th>Country</th>);
	}
	if ( $self->{'config'}->{'site_user_sector'} ) {
		$extra_headings .= q(<th>Sector</th>);
	}
	say q(<div class="box" id="account_requests">);
	say q(<span class="main_icon fas fa-user fa-3x fa-pull-left"></span>);
	say q(<h2>Account requests</h2>);
	say q(<p>Users will automatically be notified when you accept these requests.</p>);
	say q(<div class="scrollable">);
	say q(<table class="resultstable">);
	say q(<tr><th>Reject</th><th>First name</th><th>Surname</th>)
	  . qq(<th>Affiliation</th>$extra_headings<th>E-mail</th><th>Date requested</th><th>Accept</th></tr>);
	my $td = 1;
	my ( $good, $bad ) = ( GOOD, BAD );

	foreach my $user (@user_details) {
		my $extra_cols = q();
		if ( $self->{'config'}->{'site_user_country'} ) {
			$user->{'country'} //= q();
			$extra_cols .= qq(<td>$user->{'country'}</td>);
		}
		if ( $self->{'config'}->{'site_user_sector'} ) {
			$user->{'sector'} //= q();
			$extra_cols .= qq(<td>$user->{'sector'}</td>);
		}
		say qq(<tr class="td$td">)
		  . qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(reject=$user->{'user_name'}&amp;user_db=$user->{'user_db'}" class="action">$bad</a></td>)
		  . qq(<td>$user->{'first_name'}</td><td>$user->{'surname'}</td><td>$user->{'affiliation'}</td>)
		  . qq($extra_cols<td><a href="mailto:$user->{'email'}">$user->{'email'}</a></td>)
		  . qq(<td>$user->{'request_date'}</td>)
		  . qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(import=$user->{'user_name'}&amp;user_db=$user->{'user_db'}" class="action">$good</a></td></tr>);
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
	my ( $user_name, $user_db ) = ( scalar $q->param('reject'), scalar $q->param('user_db') );
	return if !$user_name || !BIGSdb::Utils::is_int($user_db);
	my $db      = $self->{'datastore'}->get_user_db($user_db);
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
	my ( $user_name, $user_db ) = ( scalar $q->param('import'), scalar $q->param('user_db') );
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
		$self->_notify_succesful_registration($user_name);
	}
	return;
}

sub _notify_succesful_registration {
	my ( $self, $user_name ) = @_;
	my $subject = qq(Account registration request for $self->{'system'}->{'description'} database approved);
	my $message;
	if ( -e "$self->{'dbase_config_dir'}/$self->{'instance'}/registration_success.txt" ) {
		my $message_ref =
		  BIGSdb::Utils::slurp("$self->{'dbase_config_dir'}/$self->{'instance'}/registration_success.txt");
		$message = $$message_ref;
	} else {
		$message = qq(Your request to access the $self->{'system'}->{'description'} database has been approved. )
		  . q(You will now be able to log in.);
	}
	my $user_info = $self->{'datastore'}->get_user_info_from_username($user_name);
	my $address   = Email::Valid->address( $user_info->{'email'} );
	my $domain    = $self->{'config'}->{'domain'} // DEFAULT_DOMAIN;
	return if !$address;
	my $sender_address = $self->{'config'}->{'automated_email_address'} // "no_reply\@$domain";
	my $transport      = Email::Sender::Transport::SMTP->new(
		{
			host => $self->{'config'}->{'smtp_server'} // 'localhost',
			port => $self->{'config'}->{'smtp_port'}   // 25,
		}
	);
	my $email = Email::MIME->create(
		header_str => [
			To      => $address,
			From    => $sender_address,
			Subject => $subject
		],
		attributes => {
			encoding => 'quoted-printable',
			charset  => 'UTF-8',
		},
		body_str => $message
	);
	eval { try_to_sendmail( $email, { transport => $transport } ) || $logger->error("Cannot send E-mail to $address"); };
	$logger->error($@) if $@;
	return;
}

sub _isolates_exist {
	my ($self) = @_;
	return $self->{'datastore'}->run_query( "SELECT EXISTS(SELECT * FROM $self->{'system'}->{'view'})",
		undef, { cache => 'CurateIndexPage::isolates_exist' } );
}

sub _schemes_exist {
	my ( $self, $options ) = @_;
	my $pk_term = $options->{'with_pk'} ? q(JOIN scheme_fields sf ON schemes.id=sf.scheme_id WHERE primary_key) : q();
	return $self->{'datastore'}->run_query( "SELECT EXISTS(SELECT * FROM schemes$pk_term)",
		undef, { cache => 'CurateIndexPage::schemes_exist' } );
}

sub _classification_schemes_exist {
	my ($self) = @_;
	return $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM classification_schemes)',
		undef, { cache => 'CurateIndexPage::cschemes_exist' } );
}

sub _loci_exist {
	my ($self) = @_;
	return $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM loci)', undef, { cache => 'CurateIndexPage::loci_exist' } );
}

sub _locus_type_exists {
	my ( $self, $type ) = @_;
	return $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM loci WHERE data_type=?)',
		$type, { cache => 'CurateIndexPage::locus_type_exists' } );
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
