#Microreact.pm - Phylogenetic tree/data visualization plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2017-2021, University of Oxford
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
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See thef
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <https://www.gnu.org/licenses/>.
#
#NOTE: This plugin requires that the isolate table has a country field with
#a defined list of allowed values, and an integer year field. Values used in
#the country field should match those found at
#https://developers.google.com/public-data/docs/canonical/countries_csv, or be
#mapped with values in the Microreact::_get_mapped_countries() method.
package BIGSdb::Plugins::Microreact;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugins::ITOL);
use BIGSdb::Utils;
use BIGSdb::Constants qw(COUNTRIES);
use LWP::UserAgent;
use Email::Valid;
use JSON;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use utf8;
use constant MAX_RECORDS                 => 2000;
use constant MAX_SEQS                    => 100_000;
use constant MICROREACT_SCHEMA_CONVERTER => 'https://demo.microreact.org/api/schema/convert';
use constant MICROREACT_URL              => 'https://demo.microreact.org/api/projects/create';

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name    => 'Microreact',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@zoo.ox.ac.uk',
			}
		],
		description      => 'Open data visualization and sharing for genomic epidemiology',
		full_description => 'Microreact is a tool for visualising genomic epidemiology and phylogeography '
		  . '(<a href="https://pubmed.ncbi.nlm.nih.gov/28348833/">Argim&oacute;n <i>et al</i> 2016 <i>Microb Genom</i> '
		  . '2:e000093</a>). Individual nodes on a displayed tree are linked to nodes on a geographical map and/or '
		  . 'timeline, making any spatial and temporal relationships between isolates apparent. The Microreact plugin '
		  . 'generates Neighbour-joining trees from concatenated sequences for any selection of loci or schemes '
		  . 'and uploads these, together with country and year field values, to the '
		  . '<a href="https://microreact.org/">Microreact website</a> for display.',
		category   => 'Third party',
		buttontext => 'Microreact',
		menutext   => 'Microreact',
		module     => 'Microreact',
		version    => '1.1.0',
		dbtype     => 'isolates',
		section    => 'third_party,postquery',
		input      => 'query',
		help       => 'tooltips',
		requires   => 'aligner,offline_jobs,js_tree,clustalw,microreact_token',
		order      => 40,
		min        => 2,
		max        => $self->{'system'}->{'microreact_record_limit'} // $self->{'config'}->{'microreact_record_limit'}
		  // MAX_RECORDS,
		url                 => "$self->{'config'}->{'doclink'}/data_analysis/microreact.html",
		system_flag         => 'Microreact',
		always_show_in_menu => 1,
		image               => '/images/plugins/Microreact/screenshot.png'
	);
	return \%att;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	my $ret_val = $self->generate_tree_files( $job_id, $params );
	my ( $message_html, $newick_file, $failed ) = @{$ret_val}{qw(message_html newick_file failed)};
	if ( !$failed ) {
		$self->_microreact_upload( $job_id, $params, $newick_file, \$message_html );
	}
	$self->{'jobManager'}->update_job_status( $job_id, { message_html => $message_html } ) if $message_html;
	return;
}

sub _get_country_field {
	my ($self) = @_;
	my $country_field = $self->{'system'}->{'microreact_country_field'} // 'country';
	return $self->{'xmlHandler'}->is_field($country_field) ? $country_field : undef;
}

sub _get_year_field {
	my ($self) = @_;
	my $year_field = $self->{'system'}->{'microreact_year_field'} // 'year';
	return $self->{'xmlHandler'}->is_field($year_field) ? $year_field : undef;
}

sub _microreact_upload {
	my ( $self, $job_id, $params, $newick_file, $message_html ) = @_;
	my $job = $self->{'jobManager'}->get_job($job_id);
	if ( !$newick_file ) {
		$logger->error('No Newick file.');
		return;
	}
	my $tsv_file = $self->_create_tsv_file( $job_id, $params );
	$self->{'jobManager'}
	  ->update_job_output( $job_id, { filename => "$job_id.tsv", description => '30_Microreact TSV file' } );
	my $uploader    = LWP::UserAgent->new( cookie_jar => {}, agent => 'BIGSdb' );
	my $tsv         = BIGSdb::Utils::slurp($tsv_file);
	my $tree        = BIGSdb::Utils::slurp($newick_file);
	my $upload_data = {
		name => $params->{'title'} || $job_id,
		description => $params->{'description'},
		website     => $params->{'website'},
		data        => $$tsv,
		tree        => $$tree
	};
	my $email = Email::Valid->address( $job->{'email'} );
	$upload_data->{'email'} = $email if $email;
	my $converter_response = $uploader->post(
		MICROREACT_SCHEMA_CONVERTER,
		Content_Type => 'application/json; charset=UTF-8',
		Content      => encode_json($upload_data)
	);

	if ( !$converter_response->is_success ) {
		$logger->error( $converter_response->status_line );
		$$message_html .= q(<p class="statusbad">Microreact scheme conversion failed.</p>);
		return;
	}
	my $microreact_json = $converter_response->decoded_content;
	my $microreact_data = decode_json($microreact_json);
	my $country_field   = $self->_get_country_field;
	if ( defined $country_field ) {
		$country_field =~ s/_/ /gx;
		$microreact_data->{'maps'}->{'map-1'} = {
			dataType     => 'iso-3166-codes',
			iso3166Field => 'iso3166',
			title        => 'Map'
		};
	}
	my $year_field = $self->_get_year_field;
	if ( defined $year_field ) {
		$year_field =~ s/_/ /gx;
		$microreact_data->{'timelines'}->{'timeline-1'} = {
			dataType  => 'year-month-day',
			yearField => $year_field,
			title     => 'Timeline'
		};
	}
	my $upload_response = $uploader->post(
		MICROREACT_URL,
		Content_Type   => 'application/json; charset=UTF-8',
		'Access-Token' => $self->{'config'}->{'microreact_token'},
		Content        => encode_json($microreact_data)
	);
	my $response_json = $upload_response->decoded_content;
	if ($response_json eq 'Unauthorized'){
		$logger->error('Microreact token is not valid.');
		$$message_html .= q(<p class="statusbad">Upload to Microreact failed.</p>);
		return;
	}
	my $ret_val;
	eval {$ret_val       = decode_json($response_json)};
	if ( $ret_val->{'url'} ) {
		$$message_html .= q(<p style="margin-top:2em;margin-bottom:2em">)
		  . qq(<a href="$ret_val->{'url'} " target="_blank" class="launchbutton">Launch Microreact</a></p>);
	} else {
		$logger->error($response_json);
		$$message_html .= q(<p class="statusbad">Microreact did not return a valid project URL.</p>);
	}
	return;
}

sub _create_tsv_file {
	my ( $self, $job_id, $params ) = @_;
	my $isolate_ids = $self->{'jobManager'}->get_job_isolates($job_id);
	my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $isolate_ids );
	my $data =
	  $self->{'datastore'}
	  ->run_query( "SELECT i.* FROM $self->{'system'}->{'view'} i JOIN $temp_table l ON i.id=l.value ORDER BY i.id",
		undef, { fetch => 'all_arrayref', slice => {} } );
	my $tsv_file = "$self->{'config'}->{'tmp_dir'}/$job_id.tsv";
	open( my $fh, '>:encoding(utf8)', $tsv_file ) || $logger->error("Cannot open $tsv_file for writing.");
	my @include_fields = split /\|_\|/x, ( $params->{'include_fields'} // q() );
	my %include_fields = map { $_ => 1 } @include_fields;
	$include_fields{"f_$_"} = 1 foreach qw(id);
	my $country_field = $self->_get_country_field;
	$include_fields{"f_$country_field"} = 1 if defined $country_field;
	my $year_field = $self->_get_year_field;
	$include_fields{"f_$year_field"} = 1 if defined $year_field;
	$include_fields{"f_$self->{'system'}->{'labelfield'}"} = 1;
	my $extended    = $self->get_extended_attributes;
	my $prov_fields = $self->{'xmlHandler'}->get_field_list;
	my @header_fields;

	foreach my $field (@$prov_fields) {
		( my $cleaned_field = $field ) =~ tr/_/ /;
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
	foreach my $field (@include_fields) {
		if ( $field =~ /^s_(\d+)_(.+)$/x ) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info( $1, { set_id => $params->{'set_id'} } );
			( my $field = "$2 ($scheme_info->{'name'})" ) =~ tr/_/ /;
			push @header_fields, $field;
		}
	}
	push @header_fields, 'iso3166' if defined $country_field;
	local $" = qq(\t);
	say $fh "@header_fields";
	my $iso_lookup = COUNTRIES;
	foreach my $record (@$data) {
		$record->{ $self->{'system'}->{'labelfield'} } =~ s/[\(\)]//gx;
		$record->{ $self->{'system'}->{'labelfield'} } =~ tr/[:,. ]/_/;
		$record->{'country'} //= q();
		my $iso2 = 'XX';
		if ( defined $country_field ) {
			my $country = $record->{$country_field};
			$iso2 = $iso_lookup->{$country}->{'iso2'} // 'XX';
		}
		my @record_values;
		foreach my $field (@$prov_fields) {
			my $field_value = $self->get_field_value( $record, $field );
			push @record_values, $field_value if $include_fields{"f_$field"};
			my $extatt = $extended->{$field};
			if ( ref $extatt eq 'ARRAY' ) {
				foreach my $extended_attribute (@$extatt) {
					next if !$include_fields{"e_$field||$extended_attribute"};
					my $value = $self->{'datastore'}->run_query(
						'SELECT value FROM isolate_value_extended_attributes WHERE '
						  . '(isolate_field,attribute,field_value)=(?,?,?)',
						[ $field, $extended_attribute, $field_value ],
						{ cache => 'Microreact::extended_attribute_value' }
					);
					push @record_values, $value // q();
				}
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
		push @record_values, $iso2 if defined $country_field;
		say $fh "@record_values";
	}
	close $fh;
	return $tsv_file;
}

sub print_extra_form_elements {
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	my $email;
	if ( $self->{'username'} ) {
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		$email = $user_info->{'email'};
	}
	my $desc = $self->get_db_description;
	my $q    = $self->{'cgi'};
	say q(<fieldset style="float:left"><legend>Descriptions</legend>);
	say q(<p>Modify the values below - these will be displayed<br />within the created Microreact project.</p>);
	say q(<ul><li><label for="title" class="display">Title:</label>);
	say $q->textfield( -id => 'title', -name => 'title', -maxlength => 50, -style => 'width:15em' );
	say q(</li><li><label for="description" class="display">Description:</label>);
	say $q->textarea( -id => 'description', -name => 'description', -default => $desc, -style => 'width:15em' );
	say q(</li></ul>);
	say q(</fieldset>);
	my $tooltip = $self->get_tooltip( q(Additional fields - These will appear in the Microreact data table. )
		  . qq(Note that $self->{'system'}->{'labelfield'}, country and year are always included.) );
	$self->print_includes_fieldset(
		{
			description         => qq(Select additional fields to include. $tooltip),
			isolate_fields      => 1,
			extended_attributes => 1,
			scheme_fields       => 1,
			hide                => "f_$self->{'system'}->{'labelfield'},f_country,f_year"
		}
	);

	if ( $self->{'config'}->{'domain'} ) {
		my $http = $q->https ? 'https' : 'http';
		say $q->hidden( website => "$http://$self->{'config'}->{'domain'}$self->{'system'}->{'webroot'}" );
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description( { formatted => 1 } );
	return "Microreact - $desc";
}

sub print_info_panel {
	my ($self) = @_;
	my $logo = '/images/plugins/Microreact/logo.png';
	say q(<div class="box" id="resultspanel">);
	say q(<div style="float:left">);
	say qq(<img src="$logo" style="max-width:95%" />);
	say q(</div>);
	say q(<div style="float:left">);
	say q(<p>This plugin uploads data for analysis within the Microreact online service:</p>)
	  . q(<p>Microreact is developed at the <a href="http://www.pathogensurveillance.net/">)
	  . q(The Centre for Genomic Pathogen Surveillance</a> by a team led by David Aanensen.</p>);
	say q(<p>Web site: <a href="https://microreact.org">https://microreact.org</a><br />);
	say q(Publication: Argim&oacute;n <i>at al.</i> (2016) Microreact: visualizing and sharing data for genomic )
	  . q(epidemiology and phylogeography. <a href="https://www.ncbi.nlm.nih.gov/pubmed/28348833">)
	  . q(<i>Microb Genom</i> <b>2:</b>e000093</a>.</p>);
	say q(</div><div style="clear:both"></div></div>);
	return;
}
1;
