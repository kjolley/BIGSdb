#Written by Keith Jolley
#Copyright (c) 2011-2018, University of Oxford
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
use 5.010;
use parent qw(BIGSdb::CuratePage);
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
	say qq(<h1>Configuration repair - $desc</h1>);
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->print_bad_status(
			{
				message => q(This function is only for use on sequence definition databases.),
				navbar  => 1
			}
		);
		return;
	}
	say q(<div class="box" id="queryform">);
	say q(<h2>Rebuild scheme warehouse tables</h2>);
	say q(<p>Schemes can become damaged if the database is modifed outside of the web interface. This )
	  . q(is especially likely if loci that belong to schemes are renamed.</p>);
	say q(<p>Warehouse tables will be (re)created.</p>);
	my $schemes = $self->{'datastore'}->run_query(
		'SELECT id,name FROM schemes WHERE id IN (SELECT scheme_id FROM scheme_fields '
		  . 'WHERE primary_key) AND id IN (SELECT scheme_id FROM scheme_members) ORDER BY id',
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
	if ( !@$schemes ) {
		say q(<p class="statusbad">No schemes with a primary key and locus members have been defined.</p>);
	} else {
		my ( @ids, %desc );
		foreach my $scheme (@$schemes) {
			push @ids, $scheme->{'id'};
			$desc{ $scheme->{'id'} } = "$scheme->{'id'}) $scheme->{'name'}";
		}
		say q(<fieldset><legend>Select damaged scheme view</legend>);
		say $q->start_form;
		say $q->hidden($_) foreach qw (db page);
		say $q->popup_menu( -name => 'scheme_id', -values => \@ids, -labels => \%desc );
		say $q->submit( -name => 'rebuild', -value => 'Rebuild', -class => 'button' );
		say $q->end_form;
		say q(</fieldset>);
	}
	say q(</div>);
	if ( $q->param('rebuild') && $q->param('scheme_id') && BIGSdb::Utils::is_int( $q->param('scheme_id') ) ) {
		$self->_rebuild( $q->param('scheme_id') );
	}
	return;
}

sub _rebuild {
	my ( $self, $scheme_id ) = @_;
	eval { $self->{'datastore'}->run_query("SELECT initiate_scheme_warehouse($scheme_id)"); };
	if ($@) {
		$logger->error($@);
		$self->print_bad_status( { message => q(Scheme rebuild failed.), navbar => 1 } );
		$self->{'db'}->rollback;
	} else {
		$self->print_good_status( { message => q(Scheme rebuild completed.), navbar => 1 } );
		$self->{'db'}->commit;
	}
	return;
}
1;
