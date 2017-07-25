v1.17.1: *Fast mode using exemplars for web-based scanning. 
         *Kiosk mode for sequence query page.
v1.17.0: *Support for user uploads of private records.
         *Private user projects.
         *Support for paging in request headers in RESTful API.
         *Added Perl and Python scripts for demonstrating the RESTful API.
         *SQL optimisation for profile combination queries.
v1.16.6: *Include classification groups in profile downloads and make
          accessible in RESTful API.
v1.16.5: *Option to prevent using Google CDN for loading JQuery. This 
          can be blocked by Chinese firewall preventing Chinese users
          from changing their password (which is needed for site-wide
          registering).
v1.16.4: *Seqbin breakdown option to only calculate contig stats (faster
          for large databases).
         *Fix for Artemis link in seqbin breakdown page.
         *Searching of isolate database via RESTful API.
         *Improved fluid layout for index page.
         *Please note new Perl module dependency: Email::MIME
          and new Javascript dependency: packery.js (found in Javascript
          directory).
         *Various bug fixes.
v1.16.3: *BLAST plugin limits.
         *Minor bug fixes.
v1.16.2: *Fix password setting issue in non-site databases.
v1.16.1: *Faster, multi-threaded Genome Comparator.
v1.16.0: *Support for site-wide accounts.
v1.15.4: *PhyloTree plugin - integrates with Interactive Tree of Life 
          (iTOL). Please note that this requires clustalw and setting its
          path in bigsdb.conf.
v1.15.3: *PhyloViz plugin.
         *Optional log in on public databases.
         *Query sequences via RESTful API.
         *Add <= and >= search modifiers.
v1.15.2: *Fix missing field in seqdef schemes table.
v1.15.1: *Fix for exemplar scanning bug introduced with v1.15.0.
v1.15.0: *Scheme descriptions including links, PubMed references and flags.
         *Options to prevent submission of alleles and profiles of specific
          loci and schemes via automated submission interface.
         *Option to disable scheme by default in seqdef database.
         *Streamline setting up of new loci in isolate databases - only 
          BIGSdb seqdef databases are now supported so some previously 
          required attributes have been removed.
         *Locus-specific threshold for allele identity match check.
v1.14.4: *Dropdown menu.
         *Field help information moved to separate page.
         *Site- and installation-wide header and footer files.
         *Loading of isolate query form elements by AJAX calls to speed up
          initial display on databases with very large numbers of loci.
         *Support for adding messages to allele and profile submission
          pages.
v1.14.3: *Support for retired isolate ids.
         *Option to allow submission of non-standard length alleles.
         *Optional quotas for daily and total pending submissions.
v1.14.2: *Ensure compatibility with CGI.pm >= 4.04.
         *Set global database configuration parameters.
v1.14.1: *Type alleles to constrain sequence search space when defining new
          alleles.
v1.14.0: *cgMLST clustering and classification groups.
v1.13.2: *Speed optimisations for sequence lookup and multi-core tagging.
v1.13.1: *Bug fixes for fast mode scanning, retired profiles and scheme 
          setup.
v1.13.0: *New locus_stats table for faster allele download page.
         *Support for retired scheme profiles.
v1.12.4: *Max upload size is now a configurable option. 
         *Include scheme fields in BLAST plugin output.
         *Fix for auto allele definer script (bug introduced with 1.12.3).
v1.12.3: *Introduction of exemplar alleles.
         *Fast mode scanning - tag genomes in a few minutes.
         *Optional per-user job quotas.
         *Automated curation of 'easy' submitted alleles.
v1.12.2: *REST interface filtering by added_after and updated_after dates.
         *Genome submissions via REST interface.
         *Script to periodically remind curators of pending submissions.
         *Performance improvements to scheme materialized views.
v1.12.1: *Genome submissions via web interface - contig files are linked 
          to each record facilitating rapid curator upload.
         *BLAST plugin now uses offline jobs for large analyses.
         *Sequence query BLAST database caches now regenerated after new 
          alleles defined - previously these were just marked stale and 
          regenerated the next time they were needed.
         *Check that new alleles aren't sub-/super- sequences of existing 
          alleles.
v1.12.0: *Support for submissions via REST interface.
         *Support for allele retirement.
         *Query isolates by allele designation/tag count.
v1.11.5: *Bug fix for batch isolate upload not including alleles (bug
          introduced in v1.11.4).
v1.11.4: *Update to REST interface for compatibility with recent Dancer2
          versions.
v1.11.3: *Search alleles by entering a list of ids.
         *The browse, list query and standard query forms are now merged.
          This allows more advanced queries where you can enter a list and
          filter this by other attributes.  Query forms can be modified to
          display only elements required.
         *REST interface parameter to disable paging and return all 
          results.
v1.11.2: *Option to ignore previously defined profiles when batch 
          uploading.
         *Option to automatically refresh scheme caches in isolate 
          databases when batch uploading.
         *Relax auto allele definer CDS checks for use with pseudogenes.
         *More efficient handling of previously tagged peptide loci in
          Genome Comparator analyses. 
         *Fix to isolate database SQL setup file.
v1.11.1: *Submission system tweaks.
         *Use offline job manager for large plugin jobs
           -Locus Explorer (translation).
           -Export dataset.
           -Two Field breakdown.
         *Performance improvements
           -Scheme breakdown.
           -Configuration check.
v1.11.0: *RESTful interface for retrieving data.
         *Web-based data submission system.
         *Command line contig uploader script. 
         *Improved password security using bcrypt hashing.
         *Improved autotag and autodefiner distribution of jobs between
          threads.
         *New icons (using Font Awesome scalable icons).
         *Support for multi-threading in MAFFT alignments.
         *Selectable schemes in seqbin breakdown to calculate % designated.
v1.10.1: *Fix for submitter upload when including allele designations.
         *More efficient Genome Comparator paralogous locus check.
v1.10.0: *New submitter class of user allowed to upload and curate their
          own records.
         *Removal of access control lists (ACL) which were not widely
          used and complicated to administer. Their purpose has been
          largely removed by the introduction of submitter accounts.
         *Project options to select whether to include individual projects
          in isolate info pages and in a new project description page.
         *Option to set base isolate id number.
         *Support for diploid MLST schemes in seqdef database.
         *New allele status of 'ignore' (while previously they were either
          'confirmed' or 'provisional') to enable an allele to be defined
          but not shown in public interface or used in analyses.  
         *Optionally include seqbin id and position in Sequence Export
          output.
         *Genome Comparator improvements:
           -Improved paralogous loci checks.
           -Core genome alignments.
           -Report of selected parameters in output.
         *Interface improvements:
           -Autosuggest values for isolate provenance fields with option
            lists.
           -Warning if batch seqbin upload is attempted when data already
            uploaded.
           -Option to display isolate publications in main results table.
         *Autotagger improvements:
           -Options to define a 'new' isolate, allowing a defined number 
            of loci to be tagged before an isolate is no longer considered
            'new'.
 v1.9.1: *Context-sensitive help and minor bug fixes.
         *Support for diploid locus in sequence definition databases.
 v1.9.0: *New table for seqbin_stats that makes searching by seqbin size
          much quicker.
         *Support for record versioning.
 v1.8.2: *Fixed permission in isolate database SQL template.
 v1.8.1: *Fixed memory leak in Genome Comparator.
         *Faster autotagger by setting word size to length of smallest
          allele.
 v1.8.0: *Allow multiple designations per locus.
         *Removal of pending designations.
         *Multithreaded autotagger and auto allele definers.
         *Optional caching of scheme field values within isolate database.
         *Use of MAFFT as default sequence aligner.
         *Batch contig downloads from contig export plugin.
 v1.7.4: *Fix for dropdown filter display in Perl 5.18.
 v1.7.3: *Minor update that mainly silences warning messages in the log
          when run under Perl 5.18.  This is the version of Perl installed
          with Ubuntu 14.04.
 v1.7.2: *Genome Comparator improvements to handling of truncated loci.
         *Auto generation of Excel submission templates.
         *Excel output in various plugins.
         *Please note new Perl module dependency: Excel::Writer::XLSX.
 v1.7.1: *Improved UNICODE support.
         *Performance enhancement when tagging following a scan.
 v1.7.0: *Offline scanner to define new alleles.
         *Logged-in users now get a list of running/finished jobs. 
         *Added ability for users to stop offline jobs.
         *Offline job quotas and priority set per database configuration.
         *Autotagger option to mark missing alleles as '0'.
         *Allow setting of min/max values for integer provenance fields.
         *Allow isolate queries based on allele designation status.
         *New allele sequence status values to support WGS.
 v1.6.5: *Fix showstopper in seqdef curator's page with empty database.
 v1.6.4: *Removal of legacy BLAST support.
         *Various performance improvements.
 v1.6.3: *Fix for BLAST+ parameters that conflict in newer versions
          of BLAST+.
 v1.6.2: *Web pages now use HTML5 rather than XHTML.
         *Client validation of curation forms.
         *Allows filtering by multiple projects/publications in queries.
         *Allows filtering by sequence bin size.
         *Batch upload of new alleles in FASTA format.
 v1.6.1: *Forked scanning allows scan jobs to be started in the
          background and bookmarked.
         *Interface improvements for mobile use.
 v1.6.0: *Allows database schemes to contain profiles with ambiguous
          alleles. Allele 'N' is effectively ignored in comparisons.
         *New contig export plugin.
         *Javascript improvements.
 v1.5.1: *GenomeComparator improvements: Core genome analysis and ability
          to upload comparator sequences in FASTA format.
 v1.5.0: *Database partitioning - Present datasets with constrained choice
          of loci, schemes and isolate records.  Datasets can also be
          associated with additional specific metafields.
 v1.4.1: *Fix misplaced semi-colon in isolate database SQL file.
 v1.4.0: *Change of seqdef database structure - Allele flags can now be
          set for sequence definitions.  These are automatically
          transferred across to the isolate database when scanning.
         *Change of isolate database structure - Added column to loci
          table to support seqdef allele flags.
         *Change of jobs database structure - Added column to jobs
          table called 'stage' to display status information during
          a job.
         *New RuleQuery plugin - Scan genomes against loci in a
          specified order and extract information in a formatted report.
          Rules can be written in Perl and placed in the dbase config
          directory.
         *Support for materialized views of schemes in seqdef databases.
          This optimises lookups from large schemes.
         *New 'starts with' and 'ends with' operators in queries.
 v1.3.8: *GenomeComparator improvements.
 v1.3.7: *Improved scheme selection in tag scanning/Genome Comparator.
         *Improved sequence query now works for whole genome data contigs
           - quickly extract MLST (profile, ST and clonal complex) etc. 
             directly from a newly assembled genome.
         *Launch Artemis from sequence bin page for graphical display of
          tagged information.
         *Produce distance matrix and generate splitsgraph for comparison
          of multiple genomes in GenomeComparator plugin.
         *Redesign of options page.
 v1.3.6: *New TagStatus plugin.
 v1.3.5: *Minor bug fixes.
         *Extra options for offline autotagger script.
 v1.3.4: *Option to hide schemes from the main results table if no
          records currently displayed contain data from scheme.
         *BLAST database caching when querying sequences with 'all loci'.
         *Option to cache scheme table within isolate database.
         *New offline script object code - job manager script converted.
         *New offline autotagger script. 
 v1.3.3: *Querying of isolates by tag status.
         *Collapsible fieldsets for query form allows the number of 
          search options to be increased (new Coolfieldset JQuery plugin
          used).
 v1.3.2: *Support TBLASTX in GenomeComparator plugin.
         *Nucleotide frequency table in LocusExplorer plugin.
         *Updated TableSorter JQuery plugin.
         *New Polymorphisms plugin.
 v1.3.1: *Added support for BLAST+ binaries.
 v1.3.0: *Change of isolate database structure - allele_sequences primary
          key changed to include stop position.
         *Change of sequence database structure - table
          'client_dbase_loci_fields' that enables fields within a client
          isolate database to be returned following a sequence query, 
          e.g. to identify a species from a specific allele sequence. 
         *Hierarchical tree for locus selection in plugins.
         *New CodonUsage plugin. 
 v1.2.0: *Small change of isolate database structure. Filter genomes to
          products of in silico PCR reactions or within a specified
          distance of a hybridization probe.
 v1.1.0: *Introduction of offline job manager for plugin jobs that take
          a long time to run.  XMFA and GenomeComparator plugins
          converted to use this. 
 v1.0.1: *Minor bug fixes.
 v1.0.0: *Initial release.
