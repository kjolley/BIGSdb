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
package BIGSdb::IsolateInfoPage;
use strict;
use warnings;
use base qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
use List::MoreUtils qw(any);
my $logger = get_logger('BIGSdb.Page');
use constant ISOLATE_SUMMARY => 1;
use constant LOCUS_SUMMARY   => 2;

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { 'general' => 1, 'main_display' => 0, 'isolate_display' => 1, 'analysis' => 0, 'query_field' => 0 };
	return;
}

sub initiate {
	my ($self) = @_;
	if ( $self->{'cgi'}->param('no_header') ) {
		$self->{'type'}    = 'no_header';
		$self->{'noCache'} = 1;
		return;
	}
	$self->{$_} = 1 foreach qw(jQuery jQuery.jstree);
	return;
}

sub get_javascript {
	my ($self) = @_;
	return $self->get_tree_javascript;
}

sub _get_child_group_scheme_tables {
	my ( $self, $id, $isolate_id, $locus_info, $locus_alias, $allele_designations, $allele_sequences, $allele_sequence_flags, $td, $level )
	  = @_;
	my $child_groups = $self->{'datastore'}->run_list_query(
"SELECT id FROM scheme_groups LEFT JOIN scheme_group_group_members ON scheme_groups.id=group_id WHERE parent_group_id=? ORDER BY display_order",
		$id
	);
	my $buffer;
	if (@$child_groups) {
		foreach (@$child_groups) {
			my $group_info = $self->{'datastore'}->get_scheme_group_info($_);
			my $new_level  = $level;
			last if $new_level == 10;    #prevent runaway if child is set as the parent of a parental group
			my $field_buffer;
			( $td, $field_buffer ) =
			  $self->_get_group_scheme_tables( $_, $isolate_id, $locus_info, $locus_alias, $allele_designations, $allele_sequences,
				$allele_sequence_flags, $td );
			$buffer .= $field_buffer;
			( $td, $field_buffer ) = $self->_get_child_group_scheme_tables(
				$_,                $isolate_id,            $locus_info, $locus_alias, $allele_designations,
				$allele_sequences, $allele_sequence_flags, $td,         ++$new_level
			);
			$buffer .= $field_buffer;
		}
	}
	return ( $td, $buffer );
}

sub _get_group_scheme_tables {
	my ( $self, $id, $isolate_id, $locus_info, $locus_alias, $allele_designations, $allele_sequences, $allele_sequence_flags, $td ) = @_;
	my $schemes = $self->{'datastore'}->run_list_query(
"SELECT scheme_id FROM scheme_group_scheme_members LEFT JOIN schemes ON schemes.id=scheme_id WHERE group_id=? ORDER BY display_order",
		$id
	);
	my $buffer;
	if (@$schemes) {
		foreach my $scheme_id (@$schemes) {
			next if !$self->{'prefs'}->{'isolate_display_schemes'}->{$scheme_id};
			if ( !$self->{'scheme_shown'}->{$scheme_id} ) {
				( $td, my $field_buffer ) = $self->_get_scheme_fields(
					$scheme_id,        $isolate_id,            $locus_info, $locus_alias, $allele_designations,
					$allele_sequences, $allele_sequence_flags, $td,         $self->{'curate'}
				);
				$buffer .= $field_buffer if $field_buffer;
				$self->{'scheme_shown'}->{$scheme_id} = 1;
			}
		}
	}
	return ( $td, $buffer );
}

sub print_content {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $isolate_id = $q->param('id');
	if ( defined $q->param('group_id') && BIGSdb::Utils::is_int( $q->param('group_id') ) ) {
		my ( $locus_info, $locus_alias, $allele_designations, $allele_sequences, $allele_sequence_flags ) =
		  $self->_get_scheme_attributes($isolate_id);
		my $group_id = $q->param('group_id');
		my $scheme_ids;
		my $td = 1;
		my ( $table_buffer, $buffer );
		if ( $group_id == 0 ) {
			$scheme_ids =
			  $self->{'datastore'}->run_list_query(
				"SELECT id FROM schemes WHERE id NOT IN (SELECT scheme_id FROM scheme_group_scheme_members) ORDER BY display_order");
			foreach (@$scheme_ids) {
				next if !$self->{'prefs'}->{'isolate_display_schemes'}->{$_};
				my $scheme_info = $self->{'datastore'}->get_scheme_info($_);
				( $td, $table_buffer ) = $self->_get_scheme_fields(
					$_,                $isolate_id,            $locus_info, $locus_alias, $allele_designations,
					$allele_sequences, $allele_sequence_flags, 1,           $self->{'curate'}
				);
				$buffer .= $table_buffer if $table_buffer;
			}
		} else {
			( $td, $table_buffer ) =
			  $self->_get_group_scheme_tables( $group_id, $isolate_id, $locus_info, $locus_alias, $allele_designations, $allele_sequences,
				$allele_sequence_flags, $td );
			$buffer .= $table_buffer;
			( $td, $table_buffer ) = $self->_get_child_group_scheme_tables(
				$group_id,         $isolate_id,            $locus_info, $locus_alias, $allele_designations,
				$allele_sequences, $allele_sequence_flags, $td,         1
			);
			$buffer .= $table_buffer if $table_buffer;
		}
		if ($buffer) {
			print "<table style=\"width:100%\">\n$buffer</table>\n";
		}
		return;
	} elsif ( defined $q->param('scheme_id') ) {
		my $scheme_id = $q->param('scheme_id');
		my ( $locus_info, $locus_alias, $allele_designations, $allele_sequences, $allele_sequence_flags ) =
		  $self->_get_scheme_attributes($isolate_id);
		my ( $td, $buffer );
		if ( $scheme_id == -1 ) {
			my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes ORDER BY display_order,id");
			foreach ( @$schemes, 0 ) {
				next if $_ && !$self->{'prefs'}->{'isolate_display_schemes'}->{$_};
				( $td, my $table_buffer ) = $self->_get_scheme_fields(
					$_,                $isolate_id,            $locus_info, $locus_alias, $allele_designations,
					$allele_sequences, $allele_sequence_flags, 1,           $self->{'curate'}
				);
				$buffer .= $table_buffer if $table_buffer;
			}
		} else {
			( $td, $buffer ) = $self->_get_scheme_fields(
				$scheme_id,        $isolate_id,            $locus_info, $locus_alias, $allele_designations,
				$allele_sequences, $allele_sequence_flags, 1,           $self->{'curate'}
			);
		}
		if ($buffer) {
			print "<table style=\"width:100%\">\n$buffer</table>\n";
		}
		return;
	}
	if ( !BIGSdb::Utils::is_int($isolate_id) ) {
		print "<h1>Isolate information: id-$isolate_id</h1>";
		print "<div class=\"box\" id=\"statusbad\"><p>Isolate id must be an integer.</p></div>\n";
		return;
	}
	$self->{'system'}->{'view'} ||= 'isolate';    #in case we're called from a seqdef database
	my $qry = "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute($isolate_id) };
	if ($@) {
		print "<h1>Isolate information: id-$isolate_id</h1>";
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid search performed.</p></div>\n";
		$logger->debug("Can't execute $qry: $@\n");
		return;
	}
	my $data = $sql->fetchrow_hashref;
	if ( !$data ) {
		print "<h1>Isolate information: id-$isolate_id</h1>";
		print "<div class=\"box\" id=\"statusbad\"><p>The database contains no record of this isolate.</p></div>";
		return;
	} elsif ( !$self->is_allowed_to_view_isolate($isolate_id) ) {
		print "<h1>Isolate information</h1>\n";
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account does not have permission to view this record.</p></div>";
		return;
	}
	if ( defined $data->{ $self->{'system'}->{'labelfield'} } && $data->{ $self->{'system'}->{'labelfield'} } ne '' ) {
		my $identifier = $self->{'system'}->{'labelfield'};
		$identifier =~ tr/_/ /;
		print "<h1>Full information on $identifier $data->{lc($self->{'system'}->{'labelfield'})}</h1>";
	} else {
		print "<h1>Full information on id $data->{'id'}</h1>";
	}
	if ( $self->{'cgi'}->param('history') ) {
		print "<div class=\"box\" id=\"resultstable\">\n";
		print "<h2>Update history</h2>\n";
		print
"<p><a href=\"$self->{'system'}->{'script_name'}?page=info&amp;db=$self->{'instance'}&amp;id=$isolate_id\">Back to isolate information</a></p>\n";
		print $self->_get_update_history($isolate_id);
	} else {
		$self->_print_projects($isolate_id);
		print "<div class=\"box\" id=\"resultstable\">\n";
		print $self->get_isolate_record($isolate_id);
	}
	print "</div>\n";
	return;
}

sub _get_update_history {
	my ( $self,    $isolate_id )  = @_;
	my ( $history, $num_changes ) = $self->_get_history($isolate_id);
	my $buffer;
	if ($num_changes) {
		$buffer .= "<table class=\"resultstable\"><tr><th>Timestamp</th><th>Curator</th><th>Action</th></tr>\n";
		my $td = 1;
		foreach (@$history) {
			my $curator_info = $self->{'datastore'}->get_user_info( $_->{'curator'} );
			my $time         = $_->{'timestamp'};
			$time =~ s/:\d\d\.\d+//;
			my $action = $_->{'action'};
			$action =~ s/->/\&rarr;/g;
			$buffer .=
"<tr class=\"td$td\"><td style=\"vertical-align:top\">$time</td><td style=\"vertical-align:top\">$curator_info->{'first_name'} $curator_info->{'surname'}</td><td style=\"text-align:left\">$action</td></tr>\n";
			$td = $td == 1 ? 2 : 1;
		}
		$buffer .= "</table>\n";
	}
	return $buffer;
}

sub get_isolate_summary {
	my ( $self, $id ) = @_;
	return $self->get_isolate_record( $id, ISOLATE_SUMMARY );
}

sub get_loci_summary {
	my ( $self, $id ) = @_;
	return $self->get_isolate_record( $id, LOCUS_SUMMARY );
}

sub get_isolate_record {
	my ( $self, $id, $summary_view ) = @_;
	$summary_view ||= 0;
	my $sql;
	my $buffer;
	my $q      = $self->{'cgi'};
	my $fields = $self->{'xmlHandler'}->get_field_list;
	my $view   = $self->{'system'}->{'view'};
	local $" = ",$view.";
	my $field_string = "$view.@$fields";
	my $qry          = "SELECT $field_string FROM $view WHERE id=?";
	$sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute($id) };

	if ($@) {
		$logger->error("Can't execute $qry; value: $id");
		throw BIGSdb::DatabaseConfigurationException("Invalid search $@");
	}
	my %data = ();
	$sql->bind_columns( map { \$data{$_} } @$fields );    #quicker binding hash to arrayref than to use hashref
	$sql->fetchrow_arrayref;
	if ( !%data ) {
		$logger->error("Record $id does not exist");
		throw BIGSdb::DatabaseNoRecordException("Record $id does not exist");
	}
	my $td = 1;
	$buffer .= "<div class=\"scrollable\"><table class=\"resultstable\">\n";
	if ( $summary_view != LOCUS_SUMMARY ) {
		$buffer .= $self->_get_provenance_fields( $id, \%data, \$td, $summary_view );
		if ( !$summary_view ) {
			$buffer .= $self->_get_samples( $id, \$td, 1 );
			$buffer .= $self->_get_ref_links( $id, \$td );
			$buffer .= $self->_get_seqbin_link( $id, \$td );
		}
	}
	my ( $locus_info, $locus_alias, $allele_designations, $allele_sequences, $allele_sequence_flags ) = $self->_get_scheme_attributes($id);

	#Print loci and scheme information
	if ( !%$allele_designations && !%$allele_sequences ) {
		$buffer .= "</table></div>\n";
		return $buffer;
	}
	my $scheme_group_count = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM scheme_groups")->[0];
	if ( $scheme_group_count || $self->{'curate'} ) {
		$buffer .= "<tr><th style=\"vertical-align:top;padding-top:1em\">Schemes and loci</th><td colspan=\"5\">";
		$buffer .= $self->_get_tree($id);
		$buffer .= "</td></tr>";
		$buffer .= "</table></div>\n";
		return $buffer;
	}
	my $scheme_sql = $self->{'db'}->prepare("SELECT * FROM schemes ORDER BY display_order,id");
	eval { $scheme_sql->execute };
	$logger->error($@) if $@;
	while ( my $scheme = $scheme_sql->fetchrow_hashref ) {
		if ( $self->{'prefs'}->{'isolate_display_schemes'}->{ $scheme->{'id'} } ) {
			( $td, my $field_buffer ) = $self->_get_scheme_fields(
				$scheme->{'id'},   $data{'id'},            $locus_info, $locus_alias, $allele_designations,
				$allele_sequences, $allele_sequence_flags, $td,         $summary_view
			);
			$buffer .= $field_buffer if $field_buffer;
		}
	}

	#Loci not belonging to a scheme
	( $td, my $field_buffer ) =
	  $self->_get_scheme_fields( 0, $data{'id'}, $locus_info, $locus_alias, $allele_designations, $allele_sequences, $allele_sequence_flags,
		$td, $summary_view );
	$buffer .= $field_buffer if $field_buffer;
	$buffer .= "</table></div>";
	return $buffer;
}

sub _get_provenance_fields {
	my ( $self, $isolate_id, $data, $td_ref, $summary_view ) = @_;
	my $buffer;
	my $q          = $self->{'cgi'};
	my $field_list = $self->{'xmlHandler'}->get_field_list;
	my ( %composites, %composite_display_pos );
	my $composite_data = $self->{'datastore'}->run_list_query_hashref("SELECT id,position_after FROM composite_fields");
	foreach (@$composite_data) {
		$composite_display_pos{ $_->{'id'} }  = $_->{'position_after'};
		$composites{ $_->{'position_after'} } = 1;
	}
	my $field_with_extended_attributes;
	if ( !$summary_view ) {
		$field_with_extended_attributes =
		  $self->{'datastore'}->run_list_query("SELECT DISTINCT isolate_field FROM isolate_field_extended_attributes");
	}
	foreach my $field (@$field_list) {
		my $displayfield = $field;
		$displayfield =~ tr/_/ /;
		my %thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
		my $web;
		if ( !defined $data->{$field} ) {
			next;

			#Do not print row
		} elsif ( $thisfield{'web'} ) {
			my $url = $thisfield{'web'};
			$url =~ s/\[\\*\?\]/$data->{$field}/;
			$url =~ s/\&/\&amp;/g;
			my $domain;
			if ( ( lc($url) =~ /http:\/\/(.*?)\/+/ ) ) {
				$domain = $1;
			}
			$web = "<a href=\"$url\">$data->{$field}</a>";
			if ( $domain && $domain ne $q->virtual_host ) {
				$web .= " <span class=\"link\"><span style=\"font-size:1.2em\">&rarr;</span> $domain</span>";
			}
		}
		if (   ( $field eq 'curator' )
			|| ( $field eq 'sender' )
			|| ( $thisfield{'userfield'} && $thisfield{'userfield'} eq 'yes' ) )
		{
			my $userdata = $self->{'datastore'}->get_user_info( $data->{$field} );
			my $colspan = $summary_view ? 5 : 2;
			$buffer .= "<tr class=\"td$$td_ref\"><th>$displayfield</th><td align=\"left\" colspan=\"$colspan\">";
			$buffer .= "$userdata->{first_name} $userdata->{surname}</td>";
			if ( !$summary_view ) {
				$buffer .= "<td style=\"text-align:left\" colspan=\"2\">$userdata->{affiliation}</td>";
				if (
					$field eq 'curator'
					|| ( ( $field eq 'sender' || ( $thisfield{'userfield'} && $thisfield{'userfield'} eq 'yes' ) )
						&& !$self->{'system'}->{'privacy'} )
				  )
				{
					if (   $userdata->{'email'} eq ''
						or $userdata->{'email'} eq '-' )
					{
						$buffer .= "<td style=\"text-align:left\">No E-mail address available</td></tr>\n";
					} else {
						$buffer .= "<td style=\"text-align:left\"><a href=\"mailto:$userdata->{'email'}\">$userdata->{'email'}</a></td>";
					}
				}
				if ( ( $field eq 'sender' || ( $thisfield{'userfield'} && $thisfield{'userfield'} eq 'yes' ) )
					&& $self->{'system'}->{'privacy'} )
				{
					$buffer .= "<td></td>";
				}
			}
			if ( $field eq 'curator' ) {
				my ( $history, $num_changes ) = $self->_get_history( $isolate_id, 20 );
				if ($num_changes) {
					$buffer .= "</tr>\n";
					$$td_ref = $$td_ref == 1 ? 2 : 1;
					my $plural = $num_changes == 1 ? '' : 's';
					my $title;
					$title = "Update history - ";
					foreach (@$history) {
						my $time = $_->{'timestamp'};
						$time =~ s/ \d\d:\d\d:\d\d\.\d+//;
						my $action = $_->{'action'};
						if ( $action =~ /<br \/>/ ) {
							$action = 'multiple updates';
						}
						$action =~ s/[\r\n]//g;
						$action =~ s/:.*//;
						$title .= "$time: $action<br />";
					}
					if ( $num_changes > 20 ) {
						$title .= "more ...";
					}
					$buffer .= "<tr class=\"td$$td_ref\"><th>update history</th><td style=\"text-align:left\" colspan=\"5\">";
					$buffer .= "<a title=\"$title\" class=\"pending_tooltip\">";
					$buffer .= "$num_changes update$plural</a>";
					my $refer_page = $q->param('page');
					$buffer .=
" <a href=\"$self->{'system'}->{'script_name'}?page=info&amp;db=$self->{'instance'}&amp;id=$isolate_id&amp;history=1&amp;refer=$refer_page\">show details</a></td>";
				}
			}
		} elsif (
			any {
				$field eq $_;
			}
			@$field_with_extended_attributes
		  )
		{
			my $sql_attord =
			  $self->{'db'}->prepare("SELECT attribute,field_order FROM isolate_field_extended_attributes WHERE isolate_field=?");
			eval { $sql_attord->execute($field) };
			if ($@) {
				$logger->error("Can't execute $@");
			}
			my %order;
			while ( my ( $att, $order ) = $sql_attord->fetchrow_array ) {
				$order{$att} = $order;
			}
			my $sql_att =
			  $self->{'db'}
			  ->prepare("SELECT attribute,value FROM isolate_value_extended_attributes WHERE isolate_field=? AND field_value=?");
			eval { $sql_att->execute( $field, $data->{$field} ) };
			$logger->error($@) if $@;
			my %attributes;
			while ( my ( $attribute, $value ) = $sql_att->fetchrow_array ) {
				$attributes{$attribute} = $value;
			}
			if ( keys %attributes ) {
				my $rows = keys %attributes || 1;
				$buffer .=
				  "<tr class=\"td$$td_ref\"><th rowspan=\"$rows\">$displayfield</th><td style=\"text-align:left\" rowspan=\"$rows\">";
				$buffer .= $web || $data->{$field};
				$buffer .= "</td>";
				my $first = 1;
				foreach ( sort { $order{$a} <=> $order{$b} } keys(%attributes) ) {
					$buffer .= "</tr>\n<tr class=\"td$$td_ref\">" if !$first;
					my $url_ref =
					  $self->{'datastore'}
					  ->run_simple_query( "SELECT url FROM isolate_field_extended_attributes WHERE isolate_field=? AND attribute=?",
						$field, $_ );
					my $att_web;
					if ( ref $url_ref eq 'ARRAY' ) {
						my $url = $url_ref->[0] || '';
						$url =~ s/\[\?\]/$attributes{$_}/;
						$url =~ s/\&/\&amp;/g;
						my $domain;
						if ( ( lc($url) =~ /http:\/\/(.*?)\/+/ ) ) {
							$domain = $1;
						}
						$att_web = "<a href=\"$url\">$attributes{$_}</a>" if $url;
						if ( $domain && $domain ne $q->virtual_host ) {
							$att_web .= " <span class=\"link\"><span style=\"font-size:1.2em\">&rarr;</span> $domain</span>";
						}
					}
					$buffer .= "<th>$_</th><td colspan=\"3\" style=\"text-align:left\">";
					$buffer .= $att_web || $attributes{$_};
					$buffer .= "</td>";
					$first = 0;
				}
			} else {
				$buffer .= "<tr class=\"td$$td_ref\"><th>$displayfield</th><td style=\"text-align:left\" colspan=\"5\">";
				$buffer .= $web || $data->{$field};
				$buffer .= "</td>";
			}
		} else {
			$buffer .= "<tr class=\"td$$td_ref\"><th>$displayfield</th><td style=\"text-align:left\" colspan=\"5\">";
			$buffer .= $web || $data->{$field};
			$buffer .= "</td>";
		}
		$buffer .= "</tr>\n";
		$$td_ref = $$td_ref == 1 ? 2 : 1;    #row stripes
		if ( $field eq $self->{'system'}->{'labelfield'} ) {
			my $aliases =
			  $self->{'datastore'}->run_list_query( "SELECT alias FROM isolate_aliases WHERE isolate_id=? ORDER BY alias", $isolate_id );
			if (@$aliases) {
				local $" = '; ';
				my $plural = @$aliases > 1 ? 'es' : '';
				$buffer .=
				  "<tr class=\"td$$td_ref\"><th>alias$plural</th><td style=\"text-align:left\" colspan=\"5\">@$aliases</td></tr>\n";
				$$td_ref = $$td_ref == 1 ? 2 : 1;
			}
		}
		if ( $composites{$field} ) {
			foreach ( keys %composite_display_pos ) {
				next if $composite_display_pos{$_} ne $field;
				$displayfield = $_;
				$displayfield =~ tr/_/ /;
				my $value = $self->{'datastore'}->get_composite_value( $isolate_id, $_, $data );
				$buffer .= "<tr class=\"td$$td_ref\"><th>$displayfield</th><td style=\"text-align:left\" colspan=\"5\">$value</td></tr>\n";
				$$td_ref = $$td_ref == 1 ? 2 : 1;
			}
		}
	}
	return $buffer;
}

sub _get_scheme_attributes {
	my ( $self, $isolate_id ) = @_;

	#Extract all locus_info, allele_designations and allele_sequences using fetchall_hashref - quicker than
	#making a separate call for each locus.
	my $locus_info_sql = $self->{'db'}->prepare("SELECT id,common_name,url,description_url FROM loci");
	eval { $locus_info_sql->execute };
	$logger->error($@) if $@;
	my $locus_info      = $locus_info_sql->fetchall_hashref('id');
	my $locus_alias_sql = $self->{'db'}->prepare("SELECT locus,alias FROM locus_aliases WHERE use_alias");
	eval { $locus_alias_sql->execute };
	$logger->error($@) if $@;
	my $locus_alias           = $locus_alias_sql->fetchall_hashref( [qw(locus alias)] );
	my $allele_designations   = $self->{'datastore'}->get_all_allele_designations($isolate_id);
	my $allele_sequences      = $self->{'datastore'}->get_all_allele_sequences($isolate_id);
	my $allele_sequence_flags = $self->{'datastore'}->get_all_sequence_flags($isolate_id);
	return ( $locus_info, $locus_alias, $allele_designations, $allele_sequences, $allele_sequence_flags );
}

sub _get_tree {
	my ( $self, $isolate_id ) = @_;
	my $buffer = "<table style=\"width:100%;border-spacing:0\">";
	$buffer .= "<tr>\n";
	$buffer .= "<td id=\"tree\" class=\"tree\">\n";
	$buffer .= "<noscript><p class=\"highlight\">Enable Javascript to enhance your viewing experience.</p></noscript>\n";
	$buffer .= $self->get_tree( $isolate_id, { 'isolate_display' => $self->{'curate'} ? 0 : 1 } );
	$buffer .= "</td><td style=\"vertical-align:top;width:80%\" id=\"scheme_table\">\n";
	$buffer .= "</td></tr>\n";
	$buffer .= "</table>\n";
	return $buffer;
}

sub get_sample_summary {
	my ( $self, $id ) = @_;
	my $td = 1;
	my ($sample_buffer) = $self->_get_samples( $id, \$td );
	my $buffer = '';
	if ($sample_buffer) {
		$buffer = "<table class=\"resultstable\">\n";
		$buffer .= $sample_buffer;
		$buffer .= "</table>\n";
	}
	return $buffer;
}

sub _get_samples {
	my ( $self, $id, $td_ref, $include_side_header ) = @_;
	my $buffer = '';
	my $sample_fields = $self->{'xmlHandler'}->get_sample_field_list;
	my ( @selected_fields, @clean_fields );
	foreach (@$sample_fields) {
		next if $_ eq 'isolate_id';
		my %attributes = $self->{'xmlHandler'}->get_sample_field_attributes($_);
		next if defined $attributes{'maindisplay'} && $attributes{'maindisplay'} eq 'no';
		push @selected_fields, $_;
		( my $clean = $_ ) =~ tr/_/ /;
		push @clean_fields, $clean;
	}
	if (@selected_fields) {
		my $samples = $self->{'datastore'}->get_samples($id);
		my @sample_rows;
		foreach my $sample (@$samples) {
			foreach (@$sample_fields) {
				if ( $_ eq 'sender' || $_ eq 'curator' ) {
					my $user_info = $self->{'datastore'}->get_user_info( $sample->{$_} );
					$sample->{$_} = "$user_info->{'first_name'} $user_info->{'surname'}";
				}
			}
			my $row = "<tr class=\"td$$td_ref\">";
			if ( $self->{'curate'} ) {
				$row .=
"<td><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=delete&amp;table=samples&amp;isolate_id=$id&amp;sample_id=$sample->{'sample_id'}\">Delete</a></td>
				<td><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=update&amp;table=samples&amp;isolate_id=$id&amp;sample_id=$sample->{'sample_id'}\">Update</a></td>";
			}
			foreach my $field (@selected_fields) {
				$sample->{$field} = defined $sample->{$field} ? $sample->{$field} : '';
				if ( $field eq 'sample_id' && $self->{'prefs'}->{'sample_details'} ) {
					my $info = "Sample $sample->{$field} - ";
					foreach (@$sample_fields) {
						next if $_ eq 'sample_id' || $_ eq 'isolate_id';
						( my $clean = $_ ) =~ tr/_/ /;
						$info .= "$clean: $sample->{$_}&nbsp;<br />" if defined $sample->{$_};   #nbsp added to stop Firefox truncating text
					}
					$row .=
"<td>$sample->{$field}<span style=\"font-size:0.5em\"> </span><a class=\"update_tooltip\" title=\"$info\">&nbsp;...&nbsp;</a></td>";
				} else {
					$row .= "<td>$sample->{$field}</td>";
				}
			}
			$row .= "</tr>";
			push @sample_rows, $row;
			$$td_ref = $$td_ref == 1 ? 2 : 1;
		}
		if (@sample_rows) {
			my $rows = scalar @sample_rows + 1;
			local $" = '</th><th>';
			$buffer .= "<tr>";
			$buffer .= "<th>samples</th>" if $include_side_header;
			$buffer .= "<td colspan=\"5\"><table style=\"width:100%\"><tr>";
			if ( $self->{'curate'} ) {
				$buffer .= "<th>Delete</th><th>Update</th>";
			}
			$buffer .= "<th>@clean_fields</th></tr>";
			local $" = "\n";
			$buffer .= "@sample_rows";
			$buffer .= "</table></td></tr>\n";
		}
	}
	return $buffer;
}

sub _get_scheme_fields {
	my (
		$self,                $id,               $isolate_id,            $locus_info, $locus_alias,
		$allele_designations, $allele_sequences, $allele_sequence_flags, $td,         $summary_view
	) = @_;
	my $q = $self->{'cgi'};
	my $display_on_own_line;
	my $scheme_fields;
	my $scheme_fields_count = 0;
	my $buffer;
	my ( $loci, @profile, $info_ref );
	my $locus_display_count = 0;

	if ($id) {
		$scheme_fields = $self->{'datastore'}->get_scheme_fields($id);
		$loci          = $self->{'datastore'}->get_scheme_loci($id);
		my $to_display;
		$display_on_own_line = $self->{'datastore'}->are_sequences_displayed_in_scheme($id);
		$display_on_own_line = 1
		  if $summary_view && @$loci + @$scheme_fields > 5;    #make sure table doesn't get too wide
		my $allele_designations_exist = $self->{'datastore'}->run_simple_query(
"SELECT COUNT(isolate_id) FROM allele_designations LEFT JOIN scheme_members ON scheme_members.locus=allele_designations.locus WHERE isolate_id=? AND scheme_id=?",
			$isolate_id, $id
		)->[0];
		my $allele_sequences_exist = $self->{'datastore'}->run_simple_query(
"SELECT COUNT(isolate_id) FROM allele_sequences LEFT JOIN sequence_bin ON allele_sequences.seqbin_id=sequence_bin.id LEFT JOIN scheme_members ON allele_sequences.locus=scheme_members.locus WHERE isolate_id=? AND scheme_id=?",
			$isolate_id, $id
		)->[0];
		foreach (@$loci) {

			if ( $self->{'prefs'}->{'isolate_display_loci'}->{$_} ne 'hide' ) {
				$locus_display_count++;
			}
		}
		return $td if !$allele_designations_exist && !$allele_sequences_exist;
		$display_on_own_line = 0 if !$locus_display_count;
		$info_ref = $self->{'datastore'}->get_scheme_info($id);
		foreach (@$scheme_fields) {
			if ( $self->{'prefs'}->{'isolate_display_scheme_fields'}->{$id}->{$_} ) {
				$scheme_fields_count++;
			}
		}
	} else {

		#Loci that don't belong to a scheme
		$scheme_fields = [];
		if ( $self->{'prefs'}->{'undesignated_alleles'} ) {
			$loci = $self->{'datastore'}->get_loci_in_no_scheme();
		} else {
			$loci = $self->{'datastore'}->run_list_query(
"SELECT allele_designations.locus FROM allele_designations LEFT JOIN scheme_members ON allele_designations.locus = scheme_members.locus WHERE isolate_id=? AND scheme_id is null UNION SELECT allele_sequences.locus FROM allele_sequences LEFT JOIN sequence_bin ON allele_sequences.seqbin_id=sequence_bin.id LEFT JOIN scheme_members ON scheme_members.locus=allele_sequences.locus WHERE scheme_id is null AND isolate_id=? ORDER BY locus",
				$isolate_id, $isolate_id
			);
		}
		foreach (@$loci) {
			if ( $self->{'prefs'}->{'isolate_display_loci'}->{$_} ne 'hide' ) {
				$locus_display_count++;
			}
		}
		$info_ref->{'description'} = 'Loci';
		$display_on_own_line = 1;
	}
	return $td if !( $locus_display_count + $scheme_fields_count ) && !$display_on_own_line;
	my $hidden_locus_count = 0;
	my %locus_aliases;
	foreach (@$loci) {
		my $aliases;
		foreach my $alias ( sort keys %{ $locus_alias->{$_} } ) {
			if ( $self->{'system'}->{'locus_superscript_prefix'} eq 'yes' ) {
				$alias =~ s/^([A-Za-z])_/<sup>$1<\/sup>/;
			}
			push @$aliases, $alias;
		}
		$locus_aliases{$_} = $aliases;
		$hidden_locus_count++
		  if $self->{'prefs'}->{'isolate_display_loci'}->{$_} eq 'hide';
	}
	return $td
	  if ( ( $hidden_locus_count == scalar @$loci && !$scheme_fields_count )
		|| ( !keys %$allele_designations && !keys %$allele_sequences ) );
	my $rowspan = $display_on_own_line ? ( $locus_display_count + $scheme_fields_count ) : 1;
	$buffer .= (
		$display_on_own_line
		? "<tr class=\"td$td\"><th rowspan=\"$rowspan\" style=\"vertical-align:top;padding-top:1em\">"
		: "<tr class=\"td$td\"><th>"
	) . "$info_ref->{'description'}</th>";
	my ( %url, %locus_value );
	my $provisional_profile;
	foreach (@$loci) {
		$allele_designations->{$_}->{'status'} ||= 'confirmed';
		$provisional_profile = 1 if $self->{'prefs'}->{'mark_provisional'} && $allele_designations->{$_}->{'status'} eq 'provisional';
		my $cleaned_name;
		my $display_locus_name = $_;
		if ( $self->{'system'}->{'locus_superscript_prefix'} eq 'yes' ) {
			$display_locus_name =~ s/^([A-Za-z])_/<sup>$1<\/sup>/;
		}
		$display_locus_name =~ tr/_/ /;
		$locus_value{$_} .= "<span class=\"provisional\">"
		  if ( $allele_designations->{$_}->{'status'} && $allele_designations->{$_}->{'status'} eq 'provisional' )
		  && $self->{'prefs'}->{'mark_provisional'};
		$cleaned_name = $display_locus_name;
		$cleaned_name =~ s/_/&nbsp;/g;
		my $tooltip_name = $cleaned_name;
		if ( $self->{'prefs'}->{'locus_alias'} && $locus_aliases{$_} ) {
			local $" = '; ';
			$cleaned_name .= "<br /><span class=\"comment\">(@{$locus_aliases{$_}})</span>";
		}
		push @profile, $allele_designations->{$_}->{'allele_id'};
		if ( defined $allele_designations->{$_}->{'allele_id'} ) {
			my $url;
			if ( $locus_info->{$_}->{'url'} && $allele_designations->{$_}->{'allele_id'} ne 'deleted' ) {
				$url{$_} = $locus_info->{$_}->{'url'};
				$url{$_} =~ s/\[\?\]/$allele_designations->{$_}->{'allele_id'}/g;
				$url{$_} =~ s/\&/\&amp;/g;
				$locus_value{$_} .= "<a href=\"$url{$_}\">$allele_designations->{$_}->{'allele_id'}</a>";
			} else {
				$locus_value{$_} .= "$allele_designations->{$_}->{'allele_id'}";
			}
			$locus_value{$_} .= "</span>"
			  if $allele_designations->{$_}->{'status'} eq 'provisional'
				  && $self->{'prefs'}->{'mark_provisional'};
			if ( $self->{'prefs'}->{'update_details'} && $allele_designations->{$_}->{'allele_id'} ) {
				my $update_tooltip = $self->get_update_details_tooltip( $tooltip_name, $allele_designations->{$_} );
				$locus_value{$_} .=
				  "<span style=\"font-size:0.5em\"> </span><a class=\"update_tooltip\" title=\"$update_tooltip\">&nbsp;...&nbsp;</a>";
			}
		}
		if ( $self->{'prefs'}->{'sequence_details'} && keys %{ $allele_sequences->{$_} } > 0 ) {
			my @seqs;
			my @flags;
			my %flags_used;
			my $complete;
			foreach my $seqbin_id ( keys %{ $allele_sequences->{$_} } ) {
				foreach my $start ( keys %{ $allele_sequences->{$_}->{$seqbin_id} } ) {
					foreach my $end ( keys %{ $allele_sequences->{$_}->{$seqbin_id}->{$start} } ) {
						push @seqs, $allele_sequences->{$_}->{$seqbin_id}->{$start}->{$end};
						$complete = 1 if $allele_sequences->{$_}->{$seqbin_id}->{$start}->{$end}->{'complete'};
						my @flag_list = keys %{ $allele_sequence_flags->{$_}->{$seqbin_id}->{$start}->{$end} };
						push @flags, \@flag_list;
						$flags_used{$_} = 1 foreach @flag_list;
					}
				}
			}
			my $sequence_tooltip = $self->get_sequence_details_tooltip( $tooltip_name, $allele_designations->{$_}, \@seqs, \@flags );
			my $sequence_class = $complete ? 'sequence_tooltip' : 'sequence_tooltip_incomplete';
			$locus_value{$_} .=
"<span style=\"font-size:0.2em\"> </span><a class=\"$sequence_class\" title=\"$sequence_tooltip\" href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleSequence&amp;id=$isolate_id&amp;locus=$_\">&nbsp;S&nbsp;</a>";
			if ( keys %flags_used ) {
				foreach my $flag ( sort keys %flags_used ) {
					$locus_value{$_} .= "<a class=\"seqflag_tooltip\">$flag</a>";
				}
			}
		}
		if ( $allele_designations->{$_}->{'allele_id'} ) {
			$locus_value{$_} .= $self->_get_pending_designation_tooltip( $isolate_id, $_ ) || '';
		}
		my $action = $allele_designations->{$_}->{'allele_id'} ? 'update' : 'add';
		$locus_value{$_} .=
" <a href=\"$self->{'system'}->{'script_name'}?page=alleleUpdate&amp;db=$self->{'instance'}&amp;isolate_id=$isolate_id&amp;locus=$_\" class=\"update\">$action</a>"
		  if $self->{'curate'};
	}
	my %field_values;
	if ( defined $scheme_fields && scalar @$scheme_fields ) {
		if ($scheme_fields_count) {
			my $scheme;
			try {
				$scheme = $self->{'datastore'}->get_scheme($id);
			}
			catch BIGSdb::DatabaseConnectionException with {};
			my $scheme_field_values = $self->{'datastore'}->get_scheme_field_values_by_profile( $id, \@profile );
			if ( defined $scheme_field_values && ref $scheme_field_values eq 'HASH' ) {
				foreach (@$scheme_fields) {
					my $value = $scheme_field_values->{ lc($_) };
					$value = defined $value ? $value : '';
					$value = 'Not defined' if $value eq '-999' || $value eq '';
					my $att = $self->{'datastore'}->get_scheme_field_info( $id, $_ );
					if ( $att->{'url'} && $value ne '' ) {
						my $url = $att->{'url'};
						$url =~ s/\[\?\]/$value/g;
						$url =~ s/\&/\&amp;/g;
						$field_values{$_} = "<a href=\"$url\">$value</a>";
					} else {
						$field_values{$_} = $value;
					}
				}
			} else {
				$field_values{$_} = 'Not defined' foreach @$scheme_fields;
			}
		}
	}
	my $first = 1;
	if ($display_on_own_line) {
		foreach (@$loci) {
			next
			  if $self->{'prefs'}->{'isolate_display_loci'}->{$_} eq 'hide';
			$buffer .= "<tr class=\"td$td\">" if !$first;
			my $cleaned = $self->clean_locus($_);
			$buffer .= "<td>$cleaned";
			my @other_display_names;
			if ( $self->{'prefs'}->{'locus_alias'} && $locus_aliases{$_} ) {
				push @other_display_names, @{ $locus_aliases{$_} };
			}
			local $" = '; ';
			$buffer .= "<br /><span class=\"comment\">(@other_display_names)</span>" if @other_display_names;
			if ( $locus_info->{$_}->{'description_url'} ) {
				$locus_info->{$_}->{'description_url'} =~ s/\&/\&amp;/g;
				$buffer .= " <a href=\"$locus_info->{$_}->{'description_url'}\" class=\"info_tooltip\">&nbsp;<i>i</i>&nbsp;</a>";
			}
			$buffer .= '</td>';
			$buffer .= defined $locus_value{$_} ? "<td>$locus_value{$_}</td>" : '<td />';
			my $display_seq =
			  (      $self->{'prefs'}->{'isolate_display_loci'}->{$_} eq 'sequence'
				  && $allele_designations->{$_}->{'allele_id'}
				  && !$summary_view )
			  ? 1
			  : 0;
			if ( $display_seq && $allele_designations->{$_}->{'allele_id'} ) {
				my $sequence;
				try {
					my $sequence_ref =
					  $self->{'datastore'}->get_locus($_)->get_allele_sequence( $allele_designations->{$_}->{'allele_id'} );
					$sequence = BIGSdb::Utils::split_line($$sequence_ref);
				}
				catch BIGSdb::DatabaseConnectionException with {
					$sequence = "Can not connect to database";
				}
				catch BIGSdb::DatabaseConfigurationException with {
					my $ex = shift;
					$sequence = $ex->{-text};
				};
				$buffer .=
				  defined $sequence ? "<td colspan=\"3\" style=\"text-align:left\" class=\"seq\">$sequence</td>" : "<td colspan=\"3\" />";
			} else {
				$buffer .= "<td colspan=\"3\" />";
			}
			$buffer .= "</tr>\n";
			$first = 0;
			$td = $td == 1 ? 2 : 1;
		}
		foreach (@$scheme_fields) {
			next if !$self->{'prefs'}->{'isolate_display_scheme_fields'}->{$id}->{$_};
			$buffer .= "<tr class=\"td$td\">" if !$first;
			( my $cleaned = $_ ) =~ tr/_/ /;
			$buffer .= "<td>$cleaned</td>";
			$buffer .= $provisional_profile ? "<td><span class=\"provisional\">" : '<td>';
			$buffer .= $field_values{$_};
			$buffer .= $provisional_profile ? '</span></td>' : '</td>';
			$buffer .= "<td colspan=\"3\" />";
			$buffer .= "</tr>";
			$first = 0;
			$td = $td == 1 ? 2 : 1;
		}
	} else {
		$buffer .= "<td colspan=\"5\">";
		$buffer .= "<table class=\"profile\">";
		my @header_buffer;
		my @value_buffer;
		my $i         = 0;
		my $j         = 0;
		my $max_cells = $q->param('no_header') ? 10 : 16;
		foreach (@$loci) {
			next
			  if $self->{'prefs'}->{'isolate_display_loci'}->{$_} eq 'hide';
			$header_buffer[$j] .= "<tr class=\"td$td\">" if !$i;
			my $cleaned = $self->clean_locus($_);
			my @other_display_names;
			if ($id) {
				$header_buffer[$j] .= "<th>$cleaned";
				if ( $self->{'prefs'}->{'locus_alias'} && $locus_aliases{$_} ) {
					push @other_display_names, @{ $locus_aliases{$_} };
				}
				if (@other_display_names) {
					local $" = '; ';
					$header_buffer[$j] .= "<br /><span class=\"comment\">(@other_display_names)</span>";
				}
				if ( $locus_info->{$_}->{'description_url'} ) {
					$locus_info->{$_}->{'description_url'} =~ s/\&/\&amp;/g;
					$header_buffer[$j] .=
					  " <a href=\"$locus_info->{$_}->{'description_url'}\" class=\"info_tooltip\">&nbsp;<i>i</i>&nbsp;</a>";
				}
				$header_buffer[$j] .= '</th>';
			} else {
				$header_buffer[$j] .= "<th>$cleaned";
				if (@other_display_names) {
					local $" = '; ';
					$header_buffer[$j] .= "<br /><span class=\"comment\">(@other_display_names)</span>";
				}
				$header_buffer[$j] .= "</th>";
			}
			$i++;
			if ( $i >= $max_cells ) {
				$header_buffer[$j] .= "</tr>\n";
				$j++;
				$i = 0;
			}
		}
		if ( defined $scheme_fields && scalar @$scheme_fields && $scheme_fields_count ) {
			foreach (@$scheme_fields) {
				if ( $self->{'prefs'}->{'isolate_display_scheme_fields'}->{$id}->{$_} ) {
					$header_buffer[$j] .= "<tr class=\"td$td\">" if !$i;
					my $cleaned = $_;
					$cleaned =~ tr/_/ /;
					$header_buffer[$j] .= "<th>$cleaned</th>";
					$i++;
					if ( $i >= $max_cells ) {
						$header_buffer[$j] .= "</tr>\n";
						$j++;
						$i = 0;
					}
				}
			}
		}
		$header_buffer[$j] .= "</tr>\n" if $i;
		$j = 0;
		$i = 0;
		foreach (@$loci) {
			next
			  if $self->{'prefs'}->{'isolate_display_loci'}->{$_} eq 'hide';
			$value_buffer[$j] .= "<tr class=\"td$td\">" if !$i;
			$value_buffer[$j] .= defined $locus_value{$_} ? "<td>$locus_value{$_}</td>" : '<td />';
			$i++;
			if ( $i >= $max_cells ) {
				$value_buffer[$j] .= "</tr>\n";
				$j++;
				$i = 0;
			}
		}
		foreach (@$scheme_fields) {
			if ( $self->{'prefs'}->{'isolate_display_scheme_fields'}->{$id}->{$_} ) {
				$value_buffer[$j] .= "<tr class=\"td$td\">" if !$i;
				$value_buffer[$j] .= $provisional_profile ? "<td><span class=\"provisional\">" : '<td>';
				$value_buffer[$j] .= $field_values{$_};
				$value_buffer[$j] .= $provisional_profile ? '</span></td>'                     : '</td>';
				$i++;
				if ( $i >= $max_cells ) {
					$value_buffer[$j] .= "</tr>\n";
					$j++;
					$i = 0;
				}
			}
		}
		$value_buffer[$j] .= "</tr>\n" if $i;
		for ( my $row = 0 ; $row < @header_buffer ; $row++ ) {
			$buffer .= "$header_buffer[$row]";
			$buffer .= "$value_buffer[$row]";
		}
		$buffer .= "</table></td></tr>";
		$td = $td == 1 ? 2 : 1;
	}
	return ( $td, $buffer );
}

sub _get_pending_designation_tooltip {
	my ( $self, $isolate_id, $locus ) = @_;
	my $buffer;
	my $pending = $self->{'datastore'}->get_pending_allele_designations( $isolate_id, $locus );
	my $pending_buffer;
	if (@$pending) {
		$pending_buffer = 'pending designations - ';
		foreach (@$pending) {
			my $sender = $self->{'datastore'}->get_user_info( $_->{'sender'} );
			$pending_buffer .= "allele: $_->{'allele_id'} ";
			$pending_buffer .= "($_->{'comments'}) " if $_->{'comments'};
			$pending_buffer .= "[$sender->{'first_name'} $sender->{'surname'}; $_->{'method'}; $_->{'datestamp'}]<br />";
		}
	}
	$buffer .= "<span style=\"font-size:0.2em\"> </span><a class=\"pending_tooltip\" title=\"$pending_buffer\">pending</a>"
	  if $pending_buffer && $self->{'prefs'}->{'display_pending'};
	return $buffer;
}

sub get_main_table_reference {
	my ( $self, $fieldname, $pmid, $td ) = @_;
	my $citation_ref =
	  $self->{'datastore'}->get_citation_hash( [$pmid], { 'formatted' => 1, 'all_authors' => 1, 'state_if_unavailable' => 1 } );
	my $buffer =
	    "<tr class=\"td$td\"><th>$fieldname</th>"
	  . "<td align=\"left\"><a href=\"http://www.ncbi.nlm.nih.gov/pubmed/$pmid\">$pmid</a></td>"
	  . "<td colspan=\"3\" style=\"text-align:left; width:75%\">$citation_ref->{$pmid}</td><td>";
	$buffer .= $self->get_link_button_to_ref($pmid);
	$buffer .= "</td></tr>\n";
	return $buffer;
}

sub get_title {
	my ($self) = @_;
	my $isolate_id = $self->{'cgi'}->param('id');
	return "Invalid isolate id" if !BIGSdb::Utils::is_int($isolate_id);
	my @name  = $self->get_name($isolate_id);
	my $title = "Isolate information: id-$isolate_id";
	local $" = ' ';
	$title .= " (@name)" if $name[1];
	$title .= ' - ';
	$title .= "$self->{'system'}->{'description'}";
	return $title;
}

sub _get_history {
	my ( $self, $isolate_id, $limit ) = @_;
	my $limit_clause = $limit ? " LIMIT $limit" : '';
	my $count;
	my $qry = "SELECT timestamp,action,curator FROM history where isolate_id=? ORDER BY timestamp desc$limit_clause";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute($isolate_id); };
	if ($@) {
		$logger->error("Can't execute $qry value:$isolate_id $@");
	}
	my @history;
	while ( my $data = $sql->fetchrow_hashref ) {
		push @history, $data;
	}
	if ($limit) {

		#need to count total
		$count = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM history WHERE isolate_id=?", $isolate_id )->[0];
	} else {
		$count = scalar @history;
	}
	return \@history, $count;
}

sub get_name {
	my ( $self, $isolate_id ) = @_;
	my $name_ref =
	  $self->{'datastore'}
	  ->run_simple_query( "SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id );
	if ( ref $name_ref eq 'ARRAY' ) {
		return ( $self->{'system'}->{'labelfield'}, $name_ref->[0] );
	}
	return;
}

sub _get_ref_links {
	my ( $self, $isolate_id, $td_ref ) = @_;
	my $buffer = '';
	my $refs = $self->{'datastore'}->run_list_query( "SELECT refs.pubmed_id FROM refs WHERE isolate_id=? ORDER BY pubmed_id", $isolate_id );
	foreach my $ref (@$refs) {
		$buffer .= $self->get_main_table_reference( 'reference', $ref, $$td_ref );
		$$td_ref = $$td_ref == 1 ? 2 : 1;
	}
	return $buffer;
}

sub _get_seqbin_link {
	my ( $self, $isolate_id, $td_ref ) = @_;
	my $seqbin_count = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM sequence_bin WHERE isolate_id=?", $isolate_id )->[0];
	my $buffer = '';
	my $q = $self->{'cgi'};
	if ($seqbin_count) {
		my $length_data =
		  $self->{'datastore'}->run_simple_query(
			"SELECT SUM(length(sequence)), CEIL(AVG(length(sequence))), MAX(length (sequence)) FROM sequence_bin WHERE isolate_id=?",
			$isolate_id );
		my $plural = $seqbin_count == 1 ? '' : 's';
		$buffer .= "<tr class=\"td$$td_ref\"><th rowspan=\"2\">sequence bin</th><td style=\"text-align:left\" colspan=\"4\">
				$seqbin_count sequence$plural (";
		if ( $seqbin_count > 1 ) {
			$buffer .= "total length: $length_data->[0] bp; max: $length_data->[2] bp; mean: $length_data->[1] bp)";
		} else {
			$buffer .= "$length_data->[0] bp)";
		}
		$buffer .= "</td><td rowspan=\"2\">\n";
		$buffer .= $q->start_form;
		$q->param( 'curate', 1 ) if $self->{'curate'};
		$q->param( 'page', 'seqbin' );
		$q->param( 'isolate_id', $isolate_id );
		$buffer .= $q->hidden($_) foreach qw (db page curate isolate_id);
		$buffer .= $q->submit( -value => 'Display', -class => 'submit' );
		$buffer .= $q->end_form;
		$buffer .= "</td></tr>\n";
		my $tagged = $self->{'datastore'}->run_simple_query(
"SELECT COUNT(*) FROM allele_sequences LEFT JOIN sequence_bin ON allele_sequences.seqbin_id = sequence_bin.id WHERE sequence_bin.isolate_id=?",
			$isolate_id
		)->[0];
		$plural = $tagged == 1 ? '' : 's';
		$buffer .= "<tr class=\"td$$td_ref\"><td style=\"text-align:left\" colspan=\"4\">$tagged allele sequence$plural tagged</td></tr>\n";
		$$td_ref = $$td_ref == 1 ? 2 : 1;
		$q->param( 'page', 'info' );
	}
	return $buffer;
}

sub _print_projects {
	my ( $self, $isolate_id ) = @_;
	my $projects = $self->{'datastore'}->run_list_query_hashref(
"SELECT * FROM projects WHERE full_description IS NOT NULL AND id IN (SELECT project_id FROM project_members WHERE isolate_id=?) ORDER BY id",
		$isolate_id
	);
	if (@$projects){
		print "<div class=\"box\" id=\"resultsheader\">\n";
		my $plural = @$projects == 1 ? '' : 's';
		print "<p>This isolate is a member of the following project$plural:</p>\n";
		print "<table>\n";
		my $td = 1;
		foreach (@$projects){
			print "<tr class=\"td$td\"><th style=\"text-align:right;padding-right:1em\">$_->{'short_description'}</th><td style=\"padding-left:1em\">$_->{'full_description'}</td></tr>\n";
			$td = $td == 1 ? 2 : 1;
		}
		print "</table>\n</div>\n";
	}
	return;
}
1;
