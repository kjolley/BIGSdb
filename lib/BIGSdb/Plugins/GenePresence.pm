#PresenceAbsence.pm - Presence/Absence export plugin for BIGSdb
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
package BIGSdb::Plugins::GenePresence;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugins::GenomeComparator);
use List::MoreUtils qw(uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_RECORDS => 100_000;

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name        => 'Gene Presence',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Analyse presence/absence of loci for dataset generated from query results',
		category    => 'Analysis',
		buttontext  => 'Gene Presence',
		menutext    => 'Gene presence',
		module      => 'GenePresence',

		#		url         => "$self->{'config'}->{'doclink'}/data_analysis.html#presence-absence",
		version  => '2.0.0',
		dbtype   => 'isolates',
		section  => 'analysis,postquery',
		input    => 'query',
		requires => 'js_tree,offline_jobs',
		help     => 'tooltips',
		order    => 16
	);
	return \%att;
}

sub _print_interface {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $qry_ref    = $self->get_query($query_file);
	my $selected_ids;
	if ( $q->param('isolate_id') ) {
		my @ids = $q->param('isolate_id');
		$selected_ids = \@ids;
	} elsif ( defined $query_file ) {
		$selected_ids = $self->get_ids_from_query($qry_ref);
	} else {
		$selected_ids = [];
	}
	$self->print_set_section if $q->param('select_sets');
	say q(<div class="box" id="queryform"><p>Please select the required isolate ids and loci for comparison - )
	  . q(use CTRL or SHIFT to make multiple selections in list boxes. In addition to selecting individual loci, )
	  . q(you can choose to include all loci defined in schemes by selecting the appropriate scheme description.</p>);
	my $max = BIGSdb::Utils::commify(MAX_RECORDS);
	say qq(<p>Interactive analysis is limited to $max data points (isolates x loci). )
	  . q(If you select more than this then output will be restricted to static tables.);
	say $q->start_form;
	say q(<div class="scrollable">);
	$self->print_seqbin_isolate_fieldset( { use_all => 1, selected_ids => $selected_ids, isolate_paste_list => 1 } );
	$self->print_user_genome_upload_fieldset;
	$self->print_isolates_locus_fieldset( { locus_paste_list => 1 } );
	$self->print_recommended_scheme_fieldset;
	$self->print_scheme_fieldset;
	$self->_print_parameters_fieldset;
	say q(<div style="clear:both"></div>);
	$self->print_action_fieldset;
	say $q->hidden($_) foreach qw (page name db);
	say q(</div>);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _print_parameters_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left;height:12em"><legend>Parameters / options</legend>);
	say q(<ul><li><label for ="identity" class="parameter">Min % identity:</label>);
	say $q->popup_menu( -name => 'identity', -id => 'identity', -values => [ 30 .. 100 ], -default => 70 );
	say $self->get_tooltip(q(Minimum % identity - Match required for partial matching.));
	say q(</li><li><label for="alignment" class="parameter">Min % alignment:</label>);
	say $q->popup_menu( -name => 'alignment', -id => 'alignment', -values => [ 10 .. 100 ], -default => 50 );
	say $self->get_tooltip( q(Minimum % alignment - Percentage of allele sequence length required to be )
		  . q(aligned for partial matching.) );
	say q(</li><li><label for="word_size" class="parameter">BLASTN word size:</label>);
	say $q->popup_menu( -name => 'word_size', -id => 'word_size', -values => [ 7 .. 30 ], -default => 20 );
	say $self->get_tooltip( q(BLASTN word size - This is the length of an exact match required to )
		  . q(initiate an extension. Larger values increase speed at the expense of sensitivity.) );
	say q(</li></ul></fieldset>);
	return;
}

sub get_initiation_values {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	return if !$q->param('results');
	return { pivot => 1, papaparse => 1, noCache => 1 };
}

sub _show_results {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="resultspanel"><div class="scrollable">);
	say q(<div id="pivot_instructions" style="display:none"><h2>Pivot table</h2>);
	say q(<p>Drag and drop fields on to the table axes. Multiple fields can be combined.</p>);
	say q(</div>);
	say q(<div id="pivot">);
	$self->print_loading_message;
	say q(</div></div>);
	return;
}

sub run {
	my ($self) = @_;
	my $desc = $self->get_db_description;
	say qq(<h1>Gene Presence - $desc</h1>);
	my $q = $self->{'cgi'};
	if ( $q->param('results') ) {
		$self->_show_results;
		return;
	}
	if ( $q->param('submit') ) {
		my $ids = $self->filter_list_to_ids( [ $q->param('isolate_id') ] );
		my ( $pasted_cleaned_ids, $invalid_ids ) = $self->get_ids_from_pasted_list( { dont_clear => 1 } );
		push @$ids, @$pasted_cleaned_ids;
		@$ids = uniq @$ids;
		my $continue = 1;
		my @errors;
		if (@$invalid_ids) {
			local $" = ', ';
			push @errors, qq(The following isolates in your pasted list are invalid: @$invalid_ids.);
			$continue = 0;
		}
		$q->param( user_genome_filename => $q->param('user_upload') );
		my $user_upload;
		if ( $q->param('user_upload') ) {
			$user_upload = $self->_upload_user_file;
		}
		my $filtered_ids = $self->filter_ids_by_project( $ids, $q->param('project_list') );
		if ( !@$filtered_ids && !$q->param('user_upload') ) {
			push @errors, q(You must include one or more isolates. Make sure your selected isolates )
			  . q(haven't been filtered to none by selecting a project.);
			$continue = 0;
		}
		my $loci_selected = $self->get_selected_loci;
		my ( $pasted_cleaned_loci, $invalid_loci ) = $self->get_loci_from_pasted_list( { dont_clear => 1 } );
		$q->delete('locus');
		push @$loci_selected, @$pasted_cleaned_loci;
		@$loci_selected = uniq @$loci_selected;
		if (@$invalid_loci) {
			local $" = ', ';
			push @errors, qq(The following loci in your pasted list are invalid: @$invalid_loci.);
			$continue = 0;
		}
		$self->add_scheme_loci($loci_selected);
		$self->add_recommended_scheme_loci($loci_selected);
		my $accession = $q->param('accession') || $q->param('annotation');
		if ( !@$loci_selected && $continue ) {
			push @errors, q(You must either select one or more loci or schemes.);
			$continue = 0;
		}
		if (@errors) {
			if ( @errors == 1 ) {
				$self->print_bad_status( { message => qq(@errors) } );
			} else {
				local $" = q(</p><p>);
				$self->print_bad_status( { message => q(Please address the following:), detail => qq(@errors) } );
			}
		}
		$q->param( user_upload => $user_upload ) if $user_upload;
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		if ($continue) {
			$q->delete('isolate_paste_list');
			$q->delete('locus_paste_list');
			$q->delete('isolate_id');
			my $params = $q->Vars;
			$params->{'script_name'} = $self->{'system'}->{'script_name'};
			my $set_id = $self->get_set_id;
			$params->{'set_id'} = $set_id if $set_id;
			local $" = q(,);
			my $att    = $self->get_attributes;
			my $job_id = $self->{'jobManager'}->add_job(
				{
					dbase_config => $self->{'instance'},
					ip_address   => $q->remote_host,
					module       => $att->{'module'},
					priority     => $att->{'priority'},
					parameters   => $params,
					username     => $self->{'username'},
					email        => $user_info->{'email'},
					isolates     => $filtered_ids,
					loci         => $loci_selected
				}
			);
			say $self->get_job_redirect($job_id);
			return;
		}
	}
	$self->_print_interface;
	return;
}

sub _upload_user_file {
	my ($self) = @_;
	my $file = $self->upload_file( 'user_upload', 'user' );
	return $file;
}

sub _signal_kill_job {
	my ( $self, $job_id ) = @_;
	my $touch_file = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}.CANCEL";
	open( my $fh, '>', $touch_file ) || $logger->error("Cannot touch $touch_file");
	close $fh;
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	$self->{'exit'} = 0;
	$self->{'threads'} =
	  BIGSdb::Utils::is_int( $self->{'config'}->{'genome_comparator_threads'} )
	  ? $self->{'config'}->{'genome_comparator_threads'}
	  : 2;

	#Allow temp files to be cleaned on kill signals
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1; $self->_signal_kill_job($job_id) } ) x 3;
	$self->{'params'}                         = $params;
	$self->{'params'}->{'designation_status'} = 1;
	$self->{'params'}->{'tag_status'}         = 1;
	my $loci         = $self->{'jobManager'}->get_job_loci($job_id);
	my $isolate_ids  = $self->{'jobManager'}->get_job_isolates($job_id);
	my $user_genomes = $self->process_uploaded_genomes( $job_id, $isolate_ids, $params );
	if ( !@$isolate_ids && !keys %$user_genomes ) {
		$self->{'jobManager'}->update_job_status(
			$job_id,
			{
				message_html => q(<p class="statusbad">You must include one or more isolates.</p>)
			}
		);
		return;
	}
	if ( !@$loci ) {
		$self->{'jobManager'}->update_job_status(
			$job_id,
			{
				message_html => q(<p class="statusbad">You must select one or more loci or schemes.</p>)
			}
		);
		return;
	}
	my $data = $self->_get_data( $job_id, $isolate_ids, $loci, $user_genomes );
	$self->_create_presence_output( $job_id, $data );
	my $message;
	my $record_count = @$isolate_ids * @$loci;
	if ( $record_count > MAX_RECORDS ) {
		my $nice_max = BIGSdb::Utils::commify(MAX_RECORDS);
		my $selected = BIGSdb::Utils::commify($record_count);
		$message =
		    qq(Interactive analysis is limited to $nice_max records (isolates x loci). )
		  . qq(You have selected $selected. Output is limited to static tables.);
	} else {
		my $tsv_file = $self->_create_tsv_output( $job_id, $data );
		$message =
		    q(<p style="margin-top:2em;margin-bottom:2em">)
		  . qq(<a href="$params->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;)
		  . qq(name=GenePresence&amp;results=$tsv_file" target="_blank" )
		  . q(class="launchbutton">Launch Pivot Table</a></p>);
	}
	$self->{'jobManager'}->update_job_status( $job_id, { message_html => $message } );
	return;
}

sub _create_tsv_output {
	my ( $self, $job_id, $data ) = @_;
	my $loci      = $self->{'jobManager'}->get_job_loci($job_id);
	my $filename  = "$job_id.txt";
	my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
	open( my $fh, '>', $full_path ) || $logger->error("Cannot open $full_path for writing");
	say $fh qq(id\tlocus\tpresence\tcomplete\tknown allele\tdesignated\ttagged);
	foreach my $record (@$data) {
		foreach my $locus (@$loci) {
			my @output = ( $record->{'id'}, $locus );
			push @output, $record->{'loci'}->{$locus}->{$_}
			  foreach qw(present complete known_allele designation_in_db tag_in_db);
			local $" = qq(\t);
			say $fh qq(@output);
		}
	}
	close $fh;
	return $filename;
}

sub _create_presence_output {
	my ( $self, $job_id, $data ) = @_;
	my $loci      = $self->{'jobManager'}->get_job_loci($job_id);
	my $filename  = "${job_id}_presence.txt";
	my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
	local $" = qq(\t);
	open( my $fh, '>', $full_path ) || $logger->error("Cannot open $full_path for writing");
	say $fh qq(id\t@$loci);
	foreach my $record (@$data) {
		print $fh $record->{'id'};
		foreach my $locus (@$loci) {
			print $fh qq(\t$record->{'loci'}->{$locus}->{'present'});
		}
		print $fh qq(\n);
	}
	close $fh;
	$self->{'jobManager'}
	  ->update_job_output( $job_id, { filename => $filename, description => '01_Presence/absence (text)' } );
	my $excel_file = BIGSdb::Utils::text2excel($full_path);
	if (-e $excel_file){
		$self->{'jobManager'}
	  ->update_job_output( $job_id, { filename => "${job_id}_presence.xlsx", description => '01_Presence/absence (Excel)' } );
	}
	return;
}

sub _get_data {
	my ( $self, $job_id, $ids, $loci, $user_genomes ) = @_;
	my $scan_data = $self->assemble_data_for_defined_loci(
		{
			job_id       => $job_id,
			ids          => $ids,
			user_genomes => $user_genomes,
			loci         => $loci
		}
	);
	my $data = [];
	foreach my $id (@$ids) {
		my %designation_in_db = map { $_ => 1 } @{ $scan_data->{'isolate_data'}->{$id}->{'designation_in_db'} };
		my %tag_in_db         = map { $_ => 1 } @{ $scan_data->{'isolate_data'}->{$id}->{'tag_in_db'} };
		my $isolate_data      = {};
		foreach my $locus (@$loci) {
			$isolate_data->{'id'} = $id;
			my $designation = $scan_data->{'isolate_data'}->{$id}->{'designations'}->{$locus};
			$isolate_data->{'loci'}->{$locus}->{'present'} =
			  ( defined $designation && $designation ne 'missing' ) ? 1 : 0;
			$isolate_data->{'loci'}->{$locus}->{'known_allele'} =
			  (      defined $designation
				  && $designation !~ /^New/x
				  && $designation ne 'missing'
				  && $designation ne 'incomplete' ) ? 1 : 0;
			$isolate_data->{'loci'}->{$locus}->{'complete'} =
			  ( $designation ne 'missing' && $designation ne 'incomplete' ) ? 1 : 0;
			$isolate_data->{'loci'}->{$locus}->{'designation_in_db'} = $designation_in_db{$locus} ? 1 : 0;
			$isolate_data->{'loci'}->{$locus}->{'tag_in_db'}         = $tag_in_db{$locus}         ? 1 : 0;
		}
		push @$data, $isolate_data;
		return if $self->{'exit'};
	}
	return $data;
}

sub get_plugin_javascript {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	return if !$q->param('results');
	my $data_file = $q->param('results');
	my $url       = qq(/tmp/$data_file);
	my $buffer    = <<"JS";

\$(function () {
	var tpl = \$.pivotUtilities.aggregatorTemplates;
	var renderers = \$.extend(\$.pivotUtilities.renderers,
            \$.pivotUtilities.export_renderers);
	
	Papa.parse("$url", {
		download: true,
		skipEmptyLines: true,
	    complete: function(parsed){
	    	\$.each(parsed.data.slice(1),function(){
	    		this[2] = this[2] == 1 ? 'present' : 'absent';
	    		if (this[2] == 'present'){
	    			this[3] = this[3] == 1 ? 'complete' : 'incomplete';
	    		} else {
	    			this[3] = 'undefined';
	    		}
	    		if (this[3] == 'complete'){
	    			this[4] = this[4] == 1 ? 'known' : 'new';
	    		} else {
	    			this[4] = 'undefined';
	    		}
	    		this[5] = this[5] == 1 ? 'designated' : 'not designated';
	    		this[6] = this[6] == 1 ? 'tagged' : 'untagged';
	    	});
			\$("#pivot").pivotUI(parsed.data, {
	        	rows: ["locus"],
	            cols: ["presence"],	
	            renderers: renderers,            
	            aggregators: {
	            	"Count":  function(){return tpl.count()()},
	            	"Count as Fraction of Rows":    function(){return tpl.fractionOf(tpl.count(),"row")()},
					"Count as Fraction of Columns": function(){return tpl.fractionOf(tpl.count(),"col")()}
	            }
	        });
	        \$("div#pivot_instructions").show();
	    }
	});
	
});
JS
	return $buffer;
}
1;
