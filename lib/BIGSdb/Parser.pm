#Parser.pm
#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
#E-mail: keith.jolley@zoo.ox.ac.uk
#
#This file is part of Bacterial Isolate Genome Sequence Database (BIGSdb).
#
#Parser.pm makes use of XML Parser code from the
#mlstdb package written by Man-Suen Chan.
#(c) 2001 Man-Suen Chan and University of Oxford
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
##############XML Parser################################
#Code modified from original mlstdb, written by
#Man-Suen Chan, (c) 2001 M-S Chan & University of Oxford
#Included and released under GPLv3 by permission.
########################################################
package BIGSdb::Parser;
use strict;
use warnings;
use 5.010;
use XML::Parser::PerlSAX;
use List::MoreUtils qw(any);

sub get_system_hash {
	my ($self) = @_;
	return $self->{'system'};
}

sub get_field_list {
	my ($self, $metadata_arrayref) = @_;
	$metadata_arrayref = [] if ref $metadata_arrayref ne 'ARRAY';
	my @fields;
	foreach my $field (@{$self->{'fields'}}){
		if ($field =~ /^(meta_[^:]+):.+/){
			foreach my $metadata (@$metadata_arrayref){
				push @fields, $field if $metadata eq $1;
			}
		} else {
			push @fields, $field;
		}
	}
	return \@fields;
}

sub get_sample_field_list {
	my ($self) = @_;
	return $self->{'sample_fields'};
}

sub get_all_field_attributes {
	my ($self) = @_;
	return $self->{'attributes'};
}

sub get_field_attributes {
	my ( $self, $name ) = @_;
	return $self->{'attributes'}->{$name} // {};
}

sub get_sample_field_attributes {
	my ( $self, $name ) = @_;
	return $self->{'sample_attributes'}->{$name} // {};
}

sub is_field {
	my ( $self, $field ) = @_;
	$field ||= '';
	return any { $_ eq $field } @{ $self->{'fields'} };
}

sub get_field_option_list {
	my ( $self, $name ) = @_;
	return $self->{'options'}->{$name} // [];
}

sub get_grouped_fields {
	my ($self) = @_;
	my @list;
	for my $i ( 1 .. 10 ) {
		if ( $self->{'system'}->{"fieldgroup$i"} ) {
			my $group = ( split /:/, $self->{'system'}->{"fieldgroup$i"} )[0];
			push @list, $group;
		}
	}
	return \@list;
}

sub new {    ##no critic
	my $class = shift;
	my $self  = {@_};
	bless( $self, $class );
	$self->{'fields'}        = [];
	$self->{'system'}        = {};
	$self->{'sample_fields'} = [];
	return $self;
}

sub characters {
	my ( $self, $element ) = @_;
	chomp( $element->{'Data'} );
	$element->{'Data'} =~ s/^\s*//;
	if ( $self->{'_in_system'} ) {
	} elsif ( $self->{'_in_field'} ) {
		$self->{'field_name'} = $element->{'Data'};
		push @{ $self->{'fields'} }, $self->{'field_name'};
		$self->{'attributes'}->{ $self->{'field_name'} } = $self->{'these'};
		$self->{'_in_field'} = 0;
	} elsif ( $self->{'_in_optlist'} ) {
		push @{ $self->{'options'}->{ $self->{'field_name'} } }, $element->{'Data'} if $element->{'Data'} ne '';
	} elsif ( $self->{'_in_sample'} ) {
		$self->{'field_name'} = $element->{'Data'};
		push @{ $self->{'sample_fields'} }, $self->{'field_name'};
		$self->{'sample_attributes'}->{ $self->{'field_name'} } = $self->{'these'};
		$self->{'_in_sample'} = 0;
	}
	return;
}

sub start_element {
	my ( $self, $element ) = @_;
	given ( $element->{'Name'} ) {
		when ('system') { $self->{'_in_system'} = 1; $self->{'system'} = $element->{'Attributes'} }
		when ('field')  { $self->{'_in_field'}  = 1; $self->{'these'}  = $element->{'Attributes'} }
		when ('optlist') { $self->{'_in_optlist'} = 1 }
		when ('sample') { $self->{'_in_sample'} = 1; $self->{'these'} = $element->{'Attributes'} }
	}
	return;
}

sub end_element {
	my ( $self, $element ) = @_;
	given ( $element->{'Name'} ) {
		when ('system')  { $self->{'_in_system'}  = 0 }
		when ('field')   { $self->{'_in_field'}   = 0 }
		when ('optlist') { $self->{'_in_optlist'} = 0 }
		when ('sample')  { $self->{'_in_sample'}  = 0 }
	}
	return;
}

sub get_metadata_list {
	my ($self) = @_;
	my %list;
	foreach my $field (@{$self->{'fields'}}){
		$list{$1} = 1 if $field =~ /^(meta_[^:]+):/;
	}
	my @list = sort keys %list;
	return \@list;
}
1;
