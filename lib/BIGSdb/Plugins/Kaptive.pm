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
use List::MoreUtils qw(uniq);

use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_RECORDS => 1000;
use constant VALID_DBS   => (qw(kpsc_k kpsc_o ab_k ab_o));

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
		category        => 'Third party',
		buttontext      => 'Kaptive',
		menutext        => 'Kaptive',
		module          => 'Kaptive',
		version         => '1.0.0',
		dbtype          => 'isolates',
		section         => 'third_party,isolate_info,postquery',
		input           => 'query',
		help            => 'tooltips',
		requires        => 'offline_jobs,Kaptive,seqbin',
		system_flag     => 'Kaptive',
		explicit_enable => 1,

		#		url             => "$self->{'config'}->{'doclink'}/data_analysis/kaptive.html",
		order => 34,
		min   => 1,
		max   => $self->{'system'}->{'kaptive_record_limit'} // $self->{'config'}->{'kaptive_record_limit'}
		  // MAX_RECORDS,
		always_show_in_menu => 1,

		#		image               => '/images/plugins/Kaptive/screenshot.png'
	};
	return $att;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description( { formatted => 1 } );
	return "Kaptive - $desc";
}

sub _check_dbs {
	my ($self) = @_;
	if ( !defined $self->{'system'}->{'Kaptive_dbs'} ) {
		$self->print_bad_status( { message => 'No Kaptive dbs have been specified in database configuration.' } );
		$logger->error( "$self->{'instance'}: Kaptive_dbs have not been set in config.xml - "
			  . 'this should be a comma-separated list containing one or more of: '
			  . 'kpsc_k, kpsc_o, ab_k, and ab_o.' );
		return 1;
	}
	my @dbs   = split( /\s*,\s*/x, $self->{'system'}->{'Kaptive_dbs'} );
	my %valid = map { $_ => 1 } VALID_DBS;
	foreach my $db (@dbs) {
		if ( !$valid{$db} ) {
			$self->print_bad_status(
				{
					message =>
					  'Invalid databases specified in Kaptive configuration. Please contact site administrator.'
				}
			);
			$logger->error("$self->{'instance'}: Kaptive_dbs setting in config.xml contains invalid database: $db");
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
		my @dbs = split /\s*,\s*/x, $self->{'system'}->{'Kaptive_dbs'};
		local $" = q(, );
		my $plural = @dbs == 1 ? q() : q(s);
		say qq(<li>Database$plural: @dbs</li></ul>);
	} else {
		$logger->error('Kaptive version not determined. Check configuration.');
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

	#	$self->_print_options_fieldset;
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
<div class="box" id="resultspanel">
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

	#	my $table_html;
	my $td = 1;

	my $version    = $self->_get_kaptive_version;
	my @dbs        = split /\s*,\s*/x, $self->{'system'}->{'Kaptive_dbs'};
	my $temp_out   = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}_temp.tsv";
	my $labelfield = ucfirst( $self->{'system'}->{'labelfield'} );

	foreach my $isolate_id (@$isolate_ids) {
		$i++;
		$progress = int( $i / @$isolate_ids * 100 );
		my $message = "Scanning isolate $i - id:$isolate_id";
		$self->{'jobManager'}->update_job_status( $job_id, { stage => $message } );
		my $assembly_file = $self->_make_assembly_file( $job_id, $isolate_id );

		foreach my $db (@dbs) {
			my $tsv_file = "$self->{'config'}->{'tmp_dir'}/${job_id}_$db.tsv";
			my $temp_out = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}_temp_${isolate_id}_$db.tsv";
			my $cmd = "$self->{'config'}->{'kaptive_path'} assembly $db $assembly_file --out $temp_out 2> /dev/null";
			system($cmd);
			if ( -e $temp_out ) {
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
				if (!$results_found){
					my $col_count = scalar split/\t/x,$header;
					my $blank_values = "\t-" x ($col_count - 2);
					say $fh_out "$isolate_id\t$name$blank_values";
				}
				close $fh_in;
				close $fh_out;
			}

			#			unlink $temp_out;
			$self->{'jobManager'}->update_job_status(
				$job_id,
				{
			 #				message_html     => qq(<div class="scrollable"><table class="resultstable">$table_html</table></div>),
					percent_complete => $progress
				}
			);
		}

		#		my ( $headers, $results ) = $self->_extract_results($out_file);
		#		my $isolate = $self->get_isolate_name_from_id($isolate_id);
		#		$headers->[0] = $self->{'system'}->{'labelfield'};
		#		$results->[0] = $isolate;
		#		unshift @$headers, 'id';
		#		unshift @$results, $isolate_id;
		#		if ( !$table_html ) {
		#			local $" = q(</th><th>);
		#			$table_html = qq(<tr><th>@$headers</th></tr>\n);
		#			local $" = qq(\t);
		#			my $text_headers = qq(@$headers);
		#			$self->_append_text_file( $text_file, $text_headers );
		#		}
		#		local $" = q(</td><td>);
		#		$table_html .= qq(<tr class="td$td"><td>@$results</td></tr>);
		#		$td = $td == 1 ? 2 : 1;
		#		local $" = qq(\t);
		#		$self->_append_text_file( $text_file, qq(@$results) );
		#		$self->{'jobManager'}->update_job_status(
		#			$job_id,
		#			{
		#				message_html     => qq(<div class="scrollable"><table class="resultstable">$table_html</table></div>),
		#				percent_complete => $progress
		#			}
		#		);
	}
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
1;
