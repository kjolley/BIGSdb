#Written by Keith Jolley
#Copyright (c) 2015-2017, University of Oxford
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

#Limits
use constant MAX_SPLITS_TAXA       => 150;
use constant MAX_MUSCLE_MB         => 4 * 1024;    #4GB
use constant MAX_ISOLATES_DROPDOWN => 1000;
push @EXPORT_OK, qw(MAX_SPLITS_TAXA MAX_MUSCLE_MB MAX_ISOLATES_DROPDOWN);
$EXPORT_TAGS{'limits'} = [qw(MAX_SPLITS_TAXA MAX_MUSCLE_MB MAX_ISOLATES_DROPDOWN)];

#Methods
use constant SEQ_METHODS =>
  ( '454', 'Illumina', 'Ion Torrent', 'PacBio', 'Oxford Nanopore', 'Sanger', 'Solexa', 'SOLiD', 'other' );
push @EXPORT_OK, qw(SEQ_METHODS);

#Interface
use constant BUTTON_CLASS       => 'submitbutton ui-button ui-widget ui-state-default ui-corner-all';
use constant RESET_BUTTON_CLASS => 'resetbutton ui-button ui-widget ui-state-default ui-corner-all';
use constant FACE_STYLE         => (
	good  => q(class="fa fa-lg fa-smile-o" style="color:green"),
	mixed => q(class="fa fa-lg fa-meh-o" style="color:blue"),
	bad   => q(class="fa fa-lg fa-frown-o" style="color:red")
);
use constant SHOW     => q(<span class="fa fa-lg fa-plus-circle" style="color:green"></span>);
use constant HIDE     => q(<span class="fa fa-lg fa-minus-circle" style="color:red"></span>);
use constant SAVE     => q(<span class="fa fa-lg fa-save" style="color:green"></span>);
use constant SAVING   => q(<span class="fa fa-lg fa-save" style="color:blue"></span>);
use constant UP       => q(<span class="fa fa-lg fa-arrow-up" style="color:blue"></span>);
use constant DOWN     => q(<span class="fa fa-lg fa-arrow-down" style="color:blue"></span>);
use constant LEFT     => q(<span class="fa fa-lg fa-arrow-left" style="color:blue"></span>);
use constant RIGHT    => q(<span class="fa fa-lg fa-arrow-right" style="color:blue"></span>);
use constant EDIT     => q(<span class="fa fa-lg fa-pencil" style="color:#44a"></span>);
use constant DELETE   => q(<span class="fa fa-lg fa-times" style="color:#a44"></span>);
use constant ADD      => q(<span class="fa fa-lg fa-plus" style="color:#4a4"></span>);
use constant COMPARE  => q(<span class="fa fa-lg fa-balance-scale" style="color:#44a"></span>);
use constant UPLOAD   => q(<span class="fa fa-lg fa-upload" style="color:#4a4"></span>);
use constant QUERY    => q(<span class="fa fa-lg fa-search" style="color:#44a"></span>);
use constant GOOD     => q(<span class="statusgood fa fa-lg fa-check"></span>);
use constant BAD      => q(<span class="statusbad fa fa-lg fa-times"></span>);
use constant TRUE     => q(<span class="fa fa-lg fa-check-square-o"></span>);
use constant FALSE    => q(<span class="fa fa-lg fa-square-o"></span>);
use constant DOWNLOAD => q(<span class="fa fa-lg fa-download" style="color:#44a"></span>);
use constant BACK     => q(<span class="main_icon fa fa-2x fa-arrow-circle-o-left"></span>);
use constant FLANKING => qw(0 20 50 100 200 500 1000 2000 5000 10000 25000 50000);
use constant MAX_ROWS => 20;
my @values = qw(BUTTON_CLASS RESET_BUTTON_CLASS FACE_STYLE SHOW HIDE SAVE SAVING UP DOWN LEFT RIGHT
  EDIT DELETE ADD COMPARE UPLOAD QUERY GOOD BAD TRUE FALSE DOWNLOAD BACK FLANKING MAX_ROWS);
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
use constant SUBMITTER_ALLOWED_PERMISSIONS => qw(modify_isolates modify_sequences tag_sequences designate_alleles);
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
push @EXPORT_OK, qw (SUBMISSIONS_DELETED_DAYS COVERAGE READ_LENGTH ASSEMBLY REQUIRES_READ_LENGTH
  REQUIRES_COVERAGE REQUIRED_GENOME_FIELDS DAILY_REST_LIMIT TOTAL_PENDING_LIMIT DAILY_PENDING_LIMIT);
$EXPORT_TAGS{'submissions'} = [
	qw (SUBMISSIONS_DELETED_DAYS COVERAGE READ_LENGTH ASSEMBLY REQUIRES_READ_LENGTH
	  REQUIRES_COVERAGE REQUIRED_GENOME_FIELDS DAILY_REST_LIMIT TOTAL_PENDING_LIMIT DAILY_PENDING_LIMIT)
];

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
