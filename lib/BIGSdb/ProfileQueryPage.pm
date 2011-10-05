#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
package BIGSdb::ProfileQueryPage;
use strict;
use warnings;
use base qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Page qw(LOCUS_PATTERNS);

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (tooltips jQuery);
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Search database by combinations of scheme loci - $desc";
}

sub print_content {
	my ($self) = @_;
	my $system    = $self->{'system'};
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		$scheme_id = -1;
	}
	my $scheme_info = $scheme_id > 0 ? $self->{'datastore'}->get_scheme_info($scheme_id) : undef;
	if (defined $scheme_info->{'description'}){
		$scheme_info->{'description'} =~ s/\&/\&amp;/g;
	} else {
		$scheme_info->{'description'} = '';
	}
	print "<h1>Search $system->{'description'} database by combinations of $scheme_info->{'description'} loci</h1>\n";
	if ( ( !$scheme_info->{'id'} && $scheme_id ) || ( $self->{'system'}->{'dbtype'} eq 'sequences' && !$scheme_id ) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid scheme selected.</p></div>\n";
		return;
	}
	my $qry;
	if ( !defined $q->param('currentpage')
		|| $q->param('First') )
	{
		$self->_print_query_interface($scheme_id);
	}
	if (   defined $q->param('query')
		or defined $q->param('submit') )
	{
		$self->_run_query($scheme_id);
	} else {
		print "<p />\n";
	}
}

sub _print_query_interface {
	my ( $self, $scheme_id ) = @_;
	my $q = $self->{'cgi'};
	print "<div class=\"box\" id=\"queryform\">\n";
	print "<p>Please enter your allelic profile below.  Blank loci will be ignored.</p>\n";
	my $primary_keys;
	if ($scheme_id) {
		$primary_keys =
		  $self->{'datastore'}
		  ->run_list_query( "SELECT field FROM scheme_fields WHERE scheme_id=? AND primary_key ORDER BY field_order", $scheme_id );
	}
	my $loci = $scheme_id ? $self->{'datastore'}->get_scheme_loci($scheme_id) : $self->{'datastore'}->get_loci({ 'query_pref' => 1 });
	my $scheme_fields;
	$scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id) if $scheme_id;
	my @errors;
	if ( $primary_keys && @$primary_keys && $q->param('Autofill') ) {
		my @values;
		foreach (@$primary_keys) {
			my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $_ );
			if ( $scheme_field_info->{'type'} eq 'integer' && !BIGSdb::Utils::is_int( $q->param($_) ) ) {
				push @errors, "$_ is an integer field.";
			}
			push @values, $q->param($_);
		}
		if ( !@errors ) {
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
				try {
					my $loci_values = $self->{'datastore'}->get_scheme($scheme_id)->get_profile_by_primary_keys( \@values );
					my $i           = 0;
					foreach (@$loci) {
						$q->param( "l_$_", $loci_values->[$i] );
						$i++;
					}
				}
				catch BIGSdb::DatabaseConfigurationException with {
					push @errors, "Error retrieving information from remote database - check configuration.";
				};
			} else {
				my @cleaned_loci = @$loci;
				foreach (@cleaned_loci){
					$_ =~ s/'/_PRIME_/g;
				}
				local $" = ',';
				my $qry = "SELECT @cleaned_loci FROM scheme_$scheme_id WHERE $primary_keys->[0]=?";
				my $sql = $self->{'db'}->prepare($qry);
				eval { $sql->execute(@values) };
				if ($@) {
					$logger->error("Can't retrieve loci from scheme view $@");
				} else {
					my $loci_values = $sql->fetchrow_hashref;
					foreach (@$loci) {
						(my $cleaned = $_) =~ s/'/_PRIME_/g;
						$q->param( "l_$_", $loci_values->{ lc($cleaned) } );
					}
				}
			}
		}
	}
	print $q->start_form;
	print "<table><tr><td style=\"vertical-align:top\">" if $primary_keys && @$primary_keys;	
	print "<div class=\"scrollable\">\n";
	print "<table class=\"queryform\">";
	my $i = 0;
	my ( $header_row, $form_row );
	my $all_integers = 1;
	foreach (@$loci) {
		my $locus_info = $self->{'datastore'}->get_locus_info($_);
		if ( $locus_info->{'allele_id_format'} ne 'integer' ) {
			$all_integers = 0;
			last;
		}
	}
	my $max_per_row;
	if ( $primary_keys && @$primary_keys ) {
		$max_per_row = $all_integers ? 7 : 4;
	} else {
		$max_per_row = $all_integers ? 14 : 7;
	}
	my $alias_sql;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$alias_sql = $self->{'db'}->prepare("SELECT alias FROM locus_aliases WHERE locus=? ORDER BY alias");
	}
	my @display_loci;
	my (%label);
	foreach (@$loci) {
		push @display_loci, "l_$_";
		my $cleaned_locus = $self->clean_locus($_);
		my $locus_info = $self->{'datastore'}->get_locus_info($_);
		$cleaned_locus .= " ($locus_info->{'common_name'})" if $locus_info->{'common_name'};
		$label{"l_$_"} = $cleaned_locus;
		if ( !$scheme_id && $self->{'prefs'}->{'locus_alias'} && $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			eval { $alias_sql->execute($_); };
			if ($@) {
				$logger->error("Can't execute $@");
			} else {
				while ( my ($alias) = $alias_sql->fetchrow_array ) {
					my $value = "la_$_||$alias";
					push @display_loci, $value;
					$alias =~ tr/_/ /;
					$label{$value} = "$alias<br /><span class=\"comment\">[$cleaned_locus]</span>";
				}
			}
		}
	}
	foreach (@display_loci) {
		if ( $i == $max_per_row ) {
			print "<tr>$header_row</tr>\n";
			print "<tr>$form_row</tr>\n";
			undef $header_row;
			undef $form_row;
			$i = 0;
		}
		my $class = $all_integers ? 'int_entry' : 'allele_entry';
		$header_row .= "<th class=\"$class\">$label{$_}</th>";
		$form_row   .= "<td>";		
		$" = ' ';
		$form_row .= $q->textfield( -name => "$_", -class => $class, -style => 'text-align:center' );
		$form_row .= "</td>\n";
		$i++;
	}
	print "<tr>$header_row</tr>\n";
	print "<tr>$form_row</tr>\n";
	print "</table></div>\n";
	print "<table>\n";
	
	
	if ($self->{'system'}->{'dbtype'} eq 'isolates' && $self->{'prefs'}->{'dropdownfields'}->{'projects'} ) {
		my $sql = $self->{'db'}->prepare("SELECT id, short_description FROM projects ORDER BY short_description");
		eval { $sql->execute };
		$logger->error($@) if $@;
		my ( @project_ids, %labels );
		while ( my ( $id, $desc ) = $sql->fetchrow_array ) {
			push @project_ids, $id;
			$labels{$id} = $desc;
		}
		if (@project_ids) {
			print "<tr><td style=\"text-align:right;padding-left:1em\">";
			print "Project filter: </td><td style=\"text-align:left\">";
			print $q->popup_menu( -name => 'project_list', -values => ['', @project_ids], -labels => \%labels, -class => 'filter' );
			print
" <a class=\"tooltip\" title=\"project filter - Click the checkbox and select a project to filter your search to only those isolates belonging to it.\">&nbsp;<i>i</i>&nbsp;</a>";
			print "</td></tr>\n";
		}
	}
	
	
	print "<tr><td style=\"text-align:right\">Type of search: </td><td>\n";
	my ( @values, %labels );
	push @values, 0;

	for ( my $i = scalar @$loci ; $i > 0 ; $i-- ) {
		push @values, $i;
		$labels{$i} = "$i or more matches";
	}
	$labels{0} = 'Exact or nearest match';
	$labels{ scalar @$loci } = 'Exact match only';
	print $q->popup_menu( -name => 'matches', -values => [@values], -labels => \%labels );
	print "</td></tr>\n";
	print "<tr><td style=\"text-align:right\">Order by: </td><td>\n";
	my ($order_by,$dropdown_labels);
	if ($self->{'system'}->{'dbtype'} eq 'isolates'){
		($order_by,$dropdown_labels) = $self->get_field_selection_list( {
				'isolate_fields' => 1,
				'loci' => 1,
				'scheme_fields' => 1 
				});
	} else {
		my $order_by_temp;
		push @$order_by_temp, @$primary_keys;
		foreach ( @$loci,@$scheme_fields){
			push @$order_by_temp, $_ if $_ ne $primary_keys->[0];
		}	
		foreach my $item (@$order_by_temp) {
			$dropdown_labels->{"f_$item"} = $item;		 
			push @$order_by, "f_$item";
			my $locus_info = $self->{'datastore'}->get_locus_info($item);
			$dropdown_labels->{"f_$item"} .= " ($locus_info->{'common_name'})" if $locus_info->{'common_name'};
			$dropdown_labels->{"f_$item"} =~ tr/_/ /;
		}
	}
	print $q->popup_menu( -name => 'order', -values => $order_by, -labels => $dropdown_labels );
	print $q->popup_menu( -name => 'direction', -values => [ 'ascending', 'descending' ], -default => 'ascending' );
	print "</td></tr>\n";
	print
"<tr><td><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=profiles&amp;scheme_id=$scheme_id\" class=\"resetbutton\">Reset</a>";
	print "&nbsp;&nbsp;Display: </td><td>\n";
	print $q->popup_menu(
		-name    => 'displayrecs',
		-values  => [ '10', '25', '50', '100', '200', '500', 'all' ],
		-default => $self->{'prefs'}->{'displayrecs'}
	);
	print " records per page";
	print
" <a class=\"tooltip\" title=\"Records per page - Analyses use the full query dataset, rather than just the page shown.\">&nbsp;<i>i</i>&nbsp;</a>";
	print "&nbsp;&nbsp;";
	print $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
	print "</td></tr>\n";
	print "</table>\n";

	print $q->hidden($_) foreach qw (db page scheme_id);
	print $q->hidden( 'sent', 1 );
	if ( $primary_keys && @$primary_keys ) {
		print "</td><td style=\"padding-left:2em; vertical-align:top\">";
		print "<p>Autofill profile by searching remote database.</p>\n";
		print "<table>\n";
		my $first = 1;
		foreach (@$primary_keys) {
			print "<tr><td style=\"text-align:right\">$_: </td><td>";
			print $q->textfield( -name => $_, -class => "allele_entry" );
			print $q->submit( -name => 'Autofill', -class => 'submit' ) if $first;
			$first = 0;
			print "</td></tr>";
		}
		print "</table>\n";
		print "</td></tr></table>";
	}
	print $q->end_form;
	print "</div>\n";
	if (@errors) {
		$" = '<br />';
		print "<div class=\"box\" id=\"statusbad\"><p>Problem with search criteria:</p><p>@errors</p></div>\n";
	}
}

sub _run_query {
	my ( $self, $scheme_id ) = @_;
	my $q      = $self->{'cgi'};
	my $system = $self->{'system'};
	my $qry;
	my $msg;
	my @errors;
	my $count;
	if ( !defined $q->param('query') ) {
		my @params = $q->param;
		my @loci;
		my %values;
		my @patterns = LOCUS_PATTERNS;
		foreach (@params) {
			if ( $_ ~~ @patterns ) {
				if ( $q->param($_) ne '') {
					push @loci, $1;
					if ( $values{$1} && $q->param($_) && $values{$1} ne $q->param($_) ) {
						my $aliases =
						  $self->{'datastore'}->run_list_query( "SELECT alias FROM locus_aliases WHERE locus=? ORDER BY alias", $1 );
						local $" = ', ';
						push @errors,
"Locus $1 has been defined with more than one value (due to an alias for this locus also being used). The following alias(es) exist for this locus: @$aliases";
						next;
					}
					$values{$1} = $q->param($_);
				}
			}
		}
		my ( @lqry, @lqry_blank );
		foreach my $locus (@loci) {
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			$values{$locus} = defined $values{$locus} ? $values{$locus} : '';
			$values{$locus} =~ s/^\s*//;
			$values{$locus} =~ s/\s*$//;
			$values{$locus} =~ s/'/\\'/g;
			(my $cleaned_locus = $locus) =~ s/'/\\'/g;
			if ( $values{$locus} ne ''
				&& ( $locus_info->{'allele_id_format'} eq 'integer' )
				&& !BIGSdb::Utils::is_int( $values{$locus} ) )
			{
				push @errors, "$locus is an integer field.";
				next;
			}
			next if $values{$locus} eq '';
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
				push @lqry,
				  $locus_info->{'allele_id_format'} eq 'text'
				  ? "(allele_designations.locus='$cleaned_locus' AND upper(allele_designations.allele_id) = upper('$values{$locus}'))"
				  : "(allele_designations.locus='$cleaned_locus' AND allele_designations.allele_id = '$values{$locus}')";
			} else {
				push @lqry,
				  $locus_info->{'allele_id_format'} eq 'text'
				  ? "(profile_members.locus='$cleaned_locus' AND upper(profile_members.allele_id) = upper('$values{$locus}') AND profile_members.scheme_id=$scheme_id)"
				  : "(profile_members.locus='$cleaned_locus' AND profile_members.allele_id = '$values{$locus}' AND profile_members.scheme_id=$scheme_id)";
			}
		}
		if (@lqry) {
			local $" = ' OR ';
			my $matches = $q->param('matches');
			if ( $matches == scalar @loci ) {
				$matches = scalar @lqry;
			}
			my $lqry;
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
				$lqry =
"(select distinct($system->{'view'}.id) FROM $system->{'view'} LEFT JOIN allele_designations ON $system->{'view'}.id=allele_designations.isolate_id WHERE @lqry";
			} else {
				my $primary_key =
				  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )
				  ->[0];
				$lqry =
"(select distinct(profiles.profile_id) FROM profiles LEFT JOIN profile_members ON profiles.profile_id=profile_members.profile_id AND profiles.scheme_id=profile_members.scheme_id AND profile_members.scheme_id=$scheme_id WHERE scheme_$scheme_id.$primary_key=profiles.profile_id AND (@lqry)";
			}
			if ( $matches == 0 ) {

				#Find out the greatest number of matches
				my $qry;
				if ($self->{'system'}->{'dbtype'} eq 'isolates'){
					$qry = "SELECT COUNT(id) FROM $system->{'view'} LEFT JOIN allele_designations ON $system->{'view'}.id=isolate_id WHERE (@lqry)"; 
					if ( $qry && $self->{'system'}->{'dbtype'} eq 'isolates' && $q->param('project_list') && $q->param('project_list') ne '') {
						my $project_id = $q->param('project_list');
						if ($project_id) {
							local $" = "','";
							$qry .= " AND id IN (SELECT isolate_id FROM project_members WHERE project_id='$project_id')";
						}
					}					
					$qry .= "GROUP BY $system->{'view'}.id ORDER BY count(id) desc LIMIT 1";
				} else {	
					$qry = "SELECT COUNT(profiles.profile_id) FROM profiles LEFT JOIN profile_members ON profiles.profile_id=profile_members.profile_id AND profiles.scheme_id=profile_members.scheme_id AND profile_members.scheme_id=$scheme_id WHERE @lqry GROUP BY profiles.profile_id ORDER BY COUNT(profiles.profile_id) desc LIMIT 1";
				}
				my $match_sql = $self->{'db'}->prepare($qry);
				eval { $match_sql->execute };
				$logger->error($@) if $@;
				my $count = 0;
				while ( my ($match_count) = $match_sql->fetchrow_array ) {
					$count = $match_count if $match_count > $count;
				}
				
				if ($count) {
					$matches = $count;
					my $term   = $count > 1  ? 'loci' : 'locus';
					my $plural = $count == 1 ? ''     : 'es';
					$msg = $matches == scalar @lqry ? "Exact match$plural found ($matches $term)." : "Nearest match: $count $term.";
				}
			}
			$lqry .=
			  $self->{'system'}->{'dbtype'} eq 'isolates'
			  ? " GROUP BY $system->{'view'}.id HAVING count($system->{'view'}.id)>=$matches)"
			  : " GROUP BY profiles.profile_id HAVING count(profiles.profile_id)>=$matches)";
			if ( !$qry ) {
				$qry =
				  $self->{'system'}->{'dbtype'} eq 'isolates'
				  ? "SELECT * FROM $system->{'view'} WHERE id IN $lqry"
				  : "SELECT * FROM scheme_$scheme_id WHERE EXISTS $lqry";
			} else {
				$qry .= " AND ($lqry)";
			}
		}
		
		if ( $qry && $self->{'system'}->{'dbtype'} eq 'isolates' && $q->param('project_list') && $q->param('project_list') ne '' ) {
			my $project_id = $q->param('project_list');
			if ($project_id) {
				local $" = "','";
				$qry .= " AND id IN (SELECT isolate_id FROM project_members WHERE project_id='$project_id')";
			}
		}
		$qry .= " ORDER BY ";
		my $dir = $q->param('direction') eq 'descending' ? 'desc' : 'asc';
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			if ( $q->param('order') =~ /la_(.+)\|\|/ || $q->param('order') =~ /cn_(.+)/) {
				$qry .= "l_$1";
			} else {
				$qry .= $q->param('order');
			}
			$qry .= " $dir,$self->{'system'}->{'view'}.id;";
		} else {
			my $primary_key =
			  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )
			  ->[0];
			my $pk_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
			my $profile_id_field = $pk_info->{'type'} eq 'integer' ? "lpad($primary_key,20,'0')" : $primary_key;
			if ( $q->param('order') =~ /^f_(.*)/ ) {
				my $order_field = $1;
				if ( $order_field eq $primary_key ) {
					$qry .= "$profile_id_field $dir;";
				} elsif ( $self->{'datastore'}->is_locus($order_field) ) {
					my $locus_info = $self->{'datastore'}->get_locus_info($order_field);
					$order_field =~ s/'/_PRIME_/g;
					$qry .= $locus_info->{'allele_id_format'} eq 'integer' ? "CAST($order_field AS int)" : $order_field;
					$qry .= " $dir,$profile_id_field;";
				} elsif ( $self->{'datastore'}->is_scheme_field( $scheme_id, $order_field ) ) {
					my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $order_field );
					$qry .= $field_info->{'type'} eq 'integer' ? "CAST($order_field AS int)" : $order_field;
					$qry .= " $dir,$profile_id_field;";
				}
			}
		}
	} else {
		$qry = $q->param('query');
	}
	if (@errors) {
		local $" = '<br />';
		print "<div class=\"box\" id=\"statusbad\"><p>Problem with search criteria:</p>\n";
		print "<p>@errors</p></div>\n";
	} elsif ( $qry !~ /^ ORDER BY/ ) {
		my @hidden_attributes;
		foreach (qw(scheme matches project_list)) {
			push @hidden_attributes, $_;
		}
		my $loci = $self->{'datastore'}->get_scheme_loci( $q->param('scheme_id') );
		foreach (@$loci) {
			push @hidden_attributes, "l_$_";
		}
		push @hidden_attributes, 'scheme_id';
		$self->paged_display( $self->{'system'}->{'dbtype'} eq 'isolates' ? $self->{'system'}->{'view'} : 'profiles',
			$qry, $msg, \@hidden_attributes, $count );
		print "<p />\n";
	} else {
		print "<div class=\"box\" id=\"statusbad\">Invalid search performed.</div>\n";
	}
	return;
}
1;
