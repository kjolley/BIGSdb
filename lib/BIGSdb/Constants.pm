#Written by Keith Jolley
#Copyright (c) 2015, University of Oxford
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
package BIGSdb::Constants;
use parent 'Exporter';
use strict;
use warnings;
our @EXPORT_OK;
our %EXPORT_TAGS;

#Limits
use constant MAX_UPLOAD_SIZE => 32 * 1024 * 1024;    #32Mb
push @EXPORT_OK, qw(MAX_UPLOAD_SIZE);
$EXPORT_TAGS{'limits'} = [qw(MAX_UPLOAD_SIZE)];

#Submissions
use constant SUBMISSIONS_DELETED_DAYS        => 90;
use constant COVERAGE                        => qw(<20x 20-49x 50-99x >100x);
use constant READ_LENGTH                     => qw(<100 100-199 200-299 300-499 >500);
use constant ASSEMBLY                        => ( 'de novo', 'mapped' );
use constant REQUIRES_READ_LENGTH => qw(Illumina);
use constant REQUIRES_COVERAGE    => qw(Illumina);
push @EXPORT_OK, qw (SUBMISSIONS_DELETED_DAYS COVERAGE READ_LENGTH ASSEMBLY REQUIRES_READ_LENGTH
  REQUIRES_COVERAGE);
$EXPORT_TAGS{'submissions'} = [
	qw (SUBMISSIONS_DELETED_DAYS COVERAGE READ_LENGTH ASSEMBLY REQUIRES_READ_LENGTH
	  REQUIRES_COVERAGE)
];
1;
