#RMLSTSpecies.pm - rMLST species identification plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2018-2020, University of Oxford
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
use BIGSdb::Constants qw(:interface);
use List::Util qw(max);
use List::MoreUtils qw(uniq);
use JSON;
use MIME::Base64;
use LWP::UserAgent;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_ISOLATES       => 1000;
use constant INITIAL_BUSY_DELAY => 60;
use constant MAX_DELAY          => 600;
use constant URL                => 'https://rest.pubmlst.org/db/pubmlst_rmlst_seqdef_kiosk/schemes/1/sequence';

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
		version     => '1.2.8',
		dbtype      => 'isolates',
		section     => 'info,analysis,postquery',
		input       => 'query',
		help        => 'tooltips',
		system_flag => 'rMLSTSpecies',
		requires    => 'seqbin',
		url         => "$self->{'config'}->{'doclink'}/data_analysis/rMLST.html",
		order       => 40,
		priority    => 0
	);
	return \%att;
}

sub run {
	my ($self) = @_;
	my $desc = $self->get_db_description;
	say qq(<h1>rMLST species identification - $desc</h1>);
	my $q = $self->{'cgi'};
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
		if ( @ids > MAX_ISOLATES ) {
			my $count  = BIGSdb::Utils::commify( scalar @ids );
			my $max    = BIGSdb::Utils::commify(MAX_ISOLATES);
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
	$self->_print_interface;
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	$self->{'exit'} = 0;
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1 } ) x 3;
	my $isolate_ids  = $self->{'jobManager'}->get_job_isolates($job_id);
	my $job          = $self->{'jobManager'}->get_job($job_id);
	my $html         = $job->{'message_html'} // q();
	my $i            = 0;
	my $progress     = 0;
	my $table_header = $self->_get_javascript;
	my $colspan      = 5;
	$table_header .=
	    q(<div class="scrollable"><table class="resultstable"><tr><th rowspan="2">id</th>)
	  . qq(<th rowspan="2">$self->{'system'}->{'labelfield'}</th>)
	  . qq(<th colspan="$colspan">Prediction from identified rMLST alleles linked to genomes</th>)
	  . qq(<th colspan="2">Identified rSTs</th></tr>\n)
	  . q(<tr><th>Rank</th><th>Taxon</th><th>Taxonomy</th><th>Support</th><th>Matches</th>)
	  . qq(<th>rST</th><th>Species</th></tr>\n);
	my $td = 1;
	my $row_buffer;
	my $report = {};

	foreach my $isolate_id (@$isolate_ids) {
		$progress = int( $i / @$isolate_ids * 100 );
		$i++;
		$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => $progress } );
		my $isolate_name = $self->get_isolate_name_from_id($isolate_id);
		my ( $data, $values, $response_code ) = $self->_perform_rest_query( $job_id, $i, $isolate_id );
		$report->{$isolate_id} = {
			$self->{'system'}->{'labelfield'} => $isolate_name,
			analysis                          => $data
		};
		$row_buffer .= $self->_format_row_html( $params,
			{ td => $td, values => $values, response_code => $response_code, row_no => $i } );
		my $message_html = qq($html\n$table_header\n$row_buffer\n</table></div>);
		$self->{'jobManager'}->update_job_status( $job_id, { message_html => $message_html } );
		$td = $td == 1 ? 2 : 1;
		last if $self->{'exit'};
	}
	if ($report) {
		my $filename = "$self->{'config'}->{'tmp_dir'}/$job_id.json";
		open( my $fh, '>', $filename ) || $logger->error("Cannot open $filename for writing");
		say $fh encode_json($report);
		close $fh;
		if ( -e $filename ) {
			$self->{'jobManager'}->update_job_output( $job_id,
				{ filename => "$job_id.json", description => '01_Report file (JSON format)' } );
		}
	}
	return;
}

sub _format_row_html {
	my ( $self, $params, $args ) = @_;
	my ( $td, $values, $response_code, $row_no ) = @{$args}{qw(td values response_code row_no)};
	my $allele_predictions = ref $values->[2] eq 'ARRAY' ? @{ $values->[2] } : 0;
	my $rows = max( $allele_predictions, 1 );
	my %italicised = map { $_ => 1 } ( 3, 4, 8 );
	my %left_align = map { $_ => 1 } ( 4, 5 );
	my $buffer;
	my ( $show, $hide ) = ( SHOW, HIDE );

	foreach my $row ( 0 .. $rows - 1 ) {
		my $no_matches;
		my $class = $row == $rows - 1 ? q( last_row) : q();
		$buffer .= qq(<tr class="td$td$class">);
		if ( $row == 0 ) {
			$buffer .= qq(<td rowspan="$rows">$values->[$_]</td>) foreach ( 0, 1 );
		}
		if ( !$allele_predictions ) {
			my $message;
			if ( $response_code == 413 ) {
				$message = q(Genome size is too large or contains too many contigs for analysis);
			} else {
				$logger->error("No matching alleles - response code was $response_code");
				$message = q(No exact matching alleles linked to genome found);
			}
			$no_matches = 1;
			$buffer .= qq(<td colspan="4" style="text-align:left">$message</td>);
		} else {
			foreach my $col ( 2 .. 5 ) {
				$buffer .= $left_align{$col} ? q(<td style="text-align:left">) : q(<td>);
				$buffer .= q(<i>) if $italicised{$col};
				if ( $col == 5 ) {
					my $colour = $self->_get_colour( $values->[$col]->[$row] );
					$buffer .=
					    q(<span style="position:absolute;margin-left:1em;font-size:0.8em">)
					  . qq($values->[$col]->[$row]%</span>)
					  . qq(<div style="display:block-inline;margin-top:0.2em;background-color:\#$colour;)
					  . qq(border:1px solid #ccc;height:0.8em;width:$values->[$col]->[$row]%"></div>);
				} else {
					$buffer .= $values->[$col]->[$row];
				}
				$buffer .= q(</i>) if $italicised{$col};
				$buffer .= q(</td>);
			}
		}
		if ( $row == 0 ) {
			foreach my $col ( 6 .. 8 ) {
				$buffer .= qq(<td rowspan="$rows">);
				$buffer .= q(<i>) if $italicised{$col};
				if ( $col == 6 ) {
					if ( !$no_matches ) {
						my $filename = $values->[$col];
						$buffer .=
						    qq(<a class="ajax_link" id="row_$row_no" href="$params->{'script_name'}?)
						  . qq(db=$self->{'instance'}&amp;)
						  . qq(page=plugin&amp;name=RMLSTSpecies&amp;filename=$filename&amp;no_header=1">$show</a>);
						$buffer .=
						  qq(<a id="row_${row_no}_hide" class="row_hide" style="display:none;cursor:pointer">$hide</a>);
					}
				} else {
					$buffer .= $values->[$col] // q();
				}
				$buffer .= q(</i>) if $italicised{$col};
				$buffer .= q(</td>);
			}
		}
		$buffer .= qq(</tr>\n);
	}
	return $buffer;
}

sub _perform_rest_query {
	my ( $self, $job_id, $i, $isolate_id ) = @_;
	my $qry = 'SELECT id,sequence FROM sequence_bin WHERE isolate_id=? AND NOT remote_contig';
	my $contigs =
	  $self->{'datastore'}
	  ->run_query( $qry, $isolate_id, { fetch => 'all_arrayref', cache => 'RMLSTSpecies::blast_create_fasta::local' } );
	my $fasta;
	foreach my $contig (@$contigs) {
		$fasta .= qq(>$contig->[0]\n$contig->[1]\n);
	}
	my $remote_qry = 'SELECT s.id,r.uri,r.length,r.checksum FROM sequence_bin s LEFT JOIN remote_contigs r ON '
	  . 's.id=r.seqbin_id WHERE s.isolate_id=? AND remote_contig';
	my $remote_contigs =
	  $self->{'datastore'}->run_query( $remote_qry, $isolate_id,
		{ fetch => 'all_arrayref', slice => {}, cache => 'RMLSTSpecies::blast_create_fasta::remote' } );
	my $remote_uris = [];
	foreach my $contig_link (@$remote_contigs) {
		push @$remote_uris, $contig_link->{'uri'};
	}
	my $remote_data;
	eval { $remote_data = $self->{'contigManager'}->get_remote_contigs_by_list($remote_uris); };
	if ($@) {
		$logger->error($@);
	} else {
		foreach my $contig_link (@$remote_contigs) {
			$fasta .= qq(>$contig_link->{'id'}\n$remote_data->{$contig_link->{'uri'}}\n);
			if ( !$contig_link->{'length'} ) {
				$self->{'contigManager'}->update_remote_contig_length( $contig_link->{'uri'},
					length( $remote_data->{ $contig_link->{'uri'} } ) );
			} elsif ( $contig_link->{'length'} != length( $remote_data->{ $contig_link->{'uri'} } ) ) {
				$logger->error("$contig_link->{'uri'} length has changed!");
			}

			#We won't set checksum because we're not extracting all metadata here
		}
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
	my %server_error = map { $_ => 1 } ( 500, 502, 503, 504 );
	do {
		$self->{'jobManager'}->update_job_status( $job_id, { stage => "Scanning isolate $i" } );
		$unavailable = 0;
		$response    = $agent->post(
			URL,
			Content_Type => 'application/json; charset=UTF-8',
			Content      => $payload
		);
		if ( $server_error{ $response->code } ) {
			my $code = $response->code;
			$logger->error("Error $code received from rMLST REST API.");
			$unavailable = 1;
			$self->{'jobManager'}->update_job_status( $job_id,
				{ stage => "rMLST server is unavailable or too busy at the moment - retrying in $delay seconds", } );
			sleep $delay;
			$delay += 10 if $delay < MAX_DELAY;
		}
	} while ($unavailable);
	my $data     = {};
	my $rank     = [];
	my $taxon    = [];
	my $taxonomy = [];
	my $support  = [];
	my ( $json_link, $rST, $species );
	if ( $response->is_success ) {
		$data = decode_json( $response->content );
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
		$json_link = $self->_write_row_json_file( $job_id, $i, $response );
	} else {
		$logger->error( $response->as_string );
	}
	push @$values, ( $rank, $taxon, $taxonomy, $support, $json_link, $rST, $species );
	return ( $data, $values, $response->code );
}

sub _write_row_json_file {
	my ( $self, $job_id, $row, $response ) = @_;
	my $filename  = "${job_id}_$row.json";
	my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
	open( my $fh, '>', $full_path ) || $logger->error("Cannot open $full_path for writing");
	say $fh $response->content;
	close $fh;
	return $filename;
}

sub _print_interface {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $qry_ref    = $self->get_query($query_file);
	my $selected_ids;
	my $seqbin_values = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT id FROM sequence_bin)');
	if ( !$seqbin_values ) {
		$self->print_bad_status( { message => q(This database view contains no genomes.), navbar => 1 } );
		return;
	}
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
	say q(<div class="box" id="queryform"><p>This analysis attempts to identify exact matching rMLST alleles within )
	  . q(selected isolate sequence record(s). A predicted taxon will be shown where identified alleles have been )
	  . q(linked to validated genomes in the rMLST database.</p>);
	if ( !$q->param('single_isolate') ) {
		say q(<p>Please select the required isolate ids to run the species identification for. )
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

sub _get_colour {
	my ( $self, $num ) = @_;
	my ( $min, $max, $middle ) = ( 0, 100, 50 );
	my $scale = 255 / ( $middle - $min );
	return q(FF0000) if $num <= $min;    # lower boundry
	return q(00FF00) if $num >= $max;    # upper boundary
	if ( $num < $middle ) {
		return sprintf q(FF%02X00) => int( ( $num - $min ) * $scale );
	} else {
		return sprintf q(%02XFF00) => 255 - int( ( $num - $middle ) * $scale );
	}
}

sub _get_javascript {
	my ($self) = @_;
	my $buffer = << "END";
<script type="text/Javascript">
\$(function () {
	\$(".ajax_link").click(function(event){	
		event.preventDefault();
		var added_id = \$(this).attr("id") + '_added';
		var row_show_button_id = \$(this).attr("id");
		var row_hide_button_id = \$(this).attr("id") + '_hide';
		if (\$("#" + added_id).length){
			return false;
		} 
		var inserted_row = jQuery('<tr id="'+added_id+'"><td colspan="9"><div id="'+added_id+'_div"></div></td></tr>');
		var row_to_insert_after = \$("#" + \$(this).attr("id")).closest("tr.last_row");
		if (!(row_to_insert_after.length)){
			row_to_insert_after = \$("#" + \$(this).attr("id")).closest("tr").nextAll("tr.last_row:first");
		}
		row_to_insert_after.after(inserted_row);
		var regex = /filename=(BIGSdb_[\\d_]*\.json)/;
		var matches = regex.exec(\$(this).attr("href"));
		var filename = matches[1];
		var full_path = "/tmp/" + filename;
		\$.ajax({
   			contentType: 'application/json',
    		dataType: "json",
    		url: full_path,
    		success: function (data) {
              	var formatted = format_data(data);          	
             	\$("#" + added_id + "_div").hide().html(formatted).slideDown("slow");
             	\$("#" + row_hide_button_id).show();
             	\$("#" + row_show_button_id).hide();
            },
    		error: function(data, errorThrown){
            	alert('request failed :'+errorThrown);
          	}
	    });	
		return false;
	});
	\$(".row_hide").click(function(event){	
		event.preventDefault();
		var row_id = \$(this).attr("id").replace("hide","added");
		var content_div = row_id + "_div";
		var hide_button = \$(this).attr("id");
		var show_button = \$(this).attr("id").replace("_hide","");
		\$("#" + content_div).slideUp("slow", function(){
			\$("#" + row_id).remove();	
			\$("#" + hide_button).hide();
			\$("#" + show_button).show();
		});		
		return false;
	});
});

function format_data(data){
	if (!('exact_matches' in data)){
		return;
	}
	var loci = [];
	console.log(data['exact_matches']);
	var loci_matched = 0;
	
	for(var key in data['exact_matches']) {
  		if(data['exact_matches'].hasOwnProperty(key)) { //to be safe
    		loci.push(key);
    		loci_matched++;
 		}
	}
	loci.sort();
	var plural = loci_matched == 1 ? "us" : "i";
	var table = '<p style="text-align:left"><b>' + loci_matched + ' loc' + plural 
	  + ' matched (rMLST uses 53 in total)</b></p>\\n'
	  + '<table class="ajaxtable" style="width:100%"><tr><th>Locus</th><th>Allele</th><th>Length</th><th>Contig</th>'
	  + '<th>Start position</th><th>End position</th><th style="text-align:left">Linked data values</th></tr>\\n';
	var td = 1 ;
	\$.each(loci, function( locus_index, locus ) {
		\$.each(data['exact_matches'][locus], function(match_index, match){
			table += '<tr class="td' + td + '"><td>' + locus + '</td>';
			table += '<td>' + match['allele_id'] + '</td>';
			table += '<td>' + match['length'] + '</td>';
			table += '<td>' + match['contig'] + '</td>';
			table += '<td>' + match['start'] + '</td>';
			table += '<td>' + match['end'] + '</td>';
			if (match.hasOwnProperty('linked_data')){
				var list = '<b>species:</b> ';
				var first = 1;
				\$.each(match['linked_data']['rMLST genome database']['species'], function (species_index,sp_obj){
					if (!first){
						list += '; ';
					};
					list += sp_obj['value'] + " [n=" + sp_obj['frequency'] + "]";
					first = 0;
				});
				table += '<td style="text-align:left">' + list + '</td>';
			} else {
				table += '<td></td>';
			}
			table += '</tr>\\n';
			td = td == 1 ? 2 : 1;
		});
	});
	
	table += '</table>';
	return table;
}

</script>
END
	return $buffer;
}
1;
