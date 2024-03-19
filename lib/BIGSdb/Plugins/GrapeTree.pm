#GrapeTree.pm - MST visualization plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2017-2023, University of Oxford
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
		name    => 'GrapeTree',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			}
		],
		description      => 'Visualization of genomic relationships',
		full_description => 'GrapeTree is a tool for generating and visualising minimum spanning trees '
		  . '(<a href="https://www.ncbi.nlm.nih.gov/pubmed/30049790">Zhou <i>at al.</i> 2018 <i>Genome Res</i> '
		  . '28:1395-1404</a>). It has been developed to handle large datasets (in the region of 1000s of '
		  . 'genomes) and works with 1000s of loci as used in cgMLST. It uses an improved minimum spanning algorithm '
		  . 'that is better able to handle missing data than alternative algorithms and is able to produce publication '
		  . 'quality outputs. Datasets can include metadata which allows nodes in the resultant tree to be coloured '
		  . 'interactively.',
		category            => 'Third party',
		buttontext          => 'GrapeTree',
		menutext            => 'GrapeTree',
		module              => 'GrapeTree',
		version             => '1.5.5',
		dbtype              => 'isolates',
		section             => 'third_party,postquery',
		input               => 'query',
		help                => 'tooltips',
		requires            => 'offline_jobs,js_tree,GrapeTree',
		url                 => "$self->{'config'}->{'doclink'}/data_analysis/grapetree.html",
		order               => 20,
		min                 => 2,
		max                 => $self->_get_limit,
		always_show_in_menu => 1,
		image               => '/images/plugins/GrapeTree/screenshot.png'
	);
	return \%att;
}

sub _get_limit {
	my ($self) = @_;
	my $limit = $self->{'system'}->{'grapetree_limit'} // $self->{'config'}->{'grapetree_limit'} // MAX_RECORDS;
	return $limit;
}

sub _get_classification_schemes {
	my ($self) = @_;
	return $self->{'datastore'}->run_query( 'SELECT id,name FROM classification_schemes ORDER BY display_order,id',
		undef, { fetch => 'all_arrayref', slice => {} } );
}

sub print_info_panel {
	my ($self) = @_;
	my $logo = '/images/plugins/GrapeTree/logo.png';
	say q(<div class="box" id="resultspanel">);
	say q(<div style="float:left">);
	say qq(<img src="$logo" style="width:100px" />);
	say q(</div>);
	say q(<p>This plugin generates a minimum-spanning tree and visualizes within GrapeTree:</p>);
	say q(<p>GrapeTree is developed by: Zhemin Zhou (1), Nabil-Fareed Alikhan (1), Martin J. Sergeant (1), )
	  . q(Nina Luhmann (1), C&aacute;tia Vaz (2,5), Alexandre P. Francisco (2,4), )
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
	my $list       = $self->get_id_list( 'id', $query_file );
	say q(<div class="flex_container" style="justify-content:left">);
	$self->print_seqbin_isolate_fieldset( { use_all          => 1, selected_ids => $list, isolate_paste_list => 1 } );
	$self->print_isolates_locus_fieldset( { locus_paste_list => 1 } );
	$self->print_recommended_scheme_fieldset( { no_clear => 1 } );
	$self->print_scheme_fieldset( { fields_or_loci => 0 } );
	$self->print_includes_fieldset(
		{
			description              => 'Select additional fields to include in GrapeTree metadata.',
			isolate_fields           => 1,
			nosplit_geography_points => 1,
			hide                     => "f_$self->{'system'}->{'labelfield'}",
			extended_attributes      => 1,
			scheme_fields            => 1,
			eav_fields               => 1,
			classification_groups    => 1,
			lincodes                 => 1,
			lincode_fields           => 1,
			size                     => 8
		}
	);
	$self->_print_parameters_fieldset;
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach qw (db page name);
	say q(</div>);
	say $q->end_form;
	say q(</div>);
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
	my $q = $self->{'cgi'};
	say q(<h1>GrapeTree: Visualization of genomic relationships</h1>);
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
		$params->{'curate'} = 1 if $self->{'curate'};
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
	$self->generate_profile_file(
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
	$self->generate_metadata_file(
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

sub generate_profile_file {
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
	my $python     = $self->{'config'}->{'python3_path'};
	my $prefix     = BIGSdb::Utils::get_random();
	my $error_file = "$self->{'config'}->{'secure_tmp_dir'}/${prefix}_grapetree";
	my $cmd =
	  "$python $self->{'config'}->{'grapetree_path'}/grapetree.py --profile $profiles_file 2>$error_file > $tree_file ";
	eval { system($cmd); };

	if ($?) {
		BIGSdb::Exception::Plugin->throw('Tree generation failed.');
	}
	if ( -e $error_file ) {
		my $error = BIGSdb::Utils::slurp($error_file);
		if ($$error) {
			$logger->error($$error);
		}
		unlink $error_file;
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

sub generate_metadata_file {
	my ( $self, $args ) = @_;
	my ( $job_id, $tsv_file, $params, $options ) = @{$args}{qw(job_id tsv_file params options)};
	$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Generating metadata file' } );
	my $isolate_ids = $self->{'jobManager'}->get_job_isolates($job_id);
	my $temp_table  = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $isolate_ids );
	my $data =
	  $self->{'datastore'}
	  ->run_query( "SELECT i.* FROM $self->{'system'}->{'view'} i JOIN $temp_table l ON i.id=l.value ORDER BY i.id",
		undef, { fetch => 'all_arrayref', slice => {} } );
	open( my $fh, '>:encoding(utf8)', $tsv_file ) || $logger->error("Cannot open $tsv_file for writing.");
	my @include_fields = split /\|_\|/x, ( $params->{'include_fields'} // q() );
	my %include_fields = map { $_ => 1 } @include_fields;
	$include_fields{'f_id'}                                = 1;
	$include_fields{"f_$self->{'system'}->{'labelfield'}"} = 1;
	my $extended               = $self->get_extended_attributes;
	my $prov_fields            = $self->{'xmlHandler'}->get_field_list;
	my $eav_fields             = $self->{'datastore'}->get_eav_fieldnames;
	my $classification_schemes = $self->_get_classification_schemes;
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
	my ( $scheme_fields, $lincode_threshold_counts ) = $self->_get_scheme_fields_for_header($params);
	push @header_fields, @$scheme_fields;
	foreach my $cs (@$classification_schemes) {
		if ( $include_fields{"cg_$cs->{'id'}_group"} ) {
			push @header_fields, $cs->{'name'};
		}
	}
	if ( $options->{'remove_non_alphanumerics'} ) {
		s/[^a-zA-Z0-9]/_/gx && s/__/_/gx && s/_$//x foreach @header_fields;
	}
	local $" = qq(\t);
	my %headers = map { $_ => 1 } @header_fields;
	if ( $options->{'add_date_field'} ) {
		push @header_fields, 'date' if !$headers{'date'};
	}
	say $fh "@header_fields";
	foreach my $record (@$data) {
		my @record_values;
		foreach my $field (@$prov_fields) {
			if ( $include_fields{"f_$field"} ) {
				my $value = $self->get_field_value( $record, $field );
				if ( $self->{'datastore'}->field_needs_conversion($field) ) {
					$value = $self->{'datastore'}->convert_field_value( $field, $value );
				}
				push @record_values, $value;
			}
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
				my $field_values = $self->get_scheme_field_values(
					{
						isolate_id => $record->{'id'},
						scheme_id  => $scheme_id,
						field      => $field
					}
				);
				local $" = q(; );
				@$field_values = grep { defined $_ } @$field_values;
				push @record_values, @$field_values ? qq(@$field_values) : q();
			}
			if ( $field =~ /^lin_(\d+)$/x ) {
				my $lincodes = $self->_get_lincode_values( $record->{'id'}, $1, $lincode_threshold_counts );
				push @record_values, @$lincodes;
			}
			if ( $field =~ /^lin_(\d+)_(.+)$/x ) {
				my $lincode_field_values = $self->_get_lincode_field_values( $record->{'id'}, $1, $2 );
				push @record_values, @$lincode_field_values;
			}
		}
		foreach my $cs (@$classification_schemes) {
			if ( $include_fields{"cg_$cs->{'id'}_group"} ) {
				my $value = $self->get_cscheme_value( $record->{'id'}, $cs->{'id'} );
				push @record_values, $value;
			}
		}
		if ( $options->{'add_date_field'} ) {
			push @record_values, $self->get_field_value( $record, $options->{'add_date_field'} );
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

sub _get_lincode_values {
	my ( $self, $isolate_id, $scheme_id, $lincode_threshold_counts ) = @_;
	my $lincodes = $self->get_lincode( $isolate_id, $scheme_id );
	$self->{'cache'}->{'current_lincode'} = $lincodes;
	my @display_values;
	my $record_values = [];
	foreach my $lincode (@$lincodes) {
		local $" = q(_);
		push @display_values, qq(@$lincode);
	}
	local $" = q(; );
	push @$record_values, qq(@display_values) // q();
	if ( $lincode_threshold_counts->{$scheme_id} > 1 ) {
		for my $i ( 0 .. $lincode_threshold_counts->{$scheme_id} - 2 ) {
			@display_values = ();
			my %used;
			foreach my $lincode (@$lincodes) {
				my @lincode_prefix = @$lincode[ 0 .. $i ];
				local $" = q(_);
				push @display_values, qq(@lincode_prefix) if !$used{qq(@lincode_prefix)};
				$used{qq(@lincode_prefix)} = 1;
			}
			local $" = q(; );
			push @$record_values, qq(@display_values) // q();
		}
	}
	return $record_values;
}

sub _get_lincode_field_values {
	my ( $self, $isolate_id, $scheme_id, $field ) = @_;
	my $lincodes = $self->{'cache'}->{'current_lincode'} // $self->get_lincode( $isolate_id, $scheme_id );
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
	my $values   = [];
	foreach my $prefix (@prefixes) {
		foreach my $lincode (@$lincodes) {
			local $" = q(_);
			if (   "@$lincode" eq $prefix
				|| "@$lincode" =~ /^${prefix}_/x && !$used{ $prefix_values->{$field}->{$prefix} } )
			{
				push @$values, $prefix_values->{$field}->{$prefix};
				$used{ $prefix_values->{$field}->{$prefix} } = 1;
			}
		}
	}
	@$values = sort @$values;
	return $values;
}

sub _get_scheme_fields_for_header {
	my ( $self, $params ) = @_;
	my @include_fields           = split /\|_\|/x, ( $params->{'include_fields'} // q() );
	my $header_fields            = [];
	my $lincode_threshold_counts = {};
	foreach my $field (@include_fields) {
		if ( $field =~ /^s_(\d+)_(.+)$/x ) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info( $1, { set_id => $params->{'set_id'} } );
			( my $field = "$2 ($scheme_info->{'name'})" ) =~ tr/_/ /;
			push @$header_fields, $field;
		}
		if ( $field =~ /^lin_(\d+)$/x ) {
			my $scheme_id   = $1;
			my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $params->{'set_id'} } );
			( my $field = "LINcode ($scheme_info->{'name'})" ) =~ tr/_/ /;
			push @$header_fields, $field;
			my $thresholds =
			  $self->{'datastore'}->run_query( 'SELECT thresholds FROM lincode_schemes WHERE scheme_id=?', $scheme_id );
			my @threshold_values = split /\s*;\s*/x, $thresholds;
			$lincode_threshold_counts->{$scheme_id} = scalar @threshold_values;
			if ( $lincode_threshold_counts->{$scheme_id} > 1 ) {
				for my $i ( 1 .. @threshold_values - 1 ) {
					( my $field = "LINcode ($scheme_info->{'name'})[$i]" ) =~ tr/_/ /;
					push @$header_fields, $field;
				}
			}
		}
		if ( $field =~ /^lin_(\d+)_(.+)$/x ) {
			my ( $scheme_id, $field ) = ( $1, $2 );
			my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $params->{'set_id'} } );
			( my $display_field = "$field ($scheme_info->{'name'})" ) =~ tr/_/ /;
			push @$header_fields, ($display_field);
		}
	}
	return ( $header_fields, $lincode_threshold_counts );
}
1;
