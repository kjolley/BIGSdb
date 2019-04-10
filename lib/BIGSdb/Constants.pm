#Written by Keith Jolley
#Copyright (c) 2015-2019, University of Oxford
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
use utf8;
our @EXPORT_OK;
our %EXPORT_TAGS;
use constant DEFAULT_DOMAIN => 'pubmlst.org';
push @EXPORT_OK, qw(DEFAULT_DOMAIN);

#Limits
use constant MAX_SPLITS_TAXA           => 150;
use constant MAX_MUSCLE_MB             => 4 * 1024;    #4GB
use constant MAX_ISOLATES_DROPDOWN     => 1000;
use constant MAX_EAV_FIELD_LIST        => 100;
use constant MAX_LOCUS_ORDER_BY        => 2000;
use constant MAX_LOCI_NON_CACHE_SCHEME => 30;
my @values = qw(MAX_SPLITS_TAXA MAX_MUSCLE_MB MAX_ISOLATES_DROPDOWN MAX_EAV_FIELD_LIST
  MAX_LOCUS_ORDER_BY MAX_LOCI_NON_CACHE_SCHEME);
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
use constant EXPORT_TABLE   => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_button"></span>)
  . q(<span class="fas fa-table fa-stack-1x fa-inverse"></span></span>);
use constant EXCEL_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_excel"></span>)
  . q(<span class="fas fa-file-excel fa-stack-1x fa-inverse"></span></span>);
use constant TEXT_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_text"></span>)
  . q(<span class="fas fa-file-alt fa-stack-1x fa-inverse"></span></span>);
use constant FASTA_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_fasta"></span>)
  . q(<span class="fas fa-file fa-stack-1x fa-inverse"></span>)
  . q(<span class="fas fa-dna fa-stack-1x" style="font-size:0.5em;padding-top:0.2em;color:#848"></span></span>);
use constant FASTA_FLANKING_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_fasta"></span>)
  . q(<span class="fas fa-file fa-stack-1x fa-inverse"></span>)
  . q(<span class="fas fa-dna fa-stack-1x" style="font-size:0.5em;padding-top:0.2em;color:#848"></span>)
  . q(<span class="fas fa-plus fa-stack-1x" style="font-size:0.6em;padding-left:0.9em;)
  . q(margin-top:-0.8em;color:#fff"></span></span>);
use constant MISC_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_misc"></span>)
  . q(<span class="fas fa-file fa-stack-1x fa-inverse"></span></span>);
use constant ARCHIVE_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_archive"></span>)
  . q(<span class="fas fa-file-archive fa-stack-1x fa-inverse"></span></span>);
use constant IMAGE_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_image"></span>)
  . q(<span class="fas fa-file-image fa-stack-1x fa-inverse"></span></span>);
use constant ALIGN_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_align"></span>)
  . q(<span class="fas fa-file fa-stack-1x fa-inverse"></span>)
  . q(<span class="fas fa-align-center fa-stack-1x" style="font-size:0.5em;padding-top:0.2em;color:#64e">)
  . q(</span></span>);
use constant CODE_FILE => q(<span class="fa-stack fa-2x export">)
  . q(<span class="fas fa-square fa-stack-2x export_code"></span>)
  . q(<span class="fas fa-file-code fa-stack-1x fa-inverse"></span></span>);
use constant FLANKING => qw(0 20 50 100 200 500 1000 2000 5000 10000 25000 50000);
use constant MAX_ROWS => 20;
@values = qw(BUTTON_CLASS RESET_BUTTON_CLASS FACE_STYLE SHOW HIDE SAVE SAVING UP DOWN LEFT RIGHT
  EDIT DELETE ADD COMPARE UPLOAD QUERY USERS GOOD BAD TRUE FALSE BAN DOWNLOAD BACK QUERY_MORE EDIT_MORE
  UPLOAD_CONTIGS LINK_CONTIGS MORE HOME RELOAD KEY EYE_SHOW EYE_HIDE EXPORT_TABLE EXCEL_FILE TEXT_FILE
  FASTA_FILE FASTA_FLANKING_FILE MISC_FILE ARCHIVE_FILE IMAGE_FILE ALIGN_FILE CODE_FILE FLANKING MAX_ROWS);
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

#ISO 3166-1 country codes
use constant COUNTRIES => {
	q(Afghanistan)                                  => { iso3 => q(AFG), continent => q(Asia) },
	q(Åland Islands)                               => { iso3 => q(ALA), continent => q(Europe) },
	q(Albania)                                      => { iso3 => q(ALB), continent => q(Europe) },
	q(Algeria)                                      => { iso3 => q(DZA), continent => q(Africa) },
	q(American Samoa)                               => { iso3 => q(ASM), continent => q(Oceania) },
	q(Andorra)                                      => { iso3 => q(AND), continent => q(Europe) },
	q(Angola)                                       => { iso3 => q(AGO), continent => q(Africa) },
	q(Anguilla)                                     => { iso3 => q(AIA), continent => q(North America) },
	q(Antarctica)                                   => { iso3 => q(ATA), continent => q(Antarctica) },
	q(Antigua and Barbuda)                          => { iso3 => q(ATG), continent => q(North America) },
	q(Argentina)                                    => { iso3 => q(ARG), continent => q(South America) },
	q(Armenia)                                      => { iso3 => q(ARM), continent => q(Asia) },
	q(Aruba)                                        => { iso3 => q(ABW), continent => q(North America) },
	q(Australia)                                    => { iso3 => q(AUS), continent => q(Oceania) },
	q(Austria)                                      => { iso3 => q(AUT), continent => q(Europe) },
	q(Azerbaijan)                                   => { iso3 => q(AZE), continent => q(Europe) },
	q(Bahamas)                                      => { iso3 => q(BHS), continent => q(North America) },
	q(Bahrain)                                      => { iso3 => q(BHR), continent => q(Asia) },
	q(Bangladesh)                                   => { iso3 => q(BGD), continent => q(Asia) },
	q(Barbados)                                     => { iso3 => q(BRB), continent => q(North America) },
	q(Belarus)                                      => { iso3 => q(BLR), continent => q(Europe) },
	q(Belgium)                                      => { iso3 => q(BEL), continent => q(Europe) },
	q(Belize)                                       => { iso3 => q(BLZ), continent => q(North America) },
	q(Benin)                                        => { iso3 => q(BEN), continent => q(Africa) },
	q(Bermuda)                                      => { iso3 => q(BMU), continent => q(North America) },
	q(Bhutan)                                       => { iso3 => q(BTN), continent => q(Asia) },
	q(Bolivia)                                      => { iso3 => q(BOL), continent => q(South America) },
	q(Bonaire, Sint Eustatius and Saba)             => { iso3 => q(BES), continent => q(North America) },
	q(Bosnia and Herzegovina)                       => { iso3 => q(BIH), continent => q(Europe) },
	q(Botswana)                                     => { iso3 => q(BWA), continent => q(Africa) },
	q(Bouvet Island)                                => { iso3 => q(BVT), continent => q(Antarctica) },
	q(Brazil)                                       => { iso3 => q(BRA), continent => q(South America) },
	q(British Indian Ocean Territory)               => { iso3 => q(IOT), continent => q(Asia) },
	q(British Virgin Islands)                       => { iso3 => q(VGB), continent => q(North America) },
	q(Brunei)                                       => { iso3 => q(BRN), continent => q(Asia) },
	q(Bulgaria)                                     => { iso3 => q(BGR), continent => q(Europe) },
	q(Burkina Faso)                                 => { iso3 => q(BFA), continent => q(Africa) },
	q(Burundi)                                      => { iso3 => q(BDI), continent => q(Africa) },
	q(Cambodia)                                     => { iso3 => q(KHM), continent => q(Asia) },
	q(Cameroon)                                     => { iso3 => q(CMR), continent => q(Africa) },
	q(Canada)                                       => { iso3 => q(CAN), continent => q(North America) },
	q(Cape Verde)                                   => { iso3 => q(CPV), continent => q(Africa) },
	q(Cayman Islands)                               => { iso3 => q(CYM), continent => q(North America) },
	q(Central African Republic)                     => { iso3 => q(CAF), continent => q(Africa) },
	q(Chad)                                         => { iso3 => q(TCD), continent => q(Africa) },
	q(Chile)                                        => { iso3 => q(CHL), continent => q(South America) },
	q(China)                                        => { iso3 => q(CHN), continent => q(Asia) },
	q(China [Hong Kong])                            => { iso3 => q(HKG), continent => q(Asia) },
	q(China [Macao])                                => { iso3 => q(MAC), continent => q(Asia) },
	q(Christmas Island)                             => { iso3 => q(CXR), continent => q(Asia) },
	q(Cocos (Keeling) Islands)                      => { iso3 => q(CCK), continent => q(Asia) },
	q(Colombia)                                     => { iso3 => q(COL), continent => q(South America) },
	q(Comoros)                                      => { iso3 => q(COM), continent => q(Africa) },
	q(Congo [DRC])                                  => { iso3 => q(COD), continent => q(Africa) },
	q(Congo [Republic])                             => { iso3 => q(COG), continent => q(Africa) },
	q(Cook Islands)                                 => { iso3 => q(COK), continent => q(Oceania) },
	q(Costa Rica)                                   => { iso3 => q(CRI), continent => q(North America) },
	q(Côte d'Ivoire)                             => { iso3 => q(CIV), continent => q(Africa) },
	q(Croatia)                                      => { iso3 => q(HRV), continent => q(Europe) },
	q(Cuba)                                         => { iso3 => q(CUB), continent => q(North America) },
	q(Curaçao)                                     => { iso3 => q(CUW), continent => q(North America) },
	q(Cyprus)                                       => { iso3 => q(CYP), continent => q(Europe) },
	q(Czech Republic)                               => { iso3 => q(CZE), continent => q(Europe) },
	q(Denmark)                                      => { iso3 => q(DNK), continent => q(Europe) },
	q(Djibouti)                                     => { iso3 => q(DJI), continent => q(Africa) },
	q(Dominica)                                     => { iso3 => q(DMA), continent => q(North America) },
	q(Dominican Republic)                           => { iso3 => q(DOM), continent => q(North America) },
	q(East Timor)                                   => { iso3 => q(TLS), continent => q(Asia) },
	q(Ecuador)                                      => { iso3 => q(ECU), continent => q(South America) },
	q(Egypt)                                        => { iso3 => q(EGY), continent => q(Africa) },
	q(El Salvador)                                  => { iso3 => q(SLV), continent => q(North America) },
	q(Equatorial Guinea)                            => { iso3 => q(GNQ), continent => q(Africa) },
	q(Eritrea)                                      => { iso3 => q(ERI), continent => q(Africa) },
	q(Estonia)                                      => { iso3 => q(EST), continent => q(Europe) },
	q(Ethiopia)                                     => { iso3 => q(ETH), continent => q(Africa) },
	q(Falkland Islands (Malvinas))                  => { iso3 => q(FLK), continent => q(South America) },
	q(Faroe Islands)                                => { iso3 => q(FRO), continent => q(Europe) },
	q(Fiji)                                         => { iso3 => q(FJI), continent => q(Oceania) },
	q(Finland)                                      => { iso3 => q(FIN), continent => q(Europe) },
	q(France)                                       => { iso3 => q(FRA), continent => q(Europe) },
	q(French Guiana)                                => { iso3 => q(GUF), continent => q(South America) },
	q(French Polynesia)                             => { iso3 => q(PYF), continent => q(Oceania) },
	q(French Southern Territories)                  => { iso3 => q(ATF), continent => q(Antarctica) },
	q(Gabon)                                        => { iso3 => q(GAB), continent => q(Africa) },
	q(Georgia)                                      => { iso3 => q(GEO), continent => q(Europe) },
	q(Germany)                                      => { iso3 => q(DEU), continent => q(Europe) },
	q(Ghana)                                        => { iso3 => q(GHA), continent => q(Africa) },
	q(Gibraltar)                                    => { iso3 => q(GIB), continent => q(Europe) },
	q(Greece)                                       => { iso3 => q(GRC), continent => q(Europe) },
	q(Greenland)                                    => { iso3 => q(GRL), continent => q(North America) },
	q(Grenada)                                      => { iso3 => q(GRD), continent => q(North America) },
	q(Guadeloupe)                                   => { iso3 => q(GLP), continent => q(North America) },
	q(Guam)                                         => { iso3 => q(GUM), continent => q(Oceania) },
	q(Guatemala)                                    => { iso3 => q(GTM), continent => q(North America) },
	q(Guernsey)                                     => { iso3 => q(GGY), continent => q(Europe) },
	q(Guinea)                                       => { iso3 => q(GIN), continent => q(Africa) },
	q(Guinea-Bissau)                                => { iso3 => q(GNB), continent => q(Africa) },
	q(Guyana)                                       => { iso3 => q(GUY), continent => q(South America) },
	q(Haiti)                                        => { iso3 => q(HTI), continent => q(North America) },
	q(Heard Island and McDonald Islands)            => { iso3 => q(HMD), continent => q(Antarctica) },
	q(Holy See)                                     => { iso3 => q(VAT), continent => q(Europe) },
	q(Honduras)                                     => { iso3 => q(HND), continent => q(North America) },
	q(Hungary)                                      => { iso3 => q(HUN), continent => q(Europe) },
	q(Iceland)                                      => { iso3 => q(ISL), continent => q(Europe) },
	q(India)                                        => { iso3 => q(IND), continent => q(Asia) },
	q(Indonesia)                                    => { iso3 => q(IDN), continent => q(Asia) },
	q(Iran)                                         => { iso3 => q(IRN), continent => q(Asia) },
	q(Iraq)                                         => { iso3 => q(IRQ), continent => q(Asia) },
	q(Ireland)                                      => { iso3 => q(IRL), continent => q(Europe) },
	q(Isle of Man)                                  => { iso3 => q(IMN), continent => q(Europe) },
	q(Israel)                                       => { iso3 => q(ISR), continent => q(Asia) },
	q(Italy)                                        => { iso3 => q(ITA), continent => q(Europe) },
	q(Jamaica)                                      => { iso3 => q(JAM), continent => q(North America) },
	q(Japan)                                        => { iso3 => q(JPN), continent => q(Asia) },
	q(Jersey)                                       => { iso3 => q(JEY), continent => q(Europe) },
	q(Jordan)                                       => { iso3 => q(JOR), continent => q(Asia) },
	q(Kazakhstan)                                   => { iso3 => q(KAZ), continent => q(Asia) },
	q(Kenya)                                        => { iso3 => q(KEN), continent => q(Africa) },
	q(Kiribati)                                     => { iso3 => q(KIR), continent => q(Oceania) },
	q(Kuwait)                                       => { iso3 => q(KWT), continent => q(Asia) },
	q(Kyrgyzstan)                                   => { iso3 => q(KGZ), continent => q(Asia) },
	q(Laos)                                         => { iso3 => q(LAO), continent => q(Asia) },
	q(Latvia)                                       => { iso3 => q(LVA), continent => q(Europe) },
	q(Lebanon)                                      => { iso3 => q(LBN), continent => q(Asia) },
	q(Lesotho)                                      => { iso3 => q(LSO), continent => q(Africa) },
	q(Liberia)                                      => { iso3 => q(LBR), continent => q(Africa) },
	q(Libya)                                        => { iso3 => q(LBY), continent => q(Africa) },
	q(Liechtenstein)                                => { iso3 => q(LIE), continent => q(Europe) },
	q(Lithuania)                                    => { iso3 => q(LTU), continent => q(Europe) },
	q(Luxembourg)                                   => { iso3 => q(LUX), continent => q(Europe) },
	q(Madagascar)                                   => { iso3 => q(MDG), continent => q(Africa) },
	q(Malawi)                                       => { iso3 => q(MWI), continent => q(Africa) },
	q(Malaysia)                                     => { iso3 => q(MYS), continent => q(Asia) },
	q(Maldives)                                     => { iso3 => q(MDV), continent => q(Asia) },
	q(Mali)                                         => { iso3 => q(MLI), continent => q(Africa) },
	q(Malta)                                        => { iso3 => q(MLT), continent => q(Europe) },
	q(Marshall Islands)                             => { iso3 => q(MHL), continent => q(Oceania) },
	q(Martinique)                                   => { iso3 => q(MTQ), continent => q(North America) },
	q(Mauritania)                                   => { iso3 => q(MRT), continent => q(Africa) },
	q(Mauritius)                                    => { iso3 => q(MUS), continent => q(Africa) },
	q(Mayotte)                                      => { iso3 => q(MYT), continent => q(Africa) },
	q(Mexico)                                       => { iso3 => q(MEX), continent => q(North America) },
	q(Micronesia)                                   => { iso3 => q(FSM), continent => q(Oceania) },
	q(Moldova)                                      => { iso3 => q(MDA), continent => q(Europe) },
	q(Monaco)                                       => { iso3 => q(MCO), continent => q(Europe) },
	q(Mongolia)                                     => { iso3 => q(MNG), continent => q(Asia) },
	q(Montenegro)                                   => { iso3 => q(MNE), continent => q(Europe) },
	q(Montserrat)                                   => { iso3 => q(MSR), continent => q(North America) },
	q(Morocco)                                      => { iso3 => q(MAR), continent => q(Africa) },
	q(Mozambique)                                   => { iso3 => q(MOZ), continent => q(Africa) },
	q(Myanmar)                                      => { iso3 => q(MMR), continent => q(Asia) },
	q(Namibia)                                      => { iso3 => q(NAM), continent => q(Africa) },
	q(Nauru)                                        => { iso3 => q(NRU), continent => q(Oceania) },
	q(Nepal)                                        => { iso3 => q(NPL), continent => q(Asia) },
	q(New Caledonia)                                => { iso3 => q(NCL), continent => q(Oceania) },
	q(New Zealand)                                  => { iso3 => q(NZL), continent => q(Oceania) },
	q(Nicaragua)                                    => { iso3 => q(NIC), continent => q(North America) },
	q(Niger)                                        => { iso3 => q(NER), continent => q(Africa) },
	q(Nigeria)                                      => { iso3 => q(NGA), continent => q(Africa) },
	q(Niue)                                         => { iso3 => q(NIU), continent => q(Oceania) },
	q(Norfolk Island)                               => { iso3 => q(NFK), continent => q(Oceania) },
	q(North Korea)                                  => { iso3 => q(PRK), continent => q(Asia) },
	q(North Macedonia)                              => { iso3 => q(MKD), continent => q(Europe) },
	q(Northern Mariana Islands)                     => { iso3 => q(MNP), continent => q(Oceania) },
	q(Norway)                                       => { iso3 => q(NOR), continent => q(Europe) },
	q(Oman)                                         => { iso3 => q(OMN), continent => q(Asia) },
	q(Pakistan)                                     => { iso3 => q(PAK), continent => q(Asia) },
	q(Palau)                                        => { iso3 => q(PLW), continent => q(Oceania) },
	q(Palestinian territories)                      => { iso3 => q(PSE), continent => q(Asia) },
	q(Panama)                                       => { iso3 => q(PAN), continent => q(North America) },
	q(Papua New Guinea)                             => { iso3 => q(PNG), continent => q(Oceania) },
	q(Paraguay)                                     => { iso3 => q(PRY), continent => q(South America) },
	q(Peru)                                         => { iso3 => q(PER), continent => q(South America) },
	q(Philippines)                                  => { iso3 => q(PHL), continent => q(Asia) },
	q(Pitcairn)                                     => { iso3 => q(PCN), continent => q(Oceania) },
	q(Poland)                                       => { iso3 => q(POL), continent => q(Europe) },
	q(Portugal)                                     => { iso3 => q(PRT), continent => q(Europe) },
	q(Puerto Rico)                                  => { iso3 => q(PRI), continent => q(North America) },
	q(Qatar)                                        => { iso3 => q(QAT), continent => q(Asia) },
	q(Réunion)                                     => { iso3 => q(REU), continent => q(Africa) },
	q(Romania)                                      => { iso3 => q(ROU), continent => q(Europe) },
	q(Russia)                                       => { iso3 => q(RUS), continent => q(Asia) },
	q(Rwanda)                                       => { iso3 => q(RWA), continent => q(Africa) },
	q(Saint Barthélemy)                            => { iso3 => q(BLM), continent => q(North America) },
	q(Saint Helena)                                 => { iso3 => q(SHN), continent => q(Africa) },
	q(Saint Kitts and Nevis)                        => { iso3 => q(KNA), continent => q(North America) },
	q(Saint Lucia)                                  => { iso3 => q(LCA), continent => q(North America) },
	q(Saint Martin (French Part))                   => { iso3 => q(MAF), continent => q(North America) },
	q(Saint Pierre and Miquelon)                    => { iso3 => q(SPM), continent => q(North America) },
	q(Saint Vincent and the Grenadines)             => { iso3 => q(VCT), continent => q(North America) },
	q(Samoa)                                        => { iso3 => q(WSM), continent => q(Oceania) },
	q(San Marino)                                   => { iso3 => q(SMR), continent => q(Europe) },
	q(Sao Tome and Principe)                        => { iso3 => q(STP), continent => q(Africa) },
	q(Sark)                                         => { iso3 => q(),    continent => q(Europe) },
	q(Saudi Arabia)                                 => { iso3 => q(SAU), continent => q(Asia) },
	q(Senegal)                                      => { iso3 => q(SEN), continent => q(Africa) },
	q(Serbia)                                       => { iso3 => q(SRB), continent => q(Europe) },
	q(Seychelles)                                   => { iso3 => q(SYC), continent => q(Africa) },
	q(Sierra Leone)                                 => { iso3 => q(SLE), continent => q(Africa) },
	q(Singapore)                                    => { iso3 => q(SGP), continent => q(Asia) },
	q(Sint Maarten (Dutch part))                    => { iso3 => q(SXM), continent => q(North America) },
	q(Slovakia)                                     => { iso3 => q(SVK), continent => q(Europe) },
	q(Slovenia)                                     => { iso3 => q(SVN), continent => q(Europe) },
	q(Solomon Islands)                              => { iso3 => q(SLB), continent => q(Oceania) },
	q(Somalia)                                      => { iso3 => q(SOM), continent => q(Africa) },
	q(South Africa)                                 => { iso3 => q(ZAF), continent => q(Africa) },
	q(South Georgia and the South Sandwich Islands) => { iso3 => q(SGS), continent => q(Antarctica) },
	q(South Korea)                                  => { iso3 => q(KOR), continent => q(Asia) },
	q(South Sudan)                                  => { iso3 => q(SSD), continent => q(Africa) },
	q(Spain)                                        => { iso3 => q(ESP), continent => q(Europe) },
	q(Sri Lanka)                                    => { iso3 => q(LKA), continent => q(Asia) },
	q(Sudan)                                        => { iso3 => q(SDN), continent => q(Africa) },
	q(Suriname)                                     => { iso3 => q(SUR), continent => q(South America) },
	q(Svalbard and Jan Mayen Islands)               => { iso3 => q(SJM), continent => q(Europe) },
	q(Swaziland)                                    => { iso3 => q(SWZ), continent => q(Africa) },
	q(Sweden)                                       => { iso3 => q(SWE), continent => q(Europe) },
	q(Switzerland)                                  => { iso3 => q(CHE), continent => q(Europe) },
	q(Syria)                                        => { iso3 => q(SYR), continent => q(Asia) },
	q(Taiwan)                                       => { iso3 => q(TWN), continent => q(Asia) },
	q(Tajikistan)                                   => { iso3 => q(TJK), continent => q(Asia) },
	q(Tanzania)                                     => { iso3 => q(TZA), continent => q(Africa) },
	q(Thailand)                                     => { iso3 => q(THA), continent => q(Asia) },
	q(The Gambia)                                   => { iso3 => q(GMB), continent => q(Africa) },
	q(The Netherlands)                              => { iso3 => q(NLD), continent => q(Europe) },
	q(Togo)                                         => { iso3 => q(TGO), continent => q(Africa) },
	q(Tokelau)                   => { iso3 => q(TKL), continent => q(Oceania) },
	q(Tonga)                     => { iso3 => q(TON), continent => q(Oceania) },
	q(Trinidad and Tobago)       => { iso3 => q(TTO), continent => q(North America) },
	q(Tunisia)                   => { iso3 => q(TUN), continent => q(Africa) },
	q(Turkey)                    => { iso3 => q(TUR), continent => q(Asia) },
	q(Turkmenistan)              => { iso3 => q(TKM), continent => q(Asia) },
	q(Turks and Caicos Islands)  => { iso3 => q(TCA), continent => q(North America) },
	q(Tuvalu)                    => { iso3 => q(TUV), continent => q(Oceania) },
	q(Uganda)                    => { iso3 => q(UGA), continent => q(Africa) },
	q(UK)                        => { iso3 => q(GBR), continent => q(Europe) },
	q(Ukraine)                   => { iso3 => q(UKR), continent => q(Europe) },
	q(United Arab Emirates)      => { iso3 => q(ARE), continent => q(Asia) },
	q(Uruguay)                   => { iso3 => q(URY), continent => q(South America) },
	q(US Minor Outlying Islands) => { iso3 => q(UMI), continent => q(Oceania) },
	q(US Virgin Islands)         => { iso3 => q(VIR), continent => q(North America) },
	q(USA)                       => { iso3 => q(USA), continent => q(North America) },
	q(Uzbekistan)                => { iso3 => q(UZB), continent => q(Asia) },
	q(Vanuatu)                   => { iso3 => q(VUT), continent => q(Oceania) },
	q(Venezuela)                 => { iso3 => q(VEN), continent => q(South America) },
	q(Vietnam)                   => { iso3 => q(VNM), continent => q(Asia) },
	q(Wallis and Futuna Islands) => { iso3 => q(WLF), continent => q(Oceania) },
	q(Western Sahara)            => { iso3 => q(ESH), continent => q(Africa) },
	q(Yemen)                     => { iso3 => q(YEM), continent => q(Asia) },
	q(Zambia)                    => { iso3 => q(ZMB), continent => q(Africa) },
	q(Zimbabwe)                  => { iso3 => q(ZWE), continent => q(Africa) },
};
push @EXPORT_OK, qw (COUNTRIES);
1;
