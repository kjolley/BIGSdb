UPDATE sequences SET status='WGS: manual extract (BIGSdb)' WHERE status='WGS: manual extract';
UPDATE sequences SET status='WGS: automated extract (BIGSdb)' WHERE status='WGS: automated extract';

ALTER TABLE users ADD submission_emails boolean;

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

ALTER TABLE loci ADD complete_cds boolean;
