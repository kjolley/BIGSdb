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
package BIGSdb::FieldHelpPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use Error qw(:try);
use BIGSdb::Page qw(LOCUS_PATTERN);

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(field_help jQuery jQuery.tablesort);
	return;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 1 };
	return;
}

sub get_javascript {
	return <<"JS";
\$(document).ready(function() 
    { 
        \$("#sortTable").tablesorter({widgets:['zebra']}); 
    } 
); 	
JS
}

sub print_content {
	my ($self) = @_;
	say "<h1>Allowed/submitted field values</h1>";
	my $q     = $self->{'cgi'};
	my $field = $q->param('field');
	my $scheme_id;
	my $field_type;
	if ( $field =~ /^([f|l])_(.*)$/ ) {
		$field_type = $1;
		$field      = $2;
	} elsif ( $field =~ /^la_(.*)\|\|(.+)$/ ) {
		$field_type = 'l';
		$field      = $1;
	} elsif ( $field =~ /^cn_(.*)$/ ) {
		$field_type = 'l';
		$field      = $1;
	} elsif ( $field =~ /^s_(\d+)_(.*)$/ ) {
		$field_type = 'sf';
		$scheme_id  = $1;
		$field      = $2;
	}
	if ( !defined $field_type ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Invalid field selected.</p></div>";
		return;
	}
	if ( $field_type eq 'f' ) {
		$self->_print_isolate_field($field);
	} elsif ( $field_type eq 'l' ) {
		$self->_print_locus($field);
	} elsif ( $field_type eq 'sf' ) {
		$self->_print_scheme_field( $scheme_id, $field );
	}
	return;
}

sub _print_isolate_field {
	my ( $self, $field ) = @_;
	if ( !$self->{'xmlHandler'}->is_field($field) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Invalid field selected.</p></div>";
		return;
	}
	my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
	( my $cleaned = $metafield // $field ) =~ tr/_/ /;
	say "<div class=\"box\" id=\"resultstable\">";
	say "<h2>$cleaned</h2>";
	my $attributes = $self->{'xmlHandler'}->get_field_attributes($field);
	say "<table class=\"resultstable\">";
	my %type = ( 'int' => 'integer', 'float' => 'floating point number' );
	my $unique_qry =
	  defined $metaset
	  ? "SELECT COUNT(DISTINCT $metafield) FROM meta_$metaset WHERE isolate_id IN (SELECT id FROM $self->{'system'}->{'view'})"
	  : "SELECT COUNT(DISTINCT $field) FROM $self->{'system'}->{'view'}";
	my $unique = $self->{'datastore'}->run_simple_query($unique_qry)->[0];
	say "<tr class=\"td1\"><th style=\"text-align:right\">Data type</th><td style=\"text-align:left\">"
	  . ( $type{ $attributes->{'type'} } || $attributes->{'type'} )
	  . "</td></tr>";
	say "<tr class=\"td2\"><th style=\"text-align:right\">Required</th><td style=\"text-align:left\">"
	  . (
		!defined $attributes->{'required'} || $attributes->{'required'} ne 'no'
		? "yes - this is a required field so all records must contain a value.</td></tr>"
		: "no - this is an optional field so some records may not contain a value.</td></tr>"
	  );
	say "<tr class=\"td1\"><th style=\"text-align:right\">Unique values</th><td style=\"text-align:left\">$unique</td></tr>";
	my $td = 2;

	if ( $attributes->{'comments'} ) {
		say "<tr class=\"td$td\"><th style=\"text-align:right\">Comments</th><td style=\"text-align:left\">$attributes->{'comments'}"
		  . "</td></tr>";
		$td = $td == 1 ? 2 : 1;
	}
	if ( $attributes->{'regex'} ) {
		say "<tr class=\"td$td\"><th style=\"text-align:right\">Regular expression</th><td style=\"text-align:left\">"
		  . "Values are constrained to the following <a href=\"http://en.wikipedia.org/wiki/Regex\">regular expression</a>"
		  . ": /$attributes->{'regex'}/</td></tr>";
	}
	print "</table>\n\n";
	my $qry =
	  defined $metaset
	  ? "SELECT DISTINCT $metafield FROM meta_$metaset WHERE isolate_id IN (SELECT id FROM $self->{'system'}->{'view'})"
	  : "SELECT DISTINCT $field FROM $self->{'system'}->{'view'} ORDER BY $field";
	my $used_list = $self->{'datastore'}->run_list_query($qry);
	my $longest   = 0;
	foreach (@$used_list) {
		$longest = length($_) if length($_) > $longest;
	}
	my $text_cols = $longest > 120 ? 2 : 6;
	my $cols = $attributes->{'type'} eq 'int' ? 10 : $text_cols;
	my $used;
	$used->{$_} = 1 foreach @$used_list;
	if ( $field eq 'sender' || $field eq 'curator' || ( $attributes->{'userfield'} && $attributes->{'userfield'} eq 'yes' ) ) {
		my $filter = $field eq 'curator' ? "WHERE (status = 'curator' or status = 'admin') AND id>0" : 'WHERE id>0';
		my $sql = $self->{'db'}->prepare("SELECT id, user_name, surname, first_name, affiliation FROM users $filter ORDER BY id");
		eval { $sql->execute };
		$logger->error($@) if $@;
		my $buffer;
		while ( my @data = $sql->fetchrow_array ) {
			next if !$used->{ $data[0] };
			foreach (@data) {
				$_ =~ s/\&/\&amp;/g;
			}
			$buffer .= "<tr><td>$data[0]</td><td>$data[1]</td><td>$data[2]</td><td>$data[3]</td><td align='left'>$data[4]</td></tr>\n";
		}
		if ($buffer) {
			print "<p>The integer stored in this field is the key to the following users";
			print " (only curators or administrators shown)" if $field eq 'curator';
			say ". Only users linked to an isolate record are shown.</p>";
			say "<table class=\"tablesorter\" id=\"sortTable\">\n";
			say "<thead><tr><th>id</th><th>username</th><th>surname</th><th>first name</th>"
			  . "<th>affiliation / collaboration</th></tr></thead><tbody>";
			say $buffer;
			say "</tbody></table>";
		} else {
			say "<p>The database currently contains no values.</p>";
		}
	} elsif ( ( $attributes->{'optlist'} // '' ) eq 'yes' ) {
		say "<p>The field has a constrained list of allowable values (values present in the database are "
		  . "<span class=\"highlightvalue\">highlighted</span>):</p>";
		my $options = $self->{'xmlHandler'}->get_field_option_list($field);
		$self->_print_list( $options, $cols, $used );
	} else {
		if (@$used_list) {
			say "<p>The following values are present in the database:</p>";
			$self->_print_list( $used_list, $cols );
		} else {
			say "<p>The database currently contains no values.</p>";
		}
	}
	say "</div>";
	return;
}

sub _print_list {
	my ( $self, $list, $cols, $used ) = @_;
	return if !$cols;
	my $items_per_column = scalar @$list / $cols;
	say qq(<div class="scrollable"><table><tr><td style="vertical-align:top">);
	my $i = 0;
	say "<ul>";
	foreach (@$list) {
		s/&/&amp;/g;
		s/</&lt;/g;
		s/>/&gt;/g;
		print $used->{$_} ? "<li><span class=\"highlightvalue\">$_</span></li>" : "<li>$_</li>";
		$i++;
		if ( $i > $items_per_column ) {
			$i = 0;
			if ( $i != scalar @$list ) {
				say "</ul>";
				say "</td><td style=\"vertical-align:top; padding-left:20px\">";
				say "<ul>";
			}
		}
	}
	say "</ul></td></tr></table></div>";
	return;
}

sub _print_scheme_field {
	my ( $self, $scheme_id, $field ) = @_;
	if ( !$self->{'datastore'}->is_scheme_field( $scheme_id, $field ) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Invalid scheme field selected.</p></div>";
		return;
	}
	my $set_id      = $self->get_set_id;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
	my $cleaned     = "$field ($scheme_info->{'description'})";
	$cleaned =~ tr/_/ /;
	say "<div class=\"box\" id=\"resultstable\">";
	say "<h2>$cleaned</h2>";
	my $info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
	say "<table class=\"resultstable\">";
	say "<tr class=\"td1\"><th style=\"text-align:right\">Data type</th><td style=\"text-align:left\">$info->{'type'}</td></tr>";
	say "<tr class=\"td2\"><th style=\"text-align:right\">Primary key</th><td style=\"text-align:left\">"
	  . ( $info->{'type'} ? 'yes' : 'no' )
	  . "</td></tr>";

	if ( $info->{'description'} ) {
		say "<tr class=\"td1\"><th style=\"text-align:right\">Description</th><td style=\"text-align:left\">"
		  . "$info->{'description'}</td></tr>";
	}
	print "</table>\n";
	my $temp_table;
	try {
		$temp_table = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
	}
	catch BIGSdb::DatabaseConnectionException with {
		say qq(<div class="box" id="statusbad"><p>The database for scheme $scheme_id is not accessible. This may be a configuration )
		  . qq(problem.</p></div>);
		$logger->error("Can't copy data to temporary table.");
	};
	say "<p>The field has a list of values retrieved from an external database.  Values present in this database are shown.";
	my $cols = $info->{'type'} eq 'integer' ? 10 : 6;
	my $list =
	  $self->{'datastore'}
	  ->run_query( "SELECT DISTINCT $field FROM $temp_table WHERE $field IS NOT NULL ORDER BY $field", undef, { fetch => 'col_arrayref' } );
	$self->_print_list( $list, $cols );
	say "</div>";
	return;
}

sub _print_locus {
	my ( $self, $locus ) = @_;
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Invalid locus selected.</p></div>";
		return;
	}
	my $cleaned = $self->clean_locus($locus);
	say "<div class=\"box\" id=\"resultstable\">";
	say "<h2>$cleaned</h2>";
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	say "<table class=\"resultstable\">";
	say "<tr class=\"td1\"><th style=\"text-align:right\">Data type</th><td style=\"text-align:left\">"
	  . "$locus_info->{'data_type'}</td></tr>";
	say "<tr class=\"td2\"><th style=\"text-align:right\">Allele id format</th><td style=\"text-align:left\">"
	  . "$locus_info->{'allele_id_format'}</td></tr>";
	my $td = 1;

	if ( $locus_info->{'common_name'} ) {
		say "<tr class=\"td$td\"><th style=\"text-align:right\">Common name</th><td style=\"text-align:left\">"
		  . "$locus_info->{'common_name'}</td></tr>";
		$td = $td == 1 ? 2 : 1;
	}
	if ( $locus_info->{'allele_id_regex'} ) {
		say "<tr class=\"td$td\"><th style=\"text-align:right\">Allele id regular expression</th><td style=\"text-align:left\">"
		  . "$locus_info->{'allele_id_regex'}</td></tr>";
		$td = $td == 1 ? 2 : 1;
	}
	if ( $locus_info->{'description'} ) {
		say "<tr class=\"td$td\"><th style=\"text-align:right\">Description</th><td style=\"text-align:left\">"
		  . "$locus_info->{'description'}</td></tr>";
		$td = $td == 1 ? 2 : 1;
	}
	if ( $locus_info->{'length'} ) {
		say "<tr class=\"td$td\"><th style=\"text-align:right\">Length</th><td style=\"text-align:left\">"
		  . "$locus_info->{'length'}</td></tr>";
		$td = $td == 1 ? 2 : 1;
	}
	say "<tr class=\"td$td\"><th style=\"text-align:right\">Variable length</th><td style=\"text-align:left\">"
	  . ( $locus_info->{'length_varies'} ? 'yes' : 'no' )
	  . "</td></tr>";
	$td = $td == 1 ? 2 : 1;
	if ( $locus_info->{'reference_sequence'} ) {
		my $truncate = BIGSdb::Utils::truncate_seq( \$locus_info->{'reference_sequence'}, 100 );
		say "<tr class=\"td$td\"><th style=\"text-align:right\">Reference sequence</th><td style=\"text-align:left\" "
		  . "class=\"seq\">$truncate</td></tr>";
		$td = $td == 1 ? 2 : 1;
	}
	say "</table>";
	my $allele_id = $locus_info->{'allele_id_format'} eq 'integer' ? 'CAST(allele_id AS integer)' : 'allele_id';
	my $used_list =
	  $self->{'datastore'}
	  ->run_list_query( "SELECT DISTINCT $allele_id FROM allele_designations WHERE locus=? ORDER BY $allele_id", $locus );
	if (@$used_list) {
		say "<p>The following values are present in the database:</p>";
		$self->_print_list( $used_list, 10 );
	} else {
		say "<p>There are no values for this locus in the database.</p>";
	}
	say "</div>";
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc    = $self->{'system'}->{'description'} || 'BIGSdb';
	my $field   = $self->{'cgi'}->param('field');
	my $pattern = LOCUS_PATTERN;
	if ( $field =~ /$pattern/ ) {
		$field = $self->clean_locus($1);
	} elsif ( $field =~ /s_(\d+)_(.*)$/ ) {
		my $scheme_id    = $1;
		my $scheme_field = $2;
		my $set_id       = $self->get_set_id;
		my $scheme_info  = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
		$field = "$scheme_field ($scheme_info->{'description'})";
	} else {
		$field =~ s/^f_//;
	}
	$field =~ tr/_/ /;
	return "Field values for '$field' - $desc";
}
1;
