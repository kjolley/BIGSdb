#!/usr/bin/env perl
#Written by Keith Jolley
#Copyright (c) 2023-2024, University of Oxford
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
#
#Version: 20240712
use strict;
use warnings;
use 5.010;
###########Local configuration################################
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases',
};
#######End Local configuration################################
use lib (LIB_DIR);
use BIGSdb::Offline::Script;
use BIGSdb::Constants qw(LOG_TO_SCREEN :limits);
use BIGSdb::Utils;
use Carp;
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
use POSIX;
use Bio::Seq;
use Bio::Tools::Run::Alignment::Clustalw;
use Bio::AlignIO;
use Try::Tiny;
use constant EVALUE_THRESHOLD => 0.001;
my %opts;
GetOptions(
	'database=s'     => \$opts{'d'},
	'exclude_loci=s' => \$opts{'L'},
	'flanking=i'     => \$opts{'flanking'},
	'help'           => \$opts{'help'},
	'loci=s'         => \$opts{'l'},
	'locus_regex=s'  => \$opts{'R'},
	'quiet'          => \$opts{'quiet'},
	'rescan'         => \$opts{'rescan'},
	'schemes=s'      => \$opts{'s'},
);

if ( $opts{'help'} ) {
	show_help();
	exit;
}
my $script = BIGSdb::Offline::Script->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		options          => { no_user_db_needed => 1, %opts },
		instance         => $opts{'d'}
	}
);

#Direct all library logging calls to screen
my $log_conf = LOG_TO_SCREEN;
$log_conf =~ s/INFO/WARN/gx if $opts{'quiet'};
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
if ( !$opts{'d'} ) {
	show_help();
	exit;
}
die "This script can only be run against a seqdef database.\n"
  if ( $script->{'system'}->{'dbtype'} // '' ) ne 'sequences';
if ( defined $opts{'flanking'} && ( $opts{'flanking'} < 10 || $opts{'flanking'} > 50 ) ) {
	die "Flanking length should be between 10 and 50.\n";
}
main();
undef $script;

sub main {
	my $locus_records = get_loci_with_mutations();
	foreach my $locus_record (@$locus_records) {
		if ( $opts{'rescan'} ) {
			remove_existing_designations( $locus_record->{'locus'} );
		}
		if ( $locus_record->{'locus_type'} eq 'DNA' ) {
			if ( $locus_record->{'mutation_type'} eq 'DNA' ) {    #Mutation defined by DNA position
				process_dna_mutation( $locus_record->{'locus'} );
			} else {                                              #Mutation defined by peptide position
				process_peptide_mutation( $locus_record->{'locus_type'}, $locus_record->{'locus'} );
			}
		} else {    #Peptide locus
			if ( $locus_record->{'mutation_type'} eq 'DNA' ) {
				die "Cannot process peptide locus $locus_record->{'locus'} by DNA polymorphisms.\n";
			} else {
				process_peptide_mutation( $locus_record->{'locus_type'}, $locus_record->{'locus'} );
			}
		}
	}
	return;
}

sub remove_existing_designations {
	my ($locus) = @_;
	eval {
		$script->{'db'}->do( 'DELETE FROM sequences_peptide_mutations WHERE locus=?', undef, $locus );
		$script->{'db'}->do( 'DELETE FROM sequences_dna_mutations WHERE locus=?',     undef, $locus );
	};
	if ($@) {
		$logger->error($@);
		$script->{'db'}->rollback;
	} else {
		$script->{'db'}->commit;
	}
	return;
}

sub get_loci_with_mutations {
	my $loci     = $script->get_selected_loci;
	my $filtered = [];
	foreach my $mutation_type (qw(peptide DNA)) {
		my $loci_with_mutations =
		  $script->{'datastore'}
		  ->run_query( "SELECT locus FROM ${mutation_type}_mutations", undef, { fetch => 'col_arrayref' } );
		my %with_mutations = map { $_ => 1 } @$loci_with_mutations;
		foreach my $locus (@$loci) {
			next if !$with_mutations{$locus};
			my $locus_info = $script->{'datastore'}->get_locus_info($locus);
			push @$filtered,
			  {
				locus         => $locus,
				locus_type    => $locus_info->{'data_type'},
				mutation_type => $mutation_type
			  };
		}
	}
	return $filtered;
}

sub process_peptide_mutation {
	my ( $locus_type, $locus ) = @_;
	my $sequences;
	if ( $locus_type eq 'DNA' ) {
		$sequences = get_translated_alleles($locus);
		if ( !@$sequences ) {
			$logger->error("No translated sequences generated for $locus.");
			return;
		}
	} else {
		$sequences = get_alleles($locus);
		if ( !@$sequences ) {
			$logger->error("No sequences defined for $locus.");
			return;
		}
	}
	my $mutations =
	  $script->{'datastore'}->run_query( 'SELECT * FROM peptide_mutations WHERE locus=? ORDER BY locus_position',
		$locus, { fetch => 'all_arrayref', slice => {}, cache => 'get_locus_peptide_mutations' } );
	foreach my $mutation (@$mutations) {
		my $alleles_to_check = get_alleles_to_check_peptide_mutations( $locus, $mutation->{'id'} );
		next if !@$alleles_to_check;
		my $most_common_length;
		my $wt_seq;
		if ( defined $mutation->{'wild_type_allele_id'} ) {
			$wt_seq = extract_allele( $sequences, $mutation->{'wild_type_allele_id'} );
			if ( !defined $wt_seq ) {
				die "Wild type allele defined for $locus (allele $mutation->{'wild_type_allele_id'}) does not exist.\n";
			}
			$most_common_length = find_most_common_sequence_length_with_wt(
				[$wt_seq],
				$mutation->{'locus_position'},
				$mutation->{'wild_type_aa'}
			);
		} else {
			$most_common_length = find_most_common_sequence_length_with_wt(
				$sequences,
				$mutation->{'locus_position'},
				$mutation->{'wild_type_aa'}
			);
		}
		( my $wt      = $mutation->{'wild_type_aa'} ) =~ s/;//gx;
		( my $variant = $mutation->{'variant_aa'} )   =~ s/;//gx;
		say "$locus - $wt$mutation->{'reported_position'}$variant:"
		  if !$opts{'quiet'};
		if ( !$most_common_length ) {
			say "$locus: No sequences found with WT amino acid '$mutation->{'wild_type_aa'}' "
			  . "at position $mutation->{'locus_position'}.";
			next;
		}
		my $flanking = $opts{'flanking'} // $mutation->{'flanking_length'};
		my $motifs   = define_motifs(
			( defined $mutation->{'wild_type_allele_id'} ? [$wt_seq] : $sequences ),
			$flanking, $most_common_length,
			$mutation->{'locus_position'},
			$mutation->{'wild_type_aa'},
			$mutation->{'variant_aa'}
		);
		annotate_alleles_with_peptide_mutations( $locus, $mutation->{'id'}, $motifs );
	}
	return;
}

sub process_dna_mutation {
	my ($locus) = @_;
	my $sequences = get_alleles($locus);
	if ( !@$sequences ) {
		$logger->error("No sequences defined for $locus.");
		return;
	}
	my $mutations =
	  $script->{'datastore'}->run_query( 'SELECT * FROM dna_mutations WHERE locus=? ORDER BY locus_position',
		$locus, { fetch => 'all_arrayref', slice => {}, cache => 'get_locus_dna_mutations' } );
	foreach my $mutation (@$mutations) {
		my $alleles_to_check = get_alleles_to_check_dna_mutations( $locus, $mutation->{'id'} );
		next if !@$alleles_to_check;
		my $most_common_length;
		if ( defined $mutation->{'wild_type_allele_id'} ) {
			my $wt_seq = extract_allele( $sequences, $mutation->{'wild_type_allele_id'} );
			if ( !defined $wt_seq ) {
				die "Wild type allele defined for $locus (allele $mutation->{'wild_type_allele_id'}) does not exist.\n";
			}
			$most_common_length = find_most_common_sequence_length_with_wt(
				[$wt_seq],
				$mutation->{'locus_position'},
				$mutation->{'wild_type_nuc'}
			);
		} else {
			$most_common_length = find_most_common_sequence_length_with_wt(
				$sequences,
				$mutation->{'locus_position'},
				$mutation->{'wild_type_nuc'}
			);
		}
		( my $wt      = $mutation->{'wild_type_nuc'} ) =~ s/;//gx;
		( my $variant = $mutation->{'variant_nuc'} )   =~ s/;//gx;
		say "$locus - $wt$mutation->{'reported_position'}$variant:"
		  if !$opts{'quiet'};
		if ( !$most_common_length ) {
			say "$locus: No sequences found with WT nucleotide '$mutation->{'wild_type_nuc'}' "
			  . "at position $mutation->{'locus_position'}.";
			next;
		}
		my $flanking = $opts{'flanking'} // $mutation->{'flanking_length'};
		my $motifs   = define_motifs(
			$sequences, $flanking, $most_common_length,
			$mutation->{'locus_position'},
			$mutation->{'wild_type_nuc'},
			$mutation->{'variant_nuc'}
		);
		annotate_alleles_with_dna_mutations( $locus, $mutation->{'id'}, $motifs );
	}
	return;
}

sub extract_allele {
	my ( $sequences, $allele_id ) = @_;
	foreach my $seq (@$sequences) {
		next if $seq->{'allele_id'} ne $allele_id;
		return $seq;
	}
	return;
}

sub get_alleles_to_check_peptide_mutations {
	my ( $locus, $mutation_id ) = @_;
	my $locus_info = $script->{'datastore'}->get_locus_info($locus);
	my $order      = $locus_info->{'allele_id_format'} eq 'integer' ? 'CAST(allele_id AS int)' : 'allele_id';
	return $script->{'datastore'}->run_query(
		'SELECT allele_id,sequence FROM sequences s WHERE locus=? AND allele_id NOT IN (?,?) AND allele_id NOT IN '
		  . '(SELECT allele_id FROM sequences_peptide_mutations m WHERE (m.locus,m.mutation_id)=(s.locus,?)) ORDER '
		  . "BY $order",
		[ $locus, 0, 'N', $mutation_id ],
		{ fetch => 'all_arrayref', slice => {}, cache => 'get_alleles_to_check_peptide_mutations' }
	);
}

sub get_alleles_to_check_dna_mutations {
	my ( $locus, $mutation_id ) = @_;
	my $locus_info = $script->{'datastore'}->get_locus_info($locus);
	my $order      = $locus_info->{'allele_id_format'} eq 'integer' ? 'CAST(allele_id AS int)' : 'allele_id';
	return $script->{'datastore'}->run_query(
		'SELECT allele_id,sequence FROM sequences s WHERE locus=? AND allele_id NOT IN (?,?) AND allele_id NOT IN '
		  . '(SELECT allele_id FROM sequences_dna_mutations m WHERE (m.locus,m.mutation_id)=(s.locus,?)) ORDER '
		  . "BY $order",
		[ $locus, 0, 'N', $mutation_id ],
		{ fetch => 'all_arrayref', slice => {}, cache => 'get_alleles_to_check_dna_mutations' }
	);
}

sub annotate_alleles_with_peptide_mutations {
	my ( $locus, $mutation_id, $motifs ) = @_;
	my $alleles  = get_alleles_to_check_peptide_mutations( $locus, $mutation_id );
	my $mutation = $script->{'datastore'}->run_query( 'SELECT * FROM peptide_mutations WHERE id=?',
		$mutation_id, { fetch => 'row_hashref', cache => 'get_peptide_mutation' } );
	my %variant_aas = map { $_ => 1 } split /;/x, $mutation->{'variant_aa'};
	my %wt_aas      = map { $_ => 1 } split /;/x, $mutation->{'wild_type_aa'};
	my $job_id      = BIGSdb::Utils::get_random();
	my $db_type     = 'prot';
	create_blast_database( $job_id, $db_type, $motifs->{'motifs'} );
	my $flanking = $opts{'flanking'} // $mutation->{'flanking_length'};
	my $insert_sql =
	  $script->{'db'}->prepare( 'INSERT INTO sequences_peptide_mutations '
		  . '(locus,allele_id,mutation_id,amino_acid,is_wild_type,is_mutation,curator,datestamp) '
		  . 'VALUES (?,?,?,?,?,?,?,?)' );

	foreach my $allele (@$alleles) {
		my $best_match = run_blast( $job_id, $db_type, $locus, \$allele->{'sequence'} );
		if ( !$best_match || !keys %$best_match || $best_match->{'evalue'} > EVALUE_THRESHOLD ) {
			if ( !$opts{'quiet'} ) {
				print "$locus-$allele->{'allele_id'}: motif not found";
				if ( $best_match->{'sseqid'} ) {
					say " - best match e-value: $best_match->{'evalue'}.";
				} else {
					say '.';
				}
			}
			next;
		}
		my $seq_ref = extract_seq_from_match( $locus, $flanking, 'prot', \$allele->{'sequence'}, $best_match );
		my $pos     = $flanking - $motifs->{'offset'};
		if ( $pos >= length $$seq_ref || length $$seq_ref < ( 2 * $flanking + 1 ) ) {
			my $closest_motif = get_motif( $motifs->{'motifs'}, $best_match->{'sseqid'} ) // 'NO VALUE';
			my $buffer        = "$locus-$allele->{'allele_id'}: extracted motif too short "
			  . "($$seq_ref - closest: $closest_motif). Creating alignment.\n";
			if ( $best_match->{'gapopen'} == 1 ) {
				my ( $gap_position, $gap_length ) = find_gap_position( $seq_ref, \$closest_motif, 'protein' );
				if ( !defined $gap_position ) {
					$buffer .= "No gap found.\n";
					say $buffer if !$opts{'quiet'};
					next;
				}
				$buffer .= "Gap at position $gap_position (length: $gap_length)";
				if ( $gap_position < $flanking ) {
					$pos = $pos - $gap_length;
					$buffer .= ' - modifying offset.';
				} else {
					$buffer .= ' - offset unchanged.';
				}
				say $buffer if !$opts{'quiet'};
			} else {
				$buffer .= "No gap found.\n";
				say $buffer if !$opts{'quiet'};
				next;
			}
		}
		my $aa = substr( $$seq_ref, $pos, 1 );

		#TODO Define curator_id.
		my $is_wt  = $wt_aas{$aa}      ? 1 : 0;
		my $is_mut = $variant_aas{$aa} ? 1 : 0;
		if ( !$opts{'quiet'} ) {
			say "$allele->{'allele_id'}: $$seq_ref\t$aa - WT:$is_wt; Mutation:$is_mut.";
			if ( !$is_wt && !$is_mut ) {
				say 'Neither WT or recognized mutation found - not updating.';
			}
		}
		if ( $is_wt || $is_mut ) {
			eval {
				$insert_sql->execute( $locus, $allele->{'allele_id'}, $mutation_id, $aa, $is_wt, $is_mut, 0, 'now' );
			};
			if ($@) {
				$logger->error($@);
				$script->{'db'}->rollback;
				exit;
			} else {
				$script->{'db'}->commit;
			}
		}
	}
	$script->delete_temp_files("$script->{'config'}->{'secure_tmp_dir'}/$job_id*");
	return;
}

sub find_gap_position {
	my ( $qry_seq_ref, $ref_seq_ref, $alphabet ) = @_;
	my $seq1    = Bio::Seq->new( -seq => $$qry_seq_ref, -alphabet => $alphabet, -id => 'qry' );
	my $seq2    = Bio::Seq->new( -seq => $$ref_seq_ref, -alphabet => $alphabet, -id => 'ref' );
	my $factory = Bio::Tools::Run::Alignment::Clustalw->new;

	# Save the original STDOUT and STDERR
	open my $oldout, '>&STDOUT' or croak "Cannot duplicate STDOUT: $!";
	open my $olderr, '>&', \*STDERR or croak "Cannot duplicate STDERR: $!";

	# Redirect STDOUT and STDERR to /dev/null
	open STDOUT, '>', '/dev/null' or croak "Cannot redirect STDOUT to /dev/null: $!";
	open STDERR, '>', '/dev/null' or croak "Cannot redirect STDERR to /dev/null: $!";
	my $aln = $factory->align( [ $seq1, $seq2 ] );

	# Restore the original STDOUT and STDERR
	open STDOUT, '>&', $oldout or croak "Cannot restore STDOUT: $!";
	open STDERR, '>&', $olderr or croak "Cannot restore STDERR: $!";
	my ( $gap_pos, $gap_length );
	for my $seq ( $aln->each_seq ) {
		my $string = $seq->seq;
		if ( $string =~ /(\.+)/x ) {
			$gap_pos    = index( $string, $1 );
			$gap_length = length $1;
			last;
		}
	}
	return ( $gap_pos, $gap_length );
}

sub get_motif {
	my ( $motifs, $id ) = @_;
	foreach my $motif (@$motifs) {
		if ( $motif->{'id'} == $id ) {
			return $motif->{'motif'};
		}
	}
	return;
}

sub annotate_alleles_with_dna_mutations {
	my ( $locus, $mutation_id, $motifs ) = @_;
	my $alleles  = get_alleles_to_check_dna_mutations( $locus, $mutation_id );
	my $mutation = $script->{'datastore'}->run_query( 'SELECT * FROM dna_mutations WHERE id=?',
		$mutation_id, { fetch => 'row_hashref', cache => 'get_dna_mutation' } );
	my %variant_nucs = map { $_ => 1 } split /;/x, $mutation->{'variant_nuc'};
	my %wt_nucs      = map { $_ => 1 } split /;/x, $mutation->{'wild_type_nuc'};
	my $job_id       = BIGSdb::Utils::get_random();
	my $db_type      = 'nucl';
	create_blast_database( $job_id, $db_type, $motifs->{'motifs'} );
	my $flanking = $opts{'flanking'} // $mutation->{'flanking_length'};
	my $pos      = $flanking - $motifs->{'offset'};
	my $insert_sql =
	  $script->{'db'}->prepare( 'INSERT INTO sequences_dna_mutations '
		  . '(locus,allele_id,mutation_id,nucleotide,is_wild_type,is_mutation,curator,datestamp) '
		  . 'VALUES (?,?,?,?,?,?,?,?)' );

	foreach my $allele (@$alleles) {
		my $best_match = run_blast( $job_id, $db_type, $locus, \$allele->{'sequence'} );
		if ( !$best_match || $best_match->{'evalue'} > EVALUE_THRESHOLD ) {
			say "$locus-$allele->{'allele_id'}: motif not found." if !$opts{'quiet'};
			next;
		}
		my $seq_ref = extract_seq_from_match( $locus, $flanking, 'dna', \$allele->{'sequence'}, $best_match );
		if ( $pos >= length $$seq_ref || length $$seq_ref < ( 2 * $flanking + 1 ) ) {
			say "$locus-$allele->{'allele_id'}: extracted motif too short." if !$opts{'quiet'};
			next;
		}
		my $nuc = substr( $$seq_ref, $pos, 1 );

		#TODO Define curator_id.
		my $is_wt  = $wt_nucs{$nuc}      ? 1 : 0;
		my $is_mut = $variant_nucs{$nuc} ? 1 : 0;
		eval { $insert_sql->execute( $locus, $allele->{'allele_id'}, $mutation_id, $nuc, $is_wt, $is_mut, 0, 'now' ); };
		if ($@) {
			$logger->error($@);
			$script->{'db'}->rollback;
			exit;
		}
		say "$allele->{'allele_id'}: $$seq_ref\t$nuc - WT:$is_wt; Mutation:$is_mut" if !$opts{'quiet'};
	}
	$script->{'db'}->commit;
	$script->delete_temp_files("$script->{'config'}->{'secure_tmp_dir'}/$job_id*");
	return;
}

sub extract_seq_from_match {
	my ( $locus, $flanking, $db_type, $seq_ref, $match ) = @_;
	my $locus_info = $script->{'datastore'}->get_locus_info($locus);
	my ( $start, $end );
	if ( $locus_info->{'data_type'} eq 'DNA' ) {
		if ( $db_type eq 'prot' ) {
			$start = $match->{'qstart'} - ( ( $match->{'sstart'} - 1 ) * 3 );
			$end =
			  $match->{'qend'} + ( ( $flanking * 2 + 1 - ( $match->{'send'} - $match->{'sstart'} + 1 ) ) * 3 ) + 1;
		} else {
			$start = $match->{'qstart'};
			$end   = $match->{'qend'} + 1;
		}
	} else {
		$start = $match->{'qstart'};
		$end   = $match->{'qend'} + 1;
	}
	my $seq = substr( $$seq_ref, $start - 1, ( $end - $start ) );
	if ( $locus_info->{'data_type'} eq 'DNA' && $db_type eq 'prot' ) {
		my $codon_table = $script->{'system'}->{'codon_table'} // 11;
		my $seq_obj     = Bio::Seq->new( -seq => $seq, -alphabet => 'dna' );
		$seq = $seq_obj->translate( -codontable_id => $codon_table )->seq;
	}
	return \$seq;
}

sub create_blast_database {
	my ( $job_id, $db_type, $motifs ) = @_;
	my $fasta_file = "$script->{'config'}->{'secure_tmp_dir'}/${job_id}.fasta";
	open( my $fasta_fh, '>:encoding(utf8)', $fasta_file ) || die "Cannot open $fasta_file for writing.\n";
	foreach my $motif (@$motifs) {
		say $fasta_fh ">$motif->{'id'}\n$motif->{'motif'}";
	}
	close $fasta_fh;
	system( "$script->{'config'}->{'blast+_path'}/makeblastdb",
		( -in => $fasta_file, -logfile => '/dev/null', -dbtype => $db_type ) );
	return;
}

sub run_blast {
	my ( $job_id, $db_type, $locus, $seq_ref ) = @_;
	my $locus_info = $script->{'datastore'}->get_locus_info($locus);
	my $program;
	if ( $db_type eq 'prot' ) {
		$program = $locus_info->{'data_type'} eq 'DNA' ? 'blastx' : 'blastp';
	} else {
		if ( $locus_info->{'data_type'} eq 'peptide' ) {
			die "Cannot query nucleotide mutations for a peptide locus.\n";
		}
		$program = 'blastn';
	}
	my $fasta_file = "$script->{'config'}->{'secure_tmp_dir'}/${job_id}.fasta";
	my $out_file   = "$script->{'config'}->{'secure_tmp_dir'}/${job_id}.out";
	my $in_file    = "$script->{'config'}->{'secure_tmp_dir'}/${job_id}.in";
	my $filter     = $program eq 'blastn' ? 'dust' : 'seg';
	open( my $fh, '>:encoding(utf8)', $in_file ) || die "Cannot open $in_file for writing.\n";
	say $fh ">in\n$$seq_ref";
	close $fh;
	my %params = (
		-db      => $fasta_file,
		-query   => $in_file,
		-out     => $out_file,
		-outfmt  => 6,
		-$filter => 'no'
	);
	$params{'-word_size'} = 7 if $program eq 'blastn';
	system( "$script->{'config'}->{'blast+_path'}/$program", %params );
	my $best_match = {};

	if ( -s $out_file ) {
		open( my $fh, '<:encoding(utf8)', $out_file ) || die "Cannot open $out_file for reading.\n";
		my $top_match = <$fh>;
		close $fh;
		my @fields = qw(qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore);
		my @values = split /\t/x, $top_match;
		%$best_match = map { $fields[$_] => $values[$_] } 0 .. $#values;
		$best_match->{'evalue'} = sprintf( '%.6f', $best_match->{'evalue'} );
	}
	return $best_match;
}

sub define_motifs {
	my ( $sequences, $flanking, $most_common_length, $pos, $wt, $variants ) = @_;
	my @wt     = split /;/x, $wt;
	my %wt     = map { $_ => 1 } @wt;
	my $start  = $pos - $flanking - 1;
	my $offset = 0;
	if ( $start < 0 ) {
		$offset = -$start;
		$start  = 0;
	}
	my $end = $pos + $flanking + $offset - 1;
	$end = ( $most_common_length - 1 ) if $end > ( $most_common_length - 1 );
	if ( ( $end - $start ) < ( 2 * $flanking ) ) {
		$offset = -( ( 2 * $flanking ) - ( $end - $start ) );
		$start += $offset;
	}
	my %used;
	my %allowed_char = map { $_ => 1 } ( @wt, split /;/x, $variants );
	my $motifs       = [];
	my $id           = 1;
	foreach my $allele (@$sequences) {
		next if length $allele->{'seq'} != $most_common_length;
		my $motif = substr( $allele->{'seq'}, $start, ( $end - $start + 1 ) );
		next if $used{$motif};
		$used{$motif} = 1;
		my $char = substr( $motif, $flanking - $offset, 1 );
		next if !$allowed_char{$char};
		push @$motifs,
		  {
			motif          => $motif,
			id             => $id,
			variant_char   => $char,
			wt             => ( $wt{$char} ? 1 : 0 ),
			from_allele_id => $allele->{'allele_id'}
		  };
		$id++;
	}
	return { motifs => $motifs, offset => $offset };
}

sub find_most_common_sequence_length_with_wt {
	my ( $sequences, $pos, $wt ) = @_;
	my %wt = map { $_ => 1 } split /;/x, $wt;
	my %lengths;
	foreach my $allele (@$sequences) {
		next if !$wt{ substr( $allele->{'seq'}, $pos - 1, 1 ) };
		my $length = length( $allele->{'seq'} );
		$lengths{$length}++;
	}
	my $most_common_length;
	foreach my $length ( sort keys %lengths ) {
		if ( !defined $most_common_length || $lengths{$length} > $lengths{$most_common_length} ) {
			$most_common_length = $length;
		}
	}
	return $most_common_length;
}

sub get_translated_alleles {
	my ($locus)     = @_;
	my $locus_info  = $script->{'datastore'}->get_locus_info($locus);
	my $codon_table = $script->{'system'}->{'codon_table'} // 11;
	my $orf         = $locus_info->{'orf'}                 // 1;
	my $reverse;
	if ( $orf > 3 ) {
		$reverse = 1;
		$orf     = $orf - 3;
	}
	my $order   = $locus_info->{'allele_id_format'} eq 'integer' ? 'CAST(allele_id AS int)' : 'allele_id';
	my $alleles = $script->{'datastore'}->run_query(
		"SELECT allele_id,sequence FROM sequences WHERE locus=? AND allele_id NOT IN (?,?) ORDER BY $order",
		[ $locus, 0, 'N' ],
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $translated = [];
	foreach my $allele (@$alleles) {
		my $seq = $reverse ? BIGSdb::Utils::reverse_complement( $allele->{'sequence'} ) : $allele->{'sequence'};
		if ( $orf > 1 && $orf <= 3 ) {
			$seq = substr( $seq, $orf - 1 );
		}
		my $seq_obj = Bio::Seq->new( -seq => $seq, -alphabet => 'dna' );
		my $peptide = $seq_obj->translate( -codontable_id => $codon_table )->seq;
		$peptide =~ s/\*$//x;            #Remove terminal stop codon.
		next if $peptide =~ /\*/gx;      #Ignore any alleles with internal stops.
		push @$translated, { allele_id => $allele->{'allele_id'}, seq => $peptide };
	}
	return $translated;
}

sub get_alleles {
	my ($locus)    = @_;
	my $locus_info = $script->{'datastore'}->get_locus_info($locus);
	my $order      = $locus_info->{'allele_id_format'} eq 'integer' ? 'CAST(allele_id AS int)' : 'allele_id';
	return $script->{'datastore'}->run_query(
		"SELECT allele_id,sequence AS seq FROM sequences WHERE locus=? AND allele_id NOT IN (?,?,?) ORDER BY $order",
		[ $locus, 0, 'N', 'P' ],
		{ fetch => 'all_arrayref', slice => {} }
	);
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t      = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw/me md us/;
	say << "HELP";
${bold}NAME$norm
    ${bold}scan_mutations.pl$norm - Search for mutations in defined allele sequences

${bold}SYNOPSIS$norm
    ${bold}scan_mutations.pl --database ${under}DB_CONFIG$norm [${under}options$norm]

${bold}OPTIONS$norm

${bold}--database$norm ${under}DATABASE CONFIG$norm
    Database configuration name.
    
${bold}--exclude_loci$norm ${under}LIST$norm
    Comma-separated list of loci to exclude.
    
${bold}--flanking$norm ${under}LENGTH$norm
    Length of flanking sequence to use either side of mutation site when 
    defining search motifs. Default: 10.
    
${bold}--help$norm
    This help page.
    
${bold}--loci$norm ${under}LIST$norm
    Comma-separated list of loci to scan (ignored if --schemes used).
 
${bold}--locus_regex$norm ${under}REGEX$norm
    Regex for locus names.
   
${bold}--quiet$norm
    Only show errors.  
    
${bold}--rescan$norm
    Remove existing designations and rescan. 

${bold}--schemes$norm ${under}LIST$norm
    Comma-separated list of scheme loci to scan.   
HELP
	return;
}
