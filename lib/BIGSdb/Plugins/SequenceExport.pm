#SequenceExport.pm - Export concatenated sequences/XMFA file plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2024, University of Oxford
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
package BIGSdb::Plugins::SequenceExport;
use strict;
use warnings;
use parent qw(BIGSdb::Plugin);
use 5.010;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Try::Tiny;
use List::MoreUtils qw(any none uniq);
use Bio::Seq;
use Bio::SeqIO;
use Bio::AlignIO;
use Time::HiRes qw(time);
use BIGSdb::Utils;
use BIGSdb::Constants qw(LOCUS_PATTERN :interface :limits);
use constant DEFAULT_ALIGN_LIMIT => 200;
use constant DEFAULT_SEQ_LIMIT   => 1_000_000;
use constant SEQ_SOURCE          => 'seqbin id + position';

sub get_attributes {
	my ($self) = @_;
	my $seqdef = ( $self->{'system'}->{'dbtype'} // q() ) eq 'sequences';
	my %att    = (
		name    => 'Sequence Export',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			}
		],
		description      => 'Export concatenated allele sequences in XMFA and FASTA formats',
		full_description => 'This plugin creates concatenated XMFA and FASTA files of selected loci for a particular '
		  . 'dataset. These sequences can optionally be aligned, using either MAFFT or MUSCLE, facilitating quick '
		  . 'analysis of the outputs in third-party phylogenetic analysis packages.',
		category           => 'Export',
		buttontext         => 'Sequences',
		menutext           => $seqdef ? 'Profile sequences' : 'Sequences',
		module             => 'SequenceExport',
		version            => '1.9.2',
		dbtype             => 'isolates,sequences',
		seqdb_type         => 'schemes',
		section            => 'isolate_info,profile_info,export,postquery',
		url                => "$self->{'config'}->{'doclink'}/data_export/sequence_export.html",
		input              => 'query',
		help               => 'tooltips',
		requires           => $seqdef ? 'aligner,offline_jobs' : 'aligner,offline_jobs,js_tree',
		image              => '/images/plugins/SequenceExport/screenshot.png',
		order              => 22,
		system_flag        => 'SequenceExport',
		enabled_by_default => 1
	);
	return \%att;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 1, query_field => 0 };
	return;
}

sub get_initiation_values {
	my ($self) = @_;
	return { 'jQuery.jstree' => ( $self->{'system'}->{'dbtype'} eq 'isolates' ? 1 : 0 ), 'jQuery.multiselect' => 1 };
}

sub run {
	my ($self)        = @_;
	my $q             = $self->{'cgi'};
	my $query_file    = $q->param('query_file');
	my $scheme_id     = $q->param('scheme_id');
	my $max_seqs      = $self->{'system'}->{'seq_export_limit'} // DEFAULT_SEQ_LIMIT;
	my $commified_max = BIGSdb::Utils::commify($max_seqs);
	say q(<h1>Export allele sequences in XMFA/concatenated FASTA formats</h1>);
	if ( ( $self->{'system'}->{'SequenceExport'} // q() ) eq 'no' ) {
		$self->print_bad_status( { message => q(Sequence exports are disabled.) } );
		return;
	}
	return if $self->has_set_changed;
	my $pk;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$pk = 'id';
	} else {
		return if defined $scheme_id && $self->is_scheme_invalid( $scheme_id, { with_pk => 1 } );
		if ( !$q->param('submit') ) {
			$self->print_scheme_section( { with_pk => 1 } );
			$scheme_id = $q->param('scheme_id');    #Will be set by scheme section method
		}
		if ( !defined $scheme_id ) {
			$self->print_bad_status( { message => q(Invalid scheme selected.), navbar => 1 } );
			return;
		}
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		$pk = $scheme_info->{'primary_key'};
	}
	my $limit = $self->_get_limit;
	if ( $q->param('submit') ) {
		my $loci_selected = $self->get_selected_loci;
		my ( $pasted_cleaned_loci, $invalid_loci ) = $self->get_loci_from_pasted_list;
		$q->delete('locus');
		push @$loci_selected, @$pasted_cleaned_loci;
		@$loci_selected = uniq @$loci_selected;
		$self->add_scheme_loci($loci_selected);
		if (@$invalid_loci) {
			local $" = q(, );
			$self->print_bad_status(
				{ message => qq(The following loci in your pasted list are invalid: @$invalid_loci.) } );
		} elsif ( !@$loci_selected ) {
			my $msg = q(You must select one or more loci);
			$msg .= q( or schemes) if $self->{'system'}->{'dbtype'} eq 'isolates';
			$self->print_bad_status( { message => $msg } );
		} elsif ( $self->attempted_spam( \( scalar $q->param('list') ) ) ) {
			$self->print_bad_status( { message => q(Invalid data detected in list.) } );
		} else {
			$self->set_scheme_param;
			my $params = $q->Vars;
			$params->{'pk'}     = $pk;
			$params->{'set_id'} = $self->get_set_id;
			$params->{'curate'} = 1 if $self->{'curate'};
			my @list = split /[\r\n]+/x, $q->param('list');
			@list = uniq @list;
			if ( !@list ) {
				if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
					my $qry     = "SELECT id FROM $self->{'system'}->{'view'} ORDER BY id";
					my $id_list = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
					@list = @$id_list;
				} else {
					my $pk_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $pk );
					my $qry     = 'SELECT profile_id FROM profiles WHERE scheme_id=? ORDER BY ';
					$qry .= $pk_info->{'type'} eq 'integer' ? 'CAST(profile_id AS INT)' : 'profile_id';
					my $id_list = $self->{'datastore'}->run_query( $qry, $scheme_id, { fetch => 'col_arrayref' } );
					@list = @$id_list;
				}
			}
			my $total_seqs = @$loci_selected * @list;
			if ( $total_seqs > $max_seqs ) {
				my $commified_total = BIGSdb::Utils::commify($total_seqs);
				$self->print_bad_status(
					{
						message => qq(Output is limited to a total of $commified_max sequences )
						  . qq((records x loci). You have selected $commified_total.),
					}
				);
				return;
			}
			my $record_count = @list;
			if ( $record_count > $limit && $q->param('align') ) {
				$self->print_bad_status(
					{
						message => qq(Aligned output is limited to a total of $limit )
						  . qq(records. You have selected $record_count.),
					}
				);
				return;
			}
			my $list_type = $self->{'system'}->{'dbtype'} eq 'isolates' ? 'isolates' : 'profiles';
			$q->delete('list');
			my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
			my $job_id    = $self->{'jobManager'}->add_job(
				{
					dbase_config => $self->{'instance'},
					ip_address   => $q->remote_host,
					module       => 'SequenceExport',
					parameters   => $params,
					username     => $self->{'username'},
					email        => $user_info->{'email'},
					loci         => $loci_selected,
					$list_type   => \@list
				}
			);
			say $self->get_job_redirect($job_id);
			return;
		}
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say q(<div class="box" id="queryform">);
		say q(<p>This script will export allele sequences in Extended Multi-FASTA (XMFA) format suitable for )
		  . q(loading into third-party applications, such as ClonalFrame.  It will also produce concatenated )
		  . q(FASTA files. Only DNA loci that have a corresponding database containing allele sequence identifiers, )
		  . q(or DNA and peptide loci with genome sequences tagged, can be included. Please check the loci that you )
		  . q(would like to include.  Alternatively select one or more schemes to include all loci that are members )
		  . q(of the scheme.  If a sequence does not exist in the remote database, it will be replaced with )
		  . q(gap characters.</p>);
		say qq(<p>Aligned output is limited to $limit records; total output (records x loci) is )
		  . qq(limited to $commified_max sequences.</p>);
		say q(<p>Please be aware that if you select the alignment option it may take a long time )
		  . q(to generate the output file.</p>);
	} else {
		say q(<div class="box" id="queryform">);
		say q(<p>This script will export allele sequences in Extended Multi-FASTA (XMFA) format suitable )
		  . q(for loading into third-party applications, such as ClonalFrame.</p>);
		say qq(<p>Aligned Output is limited to $limit records; total output (records x loci) is limited to )
		  . qq($commified_max sequences.</p>);
		say q(<p>Please be aware that if you select the alignment option it may take a long time to )
		  . q(generate the output file.</p>);
	}
	my $list = $self->get_id_list( $pk, $query_file );
	if ( !@$list && BIGSdb::Utils::is_int( scalar $q->param('single_isolate') ) ) {
		$list = [ scalar $q->param('single_isolate') ];
	}
	$self->_print_interface( $pk, $list, $scheme_id );
	say q(</div>);
	return;
}

sub _print_interface {
	my ( $self, $pk, $list, $scheme_id ) = @_;
	$logger->error('No primary key passed') if !defined $pk;
	my $q = $self->{'cgi'};
	say $q->start_form;
	say q(<div class="flex_container" style="justify-content:left">);
	$self->print_id_fieldset( { fieldname => $pk, list => $list } );
	$self->_print_includes_fieldset($scheme_id);

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->print_isolates_locus_fieldset( { no_all_none => 1, locus_paste_list => 1 } );
		$self->print_scheme_fieldset;
	} else {
		$self->print_scheme_locus_fieldset( $scheme_id, { no_all_none => 1 } );
	}
	say q(<fieldset style="float:left"><legend>Options</legend>);
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say q(<p>If both allele designations and tagged sequences<br />)
		  . q(exist for a locus, choose how you want these handled: );
		say $self->get_tooltip( q(Sequence retrieval - Peptide loci will only be retrieved from the )
			  . q(sequence bin (as nucleotide sequences).) );
		say q(</p><ul><li>);
		my %labels = (
			seqbin             => 'Use sequences tagged from the bin',
			allele_designation => 'Use allele sequence retrieved from external database'
		);
		say $q->radio_group(
			-name      => 'chooseseq',
			-values    => [ 'seqbin', 'allele_designation' ],
			-labels    => \%labels,
			-linebreak => 'true'
		);
		say q(</li><li style="margin-top:0.5em">);
		say $q->checkbox(
			-name    => 'ignore_seqflags',
			-label   => 'Do not include sequences with problem flagged (defined alleles will still be used)',
			-checked => 'checked'
		);
		say q(</li><li>);
		say $q->checkbox(
			-name    => 'ignore_incomplete',
			-label   => 'Do not include incomplete sequences',
			-checked => 'checked'
		);
		say q(</li><li>);
		say q(Include );
		say $q->popup_menu( -name => 'flanking', -values => [FLANKING], -default => 0 );
		say q( bp flanking sequence);
		say $self->get_tooltip( q(Flanking sequence - This can only be included if you )
			  . q(select to retrieve sequences from the sequence bin rather than from an external database.) );
		say q(</li>);
	} else {
		say q(<ul>);
	}
	if ( !-x $self->{'config'}->{'muscle_path'} && !-x $self->{'config'}->{'mafft_path'} ) {
		$logger->error( 'This plugin requires an aligner (MAFFT or MUSCLE) to be installed and one is not. '
			  . 'Please install one of these or check the settings in bigsdb.conf.' );
	} else {
		say q(<li>);
		say $q->checkbox( -name => 'align', -id => 'align', -label => 'Align sequences' );
		say q(</li>);
		my @aligners;
		foreach my $aligner (qw(mafft muscle)) {
			push @aligners, uc($aligner) if $self->{'config'}->{"$aligner\_path"};
		}
		if (@aligners) {
			say q(<li>Aligner: );
			say $q->popup_menu( -name => 'aligner', -id => 'aligner', -values => \@aligners );
			say q(</li>);
		}
	}
	say q(<li>);
	say $q->checkbox( -name => 'translate', -label => 'Translate sequences' );
	say q(</li>);
	say q(<li>);
	say $q->checkbox( -name => 'in_frame', -label => 'Concatenate in frame' );
	say q(</li>);
	say q(</ul></fieldset>);
	$self->print_action_fieldset( { no_reset => 1 } );
	say q(<div style="clear:both"></div>);
	my $set_id = $self->get_set_id;
	$q->param( set_id => $set_id );
	say $q->hidden($_) foreach qw (db page name query_file scheme_id set_id list_file datatype);
	say q(</div>);
	say $q->end_form;
	return;
}

sub _print_includes_fieldset {
	my ( $self, $scheme_id ) = @_;
	my $q = $self->{'cgi'};
	my ( @fields, $labels );
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->print_includes_fieldset(
			{
				isolate_fields => 1,
				scheme_fields  => 1,
				analysis_pref  => 1,
				title          => 'Include in identifier',
				size           => 7,
				additional     => [SEQ_SOURCE]
			}
		);
	} else {
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		my $scheme_info   = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		foreach (@$scheme_fields) {
			push @fields, $_ if $_ ne $scheme_info->{'primary_key'};
		}
		if (@fields) {
			say q(<fieldset style="float:left"><legend>Include in identifier</legend>);
			say $q->scrolling_list(
				-name     => 'include_fields',
				-id       => 'include_fields',
				-values   => \@fields,
				-labels   => $labels,
				-size     => 7,
				-multiple => 'true'
			);
			say q(</fieldset>);
		}
	}
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	$self->set_offline_view($params);
	$self->{'exit'} = 0;
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1 } ) x 3; #Allow temp files to be cleaned on kill signals
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->_run_job_isolates( $job_id, $params );
	} else {
		$self->_run_job_profiles( $job_id, $params );
	}
	return;
}

sub _get_includes {
	my ( $self, $params ) = @_;
	my @includes;
	if ( $params->{'include_fields'} ) {
		my $separator = '\|\|';
		@includes = split /$separator/x, $params->{'include_fields'};
	}
	return \@includes;
}

sub _get_limit {
	my ($self) = @_;
	my $limit = $self->{'system'}->{'XMFA_limit'} // $self->{'system'}->{'align_limit'} // DEFAULT_ALIGN_LIMIT;
	return $limit;
}

sub _run_job_profiles {
	my ( $self, $job_id, $params ) = @_;
	my $scheme_id = $params->{'scheme_id'};
	my $pk        = $params->{'pk'};
	my $filename  = "$self->{'config'}->{'tmp_dir'}/$job_id\.xmfa";
	open( my $fh, '>', $filename )
	  or $logger->error("Can't open output file $filename for writing");
	my $includes       = $self->_get_includes($params);
	my $problem_ids    = [];
	my $restricted_ids = [];
	my %problem_id_checked;
	my $start = 1;
	my $end;
	my $no_output        = 1;
	my $loci             = $self->{'jobManager'}->get_job_loci($job_id);
	my $selected_loci    = $self->order_loci( $loci, { scheme_id => $scheme_id } );
	my $ids              = $self->{'jobManager'}->get_job_profiles( $job_id, $scheme_id );
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $job              = $self->{'jobManager'}->get_job($job_id);
	my $date_restriction = $self->{'datastore'}->get_date_restriction;
	my $progress         = 0;

	foreach my $locus_name (@$selected_loci) {
		last if $self->{'exit'};
		my $output_locus_name = $self->clean_locus( $locus_name, { text_output => 1, no_common_name => 1 } );
		$self->{'jobManager'}->update_job_status( $job_id, { stage => "Processing $output_locus_name" } );
		my %no_seq;
		my $locus;
		my $locus_info = $self->{'datastore'}->get_locus_info($locus_name);
		try {
			$locus = $self->{'datastore'}->get_locus($locus_name);
		} catch {
			if ( $_->isa('BIGSdb::Exception::Data') ) {
				$logger->warn("Invalid locus '$locus_name' passed.");
			} else {
				$logger->logdie($_);
			}
		};
		my $temp         = BIGSdb::Utils::get_random();
		my $temp_file    = "$self->{'config'}->{secure_tmp_dir}/$temp.txt";
		my $aligned_file = "$self->{'config'}->{secure_tmp_dir}/$temp.aligned";
		open( my $fh_unaligned, '>', "$temp_file" ) or $logger->error("could not open temp file $temp_file");
		foreach my $id (@$ids) {
			my $profile_data = $self->{'datastore'}->run_query( "SELECT * FROM $scheme_warehouse WHERE $pk=?",
				$id, { fetch => 'row_hashref', cache => 'SequenceExport::run_job_profiles::profile_data' } );
			my $profile_id = $profile_data->{ lc($pk) };
			my $header;
			if ( defined $profile_id ) {
				if ( !$job->{'username'} && $date_restriction && $date_restriction lt $profile_data->{'date_entered'} )
				{
					push @$restricted_ids, $profile_id if !$problem_id_checked{$id};
					$problem_id_checked{$id} = 1;
					next;
				}
				$header = ">$profile_id";
				if (@$includes) {
					foreach my $field (@$includes) {
						my $value = $profile_data->{ lc($field) } // '';
						$value =~ tr/[\(\):, ]/_/;
						$header .= "|$value";
					}
				}
				my $allele_id =
				  $self->{'datastore'}->get_profile_allele_designation( $scheme_id, $id, $locus_name )->{'allele_id'};
				my $allele_seq_ref = $self->{'datastore'}->get_sequence( $locus_name, $allele_id );
				say $fh_unaligned $header;
				if ( $allele_id eq '0' || $allele_id eq 'N' || $allele_id eq 'P' ) {
					say $fh_unaligned 'N';
					$no_seq{$id} = 1;
				} else {
					my $seq = $self->_translate_seq_if_required( $params, $locus_info, $$allele_seq_ref );
					say $fh_unaligned $seq;
				}
			} else {
				push @$problem_ids, $id if !$problem_id_checked{$id};
				$problem_id_checked{$id} = 1;
				next;
			}
		}
		close $fh_unaligned;
		$self->{'db'}->commit;    #prevent idle in transaction table locks
		$self->_append_sequences(
			{
				fh                => $fh,
				output_locus_name => $output_locus_name,
				params            => $params,
				aligned_file      => $aligned_file,
				temp_file         => $temp_file,
				start             => \$start,
				end               => \$end,
				no_output_ref     => \$no_output,
				no_seq            => \%no_seq
			}
		);
		$progress++;
		my $complete = int( 100 * $progress / scalar @$selected_loci );
		$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => $complete } );
	}
	close $fh;
	if ( $self->{'exit'} ) {
		$self->{'jobManager'}->update_job_status( $job_id, { status => 'terminated' } );
		unlink $filename;
		return;
	}
	$self->_output(
		{
			job_id         => $job_id,
			params         => $params,
			problem_ids    => $problem_ids,
			restricted_ids => $restricted_ids,
			no_output      => $no_output,
			filename       => $filename
		}
	);
	return;
}

sub _run_job_isolates {
	my ( $self, $job_id, $params ) = @_;
	my $filename      = "$self->{'config'}->{'tmp_dir'}/$job_id.xmfa";
	my $loci          = $self->{'jobManager'}->get_job_loci($job_id);
	my $selected_loci = $self->order_loci($loci);
	my $ids           = $self->{'jobManager'}->get_job_isolates($job_id);
	my $ret_val       = $self->_make_isolate_seq_file(
		{
			job_id       => $job_id,
			params       => $params,
			ids          => $ids,
			loci         => $selected_loci,
			filename     => $filename,
			max_progress => 100
		}
	);
	if ( $self->{'exit'} ) {
		$self->{'jobManager'}->update_job_status( $job_id, { status => 'terminated' } );
		unlink $filename;
		return;
	}
	$self->_output(
		{
			job_id      => $job_id,
			params      => $params,
			problem_ids => $ret_val->{'problem_ids'},
			no_output   => $ret_val->{'no_output'},
			filename    => $filename
		}
	);
	return;
}

sub _make_isolate_seq_file {
	my ( $self, $args ) = @_;
	my ( $job_id, $params, $ids, $loci, $filename, $max_progress ) =
	  @$args{qw(job_id params ids loci filename max_progress)};
	my $problem_ids    = {};
	my $includes       = $self->_get_includes($params);
	my %field_included = map { $_ => 1 } @$includes;
	my $tag_data       = $self->_get_tag_data( $ids, $loci, $params );

	#round up to the nearest multiple of 3 if translating sequences to keep in reading frame
	$params->{'flanking'} = 0 if !BIGSdb::Utils::is_int( $params->{'flanking'} );
	my $flanking =
	  $params->{'translate'}
	  ? BIGSdb::Utils::round_to_nearest( $params->{'flanking'}, 3 )
	  : $params->{'flanking'};
	my $start = 1;
	my $end;
	my $no_output = 1;
	my $progress  = 0;
	open( my $fh, '>', $filename )
	  or $logger->error("Can't open output file $filename for writing");
	my $last_update_time = 0;
  LOCUS: foreach my $locus_name (@$loci) {
		last if $self->{'exit'};
		my $output_locus_name = $self->clean_locus( $locus_name, { text_output => 1, no_common_name => 1 } );
		if ( time - $last_update_time > 2 ) {    #No need to update job db too often.
			my $complete = int( $max_progress * $progress / scalar @$loci );
			$self->{'jobManager'}->update_job_status( $job_id,
				{ stage => "Processing $output_locus_name", percent_complete => $complete } );
			$last_update_time = time;
		}
		my %no_seq;
		my $locus;
		my $locus_info = $self->{'datastore'}->get_locus_info($locus_name);
		try {
			$locus = $self->{'datastore'}->get_locus($locus_name);
		} catch {
			if ( $_->isa('BIGSdb::Exception::Data') ) {
				$logger->warn("Invalid locus '$locus_name' passed.");
			} else {
				$logger->logdie($_);
			}
		};
		my $temp         = BIGSdb::Utils::get_random();
		my $temp_file    = "$self->{'config'}->{secure_tmp_dir}/$temp.txt";
		my $aligned_file = "$self->{'config'}->{secure_tmp_dir}/$temp.aligned";
		open( my $fh_unaligned, '>:encoding(utf8)', $temp_file )
		  or $logger->error("could not open temp file $temp_file");
	  ISOLATE: foreach my $id (@$ids) {
			my $include_values = [];
			try {
				$include_values = $self->_get_included_values( $includes, $id, $problem_ids );
			} catch {
				no warnings 'exiting';
				next ISOLATE;
			};
			my $allele_seq = $self->_get_allele_seq( $id, $locus, $locus_name, $locus_info );
			my $seqbin_seq;
			my $seqbin_pos = q();
			my $tag        = $tag_data->{$locus_name}->{$id};
			if ( $tag->{'seqbin_id'} ) {
				my ( $reverse, $seqbin_id, $start_pos, $end_pos ) = @{$tag}{qw(reverse seqbin_id start_pos end_pos)};
				my $seq_ref = $self->{'contigManager'}->get_contig_fragment(
					{
						seqbin_id => $seqbin_id,
						start     => $start_pos,
						end       => $end_pos,
						reverse   => $reverse,
						flanking  => $flanking
					}
				);
				my $five_prime  = $reverse ? 'downstream' : 'upstream';
				my $three_prime = $reverse ? 'upstream'   : 'downstream';
				$seqbin_seq .= $seq_ref->{$five_prime} if $seq_ref->{$five_prime};
				$seqbin_seq .= $seq_ref->{'seq'};
				$seqbin_seq .= $seq_ref->{$three_prime} if $seq_ref->{$three_prime};
				$seqbin_pos = "${seqbin_id}_$start_pos" if $seqbin_seq;
			}
			my $seq;
			my $pos_include_value;
			if ( $allele_seq && $seqbin_seq ) {
				if ( $params->{'chooseseq'} eq 'seqbin' ) {
					$seq               = $seqbin_seq;
					$pos_include_value = $seqbin_pos;
				} else {
					$seq               = $allele_seq;
					$pos_include_value = 'defined_allele';
				}
			} elsif ($allele_seq) {
				$seq               = $allele_seq;
				$pos_include_value = 'defined_allele';
			} elsif ($seqbin_seq) {
				$seq               = $seqbin_seq;
				$pos_include_value = $seqbin_pos;
			} else {
				$seq               = 'N';
				$no_seq{$id}       = 1;
				$pos_include_value = 'no_seq';
			}
			my @local_include_values = @$include_values;    #Don't clobber
			if ( $field_included{&SEQ_SOURCE} ) {
				push @local_include_values, $pos_include_value;
				$self->{'seq_source'} = 1;
			}
			print $fh_unaligned ">$id";
			local $" = '|';
			print $fh_unaligned "|@local_include_values" if @$includes;
			print $fh_unaligned "\n";
			$seq = $self->_translate_seq_if_required( $params, $locus_info, $seq );
			say $fh_unaligned $seq;
		}
		close $fh_unaligned;
		$self->{'db'}->commit;    #prevent idle in transaction table locks
		$self->_append_sequences(
			{
				fh                => $fh,
				output_locus_name => $output_locus_name,
				params            => $params,
				aligned_file      => $aligned_file,
				temp_file         => $temp_file,
				start             => \$start,
				end               => \$end,
				no_output_ref     => \$no_output,
				no_seq            => \%no_seq
			}
		);
		$progress++;
	}
	close $fh;
	return { problem_ids => [ sort { $a <=> $b } keys %$problem_ids ], no_output => $no_output };
}

sub _get_allele_seq {
	my ( $self, $id, $locus, $locus_name, $locus_info ) = @_;
	my $allele_ids = $self->{'datastore'}->get_allele_ids( $id, $locus_name );
	my $allele_seq;
	if ( $locus_info->{'data_type'} eq 'DNA' ) {
		try {
			foreach my $allele_id ( sort @$allele_ids ) {
				next if $allele_id eq '0';
				my $seq = ${ $locus->get_allele_sequence($allele_id) };
				if ($seq) {
					$allele_seq .= $seq;
				} else {
					$logger->error("$self->{'system'}->{'db'} id-$id $locus_name-$allele_id does not exist.");
				}
			}
		} catch {
		};    #do nothing
	}
	return $allele_seq;
}

sub _get_included_values {
	my ( $self, $includes, $isolate_id, $problem_ids ) = @_;
	if ( defined $self->{'cache'}->{'includes'}->{$isolate_id} ) {
		return $self->{'cache'}->{'includes'}->{$isolate_id};
	}
	my $include_values = [];
	my $isolate_data   = $self->{'datastore'}->run_query( "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?",
		$isolate_id, { fetch => 'row_hashref', cache => 'SequenceExport::run_job_isolates::isolate_data' } );
	foreach my $field (@$includes) {
		next if $field eq SEQ_SOURCE;
		if ( $field =~ /^s_(\d+)_(.+)$/x ) {
			my ( $scheme_id, $scheme_field ) = ( $1, $2 );
			my $scheme_field_values =
			  $self->{'datastore'}->get_scheme_field_values_by_isolate_id( $isolate_id, $scheme_id );
			my @values = sort ( keys %{ $scheme_field_values->{ lc($scheme_field) } } );
			local $" = q(;);
			( my $string = qq(@values) ) =~ tr/ /_/;
			push @$include_values, $string;
		} elsif ( $field =~ /^f_(.+)$/x ) {
			my $value = $self->get_field_value( $isolate_data, $1 );
			push @$include_values, $value;
		}
	}
	if ( !$isolate_data->{'id'} ) {
		$problem_ids->{$isolate_id} = 1;
		BIGSdb::Exception::Database::NoRecord->throw;
	}
	$self->{'cache'}->{'includes'}->{$isolate_id} = $include_values;
	return $include_values;
}

sub _translate_seq_if_required {
	my ( $self, $params, $locus_info, $seq, $isolate_id ) = @_;
	if ( $locus_info->{'data_type'} eq 'DNA' ) {
		if ( $params->{'in_frame'} || $params->{'translate'} ) {
			$seq = BIGSdb::Utils::chop_seq( $seq, $locus_info->{'orf'} // 1 );
			if ( !length($seq) ) {
				$seq = 'NNN';
			}
		}
		if ( $params->{'translate'} ) {
			my $seq_obj = Bio::Seq->new( -seq => $seq, -alphabet => 'dna' );
			my $peptide;
			if ($seq) {
				my $codon_table = $self->{'datastore'}->get_codon_table($isolate_id);
				$peptide = $seq_obj->translate( -codontable_id => $codon_table )->seq;
			} else {
				$peptide = 'X';
			}
			return $peptide;
		}
	}
	return $seq;
}

sub _get_tag_data {
	my ( $self, $ids, $loci, $params ) = @_;
	my $temp_isolate_table = $self->{'datastore'}->create_temp_list_table_from_array( 'int',  $ids );
	my $temp_locus_table   = $self->{'datastore'}->create_temp_list_table_from_array( 'text', $loci );
	my $ignore_seqflags    = $params->{'ignore_seqflags'}   ? 'AND flag IS NULL' : '';
	my $ignore_incomplete  = $params->{'ignore_incomplete'} ? 'AND complete'     : '';
	my $data               = $self->{'datastore'}->run_query(
		'SELECT locus,isolate_id,reverse,seqbin_id,start_pos,end_pos FROM allele_sequences a '
		  . "JOIN $temp_isolate_table i ON a.isolate_id=i.value JOIN $temp_locus_table l ON a.locus=l.value "
		  . 'LEFT JOIN sequence_flags sf ON a.id=sf.id '
		  . "$ignore_seqflags $ignore_incomplete ORDER BY complete,a.datestamp",
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $ordered = {};
	foreach my $record (@$data) {
		if ( !defined $ordered->{ $record->{'locus'} }->{ $record->{'isolate_id'} } ) {
			$ordered->{ $record->{'locus'} }->{ $record->{'isolate_id'} } = {
				seqbin_id => $record->{'seqbin_id'},
				reverse   => $record->{'reverse'},
				start_pos => $record->{'start_pos'},
				end_pos   => $record->{'end_pos'}
			};
		}
	}
	return $ordered;
}

sub _output {
	my ( $self, $args ) = @_;
	my ( $job_id, $params, $problem_ids, $restricted_ids, $no_output, $filename ) =
	  @{$args}{qw(job_id params problem_ids restricted_ids no_output filename)};
	my $message_html;
	if (@$problem_ids) {
		local $" = ', ';
		$message_html = qq(<p>The following ids could not be processed (they do not exist): @$problem_ids.</p>\n);
	}
	if (ref $restricted_ids && @$restricted_ids) {
		local $" = ', ';
		$message_html .= q(<p>The following profiles are restricted and have been excluded - )
		  . qq(you need to log in to include these: @$restricted_ids.</p>\n);
	}
	if ($no_output) {
		$message_html .=
		  "<p>No output generated.  Please ensure that your sequences have been defined for these isolates.</p>\n";
	} else {
		my $align_qualifier = $params->{'align'} ? '(aligned)' : '(not aligned)';
		$self->{'jobManager'}->update_job_output(
			$job_id,
			{
				filename      => "$job_id.xmfa",
				description   => "10_XMFA output file $align_qualifier",
				compress      => 1,
				keep_original => 1                                         #Original needed to generate FASTA file
			}
		);
		try {
			$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Converting XMFA to FASTA' } );
			my $fasta_file = BIGSdb::Utils::xmfa2fasta( $filename, { strip_pos => $self->{'seq_source'} } );
			if ( -e $fasta_file ) {
				$self->{'jobManager'}->update_job_output(
					$job_id,
					{
						filename    => "$job_id.fas",
						description => "20_Concatenated FASTA $align_qualifier",
						compress    => 1
					}
				);
			}
		} catch {
			if ( $_->isa('BIGSdb::Exception::File::CannotOpen') ) {
				$logger->error('Cannot create FASTA file from XMFA.');
			} else {
				$logger->logdie($_);
			}
		};
		unlink $filename if -e "$filename.gz";
	}
	$self->{'jobManager'}->update_job_status( $job_id, { message_html => $message_html } ) if $message_html;
	return;
}

sub _append_sequences {
	my ( $self, $args ) = @_;
	my ( $fh, $output_locus_name, $params, $aligned_file, $temp_file, $start, $end, $no_output_ref, $no_seq ) =
	  @{$args}{qw(fh output_locus_name params aligned_file temp_file start end no_output_ref no_seq)};
	my $output_file;
	my $aligner = $params->{'aligner'};
	if ( !defined $aligner ) {
		foreach my $program (qw(mafft muscle)) {
			if ( $self->{'config'}->{"${program}_path"} ) {
				$aligner = $program;
				last;
			}
		}
	}
	if ( $params->{'align'} && $aligner eq 'MAFFT' && -e $temp_file && -s $temp_file ) {
		my $threads =
		  BIGSdb::Utils::is_int( $self->{'config'}->{'mafft_threads'} ) ? $self->{'config'}->{'mafft_threads'} : 1;
		system("$self->{'config'}->{'mafft_path'} --thread $threads --quiet --preservecase $temp_file > $aligned_file");
		$output_file = $aligned_file;
	} elsif ( $params->{'align'} && $aligner eq 'MUSCLE' && -e $temp_file && -s $temp_file ) {
		my $max_mb = $self->{'config'}->{'max_muscle_mb'} // MAX_MUSCLE_MB;
		system( $self->{'config'}->{'muscle_path'},
			-in    => $temp_file,
			-out   => $aligned_file,
			-maxmb => $max_mb,
			'-quiet'
		);
		$output_file = $aligned_file;
	} else {
		$output_file = $temp_file;
	}
	if ( -e $output_file && !-z $output_file ) {
		$$no_output_ref = 0;
		my $seq_in = Bio::SeqIO->new( -format => 'fasta', -file => $output_file );
		while ( my $seq = $seq_in->next_seq ) {
			my $length = $seq->length;
			$$end = $$start + $length - 1;
			print $fh '>' . $seq->id . ":$$start-$$end + $output_locus_name\n";
			my $sequence = BIGSdb::Utils::break_line( $seq->seq, 60 );
			( my $id = $seq->id ) =~ s/\|.*$//x;
			$sequence =~ s/N/-/g if $no_seq->{$id};
			say $fh $sequence;
		}
		$$start = ( $$end // 0 ) + 1;
		print $fh "=\n";
	}
	unlink $output_file;
	unlink $temp_file;
	return;
}

sub get_field_value {
	my ( $self, $isolate_data, $field ) = @_;
	my $value;
	$value = $isolate_data->{ lc($field) } // '';
	if ( ref $value eq 'ARRAY' ) {
		local $" = q(; );
		$value = qq(@$value);
	}
	$value =~ tr/ /_/;
	$value =~ tr/(/_/;
	$value =~ tr/)/_/;
	return $value;
}

sub get_plugin_javascript {
	my ($self) = @_;
	my $buffer = << "END";
function enable_aligner(){
	if (\$("#align").prop("checked")){
		\$("#aligner").prop("disabled", false);
	} else {
		\$("#aligner").prop("disabled", true);
	}
}
	
\$(function () {
	enable_aligner();
	\$("#align").change(function(e) {
		enable_aligner();
	});
	\$('#locus,#include_fields').multiselect({
		noneSelectedText: "",
 		classes: 'filter',
 		menuHeight: 250,
 		menuWidth: 400,
 		selectedList: 8
  	}).multiselectfilter({
		placeholder: 'Search'
	});
});
END
	return $buffer;
}
1;
