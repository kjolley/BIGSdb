CREATE TABLE user_dbases (
id int NOT NULL,
name text NOT NULL,
dbase_name text NOT NULL,
dbase_host text,
dbase_port int,
dbase_user text,
dbase_password text,
list_order int,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT ud_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON user_dbases TO apache;

ALTER TABLE users ADD user_db int;
ALTER TABLE users ADD CONSTRAINT u_user_db FOREIGN KEY (user_db) REFERENCES user_dbases(id); 
ALTER TABLE users ALTER COLUMN surname DROP NOT NULL;
ALTER TABLE users ALTER COLUMN first_name DROP NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
ALTER TABLE users ALTER COLUMN affiliation DROP NOT NULL;
ALTER TABLE users ALTER COLUMN status DROP NOT NULL;

ALTER TABLE curator_permissions RENAME TO permissions;

