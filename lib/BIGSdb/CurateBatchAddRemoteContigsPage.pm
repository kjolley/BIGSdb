#Written by Keith Jolley
#Copyright (c) 2017, University of Oxford
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
package BIGSdb::CurateBatchAddRemoteContigsPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateBatchAddSeqbinPage);
use BIGSdb::BIGSException;
use BIGSdb::Constants qw(:interface);
use BIGSdb::Offline::ProcessRemoteContigs;
use Error qw(:try);
use LWP::Simple;
use JSON;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Add remote contigs</h1>);
	if ( $q->param('check') ) {
		$self->_check;
		return;
	} elsif ( $q->param('upload') ) {
		$self->_upload;
		return;
	} elsif ( $q->param('process') ) {
		$self->_process;
		return;
	}
	$self->_print_interface;
	return;
}

sub _process {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $isolate_id = $q->param('isolate_id');
	if ( !BIGSdb::Utils::is_int($isolate_id) || !$self->isolate_exists($isolate_id) ) {
		say q(<div class="box" id="statusbad"><p>Isolate does not exist.</p></div>);
		$self->_print_interface;
		return;
	}
	my $results_prefix = BIGSdb::Utils::get_random();
	my $results_file   = "$self->{'config'}->{'tmp_dir'}/${results_prefix}.txt";
	my $status_file    = "$self->{'config'}->{'tmp_dir'}/${results_prefix}_status.json";
	say $self->_get_polling_javascript($results_prefix);
	say q(<div id="error"></div>);
	say q(<div class="box" id="resultspanel">);
	say q(<div id="wait"><span class="main_icon fa fa-refresh fa-spin fa-4x" style="margin-right:0.5em"></span>)
	  . q(<span class="wait_message">Processing - Please wait.</span></div>)
	  . q(<noscript><div class="box statusbad"><p>Please enable Javascript in your browser</p></div></noscript>);
	say q(<h2 id="title">Processing contigs</h2>);
	say q(<div id="results"></div>);
	say q(<div id="nav" style="display:none">);
	$self->_print_nav_link;
	say q(</div></div>);
	my $prefix      = BIGSdb::Utils::get_random();
	my $output_file = "$self->{'config'}->{'tmp_dir'}/$prefix.txt";
	$self->_run_forked_contig_processor( $results_prefix, $isolate_id );
	return;
}

sub _run_forked_contig_processor {
	my ( $self, $results_prefix, $isolate_id ) = @_;
	my $results_file = "$self->{'config'}->{'tmp_dir'}/${results_prefix}.txt";
	my $status_file  = "$self->{'config'}->{'tmp_dir'}/${results_prefix}_status.json";

	#Use double fork to prevent zombie processes on apache2-mpm-worker
	defined( my $kid = fork ) or $logger->error('cannot fork');
	if ($kid) {
		waitpid( $kid, 0 );
	} else {
		defined( my $grandkid = fork ) || $logger->error('Kid cannot fork');
		if ($grandkid) {
			CORE::exit(0);
		} else {
			open STDIN,  '<', '/dev/null' || $logger->error("Cannot detach STDIN: $!");
			open STDOUT, '>', '/dev/null' || $logger->error("Cannot detach STDOUT: $!");
			open STDERR, '>&STDOUT' || $logger->error("Cannot detach STDERR: $!");
			my $processor = BIGSdb::Offline::ProcessRemoteContigs->new(
				{
					config_dir       => $self->{'config_dir'},
					lib_dir          => $self->{'lib_dir'},
					dbase_config_dir => $self->{'dbase_config_dir'},
					host             => $self->{'system'}->{'host'},
					port             => $self->{'system'}->{'port'},
					user             => $self->{'system'}->{'user'},
					password         => $self->{'system'}->{'password'},
					options          => {
						always_run  => 1,
						output_html => $results_file,
						status_file => $status_file,
						i           => $isolate_id
					},
					instance => $self->{'instance'},
					logger   => $logger
				}
			);
		}
		CORE::exit(0);
	}
	return;
}

sub _get_polling_javascript {
	my ( $self, $results_prefix ) = @_;
	my $status_file   = "/tmp/${results_prefix}_status.json";
	my $results_file  = "/tmp/${results_prefix}.txt";
	my $max_poll_time = 5_000;
	my $buffer        = << "END";
<script type="text/Javascript">//<![CDATA[
\$(function () {	
	getResults(500);
});

function getResults(poll_time) {
	\$.ajax({
		url: "$status_file",
		dataType: 'json',
		cache: false,
		error: function(data){
			\$("div#error").html('<div class="box" id="statusbad"><p>Something went wrong!</p></div>');
			finishProcessing();
		},		
		success: function(data){
			if (data.status == 'complete'){	
				\$("div#results").load("$results_file");
				finishProcessing();
			} else if (data.status == 'failed'){
				\$("div#error").html('<div class="box statusbad"><p>Contig processing failed!</p></div>');
				finishProcessing();
			} else if (data.status == 'running'){
				// Wait and poll again - increase poll time by 0.5s each time.
				poll_time += 500;
				if (poll_time > $max_poll_time){
					poll_time = $max_poll_time;
				}
				setTimeout(function() { 
           	        getResults(poll_time); 
                }, poll_time);
                \$("div#results").load("$results_file");
 			} else {
				\$("div#results").html();
			}
		}
	});
}

function finishProcessing(){
	\$("h2#title").text('Processed contigs');
	\$("div#wait").html('');
	\$("div#nav").css('display','block');
}
//]]></script>
END
	return $buffer;
}

sub _upload {
	my ($self)       = @_;
	my $q            = $self->{'cgi'};
	my $contigs_list = $q->param('contigs_list');
	if ( !$contigs_list ) {
		say q(<div class="box" id="statusbad"><p>No contigs list passed.</p></div>);
		return;
	}
	my $data;
	my $error;
	my $all_records;
	do {
		try {
			$data = $self->{'contigManager'}->get_remote_contig_list($contigs_list);
		}
		catch BIGSdb::AuthenticationException with {
			say q(<div class="box" id="statusbad"><p>OAuth authentication failed.</p></div>);
			$error = 1;
		}
		catch BIGSdb::FileException with {
			say q(<div class="box" id="statusbad"><p>URI is inaccessible.</p></div>);
			$error = 1;
		}
		catch BIGSdb::DataException with {
			say q(<div class="box" id="statusbad"><p>Contigs list is not valid JSON.</p></div>);
			$error = 1;
		};
		if ( $data->{'paging'} ) {
			$contigs_list = $data->{'paging'}->{'return_all'};
		} else {
			$all_records = 1;
		}
	} until ( $error || $all_records );
	my $contigs = $data->{'contigs'};
	if ( ref $contigs ne 'ARRAY' || !@$contigs ) {
		say q(<div class="box" id="statusbad"><p>No contigs found.</p></div>);
		return;
	}
	my $isolate_id = $q->param('isolate_id');
	if ( !BIGSdb::Utils::is_int($isolate_id) || !$self->isolate_exists($isolate_id) ) {
		say q(<div class="box" id="statusbad"><p>You do not have permission to modify this isolate.</p></div>);
		$self->_print_interface;
		return;
	}
	my $curator_id = $self->get_curator_id;
	my $existing =
	  $self->{'datastore'}->run_query(
		'SELECT r.uri FROM remote_contigs r INNER JOIN sequence_bin s ON r.seqbin_id=s.id AND s.isolate_id=?',
		$isolate_id, { fetch => 'col_arrayref' } );
	my %existing = map { $_ => 1 } @$existing;
	eval {
		foreach my $contig (@$contigs) {
			next if $existing{$contig};    #Don't add duplicates
			$self->{'db'}
			  ->do( 'SELECT add_remote_contig(?,?,?,?)', undef, $isolate_id, $curator_id, $curator_id, $contig );
		}
	};
	if ($@) {
		$logger->error($@);
		say q(<div class="box" id="statusbad"><p>Contig upload failed.</p></div>);
		$self->{'db'}->rollback;
		return;
	}
	$self->{'db'}->commit;
	$self->{'contigManager'}->update_isolate_remote_contig_lengths($isolate_id);
	my $count = @$contigs;
	my $plural = $count == 1 ? q() : q(s);
	say qq(<div class="box" id="resultsheader"><p>$count remote contig$plural added.</p></div>);
	say q(<div class="box" id="queryform">);
	say q(<p>Please note that so far only links to the contig records have been added to the database. )
	  . q(The contigs themselves have not been downloaded and checked. Processing records the length of )
	  . q(each contig and stores a checksum within the database so that it is possible to tell if the )
	  . q(sequence ever changes. You can either do this now or it can be performed offline by a scheduled task.</p>);
	my $seqbin = $self->{'datastore'}->run_query(
		'SELECT * FROM seqbin_stats WHERE isolate_id=? AND isolate_id IN '
		  . "(SELECT id FROM $self->{'system'}->{'view'})",
		$isolate_id,
		{ fetch => 'row_hashref' }
	);
	my $remote_contigs = $self->{'datastore'}
	  ->run_query( 'SELECT COUNT(*) FROM sequence_bin WHERE isolate_id=? AND remote_contig', $isolate_id );
	my $unprocessed = $self->{'datastore'}->run_query(
		'SELECT COUNT(*) FROM remote_contigs r INNER JOIN sequence_bin s ON '
		  . 'r.seqbin_id=s.id AND r.checksum IS NULL AND s.isolate_id=?',
		$isolate_id
	);
	my $length = BIGSdb::Utils::commify( $seqbin->{'total_length'} );
	say qq(<dl class="data"><dt>Total contigs</dt><dd>$seqbin->{'contigs'}</dd>);
	say qq(<dt>Remote contigs</dt><dd>$remote_contigs ($unprocessed unprocessed)</dd>)
	  . qq(<dt>Total length</dt><dd>$length</dd></dl>);
	if ($unprocessed) {
		say $q->start_form;
		$self->print_action_fieldset( { no_reset => 1, submit_label => 'Process contigs now' } );
		$q->param( process => 1 );
		say $q->hidden($_) foreach qw(db page contigs_list isolate_id process);
		say $q->end_form;
	}
	$self->_print_nav_link;
	say q(</div>);
	return;
}

sub _check {
	my ($self)      = @_;
	my $q           = $self->{'cgi'};
	my $isolate_id  = $q->param('isolate_id');
	my $isolate_uri = $q->param('isolate_uri');
	my $contigs_list;
	if ( !$isolate_id && !$isolate_uri ) {
		$self->_print_interface;
		return;
	}
	my $error;
	if ( !$isolate_id ) {
		$error = 'Please select isolate.';
	} elsif ( !BIGSdb::Utils::is_int($isolate_id) || !$self->isolate_exists($isolate_id) ) {
		$error = 'Isolate does not exist.';
	}
	$error = 'Please enter URI for isolate record.' if !$isolate_uri;
	if ($error) {
		say qq(<div class="box" id="statusbad"><p>$error</p></div>);
		$self->_print_interface;
		return;
	}
	$self->print_seqbin_warnings( $q->param('isolate_id') );
	say q(<div class="box resultspanel">);
	say q(<h2>Checking contigs</h2>);
	say q(<p>Downloading isolate record ...);
	my $isolate_data;
	try {
		$isolate_data = $self->{'contigManager'}->get_remote_isolate($isolate_uri);
	}
	catch BIGSdb::AuthenticationException with {
		say q(failed! - check OAuth authentication settings</p>);
		$error = 1;
	}
	catch BIGSdb::FileException with {
		say q(failed! - URI is inaccesible</p>);
		$error = 1;
	}
	catch BIGSdb::DataException with {
		say q(failed! - Returned data is not in valid format</p>);
		$error = 1;
	};
	if ($error) {
		$self->_print_nav_link;
	} else {
		say q(done.</p>);
		if ($@) {
			say q(<p class="statusbad">Isolate record is not valid.</p></div>);
			return;
		}
		if ( ref $isolate_data ne 'HASH' || !$isolate_data->{'sequence_bin'} ) {
			say q(<p class="statusbad">No contigs found.</p>);
			$self->_print_nav_link;
		} else {
			my $contig_count = $isolate_data->{'sequence_bin'}->{'contig_count'};
			my $length       = BIGSdb::Utils::commify( $isolate_data->{'sequence_bin'}->{'total_length'} );
			say qq(<dl class="data"><dt>Contigs</dt><dd>$contig_count</dd>);
			say qq(<dt>Total length</dt><dd>$length bp</dd></dl>);
			$contigs_list = $isolate_data->{'sequence_bin'}->{'contigs'};
			say $q->start_form;
			$self->print_action_fieldset( { no_reset => 1, submit_label => 'Upload' } );
			$q->param( contigs_list => $contigs_list );
			$q->param( upload       => 1 );
			say $q->hidden($_) foreach qw(db page isolate_id contigs_list upload);
			say $q->end_form;
		}
	}
	say q(</div>);
	return;
}

sub _print_nav_link {
	my ($self) = @_;
	my $back = BACK;
	say qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddRemoteContigs")
	  . qq( title="Return to batch add remote contigs" style="margin-right:1em">$back</a>);
	$self->print_home_link;
	return;
}

sub _print_interface {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box queryform"><div class="scrollable">);
	say q(<p>This page allows you to link contigs stored in a remote BIGSdb database to an isolate record. Access )
	  . q(to these contigs is via the BIGSdb RESTful API which must be running on the remote database.</p>);
	say q(<p>Valid URIs are in the form 'http://rest.pubmlst.org/db/{database_config}/isolates/{isolate_id}'.)
	  . q(</p>);
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Enter details</legend>);
	say q(<ul><li><label for="isolate_id" class="parameter">isolate id: !</label>);
	my $id_arrayref =
	  $self->{'datastore'}
	  ->run_query( "SELECT id,$self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} ORDER BY id",
		undef, { fetch => 'all_arrayref' } );
	my @ids = (0);
	my %labels;
	$labels{'0'} = 'Select isolate...';

	if ( @$id_arrayref <= 1000 ) {
		foreach (@$id_arrayref) {
			push @ids, $_->[0];
			$labels{ $_->[0] } = "$_->[0]) $_->[1]";
		}
		say $q->popup_menu( -name => 'isolate_id', -id => 'isolate_id', -values => \@ids, -labels => \%labels );
	} else {
		say $q->textfield( -name => 'isolate_id', -id => 'isolate_id', -size => 6 );
	}
	say q(</li><li>);
	say q(<label for="contig_uri" class="parameter">isolate record URI: !</label>);
	say $q->textfield( -name => 'isolate_uri', -id => 'contig_url', -size => 80 );
	say q(</li></ul>);
	say q(</fieldset>);
	$self->print_action_fieldset;
	$q->param( check => 1 );
	say $q->hidden($_) foreach qw(db page check);
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Add remote contigs - $desc";
}
1;
