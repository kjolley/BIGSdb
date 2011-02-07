#Written by Keith Jolley
#Copyright (c) 2010, University of Oxford
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
use List::MoreUtils qw(any none);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

sub new {
	my $class = shift;
	my $self  = {@_};
	$self->{'plugins'}    = {};
	$self->{'attributes'} = {};
	bless( $self, $class );
	$self->initiate();
	return $self;
}

sub initiate {
	my ($self) = @_;
	my @plugins;
	opendir( PLUGINDIR, "$self->{'pluginDir'}/BIGSdb/Plugins" );
	foreach ( readdir PLUGINDIR ) {
		push @plugins, $1 if /(.*)\.pm$/;
	}
	close PLUGINDIR;
	foreach (@plugins) {
		my $plugin_name = $_ if ~/^(.*)$/;    #untaint
		$plugin_name = "$plugin_name";
		eval "use BIGSdb::Plugins::$plugin_name";
		if ($@) {
			$logger->warn("$plugin_name plugin not installed properly!  $@");
		} else {
			my $plugin = "BIGSdb::Plugins::$plugin_name"->new(
				'system'           => $self->{'system'},
				'cgi'              => $self->{'cgi'},
				'instance'         => $self->{'instance'},
				'prefs'            => $self->{'prefs'},
				'prefstore'        => $self->{'prefstore'},
				'config'           => $self->{'config'},
				'datastore'        => $self->{'datastore'},
				'db'               => $self->{'db'},
				'xmlHandler'       => $self->{'xmlHandler'},
				'dataConnector'    => $self->{'dataConnector'},
				'jobManager'	   => $self->{'jobManager'},
				'mod_perl_request' => $self->{'mod_perl_request'}
			);
			$self->{'plugins'}->{$plugin_name}    = $plugin;
			$self->{'attributes'}->{$plugin_name} = $plugin->get_attributes();
		}
	}
}

#sub get_plugin_attribute_names {
#	return qw(name description menutext author affiliation email module version type section);
#}

sub get_plugin {
	my ( $self, $plugin_name ) = @_;
	if ( $self->{'plugins'}->{$plugin_name} ) {
		return $self->{'plugins'}->{$plugin_name};
	}
	throw BIGSdb::InvalidPluginException("Plugin '$plugin_name' does not exist!");
}

sub get_plugin_attributes {
	my ( $self, $plugin_name ) = @_;
	my $att = $self->{'attributes'}->{$plugin_name};
	return $att;
}

sub get_plugin_categories {
	my ( $self, $section, $dbtype ) = @_;
	return
	  if ( $section !~ /tools/
		&& $section !~ /postquery/
		&& $section !~ /stats/
		&& $section !~ /options/ );
	my ( @categories, %done );
	foreach ( sort { $self->{'attributes'}->{$a}->{'order'} <=> $self->{'attributes'}->{$b}->{'order'} } keys %{ $self->{'attributes'} } ) {
		my $attr = $self->{'attributes'}->{$_};
		next if $attr->{'section'} !~ /$section/;
		next if $attr->{'dbtype'} !~ /$dbtype/;
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
	my ( $self, $section, $dbtype, $category ) = @_;
	return if none {$section =~ /$_/} qw (postquery breakdown analysis export miscellaneous);
	my @plugins;
	foreach ( sort { $self->{'attributes'}->{$a}->{'order'} <=> $self->{'attributes'}->{$b}->{'order'} } keys %{ $self->{'attributes'} } ) {
		my $attr = $self->{'attributes'}->{$_};
		if ( $attr->{'requires'} ) {
			next
			  if !$self->{'config'}->{'chartdirector'}
				  && $attr->{'requires'} =~ /chartdirector/;
			next
			  if !$self->{'config'}->{'refdb'}
				  && $attr->{'requires'} =~ /refdb/;
			next
			  if !$self->{'config'}->{'emboss_path'}
				  && $attr->{'requires'} =~ /emboss/;
			next
			  if !$self->{'config'}->{'muscle_path'}
				  && $attr->{'requires'} =~ /muscle/;
			next
			  if !$self->{'config'}->{'mogrify_path'}
				  && $attr->{'requires'} =~ /mogrify/;
		 	next
		 	  if !$self->{'config'}->{'jobs_db'}
				  && $attr->{'requires'} =~ /offline_jobs/;
		}
		next
		  if (
			$attr->{'system_flag'}
			&& (  !$self->{'system'}->{ $attr->{'system_flag'} }
				|| $self->{'system'}->{ $attr->{'system_flag'} } eq 'no' )
		  );
		my $plugin_section = $attr->{'section'};
		next if $plugin_section !~ /$section/;	
		next if $attr->{'dbtype'} !~ /$dbtype/;	
		if (  !$self->{'cgi'}->param('page')
			|| $self->{'cgi'}->param('page') eq 'index'
			|| $self->{'cgi'}->param('page') eq 'options'
			|| $self->{'cgi'}->param('page') eq 'logout'
			|| ( $category eq 'none' && !$attr->{'category'} )
			|| $category eq $attr->{'category'} )
		{
			push @plugins, $_;
			
		}
	}
	return \@plugins;
}

sub is_plugin {
	my ( $self, $name ) = @_;
	return any { $_ eq $name } keys %{ $self->{'attributes'} };
}
1;
