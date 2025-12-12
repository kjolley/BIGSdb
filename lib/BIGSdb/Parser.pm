#Parser.pm
#Written by Keith Jolley
#Copyright (c) 2010-2025, University of Oxford
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

	# Normalise whitespace and skip empty-only chunks
	my $data = $element->{'Data'};
	$data =~ s/\r?\n/ /gx;
	$data =~ s/\s+/ /gx;
	$data =~ s/^\s+|\s+$//gx;
	return unless length $data;

	# look at top-of-stack context (if any)
	my $stack = $self->{'_field_stack'} // [];
	my $ctx   = @$stack ? $stack->[-1] : undef;

	# If inside an <option>, append into option_buffer
	if ( $self->{'_in_option'} ) {
		$self->{'_option_buffer'} .= $data;
		return;
	}

	# If inside a <field> but not inside optlist/option, append to this field's char_buffer
	if ( $self->{'_in_field'} && !$self->{'_in_optlist'} && !$self->{'_in_option'} ) {
		if ($ctx) {
			$ctx->{'char_buffer'} .= $data;
		} else {

			# defensive fallback: accumulate into global buffer if context missing
			$self->{'_char_buffer'} .= $data;
		}
		return;
	}

	# otherwise ignore stray text inside optlist or elsewhere
	return;
}

sub start_element {
	my ( $self, $element ) = @_;

	# ensure stack exists
	$self->{'_field_stack'} ||= [];

	my %methods = (
		system => sub {
			$self->{'_in_system'} = 1;
			$self->{'system'}     = $element->{'Attributes'};
		},

		# When a <field> starts push a new context on the stack
		field => sub {
			$self->{'_in_field'} = 1;
			my $ctx = {
				these       => $element->{'Attributes'} || {},
				char_buffer => '',                               # accumulate field text
				options     => [],                               # accumulate option values for this field
			};
			push @{ $self->{_field_stack} }, $ctx;
		},

		optlist => sub {
			$self->{'_in_optlist'} = 1;

			# make sure we have a stack to operate on
			$self->{'_field_stack'} ||= [];
		},

		option => sub {
			$self->{'_in_option'}     = 1;
			$self->{'_option_buffer'} = '';

			# ensure top context exists (defensive)
			$self->{'_field_stack'} ||= [];
		},
	);

	$methods{ $element->{'Name'} }->() if $methods{ $element->{'Name'} };
	return;
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

		# end of an <option> — push into top context's options array
		option => sub {
			$self->{'_in_option'} = 0;
			my $opt = $self->{'_option_buffer'} // q();
			$opt =~ s/^\s+|\s+$//gx;
			if ( $self->{'_field_stack'} && @{ $self->{'_field_stack'} } ) {
				push @{ $self->{'_field_stack'}->[-1]{'options'} }, $opt if length $opt;
			} else {

				# defensive fallback: push into global options keyed by last known field_name
				push @{ $self->{'options'}{ $self->{'field_name'} // '_unknown' } }, $opt if length $opt;
			}
			delete $self->{'_option_buffer'};
		},

		# end of <optlist> — we don't commit until field closes, but we clear the in-optlist flag
		optlist => sub {
			$self->{'_in_optlist'} = 0;

			# leave options in the top context; sort later when committing at field end if needed
		},

		# end of <field> — pop the context, commit name, attributes and options
		field => sub {
			$self->{'_in_field'} = 0;

			# pop top context
			my $ctx;
			$ctx = pop @{ $self->{'_field_stack'} } if $self->{'_field_stack'} && @{ $self->{'_field_stack'} };

			# if no context (defensive) fall back to global buffers
			unless ($ctx) {
				$ctx = {
					these       => $self->{'these'} || {},
					char_buffer => $self->{'_char_buffer'} // q(),
					options     => $self->{'_options_temp'} ? [ @{ $self->{'_options_temp'} } ] : [],
				};
			}

			my $text = $ctx->{'char_buffer'} // q();

			# field name is the text content
			$self->{'field_name'} = $text;
			push @{ $self->{fields} }, $self->{'field_name'};

			# store attributes for this field
			$self->_process_special_values( $ctx->{'these'} );
			$self->{'attributes'}{ $self->{'field_name'} } = $ctx->{'these'};

			# normalize options: trim, remove blank and dedupe
			my @opts = @{ $ctx->{options} // [] };
			my %seen;
			@opts = map  { s/^\s+|\s+$//rx } grep { defined && length } @opts;
			@opts = grep { !$seen{$_}++ } @opts;

			if (@opts) {
				$self->{'options'}{ $self->{'field_name'} } = \@opts;
			}

			# preserve existing special optlist handling
			if ( ( $ctx->{'these'}{'optlist'} // q() ) eq 'yes' && $ctx->{'these'}{'values'} ) {
				$self->_add_special_optlist_values( $self->{'field_name'}, $ctx->{'these'}{'values'} );
			}

			# optional: if sorting requested, do it now
			if ( ( $self->{'attributes'}{ $self->{'field_name'} }{'sort'} // q() ) eq 'yes' ) {
				$self->{'options'}{ $self->{'field_name'} } =
				  BIGSdb::Utils::unicode_dictionary_sort( $self->{'options'}{ $self->{'field_name'} } || [] );
			}

			# cleanup any global fallback buffers
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
