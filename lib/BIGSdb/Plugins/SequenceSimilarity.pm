#SequenceSimilarity.pm - Plugin for BIGSdb
#This requires the SequenceComparison plugin
#Written by Keith Jolley
#Copyright (c) 2010-2024, University of Oxford
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
package BIGSdb::Plugins::SequenceSimilarity;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use BIGSdb::Constants qw(:interface);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name    => 'Sequence Similarity',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			}
		],
		description      => 'Find sequences most similar to selected allele',
		full_description => 'This plugin will return a list of the most similar alleles to a selected allele, along '
		  . 'with values for percentage identity, number of mismatches, and number of gaps. Clicking on the link for '
		  . 'each returned match will lead to a sequence comparison page, identifying the exact nucleotide/amino acid '
		  . 'differences between the query and most similar sequences.',
		category => 'Analysis',
		menutext => 'Sequence similarity',
		module   => 'SequenceSimilarity',
		url      =>
		  "$self->{'config'}->{'doclink'}/data_query/0050_investigating_allele_differences.html#sequence-similarity",
		version    => '1.2.0',
		dbtype     => 'sequences',
		seqdb_type => 'sequences',
		section    => 'analysis',
		order      => 10,
		image      => '/images/plugins/SequenceSimilarity/screenshot.png'
	);
	return \%att;
}

sub get_initiation_values {
	return { 'jQuery.tablesort' => 1, 'jQuery.multiselect' => 1 };
}

sub run {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $locus  = $q->param('locus') || '';
	$locus =~ s/^cn_//x;
	my $allele = $q->param('allele');
	say q(<h1>Find most similar alleles</h1>);
	my $set_id = $self->get_set_id;
	my ( $display_loci, $cleaned ) =
	  $self->{'datastore'}->get_locus_list( { set_id => $set_id, no_list_by_common_name => 1 } );

	if ( !@$display_loci ) {
		$self->print_bad_status( { message => q(No loci have been defined for this database.), navbar => 1 } );
		return;
	}
	say q(<div class="box" id="queryform">);
	say q(<p>This page allows you to find the most similar sequences to a selected allele using BLAST.</p>);
	my $num_results = 10;
	if ( defined $q->param('num_results') && $q->param('num_results') =~ /(\d+)/x ) {
		$num_results = $1;
	}
	say $q->start_form;
	say $q->hidden($_) foreach qw (db page name);
	say q(<fieldset style="float:left"><legend>Select parameters</legend>);
	say q(<ul><li><label for="locus" class="parameter">Locus: </label>);
	say $q->popup_menu( -name => 'locus', -id => 'locus', -values => $display_loci, -labels => $cleaned );
	say q(</li><li><label for="allele" class="parameter">Allele: </label>);
	say $q->textfield( -name => 'allele', -id => 'allele', -size => 4 );
	say q(</li><li><label for="num_results" class="parameter">Number of results:</label>);
	say $q->popup_menu(
		-name    => 'num_results',
		-id      => 'num_results',
		-values  => [ 5, 10, 25, 50, 100, 200 ],
		-default => $num_results
	);
	say q(</li></ul></fieldset>);
	$self->print_action_fieldset( { name => 'SequenceSimilarity' } );
	say $q->end_form;
	say q(</div>);
	return if !$locus || !defined $allele || $allele eq q();

	if ( !$self->{'datastore'}->is_locus($locus) ) {
		$self->print_bad_status( { message => q(Invalid locus entered.) } );
		return;
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( $locus_info->{'allele_id_format'} eq 'integer' && !BIGSdb::Utils::is_int($allele) ) {
		$self->print_bad_status( { message => q(Allele must be an integer.) } );
		return;
	}
	my ($valid) =
	  $self->{'datastore'}
	  ->run_query( q(SELECT EXISTS(SELECT * FROM sequences WHERE (locus,allele_id)=(?,?) AND allele_id != '0')),
		[ $locus, $allele ] );
	if ( !$valid ) {
		$self->print_bad_status( { message => qq(Allele $locus-$allele does not exist.) } );
		return;
	}
	my $cleanlocus = $self->clean_locus($locus);
	my $seq_ref    = $self->{'datastore'}->get_sequence( $locus, $allele );
	my $blast_obj  = $self->_get_blast_obj($locus);
	$blast_obj->blast( $seq_ref, { num_results => $num_results + 1 } );
	my $partial_matches = $blast_obj->get_partial_matches( { details => 1 } );
	my $matches         = ref $partial_matches->{$locus} eq 'ARRAY' ? $partial_matches->{$locus} : [];
	say q(<div class="box resultstable">);
	say qq(<h2>$cleanlocus-$allele</h2>);

	if ( @$matches > 1 ) {
		say q(<table class="resultstable"><tr><th>Allele</th><th>% Identity</th><th>Mismatches</th>)
		  . q(<th>Gaps</th><th>Alignment</th><th>Compare</th></tr>);
		my $td = 1;
		foreach my $match (@$matches) {
			next if $match->{'allele'} eq $allele;
			my $length = length $$seq_ref;
			say qq(<tr class="td$td"><td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=alleleInfo&amp;locus=$locus&amp;allele_id=$match->{'allele'}">)
			  . qq($cleanlocus: $match->{'allele'}</a></td><td>$match->{'identity'}</td>)
			  . qq(<td>$match->{'mismatches'}</td><td>$match->{'gaps'}</td><td>$match->{'alignment'}/$length)
			  . q(</td><td>);
			say $q->start_form;
			$q->param( allele1 => $allele );
			$q->param( allele2 => $match->{'allele'} );
			$q->param( name    => 'SequenceComparison' );
			$q->param( sent    => 1 );
			say $q->hidden($_) foreach qw (db page name locus allele1 allele2 sent);
			my $compare = COMPARE;
			say qq(<button type="submit" name="compare:$match->{'allele'}" class="smallbutton">$compare</button>);
			say $q->end_form;
			say q(</td></tr>);
			$td = $td == 1 ? 2 : 1;
		}
		say q(</table>);
	} else {
		say q(<p>No similar alleles found.</p>);
	}
	say q(</div>);
	return;
}

sub _get_blast_obj {
	my ( $self, $locus ) = @_;
	my $blast_obj = BIGSdb::Offline::Blast->new(
		{
			config_dir       => $self->{'config_dir'},
			lib_dir          => $self->{'lib_dir'},
			dbase_config_dir => $self->{'dbase_config_dir'},
			host             => $self->{'system'}->{'host'},
			port             => $self->{'system'}->{'port'},
			user             => $self->{'system'}->{'user'},
			password         => $self->{'system'}->{'password'},
			options          => {
				l             => ($locus),
				keep_partials => 1,
				find_similar  => 1,
				always_run    => 1
			},
			instance => $self->{'instance'},
			logger   => $logger
		}
	);
	return $blast_obj;
}

sub get_plugin_javascript {
	my $buffer = << "END";
\$(function () {
  	\$('#locus').multiselect({
 		classes: 'filter',
 		menuHeight: 350,
 		menuWidth: 400,
 		selectedList: 1,
  	}).multiselectfilter();
});
END
	return $buffer;
}
1;
