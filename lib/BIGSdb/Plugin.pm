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
package BIGSdb::Plugin;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::TreeViewPage Exporter);
use Error qw(:try);
use Log::Log4perl qw(get_logger);
use List::MoreUtils qw(any uniq);
use BIGSdb::Constants qw(LOCUS_PATTERN :interface);
my $logger = get_logger('BIGSdb.Plugins');
use constant SEQ_SOURCE => 'seqbin id + position';
our @EXPORT_OK = qw(SEQ_SOURCE);

#Override the following methods in subclass
sub get_attributes { return {} }
sub get_option_list { return [] }
sub print_extra_form_elements { }
sub print_extra_fields        { }
sub print_options             { }
sub print_extra_options       { }
sub get_hidden_attributes     { return [] }
sub get_plugin_javascript     { return q() }
sub run                       { }
sub run_job                   { }              #used to run offline job

sub get_javascript {
	my ($self) = @_;
	my $plugin_name = $self->{'cgi'}->param('name');
	my ( $js, $tree_js );
	try {
		$js = $self->{'pluginManager'}->get_plugin($plugin_name)->get_plugin_javascript;
		my $requires = $self->{'pluginManager'}->get_plugin($plugin_name)->get_attributes->{'requires'};
		if ($requires) {
			$tree_js =
			  $requires =~ /js_tree/x ? $self->get_tree_javascript( { checkboxes => 1, check_schemes => 1 } ) : q();
		} else {
			$tree_js = q();
		}
	}
	catch BIGSdb::InvalidPluginException with {
		my $message = $plugin_name ? "Plugin $plugin_name does not exist." : 'Plugin name not called.';
		$tree_js = q();
		$logger->warn($message);
	};
	$js .= $self->get_list_javascript;
	$js .= <<"JS";
\$(document).ready(function() 
    { 
        \$("#sortTable").tablesorter({widgets:['zebra']});       
    } 
); 	
$tree_js
JS
	return $js;
}

sub get_job_redirect {
	my ( $self, $job_id ) = @_;
	my $buffer = <<"REDIRECT";
<div class="box" id="resultspanel">
<p>This export job has been submitted to the job queue.</p>
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
					say q(<div class="box" id="statusbad"><p>Cannot open temporary file.</p></div>);
				}
				$logger->error($@);
				return;
			}
		} else {
			if ( $self->{'cgi'}->param('format') eq 'text' ) {
				say 'The temporary file containing your query does not exist. Please repeat your query.';
			} else {
				say q(<div class="box" id="statusbad"><p>The temporary file containing your query does not exist. )
				  . q(Please repeat your query.</p></div>);
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

sub create_temp_tables {
	my ( $self, $qry_ref ) = @_;
	return 1 if $self->{'temp_tables_created'};
	my $qry      = $$qry_ref;
	my $q        = $self->{'cgi'};
	my $format   = $q->param('format') || 'html';
	my $schemes  = $self->{'datastore'}->run_query( 'SELECT id FROM schemes', undef, { fetch => 'col_arrayref' } );
	my $continue = 1;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $view = $self->{'system'}->{'view'};
		try {
			foreach my $scheme_id (@$schemes) {
				if ( $qry =~ /temp_$view\_scheme_fields_$scheme_id\s/x ) {
					$self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
				}
				if ( $qry =~ /temp_$view\_scheme_completion_$scheme_id\s/x ) {
					$self->{'datastore'}->create_temp_scheme_status_table($scheme_id);
				}
				if ( $qry =~ /temp_scheme_$scheme_id\s/x || $qry =~ /ORDER\ BY\ s_$scheme_id\_/x ) {
					$self->{'datastore'}->create_temp_scheme_table($scheme_id);
					$self->{'datastore'}->create_temp_isolate_scheme_loci_view($scheme_id);
				}
			}
		}
		catch BIGSdb::DatabaseConnectionException with {
			if ( $format ne 'text' ) {
				say q(<div class="box" id="statusbad"><p>Can not connect to remote database. )
				  . q(The query can not be performed.</p></div>);
			} else {
				say q(Cannot connect to remote database.  The query can not be performed.);
			}
			$logger->error('Cannot connect to remote database.');
			$continue = 0;
		};
	}
	if ( $q->param('list_file') && $q->param('datatype') ) {
		$self->{'datastore'}->create_temp_list_table( $q->param('datatype'), $q->param('list_file') );
	}
	$self->{'temp_tables_created'} = 1;
	return $continue;
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
		say q(<div class="box" id="statusbad"><p>Invalid (or no) plugin called.</p></div>);
		return;
	}
	my $plugin = $self->{'pluginManager'}->get_plugin($plugin_name);
	my $att    = $plugin->get_attributes;
	$plugin->{'username'} = $self->{'username'};
	my $dbtype = $self->{'system'}->{'dbtype'};
	if ( $att->{'dbtype'} !~ /$dbtype/x ) {
		say q(<div class="box" id="statusbad"><p>This plugin is not compatible )
		  . qq(with this type of database ($dbtype).</p></div>);
		return;
	}
	my $option_list = $plugin->get_option_list;
	if ( @$option_list && $q->param('format') eq 'html' ) {
		if ( $q->param('update_options') ) {
			$self->_update_options($option_list);
		}
		if ( !$self->{'cookies_disabled'} ) {
			say $q->start_form;
			$q->param( 'update_options', 1 );
			say $q->hidden($_) foreach @{ $plugin->get_hidden_attributes() };
			say $q->hidden($_) foreach qw(page db name query_file update_options);
			say q(<div id="hidefromnonJS" class="hiddenbydefault">);
			say q(<div class="floatmenu"><a id="toggle1" class="showhide">Show options</a>);
			say q(<a id="toggle2" class="hideshow">Hide options</a></div>);
			say q(<div class="hideshow">);
			say q(<div id="pluginoptions"><h2>Options</h2><ul>);
			my $guid = $self->get_guid;

			foreach (@$option_list) {
				say q(<li>);
				my $default;
				try {
					$default =
					  $self->{'prefstore'}
					  ->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, $plugin_name, $_->{'name'} );
					if ( $default eq 'true' || $default eq 'false' ) {
						$default = $default eq 'true' ? 1 : 0;
					}
				}
				catch BIGSdb::DatabaseNoRecordException with {
					$default = $_->{'default'};
				};
				if ( $_->{'optlist'} ) {
					print $_->{'description'} . ': ';
					my @values = split /;/x, $_->{'optlist'};
					say $q->popup_menu( -name => $_->{'name'}, -values => [@values], -default => $default );
				} else {
					say $q->checkbox( -name => $_->{'name'}, -label => $_->{'description'}, selected => $default );
				}
				say q(</li>);
			}
			say q(</ul><fieldset><legend>Action</legend>);
			say $q->submit( -name => 'reset', -label => 'Reset to defaults', -class => RESET_BUTTON_CLASS );
			say $q->submit( -name => 'set',   -label => 'Set options',       -class => BUTTON_CLASS );
			say q(</fieldset></div></div></div>);
			say $q->end_form;
		} else {
			say q(<div class="floatmenu">Options disabled (allow cookies to enable)</div>);
		}
	}
	$plugin->initiate_prefs;
	$plugin->initiate_view( $self->{'username'} );
	$plugin->run;
	return;
}

sub _update_options {
	my ( $self, $option_list ) = @_;
	my $q    = $self->{'cgi'};
	my $guid = $self->get_guid;
	if ($guid) {
		if ( $q->param('set') ) {
			foreach my $option (@$option_list) {
				my $value;
				if ( $option->{'optlist'} ) {
					$value = $q->param( $option->{'name'} );
				} else {
					$value = $q->param( $option->{'name'} ) ? 'true' : 'false';
				}
				$self->{'prefstore'}->set_plugin_attribute( $guid, $self->{'system'}->{'db'},
					$q->param('name'), $option->{'name'}, $value );
			}
			$self->{'prefstore'}->update_datestamp($guid);
		} elsif ( $q->param('reset') ) {
			foreach my $option (@$option_list) {
				$self->{'prefstore'}
				  ->delete_plugin_attribute( $guid, $self->{'system'}->{'db'}, $q->param('name'), $option->{'name'} );
				my $value;
				if ( $option->{'optlist'} ) {
					$value = $option->{'default'};
				} else {
					$value = $option->{'default'} ? 'on' : 'off';
				}
				$q->param( $option->{'name'}, $value );
			}
		}
	} else {
		$self->{'cookies_disabled'} = 1;
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc        = $self->get_db_description || 'BIGSdb';
	my $plugin_name = $self->{'cgi'}->param('name');
	my $att         = $self->{'pluginManager'}->get_plugin_attributes($plugin_name);
	if ( $att->{'menutext'} ) {
		return "$att->{'menutext'} - $desc";
	}
	return $desc;
}

sub _print_fields {
	my ( $self, $args ) = @_;
	my ( $fields, $prefix, $num_columns, $labels, $default_select ) =
	  @{$args}{qw(fields prefix num_columns labels default_select)};
	my $q                 = $self->{'cgi'};
	my $fields_per_column = BIGSdb::Utils::round_up( @$fields / $num_columns );
	say q(<div style="float:left;margin-bottom:1em"><ul>);
	my $i = 0;
	foreach my $field (@$fields) {
		my $label = $labels->{$field} || $field;
		$label =~ s/^.*___//x;         #only show extended field.
		$label =~ s/^meta_[^:]+://x;
		$label =~ tr/_/ /;
		my $id = $self->clean_checkbox_id("$prefix\_$field");
		print q(<li>);
		print $q->checkbox(
			-name    => "$prefix\_$field",
			-id      => $id,
			-checked => $default_select,
			-value   => 'checked',
			-label   => $label
		);
		say q(</li>);
		$i++;

		if ( $i == $fields_per_column && $field ne $fields->[-1] ) {
			$i = 0;
			say q(</ul></div><div style="float:left;margin-bottom:1em"><ul>);
		}
	}
	say q(</ul></div>);
	say q(<div style="clear:both"></div>);
	return;
}

sub print_field_export_form {
	my ( $self, $default_select, $options ) = @_;
	my $q             = $self->{'cgi'};
	my $set_id        = $self->get_set_id;
	my $schemes       = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	my $loci          = $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $fields        = $self->{'xmlHandler'}->get_field_list($metadata_list);
	my @display_fields;
	my $extended = $options->{'extended_attributes'} ? $self->get_extended_attributes : undef;
	my ( @js, @js2, @isolate_js, @isolate_js2 );

	foreach my $field (@$fields) {
		push @display_fields, $field;
		push @display_fields, 'aliases' if $field eq $self->{'system'}->{'labelfield'};
		if ( $options->{'extended_attributes'} ) {
			my $extatt = $extended->{$field};
			if ( ref $extatt eq 'ARRAY' ) {
				foreach my $extended_attribute (@$extatt) {
					push @display_fields, "$field\_\_\_$extended_attribute";
				}
			}
		}
	}
	push @isolate_js,  @js;
	push @isolate_js2, @js2;
	foreach my $field (@display_fields) {
		( my $id = "f_$field" ) =~ tr/:/_/;
		push @js,          qq(\$("#$id").prop("checked",true));
		push @js2,         qq(\$("#$id").prop("checked",false));
		push @isolate_js,  qq(\$("#$id").prop("checked",true));
		push @isolate_js2, qq(\$("#$id").prop("checked",false));
	}
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Isolate fields</legend>);
	$self->_print_fields(
		{
			fields         => \@display_fields,
			prefix         => 'f',
			num_columns    => 3,
			labels         => {},
			default_select => $default_select
		}
	);
	$self->_print_all_none_buttons( \@isolate_js, \@isolate_js2, 'smallbutton' );
	say q(</fieldset>);
	if ( $options->{'include_composites'} ) {
		my $composites =
		  $self->{'datastore'}
		  ->run_query( 'SELECT id FROM composite_fields ORDER BY id', undef, { fetch => 'col_arrayref' } );
		if (@$composites) {
			my ( @com_js, @com_js2 );
			foreach (@$composites) {
				push @js,      qq(\$("#c_$_").prop("checked",true));
				push @js2,     qq(\$("#c_$_").prop("checked",false));
				push @com_js,  qq(\$("#c_$_").prop("checked",true));
				push @com_js2, qq(\$("#c_$_").prop("checked",false));
			}
			say q(<fieldset style="float:left"><legend>Composite fields);
			say q( <a class="tooltip" title="Composite fields - These are constructed from combinations of )
			  . q(other fields (some of which may come from external databases).  Including composite fields )
			  . q(will slow down the processing."><span class="fa fa-info-circle"></span></a>);
			say q(</legend>);
			$self->_print_fields(
				{ fields => $composites, prefix => 'c', num_columns => 1, labels => {}, default_select => 0 } );
			$self->_print_all_none_buttons( \@com_js, \@com_js2, 'smallbutton' );
			say q(</fieldset>);
		}
	}
	$self->print_extra_fields;
	$self->print_isolates_locus_fieldset;
	$self->print_scheme_fieldset( { fields_or_loci => 1 } );
	$self->print_options;
	$self->print_extra_options;
	$self->print_action_fieldset( { no_reset => 1 } );
	say q(<div style="clear:both"></div>);
	$q->param( set_id => $set_id );
	say $q->hidden($_) foreach qw (db page name query_file set_id list_file datatype);
	say $q->end_form;
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
	return \@;;
}

sub get_selected_fields {
	my ($self)        = @_;
	my $q             = $self->{'cgi'};
	my $set_id        = $self->get_set_id;
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $fields        = $self->{'xmlHandler'}->get_field_list($metadata_list);
	my $extended      = $self->get_extended_attributes;
	my @display_fields;
	$self->escape_params;

	foreach (@$fields) {
		push @display_fields, $_;
		push @display_fields, 'aliases' if $_ eq $self->{'system'}->{'labelfield'};
		my $extatt = $extended->{$_};
		if ( ref $extatt eq 'ARRAY' ) {
			foreach my $extended_attribute (@$extatt) {
				push @display_fields, "$_\_\_\_$extended_attribute";
			}
		}
	}
	my $loci = $self->{'datastore'}->get_loci( { set_id => $set_id } );
	my $composites =
	  $self->{'datastore'}->run_query( 'SELECT id FROM composite_fields', undef, { fetch => 'col_arrayref' } );
	my $schemes = $self->{'datastore'}->run_query( 'SELECT id FROM schemes', undef, { fetch => 'col_arrayref' } );
	my @fields_selected;
	foreach (@display_fields) {
		push @fields_selected, "f_$_" if $q->param("f_$_");
	}
	foreach (@$composites) {
		push @fields_selected, "c_$_" if $q->param("c_$_");
	}
	foreach (@$schemes) {
		my $scheme_members = $self->{'datastore'}->get_scheme_loci($_);
		foreach my $member (@$scheme_members) {
			push @fields_selected, "s_$_\_l_$member"
			  if $q->param("s_$_") && $q->param('scheme_members');
		}
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($_);
		foreach my $scheme_field (@$scheme_fields) {
			push @fields_selected, "s_$_\_f_$scheme_field"
			  if $q->param("s_$_") && $q->param('scheme_fields');
		}
	}
	my $selected_loci = $self->get_selected_loci;
	foreach my $locus (@$loci) {
		push @fields_selected, "l_$locus" if any { $locus eq $_ } @$selected_loci;
	}
	return \@fields_selected;
}

sub print_sequence_export_form {
	my ( $self, $pk, $list, $scheme_id, $options ) = @_;
	$logger->error('No primary key passed') if !defined $pk;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	say $q->start_form;
	say qq(<fieldset style="float:left"><legend>Select ${pk}s</legend>);
	local $" = "\n";
	say q(<p style="padding-right:2em">Paste in list of ids to include, start a new<br />)
	  . q(line for each. Leave blank to include all ids.</p>);
	@$list = uniq @$list;
	say $q->textarea( -name => 'list', -rows => 5, -cols => 25, -default => "@$list" );
	say q(</fieldset>);
	my ( $locus_list, $locus_labels ) =
	  $self->get_field_selection_list( { loci => 1, analysis_pref => 1, query_pref => 0, sort_labels => 1 } );
	$self->print_includes_fieldset( { scheme_id => $scheme_id, include_seqbin_id => $options->{'include_seqbin_id'} } );

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->print_isolates_locus_fieldset( { locus_paste_list => 1 } );
		$self->print_scheme_fieldset;
	} else {
		$self->print_scheme_locus_fieldset( $scheme_id, $options );
	}
	if ( !$options->{'no_options'} ) {
		my $options_heading = $options->{'options_heading'} || 'Options';
		say qq(<fieldset style="float:left"><legend>$options_heading</legend>);
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			say q(<p>If both allele designations and tagged sequences<br />)
			  . q(exist for a locus, choose how you want these handled: );
			say q( <a class="tooltip" title="Sequence retrieval - Peptide loci will only be retrieved from the )
			  . q(sequence bin (as nucleotide sequences)."><span class="fa fa-info-circle"></span></a></p>);
			say q(<ul><li>);
			my %labels = (
				seqbin             => 'Use sequences tagged from the bin',
				allele_designation => 'Use allele sequence retrieved from external database'
			);
			say $q->radio_group(
				-name      => 'chooseseq',
				-values    => [ 'seqbin', 'allele_designation' ],
				-labels    => \%labels,
				-linebreak => 'true'
			);
			say q(</li><li style="margin-top:0.5em">);
			if ( $options->{'ignore_seqflags'} ) {
				say $q->checkbox(
					-name    => 'ignore_seqflags',
					-label   => 'Do not include sequences with problem flagged (defined alleles will still be used)',
					-checked => 'checked'
				);
				say q(</li><li>);
			}
			if ( $options->{'ignore_incomplete'} ) {
				say $q->checkbox(
					-name    => 'ignore_incomplete',
					-label   => 'Do not include incomplete sequences',
					-checked => 'checked'
				);
				say q(</li><li>);
			}
			if ( $options->{'flanking'} ) {
				say q(Include );
				say $q->popup_menu( -name => 'flanking', -values => [FLANKING], -default => 0 );
				say q( bp flanking sequence);
				say q( <a class="tooltip" title="Flanking sequence - This can only be included if you )
				  . q(select to retrieve sequences from the sequence bin rather than from an external database.">)
				  . q(<span class="fa fa-info-circle"></span></a>);
				say q(</li>);
			}
		} else {
			say q(<ul>);
		}
		if ( $options->{'align'} ) {
			say q(<li>);
			say $q->checkbox( -name => 'align', -id => 'align', -label => 'Align sequences' );
			say q(</li>);
			my @aligners;
			foreach my $aligner (qw(mafft muscle)) {
				push @aligners, uc($aligner) if $self->{'config'}->{"$aligner\_path"};
			}
			if (@aligners) {
				say q(<li>Aligner: );
				say $q->popup_menu( -name => 'aligner', -id => 'aligner', -values => \@aligners );
				say q(</li>);
			}
		}
		if ( $options->{'translate'} ) {
			say q(<li>);
			say $q->checkbox( -name => 'translate', -label => 'Translate sequences' );
			say q(</li>);
		}
		if ( $options->{'in_frame'} ) {
			say q(<li>);
			say $q->checkbox( -name => 'in_frame', -label => 'Concatenate in frame' );
			say q(</li>);
		}
		say q(</ul></fieldset>);
	}
	$self->print_extra_form_elements;
	$self->print_action_fieldset( { no_reset => 1 } );
	say q(<div style="clear:both"></div>);
	my $set_id = $self->get_set_id;
	$q->param( set_id => $set_id );
	say $q->hidden($_) foreach qw (db page name query_file scheme_id set_id list_file datatype);
	say $q->end_form;
	return;
}

sub has_set_changed {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $set_id = $self->get_set_id;
	if ( $q->param('set_id') && $set_id ) {
		if ( $q->param('set_id') != $set_id ) {
			say q(<div class="box" id="statusbad"><p>The dataset has been changed since this )
			  . q(plugin was started. Please repeat the query.</p></div>);
			return 1;
		}
	}
	return;
}

sub print_includes_fieldset {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	my ( @fields, $labels );
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $set_id        = $self->get_set_id;
		my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
		my $field_list    = $self->{'xmlHandler'}->get_field_list($metadata_list);
		foreach my $field (@$field_list) {
			next if any { $field eq $_ } qw (id datestamp date_entered curator sender);
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			push @fields, $field;
			( $labels->{$field} = $metafield // $field ) =~ tr/_/ /;
		}
		if ( $options->{'include_seqbin_id'} ) {
			push @fields, SEQ_SOURCE;
		}
	} else {
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields( $options->{'scheme_id'} );
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $options->{'scheme_id'}, { get_pk => 1 } );
		foreach (@$scheme_fields) {
			push @fields, $_ if $_ ne $scheme_info->{'primary_key'};
		}
	}
	if (@fields) {
		my $title = $options->{'title'} // 'Include in identifier';
		say qq(<fieldset style="float:left"><legend>$title</legend>);
		say $q->scrolling_list(
			-name     => 'includes',
			-id       => 'includes',
			-values   => \@fields,
			-labels   => $labels,
			-size     => 10,
			-default  => $options->{'preselect'},
			-multiple => 'true'
		);
		say q(</fieldset>);
	}
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
		say q(<div style="text-align:center"><input type="button" onclick='listbox_selectall("locus",true)' )
		  . q(value="All" style="margin-top:1em" class="smallbutton" /><input type="button" )
		  . q(onclick='listbox_selectall("locus",false)' value="None" style="margin-top:1em" class="smallbutton" /></div>);
	} else {
		say q(No loci available<br />for analysis);
	}
	say q(</fieldset>);
	return;
}

sub print_scheme_fieldset {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	say q(<fieldset id="scheme_fieldset" style="float:left"><legend>Schemes</legend>)
	  . q(<noscript><p class="highlight">Enable Javascript to select schemes.</p></noscript>)
	  . q(<div id="tree" class="tree" style="height:13em; width:20em">);
	say $self->get_tree( undef, { no_link_out => 1, select_schemes => 1 } );
	say q(</div>);
	if ( $options->{'fields_or_loci'} ) {
		say q(<div style="padding-top:1em"><ul><li>);
		say $q->checkbox( -name => 'scheme_fields', -label => 'Include all fields from selected schemes',
			-checked => 1 );
		say q(</li><li>);
		say $q->checkbox( -name => 'scheme_members', -label => 'Include all loci from selected schemes',
			-checked => 1 );
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
	$buffer = $self->get_experiment_filter( { class => 'parameter' } );
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

sub filter_ids_by_project {
	my ( $self, $ids, $project_id ) = @_;
	return $ids if !$project_id;
	my $ids_in_project = $self->{'datastore'}->run_query( 'SELECT isolate_id FROM project_members WHERE project_id=?',
		$project_id, { fetch => 'col_arrayref' } );
	my @filtered_ids;
	foreach my $id (@$ids) {
		push @filtered_ids, $id if any { $id eq $_ } @$ids_in_project;
	}
	return \@filtered_ids;
}

sub get_selected_loci {
	my ($self) = @_;
	$self->escape_params;
	my @loci = $self->{'cgi'}->param('locus');
	my @loci_selected;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $pattern = LOCUS_PATTERN;
		foreach my $locus (@loci) {
			my $locus_name = $locus =~ /$pattern/x ? $1 : undef;
			push @loci_selected, "$locus_name" if defined $locus_name;
		}
	} else {
		@loci_selected = @loci;
	}
	return \@loci_selected;
}

sub add_scheme_loci {

	#Merge scheme loci into locus arrayref.  This deletes CGI params so don't call more than once.
	my ( $self, $loci ) = @_;
	my $q = $self->{'cgi'};
	my $scheme_ids = $self->{'datastore'}->run_query( 'SELECT id FROM schemes', undef, { fetch => 'col_arrayref' } );
	push @$scheme_ids, 0;
	my @selected_schemes;
	foreach my $scheme_id (@$scheme_ids) {
		next if !$q->param("s_$scheme_id");
		push @selected_schemes, $scheme_id;
		$q->delete("s_$scheme_id");
	}
	my %locus_selected = map { $_ => 1 } @$loci;
	my $set_id = $self->get_set_id;
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
	my ($self) = @_;
	my $q = $self->{'cgi'};
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

sub _print_all_none_buttons {
	my ( $self, $js1, $js2, $class ) = @_;
	if ( ref $js1 && ref $js2 ) {
		local $" = ',';
		say qq(<input type="button" value="All" class="$class" onclick='@$js1' />);
		say qq(<input type="button" value="None" class="$class" onclick='@$js2' />);
	}
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
	my ( $isolate_id, $scheme_id, $field, ) = @{$args}{qw(isolate_id scheme_id field )};
	if ( !$self->{'scheme_field_table'}->{$scheme_id} ) {
		try {
			$self->{'scheme_field_table'}->{$scheme_id} =
			  $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
		}
		catch BIGSdb::DatabaseConnectionException with {
			$logger->error('Cannot copy data to temporary table.');
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

sub attempted_spam {
	my ( $self, $str ) = @_;
	return if !$str || !ref $str;
	return 1 if $$str =~ /<\s*a\s*href/ix;    #Test for HTML links in submitted data
	return;
}
1;
