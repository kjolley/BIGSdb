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
package BIGSdb::CurateIsolateACLPage;
use strict;
use warnings;
use parent qw(BIGSdb::CuratePage);
use Error qw(:try);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $query  = $q->param('query');
	if ($query) {
		$query =~ s/SELECT \*/SELECT id/;
		$query =~ s/ORDER BY.*//;
		my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
		foreach (@$schemes) {
			if ( $query =~ /temp_scheme_$_\s/ ) {
				try {
					$self->{'datastore'}->create_temp_scheme_table($_);
				} catch BIGSdb::DatabaseConnectionException with {
					print
"<div class=\"box\" id=\"statusbad\"><p>Can't copy data into temporary table - please check scheme configuration (more details will be in the log file).</p></div>\n";					
					$logger->error("Can't copy data to temporary table.");
				};
			}
		}
		my $ids = $self->{'datastore'}->run_list_query($query);
		print "<h1>Batch modify access control list</h1>\n";
		$self->_batch_update($ids);
	} else {
		my $isolate_id = $q->param('id');
		print "<h1>Modify access control list";
		if ( $isolate_id && !BIGSdb::Utils::is_int($isolate_id) ) {
			print "</h1><div class=\"box\" id=\"statusbad\"><p>Isolate id must be an integer.</p></div>\n";
			return;
		}
		if ($isolate_id) {
			if ( $self->is_allowed_to_view_isolate($isolate_id) ) {
				my $isolate_name =
				  $self->{'datastore'}->run_simple_query( "SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id )->[0];
				print " - isolate $isolate_id: $isolate_name";
			} else {
				print
"</h1>\n<div class=\"box\" id=\"statusbad\"><p>Your user account does not have permission to modify this isolate.</p></div>\n";
				return;
			}
		}
		print "</h1>";
		$self->_single_update($isolate_id);
	}
}

sub _print_selector_list {
	my ( $self, $type, $isolate_id ) = @_;
	my $qry =
	  $type eq 'Group'
	  ? "SELECT id,description FROM user_groups WHERE id NOT IN (SELECT user_group_id FROM isolate_usergroup_acl WHERE isolate_id=?) ORDER BY description"
	  : "SELECT id,first_name,surname,affiliation FROM users WHERE id NOT IN (SELECT user_id FROM isolate_user_acl WHERE isolate_id=?) AND id>0  ORDER BY surname,first_name";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute($isolate_id) };
	$logger->error($@) if $@;
	my @list;
	my %labels;
	$" = ' ';
	while ( my @data = $sql->fetchrow_array ) {
		my $id = shift @data;
		push @list, $id;
		my $affiliation = defined $data[2] ? pop @data: '';
		if ( length $affiliation > 50 ) {
			$affiliation = ( substr $affiliation, 0, 25 ) . ' ... ' . ( substr $affiliation, -25 );
		}
		$labels{$id} = "@data";
		$labels{$id} .= " ($affiliation)" if $affiliation;
	}
	if ( scalar @list ) {
		print $self->{'cgi'}
		  ->scrolling_list( -name => "$type\_list", -values => \@list, -size => 10, -multiple => 'true', -labels => \%labels );
	} else {
		push @list, 'Empty list';
		print $self->{'cgi'}->scrolling_list( -name => "$type\_list", -values => \@list, -size => 10, -disabled => 'disabled' );
	}
}

sub _single_update {
	my ( $self, $isolate_id ) = @_;
	my $q          = $self->{'cgi'};
	my $curator_id = $self->get_curator_id;
	if ( $q->param('add_name') ) {
		$self->_add_names($isolate_id);
	} elsif ( $q->param('delete_name') ) {
		$self->_delete_names($isolate_id);
	} elsif ( $q->param('add_group') ) {
		$self->_add_group($isolate_id);
	} elsif ( $q->param('delete_group') ) {
		$self->_delete_group($isolate_id);
	} elsif ( $q->param('Group_update') ) {
		$self->_group_update($isolate_id);
	} elsif ( $q->param('User_update') ) {
		$self->_user_update($isolate_id);
	}
	print "<div class=\"box\" id=\"resultstable\">\n";
	print "<p>You can add access controls for multiple user groups or users by selecting them in the right-hand lists and clicking the
		'<<' buttons.  New access controls are set to read access only.  Change these by selecting the appropriate check boxes and updating.  Access
		controls can be removed by selecting the appropriate checkbox in the 'Remove' column and clicking the '>>' buttons.</p>\n";
	$self->_print_interface($isolate_id);
	print "</div>\n";
}

sub _print_interface {
	my ( $self, $isolate_id ) = @_;
	my $q = $self->{'cgi'};
	print "<h2>User groups</h2>\n";
	print $q->start_form;
	print "<table><tr><td>";
	$self->_print_access_table( 'Group', $isolate_id );
	print "</td><td>";
	print $q->submit( -name => 'add_group', -label => '<<', -class => 'submit' );
	print "<br />\n";
	print $q->submit( -name => 'delete_group', -label => '>>', -class => 'submit' );
	print "</td><td>Select group(s):<br />";
	$self->_print_selector_list( 'Group', $isolate_id );
	print "</td></tr></table>\n";
	print "<h2>Users</h2>\n";
	print "<table><tr><td>";
	$self->_print_access_table( 'User', $isolate_id );
	print "</td><td>";
	print $q->submit( -name => 'add_name', -label => '<<', -class => 'submit' );
	print "<br />\n";
	print $q->submit( -name => 'delete_name', -label => '>>', -class => 'submit' );
	print "</td><td>Select name(s):<br />";
	$self->_print_selector_list( 'User', $isolate_id );
	print "</td></tr></table>\n";
	print $q->hidden($_) foreach qw (db page id query);
	print $q->end_form;
}

sub _print_access_table {
	my ( $self, $type, $isolate_id ) = @_;
	my $q = $self->{'cgi'};
	print "<table><tr><th colspan=\"4\">Existing permissions</th></tr>\n";
	my $table = $type eq 'Group' ? 'isolate_usergroup_acl' : 'isolate_user_acl';
	print "<tr><th>Remove</th><th>$type</th><th>Read</th><th>Write</th></tr>";
	my $qry =
	  $type eq 'Group'
	  ? "SELECT read,write,user_groups.id,description FROM user_groups LEFT JOIN isolate_usergroup_acl ON user_groups.id=user_group_id WHERE isolate_id=? ORDER BY description"
	  : "SELECT read,write,users.id,first_name,surname FROM users LEFT JOIN isolate_user_acl ON users.id=user_id WHERE id>0 AND isolate_id=? ORDER BY surname,first_name";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute($isolate_id) };
	$logger->error($@) if $@;
	my $td = 1;
	my $count;
	$" = ' ';
	my ( @js, @js2, @js3, @js4, @js5, @js6 );
	while ( my ( $read, $write, @description ) = $sql->fetchrow_array ) {
		my $id = shift @description;
		print "<tr class=\"td$td\"><td style=\"text-align:center\">"
		  . $q->checkbox( -name => "$type\_select\_$id", -label => '', -checked => 0, -id => "$type\_select_$id" )
		  . "</td><td>@description</td><td style=\"text-align:center\">"
		  . $q->checkbox( -name => "$type\_read\_$id", -label => '', -checked => $read, -id => "$type\_read_$id" )
		  . "</td><td style=\"text-align:center\">"
		  . $q->checkbox( -name => "$type\_write\_$id", -label => '', -checked => $write, -id => "$type\_write_$id" )
		  . "</td></tr>\n";
		push @js,  "\$(\"#$type\_select_$id\").prop(\"checked\",true)";
		push @js2, "\$(\"#$type\_select_$id\").prop(\"checked\",false)";
		push @js3, "\$(\"#$type\_read_$id\").prop(\"checked\",true)";
		push @js4, "\$(\"#$type\_read_$id\").prop(\"checked\",false)";
		push @js5, "\$(\"#$type\_write_$id\").prop(\"checked\",true)";
		push @js6, "\$(\"#$type\_write_$id\").prop(\"checked\",false)";
		$td = $td == 1 ? 2 : 1;
		$count++;
	}
	if ($count) {
		$" = ';';
		print "<tr class=\"td$td\"><td style=\"text-align:center\">"
		  . "<input type=\"checkbox\" onclick='if (this.checked) {@js} else {@js2}' />"
		  . "</td><td></td><td style=\"text-align:center\">"
		  . "<input type=\"checkbox\" onclick='if (this.checked) {@js3} else {@js4}' />"
		  . "</td><td style=\"text-align:center\">"
		  . "<input type=\"checkbox\" onclick='if (this.checked) {@js5} else {@js6}' />"
		  . "</td></tr>\n";
		print "<tr><td colspan=\"4\" style=\"text-align:right\">";
		print $q->submit( -name => "$type\_update", -label => 'Update permissions', -class => 'submit' );
		print "</td></tr>\n";
	} else {
		print "<tr class=\"td$td\"><td colspan=\"4\" style=\"text-align:center\">No permissions set</td></tr>\n";
	}
	print "</table>\n";
}

sub _replicate_user_acls {
	my ( $self, $isolate_id, $ids_ref ) = @_;
	my $qry        = "SELECT user_id,read,write FROM isolate_user_acl WHERE isolate_id=?";
	my $sql        = $self->{'db'}->prepare($qry);
	my $sql_delete = $self->{'db'}->prepare("DELETE FROM isolate_user_acl WHERE isolate_id=?");
	my $sql_insert = $self->{'db'}->prepare("INSERT INTO isolate_user_acl (isolate_id,user_id,read,write) VALUES (?,?,?,?)");
	foreach my $isolate_id (@$ids_ref) {
		eval { $sql_delete->execute($isolate_id) };
		if ($@) {
			$self->{'db'}->rollback;
			$logger->error("Can't delete $@");
			return;
		}
	}
	eval { $sql->execute($isolate_id) };
	$logger->error($@) if $@;
	while ( my ( $user_id, $read, $write ) = $sql->fetchrow_array ) {
		foreach my $isolate_id (@$ids_ref) {
			eval { $sql_insert->execute( $isolate_id, $user_id, $read, $write ); };
			if ($@) {
				$logger->error("Can't insert $@; isolate $isolate_id, user_id $user_id");
				$self->{'db'}->rollback;
				return;
			}
		}
	}
	$self->{'db'}->commit;
}

sub _replicate_usergroup_acls {
	my ( $self, $isolate_id, $ids_ref ) = @_;
	my $qry        = "SELECT user_group_id,read,write FROM isolate_usergroup_acl WHERE isolate_id=?";
	my $sql        = $self->{'db'}->prepare($qry);
	my $sql_delete = $self->{'db'}->prepare("DELETE FROM isolate_usergroup_acl WHERE isolate_id=?");
	my $sql_insert = $self->{'db'}->prepare("INSERT INTO isolate_usergroup_acl (isolate_id,user_group_id,read,write) VALUES (?,?,?,?)");
	foreach my $isolate_id (@$ids_ref) {
		eval { $sql_delete->execute($isolate_id) };
		if ($@) {
			$self->{'db'}->rollback;
			$logger->error("Can't delete $@");
			return;
		}
	}
	eval { $sql->execute($isolate_id) };
	$logger->error($@) if $@;
	while ( my ( $user_id, $read, $write ) = $sql->fetchrow_array ) {
		foreach my $isolate_id (@$ids_ref) {
			eval { $sql_insert->execute( $isolate_id, $user_id, $read, $write ); };
			if ($@) {
				$logger->error("Can't insert $@; isolate $isolate_id, user_id $user_id");
				$self->{'db'}->rollback;
				return;
			}
		}
	}
	$self->{'db'}->commit;
}

sub _add_names {
	my ( $self, $isolate_id ) = @_;
	my $q         = $self->{'cgi'};
	my @user_list = $q->param('User_list');
	my $qry       = "INSERT INTO isolate_user_acl (isolate_id,user_id,read,write) VALUES (?,?,true,false)";
	my $sql       = $self->{'db'}->prepare($qry);
	foreach (@user_list) {
		eval { $sql->execute( $isolate_id, $_ ) };
		$logger->error($@) if $@;
	}
	$self->{'db'}->commit;
}

sub _add_group {
	my ( $self, $isolate_id ) = @_;
	my $q          = $self->{'cgi'};
	my @group_list = $q->param('Group_list');
	my $qry        = "INSERT INTO isolate_usergroup_acl (isolate_id,user_group_id,read,write) VALUES ($isolate_id,?,true,false)";
	my $sql        = $self->{'db'}->prepare($qry);
	foreach (@group_list) {
		eval { $sql->execute($_) };
		$logger->error($@) if $@;
	}
	$self->{'db'}->commit;
}

sub _delete_names {
	my ( $self, $isolate_id ) = @_;
	my $curator_id = $self->get_curator_id;
	my $q          = $self->{'cgi'};
	my $params     = $q->Vars;
	my $qry        = "DELETE FROM isolate_user_acl WHERE isolate_id=? and user_id=?";
	my $sql        = $self->{'db'}->prepare($qry);
	foreach ( keys %$params ) {
		if ( $_ =~ /User_select_(\d+)/ ) {
			if ( $1 == $curator_id && !$self->is_admin ) {
				print "<div class=\"box\" id=\"statusbad\"><p>Not removing your user account - user selection is being
						overridden to prevent you being locked out. Your access can be removed from another curator or admin account.</p></div>\n";
				next;
			}
			eval { $sql->execute( $isolate_id, $1 ) };
			$logger->error($@) if $@;
		}
	}
	$self->{'db'}->commit;
}

sub _delete_group {
	my ( $self, $isolate_id ) = @_;
	my $curator_id = $self->get_curator_id;
	my $q          = $self->{'cgi'};
	my $params     = $q->Vars;
	my $qry        = "DELETE FROM isolate_usergroup_acl WHERE isolate_id=? and user_group_id=?";
	my $sql        = $self->{'db'}->prepare($qry);
	foreach ( keys %$params ) {
		if ( $_ =~ /Group_select_(\d+)/ ) {
			eval { $sql->execute( $isolate_id, $1 ) };
			$logger->error($@) if $@;
		}
	}
	$self->{'db'}->commit;
}

sub _user_update {
	my ( $self, $isolate_id ) = @_;
	my $curator_id = $self->get_curator_id;
	my $q          = $self->{'cgi'};
	my $users      = $self->{'datastore'}->run_list_query( "SELECT user_id FROM isolate_user_acl WHERE isolate_id=?", $isolate_id );
	my $qry        = "UPDATE isolate_user_acl SET read=?,write=? WHERE isolate_id=? AND user_id=?";
	my $sql        = $self->{'db'}->prepare($qry);
	foreach (@$users) {
		my $read  = $q->param("User_read_$_")  ? 'true' : 'false';
		my $write = $q->param("User_write_$_") ? 'true' : 'false';
		if ( $_ == $curator_id && !$self->is_admin && ( $read eq 'false' || $write eq 'false' ) ) {
			print
"<div class=\"box\" id=\"statusbad\"><p>Preventing removal of read or write access to your user account for this isolate - user selection is being
				overridden to prevent you being locked out. Your access can be removed from another curator or admin account.</p></div>\n";
			$q->param( "User_read_$_",  'on' );
			$q->param( "User_write_$_", 'on' );
			$read  = 'true';
			$write = 'true';
		}
		eval { $sql->execute( $read, $write, $isolate_id, $_ ) };
		$logger->error($@) if $@;
	}
	$self->{'db'}->commit;
}

sub _group_update {
	my ( $self, $isolate_id ) = @_;
	my $curator_id = $self->get_curator_id;
	my $q          = $self->{'cgi'};
	my $groups = $self->{'datastore'}->run_list_query( "SELECT user_group_id FROM isolate_usergroup_acl WHERE isolate_id=?", $isolate_id );
	my $qry    = "UPDATE isolate_usergroup_acl SET read=?,write=? WHERE isolate_id=? AND user_group_id=?";
	my $sql    = $self->{'db'}->prepare($qry);
	foreach (@$groups) {
		my $read  = $q->param("Group_read_$_")  ? 'true' : 'false';
		my $write = $q->param("Group_write_$_") ? 'true' : 'false';
		eval { $sql->execute( $read, $write, $isolate_id, $_ ) };
		$logger->error($@) if $@;
	}
	$self->{'db'}->commit;
}

sub _batch_update {
	my ( $self, $ids_ref ) = @_;
	my $q          = $self->{'cgi'};
	my $curator_id = $self->get_curator_id;

	#Set batch to same controls as first isolate in list.
	my $isolate_id = shift @$ids_ref;
	if ( $q->param('add_name') ) {
		$self->_add_names($isolate_id);
		$self->_replicate_user_acls( $isolate_id, $ids_ref );
	} elsif ( $q->param('delete_name') ) {
		$self->_delete_names($isolate_id);
		$self->_replicate_user_acls( $isolate_id, $ids_ref );
	} elsif ( $q->param('User_update') ) {
		$self->_user_update($isolate_id);
		$self->_replicate_user_acls( $isolate_id, $ids_ref );
	} elsif ( $q->param('add_group') ) {
		$self->_add_group($isolate_id);
		$self->_replicate_usergroup_acls( $isolate_id, $ids_ref );
	} elsif ( $q->param('Group_update') ) {
		$self->_group_update($isolate_id);
		$self->_replicate_usergroup_acls( $isolate_id, $ids_ref );
	} elsif ( $q->param('delete_group') ) {
		$self->_delete_group($isolate_id);
		$self->_replicate_usergroup_acls( $isolate_id, $ids_ref );
	}
	my $isolate_name_ref =
	  $self->{'datastore'}->run_simple_query( "SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id );
	if ( ref $isolate_name_ref eq 'ARRAY' ) {
		my $isolate_name = $isolate_name_ref->[0];
		print "<div class=\"box\" id=\"resultstable\">\n";
		print "<p>You can add access controls for multiple user groups or users by selecting them in the right-hand lists and clicking the
		'<<' buttons.  New access controls are set to read access only.  Change these by selecting the appropriate check boxes and updating.  Access
		controls can be removed by selecting the appropriate checkbox in the 'Remove' column and clicking the '>>' buttons.</p>\n";
		print "<p><b>Please note:</b> some of these isolates may already have access controls set.  Any updates on this page will overwrite 
		existing controls.  Permissions displayed are those for isolate $isolate_id ($isolate_name). Updates will replicate on
		all other isolates in the selected query.</p>";
		$self->_print_interface($isolate_id);
		print "</div>\n";
	} else {
		print
"<p clsss=\"box\" id=\"statusbad\"><p>A problem has occurred viewing existing isolate controls.  You may not have permission to do so.</p></div>\n";
	}
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	my $table = $self->{'cgi'}->param('table');
	return "Modify isolate access control list - $desc";
}
1;
