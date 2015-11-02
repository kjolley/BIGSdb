#Combinations.pm - Unique combinations plugin for BIGSdb
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
package BIGSdb::Plugins::Combinations;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_FIELDS => 100;

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 1, query_field => 0 };
	return;
}

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name        => 'Unique Combinations',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Determine frequencies of unique field combinations',
		category    => 'Breakdown',
		buttontext  => 'Combinations',
		menutext    => 'Unique combinations',
		module      => 'Combinations',
		url         => "$self->{'config'}->{'doclink'}/data_analysis.html#unique-combinations",
		version     => '1.1.2',
		dbtype      => 'isolates',
		section     => 'breakdown,postquery',
		input       => 'query',
		help        => 'tooltips',
		requires    => 'js_tree',
		order       => 15
	);
	return \%att;
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Frequencies of field combinations</h1>);
	return if $self->has_set_changed;
	if ( !$q->param('submit') ) {
		$self->_print_interface;
		return;
	}
	my $selected_fields = $self->get_selected_fields;
	if ( !@$selected_fields ) {
		say q(<div class="box" id="statusbad"><p>No fields have been selected!</p></div>);
		$self->_print_interface;
		return;
	} elsif (@$selected_fields > MAX_FIELDS){
		my $limit = MAX_FIELDS;
		my $selected_count = @$selected_fields;
		say qq(<div class="box" id="statusbad"><p>This analysis is limited to $limit fields. )
		  . qq(You have selected $selected_count!</p></div>);
		$self->_print_interface;
		return;
	}
	my $query_file = $q->param('query_file');
	my $qry_ref    = $self->get_query($query_file);
	return if ref $qry_ref ne 'SCALAR';
	my $view = $self->{'system'}->{'view'};
	return if !$self->create_temp_tables($qry_ref);
	my $fields = $self->{'xmlHandler'}->get_field_list;
	local $" = ",$view.";
	my $field_string = "$view.@$fields";
	$$qry_ref =~ s/SELECT\ ($view\.\*|\*)/SELECT $field_string/x;
	$self->rewrite_query_ref_order_by($qry_ref);
	
	local $| = 1;
	my @header;
	my %schemes;
	


	foreach (@$selected_fields) {
		my $field = $_;
		if ( $field =~ /^s_(\d+)_f/x ) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($1);
			$field .= " ($scheme_info->{'description'})"
			  if $scheme_info->{'description'};
			$schemes{$1} = 1;
		}
		$field =~ s/^(s_\d+_l|s_\d+_f|f|l|c)_//gx;                      #strip off prefix for header row
		$field =~ s/^meta_.+?://x;
		$field =~ s/^.*___//x;
		$field =~ tr/_/ / if !$self->{'datastore'}->is_locus($field);
		push @header, $field;
	}
	print "\n";
	my $scheme_field_pos;
	foreach my $scheme_id ( keys %schemes ) {
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		my $i             = 0;
		foreach my $field (@$scheme_fields) {
			$scheme_field_pos->{$scheme_id}->{$field} = $i;
			$i++;
		}
	}
	my $dataset = $self->{'datastore'}->run_query( $$qry_ref, undef, { fetch => 'all_arrayref', slice => {} } );
	my $i       = 1;
	my $j       = 0;
	my %combs;
	say q(<div class="box" id="resultstable">);
	print q(<p class="comment" id="calculating">Calculating... );
	my $total;
	my $values = {};

	foreach my $data (@$dataset) {
		$total++;
		print q(.) if !$i;
		print q( ) if !$j;
		if ( !$i && $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
		my $allele_ids = $self->{'datastore'}->get_all_allele_ids( $data->{'id'} );
		foreach my $field (@$selected_fields) {
			if ( $field =~ /^f_(.*)/x ) {
				my $prov_field = $1;
				$values->{ $data->{'id'} }->{$field} = $self->_get_field_value( $prov_field, $data );
				next;
			}
			if ( $field =~ /^(s_\d+_l_|l_)(.*)/x ) {
				my $locus = $2;
				$values->{ $data->{'id'} }->{$field} =
				  ( defined $allele_ids->{$locus} && $allele_ids->{$locus} ne '' )
				  ? $allele_ids->{$locus}
				  : ['-'];
				next;
			}
			if ( $field =~ /^s_(\d+)_f_(.*)/x ) {
				my $scheme_id    = $1;
				my $scheme_field = lc($2);
				my $scheme_field_values =
				  $self->get_scheme_field_values(
					{ isolate_id => $data->{'id'}, scheme_id => $scheme_id, field => $scheme_field } );
				foreach my $value (@$scheme_field_values) {
					$value //= '-';
				}
				$values->{ $data->{'id'} }->{$field} = @$scheme_field_values ? $scheme_field_values : ['-'];
				next;
			}
			if ( $field =~ /^c_(.*)/x ) {
				my $value = $self->{'datastore'}->get_composite_value( $data->{'id'}, $1, $data );
				$values->{ $data->{'id'} }->{$field} = [$value];
			}
		}
		$i++;
		if ( $i == 200 ) {
			$i = 0;
			$j++;
		}
		$j = 0 if $j == 10;
	}
	$self->_update_combinations( \%combs, $selected_fields, $values );
	say q(</p>);
	$self->_print_results( \@header, \%combs, $total );
	return;
}

sub _print_results {
	my ( $self, $header, $combs, $total ) = @_;
	say q(<p>Number of unique combinations: ) . ( keys %$combs ) . q(</p>);
	say q(<p>The percentages may add up to more than 100% if you have selected loci or scheme )
	  . q(fields with multiple values for an isolate.</p>);
	my $prefix    = BIGSdb::Utils::get_random();
	my $filename  = "$prefix.txt";
	my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
	open( my $fh, '>', $full_path )
	  or $logger->error("Can't open temp file $filename for writing");
	say q(<div class="scrollable"><table class="tablesorter" id="sortTable"><thead>);
	say q(<tr>);

	foreach my $heading (@$header) {
		my ( $cleaned_html, $cleaned_text ) = ( $heading, $heading );
		if ( $self->{'datastore'}->is_locus($heading) ) {
			$cleaned_html = $self->clean_locus($heading);
			$cleaned_text = $self->clean_locus( $heading, { text_output => 1, no_common_name => 1 } );
		}
		say qq(<th>$cleaned_html</th>);
		print $fh qq($cleaned_text\t);
	}
	say q(<th>Frequency</th><th>Percentage</th></tr></thead><tbody>);
	say $fh qq(Frequency\tPercentage);
	my $td = 1;
	foreach ( sort { $combs->{$b} <=> $combs->{$a} } keys %$combs ) {
		my @values = split /_\|_/x, $_;
		my $pc = BIGSdb::Utils::decimal_place( 100 * $combs->{$_} / $total, 2 );
		local $" = q(</td><td>);
		say qq(<tr class="td$td"><td>@values</td><td>$combs->{$_}</td><td>$pc</td></tr>);
		local $" = "\t";
		say $fh qq(@values\t$combs->{$_}\t$pc);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</tbody></table></div>);
	close $fh;
	say qq(<ul><li><a href="/tmp/$filename">Download as tab-delimited text</a></li>);
	my $excel =
	  BIGSdb::Utils::text2excel( $full_path,
		{ worksheet => 'Unique combinations', tmp_dir => $self->{'config'}->{'secure_tmp_dir'} } );
	say qq(<li><a href="/tmp/$prefix.xlsx">Download in Excel format</a></li>) if -e $excel;
	say q(</ul></div>);
	return;
}

sub _get_field_value {
	my ( $self, $field, $data ) = @_;
	my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
	if ( defined $metaset ) {
		my $value = $self->{'datastore'}->get_metadata_value( $data->{'id'}, $metaset, $metafield );
		$value = '-' if $value eq '';
		return [$value];
	} elsif ( $field eq 'aliases' ) {
		my $aliases = $self->{'datastore'}->get_isolate_aliases( $data->{'id'} );
		local $" = '; ';
		my $value = @$aliases ? "@$aliases" : '-';
		return [$value];
	} elsif ( $field =~ /(.*)___(.*)/x ) {
		my ( $isolate_field, $attribute ) = ( $1, $2 );
		my $value = $self->{'datastore'}->run_query(
			'SELECT value FROM isolate_value_extended_attributes WHERE '
			  . '(isolate_field,attribute,field_value)=(?,?,?)',
			[ $isolate_field, $attribute, $data->{$isolate_field} ],
			{ cache => 'Combinations::extended_values' }
		);
		$value = '-' if !defined $value || $value eq '';
		return [$value];
	} else {
		my $value = ( defined $data->{$field} && $data->{$field} ne '' ) ? $data->{$field} : '-';
		return [$value];
	}
}

sub _print_interface {
	my ($self) = @_;
	say q(<div class="box" id="queryform"><p>Here you can determine the frequencies of unique field )
	  . q(combinations in the dataset. Please select your combination of fields. Select loci either )
	  . q(from the locus list or by selecting one or more schemes to include all loci (and/or fields) )
	  . q(from a scheme.</p>);
	$self->print_field_export_form( 0, { include_composites => 1, extended_attributes => 1 } );
	say q(</div>);
	return;
}

sub _update_combinations {
	my ( $self, $combs, $fields, $values ) = @_;
	foreach my $isolate_id ( keys %$values ) {
		my @keys;
		my @fields_to_check = @$fields;
		my $current_field   = shift @fields_to_check;
		$self->_append_keys( \@keys, \@fields_to_check, $current_field, $values->{$isolate_id} );
		$combs->{$_}++ foreach @keys;
	}
	return;
}

sub _append_keys {
	my ( $self, $keys, $fields_to_check, $current_field, $values ) = @_;
	if ( !@$keys ) {
		foreach my $value ( @{ $values->{$current_field} } ) {
			push @$keys, $value;
		}
	} else {
		foreach my $i ( 0 .. @$keys - 1 ) {
			my $existing_value = $keys->[$i];
			my $j              = 0;
			my %used;
			foreach my $value ( @{ $values->{$current_field} } ) {
				next if $used{$value};
				if ($j) {
					my $new_value = "$existing_value\_|_$value";
					push @$keys, $new_value;
				} else {
					$keys->[$i] .= "_|_$value";
					$j = 1;
				}
				$used{$value} = 1;
			}
		}
	}
	return if !@$fields_to_check;
	$current_field = shift @$fields_to_check;
	$self->_append_keys( $keys, $fields_to_check, $current_field, $values );
	return;
}

sub get_plugin_javascript {
	my ($self) = @_;
	my $js = << "END";
\$(function () {
	\$("#calculating").css('display','none');
});
END
	return $js;
}
1;
