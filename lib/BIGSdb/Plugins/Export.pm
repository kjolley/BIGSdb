#Export.pm - Export plugin for BIGSdb
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
package BIGSdb::Plugins::Export;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use BIGSdb::Constants qw(:interface);
use Try::Tiny;
use List::MoreUtils qw(uniq);
use Bio::Seq;
use Bio::Tools::SeqStats;
use constant MAX_INSTANT_RUN         => 2000;
use constant MAX_DEFAULT_DATA_POINTS => 25_000_000;

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name    => 'Export',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			}
		],
		description      => 'Export dataset generated from query results',
		full_description => 'The Export plugin creates a download file of any primary metadata, secondary metadata, '
		  . 'allele designations, scheme designations, or publications for isolates within a selected dataset or '
		  . 'for the whole database. The output file is in Excel format.',
		category           => 'Export',
		buttontext         => 'Dataset',
		menutext           => 'Dataset',
		module             => 'Export',
		version            => '1.16.1',
		dbtype             => 'isolates',
		section            => 'export,postquery',
		url                => "$self->{'config'}->{'doclink'}/data_export/isolate_export.html",
		input              => 'query',
		requires           => 'ref_db,js_tree,offline_jobs',
		help               => 'tooltips',
		image              => '/images/plugins/Export/screenshot.png',
		order              => 15,
		system_flag        => 'DatasetExport',
		enabled_by_default => 1
	);
	return \%att;
}

sub get_initiation_values {
	return { 'jQuery.jstree' => 1, 'jQuery.multiselect' => 1, 'modify_panel' => 1, 'noCache' => 1 };
}

sub get_plugin_javascript {
	my ( $show, $hide, $save, $saving ) = ( SHOW, HIDE, SAVE, SAVING );
	my $js = << "END";
function enable_ref_controls(){
	if (\$("#m_references").prop("checked")){
		\$("input:radio[name='ref_type']").prop("disabled", false);
	} else {
		\$("input:radio[name='ref_type']").prop("disabled", true);
	}
}
function enable_private_controls(){
	\$("#private_owner").prop("disabled", !\$("#private_record").prop("checked"));
	\$("input:radio[name='private_name']").prop("disabled", !(\$("#private_owner")
		.prop("checked") && \$("#private_record").prop("checked")));
}

function enable_tag_controls(){	
	if (\$("#oneline").prop("checked")){
		\$("#indicate_tags").prop("checked", false);
		\$("#indicate_tags").prop("disabled", true);
	} else {
		\$("#indicate_tags").prop("disabled", false);
	}
	if (\$("#indicate_tags").prop("checked")){
		\$("input:radio[name='indicate_tags_when']").prop("disabled", false);
	} else {
		\$("input:radio[name='indicate_tags_when']").prop("disabled", true);
	}
}

\$(document).ready(function(){ 
	enable_ref_controls();
	enable_private_controls();
	enable_tag_controls();
	\$('#fields,#eav_fields,#composite_fields,#locus,#classification_schemes,#analysis_fields,#lincode_prefixes').multiselect({
 		classes: 'filter',
 		menuHeight: 250,
 		menuWidth: 400,
 		selectedList: 8,
  	});
 	\$('#locus').multiselectfilter();
 	\$("span#example_private").css("background",\$('#private_bg').val());
 	\$("span#example_private").css("color",\$('#private_fg').val());
 	\$('#private_bg').on('change',function(){
 		\$("span#example_private").css("background",\$('#private_bg').val());
 	});
 	\$('#private_fg').on('change',function(){
 		\$("span#example_private").css("color",\$('#private_fg').val());
 	});
 	\$("#panel_trigger,#close_trigger").click(function(){			
		\$("#modify_panel").toggle("slide",{direction:"right"},"fast");
		return false;
	});
 	\$("#panel_trigger").show();
 	//Close panel
	\$(document).mouseup(function(e) {
		// if the target of the click isn't the container nor a
		// descendant of the container
		var trigger = \$("#panel_trigger");
 		var container = \$("#modify_panel");
		if (!container.is(e.target) && container.has(e.target).length === 0 && 
		!trigger.is(e.target) && trigger.has(e.target).length === 0) {
			container.hide();
		}
	});
	\$(".fieldset_trigger").click(function(event) {
		let show = '$show';
		let hide = '$hide';
		let fieldset = this.id.replace('show_','');
		event.preventDefault();
		if(\$(this).html() == hide){
			clear_form(fieldset);
		}
		\$("#" + fieldset + "_fieldset").toggle(100);
		\$(this).html(\$(this).html() == show ? hide : show);
		\$("a#save_options").fadeIn();
		return false;
	});
	\$("a#save_options").click(function(event){		
		event.preventDefault();
		let show = '$show';
		let save_url = this.href;
		let fieldsets = ['eav','composite','refs','private','classification','analysis','lincode','molwt','options'];
		for (let i = 0; i < fieldsets.length; ++i) {			
			let value = \$("#show_" + fieldsets[i]).html() == show ? 0 : 1;
			save_url += "&" + fieldsets[i] + "=" + value;
		}
	  	\$(this).attr('href', function(){  	
	  		\$("a#save_options").html('$saving').animate({backgroundColor: "#99d"},100)
	  		.animate({backgroundColor: "#f0f0f0"},100);
	  		\$("span#saving").text('Saving...');
		  	\$.ajax({
	  			url : save_url,
	  			success: function () {	  				
	  				\$("a#save_options").hide();
	  				\$("span#saving").text('');
	  				\$("a#save_options").html('$save');
	  				\$("#modify_panel").toggle("slide",{direction:"right"},"fast");
	  			}
	  		});
	   	});
	});
	if (!localStorage.getItem('export_onboarding_202411')) {
        \$('#onboarding').show();
        localStorage.setItem('export_onboarding_202411', 'true');
    }
    \$('#close_onboarding').click(function() {
        \$('#onboarding').hide();
    });
    //Reset form if not visible, e.g. after reloading.
	let fieldsets = ['eav','composite','refs','private','classification','analysis','lincode','molwt','options'];
	for (let i = 0; i < fieldsets.length; ++i) {		
		let fieldset = fieldsets[i] + "_fieldset";
		if (\$("#" + fieldset).is(":hidden")){
			clear_form(fieldsets[i]);
		}
	}
}); 

function clear_form(fieldset){
	if (fieldset == 'eav'){
		\$("#eav_fields").multiselect("uncheckAll");
	}
	if (fieldset == 'composite'){
		\$("#composite_fields").multiselect("uncheckAll");
	}
	if (fieldset == 'refs'){
		\$("#m_references").prop("checked", false);
		\$("input:radio[name='ref_type']").prop("disabled", true);
	}
	if (fieldset == 'private'){
		\$("#private_record,#private_owner").prop("checked", true);
		enable_private_controls();
	}
	if (fieldset == 'classification'){
		\$("#classification_schemes").multiselect("uncheckAll");
	}
	if (fieldset == 'lincode'){
		\$("#lincode_prefixes").multiselect("uncheckAll");
	}
	if (fieldset == 'analysis'){
		\$("#analysis_fields").multiselect("uncheckAll");
	}
	if (fieldset == 'molwt'){
		\$("#molwt").prop("checked", false);
	}
	if (fieldset == 'options'){
		\$("#indicate_tags").prop("checked", false);
		\$("#common_names").prop("checked", false);
		\$("#alleles").prop("checked", true);
		\$("#oneline").prop("checked", false);
		\$("#labelfield").prop("checked", false);
		\$("#info").prop("checked", false);
	}
}
END
	return $js;
}

sub _print_ref_fields {
	my ($self)  = @_;
	my $display = $self->{'plugin_prefs'}->{'refs_fieldset'} ? 'block' : 'none';
	my $q       = $self->{'cgi'};
	say qq(<fieldset id="refs_fieldset" style="float:left;display:$display"><legend>References</legend><ul><li>);
	say $q->checkbox(
		-name     => 'm_references',
		-id       => 'm_references',
		-value    => 'checked',
		-label    => 'references',
		-onChange => 'enable_ref_controls()'
	);
	say q(</li><li>);
	say $q->radio_group(
		-name      => 'ref_type',
		-values    => [ 'PubMed id', 'Full citation' ],
		-default   => 'PubMed id',
		-linebreak => 'true'
	);
	say q(</li></ul></fieldset>);
	return;
}

sub _may_access_private_records {
	my ($self) = @_;
	return if !defined $self->{'username'};
	my $private =
	  $self->{'datastore'}->run_query(
		"SELECT EXISTS(SELECT * FROM private_isolates p JOIN $self->{'system'}->{'view'} v ON p.isolate_id=v.id)");
	return $private;
}

sub _print_private_fieldset {
	my ($self) = @_;
	return if !$self->_may_access_private_records;
	my $bg_private_colour;
	my $fg_private_colour;
	eval {
		my $guid = $self->get_guid;
		if ($guid) {
			$bg_private_colour =
			  $self->{'prefstore'}
			  ->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'Export', 'bg_private_colour' );
			$fg_private_colour =
			  $self->{'prefstore'}
			  ->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'Export', 'fg_private_colour' );
		}
	};
	my $bg      = $bg_private_colour // '#cc3956';
	my $fg      = $fg_private_colour // '#ffffff';
	my $q       = $self->{'cgi'};
	my $display = $self->{'plugin_prefs'}->{'private_fieldset'} ? 'block' : 'none';
	say qq(<fieldset id="private_fieldset" style="float:left;display:$display">)
	  . q(<legend>Private records</legend><ul><li>);
	say $q->checkbox(
		-name     => 'private_record',
		-id       => 'private_record',
		-value    => 'checked',
		-label    => 'Indicate private records',
		-checked  => 1,
		-onChange => 'enable_private_controls()'
	);
	say q(</li><li>);
	say $q->checkbox(
		-name     => 'private_owner',
		-id       => 'private_owner',
		-value    => 'checked',
		-label    => 'List owner',
		-checked  => 1,
		-onChange => 'enable_private_controls()'
	);
	say q(</li><li>);
	say $q->radio_group(
		-name      => 'private_name',
		-id        => 'private_name',
		-values    => [ 'user_id', 'name' ],
		-labels    => { user_id => 'user id', name => 'name/affiliation' },
		-default   => 'name',
		-linebreak => 'true'
	);
	say q(</li><li>);
	say qq(<input type="color" name="private_fg" id="private_fg" value="$fg" )
	  . q(style="width:30px;height:15px"> Text colour);
	say q(</li><li>);
	say qq(<input type="color" name="private_bg" id="private_bg" value="$bg" )
	  . q(style="width:30px;height:15px"> Background colour);
	say q(</li></li>);
	say q(<span id="example_private" style="border:1px solid #aaa;)
	  . qq(background:$bg;color:$fg;padding:0 0.2em">example private record</span>);
	say q(</li></ul></fieldset>);
	$self->{'private_fieldset'} = 1;
	return;
}

sub _print_options {
	my ($self)  = @_;
	my $q       = $self->{'cgi'};
	my $display = $self->{'plugin_prefs'}->{'options_fieldset'} ? 'block' : 'none';
	say qq(<fieldset id="options_fieldset" style="float:left;display:$display">) . q(<legend>Options</legend><ul></li>);
	say $q->checkbox(
		-name     => 'indicate_tags',
		-id       => 'indicate_tags',
		-label    => 'Indicate sequence status',
		-onChange => 'enable_tag_controls()'
	);
	say $self->get_tooltip( q(Indicate sequence status - Where alleles have not been designated but the )
		  . q(sequence has been tagged in the sequence bin, [S] will be shown. If the tagged sequence is incomplete )
		  . q(then [I] will also be shown. if more than one sequence tag is found, the number of tags will be )
		  . q(indicated with a number after the S or I.) );
	say q(<ul><li>);
	say $q->radio_group(
		-name      => 'indicate_tags_when',
		-id        => 'indicate_tags_when',
		-values    => [ 'no_designation', 'always' ],
		-labels    => { no_designation => 'if no allele defined', always => 'always' },
		-default   => 'no_designation',
		-linebreak => 'true'
	);
	say q(</li></ul>);
	say q(</li><li>);
	say $q->checkbox( -name => 'common_names', -id => 'common_names', -label => 'Include locus common names' );
	say q(</li><li>);
	say $q->checkbox( -name => 'alleles', -id => 'alleles', -label => 'Export allele numbers', -checked => 'checked' );
	say q(</li><li>);
	say $q->checkbox(
		-name     => 'oneline',
		-id       => 'oneline',
		-label    => 'Use one row per field',
		-onChange => 'enable_tag_controls()'
	);
	say q(</li><li>);
	say $q->checkbox(
		-name  => 'labelfield',
		-id    => 'labelfield',
		-label => "Include $self->{'system'}->{'labelfield'} field in row (used only with 'one row' option)"
	);
	say q(</li><li>);
	say $q->checkbox(
		-name  => 'info',
		-id    => 'info',
		-label => q(Export full allele designation record (used only with 'one row' option))
	);
	say q(</li></ul></fieldset>);
	return;
}

sub _print_classification_scheme_fields {
	my ($self) = @_;
	my $classification_schemes =
	  $self->{'datastore'}->run_query( 'SELECT id,name FROM classification_schemes ORDER BY display_order,name',
		undef, { fetch => 'all_arrayref', slice => {} } );
	return if !@$classification_schemes;
	my $display = $self->{'plugin_prefs'}->{'classification_fieldset'} ? 'block' : 'none';
	my $ids     = [];
	my $labels  = {};
	foreach my $cf (@$classification_schemes) {
		push @$ids, $cf->{'id'};
		$labels->{ $cf->{'id'} } = $cf->{'name'};
	}
	say qq(<fieldset id="classification_fieldset" style="float:left;display:$display">)
	  . q(<legend>Classification schemes</legend>);
	say $self->popup_menu(
		-name     => 'classification_schemes',
		-id       => 'classification_schemes',
		-values   => $ids,
		-labels   => $labels,
		-size     => 8,
		-multiple => 'true',
		-style    => 'width:100%'
	);
	say q(</fieldset>);
	$self->{'classification_fieldset'} = 1;
	return;
}

sub _print_lincode_fieldset {
	my ($self) = @_;
	my $lincode_schemes =
	  $self->{'datastore'}->run_query(
		'SELECT s.id,ls.thresholds FROM lincode_schemes ls JOIN ' . 'schemes s ON ls.scheme_id=s.id ORDER BY s.name',
		undef, { fetch => 'all_arrayref', slice => {} } );
	return if !@$lincode_schemes;
	my $ids    = [];
	my $labels = {};
	my $set_id = $self->get_set_id;
	foreach my $scheme (@$lincode_schemes) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme->{'id'}, { set_id => $set_id } );
		my @thresholds  = split( ';', $scheme->{'thresholds'} );
		foreach my $i ( 1 .. @thresholds - 1 ) {
			my $id = "linp_$scheme->{'id'}_$i";
			push @$ids, $id;
			$labels->{$id} = "LINcode ($scheme_info->{'name'})[$i]";
		}
	}
	my $display = $self->{'plugin_prefs'}->{'lincode_fieldset'} ? 'block' : 'none';
	say qq(<fieldset id="lincode_fieldset" style="float:left;display:$display;max-width:400px">)
	  . q(<legend>LIN code prefixes</legend><p>Selecting a scheme and all fields for it will include )
	  . q(the full LIN code and prefix-linked fields. The following list just allows you to select )
	  . q(LIN code prefixes of a specific length.</p><ul></li>);
	say $self->popup_menu(
		-name     => 'lincode_prefixes',
		-id       => 'lincode_prefixes',
		-values   => $ids,
		-labels   => $labels,
		-size     => 8,
		-multiple => 'true',
		-style    => 'width:100%'
	);
	say q(</li></ul></fieldset>);
	$self->{'lincode_fieldset'} = 1;
	return;
}

sub _print_analysis_fields {
	my ($self) = @_;
	my $fields = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM analysis_fields)');
	return if !$fields;
	my $q = $self->{'cgi'};
	my ( $values, $labels ) =
	  $self->get_analysis_field_values_and_labels( { prefix => 'af_', no_blank_value => 1 } );
	my $display = $self->{'plugin_prefs'}->{'analysis_fieldset'} ? 'block' : 'none';
	say qq(<fieldset id="analysis_fieldset" style="float:left;display:$display">)
	  . q(<legend>Analysis results</legend>);
	say $q->scrolling_list(
		-name     => 'analysis_fields',
		-id       => 'analysis_fields',
		-values   => $values,
		-labels   => $labels,
		-size     => 8,
		-multiple => 'true',
		-style    => 'width:100%'
	);
	say q(</fieldset>);
	$self->{'analysis_fieldset'} = 1;
	return;
}

sub _print_molwt_options {
	my ($self)  = @_;
	my $display = $self->{'plugin_prefs'}->{'molwt_fieldset'} ? 'block' : 'none';
	my $q       = $self->{'cgi'};
	say qq(<fieldset id="molwt_fieldset" style="float:left;display:$display">)
	  . q(<legend>Molecular weights</legend><ul></li>);
	say $q->checkbox( -name => 'molwt', -id => 'molwt', -label => 'Export protein molecular weights' );
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'met',
		-id      => 'met',
		-label   => 'GTG/TTG at start codes for methionine',
		-checked => 'checked'
	);
	say q(</li></ul></fieldset>);
	return;
}

sub _update_prefs {
	my ($self) = @_;
	return if !$self->_may_access_private_records;
	my $q    = $self->{'cgi'};
	my $guid = $self->get_guid;
	eval {
		if ( $q->param('private_bg') ) {
			$self->{'prefstore'}->set_plugin_attribute( $guid, $self->{'system'}->{'db'},
				'Export', 'bg_private_colour', scalar $q->param('private_bg') );
		}
		if ( $q->param('private_fg') ) {
			$self->{'prefstore'}->set_plugin_attribute( $guid, $self->{'system'}->{'db'},
				'Export', 'fg_private_colour', scalar $q->param('private_fg') );
		}
	};
	return;
}

sub _save_options {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $guid   = $self->get_guid;
	foreach my $fieldset (qw(eav composite refs private classification lincode analysis molwt options)) {
		$self->{'prefstore'}->set_plugin_attribute( $guid, $self->{'system'}->{'db'},
			'Export', "${fieldset}_fieldset", scalar $q->param($fieldset) // 0 );
	}
	return;
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('save_options') ) {
		$self->_save_options;
		return;
	}
	say q(<h1>Export dataset</h1>);
	if ( ( $self->{'system'}->{'DatasetExport'} // q() ) eq 'no' ) {
		$self->print_bad_status( { message => q(Dataset exports are disabled.) } );
		return;
	}
	return if $self->has_set_changed;
	if ( $q->param('submit') ) {
		$self->_update_prefs;
		my $selected_fields = $self->get_selected_fields(
			{
				locus_extended_attributes => 1,
				lincodes                  => 1,
				lincode_fields            => 1,
				analysis_fields           => 1 =>,
				lincode_prefixes          => 1
			}
		);
		$q->delete('classification_schemes');
		push @$selected_fields, 'm_references'   if $q->param('m_references');
		push @$selected_fields, 'private_record' if $q->param('private_record');
		push @$selected_fields, 'private_owner'  if $q->param('private_owner');
		if ( !@$selected_fields ) {
			$self->print_bad_status( { message => q(No fields have been selected!) } );
			$self->_print_interface;
			return;
		}
		my $prefix   = BIGSdb::Utils::get_random();
		my $filename = "$prefix.txt";
		my $ids      = $self->filter_list_to_ids( [ $q->multi_param('isolate_id') ] );
		my ( $pasted_cleaned_ids, $invalid_ids ) = $self->get_ids_from_pasted_list( { dont_clear => 1 } );
		push @$ids, @$pasted_cleaned_ids;
		@$ids = uniq @$ids;
		if ( !@$ids ) {
			$self->print_bad_status( { message => q(No valid ids have been selected!) } );
			$self->_print_interface;
			return;
		}
		if (@$invalid_ids) {
			local $" = ', ';
			$self->print_bad_status(
				{ message => qq(The following isolates in your pasted list are invalid: @$invalid_ids.) } );
			$self->_print_interface;
			return;
		}
		$q->delete('isolate_paste_list');
		$q->delete('isolate_id');
		my $set_id = $self->get_set_id;
		my $params = $q->Vars;
		$params->{'set_id'}      = $set_id if $set_id;
		$params->{'curate'}      = 1       if $self->{'curate'};
		$params->{'script_name'} = $self->{'system'}->{'script_name'};
		local $" = '||';
		$params->{'selected_fields'} = "@$selected_fields";
		my $max_instant_run =
		  BIGSdb::Utils::is_int( $self->{'config'}->{'export_instant_run'} )
		  ? $self->{'config'}->{'export_instant_run'}
		  : MAX_INSTANT_RUN;

		if ( @$ids > $max_instant_run && $self->{'config'}->{'jobs_db'} ) {
			my $att       = $self->get_attributes;
			my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
			my $job_id    = $self->{'jobManager'}->add_job(
				{
					dbase_config => $self->{'instance'},
					ip_address   => $q->remote_host,
					module       => $att->{'module'},
					priority     => $att->{'priority'},
					parameters   => $params,
					username     => $self->{'username'},
					email        => $user_info->{'email'},
					isolates     => $ids
				}
			);
			say $self->get_job_redirect($job_id);
			return;
		}
		say q(<div class="box" id="resultstable">);
		say q(<p>Please wait for processing to finish (do not refresh page).</p>);
		say q(<p class="hideonload"><span class="wait_icon fas fa-sync-alt fa-spin fa-4x"></span></p>);
		print q(<p>Output files being generated ...);
		my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
		$self->_write_tab_text(
			{
				ids      => $ids,
				fields   => $selected_fields,
				filename => $full_path,
				set_id   => $set_id,
				params   => $params
			}
		);
		say q( done</p>);
		my ( $excel_file, $text_file ) = ( EXCEL_FILE, TEXT_FILE );
		print qq(<p><a href="/tmp/$filename" target="_blank" title="Tab-delimited text file">$text_file</a>);
		my $format = $self->_get_excel_formatting(
			{
				private_bg => scalar $q->param('private_bg'),
				private_fg => scalar $q->param('private_fg')
			}
		);
		my $excel = BIGSdb::Utils::text2excel(
			$full_path,
			{
				worksheet              => 'Export',
				tmp_dir                => $self->{'config'}->{'secure_tmp_dir'},
				text_fields            => $self->{'system'}->{'labelfield'},
				conditional_formatting => $format
			}
		);
		say qq(<a href="/tmp/$prefix.xlsx" target="_blank" title="Excel file">$excel_file</a>)
		  if -e $excel;
		say q(</p>);
		say q(</div>);
		return;
	}
	$self->_print_interface;
	return;
}

sub _get_excel_formatting {
	my ( $self, $args ) = @_;
	my $format = [];
	if ( $self->{'private_col'} ) {
		push @$format,
		  {
			col    => $self->{'private_col'},
			value  => 'true',
			format => {
				bg_color => $args->{'private_bg'} // '#cc3956',
				color    => $args->{'private_fg'} // '#ffffff'
			},
			apply_to_row => 1
		  };
	}
	return $format;
}

sub _print_onboarding {
	my ($self) = @_;
	say q(<div id="onboarding" style="max-width:300px"><h2 style="color:white">More options</h2>)
	  . q(<p>Please note that some export options are now hidden by default but are available for )
	  . q(selection by clicking the 'Modify Form' tab at the top-right of the page.</p>)
	  . q(<button id="close_onboarding">Close</button></div>);
	return;
}

sub _print_interface {
	my ( $self, $default_select ) = @_;
	$self->_print_onboarding;
	my $q          = $self->{'cgi'};
	my $set_id     = $self->get_set_id;
	my $query_file = $q->param('query_file');
	my $selected_ids;
	if ( $q->param('isolate_id') ) {
		my @ids = $q->multi_param('isolate_id');
		$selected_ids = \@ids;
	} elsif ( defined $query_file ) {
		my $qry_ref = $self->get_query($query_file);
		$selected_ids = $self->get_ids_from_query($qry_ref);
	} else {
		$selected_ids = [];
	}
	say q(<div class="box" id="queryform"><div class="scrollable">);
	say q(<p>This script will export the dataset in tab-delimited text and Excel formats. )
	  . q(Select which fields you would like included. Select loci either from the locus list or by selecting one or )
	  . q(more schemes to include all loci (and/or fields) from a scheme.</p>);
	foreach my $suffix (qw (shtml html)) {
		my $policy = "$ENV{'DOCUMENT_ROOT'}$self->{'system'}->{'webroot'}/policy.$suffix";
		if ( -e $policy ) {
			say q(<p>Use of exported data is subject to the terms of the )
			  . qq(<a href='$self->{'system'}->{'webroot'}/policy.$suffix'>policy document</a>!</p>);
			last;
		}
	}
	my $guid = $self->get_guid;
	$self->{'plugin_prefs'} = $self->{'prefstore'}->get_plugin_attributes( $guid, $self->{'system'}->{'db'}, 'Export' );
	say $q->start_form;
	$self->print_seqbin_isolate_fieldset( { use_all => 1, selected_ids => $selected_ids, isolate_paste_list => 1 } );
	$self->print_isolate_fields_fieldset(
		{ extended_attributes => 1, default => [ 'id', $self->{'system'}->{'labelfield'} ], no_all_none => 1 } );
	$self->print_eav_fields_fieldset( { no_all_none => 1, hide => $self->{'plugin_prefs'}->{'eav_fieldset'} ? 0 : 1 } );
	$self->print_composite_fields_fieldset( { hide => $self->{'plugin_prefs'}->{'composite_fieldset'} ? 0 : 1 } );
	$self->_print_ref_fields;
	$self->_print_private_fieldset;
	$self->print_isolates_locus_fieldset( { locus_paste_list => 1, no_all_none => 1, locus_extended_attributes => 1 } );
	$self->print_scheme_fieldset( { fields_or_loci => 1 } );
	$self->_print_classification_scheme_fields;
	$self->_print_analysis_fields;
	$self->_print_lincode_fieldset;
	$self->_print_options;
	$self->_print_molwt_options;
	$self->print_action_fieldset( { no_reset => 1 } );
	say q(<div style="clear:both"></div>);
	$self->_print_modify_search_fieldset;
	$q->param( set_id => $set_id );
	say $q->hidden($_) foreach qw (db page name set_id);
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	$self->{'exit'} = 0;

	#Terminate cleanly on kill signals
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1 } ) x 3;
	$self->{'system'}->{'script_name'} = $params->{'script_name'};
	my $filename = "$self->{'config'}->{'tmp_dir'}/$job_id.txt";
	my @fields   = split /\|\|/x, $params->{'selected_fields'};
	$params->{'job_id'} = $job_id;
	my $ids = $self->{'jobManager'}->get_job_isolates($job_id);
	my $limit =
	  BIGSdb::Utils::is_int( $self->{'system'}->{'export_limit'} )
	  ? $self->{'system'}->{'export_limit'}
	  : MAX_DEFAULT_DATA_POINTS;
	my $data_points = @$ids * @fields;

	if ( $data_points > $limit ) {
		my $nice_data_points = BIGSdb::Utils::commify($data_points);
		my $nice_limit       = BIGSdb::Utils::commify($limit);
		my $msg = qq(<p>The submitted job is too big - you requested output containing $nice_data_points data points )
		  . qq((isolates x fields). Jobs are limited to $nice_limit data points.</p>);
		$self->{'jobManager'}->update_job_status( $job_id, { status => 'failed', message_html => $msg } );
		return;
	}
	$self->_write_tab_text(
		{
			ids      => $ids,
			fields   => \@fields,
			filename => $filename,
			set_id   => $params->{'set_id'},
			offline  => 1,
			params   => $params
		}
	);
	return if $self->{'exit'};
	if ( -e $filename ) {
		$self->{'jobManager'}->update_job_output(
			$job_id,
			{
				filename      => "$job_id.txt",
				description   => '01_Export table (text)',
				compress      => 1,
				keep_original => 1                           #Original needed to generate Excel file
			}
		);
		$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Creating Excel file' } );
		$self->{'db'}->commit;                               #prevent idle in transaction table locks
		my $format = $self->_get_excel_formatting(
			{
				private_bg => $params->{'private_bg'},
				private_fg => $params->{'private_fg'}
			}
		);
		my $excel_file = BIGSdb::Utils::text2excel(
			$filename,
			{
				worksheet              => 'Export',
				tmp_dir                => $self->{'config'}->{'secure_tmp_dir'},
				text_fields            => $self->{'system'}->{'labelfield'},
				conditional_formatting => $format
			}
		);
		if ( -e $excel_file ) {
			$self->{'jobManager'}->update_job_output( $job_id,
				{ filename => "$job_id.xlsx", description => '02_Export table (Excel)', compress => 1 } );
		}
		unlink $filename if -e "$filename.gz";
	}
	return;
}

sub _write_tab_text {
	my ( $self, $args ) = @_;
	my ( $ids, $fields, $filename, $set_id, $offline, $params ) =
	  @{$args}{qw(ids fields filename set_id offline params)};
	$self->{'datastore'}->create_temp_list_table_from_array( 'integer', $ids, { table => 'temp_list' } );
	open( my $fh, '>:encoding(utf8)', $filename )
	  || $logger->error("Can't open temp file $filename for writing");
	my ( $header, $error ) = $self->_get_header( $fields, $set_id, $params );
	say $fh $header;
	return if $error;
	my $fields_to_bind = $self->{'xmlHandler'}->get_field_list;
	local $" = q(,);
	my $sql =
	  $self->{'db'}->prepare(
		"SELECT @$fields_to_bind FROM $self->{'system'}->{'view'} WHERE id IN (SELECT value FROM temp_list) ORDER BY id"
	  );
	eval { $sql->execute };
	$logger->error($@) if $@;
	my %data = ();
	$sql->bind_columns( map { \$data{ lc $_ } } @$fields_to_bind )
	  ;    #quicker binding hash to arrayref than to use hashref
	my $i = 0;
	my $j = 0;
	local $| = 1;
	my %id_used;
	my $total    = 0;
	my $progress = 0;

	while ( $sql->fetchrow_arrayref ) {
		undef $self->{'cache'}->{'current_lincode'};
		next
		  if $id_used{ $data{'id'} }
		  ;    #Ordering by scheme field/locus can result in multiple rows per isolate if multiple values defined.
		$id_used{ $data{'id'} } = 1;
		if ( !$offline ) {
			print q(.) if !$i;
			print q( ) if !$j;
		}
		if ( !$i && $ENV{'MOD_PERL'} ) {
			eval { $self->{'mod_perl_request'}->rflush };
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
		my $first             = 1;
		my $all_allele_ids    = $self->{'datastore'}->get_all_allele_ids( $data{'id'} );
		my $allele_tag_counts = {};
		if ( $params->{'indicate_tags'} ) {
			my $counts =
			  $self->{'datastore'}->run_query( 'SELECT locus,complete FROM allele_sequences WHERE isolate_id=?',
				$data{'id'}, { fetch => 'all_arrayref', slice => {} } );
			foreach my $tag (@$counts) {
				$allele_tag_counts->{ $tag->{'locus'} }->{'count'}++;
				$allele_tag_counts->{ $tag->{'locus'} }->{'incomplete'}++ if !$tag->{'complete'};
			}
		}
		foreach my $field (@$fields) {
			my $regex = {
				field                    => qr/^f_(.*)/x,
				eav_field                => qr/^eav_(.*)/x,
				locus                    => qr/^(s_\d+_l_|l_)(.*)/x,
				locus_extended_attribute => qr/^lex_(.+)\|_\|(.+)/x,
				scheme_field             => qr/^s_(\d+)_f_(.*)/x,
				lincode                  => qr/^lin_(\d+)$/x,
				lincode_prefix           => qr/^linp_(\d+)_(\d+)$/x,
				lincode_field            => qr/^lin_(\d+)_(.+)$/x,
				composite_field          => qr/^c_(.*)/x,
				classification_scheme    => qr/^cs_(.*)/x,
				reference                => qr/^m_references/x,
				private_record           => qr/^private_record$/x,
				private_owner            => qr/^private_owner$/x,
				analysis_field           => qr/^af_(.*)___(.*)/x
			};
			my $methods = {
				field     => sub { $self->_write_field( $fh, $1, \%data, $first, $params ) },
				eav_field => sub { $self->_write_eav_field( $fh, $1, \%data, $first, $params ) },
				locus     => sub {
					$self->_write_allele(
						{
							fh                => $fh,
							locus             => $2,
							data              => \%data,
							all_allele_ids    => $all_allele_ids,
							allele_tag_counts => $allele_tag_counts,
							first             => $first,
							params            => $params
						}
					);
				},
				locus_extended_attribute => sub {
					$self->_write_locus_extended_attributes(
						{
							fh        => $fh,
							locus     => $1,
							attribute => $2,
							data      => \%data,
							first     => $first,
							params    => $params
						}
					);
				},
				scheme_field => sub {
					$self->_write_scheme_field(
						{ fh => $fh, scheme_id => $1, field => $2, data => \%data, first => $first, params => $params }
					);
				},
				lincode => sub {
					$self->_write_lincode(
						{ fh => $fh, scheme_id => $1, data => \%data, first => $first, params => $params } );
				},
				lincode_prefix => sub {
					$self->_write_lincode_prefix_field(
						{
							fh        => $fh,
							scheme_id => $1,
							threshold => $2,
							data      => \%data,
							first     => $first,
							params    => $params
						}
					);
				},
				lincode_field => sub {
					$self->_write_lincode_field(
						{ fh => $fh, scheme_id => $1, field => $2, data => \%data, first => $first, params => $params }
					);
				},
				composite_field => sub {
					$self->_write_composite( $fh, $1, \%data, $first, $params );
				},
				classification_scheme => sub {
					$self->_write_classification_scheme( $fh, $1, \%data, $first, $params );
				},
				reference => sub {
					$self->_write_ref( $fh, \%data, $first, $params );
				},
				private_record => sub {
					$self->_write_private( $fh, \%data, $first, $params );
				},
				private_owner => sub {
					$self->_write_private_owner( $fh, \%data, $first, $params );
				},
				analysis_field => sub {
					$self->_write_analysis_field(
						{
							fh            => $fh,
							analysis_name => $1,
							field_name    => $2,
							data          => \%data,
							first         => $first,
							params        => $params
						}
					);
				}
			};
			foreach my $field_type (
				qw(field eav_field locus scheme_field lincode lincode_prefix lincode_field composite_field
				classification_scheme reference private_record private_owner analysis_field locus_extended_attribute)
			  )
			{
				if ( $field =~ $regex->{$field_type} ) {
					$methods->{$field_type}->();
					last;
				}
			}
			$first = 0;
		}
		print $fh "\n" if !$params->{'oneline'};
		$i++;
		if ( $i == 50 ) {
			$i = 0;
			$j++;
		}
		$j = 0 if $j == 10;
		$total++;
		if ( $offline && $params->{'job_id'} ) {
			my $new_progress = int( $total / @$ids * 100 );

			#Only update when progress percentage changes when rounded to nearest 1 percent
			if ( $new_progress > $progress ) {
				$progress = $new_progress;
				$self->{'jobManager'}->update_job_status( $params->{'job_id'}, { percent_complete => $progress } );
				$self->{'db'}->commit;    #prevent idle in transaction table locks
			}
			last if $self->{'exit'};
		}
	}
	close $fh;
	return;
}

sub _get_header {
	my ( $self, $fields, $set_id, $params ) = @_;
	my $buffer;
	if ( $params->{'oneline'} ) {
		$buffer .= "id\t";
		$buffer .= $self->{'system'}->{'labelfield'} . "\t" if $params->{'labelfield'};
		$buffer .= "Field\tValue";
		$buffer .= "\tCurator\tDatestamp\tComments" if $params->{'info'};
	} else {
		my $first = 1;
		my %schemes;
		my $i = 0;
		foreach (@$fields) {
			my $field = $_;    #don't modify @$fields
			if (   $field =~ /^s_(\d+)_f/x
				|| $field =~ /^lin_(\d+)$/x
				|| $field =~ /^lin_(\d+)_(.+)$/x
				|| $field =~ /^linp_(\d+)_(\d+)$/x )
			{
				my $scheme_id = $1;
				my $scheme_info =
				  $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
				if ( $field =~ /^lin_(\d+)$/x ) {
					$field = 'LINcode';
				} elsif ( $field =~ /^linp_(\d+)_(\d+)/x ) {
					$field = "LINcode[$2]";
				} elsif ( defined $2 ) {    #Lincode prefix field
					$field = $2;
				}
				$field .= " ($scheme_info->{'name'})"
				  if $scheme_info->{'name'};
				$schemes{$scheme_id} = 1;
			}
			my $is_locus = $field =~ /^(s_\d+_l_|l_)/x ? 1 : 0;
			my ( $cscheme, $is_cscheme );
			if ( $field =~ /^cs_(\d+)/x ) {
				$is_cscheme = 1;
				$cscheme    = $1;
			}
			$field =~ s/^(?:s_\d+_l|s_\d+_f|f|l|c|m|cs|eav)_//x;    #strip off prefix for header row
			$field =~ s/^.*___//x;
			if ( $field =~ /^lex_/x ) {
				$field =~ s/^lex_//x;
				$field =~ s/\|_\|/ /x;
			}
			if ($is_locus) {
				$field =
				  $self->clean_locus( $field,
					{ text_output => 1, ( no_common_name => $params->{'common_names'} ? 0 : 1 ) } );
				if ( $params->{'alleles'} ) {
					$buffer .= "\t" if !$first;
					$buffer .= $field;
				}
				if ( $params->{'molwt'} ) {
					$buffer .= "\t" if !$first;
					$buffer .= "$field Mwt";
				}
			} elsif ($is_cscheme) {
				$buffer .= "\t" if !$first;
				my $name =
				  $self->{'datastore'}->run_query( 'SELECT name FROM classification_schemes WHERE id=?', $cscheme );
				$buffer .= $name;
				my $cscheme_fields =
				  $self->{'datastore'}->run_query(
					'SELECT field FROM classification_group_fields WHERE cg_scheme_id=? ORDER BY field_order,field',
					$cscheme, { fetch => 'col_arrayref' } );
				local $" = "\t";
				$buffer .= "\t@$cscheme_fields" if @$cscheme_fields;
			} else {
				$buffer .= "\t" if !$first;
				$buffer .= $field;
			}
			$first = 0;
			$self->{'private_col'} = $i if $field eq 'private_record';
			$i++;
		}
		if ($first) {
			$buffer .= 'Make sure you select an option for locus export.';
			return ( $buffer, 1 );
		}
	}
	return ( $buffer, 0 );
}

sub _get_id_one_line {
	my ( $self, $data, $params ) = @_;
	my $buffer = "$data->{'id'}\t";
	$data->{ $self->{'system'}->{'labelfield'} } //= q();
	$buffer .= "$data->{$self->{'system'}->{'labelfield'}}\t" if $params->{'labelfield'};
	return $buffer;
}

sub _write_field {
	my ( $self, $fh, $field, $data, $first, $params ) = @_;
	if ( $field eq 'aliases' ) {
		my $aliases = $self->{'datastore'}->get_isolate_aliases( $data->{'id'} );
		local $" = '; ';
		if ( $params->{'oneline'} ) {
			print $fh $self->_get_id_one_line( $data, $params );
			print $fh "aliases\t@$aliases\n";
		} else {
			print $fh "\t" if !$first;
			print $fh "@$aliases";
		}
	} elsif ( $field =~ /(.*)___(.*)/x ) {
		my ( $isolate_field, $attribute ) = ( $1, $2 );
		my $value = $self->{'datastore'}->run_query(
			'SELECT value FROM isolate_value_extended_attributes WHERE '
			  . '(isolate_field,attribute,field_value)=(?,?,?)',
			[ $isolate_field, $attribute, $data->{$isolate_field} ],
			{ cache => 'Export::extended_attributes' }
		);
		if ( $params->{'oneline'} ) {
			print $fh $self->_get_id_one_line( $data, $params );
			print $fh "$attribute\t";
			print $fh $value if defined $value;
			print $fh "\n";
		} else {
			print $fh "\t"   if !$first;
			print $fh $value if defined $value;
		}
	} else {
		my $value = $self->get_field_value( $data, $field );
		if ( $self->{'datastore'}->field_needs_conversion($field) ) {
			$value = $self->{'datastore'}->convert_field_value( $field, $value );
		}
		if ( $params->{'oneline'} ) {
			print $fh $self->_get_id_one_line( $data, $params );
			print $fh "$field\t";
			print $fh $value if defined $value;
			print $fh "\n";
		} else {
			print $fh "\t"   if !$first;
			print $fh $value if defined $value;
		}
	}
	return;
}

sub _write_eav_field {
	my ( $self, $fh, $field, $data, $first, $params ) = @_;
	my $value = $self->{'datastore'}->get_eav_field_value( $data->{'id'}, $field );
	if ( $params->{'oneline'} ) {
		print $fh $self->_get_id_one_line( $data, $params );
		print $fh "$field\t";
		print $fh $value if defined $value;
		print $fh "\n";
	} else {
		print $fh "\t"   if !$first;
		print $fh $value if defined $value;
	}
	return;
}

sub _sort_alleles {
	my ( $self, $locus, $allele_ids ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	return $allele_ids if !$locus_info || $allele_ids->[0] eq q();
	my @list = $locus_info->{'allele_id_format'} eq 'integer' ? sort { $a <=> $b } @$allele_ids : sort @$allele_ids;
	return \@list;
}

sub _write_allele {
	my ( $self, $args ) = @_;
	my ( $fh, $locus, $data, $all_allele_ids, $allele_tag_counts, $first_col, $params ) =
	  @{$args}{qw(fh locus data all_allele_ids allele_tag_counts first params)};
	my @unsorted_allele_ids = defined $all_allele_ids->{$locus} ? @{ $all_allele_ids->{$locus} } : (q());
	my $allele_ids          = $self->_sort_alleles( $locus, \@unsorted_allele_ids );
	if ( $params->{'alleles'} ) {
		my $first_allele = 1;
		my $seq_tag      = q();
		foreach my $allele_id (@$allele_ids) {
			if (
				$params->{'indicate_tags'}
				&& (   ( $allele_id eq q() && ( $params->{'indicate_tags_when'} // q() ) eq 'no_designation' )
					|| ( $params->{'indicate_tags_when'} // q() ) eq 'always' )
			  )
			{
				my $seq_count        = $allele_tag_counts->{$locus}->{'count'};
				my $incomplete_count = $allele_tag_counts->{$locus}->{'incomplete'};
				if ($seq_count) {
					$seq_count = q() if $seq_count <= 1;
					$seq_tag   = "[S$seq_count]";
					if ($incomplete_count) {
						$incomplete_count = q() if $incomplete_count <= 1;
						$seq_tag .= "[I$incomplete_count]";
					}
				}
			}
			if ( $params->{'oneline'} ) {
				next if $allele_id eq q();
				print $fh $self->_get_id_one_line( $data, $params );
				print $fh "$locus\t";
				print $fh $allele_id;
				if ( $params->{'info'} ) {
					my $allele_info = $self->{'datastore'}->run_query(
						'SELECT datestamp ,curator,comments FROM allele_designations WHERE '
						  . '(isolate_id,locus,allele_id)=(?,?,?)',
						[ $data->{'id'}, $locus, $allele_id ],
						{ fetch => 'row_hashref', cache => 'Export::write_allele::info' }
					);
					if ( defined $allele_info ) {
						my $user_string = $self->{'datastore'}->get_user_string( $allele_info->{'curator'} );
						print $fh "\t$user_string\t";
						print $fh "$allele_info->{'datestamp'}\t";
						print $fh $allele_info->{'comments'} if defined $allele_info->{'comments'};
					}
				}
				print $fh "\n";
			} else {
				if ( !$first_allele ) {
					print $fh ';';
				} elsif ( !$first_col ) {
					print $fh "\t";
				}
				print $fh "$allele_id";
			}
			$first_allele = 0;
		}
		print $fh $seq_tag if !$params->{'oneline'};
	}
	if ( $params->{'molwt'} ) {
		my $first_allele = 1;
		foreach my $allele_id (@$allele_ids) {
			if ( $params->{'oneline'} ) {
				print $fh $self->_get_id_one_line( $data, $params );
				print $fh "$locus MolWt\t";
				print $fh $self->_get_molwt( $locus, $allele_id, $params->{'met'} );
				print $fh "\n";
			} else {
				if ( !$first_allele ) {
					print $fh ',';
				} elsif ( !$first_col ) {
					print $fh "\t";
				}
				print $fh $self->_get_molwt( $locus, $allele_id, $params->{'met'} );
			}
			$first_allele = 0;
		}
	}
	return;
}

sub _write_locus_extended_attributes {
	my ( $self, $args ) = @_;
	my ( $fh, $locus, $attribute, $data, $first, $params ) =
	  @{$args}{qw(fh locus attribute data first params)};
	my $table  = $self->{'datastore'}->create_temp_sequence_extended_attributes_table( $locus, $attribute );
	my $values = $self->{'datastore'}->run_query(
		"SELECT value FROM $table a JOIN allele_designations ad ON (ad.isolate_id,ad.locus)=(?,?) "
		  . 'WHERE ad.allele_id=a.allele_id::text ORDER BY value',
		[ $data->{'id'}, $locus ],
		{ fetch => 'col_arrayref', cache => "Export::write_locus_extended_attributes::$table" }
	);
	@$values = uniq @$values;
	local $" = q(; );
	if ( $params->{'oneline'} ) {
		print $fh $self->_get_id_one_line( $data, $params );
		print $fh "$locus $attribute\t";
		print $fh "@$values";
		print $fh "\n";
	} else {
		print $fh "\t" if !$first;
		print $fh "@$values";
	}
	return;
}

sub _write_scheme_field {
	my ( $self, $args ) = @_;
	my ( $fh, $scheme_id, $field, $data, $first_col, $params ) = @{$args}{qw(fh scheme_id field data first params )};
	my $scheme_info  = $self->{'datastore'}->get_scheme_info($scheme_id);
	my $scheme_field = lc($field);
	my $values =
	  $self->get_scheme_field_values( { isolate_id => $data->{'id'}, scheme_id => $scheme_id, field => $field } );
	@$values = ('') if !@$values;
	my $first_value = 1;
	foreach my $value (@$values) {
		if ( $params->{'oneline'} ) {
			next if !defined $value || $value eq q();
			print $fh $self->_get_id_one_line( $data, $params );
			print $fh "$field ($scheme_info->{'name'})\t";
			print $fh $value;
			print $fh "\n";
		} else {
			if ( !$first_value ) {
				print $fh ';';
			} elsif ( !$first_col ) {
				print $fh "\t";
			}
			print $fh $value if defined $value;
		}
		$first_value = 0;
	}
	return;
}

sub _write_lincode {
	my ( $self, $args ) = @_;
	my ( $fh, $scheme_id, $data, $first_col, $params ) =
	  @{$args}{qw(fh scheme_id data first params )};
	my $lincode = $self->{'datastore'}->get_lincode_value( $data->{'id'}, $scheme_id );

	#LINcode fields are always calculated after the LINcode itself, so
	#we can just cache the last LINcode value rather than re-calculating it.
	$self->{'cache'}->{'current_lincode'} = $lincode;
	local $" = q(_);
	if ( $params->{'oneline'} ) {
		if ( defined $lincode ) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
			print $fh $self->_get_id_one_line( $data, $params );
			print $fh "LINcode ($scheme_info->{'name'})\t";
			print $fh qq(@$lincode) if defined $lincode;
			print $fh qq(\n);
		}
	} else {
		print $fh qq(\t)        if !$first_col;
		print $fh qq(@$lincode) if defined $lincode;
	}
	return;
}

sub _write_lincode_prefix_field {
	my ( $self, $args ) = @_;
	my ( $fh, $scheme_id, $threshold, $data, $first_col, $params ) =
	  @{$args}{qw(fh scheme_id threshold data first params )};
	my $lincode;
	if ( defined $self->{'cache'}->{'current_lincode'} ) {
		$lincode = $self->{'cache'}->{'current_lincode'};
	} else {
		$lincode = $self->{'datastore'}->get_lincode_value( $data->{'id'}, $scheme_id );
	}
	my @prefix = defined $lincode ? @{$lincode}[ 0 .. $threshold - 1 ] : ();
	local $" = q(_);
	if ( $params->{'oneline'} ) {
		if (@prefix) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
			print $fh $self->_get_id_one_line( $data, $params );
			print $fh "LINcode[$threshold] ($scheme_info->{'name'})\t";
			say $fh qq(@prefix);
		}
	} else {
		print $fh qq(\t) if !$first_col;
		print $fh qq(@prefix);
	}
	return;
}

sub _write_lincode_field {
	my ( $self, $args ) = @_;
	my ( $fh, $scheme_id, $field, $data, $first_col, $params ) =
	  @{$args}{qw(fh scheme_id field data first params )};
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
	if ( !$self->{'cache'}->{'lincode_prefixes'}->{$scheme_id} ) {
		my $prefix_table = $self->{'datastore'}->create_temp_lincode_prefix_values_table($scheme_id);
		my $prefix_data  = $self->{'datastore'}
		  ->run_query( "SELECT * FROM $prefix_table", undef, { fetch => 'all_arrayref', slice => {} } );
		foreach my $record (@$prefix_data) {
			$self->{'cache'}->{'lincode_prefixes'}->{$scheme_id}->{ $record->{'field'} }->{ $record->{'prefix'} } =
			  $record->{'value'};
		}
	}
	my $prefix_values = $self->{'cache'}->{'lincode_prefixes'}->{$scheme_id};
	my %used;
	my @prefixes = keys %{ $prefix_values->{$field} };
	my @values;
	foreach my $prefix (@prefixes) {

		#LINcode is always calculated immediately before LINcode fields so we have cached the
		#LINcode value in $self->{'cache'}->{'current_lincode'}.
		last if !ref $self->{'cache'}->{'current_lincode'};
		local $" = q(_);
		my $lincode = qq(@{ $self->{'cache'}->{'current_lincode'}});
		if (   $lincode eq $prefix
			|| $lincode =~ /^${prefix}_/x && !$used{ $prefix_values->{$field}->{$prefix} } )
		{
			push @values, $prefix_values->{$field}->{$prefix};
			$used{ $prefix_values->{$field}->{$prefix} } = 1;
		}
	}
	@values = sort @values;
	if ( $params->{'oneline'} ) {
		foreach my $value (@values) {
			print $fh $self->_get_id_one_line( $data, $params );
			print $fh "$field ($scheme_info->{'name'})\t";
			print $fh $value if defined $value;
			print $fh qq(\n);
		}
	} else {
		print $fh qq(\t) if !$first_col;
		local $" = q(; );
		print $fh qq(@values) if @values;
	}
	return;
}

sub _write_composite {
	my ( $self, $fh, $composite_field, $data, $first, $params ) = @_;
	my $value = $self->{'datastore'}->get_composite_value( $data->{'id'}, $composite_field, $data, { no_format => 1 } );
	if ( $params->{'oneline'} ) {
		print $fh $self->_get_id_one_line( $data, $params );
		print $fh "$composite_field\t";
		print $fh $value if defined $value;
		print $fh "\n";
	} else {
		print $fh "\t"   if !$first;
		print $fh $value if defined $value;
	}
	return;
}

sub _write_classification_scheme {
	my ( $self, $fh, $cscheme, $data, $first, $params ) = @_;
	if ( !$self->{'cache'}->{'cscheme_name'}->{$cscheme} ) {
		$self->{'cache'}->{'cscheme_name'}->{$cscheme} =
		  $self->{'datastore'}->run_query( 'SELECT name FROM classification_schemes WHERE id=?', $cscheme );
	}
	if ( !defined $self->{'cache'}->{'cscheme_fields'}->{$cscheme} ) {
		$self->{'cache'}->{'cscheme_fields'}->{$cscheme} =
		  $self->{'datastore'}
		  ->run_query( 'SELECT field FROM classification_group_fields WHERE cg_scheme_id=? ORDER BY field_order,field',
			$cscheme, { fetch => 'col_arrayref' } );
	}
	my $value = $self->get_cscheme_value( $data->{'id'}, $cscheme );
	if ( $params->{'oneline'} ) {
		if ( $self->{'cache'}->{'cscheme_cache_table_exists'}->{$cscheme} ) {
			print $fh $self->_get_id_one_line( $data, $params );
			print $fh "$self->{'cache'}->{'cscheme_name'}->{$cscheme}\t";
			print $fh $value if defined $value;
			print $fh "\n";
			foreach my $cscheme_field ( @{ $self->{'cache'}->{'cscheme_fields'}->{$cscheme} } ) {
				print $fh $self->_get_id_one_line( $data, $params );
				print $fh "$cscheme_field\t";
				my $field_value = $self->get_cscheme_field_value( $data->{'id'}, $cscheme, $cscheme_field );
				print $fh $field_value if defined $field_value;
				print $fh "\n";
			}
		}
	} else {
		print $fh "\t"   if !$first;
		print $fh $value if defined $value;
		foreach my $cscheme_field ( @{ $self->{'cache'}->{'cscheme_fields'}->{$cscheme} } ) {
			print $fh "\t";
			my $field_value = $self->get_cscheme_field_value( $data->{'id'}, $cscheme, $cscheme_field );
			print $fh $field_value if defined $field_value;
		}
	}
	return;
}

sub _write_ref {
	my ( $self, $fh, $data, $first, $params ) = @_;
	my $values = $self->{'datastore'}->get_isolate_refs( $data->{'id'} );
	if ( ( $params->{'ref_type'} // '' ) eq 'Full citation' ) {
		my $citation_hash = $self->{'datastore'}->get_citation_hash($values);
		my @citations;
		push @citations, $citation_hash->{$_} foreach @$values;
		$values = \@citations;
	}
	if ( $params->{'oneline'} ) {
		foreach my $value (@$values) {
			print $fh $self->_get_id_one_line( $data, $params );
			print $fh "references\t";
			print $fh "$value";
			print $fh "\n";
		}
	} else {
		print $fh "\t" if !$first;
		local $" = ';';
		print $fh "@$values";
	}
	return;
}

sub _write_private {
	my ( $self, $fh, $data, $first, $params ) = @_;
	my $private = $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM private_isolates WHERE isolate_id=?)',
		$data->{'id'}, { cache => 'Export::write_private' } );
	my $value = $private ? 'true' : 'false';
	if ( $params->{'oneline'} ) {
		print $fh $self->_get_id_one_line( $data, $params );
		print $fh "private\t";
		print $fh "$value";
		print $fh "\n";
	} else {
		print $fh "\t" if !$first;
		print $fh $value;
	}
	return;
}

sub _write_private_owner {
	my ( $self, $fh, $data, $first, $params ) = @_;
	my $value = $self->{'datastore'}->run_query( 'SELECT user_id FROM private_isolates WHERE isolate_id=?',
		$data->{'id'}, { cache => 'Export::write_private_owner' } );
	if ( defined $value ) {
		$value =
			$params->{'private_name'} eq 'name'
		  ? $self->{'datastore'}->get_user_string( $value, { affiliation => 1 } )
		  : $value;
	}
	$value //= q();
	if ( $params->{'oneline'} ) {
		print $fh $self->_get_id_one_line( $data, $params );
		print $fh "private_owner\t";
		print $fh "$value";
		print $fh "\n";
	} else {
		print $fh "\t" if !$first;
		print $fh $value;
	}
	return;
}

sub _write_analysis_field {
	my ( $self, $args ) = @_;
	my ( $analysis_name, $field_name, $fh, $data, $first, $params ) =
	  @{$args}{qw(analysis_name field_name fh data first params)};
	my $value = $self->{'datastore'}->run_query(
		'SELECT value FROM analysis_fields af JOIN analysis_results_cache arc '
		  . 'ON (af.analysis_name,af.json_path)=(arc.analysis_name,arc.json_path) '
		  . 'WHERE (af.analysis_name,af.field_name,arc.isolate_id)'
		  . '=(?,?,?)',
		[ $analysis_name, $field_name, $data->{'id'} ],
		{ fetch => 'col_arrayref', cache => 'Export::_write_analysis_field' }
	);
	local $" = q(; );
	my $values = qq(@$value) // q();
	if ( $params->{'oneline'} ) {
		print $fh $self->_get_id_one_line( $data, $params );
		print $fh "$field_name\t";
		say $fh $values;
	} else {
		print $fh "\t" if !$first;
		print $fh $values;
	}
	return;
}

sub _get_molwt {
	my ( $self, $locus_name, $allele, $met ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus_name);
	my $peptide;
	my $locus = $self->{'datastore'}->get_locus($locus_name);
	if ( $locus_info->{'data_type'} eq 'DNA' ) {
		my $seq_ref;
		try {
			if ( $allele ne '0' ) {
				$seq_ref = $locus->get_allele_sequence($allele);
			}
		} catch {    #do nothing
		};
		my $seq = BIGSdb::Utils::chop_seq( $$seq_ref, $locus_info->{'orf'} || 1 );
		if ($met) {
			$seq =~ s/^(TTG|GTG)/ATG/x;
		}
		if ($seq) {
			my $seq_obj = Bio::Seq->new( -seq => $seq, -alphabet => 'dna' );
			$peptide = $seq_obj->translate->seq;
		}
	} else {
		$peptide = ${ $locus->get_allele_sequence($allele) };
	}
	return if !$peptide;
	my $weight;
	try {
		my $seqobj    = Bio::PrimarySeq->new( -seq => $peptide, -id => $allele, -alphabet => 'protein', );
		my $seq_stats = Bio::Tools::SeqStats->new($seqobj);
		my $stats     = $seq_stats->get_mol_wt;
		$weight = $stats->[0];
	} catch {
		$weight = q(-);
	};
	return $weight;
}

sub _print_modify_search_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<div id="modify_panel" class="panel">);
	say q(<a class="close_trigger" id="close_trigger"><span class="fas fa-lg fa-times"></span></a>);
	say q(<h2>Modify form parameters</h2>);
	say q(<p>Click to add or remove additional<br />export category selections:</p>)
	  . q(<ul style="list-style:none;margin-left:-2em">);
	if ( $self->{'eav_fieldset'} ) {
		my $eav_fieldset_display = $self->{'plugin_prefs'}->{'eav_fieldset'} ? HIDE : SHOW;
		say qq(<li><a href="" class="button fieldset_trigger" id="show_eav">$eav_fieldset_display</a>);
		say q(Secondary metadata</li>);
	}
	if ( $self->{'composite_fieldset'} ) {
		my $composite_fieldset_display = $self->{'plugin_prefs'}->{'composite_fieldset'} ? HIDE : SHOW;
		say qq(<li><a href="" class="button fieldset_trigger" id="show_composite">$composite_fieldset_display</a>);
		say q(Composite fields</li>);
	}
	my $refs_display = $self->{'plugin_prefs'}->{'refs_fieldset'} ? HIDE : SHOW;
	say qq(<li><a href="" class="button fieldset_trigger" id="show_refs">$refs_display</a>);
	say q(References</li>);
	if ( $self->{'private_fieldset'} ) {
		my $private_display = $self->{'plugin_prefs'}->{'private_fieldset'} ? HIDE : SHOW;
		say qq(<li><a href="" class="button fieldset_trigger" id="show_private">$private_display</a>);
		say q(Private records</li>);
	}
	if ( $self->{'classification_fieldset'} ) {
		my $classification_display = $self->{'plugin_prefs'}->{'classification_fieldset'} ? HIDE : SHOW;
		say qq(<li><a href="" class="button fieldset_trigger" id="show_classification">$classification_display</a>);
		say q(Classification schemes</li>);
	}
	if ( $self->{'lincode_fieldset'} ) {
		my $lincode_display = $self->{'plugin_prefs'}->{'lincode_fieldset'} ? HIDE : SHOW;
		say qq(<li><a href="" class="button fieldset_trigger" id="show_lincode">$lincode_display</a>);
		say q(LIN code prefixes</li>);
	}
	if ( $self->{'analysis_fieldset'} ) {
		my $analysis_display = $self->{'plugin_prefs'}->{'analysis_fieldset'} ? HIDE : SHOW;
		say qq(<li><a href="" class="button fieldset_trigger" id="show_analysis">$analysis_display</a>);
		say q(Analysis fields</li>);
	}
	my $molwt_display = $self->{'plugin_prefs'}->{'molwt_fieldset'} ? HIDE : SHOW;
	say qq(<li><a href="" class="button fieldset_trigger" id="show_molwt">$molwt_display</a>);
	say q(Molecular weights</li>);
	my $options_display = $self->{'plugin_prefs'}->{'options_fieldset'} ? HIDE : SHOW;
	say qq(<li><a href="" class="button fieldset_trigger" id="show_options">$options_display</a>);
	say q(General options</li>);
	say q(</ul>);
	my $save = SAVE;
	say qq(<a id="save_options" class="button" href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=plugin&amp;name=Export&amp;save_options=1" style="display:none">$save</a> <span id="saving"></span><br />);
	say q(</div>);
	return;
}
1;
