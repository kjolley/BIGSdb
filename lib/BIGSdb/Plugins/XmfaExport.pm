#XmfaExport.pm - Export XMFA file plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2012, University of Oxford
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
package BIGSdb::Plugins::XmfaExport;
use strict;
use warnings;
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use Apache2::Connection ();
use Bio::Perl;
use Bio::SeqIO;
use Bio::AlignIO;
use BIGSdb::Utils;
use constant DEFAULT_LIMIT => 200;

sub get_attributes {
	my %att = (
		name        => 'Xmfa Export',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Export allele sequences in XMFA format',
		category    => 'Export',
		buttontext  => 'XMFA',
		menutext    => 'XMFA export',
		module      => 'XmfaExport',
		version     => '1.2.2',
		dbtype      => 'isolates,sequences',
		seqdb_type  => 'schemes',
		section     => 'export,postquery',
		url         => 'http://pubmlst.org/software/database/bigsdb/userguide/isolates/xmfa.shtml',
		input       => 'query',
		help        => 'tooltips',
		requires    => 'muscle,offline_jobs,js_tree',
		order       => 22,
	);
	return \%att;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { 'general' => 1, 'main_display' => 0, 'isolate_display' => 0, 'analysis' => 1, 'query_field' => 0 };
	return;
}

sub run {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $scheme_id  = $q->param('scheme_id');
	print "<h1>Export allele sequences in XMFA format</h1>\n";
	if ( !-e $self->{'config'}->{'muscle_path'} || !-x $self->{'config'}->{'muscle_path'} ) {
		$logger->error( "This plugin requires MUSCLE to be installed and it is not.  Please install MUSCLE "
			  . "or check the settings in bigsdb.conf." );
	}
	my $list;
	my $qry_ref;
	my $pk;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$pk = 'id';
	} else {
		if ( !$scheme_id ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No scheme id passed.</p></div>\n";
			return;
		} elsif ( !BIGSdb::Utils::is_int($scheme_id) ) {
			print "<div class=\"box\" id=\"statusbad\"><p>Scheme id must be an integer.</p></div>\n";
			return;
		} else {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
			if ( !$scheme_info ) {
				print "<div class=\"box\" id=\"statusbad\">Scheme does not exist.</p></div>\n";
				return;
			}
		}
		my $pk_ref =
		  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE scheme_id=? AND primary_key", $scheme_id );
		if ( ref $pk_ref ne 'ARRAY' ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No primary key field has been set for this scheme.  Profile concatenation "
			  . "can not be done until this has been set.</p></div>\n";
			return;
		}
		$pk = $pk_ref->[0];
	}
	if ( $q->param('list') ) {
		foreach ( split /\n/, $q->param('list') ) {
			chomp;
			push @$list, $_;
		}
	} elsif ($query_file) {
		my $qry_ref = $self->get_query($query_file);
		return if ref $qry_ref ne 'SCALAR';
		my $view = $self->{'system'}->{'view'};
		return if !$self->create_temp_tables($qry_ref);
		$$qry_ref =~ s/SELECT ($view\.\*|\*)/SELECT $pk/ if defined $view;
		$self->rewrite_query_ref_order_by($qry_ref) if $self->{'system'}->{'dbtype'} eq 'isolates';
		$list = $self->{'datastore'}->run_list_query($$qry_ref);
	} else {
		$list = \@;;
	}
	if ( $q->param('submit') ) {
		$self->escape_params;
		my @param_names = $q->param;
		my @fields_selected;
		foreach (@param_names) {
			push @fields_selected, $_ if $_ =~ /^l_/ or $_ =~ /s_\d+_l_/;
		}
		if ( !@fields_selected ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No fields have been selected!</p></div>\n";
		} else {
			my $params = $q->Vars;
			$params->{'pk'} = $pk;
			( my $list = $q->param('list') ) =~ s/[\r\n]+/\|\|/g;
			$params->{'list'} = $list;
			my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
			my $job_id    = $self->{'jobManager'}->add_job(
				{
					'dbase_config' => $self->{'instance'},
					'ip_address'   => $q->remote_host,
					'module'       => 'XmfaExport',
					'parameters'   => $params,
					'username'     => $self->{'username'},
					'email'        => $user_info->{'email'}
				}
			);
			print <<"HTML";
<div class="box" id="resultstable">
<p>This analysis has been submitted to the job queue.</p>
<p>Please be aware that this job may take a long time depending on the number of sequences to align
and how busy the server is.  Alignment of hundreds of sequences can take many hours!</p>
<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=job&amp;id=$job_id">
Follow the progress of this job and view the output.</a></p> 	
<p>Please note that the % complete value will only update after the alignment of each locus.</p>
</div>	
HTML
			return;
		}
	}
	my $limit = $self->{'system'}->{'XMFA_limit'} || DEFAULT_LIMIT;
	print <<"HTML";
<div class="box" id="queryform">
<p>This script will export allele sequences in Extended Multi-FASTA (XMFA) format suitable for loading into third-party
applications, such as ClonalFrame.  Only loci that have a corresponding database containing sequences, or with sequences tagged,  
can be included.  Please check the loci that you would like to include.  If a sequence does not exist in
the remote database, it will be replaced with 'N's. Output is limited to $limit records. Please be aware that it may take a long time 
to generate the output file as the sequences are passed through muscle to align them.</p>
HTML
	my $options = { default_select => 0, translate => 1, flanking => 1, ignore_seqflags => 1, ignore_incomplete => 1 };
	$self->print_sequence_export_form( $pk, $list, $scheme_id, $options );
	print "</div>\n";
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	my $scheme_id = $params->{'scheme_id'};
	my $pk        = $params->{'pk'};
	my $filename  = "$self->{'config'}->{'tmp_dir'}/$job_id\.txt";
	open( my $fh, '>', $filename )
	  or $logger->error("Can't open output file $filename for writing");
	my $isolate_sql;
	if ( $params->{'includes'} ) {
		my @includes = split /\|\|/, $params->{'includes'};
		local $" = ',';
		$isolate_sql = $self->{'db'}->prepare("SELECT @includes FROM $self->{'system'}->{'view'} WHERE id=?");
	}
	my $substring_query;
	if ( $params->{'flanking'} && BIGSdb::Utils::is_int( $params->{'flanking'} ) ) {

		#round up to the nearest multiple of 3 if translating sequences to keep in reading frame
		if ( $params->{'translate'} ) {
			$params->{'flanking'} = BIGSdb::Utils::round_to_nearest( $params->{'flanking'}, 3 );
		}
		$substring_query = "substring(sequence from allele_sequences.start_pos-$params->{'flanking'} for "
		. "allele_sequences.end_pos-allele_sequences.start_pos+1+2*$params->{'flanking'})";
	} else {
		$substring_query = "substring(sequence from allele_sequences.start_pos for allele_sequences.end_pos-allele_sequences.start_pos+1)";
	}
	my $ignore_seqflags   = $params->{'ignore_seqflags'}   ? 'AND flag IS NULL' : '';
	my $ignore_incomplete = $params->{'ignore_incomplete'} ? 'AND complete'     : '';
	my $seqbin_sql =
	  $self->{'db'}->prepare( "SELECT $substring_query,reverse FROM allele_sequences LEFT JOIN sequence_bin ON "
		  . "allele_sequences.seqbin_id = sequence_bin.id LEFT JOIN sequence_flags ON allele_sequences.seqbin_id = "
		  . "sequence_flags.seqbin_id AND allele_sequences.locus = sequence_flags.locus AND allele_sequences.start_pos = "
		  . "sequence_flags.start_pos AND allele_sequences.end_pos = sequence_flags.end_pos WHERE isolate_id=? AND allele_sequences.locus=? "
		  . "$ignore_seqflags $ignore_incomplete ORDER BY complete,allele_sequences.datestamp LIMIT 1" );
	my @problem_ids;
	my $start = 1;
	my $end;
	my $no_output = 1;

	#reorder loci by genome order, schemes then by name (genome order may not be set)
	my $locus_qry = "SELECT id,scheme_id from loci left join scheme_members on loci.id = scheme_members.locus "
	. "order by genome_position,scheme_members.scheme_id,id";
	my $locus_sql = $self->{'db'}->prepare($locus_qry);
	eval { $locus_sql->execute };
	$logger->error($@) if $@;
	my @selected_fields;
	my %picked;
	while ( my ( $locus, $scheme_id ) = $locus_sql->fetchrow_array ) {

		if ( ( $scheme_id && $params->{"s_$scheme_id\_l_$locus"} ) || ( !$scheme_id && $params->{"l_$locus"} ) ) {
			push @selected_fields, $locus if !$picked{$locus};
			$picked{$locus} = 1;
		}
	}
	my @list = split /\|\|/, $params->{'list'};
	if ( !@list ) {
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			my $qry = "SELECT id FROM $self->{'system'}->{'view'} ORDER BY id";
			@list = @{ $self->{'datastore'}->run_list_query($qry) };
		} else {
			my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $pk );
			my $qry;
			if ( $field_info->{'type'} eq 'integer' ) {
				$qry = "SELECT $pk FROM scheme_$scheme_id ORDER BY CAST($pk AS integer)";
			} else {
				$qry = "SELECT $pk FROM scheme_$scheme_id ORDER BY $pk";
			}
			@list = @{ $self->{'datastore'}->run_list_query($qry) };
		}
	}
	my $limit = $self->{'system'}->{'XMFA_limit'} || DEFAULT_LIMIT;
	if ( @list > $limit ) {
		my $message_html = "<p class=\"statusbad\">Please note that output is limited to the first $limit records.</p>\n";
		$self->{'jobManager'}->update_job_status( $job_id, { 'message_html' => $message_html } );
	}
	my $progress = 0;
	my %no_seq;
	foreach my $locus_name (@selected_fields) {
		my $locus;
		my $locus_info = $self->{'datastore'}->get_locus_info($locus_name);
		my $common_length;
		try {
			$locus = $self->{'datastore'}->get_locus($locus_name);
		}
		catch BIGSdb::DataException with {
			$logger->warn("Invalid locus '$locus_name' passed.");
		};
		my $temp        = BIGSdb::Utils::get_random();
		my $temp_file   = "$self->{'config'}->{secure_tmp_dir}/$temp.txt";
		my $muscle_file = "$self->{'config'}->{secure_tmp_dir}/$temp.muscle";
		open( my $fh_muscle, '>', "$temp_file" ) or $logger->error("could not open temp file $temp_file");
		my $count = 0;
		foreach my $id (@list) {
			last if $count == $limit;
			$count++;
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
				my @includes;
				next if !BIGSdb::Utils::is_int($id);
				if ( $params->{'includes'} ) {
					eval { $isolate_sql->execute($id) };
					$logger->error($@) if $@;
					@includes = $isolate_sql->fetchrow_array;
					foreach (@includes) {
						$_ =~ tr/ /_/;
					}
				}
				if ($id) {
					print $fh_muscle ">$id";
					local $" = '|';
					print $fh_muscle "|@includes" if $params->{'includes'};
					print $fh_muscle "\n";
				} else {
					push @problem_ids, $id;
					next;
				}
				my $allele_id = $self->{'datastore'}->get_allele_id( $id, $locus_name );
				my $allele_seq;
				if ( $locus_info->{'data_type'} eq 'DNA' ) {
					try {
						$allele_seq = $locus->get_allele_sequence($allele_id);
					}
					catch BIGSdb::DatabaseConnectionException with {

						#do nothing
					};
				}
				my $seqbin_seq;
				eval { $seqbin_sql->execute( $id, $locus_name ) };
				if ($@) {
					$logger->error($@);
				} else {
					my $reverse;
					( $seqbin_seq, $reverse ) = $seqbin_sql->fetchrow_array;
					if ($reverse) {
						$seqbin_seq = BIGSdb::Utils::reverse_complement($seqbin_seq);
					}
				}
				my $seq;
				if ( ref $allele_seq && $$allele_seq && $seqbin_seq ) {
					$seq = $params->{'chooseseq'} eq 'seqbin' ? $seqbin_seq : $$allele_seq;
				} elsif ( ref $allele_seq && $$allele_seq && !$seqbin_seq ) {
					$seq = $$allele_seq;
				} elsif ($seqbin_seq) {
					$seq = $seqbin_seq;
				} else {
					$seq = 'N';
					$no_seq{$id} = 1;
				}
				if ( $params->{'translate'} ) {
					$seq = BIGSdb::Utils::chop_seq( $seq, $locus_info->{'orf'} || 1 );
					my $peptide = Bio::Perl::translate_as_string($seq);
					print $fh_muscle "$peptide\n";
				} else {
					print $fh_muscle "$seq\n";
				}
			} else {
				my $profile_sql = $self->{'db'}->prepare("SELECT $pk FROM scheme_$scheme_id WHERE $pk=?");
				eval { $profile_sql->execute($id) };
				$logger->error($@) if $@;
				my ($profile_id) = $profile_sql->fetchrow_array;
				if ($profile_id) {
					my $allele_id = $self->{'datastore'}->get_profile_allele_designation( $scheme_id, $id, $locus_name )->{'allele_id'};
					my $allele_seq = $self->{'datastore'}->get_sequence( $locus_name, $allele_id );
					print $fh_muscle ">$profile_id\n";
					print $fh_muscle "$$allele_seq\n";
				} else {
					push @problem_ids, $id;
					next;
				}
			}
		}
		close $fh_muscle;
		system( $self->{'config'}->{'muscle_path'}, '-in', $temp_file, '-out', $muscle_file, '-quiet' );
		if ( -e $muscle_file ) {
			$no_output = 0;
			my $seq_in = Bio::SeqIO->new( '-format' => 'fasta', '-file' => $muscle_file );
			while ( my $seq = $seq_in->next_seq ) {
				my $length = $seq->length;
				$end = $start + $length - 1;
				print $fh '>' . $seq->id . ":$start-$end + $locus_name\n";
				my $sequence = BIGSdb::Utils::break_line( $seq->seq, 60 );
				$sequence =~ s/N/-/g if $no_seq{$seq->id};
				print $fh "$sequence\n";
			}
			$start = $end + 1;
			print $fh "=\n";
		}
		unlink $muscle_file;
		unlink $temp_file;
		$progress++;
		my $complete = int( 100 * $progress / scalar @selected_fields );
		$self->{'jobManager'}->update_job_status( $job_id, { 'percent_complete' => $complete } );
	}
	close $fh;
	my $message_html;
	if (@problem_ids) {
		local $" = ', ';
		$message_html = "<p>The following ids could not be processed (they do not exist): @problem_ids.</p>\n";
	}
	if ($no_output) {
		$message_html .= "<p>No output generated.  Please ensure that your sequences have been defined for these isolates.</p>\n";
	} else {
		$self->{'jobManager'}->update_job_output( $job_id, { 'filename' => "$job_id.txt", 'description' => 'XMFA output file' } );
	}
	$self->{'jobManager'}->update_job_status( $job_id, { 'message_html' => $message_html } ) if $message_html;
	return;
}
1;
