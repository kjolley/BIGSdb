CREATE UNLOGGED TABLE log (
timestamp timestamp NOT NULL,
ip_address text NOT NULL,
user_name text,
curate boolean NOT NULL,
method text NOT NULL,
dbase_config text,
page text NOT NULL
);

GRANT SELECT,UPDATE,INSERT,DELETE ON log TO apache;
CREATE INDEX l_l1 ON log USING brin(timestamp);
