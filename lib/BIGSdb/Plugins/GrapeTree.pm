#GrapeTree.pm - MST visualization plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2017-2019, University of Oxford
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
#
package BIGSdb::Plugins::GrapeTree;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugins::GenomeComparator);
use BIGSdb::Exceptions;
use List::MoreUtils qw(uniq all);
use Digest::MD5;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_RECORDS => 10_000;

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name                => 'GrapeTree',
		author              => 'Keith Jolley',
		affiliation         => 'University of Oxford, UK',
		email               => 'keith.jolley@zoo.ox.ac.uk',
		description         => 'Visualization of genomic relationships',
		menu_description    => 'Visualization of genomic relationships',
		category            => 'Third party',
		buttontext          => 'GrapeTree',
		menutext            => 'GrapeTree',
		module              => 'GrapeTree',
		version             => '1.3.7',
		dbtype              => 'isolates',
		section             => 'third_party,postquery',
		input               => 'query',
		help                => 'tooltips',
		requires            => 'offline_jobs,js_tree,GrapeTree',
		url                 => "$self->{'config'}->{'doclink'}/data_analysis/grapetree.html",
		order               => 20,
		min                 => 2,
		max                 => $self->_get_limit,
		always_show_in_menu => 1
	);
	return \%att;
}

sub _get_limit {
	my ($self) = @_;
	my $limit = $self->{'system'}->{'grapetree_limit'} // $self->{'config'}->{'grapetree_limit'} // MAX_RECORDS;
	return $limit;
}

sub print_info_panel {
	my ($self) = @_;
	my $logo = '/images/plugins/GrapeTree/logo.png';
	say q(<div class="box" id="resultspanel">);
	if ( -e "$ENV{'DOCUMENT_ROOT'}$logo" ) {
		say q(<div style="float:left">);
		say qq(<img src="$logo" style="width:100px" />);
		say q(</div>);
	}
	say q(<p>This plugin generates a minimum-spanning tree and visualizes within GrapeTree:</p>);
	say q(<p>GrapeTree is developed by: Zhemin Zhou (1), Nabil-Fareed Alikhan (1), Martin J. Sergeant (1),)
	  . q(Nina Luhmann (1), C&aacute;tia Vaz (2,5), Alexandre P. Francisco (2,4),)
	  . q(Jo&atilde;o Andr&eacute; Carri&ccedil;o (3) and Mark Achtman (1)</p>);
	say q(<ol style="overflow:hidden">);
	say q(<li>Warwick Medical School, University of Warwick, UK</li>);
	say q(<li>Instituto de Engenharia de Sistemas e Computadores: Investiga&ccedil;&atilde;o e Desenvolvimento )
	  . q((INESC-ID), Lisboa, Portugal</li>);
	say q(<li>Universidade de Lisboa, Faculdade de Medicina, Instituto de Microbiologia and Instituto de Medicina )
	  . q(Molecular, Lisboa, Portugal</li>);
	say q(<li>Instituto Superior T&eacute;cnico, Universidade de Lisboa, Lisboa, Portugal</li>);
	say q(<li>ADEETC, Instituto Superior de Engenharia de Lisboa, Instituto Polit&eacute;cnico de Lisboa, )
	  . q(Lisboa, Portugal</li>);
	say q(</ol>);
	say q(<p>Publication: Zhou <i>at al.</i> (2018) GrapeTree: Visualization of core genomic relationships among )
	  . q(100,000 bacterial pathogens. <a href="https://www.ncbi.nlm.nih.gov/pubmed/30049790"><i>Genome Res</i> )
	  . q(<b>28:</b>1395-1404</a>.</p>);
	say q(</div>);
	return;
}

sub _print_interface {
	my ( $self, $isolate_ids ) = @_;
	my $q = $self->{'cgi'};
	$self->print_info_panel;
	$self->print_scheme_selection_banner;
	say q(<div class="box" id="queryform">);
	say q(<p>This tool will generate minimum spanning trees trees from allelic profiles. )
	  . q(Please check the loci that you would like to include.  Alternatively select one or more )
	  . q(schemes to include all loci that are members of the scheme.</p>);
	my $limit         = $self->_get_limit;
	my $commify_limit = BIGSdb::Utils::commify($limit);
	say qq(<p>Analysis is limited to $commify_limit records.</p>);
	say $q->start_form;
	my $query_file = $q->param('query_file');
	my $list = $self->get_id_list( 'id', $query_file );
	$self->print_seqbin_isolate_fieldset( { use_all => 1, selected_ids => $list, isolate_paste_list => 1 } );
	$self->print_isolates_locus_fieldset( { locus_paste_list => 1 } );
	$self->print_recommended_scheme_fieldset;
	$self->print_scheme_fieldset( { fields_or_loci => 0 } );
	$self->_print_includes_fieldset;
	$self->_print_parameters_fieldset;
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach qw (db page name);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _print_includes_fieldset {
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	say q(<fieldset style="float:left"><legend>Include fields</legend>);
	say q(<p>Select additional fields to include in GrapeTree metadata.</p>);
	my ( $headings, $labels ) = $self->get_field_selection_list(
		{
			isolate_fields      => 1,
			extended_attributes => 1,
			loci                => 0,
			query_pref          => 0,
			analysis_pref       => 1,
			scheme_fields       => 1,
			sort_labels         => 1,
			eav_fields          => 1,
			set_id              => $set_id
		}
	);
	my $fields = [];
	foreach my $field (@$headings) {
		next if $field eq 'f_id';
		next if $field eq "f_$self->{'system'}->{'labelfield'}";
		push @$fields, $field;
	}
	say $self->popup_menu(
		-name     => 'include_fields',
		-id       => 'include_fields',
		-values   => $fields,
		-labels   => $labels,
		-multiple => 'true',
		-size     => 6
	);
	say q(</fieldset>);
	return;
}

sub _print_parameters_fieldset {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left;height:12em"><legend>Parameters / options</legend>);
	say q(<ul><li>);
	say $q->checkbox(
		-name  => 'rescan_missing',
		-id    => 'rescan_missing',
		-label => 'Rescan undesignated loci',
	);
	say $self->get_tooltip(
		    q(Rescan undesignated - By default, if a genome has >= 50% of the selected loci designated, it will not )
		  . q(be rescanned. Selecting this option will perform a BLAST query for each genome to attempt to fill in )
		  . q(any missing annotations. Please note that this will take <b>much longer</b> to run.) );
	say q(</li></ul></fieldset>);
	return;
}

sub run {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $desc   = $self->get_db_description;
	say qq(<h1>GrapeTree: Visualization of genomic relationships - $desc</h1>);
	my $isolate_ids = [];
	if ( $q->param('submit') ) {
		my $loci_selected = $self->get_selected_loci;
		my ( $pasted_cleaned_loci, $invalid_loci ) = $self->get_loci_from_pasted_list;
		$q->delete('locus');
		push @$loci_selected, @$pasted_cleaned_loci;
		@$loci_selected = uniq @$loci_selected;
		$self->add_scheme_loci($loci_selected);
		$self->add_recommended_scheme_loci($loci_selected);
		my @ids = $q->multi_param('isolate_id');
		my ( $pasted_cleaned_ids, $invalid_ids ) = $self->get_ids_from_pasted_list( { dont_clear => 1 } );
		push @ids, @$pasted_cleaned_ids;
		@ids = uniq @ids;
		my $continue = 1;
		my ( @errors, @info );

		if ( !@ids || @ids < 2 ) {
			push @errors, q(You must select at least two valid isolate id.);
		}
		if (@$invalid_ids) {
			local $" = q(, );
			push @info,
			  qq(The id list contained some invalid values - these will be ignored. Invalid values: @$invalid_ids.);
		}
		if ( !@$loci_selected ) {
			push @errors, q(You must select one or more loci or schemes.);
		}
		my $max_records         = $self->_get_limit;
		my $commify_max_records = BIGSdb::Utils::commify($max_records);
		if ( @ids > $max_records ) {
			my $commify_total_records = BIGSdb::Utils::commify( scalar @ids );
			push @errors, qq(Output is limited to a total of $commify_max_records records. )
			  . qq(You have selected $commify_total_records.);
		}
		if ( @errors || @info ) {
			say q(<div class="box" id="statusbad">);
			foreach my $msg ( @errors, @info ) {
				say qq(<p>$msg</p>);
			}
			say q(</div>);
			if (@errors) {
				$self->_print_interface;
				return;
			}
		}
		$self->set_scheme_param;
		my $params = $q->Vars;
		$params->{'set_id'} = $self->get_set_id;
		$q->delete('list');
		$q->delete('isolate_paste_list');
		$q->delete('locus_paste_list');
		$q->delete('isolate_id');

		foreach my $field_dataset (qw(itol_dataset include_fields)) {
			my @dataset = $q->multi_param($field_dataset);
			$q->delete($field_dataset);
			local $" = '|_|';
			$params->{$field_dataset} = "@dataset";
		}
		$params->{'includes'} = $self->{'system'}->{'labelfield'} if $q->param('include_name');
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		my $job_id    = $self->{'jobManager'}->add_job(
			{
				dbase_config => $self->{'instance'},
				ip_address   => $q->remote_host,
				module       => 'GrapeTree',
				parameters   => $params,
				username     => $self->{'username'},
				email        => $user_info->{'email'},
				loci         => $loci_selected,
				isolates     => \@ids
			}
		);
		say $self->get_job_redirect($job_id);
		return;
	}
	$self->_print_interface;
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	my $profile_file = "$self->{'config'}->{'tmp_dir'}/${job_id}_profiles.txt";
	my $tree_file    = "$self->{'config'}->{'tmp_dir'}/${job_id}_tree.nwk";
	my $tsv_file     = "$self->{'config'}->{'tmp_dir'}/${job_id}_metadata.txt";
	my $ids          = $self->{'jobManager'}->get_job_isolates($job_id);
	my $loci         = $self->{'jobManager'}->get_job_loci($job_id);
	( $ids, my $missing ) = $self->filter_missing_isolates($ids);
	if ( @$ids - @$missing < 2 ) {
		$self->{'jobManager'}->update_job_status(
			$job_id,
			{
				message_html =>
				  q(<p class="statusbad">There are fewer than 2 valid ids in the list - tree cannot be generated.</p>)
			}
		);
		return;
	}
	$self->_generate_profile_file(
		{
			job_id   => $job_id,
			file     => $profile_file,
			isolates => $ids,
			loci     => $loci,
			params   => $params,
		}
	);
	return if $self->{'exit'};
	$self->_generate_mstree(
		{
			job_id   => $job_id,
			profiles => $profile_file,
			tree     => $tree_file
		}
	);
	$self->_generate_tsv_file(
		{
			job_id   => $job_id,
			tsv_file => $tsv_file,
			params   => $params
		}
	);
	$self->{'jobManager'}->update_job_status(
		$job_id,
		{
			    message_html => q(<p style="margin-top:2em;margin-bottom:2em">)
			  . qq(<a href="$self->{'config'}->{'MSTree_holder_rel_path'}?tree=/tmp/${job_id}_tree.nwk&amp;)
			  . qq(metadata=/tmp/${job_id}_metadata.txt" target="_blank" )
			  . q(class="launchbutton">Launch GrapeTree</a></p>)
		}
	);
	return;
}

sub _generate_profile_file {
	my ( $self, $args ) = @_;
	my ( $job_id, $filename, $isolates, $loci, $params ) = @{$args}{qw(job_id file isolates loci params)};
	my $ids = $self->{'jobManager'}->get_job_isolates($job_id);
	$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Generating profile data file' } );
	$self->set_offline_view($params);
	$self->{'params'} = $params;
	$self->{'threads'} =
	  BIGSdb::Utils::is_int( $self->{'config'}->{'genome_comparator_threads'} )
	  ? $self->{'config'}->{'genome_comparator_threads'}
	  : 2;
	$self->{'params'}->{'finish_progress'} = 60;
	$self->{'exit'} = 0;

	#Allow temp files to be cleaned on kill signals
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1; $self->signal_kill_job($job_id) } ) x 3;
	my %profile_hash;
	my $empty_profiles = 0;
	my $scan_data;
	eval { $scan_data = $self->assemble_data_for_defined_loci( { job_id => $job_id, ids => $ids, loci => $loci } ); };
	return if $self->{'exit'};
	local $" = qq(\t);
	open( my $fh, '>:encoding(utf8)', $filename )
	  or $logger->error("Cannot open temp file $filename for writing");
	say $fh qq(#isolate\t@$loci);

	foreach my $isolate_id (@$isolates) {
		my @profile;
		foreach my $locus (@$loci) {
			my @values = split /;/x, $scan_data->{'isolate_data'}->{$isolate_id}->{'designations'}->{$locus};

			#Just pick lowest value
			$values[0] = q(-) if $values[0] eq 'missing';
			$values[0] = q(I) if $values[0] eq 'incomplete';
			push @profile, $values[0] // q(-);
		}
		$profile_hash{ Digest::MD5::md5_hex(qq(@profile)) } = 1;
		$empty_profiles = 1 if all { $_ eq q(-) } @profile;
		unshift @profile, $isolate_id;
		say $fh qq(@profile);
	}
	close $fh;
	if ( keys %profile_hash == 1 ) {
		BIGSdb::Exception::Plugin->throw('All isolates are identical at selected loci. Cannot generate tree.');
	}
	if ( ( keys %profile_hash ) - $empty_profiles <= 1 ) {
		BIGSdb::Exception::Plugin->throw(
			'All isolates are either identical or missing at selected loci. Cannot generate tree.');
	}
	$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => 60 } );
	if ( -e $filename ) {
		$self->{'jobManager'}->update_job_output(
			$job_id,
			{
				filename    => "${job_id}_profiles.txt",
				description => '10_Profiles (TSV format)',
			}
		);
	}
	return;
}

sub _generate_mstree {
	my ( $self, $args ) = @_;
	my ( $job_id, $profiles_file, $tree_file ) = @{$args}{qw(job_id profiles tree)};
	$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Generating minimum spanning tree' } );
	my $python = $self->{'config'}->{'python3_path'};
	my $cmd    = "$python $self->{'config'}->{'grapetree_path'}/grapetree.py --profile $profiles_file > $tree_file";
	eval { system($cmd); };
	if ($?) {
		BIGSdb::Exception::Plugin->throw('Tree generation failed.');
	}
	$self->{'jobManager'}->update_job_output(
		$job_id,
		{
			filename    => "${job_id}_tree.nwk",
			description => '20_MS Tree (Newick format)',
		}
	);
	$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => 80 } );
	return;
}

sub _generate_tsv_file {
	my ( $self, $args ) = @_;
	my ( $job_id, $tsv_file, $params ) = @{$args}{qw(job_id tsv_file params)};
	$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Generating metadata file' } );
	my $isolate_ids = $self->{'jobManager'}->get_job_isolates($job_id);
	my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $isolate_ids );
	my $data =
	  $self->{'datastore'}
	  ->run_query( "SELECT i.* FROM $self->{'system'}->{'view'} i JOIN $temp_table l ON i.id=l.value ORDER BY i.id",
		undef, { fetch => 'all_arrayref', slice => {} } );
	open( my $fh, '>:encoding(utf8)', $tsv_file ) || $logger->error("Cannot open $tsv_file for writing.");
	my @include_fields = split /\|_\|/x, ( $params->{'include_fields'} // q() );
	my %include_fields = map { $_ => 1 } @include_fields;
	$include_fields{'f_id'}                                = 1;
	$include_fields{"f_$self->{'system'}->{'labelfield'}"} = 1;
	my $extended    = $self->get_extended_attributes;
	my $prov_fields = $self->{'xmlHandler'}->get_field_list;
	my $eav_fields  = $self->{'datastore'}->get_eav_fieldnames;
	my @header_fields;

	foreach my $field (@$prov_fields) {
		( my $cleaned_field = $field ) =~ tr/_/ /;
		$cleaned_field = 'ID' if $field eq 'id';
		push @header_fields, $cleaned_field if $include_fields{"f_$field"};
		my $extatt = $extended->{$field};
		if ( ref $extatt eq 'ARRAY' ) {
			foreach my $extended_attribute (@$extatt) {
				if ( $include_fields{"e_$field||$extended_attribute"} ) {
					( my $cleaned_attribute = $extended_attribute ) =~ tr/_/ /;
					push @header_fields, $cleaned_attribute;
				}
			}
		}
	}
	foreach my $field (@$eav_fields) {
		( my $cleaned_field = $field ) =~ tr/_/ /;
		push @header_fields, $cleaned_field if $include_fields{"eav_$field"};
	}
	foreach my $field (@include_fields) {
		if ( $field =~ /^s_(\d+)_(.+)$/x ) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info( $1, { set_id => $params->{'set_id'} } );
			( my $field = "$2 ($scheme_info->{'name'})" ) =~ tr/_/ /;
			push @header_fields, $field;
		}
	}
	local $" = qq(\t);
	say $fh "@header_fields";
	foreach my $record (@$data) {
		my @record_values;
		foreach my $field (@$prov_fields) {
			push @record_values, $self->get_field_value( $record, $field )
			  if $include_fields{"f_$field"};
			my $extatt = $extended->{$field};
			if ( ref $extatt eq 'ARRAY' ) {
				foreach my $extended_attribute (@$extatt) {
					next if !$include_fields{"e_$field||$extended_attribute"};
					my $value = $self->{'datastore'}->run_query(
						'SELECT value FROM isolate_value_extended_attributes WHERE '
						  . '(isolate_field,attribute,field_value)=(?,?,?)',
						[ $field, $extended_attribute, $record->{ lc($field) } ],
						{ cache => 'GrapeTree::extended_attribute_value' }
					);
					push @record_values, $value // q();
				}
			}
		}
		foreach my $field (@$eav_fields) {
			if ( $include_fields{"eav_$field"} ) {
				my $value = $self->{'datastore'}->get_eav_field_value( $record->{'id'}, $field ) // q();
				push @record_values, $value;
			}
		}
		foreach my $field (@include_fields) {
			if ( $field =~ /^s_(\d+)_(.+)$/x ) {
				my ( $scheme_id, $field ) = ( $1, $2 );
				my $field_values =
				  $self->{'datastore'}->get_scheme_field_values_by_isolate_id( $record->{'id'}, $scheme_id );
				my @display_values = sort keys %{ $field_values->{ lc($field) } };
				local $" = q(; );
				push @record_values, qq(@display_values) // q();
			}
		}
		say $fh "@record_values";
	}
	close $fh;
	if ( -e $tsv_file ) {
		$self->{'jobManager'}->update_job_output(
			$job_id,
			{
				filename    => "${job_id}_metadata.txt",
				description => '30_Metadata (TSV format)',
			}
		);
	}
	return;
}
1;
