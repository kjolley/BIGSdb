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
package BIGSdb::DownloadProfilesPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use List::MoreUtils qw(uniq);
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
		say q(No scheme id passed.);
		return;
	} elsif ( !BIGSdb::Utils::is_int($scheme_id) ) {
		say q(Scheme id must be an integer.);
		return;
	} elsif ( $set_id && !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id ) ) {
		say qq(Scheme $scheme_id is not available.);
		return;
	}
	$scheme_id =~ s/^0*//x;    #In case scheme_id has preceeding zeros.
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	if ( !$scheme_info ) {
		say q(Scheme does not exist.);
		return;
	}
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $primary_key   = $scheme_info->{'primary_key'};
	if ( !$primary_key ) {
		say q(This scheme has no primary key set.);
		return;
	}
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	print $primary_key;
	my @fields = ( $primary_key, 'profile' );
	my $locus_indices = $self->{'datastore'}->get_scheme_locus_indices($scheme_id);
	my @order;
	foreach my $locus (@$loci) {
		my $locus_info = $self->{'datastore'}->get_locus_info( $locus, { set_id => $set_id } );
		my $header_value = $locus_info->{'set_name'} // $locus;
		print qq(\t$header_value);
		push @order, $locus_indices->{$locus};
	}
	foreach my $field (@$scheme_fields) {
		next if $field eq $primary_key;
		print qq(\t$field);
		push @fields, $field;
	}
	print qq(\n);
	local $" = q(,);
	my $scheme_warehouse = qq(mv_scheme_$scheme_id);
	my $pk_info          = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	my $qry              = "SELECT @fields FROM $scheme_warehouse ORDER BY "
	  . ( $pk_info->{'type'} eq 'integer' ? "CAST($primary_key AS int)" : $primary_key );
	my $data = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref' } );
	local $" = qq(\t);
	{
		no warnings 'uninitialized';    #scheme field values may be undefined
		foreach my $definition (@$data) {
			my $pk      = shift @$definition;
			my $profile = shift @$definition;
			say qq($pk\t@$profile[@order]\t@$definition);
		}
	}
	return;
}
1;
