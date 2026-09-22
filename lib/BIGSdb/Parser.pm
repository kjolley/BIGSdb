#Parser.pm
#Written by Keith Jolley
#Copyright (c) 2010-2026, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
use List::MoreUtils qw(any);
use Log::Log4perl   qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_system_hash {
	my ($self) = @_;
	return $self->{'system'};
}

sub get_field_list {
	my ( $self, $options ) = @_;
	my @fields;
	foreach my $field ( @{ $self->{'fields'} } ) {
		next
		  if $options->{'no_curate_only'}
		  && ( $self->{'attributes'}->{$field}->{'curate_only'} // q() ) eq 'yes';
		next
		  if $options->{'multivalue_only'}
		  && ( $self->{'attributes'}->{$field}->{'multiple'} // q() ) ne 'yes';
		next if !$options->{'show_hidden'} && ( $self->{'attributes'}->{$field}->{'hide'} // q() ) eq 'yes';
		push @fields, $field;
	}
	return \@fields;
}

sub get_all_field_attributes {
	my ($self) = @_;
	$self->_set_prefix_fields;
	return $self->{'attributes'};
}

sub get_field_attributes {
	my ( $self, $name ) = @_;
	$self->_set_prefix_fields;
	return $self->{'attributes'}->{$name} // { type => q(), required => q() };
}

sub _set_prefix_fields {
	my ($self) = @_;
	return if $self->{'prefixes_already_defined'};
	my $atts = $self->{'attributes'};
	foreach my $field ( keys %$atts ) {
		next if !$atts->{$field}->{'prefixes'};
		if ( defined $atts->{ $atts->{$field}->{'prefixes'} } ) {
			$atts->{ $atts->{$field}->{'prefixes'} }->{'prefixed_by'} = $field;
			if ( defined $atts->{$field}->{'separator'} ) {
				$atts->{ $atts->{$field}->{'prefixes'} }->{'prefix_separator'} =
				  $atts->{$field}->{'separator'};
			}
		} else {
			$logger->error("Field $field prefixes $atts->{$field}->{'prefixes'} but this is not defined.");
		}
	}
	$self->{'prefixes_already_defined'} = 1;
	return;
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
	$self->{'fields'} = [];
	$self->{'system'} = {};
	return $self;
}

sub characters {
	my ( $self, $element ) = @_;
	return unless defined $element->{'Data'};

	# normalize whitespace
	my $data = $element->{'Data'};
	$data =~ s/\r?\n/ /gx;
	$data =~ s/\s+/ /gx;
	$data =~ s/^\s+|\s+$//gx;
	return unless length $data;
	my $stack = $self->{'_field_stack'} // [];
	my $ctx   = @$stack ? $stack->[-1] : undef;

	if ( $self->{'_in_option'} ) {
		$self->{'_option_buffer'} .= $data;
		return;
	}
	if ( $self->{'_in_field'} && !$self->{'_in_optlist'} && !$self->{'_in_option'} ) {
		if ($ctx) {
			$ctx->{'char_buffer'} .= $data;
		} else {
			$self->{'_char_buffer'} .= $data;
		}
		return;
	}

	# if inside optlist but not option, ignore
	return;
}

sub start_element {
	my ( $self, $element ) = @_;

	$self->{'_field_stack'} ||= [];

	my %methods = (
		system => sub { $self->{'_in_system'} = 1; $self->{'system'} = $element->{'Attributes'} },
		field  => sub {
			$self->{'_in_field'} = 1;
			my $ctx = {
				these       => $element->{'Attributes'} || {},
				char_buffer => '',
				options     => [],
			};
			push @{ $self->{_field_stack} }, $ctx;
		},
		optlist => sub {
			$self->{'_in_optlist'} = 1;
		},
		option => sub {
			$self->{'_in_option'}         = 1;
			$self->{'_option_buffer'}     = '';
			$self->{'_option_attributes'} = $element->{'Attributes'} || {};
		},
	);
	$methods{ $element->{'Name'} }->() if $methods{ $element->{'Name'} };
	return;
}

sub _get_attribute_value {
	my ( $self, $attributes, $name ) = @_;
	return if !exists $attributes->{$name};
	return ref $attributes->{$name} eq 'HASH'
	  ? ( $attributes->{$name}{'Value'} // $attributes->{$name}{'value'} )
	  : $attributes->{$name};
}

sub _get_explicit_options {
	my ( $self, $options, $sort ) = @_;
	my ( @sortable, @unsorted );
	my %seen;
	for my $option (@$options) {
		my $value = $option->{'value'};
		next if !defined $value;
		$value =~ s/^\s+|\s+$//gx;
		next if !length $value || $seen{$value}++;
		if ( $sort eq 'yes' && ( $option->{'sort'} // q() ) eq 'no' ) {
			push @unsorted, $value;
		} else {
			push @sortable, $value;
		}
	}
	if ( $sort eq 'yes' ) {
		@sortable = @{ BIGSdb::Utils::unicode_dictionary_sort( \@sortable ) };
	}
	return ( \@sortable, \@unsorted );
}

sub _add_special_optlist_values {
	my ( $self, $field_name, $value_name ) = @_;
	if ( $value_name eq 'COUNTRIES' ) {
		my $countries = COUNTRIES;
		my $values    = [ keys %$countries ];
		$self->{'options'}->{$field_name} = BIGSdb::Utils::unicode_dictionary_sort($values);
	}
	return;
}

sub end_element {
	my ( $self, $element ) = @_;
	my %methods = (
		system => sub { $self->{'_in_system'} = 0 },
		option => sub {
			$self->{'_in_option'} = 0;

			my $opt   = $self->{'_option_buffer'} // q();
			my $attrs = $self->{'_option_attributes'} || {};
			my $value = $self->_get_attribute_value( $attrs, 'value' );
			$opt = $value if defined $value;
			$opt =~ s/^\s+|\s+$//gx;
			if ( length $opt ) {
				my $sort   = $self->_get_attribute_value( $attrs, 'sort' );
				my $option = {
					value => $opt,
					defined $sort ? ( sort => $sort ) : (),
				};
				if ( $self->{'_field_stack'} && @{ $self->{'_field_stack'} } ) {
					push @{ $self->{'_field_stack'}->[-1]{'options'} }, $option;
				} else {
					push @{ $self->{'options'}{ $self->{'field_name'} // '_unknown' } }, $opt;
				}
			}
			delete $self->{'_option_buffer'};
			delete $self->{'_option_attributes'};
		},
		optlist => sub {
			$self->{'_in_optlist'} = 0;

			# do nothing; commit at field end
		},
		field => sub {
			$self->{'_in_field'} = 0;
			my $ctx;
			$ctx = pop @{ $self->{_field_stack} } if $self->{'_field_stack'} && @{ $self->{'_field_stack'} };
			unless ($ctx) {
				$ctx = {
					these       => $self->{'these'} || {},
					char_buffer => $self->{'_char_buffer'} // q(),
					options     => $self->{'_options_temp'} ? [ @{ $self->{'_options_temp'} } ] : [],
				};
			}
			my $text = $ctx->{'char_buffer'} // q();
			$self->{'field_name'} = $text;
			push @{ $self->{fields} }, $self->{'field_name'};
			$self->_process_special_values( $ctx->{'these'} );
			$self->{'attributes'}{ $self->{'field_name'} } = $ctx->{'these'};

			# Clean explicit options
			my $sort = $self->{'attributes'}{ $self->{'field_name'} }{'sort'} // q();
			my ( $explicit, $unsorted ) =
			  $self->_get_explicit_options( $ctx->{'options'} // [], $sort );

			# If special-values exist, generate and merge (special first), then append explicit options
			if ( ( $ctx->{'these'}{'optlist'} // q() ) eq 'yes' && $ctx->{'these'}{'values'} ) {
				my $tmp = '__SPECIAL__' . int( rand(1000000) );
				$self->_add_special_optlist_values( $tmp, $ctx->{'these'}{'values'} );
				my @special = @{ $self->{options}{$tmp} // [] };
				delete $self->{'options'}{$tmp};

				# clean special and dedupe preserving order
				my %seen;
				my @clean_special;
				for my $o (@special) {
					next unless defined $o;
					$o =~ s/^\s+|\s+$//gx;
					next unless length $o;
					push @clean_special, $o unless $seen{$o}++;
				}

				# Merge sortable explicit options with special values.
				for my $o (@$explicit) {
					push @clean_special, $o unless $seen{$o}++;
				}
				if ( $sort eq 'yes' ) {
					@clean_special = @{ BIGSdb::Utils::unicode_dictionary_sort( \@clean_special ) };
				}

				# Options marked sort="no" follow sorted options in written order.
				for my $o (@$unsorted) {
					push @clean_special, $o unless $seen{$o}++;
				}
				$self->{'options'}{ $self->{'field_name'} } = \@clean_special if @clean_special;
			} else {
				my @clean = ( @$explicit, @$unsorted );
				$self->{'options'}{ $self->{'field_name'} } = \@clean if @clean;
			}

			# special-values helper for values in attributes (legacy)
			if ( ( $ctx->{'these'}{'optlist'} // q() ) eq 'yes' && $ctx->{'these'}{'values'} ) {
				# already handled above
			}

			# clear buffers
			delete $self->{'_char_buffer'};
			delete $self->{'_options_temp'};
		},
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
1;
