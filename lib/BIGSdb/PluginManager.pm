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
package BIGSdb::PluginManager;
use strict;
use warnings;
use BIGSdb::Exceptions;
use List::MoreUtils qw(any none);
use JSON;
use Config::Tiny;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

sub new {    ## no critic (RequireArgUnpacking)
	my $class = shift;
	my $self  = {@_};
	$self->{'plugins'}    = {};
	$self->{'attributes'} = {};
	bless( $self, $class );
	$self->initiate;
	return $self;
}

sub initiate {
	my ($self) = @_;
	my @plugins;
	opendir( PLUGINDIR, "$self->{'pluginDir'}/BIGSdb/Plugins" );
	foreach ( readdir PLUGINDIR ) {
		push @plugins, $1 if /(.*)\.pm$/x;
	}
	close PLUGINDIR;
	foreach (@plugins) {
		my $plugin_name = ~/^(\w*)$/x ? $1 : undef;    #untaint
		$plugin_name = "$plugin_name";
		eval "use BIGSdb::Plugins::$plugin_name";      ## no critic (ProhibitStringyEval)
		if ($@) {
			$logger->warn("$plugin_name plugin not installed properly!  $@");
		} else {
			my $plugin = "BIGSdb::Plugins::$plugin_name"->new(
				system             => $self->{'system'},
				dbase_config_dir   => $self->{'dbase_config_dir'},
				config_dir         => $self->{'config_dir'},
				lib_dir            => $self->{'lib_dir'},
				cgi                => $self->{'cgi'},
				instance           => $self->{'instance'},
				prefs              => $self->{'prefs'},
				prefstore          => $self->{'prefstore'},
				config             => $self->{'config'},
				datastore          => $self->{'datastore'},
				db                 => $self->{'db'},
				xmlHandler         => $self->{'xmlHandler'},
				dataConnector      => $self->{'dataConnector'},
				jobManager         => $self->{'jobManager'},
				mod_perl_request   => $self->{'mod_perl_request'},
				contigManager      => $self->{'contigManager'},
				max_upload_size_mb => $self->{'config'}->{'max_upload_size'},
				curate             => $self->{'curate'}
			);
			$self->{'plugins'}->{$plugin_name}                  = $plugin;
			$self->{'attributes'}->{$plugin_name}               = $plugin->get_attributes;
			$self->{'attributes'}->{$plugin_name}->{'language'} = 'Perl';
		}
	}
	if ( $self->_python_plugins_enabled ) {
		my $python_config = "$self->{'config_dir'}/python_plugins.json";
		eval {
			my $json_ref       = BIGSdb::Utils::slurp($python_config);
			my $python_plugins = decode_json($$json_ref);
			foreach my $plugin (@$python_plugins) {
				push @{ $self->{'python_plugins'} }, $plugin->{'module'};
				$self->{'attributes'}->{ $plugin->{'module'} } = $plugin;
				$self->{'attributes'}->{ $plugin->{'module'} }->{'language'} = 'Python';
			}
		};
		$logger->error("$self->{'config_dir'}/python_plugins.json: $@") if $@;
	}
	return;
}

sub get_restricted_plugins {
	my ( $self, $username ) = @_;
	my $file = "$self->{'config_dir'}/restrictions.conf";
	return {} if !-e $file;
	if ( !defined $self->{'cache'}->{'blocked_plugins'} ) {
		my $config = Config::Tiny->read($file);
		if ( !defined $config ) {
			$logger->fatal( 'Unable to read or parse restrictions.conf file. Reason: ' . Config::Tiny->errstr );
			$config = Config::Tiny->new();
		}
		my $q                   = $self->{'cgi'};
		my @user_groups         = keys %{ $config->{'Usergroups'} // {} };
		my @plugin_names        = keys %{ $self->{'attributes'} };
		my $member_of_usergroup = {};
		$self->{'cache'}->{'blocked_plugins'} = {};
		if ( @user_groups && $username ) {
			foreach my $group (@user_groups) {
				my @members = split( /\s*,\s*/x, $config->{'Usergroups'}->{$group} );
				foreach my $member (@members) {
					next if $member ne $username;
					$member_of_usergroup->{$group} = 1;
					last;
				}
			}
			my $db_usergroups = $self->{'datastore'}->run_query(
				'SELECT ug.description FROM users u JOIN user_group_members ugm ON u.id=ugm.user_id '
				  . 'JOIN user_groups ug ON ug.id=ugm.user_group where u.user_name=?',
				$username,
				{ fetch => 'col_arrayref' }
			);
			$member_of_usergroup->{$_} = 1 foreach @$db_usergroups;
		}
	  PLUGIN: foreach my $plugin (@plugin_names) {
			next if ( $config->{$plugin}->{'default'} // 'allow' ) ne 'deny';
			my @allowed_users      = split( /\s*,\s*/x, ( $config->{$plugin}->{'allowed_users'} // q() ) );
			my %allowed_users      = map { $_ => 1 } @allowed_users;
			my @allowed_usergroups = split( /\s*,\s*/x, ( $config->{$plugin}->{'allowed_usergroups'} // q() ) );
			my %allowed_usergroups = map { $_ => 1 } @allowed_usergroups;
			if ($username) {
				next PLUGIN if $allowed_users{$username};
				foreach my $usergroup ( keys %$member_of_usergroup ) {
					next PLUGIN if $allowed_usergroups{$usergroup};
				}
			}
			$self->{'cache'}->{'blocked_plugins'}->{$plugin} = 1;
		}
	}
	return $self->{'cache'}->{'blocked_plugins'};
}

sub _python_plugins_enabled {
	my ($self) = @_;
	my $python_config = "$self->{'config_dir'}/python_plugins.json";
	return
		 $self->{'config'}->{'python_plugin_runner_path'}
	  && $self->{'config'}->{'python_plugin_dir'}
	  && -e $python_config;
}

sub get_plugin {
	my ( $self, $plugin_name ) = @_;
	if ( $plugin_name && $self->{'plugins'}->{$plugin_name} ) {
		return $self->{'plugins'}->{$plugin_name};
	}
	BIGSdb::Exception::Plugin::Invalid->throw('Plugin does not exist');
	return;
}

sub get_plugin_attributes {
	my ( $self, $plugin_name ) = @_;
	return if !$plugin_name;
	my $att = $self->{'attributes'}->{$plugin_name};
	delete $self->{'attributes'}->{$plugin_name} if !keys %$att;
	return $att;
}

sub get_plugin_categories {
	my ( $self, $section, $dbtype, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	return if $section !~ /postquery|info/x;
	my ( @categories, %done );
	foreach (
		sort { ( $self->{'attributes'}->{$a}->{'order'} // 100 ) <=> ( $self->{'attributes'}->{$b}->{'order'} // 100 ) }
		keys %{ $self->{'attributes'} }
	  )
	{
		my $attr = $self->{'attributes'}->{$_};
		next if $attr->{'section'} !~ /$section/x;
		next if $attr->{'dbtype'}  !~ /$dbtype/x;
		next
		  if $dbtype eq 'sequences'
		  && $options->{'seqdb_type'}
		  && ( $attr->{'seqdb_type'} // q() ) !~ /$options->{'seqdb_type'}/x;
		if ( $attr->{'category'} ) {
			if ( !$done{ $attr->{'category'} } ) {
				push @categories, $attr->{'category'};
				$done{ $attr->{'category'} } = 1;
			}
		} else {
			if ( !$done{''} ) {
				push @categories, '';
				$done{''} = 1;
			}
		}
	}
	return \@categories;
}

sub _valid_section {
	my ( $self, $sections ) = @_;
	my %allowed_sections =
	  map { $_ => 1 } qw (isolate_info profile_info info postquery breakdown analysis third_party export miscellaneous);
	foreach my $section (@$sections) {
		return 1 if $allowed_sections{$section};
	}
	return;
}

sub _section_matches_plugin {
	my ( $self, $sections, $plugin_sections ) = @_;
	my @plugin_sections = split /,/x, $plugin_sections;
	foreach my $plugin_section (@plugin_sections) {
		foreach my $section (@$sections) {
			return 1 if $plugin_section eq $section;
		}
	}
	return;
}

sub _filter_schemes {
	my ( $self, $scheme_data, $plugin ) = @_;
	my $filtered = [];
	my $attr     = $self->{'attributes'}->{$plugin};
	if ( !defined $self->{'cache'}->{'scheme_locus_counts'} ) {
		$self->{'cache'}->{'scheme_locus_counts'} =
		  $self->{'datastore'}->run_query( 'SELECT scheme_id,COUNT(*) AS count FROM scheme_members GROUP BY scheme_id',
			undef, { fetch => 'all_hashref', key => 'scheme_id' } );
	}
	foreach my $scheme (@$scheme_data) {
		if ( !defined $attr->{'max_scheme_loci'} && !defined $attr->{'min_scheme_loci'} ) {
			push @$filtered, $scheme;
			next;
		}
		my $locus_count = $self->{'cache'}->{'scheme_locus_counts'}->{ $scheme->{'id'} }->{'count'};
		next if defined $attr->{'max_scheme_loci'} && $locus_count > $attr->{'max_scheme_loci'};
		next if defined $attr->{'min_scheme_loci'} && $locus_count < $attr->{'min_scheme_loci'};
		push @$filtered, $scheme;
	}
	return $filtered;
}

sub get_appropriate_plugin_names {
	my ( $self, $sections, $dbtype, $category, $options ) = @_;
	my $q = $self->{'cgi'};
	$sections = ref $sections ? $sections : [$sections];
	return if !$self->_valid_section($sections);
	my $plugins        = [];
	my $pk_scheme_list = $self->{'datastore'}->get_scheme_list( { with_pk => 1, set_id => $options->{'set_id'} } );
	my $order          = $options->{'order'} // 'order';
	my $restricted     = $self->get_restricted_plugins( $options->{'username'} );
	no warnings 'numeric';

	foreach my $plugin (
		sort {
			( $self->{'attributes'}->{$a}->{$order} // 100 ) <=> ( $self->{'attributes'}->{$b}->{$order} // 100 )
			  || lc( $self->{'attributes'}->{$a}->{$order} ) cmp lc( $self->{'attributes'}->{$b}->{$order} )
		}
		keys %{ $self->{'attributes'} }
	  )
	{
		next if $restricted->{$plugin};
		my $attr = $self->{'attributes'}->{$plugin};
		next if !$self->_has_required_item( $attr->{'requires'} );
		next if !$self->_matches_required_fields( $attr->{'requires'} );
		next if !$self->_has_required_genome( $attr->{'requires'}, $options );
		next if !$self->_matches_view( $attr->{'requires'}, $options );

		#must be a scheme with primary key and loci defined
		my $filtered_scheme_list = $self->_filter_schemes( $pk_scheme_list, $plugin );
		if ( ( $attr->{'requires'} // q() ) =~ /pk_scheme/ ) {
			next if !@$filtered_scheme_list;
		}
		next
		  if $self->{'system'}->{'dbtype'} eq 'sequences'
		  && !@$filtered_scheme_list
		  && ( $attr->{'seqdb_type'} // q() ) eq 'schemes';
		if ( $attr->{'system_flag'} ) {
			next if ( $self->{'system'}->{ $attr->{'system_flag'} } // q() ) eq 'no';
			next if $attr->{'explicit_enable'} && ( $self->{'system'}->{ $attr->{'system_flag'} } // q() ) ne 'yes';
			next
			  if (!( ( $self->{'system'}->{'all_plugins'} // q() ) eq 'yes' || $attr->{'enabled_by_default'} )
				&& ( $self->{'system'}->{ $attr->{'system_flag'} } // q() ) ne 'yes' );
		}
		next if !$self->_section_matches_plugin( $sections, $attr->{'section'} );
		next if $attr->{'dbtype'} !~ /$dbtype/x;
		next
		  if $dbtype eq 'sequences'
		  && $options->{'seqdb_type'}
		  && ( $attr->{'seqdb_type'} // q() ) !~ /$options->{'seqdb_type'}/x;
		my %possible_index_page = map { $_ => 1 } qw (index dashboard project options logout login pluginSummary);
		if (  !$q->param('page')
			|| $possible_index_page{ $q->param('page') }
			|| $self->_is_matching_category( $category, $attr->{'category'} ) )
		{
			push @$plugins, $plugin;
		}
	}
	return $plugins;
}

sub _matches_view {
	my ( $self, $requires, $options ) = @_;
	return 1 if !defined $requires;
	if ( $requires =~ /Kaptive/x ) {
		if ( $self->{'system'}->{'kaptive_view'} && $options->{'single_isolate'} ) {
			return 0
			  if !$self->{'datastore'}
			  ->is_isolate_in_view( $self->{'system'}->{'kaptive_view'}, $options->{'single_isolate'} );
		}
	}
	return 1;
}

#Check if isolate database contains fields with appropriate characteristics
sub _matches_required_fields {
	my ( $self, $requires ) = @_;
	my %require_items = map { $_ => 1 } split /,/x, ( $requires // q() );
	my $field_list    = $self->{'xmlHandler'}->get_field_list;
	my %fields        = map { $_ => 1 } @$field_list;
	my $checks        = {

		#Country field with defined option list (needed for geo-mapping plugins)
		field_country_optlist => sub {
			return if !$fields{'country'};
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes('country');
			return $thisfield->{'optlist'} ? 1 : 0;
		},

		#Year field with integer data type
		field_year_int => sub {
			return if !$fields{'year'};
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes('year');
			return $thisfield->{'type'} =~ /int/x ? 1 : 0;
		}
	};
	foreach my $check (qw (field_country_optlist field_year_int)) {
		return if $require_items{$check} && !$checks->{$check}->();
	}
	return 1;
}

sub _has_required_genome {
	my ( $self, $requires, $options ) = @_;
	return 1 if $self->{'system'}->{'dbtype'} ne 'isolates';
	my %require_items = map { $_ => 1 } split /,/x, ( $requires // q() );
	return 1 if !$require_items{'seqbin'};
	if ( $options->{'single_isolate'} ) {
		return $self->{'datastore'}
		  ->run_query( 'SELECT EXISTS(SELECT * FROM seqbin_stats WHERE isolate_id=?)', $options->{'single_isolate'} );
	} else {

		#This will be called for each plugin, so cache the result
		if ( !defined $self->{'cache'}->{'has_required_genome_all'} ) {
			$self->{'cache'}->{'has_required_genome_all'} = $self->{'datastore'}->run_query(
				"SELECT EXISTS(SELECT * FROM seqbin_stats s JOIN $self->{'system'}->{'view'} v ON s.isolate_id=v.id)");
		}
		return $self->{'cache'}->{'has_required_genome_all'};
	}
	return;
}

sub _has_required_item {
	my ( $self, $required_attr ) = @_;
	my %requires = (
		ref_db                 => 'ref_?db',
		emboss_path            => 'emboss',
		muscle_path            => 'muscle',
		clustalw_path          => 'clustalw',
		aligner                => 'aligner',
		grapetree_path         => 'GrapeTree',
		MSTree_holder_rel_path => 'GrapeTree',
		ipcress_path           => 'ipcress',
		jobs_db                => 'offline_jobs',
		itol_api_key           => 'itol_api_key',
		itol_project_name      => 'itol_project_name',
		phyloviz_user          => 'phyloviz_user',
		phyloviz_passwd        => 'phyloviz_passwd',
		microreact_token       => 'microreact_token',
		kleborate_path         => 'Kleborate',
		kaptive_path           => 'Kaptive',
		weasyprint_path        => 'weasyprint',
		reportree_path         => 'ReporTree',
		snp_sites_path         => 'snp_sites',
		rmlst_client_key       => 'rmlst_oauth',
		rmlst_client_secret    => 'rmlst_oauth',
		rmlst_access_token     => 'rmlst_oauth',
		rmlst_access_secret    => 'rmlst_oauth'
	);
	return 1 if !$required_attr;
	foreach my $config_param ( keys %requires ) {
		return
		  if !$self->{'config'}->{$config_param} && $required_attr =~ /$requires{$config_param}/x;
	}
	return 1;
}

sub _is_matching_category {
	my ( $self, $category, $plugin_category ) = @_;
	return 1 if $category eq 'none' && !$plugin_category;
	return 1 if $category eq $plugin_category;
	return;
}

sub is_plugin {
	my ( $self, $name ) = @_;
	return if !$name;
	return any { $_ eq $name } keys %{ $self->{'attributes'} };
}

sub get_installed_plugins {
	my ($self) = @_;
	return $self->{'attributes'};
}
1;
