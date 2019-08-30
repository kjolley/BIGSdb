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
use BIGSdb::Constants qw(:interface);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

sub get_attributes {
	my %att = (
		name        => 'FASTA Export',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Export FASTA file of sequences following an allele attribute query',
		category    => 'Export',
		menutext    => 'Export FASTA',
		buttontext  => 'FASTA',
		module      => 'FastaExport',
		version     => '1.1.0',
		dbtype      => 'sequences',
		seqdb_type  => 'sequences',
		input       => 'query',
		section     => 'postquery',
		order       => 10
	);
	return \%att;
}

sub _create_fasta_file {
	my ( $self, $locus, $allele_id_string ) = @_;
	my @list      = split /\r?\n/x, $allele_id_string;
	my $temp      = BIGSdb::Utils::get_random();
	my $filename  = "$temp.fas";
	my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
	my $invalid   = [];
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
		say $fh ">${locus}_$seq_data->{'allele_id'}";
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
	say q(<h1>Export sequences in FASTA file</h1>);
	my $locus = $q->param('locus');
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
	my $query_file = $q->param('query_file');
	my $list_file  = $q->param('list_file');
	my $allele_ids = $self->get_allele_id_list( $query_file, $list_file );
	my $set_id     = $self->get_set_id;
	say q(<div class="box" id="queryform">);
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
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach (qw(db page name query_file list_file));
	say $q->end_form;
	say q(<div style="clear:both"></div>);
	say q(</div>);
	$self->_print_output($filename);
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
1;
