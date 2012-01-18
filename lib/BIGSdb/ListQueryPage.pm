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
package BIGSdb::ListQueryPage;
use strict;
use warnings;
use 5.010;
use List::MoreUtils qw(uniq);
use base qw(BIGSdb::QueryPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Page qw(LOCUS_PATTERNS);

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { 'general' => 1, 'main_display' => 1, 'isolate_display' => 0, 'analysis' => 0, 'query_field' => 1 };
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "List query - $desc";
}

sub print_content {
	my ($self)    = @_;
	my $system    = $self->{'system'};
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	my $scheme_info;
	my $primary_key;
	if ( $system->{'dbtype'} eq 'sequences' ) {
		if ( !$scheme_id ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No scheme id passed.</p></div>\n";
			return;
		} elsif ( !BIGSdb::Utils::is_int($scheme_id) ) {
			print "<div class=\"box\" id=\"statusbad\">Scheme id must be an integer.</p></div>\n";
			return;
		} else {
			$scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
			if ( !$scheme_info ) {
				print "<div class=\"box\" id=\"statusbad\">Scheme does not exist.</p></div>\n";
				return;
			}
			print "<h1>Query $scheme_info->{'description'} profiles by matching a field against a list</h1>\n";
			eval {
				$primary_key =
				  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )
				  ->[0];
			};
			if ( !$primary_key ) {
				print
"<div class=\"box\" id=\"statusbad\"><p>No primary key field has been set for this scheme.  Profile browsing can not be done until this has been set.</p></div>\n";
				return;
			}
		}
	} else {
		print "<h1>Query $system->{'description'} database matching a field against a list</h1>\n";
	}
	my $qry;
	if ( !defined $q->param('currentpage')
		|| $q->param('First') )
	{
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			$self->_print_query_interface;
		} else {
			$self->_print_query_interface($scheme_id);
		}
	}
	if ( defined $q->param('query')
		or ( $q->param('attribute') && $q->param('list') ) )
	{
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			$self->_run_isolate_query;
		} else {
			$self->_run_profile_query( $scheme_id, $primary_key );
		}
	} else {
		print "<p />\n";
	}
	return;
}

sub _print_query_interface {
	my ( $self, $scheme_id ) = @_;
	my $q = $self->{'cgi'};
	my ( $field_list, $order_list, $labels, $order_labels );
	my @grouped_fields;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		( $order_list, $order_labels ) =
		  $self->get_field_selection_list( { 'isolate_fields' => 1, 'loci' => 1, 'scheme_fields' => 1, 'sender_attributes' => 0, } );
		( $field_list, $labels ) = $self->get_field_selection_list(
			{ 'isolate_fields' => 1, 'loci' => 1, 'scheme_fields' => 1, 'sender_attributes' => 1, 'extended_attributes' => 1 } );
		my $grouped = $self->{'xmlHandler'}->get_grouped_fields;
		foreach (@$grouped) {
			push @grouped_fields, "f_$_";
			( $labels->{"f_$_"} = $_ ) =~ tr/_/ /;
		}
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		foreach (@$fields) {
			push @$field_list, "s_$scheme_id\_$_";
			( $labels->{"s_$scheme_id\_$_"} = $_ ) =~ tr/_/ /;
		}
		my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
		foreach (@$loci) {
			my $locus_info = $self->{'datastore'}->get_locus_info($_);
			push @$field_list, "l_$_";
			$labels->{"l_$_"} = $_;
			$labels->{"l_$_"} .= " ($locus_info->{'common_name'})" if $locus_info->{'common_name'};
		}
		$order_list   = $field_list;
		$order_labels = $labels;
	}
	print "<div class=\"box\" id=\"queryform\">\n";
	print $q->start_form;
	print "<table><tr><td>Please select attribute: ";
	my @select_items = ( @grouped_fields, @$field_list );
	print $q->popup_menu( -name => 'attribute', -values => \@select_items, -labels => $labels );
	print "</td></tr>\n<tr><td>Enter your list of attribute values below (one per line):</td></tr>\n<tr><td>";
	print $q->textarea( -name => 'list', -rows => 10, -cols => 40 );
	print "</td></tr>\n";

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		print
"<tr><td><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=listQuery\" class=\"resetbutton\">Reset</a>";
	} else {
		print
"<tr><td><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=listQuery&amp;scheme_id=$scheme_id\" class=\"resetbutton\">Reset</a>";
	}
	print "&nbsp;&nbsp;Order by: ";
	print $q->popup_menu( -name => 'order', -values => $order_list, -labels => $order_labels );
	print $q->popup_menu( -name => 'direction', -values => [ 'ascending', 'descending' ], -default => 'ascending' );
	print "&nbsp;&nbsp;Display ";
	if ( $q->param('displayrecs') ) {
		$self->{'prefs'}->{'displayrecs'} = $q->param('displayrecs');
	}
	print $q->popup_menu(
		-name    => 'displayrecs',
		-values  => [ '10', '25', '50', '100', '200', '500', 'all' ],
		-default => $self->{'prefs'}->{'displayrecs'}
	);
	print " records per page&nbsp;";
	print
" <a class=\"tooltip\" title=\"Records per page - Analyses use the full query dataset, rather than just the page shown.\">&nbsp;<i>i</i>&nbsp;</a>";
	print "&nbsp;&nbsp;";
	print $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
	print "</td></tr>\n";
	print "</table>\n";
	print $q->hidden($_) foreach qw (page db scheme_id);
	print $q->end_form;
	print "</div>\n";
	return;
}

sub _run_profile_query {
	my ( $self, $scheme_id, $primary_key ) = @_;
	my $q     = $self->{'cgi'};
	my $field = $q->param('attribute');
	my ( $datatype, $fieldtype );
	if ( $field =~ /^l_(.*)$/ || $field =~ /^la_(.*)\|\|/ ) {
		$field     = $1;
		$datatype  = $self->{'datastore'}->get_locus_info($field)->{'allele_id_format'};
		$fieldtype = 'locus';
	} elsif ( $field =~ /^s_(\d+)\_(.*)$/ ) {
		$scheme_id = $1;
		$field     = $2;
		$datatype  = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field )->{'type'};
		$fieldtype = 'scheme_field';
	}
	my @list = split /\n/, $q->param('list');
	my $tempqry;
	@list = uniq @list;
	foreach my $value (@list) {
		$value =~ s/^\s*//;
		$value =~ s/\s*$//;
		$value =~ s/[\r\n]//g;
		$value =~ s/'/\'/g;
		next
		  if ( ( lc($datatype) =~ /^int/ )
			&& !BIGSdb::Utils::is_int($value) );
		next
		  if ( $field =~ /(.*) \(id\)$/
			&& !BIGSdb::Utils::is_int($value) );
		next
		  if ( lc($datatype) eq 'date'
			&& !BIGSdb::Utils::is_date($value) );
		if ($value) {

			if ($tempqry) {
				$tempqry .= " OR ";
			}
			if ( $fieldtype eq 'scheme_field' || $fieldtype eq 'locus' ) {
				( my $cleaned = $field ) =~ s/'/_PRIME_/g;
				$tempqry .=
				  $datatype eq 'text'
				  ? "upper($cleaned)=upper('$value')"
				  : "$cleaned='$value'";
			}
		}
	}
	if ( !$tempqry ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No valid values entered.</p></div>\n";
		return;
	}
	my $qry = "SELECT * FROM scheme_$scheme_id WHERE $tempqry";
	$qry .= " ORDER BY ";
	if ( $q->param('order') =~ /^la_(.*)\|\|/ || $q->param('order') =~ /^l_(.*)/ ) {
		my $locus = $1;
		( my $cleaned = $locus ) =~ s/'/_PRIME_/;
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
			$qry .= "CAST($cleaned AS int)";
		} else {
			$qry .= "$cleaned";
		}
	} elsif ( $q->param('order') =~ /s_\d+_(.*)/ ) {
		my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $1 );
		$qry .= $field_info->{'type'} eq 'integer' ? "CAST($1 AS int)" : $1;
	}
	my $dir = $q->param('direction') eq 'descending' ? 'desc' : 'asc';
	my $pk_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	my $profile_id_field = $pk_field_info->{'type'} eq 'integer' ? "lpad($primary_key,20,'0')" : $primary_key;
	$qry .= " $dir,$profile_id_field;";
	my @hidden_attributes = qw(list attribute scheme_id);
	$self->paged_display( 'profiles', $qry, '', \@hidden_attributes );
	return;
}

sub _run_isolate_query {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $field  = $q->param('attribute');
	my @groupedfields = $self->get_grouped_fields( $field, { strip_prefix => 1 } );
	my ( $datatype, $fieldtype, $scheme_id, $joined_table );
	my @list = split /\n/, $q->param('list');
	@list = uniq @list;
	my $tempqry;
	my $lqry;
	my $extended_isolate_field;
	my @locus_patterns = LOCUS_PATTERNS;

	if ( $field =~ /^f_(.*)$/ ) {
		$field = $1;
		my %thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
		$datatype  = $thisfield{'type'};
		$fieldtype = 'isolate';
	} elsif ( $field ~~ @locus_patterns ) {
		$field    = $1;
		$datatype = $self->{'datastore'}->get_locus_info($field)->{'allele_id_format'};
		$field =~ s/\'/\\'/g;
		$fieldtype = 'locus';
	} elsif ( $field =~ /^s_(\d+)\_(.*)$/ ) {
		$scheme_id = $1;
		$field     = $2;
		$datatype  = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field )->{'type'};
		$fieldtype = 'scheme_field';
		my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
		$joined_table = "SELECT id FROM $self->{'system'}->{'view'}";
		foreach (@$scheme_loci) {
			$joined_table .= " left join allele_designations AS $_ on $_.isolate_id = $self->{'system'}->{'view'}.id";
		}
		$joined_table .= " left join temp_scheme_$scheme_id AS scheme_$scheme_id ON ";
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
			push @temp, "$_.locus=E'$_'";
		}
		$joined_table .= " @temp";
	} elsif ( $field =~ /^e_(.*)\|\|(.*)/ ) {
		$extended_isolate_field = $1;
		$field                  = $2;
		$fieldtype              = 'extended_isolate';
	}
	foreach my $value (@list) {
		$value =~ s/^\s*//;
		$value =~ s/\s*$//;
		$value =~ s/[\r\n]//g;
		$value =~ s/'/\\'/g;
		next
		  if ( ( lc($datatype) =~ /^int/ )
			&& !BIGSdb::Utils::is_int($value) );
		next
		  if ( $field =~ /(.*) \(id\)$/
			&& !BIGSdb::Utils::is_int($value) );
		next
		  if ( lc($datatype) eq 'date'
			&& !BIGSdb::Utils::is_date($value) );
		if ($value) {

			if ($tempqry) {
				$tempqry .= " OR ";
			}
			if ( $fieldtype eq 'isolate' ) {
				if (   $field =~ /(.*) \(id\)$/
					|| $field =~ /(.*) \(surname\)$/
					|| $field =~ /(.*) \(first_name\)$/
					|| $field =~ /(.*) \(affiliation\)$/ )
				{
					$tempqry .= $self->search_users( $field, '=', $value, $self->{'system'}->{'view'} );
				} elsif ( scalar @groupedfields ) {
					$tempqry .= " (";
					my $first = 1;
					for ( my $x = 0 ; $x < scalar @groupedfields ; $x++ ) {
						my %thisfield = $self->{'xmlHandler'}->get_field_attributes( $groupedfields[$x] );
						next if $thisfield{'type'} eq 'int' && !BIGSdb::Utils::is_int($value);
						$tempqry .= ' OR ' if !$first;
						if ( $thisfield{'type'} eq 'int' ) {
							$tempqry .= "$groupedfields[$x] = '$value'";
						} else {
							$tempqry .= "upper($groupedfields[$x]) = upper('$value')";
						}
						$first = 0;
					}
					$tempqry .= ')';
				} elsif ( $field eq $self->{'system'}->{'labelfield'} ) {
					$tempqry .=
"(upper($self->{'system'}->{'labelfield'}) = upper('$value') OR id IN (SELECT isolate_id FROM isolate_aliases WHERE upper(alias) = upper('$value')))";
				} elsif ( $datatype eq 'text' ) {
					$tempqry .= "upper($field) = upper('$value')";
				} else {
					$tempqry .= "$field = '$value'";
				}
			} elsif ( $fieldtype eq 'locus' ) {
				$tempqry .=
				  $datatype eq 'text'
				  ? "(allele_designations.locus=E'$field' AND upper(allele_designations.allele_id) = upper('$value'))"
				  : "(allele_designations.locus=E'$field' AND allele_designations.allele_id = '$value')";
			} elsif ( $fieldtype eq 'scheme_field' ) {
				$tempqry .=
				  $datatype eq 'text'
				  ? "upper($field)=upper('$value')"
				  : "$field='$value'";
			} elsif ( $fieldtype eq 'extended_isolate' ) {
				$tempqry .=
"$extended_isolate_field IN (SELECT field_value FROM isolate_value_extended_attributes WHERE isolate_field='$extended_isolate_field' AND attribute='$field' AND upper(value) = upper('$value'))";
			}
		}
	}
	if ( !$tempqry ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No valid values entered.</p></div>\n";
		return;
	}
	my $qry;
	if ( $fieldtype eq 'isolate' || $extended_isolate_field ) {
		$qry = "SELECT * FROM $self->{'system'}->{'view'} WHERE ($tempqry)";
	} elsif ( $fieldtype eq 'locus' ) {
		$qry =
"SELECT * FROM $self->{'system'}->{'view'} WHERE id IN (select distinct($self->{'system'}->{'view'}.id) FROM $self->{'system'}->{'view'} LEFT JOIN allele_designations ON $self->{'system'}->{'view'}.id=allele_designations.isolate_id WHERE $tempqry)";
	} elsif ( $fieldtype eq 'scheme_field' ) {
		$qry = "SELECT * FROM $self->{'system'}->{'view'} WHERE $self->{'system'}->{'view'}.id IN ($joined_table AND ($tempqry))";
	}
	$qry .= " ORDER BY ";
	if ( $q->param('order') ~~ @locus_patterns ) {
		$qry .= "l_$1";
	} else {
		$qry .= $q->param('order');
	}
	my $dir = $q->param('direction') eq 'descending' ? 'desc' : 'asc';
	$qry .= " $dir,$self->{'system'}->{'view'}.id;";
	my @hidden_attributes = qw(list attribute);
	$self->paged_display( $self->{'system'}->{'view'}, $qry, '', \@hidden_attributes );
	return;
}
1;
