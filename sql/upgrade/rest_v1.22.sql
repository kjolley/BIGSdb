CREATE UNLOGGED TABLE log (
timestamp timestamp NOT NULL,
ip_address text NOT NULL,
method text NOT NULL,
route text NOT NULL,
duration float NOT NULL
);

GRANT SELECT,UPDATE,INSERT,DELETE ON log TO apache,bigsdb;
CREATE INDEX i_l1 ON log USING brin(timestamp);
