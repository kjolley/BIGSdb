#Written by Keith Jolley
#Copyright (c) 2010-2023, University of Oxford
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
package BIGSdb::SeqbinPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::IsolateInfoPage);
use BIGSdb::SeqbinToEMBL;
use BIGSdb::SeqbinToGFF3;
use BIGSdb::Constants qw(:interface LOCUS_TYPES);
use JSON;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use POSIX qw(ceil);

sub initiate {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('ajax') ) {
		$self->{'type'}    = 'no_header';
		$self->{'noCache'} = 1;
		return;
	}
	$self->{$_} = 1 foreach qw (tooltips packery jQuery billboard igv);
	$self->{'prefix'} = BIGSdb::Utils::get_random();
	my $page_name  = $self->get_title( { breadcrumb => 1 } );
	my $isolate_id = $q->param('isolate_id');
	return if !BIGSdb::Utils::is_int($isolate_id);
	$self->{'breadcrumbs'} = [
		{
			label => $self->{'system'}->{'webroot_label'} // 'Organism',
			href  => $self->{'system'}->{'webroot'}
		},
		{
			label => $self->{'system'}->{'formatted_description'} // $self->{'system'}->{'description'},
			href  => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}"
		},
		{
			label => 'Isolate info',
			href  => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=info&amp;id=$isolate_id"
		},
		{
			label => 'Sequence bin'
		}
	];
	return;
}

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/data_records.html#sequence-bin-records";
}

sub _ajax {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $isolate_id = $q->param('isolate_id');
	return if !BIGSdb::Utils::is_int($isolate_id);
	my $seqbin_stats = $self->{'datastore'}->get_seqbin_stats( $isolate_id, { general => 1, lengths => 1 } );
	if ( scalar $q->param('ajax') eq 'contig_size' ) {
		my $std_dev = BIGSdb::Utils::std_dev( $seqbin_stats->{'mean_length'}, $seqbin_stats->{'lengths'} );

		#Scott's choice [Scott DW (1979). On optimal and data-based histograms. Biometrika 66(3):605–610]
		my $bins = ceil( ( 3.5 * $std_dev ) / $seqbin_stats->{'contigs'}**0.33 );
		$bins = 1 if !$bins;
		my $width = ( $seqbin_stats->{'max_length'} - $seqbin_stats->{'min_length'} ) / $bins;

		#round width to nearest 500
		$width = int( $width - ( $width % 500 ) ) || 500;
		my ( $histogram, $min, $max ) = BIGSdb::Utils::histogram( $width, $seqbin_stats->{'lengths'} );
		my ( @labels, @values );
		foreach my $i ( $min .. $max ) {
			push @labels, $i * $width;
			push @values, $histogram->{$i};
		}
		my $size_dis = [];
		foreach my $i ( $min .. $max ) {
			push @$size_dis,
			  {
				label => $i == 0 ? q(0-) . $width : ( $i * $width + 1 ) . q(-) . ( ( $i + 1 ) * $width ),
				value => $histogram->{$i}
			  };
		}
		say encode_json($size_dis);
	} elsif ( scalar $q->param('ajax') eq 'cumulative' ) {
		my $total_length = 0;
		my $contig       = 0;
		my $cumulative   = [];
		foreach my $length ( @{ $seqbin_stats->{'lengths'} } ) {
			$contig++;
			$total_length += $length;
			push @$cumulative,
			  {
				contig     => $contig,
				cumulative => $total_length
			  };
		}
		say encode_json($cumulative);
	}
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('ajax') ) {
		$self->_ajax;
		return;
	}
	my $isolate_id = $q->param('isolate_id');
	if ( !defined $isolate_id ) {
		$self->print_bad_status( { message => q(Isolate id not specified.), navbar => 1 } );
		return;
	}
	if ( !BIGSdb::Utils::is_int($isolate_id) ) {
		$self->print_bad_status( { message => q(Isolate id must be an integer.), navbar => 1 } );
		return;
	}
	my $exists =
	  $self->{'datastore'}
	  ->run_query( "SELECT EXISTS(SELECT * FROM $self->{'system'}->{'view'} WHERE id=?)", $isolate_id );
	if ( !$exists ) {
		say qq(<h1>Sequence bin for isolate id $isolate_id</h1>);
		$self->print_bad_status(
			{ message => q(The database contains no accessible record of this isolate.), navbar => 1 } );
		return;
	}
	my $name = $self->get_name($isolate_id);
	if ($name) {
		say qq(<h1>Sequence bin for $name</h1>);
	} else {
		say qq(<h1>Sequence bin for isolate id $isolate_id</h1>);
	}
	$self->{'contigManager'}->update_isolate_remote_contig_lengths($isolate_id);
	my $seqbin_stats = $self->{'datastore'}->get_seqbin_stats( $isolate_id, { general => 1, lengths => 1 } );
	if ( !$seqbin_stats->{'contigs'} ) {
		say q(<div class="box statusbad"><p>This isolate has no sequence data attached.</p></div>);
		return;
	}
	$self->_print_stats( $isolate_id, $seqbin_stats );
	$self->_print_contig_table( $isolate_id, $seqbin_stats );
	return;
}

sub _print_stats {
	my ( $self, $isolate_id, $seqbin_stats ) = @_;
	say q(<div class="box resultspanel">);
	say q(<div class="grid" style="margin-bottom:0.5em">);
	say q(<div style="float:left" class="grid-item">);
	say q(<h2>Contig summary statistics</h2>);
	say qq(<dl class="data"><dt>Contigs</dt><dd>$seqbin_stats->{'contigs'}</dd>);
	if ( $seqbin_stats->{'contigs'} > 1 ) {
		my $n_stats = BIGSdb::Utils::get_N_stats( $seqbin_stats->{'total_length'}, $seqbin_stats->{'lengths'} );
		my %commify = map { $_ => BIGSdb::Utils::commify( $seqbin_stats->{$_} ) }
		  qw(total_length min_length max_length mean_length);
		say qq(<dt>Total length</dt><dd>$commify{'total_length'}</dd>);
		say qq(<dt>Minimum length</dt><dd>$commify{'min_length'}</dd>);
		say qq(<dt>Maximum length</dt><dd>$commify{'max_length'}</dd>);
		say qq(<dt>Mean length</dt><dd>$commify{'mean_length'}</dd>);
		foreach my $stat (qw(N50 L50 N90 L90 N95 L95)) {
			my $commify = BIGSdb::Utils::commify( $n_stats->{$stat} );
			say qq(<dt>$stat</dt><dd>$commify</dd>);
		}
		say q(</dl>);
	} else {
		my $commify = BIGSdb::Utils::commify( $seqbin_stats->{'total_length'} );
		say qq(<dt>Length</dt><dd>$commify</dd></dl>);
	}
	my ( $fasta, $embl, $gbk, $gff3 ) = ( FASTA_FILE, EMBL_FILE, GBK_FILE, GFF3_FILE );
	print qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=downloadSeqbin&amp;isolate_id=$isolate_id" title="FASTA format">$fasta</a>);
	print qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=embl&amp;)
	  . qq(isolate_id=$isolate_id" title="EMBL format">$embl</a>);
	print qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=embl&amp;)
	  . qq(isolate_id=$isolate_id&amp;format=genbank" title="Genbank format">$gbk</a>);
	my $tags = $self->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM allele_sequences WHERE isolate_id=?)', $isolate_id );
	if ($tags) {
		print qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=gff&amp;)
		  . qq(isolate_id=$isolate_id" title="GFF3 format">$gff3</a>);
	}
	say q(</p>);
	say q(</div>);
	if ( $seqbin_stats->{'contigs'} > 1 ) {
		say q(<div class="grid-item" style="max-width:100%">);
		say q(<div id="contig_size" class="embed_bb_chart smooth_enlarge"></div>);
		say q(</div>);
		say q(<div class="grid-item" style="max-width:100%">);
		say q(<div id="cumulative" class="embed_bb_chart smooth_enlarge"></div>);
		say q(</div>);
	}
	say q(</div>);
	say q(<div style="clear:both"></div></div>);
	say q(<div id="igv" class="box"></div>);
	return;
}

sub _get_tracks_js {
	my ( $self, $isolate_id ) = @_;
	my $locus_types =
	  $self->{'datastore'}->run_query(
		'SELECT DISTINCT locus_type FROM loci l JOIN allele_sequences a ON l.id=a.locus WHERE a.isolate_id=?',
		$isolate_id, { fetch => 'col_arrayref' } );
	my @palette = ( '#7570b3', '#1b9e77', '#d95f02', '#e7298a', '#66a61e', '#e6ab02', '#a6761d', '#666666' );
	my @types   = ( LOCUS_TYPES, 'miscellaneous', );
	my %locus_colours;
	my $no_types_defined = @$locus_types == 1 && !defined $locus_types->[0];
	if ($no_types_defined) {
		%locus_colours = ( loci => $palette[0] );
	} else {
		for my $i ( 0 .. @types - 1 ) {
			$locus_colours{ $types[$i] } = $palette[$i];
		}
	}
	my $tracks = [];
	my @tracks;
	foreach my $type (@$locus_types) {
		$type //= $no_types_defined ? 'loci' : 'miscellaneous';
		( my $type_arg = $type ) =~ s/\s/_/gx;
		my $type_clause = $type eq 'loci' ? q() : qq(&type=$type_arg);
		push @tracks, << "TRACKS";
{
                name:"$type",
                type:"annotation", 
                url:"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=gff&isolate_id=$isolate_id&igv=1$type_clause",
                format:"gff3",
                indexed:false,
                color:"$locus_colours{$type}",
                removable:false,
                searchable:true
             }
TRACKS
	}
	my $buffer = q(tracks: [);
	local $" = q(             ,);
	$buffer .= qq(@tracks);
	$buffer .= q(            ]);
	return $buffer;
}

sub get_javascript {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $isolate_id = $q->param('isolate_id');
	return if !BIGSdb::Utils::is_int($isolate_id);
	$self->_get_tracks_js($isolate_id);
	my $url    = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=seqbin&isolate_id=$isolate_id";
	my $tracks = $self->_get_tracks_js($isolate_id);
	my $buffer = << "END";
\$(function () {
	var \$grid = \$(".grid").packery({
    	itemSelector:'.grid-item',
  		gutter:5
    });        
    \$(window).resize(function() {
    	delay(function(){
      		\$grid.packery();
    	}, 1000);
 	});
	var chart = [];
	\$(".embed_bb_chart").click(function() {
		if (jQuery.data(this,'expand')){
			\$(this).css({width:'400px','height':'250px'});    
			jQuery.data(this,'expand',0);
		} else {
  			\$(this).css({width:'800px','height':'500px'});    		
    		jQuery.data(this,'expand',1);
		}
		var chart_id=this.id;
		//For browsers that don't support ResizeObserver.
		delay(function(){
      		chart[chart_id].resize();
			\$grid.packery();
  	 	}, 500);
		
	});
	
	d3.json("$url" + "&ajax=contig_size").then (function(jsonData) {
		chart['contig_size'] = bb.generate({
			bindto: '#contig_size',
			title: {
				text: 'Contig size distribution'
			},
			data: {
				json: jsonData,
				keys: {
					x: 'label',
					value: ['value']
				},
				type: 'bar'
			},	
			bar: {
				width: {
					ratio: 0.6
				}
			},
			axis: {
				x: {
					label: {
						text: 'Size range (bp)',
						position: 'outer-center'
					},
					type: 'category',
					tick: {
						count: 2,
						multiline:false
					}
				}
			},
			legend: {
				show: false
			},
			padding: {
				right: 40
			},
			oninit: function(){
				\$grid.packery();
			}
		});
	});
	
	d3.json("$url" + "&ajax=cumulative").then (function(jsonData) {
		chart['cumulative'] = bb.generate({
			bindto: '#cumulative',
			title: {
				text: 'Cumulative contig length'
			},
			data: {
				json: jsonData,
				keys: {
					x: 'contig',
					value: ['cumulative']
				}
			},	
			axis: {
				x: {
					label: {
						text: 'Contig',
						position: 'outer-center'
					},
					type: 'category',
					tick: {
						count: 2,
						multiline:false
					}
				}
			},
			legend: {
				show: false
			},
			padding: {
				right: 20
			},
			tooltip: {
				format: {
					title: function (x, index) { return 'Contig ' + (x+1); }
				}
			},
			oninit: function(){
				\$grid.packery();
			}
		});
	});
	\$(".embed_bb_chart").css({width:'400px','max-width':'95%',height:'250px'});
	var resizeObserver = new ResizeObserver( entries => { 
		for (let entry of entries) {
			if (typeof chart[entry.target.id] != 'undefined'){
				chart[entry.target.id].resize();
			}
		}
    	\$grid.packery();
	}); 
	if (\$('#contig_size').length){
		resizeObserver.observe( document.querySelector('#contig_size') ); 
	}
	if (\$('#cumulative').length){
		resizeObserver.observe( document.querySelector('#cumulative') ); 
	}
	
	var igvDiv = \$("#igv");
	var options = {
  		reference: {
  			fastaURL: "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=downloadSeqbin&isolate_id=$isolate_id",
  			indexed: false,
  			showAllChromosomes: true,
  			$tracks
  		}
	};
	igv.createBrowser(igvDiv, options);

  });
var delay = (function(){
  var timer = 0;
  return function(callback, ms){
    clearTimeout (timer);
    timer = setTimeout(callback, ms);
  };
})();
END
	return $buffer;
}

sub _print_contig_table_header {
	my ( $self, $attributes ) = @_;
	my @cleaned_attributes = @$attributes;
	s/_/ / foreach @cleaned_attributes;
	local $" = q(</th><th>);
	my $att_headings = @cleaned_attributes ? qq(<th>@cleaned_attributes</th>) : q();
	say q(<tr><th>Sequence</th><th>Sequencing method</th>)
	  . qq(<th>Original designation</th><th>Length</th><th>Comments</th>$att_headings<th>Locus</th>)
	  . q(<th>Start</th><th>End</th><th>Direction</th><th>Annotation</th>);
	if ( $self->{'curate'} && ( $self->{'permissions'}->{'modify_loci'} || $self->is_admin ) ) {
		say q(<th>Renumber);
		say $self->get_tooltip(
			q(Renumber - You can use the numbering of the )
			  . q(sequence tags to automatically set the genome order position for each locus. This will )
			  . q(be used to order the sequences when exporting FASTA or XMFA files.),
			{ style => 'color:white' }
		);
		say q(</th>);
	}
	say q(</tr>);
	return;
}

sub _print_contig_table {
	my ( $self, $isolate_id, $seqbin_stats ) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="resultstable">);
	say q(<div class="scrollable">);
	my $seq_attributes =
	  $self->{'datastore'}
	  ->run_query( 'SELECT key FROM sequence_attributes ORDER BY key', undef, { fetch => 'col_arrayref' } );
	say q(<table class="resultstable">);
	$self->_print_contig_table_header($seq_attributes);
	my $td     = 1;
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? 'AND (locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes '
	  . "WHERE set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';
	local $| = 1;
	my $qry =
		'SELECT id,GREATEST(r.length,length(sequence)) AS length,original_designation,method,comments,sender,'
	  . 'curator,date_entered,datestamp FROM sequence_bin s LEFT JOIN remote_contigs r ON s.id=r.seqbin_id WHERE '
	  . 'isolate_id=? ORDER BY length desc';
	my $contig_data = $self->{'datastore'}->run_query( $qry, $isolate_id, { fetch => 'all_arrayref', slice => {} } );

	foreach my $data (@$contig_data) {
		my $allele_count =
		  $self->{'datastore'}->run_query( "SELECT COUNT(*) FROM allele_sequences WHERE seqbin_id=? $set_clause",
			$data->{'id'}, { cache => 'SeqbinPage::print_content::count' } );
		my $att_values =
		  $self->{'datastore'}->run_query( 'SELECT key,value FROM sequence_attribute_values WHERE seqbin_id=?',
			$data->{'id'}, { fetch => 'all_hashref', key => 'key', cache => 'SeqbinPage::print_content::keyvalue' } );
		my $first = 1;
		if ($allele_count) {
			print qq(<tr class="td$td">);
			my $open_td = qq(<td rowspan="$allele_count" style="vertical-align:top">);
			print qq($open_td$data->{'id'}</td>);
			foreach my $field (qw(method original_designation length comments)) {
				$data->{$field} //= q();
				print qq($open_td$data->{$field}</td>);
			}
			foreach my $att (@$seq_attributes) {
				$att_values->{$att}->{'value'} //= '';
				print qq($open_td$att_values->{$att}->{'value'}</td>);
			}
			my $allele_seqs =
			  $self->{'datastore'}
			  ->run_query( "SELECT * FROM allele_sequences WHERE seqbin_id=? $set_clause ORDER BY start_pos",
				$data->{'id'},
				{ fetch => 'all_arrayref', slice => {}, cache => 'SeqbinPage::print_content::allele_sequences' } );
			foreach my $allele_seq (@$allele_seqs) {
				print qq(<tr class="td$td">) if !$first;
				my $cleaned_locus = $self->clean_locus( $allele_seq->{'locus'} );
				my $start         = $allele_seq->{'start_pos'} < 1     ? 1                 : $allele_seq->{'start_pos'};
				my $end = $allele_seq->{'end_pos'} > $data->{'length'} ? $data->{'length'} : $allele_seq->{'end_pos'};
				say qq(<td>$cleaned_locus )
				  . ( $allele_seq->{'complete'} ? '' : '*' )
				  . qq(</td><td>$start</td><td>$end</td>);
				say q(<td style="font-size:2em">) . ( $allele_seq->{'reverse'} ? q(&larr;) : q(&rarr;) ) . q(</td>);
				if ($first) {
					my $url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;"
					  . "page=embl&amp;seqbin_id=$data->{'id'}";
					say qq(<td rowspan="$allele_count" style="vertical-align:top">);
					say qq(<span class="annotation_link"><a href="$url">EMBL</span></a>);
					say qq(<span class="annotation_link"><a href="$url&amp;format=genbank">GBK</span></a></td>);
					if ( $self->{'curate'} && ( $self->{'permissions'}->{'modify_loci'} || $self->is_admin ) ) {
						say qq(<td rowspan="$allele_count" style="vertical-align:top">);
						say $q->start_form;
						$q->param( page      => 'renumber' );
						$q->param( seqbin_id => $data->{'id'} );
						say $q->hidden($_) foreach qw (page db seqbin_id);
						say $q->submit( -name => 'Renumber', -class => 'small_submit', -style => 'margin-top:0.3em' );
						say $q->end_form;
						say q(</td>);
					}
				}
				say q(</tr>);
				$first = 0;
			}
		} else {
			say qq(<tr class="td$td"><td>$data->{'id'}</td>);
			say defined $data->{'method'}               ? qq(<td>$data->{'method'}</td>)               : q(<td /></td>);
			say defined $data->{'original_designation'} ? qq(<td>$data->{'original_designation'}</td>) : q(<td></td>);
			say qq(<td>$data->{'length'}</td>);
			print defined $data->{'comments'} ? qq(<td>$data->{'comments'}</td>) : q(<td></td>);
			foreach my $att (@$seq_attributes) {
				$att_values->{$att}->{'value'} //= q();
				say qq(<td>$att_values->{$att}->{'value'}</td>);
			}
			say q(<td></td><td></td><td></td><td></td><td></td>);
			say q(<td></td>) if $self->{'curate'};
			say q(</tr>);
		}
		$td = $td == 1 ? 2 : 1;
		if ( $ENV{'MOD_PERL'} ) {
			return if $self->{'mod_perl_request'}->connection->aborted;
			eval { $self->{'mod_perl_request'}->rflush };
		}
	}
	say q(</table></div></div>);
	return;
}

sub get_title {
	my ($self) = @_;
	my $isolate_id = $self->{'cgi'}->param('isolate_id');
	return 'Invalid isolate id' if !BIGSdb::Utils::is_int($isolate_id);
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	if ($isolate_id) {
		my $name = $self->get_name($isolate_id);
		return qq(Sequence bin: id-$isolate_id ($name)) if $name;
	}
	return qq(Sequence bin - $desc);
}
1;
