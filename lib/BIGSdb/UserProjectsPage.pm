#Written by Keith Jolley
#Copyright (c) 2017, University of Oxford
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
package BIGSdb::UserProjectsPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description || 'BIGSdb';
	return "User projects - $desc";
}

sub print_content {
	my ($self) = @_;
	say q(<h1>User projects</h1>);
	return;
}

1;