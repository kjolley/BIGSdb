#Polymorphisms.pm - Plugin for BIGSdb (requires LocusExplorer plugin)
#Written by Keith Jolley
#Copyright (c) 2011-2015, University of Oxford
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
package BIGSdb::Plugins::Polymorphisms;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugins::LocusExplorer);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use List::MoreUtils qw(none);
use Apache2::Connection ();
use Bio::SeqIO;
use File::Copy;
use constant MAX_INSTANT_RUN => 100;    #Number of sequences before we start an offline job
use constant MAX_SEQUENCES   => 2000;

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name        => 'Polymorphisms',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Tool for analysing polymorphic sites for particular locus in an isolate dataset',
		category    => 'Breakdown',
		menutext    => 'Polymorphic sites',
		module      => 'Polymorphisms',
		version     => '1.1.2',
		dbtype      => 'isolates',
		url         => "$self->{'config'}->{'doclink'}/data_analysis.html#polymorphisms",
		section     => 'breakdown,postquery',
		requires    => 'aligner,offline_jobs',
		input       => 'query',
		help        => 'tooltips',
		order       => 15,
		max         => MAX_SEQUENCES
	);
	return \%att;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 1, query_field => 0 };
	return;
}
sub get_plugin_javascript { }    #override version in LocusExplorer.pm

sub run {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $list_file  = $q->param('list_file');
	my $datatype   = $q->param('datatype');
	say q(<h1>Polymorphic site analysis</h1>);
	my $locus = $q->param('locus') // q();
	$locus =~ s/^cn_//x;

	if ( !$locus ) {
		say q(<div class="box" id="statusbad"><p>Please select a locus.</p></div>) if $q->param('submit');
		$self->_print_interface;
		return;
	}
	local $| = 1;
	say q(<div class="hideonload"><p>Please wait - checking sequences (do not refresh) ...</p>)
	  . q(<p><span class="main_icon fa fa-refresh fa-spin fa-4x"></span></p></div>);
	if ( $ENV{'MOD_PERL'} ) {
		$self->{'mod_perl_request'}->rflush;
		return if $self->{'mod_perl_request'}->connection->aborted;
	}
	my $qry_ref = $self->get_query($query_file);
	return if ref $qry_ref ne 'SCALAR';
	my $ids = $self->get_ids_from_query($qry_ref);
	my %options;
	$options{'from_bin'}            = $q->param('chooseseq') eq 'seqbin' ? 1 : 0;
	$options{'unique'}              = $q->param('unique');
	$options{'exclude_incompletes'} = $q->param('exclude_incompletes');
	$options{'count_only'}          = 1;
	my $seq_count = $self->_get_seqs( $locus, $ids, \%options );

	if ( $seq_count <= MAX_INSTANT_RUN ) {
		$options{'count_only'} = 0;
		my $seqs = $self->_get_seqs( $locus, $ids, \%options );
		if ( !@$seqs ) {
			say qq(<div class="box" id="statusbad"><p>There are no $locus alleles in your selection.</p></div>);
			return;
		}
		say q(<div class="box" id="resultspanel">);
		my ( $buffer, $freqs ) = $self->get_snp_schematic( $locus, $seqs, undef, $self->{'prefs'}->{'alignwidth'} );
		say $buffer;
		say q(</div>);
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		( $buffer, undef ) = $self->get_freq_table( $freqs, $locus_info );
		say $buffer if $buffer;
		say q(</div>);
	} elsif ( $seq_count <= MAX_SEQUENCES ) {

		#Make sure query file is accessible to job host (the web server and job host may not be the same machine)
		#These machines should share the tmp_dir but not the secure_tmp_dir, so copy this over to the tmp_dir.
		if ( defined $query_file && !-e "$self->{'config'}->{'tmp_dir'}/$query_file" ) {
			if ( $query_file =~ /^(BIGSdb[\d_]*\.txt)$/x ) {
				$query_file = $1;    #untaint
			}
			copy( "$self->{'config'}->{'secure_tmp_dir'}/$query_file", "$self->{'config'}->{'tmp_dir'}/$query_file" )
			  || $logger->error("Can't copy $query_file");
		}
		if ( defined $list_file && !-e "$self->{'config'}->{'tmp_dir'}/$list_file" ) {
			if ( $list_file =~ /^(BIGSdb[\d_]*\.list)$/x ) {
				$list_file = $1;     #untaint
			}
			copy( "$self->{'config'}->{'secure_tmp_dir'}/$list_file", "$self->{'config'}->{'tmp_dir'}/$list_file" )
			  || $logger->error("Can't copy $list_file");
		}
		my $params = $q->Vars;
		$params->{'alignwidth'} = $self->{'prefs'}->{'alignwidth'};
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		my $job_id    = $self->{'jobManager'}->add_job(
			{
				dbase_config => $self->{'instance'},
				ip_address   => $q->remote_host,
				module       => 'Polymorphisms',
				parameters   => $params,
				username     => $self->{'username'},
				email        => $user_info->{'email'}
			}
		);
		say q(<div class="box" id="resultstable">)
		  . q(<p>This analysis has been submitted to the job queue.</p>)
		  . q(<p>Please be aware that this job may take a long time depending on the number of )
		  . q(sequences to align and how busy the server is.</p>)
		  . q(<p>Since alignment is offloaded to a third-party application, the progress report )
		  . q(will not be accurate.</p>)
		  . qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=job&amp;id=$job_id">Follow the progress of this job and view the output.</a></p></div>);
		return;
	} else {
		my $max      = MAX_SEQUENCES;
		my $num_seqs = @$ids;
		say q(<div class="box" id="statusbad"><p>This analysis relies are being able to produce )
		  . q(an alignment of your sequences. This is a potentially processor- and memory-intensive operation )
		  . qq(for large numbers of sequences and is consequently limited to $max records.  You have $num_seqs )
		  . q(records in your analysis.</p></div>);
	}
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	my $query_file = $params->{'query_file'};
	my $list_file  = $params->{'list_file'};

	#Make sure query file is accessible to job host (the web server and job host may not be the same machine)
	#These machines should share the tmp_dir but not the secure_tmp_dir, so copy this from the tmp_dir.
	if ( $query_file && !-e "$self->{'config'}->{'secure_tmp_dir'}/$query_file" ) {
		if ( $query_file =~ /^(BIGSdb[\d_]*\.txt)$/x ) {
			$query_file = $1;    #untaint
		}
		copy( "$self->{'config'}->{'tmp_dir'}/$query_file", "$self->{'config'}->{'secure_tmp_dir'}/$query_file" )
		  || $logger->error("Can't copy $query_file");
	}
	if ( $list_file && !-e "$self->{'config'}->{'secure_tmp_dir'}/$list_file" ) {
		if ( $list_file =~ /^(BIGSdb[\d_]*\.list)$/x ) {
			$list_file = $1;     #untaint
		}
		copy( "$self->{'config'}->{'tmp_dir'}/$list_file", "$self->{'config'}->{'secure_tmp_dir'}/$list_file" )
		  || $logger->error("Can't copy $list_file");
	}
	if ( $params->{'datatype'} && $params->{'list_file'} ) {
		$self->{'datastore'}->create_temp_list_table( $params->{'datatype'}, $params->{'list_file'} );
	}
	my $locus = $params->{'locus'};
	$locus =~ s/^cn_//x;
	$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => -1 } );    #indeterminate length of time
	my $qry_ref = $self->get_query($query_file);
	my $ids     = $self->get_ids_from_query($qry_ref);
	my %options;
	$options{'from_bin'}            = $params->{'chooseseq'} eq 'seqbin' ? 1 : 0;
	$options{'unique'}              = $params->{'unique'};
	$options{'exclude_incompletes'} = $params->{'exclude_incompletes'};
	my $seqs = $self->_get_seqs( $locus, $ids, \%options );

	if ( !@$seqs ) {
		$self->{'jobManager'}
		  ->update_job_status( $job_id, { message_html => '<p>No sequences retrieved for analysis.</p>' } );
		return;
	}
	my $temp      = BIGSdb::Utils::get_random();
	my $html_file = "$self->{'config'}->{tmp_dir}/$temp.html";
	my ( $buffer, $freqs ) = $self->get_snp_schematic( $locus, $seqs, undef, $params->{'alignwidth'} );
	open( my $html_fh, '>', $html_file ) || $logger->error("Can't open $html_file for writing");
	say $html_fh $self->get_html_header($locus);
	say $html_fh q(<h1>Polymorphic site analysis</h1><div class="box" id="resultspanel">);
	say $html_fh $buffer;
	say $html_fh q(</div>);
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	( $buffer, undef ) = $self->get_freq_table( $freqs, $locus_info );
	say $html_fh $buffer;
	say $html_fh q(</div></body></html>);
	$self->{'jobManager'}
	  ->update_job_output( $job_id, { filename => "$temp.html", description => 'Locus schematic (HTML format)' } );
	return;
}

#Options: count_only - don't align, just count how many sequences would be included.
#         unique - only include one example of each allele.
#         from_bin - choose sequences from seqbin in preference to allele from external db.
#		  exclude_incompletes - don't include incomplete sequences.
sub _get_seqs {
	my ( $self, $locus_name, $isolate_ids, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $locus_info = $self->{'datastore'}->get_locus_info($locus_name);
	my $locus;
	try {
		$locus = $self->{'datastore'}->get_locus($locus_name);
	}
	catch BIGSdb::BIGSException with {
		$logger->error("Invalid locus '$locus_name'");
		return;
	};
	my %used;
	my $temp     = BIGSdb::Utils::get_random();
	my $tempfile = "$self->{'config'}->{'secure_tmp_dir'}/$temp.txt";
	open( my $fh, '>', $tempfile ) or $logger->error("could not open temp file $tempfile");
	my $i = 0;
	foreach my $id (@$isolate_ids) {
		my $exclude_clause = $options->{'exclude_incompletes'} ? ' AND complete ' : '';
		my $qry =
		    'SELECT substring(sequence from start_pos for end_pos-start_pos+1),reverse FROM '
		  . 'allele_sequences LEFT JOIN sequence_bin ON allele_sequences.seqbin_id = sequence_bin.id WHERE '
		  . "sequence_bin.isolate_id=? AND locus=? $exclude_clause ORDER BY complete "
		  . 'desc,allele_sequences.datestamp LIMIT 1';
		my ( $seqbin_seq, $reverse ) =
		  $self->{'datastore'}->run_query( $qry, [ $id, $locus_name ], { cache => 'Polymorphisms::get_seqs' } );
		if ($reverse) {
			$seqbin_seq = BIGSdb::Utils::reverse_complement($seqbin_seq);
		}

		#TODO Only a single seqbin sequence is compared against each allele designation.  Ideally we would use every
		#sequence, but this may need to wait until we can link designations with sequence bin tags.
		my $allele_ids = $self->{'datastore'}->get_allele_ids( $id, $locus_name );
		my $allele_seq;
		push @$allele_ids, 0 if !@$allele_ids;    #We still need to get the seqbin seqs if no allele ids are set.
		foreach my $allele_id (@$allele_ids) {
			if ( $allele_id ne '0' && $locus_info->{'data_type'} eq 'DNA' ) {
				try {
					$allele_seq = $locus->get_allele_sequence($allele_id);
				}
				catch BIGSdb::DatabaseConnectionException with {

					#do nothing
				};
			}
			my $seq;
			if ( ref $allele_seq && $$allele_seq && $seqbin_seq ) {
				$seq = $options->{'from_bin'} ? $seqbin_seq : $$allele_seq;
			} elsif ( ref $allele_seq && $$allele_seq && !$seqbin_seq ) {
				$seq = $$allele_seq;
			} elsif ($seqbin_seq) {
				$seq = $seqbin_seq;
			}
			if ( $seq && !$used{$seq} ) {
				$i++;
				say $fh ">seq$i\n$seq" if !$used{$seq};
				$used{$seq} = 1 if $options->{'unique'};
			}
		}
	}
	close $fh;
	if ( $options->{'count_only'} ) {
		unlink $tempfile;
		return $i;
	}
	my $aligned_file = "$self->{'config'}->{secure_tmp_dir}/$temp.aligned";
	if ( $i > 1 ) {
		if ( -x $self->{'config'}->{'mafft_path'} ) {
			my $threads =
			  BIGSdb::Utils::is_int( $self->{'config'}->{'mafft_threads'} ) ? $self->{'config'}->{'mafft_threads'} : 1;
			system(
				"$self->{'config'}->{'mafft_path'} --thread $threads --quiet --preservecase $tempfile > $aligned_file");
		} elsif ( -x $self->{'config'}->{'muscle_path'} ) {
			system( $self->{'config'}->{'muscle_path'}, '-quiet', ( -in => $tempfile, -fastaout => $aligned_file ) );
		}
	}
	my $output_file = $i > 1 ? $aligned_file : $tempfile;
	my @seqs;
	if ( -e $output_file ) {
		my $seqio_object = Bio::SeqIO->new( -file => $output_file, -format => 'Fasta' );
		while ( my $seq_object = $seqio_object->next_seq ) {
			push @seqs, $seq_object->seq;
		}
	}
	unlink $tempfile;
	unlink $aligned_file;
	return \@seqs;
}

sub _print_interface {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $view   = $self->{'system'}->{'view'};
	my $set_id = $self->get_set_id;
	my ( $loci, $cleaned ) = $self->{'datastore'}->get_locus_list( { set_id => $set_id, analysis_pref => 1 } );
	if ( !@$loci ) {
		say q(<div class="box" id="statusbad"><p>No loci have been defined for this database.</p></div>);
		return;
	}
	my $max = MAX_INSTANT_RUN;
	say q(<div class="box" id="queryform">);
	say q(<p>This tool will analyse the polymorphic sites in the selected locus for the current isolate dataset.</p>);
	say qq(<p>If more than $max sequences have been selected, the job will be run by the offline job manager which may )
	  . q(take a few minutes (or longer depending on the queue).  This is because sequences may have gaps in them and )
	  . q(consequently need to be aligned which is a processor- and memory- intensive operation.</p>);
	say q(<div class="scrollable">);
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Loci</legend>);
	say $q->scrolling_list(
		-name     => 'locus',
		-id       => 'locus',
		-values   => $loci,
		-labels   => $cleaned,
		-size     => 8,
		-required => 'required'
	);
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Options</legend>);
	say q(If both allele designations and tagged sequences<br />)
	  . q(exist for a locus, choose how you want these handled: );
	say q[ <a class="tooltip" title="Sequence retrieval - Peptide loci will only be retrieved from ]
	  . q[the sequence bin (as nucleotide sequences)."><span class="fa fa-info-circle"></span></a>];
	say q(<br /><br />);
	say q(<ul><li>);
	my %labels = (
		seqbin             => 'Use sequences tagged from the bin',
		allele_designation => 'Use allele sequence retrieved from external database'
	);
	say $q->radio_group(
		-name      => 'chooseseq',
		-values    => [qw(allele_designation seqbin)],
		-labels    => \%labels,
		-linebreak => 'true'
	);
	say q(</li><li style="margin-top:1em">);
	say $q->checkbox(
		-name    => 'unique',
		-label   => 'Analyse single example of each unique sequence',
		-checked => 'checked'
	);
	say q(</li><li>);
	say $q->checkbox( -name => 'exclude_incompletes', -label => 'Exclude incomplete sequences', -checked => 'checked' );
	say q(</li></ul>);
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Analyse' } );
	say $q->hidden($_) foreach qw (page name db query_file list_file datatype);
	say $q->end_form;
	say q(</div></div>);
	return;
}
1;
