ALTER TABLE projects ADD private boolean;
UPDATE projects SET private=false;
ALTER TABLE projects ALTER COLUMN private SET NOT NULL;
UPDATE projects SET isolate_display=false WHERE isolate_display IS NULL;
ALTER TABLE projects ALTER COLUMN isolate_display SET NOT NULL;
UPDATE projects SET list=false WHERE list IS NULL;
ALTER TABLE projects ALTER COLUMN list SET NOT NULL;

--Not yet added to isolatedb.sql
ALTER TABLE user_groups ADD co_curate boolean;
UPDATE user_groups SET co_curate=true;
ALTER TABLE user_groups ALTER COLUMN co_curate SET NOT NULL;

ALTER TABLE projects ADD no_quota boolean;
UPDATE projects SET no_quota=true;
ALTER TABLE projects ALTER COLUMN no_quota SET NOT NULL;

CREATE TABLE project_users (
project_id integer NOT NULL,
user_id integer NOT NULL,
admin boolean NOT NULL,
modify boolean NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (project_id,user_id),
CONSTRAINT pu_project FOREIGN KEY (project_id) REFERENCES projects
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pu_user FOREIGN KEY (user_id) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pu_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON project_users TO apache;

CREATE TABLE project_user_groups (
project_id integer NOT NULL,
user_group integer NOT NULL,
modify boolean NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (project_id,user_group),
CONSTRAINT pug_project FOREIGN KEY (project_id) REFERENCES projects
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pug_usergroup FOREIGN KEY (user_group) REFERENCES user_groups
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pug_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON project_user_groups TO apache;

CREATE VIEW merged_project_users AS SELECT project_id,user_id,bool_or(admin) AS admin,bool_or(modify) AS modify 
FROM (SELECT project_id,user_id,admin,modify FROM project_users UNION ALL SELECT project_id,user_id,false,modify 
FROM project_user_groups AS pug LEFT JOIN user_group_members ugm ON pug.user_group=ugm.user_group) AS merged 
GROUP BY project_id,user_id;

GRANT SELECT ON merged_project_users TO apache;

CREATE TABLE private_isolates (
isolate_id integer NOT NULL,
user_id INTEGER NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (isolate_id),
CONSTRAINT pi_isolate_id FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT pi_user_id FOREIGN KEY (user_id) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON private_isolates TO apache;

CREATE TABLE user_limits (
user_id integer NOT NULL,
attribute text NOT NULL,
value integer NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (user_id,attribute),
CONSTRAINT ul_user_id FOREIGN KEY (user_id) REFERENCES users
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ul_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON user_limits TO apache;

ALTER TABLE isolate_field_extended_attributes DROP CONSTRAINT isolate_field_extended_attributes_pkey;
ALTER TABLE isolate_field_extended_attributes ADD PRIMARY KEY(attribute);
ALTER TABLE isolate_value_extended_attributes DROP CONSTRAINT isolate_value_extended_attributes_pkey;
ALTER TABLE isolate_value_extended_attributes ADD PRIMARY KEY (attribute,field_value);

