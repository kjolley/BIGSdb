CREATE TABLE users (
id integer NOT NULL UNIQUE,
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

INSERT INTO users VALUES (0,'setup','','','','','user','now','now',0);
INSERT INTO users VALUES (-1,'autotagger','Tagger','Auto','','','curator','now','now',0);

GRANT SELECT,UPDATE,INSERT,DELETE ON users TO apache;

CREATE TABLE user_permissions (
user_id integer NOT NULL,
disable_access boolean,
modify_users boolean,
modify_usergroups boolean,
set_user_passwords boolean,
modify_isolates boolean,
modify_isolates_acl boolean,
modify_projects boolean,
modify_loci boolean,
modify_schemes boolean,
modify_composites boolean,
modify_field_attributes boolean,
modify_value_attributes boolean,
modify_probes boolean,
modify_sequences boolean,
tag_sequences boolean,
designate_alleles boolean,
sample_management boolean,
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
PRIMARY KEY (isolate_field,attribute),
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
PRIMARY KEY (isolate_field,attribute,field_value),
CONSTRAINT ivea_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON isolate_value_extended_attributes TO apache;

CREATE TABLE isolate_user_acl (
isolate_id integer NOT NULL,
user_id integer NOT NULL,
read boolean NOT NULL,
write boolean NOT NULL,
PRIMARY KEY (isolate_id,user_id),
CONSTRAINT iua_isolate_id FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT iua_user_id FOREIGN KEY (user_id) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON isolate_user_acl TO apache;

CREATE TABLE isolate_usergroup_acl (
isolate_id integer NOT NULL,
user_group_id integer NOT NULL,
read boolean NOT NULL,
write boolean NOT NULL,
PRIMARY KEY (isolate_id,user_group_id),
CONSTRAINT iua2_isolate_id FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT iua2_user_group_id FOREIGN KEY (user_group_id) REFERENCES user_groups
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON isolate_usergroup_acl TO apache;

CREATE TABLE projects (
id integer NOT NULL,
short_description text NOT NULL,
full_description text,
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

CREATE TABLE sequence_bin (
id integer NOT NULL UNIQUE,
isolate_id integer NOT NULL,
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

CREATE LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION maint_seqbin_stats() RETURNS TRIGGER AS $maint_seqbin_stats$
	DECLARE
		delta_isolate_id	integer;
		delta_contigs		integer;
		delta_total_length	integer;
	BEGIN
		IF (TG_OP = 'DELETE') THEN
			PERFORM id FROM isolates WHERE id=OLD.isolate_id;
			IF NOT FOUND THEN  --The isolate record itself has been deleted.
				RETURN NULL;
			END IF;
			delta_isolate_id = OLD.isolate_id;
			delta_contigs = - 1;
			delta_total_length = - length(OLD.sequence);		
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
dbase_table text,
dbase_id_field text,
dbase_id2_field text,
dbase_id2_value text,
dbase_seq_field text,
flag_table boolean NOT NULL,
url text,
isolate_display text NOT NULL,
main_display boolean NOT NULL,
query_field boolean NOT NULL,
analysis boolean NOT NULL,
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
GRANT USAGE, SELECT ON SEQUENCE allele_designations_id_seq TO apache;
GRANT SELECT,UPDATE,INSERT,DELETE ON allele_designations TO apache;

CREATE TABLE schemes (
id int NOT NULL UNIQUE,
description text NOT NULL,
allow_missing_loci boolean,
dbase_name text,
dbase_host text,
dbase_port int,
dbase_user text,
dbase_password text,
dbase_table text,
dbase_st_field text,
dbase_st_descriptor text,
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

