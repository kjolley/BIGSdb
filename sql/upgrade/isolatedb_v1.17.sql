ALTER TABLE projects ADD private boolean;
UPDATE projects SET private=false;
ALTER TABLE projects ALTER COLUMN private SET NOT NULL;
UPDATE projects SET isolate_display=false WHERE isolate_display IS NULL;
ALTER TABLE projects ALTER COLUMN isolate_display SET NOT NULL;
UPDATE projects SET list=false WHERE list IS NULL;
ALTER TABLE projects ALTER COLUMN list SET NOT NULL;

--Not yet added to isolatedb.sql
ALTER TABLE projects ADD

CREATE TABLE project_users (
project_id integer NOT NULL,
user_id integer NOT NULL,
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

CREATE VIEW merged_project_users AS
SELECT project_id,user_id FROM project_users UNION 
(SELECT project_id,user_id FROM project_user_groups AS pug LEFT JOIN 
user_group_members ugm ON pug.user_group=ugm.user_group);

GRANT SELECT ON merged_project_users TO apache;
