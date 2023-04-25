#Written by Keith Jolley
#Copyright (c) 2010-2020, University of Oxford
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
package BIGSdb::FieldHelpPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use Try::Tiny;
use BIGSdb::Constants qw(LOCUS_PATTERN :limits);

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery jQuery.tablesort jQuery.columnizer);
	$self->set_level1_breadcrumbs;
	return;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 1 };
	return;
}

sub get_javascript {
	return <<"JS";
\$(document).ready(function() 
    { 
        \$("#sortTable").tablesorter({widgets:['zebra']}); 
        \$("#valueList").columnize({width:200,lastNeverTallest:true});
    } 
); 	
JS
}

sub _get_field_and_type {
	my ( $self, $param_value ) = @_;
	return if !defined $param_value;
	if ( $param_value =~ /^(f|l|eav)_(.*)$/x ) {
		return ( $2, $1 );
	}
	if ( $param_value =~ /^la_(.*)\|\|(.+)$/x ) {
		return ( $1, 'l' );
	}
	if ( $param_value =~ /^cn_(.*)$/x ) {
		return ( $1, 'l' );
	}
	if ( $param_value =~ /^s_(\d+)_(.*)$/x ) {
		return ( $2, 'sf', $1 );
	}
	return;
}

sub print_content {
	my ($self) = @_;
	say q(<h1>Allowed/submitted field values</h1>);
	my $q = $self->{'cgi'};
	$self->_print_interface;
	return if !$q->param('field');
	my ( $field, $field_type, $scheme_id ) = $self->_get_field_and_type( scalar $q->param('field') );
	if ( !defined $field_type ) {
		$self->print_bad_status( { message => q(Invalid field selected.), navbar => 1 } );
		return;
	}
	my %methods = (
		f   => sub { $self->_print_isolate_field($field) },
		l   => sub { $self->_print_locus($field) },
		sf  => sub { $self->_print_scheme_field( $scheme_id, $field ) },
		eav => sub { $self->_print_eav_field($field) },
	);
	$methods{$field_type}->() if $methods{$field_type};
	return;
}

sub _print_interface {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="queryform"><div class="scrollable">);
	say q(<p>This page will display all values defined in the database for a selected field.</p>);
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Select field</legend>);
	my ( $values, $labels ) = $self->get_field_selection_list(
		{
			isolate_fields => 1,
			eav_fields     => 1,
			loci           => 1,
			locus_limit    => MAX_LOCUS_ORDER_BY,
			scheme_fields  => 1,
			sort_labels    => 1
		}
	);
	say $self->popup_menu( -name => 'field', -values => $values, -labels => $labels );
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach qw (db page);
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub _print_isolate_field {
	my ( $self, $field ) = @_;
	if ( !$self->{'xmlHandler'}->is_field($field) ) {
		$self->print_bad_status( { message => q(Invalid field selected.), navbar => 1 } );
		return;
	}
	( my $cleaned = $field ) =~ tr/_/ /;
	say q(<div class="box" id="resultsheader">);
	say qq(<h2>Field: $cleaned</h2>);
	my $attributes = $self->{'xmlHandler'}->get_field_attributes($field);
	my %type = ( int => 'integer', float => 'floating point number' );
	my $unique_qry =
	  ( $attributes->{'multiple'} // q() ) eq 'yes'
	  ? "SELECT COUNT(DISTINCT values) FROM $self->{'system'}->{'view'} v,unnest(v.$field) values"
	  : "SELECT COUNT(DISTINCT $field) FROM $self->{'system'}->{'view'}";
	my $unique = $self->{'datastore'}->run_query($unique_qry);
	my $data_type = $type{ $attributes->{'type'} } || $attributes->{'type'};
	my $required_text =
	  !defined $attributes->{'required'} || $attributes->{'required'} ne 'no'
	  ? q(yes - this is a required field so all records must contain a value.)
	  : q(no - this is an optional field so some records may not contain a value.);
	say q(<dl class="data">);
	say qq(<dt>Data type</dt><dd>$data_type</dd>);
	say qq(<dt>Required</dt><dd>$required_text</dd>);
	say qq(<dt>Unique values</dt><dd>$unique</dd>);

	if ( $attributes->{'comments'} ) {
		say qq(<dt>Comments</dt><dd>$attributes->{'comments'}</dd>);
	}
	if ( $attributes->{'regex'} ) {
		say q(<dt>Regular expression</dt><dd>Values are constrained to the following )
		  . q(<a href="http://en.wikipedia.org/wiki/Regex">regular expression</a>: )
		  . qq(/$attributes->{'regex'}/<dd>);
	}
	say q(</dl>);
	say q(</div><div class="box" id="resultstable">);
	say q(<h2>Values</h2>);
	my $qry =
	  ( $attributes->{'multiple'} // q() ) eq 'yes'
	  ? "SELECT DISTINCT values FROM $self->{'system'}->{'view'} v,unnest(v.$field) values ORDER BY values"
	  : "SELECT DISTINCT $field FROM $self->{'system'}->{'view'} WHERE $field IS NOT NULL ORDER BY $field ";
	my $used_list = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	my $used;
	$used->{$_} = 1 foreach @$used_list;

	if (   $field eq 'sender'
		|| $field eq 'curator'
		|| ( ( $attributes->{'userfield'} // q() ) eq 'yes' ) )
	{
		my $filter = $field eq 'curator' ? q(WHERE status IN ('curator','admin') AND id>0) : q(WHERE id>0);
		my $users =
		  $self->{'datastore'}->run_query(
			"SELECT id FROM users $filter AND id IN (SELECT $field FROM $self->{'system'}->{'view'}) ORDER BY id",
			undef, { fetch => 'col_arrayref' } );
		my $buffer;
		if ( $field eq 'sender' && $self->{'username'} ) {
			my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
			$buffer .= qq(<p>Your user id is: <b>$user_info->{'id'}</b></p>);
		}
		foreach my $id (@$users) {
			next if !$used->{$id};
			my $data = $self->{'datastore'}->get_user_info($id);
			$data->{'affiliation'} =~ s/\&/\&amp;/gx;
			$buffer .= qq(<tr><td>$data->{'id'}</td><td>$data->{'surname'}</td><td>$data->{'first_name'}</td>)
			  . qq(<td style="text-align:left">$data->{'affiliation'}</td></tr>\n);
		}
		if (@$users) {
			print q(<p>The integer stored in this field is the key to the following users);
			print q( (only curators or administrators shown)) if $field eq 'curator';
			say q(. Only users linked to an isolate record are shown.</p>);
			say q(<table class="tablesorter" id="sortTable">);
			say q(<thead><tr><th>id</th><th>surname</th><th>first name</th>)
			  . q(<th>affiliation / collaboration</th></tr></thead><tbody>);
			say $buffer;
			say q(</tbody></table>);
		} else {
			say q(<p>The database currently contains no values.</p>);
		}
	} elsif ( ( $attributes->{'optlist'} // '' ) eq 'yes' ) {
		say q[<p>The field has a constrained list of allowable values (values present in ]
		  . q[the database are <span class="highlightvalue">highlighted</span>):</p>];
		my $options = $self->{'xmlHandler'}->get_field_option_list($field);
		$self->_print_list( $options, $used );
	} else {
		if (@$used_list) {
			say q(<p>The following values are present in the database:</p>);
			$self->_print_list($used_list);
		} else {
			say q(<p>The database currently contains no values.</p>);
		}
	}
	say q(</div>);
	return;
}

sub _print_eav_field {
	my ( $self, $field ) = @_;
	if ( !$self->{'datastore'}->is_eav_field($field) ) {
		$self->print_bad_status( { message => q(Invalid field selected.), navbar => 1 } );
		return;
	}
	( my $cleaned = $field ) =~ tr/_/ /;
	say q(<div class="box" id="resultsheader">);
	say qq(<h2>Field: $cleaned</h2>);
	my $attributes = $self->{'datastore'}->get_eav_field($field);
	my %type       = ( float => 'floating point number' );
	my $table      = $self->{'datastore'}->get_eav_field_table($field);
	my $unique_qry =
	    "SELECT COUNT(DISTINCT value) FROM $table t JOIN $self->{'system'}->{'view'} v "
	  . 'ON t.isolate_id=v.id WHERE field=?';
	my $unique = $self->{'datastore'}->run_query( $unique_qry, $field );
	my $data_type = $type{ $attributes->{'value_format'} } || $attributes->{'value_format'};
	say q(<dl class="data">);
	say qq(<dt>Data type</dt><dd>$data_type</dd>);
	say q(<dt>Required</dt><dd>no</dd>);
	say qq(<dt>Unique values</dt><dd>$unique</dd>);

	if ( $attributes->{'description'} ) {
		say qq(<dt>Comments</dt><dd>$attributes->{'description'}</dd>);
	}
	if ( $attributes->{'value_regex'} ) {
		say q(<dt>Regular expression</dt><dd>Values are constrained to the following )
		  . q(<a href="http://en.wikipedia.org/wiki/Regex">regular expression</a>: )
		  . qq(/$attributes->{'value_regex'}/<dd>);
	}
	say q(</dl>);
	say q(</div><div class="box" id="resultstable">);
	say q(<h2>Values</h2>);
	my $qry = "SELECT DISTINCT value FROM $table t JOIN $self->{'system'}->{'view'} v "
	  . 'ON t.isolate_id=v.id WHERE field=? ORDER BY value';
	my $used_list = $self->{'datastore'}->run_query( $qry, $field, { fetch => 'col_arrayref' } );
	my %used = map { $_ => 1 } @$used_list;
	if ( defined $attributes->{'option_list'} ) {
		say q[<p>The field has a constrained list of allowable values (values present in ]
		  . q[the database are <span class="highlightvalue">highlighted</span>):</p>];
		my @options = split /;/x, $attributes->{'option_list'};
		$self->_print_list( \@options, \%used );
	} else {
		if (@$used_list) {
			say q(<p>The following values are present in the database:</p>);
			$self->_print_list($used_list);
		} else {
			say q(<p>The database currently contains no values.</p>);
		}
	}
	return;
}

sub _print_list {
	my ( $self, $list, $used ) = @_;
	say q(<div class="scrollable">);
	say q(<div id="valueList">) if @$list < 2000;    #Columnizer javascript is too slow if list is very long.
	say q(<ul>);
	foreach my $value (@$list) {
		my $escaped_value = BIGSdb::Utils::escape_html($value);
		say $used->{$value}
		  ? qq(<li class="dontsplit"><span class="highlightvalue">$escaped_value</span></li>)
		  : qq(<li class="dontsplit">$escaped_value</li>);
	}
	say q(</ul></div>);
	say q(</div>) if @$list < 2000;
	return;
}

sub _print_scheme_field {
	my ( $self, $scheme_id, $field ) = @_;
	if ( !$self->{'datastore'}->is_scheme_field( $scheme_id, $field ) ) {
		$self->print_bad_status( { message => q(Invalid scheme field selected.), navbar => 1 } );
		return;
	}
	my $set_id      = $self->get_set_id;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
	my $cleaned     = qq($field ($scheme_info->{'name'}));
	$cleaned =~ tr/_/ /;
	say q(<div class="box" id="resultsheader">);
	say qq(<h2>Field: $cleaned</h2>);
	my $info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
	my $is_pk = $info->{'primary_key'} ? q(yes) : q(no);
	say q(<dl class="data">);
	say qq(<dt>Data type</dt><dd>$info->{'type'}</dd>);
	say qq(<dt>Primary key</dt><dd>$is_pk</dd>);
	say qq(<dt>Description</dt><dd>$info->{'description'}</dd>) if $info->{'description'};
	say q(</dl>);
	say q(</div><div class="box" id="resultstable">);
	say q(<h2>Values</h2>);
	my $temp_table;
	try {
		$temp_table = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
	}
	catch {
		if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
			$self->print_bad_status(
				{
					message => qq(The database for scheme $scheme_id is not )
					  . q(accessible. This may be a configuration problem.),
					navbar => 1
				}
			);
			$logger->error('Cannot copy data to temporary table.');
		} else {
			$logger->logdie($_);
		}
	};
	say q(<p>The field has a list of values retrieved from an external database. )
	  . q(Values present in this database are shown.);
	my $list = $self->{'datastore'}->run_query(
		"SELECT DISTINCT $field FROM $temp_table WHERE $field IS NOT NULL AND id IN "
		  . "(SELECT id FROM $self->{'system'}->{'view'}) ORDER BY $field",
		undef,
		{ fetch => 'col_arrayref' }
	);
	$self->_print_list($list);
	say q(</div>);
	return;
}

sub _print_locus {
	my ( $self, $locus ) = @_;
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		$self->print_bad_status( { message => q(Invalid locus selected.), navbar => 1 } );
		return;
	}
	my $cleaned = $self->clean_locus($locus);
	say q(<div class="box" id="resultsheader">);
	say qq(<h2>Locus: $cleaned</h2>);
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $length_varies = $locus_info->{'length_varies'} ? q(yes) : q(no);
	say q(<dl class="data">);
	say qq(<dt>Data type</dt><dd>$locus_info->{'data_type'}</dd>);
	say qq(<dt>Allele id format</dt><dd>$locus_info->{'allele_id_format'}</dd>);
	say qq(<dt>Common name</dt><dd>$locus_info->{'common_name'}</dd>)         if $locus_info->{'common_name'};
	say qq(<dt>Allele id regex</dt><dd>$locus_info->{'allele_id_regex'}</dd>) if $locus_info->{'allele_id_regex'};
	say qq(<dt>Length</dt><dd>$locus_info->{'length'}</dd>)                   if $locus_info->{'length'};
	say qq(<dt>Variable length</dt><dd>$length_varies</dd>);

	if ( $locus_info->{'reference_sequence'} ) {
		my $truncate = BIGSdb::Utils::truncate_seq( \$locus_info->{'reference_sequence'}, 100 );
		say qq(<dt>Reference seq</dt><dd class="seq">$truncate</dd>);
	}
	say q(</dl>);
	say q(</div><div class="box" id="resultstable">);
	say q(<h2>Values</h2>);
	my $allele_id = $locus_info->{'allele_id_format'} eq 'integer' ? q(CAST(allele_id AS integer)) : q(allele_id);
	my $used_list = $self->{'datastore'}->run_query(
		"SELECT DISTINCT $allele_id FROM allele_designations WHERE locus=? AND isolate_id "
		  . "IN (SELECT id FROM $self->{'system'}->{'view'}) ORDER BY $allele_id",
		$locus,
		{ fetch => 'col_arrayref' }
	);
	if (@$used_list) {
		say q(<p>The following values are present in the database:</p>);
		$self->_print_list($used_list);
	} else {
		say q(<p>There are no values for this locus in the database.</p>);
	}
	say q(</div>);
	return;
}

sub get_title {
	my ($self) = @_;
	return q(Field values);
}
1;
