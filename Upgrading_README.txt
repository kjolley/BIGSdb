Important notes about upgrading
-------------------------------

Version 1.1: Offline job manager - set up new user account and cron job.
Version 1.2: Change of isolate database structure. New package 'exonerate'
             required.
Version 1.3: Change of isolate and seqdef database structures.  Ensure 
             jstree.js is upgraded.
Version 1.4: Change of isolate, seqdef, and job database structures.

Details can be found below.


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
