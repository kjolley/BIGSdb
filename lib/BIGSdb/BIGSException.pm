#Written by Keith Jolley
#(c) 2010-2012, University of Oxford
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

package BIGSdb::BIGSException;
use strict;
use warnings;
use parent qw(Error);
use overload ( '""' => 'stringify' );
no warnings 'redefine';

sub new {
	my ($self,$text) = @_;
	my @args = ();
	local $Error::Depth = $Error::Depth + 1;
	local $Error::Debug = 1;                   # Enables storing of stacktrace
	return $self->SUPER::new( -text => $text, @args );
}
1;

## no critic (ProhibitMultiplePackages)
#Database exceptions
package BIGSdb::DatabaseException;
use parent qw(BIGSdb::BIGSException);
1;

package BIGSdb::DatabaseConnectionException;
use parent -norequire, qw(BIGSdb::DatabaseException);
1;

package BIGSdb::DatabaseConfigurationException;
use parent -norequire, qw(BIGSdb::DatabaseException);
1;

package BIGSdb::DatabaseNoRecordException;
use parent -norequire, qw(BIGSdb::DatabaseException);
1;

package BIGSdb::PrefstoreConfigurationException;
use parent -norequire, qw(BIGSdb::DatabaseException);
1;

#Server exceptions
package BIGSdb::ServerException;
use parent qw(BIGSdb::BIGSException);
1;

package BIGSdb::ServerBusyException;
use parent -norequire, qw(BIGSdb::ServerException);
1;

#File exceptions
package BIGSdb::FileException;
use parent qw(BIGSdb::BIGSException);
1;

package BIGSdb::FileDoesNotExistException;
use parent -norequire, qw(BIGSdb::FileException);
1;

package BIGSdb::CannotOpenFileException;
use parent -norequire, qw(BIGSdb::FileException);
1;

#Data exceptions
package BIGSdb::DataException;
use parent qw(BIGSdb::BIGSException);
1;

package BIGSdb::DataWarning;
use parent qw(BIGSdb::BIGSException);
1;

#Authentication exceptions
package BIGSdb::AuthenticationException;
use parent qw(BIGSdb::BIGSException);
1;

#Plugins
package BIGSdb::PluginException;
use parent qw(BIGSdb::BIGSException);
1;

package BIGSdb::InvalidPluginException;
use parent -norequire, qw(BIGSdb::PluginException);

1;


