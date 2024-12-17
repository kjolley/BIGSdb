v1.50.1: *Added support for Neighbour-joining trees in GrapeTree.
         *Added a means to restrict use of particular plugins to users/groups.
v1.50.0: *Field values from arbitrary analyses, e.g. Kleborate and rMLST
          species id, stored as JSON can now be registered and included in
          isolate queries, export, and analysis.
v1.49.1: *Fix for lincodes.pl for use with latest version of PDL module.
         *Improved layout of site user registration and admin pages.
         *Users can now upload their own genomes using .tar.gz or .tar files
          (not just .zip files) in Genome Comparator and related plugins.
         *New option to export LIN code prefixes of different lengths in Export
          plugin.
v1.49.0: *Automated generation of personal API keys.
         *Use LINcodes to identify closest profiles and genomes on profile 
          info page.
         *Include sequencing method on isolate info page.
         *Fix to verification of POST signatures in the API.
v1.48.5: *Improved formatting for user registration page.
         *Option to select only DNA or only peptide loci in sequence query.
v1.48.4: *The scheme cache is now used for isolate query results if the scheme
          has >100 loci and 'cache_schemes' is set.
         *If there are multiple cgSTs for an isolate, these are now collapsed
          with just the cgST with the fewest missing loci shown in the results
          table (other matching cgSTs can be shown by clicking a link).
v1.48.3: *Determine nearest matching genome using LIN codes in sequence query.
         *Performance improvements to sequence query.
v1.48.2: *Hotfix for API downloads crashing if selected scheme did not have
          primary key.
v1.48.1: *Fix for LIN code prefix field lookup on web/REST profile pages.
         *Fix for LIN code assignment when scheme has field called profile_id.
         *Performance improvement for API cgMLST profile download.
v1.48.0: *Add support for placeholder text on isolate query forms. Placeholders
          can be defined for provenance fields in config.xml or for scheme/LIN
          code fields by adding a placeholder value in the appropriate table.
         *Setting of GrapeTree path in bigsdb.conf is now consistent with other
          Python scripts called by plugins (the old method of defining 
          python3_path and grapetree_path separately still works).
v1.47.3: *Potential fix for https://github.com/kjolley/BIGSdb/issues/970.
v1.47.2: *Functionality added to support plugins written in Python using the
          BIGSdb Python Toolkit (https://github.com/kjolley/BIGSdb_Python_Toolkit)
v1.47.1: *Added option to hyperlink to a different URL depending on regex of
          field value.
         *More efficient batch sequence queries when exemplars used.        
v1.47.0: *Added optional private data quotas to projects.
         *Added embargoing for isolate submissions.
v1.46.2: *BingMaps has been removed as an option for mapping as Microsoft are
          retiring this service next year. It has been replaced with options
          for MapTiler and ArcGIS maps.
v1.46.1: *New SNPsites plugin - this provides a wrapper to the snp-sites tool
          and can be applied across multiple loci to identify polymorphic sites
          and allele counts within a dataset.
v1.46.0: *Option to filter alleles, profiles, and isolates for non-logged in
          users to records added before a specified date.
         *Improved AJAX loading of isolate query interface.
v1.45.0: *Added option to highlight private data in isolate exports.
         *Added option for an admin to create customized isolate query forms
          with pre-selected fields shown.
         *Added separate options to require a user to be logged in to download
          alleles and profiles using the web interface.
v1.44.1: *Added option to show if assembly checks have passed in isolate 
          results table.
         *Added option to scannew.pl to only scan records that have passed
          assembly checks.
         *Added option to scannew.pl to not check private records.         
v1.44.0: *Database indexes have been revised following a performance review.
         *'Ignore' option has been removed for allele designations.
         *Matching isolates at different LINcode thresholds are now shown 
          within an isolate record is LINcode has been assigned.
v1.43.3: *Added optional message to users to use API on the allele and profile
          download page.
         *Searchable dropdown boxes are now used for lists with large number 
          of values.
         *Dropdown lists of checkboxes now used for fields requiring 
          multiselect.
         *Javascript performance tweaks for background loading of isolate query
          form elements.
         *Optionally set a limit to the number of offline jobs that any single
          user can run for individual plugins.
v1.43.2: *Added additional logging information.
         *cgST with fewest missing loci is now highlighted when isolate has 
          multiple cgSTs.
         *Dashboard now shown for bookmarked and publication queries.
         *Added option for users to have to log-in to run offline jobs.
         *Added option to tag incomplete loci at specified identity thresholds.
         *Automatically set 'ambiguous read' flag on tags if sequence contains
          non-A,G,T,C characters.
         *JQuery.UI.multiselect now used for flag dropdown box on tag scan page. 
          Only rows in current viewport are rendered as needed for performance.        
v1.43.1: *Hotfix for isolate query modification trigger.
v1.43.0: *Added optional web logging to record user accesses.
         *Improved API logging to include client and usernames.
v1.42.7: *Add new Reports plugin - this is used to generate customized genome
          reports. See https://github.com/kjolley/Klebsiella_reports for
          examples.
         *Added option to silently reject alleles that fail similarity check
          when batch uploading.
         *Added option to make some fields expected for genome assemblies.
         *Make the 'expand width' view persistent and allow its use for the
          front-end dashboard.
         *Add option to return partial sequence matches for scheme queries
          using the API.
v1.42.6: *Add list query to all table queries.
         *N50 gridlines added to seqbin cumulative length display.
         *Query and initialization optimizations to improve performance.
         *Include selected fields in ReporTree partitions summary.
v1.42.5: *New ReporTree plugin.
v1.42.4: *Improve web-based sequence-scanning:
          - Show position of first stop codon for complete CDS loci
          - Optionally extract sequence to first stop codon if within a 
            specified percentage of the length of the closest allele.
v1.42.3: *Fix LINcode field export.
v1.42.2: *Search isolates by SAVs or SNPs defined in typing database.
         *Use caching for dashboard AJAX calls where possible.
         *Add option to batch download full allele records via API.
         *Fix for export of LINcode field values.
v1.42.1: *Upgrade to FontAwesome 6.
         *Added provenance completeness metrics - include fields in metric by
          setting annotation_metric="yes" for a specific field in config.xml.
         *Search isolates by allele extended attributes defined in typing
          database.
v1.42.0: *Option to define schemes that can include locus presence in profile
          definitions.
         *Mutation and SNP detection tools added to annotate allele 
          definitions. Mutation presence can be queried in locus-specific
          allele query interface.
         *Add secure and httponly attributes to cookies.
v1.41.3: *Add Kleborate plugin.
v1.41.2: *Add choice of colour palettes to front-end and query dashboards.
v1.41.1: *Option to define dashboard colours for specific field values.
v1.41.0: *Bug fix for scheme field ordering in cache tables.
v1.40.1: *Check, and add if necessary, field indexes on scheme cache tables.
         *Add new index that speeds up scheme cache renewal.
         *Fix flanking sequence export.
         *Add --curator option to autotag.pl and scannew.pl scripts.
v1.40.0: *Cache renewal now uses an embedded database stored procedure for
          scheme field lookup, improving memory use.
v1.39.1: *Improvements to scheme caching in isolate databases. This is now more
          scalable for large databases. Manually refreshing the scheme is now
          done in a forked process with updates displayed using AJAX calls.
v1.39.0: *Export dashboard function which can be used to create TOML files for
          setting up default primary, query, or project dashboards.
         *Assembly submissions now allow users to submit genome assemblies via
          the submission interface for adding to existing records.
v1.38.1: *New project front-end dashboards.
         *Query dashboard now shown for publication results. 
         *New annotation status visualisation for dashboards.
v1.38.0: *Support for limiting submissions and curators to a specific database
          configuration.
         *Added ability to hide fields in a specific configuration with a 
          default value automatically set if provided.
         *Added tab-delimited text and Excel outputs to rMLST species tool.
v1.37.0: *Support for scheme fields with constrained allowed values.
v1.36.7: *Option to show whether isolate is private in data exports.
v1.36.6: *Improvement to define_profiles.pl script so that it assigns profiles
          even when there is an existing profile that matches but has more
          missing loci than the isolate.
v1.36.5: *Support for GPS maps in dashboards.
         *Introduction of query dashboards to visually summarise the results
          of an isolate query.
v1.36.4: *New options to reject alleles in allele_curator.pl script.
v1.36.3: *Fix for LINcode and field duplication in exports.
         *Prevent private submitters from deleting their own public records.
         *Improved results header button display.
v1.36.2: *Fix for LINcode prefix field matching in Profile Export plugin.
v1.36.1: *Minor update to lincodes.pl script affecting order when adding new
          batch of profiles.
v1.36.0: *Option to link isolate field values to a lookup table containing GPS
          coordinates to facilitate mapping by e.g. town/city.
         *Display maps for these fields in isolate info page and in Field
          Breakdown plugin.
         *Script to automatically lookup GPS coordinates for towns and cities
          from linked fields, using the Geonames database.
         *Optionally export GPS coordinates from above in the Microreact 
          plugin.
v1.35.3: *Improve GPS mapping in FieldBreakdown plugin - users can dynamically
          change pointer colour and size, and the map is automatically centred
          and zoomed on displayed points.
v1.35.2: *New isolate field type - geography_point that stores GPS coordinates.
          Mapping using OpenStreetMap or Bing is now available for such fields
          within isolate records and within the FieldBreakdown plugin.
v1.35.1: *Minor bug fixes.
v1.35.0: *Adds support for alternative codon tables.
v1.34.2: *LINcode bug fixes.
         *Option to allow batch upload of profiles that are identical except
          for missing data.
v1.34.1: *Include EAV fields and classification schemes in ITOL output.
         *LINcode bug fixes.
v1.34.0: *Support for LINcodes based on cgMLST schemes.
v1.33.0: *Data explorer page linked to dashboard. This offers an interactive
          decomposition tree based on selected fields with links directly to
          return query dataset.
v1.32.2: *Minor bug fix.
v1.32.1: *Update of Microreact plugin to support new API.
v1.32.0: *New front-end dashboards.
         *Please note that there is a new Perl module dependency: TOML.
v1.31.3: *Minor formatting changes.
v1.31.2: *Option to clear BLAST caches from admin interface.
v1.31.1: *Added assembly checks - results of these can be queried and used for
          filtering of isolate datasets.
         *Added announcement banner to database front page. The contents of
          /etc/bigsdb/announcement.html will be shown on all database front 
          pages - this is useful for service announcements, e.g. scheduled
          maintenance.
         *Upgraded D3 to v6, and changed charting library from c3.js to 
          billboard.js.
         *Added means of grouping standard isolate fields into categories.
          Separate groups are listed in dropdown boxes in queries and 
          plugins, and on the isolate display page.
v1.31.0: *Batch uploading data is now performed in a separate process, with
          progress notifications loaded by AJAX polling. This prevents browser
          timeout when lots of genomes are uploaded together.
         *N50 and L50 values are now stored in the seqbin_stats table and can
          be used in isolate queries. The stats are automatically updated by
          a database trigger whenever contigs are added to the sequence bin.
         *The results of arbitrary analyses can now be stored in the isolate
          database as JSON values. These can be displayed within an isolate
          record using a templating system. Results of rMLST analysis generated
          by the rMLST species plugin are now stored and shown in isolate 
          record.
         *External script to run and store rMLST analysis for an isolate
          database.
         *External script to perform rMLST analysis on submitted genomes before
          they are curated to check species and look for contamination. The 
          results are displayed within the submission.
         *Submitted genome assemblies are now checked immediately on upload.
          Thresholds can be set for N50, total length, and number of contigs.
          Soft limit breaches produce warnings to the submitter and curator. 
          Hard limit breaches result in automatic rejection of submission.
         *External script to record %GC, Ns and gaps. These values can now be
          used in isolate queries.
v1.30.1: *Option to limit number of running jobs for particular plugins.
v1.30.0: *Annotation quality metrics. Use the number of allele designations
          defined for a scheme as an indication of annotation quality.
v1.29.5: *Minor bug fixes.
v1.29.4: *Support for upload of compressed sequences - please note the new
          Perl module dependency: File::Type.
v1.29.3: *Include sequence bin size and contig number in isolate queries.
         *Improved database connection handling.
         *Option to deny publication of private data.
v1.29.2: *Multi-threaded SpeciesID plugin - this is now much faster.
v1.29.1: *Isolate fields can be either required, optional and now 'expected'.
          Expected fields require a submitter to explicitly state if there is
          no value available by entering 'null'. For use when you want 
          a submitter to always include a value for a field but it is not
          always possible.
         *Fix for tooltip positioning in GenePresence heatmap.
v1.29.0: *New options for curators to modify how submission notifications are
          received - digest mode and ability to mark holiday absence.
v1.28.1: *Update ITOL plugin to support API key needed due to the change in
          subscription model at https://itol.embl.de/.
         *Extract new allele sequence if found during query with option to
          start a new submission for assignment.
v1.28.0: *New interface.
v1.27.1: *Improved kiosk mode support.
         *Fixed memory leak in BLAST plugin.
v1.27.0: *Support for different locus categories - these show on different 
          tracks on IGV genome viewer.
         *Improved formatting of large field values.
         *Improved handling of sparse field categories.
v1.26.2: *New database status page, moving summaries from index page. Includes
          D3 charts of submissions for isolates, alleles and profiles.
         *Preview plugin output SVG files in job viewer page.
         *Improvements to field description plugin.
v1.26.1: *Dynamically load and remove field filters directly from query page.
         *Automatically exclude paralogous loci in iTOL trees.
         *IGV genome viewer embedded in sequence bin page. 
v1.26.0: *Bookmark isolate queries.
         *Optionally log isolate deletion to a log table.
v1.25.1: *ChartDirector is no longer used - all static chart images have been 
          replaced with D3 dynamic charts.
         *Annotations can now be downloaded from sequence bin page as Genbank
          or GFF3 files.
         *Global limits for plugins can now be set in bigsdb.conf.
         *Deletion without retirement can now be disabled to ensure that
          identifiers are not re-used.
         *Memory leak fixed in PCR plugin.
v1.25.0: *Option to allow user group members to co-curate private shared data.
         *Separate load limits for web scans and offline jobs.
v1.24.1: *Support for non-optlist multivalue fields.
v1.24.0: *Support for loci containing introns. You will need to install BLAT
          and set its path in bigsdb.conf to enable this.
v1.23.6: *Use multiple threads for alignment stage for Genome Comparator, ITOL,
          and Microreact plugins.
         *Option for a curator to re-open a closed submission.
v1.23.5: *Support for only using type alleles when autotagging missing loci.
         *Fix REST OAuth calls when mounted in domain sub-directory.
         *Indicate ST in uploaded isolate submissions.
v1.23.4: *Support for option list fields with multiple values.
         *Removal of support for set-specific metadata fields - these were 
          rarely used, led to complicated and difficult to maintain code, and
          the same functionality can be achieved using alternative configs.
v1.23.3: *Add option to GenomeComparator to restore ability to re-scan genomes
          for missing loci.
v1.23.2: *GrapeTree and GenomeComparator now only scan records if <50% 
          selected loci are designated. This prevents unnecessary re-scanning
          so these jobs run much faster.
         *Plugins are now available within the curator interface.
v1.23.1: *Improved script to retrieve PubMed records from NCBI.
         *Improved FASTA export plugin. 
v1.23.0: *Automated password reset for site-wide accounts.
         *Support for grouping sparse fields by different category.
         *Validation rules to constrain field values based on value of other
          fields.
         *Asynchronous update of job viewer page.
         *Please note that the, previously optional, Perl module Time::Duration
          is now required.
v1.22.5: *Allow users to reset site passwords if they know username and E-mail.
         *Faster search for null allele designations.
         *Drag-and-drop file upload for submissions.
         *Option to retire when batch deleting isolates, profiles or alleles.
         *EAV fields now included in GrapeTree metadata output.
v1.22.4: *In silico PCR plugin.
v1.22.3: *Use standard list of country names linked to ISO 3 letter codes and
          continents. This can be set up using the 'Geocoding' link in the
          admin interface.
         *Incorporate D3 maps in to field breakdown plugin for country and
          continent.
v1.22.2: *Update of jquery-ui-multiselect. Make sure the full contents of the
          javascript and css directories are updated.
         *Fix for daylight-saving in job and API monitors.
         *Include EAV fields in data exports.
         *Added cookie notification.
v1.22.1: *Improved new allele sequence upload checking. 
v1.22.0: *Option to restrict schemes and loci to subsets of isolate records
          defined by database views.
         *Option to track maintenance tasks in jobs database and include in
          the jobs monitor.
         *REST API monitor to track hits and performance.
v1.21.3: *New GenePresence plugin using interactive pivot tables and heatmaps
          to replace the old PresenceAbsence and TagStatus plugins.
         *Job monitor page to track current running and queuing jobs. This can
          also track maintenance tasks such as autotagger.
         *Updated SplitsTree parameters in Genome Comparator to support more
          recent versions.
v1.21.2: *GrapeTree plugin now uses Genome Comparator scanner so genomes do
          not need to be fully scanned and tagged before use.
         *New export file icons.
v1.21.1: *New D3-based FieldBreakdown plugin offering dynamic charting. This
          works for provenance fields, alleles and scheme fields, so the old
          Scheme/allele breakdown plugin has been removed as it is redundant.
         *Classification groups now shown for exact matching sequence queries.
v1.21.0: *Faster clustering function.
         *Faster cache renewal.
         *Support for classification group fields.
v1.20.3: *Cache renewal fixes to prevent table locking if multiple processes
          try to renew the same cache (may happen on big schemes when the 
          renewal is run as a CRON job).
         *Sequence query update to always include classification groups if
          defined.
         *Classification groups included in profile export plugin.
v1.20.2: *Fix for bug in export plugin introduced with v1.20.1.
v1.20.1: *Improved exception handling - please note new Perl module 
          dependencies: Try::Tiny and Exception::Class.
         *Updated GrapeTree plugin reflects upstream filename and data 
          formatting changes (see attributes in bigsdb.conf to enable).
v1.20.0: *Conditional formatting for EAV fields.
         *Query classification schemes from genome sequence query.
v1.19.1: *Include EAV field in RESTful API isolate record.
         *Minor bug fixes.
v1.19.0: *Support for sparsely-populated fields - useful for storing large
          numbers of phenotypic data category values that are only available
          for a minority of isolates.
         *rMLST plugin - provide match results for each row of results.
         *Curators now allowed to curate private isolates that are part of a
          user project that they have been invited to.
v1.18.4: *Improved navigation bars.
         *New curator index page.
         *Drag and drop batch genome uploads (make sure javascript directory is
          updated).
         *Export classification groups with isolate data.
         *Update for FontAwesone 5.1 (make sure webfonts directory is updated).
v1.18.3: *Update FontAwesome to version 5. Ensure you copy the contents of the
          new webfonts directory (renamed from fonts) to the root of your web
          site and update the css directory.
         *Sequence/scheme query via RESTful API, e.g. extract MLST/cgMLST from
          local genome file via command line.
         *rMLST species identification plugin.
         *Allow upload of local user genome files for Genome Comparator 
          analysis.
v1.18.2: *New Microreact and GrapeTree plugins (ensure new images/plugins 
          directory is copied, see new bigsdb.conf settings for configuring
          GrapeTree).
v1.18.1: *Bug fix for Genome Comparator alignments using reference genome
          (bug introduced in 1.18.0).
v1.18.0: *Support for storing contigs in remote BIGSdb databases.
         *Users can request private records are made public.
v1.17.2: *Improved sequence query using exemplars and AJAX polling. This
          speeds up scanning of whole genome sized queries.
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
