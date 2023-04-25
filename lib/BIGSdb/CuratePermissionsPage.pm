#Written by Keith Jolley
#Copyright (c) 2014-2020, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
package BIGSdb::CuratePermissionsPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Constants qw(SUBMITTER_ALLOWED_PERMISSIONS);

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/administration.html#curator-permissions";
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Set curator permissions</h1>);
	if ( !$self->can_modify_table('permissions') ) {
		$self->print_bad_status(
			{
				message => q(Your account has insufficient privileges to modify curator permissions.)
			}
		);
		return;
	}
	my ( $curators, $labels ) = $self->{'datastore'}->get_users( { curators => 1 } );
	my %submitter_allowed = map { $_ => 1 } SUBMITTER_ALLOWED_PERMISSIONS;
	if ( !@$curators ) {
		$self->print_bad_status( { message => q(There are no curator defined for this database.) } );
		return;
	}
	if ( $q->param('update') ) {
		$self->_update;
	}
	say q(<div class="box" id="queryform"><div class="scrollable">);
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Select curator(s)</legend>);
	my @curator_list = $q->multi_param('curators');
	say $self->popup_menu(
		-name     => 'curators',
		-id       => 'curators',
		-values   => $curators,
		-labels   => $labels,
		-multiple => 'true',
		-default  => \@curator_list,
		-size     => 8
	);
	say q(<div style="text-align:center"><input type="button" onclick='listbox_selectall("curators",true)' )
	  . q(value="All" style="margin-top:1em" class="small_submit" />);
	say q(<input type="button" )
	  . q(onclick='listbox_selectall("curators",false)' value="None" style="margin-top:1em" )
	  . q(class="small_submit" /></div>);
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Select' } );
	say $q->hidden($_) foreach qw(db page);
	say $q->end_form;
	my $permission_list = $self->_get_permission_list;
	say q(</div></div>);

	if (@curator_list) {
		my $curator_count = @curator_list;
		my %selected = map { $_ => 1 } @curator_list;
		say q(<div class="box" id="resultstable"><div class="scrollable">);
		say q(<p>Check the boxes for the required permissions.  Users with a status of 'submitter' )
		  . q(have a restricted list of allowed permissions that can be selected. Attributes with a )
		  . q(<span class="warning">red background</span> add restrictions.</p>);
		say $q->start_form;
		say q(<fieldset style="float:left"><legend>Update permissions</legend>);
		say q(<table class="resultstable"><tr><th rowspan="2">Permission</th>)
		  . qq(<th colspan="$curator_count">Curator</th><th rowspan="2">All/None</th></tr><tr>);
		my $permissions = {};
		my $user_info   = {};

		foreach my $user_id (@$curators) {
			next if !$selected{$user_id};
			$user_info->{$user_id} = $self->{'datastore'}->get_user_info($user_id);
			my $style = $user_info->{$user_id}->{'status'} eq 'admin' ? q ( style="background:#f44") : q();
			say qq(<th$style>$user_info->{$user_id}->{'surname'}, $user_info->{$user_id}->{'first_name'}</th>);
			$permissions->{$user_id} = $self->{'datastore'}->get_permissions( $user_info->{$user_id}->{'user_name'} );
		}
		say q(</tr>);
		my $td = 1;
		my %prohibit = map { $_ => 1 } qw(disable_access only_private);
		foreach my $permission (@$permission_list) {
			( my $cleaned_permission = $permission ) =~ tr/_/ /;
			say $prohibit{$permission} ? q(<tr class="warning">) : qq(<tr class="td$td">);
			say qq(<th>$cleaned_permission</th>);
			foreach my $user_id (@$curators) {
				next if !$selected{$user_id};
				print q(<td>);
				if (   $user_info->{$user_id}->{'status'} eq 'curator'
					|| $user_info->{$user_id}->{'status'} eq 'admin'
					|| ( $user_info->{$user_id}->{'status'} eq 'submitter' && $submitter_allowed{$permission} ) )
				{
					print $q->checkbox(
						-name    => "${permission}_$user_id",
						-id      => $prohibit{$permission} ? undef : "${permission}_$user_id",
						-label   => '',
						-checked => $permissions->{$user_id}->{$permission}
					);
				}
				print q(</td>);
			}
			print q(<td>);
			print $q->checkbox( -name => "${permission}_allnone", -id => "${permission}_allnone", -label => q() )
			  if !$prohibit{$permission};
			say q(</td></tr>);
			$td = $td == 1 ? 2 : 1;
		}
		print qq(<tr class="td$td"><th>All/None</th>);
		foreach my $user_id (@$curators) {
			next if !$selected{$user_id};
			print q(<td>);
			print $q->checkbox( -name => "user_${user_id}_allnone", -id => "user_${user_id}_allnone", -label => q() );
		}
		say q(</td><td></td></tr>);
		say q(</table>);
		say q(</fieldset>);
		$self->print_action_fieldset( { no_reset => 1, submit_label => 'Update' } );
		$q->param( update => 1 );
		say $q->hidden($_) foreach (qw(db page curators update));
		say $q->end_form;
		say q(</div></div>);
	}
	return;
}

sub _get_permission_list {
	my ($self) = @_;
	my $attributes = $self->{'datastore'}->get_table_field_attributes('permissions');
	my @permission_list;
	foreach my $att (@$attributes) {
		if ( $att->{'name'} eq 'permission' ) {
			@permission_list = split /;/x, $att->{'optlist'};
			last;
		}
	}
	return \@permission_list;
}

sub _update {
	my ($self)        = @_;
	my $q             = $self->{'cgi'};
	my @curator_list  = $q->multi_param('curators');
	my $curator_count = @curator_list;
	my $permissions   = {};
	my %selected = map { $_ => 1 } @curator_list;
	my $permission_list = $self->_get_permission_list;
	my ( @additions, @deletions );
	my $curator_id = $self->get_curator_id;

	foreach my $user_id (@curator_list) {
		next if !$selected{$user_id};
		my $user_info = $self->{'datastore'}->get_user_info($user_id);
		$permissions->{$user_id} = $self->{'datastore'}->get_permissions( $user_info->{'user_name'} );
		foreach my $permission (@$permission_list) {
			if ( $q->param("${permission}_$user_id") ) {
				if ( !$permissions->{$user_id}->{$permission} ) {
					push @additions, { user_id => $user_id, permission => $permission };
				}
			} else {
				if ( $permissions->{$user_id}->{$permission} ) {
					push @deletions, { user_id => $user_id, permission => $permission };
				}
			}
		}
	}
	if ( @additions || @deletions ) {
		eval {
			if (@additions) {
				my $sql =
				  $self->{'db'}
				  ->prepare('INSERT INTO permissions (user_id,permission,curator,datestamp) VALUES (?,?,?,?)');
				$sql->execute( $_->{'user_id'}, $_->{'permission'}, $curator_id, 'now' ) foreach @additions;
			}
			if (@deletions) {
				my $sql = $self->{'db'}->prepare('DELETE FROM permissions WHERE (user_id,permission) = (?,?)');
				$sql->execute( $_->{'user_id'}, $_->{'permission'} ) foreach @deletions;
			}
		};
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
			$self->print_bad_status( { message => q(Update failed.) } );
		} else {
			$self->{'db'}->commit;
			my $total = @additions + @deletions;
			my $plural = $total == 1 ? q() : q(s);
			$self->print_good_status( { message => qq($total update$plural made.) } );
		}
	} else {
		$self->print_bad_status( { message => q(No changes made.) } );
	}
	return;
}

sub get_javascript {
	return <<"JS";
function listbox_selectall(listID, isSelect) {
	var listbox = document.getElementById(listID);
	for(var count=0; count < listbox.options.length; count++) {
		listbox.options[count].selected = isSelect;
	}
}
\$(document).ready(function() { 
    \$('input:checkbox').change(
    function(){
        if (\$(this).attr('id').match("allnone\$") ) {
        	var permission = \$(this).attr('id').replace('_allnone','');
        	\$("[id^=" + permission + "]").prop('checked',\$(this).is(':checked') ? true : false);
        	var pattern = /^user_(.+)_allnone/;
        	var user = \$(this).attr('id').match(pattern);
        	if (user && user[1]){
        		\$("[id\$='_" + user[1] + "']").prop('checked',\$(this).is(':checked') ? true : false);
        	}
        }
    });     
  } 
); 	
JS
}

sub get_title {
	return q(Set curator permissions);
}
1;
