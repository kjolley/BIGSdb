#Written by Keith Jolley
#Copyright (c) 2010-2015, University of Oxford
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
package BIGSdb::DownloadProfilesPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{'type'}   = 'text';
	$self->{'jQuery'} = 1;
	return;
}

sub print_content {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	my $set_id    = $self->get_set_id;
	if ( !$scheme_id ) {
		say "No scheme id passed.";
		return;
	} elsif ( !BIGSdb::Utils::is_int($scheme_id) ) {
		say "Scheme id must be an integer.";
		return;
	} elsif ( $set_id && !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id ) ) {
		say "Scheme $scheme_id is not available.";
		return;
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	if ( !$scheme_info ) {
		say "Scheme does not exist.";
		return;
	}
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $primary_key   = $scheme_info->{'primary_key'};
	if ( !$primary_key ) {
		say "This scheme has no primary key set.";
		return;
	}
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	print "$primary_key";
	my @fields = ($primary_key);
	foreach my $locus (@$loci) {
		print "\t";
		my $locus_info = $self->{'datastore'}->get_locus_info( $locus, { set_id => $set_id } );
		my $header_value = $locus_info->{'set_name'} // $locus;
		print $header_value;
		( my $cleaned = $locus ) =~ s/'/_PRIME_/g;
		push @fields, $cleaned;
	}
	foreach my $field (@$scheme_fields) {
		next if $field eq $primary_key;
		print "\t$field";
		push @fields, $field;
	}
	print "\n";
	local $" = ',';
	my $scheme_view = $self->{'datastore'}->materialized_view_exists($scheme_id) ? "mv_scheme_$scheme_id" : "scheme_$scheme_id";
	my $pk_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	my $qry =
	  "SELECT @fields FROM $scheme_view ORDER BY " . ( $pk_info->{'type'} eq 'integer' ? "CAST($primary_key AS int)" : $primary_key );
	my $data = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref' } );
	local $" = "\t";
	{
		no warnings 'uninitialized';    #scheme field values may be undefined
		foreach my $profile (@$data) {
			say "@$profile";
		}
	}
	return;
}
1;
