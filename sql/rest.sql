CREATE TABLE groups (
	name text NOT NULL,
	description text NOT NULL,
	long_description text,
	PRIMARY KEY (name)
);

CREATE TABLE resources (
	dbase_config text NOT NULL,
	description text NOT NULL,
	PRIMARY KEY (dbase_config)
);

CREATE TABLE group_resources (
	group_name text NOT NULL,
	dbase_config text NOT NULL,
	PRIMARY KEY (group_name,dbase_config),
	CONSTRAINT gr_group_name FOREIGN KEY (group_name) REFERENCES groups
	ON DELETE NO ACTION
	ON UPDATE CASCADE,
	CONSTRAINT gr_dbase_config FOREIGN KEY (dbase_config) REFERENCES resources
	ON DELETE NO ACTION
	ON UPDATE CASCADE
);

GRANT SELECT ON groups,resources,group_resources TO apache;
