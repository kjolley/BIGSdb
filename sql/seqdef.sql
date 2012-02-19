CREATE TABLE users (
id INTEGER NOT NULL UNIQUE,
user_name text NOT NULL UNIQUE,
surname text NOT NULL,
first_name text NOT NULL,
email text NOT NULL,
affiliation text NOT NULL,
status text NOT NULL,
date_entered date NOT NULL,
datestamp date NOT NULL,
curator int NOT NULL,
PRIMARY KEY (id),
CONSTRAINT u_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

INSERT INTO users VALUES (0,'setup','','','','','user','today','today',0);

GRANT SELECT,UPDATE,INSERT,DELETE ON users TO apache;

CREATE TABLE user_permissions (
user_id integer NOT NULL,
disable_access boolean,
modify_users boolean,
modify_usergroups boolean,
set_user_passwords boolean,
set_user_permissions boolean,
modify_loci boolean,
modify_schemes boolean,
modify_sequences boolean,
modify_profiles boolean,
PRIMARY KEY (user_id),
CONSTRAINT up_user_id FOREIGN KEY (user_id) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON user_permissions TO apache;

CREATE TABLE user_groups (
id integer NOT NULL UNIQUE,
description text NOT NULL UNIQUE,
datestamp date NOT NULL,
curator int NOT NULL,
PRIMARY KEY (id),
CONSTRAINT ug_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

INSERT INTO user_groups VALUES (0,'All users','today',0);

GRANT SELECT,UPDATE,INSERT,DELETE ON user_groups TO apache;

CREATE TABLE user_group_members (
user_id integer NOT NULL,
user_group integer NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (user_id,user_group),
CONSTRAINT ugm_user_id FOREIGN KEY (user_id) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ugm_user_group FOREIGN KEY (user_group) REFERENCES user_groups
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ugm_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON user_group_members TO apache;

CREATE TABLE loci (
id text NOT NULL UNIQUE,
data_type text NOT NULL,
allele_id_format text NOT NULL,
allele_id_regex text,
common_name text,
length int,
length_varies boolean NOT NULL,
min_length int,
max_length int,
coding_sequence boolean NOT NULL,
genome_position int,
orf int,
curator int NOT NULL,
date_entered date NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT l_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON loci TO apache;

CREATE TABLE locus_extended_attributes (
locus text NOT NULL,
field text NOT NULL,
value_format text NOT NULL,
length int,
value_regex text,
description text,
option_list text,
required boolean NOT NULL,
field_order int,
datestamp date NOT NULL,
curator int NOT NULL,
PRIMARY KEY (locus,field),
CONSTRAINT lea_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT lea_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON locus_extended_attributes TO apache;

CREATE TABLE locus_curators (
locus text NOT NULL,
curator_id int NOT NULL,
hide_public bool,
PRIMARY KEY(locus,curator_id),
CONSTRAINT lc_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT lc_curator_id FOREIGN KEY (curator_id) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON locus_curators TO apache;

CREATE TABLE locus_descriptions (
locus text NOT NULL,
full_name text,
product text,
description text,
datestamp date NOT NULL,
curator int NOT NULL,
PRIMARY KEY(locus),
CONSTRAINT ld_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ld_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON locus_descriptions TO apache;

CREATE TABLE locus_links (
locus text NOT NULL,
url text NOT NULL,
description text,
link_order int,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(locus),
CONSTRAINT ll_locus FOREIGN KEY (locus) REFERENCES locus_descriptions
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ll_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON locus_links TO apache;

CREATE TABLE locus_refs (
locus text NOT NULL,
pubmed_id int NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(locus,pubmed_id),
CONSTRAINT lr_locus FOREIGN KEY (locus) REFERENCES locus_descriptions
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT lr_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON locus_refs TO apache;

CREATE TABLE locus_aliases (
locus text NOT NULL,
alias text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (locus,alias),
CONSTRAINT la_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT la_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON locus_aliases TO apache;

CREATE TABLE client_dbases (
id int NOT NULL,
name text NOT NULL,
description text NOT NULL,
dbase_name text NOT NULL,
dbase_config_name text NOT NULL,
dbase_host text,
dbase_port int,
dbase_user text,
dbase_password text,
url text,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT cd_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON client_dbases TO apache; 

CREATE TABLE client_dbase_loci (
client_dbase_id int NOT NULL,
locus text NOT NULL,
locus_alias text,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(client_dbase_id,locus),
CONSTRAINT cdl_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT cdl_client_dbase_id FOREIGN KEY (client_dbase_id) REFERENCES client_dbases
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cdl_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON client_dbase_loci TO apache;

CREATE TABLE client_dbase_loci_fields (
client_dbase_id int NOT NULL,
locus text NOT NULL,
isolate_field text NOT NULL,
allele_query bool NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(client_dbase_id,locus,isolate_field),
CONSTRAINT lcdf_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT lcdf_client_dbase_id FOREIGN KEY (client_dbase_id) REFERENCES client_dbases
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT lcdf_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON client_dbase_loci_fields TO apache;

CREATE TABLE sequences (
locus text NOT NULL,
allele_id text NOT NULL,
sequence text NOT NULL,
status text NOT NULL,
sender int NOT NULL,
curator int NOT NULL,
date_entered date NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (locus,allele_id),
CONSTRAINT seq_loci FOREIGN KEY (locus) REFERENCES loci
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT seq_sender FOREIGN KEY (sender) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT seq_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

CREATE UNIQUE INDEX i_s1 ON sequences(locus,md5(sequence));
GRANT SELECT,UPDATE,INSERT,DELETE ON sequences TO apache;

CREATE TABLE sequence_extended_attributes (
locus text NOT NULL,
field text NOT NULL,
allele_id text NOT NULL,
value text NOT NULL,
datestamp date NOT NULL,
curator int NOT NULL,
PRIMARY KEY(locus,field,allele_id),
CONSTRAINT sea_locus_field FOREIGN KEY(locus,field) REFERENCES locus_extended_attributes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sea_locus_allele_id FOREIGN KEY(locus,allele_id) REFERENCES sequences
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sea_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON sequence_extended_attributes TO apache;

CREATE TABLE schemes (
id int NOT NULL UNIQUE,
description text NOT NULL,
display_order int,
curator int NOT NULL,
date_entered date NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(id),
CONSTRAINT s_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON schemes TO apache;

CREATE TABLE scheme_members (
scheme_id int NOT NULL,
locus text NOT NULL,
field_order int,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(scheme_id,locus),
CONSTRAINT sm_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT sm_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sm_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON scheme_members TO apache;

CREATE TABLE scheme_fields (
scheme_id int NOT NULL,
field text NOT NULL,
type text NOT NULL,
value_regex text,
description text,
field_order int,
dropdown boolean NOT NULL,
primary_key boolean NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(scheme_id,field),
CONSTRAINT sf_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sf_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON scheme_fields TO apache;

CREATE TABLE scheme_curators (
scheme_id int NOT NULL,
curator_id int NOT NULL,
PRIMARY KEY(scheme_id,curator_id),
CONSTRAINT pc_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pc_curator_id FOREIGN KEY (curator_id) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON scheme_curators TO apache;

CREATE TABLE scheme_groups (
id int NOT NULL,
name text NOT NULL,
description text,
display_order int,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(id),
CONSTRAINT sg_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON scheme_groups TO apache;

CREATE TABLE scheme_group_scheme_members (
group_id int NOT NULL,
scheme_id int NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(group_id,scheme_id),
CONSTRAINT sgsm_group_id FOREIGN KEY (group_id) REFERENCES scheme_groups
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sgsm_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sgsm_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON scheme_group_scheme_members TO apache;

CREATE TABLE scheme_group_group_members (
parent_group_id int NOT NULL,
group_id int NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(parent_group_id,group_id),
CONSTRAINT sggm_parent_group_id FOREIGN KEY (parent_group_id) REFERENCES scheme_groups
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sggm_group_id FOREIGN KEY (group_id) REFERENCES scheme_groups
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sggm_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON scheme_group_group_members TO apache;

CREATE TABLE client_dbase_schemes (
client_dbase_id int NOT NULL,
scheme_id int NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (client_dbase_id,scheme_id),
CONSTRAINT cds_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT cds_client_dbase_id FOREIGN KEY (client_dbase_id) REFERENCES client_dbases
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cds_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON client_dbase_schemes TO apache;


CREATE TABLE sequence_refs (
locus text NOT NULL,
allele_id text NOT NULL,
pubmed_id integer NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (locus,allele_id,pubmed_id),
CONSTRAINT sr_locus_allele_id FOREIGN KEY (locus,allele_id) REFERENCES sequences 
ON DELETE CASCADE 
ON UPDATE CASCADE,
CONSTRAINT sr_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE INDEX i_sr1 ON sequence_refs (pubmed_id);
CREATE INDEX i_sr2 ON sequence_refs (locus,allele_id);

GRANT SELECT,UPDATE,INSERT,DELETE ON sequence_refs TO apache;

CREATE TABLE accession (
locus text NOT NULL,
allele_id text NOT NULL,
databank text NOT NULL,
databank_id text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (locus,allele_id,databank,databank_id),
CONSTRAINT a_locus_allele_id FOREIGN KEY (locus,allele_id) REFERENCES sequences 
ON DELETE CASCADE 
ON UPDATE CASCADE,
CONSTRAINT a_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE INDEX i_a1 ON accession (databank,databank_id);
CREATE INDEX i_a2 ON accession (locus,allele_id);

GRANT SELECT,UPDATE,INSERT,DELETE ON accession TO apache;

CREATE TABLE profiles (
scheme_id int NOT NULL,
profile_id text NOT NULL,
sender int NOT NULL,
curator int NOT NULL,
date_entered date NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (scheme_id, profile_id),
CONSTRAINT p_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT p_sender FOREIGN KEY (sender) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT p_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE INDEX i_p1 ON profiles ((lpad(profile_id,20,'0')));

GRANT SELECT,UPDATE,INSERT,DELETE ON profiles TO apache;

CREATE TABLE profile_members (
scheme_id int NOT NULL,
locus text NOT NULL,
profile_id text NOT NULL,
allele_id text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(scheme_id,locus,profile_id),
CONSTRAINT pm_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT pm_scheme_id_locus FOREIGN KEY (scheme_id,locus) REFERENCES scheme_members
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pm_scheme_id_profile FOREIGN KEY (scheme_id,profile_id) REFERENCES profiles
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pm_scheme_id_locus_allele_id FOREIGN KEY (locus,allele_id) REFERENCES sequences
ON DELETE NO ACTION 
ON UPDATE CASCADE
);

CREATE INDEX i_pm1 ON profile_members (scheme_id,profile_id);
CREATE INDEX i_pm2 ON profile_members (scheme_id,locus);
CREATE INDEX i_pm3 ON profile_members (scheme_id,locus,allele_id);

GRANT SELECT,UPDATE,INSERT,DELETE ON profile_members TO apache;

CREATE TABLE profile_fields (
scheme_id int NOT NULL,
scheme_field text NOT NULL,
profile_id text NOT NULL,
value text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(scheme_id,scheme_field,profile_id),
CONSTRAINT pf_scheme_id_scheme_field FOREIGN KEY (scheme_id,scheme_field) REFERENCES scheme_fields (scheme_id,field)
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sf_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT pm_scheme_id_profile FOREIGN KEY (scheme_id,profile_id) REFERENCES profiles
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE INDEX i_pf1 ON profile_fields (scheme_id,profile_id);
CREATE INDEX i_pf2 ON profile_fields (scheme_id,scheme_field);
CREATE INDEX i_pf3 ON profile_fields (scheme_id,scheme_field,value);
GRANT SELECT,UPDATE,INSERT,DELETE ON profile_fields TO apache;

CREATE TABLE profile_refs (
scheme_id int NOT NULL,
profile_id text NOT NULL,
pubmed_id integer NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (scheme_id,profile_id,pubmed_id),
CONSTRAINT pr_scheme_id_profile_id FOREIGN KEY (scheme_id,profile_id) REFERENCES profiles 
ON DELETE CASCADE 
ON UPDATE CASCADE,
CONSTRAINT pr_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE INDEX i_pr1 ON profile_refs (pubmed_id);
CREATE INDEX i_pr2 ON profile_refs (scheme_id,profile_id);
GRANT SELECT,UPDATE,INSERT,DELETE ON profile_refs TO apache;

CREATE TABLE profile_history (
scheme_id int NOT NULL,
profile_id text NOT NULL,
timestamp timestamp NOT NULL,
action text NOT NULL,
curator int NOT NULL,
PRIMARY KEY(scheme_id,profile_id,timestamp),
CONSTRAINT ph_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT ph_scheme_id_profile_id FOREIGN KEY (scheme_id,profile_id) REFERENCES profiles
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE INDEX i_ph1 ON profile_history (scheme_id,profile_id);
GRANT SELECT,UPDATE,INSERT,DELETE ON profile_history TO apache;

-- Snapshot materialized view SQL written by Jonathan Gardner
-- http://tech.jonathangardner.net/wiki/PostgreSQL/Materialized_Views

CREATE TABLE matviews (
  mv_name NAME NOT NULL PRIMARY KEY,
  v_name NAME NOT NULL,
  last_refresh TIMESTAMP WITH TIME ZONE
);
GRANT SELECT,UPDATE,INSERT,DELETE ON matviews TO apache;

CREATE OR REPLACE FUNCTION create_matview(NAME, NAME)
 RETURNS VOID
 SECURITY DEFINER
 LANGUAGE plpgsql AS '
 DECLARE
     matview ALIAS FOR $1;
     view_name ALIAS FOR $2;
     entry matviews%ROWTYPE;
 BEGIN
     SELECT * INTO entry FROM matviews WHERE mv_name = matview;
 
     IF FOUND THEN
         RAISE EXCEPTION ''Materialized view ''''%'''' already exists.'',
           matview;
     END IF;
 
     EXECUTE ''REVOKE ALL ON '' || view_name || '' FROM PUBLIC''; 
 
     EXECUTE ''GRANT SELECT ON '' || view_name || '' TO PUBLIC'';
 
     EXECUTE ''CREATE TABLE '' || matview || '' AS SELECT * FROM '' || view_name;
 
     EXECUTE ''REVOKE ALL ON '' || matview || '' FROM PUBLIC'';
 
     EXECUTE ''GRANT SELECT ON '' || matview || '' TO PUBLIC'';

     INSERT INTO matviews (mv_name, v_name, last_refresh)
       VALUES (matview, view_name, CURRENT_TIMESTAMP); 
     
     RETURN;
 END
 ';
 
ALTER FUNCTION create_matview(NAME, NAME) OWNER TO apache;
 
CREATE OR REPLACE FUNCTION drop_matview(NAME) RETURNS VOID
 SECURITY DEFINER
 LANGUAGE plpgsql AS '
 DECLARE
     matview ALIAS FOR $1;
     entry matviews%ROWTYPE;
 BEGIN
 
     SELECT * INTO entry FROM matviews WHERE mv_name = matview;
 
     IF NOT FOUND THEN
         RAISE EXCEPTION ''Materialized view % does not exist.'', matview;
     END IF;
 
     EXECUTE ''DROP TABLE '' || matview;
     DELETE FROM matviews WHERE mv_name=matview;
 
     RETURN;
 END
 ';
 
 CREATE OR REPLACE FUNCTION refresh_matview(name) RETURNS VOID
 SECURITY DEFINER
 LANGUAGE plpgsql AS '
 DECLARE 
     matview ALIAS FOR $1;
     entry matviews%ROWTYPE;
 BEGIN
 
     SELECT * INTO entry FROM matviews WHERE mv_name = matview;
 
     IF NOT FOUND THEN
         RAISE EXCEPTION ''Materialized view % does not exist.'', matview;
    END IF;

    EXECUTE ''DELETE FROM '' || matview;
    EXECUTE ''INSERT INTO '' || matview
        || '' SELECT * FROM '' || entry.v_name;

    UPDATE matviews
        SET last_refresh=CURRENT_TIMESTAMP
        WHERE mv_name=matview;

    RETURN;
END
';

