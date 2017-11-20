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
INSERT INTO users VALUES (-1,'autotagger','Tagger','Auto','','','curator',FALSE,FALSE,null,'now','now',0);

GRANT SELECT,UPDATE,INSERT,DELETE ON users TO apache;

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
co_curate boolean NOT NULL,
curator int NOT NULL,
PRIMARY KEY (id),
CONSTRAINT ug_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

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

CREATE TABLE user_limits (
user_id integer NOT NULL,
attribute text NOT NULL,
value integer NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (user_id,attribute),
CONSTRAINT ul_user_id FOREIGN KEY (user_id) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ul_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON user_limits TO apache;

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

CREATE TABLE isolates (
id integer NOT NULL UNIQUE,
isolate text NOT NULL,
new_version integer,
sender integer NOT NULL,
curator integer NOT NULL,
date_entered date NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT i_new_version FOREIGN KEY (new_version) REFERENCES isolates
ON DELETE NO ACTION
ON UPDATE NO ACTION,
CONSTRAINT i_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT i_sender FOREIGN KEY (sender) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

CREATE INDEX i_i1 ON isolates (datestamp);
CREATE INDEX i_i2 ON isolates(new_version);
GRANT SELECT,UPDATE,INSERT,DELETE ON isolates TO apache;

CREATE TABLE isolate_aliases (
isolate_id integer NOT NULL,
alias text NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (isolate_id,alias),
CONSTRAINT ia_isolate_id FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ia_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON isolate_aliases TO apache;

CREATE TABLE isolate_field_extended_attributes (
isolate_field text NOT NULL,
attribute text NOT NULL,
value_format text NOT NULL,
value_regex text,
description text,
length integer,
url text,
field_order integer,
datestamp date NOT NULL,
curator integer NOT NULL,
PRIMARY KEY (attribute),
CONSTRAINT ifea_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON isolate_field_extended_attributes TO apache;

CREATE TABLE isolate_value_extended_attributes (
isolate_field text NOT NULL,
attribute text NOT NULL,
field_value text NOT NULL,
value text NOT NULL,
datestamp date NOT NULL,
curator integer NOT NULL,
PRIMARY KEY (attribute,field_value),
CONSTRAINT ivea_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON isolate_value_extended_attributes TO apache;

CREATE TABLE projects (
id integer NOT NULL,
short_description text NOT NULL,
full_description text,
isolate_display boolean NOT NULL,
list boolean NOT NULL,
private boolean NOT NULL,
no_quota boolean NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT p_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON projects TO apache;

CREATE TABLE project_members (
project_id integer NOT NULL,
isolate_id integer NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (project_id,isolate_id),
CONSTRAINT pm_project FOREIGN KEY (project_id) REFERENCES projects
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pm_isolate FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pm_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON project_members TO apache;

CREATE TABLE project_users (
project_id integer NOT NULL,
user_id integer NOT NULL,
admin boolean NOT NULL,
modify boolean NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (project_id,user_id),
CONSTRAINT pu_project FOREIGN KEY (project_id) REFERENCES projects
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pu_user FOREIGN KEY (user_id) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pu_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON project_users TO apache;

CREATE TABLE project_user_groups (
project_id integer NOT NULL,
user_group integer NOT NULL,
modify boolean NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (project_id,user_group),
CONSTRAINT pug_project FOREIGN KEY (project_id) REFERENCES projects
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pug_usergroup FOREIGN KEY (user_group) REFERENCES user_groups
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pug_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON project_user_groups TO apache;

CREATE VIEW merged_project_users AS SELECT project_id,user_id,bool_or(admin) AS admin,bool_or(modify) AS modify 
FROM (SELECT project_id,user_id,admin,modify FROM project_users UNION ALL SELECT project_id,user_id,false,modify 
FROM project_user_groups AS pug LEFT JOIN user_group_members ugm ON pug.user_group=ugm.user_group) AS merged 
GROUP BY project_id,user_id;

GRANT SELECT ON merged_project_users TO apache;

CREATE TABLE private_isolates (
isolate_id integer NOT NULL,
user_id integer NOT NULL,
request_publish boolean NOT NULL DEFAULT FALSE,
datestamp date NOT NULL,
PRIMARY KEY (isolate_id),
CONSTRAINT pi_isolate_id FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pi_user_id FOREIGN KEY (user_id) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON private_isolates TO apache;

CREATE TABLE sequence_bin (
id bigserial NOT NULL UNIQUE,
isolate_id integer NOT NULL,
remote_contig boolean NOT NULL DEFAULT FALSE,
sequence text NOT NULL,
method text,
run_id text,
assembly_id text,
original_designation text,
comments text,
sender integer NOT NULL,
curator integer NOT NULL,
date_entered date NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT sb_isolate FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sb_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT sb_sender FOREIGN KEY (sender) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

CREATE INDEX i_isolate_id on sequence_bin (isolate_id);
GRANT SELECT,UPDATE,INSERT,DELETE ON sequence_bin TO apache;
GRANT USAGE,SELECT ON SEQUENCE sequence_bin_id_seq TO apache;
--Allow apache user to disable triggers on sequence_bin.
ALTER TABLE sequence_bin OWNER TO apache;

CREATE TABLE seqbin_stats (
isolate_id int NOT NULL,
contigs int NOT NULL,
total_length int NOT NULL,
PRIMARY KEY (isolate_id),
CONSTRAINT ss_isolate_id FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,INSERT,UPDATE,DELETE ON seqbin_stats TO apache;

CREATE TABLE remote_contigs (
seqbin_id bigint NOT NULL UNIQUE,
uri text NOT NULL,
length int,
checksum text,
PRIMARY KEY (seqbin_id),
CONSTRAINT rc_seqbin_id FOREIGN KEY (seqbin_id) REFERENCES sequence_bin (id)
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON remote_contigs TO apache;

CREATE OR REPLACE LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION check_sequence_bin() RETURNS TRIGGER AS $check_sequence_bin$
	BEGIN
		IF (length(NEW.sequence) = 0 AND NEW.remote_contig IS FALSE) THEN
			RAISE EXCEPTION 'sequence must be populated if remote_contig is FALSE';
		END IF;
		IF (NEW.remote_contig IS TRUE AND NOT EXISTS(SELECT * FROM remote_contigs WHERE seqbin_id=NEW.id)) THEN
			RAISE EXCEPTION 'Use add_remote_contig() function to add remote contig.';
		END IF;
		RETURN NEW;
	END; 
$check_sequence_bin$ LANGUAGE plpgsql;	

CREATE CONSTRAINT TRIGGER check_sequence_bin AFTER INSERT OR UPDATE ON sequence_bin
	DEFERRABLE
	FOR EACH ROW
	EXECUTE PROCEDURE check_sequence_bin();
	
--Function to populate remote contigs (don't populate both tables manually)
CREATE OR REPLACE FUNCTION add_remote_contig(isolate_id int, sender int, curator int, uri text) 
  RETURNS VOID AS $add_remote_contig$
	DECLARE
		v_id integer;
	BEGIN
		ALTER TABLE sequence_bin DISABLE TRIGGER check_sequence_bin;
		INSERT INTO sequence_bin(isolate_id,remote_contig,sequence,sender,curator,date_entered,datestamp) VALUES
		 (isolate_id,true,'',sender,curator,'now','now') RETURNING id INTO v_id;
		ALTER TABLE sequence_bin ENABLE TRIGGER check_sequence_bin;
		INSERT INTO remote_contigs (seqbin_id,uri) VALUES (v_id,uri);
	END 
$add_remote_contig$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_remote_contigs() RETURNS TRIGGER AS $check_remote_contigs$
	DECLARE
		old_length integer;
		new_length integer;
		delta_length integer;
		v_isolate_id integer;
	BEGIN
		IF (TG_OP = 'DELETE') THEN
			IF (EXISTS(SELECT * FROM sequence_bin WHERE (id,remote_contig)=(OLD.seqbin_id,TRUE))) THEN
				RAISE EXCEPTION 'Do not delete directly from remote_contigs table.';
			END IF;	
			IF (OLD.length IS NOT NULL) THEN
				SELECT isolate_id FROM sequence_bin WHERE id=OLD.seqbin_id INTO v_isolate_id;
				UPDATE seqbin_stats SET total_length = total_length - OLD.length WHERE isolate_id = v_isolate_id;
			END IF;
			
		ELSIF (TG_OP = 'UPDATE') THEN
			IF (OLD.length IS NOT NULL) THEN 
				old_length = OLD.length;
			ELSE
				old_length = 0;
			END IF;
			IF (NEW.length IS NOT NULL) THEN 
				new_length = NEW.length;
			ELSE
				new_length = 0;
			END IF;
			delta_length = new_length - old_length;
			IF delta_length != 0 THEN
				SELECT isolate_id FROM sequence_bin WHERE id=OLD.seqbin_id INTO v_isolate_id;
				UPDATE seqbin_stats SET total_length = total_length + delta_length WHERE isolate_id = v_isolate_id;
			END IF;
		ELSIF (TG_OP = 'INSERT') THEN
			IF (EXISTS(SELECT * FROM sequence_bin WHERE id=NEW.seqbin_id AND NOT remote_contig)) THEN
				RAISE EXCEPTION 'Do not insert directly in to remote_contigs table. Use add_remote_contig().';
			END IF;
		END IF;
		RETURN NULL;
	END
$check_remote_contigs$ LANGUAGE plpgsql;

CREATE TRIGGER check_remote_contigs AFTER INSERT OR DELETE OR UPDATE ON remote_contigs
	FOR EACH ROW
	EXECUTE PROCEDURE check_remote_contigs();

CREATE OR REPLACE FUNCTION maint_seqbin_stats() RETURNS TRIGGER AS $maint_seqbin_stats$
	DECLARE
		delta_isolate_id	 integer;
		delta_contigs		 integer;
		delta_total_length	 integer;
		remote_contig_length integer;
	BEGIN
		IF (TG_OP = 'DELETE') THEN
			PERFORM id FROM isolates WHERE id=OLD.isolate_id;
			IF NOT FOUND THEN  --The isolate record itself has been deleted.
				RETURN NULL;
			END IF;
			delta_isolate_id = OLD.isolate_id;
			delta_contigs = - 1;
			SELECT length FROM remote_contigs WHERE seqbin_id=OLD.id INTO remote_contig_length;	
			IF (remote_contig_length IS NULL) THEN
				remote_contig_length = 0;
			END IF;
			delta_total_length = - length(OLD.sequence) - remote_contig_length;	
		ELSIF (TG_OP = 'UPDATE') THEN
			delta_isolate_id = OLD.isolate_id;
			delta_total_length = length(NEW.sequence) - length(OLD.sequence);
			delta_contigs = 0;
		ELSIF (TG_OP = 'INSERT') THEN
			delta_isolate_id = NEW.isolate_id;
			delta_contigs = + 1;
			delta_total_length = + length(NEW.sequence);
		END IF;
		
		<<insert_update>>
		LOOP
			IF (TG_OP = 'DELETE') THEN
				DELETE FROM seqbin_stats WHERE isolate_id = delta_isolate_id AND contigs + delta_contigs = 0;
				EXIT insert_update WHEN found;
			END IF;
			UPDATE seqbin_stats SET contigs = contigs + delta_contigs,total_length = total_length + delta_total_length 
				WHERE isolate_id = delta_isolate_id;
			EXIT insert_update WHEN found;
			INSERT INTO seqbin_stats (isolate_id,contigs,total_length)
				VALUES (delta_isolate_id,delta_contigs,delta_total_length);
			EXIT insert_update;
		END LOOP insert_update;
	
		RETURN NULL;
	END;
$maint_seqbin_stats$ LANGUAGE plpgsql;	

CREATE TRIGGER maint_seqbin_stats AFTER INSERT OR UPDATE OR DELETE ON sequence_bin
	FOR EACH ROW
	EXECUTE PROCEDURE maint_seqbin_stats();
	
CREATE TABLE oauth_credentials (
base_uri text NOT NULL UNIQUE,
consumer_key text NOT NULL,
consumer_secret text NOT NULL,
access_token text,
access_secret text,
session_token text,
session_secret text,
curator int NOT NULL,
date_entered date NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (base_uri),
CONSTRAINT oc_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON oauth_credentials TO apache;

CREATE TABLE experiments (
id integer NOT NULL,
description text NOT NULL UNIQUE,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT e_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON experiments TO apache;

CREATE TABLE experiment_sequences (
experiment_id integer NOT NULL,
seqbin_id integer NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (experiment_id,seqbin_id),
CONSTRAINT es_experiment FOREIGN KEY (experiment_id) REFERENCES experiments
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT es_seqbin FOREIGN KEY (seqbin_id) REFERENCES sequence_bin
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT es_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON experiment_sequences TO apache;

CREATE TABLE accession (
seqbin_id integer NOT NULL,
databank text NOT NULL,
databank_id text NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (seqbin_id,databank,databank_id),
CONSTRAINT a_seqbin_id FOREIGN KEY (seqbin_id) REFERENCES sequence_bin
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT a_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON accession TO apache;

CREATE TABLE sequence_attributes (
key text NOT NULL,
type text NOT NULL,
description text,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (key),
CONSTRAINT sa_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON sequence_attributes TO apache;

CREATE TABLE sequence_attribute_values (
seqbin_id integer NOT NULL,
key text NOT NULL,
value text NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (seqbin_id,key),
CONSTRAINT sav_seqbin FOREIGN KEY (seqbin_id) REFERENCES sequence_bin
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sav_key FOREIGN KEY (key) REFERENCES sequence_attributes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sav_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON sequence_attribute_values TO apache;

CREATE TABLE refs (
isolate_id integer NOT NULL,
pubmed_id integer NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (isolate_id,pubmed_id),
CONSTRAINT r_id FOREIGN KEY (isolate_id) REFERENCES isolates 
ON DELETE CASCADE 
ON UPDATE CASCADE,
CONSTRAINT r_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE INDEX i_pmid ON refs (pubmed_id);
--CREATE INDEX i_id ON refs (isolate_id) removed as not necessary (covered by pkey index)

GRANT SELECT,UPDATE,INSERT,DELETE ON refs TO apache;

CREATE TABLE loci (
id text NOT NULL UNIQUE,
data_type text NOT NULL,
allele_id_format text NOT NULL,
allele_id_regex text,
formatted_name text,
common_name text,
formatted_common_name text,
description_url text,
length int,
length_varies boolean NOT NULL,
coding_sequence boolean NOT NULL,
genome_position int,
complete_cds boolean,
orf int,
reference_sequence text,
pcr_filter bool,
probe_filter bool,
match_longest bool,
dbase_name text,
dbase_host text,
dbase_port int,
dbase_user text,
dbase_password text,
dbase_id text,
url text,
isolate_display text NOT NULL,
main_display boolean NOT NULL,
query_field boolean NOT NULL,
analysis boolean NOT NULL,
submission_template boolean,
curator int NOT NULL,
date_entered date NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT l_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON loci TO apache;

CREATE TABLE locus_aliases (
locus text NOT NULL,
alias text NOT NULL,
use_alias boolean NOT NULL,
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

CREATE TABLE pcr (
id int NOT NULL,
description text NOT NULL,
primer1 text NOT NULL,
primer2 text NOT NULL,
min_length int,
max_length int,
max_primer_mismatch int,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT p_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON pcr TO apache;

CREATE TABLE pcr_locus (
pcr_id int NOT NULL,
locus text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (pcr_id,locus),
CONSTRAINT pl_pcr FOREIGN KEY (pcr_id) REFERENCES pcr
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pl_loci FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pl_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON pcr_locus TO apache;

CREATE TABLE probes (
id int NOT NULL,
description text NOT NULL,
sequence text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT pr_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON probes TO apache;

CREATE TABLE probe_locus (
probe_id int NOT NULL,
locus text NOT NULL,
max_distance int NOT NULL,
min_alignment int,
max_mismatch int,
max_gaps int,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (probe_id,locus),
CONSTRAINT prl_probe FOREIGN KEY (probe_id) REFERENCES probes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT prl_loci FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT prl_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON probe_locus TO apache;


CREATE TABLE allele_sequences (
id bigserial NOT NULL,
seqbin_id int NOT NULL,
locus text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
start_pos int NOT NULL,
end_pos int NOT NULL,
reverse boolean NOT NULL,
complete boolean NOT NULL,
isolate_id int NOT NULL,
PRIMARY KEY (id),
UNIQUE (seqbin_id,locus,start_pos,end_pos),
CONSTRAINT as_loci FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT as_seqbin FOREIGN KEY (seqbin_id) REFERENCES sequence_bin
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT as_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT as_isolate_id FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE
);

CREATE INDEX i_as1 ON allele_sequences (locus);
CREATE INDEX i_as2 ON allele_sequences (datestamp);
CREATE INDEX i_as3 ON allele_sequences (isolate_id);

-- Set isolate_id in allele_sequences table when adding or updating allele_sequences.
CREATE OR REPLACE FUNCTION set_allele_sequences_isolate_id_field() RETURNS TRIGGER AS $set_allele_sequences_isolate_id_field$
	DECLARE set_isolate_id integer;		
	BEGIN
		SELECT isolate_id INTO set_isolate_id FROM sequence_bin WHERE id=NEW.seqbin_id;
		NEW.isolate_id := set_isolate_id;
		RETURN NEW;
	END; 
$set_allele_sequences_isolate_id_field$ LANGUAGE plpgsql;

CREATE TRIGGER set_allele_sequences_isolate_id_field BEFORE INSERT OR UPDATE ON allele_sequences
	FOR EACH ROW
	EXECUTE PROCEDURE set_allele_sequences_isolate_id_field();
	
-- Update isolate_id in allele_sequences table after updating sequence bin record.
CREATE OR REPLACE FUNCTION set_allele_sequences_isolate_id_field2() RETURNS TRIGGER AS $set_allele_sequences_isolate_id_field2$
	BEGIN
		IF (NEW.isolate_id != OLD.isolate_id) THEN
			UPDATE allele_sequences SET isolate_id=NEW.isolate_id WHERE seqbin_id=NEW.id;
		END IF;
		RETURN NULL;
	END; 
$set_allele_sequences_isolate_id_field2$ LANGUAGE plpgsql;
	
CREATE TRIGGER set_allele_sequences_isolate_id_field2 AFTER UPDATE ON sequence_bin
	FOR EACH ROW
	EXECUTE PROCEDURE set_allele_sequences_isolate_id_field2();

GRANT SELECT,UPDATE,INSERT,DELETE ON allele_sequences TO apache;
GRANT USAGE, SELECT ON SEQUENCE allele_sequences_id_seq TO apache;

CREATE TABLE sequence_flags (
id bigint NOT NULL,
flag text NOT NULL,
datestamp date NOT NULL,
curator int NOT NULL,
PRIMARY KEY (id,flag),
CONSTRAINT sf_fkeys FOREIGN KEY(id) REFERENCES allele_sequences
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON sequence_flags TO apache;

CREATE TABLE allele_designations (
id bigserial NOT NULL,
isolate_id int NOT NULL,
locus text NOT NULL,
allele_id text NOT NULL,
sender integer NOT NULL,
status text NOT NULL,
method text NOT NULL,
curator integer NOT NULL,
date_entered date NOT NULL,
datestamp date NOT NULL,
comments text,
PRIMARY KEY (id),
UNIQUE (isolate_id,locus,allele_id),
CONSTRAINT ad_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT ad_sender FOREIGN KEY (sender) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT ad_isolate FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ad_loci FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE
);

-- Index i_ad1 (isolate_id) removed as not necessary (covered by pkey index)
-- Index i_ad2 (locus) removed as not necessary (covered by i_ad3)
CREATE INDEX i_ad3 ON allele_designations (locus,allele_id);
CREATE INDEX i_ad4 ON allele_designations (datestamp);
CREATE INDEX i_ad5 ON allele_designations (UPPER(locus));
GRANT USAGE, SELECT ON SEQUENCE allele_designations_id_seq TO apache;
GRANT SELECT,UPDATE,INSERT,DELETE ON allele_designations TO apache;

CREATE TABLE schemes (
id int NOT NULL UNIQUE,
name text NOT NULL,
description text,
allow_missing_loci boolean,
dbase_name text,
dbase_host text,
dbase_port int,
dbase_user text,
dbase_password text,
dbase_id int,
isolate_display boolean NOT NULL,
main_display boolean NOT NULL,
query_field boolean NOT NULL,
query_status boolean NOT NULL,
analysis boolean NOT NULL,
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
profile_name text,
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
description text,
type text NOT NULL,
url text,
field_order int,
primary_key boolean NOT NULL,
main_display boolean NOT NULL,
isolate_display boolean NOT NULL,
query_field boolean NOT NULL,
dropdown boolean NOT NULL,
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

CREATE TABLE composite_fields (
id text NOT NULL,
position_after text NOT NULL,
main_display boolean NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT cf_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON composite_fields TO apache;

CREATE TABLE composite_field_values (
composite_field_id text NOT NULL,
field text NOT NULL,
field_order int NOT NULL,
empty_value text,
regex text,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(composite_field_id,field_order),
CONSTRAINT cfv_composite_field_id FOREIGN KEY (composite_field_id) REFERENCES composite_fields
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cfv_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON composite_field_values TO apache;

CREATE TABLE history (
isolate_id int NOT NULL,
timestamp timestamp NOT NULL,
action text NOT NULL,
curator int NOT NULL,
PRIMARY KEY(isolate_id, timestamp),
CONSTRAINT h_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT h_isolate FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE
);

--CREATE INDEX i_h1 ON history (isolate_id) removed as not necessary (covered by pkey index)
GRANT SELECT,UPDATE,INSERT,DELETE ON history TO apache;

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

CREATE TABLE set_metadata (
set_id int NOT NULL,
metadata_id text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(set_id, metadata_id),
CONSTRAINT sm_set_id FOREIGN KEY (set_id) REFERENCES sets
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sm_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON set_metadata TO apache;

CREATE TABLE set_view (
set_id int NOT NULL,
view text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(set_id),
CONSTRAINT sv_set_id FOREIGN KEY (set_id) REFERENCES sets
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT sv_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON set_view TO apache;

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

CREATE TABLE isolate_submission_isolates (
submission_id text NOT NULL,
index int NOT NULL,
field text NOT NULL,
value text,
PRIMARY KEY(submission_id,index,field),
CONSTRAINT isi_submission_id FOREIGN KEY (submission_id) REFERENCES submissions
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON isolate_submission_isolates TO apache;

CREATE TABLE isolate_submission_field_order (
submission_id text NOT NULL,
field text NOT NULL,
index int NOT NULL,
PRIMARY KEY(submission_id,field),
CONSTRAINT isfo_submission_id FOREIGN KEY (submission_id) REFERENCES submissions
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON isolate_submission_field_order TO apache;

CREATE TABLE retired_isolates (
isolate_id int NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (isolate_id),
CONSTRAINT ri_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON retired_isolates TO apache;

CREATE OR REPLACE FUNCTION check_retired_isolates() RETURNS TRIGGER AS $check_retired_isolates$
	BEGIN
		IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
			PERFORM * FROM retired_isolates WHERE isolate_id=NEW.id;
			IF FOUND THEN 
				RAISE EXCEPTION 'Isolate id % has been retired.',NEW.id;
			END IF;
		END IF;
		RETURN NEW;
	END;
$check_retired_isolates$ LANGUAGE plpgsql;

CREATE TRIGGER check_retired_isolates AFTER INSERT OR UPDATE ON isolates
	FOR EACH ROW
	EXECUTE PROCEDURE check_retired_isolates();
	
CREATE OR REPLACE FUNCTION check_isolate_defined() RETURNS TRIGGER AS $check_isolate_defined$
	BEGIN
		IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
			PERFORM * FROM isolates WHERE id=NEW.isolate_id;
			IF FOUND THEN 
				RAISE EXCEPTION 'Isolate id % still exists - delete it before retiring.',NEW.isolate_id;
			END IF;
		END IF;
		RETURN NEW;
	END;
$check_isolate_defined$ LANGUAGE plpgsql;

CREATE TRIGGER check_isolate_defined AFTER INSERT OR UPDATE ON retired_isolates
	FOR EACH ROW
	EXECUTE PROCEDURE check_isolate_defined();

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

CREATE OR REPLACE FUNCTION create_isolate_scheme_cache(_scheme_id int,_view text,_temp_table boolean,_method text DEFAULT 'full') 
RETURNS VOID AS $$
	--_method param:
	--full (default): Recreate full cache.
	--incremental:    Only add to the cache, do not replace existing values. If cache does not already exist, a
	--                full refresh will be performed.
	--daily:          Add cache for isolates updated today.
	--daily_replace:  Replace cache for isolates updated today.
	DECLARE
		cache_table text;
		cache_table_temp text;
		scheme_table text;
		fields text[];
		loci text[];
		scheme_locus_count int;
		scheme_info RECORD;
		scheme_fields text;
		unqual_scheme_fields text;
		isolate_qry text;
		modify_qry text;
		qry text;
		isolate RECORD;
		table_type text;
	BEGIN
		EXECUTE('SELECT * FROM schemes WHERE id=$1') INTO scheme_info USING _scheme_id;
		IF (scheme_info.id IS NULL) THEN
			RAISE EXCEPTION 'Scheme % does not exist.', _scheme_id;
		END IF;
		IF _temp_table THEN
			table_type:='TEMP TABLE';
		ELSE
			table_type:='TABLE';
		END IF;
		IF _method NOT IN ('full','incremental','daily','daily_replace') THEN
			RAISE EXCEPTION 'Unrecognized method.';
		END IF;
		IF _method != 'full' AND _temp_table THEN
			RAISE EXCEPTION 'You cannot do an incremental update on a temporary table.';
		END IF;
		--Create table with a temporary name so we don't nobble cache - rename at end.
		cache_table:='temp_' || _view || '_scheme_fields_' || _scheme_id;
		IF EXISTS(SELECT * FROM information_schema.tables WHERE table_name=cache_table) THEN
			IF _method='daily_replace' THEN
				EXECUTE(FORMAT('DELETE FROM %I WHERE id IN (SELECT id FROM %I WHERE datestamp=''today'')',cache_table,_view));
			END IF;
		ELSE
			_method='full';
		END IF;
		cache_table_temp:=cache_table || floor(random()*9999999);
		scheme_table:='temp_scheme_' || _scheme_id;

		EXECUTE('SELECT ARRAY(SELECT field FROM scheme_fields WHERE scheme_id=$1 ORDER BY primary_key DESC )') 
		INTO fields USING _scheme_id;
		IF ARRAY_UPPER(fields,1) IS NULL THEN
			RAISE EXCEPTION 'Scheme has no fields.';
		END IF;
		scheme_fields:='';
		unqual_scheme_fields:='';
		
		FOR i IN 1 .. ARRAY_UPPER(fields,1) LOOP
			IF i>1 THEN 
				scheme_fields:=scheme_fields||',';
				unqual_scheme_fields:=unqual_scheme_fields||',';
			END IF;
			scheme_fields:=scheme_fields||'st.'||fields[i];
			unqual_scheme_fields:=unqual_scheme_fields||fields[i];
		END LOOP;
		IF _method='incremental' THEN
			modify_qry:=FORMAT(' AND isolate_id NOT IN (SELECT id FROM %I) ',cache_table);
		ELSIF _method='daily' OR _method='daily_replace' THEN
			modify_qry:=FORMAT(' AND isolate_id NOT IN (SELECT id FROM %I) AND isolate_id IN (SELECT id FROM %I WHERE datestamp=''today'') ',
			cache_table,_view);
		ELSE
			modify_qry:=' ';
		END IF;
		EXECUTE('CREATE TEMP TABLE ad AS SELECT isolate_id,locus,allele_id FROM allele_designations '
		|| 'WHERE locus IN (SELECT locus FROM scheme_members WHERE scheme_id=$1) AND status!=$2'||modify_qry
		|| ';CREATE INDEX ON ad(isolate_id,locus)') USING _scheme_id,'ignore';
		EXECUTE('SELECT ARRAY(SELECT locus FROM scheme_warehouse_indices WHERE scheme_id=$1 ORDER BY index)') 
		INTO loci USING _scheme_id;
		scheme_locus_count:=array_length(loci,1);
		modify_qry=regexp_replace(modify_qry,'^ AND',' WHERE');
			
		IF scheme_info.allow_missing_loci THEN
			--Schemes that allow missing values. Can't do a simple array comparison.
			isolate_qry:='CREATE TEMP TABLE temp_isolates AS SELECT DISTINCT(isolate_id) AS id FROM ad' || modify_qry;
			EXECUTE(isolate_qry);
			qry:=FORMAT('CREATE %s %s AS SELECT ti.id,%s FROM temp_isolates AS ti JOIN ad ON ti.id=ad.isolate_id JOIN %I AS st ON ',
			table_type,cache_table_temp,scheme_fields,scheme_table);
			FOR i IN 1 .. ARRAY_UPPER(loci,1) LOOP
				IF i>1 THEN
					qry:=qry||' AND ';
				END IF;
				qry:=qry||FORMAT(
				'(profile[%s]=ANY(array_append(ARRAY(SELECT allele_id FROM ad WHERE locus=''%s'' AND isolate_id=ti.id),''N'')))',
				i,replace(loci[i],'''',''''''));					
			END LOOP;
			qry:=qry||FORMAT(' GROUP BY ti.id,%s',scheme_fields);
			EXECUTE qry;	
			DROP TABLE temp_isolates;
		ELSE
			--Complete profile and only one designation per locus
			isolate_qry=FORMAT('CREATE TEMP TABLE temp_isolates AS SELECT id FROM %I JOIN ad ON %I.id=ad.isolate_id%s',_view,_view,modify_qry);
			isolate_qry:=isolate_qry||FORMAT('GROUP BY %I.id HAVING COUNT(DISTINCT(locus))=$1 AND COUNT(*)=$1',_view);
			EXECUTE(isolate_qry) USING scheme_locus_count;
			EXECUTE('CREATE TEMP TABLE temp_isolate_profiles AS SELECT id,ARRAY(SELECT ad.allele_id FROM ad '
			|| 'JOIN scheme_warehouse_indices AS sw ON ad.locus=sw.locus AND sw.scheme_id=$1 AND ad.isolate_id=temp_isolates.id '
			|| 'ORDER BY index) AS profile FROM temp_isolates') USING _scheme_id;
			EXECUTE(FORMAT('CREATE %s %s AS SELECT id,%s FROM temp_isolate_profiles AS tip JOIN %I AS st ON '
			|| 'tip.profile=st.profile',table_type,cache_table_temp,scheme_fields,scheme_table));
			DROP TABLE temp_isolates;
			DROP TABLE temp_isolate_profiles;
			
			--Profiles with more than one designation at some loci
			EXECUTE(FORMAT('CREATE TEMP TABLE temp_isolates AS SELECT id FROM %I JOIN ad ON %I.id=ad.isolate_id '
			|| '%sGROUP BY %I.id HAVING COUNT(DISTINCT(locus))=$1 AND COUNT(*)>$1',_view,_view,modify_qry,_view)) USING scheme_locus_count;
			FOR isolate IN SELECT id FROM temp_isolates LOOP
				qry:=FORMAT('SELECT %s,%s FROM %I AS st WHERE ',isolate.id,scheme_fields,scheme_table);
				FOR i IN 1 .. ARRAY_UPPER(loci,1) LOOP
					IF i>1 THEN
						qry:=qry||' AND ';
					END IF;
					qry:=qry||FORMAT('profile[%s]=ANY(ARRAY(SELECT allele_id FROM ad WHERE locus=''%s'' AND isolate_id=%s))',
					i,replace(loci[i],'''',''''''),isolate.id);					
				END LOOP;
				EXECUTE(FORMAT('INSERT INTO %I (%s)',cache_table_temp,qry));
			END LOOP;			
			DROP TABLE temp_isolates;
		END IF;
		IF _method != 'full' THEN
			EXECUTE(FORMAT('INSERT INTO %I (SELECT id,%s FROM %I)',cache_table_temp,unqual_scheme_fields,cache_table)); 
		END IF;
		EXECUTE FORMAT('CREATE INDEX on %I(id)',cache_table_temp);
		FOR i IN 1 .. ARRAY_UPPER(fields,1) LOOP
			EXECUTE FORMAT('CREATE INDEX on %I(%s)',cache_table_temp,fields[i]);
		END LOOP;
		EXECUTE FORMAT('ALTER TABLE %I OWNER TO apache', cache_table_temp);
		IF EXISTS(SELECT * FROM information_schema.tables WHERE table_name=cache_table) THEN
			EXECUTE FORMAT('DROP TABLE %I', cache_table);
		END IF;
		EXECUTE FORMAT('ALTER TABLE %I RENAME TO %s',cache_table_temp,cache_table);
		DROP TABLE ad;
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_isolate_scheme_status_table(_scheme_id int,_view text,_temp_table boolean,_method text DEFAULT 'full') 
RETURNS VOID AS $$
	--_method param:
	--full (default): Recreate full cache.
	--incremental:    Only add to the cache, do not replace existing values. If cache does not already exist, a
	--                full refresh will be performed.
	--daily:          Add cache for isolates updated today.
	--daily_replace:  Replace cache for isolates updated today.
	DECLARE
		cache_table text;
		cache_table_temp text;
		scheme_info RECORD;
		modify_qry text;
		table_type text;
	BEGIN
		EXECUTE('SELECT * FROM schemes WHERE id=$1') INTO scheme_info USING _scheme_id;
		IF (scheme_info.id IS NULL) THEN
			RAISE EXCEPTION 'Scheme % does not exist.', _scheme_id;
		END IF;
		IF _temp_table THEN
			table_type:='TEMP TABLE';
		ELSE
			table_type:='TABLE';
		END IF;
		IF _method NOT IN ('full','incremental','daily','daily_replace') THEN
			RAISE EXCEPTION 'Unrecognized method.';
		END IF;
		IF _method != 'full' AND _temp_table THEN
			RAISE EXCEPTION 'You cannot do an incremental update on a temporary table.';
		END IF;
		--Create table with a temporary name so we don't nobble cache - rename at end.
		cache_table:='temp_' || _view || '_scheme_completion_' || _scheme_id;
		IF EXISTS(SELECT * FROM information_schema.tables WHERE table_name=cache_table) THEN
			IF _method='daily_replace' THEN
				EXECUTE(FORMAT('DELETE FROM %I WHERE id IN (SELECT id FROM %I WHERE datestamp=''today'')',cache_table,_view));
			END IF;
		ELSE
			_method='full';
		END IF;
		cache_table_temp:=cache_table || floor(random()*9999999);

		IF _method='incremental' THEN
			modify_qry:=FORMAT(' AND isolate_id NOT IN (SELECT id FROM %I) ',cache_table);
		ELSIF _method='daily' OR _method='daily_replace' THEN
			modify_qry:=FORMAT(' AND isolate_id NOT IN (SELECT id FROM %I) AND isolate_id IN (SELECT id FROM %I WHERE datestamp=''today'') ',
			cache_table,_view);
		ELSE
			modify_qry:=' ';
		END IF;
		EXECUTE('CREATE TEMP TABLE ad AS SELECT isolate_id,locus,allele_id FROM allele_designations '
		|| 'WHERE locus IN (SELECT locus FROM scheme_members WHERE scheme_id=$1) AND status!=$2'||modify_qry
		|| ';CREATE INDEX ON ad(isolate_id,locus)') USING _scheme_id,'ignore';
		EXECUTE(FORMAT('CREATE %s %s AS SELECT %I.id, COUNT(DISTINCT locus) AS locus_count FROM %I JOIN ad '
		||'ON %I.id=ad.isolate_id AND locus IN (SELECT locus FROM scheme_members WHERE scheme_id=%s) GROUP BY %I.id;'
	  	,table_type,cache_table_temp,_view,_view,_view,_scheme_id,_view));

		IF _method != 'full' THEN
			EXECUTE(FORMAT('INSERT INTO %I (SELECT * FROM %I)',cache_table_temp,cache_table)); 
		END IF;
		EXECUTE FORMAT('CREATE INDEX on %I(id)',cache_table_temp);
		EXECUTE FORMAT('CREATE INDEX ON %I(locus_count)',cache_table_temp);
		EXECUTE FORMAT('ALTER TABLE %I OWNER TO apache', cache_table_temp);
		IF EXISTS(SELECT * FROM information_schema.tables WHERE table_name=cache_table) THEN
			EXECUTE FORMAT('DROP TABLE %I', cache_table);
		END IF;
		EXECUTE FORMAT('ALTER TABLE %I RENAME TO %s',cache_table_temp,cache_table);
		DROP TABLE ad;
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
seqdef_cscheme_id int,
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

GRANT SELECT,UPDATE,INSERT,DELETE ON classification_schemes TO apache;

--classification_group_fields
CREATE TABLE classification_group_fields (
cg_scheme_id int NOT NULL,
field text NOT NULL,
type text NOT NULL,
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


