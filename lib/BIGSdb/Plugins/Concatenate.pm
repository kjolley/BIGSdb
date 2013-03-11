#Concatenate.pm - Concatenate plugin for BIGSdb
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
package BIGSdb::Plugins::Concatenate;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use List::MoreUtils qw(none uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use Apache2::Connection ();

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { general => 1, main_display => 0, isolate_display => 0, analysis => 1, query_field => 0 };
	return;
}

sub get_attributes {
	my %att = (
		name        => 'Concatenate',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Concatenate allele sequences from dataset generated from query results',
		category    => 'Export',
		buttontext  => 'Concatenate',
		menutext    => 'Concatenate alleles',
		module      => 'Concatenate',
		version     => '1.1.2',
		dbtype      => 'isolates,sequences',
		seqdb_type  => 'schemes',
		help        => 'tooltips',
		section     => 'export,postquery',
		url         => 'http://pubmlst.org/software/database/bigsdb/userguide/isolates/concatenated.shtml',
		input       => 'query',
		requires    => 'js_tree',
		order       => 20
	);
	return \%att;
}

sub run {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $scheme_id  = $q->param('scheme_id');
	my $desc       = $self->get_db_description;
	say "<h1>Concatenate allele sequences - $desc</h1>";
	my $pk;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$pk = 'id';
	} else {
		if ( !$scheme_id ) {
			say "<div class=\"box\" id=\"statusbad\"><p>No scheme id passed.</p></div>";
			return;
		} elsif ( !BIGSdb::Utils::is_int($scheme_id) ) {
			say "<div class=\"box\" id=\"statusbad\"><p>Scheme id must be an integer.</p></div>";
			return;
		} else {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
			if ( !$scheme_info ) {
				say "<div class=\"box\" id=\"statusbad\">Scheme does not exist.</p></div>";
				return;
			}
		}
		my $pk_ref =
		  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE scheme_id=? AND primary_key", $scheme_id );
		if ( ref $pk_ref ne 'ARRAY' ) {
			say "<div class=\"box\" id=\"statusbad\"><p>No primary key field has been set for this scheme.  Profile concatenation "
			  . "can not be done until this has been set.</p></div>";
			return;
		}
		$pk = $pk_ref->[0];
	}
	my $list = $self->get_id_list( $pk, $query_file );
	if ( $q->param('submit') ) {
		my $loci_selected = $self->get_selected_loci;
		my $scheme_ids    = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
		push @$scheme_ids, 0;
		if ( !@$loci_selected && none { $q->param("s_$_") } @$scheme_ids ) {
			print "<div class=\"box\" id=\"statusbad\"><p>You must select one or more loci";
			print " or schemes" if $self->{'system'}->{'dbtype'} eq 'isolates';
			say ".</p></div>";
		} else {
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
				if ( !@$list ) {
					my $qry = "SELECT id FROM $self->{'system'}->{'view'} ORDER BY id";
					$list = $self->{'datastore'}->run_list_query($qry);
				}
			} else {
				if ( !@$list ) {
					my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $pk );
					my $qry;
					if ( $field_info->{'type'} eq 'integer' ) {
						$qry = "SELECT $pk FROM scheme_$scheme_id ORDER BY CAST($pk AS integer)";
					} else {
						$qry = "SELECT $pk FROM scheme_$scheme_id ORDER BY $pk";
					}
					$list = $self->{'datastore'}->run_list_query($qry);
				}
			}
			say "<div class=\"box\" id=\"resultstable\">";
			say "<p>Please wait for processing to finish (do not refresh page).</p>";
			print "<p>Output file being generated ...";
			my $filename    = ( BIGSdb::Utils::get_random() ) . '.txt';
			my $full_path   = "$self->{'config'}->{'tmp_dir'}/$filename";
			my $problem_ids = $self->_write_fasta( $list, $loci_selected, $full_path, $pk );
			say " done</p>";
			say "<p><a href=\"/tmp/$filename\">Output file</a> (right-click to save)</p>";
			say "</div>";

			if (@$problem_ids) {
				local $" = '; ';
				say "<div class=\"box\" id=\"statusbad\"><p>The following ids could not be processed "
				  . "(they do not exist): @$problem_ids.</p></div>";
			}
			return;
		}
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		print <<"HTML";
<div class="box" id="queryform">
<p>This script will concatenate alleles in FASTA format.  Only loci that have a corresponding database containing
sequences, or with sequences tagged, can be included.  Please check the loci that you would like to include.  
Alternatively select one or more schemes to include all loci that are members of the scheme.  If a sequence does 
not exist in the remote database, it will be replaced with dashes. Please be aware that since alleles may have 
insertions or deletions, the sequences may need to be aligned.</p>
HTML
	} else {
		print <<"HTML";
<div class="box" id="queryform">
<p>This script will concatenate alleles in FASTA format. Please be aware that since alleles may have 
insertions or deletions, the sequences may need to be aligned.</p>
HTML
	}
	my $options = { default_select => 0, translate => 1, in_frame => 1 };
	$self->print_sequence_export_form( $pk, $list, $scheme_id, $options );
	say "</div>";
	return;
}

sub _write_fasta {
	my ( $self, $list, $fields, $filename, $pk ) = @_;
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	$self->escape_params;
	local $| = 1;
	open( my $fh, '>', $filename )
	  or $logger->error("Can't open temp file $filename for writing");
	my $isolate_sql = $self->{'system'}->{'view'} ? $self->{'db'}->prepare("SELECT * FROM $self->{'system'}->{'view'} WHERE id=?") : undef;
	my @includes    = $q->param('includes');
	my $length_sql  = $self->{'db'}->prepare("SELECT length FROM loci WHERE id=?");
	my $seqbin_sql =
	  $self->{'db'}->prepare( "SELECT substring(sequence from start_pos for end_pos-start_pos+1),reverse FROM "
		  . "allele_sequences LEFT JOIN sequence_bin ON allele_sequences.seqbin_id = sequence_bin.id WHERE isolate_id=? AND locus=? "
		  . "ORDER BY complete desc,allele_sequences.datestamp LIMIT 1" );
	my @problem_ids;
	my %most_common;
	my $i             = 0;
	my $j             = 0;
	my $selected_loci = $self->order_selected_loci;

	foreach my $id (@$list) {
		print "." if !$i;
		print " " if !$j;
		if ( !$i && $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
		$id =~ s/[\r\n]//g;
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			next if !BIGSdb::Utils::is_int($id);
			my @include_values;
			if (@includes) {
				eval { $isolate_sql->execute($id) };
				$logger->error($@) if $@;
				my $include_data = $isolate_sql->fetchrow_hashref;
				foreach my $field (@includes) {
					my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
					my $value;
					if ( defined $metaset ) {
						$value = $self->{'datastore'}->get_metadata_value( $id, $metaset, $metafield );
					} else {
						$value = $include_data->{$field} // '';
					}
					$value =~ tr/ /_/;
					push @include_values, $value;
				}
			}
			if ($id) {
				print $fh ">$id";
				local $" = '|';
				print $fh "|@include_values" if @includes;
				print $fh "\n";
			} else {
				push @problem_ids, $id;
				next;
			}
		} else {
			my $profile_sql = $self->{'db'}->prepare("SELECT $pk FROM scheme_$scheme_id WHERE $pk=?");
			eval { $profile_sql->execute($id) };
			$logger->error($@) if $@;
			my ($profile_id) = $profile_sql->fetchrow_array;
			if ($profile_id) {
				print $fh ">$profile_id\n";
			} else {
				push @problem_ids, $id;
				next;
			}
		}
		my %loci;
		my $seq;
		foreach my $locus (@$selected_loci) {
			my $no_seq     = 0;
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			if ( !$loci{$locus} ) {
				try {
					$loci{$locus} = $self->{'datastore'}->get_locus($locus);
				}
				catch BIGSdb::DataException with {
					$logger->warn("Invalid locus '$locus' passed.");
				};
			}
			if ( $loci{$locus} ) {
				if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
					my $allele_id = $self->{'datastore'}->get_allele_id( $id, $locus );
					my $allele_seq;
					if ( $locus_info->{'data_type'} eq 'DNA' ) {
						if (($allele_id // '0') ne '0'){
							try {
								$allele_seq = $loci{$locus}->get_allele_sequence($allele_id);
							}
							catch BIGSdb::DatabaseConnectionException with {
	
								#do nothing
							};
						}
					}
					my $seqbin_seq;
					eval { $seqbin_sql->execute( $id, $locus ); };
					if ($@) {
						$logger->error("Can't execute, $@");
					} else {
						my $reverse;
						( $seqbin_seq, $reverse ) = $seqbin_sql->fetchrow_array;
						if ($reverse) {
							$seqbin_seq = BIGSdb::Utils::reverse_complement($seqbin_seq);
						}
					}
					my $temp_seq;
					if ( ref $allele_seq && $$allele_seq && $seqbin_seq ) {
						$temp_seq = $q->param('chooseseq') eq 'seqbin' ? $seqbin_seq : $$allele_seq;
					} elsif ( ref $allele_seq && $$allele_seq && !$seqbin_seq ) {
						$temp_seq = $$allele_seq;
					} elsif ($seqbin_seq) {
						$temp_seq = $seqbin_seq;
					} else {
						eval { $length_sql->execute($locus); };
						if ($@) {
							$logger->error("Can't execute $@");
						}
						my ($length) = $length_sql->fetchrow_array;
						if ($length) {
							$temp_seq = '-' x $length;
							$no_seq   = 1;
						} else {

							#find most common length;
							if ( !$most_common{$locus} ) {
								my $seqs = $loci{$locus}->get_all_sequences;
								my %length_freqs;
								foreach ( values %$seqs ) {
									$length_freqs{ length $_ }++;
								}
								my $max_freqs = 0;
								foreach ( keys %length_freqs ) {
									if ( $length_freqs{$_} > $max_freqs ) {
										$max_freqs = $length_freqs{$_};
										$most_common{$locus} = $_;
									}
								}
								if ( $locus_info->{'data_type'} eq 'peptide' ) {
									$most_common{$locus} *= 3;    #3 nucleotides/codon
								}
							}
							if ( !$most_common{$locus} ) {
								$most_common{$locus} = 10;        #arbitrary length to show that sequence is missing.
							}
							$temp_seq = '-' x $most_common{$locus};
							$no_seq   = 1;
						}
					}
					if ( $q->param('in_frame')){
						$temp_seq = BIGSdb::Utils::chop_seq( $temp_seq, $locus_info->{'orf'} || 1 );
					}
					if ( $q->param('translate') ) {					
						my $peptide = !$no_seq ? Bio::Perl::translate_as_string($temp_seq) : 'X';
						$seq .= $peptide;
					} else {
						$seq .= $temp_seq;
					}
				} else {
					my $allele_id = $self->{'datastore'}->get_profile_allele_designation( $scheme_id, $id, $locus )->{'allele_id'};
					if ($allele_id ne 'N' && $allele_id ne '0'){
						my $allele_seq_ref = $self->{'datastore'}->get_sequence( $locus, $allele_id );
						my $allele_seq;
						if ( $q->param('in_frame')){
							$allele_seq = BIGSdb::Utils::chop_seq( $$allele_seq_ref, $locus_info->{'orf'} || 1 );
						} else {
							$allele_seq = $$allele_seq_ref;
						}			
						if ( $q->param('translate') ) {
							my $peptide = !$no_seq ? Bio::Perl::translate_as_string($allele_seq) : 'X';
							$seq .= $peptide;
						} else {
							$seq .= $allele_seq;
						}
					}
				}
			}
		}
		$seq = BIGSdb::Utils::break_line( $seq, 60 );
		say $fh "$seq";
		$i++;
		if ( $i == 50 ) {
			$i = 0;
			$j++;
		}
		$j = 0 if $j == 10;
	}
	close $fh;
	return \@problem_ids;
}
1;
