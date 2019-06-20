#Export.pm - Export plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2019, University of Oxford
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
use Bio::Tools::SeqStats;
use constant MAX_INSTANT_RUN         => 2000;
use constant MAX_DEFAULT_DATA_POINTS => 25_000_000;

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name        => 'Export',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Export dataset generated from query results',
		category    => 'Export',
		buttontext  => 'Dataset',
		menutext    => 'Export dataset',
		module      => 'Export',
		version     => '1.7.3',
		dbtype      => 'isolates',
		section     => 'export,postquery',
		url         => "$self->{'config'}->{'doclink'}/data_export.html#isolate-record-export",
		input       => 'query',
		requires    => 'ref_db,js_tree',
		help        => 'tooltips',
		order       => 15
	);
	return \%att;
}

sub get_initiation_values {
	return { 'jQuery.jstree' => 1 };
}

sub get_plugin_javascript {
	my $js = << "END";
function enable_controls(){
	if (\$("#m_references").prop("checked")){
		\$("input:radio[name='ref_type']").prop("disabled", false);
	} else {
		\$("input:radio[name='ref_type']").prop("disabled", true);
	}
}

\$(document).ready(function(){ 
	enable_controls();
}); 
END
	return $js;
}

sub _print_ref_fields {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left"><legend>References</legend><ul><li>);
	say $q->checkbox(
		-name     => 'm_references',
		-id       => 'm_references',
		-value    => 'checked',
		-label    => 'references',
		-onChange => 'enable_controls()'
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

sub _print_options {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left"><legend>Options</legend><ul></li>);
	say $q->checkbox(
		-name  => 'indicate_tags',
		-id    => 'indicate_tags',
		-label => 'Indicate sequence status if no allele defined'
	);
	say $self->get_tooltip( q(Indicate sequence status - Where alleles have not been designated but the )
		  . q(sequence has been tagged in the sequence bin, [S] will be shown. If the tagged sequence is incomplete )
		  . q(then [I] will also be shown.) );
	say q(</li><li>);
	say $q->checkbox( -name => 'common_names', -id => 'common_names', -label => 'Include locus common names' );
	say q(</li><li>);
	say $q->checkbox( -name => 'alleles', -id => 'alleles', -label => 'Export allele numbers', -checked => 'checked' );
	say q(</li><li>);
	say $q->checkbox( -name => 'oneline', -id => 'oneline', -label => 'Use one row per field' );
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
	my $ids    = [];
	my $labels = {};
	foreach my $cf (@$classification_schemes) {
		push @$ids, $cf->{'id'};
		$labels->{ $cf->{'id'} } = $cf->{'name'};
	}
	say q(<fieldset style="float:left"><legend>Classification schemes</legend>);
	say $self->popup_menu(
		-name     => 'classification_schemes',
		-id       => 'classification_schemes',
		-values   => $ids,
		-labels   => $labels,
		-size     => 8,
		-multiple => 'true',
		-style    => 'width:100%'
	);
	say
	  q(<div style="text-align:center"><input type="button" onclick='listbox_selectall("classification_schemes",true)' )
	  . q(value="All" style="margin-top:1em" class="smallbutton" /><input type="button" )
	  . q(onclick='listbox_selectall("classification_schemes",false)' value="None" style="margin-top:1em" )
	  . q(class="smallbutton" /></div>);
	say q(</fieldset>);
return;
}

sub _print_molwt_options {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left"><legend>Molecular weights</legend><ul></li>);
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

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Export dataset</h1>);
	return if $self->has_set_changed;
	if ( $q->param('submit') ) {
		my $selected_fields = $self->get_selected_fields2;
		$q->delete('classification_schemes');
		push @$selected_fields, 'm_references' if $q->param('m_references');
		if ( !@$selected_fields ) {
			$self->print_bad_status( { message => q(No fields have been selected!) } );
			$self->_print_interface;
			return;
		}
		my $prefix   = BIGSdb::Utils::get_random();
		my $filename = "$prefix.txt";
		my $ids      = $self->filter_list_to_ids( [ $q->param('isolate_id') ] );
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
		my $set_id = $self->get_set_id;
		my $params = $q->Vars;
		$params->{'set_id'} = $set_id if $set_id;
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
		my $excel = BIGSdb::Utils::text2excel(
			$full_path,
			{
				worksheet   => 'Export',
				tmp_dir     => $self->{'config'}->{'secure_tmp_dir'},
				text_fields => $self->{'system'}->{'labelfield'}
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

sub _print_interface {
	my ( $self, $default_select ) = @_;
	my $q          = $self->{'cgi'};
	my $set_id     = $self->get_set_id;
	my $query_file = $q->param('query_file');
	my $selected_ids;
	if ( $q->param('isolate_id') ) {
		my @ids = $q->param('isolate_id');
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
	say $q->start_form;
	$self->print_seqbin_isolate_fieldset( { use_all => 1, selected_ids => $selected_ids, isolate_paste_list => 1 } );
	$self->print_isolate_fields_fieldset( { extended_attributes => 1, default => ['id'] } );
	$self->print_eav_fields_fieldset;
	$self->print_composite_fields_fieldset;
	$self->_print_ref_fields;
	$self->print_isolates_locus_fieldset;
	$self->print_scheme_fieldset( { fields_or_loci => 1 } );
	
	$self->_print_classification_scheme_fields;
	$self->_print_options;
	$self->_print_molwt_options;
	$self->print_action_fieldset( { no_reset => 1 } );
	say q(<div style="clear:both"></div>);
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
	my @fields = split /\|\|/x, $params->{'selected_fields'};
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
		my $excel_file = BIGSdb::Utils::text2excel(
			$filename,
			{
				worksheet   => 'Export',
				tmp_dir     => $self->{'config'}->{'secure_tmp_dir'},
				text_fields => $self->{'system'}->{'labelfield'}
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
	$sql->bind_columns( map { \$data{$_} } @$fields_to_bind );    #quicker binding hash to arrayref than to use hashref
	my $i = 0;
	my $j = 0;
	local $| = 1;
	my %id_used;
	my $total    = 0;
	my $progress = 0;

	while ( $sql->fetchrow_arrayref ) {
		next
		  if $id_used{ $data{'id'} }
		  ;    #Ordering by scheme field/locus can result in multiple rows per isolate if multiple values defined.
		$id_used{ $data{'id'} } = 1;
		if ( !$offline ) {
			print q(.) if !$i;
			print q( ) if !$j;
		}
		if ( !$i && $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
		my $first          = 1;
		my $all_allele_ids = $self->{'datastore'}->get_all_allele_ids( $data{'id'} );
		foreach my $field (@$fields) {
			my $regex = {
				field                 => qr/^f_(.*)/x,
				eav_field             => qr/^eav_(.*)/x,
				locus                 => qr/^(s_\d+_l_|l_)(.*)/x,
				scheme_field          => qr/^s_(\d+)_f_(.*)/x,
				composite_field       => qr/^c_(.*)/x,
				classification_scheme => qr/^cs_(.*)/x,
				reference             => qr/^m_references/x
			};
			my $methods = {
				field     => sub { $self->_write_field( $fh,     $1, \%data, $first, $params ) },
				eav_field => sub { $self->_write_eav_field( $fh, $1, \%data, $first, $params ) },
				locus     => sub {
					$self->_write_allele(
						{
							fh             => $fh,
							locus          => $2,
							data           => \%data,
							all_allele_ids => $all_allele_ids,
							first          => $first,
							params         => $params
						}
					);
				},
				scheme_field => sub {
					$self->_write_scheme_field(
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
				}
			};
			foreach
			  my $field_type (qw(field eav_field locus scheme_field composite_field classification_scheme reference))
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
		foreach (@$fields) {
			my $field = $_;    #don't modify @$fields
			if ( $field =~ /^s_(\d+)_f/x ) {
				my $scheme_info = $self->{'datastore'}->get_scheme_info( $1, { set_id => $set_id } );
				$field .= " ($scheme_info->{'name'})"
				  if $scheme_info->{'name'};
				$schemes{$1} = 1;
			}
			my $is_locus = $field =~ /^(s_\d+_l_|l_)/x ? 1 : 0;
			my ( $cscheme, $is_cscheme );
			if ( $field =~ /^cs_(\d+)/x ) {
				$is_cscheme = 1;
				$cscheme    = $1;
			}
			$field =~ s/^(?:s_\d+_l|s_\d+_f|f|l|c|m|cs|eav)_//x;    #strip off prefix for header row
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			$field =~ s/^.*___//x;
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
			} else {
				$buffer .= "\t" if !$first;
				$buffer .= $metafield // $field;
			}
			$first = 0;
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
	$buffer .= "$data->{$self->{'system'}->{'labelfield'}}\t" if $params->{'labelfield'};
	return $buffer;
}

sub _write_field {
	my ( $self, $fh, $field, $data, $first, $params ) = @_;
	my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
	if ( defined $metaset ) {
		my $value = $self->{'datastore'}->get_metadata_value( $data->{'id'}, $metaset, $metafield );
		if ( $params->{'oneline'} ) {
			print $fh $self->_get_id_one_line( $data, $params );
			print $fh "$metafield\t";
			print $fh $value;
			print $fh "\n";
		} else {
			print $fh "\t" if !$first;
			print $fh $value;
		}
	} elsif ( $field eq 'aliases' ) {
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
		if ( $params->{'oneline'} ) {
			print $fh $self->_get_id_one_line( $data, $params );
			print $fh "$field\t";
			print $fh "$data->{$field}" if defined $data->{$field};
			print $fh "\n";
		} else {
			print $fh "\t" if !$first;
			print $fh $data->{$field} if defined $data->{$field};
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
	my ( $fh, $locus, $data, $all_allele_ids, $first_col, $params ) =
	  @{$args}{qw(fh locus data all_allele_ids first params)};
	my @unsorted_allele_ids = defined $all_allele_ids->{$locus} ? @{ $all_allele_ids->{$locus} } : (q());
	my $allele_ids = $self->_sort_alleles( $locus, \@unsorted_allele_ids );
	if ( $params->{'alleles'} ) {
		my $first_allele = 1;
		foreach my $allele_id (@$allele_ids) {
			if ( $allele_id eq q() ) {
				if ( $params->{'indicate_tags'} ) {
					my $tag = $self->{'datastore'}->run_query(
						'SELECT id,complete FROM allele_sequences WHERE (isolate_id,locus)=(?,?) '
						  . 'ORDER BY complete desc LIMIT 1',
						[ $data->{'id'}, $locus ],
						{ fetch => 'row_hashref', cache => 'Export::write_allele::tag' }
					);
					if ($tag) {
						$allele_id .= '[S]';
						$allele_id .= '[I]' if !$tag->{'complete'};
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

sub _write_scheme_field {
	my ( $self, $args ) = @_;
	my ( $fh, $scheme_id, $field, $data, $first_col, $params ) = @{$args}{qw(fh scheme_id field data first params )};
	my $scheme_info  = $self->{'datastore'}->get_scheme_info($scheme_id);
	my $scheme_field = lc($field);
	my $values =
	  $self->get_scheme_field_values( { isolate_id => $data->{'id'}, scheme_id => $scheme_id, field => $field } );
	@$values = ('') if !@$values;
	my $first_allele = 1;
	foreach my $value (@$values) {

		if ( $params->{'oneline'} ) {
			print $fh $self->_get_id_one_line( $data, $params );
			print $fh "$field ($scheme_info->{'name'})\t";
			print $fh $value if defined $value;
			print $fh "\n";
		} else {
			if ( !$first_allele ) {
				print $fh ';';
			} elsif ( !$first_col ) {
				print $fh "\t";
			}
			print $fh $value if defined $value;
		}
		$first_allele = 0;
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
	if ( !$self->{'cache'}->{'cscheme_cache_table_exists'}->{$cscheme} ) {
		my $scheme_id =
		  $self->{'datastore'}->run_query( 'SELECT scheme_id FROM classification_schemes WHERE id=?', $cscheme );
		$self->{'cache'}->{'cscheme_scheme_info'}->{$cscheme}->{'scheme_id'} = $scheme_id;
		$self->{'cache'}->{'cscheme_cache_table_exists'}->{$cscheme} =
		  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)',
			["temp_isolates_scheme_fields_$scheme_id"] );
	}
	if ( !$self->{'cache'}->{'cscheme_name'}->{$cscheme} ) {
		$self->{'cache'}->{'cscheme_name'}->{$cscheme} =
		  $self->{'datastore'}->run_query( 'SELECT name FROM classification_schemes WHERE id=?', $cscheme );
	}
	my $value;
	if ( $self->{'cache'}->{'cscheme_cache_table_exists'}->{$cscheme} ) {
		if ( !$self->{'cache'}->{'cscheme_scheme_info'}->{$cscheme}->{'pk'} ) {
			my $scheme_id    = $self->{'cache'}->{'cscheme_scheme_info'}->{$cscheme}->{'scheme_id'};
			my $scheme_info  = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
			my $scheme_table = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
			$self->{'cache'}->{'cscheme_scheme_info'}->{$cscheme}->{'table'} =
			  $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
			$self->{'cache'}->{'cscheme_scheme_info'}->{$cscheme}->{'pk'} = $scheme_info->{'primary_key'};
		}
		my $scheme_id    = $self->{'cache'}->{'cscheme_scheme_info'}->{$cscheme}->{'scheme_id'};
		my $scheme_table = $self->{'cache'}->{'cscheme_scheme_info'}->{$cscheme}->{'table'};
		my $pk           = $self->{'cache'}->{'cscheme_scheme_info'}->{$cscheme}->{'pk'};
		my $pk_values    = $self->{'datastore'}->run_query( "SELECT $pk FROM $scheme_table WHERE id=?",
			$data->{'id'}, { fetch => 'col_arrayref', cache => "Export::write_cscheme::$scheme_id" } );
		if (@$pk_values) {
			my $cscheme_table = $self->{'datastore'}->create_temp_cscheme_table($cscheme);
			my $view          = $self->{'system'}->{'view'};

			#You may get multiple groups if you have a mixed sample
			my @groups = ();
			foreach my $pk_value (@$pk_values) {
				my $groups = $self->{'datastore'}->run_query( "SELECT group_id FROM $cscheme_table WHERE profile_id=?",
					$pk_value,
					{ fetch => 'col_arrayref', cache => "Export::write_cscheme::get_group::$cscheme_table" } );
				push @groups, @$groups;
			}
			@groups = uniq sort @groups;
			local $" = q(;);
			$value = qq(@groups);
		}
	}
	if ( $params->{'oneline'} ) {
		if ( $self->{'cache'}->{'cscheme_cache_table_exists'}->{$cscheme} ) {
			print $fh $self->_get_id_one_line( $data, $params );
			print $fh "$self->{'cache'}->{'cscheme_name'}->{$cscheme}\t";
			print $fh $value if defined $value;
			print $fh "\n";
		}
	} else {
		print $fh "\t"   if !$first;
		print $fh $value if defined $value;
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

sub _get_molwt {
	my ( $self, $locus_name, $allele, $met ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus_name);
	my $peptide;
	my $locus = $self->{'datastore'}->get_locus($locus_name);
	if ( $locus_info->{'data_type'} eq 'DNA' ) {
		my $seq_ref;
		try {
			if ($allele ne '0'){
				$seq_ref = $locus->get_allele_sequence($allele);
			}
		}
		catch {    #do nothing
		};
		my $seq = BIGSdb::Utils::chop_seq( $$seq_ref, $locus_info->{'orf'} || 1 );
		if ($met) {
			$seq =~ s/^(TTG|GTG)/ATG/x;
		}
		$peptide = Bio::Perl::translate_as_string($seq) if $seq;
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
	}
	catch {
		$weight = q(-);
	};
	return $weight;
}
1;
