CREATE TABLE jobs (
id text NOT NULL,
dbase_config text NOT NULL,
username text,
email text,
ip_address text NOT NULL,
submit_time timestamp NOT NULL,
start_time timestamp,
stop_time timestamp,
module text NOT NULL,
status text NOT NULL,
pid integer,
cancel boolean,
percent_complete int,
stage text,
message_html text,
priority int NOT NULL,
fingerprint text,
PRIMARY KEY(id)
);

GRANT SELECT,UPDATE,INSERT,DELETE ON jobs TO apache,bigsdb;

CREATE TABLE params (
job_id text NOT NULL,
key text NOT NULL,
value text NOT NULL,
PRIMARY KEY (job_id,key),
CONSTRAINT p_job_id FOREIGN KEY (job_id) REFERENCES jobs
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON params TO apache,bigsdb;

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

CREATE TABLE profiles (
job_id text NOT NULL,
scheme_id int NOT NULL,
profile_id text NOT NULL,
PRIMARY KEY (job_id,scheme_id,profile_id),
CONSTRAINT p_job_id FOREIGN KEY (job_id) REFERENCES jobs
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON profiles TO apache,bigsdb;

CREATE TABLE output (
job_id text NOT NULL,
filename text NOT NULL,
description text NOT NULL,
PRIMARY KEY (job_id,filename),
CONSTRAINT o_job_id FOREIGN KEY (job_id) REFERENCES jobs
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON output TO apache,bigsdb;
