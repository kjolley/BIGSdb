#Kaptive.pm - Kaptive wrapper for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2025, University of Oxford
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
package BIGSdb::Plugins::Kaptive;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use BIGSdb::Utils;
use List::MoreUtils qw(uniq);
use Text::CSV;
use File::Path qw(make_path rmtree);
use JSON;
use File::Copy;

use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_RECORDS => 1000;
use constant VALID_DBS   => (qw(kpsc_k kpsc_o ab_k ab_o));
use constant DB_NAMES => {
	kpsc_k => 'Klebsiella K locus',
	kpsc_o => 'Klebsiella O locus',
	ab_k   => 'Acinetobacter baumannii K locus',
	ab_o   => 'Acinetobacter baumannii OC locus'
};

sub get_attributes {
	my ($self) = @_;
	my $att = {
		name    => 'Kaptive',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			}
		],
		description      => 'Wrapper for Kaptive',
		full_description => 'Kaptive reports information about surface polysaccharide loci for <i>Klebsiella '
		  . 'pneumoniae</i> species complex and <i>Acinetobacter baumannii</i> genome assemblies.',
		category            => 'Third party',
		buttontext          => 'Kaptive',
		menutext            => 'Kaptive',
		module              => 'Kaptive',
		version             => '1.0.1',
		dbtype              => 'isolates',
		section             => 'third_party,isolate_info,postquery',
		input               => 'query',
		help                => 'tooltips',
		requires            => 'offline_jobs,Kaptive,seqbin',
		system_flag         => 'Kaptive',
		explicit_enable     => 1,
		url                 => "$self->{'config'}->{'doclink'}/data_analysis/kaptive.html",
		order               => 37,
		min                 => 1,
		max                 => $self->_get_max_records,
		always_show_in_menu => 1,
		image               => '/images/plugins/Kaptive/screenshot.png'
	};
	return $att;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description( { formatted => 1 } );
	return "Kaptive - $desc";
}

sub _get_max_records {
	my ($self) = @_;
	return $self->{'system'}->{'kaptive_record_limit'} // $self->{'config'}->{'kaptive_record_limit'} // MAX_RECORDS;
}

sub _check_dbs {
	my ($self) = @_;
	if ( !defined $self->{'system'}->{'kaptive_dbs'} ) {
		$self->print_bad_status( { message => 'No Kaptive dbs have been specified in database configuration.' } );
		$logger->error( "$self->{'instance'}: kaptive_dbs have not been set in config.xml - "
			  . 'this should be a comma-separated list containing one or more of: '
			  . 'kpsc_k, kpsc_o, ab_k, and ab_o.' );
		return 1;
	}
	my @dbs   = split( /\s*,\s*/x, $self->{'system'}->{'kaptive_dbs'} );
	my %valid = map { $_ => 1 } VALID_DBS;
	foreach my $db (@dbs) {
		if ( !$valid{$db} ) {
			$self->print_bad_status(
				{
					message =>
					  'Invalid databases specified in Kaptive configuration. Please contact site administrator.'
				}
			);
			$logger->error("$self->{'instance'}: kaptive_dbs setting in config.xml contains invalid database: $db");
			return 1;
		}
	}
	return;
}

sub run {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $title  = $self->get_title;
	say qq(<h1>$title</h1>);
	return if $self->_check_dbs;

	if ( $q->param('submit') ) {
		if ( defined $q->param('method') ) {
			my $guid = $self->get_guid;
			eval {
				$self->{'prefstore'}->set_plugin_attribute( $guid, $self->{'system'}->{'db'},
					'Kaptive', 'method', scalar $q->param('method') );
			};
		}
		my @ids = $q->multi_param('isolate_id');
		my ( $pasted_cleaned_ids, $invalid_ids ) =
		  $self->get_ids_from_pasted_list( { dont_clear => 1, has_seqbin => 1 } );
		push @ids, @$pasted_cleaned_ids;
		@ids = uniq @ids;
		my ( $filtered_ids, $view_invalid ) = $self->_filter_ids_by_kaptive_view( \@ids );
		@ids = @$filtered_ids;
		push @$invalid_ids, @$view_invalid if @$view_invalid;
		my $message_html;

		if (@$invalid_ids) {
			local $" = ', ';
			my $error = q(<p>);
			if ( @$invalid_ids <= 10 ) {
				$error .=
					q(The following isolates in your pasted list are invalid - they either do not exist, )
				  . q(do not have sequence data available, or have been filtered out as not suitable to run )
				  . q(Kaptive against: @$invalid_ids.);
			} else {
				$error .=
					@$invalid_ids
				  . q( isolates are invalid - they either do not exist, do not have sequence data available, )
				  . q(or have been filtererd out as not suitable to run Kaptive against.);
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
	if ( $self->{'system'}->{'kaptive_view'} ) {
		if ( $q->param('single_isolate') ) {
			my $valid_id =
			  $self->{'datastore'}
			  ->run_query( "SELECT EXISTS(SELECT * FROM $self->{'system'}->{'kaptive_view'} WHERE id=?)",
				scalar $q->param('single_isolate') );
			if ( !$valid_id ) {
				my $detail =
				  $self->{'system'}->{'kaptive_view_desc'} ? ": $self->{'system'}->{'kaptive_view_desc'}" : q();
				$self->print_bad_status(
					{
						message => 'Kaptive cannot be run against this isolate.',
						detail  => "Use of Kaptive is restricted to a specific database view$detail"
					}
				);
				return;
			}
		}

	}
	$self->_print_info_panel;
	$self->_print_interface;
	return;
}

sub _filter_ids_by_kaptive_view {
	my ( $self, $ids ) = @_;
	my $filtered = [];
	my $invalid  = [];
	if ( !$self->{'system'}->{'kaptive_view'} ) {
		$filtered = $ids;
	} else {
		my $temp_table = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $ids );
		$filtered =
		  $self->{'datastore'}
		  ->run_query( "SELECT v.id FROM $self->{'system'}->{'kaptive_view'} v JOIN $temp_table t ON v.id=t.value",
			undef, { fetch => 'col_arrayref' } );
		my %valid = map { $_ => 1 } @$filtered;
		foreach my $id (@$ids) {
			push @$invalid, $id if !$valid{$id};
		}
	}
	return ( $filtered, $invalid );
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
	my $version = $self->_get_kaptive_version;
	say q(<div class="box" id="queryform"><p>This tool will run Kaptive against selected genome assembles )
	  . q(and produce the results in tabular form.</p>);
	if ($version) {
		say qq(<ul><li>Kaptive version: $version</li>);
		my @dbs = split /\s*,\s*/x, $self->{'system'}->{'kaptive_dbs'};
		local $" = q(, );
		my $plural = @dbs == 1 ? q() : q(s);
		my @db_names;
		my $db_names = DB_NAMES;
		foreach my $db (@dbs) {
			push @db_names, "$db_names->{$db} ($db)";
		}
		say qq(<li>Database$plural: @db_names</li></ul>);
	} else {
		$logger->error('Kaptive version not determined. Check configuration.');
	}
	if ( !$q->param('single_isolate') ) {
		my $max      = $self->_get_max_records;
		my $nice_max = BIGSdb::Utils::commify($max);
		say qq(<p>Please select the required isolate ids to run the analysis for (maximum $nice_max records). )
		  . q(These isolate records must include genome sequences.</p>);
		if ( $self->{'system'}->{'kaptive_view'} && $self->{'system'}->{'kaptive_view_desc'} ) {
			print qq(<p>$self->{'system'}->{'kaptive_view_desc'}</p>);
		}
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

sub _print_info_panel {
	my ($self) = @_;
	say << "HTML";
<div class="box" id="resultspanel" style="min-height:100px">
<div style="float:right">
<img src="/images/plugins/Kaptive/logo.png" style="height:100px;margin:0 2em" />
</div>
<p>Kaptive reports information about surface polysaccharide loci for <i>Klebsiella pneumoniae</i> species complex and 
<i>Acinetobacter baumannii</i> genome assemblies.</p>
<p>Kaptive is described in Stanton TD, Hetland MAK, L&ouml;hr IH, Holt KE, Wyres KL. Fast and Accurate in silico 
Antigen Typing with Kaptive 3. 
<a target="_blank" href="https://doi.org/10.1101/2025.02.05.636613">bioRxiv 2025.02.05.636613</a>.</p>
</div>

HTML
	return;
}

sub _get_kaptive_version {
	my ($self)  = @_;
	my $command = "$self->{'config'}->{'kaptive_path'} --version";
	my $version = `$command`;
	chomp $version;
	return $version;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	$self->{'exit'} = 0;
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1 } ) x 3;
	my $isolate_ids = $self->{'jobManager'}->get_job_isolates($job_id);
	my $job         = $self->{'jobManager'}->get_job($job_id);
	my $html        = q();
	my $i           = 0;
	my $progress    = 0;
	my $td          = 1;

	my $version    = $self->_get_kaptive_version;
	my @dbs        = split /\s*,\s*/x, $self->{'system'}->{'kaptive_dbs'};
	my $labelfield = ucfirst( $self->{'system'}->{'labelfield'} );
	my $db_names   = DB_NAMES;

	foreach my $isolate_id (@$isolate_ids) {
		my $isolate_data = {};
		$progress = int( $i / @$isolate_ids * 100 );
		$i++;
		my $message = "Scanning isolate $i - id:$isolate_id";
		$self->{'jobManager'}->update_job_status( $job_id, { stage => $message } );
		my $assembly_file = $self->_make_assembly_file( $job_id, $isolate_id );
		my $output_num    = 11;

		foreach my $db (@dbs) {
			my $tsv_file = "$self->{'config'}->{'tmp_dir'}/${job_id}_$db.txt";
			my $temp_out = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}/temp_${isolate_id}_$db.tsv";
			my $cmd      = "$self->{'config'}->{'kaptive_path'} assembly $db $assembly_file --out $temp_out "
			  . "--plot $self->{'config'}->{'secure_tmp_dir'}/$job_id --plot-fmt svg 2> /dev/null";

			system($cmd);
			if ( -e $temp_out ) {
				my $data = $self->_tsv2arrayref($temp_out);
				if ( ref $data eq 'ARRAY' ) {
					if ( @$data == 1 ) {
						$isolate_data->{$db}->{'fields'} = $data->[0];
						delete $isolate_data->{$db}->{'Assembly'};
					} elsif ( @$data > 1 ) {
						$logger->error("Multiple rows reported for id-$isolate_id $db - This is unexpected.");
					}
				}
				open( my $fh_in, '<:encoding(utf8)', $temp_out )
				  || $logger->error("Cannot open $temp_out for reading.");
				open( my $fh_out, '>>:encoding(utf8)', $tsv_file )
				  || $logger->error("Cannot open $tsv_file for writing.");
				my $header = <$fh_in>;
				$header =~ s/^Assembly/Id\t$labelfield/x;
				print $fh_out $header if !-s $tsv_file;
				my $name = $self->{'datastore'}
				  ->run_query( "SELECT $self->{'system'}->{'labelfield'} FROM isolates WHERE id=?", $isolate_id );
				my $results_found;

				while ( my $results = <$fh_in> ) {
					$results_found = 1;
					$results =~ s/^${job_id}_$isolate_id/$isolate_id\t$name/x;
					print $fh_out $results;
				}
				if ( !$results_found ) {
					my $col_count    = scalar split /\t/x, $header;
					my $blank_values = "\t-" x ( $col_count - 2 );
					say $fh_out "$isolate_id\t$name$blank_values";
				}
				close $fh_in;
				close $fh_out;
				my $svg_filename = "id-${isolate_id}_kaptive_results.svg";
				my $svg_path     = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}/$svg_filename";
				if ( -e $svg_path ) {
					my $svg_ref = BIGSdb::Utils::slurp($svg_path);
					$isolate_data->{$db}->{'svg'} = $$svg_ref;
					if ( @$isolate_ids == 1 ) {
						move(
							"$self->{'config'}->{'secure_tmp_dir'}/${job_id}/$svg_filename",
							"$self->{'config'}->{'tmp_dir'}/${job_id}_${isolate_id}_${db}.svg"
						);
						$self->{'jobManager'}->update_job_output(
							$job_id,
							{
								filename    => "${job_id}_${isolate_id}_${db}.svg",
								description => "$db_names->{$db} (SVG format)"
							}
						);
						$output_num++;
					}
				}
			}
		}
		$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => $progress } );
		if ( keys %$isolate_data ) {
			$self->_store_results( $isolate_id, $isolate_data );
		}
	}
	$i = 1;

	foreach my $db (@dbs) {
		my $tsv_file = "$self->{'config'}->{'tmp_dir'}/${job_id}_$db.txt";
		if ( -e $tsv_file ) {
			my $id   = sprintf( '%02d', $i );
			my $desc = "${id}_$db_names->{$db} (TSV format)";
			$self->{'jobManager'}
			  ->update_job_output( $job_id, { filename => "${job_id}_$db.txt", description => $desc } );
			my $excel_file = BIGSdb::Utils::text2excel(
				$tsv_file,
				{
					worksheet => 'Kaptive',
					tmp_dir   => $self->{'config'}->{'secure_tmp_dir'},
				}

			);
			$i++;
			if ( -e $excel_file ) {
				$id   = sprintf( '%02d', $i );
				$desc = "${id}_$db_names->{$db} (Excel format)";
				$self->{'jobManager'}->update_job_output( $job_id,
					{ filename => "${job_id}_$db.xlsx", description => $desc, compress => 1 } );
				$i++;
			}
		}
	}
	rmtree("$self->{'config'}->{'secure_tmp_dir'}/$job_id");
	return;
}

sub _store_results {
	my ( $self, $isolate_id, $data ) = @_;
	my %ignore = map { $_ => 1 }
	  qw(strain contig_count N50 largest_contig total_size ambiguous_bases ST Chr_ST gapA infB mdh pgi phoE rpoB tonB);
	my $version = $self->_get_kaptive_version;
	my $json    = encode_json( { version => $version, data => $data } );
	my $att     = $self->get_attributes;
	eval {
		$self->{'db'}
		  ->do( 'DELETE FROM analysis_results WHERE (isolate_id,name)=(?,?)', undef, $isolate_id, $att->{'module'} );
		$self->{'db'}->do( 'INSERT INTO analysis_results (name,isolate_id,results) VALUES (?,?,?)',
			undef, $att->{'module'}, $isolate_id, $json );
		$self->{'db'}->do(
			'INSERT INTO last_run (name,isolate_id) VALUES (?,?) ON '
			  . 'CONFLICT (name,isolate_id) DO UPDATE SET timestamp = now()',
			undef, $att->{'module'}, $isolate_id
		);
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub _tsv2arrayref {
	my ( $self, $tsv_file ) = @_;
	open( my $fh, '<', $tsv_file ) || $logger->error("Could not open '$tsv_file': $!");
	my $tsv    = Text::CSV->new( { sep_char => "\t", binary => 1, auto_diag => 1 } );
	my $header = $tsv->getline($fh);
	$tsv->column_names(@$header);
	my $rows = [];
	while ( my $row = $tsv->getline_hr($fh) ) {
		push @$rows, $row;
	}
	close $fh;
	return $rows;
}

sub _make_assembly_file {
	my ( $self, $job_id, $isolate_id ) = @_;
	my $filename   = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}/id-$isolate_id.fasta";
	my $seqbin_ids = $self->{'datastore'}->run_query( 'SELECT id FROM sequence_bin WHERE isolate_id=?',
		$isolate_id, { fetch => 'col_arrayref', cache => 'make_assembly_file::get_seqbin_list' } );
	my $contigs = $self->{'contigManager'}->get_contigs_by_list($seqbin_ids);
	make_path("$self->{'config'}->{'secure_tmp_dir'}/${job_id}");
	open( my $fh, '>', $filename ) || $logger->error("Cannot open $filename for writing.");
	foreach my $contig_id ( sort { $a <=> $b } keys %$contigs ) {
		say $fh ">$contig_id";
		say $fh $contigs->{$contig_id};
	}
	close $fh;
	return $filename;
}
1;
