#ITol.pm - Phylogenetic tree plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2016-2017, University of Oxford
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
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See thef
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
package BIGSdb::Plugins::Microreact;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugins::ITOL);
use BIGSdb::Utils;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_RECORDS => 2000;
use constant MAX_SEQS    => 100_000;

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name                => 'Microreact',
		author              => 'Keith Jolley',
		affiliation         => 'University of Oxford, UK',
		email               => 'keith.jolley@zoo.ox.ac.uk',
		description         => 'Open data visualization and sharing for genomic epidemiology',
		menu_description    => 'Open data visualization and sharing for genomic epidemiology',
		category            => 'Third party',
		buttontext          => 'Microreact',
		menutext            => 'Microreact',
		module              => 'Microreact',
		version             => '1.0.0',
		dbtype              => 'isolates',
		section             => 'third_party,postquery',
		input               => 'query',
		help                => 'tooltips',
		requires            => 'aligner,offline_jobs,js_tree,clustalw',
		order               => 40,
		min                 => 2,
		max                 => MAX_RECORDS,
		always_show_in_menu => 1
	);
	return \%att;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description;
	return "Microreact - $desc";
}

sub print_info_panel {
	my ($self) = @_;
	my $logo = '/images/plugins/Microreact/logo.png';
	say q(<div class="box" id="resultspanel">);
	if ( -e "$ENV{'DOCUMENT_ROOT'}$logo" ) {
		say q(<div style="float:left">);
		say qq(<img src="$logo" style="max-width:95%" />);
		say q(</div>);
	}
	say q(<div style="float:left">);
	say q(<p>This plugin uploads data for analysis within the Microreact online service:</p>);
	say q(<h2>Microreact: visualizing and sharing data for genomic epidemiology and phylogeography</h2>);
	say q(<p>Microreact is developed by:</p>);
	say q(<ul>);
	say q(<li>Khalil Abudahab</li>);
	say q(<li>Richard Goater</li>);
	say q(<li>Artemij Fedosejev</li>);
	say q(<li>Jyothish NT</li>);
	say q(<li>Stephano</li>);
	say q(</ul>);
	say
	  q(<p>in the <a href="http://www.imperial.ac.uk/people/d.aanensen">Aanensen Research Group</a> )
	  . q(at Imperial College London and <a href="http://www.pathogensurveillance.net/">)
	  . q(The Centre for Genomic Pathogen Surveillance</a>.</p>);
	say q(<p>Web site: <a href="https://microreact.org">https://microreact.org</a><br />);
	say q(Publication: Argim&oacute;n <i>at al.</i> (2016) Microreact: visualizing and sharing data for genomic )
	  . q(epidemiology and phylogeography. <a href="https://www.ncbi.nlm.nih.gov/pubmed/28348833">)
	  . q(<i>Microb Genom</i> <b>2:</b>e000093</a>.</p>);
	say q(</div><div style="clear:both"></div></div>);
	return;
}
sub print_extra_form_elements { }
1;
