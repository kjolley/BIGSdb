CREATE TABLE submissions (
id text NOT NULL,
submitter int NOT NULL,
datestamp date NOT NULL,
status text NOT NULL,
comments text,
curator int NOT NULL,
PRIMARY KEY(id),
CONSTRAINT s_submitter FOREIGN KEY (submitter) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT s_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON submissions TO apache;

CREATE TABLE allele_submissions (
submission_id text NOT NULL,
seq_id int NOT NULL,
locus text NOT NULL,
technology text NOT NULL,
read_length text NOT NULL,
coverage text NOT NULL,
sequence text NOT NULL,
assembly_method text NOT NULL,
software text,
comments text,
PRIMARY KEY(submission_id,seq_id),
CONSTRAINT as_submission_id FOREIGN KEY (submission_id) REFERENCES submissions
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT as_locus FOREIGN KEY (locus) REFERENCES loci
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON allele_submissions TO apache;

ALTER TABLE loci ADD complete_cds boolean;
