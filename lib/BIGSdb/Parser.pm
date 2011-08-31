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
use XML::Parser::PerlSAX;
use List::MoreUtils qw(any);

my ( $_in_system, $_in_field, $_in_sample, $_in_optlist, $fieldname, $samplename );
my (@fields, @sample_fields);
my ( %system,     %these );
my ( %attributes, %sample_attributes, %options );

sub get_system_hash { return \%system }
sub get_field_list  { return \@fields }
sub get_sample_field_list { return \@sample_fields}

sub get_all_field_attributes {
	return \%attributes;
}

sub get_field_attributes {
	my ( $self, $name ) = @_;
	if ( $attributes{$name} ) {
		return %{ $attributes{$name} };
	}
	return %;
}

sub get_sample_field_attributes {
	my ( $self, $name ) = @_;
	if ( $sample_attributes{$name} ) {
		return %{ $sample_attributes{$name} };
	}
	return %;
}

sub is_field {
	my ( $self, $field ) = @_;
	$field ||= '';
	return any {$_ eq $field} @fields;
}

sub get_field_option_list {
	my ( $self, $name ) = @_;
	if ( $options{$name} ) {
		return @{ $options{$name} };
	}
	return @;
}

sub get_order_by {
	my ($self) = @_;
	my @orderby;
	foreach (@fields) {
		my %thisfield = %{ $attributes{$_} };
		push @orderby, $_;
	}
	return \@orderby;
}

sub get_select_items {
	my ( $self, $args ) = @_;
	my @selectitems;
	if ( $args =~ /includeGroupedFields/ ) {
		for ( my $i = 1 ; $i < 11 ; $i++ ) {
			if ( $system{"fieldgroup$i"} ) {
				my $group = ( split /:/, $system{"fieldgroup$i"} )[0];
				push @selectitems, $group;
			}
		}
	}
	foreach (@fields) {
		my %thisfield = %{ $attributes{$_} };
		$_ = 'ST' if $_ eq 'st';
		if (
			( $args !~ /userFieldIdsOnly/ )
			&& (   $_ eq 'sender'
				|| $_ eq 'curator'
				|| ( $thisfield{'userfield'} && $thisfield{'userfield'} eq 'yes' ) )
		  )
		{
			push @selectitems, "$_ (id)";
			push @selectitems, "$_ (surname)";
			push @selectitems, "$_ (first_name)";
			push @selectitems, "$_ (affiliation)";
		} else {
			push @selectitems, $_;
		}
	}
	return @selectitems;
}

sub get_grouped_fields {
	my ($self) = @_;
	my @list;
	for ( my $i = 1 ; $i < 11 ; $i++ ) {
		if ( $system{"fieldgroup$i"} ) {
			my $group = ( split /:/, $system{"fieldgroup$i"} )[0];
			push @list, $group;
		}
	}
	return \@list;
}

sub new {
	my ($class) = @_;
	return bless {}, $class;
}

sub characters {
	my ( $self, $element ) = @_;
	chomp( $element->{'Data'} );
	$element->{'Data'} =~ s/^\s*//;
	if ($_in_system) {
		undef @fields;    #needed under mod_perl to prevent list growing with each invocation
		undef @sample_fields;
	} elsif ($_in_field) {
		$fieldname = $element->{'Data'};
		push @fields, $fieldname;
		%{ $attributes{$fieldname} } = %these;
		$_in_field = 0;
	} elsif ( $_in_optlist ) {
		push @{ $options{$fieldname} }, $element->{'Data'} if $element->{'Data'} ne '';
	} elsif ( $_in_sample) {
		$fieldname = $element->{'Data'};
		push @sample_fields, $fieldname;
		%{ $sample_attributes{$fieldname} } = %these;
		$_in_sample = 0;
	}
}

sub start_element {
	my ( $self, $element ) = @_;
	if ( $element->{'Name'} eq 'system' ) {
		$_in_system = 1;
		%system     = %{ $element->{'Attributes'} };
	} elsif ( $element->{'Name'} eq 'field' ) {
		$_in_field = 1;
		%these     = %{ $element->{'Attributes'} };
	} elsif ( $element->{'Name'} eq 'optlist' ) {
		$_in_optlist = 1;
		undef @{ $options{$fieldname} };

		#needed under mod_perl to prevent list growing with each invocation
	} elsif ( $element->{'Name'} eq 'sample' ) {
		$_in_sample = 1;
		%these     = %{ $element->{'Attributes'} };
	}
}

sub end_element {
	my ( $self, $element ) = @_;
	if ($element->{'Name'} eq 'system'){
		$_in_system  = 0;
	} elsif ($element->{'Name'} eq 'field'){
		$_in_field   = 0;
	} elsif ($element->{'Name'} eq 'optlist'){
		$_in_optlist = 0
	} elsif ($element->{'Name'} eq 'sample'){
		$_in_sample = 0
	}
}
1;
