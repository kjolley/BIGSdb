#Written by Keith Jolley
#Copyright (c) 2012-2014
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
package BIGSdb::CurateMembersPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use List::MoreUtils 0.28 qw(none);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $desc  = $self->{'system'}->{'description'} || 'BIGSdb';
	my $table = $self->{'cgi'}->param('table');
	my $type  = $self->get_record_name($table) // 'record';
	return "Batch update $type" . "s - $desc";
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $table  = $q->param('table');
	if ( !$self->{'datastore'}->is_table($table) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Table $table does not exist!</p></div>\n";
		return;
	} elsif (
		none {
			$table eq $_;
		}
		qw (user_group_members locus_curators scheme_curators)
	  )
	{
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid table selected!</p></div>\n";
		return;
	}
	my $type = $self->get_record_name($table) // 'record';
	print "<h1>Batch update $type" . "s </h1>\n";
	if ( !$self->can_modify_table($table) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account does not have permission to modify this table.<p></div>\n";
		return;
	}
	$self->_print_interface;
	return;
}

sub _print_interface {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $table  = $q->param('table');
	print "<div class=\"box\" id=\"queryform\">\n";
	my $user_id = $q->param('users_list');
	if ( $user_id && BIGSdb::Utils::is_int($user_id) ) {
		$self->_perform_action($table);
		my $user_info = $self->{'datastore'}->get_user_info($user_id);
		if ( !$user_info ) {
			print "<p class=\"statusbad\">Invalid user selected.</p>\n</div>\n";
			return;
		}
		print "<b>User: $user_info->{'first_name'} $user_info->{'surname'}</b>\n";
		print "<p>Select values to enable or disable and then click the appropriate arrow button.</p>\n";
		my $table_data = $self->_get_table_data($table);
		print "<fieldset><legend>Select $table_data->{'plural'}</legend>\n";
		my $set_clause = '';
		my $set_id     = $self->get_set_id;
		if ($set_id) {

			if ( $table eq 'locus_curators' ) {

				#make sure 'id IN' has a space before it - used in the substitution a few lines on (also matches scheme_id otherwise).
				$set_clause = "AND ( id IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM "
				  . "set_schemes WHERE set_id=$set_id)) OR id IN (SELECT locus FROM set_loci WHERE set_id=$set_id))";
			} elsif ( $table eq 'scheme_curators' ) {
				$set_clause = "AND ( id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id))";
			}
		}
		my $available = $self->{'datastore'}->run_list_query(
"SELECT id FROM $table_data->{'parent'} WHERE id NOT IN (SELECT $table_data->{'foreign'} FROM $table WHERE $table_data->{'user_field'}=?) $set_clause ORDER BY $table_data->{'order'}",
			$user_id
		);
		push @$available, '' if !@$available;
		$set_clause =~ s/id IN/$table_data->{'foreign'} IN/;
		my $selected = $self->{'datastore'}->run_list_query(
"SELECT $table_data->{'foreign'} FROM $table LEFT JOIN $table_data->{'parent'} ON $table_data->{'foreign'} = $table_data->{'id'} WHERE $table_data->{'user_field'}=? $set_clause ORDER BY $table_data->{'parent'}.$table_data->{'order'}",
			$user_id
		);
		push @$selected, '' if !@$selected;
		my $labels = $self->_get_labels($table);
		print $q->start_form;
		print "<table><tr><th>Available</th><td></td><th>Selected</th></tr>\n<tr><td>";
		print $q->popup_menu(
			-name     => 'available',
			-id       => 'available',
			-values   => $available,
			-multiple => 'multiple',
			-labels   => $labels,
			-style    => 'min-width:10em; min-height:15em'
		);
		print "</td><td>\n";
		print $q->submit( -name => 'add', -label => '>', -class => 'submit' );
		print "<br />\n";
		print $q->submit( -name => 'remove', -label => '<', -class => 'submit' );
		print "</td><td>\n";
		print $q->popup_menu(
			-name     => 'selected',
			-id       => 'selected',
			-values   => $selected,
			-multiple => 'multiple',
			-labels   => $labels,
			-style    => 'min-width:10em; min-height:15em'
		);
		print "</td></tr>\n";
		print "<tr><td style=\"text-align:center\"><input type=\"button\" onclick='listbox_selectall(\"available\",true)'"
		  . " value=\"All\" style=\"margin-top:1em\" class=\"smallbutton\" />\n";
		print "<input type=\"button\" onclick='listbox_selectall(\"available\",false)' value=\"None\" "
		  . "style=\"margin-top:1em\" class=\"smallbutton\" /></td><td></td>\n";
		print "<td style=\"text-align:center\"><input type=\"button\" onclick='listbox_selectall(\"selected\",true)' "
		  . "value=\"All\" style=\"margin-top:1em\" class=\"smallbutton\" />\n";
		print "<input type=\"button\" onclick='listbox_selectall(\"selected\",false)' value=\"None\" "
		  . "style=\"margin-top:1em\" class=\"smallbutton\" />\n";
		print "</td></tr>\n";

		if ( $table eq 'locus_curators' ) {
			print "<tr><td colspan=\"3\">\n";
			print $q->checkbox( -name => 'hide_public', -label => 'Hide curator name from public view', -checked => 'checked' );
			print "</td></tr>\n";
		}
		print "</table>\n";
		print $q->hidden($_) foreach qw(db page table users_list);
		print $q->end_form;
		print "</fieldset>\n";
		print "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back to main</a></p>\n";
	} else {
		print $self->_print_sender_form;
	}
	print "</div>\n";
	return;
}

sub _perform_action {
	my ( $self, $table ) = @_;
	my $q          = $self->{'cgi'};
	my $user_id    = $q->param('users_list');
	my $table_data = $self->_get_table_data($table);
	my $qry;
	if ( $q->param('add') ) {
		if    ( $table eq 'locus_curators' )  { $qry = "INSERT INTO locus_curators(locus,curator_id,hide_public) VALUES (?,?,?)" }
		elsif ( $table eq 'scheme_curators' ) { $qry = "INSERT INTO scheme_curators(scheme_id,curator_id) VALUES (?,?)" }
		elsif ( $table eq 'user_group_members' ) {
			$qry = "INSERT INTO user_group_members(user_group,user_id,curator,datestamp) VALUES (?,?,?,?)";
		}
		my $sql_add = $self->{'db'}->prepare($qry);
		eval {
			foreach my $record ( $q->param('available') )
			{
				next if $record eq '';
				if ( $table eq 'locus_curators' ) {
					$sql_add->execute( $record, $user_id, ( $q->param('hide_public') ? 'true' : 'false' ) );
				} elsif ( $table eq 'scheme_curators' ) {
					$sql_add->execute( $record, $user_id );
				} elsif ( $table eq 'user_group_members' ) {
					$sql_add->execute( $record, $user_id, $self->get_curator_id, 'now' );
				}
			}
		};
		if ($@) {
			$logger->error($@) if $@ !~ /duplicate/;
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
		}
	} elsif ( $q->param('remove') ) {
		$qry = "DELETE FROM $table WHERE $table_data->{'foreign'}=? AND  $table_data->{'user_field'}=?";
		my $sql_remove = $self->{'db'}->prepare($qry);
		eval {
			foreach my $record ( $q->param('selected') )
			{
				next if $record eq '';
				$sql_remove->execute( $record, $user_id );
			}
		};
		if ($@) {
			$logger->error($@) if $@ !~ /duplicate/;
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
		}
	}
	return;
}

sub _print_sender_form {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $list =
	  $self->{'datastore'}->run_list_query_hashref("SELECT id,user_name,first_name,surname from users WHERE id>0 order by surname");
	my ( @users, %usernames );
	foreach (@$list) {
		push @users, $_->{'id'};
		$usernames{ $_->{'id'} } = "$_->{'surname'}, $_->{'first_name'} ($_->{'user_name'})";
	}
	print "<fieldset><legend>Select user</legend>\n";
	print "<p>The user status must also be <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;"
	  . "page=tableQuery&amp;table=users\">set to curator</a> for permissions to work.</p>"
	  if $q->param('table') =~ /_curators$/;
	print $q->start_form;
	print $self->get_filter( 'users', \@users, { class => 'display', labels => \%usernames } );
	print $q->submit( -name => 'Select', -class => 'submit' );
	print $q->hidden($_) foreach qw(db page table);
	print $q->end_form;
	print "</fieldset>\n";
	return;
}

sub _get_table_data {
	my ( $self, $table ) = @_;
	my %values;
	if ( $table eq 'user_group_members' ) {
		%values = (
			parent     => 'user_groups',
			plural     => 'user groups',
			id         => 'id',
			foreign    => 'user_group',
			order      => 'description',
			user_field => 'user_id'
		);
	} elsif ( $table eq 'locus_curators' ) {
		%values = ( parent => 'loci', plural => 'loci', id => 'id', foreign => 'locus', order => 'id', user_field => 'curator_id' );
	} elsif ( $table eq 'scheme_curators' ) {
		%values = (
			parent     => 'schemes',
			plural     => 'schemes',
			id         => 'id',
			foreign    => 'scheme_id',
			order      => 'description',
			user_field => 'curator_id'
		);
	}
	return \%values;
}

sub _get_labels {
	my ( $self, $table ) = @_;
	my %labels;
	my $table_data = $self->_get_table_data($table);
	if ( $table ne 'locus_curators' ) {
		my $data = $self->{'datastore'}->run_list_query_hashref("SELECT id, description FROM $table_data->{'parent'}");
		$labels{ $_->{'id'} } = $_->{'description'} foreach @$data;
	}
	return \%labels;
}

sub get_javascript {
	my ($self) = @_;
	my $buffer = << "END";
function listbox_selectall(listID, isSelect) {
	\$("#" + listID + " option").prop("selected",isSelect);
}
END
	return $buffer;
}
1;
