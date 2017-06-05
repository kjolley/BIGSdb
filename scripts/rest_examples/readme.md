Sample scripts and worked examples
==================================
Sample scripts can be found in the python and perl sub-directories. Each script
is written in both languages, utilizing the same command line parameters to
demonstrate interaction with the API from both languages.

Available scripts
-----------------
 * get_schemes.pl, get_schemes.py
 
   Demonstrates traversal of the API from the root level, returning links to
   all scheme definitions (available in sequence/profile definition databases).
   Schemes can be filtered using --match and --exclude arguments, e.g. to 
   search for schemes containing the term 'MLST' but not including 'cgMLST' 
   use:

   ```
   ./get_schemes.py --match MLST --exclude cgMLST
   ```
   
   The script outputs three tab-delimited columns containing the database
   description, scheme name, and link to the scheme definition which can be
   used as the start point for the download_scheme script.
   
