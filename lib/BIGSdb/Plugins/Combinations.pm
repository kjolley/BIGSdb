#Combinations.pm - Unique combinations plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2014, University of Oxford
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
use Error qw(:try);

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { general => 1, main_display => 0, isolate_display => 0, analysis => 1, query_field => 0 };
	return;
}

sub get_attributes {
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
		version     => '1.1.0',
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
	say "<h1>Frequencies of field combinations</h1>";
	if ( $q->param('submit') ) {
		my $selected_fields = $self->get_selected_fields;
		if ( !@$selected_fields ) {
			say "<div class=\"box\" id=\"statusbad\"><p>No fields have been selected!</p></div>";
		} else {
			my $query_file = $q->param('query_file');
			my $qry_ref    = $self->get_query($query_file);
			return if ref $qry_ref ne 'SCALAR';
			my $view = $self->{'system'}->{'view'};
			return if !$self->create_temp_tables($qry_ref);
			my $fields = $self->{'xmlHandler'}->get_field_list;
			local $" = ",$view.";
			my $field_string = "$view.@$fields";
			$$qry_ref =~ s/SELECT ($view\.\*|\*)/SELECT $field_string/;
			$self->rewrite_query_ref_order_by($qry_ref);
			my $sql = $self->{'db'}->prepare($$qry_ref);
			eval { $sql->execute };
			$logger->error($@) if $@;
			local $| = 1;
			my @header;
			my %schemes;

			foreach (@$selected_fields) {
				my $field = $_;
				if ( $field =~ /^s_(\d+)_f/ ) {
					my $scheme_info = $self->{'datastore'}->get_scheme_info($1);
					$field .= " ($scheme_info->{'description'})"
					  if $scheme_info->{'description'};
					$schemes{$1} = 1;
				}
				$field =~ s/^(s_\d+_l|s_\d+_f|f|l|c)_//g;                       #strip off prefix for header row
				$field =~ s/^meta_.+?://;
				$field =~ s/^.*___//;
				$field =~ tr/_/ / if !$self->{'datastore'}->is_locus($field);
				push @header, $field;
			}
			print "\n";
			my $scheme_field_pos;
			foreach my $scheme_id ( keys %schemes ) {
				my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
				my $i             = 0;
				foreach (@$scheme_fields) {
					$scheme_field_pos->{$scheme_id}->{$_} = $i;
					$i++;
				}
			}
			my %data           = ();
			my $fields_to_bind = $self->{'xmlHandler'}->get_field_list;
			$sql->bind_columns( map { \$data{$_} } @$fields_to_bind );    #quicker binding hash to arrayref than to use hashref
			my $i         = 1;
			my $j         = 0;
			my $alias_sql = $self->{'db'}->prepare("SELECT alias FROM isolate_aliases WHERE isolate_id=? ORDER BY alias");
			my $attribute_sql =
			  $self->{'db'}
			  ->prepare("SELECT value FROM isolate_value_extended_attributes WHERE isolate_field=? AND attribute=? AND field_value=?");
			my %combs;
			say "<div class=\"box\" id=\"resultstable\">";
			print qq(<p class="comment" id="calculating">Calculating... );
			my $total;
			my $values = {};

			while ( $sql->fetchrow_arrayref ) {
				$total++;
				print "." if !$i;
				print " " if !$j;
				if ( !$i && $ENV{'MOD_PERL'} ) {
					$self->{'mod_perl_request'}->rflush;
					return if $self->{'mod_perl_request'}->connection->aborted;
				}
				my $allele_ids = $self->{'datastore'}->get_all_allele_ids( $data{'id'} );
				foreach my $field (@$selected_fields) {
					if ( $field =~ /^f_(.*)/ ) {
						my $prov_field = $1;
						my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($prov_field);
						if ( defined $metaset ) {
							my $value = $self->{'datastore'}->get_metadata_value( $data{'id'}, $metaset, $metafield );
							$value = '-' if $value eq '';
							$values->{ $data{'id'} }->{$field} = [$value];
						} elsif ( $prov_field eq 'aliases' ) {
							eval { $alias_sql->execute( $data{'id'} ) };
							$logger->error($@) if $@;
							my @aliases;
							while ( my ($alias) = $alias_sql->fetchrow_array ) {
								push @aliases, $alias;
							}
							local $" = '; ';
							my $value = "@aliases" ? "@aliases" : '-';
							$values->{ $data{'id'} }->{$field} = [$value];
						} elsif ( $prov_field =~ /(.*)___(.*)/ ) {
							my ( $isolate_field, $attribute ) = ( $1, $2 );
							eval { $attribute_sql->execute( $isolate_field, $attribute, $data{$isolate_field} ) };
							$logger->error($@) if $@;
							my ($value) = $attribute_sql->fetchrow_array;
							$value = '-' if !defined $value || $value eq '';
							$values->{ $data{'id'} }->{$field} = [$value];
						} else {
							my $value = ( defined $data{$prov_field} && $data{$prov_field} ne '' ) ? $data{$prov_field} : '-';
							$values->{ $data{'id'} }->{$field} = [$value];
						}
					} elsif ( $field =~ /^(s_\d+_l_|l_)(.*)/ ) {
						my $locus = $2;
						$values->{ $data{'id'} }->{$field} =
						  ( defined $allele_ids->{$locus} && $allele_ids->{$locus} ne '' ) ? $allele_ids->{$locus} : ['-'];
					} elsif ( $field =~ /^s_(\d+)_f_(.*)/ ) {
						my $scheme_id    = $1;
						my $scheme_field = lc($2);
						my $scheme_field_values =
						  $self->get_scheme_field_values( { isolate_id => $data{'id'}, scheme_id => $scheme_id, field => $scheme_field } );
						foreach (@$scheme_field_values) {
							$_ = '-' if !defined || $_ eq '';
						}
						$values->{ $data{'id'} }->{$field} = @$scheme_field_values ? $scheme_field_values : ['-'];
					} elsif ( $field =~ /^c_(.*)/ ) {
						my $value = $self->{'datastore'}->get_composite_value( $data{'id'}, $1, \%data );
						$values->{ $data{'id'} }->{$field} = $value;
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
			say "</p>";
			say "<p>Number of unique combinations: " . ( keys %combs ) . "</p>";
			say "<p>The percentages may add up to more than 100% if you have selected loci or scheme fields with multiple values "
			  . "for an isolate.</p>";
			my $filename  = BIGSdb::Utils::get_random() . '.txt';
			my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
			open( my $fh, '>', $full_path )
			  or $logger->error("Can't open temp file $filename for writing");
			say "<div class=\"scrollable\"><table class=\"tablesorter\" id=\"sortTable\">\n<thead>";
			say "<tr>";

			foreach my $heading (@header) {
				my ( $cleaned_html, $cleaned_text ) = ( $heading, $heading );
				if ( $self->{'datastore'}->is_locus($heading) ) {
					$cleaned_html = $self->clean_locus($heading);
					$cleaned_text = $self->clean_locus( $heading, { text_output => 1, no_common_name => 1 } );
				}
				say "<th>$cleaned_html</th>";
				print $fh "$cleaned_text\t";
			}
			say "<th>Frequency</th><th>Percentage</th></tr></thead>\n<tbody>";
			say $fh "Frequency\tPercentage";
			my $td = 1;
			foreach ( sort { $combs{$b} <=> $combs{$a} } keys %combs ) {
				my @values = split /_\|_/, $_;
				my $pc = BIGSdb::Utils::decimal_place( 100 * $combs{$_} / $total, 2 );
				local $" = '</td><td>';
				print "<tr class=\"td$td\"><td>@values</td><td>$combs{$_}</td><td>$pc</td></tr>\n";
				local $" = "\t";
				print $fh "@values\t$combs{$_}\t$pc\n";
				$td = $td == 1 ? 2 : 1;
			}
			say "</tbody></table></div>";
			close $fh;
			say "<p><a href=\"/tmp/$filename\">Download as tab-delimited text.</a></p>";
			say "</div>";
			return;
		}
	}
	print <<"HTML";
<div class="box" id="queryform">
<p>Here you can determine the frequencies of unique field combinations in the dataset.  Please select your 
combination of fields. Select loci either from the locus list or by selecting one or more schemes to include 
all loci (and/or fields) from a scheme.</p>
HTML
	$self->print_field_export_form( 0, { include_composites => 1, extended_attributes => 1 } );
	say "</div>";
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
