#FlavoTyper.pm - FlavoTyper wrapper for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2026, University of Oxford
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
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See thef
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
package BIGSdb::Plugins::FlavoTyper;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use BIGSdb::Exceptions;
use List::MoreUtils qw(uniq);
use MIME::Base64    qw(encode_base64);
use Encode          qw(decode_utf8);
use IPC::Open3;
use Symbol     qw(gensym);
use File::Path qw(rmtree);
use File::Copy;
use JSON;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_RECORDS    => 1000;
use constant MAX_HTML_TABLE => 100;

sub get_attributes {
	my ($self) = @_;
	my $att = {
		name    => 'FlavoTyper',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			}
		],
		description      => 'Wrapper for FlavoTyper',
		full_description => 'FlavoTyper is a tool that performs in silico serotyping of '
		  . 'Flavobacterium psychrophilum from genome assemblies.',
		category            => 'Analysis',
		buttontext          => 'FlavoTyper',
		menutext            => 'FlavoTyper',
		module              => 'FlavoTyper',
		version             => '1.0.0',
		dbtype              => 'isolates',
		section             => 'analysis,isolate_info,postquery',
		input               => 'query',
		help                => 'tooltips',
		requires            => 'offline_jobs,FlavoTyper,seqbin',
		system_flag         => 'FlavoTyper',
		explicit_enable     => 1,
		url                 => "$self->{'config'}->{'doclink'}/data_analysis/flavotyper.html",
		order               => 50,
		min                 => 1,
		max                 => $self->_get_max_records,
		always_show_in_menu => 1,
		image               => '/images/plugins/FlavoTyper/screenshot.png'
	};
	return $att;
}

sub _get_max_records {
	my ($self) = @_;
	return $self->{'system'}->{'flavotyper_record_limit'} // $self->{'config'}->{'flavotyper_record_limit'}
	  // MAX_RECORDS;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description( { formatted => 1 } );
	return "FlavoTyper - $desc";
}

sub run {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $title  = $self->get_title;
	say qq(<h1>$title</h1>);
	if ( $q->param('submit') ) {
		my @ids = $q->multi_param('isolate_id');
		my ( $pasted_cleaned_ids, $invalid_ids ) =
		  $self->get_ids_from_pasted_list( { dont_clear => 1, has_seqbin => 1 } );
		push @ids, @$pasted_cleaned_ids;
		@ids = uniq @ids;
		my $message_html;
		if (@$invalid_ids) {
			local $" = ', ';
			my $error = q(<p>);
			if ( @$invalid_ids <= 10 ) {
				$error .=
					q(The following isolates in your pasted list are invalid - they either do not exist or )
				  . qq(do not have sequence data available: @$invalid_ids.);
			} else {
				$error .=
					@$invalid_ids
				  . q( isolates are invalid - they either do not exist or )
				  . q(do not have sequence data available.);
			}
			if (@ids) {
				$error .= q( These have been removed from the analysis.</p>);
				$message_html = $error;
			} else {
				$error .= q(</p><p>There are no valid ids in your selection to analyse.<p>);
				say qq(<div class="box statusbad">$error</div>);
				$self->_print_interface;
				return;
			}
		}
		if ( !@ids ) {
			say q(<div class="box statusbad"><p>You have not selected any records.</p></div>);
			$self->_print_interface;
			return;
		}
		my $max_records = $self->_get_max_records;
		if ( @ids > $max_records ) {
			my $count  = BIGSdb::Utils::commify( scalar @ids );
			my $max    = BIGSdb::Utils::commify($max_records);
			my $plural = @ids == 1 ? q() : q(s);
			say qq(<div class="box statusbad"><p>You have selected $count record$plural. )
			  . qq(This analysis is limited to $max records.</p></div>);
			$self->_print_interface;
			return;
		}
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		$q->delete('isolate_paste_list');
		$q->delete('isolate_id');
		my $params = $q->Vars;
		$params->{'script_name'} = $self->{'system'}->{'script_name'};
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
				isolates     => \@ids,
			}
		);
		$self->{'jobManager'}->update_job_status( $job_id, { message_html => $message_html } ) if $message_html;
		say $self->get_job_redirect($job_id);
		return;
	}
	$self->_print_info_panel;
	$self->_print_interface;
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	$self->{'exit'} = 0;
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1 } ) x 3;
	my $isolate_ids = $self->{'jobManager'}->get_job_isolates($job_id);
	my $job         = $self->{'jobManager'}->get_job($job_id);
	if ( !-x "$self->{'config'}->{'flavotyper_path'}" ) {
		$logger->error("FlavoTyper not executable: Path is $self->{'config'}->{'flavotyper_path'}");
		BIGSdb::Exception::Plugin->throw('FlavoTyper run failed.');
	}
	my $version  = $self->_get_flavotyper_version;
	my $out_dir  = "$self->{'config'}->{'secure_tmp_dir'}/$job_id/";
	my $i        = 0;
	my $progress = 0;
	my $table_header;
	my @table_rows;
	my $td        = 1;
	my $html      = @$isolate_ids > MAX_HTML_TABLE ? q(<p>Too many isolates to display HTML table.</p>) : q();
	my $text_file = "$self->{'config'}->{'tmp_dir'}/${job_id}.txt";

	foreach my $isolate_id (@$isolate_ids) {

		$progress = int( $i / @$isolate_ids * 100 );
		my $message = "Scanning isolate $i - id:$isolate_id";

		$self->{'jobManager'}
		  ->update_job_status( $job_id, { percent_complete => $progress, stage => $message, message_html => $html } );
		$i++;
		$self->_run_flavotyper( $job_id, $isolate_id );
		my $output_tsv = "$out_dir/typing_results.tsv";
		if ( -e $output_tsv ) {
			open( my $fh, '<:encoding(utf8)', $output_tsv )
			  || $logger->error("Cannot open $output_tsv for reading.");
			my $first_line = <$fh>;
			chomp $first_line;
			if ( !$table_header ) {
				my @headings = split /\t/x, $first_line;
				unshift @headings, 'id';
				$headings[1] = $self->{'system'}->{'labelfield'};
				local $" = q(</th><th>);
				$table_header = qq(<tr><th>@headings</th></tr>);
				local $" = qq(\t);
				$self->_append_text_output( $text_file, qq(@headings) );
			}
			my $result_line = <$fh>;
			chomp $result_line;
			my @results = split /\t/x, $result_line;
			unshift @results, $isolate_id;

			$results[1] = $self->get_isolate_name_from_id($isolate_id);
			local $" = qq(\t);
			$self->_append_text_output( $text_file, qq(@results) );
			$results[0] = qq(<a href="$params->{'script_name'}?db=$params->{'db'}&amp;page=info&amp;id=$isolate_id">)
			  . qq($isolate_id</a>);
			local $" = q(</td><td>);
			push @table_rows, qq(<tr class="td$td"><td>@results</td></tr>);

			$td = $td == 1 ? 2 : 1;
		} else {
			$logger->error("No FlavoTyper output file for isolate id-$isolate_id.");
		}
		local $" = qq(\n);
		if ( @$isolate_ids <= MAX_HTML_TABLE ) {
			$html = qq(<div class="scrollable"><table class="resultstable">$table_header@table_rows</table></div>);

			$self->{'jobManager'}->update_job_status(
				$job_id,
				{
					message_html     => $html,
					percent_complete => $progress
				}
			);
		}
		last if $self->{'exit'};
		my $png_file =
			"$self->{'config'}->{'secure_tmp_dir'}/${job_id}/id-${isolate_id}_locus_analysis/"
		  . "id-${isolate_id}_locus_map.png";
		if ( @$isolate_ids == 1 && -e $png_file ) {
			copy( $png_file, $self->{'config'}->{'tmp_dir'} );
			$self->{'jobManager'}->update_job_output( $job_id,
				{ filename => "id-${isolate_id}_locus_map.png", description => '01_Locus map (png format)' } );
		}
		$self->_store_results( $isolate_id, $out_dir );
	}
	$self->{'jobManager'}
	  ->update_job_output( $job_id, { filename => "$job_id.txt", description => '10_Results (Text format)' } );
	my $excel_file = BIGSdb::Utils::text2excel(
		$text_file,
		{
			worksheet => 'FlavoTyper',
			tmp_dir   => $self->{'config'}->{'secure_tmp_dir'},
		}
	);
	if ( -e $excel_file ) {
		$self->{'jobManager'}->update_job_output( $job_id,
			{ filename => "$job_id.xlsx", description => '20_Results (Excel)', compress => 1 } );
	}
	rmtree($out_dir);
	return;
}

sub _store_results {
	my ( $self, $isolate_id, $out_dir ) = @_;

	my $results     = {};
	my $output_file = qq(${out_dir}typing_results.jsonl);
	if ( -e $output_file ) {
		my $contents_ref = BIGSdb::Utils::slurp($output_file);
		eval { $results = decode_json($$contents_ref); };
		$logger->error($@) if $@;
	}
	my $version = $self->_get_flavotyper_version;
	$results->{'version'} = $version;
	my $img_file = qq(${out_dir}id-${isolate_id}_locus_analysis/id-${isolate_id}_locus_map.png);
	if ( -e $img_file ) {
		my $file_contents = BIGSdb::Utils::slurp($img_file);
		my $b64           = encode_base64($$file_contents);
		$results->{'image'} = $b64;
	}
	my $json      = encode_json($results);
	my $json_text = decode_utf8($json);
	eval {
		$self->{'db'}
		  ->do( 'DELETE FROM analysis_results WHERE (isolate_id,name)=(?,?)', undef, $isolate_id, 'FlavoTyper' );
		$self->{'db'}->do( 'INSERT INTO analysis_results (name,isolate_id,results) VALUES (?,?,?)',
			undef, 'FlavoTyper', $isolate_id, $json_text );
		$self->{'db'}->do(
			'INSERT INTO last_run (name,isolate_id) VALUES (?,?) ON '
			  . 'CONFLICT (name,isolate_id) DO UPDATE SET timestamp = now()',
			undef, 'FlavoTyper', $isolate_id
		);
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
}

sub _append_text_output {
	my ( $self, $text_file, $line ) = @_;
	open( my $fh, '>>:encoding(utf8)', $text_file ) or $logger->error("Cannot open $text_file for appending.");
	say $fh $line;
	close $fh;
	return;
}

sub _run_flavotyper {
	my ( $self, $job_id, $isolate_id ) = @_;
	my $out_dir       = "$self->{'config'}->{'secure_tmp_dir'}/$job_id/";
	my $assembly_file = $self->make_assembly_file( $job_id, $isolate_id );
	my $err_fh        = gensym;
	eval {
		my $pid = open3(
			my $in_fh, my $out_fh, $err_fh,
			"$self->{'config'}->{'flavotyper_path'}",
			( 'type', '--locus-analysis', '--genomes' => $assembly_file, '--outdir' => $out_dir )
		);
		close $in_fh;
		local $/ = undef;
		my $out = <$out_fh>;
		my $err = <$err_fh>;
		waitpid( $pid, 0 );
		my $exit_code = $? >> 8;
		if ($exit_code) {
			$logger->error($err) if $err;
			$logger->error($out) if $out;
			BIGSdb::Exception::Plugin->throw('FlavoTyper run failed.');
		}
	};
	if ($@) {
		$logger->error($@) if $@;
		BIGSdb::Exception::Plugin->throw('FlavoTyper run failed.');
	}
	return;
}

sub _print_info_panel {
	my ($self) = @_;
	say << "HTML";
<div class="box" id="resultspanel">
<p>FlavoTyper is a bioinformatics tool that performs <i>in silico</i> serotyping of <i>Flavobacterium psychrophilum</i>
genome assemblies.</p>
<p>This plugin is a wrapper for the command-line tool that enables you to run FlavoTyper against genomes in the
database.</p>
<p>FlavoTyper was developed by Salma Mbarki in the Laboratory of Eric Duchaud, Unit&eacute; Virologie et Immunologie 
Mol&eacute;culaires (INRAE), France. The code can be found at <a href="https://pypi.org/project/flavotyper/">
https://pypi.org/project/flavotyper/</a>.</p>
</div>
HTML
	return;
}

sub _print_interface {
	my ($self) = @_;
	my $seqbin_values = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT id FROM sequence_bin)');
	if ( !$seqbin_values ) {
		$self->print_bad_status( { message => q(This database view contains no genomes.), navbar => 1 } );
		return;
	}
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $qry_ref    = $self->get_query($query_file);
	my $selected_ids;
	if ( $q->param('single_isolate') ) {
		if ( !BIGSdb::Utils::is_int( scalar $q->param('single_isolate') ) ) {
			$self->print_bad_status( { message => q(Invalid isolate id passed.), navbar => 1 } );
			return;
		}
		if ( !$self->isolate_exists( scalar $q->param('single_isolate'), { has_seqbin => 1 } ) ) {
			$self->print_bad_status(
				{
					message => q(Passed isolate id either does not exist or has no sequence bin data.),
					navbar  => 1
				}
			);
			return;
		}
	}
	if ( $q->param('isolate_id') ) {
		my @ids = $q->multi_param('isolate_id');
		$selected_ids = \@ids;
	} elsif ( defined $query_file ) {
		$selected_ids = $self->get_ids_from_query($qry_ref);
	} else {
		$selected_ids = [];
	}
	say q(<div class="box" id="queryform">);
	my $version = $self->_get_flavotyper_version;

	if ($version) {
		say qq(<p>Version: $version</p>);
	}
	if ( !$q->param('single_isolate') ) {
		my $max      = $self->_get_max_records;
		my $nice_max = BIGSdb::Utils::commify($max);
		say qq(<p>Please select the required isolate ids to run the analysis for (maximum $nice_max records). )
		  . q(These isolate records must include genome sequences.</p>);
	}
	say $q->start_form;
	say q(<div class="scrollable">);
	if ( BIGSdb::Utils::is_int( scalar $q->param('single_isolate') ) ) {
		my $isolate_id = $q->param('single_isolate');
		my $name       = $self->get_isolate_name_from_id($isolate_id);
		say q(<h2>Selected record</h2>);
		say $self->get_list_block(
			[ { title => 'id', data => $isolate_id }, { title => $self->{'system'}->{'labelfield'}, data => $name } ],
			{ width => 6 } );
		say $q->hidden( isolate_id => $isolate_id );
	} else {
		$self->print_seqbin_isolate_fieldset(
			{ selected_ids => $selected_ids, isolate_paste_list => 1, only_genomes => 1 } );
	}
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach qw (page name db);
	say q(</div>);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _get_flavotyper_version {
	my ($self) = @_;
	return if !-e $self->{'config'}->{'flavotyper_path'} || !-x $self->{'config'}->{'flavotyper_path'};
	my $version;
	my $err_fh = gensym;
	eval {
		my $pid = open3( my $in_fh, my $out_fh, $err_fh, $self->{'config'}->{'flavotyper_path'}, '--version' );
		close $in_fh;
		local $/ = undef;
		my $out = <$out_fh>;
		my $err = <$err_fh>;
		waitpid( $pid, 0 );
		my $exit_code = $? >> 8;
		if ($exit_code) {
			$logger->error($err) if $err;
			$logger->error($out) if $out;
		}
		$version = $out;
	};
	chomp $version;
	return $version;
}

1;
