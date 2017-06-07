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
   used as the start point for the download_alleles script.
   
   Once schemes have been identified, allelic profiles can be retrieved with 
   a single call to the API, e.g.:
   
   ```
   curl http://rest.pubmlst.org/db/pubmlst_neisseria_seqdef/schemes/1/profiles_csv
   ```
   
   Note that schemes can be either simple collections of loci, in which case 
   they do not have defined profiles, or schemes associated with a primary key 
   field such as MLST where the ST field defines the combination of alleles. 
   
 * download_alleles.pl, download_alleles.py
 
   Downloads FASTA files of alleles defined for a set of loci. If the
   --scheme_id option is set it will download only loci from the selected
   scheme. All loci defined in the database will be downloaded if this option
   is not selected. Use the --dir option to set the download directory, 
   otherwise the current directory will be used. For example, to download MLST
   alleles for Neisseria MLST (scheme 1) to the /var/tmp/downloads directory
   do the following:
   
   ```
   ./download_alleles.py --database pubmlst_neisseria_seqdef --scheme_id 1 --dir /var/tmp/downloads
   ```
   
 * rest_auth.pl, rest_auth.py
 
   Test client demonstrating the OAuth authentication process. To use this you
   will need to register for a [PubMLST account](https://pubmlst.org/site_accounts.shtml)
   and [link this to the pubmlst_test_seqdef and pubmlst_test_isolates databases](https://pubmlst.org/site_accounts.shtml#registering_with_databases). 
   
   A test sequence definition database (pubmlst_test_seqdef) is hard-coded
   in to the script. Calling the script without any route is the same as sending
   a GET request to http://rest.pubmlst.org/db/pubmlst_test_seqdef.
   
   A detailed list of all available API methods can be found at 
   http://bigsdb.readthedocs.io/en/latest/rest.html.
    
   The first call you make with the script will request an access token which 
   will involve you logging in to the site using the provided URL, authorising 
   delegation of your credentials and entering a provided verifier code in to 
   the script. This access token will be stored in the current directory and 
   lasts indefinitely (if you delete it, the script will request another). The
   script will use the access token to request a session token (valid for 12 
   hours). While the session token is valid, it will be used to sign all 
   requests to the API. If it is deleted or expires, the script will request 
   a new session token using the stored access token.
   
   ```
   ./rest_auth.py
   ```
   
   This will return a JSON response describing available resources.
   
   **Submitting a new allele to the curation queue**
   
   Suppose we have a new sequence for the glp locus. First create
   a FASTA file (sequence.fas) containing the sequence. We also have two 
   Sanger trace files to upload for assessment (forward.ab1 and reverse.ab1). 
   We need to state the technology and software used to determine the 
   sequence. First create the session:
   
   ```
   ./rest_auth.py --method POST --route 'submissions' --arguments 'type=alleles&locus=glp&assembly=de novo&technology=Staden&software=Staden' --sequence_file sequences.fas
   ```
   
   Provided the submission is successful, a JSON response will include a URL 
   to the submission record:
   
   ```
   {'submission': 'http://rest.pubmlst.org/db/pubmlst_test_seqdef/submissions/BIGSdb_20170605142839_76379_14007'}
   ```
   You can query this submission:
   
   ```
   ./rest_auth.py --method GET --route 'submissions/BIGSdb_20170605142839_76379_14007'
   ```
   Upload the supporting trace files:
   
   ```
   ./rest_auth.py --method PUT --route 'submissions/BIGSdb_20170605142839_76379_14007/files' --arguments 'filename=forward.ab1' --file forward.ab1
   ./rest_auth.py --method PUT --route 'submissions/BIGSdb_20170605142839_76379_14007/files' --arguments 'filename=reverse.ab1' --file reverse.ab1
   ```
   
   Submissions to the test database will be periodically deleted. You do not 
   need to do anything.