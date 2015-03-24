CREATE TABLE resource_groups (
	name text NOT NULL,
	description text NOT NULL,
	PRIMARY KEY (name)
);

CREATE TABLE resources (
	group_name text NOT NULL,
	dbase_config text NOT NULL,
	description text NOT NULL,
	PRIMARY KEY (group_name,dbase_config)
);

GRANT SELECT ON resources,resource_groups TO apache;
