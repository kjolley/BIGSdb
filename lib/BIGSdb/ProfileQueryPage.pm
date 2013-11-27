#Written by Keith Jolley
#Copyright (c) 2010-2013, University of Oxford
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
use 5.010;
use parent qw(BIGSdb::ResultsTablePage);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Page qw(LOCUS_PATTERN);

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (tooltips jQuery);
	$self->{'noCache'} = 1 if ( $self->{'system'}->{'sets'} // '' ) eq 'yes';
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Search database by combinations of scheme loci - $desc";
}

sub print_content {
	my ($self)    = @_;
	my $system    = $self->{'system'};
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	my $desc      = $self->get_db_description;
	say "<h1>Search $desc database by combinations of loci</h1>";
	if ( !defined $q->param('currentpage')
		|| $q->param('First') )
	{
		my $with_pk  = $self->{'system'}->{'dbtype'} eq 'sequences' ? 1 : 0;
		my $all_loci = $self->{'system'}->{'dbtype'} eq 'isolates'  ? 1 : 0;
		return if defined $scheme_id && $self->is_scheme_invalid( $scheme_id, { with_pk => $with_pk, all_loci => $all_loci } );
		$self->print_scheme_section( { with_pk => $with_pk, all_loci => $all_loci } );
		$scheme_id = $q->param('scheme_id');    #Will be set by scheme section method
		$self->_print_query_interface($scheme_id);
	}
	if (   defined $q->param('query_file')
		or defined $q->param('submit') )
	{
		$self->_run_query($scheme_id);
	}
	return;
}

sub _print_query_interface {
	my ( $self, $scheme_id ) = @_;
	my $q = $self->{'cgi'};
	say "<div class=\"box\" id=\"queryform\">";
	my $primary_key;
	if ($scheme_id) {
		my $primary_key_ref =
		  $self->{'datastore'}
		  ->run_simple_query( "SELECT field FROM scheme_fields WHERE scheme_id=? AND primary_key ORDER BY field_order", $scheme_id );
		$primary_key = $primary_key_ref->[0] if ref $primary_key_ref eq 'ARRAY';
	}
	my $set_id = $self->get_set_id;
	my $loci =
	    $scheme_id
	  ? $self->{'datastore'}->get_scheme_loci($scheme_id)
	  : $self->{'datastore'}->get_loci( { query_pref => 1, set_id => $set_id } );
	my $scheme_fields;
	$scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id) if $scheme_id;
	my @errors;
	if ( $primary_key && $q->param('Autofill') ) {
		my @values;
		my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
		if ( $scheme_field_info->{'type'} eq 'integer' && !BIGSdb::Utils::is_int( $q->param($primary_key) ) ) {
			push @errors, "$primary_key is an integer field.";
		}
		push @values, $q->param($primary_key);
		if ( !@errors ) {
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
				try {
					my $loci_values = $self->{'datastore'}->get_scheme($scheme_id)->get_profile_by_primary_keys( \@values );
					foreach my $i ( 0 .. @$loci - 1 ) {
						$q->param( "l_$loci->[$i]", $loci_values->[$i] );
					}
				}
				catch BIGSdb::DatabaseConfigurationException with {
					push @errors, "Error retrieving information from remote database - check configuration.";
				};
			} else {
				my @cleaned_loci = @$loci;
				foreach (@cleaned_loci) {
					$_ =~ s/'/_PRIME_/g;
				}
				local $" = ',';
				my $scheme_view = $self->{'datastore'}->materialized_view_exists($scheme_id) ? "mv_scheme_$scheme_id" : "scheme_$scheme_id";
				my $qry         = "SELECT @cleaned_loci FROM $scheme_view WHERE $primary_key=?";
				my $sql         = $self->{'db'}->prepare($qry);
				eval { $sql->execute(@values) };
				if ($@) {
					$logger->error("Can't retrieve loci from scheme view $@");
				} else {
					my $loci_values = $sql->fetchrow_hashref;
					foreach (@$loci) {
						( my $cleaned = $_ ) =~ s/'/_PRIME_/g;
						$q->param( "l_$_", $loci_values->{ lc($cleaned) } );
					}
				}
			}
		}
	}
	say "<div class=\"scrollable\">";
	say $q->start_form;
	say "<fieldset id=\"profile_fieldset\" style=\"float:left\"><legend>Please enter your allelic profile below.  Blank loci "
	  . "will be ignored.</legend>";
	say "<table class=\"queryform\">";
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
	if ($primary_key) {
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
			say "<tr>$header_row</tr>";
			say "<tr>$form_row</tr>";
			undef $header_row;
			undef $form_row;
			$i = 0;
		}
		my $class = $all_integers ? 'int_entry' : 'allele_entry';
		$header_row .= "<th class=\"$class\">$label{$_}</th>";
		$form_row   .= "<td>";
		$form_row   .= $q->textfield( -name => "$_", -class => $class, -style => 'text-align:center' );
		$form_row   .= "</td>\n";
		$i++;
	}
	say "<tr>$header_row</tr>";
	say "<tr>$form_row</tr>";
	say "</table>";
	say "</fieldset>";
	if ($primary_key) {
		my $remote = $self->{'system'}->{'dbtype'} eq 'isolates' ? ' by searching remote database' : '';
		say "<fieldset id=\"autofill_fieldset\" style=\"float:left\"><legend>Autofill profile$remote</legend>\n<ul>";
		my $first = 1;
		say "<li><label for=\"$primary_key\" class=\"display\">$primary_key: </label>";
		say $q->textfield( -name => $primary_key, -id => $primary_key, -class => "allele_entry" );
		say $q->submit( -name => 'Autofill', -class => 'submit' ) if $first;
		$first = 0;
		say "</li>";
		say "</ul></fieldset>";
	}
	say "<div style=\"clear:both\">";
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $buffer = $self->get_project_filter( { class => 'display' } );
		if ($buffer) {
			say "<fieldset>\n<legend>Restrict included sequences by</legend>";
			say "<ul><li>$buffer</li></ul></fieldset>";
		}
	}
	say "<fieldset id=\"options_fieldset\" style=\"float:left\"><legend>Options</legend>";
	my ( @values, %labels );
	push @values, 0;
	foreach my $i ( reverse 1 .. @$loci ) {
		push @values, $i;
		$labels{$i} = "$i or more matches";
	}
	$labels{0} = 'Exact or nearest match';
	$labels{ scalar @$loci } = 'Exact match only';
	say $self->get_filter( 'matches', \@values, { labels => \%labels, text => 'Search', noblank => 1, class => 'display' } );
	say "</fieldset>";
	say "<fieldset id=\"display_fieldset\" style=\"float:left\"><legend>Display/sort options</legend>";
	say "<ul>\n<li><span style=\"white-space:nowrap\">\n<label for=\"order\" class=\"display\">Order by: </label>";
	my ( $order_by, $dropdown_labels );

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		( $order_by, $dropdown_labels ) = $self->get_field_selection_list( { isolate_fields => 1, loci => 1, scheme_fields => 1 } );
	} else {
		my $order_by_temp;
		push @$order_by_temp, $primary_key;
		foreach ( @$loci, @$scheme_fields ) {
			push @$order_by_temp, $_ if $_ ne $primary_key;
		}
		foreach my $item (@$order_by_temp) {
			$dropdown_labels->{"f_$item"} = $item;
			push @$order_by, "f_$item";
			my $locus_info = $self->{'datastore'}->get_locus_info($item);
			$dropdown_labels->{"f_$item"} .= " ($locus_info->{'common_name'})" if $locus_info->{'common_name'};
			$dropdown_labels->{"f_$item"} =~ tr/_/ /;
		}
	}
	say $q->popup_menu( -name => 'order', -id => 'order', -values => $order_by, -labels => $dropdown_labels );
	say $q->popup_menu( -name => 'direction', -values => [ 'ascending', 'descending' ], -default => 'ascending' );
	say "</span></li>\n<li>";
	say $self->get_number_records_control;
	say "</li></ul></fieldset>";
	say "</div>";
	$self->print_action_fieldset( { scheme_id => $scheme_id } );
	say $q->hidden($_) foreach qw (db page scheme_id);
	say $q->hidden( 'sent', 1 );
	say $q->end_form;
	say "</div></div>";

	if (@errors) {
		local $" = '<br />';
		say "<div class=\"box\" id=\"statusbad\"><p>Problem with search criteria:</p><p>@errors</p></div>";
	}
	return;
}

sub _run_query {
	my ( $self, $scheme_id ) = @_;
	my $q      = $self->{'cgi'};
	my $system = $self->{'system'};
	my $qry;
	my $msg;
	my @errors;
	my $count;
	my $scheme_view;

	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		$scheme_view = $self->{'datastore'}->materialized_view_exists($scheme_id) ? "mv_scheme_$scheme_id" : "scheme_$scheme_id";
	}
	if ( !defined $q->param('query') ) {
		my @params = $q->param;
		my @loci;
		my %values;
		my $pattern = LOCUS_PATTERN;
		foreach (@params) {
			if ( $_ =~ /$pattern/ ) {
				if ( $q->param($_) ne '' ) {
					push @loci, $1;
					if ( $values{$1} && $q->param($_) && $values{$1} ne $q->param($_) ) {
						my $aliases =
						  $self->{'datastore'}->run_list_query( "SELECT alias FROM locus_aliases WHERE locus=? ORDER BY alias", $1 );
						local $" = ', ';
						push @errors, "Locus $1 has been defined with more than one value (due to an alias for this locus also being "
						  . "used). The following alias(es) exist for this locus: @$aliases";
						next;
					}
					$values{$1} = $q->param($_);
				}
			}
		}
		my ( @lqry, @lqry_blank );
		my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
		foreach my $locus (@loci) {
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			$values{$locus} = defined $values{$locus} ? $values{$locus} : '';
			$values{$locus} =~ s/^\s*//;
			$values{$locus} =~ s/\s*$//;
			$values{$locus} =~ s/'/\\'/g;
			( my $cleaned_locus = $locus ) =~ s/'/\\'/g;
			if ( ( $values{$locus} ne '' && $locus_info->{'allele_id_format'} eq 'integer' && !BIGSdb::Utils::is_int( $values{$locus} ) )
				&& !( $scheme_info->{'allow_missing_loci'} && $values{$locus} eq 'N' ) )
			{
				my $msg = $scheme_info->{'allow_missing_loci'} ? ' Arbitrary values (N) may also be used.' : '';
				push @errors, "$locus is an integer field.$msg";
				next;
			}
			next if $values{$locus} eq '';
			my $table = $self->{'system'}->{'dbtype'} eq 'isolates' ? 'allele_designations' : 'profile_members';
			my $locus_qry;
			if ( $values{$locus} eq 'N' ) {
				$locus_qry = "($table.locus=E'$cleaned_locus'";    #don't match allele_id because it can be anything
			} else {
				my $arbitrary_clause = $scheme_info->{'allow_missing_loci'} ? " OR $table.allele_id = 'N'" : '';
				$locus_qry =
				  $locus_info->{'allele_id_format'} eq 'text'
				  ? "($table.locus=E'$cleaned_locus' AND (upper($table.allele_id) = upper(E'$values{$locus}')$arbitrary_clause)"
				  : "($table.locus=E'$cleaned_locus' AND ($table.allele_id = E'$values{$locus}'$arbitrary_clause)";
			}
			$locus_qry .= $self->{'system'}->{'dbtype'} eq 'isolates' ? ')' : " AND profile_members.scheme_id=$scheme_id)";
			push @lqry, $locus_qry;
		}
		if (@lqry) {
			local $" = ' OR ';
			my $matches = $q->param('matches_list');
			$matches = @lqry if $matches == @loci;
			my $lqry;
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
				$lqry = "(select distinct($system->{'view'}.id) FROM $system->{'view'} LEFT JOIN allele_designations ON "
				  . "$system->{'view'}.id=allele_designations.isolate_id WHERE @lqry";
			} else {
				my $primary_key =
				  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )
				  ->[0];
				$lqry =
				    "(select distinct(profiles.profile_id) FROM profiles LEFT JOIN profile_members ON profiles.profile_id="
				  . "profile_members.profile_id AND profiles.scheme_id=profile_members.scheme_id AND profile_members.scheme_id=$scheme_id "
				  . "WHERE $scheme_view.$primary_key=profiles.profile_id AND (@lqry)";
			}
			if ( $matches == 0 ) {    #Find out the greatest number of matches
				my $qry;
				if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
					$qry = "SELECT COUNT(id) FROM $system->{'view'} LEFT JOIN allele_designations ON $system->{'view'}.id=isolate_id "
					  . "WHERE (@lqry)";
					if (   $qry
						&& $self->{'system'}->{'dbtype'} eq 'isolates'
						&& $q->param('project_list')
						&& $q->param('project_list') ne '' )
					{
						my $project_id = $q->param('project_list');
						if ($project_id) {
							local $" = "','";
							$qry .= " AND id IN (SELECT isolate_id FROM project_members WHERE project_id='$project_id')";
						}
					}
					$qry .= "GROUP BY $system->{'view'}.id ORDER BY count(id) desc LIMIT 1";
				} else {
					$qry =
					    "SELECT COUNT(profiles.profile_id) FROM profiles LEFT JOIN profile_members ON profiles.profile_id="
					  . "profile_members.profile_id AND profiles.scheme_id=profile_members.scheme_id AND profile_members.scheme_id="
					  . "$scheme_id WHERE @lqry GROUP BY profiles.profile_id ORDER BY COUNT(profiles.profile_id) desc LIMIT 1";
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
				  ? "SELECT * FROM $system->{'view'} WHERE $system->{'view'}.id IN $lqry"
				  : "SELECT * FROM $scheme_view WHERE EXISTS $lqry";
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
			if ( $q->param('order') =~ /la_(.+)\|\|/ || $q->param('order') =~ /cn_(.+)/ ) {
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
					$qry .=
					  $locus_info->{'allele_id_format'} eq 'integer'
					  ? "to_number(textcat('0', $order_field), text(99999999))"
					  : $order_field;
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
		say "<div class=\"box\" id=\"statusbad\"><p>Problem with search criteria:</p>";
		say "<p>@errors</p></div>";
	} elsif ( $qry !~ /^ ORDER BY/ ) {
		my @hidden_attributes;
		push @hidden_attributes, $_ foreach qw(scheme matches project_list);
		my $loci = $self->{'datastore'}->get_scheme_loci( $q->param('scheme_id') );
		push @hidden_attributes, "l_$_" foreach @$loci;
		push @hidden_attributes, qw(scheme_id matches_list);
		my $table = $self->{'system'}->{'dbtype'} eq 'isolates' ? $self->{'system'}->{'view'} : 'profiles';
		my $args = { table => $table, query => $qry, message => $msg, hidden_attributes => \@hidden_attributes, count => $count };
		$args->{'passed_qry_file'} = $q->param('query_file') if defined $q->param('query_file');
		$self->paged_display($args);
	} else {
		say "<div class=\"box\" id=\"statusbad\">Invalid search performed.</div>";
	}
	return;
}
1;
