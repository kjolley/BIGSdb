#Written by Keith Jolley
#Copyright (c) 2010-2016, University of Oxford
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
package BIGSdb::SchemeInfoPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use BIGSdb::Utils;

sub get_title {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	my $desc      = $self->get_db_description;
	return "Invalid scheme - $desc" if !BIGSdb::Utils::is_int($scheme_id);
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
	return "Invalid scheme - $desc" if !$scheme_info;
	return "$scheme_info->{'name'} - $desc";
}

sub print_content {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	my $desc      = $self->get_db_description;
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		say q(<h1>Scheme information</h1>);
		say q(<div class="box" id="statusbad"><p>Invalid scheme selected.</p></div>);
		return;
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
	if ( !$scheme_info ) {
		say q(<h1>Scheme information</h1>);
		say q(<div class="box" id="statusbad"><p>Invalid scheme selected.</p></div>);
		return;
	}
	say qq(<h1>Scheme information - $scheme_info->{'name'}</h1>);
	say q(<div class="box" id="resultspanel">);
	my $flags = $self->get_scheme_flags($scheme_id);
	if ($flags) {
		say qq(<div style="margin-bottom:1em">$flags</div>);
	}
	say qq(<p>$scheme_info->{'description'}</p>) if $scheme_info->{'description'};
	$self->_print_scheme_curators($scheme_id);
	$self->_print_loci($scheme_id);
	$self->_print_profiles($scheme_id);
	say q(</div>);
	return;
}

sub _print_scheme_curators {
	my ( $self, $scheme_id ) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'sequences';
	my $scheme_curators = $self->{'datastore'}->run_query(
		'SELECT curator_id FROM scheme_curators JOIN users ON users.id=scheme_curators.curator_id '
		  . 'WHERE scheme_id=? ORDER BY surname',
		$scheme_id,
		{ fetch => 'col_arrayref' }
	);
	if (@$scheme_curators) {
		my $plural = @$scheme_curators == 1 ? q() : q(s);
		say qq(<h2>Curator$plural</h2>);
		say q(<p>This scheme is curated by:</p><ul>);
		foreach my $user_id (@$scheme_curators) {
			my $user_string = $self->{'datastore'}->get_user_string( $user_id, { email => 1, affiliation => 1 } );
			say qq(<li>$user_string</li>);
		}
		say q(</ul>);
	}
	return;
}

sub _print_loci {
	my ( $self, $scheme_id ) = @_;
	my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	say q(<h2>Loci</h2>);
	my $count = @$scheme_loci;
	my $plural = @$scheme_loci == 1 ? q(us) : q(i);
	say qq(<p>This scheme consists of alleles from $count loc$plural.</p>);
	if ( @$scheme_loci <= 20 ) {
		say q(<ul>);
		foreach my $locus (@$scheme_loci) {
			say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=locusInfo&amp;locus=$locus">);
			my $clean_locus = $self->clean_locus($locus);
			say qq($locus</a></li>);
		}
		say q(</ul>);
	}
	return;
}

sub _print_profiles {
	my ( $self, $scheme_id ) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'sequences';
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id,{get_pk=>1});
	return if !$scheme_info->{'primary_key'};
	my $count = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM mv_scheme_$scheme_id");
	my $plural = $count == 1 ? q() : q(s);
	say q(<h2>Profiles</h2>);
	my $nice_count = BIGSdb::Utils::commify($count);
	say qq(<p>This scheme has <a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	. qq(page=query&amp;scheme_id=$scheme_id&amp;submit=1">$nice_count profile$plural</a> defined.</p>);
	return;
}
1;
