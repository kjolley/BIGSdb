#SequenceComparison.pm - Plugin for BIGSdb
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
package BIGSdb::Plugins::SequenceComparison;
use strict;
use warnings;
use base qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use Apache2::Connection ();

sub get_attributes {
	my %att = (
		name             => 'Sequence Comparison',
		author           => 'Keith Jolley',
		affiliation      => 'University of Oxford, UK',
		email            => 'keith.jolley@zoo.ox.ac.uk',
		description      => 'Display a comparison between two sequences',
		menu_description => 'display a comparison between two sequences.',
		category         => 'Analysis',
		menutext         => 'Sequence comparison',
		module           => 'SequenceComparison',
		version          => '1.0.1',
		dbtype           => 'sequences',
		seqdb_type       => 'sequences',
		section          => 'analysis',
		requires         => 'emboss',
		order            => 11
	);
	return \%att;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { 'general' => 1, 'main_display' => 0, 'isolate_display' => 0, 'analysis' => 0, 'query_field' => 0 };
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<h1>Allele sequence comparison</h1>\n";
	my ( $display_loci, $cleaned ) = $self->{'datastore'}->get_locus_list;
	if ( !@$display_loci ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No loci have been defined for this database.</p></div>\n";
		return;
	}
	print "<div class=\"box\" id=\"queryform\">\n";
	print "<p>This tool allows you to select two alleles and highlight the nucleotide differences between them.</p>\n";
	my $locus = $q->param('locus') || '';
	if ( $locus =~ /^cn_(.+)/ ) {
		$locus = $1;
		$q->param( 'locus', $locus );
	}
	print $q->start_form;
	my $sent = $q->param('sent');
	$q->param( 'sent', 1 );
	print $q->hidden($_) foreach qw (db page name sent);
	print "<table>";
	print "<tr><td style=\"text-align:right\">Select locus: </td><td>\n";
	print $q->popup_menu( -name => 'locus', -values => $display_loci, -labels => $cleaned );
	print "</td></tr>\n";

	foreach (qw(1 2)) {
		print "<tr><td style=\"text-align:right\">Allele #$_</td><td>\n";
		print $q->textfield( -name => "allele$_", size => '8' );
		print "</td></tr>\n";
	}
	print "<tr><td /><td>\n";
	print $q->submit( -name => 'Submit', -class => 'submit' );
	print "</td></tr>\n";
	print "</table>\n";
	print $q->endform;
	print "</div>\n";
	return if !$sent;
	my @seq;
	my $displaylocus = $self->clean_locus($locus);
	my $allele1      = $q->param('allele1');
	my $allele2      = $q->param('allele2');

	if ( !$allele1 || !$allele2 ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Please enter two allele identifiers.</p></div>\n";
		return;
	} elsif ( $allele1 eq $allele2 ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Please enter two <em>different</em> allele numbers.</p></div>\n";
		return;
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( $locus_info->{'allele_id_format'} eq 'integer' && ( !BIGSdb::Utils::is_int($allele1) || !BIGSdb::Utils::is_int($allele2) ) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Both your allele identifiers should be integers.</p></div>\n";
		return;
	}
	my $seq1_ref = $self->{'datastore'}->get_sequence( $locus, $allele1 );
	my $seq2_ref = $self->{'datastore'}->get_sequence( $locus, $allele2 );
	if ( !defined $$seq1_ref ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Allele #1 has not been defined.</p></div>\n";
		return;
	} elsif ( !defined $$seq2_ref ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Allele #2 has not been defined.</p></div>\n";
		return;
	}
	print "<div class=\"box\" id=\"resultsheader\">\n";
	print "<h2>Nucleotide differences between $displaylocus: $allele1 and $displaylocus: $allele2</h2>\n";
	my $temp = &BIGSdb::Utils::get_random();
	my $buffer;
	if ( length $$seq1_ref == length $$seq2_ref ) {
		my @results;
		for my $i ( 0 .. length $$seq1_ref ) {
			my $base1 = substr( $$seq1_ref, $i, 1 );
			my $base2 = substr( $$seq2_ref, $i, 1 );
			if ( $base1 ne $base2 ) {
				my $pos = $i + 1;
				push @results, "$pos: <span class=\"$base1\">$base1</span> &rarr; <span class=\"$base2\">$base2</span>";
			}
		}
		my $numdiffs = scalar @results;
		my $ident = BIGSdb::Utils::decimal_place( 100 - ( ( $numdiffs / ( length $$seq1_ref ) ) * 100 ), 2 );
		$buffer .= "<p>Identity: $ident %<br />\n";
		$buffer .= "<a href=\"/tmp/$temp.txt\"> View alignment </a>\n" if $self->{'config'}->{'emboss_path'};
		$buffer .= "</p>\n";
		$buffer .= "<p>Differences: $numdiffs<br />\n";
		$" = "<br />\n";
		$buffer .= "@results</p>";
	} else {
		print "<p>The alleles at this locus can have insertions or deletions so an alignment will be performed.</p>\n";
	}
	if ( $self->{'config'}->{'emboss_path'} ) {
		my $seq1_infile = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_1.txt";
		my $seq2_infile = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_2.txt";
		open( my $fh, '>', $seq1_infile )
		  || $logger->error("Could not write temporary input file");
		print $fh ">$allele1\n";
		print $fh $$seq1_ref;
		close $fh;
		open( $fh, '>', $seq2_infile )
		  || $logger->error("Could not write temporary input file");
		print $fh ">$allele2\n";
		print $fh $$seq2_ref;
		close $fh;
		my $outfile = "$self->{'config'}->{'tmp_dir'}/$temp.txt";

		#run EMBOSS stretcher
		system(
"$self->{'config'}->{'emboss_path'}/stretcher -aformat markx2 -awidth $self->{'prefs'}->{'alignwidth'} $seq1_infile $seq2_infile $outfile 2> /dev/null"
		);
		unlink $seq1_infile, $seq2_infile;
		if ( length $$seq1_ref != length $$seq2_ref ) {
			print "<pre style=\"font-size:1.2em\">\n";
			$self->print_file( "$self->{'config'}->{'tmp_dir'}/$temp.txt", 1 );
			print "</pre>\n";
		}
	}
	print $buffer if $buffer;
	print "</div>\n";
}
1;
