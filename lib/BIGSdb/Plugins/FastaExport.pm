#FastaExport.pm - Plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2012-2019, University of Oxford
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
package BIGSdb::Plugins::FastaExport;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use BIGSdb::Constants qw(:interface DATABANKS);
use JSON;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant DIVIDER => q( );

sub get_attributes {
	my %att = (
		name             => 'FASTA Export',
		author           => 'Keith Jolley',
		affiliation      => 'University of Oxford, UK',
		email            => 'keith.jolley@zoo.ox.ac.uk',
		description      => 'Export FASTA file of sequences following an allele attribute query',
		menu_description => 'FASTA format',
		category         => 'Export',
		menutext         => 'Locus sequences',
		buttontext       => 'FASTA',
		module           => 'FastaExport',
		version          => '2.0.0',
		dbtype           => 'sequences',
		seqdb_type       => 'sequences',
		input            => 'query',
		section          => 'export,postquery',
		order            => 10
	);
	return \%att;
}

sub _create_fasta_file {
	my ( $self, $locus, $allele_id_string ) = @_;
	my $q               = $self->{'cgi'};
	my @list            = split /\r?\n/x, $allele_id_string;
	my $temp            = BIGSdb::Utils::get_random();
	my $filename        = "$temp.fas";
	my $full_path       = "$self->{'config'}->{'tmp_dir'}/$filename";
	my %extended_select = map { $_ => 1 } $q->multi_param('extended');
	my $extended_fields =
	  $self->{'datastore'}->run_query( 'SELECT field FROM locus_extended_attributes WHERE locus=? ORDER BY field_order',
		$locus, { fetch => 'col_arrayref' } );
	my $invalid = [];
	open( my $fh, '>:encoding(utf8)', $full_path ) or $logger->error("Cannot open $full_path for writing.");

	foreach my $allele_id (@list) {
		$allele_id =~ s/^\s+|\s+$//gx;
		next if !length($allele_id);
		my $seq_data = $self->{'datastore'}->run_query(
			'SELECT allele_id,sequence FROM sequences WHERE (locus,allele_id)=(?,?)',
			[ $locus, $allele_id ],
			{ fetch => 'row_hashref', cache => 'FastaExport::run' }
		);
		if ( !defined $seq_data->{'allele_id'} ) {
			push @$invalid, $allele_id;
			next;
		}
		my $header = qq(>${locus}_$seq_data->{'allele_id'});
		my %selected = map { $_ => 1 } $q->multi_param('extended');
		foreach my $field (@$extended_fields) {
			next if !$selected{$field};
			my $value = $self->{'datastore'}->run_query(
				'SELECT value FROM sequence_extended_attributes WHERE (locus,allele_id,field)=(?,?,?)',
				[ $locus, $seq_data->{'allele_id'}, $field ],
				{ cache => 'FastaExport::extended_value' }
			);
			if ( defined $value ) {
				$header .= DIVIDER . qq($field:$value);
			}
		}
		foreach my $databank (DATABANKS) {
			next if !$selected{$databank};
			my $values = $self->{'datastore'}->run_query(
				'SELECT databank_id FROM accession WHERE (locus,allele_id,databank)=(?,?,?)',
				[ $locus, $seq_data->{'allele_id'}, $databank ],
				{ fetch => 'col_arrayref', cache => 'FastaExport::databank_accession' }
			);
			if (@$values) {
				local $" = q(,);
				$header .= DIVIDER . qq($databank:@$values);
			}
		}
		if ( $selected{'PubMed'} ) {
			my $values = $self->{'datastore'}->run_query(
				'SELECT pubmed_id FROM sequence_refs WHERE (locus,allele_id)=(?,?)',
				[ $locus, $seq_data->{'allele_id'} ],
				{ fetch => 'col_arrayref', cache => 'FastaExport::pubmed' }
			);
			if (@$values) {
				local $" = q(,);
				$header .= DIVIDER . qq(PubMed:@$values);
			}
		}
		if ( ( $self->{'system'}->{'allele_flags'} // q() ) eq 'yes' ) {
			my $values = $self->{'datastore'}->run_query(
				'SELECT flag FROM allele_flags WHERE (locus,allele_id)=(?,?)',
				[ $locus, $seq_data->{'allele_id'} ],
				{ fetch => 'col_arrayref', cache => 'FastaExport::flags' }
			);
			if (@$values) {
				local $" = q(,);
				$header .= DIVIDER . qq(Flags:@$values);
			}
		}
		say $fh $header;
		my $seq = BIGSdb::Utils::break_line( $seq_data->{'sequence'}, 60 );
		say $fh $seq;
	}
	close $fh;
	if ( !-e $full_path ) {
		$self->print_bad_status( { message => q(Sequence file could not be generated.) } );
		$logger->error('Sequence file cannot be generated');
	}
	return ( $filename, $invalid );
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $locus = $q->param('locus') // q();
	if ( $q->param('get_extended') && $locus ) {
		$self->_get_extended($locus);
		return;
	}
	if ( $q->param('defined') && $locus ) {
		$self->_get_defined_alleles($locus);
		return;
	}
	say q(<h1>Export sequences in FASTA file</h1>);
	$locus =~ s/^cn_//x;
	my $filename;
	my $invalid = [];
	if ( $q->param('submit') ) {
		my @errors;
		if ( !$locus ) {
			push @errors, 'No locus selected.';
		} elsif ( !$self->{'datastore'}->is_locus($locus) ) {
			push @errors, 'Invalid locus selected.';
		}
		if ( !$q->param('allele_ids') ) {
			push @errors, 'No sequences ids selected.';
		}
		if (@errors) {
			local $" = q(<br />);
			$self->print_bad_status( { message => q(Invalid selection), detail => qq(@errors) } );
		} else {
			local $| = 1;
			say q(<div class="hideonload"><p>Please wait - calculating (do not refresh) ...</p>)
			  . q(<p><span class="wait_icon fas fa-sync-alt fa-spin fa-4x"></span></p></div>);
			$self->{'mod_perl_request'}->rflush if $ENV{'MOD_PERL'};
			( $filename, $invalid ) = $self->_create_fasta_file( $locus, scalar $q->param('allele_ids') );
			if (@$invalid) {
				local $" = q(, );
				$self->print_bad_status(
					{
						message => q(Invalid ids in selection),
						detail  => BIGSdb::Utils::escape_html(
							qq(The following sequence ids do not exist and have been removed: @$invalid.)
						)
					}
				);
			}
		}
	}
	$self->_print_interface($locus);
	$self->_print_output($filename);
	return;
}

sub _print_interface {
	my ( $self, $locus ) = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $list_file  = $q->param('list_file');
	my $allele_ids = $self->get_allele_id_list( $query_file, $list_file );
	my $set_id     = $self->get_set_id;
	say q(<div class="box" id="queryform"><div class="scrollable">);
	my ( $display_loci, $labels ) = $self->{'datastore'}->get_locus_list( { set_id => $set_id } );
	unshift @$display_loci, q();
	$labels->{''} = 'Select locus...';
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Select locus</legend>);
	say $self->popup_menu(
		-id      => 'locus',
		-name    => 'locus',
		-values  => $display_loci,
		-labels  => $labels,
		-default => $locus
	);
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Sequence ids</legend>);
	local $" = qq(\n);
	say $q->textarea( -id => 'allele_ids', -name => 'allele_ids', -default => qq(@$allele_ids), -rows => 10 );
	say q(<div style="text-align:center"><input type="button" onclick='alleles_list_all()' )
	  . q(value="List all" style="margin-top:1em" class="smallbutton" /><input type="button" )
	  . q(onclick='alleles_clear_all()' value="Clear" style="margin-top:1em" class="smallbutton" />)
	  . q(</div>);
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Include in headers</legend>);
	my $extended = [];

	if ($locus) {
		$extended =
		  $self->{'datastore'}
		  ->run_query( 'SELECT field FROM locus_extended_attributes WHERE locus=? ORDER BY field_order',
			$locus, { fetch => 'col_arrayref' } );
	}
	push @$extended, DATABANKS;
	push @$extended, 'PubMed';
	push @$extended, 'Flags' if ( $self->{'system'}->{'allele_flags'} // q() ) eq 'yes';
	my @selected = $q->multi_param('extended');
	if (@$extended) {
		say $self->popup_menu(
			-id       => 'extended',
			-name     => 'extended',
			-values   => $extended,
			-multiple => 'true',
			-size     => 5,
			-default => \@selected
		);
	}
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach (qw(db page name query_file list_file));
	say $q->end_form;
	say q(<div style="clear:both"></div>);
	say q(</div></div>);
	return;
}

sub _print_output {
	my ( $self, $filename ) = @_;
	return if !$filename;
	my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
	if ( -e $full_path && -s $full_path ) {
		say q(<div class="box" id="resultspanel">);
		say q(<h2>Output</h2>);
		my $fasta_file = FASTA_FILE;
		say qq(<p><a href="/tmp/$filename" title="Output in FASTA format">$fasta_file</a></p>);
		say q(</div>);
	}
	return;
}

sub get_plugin_javascript {
	my ($self) = @_;
	my $extended_url =
	  "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=plugin&name=FastaExport&get_extended=1";
	my $alleles_url =
	  "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=plugin&name=FastaExport&defined=1";
	my @default_list = ( DATABANKS, 'PubMed' );
	if ( ( $self->{'system'}->{'allele_flags'} // q() ) eq 'yes' ) {
		push @default_list, 'Flags';
	}
	local $" = q(",");
	my $buffer = << "END";

\$(function () {
	\$("#locus").bind("input propertychange", function () {
		populate_extended();
	});
});

function populate_extended(){
	var locus = \$("#locus").val();
	locus = locus.replace(/^cn_/,'');
	if (locus == ""){
		return;
	}
	\$.ajax({
		url: "$extended_url" + '&locus=' + locus
	})
	.done(function(data) {
		var field_names = JSON.parse(data);
		field_names.push("@default_list");
		var selected = \$("#extended").val();
		\$("#extended").empty();
		\$.each(field_names, function(value,key){
			\$("#extended").append(\$("<option></option>").attr("value",key).text(key))
		});
		\$("#extended").val(selected);
	});
}

function alleles_clear_all(){
	\$("#allele_ids").val("");
}

function alleles_list_all(){
	var locus = \$("#locus").val();
	locus = locus.replace(/^cn_/,'');
	if (locus == ""){
		return;
	}
	\$.ajax({
		url: "$alleles_url" + '&locus=' + locus,
		cache: false
	})
	.done(function(data) {
		\$("#allele_ids").val(data);
	});
}

END
	return $buffer;
}

sub get_initiation_values {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('get_extended') && $q->param('locus') ) {
		return { type => 'json' };
	}
	if ( $q->param('defined') && $q->param('locus') ) {
		return { type => 'text' };
	}
}

sub _get_extended {
	my ( $self, $locus ) = @_;
	my $extended =
	  $self->{'datastore'}->run_query( 'SELECT field FROM locus_extended_attributes WHERE locus=? ORDER BY field_order',
		$locus, { fetch => 'col_arrayref' } );
	say encode_json($extended);
	return;
}

sub _get_defined_alleles {
	my ( $self, $locus ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $format     = $locus_info->{'allele_id_format'} // 'text';
	my $cast       = $format eq 'integer' ? 'CAST(allele_id AS integer)' : 'allele_id';
	my $defined =
	  $self->{'datastore'}
	  ->run_query( "SELECT $cast FROM sequences WHERE locus=? AND allele_id NOT IN ('0','N') ORDER BY allele_id",
		$locus, { fetch => 'col_arrayref' } );
	say $_ foreach @$defined;
	return;
}
1;
