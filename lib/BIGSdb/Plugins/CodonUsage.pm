#XmfaExport.pm - Codon usage plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 22011, University of Oxford
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
package BIGSdb::Plugins::CodonUsage;
use strict;
use base qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use Apache2::Connection ();

sub get_attributes {
	my %att = (
		name        => 'CodonUsage',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Determine codon usage for specified loci for an isolate database query',
		category    => 'Breakdown',
		buttontext  => 'Codons',
		menutext    => 'Codon usage',
		module      => 'CodonUsage',
		version     => '1.0.0',
		dbtype      => 'isolates',
		section     => 'analysis,postquery',
		input       => 'query',
		requires    => 'offline_jobs',
		order       => 13
	);
	return \%att;
}

sub run {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	print "<h1>Codon usage analysis</h1>\n";
	my $list;
	my $qry_ref;
	if ( $q->param('list') ) {

		foreach ( split /\n/, $q->param('list') ) {
			chomp;
			push @$list, $_;
		}
	} elsif ($query_file) {
		my $qry_ref = $self->get_query($query_file);
		return if ref $qry_ref ne 'SCALAR';
		my $view = $self->{'system'}->{'view'};
		return if !$self->create_temp_tables($qry_ref);
		$$qry_ref =~ s/SELECT ($view\.\*|\*)/SELECT $view.id/;
		$self->rewrite_query_ref_order_by($qry_ref) if $self->{'system'}->{'dbtype'} eq 'isolates';
		$list = $self->{'datastore'}->run_list_query($$qry_ref);
	} else {
		$list = \@;;
	}
	if ( $q->param('submit') ) {
		my @param_names = $q->param;
		my @fields_selected;
		foreach (@param_names) {
			push @fields_selected, $_ if $_ =~ /^l_/ or $_ =~ /s_\d+_l_/;
		}
		if ( !@fields_selected ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No fields have been selected!</p></div>\n";
		} else {
			my $params    = $q->Vars;
			(my $list = $q->param('list')) =~ s/[\r\n]+/\|\|/g;
			$params->{'list'} = $list;
			my $job_id = $self->{'jobManager'}->add_job(
				{
					'dbase_config' => $self->{'instance'},
					'ip_address'   => $q->remote_host,
					'module'       => 'CodonUsage',
					'parameters'   => $params
				}
			);
			print <<"HTML";
<div class="box" id="resultstable">
<p>This analysis has been submitted to the job queue.</p>
<p>Please be aware that this job may take some time depending on the number of sequences to analyse
and how busy the server is.</p>
<p><a href="$self->{'script_name'}?db=$self->{'instance'}&amp;page=job&amp;id=$job_id">
Follow the progress of this job and view the output.</a></p> 	
</div>	
HTML
			return;
		}
	}
	print <<"HTML";
<div class="box" id="queryform">
<p>This script will analyse the codon usage for individual loci and overall for an isolate.  Only loci that 
have a corresponding database containing sequences, or with sequences tagged,  
can be included.  Please check the loci that you would like to include.</p>
HTML
	my $options = {'default_select' => 1, 'translate' => 0};
	$self->print_sequence_export_form( 'id', $list, undef, $options );
	print "</div>\n";
}
1;
