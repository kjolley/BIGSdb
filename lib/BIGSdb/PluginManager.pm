#Written by Keith Jolley
#Copyright (c) 2010-2016, University of Oxford
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
package BIGSdb::PluginManager;
use strict;
use warnings;
use List::MoreUtils qw(any none);
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
				system           => $self->{'system'},
				cgi              => $self->{'cgi'},
				instance         => $self->{'instance'},
				prefs            => $self->{'prefs'},
				prefstore        => $self->{'prefstore'},
				config           => $self->{'config'},
				datastore        => $self->{'datastore'},
				db               => $self->{'db'},
				xmlHandler       => $self->{'xmlHandler'},
				dataConnector    => $self->{'dataConnector'},
				jobManager       => $self->{'jobManager'},
				mod_perl_request => $self->{'mod_perl_request'}
			);
			$self->{'plugins'}->{$plugin_name}    = $plugin;
			$self->{'attributes'}->{$plugin_name} = $plugin->get_attributes;
		}
	}
	return;
}

sub get_plugin {
	my ( $self, $plugin_name ) = @_;
	if ( $plugin_name && $self->{'plugins'}->{$plugin_name} ) {
		return $self->{'plugins'}->{$plugin_name};
	}
	throw BIGSdb::InvalidPluginException('Plugin does not exist');
}

sub get_plugin_attributes {
	my ( $self, $plugin_name ) = @_;
	return if !$plugin_name;
	my $att = $self->{'attributes'}->{$plugin_name};
	return $att;
}

sub get_plugin_categories {
	my ( $self, $section, $dbtype, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	return
	  if ( $section !~ /tools/x
		&& $section !~ /postquery/x
		&& $section !~ /stats/x
		&& $section !~ /options/x );
	my ( @categories, %done );
	foreach (
		sort { $self->{'attributes'}->{$a}->{'order'} <=> $self->{'attributes'}->{$b}->{'order'} }
		keys %{ $self->{'attributes'} }
	  )
	{
		my $attr = $self->{'attributes'}->{$_};
		next if $attr->{'section'} !~ /$section/x;
		next if $attr->{'dbtype'} !~ /$dbtype/x;
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

sub get_appropriate_plugin_names {
	my ( $self, $section, $dbtype, $category, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	return if none { $section =~ /$_/x } qw (postquery breakdown analysis export miscellaneous);
	my @plugins;
	my $pk_scheme_list = $self->{'datastore'}->get_scheme_list( { with_pk => 1, set_id => $options->{'set_id'} } );
	foreach my $plugin (
		sort { $self->{'attributes'}->{$a}->{'order'} <=> $self->{'attributes'}->{$b}->{'order'} }
		keys %{ $self->{'attributes'} }
	  )
	{
		my $attr = $self->{'attributes'}->{$plugin};
		next if !$self->_has_required_item( $attr->{'requires'} );

		#must be a scheme with primary key and loci defined
		next if !@$pk_scheme_list && ( $attr->{'requires'} // q() ) =~ /pk_scheme/;
		next
		  if $self->{'system'}->{'dbtype'} eq 'sequences'
		  && !@$pk_scheme_list
		  && ( $attr->{'seqdb_type'} // q() ) eq 'schemes';
		next
		  if (
			   !( ( $self->{'system'}->{'all_plugins'} // q() ) eq 'yes' )
			&& $attr->{'system_flag'}
			&& (  !$self->{'system'}->{ $attr->{'system_flag'} }
				|| $self->{'system'}->{ $attr->{'system_flag'} } eq 'no' )
		  );
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			next if !$self->_is_isolate_count_ok($attr);
		}
		my $plugin_section = $attr->{'section'};
		next if $plugin_section !~ /$section/x;
		next if $attr->{'dbtype'} !~ /$dbtype/x;
		next
		  if $dbtype eq 'sequences'
		  && $options->{'seqdb_type'}
		  && ( $attr->{'seqdb_type'} // q() ) !~ /$options->{'seqdb_type'}/x;
		my %possible_index_page = map { $_ => 1 } qw (index options logout login);
		if (  !$q->param('page')
			|| $possible_index_page{ $q->param('page') }
			|| $self->_is_matching_category( $category, $attr->{'category'} ) )
		{
			push @plugins, $plugin;
		}
	}
	return \@plugins;
}

sub _is_isolate_count_ok {
	my ( $self, $attr ) = @_;
	my $q = $self->{'cgi'};
	if ( !$q->param('page') || $q->param('page') eq 'index' ) {
		if ( !$self->{'cache'}->{'isolate_count'} ) {
			$self->{'cache'}->{'isolate_count'} =
			  $self->{'datastore'}->run_query("SELECT COUNT(*) FROM $self->{'system'}->{'view'}");
		}
		return if $attr->{'max'} && $self->{'cache'}->{'isolate_count'} > $attr->{'max'};
		return if $attr->{'min'} && $self->{'cache'}->{'isolate_count'} < $attr->{'min'};
	}
	return 1;
}

sub _has_required_item {
	my ( $self, $required_attr ) = @_;
	my %requires = (
		chartdirector => 'chartdirector',
		ref_db        => 'ref_?db',
		emboss_path   => 'emboss',
		muscle_path   => 'muscle',
		clustalw_path => 'clustalw',
		aligner       => 'aligner',
		mogrify_path  => 'mogrify',
		jobs_db       => 'offline_jobs'
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
