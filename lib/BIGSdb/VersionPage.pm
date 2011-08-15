#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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

package BIGSdb::VersionPage;
use strict;
use base qw(BIGSdb::Page);

sub print_content {
	print <<"HTML";

<h1>Bacterial Isolate Genome Sequence Database (BIGSdb)</h1>\n
<div class="box" id="resultstable">
<h2>Version $BIGSdb::main::VERSION</h2>\n
<p>Written by Keith Jolley<br />\n
Copyright &copy; University of Oxford, 2010-2011.</p>\n
<p>
BIGSdb is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.</p>

<p>BIGSdb is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.</p>

<p>Full details of the GNU General Public License
can be found at <a href="http://www.gnu.org/licenses/gpl.html">http://www.gnu.org/licenses/gpl.html</a>.</p>

<p>Details of this software and the latest version can be downloaded from 
<a href=\"http://pubmlst.org/software/database/bigsdb/\">
http://pubmlst.org/software/database/bigsdb/</a>.</p>
</div>
HTML
}

sub get_title {
	return "BIGSdb Version $BIGSdb::main::VERSION";
}

1;