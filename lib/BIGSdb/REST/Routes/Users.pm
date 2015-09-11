#Written by Keith Jolley
#Copyright (c) 2014-2015, University of Oxford
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
package BIGSdb::REST::Routes::Users;
use strict;
use warnings;
use 5.010;
use Dancer2 appname => 'BIGSdb::REST::Interface';
use BIGSdb::Utils;

#User routes
get '/db/:db/users/:user' => sub { _get_user() };

sub _get_user {
	my $self    = setting('self');
	my $user_id = param('user');
	if ( !BIGSdb::Utils::is_int($user_id) ) {
		send_error( 'User id must be an integer.', 400 );
	}
	my $user =
	  $self->{'datastore'}->run_query( 'SELECT * FROM users WHERE id=?', $user_id, { fetch => 'row_hashref' } );
	if ( !defined $user->{'id'} ) {
		send_error( "User $user_id does not exist.", 404 );
	}
	my $values = {};
	foreach my $field (qw(id first_name surname affiliation email)) {

		#Only include E-mail for curators/admins
		next if $field eq 'email' && !$self->{'system'}->{'privacy'} && $user->{'status'} eq 'user';
		$values->{$field} = $user->{$field};
	}
	return $values;
}
1;
