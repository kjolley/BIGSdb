#Parser.pm
#Written by Keith Jolley
#Copyright (c) 2010-2019, University of Oxford
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
use BIGSdb::Utils;
use BIGSdb::Constants qw(COUNTRIES);
use XML::Parser::PerlSAX;
use Unicode::Collate;
use List::MoreUtils qw(any);

sub get_system_hash {
	my ($self) = @_;
	return $self->{'system'};
}

sub get_field_list {
	my ( $self, $metadata_arrayref, $options ) = @_;
	$options           = {} if ref $options ne 'HASH';
	$metadata_arrayref = [] if ref $metadata_arrayref ne 'ARRAY';
	my @fields;
	foreach my $field ( @{ $self->{'fields'} } ) {
		if ( $field =~ /^(meta_[^:]+):.+/x ) {
			foreach my $metadata (@$metadata_arrayref) {
				push @fields, $field if $metadata eq $1;
			}
		} else {
			next if $options->{'meta_fields_only'};
			next
			  if $options->{'no_curate_only'}
			  && ( $self->{'attributes'}->{$field}->{'curate_only'} // q() ) eq 'yes';
			push @fields, $field;
		}
	}
	return \@fields;
}



sub get_all_field_attributes {
	my ($self) = @_;
	return $self->{'attributes'};
}

sub get_field_attributes {
	my ( $self, $name ) = @_;
	return $self->{'attributes'}->{$name} // { type => q(), required => q() };
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
			my $group = ( split /:/x, $self->{'system'}->{"fieldgroup$i"} )[0];
			push @list, $group;
		}
	}
	return \@list;
}

sub new {    ## no critic (RequireArgUnpacking)
	my $class = shift;
	my $self  = {@_};
	bless( $self, $class );
	$self->{'fields'}        = [];
	$self->{'system'}        = {};
	return $self;
}

sub characters {
	my ( $self, $element ) = @_;
	chomp( $element->{'Data'} );
	$element->{'Data'} =~ s/^\s*//x;
	if ( $self->{'_in_field'} ) {
		$self->{'field_name'} = $element->{'Data'};
		push @{ $self->{'fields'} }, $self->{'field_name'};
		$self->_process_special_values( $self->{'these'} );
		$self->{'attributes'}->{ $self->{'field_name'} } = $self->{'these'};
		if ( ( $self->{'these'}->{'optlist'} // q() ) eq 'yes' && $self->{'these'}->{'values'} ) {
			$self->_add_special_optlist_values( $self->{'field_name'}, $self->{'these'}->{'values'} );
		}
		$self->{'_in_field'} = 0;
	} elsif ( $self->{'_in_optlist'} ) {
		push @{ $self->{'options'}->{ $self->{'field_name'} } }, $element->{'Data'} if $element->{'Data'} ne '';
	}
	return;
}

sub start_element {
	my ( $self, $element ) = @_;
	my %methods = (
		system => sub { $self->{'_in_system'} = 1; $self->{'system'} = $element->{'Attributes'} },
		field => sub {
			$self->{'_in_field'} = 1;
			$self->{'these'}     = $element->{'Attributes'};
		},
		optlist => sub {
			$self->{'_in_optlist'} = 1;
		}
	);
	$methods{ $element->{'Name'} }->() if $methods{ $element->{'Name'} };
	return;
}

sub _add_special_optlist_values {
	my ( $self, $field_name, $value_name ) = @_;
	if ( $value_name eq 'COUNTRIES' ) {
		my $countries = COUNTRIES;
		my $values    = [ keys %$countries ];
		$self->{'options'}->{$field_name} = $self->_dictionary_sort($values);
	}
	return;
}

sub _dictionary_sort {
	my ( $self, $values ) = @_;
	my $collator = Unicode::Collate->new;
	my $sort_key = {};
	for my $value (@$values) {
		$sort_key->{$value} = $collator->getSortKey($value);
	}
	my @sorted = sort { $sort_key->{$a} cmp $sort_key->{$b} } @$values;
	return \@sorted;
}

sub end_element {
	my ( $self, $element ) = @_;
	my %methods = (
		system => sub { $self->{'_in_system'} = 0 },
		field  => sub { $self->{'_in_field'}  = 0 },
		optlist => sub {
			$self->{'_in_optlist'} = 0;
			if ( ( $self->{'attributes'}->{ $self->{'field_name'} }->{'sort'} // q() ) eq 'yes' ) {
				$self->{'options'}->{ $self->{'field_name'} } =
				  $self->_dictionary_sort( $self->{'options'}->{ $self->{'field_name'} } );
			}
		}
	);
	$methods{ $element->{'Name'} }->() if $methods{ $element->{'Name'} };
	return;
}

sub _process_special_values {
	my ( $self, $attributes ) = @_;
	foreach my $value ( values %$attributes ) {
		if ( $value eq 'CURRENT_YEAR' ) {
			$value = (localtime)[5] + 1900;
		}
		if ( $value eq 'CURRENT_DATE' ) {
			$value = BIGSdb::Utils::get_datestamp();
		}
	}
	return;
}

sub get_metadata_list {
	my ($self) = @_;
	my %list;
	foreach my $field ( @{ $self->{'fields'} } ) {
		$list{$1} = 1 if $field =~ /^(meta_[^:]+):/x;
	}
	my @list = sort keys %list;
	return \@list;
}
1;
