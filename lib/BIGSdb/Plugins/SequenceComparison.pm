#SequenceComparison.pm - Plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2020, University of Oxford
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
use 5.010;
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name    => 'Sequence Comparison',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@zoo.ox.ac.uk',
			}
		],
		description      => 'Display a comparison between two sequences',
		full_description => 'This shows the nucleotide/amino acid differences between two selected alleles/variants.',
		category         => 'Analysis',
		menutext         => 'Sequence comparison',
		module           => 'SequenceComparison',
		url =>
		  "$self->{'config'}->{'doclink'}/data_query/0050_investigating_allele_differences.html#sequence-comparison"
		,
		version    => '1.0.11',
		dbtype     => 'sequences',
		seqdb_type => 'sequences',
		section    => 'analysis',
		requires   => 'emboss',
		order      => 11,
		image      => '/images/plugins/SequenceComparison/screenshot.png'
	);
	return \%att;
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Allele sequence comparison</h1>);
	my $set_id = $self->get_set_id;
	my ( $display_loci, $cleaned ) = $self->{'datastore'}->get_locus_list( { set_id => $set_id } );
	if ( !@$display_loci ) {
		$self->print_bad_status( { message => q(No loci have been defined for this database.), navbar => 1 } );
		return;
	}
	say q(<div class="box" id="queryform">);
	say q(<p>This tool allows you to select two alleles and highlight the nucleotide differences between them.</p>);
	my $locus = $q->param('locus') // q();
	if ( $locus =~ /^cn_(.+)/x ) {
		$locus = $1;
		$q->param( locus => $locus );
	}
	say $q->start_form;
	my $sent = $q->param('sent');
	$q->param( sent => 1 );
	say $q->hidden($_) foreach qw (db page name sent);
	say q(<fieldset style="float:left"><legend>Select parameters</legend>);
	say q(<ul><li>);
	say q(<label for="locus" class="display">Locus: </label>);
	say $q->popup_menu( -name => 'locus', -id => 'locus', values => $display_loci, -labels => $cleaned );
	say q(</li>);

	foreach my $num (qw(1 2)) {
		say qq(<li><label for="allele$num" class="display">Allele #$num: </label>);
		say $q->textfield( -name => "allele$num", -id => "allele$num", -size => 8 );
		say q(</li>);
	}
	say q(</ul></fieldset>);
	$self->print_action_fieldset( { name => 'SequenceComparison', no_reset => 1 } );
	say $q->end_form;
	say q(</div>);
	return if !$sent;
	my $displaylocus = $self->clean_locus($locus);
	my $allele1      = $q->param('allele1');
	my $allele2      = $q->param('allele2');

	if ( !defined $allele1 || !defined $allele2 ) {
		$self->print_bad_status( { message => q(Please enter two allele identifiers.) } );
		return;
	} elsif ( $allele1 eq $allele2 ) {
		$self->print_bad_status( { message => q(Please enter two <em>different</em> allele numbers.) } );
		return;
	} elsif ( $allele1 eq '0' || $allele2 eq '0' ) {
		$self->print_bad_status( { message => q(Allele 0 is not a valid identifier.) } );
		return;
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( $locus_info->{'allele_id_format'} eq 'integer'
		&& ( !BIGSdb::Utils::is_int($allele1) || !BIGSdb::Utils::is_int($allele2) ) )
	{
		$self->print_bad_status( { message => q(Both your allele identifiers should be integers.) } );
		return;
	}
	my $seq1_ref = $self->{'datastore'}->get_sequence( $locus, $allele1 );
	my $seq2_ref = $self->{'datastore'}->get_sequence( $locus, $allele2 );
	if ( !defined $$seq1_ref ) {
		$self->print_bad_status( { message => q(Allele #1 has not been defined.) } );
		return;
	} elsif ( !defined $$seq2_ref ) {
		$self->print_bad_status( { message => q(Allele #2 has not been defined.) } );
		return;
	}
	say q(<div class="box" id="resultspanel">);
	my $type = $locus_info->{'data_type'} eq 'DNA' ? 'Nucleotide' : 'Amino acid';
	say qq(<h2>$type differences between $displaylocus: $allele1 and $displaylocus: $allele2</h2>);
	my $temp    = BIGSdb::Utils::get_random();
	my $outfile = "$self->{'config'}->{'tmp_dir'}/$temp.txt";
	if ( $self->{'config'}->{'emboss_path'} ) {
		my $seq1_infile = "$self->{'config'}->{'secure_tmp_dir'}/${temp}_1.txt";
		my $seq2_infile = "$self->{'config'}->{'secure_tmp_dir'}/${temp}_2.txt";
		open( my $fh, '>', $seq1_infile )
		  || $logger->error('Could not write temporary input file');
		say $fh ">$allele1";
		print $fh $$seq1_ref;
		close $fh;
		open( $fh, '>', $seq2_infile )
		  || $logger->error('Could not write temporary input file');
		say $fh ">$allele2";
		print $fh $$seq2_ref;
		close $fh;

		#run EMBOSS stretcher
		system( "$self->{'config'}->{'emboss_path'}/stretcher -aformat markx2 -awidth "
			  . "$self->{'prefs'}->{'alignwidth'} $seq1_infile $seq2_infile $outfile 2> /dev/null" );
		unlink $seq1_infile, $seq2_infile;
	}
	my $buffer;
	if ( length $$seq1_ref == length $$seq2_ref ) {
		my @results;
		for my $i ( 0 .. length $$seq1_ref ) {
			my $base1 = substr( $$seq1_ref, $i, 1 );
			my $base2 = substr( $$seq2_ref, $i, 1 );
			if ( $base1 ne $base2 ) {
				my $pos = $i + 1;
				if ( $locus_info->{'data_type'} eq 'peptide' ) {
					push @results, qq($pos: <span>$base1</span> &rarr; <span>$base2</span>);
				} else {
					push @results,
					  qq($pos: <span class="$base1">$base1</span> &rarr; <span class="$base2">$base2</span>);
				}
			}
		}
		my $numdiffs = scalar @results;
		my $ident = BIGSdb::Utils::decimal_place( 100 - ( ( $numdiffs / ( length $$seq1_ref ) ) * 100 ), 2 );
		$buffer .= qq(<p>Identity: $ident %</p>\n);
		$buffer .= qq(<div class="scrollable">\n);
		$buffer .= $self->get_alignment( $outfile, $temp );
		$buffer .= qq(</div>\n);
		$buffer .= qq(<p>Differences: $numdiffs<br />\n);
		local $" = qq(<br />\n);
		$buffer .= qq(@results</p>);
	} else {
		say q(<p>The alleles at this locus can have insertions or deletions so an alignment will be performed.</p>);
	}
	if ( length $$seq1_ref != length $$seq2_ref ) {
		say q(<div class="scrollable">);
		say q(<pre>);
		$self->print_file( $outfile, { ignore_hashlines => 1 } );
		say q(</pre>);
		say q(</div>);
	}
	say $buffer if $buffer;
	say q(</div>);
	return;
}

sub get_alignment {
	my ( $self, $outfile, $outfile_prefix ) = @_;
	my $buffer = '';
	if ( -e $outfile ) {
		my $cleaned_file = "$self->{'config'}->{'tmp_dir'}/${outfile_prefix}_cleaned.txt";
		$self->_cleanup_alignment( $outfile, $cleaned_file );
		$buffer .= qq(<p><a href="/tmp/${outfile_prefix}_cleaned.txt" id="alignment_link" data-rel="ajax">)
		  . qq(Show alignment</a></p>\n);
		$buffer .= qq(<pre><span id="alignment"></span></pre>\n);
	}
	return $buffer;
}

sub _cleanup_alignment {
	my ( $self, $infile, $outfile ) = @_;
	open( my $in_fh,  '<', $infile )  || $logger->error("Can't open $infile for reading");
	open( my $out_fh, '>', $outfile ) || $logger->error("Can't open $outfile for writing");
	while (<$in_fh>) {
		next if $_ =~ /^\#/x;
		print $out_fh $_;
	}
	close $in_fh;
	close $out_fh;
	return;
}

sub get_plugin_javascript {
	my $buffer = << "END";
\$(function () {
	\$('a[data-rel=ajax]').click(function(){
  		\$(this).attr('href', function(){
  			if (this.href.match(/javascript.loadContent/)){
  				return;
  			};
    		return(this.href.replace(/(.*)/, "javascript:loadContent\('\$1\'\)"));
    	});
  	});
});

function loadContent(url) {
	\$("#alignment").html('<img src=\"/javascript/themes/default/throbber.gif\" /> Loading ...').load(url);
	\$("#alignment_link").hide();
}

END
	return $buffer;
}
1;
