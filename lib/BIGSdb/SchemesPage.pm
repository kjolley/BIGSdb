#Written by Keith Jolley
#Copyright (c) 2020, University of Oxford
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
package BIGSdb::SchemesPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	say q(<h1>Download scheme profiles</h1>);
	my $set_id = $self->get_set_id;
	my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id, with_pk => 1 } );
	if ( !@$schemes ) {
		$self->print_bad_status(
			{
				message => q(No indexed schemes defined),
			}
		);
		return;
	}
	say q(<div class="box" id="resultstable">);
	say q(<p>Schemes are collections of loci. They may be indexed, in which case they have a primary key )
	  . q(field that identifies unique combinations of alleles. The following schemes are indexed.</p>);
	say q(<div class="scrollable">);
	say q(<table class="resultstable">);
	say q(<tr><th>Name</th><th>Download</th><th>Profiles</th><th>Description</th>)
	  . q(<th>Curator(s)</th><th>Last updated</th></tr>);
	my $td = 1;
	foreach my $scheme (@$schemes) {
		my $scheme_info   = $self->{'datastore'}->get_scheme_info( $scheme->{'id'} );
		my $profile_count = BIGSdb::Utils::commify(
			$self->{'datastore'}->run_query( 'SELECT COUNT(*) FROM profiles WHERE scheme_id=?', $scheme->{'id'} ) );
		my $desc = $scheme_info->{'description'} // q();
		my $curators = $self->_get_curator_string( $scheme->{'id'} );
		my $updated =
		  $self->{'datastore'}->run_query( 'SELECT MAX(datestamp) FROM profiles WHERE scheme_id=?', $scheme->{'id'} );
		$updated //= q();
		say qq(<tr class="td$td"><td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=schemeInfo&scheme_id=$scheme->{'id'}">$scheme_info->{'name'}</a></td>)
		  . qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadProfiles&amp;)
		  . qq(scheme_id=$scheme->{'id'}"><span class="file_icon fas fa-download"></span></a></td>)
		  . qq(<td>$profile_count</td><td>$desc</td><td>$curators</td><td>$updated</td></tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</table>);
	say q(</div></div>);
	return;
}

sub _get_curator_string {
	my ( $self, $scheme_id ) = @_;
	my $scheme_curators = $self->{'datastore'}->run_query(
		'SELECT curator_id FROM scheme_curators JOIN users ON users.id=scheme_curators.curator_id '
		  . 'WHERE scheme_id=? ORDER BY surname',
		$scheme_id,
		{ fetch => 'col_arrayref' }
	);
	my @curator_strings;
	if (@$scheme_curators) {
		my $plural = @$scheme_curators == 1 ? q() : q(s);
		foreach my $user_id (@$scheme_curators) {
			my $user_string = $self->{'datastore'}->get_user_string( $user_id, { email => 1 } );
			push @curator_strings, $user_string;
		}
	}
	local $" = q(, );
	return qq(@curator_strings);
}

sub get_title {
	my ($self) = @_;
	return q(Download scheme profiles);
}

sub initiate {
	my ($self) = @_;
	$self->{'jQuery'} = 1;
	$self->set_level1_breadcrumbs;
	return;
}
1;
