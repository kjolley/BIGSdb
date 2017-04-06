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
package BIGSdb::IndexPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
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
	my $q = $self->{'cgi'};
	$self->{'jQuery'}  = 1;
	$self->{'noCache'} = 1;
	$self->choose_set;
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $set_id = $self->get_set_id;
		my $scheme_data = $self->{'datastore'}->get_scheme_list( { with_pk => 1, set_id => $set_id } );
		$self->{'tooltips'} = 1 if @$scheme_data > 1;
	}
	return;
}

sub print_content {
	my ($self)      = @_;
	my $script_name = $self->{'system'}->{'script_name'};
	my $q           = $self->{'cgi'};
	my $desc        = $self->get_db_description;
	say qq(<h1>$desc database</h1>);
	$self->print_banner;
	$self->_print_jobs;
	if ( ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ) {
		$self->print_set_section;
	}
	$self->_print_main_section;
	$self->_print_plugin_section;
	return;
}

sub _print_jobs {
	my ($self) = @_;
	return if !$self->{'system'}->{'read_access'} eq 'public' || !$self->{'config'}->{'jobs_db'};
	return if !defined $self->{'username'};
	my $days = $self->{'config'}->{'results_deleted_days'} // 7;
	my $jobs = $self->{'jobManager'}->get_user_jobs( $self->{'instance'}, $self->{'username'}, $days );
	return if !@$jobs;
	my %status_counts;
	$status_counts{ $_->{'status'} }++ foreach @$jobs;
	my $days_plural = $days == 1  ? '' : 's';
	my $jobs_plural = @$jobs == 1 ? '' : 's';
	say q(<div class="box" id="jobs">);
	say q(<span class="job_icon fa fa-briefcase fa-3x pull-left"></span>);
	say q(<h2>Jobs</h2>);
	say q(<p>You have submitted or run )
	  . @$jobs
	  . qq( offline job$jobs_plural in the past )
	  . ( $days_plural ? $days : '' )
	  . qq( day$days_plural. )
	  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=jobs">Show jobs</a></p>);
	my %replace = ( started => 'running', submitted => 'queued' );
	my @breakdown;

	foreach my $status (qw (started submitted finished failed cancelled terminated)) {
		push @breakdown, ( $replace{$status} // $status ) . ": $status_counts{$status}" if $status_counts{$status};
	}
	local $" = '; ';
	say qq(<p>@breakdown</p>);
	say q(</div>);
	return;
}

sub _print_main_section {
	my ($self) = @_;
	say q(<div class="box" id="index"><div class="scrollable">);
	my $scheme_data = $self->get_scheme_data( { with_pk => 1 } );
	$self->_print_query_section($scheme_data);
	$self->_print_projects_section;
	$self->_print_download_section($scheme_data);
	$self->_print_options_section;
	$self->_print_submissions_section;
	$self->_print_private_data_section;
	
	$self->_print_general_info_section($scheme_data);
	say q(</div></div>);
	return;
}

sub _print_query_section {
	my ( $self, $scheme_data ) = @_;
	my $system   = $self->{'system'};
	my $instance = $self->{'instance'};

	#Append to URLs to ensure unique caching.
	my $cache_string = $self->get_cache_string;
	my $set_id       = $self->get_set_id;
	say q(<div style="float:left;margin-right:1em">);
	say q(<span class="main_icon fa fa-search fa-3x pull-left"></span>);
	say q(<h2>Query database</h2><ul class="toplevel">);
	my $url_root = "$self->{'system'}->{'script_name'}?db=$instance$cache_string&amp;";
	if ( $system->{'dbtype'} eq 'isolates' ) {
		say qq(<li><a href="${url_root}page=query">Search or browse database</a></li>);
		my $loci = $self->{'datastore'}->get_loci( { set_id => $set_id, do_not_order => 1 } );
		if (@$loci) {
			say qq(<li><a href="${url_root}page=profiles">Search by combinations of loci (profiles)</a></li>);
		}
	} elsif ( $system->{'dbtype'} eq 'sequences' ) {
		say qq(<li><a href="${url_root}page=sequenceQuery">Sequence query</a> - query an allele sequence.</li>);
		say qq(<li><a href="${url_root}page=batchSequenceQuery">Batch sequence query</a> - )
		  . q(query multiple sequences in FASTA format.</li>);
		say qq(<li><a href="${url_root}page=tableQuery&amp;table=sequences">Sequence attribute search</a> - )
		  . q(find alleles by matching criteria (all loci together)</li>);
		say qq(<li><a href="${url_root}page=alleleQuery&amp;table=sequences">Locus-specific sequence attribute )
		  . q(search</a> - select, analyse and download specific alleles.</li>);
		if (@$scheme_data) {
			my $scheme_arg = @$scheme_data == 1 ? "&amp;scheme_id=$scheme_data->[0]->{'id'}" : '';
			my $scheme_desc = @$scheme_data == 1 ? $scheme_data->[0]->{'name'} : '';
			say qq(<li><a href="${url_root}page=query$scheme_arg">Search, browse or enter list of )
			  . qq($scheme_desc profiles</a></li>);
			say qq(<li><a href="${url_root}page=profiles$scheme_arg">Search by combinations of $scheme_desc )
			  . q(alleles</a> - including partial matching.</li>);
			say qq(<li><a href="${url_root}page=batchProfiles$scheme_arg">Batch profile query</a> - )
			  . qq(lookup $scheme_desc profiles copied from a spreadsheet.</li>);
		}
	}
	if ( $self->{'config'}->{'jobs_db'} ) {
		my $query_html_file = "$self->{'system'}->{'dbase_config_dir'}/$self->{'instance'}/contents/job_query.html";
		$self->print_file($query_html_file) if -e $query_html_file;
	}
	if ( $system->{'dbtype'} eq 'isolates' ) {
		my $sample_fields = $self->{'xmlHandler'}->get_sample_field_list;
		if (@$sample_fields) {
			say qq(<li><a href="${url_root}page=tableQuery&amp;table=samples">Sample management</a> - )
			  . q(culture/DNA storage tracking</li>);
		}
	}
	say q(</ul></div>);
	return;
}

sub _print_projects_section {
	my ($self) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'isolates';
	my $cache_string = $self->get_cache_string;
	my $url_root     = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}$cache_string&amp;";
	my @list;
	my $listed_projects = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM projects WHERE list)');
	if ($listed_projects) {
		push @list, qq(<a href="${url_root}page=projects">Main public projects</a>);
	}
	if ( $self->show_user_projects ) {
		push @list, qq(<a href="${url_root}page=userProjects">Your projects</a>);
	}
	return if !@list;
	say q(<div style="float:left;margin-right:1em">);
	say q(<span class="main_icon fa fa-list-alt fa-3x pull-left"></span>);
	say q(<h2>Projects</h2><ul class="toplevel">);
	local $" = qq(</li>\n<li>);
	say qq(<li>@list</li>);
	say q(</ul></div>);
	return;
}

sub _print_private_data_section {
	my ($self) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'isolates';
	return if !$self->{'username'};
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	return if !$user_info;
	my $limit = $self->{'datastore'}->get_user_private_isolate_limit( $user_info->{'id'} );
	return if !$limit;
	my $cache_string = $self->get_cache_string;
	say q(<div style="float:left;margin-right:1em">);
	say q(<span class="main_icon fa fa-lock fa-3x pull-left"></span>);
	say q(<h2>Private data</h2><ul class="toplevel">);
	say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}$cache_string&amp;)
	  . q(page=privateRecords">Upload/manage records</a></li>);
	say q(</ul></div>);
	return;
}

sub _print_download_section {
	my ( $self, $scheme_data ) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'sequences';
	my ( $scheme_ids_ref, $desc_ref ) = $self->extract_scheme_desc($scheme_data);
	my $q                   = $self->{'cgi'};
	my $seq_download_buffer = '';
	my $scheme_buffer       = '';
	my $group_count         = $self->{'datastore'}->run_query('SELECT COUNT(*) FROM scheme_groups');
	if ( !( $self->{'system'}->{'disable_seq_downloads'} && $self->{'system'}->{'disable_seq_downloads'} eq 'yes' )
		|| $self->is_admin )
	{
		$seq_download_buffer =
		    qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadAlleles)
		  . ( $group_count ? '&amp;tree=1' : '' )
		  . qq(">Allele sequences</a></li>\n);
	}
	my $first = 1;
	my $i     = 0;
	if ( @$scheme_data > 1 ) {
		$scheme_buffer .= q(<li style="white-space:nowrap">);
		$scheme_buffer .= $q->start_form;
		$scheme_buffer .= $q->popup_menu( -name => 'scheme_id', -values => $scheme_ids_ref, -labels => $desc_ref );
		$scheme_buffer .= $q->hidden('db');
		my $download = DOWNLOAD;
		$scheme_buffer .= q( <button type="submit" name="page" value="downloadProfiles" )
		  . qq(class="smallbutton">$download Profiles</button>\n);
		$scheme_buffer .= $q->end_form;
		$scheme_buffer .= q(</li>);
	} elsif ( @$scheme_data == 1 ) {
		$scheme_buffer .=
		    qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=downloadProfiles&amp;scheme_id=$scheme_data->[0]->{'id'}">)
		  . qq($scheme_data->[0]->{'name'} profiles</a></li>);
	}
	if ( $seq_download_buffer || $scheme_buffer ) {
		say q(<div style="float:left; margin-right:1em">);
		say q(<span class="main_icon fa fa-download fa-3x pull-left"></span>);
		say q(<h2>Downloads</h2>);
		say q(<ul class="toplevel">);
		say $seq_download_buffer;
		say $scheme_buffer;
		say q(</ul></div>);
	}
	return;
}

sub _print_options_section {
	my ($self) = @_;
	my $cache_string = $self->get_cache_string;
	say q(<div style="float:left; margin-right:1em">);
	say q(<span class="main_icon fa fa-cogs fa-3x pull-left"></span>);
	say q(<h2>Option settings</h2>);
	say q(<ul class="toplevel">);
	say qq(<li><a href="$self->{'system'}->{'script_name'}?page=options&amp;db=$self->{'instance'}$cache_string">)
	  . q(Set general options</a>);
	say q( - including isolate table field handling.) if $self->{'system'}->{'dbtype'} eq 'isolates';
	say q(</li>);
	my $url_root = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;);

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say q(<li>Set display and query options for )
		  . qq(<a href="${url_root}table=loci$cache_string">locus</a>, )
		  . qq(<a href="${url_root}table=schemes$cache_string">schemes</a> or )
		  . qq(<a href="${url_root}table=scheme_fields$cache_string">scheme fields</a>.</li>);
	} else {
		say qq(<li><a href="${url_root}table=schemes$cache_string">Scheme options</a></li>);
	}
	if ( $self->{'system'}->{'authentication'} eq 'builtin' && $self->{'auth_db'} ) {
		my $clients_authorized = $self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM access_tokens WHERE dbase=?)',
			$self->{'system'}->{'db'},
			{ db => $self->{'auth_db'} }
		);
		if ($clients_authorized) {
			say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . q(page=authorizeClient&amp;modify=1">View/modify client software permissions</a></li>);
		}
	}
	say q(</ul></div>);
	return;
}

sub _print_submissions_section {
	my ($self) = @_;
	return if ( $self->{'system'}->{'submissions'} // '' ) ne 'yes';
	if ( !$self->{'config'}->{'submission_dir'} ) {
		$logger->error('Submission directory is not configured in bigsdb.conf.');
		return;
	}
	say q(<div style="float:left; margin-right:1em">);
	say q(<span class="main_icon fa fa-upload fa-3x pull-left"></span>);
	say q(<h2>Submissions</h2><ul class="toplevel">);
	my $set_id = $self->get_set_id // 0;
	my $set_string = ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ? "&amp;choose_set=1&amp;sets_list=$set_id" : q();
	say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit$set_string">)
	  . q(Manage submissions</a></li>);
	say '</ul></div>';
	return;
}

sub _print_general_info_section {
	my ( $self, $scheme_data ) = @_;
	say q(<div style="float:left; margin-right:1em">);
	say q(<span class="main_icon fa fa-info-circle fa-3x pull-left"></span>);
	say q(<h2>General information</h2><ul class="toplevel">);
	my $cache_string = $self->get_cache_string;
	my $max_date;
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $allele_count = $self->_get_allele_count;
		my $tables       = [qw (locus_stats profiles profile_refs accession)];
		$max_date = $self->_get_max_date($tables);
		say "<li>Number of sequences: $allele_count</li>";
		if ( @$scheme_data == 1 ) {
			foreach (@$scheme_data) {
				my $profile_count =
				  $self->{'datastore'}
				  ->run_query( 'SELECT COUNT(*) FROM profiles WHERE scheme_id=?', $scheme_data->[0]->{'id'} );
				say "<li>Number of profiles ($scheme_data->[0]->{'name'}): $profile_count</li>";
			}
		} elsif ( @$scheme_data > 1 ) {
			say q(<li>Number of profiles: <a id="toggle1" class="showhide">Show</a>);
			say q(<a id="toggle2" class="hideshow">Hide</a><div class="hideshow"><ul>);
			foreach (@$scheme_data) {
				my $profile_count =
				  $self->{'datastore'}->run_query( 'SELECT COUNT(*) FROM profiles WHERE scheme_id=?', $_->{'id'} );
				$_->{'name'} =~ s/\&/\&amp;/gx;
				say qq(<li>$_->{'name'}: $profile_count</li>);
			}
			say q(</ul></div></li>);
		}
	} else {
		my $isolate_count = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM $self->{'system'}->{'view'}");
		my @tables        = qw (isolates isolate_aliases allele_designations allele_sequences refs);
		$max_date = $self->_get_max_date( \@tables );
		print qq(<li>Isolates: $isolate_count</li>);
	}
	say qq(<li>Last updated: $max_date</li>) if $max_date;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . q(page=fieldValues">Defined field values</a></li>);
	}
	my $history_table = $self->{'system'}->{'dbtype'} eq 'isolates' ? 'history' : 'profile_history';
	my $history_exists = $self->{'datastore'}->run_query("SELECT EXISTS(SELECT * FROM $history_table)");
	say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;)
	  . qq(table=$history_table&amp;order=timestamp&amp;direction=descending&amp;submit=1$cache_string">)
	  . ( $self->{'system'}->{'dbtype'} eq 'sequences' ? 'Profile u' : 'U' )
	  . q(pdate history</a></li>)
	  if $history_exists;
	say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=version">)
	  . q(About BIGSdb</a></li>);
	say q(</ul></div>);
	return;
}

sub _print_plugin_section {
	my ($self) = @_;
	my $scheme_data = $self->get_scheme_data( { with_pk => 1 } );
	my ( $scheme_ids_ref, $desc_ref ) = $self->extract_scheme_desc($scheme_data);
	my $q            = $self->{'cgi'};
	my $set_id       = $self->get_set_id;
	my $cache_string = $self->get_cache_string;
	my $plugins      = $self->{'pluginManager'}->get_appropriate_plugin_names(
		'breakdown|export|analysis|miscellaneous',
		$self->{'system'}->{'dbtype'},
		{ set_id => $set_id }
	);
	if (@$plugins) {
		say q(<div class="box" id="plugins"><div class="scrollable">);
		my %icon =
		  ( breakdown => 'pie-chart', export => 'save', analysis => 'line-chart', miscellaneous => 'file-text-o' );
		foreach my $section (qw (breakdown export analysis miscellaneous)) {
			$q->param( 'page', 'index' );
			$plugins =
			  $self->{'pluginManager'}
			  ->get_appropriate_plugin_names( $section, $self->{'system'}->{'dbtype'}, { set_id => $set_id } );
			next if !@$plugins;
			say q(<div style="float:left; margin-right:1em">);
			say qq(<span class="plugin_icon fa fa-$icon{$section} fa-3x pull-left"></span>);
			say q(<h2 style="margin-right:1em">) . ucfirst($section) . q(</h2><ul class="toplevel">);
			foreach my $plugin (@$plugins) {
				my $att      = $self->{'pluginManager'}->get_plugin_attributes($plugin);
				my $menuitem = $att->{'menutext'};
				my $scheme_arg =
				  (      $self->{'system'}->{'dbtype'} eq 'sequences'
					  && $att->{'seqdb_type'} eq 'schemes'
					  && @$scheme_data == 1 )
				  ? qq(&amp;scheme_id=$scheme_data->[0]->{'id'})
				  : q();
				say qq(<li><a href="$self->{'system'}->{'script_name'}?page=plugin&amp;name=$att->{'module'}&amp;)
				  . qq(db=$self->{'instance'}$scheme_arg$cache_string">$menuitem</a>);
				say qq( - $att->{'menu_description'}) if $att->{'menu_description'};
				say q(</li>);
			}
			say q(</ul></div>);
		}
		say q(</div></div>);
	}
	return;
}

sub _get_max_date {
	my ( $self, $tables ) = @_;
	local $" = ' UNION SELECT MAX(datestamp) FROM ';
	my $qry      = "SELECT MAX(max_datestamp) FROM (SELECT MAX(datestamp) AS max_datestamp FROM @$tables) AS v";
	my $max_date = $self->{'datastore'}->run_query($qry);
	return $max_date;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description || 'BIGSdb';
	return $desc;
}

sub _get_allele_count {
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? ' WHERE locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE '
	  . "set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id)"
	  : q();
	return $self->{'datastore'}->run_query("SELECT SUM(allele_count) FROM locus_stats$set_clause") // 0;
}
1;
