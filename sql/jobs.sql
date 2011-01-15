CREATE TABLE jobs (
id text NOT NULL,
dbase_config text NOT NULL,
username text,
email text,
ip_address text NOT NULL,
submit_time timestamp NOT NULL,
start_time timestamp NOT NULL,
stop_time timestamp NOT NULL,
module text NOT NULL,
function text NOT NULL,
query text,
parameters text,
status text NOT NULL,
priority int NOT NULL,
PRIMARY KEY(id)
);

GRANT SELECT,UPDATE,INSERT,DELETE ON jobs TO apache,bigsdb;
