#Written by Keith Jolley
#Copyright (c) 2014-2019, University of Oxford
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
package BIGSdb::REST::Routes::AlleleDesignations;
use strict;
use warnings;
use 5.010;
use Dancer2 appname => 'BIGSdb::REST::Interface';

#Allele designation routes
sub setup_routes {
	my $self = setting('self');
	foreach my $dir ( @{ setting('api_dirs') } ) {
		get "$dir/db/:db/isolates/:id/allele_designations"        => sub { _get_allele_designations() };
		get "$dir/db/:db/isolates/:id/allele_designations/:locus" => sub { _get_allele_designation() };
		get "$dir/db/:db/isolates/:id/allele_ids"                 => sub { _get_allele_ids() };
		get "$dir/db/:db/isolates/:id/schemes/:scheme/allele_ids" => sub { _get_scheme_allele_ids() };
		get "$dir/db/:db/isolates/:id/schemes/:scheme/allele_designations" =>
		  sub { _get_scheme_allele_designations() };
	}
	return;
}

sub _get_allele_designations {
	my $self = setting('self');
	my ( $db, $isolate_id ) = ( params->{'db'}, params->{'id'} );
	my $subdir          = setting('subdir');
	$self->check_isolate_is_valid($isolate_id);
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? ' AND (locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes '
	  . "WHERE set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';
	my $designation_count =
	  $self->{'datastore'}
	  ->run_query( "SELECT COUNT(DISTINCT locus) FROM allele_designations WHERE isolate_id=?$set_clause", $isolate_id );
	my $values = { records => int($designation_count) };
	my $page_values = $self->get_page_values($designation_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};
	my $qry = "SELECT DISTINCT locus FROM allele_designations WHERE isolate_id=?$set_clause ORDER BY locus";
	$qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !param('return_all');
	my $loci = $self->{'datastore'}->run_query( $qry, $isolate_id, { fetch => 'col_arrayref' } );
	my $paging = $self->get_paging( "$subdir/db/$db/isolates/$isolate_id/allele_designations", $pages, $page, $offset );
	$values->{'paging'} = $paging if %$paging;
	my $designation_links = [];

	foreach my $locus (@$loci) {
		my $locus_name = $self->clean_locus($locus);
		push @$designation_links, request->uri_for("$subdir/db/$db/isolates/$isolate_id/allele_designations/$locus_name");
	}
	$values->{'allele_designations'} = $designation_links;
	return $values;
}

sub _get_allele_designation {
	my $self = setting('self');
	my ( $db, $isolate_id, $locus ) = ( params->{'db'}, params->{'id'}, params->{'locus'} );
	$self->check_isolate_is_valid($isolate_id);
	my $subdir          = setting('subdir');
	my $set_id     = $self->get_set_id;
	my $locus_name = $locus;
	if ($set_id) {
		$locus_name = $self->{'datastore'}->get_set_locus_real_id( $locus, $set_id );
	}
	if ( !$self->{'datastore'}->is_locus($locus_name)
		|| ( $set_id && !$self->{'datastore'}->is_locus_in_set( $locus_name, $set_id ) ) )
	{
		send_error( "Locus $locus does not exist.", 404 );
	}
	my $values = [];
	my $designations = $self->{'datastore'}->get_allele_designations( $isolate_id, $locus_name );
	if ( !@$designations ) {
		send_error( "Isolate $isolate_id has no designations defined for locus $locus.", 404 );
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus_name);
	foreach my $designation (@$designations) {
		my $returned_designation = {};
		foreach my $attribute (qw(locus allele_id status method comments sender curator datestamp)) {
			next if !defined $designation->{$attribute} || $designation->{$attribute} eq '';
			if ( $attribute eq 'locus' ) {
				$returned_designation->{'locus'} = request->uri_for("$subdir/db/$db/loci/$locus");
			} elsif ( $attribute eq 'allele_id' ) {
				$returned_designation->{'allele_id'} =
				  $locus_info->{'allele_id_format'} eq 'integer'
				  ? int( $designation->{'allele_id'} )
				  : $designation->{'allele_id'};
			} elsif ( $attribute eq 'sender' || $attribute eq 'curator' ) {
				$returned_designation->{$attribute} = request->uri_for("$subdir/db/$db/users/$designation->{$attribute}");
			} else {
				$returned_designation->{$attribute} = $designation->{$attribute};
			}
		}
		push @$values, $returned_designation;
	}
	return $values;
}

sub _get_allele_ids {
	my $self = setting('self');
	my ( $db, $isolate_id ) = ( params->{'db'}, params->{'id'} );
	$self->check_isolate_is_valid($isolate_id);
	my $subdir          = setting('subdir');
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? ' AND (locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes '
	  . "WHERE set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';
	my $allele_count =
	  $self->{'datastore'}
	  ->run_query( "SELECT COUNT(DISTINCT locus) FROM allele_designations WHERE isolate_id=?$set_clause", $isolate_id );
	my $values = { records => int($allele_count) };
	my $page_values = $self->get_page_values($allele_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};
	my $qry = "SELECT DISTINCT locus FROM allele_designations WHERE isolate_id=?$set_clause ORDER BY locus";
	$qry .= " OFFSET $offset LIMIT $self->{'page_size'}" if !param('return_all');
	my $loci = $self->{'datastore'}->run_query( $qry, $isolate_id, { fetch => 'col_arrayref' } );
	my $paging = $self->get_paging( "$subdir/db/$db/isolates/$isolate_id/allele_ids", $pages, $page, $offset );
	$values->{'paging'} = $paging if %$paging;
	my $designations = [];

	foreach my $locus (@$loci) {
		my $locus_name = $self->clean_locus($locus);
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		my $allele_ids = $self->{'datastore'}->get_allele_ids( $isolate_id, $locus );
		if ( @$allele_ids == 1 ) {
			push @$designations,
			  {
				$locus_name => $locus_info->{'allele_id_format'} eq 'integer'
				? int( $allele_ids->[0] )
				: $allele_ids->[0]
			  };
		} else {
			if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
				my @int_allele_ids;
				push @int_allele_ids, int($_) foreach @$allele_ids;
				push @$designations, { $locus_name => \@int_allele_ids };
			} else {
				push @$designations, { $locus_name => $allele_ids };
			}
		}
	}
	$values->{'allele_ids'} = $designations;
	return $values;
}

sub _get_scheme_allele_ids {
	my $self = setting('self');
	my ( $db, $isolate_id, $scheme_id ) = ( params->{'db'}, params->{'id'}, params->{'scheme'} );
	$self->check_isolate_is_valid($isolate_id);
	$self->check_scheme($scheme_id);
	my $set_id = $self->get_set_id;
	my $allele_designations =
	  $self->{'datastore'}->get_scheme_allele_designations( $isolate_id, $scheme_id, { set_id => $set_id } );
	my $values       = { records => int( keys %$allele_designations ) };
	my $loci         = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $designations = [];

	foreach my $locus (@$loci) {
		my $locus_name = $self->clean_locus($locus);
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		my $allele_ids = $self->{'datastore'}->get_allele_ids( $isolate_id, $locus );
		next if !@$allele_ids;
		if ( @$allele_ids == 1 ) {
			push @$designations,
			  {
				$locus_name => $locus_info->{'allele_id_format'} eq 'integer'
				? int( $allele_ids->[0] )
				: $allele_ids->[0]
			  };
		} else {
			if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
				my @int_allele_ids;
				push @int_allele_ids, int($_) foreach @$allele_ids;
				push @$designations, { $locus_name => \@int_allele_ids };
			} else {
				push @$designations, { $locus_name => $allele_ids };
			}
		}
	}
	$values->{'allele_ids'} = $designations;
	return $values;
}

sub _get_scheme_allele_designations {
	my $self = setting('self');
	my ( $db, $isolate_id, $scheme_id ) = ( params->{'db'}, params->{'id'}, params->{'scheme'} );
	$self->check_isolate_is_valid($isolate_id);
	$self->check_scheme($scheme_id);
	my $set_id = $self->get_set_id;
	my $subdir          = setting('subdir');
	my $allele_designations =
	  $self->{'datastore'}->get_scheme_allele_designations( $isolate_id, $scheme_id, { set_id => $set_id } );
	my $values       = { records => int( keys %$allele_designations ) };
	my $loci         = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $designations = [];

	foreach my $locus (@$loci) {
		next if !$allele_designations->{$locus};
		my $locus_info   = $self->{'datastore'}->get_locus_info($locus);
		my $locus_values = [];
		my $locus_name   = $self->clean_locus($locus);
		foreach my $designation ( @{ $allele_designations->{$locus} } ) {
			my $value = {};
			foreach my $field (qw ( locus allele_id sender status method curator date_entered datestamp)) {
				if ( $field eq 'locus' ) {
					$value->{'locus'} = request->uri_for("$subdir/db/$db/loci/$locus_name");
				} elsif ( $field eq 'allele_id'
					&& $locus_info->{'allele_id_format'} eq 'integer'
					&& BIGSdb::Utils::is_int( $designation->{'allele_id'} ) )
				{
					$value->{'allele_id'} = int( $designation->{'allele_id'} );
				} elsif ( $field eq 'sender' || $field eq 'curator' ) {
					$value->{$field} = request->uri_for("$subdir/db/$db/users/$designation->{$field}");
				} else {
					$value->{$field} = $designation->{$field} if defined $designation->{$field};
				}
			}
			push @$locus_values, $value;
		}
		push @$designations, { $locus_name => $locus_values };
	}
	$values->{'allele_designations'} = $designations;
	return $values;
}
1;
