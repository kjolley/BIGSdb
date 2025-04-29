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
package BIGSdb::Plugin;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::TreeViewPage Exporter);
use BIGSdb::Exceptions;
use Try::Tiny;
use Log::Log4perl qw(get_logger);
use List::MoreUtils qw(any uniq);
use JSON;
use Encode;
use BIGSdb::Constants qw(LOCUS_PATTERN :interface);
my $logger = get_logger('BIGSdb.Plugins');
use constant SEQ_SOURCE => 'seqbin id + position';
our @EXPORT_OK = qw(SEQ_SOURCE);

#Override the following methods in subclass
sub get_initiation_values { return {} }
sub get_attributes        { return {} }
sub get_hidden_attributes { return [] }
sub get_plugin_javascript { return q() }
sub run                   { }
sub run_job               { }              #used to run offline job

sub get_javascript {
	my ($self) = @_;
	my $plugin_name = $self->{'cgi'}->param('name');
	my ( $js, $tree_js, $requires );
	my $att = $self->{'pluginManager'}->get_plugin_attributes($plugin_name);
	try {
		if ( ( $att->{'language'} // q() ) eq 'Python' ) {
			$js       = $att->{'javascript'} // q();
			$requires = $att->{'requires'}   // q();
		} else {
			$js       = $self->{'pluginManager'}->get_plugin($plugin_name)->get_plugin_javascript;
			$requires = $self->{'pluginManager'}->get_plugin($plugin_name)->get_attributes->{'requires'};
		}
		if ($requires) {
			$tree_js =
				$requires =~ /js_tree/x || $self->{'jQuery.jstree'}
			  ? $self->get_tree_javascript( { checkboxes => 1, check_schemes => 1, resizable => 1 } )
			  : q();
		} else {
			$tree_js = q();
		}
	} catch {
		if ( $_->isa('BIGSdb::Exception::Plugin::Invalid') ) {
			my $message = $plugin_name ? "Plugin $plugin_name does not exist." : 'Plugin name not called.';
			$tree_js = q();
			$logger->warn($message);
		} else {
			$logger->logdie($_);
		}
	};
	$js .= $self->get_list_javascript;
	if ( $self->{'jQuery.tablesort'} ) {
		$js .= <<"JS";
\$(document).ready(function() 
    { 
        \$(".tablesorter").tablesorter({widgets:['zebra']});       
    } 
); 	
JS
	}
	$js .= $tree_js;
	return $js;
}

sub get_job_redirect {
	my ( $self, $job_id ) = @_;
	my $buffer = <<"REDIRECT";
<div class="box" id="resultspanel">
<p>This job has been submitted to the queue.</p>
<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=job&amp;id=$job_id">
Follow the progress of this job and view the output.</a></p></div>
<script type="text/javascript">
setTimeout(function(){
	window.location = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=job&id=$job_id";
}, 2000);
</script>
REDIRECT
	return $buffer;
}

sub get_query {
	my ( $self, $query_file ) = @_;
	my $qry;
	my $view = $self->{'system'}->{'view'};
	if ( !$query_file ) {
		$qry = "SELECT * FROM $view WHERE new_version IS NULL ORDER BY id";
	} else {
		if ( -e "$self->{'config'}->{'secure_tmp_dir'}/$query_file" ) {
			if ( $query_file =~ /^([^\/]+)$/x ) {    #Untaint - no directory traversal
				$query_file = $1;
			}
			my $fh;
			if ( open( $fh, '<:encoding(utf8)', "$self->{'config'}->{'secure_tmp_dir'}/$query_file" ) ) {
				$qry = <$fh>;
				close $fh;
			} else {
				if ( $self->{'cgi'}->param('format') eq 'text' ) {
					say 'Cannot open temporary file.';
				} else {
					$self->print_bad_status( { message => q(Cannot open temporary file.) } );
				}
				$logger->error($@);
				return;
			}
		} else {
			if ( $self->{'cgi'}->param('format') eq 'text' ) {
				say 'The temporary file containing your query does not exist. Please repeat your query.';
			} else {
				$self->print_bad_status(
					{
						message => q(The temporary file containing your query does not exist. )
						  . q(Please repeat your query.)
					}
				);
			}
			return;
		}
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$qry =~ s/([\s\(])datestamp/$1$view.datestamp/gx;
		$qry =~ s/([\s\(])date_entered/$1$view.date_entered/gx;
	}
	return \$qry;
}

sub delete_temp_files {
	my ( $self, $wildcard ) = @_;
	my @files = glob("$self->{'config'}->{'secure_tmp_dir'}/$wildcard");
	foreach (@files) { unlink $1 if /^(.*BIGSdb.*)$/x }
	return;
}

sub print_content {
	my ($self)      = @_;
	my $q           = $self->{'cgi'};
	my $plugin_name = $q->param('name');
	if ( !$self->{'pluginManager'}->is_plugin($plugin_name) ) {
		my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
		say qq(<h1>$desc</h1>);
		$self->print_bad_status( { message => q(Invalid (or no) plugin called.), navbar => 1 } );
		return;
	}
	my $att    = $self->{'pluginManager'}->get_plugin_attributes($plugin_name);
	my $dbtype = $self->{'system'}->{'dbtype'};
	if ( $att->{'dbtype'} !~ /$dbtype/x ) {
		say q(<h1>Incompatible plugin</h1>);
		$self->print_bad_status(
			{
				message => qq(This plugin is not compatible with this type of database ($dbtype).),
				navbar  => 1
			}
		);
		return;
	}
	my $blocked_plugins = $self->{'pluginManager'}->get_restricted_plugins( $self->{'username'} );
	if ( $blocked_plugins->{$plugin_name} ) {
		say q(<h1>Restricted plugin</h1>);
		$self->print_bad_status(
			{
				message => q(This plugin has restricted access. Make sure you are logged )
				  . q(in with an account that has appropriate permissions to access this plugin.),
				navbar => 1
			}
		);
		return;
	}
	if ( $att->{'language'} eq 'Python' ) {
		my $args      = { username => $self->{'username'} };
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		$args->{'email'} = $user_info->{'email'} if defined $user_info->{'email'};
		my $set_id = $self->get_set_id;
		$args->{'set_id'}                      = $set_id           if defined $set_id;
		$args->{'curate'}                      = $self->{'curate'} if $self->{'curate'};
		$args->{'guid'}                        = $self->get_guid;
		$args->{'cgi_params'}                  = { %{ $q->Vars } };    #Shallow copy
		$args->{'cgi_params'}->{'remote_host'} = $q->remote_host;

		foreach my $key ( keys %{ $args->{'cgi_params'} } ) {
			if ( $args->{'cgi_params'}->{$key} =~ /\x{0000}/x ) {
				my $value_string = $args->{'cgi_params'}->{$key};
				$args->{'cgi_params'}->{$key} = [ split /\x{0000}/x, $value_string ];
				foreach my $value ( @{ $args->{'cgi_params'}->{$key} } ) {
					if ( BIGSdb::Utils::is_int($value) ) {
						$value = int($value);
					}
				}
			}
		}
		my $arg_file     = $self->_make_arg_file($args);
		my $appender     = Log::Log4perl->appender_by_name('A1');
		my $log_filename = $appender->{'filename'} // '/var/log/bigsdb.log';
		my $command =
			"$self->{'config'}->{'python_plugin_runner_path'} --database $self->{'instance'} "
		  . "--module $plugin_name --module_dir $self->{'config'}->{'python_plugin_dir'} --arg_file $arg_file "
		  . "--log_file $log_filename";
		my $output = `$command`;
		$output = Encode::decode( 'utf8', $output );
		say $output;
		return;
	}
	my $plugin = $self->{'pluginManager'}->get_plugin($plugin_name);
	$plugin->{'username'} = $self->{'username'};
	$plugin->initiate_prefs;
	$plugin->initiate_view( $self->{'username'} );
	$plugin->run;
	return;
}

sub _make_arg_file {
	my ( $self, $data ) = @_;
	my ( $filename, $full_file_path );
	do {
		$filename       = BIGSdb::Utils::get_random();
		$full_file_path = "$self->{'config'}->{'secure_tmp_dir'}/$filename";
	} while ( -e $full_file_path );
	my $json = encode_json($data);
	open( my $fh, '>:encoding(utf8)', $full_file_path ) || $logger->error("Can't open $full_file_path for writing");
	say $fh $json;
	close $fh;
	return $filename;
}

sub get_title {
	my ($self)      = @_;
	my $desc        = $self->get_db_description || 'BIGSdb';
	my $plugin_name = $self->{'cgi'}->param('name');
	my $att         = $self->{'pluginManager'}->get_plugin_attributes($plugin_name);
	if ( $att->{'menutext'} ) {
		return "$att->{'menutext'} - $desc";
	}
	return $desc;
}

sub print_isolate_fields_fieldset {
	my ( $self, $options ) = @_;
	my $set_id         = $self->get_set_id;
	my $is_curator     = $self->is_curator;
	my $fields         = $self->{'xmlHandler'}->get_field_list( { no_curate_only => !$is_curator } );
	my $display_fields = [];
	my $labels         = {};
	my @group_list     = split /,/x, ( $self->{'system'}->{'field_groups'} // q() );
	my $group_members  = {};
	my $attributes     = $self->{'xmlHandler'}->get_all_field_attributes;

	foreach my $field (@$fields) {
		if ( $attributes->{$field}->{'group'} ) {
			push @{ $group_members->{ $attributes->{$field}->{'group'} } }, $field;
		} else {
			push @{ $group_members->{'General'} }, $field;
		}
		my $label = $field;
		$label =~ tr/_/ /;
		$labels->{$field} = $label;
		if ( $field eq $self->{'system'}->{'labelfield'} && !$options->{'no_aliases'} ) {
			push @{ $group_members->{'General'} }, 'aliases';
		}
		if ( $options->{'extended_attributes'} ) {
			my $extended = $self->get_extended_attributes;
			my $extatt   = $extended->{$field};
			if ( ref $extatt eq 'ARRAY' ) {
				foreach my $extended_attribute (@$extatt) {
					if ( $attributes->{$field}->{'group'} ) {
						push @{ $group_members->{ $attributes->{$field}->{'group'} } },
						  "${field}___$extended_attribute";
					} else {
						push @{ $group_members->{'General'} }, "${field}___$extended_attribute";
					}
					( $labels->{"${field}___$extended_attribute"} = $extended_attribute ) =~ tr/_/ /;
				}
			}
		}
	}
	my $q = $self->{'cgi'};
	foreach my $group ( undef, @group_list ) {
		my $name = $group // 'General';
		$name =~ s/\|.+$//x;
		if ( ref $group_members->{$name} ) {
			push @$display_fields,
			  $q->optgroup( -name => $name, -values => $group_members->{$name}, -labels => $labels );
		}
	}
	say q(<fieldset style="float:left"><legend>Provenance fields</legend>);
	say $q->scrolling_list(
		-name     => 'fields',
		-id       => 'fields',
		-values   => $display_fields,
		-labels   => $labels,
		-multiple => 'true',
		-size     => $options->{'size'} // 8,
		-default  => $options->{'default'}
	);
	if ( !$options->{'no_all_none'} ) {
		say q(<div style="text-align:center">);
		say q(<input type="button" onclick='listbox_selectall("fields",true)' )
		  . q(value="All" style="margin-top:1em" class="small_submit" /><input type="button" )
		  . q(onclick='listbox_selectall("fields",false)' value="None" style="margin:1em 0 0 0.2em" class="small_submit" />);
		say q(</div>);
	}
	say q(</fieldset>);
	return;
}

sub print_eav_fields_fieldset {
	my ( $self, $options ) = @_;
	my $eav_fields = $self->{'datastore'}->get_eav_fields;
	return if !@$eav_fields;
	my @group_list = split /,/x, ( $self->{'system'}->{'eav_groups'} // q() );
	my $values     = [];
	my $labels     = {};
	my $q          = $self->{'cgi'};
	if (@group_list) {
		my $eav_groups    = { map { $_->{'field'} => $_->{'category'} } @$eav_fields };
		my $group_members = {};
		foreach my $eav_field (@$eav_fields) {
			my $fieldname = $eav_field->{'field'};
			( $labels->{$fieldname} = $fieldname ) =~ tr/_/ /;
			if ( $eav_groups->{$fieldname} ) {
				push @{ $group_members->{ $eav_groups->{$fieldname} } }, $fieldname;
			} else {
				push @{ $group_members->{'General'} }, $fieldname;
			}
		}
		foreach my $group ( undef, @group_list ) {
			my $name = $group // 'General';
			$name =~ s/\|.+$//x;
			if ( ref $group_members->{$name} ) {
				push @$values, $q->optgroup( -name => $name, -values => $group_members->{$name}, -labels => $labels );
			}
		}
	} else {
		$values = $self->{'datastore'}->get_eav_fieldnames;
	}
	my $legend  = $self->{'system'}->{'eav_fields'} // 'Secondary metadata';
	my $display = $options->{'hide'} ? 'none' : 'block';
	say qq(<fieldset id="eav_fieldset" style="float:left;display:$display"><legend>$legend</legend>);
	say $q->scrolling_list(
		-name     => 'eav_fields',
		-id       => 'eav_fields',
		-values   => $values,
		-labels   => $labels,
		-multiple => 'true',
		-size     => $options->{'size'} // 8
	);
	if ( !$options->{'no_all_none'} ) {
		say q(<div style="text-align:center"><input type="button" onclick='listbox_selectall("eav_fields",true)' )
		  . q(value="All" style="margin-top:1em" class="small_submit" /><input type="button" )
		  . q(onclick='listbox_selectall("eav_fields",false)' value="None" style="margin:1em 0 0 0.2em" )
		  . q(class="small_submit" /></div>);
	}
	say q(</fieldset>);
	$self->{'eav_fieldset'} = 1;
	return;
}

sub print_composite_fields_fieldset {
	my ( $self, $options ) = @_;
	my $composites =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id FROM composite_fields ORDER BY id', undef, { fetch => 'col_arrayref' } );
	return if !@$composites;
	my $labels = {};
	foreach my $field (@$composites) {
		( $labels->{$field} = $field ) =~ tr/_/ /;
	}
	my $display = $options->{'hide'} ? 'none' : 'block';
	say qq(<fieldset id="composite_fieldset" style="float:left;display:$display">)
	  . q(<legend>Composite fields</legend>);
	say $self->popup_menu(
		-name     => 'composite_fields',
		-id       => 'composite_fields',
		-values   => $composites,
		-labels   => $labels,
		-multiple => 'true',
		-class    => 'multiselect'
	);
	say $self->get_tooltip( q(Composite fields - These are constructed from combinations of )
		  . q(other fields (some of which may come from external databases). Including composite fields )
		  . q(will slow down the processing.) );
	say q(</fieldset>);
	$self->{'composite_fieldset'} = 1;
	return;
}

sub set_offline_view {
	my ( $self, $params ) = @_;
	my $set_id = $params->{'set_id'};
	if ( ( $self->{'system'}->{'view'} // '' ) eq 'isolates' && $set_id ) {
		my $view = $self->{'datastore'}->run_query( 'SELECT view FROM set_view WHERE set_id=?', $set_id );
		$self->{'system'}->{'view'} = $view if defined $view;
	}
	return;
}

sub get_id_list {
	my ( $self, $pk, $query_file ) = @_;
	my $q = $self->{'cgi'};
	my $list;
	if ( $q->param('list') ) {
		foreach ( split /\n/x, $q->param('list') ) {
			$_ =~ s/\s*$//x;
			push @$list, $_;
		}
	} elsif ($query_file) {
		my $qry_ref = $self->get_query($query_file);
		return if ref $qry_ref ne 'SCALAR';
		return if !$self->create_temp_tables($qry_ref);
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			my $view = $self->{'system'}->{'view'};
			$$qry_ref =~ s/SELECT\ ($view\.\*|\*)/SELECT $view\.$pk/x;
			$self->rewrite_query_ref_order_by($qry_ref);
		}
		$list = $self->{'datastore'}->run_query( $$qry_ref, undef, { fetch => 'col_arrayref' } );
	} else {
		$list = [];
	}
	return $list;
}

sub get_allele_id_list {
	my ( $self, $query_file, $list_file ) = @_;
	if ($list_file) {
		$self->{'datastore'}->create_temp_list_table( 'text', $list_file );
	}
	if ($query_file) {
		my $qry_ref = $self->get_query($query_file);
		return if ref $qry_ref ne 'SCALAR';
		$$qry_ref =~ s/\*/allele_id/x;
		my $ids = $self->{'datastore'}->run_query( $$qry_ref, undef, { fetch => 'col_arrayref' } );
		return $ids;
	}
	return [];
}

sub get_selected_fields {
	my ( $self, $options ) = @_;
	my $q          = $self->{'cgi'};
	my $fields     = [];
	my @provenance = $q->multi_param('fields');
	push @$fields, qq(f_$_) foreach @provenance;
	if ( $q->param('eav_fields') ) {
		my @eav_fields = $q->multi_param('eav_fields');
		foreach my $eav_field (@eav_fields) {
			push @$fields, "eav_$eav_field";
		}
	}
	my @composite = $q->multi_param('composite_fields');
	push @$fields, qq(c_$_) foreach @composite;
	my $set_id        = $self->get_set_id;
	my $loci          = $self->{'datastore'}->get_loci( { set_id => $set_id } );
	my $selected_loci = $self->get_selected_loci($options);
	my ( $pasted_cleaned_loci, $invalid_loci ) = $self->get_loci_from_pasted_list( { dont_clear => 1 } );
	push @$selected_loci, @$pasted_cleaned_loci;
	my %selected_loci = map { $_ => 1 } @$selected_loci;
	my %locus_seen;
	my $locus_extended_attributes = {};

	if ( $options->{'locus_extended_attributes'} ) {
		foreach my $selected (@$selected_loci) {
			if ( $selected =~ /^lex_(.+)\|\|/x ) {
				push @{ $locus_extended_attributes->{$1} }, $selected;
			}
		}
	}
	foreach my $locus (@$loci) {
		if ( $selected_loci{$locus} ) {
			push @$fields, "l_$locus";
			$locus_seen{$locus} = 1;
		}
		if ( $options->{'locus_extended_attributes'} && defined $locus_extended_attributes->{$locus} ) {
			push @$fields, @{ $locus_extended_attributes->{$locus} };
		}
	}
	my $schemes =
	  $self->{'datastore'}->run_query( 'SELECT id FROM schemes', undef, { fetch => 'col_arrayref' } );
	my $lincode_prefixes = {};
	if ( $q->param('lincode_prefixes') ) {
		my @prefixes = $q->multi_param('lincode_prefixes');
		foreach my $prefix (@prefixes) {
			if ( $prefix =~ /^linp_(\d+)_/x ) {
				push @{ $lincode_prefixes->{$1} }, $prefix;
			}
		}
	}
	foreach my $scheme_id (@$schemes) {
		my $scheme_info    = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		my $scheme_members = $self->{'datastore'}->get_scheme_loci($scheme_id);
		foreach my $member (@$scheme_members) {
			if ( $q->param("s_$scheme_id") && $q->param('scheme_members') ) {
				next if $locus_seen{$member};
				push @$fields, "s_$scheme_id\_l_$member";
				$locus_seen{$member} = 1;
			}
		}
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		foreach my $scheme_field (@$scheme_fields) {
			if ( $q->param("s_$scheme_id") && $q->param('scheme_fields') ) {
				push @$fields, "s_${scheme_id}_f_$scheme_field";
				if (   $scheme_field eq ( $scheme_info->{'primary_key'} // q() )
					&& $self->{'datastore'}->are_lincodes_defined($scheme_id) )
				{
					push @$fields, "lin_$scheme_id" if $options->{'lincodes'};
					next if !$options->{'lincode_fields'};
					my $lincode_fields =
					  $self->{'datastore'}
					  ->run_query( 'SELECT field FROM lincode_fields WHERE scheme_id=? ORDER BY display_order,field',
						$scheme_id, { fetch => 'col_arrayref' } );
					push @$fields, "lin_${scheme_id}_$_" foreach @$lincode_fields;
				}
			}
		}
		push @$fields, @{ $lincode_prefixes->{$scheme_id} }
		  if $options->{'lincode_prefixes'} && defined $lincode_prefixes->{$scheme_id};
	}
	$self->_process_selected_classification_schemes($fields);
	$self->_process_selected_analysis_fields( $options, $fields );
	return $fields;
}

sub _process_selected_classification_schemes {
	my ( $self, $fields ) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('classification_schemes') ) {
		my @cschemes = $q->multi_param('classification_schemes');
		foreach my $cs (@cschemes) {
			push @$fields, "cs_$cs";
		}
	}
	return;
}

sub _process_selected_analysis_fields {
	my ( $self, $options, $fields ) = @_;
	return if !$options->{'analysis_fields'};
	my $q               = $self->{'cgi'};
	my @analysis_fields = $q->multi_param('analysis_fields');
	push @$fields, @analysis_fields;
	return;
}

sub check_id_list {
	my ( $self, $list ) = @_;
	my $invalid = [];
	my $valid   = [];
	my $valid_id_list =
	  $self->{'datastore'}
	  ->run_query( "SELECT id FROM $self->{'system'}->{'view'}", undef, { fetch => 'col_arrayref' } );
	my %valid_ids = map { $_ => 1 } @$valid_id_list;
	foreach my $id (@$list) {
		$id =~ s/^\s*//x;
		$id =~ s/\s*$//x;
		if ( $valid_ids{$id} ) {
			push @$valid, $id;
		} else {
			push @$invalid, $id;
		}
	}
	return ( $valid, $invalid );
}

sub print_id_fieldset {
	my ( $self, $options ) = @_;
	$options->{'fieldname'} //= 'id';
	my $list = $options->{'list'} // [];
	my $q    = $self->{'cgi'};
	say qq(<fieldset style="float:left"><legend>Select $options->{'fieldname'}s</legend>);
	local $" = "\n";
	say q(<p style="padding-right:2em">Paste in list of ids to include, start a new<br />) . q(line for each.);
	say q( Leave blank to include all ids.) if !$options->{'no_leave_blank'};
	say q(</p>);
	@$list = uniq @$list;
	say $q->textarea( -name => 'list', -rows => 5, -cols => 25, -default => "@$list" );
	say q(</fieldset>);
	return;
}

sub has_set_changed {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $set_id = $self->get_set_id;
	if ( $q->param('set_id') && $set_id ) {
		if ( $q->param('set_id') != $set_id ) {
			$self->print_bad_status(
				{
					message => q(The dataset has been changed since this )
					  . q(plugin was started. Please repeat the query.)
				}
			);
			return 1;
		}
	}
	return;
}

sub print_includes_fieldset {
	my ( $self, $options ) = @_;
	my $set_id = $self->get_set_id;
	my $q      = $self->{'cgi'};
	my $title  = $options->{'title'} // 'Include fields';
	say qq(<div class="scrollable"><fieldset><legend>$title</legend>);
	say qq(<p>$options->{'description'}</p>) if $options->{'description'};
	my ( $fields, $labels ) = $self->get_field_selection_list(
		{
			query_pref    => 0,
			analysis_pref => 1,
			%$options,
			set_id => $set_id
		}
	);
	my $group_members    = {};
	my $values           = [];
	my %skip_fields      = map { $_ => 1 } qw (id datestamp date_entered curator sender);
	my $attributes       = $self->{'xmlHandler'}->get_all_field_attributes;
	my $eav_fields       = $self->{'datastore'}->get_eav_fields;
	my $eav_field_groups = { map { $_->{'field'} => $_->{'category'} } @$eav_fields };
	my %hide_field       = map { $_ => 1 } ( split /,/x, ( $options->{'hide'} // q() ) );

	foreach my $field (@$fields) {
		next if $field eq 'f_id';
		next if $hide_field{$field};
		if ( $field =~ /^(?:s)_/x ) {
			push @{ $group_members->{'Schemes'} }, $field;
		}
		if ( $field =~ /^(?:lin)_/x ) {
			push @{ $group_members->{'LINcodes'} }, $field;
		}
		if ( $field =~ /^(?:l|cn)_/x ) {
			push @{ $group_members->{'Loci'} }, $field;
		}
		if ( $field =~ /^af_/x ) {
			push @{ $group_members->{'Analysis fields'} }, $field;
		}
		if ( $field =~ /^(?:f|e|gp)_/x ) {
			( my $stripped_field = $field ) =~ s/^[f|e]_//x;
			next if $skip_fields{$stripped_field};
			$stripped_field =~ s/[\|\||\s].+$//x;
			if ( $attributes->{$stripped_field}->{'group'} ) {
				push @{ $group_members->{ $attributes->{$stripped_field}->{'group'} } }, $field;
			} else {
				push @{ $group_members->{'General'} }, $field;
			}
		}
		if ( $field =~ /^eav_/x ) {
			( my $stripped_field = $field ) =~ s/^eav_//x;
			if ( $eav_field_groups->{$stripped_field} ) {
				push @{ $group_members->{ $eav_field_groups->{$stripped_field} } }, $field;
			} else {
				push @{ $group_members->{'General'} }, $field;
			}
		}
		if ( $field =~ /^cg_/x ) {
			push @{ $group_members->{'Classification schemes'} }, $field;
		}
	}
	my @group_list = split /,/x, ( $self->{'system'}->{'field_groups'} // q() );
	my @eav_groups = split /,/x, ( $self->{'system'}->{'eav_groups'}   // q() );
	push @group_list, @eav_groups       if @eav_groups;
	push @group_list, 'Analysis fields' if defined $group_members->{'Analysis fields'};
	push @group_list, ( 'Loci', 'Schemes', 'LINcodes', 'Classification schemes' );
	foreach my $group ( undef, @group_list ) {
		my $name = $group // 'General';
		$name =~ s/\|.+$//x;
		if ( ref $group_members->{$name} ) {
			push @$values, $q->optgroup( -name => $name, -values => $group_members->{$name}, -labels => $labels );
		}
	}
	if ( $options->{'additional'} ) {
		push @$values, $q->optgroup( -name => 'Miscellaneous', -values => $options->{'additional'} );
	}
	my $name = $options->{'name'} // 'include_fields';
	my $id   = $options->{'id'}   // $name;
	say $q->scrolling_list(
		-name     => $name,
		-id       => $id,
		-values   => $values,
		-labels   => $labels,
		-multiple => 'true',
		-size     => $options->{'size'} // 6,
		-default  => $options->{'preselect'},
		-style    => 'min-width:10em;width:20em;resize:both'
	);
	say q(</fieldset></div>);
	return;
}

sub print_scheme_locus_fieldset {
	my ( $self, $scheme_id, $options ) = @_;
	my $locus_list = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $set_id     = $self->get_set_id;
	my %labels;
	( $labels{$_} = $self->clean_locus( $_, { text_output => 1 } ) ) foreach @$locus_list;
	say q(<fieldset style="float:left"><legend>Select loci</legend>);
	if (@$locus_list) {
		print $self->{'cgi'}->scrolling_list(
			-name     => 'locus',
			-id       => 'locus',
			-values   => $locus_list,
			-labels   => \%labels,
			-size     => 8,
			-multiple => 'true'
		);
		if ( !$options->{'no_all_none'} ) {
			say q(<div style="text-align:center"><input type="button" onclick='listbox_selectall("locus",true)' )
			  . q(value="All" style="margin-top:1em" class="small_submit" /><input type="button" )
			  . q(onclick='listbox_selectall("locus",false)' value="None" style="margin:1em 0 0 0.2em" )
			  . q(class="small_submit" /></div>);
		}
	} else {
		say q(No loci available<br />for analysis);
	}
	say q(</fieldset>);
	return;
}

sub print_scheme_fieldset {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $analysis_pref = $options->{'analysis_pref'} // 1;
	my $q             = $self->{'cgi'};
	say q(<fieldset id="scheme_fieldset" style="float:left"><legend>Schemes</legend>)
	  . q(<noscript><p class="highlight">Enable Javascript to select schemes.</p></noscript>)
	  . q(<div id="tree" class="tree" style="height:14em;width:20em">);
	say $self->get_tree( undef, { no_link_out => 1, select_schemes => 1, analysis_pref => $analysis_pref } );
	say q(</div>);
	if ( $options->{'fields_or_loci'} ) {
		say q(<div style="padding-top:1em"><ul><li>);
		say $q->checkbox(
			-name    => 'scheme_fields',
			-label   => 'Include all fields from selected schemes',
			-checked => 1
		);
		say q(</li><li>);
		say $q->checkbox(
			-name    => 'scheme_members',
			-label   => 'Include all loci from selected schemes',
			-checked => 1
		);
		say q(</li></ul></div>);
	}
	say q(</fieldset>);
	return;
}

sub print_sequence_filter_fieldset {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	say q(<fieldset style="float:left"><legend>Filter by</legend><ul>);
	my $buffer = $self->get_sequence_method_filter( { class => 'parameter' } );
	say qq(<li>$buffer</li>) if $buffer;
	$buffer = $self->get_project_filter( { class => 'parameter' } );
	say qq(<li>$buffer</li>) if $buffer;
	if ( $options->{'min_length'} ) {
		$buffer = $self->get_filter(
			'min_length',
			[qw (100 200 500 1000 2000 5000 10000 20000 50000 100000)],
			{
				text    => 'Minimum length',
				tooltip => 'minimum length filter - Only include sequences that are '
				  . 'longer or equal to the specified length.',
				class => 'parameter'
			}
		);
		say qq(<li>$buffer</li>);
	}
	say q(</ul></fieldset>);
	return;
}

sub filter_list_to_ids {
	my ( $self, $list ) = @_;
	my $returned_list = [];
	foreach my $value (@$list) {
		push @$returned_list, $value if BIGSdb::Utils::is_int($value);
	}
	return $returned_list;
}

sub filter_ids_by_project {
	my ( $self, $ids, $project_id ) = @_;
	return $ids if !$project_id;
	return $ids if !BIGSdb::Utils::is_int($project_id);
	my $ids_in_project = $self->{'datastore'}->run_query( 'SELECT isolate_id FROM project_members WHERE project_id=?',
		$project_id, { fetch => 'col_arrayref' } );
	my @filtered_ids;
	foreach my $id (@$ids) {
		push @filtered_ids, $id if any { $id eq $_ } @$ids_in_project;
	}
	return \@filtered_ids;
}

sub get_selected_loci {
	my ( $self, $options ) = @_;
	$self->escape_params;
	my @loci = $self->{'cgi'}->multi_param('locus');
	my @loci_selected;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $pattern = LOCUS_PATTERN;
		foreach my $locus (@loci) {
			my $locus_name = $locus =~ /$pattern/x ? $1 : undef;
			push @loci_selected, $locus_name if defined $locus_name;
			if ( $options->{'locus_extended_attributes'} ) {
				push @loci_selected, $locus if $locus =~ /^lex_/x;
			}
		}
	} else {
		@loci_selected = @loci;
	}
	return \@loci_selected;
}

sub add_scheme_loci {

	#Merge scheme loci into locus arrayref.  This deletes CGI params so don't call more than once.
	my ( $self, $loci ) = @_;
	my $q          = $self->{'cgi'};
	my $scheme_ids = $self->{'datastore'}->run_query( 'SELECT id FROM schemes', undef, { fetch => 'col_arrayref' } );
	push @$scheme_ids, 0;
	my @selected_schemes;
	$self->{'cite_schemes'} = [];
	foreach my $scheme_id (@$scheme_ids) {
		next if !$q->param("s_$scheme_id");
		push @selected_schemes, $scheme_id;
		$q->delete("s_$scheme_id");
		if ( $self->should_scheme_be_cited($scheme_id) ) {
			push @{ $self->{'cite_schemes'} }, $scheme_id;
		}
	}
	my %locus_selected = map { $_ => 1 } @$loci;
	my $set_id         = $self->get_set_id;
	foreach my $scheme_id (@selected_schemes) {
		my $scheme_loci =
			$scheme_id
		  ? $self->{'datastore'}->get_scheme_loci($scheme_id)
		  : $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
		foreach my $locus (@$scheme_loci) {
			if ( !$locus_selected{$locus} ) {
				push @$loci, $locus;
				$locus_selected{$locus} = 1;
			}
		}
	}
	return;
}

sub should_scheme_be_cited {
	my ( $self, $scheme_id ) = @_;
	return $self->{'datastore'}->run_query(
		'SELECT EXISTS(SELECT * FROM scheme_flags WHERE (scheme_id,flag)=(?,?))',
		[ $scheme_id, 'please cite' ],
		{ cache => 'Plugin::should_scheme_be_cited' }
	);
}

sub order_loci {

	#Reorder loci by scheme member order (if seqdefdb), genome order then by name (genome order may not be set)
	my ( $self, $loci, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my %loci = map { $_ => 1 } @$loci;
	my $qry;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' || !$options->{'scheme_id'} ) {
		$qry = 'SELECT id FROM loci ORDER BY genome_position,id';
	} else {
		$logger->logdie('Invalid scheme_id passed.') if !BIGSdb::Utils::is_int( $options->{'scheme_id'} );
		$qry = 'SELECT id FROM loci INNER JOIN scheme_members ON loci.id=scheme_members.locus AND '
		  . "scheme_id=$options->{'scheme_id'} ORDER BY field_order,genome_position,id";
	}
	my $ordered = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	my @list;
	foreach my $locus (@$ordered) {
		push @list, $locus if $loci{$locus};
	}
	return \@list;
}

#Set CGI param from scheme tree selections for passing to offline job.
sub set_scheme_param {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $scheme_ids = $self->{'datastore'}->run_query( 'SELECT id FROM schemes', undef, { fetch => 'col_arrayref' } );
	push @$scheme_ids, 0;
	my @selected_schemes;
	foreach (@$scheme_ids) {
		next if !$q->param("s_$_");
		push @selected_schemes, $_;
		$q->delete("s_$_");
	}
	local $" = '||';
	my $scheme_string = "@selected_schemes";
	$q->param( 'scheme', $scheme_string );
	return;
}

sub get_ids_from_query {
	my ( $self, $qry_ref ) = @_;
	return if ref $qry_ref ne 'SCALAR';
	my $qry = $$qry_ref;
	$qry =~ s/ORDER\ BY.*$//gx;
	return if !$self->create_temp_tables($qry_ref);
	my $view = $self->{'system'}->{'view'};
	$qry =~ s/SELECT\ ($view\.\*|\*)/SELECT id/x;
	$qry .= " ORDER BY $view.id";
	my $ids = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	return $ids;
}

sub write_list_file {
	my ( $self, $list ) = @_;
	my $list_file = BIGSdb::Utils::get_random() . '.list';
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$list_file";
	open( my $fh, '>:encoding(utf8)', $full_path ) || $logger->error("Can't open $full_path for writing");
	say $fh $_ foreach @$list;
	close $fh;
	my $q = $self->{'cgi'};
	$q->param( list_file => $list_file );
	return;
}

sub escape_params {
	my ($self)      = @_;
	my $q           = $self->{'cgi'};
	my @param_names = $q->param;
	my %escapes     = (
		'__prime__' => q('),
		'__slash__' => q(\\),
		'__comma__' => q(,),
		'__space__' => q( ),
		'_OPEN_'    => q[(],
		'_CLOSE_'   => q[)],
		'_GT_'      => q(>)
	);
	foreach my $param_name (@param_names) {
		my $key = $param_name;
		if ( any { $param_name =~ /$_/x } keys %escapes ) {
			foreach my $escape_string ( keys %escapes ) {
				$key =~ s/$escape_string/$escapes{$escape_string}/gx;
			}
			$q->param( $key, $q->param($param_name) );
		}
	}
	return;
}

sub get_scheme_field_values {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $scheme_id, $field ) = @{$args}{qw(isolate_id scheme_id field )};
	return if !BIGSdb::Utils::is_int($isolate_id);
	if ( !$self->{'scheme_field_table'}->{$scheme_id} ) {
		try {
			$self->{'scheme_field_table'}->{$scheme_id} =
			  $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
		} catch {
			if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
				$logger->error('Cannot copy data to temporary table.');
			} else {
				$logger->logdie($_);
			}
		};
	}
	my $values =
	  $self->{'datastore'}
	  ->run_query( "SELECT $field FROM $self->{'scheme_field_table'}->{$scheme_id} WHERE id=? ORDER BY $field",
		$isolate_id, { fetch => 'col_arrayref', cache => "Plugin::get_scheme_field_values::${scheme_id}::$field" } );
	no warnings 'uninitialized';    #Values most probably include undef
	@$values = uniq @$values;
	return $values;
}

sub get_cscheme_value {
	my ( $self, $isolate_id, $cscheme_id ) = @_;
	if ( !$self->{'cache'}->{'cscheme_cache_table_exists'}->{$cscheme_id} ) {
		my $scheme_id =
		  $self->{'datastore'}->run_query( 'SELECT scheme_id FROM classification_schemes WHERE id=?', $cscheme_id );
		$self->{'cache'}->{'cscheme_scheme_info'}->{$cscheme_id}->{'scheme_id'} = $scheme_id;
		$self->{'cache'}->{'cscheme_cache_table_exists'}->{$cscheme_id} =
		  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)',
			["temp_isolates_scheme_fields_$scheme_id"] );
	}
	my $value = q();
	if ( $self->{'cache'}->{'cscheme_cache_table_exists'}->{$cscheme_id} ) {
		if ( !$self->{'cache'}->{'cscheme_scheme_info'}->{$cscheme_id}->{'pk'} ) {
			my $scheme_id    = $self->{'cache'}->{'cscheme_scheme_info'}->{$cscheme_id}->{'scheme_id'};
			my $scheme_info  = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
			my $scheme_table = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
			$self->{'cache'}->{'cscheme_scheme_info'}->{$cscheme_id}->{'table'} =
			  $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
			$self->{'cache'}->{'cscheme_scheme_info'}->{$cscheme_id}->{'pk'} = $scheme_info->{'primary_key'};
		}
		my $scheme_id    = $self->{'cache'}->{'cscheme_scheme_info'}->{$cscheme_id}->{'scheme_id'};
		my $scheme_table = $self->{'cache'}->{'cscheme_scheme_info'}->{$cscheme_id}->{'table'};
		my $pk           = $self->{'cache'}->{'cscheme_scheme_info'}->{$cscheme_id}->{'pk'};
		my $pk_values    = $self->{'datastore'}->run_query( "SELECT $pk FROM $scheme_table WHERE id=?",
			$isolate_id, { fetch => 'col_arrayref', cache => "Plugin::cscheme::$scheme_id" } );
		if (@$pk_values) {
			my $cscheme_table = $self->{'datastore'}->create_temp_cscheme_table($cscheme_id);
			my $view          = $self->{'system'}->{'view'};

			#You may get multiple groups if you have a mixed sample
			my @groups = ();
			foreach my $pk_value (@$pk_values) {
				my $groups = $self->{'datastore'}->run_query( "SELECT group_id FROM $cscheme_table WHERE profile_id=?",
					$pk_value, { fetch => 'col_arrayref', cache => "Plugin::cscheme::get_group::$cscheme_table" } );
				push @groups, @$groups;
			}
			@groups = uniq sort @groups;
			local $" = q(;);
			$value = qq(@groups);
		}
	}
	return $value;
}

sub get_cscheme_field_value {
	my ( $self, $isolate_id, $cscheme_id, $scheme_field ) = @_;
	my $table = $self->{'datastore'}->create_temp_cscheme_field_values_table($cscheme_id);
	if ( !$self->{'cache'}->{'cscheme_field_cache_table_exists'}->{$cscheme_id} ) {
		$self->{'cache'}->{'cscheme_field_cache_table_exists'}->{$cscheme_id} =
		  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)',
			"temp_cscheme_${cscheme_id}_field_values" );
	}
	my @values;
	if ( $self->{'cache'}->{'cscheme_field_cache_table_exists'}->{$cscheme_id} ) {
		my $cscheme_group  = $self->get_cscheme_value( $isolate_id, $cscheme_id );
		my @cscheme_groups = split /;/x, $cscheme_group;
		foreach my $group (@cscheme_groups) {
			my $value = $self->{'datastore'}->run_query(
				"SELECT value FROM $table WHERE (group_id,field)=(?,?)",
				[ $group, $scheme_field ],
				cache => 'Plugin::get_cscheme_field_value'
			);
			push @values, $value if defined $value;
		}
	}
	@values = uniq sort @values;
	local $" = q(;);
	return qq(@values);
}

sub get_lincode {
	my ( $self, $isolate_id, $scheme_id ) = @_;
	return if !BIGSdb::Utils::is_int($isolate_id);
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $profile_ids = $self->get_scheme_field_values(
		{
			isolate_id => $isolate_id,
			scheme_id  => $scheme_id,
			field      => $scheme_info->{'primary_key'}
		}
	);
	my $lincode_table = $self->{'datastore'}->create_temp_lincodes_table($scheme_id);
	my $lincodes      = [];
	my %used;
	foreach my $profile_id (@$profile_ids) {
		my $lincode =
		  $self->{'datastore'}->run_query( "SELECT lincode FROM $lincode_table WHERE profile_id=?", $profile_id );
		if ($lincode) {
			local $" = q(_);
			next if $used{"@$lincode"};
			push @$lincodes, $lincode;
			$used{"@$lincode"} = 1;
		}
	}
	return $lincodes;
}

sub attempted_spam {
	my ( $self, $str ) = @_;
	return   if !$str || !ref $str;
	return 1 if $$str =~ /<\s*a\s*href/ix;    #Test for HTML links in submitted data
	return;
}

sub create_list_file {
	my ( $self, $job_id, $suffix, $list ) = @_;
	my $filename = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}_$suffix.list";
	open( my $fh, '>', $filename ) || $logger->error("Cannot open $filename to write");
	say $fh $_ foreach (@$list);
	close $fh;
	return $filename;
}

sub filter_missing_isolates {
	my ( $self, $ids ) = @_;
	my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $ids );
	my $ids_found =
	  $self->{'datastore'}
	  ->run_query( "SELECT i.id FROM $self->{'system'}->{'view'} i JOIN $temp_table t ON i.id=t.value ORDER BY i.id",
		undef, { fetch => 'col_arrayref' } );
	my $ids_missing = $self->{'datastore'}->run_query(
		"SELECT value FROM $temp_table WHERE value NOT IN (SELECT id FROM $self->{'system'}->{'view'}) ORDER BY value",
		undef,
		{ fetch => 'col_arrayref' }
	);
	return ( $ids_found, $ids_missing );
}

sub get_export_buttons {
	my ( $self, $options ) = @_;
	my $buffer      = ();
	my $div_display = $options->{'hide_div'} ? 'none' : 'block';
	$buffer .= qq(<div id="export" style="display:$div_display;margin-top:1em">\n);
	my %hide = $options->{'hide'} ? map { $_ => 1 } @{ $options->{'hide'} } : ();
	if ( $options->{'table'} ) {
		my $display = $hide{'table'} ? 'none' : 'inline';
		my $table   = EXPORT_TABLE;
		$buffer .= qq(<a id="export_table" title="Show as table" style="cursor:pointer;display:$display">$table</a>);
	}
	if ( $options->{'excel'} ) {
		my $display = $hide{'excel'} ? 'none' : 'inline';
		my $excel   = EXCEL_FILE;
		$buffer .=
		  qq(<a id="export_excel" title="Export Excel file" style="cursor:pointer;display:$display">$excel</a>);
	}
	if ( $options->{'text'} ) {
		my $display = $hide{'text'} ? 'none' : 'inline';
		my $text    = TEXT_FILE;
		$buffer .= qq(<a id="export_text" title="Export text file" style="cursor:pointer;display:$display">$text</a>);
	}
	if ( $options->{'fasta'} ) {
		my $display = $hide{'fasta'} ? 'none' : 'inline';
		my $fasta   = FASTA_FILE;
		$buffer .=
		  qq(<a id="export_fasta" title="Export FASTA file" style="cursor:pointer;display:$display">$fasta</a>);
	}
	if ( $options->{'image'} ) {
		my $display = $hide{'image'} ? 'none' : 'inline';
		my $image   = IMAGE_FILE;
		$buffer .=
			q(<a id="export_image" title="Export SVG image file" )
		  . qq(style="cursor:pointer;display:$display">$image</a>);
	}
	if ( $options->{'map_image'} ) {
		my $display = $hide{'map_image'} ? 'none' : 'inline';
		my $image   = IMAGE_FILE;
		$buffer .=
			q(<a id="export_map_image" title="Export PNG image file" )
		  . qq(style="cursor:pointer;display:$display">$image</a>);
	}
	$buffer .= q(</div>);
	return $buffer;
}

sub print_recommended_scheme_fieldset {
	my ( $self, $options ) = @_;
	my $schemes =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id FROM schemes WHERE recommended ORDER BY name', undef, { fetch => 'col_arrayref' } );
	return if !@$schemes;
	my $set_id = $self->get_set_id;
	my $labels = {};
	foreach my $scheme_id (@$schemes) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
		$labels->{$scheme_id} = $scheme_info->{'name'};
	}
	say q(<fieldset id="recommended_scheme_fieldset" style="float:left"><legend>Recommended schemes</legend>);
	say q(<p>Select one or more schemes<br />below or use the full schemes list.</p>);
	say $self->popup_menu(
		-name     => 'recommended_schemes',
		-id       => 'recommended_schemes',
		-values   => $schemes,
		-labels   => $labels,
		-size     => 5,
		-multiple => 'true'
	);
	if ( !$options->{'no_clear'} ) {
		say q(<div style="text-align:center"><input type="button" )
		  . q(onclick='listbox_selectall("recommended_schemes",false)' )
		  . q(value="Clear" style="margin-top:1em" class="small_submit" /></div>);
	}
	say q(</fieldset>);
	return;
}

sub add_recommended_scheme_loci {
	my ( $self, $loci ) = @_;
	my $q              = $self->{'cgi'};
	my @schemes        = $q->multi_param('recommended_schemes');
	my %locus_selected = map { $_ => 1 } @$loci;
	foreach my $scheme_id (@schemes) {
		next if !BIGSdb::Utils::is_int($scheme_id);
		my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
		foreach my $locus (@$scheme_loci) {
			next if $locus_selected{$locus};
			push @$loci, $locus;
			$locus_selected{$locus} = 1;
		}
	}
	return;
}

sub print_user_genome_upload_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left;height:12em"><legend>User genomes</legend>);
	say q(<p>Optionally include data not in the<br />database.</p>);
	say
q(<p>Upload assembly FASTA file<br />(or zip/tar.gz/tar file containing multiple<br />FASTA files - one per genome):);
	my $upload_limit = BIGSdb::Utils::get_nice_size( $self->{'max_upload_size_mb'} // 0 );
	say $self->get_tooltip( q(User data - The name of the file(s) containing genome data will be )
		  . qq(used as the name of the isolate(s) in the output. Maximum upload size is $upload_limit.) );
	say q(</p>);
	say $q->filefield( -name => 'user_upload', -id => 'user_upload' );
	say q(<a id="clear_user_upload" class="small_reset" title="Clear upload">)
	  . q(<span><span class="far fa-trash-can"></span></span></a>);
	say q(</fieldset>);
	return;
}

sub upload_file {
	my ( $self, $param, $suffix ) = @_;
	my $temp = BIGSdb::Utils::get_random();
	my $q    = $self->{'cgi'};
	my $format;
	if ( $q->param($param) =~ /.+\.tar\.gz$/x ) {
		$format = '.tar.gz';
	} else {
		$format = $q->param($param) =~ /.+(\.\w+)$/x ? $1 : q();
	}
	my $filename = "$self->{'config'}->{'tmp_dir'}/${temp}_$suffix$format";
	my $buffer;
	open( my $fh, '>', $filename ) || $logger->error("Could not open $filename for writing.");
	my $fh2 = $self->{'cgi'}->upload($param);
	binmode $fh2;
	binmode $fh;
	read( $fh2, $buffer, $self->{'config'}->{'max_upload_size'} );
	print $fh $buffer;
	close $fh;
	return "${temp}_$suffix$format";
}

sub print_scheme_selection_banner {
	my ($self) = @_;
	my $banner_file = "$self->{'dbase_config_dir'}/$self->{'instance'}/scheme_selection_banner.html";
	return if !-e $banner_file;
	say q(<div class="box" id="pluginbanner">);
	$self->print_file($banner_file);
	say q(</div>);
	return;
}

#Take account of multivalue fields
#$record is a hashref retrieved from the database
sub get_field_value {
	my ( $self, $record, $field, $divider ) = @_;
	if ( !$self->{'cache'}->{'attributes'}->{$field} ) {
		my $att = $self->{'xmlHandler'}->get_field_attributes($field);
		if ( ( $att->{'multiple'} // q() ) eq 'yes' && ( $att->{'optlist'} // q() ) eq 'yes' ) {
			$self->{'cache'}->{'optlist'}->{$field} = $self->{'xmlHandler'}->get_field_option_list($field);
		}
		$self->{'cache'}->{'attributes'}->{$field} = $att;
	}
	my $field_value;
	if ( defined $record->{ lc $field } && $record->{ lc $field } ne q() ) {
		if ( ref $record->{ lc $field } ) {
			local $" = $divider // q(; );
			my $values = $record->{ lc $field };
			if ( $self->{'cache'}->{'optlist'}->{$field} ) {
				$values =
				  BIGSdb::Utils::arbitrary_order_list( $self->{'cache'}->{'optlist'}->{$field}, $values );
			} else {
				@$values =
				  $self->{'cache'}->{'attributes'}->{$field}->{'type'} eq 'text'
				  ? sort { $a cmp $b } @$values
				  : sort { $a <=> $b } @$values;
			}
			$field_value = qq(@$values);
		} else {
			$field_value = $record->{ lc $field };
		}
	} else {
		$field_value = q();
	}
	return $field_value;
}

sub print_panel_buttons {
	my ($self) = @_;
	if ( $self->{'modify_panel'} ) {
		say q(<span class="icon_button">)
		  . q(<a class="trigger_button" id="panel_trigger" style="display:none">)
		  . q(<span class="fas fa-lg fa-wrench"></span><span class="icon_label">Modify form</span></a></span>);
	}
	return;
}

sub check_connection {
	my ( $self, $job_id ) = @_;
	return if $self->{'db'}->ping;
	$self->_reconnect;
	my $job    = $self->{'jobManager'}->get_job($job_id);
	my $params = $self->{'jobManager'}->get_job_params($job_id);
	$self->{'datastore'}->initiate_view(
		{
			username      => $job->{'username'},
			curate        => $params->{'curate'},
			original_view => $self->{'system'}->{'original_view'}
		}
	);
	return;
}

sub _reconnect {
	my ($self) = @_;
	$self->{'dataConnector'}->initiate( $self->{'system'}, $self->{'config'} );
	my $att = {
		dbase_name => $self->{'system'}->{'db'},
		host       => $self->{'system'}->{'host'},
		port       => $self->{'system'}->{'port'},
		user       => $self->{'system'}->{'user'},
		password   => $self->{'system'}->{'password'}
	};
	$self->{'dataConnector'}->drop_connection($att);
	$self->{'db'} = $self->{'dataConnector'}->get_connection($att);
	$self->{'datastore'}->change_db( $self->{'db'} );
	return;
}
1;
