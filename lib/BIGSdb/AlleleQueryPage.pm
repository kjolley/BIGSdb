#Written by Keith Jolley
#Copyright (c) 2010, University of Oxford
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
package BIGSdb::AlleleQueryPage;
use strict;
use base qw(BIGSdb::QueryPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{'field_help'} = 0;
	$self->{'jQuery'}     = 1;
}

sub get_javascript {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $buffer = << "END";
\$(function () {
 \$("#locus").change(function(){
 	var locus_name = \$("#locus").val();
 	locus_name = locus_name.replace("cn_","");
 	var url = '$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=alleleQuery&locus=' + locus_name;
 	location.href=url;
  });
});
END
	return $buffer;
}

sub print_content {
	my ($self) = @_;
	my $system = $self->{'system'};
	my $q      = $self->{'cgi'};
	my $locus  = $q->param('locus');
	$locus =~ s/^cn_//;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	$locus =~ tr/_/ /;
	print "<h1>Query $locus";
	print " ($locus_info->{'common_name'})" if $locus_info->{'common_name'};
	print " sequences - $system->{'description'} database</h1>\n";
	my $qry;
	if (   !defined $q->param('currentpage')
		|| $q->param('pagejump') eq '1'
		|| $q->param('First') )
	{
		$self->_print_query_interface();
	}
	if (   defined $q->param('query')
		or defined $q->param('t1') )
	{
		if ( $q->param('locus') eq '' ) {
			print "<div class=\"box\" id=\"statusbad\"><p>Please select locus.</p></div>\n";
		} else {
			$self->_run_query();
		}
	} else {
		print "<p />\n";
	}
}

sub _print_query_interface {
	my ($self)     = @_;
	my $system     = $self->{'system'};
	my $prefs      = $self->{'prefs'};
	my $q          = $self->{'cgi'};
	my $locus      = $q->param('locus');
	my $attributes = $self->{'datastore'}->get_table_field_attributes('sequences');
	my ( @selectitems, @orderby );
	foreach (@$attributes) {
		next if $_->{'name'} eq 'locus';
		if ( $_->{'name'} eq 'sender' || $_->{'name'} eq 'curator' || $_->{'name'} eq 'user_id' ) {
			push @selectitems, "$_->{'name'} (id)";
			push @selectitems, "$_->{'name'} (surname)";
			push @selectitems, "$_->{'name'} (first_name)";
			push @selectitems, "$_->{'name'} (affiliation)";
		} else {
			push @selectitems, $_->{'name'};
		}
		push @orderby, $_->{'name'};
	}
	my %cleanedSelectItems;
	foreach my $item (@selectitems) {
		( $cleanedSelectItems{$item} = $item ) =~ tr/_/ /;
	}
	if ($locus) {
		my $sql =
		  $self->{'db'}->prepare(
"SELECT field,description,value_format,required,length,option_list FROM locus_extended_attributes WHERE locus=? ORDER BY field_order"
		  );
		eval { $sql->execute($locus); };
		if ($@) {
			$logger->error("Can't execute $@");
		}
		while ( my ( $field, $desc, $format, $length, $optlist ) = $sql->fetchrow_array ) {
			my $item = "extatt_$field";
			push @selectitems, $item;
			( $cleanedSelectItems{$item} = $item ) =~ s/^extatt_//;
			$cleanedSelectItems{$item} =~ tr/_/ /;
		}
	}
	print "<div class=\"box\" id=\"queryform\">\n";
	my ($display_loci,$cleaned) = $self->{'datastore'}->get_locus_list;
	unshift @$display_loci, '';
	print $q->startform();
	$cleaned->{''} = 'Please select ...';
	print "<p><b>Locus: </b>";
	print $q->popup_menu( -name => 'locus', -id => 'locus', -values => $display_loci, -labels => $cleaned );
	print " <span class=\"comment\">Page will reload when changed</span></p>";
	foreach (qw (db page)) {
		print $q->hidden($_);
	}
	if ($q->param('locus')){
		my $locus = $q->param('locus');
		my $desc_exists = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM locus_descriptions WHERE locus=?",$locus)->[0];
		if ($desc_exists){
			print "<ul><li><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=locusInfo&amp;locus=$locus\">Further information</a> is available for this locus.</li></ul>\n";
		}
	}
	print "<p>Please enter your search criteria below (or leave blank and submit to return all records).</p>";
	print "<div style=\"white-space:nowrap\">";
	print "<fieldset>\n<legend>Locus fields</legend>\n";
	print "<label for=\"c0\">Combine searches with: </label>\n";
	print $q->popup_menu( -name => 'c0', -id => 'c0', -values => [ "AND", "OR" ] );
	my $combfields = $prefs->{'combfields_locus'};
	print "<ul>\n";

	for ( my $i = 1 ; $i <= $combfields ; $i++ ) {
		print "<li><span style=\"white-space:nowrap\">\n";
		print $q->popup_menu( -name => "s$i", -values => [@selectitems], -labels => \%cleanedSelectItems, -class => 'fieldlist' );
		print $q->popup_menu( -name => "y$i", -values => [ "=", "contains", ">", "<", "NOT", "NOT contain" ] );
		print $q->textfield( -name => "t$i", -class => 'value_entry' );
		if ( $i == 1 ) {
			print
" <a class=\"tooltip\" title=\"Search values - Empty field values can be searched using the term \&lt;&shy;blank\&gt; or null. <p /><h3>Number of fields</h3>The number of fields that can be combined can be set in the options page.\">&nbsp;<i>i</i>&nbsp;</a>"
			  if $self->{'prefs'}->{'tooltips'};
		}
		print "</span></li>\n";
	}
	print "</ul>\n";
	print "</fieldset>\n";
	print "<fieldset class=\"display\">\n";
	print "<ul>\n<li><span style=\"white-space:nowrap\">\n<label for=\"order\" class=\"display\">Order by: </label>\n";
	print $q->popup_menu( -name => 'order', -id => 'order', -values => [@orderby], -labels => \%cleanedSelectItems );
	print $q->popup_menu( -name => 'direction', -values => [ 'ascending', 'descending' ], -default => 'ascending' );
	print "</span></li>\n<li><span style=\"white-space:nowrap\">\n";

	if ( $q->param('displayrecs') ) {
		$prefs->{'displayrecs'} = $q->param('displayrecs');
	}
	print "<label for=\"displayrecs\" class=\"display\">Display: </label>\n";
	print $q->popup_menu(
		-name    => 'displayrecs',
		-id      => 'displayrecs',
		-values  => [ '10', '25', '50', '100', '200', '500', 'all' ],
		-default => $prefs->{'displayrecs'}
	);
	print " records per page&nbsp;";
	print
" <a class=\"tooltip\" title=\"Records per page - Analyses use the full query dataset, rather than just the page shown.\">&nbsp;<i>i</i>&nbsp;</a>"
	  if $self->{'prefs'}->{'tooltips'};
	print "</span></li>\n\n";
	my $locus_clause = "&amp;locus=$locus" if $locus;
	print
"</ul><span style=\"float:left\"><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleQuery$locus_clause\" class=\"resetbutton\">Reset</a></span><span style=\"float:right\">";
	print $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
	print "</span></fieldset>\n";
	print "</div>\n";
	my %labels;
	my @username;
	my $qry = "SELECT id,first_name,surname FROM users WHERE id>0 ORDER BY surname ";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute(); };

	if ($@) {
		$logger->error("Can't execute: $qry");
	} else {
		$logger->debug("Query: $qry");
	}
	while ( my @data = $sql->fetchrow_array() ) {
		push @username, $data[0];
		$labels{ $data[0] } = "$data[2], $data[1]";
	}
	print "<div style=\"white-space:nowrap\"><fieldset><legend>Filter query by</legend>\n";
	print "<ul>\n";
	print "<li><span style=\"white-space:nowrap\">";
	print "<label for=\"status_list\">status: </label>\n";
	print $q->popup_menu( -name => 'status_list', -id => 'status_list', -values => [ '', 'trace checked', 'trace not checked' ] );
	print "</span></li>\n";
	print "</ul>\n</fieldset></div>";
	print $q->endform;
	print "</div>\n";
}

sub _run_query {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $system = $self->{'system'};
	my $prefs  = $self->{'prefs'};
	my ( $qry, $qry2 );
	my @errors;
	my $combfields = $prefs->{'combfields_locus'};
	my $attributes = $self->{'datastore'}->get_table_field_attributes('sequences');
	my $locus      = $q->param('locus');
	if ($locus =~ /^cn_(.+)$/){
		$locus = $1;
	}
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		$logger->error("Invalid locus $locus");
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid locus selected.</p></div>\n";
		return;
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( !defined $q->param('query') ) {
		my $andor       = $q->param('c0');
		my $first_value = 1;
		my $extatt_sql  = $self->{'db'}->prepare("SELECT * FROM locus_extended_attributes WHERE locus=? AND field=?");
		for ( my $i = 1 ; $i <= $combfields ; $i++ ) {
			if ( $q->param("t$i") ne '' ) {
				my $field    = $q->param("s$i");
				my $operator = $q->param("y$i");
				my $text     = $q->param("t$i");
				$text =~ s/^\s*//;
				$text =~ s/\s*$//;
				$text =~ s/'/\\'/g;
				if ( $field =~ /^extatt_(.*)$/ ) {

					#search by extended attribute
					$field = $1;
					eval { $extatt_sql->execute( $locus, $field ); };
					if ($@) {
						$logger->error("Can't execute $@");
					}
					my $thisfield = $extatt_sql->fetchrow_hashref;
					if (   $text ne '<blank>'
						&& $text ne 'null'
						&& ( $thisfield->{'value_format'} eq 'integer' )
						&& !BIGSdb::Utils::is_int($text) )
					{
						push @errors, "$field is an integer field.";
						next;
					} elsif ( $text ne '<blank>'
						&& $text ne 'null'
						&& lc( $thisfield->{'value_format'} ) eq 'date'
						&& !BIGSdb::Utils::is_date($text) )
					{
						push @errors, "$field is a date field - should be in yyyy-mm-dd format (or 'today' / 'yesterday').";
						next;
					} elsif ( !$self->is_valid_operator($operator) ) {
						push @errors, "$operator is not a valid operator.";
						next;
					}
					my $modifier = '';
					if ( $i > 1 && !$first_value ) {
						$modifier = " $andor ";
					}
					$first_value = 0;
					my $std_clause = "$modifier (allele_id IN (SELECT allele_id FROM sequence_extended_attributes WHERE ";
					if ( $operator eq 'NOT' ) {
						if ( $text eq '<blank>' || $text eq 'null' ) {
							$qry .=
"$modifier (allele_id IN (select allele_id FROM sequence_extended_attributes WHERE locus='$locus' AND field='$field'))";
						} else {
							$qry .= $std_clause;
							if ( $thisfield->{'value_format'} eq 'integer' ) {
								$qry .= "locus='$locus' AND field='$field' AND NOT CAST(value AS text) = '$text'))";
							} else {
								$qry .= "locus='$locus' AND field='$field' AND NOT upper(value) = upper('$text')))";
							}
						}
					} elsif ( $operator eq "contains" ) {
						$qry .= $std_clause;
						if ( $thisfield->{'value_format'} eq 'integer' ) {
							$qry .= "locus='$locus' AND field='$field' AND CAST(value AS text) LIKE '\%$text\%'))";
						} else {
							$qry .= "locus='$locus' AND field='$field' AND upper(value) LIKE upper('\%$text\%')))";
						}
					} elsif ( $operator eq "NOT contain" ) {
						$qry .= $std_clause;
						if ( $thisfield->{'value_format'} eq 'integer' ) {
							$qry .= "locus='$locus' AND field='$field' AND NOT CAST(value AS text) LIKE '\%$text\%'))";
						} else {
							$qry .= "locus='$locus' AND field='$field' AND NOT upper(value) LIKE upper('\%$text\%')))";
						}
					} elsif ( $operator eq '=' ) {
						if ( $text eq '<blank>' || $text eq 'null' ) {
							$qry .=
"$modifier (allele_id NOT IN (select allele_id FROM sequence_extended_attributes WHERE locus='$locus' AND field='$field'))";
						} else {
							$qry .= $std_clause;
							if ( lc( $thisfield->{'value_format'} ) eq 'text' ) {
								$qry .= "locus='$locus' AND field='$field' AND upper(value)=upper('$text')))";
							} else {
								$qry .= "locus='$locus' AND field='$field' AND value='$text'))";
							}
						}
					} else {
						$qry .= $std_clause;
						$qry .= "locus='$locus' AND field='$field' AND value $operator '$text'))";
					}
				} else {
					my $thisfield;
					foreach (@$attributes) {
						if ( $_->{'name'} eq $field ) {
							$thisfield = $_;
							last;
						}
					}
					if (   $text ne '<blank>'
						&& $text ne 'null'
						&& ( $thisfield->{'type'} eq 'int' )
						&& !BIGSdb::Utils::is_int($text) )
					{
						push @errors, "$field is an integer field.";
						next;
					} elsif ( $text ne '<blank>'
						&& $text ne 'null'
						&& lc( $thisfield->{'type'} ) eq 'date'
						&& !BIGSdb::Utils::is_date($text) )
					{
						push @errors, "$field is a date field - should be in yyyy-mm-dd format (or 'today' / 'yesterday').";
						next;
					} elsif ( !$self->is_valid_operator($operator) ) {
						push @errors, "$operator is not a valid operator.";
						next;
					}
					my $modifier = '';
					if ( $i > 1 && !$first_value ) {
						$modifier = " $andor ";
					}
					$first_value = 0;
					if ( $field =~ /(.*) \(id\)$/
						&& !BIGSdb::Utils::is_int($text) )
					{
						push @errors, "$field is an integer field.";
						next;
					}
					if (   $field =~ /(.*) \(id\)$/
						|| $field =~ /(.*) \(surname\)$/
						|| $field =~ /(.*) \(first_name\)$/
						|| $field =~ /(.*) \(affiliation\)$/ )
					{
						$qry .= $modifier . $self->search_users( $field, $operator, $text, 'sequences' );
					} else {
						if ( $operator eq 'NOT' ) {
							if ( $text eq '<blank>' || $text eq 'null' ) {
								$qry .= $modifier . "$field is not null";
							} else {
								if ( $thisfield->{'type'} eq 'int' ) {
									$qry .= $modifier . "NOT CAST($field AS text) = '$text'";
								} else {
									$qry .= $modifier . "NOT upper($field) = upper('$text')";
								}
							}
						} elsif ( $operator eq "contains" ) {
							if ( $thisfield->{'type'} eq 'int' ) {
								$qry .= $modifier . "CAST($field AS text) LIKE '\%$text\%'";
							} else {
								$qry .= $modifier . "upper($field) LIKE upper('\%$text\%')";
							}
						} elsif ( $operator eq "NOT contain" ) {
							if ( $thisfield->{'type'} eq 'int' ) {
								$qry .= $modifier . "NOT CAST($field AS text) LIKE '\%$text\%'";
							} else {
								$qry .= $modifier . "NOT upper($field) LIKE upper('\%$text\%')";
							}
						} elsif ( $operator eq '=' ) {
							if ( lc( $thisfield->{'type'} ) eq 'text' ) {
								$qry .= $modifier
								  . ( ( $text eq '<blank>' || $text eq 'null' ) ? "$field is null" : "upper($field) = upper('$text')" );
							} else {
								$qry .= $modifier . ( ( $text eq '<blank>' || $text eq 'null' ) ? "$field is null" : "$field = '$text'" );
							}
						} else {
							if ( $field eq 'allele_id' && $locus_info->{'allele_id_format'} eq 'integer' ) {
								$qry .= $modifier . "CAST($field AS integer) $operator '$text'";
							} else {
								$qry .= $modifier . "$field $operator '$text'";
							}
						}
					}
				}
			}
		}
		$qry2 = "SELECT * FROM sequences WHERE locus='$locus' AND ($qry)";
		foreach (@$attributes) {
			if ( $q->param( $_->{'name'} . '_list' ) ne '' ) {
				my $value = $q->param( $_->{'name'} . '_list' );
				if ( $qry2 !~ /WHERE \(\)\s*$/ ) {
					$qry2 .= " AND ";
				} else {
					$qry2 = "SELECT * FROM sequences WHERE locus='$locus' AND ";
				}
				$value =~ s/'/\\'/g;
				$qry2 .= ( ( $value eq '<blank>' || $value eq 'null' ) ? "$_ is null" : "$_->{'name'} = '$value'" );
			}
		}
		$qry2 .= " ORDER BY ";
		if ( $q->param('order') eq 'allele_id' && $locus_info->{'allele_id_format'} eq 'integer' ) {
			$qry2 .= "CAST (" . ( $q->param('order') ) . " AS integer)";
		} else {
			$qry2 .= $q->param('order');
		}
		my $dir = $q->param('direction') eq 'descending' ? 'desc' : 'asc';
		$qry2 .= " $dir;";
	} else {
		$qry2 = $q->param('query');
	}
	my @hidden_attributes;
	push @hidden_attributes, 'c0';
	for ( my $i = 1 ; $i <= $self->{'prefs'}->{'combfields'} ; $i++ ) {
		push @hidden_attributes, "s$i", "t$i", "y$i";
	}
	foreach (@$attributes) {
		push @hidden_attributes, $_->{'name'} . '_list';
	}
	push @hidden_attributes, 'locus';
	if (@errors) {
		print "<div class=\"box\" id=\"statusbad\"><p>Problem with search criteria:</p>\n";
		print "<p>@errors</p></div>\n";
	} else {
		$qry2 =~ s/AND \(\)//;
		$self->paged_display( 'sequences', $qry2, '', \@hidden_attributes );
		print "<p />\n";
	}
}
