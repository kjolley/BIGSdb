#Export.pm - rMLST species identification plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2018, University of Oxford
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
package BIGSdb::Plugins::RMLSTSpecies;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use List::MoreUtils qw(uniq);
use JSON;
use MIME::Base64;
use LWP::UserAgent;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_ISOLATES       => 1000;
use constant INITIAL_BUSY_DELAY => 60;
use constant MAX_DELAY          => 600;
use constant URL                => 'http://rest.pubmlst.org/db/pubmlst_rmlst_seqdef_kiosk/schemes/1/sequence';

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name        => 'rMLST species identity',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Query genomes against rMLST species identifier',
		category    => 'Analysis',
		buttontext  => 'rMLST species id',
		menutext    => 'Species identification',
		module      => 'RMLSTSpecies',
		version     => '1.0.0',
		dbtype      => 'isolates',
		section     => 'info,analysis,postquery',
		input       => 'query',
		help        => 'tooltips',
		system_flag => 'rMLSTSpecies',
		order       => 40,
		priority    => 1
	);
	return \%att;
}

sub run {
	my ($self) = @_;
	my $desc = $self->get_db_description;
	say qq(<h1>rMLST species identification - $desc</h1>);
	my $q = $self->{'cgi'};
	if ( $q->param('submit') ) {
		my @ids = $q->param('isolate_id');
		my ( $pasted_cleaned_ids, $invalid_ids ) =
		  $self->get_ids_from_pasted_list( { dont_clear => 1, has_seqbin => 1 } );
		push @ids, @$pasted_cleaned_ids;
		@ids = uniq @ids;
		my $message_html;
		if (@$invalid_ids) {
			local $" = ', ';
			my $error =
			    q(<p>The following isolates in your pasted list are invalid - they either do not exist or )
			  . qq(do not have sequence data available: @$invalid_ids.);
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
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		$q->delete('isolate_paste_list');
		$q->delete('isolate_id');
		my $params = $q->Vars;
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
	$self->_print_interface;
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	$self->{'exit'} = 0;
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1 } ) x 3;
	my $isolate_ids = $self->{'jobManager'}->get_job_isolates($job_id);
	my $job         = $self->{'jobManager'}->get_job($job_id);
	my $html        = $job->{'message_html'} // q();
	my $i           = 0;
	my $progress    = 0;
	my $table_header =
	    q(<div class="scrollable"><table class="resultstable"><tr><th>id</th>)
	  . qq(<th>$self->{'system'}->{'labelfield'}</th><th>Rank</th><th>Predicted taxon (from alleles)</th>)
	  . q(<th>Taxonomy</th><th>Support</th><th>rST</th><th>Predicted species (from rST)</th></tr>);
	my $td = 1;
	my $row_buffer;

	foreach my $isolate_id (@$isolate_ids) {
		$progress = int( $i / @$isolate_ids * 100 );
		$i++;
		$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => $progress } );
		my $values = $self->_perform_rest_query( $job_id, $i, $isolate_id );
		$row_buffer .= qq(<tr class="td$td">);
		foreach my $value (@$values) {
			if ( ref $value eq 'ARRAY' ) {
				local $" = q(<br />);
				$row_buffer .= qq(<td>@$value</td>);
			} else {
				$value //= q();
				$row_buffer .= qq(<td>$value</td>);
			}
		}
		$row_buffer .= q(</tr>);
		my $message_html = qq($html\n$table_header\n$row_buffer\n</table></div>);
		$self->{'jobManager'}->update_job_status( $job_id, { message_html => $message_html } );
		$td = $td == 1 ? 2 : 1;
		last if $self->{'exit'};
	}
	return;
}

sub _perform_rest_query {
	my ( $self, $job_id, $i, $isolate_id ) = @_;
	my $seqbin_ids = $self->{'datastore'}->run_query( 'SELECT id FROM sequence_bin WHERE isolate_id=? ORDER BY id',
		$isolate_id, { fetch => 'col_arrayref', cache => 'RMLSTSpecies::get_seqbin_ids' } );
	my $fasta;
	foreach my $seqbin_id (@$seqbin_ids) {
		my $seq_ref = $self->{'contigManager'}->get_contig($seqbin_id);
		$fasta .= qq(>$seqbin_id\n$$seq_ref\n);
	}
	my $agent = LWP::UserAgent->new( agent => 'BIGSdb' );
	my $payload = encode_json(
		{
			base64   => JSON::true(),
			details  => JSON::true(),
			sequence => encode_base64($fasta)
		}
	);
	my ( $response, $unavailable );
	my $delay        = INITIAL_BUSY_DELAY;
	my $isolate_name = $self->get_isolate_name_from_id($isolate_id);
	my $values       = [ $isolate_id, $isolate_name ];
	do {
		$self->{'jobManager'}->update_job_status( $job_id, { stage => "Scanning isolate $i" } );
		$unavailable = 0;
		$response    = $agent->post(
			URL,
			Content_Type => 'application/json; charset=UTF-8',
			Content      => $payload
		);
		if ( $response->code == 503 ) {
			$unavailable = 1;
			$self->{'jobManager'}->update_job_status( $job_id,
				{ stage => "rMLST server is unavailable or too busy at the moment - retrying in $delay seconds", } );
			sleep $delay;
			$delay += 10 if $delay < MAX_DELAY;
		}
	} while ($unavailable);
	my $rank     = [];
	my $taxon    = [];
	my $taxonomy = [];
	my $support  = [];
	my ( $rST, $species );
	if ( $response->is_success ) {
		my $data = decode_json( $response->content );
		if ( $data->{'taxon_prediction'} ) {
			foreach my $prediction ( @{ $data->{'taxon_prediction'} } ) {
				push @$rank,     $prediction->{'rank'};
				push @$taxon,    $prediction->{'taxon'};
				push @$taxonomy, $prediction->{'taxonomy'};
				push @$support,  $prediction->{'support'};
			}
		}
		if ( $data->{'fields'} ) {
			$rST = $data->{'fields'}->{'rST'};
			$species = $data->{'fields'}->{'species'} // q();
		}
	} else {
		$logger->error( $response->as_string );
	}
	push @$values, ( $rank, $taxon, $taxonomy, $support, $rST, $species );
	return $values;
}

sub _print_interface {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $qry_ref    = $self->get_query($query_file);
	my $selected_ids;
	my $seqbin_values = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT id FROM sequence_bin)');
	if ( !$seqbin_values ) {
		say q(<div class="box" id="statusbad"><p>There are no sequences in the sequence bin.</p></div>);
		return;
	}
	if ( $q->param('isolate_id') ) {
		my @ids = $q->param('isolate_id');
		$selected_ids = \@ids;
	} elsif ( defined $query_file ) {
		$selected_ids = $self->get_ids_from_query($qry_ref);
	} else {
		$selected_ids = [];
	}
	say q(<div class="box" id="queryform"><p>Please select the required isolate ids to run the species )
	  . q(identification for. These isolate records must include genome sequences.</p>);
	say $q->start_form;
	say q(<div class="scrollable">);
	$self->print_seqbin_isolate_fieldset( { selected_ids => $selected_ids, isolate_paste_list => 1 } );
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach qw (page name db);
	say q(</div>);
	say $q->end_form;
	say q(</div>);
	return;
}
1;
