#Written by Keith Jolley
#Copyright (c) 2020-2021, University of Oxford
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
package BIGSdb::BookmarksPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use BIGSdb::Constants qw(:interface);
use JSON;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	return 'Bookmarks';
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery jQuery.tablesort noCache);
	$self->set_level1_breadcrumbs;
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('delete') ) {
		$self->_delete;
	}
	if ( $q->param('share') ) {
		$self->_toggle_share;
	}
	say q(<h1>Bookmarks</h1>);
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	if ( !$user_info ) {
		$self->print_bad_status( { message => q(You are not logged in.), navbar => 1 } );
		return;
	}
	my $bookmarks = $self->{'datastore'}->run_query( 'SELECT * FROM bookmarks WHERE user_id=? ORDER BY name',
		$user_info->{'id'}, { fetch => 'all_arrayref', slice => {} } );
	if ( !@$bookmarks ) {
		$self->print_bad_status( { message => q(You have no bookmarks set for this database.), navbar => 1 } );
		return;
	}
	say q(<div class="box" id="resultstable">);
	say q(<p>Please note that only you will be able to access a query defined by a bookmark if it is shown as )
	  . q(locked.<p>)
	  . q(<p>Click the padlock icon to make it publicly shareable - you can then copy the URL from the 'Run query' )
	  . q(field and share this with colleagues.</p>);
	say q(<div class="scrollable">);
	my $show_sets = ( $self->{'system'}->{'sets'} // q() ) eq 'yes' && !defined $self->{'system'}->{'set_id'} ? 1 : 0;
	say q(<table class="tablesorter" id="sortTable" style="margin-bottom:1em"><thead>)
	  . q(<tr><th class="sorter-false">Delete</th><th>Name</th><th>Database configuration</th>);
	if ($show_sets) {
		say q(<th>Set</th>);
	}
	say q(<th>Created</th><th class="sorter-false">Share</th><th class="sorter-false">Run query</th></tr></thead>);
	my $td = 1;
	say q(<tbody>);
	my ( $query, $delete, $public, $private ) = ( QUERY, DELETE, UNLOCK, LOCK );
	foreach my $bookmark (@$bookmarks) {

		#The hidden span in the name field seems to be necessary due to a bug in the tablesorter
		#when values look like dates.
		print qq(<tr class="td$td">)
		  . qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=bookmarks&amp;delete=$bookmark->{'id'}">$delete</a></td>)
		  . qq(<td><span style="display:none">x</span>$bookmark->{'name'}</td><td>$bookmark->{'dbase_config'}</td>);
		if ($show_sets) {
			my $set_name;
			if ( defined $bookmark->{'set_id'} ) {
				$set_name =
				  $self->{'datastore'}->run_query( 'SELECT description FROM sets WHERE id=?', $bookmark->{'set_id'} );
			}
			$set_name //= 'Whole database';
			print qq(<td>$set_name</td>);
		}
		my $share = $bookmark->{'public'} ? $public : $private;
		say qq(<td>$bookmark->{'date_entered'}</td>)
		  . qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=bookmarks&amp;)
		  . qq(share=$bookmark->{'id'}">$share</td><td><a href="$self->{'system'}->{'script_name'}?)
		  . qq(db=$bookmark->{'dbase_config'}&amp;page=$bookmark->{'page'}&amp;)
		  . qq(bookmark=$bookmark->{'id'}">$query</a></td></tr>);
	}
	say q(</tbody></table>);
	say q(</div>);
	say q(</div>);
	return;
}

sub _delete {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $bookmark = $q->param('delete');
	return if !BIGSdb::Utils::is_int($bookmark);
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	return if !$user_info;
	my $is_owner = $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM bookmarks WHERE (id,user_id)=(?,?))',
		[ $bookmark, $user_info->{'id'} ] );
	return if !$is_owner;
	eval { $self->{'db'}->do( 'DELETE FROM bookmarks WHERE id=?', undef, $bookmark ); };

	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub _toggle_share {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $bookmark = $q->param('share');
	return if !BIGSdb::Utils::is_int($bookmark);
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	return if !$user_info;
	my $is_owner = $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM bookmarks WHERE (id,user_id)=(?,?))',
		[ $bookmark, $user_info->{'id'} ] );
	return if !$is_owner;
	my $public = $self->{'datastore'}->run_query( 'SELECT public FROM bookmarks WHERE id=?', $bookmark );
	eval {
		$self->{'db'}->do( 'UPDATE bookmarks SET public=? WHERE id=?', undef, $public ? 'false' : 'true', $bookmark );
	};

	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/data_query/0080_bookmarking_isolate_query.html";
}

sub get_javascript {
	return <<"JS";
\$(document).ready(function() 
    { 
        \$("#sortTable").tablesorter({widgets:['zebra']}); 
        \$("input.link").hover(function(){
        	\$(this).css('text-decoration','underline');
         }, function(){
         	\$(this).css('text-decoration','none');
         });
    } 
); 	
JS
}
1;
