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
use constant MAX_ISOLATES => 1000;
use constant URL          => 'http://rest.pubmlst.org/db/pubmlst_rmlst_seqdef_kiosk/schemes/1/sequence';

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
		my $error;
		if (@$invalid_ids) {
			local $" = ', ';
			$error =
			    q(<p>The following isolates in your pasted list are invalid - they either do not exist or )
			  . qq(do not have sequence data available: @$invalid_ids.</p>);
			if (@ids) {
				$error .= q(<p>These will be removed from the analysis.</p>);
				say qq(<div class="box statusbad">$error</div>);
			} else {
				$error.= q(<p>There are no valid ids in your selection to analyse.<p>);
				say qq(<div class="box statusbad">$error</div>);
				$self->_print_interface;
				return;
			}
		}
		#TODO Add list of invalid ids to job output.
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
	my $i           = 0;
	my $progress    = 0;
	foreach my $isolate_id (@$isolate_ids) {
		$progress = int( $i / @$isolate_ids * 100 );
		$i++;
		$self->{'jobManager'}
		  ->update_job_status( $job_id, { stage => "Scanning isolate $i", percent_complete => $progress } );
		$self->_perform_rest_query($isolate_id);
		last if $self->{'exit'};
	}
	return;
}

sub _perform_rest_query {
	my ( $self, $isolate_id ) = @_;
	my $seqbin_ids = $self->{'datastore'}->run_query( 'SELECT id FROM sequence_bin WHERE isolate_id=? ORDER BY id',
		$isolate_id, { fetch => 'col_arrayref', cache => 'RMLSTSpecies::get_seqbin_ids' } );
	my $fasta;
	foreach my $seqbin_id (@$seqbin_ids) {
		my $seq_ref = $self->{'contigManager'}->get_contig($seqbin_id);
		$fasta .= qq(>$seqbin_id\n$$seq_ref\n);
	}
	my $agent = LWP::UserAgent->new( agent => 'BIGSdb' );

	#TODO Check for server busy message - if it is then wait, increase wait time each iteration
	my $payload = encode_json(
		{
			base64   => 1,
			details  => 1,
			sequence => encode_base64($fasta)
		}
	);
	my $response = $agent->post(
		URL,
		Content_Type => 'application/json; charset=UTF-8',
		Content      => $payload
	);
	if ( $response->is_success ) {
		my $data = decode_json( $response->content );
		use Data::Dumper;
		$logger->error( Dumper $data);
	} else {
		$logger->error( $response->as_string );
	}
	return;
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
