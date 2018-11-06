#Written by Keith Jolley
#(c) 2018, University of Oxford
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
package BIGSdb::Exceptions;
use strict;
use warnings;
use 5.010;
use Exception::Class (
	'BIGSdb::Exception::Database' => {
		description => 'Database-related exception'
	},
	'BIGSdb::Exception::Database::Connection' => {
		isa         => 'BIGSdb::Exception::Database',
		description => 'Database connection exception'
	},
	'BIGSdb::Exception::Database::Configuration' => {
		isa         => 'BIGSdb::Exception::Database',
		description => 'Database configuration exception'
	},
	'BIGSdb::Exception::Database::NoRecord' => {
		isa         => 'BIGSdb::Exception::Database',
		description => 'No matching record'
	},
	'BIGSdb::Exception::Prefstore' => {
		description => 'Prefstore-related exception'
	},
	'BIGSdb::Exception::Plugin' => {
		description => 'Plugin-related exception'
	},
	'BIGSdb::Exception::Plugin::Invalid' => {
		isa         => 'BIGSdb::Exception::Plugin',
		description => 'Plugin does not exist'
	},
	'BIGSdb::Exception::File' => {
		description => 'File-related exception'
	},
	'BIGSdb::Exception::File::NotExist' => {
		isa         => 'BIGSdb::Exception::File',
		description => 'File does not exist'
	},
	'BIGSdb::Exception::File::CannotOpen' => {
		isa         => 'BIGSdb::Exception::File',
		description => 'File cannot be opened'
	},
	'BIGSdb::Exception::Authentication' => {
		description => 'Authentication-related exception'
	},
	'BIGSdb::Exception::Data' => {
		description => 'Data-related exception'
	},
	'BIGSdb::Exception::Data::Warning' => {
		isa         => 'BIGSdb::Exception::Data',
		description => 'Data warning'
	},
	'BIGSdb::Exception::Server' => {
		description => 'Server-related exception'
	},
	'BIGSdb::Exception::Server::Busy' => {
		isa         => 'BIGSdb::Exception::Server',
		description => 'Server is too busy'
	  }
);
1;
