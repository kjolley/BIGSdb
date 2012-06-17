#Concatenate.pm - Concatenate plugin for BIGSdb
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
package BIGSdb::Plugins::Concatenate;
use strict;
use warnings;
use parent qw(BIGSdb::Plugin);
use List::MoreUtils qw(uniq);
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
		version     => '1.0.2',
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
	print "<h1>Concatenate allele sequences</h1>\n";
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
			print
"<div class=\"box\" id=\"statusbad\"><p>No primary key field has been set for this scheme.  Profile concatenation can not be done until this has been set.</p></div>\n";
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
		return if !$self->create_temp_tables($qry_ref);
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			my $view = $self->{'system'}->{'view'};
			$$qry_ref =~ s/SELECT ($view\.\*|\*)/SELECT $pk/;
			$self->rewrite_query_ref_order_by($qry_ref) if $self->{'system'}->{'dbtype'} eq 'isolates';
		}
		$list = $self->{'datastore'}->run_list_query($$qry_ref);
	} else {
		$list = \@;;
	}
	if ( $q->param('submit') ) {
		my @params = $q->param;
		my @fields_selected;
		foreach (@params) {
			push @fields_selected, $_ if $_ =~ /^l_/ or $_ =~ /s_\d+_l_/;
		}
		if ( !@fields_selected ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No fields have been selected!</p></div>\n";
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
			print "<div class=\"box\" id=\"resultstable\">";
			print "<p>Please wait for processing to finish (do not refresh page).</p>\n";
			print "<p>Output file being generated ...";
			my $filename    = ( BIGSdb::Utils::get_random() ) . '.txt';
			my $full_path   = "$self->{'config'}->{'tmp_dir'}/$filename";
			my $problem_ids = $self->_write_fasta( $list, \@fields_selected, $full_path, $pk );
			print " done</p>";
			print "<p><a href=\"/tmp/$filename\">Output file</a> (right-click to save)</p>\n";
			print "</div>\n";

			if (@$problem_ids) {
				local $" = '; ';
				print
"<div class=\"box\" id=\"statusbad\"><p>The following ids could not be processed (they do not exist): @$problem_ids.</p></div>\n";
			}
			return;
		}
	}
	print <<"HTML";
<div class="box" id="queryform">
<p>This script will concatenate alleles in FASTA format.  Only loci that have a corresponding database containing
sequences can be included.  Please check the loci that you would like to include.  If a sequence does not exist in
the remote database, it will be replaced with dashes. Please be aware that since alleles may have insertions or deletions,
the sequences may need to be aligned.</p>
HTML
	my $options = { default_select => 0, translate => 1 };
	$self->print_sequence_export_form( $pk, $list, $scheme_id, $options );
	print "</div>\n";
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
	my $isolate_sql;
	if ( $q->param('includes') ) {
		my @includes = $q->param('includes');
		local $" = ',';
		$isolate_sql = $self->{'db'}->prepare("SELECT @includes FROM $self->{'system'}->{'view'} WHERE id=?");
	}
	my $length_sql = $self->{'db'}->prepare("SELECT length FROM loci WHERE id=?");
	my $seqbin_sql =
	  $self->{'db'}->prepare(
"SELECT substring(sequence from start_pos for end_pos-start_pos+1),reverse FROM allele_sequences LEFT JOIN sequence_bin ON allele_sequences.seqbin_id = sequence_bin.id WHERE isolate_id=? AND locus=? ORDER BY complete desc,allele_sequences.datestamp LIMIT 1"
	  );
	my @problem_ids;
	my %most_common;
	my $i = 0;
	my $j = 0;

	#reorder loci by genome order, schemes then by name (genome order may not be set)
	my $locus_qry = "SELECT id,scheme_id from loci left join scheme_members on loci.id = scheme_members.locus order "
	  . "by genome_position,scheme_members.scheme_id,id";
	my $locus_sql = $self->{'db'}->prepare($locus_qry);
	eval { $locus_sql->execute };
	$logger->error($@) if $@;
	my @selected_fields;
	while ( my ( $locus, $scheme_id ) = $locus_sql->fetchrow_array ) {
		if ( ( $scheme_id && $q->param("s_$scheme_id\_l_$locus") ) || ( $q->param("l_$locus") ) ) {
			push @selected_fields, $locus;
		}
	}
	@selected_fields = uniq @selected_fields;
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
			my @includes;
			if ( $q->param('includes') ) {
				eval { $isolate_sql->execute($id) };
				$logger->error($@) if $@;
				@includes = $isolate_sql->fetchrow_array;
				foreach (@includes) {
					tr/ /_/ if defined;
				}
			}
			if ($id) {
				print $fh ">$id";
				local $" = '|';
				{
					no warnings 'uninitialized';
					print $fh "|@includes" if $q->param('includes');
				}
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
		foreach my $locus (@selected_fields) {
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
						try {
							$allele_seq = $loci{$locus}->get_allele_sequence($allele_id);
						}
						catch BIGSdb::DatabaseConnectionException with {

							#do nothing
						};
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
						}
					}
					if ( $q->param('translate') ) {
						$temp_seq = BIGSdb::Utils::chop_seq( $temp_seq, $locus_info->{'orf'} || 1 );
						my $peptide = Bio::Perl::translate_as_string($temp_seq);
						$seq .= $peptide;
					} else {
						$seq .= $temp_seq;
					}
				} else {
					my $allele_id = $self->{'datastore'}->get_profile_allele_designation( $scheme_id, $id, $locus )->{'allele_id'};
					my $allele_seq = $self->{'datastore'}->get_sequence( $locus, $allele_id );
					$seq .= $$allele_seq;
				}
			}
		}
		$seq = BIGSdb::Utils::break_line( $seq, 60 );
		print $fh "$seq\n";
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
