#Written by Keith Jolley
#Copyright (c) 2012-2021, University of Oxford
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
package BIGSdb::CurateMembersPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use BIGSdb::Constants qw(:interface);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $table = $self->{'cgi'}->param('table');
	my $type = $self->get_record_name($table) // 'record';
	return qq(Batch update ${type}s);
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $table  = $q->param('table');
	my %valid_table = map { $_ => 1 } qw (user_group_members locus_curators scheme_curators);
	if ( !$self->{'datastore'}->is_table($table) ) {
		say q(<h1>Batch update</h1>);
		$self->print_bad_status( { message => qq(Table $table does not exist!) } );
		return;
	} elsif ( !$valid_table{$table} ) {
		say q(<h1>Batch update</h1>);
		$self->print_bad_status( { message => q(Invalid table selected!) } );
		return;
	}
	my $type = $self->get_record_name($table) // 'record';
	say qq(<h1>Batch update ${type}s </h1>);
	if ( !$self->can_modify_table($table) ) {
		$self->print_bad_status(
			{
				message => q(Your user account does not have permission to modify this table.)
			}
		);
		return;
	}
	$self->_print_interface;
	return;
}

sub _print_interface {
	my ($self)  = @_;
	my $q       = $self->{'cgi'};
	my $table   = $q->param('table');
	my $user_id = $q->param('users_list');
	if ( $user_id && BIGSdb::Utils::is_int($user_id) ) {
		$self->_perform_action($table);
		my $user_info = $self->{'datastore'}->get_user_info($user_id);
		if ( !$user_info ) {
			$self->print_bad_status( { message => q(Invalid user selected.) } );
			return;
		}
		say q(<div class="box" id="queryform">);
		say qq(<b>User: $user_info->{'first_name'} $user_info->{'surname'}</b>);
		say q(<p>Select values to enable or disable and then click the appropriate arrow button.</p>);
		my $table_data = $self->_get_table_data($table);
		say qq(<fieldset><legend>Select $table_data->{'plural'}</legend>);
		my $set_clause = '';
		my $set_id     = $self->get_set_id;

		if ($set_id) {
			if ( $table eq 'locus_curators' ) {

				#make sure 'id IN' has a space before it - used in the substitution
				#a few lines on (also matches scheme_id otherwise).
				$set_clause =
				    'AND ( id IN (SELECT locus FROM scheme_members WHERE scheme_id IN '
				  . "(SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)) OR id IN (SELECT "
				  . "locus FROM set_loci WHERE set_id=$set_id))";
			} elsif ( $table eq 'scheme_curators' ) {
				$set_clause = "AND ( id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id))";
			}
		}
		my $available = $self->{'datastore'}->run_query(
			"SELECT id FROM $table_data->{'parent'} WHERE id NOT IN (SELECT $table_data->{'foreign'} FROM $table "
			  . "WHERE $table_data->{'user_field'}=?) $set_clause ORDER BY $table_data->{'order'}",
			$user_id,
			{ fetch => 'col_arrayref' }
		);
		push @$available, q() if !@$available;
		$set_clause =~ s/id\ IN/$table_data->{'foreign'} IN/x;
		my $selected = $self->{'datastore'}->run_query(
			"SELECT $table_data->{'foreign'} FROM $table LEFT JOIN $table_data->{'parent'} ON "
			  . "$table_data->{'foreign'}=$table_data->{'id'} WHERE $table_data->{'user_field'}=? "
			  . "$set_clause ORDER BY $table_data->{'parent'}.$table_data->{'order'}",
			$user_id,
			{ fetch => 'col_arrayref' }
		);
		push @$selected, q() if !@$selected;
		my $labels = $self->_get_labels($table);
		say $q->start_form;
		say qq(<table><tr><th>Available</th><td></td><th>Selected</th></tr>\n<tr><td>);
		say $self->popup_menu(
			-name     => 'available',
			-id       => 'available',
			-values   => $available,
			-multiple => 'true',
			-labels   => $labels,
			-style    => 'min-width:10em; min-height:15em'
		);
		say q(</td><td>);
		my ( $add, $remove ) = ( RIGHT, LEFT );
		say qq(<button type="submit" name="add" value="add" class="smallbutton">$add</button>);
		say q(<br />);
		say qq(<button type="submit" name="remove" value="remove" class="smallbutton">$remove</button>);
		say q(</td><td>);
		say $self->popup_menu(
			-name     => 'selected',
			-id       => 'selected',
			-values   => $selected,
			-multiple => 'true',
			-labels   => $labels,
			-style    => 'min-width:10em; min-height:15em'
		);
		say q(</td></tr>);
		say q(<tr><td style="text-align:center"><input type="button" onclick='listbox_selectall("available",true)' )
		  . q(value="All" style="margin-top:1em" class="small_submit" />);
		say q(<input type="button" onclick='listbox_selectall("available",false)' value="None" )
		  . q(style="margin-top:1em" class="small_submit" /></td><td></td>);
		say q(<td style="text-align:center"><input type="button" onclick='listbox_selectall("selected",true)' )
		  . q(value="All" style="margin-top:1em" class="small_submit" />);
		say q(<input type="button" onclick='listbox_selectall("selected",false)' value="None" )
		  . q(style="margin-top:1em" class="small_submit" />);
		say q(</td></tr>);

		if ( $table eq 'locus_curators' ) {
			say q(<tr><td colspan="3" style="padding-top:0.5em">);
			say $q->checkbox(
				-name    => 'hide_public',
				-label   => 'Hide curator name from public view',
				-checked => 'checked'
			);
			say q(</td></tr>);
		}
		say q(</table>);
		say $q->hidden($_) foreach qw(db page table users_list);
		say $q->end_form;
		say q(</fieldset>);
		say q(<div>);
		say q(</div>);
	} else {
		say q(<div class="box" id="queryform">);
		say $self->_print_user_form;
	}
	say q(</div>);
	return;
}

sub _perform_action {
	my ( $self, $table ) = @_;
	my $q          = $self->{'cgi'};
	my $user_id    = $q->param('users_list');
	my $table_data = $self->_get_table_data($table);
	if ( $q->param('add') ) {
		my %qry = (
			locus_curators =>
			  'INSERT INTO locus_curators(locus,curator_id,hide_public,curator,datestamp) VALUES (?,?,?,?,?)',
			scheme_curators => 'INSERT INTO scheme_curators(scheme_id,curator_id,curator,datestamp) VALUES (?,?,?,?)',
			user_group_members =>
			  'INSERT INTO user_group_members(user_group,user_id,curator,datestamp) VALUES (?,?,?,?)'
		);
		my $sql_add    = $self->{'db'}->prepare( $qry{$table} );
		my $curator_id = $self->get_curator_id;
		eval {
			foreach my $record ( $q->multi_param('available') ) {
				next if $record eq '';
				my %method = (
					locus_curators => sub {
						$sql_add->execute( $record, $user_id, ( $q->param('hide_public') ? 'true' : 'false' ),
							$curator_id, 'now' );
					},
					scheme_curators => sub {
						$sql_add->execute( $record, $user_id, $curator_id, 'now' );
					},
					user_group_members => sub {
						$sql_add->execute( $record, $user_id, $curator_id, 'now' );
					}
				);
				$method{$table}->();
			}
		};
		if ($@) {
			$logger->error($@) if $@ !~ /duplicate/;
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
		}
	} elsif ( $q->param('remove') ) {
		my $qry        = "DELETE FROM $table WHERE $table_data->{'foreign'}=? AND  $table_data->{'user_field'}=?";
		my $sql_remove = $self->{'db'}->prepare($qry);
		eval {
			foreach my $record ( $q->multi_param('selected') ) {
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

sub _print_user_form {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $list   = $self->{'datastore'}->run_query( q(SELECT id FROM users WHERE id>0 AND status!='user'),
		undef, { fetch => 'col_arrayref', slice => {} } );
	my ( @users, %usernames );

	#We can't just get the user info directly from the users table as some users
	#may be defined in an external users database.
	foreach my $user_id (@$list) {
		my $user_info = $self->{'datastore'}->get_user_info($user_id);
		push @users, $user_id;
		$usernames{ $user_info->{'id'} } =
		  "$user_info->{'surname'}, $user_info->{'first_name'} ($user_info->{'user_name'})";
	}
	@users = sort { $usernames{$a} cmp $usernames{$b} } @users;
	say q(<fieldset><legend>Select user</legend>);
	say qq(<p>The user status must also be <a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . q(page=tableQuery&amp;table=users">set to curator</a> for permissions to work.</p>)
	  if $q->param('table') =~ /_curators$/x;
	say $q->start_form;
	say $self->get_filter( 'users', \@users, { class => 'display', labels => \%usernames } );
	say $q->submit( -name => 'Select', -class => 'small_submit' );
	say $q->hidden($_) foreach qw(db page table);
	say $q->end_form;
	say q(</fieldset>);
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
		%values = (
			parent     => 'loci',
			plural     => 'loci',
			id         => 'id',
			foreign    => 'locus',
			order      => 'id',
			user_field => 'curator_id'
		);
	} elsif ( $table eq 'scheme_curators' ) {
		%values = (
			parent     => 'schemes',
			plural     => 'schemes',
			id         => 'id',
			foreign    => 'scheme_id',
			order      => 'name',
			user_field => 'curator_id'
		);
	}
	return \%values;
}

sub _get_labels {
	my ( $self, $table ) = @_;
	my %labels;
	my $table_data = $self->_get_table_data($table);
	my $field = $table eq 'scheme_curators' ? 'name' : 'description';
	if ( $table ne 'locus_curators' ) {
		my $data = $self->{'datastore'}->run_query( "SELECT id, $field FROM $table_data->{'parent'}",
			undef, { fetch => 'all_arrayref', slice => {} } );
		$labels{ $_->{'id'} } = $_->{$field} foreach @$data;
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
