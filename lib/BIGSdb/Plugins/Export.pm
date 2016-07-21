#Export.pm - Export plugin for BIGSdb
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
package BIGSdb::Plugins::Export;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use Apache2::Connection ();
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
		version     => '1.3.8',
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

sub print_extra_fields {
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

sub print_options {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left"><legend>Options</legend><ul></li>);
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

sub print_extra_options {
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
		my $selected_fields = $self->get_selected_fields;
		push @$selected_fields, 'm_references' if $q->param('m_references');
		if ( !@$selected_fields ) {
			say q(<div class="box" id="statusbad"><p>No fields have been selected!</p></div>);
		} else {
			my $prefix     = BIGSdb::Utils::get_random();
			my $filename   = "$prefix.txt";
			my $query_file = $q->param('query_file');
			my $qry_ref    = $self->get_query($query_file);
			return if ref $qry_ref ne 'SCALAR';
			my $fields = $self->{'xmlHandler'}->get_field_list;
			my $view   = $self->{'system'}->{'view'};
			local $" = ",$view.";
			my $field_string = "$view.@$fields";
			$$qry_ref =~ s/SELECT\ ($view\.\*|\*)/SELECT $field_string/x;
			my $set_id = $self->get_set_id;
			$self->rewrite_query_ref_order_by($qry_ref);
			my $ids    = $self->get_ids_from_query($qry_ref);
			my $params = $q->Vars;
			$params->{'set_id'}      = $set_id if $set_id;
			$params->{'script_name'} = $self->{'system'}->{'script_name'};
			$params->{'qry'}         = $$qry_ref;
			local $" = '||';
			$params->{'selected_fields'} = "@$selected_fields";

			#We only need the isolate count to calculate the %progress.  The isolate list is not uploaded
			#to the job database because we have included the query as a parameter.  The query has ordering
			#information so the output will be in the same order as requested, which it wouldn't be if we
			#used the isolate id list from the job database.
			#If we did a list query though, we should upload the list.
			$params->{'isolate_count'} = scalar @$ids;
			if ( @$ids > MAX_INSTANT_RUN && $self->{'config'}->{'jobs_db'} ) {
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
						isolates     => $$qry_ref =~ /temp_list/x ? $ids : undef
					}
				);
				say $self->get_job_redirect($job_id);
				return;
			}
			say q(<div class="box" id="resultstable">);
			say q(<p>Please wait for processing to finish (do not refresh page).</p>);
			say q(<p class="hideonload"><span class="main_icon fa fa-refresh fa-spin fa-4x"></span></p>);
			print q(<p>Output files being generated ...);
			my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
			$self->_write_tab_text(
				{
					qry_ref  => $qry_ref,
					fields   => $selected_fields,
					filename => $full_path,
					set_id   => $set_id,
					params   => $params
				}
			);
			say q( done</p>);
			say qq(<p>Download: <a href="/tmp/$filename" target="_blank">Text file</a>);
			my $excel =
			  BIGSdb::Utils::text2excel( $full_path,
				{ worksheet => 'Export', tmp_dir => $self->{'config'}->{'secure_tmp_dir'} } );
			say qq( | <a href="/tmp/$prefix.xlsx" target="_blank">Excel file</a>) if -e $excel;
			say q( (right-click to save)</p>);
			say q(</div>);
			return;
		}
	}
	print <<"HTML";
<div class="box" id="queryform">
<p>This script will export the dataset in tab-delimited text, suitable for importing into a spreadsheet.
Select which fields you would like included.  Select loci either from the locus list or by selecting one or
more schemes to include all loci (and/or fields) from a scheme.</p>
HTML
	foreach (qw (shtml html)) {
		my $policy = "$ENV{'DOCUMENT_ROOT'}$self->{'system'}->{'webroot'}/policy.$_";
		if ( -e $policy ) {
			say q(<p>Use of exported data is subject to the terms of the )
			  . qq(<a href='$self->{'system'}->{'webroot'}/policy.$_'>policy document</a>!</p>);
			last;
		}
	}
	$self->print_field_export_form( 1, { include_composites => 1, extended_attributes => 1 } );
	say q(</div>);
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
	if ( $params->{'qry'} =~ /temp_list/x ) {
		my $ids = $self->{'jobManager'}->get_job_isolates($job_id);
		$self->{'datastore'}->create_temp_list_table_from_array( 'integer', $ids, { table => 'temp_list' } );

		#Convert list attribute field to ids.
		my $view            = $self->{'system'}->{'view'};
		my $BY_ID           = "($view.id IN (SELECT value FROM temp_list)) ORDER BY";
		$params->{'qry'} =~ s/FROM\ $view.*?ORDER\ BY/FROM $view WHERE $BY_ID/x;
	}
	my $limit =
	  BIGSdb::Utils::is_int( $self->{'system'}->{'export_limit'} )
	  ? $self->{'system'}->{'export_limit'}
	  : MAX_DEFAULT_DATA_POINTS;
	my $data_points = $params->{'isolate_count'} * @fields;
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
			qry_ref  => \$params->{'qry'},
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
		my $excel_file =
		  BIGSdb::Utils::text2excel( $filename,
			{ worksheet => 'Export', tmp_dir => $self->{'config'}->{'secure_tmp_dir'} } );
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
	my ( $qry_ref, $fields, $filename, $set_id, $offline, $params ) =
	  @{$args}{qw(qry_ref fields filename set_id offline params)};
	$self->create_temp_tables($qry_ref);
	open( my $fh, '>:encoding(utf8)', $filename )
	  || $logger->error("Can't open temp file $filename for writing");
	if ( $params->{'oneline'} ) {
		print $fh "id\t";
		print $fh $self->{'system'}->{'labelfield'} . "\t" if $params->{'labelfield'};
		print $fh "Field\tValue";
		print $fh "\tCurator\tDatestamp\tComments" if $params->{'info'};
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
			$field =~ s/^(s_\d+_l|s_\d+_f|f|l|c|m)_//x;    #strip off prefix for header row
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			$field =~ s/^.*___//x;
			if ($is_locus) {
				$field =
				  $self->clean_locus( $field,
					{ text_output => 1, ( no_common_name => $params->{'common_names'} ? 0 : 1 ) } );
				if ( $params->{'alleles'} ) {
					print $fh "\t" if !$first;
					print $fh $field;
					$first = 0;
				}
				if ( $params->{'molwt'} ) {
					print $fh "\t" if !$first;
					print $fh "$field Mwt";
					$first = 0;
				}
			} else {
				print $fh "\t" if !$first;
				print $fh $metafield // $field;
				$first = 0;
			}
		}
		my $scheme_field_pos;
		foreach my $scheme_id ( keys %schemes ) {
			my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
			my $i             = 0;
			foreach (@$scheme_fields) {
				$scheme_field_pos->{$scheme_id}->{$_} = $i;
				$i++;
			}
		}
		if ($first) {
			say $fh 'Make sure you select an option for locus export (see options in the top-right corner).';
			return;
		}
	}
	print $fh "\n";
	my $sql = $self->{'db'}->prepare($$qry_ref);
	eval { $sql->execute };
	$logger->error($@) if $@;
	my %data           = ();
	my $fields_to_bind = $self->{'xmlHandler'}->get_field_list;
	$sql->bind_columns( map { \$data{$_} } @$fields_to_bind );    #quicker binding hash to arrayref than to use hashref
	my $i = 0;
	my $j = 0;
	local $| = 1;
	my %id_used;
	my $total    = 0;
	my $progress = 0;

	while ( $sql->fetchrow_arrayref ) {
		next
		  if $id_used{ $data{ 'id'
		  } };    #Ordering by scheme field/locus can result in multiple rows per isolate if multiple values defined.
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
		foreach (@$fields) {
			if ( $_ =~ /^f_(.*)/x ) {
				$self->_write_field( $fh, $1, \%data, $first, $params );
			} elsif ( $_ =~ /^(s_\d+_l_|l_)(.*)/x ) {
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
			} elsif ( $_ =~ /^s_(\d+)_f_(.*)/x ) {
				$self->_write_scheme_field(
					{ fh => $fh, scheme_id => $1, field => $2, data => \%data, first => $first, params => $params } );
			} elsif ( $_ =~ /^c_(.*)/x ) {
				$self->_write_composite( $fh, $1, \%data, $first, $params );
			} elsif ( $_ =~ /^m_references/x ) {
				$self->_write_ref( $fh, \%data, $first, $params );
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
		if ( $offline && $params->{'job_id'} && $params->{'isolate_count'} ) {
			my $new_progress = int( $total / $params->{'isolate_count'} * 100 );

			#Only update when progress percentage changes when rounded to nearest 1 percent
			if ( $new_progress > $progress ) {
				$progress = $new_progress;
				$self->{'jobManager'}->update_job_status( $params->{'job_id'}, { percent_complete => $progress } );
			}
			last if $self->{'exit'};
		}
	}
	close $fh;
	return;
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
		if ( !$self->{'sql'}->{'attribute'} ) {
			$self->{'sql'}->{'attribute'} =
			  $self->{'db'}->prepare( 'SELECT value FROM isolate_value_extended_attributes WHERE '
				  . '(isolate_field,attribute,field_value)=(?,?,?)' );
		}
		eval { $self->{'sql'}->{'attribute'}->execute( $isolate_field, $attribute, $data->{$isolate_field} ) };
		$logger->error($@) if $@;
		my ($value) = $self->{'sql'}->{'attribute'}->fetchrow_array;
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

sub _sort_alleles {
	my ( $self, $locus, $allele_ids ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	return $allele_ids if !$locus_info;
	my @list = $locus_info->{'allele_id_format'} eq 'integer' ? sort { $a <=> $b } @$allele_ids : sort @$allele_ids;
	return \@list;
}

sub _write_allele {
	my ( $self, $args ) = @_;
	my ( $fh, $locus, $data, $all_allele_ids, $first_col, $params ) =
	  @{$args}{qw(fh locus data all_allele_ids first params)};
	my @unsorted_allele_ids = defined $all_allele_ids->{$locus} ? @{ $all_allele_ids->{$locus} } : ('');
	my $allele_ids = $self->_sort_alleles( $locus, \@unsorted_allele_ids );
	if ( $params->{'alleles'} ) {
		my $first_allele = 1;
		foreach my $allele_id (@$allele_ids) {
			if ( $params->{'oneline'} ) {
				print $fh $self->_get_id_one_line( $data, $params );
				print $fh "$locus\t";
				print $fh $allele_id;
				if ( $params->{'info'} ) {
					my $allele_info = $self->{'datastore'}->run_query(
						'SELECT allele_designations.datestamp AS des_datestamp,first_name,'
						  . 'surname,comments FROM allele_designations LEFT JOIN users ON '
						  . 'allele_designations.curator = users.id WHERE (isolate_id,locus,allele_id)=(?,?,?)',
						[ $data->{'id'}, $locus, $allele_id ],
						{ fetch => 'row_hashref', cache => 'Export::write_allele::info' }
					);
					if ( defined $allele_info ) {
						print $fh "\t$allele_info->{'first_name'} $allele_info->{'surname'}\t";
						print $fh "$allele_info->{'des_datestamp'}\t";
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
			$seq_ref = $locus->get_allele_sequence($allele);
		}
		catch BIGSdb::DatabaseConnectionException with {

			#do nothing
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
	catch Bio::Root::Exception with {
		$weight = q(-);
	};
	return $weight;
}
1;
