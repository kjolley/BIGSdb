#Written by Keith Jolley
#Copyright (c) 2010-2015, University of Oxford
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
	$buffer .= "<div class=\"box\" id=\"resultspanel\">\n";
	$buffer .= "<div class=\"scrollable\">";
	$buffer .= "<p>You have chosen to delete the following record:</p>\n";
	$buffer .= $q->hidden($_) foreach qw(page db table);
	$buffer .= $q->hidden( 'sent', 1 );
	foreach (@$attributes) {

		if ( $_->{'primary_key'} ) {
			$buffer .= $q->hidden( $_->{'name'}, $data->{ $_->{'name'} } );
		}
	}
	$buffer .= "<div id=\"record\"><dl class=\"data\">";
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
		next if $_->{'hide_query'} eq 'yes';
		( my $field_name = $_->{'name'} ) =~ tr/_/ /;
		if ( $table eq 'profiles' && $_->{'name'} eq 'profile_id' ) {
			$buffer .= "<dt>$primary_key</dt>";
		} else {
			$buffer .= "<dt>$field_name</dt>";
		}
		my $value;
		if ( $_->{'type'} eq 'bool' ) {
			$value = $data->{ $_->{'name'} } ? 'true' : 'false';
		} else {
			$value = $data->{ $_->{'name'} };
		}
		$value = BIGSdb::Utils::escape_html($value);
		if ( $_->{'name'} =~ /sequence$/ && $_->{'name'} ne 'coding_sequence' ) {
			$value //= ' ';
			my $value_length = length($value);
			if ( $value_length > 5000 ) {
				$value = BIGSdb::Utils::truncate_seq( \$value, 30 );
				$buffer .= "<dd><span class=\"seq\">$value</span> Sequence is $value_length characters (too long to display)</dd>\n";
			} else {
				$value = BIGSdb::Utils::split_line($value) || '';
				$buffer .= "<dd class=\"seq\">$value</dd>\n";
			}
		} elsif ( $_->{'name'} eq 'curator' or $_->{'name'} eq 'sender' ) {
			my $user = $self->{'datastore'}->get_user_info($value);
			$user->{'first_name'} //= '';
			$user->{'surname'}    //= '';
			$buffer .= "<dd>$user->{'first_name'} $user->{'surname'}</dd>\n";
		} elsif ( $_->{'name'} eq 'scheme_id' ) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($value);
			$buffer .= "<dd>$value) $scheme_info->{'description'}</dd>\n";
		} elsif ( $_->{'foreign_key'} && $_->{'labels'} ) {
			my @fields_to_query;
			my @values = split /\|/, $_->{'labels'};
			foreach (@values) {
				if ( $_ =~ /\$(.*)/ ) {
					push @fields_to_query, $1;
				}
			}
			local $" = ',';
			my $foreign_key_sql = $self->{'db'}->prepare("SELECT @fields_to_query FROM $_->{'foreign_key'} WHERE id=?");
			eval { $foreign_key_sql->execute($value) };
			$logger->error($@) if $@;
			while ( my @labels = $foreign_key_sql->fetchrow_array ) {
				my $label_value = $_->{'labels'};
				my $i           = 0;
				foreach (@fields_to_query) {
					$label_value =~ s/$_/$labels[$i]/;
					$i++;
				}
				$label_value =~ s/[\|\$]//g;
				$buffer .= "<dd>$label_value</dd>\n";
			}
		} elsif ( $_->{'name'} eq 'locus' ) {
			$value = $self->clean_locus($value);
			$buffer .= defined $value ? "<dd>$value</dd>\n" : '<dd>&nbsp;</dd>';
		} else {
			$value = '&nbsp;' if !defined $value || $value eq '';
			$buffer .= defined $value ? "<dd>$value</dd>\n" : '<dd>&nbsp;</dd>';
		}
		if ( $table eq 'profiles' && $_->{'name'} eq 'profile_id' ) {
			my $scheme_id = $q->param('scheme_id');
			$buffer .= $self->_get_profile_fields( $scheme_id, $primary_key, $data );
		}
	}
	if    ( $table eq 'sequences' )    { $buffer .= $self->_get_extra_sequences_fields($data) }
	elsif ( $table eq 'sequence_bin' ) { $buffer .= $self->_get_extra_seqbin_fields($data) }
	$buffer .= "</dl></div></div>\n";
	if ( $table eq 'allele_designations' ) {
		$buffer .= "<div><fieldset>\n<legend>Options</legend>\n<ul>\n<li>\n";
		if ( $self->can_modify_table('allele_sequences') ) {
			$buffer .= $q->checkbox( -name => 'delete_tags', -label => 'Also delete all sequence tags for this isolate/locus combination' );
			$buffer .= "</li>\n";
		}
		$buffer .= "</ul>\n</fieldset>\n</div>\n";
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
				if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
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
	}

	#Check if record is a foreign key in another table
	if ( $proceed && $table ne 'composite_fields' && $table ne 'schemes' ) {
		my %tables_to_check = $self->_get_tables_which_reference_table($table);
		foreach my $table_to_check ( keys %tables_to_check ) {

			#cascade deletion of locus
			next if $table eq 'loci' && any { $table_to_check eq $_ } qw (locus_aliases locus_descriptions allele_designations
			  allele_sequences locus_curators client_dbase_loci locus_extended_attributes);

			#cascade deletion of user
			next if $table eq 'users' && any { $table_to_check eq $_ } qw ( curator_permissions user_group_members);

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
	} elsif ( $proceed && $table eq 'allele_designations' && !$self->is_allowed_to_view_isolate( $data->{'isolate_id'} ) ) {
		$nogo_buffer .= "Your user account is not allowed to delete allele designations for this isolate.<br />\n";
		$proceed = 0;
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
		say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;scheme_id=$scheme_id\">"
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
	} elsif ( $table eq 'sequences' ) {
		$self->mark_cache_stale;
	}
	return;
}

sub _get_extra_sequences_fields {
	my ( $self, $data ) = @_;
	my $q      = $self->{'cgi'};
	my $buffer = '';
	if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
		my $flags = $self->{'datastore'}->get_allele_flags( $q->param('locus'), $q->param('allele_id') );
		local $" = '</a> <a class="seqflag_tooltip">';
		if (@$flags) {
			$buffer .= "<dt>flags&nbsp;</dt><dd><a class=\"seqflag_tooltip\">@$flags</a></dd>\n";
		}
	}
	foreach my $databank (DATABANKS) {
		my $accessions = $self->{'datastore'}->run_query(
			"SELECT databank_id FROM accession WHERE locus=? AND allele_id=? AND databank=? ORDER BY databank_id",
			[ $q->param('locus'), $q->param('allele_id'), $databank ],
			{ fetch => 'col_arrayref' }
		);
		foreach my $accession (@$accessions) {
			if    ( $databank eq 'Genbank' ) { $accession = qq(<a href="http://www.ncbi.nlm.nih.gov/nuccore/$accession">$accession</a>) }
			elsif ( $databank eq 'ENA' )     { $accession = qq(<a href="http://www.ebi.ac.uk/ena/data/view/$accession">$accession</a>) }
			$buffer .= "<dt>$databank&nbsp;</dt><dd>$accession</dd>\n";
		}
	}
	my $pubmed_list = $self->{'datastore'}->run_query(
		"SELECT pubmed_id FROM sequence_refs WHERE locus=? AND allele_id=? ORDER BY pubmed_id",
		[ $q->param('locus'), $q->param('allele_id') ],
		{ fetch => 'col_arrayref' }
	);
	my $citations = $self->{'datastore'}->get_citation_hash( $pubmed_list, { formatted => 1, all_authors => 1, link_pubmed => 1 } );
	foreach my $pmid (@$pubmed_list) {
		$buffer .= "<dt>reference&nbsp;</dt><dd>$citations->{$pmid}</dd>\n";
	}
	my $extended_attributes = $self->{'datastore'}->get_allele_extended_attributes( $q->param('locus'), $q->param('allele_id') );
	foreach my $ext (@$extended_attributes) {
		my $cleaned_field = $ext->{'field'};
		$cleaned_field =~ tr/_/ /;
		if ( $cleaned_field =~ /sequence$/ ) {
			my $seq = BIGSdb::Utils::split_line( $ext->{'value'} );
			$buffer .= qq(<dt>$cleaned_field&nbsp;</dt><dd class="seq">$seq</dd>\n);
		} else {
			$buffer .= "<dt>$cleaned_field&nbsp;</dt><dd>$ext->{'value'}</dd>\n";
		}
	}
	return $buffer;
}

sub _get_extra_seqbin_fields {
	my ( $self, $data ) = @_;
	my $q          = $self->{'cgi'};
	my $attributes = $self->{'datastore'}->run_query( "SELECT key,value FROM sequence_attribute_values WHERE seqbin_id=? ORDER BY key",
		$data->{'id'}, { fetch => 'all_arrayref', slice => {} } );
	my $buffer = '';
	foreach my $att (@$attributes) {
		( my $cleaned_field = $att->{'key'} ) =~ tr/_/ /;
		$buffer .= "<dt>$cleaned_field</dt><dd>$att->{'value'}</dd>\n";
	}
	return $buffer;
}

sub _get_profile_fields {
	my ( $self, $scheme_id, $primary_key, $data ) = @_;
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $buffer;
	foreach my $locus (@$loci) {
		my $mapped = $self->clean_locus( $locus, { no_common_name => 1 } );
		$buffer .= "<dt>$mapped&nbsp;</dt>";
		my $allele_id =
		  $self->{'datastore'}->run_query( "SELECT allele_id FROM profile_members WHERE scheme_id=? AND locus=? AND profile_id=?",
			[ $scheme_id, $locus, $data->{ $_->{'name'} } ] );
		$buffer .= "<dd>$allele_id</dd>\n";
	}
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach my $field (@$scheme_fields) {
		next if $field eq $primary_key;
		$buffer .= "<dt>$field&nbsp;</dt>";
		my $value =
		  $self->{'datastore'}->run_query( "SELECT value FROM profile_fields WHERE scheme_id=? AND scheme_field=? AND profile_id=?",
			[ $scheme_id, $field, $data->{ $_->{'name'} } ] );
		$buffer .= defined $value ? "<dd>$value</dd>\n" : "<dd>&nbsp;</dd>\n";
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

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery);
	return;
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
