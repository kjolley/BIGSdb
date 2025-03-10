#Kleborate.pm - Kleborate wrapper for BIGSdb
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
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See thef
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
package BIGSdb::Plugins::Kleborate;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use List::MoreUtils qw(uniq);
use JSON;
use File::Path qw(rmtree);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_RECORDS => 1000;

sub get_attributes {
	my ($self) = @_;
	my $att = {
		name    => 'Kleborate',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			}
		],
		description      => 'Wrapper for Kleborate',
		full_description => 'Kleborate is a tool to screen genome assemblies of <i>Klebsiella pneumoniae</i> and the '
		  . '<i>Klebsiella pneumoniae</i> species complex (KpSC) for: MLST; species; ICE<i>Kp</i> associated virulence '
		  . 'loci; virulence plasmid associated loci; antimicrobial resistance determinants; and K (capsule) and O '
		  . 'antigen (LPS) serotype prediction (<a href="https://pubmed.ncbi.nlm.nih.gov/34234121/">'
		  . 'Lam <i>et al.</i> 2021 <i>Nat Commun</i> <b>12:</b>4188</a>).',
		category        => 'Third party',
		buttontext      => 'Kleborate',
		menutext        => 'Kleborate',
		module          => 'Kleborate',
		version         => '1.1.0',
		dbtype          => 'isolates',
		section         => 'third_party,isolate_info,postquery',
		input           => 'query',
		help            => 'tooltips',
		requires        => 'offline_jobs,Kleborate,seqbin',
		system_flag     => 'Kleborate',
		explicit_enable => 1,
		url             => "$self->{'config'}->{'doclink'}/data_analysis/kleborate.html",
		order           => 36,
		min             => 1,
		max => $self->{'system'}->{'kleborate_record_limit'} // $self->{'config'}->{'kleborate_record_limit'}
		  // MAX_RECORDS,
		always_show_in_menu => 1,
		image               => '/images/plugins/Kleborate/screenshot.png'
	};
	return $att;
}

sub run {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $title  = $self->get_title;
	say qq(<h1>$title</h1>);
	if ( $q->param('submit') ) {
		if ( defined $q->param('method') ) {
			my $guid = $self->get_guid;
			eval {
				$self->{'prefstore'}->set_plugin_attribute( $guid, $self->{'system'}->{'db'},
					'Kleborate', 'method', scalar $q->param('method') );
			};
		}
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
		if ( @ids > MAX_RECORDS ) {
			my $count  = BIGSdb::Utils::commify( scalar @ids );
			my $max    = BIGSdb::Utils::commify(MAX_RECORDS);
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
	my $html        = q();
	my $i           = 0;
	my $progress    = 0;
	my $text_file   = "$self->{'config'}->{'tmp_dir'}/$job_id.txt";

	my $table_html;
	my $td = 1;

	if ( !-x "$self->{'config'}->{'kleborate_path'}" ) {
		$logger->error("Kleborate not executable: Path is $self->{'config'}->{'kleborate_path'}");
		return;
	}
	my $major_version = $self->_get_kleborate_major_version;

	foreach my $isolate_id (@$isolate_ids) {
		$i++;
		$progress = int( $i / @$isolate_ids * 100 );
		my $message = "Scanning isolate $i - id:$isolate_id";
		$self->{'jobManager'}->update_job_status( $job_id, { stage => $message } );
		my $assembly_file = $self->_make_assembly_file( $job_id, $isolate_id );
		my $cmd;
		my $out_file;
		if ( $major_version == 2 ) {
			$out_file = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}_kleborate.txt";
			my $method = $params->{'method'} ne 'basic' ? " --$params->{'method'}" : q();
			$cmd = "$self->{'config'}->{'kleborate_path'}$method -o $out_file -a $assembly_file > /dev/null";
		} else {
			my %allowed_presets = map { $_ => 1 } qw(kpsc kosc escherichia);
			my $preset          = $self->{'system'}->{'kleborate_preset'} // 'kpsc';
			if ( !$allowed_presets{$preset} ) {
				$logger->error(q('Invalid Kleborate preset option - using 'kpsc'.));
				$preset = 'kpsc';
			}
			local $ENV{'MPLCONFIGDIR'} = $self->{'config'}->{'secure_tmp_dir'};
			my $dir = "$self->{'config'}->{'secure_tmp_dir'}/$job_id";
			mkdir $dir;
			$cmd =
			  "$self->{'config'}->{'kleborate_path'} -o $dir -a $assembly_file -p $preset --trim_headers > /dev/null";
			my %out_files = (
				kpsc        => "$dir/klebsiella_pneumo_complex_output.txt",
				kosc        => "$dir/klebsiella_oxytoca_complex_output.txt",
				escherichia => "$dir/escherichia_output.txt"
			);
			$out_file = $out_files{$preset};
		}

		my $exit_code = system($cmd);
		if ( !-e $out_file ) {
			$logger->error('Kleborate did not produce an output file.');
			return;
		}
		my ( $headers, $results ) = $self->_extract_results($out_file);
		my $isolate = $self->get_isolate_name_from_id($isolate_id);
		$headers->[0] = $self->{'system'}->{'labelfield'};
		$results->[0] = $isolate;
		unshift @$headers, 'id';
		unshift @$results, $isolate_id;
		if ( !$table_html ) {
			local $" = q(</th><th>);
			$table_html = qq(<tr><th>@$headers</th></tr>\n);
			local $" = qq(\t);
			my $text_headers = qq(@$headers);
			$self->_append_text_file( $text_file, $text_headers );
		}
		local $" = q(</td><td>);
		$table_html .= qq(<tr class="td$td"><td>@$results</td></tr>);
		$td = $td == 1 ? 2 : 1;
		local $" = qq(\t);
		$self->_append_text_file( $text_file, qq(@$results) );
		$self->{'jobManager'}->update_job_status(
			$job_id,
			{
				message_html     => qq(<div class="scrollable"><table class="resultstable">$table_html</table></div>),
				percent_complete => $progress
			}
		);
		$self->_store_results( $isolate_id, $out_file ) if $major_version > 2 || $params->{'method'} eq 'all';

		if ( $major_version == 2 ) {
			$self->delete_temp_files("$job_id*");
			unlink $out_file;
		} else {
			unlink $assembly_file;
			rmtree "$self->{'config'}->{'secure_tmp_dir'}/$job_id";
		}

		last if $self->{'exit'};
	}
	if ( -e $text_file ) {
		$self->{'jobManager'}
		  ->update_job_output( $job_id, { filename => "$job_id.txt", description => '01_Results (Text format)' } );
		my $excel_file = BIGSdb::Utils::text2excel(
			$text_file,
			{
				worksheet => 'Kleborate',
				tmp_dir   => $self->{'config'}->{'secure_tmp_dir'},
			}
		);
		if ( -e $excel_file ) {
			$self->{'jobManager'}->update_job_output( $job_id,
				{ filename => "$job_id.xlsx", description => '02_Results (Excel)', compress => 1 } );
		}
	}
	return;
}

sub _extract_results {
	my ( $self, $filename ) = @_;
	open( my $fh, '<', $filename ) || $logger->error("Cannot open $filename for reading");
	my $header_line = <$fh>;
	chomp $header_line;
	my $results_line = <$fh>;
	chomp $results_line;
	close $fh;
	my $headers = [ split /\t/x, $header_line ];
	my $results = [ split /\t/x, $results_line ];
	return ( $headers, $results );
}

sub _append_text_file {
	my ( $self, $file_path, $line ) = @_;
	open( my $fh, '>>:encoding(utf8)', $file_path ) || $logger->error("Cannot open $file_path for writing.");
	say $fh $line;
	close $fh;
	return;
}

sub _make_assembly_file {
	my ( $self, $job_id, $isolate_id ) = @_;
	my $filename   = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}_$isolate_id.fasta";
	my $seqbin_ids = $self->{'datastore'}->run_query( 'SELECT id FROM sequence_bin WHERE isolate_id=?',
		$isolate_id, { fetch => 'col_arrayref', cache => 'make_assembly_file::get_seqbin_list' } );
	my $contigs = $self->{'contigManager'}->get_contigs_by_list($seqbin_ids);
	open( my $fh, '>', $filename ) || $logger->error("Cannot open $filename for writing.");
	foreach my $contig_id ( sort { $a <=> $b } keys %$contigs ) {
		say $fh ">$contig_id";
		say $fh $contigs->{$contig_id};
	}
	close $fh;
	return $filename;
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
	my $version = $self->_get_kleborate_version;
	say q(<div class="box" id="queryform"><p>This tool will run Kleborate against selected genome assembles )
	  . q(and produce the results in tabular form.</p>);
	if ($version) {
		say qq(<p>Version: $version</p>);
	}
	if ( !$q->param('single_isolate') ) {
		say q(<p>Please select the required isolate ids to run the analysis for. )
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
	$self->_print_options_fieldset;
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach qw (page name db);
	say q(</div>);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _get_kleborate_version {
	my ($self) = @_;
	return if !-e $self->{'config'}->{'kleborate_path'} || !-x $self->{'config'}->{'kleborate_path'};
	my $out = "$self->{'config'}->{'secure_tmp_dir'}/kleborate_$$";
	local $ENV{'TERM'}         = 'dumb';
	local $ENV{'MPLCONFIGDIR'} = $self->{'config'}->{'secure_tmp_dir'};
	my $version     = system("$self->{'config'}->{'kleborate_path'} --version > $out");
	my $version_ref = BIGSdb::Utils::slurp($out);
	unlink $out;
	return $$version_ref;
}

sub _get_kleborate_major_version {
	my ($self) = @_;
	my $version = $self->_get_kleborate_version;
	my $major_version;
	if ( $version =~ /^Kleborate\s+v(\d+)\./x ) {
		$major_version = $1;
	} else {
		$logger->error('Unknown Kleborate version');
		$major_version = 2;
	}
	return $major_version;
}

sub _print_options_fieldset {
	my ($self) = @_;
	my $major_version = $self->_get_kleborate_major_version;
	return if $major_version > 2;
	my $default_method;
	my $guid = $self->get_guid;
	eval {
		if ($guid) {
			$default_method =
			  $self->{'prefstore'}->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'Kleborate', 'method' );
		}
	};
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:left"><legend>Options</legend>);
	say q(<p>Choose method - note that running --all will be slower.</p>);
	say $q->radio_group(
		-name   => 'method',
		-values => [qw(basic resistance all)],
		-labels => {
			basic      => 'Basic screening for species, MLST and virulence loci',
			resistance => 'As above and turn on screening for resistance genes (--resistance)',
			all        => 'As above and turn on screening for K & O antigen loci (--all)'
		},
		-linebreak => 'true',
		-default   => $default_method // 'basic'
	);
	say q(</fieldset>);
	return;
}

sub _store_results {
	my ( $self, $isolate_id, $output_file ) = @_;
	my $cleaned_results = [];
	my ( $headers, $results ) = $self->_extract_results($output_file);
	if ( !@$headers || !@$results ) {
		$logger->error("No valid results for id-$isolate_id");
		return;
	}
	my %ignore = map { $_ => 1 }
	  qw(strain contig_count N50 largest_contig total_size ambiguous_bases ST Chr_ST gapA infB mdh pgi phoE rpoB tonB);
	for my $i ( 0 .. @$headers - 1 ) {
		next if $ignore{ $headers->[$i] };
		next if !defined $results->[$i] || $results->[$i] eq '-' || $results->[$i] eq '';
		push @$cleaned_results,
		  { $headers->[$i] => BIGSdb::Utils::is_int( $results->[$i] ) ? int( $results->[$i] ) : $results->[$i] };
	}
	my $att     = $self->get_attributes;
	my $version = $self->_get_kleborate_version;
	chomp $version;
	my $json = encode_json( { version => $version, fields => $cleaned_results } );
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

sub _print_info_panel {
	my ($self) = @_;
	say << "HTML";
<div class="box" id="resultspanel">
<div style="float:right">
<img src="/images/plugins/Kleborate/logo.png" style="height:100px;margin:0 2em" />
</div>
<p>Kleborate is a tool to screen genome assemblies of <i>Klebsiella pneumoniae</i> and the <i>Klebsiella pneumoniae</i>
species complex (KpSC) for:</p>
<ul>
<li>MLST sequence type</li>
<li>species (e.g. <i>K. pneumoniae</i>, <i>K. quasipneumoniae</i>, <i>K. variicola</i>, etc.)</li>
<li>ICE<i>Kp</i> associated virulence loci: yersiniabactin (<i>ybt</i>), colibactin (<i>clb</i>), salmochelin 
(<i>iro</i>), hypermucoidy (<i>rmpA</i>)
<li>virulence plasmid associated loci: salmochelin (<i>iro</i>), aerobactin (<i>iuc</i>), hypermucoidy (<i>rmpA</i>, 
<i>rmpA2</i>)</li>
<li>antimicrobial resistance determinants: acquired genes, SNPs, gene truncations and intrinsic &beta;-lactamases</li>
<li>K (capsule) and O antigen (LPS) serotype prediction, via <i>wzi</i> alleles and Kaptive</li>
</ul>
<p>Kleborate and Kaptive are described in <a href="https://pubmed.ncbi.nlm.nih.gov/34234121/">
Lam <i>et al.</i> 2021 <i>Nat Commun</i> <b>12:</b>4188</a> and <a href="https://pubmed.ncbi.nlm.nih.gov/35311639/">
Lam <i>et al.</i> 2022 <i>Microb Genom</i> <b>8:</b>000800</a> respectively.</p>
</div>

HTML
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description( { formatted => 1 } );
	return "Kleborate - $desc";
}
1;
