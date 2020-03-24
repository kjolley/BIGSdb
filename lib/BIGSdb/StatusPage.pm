#Written by Keith Jolley
#Copyright (c) 2020, University of Oxford
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
package BIGSdb::StatusPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description || 'BIGSdb';
	return "Database status: $desc";
}

sub print_content {
	my ($self) = @_;
	my $desc = $self->get_db_description || 'BIGSdb';
	my $cache_string = $self->get_cache_string;
	say qq(<h1>Database status: $desc</h1>);
	say q(<div class="box" id="resultspanel">);
	say q(<h2>Overview</h2>);
	say q(<ul>);
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $allele_count = BIGSdb::Utils::commify( $self->_get_allele_count );
		say qq(<li>Sequences: $allele_count</li>);
		my $scheme_data = $self->get_scheme_data( { with_pk => 1 } );
		if ( @$scheme_data == 1 ) {
			foreach (@$scheme_data) {
				my $profile_count =
				  $self->{'datastore'}
				  ->run_query( 'SELECT COUNT(*) FROM profiles WHERE scheme_id=?', $scheme_data->[0]->{'id'} );
				my $commified = BIGSdb::Utils::commify($profile_count);
				say qq(<li>Profiles ($scheme_data->[0]->{'name'}): $commified</li>);
			}
		} elsif ( @$scheme_data > 1 ) {
			say q(<li>Profiles: <a id="toggle1" class="showhide">Show</a>);
			say q(<a id="toggle2" class="hideshow">Hide</a><div class="hideshow"><ul>);
			foreach (@$scheme_data) {
				my $profile_count =
				  $self->{'datastore'}->run_query( 'SELECT COUNT(*) FROM profiles WHERE scheme_id=?', $_->{'id'} );
				my $commified = BIGSdb::Utils::commify($profile_count);
				$_->{'name'} =~ s/\&/\&amp;/gx;
				say qq(<li>$_->{'name'}: $commified</li>);
			}
			say q(</ul></div></li>);
		}
	} else {
		my $isolate_count =
		  $self->{'datastore'}->run_query("SELECT COUNT(*) FROM $self->{'system'}->{'view'}");
		my $commified = BIGSdb::Utils::commify($isolate_count);
		say qq(<li>Isolates: $commified</li>);
		say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . q(page=fieldValues">Defined field values</a></li>);
	}
	my $max_date = $self->get_last_update;
	say qq(<li>Last updated: $max_date</li>) if $max_date;
			my $history_table = $self->{'system'}->{'dbtype'} eq 'isolates' ? 'history' : 'profile_history';
		my $history_exists = $self->{'datastore'}->run_query("SELECT EXISTS(SELECT * FROM $history_table)");
		say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;)
		  . qq(table=$history_table&amp;order=timestamp&amp;direction=descending&amp;submit=1$cache_string">)
		  . ( $self->{'system'}->{'dbtype'} eq 'sequences' ? 'Profile u' : 'U' )
		  . q(pdate history</a></li>)
		  if $history_exists;
	say q(</ul>);
	say q(</div>);
	return;
}

sub get_last_update {
	my ($self) = @_;
	my $tables =
	  $self->{'system'}->{'dbtype'} eq 'sequences'
	  ? [qw (locus_stats profiles profile_refs accession)]
	  : [qw (isolates isolate_aliases allele_designations allele_sequences refs)];
	my $max_date = $self->_get_max_date($tables);
	return $max_date;
}

sub _get_max_date {
	my ( $self, $tables ) = @_;
	local $" = ' UNION SELECT MAX(datestamp) FROM ';
	my $qry      = "SELECT MAX(max_datestamp) FROM (SELECT MAX(datestamp) AS max_datestamp FROM @$tables) AS v";
	my $max_date = $self->{'datastore'}->run_query($qry);
	return $max_date;
}

sub _get_allele_count {
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? ' WHERE locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE '
	  . "set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id)"
	  : q();
	return $self->{'datastore'}->run_query("SELECT SUM(allele_count) FROM locus_stats$set_clause") // 0;
}
1;
