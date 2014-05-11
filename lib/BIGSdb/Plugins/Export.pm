#Export.pm - Export plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2014, University of Oxford
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
use 5.010;
use parent qw(BIGSdb::Plugin);
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
		version     => '1.2.0',
		dbtype      => 'isolates',
		section     => 'export,postquery',
		url         => 'http://pubmlst.org/software/database/bigsdb/userguide/isolates/export_isolates.shtml',
		input       => 'query',
		requires    => 'ref_db,js_tree',
		help        => 'tooltips',
		order       => 15
	);
	return \%att;
}

sub get_plugin_javascript {
	my $js = << "END";
function enable_controls(){
	if (\$("#m_references").prop("checked")){
		\$("input:radio[name='ref_type']").prop("disabled", false);
	} else {
		\$("input:radio[name='ref_type']").prop("disabled", true);
	}
}

\$(document).ready(function() 
    { 
		enable_controls();
    } 
); 
END
	return $js;
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

sub get_extra_fields {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say "<fieldset style=\"float:left\"><legend>References</legend><ul><li>";
	print $q->checkbox(
		-name     => 'm_references',
		-id       => 'm_references',
		-value    => 'checked',
		-label    => 'references',
		-onChange => 'enable_controls()'
	);
	say "</li><li>";
	print $q->radio_group( -name => 'ref_type', -values => [ 'PubMed id', 'Full citation' ], -default => 'PubMed id',
		-linebreak => 'true' );
	say "</li></ul></fieldset>";
	return;
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say "<h1>Export dataset</h1>";
	if ( $q->param('submit') ) {
		my $selected_fields = $self->get_selected_fields;
		push @$selected_fields, "m_references" if $q->param('m_references');
		if ( !@$selected_fields ) {
			say "<div class=\"box\" id=\"statusbad\"><p>No fields have been selected!</p></div>";
		} else {
			my $prefix     = BIGSdb::Utils::get_random();
			my $filename   = "$prefix.txt";
			my $query_file = $q->param('query_file');
			my $qry_ref    = $self->get_query($query_file);
			return if ref $qry_ref ne 'SCALAR';
			my $view = $self->{'system'}->{'view'};
			say "<div class=\"box\" id=\"resultstable\">";
			say "<p>Please wait for processing to finish (do not refresh page).</p>";
			print "<p>Output files being generated ...";
			my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
			return if !$self->create_temp_tables($qry_ref);
			my $fields = $self->{'xmlHandler'}->get_field_list;
			local $" = ",$view.";
			my $field_string = "$view.@$fields";
			$$qry_ref =~ s/SELECT ($view\.\*|\*)/SELECT $field_string/;
			$self->rewrite_query_ref_order_by($qry_ref);
			$self->_write_tab_text( $qry_ref, $selected_fields, $full_path );
			say " done</p>";
			say "<p>Download: <a href=\"/tmp/$filename\">Text file</a>";
			my $excel = BIGSdb::Utils::text2excel( $full_path, { worksheet => "Export" } );
			say qq( | <a href="/tmp/$prefix.xlsx">Excel file</a>) if -e $excel;
			say " (right-click to save)</p>";
			say "</div>";
			return;
		}
	}
	print <<"HTML";
<div class="box" id="queryform">
<p>This script will export the dataset in tab-delimited text, suitable for importing into a spreadsheet.
Select which fields you would like included.  Select loci either from the locus list or by selecting one or
more schemes to include all loci (and/or fields) from a scheme.</p>
HTML
	foreach (qw (shtml html)) {
		my $policy = "$ENV{'DOCUMENT_ROOT'}$self->{'system'}->{'webroot'}/policy.$_";
		if ( -e $policy ) {
			say "<p>Use of exported data is subject to the terms of the <a href='$self->{'system'}->{'webroot'}/policy.$_'>"
			  . "policy document</a>!</p>";
			last;
		}
	}
	$self->print_field_export_form( 1, { include_composites => 1, extended_attributes => 1 } );
	print "</div>\n";
	return;
}

sub _write_tab_text {
	my ( $self, $qry_ref, $fields, $filename ) = @_;
	my $guid = $self->get_guid;
	my %prefs;
	my %default_prefs = ( alleles => 1, molwt => 0, met => 1, oneline => 0, labelfield => 0, info => 0 );
	my $set_id = $self->get_set_id;
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
			my $field = $_;    #don't modify @$fields
			if ( $field =~ /^s_(\d+)_f/ ) {
				my $scheme_info = $self->{'datastore'}->get_scheme_info( $1, { set_id => $set_id } );
				$field .= " ($scheme_info->{'description'})"
				  if $scheme_info->{'description'};
				$schemes{$1} = 1;
			}
			my $is_locus = $field =~ /^(s_\d+_l_|l_)/ ? 1 : 0;
			$field =~ s/^(s_\d+_l|s_\d+_f|f|l|c|m)_//g;    #strip off prefix for header row
			my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
			$field =~ s/^.*___//;
			if ($is_locus) {
				$field = $self->clean_locus( $field, { text_output => 1 } );
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
				print $fh $metafield // $field;
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
			say $fh "Make sure you select an option for locus export (see options in the top-right corner).";
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
	my $i = 0;
	my $j = 0;
	local $| = 1;
	my %id_used;

	while ( $sql->fetchrow_arrayref ) {
		next if $id_used{ $data{'id'} }; #Ordering by scheme field/locus can result in multiple rows per isolate if multiple values defined.
		$id_used{ $data{'id'} } = 1;
		print "." if !$i;
		print " " if !$j;
		if ( !$i && $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
		my $first      = 1;
		my $allele_ids = $self->{'datastore'}->get_all_allele_ids( $data{'id'} );
		foreach (@$fields) {
			if ( $_ =~ /^f_(.*)/ ) {
				$self->_write_field( $fh, $1, \%data, $first, \%prefs );
			} elsif ( $_ =~ /^(s_\d+_l_|l_)(.*)/ ) {
				$self->_write_allele(
					{ fh => $fh, locus => $2, data => \%data, allele_ids => $allele_ids, first => $first, prefs => \%prefs } );
			} elsif ( $_ =~ /^s_(\d+)_f_(.*)/ ) {
				$self->_write_scheme_field(
					{ fh => $fh, scheme_id => $1, field => $2, data => \%data, first => $first, prefs => \%prefs } );
			} elsif ( $_ =~ /^c_(.*)/ ) {
				$self->_write_composite( $fh, $1, \%data, $first, \%prefs );
			} elsif ( $_ =~ /^m_references/ ) {
				$self->_write_ref( $fh, \%data, $first, \%prefs );
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

sub _get_id_one_line {
	my ( $self, $data, $prefs, ) = @_;
	my $buffer = "$data->{'id'}\t";
	$buffer .= "$data->{$self->{'system'}->{'labelfield'}}\t" if $prefs->{'labelfield'};
	return $buffer;
}

sub _write_field {
	my ( $self, $fh, $field, $data, $first, $prefs ) = @_;
	my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
	if ( defined $metaset ) {
		my $value = $self->{'datastore'}->get_metadata_value( $data->{'id'}, $metaset, $metafield );
		if ( $prefs->{'oneline'} ) {
			print $fh $self->_get_id_one_line( $data, $prefs );
			print $fh "$metafield\t";
			print $fh $value;
			print $fh "\n";
		} else {
			print $fh "\t" if !$first;
			print $fh $value;
		}
	} elsif ( $field eq 'aliases' ) {
		if ( !$self->{'sql'}->{'alias'} ) {
			$self->{'sql'}->{'alias'} = $self->{'db'}->prepare("SELECT alias FROM isolate_aliases WHERE isolate_id=? ORDER BY alias");
		}
		eval { $self->{'sql'}->{'alias'}->execute( $data->{'id'} ) };
		$logger->error($@) if $@;
		my @aliases;
		while ( my ($alias) = $self->{'sql'}->{'alias'}->fetchrow_array ) {
			push @aliases, $alias;
		}
		local $" = '; ';
		if ( $prefs->{'oneline'} ) {
			print $fh $self->_get_id_one_line( $data, $prefs );
			print $fh "aliases\t@aliases\n";
		} else {
			print $fh "\t" if !$first;
			print $fh "@aliases";
		}
	} elsif ( $field =~ /(.*)___(.*)/ ) {
		my ( $isolate_field, $attribute ) = ( $1, $2 );
		if ( !$self->{'sql'}->{'attribute'} ) {
			$self->{'sql'}->{'attribute'} =
			  $self->{'db'}
			  ->prepare("SELECT value FROM isolate_value_extended_attributes WHERE isolate_field=? AND attribute=? AND field_value=?");
		}
		eval { $self->{'sql'}->{'attribute'}->execute( $isolate_field, $attribute, $data->{$isolate_field} ) };
		$logger->error($@) if $@;
		my ($value) = $self->{'sql'}->{'attribute'}->fetchrow_array;
		if ( $prefs->{'oneline'} ) {
			print $fh $self->_get_id_one_line( $data, $prefs );
			print $fh "$attribute\t";
			print $fh $value if defined $value;
			print $fh "\n";
		} else {
			print $fh "\t"   if !$first;
			print $fh $value if defined $value;
		}
	} else {
		if ( $prefs->{'oneline'} ) {
			print $fh $self->_get_id_one_line( $data, $prefs );
			print $fh "$field\t";
			print $fh "$data->{$field}" if defined $data->{$field};
			print $fh "\n";
		} else {
			print $fh "\t" if !$first;
			print $fh $data->{$field} if defined $data->{$field};
		}
	}
	return;
}

sub _write_allele {
	my ( $self, $args ) = @_;
	my ( $fh, $locus, $data, $allele_ids, $first_col, $prefs ) = @{$args}{qw(fh locus data allele_ids first prefs)};
	my @allele_ids = defined $allele_ids->{$locus} ? @{ $allele_ids->{$locus} } : ('');
	if ( $prefs->{'alleles'} ) {
		my $first_allele = 1;
		foreach my $allele_id (@allele_ids) {
			if ( $prefs->{'oneline'} ) {
				print $fh $self->_get_id_one_line( $data, $prefs );
				print $fh "$locus\t";
				print $fh $allele_id;
				if ( $prefs->{'info'} ) {
					if ( !$self->{'sql'}->{'allele'} ) {
						$self->{'sql'}->{'allele'} =
						  $self->{'db'}->prepare( "SELECT allele_designations.datestamp AS des_datestamp,first_name,surname,comments FROM "
							  . "allele_designations LEFT JOIN users ON allele_designations.curator = users.id WHERE isolate_id=? AND locus=?"
						  );
					}
					eval { $self->{'sql'}->{'allele'}->execute( $data->{'id'}, $locus ) };
					$logger->error($@) if $@;
					my $allele_info = $self->{'sql'}->{'allele'}->fetchrow_hashref;
					if ( defined $allele_info ) {
						print $fh "\t$allele_info->{'first_name'} $allele_info->{'surname'}\t";
						print $fh "$allele_info->{'des_datestamp'}\t";
						print $fh $allele_info->{'comments'} if defined $allele_info->{'comments'};
					}
				}
				print $fh "\n";
			} else {
				if ( !$first_allele ) {
					print $fh ';';
				} elsif ( !$first_col ) {
					print $fh "\t";
				}
				print $fh "$allele_id";
			}
			$first_allele = 0;
		}
	}
	if ( $prefs->{'molwt'} ) {
		my $first_allele = 1;
		foreach my $allele_id (@allele_ids) {
			if ( $prefs->{'oneline'} ) {
				print $fh $self->_get_id_one_line( $data, $prefs );
				print $fh "$locus MolWt\t";
				print $fh $self->_get_molwt( $locus, $allele_id, $prefs->{'met'} );
				print $fh "\n";
			} else {
				if ( !$first_allele ) {
					print $fh ',';
				} elsif ( !$first_col ) {
					print $fh "\t";
				}
				print $fh $self->_get_molwt( $locus, $allele_id, $prefs->{'met'} );
			}
			$first_allele = 0;
		}
	}
	return;
}

sub _write_scheme_field {
	my ( $self, $args ) = @_;
	my ( $fh, $scheme_id, $field, $data, $first_col, $prefs ) = @{$args}{qw(fh scheme_id field data first prefs)};
	my $scheme_info  = $self->{'datastore'}->get_scheme_info($scheme_id);
	my $scheme_field = lc($field);
	my $values       = $self->get_scheme_field_values( { isolate_id => $data->{'id'}, scheme_id => $scheme_id, field => $field } );
	@$values = ('') if !@$values;
	my $first_allele = 1;
	foreach my $value (@$values) {

		if ( $prefs->{'oneline'} ) {
			print $fh $self->_get_id_one_line( $data, $prefs );
			print $fh "$field ($scheme_info->{'description'})\t";
			print $fh $value if defined $value;
			print $fh "\n";
		} else {
			if ( !$first_allele ) {
				print $fh ';';
			} elsif ( !$first_col ) {
				print $fh "\t";
			}
			print $fh $value if defined $value;
		}
		$first_allele = 0;
	}
	return;
}

sub _write_composite {
	my ( $self, $fh, $composite_field, $data, $first, $prefs ) = @_;
	my $value = $self->{'datastore'}->get_composite_value( $data->{'id'}, $composite_field, $data, { no_format => 1 } );
	if ( $prefs->{'oneline'} ) {
		print $fh $self->_get_id_one_line( $data, $prefs );
		print $fh "$composite_field\t";
		print $fh $value if defined $value;
		print $fh "\n";
	} else {
		print $fh "\t"   if !$first;
		print $fh $value if defined $value;
	}
	return;
}

sub _write_ref {
	my ( $self, $fh, $data, $first, $prefs ) = @_;
	my $values = $self->_get_refs( $data->{'id'} );
	if ( ( $self->{'cgi'}->param('ref_type') // '' ) eq 'Full citation' ) {
		my $citation_hash = $self->{'datastore'}->get_citation_hash($values);
		my @citations;
		push @citations, $citation_hash->{$_} foreach @$values;
		$values = \@citations;
	}
	if ( $prefs->{'oneline'} ) {
		foreach my $value (@$values) {
			print $fh $self->_get_id_one_line( $data, $prefs );
			print $fh "references\t";
			print $fh "$value";
			print $fh "\n";
		}
	} else {
		print $fh "\t" if !$first;
		local $" = ';';
		print $fh "@$values";
	}
	return;
}

sub _get_refs {
	my ( $self, $isolate_id ) = @_;
	if ( !$self->{'sql'}->{'get_refs'} ) {
		$self->{'sql'}->{'get_refs'} = $self->{'db'}->prepare("SELECT pubmed_id FROM refs WHERE isolate_id=? ORDER BY pubmed_id");
	}
	eval { $self->{'sql'}->{'get_refs'}->execute($isolate_id) };
	$logger->error($@) if $@;
	my @refs;
	while ( my ($ref) = $self->{'sql'}->{'get_refs'}->fetchrow_array ) {
		push @refs, $ref;
	}
	return \@refs;
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
