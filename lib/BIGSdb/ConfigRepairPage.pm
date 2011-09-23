#Written by Keith Jolley
#Copyright (c) 2011, University of Oxford
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
package BIGSdb::ConfigRepairPage;
use strict;
use warnings;
use base qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Configuration repair - $desc";
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	print "<h1>Configuration repair - $desc</h1>";
	if ($self->{'system'}->{'dbtype'} eq 'isolates'){
		print "<div class=\"box\" id=\"statusbad\"><p>This function is only for use on sequence definition databases.</p></div>\n";
		return;
	} 
	print "<div class=\"box\" id=\"queryform\">\n";
	print "<h2>Rebuild scheme views</h2>\n";
	print "<p>Scheme views can become damaged if the database is modifed outside of the web interface. This "
	  . "is especially likely if loci that belong to schemes are renamed.</p>";
	my $scheme_ids =
	  $self->{'datastore'}
	  ->run_list_query_hashref( "SELECT id,description FROM schemes WHERE id IN (SELECT scheme_id FROM scheme_fields WHERE primary_key) "
		  . "AND id IN (SELECT scheme_id FROM scheme_members) ORDER BY id" );
	if (!@$scheme_ids){
		print "<p class=\"statusbad\">No schemes with a primary key and locus members have been defined.</p>\n"; 
	} else {
		print "<p>Select the damaged scheme view and click 'Rebuid'.</p>\n";
		my (@ids, %desc);
		foreach (@$scheme_ids){
			push @ids, $_->{'id'};
			$desc{$_->{'id'}} = "$_->{'id'}) $_->{'description'}";
		}
		print $q->start_form;
		print $q->hidden($_) foreach qw (db page);
		print $q->popup_menu(-name => 'scheme_id', -values => \@ids, -labels => \%desc);
		print $q->submit(-name => 'rebuild', -value => 'Rebuild', -class => 'submit');
		print $q->end_form;
	}
	print "</div>\n";
	if ($q->param('rebuild') && $q->param('scheme_id') && BIGSdb::Utils::is_int($q->param('scheme_id'))){
		$self->_rebuild($q->param('scheme_id'));
	}
	return;
}

sub _rebuild {
	my ($self, $scheme_id) = @_;
	eval { 
		$self->drop_scheme_view($scheme_id);
		$self->create_scheme_view($scheme_id);
	};
	if ($@){
		print "<div class=\"box\" id=\"statusbad\"><p>Scheme rebuild failed.</p></div>\n";
		$self->{'db'}->rollback;
	} else {
		print "<div class=\"box\" id=\"resultsheader\"><p>Scheme rebuild completed.</p></div>\n";
		$self->{'db'}->commit;
	}
	return;	
}

1;
