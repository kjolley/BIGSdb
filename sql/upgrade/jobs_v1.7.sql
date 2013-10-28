ALTER TABLE jobs ADD pid integer;
ALTER TABLE jobs ADD cancel boolean;

CREATE TABLE isolates (
job_id text NOT NULL,
isolate_id int NOT NULL,
PRIMARY KEY (job_id,isolate_id),
CONSTRAINT i_job_id FOREIGN KEY (job_id) REFERENCES jobs
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON isolates TO apache,bigsdb;

CREATE TABLE loci (
job_id text NOT NULL,
locus text NOT NULL,
PRIMARY KEY (job_id,locus),
CONSTRAINT l_job_id FOREIGN KEY (job_id) REFERENCES jobs
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON loci TO apache,bigsdb;

