#Written by Keith Jolley
#(c) 2010-2011, University of Oxford
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
use base qw(Error);
use overload ( '""' => 'stringify' );
no warnings 'redefine';

sub new {
	my ($self,$text) = @_;
	my @args = ();
	local $Error::Depth = $Error::Depth + 1;
	local $Error::Debug = 1;                   # Enables storing of stacktrace
	$self->SUPER::new( -text => $text, @args );
}
1;

#Database exceptions
package BIGSdb::DatabaseException;
use base qw(BIGSdb::BIGSException);
1;

package BIGSdb::DatabaseConnectionException;
use base qw(BIGSdb::DatabaseException);
1;

package BIGSdb::DatabaseConfigurationException;
use base qw(BIGSdb::DatabaseException);
1;

package BIGSdb::DatabaseNoRecordException;
use base qw(BIGSdb::DatabaseException);
1;

package BIGSdb::PrefstoreConfigurationException;
use base qw(BIGSdb::DatabaseException);
1;

#File exceptions
package BIGSdb::FileException;
use base qw(BIGSdb::BIGSException);
1;

package BIGSdb::FileDoesNotExistException;
use base qw(BIGSdb::FileException);
1;

package BIGSdb::CannotOpenFileException;
use base qw(BIGSdb::FileException);
1;

#Data exceptions
package BIGSdb::DataException;
use base qw(BIGSdb::BIGSException);
1;

#Authentication exceptions
package BIGSdb::AuthenticationException;
use base qw(BIGSdb::BIGSException);
1;

#Plugins
package BIGSdb::PluginException;
use base qw(BIGSdb::BIGSException);
1;

package BIGSdb::InvalidPluginException;
use base qw(BIGSdb::PluginException);

1;


