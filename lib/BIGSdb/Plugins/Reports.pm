#Reports.pm - Isolate report plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2023, University of Oxford
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
use parent qw(BIGSdb::Plugin);
use BIGSdb::Constants qw(:interface);
use TOML;
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
		version         => '1.0.0',
		dbtype          => 'isolates',
		section         => 'isolate_info',
		input           => '',
		order           => 10,
		help            => 'tooltips',
		system_flag     => 'Reports',
		explicit_enable => 1,

		#		url         => "$self->{'config'}->{'doclink'}/data_analysis/reports.html",
		requires => 'wkhtmltopdf',

		#		image       => '/images/plugins/Reports/screenshot.png'
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
		my $error;
		my $isolate_id = $q->param('isolate_id');
		if ( !BIGSdb::Utils::is_int($isolate_id) ) {
			$error = 'Isolate id must be an integer.';
		} elsif ( !$self->isolate_exists($isolate_id) ) {
			$error = 'No record exists for passed isolate id.';
		}
		my $report = $q->param('report');
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
		if ($error) {
			say qq(<h1>$title</h1>);
			$self->print_bad_status(
				{
					message => $error
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

sub _generate_report {
	my ( $self, $isolate_id, $report ) = @_;
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
		my $icon = PDF_FILE;
		my $url  = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;"
		  . "name=Reports&amp;isolate_id=$isolate_id&amp;report=$template->{'index'}";
		say qq(<div class="file_output"><a href="$url">)
		  . qq(<span style="float:left;margin-right:1em">$icon</span></a>)
		  . qq(<div style="width:90%;margin-top:1em"><a href="$url">$template->{'name'}</a> - $template->{'comments'});
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
	return { packery => 1 };
}

sub _get_templates {
	my ($self) = @_;
	my $dir = "$self->{'dbase_config_dir'}/$self->{'instance'}/Reports";
	if ( !-e $dir ) {
		$logger->error("Report template directory $dir does not exist.");
		return { error => q(Report template directory does not exist.) };
	}
	my $templates = [];
	my $filename  = "$dir/reports.toml";
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
	foreach my $report ( @{ $data->{'reports'} } ) {
		$i++;
		foreach my $attribute (qw(name template_file comments)) {
			if ( !defined $report->{$attribute} ) {
				$logger->error("$attribute attribute is not defined for template $i in $filename");
				next;
			}
		}
		my $full_path = "$dir/$report->{'template_file'}";
		if ( !-e $full_path ) {
			$logger->error("Report template file $full_path does not exist.");
			next;
		}
		$report->{'index'} = $i;
		push @$templates, $report;
	}
	if ( !@$templates ) {
		$logger->error("No template files described in $filename exist.");
		return { error => q(No template files found.) };
	}
	return { templates => $templates };
}
1;
