Important notes about upgrading
===============================
Version 1.1:  Offline job manager - set up new user account and cron job.
Version 1.2:  Change of isolate database structure. New package 'exonerate'
              required.
Version 1.3:  Change of isolate and seqdef database structures.  Ensure 
              jstree.js is upgraded.
Version 1.4:  Change of isolate, seqdef, and job database structures.
Version 1.5:  Change of isolate and seqdef database structures.
Version 1.6:  Change of isolate and seqdef database structures.
Version 1.7:  Change of isolate, seqdef, and job database structures.
Version 1.8:  Change of isolate database structures.
Version 1.9:  Change of isolate database structures.
Version 1.10: Change of isolate and seqdef database structures.
Version 1.11: Change of authentication database structure.  
              New md5.js Javascript file required.  
              New Perl modules: Net::Oauth and Crypt::Eksblowfish::Bcrypt 
              required.
Version 1.12: Change of authentication and seqdef database structures.
Version 1.13: Change of seqdef and isolate database structures.
Version 1.14: Change of seqdef and isolate database structures.
Version 1.15: Change of seqdef and isolate database structures.
Version 1.16: Change of authentication, seqdef and isolate database 
              structures.
Version 1.17: Change of seqdef and isolate database structures.
Version 1.18: Change of seqdef and isolate database structures.
Version 1.19: Change of seqdef and isolate database structures.
Version 1.20: Change of seqdef and isolate database structures.
Version 1.21: Change of seqdef and isolate database structures.
Version 1.22: Change of isolate and rest_db database structures.
Version 1.23: Change of isolate database structure.
Version 1.24: Change of isolate database structure.
Version 1.25: Change of isolate database structure.
Version 1.26: Change of isolate database structure.
Version 1.27: Change of seqdef and isolate database structures.
Version 1.28: Change of REST database structure.
Version 1.29: Change of user and isolate database structures.
Version 1.30: Change of isolate database structure.
Version 1.31: Change of isolate database structure.
Version 1.32: Change of seqdef, isolate and preference database structures.
Version 1.33: Change of isolate database structure.
Version 1.34: Change of seqdef and isolate database structures.
Version 1.35: Change of isolate database structure.
Version 1.36: Optional additional table added to the isolate database structure.
Version 1.37: Change of seqdef and isolate database structures.

Details can be found below.

More details about the upgrade process can be found at
http://bigsdb.readthedocs.io/en/latest/installation.html#upgrading-bigsdb.

Version 1.1
-----------
Version 1.1 introduces an offline job manager.  This is required to control
analyses that take a long time for which it is inappropriate to require the
browser remains connected.  When upgrading to version 1.1, you will need to
do the following:

1) Create a 'bigsdb' UNIX user, e.g.

sudo useradd -s /bin/sh bigsdb

2) As the postgres user, create a 'bigsdb' user and create a bigsdb_jobs 
database using the jobs.sql SQL file, e.g.

createuser bigsdb [no need for special priveleges]
createdb bigsdb_jobs
psql -f jobs.sql bigsdb_jobs

3) Set up the jobs parameters in the /etc/bigsdb/bigsdb.conf file, e.g.

jobs_db=bigsdb_jobs
max_load=8

The jobs script will not process a job if the server's load average (over the
last minute) is higher than the max_load parameter.  This should be set higher
than the number of processor cores or you may find that jobs never run on a
busy server.  Setting it to double the number of cores is probably a good
starting point.  

4) Copy the job_logging.conf file to the /etc/bigsdb directory.

5) Set the script to run frequently (preferably every minute) from CRON. Note
that CRON does not like '.' in executable filenames, so either rename the
script to 'bigsjobs' or create a symlink and call that from CRON, e.g.

copy bigsjobs.pl to /usr/local/bin
sudo ln -s /usr/local/bin/bigsjobs.pl /usr/local/bin/bigsjobs

Add the following to /etc/crontab:

* *    * * *	bigsdb  /usr/local/bin/bigsjobs

(set to run every minute from the 'bigsdb' user account).

6) Create a log file, bigsdb_jobs.log, in /var/log owned by 'bigsdb',
 e.g.

sudo touch /var/log/bigsdb_jobs.log
sudo chown bigsdb /var/log/bigsdb_jobs.log 

Version 1.2
-----------
This version requires changes to the structure of isolate databases to 
accommodate in silico PCR and hybridization reaction filtering. Please run the
isolatedb_v1.2.sql script, found in the sql/upgrade directory, against your
isolate databases.

PCR simulation requires installation of ipcress.  This is part of the exonerate
package (http://www.ebi.ac.uk/~guy/exonerate/). A Debian/Ubuntu package for
exonerate is available as part of the main distribution of the operating
system.
 
Version 1.3
-----------
There has been a change in the allele_sequence definitions in the isolate
database so that the primary key now includes the stop position as well as 
the start. Please run the isolatedb_v1.3.sql script, found in the sql/upgrade
directory, against your isolate databases.

There has also been a change in the seqdef database schema.  There is a new
table 'client_dbase_loci_fields' that enables fields within a client isolate
database to be returned following a sequence query, e.g. to identify a species
from a specific allele sequence.  Please run the seqdefdb_v1.3.sql script, 
found in the sql/upgrade directory, against your seqdef databases.

Locus selection for plugins now uses a hierarchical expandable tree.  Please
ensure you update the jquery.jstree.js file in the javascript directory.

Version 1.4
-----------
There are changes to the isolate, sequence definition and jobs database
structures.  Please run the isolatedb_v1.4.sql, seqdefdb_v1.4.sql and
jobs_v1.4.sql scripts, found in the sql/upgrade directory, against your
databases.

Changes to the database structures are detailed below:

1) The loci table of the isolate database has a new field to support flag
tables in seqdef databases.  
2) The sequence bin table of the isolate database has two new fields, run_id
and assembly_id, to support assembly versioning.
3) In both the isolate and seqdef databases the user_permissions table 
has the set_user_permissions field removed as this is no longer used. 
4) The seqdef database has a new allele_flags table to support flagging of
allele sequences.
5) The seqdef database has a new matviews table and Postgres functions
defined to support materialized views of scheme data.
6) The bigsdb_jobs database has a new field called stage added to the jobs
table.  This is to support status messages during a job run.

Version 1.5
-----------
There are changes to the isolate and sequence definition database structures.
Please run the isolatedb_v1.5.sql and seqdefdb_v1.5.sql, found in the sql/
upgrade directory, against your databases.

Changes to the database structures are detailed below:

11) There are new tables in both the isolate and seqdef databases to support
dataset partitions: sets, set_loci, set_schemes. The isolate database has two 
extra tables to handle database views and metadata: set_view and set_metadata.
2) There is a new field in the isolate database loci table, match_longest, 
that when true specifies that a BLAST search for tagging will only return the
best (longest) match.
3) There are two new fields in the loci table of both isolate and seqdef
databases, formatted_name and formatted_common_name, where the isolate name
can be formatted using HTML attributes for display in the website.

Version 1.6
-----------
There are changes to the isolate and sequence definition database structures.
Please run the isolatedb_v1.6.sql and seqdefdb_v1.6.sql, found in the sql/
upgrade directory, against your databases.

Additionally, jQuery has been updated to version 1.9.1.  This has necessitated
an upgrade to various Javascript plugins.  Please make sure that the 
javascript directory is up to date.  The cornerz jquery plugin is no longer
required since its functionality is now available using CSS.

There are also stylesheet changes so update bigsdb.css and ensure the new 
jquery-ui.css is copied to the same location.

Version 1.7
-----------
There are changes to the isolate, sequence definition and jobs database
structures.  Please run the isolatedb_v1.7.sql, seqdefdb_v1.7.sql and
jobs_v1.7.sql scripts, found in the sql/upgrade directory, against your
databases.

Changes to the database structures are detailed below:
1) New tables in the isolate database for setting contigsequence attributes.
2) New isolate_id column in the isolate database allele_sequences table. This
is set automatically by triggers on adding/updating this table or updating
the sequence_bin table.
3) New field 'seq_query' in the seqdef scheme_groups table to specify whether
the group should be selectable for sequence queries.
4) New field 'index' in the seqdef scheme_fields table to specify if an index
should be set up for a field when materialized views are used.
5) The jobs database has new fields in the jobs table needed for cancelling
running jobs - these store the process id, status, and a fingerprint of the
parameters (used to detect duplicate jobs).
6) The jobs database has new tables for isolates, loci and profiles so that
these can be stored in a normalized fashion rather than as concatenated lists.
This makes determining the job size much easier.

Version 1.8
-----------
There are changes to the isolate database structure.  Please run the 
isolatedb_v.1.8.sql script, found in the sql/upgrade direcotory, against your
isolate databases.

There are also minor stylesheet changes so update bigsdb.css

MAFFT is now the default sequence aligner (MUSCLE is still supported). This
is significantly faster.  To use this, make sure it is installed (v6.840+) and
set the mafft_path attribute in bigsdb.conf to point to the mafft executable.

You can also cache scheme field values within isolate databases.  This can be
done by running the update_scheme_caches.pl script regularly (at least once per
day).  This is used for querying isolates by scheme fields (e.g. ST) and is
required for large databases since the introduction of multiple allele
designations for a locus - resulting in potentially multiple scheme field
values per isolate and significantly more complicated database queries. Small
databases (<10,000 isolates) don't normally require this caching.  A warning
message will appear in bigsdb.log if caching isn't used and an isolate query
that would benefit from the cache takes longer than 5 seconds.  Unless you see
these messages, you probably don't need it.

Version 1.9
-----------
There are changes to the isolate database structure.  Please run the 
isolatedb_v.1.9.sql script, found in the sql/upgrade direcotory, against your
isolate databases.

The main change is a new table called seqbin_stats that contains a count of
contigs and the sum of lengths of contigs for each isolate.  This table is
automatically updated by database triggers.  

There is also an additional field, new_version, that needs to be added to
the isolates table of an isolate database.  This is to support record
versioning.

Version 1.10
------------
There are changes to the isolate and sequence definition database structures.
Please run the isolatedb_v1.10.sql and seqdefdb_v1.10.sql scripts, found in
the sql/upgrade directory, against your databases.

The main change to both databases is a modification to the way that curator
permissions are stored.  The previous user_permissions table is removed and
is replaced with a new curator_permissions table that uses key/value pairs
allowing new permissions to be introduced without changes to the database
structure.

There are also changes to the projects table in the isolates database.

Version 1.11
------------
There are three new Perl modules that should be installed:
 * Net::Oauth
 * Crypt::Eksblowfish::Bcrypt
 * Mail::Sender  
These should be available as system packages on most Linux distributions.

The contents of the Javascript directory should be updated to include the
new md5.js file and updated modernizr.js files.

The css files should now be placed in a directory 'css' in the root of the web
site, although they will still be found if all placed directly in the root
directory.  There have been changes to bigsdb.css so make sure this is updated.

The new fonts directory should be copied to the root directory of the web site.

There are changes to the isolate and sequence definition database structures.
Please run the isolatedb_v1.11.sql and seqdefdb_v1.11.sql scripts, found in
the sql/upgrade directory, against your databases.

The authentication database has also been modified in order to support bcrypt
hashing.  Please run auth_v1.11.sql against your authentication database
(bigsdb_auth by default).  You should then run the upgrade_auth_hashes.pl
script.  Make sure you also update the add_user.pl script as the old version
is not compatible with the bcrypt hashing now used.

There is a new script, upload_contigs.pl, to upload contigs directly to the 
sequence bin via the command line.  This can be found in the 
scripts/maintenance directory.

Version 1.12
------------
There are changes to the sequence definition database structure to support
allele retirement. Additional fields have also been added to the sequences
table in preparation for future functionality. Please run the 
seqdefdb_v1.12.sql script, found in the sql/upgrade directory, against your
seqdef databases.

The authentication database has also been modified to more flexibly support
client software permissions when accessing authenticated resources via the
RESTful API. Please run auth_v1.12.sql against your authentication database
(bigsdb_auth by default).

Version 1.13
------------
There are changes to the sequence definition database structure to support
profile retirement. There is also a new locus_stats table and additional fields
added to the sequences and allele_submission_sequences tables in preparation
for future functionality. Please run the seqdefdb_v1.13.sql script, found in
the sql/upgrade directory, against your seqdef database.

The isolate database has also been modified to support future functionality.
Please run isolatedb_v1.13.sql against your isolate databases.

Version 1.14
------------
There are large-scale changes to both the sequence definition and isolate 
database structures to support cgMLST schemes with primary key indexing. The
previous method of caching scheme profiles did not support schemes with a ST
value and more than ~1600 loci due to PostgreSQL column limits. This did not
apply to schemes that were simply a collection of loci. Even before this limit
was reached, such large schemes would suffer performance penalties. The new 
structure has no such limits.

Classification groups for cgMLST schemes are also introduced with this version.
This has necessitated a number of new tables in the database schemas.

Please run the seqdefdb_v1.14.sql against sequence definition databases and
isolatedb_v1.14.sql against isolate databases. These can be found in the 
sql/upgrade directory.

Any scheme views set up in the sequence definition database named 'scheme_1'
etc. can be dropped as these are no longer used.  To do this log in to the
database using psql, and type 'DROP VIEW scheme_1;'. Do this for each of the
scheme views.

If you are planning to use cgMLST schemes, you should ensure that your database
configuration has a temp_buffers setting of at least 64MB. This can be done by 
editing bigsdb.conf and setting:

temp_buffers=64

Alternatively, this can be set globally in the postgresql.conf file (probably 
/etc/postgresql/9.x/main/postgresql.conf) with the following line:

SET temp_buffers=64MB

Without this, the database engine is likely to run out of memory during cache
renewal.

Version 1.15
------------
There have been changes to both the sequence definition and isolate
database structures mainly to support scheme descriptions.

Please run the seqdefdb_v1.15.sql script against sequence definition databases
and isolatedb_v1.15.sql against isolate databases. These can be found in the 
sql/upgrade directory.

Additionally, you need to update the bigsdb.css stylesheet and contents of
the javascript directory.

Version 1.16
------------
There are changes to the sequence definition, isolate and authentication
databases to support site-wide user accounts.

Please run the seqdefdb_v1.16.sql script against sequence definition databases,
isolatedb_v1.16.sql against isolate databases and auth_v1.16.sql against the
authentication database (bigsdb_auth).

Additional logging directives have been added to logging.conf (/etc/bigsdb).

Additionally, you need to update the bigsdb.css stylesheet and the contents
of the fonts directory.

The following Perl modules are now also dependencies and need to be installed:

Email::Valid
Email::Sender

Version 1.17
------------
There are changes to the sequence definition and isolate databases to support
private projects and private data.

Please run the seqdefdb_v1.17.sql script against sequence definition databases
and isolatedb_v1.17.sql against isolate databases.

Additionally, you need to update the bigsdb.css stylesheet and the contents
of the javascript directory.

Version 1.18
------------
There are changes to the sequence definition and isolate databases to support
accessing remote contigs.

Please run the seqdefdb_v1.18.sql script against sequence definition databases
and isolatedb_v1.18.sql against isolate databases.

Additionally, you need to update the contents of the javascript directory.
jQuery; jQuery UI; and the jsTree and columnizer plugins have been updated to 
the latest versions. Ensure that the javascript/themes directory is also 
updated.

Version 1.19
------------
There are changes to the sequence definition and isolate databases to support
accessing remote contigs.

Please run the seqdefdb_v1.19.sql script against sequence definition databases
and isolatedb_v1.19.sql against isolate databases.

Additionally, if updating from a version <1.18.3 you need to rename the fonts 
directory to webfonts. You need to update the contents of this to support 
FontAwesome 5.2. You also need to update the css directory.

Version 1.20
------------
There are changes to the sequence definition and isolate databases. These 
support accessing client isolate databases when doing a classification scheme
search and conditional formatting of EAV fields.

Please run the seqdefdb_v1.20.sql script against sequence definition databases
and isolatedb_v1.20.sql against isolate databases.

Version 1.21
------------
There are changes to the sequence definition and isolate databases. These 
support associating additional fields to classification groups.

Please run the seqdefdb_v1.21.sql script against sequence definition databases
and isolatedb_v1.21.sql against isolate databases.

Version 1.22
------------
There are changes to the isolate database. These are to support restricting 
loci and schemes to particular isolate table views.

Please run isolatedb_v1.22.sql against isolate databases. 

There has also been a change to the rest_db database structure in order to 
support logging. Please run rest_v1.22.sql against the rest_db database.

Version 1.23
------------
There are changes to the isolate database. These are to support sparse field
grouping and field validation rules.

Please run isolatedb_v1.23.sql against isolate databases.

Version 1.24
------------
There are changes to the isolate database. These are to support loci with
introns - needed if working with eukaryote genes. BLAT needs to be installed
to enable the use of introns and its path set in bigsdb.conf.

Please run isolatedb_v1.24.sql against isolate databases.

Version 1.25
------------
There are changes to the isolate database. These are needed to allow permission
to be given for members of a user group to be able to curate shared private
data submitted by another member of the user group.

Please run isolatedb_v1.25.sql against isolate databases.

Version 1.26
------------
There are changes to the isolate database. These are needed to facilitate
bookmarking of isolate queries and for logging of record deletion.

Please run isolatedb_v1.26.sql against isolate databases.

Version 1.27
------------
There are changes to the sequence definition and isolate databases. These 
support categorising loci into different types.

Please run the seqdefdb_v1.27.sql script against sequence definition databases
and isolatedb_v1.27.sql against isolate databases.

Version 1.28
------------
There is a change to the REST database structure.

Please run the rest_v1.28 sql script against the REST database (bigsdb_rest).

Version 1.29
------------
There are changes to the site users database to support optional submission
notification digests and to mark holiday absence. Additionally, there are new
indexes defined for the isolate database to improve the efficiency of deleting
users.

Please run the isolatedb_v1.29.sql script against isolate databases and the
users_v1.29.sql script against the site-wide users database (if used).

Version 1.30
------------
There are changes to the isolate database structure. These are to support 
recommended schemes and annotation quality metrics.

Please run the isolatedb_v1.30.sql script against isolate databases.

Version 1.31
------------
There are changes to the isolate database structure. These are to support 
storing arbitrary analyses, assembly metrics, and quality checks.

Please run the isolatedb_v1.31.sql script against isolate databases.

Version 1.32
------------
There are changes to the isolate, sequence definition, and preference database
structures. These are to support front-end dashboards and the use of 
alternative start codons for loci.

Please run the isolatedb_v1.32.sql script against isolate databases, the
seqdefdb_v1.32.sql script against sequence definition databases, and the
prefs_v1.32.sql script against the prefs database (bigsdb_prefs by default).

Note that there is a new Perl module dependency: TOML.

Version 1.33
------------
There is a small change to the isolate database, introducing an embedded 
function needed to sort the contents of array fields. This is used by the
Data Explorer tool linked to the front-end dashboard.

Please run the isolatedb_v1.33.sql script against isolate databases.

Version 1.34
------------
There are changes to the isolate and sequence definition database structures.
These are to support the integration of cgMLST-based LINcodes.

Please run the isolatedb_v1.34.sql script against isolate databases and the
seqdefdb_v1.34.sql script against sequence definition databases.

Note that there is a new Perl module dependency: PDL.

Version 1.35
------------
There are changes to the isolate database in order to support alternative codon
tables.

Please run the isolatedb_v1.35.sql script against isolate databases.

Version 1.36
------------
There are optional changes to the isolate database needed to support GPS lookup
tables for specified isolate fields. These are optional because the table 
includes a field using a geography point data type that requires the PostgreSQL
PostGIS module to be installed. If you have no need to map fields, then this
does not need to be installed.

To add this table please first install PostGIS and then run the 
isolatedb_geocoding.sql script against any isolate databases requiring it.

Version 1.37
------------
There are changes to the sequence definition database structure to support 
profile fields with constrained allowed values. There is also a small change
to the isolate database structure, adding a foreign key constraint to the
sequence_flags table.

Please run the isolatedb_v1.37.sql script against isolate databases and the
seqdefdb_v1.37.sql script against sequence definition databases.

