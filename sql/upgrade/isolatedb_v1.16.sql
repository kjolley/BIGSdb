CREATE TABLE user_dbases (
id int NOT NULL,
name text NOT NULL,
dbase_name text NOT NULL,
dbase_host text,
dbase_port int,
dbase_user text,
dbase_password text,
list_order int,
auto_registration boolean,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT ud_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON user_dbases TO apache;

ALTER TABLE users ADD user_db int;
ALTER TABLE users ADD CONSTRAINT u_user_db FOREIGN KEY (user_db) REFERENCES user_dbases(id) 
ON DELETE NO ACTION ON UPDATE CASCADE; 
ALTER TABLE users ALTER COLUMN surname DROP NOT NULL;
ALTER TABLE users ALTER COLUMN first_name DROP NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
ALTER TABLE users ALTER COLUMN affiliation DROP NOT NULL;
ALTER TABLE users ADD account_request_emails boolean;
UPDATE users SET account_request_emails=FALSE;
UPDATE users SET submission_emails=FALSE WHERE submission_emails IS NULL;

ALTER TABLE curator_permissions RENAME TO permissions;

UPDATE scheme_flags SET flag='please cite' where flag='citation required';

ALTER TABLE loci ADD complete_cds boolean;
