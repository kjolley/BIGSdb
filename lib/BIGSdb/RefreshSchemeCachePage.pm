#Written by Keith Jolley
#Copyright (c) 2015-2023, University of Oxford
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
package BIGSdb::RefreshSchemeCachePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use JSON;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	return 'Refresh scheme caches';
}

sub _print_interface {
	my ( $self, $schemes ) = @_;
	my $q      = $self->{'cgi'};
	my $set_id = $self->get_set_id;
	my %desc;
	foreach my $scheme_id (@$schemes) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
		$desc{$scheme_id} = "$scheme_id) $scheme_info->{'name'}";
	}
	say q(<div class="box" id="queryform">);
	say q(<p>The scheme caches contain scheme fields, e.g. MLST ST values, within the isolate database, removing the )
	  . q(requirement to determine these in real time.  This can significantly speed up querying and data export, but )
	  . q(the cache can become stale if there are changes to either the isolate or sequence definition database after )
	  . q(it was last updated.</p>);
	say q(<p>The following options are available:</p>);
	say q(<ul><li>full - delete and re-create whole cache.</li>);
	say q(<li>incremental - check and add cache values for records which currently lack values. You will also have )
	  . q(the option to update the cache only for recently modified records.</li>);
	say q(<li>daily - add cache values for records that currently lack scheme values and were added today.</li>);
	say q(<li>daily_replace - delete and re-create cache values for records that were added today.</li>);
	say q(<li>completion_metrics - only update the completion metrics.</li></ul>);

	if ( $self->{'system'}->{'cache_schemes'} ) {
		say q(<p>This database is also set to automatically refresh scheme caches when isolates are added using the )
		  . q(batch add page.</p>);
	}
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Select scheme</legend>);
	$desc{0} = 'All schemes';
	say $q->popup_menu( -name => 'scheme', -values => [ 0, @$schemes ], -labels => \%desc );
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Select method</legend>);
	say $q->popup_menu( -name => 'method', -id => 'method', -values => [qw(full incremental daily daily_replace completion_metrics)] );
	say q(</fieldset>);
	say q(<fieldset style="float:left;display:none" id="options"><legend>Options</legend>);
	say q(Refresh records modified in past );
	say $q->textfield( -name => 'reldate', -size => 3 );
	say q( days.<br />);
	say q(<span class="comment">Leave blank to include all records.</span>);
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Refresh cache' } );
	$q->param( job_id => $self->{'job_id'} );
	say $q->hidden($_) foreach qw(db page job_id);
	say $q->end_form;
	say q(</div>);
	return;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (tooltips jQuery noCache);
	$self->set_level1_breadcrumbs;
	my $q = $self->{'cgi'};
	$self->{'job_id'} = $q->param('job_id') // BIGSdb::Utils::get_random();
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( !$q->param('submit') ) {
		my $buffer = << "END";
\$(function () {
	\$("#method").change(function(){
		if (\$("#method").val() === 'incremental'){
			\$("fieldset#options").show();
		} else {
			\$("fieldset#options").hide();
		}
	})
});		
END
		return $buffer;
	}
	my $bookmark =
		"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=refreshCache&amp;"
	  . "job_id=$self->{'job_id'}&amp;submit=1";
	my $buffer = << "END";
var status_file = "/tmp/$self->{'job_id'}.json";
\$(function () {
	\$(':input[type="submit"]').prop('disabled', true);
	\$(':input[type="submit"]').addClass('submit_disabled');
	
	\$("p#message").html('Processing will continue even if you close the page. Use <a href="$bookmark">this '
	+ 'link</a> if you wish to bookmark and return.');
	if (\$("#method").val() === 'incremental'){
		\$("fieldset#options").show();
	}
	\$("#method").change(function(){
		if (\$("#method").val() === 'incremental'){
			\$("fieldset#options").show();
		} else {
			\$("fieldset#options").hide();
		}
	})
	read_status();	
});

function read_status(){
	 var interval = setInterval(function () {
	 	\$.ajax({
			dataType: "json",
			url: status_file,
			success: function(response) {
				if (typeof response['stage'] !== 'undefined'){
					var message = response['stage'];
					if (typeof response['stage_progress'] !== 'undefined'){
						message += " (" + response['stage_progress'] + "% complete)";
					}
					\$("p#results").html(message);
				}
				if (typeof response['stop_time'] !== 'undefined'){
					clearInterval(interval);
					finish();
				}
				if (typeof response['status'] !== 'undefined'){
					if (response['status'] === 'failed'){
						clearInterval(interval);
						finish();
						let msg = 'Failed.'
						if (typeof response['message'] !== 'undefined'){
							msg = response['message'];
						}
						\$("p#results").html(msg);
					}
				}
			},
		});
	 }, 2000);
}

function finish(){
	\$("p#wait").hide();
	\$("p#results").html('Cache renewal finished.');
	\$(':input[type="submit"]').prop('disabled', false);
	\$(':input[type="submit"]').removeClass('submit_disabled');
	\$("p#message").html("");
	\$('input:hidden[name=job_id]').remove();
}
END
	return $buffer;
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $desc   = $self->get_db_description( { formatted => 1 } ) // 'BIGSdb';
	say "<h1>Refresh scheme caches - $desc</h1>";
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		$self->print_bad_status( { message => q(This function is only for use on isolate databases.), navbar => 1 } );
		return;
	}
	if ( !( $self->is_admin || $self->{'permissions'}->{'refresh_scheme_caches'} ) ) {
		$self->print_bad_status( { message => q(You do not have permission to view this page.), navbar => 1 } );
		return;
	}
	my $schemes =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id FROM schemes WHERE dbase_name IS NOT NULL AND dbase_id IS NOT NULL ORDER BY id',
		undef, { fetch => 'col_arrayref' } );
	my @filtered_schemes;
	my $set_id = $self->get_set_id;
	if ($set_id) {
		foreach my $scheme_id (@$schemes) {
			push @filtered_schemes, $scheme_id if $self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id );
		}
	} else {
		@filtered_schemes = @$schemes;
	}
	if ( !@filtered_schemes ) {
		$self->print_bad_status( { message => q(There are no schemes that can be cached.), navbar => 1 } );
		return;
	}
	$self->_print_interface( \@filtered_schemes );
	if ( $q->param('submit') ) {
		$self->_refresh_caches( \@filtered_schemes );
	}
	return;
}

sub _refresh_caches {
	my ( $self, $schemes ) = @_;
	my $q = $self->{'cgi'};
	my $selected_scheme;
	if ( $q->param('scheme') && BIGSdb::Utils::is_int( scalar $q->param('scheme') ) ) {
		$selected_scheme = $q->param('scheme');
	}
	my $method  = $q->param('method');
	my $reldate = $q->param('reldate');
	if ( !$reldate || !BIGSdb::Utils::is_int($reldate) ) {
		undef $reldate;
	}
	my %allowed_methods = map { $_ => 1 } qw(full incremental daily daily_replace completion_metrics);
	if ( !$allowed_methods{$method} ) {
		$method = 'full';
	}
	my $status_file      = "$self->{'job_id'}.json";
	my $status_full_path = "$self->{'config'}->{'tmp_dir'}/$status_file";
	if ( -e $status_full_path ) {    #Page has been refreshed.
		$self->_print_status_divs;
		return;
	}

	#Use double fork to prevent zombie processes on apache2-mpm-worker
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	defined( my $kid = fork ) or $logger->error('cannot fork');
	if ($kid) {
		waitpid( $kid, 0 );
	} else {
		defined( my $grandkid = fork ) or $logger->error('Kid cannot fork');
		if ($grandkid) {
			CORE::exit(0);
		} else {
			open STDIN,  '<', '/dev/null' || $logger->error("Cannot detach STDIN: $!");
			open STDOUT, '>', '/dev/null' || $logger->error("Cannot detach STDOUT: $!");
			open STDERR, '>&STDOUT' || $logger->error("Cannott detach STDERR: $!");
			try {
				BIGSdb::Offline::UpdateSchemeCaches->new(
					{
						config_dir       => $self->{'config_dir'},
						lib_dir          => $self->{'lib_dir'},
						dbase_config_dir => $self->{'dbase_config_dir'},
						options          => {
							mark_job          => 1,
							job_id            => $self->{'job_id'},
							no_user_db_needed => 1,
							ip_address        => $ENV{'REMOTE_ADDR'},
							username          => $self->{'username'},
							email             => $user_info->{'email'},
							method            => $method,
							schemes           => $selected_scheme,
							reldate           => $reldate,
							status_file       => $status_full_path
						},
						instance => $self->{'instance'}
					}
				);
			} catch {
				if ( $_->isa('BIGSdb::Exception::Server::Busy') ) {
					my $json = encode_json(
						{
							server_busy => 1
						}
					);
					open( my $fh, '>', $status_full_path )
					  || $logger->error("Cannot open $status_full_path for writing");
					say $fh $json;
					close $fh;
				} else {
					$logger->logdie($_);
				}
			};
			CORE::exit(0);
		}
	}
	$self->_print_status_divs;
	return;
}

sub _print_status_divs {
	say q(<div class="box" id="resultsheader"><p id="wait">)
	  . q(<span class="wait_icon fas fa-sync-alt fa-spin fa-4x" style="margin-right:0.5em"></span>)
	  . q(<span class="wait_message">Please wait...</span></p>);
	say q(<p id="results" class="progress"></p>);
	say q(<p id="message"</p>);
	say q(</div>);
	return;
}
1;
