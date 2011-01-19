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
percent_complete int,
message_html text,
priority int NOT NULL,
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

CREATE TABLE output (
job_id text NOT NULL,
filename text NOT NULL,
description text NOT NULL,
PRIMARY KEY (job_id),
CONSTRAINT o_job_id FOREIGN KEY (job_id) REFERENCES jobs
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON output TO apache,bigsdb;
