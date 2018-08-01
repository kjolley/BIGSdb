#Written by Keith Jolley
#Copyright (c) 2015-2018, University of Oxford
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
package BIGSdb::Constants;
use parent 'Exporter';
use strict;
use warnings;
our @EXPORT_OK;
our %EXPORT_TAGS;
use constant DEFAULT_DOMAIN => 'pubmlst.org';
push @EXPORT_OK, qw(DEFAULT_DOMAIN);

#Limits
use constant MAX_SPLITS_TAXA       => 150;
use constant MAX_MUSCLE_MB         => 4 * 1024;    #4GB
use constant MAX_ISOLATES_DROPDOWN => 1000;
use constant MAX_EAV_FIELD_LIST    => 100;
my @values = qw(MAX_SPLITS_TAXA MAX_MUSCLE_MB MAX_ISOLATES_DROPDOWN MAX_EAV_FIELD_LIST);
push @EXPORT_OK, @values;
$EXPORT_TAGS{'limits'} = [@values];

#Methods
use constant SEQ_METHODS =>
  ( '454', 'Illumina', 'Ion Torrent', 'PacBio', 'Oxford Nanopore', 'Sanger', 'Solexa', 'SOLiD', 'other' );
push @EXPORT_OK, qw(SEQ_METHODS);

#Interface
use constant BUTTON_CLASS       => 'submitbutton ui-button ui-widget ui-state-default ui-corner-all';
use constant RESET_BUTTON_CLASS => 'resetbutton ui-button ui-widget ui-state-default ui-corner-all';
use constant FACE_STYLE         => (
	good  => q(class="far fa-lg fa-smile" style="color:green"),
	mixed => q(class="far fa-lg fa-meh" style="color:blue"),
	bad   => q(class="far fa-lg fa-frown" style="color:red")
);
use constant SHOW           => q(<span class="fas fa-plus-circle" style="color:green"></span>);
use constant HIDE           => q(<span class="fas fa-minus-circle" style="color:red"></span>);
use constant SAVE           => q(<span class="fas fa-save" style="color:green"></span>);
use constant SAVING         => q(<span class="fas fa-save" style="color:blue"></span>);
use constant UP             => q(<span class="fas fa-arrow-up" style="color:blue"></span>);
use constant DOWN           => q(<span class="fas fa-arrow-down" style="color:blue"></span>);
use constant LEFT           => q(<span class="fas fa-lg fa-arrow-left" style="color:blue"></span>);
use constant RIGHT          => q(<span class="fas fa-lg fa-arrow-right" style="color:blue"></span>);
use constant EDIT           => q(<span class="fas fa-pencil-alt" style="color:#44a"></span>);
use constant DELETE         => q(<span class="fas fa-times" style="color:#a44"></span>);
use constant ADD            => q(<span class="fas fa-plus" style="color:#080"></span>);
use constant COMPARE        => q(<span class="fas fa-balance-scale" style="color:#44a"></span>);
use constant UPLOAD         => q(<span class="fas fa-upload" style="color:#080"></span>);
use constant QUERY          => q(<span class="fas fa-search" style="color:#44a"></span>);
use constant USERS          => q(<span class="fas fa-users" style="color:#a4a"></span>);
use constant GOOD           => q(<span class="statusgood fas fa-check"></span>);
use constant BAD            => q(<span class="statusbad fas fa-times"></span>);
use constant TRUE           => q(<span class="far fa-lg fa-check-square"></span>);
use constant FALSE          => q(<span class="far fa-lg fa-square"></span>);
use constant BAN            => q(<span class="fas fa-ban" style="color:#a44"></span>);
use constant DOWNLOAD       => q(<span class="fas fa-download" style="color:#44a"></span>);
use constant BACK           => q(<span class="nav_icon fas fa-2x fa-arrow-circle-left"></span>);
use constant QUERY_MORE     => q(<span class="nav_icon fas fa-2x fa-search"></span>);
use constant EDIT_MORE      => q(<span class="nav_icon fas fa-2x fa-pencil-alt"></span>);
use constant UPLOAD_CONTIGS => q(<span class="nav_icon fas fa-2x fa-dna"></span>);
use constant LINK_CONTIGS   => q(<span class="nav_icon fas fa-2x fa-link"></span>);
use constant MORE           => q(<span class="nav_icon fas fa-2x fa-plus"></span>);
use constant HOME           => q(<span class="nav_icon fas fa-2x fa-home"></span>);
use constant RELOAD         => q(<span class="nav_icon fas fa-2x fa-sync"></span>);
use constant KEY            => q(<span class="nav_icon fas fa-2x fa-key"></span>);
use constant EYE_SHOW       => q(<span class="nav_icon fas fa-2x fa-eye"></span>);
use constant EYE_HIDE       => q(<span class="nav_icon fas fa-2x fa-eye-slash"></span>);
use constant EXCEL_FILE => q(<span class="file_icon far fa-2x fa-file-excel" style="color:green"></span>);
use constant TEXT_FILE  => q(<span class="file_icon far fa-2x fa-file-alt" style="color:#333"></span>);
use constant FLANKING   => qw(0 20 50 100 200 500 1000 2000 5000 10000 25000 50000);
use constant MAX_ROWS   => 20;
@values = qw(BUTTON_CLASS RESET_BUTTON_CLASS FACE_STYLE SHOW HIDE SAVE SAVING UP DOWN LEFT RIGHT
  EDIT DELETE ADD COMPARE UPLOAD QUERY USERS GOOD BAD TRUE FALSE BAN DOWNLOAD BACK QUERY_MORE EDIT_MORE 
  UPLOAD_CONTIGS LINK_CONTIGS MORE HOME RELOAD KEY EYE_SHOW EYE_HIDE EXCEL_FILE TEXT_FILE FLANKING MAX_ROWS);
push @EXPORT_OK, @values;
$EXPORT_TAGS{'interface'} = [@values];

#Queries
use constant LOCUS_PATTERN => qr/^(?:l|cn|la)_(.+?)(?:\|\|.+)?$/x;
use constant OPERATORS => ( '=', 'contains', 'starts with', 'ends with', '>', '>=', '<', '<=', 'NOT', 'NOT contain' );
push @EXPORT_OK, qw(LOCUS_PATTERN OPERATORS);

#Sequences
use constant SEQ_STATUS => (
	'Sanger trace checked',
	'WGS: manual extract (BIGSdb)',
	'WGS: automated extract (BIGSdb)',
	'WGS: visually checked',
	'WGS: automatically checked',
	'unchecked'
);
use constant SEQ_FLAGS => (
	'ambiguous read',
	'apparent misassembly',
	'atypical',
	'contains IS element',
	'downstream fusion',
	'frameshift',
	'indel',
	'internal stop codon',
	'no start codon',
	'no stop codon',
	'phase variable: off',
	'truncated',
	'upstream fusion'
);
use constant ALLELE_FLAGS => (
	'atypical',
	'contains IS element',
	'downstream fusion',
	'frameshift',
	'indel',
	'internal stop codon',
	'no start codon',
	'no stop codon',
	'phase variable: off',
	'truncated',
	'upstream fusion'
);
use constant DIPLOID            => qw(A C G T R Y W S M K);
use constant HAPLOID            => qw(A C G T);
use constant IDENTITY_THRESHOLD => 70;
push @EXPORT_OK, qw(SEQ_STATUS SEQ_FLAGS ALLELE_FLAGS DIPLOID HAPLOID IDENTITY_THRESHOLD);

#Databanks
use constant DATABANKS => qw(ENA Genbank);
push @EXPORT_OK, qw(DATABANKS);

#Permissions
use constant SUBMITTER_ALLOWED_PERMISSIONS => qw(modify_isolates modify_sequences tag_sequences designate_alleles
  only_private disable_access);
push @EXPORT_OK, qw(SUBMITTER_ALLOWED_PERMISSIONS);

#Submissions
use constant SUBMISSIONS_DELETED_DAYS => 90;
use constant COVERAGE                 => qw(<20x 20-49x 50-99x >100x);
use constant READ_LENGTH              => qw(<100 100-199 200-299 300-499 >500);
use constant ASSEMBLY                 => ( 'de novo', 'mapped' );
use constant REQUIRES_READ_LENGTH     => qw(Illumina);
use constant REQUIRES_COVERAGE        => qw(Illumina);
use constant REQUIRED_GENOME_FIELDS   => qw(assembly_filename sequence_method);
use constant DAILY_REST_LIMIT         => 50;
use constant TOTAL_PENDING_LIMIT      => 20;
use constant DAILY_PENDING_LIMIT      => 15;
@values = qw (SUBMISSIONS_DELETED_DAYS COVERAGE READ_LENGTH ASSEMBLY REQUIRES_READ_LENGTH
  REQUIRES_COVERAGE REQUIRED_GENOME_FIELDS DAILY_REST_LIMIT TOTAL_PENDING_LIMIT DAILY_PENDING_LIMIT);
push @EXPORT_OK, @values;
$EXPORT_TAGS{'submissions'} = [@values];

#Schemes
use constant SCHEME_FLAGS => ( 'experimental', 'in development', 'please cite', 'unpublished' );
use constant SCHEME_FLAG_COLOURS => {
	'please cite'    => '#990000',
	'experimental'   => '#4c9900',
	'in development' => '#4c0099',
	'unpublished'    => '#009999'
};
push @EXPORT_OK, qw (SCHEME_FLAGS SCHEME_FLAG_COLOURS);
$EXPORT_TAGS{'scheme_flags'} = [qw(SCHEME_FLAGS SCHEME_FLAG_COLOURS)];

#Log in
use constant NOT_ALLOWED => 0;
use constant OPTIONAL    => 1;
use constant REQUIRED    => 2;
push @EXPORT_OK, qw (NOT_ALLOWED OPTIONAL REQUIRED);
$EXPORT_TAGS{'login_requirements'} = [qw(NOT_ALLOWED OPTIONAL REQUIRED)];

#Account management
use constant NEW_ACCOUNT_VALIDATION_TIMEOUT_MINS => 60;
use constant INACTIVE_ACCOUNT_REMOVAL_DAYS       => 180;
push @EXPORT_OK, qw (NEW_ACCOUNT_VALIDATION_TIMEOUT_MINS INACTIVE_ACCOUNT_REMOVAL_DAYS);
$EXPORT_TAGS{'accounts'} = [qw(NEW_ACCOUNT_VALIDATION_TIMEOUT_MINS INACTIVE_ACCOUNT_REMOVAL_DAYS)];
1;
