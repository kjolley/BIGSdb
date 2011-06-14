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
package BIGSdb::CurateDeletePage;
use strict;
use base qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self)      = @_;
	my $q           = $self->{'cgi'};
	my $table       = $q->param('table');
	my $record_name = $self->get_record_name($table);
	if ( !$self->{'datastore'}->is_table($table) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Table $table does not exist!</p></div>\n";
		return;
	}
	print "<h1>Delete $record_name</h1>\n";
	if ( !$self->can_modify_table($table) ) {
		if ( $table eq 'sequences' && $q->param('locus') ) {
			my $locus = $q->param('locus');
			print
"<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to delete $locus sequences from the database.</p></div>\n";
		} else {
			print
"<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to delete records from the $table table.</p></div>\n";
		}
		return;
	} elsif ( ( $self->{'system'}->{'read_access'} eq 'acl' || $self->{'system'}->{'write_access'} eq 'acl' )
		&& $self->{'username'}
		&& !$self->is_admin
		&& $q->param('isolate_id')
		&& !$self->is_allowed_to_view_isolate( $q->param('isolate_id') ) )
	{
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to modify this isolate.</p></div>\n";
		return;
	} elsif (($table eq 'sequence_refs' || $table eq 'accession') && $q->param('locus')){
		my $locus = $q->param('locus');
		if (!$self->is_admin){
			my $allowed = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM locus_curators WHERE locus=? AND curator_id=?",$locus,$self->get_curator_id)->[0];
			if (!$allowed){
				print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to delete ". ($table eq 'sequence_refs' ? 'references' : 'accession numbers') ." for this locus.</p></div>\n";
				return;					
			}
		}
	}
	if ( ( $table eq 'scheme_fields' || $table eq 'scheme_members' ) && $self->{'system'}->{'dbtype'} eq 'sequences' && !$q->param('sent') )
	{
		print
		  "<div class=\"box\" id=\"warning\"><p>Please be aware that any modifications to the structure of this scheme will result in the
		removal of all data from it. This is done to ensure data integrity.  This does not affect allele designations, but any profiles
		will have to be reloaded.</p></div>\n";
	}
	my $buffer;
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my @query_values;
	my %primary_keys;
	foreach (@$attributes) {
		if ( $_->{'primary_key'} eq 'yes' ) {
			my $value = $q->param( $_->{'name'} );
			$value =~ s/'/\\'/g;
			push @query_values, "$_->{'name'} = '$value'";
			$primary_keys{ $_->{'name'} } = 1 if defined $q->param( $_->{'name'} );
			if ( $_->{'type'} eq 'int' && !BIGSdb::Utils::is_int( $q->param( $_->{'name'} ) ) ) {
				print "<div class=\"box\" id=\"statusbad\"><p>Field $_->{'name'} must be an integer.</p></div>\n";
			}
		}
	}
	if ( scalar @query_values != scalar keys %primary_keys ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Insufficient identifying attributes sent.</p></div>\n";
		return;
	}
	$" = ' AND ';
	my $qry = "SELECT * FROM $table WHERE @query_values";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute(); };
	if ($@) {
		$logger->error("Can't execute: $qry");
	} else {
		$logger->debug("Query: $qry");
	}
	my $data = $sql->fetchrow_hashref();
	$buffer .= $q->start_form;
	$buffer .= "<div class=\"box\" id=\"resultstable\">\n";
	$buffer .= "<p>You have chosen to delete the following record:</p>\n";
	if ( scalar @$attributes > 10 ) {
		$buffer .= "<p />";
		$buffer .= $q->submit( -name => 'submit', -value => 'Delete!', -class => 'submit' );
	}
	$buffer .= $q->hidden('page');
	$buffer .= $q->hidden('db');
	$buffer .= $q->hidden( 'sent', 1 );
	$buffer .= $q->hidden('table');
	foreach (@$attributes) {
		if ( $_->{'primary_key'} eq 'yes' ) {
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
			$value =~ s/\&/\&amp;/g;
		}
		if ( $_->{'name'} =~ /sequence$/ && $_->{'name'} ne 'coding_sequence' ) {
			my $value_length = length($value);
			if ( $value_length > 5000 ) {
				$value = BIGSdb::Utils::truncate_seq( \$value, 30 );
				$buffer .=
"<td style=\"text-align:left\"><span class=\"seq\">$value</span><br />Sequence is $value_length characters (too long to display)</td></tr>\n";
			} else {
				$value = BIGSdb::Utils::split_line($value);
				$buffer .= "<td style=\"text-align:left\" class=\"seq\">$value</td></tr>\n";
			}
		} elsif ( $_->{'name'} eq 'curator' or $_->{'name'} eq 'sender' ) {
			my $user = $self->{'datastore'}->get_user_info($value);
			$buffer .= "<td style=\"text-align:left\">$user->{'first_name'} $user->{'surname'}</td></tr>\n";
		} elsif ( $_->{'name'} eq 'scheme_id' ) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($value);
			$buffer .= "<td style=\"text-align:left\">$value) $scheme_info->{'description'}</td></tr>\n";
		} elsif ( $_->{'foreign_key'} && $_->{'labels'} ) {
			my @fields_to_query;
			my @values = split /\|/, $_->{'labels'};
			foreach (@values) {
				if ( $_ =~ /\$(.*)/ ) {
					push @fields_to_query, $1;
				}
			}
			$" = ',';
			my $qry = "select @fields_to_query from $_->{'foreign_key'} WHERE id=?";
			my $foreign_key_sql = $self->{'db'}->prepare($qry) or die;
			eval { $foreign_key_sql->execute($value); };
			if ($@) {
				$logger->error("Can't execute: $@ value:$value");
			}
			while ( my @labels = $foreign_key_sql->fetchrow_array() ) {
				my $label_value = $_->{'labels'};
				my $i           = 0;
				foreach (@fields_to_query) {
					$label_value =~ s/$_/$labels[$i]/;
					$i++;
				}
				$label_value =~ s/[\|\$]//g;
				$buffer .= "<td style=\"text-align:left\">$label_value</td></tr>\n";
			}
		} elsif ($_->{'name'} eq 'locus' && $self->{'system'}->{'locus_superscript_prefix'} eq 'yes'){
			$value =~ s/^([A-Za-z])_/<sup>$1<\/sup>/;
			$buffer .= "<td style=\"text-align:left\">$value</td></tr>\n";
		} else {
			$buffer .= "<td style=\"text-align:left\">$value</td></tr>\n";
		}
		$td = $td == 1 ? 2 : 1;
		if ( $table eq 'profiles' && $_->{'name'} eq 'profile_id' ) {
			my $scheme_id = $q->param('scheme_id');
			my $loci      = $self->{'datastore'}->get_scheme_loci($scheme_id);
			foreach my $locus (@$loci) {
				$buffer .= "<tr class=\"td$td\"><th style=\"text-align:right\">$locus&nbsp;</th>";
				my $allele_id =
				  $self->{'datastore'}
				  ->run_simple_query( "SELECT allele_id FROM profile_members WHERE scheme_id=? AND locus=? AND profile_id=?",
					$scheme_id, $locus, $data->{ $_->{'name'} } )->[0];
				$buffer .= "<td style=\"text-align:left\">$allele_id</td></tr>\n";
				$td = $td == 1 ? 2 : 1;
			}
			my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
			foreach my $field (@$scheme_fields) {
				next if $field eq $primary_key;
				$buffer .= "<tr class=\"td$td\"><th style=\"text-align:right\">$field&nbsp;</th>";
				my $value_ref =
				  $self->{'datastore'}
				  ->run_simple_query( "SELECT value FROM profile_fields WHERE scheme_id=? AND scheme_field=? AND profile_id=?",
					$scheme_id, $field, $data->{ $_->{'name'} } );
				if (ref $value_ref eq 'ARRAY'){
					$buffer .= "<td style=\"text-align:left\">$value_ref->[0]</td></tr>\n";
				} else {
					$buffer .= "<td /></tr>\n";
				}
				$td = $td == 1 ? 2 : 1;
			}
		}
	}
	if ( $table eq 'profiles' ) {
	}
	$buffer .= "</table>\n";
	if ($table eq 'allele_designations' ){
		$buffer.= "<div><fieldset>\n<legend>Options</legend>\n<ul>\n<li>\n";
		if ($self->can_modify_table('allele_sequences')){
			$buffer .= $q->checkbox(-name=>'delete_tags', -label => 'Also delete all sequence tags for this isolate/locus combination');
			$buffer .= "</li>\n<li>\n";
		}
		$buffer .= $q->checkbox(-name=>'delete_pending', -label => 'Also delete all pending designations for this isolate/locus combination');
		$buffer .= "</li>\n</ul>\n</fieldset>\n</div>\n";
	}
	$buffer .= $q->submit( -name => 'submit', -value => 'Delete!', -class => 'submit' );
	$buffer .= "</div>\n";
	$buffer .= $q->end_form();
	if ( $q->param('sent') ) {
		my $proceed = 1;
		my $nogo_buffer;
		if ( $table eq 'users' ) {

			#Don't delete yourself
			if ( $data->{'id'} == $self->get_curator_id() ) {
				$nogo_buffer .=
"<p>It's not a good idea to remove yourself as a curator!  If you really wish to do this, you'll need to do it from another curator account.</p>\n";
				$proceed = 0;
			}

			#Don't delete curators or admins unless you are an admin yourself
			elsif ( $data->{'status'} ne 'user' && !$self->is_admin() ) {
				$nogo_buffer .= "<p>Only administrators can delete users with curator or admin status!</p>\n";
				$proceed = 0;
			}
			if ($proceed) {
				my $sample_fields = $self->{'xmlHandler'}->get_sample_field_list;
				foreach my $table ( $self->{'datastore'}->get_tables_with_curator() ) {
					next if !@$sample_fields && $table eq 'samples';
					
					my $num =$self->{'datastore'}->run_simple_query( "SELECT count(*) FROM $table WHERE curator = ?", $data->{'id'} )->[0];
					my $num_senders;
					if ( $table eq $self->{'system'}->{'view'} ) {
						$num_senders =$self->{'datastore'}->run_simple_query( "SELECT count(*) FROM $table WHERE sender = ?", $data->{'id'} )->[0];
					} 
					if ($num || $num_senders) {
						my $plural = $num > 1 ? 's' : '';
						$nogo_buffer .=
						  "<p>User '$data->{'id'}' is the curator for $num record$plural in table '$table' - can not delete!</p>" if $num;
						  $nogo_buffer .=
						  "<p>User '$data->{'id'}' is the sender for $num_senders record$plural in table '$table' - can not delete!</p>" if $num_senders;
						$proceed = 0;
					}
				}
			}

			#don't delete 'All users' group
		} elsif ( $table eq 'user_groups' ) {
			if ( defined $data->{'id'} && $data->{'id'} == 0 ) {
				$nogo_buffer .= "<p>You can not delete the 'All users' group!</p>";
				$proceed = 0;
			}
		} elsif ( $table eq 'user_group_members' ) {
			if ( defined $data->{'user_group'} && $data->{'user_group'} == 0 ) {
				$nogo_buffer .= "<p>You can not remove members from the 'All users' group!</p>";
				$proceed = 0;
			}
		}

		#Check if record is a foreign key in another table
		if ( $proceed && $table ne 'composite_fields' && $table ne 'schemes' ) {
			my %tables_to_check = $self->_get_tables_which_reference_table($table);
			foreach ( keys %tables_to_check ) {
				next
				  if $table eq 'loci'
				  && ( $_ eq 'locus_aliases'
				    || $_ eq 'locus_descriptions'
					|| $_ eq 'allele_designations'
					|| $_ eq 'pending_allele_designations'
					|| $_ eq 'allele_sequences'
					|| $_ eq 'locus_curators'
					|| $_ eq 'client_dbase_loci' );           #cascade deletion of locus
				next if $table eq 'users' && ( $_ eq 'user_permissions' || $_ eq 'user_group_members' );    #cascade deletion of user
				next if $table eq 'sequence_bin' && $_ eq 'allele_sequences'; #cascade deletion of sequence bin records
				my $num =
				  $self->{'datastore'}->run_simple_query( "SELECT count(*) FROM $_ WHERE $tables_to_check{$_} = ?", $data->{'id'} )->[0];
				if ($num) {
					my $record_name = $self->get_record_name($table);
					my $plural = $num > 1 ? 's' : '';
					$data->{'id'} =~ s/'/\\'/g;
					$nogo_buffer .=
					  "<p>$record_name '$data->{'id'}' is referenced by $num record$plural in table '$_' - can not delete!</p>";
					$proceed = 0;
				}
			}
		}

		#special case to check that allele sequence is not used in a profile (profile database)
		if ( $proceed && $table eq 'sequences' && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
			my $num = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM profile_members WHERE locus=? AND allele_id=?",
				$data->{'locus'}, $data->{'allele_id'} )->[0];
			if ($num) {
				my $plural = $num > 1 ? 's' : '';
				$nogo_buffer .=
				  "<p>Sequence $data->{'locus'}-$data->{'allele_id'} is referenced by $num allelic profile$plural - can not delete!</p>";
				$proceed = 0;
			}

			#check isolate ACLs where appropriate
		} elsif ( $proceed && $table eq 'allele_designations' && !$self->is_allowed_to_view_isolate( $data->{'isolate_id'} ) ) {
			$nogo_buffer .= "<p>Your user account is not allowed to delete allele designations for this isolate.</p>\n";
			$proceed = 0;
		} elsif ( $proceed
			&& ( $self->{'system'}->{'read_access'} eq 'acl' || $self->{'system'}->{'write_access'} eq 'acl' )
			&& $self->{'username'}
			&& !$self->is_admin
			&& ( $table eq 'accession' || $table eq 'allele_sequences' )
			&& $self->{'system'}->{'dbtype'} eq 'isolates' )
		{
			my $isolate_id =
			  $self->{'datastore'}->run_simple_query( "SELECT isolate_id FROM sequence_bin WHERE id=?", $data->{'seqbin_id'} )->[0];
			if ( !$self->is_allowed_to_view_isolate($isolate_id) ) {
				my $record_type = $self->get_record_name($table);
				$nogo_buffer .=
"<p>The $record_type you are trying to delete belongs to an isolate to which your user account is not allowed to access.</p>";
				$proceed = 0;
			}
		}
		if ( !$proceed ) {
			print "<div class=\"box\" id=\"statusbad\">$nogo_buffer<p><a href=\""
			  . $q->script_name
			  . "?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
			return;
		}
		$buffer .= "</p>\n";
		if ( $q->param('submit') && $proceed ) {
			$" = ' AND ';
			my $qry = "DELETE FROM $table WHERE @query_values";
			if ($table eq 'allele_designations' && $self->can_modify_table('allele_sequences') && $q->param('delete_tags')){
				$qry .=  ";DELETE FROM allele_sequences WHERE seqbin_id IN (SELECT id FROM sequence_bin WHERE $query_values[0]) AND $query_values[1]";
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
				$logger->error("Couldn't delete record: $qry $@");
				print "<div class=\"box\" id=\"statusbad\"><p>Delete failed - transaction cancelled - no records have been touched.</p>\n";
				print "<p>Failed SQL: $qry</p>\n";
				print "<p>Error message: $@</p></div>\n";
				$self->{'db'}->rollback();
				return;
			}
			$self->{'db'}->commit()
			  && print "<div class=\"box\" id=\"resultsheader\"><p>$record_name deleted!</p>";
			if ( $table eq 'composite_fields' ) {
				print "<p><a href=\"" . $q->script_name . "?db=$self->{'instance'}&amp;page=compositeQuery\">Query another</a>";
			} elsif ( $table eq 'profiles'){
				my $scheme_id = $q->param('scheme_id');
				print "<p><a href=\"" . $q->script_name . "?db=$self->{'instance'}&amp;page=profileQuery&amp;scheme_id=$scheme_id\">Query another</a>";
			} else {
				print "<p><a href=\"" . $q->script_name . "?db=$self->{'instance'}&amp;page=tableQuery&amp;table=$table\">Query another</a>";
			}
			print " | <a href=\"" . $q->script_name . "?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
			$logger->debug("Deleted record: $qry");
			if ( $table eq 'allele_designations' ) {
				my $deltags;
				if ($q->param('delete_tags')){
					$deltags = "<br />$data->{'locus'}: sequence tag(s) deleted"
				}
				$self->update_history( $data->{'isolate_id'}, "$data->{'locus'}: designation '$data->{'allele_id'}' deleted$deltags" );

				#check if pending designation exists as this needs to be promoted.
				if ($q->param('delete_pending')){
					$self->delete_pending_designations($data->{'isolate_id'}, $data->{'locus'});
				} else {
					$self->promote_pending_allele_designation( $data->{'isolate_id'}, $data->{'locus'} );
				}
			} elsif ( $table eq 'pending_allele_designations' ) {
				$self->update_history( $data->{'isolate_id'}, "$data->{'locus'}: pending designation '$data->{'allele_id'}' deleted" );
			}
			return;
		}
	}
	print $buffer;
}

sub get_title {
	my ($self) = @_;
	my $desc  = $self->{'system'}->{'description'} || 'BIGSdb';
	my $table = $self->{'cgi'}->param('table');
	my $type  = $self->get_record_name($table);
	return "Delete $type - $desc";
}

sub _get_tables_which_reference_table {
	my ( $self, $table ) = @_;
	my %tables;
	foreach my $table2 ( $self->{'datastore'}->get_tables() ) {
		if (   $table2 ne $self->{'system'}->{'view'}
			&& $table2 ne 'isolates'
			&& $table2 ne $table )
		{
			my $attributes = $self->{'datastore'}->get_table_field_attributes($table2);
			if (ref $attributes eq 'ARRAY'){
				foreach (@$attributes) {
					if ( $_->{'foreign_key'} eq $table ) {
						$tables{$table2} = $_->{'name'};
					}
				}
			}
		}
	}
	return %tables;
}
1;
