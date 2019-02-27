#Written by Keith Jolley
#Copyright (c) 2018-2019, University of Oxford
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
package BIGSdb::REST::Routes::Sequences;
use strict;
use warnings;
use 5.010;
use JSON;
use Dancer2 appname => 'BIGSdb::REST::Interface';
get '/db/:db/sequences'                         => sub { _get_sequences() };
get '/db/:db/sequences/fields'                  => sub { _get_fields() };
get '/db/:db/sequences/fields/:field/breakdown' => sub { _get_fields_breakdown() };

sub _get_sequences {
	my $self = setting('self');
	my ($db) = params->{'db'};
	$self->check_seqdef_database;
	my $values = { loci => request->uri_for("/db/$db/loci") };
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? ' AND (locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes '
	  . "WHERE set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';
	if ( params->{'added_after'} || params->{'updated_after'} || params->{'added_on'} || params->{'updated_on'} ) {
		my $allowed_filters = [qw(added_after added_on updated_after updated_on)];
		my $qry             = $self->add_filters(
			'SELECT COUNT(*),MAX(date_entered),MAX(datestamp) FROM sequences WHERE '
			  . "allele_id NOT IN ('0','N')$set_clause",
			$allowed_filters
		);
		my ( $count, $last_added, $last_updated ) = $self->{'datastore'}->run_query($qry);
		$values->{'records'}      = int($count);
		$values->{'last_added'}   = $last_added if $last_added;
		$values->{'last_updated'} = $last_updated if $last_updated;
	} else {
		$set_clause =~ s/^\sAND/ WHERE/x;
		#This is more efficient if we don't need to filter.
		my ( $count, $last_updated ) =
		  $self->{'datastore'}->run_query("SELECT SUM(allele_count),MAX(datestamp) FROM locus_stats$set_clause");
		$values->{'records'}      = int($count);
		$values->{'last_updated'} = $last_updated if $last_updated;
		$values->{'fields'}       = request->uri_for("/db/$db/sequences/fields");
	}
	return $values;
}

sub _get_fields {
	my $self = setting('self');
	my ($db) = params->{'db'};
	$self->check_seqdef_database;
	return [
		{
			name      => 'date_entered',
			required  => JSON::true,
			breakdown => request->uri_for("/db/$db/sequences/fields/date_entered/breakdown")
		},
		{
			name      => 'datestamp',
			required  => JSON::true,
			breakdown => request->uri_for("/db/$db/sequences/fields/datestamp/breakdown")
		}
	];
}

sub _get_fields_breakdown {
	my $self   = setting('self');
	my $params = params;
	my ( $db, $field ) = @{$params}{qw(db field)};
	$self->check_seqdef_database;
	my %allowed = map { $_ => 1 } qw(date_entered datestamp);
	if ( !$allowed{$field} ) {
		send_error( 'Invalid field selected', 400 );
	}
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? qq[ AND (locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id) OR ]
	  . q[locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN ]
	  . qq[(SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)))]
	  : q();
	my $qry = "SELECT $field,COUNT(*) AS count FROM sequences WHERE $field IS NOT NULL AND allele_id "
	  . "NOT IN ('0','N')$set_clause GROUP BY $field";
	my $value_counts =
	  $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	my %values = map { $_->{$field} => $_->{'count'} } @$value_counts;
	return \%values;
}
1;
