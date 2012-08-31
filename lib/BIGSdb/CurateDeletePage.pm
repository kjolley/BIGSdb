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
package BIGSdb::CurateDeletePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Page qw(DATABANKS);

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $table = $q->param('table') || '';
	my $record_name = $self->get_record_name($table);
	if ( !$self->{'datastore'}->is_table($table) && !( $table eq 'samples' && @{ $self->{'xmlHandler'}->get_sample_field_list } ) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Table $table does not exist!</p></div>";
		return;
	}
	say "<h1>Delete $record_name</h1>";
	if ( $table eq 'profiles' ) {
		my $scheme_id = $q->param('scheme_id');
		if ( !$scheme_id || !BIGSdb::Utils::is_int($scheme_id) ) {
			say "<div class=\"box\" id=\"statusbad\">Invalid scheme id.</p></div>";
			return;
		}
		my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
		if ( !$scheme_info ) {
			say "<div class=\"box\" id=\"statusbad\">Scheme does not exist.</p></div>";
			return;
		}
	}
	if ( !$self->can_modify_table($table) ) {
		if ( $table eq 'sequences' && $q->param('locus') ) {
			my $locus = $q->param('locus');
			say "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to delete $locus sequences from the "
			  . "database.</p></div>";
		} else {
			say "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to delete records from the $table "
			  . "table.</p></div>";
		}
		return;
	} elsif ( ( $self->{'system'}->{'read_access'} eq 'acl' || ( ( $self->{'system'}->{'write_access'} // '' ) eq 'acl' ) )
		&& $self->{'username'}
		&& !$self->is_admin
		&& $q->param('isolate_id')
		&& !$self->is_allowed_to_view_isolate( $q->param('isolate_id') ) )
	{
		say "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to modify this isolate.</p></div>";
		return;
	} elsif ( ( $table eq 'sequence_refs' || $table eq 'accession' ) && $q->param('locus') ) {
		my $locus = $q->param('locus');
		if ( !$self->is_admin && !$self->{'datastore'}->is_allowed_to_modify_locus_sequences( $locus, $self->get_curator_id ) ) {
			say "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to delete "
			  . ( $table eq 'sequence_refs' ? 'references' : 'accession numbers' )
			  . " for this locus.</p></div>";
			return;
		}
	}
	$self->_display_record($table);
	return;
}

sub _display_record {
	my ( $self, $table ) = @_;
	my $q = $self->{'cgi'};
	if ( ( $table eq 'scheme_fields' || $table eq 'scheme_members' ) && $self->{'system'}->{'dbtype'} eq 'sequences' && !$q->param('sent') )
	{
		say "<div class=\"box\" id=\"warning\"><p>Please be aware that any modifications to the structure of this scheme will result "
		  . "in the removal of all data from it. This is done to ensure data integrity.  This does not affect allele designations, but "
		  . "any profiles will have to be reloaded.</p></div>";
	}
	my $buffer;
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my @query_values;
	my %primary_keys;
	foreach (@$attributes) {
		if ( $_->{'primary_key'} ) {
			my $value = $q->param( $_->{'name'} ) // '';
			$value =~ s/'/\\'/g;
			push @query_values, "$_->{'name'} = E'$value'";
			$primary_keys{ $_->{'name'} } = 1 if defined $q->param( $_->{'name'} );
			if ( $_->{'type'} eq 'int' && !BIGSdb::Utils::is_int( $q->param( $_->{'name'} ) ) ) {
				say "<div class=\"box\" id=\"statusbad\"><p>Field $_->{'name'} must be an integer.</p></div>";
			}
		}
	}
	if ( scalar @query_values != scalar keys %primary_keys ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Insufficient identifying attributes sent.</p></div>";
		return;
	}
	local $" = ' AND ';
	my $qry = "SELECT * FROM $table WHERE @query_values";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error($@) if $@;
	my $data = $sql->fetchrow_hashref;
	if ( !$data ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Selected record does not exist.</p></div>";
		return;
	}
	$buffer .= $q->start_form;
	$buffer .= "<div class=\"box\" id=\"resultstable\">\n";
	$buffer .= "<p>You have chosen to delete the following record:</p>\n";
	if ( scalar @$attributes > 10 ) {
		$buffer .= "<p />";
		$buffer .= $q->submit( -name => 'submit', -value => 'Delete!', -class => 'submit' );
	}
	$buffer .= $q->hidden($_) foreach qw(page db table);
	$buffer .= $q->hidden( 'sent', 1 );
	foreach (@$attributes) {
		if ( $_->{'primary_key'} ) {
			$buffer .= $q->hidden( $_->{'name'}, $data->{ $_->{'name'} } );
		}
	}
	$buffer .= "<table class=\"resultstable\">\n";
	my $td = 1;
	my $primary_key;
	if ( $table eq 'profiles' ) {
		eval {
			$primary_key =
			  $self->{'datastore'}
			  ->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $q->param('scheme_id') )->[0];
		};
		$logger->error($@) if $@;
	}
	foreach (@$attributes) {
		if ( $table eq 'profiles' && $_->{'name'} eq 'profile_id' ) {
			$buffer .= "<tr class=\"td$td\"><th style=\"text-align:right\">$primary_key&nbsp;</th>";
		} else {
			$buffer .= "<tr class=\"td$td\"><th style=\"text-align:right\">$_->{name}&nbsp;</th>";
		}
		my $value;
		if ( $_->{'type'} eq 'bool' ) {
			$value = $data->{ $_->{'name'} } ? 'true' : 'false';
		} else {
			$value = $data->{ $_->{'name'} };
		}
		if ( $_->{'name'} eq 'url' ) {
			$value =~ s/\&/\&amp;/g if defined $value;
		}
		if ( $_->{'name'} =~ /sequence$/ && $_->{'name'} ne 'coding_sequence' ) {
			$value ||= '';
			my $value_length = length($value);
			if ( $value_length > 5000 ) {
				$value = BIGSdb::Utils::truncate_seq( \$value, 30 );
				$buffer .= "<td style=\"text-align:left\"><span class=\"seq\">$value</span><br />Sequence is $value_length characters "
				  . "(too long to display)</td>\n";
			} else {
				$value = BIGSdb::Utils::split_line($value) || '';
				$buffer .= "<td style=\"text-align:left\" class=\"seq\">$value</td>\n";
			}
		} elsif ( $_->{'name'} eq 'curator' or $_->{'name'} eq 'sender' ) {
			my $user = $self->{'datastore'}->get_user_info($value);
			$user->{'first_name'} ||= '';
			$user->{'surname'}    ||= '';
			$buffer .= "<td style=\"text-align:left\">$user->{'first_name'} $user->{'surname'}</td>\n";
		} elsif ( $_->{'name'} eq 'scheme_id' ) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($value);
			$buffer .= "<td style=\"text-align:left\">$value) $scheme_info->{'description'}</td>\n";
		} elsif ( $_->{'foreign_key'} && $_->{'labels'} ) {
			my @fields_to_query;
			my @values = split /\|/, $_->{'labels'};
			foreach (@values) {
				if ( $_ =~ /\$(.*)/ ) {
					push @fields_to_query, $1;
				}
			}
			local $" = ',';
			my $qry = "select @fields_to_query from $_->{'foreign_key'} WHERE id=?";
			my $foreign_key_sql = $self->{'db'}->prepare($qry) or die;
			eval { $foreign_key_sql->execute($value) };
			$logger->error($@) if $@;
			while ( my @labels = $foreign_key_sql->fetchrow_array() ) {
				my $label_value = $_->{'labels'};
				my $i           = 0;
				foreach (@fields_to_query) {
					$label_value =~ s/$_/$labels[$i]/;
					$i++;
				}
				$label_value =~ s/[\|\$]//g;
				$buffer .= "<td style=\"text-align:left\">$label_value</td>\n";
			}
		} elsif ( $_->{'name'} eq 'locus' ) {
			$value = $self->clean_locus($value);
			$buffer .= defined $value ? "<td style=\"text-align:left\">$value</td>\n" : '<td />';
		} else {
			$buffer .= defined $value ? "<td style=\"text-align:left\">$value</td>\n" : '<td />';
		}
		$buffer .= "</tr>\n";
		$td = $td == 1 ? 2 : 1;
		if ( $table eq 'profiles' && $_->{'name'} eq 'profile_id' ) {
			my $scheme_id = $q->param('scheme_id');
			$buffer .= $self->_get_profile_fields( $scheme_id, $primary_key, $data, \$td );
		}
	}
	if ( $table eq 'sequences' ) {
		$buffer .= $self->_get_extra_sequences_fields( $data, $td );
	}
	$buffer .= "</table>\n";
	if ( $table eq 'allele_designations' ) {
		$buffer .= "<div><fieldset>\n<legend>Options</legend>\n<ul>\n<li>\n";
		if ( $self->can_modify_table('allele_sequences') ) {
			$buffer .= $q->checkbox( -name => 'delete_tags', -label => 'Also delete all sequence tags for this isolate/locus combination' );
			$buffer .= "</li>\n<li>\n";
		}
		$buffer .=
		  $q->checkbox( -name => 'delete_pending', -label => 'Also delete all pending designations for this isolate/locus combination' );
		$buffer .= "</li>\n</ul>\n</fieldset>\n</div>\n";
	}
	$buffer .= $q->submit( -name => 'submit', -value => 'Delete!', -class => 'submit' );
	$buffer .= "</div>\n";
	$buffer .= $q->end_form;
	if ( $q->param('sent') ) {
		$buffer .= $self->_delete( $table, $data, \@query_values ) || '';
		return if $q->param('submit');
	}
	say $buffer;
	return;
}

sub _delete {
	my ( $self, $table, $data, $query_values_ref ) = @_;
	my $q = $self->{'cgi'};
	my $buffer;
	my $proceed = 1;
	my $nogo_buffer;
	if ( $table eq 'users' ) {

		#Don't delete yourself
		if ( defined $data->{'id'} && $data->{'id'} == $self->get_curator_id ) {
			$nogo_buffer .= "It's not a good idea to remove yourself as a curator!  If you really wish to do this, you'll need to do it "
			  . "from another curator account.<br />\n";
			$proceed = 0;
		}

		#Don't delete curators or admins unless you are an admin yourself
		elsif ( defined $data->{'status'} && $data->{'status'} ne 'user' && !$self->is_admin ) {
			$nogo_buffer .= "Only administrators can delete users with curator or admin status!<br />\n";
			$proceed = 0;
		}
		if ($proceed) {
			my $sample_fields = $self->{'xmlHandler'}->get_sample_field_list;
			foreach my $table ( $self->{'datastore'}->get_tables_with_curator ) {
				next if !@$sample_fields && $table eq 'samples';
				my $num = $self->{'datastore'}->run_simple_query( "SELECT count(*) FROM $table WHERE curator = ?", $data->{'id'} )->[0];
				my $num_senders;
				if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) {
					$num_senders =
					  $self->{'datastore'}->run_simple_query( "SELECT count(*) FROM $table WHERE sender = ?", $data->{'id'} )->[0];
				}
				if ( $num || $num_senders ) {
					if ($num) {
						my $plural = $num > 1 ? 's' : '';
						$nogo_buffer .=
						  "User '$data->{'id'}' is the curator for $num record$plural in table '$table' - can not delete!<br />"
						  if $num;
					}
					if ($num_senders) {
						my $plural = $num_senders > 1 ? 's' : '';
						$nogo_buffer .=
						  "User '$data->{'id'}' is the sender for $num_senders record$plural in table '$table' - can not delete!<br />"
						  if $num_senders;
					}
					$proceed = 0;
				}
			}
		}

		#don't delete 'All users' group
	} elsif ( $table eq 'user_groups' ) {
		if ( defined $data->{'id'} && $data->{'id'} == 0 ) {
			$nogo_buffer .= "You can not delete the 'All users' group!<br />";
			$proceed = 0;
		}
	} elsif ( $table eq 'user_group_members' ) {
		if ( defined $data->{'user_group'} && $data->{'user_group'} == 0 ) {
			$nogo_buffer .= "You can not remove members from the 'All users' group!<br />";
			$proceed = 0;
		}
	}

	#Check if record is a foreign key in another table
	if ( $proceed && $table ne 'composite_fields' && $table ne 'schemes' ) {
		my %tables_to_check = $self->_get_tables_which_reference_table($table);
		foreach my $table_to_check ( keys %tables_to_check ) {

			#cascade deletion of locus
			next if $table eq 'loci' && any { $table_to_check eq $_ } qw (locus_aliases locus_descriptions
				  allele_designations pending_allele_designations allele_sequences locus_curators
				  client_dbase_loci locus_extended_attributes);

			#cascade deletion of user
			next if $table eq 'users' && any { $table_to_check eq $_ } qw ( user_permissions user_group_members);

			#cascade deletion of sequence bin records
			next if $table eq 'sequence_bin' && $table_to_check eq 'allele_sequences';

			#cascade deletion of scheme group
			next
			  if $table eq 'scheme_groups' && any { $table_to_check eq $_ } qw ( scheme_group_group_members scheme_group_scheme_members );
			my $num =
			  $self->{'datastore'}
			  ->run_simple_query( "SELECT count(*) FROM $table_to_check WHERE $tables_to_check{$table_to_check} = ?", $data->{'id'} )->[0];
			if ($num) {
				my $record_name = $self->get_record_name($table);
				my $plural = $num > 1 ? 's' : '';
				$data->{'id'} =~ s/'/\\'/g;
				$nogo_buffer .= "$record_name '$data->{'id'}' is referenced by $num record$plural in table '$table_to_check' - "
				  . "can not delete!<br />";
				$proceed = 0;
			}
		}
	}

	#special case to check that allele sequence is not used in a profile (profile database)
	if ( $proceed && $table eq 'sequences' && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $num =
		  $self->{'datastore'}
		  ->run_simple_query( "SELECT COUNT(*) FROM profile_members WHERE locus=? AND allele_id=?", $data->{'locus'}, $data->{'allele_id'} )
		  ->[0];
		if ($num) {
			my $plural = $num > 1 ? 's' : '';
			$nogo_buffer .=
			  "Sequence $data->{'locus'}-$data->{'allele_id'} is referenced by $num allelic profile$plural - can not delete!<br />";
			$proceed = 0;
		}

		#check isolate ACLs where appropriate
	} elsif ( $proceed && $table eq 'allele_designations' && !$self->is_allowed_to_view_isolate( $data->{'isolate_id'} ) ) {
		$nogo_buffer .= "Your user account is not allowed to delete allele designations for this isolate.<br />\n";
		$proceed = 0;
	} elsif (
		$proceed
		&& ( $self->{'system'}->{'read_access'} eq 'acl'
			|| ( ( $self->{'system'}->{'write_access'} // '' ) eq 'acl' ) )
		&& $self->{'username'}
		&& !$self->is_admin
		&& ( $table eq 'accession' || $table eq 'allele_sequences' )
		&& $self->{'system'}->{'dbtype'} eq 'isolates'
	  )
	{
		my $isolate_id =
		  $self->{'datastore'}->run_simple_query( "SELECT isolate_id FROM sequence_bin WHERE id=?", $data->{'seqbin_id'} )->[0];
		if ( !$self->is_allowed_to_view_isolate($isolate_id) ) {
			my $record_type = $self->get_record_name($table);
			$nogo_buffer .= "The $record_type you are trying to delete belongs to an isolate to which your user account is not "
			  . "allowed to access.<br />";
			$proceed = 0;
		}
	}
	if ( !$proceed ) {
		say "<div class=\"box\" id=\"statusbad\"><p>$nogo_buffer</p><p>"
		  . "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back to main page</a></p></div>";
		return;
	}
	$buffer .= "</p>\n";
	if ( $q->param('submit') && $proceed ) {
		$self->_confirm( $table, $data, $query_values_ref );
		return;
	}
	return $buffer;
}

sub _confirm {
	my ( $self, $table, $data, $query_values_ref ) = @_;
	my $q = $self->{'cgi'};
	local $" = ' AND ';
	my $qry = "DELETE FROM $table WHERE @$query_values_ref";
	if ( $table eq 'allele_designations' && $self->can_modify_table('allele_sequences') && $q->param('delete_tags') ) {
		$qry .= ";DELETE FROM allele_sequences WHERE seqbin_id IN (SELECT id FROM sequence_bin WHERE "
		  . "$query_values_ref->[0]) AND $query_values_ref->[1]";
	}
	eval {
		$self->{'db'}->do($qry);
		if ( ( $table eq 'scheme_members' || $table eq 'scheme_fields' ) && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
			$self->remove_profile_data( $data->{'scheme_id'} );
			$self->drop_scheme_view( $data->{'scheme_id'} );
			$self->create_scheme_view( $data->{'scheme_id'} );
		} elsif ( $table eq 'schemes' && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
			$self->drop_scheme_view( $data->{'id'} );
		}
	};
	if ($@) {
		my $err = $@;
		$logger->error($err);
		say "<div class=\"box\" id=\"statusbad\"><p>Delete failed - transaction cancelled - no records have been touched.</p>";
		say "<p>Failed SQL: $qry</p>";
		say "<p>Error message: $err</p></div>";
		$self->{'db'}->rollback;
		return;
	}
	my $record_name = $self->get_record_name($table);
	$self->{'db'}->commit && say "<div class=\"box\" id=\"resultsheader\"><p>$record_name deleted!</p>";
	if ( $table eq 'composite_fields' ) {
		say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=compositeQuery\">Query another</a>";
	} elsif ( $table eq 'profiles' ) {
		my $scheme_id = $q->param('scheme_id');
		$self->refresh_material_view($scheme_id);
		$self->{'db'}->commit;
		say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=profileQuery&amp;scheme_id=$scheme_id\">"
		  . "Query another</a>";
	} else {
		say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=$table\">"
		  . "Query another</a>";
	}
	say " | <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back to main page</a></p></div>";
	$logger->debug("Deleted record: $qry");
	if ( $table eq 'allele_designations' ) {
		my $deltags = $q->param('delete_tags') ? "<br />$data->{'locus'}: sequence tag(s) deleted" : '';
		$self->update_history( $data->{'isolate_id'}, "$data->{'locus'}: designation '$data->{'allele_id'}' deleted$deltags" );

		#check if pending designation exists as this needs to be promoted.
		if ( $q->param('delete_pending') ) {
			$self->delete_pending_designations( $data->{'isolate_id'}, $data->{'locus'} );
		} else {
			$self->promote_pending_allele_designation( $data->{'isolate_id'}, $data->{'locus'} );
		}
	} elsif ( $table eq 'pending_allele_designations' ) {
		$self->update_history( $data->{'isolate_id'}, "$data->{'locus'}: pending designation '$data->{'allele_id'}' deleted" );
	} elsif ( $table eq 'sequences' ) {
		$self->mark_cache_stale;
	}
	return;
}

sub _get_extra_sequences_fields {
	my ( $self, $data, $td ) = @_;
	my $q      = $self->{'cgi'};
	my $buffer = '';
	if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
		my $flags = $self->{'datastore'}->get_allele_flags( $q->param('locus'), $q->param('allele_id') );
		local $" = '</a> <a class="seqflag_tooltip">';
		if (@$flags) {
			$buffer .= "<tr class=\"td$td\"><th style=\"text-align:right\">flags&nbsp;</th><td style=\"text-align:left\">"
			  . "<a class=\"seqflag_tooltip\">@$flags</a></td></tr>\n";
			$td = $td == 1 ? 2 : 1;
		}
	}
	foreach my $databank (DATABANKS) {
		my $accessions =
		  $self->{'datastore'}
		  ->run_list_query( "SELECT databank_id FROM accession WHERE locus=? AND allele_id=? AND databank=? ORDER BY databank_id",
			$q->param('locus'), $q->param('allele_id'), $databank );
		foreach my $accession (@$accessions) {
			$accession = "<a href=\"http://www.ncbi.nlm.nih.gov/nuccore/$accession\">$accession</a>" if $databank eq 'Genbank';
			$buffer .= "<tr class=\"td$td\"><th style=\"text-align:right\">$databank&nbsp;</th>"
			  . "<td style=\"text-align:left\">$accession</td></tr>\n";
			$td = $td == 1 ? 2 : 1;
		}
	}
	my $pubmed_list =
	  $self->{'datastore'}->run_list_query( "SELECT pubmed_id FROM sequence_refs WHERE locus=? AND allele_id=? ORDER BY pubmed_id",
		$q->param('locus'), $q->param('allele_id') );
	my $citations = $self->{'datastore'}->get_citation_hash( $pubmed_list, { formatted => 1, all_authors => 1, link_pubmed => 1 } );
	foreach my $pmid (@$pubmed_list) {
		$buffer .= "<tr class=\"td$td\"><th style=\"text-align:right\">reference&nbsp;</th><td style=\"text-align:left\">"
		  . "$citations->{$pmid}</td></tr>";
		$td = $td == 1 ? 2 : 1;
	}
	my $extended_attributes = $self->{'datastore'}->get_allele_extended_attributes( $q->param('locus'), $q->param('allele_id') );
	foreach my $ext (@$extended_attributes) {
		my $cleaned_field = $ext->{'field'};
		$cleaned_field =~ tr/_/ /;
		if ( $cleaned_field =~ /sequence$/ ) {
			my $seq = BIGSdb::Utils::split_line( $ext->{'value'} );
			$buffer .= "<tr class=\"td$td\"><th style=\"text-align:right\">$cleaned_field&nbsp;</th>"
			  . "<td style=\"text-align:left\" colspan=\"3\" class=\"seq\">$seq</td></tr>\n";
		} else {
			$buffer .= "<tr class=\"td$td\"><th style=\"text-align:right\">$cleaned_field&nbsp;</th>"
			  . "<td style=\"text-align:left\" colspan=\"3\">$ext->{'value'}</td></tr>\n";
		}
		$td = $td == 1 ? 2 : 1;
	}
	return $buffer;
}

sub _get_profile_fields {
	my ( $self, $scheme_id, $primary_key, $data, $td_ref ) = @_;
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $buffer;
	foreach my $locus (@$loci) {
		$buffer .= "<tr class=\"td$$td_ref\"><th style=\"text-align:right\">$locus&nbsp;</th>";
		my $allele_id =
		  $self->{'datastore'}->run_simple_query( "SELECT allele_id FROM profile_members WHERE scheme_id=? AND locus=? AND profile_id=?",
			$scheme_id, $locus, $data->{ $_->{'name'} } )->[0];
		$buffer .= "<td style=\"text-align:left\">$allele_id</td></tr>\n";
		$$td_ref = $$td_ref == 1 ? 2 : 1;
	}
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach my $field (@$scheme_fields) {
		next if $field eq $primary_key;
		$buffer .= "<tr class=\"td$$td_ref\"><th style=\"text-align:right\">$field&nbsp;</th>";
		my $value_ref =
		  $self->{'datastore'}->run_simple_query( "SELECT value FROM profile_fields WHERE scheme_id=? AND scheme_field=? AND profile_id=?",
			$scheme_id, $field, $data->{ $_->{'name'} } );
		if ( ref $value_ref eq 'ARRAY' ) {
			$buffer .= "<td style=\"text-align:left\">$value_ref->[0]</td></tr>\n";
		} else {
			$buffer .= "<td /></tr>\n";
		}
		$$td_ref = $$td_ref == 1 ? 2 : 1;
	}
	return $buffer;
}

sub get_title {
	my ($self) = @_;
	my $desc  = $self->{'system'}->{'description'} || 'BIGSdb';
	my $table = $self->{'cgi'}->param('table');
	my $type  = $self->get_record_name($table) || 'record';
	return "Delete $type - $desc";
}

sub _get_tables_which_reference_table {
	my ( $self, $table ) = @_;
	my %tables;
	foreach my $table2 ( $self->{'datastore'}->get_tables ) {
		if ( !( $self->{'system'}->{'dbtype'} eq 'isolates' && ( $table2 eq $self->{'system'}->{'view'} || $table2 eq 'isolates' ) )
			&& $table2 ne $table )
		{
			my $attributes = $self->{'datastore'}->get_table_field_attributes($table2);
			if ( ref $attributes eq 'ARRAY' ) {
				foreach my $att (@$attributes) {
					if (   ( $att->{'foreign_key'} && $att->{'foreign_key'} eq $table )
						|| ( $table eq 'users' && $att->{'name'} eq 'sender' ) )
					{
						$tables{$table2} = $att->{'name'};
					}
				}
			}
		}
	}
	return %tables;
}
1;
