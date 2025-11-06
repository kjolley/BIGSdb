#PlasmidFinder.pm - PlasmidFinder wrapper for BIGSdb
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
package BIGSdb::Plugins::PlasmidFinder;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use BIGSdb::Exceptions;
use List::MoreUtils qw(uniq);
use JSON;
use File::Copy;
use File::Path    qw(rmtree);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_RECORDS => 100;

sub get_attributes {
	my ($self) = @_;
	my $att = {
		name    => 'PlasmidFinder',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			}
		],
		description      => 'Wrapper for PlasmidFinder',
		full_description => 'PlasmidFinder is an in silico detection and typing tool for plasmids '
		  . '(<a href="https://pubmed.ncbi.nlm.nih.gov/24777092/">'
		  . 'Carattoli <i>et al.</i> 2014 <i>Antimicrob Agents Chemothe</i> <b>58:</b>3895-903</a>).',
		category    => 'Third party',
		buttontext  => 'PlasmidFinder',
		menutext    => 'PlasmidFinder',
		module      => 'PlasmidFinder',
		version     => '1.0.0',
		dbtype      => 'isolates',
		section     => 'third_party,isolate_info,postquery',
		input       => 'query',
		help        => 'tooltips',
		requires    => 'offline_jobs,PlasmidFinder,seqbin',
		system_flag => 'PlasmidFinder',

		#		url             => "$self->{'config'}->{'doclink'}/data_analysis/PlasmidFinder.html",
		order => 50,
		min   => 1,
		max   => $self->{'system'}->{'plasmidfinder_record_limit'} // $self->{'config'}->{'plasmidfinder_record_limit'}
		  // MAX_RECORDS,
		always_show_in_menu => 1,

		#		image               => '/images/plugins/PlasmidFinder/screenshot.png'
	};
	return $att;
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
	my $i           = 0;
	my $progress    = 0;

	my $td = 1;

	if ( !$self->{'config'}->{'plasmidfinder'} ) {
		$logger->error('PlasmidFinder is not enabled.');
		return;
	}
	if ( !$self->{'config'}->{'plasmidfinder_db_path'} ) {
		$logger->error('plasmidfinder_db_path has not been set.');
		return;
	}
	if ( !-e $self->{'config'}->{'plasmidfinder_db_path'} ) {
		$logger->error("plasmidfinder_db_path $self->{'config'}->{'plasmidfinder_db_path'} does not exist.");
		return;
	}

	my $version = $self->_get_version;
	my $tmp_dir = "$self->{'config'}->{'secure_tmp_dir'}/$job_id";
	mkdir $tmp_dir;

	foreach my $isolate_id (@$isolate_ids) {
		$i++;
		$progress = int( $i / @$isolate_ids * 100 );
		my $message = "Scanning isolate $i - id:$isolate_id";
		$self->{'jobManager'}->update_job_status( $job_id, { stage => $message } );
		my $assembly_file_path = $self->make_assembly_file( $job_id, $isolate_id );
		( my $assembly_filename = $assembly_file_path ) =~ s/.+\///x;

		my $error_file = "$tmp_dir/${isolate_id}_error.log";

		move( $assembly_file_path, $tmp_dir );
		my $json_file = "${isolate_id}.json";
		my $cmd =
			qq(docker run -u "\$(id -u):\$(id -g)" --rm -v plasmidfinder_db_path:/database -v ${tmp_dir}:/workdir )
		  . qq(-w /workdir plasmidfinder -i $assembly_filename -o /workdir -j $json_file);
		eval { system(qq($cmd 1>/dev/null 2>$error_file)); };

		my $error_ref = BIGSdb::Utils::slurp($error_file);
		if ( $! || $$error_ref ) {
			$logger->error("$$error_ref Command: $cmd");
			BIGSdb::Exception::Plugin->throw('PlasmidFinder failed.');
		}
		rmtree("$tmp_dir/tmp");
		unlink $assembly_file_path;
		my $json_path = "$tmp_dir/$json_file";

		$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => $progress } );
		if ( @$isolate_ids == 1 ) {
			if ( -e $json_path ) {
				$self->_store_results( $isolate_id, $json_path );
				move( $json_path, "$self->{'config'}->{'tmp_dir'}/$json_file" );
				$self->{'jobManager'}->update_job_output(
					$job_id,
					{
						filename    => $json_file,
						description => 'Output (JSON format)'
					}
				);
			} else {
				my $html = q(<p class="statusbad">No output generated by PlasmidFinder.</p>);
				$self->{'jobManager'}->update_job_status( $job_id, { message_html => $html } );
			}
		} else {
			if ( -e $json_path ) {
				$self->_store_results( $isolate_id, $json_path );
			}
		}
		last if $self->{'exit'};
	}
	rmtree($tmp_dir);
	return;
}

sub _store_results {
	my ( $self, $isolate_id, $json_file ) = @_;
	return if !-e $json_file;
	my $json_ref = BIGSdb::Utils::slurp($json_file);
	my $att      = $self->get_attributes;
	eval {
		$self->{'db'}
		  ->do( 'DELETE FROM analysis_results WHERE (isolate_id,name)=(?,?)', undef, $isolate_id, $att->{'module'} );
		$self->{'db'}->do( 'INSERT INTO analysis_results (name,isolate_id,results) VALUES (?,?,?)',
			undef, $att->{'module'}, $isolate_id, $$json_ref );
		$self->{'db'}->do(
			'INSERT INTO last_run (name,isolate_id) VALUES (?,?) ON '
			  . 'CONFLICT (name,isolate_id) DO UPDATE SET timestamp = now()',
			undef, $att->{'module'}, $isolate_id
		);
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	}
	$self->{'db'}->commit;
	return;
}

sub _print_info_panel {
	my ($self) = @_;
	say << "HTML";
<div class="box" id="resultspanel">
<p>PlasmidFinder is a tool for the identification and typing of plasmid replicons in whole genome sequencing.</p>
<p>PlasmidFinder is described in <a href="https://pubmed.ncbi.nlm.nih.gov/24777092/" target="_blank">
Carattoli <i>et al.</i> 2014 <i>Antimicrob Agents Chemother</i> <b>58:</b>3895-903</a> and 
<a href="https://pubmed.ncbi.nlm.nih.gov/31584170/" target="_blank">
Carattoli <i>et al.</i> 2020 <i>Methods Mol Biol</i> <b>2075:</b>285-294</a>.</p>
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

	say q(<div class="box" id="queryform"><p>This tool will run PlasmidFinder against selected genome assembles )
	  . q(and produce the results in JSON format.</p>);
	if ( !$self->{'config'}->{'plasmidfinder_noweb'} ) {
		my $version = $self->_get_version;
		if ($version) {
			say qq(<p>PlasmidFinder Version: $version</p>);
		}
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
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach qw (page name db);
	say q(</div>);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _get_version {
	my ($self) = @_;
	my $temp_file = "$self->{'config'}->{'secure_tmp_dir'}/${$}_version";
	eval { system("docker run plasmidfinder -v > $temp_file 2>&1 "); };
	my $out = BIGSdb::Utils::slurp($temp_file);
	unlink $temp_file;
	if ( $$out =~ /^\d+\./x ) {
		return $$out;
	}
	$logger->error($$out);
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description( { formatted => 1 } );
	return "PlasmidFinder - $desc";
}

1;
