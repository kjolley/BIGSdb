#Reports.pm - Isolate report plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2023-2025, University of Oxford
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
package BIGSdb::Plugins::Reports;
use strict;
use warnings;
use 5.010;
use parent            qw(BIGSdb::Plugin);
use BIGSdb::Constants qw(:interface);
use TOML;
use Template;
use Template::Stash;
use JSON;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name    => 'Reports',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			}
		],
		description      => 'Prepare formatted isolate reports based on template files',
		full_description => 'The Reports plugin prepares PDF reports that describe a specific isolate record based on '
		  . 'template files. Multiple reports can be generated that are aimed at different roles, e.g. clinical, public '
		  . 'health, or genomics specialists.',
		category        => 'Export',
		buttontext      => 'Reports',
		menutext        => 'Reports',
		module          => 'Reports',
		version         => '1.1.0',
		dbtype          => 'isolates',
		section         => 'isolate_info',
		input           => '',
		order           => 10,
		help            => 'tooltips',
		system_flag     => 'Reports',
		explicit_enable => 1,
		url             => "$self->{'config'}->{'doclink'}/data_analysis/reports.html",
		requires        => 'weasyprint',
		image           => '/images/plugins/Reports/screenshot.png'
	);
	return \%att;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description( { formatted => 1 } );
	return "Reports - $desc";
}

sub run {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $title  = $self->get_title;
	if ( $q->param('isolate_id') && $q->param('report') ) {
		my $isolate_id = $q->param('isolate_id');
		my $report     = $q->param('report');
		my $check      = $self->_check_params( $isolate_id, $report );
		if ( $check->{'error'} ) {
			say qq(<h1>$title</h1>);
			$self->print_bad_status(
				{
					message => $check->{'error'}
				}
			);
			return;
		}
		$self->_generate_report( $isolate_id, $report );
		return;
	}
	say qq(<h1>$title</h1>);
	$self->_print_interface;
	return;
}

sub _check_params {
	my ( $self, $isolate_id, $report ) = @_;
	my $error;
	if ( !BIGSdb::Utils::is_int($isolate_id) ) {
		$error = 'Isolate id must be an integer.';
	} elsif ( !$self->isolate_exists($isolate_id) ) {
		$error = 'No record exists for passed isolate id.';
	}
	if ( !$error ) {
		if ( !BIGSdb::Utils::is_int($report) ) {
			$error = 'Report id must be an integer.';
		} else {
			my $template_list = $self->_get_templates;
			if ( $template_list->{'error'} ) {
				$error = $template_list->{'error'};
			} else {
				my %report_ids = map { $_->{'index'} => 1 } @{ $template_list->{'templates'} };
				$error = 'Passed report id does not exist' if !$report_ids{$report};
			}
		}
	}
	return {
		passed => !defined $error,
		error  => $error
	};
}

sub _generate_report {
	my ( $self, $isolate_id, $report_id ) = @_;
	my $template_info = $self->_get_template_info($report_id);
	my $dir           = $self->_get_template_dir;
	$Template::Stash::LIST_OPS->{'format_list'} = sub {
		my ( $list, $args ) = @_;
		my ( $separator, $prefix, $empty_term, $final_term ) =
		  @{$args}{qw(separator prefix empty_term final_term)};
		$separator //= q(, );
		$prefix    //= q();
		@$list = grep { defined $_ && $_ ne q() } @$list;
		$separator //= q(, );
		local $" = qq($separator$prefix);
		return $empty_term if !@$list;
		my $value = qq($prefix@$list);

		if ( $final_term && @$list > 1 ) {

			#Term may contain spaces so don't use /x
			$value =~ s/$separator$list->[-1]$/$final_term$list->[-1]/;    ##no critic(RequireExtendedFormatting)
		}
		return $value;
	};
	my $template = Template->new(
		{
			INCLUDE_PATH => $dir,
			TRIM         => 1
		}
	);
	my $template_output = q();
	my $data            = $self->_get_isolate_data( $isolate_id, $report_id );
	$data->{'date'} = BIGSdb::Utils::get_datestamp();
	$data->{'css'}  = ${ BIGSdb::Utils::slurp("$dir/style.css") };
	$template->process( $template_info->{'template_file'}, $data, \$template_output )
	  || $logger->error( $template->error );

	if ( $self->{'format'} eq 'html' ) {
		say $template_output;
		return;
	}

	#Convert to PDF.
	open( my $make_pdf, '|-', $self->{'config'}->{'weasyprint_path'}, '-', '-' )
	  || $logger->error("Cannot convert PDF. $!");
	say $make_pdf $template_output;
	close $make_pdf;
	return;
}

sub _get_isolate_data {
	my ( $self, $isolate_id, $report_id ) = @_;
	my $data = {};
	$data->{'fields'}          = $self->_get_field_values($isolate_id);
	$data->{'aliases'}         = $self->{'datastore'}->get_isolate_aliases($isolate_id);
	$data->{'alleles'}         = $self->_get_allele_data($isolate_id);
	$data->{'schemes'}         = $self->_get_scheme_values( $isolate_id, $report_id );
	$data->{'lincodes'}        = $self->_get_lincodes( $isolate_id, $report_id );
	$data->{'analysis'}        = $self->_get_analysis_results($isolate_id);
	$data->{'assembly'}        = $self->_get_assembly_details($isolate_id);
	$data->{'assembly_checks'} = $self->_get_assembly_checks($isolate_id);
	return $data;
}

sub _get_assembly_details {
	my ( $self, $isolate_id ) = @_;
	return $self->{'datastore'}->run_query( 'SELECT contigs,total_length,n50,l50 FROM seqbin_stats WHERE isolate_id=?',
		$isolate_id, { fetch => 'row_hashref' } );
}

sub _get_assembly_checks {
	my ( $self, $isolate_id ) = @_;
	my $checks   = {};
	my $last_run = $self->{'datastore'}
	  ->run_query( 'SELECT timestamp FROM last_run WHERE (name,isolate_id)=(?,?)', [ 'AssemblyChecks', $isolate_id ] );
	$checks->{'last_run'} = $last_run if $last_run;
	my $warn = $self->{'datastore'}->run_query(
		'SELECT name FROM assembly_checks WHERE (isolate_id,status)=(?,?)',
		[ $isolate_id, 'warn' ],
		{ fetch => 'col_arrayref' }
	);
	$checks->{'warn'} = $warn if @$warn;
	my $fail = $self->{'datastore'}->run_query(
		'SELECT name FROM assembly_checks WHERE (isolate_id,status)=(?,?)',
		[ $isolate_id, 'fail' ],
		{ fetch => 'col_arrayref' }
	);
	$checks->{'fail'} = $fail if @$fail;
	return $checks;
}

sub _get_field_values {
	my ( $self, $isolate_id ) = @_;
	my $data = $self->{'datastore'}->get_isolate_field_values($isolate_id);
	my $ext_attributes =
	  $self->{'datastore'}->run_query( 'SELECT attribute,isolate_field FROM isolate_field_extended_attributes',
		undef, { fetch => 'all_arrayref', slice => {} } );
	foreach my $att (@$ext_attributes) {
		my $value = $self->{'datastore'}->run_query(
			'SELECT value FROM isolate_value_extended_attributes WHERE (attribute,isolate_field,field_value)=(?,?,?)',
			[ $att->{'attribute'}, $att->{'isolate_field'}, $data->{ lc $att->{'isolate_field'} } ],
			{ cache => 'Reports::get_extended_attributes' }
		);
		$data->{ $att->{'attribute'} } = $value if defined $value;
	}
	my $eav_fields = $self->{'datastore'}->get_eav_fieldnames;
	foreach my $eav_field (@$eav_fields) {
		my $value = $self->{'datastore'}->get_eav_field_value( $isolate_id, $eav_field );
		$data->{$eav_field} = $value if defined $value;
	}
	return $data;
}

sub _get_scheme_values {
	my ( $self, $isolate_id, $report_id ) = @_;
	my $template   = $self->_get_template_info($report_id);
	my $scheme_ids = $template->{'requires'}->{'schemes'};
	my $data       = {};
	return $data if !ref $scheme_ids || !@$scheme_ids;
	foreach my $scheme_id (@$scheme_ids) {
		my $values =
		  $self->{'datastore'}->get_scheme_field_values_by_isolate_id( $isolate_id, $scheme_id,
			{ fewest_missing => 1, no_status => 1 } )
		  ;
		$data->{$scheme_id} = $values;
	}
	return $data;
}

sub _get_lincodes {
	my ( $self, $isolate_id, $report_id ) = @_;
	my $template  = $self->_get_template_info($report_id);
	my $scheme_id = $template->{'requires'}->{'lincodes'}->{'scheme'};
	my $data      = {};
	return $data if !BIGSdb::Utils::is_int($scheme_id) || !$self->{'datastore'}->are_lincodes_defined($scheme_id);
	my $lincode = $self->{'datastore'}->get_lincode_value( $isolate_id, $scheme_id );
	if ( ref $lincode && @$lincode ) {
		my $clusters = $self->_get_lincode_clusters( $isolate_id, $lincode, $report_id );
		$data->{'clusters'} = $clusters if keys %$clusters;
		local $" = q(_);
		my $lincode_string = qq(@$lincode);
		$data->{'lincode'} = $lincode_string;
		my $prefix_table = $self->{'datastore'}->create_temp_lincode_prefix_values_table($scheme_id);
		my $prefix_data  = $self->{'datastore'}
		  ->run_query( "SELECT * FROM $prefix_table", undef, { fetch => 'all_arrayref', slice => {} } );
		my $prefix_values = {};

		foreach my $record (@$prefix_data) {
			$prefix_values->{ $record->{'field'} }->{ $record->{'prefix'} } = $record->{'value'};
		}
		my $prefix_fields =
		  $self->{'datastore'}
		  ->run_query( 'SELECT field FROM lincode_fields WHERE scheme_id=? ORDER BY display_order,field',
			$scheme_id, { fetch => 'col_arrayref' } );
		foreach my $field (@$prefix_fields) {
			my %used;
			my @prefixes = keys %{ $prefix_values->{$field} };
			my @values;
			foreach my $prefix (@prefixes) {
				if (   $lincode_string eq $prefix
					|| $lincode_string =~ /^${prefix}_/x && !$used{ $prefix_values->{$field}->{$prefix} } )
				{
					push @values, $prefix_values->{$field}->{$prefix};
					$used{ $prefix_values->{$field}->{$prefix} } = 1;
				}
			}
			@values = sort @values;
			local $" = q(; );
			next if !@values;
			$field =~ tr/ /_/;
			$data->{ lc $field } = [@values];
		}
	}
	return $data;
}

sub _get_lincode_clusters {
	my ( $self, $isolate_id, $lincode, $report_id ) = @_;
	my $template   = $self->_get_template_info($report_id);
	my $scheme_id  = $template->{'requires'}->{'lincodes'}->{'scheme'};
	my $thresholds = $template->{'requires'}->{'lincodes'}->{'clusters'}->{'thresholds'};
	my $fields     = $template->{'requires'}->{'lincodes'}->{'clusters'}->{'fields'};
	my $data       = {};
	return $data if !defined $thresholds || !defined $scheme_id || !BIGSdb::Utils::is_int($scheme_id);
	my $cache_table_exists =
	  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)',
		["temp_isolates_scheme_fields_$scheme_id"] );

	if ( !$cache_table_exists ) {
		$logger->warn( "$self->{'instance'}: Scheme $scheme_id is not cached for this database.  "
			  . 'Display of similar isolates is disabled. You need to run the update_scheme_caches.pl script '
			  . 'regularly against this database to create these caches.' );
		return $data;
	}
	my $scheme_info        = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key        = $scheme_info->{'primary_key'};
	my $scheme_field_table = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
	my $lincode_table      = $self->{'datastore'}->create_temp_lincodes_table($scheme_id);
	my @prov_fields;
	foreach my $field (@$fields) {
		next if $field eq 'id';
		next if !$self->{'xmlHandler'}->is_field($field);
		push @prov_fields, $field;
	}
	foreach my $threshold (@$thresholds) {
		next if !BIGSdb::Utils::is_int($threshold);
		next if $threshold > @$lincode;
		my @prefix = @$lincode[ 0 .. $threshold - 1 ];
		local $" = q(,v.);
		my $prov_field_string = @prov_fields ? qq(,v.@prov_fields) : q();
		my $qry =
			"SELECT v.id$prov_field_string,array_to_string(l.lincode,'_') AS lincode "
		  . "FROM $scheme_field_table sf JOIN $lincode_table l "
		  . "ON CAST(sf.$primary_key AS text)=l.profile_id JOIN "
		  . "$self->{'system'}->{'view'} v ON v.id=sf.id WHERE ";
		for ( my $i = 1 ; $i <= $threshold ; $i++ ) {    #PostgreSQL uses 1-based index
			$qry .= ' AND ' if $i > 1;
			$qry .= "lincode[$i]=? ";
		}
		$qry .= "GROUP BY v.id$prov_field_string,l.lincode ORDER BY l.lincode";
		my $isolate_records =
		  $self->{'datastore'}->run_query( $qry, [@prefix], { fetch => 'all_arrayref', slice => {} } );
		$data->{$threshold}->{'isolates'} = $isolate_records;
		$data->{$threshold}->{'similar'}  = @$isolate_records - 1;
		local $" = q(_);
		$data->{$threshold}->{'prefix'} = qq(@$lincode[0 .. $threshold - 1]);
	}
	return $data;
}

sub _get_allele_data {
	my ( $self, $isolate_id ) = @_;
	my $alleles = $self->{'datastore'}->run_query( 'SELECT locus,allele_id FROM allele_designations WHERE isolate_id=?',
		$isolate_id, { fetch => 'all_arrayref', slice => {} } );
	my $data = {};
	foreach my $allele (@$alleles) {
		push @{ $data->{ $allele->{'locus'} } }, $allele->{'allele_id'};
	}
	return $data;
}

sub _get_analysis_results {
	my ( $self, $isolate_id ) = @_;
	my $data = $self->{'datastore'}->run_query( 'SELECT * FROM analysis_results WHERE isolate_id=?',
		$isolate_id, { fetch => 'all_arrayref', slice => {} } );
	my $results = {};
	foreach my $analysis (@$data) {
		$results->{ $analysis->{'name'} } = {
			results   => decode_json( $analysis->{'results'} ),
			datestamp => $analysis->{'datestamp'}
		};
	}
	return $results;
}

sub _print_interface {
	my ($self) = @_;
	my $templates = $self->_get_templates;
	if ( $templates->{'error'} ) {
		$self->print_bad_status(
			{
				message => $templates->{'error'}
			}
		);
		return;
	}
	my $q          = $self->{'cgi'};
	my $isolate_id = $q->param('single_isolate');
	if ( !BIGSdb::Utils::is_int($isolate_id) ) {
		$self->print_bad_status(
			{
				message => q(No isolate id passed.)
			}
		);
		return;
	}
	say q(<div class="box" id="resultstable">);
	say q(<p>This tool will export isolate reports in PDF format based on specific templates. Click the appropriate )
	  . q(link to generate and download the report.</p>);
	say q(<h2>Available reports</h2>);
	say q(<div class="grid scrollable">);
	foreach my $template ( @{ $templates->{'templates'} } ) {
		my $pdf  = PDF_FILE;
		my $html = HTML_FILE;
		my $url  = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;"
		  . "name=Reports&amp;isolate_id=$isolate_id&amp;report=$template->{'index'}";
		my $desc = $template->{'name'};
		$desc .= qq( - $template->{'comments'}) if $template->{'comments'};
		say qq(<div class="file_output"><a href="$url&amp;format=html" target="_blank">)
		  . qq(<span style="float:left;margin-right:0.2em">$html</span></a>)
		  . qq(<a href="$url&amp;format=pdf"><span style="float:left;margin-right:1em">$pdf</span></a>)
		  . qq(<div style="width:90%;margin-top:0.2em">$desc);
		say q(</div></div>);
	}
	say q(<div style="clear:both"></div>);
	say q(</div></div>);
	return;
}

sub get_plugin_javascript {
	my ($self) = @_;
	my $buffer = << "END";
var last_html = '';
\$(function () {
    \$(".grid").packery();
});
END
	return $buffer;
}

sub get_initiation_values {
	my ($self) = @_;
	my $values = {
		noCache => 1,
		packery => 1
	};
	my $q          = $self->{'cgi'};
	my $isolate_id = $q->param('isolate_id');
	my $report     = $q->param('report');
	my $format     = $q->param('format');
	$format //= 'html';
	$format = 'html' if $format ne 'pdf';
	$self->{'format'} = $format;
	my $check = $self->_check_params( $isolate_id, $report );

	if ( $check->{'passed'} ) {
		my $template_info = $self->_get_template_info($report);
		( my $name = lc( $template_info->{'name'} ) ) =~ s/\s/_/gx;
		my $filename = "id_${isolate_id}_${name}.$format";
		if ( $format eq 'pdf' ) {
			$values->{'attachment'} = $filename;
		}
		$values->{'type'} = $format;
	}
	return $values;
}

sub _get_template_dir {
	my ($self) = @_;
	return "$self->{'dbase_config_dir'}/$self->{'instance'}/Reports";
}

sub _get_templates {
	my ($self) = @_;
	my $dir = $self->_get_template_dir;
	if ( !-e $dir ) {
		$logger->error("Report template directory $dir does not exist.");
		return { error => q(Report template directory does not exist.) };
	}
	my $filename = "$dir/reports.toml";
	if ( !defined $self->{'cache'}->{'reports'} ) {
		my $templates = [];
		my $data;
		my $error;
		if ( -e $filename ) {
			my $toml = BIGSdb::Utils::slurp($filename);
			my $err;
			( $data, $err ) = from_toml($$toml);
			if ( !$data->{'reports'} ) {
				$logger->error("Error parsing $filename: $err");
				return { error => qq(Error parsing $filename: $err) };
			}
		} else {
			$logger->error("Report template configuration file $filename does not exist.");
			return { error => q(Report template configuration file does not exist.) };
		}
		my $i = 0;
	  REPORT: foreach my $report ( @{ $data->{'reports'} } ) {
			$i++;
			foreach my $attribute (qw(name template_file)) {
				if ( !defined $report->{$attribute} ) {
					$logger->error("$attribute attribute is not defined for template $i in $filename");
					next REPORT;
				}
			}
			my $full_path = "$dir/$report->{'template_file'}";
			if ( !-e $full_path ) {
				$logger->error("Report template file $full_path does not exist.");
				next REPORT;
			}
			$report->{'index'} = $i;
			push @$templates, $report;
		}
		$self->{'cache'}->{'reports'} = $templates;
	}
	my $templates = $self->{'cache'}->{'reports'};
	if ( !@$templates ) {
		$logger->error("No template files described in $filename exist.");
		return { error => q(No template files found.) };
	}
	return { templates => $templates };
}

sub _get_template_info {
	my ( $self, $report_id ) = @_;
	my $templates = $self->_get_templates;
	return if !defined $templates->{'templates'};
	foreach my $template ( @{ $templates->{'templates'} } ) {
		return $template if $template->{'index'} == $report_id;
	}
	return;
}
1;
