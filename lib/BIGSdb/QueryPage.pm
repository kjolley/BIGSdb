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
package BIGSdb::QueryPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::ResultsTablePage);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant MAX_ROWS  => 20;
use constant MAX_INT   => 2147483647;
use constant OPERATORS => ( '=', 'contains', 'starts with', 'ends with', '>', '<', 'NOT', 'NOT contain' );
our @EXPORT_OK = qw(OPERATORS MAX_ROWS);

sub initiate {
	my ($self) = @_;
	if ( $self->{'cgi'}->param('no_header') ) {
		$self->{'type'} = 'no_header';
		return;
	}
	$self->{$_} = 1 foreach qw (field_help tooltips jQuery jQuery.multiselect);
	return;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { general => 1, main_display => 1, isolate_display => 0, analysis => 0, query_field => 1 };
	return;
}

sub get_javascript {
	my ($self)   = @_;
	my $max_rows = MAX_ROWS;
	my $buffer   = $self->SUPER::get_javascript;
	$buffer .= << "END";
\$(function () {
	\$('a[data-rel=ajax]').click(function(){
  		\$(this).attr('href', function(){
    		return(this.href.replace(/(.*)/, "javascript:loadContent\('\$1\'\)"));
    	});
  	});
 });
 
function add_rows(url,list_name,row_name,row,field_heading,button_id){
	var new_row = row+1;
	\$("ul#"+list_name).append('<li id="' + row_name + row + '" />');
	\$("li#"+row_name+row).html('<img src=\"/javascript/themes/default/throbber.gif\" /> Loading ...').load(url);
	url = url.replace(/row=\\d+/,'row='+new_row);
	\$("#"+button_id).attr('href',url);
	\$("span#"+field_heading).show();
	if (new_row > $max_rows){
		\$("#"+button_id).hide();
	}
}
END
	return $buffer;
}

sub filters_selected {
	my ($self) = @_;
	my %params = $self->{'cgi'}->Vars;
	return 1 if any { $_ =~ /_list$/ && $params{$_} ne '' } keys %params;
	return;
}

sub get_grouped_fields {
	my ( $self, $field, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	$field =~ s/^f_// if $options->{'strip_prefix'};
	my @groupedfields;
	for ( 1 .. 10 ) {
		if ( $self->{'system'}->{"fieldgroup$_"} ) {
			my @grouped = ( split /:/, $self->{'system'}->{"fieldgroup$_"} );
			@groupedfields = split /,/, $grouped[1] if $field eq $grouped[0];
		}
	}
	return @groupedfields;
}

sub get_scheme_locus_query_clause {
	my ( $self, $scheme_id, $table, $locus, $scheme_named, $named ) = @_;
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);

	#Use correct cast to ensure that database indexes are used.
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( $scheme_info->{'allow_missing_loci'} ) {
		return "scheme_$scheme_id\.$scheme_named=ANY($table.$named || 'N'::text)";
	} else {
		if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
			return "scheme_$scheme_id\.$scheme_named=ANY(CAST($table.$named AS int[]))";
		} else {
			return "scheme_$scheme_id\.$scheme_named=ANY($table.$named)";
		}
	}
}

sub is_valid_operator {
	my ( $self, $value ) = @_;
	my @operators = OPERATORS;
	return ( any { $value eq $_ } @operators ) ? 1 : 0;
}

sub search_users {
	my ( $self, $name, $operator, $text, $table ) = @_;
	my ( $field, $suffix ) = split / /, $name;
	$suffix =~ s/[\(\)\s]//g;
	my $qry         = "SELECT id FROM users WHERE ";
	my $equals      = $suffix ne 'id' ? "upper($suffix) = upper('$text')" : "$suffix = '$text'";
	my $contains    = $suffix ne 'id' ? "upper($suffix) LIKE upper('\%$text\%')" : "CAST($suffix AS text) LIKE ('\%$text\%')";
	my $starts_with = $suffix ne 'id' ? "upper($suffix) LIKE upper('$text\%')" : "CAST($suffix AS text) LIKE ('$text\%')";
	my $ends_with   = $suffix ne 'id' ? "upper($suffix) LIKE upper('\%$text')" : "CAST($suffix AS text) LIKE ('\%$text')";
	if    ( $operator eq 'NOT' )         { $qry .= "NOT $equals" }
	elsif ( $operator eq 'contains' )    { $qry .= $contains }
	elsif ( $operator eq 'starts with' ) { $qry .= $starts_with }
	elsif ( $operator eq 'ends with' )   { $qry .= $ends_with }
	elsif ( $operator eq 'NOT contain' ) { $qry .= "NOT $contains" }
	elsif ( $operator eq '=' )           { $qry .= $equals }
	else                                 { $qry .= "$suffix $operator '$text'" }
	my $ids = $self->{'datastore'}->run_list_query($qry);
	$ids = [-999] if !@$ids;    #Need to return an integer but not 0 since this is actually the setup user.
	local $" = "' OR $table.$field = '";
	return "($table.$field = '@$ids')";
}

sub check_format {

	#returns 1 if error
	my ( $self, $data, $error_ref ) = @_;
	my $clean_fieldname = $data->{'clean_fieldname'} // $data->{'field'};
	my $error;
	if ( $data->{'text'} ne 'null' && defined $data->{'type'} ) {
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname( $data->{'field'} );
		if ( $data->{'type'} =~ /int/ ) {
			if ( !BIGSdb::Utils::is_int( $data->{'text'}, { do_not_check_range => 1 } ) ) {
				$error = ( $metafield // $clean_fieldname ) . " is an integer field.";
			} elsif ( $data->{'text'} > MAX_INT ) {
				$error = ( $metafield // $clean_fieldname ) . " is too big (largest allowed integer is " . MAX_INT . ').';
			}
		} elsif ( $data->{'type'} =~ /bool/ && !BIGSdb::Utils::is_bool( $data->{'text'} ) ) {
			$error = ( $metafield // $clean_fieldname ) . " is a boolean (true/false) field.";
		} elsif ( $data->{'type'} eq 'float' && !BIGSdb::Utils::is_float( $data->{'text'} ) ) {
			$error = ( $metafield // $clean_fieldname ) . " is a floating point number field.";
		} elsif (
			$data->{'type'} eq 'date' && (
				any {
					$data->{'operator'} eq $_;
				}
				( 'contains', 'NOT contain', 'starts with', 'ends with' )
			)
		  )
		{
			$error = "Searching a date field can not be done for the '$data->{'operator'}' operator.";
		} elsif ( $data->{'type'} eq 'date' && !BIGSdb::Utils::is_date( $data->{'text'} ) ) {
			$error = ( $metafield // $clean_fieldname ) . " is a date field - should be in yyyy-mm-dd format (or 'today' / 'yesterday').";
		}
	}
	if ( !$error && !$self->is_valid_operator( $data->{'operator'} ) ) {
		$error = "$data->{'operator'} is not a valid operator.";
	}
	push @$error_ref, $error if $error;
	return $error ? 1 : 0;
}

sub process_value {
	my ( $self, $value_ref ) = @_;
	$$value_ref =~ s/^\s*//;
	$$value_ref =~ s/\s*$//;
	$$value_ref =~ s/\\/\\\\/g;
	$$value_ref =~ s/'/\\'/g;
	return;
}
1;
