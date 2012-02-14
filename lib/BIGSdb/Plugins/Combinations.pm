#Combinations.pm - Unique combinations plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2012, University of Oxford
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
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);

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
		version     => '1.0.1',
		dbtype      => 'isolates',
		section     => 'breakdown,postquery',
		input       => 'query',
		help        => 'tooltips',
		order       => 15
	);
	return \%att;
}

sub run {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	print "<h1>Frequencies of field combinations</h1>\n";
	if ( $q->param('submit') ) {
		my $selected_fields = $self->get_selected_fields;
		if ( !@$selected_fields ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No fields have been selected!</p></div>\n";
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
				$field =~ s/^(s_\d+_l|s_\d+_f|f|l|c)_//g;    #strip off prefix for header row
				$field =~ s/___/../;
				$field =~ tr/_/ /;
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
			print "<div class=\"box\" id=\"resultstable\">\n";
			print "<p class=\"comment\">Calculating... ";
			my $total;

			while ( $sql->fetchrow_arrayref ) {
				my $first = 1;
				$total++;
				print "." if !$i;
				print " " if !$j;
				if ( !$i && $ENV{'MOD_PERL'} ) {
					$self->{'mod_perl_request'}->rflush;
					return if $self->{'mod_perl_request'}->connection->aborted;
				}
				my $allele_ids = $self->{'datastore'}->get_all_allele_ids( $data{'id'} );
				my $scheme_field_values;
				my $key;
				foreach (@$selected_fields) {
					$key .= '_|_' if !$first;
					if ( $_ =~ /^f_(.*)/ ) {
						my $field = $1;
						if ( $field eq 'aliases' ) {
							eval { $alias_sql->execute( $data{'id'} ) };
							$logger->error($@) if $@;
							my @aliases;
							while ( my ($alias) = $alias_sql->fetchrow_array ) {
								push @aliases, $alias;
							}
							local $" = '; ';
							$key .= "@aliases" ? "@aliases" : '-';
						} elsif ( $field =~ /(.*)___(.*)/ ) {
							my ( $isolate_field, $attribute ) = ( $1, $2 );
							eval { $attribute_sql->execute( $isolate_field, $attribute, $data{$isolate_field} ) };
							$logger->error($@) if $@;
							my ($value) = $attribute_sql->fetchrow_array;
							$key .= (defined $value && $value ne '') ? $value : '-';
						} else {
							$key .= (defined $data{$field} && $data{$field} ne '') ? $data{$field} : '-';
						}
					} elsif ( $_ =~ /^(s_\d+_l_|l_)(.*)/ ) {
						$key .= (defined $allele_ids->{$2} && $allele_ids->{$2} ne '') ? $allele_ids->{$2} : '-';
					} elsif ( $_ =~ /^s_(\d+)_f_(.*)/ ) {
						my $scheme_id = $1;
						my $scheme_field = lc($2);
						if ( ref $scheme_field_values->{$scheme_id} ne 'HASH' ) {
							$scheme_field_values->{$scheme_id} = $self->{'datastore'}->get_scheme_field_values_by_isolate_id( $data{'id'}, $scheme_id );
						}
						my $value = $scheme_field_values->{$scheme_id}->{$scheme_field};
						undef $value
						  if defined $value && $value eq '-999';    #old null code from mlstdbNet databases
						$key .= ( defined $value && $value ne '' ) ? $value : '-';
					} elsif ( $_ =~ /^c_(.*)/ ) {
						my $value = $self->{'datastore'}->get_composite_value( $data{'id'}, $1, \%data );
						$key .= $value;
					}
					$first = 0;
				}
				$combs{$key}++;
				$i++;
				if ( $i == 200 ) {
					$i = 0;
					$j++;
				}
				$j = 0 if $j == 10;
			}
			print "</p>";
			my $filename  = BIGSdb::Utils::get_random() . '.txt';
			my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
			open( my $fh, '>', $full_path )
			  or $logger->error("Can't open temp file $filename for writing");
			print "<div class=\"scrollable\"><table class=\"tablesorter\" id=\"sortTable\">\n<thead>\n";
			local $" = '</th><th>';
			print "<tr><th>@header</th><th>Frequency</th><th>Percentage</th></tr></thead>\n<tbody>\n";
			local $" = "\t";
			print $fh "@header\tFrequency\tPercentage\n";
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
			print "</tbody></table></div>\n";
			close $fh;
			print "<p /><p><a href=\"/tmp/$filename\">Download as tab-delimited text.</a></p>\n";
			print "</div>\n";
			return;
		}
	}
	print <<"HTML";
<div class="box" id="queryform">
<p>Here you can determine the frequencies of unique field combinations in the dataset.  Please select your combination of fields.</p>
HTML
	$self->print_field_export_form( 0, 0, { 'include_composites' => 1, 'extended_attributes' => 1 } );
	print "</div>\n";
	return;
}
1;
