#Written by Keith Jolley
#Copyright (c) 2010-2022, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
package BIGSdb::CurateTableHeaderPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use List::MoreUtils qw(none);
use Log::Log4perl qw(get_logger);
use BIGSdb::Constants qw(:limits);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{'type'} = 'text';
	return;
}

sub print_content {
	my ($self) = @_;
	my $table = $self->{'cgi'}->param('table') || '';
	if ( !$self->{'datastore'}->is_table($table) ) {
		say "Table $table does not exist!";
		return;
	}
	my $q         = $self->{'cgi'};
	my $no_fields = $q->param('no_fields') ? 1 : 0;    #For profile submissions
	my $id_field  = $q->param('id_field') ? 1 : 0;     #Ditto
	my $headers = $self->get_headers( $table, { no_fields => $no_fields, id_field => $id_field } );
	if ( $table eq 'isolates' && $q->param('addCols') ) {
		my @cols = split /,/x, $q->param('addCols');
		push @$headers, @cols;
	}
	local $" = "\t";
	say "@$headers";
	return;
}

sub _get_isolate_table_headers {
	my ($self)     = @_;
	my $headers    = [];
	my $set_id     = $self->get_set_id;
	my $is_curator = $self->is_curator;
	my $field_list = $self->{'xmlHandler'}->get_field_list;
	foreach my $field (@$field_list) {
		my $att = $self->{'xmlHandler'}->get_field_attributes($field);
		$att->{$_} //= q() foreach qw(curate_only allow_submissions no_curate no_submissions);
		next if $att->{'curate_only'} eq 'yes' && !$is_curator && $att->{'allow_submissions'} ne 'yes';
		next if $att->{'no_curate'} eq 'yes';
		next if $att->{'no_submissions'} eq 'yes';
		push @$headers, $field if none { $field eq $_ } qw (id curator sender date_entered datestamp);
		if ( $field eq $self->{'system'}->{'labelfield'} ) {
			push @$headers, q(aliases);
			if ( ( $self->{'system'}->{'alternative_codon_tables'} // q() ) eq 'yes' ) {
				push @$headers, q(codon_table);
			}
			push @$headers, q(references);
		}
	}
	my $eav_fields = $self->{'datastore'}->get_eav_fields;
	if ( @$eav_fields && @$eav_fields <= MAX_EAV_FIELD_LIST ) {
		foreach my $eav_field (@$eav_fields) {
			push @$headers, $eav_field->{'field'} if !$eav_field->{'no_curate'} && !$eav_field->{'no_submissions'};
		}
	}
	my $isolate_loci = $self->get_isolate_loci;
	push @$headers, @$isolate_loci;
	return $headers;
}

sub _get_profile_table_headers {
	my ( $self, $options ) = @_;
	my $q         = $self->{'cgi'};
	my $headers   = [];
	my $scheme_id = $self->{'cgi'}->param('scheme_id') // 0;
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		return ['Scheme id must be an integer.'];
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $set_id = $self->get_set_id;
	push @$headers, 'id' if $options->{'id_field'};
	push @$headers, $scheme_info->{'primary_key'} if ( !$options->{'no_fields'} );
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	foreach my $locus (@$loci) {
		my $label = $self->clean_locus( $locus, { text_output => 1, no_common_name => 1 } );
		push @$headers, $label // $locus;
	}
	if ( !$options->{'no_fields'} ) {
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		foreach my $field (@$scheme_fields) {
			my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
			push @$headers, $field if !$scheme_field_info->{'primary_key'};
		}
	}
	return $headers;
}

sub _get_lincode_table_headers {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id') // 0;
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		return ['Scheme id must be an integer.'];
	}
	my $lincode_scheme =
	  $self->{'datastore'}
	  ->run_query( 'SELECT * FROM lincode_schemes WHERE scheme_id=?', $scheme_id, { fetch => 'row_hashref' } );
	if ( !$lincode_scheme ) {
		return ['Lincode thresholds have not been defined for this scheme.'];
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	if ( !$scheme_info->{'primary_key'} ) {
		return ['No primary key is defined for this scheme.'];
	}
	my $headers = [];
	push @$headers, $scheme_info->{'primary_key'};
	my @thresholds = split /\s*;\s*/x, $lincode_scheme->{'thresholds'};
	foreach my $threshold (@thresholds) {
		push @$headers, "threshold_$threshold";
	}
	return $headers;
}

sub _get_other_table_headers {
	my ( $self, $table ) = @_;
	my $headers    = [];
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	foreach my $att (@$attributes) {
		if ( !( $att->{'name'} eq 'id' && $att->{'type'} eq 'int' ) ) {
			push @$headers, $att->{'name'}
			  if none { $att->{'name'} eq $_ } qw (curator sender date_entered datestamp);
		}
		if ( $table eq 'loci' && $att->{'name'} eq 'id' ) {
			push @$headers, 'aliases';
		}
	}
	if ( $table eq 'sequences' ) {
		if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
			push @$headers, 'flags';
		}
		if ( $self->{'cgi'}->param('locus') ) {
			shift @$headers;    #don't include 'locus'
			my $extended_attributes = $self->{'datastore'}->run_query(
				'SELECT field FROM locus_extended_attributes WHERE locus=? ORDER BY field_order',
				scalar $self->{'cgi'}->param('locus'),
				{ fetch => 'col_arrayref' }
			);
			if ( ref $extended_attributes eq 'ARRAY' ) {
				push @$headers, @$extended_attributes;
			}
		}
	} elsif ( $table eq 'loci' && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		push @$headers, qw(full_name product description);
	}
	return $headers;
}

sub get_headers {
	my ( $self, $table, $options ) = @_;
	my $headers = [];
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		$headers = $self->_get_isolate_table_headers;
	} elsif ( $table eq 'profiles' ) {
		$headers = $self->_get_profile_table_headers($options);
	} elsif ( $table eq 'lincodes' ) {
		$headers = $self->_get_lincode_table_headers;
	} else {
		$headers = $self->_get_other_table_headers($table);
	}
	return $headers;
}

sub get_isolate_loci {
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	my @headers;
	my $q = $self->{'cgi'};
	return [] if $q->param('noLoci');
	my $order = $q->param('order') // 'alphabetical';
	my $loci;
	my %include;

	if ( BIGSdb::Utils::is_int( scalar $q->param('scheme') ) ) {
		$loci = $self->{'datastore'}->get_scheme_loci( scalar $q->param('scheme') );
		%include = map { $_ => 1 } @$loci;
	} else {
		$loci =
		  $self->{'datastore'}->get_loci( { set_id => $set_id, analysis_pref => ( $order eq 'scheme' ? 1 : 0 ) } );
		my $loci_with_flag =
		  $self->{'datastore'}
		  ->run_query( 'SELECT id FROM loci WHERE submission_template', undef, { fetch => 'col_arrayref' } );
		%include = map { $_ => 1 } @$loci_with_flag;
	}
	foreach my $locus (@$loci) {
		next if !$include{$locus};
		my $cleaned_name = $self->clean_locus( $locus, { no_common_name => 1, text_output => 1 } );
		push @headers, $cleaned_name;
	}
	return \@headers;
}
1;
