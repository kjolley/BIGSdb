#XmfaExport.pm - Export XMFA file plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2013, University of Oxford
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
use 5.010;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use List::MoreUtils qw(any none uniq);
use Apache2::Connection ();
use Bio::Perl;
use Bio::SeqIO;
use Bio::AlignIO;
use BIGSdb::Utils;
use constant DEFAULT_LIMIT => 200;
use BIGSdb::Page qw(LOCUS_PATTERN);

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
		version     => '1.4.4',
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
	$self->{'pref_requirements'} = { general => 1, main_display => 0, isolate_display => 0, analysis => 1, query_field => 0 };
	return;
}

sub run {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $scheme_id  = $q->param('scheme_id');
	my $desc       = $self->get_db_description;
	say "<h1>Export allele sequences in XMFA format - $desc</h1>";
	if ( !-e $self->{'config'}->{'muscle_path'} || !-x $self->{'config'}->{'muscle_path'} ) {
		$logger->error( "This plugin requires MUSCLE to be installed and it is not.  Please install MUSCLE "
			  . "or check the settings in bigsdb.conf." );
	}
	my $pk;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$pk = 'id';
	} else {
		return if defined $scheme_id && $self->is_scheme_invalid( $scheme_id, { with_pk => 1 } );
		if ( !$q->param('submit') ) {
			$self->print_scheme_section( { with_pk => 1 } );
			$scheme_id = $q->param('scheme_id');    #Will be set by scheme section method
		}
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		$pk = $scheme_info->{'primary_key'};
	}
	if ( $q->param('submit') ) {
		my $loci_selected = $self->get_selected_loci;
		my ( $pasted_cleaned_loci, $invalid_loci ) = $self->get_loci_from_pasted_list;
		$q->delete('locus');
		push @$loci_selected, @$pasted_cleaned_loci;
		@$loci_selected = uniq @$loci_selected;
		$self->add_scheme_loci($loci_selected);
		if (@$invalid_loci) {
			local $" = ', ';
			say "<div class=\"box\" id=\"statusbad\"><p>The following loci in your pasted list are invalid: @$invalid_loci.</p></div>";
		} elsif ( !@$loci_selected ) {
			print "<div class=\"box\" id=\"statusbad\"><p>You must select one or more loci";
			print " or schemes" if $self->{'system'}->{'dbtype'} eq 'isolates';
			say ".</p></div>\n";
		} else {
			$self->set_scheme_param;
			my $params = $q->Vars;
			$params->{'pk'}     = $pk;
			$params->{'set_id'} = $self->get_set_id;
			my @list = split /[\r\n]+/, $q->param('list');
			@list = uniq @list;
			if ( !@list ) {
				if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
					my $qry = "SELECT id FROM $self->{'system'}->{'view'} ORDER BY id";
					@list = @{ $self->{'datastore'}->run_list_query($qry) };
				} else {
					my $pk_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $pk );
					my $qry = "SELECT profile_id FROM profiles WHERE scheme_id=? ORDER BY ";
					$qry .= $pk_info->{'type'} eq 'integer' ? 'CAST(profile_id AS INT)' : 'profile_id';
					@list = @{ $self->{'datastore'}->run_list_query( $qry, $scheme_id ) };
				}
			}
			my $list_type = $self->{'system'}->{'dbtype'} eq 'isolates' ? 'isolates' : 'profiles';
			$q->delete('list');
			my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
			my $job_id    = $self->{'jobManager'}->add_job(
				{
					dbase_config => $self->{'instance'},
					ip_address   => $q->remote_host,
					module       => 'XmfaExport',
					parameters   => $params,
					username     => $self->{'username'},
					email        => $user_info->{'email'},
					loci         => $loci_selected,
					$list_type   => \@list
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
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		print <<"HTML";
<div class="box" id="queryform">
<p>This script will export allele sequences in Extended Multi-FASTA (XMFA) format suitable for loading into third-party
applications, such as ClonalFrame.  Only loci that have a corresponding database containing sequences, or with sequences tagged,  
can be included.  Please check the loci that you would like to include.  Alternatively select one or more schemes to include
all loci that are members of the scheme.  If a sequence does not exist in the remote database, it will be replaced with 
'-'s. Output is limited to $limit records. Please be aware that it may take a long time to generate the output file as the 
sequences are passed through muscle to align them.</p>
HTML
	} else {
		print <<"HTML";
<div class="box" id="queryform">
<p>This script will export allele sequences in Extended Multi-FASTA (XMFA) format suitable for loading into third-party
applications, such as ClonalFrame.  Output is limited to $limit records. Please be aware that it may take a long time 
to generate the output file as the sequences are passed through muscle to align them.</p>
HTML
	}
	my $options = { default_select => 0, translate => 1, flanking => 1, ignore_seqflags => 1, ignore_incomplete => 1 };
	my $list = $self->get_id_list( $pk, $query_file );
	$self->print_sequence_export_form( $pk, $list, $scheme_id, $options );
	say "</div>";
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	$self->set_offline_view($params);
	$self->{'exit'} = 0;
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1 } ) x 3;    #Allow temp files to be cleaned on kill signals
	my $scheme_id = $params->{'scheme_id'};
	my $pk        = $params->{'pk'};
	my $filename  = "$self->{'config'}->{'tmp_dir'}/$job_id\.xmfa";
	open( my $fh, '>', $filename )
	  or $logger->error("Can't open output file $filename for writing");
	my $isolate_sql =
	    $self->{'system'}->{'dbtype'} eq 'isolates'
	  ? $self->{'db'}->prepare("SELECT * FROM $self->{'system'}->{'view'} WHERE id=?")
	  : undef;
	my @includes;

	if ( $params->{'includes'} ) {
		my $separator = '\|\|';
		@includes = split /$separator/, $params->{'includes'};
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
	my %problem_id_checked;
	my $start = 1;
	my $end;
	my $no_output     = 1;
	my $loci          = $self->{'jobManager'}->get_job_loci($job_id);
	my $selected_loci = $self->order_loci($loci);
	my $ids;

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$ids = $self->{'jobManager'}->get_job_isolates($job_id);
	} else {
		$ids = $self->{'jobManager'}->get_job_profiles( $job_id, $scheme_id );
	}
	my $limit = $self->{'system'}->{'XMFA_limit'} || DEFAULT_LIMIT;
	if ( @$ids > $limit ) {
		my $message_html = "<p class=\"statusbad\">Please note that output is limited to the first $limit records.</p>\n";
		$self->{'jobManager'}->update_job_status( $job_id, { message_html => $message_html } );
	}
	my $progress = 0;
	foreach my $locus_name (@$selected_loci) {
		last if $self->{'exit'};
		my %no_seq;
		my $locus;
		my $locus_info = $self->{'datastore'}->get_locus_info($locus_name);
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
		foreach my $id (@$ids) {
			last if $count == $limit;
			$count++;
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
				my @include_values;
				eval { $isolate_sql->execute($id) };
				my $isolate_data = $isolate_sql->fetchrow_hashref;
				if (@includes) {
					foreach my $field (@includes) {
						my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
						my $value;
						if ( defined $metaset ) {
							$value = $self->{'datastore'}->get_metadata_value( $id, $metaset, $metafield );
						} else {
							$value = $isolate_data->{$field} // '';
						}
						$value =~ tr/ /_/;
						push @include_values, $value;
					}
				}
				if ( $isolate_data->{'id'} ) {
					print $fh_muscle ">$id";
					local $" = '|';
					print $fh_muscle "|@include_values" if @includes;
					print $fh_muscle "\n";
				} else {
					push @problem_ids, $id if !$problem_id_checked{$id};
					$problem_id_checked{$id} = 1;
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
					my $peptide = $seq ? Bio::Perl::translate_as_string($seq) : 'X';
					say $fh_muscle $peptide;
				} else {
					say $fh_muscle $seq;
				}
			} else {
				my $profile_sql = $self->{'db'}->prepare("SELECT * FROM scheme_$scheme_id WHERE $pk=?");
				eval { $profile_sql->execute($id) };
				$logger->error($@) if $@;
				my $profile_data = $profile_sql->fetchrow_hashref;
				my $profile_id   = $profile_data->{ lc($pk) };
				my $header;
				if ( defined $profile_id ) {
					$header = ">$profile_id";
					if (@includes) {
						foreach my $field (@includes) {
							my $value = $profile_data->{ lc($field) } // '';
							$value =~ tr/[\(\):, ]/_/;
							$header .= "|$value";
						}
					}
				}
				if ($profile_id) {
					my $allele_id = $self->{'datastore'}->get_profile_allele_designation( $scheme_id, $id, $locus_name )->{'allele_id'};
					my $allele_seq_ref = $self->{'datastore'}->get_sequence( $locus_name, $allele_id );
					say $fh_muscle $header;
					if ( $allele_id eq '0' || $allele_id eq 'N' ) {
						say $fh_muscle 'N';
						$no_seq{$id} = 1;
					} else {
						my $allele_seq = $$allele_seq_ref;
						if ( $params->{'translate'} && $locus_info->{'data_type'} eq 'DNA' ) {
							$allele_seq = BIGSdb::Utils::chop_seq( $allele_seq, $locus_info->{'orf'} || 1 );
							my $peptide = $allele_seq ? Bio::Perl::translate_as_string($allele_seq) : 'X';
							say $fh_muscle $peptide;
						} else {
							say $fh_muscle $allele_seq;
						}
					}
				} else {
					push @problem_ids, $id if !$problem_id_checked{$id};
					$problem_id_checked{$id} = 1;
					next;
				}
			}
		}
		close $fh_muscle;
		my $output_locus_name = $self->{'datastore'}->get_set_locus_label( $locus_name, $params->{'set_id'} ) // $locus_name;
		$self->{'jobManager'}->update_job_status( $job_id, { stage => "Aligning $output_locus_name" } );
		if ( -e $temp_file && -s $temp_file ) {
			system( $self->{'config'}->{'muscle_path'}, '-in', $temp_file, '-out', $muscle_file, '-quiet' );
		}
		if ( -e $muscle_file ) {
			$no_output = 0;
			my $seq_in = Bio::SeqIO->new( -format => 'fasta', -file => $muscle_file );
			while ( my $seq = $seq_in->next_seq ) {
				my $length = $seq->length;
				$end = $start + $length - 1;
				print $fh '>' . $seq->id . ":$start-$end + $output_locus_name\n";
				my $sequence = BIGSdb::Utils::break_line( $seq->seq, 60 );
				( my $id = $seq->id ) =~ s/\|.*$//;
				$sequence =~ s/N/-/g if $no_seq{$id};
				say $fh $sequence;
			}
			$start = $end + 1;
			print $fh "=\n";
		}
		unlink $muscle_file;
		unlink $temp_file;
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
	my $message_html;
	if (@problem_ids) {
		local $" = ', ';
		$message_html = "<p>The following ids could not be processed (they do not exist): @problem_ids.</p>\n";
	}
	if ($no_output) {
		$message_html .= "<p>No output generated.  Please ensure that your sequences have been defined for these isolates.</p>\n";
	} else {
		$self->{'jobManager'}->update_job_output( $job_id, { filename => "$job_id.xmfa", description => '10_XMFA output file' } );
		try {
			$self->{'jobManager'}->update_job_status( $job_id, { stage => "Converting XMFA to FASTA" } );
			my $fasta_file = BIGSdb::Utils::xmfa2fasta("$self->{'config'}->{'tmp_dir'}/$job_id\.xmfa");
			if ( -e $fasta_file ) {
				$self->{'jobManager'}->update_job_output( $job_id,
					{ filename => "$job_id.fas", description => '20_Concatenated aligned sequences (FASTA format)' } );
			}
		}
		catch BIGSdb::CannotOpenFileException with {
			$logger->error("Can't create FASTA file from XMFA.");
		};
	}
	$self->{'jobManager'}->update_job_status( $job_id, { message_html => $message_html } ) if $message_html;
	return;
}
1;
