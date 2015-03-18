CREATE TABLE resources (
	name text NOT NULL,
	description text NOT NULL,
	seqdef_config text,
	isolates_config text,
	PRIMARY KEY (name)
);

GRANT SELECT ON resources TO apache;
