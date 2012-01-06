#Export.pm - Export plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
package BIGSdb::Plugins::Export;
use strict;
use warnings;
use base qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use Apache2::Connection ();
use Bio::Tools::SeqStats;

sub get_attributes {
	my %att = (
		name        => 'Export',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Export dataset generated from query results',
		category    => 'Export',
		buttontext  => 'Dataset',
		menutext    => 'Export dataset',
		module      => 'Export',
		version     => '1.1.0',
		dbtype      => 'isolates',
		section     => 'export,postquery',
		url         => 'http://pubmlst.org/software/database/bigsdb/userguide/isolates/export_isolates.shtml',
		input       => 'query',
		requires    => 'refdb,js_tree',
		help        => 'tooltips',
		order       => 15
	);
	return \%att;
}

sub get_option_list {
	my ($self) = @_;
	my @list = (
		{ name => 'alleles', description => 'Export allele numbers',                 default => 1 },
		{ name => 'molwt',   description => 'Export protein molecular weights',      default => 0 },
		{ name => 'met',     description => 'GTG/TTG at start codes for methionine', default => 1 },
		{ name => 'oneline', description => 'Use one row per field',                 default => 0 },
		{
			name        => 'labelfield',
			description => "Include $self->{'system'}->{'labelfield'} field in row (used only with 'one row' option)",
			default     => 0
		},
		{ name => 'info', description => "Export full allele designation record (used only with 'one row' option)", default => 0 }
	);
	return \@list;
}

sub run {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	print "<h1>Export dataset</h1>\n";
	if ( $q->param('submit') ) {
		my $selected_fields = $self->get_selected_fields;
		if ( !@$selected_fields ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No fields have been selected!</p></div>\n";
		} else {
			my $filename   = BIGSdb::Utils::get_random() . '.txt';
			my $query_file = $q->param('query_file');
			my $qry_ref    = $self->get_query($query_file);
			return if ref $qry_ref ne 'SCALAR';
			my $view = $self->{'system'}->{'view'};
			print "<div class=\"box\" id=\"resultstable\">";
			print "<p>Please wait for processing to finish (do not refresh page).</p>\n";
			print "<p>Output file being generated ...";
			my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
			return if !$self->create_temp_tables($qry_ref);
			my $fields = $self->{'xmlHandler'}->get_field_list;
			local $" = ",$view.";
			my $field_string = "$view.@$fields";
			$$qry_ref =~ s/SELECT ($view\.\*|\*)/SELECT $field_string/;
			$self->rewrite_query_ref_order_by($qry_ref);
			$self->_write_tab_text( $qry_ref, $selected_fields, $full_path );
			print " done</p>";
			print "<p><a href=\"/tmp/$filename\">Output file</a> (right-click to save)</p>\n";
			print "</div>\n";
			return;
		}
	}
	print <<"HTML";
<div class="box" id="queryform">
<p>This script will export the dataset in tab-delimited text, suitable for importing into a spreadsheet.
You can choose which fields you would like included - please uncheck any that are not required.</p>
HTML
	foreach (qw (shtml html)) {
		my $policy = "$ENV{'DOCUMENT_ROOT'}$self->{'system'}->{'webroot'}/policy.$_";
		if ( -e $policy ) {
			print
"<p>Use of exported data is subject to the terms of the <a href='$self->{'system'}->{'webroot'}/policy.$_'>policy document</a>!</p>";
			last;
		}
	}
	$self->print_field_export_form( 1, [], { 'include_composites' => 1, 'extended_attributes' => 1 } );
	print "</div>\n";
	return;
}

sub _write_tab_text {
	my ( $self, $qry_ref, $fields, $filename ) = @_;
	my $guid = $self->get_guid;
	my %prefs;
	my %default_prefs = ( alleles => 1, molwt => 0, met => 1, oneline => 0, labelfield => 0, info => 0 );
	foreach (qw (alleles molwt met oneline labelfield info)) {
		try {
			$prefs{$_} = $self->{'prefstore'}->get_plugin_attribute( $guid, $self->{'system'}->{'db'}, 'Export', $_ );
			$prefs{$_} = $prefs{$_} eq 'true' ? 1 : 0;
		}
		catch BIGSdb::DatabaseNoRecordException with {
			$prefs{$_} = $default_prefs{$_};
		};
	}
	open( my $fh, '>', $filename )
	  or $logger->error("Can't open temp file $filename for writing");
	if ( $prefs{'oneline'} ) {
		print $fh "id\t";
		print $fh $self->{'system'}->{'labelfield'} . "\t" if $prefs{'labelfield'};
		print $fh "Field\tValue";
		print $fh "\tCurator\tDatestamp\tComments" if $prefs{'info'};
	} else {
		my $first = 1;
		my %schemes;
		foreach (@$fields) {
			my $field = $_;
			if ( $field =~ /^s_(\d+)_f/ ) {
				my $scheme_info = $self->{'datastore'}->get_scheme_info($1);
				$field .= " ($scheme_info->{'description'})"
				  if $scheme_info->{'description'};
				$schemes{$1} = 1;
			}
			my $is_locus = $field =~ /^(s_\d+_l_|l_)/ ? 1 : 0;
			$field =~ s/^(s_\d+_l|s_\d+_f|f|l|c)_//g;    #strip off prefix for header row
			$field =~ s/___/../;
			if ($is_locus) {
				if ( $prefs{'alleles'} ) {
					print $fh "\t" if !$first;
					print $fh $field;
					$first = 0;
				}
				if ( $prefs{'molwt'} ) {
					print $fh "\t" if !$first;
					print $fh "$field Mwt";
					$first = 0;
				}
			} else {
				print $fh "\t" if !$first;
				print $fh $field;
				$first = 0;
			}
		}
		my $scheme_field_pos;
		foreach my $scheme_id ( keys %schemes ) {
			my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
			my $i             = 0;
			foreach (@$scheme_fields) {
				$scheme_field_pos->{$scheme_id}->{$_} = $i;
				$i++;
			}
		}
		if ($first) {
			print $fh "Make sure you select an option for locus export (see options in the top-right corner).\n";
			return;
		}
	}
	print $fh "\n";
	my $sql = $self->{'db'}->prepare($$qry_ref);
	eval { $sql->execute };
	$logger->error($@) if $@;
	my %data           = ();
	my $fields_to_bind = $self->{'xmlHandler'}->get_field_list;
	$sql->bind_columns( map { \$data{$_} } @$fields_to_bind );    #quicker binding hash to arrayref than to use hashref
	my $i         = 0;
	my $j         = 0;
	my $alias_sql = $self->{'db'}->prepare("SELECT alias FROM isolate_aliases WHERE isolate_id=? ORDER BY alias");
	my $attribute_sql =
	  $self->{'db'}->prepare("SELECT value FROM isolate_value_extended_attributes WHERE isolate_field=? AND attribute=? AND field_value=?");
	my $allele_sql = $self->{'db'}->prepare("SELECT allele_designations.datestamp AS des_datestamp,first_name,surname FROM allele_designations LEFT JOIN users ON allele_designations.curator = users.id WHERE isolate_id=? AND locus=?");
	local $| = 1;

	while ( $sql->fetchrow_arrayref ) {
		print "." if !$i;
		print " " if !$j;
		if ( !$i && $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
		my $first      = 1;
		my $allele_ids = $self->{'datastore'}->get_all_allele_ids( $data{'id'} );
		my $scheme_field_values;

		foreach (@$fields) {
			if ( $prefs{'oneline'} ) {
				print $fh "$data{'id'}\t";
				print $fh "$data{$self->{'system'}->{'labelfield'}}\t" if $prefs{'labelfield'};				
			}
			if ( $_ =~ /^f_(.*)/ ) {
				my $field = $1;
				if ( $field eq 'aliases' ) {
					eval { $alias_sql->execute( $data{'id'} ) };
					$logger->error($@) if $@;
					my @aliases;
					while ( my ($alias) = $alias_sql->fetchrow_array ) {
						push @aliases, $alias;
					}
					local $" = '; ';
					if ( $prefs{'oneline'} ) {
						print $fh "aliases\t@aliases\n";
					} else {
						print $fh "\t" if !$first;
						print $fh "@aliases";
					}
				} elsif ( $field =~ /(.*)___(.*)/ ) {
					my ( $isolate_field, $attribute ) = ( $1, $2 );
					eval { $attribute_sql->execute( $isolate_field, $attribute, $data{$isolate_field} ) };
					$logger->error($@) if $@;
					my ($value) = $attribute_sql->fetchrow_array;
					if ( $prefs{'oneline'} ) {
						print $fh "$isolate_field..$attribute\t";
						print $fh $value if defined $value;
						print $fh "\n";
					} else {
						print $fh "\t"   if !$first;
						print $fh $value if defined $value;
					}
				} else {
					if ( $prefs{'oneline'} ) {
						print $fh "$field\t";
						print $fh "$data{$field}" if defined $data{$field};
						print $fh "\n";
					} else {
						print $fh "\t" if !$first;
						print $fh $data{$field} if defined $data{$field};
					}
				}
			} elsif ( $_ =~ /^(s_\d+_l_|l_)(.*)/ ) {
				my $locus = $2;
				if ( $prefs{'alleles'} ) {
					if ( $prefs{'oneline'} ) {
						print $fh "$locus\t";
						print $fh $allele_ids->{$locus} if defined $allele_ids->{$locus};
						if ($prefs{'info'}){
							eval { $allele_sql->execute($data{'id'},$locus)};
							$logger->error($@) if $@;
							my $allele_info = $allele_sql->fetchrow_hashref;
							if (defined $allele_info){
								print $fh "\t$allele_info->{'first_name'} $allele_info->{'surname'}\t";
								print $fh "$allele_info->{'des_datestamp'}\t";
								print $fh $allele_info->{'comments'} if defined $allele_info->{'comments'};
							}
						}
						print $fh "\n";						
					} else {
						print $fh "\t" if !$first;
						print $fh $allele_ids->{$locus} if defined $allele_ids->{$locus};
					}
				}
				if ( $prefs{'molwt'} ) {
					if ( $prefs{'oneline'} ) {
						if ($prefs{'alleles'}){
							print $fh "$data{'id'}\t";
							print $fh "$data{$self->{'system'}->{'labelfield'}}\t" if $prefs{'labelfield'};			
						}
						print $fh "$locus MolWt\t";
						print $fh $self->_get_molwt( $locus, $allele_ids->{$locus}, $prefs{'met'} );
						print $fh "\n";
					} else {
						print $fh "\t" if !$first;
						print $fh $self->_get_molwt( $locus, $allele_ids->{$locus}, $prefs{'met'} );
					}
				}
			} elsif ( $_ =~ /^s_(\d+)_f_(.*)/ ) {
				my $scheme_id    = $1;
				my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
				my $display_scheme_field = $2;
				my $scheme_field = lc($display_scheme_field);
				if ( ref $scheme_field_values->{$1} ne 'HASH' ) {
					$scheme_field_values->{$scheme_id} =
					  $self->{'datastore'}->get_scheme_field_values_by_isolate_id( $data{'id'}, $scheme_id );
				}
				my $value = $scheme_field_values->{$scheme_id}->{$scheme_field};
				undef $value
				  if defined $value && $value eq '-999';    #old null code from mlstdbNet databases
				if ( $prefs{'oneline'} ) {
					print $fh "$display_scheme_field ($scheme_info->{'description'})\t";
					print $fh $value if defined $value;
					print $fh "\n";
				} else {
					print $fh "\t"   if !$first;
					print $fh $value if defined $value;
				}
			} elsif ( $_ =~ /^c_(.*)/ ) {
				my $composite_field = $1;
				my $value = $self->{'datastore'}->get_composite_value( $data{'id'}, $composite_field, \%data );
				if ( $prefs{'oneline'} ) {
					print $fh "$composite_field\t";
					print $fh $value if defined $value;
					print $fh "\n";
				} else {
					print $fh "\t" if !$first;
					print $fh $value;
				}
			}
			$first = 0;
		}
		print $fh "\n" if !$prefs{'oneline'};
		$i++;
		if ( $i == 50 ) {
			$i = 0;
			$j++;
		}
		$j = 0 if $j == 10;
	}
	close $fh;
	return;
}

sub _get_molwt {
	my ( $self, $locus_name, $allele, $met ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus_name);
	my $peptide;
	my $locus = $self->{'datastore'}->get_locus($locus_name);
	if ( $locus_info->{'data_type'} eq 'DNA' ) {
		my $seq_ref;
		try {
			$seq_ref = $locus->get_allele_sequence($allele);
		}
		catch BIGSdb::DatabaseConnectionException with {

			#do nothing
		};
		my $seq = BIGSdb::Utils::chop_seq( $$seq_ref, $locus_info->{'orf'} || 1 );
		if ($met) {
			$seq =~ s/^(TTG|GTG)/ATG/;
		}
		$peptide = Bio::Perl::translate_as_string($seq) if $seq;
	} else {
		$peptide = ${ $locus->get_allele_sequence($allele) };
	}
	return if !$peptide;
	my $seqobj    = Bio::PrimarySeq->new( -seq => $peptide, -id => $allele, -alphabet => 'protein', );
	my $seq_stats = Bio::Tools::SeqStats->new($seqobj);
	my $weight    = $seq_stats->get_mol_wt;
	return $weight->[0];
}
1;
