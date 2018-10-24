#!/usr/bin/env perl
#Automatically curate the 'easy' allele submissions
#Written by Keith Jolley
#Copyright (c) 2016-2018, University of Oxford
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
use strict;
use warnings;
use 5.010;
###########Local configuration#############################################
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases',
	HOST             => undef,                  #Use values in config.xml
	PORT             => undef,                  #But you can override here.
	USER             => undef,
	PASSWORD         => undef
};
#######End Local configuration#############################################
use lib (LIB_DIR);
use BIGSdb::Offline::Script;
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
use constant DEFINER_USER     => -1;              #User id for tagger (there needs to be a record in the users table)
use constant DEFINER_USERNAME => 'autodefiner';
use constant DEFAULT_IDENTITY => 98;
my %opts;
GetOptions(
	'database=s'     => \$opts{'d'},
	'exclude_loci=s' => \$opts{'L'},
	'help'           => \$opts{'h'},
	'identity=f'     => \$opts{'identity'},
	'loci=s'         => \$opts{'l'},
	'locus_regex=s'  => \$opts{'R'},
	'schemes=s'      => \$opts{'s'},
	'submission=s'   => \$opts{'submission'}
) or die("Error in command line arguments\n");

if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( !$opts{'d'} ) {
	say "\nUsage: allele_curator.pl --database <NAME>\n";
	say 'Help: allele_curator.pl --help';
	exit;
}
my $script = BIGSdb::Offline::Script->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		host             => HOST,
		port             => PORT,
		user             => USER,
		password         => PASSWORD,
		options          => \%opts,
		instance         => $opts{'d'},
	}
);
die "Script initialization failed - check logs (authentication problems or server too busy?).\n"
  if !defined $script->{'db'};
die "This script can only be run against a seqdef database.\n"
  if ( $script->{'system'}->{'dbtype'} // '' ) ne 'sequences';
die "The autodefiner user does not exist in the users table.\n" if !user_exists();
$script->setup_submission_handler;
$opts{'identity'} //= DEFAULT_IDENTITY;
main();

sub main {
	my $loci           = $script->get_selected_loci;
	my %allowed_loci   = map { $_ => 1 } @$loci;
	my $submission_ids = get_submissions();
	foreach my $submission_id (@$submission_ids) {
		my $submission        = $script->{'submissionHandler'}->get_submission($submission_id);
		my $allele_submission = $script->{'submissionHandler'}->get_allele_submission($submission_id);
		next if !$allele_submission;
		next if $allele_submission->{'technology'} eq 'Sanger';
		next if !$allowed_loci{ $allele_submission->{'locus'} };
		my $locus_info = $script->{'datastore'}->get_locus_info( $allele_submission->{'locus'} );
		next if $locus_info->{'allele_id_format'} ne 'integer';
		my $ext_attributes =
		  $script->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM locus_extended_attributes WHERE locus=?)',
			$allele_submission->{'locus'} );
		next if $ext_attributes;
		say "Submission: $submission_id";
		my $seqs = $allele_submission->{'seqs'};
	  SEQS: foreach my $seq (@$seqs) {
			$seq->{'sequence'} =~ s/[\-\.\s]//gx;
			if ( $locus_info->{'complete_cds'} ) {
				my $complete_cds = BIGSdb::Utils::is_complete_cds( $seq->{'sequence'} );
				if ( !$complete_cds->{'cds'} ) {
					say "$seq->{'seq_id'}: Rejected - not complete CDS.";
					next SEQS;
				}
			}
			my $seq_exists = $script->{'datastore'}->run_query(
				'SELECT allele_id FROM sequences WHERE (locus,sequence)=(?,?)',
				[ $allele_submission->{'locus'}, $seq->{'sequence'} ]
			);
			if ($seq_exists) {
				say "$seq->{'seq_id'}: Rejected - sequence already exists - allele $seq_exists.";
				next SEQS;
			}
			my $ref_seqs = $script->{'datastore'}->run_query(
				'SELECT sequence FROM sequences WHERE (locus,length(sequence))=(?,?)',
				[ $allele_submission->{'locus'}, length $seq->{'sequence'} ],
				{ fetch => 'col_arrayref' }
			);
		  COMPARE_SEQS: foreach my $ref_seq (@$ref_seqs) {
				if ( are_sequences_similar( uc( $seq->{'sequence'} ), $ref_seq, $opts{'identity'} ) ) {
					my $assigned_id = assign_allele( $allele_submission->{'locus'}, $seq->{'sequence'} );
					say "$seq->{'seq_id'}: Assigned: $allele_submission->{'locus'}-$assigned_id";
					eval {
						$script->{'db'}->do(
							'INSERT INTO sequences(locus,allele_id,sequence,sender,curator,date_entered,'
							  . 'datestamp,status) VALUES (?,?,?,?,?,?,?,?)',
							undef,
							$allele_submission->{'locus'},
							$assigned_id,
							uc( $seq->{'sequence'} ),
							$submission->{'submitter'},
							DEFINER_USER,
							'now',
							'now',
							'unchecked'
						);
					};
					if ($@) {
						$script->{'db'}->rollback;
						die "$@\n";
					}
					$script->{'db'}->commit;
					$script->{'submissionHandler'}
					  ->set_allele_status( $submission_id, $seq->{'seq_id'}, 'assigned', $assigned_id );
					next SEQS;
				}
			}
			say "$seq->{'seq_id'}: Rejected - too dissimilar to existing allele.";
		}
		my $all_assigned = are_all_alleles_assigned($submission_id);
		if ($all_assigned) {
			close_submission($submission_id);
		}
	}

	#TODO Update BLAST caches if changes.
	return;
}

sub close_submission {
	my ($submission_id) = @_;
	my $submission = $script->{'submissionHandler'}->get_submission($submission_id);
	return if !$submission;
	eval {
		$script->{'db'}->do( 'UPDATE submissions SET (status,outcome,datestamp,curator)=(?,?,?,?) WHERE id=?',
			undef, 'closed', 'good', 'now', DEFINER_USER, $submission_id );
	};
	if ($@) {
		$script->{'db'}->rollback;
		die "$@\n";
	}
	$script->{'db'}->commit;
	if ( $submission->{'email'} ) {
		my $desc = $script->{'system'}->{'description'} || 'BIGSdb';
		$script->{'submissionHandler'}->email(
			$submission_id,
			{
				recipient => $submission->{'submitter'},
				sender    => DEFINER_USER,
				subject   => "$desc submission closed - $submission_id",
				message   => $script->{'submissionHandler'}->get_text_summary( $submission_id, { messages => 1 } )
			}
		);

		#Don't spam the mail servers.
		sleep 5;
	}
	return;
}

sub are_all_alleles_assigned {
	my ($submission_id) = @_;
	my $allele_submission = $script->{'submissionHandler'}->get_allele_submission($submission_id);
	return if !$allele_submission;
	my $all_assigned = 1;
	foreach my $seq ( @{ $allele_submission->{'seqs'} } ) {
		$all_assigned = 0 if $seq->{'status'} ne 'assigned';
	}
	return $all_assigned;
}

sub assign_allele {
	my ( $locus, $sequence ) = @_;
	my $allele_id = $script->{'datastore'}->get_next_allele_id($locus);
	return $allele_id;
}

sub are_sequences_similar {
	my ( $seq1, $seq2, $identity_threshold ) = @_;
	die "Sequences are not the same length.\n" if length $seq1 != length $seq2;
	my $diffs  = 0;
	my $length = length $seq1;
	foreach my $pos ( 0 .. ( $length - 1 ) ) {
		$diffs++ if substr( $seq1, $pos, 1 ) ne substr( $seq2, $pos, 1 );
	}
	my $identity = 100 - ( $diffs * 100 / $length );
	return 1 if $identity >= $identity_threshold;
	return;
}

sub get_submissions {
	if ( $opts{'submission'} ) {
		my $exists =
		  $script->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM submissions WHERE (id,type)=(?,?))',
			[ $opts{'submission'}, 'alleles' ] );
		die "No allele submission $opts{'submission'} exists.\n" if !$exists;
		return [ $opts{'submission'} ];
	}
	my $submissions = $script->{'datastore'}->run_query(
		'SELECT id FROM submissions WHERE (status,type)=(?,?) ORDER BY id',
		[ 'pending', 'alleles' ],
		{ fetch => 'col_arrayref' }
	);
	return $submissions;
}

sub user_exists {
	return $script->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM users WHERE (id,user_name)=(?,?))',
		[ DEFINER_USER, DEFINER_USERNAME ] );
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw(me md us);
	say << "HELP";
${bold}NAME$norm
    ${bold}allele_curator.pl$norm - Automatically curate the 'easy' allele
    submissions

${bold}SYNOPSIS$norm
    ${bold}allele_curator.pl --database ${under}NAME$norm${bold}$norm [${under}options$norm]

${bold}OPTIONS$norm

${bold}--database$norm ${under}NAME$norm
    Database configuration name.
    
${bold}--exclude_loci$norm ${under}LIST$norm
    Comma-separated list of loci to exclude
    
${bold}--help$norm
    This help page.
    
${bold}--identity$norm ${under}IDENTITY$norm
    Alleles must have >= %identity to an allele of the same length to be
    accepted. Default: 98.
    
${bold}--loci$norm ${under}LIST$norm
    Comma-separated list of loci to scan (ignored if -s used).
    
${bold}--locus_regex$norm ${under}REGEX$norm
    Regex for locus names.    

${bold}--schemes$norm ${under}LIST$norm
    Comma-separated list of scheme loci to scan.
   
${bold}--submission$norm ${under}SUBMISSION ID$norm
    Submission id.
    
HELP
	return;
}
