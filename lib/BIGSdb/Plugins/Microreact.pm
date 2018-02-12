#Microreact.pm - Phylogenetic tree/data visualization plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2017-2018, University of Oxford
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
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
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
use LWP::UserAgent;
use Email::Valid;
use JSON;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_RECORDS    => 2000;
use constant MAX_SEQS       => 100_000;
use constant MICROREACT_URL => 'https://microreact.org/api/1.0/project/';

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name                => 'Microreact',
		author              => 'Keith Jolley',
		affiliation         => 'University of Oxford, UK',
		email               => 'keith.jolley@zoo.ox.ac.uk',
		description         => 'Open data visualization and sharing for genomic epidemiology',
		menu_description    => 'Open data visualization and sharing for genomic epidemiology',
		category            => 'Third party',
		buttontext          => 'Microreact',
		menutext            => 'Microreact',
		module              => 'Microreact',
		version             => '1.0.3',
		dbtype              => 'isolates',
		section             => 'third_party,postquery',
		input               => 'query',
		help                => 'tooltips',
		requires            => 'aligner,offline_jobs,js_tree,clustalw,field_country_optlist,field_year_int',
		order               => 40,
		min                 => 2,
		max                 => MAX_RECORDS,
		system_flag         => 'Microreact',
		always_show_in_menu => 1
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
		description      => $params->{'description'},
		website          => $params->{'website'},
		map_countryField => 'country',
		data             => $$tsv,
		tree             => $$tree
	};
	my $email = Email::Valid->address( $job->{'email'} );
	$upload_data->{'email'} = $email if $email;
	my $upload_response = $uploader->post(
		MICROREACT_URL,
		Content_Type => 'application/json; charset=UTF-8',
		Content      => encode_json($upload_data)
	);

	if ( !$upload_response->is_success ) {
		$logger->error( $upload_response->status_line );
		$$message_html .= q(<p class="statusbad">Microreact upload failed.</p>);
		return;
	}
	my $json    = $upload_response->decoded_content;
	my $ret_val = decode_json($json);
	if ( $ret_val->{'url'} ) {
		$$message_html .= q(<p style="margin-top:2em;margin-bottom:2em">)
		  . qq(<a href="$ret_val->{'url'} " target="_blank" class="launchbutton">Launch Microreact</a></p>);
	} else {
		$logger->error($json);
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
	my @include_fields = split /\|_\|/x, ($params->{'include_fields'} // q());
	my %include_fields = map { $_ => 1 } @include_fields;
	$include_fields{"f_$_"} = 1 foreach qw(id country year);
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
	local $" = qq(\t);
	say $fh "@header_fields";
	my $allowed = $self->_get_allowed_countries;
	my $mapped  = $self->_get_mapped_countries;
	foreach my $record (@$data) {
		$record->{ $self->{'system'}->{'labelfield'} } =~ s/[\(\)]//gx;
		$record->{ $self->{'system'}->{'labelfield'} } =~ tr/[:,. ]/_/;
		my $country = $record->{'country'};
		if ( !$allowed->{ $record->{'country'} } ) {
			if ( defined $mapped->{ $record->{'country'} } ) {
				$record->{'country'} = $mapped->{ $record->{'country'} };
			} else {
				$logger->error("$record->{'country'} is not an allowed country")
				  if $record->{'country'} ne q();
			}
		}
		my @record_values;
		foreach my $field (@$prov_fields) {
			push @record_values, $record->{$field} // q() if $include_fields{"f_$field"};
			my $extatt = $extended->{$field};
			if ( ref $extatt eq 'ARRAY' ) {
				foreach my $extended_attribute (@$extatt) {
					next if !$include_fields{"e_$field||$extended_attribute"};
					my $field_value = $field eq 'country' ? $country : $record->{$field};    #use unmapped country value
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
	say q(<p>Modify the values below - these will be displayed within the created Microreact project.</p>);
	say q(<ul><li><label for="title" class="form">Title:</label>);
	say $q->textfield( -id => 'title', -name => 'title', -size => 30 );
	say q(</li><li><label for="description" class="form">Description:</label>);
	say $q->textarea( -id => 'description', -name => 'description', -default => $desc );
	say q(</li></ul>);
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Include fields</legend>);
	say q(<p>Select additional fields to include in Microreact data table.-<br />)
	  . qq(($self->{'system'}->{'labelfield'}, country and year are always included).</p>);
	my ( $headings, $labels ) = $self->get_field_selection_list(
		{
			isolate_fields      => 1,
			extended_attributes => 1,
			loci                => 0,
			query_pref          => 0,
			analysis_pref       => 1,
			scheme_fields       => 1,
			set_id              => $set_id
		}
	);
	my $fields = [];
	my %invalid = map { $_ => 1 } qw(f_id f_country f_year);

	foreach my $field (@$headings) {
		next if $invalid{$field};
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
	if ( $self->{'config'}->{'domain'} ) {
		my $http = $q->https ? 'https' : 'http';
		say $q->hidden( website => "$http://$self->{'config'}->{'domain'}$self->{'system'}->{'webroot'}" );
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description;
	return "Microreact - $desc";
}

sub print_info_panel {
	my ($self) = @_;
	my $logo = '/images/plugins/Microreact/logo.png';
	say q(<div class="box" id="resultspanel">);
	if ( -e "$ENV{'DOCUMENT_ROOT'}$logo" ) {
		say q(<div style="float:left">);
		say qq(<img src="$logo" style="max-width:95%" />);
		say q(</div>);
	}
	say q(<div style="float:left">);
	say q(<p>This plugin uploads data for analysis within the Microreact online service:</p>);
	say q(<h2>Microreact: visualizing and sharing data for genomic epidemiology and phylogeography</h2>);
	say q(<p>Microreact is developed by:</p>);
	say q(<ul>);
	say q(<li>Khalil Abudahab</li>);
	say q(<li>Richard Goater</li>);
	say q(<li>Artemij Fedosejev</li>);
	say q(<li>Jyothish NT</li>);
	say q(<li>Stephano</li>);
	say q(</ul>);
	say q(<p>in the <a href="http://www.imperial.ac.uk/people/d.aanensen">Aanensen Research Group</a> )
	  . q(at Imperial College London and <a href="http://www.pathogensurveillance.net/">)
	  . q(The Centre for Genomic Pathogen Surveillance</a>.</p>);
	say q(<p>Web site: <a href="https://microreact.org">https://microreact.org</a><br />);
	say q(Publication: Argim&oacute;n <i>at al.</i> (2016) Microreact: visualizing and sharing data for genomic )
	  . q(epidemiology and phylogeography. <a href="https://www.ncbi.nlm.nih.gov/pubmed/28348833">)
	  . q(<i>Microb Genom</i> <b>2:</b>e000093</a>.</p>);
	say q(</div><div style="clear:both"></div></div>);
	return;
}

#list from https://developers.google.com/public-data/docs/canonical/countries_csv
sub _get_allowed_countries {
	my ($self) = @_;
	my $list = [
		q(Afghanistan),                                  q(Albania),
		q(Andorra),                                      q(Anguilla),
		q(Antigua and Barbuda),                          q(Armenia),
		q(Netherlands Antilles),                         q(Algeria),
		q(American Samoa),                               q(Angola),
		q(Antarctica),                                   q(Argentina),
		q(Aruba),                                        q(Australia),
		q(Austria),                                      q(Azerbaijan),
		q(Bahamas),                                      q(Bahrain),
		q(Bangladesh),                                   q(Barbados),
		q(Belarus),                                      q(Belgium),
		q(Belize),                                       q(Benin),
		q(Bermuda),                                      q(Bhutan),
		q(Bolivia),                                      q(Bosnia and Herzegovina),
		q(Botswana),                                     q(Bouvet Island),
		q(Brazil),                                       q(British Indian Ocean Territory),
		q(British Virgin Islands),                       q(Brunei),
		q(Bulgaria),                                     q(Burkina Faso),
		q(Burundi),                                      q(Cambodia),
		q(Cameroon),                                     q(Canada),
		q(Cape Verde),                                   q(Cayman Islands),
		q(Central African Republic),                     q(Chad),
		q(Chile),                                        q(China),
		q(Christmas Island),                             q(Cocos [Keeling] Islands),
		q(Colombia),                                     q(Comoros),
		q(Congo [DRC]),                                  q(Congo [Republic]),
		q(Cook Islands),                                 q(Costa Rica),
		q(Côte d'Ivoire),                               q(Croatia),
		q(Cuba),                                         q(Cyprus),
		q(Czech Republic),                               q(Denmark),
		q(Djibouti),                                     q(Dominica),
		q(Dominican Republic),                           q(Ecuador),
		q(Egypt),                                        q(El Salvador),
		q(Equatorial Guinea),                            q(Eritrea),
		q(Estonia),                                      q(Ethiopia),
		q(Falkland Islands [Islas Malvinas]),            q(Faroe Islands),
		q(Fiji),                                         q(Finland),
		q(France),                                       q(French Guiana),
		q(French Polynesia),                             q(French Southern Territories),
		q(Gabon),                                        q(Gambia),
		q(Gaza Strip),                                   q(Georgia),
		q(Germany),                                      q(Ghana),
		q(Gibraltar),                                    q(Greece),
		q(Greenland),                                    q(Grenada),
		q(Guadeloupe),                                   q(Guam),
		q(Guatemala),                                    q(Guernsey),
		q(Guinea),                                       q(Guinea-Bissau),
		q(Guyana),                                       q(Haiti),
		q(Heard Island and McDonald Islands),            q(Honduras),
		q(Hong Kong),                                    q(Hungary),
		q(Iceland),                                      q(India),
		q(Indonesia),                                    q(Iran),
		q(Iraq),                                         q(Ireland),
		q(Isle of Man),                                  q(Israel),
		q(Italy),                                        q(Jamaica),
		q(Japan),                                        q(Jersey),
		q(Jordan),                                       q(Kazakhstan),
		q(Kenya),                                        q(Kiribati),
		q(Kosovo),                                       q(Kuwait),
		q(Kyrgyzstan),                                   q(Laos),
		q(Latvia),                                       q(Lebanon),
		q(Lesotho),                                      q(Liberia),
		q(Libya),                                        q(Liechtenstein),
		q(Lithuania),                                    q(Luxembourg),
		q(Macau),                                        q(Macedonia [FYROM]),
		q(Madagascar),                                   q(Malawi),
		q(Malaysia),                                     q(Maldives),
		q(Mali),                                         q(Malta),
		q(Marshall Islands),                             q(Martinique),
		q(Mauritania),                                   q(Mauritius),
		q(Mayotte),                                      q(Mexico),
		q(Micronesia),                                   q(Moldova),
		q(Monaco),                                       q(Mongolia),
		q(Montenegro),                                   q(Montserrat),
		q(Morocco),                                      q(Mozambique),
		q(Myanmar [Burma]),                              q(Namibia),
		q(Nauru),                                        q(Nepal),
		q(Netherlands),                                  q(New Caledonia),
		q(New Zealand),                                  q(Nicaragua),
		q(Niger),                                        q(Nigeria),
		q(Niue),                                         q(Norfolk Island),
		q(North Korea),                                  q(Northern Mariana Islands),
		q(Norway),                                       q(Oman),
		q(Pakistan),                                     q(Palau),
		q(Palestinian Territories),                      q(Panama),
		q(Papua New Guinea),                             q(Paraguay),
		q(Peru),                                         q(Philippines),
		q(Pitcairn Islands),                             q(Poland),
		q(Portugal),                                     q(Puerto Rico),
		q(Qatar),                                        q(Réunion),
		q(Romania),                                      q(Russia),
		q(Rwanda),                                       q(Saint Helena),
		q(Saint Kitts and Nevis),                        q(Saint Lucia),
		q(Saint Pierre and Miquelon),                    q(Saint Vincent and the Grenadines),
		q(Samoa),                                        q(San Marino),
		q(São Tomé and Príncipe),                     q(Saudi Arabia),
		q(Senegal),                                      q(Serbia),
		q(Seychelles),                                   q(Sierra Leone),
		q(Singapore),                                    q(Slovakia),
		q(Slovenia),                                     q(Solomon Islands),
		q(Somalia),                                      q(South Africa),
		q(South Georgia and the South Sandwich Islands), q(South Korea),
		q(Spain),                                        q(Sri Lanka),
		q(Sudan),                                        q(Suriname),
		q(Svalbard and Jan Mayen),                       q(Swaziland),
		q(Sweden),                                       q(Switzerland),
		q(Syria),                                        q(Taiwan),
		q(Tajikistan),                                   q(Tanzania),
		q(Thailand),                                     q(Timor-Leste),
		q(Togo),                                         q(Tokelau),
		q(Tonga),                                        q(Trinidad and Tobago),
		q(Tunisia),                                      q(Turkey),
		q(Turkmenistan),                                 q(Turks and Caicos Islands),
		q(Tuvalu),                                       q(U.S. Minor Outlying Islands),
		q(U.S. Virgin Islands),                          q(Uganda),
		q(Ukraine),                                      q(United Kingdom),
		q(United States),                                q(Uruguay),
		q(Uzbekistan),                                   q(Vanuatu),
		q(Vatican City),                                 q(Venezuela),
		q(Vietnam),                                      q(Wallis and Futuna),
		q(Western Sahara),                               q(Yemen),
		q(Zambia),                                       q(Zimbabwe),
		q(United Arab Emirates),
	];
	my %allowed = map { $_ => 1 } @$list;
	return \%allowed;
}

sub _get_mapped_countries {
	my ($self) = @_;
	my $mapped = {
		'The Gambia'      => 'Gambia',
		'The Netherlands' => 'Netherlands',
		'UK'              => 'United Kingdom',
		'USA'             => 'United States',
		'Unknown'         => ''
	};
	return $mapped;
}
1;
