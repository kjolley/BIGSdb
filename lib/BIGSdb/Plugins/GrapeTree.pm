#GrapeTree.pm - MST visualization plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2017, University of Oxford
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
#
package BIGSdb::Plugins::GrapeTree;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name                => 'GrapeTree',
		author              => 'Keith Jolley',
		affiliation         => 'University of Oxford, UK',
		email               => 'keith.jolley@zoo.ox.ac.uk',
		description         => 'Visualization of genomic relationships',
		menu_description    => 'Visualization of genomic relationships',
		category            => 'Third party',
		buttontext          => 'GrapeTree',
		menutext            => 'GrapeTree',
		module              => 'GrapeTree',
		version             => '1.0.0',
		dbtype              => 'isolates',
		section             => 'third_party,postquery',
		input               => 'query',
		help                => 'tooltips',
		requires            => 'offline_jobs,js_tree,EnteroMSTree',
		order               => 20,
		min                 => 2,
		system_flag         => 'GrapeTree',
		always_show_in_menu => 1
	);
	return \%att;
}

sub print_info_panel {
	my ($self) = @_;
	my $logo = '/images/plugins/GrapeTree/logo.png';
	say q(<div class="box" id="resultspanel">);
	if ( -e "$ENV{'DOCUMENT_ROOT'}$logo" ) {
		say q(<div style="float:left">);
		say qq(<img src="$logo" style="max-width:95%" />);
		say q(</div>);
	}
	say q(<div style="float:left">);
	say q(<p>This plugin generates a minimum-spanning tree and visualizes within GrapeTree:</p>);
	say q(<h2>GrapeTree: Visualization of core genomic relationships</h2>);
	say q(<p>GrapeTree is developed by:</p>);
	say q(<li>Zhemin Zhou (1)</li>);
	say q(<li>Nabil-Fareed Alikhan (1)</li>);
	say q(<li>Martin J. Sergeant (1)</li>);
	say q(<li>Nina Luhmann (1)</li>);
	say q(<li>C&aacute;tia Vaz (2,5)</li>);
	say q(<li>Alexandre P. Francisco (2,4)</li>);
	say q(<li>Jo&atilde;o Andr&eacute; Carri&ccedil;o (3)</li>);
	say q(<li>Mark Achtman (1)</li>);
	say q(</ul>);
	say q(<ol>);
	say q(<li>Warwick Medical School, University of Warwick, UK</li>);
	say q(<li>Instituto de Engenharia de Sistemas e Computadores: Investiga&ccedil;&atilde;o e Desenvolvimento )
	  . q((INESC-ID), Lisboa, Portugal</li>);
	say q(<li>Universidade de Lisboa, Faculdade de Medicina, Instituto de Microbiologia and Instituto de Medicina )
	  . q(Molecular, Lisboa, Portugal</li>);
	say q(<li>Instituto Superior T&eacute;cnico, Universidade de Lisboa, Lisboa, Portugal</li>);
	say q(<li>ADEETC, Instituto Superior de Engenharia de Lisboa, Instituto Polit&eacute;cnico de Lisboa, )
	  . q(Lisboa, Portugal</li>);
	say q(</ol>);
	say q(<p>Publication: Zhou <i>at al.</i> (2017) GrapeTree: Visualization of core genomic relationships among )
	  . q(100,000 bacterial pathogens. <a href="https://www.biorxiv.org/content/early/2017/11/09/216788">)
	  . q(bioRxiv preprint</a>.</p>);
	say q(</div><div style="clear:both"></div></div>);
	return;
}

sub _print_interface {
	my ( $self, $isolate_ids ) = @_;
	my $set_id = $self->get_set_id;
	my $q      = $self->{'cgi'};
	$self->print_info_panel;
	say q(<div class="box" id="queryform">);
	say $q->start_form;
	$self->print_id_fieldset( { list => $isolate_ids } );
	say q(<fieldset style="float:left"><legend>Include fields</legend>);
	say q(<p>Select additional fields to include in GrapeTree metadata.</p>);
	my ( $headings, $labels ) = $self->get_field_selection_list(
		{
			isolate_fields      => 1,
			extended_attributes => 1,
			loci                => 0,
			query_pref          => 0,
			analysis_pref       => 1,
			scheme_fields       => 1,
			set_id              => $set_id
		}
	);
	my $fields = [];

	foreach my $field (@$headings) {
		next if $field eq 'f_id';
		next if $field eq "f_$self->{'system'}->{'labelfield'}";
		push @$fields, $field;
	}
	say $self->popup_menu(
		-name     => 'include_fields',
		-id       => 'include_fields',
		-values   => $fields,
		-labels   => $labels,
		-multiple => 'true',
		-size     => 6
	);
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach qw (db page name);
	say $q->end_form;
	say q(</div>);
	return;
}

sub run {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $desc   = $self->get_db_description;
	say qq(<h1>GrapeTree: Visualization of genomic relationships - $desc</h1>);
	my $isolate_ids = [];
	if ( $q->param('submit') ) {
	}
	if ( $q->param('query_file') ) {
		my $qry_ref = $self->get_query( $q->param('query_file') );
		if ($qry_ref) {
			$isolate_ids = $self->get_ids_from_query($qry_ref);
		}
	}
	$self->_print_interface($isolate_ids);
	return;
}
1;
