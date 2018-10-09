#Written by Keith Jolley
#Copyright (c) 2010-2018, University of Oxford
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
package BIGSdb::SequenceQueryPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
use List::MoreUtils qw(any uniq none);
use BIGSdb::BIGSException;
use BIGSdb::Constants qw(:interface);
use BIGSdb::Offline::SequenceQuery;
use Bio::DB::GenBank;
use JSON;
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');
use constant INF                => 9**99;
use constant RUN_OFFLINE_LENGTH => 10_000;

sub get_title {
	my ($self) = @_;
	return $self->{'system'}->{'kiosk_title'} if $self->{'system'}->{'kiosk_title'};
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return $self->{'cgi'}->param('page') eq 'sequenceQuery'
	  ? qq(Sequence query - $desc)
	  : qq(Batch sequence query - $desc);
}

sub _get_text {
	my ($self) = @_;
	return $self->{'system'}->{'kiosk_text'} if $self->{'system'}->{'kiosk_text'};
	my $q    = $self->{'cgi'};
	my $page = $q->param('page');
	my $buffer =
	    q(Please paste in your sequence)
	  . ( $page eq 'batchSequenceQuery' ? 's' : '' )
	  . q( to query against the database. );
	if ( !$q->param('simple') ) {
		$buffer .=
		    q(Query sequences will be checked first for an exact match against the chosen (or all) loci - )
		  . q(they do not need to be trimmed. The nearest partial matches will be identified if an exact )
		  . q(match is not found. You can query using either DNA or peptide sequences. );
		$buffer .= $self->get_tooltip( q(Query sequence - Your query sequence is assumed to be DNA if it contains )
			  . q(90% or more G,A,T,C or N characters.) );
	}
	return $buffer;
}

sub get_help_url {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	return if $q->param('page') eq 'batchSequenceQuery';
	return "$self->{'config'}->{'doclink'}/data_query.html#querying-sequences-to-determine-allele-identity";
}

sub get_javascript {
	my $buffer = << "END";
\$(function () {
	\$(document).ajaxComplete(function() {
		initiate();
		
	});
	initiate();

});

function initiate() {
	\$('a[data-rel=ajax]').click(function(){
  		\$(this).attr('href', function(){
  			if (this.href.match(/javascript.loadContent/)){
  				return;
  			};
    		return(this.href.replace(/(.*)/, "javascript:loadContent\('\$1\'\)"));
    	});
  	});
  	\$( "#show_more" ).click(function() {
		if (\$("span#show_extra_matches").css('display') == 'none'){
			\$("span#show_extra_matches").css('display', 'inline');
			\$("span#hide_extra_matches").css('display', 'none');
		} else {
			\$("span#show_extra_matches").css('display', 'none');
			\$("span#hide_extra_matches").css('display', 'inline');
		}
		\$( ".extra_match" ).toggle();
		return false;
	});
	\$('#show_extra_matches').tooltip({ content: "Show extra matches"});
	\$('#hide_extra_matches').tooltip({ content: "Hide extra matches"});
}

function loadContent(url) {
	\$("#alignment").html('<img src=\"/javascript/themes/default/throbber.gif\" /> Loading ...').load(url);
	\$("#alignment_link").hide();
}

END
	return $buffer;
}

sub _print_interface {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	$self->_populate_kiosk_params;
	my $locus = $q->param('locus') // 0;
	$locus =~ s/%27/'/gx if $locus;    #Web-escaped locus
	$q->param( locus => $locus );
	my $page   = $q->param('page');
	my $desc   = $self->get_db_description;
	my $set_id = $self->get_set_id;
	if ( $locus && $q->param('simple') ) {

		if ( $q->param('locus') =~ /^SCHEME_(\d+)$/x ) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($1);
			$desc = $scheme_info->{'name'};
		} else {
			$desc = $q->param('locus');
		}
	}
	my $title = $self->get_title;
	say qq(<h1>$title</h1>);
	say q(<div class="box" id="queryform">);
	my $text = $self->_get_text;
	say qq(<p>$text</p>);
	say $q->start_form;
	say q(<div class="scrollable">);

	if ( !$q->param('simple') ) {
		say q(<fieldset><legend>Please select locus/scheme</legend>);
		my ( $display_loci, $cleaned ) = $self->{'datastore'}->get_locus_list( { set_id => $set_id } );
		my $scheme_list = $self->get_scheme_data;
		my %order;
		my @schemes_and_groups;
		foreach my $scheme ( reverse @$scheme_list ) {
			my $value = "SCHEME_$scheme->{'id'}";
			push @schemes_and_groups, $value;
			$order{$value} = $scheme->{'display_order'} if $scheme->{'display_order'};
			$cleaned->{$value} = $scheme->{'name'};
		}
		my $group_list = $self->{'datastore'}->get_group_list( { seq_query => 1 } );
		foreach my $group ( reverse @$group_list ) {
			my $group_schemes = $self->{'datastore'}->get_schemes_in_group( $group->{'id'}, { set_id => $set_id } );
			if (@$group_schemes) {
				my $value = "GROUP_$group->{'id'}";
				push @schemes_and_groups, $value;
				$order{$value} = $group->{'display_order'} if $group->{'display_order'};
				$cleaned->{$value} = $group->{'name'};
			}
		}
		@schemes_and_groups =
		  sort { ( $order{$a} // INF ) <=> ( $order{$b} // INF ) || $cleaned->{$a} cmp $cleaned->{$b} }
		  @schemes_and_groups;
		unshift @$display_loci, @schemes_and_groups;
		unshift @$display_loci, 0;
		$cleaned->{0} = 'All loci';
		say $q->popup_menu( -name => 'locus', -values => $display_loci, -labels => $cleaned );
		say q(</fieldset>);
		say q(<fieldset><legend>Order results by</legend>);
		say $q->popup_menu( -name => 'order', -values => [ ( 'locus', 'best match' ) ] );
		say q(</fieldset>);
	} else {
		$q->param( order => 'locus' );
		say $q->hidden($_) foreach qw(locus order simple debug);
	}
	say q(<div style="clear:both">);
	say q(<fieldset style="float:left"><legend>)
	  . (
		$page eq 'sequenceQuery'
		? q(Enter query sequence (single or multiple contigs up to whole genome in size))
		: q(Enter query sequences (FASTA format))
	  ) . q(</legend>);
	say $q->textarea( -name => 'sequence', -rows => 6, -cols => 70 );
	say q(</fieldset>);
	if ( !$q->param('no_upload') ) {
		say q(<fieldset style="float:left"><legend>Alternatively upload FASTA file</legend>);
		say q(Select FASTA file:<br />);
		say $q->filefield( -name => 'fasta_upload', -id => 'fasta_upload' );
		say q(</fieldset>);
	}
	if ( $page eq 'sequenceQuery' && !$self->{'config'}->{'intranet'} && !$q->param('no_genbank') ) {
		say q(<fieldset style="float:left"><legend>or enter Genbank accession</legend>);
		say $q->textfield( -name => 'accession' );
		say q(</fieldset>);
	}
	my $action_args;
	$action_args->{'simple'} = 1       if $q->param('simple');
	$action_args->{'set_id'} = $set_id if $set_id;
	$self->print_action_fieldset($action_args);
	say q(</div></div>);
	say $q->hidden($_) foreach qw (db page word_size no_ajax);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _populate_kiosk_params {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	foreach my $param (qw(locus simple no_upload no_genbank)) {
		$q->param( $param => $self->{'system'}->{"kiosk_$param"} ) if $self->{'system'}->{"kiosk_$param"};
	}
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->print_bad_status( { message => q(This function is not available in isolate databases.), navbar => 1 } );
		return;
	}
	my $sequence;
	$self->populate_submission_params;
	if ( $q->param('sequence') ) {
		$sequence = $q->param('sequence');
		$q->delete('sequence') if !$q->param('submission_id');
	}
	$self->_print_interface;
	if ( $q->param('submit') ) {
		if ($sequence) {
			$self->_run_query( \$sequence );
		} elsif ( $q->param('fasta_upload') ) {
			my $upload_file = $self->_upload_fasta_file;
			my $full_path   = "$self->{'config'}->{'secure_tmp_dir'}/$upload_file";
			if ( -e $full_path ) {
				$self->_run_query( BIGSdb::Utils::slurp($full_path) );
				unlink $full_path;
			}
		} elsif ( $q->param('accession') ) {
			try {
				my $acc_seq = $self->_upload_accession;
				if ($acc_seq) {
					$self->_run_query( \$acc_seq );
				}
			}
			catch BIGSdb::DataException with {
				my $err = shift;
				$logger->debug($err);
				if ( $err =~ /INVALID_ACCESSION/x ) {
					$self->print_bad_status( { message => q(Accession is invalid.) } );
				} elsif ( $err =~ /NO_DATA/x ) {
					$self->print_bad_status(
						{ message => q(The accession is valid but it contains no sequence data.) } );
				}
			};
		}
	}
	return;
}

sub _upload_fasta_file {
	my ($self)   = @_;
	my $temp     = BIGSdb::Utils::get_random();
	my $filename = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_upload.fas";
	my $buffer;
	open( my $fh, '>', $filename ) || $logger->error("Cannot open $filename for writing.");
	my $fh2 = $self->{'cgi'}->upload('fasta_upload');
	binmode $fh2;
	binmode $fh;
	read( $fh2, $buffer, $self->{'config'}->{'max_upload_size'} );
	print $fh $buffer;
	close $fh;
	return "${temp}_upload.fas";
}

sub _upload_accession {
	my ($self)    = @_;
	my $accession = $self->{'cgi'}->param('accession');
	my $seq_db    = Bio::DB::GenBank->new;
	$seq_db->retrieval_type('tempfile');    #prevent forking resulting in duplicate error message on fail.
	my $sequence;
	try {
		my $seq_obj = $seq_db->get_Seq_by_acc($accession);
		$sequence = $seq_obj->seq;
	}
	catch Bio::Root::Exception with {
		my $err = shift;
		$logger->debug($err);
		throw BIGSdb::DataException('INVALID_ACCESSION');
	};
	if ( !length($sequence) ) {
		throw BIGSdb::DataException('NO_DATA');
	}
	return $sequence;
}

sub _run_query {
	my ( $self, $seq_ref ) = @_;
	my $loci                   = $self->_get_selected_loci;
	my $q                      = $self->{'cgi'};
	my $always_run_immediately = $q->param('no_ajax') ? 1 : 0;
	if ( ( length $$seq_ref > RUN_OFFLINE_LENGTH || $q->param('page') eq 'batchSequenceQuery' )
		&& !$always_run_immediately )
	{
		$self->_blast_fork( $seq_ref, $loci );
	} else {
		$self->_blast_now( $seq_ref, $loci );
	}
	return;
}

sub _blast_now {
	my ( $self, $seq_ref, $loci ) = @_;
	my $results = $self->_run_blast( $seq_ref, $loci, 1 );
	my $q = $self->{'cgi'};
	if ( $q->param('page') eq 'sequenceQuery' && $self->{'system'}->{'web_hook_seq_query'} ) {
		my $results_prefix    = BIGSdb::Utils::get_random();
		my $results_json_file = "$self->{'config'}->{'secure_tmp_dir'}/${results_prefix}.json";
		$results->{'debug'} = 1 if $q->param('debug');
		my $results_json = encode_json($results);
		$self->_write_results_file( $results_json_file, $results_json );
		if ( -e $self->{'system'}->{'web_hook_seq_query'} ) {
			my $script_out = `$self->{'system'}->{'web_hook_seq_query'} $results_json_file`;
			say $script_out;
		} else {
			$logger->error("Script $self->{'system'}->{'web_hook_seq_query'} cannot be executed.");
			say $results->{'html'};
		}
		unlink $results_json_file;
	} else {
		say $results->{'html'};
	}
	return;
}

sub _blast_fork {
	my ( $self, $seq_ref, $loci ) = @_;
	my $q                 = $self->{'cgi'};
	my $results_prefix    = BIGSdb::Utils::get_random();
	my $results_file      = "$self->{'config'}->{'tmp_dir'}/${results_prefix}.txt";
	my $status_file       = "$self->{'config'}->{'tmp_dir'}/${results_prefix}_status.json";
	my $results_json_file = "$self->{'config'}->{'secure_tmp_dir'}/${results_prefix}.json";
	say $self->_get_polling_javascript($results_prefix);
	say q(<div id="results"><div class="box" id="resultspanel">)
	  . q(<span class="main_icon fas fa-sync-alt fa-spin fa-4x" style="margin-right:0.5em"></span>)
	  . q(<span class="wait_message">Scanning - Please wait.</span></div>)
	  . q(<noscript><div class="box statusbad"><p>Please enable Javascript in your browser</p></div></noscript></div>);

	#Use double fork to prevent zombie processes on apache2-mpm-worker
	defined( my $kid = fork ) or $logger->error('cannot fork');
	if ($kid) {
		waitpid( $kid, 0 );
	} else {
		defined( my $grandkid = fork ) || $logger->error('Kid cannot fork');
		if ($grandkid) {
			CORE::exit(0);
		} else {
			try {
				open STDIN,  '<', '/dev/null' || $logger->error("Cannot detach STDIN: $!");
				open STDOUT, '>', '/dev/null' || $logger->error("Cannot detach STDOUT: $!");
				open STDERR, '>&STDOUT' || $logger->error("Cannot detach STDERR: $!");
				$self->_update_status_file( $status_file, 'running' );
				my $results = $self->_run_blast( $seq_ref, $loci, 0 );
				if ( $q->param('page') eq 'sequenceQuery' && $self->{'system'}->{'web_hook_seq_query'} ) {
					$results->{'debug'} = 1 if $q->param('debug');
					my $results_json = encode_json($results);
					$self->_write_results_file( $results_json_file, $results_json );
					if ( -e $self->{'system'}->{'web_hook_seq_query'} ) {
						my $script_out = `$self->{'system'}->{'web_hook_seq_query'} $results_json_file`;
						$self->_write_results_file( $results_file, $script_out );
					} else {
						$logger->error("Script $self->{'system'}->{'web_hook_seq_query'} cannot be executed.");
						$self->_write_results_file( $results_file, $results->{'html'} );
					}
					unlink $results_json_file;
				} else {
					$self->_write_results_file( $results_file, $results->{'html'} );
				}
				$self->_update_status_file( $status_file, 'complete' );
			}
			catch BIGSdb::ServerBusyException with {
				my $too_busy = q(<div class="box" id="statusbad"><p>The server is currently too busy to run )
				  . q(your query. Please try again in a few minutes.</p></div>);
				$self->_write_results_file( $results_file, $too_busy );
				$self->_update_status_file( $status_file, 'complete' );
				$logger->error('Server too busy to run sequence query.');
			}
			otherwise {
				$self->_update_status_file( $status_file, 'failed' );
				$logger->error($@);
			};
		}
		CORE::exit(0);
	}
	return;
}

sub _update_status_file {
	my ( $self, $status_file, $status ) = @_;
	open( my $fh, '>', $status_file )
	  || $self->{'logger'}->error("Cannot touch $status_file");
	say $fh qq({"status":"$status"});
	close $fh;
	return;
}

sub _write_results_file {
	my ( $self, $filename, $buffer ) = @_;
	open( my $fh, '>', $filename ) || $logger->error("Cannot open $filename for writing");
	say $fh $buffer;
	close $fh;
	return;
}

sub _get_polling_javascript {
	my ( $self, $results_prefix ) = @_;
	my $status_file   = "/tmp/${results_prefix}_status.json";
	my $results_file  = "/tmp/${results_prefix}.txt";
	my $max_poll_time = 10_000;
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
			\$("div#results").html('<div class="box" id="statusbad"><p>Something went wrong!</p></div>');
		},		
		success: function(data){
			if (data.status == 'complete'){	
				\$("div#results").load("$results_file");
			} else if (data.status == 'failed'){
				\$("div#results").html('<div class="box statusbad"><p>Sequence query failed.</p></div>');
			} else if (data.status == 'running'){
				// Wait and poll again - increase poll time by 0.5s each time.
				poll_time += 500;
				if (poll_time > $max_poll_time){
					poll_time = $max_poll_time;
				}
				setTimeout(function() { 
           	        getResults(poll_time); 
                }, poll_time);
 			} else {
				\$("div#results").html();
			}
		}
	});
}
//]]></script>
END
	return $buffer;
}

sub _run_blast {
	my ( $self, $seq_ref, $loci, $always_run ) = @_;
	my $q = $self->{'cgi'};
	my $exemplar = ( $self->{'system'}->{'exemplars'} // q() ) eq 'yes' ? 1 : 0;
	$exemplar = 0 if @$loci == 1;    #We need to be able to find the nearest match if not exact.
	my $keep_partials = $q->param('page') eq 'batchSequenceQuery' ? 1 : 0;
	my $batch_query   = $q->param('page') eq 'batchSequenceQuery' ? 1 : 0;
	my $set_id        = $self->get_set_id;
	local $" = q(,);
	my $seq_qry_obj = BIGSdb::Offline::SequenceQuery->new(
		{
			config_dir       => $self->{'config_dir'},
			lib_dir          => $self->{'lib_dir'},
			dbase_config_dir => $self->{'dbase_config_dir'},
			host             => $self->{'system'}->{'host'},
			port             => $self->{'system'}->{'port'},
			user             => $self->{'system'}->{'user'},
			password         => $self->{'system'}->{'password'},
			options          => {
				l                    => qq(@$loci),
				keep_partials        => $keep_partials,
				batch_query          => $batch_query,
				exemplar             => $exemplar,
				always_run           => $always_run,
				throw_busy_exception => 1,
				select_type          => $self->{'select_type'},
				select_id            => $self->{'select_id'},
				set_id               => $set_id,
				script_name          => $self->{'system'}->{'script_name'},
				align_width          => $self->{'prefs'}->{'alignwidth'}
			},
			instance => $self->{'instance'},
			logger   => $logger
		}
	);
	my $html = $seq_qry_obj->run($$seq_ref);
	my $return_obj = { html => $html };

	if ( $q->param('page') eq 'sequenceQuery' ) {
		$return_obj->{'exact_matches'} = $seq_qry_obj->get_exact_matches;
		$return_obj->{'linked_data'}   = $seq_qry_obj->get_allele_linked_data;
	}
	return $return_obj;
}

sub _get_selected_loci {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $selection = $q->param('locus');
	my $set_id    = $self->get_set_id;
	if ( $selection eq '0' ) {
		$self->{'select_type'} = 'all';
		return $self->{'datastore'}->get_loci( { set_id => $set_id } );
	}
	if ( $selection =~ /^SCHEME_(\d+)$/x ) {
		my $scheme_id = $1;
		$self->{'select_type'} = 'scheme';
		$self->{'select_id'}   = $scheme_id;
		return $self->{'datastore'}->get_scheme_loci($scheme_id);
	}
	if ( $selection =~ /^GROUP_(\d+)$/x ) {
		my $group_id = $1;
		my $schemes  = $self->{'datastore'}->get_schemes_in_group($group_id);
		$self->{'select_type'} = 'group';
		$self->{'select_id'}   = $group_id;
		my $loci = [];
		foreach my $scheme_id (@$schemes) {
			my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
			push @$loci, @$scheme_loci;
		}
		@$loci = uniq @$loci;
		return $loci;
	}
	$selection =~ s/^cn_//x;
	$self->{'select_type'} = 'locus';
	$self->{'select_id'}   = $selection;
	return [$selection];
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (tooltips jQuery);
	return;
}
1;
