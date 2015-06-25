ALTER TABLE users ADD submission_emails boolean;
ALTER TABLE loci ADD submission_template boolean;

--Add columns for MLST loci in submission template
UPDATE loci SET submission_template=TRUE WHERE id IN 
  (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT id FROM schemes WHERE description='MLST'));
--Add columns for all loci to submission template if total <= 20
UPDATE loci SET submission_template = TRUE WHERE (SELECT COUNT(*) FROM loci) <= 20;  

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

CREATE sequence sequence_bin_id_seq;
GRANT USAGE, SELECT ON SEQUENCE sequence_bin_id_seq TO apache;
ALTER TABLE sequence_bin ADD new_id bigint UNIQUE;
ALTER TABLE sequence_bin ALTER COLUMN new_id SET DEFAULT NEXTVAL('sequence_bin_id_seq');

UPDATE sequence_bin SET new_id=id;
SELECT setval('sequence_bin_id_seq', (SELECT max(id)+1 FROM sequence_bin));

ALTER TABLE accession DROP CONSTRAINT a_seqbin_id;
ALTER TABLE accession ADD CONSTRAINT a_seqbin_id FOREIGN KEY(seqbin_id) REFERENCES sequence_bin(new_id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE allele_sequences DROP CONSTRAINT as_seqbin;
ALTER TABLE allele_sequences ADD CONSTRAINT as_seqbin FOREIGN KEY(seqbin_id) REFERENCES sequence_bin(new_id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE experiment_sequences DROP CONSTRAINT es_seqbin;
ALTER TABLE experiment_sequences ADD CONSTRAINT es_seqbin FOREIGN KEY(seqbin_id) REFERENCES sequence_bin(new_id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE sequence_attribute_values DROP CONSTRAINT sav_seqbin;
ALTER TABLE sequence_attribute_values ADD CONSTRAINT sav_seqbin FOREIGN KEY(seqbin_id) REFERENCES sequence_bin(new_id) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE sequence_bin DROP CONSTRAINT sequence_bin_pkey;
ALTER TABLE sequence_bin ADD PRIMARY KEY(new_id);
ALTER TABLE sequence_bin DROP COLUMN id;
ALTER TABLE sequence_bin RENAME new_id TO id;
