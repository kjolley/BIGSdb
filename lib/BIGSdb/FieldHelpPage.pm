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
package BIGSdb::FieldHelpPage;
use strict;
use warnings;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use Error qw(:try);

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(field_help jQuery jQuery.tablesort);
	return;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { 'general' => 0, 'main_display' => 0, 'isolate_display' => 0, 'analysis' => 0, 'query_field' => 1 };
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
	print "<h1>Allowed/submitted field values</h1>\n";
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
	if ( !defined $field_type){
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid field selected.</p></div>\n";
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
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid field selected.</p></div>\n";
		return;
	}
	( my $cleaned = $field ) =~ tr/_/ /;
	print "<div class=\"box\" id=\"resultstable\">\n";
	print "<h2>$cleaned</h2>\n";
	my %attributes = $self->{'xmlHandler'}->get_field_attributes($field);
	print "<table class=\"resultstable\">\n";
	my %type = ( 'int' => 'integer', 'float' => 'floating point number' );
	my $unique = $self->{'datastore'}->run_simple_query("SELECT COUNT(DISTINCT $field) FROM $self->{'system'}->{'view'}")->[0];
	print "<tr class=\"td1\"><th style=\"text-align:right\">Data type</th><td style=\"text-align:left\">"
	  . ( $type{ $attributes{'type'} } || $attributes{'type'} )
	  . "</td></tr>\n";
	print "<tr class=\"td2\"><th style=\"text-align:right\">Required</th><td style=\"text-align:left\">"
	  . (
		!defined $attributes{'required'} || $attributes{'required'} ne 'no'
		? "yes - this is a required field so all records must contain a value.</td></tr>\n"
		: "no - this is an optional field so some records may not contain a value.</td></tr>\n"
	  );
	print "<tr class=\"td1\"><th style=\"text-align:right\">Unique values</th><td style=\"text-align:left\">$unique</td></tr>\n";
	my $td = 2;

	if ( $attributes{'comments'} ) {
		print
"<tr class=\"td$td\"><th style=\"text-align:right\">Comments</th><td style=\"text-align:left\">$attributes{'comments'}</td></tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	if ( $attributes{'regex'} ) {
		print
"<tr class=\"td$td\"><th style=\"text-align:right\">Regular expression</th><td style=\"text-align:left\">Values are constrained to the following <a href=\"http://en.wikipedia.org/wiki/Regex\">regular expression</a>: /$attributes{'regex'}/</td></tr>\n";
	}
	print "</table>\n<p />\n";
	my $used_list = $self->{'datastore'}->run_list_query("SELECT DISTINCT $field FROM $self->{'system'}->{'view'} ORDER BY $field");
	my $cols = $attributes{'type'} eq 'int' ? 10 : 6;
	my $used;
	$used->{$_} = 1 foreach @$used_list;
	if ( $field eq 'sender' || $field eq 'curator' || ( $attributes{'userfield'} && $attributes{'userfield'} eq 'yes' ) ) {
		print "<p>The integer stored in this field is the key to the following users";
		my $filter = $field eq 'curator' ? "WHERE (status = 'curator' or status = 'admin') AND id>0" : 'WHERE id>0';
		my $qry = "SELECT id, user_name, surname, first_name, affiliation FROM users $filter ORDER BY id";
		print " (only curators or administrators shown)" if $field eq 'curator';
		print ". Values present in the database are <span class=\"highlightvalue\">highlighted</span>.\n";
		print "</p>\n";
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute };
		$logger->error($@) if $@;
		print "<table class=\"tablesorter\" id=\"sortTable\">\n";
		print
"<thead><tr><th>id</th><th>username</th><th>surname</th><th>first name</th><th>affiliation / collaboration</th></tr></thead><tbody>\n";
		while ( my @data = $sql->fetchrow_array ) {
			foreach (@data) {
				$_ =~ s/\&/\&amp;/g;
			}
			print "<tr><td>"
			  . ( $used->{ $data[0] } ? "<span class=\"highlightvalue\">$data[0]</span>" : "$data[0]" )
			  . "</td><td>$data[1]</td><td>$data[2]</td><td>$data[3]</td><td align='left'>$data[4]</td></tr>\n";
		}
		print "</tbody></table>\n";
	} elsif ( $attributes{'optlist'} && $attributes{'optlist'} eq 'yes' ) {
		print
"<p>The field has a constrained list of allowable values (values present in the database are <span class=\"highlightvalue\">highlighted</span>):</p>";
		my @options = $self->{'xmlHandler'}->get_field_option_list($field);
		$self->_print_list( \@options, $cols, $used );
	} else {
		print "<p>The following values are present in the database:</p>";
		$self->_print_list( $used_list, $cols );
	}
	print "</div>\n";
	return;
}

sub _print_list {
	my ( $self, $list, $cols, $used ) = @_;
	return if !$cols;
	my $items_per_column = scalar @$list / $cols;
	print "<table><tr><td style=\"vertical-align:top\">\n";
	my $i = 0;
	foreach (@$list) {
		print $used->{$_} ? "<span class=\"highlightvalue\">$_</span><br />" : "$_<br />";
		$i++;
		if ( $i > $items_per_column ) {
			$i = 0;
			print "</td><td style=\"vertical-align:top; padding-left:20px\">"
			  if $i != scalar @$list;
		}
	}
	print "</td></tr></table>\n";
	return;
}

sub _print_scheme_field {
	my ( $self, $scheme_id, $field ) = @_;
	if ( !$self->{'datastore'}->is_scheme_field( $scheme_id, $field ) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid scheme field selected.</p></div>\n";
		return;
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
	my $cleaned     = "$field ($scheme_info->{'description'})";
	$cleaned =~ tr/_/ /;
	print "<div class=\"box\" id=\"resultstable\">\n";
	print "<h2>$cleaned</h2>\n";
	my $info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
	print "<table class=\"resultstable\">\n";
	print "<tr class=\"td1\"><th style=\"text-align:right\">Data type</th><td style=\"text-align:left\">$info->{'type'}</td></tr>\n";
	print "<tr class=\"td2\"><th style=\"text-align:right\">Primary key</th><td style=\"text-align:left\">"
	  . ( $info->{'type'} ? 'yes' : 'no' )
	  . "</td></tr>\n";

	if ( $info->{'description'} ) {
		print
"<tr class=\"td1\"><th style=\"text-align:right\">Description</th><td style=\"text-align:left\">$info->{'description'}</td></tr>\n";
	}
	print "</table><p />\n";
	try {
		$self->{'datastore'}->create_temp_scheme_table($scheme_id);
	}
	catch BIGSdb::DatabaseConnectionException with {
		print
"<p class=\"statusbad\">Can't copy data into temporary table - please check scheme configuration (more details will be in the log file).</p>\n";
		$logger->error("Can't copy data to temporary table.");
	};
	print
"<p>The field has a list of allowable values retrieved from an external database (values present in this database are <span class=\"highlightvalue\">highlighted</span>):</p>";
	my $cols = $info->{'type'} eq 'integer' ? 10 : 6;
	my $list =
	  $self->{'datastore'}->run_list_query("SELECT DISTINCT $field FROM temp_scheme_$scheme_id WHERE $field IS NOT NULL ORDER BY $field");
	my $scheme_loci  = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $joined_table = "SELECT DISTINCT scheme_$scheme_id.$field FROM $self->{'system'}->{'view'}";
	foreach (@$scheme_loci) {
		$joined_table .= " left join allele_designations AS $_ on $_.isolate_id = $self->{'system'}->{'view'}.id";
	}
	$joined_table .= " left join temp_scheme_$scheme_id AS scheme_$scheme_id ON";
	my @temp;
	foreach (@$scheme_loci) {
		my $locus_info = $self->{'datastore'}->get_locus_info($_);
		if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
			push @temp, " CAST($_.allele_id AS int)=scheme_$scheme_id\.$_";
		} else {
			push @temp, " $_.allele_id=scheme_$scheme_id\.$_";
		}
	}
	local $" = ' AND ';
	$joined_table .= " @temp WHERE";
	undef @temp;
	foreach (@$scheme_loci) {
		push @temp, "$_.locus='$_'";
	}
	$joined_table .= " @temp";
	my $used_list = $self->{'datastore'}->run_list_query($joined_table);
	my $used;
	$used->{$_} = 1 foreach @$used_list;
	$self->_print_list( $list, $cols, $used );
	print "</div>\n";
	return;
}

sub _print_locus {
	my ( $self, $locus ) = @_;
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid locus selected.</p></div>\n";
		return;
	}
	( my $cleaned = $locus ) =~ tr/_/ /;
	print "<div class=\"box\" id=\"resultstable\">\n";
	print "<h2>$cleaned</h2>\n";
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	print "<table class=\"resultstable\">\n";
	print
	  "<tr class=\"td1\"><th style=\"text-align:right\">Data type</th><td style=\"text-align:left\">$locus_info->{'data_type'}</td></tr>\n";
	print
"<tr class=\"td2\"><th style=\"text-align:right\">Allele id format</th><td style=\"text-align:left\">$locus_info->{'allele_id_format'}</td></tr>\n";
	my $td = 1;

	if ( $locus_info->{'common_name'} ) {
		print
"<tr class=\"td$td\"><th style=\"text-align:right\">Common name</th><td style=\"text-align:left\">$locus_info->{'common_name'}</td></tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	if ( $locus_info->{'allele_id_regex'} ) {
		print
"<tr class=\"td$td\"><th style=\"text-align:right\">Allele id regular expression</th><td style=\"text-align:left\">$locus_info->{'allele_id_regex'}</td></tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	if ( $locus_info->{'description'} ) {
		print
"<tr class=\"td$td\"><th style=\"text-align:right\">Description</th><td style=\"text-align:left\">$locus_info->{'description'}</td></tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	if ( $locus_info->{'length'} ) {
		print
		  "<tr class=\"td$td\"><th style=\"text-align:right\">Length</th><td style=\"text-align:left\">$locus_info->{'length'}</td></tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	print "<tr class=\"td$td\"><th style=\"text-align:right\">Variable length</th><td style=\"text-align:left\">"
	  . ( $locus_info->{'length_varies'} ? 'yes' : 'no' )
	  . "</td></tr>\n";
	$td = $td == 1 ? 2 : 1;
	if ( $locus_info->{'reference_sequence'} ) {
		my $truncate = BIGSdb::Utils::truncate_seq( \$locus_info->{'reference_sequence'}, 100 );
		print
"<tr class=\"td$td\"><th style=\"text-align:right\">Reference sequence</th><td style=\"text-align:left\" class=\"seq\">$truncate</td></tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	print "</table><p />\n";
	my $allele_id = $locus_info->{'allele_id_format'} eq 'integer' ? 'CAST(allele_id AS integer)' : 'allele_id';
	my $used_list =
	  $self->{'datastore'}
	  ->run_list_query( "SELECT DISTINCT $allele_id FROM allele_designations WHERE locus=? ORDER BY $allele_id", $locus );
	if (@$used_list) {
		print "<p>The following values are present in the database:</p>";
		$self->_print_list( $used_list, 10 );
	} else {
		print "<p>There are no values for this locus in the database.</p>";
	}
	print "</div>\n";
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	my $field = $self->{'cgi'}->param('field');
	$field =~ s/^[f|l|la]_//;
	if ( $field =~ /^la_(.*)\|\|(.+)$/ ) {
		$field = "$2 ($1)";
	} elsif ( $field =~ /s_(\d+)_(.*)$/ ) {
		my $scheme_id    = $1;
		my $scheme_field = $2;
		my $scheme_info  = $self->{'datastore'}->get_scheme_info($scheme_id);
		$field = "$scheme_field ($scheme_info->{'description'})";
	}
	$field =~ tr/_/ /;
	return "Field values for '$field' - $desc";
}
1;
