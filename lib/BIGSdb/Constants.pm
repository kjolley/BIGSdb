#Written by Keith Jolley
#Copyright (c) 2015-2024, University of Oxford
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
package BIGSdb::Constants;
use parent 'Exporter';
use strict;
use warnings;
use utf8;
our @EXPORT_OK;
our %EXPORT_TAGS;
use constant DEFAULT_DOMAIN => 'pubmlst.org';
push @EXPORT_OK, qw(DEFAULT_DOMAIN);

#Design
use constant PAGE_MAX_WIDTH => 1600;
my @values = qw(PAGE_MAX_WIDTH);
push @EXPORT_OK, @values;
$EXPORT_TAGS{'design'} = [@values];

#Limits
use constant MAX_SPLITS_TAXA           => 150;
use constant MAX_MUSCLE_MB             => 4 * 1024;    #4GB
use constant MAX_ISOLATES_DROPDOWN     => 1000;
use constant MAX_EAV_FIELD_LIST        => 100;
use constant MAX_LOCUS_ORDER_BY        => 500;
use constant MAX_LOCI_NON_CACHE_SCHEME => 30;
use constant MIN_CONTIG_LENGTH         => 100;
use constant MIN_GENOME_SIZE           => 1_000_000;
@values = qw(MAX_SPLITS_TAXA MAX_MUSCLE_MB MAX_ISOLATES_DROPDOWN MAX_EAV_FIELD_LIST
  MAX_LOCUS_ORDER_BY MAX_LOCI_NON_CACHE_SCHEME MIN_CONTIG_LENGTH MIN_GENOME_SIZE);
push @EXPORT_OK, @values;
$EXPORT_TAGS{'limits'} = [@values];

#Methods
use constant SEQ_METHODS => (
	'454', 'Illumina',
	'Illumina + ONT hybrid',
	'Illumina + PacBio hybrid',
	'Ion Torrent', 'Oxford Nanopore',
	'PacBio', 'Sanger', 'Solexa', 'SOLiD', 'other', 'unknown'
);
push @EXPORT_OK, qw(SEQ_METHODS);

#Codons
use constant DEFAULT_CODON_TABLE => 11;
push @EXPORT_OK, qw(DEFAULT_CODON_TABLE);

#Isolate embargoes
use constant DEFAULT_EMBARGO       => 12;
use constant MAX_INITIAL_EMBARGO   => 24;
use constant MAX_TOTAL_EMBARGO     => 48;
@values = qw(DEFAULT_EMBARGO MAX_INITIAL_EMBARGO MAX_TOTAL_EMBARGO);
push @EXPORT_OK, @values;
$EXPORT_TAGS{'embargo'} = [@values];

#Interface
use constant FACE_STYLE => (
	good  => q(class="far fa-lg fa-smile" style="color:green"),
	mixed => q(class="far fa-lg fa-meh" style="color:blue"),
	bad   => q(class="far fa-lg fa-frown" style="color:red")
);
use constant SHOW                 => q(<span class="fas fa-plus-circle" style="color:green"></span>);
use constant HIDE                 => q(<span class="fas fa-minus-circle" style="color:red"></span>);
use constant SAVE                 => q(<span class="fas fa-save" style="color:green"></span>);
use constant SAVING               => q(<span class="fas fa-save" style="color:blue"></span>);
use constant UP                   => q(<span class="fas fa-arrow-up" style="color:blue"></span>);
use constant DOWN                 => q(<span class="fas fa-arrow-down" style="color:blue"></span>);
use constant LEFT                 => q(<span class="fas fa-lg fa-arrow-left" style="color:blue"></span>);
use constant RIGHT                => q(<span class="fas fa-lg fa-arrow-right" style="color:blue"></span>);
use constant EDIT                 => q(<span class="fas fa-pencil-alt" style="color:#44a"></span>);
use constant DELETE               => q(<span class="fas fa-times" style="color:#a44"></span>);
use constant ADD                  => q(<span class="fas fa-plus" style="color:#080"></span>);
use constant COMPARE              => q(<span class="fas fa-balance-scale" style="color:#44a"></span>);
use constant UPLOAD               => q(<span class="fas fa-upload" style="color:#080"></span>);
use constant UPLOAD_CHANGE_CONFIG => q(<span class="fas fa-upload" style="color:#800"></span>);
use constant QUERY                => q(<span class="fas fa-search" style="color:#44a"></span>);
use constant USERS                => q(<span class="fas fa-users" style="color:#a4a"></span>);
use constant PENDING              => q(<span class="fa fa-hourglass-half" style="color:#888"></span>);
use constant GOOD                 => q(<span class="statusgood fas fa-check"></span>);
use constant BAD                  => q(<span class="statusbad fas fa-times"></span>);
use constant MEH                  => q(<span class="statusmeh fas fa-minus"></span>);
use constant TRUE                 => q(<span class="far fa-lg fa-check-square" style="font-size:0.95em"></span>);
use constant FALSE                => q(<span class="far fa-lg fa-square" style="font-size:0.95em"></span>);
use constant BAN                  => q(<span class="fas fa-ban" style="color:#a44"></span>);
use constant DOWNLOAD             => q(<span class="fas fa-download" style="color:#44a"></span>);
use constant LOCK                 => q(<span class="fas fa-lock" style="color:#a44"></span>);
use constant UNLOCK               => q(<span class="fas fa-lock-open" style="color:#4a4"></span>);
use constant BACK                 => q(<span class="nav_icon fas fa-2x fa-arrow-circle-left"></span>);
use constant QUERY_MORE           => q(<span class="nav_icon fas fa-2x fa-search"></span>);
use constant EDIT_MORE            => q(<span class="nav_icon fas fa-2x fa-pencil-alt"></span>);
use constant UPLOAD_CONTIGS       => q(<span class="nav_icon fas fa-2x fa-dna"></span>);
use constant LINK_CONTIGS         => q(<span class="nav_icon fas fa-2x fa-link"></span>);
use constant MORE                 => q(<span class="nav_icon fas fa-2x fa-plus"></span>);
use constant HOME                 => q(<span class="nav_icon fas fa-2x fa-home"></span>);
use constant RELOAD               => q(<span class="nav_icon fas fa-2x fa-sync"></span>);
use constant KEY                  => q(<span class="nav_icon fas fa-2x fa-key"></span>);
use constant EYE_SHOW             => q(<span class="nav_icon fas fa-2x fa-eye"></span>);
use constant EYE_HIDE             => q(<span class="nav_icon fas fa-2x fa-eye-slash"></span>);
use constant CURATE               => q(<span class="nav_icon fas fa-2x fa-user-tie"></span>);
use constant EXPORT_TABLE         => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_button"></span>)
  . q(<span class="fas fa-table fa-stack-1x fa-inverse" style="margin-top:-0.2em"></span>)
  . q(<span class="fas fa-stack-text fa-stack-1x" style="font-size:0.4em;)
  . q(margin-top:1.5em">Table</span></span>);
use constant EXCEL_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_excel"></span>)
  . q(<span class="fas fa-file-excel fa-stack-1x fa-inverse" style="margin-top:-0.2em"></span>)
  . q(<span class="fas fa-stack-text fa-stack-1x" style="font-size:0.4em;)
  . q(margin-top:1.5em">Excel</span></span>);
use constant TEXT_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_text"></span>)
  . q(<span class="fas fa-file-alt fa-stack-1x fa-inverse" style="margin-top:-0.2em"></span>)
  . q(<span class="fas fa-stack-text fa-stack-1x" style="font-size:0.4em;)
  . q(margin-top:1.5em">Text</span></span>);
use constant FASTA_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_fasta"></span>)
  . q(<span class="fas fa-file fa-stack-1x fa-inverse" style="margin-top:-0.2em"></span>)
  . q(<span class="fas fa-dna fa-stack-1x" style="font-size:0.5em;margin-top:-0.2em;color:#848"></span>)
  . q(<span class="fas fa-stack-text fa-stack-1x" style="font-size:0.4em;)
  . q(margin-top:1.5em">FASTA</span></span>);
use constant FASTA_FLANKING_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_fasta"></span>)
  . q(<span class="fas fa-file fa-stack-1x fa-inverse" style="margin-top:-0.2em"></span>)
  . q(<span class="fas fa-dna fa-stack-1x" style="font-size:0.5em;margin-top:-0.2em;color:#848"></span>)
  . q(<span class="fas fa-plus fa-stack-1x" style="font-size:0.4em;padding-left:1.4em;)
  . q(margin-top:-1.3em;color:#fff"></span>)
  . q(<span class="fas fa-stack-text fa-stack-1x" style="font-size:0.4em;)
  . q(margin-top:1.5em">FASTA</span></span>);
use constant EMBL_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_fasta"></span>)
  . q(<span class="fas fa-file fa-stack-1x fa-inverse" style="margin-top:-0.2em"></span>)
  . q(<span class="fas fa-dna fa-stack-1x" style="font-size:0.5em;margin-top:-0.2em;color:#848"></span>)
  . q(<span class="fas fa-stack-text fa-stack-1x" style="font-size:0.4em;)
  . q(margin-top:1.5em">EMBL</span></span>);
use constant GBK_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_fasta"></span>)
  . q(<span class="fas fa-file fa-stack-1x fa-inverse" style="margin-top:-0.2em"></span>)
  . q(<span class="fas fa-dna fa-stack-1x" style="font-size:0.5em;margin-top:-0.2em;color:#848"></span>)
  . q(<span class="fas fa-stack-text fa-stack-1x" style="font-size:0.4em;)
  . q(margin-top:1.5em">GBK</span></span>);
use constant GFF3_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_gff"></span>)
  . q(<span class="fas fa-file-alt fa-stack-1x fa-inverse" style="margin-top:-0.2em"></span>)
  . q(<span class="fas fa-stack-text fa-stack-1x" style="font-size:0.4em;)
  . q(margin-top:1.5em">GFF3</span></span>);
use constant MISC_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_misc"></span>)
  . q(<span class="fas fa-file fa-stack-1x fa-inverse"></span></span>);
use constant ARCHIVE_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_archive"></span>)
  . q(<span class="fas fa-file-archive fa-stack-1x fa-inverse" style="margin-top:-0.2em"></span>)
  . q(<span class="fas fa-stack-text fa-stack-1x" style="font-size:0.4em;)
  . q(margin-top:1.5em">Archive</span></span>);
use constant IMAGE_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_image"></span>)
  . q(<span class="fas fa-file-image fa-stack-1x fa-inverse" style="margin-top:-0.2em"></span>)
  . q(<span class="fas fa-stack-text fa-stack-1x" style="font-size:0.4em;)
  . q(margin-top:1.5em">Image</span></span>);
use constant ALIGN_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_align"></span>)
  . q(<span class="fas fa-file fa-stack-1x fa-inverse" style="margin-top:-0.2em"></span>)
  . q(<span class="fas fa-align-center fa-stack-1x" style="font-size:0.5em;margin-top:-0.2em;color:#64e">)
  . q(</span>)
  . q(<span class="fas fa-stack-text fa-stack-1x" style="font-size:0.4em;)
  . q(margin-top:1.5em">Aligned</span></span>);
use constant CODE_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_code"></span>)
  . q(<span class="fas fa-file-code fa-stack-1x fa-inverse"></span></span>);
use constant PDF_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_pdf"></span>)
  . q(<span class="fas fa-file-pdf fa-stack-1x fa-inverse"></span></span>);
use constant HTML_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_html"></span>)
  . q(<span class="fas fa-file-code fa-stack-1x fa-inverse" style="margin-top:-0.2em"></span>)
  . q(<span class="fas fa-stack-text fa-stack-1x" style="font-size:0.4em;)
  . q(margin-top:1.5em">HTML</span></span>);
use constant SUBMIT_BUTTON => q(<span class="fa-stack fa-2x upload">)
  . q(<span class="fas fa-square fa-stack-2x upload_button"></span>)
  . q(<span class="fas fa-upload fa-stack-1x fa-inverse" style="margin-top:-0.2em"></span>)
  . q(<span class="fas fa-stack-text fa-stack-1x" style="font-size:0.4em;)
  . q(margin-top:1.5em">Submit</span></span>);
use constant FIRST => q(<span class="fa-stack">)
  . q(<span class="far fa-circle fa-stack-2x"></span>)
  . q(<span class="fas fa-angle-double-left fa-stack-1x"></span></span>);
use constant PREVIOUS => q(<span class="fa-stack ">)
  . q(<span class="far fa-circle fa-stack-2x"></span>)
  . q(<span class="fas fa-angle-left fa-stack-1x"></span></span>);
use constant NEXT => q(<span class="fa-stack">)
  . q(<span class="far fa-circle fa-stack-2x"></span>)
  . q(<span class="fas fa-angle-right fa-stack-1x"></span></span>);
use constant LAST => q(<span class="fa-stack">)
  . q(<span class="far fa-circle fa-stack-2x"></span>)
  . q(<span class="fas fa-angle-double-right fa-stack-1x"></span></span>);
use constant TOOLTIP => q(<span class="fa-stack">)
  . q(<span class="far fa-circle fa-stack-2x"></span>)
  . q(<span class="fas fa-info fa-stack-1x"></span></span>);
use constant WARNING_TOOLTIP => q(<span class="fa-stack">)
  . q(<span class="far fa-circle fa-stack-2x"></span>)
  . q(<span class="fas fa-exclamation fa-stack-1x"></span></span>);
use constant FLANKING => qw(0 20 50 100 200 500 1000 2000 5000 10000 25000 50000);
use constant MAX_ROWS => 20;
@values = qw(FACE_STYLE SHOW HIDE SAVE SAVING UP DOWN LEFT RIGHT
  EDIT DELETE ADD COMPARE UPLOAD UPLOAD_CHANGE_CONFIG QUERY USERS PENDING GOOD BAD MEH TRUE FALSE BAN DOWNLOAD
  BACK QUERY_MORE EDIT_MORE UPLOAD_CONTIGS LINK_CONTIGS MORE HOME RELOAD KEY EYE_SHOW EYE_HIDE
  CURATE EXPORT_TABLE EXCEL_FILE TEXT_FILE FASTA_FILE FASTA_FLANKING_FILE PDF_FILE HTML_FILE
  EMBL_FILE GBK_FILE GFF3_FILE MISC_FILE ARCHIVE_FILE IMAGE_FILE ALIGN_FILE CODE_FILE FLANKING
  SUBMIT_BUTTON MAX_ROWS LOCK UNLOCK FIRST PREVIOUS NEXT LAST TOOLTIP WARNING_TOOLTIP);
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
	'alternative start codon',
	'ambiguous read',
	'apparent misassembly',
	'atypical',
	'contains IS element',
	'downstream fusion',
	'frameshift',
	'indel',
	'internal stop codon',
	'introns',
	'no start codon',
	'no stop codon',
	'phase variable: off',
	'truncated',
	'upstream fusion'
);
use constant ALLELE_FLAGS => (
	'alternative start codon',
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
use constant LOCUS_TYPES => (
	'complete CDS',
	'partial CDS',
	'intergenic region',
	'promoter region',
	'pseudogene',
	'complete protein',
	'partial protein'
);
use constant DIPLOID            => qw(A C G T R Y W S M K);
use constant HAPLOID            => qw(A C G T);
use constant IDENTITY_THRESHOLD => 70;
push @EXPORT_OK, qw(SEQ_STATUS SEQ_FLAGS ALLELE_FLAGS LOCUS_TYPES DIPLOID HAPLOID IDENTITY_THRESHOLD);

#Databanks
use constant DATABANKS => qw(ENA Genbank);
push @EXPORT_OK, qw(DATABANKS);

#Permissions
use constant SUBMITTER_ALLOWED_PERMISSIONS => qw(modify_isolates modify_sequences tag_sequences designate_alleles
  only_private disable_access delete_all);
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
use constant WARN_MAX_CONTIGS         => 500;
use constant WARN_MIN_N50             => 20_000;
use constant WARN_MIN_TOTAL_LENGTH    => 1_000_000;
use constant WARN_MAX_TOTAL_LENGTH    => 15_000_000;
use constant MAX_CONTIGS              => 1000;
use constant MIN_N50                  => 10_000;
use constant MIN_TOTAL_LENGTH         => 1_000_000;
use constant MAX_TOTAL_LENGTH         => 15_000_000;
use constant NULL_TERMS               =>
  ( 'none', 'N/A', 'NA', '-', '.', 'not applicable', 'no value', 'unknown', 'unk', 'not known', 'null' );
@values = qw (SUBMISSIONS_DELETED_DAYS COVERAGE READ_LENGTH ASSEMBLY REQUIRES_READ_LENGTH
  REQUIRES_COVERAGE REQUIRED_GENOME_FIELDS DAILY_REST_LIMIT TOTAL_PENDING_LIMIT DAILY_PENDING_LIMIT NULL_TERMS
  WARN_MAX_CONTIGS WARN_MIN_N50 WARN_MIN_TOTAL_LENGTH WARN_MAX_TOTAL_LENGTH MAX_CONTIGS MIN_N50 MIN_TOTAL_LENGTH
  MAX_TOTAL_LENGTH
);
push @EXPORT_OK, @values;
$EXPORT_TAGS{'submissions'} = [@values];

#Schemes
use constant SCHEME_FLAGS        => ( 'experimental', 'in development', 'please cite', 'unpublished' );
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

#ISO 3166-1 country codes
use constant COUNTRIES => {
	q(Afghanistan)                                  => { iso2 => q(AF), iso3 => q(AFG), continent => q(Asia) },
	q(Åland Islands)                                => { iso2 => q(AX), iso3 => q(ALA), continent => q(Europe) },
	q(Albania)                                      => { iso2 => q(AL), iso3 => q(ALB), continent => q(Europe) },
	q(Algeria)                                      => { iso2 => q(DZ), iso3 => q(DZA), continent => q(Africa) },
	q(American Samoa)                               => { iso2 => q(AS), iso3 => q(ASM), continent => q(Oceania) },
	q(Andorra)                                      => { iso2 => q(AD), iso3 => q(AND), continent => q(Europe) },
	q(Angola)                                       => { iso2 => q(AO), iso3 => q(AGO), continent => q(Africa) },
	q(Anguilla)                                     => { iso2 => q(AI), iso3 => q(AIA), continent => q(North America) },
	q(Antarctica)                                   => { iso2 => q(AQ), iso3 => q(ATA), continent => q(Antarctica) },
	q(Antigua and Barbuda)                          => { iso2 => q(AG), iso3 => q(ATG), continent => q(North America) },
	q(Argentina)                                    => { iso2 => q(AR), iso3 => q(ARG), continent => q(South America) },
	q(Armenia)                                      => { iso2 => q(AM), iso3 => q(ARM), continent => q(Asia) },
	q(Aruba)                                        => { iso2 => q(AW), iso3 => q(ABW), continent => q(North America) },
	q(Australia)                                    => { iso2 => q(AU), iso3 => q(AUS), continent => q(Oceania) },
	q(Austria)                                      => { iso2 => q(AT), iso3 => q(AUT), continent => q(Europe) },
	q(Azerbaijan)                                   => { iso2 => q(AZ), iso3 => q(AZE), continent => q(Europe) },
	q(Bahamas)                                      => { iso2 => q(BS), iso3 => q(BHS), continent => q(North America) },
	q(Bahrain)                                      => { iso2 => q(BH), iso3 => q(BHR), continent => q(Asia) },
	q(Bangladesh)                                   => { iso2 => q(BD), iso3 => q(BGD), continent => q(Asia) },
	q(Barbados)                                     => { iso2 => q(BB), iso3 => q(BRB), continent => q(North America) },
	q(Belarus)                                      => { iso2 => q(BY), iso3 => q(BLR), continent => q(Europe) },
	q(Belgium)                                      => { iso2 => q(BE), iso3 => q(BEL), continent => q(Europe) },
	q(Belize)                                       => { iso2 => q(BZ), iso3 => q(BLZ), continent => q(North America) },
	q(Benin)                                        => { iso2 => q(BJ), iso3 => q(BEN), continent => q(Africa) },
	q(Bermuda)                                      => { iso2 => q(BM), iso3 => q(BMU), continent => q(North America) },
	q(Bhutan)                                       => { iso2 => q(BT), iso3 => q(BTN), continent => q(Asia) },
	q(Bolivia)                                      => { iso2 => q(BO), iso3 => q(BOL), continent => q(South America) },
	q(Bonaire, Sint Eustatius and Saba)             => { iso2 => q(BQ), iso3 => q(BES), continent => q(North America) },
	q(Bosnia and Herzegovina)                       => { iso2 => q(BA), iso3 => q(BIH), continent => q(Europe) },
	q(Botswana)                                     => { iso2 => q(BW), iso3 => q(BWA), continent => q(Africa) },
	q(Bouvet Island)                                => { iso2 => q(BV), iso3 => q(BVT), continent => q(Antarctica) },
	q(Brazil)                                       => { iso2 => q(BR), iso3 => q(BRA), continent => q(South America) },
	q(British Indian Ocean Territory)               => { iso2 => q(IO), iso3 => q(IOT), continent => q(Asia) },
	q(British Virgin Islands)                       => { iso2 => q(VG), iso3 => q(VGB), continent => q(North America) },
	q(Brunei)                                       => { iso2 => q(BN), iso3 => q(BRN), continent => q(Asia) },
	q(Bulgaria)                                     => { iso2 => q(BG), iso3 => q(BGR), continent => q(Europe) },
	q(Burkina Faso)                                 => { iso2 => q(BF), iso3 => q(BFA), continent => q(Africa) },
	q(Burundi)                                      => { iso2 => q(BI), iso3 => q(BDI), continent => q(Africa) },
	q(Cambodia)                                     => { iso2 => q(KH), iso3 => q(KHM), continent => q(Asia) },
	q(Cameroon)                                     => { iso2 => q(CM), iso3 => q(CMR), continent => q(Africa) },
	q(Canada)                                       => { iso2 => q(CA), iso3 => q(CAN), continent => q(North America) },
	q(Cape Verde)                                   => { iso2 => q(CV), iso3 => q(CPV), continent => q(Africa) },
	q(Cayman Islands)                               => { iso2 => q(KY), iso3 => q(CYM), continent => q(North America) },
	q(Central African Republic)                     => { iso2 => q(CF), iso3 => q(CAF), continent => q(Africa) },
	q(Chad)                                         => { iso2 => q(TD), iso3 => q(TCD), continent => q(Africa) },
	q(Chile)                                        => { iso2 => q(CL), iso3 => q(CHL), continent => q(South America) },
	q(China)                                        => { iso2 => q(CN), iso3 => q(CHN), continent => q(Asia) },
	q(China [Hong Kong])                            => { iso2 => q(HK), iso3 => q(HKG), continent => q(Asia) },
	q(China [Macao])                                => { iso2 => q(MO), iso3 => q(MAC), continent => q(Asia) },
	q(Christmas Island)                             => { iso2 => q(CX), iso3 => q(CXR), continent => q(Asia) },
	q(Cocos (Keeling) Islands)                      => { iso2 => q(CC), iso3 => q(CCK), continent => q(Asia) },
	q(Colombia)                                     => { iso2 => q(CO), iso3 => q(COL), continent => q(South America) },
	q(Comoros)                                      => { iso2 => q(KM), iso3 => q(COM), continent => q(Africa) },
	q(Congo [DRC])                                  => { iso2 => q(CD), iso3 => q(COD), continent => q(Africa) },
	q(Congo [Republic])                             => { iso2 => q(CG), iso3 => q(COG), continent => q(Africa) },
	q(Cook Islands)                                 => { iso2 => q(CK), iso3 => q(COK), continent => q(Oceania) },
	q(Costa Rica)                                   => { iso2 => q(CR), iso3 => q(CRI), continent => q(North America) },
	q(Croatia)                                      => { iso2 => q(HR), iso3 => q(HRV), continent => q(Europe) },
	q(Cuba)                                         => { iso2 => q(CU), iso3 => q(CUB), continent => q(North America) },
	q(Curaçao)                                      => { iso2 => q(CW), iso3 => q(CUW), continent => q(North America) },
	q(Cyprus)                                       => { iso2 => q(CY), iso3 => q(CYP), continent => q(Europe) },
	q(Czech Republic)                               => { iso2 => q(CZ), iso3 => q(CZE), continent => q(Europe) },
	q(Denmark)                                      => { iso2 => q(DK), iso3 => q(DNK), continent => q(Europe) },
	q(Djibouti)                                     => { iso2 => q(DJ), iso3 => q(DJI), continent => q(Africa) },
	q(Dominica)                                     => { iso2 => q(DM), iso3 => q(DMA), continent => q(North America) },
	q(Dominican Republic)                           => { iso2 => q(DO), iso3 => q(DOM), continent => q(North America) },
	q(East Timor)                                   => { iso2 => q(TL), iso3 => q(TLS), continent => q(Asia) },
	q(Ecuador)                                      => { iso2 => q(EC), iso3 => q(ECU), continent => q(South America) },
	q(Egypt)                                        => { iso2 => q(EG), iso3 => q(EGY), continent => q(Africa) },
	q(El Salvador)                                  => { iso2 => q(SV), iso3 => q(SLV), continent => q(North America) },
	q(Equatorial Guinea)                            => { iso2 => q(GQ), iso3 => q(GNQ), continent => q(Africa) },
	q(Eritrea)                                      => { iso2 => q(ER), iso3 => q(ERI), continent => q(Africa) },
	q(Estonia)                                      => { iso2 => q(EE), iso3 => q(EST), continent => q(Europe) },
	q(Ethiopia)                                     => { iso2 => q(ET), iso3 => q(ETH), continent => q(Africa) },
	q(Falkland Islands (Malvinas))                  => { iso2 => q(FK), iso3 => q(FLK), continent => q(South America) },
	q(Faroe Islands)                                => { iso2 => q(FO), iso3 => q(FRO), continent => q(Europe) },
	q(Fiji)                                         => { iso2 => q(FJ), iso3 => q(FJI), continent => q(Oceania) },
	q(Finland)                                      => { iso2 => q(FI), iso3 => q(FIN), continent => q(Europe) },
	q(France)                                       => { iso2 => q(FR), iso3 => q(FRA), continent => q(Europe) },
	q(French Guiana)                                => { iso2 => q(GF), iso3 => q(GUF), continent => q(South America) },
	q(French Polynesia)                             => { iso2 => q(PF), iso3 => q(PYF), continent => q(Oceania) },
	q(French Southern Territories)                  => { iso2 => q(TF), iso3 => q(ATF), continent => q(Antarctica) },
	q(Gabon)                                        => { iso2 => q(GA), iso3 => q(GAB), continent => q(Africa) },
	q(Georgia)                                      => { iso2 => q(GE), iso3 => q(GEO), continent => q(Europe) },
	q(Germany)                                      => { iso2 => q(DE), iso3 => q(DEU), continent => q(Europe) },
	q(Ghana)                                        => { iso2 => q(GH), iso3 => q(GHA), continent => q(Africa) },
	q(Gibraltar)                                    => { iso2 => q(GI), iso3 => q(GIB), continent => q(Europe) },
	q(Greece)                                       => { iso2 => q(GR), iso3 => q(GRC), continent => q(Europe) },
	q(Greenland)                                    => { iso2 => q(GL), iso3 => q(GRL), continent => q(North America) },
	q(Grenada)                                      => { iso2 => q(GD), iso3 => q(GRD), continent => q(North America) },
	q(Guadeloupe)                                   => { iso2 => q(GP), iso3 => q(GLP), continent => q(North America) },
	q(Guam)                                         => { iso2 => q(GU), iso3 => q(GUM), continent => q(Oceania) },
	q(Guatemala)                                    => { iso2 => q(GT), iso3 => q(GTM), continent => q(North America) },
	q(Guernsey)                                     => { iso2 => q(GG), iso3 => q(GGY), continent => q(Europe) },
	q(Guinea)                                       => { iso2 => q(GN), iso3 => q(GIN), continent => q(Africa) },
	q(Guinea-Bissau)                                => { iso2 => q(GW), iso3 => q(GNB), continent => q(Africa) },
	q(Guyana)                                       => { iso2 => q(GY), iso3 => q(GUY), continent => q(South America) },
	q(Haiti)                                        => { iso2 => q(HT), iso3 => q(HTI), continent => q(North America) },
	q(Heard Island and McDonald Islands)            => { iso2 => q(HM), iso3 => q(HMD), continent => q(Antarctica) },
	q(Holy See)                                     => { iso2 => q(VA), iso3 => q(VAT), continent => q(Europe) },
	q(Honduras)                                     => { iso2 => q(HN), iso3 => q(HND), continent => q(North America) },
	q(Hungary)                                      => { iso2 => q(HU), iso3 => q(HUN), continent => q(Europe) },
	q(Iceland)                                      => { iso2 => q(IS), iso3 => q(ISL), continent => q(Europe) },
	q(India)                                        => { iso2 => q(IN), iso3 => q(IND), continent => q(Asia) },
	q(Indonesia)                                    => { iso2 => q(ID), iso3 => q(IDN), continent => q(Asia) },
	q(Iran)                                         => { iso2 => q(IR), iso3 => q(IRN), continent => q(Asia) },
	q(Iraq)                                         => { iso2 => q(IQ), iso3 => q(IRQ), continent => q(Asia) },
	q(Ireland)                                      => { iso2 => q(IE), iso3 => q(IRL), continent => q(Europe) },
	q(Isle of Man)                                  => { iso2 => q(IM), iso3 => q(IMN), continent => q(Europe) },
	q(Israel)                                       => { iso2 => q(IL), iso3 => q(ISR), continent => q(Asia) },
	q(Italy)                                        => { iso2 => q(IT), iso3 => q(ITA), continent => q(Europe) },
	q(Ivory Coast)                                  => { iso2 => q(CI), iso3 => q(CIV), continent => q(Africa) },
	q(Jamaica)                                      => { iso2 => q(JM), iso3 => q(JAM), continent => q(North America) },
	q(Japan)                                        => { iso2 => q(JP), iso3 => q(JPN), continent => q(Asia) },
	q(Jersey)                                       => { iso2 => q(JE), iso3 => q(JEY), continent => q(Europe) },
	q(Jordan)                                       => { iso2 => q(JO), iso3 => q(JOR), continent => q(Asia) },
	q(Kazakhstan)                                   => { iso2 => q(KZ), iso3 => q(KAZ), continent => q(Asia) },
	q(Kenya)                                        => { iso2 => q(KE), iso3 => q(KEN), continent => q(Africa) },
	q(Kiribati)                                     => { iso2 => q(KI), iso3 => q(KIR), continent => q(Oceania) },
	q(Kuwait)                                       => { iso2 => q(KW), iso3 => q(KWT), continent => q(Asia) },
	q(Kyrgyzstan)                                   => { iso2 => q(KG), iso3 => q(KGZ), continent => q(Asia) },
	q(Laos)                                         => { iso2 => q(LA), iso3 => q(LAO), continent => q(Asia) },
	q(Latvia)                                       => { iso2 => q(LV), iso3 => q(LVA), continent => q(Europe) },
	q(Lebanon)                                      => { iso2 => q(LB), iso3 => q(LBN), continent => q(Asia) },
	q(Lesotho)                                      => { iso2 => q(LS), iso3 => q(LSO), continent => q(Africa) },
	q(Liberia)                                      => { iso2 => q(LR), iso3 => q(LBR), continent => q(Africa) },
	q(Libya)                                        => { iso2 => q(LY), iso3 => q(LBY), continent => q(Africa) },
	q(Liechtenstein)                                => { iso2 => q(LI), iso3 => q(LIE), continent => q(Europe) },
	q(Lithuania)                                    => { iso2 => q(LT), iso3 => q(LTU), continent => q(Europe) },
	q(Luxembourg)                                   => { iso2 => q(LU), iso3 => q(LUX), continent => q(Europe) },
	q(Madagascar)                                   => { iso2 => q(MG), iso3 => q(MDG), continent => q(Africa) },
	q(Malawi)                                       => { iso2 => q(MW), iso3 => q(MWI), continent => q(Africa) },
	q(Malaysia)                                     => { iso2 => q(MY), iso3 => q(MYS), continent => q(Asia) },
	q(Maldives)                                     => { iso2 => q(MV), iso3 => q(MDV), continent => q(Asia) },
	q(Mali)                                         => { iso2 => q(ML), iso3 => q(MLI), continent => q(Africa) },
	q(Malta)                                        => { iso2 => q(MT), iso3 => q(MLT), continent => q(Europe) },
	q(Marshall Islands)                             => { iso2 => q(MH), iso3 => q(MHL), continent => q(Oceania) },
	q(Martinique)                                   => { iso2 => q(MQ), iso3 => q(MTQ), continent => q(North America) },
	q(Mauritania)                                   => { iso2 => q(MR), iso3 => q(MRT), continent => q(Africa) },
	q(Mauritius)                                    => { iso2 => q(MU), iso3 => q(MUS), continent => q(Africa) },
	q(Mayotte)                                      => { iso2 => q(YT), iso3 => q(MYT), continent => q(Africa) },
	q(Mexico)                                       => { iso2 => q(MX), iso3 => q(MEX), continent => q(North America) },
	q(Micronesia)                                   => { iso2 => q(FM), iso3 => q(FSM), continent => q(Oceania) },
	q(Moldova)                                      => { iso2 => q(MD), iso3 => q(MDA), continent => q(Europe) },
	q(Monaco)                                       => { iso2 => q(MC), iso3 => q(MCO), continent => q(Europe) },
	q(Mongolia)                                     => { iso2 => q(MN), iso3 => q(MNG), continent => q(Asia) },
	q(Montenegro)                                   => { iso2 => q(ME), iso3 => q(MNE), continent => q(Europe) },
	q(Montserrat)                                   => { iso2 => q(MS), iso3 => q(MSR), continent => q(North America) },
	q(Morocco)                                      => { iso2 => q(MA), iso3 => q(MAR), continent => q(Africa) },
	q(Mozambique)                                   => { iso2 => q(MZ), iso3 => q(MOZ), continent => q(Africa) },
	q(Myanmar)                                      => { iso2 => q(MM), iso3 => q(MMR), continent => q(Asia) },
	q(Namibia)                                      => { iso2 => q(NA), iso3 => q(NAM), continent => q(Africa) },
	q(Nauru)                                        => { iso2 => q(NR), iso3 => q(NRU), continent => q(Oceania) },
	q(Nepal)                                        => { iso2 => q(NP), iso3 => q(NPL), continent => q(Asia) },
	q(New Caledonia)                                => { iso2 => q(NC), iso3 => q(NCL), continent => q(Oceania) },
	q(New Zealand)                                  => { iso2 => q(NZ), iso3 => q(NZL), continent => q(Oceania) },
	q(Nicaragua)                                    => { iso2 => q(NI), iso3 => q(NIC), continent => q(North America) },
	q(Niger)                                        => { iso2 => q(NE), iso3 => q(NER), continent => q(Africa) },
	q(Nigeria)                                      => { iso2 => q(NG), iso3 => q(NGA), continent => q(Africa) },
	q(Niue)                                         => { iso2 => q(NU), iso3 => q(NIU), continent => q(Oceania) },
	q(Norfolk Island)                               => { iso2 => q(NF), iso3 => q(NFK), continent => q(Oceania) },
	q(North Korea)                                  => { iso2 => q(KP), iso3 => q(PRK), continent => q(Asia) },
	q(North Macedonia)                              => { iso2 => q(MK), iso3 => q(MKD), continent => q(Europe) },
	q(Northern Mariana Islands)                     => { iso2 => q(MP), iso3 => q(MNP), continent => q(Oceania) },
	q(Norway)                                       => { iso2 => q(NO), iso3 => q(NOR), continent => q(Europe) },
	q(Oman)                                         => { iso2 => q(OM), iso3 => q(OMN), continent => q(Asia) },
	q(Pakistan)                                     => { iso2 => q(PK), iso3 => q(PAK), continent => q(Asia) },
	q(Palau)                                        => { iso2 => q(PW), iso3 => q(PLW), continent => q(Oceania) },
	q(Palestinian territories)                      => { iso2 => q(PS), iso3 => q(PSE), continent => q(Asia) },
	q(Panama)                                       => { iso2 => q(PA), iso3 => q(PAN), continent => q(North America) },
	q(Papua New Guinea)                             => { iso2 => q(PG), iso3 => q(PNG), continent => q(Oceania) },
	q(Paraguay)                                     => { iso2 => q(PY), iso3 => q(PRY), continent => q(South America) },
	q(Peru)                                         => { iso2 => q(PE), iso3 => q(PER), continent => q(South America) },
	q(Philippines)                                  => { iso2 => q(PH), iso3 => q(PHL), continent => q(Asia) },
	q(Pitcairn)                                     => { iso2 => q(PN), iso3 => q(PCN), continent => q(Oceania) },
	q(Poland)                                       => { iso2 => q(PL), iso3 => q(POL), continent => q(Europe) },
	q(Portugal)                                     => { iso2 => q(PT), iso3 => q(PRT), continent => q(Europe) },
	q(Puerto Rico)                                  => { iso2 => q(PR), iso3 => q(PRI), continent => q(North America) },
	q(Qatar)                                        => { iso2 => q(QA), iso3 => q(QAT), continent => q(Asia) },
	q(Réunion)                                      => { iso2 => q(RE), iso3 => q(REU), continent => q(Africa) },
	q(Romania)                                      => { iso2 => q(RO), iso3 => q(ROU), continent => q(Europe) },
	q(Russia)                                       => { iso2 => q(RU), iso3 => q(RUS), continent => q(Asia) },
	q(Russia [Asia])                                => { iso2 => q(RU), iso3 => q(RUS), continent => q(Asia) },
	q(Russia [Europe])                              => { iso2 => q(RU), iso3 => q(RUS), continent => q(Europe) },
	q(Rwanda)                                       => { iso2 => q(RW), iso3 => q(RWA), continent => q(Africa) },
	q(Saint Barthélemy)                             => { iso2 => q(BL), iso3 => q(BLM), continent => q(North America) },
	q(Saint Helena)                                 => { iso2 => q(SH), iso3 => q(SHN), continent => q(Africa) },
	q(Saint Kitts and Nevis)                        => { iso2 => q(KN), iso3 => q(KNA), continent => q(North America) },
	q(Saint Lucia)                                  => { iso2 => q(LC), iso3 => q(LCA), continent => q(North America) },
	q(Saint Martin (French Part))                   => { iso2 => q(MF), iso3 => q(MAF), continent => q(North America) },
	q(Saint Pierre and Miquelon)                    => { iso2 => q(PM), iso3 => q(SPM), continent => q(North America) },
	q(Saint Vincent and the Grenadines)             => { iso2 => q(VC), iso3 => q(VCT), continent => q(North America) },
	q(Samoa)                                        => { iso2 => q(WS), iso3 => q(WSM), continent => q(Oceania) },
	q(San Marino)                                   => { iso2 => q(SM), iso3 => q(SMR), continent => q(Europe) },
	q(São Tomé and Príncipe)                        => { iso2 => q(ST), iso3 => q(STP), continent => q(Africa) },
	q(Sark)                                         => { iso2 => q(CQ), iso3 => q(),    continent => q(Europe) },
	q(Saudi Arabia)                                 => { iso2 => q(SA), iso3 => q(SAU), continent => q(Asia) },
	q(Senegal)                                      => { iso2 => q(SN), iso3 => q(SEN), continent => q(Africa) },
	q(Serbia)                                       => { iso2 => q(RS), iso3 => q(SRB), continent => q(Europe) },
	q(Seychelles)                                   => { iso2 => q(SC), iso3 => q(SYC), continent => q(Africa) },
	q(Sierra Leone)                                 => { iso2 => q(SL), iso3 => q(SLE), continent => q(Africa) },
	q(Singapore)                                    => { iso2 => q(SG), iso3 => q(SGP), continent => q(Asia) },
	q(Sint Maarten (Dutch part))                    => { iso2 => q(SX), iso3 => q(SXM), continent => q(North America) },
	q(Slovakia)                                     => { iso2 => q(SK), iso3 => q(SVK), continent => q(Europe) },
	q(Slovenia)                                     => { iso2 => q(SI), iso3 => q(SVN), continent => q(Europe) },
	q(Solomon Islands)                              => { iso2 => q(SB), iso3 => q(SLB), continent => q(Oceania) },
	q(Somalia)                                      => { iso2 => q(SO), iso3 => q(SOM), continent => q(Africa) },
	q(South Africa)                                 => { iso2 => q(ZA), iso3 => q(ZAF), continent => q(Africa) },
	q(South Georgia and the South Sandwich Islands) => { iso2 => q(GS), iso3 => q(SGS), continent => q(Antarctica) },
	q(South Korea)                                  => { iso2 => q(KR), iso3 => q(KOR), continent => q(Asia) },
	q(South Sudan)                                  => { iso2 => q(SS), iso3 => q(SSD), continent => q(Africa) },
	q(Spain)                                        => { iso2 => q(ES), iso3 => q(ESP), continent => q(Europe) },
	q(Sri Lanka)                                    => { iso2 => q(LK), iso3 => q(LKA), continent => q(Asia) },
	q(Sudan)                                        => { iso2 => q(SD), iso3 => q(SDN), continent => q(Africa) },
	q(Suriname)                                     => { iso2 => q(SR), iso3 => q(SUR), continent => q(South America) },
	q(Svalbard and Jan Mayen Islands)               => { iso2 => q(SJ), iso3 => q(SJM), continent => q(Europe) },
	q(Swaziland)                                    => { iso2 => q(SZ), iso3 => q(SWZ), continent => q(Africa) },
	q(Sweden)                                       => { iso2 => q(SE), iso3 => q(SWE), continent => q(Europe) },
	q(Switzerland)                                  => { iso2 => q(CH), iso3 => q(CHE), continent => q(Europe) },
	q(Syria)                                        => { iso2 => q(SY), iso3 => q(SYR), continent => q(Asia) },
	q(Taiwan)                                       => { iso2 => q(TW), iso3 => q(TWN), continent => q(Asia) },
	q(Tajikistan)                                   => { iso2 => q(TJ), iso3 => q(TJK), continent => q(Asia) },
	q(Tanzania)                                     => { iso2 => q(TZ), iso3 => q(TZA), continent => q(Africa) },
	q(Thailand)                                     => { iso2 => q(TH), iso3 => q(THA), continent => q(Asia) },
	q(The Gambia)                                   => { iso2 => q(GM), iso3 => q(GMB), continent => q(Africa) },
	q(The Netherlands)                              => { iso2 => q(NL), iso3 => q(NLD), continent => q(Europe) },
	q(Togo)                                         => { iso2 => q(TG), iso3 => q(TGO), continent => q(Africa) },
	q(Tokelau)                                      => { iso2 => q(TK), iso3 => q(TKL), continent => q(Oceania) },
	q(Tonga)                                        => { iso2 => q(TO), iso3 => q(TON), continent => q(Oceania) },
	q(Trinidad and Tobago)                          => { iso2 => q(TT), iso3 => q(TTO), continent => q(North America) },
	q(Tunisia)                                      => { iso2 => q(TN), iso3 => q(TUN), continent => q(Africa) },
	q(Turkey)                                       => { iso2 => q(TR), iso3 => q(TUR), continent => q(Asia) },
	q(Turkmenistan)                                 => { iso2 => q(TM), iso3 => q(TKM), continent => q(Asia) },
	q(Turks and Caicos Islands)                     => { iso2 => q(TC), iso3 => q(TCA), continent => q(North America) },
	q(Tuvalu)                                       => { iso2 => q(TV), iso3 => q(TUV), continent => q(Oceania) },
	q(Uganda)                                       => { iso2 => q(UG), iso3 => q(UGA), continent => q(Africa) },
	q(UK)                                           => { iso2 => q(GB), iso3 => q(GBR), continent => q(Europe) },
	q(UK [England])                                 => { iso2 => q(GB), iso3 => q(GBR), continent => q(Europe) },
	q(UK [Northern Ireland])                        => { iso2 => q(GB), iso3 => q(GBR), continent => q(Europe) },
	q(UK [Scotland])                                => { iso2 => q(GB), iso3 => q(GBR), continent => q(Europe) },
	q(UK [Wales])                                   => { iso2 => q(GB), iso3 => q(GBR), continent => q(Europe) },
	q(Ukraine)                                      => { iso2 => q(UA), iso3 => q(UKR), continent => q(Europe) },
	q(United Arab Emirates)                         => { iso2 => q(AE), iso3 => q(ARE), continent => q(Asia) },
	q(Uruguay)                                      => { iso2 => q(UY), iso3 => q(URY), continent => q(South America) },
	q(US Minor Outlying Islands)                    => { iso2 => q(UM), iso3 => q(UMI), continent => q(Oceania) },
	q(US Virgin Islands)                            => { iso2 => q(VI), iso3 => q(VIR), continent => q(North America) },
	q(USA)                                          => { iso2 => q(US), iso3 => q(USA), continent => q(North America) },
	q(Uzbekistan)                                   => { iso2 => q(UZ), iso3 => q(UZB), continent => q(Asia) },
	q(Vanuatu)                                      => { iso2 => q(VU), iso3 => q(VUT), continent => q(Oceania) },
	q(Venezuela)                                    => { iso2 => q(VE), iso3 => q(VEN), continent => q(South America) },
	q(Vietnam)                                      => { iso2 => q(VN), iso3 => q(VNM), continent => q(Asia) },
	q(Wallis and Futuna Islands)                    => { iso2 => q(WF), iso3 => q(WLF), continent => q(Oceania) },
	q(Western Sahara)                               => { iso2 => q(EH), iso3 => q(ESH), continent => q(Africa) },
	q(Yemen)                                        => { iso2 => q(YE), iso3 => q(YEM), continent => q(Asia) },
	q(Zambia)                                       => { iso2 => q(ZM), iso3 => q(ZMB), continent => q(Africa) },
	q(Zimbabwe)                                     => { iso2 => q(ZW), iso3 => q(ZWE), continent => q(Africa) },
};
push @EXPORT_OK, qw (COUNTRIES);

#Log4Perl logging to screen
use constant LOG_TO_SCREEN => qq(log4perl.category.BIGSdb.Script        = INFO, Screen\n)
  . qq(log4perl.category.BIGSdb.Dataconnector = WARN, Screen\n)
  . qq(log4perl.category.BIGSdb.Datastore     = WARN, Screen\n)
  . qq(log4perl.appender.Screen               = Log::Log4perl::Appender::Screen\n)
  . qq(log4perl.appender.Screen.stderr        = 1\n)
  . qq(log4perl.appender.Screen.layout        = Log::Log4perl::Layout::SimpleLayout\n)
  . qq(log4perl.appender.Screen.utf8          = 1\n);
push @EXPORT_OK, qw (LOG_TO_SCREEN);

#Dashboards
use constant DEFAULT_FRONTEND_DASHBOARD => [
	{
		display           => 'record_count',
		name              => 'Isolate count',
		width             => 2,
		background_colour => '#9bb5d0',
		main_text_colour  => '#404040',
		watermark         => 'fas fa-bacteria',
		change_duration   => 'month',
		url_text          => 'Browse isolates'
	},
	{
		display           => 'record_count',
		name              => 'Genome count',
		genomes           => 1,
		width             => 2,
		background_colour => '#99ca92',
		main_text_colour  => '#404040',
		watermark         => 'fas fa-dna',
		change_duration   => 'month',
		url_text          => 'Browse genomes',
		post_data         => { genomes => 1 }
	},
	{
		display           => 'field',
		name              => 'Country',
		field             => 'f_country',
		breakdown_display => 'map',
		width             => 3,
		height            => 2,
		hide_mobile       => 1
	},
	{
		display           => 'field',
		name              => 'Continent',
		field             => 'e_country||continent',
		breakdown_display => 'top',
		top_values        => 5,
		width             => 2
	},
	{
		name        => 'Sequence size',
		display     => 'seqbin_size',
		genomes     => 1,
		hide_mobile => 1,
		width       => 2,
		height      => 1
	},
	{
		display           => 'field',
		name              => 'Species',
		field             => 'f_species',
		breakdown_display => 'doughnut',
		height            => 2,
		width             => 2
	},
	{
		display           => 'field',
		name              => 'Year',
		field             => 'f_year',
		breakdown_display => 'bar',
		width             => 3,
		bar_colour_type   => 'continuous',
		chart_colour      => '#126716'
	},
	{
		display           => 'field',
		name              => 'Date entered',
		field             => 'f_date_entered',
		width             => 2,
		breakdown_display => 'cumulative'
	}
];
use constant DEFAULT_QUERY_DASHBOARD => [
	{
		display           => 'record_count',
		name              => 'Isolate count',
		width             => 1,
		background_colour => '#79cafb',
		main_text_colour  => '#404040',
		watermark         => 'fas fa-bacteria',
		change_duration   => 'month'
	},
	{
		display           => 'record_count',
		name              => 'Genome count',
		genomes           => 1,
		width             => 1,
		background_colour => '#7ecc66',
		main_text_colour  => '#404040',
		watermark         => 'fas fa-dna',
		change_duration   => 'month'
	},
	{
		display           => 'field',
		name              => 'Continent',
		field             => 'e_country||continent',
		breakdown_display => 'map',
		palette           => 'purple/blue/green',
		width             => 2,
		height            => 1,
		hide_mobile       => 1
	},
	{
		display           => 'field',
		name              => 'Species',
		field             => 'f_species',
		breakdown_display => 'treemap',
		height            => 1,
		width             => 1,
		hide_mobile       => 1
	},
	{
		display           => 'field',
		name              => 'Disease',
		field             => 'f_disease',
		breakdown_display => 'treemap',
		height            => 1,
		width             => 1,
		hide_mobile       => 1
	},
	{
		display           => 'field',
		name              => 'Source',
		field             => 'f_source',
		breakdown_display => 'treemap',
		height            => 1,
		width             => 1,
		hide_mobile       => 1
	},
	{
		display           => 'field',
		name              => 'Year',
		field             => 'f_year',
		breakdown_display => 'bar',
		width             => 2,
		bar_colour_type   => 'continuous',
		chart_colour      => '#126716',
		hide_mobile       => 1
	}
];
use constant RECORD_AGE => {
	0 => 'all time',
	1 => 'past 5 years',
	2 => 'past 4 years',
	3 => 'past 3 years',
	4 => 'past 2 years',
	5 => 'past year',
	6 => 'past month',
	7 => 'past week'
};
push @EXPORT_OK, qw (DEFAULT_FRONTEND_DASHBOARD DEFAULT_QUERY_DASHBOARD RECORD_AGE);
$EXPORT_TAGS{'dashboard'} = [qw (DEFAULT_FRONTEND_DASHBOARD DEFAULT_QUERY_DASHBOARD RECORD_AGE)];
1;
