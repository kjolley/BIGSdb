#Written by Keith Jolley
#Copyright (c) 2010-2017, University of Oxford
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
use BIGSdb::Constants qw(:interface OPERATORS);
my $logger = get_logger('BIGSdb.Page');
use constant MAX_INT => 2147483647;

sub initiate {
	my ($self) = @_;
	if ( $self->{'cgi'}->param('no_header') ) {
		$self->{'type'} = 'no_header';
		return;
	}
	$self->{$_} = 1 foreach qw (tooltips jQuery jQuery.multiselect);
	return;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 1, isolate_display => 0, analysis => 0, query_field => 1 };
	return;
}

sub get_javascript_panel {
	my ( $self, @fieldsets ) = @_;
	my $button_text_js;
	my $button_toggle_js;
	my $new_url    = 'this.href';
	my %clear_form = (
		list    => q[$("#list").val('')],
		filters => qq[if (! Modernizr.touch){\n            \$('.multiselect').multiselect("uncheckAll")\n          }\n]
		  . q[          $('[id$="_list"]').val('')],
		provenance          => q[$('[id^="prov_value"]').val('')],
		allele              => q[$('[id^="value"]').val('')],
		scheme              => q[$('[id^="value"]').val('')],
		allele_designations => q[$('[id^="designation"]').val('')],
		allele_count        => q[$('[id^="allele_count"]').val('')],
		allele_status       => q[$('[id^="allele_sequence"]').val('')],
		tags                => q[$('[id^="tag"]').val('')],
		tag_count           => q[$('[id^="tag_count"]').val('')],
	);
	my ( $show, $hide, $save, $saving ) = ( SHOW, HIDE, SAVE, SAVING );
	foreach my $fieldset (@fieldsets) {
		$button_text_js   .= qq(        var $fieldset = \$("#show_$fieldset").html() == '$show' ? 0 : 1;\n);
		$new_url          .= qq( + "\&$fieldset=" + $fieldset);
		$button_toggle_js .= qq[    \$("#show_$fieldset").click(function() {\n];
		$button_toggle_js .= qq[       if(\$(this).html() == '$hide'){\n];
		$button_toggle_js .= qq[          $clear_form{$fieldset};\n];
		$button_toggle_js .= qq[       }\n];
		$button_toggle_js .= qq[       \$("#${fieldset}_fieldset").toggle(100);\n];
		$button_toggle_js .= qq[       \$(this).html(\$(this).html() == '$show' ? '$hide' : '$show');\n];
		$button_toggle_js .= qq[       \$("a#save_options").fadeIn();\n];
		$button_toggle_js .= qq[       return false;\n];
		$button_toggle_js .= qq[    });\n];
	}
	my $buffer = <<"END";
	$button_toggle_js
	\$(".trigger").click(function(){		
		\$(".panel").toggle("slide",{direction:"right"},"fast");
		\$("#panel_trigger").show().animate({backgroundColor: "#448"},100).animate({backgroundColor: "#99d"},100);		
		return false;
	});
	\$("#panel_trigger").show().animate({backgroundColor: "#99d"},500);
		\$("a#save_options").click(function(event){		
		event.preventDefault();
		$button_text_js
	  	\$(this).attr('href', function(){  	
	  		\$("a#save_options").html('$saving').animate({backgroundColor: "#99d"},100).animate({backgroundColor: "#f0f0f0"},100);
	  		\$("span#saving").text('Saving...');
	  		var new_url = $new_url;
		  		\$.ajax({
	  			url : new_url,
	  			success: function () {	  				
	  				\$("a#save_options").hide();
	  				\$("span#saving").text('');
	  				\$("a#save_options").html('$save');
	  			}
	  		});
	   	});
	});
END
	return $buffer;
}

sub get_javascript {
	my ($self)   = @_;
	my $max_rows = MAX_ROWS;
	my $buffer   = $self->SUPER::get_javascript;
	$buffer .= << "END";
\$(function () {
	\$('div#queryform').on('click', 'a[data-rel=ajax]',function(){
  		\$(this).attr('href', function(){
    		return(this.href.replace(/(.*)/, "javascript:loadContent\('\$1\'\)"));
    	});
  	});
 });
 
function add_rows(url,list_name,row_name,row,field_heading,button_id){
	var new_row = row+1;
	\$("ul#"+list_name).append('<li id="' + row_name + row + '" />');
	\$("li#"+row_name+row).html('<span class="fa fa-spinner fa-spin fa-lg fa-fw"></span> Loading ...').load(url);
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
	my $q      = $self->{'cgi'};
	my %params = $q->Vars;
	return 1 if any { $_ =~ /_list$/x && $params{$_} ne '' } keys %params;
	return 1 if $q->param('include_old');
	return;
}

sub get_grouped_fields {
	my ( $self, $field, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	$field =~ s/^f_//x if $options->{'strip_prefix'};
	my @groupedfields;
	for ( 1 .. 10 ) {
		if ( $self->{'system'}->{"fieldgroup$_"} ) {
			my @grouped = ( split /:/x, $self->{'system'}->{"fieldgroup$_"} );
			@groupedfields = split /,/x, $grouped[1] if $field eq $grouped[0];
		}
	}
	return @groupedfields;
}

sub is_valid_operator {
	my ( $self, $value ) = @_;
	my @operators = OPERATORS;
	return ( any { $value eq $_ } @operators ) ? 1 : 0;
}

sub search_users {
	my ( $self, $name, $operator, $text, $table ) = @_;
	my ( $field, $suffix ) = split / /, $name;
	$suffix =~ s/[\(\)\s]//gx;
	my $qry = 'SELECT id FROM users WHERE ';
	my $equals = $suffix ne 'id' ? "upper($suffix) = upper('$text')" : "$suffix = '$text'";
	my $contains =
	  $suffix ne 'id' ? "upper($suffix) LIKE upper('\%$text\%')" : "CAST($suffix AS text) LIKE ('\%$text\%')";
	my $starts_with =
	  $suffix ne 'id' ? "upper($suffix) LIKE upper('$text\%')" : "CAST($suffix AS text) LIKE ('$text\%')";
	my $ends_with = $suffix ne 'id' ? "upper($suffix) LIKE upper('\%$text')" : "CAST($suffix AS text) LIKE ('\%$text')";
	my %modify = (
		'NOT'         => "NOT $equals",
		'contains'    => $contains,
		'starts with' => $starts_with,
		'ends with'   => $ends_with,
		'NOT contain' => "NOT $contains",
		'='           => $equals
	);

	if ( $modify{$operator} ) {
		$qry .= $modify{$operator};
	} else {
		$qry .= "$suffix $operator '$text'";
	}
	my $local_ids = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	if ($suffix ne 'id'){
	my $remote_db_ids =
	  $self->{'datastore'}
	  ->run_query( 'SELECT DISTINCT user_db FROM users WHERE user_db IS NOT NULL', undef, { fetch => 'col_arrayref' } );
	foreach my $user_db_id (@$remote_db_ids) {
		my $user_db = $self->{'datastore'}->get_user_db($user_db_id);
		( my $user_qry = $qry ) =~ s/^SELECT\ id/SELECT user_name/x;
		my $remote_user_names =
		  $self->{'datastore'}->run_query( $user_qry, undef, { db => $user_db, fetch => 'col_arrayref' } );
		foreach my $user_name (@$remote_user_names) {

			#Only add user if exists in local database with the same user_db
			my $user_info = $self->{'datastore'}->get_user_info_from_username($user_name);
			push @$local_ids, $user_info->{'id'} if $user_info->{'id'};
		}
	}}
	$local_ids = [-999] if !@$local_ids;    #Need to return an integer but not 0 since this is actually the setup user.
	local $" = "' OR $table.$field = '";
	return "($table.$field = '@$local_ids')";
}

#returns 1 if error
sub check_format {
	my ( $self, $data, $error_ref ) = @_;
	my $clean_fieldname = $data->{'clean_fieldname'} // $data->{'field'};
	my $error;
	if ( lc( $data->{'text'} ) ne 'null' && defined $data->{'type'} ) {
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname( $data->{'field'} );
		my $display_field = ( $metafield // $clean_fieldname );
		my %checks = (
			int => sub {
				if ( !BIGSdb::Utils::is_int( $data->{'text'}, { do_not_check_range => 1 } ) ) {
					$error = qq($display_field is an integer field.);
				} elsif ( $data->{'text'} > MAX_INT ) {
					my $max = MAX_INT;
					$error = qq($display_field is too big (largest allowed integer is $max).);
				}
			},
			bool => sub {
				if ( !BIGSdb::Utils::is_bool( $data->{'text'} ) ) {
					$error = qq($display_field is a boolean (true/false) field.);
				}
			},
			float => sub {
				if ( !BIGSdb::Utils::is_float( $data->{'text'} ) ) {
					$error = qq($display_field is a floating point number field.);
				}
			},
			date => sub {
				my %invalid_operator = map { $_ => 1 } ( 'contains', 'NOT contain', 'starts with', 'ends with' );
				my $operator = $data->{'operator'};
				if ( $invalid_operator{$operator} ) {
					$error = qq(Searching a date field cannot be done for the '$operator' operator.);
				} elsif ( !BIGSdb::Utils::is_date( $data->{'text'} ) ) {
					$error = qq($display_field is a date field - )
					  . q(should be in yyyy-mm-dd format (or 'today' / 'yesterday').);
				}
			}
		);
		foreach my $type (qw(int bool float date)) {
			if ( $data->{'type'} =~ /$type/x ) {
				$checks{$type}->();
				last;
			}
		}
	}
	if ( !$error && !$self->is_valid_operator( $data->{'operator'} ) ) {
		$error = qq($data->{'operator'} is not a valid operator.);
	}
	push @$error_ref, $error if $error;
	return $error ? 1 : 0;
}

sub clean_list {
	my ( $self, $data_type, $list ) = @_;
	my @new_list;
	foreach my $value (@$list) {
		$value =~ tr/[\x{ff10}-\x{ff19}]/[0-9]/;    #Convert Unicode full width integers
		next if lc($data_type) =~ /^int/x  && !BIGSdb::Utils::is_int($value);
		next if lc($data_type) =~ /^bool/x && !BIGSdb::Utils::is_bool($value);
		next if lc($data_type) eq 'date'  && !BIGSdb::Utils::is_date($value);
		next if lc($data_type) eq 'float' && !BIGSdb::Utils::is_float($value);
		push @new_list, uc($value);
	}
	return \@new_list;
}

sub process_value {
	my ( $self, $value_ref ) = @_;
	$$value_ref //= q();
	$$value_ref =~ s/^\s*//x;
	$$value_ref =~ s/\s*$//x;
	$$value_ref =~ s/\\/\\\\/gx;
	$$value_ref =~ s/'/\\'/gx;
	$$value_ref =~ tr/[\x{ff10}-\x{ff19}]/[0-9]/;    #Convert Unicode full width integers
	return;
}
1;
