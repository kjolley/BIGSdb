#SequenceSimilarity.pm - Plugin for BIGSdb
#This requires the SequenceComparison plugin
#Written by Keith Jolley
#Copyright (c) 2010-2012, University of Oxford
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
package BIGSdb::Plugins::SequenceSimilarity;
use strict;
use warnings;
use parent qw(BIGSdb::Plugin BIGSdb::BlastPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use Apache2::Connection ();

sub get_attributes {
	my %att = (
		name             => 'Sequence Similarity',
		author           => 'Keith Jolley',
		affiliation      => 'University of Oxford, UK',
		email            => 'keith.jolley@zoo.ox.ac.uk',
		description      => 'Find sequences most similar to selected allele',
		menu_description => 'find sequences most similar to selected allele.',
		category         => 'Analysis',
		menutext         => 'Sequence similarity',
		module           => 'SequenceSimilarity',
		version          => '1.0.1',
		dbtype           => 'sequences',
		seqdb_type       => 'sequences',
		section          => 'analysis',
		requires         => '',
		order            => 10
	);
	return \%att;
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $locus = $q->param('locus') || '';
	$locus =~ s/^cn_//;
	my $allele = $q->param('allele');
	print "<h1>Find most similar alleles</h1>\n";
	my ( $display_loci, $cleaned ) = $self->{'datastore'}->get_locus_list;
	if ( !@$display_loci ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No loci have been defined for this database.</p></div>\n";
		return;
	}
	print "<div class=\"box\" id=\"queryform\">\n";
	print "<p>This page allows you to find the most similar sequences to a selected allele using BLAST.</p>\n";
	my $num_results =
	  ( defined $q->param('num_results') && $q->param('num_results') =~ /(\d+)/ )
	  ? $1
	  : 10;
	print $q->start_form;
	print $q->hidden($_) foreach qw (db page name);
	print "<table>";
	print "<tr><td style=\"text-align:right\">Select locus: </td><td>";
	print $q->popup_menu( -name => 'locus', -values => $display_loci, -labels => $cleaned );
	print "</td></tr><tr><td style=\"text-align:right\">Allele: </td><td>\n";
	print $q->textfield( -name => 'allele', -size => 4 );
	print "</td></tr><tr><td style=\"text-align:right\">Number of results: </td><td>\n";
	print $q->popup_menu( -name => 'num_results', -values => [ 5, 10, 25, 50, 100, 200 ], -default => $num_results );
	print "</td></tr>";
	print
"<tr><td style=\"text-align:left\"><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;name=SequenceSimilarity\" class=\"resetbutton\">Reset</a></td><td style=\"text-align:right\">";
	print $q->submit( -name => 'submit', -value => 'Submit', -class => 'submit' );
	print "</td></tr>\n</table>\n";
	print $q->end_form;
	print "</div>\n";
	return if !( $locus && $allele );

	if ( !$self->{'datastore'}->is_locus($locus) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid locus entered.</p></div>\n";
		return;
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( $locus_info->{'allele_id_format'} eq 'integer' && !BIGSdb::Utils::is_int($allele) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Allele must be an integer.</p></div>\n";
		return;
	}
	my ($valid) =
	  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM sequences WHERE locus=? AND allele_id=?", $locus, $allele )->[0];
	if ( !$valid ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Allele $locus-$allele does not exist.</p></div>\n";
		return;
	}
	my $cleanlocus = $self->clean_locus($locus);
	my $seq_ref = $self->{'datastore'}->get_sequence( $locus, $allele );
	my ( $blast_file, undef ) = $self->run_blast(
		{ 'locus' => $locus, 'seq_ref' => $seq_ref, 'qry_type' => $locus_info->{'data_type'}, 'num_results' => $num_results + 1 } );
	my $matches_ref = $self->_parse_blast_partial($blast_file);
	print "<div class=\"box\" id=\"resultsheader\">\n";
	print "<h2>$cleanlocus-$allele</h2>\n";
	if ( ref $matches_ref eq 'ARRAY' && scalar @$matches_ref > 0 ) {
		print
"<table class=\"resultstable\"><tr><th>Allele</th><th>% Identity</th><th>Mismatches</th><th>Gaps</th><th>Alignment</th><th>Compare</th></tr>\n";
		my $td = 1;
		foreach (@$matches_ref) {
			next if $_->{'allele'} eq $allele;
			print "<tr class=\"td$td\"><td>$cleanlocus: $_->{'allele'}</td>
			<td>$_->{'identity'}</td>
			<td>$_->{'mismatches'}</td>
			<td>$_->{'gaps'}</td>
			<td>$_->{'alignment'}/" . ( length $$seq_ref ) . "</td>\n<td>";
			print $q->start_form;
			$q->param( 'allele1', $allele );
			$q->param( 'allele2', $_->{'allele'} );
			$q->param( 'name',    'SequenceComparison' );
			$q->param( 'sent',    1 );
			print $q->hidden($_) foreach qw (db page name locus allele1 allele2 sent);
			print $q->submit( -name => "Compare $cleaned->{$locus}: $_->{'allele'}", -class => 'submit' );
			print $q->end_form;
			print "</td></tr>\n";
			$td = $td == 1 ? 2 : 1;
		}
		print "</table>\n";
	} else {
		print "<p>No similar alleles found.</p>\n";
	}

	#delete all working files
	system "rm -f $self->{'config'}->{'secure_tmp_dir'}/$blast_file";
	print "</div>\n";
}

sub _parse_blast_partial {

	#return best match
	my ( $self, $blast_file ) = @_;
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$blast_file";
	open( my $blast_fh, '<', $full_path ) || ( $logger->error("Can't open BLAST output file $full_path. $!"), return \$; );
	my @matches;
	my %allele_matched;
	while ( my $line = <$blast_fh> ) {
		next if !$line || $line =~ /^#/;
		my $match;
		my @record = split /\s+/, $line;
		next if $allele_matched{ $record[1] };    #sometimes BLAST will display two alignments for a sequence
		$match->{'allele'}     = $record[1];
		$match->{'identity'}   = $record[2];
		$match->{'alignment'}  = $record[3];
		$match->{'mismatches'} = $record[4];
		$match->{'gaps'}       = $record[5];
		push @matches, $match;
		$allele_matched{ $record[1] } = 1;
	}
	close $blast_fh;
	return \@matches;
}
1;
