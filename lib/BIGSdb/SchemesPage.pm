#Written by Keith Jolley
#Copyright (c) 2020-2024, University of Oxford
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

sub _downloads_disabled {
	my ($self) = @_;
	return 1
	  if ( $self->{'system'}->{'disable_profile_downloads'} // q() ) eq 'yes'
	  && !$self->is_admin;
	return;
}

sub print_content {
	my ($self) = @_;
	say q(<h1>Download scheme profiles</h1>);
	if ( $self->{'system'}->{'dbtype'} ne 'sequences' ) {
		$self->print_bad_status(
			{
				message => q(This function is only available for sequence definition databases),
				navbar  => 1
			}
		);
		return;
	}
	my $set_id  = $self->get_set_id;
	my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id, with_pk => 1 } );
	if ( !@$schemes ) {
		$self->print_bad_status(
			{
				message => q(No indexed schemes defined),
			}
		);
		return;
	}
	$self->_print_api_message;
	my $downloads_disabled = $self->_downloads_disabled;
	say q(<div class="box" id="resultstable">);
	say q(<p>Schemes are collections of loci. They may be indexed, in which case they have a primary key )
	  . q(field that identifies unique combinations of alleles. The following schemes are indexed.</p>);
	say q(<div class="scrollable">);
	say q(<table class="resultstable">);
	say q(<tr><th>Name</th>);
	say q(<th>Download</th>) if !$downloads_disabled;
	say q(<th>Profiles</th><th>Description</th><th>Curator(s)</th><th>Last updated</th></tr>);
	my $td = 1;

	foreach my $scheme (@$schemes) {
		my $scheme_info   = $self->{'datastore'}->get_scheme_info( $scheme->{'id'} );
		my $profile_count = BIGSdb::Utils::commify(
			$self->{'datastore'}->run_query( 'SELECT COUNT(*) FROM profiles WHERE scheme_id=?', $scheme->{'id'} ) );
		my $desc     = $scheme_info->{'description'} // q();
		my $curators = $self->_get_curator_string( $scheme->{'id'} );
		my $updated =
		  $self->{'datastore'}->run_query( 'SELECT MAX(datestamp) FROM profiles WHERE scheme_id=?', $scheme->{'id'} );
		$updated //= q();
		say qq(<tr class="td$td"><td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=schemeInfo&scheme_id=$scheme->{'id'}">$scheme_info->{'name'}</a></td>);
		if ( !$downloads_disabled ) {
			say
			  qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadProfiles&amp;)
			  . qq(scheme_id=$scheme->{'id'}"><span class="file_icon fas fa-download"></span></a></td>);
		}
		say qq(<td>$profile_count</td><td>$desc</td><td>$curators</td><td>$updated</td></tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</table>);
	say q(</div></div>);
	return;
}

sub _print_api_message {
	my ($self) = @_;
	my $date_restriction_message = $self->get_date_restriction_message;
	if ( $self->{'config'}->{'rest_url'} ) {
		my $url = "$self->{'config'}->{'rest_url'}/db/$self->{'instance'}";
		say q(<div class="box" id="message">);
		say q(<h2>Programmatic access</h2>);
		say q(<p>Please note that if you are scripting downloads of allelic profiles then you should use the )
		  . qq(<a href="$url" target="_blank">application programming interface (API)</a> to do this.</p>);
		my $doc_url   = 'https://bigsdb.readthedocs.io/en/latest/rest.html';
		my $fasta_url = 'https://bigsdb.readthedocs.io/en/latest/rest.html#' . 'db-schemes-scheme-id-profiles-csv';
		say qq(<p>See the API <a href="$doc_url" target="_blank">documentation</a> for more details - in particular, )
		  . qq(the method call for <a href="$fasta_url" target="_blank">downloading a list of profiles</a> for a specified )
		  . q(scheme.</p>);
		say $date_restriction_message if $date_restriction_message;
		say q(</div>);
	} else {
		say qq(<div class="box banner">$date_restriction_message</div>);
	}
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
