CREATE TABLE users (
id integer NOT NULL UNIQUE,
user_name text NOT NULL UNIQUE,
surname text,
first_name text,
email text,
affiliation text,
status text,
submission_emails boolean,
account_request_emails boolean,
user_db integer,
date_entered date NOT NULL,
datestamp date NOT NULL,
curator int NOT NULL,
PRIMARY KEY (id),
CONSTRAINT u_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

INSERT INTO users VALUES (0,'setup','','','','','user',FALSE,FALSE,null,'now','now',0);
INSERT INTO users VALUES (-1,'autodefiner','Definer','Auto','','','curator',FALSE,FALSE,null,'now','now',0);

GRANT SELECT,UPDATE,INSERT,DELETE ON users TO apache;

CREATE TABLE user_dbases (
id int NOT NULL,
name text NOT NULL,
dbase_name text NOT NULL,
dbase_host text,
dbase_port int,
dbase_user text,
dbase_password text,
list_order int,
auto_registration boolean,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT ud_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON user_dbases TO apache;

ALTER TABLE users ADD CONSTRAINT u_user_db FOREIGN KEY (user_db) REFERENCES user_dbases(id) 
ON DELETE NO ACTION 
ON UPDATE CASCADE; 

CREATE TABLE permissions (
user_id integer NOT NULL,
permission text NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (user_id,permission),
CONSTRAINT p_user_id FOREIGN KEY (user_id) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT p_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON permissions TO apache;

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
formatted_name text,
common_name text,
formatted_common_name text,
length int,
length_varies boolean NOT NULL,
min_length int,
max_length int,
coding_sequence boolean NOT NULL,
genome_position int,
match_longest boolean,
complete_cds boolean,
orf int,
no_submissions boolean,
id_check_type_alleles boolean,
id_check_threshold float,
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
url text,
required boolean NOT NULL,
field_order int,
main_display boolean NOT NULL,
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
ON DELETE NO ACTION
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
PRIMARY KEY(locus,url),
CONSTRAINT ll_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ll_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON locus_links TO apache;

CREATE TABLE locus_refs (
locus text NOT NULL,
pubmed_id int NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(locus,pubmed_id),
CONSTRAINT lr_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT lr_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
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
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON locus_aliases TO apache;

CREATE TABLE client_dbases (
id int NOT NULL,
name text NOT NULL,
description text NOT NULL,
dbase_name text NOT NULL,
dbase_config_name text NOT NULL,
dbase_view text,
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
comments text,
validated boolean,
exemplar boolean,
lock_exemplar boolean,
type_allele boolean,
lock_type boolean,
inferred_allele_id text,
sender int NOT NULL,
curator int NOT NULL,
date_entered date NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (locus,allele_id),
CONSTRAINT seq_loci FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT seq_inferred_allele_id FOREIGN KEY (locus,inferred_allele_id) REFERENCES sequences(locus,allele_id) 
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
CREATE INDEX i_s2 ON sequences(exemplar) WHERE exemplar;
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

CREATE TABLE allele_flags (
locus text NOT NULL,
allele_id text NOT NULL,
flag text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(locus,allele_id,flag),
CONSTRAINT af_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT af_locus_allele_id FOREIGN KEY(locus,allele_id) REFERENCES sequences
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON allele_flags TO apache;

CREATE TABLE schemes (
id int NOT NULL UNIQUE,
name text NOT NULL,
description text,
allow_missing_loci boolean,
display_order int,
display boolean,
no_submissions boolean,
disable boolean,
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
index boolean,
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

CREATE TABLE scheme_flags (
scheme_id int NOT NULL,
flag text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(scheme_id,flag),
CONSTRAINT sfl_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT sfl_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON scheme_flags TO apache;

CREATE TABLE scheme_links (
scheme_id int NOT NULL,
url text NOT NULL,
description text NOT NULL,
link_order int,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(scheme_id,url),
CONSTRAINT sli_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sli_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON scheme_links TO apache;

CREATE TABLE scheme_refs (
scheme_id int NOT NULL,
pubmed_id int NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(scheme_id,pubmed_id),
CONSTRAINT sre_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sre_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON scheme_refs TO apache;

CREATE TABLE scheme_groups (
id int NOT NULL,
name text NOT NULL,
description text,
display_order int,
seq_query boolean,
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
client_scheme_id int,
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
--CREATE INDEX i_sr2 ON sequence_refs (locus,allele_id) removed as not necessary (covered by pkey index)

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
--CREATE INDEX i_a2 ON accession (locus,allele_id) removed as not necessary (covered by pkey index)

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
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT p_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
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
--CREATE INDEX i_pm2 ON profile_members (scheme_id,locus) removed as not necessary (covered by pkey index)
CREATE INDEX i_pm3 ON profile_members (allele_id);

GRANT SELECT,UPDATE,INSERT,DELETE ON profile_members TO apache;
ALTER TABLE profile_members OWNER TO apache;

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
--CREATE INDEX i_pf2 ON profile_fields (scheme_id,scheme_field) removed as not necessary (covered by pkey index)
CREATE INDEX i_pf3 ON profile_fields (value);
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
--CREATE INDEX i_pr2 ON profile_refs (scheme_id,profile_id) removed as not necessary (covered by pkey index)
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

--CREATE INDEX i_ph1 ON profile_history (scheme_id,profile_id) removed as not necessary (covered by pkey index)
GRANT SELECT,UPDATE,INSERT,DELETE ON profile_history TO apache;

CREATE TABLE sets (
id int NOT NULL,
description text NOT NULL,
long_description text,
display_order int,
hidden boolean,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(id),
CONSTRAINT s_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON sets TO apache;

CREATE TABLE set_loci (
set_id int NOT NULL,
locus text NOT NULL,
set_name text,
formatted_set_name text,
set_common_name text,
formatted_set_common_name text,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(set_id, locus),
CONSTRAINT sl_set_id FOREIGN KEY (set_id) REFERENCES sets
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sl_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sl_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON set_loci TO apache;

CREATE TABLE set_schemes (
set_id int NOT NULL,
scheme_id int NOT NULL,
set_name text,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(set_id, scheme_id),
CONSTRAINT ss_set_id FOREIGN KEY (set_id) REFERENCES sets
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ss_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ss_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON set_schemes TO apache;

CREATE TABLE submissions (
id text NOT NULL,
type text NOT NULL,
submitter int NOT NULL,
date_submitted date NOT NULL,
datestamp date NOT NULL,
status text NOT NULL,
curator int,
outcome text,
email boolean,
PRIMARY KEY(id),
CONSTRAINT s_submitter FOREIGN KEY (submitter) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT s_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON submissions TO apache;

CREATE TABLE allele_submissions (
submission_id text NOT NULL,
locus text NOT NULL,
technology text NOT NULL,
read_length text,
coverage text,
assembly text NOT NULL,
software text NOT NULL,
PRIMARY KEY(submission_id),
CONSTRAINT as_submission_id FOREIGN KEY (submission_id) REFERENCES submissions
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT as_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON allele_submissions TO apache;

CREATE TABLE allele_submission_sequences (
submission_id text NOT NULL,
index int NOT NULL,
seq_id text NOT NULL,
sequence text NOT NULL,
status text NOT NULL,
databank text,
databank_id text,
pubmed_id int,
assigned_id text,
PRIMARY KEY(submission_id,seq_id),
CONSTRAINT ass_submission_id FOREIGN KEY (submission_id) REFERENCES allele_submissions
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON allele_submission_sequences TO apache;

CREATE TABLE messages (
submission_id text NOT NULL,
timestamp timestamptz NOT NULL,
user_id int NOT NULL,
message text NOT NULL,
PRIMARY KEY (submission_id,timestamp),
CONSTRAINT m_submission_id FOREIGN KEY (submission_id) REFERENCES submissions
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT s_user FOREIGN KEY (user_id) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON messages TO apache;

CREATE TABLE profile_submissions (
submission_id text NOT NULL,
scheme_id int NOT NULL,
PRIMARY KEY(submission_id),
CONSTRAINT as_submission_id FOREIGN KEY (submission_id) REFERENCES submissions
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ps_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON profile_submissions TO apache;

CREATE TABLE profile_submission_profiles (
submission_id text NOT NULL,
index int NOT NULL,
profile_id text NOT NULL,
status text NOT NULL,
assigned_id text,
PRIMARY KEY(submission_id,profile_id),
CONSTRAINT ass_submission_id FOREIGN KEY (submission_id) REFERENCES profile_submissions
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON profile_submission_profiles TO apache;

CREATE TABLE profile_submission_designations (
submission_id text NOT NULL,
profile_id text NOT NULL,
locus text NOT NULL,
allele_id text NOT NULL,
PRIMARY KEY(submission_id,profile_id,locus),
CONSTRAINT psd_submission_id FOREIGN KEY (submission_id,profile_id) REFERENCES profile_submission_profiles(submission_id,profile_id)
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT psd_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON profile_submission_designations TO apache;

CREATE TABLE retired_allele_ids (
locus text NOT NULL,
allele_id text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (locus, allele_id),
CONSTRAINT rai_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT rai_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON retired_allele_ids TO apache;

CREATE OR REPLACE LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION check_retired_alleles() RETURNS TRIGGER AS $check_retired_alleles$
	BEGIN
		IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
			PERFORM * FROM retired_allele_ids WHERE (locus,allele_id)=(NEW.locus,NEW.allele_id);
			IF FOUND THEN 
				RAISE EXCEPTION 'Allele id (locus=%,allele_id=%) has been retired.',NEW.locus,NEW.allele_id;
			END IF;
		END IF;
		RETURN NEW;
	END;
$check_retired_alleles$ LANGUAGE plpgsql;

CREATE TRIGGER check_retired_alleles AFTER INSERT OR UPDATE ON sequences
	FOR EACH ROW
	EXECUTE PROCEDURE check_retired_alleles();
	
CREATE OR REPLACE FUNCTION check_allele_defined() RETURNS TRIGGER AS $check_allele_defined$
	BEGIN
		IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
			PERFORM * FROM sequences WHERE (locus,allele_id)=(NEW.locus,NEW.allele_id);
			IF FOUND THEN 
				RAISE EXCEPTION 'Allele id (locus=%,allele_id=%) still exists - delete it before retiring.',NEW.locus,NEW.allele_id;
			END IF;
		END IF;
		RETURN NEW;
	END;
$check_allele_defined$ LANGUAGE plpgsql;

CREATE TRIGGER check_allele_defined AFTER INSERT OR UPDATE ON retired_allele_ids
	FOR EACH ROW
	EXECUTE PROCEDURE check_allele_defined();

CREATE TABLE locus_stats (
locus text NOT NULL,
datestamp date,
allele_count int NOT NULL,
min_length int,
max_length int,
PRIMARY KEY (locus),
CONSTRAINT ls_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON locus_stats TO apache;

-- Add new locus_stats value when creating new locus.
CREATE OR REPLACE FUNCTION add_locus_stats_record() RETURNS TRIGGER AS $add_locus_stats_record$
	BEGIN
		INSERT INTO locus_stats(locus,allele_count) VALUES (NEW.id,0);
		RETURN NULL;
	END; 
$add_locus_stats_record$ LANGUAGE plpgsql;

CREATE TRIGGER add_locus_stats_record AFTER INSERT ON loci
	FOR EACH ROW
	EXECUTE PROCEDURE add_locus_stats_record();

-- Update stats when adding or removing alleles.
CREATE OR REPLACE FUNCTION update_locus_stats() RETURNS TRIGGER AS $update_locus_stats$
	DECLARE
		current_min_length integer;
		current_max_length integer;
		current_datestamp date;
		allele_length integer;
	BEGIN
		IF (TG_OP = 'DELETE' AND OLD.allele_id NOT IN ('0','N')) THEN
			PERFORM locus FROM sequences WHERE locus=OLD.locus;
			IF NOT FOUND THEN  --There are no more alleles for this locus.
				UPDATE locus_stats SET datestamp=null,allele_count=0,min_length=null,max_length=null WHERE locus=OLD.locus;
			ELSE
				SELECT MIN(LENGTH(sequence)),MAX(LENGTH(sequence)),MAX(datestamp) INTO 
				current_min_length,current_max_length,current_datestamp FROM sequences WHERE 
				locus=OLD.locus AND allele_id NOT IN ('0','N');
				UPDATE locus_stats SET datestamp=current_datestamp,allele_count=allele_count-1,
				min_length=current_min_length,max_length=current_max_length WHERE locus=OLD.locus;
			END IF;
		ELSIF (TG_OP = 'INSERT' AND NEW.allele_id NOT IN ('0','N')) THEN
			UPDATE locus_stats SET datestamp='now',allele_count=allele_count+1 WHERE locus=NEW.locus;
			SELECT min_length,max_length INTO current_min_length,current_max_length FROM locus_stats WHERE locus=NEW.locus;
			allele_length := LENGTH(NEW.sequence);
			IF (current_min_length IS NULL OR allele_length < current_min_length) THEN
				UPDATE locus_stats SET min_length = allele_length WHERE locus=NEW.locus;
			END IF;
			IF (current_max_length IS NULL OR allele_length > current_max_length) THEN
				UPDATE locus_stats SET max_length = allele_length WHERE locus=NEW.locus;
			END IF;
		END IF;
		RETURN NULL;
	END;
$update_locus_stats$ LANGUAGE plpgsql;

CREATE TRIGGER update_locus_stats AFTER INSERT OR DELETE ON sequences
	FOR EACH ROW
	EXECUTE PROCEDURE update_locus_stats();
	
CREATE TABLE retired_profiles (
scheme_id int NOT NULL,
profile_id text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (scheme_id, profile_id),
CONSTRAINT rp_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT rp_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON retired_profiles TO apache;

CREATE OR REPLACE FUNCTION check_retired_profiles() RETURNS TRIGGER AS $check_retired_profiles$
	BEGIN
		IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
			PERFORM * FROM retired_profiles WHERE (scheme_id,profile_id)=(NEW.scheme_id,NEW.profile_id);
			IF FOUND THEN 
				RAISE EXCEPTION 'Profile id (scheme=%,profile_id=%) has been retired.',NEW.scheme_id,NEW.profile_id;
			END IF;
		END IF;
		RETURN NEW;
	END;
$check_retired_profiles$ LANGUAGE plpgsql;

CREATE TRIGGER check_retired_alleles AFTER INSERT OR UPDATE ON profiles
	FOR EACH ROW
	EXECUTE PROCEDURE check_retired_profiles();
	
CREATE OR REPLACE FUNCTION check_profile_defined() RETURNS TRIGGER AS $check_profile_defined$
	BEGIN
		IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
			PERFORM * FROM profiles WHERE (scheme_id,profile_id)=(NEW.scheme_id,NEW.profile_id);
			IF FOUND THEN 
				RAISE EXCEPTION 'Profile (scheme_id=%,profile_id=%) still exists - delete it before retiring.',NEW.scheme_id,NEW.profile_id;
			END IF;
		END IF;
		RETURN NEW;
	END;
$check_profile_defined$ LANGUAGE plpgsql;

CREATE TRIGGER check_profile_defined AFTER INSERT OR UPDATE ON retired_profiles
	FOR EACH ROW
	EXECUTE PROCEDURE check_profile_defined();
	
CREATE TABLE scheme_warehouse_indices (
scheme_id int NOT NULL,
locus text NOT NULL,
index int NOT NULL,
PRIMARY KEY (scheme_id,locus),
CONSTRAINT swi_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT swi_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON scheme_warehouse_indices TO apache;

CREATE OR REPLACE FUNCTION set_scheme_warehouse_indices(i_id int) RETURNS VOID AS $$
	DECLARE
		i int;
		x record;
	BEGIN
		DELETE FROM scheme_warehouse_indices WHERE scheme_id=i_id;
		i:=1;
		FOR x IN SELECT * FROM scheme_members WHERE scheme_id=i_id ORDER BY locus LOOP
			INSERT INTO scheme_warehouse_indices (scheme_id,locus,index) VALUES (i_id,x.locus,i);
			i:=i+1;
		END LOOP;
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION md5(text_array text []) RETURNS text AS $$
	SELECT md5(array_to_string(text_array,','));
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION create_scheme_warehouse(i_id int) RETURNS VOID AS $$
	DECLARE
		scheme_table text;
		create_command text;
		pk text;
		x RECORD;
	BEGIN
		scheme_table := 'mv_scheme_' || i_id;
		PERFORM id FROM schemes WHERE id=i_id;
		IF NOT FOUND THEN
			RAISE EXCEPTION 'Scheme % does not exist', i_id;
		END IF;
		PERFORM scheme_id FROM scheme_fields WHERE primary_key AND scheme_id=i_id;
		IF NOT FOUND THEN
			RAISE EXCEPTION 'Scheme % does not have a primary key', i_id;
		END IF;
		IF EXISTS(SELECT * FROM information_schema.tables WHERE table_name=scheme_table) THEN
			EXECUTE FORMAT('DROP TABLE %I', scheme_table);
		END IF;
		PERFORM set_scheme_warehouse_indices(i_id);
		create_command := FORMAT('CREATE TABLE %s (',scheme_table);
		FOR x IN SELECT * FROM scheme_fields WHERE scheme_id=i_id ORDER BY primary_key DESC LOOP
			create_command := FORMAT('%s %s text',create_command, x.field);
			IF x.primary_key THEN
				pk := x.field;
				create_command := create_command || ' NOT NULL';
			END IF;
			create_command := create_command || ',';
		END LOOP;
		EXECUTE FORMAT('%ssender int NOT NULL,curator int NOT NULL,date_entered date NOT NULL,'
		|| 'datestamp date NOT NULL,profile text[], PRIMARY KEY (%s))', 
		create_command, pk);
		FOR x IN SELECT * FROM scheme_fields WHERE scheme_id=i_id ORDER BY primary_key DESC LOOP
			IF x.index THEN
				EXECUTE FORMAT('CREATE INDEX ON %I(UPPER(%s))',scheme_table,x.field);
			END IF;
		END LOOP;
		EXECUTE FORMAT('CREATE UNIQUE INDEX ON %I(md5(profile))',scheme_table);
		EXECUTE FORMAT('CREATE INDEX ON %I ((profile[1]))',scheme_table);
		--We need to be able to drop and recreate as apache user.
		EXECUTE FORMAT('ALTER TABLE %I OWNER TO apache', scheme_table);
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION initiate_scheme_warehouse(i_id int)
  RETURNS void AS $$
	DECLARE
		scheme_table text;
		pk text;
		fields text[];
		locus_index int;
		array_length int;
		update_command text;
		x RECORD;
		counter int;
		prev_profile_id text;
	BEGIN
		PERFORM create_scheme_warehouse(i_id);
		scheme_table := 'mv_scheme_' || i_id;
		SELECT field INTO pk FROM scheme_fields WHERE scheme_id=i_id AND primary_key;
		EXECUTE FORMAT(
		'INSERT INTO %I (%s,sender,curator,date_entered,datestamp) '
		|| 'SELECT profile_id,sender,curator,date_entered,datestamp FROM '
		|| 'profiles WHERE scheme_id=%s',scheme_table,pk,i_id);
		FOR x IN SELECT * FROM profile_fields WHERE scheme_id=i_id AND scheme_field NOT IN 
		(SELECT field FROM scheme_fields WHERE scheme_id=i_id AND primary_key) LOOP
			EXECUTE FORMAT('UPDATE %I SET %s=$1 WHERE %s=$2',
			scheme_table,x.scheme_field,pk) USING x.value,x.profile_id;
		END LOOP;

		counter := 0;
		prev_profile_id := '';
		
		--Verifying that profiles are complete
		FOR x IN SELECT profile_id, locus FROM profile_members WHERE scheme_id=i_id ORDER BY profile_id,locus LOOP
			counter := counter + 1;
			IF (prev_profile_id != x.profile_id) THEN
				prev_profile_id = x.profile_id;
				counter := 1;
			END IF;
			SELECT index INTO locus_index FROM scheme_warehouse_indices WHERE scheme_id=i_id AND locus=x.locus;
			IF (locus_index != counter) THEN
				RAISE EXCEPTION 'Profile % is incomplete.', x.profile_id;
			END IF;		
		END LOOP;
		
		--Starting array update
		update_command := format('UPDATE %I SET profile=$1 WHERE %s=$2',scheme_table,pk);
		counter := 0;
		
		FOR x IN SELECT profile_id, array_agg(allele_id ORDER BY locus) AS profile_array FROM profile_members 
		WHERE scheme_id=i_id GROUP BY profile_id ORDER BY profile_id LOOP
			counter := counter + 1;
			EXECUTE update_command USING x.profile_array,x.profile_id;
		END LOOP;
		
		RAISE NOTICE '% profiles cached', counter;		
	END;
$$ LANGUAGE plpgsql; 

CREATE OR REPLACE FUNCTION modify_scheme() RETURNS TRIGGER AS $modify_scheme$
	DECLARE
		scheme_table text;
		i_scheme_id int;
	BEGIN		
		if (TG_OP = 'INSERT') THEN
			i_scheme_id = NEW.scheme_id;
		ELSE
			i_scheme_id = OLD.scheme_id;
		END IF;
		--Make sure scheme has a primary key and member loci	
		IF NOT EXISTS(SELECT * FROM scheme_fields WHERE scheme_id=i_scheme_id AND primary_key) 
		OR NOT EXISTS(SELECT * FROM scheme_members WHERE scheme_id=i_scheme_id) THEN	
			IF (TG_OP = 'DELETE' OR TG_OP = 'UPDATE') THEN
				scheme_table := 'mv_scheme_' || i_scheme_id;
				EXECUTE FORMAT('DROP TABLE IF EXISTS %I',scheme_table); 
				DELETE FROM scheme_warehouse_indices WHERE scheme_id=i_scheme_id;
			END IF;
			RETURN NEW;
		END IF;
		PERFORM create_scheme_warehouse(i_scheme_id);
		RETURN NEW;
	END;
$modify_scheme$ LANGUAGE plpgsql;

CREATE TRIGGER modify_scheme AFTER INSERT OR UPDATE OR DELETE ON scheme_fields
	FOR EACH ROW
	EXECUTE PROCEDURE modify_scheme();
	
CREATE TRIGGER modify_scheme AFTER INSERT OR DELETE ON scheme_members
	FOR EACH ROW
	EXECUTE PROCEDURE modify_scheme();
	
CREATE OR REPLACE FUNCTION modify_profile() RETURNS TRIGGER AS $modify_profile$
	DECLARE 
		pk text;
		scheme_table text;
	BEGIN
		IF (TG_OP = 'INSERT') THEN
			SELECT field INTO pk FROM scheme_fields WHERE scheme_id=NEW.scheme_id AND primary_key;
			scheme_table := 'mv_scheme_' || NEW.scheme_id;		
			EXECUTE FORMAT(
			'INSERT INTO %I (%s,sender,curator,date_entered,datestamp) VALUES ($1,$2,$3,$4,$5)',
			scheme_table,pk) USING 
			NEW.profile_id,NEW.sender,NEW.curator,NEW.date_entered,NEW.datestamp;
			RETURN NEW;
		END IF;
		scheme_table := 'mv_scheme_' || OLD.scheme_id;
		SELECT field INTO pk FROM scheme_fields WHERE scheme_id=OLD.scheme_id AND primary_key;
		IF (TG_OP = 'DELETE') THEN
			--If PK scheme field is deleted, this function is still triggered.
			IF (pk IS NOT NULL) THEN
				EXECUTE FORMAT('DELETE FROM %I WHERE %s=$1',scheme_table,pk) USING OLD.profile_id;
			END IF;
			RETURN OLD;
		ELSIF (TG_OP = 'UPDATE') THEN
			EXECUTE FORMAT('UPDATE %I SET (%s,sender,curator,date_entered,datestamp)=($1,$2,$3,$4,$5) WHERE %s=$6',
			scheme_table,pk,pk) USING NEW.profile_id,NEW.sender,NEW.curator,NEW.date_entered,NEW.datestamp,OLD.profile_id;
			RETURN NEW;
		END IF;
	END;
$modify_profile$ LANGUAGE plpgsql;

CREATE TRIGGER modify_profile AFTER INSERT OR DELETE OR UPDATE ON profiles
	FOR EACH ROW
	EXECUTE PROCEDURE modify_profile();

CREATE OR REPLACE FUNCTION modify_profile_field() RETURNS TRIGGER AS $modify_profile_field$
	DECLARE 
		pk text;
		scheme_table text;
	BEGIN
		IF (TG_OP = 'INSERT') THEN
			SELECT field INTO pk FROM scheme_fields WHERE scheme_id=NEW.scheme_id AND primary_key;
			IF (pk = NEW.scheme_field) THEN
				RETURN NEW;
			END IF;
			scheme_table := 'mv_scheme_' || NEW.scheme_id;		
			EXECUTE FORMAT('UPDATE %I SET %s=$1 WHERE %s=$2',scheme_table,NEW.scheme_field,pk) USING 
			NEW.value,NEW.profile_id;
			RETURN NEW;
		END IF;
		IF (pk = OLD.scheme_field) THEN
			RETURN OLD;
		END IF;
		scheme_table := 'mv_scheme_' || OLD.scheme_id;
		SELECT field INTO pk FROM scheme_fields WHERE scheme_id=OLD.scheme_id AND primary_key;
		IF (TG_OP = 'DELETE') THEN	
			--If PK scheme field is deleted, this function is still triggered.
			IF (pk IS NOT NULL) THEN
				EXECUTE FORMAT('UPDATE %I SET %s=null WHERE %s=$1',scheme_table,OLD.scheme_field,pk) USING OLD.profile_id;
			END IF;
			RETURN OLD;
		ELSIF (TG_OP = 'UPDATE') THEN
			EXECUTE FORMAT('UPDATE %I SET %s=$1 WHERE %s=$2',scheme_table,NEW.scheme_field,pk) USING 
			NEW.value,OLD.profile_id;
			RETURN NEW;
		END IF;
	END;
$modify_profile_field$ LANGUAGE plpgsql;

CREATE TRIGGER modify_profile_field AFTER INSERT OR DELETE OR UPDATE ON profile_fields
	FOR EACH ROW
	EXECUTE PROCEDURE modify_profile_field();
	
CREATE OR REPLACE FUNCTION modify_profile_member() RETURNS TRIGGER AS $modify_profile_member$
	DECLARE 
		pk text;
		scheme_table text;
		locus_index int;
	BEGIN
		SELECT field INTO pk FROM scheme_fields WHERE scheme_id=NEW.scheme_id AND primary_key;
		scheme_table := 'mv_scheme_' || NEW.scheme_id;
		SELECT index INTO locus_index FROM scheme_warehouse_indices WHERE scheme_id=NEW.scheme_id AND locus=NEW.locus;
		EXECUTE FORMAT('UPDATE %I SET profile[$1]=$2 WHERE %s=$3',scheme_table,pk) USING 
		locus_index,NEW.allele_id,NEW.profile_id;
		RETURN NEW;
	END;
$modify_profile_member$ LANGUAGE plpgsql;

CREATE TRIGGER modify_profile_member AFTER INSERT OR UPDATE ON profile_members
	FOR EACH ROW
	EXECUTE PROCEDURE modify_profile_member();
	
--Functions for profile comparison
CREATE OR REPLACE FUNCTION profile_diff(i_scheme_id int, profile_id1 text, profile_id2 text) RETURNS bigint AS $$
	SELECT COUNT(*) FROM profile_members AS p1 JOIN profile_members AS p2 ON p1.locus=p2.locus AND 
		p1.scheme_id=p2.scheme_id AND p1.scheme_id=i_scheme_id WHERE p1.profile_id=profile_id1 AND 
		p2.profile_id=profile_id2 AND p1.allele_id!=p2.allele_id AND p1.allele_id!='N' AND p2.allele_id!='N';
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION matching_profiles(i_scheme_id int, profile_id1 text, threshold int) RETURNS setof text AS $$
	SELECT p2.profile_id FROM profile_members AS p1 JOIN profile_members AS p2 ON p1.locus=p2.locus AND 
	p1.scheme_id=p2.scheme_id AND p1.scheme_id=i_scheme_id WHERE p1.profile_id=profile_id1 AND p1.profile_id!=p2.profile_id AND
	(p1.allele_id=p2.allele_id OR p1.allele_id='N' OR p2.allele_id='N') 
	GROUP BY p2.profile_id HAVING COUNT(*) >= ((SELECT COUNT(*) FROM scheme_members WHERE scheme_id=i_scheme_id)-threshold) 
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION matching_profiles_with_relative_threshold(i_scheme_id int, profile_id1 text, i_threshold int) 
RETURNS setof text AS $$
	DECLARE
		total int;
	BEGIN
		SELECT COUNT(*) INTO total FROM scheme_members WHERE scheme_id=i_scheme_id;
		CREATE TEMP TABLE loci_in_common AS SELECT p2.profile_id AS profile_id,COUNT(*) AS loci,
		COUNT(CASE WHEN p1.allele_id=p2.allele_id THEN 1 ELSE NULL END) AS matched,
		ROUND((CAST(COUNT(*) AS float)*(total-i_threshold))/total) AS threshold 
		FROM profile_members AS p1 JOIN profile_members AS p2 ON p1.locus=p2.locus AND p1.scheme_id=p2.scheme_id AND 
		p1.scheme_id=i_scheme_id WHERE p1.profile_id=profile_id1 AND p1.profile_id!=p2.profile_id AND p1.allele_id!='N' 
		AND p2.allele_id!='N' GROUP BY p2.profile_id;

		RETURN QUERY SELECT profile_id FROM loci_in_common WHERE matched>=threshold;
		DROP TABLE loci_in_common;	
	END;
$$ LANGUAGE plpgsql;

--classification_schemes
CREATE TABLE classification_schemes (
id int NOT NULL,
scheme_id int NOT NULL,
name text NOT NULL,
description text,
inclusion_threshold int NOT NULL,
use_relative_threshold boolean NOT NULL,
display_order int,
status text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(id),
CONSTRAINT cgs_scheme_id FOREIGN KEY (scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cgs_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

--Unique constraint necessary to set up foreign key on classification_group_profiles
CREATE UNIQUE INDEX ON classification_schemes(id,scheme_id);
GRANT SELECT,UPDATE,INSERT,DELETE ON classification_schemes TO apache;

--classification_groups
CREATE TABLE classification_groups (
cg_scheme_id int NOT NULL,
group_id int NOT NULL,
active boolean NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(cg_scheme_id,group_id),
CONSTRAINT cg_cg_scheme_id FOREIGN KEY (cg_scheme_id) REFERENCES classification_schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cg_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON classification_groups TO apache;

--classification_group_fields
CREATE TABLE classification_group_fields (
cg_scheme_id int NOT NULL,
field text NOT NULL,
type text NOT NULL,
value_regex text,
description text,
field_order int,
dropdown boolean NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(cg_scheme_id,field),
CONSTRAINT cgf_cg_scheme_id FOREIGN KEY (cg_scheme_id) REFERENCES classification_schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cgf_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON classification_group_fields TO apache;

--classification_group_profiles
CREATE TABLE classification_group_profiles (
cg_scheme_id int NOT NULL,
group_id int NOT NULL,
profile_id text NOT NULL,
scheme_id int NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(cg_scheme_id,group_id,profile_id),
CONSTRAINT cgp_cg_scheme_id_group_id FOREIGN KEY (cg_scheme_id,group_id) REFERENCES classification_groups
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cgp_cg_scheme_id_scheme_id FOREIGN KEY (cg_scheme_id,scheme_id) REFERENCES classification_schemes(id,scheme_id)
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cgp_scheme_id_profile_id FOREIGN KEY (scheme_id,profile_id) REFERENCES profiles
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cgp_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON classification_group_profiles TO apache;

--classification_group_profile_fields
CREATE TABLE classification_group_profile_fields (
cg_scheme_id int NOT NULL,
field text NOT NULL,
group_id int NOT NULL,
profile_id text NOT NULL,
value text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(cg_scheme_id,field,group_id,profile_id),
CONSTRAINT cgpf_cg_scheme_id_field FOREIGN KEY (cg_scheme_id,field) REFERENCES classification_group_fields
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cgpf_cg_scheme_id_group_profile_id FOREIGN KEY (cg_scheme_id,group_id,profile_id) REFERENCES classification_group_profiles
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cgpf_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON classification_group_profile_fields TO apache;

--classification_group_profile_history
CREATE TABLE classification_group_profile_history (
timestamp timestamp NOT NULL,
scheme_id int NOT NULL,
profile_id text NOT NULL,
cg_scheme_id int NOT NULL,
previous_group int NOT NULL,
comment text,
PRIMARY KEY(timestamp,scheme_id,profile_id),
CONSTRAINT cgph_cg_scheme_id_previous_group FOREIGN KEY (cg_scheme_id,previous_group) REFERENCES classification_groups(cg_scheme_id,group_id)
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cgph_scheme_id_profile_id FOREIGN KEY (scheme_id,profile_id) REFERENCES profiles
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON classification_group_profile_history TO apache;

